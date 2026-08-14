"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const MODULE_PATH = require.resolve("./formal-execution-lease");
const FS_MUTATORS = [
  "appendFileSync", "chmodSync", "chownSync", "copyFileSync", "cpSync",
  "createWriteStream", "fchmodSync", "fchownSync", "fdatasyncSync", "fsyncSync",
  "ftruncateSync", "futimesSync", "linkSync", "lutimesSync", "mkdirSync",
  "mkdtempSync", "openSync", "renameSync", "rmSync", "rmdirSync", "symlinkSync",
  "truncateSync", "unlinkSync", "utimesSync", "writeFileSync", "writeSync",
];
const originalMutators = new Map();
const attemptedWrites = [];

for (const name of FS_MUTATORS) {
  if (typeof fs[name] !== "function") continue;
  originalMutators.set(name, fs[name]);
  fs[name] = (...args) => {
    attemptedWrites.push({ name, args });
    throw new Error("filesystem mutation attempted during module require: " + name);
  };
}

let FormalExecution;
try {
  delete require.cache[MODULE_PATH];
  FormalExecution = require(MODULE_PATH);
} finally {
  for (const [name, original] of originalMutators) fs[name] = original;
}

const EXPECTED_EXPORTS = Object.freeze([
  "ADMISSION_BINDING_SCHEMA",
  "ADMISSION_NAME",
  "ADMISSION_SCHEMA",
  "DESIGN_ONLY",
  "DURABILITY_SCOPE",
  "FORMAL_RUNS_DIRECTORY",
  "INTEGRATION_AVAILABLE",
  "LEASE_NAME",
  "LEASE_SCHEMA",
  "MODE",
  "OUTCOME_NAME",
  "STRUCTURAL_SCOPE",
  "exactFormalRunDirectory",
  "expectedFormalRunDirectory",
  "validateAdmissionArtifactBindingShape",
  "validateAdmissionTokenShape",
  "validateLeaseShape",
  "validateOutcomeShape",
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

function sha256Text(value) {
  return crypto.createHash("sha256").update(Buffer.from(String(value), "utf8")).digest("hex");
}

function sha(character) {
  return character.repeat(64);
}

function rehashWithout(value, key) {
  const copy = Object.assign({}, value);
  delete copy[key];
  return sha256Text(canonicalJson(copy));
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function fixture() {
  const runId = "formal-a5-design-01";
  const formalRunDir = FormalExecution.expectedFormalRunDirectory(runId);
  const token = {
    schema: FormalExecution.ADMISSION_SCHEMA,
    admittedAt: "2026-08-14T09:00:00.000Z",
    status: "admitted",
    runId,
    formalRunDir,
    preflightSha256: sha("1"),
    formalPlanSha256: sha("2"),
    promotionVerificationSha256: sha("3"),
    applicabilityVerificationSha256: sha("4"),
    authorizationDecisionSha256: sha("5"),
    oneShotExecution: true,
  };
  token.admissionSha256 = rehashWithout(token, "admissionSha256");

  const tokenBytes = Buffer.from(JSON.stringify(token, null, 2) + "\n", "utf8");
  const artifact = {
    bytes: tokenBytes.length,
    sha256: crypto.createHash("sha256").update(tokenBytes).digest("hex"),
  };
  const binding = {
    schema: FormalExecution.ADMISSION_BINDING_SCHEMA,
    verifiedAt: "2026-08-14T09:00:30.000Z",
    authority: "validated_formal_admission_chain",
    runId,
    formalRunDir,
    preflightSha256: token.preflightSha256,
    formalPlanSha256: token.formalPlanSha256,
    promotionVerificationSha256: token.promotionVerificationSha256,
    applicabilityVerificationSha256: token.applicabilityVerificationSha256,
    authorizationDecisionSha256: token.authorizationDecisionSha256,
    admissionSha256: token.admissionSha256,
    admissionArtifactBytes: artifact.bytes,
    admissionArtifactSha256: artifact.sha256,
  };
  binding.bindingSha256 = rehashWithout(binding, "bindingSha256");

  const executionIdentitySha256 = sha256Text(canonicalJson({
    admissionSha256: token.admissionSha256,
    admissionArtifactSha256: artifact.sha256,
    admissionBindingSha256: binding.bindingSha256,
    formalPlanSha256: token.formalPlanSha256,
    promotionVerificationSha256: token.promotionVerificationSha256,
    applicabilityVerificationSha256: token.applicabilityVerificationSha256,
    authorizationDecisionSha256: token.authorizationDecisionSha256,
  }));
  const lease = {
    schema: FormalExecution.LEASE_SCHEMA,
    consumedAt: "2026-08-14T09:01:00.000Z",
    runId,
    formalRunDir,
    mode: FormalExecution.MODE,
    admissionSha256: token.admissionSha256,
    admissionArtifactBytes: artifact.bytes,
    admissionArtifactSha256: artifact.sha256,
    admissionBindingSha256: binding.bindingSha256,
    formalPlanSha256: token.formalPlanSha256,
    promotionVerificationSha256: token.promotionVerificationSha256,
    applicabilityVerificationSha256: token.applicabilityVerificationSha256,
    authorizationDecisionSha256: token.authorizationDecisionSha256,
    executionIdentitySha256,
    ownerPid: 42001,
    ownerProcessStartUtcTicks: "638591040000000000",
    ownerNonceSha256: sha("6"),
    oneShot: true,
    durabilityScope: FormalExecution.DURABILITY_SCOPE,
  };
  lease.leaseSha256 = rehashWithout(lease, "leaseSha256");
  return { runId, formalRunDir, token, artifact, binding, lease };
}

function assertStructuralOnly(result, kind) {
  assert.equal(result.ok, true);
  assert.equal(result.kind, kind);
  assert.equal(result.scope, FormalExecution.STRUCTURAL_SCOPE);
  assert.equal(result.designOnly, true);
  assert.equal(result.integrationAvailable, false);
  assert.equal(result.authorityGranted, false);
}

test("require is write-free and exports only the frozen design-only surface", () => {
  assert.deepEqual(attemptedWrites, []);
  assert.deepEqual(Object.keys(FormalExecution).sort(), EXPECTED_EXPORTS.slice().sort());
  assert.equal(Object.isFrozen(FormalExecution), true);
  assert.equal(FormalExecution.DESIGN_ONLY, true);
  assert.equal(FormalExecution.INTEGRATION_AVAILABLE, false);
  assert.equal(FormalExecution.DURABILITY_SCOPE,
    "design_only_no_runtime_durability_claim");

  for (const forbidden of [
    "acquire", "createAdmissionBinding", "createAdmissionToken", "createLease",
    "createRuntimeQuiescenceReceipt", "createTestHarness", "linkOutcomeNew",
    "ownerState", "processStartProbe", "publishVerifiedAdmission", "readAdmission",
    "readExecutionState", "release", "resolveStale", "runtimeQuiescence",
    "validateQuiescenceReceipt", "writeFileNew",
  ]) {
    assert.equal(FormalExecution[forbidden], undefined, forbidden);
  }
  assert.equal(Object.keys(FormalExecution).some((name) => /^(?:read|publish|create)/.test(name)),
    false);
});

test("production formal-run path is pinned without root or owned-base override", () => {
  const repoRoot = path.resolve(__dirname, "..", "..", "..");
  const runId = "formal-a5-design-01";
  const expected = path.join(repoRoot, "tmp", "workbench-live-e2e", "material-shop",
    FormalExecution.FORMAL_RUNS_DIRECTORY, runId);
  assert.equal(FormalExecution.expectedFormalRunDirectory(runId), expected);
  assert.equal(FormalExecution.exactFormalRunDirectory(expected, runId), expected);
  assert.throws(() => FormalExecution.exactFormalRunDirectory(
    path.join(repoRoot, "tmp", "elsewhere", runId), runId),
  (error) => error.code === "material_shop_formal_execution_path_invalid");
  for (const invalid of ["", ".", "..", "trailing.", "a/b", "a\\b"] ) {
    assert.throws(() => FormalExecution.expectedFormalRunDirectory(invalid),
      (error) => error.code === "material_shop_formal_execution_path_invalid");
  }
});

test("admission token and artifact binding validators are structural and tamper-closed", () => {
  const fx = fixture();
  const tokenResult = FormalExecution.validateAdmissionTokenShape(fx.token);
  assertStructuralOnly(tokenResult, "admission_token_shape");
  assert.equal(Object.hasOwn(tokenResult, "value"), false);

  const bindingResult = FormalExecution.validateAdmissionArtifactBindingShape(
    fx.binding, fx.token, fx.artifact);
  assertStructuralOnly(bindingResult, "admission_artifact_binding_shape");

  const tokenTamper = clone(fx.token);
  tokenTamper.formalPlanSha256 = sha("f");
  assert.throws(() => FormalExecution.validateAdmissionTokenShape(tokenTamper),
    (error) => error.code === "material_shop_formal_admission_shape_invalid");

  const resealedToken = clone(tokenTamper);
  resealedToken.admissionSha256 = rehashWithout(resealedToken, "admissionSha256");
  assert.throws(() => FormalExecution.validateAdmissionArtifactBindingShape(
    fx.binding, resealedToken, fx.artifact),
  (error) => error.code === "material_shop_formal_admission_binding_shape_invalid");

  const bindingTamper = clone(fx.binding);
  bindingTamper.admissionArtifactSha256 = sha("e");
  bindingTamper.bindingSha256 = rehashWithout(bindingTamper, "bindingSha256");
  assert.throws(() => FormalExecution.validateAdmissionArtifactBindingShape(
    bindingTamper, fx.token, fx.artifact),
  (error) => error.code === "material_shop_formal_admission_binding_shape_invalid");
  assert.throws(() => FormalExecution.validateAdmissionArtifactBindingShape(
    fx.binding, fx.token),
  (error) => error.code === "material_shop_formal_admission_artifact_shape_invalid");
});

test("lease and unified outcome validators reject structural and cross-binding tamper", () => {
  const fx = fixture();
  const leaseResult = FormalExecution.validateLeaseShape(
    fx.lease, fx.token, fx.binding, fx.artifact);
  assertStructuralOnly(leaseResult, "execution_lease_shape");

  const bindingTamper = clone(fx.lease);
  bindingTamper.admissionBindingSha256 = sha("e");
  bindingTamper.leaseSha256 = rehashWithout(bindingTamper, "leaseSha256");
  assert.throws(() => FormalExecution.validateLeaseShape(
    bindingTamper, fx.token, fx.binding, fx.artifact),
  (error) => error.code === "material_shop_formal_execution_lease_shape_invalid");

  const durabilityOverclaim = clone(fx.lease);
  durabilityOverclaim.durabilityScope =
    "process_race_and_process_crash_only_no_machine_power_loss_claim";
  durabilityOverclaim.leaseSha256 = rehashWithout(durabilityOverclaim, "leaseSha256");
  assert.throws(() => FormalExecution.validateLeaseShape(
    durabilityOverclaim, fx.token, fx.binding, fx.artifact),
  (error) => error.code === "material_shop_formal_execution_lease_shape_invalid");

  const outcome = clone(fx.lease);
  const outcomeResult = FormalExecution.validateOutcomeShape(
    outcome, fx.lease, fx.token, fx.binding, fx.artifact);
  assertStructuralOnly(outcomeResult, "execution_outcome_shape");

  const foreignOutcome = clone(fx.lease);
  foreignOutcome.ownerPid += 1;
  foreignOutcome.leaseSha256 = rehashWithout(foreignOutcome, "leaseSha256");
  assert.throws(() => FormalExecution.validateOutcomeShape(
    foreignOutcome, fx.lease, fx.token, fx.binding, fx.artifact),
  (error) => error.code === "material_shop_formal_execution_outcome_shape_invalid");
});
