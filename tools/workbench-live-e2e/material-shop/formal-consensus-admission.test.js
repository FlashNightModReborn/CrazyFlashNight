"use strict";

const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const MODULE_PATH = require.resolve("./formal-consensus-admission");
const MODULE_SOURCE = fs.readFileSync(MODULE_PATH, "utf8");
const FS_MUTATORS = [
  "appendFileSync", "copyFileSync", "cpSync", "createWriteStream", "fsyncSync",
  "linkSync", "mkdirSync", "mkdtempSync", "openSync", "renameSync", "rmSync",
  "rmdirSync", "symlinkSync", "truncateSync", "unlinkSync", "writeFileSync", "writeSync",
];
const PROCESS_LAUNCHERS = ["exec", "execFile", "execFileSync", "execSync", "fork", "spawn",
  "spawnSync"];
const originals = [];
const sideEffects = [];

for (const [owner, names] of [[fs, FS_MUTATORS], [childProcess, PROCESS_LAUNCHERS]]) {
  for (const name of names) {
    if (typeof owner[name] !== "function") continue;
    originals.push([owner, name, owner[name]]);
    owner[name] = (...args) => {
      sideEffects.push({ name, args });
      throw new Error("side effect attempted during module require: " + name);
    };
  }
}

let Admission;
try {
  delete require.cache[MODULE_PATH];
  Admission = require(MODULE_PATH);
} finally {
  for (const [owner, name, original] of originals) owner[name] = original;
}

const EXPECTED_EXPORTS = Object.freeze([
  "ADMISSION_SCHEMA",
  "CONSENSUS_SCHEMA",
  "CORE_LIBRARY_FILE",
  "DESIGN_ONLY",
  "IMMUTABLE_SOURCE_SCHEMA",
  "INTEGRATION_AVAILABLE",
  "MANIFEST_FILE",
  "PROCESS_IMAGE_FILE",
  "PROMOTION_SCHEMA",
  "STRUCTURAL_SCOPE",
  "VERIFY_SCRIPT",
  "VERIFIER_PROGRAM_FILES",
  "WINDOW_SCHEMA",
  "validateAcceptedProducerBindingShape",
  "validateFormalConsensusAdmissionShape",
  "validateInvocationShape",
  "validatePromotionShape",
  "validateReleaseWindowShape",
  "validateVerifierCommandShape",
]);

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

function hash(label) {
  return crypto.createHash("sha256").update(Buffer.from(String(label), "utf8")).digest("hex");
}

function upperHash(label) {
  return hash(label).toUpperCase();
}

function rehashWithout(value, key) {
  const copy = Object.assign({}, value);
  delete copy[key];
  return hashBuffer(Buffer.from(canonicalJson(copy), "utf8"));
}

function hashBuffer(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function outputDescriptor(text) {
  const bytes = Buffer.from(text, "utf8");
  return { base64: bytes.toString("base64"), bytes: bytes.length, sha256: hashBuffer(bytes) };
}

function fixture() {
  const canonicalRoot = path.win32.normalize(path.win32.join(__dirname, "..", "..", ".."));
  const sourceCommitOid = hash("source-commit");
  const releaseTreeOid = hash("release-tree");
  const files = {};
  let ordinal = 1;
  for (const [name, expected] of Object.entries(Admission.VERIFIER_PROGRAM_FILES)) {
    files[name] = {
      locator: "root:" + expected.relativePath,
      relativePath: expected.relativePath,
      bytes: 1000 + ordinal,
      sha256: hash("window-" + name),
    };
    ordinal += 1;
  }
  const extraFiles = {
    consensus: "config/build/runtime-release-consensus.json",
    manifest: Admission.MANIFEST_FILE,
    coreLibrary: Admission.CORE_LIBRARY_FILE,
    processImage: Admission.PROCESS_IMAGE_FILE,
  };
  for (const [name, relativePath] of Object.entries(extraFiles)) {
    files[name] = {
      locator: "root:" + relativePath,
      relativePath,
      bytes: 2000 + ordinal,
      sha256: hash("window-" + name),
    };
    ordinal += 1;
  }

  const immutableFiles = {};
  for (const [name, expected] of Object.entries(Admission.VERIFIER_PROGRAM_FILES)) {
    immutableFiles[name] = {
      relativePath: expected.relativePath,
      sourceBytes: files[name].bytes,
      sourceSha256: files[name].sha256,
      worktreeBytes: files[name].bytes,
      worktreeSha256: files[name].sha256,
      worktreeCanonicalBytes: files[name].bytes,
      worktreeCanonicalSha256: files[name].sha256,
    };
  }
  const immutableSource = {
    schema: Admission.IMMUTABLE_SOURCE_SCHEMA,
    sourceCommitOid,
    releaseTreeOid,
    files: immutableFiles,
  };
  immutableSource.sourceSha256 = rehashWithout(immutableSource, "sourceSha256");

  const executorPath = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";
  const window = {
    schema: Admission.WINDOW_SCHEMA,
    canonicalRoot,
    executor: { absolutePath: executorPath, bytes: 512000, sha256: hash("powershell") },
    immutableSource,
    files,
  };
  window.windowSha256 = rehashWithout(window, "windowSha256");

  const verifierPath = path.win32.join(canonicalRoot,
    Admission.VERIFY_SCRIPT.replace(/\//g, "\\"));
  const recordPath = path.win32.join(canonicalRoot,
    "config\\build\\runtime-release-consensus.json");
  const command = {
    executable: executorPath,
    args: [
      "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
      verifierPath, "-ProjectRoot", canonicalRoot, "-DeploymentRoot", canonicalRoot,
      "-RecordPath", recordPath,
    ],
    cwd: canonicalRoot,
    encoding: null,
    windowsHide: true,
    timeoutMs: 600000,
    maxBufferBytes: 4 * 1024 * 1024,
  };

  const buildIdentityHash = hash("build-identity");
  const payloadClosureHash = hash("payload-closure");
  const producer = {
    schema: "workbench-live-e2e.crafting.candidate-producer-binding.v2",
    candidateRoot: "E:\\isolated-candidate",
    metadata: {
      locator: "candidate:runtime-build-metadata.v2.json",
      sha256: hash("metadata"), bytes: 4000,
    },
    manifest: {
      locator: "candidate:runtime/cf7-runtime-manifest.tsv",
      sha256: files.manifest.sha256, bytes: files.manifest.bytes,
    },
    builderLabel: "structural-fixture",
    createdAtUtc: "2026-08-14T08:58:00.000Z",
    producerInputsSha256: hash("producer-inputs"),
    artifactSourceHash: hash("artifact-source"),
    producerRecipeHash: hash("producer-recipe"),
    toolchainLockHash: hash("toolchain-lock"),
    buildIdentityHash,
    payloadClosureHash,
    payloadFileCount: 8,
    processImage: {
      locator: "candidate:" + Admission.PROCESS_IMAGE_FILE,
      sha256: files.processImage.sha256, bytes: files.processImage.bytes,
    },
    coreLibrary: {
      locator: "candidate:" + Admission.CORE_LIBRARY_FILE,
      sha256: files.coreLibrary.sha256, bytes: files.coreLibrary.bytes,
    },
  };
  producer.evidenceSha256 = rehashWithout(producer, "evidenceSha256");

  const policyReceiptSha256 = upperHash("policy-receipt");
  const promotion = {
    schema: Admission.PROMOTION_SCHEMA,
    consensusSchema: Admission.CONSENSUS_SCHEMA,
    status: "promoted",
    sourceCommitOid,
    releaseTreeOid,
    sourceTag: "runtime-build-v2/design-structural-v1",
    requestId: upperHash("request"),
    buildIdentityHash: buildIdentityHash.toUpperCase(),
    payloadClosureHash: payloadClosureHash.toUpperCase(),
    processImageSha256: files.processImage.sha256.toUpperCase(),
    coreLibrarySha256: files.coreLibrary.sha256.toUpperCase(),
    policyReceiptSha256,
    consensusSha256: files.consensus.sha256,
    promotedAtUtc: "2026-08-14T09:00:00.000Z",
  };

  const successMarker = "[RuntimeConsensus] OK schema=v2 mode=Worktree signers=2 "
    + "faultDomains=2 payload=" + promotion.payloadClosureHash;
  const invocation = {
    command,
    verifierScriptSha256: files.verifierScript.sha256,
    verifierProgramClosureSha256: immutableSource.sourceSha256,
    executorSha256: window.executor.sha256,
    startedAtUtc: "2026-08-14T09:01:00.000Z",
    completedAtUtc: "2026-08-14T09:02:00.000Z",
    durationMs: 60000,
    exitCode: 0,
    signal: null,
    stdout: outputDescriptor(successMarker + "\n"),
    stderr: outputDescriptor(""),
    successMarker,
  };

  const admission = {
    schema: Admission.ADMISSION_SCHEMA,
    admittedAtUtc: "2026-08-14T09:03:00.000Z",
    status: "promotion_identity_verified",
    scope: "official_consensus_only",
    runId: "formal-consensus-design-01",
    preflightSha256: hash("preflight"),
    preparerInputSha256: hash("preparer-input"),
    invocation,
    window: { before: clone(window), after: clone(window), exactMatch: true },
    source: {
      sourceCommitOid,
      sourceRef: "refs/tags/" + promotion.sourceTag,
      sourceTag: promotion.sourceTag,
    },
    policy: {
      schema: "cf7-runtime-policy-validation.v2",
      profile: "production",
      passed: true,
      artifactSourceHash: producer.artifactSourceHash.toUpperCase(),
      producerRecipeHash: producer.producerRecipeHash.toUpperCase(),
      toolchainLockHash: producer.toolchainLockHash.toUpperCase(),
      toolchainHash: producer.toolchainLockHash.toUpperCase(),
      policyHash: upperHash("policy"),
      candidateRoot: producer.candidateRoot,
      receiptSha256: policyReceiptSha256,
      requiredChecks: [
        "release-tree-materialized", "tracked-tree-readonly", "candidate-payload-readonly",
      ],
    },
    candidate: {
      buildSha256: hash("candidate-build"),
      producerBindingSha256: producer.evidenceSha256,
      buildIdentityHash: promotion.buildIdentityHash,
      payloadClosureHash: promotion.payloadClosureHash,
      processImageSha256: promotion.processImageSha256,
      coreLibrarySha256: promotion.coreLibrarySha256,
    },
    promotion,
    boundaries: {
      officialConsensusVerifierExecuted: true,
      officialConsensusVerified: true,
      verificationWindowStable: true,
      promotionIdentityVerified: true,
      formalApplicabilityCaptured: false,
      formalPlanCreated: false,
      purchaseAuthorityCreated: false,
      formalExecutionAdmitted: false,
      runtimeLaunched: false,
      purchasePerformed: false,
      standardEntryVerified: false,
    },
  };
  admission.admissionSha256 = rehashWithout(admission, "admissionSha256");
  return { producer, window, command, promotion, invocation, admission };
}

function assertStructuralOnly(result, kind) {
  assert.deepEqual(Object.keys(result).sort(), [
    "authorityGranted", "designOnly", "integrationAvailable", "kind", "ok", "scope",
  ]);
  assert.equal(result.ok, true);
  assert.equal(result.kind, kind);
  assert.equal(result.scope, Admission.STRUCTURAL_SCOPE);
  assert.equal(result.designOnly, true);
  assert.equal(result.integrationAvailable, false);
  assert.equal(result.authorityGranted, false);
  assert.equal(Object.hasOwn(result, "value"), false);
}

test("module require is inert and export allowlist is exact", () => {
  assert.deepEqual(sideEffects, []);
  assert.deepEqual(Object.keys(Admission).sort(), EXPECTED_EXPORTS.slice().sort());
  assert.equal(Object.isFrozen(Admission), true);
  assert.equal(Admission.DESIGN_ONLY, true);
  assert.equal(Admission.INTEGRATION_AVAILABLE, false);
  assert.equal(Object.isFrozen(Admission.VERIFIER_PROGRAM_FILES), true);
  assert.equal(Object.values(Admission.VERIFIER_PROGRAM_FILES)
    .every((entry) => Object.isFrozen(entry)), true);
  assert.doesNotMatch(MODULE_SOURCE,
    /require\(["'](?:node:)?(?:fs|child_process)["']\)/);
  for (const forbidden of [
    "buildVerifierCommand", "captureReleaseWindow", "createInvocation", "createPromotion",
    "gitBytes", "parseStrictConsensus", "projectStrictVerifiedConsensus",
    "resolveWindowsPowerShellPath", "runOfficialConsensusAdmission", "stableAdmission",
    "stableWindow", "uniqueGitHubSource",
  ]) {
    assert.equal(Admission[forbidden], undefined, forbidden);
    assert.equal(MODULE_SOURCE.includes("function " + forbidden + "("), false, forbidden);
  }
});

test("accepted producer validator is self-hash and descriptor structural only", () => {
  const fx = fixture();
  assertStructuralOnly(Admission.validateAcceptedProducerBindingShape(fx.producer),
    "accepted_producer_binding_shape");

  const tamper = clone(fx.producer);
  tamper.processImage.sha256 = hash("foreign-process");
  assert.throws(() => Admission.validateAcceptedProducerBindingShape(tamper),
    (error) => error.code === "material_shop_formal_consensus_candidate_shape_invalid");

  const resealed = clone(tamper);
  resealed.evidenceSha256 = rehashWithout(resealed, "evidenceSha256");
  assertStructuralOnly(Admission.validateAcceptedProducerBindingShape(resealed),
    "accepted_producer_binding_shape");
});

test("release window and verifier command enforce frozen structural paths and closure", () => {
  const fx = fixture();
  assertStructuralOnly(Admission.validateReleaseWindowShape(fx.window),
    "release_window_shape");
  assertStructuralOnly(Admission.validateVerifierCommandShape(fx.command),
    "verifier_command_shape");

  const sourceTamper = clone(fx.window);
  sourceTamper.immutableSource.files.verifierScript.worktreeSha256 = hash("foreign-script");
  sourceTamper.immutableSource.sourceSha256 = rehashWithout(
    sourceTamper.immutableSource, "sourceSha256");
  sourceTamper.windowSha256 = rehashWithout(sourceTamper, "windowSha256");
  assert.throws(() => Admission.validateReleaseWindowShape(sourceTamper),
    (error) => error.code === "material_shop_formal_consensus_source_shape_invalid");

  const commandTamper = clone(fx.command);
  commandTamper.args.push("-IntegrityOnly");
  assert.throws(() => Admission.validateVerifierCommandShape(commandTamper),
    (error) => error.code === "material_shop_formal_consensus_command_shape_invalid");
});

test("invocation validator binds canonical base64 output, marker quorum, payload, and window", () => {
  const fx = fixture();
  assertStructuralOnly(Admission.validateInvocationShape(
    fx.invocation, fx.window, fx.promotion.payloadClosureHash),
  "verifier_invocation_shape");

  const lowQuorum = clone(fx.invocation);
  lowQuorum.successMarker = lowQuorum.successMarker.replace("signers=2", "signers=1");
  lowQuorum.stdout = outputDescriptor(lowQuorum.successMarker + "\n");
  assert.throws(() => Admission.validateInvocationShape(
    lowQuorum, fx.window, fx.promotion.payloadClosureHash),
  (error) => error.code === "material_shop_formal_consensus_invocation_shape_invalid");

  const detachedOutput = clone(fx.invocation);
  detachedOutput.stdout.base64 += "=";
  assert.throws(() => Admission.validateInvocationShape(
    detachedOutput, fx.window, fx.promotion.payloadClosureHash),
  (error) => error.code === "material_shop_formal_consensus_invocation_shape_invalid");

  assert.throws(() => Admission.validateInvocationShape(
    fx.invocation, fx.window, upperHash("foreign-payload")),
  (error) => error.code === "material_shop_formal_consensus_invocation_shape_invalid");
});

test("promotion validator accepts shape without granting promotion authority", () => {
  const fx = fixture();
  assertStructuralOnly(Admission.validatePromotionShape(fx.promotion), "promotion_shape");

  const tamper = clone(fx.promotion);
  tamper.status = "candidate_built";
  assert.throws(() => Admission.validatePromotionShape(tamper),
    (error) => error.code === "material_shop_formal_promotion_shape_invalid");
});

test("formal admission validator rejects cross-binding and boundary overclaim tamper", () => {
  const fx = fixture();
  assertStructuralOnly(Admission.validateFormalConsensusAdmissionShape(
    fx.admission, fx.producer), "formal_consensus_admission_shape");

  const candidateTamper = clone(fx.admission);
  candidateTamper.candidate.processImageSha256 = upperHash("foreign-process");
  candidateTamper.admissionSha256 = rehashWithout(candidateTamper, "admissionSha256");
  assert.throws(() => Admission.validateFormalConsensusAdmissionShape(
    candidateTamper, fx.producer),
  (error) => error.code === "material_shop_formal_consensus_admission_shape_invalid");

  const boundaryTamper = clone(fx.admission);
  boundaryTamper.boundaries.runtimeLaunched = true;
  boundaryTamper.admissionSha256 = rehashWithout(boundaryTamper, "admissionSha256");
  assert.throws(() => Admission.validateFormalConsensusAdmissionShape(
    boundaryTamper, fx.producer),
  (error) => error.code === "material_shop_formal_consensus_admission_shape_invalid");

  const windowTamper = clone(fx.admission);
  windowTamper.window.before.files.manifest.sha256 = hash("foreign-manifest");
  windowTamper.window.before.windowSha256 = rehashWithout(
    windowTamper.window.before, "windowSha256");
  windowTamper.admissionSha256 = rehashWithout(windowTamper, "admissionSha256");
  assert.throws(() => Admission.validateFormalConsensusAdmissionShape(
    windowTamper, fx.producer),
  (error) => error.code === "material_shop_formal_consensus_admission_shape_invalid");
});
