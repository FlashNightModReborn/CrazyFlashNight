"use strict";

const fs = require("fs");
const path = require("path");
const {
  assertExactDirectory,
  canonicalJson,
  contractFail,
  isPlainObject,
  pathInside,
  readExactRegularFile,
  sha256Text,
} = require("./evidence-artifact");

const API_VERSION = "FROZEN-v1";
const ADMISSION_STATUS = "DIAGNOSTIC_ONLY";
const FINGERPRINT_SCHEMA = "workbench-live-e2e.transitive-source-fingerprint.v1";
const SAFE_BUILTIN_NAMES = [
  "assert", "assert/strict", "async_hooks", "buffer", "child_process", "cluster", "console",
  "constants", "crypto", "dgram", "diagnostics_channel", "dns", "dns/promises", "domain",
  "events", "fs", "fs/promises", "http", "http2", "https", "net", "os", "path",
  "path/posix", "path/win32", "perf_hooks", "punycode", "querystring", "readline",
  "readline/promises", "stream", "stream/consumers", "stream/promises", "stream/web",
  "string_decoder", "sys", "timers", "timers/promises", "tls", "trace_events", "tty",
  "url", "util", "util/types", "v8", "wasi", "worker_threads", "zlib", "test",
  "test/reporters",
];
const BUILTINS = new Set(SAFE_BUILTIN_NAMES.concat(
  SAFE_BUILTIN_NAMES.map((entry) => "node:" + entry)));
const LOADER_CAPABLE_BUILTINS = new Set(["module", "node:module", "process", "node:process",
  "vm", "node:vm", "repl", "node:repl", "inspector", "node:inspector"]);

function normalizeRelative(root, filePath) {
  const resolved = path.resolve(filePath);
  if (!pathInside(root, resolved)) {
    contractFail("source_dependency_outside_root", "source_fingerprint",
      "repository source dependency escaped root", { filePath: resolved });
  }
  return path.relative(root, resolved).replace(/\\/g, "/");
}

function resolveLocalDependency(parentFile, specifier) {
  if (path.isAbsolute(specifier)) {
    contractFail("source_absolute_require_forbidden", "source_fingerprint",
      "absolute require is not a closed repository dependency", { parentFile, specifier });
  }
  const requested = path.resolve(path.dirname(parentFile), specifier);
  const candidates = [requested, requested + ".js", requested + ".json",
    path.join(requested, "index.js"), path.join(requested, "index.json")];
  const matches = candidates.filter((candidate) => {
    try {
      const stat = fs.lstatSync(candidate);
      return stat.isFile() && !stat.isSymbolicLink();
    } catch (_error) { return false; }
  });
  if (matches.length !== 1) {
    contractFail("source_local_require_unresolved", "source_fingerprint",
      "local require must resolve to one exact file", { parentFile, specifier, matches });
  }
  return path.resolve(matches[0]);
}

function codeMask(source) {
  const mask = new Uint8Array(source.length);
  let state = "code";
  let quote = null;
  let escaped = false;
  let regexClass = false;
  let regexAllowed = true;
  let templateExpressionDepth = 0;
  const expressionKeywords = new Set(["await", "case", "delete", "do", "else", "in",
    "instanceof", "new", "of", "return", "throw", "typeof", "void", "yield"]);
  for (let index = 0; index < source.length; index += 1) {
    const char = source[index];
    const next = source[index + 1];
    if (state === "line_comment") {
      if (char === "\n") { state = "code"; mask[index] = 1; }
      continue;
    }
    if (state === "block_comment") {
      if (char === "*" && next === "/") { index += 1; state = "code"; }
      continue;
    }
    if (state === "string") {
      if (escaped) { escaped = false; continue; }
      if (char === "\\") { escaped = true; continue; }
      if (char === quote) { state = "code"; quote = null; regexAllowed = false; }
      if (char === "\n") {
        contractFail("source_string_unterminated", "source_fingerprint", "unterminated string literal");
      }
      continue;
    }
    if (state === "template") {
      if (escaped) { escaped = false; continue; }
      if (char === "\\") { escaped = true; continue; }
      if (char === "`") { state = "code"; regexAllowed = false; continue; }
      if (char === "$" && next === "{") {
        index += 1;
        templateExpressionDepth = 1;
        state = "code";
        regexAllowed = true;
      }
      continue;
    }
    if (state === "regex") {
      if (char === "\n" || char === "\r") {
        contractFail("source_regex_unterminated", "source_fingerprint", "unterminated regex literal");
      }
      if (escaped) { escaped = false; continue; }
      if (char === "\\") { escaped = true; continue; }
      if (char === "[") { regexClass = true; continue; }
      if (char === "]" && regexClass) { regexClass = false; continue; }
      if (char === "/" && !regexClass) {
        while (/[A-Za-z]/.test(source[index + 1] || "")) index += 1;
        state = "code";
        regexAllowed = false;
      }
      continue;
    }
    if (/\s/.test(char)) { mask[index] = 1; continue; }
    if (templateExpressionDepth > 0 && char === "}") {
      mask[index] = 1;
      templateExpressionDepth -= 1;
      if (templateExpressionDepth === 0) {
        state = "template";
        regexAllowed = false;
      } else {
        regexAllowed = false;
      }
      continue;
    }
    if (char === "/" && next === "/") { index += 1; state = "line_comment"; continue; }
    if (char === "/" && next === "*") { index += 1; state = "block_comment"; continue; }
    if (char === "'" || char === '"') { state = "string"; quote = char; continue; }
    if (char === "`") {
      if (templateExpressionDepth > 0) {
        contractFail("source_nested_template_forbidden", "source_fingerprint",
          "nested template literals are outside the closed dependency lexer");
      }
      state = "template";
      continue;
    }
    if (char === "/" && regexAllowed) {
      state = "regex";
      regexClass = false;
      escaped = false;
      continue;
    }
    if (/[A-Za-z_$]/.test(char)) {
      let end = index + 1;
      while (/[A-Za-z0-9_$]/.test(source[end] || "")) end += 1;
      for (let cursor = index; cursor < end; cursor += 1) mask[cursor] = 1;
      regexAllowed = expressionKeywords.has(source.slice(index, end));
      index = end - 1;
      continue;
    }
    if (/[0-9]/.test(char)) {
      let end = index + 1;
      while (/[A-Za-z0-9._]/.test(source[end] || "")) end += 1;
      for (let cursor = index; cursor < end; cursor += 1) mask[cursor] = 1;
      regexAllowed = false;
      index = end - 1;
      continue;
    }
    mask[index] = 1;
    if (char === "{" && templateExpressionDepth > 0) {
      templateExpressionDepth += 1;
      regexAllowed = true;
    } else if (char === ")" || char === "]") regexAllowed = false;
    else if (char === "}") regexAllowed = true;
    else if (char === ".") regexAllowed = false;
    else if ((char === "+" || char === "-") && next === char) {
      mask[index + 1] = 1;
      if (regexAllowed) regexAllowed = true;
      else regexAllowed = false;
      index += 1;
    } else regexAllowed = true;
  }
  if (!["code", "line_comment"].includes(state) || templateExpressionDepth !== 0) {
    contractFail("source_lexical_state_invalid", "source_fingerprint",
      "source ended inside a string, comment, or template expression", { state });
  }
  return mask;
}

function isIdentifierCharacter(char) {
  return !!char && /[A-Za-z0-9_$]/.test(char);
}

function skipSpace(source, index) {
  let cursor = index;
  while (cursor < source.length && /\s/.test(source[cursor])) cursor += 1;
  return cursor;
}

function previousNonSpace(source, index) {
  let cursor = index - 1;
  while (cursor >= 0 && /\s/.test(source[cursor])) cursor -= 1;
  return cursor >= 0 ? source[cursor] : "";
}

function readIdentifier(source, index) {
  if (!/[A-Za-z_$]/.test(source[index] || "")) return null;
  let cursor = index + 1;
  while (/[A-Za-z0-9_$]/.test(source[cursor] || "")) cursor += 1;
  return { value: source.slice(index, cursor), end: cursor };
}

function assertLoaderGlobalUsage(source, mask, filePath) {
  const allowedProcessProperties = new Set(["arch", "argv", "cwd", "env", "execPath", "exit",
    "kill", "pid", "platform", "release", "stderr", "stdin", "stdout", "version", "versions"]);
  ["module", "globalThis", "global", "process"].forEach((token) => {
    for (let index = source.indexOf(token); index >= 0; index = source.indexOf(token, index + 1)) {
      if (!mask[index] || isIdentifierCharacter(source[index - 1])
          || isIdentifierCharacter(source[index + token.length])
          || previousNonSpace(source, index) === ".") continue;
      const cursor = skipSpace(source, index + token.length);
      if (source[cursor] === "[") {
        contractFail("source_dynamic_property_forbidden", "source_fingerprint",
          "computed loader-capable property access prevents a closed dependency graph",
          { filePath, token });
      }
      if (source[cursor] !== ".") {
        contractFail("source_loader_global_reference_forbidden", "source_fingerprint",
          "loader-capable globals cannot be aliased, passed, returned, or captured",
          { filePath, token, index });
      }
      const property = readIdentifier(source, skipSpace(source, cursor + 1));
      const allowed = token === "module"
        ? property && property.value === "exports"
        : token === "process" && property && allowedProcessProperties.has(property.value);
      if (!allowed) {
        contractFail("source_loader_global_property_forbidden", "source_fingerprint",
          "loader-capable global property is outside the closed allowlist",
          { filePath, token, property: property && property.value || null, index });
      }
    }
  });
}

function readQuotedLiteral(source, index) {
  const quote = source[index];
  if (quote !== "'" && quote !== '"') return null;
  let cursor = index + 1;
  let escaped = false;
  for (; cursor < source.length; cursor += 1) {
    const char = source[cursor];
    if (escaped) { escaped = false; continue; }
    if (char === "\\") { escaped = true; continue; }
    if (char === quote) break;
  }
  if (cursor >= source.length) return null;
  const raw = source.slice(index + 1, cursor);
  let value = "";
  for (let inner = 0; inner < raw.length; inner += 1) {
    if (raw[inner] !== "\\") { value += raw[inner]; continue; }
    inner += 1;
    if (inner >= raw.length || !["\\", "'", '"', "/"].includes(raw[inner])) return null;
    value += raw[inner];
  }
  return { value, end: cursor + 1 };
}

function scanLiteralRequires(source, filePath) {
  const mask = codeMask(source);
  const dependencies = [];
  for (let index = source.indexOf("\\"); index >= 0; index = source.indexOf("\\", index + 1)) {
    if (mask[index]) {
      contractFail("source_identifier_escape_forbidden", "source_fingerprint",
        "identifier escapes are outside the closed dependency lexer", { filePath, index });
    }
  }
  const forbiddenLoaderTokens = ["createRequire", "mainModule", "_load", "eval", "Function",
    "getBuiltinModule", "getOwnPropertyDescriptor", "getOwnPropertyDescriptors",
    "runInThisContext", "runInNewContext", "compileFunction"];
  forbiddenLoaderTokens.forEach((token) => {
    for (let index = source.indexOf(token); index >= 0; index = source.indexOf(token, index + 1)) {
      if (mask[index] && !isIdentifierCharacter(source[index - 1])
          && !isIdentifierCharacter(source[index + token.length])) {
        contractFail("source_dynamic_loader_forbidden", "source_fingerprint",
          "dynamic loader construct prevents a closed dependency graph", { filePath, token });
      }
    }
  });
  assertLoaderGlobalUsage(source, mask, filePath);
  for (let index = source.indexOf(".constructor"); index >= 0;
    index = source.indexOf(".constructor", index + 1)) {
    if (mask[index]) {
      contractFail("source_dynamic_loader_forbidden", "source_fingerprint",
        "constructor-based code generation is outside the closed dependency graph", { filePath });
    }
  }
  for (let index = source.indexOf("import"); index >= 0; index = source.indexOf("import", index + 1)) {
    if (mask[index] && !isIdentifierCharacter(source[index - 1])
        && !isIdentifierCharacter(source[index + 6])) {
      contractFail("source_import_unsupported", "source_fingerprint",
        "ES module import is not allowed in this CommonJS closure", { filePath });
    }
  }
  for (let index = source.indexOf("module"); index >= 0; index = source.indexOf("module", index + 1)) {
    if (!mask[index] || isIdentifierCharacter(source[index - 1])
        || isIdentifierCharacter(source[index + 6])) continue;
    const cursor = skipSpace(source, index + 6);
    if (source[cursor] === "." && source.slice(skipSpace(source, cursor + 1),
      skipSpace(source, cursor + 1) + 7) === "require") {
      contractFail("source_indirect_require_forbidden", "source_fingerprint",
        "module.require is not part of the literal dependency closure", { filePath });
    }
    if (source[cursor] === "[") {
      const literal = readQuotedLiteral(source, skipSpace(source, cursor + 1));
      if (literal && literal.value === "require") {
        contractFail("source_indirect_require_forbidden", "source_fingerprint",
          "bracketed module require is not part of the literal dependency closure", { filePath });
      }
    }
  }
  for (let index = source.indexOf("["); index >= 0; index = source.indexOf("[", index + 1)) {
    if (!mask[index]) continue;
    const literal = readQuotedLiteral(source, skipSpace(source, index + 1));
    if (literal && literal.value === "require") {
      contractFail("source_indirect_require_forbidden", "source_fingerprint",
        "bracketed require property is outside the literal dependency contract", { filePath });
    }
  }
  for (let index = source.indexOf("require"); index >= 0; index = source.indexOf("require", index + 1)) {
    if (!mask[index] || isIdentifierCharacter(source[index - 1])
        || isIdentifierCharacter(source[index + 7])) continue;
    let cursor = skipSpace(source, index + 7);
    if (source[cursor] !== "(") {
      contractFail("source_require_reference_forbidden", "source_fingerprint",
        "require may only appear as a direct literal call", { filePath, index });
    }
    cursor = skipSpace(source, cursor + 1);
    const literal = readQuotedLiteral(source, cursor);
    if (!literal) {
      contractFail("source_dynamic_require_forbidden", "source_fingerprint",
        "require argument must be one static string literal", { filePath, index });
    }
    cursor = skipSpace(source, literal.end);
    if (source[cursor] !== ")") {
      contractFail("source_require_shape_invalid", "source_fingerprint",
        "require call has unsupported extra arguments or syntax", { filePath, index });
    }
    dependencies.push(literal.value);
  }
  return dependencies;
}

function normalizeEntrypoints(root, entrypoints) {
  if (!Array.isArray(entrypoints) || entrypoints.length < 1) {
    contractFail("source_entrypoints_invalid", "source_fingerprint", "entrypoints are required");
  }
  const values = entrypoints.concat([__filename]).map((entry) => {
    const resolved = path.isAbsolute(entry) ? path.resolve(entry) : path.resolve(root, entry);
    normalizeRelative(root, resolved);
    return resolved;
  });
  return Array.from(new Set(values)).sort((left, right) => left.localeCompare(right));
}

function externalArtifactMap(root, values) {
  const map = new Map();
  (values || []).forEach((entry) => {
    if (!isPlainObject(entry) || typeof entry.specifier !== "string"
        || typeof entry.artifactPath !== "string" || map.has(entry.specifier)) {
      contractFail("source_external_artifact_invalid", "source_fingerprint",
        "external artifact declaration is malformed or duplicated");
    }
    const artifactPath = path.isAbsolute(entry.artifactPath)
      ? path.resolve(entry.artifactPath) : path.resolve(root, entry.artifactPath);
    map.set(entry.specifier, artifactPath);
  });
  return map;
}

function buildTransitiveSourceFingerprint(options) {
  const root = assertExactDirectory(path.resolve(options.root), "source_fingerprint");
  const phase = String(options.phase || "");
  if (!/^[A-Za-z0-9._~-]{1,80}$/.test(phase)) {
    contractFail("source_phase_invalid", "source_fingerprint", "source phase is not closed");
  }
  const entrypoints = normalizeEntrypoints(root, options.entrypoints);
  const externals = externalArtifactMap(root, options.externalArtifacts);
  const queue = entrypoints.slice();
  const visited = new Map();
  const builtins = new Set();
  const usedExternals = new Map();
  while (queue.length > 0) {
    const filePath = queue.shift();
    if (visited.has(filePath)) continue;
    const file = readExactRegularFile(filePath, {
      phase: "source_fingerprint", maximumBytes: 8 * 1024 * 1024,
    });
    const relativePath = normalizeRelative(root, filePath);
    let dependencies = [];
    if (path.extname(filePath).toLowerCase() === ".js") {
      dependencies = scanLiteralRequires(file.bytes.toString("utf8"), relativePath);
    } else if (path.extname(filePath).toLowerCase() !== ".json") {
      contractFail("source_extension_invalid", "source_fingerprint",
        "transitive source must be JS or JSON", { relativePath });
    }
    const localDependencies = [];
    dependencies.forEach((specifier) => {
      if (specifier.startsWith(".") || specifier.startsWith("/")) {
        const resolved = resolveLocalDependency(filePath, specifier);
        normalizeRelative(root, resolved);
        localDependencies.push(normalizeRelative(root, resolved));
        queue.push(resolved);
      } else if (LOADER_CAPABLE_BUILTINS.has(specifier)) {
        contractFail("source_loader_builtin_forbidden", "source_fingerprint",
          "loader-capable builtin is outside the closed dependency graph",
          { relativePath, specifier });
      } else if (BUILTINS.has(specifier)) {
        builtins.add(specifier.replace(/^node:/, ""));
      } else {
        const artifactPath = externals.get(specifier);
        if (!artifactPath) {
          contractFail("source_external_artifact_required", "source_fingerprint",
            "non-builtin dependency needs one explicit artifact", { relativePath, specifier });
        }
        usedExternals.set(specifier, artifactPath);
      }
    });
    visited.set(filePath, { relativePath, sha256: file.sha256, bytes: file.length,
      localDependencies: Array.from(new Set(localDependencies)).sort(),
      builtins: Array.from(new Set(dependencies.filter((entry) => BUILTINS.has(entry))
        .map((entry) => entry.replace(/^node:/, "")))).sort(),
      externals: Array.from(new Set(dependencies.filter((entry) =>
        !entry.startsWith(".") && !entry.startsWith("/") && !BUILTINS.has(entry)))).sort() });
  }
  const files = Array.from(visited.values()).sort((left, right) =>
    left.relativePath.localeCompare(right.relativePath));
  const externalArtifacts = Array.from(usedExternals.entries()).map(([specifier, artifactPath]) => {
    const file = readExactRegularFile(artifactPath, {
      phase: "source_fingerprint", maximumBytes: 64 * 1024 * 1024,
    });
    return { specifier, artifactPath: pathInside(root, artifactPath)
      ? path.relative(root, artifactPath).replace(/\\/g, "/") : path.resolve(artifactPath),
    sha256: file.sha256, bytes: file.length };
  }).sort((left, right) => left.specifier.localeCompare(right.specifier));
  if (usedExternals.size !== externals.size) {
    contractFail("source_external_artifact_unused", "source_fingerprint",
      "external artifact declaration was not reached by the dependency closure");
  }
  const payload = {
    schema: FINGERPRINT_SCHEMA,
    apiVersion: API_VERSION,
    admissionStatus: ADMISSION_STATUS,
    admissionEligible: false,
    entrypoints: entrypoints.map((entry) => normalizeRelative(root, entry)).sort(),
    files,
    builtins: Array.from(builtins).sort(),
    externalArtifacts,
  };
  const contentSha256 = sha256Text(canonicalJson(payload));
  return Object.assign({}, payload, {
    phase,
    capturedAt: options.capturedAt || new Date().toISOString(),
    contentSha256,
    phaseSha256: sha256Text(canonicalJson({ phase, contentSha256 })),
  });
}

function verifySourceFingerprint(options) {
  const fingerprint = options.fingerprint;
  if (!isPlainObject(fingerprint) || fingerprint.schema !== FINGERPRINT_SCHEMA
      || fingerprint.apiVersion !== API_VERSION || fingerprint.admissionStatus !== ADMISSION_STATUS
      || fingerprint.admissionEligible !== false || !Array.isArray(fingerprint.entrypoints)
      || !Array.isArray(fingerprint.externalArtifacts)
      || !Number.isFinite(Date.parse(fingerprint.capturedAt))
      || !/^[a-f0-9]{64}$/.test(String(fingerprint.contentSha256 || ""))
      || !/^[a-f0-9]{64}$/.test(String(fingerprint.phaseSha256 || ""))) {
    contractFail("source_fingerprint_invalid", "source_fingerprint", "source fingerprint is malformed");
  }
  const externalArtifacts = fingerprint.externalArtifacts.map((entry) => ({
    specifier: entry.specifier,
    artifactPath: path.isAbsolute(entry.artifactPath)
      ? entry.artifactPath : path.resolve(options.root, entry.artifactPath.replace(/\//g, path.sep)),
  }));
  const recomputed = buildTransitiveSourceFingerprint({
    root: options.root,
    phase: fingerprint.phase,
    capturedAt: fingerprint.capturedAt,
    entrypoints: fingerprint.entrypoints.filter((entry) =>
      path.resolve(options.root, entry.replace(/\//g, path.sep)) !== path.resolve(__filename)),
    externalArtifacts,
  });
  if (canonicalJson(recomputed) !== canonicalJson(fingerprint)) {
    contractFail("source_fingerprint_mismatch", "source_fingerprint",
      "transitive source closure or bytes changed after capture");
  }
  return fingerprint;
}

function verifySourceFingerprintPhases(options) {
  const fingerprints = Array.isArray(options.fingerprints) ? options.fingerprints : [];
  const requiredPhases = Array.from(options.requiredPhases || []);
  if (requiredPhases.length < 1 || new Set(requiredPhases).size !== requiredPhases.length
      || requiredPhases.some((phase) => !/^[A-Za-z0-9._~-]{1,80}$/.test(String(phase)))
      || fingerprints.length !== requiredPhases.length
      || new Set(fingerprints.map((entry) => entry.phase)).size !== fingerprints.length) {
    contractFail("source_phase_set_invalid", "source_fingerprint",
      "source fingerprints must cover the exact phase set");
  }
  const ordered = requiredPhases.map((phase) => {
    const matching = fingerprints.filter((entry) => entry.phase === phase);
    if (matching.length !== 1) {
      contractFail("source_phase_missing", "source_fingerprint", "required source phase is missing", { phase });
    }
    return verifySourceFingerprint({ root: options.root, fingerprint: matching[0] });
  });
  const content = new Set(ordered.map((entry) => entry.contentSha256));
  if (content.size !== 1) {
    contractFail("source_phase_drift", "source_fingerprint",
      "transitive source closure changed between execution phases");
  }
  return { phases: requiredPhases, contentSha256: ordered[0].contentSha256,
    fileCount: ordered[0].files.length };
}

module.exports = {
  API_VERSION,
  ADMISSION_STATUS,
  FINGERPRINT_SCHEMA,
  buildTransitiveSourceFingerprint,
  scanLiteralRequires,
  verifySourceFingerprint,
  verifySourceFingerprintPhases,
};
