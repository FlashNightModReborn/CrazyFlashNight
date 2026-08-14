"use strict";

// Design contract only. This module performs no filesystem, process, source-control,
// verifier, or runtime operation and grants no admission or promotion authority.

const crypto = require("node:crypto");
const path = require("node:path");

const DESIGN_ONLY = true;
const INTEGRATION_AVAILABLE = false;
const STRUCTURAL_SCOPE = "design_only_structural_validation_no_production_authority";

const ADMISSION_SCHEMA =
  "workbench-live-e2e.material-shop.formal-consensus-admission.v1";
const WINDOW_SCHEMA =
  "workbench-live-e2e.material-shop.formal-consensus-window.v1";
const IMMUTABLE_SOURCE_SCHEMA =
  "workbench-live-e2e.material-shop.formal-verifier-source.v1";
const PROMOTION_SCHEMA =
  "workbench-live-e2e.material-shop.formal-promotion-binding.v1";
const CONSENSUS_SCHEMA = "cf7-runtime-release-consensus.v2";
const PRODUCER_BINDING_SCHEMA =
  "workbench-live-e2e.crafting.candidate-producer-binding.v2";

const VERIFY_SCRIPT = "tools/verify-runtime-consensus.ps1";
const CONSENSUS_FILE = "config/build/runtime-release-consensus.json";
const MANIFEST_FILE = "runtime/cf7-runtime-manifest.tsv";
const CORE_LIBRARY_FILE = "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll";
const PROCESS_IMAGE_FILE = "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe";

const MAX_BUFFER_BYTES = 4 * 1024 * 1024;
const TIMEOUT_MS = 10 * 60 * 1000;
const CANONICAL_ROOT = path.win32.normalize(path.win32.join(__dirname, "..", "..", ".."));
const SHA256_RE = /^[a-f0-9]{64}$/;
const SHA256_ANY_RE = /^[A-Fa-f0-9]{64}$/;
const UPPER_SHA256_RE = /^[A-F0-9]{64}$/;
const OID_RE = /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/;
const ID_RE = /^[A-Za-z0-9_~-][A-Za-z0-9._~-]{0,159}$/;
const SOURCE_TAG_RE = /^runtime-build-v2\/[A-Za-z0-9][A-Za-z0-9._-]{0,159}$/;
const SOURCE_REF_RE = /^refs\/tags\/(runtime-build-v2\/[A-Za-z0-9][A-Za-z0-9._-]{0,159})$/;
const SUCCESS_MARKER_RE = /^\[RuntimeConsensus\] OK schema=v2 mode=Worktree signers=([1-9]\d*) faultDomains=([1-9]\d*) payload=([A-F0-9]{64})$/;
const POWERSHELL_SUFFIX = "\\system32\\windowspowershell\\v1.0\\powershell.exe";

const VERIFIER_PROGRAM_FILES = Object.freeze({
  verifierScript: Object.freeze({
    relativePath: VERIFY_SCRIPT, maximumBytes: 1024 * 1024,
  }),
  runtimeBuildCommon: Object.freeze({
    relativePath: "tools/runtime-build-common.ps1", maximumBytes: 2 * 1024 * 1024,
  }),
  runtimeBuildV2Common: Object.freeze({
    relativePath: "tools/runtime-build-v2-common.ps1", maximumBytes: 2 * 1024 * 1024,
  }),
  runtimeBuildAttestationV2Common: Object.freeze({
    relativePath: "tools/runtime-build-attestation-v2-common.ps1",
    maximumBytes: 2 * 1024 * 1024,
  }),
  runtimeBuildQueueCommon: Object.freeze({
    relativePath: "tools/runtime-build-queue-common.ps1", maximumBytes: 2 * 1024 * 1024,
  }),
  bundleVerifier: Object.freeze({
    relativePath: "tools/verify-runtime-bundle-v2.ps1", maximumBytes: 2 * 1024 * 1024,
  }),
  githubAttestationVerifier: Object.freeze({
    relativePath: "tools/verify-runtime-github-attestation.ps1",
    maximumBytes: 2 * 1024 * 1024,
  }),
});

const WINDOW_FILES = Object.freeze({
  ...VERIFIER_PROGRAM_FILES,
  consensus: Object.freeze({
    relativePath: CONSENSUS_FILE, maximumBytes: 8 * 1024 * 1024,
  }),
  manifest: Object.freeze({
    relativePath: MANIFEST_FILE, maximumBytes: 8 * 1024 * 1024,
  }),
  coreLibrary: Object.freeze({
    relativePath: CORE_LIBRARY_FILE, maximumBytes: 512 * 1024 * 1024,
  }),
  processImage: Object.freeze({
    relativePath: PROCESS_IMAGE_FILE, maximumBytes: 512 * 1024 * 1024,
  }),
});

const PRODUCER_KEYS = Object.freeze([
  "schema", "candidateRoot", "metadata", "manifest", "builderLabel", "createdAtUtc",
  "producerInputsSha256", "artifactSourceHash", "producerRecipeHash",
  "toolchainLockHash", "buildIdentityHash", "payloadClosureHash", "payloadFileCount",
  "processImage", "coreLibrary", "evidenceSha256",
]);
const FILE_DESCRIPTOR_KEYS = Object.freeze(["locator", "relativePath", "bytes", "sha256"]);
const PRODUCER_FILE_KEYS = Object.freeze(["locator", "sha256", "bytes"]);
const IMMUTABLE_SOURCE_KEYS = Object.freeze([
  "schema", "sourceCommitOid", "releaseTreeOid", "files", "sourceSha256",
]);
const IMMUTABLE_FILE_KEYS = Object.freeze([
  "relativePath", "sourceBytes", "sourceSha256", "worktreeBytes", "worktreeSha256",
  "worktreeCanonicalBytes", "worktreeCanonicalSha256",
]);
const WINDOW_KEYS = Object.freeze([
  "schema", "canonicalRoot", "executor", "immutableSource", "files", "windowSha256",
]);
const EXECUTOR_KEYS = Object.freeze(["absolutePath", "bytes", "sha256"]);
const COMMAND_KEYS = Object.freeze([
  "executable", "args", "cwd", "encoding", "windowsHide", "timeoutMs",
  "maxBufferBytes",
]);
const OUTPUT_KEYS = Object.freeze(["base64", "bytes", "sha256"]);
const INVOCATION_KEYS = Object.freeze([
  "command", "verifierScriptSha256", "verifierProgramClosureSha256",
  "executorSha256", "startedAtUtc", "completedAtUtc", "durationMs", "exitCode",
  "signal", "stdout", "stderr", "successMarker",
]);
const PROMOTION_KEYS = Object.freeze([
  "schema", "consensusSchema", "status", "sourceCommitOid", "releaseTreeOid",
  "sourceTag", "requestId", "buildIdentityHash", "payloadClosureHash",
  "processImageSha256", "coreLibrarySha256", "policyReceiptSha256",
  "consensusSha256", "promotedAtUtc",
]);
const ADMISSION_KEYS = Object.freeze([
  "schema", "admittedAtUtc", "status", "scope", "runId", "preflightSha256",
  "preparerInputSha256", "invocation", "window", "source", "policy", "candidate",
  "promotion", "boundaries", "admissionSha256",
]);
const SOURCE_KEYS = Object.freeze(["sourceCommitOid", "sourceRef", "sourceTag"]);
const POLICY_KEYS = Object.freeze([
  "schema", "profile", "passed", "artifactSourceHash", "producerRecipeHash",
  "toolchainLockHash", "toolchainHash", "policyHash", "candidateRoot",
  "receiptSha256", "requiredChecks",
]);
const CANDIDATE_KEYS = Object.freeze([
  "buildSha256", "producerBindingSha256", "buildIdentityHash", "payloadClosureHash",
  "processImageSha256", "coreLibrarySha256",
]);
const BOUNDARY_KEYS = Object.freeze([
  "officialConsensusVerifierExecuted", "officialConsensusVerified",
  "verificationWindowStable", "promotionIdentityVerified", "formalApplicabilityCaptured",
  "formalPlanCreated", "purchaseAuthorityCreated", "formalExecutionAdmitted",
  "runtimeLaunched", "purchasePerformed", "standardEntryVerified",
]);
const REQUIRED_POLICY_CHECKS = Object.freeze([
  "release-tree-materialized", "tracked-tree-readonly", "candidate-payload-readonly",
]);

class StructuralContractError extends Error {
  constructor(code, message, details) {
    super(message);
    this.name = "StructuralContractError";
    this.code = code;
    this.phase = "formal_consensus_admission_design_only";
    this.details = details || null;
  }
}

function fail(code, message, details) {
  throw new StructuralContractError(code, message, details);
}

function isPlainObject(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (!isPlainObject(value)) return value;
  const output = {};
  Object.keys(value).sort().forEach((key) => { output[key] = stableValue(value[key]); });
  return output;
}

function canonicalJson(value) {
  return JSON.stringify(stableValue(value));
}

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function sha256Text(value) {
  return sha256Bytes(Buffer.from(String(value), "utf8"));
}

function digestWithout(value, key) {
  const unsigned = Object.assign({}, value);
  delete unsigned[key];
  return sha256Text(canonicalJson(unsigned));
}

function exactKeys(value, expected, code, label) {
  const actual = isPlainObject(value) ? Object.keys(value).sort() : null;
  if (!actual || canonicalJson(actual) !== canonicalJson(expected.slice().sort())) {
    fail(code, label + " key set is not the frozen design shape", {
      expected: expected.slice().sort(), actual,
    });
  }
  return value;
}

function sameWindowsPath(left, right) {
  return typeof left === "string" && typeof right === "string"
    && path.win32.isAbsolute(left) && path.win32.isAbsolute(right)
    && path.win32.normalize(left).toLowerCase() === path.win32.normalize(right).toLowerCase();
}

function validTimestamp(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)) {
    return false;
  }
  const milliseconds = new Date(value).getTime();
  return Number.isFinite(milliseconds) && new Date(milliseconds).toISOString() === value;
}

function upperHash(value) {
  return SHA256_ANY_RE.test(String(value || "")) ? String(value).toUpperCase() : null;
}

function structuralResult(kind) {
  return Object.freeze({
    ok: true,
    kind,
    scope: STRUCTURAL_SCOPE,
    designOnly: DESIGN_ONLY,
    integrationAvailable: INTEGRATION_AVAILABLE,
    authorityGranted: false,
  });
}

function validateProducerFileCore(value, locator, label) {
  exactKeys(value, PRODUCER_FILE_KEYS,
    "material_shop_formal_consensus_candidate_shape_invalid", label);
  if (value.locator !== locator || !SHA256_ANY_RE.test(String(value.sha256 || ""))
      || !Number.isSafeInteger(value.bytes) || value.bytes < 1) {
    fail("material_shop_formal_consensus_candidate_shape_invalid",
      label + " descriptor fails the design-only structural contract");
  }
}

function validateAcceptedProducerBindingCore(value) {
  exactKeys(value, PRODUCER_KEYS,
    "material_shop_formal_consensus_candidate_shape_invalid", "accepted producer binding");
  validateProducerFileCore(value.metadata,
    "candidate:runtime-build-metadata.v2.json", "metadata");
  validateProducerFileCore(value.manifest,
    "candidate:runtime/cf7-runtime-manifest.tsv", "manifest");
  validateProducerFileCore(value.processImage,
    "candidate:" + PROCESS_IMAGE_FILE, "process image");
  validateProducerFileCore(value.coreLibrary,
    "candidate:" + CORE_LIBRARY_FILE, "Core library");
  const hashes = [value.producerInputsSha256, value.artifactSourceHash,
    value.producerRecipeHash, value.toolchainLockHash, value.buildIdentityHash,
    value.payloadClosureHash];
  if (value.schema !== PRODUCER_BINDING_SCHEMA
      || !path.win32.isAbsolute(value.candidateRoot)
      || typeof value.builderLabel !== "string" || !value.builderLabel.trim()
      || !validTimestamp(value.createdAtUtc)
      || hashes.some((entry) => !SHA256_ANY_RE.test(String(entry || "")))
      || !Number.isSafeInteger(value.payloadFileCount) || value.payloadFileCount < 1
      || !SHA256_RE.test(String(value.evidenceSha256 || ""))
      || value.evidenceSha256 !== digestWithout(value, "evidenceSha256")) {
    fail("material_shop_formal_consensus_candidate_shape_invalid",
      "accepted producer binding fails structural checks; acceptance is not established");
  }
  return value;
}

function validateAcceptedProducerBindingShape(value) {
  validateAcceptedProducerBindingCore(value);
  return structuralResult("accepted_producer_binding_shape");
}

function validateWindowFileCore(value, expected, label) {
  exactKeys(value, FILE_DESCRIPTOR_KEYS,
    "material_shop_formal_consensus_window_shape_invalid", label);
  if (value.locator !== "root:" + expected.relativePath
      || value.relativePath !== expected.relativePath
      || !Number.isSafeInteger(value.bytes) || value.bytes < 1
      || value.bytes > expected.maximumBytes
      || !SHA256_RE.test(String(value.sha256 || ""))) {
    fail("material_shop_formal_consensus_window_shape_invalid",
      label + " descriptor fails the frozen structural contract");
  }
}

function validateImmutableSourceCore(value, currentFiles) {
  exactKeys(value, IMMUTABLE_SOURCE_KEYS,
    "material_shop_formal_consensus_source_shape_invalid", "immutable source closure");
  exactKeys(value.files, Object.keys(VERIFIER_PROGRAM_FILES),
    "material_shop_formal_consensus_source_shape_invalid", "immutable source files");
  if (value.schema !== IMMUTABLE_SOURCE_SCHEMA
      || !OID_RE.test(String(value.sourceCommitOid || ""))
      || !OID_RE.test(String(value.releaseTreeOid || ""))) {
    fail("material_shop_formal_consensus_source_shape_invalid",
      "immutable source identifiers fail the design-only structural contract");
  }
  for (const name of Object.keys(VERIFIER_PROGRAM_FILES)) {
    const expected = VERIFIER_PROGRAM_FILES[name];
    const descriptor = value.files[name];
    const current = currentFiles[name];
    exactKeys(descriptor, IMMUTABLE_FILE_KEYS,
      "material_shop_formal_consensus_source_shape_invalid", name + " source binding");
    if (descriptor.relativePath !== expected.relativePath
        || !Number.isSafeInteger(descriptor.sourceBytes) || descriptor.sourceBytes < 1
        || descriptor.sourceBytes > expected.maximumBytes
        || !SHA256_RE.test(String(descriptor.sourceSha256 || ""))
        || !Number.isSafeInteger(descriptor.worktreeBytes) || descriptor.worktreeBytes < 1
        || descriptor.worktreeBytes > expected.maximumBytes
        || !SHA256_RE.test(String(descriptor.worktreeSha256 || ""))
        || descriptor.worktreeCanonicalBytes !== descriptor.sourceBytes
        || descriptor.worktreeCanonicalSha256 !== descriptor.sourceSha256
        || current.relativePath !== descriptor.relativePath
        || current.bytes !== descriptor.worktreeBytes
        || current.sha256 !== descriptor.worktreeSha256) {
      fail("material_shop_formal_consensus_source_shape_invalid",
        name + " source/worktree descriptors are not structurally cross-bound");
    }
  }
  if (!SHA256_RE.test(String(value.sourceSha256 || ""))
      || value.sourceSha256 !== digestWithout(value, "sourceSha256")) {
    fail("material_shop_formal_consensus_source_shape_invalid",
      "immutable source closure self-digest drifted; no source truth is inferred");
  }
}

function validateReleaseWindowCore(value) {
  exactKeys(value, WINDOW_KEYS,
    "material_shop_formal_consensus_window_shape_invalid", "release window");
  exactKeys(value.executor, EXECUTOR_KEYS,
    "material_shop_formal_consensus_window_shape_invalid", "executor descriptor");
  exactKeys(value.files, Object.keys(WINDOW_FILES),
    "material_shop_formal_consensus_window_shape_invalid", "release window files");
  for (const name of Object.keys(WINDOW_FILES)) {
    validateWindowFileCore(value.files[name], WINDOW_FILES[name], name);
  }
  validateImmutableSourceCore(value.immutableSource, value.files);
  if (value.schema !== WINDOW_SCHEMA
      || !sameWindowsPath(value.canonicalRoot, CANONICAL_ROOT)
      || !path.win32.isAbsolute(value.executor.absolutePath)
      || !path.win32.normalize(value.executor.absolutePath).toLowerCase()
        .endsWith(POWERSHELL_SUFFIX)
      || !Number.isSafeInteger(value.executor.bytes) || value.executor.bytes < 1
      || value.executor.bytes > 64 * 1024 * 1024
      || !SHA256_RE.test(String(value.executor.sha256 || ""))
      || !SHA256_RE.test(String(value.windowSha256 || ""))
      || value.windowSha256 !== digestWithout(value, "windowSha256")) {
    fail("material_shop_formal_consensus_window_shape_invalid",
      "release window fails structural checks; filesystem stability is not established");
  }
  return value;
}

function validateReleaseWindowShape(value) {
  validateReleaseWindowCore(value);
  return structuralResult("release_window_shape");
}

function validateVerifierCommandCore(value, expectedExecutor) {
  exactKeys(value, COMMAND_KEYS,
    "material_shop_formal_consensus_command_shape_invalid", "verifier command");
  const verifierPath = path.win32.join(CANONICAL_ROOT,
    VERIFY_SCRIPT.replace(/\//g, "\\"));
  const recordPath = path.win32.join(CANONICAL_ROOT,
    CONSENSUS_FILE.replace(/\//g, "\\"));
  const expectedArgs = [
    "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
    verifierPath, "-ProjectRoot", CANONICAL_ROOT, "-DeploymentRoot", CANONICAL_ROOT,
    "-RecordPath", recordPath,
  ];
  if (!path.win32.isAbsolute(value.executable)
      || !path.win32.normalize(value.executable).toLowerCase().endsWith(POWERSHELL_SUFFIX)
      || (expectedExecutor && !sameWindowsPath(value.executable, expectedExecutor))
      || canonicalJson(value.args) !== canonicalJson(expectedArgs)
      || !sameWindowsPath(value.cwd, CANONICAL_ROOT)
      || value.encoding !== null || value.windowsHide !== true
      || value.timeoutMs !== TIMEOUT_MS || value.maxBufferBytes !== MAX_BUFFER_BYTES) {
    fail("material_shop_formal_consensus_command_shape_invalid",
      "verifier command fails the pinned Worktree structural contract; it is not executed here");
  }
  return value;
}

function validateVerifierCommandShape(value) {
  validateVerifierCommandCore(value, null);
  return structuralResult("verifier_command_shape");
}

function validateOutputCore(value, label) {
  exactKeys(value, OUTPUT_KEYS,
    "material_shop_formal_consensus_invocation_shape_invalid", label);
  let bytes = null;
  if (typeof value.base64 === "string") {
    try { bytes = Buffer.from(value.base64, "base64"); } catch (_error) { bytes = null; }
  }
  if (!bytes || bytes.toString("base64") !== value.base64
      || !Number.isSafeInteger(value.bytes) || value.bytes !== bytes.length
      || value.bytes > MAX_BUFFER_BYTES
      || !SHA256_RE.test(String(value.sha256 || ""))
      || value.sha256 !== sha256Bytes(bytes)) {
    fail("material_shop_formal_consensus_invocation_shape_invalid",
      label + " descriptor is not canonical or self-consistent");
  }
  return bytes;
}

function validateInvocationCore(value, releaseWindow, payloadClosureHash) {
  exactKeys(value, INVOCATION_KEYS,
    "material_shop_formal_consensus_invocation_shape_invalid", "verifier invocation");
  const window = validateReleaseWindowCore(releaseWindow);
  validateVerifierCommandCore(value.command, window.executor.absolutePath);
  const stdoutBytes = validateOutputCore(value.stdout, "stdout");
  validateOutputCore(value.stderr, "stderr");
  const started = validTimestamp(value.startedAtUtc)
    ? new Date(value.startedAtUtc).getTime() : NaN;
  const completed = validTimestamp(value.completedAtUtc)
    ? new Date(value.completedAtUtc).getTime() : NaN;
  const marker = SUCCESS_MARKER_RE.exec(String(value.successMarker || ""));
  const markerLines = stdoutBytes.toString("utf8").split(/\r?\n/)
    .filter((line) => line.startsWith("[RuntimeConsensus] OK"));
  if (value.verifierScriptSha256 !== window.files.verifierScript.sha256
      || value.verifierProgramClosureSha256 !== window.immutableSource.sourceSha256
      || value.executorSha256 !== window.executor.sha256
      || !Number.isFinite(started) || !Number.isFinite(completed) || completed < started
      || value.durationMs !== completed - started
      || value.exitCode !== 0 || value.signal !== null || value.stdout.bytes < 1
      || !marker || Number(marker[1]) < 2 || Number(marker[2]) < 2
      || markerLines.length !== 1 || markerLines[0] !== value.successMarker
      || !UPPER_SHA256_RE.test(String(payloadClosureHash || ""))
      || marker[3] !== payloadClosureHash) {
    fail("material_shop_formal_consensus_invocation_shape_invalid",
      "invocation receipt is only structurally invalid or detached; no execution is inferred");
  }
  return value;
}

function validateInvocationShape(value, releaseWindow, payloadClosureHash) {
  validateInvocationCore(value, releaseWindow, payloadClosureHash);
  return structuralResult("verifier_invocation_shape");
}

function validatePromotionCore(value) {
  exactKeys(value, PROMOTION_KEYS,
    "material_shop_formal_promotion_shape_invalid", "promotion projection");
  if (value.schema !== PROMOTION_SCHEMA || value.consensusSchema !== CONSENSUS_SCHEMA
      || value.status !== "promoted"
      || !OID_RE.test(String(value.sourceCommitOid || ""))
      || !OID_RE.test(String(value.releaseTreeOid || ""))
      || !SOURCE_TAG_RE.test(String(value.sourceTag || ""))
      || !UPPER_SHA256_RE.test(String(value.requestId || ""))
      || !UPPER_SHA256_RE.test(String(value.buildIdentityHash || ""))
      || !UPPER_SHA256_RE.test(String(value.payloadClosureHash || ""))
      || !UPPER_SHA256_RE.test(String(value.processImageSha256 || ""))
      || !UPPER_SHA256_RE.test(String(value.coreLibrarySha256 || ""))
      || !UPPER_SHA256_RE.test(String(value.policyReceiptSha256 || ""))
      || !SHA256_RE.test(String(value.consensusSha256 || ""))
      || !validTimestamp(value.promotedAtUtc)) {
    fail("material_shop_formal_promotion_shape_invalid",
      "promotion projection fails structural checks; promotion is not established");
  }
  return value;
}

function validatePromotionShape(value) {
  validatePromotionCore(value);
  return structuralResult("promotion_shape");
}

function validateAdmissionTimelineCore(value) {
  const promoted = new Date(value.promotion.promotedAtUtc).getTime();
  const started = new Date(value.invocation.startedAtUtc).getTime();
  const completed = new Date(value.invocation.completedAtUtc).getTime();
  const admitted = validTimestamp(value.admittedAtUtc)
    ? new Date(value.admittedAtUtc).getTime() : NaN;
  if (![promoted, started, completed, admitted].every(Number.isFinite)
      || promoted > started || started > completed || completed > admitted) {
    fail("material_shop_formal_consensus_time_shape_invalid",
      "promotion, invocation, and admission timestamps are structurally reversed");
  }
}

function validateFormalConsensusAdmissionCore(value, acceptedProducerBinding) {
  const producer = validateAcceptedProducerBindingCore(acceptedProducerBinding);
  exactKeys(value, ADMISSION_KEYS,
    "material_shop_formal_consensus_admission_shape_invalid", "formal consensus admission");
  exactKeys(value.window, ["before", "after", "exactMatch"],
    "material_shop_formal_consensus_admission_shape_invalid", "verification window pair");
  exactKeys(value.source, SOURCE_KEYS,
    "material_shop_formal_consensus_admission_shape_invalid", "source projection");
  exactKeys(value.policy, POLICY_KEYS,
    "material_shop_formal_consensus_admission_shape_invalid", "policy projection");
  exactKeys(value.candidate, CANDIDATE_KEYS,
    "material_shop_formal_consensus_admission_shape_invalid", "candidate projection");
  exactKeys(value.boundaries, BOUNDARY_KEYS,
    "material_shop_formal_consensus_admission_shape_invalid", "boundary projection");
  const before = validateReleaseWindowCore(value.window.before);
  const after = validateReleaseWindowCore(value.window.after);
  const promotion = validatePromotionCore(value.promotion);
  validateInvocationCore(value.invocation, after, promotion.payloadClosureHash);
  validateAdmissionTimelineCore(value);
  const sourceMatch = SOURCE_REF_RE.exec(String(value.source.sourceRef || ""));
  const falseBoundaries = ["formalApplicabilityCaptured", "formalPlanCreated",
    "purchaseAuthorityCreated", "formalExecutionAdmitted", "runtimeLaunched",
    "purchasePerformed", "standardEntryVerified"];
  const policyHashes = [value.policy.artifactSourceHash, value.policy.producerRecipeHash,
    value.policy.toolchainLockHash, value.policy.toolchainHash, value.policy.policyHash];
  if (value.schema !== ADMISSION_SCHEMA
      || value.status !== "promotion_identity_verified"
      || value.scope !== "official_consensus_only"
      || !ID_RE.test(String(value.runId || "")) || String(value.runId).endsWith(".")
      || !SHA256_RE.test(String(value.preflightSha256 || ""))
      || !SHA256_RE.test(String(value.preparerInputSha256 || ""))
      || value.window.exactMatch !== true
      || canonicalJson(before) !== canonicalJson(after)
      || value.source.sourceCommitOid !== promotion.sourceCommitOid
      || value.source.sourceTag !== promotion.sourceTag
      || !sourceMatch || sourceMatch[1] !== value.source.sourceTag
      || after.immutableSource.sourceCommitOid !== value.source.sourceCommitOid
      || after.immutableSource.releaseTreeOid !== promotion.releaseTreeOid
      || value.policy.schema !== "cf7-runtime-policy-validation.v2"
      || value.policy.profile !== "production" || value.policy.passed !== true
      || policyHashes.some((entry) => !UPPER_SHA256_RE.test(String(entry || "")))
      || value.policy.artifactSourceHash !== upperHash(producer.artifactSourceHash)
      || value.policy.producerRecipeHash !== upperHash(producer.producerRecipeHash)
      || value.policy.toolchainLockHash !== upperHash(producer.toolchainLockHash)
      || value.policy.toolchainHash !== value.policy.toolchainLockHash
      || typeof value.policy.candidateRoot !== "string" || !value.policy.candidateRoot.trim()
      || value.policy.receiptSha256 !== promotion.policyReceiptSha256
      || canonicalJson(value.policy.requiredChecks) !== canonicalJson(REQUIRED_POLICY_CHECKS)
      || !SHA256_RE.test(String(value.candidate.buildSha256 || ""))
      || value.candidate.producerBindingSha256 !== producer.evidenceSha256
      || value.candidate.buildIdentityHash !== promotion.buildIdentityHash
      || value.candidate.payloadClosureHash !== promotion.payloadClosureHash
      || value.candidate.processImageSha256 !== promotion.processImageSha256
      || value.candidate.coreLibrarySha256 !== promotion.coreLibrarySha256
      || value.candidate.processImageSha256 !== upperHash(producer.processImage.sha256)
      || value.candidate.coreLibrarySha256 !== upperHash(producer.coreLibrary.sha256)
      || promotion.consensusSha256 !== after.files.consensus.sha256
      || promotion.processImageSha256 !== upperHash(after.files.processImage.sha256)
      || promotion.coreLibrarySha256 !== upperHash(after.files.coreLibrary.sha256)
      || value.boundaries.officialConsensusVerifierExecuted !== true
      || value.boundaries.officialConsensusVerified !== true
      || value.boundaries.verificationWindowStable !== true
      || value.boundaries.promotionIdentityVerified !== true
      || falseBoundaries.some((name) => value.boundaries[name] !== false)
      || !SHA256_RE.test(String(value.admissionSha256 || ""))
      || value.admissionSha256 !== digestWithout(value, "admissionSha256")) {
    fail("material_shop_formal_consensus_admission_shape_invalid",
      "admission record fails structural cross-binding; no production authority is granted");
  }
  return value;
}

function validateFormalConsensusAdmissionShape(value, acceptedProducerBinding) {
  validateFormalConsensusAdmissionCore(value, acceptedProducerBinding);
  return structuralResult("formal_consensus_admission_shape");
}

module.exports = Object.freeze({
  ADMISSION_SCHEMA,
  CONSENSUS_SCHEMA,
  CORE_LIBRARY_FILE,
  DESIGN_ONLY,
  IMMUTABLE_SOURCE_SCHEMA,
  INTEGRATION_AVAILABLE,
  MANIFEST_FILE,
  PROCESS_IMAGE_FILE,
  PROMOTION_SCHEMA,
  STRUCTURAL_SCOPE,
  VERIFY_SCRIPT,
  VERIFIER_PROGRAM_FILES,
  WINDOW_SCHEMA,
  validateAcceptedProducerBindingShape,
  validateFormalConsensusAdmissionShape,
  validateInvocationShape,
  validatePromotionShape,
  validateReleaseWindowShape,
  validateVerifierCommandShape,
});
