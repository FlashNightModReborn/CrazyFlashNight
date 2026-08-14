"use strict";

const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const Admission = require("./admission");
const Common = require("./common");
const Control = require("./control-channel");
const Protocol = require("./protocol");

const PROVIDER_RECEIPT_SCHEMA = "workbench-live-e2e.material-shop.control-provider-receipt.v1";

function readJson(filePath) {
  const file = Evidence.readExactRegularFile(path.resolve(filePath), {
    phase: "control_ack", maximumBytes: 4 * 1024 * 1024,
  });
  try { return JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) { Common.fail("material_shop_control_json_invalid", "control_ack", error.message); }
}

function candidateBinding(request, admission) {
  Admission.validateCandidateAdmissionBundle(admission);
  return { runId: request.runId, planSha256: request.planSha256,
    requestSha256: Evidence.sha256Text(Evidence.canonicalJson(request)), step: request.step,
    candidateIdentitySha256: admission.admission.candidateIdentitySha256,
    pid: admission.operatorAttestation.pid,
    window: JSON.parse(JSON.stringify(admission.operatorAttestation.window)),
    admissionSha256: admission.admission.admissionSha256 };
}

function validateProviderReceipt(value, request, admission, runDir) {
  if (request.transportClass === "runner_owned"
      || request.allowedTransports.includes(Protocol.RUNNER_TRANSPORT)) {
    Common.fail("material_shop_runner_ack_external_forbidden", "control_ack",
      "runner-owned restart/shutdown acknowledgements are created only inside the journey runner");
  }
  Common.exactKeys(value, ["schema", "requestId", "transport", "result", "completedAt",
    "operationId", "driverMethods", "capturePath", "captureSha256", "businessApiCalls",
    "rawOperationArtifact", "trustBoundary", "independentlyVerifiable"],
  "material_shop_control_provider_receipt_invalid", "control_ack");
  const expectedMethods = value.transport === Protocol.PREFERRED_TRANSPORT
    ? ["computer_use"] : request.driverMethods.filter((entry) => Protocol.FALLBACK_METHODS.includes(entry));
  if (value.schema !== PROVIDER_RECEIPT_SCHEMA || value.requestId !== request.requestId
      || !request.allowedTransports.includes(value.transport)
      || !["completed", "unavailable", "cancelled", "failed", "timeout"].includes(value.result)
      || !Number.isFinite(Date.parse(value.completedAt))
      || !Common.ID_RE.test(String(value.operationId || ""))
      || Evidence.canonicalJson(value.driverMethods) !== Evidence.canonicalJson(expectedMethods)
      || value.businessApiCalls !== 0
      || value.trustBoundary !== Admission.OPERATOR_TRUST_BOUNDARY
      || value.independentlyVerifiable !== false
      || (request.requiresCaptureSha256
        ? typeof value.capturePath !== "string" || !Common.SHA256_RE.test(String(value.captureSha256 || ""))
        : value.capturePath !== null || value.captureSha256 !== null)) {
    Common.fail("material_shop_control_provider_receipt_invalid", "control_ack",
      "provider receipt is detached from its exact visible-input request");
  }
  Admission.validateRawOperationArtifact(value.rawOperationArtifact, "control_ack");
  if (!Evidence.pathInside(path.resolve(runDir || ""),
    path.resolve(value.rawOperationArtifact.sourcePath))) {
    Common.fail("material_shop_control_operation_artifact_foreign", "control_ack",
      "raw operator result must be retained inside the exact run directory");
  }
  candidateBinding(request, admission);
  if (value.transport === Protocol.FALLBACK_TRANSPORT
      && request.transportClass !== "panel_visible_input") {
    Common.fail("material_shop_native_fallback_forbidden", "control_ack",
      "CDP fallback cannot acknowledge Native HUD input");
  }
  return value;
}

function parseArgs(argv) {
  const args = { plan: null, request: null, receipt: null, candidateAdmission: null,
    runDir: null };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    index += 1;
    if (index >= argv.length) Common.fail("material_shop_ack_argument_missing", "control_ack", token);
    if (token === "--plan") args.plan = argv[index];
    else if (token === "--request") args.request = argv[index];
    else if (token === "--provider-receipt") args.receipt = argv[index];
    else if (token === "--candidate-admission") args.candidateAdmission = argv[index];
    else if (token === "--run-dir") args.runDir = argv[index];
    else Common.fail("material_shop_ack_argument_unknown", "control_ack", token);
  }
  if (Object.values(args).some((entry) => !entry)) {
    Common.fail("material_shop_ack_arguments_invalid", "control_ack",
      "plan, request, operator receipt, candidate admission, and run directory are required");
  }
  return args;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const plan = Protocol.validateControlPlan(readJson(args.plan));
    const request = readJson(args.request);
    const planStep = plan.steps[request.ordinal];
    Control.validateRequest(request, plan, planStep);
    const admission = Admission.validateCandidateAdmissionBundle(readJson(args.candidateAdmission));
    const receipt = validateProviderReceipt(readJson(args.receipt), request, admission, args.runDir);
    const binding = candidateBinding(request, admission);
    const ack = Control.createAck({ root: Common.CANONICAL_ROOT, runDir: args.runDir,
      plan, request, transport: receipt.transport, result: receipt.result,
      completedAt: receipt.completedAt, operationId: receipt.operationId,
      rawOperationArtifact: receipt.rawOperationArtifact, candidateBinding: binding,
      capturePath: receipt.capturePath, captureSha256: receipt.captureSha256 });
    process.stdout.write(JSON.stringify({ ok: true, requestId: ack.requestId,
      result: ack.result }) + "\n");
  } catch (error) {
    process.stderr.write(JSON.stringify(Common.publicError(error)) + "\n");
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = { PROVIDER_RECEIPT_SCHEMA, candidateBinding, validateProviderReceipt };
