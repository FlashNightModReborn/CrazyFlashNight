"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const { fail } = require("./common");

const PRODUCER_INPUTS_SCHEMA = "workbench-live-e2e.crafting.runtime-producer-inputs.v1";
const CANDIDATE_PRODUCER_SCHEMA = "workbench-live-e2e.crafting.candidate-producer-binding.v2";
const SHA256_RE = /^[A-F0-9]{64}$/;
const producerInputsCache = new Map();

const BUILD_FILES = Object.freeze([
  { role: "runtime_artifact_source", relativePath: "launcher/CRAZYFLASHER7MercenaryEmpire.csproj" },
  { role: "runtime_input_descriptor", relativePath: "config/build/runtime-inputs.v2.json" },
  { role: "runtime_producer_source", relativePath: ".gitattributes" },
  { role: "runtime_producer_source", relativePath: "launcher/build-runtime-candidate.ps1" },
  { role: "runtime_producer_source", relativePath: "launcher/native/assert-pinned-tools.bat" },
  { role: "runtime_producer_source", relativePath: "launcher/native/build-audio-v2.ps1" },
  { role: "runtime_producer_source", relativePath: "launcher/native/build.bat" },
  { role: "runtime_producer_source", relativePath: "launcher/native/bootstrap/build.bat" },
  { role: "runtime_producer_source", relativePath: "launcher/native/sol_parser/.cargo/config.toml" },
  { role: "runtime_producer_source", relativePath: "launcher/native/sol_parser/build.bat" },
  { role: "runtime_producer_source", relativePath: "tools/check-runtime-build-env.ps1" },
  { role: "runtime_producer_source", relativePath: "tools/runtime-build-v2-common.ps1" },
  { role: "runtime_toolchain_lock", relativePath: "config/build/runtime-toolchain.lock.json" },
  { role: "runtime_toolchain_lock", relativePath: "global.json" },
  { role: "runtime_toolchain_lock", relativePath: "launcher/native/sol_parser/rust-toolchain.toml" },
]);

function exactFile(root, descriptor) {
  const canonicalRoot = path.resolve(root);
  const filePath = path.resolve(canonicalRoot, descriptor.relativePath.replace(/\//g, path.sep));
  const relative = path.relative(canonicalRoot, filePath);
  if (!relative || relative.startsWith(".." + path.sep) || path.isAbsolute(relative)) {
    fail("runtime_producer_path_invalid", "production_closure",
      "runtime producer path escaped the canonical root", descriptor);
  }
  let stat;
  let real;
  try { stat = fs.lstatSync(filePath); real = fs.realpathSync.native(filePath); }
  catch (_error) {
    fail("runtime_producer_file_missing", "production_closure",
      "required runtime producer file is missing", descriptor);
  }
  if (!stat.isFile() || stat.isSymbolicLink()
      || path.resolve(real).toLowerCase() !== filePath.toLowerCase()) {
    fail("runtime_producer_file_invalid", "production_closure",
      "required runtime producer path is not one exact regular file", descriptor);
  }
  const bytes = fs.readFileSync(filePath);
  return { role: descriptor.role,
    locator: "root:" + descriptor.relativePath.replace(/\\/g, "/"),
    sha256: Evidence.sha256Bytes(bytes), bytes: bytes.length };
}

function exactText(root, relativePath, code) {
  exactFile(root, { role: "declaration", relativePath });
  try { return fs.readFileSync(path.resolve(root, relativePath.replace(/\//g, path.sep)), "utf8"); }
  catch (_error) {
    fail(code, "production_closure", "runtime producer declaration cannot be read", { relativePath });
  }
}

function safeRelativePath(value, code) {
  const normalized = String(value || "").replace(/\\/g, "/");
  if (!normalized || normalized.startsWith("/") || path.isAbsolute(normalized)
      || /(^|\/)\.\.(\/|$)/.test(normalized) || /[\t\r\n]/.test(normalized)) {
    fail(code, "production_closure", "runtime input contains an unsafe path", { value });
  }
  return normalized;
}

function readRuntimeInputConfig(root) {
  const relativePath = "config/build/runtime-inputs.v2.json";
  let value;
  try {
    value = JSON.parse(exactText(root, relativePath, "runtime_input_config_invalid")
      .replace(/^\uFEFF/, ""));
  } catch (error) {
    if (error && error.code) throw error;
    fail("runtime_input_config_invalid", "production_closure",
      "runtime-inputs.v2.json is not valid JSON", { message: error.message });
  }
  const requiredDomains = ["artifactSource", "producerRecipe", "toolchainLock"];
  if (!Evidence.isPlainObject(value) || value.schema !== "cf7-runtime-inputs.v2"
      || !Evidence.isPlainObject(value.domains) || !Evidence.isPlainObject(value.payload)
      || requiredDomains.some((name) => !Evidence.isPlainObject(value.domains[name])
        || !Array.isArray(value.domains[name].fixedFiles)
        || !Array.isArray(value.domains[name].trees))) {
    fail("runtime_input_config_invalid", "production_closure",
      "runtime producer input config is missing or unsupported");
  }
  return value;
}

function enumerateDomainFiles(root, config, domainName) {
  const domain = config.domains[domainName];
  const values = new Set();
  (domain.fixedFiles || []).forEach((entry) => values.add(
    safeRelativePath(entry, "runtime_input_config_invalid")));
  function walk(directory, base, tree) {
    fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
      const relative = (base ? base + "/" : "") + entry.name;
      const normalized = safeRelativePath(
        String(tree.path).replace(/\\/g, "/").replace(/\/$/, "") + "/" + relative,
        "runtime_input_config_invalid");
      const full = path.join(directory, entry.name);
      if (entry.isSymbolicLink()) {
        fail("runtime_input_tree_invalid", "production_closure",
          "runtime input tree contains a symbolic link", { path: normalized });
      }
      if (entry.isDirectory()) { walk(full, relative, tree); return; }
      if (!entry.isFile()) return;
      const extensions = (tree.includeExtensions || [])
        .map((value) => String(value).toLowerCase());
      if (extensions.length && !extensions.includes(path.extname(normalized).toLowerCase())) return;
      const excludes = (tree.excludePaths || []).map((value) =>
        safeRelativePath(value, "runtime_input_config_invalid"));
      const prefixes = (tree.excludePrefixes || []).map((value) =>
        safeRelativePath(value, "runtime_input_config_invalid"));
      if (excludes.includes(normalized) || prefixes.some((prefix) => normalized.startsWith(prefix))) return;
      values.add(normalized);
    });
  }
  (domain.trees || []).forEach((tree) => {
    if (!Evidence.isPlainObject(tree)) {
      fail("runtime_input_config_invalid", "production_closure",
        "runtime input tree declaration is malformed", { domainName });
    }
    const baseRelative = safeRelativePath(tree.path, "runtime_input_config_invalid");
    const base = path.resolve(root, baseRelative.replace(/\//g, path.sep));
    let stat;
    try { stat = fs.lstatSync(base); } catch (_error) { stat = null; }
    if (!stat || !stat.isDirectory() || stat.isSymbolicLink()) {
      fail("runtime_input_tree_invalid", "production_closure",
        "runtime producer input tree is missing or indirect", { path: baseRelative });
    }
    walk(base, "", tree);
  });
  return Array.from(values).sort();
}

function normalizedPayloadConfig(config) {
  const payload = config.payload;
  if (!Array.isArray(payload.fixedRoots) || !Array.isArray(payload.trees)
      || !Array.isArray(payload.excludePaths) || !Array.isArray(payload.excludePrefixes)) {
    fail("runtime_input_config_invalid", "production_closure",
      "runtime payload input config is incomplete");
  }
  return {
    fixedRoots: payload.fixedRoots.map((entry) => safeRelativePath(entry,
      "runtime_input_config_invalid")),
    trees: payload.trees.map((entry) => safeRelativePath(entry,
      "runtime_input_config_invalid").replace(/\/$/, "")),
    excludePaths: payload.excludePaths.map((entry) => safeRelativePath(entry,
      "runtime_input_config_invalid")),
    excludePrefixes: payload.excludePrefixes.map((entry) => safeRelativePath(entry,
      "runtime_input_config_invalid")),
  };
}

function validateProducerInputsEnvelope(value, expectedRoot) {
  const domainNames = ["artifactSource", "producerRecipe", "toolchainLock"];
  if (!Evidence.isPlainObject(value) || value.schema !== PRODUCER_INPUTS_SCHEMA
      || path.resolve(value.root || "").toLowerCase() !== path.resolve(expectedRoot).toLowerCase()
      || !Evidence.isPlainObject(value.config)
      || value.config.role !== "runtime_input_descriptor"
      || value.config.locator !== "root:config/build/runtime-inputs.v2.json"
      || !/^[a-f0-9]{64}$/.test(String(value.config.sha256 || ""))
      || !Number.isInteger(value.config.bytes) || value.config.bytes < 1
      || !Evidence.isPlainObject(value.domains)
      || Evidence.canonicalJson(Object.keys(value.domains).sort())
        !== Evidence.canonicalJson(domainNames.slice().sort())
      || !Evidence.isPlainObject(value.payload)
      || Evidence.canonicalJson(Object.keys(value.payload).sort())
        !== Evidence.canonicalJson(["excludePaths", "excludePrefixes", "fixedRoots", "trees"])
      || !SHA256_RE.test(String(value.buildIdentityHash || ""))
      || !/^[a-f0-9]{64}$/.test(String(value.inputsSha256 || ""))) {
    fail("runtime_producer_inputs_invalid", "production_closure",
      "runtime producer input envelope is malformed");
  }
  domainNames.forEach((name) => {
    const domain = value.domains[name];
    if (!Evidence.isPlainObject(domain)
        || Evidence.canonicalJson(Object.keys(domain).sort())
          !== Evidence.canonicalJson(["fileCount", "files", "fingerprintSha256", "hash"])
        || !SHA256_RE.test(String(domain.hash || ""))
        || !/^[a-f0-9]{64}$/.test(String(domain.fingerprintSha256 || ""))
        || !Array.isArray(domain.files) || domain.fileCount !== domain.files.length
        || domain.files.length < 1) {
      fail("runtime_producer_inputs_invalid", "production_closure",
        "runtime producer input domain is malformed", { name });
    }
    const paths = domain.files.map((entry) => entry && entry.relativePath);
    if (new Set(paths).size !== paths.length
        || Evidence.canonicalJson(paths) !== Evidence.canonicalJson(paths.slice().sort())
        || domain.files.some((entry) => !Evidence.isPlainObject(entry)
          || Evidence.canonicalJson(Object.keys(entry).sort())
            !== Evidence.canonicalJson(["bytes", "relativePath", "sha256"])
          || safeRelativePath(entry.relativePath, "runtime_producer_inputs_invalid")
            !== entry.relativePath
          || !/^[a-f0-9]{64}$/.test(String(entry.sha256 || ""))
          || !Number.isInteger(entry.bytes) || entry.bytes < 1)
        || domain.fingerprintSha256 !== Evidence.sha256Text(
          Evidence.canonicalJson(domain.files))) {
      fail("runtime_producer_inputs_invalid", "production_closure",
        "runtime producer input file inventory is malformed", { name });
    }
  });
  ["fixedRoots", "trees", "excludePaths", "excludePrefixes"].forEach((name) => {
    const values = value.payload[name];
    if (!Array.isArray(values) || new Set(values).size !== values.length
        || values.some((entry) => typeof entry !== "string"
          || safeRelativePath(entry, "runtime_producer_inputs_invalid") !== entry)) {
      fail("runtime_producer_inputs_invalid", "production_closure",
        "runtime payload declaration is malformed", { name });
    }
  });
  if (!value.payload.fixedRoots.length || !value.payload.trees.length
      || computeBuildIdentityHash(value.domains.artifactSource.hash,
        value.domains.producerRecipe.hash, value.domains.toolchainLock.hash)
        !== value.buildIdentityHash) {
    fail("runtime_producer_inputs_invalid", "production_closure",
      "runtime producer input hashes do not form one build identity");
  }
  const unsigned = Object.assign({}, value);
  delete unsigned.inputsSha256;
  if (value.inputsSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    fail("runtime_producer_inputs_invalid", "production_closure",
      "runtime producer input digest is detached");
  }
  return value;
}

function currentProducerInputs(root) {
  const resolvedRoot = path.resolve(root);
  const config = readRuntimeInputConfig(resolvedRoot);
  const names = ["artifactSource", "producerRecipe", "toolchainLock"];
  const rowsByDomain = {};
  const owners = new Map();
  names.forEach((name) => {
    const paths = enumerateDomainFiles(resolvedRoot, config, name);
    rowsByDomain[name] = paths.map((relativePath) => {
      if (owners.has(relativePath)) {
        fail("runtime_input_domain_overlap", "production_closure",
          "runtime producer input belongs to multiple identity domains", {
            relativePath, domains: [owners.get(relativePath), name],
          });
      }
      owners.set(relativePath, name);
      const file = exactFile(resolvedRoot, { role: "runtime_input", relativePath });
      return { relativePath, sha256: file.sha256, bytes: file.bytes };
    });
  });
  const configFile = exactFile(resolvedRoot, {
    role: "runtime_input_descriptor", relativePath: "config/build/runtime-inputs.v2.json",
  });
  const payload = normalizedPayloadConfig(config);
  const fingerprint = Evidence.sha256Text(Evidence.canonicalJson({
    config: configFile, rowsByDomain, payload,
  }));
  const cacheKey = resolvedRoot.toLowerCase();
  const cached = producerInputsCache.get(cacheKey);
  if (cached && cached.fingerprint === fingerprint) {
    return JSON.parse(JSON.stringify(cached.value));
  }
  const script = [
    "$ErrorActionPreference='Stop'",
    "[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)",
    ". (Join-Path $env:CF7_CRAFTING_SOURCE_ROOT 'tools/runtime-build-v2-common.ps1')",
    "$a=Get-Cf7RuntimeArtifactSourceHash -ProjectRoot $env:CF7_CRAFTING_SOURCE_ROOT -Mode Worktree",
    "$p=Get-Cf7RuntimeProducerRecipeHash -ProjectRoot $env:CF7_CRAFTING_SOURCE_ROOT -Mode Worktree",
    "$t=Get-Cf7RuntimeToolchainLockHashV2 -ProjectRoot $env:CF7_CRAFTING_SOURCE_ROOT -Mode Worktree",
    "$b=Get-Cf7RuntimeV2BuildIdentityHash -ArtifactSourceHash $a -ProducerRecipeHash $p -ToolchainLockHash $t",
    "[ordered]@{artifactSourceHash=$a;producerRecipeHash=$p;toolchainLockHash=$t;buildIdentityHash=$b}|ConvertTo-Json -Compress",
  ].join("\n");
  const result = childProcess.spawnSync("powershell.exe",
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script], {
      cwd: resolvedRoot, encoding: "utf8", windowsHide: true, maxBuffer: 4 * 1024 * 1024,
      env: Object.assign({}, process.env, { CF7_CRAFTING_SOURCE_ROOT: resolvedRoot }),
    });
  let hashes;
  try { hashes = JSON.parse(String(result.stdout || "").trim()); } catch (_error) { hashes = null; }
  const hashFields = ["artifactSourceHash", "producerRecipeHash", "toolchainLockHash",
    "buildIdentityHash"];
  if (result.status !== 0 || !Evidence.isPlainObject(hashes)
      || hashFields.some((name) => !SHA256_RE.test(String(hashes[name] || "").toUpperCase()))) {
    fail("runtime_producer_hash_failed", "production_closure",
      "canonical runtime producer identity could not be recomputed", {
        status: result.status, stderr: String(result.stderr || "").slice(0, 400),
      });
  }
  const finalConfig = readRuntimeInputConfig(resolvedRoot);
  const finalRowsByDomain = {};
  names.forEach((name) => {
    finalRowsByDomain[name] = enumerateDomainFiles(resolvedRoot, finalConfig, name)
      .map((relativePath) => {
        const file = exactFile(resolvedRoot, { role: "runtime_input", relativePath });
        return { relativePath, sha256: file.sha256, bytes: file.bytes };
      });
  });
  const finalConfigFile = exactFile(resolvedRoot, {
    role: "runtime_input_descriptor", relativePath: "config/build/runtime-inputs.v2.json",
  });
  const finalPayload = normalizedPayloadConfig(finalConfig);
  const finalFingerprint = Evidence.sha256Text(Evidence.canonicalJson({
    config: finalConfigFile, rowsByDomain: finalRowsByDomain, payload: finalPayload,
  }));
  if (finalFingerprint !== fingerprint) {
    fail("runtime_producer_inputs_changed", "production_closure",
      "runtime producer inputs changed while their canonical identity was recomputed");
  }
  const domains = {};
  names.forEach((name) => {
    const files = rowsByDomain[name];
    domains[name] = { hash: String(hashes[name + "Hash"]).toUpperCase(),
      fileCount: files.length, fingerprintSha256: Evidence.sha256Text(
        Evidence.canonicalJson(files)), files };
  });
  const value = { schema: PRODUCER_INPUTS_SCHEMA, root: resolvedRoot,
    config: configFile, domains, payload,
    buildIdentityHash: String(hashes.buildIdentityHash).toUpperCase() };
  value.inputsSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  validateProducerInputsEnvelope(value, resolvedRoot);
  producerInputsCache.set(cacheKey, { fingerprint, value });
  return JSON.parse(JSON.stringify(value));
}

function verifyBuildFileInventory(root) {
  const config = readRuntimeInputConfig(root);
  const declaredProducer = enumerateDomainFiles(root, config, "producerRecipe");
  const declaredToolchain = enumerateDomainFiles(root, config, "toolchainLock");
  const closedProducer = BUILD_FILES.filter((entry) => entry.role === "runtime_producer_source")
    .map((entry) => entry.relativePath).sort();
  const closedToolchain = BUILD_FILES.filter((entry) => entry.role === "runtime_toolchain_lock")
    .map((entry) => entry.relativePath).sort();
  const artifactSource = new Set(enumerateDomainFiles(root, config, "artifactSource"));
  if (Evidence.canonicalJson(declaredProducer) !== Evidence.canonicalJson(closedProducer)
      || Evidence.canonicalJson(declaredToolchain) !== Evidence.canonicalJson(closedToolchain)
      || !artifactSource.has("launcher/CRAZYFLASHER7MercenaryEmpire.csproj")
      || BUILD_FILES.filter((entry) => entry.role === "runtime_input_descriptor").length !== 1) {
    fail("production_build_inventory_invalid", "production_closure",
      "Crafting build-file surface drifted from runtime-inputs.v2", {
        declaredProducer, closedProducer, declaredToolchain, closedToolchain,
      });
  }
  return { producerRecipe: declaredProducer, toolchainLock: declaredToolchain };
}

function normalizedHash(value, field) {
  const normalized = String(value || "").toUpperCase();
  if (!SHA256_RE.test(normalized)) {
    fail("candidate_producer_hash_invalid", "production_closure",
      "candidate producer field is not SHA-256", { field });
  }
  return normalized;
}

function computeBuildIdentityHash(artifactSourceHash, producerRecipeHash, toolchainLockHash) {
  return Evidence.sha256Text("artifactSourceHash\t"
    + normalizedHash(artifactSourceHash, "artifactSourceHash") + "\n"
    + "producerRecipeHash\t" + normalizedHash(producerRecipeHash, "producerRecipeHash") + "\n"
    + "toolchainLockHash\t" + normalizedHash(toolchainLockHash, "toolchainLockHash") + "\n")
    .toUpperCase();
}

function exactCandidateFile(candidateRoot, relativePath, maximumBytes, allowEmpty) {
  const resolvedRoot = path.resolve(candidateRoot);
  let rootStat;
  let rootReal;
  try { rootStat = fs.lstatSync(resolvedRoot); rootReal = fs.realpathSync.native(resolvedRoot); }
  catch (_error) { rootStat = null; rootReal = null; }
  if (!rootStat || !rootStat.isDirectory() || rootStat.isSymbolicLink()
      || path.resolve(rootReal).toLowerCase() !== resolvedRoot.toLowerCase()) {
    fail("candidate_producer_root_invalid", "production_closure",
      "candidate producer root is missing or indirect");
  }
  const safe = safeRelativePath(relativePath, "candidate_producer_path_invalid");
  const filePath = path.resolve(resolvedRoot, safe.replace(/\//g, path.sep));
  const relative = path.relative(resolvedRoot, filePath);
  let stat;
  let real;
  try { stat = fs.lstatSync(filePath); real = fs.realpathSync.native(filePath); }
  catch (_error) {
    fail("candidate_producer_file_missing", "production_closure",
      "candidate producer evidence file is missing", { relativePath: safe });
  }
  if (!relative || relative.startsWith(".." + path.sep) || path.isAbsolute(relative)
      || !stat.isFile() || stat.isSymbolicLink()
      || path.resolve(real).toLowerCase() !== filePath.toLowerCase()
      || stat.size < (allowEmpty === true ? 0 : 1) || stat.size > maximumBytes) {
    fail("candidate_producer_file_invalid", "production_closure",
      "candidate producer evidence is not one bounded exact regular file", { relativePath: safe });
  }
  const bytes = fs.readFileSync(filePath);
  return { filePath, bytes, sha256: Evidence.sha256Bytes(bytes).toUpperCase(), size: bytes.length };
}

function excludedPayloadPath(relativePath, payload) {
  return payload.excludePaths.includes(relativePath)
    || payload.excludePrefixes.some((prefix) => relativePath.startsWith(prefix));
}

function enumerateCandidatePayload(candidateRoot, payload) {
  const values = new Set();
  payload.fixedRoots.forEach((relativePath) => {
    if (!excludedPayloadPath(relativePath, payload)) values.add(relativePath);
  });
  function walk(directory, base, tree) {
    fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
      const relative = tree + "/" + (base ? base + "/" : "") + entry.name;
      const full = path.join(directory, entry.name);
      if (entry.isSymbolicLink()) {
        fail("candidate_payload_file_invalid", "production_closure",
          "candidate payload contains a symbolic link", { path: relative });
      }
      if (entry.isDirectory()) { walk(full, (base ? base + "/" : "") + entry.name, tree); return; }
      if (entry.isFile() && !excludedPayloadPath(relative, payload)) values.add(relative);
    });
  }
  payload.trees.forEach((tree) => {
    const directory = path.resolve(candidateRoot, tree.replace(/\//g, path.sep));
    let stat;
    try { stat = fs.lstatSync(directory); } catch (_error) { stat = null; }
    if (!stat || !stat.isDirectory() || stat.isSymbolicLink()) {
      fail("candidate_payload_tree_invalid", "production_closure",
        "candidate payload tree is missing or indirect", { tree });
    }
    walk(directory, "", tree);
  });
  const paths = Array.from(values).sort();
  return paths.map((relativePath) => {
    const file = exactCandidateFile(candidateRoot, relativePath, 1024 * 1024 * 1024, true);
    return { path: relativePath, size: file.size, sha256: file.sha256 };
  });
}

function canonicalPayloadClosureHash(files) {
  const sorted = files.slice().sort((left, right) =>
    String(left.path) < String(right.path) ? -1 : (String(left.path) > String(right.path) ? 1 : 0));
  if (!sorted.length || new Set(sorted.map((entry) => String(entry.path).toLowerCase())).size
      !== sorted.length) {
    fail("candidate_payload_manifest_invalid", "production_closure",
      "candidate payload file set is empty or duplicated");
  }
  const canonical = sorted.map((row) => {
    const relative = safeRelativePath(row.path, "candidate_payload_manifest_invalid");
    const size = Number(row.size);
    const digest = normalizedHash(row.sha256, "payload.sha256");
    if (!Number.isSafeInteger(size) || size < 0) {
      fail("candidate_payload_manifest_invalid", "production_closure",
        "candidate payload size is malformed", { relative, size });
    }
    return relative + "\t" + size + "\t" + digest;
  }).join("\n") + "\n";
  return Evidence.sha256Text(canonical).toUpperCase();
}

function parseCandidateManifest(candidateRoot, manifestFile, payload) {
  const lines = manifestFile.bytes.toString("utf8").replace(/\r/g, "").split("\n");
  if (lines.pop() !== "" || lines.shift() !== "cf7-runtime-manifest-v2") {
    fail("candidate_producer_manifest_invalid", "production_closure",
      "candidate runtime manifest header or terminal newline is unsupported");
  }
  const metadataNames = ["publishMode", "artifactSourceHash", "producerRecipeHash",
    "toolchainLockHash", "toolchainBaseline", "buildIdentityHash", "payloadClosureHash"];
  const metadata = Object.create(null);
  const files = [];
  lines.forEach((line) => {
    const fields = line.split("\t");
    if (fields[0] === "file") {
      if (fields.length !== 4 || !/^\d+$/.test(fields[2])) {
        fail("candidate_payload_manifest_invalid", "production_closure",
          "candidate payload row is malformed");
      }
      files.push({ path: safeRelativePath(fields[1], "candidate_payload_manifest_invalid"),
        size: Number(fields[2]), sha256: normalizedHash(fields[3], "payload.sha256") });
      return;
    }
    if (fields.length !== 2 || !metadataNames.includes(fields[0])
        || Object.prototype.hasOwnProperty.call(metadata, fields[0]) || !fields[1]) {
      fail("candidate_producer_manifest_invalid", "production_closure",
        "candidate runtime manifest metadata is missing, duplicated, or extra", { line });
    }
    metadata[fields[0]] = fields[1];
  });
  if (Object.keys(metadata).length !== metadataNames.length
      || metadata.publishMode !== "framework-dependent" || !metadata.toolchainBaseline.trim()) {
    fail("candidate_producer_manifest_invalid", "production_closure",
      "candidate runtime manifest metadata set is incomplete or unsupported");
  }
  ["artifactSourceHash", "producerRecipeHash", "toolchainLockHash", "buildIdentityHash",
    "payloadClosureHash"].forEach((name) => { metadata[name] = normalizedHash(metadata[name], name); });
  const sorted = files.slice().sort((left, right) =>
    left.path < right.path ? -1 : (left.path > right.path ? 1 : 0));
  if (Evidence.canonicalJson(files) !== Evidence.canonicalJson(sorted)) {
    fail("candidate_payload_manifest_invalid", "production_closure",
      "candidate payload rows are not in canonical ordinal order");
  }
  const actualFiles = enumerateCandidatePayload(candidateRoot, payload);
  if (Evidence.canonicalJson(files) !== Evidence.canonicalJson(actualFiles)) {
    fail("candidate_payload_file_mismatch", "production_closure",
      "candidate payload manifest differs from the exact candidate payload files");
  }
  if (canonicalPayloadClosureHash(files) !== metadata.payloadClosureHash) {
    fail("candidate_payload_closure_mismatch", "production_closure",
      "candidate payload closure differs from its exact manifest rows");
  }
  return { metadata, files };
}

function captureCandidateProducerBinding(candidateRoot, candidateIdentity, closure) {
  validateProducerInputsEnvelope(closure && closure.producerInputs, closure && closure.root);
  const metadataFile = exactCandidateFile(candidateRoot, "runtime-build-metadata.v2.json",
    64 * 1024);
  const manifestFile = exactCandidateFile(candidateRoot,
    "runtime/cf7-runtime-manifest.tsv", 8 * 1024 * 1024);
  let metadata;
  try { metadata = JSON.parse(metadataFile.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (_error) {
    fail("candidate_producer_metadata_invalid", "production_closure",
      "candidate build metadata is not valid JSON");
  }
  const metadataKeys = ["schema", "builderLabel", "artifactSourceHash", "producerRecipeHash",
    "toolchainLockHash", "buildIdentityHash", "payloadClosureHash", "createdAtUtc"].sort();
  if (!Evidence.isPlainObject(metadata) || metadata.schema !== "cf7-runtime-candidate-metadata.v2"
      || Evidence.canonicalJson(Object.keys(metadata).sort()) !== Evidence.canonicalJson(metadataKeys)
      || typeof metadata.builderLabel !== "string" || !metadata.builderLabel.trim()
      || !Number.isFinite(Date.parse(metadata.createdAtUtc))) {
    fail("candidate_producer_metadata_invalid", "production_closure",
      "candidate build metadata does not have the exact v2 producer schema");
  }
  const hashes = {};
  ["artifactSourceHash", "producerRecipeHash", "toolchainLockHash", "buildIdentityHash",
    "payloadClosureHash"].forEach((field) => { hashes[field] = normalizedHash(metadata[field], field); });
  const parsed = parseCandidateManifest(candidateRoot, manifestFile,
    closure.producerInputs.payload);
  const current = closure.producerInputs;
  if (["artifactSourceHash", "producerRecipeHash", "toolchainLockHash", "buildIdentityHash",
    "payloadClosureHash"].some((field) => parsed.metadata[field] !== hashes[field])
      || hashes.artifactSourceHash !== current.domains.artifactSource.hash
      || hashes.producerRecipeHash !== current.domains.producerRecipe.hash
      || hashes.toolchainLockHash !== current.domains.toolchainLock.hash
      || hashes.buildIdentityHash !== current.buildIdentityHash
      || computeBuildIdentityHash(hashes.artifactSourceHash, hashes.producerRecipeHash,
        hashes.toolchainLockHash) !== hashes.buildIdentityHash
      || hashes.buildIdentityHash !== normalizedHash(candidateIdentity.buildIdentity,
        "candidateIdentity.buildIdentity")
      || hashes.payloadClosureHash !== normalizedHash(candidateIdentity.payloadClosure,
        "candidateIdentity.payloadClosure")) {
    fail("candidate_producer_identity_mismatch", "production_closure",
      "candidate producer identity is detached from current runtime inputs or authenticated runtime");
  }
  const core = parsed.files.filter((entry) =>
    entry.path.toLowerCase() === "runtime/crazyflasher7mercenaryempire.core.dll");
  if (core.length !== 1 || core[0].sha256 !== normalizedHash(candidateIdentity.coreSha256,
    "candidateIdentity.coreSha256")) {
    fail("candidate_core_identity_mismatch", "production_closure",
      "candidate runtime identity is detached from the payload manifest Core DLL row");
  }
  const resolvedCandidateRoot = path.resolve(candidateRoot);
  const authenticatedInstallRoot = path.resolve(String(candidateIdentity.installRoot || ""));
  const authenticatedProcessPath = path.resolve(String(candidateIdentity.processPath || ""));
  const processRelative = safeRelativePath(
    path.relative(resolvedCandidateRoot, authenticatedProcessPath).replace(/\\/g, "/"),
    "candidate_process_path_invalid");
  const processRows = parsed.files.filter((entry) => entry.path.toLowerCase()
    === processRelative.toLowerCase());
  if (authenticatedInstallRoot.toLowerCase() !== resolvedCandidateRoot.toLowerCase()
      || processRelative.toLowerCase()
        !== "runtime/crazyflasher7mercenaryempire.core.exe"
      || processRows.length !== 1) {
    fail("candidate_process_identity_mismatch", "production_closure",
      "authenticated processPath is not the one exact candidate Core EXE payload row");
  }
  const coreFile = exactCandidateFile(candidateRoot, core[0].path, 512 * 1024 * 1024);
  const processFile = exactCandidateFile(candidateRoot, processRows[0].path,
    512 * 1024 * 1024);
  if (coreFile.sha256 !== core[0].sha256 || coreFile.size !== core[0].size
      || processFile.sha256 !== processRows[0].sha256
      || processFile.size !== processRows[0].size) {
    fail("candidate_process_bytes_mismatch", "production_closure",
      "authenticated Core EXE/DLL bytes differ from their exact payload rows");
  }
  const value = { schema: CANDIDATE_PRODUCER_SCHEMA,
    candidateRoot: resolvedCandidateRoot,
    metadata: { locator: "candidate:runtime-build-metadata.v2.json",
      sha256: metadataFile.sha256, bytes: metadataFile.size },
    manifest: { locator: "candidate:runtime/cf7-runtime-manifest.tsv",
      sha256: manifestFile.sha256, bytes: manifestFile.size },
    builderLabel: metadata.builderLabel, createdAtUtc: metadata.createdAtUtc,
    producerInputsSha256: current.inputsSha256,
    artifactSourceHash: hashes.artifactSourceHash,
    producerRecipeHash: hashes.producerRecipeHash,
    toolchainLockHash: hashes.toolchainLockHash,
    buildIdentityHash: hashes.buildIdentityHash,
    payloadClosureHash: hashes.payloadClosureHash,
    payloadFileCount: parsed.files.length,
    processImage: { locator: "candidate:" + processRows[0].path,
      sha256: processFile.sha256, bytes: processFile.size },
    coreLibrary: { locator: "candidate:" + core[0].path,
      sha256: coreFile.sha256, bytes: coreFile.size } };
  value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function verifyCandidateProducerBinding(candidateRoot, candidateIdentity, closure, evidence) {
  const current = captureCandidateProducerBinding(candidateRoot, candidateIdentity, closure);
  if (!Evidence.isPlainObject(evidence) || evidence.schema !== CANDIDATE_PRODUCER_SCHEMA
      || Evidence.canonicalJson(current) !== Evidence.canonicalJson(evidence)) {
    fail("candidate_producer_evidence_mismatch", "production_closure",
      "captured candidate producer evidence differs from exact current candidate files");
  }
  return evidence;
}


module.exports = {
  BUILD_FILES,
  CANDIDATE_PRODUCER_SCHEMA,
  PRODUCER_INPUTS_SCHEMA,
  canonicalPayloadClosureHash,
  captureCandidateProducerBinding,
  computeBuildIdentityHash,
  currentProducerInputs,
  validateProducerInputsEnvelope,
  verifyBuildFileInventory,
  verifyCandidateProducerBinding,
};
