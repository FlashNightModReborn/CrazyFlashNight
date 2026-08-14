"use strict";

const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const Common = require("./common");

const ENVIRONMENT_RECEIPT_SCHEMA =
  "workbench-live-e2e.material-shop.environment-operator-attestation.v1";
const CANDIDATE_RECEIPT_SCHEMA =
  "workbench-live-e2e.material-shop.candidate-ui-operator-attestation.v1";
const CANDIDATE_REQUEST_SCHEMA = "workbench-live-e2e.material-shop.candidate-ui-request.v1";
const CANDIDATE_ADMISSION_SCHEMA = "workbench-live-e2e.material-shop.candidate-ui-admission.v1";
const CANDIDATE_ADMISSION_BUNDLE_SCHEMA = "workbench-live-e2e.material-shop.candidate-ui-admission-bundle.v1";
const OPERATOR_ISSUER = "operator_attested_computer_use";
const OPERATOR_TRUST_BOUNDARY =
  "operator_attested_external_result_not_cryptographically_or_independently_verified";

function validateRawOperationArtifact(value, phase) {
  Common.exactKeys(value, ["sourcePath", "sourceLastWriteUtc", "bytes", "sha256",
    "contentBase64"], "material_shop_raw_operation_artifact_invalid", phase);
  let decoded;
  try { decoded = Buffer.from(String(value.contentBase64 || ""), "base64"); }
  catch (_error) { decoded = Buffer.alloc(0); }
  let current;
  let stat;
  try {
    current = Evidence.readExactRegularFile(path.resolve(value.sourcePath), {
      phase, maximumBytes: 16 * 1024 * 1024,
    });
    stat = fs.statSync(current.path);
  } catch (_error) {
    Common.fail("material_shop_raw_operation_artifact_invalid", phase,
      "operator-attested raw operation artifact is not readable");
  }
  if (!Number.isFinite(Date.parse(value.sourceLastWriteUtc))
      || value.sourceLastWriteUtc !== stat.mtime.toISOString()
      || !Number.isInteger(value.bytes) || value.bytes < 1 || value.bytes !== decoded.length
      || value.bytes !== current.length || !Common.SHA256_RE.test(String(value.sha256 || ""))
      || value.sha256 !== Evidence.sha256Bytes(decoded) || value.sha256 !== current.sha256) {
    Common.fail("material_shop_raw_operation_artifact_invalid", phase,
      "raw Computer Use artifact bytes, digest, or mtime differ from the attestation");
  }
  return value;
}

function captureRawOperationArtifact(sourcePathValue) {
  const sourcePath = path.resolve(sourcePathValue);
  const file = Evidence.readExactRegularFile(sourcePath, {
    phase: "operator_attestation", maximumBytes: 16 * 1024 * 1024,
  });
  const stat = fs.statSync(file.path);
  return { sourcePath: file.path, sourceLastWriteUtc: stat.mtime.toISOString(),
    bytes: file.length, sha256: file.sha256, contentBase64: file.bytes.toString("base64") };
}

function readJson(filePath, phase) {
  const file = Evidence.readExactRegularFile(path.resolve(filePath), {
    phase: phase || "admission", maximumBytes: 4 * 1024 * 1024,
  });
  let value;
  try { value = JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) { Common.fail("material_shop_admission_json_invalid", phase || "admission", error.message); }
  return value;
}

function writeJsonNew(filePath, value) {
  fs.writeFileSync(path.resolve(filePath), JSON.stringify(value, null, 2) + "\n", {
    encoding: "utf8", mode: 0o600, flag: "wx",
  });
  return value;
}

function validateProviderBase(value, schema, phase) {
  if (!Evidence.isPlainObject(value) || value.schema !== schema
      || value.issuer !== OPERATOR_ISSUER
      || !Common.ID_RE.test(String(value.operationId || ""))
      || !Number.isFinite(Date.parse(value.observedAt))
      || value.businessApiCalls !== 0
      || value.trustBoundary !== OPERATOR_TRUST_BOUNDARY
      || value.independentlyVerifiable !== false) {
    Common.fail("material_shop_provider_receipt_invalid", phase,
      "operator Computer Use attestation is malformed or overstates its trust boundary");
  }
  validateRawOperationArtifact(value.rawOperationArtifact, phase);
  return value;
}

function createEnvironmentCapability(receipt) {
  Common.exactKeys(receipt, ["schema", "issuer", "operationId", "observedAt", "available",
    "toolName", "businessApiCalls", "rawOperationArtifact", "trustBoundary",
    "independentlyVerifiable", "nativeInputVisibleClaim"],
  "material_shop_environment_receipt_invalid", "environment_preflight");
  validateProviderBase(receipt, ENVIRONMENT_RECEIPT_SCHEMA, "environment_preflight");
  const observed = Date.parse(receipt.observedAt);
  const sourceLastWrite = Date.parse(receipt.rawOperationArtifact.sourceLastWriteUtc);
  if (typeof receipt.available !== "boolean" || receipt.toolName !== "computer-use"
      || receipt.nativeInputVisibleClaim !== false
      || sourceLastWrite > observed || observed - sourceLastWrite > 15 * 60 * 1000) {
    Common.fail("material_shop_environment_receipt_invalid", "environment_preflight",
      "environment attestation is stale, or claims more than tool availability");
  }
  const artifact = JSON.parse(JSON.stringify(receipt));
  return { available: receipt.available, source: "operator_attested_computer_use_environment",
    artifact,
    artifactSha256: Evidence.sha256Text(Evidence.canonicalJson(artifact)) };
}

function validateEnvironmentCapability(value) {
  Common.exactKeys(value, ["available", "source", "artifact", "artifactSha256"],
    "material_shop_capability_invalid", "environment_preflight");
  if (value.source !== "operator_attested_computer_use_environment"
      || !Evidence.isPlainObject(value.artifact)) {
    Common.fail("material_shop_capability_invalid", "environment_preflight",
      "environment capability must contain one explicit operator Computer Use attestation");
  }
  const expected = createEnvironmentCapability(value.artifact);
  if (Evidence.canonicalJson(value) !== Evidence.canonicalJson(expected)) {
    Common.fail("material_shop_capability_invalid", "environment_preflight",
      "environment capability differs from its raw-artifact-bound operator attestation");
  }
  return value;
}

function createCandidateRequest(options) {
  const settings = options || {};
  const identity = settings.candidateIdentity;
  if (!Evidence.isPlainObject(identity) || !Number.isInteger(Number(identity.pid))
      || Number(identity.pid) < 1) {
    Common.fail("material_shop_candidate_identity_invalid", "candidate_admission",
      "candidate UI request requires an authenticated running candidate identity");
  }
  const value = { schema: CANDIDATE_REQUEST_SCHEMA, runId: String(settings.runId || ""),
    planSha256: String(settings.planSha256 || ""), issuedAt: new Date().toISOString(),
    candidateIdentity: JSON.parse(JSON.stringify(identity)),
    instructions: "Use Computer Use on the exact candidate window and retain the raw tool result. This is operator-attested input, not cryptographic proof; do not call Bridge, Panels, CDP, or application APIs." };
  if (!Common.ID_RE.test(value.runId) || !Common.SHA256_RE.test(value.planSha256)) {
    Common.fail("material_shop_candidate_request_invalid", "candidate_admission",
      "candidate UI request is detached from the run plan");
  }
  value.requestSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function validateCandidateAdmission(request, receipt, value) {
  Common.exactKeys(request, ["schema", "runId", "planSha256", "issuedAt",
    "candidateIdentity", "instructions", "requestSha256"],
  "material_shop_candidate_request_invalid", "candidate_admission");
  const unsignedRequest = Object.assign({}, request);
  delete unsignedRequest.requestSha256;
  if (request.schema !== CANDIDATE_REQUEST_SCHEMA
      || request.requestSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsignedRequest))) {
    Common.fail("material_shop_candidate_request_invalid", "candidate_admission",
      "candidate UI request digest is invalid");
  }
  Common.exactKeys(receipt, ["schema", "issuer", "operationId", "observedAt", "available",
    "runId", "planSha256", "requestSha256", "candidateIdentitySha256", "pid", "window",
    "attestedNativeInputVisible", "businessApiCalls", "rawOperationArtifact",
    "trustBoundary", "independentlyVerifiable", "independentEvidenceRequired"],
  "material_shop_candidate_receipt_invalid", "candidate_admission");
  validateProviderBase(receipt, CANDIDATE_RECEIPT_SCHEMA, "candidate_admission");
  Common.exactKeys(receipt.window, ["handle", "title", "visible"],
    "material_shop_candidate_window_invalid", "candidate_admission");
  const pid = Number(request.candidateIdentity.pid);
  const identitySha256 = Evidence.sha256Text(Evidence.canonicalJson(request.candidateIdentity));
  const observed = Date.parse(receipt.observedAt);
  const issued = Date.parse(request.issuedAt);
  if (receipt.available !== true || receipt.runId !== request.runId
      || receipt.planSha256 !== request.planSha256
      || receipt.requestSha256 !== request.requestSha256
      || receipt.candidateIdentitySha256 !== identitySha256
      || receipt.pid !== pid || receipt.attestedNativeInputVisible !== true
      || observed < issued || observed - issued > 15 * 60 * 1000
      || !Common.ID_RE.test(String(receipt.window.handle || ""))
      || typeof receipt.window.title !== "string" || receipt.window.title.length < 1
      || receipt.window.visible !== true
      || receipt.independentEvidenceRequired !== true
      || Date.parse(receipt.rawOperationArtifact.sourceLastWriteUtc) < issued
      || Date.parse(receipt.rawOperationArtifact.sourceLastWriteUtc) > observed) {
    Common.fail("material_shop_candidate_ui_not_admitted", "candidate_admission",
      "candidate-bound operator attestation is stale, foreign, or lacks required independent evidence");
  }
  Common.exactKeys(value, ["schema", "runId", "planSha256", "requestSha256",
    "candidateIdentitySha256", "operatorAttestationSha256", "available", "admittedAt",
    "trustLevel", "admissionSha256"], "material_shop_candidate_admission_invalid",
  "candidate_admission");
  const unsigned = Object.assign({}, value);
  delete unsigned.admissionSha256;
  if (value.schema !== CANDIDATE_ADMISSION_SCHEMA || value.runId !== request.runId
      || value.planSha256 !== request.planSha256 || value.requestSha256 !== request.requestSha256
      || value.candidateIdentitySha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(request.candidateIdentity))
      || value.operatorAttestationSha256 !== Evidence.sha256Text(Evidence.canonicalJson(receipt))
      || value.available !== true || !Number.isFinite(Date.parse(value.admittedAt))
      || value.trustLevel !== "operator_attested_not_independently_verified"
      || value.admissionSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_candidate_admission_invalid", "candidate_admission",
      "candidate UI admission is malformed or detached from its process/window probe");
  }
  return value;
}

function createCandidateAdmission(request, receipt) {
  const identitySha256 = Evidence.sha256Text(Evidence.canonicalJson(request.candidateIdentity));
  const value = { schema: CANDIDATE_ADMISSION_SCHEMA, runId: request.runId,
    planSha256: request.planSha256, requestSha256: request.requestSha256,
    candidateIdentitySha256: identitySha256,
    operatorAttestationSha256: Evidence.sha256Text(Evidence.canonicalJson(receipt)),
    available: true, admittedAt: receipt.observedAt,
    trustLevel: "operator_attested_not_independently_verified" };
  value.admissionSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateCandidateAdmission(request, receipt, value);
}

function createCandidateAdmissionBundle(request, receipt) {
  const admission = createCandidateAdmission(request, receipt);
  const value = { schema: CANDIDATE_ADMISSION_BUNDLE_SCHEMA,
    request: JSON.parse(JSON.stringify(request)),
    operatorAttestation: JSON.parse(JSON.stringify(receipt)), admission };
  value.bundleSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateCandidateAdmissionBundle(value);
}

function validateCandidateAdmissionBundle(value) {
  Common.exactKeys(value, ["schema", "request", "operatorAttestation", "admission",
    "bundleSha256"],
    "material_shop_candidate_admission_bundle_invalid", "candidate_admission");
  const unsigned = Object.assign({}, value);
  delete unsigned.bundleSha256;
  if (value.schema !== CANDIDATE_ADMISSION_BUNDLE_SCHEMA
      || value.bundleSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_candidate_admission_bundle_invalid", "candidate_admission",
      "candidate UI admission bundle digest is invalid");
  }
  validateCandidateAdmission(value.request, value.operatorAttestation, value.admission);
  return value;
}

function parseArgs(argv) {
  const result = { mode: null, receipt: null, request: null, out: null };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    const take = () => { index += 1; return argv[index]; };
    if (token === "--environment") result.mode = "environment";
    else if (token === "--candidate") result.mode = "candidate";
    else if (token === "--provider-receipt") result.receipt = take();
    else if (token === "--request") result.request = take();
    else if (token === "--out") result.out = take();
    else Common.fail("material_shop_admission_argument_unknown", "admission", token);
  }
  if (!result.mode || !result.receipt || !result.out
      || (result.mode === "candidate" && !result.request)) {
    Common.fail("material_shop_admission_arguments_invalid", "admission",
      "mode, operator attestation, output, and candidate request when applicable are required");
  }
  return result;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const receipt = readJson(args.receipt, "admission");
    const value = args.mode === "environment" ? createEnvironmentCapability(receipt)
      : createCandidateAdmissionBundle(readJson(args.request, "candidate_admission"), receipt);
    writeJsonNew(args.out, value);
    process.stdout.write(JSON.stringify({ ok: true, output: path.resolve(args.out) }) + "\n");
  } catch (error) {
    process.stderr.write(JSON.stringify(Common.publicError(error)) + "\n");
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = {
  CANDIDATE_ADMISSION_SCHEMA,
  CANDIDATE_ADMISSION_BUNDLE_SCHEMA,
  CANDIDATE_RECEIPT_SCHEMA,
  CANDIDATE_REQUEST_SCHEMA,
  ENVIRONMENT_RECEIPT_SCHEMA,
  OPERATOR_ISSUER,
  OPERATOR_TRUST_BOUNDARY,
  captureRawOperationArtifact,
  createCandidateAdmission,
  createCandidateAdmissionBundle,
  createCandidateRequest,
  createEnvironmentCapability,
  validateEnvironmentCapability,
  validateCandidateAdmission,
  validateCandidateAdmissionBundle,
  validateRawOperationArtifact,
};
