"use strict";

// This module intentionally describes artifact shapes only. It is not connected to
// the formal runner and grants no execution, admission, lease, or outcome authority.

const crypto = require("node:crypto");
const path = require("node:path");

const DESIGN_ONLY = true;
const INTEGRATION_AVAILABLE = false;
const STRUCTURAL_SCOPE = "design_only_structural_validation_no_runtime_authority";

const FORMAL_RUNS_DIRECTORY = "formal-runs";
const ADMISSION_NAME = "formal-admission.json";
const ADMISSION_SCHEMA = "workbench-live-e2e.material-shop.formal-admission.v1";
const ADMISSION_BINDING_SCHEMA =
  "workbench-live-e2e.material-shop.formal-admission-artifact-binding.v1";
const LEASE_NAME = "formal-execution-lease.json";
const LEASE_SCHEMA = "workbench-live-e2e.material-shop.formal-execution-lease.v2";
const OUTCOME_NAME = "formal-execution-outcome.json";
const MODE = "formal_execution";
const DURABILITY_SCOPE = "design_only_no_runtime_durability_claim";

const CANONICAL_ROOT = path.resolve(__dirname, "..", "..", "..");
const OWNED_BASE_RELATIVE = path.join("tmp", "workbench-live-e2e", "material-shop");
const RUN_ID_RE = /^[A-Za-z0-9_~-][A-Za-z0-9._~-]{0,159}$/;
const SHA256_RE = /^[a-f0-9]{64}$/;
const PROCESS_START_TICKS_RE = /^\d{12,20}$/;

const ADMISSION_KEYS = Object.freeze([
  "schema", "admittedAt", "status", "runId", "formalRunDir", "preflightSha256",
  "formalPlanSha256", "promotionVerificationSha256",
  "applicabilityVerificationSha256", "authorizationDecisionSha256",
  "oneShotExecution", "admissionSha256",
]);
const ADMISSION_BINDING_KEYS = Object.freeze([
  "schema", "verifiedAt", "authority", "runId", "formalRunDir",
  "preflightSha256", "formalPlanSha256", "promotionVerificationSha256",
  "applicabilityVerificationSha256", "authorizationDecisionSha256",
  "admissionSha256", "admissionArtifactBytes", "admissionArtifactSha256",
  "bindingSha256",
]);
const ARTIFACT_KEYS = Object.freeze(["bytes", "sha256"]);
const LEASE_KEYS = Object.freeze([
  "schema", "consumedAt", "runId", "formalRunDir", "mode", "admissionSha256",
  "admissionArtifactBytes", "admissionArtifactSha256", "admissionBindingSha256",
  "formalPlanSha256", "promotionVerificationSha256",
  "applicabilityVerificationSha256", "authorizationDecisionSha256",
  "executionIdentitySha256", "ownerPid", "ownerProcessStartUtcTicks",
  "ownerNonceSha256", "oneShot", "durabilityScope", "leaseSha256",
]);

class StructuralContractError extends Error {
  constructor(code, message, details) {
    super(message);
    this.name = "StructuralContractError";
    this.code = code;
    this.phase = "formal_execution_lease_design_only";
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

function sha256Text(value) {
  return crypto.createHash("sha256").update(Buffer.from(String(value), "utf8")).digest("hex");
}

function digestWithout(value, key) {
  const copy = Object.assign({}, value);
  delete copy[key];
  return sha256Text(canonicalJson(copy));
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

function validDate(value) {
  return typeof value === "string" && value.length > 0
    && Number.isFinite(Date.parse(value));
}

function validRunId(value) {
  return typeof value === "string" && RUN_ID_RE.test(value) && !value.endsWith(".");
}

function samePath(left, right) {
  return typeof left === "string" && typeof right === "string"
    && path.isAbsolute(left) && path.isAbsolute(right)
    && path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
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

function expectedFormalRunDirectory(runId) {
  if (!validRunId(runId)) {
    fail("material_shop_formal_execution_path_invalid",
      "formal execution design requires one closed run id");
  }
  return path.join(CANONICAL_ROOT, OWNED_BASE_RELATIVE,
    FORMAL_RUNS_DIRECTORY, runId);
}

function exactFormalRunDirectory(runDir, runId) {
  const expected = expectedFormalRunDirectory(runId);
  if (!samePath(runDir, expected) || path.basename(path.resolve(runDir)) !== runId) {
    fail("material_shop_formal_execution_path_invalid",
      "path is not the pinned canonical formal-runs/<runId> design path", {
        expected, actual: runDir,
      });
  }
  return expected;
}

function validateAdmissionTokenCore(value) {
  exactKeys(value, ADMISSION_KEYS, "material_shop_formal_admission_shape_invalid",
    "formal admission token");
  const expectedRunDir = validRunId(value.runId)
    ? expectedFormalRunDirectory(value.runId) : null;
  const digests = [value.preflightSha256, value.formalPlanSha256,
    value.promotionVerificationSha256, value.applicabilityVerificationSha256,
    value.authorizationDecisionSha256];
  if (value.schema !== ADMISSION_SCHEMA || value.status !== "admitted"
      || !validDate(value.admittedAt) || !validRunId(value.runId)
      || !samePath(value.formalRunDir, expectedRunDir)
      || digests.some((entry) => !SHA256_RE.test(String(entry || "")))
      || value.oneShotExecution !== true
      || value.admissionSha256 !== digestWithout(value, "admissionSha256")) {
    fail("material_shop_formal_admission_shape_invalid",
      "formal admission token fails the design-only structural contract");
  }
  return value;
}

function validateAdmissionTokenShape(value) {
  validateAdmissionTokenCore(value);
  return structuralResult("admission_token_shape");
}

function validateArtifactDescriptor(value) {
  exactKeys(value, ARTIFACT_KEYS,
    "material_shop_formal_admission_artifact_shape_invalid", "admission artifact");
  if (!Number.isSafeInteger(value.bytes) || value.bytes < 1
      || !SHA256_RE.test(String(value.sha256 || ""))) {
    fail("material_shop_formal_admission_artifact_shape_invalid",
      "admission artifact descriptor fails the design-only structural contract");
  }
  return value;
}

function validateAdmissionBindingCore(value, token, artifact) {
  validateAdmissionTokenCore(token);
  validateArtifactDescriptor(artifact);
  exactKeys(value, ADMISSION_BINDING_KEYS,
    "material_shop_formal_admission_binding_shape_invalid", "formal admission binding");
  const digests = [value.preflightSha256, value.formalPlanSha256,
    value.promotionVerificationSha256, value.applicabilityVerificationSha256,
    value.authorizationDecisionSha256, value.admissionSha256,
    value.admissionArtifactSha256];
  if (value.schema !== ADMISSION_BINDING_SCHEMA
      || value.authority !== "validated_formal_admission_chain"
      || !validDate(value.verifiedAt)
      || Date.parse(value.verifiedAt) < Date.parse(token.admittedAt)
      || value.runId !== token.runId || !samePath(value.formalRunDir, token.formalRunDir)
      || value.preflightSha256 !== token.preflightSha256
      || value.formalPlanSha256 !== token.formalPlanSha256
      || value.promotionVerificationSha256 !== token.promotionVerificationSha256
      || value.applicabilityVerificationSha256 !== token.applicabilityVerificationSha256
      || value.authorizationDecisionSha256 !== token.authorizationDecisionSha256
      || value.admissionSha256 !== token.admissionSha256
      || digests.some((entry) => !SHA256_RE.test(String(entry || "")))
      || value.admissionArtifactBytes !== artifact.bytes
      || value.admissionArtifactSha256 !== artifact.sha256
      || value.bindingSha256 !== digestWithout(value, "bindingSha256")) {
    fail("material_shop_formal_admission_binding_shape_invalid",
      "formal admission binding fails structural cross-binding; no authority is inferred");
  }
  return value;
}

function validateAdmissionArtifactBindingShape(value, token, artifact) {
  validateAdmissionBindingCore(value, token, artifact);
  return structuralResult("admission_artifact_binding_shape");
}

function expectedExecutionIdentity(token, binding, artifact) {
  return sha256Text(canonicalJson({
    admissionSha256: token.admissionSha256,
    admissionArtifactSha256: artifact.sha256,
    admissionBindingSha256: binding.bindingSha256,
    formalPlanSha256: token.formalPlanSha256,
    promotionVerificationSha256: token.promotionVerificationSha256,
    applicabilityVerificationSha256: token.applicabilityVerificationSha256,
    authorizationDecisionSha256: token.authorizationDecisionSha256,
  }));
}

function validateLeaseCore(value, token, binding, artifact) {
  validateAdmissionBindingCore(binding, token, artifact);
  exactKeys(value, LEASE_KEYS, "material_shop_formal_execution_lease_shape_invalid",
    "formal execution lease");
  const expectedRunDir = validRunId(value.runId)
    ? expectedFormalRunDirectory(value.runId) : null;
  const digests = [value.admissionSha256, value.admissionArtifactSha256,
    value.admissionBindingSha256, value.formalPlanSha256,
    value.promotionVerificationSha256, value.applicabilityVerificationSha256,
    value.authorizationDecisionSha256, value.executionIdentitySha256,
    value.ownerNonceSha256];
  if (value.schema !== LEASE_SCHEMA || value.mode !== MODE
      || !validDate(value.consumedAt)
      || Date.parse(value.consumedAt) < Date.parse(binding.verifiedAt)
      || !validRunId(value.runId) || !samePath(value.formalRunDir, expectedRunDir)
      || digests.some((entry) => !SHA256_RE.test(String(entry || "")))
      || !Number.isSafeInteger(value.admissionArtifactBytes)
      || value.admissionArtifactBytes < 1
      || !Number.isInteger(value.ownerPid) || value.ownerPid < 1
      || !PROCESS_START_TICKS_RE.test(String(value.ownerProcessStartUtcTicks || ""))
      || value.oneShot !== true || value.durabilityScope !== DURABILITY_SCOPE
      || value.leaseSha256 !== digestWithout(value, "leaseSha256")
      || value.runId !== token.runId || !samePath(value.formalRunDir, token.formalRunDir)
      || value.admissionSha256 !== token.admissionSha256
      || value.admissionArtifactBytes !== artifact.bytes
      || value.admissionArtifactSha256 !== artifact.sha256
      || value.admissionBindingSha256 !== binding.bindingSha256
      || value.formalPlanSha256 !== token.formalPlanSha256
      || value.promotionVerificationSha256 !== token.promotionVerificationSha256
      || value.applicabilityVerificationSha256 !== token.applicabilityVerificationSha256
      || value.authorizationDecisionSha256 !== token.authorizationDecisionSha256
      || value.executionIdentitySha256 !== expectedExecutionIdentity(token, binding, artifact)) {
    fail("material_shop_formal_execution_lease_shape_invalid",
      "formal execution lease fails structural cross-binding; it is not an acquired lease");
  }
  return value;
}

function validateLeaseShape(value, token, binding, artifact) {
  validateLeaseCore(value, token, binding, artifact);
  return structuralResult("execution_lease_shape");
}

function validateOutcomeShape(value, lease, token, binding, artifact) {
  validateLeaseCore(lease, token, binding, artifact);
  validateLeaseCore(value, token, binding, artifact);
  if (canonicalJson(value) !== canonicalJson(lease)) {
    fail("material_shop_formal_execution_outcome_shape_invalid",
      "outcome is not the exact unified lease shape; hardlink identity is not evaluated here");
  }
  return structuralResult("execution_outcome_shape");
}

module.exports = Object.freeze({
  ADMISSION_BINDING_SCHEMA,
  ADMISSION_NAME,
  ADMISSION_SCHEMA,
  DESIGN_ONLY,
  DURABILITY_SCOPE,
  FORMAL_RUNS_DIRECTORY,
  INTEGRATION_AVAILABLE,
  LEASE_NAME,
  LEASE_SCHEMA,
  MODE,
  OUTCOME_NAME,
  STRUCTURAL_SCOPE,
  exactFormalRunDirectory,
  expectedFormalRunDirectory,
  validateAdmissionArtifactBindingShape,
  validateAdmissionTokenShape,
  validateLeaseShape,
  validateOutcomeShape,
});
