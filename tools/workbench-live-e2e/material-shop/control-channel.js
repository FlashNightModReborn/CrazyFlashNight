"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const SharedControl = require("../lib/control-contract");
const Evidence = require("../lib/evidence-artifact");
const Admission = require("./admission");
const Capture = require("./capture-verifier");
const Common = require("./common");
const Protocol = require("./protocol");

const REQUEST_SCHEMA = "workbench-live-e2e.material-shop.control-request.v1";
const ACK_SCHEMA = "workbench-live-e2e.material-shop.control-ack.v1";
const RESULTS = Object.freeze(["completed", "unavailable", "cancelled", "failed", "timeout"]);

function requestId(step) {
  return String(step) + "-" + Date.now().toString(36) + "-"
    + crypto.randomBytes(8).toString("hex");
}

function writeNew(filePath, value) {
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", {
    encoding: "utf8", mode: 0o600, flag: "wx",
  });
}

function validateRequest(value, plan, planStep) {
  SharedControl.validateControlRequest(value, {
    requestSchema: REQUEST_SCHEMA,
    allowedTransports: [Protocol.PREFERRED_TRANSPORT, Protocol.FALLBACK_TRANSPORT,
      Protocol.RUNNER_TRANSPORT],
    maximumTtlMs: 3600000,
  });
  Common.exactKeys(value, ["schema", "requestId", "step", "runId", "issuedAt",
    "expiresAt", "allowedTransports", "requiresCommitAuthorization",
    "requiresCaptureSha256", "authorizationRef", "instructions", "selectors",
    "expectedIndependentEvidence", "planSha256", "ordinal", "action",
    "visibleTarget", "transportClass", "driverMethods"],
  "material_shop_control_request_invalid", "control");
  if (value.runId !== plan.runId || value.planSha256 !== plan.planSha256
      || value.step !== planStep.id || value.ordinal !== planStep.ordinal
      || value.action !== planStep.action || value.visibleTarget !== planStep.visibleTarget
      || value.transportClass !== planStep.transportClass
      || Evidence.canonicalJson(value.driverMethods)
        !== Evidence.canonicalJson(planStep.driverMethods)
      || value.requiresCommitAuthorization !== planStep.requiresCommitAuthorization
      || value.requiresCaptureSha256 !== planStep.requiresCapture
      || Evidence.canonicalJson(value.allowedTransports)
        !== Evidence.canonicalJson(planStep.allowedTransports)
      || !Array.isArray(value.selectors) || value.selectors.length !== 0
      || !Array.isArray(value.expectedIndependentEvidence)
      || !value.expectedIndependentEvidence.includes("passive_browser_transcript")
      || !value.expectedIndependentEvidence.includes("authenticated_host_log")
      || typeof value.instructions !== "string" || value.instructions.length < 20) {
    Common.fail("material_shop_control_request_invalid", "control",
      "control request differs from its frozen visible-input plan step", { step: planStep.id });
  }
  Protocol.assertNoControllerApi(value.instructions, value.step + ":instructions");
  Protocol.assertNoControllerApi(Evidence.canonicalJson(value), value.step + ":request");
  return value;
}

function validateAck(value, request, plan, runDir) {
  SharedControl.validateControlAck(value, request, {
    ackSchema: ACK_SCHEMA, allowedResults: RESULTS,
  });
  Common.exactKeys(value, ["schema", "requestId", "runId", "step", "transport",
    "result", "completedAt", "requestBindingSha256", "captureSha256", "capture",
    "captureReceipt", "authorizationDecisionId", "provider"],
  "material_shop_control_ack_invalid", "control");
  Common.exactKeys(value.provider, ["issuer", "operationId", "rawOperationArtifact",
    "driverMethods", "businessApiCalls", "trustBoundary", "candidateBinding"],
  "material_shop_control_provider_invalid", "control");
  const external = value.transport !== Protocol.RUNNER_TRANSPORT;
  const expectedIssuer = external ? Admission.OPERATOR_ISSUER : "cf7.material-shop.runner";
  const expectedMethods = value.transport === Protocol.PREFERRED_TRANSPORT
    ? ["computer_use"]
    : value.transport === Protocol.FALLBACK_TRANSPORT
      ? request.driverMethods.filter((entry) => Protocol.FALLBACK_METHODS.includes(entry))
      : request.driverMethods;
  if (value.runId !== plan.runId || value.step !== request.step
      || value.requestBindingSha256 !== Evidence.sha256Text(Evidence.canonicalJson(request))
      || !request.allowedTransports.includes(value.transport)
      || value.provider.issuer !== expectedIssuer
      || !Common.ID_RE.test(String(value.provider.operationId || ""))
      || Evidence.canonicalJson(value.provider.driverMethods) !== Evidence.canonicalJson(expectedMethods)
      || value.provider.businessApiCalls !== 0
      || (external ? value.provider.trustBoundary !== Admission.OPERATOR_TRUST_BOUNDARY
        : value.provider.trustBoundary !== "runner_owned_internal_result")) {
    Common.fail("material_shop_control_ack_invalid", "control",
      "provider acknowledgement is detached or crosses the business API boundary");
  }
  if (external) {
    Admission.validateRawOperationArtifact(value.provider.rawOperationArtifact, "control");
    Common.exactKeys(value.provider.candidateBinding, ["runId", "planSha256",
      "requestSha256", "step", "candidateIdentitySha256", "pid", "window",
      "admissionSha256"], "material_shop_control_candidate_binding_invalid", "control");
    const binding = value.provider.candidateBinding;
    if (binding.runId !== request.runId || binding.planSha256 !== request.planSha256
        || binding.requestSha256 !== value.requestBindingSha256 || binding.step !== request.step
        || !Common.SHA256_RE.test(String(binding.candidateIdentitySha256 || ""))
        || !Number.isInteger(binding.pid) || binding.pid < 1
        || !Evidence.isPlainObject(binding.window)
        || !Common.SHA256_RE.test(String(binding.admissionSha256 || ""))
        || !Evidence.pathInside(path.resolve(runDir || ""),
          path.resolve(value.provider.rawOperationArtifact.sourcePath))) {
      Common.fail("material_shop_control_candidate_binding_invalid", "control",
        "operator input is detached from the current request/candidate/run artifact");
    }
    const operationTime = Date.parse(value.provider.rawOperationArtifact.sourceLastWriteUtc);
    if (operationTime < Date.parse(request.issuedAt)
        || operationTime > Date.parse(value.completedAt)) {
      Common.fail("material_shop_control_operation_stale", "control",
        "operator input artifact predates the request or follows its completion");
    }
  } else if (value.provider.rawOperationArtifact !== null
      || value.provider.candidateBinding !== null) {
    Common.fail("material_shop_runner_provider_invalid", "control",
      "runner-owned lifecycle acknowledgement cannot carry operator evidence");
  }
  if (value.transport === Protocol.FALLBACK_TRANSPORT
      && request.transportClass !== "panel_visible_input") {
    Common.fail("material_shop_native_fallback_forbidden", "control",
      "CDP acknowledgement cannot satisfy a Native HUD or runner-owned step");
  }
  SharedControl.assertAckWithinTtl(request, value);
  if (request.requiresCaptureSha256) {
    Capture.verifyCapture(Common.CANONICAL_ROOT,
      path.resolve(runDir || ""), value.captureReceipt);
    if (Evidence.canonicalJson(value.capture)
        !== Evidence.canonicalJson(value.captureReceipt.capture)
        || value.captureReceipt.requestId !== request.requestId
        || value.captureReceipt.step !== request.step
        || value.captureReceipt.requestBindingSha256 !== value.requestBindingSha256
        || value.captureReceipt.operationArtifactSha256
          !== value.provider.rawOperationArtifact.sha256
        || Evidence.canonicalJson(value.captureReceipt.candidateBinding)
          !== Evidence.canonicalJson(value.provider.candidateBinding)
        || value.captureReceipt.sourceLastWriteUtc !== fs.statSync(
          path.join(path.resolve(runDir || ""),
            value.capture.relativePath.replace(/\//g, path.sep))).mtime.toISOString()) {
      Common.fail("material_shop_control_capture_mismatch", "control",
        "ack capture differs from its request, operator artifact, candidate, or PNG receipt");
    }
  } else if (value.capture !== null || value.captureSha256 !== null
      || value.captureReceipt !== null) {
    Common.fail("material_shop_control_capture_unexpected", "control",
      "non-capture control step carries visual evidence");
  }
  return value;
}

class ControlChannel {
  constructor(rootValue, runDirValue, plan) {
    this.root = Common.assertCanonicalRoot(rootValue);
    this.runDir = Evidence.assertOwnedRunDirectory(this.root, runDirValue,
      Common.OWNED_BASE_RELATIVE, "control");
    this.plan = Protocol.validateControlPlan(plan);
    this.controlDir = Evidence.ensureExactChildDirectory(this.runDir, "control", "control");
    this.requestsDir = Evidence.ensureExactChildDirectory(this.controlDir, "requests", "control");
    this.acksDir = Evidence.ensureExactChildDirectory(this.controlDir, "acks", "control");
    this.capturesDir = Evidence.ensureExactChildDirectory(this.controlDir, "captures", "control");
  }

  issue(stepId, timeoutMs) {
    const planStep = this.plan.steps.find((entry) => entry.id === stepId);
    const ttl = Number(timeoutMs || 900000);
    if (!planStep || !Number.isInteger(ttl) || ttl < 1000 || ttl > 3600000) {
      Common.fail("material_shop_control_issue_invalid", "control", "step or TTL is invalid");
    }
    const issued = new Date();
    const value = {
      schema: REQUEST_SCHEMA,
      requestId: requestId(stepId),
      step: stepId,
      runId: this.plan.runId,
      issuedAt: issued.toISOString(),
      expiresAt: new Date(issued.getTime() + ttl).toISOString(),
      allowedTransports: planStep.allowedTransports,
      requiresCommitAuthorization: planStep.requiresCommitAuthorization,
      requiresCaptureSha256: planStep.requiresCapture,
      authorizationRef: planStep.authorizationRef,
      instructions: "Use only the authorized input or lifecycle transport to complete: "
        + planStep.visibleTarget
        + ". Record the actual visible result; do not invoke application commands.",
      selectors: [],
      expectedIndependentEvidence: ["passive_browser_transcript", "authenticated_host_log"],
      planSha256: this.plan.planSha256,
      ordinal: planStep.ordinal,
      action: planStep.action,
      visibleTarget: planStep.visibleTarget,
      transportClass: planStep.transportClass,
      driverMethods: planStep.driverMethods,
    };
    validateRequest(value, this.plan, planStep);
    writeNew(path.join(this.requestsDir, value.requestId + ".json"), value);
    const current = path.join(this.controlDir, "current-request.json");
    const temporary = current + ".next-" + process.pid + "-" + crypto.randomBytes(4).toString("hex");
    writeNew(temporary, value);
    if (fs.existsSync(current)) fs.unlinkSync(current);
    fs.renameSync(temporary, current);
    return value;
  }

  async wait(request, pollMs) {
    const planStep = this.plan.steps[request.ordinal];
    validateRequest(request, this.plan, planStep);
    const ackPath = path.join(this.acksDir, request.requestId + ".json");
    const deadline = Date.parse(request.expiresAt);
    while (Date.now() <= deadline) {
      if (fs.existsSync(ackPath)) {
        const ack = JSON.parse(Evidence.readExactRegularFile(ackPath, {
          phase: "control", maximumBytes: 4 * 1024 * 1024,
        }).bytes.toString("utf8"));
        return validateAck(ack, request, this.plan, this.runDir);
      }
      await new Promise((resolve) => setTimeout(resolve, Math.max(100, Number(pollMs || 250))));
    }
    Common.fail("material_shop_control_timeout", "control",
      "visible-input provider acknowledgement timed out", { step: request.step, ackPath });
  }
}

function createAck(options) {
  const settings = options || {};
  const plan = Protocol.validateControlPlan(settings.plan);
  const planStep = plan.steps[settings.request.ordinal];
  const request = validateRequest(settings.request, plan, planStep);
  const transport = String(settings.transport || request.allowedTransports[0]);
  if (!request.allowedTransports.includes(transport)) {
    Common.fail("control_transport_not_allowed", "control",
      "provider selected a transport outside the exact plan step", {
        step: request.step, transport,
      });
  }
  if (transport === Protocol.FALLBACK_TRANSPORT
      && request.transportClass !== "panel_visible_input") {
    Common.fail("material_shop_native_fallback_forbidden", "control",
      "CDP cannot satisfy Native HUD or runner-owned input");
  }
  if (request.requiresCaptureSha256 && typeof settings.capturePath !== "string") {
    Common.fail("material_shop_control_capture_source_missing", "control",
      "capture-required control acknowledgement lacks a PNG source path");
  }
  let captureReceipt = null;
  if (request.requiresCaptureSha256) {
    captureReceipt = Capture.stageCapture({
      root: settings.root, runDir: settings.runDir,
      requestId: request.requestId, step: request.step,
      sourcePath: settings.capturePath, expectedSha256: settings.captureSha256,
      capturedAt: settings.completedAt, request,
      rawOperationArtifact: settings.rawOperationArtifact,
      candidateBinding: settings.candidateBinding,
    });
  }
  const value = {
    schema: ACK_SCHEMA,
    requestId: request.requestId,
    runId: request.runId,
    step: request.step,
    transport,
    result: settings.result || "completed",
    completedAt: settings.completedAt || new Date().toISOString(),
    requestBindingSha256: Evidence.sha256Text(Evidence.canonicalJson(request)),
    captureSha256: captureReceipt ? captureReceipt.capture.sha256 : null,
    capture: captureReceipt ? captureReceipt.capture : null,
    captureReceipt,
    authorizationDecisionId: request.requiresCommitAuthorization
      ? request.authorizationRef.decisionId : null,
    provider: {
      issuer: transport
        === Protocol.RUNNER_TRANSPORT ? "cf7.material-shop.runner" : Admission.OPERATOR_ISSUER,
      operationId: String(settings.operationId || ""),
      rawOperationArtifact: transport === Protocol.RUNNER_TRANSPORT
        ? null : settings.rawOperationArtifact,
      driverMethods: transport
        === Protocol.PREFERRED_TRANSPORT ? ["computer_use"]
        : transport
          === Protocol.FALLBACK_TRANSPORT
          ? request.driverMethods.filter((entry) => Protocol.FALLBACK_METHODS.includes(entry))
          : request.driverMethods,
      businessApiCalls: 0,
      trustBoundary: transport === Protocol.RUNNER_TRANSPORT
        ? "runner_owned_internal_result" : Admission.OPERATOR_TRUST_BOUNDARY,
      candidateBinding: transport === Protocol.RUNNER_TRANSPORT
        ? null : settings.candidateBinding,
    },
  };
  validateAck(value, request, plan, settings.runDir);
  writeNew(path.join(settings.runDir, "control", "acks", request.requestId + ".json"), value);
  return value;
}

module.exports = {
  ACK_SCHEMA,
  ControlChannel,
  REQUEST_SCHEMA,
  RESULTS,
  createAck,
  validateAck,
  validateRequest,
};
