"use strict";

// Object-only preflight: never check out, read blobs, create a destination, or
// borrow source-tree historical exceptions for this generated worktree.
const childProcess = require("child_process");
const path = require("path");
const { TextDecoder } = require("util");

const MAXIMUM_PROJECTED_PATH_LENGTH = 240; // Visible UTF-16 units; excludes NUL.
const OID_RE = /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/;

function fail(code, message, details) {
  const error = new Error(message);
  error.code = "material_shop_worktree_path_budget_" + code;
  error.phase = "materialize";
  error.details = details || {};
  throw error;
}

// Repository identity/config/index overrides can defeat -C and create an index
// outside the owned tree. Refuse them locally; never change the caller's config.
const GIT_CONTEXT_ENVIRONMENT = Object.freeze([
  "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",
  "GIT_OBJECT_DIRECTORY", "GIT_DIR", "GIT_WORK_TREE", "GIT_IMPLICIT_WORK_TREE",
  "GIT_GRAFT_FILE", "GIT_INDEX_FILE", "GIT_REPLACE_REF_BASE", "GIT_PREFIX",
  "GIT_SHALLOW_FILE", "GIT_COMMON_DIR", "GIT_NAMESPACE",
]);
function gitEnvironment() {
  const blocked = Object.keys(process.env).filter((key) =>
    GIT_CONTEXT_ENVIRONMENT.includes(key.toUpperCase()) && String(process.env[key] || "") !== "");
  if (blocked.length) {
    fail("environment", "Git context/index overrides are not admitted for an exact owned A5 worktree", {
      variableNames: blocked.slice().sort(),
    });
  }
  return Object.assign({}, process.env, { GIT_NO_REPLACE_OBJECTS: "1", GIT_NO_LAZY_FETCH: "1" });
}

function assertRelative(relativePath) {
  if (typeof relativePath !== "string" || !relativePath
      || /[\\\x00-\x1f<>:"|?*]/.test(relativePath)
      || relativePath.split("/").some((part) => !part || part === "." || part === ".."
        || /[. ]$/.test(part) || part.length > 255
        || /^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)/i.test(part))) {
    fail("invalid", "worktree path is not a safe Windows relative path", { relativePath });
  }
  // Reject lone surrogates in overlay strings; Git bytes use fatal UTF-8 below.
  for (let index = 0; index < relativePath.length; index += 1) {
    const unit = relativePath.charCodeAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const low = relativePath.charCodeAt(++index);
      if (!(low >= 0xdc00 && low <= 0xdfff)) fail("invalid", "path has invalid Unicode", { relativePath });
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      fail("invalid", "path has invalid Unicode", { relativePath });
    }
  }
  return relativePath;
}

function parseTree(bytes) {
  if (!Buffer.isBuffer(bytes) || bytes.length < 1 || bytes[bytes.length - 1] !== 0) {
    fail("incomplete", "complete non-empty NUL-terminated Git tree data is required");
  }
  let text;
  try { text = new TextDecoder("utf-8", { fatal: true }).decode(bytes); }
  catch (_) { fail("incomplete", "Git paths are not valid UTF-8"); }
  return text.slice(0, -1).split("\0").map((record) => {
    const tab = record.indexOf("\t");
    const header = record.slice(0, tab);
    const match = /^(040000|100644|100755|120000|160000) (tree|blob|commit) ([a-f0-9]{40}|[a-f0-9]{64})$/.exec(header);
    if (tab < 0 || !match || !record.slice(tab + 1)) {
      fail("incomplete", "malformed Git tree record");
    }
    const mode = match[1];
    const type = match[2];
    if (mode === "120000" || mode === "160000") {
      fail("unsupported", "symlink or gitlink materialization is not covered", {
        relativePath: record.slice(tab + 1), mode, type,
      });
    }
    if (mode === "040000" ? type !== "tree" : type !== "blob") {
      fail("incomplete", "Git mode/type disagree");
    }
    return { relativePath: record.slice(tab + 1), kind: type === "tree" ? "directory" : "file" };
  });
}

function projectPaths(destinationValue, headEntries, overlayFiles) {
  if (typeof destinationValue !== "string" || !path.isAbsolute(destinationValue)
      || !Array.isArray(headEntries) || headEntries.length < 1
      || !Array.isArray(overlayFiles) || overlayFiles.length < 1) {
    fail("invalid", "full HEAD and sealed overlay are required at an absolute destination");
  }
  const destination = path.resolve(destinationValue);
  const entries = new Map();
  function add(relativeValue, kind, origin) {
    const relativePath = assertRelative(relativeValue);
    const key = relativePath.toLowerCase();
    const prior = entries.get(key);
    if (prior && (prior.relativePath !== relativePath || prior.kind !== kind
        || origin === "head" && prior.origin === "head")) {
      fail("invalid", "worktree paths collide", { left: prior.relativePath, right: relativePath });
    }
    if (!prior) entries.set(key, { relativePath, kind, origin });
  }
  // ls-tree -r -t includes the directories as well as every leaf. Require every
  // parent in that listing, rather than silently accepting a partial tree input.
  headEntries.forEach((entry) => {
    if (!entry || !["directory", "file"].includes(entry.kind)) fail("incomplete", "invalid HEAD entry");
    add(entry.relativePath, entry.kind, "head");
  });
  headEntries.forEach((entry) => {
    const segments = entry.relativePath.split("/");
    segments.pop();
    while (segments.length) {
      const parent = entries.get(segments.join("/").toLowerCase());
      if (!parent || parent.relativePath !== segments.join("/") || parent.kind !== "directory") {
        fail("incomplete", "HEAD listing lacks an exact parent directory", { relativePath: entry.relativePath });
      }
      segments.pop();
    }
  });
  const overlaySeen = new Set();
  overlayFiles.forEach((entry) => {
    const relativePath = assertRelative(entry && entry.relativePath);
    const key = relativePath.toLowerCase();
    if (overlaySeen.has(key)) fail("invalid", "duplicate overlay path", { relativePath });
    overlaySeen.add(key);
    add(relativePath, "file", "overlay");
    const segments = relativePath.split("/");
    segments.pop();
    while (segments.length) {
      add(segments.join("/"), "directory", "overlay");
      segments.pop();
    }
  });
  let longest = null;
  entries.forEach((entry) => {
    const absolutePath = path.join(destination, ...entry.relativePath.split("/"));
    const projection = { relativePath: entry.relativePath, absolutePath,
      pathLength: absolutePath.length, kind: entry.kind, origin: entry.origin };
    if (!longest || projection.pathLength > longest.pathLength
        || projection.pathLength === longest.pathLength && projection.relativePath < longest.relativePath) {
      longest = projection;
    }
  });
  const budget = { destination, headEntryCount: headEntries.length,
    overlayFileCount: overlayFiles.length, projectedEntryCount: entries.size,
    longestRelativePath: longest.relativePath, longestAbsolutePath: longest.absolutePath,
    longestPathLength: longest.pathLength, maximumPathLength: MAXIMUM_PROJECTED_PATH_LENGTH };
  if (longest.pathLength > MAXIMUM_PROJECTED_PATH_LENGTH) {
    fail("exceeded", "full HEAD plus overlay exceeds the generated worktree path budget: relative="
      + JSON.stringify(longest.relativePath) + ", absolute=" + JSON.stringify(longest.absolutePath)
      + ", projected=" + longest.pathLength + ", maximum=" + MAXIMUM_PROJECTED_PATH_LENGTH
      + ", headEntries=" + headEntries.length + ", overlayFiles=" + overlayFiles.length, budget);
  }
  return budget;
}

function assertWorktreePathBudget(rootValue, destinationValue, scope) {
  if (!scope || !OID_RE.test(scope.head) || !Array.isArray(scope.files) || !scope.files.length) {
    fail("invalid", "full immutable HEAD and sealed overlay are required");
  }
  const root = path.resolve(rootValue);
  function git(args) {
    const result = childProcess.spawnSync("git", ["-C", root].concat(args), {
      encoding: null, windowsHide: true, maxBuffer: 64 * 1024 * 1024, timeout: 30000,
      env: Object.assign(gitEnvironment(), { GIT_OPTIONAL_LOCKS: "0" }),
    });
    if (result.error || result.status !== 0 || !Buffer.isBuffer(result.stdout)) {
      fail("incomplete", "unable to read the full immutable Git tree", {
        status: result.status, cause: result.error && result.error.message || null,
      });
    }
    return result.stdout;
  }
  const resolved = git(["rev-parse", "--verify", scope.head + "^{commit}"]).toString("ascii").trim();
  if (resolved !== scope.head) fail("incomplete", "HEAD is not the exact immutable commit");
  const entries = parseTree(git(["ls-tree", "-r", "-t", "-z", "--full-tree", scope.head]));
  return Object.assign({ head: scope.head }, projectPaths(destinationValue, entries, scope.files));
}

module.exports = { MAXIMUM_PROJECTED_PATH_LENGTH, GIT_CONTEXT_ENVIRONMENT, gitEnvironment, assertRelative,
  parseTree, projectPaths, assertWorktreePathBudget };
