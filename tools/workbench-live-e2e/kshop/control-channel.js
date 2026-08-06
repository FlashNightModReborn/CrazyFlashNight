"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const SharedControl = require("../lib/control-contract");
const SharedEvidence = require("../lib/evidence-artifact");
const {
  ACK_SCHEMA,
  CONTROL_SCHEMA,
  OPAQUE_ID_RE,
  PROVIDER_EVENT_SCHEMA,
  PROVIDER_RECEIPT_SCHEMA,
  SHA256_RE,
  assertNoRawTokens,
  canonicalJson,
  fail,
  isPlainObject,
  readJson,
  sha256Bytes,
  sha256Text,
  sleep,
} = require("./common");
const { decodePng } = require("./png-contract");

const TRANSPORTS = new Set(["launcher_agent_runtime", "codex_computer_use"]);
const RESULTS = new Set(["completed", "unavailable", "cancelled", "failed"]);
const OWNED_BASE_RELATIVE = path.join("tmp", "workbench-live-e2e", "kshop");
const PROVIDER_PROFILES = Object.freeze({
  launcher_agent_runtime: Object.freeze({ issuer: "cf7.launcher.agent-runtime",
    toolResultSource: "launcher_agent_runtime.computer_use.result" }),
  codex_computer_use: Object.freeze({ issuer: "openai.codex.computer-use",
    toolResultSource: "codex_computer_use.tool_result" }),
});
const DOM_CONTROL_STEPS = new Set(["add_selected_item", "open_checkout", "commit_checkout",
  "close_kshop", "restart_readback_close_kshop"]);

function exactKeys(value, keys) {
  return isPlainObject(value)
    && canonicalJson(Object.keys(value).sort()) === canonicalJson(keys.slice().sort());
}

function providerEventSha256(event) {
  const payload = Object.assign({}, event);
  delete payload.eventSha256;
  return sha256Text(canonicalJson(payload));
}

function assertOwnedRunDirectory(root, runDir) {
  return SharedEvidence.assertOwnedRunDirectory(root, runDir, OWNED_BASE_RELATIVE, "control");
}

function ensureExactChildDirectory(parent, name) {
  return SharedEvidence.ensureExactChildDirectory(parent, name, "control");
}

function writeNewJson(filePath, value) {
  assertNoRawTokens(value);
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", {
    encoding: "utf8",
    mode: 0o600,
    flag: "wx",
  });
}

function requestId(step) {
  return String(step).replace(/[^a-z0-9_-]/gi, "_") + "-"
    + Date.now().toString(36) + "-" + crypto.randomBytes(8).toString("hex");
}

function validateRequest(request) {
  SharedControl.validateControlRequest(request, {
    requestSchema: CONTROL_SCHEMA,
    allowedTransports: TRANSPORTS,
    maximumTtlMs: 3600000,
  });
  if (!OPAQUE_ID_RE.test(String(request.runId || "")) || !isPlainObject(request.domainIntent)
      || !OPAQUE_ID_RE.test(String(request.domainIntent.action || ""))
      || !Number.isInteger(request.domainIntent.browserSequenceStart)
      || request.domainIntent.browserSequenceStart < 0
      || !Array.isArray(request.domainIntent.expectedWebCommands)
      || request.domainIntent.expectedWebCommands.some((entry) => !OPAQUE_ID_RE.test(String(entry)))) {
    fail("control_domain_intent_invalid", "control",
      "KShop control request lacks an exact run/action/browser/Web intent");
  }
  return request;
}

function validateAck(ack, request) {
  const keys = ["schema", "requestId", "runId", "step", "action", "requestBindingSha256",
    "transport", "result", "completedAt", "authorizationDecisionId", "providerReceiptRef"];
  if (!exactKeys(ack, keys) || ack.schema !== ACK_SCHEMA || ack.requestId !== request.requestId
      || ack.runId !== request.runId || ack.step !== request.step
      || ack.action !== request.domainIntent.action
      || !request.allowedTransports.includes(ack.transport) || !RESULTS.has(ack.result)
      || !Number.isFinite(Date.parse(ack.completedAt))
      || Date.parse(ack.completedAt) < Date.parse(request.issuedAt)
      || Date.parse(ack.completedAt) > Date.parse(request.expiresAt)
      || (request.requiresCommitAuthorization
        ? ack.authorizationDecisionId !== request.authorizationRef.decisionId
        : ack.authorizationDecisionId !== null)
      || ack.requestBindingSha256 !== sha256Text(canonicalJson(request))) {
    fail("control_ack_domain_binding_invalid", "control",
      "KShop acknowledgement is not bound to its exact run/step/action request bytes");
  }
  assertNoRawTokens(ack);
  return ack;
}

class ControlChannel {
  constructor(root, runDir) {
    this.root = path.resolve(root);
    this.runDir = assertOwnedRunDirectory(this.root, runDir);
    this.controlDir = ensureExactChildDirectory(this.runDir, "control");
    this.requestsDir = ensureExactChildDirectory(this.controlDir, "requests");
    this.acksDir = ensureExactChildDirectory(this.controlDir, "acks");
    this.capturesDir = ensureExactChildDirectory(this.controlDir, "captures");
    this.providerReceiptsDir = ensureExactChildDirectory(this.controlDir, "provider-receipts");
  }

  issue(step, options) {
    const settings = options || {};
    const timeoutMs = Number(settings.timeoutMs || 300000);
    if (!OPAQUE_ID_RE.test(String(step || "")) || !Number.isFinite(timeoutMs)
        || timeoutMs < 1000 || timeoutMs > 3600000) {
      fail("control_issue_invalid", "control", "step or timeout is invalid");
    }
    const allowedTransports = Array.from(new Set(settings.allowedTransports || []));
    if (allowedTransports.length < 1 || allowedTransports.some((entry) => !TRANSPORTS.has(entry))) {
      fail("control_transport_invalid", "control", "allowed transport set is invalid");
    }
    const issued = new Date();
    const request = {
      schema: CONTROL_SCHEMA,
      requestId: settings.requestId || requestId(step),
      step,
      runId: String(settings.runId || ""),
      issuedAt: issued.toISOString(),
      expiresAt: new Date(issued.getTime() + timeoutMs).toISOString(),
      allowedTransports,
      requiresCommitAuthorization: settings.requiresCommitAuthorization === true,
      requiresCaptureSha256: settings.requiresCaptureSha256 === true,
      authorizationRef: settings.requiresCommitAuthorization === true
        ? settings.authorizationRef : null,
      instructions: String(settings.instructions || ""),
      selectors: Array.isArray(settings.selectors) ? settings.selectors.map(String) : [],
      expectedIndependentEvidence: Array.isArray(settings.expectedIndependentEvidence)
        ? settings.expectedIndependentEvidence.map(String) : [],
      domainIntent: isPlainObject(settings.domainIntent) ? settings.domainIntent : null,
    };
    assertNoRawTokens(request);
    writeNewJson(path.join(this.requestsDir, request.requestId + ".json"), request);
    const currentPath = path.join(this.controlDir, "current-request.json");
    const temporary = currentPath + ".tmp-" + process.pid + "-" + crypto.randomBytes(5).toString("hex");
    try {
      fs.writeFileSync(temporary, JSON.stringify(request, null, 2) + "\n", {
        encoding: "utf8",
        mode: 0o600,
        flag: "wx",
      });
      if (fs.existsSync(currentPath)) {
        const currentStat = fs.lstatSync(currentPath);
        if (!currentStat.isFile() || currentStat.isSymbolicLink()) {
          fail("control_current_request_invalid", "control", "current request path is not a regular file");
        }
        fs.unlinkSync(currentPath);
      }
      fs.renameSync(temporary, currentPath);
    } finally {
      try { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); } catch (_error) {}
    }
    return request;
  }

  ackPath(requestIdValue) {
    if (!OPAQUE_ID_RE.test(String(requestIdValue || ""))) {
      fail("control_request_id_invalid", "control", "request id is malformed");
    }
    return path.join(this.acksDir, String(requestIdValue) + ".json");
  }

  async wait(request, pollMs) {
    validateRequest(request);
    const ackPath = this.ackPath(request.requestId);
    const deadline = Date.parse(request.expiresAt);
    while (Date.now() <= deadline) {
      if (fs.existsSync(ackPath)) {
        const ack = validateAck(readJson(ackPath, "control acknowledgement"), request);
        SharedControl.assertAckWithinTtl(request, ack);
        const providerReceipt = verifyProviderReceiptFile(this.root, this.runDir,
          ack, request, "live_capture");
        const capture = verifyAckCaptureFile(this.root, this.runDir, ack, request, providerReceipt);
        return { ack, providerReceipt, capture };
      }
      await sleep(Math.max(100, Number(pollMs || 250)));
    }
    fail("control_ack_timeout", "control", "operator acknowledgement timed out", {
      requestId: request.requestId,
      step: request.step,
      ackPath,
    });
  }
}

function captureKind(buffer) {
  try { decodePng(buffer, "capture_png"); return "image/png"; }
  catch (_error) { return null; }
}

function requestArtifactBytes(request) {
  return Buffer.from(JSON.stringify(request, null, 2) + "\n", "utf8");
}

function requestArtifactReference(root, runDir, request) {
  const resolvedRun = assertOwnedRunDirectory(root, runDir);
  const relativePath = path.posix.join("control", "requests", request.requestId + ".json");
  const filePath = path.resolve(resolvedRun, relativePath.replace(/\//g, path.sep));
  let stat;
  let real;
  try { stat = fs.lstatSync(filePath); real = fs.realpathSync.native(filePath); }
  catch (error) { fail("control_request_artifact_missing", "control", error.message); }
  const bytes = fs.readFileSync(filePath);
  const expected = requestArtifactBytes(request);
  if (!stat.isFile() || stat.isSymbolicLink() || path.resolve(real).toLowerCase() !== filePath.toLowerCase()
      || !bytes.equals(expected)) {
    fail("control_request_artifact_invalid", "control",
      "persisted request bytes differ from the exact issued request artifact");
  }
  return { relativePath, sha256: sha256Bytes(bytes), bytes: bytes.length };
}

function finiteRect(value) {
  return exactKeys(value, ["left", "top", "right", "bottom", "width", "height"])
    && Object.values(value).every(Number.isFinite) && value.width > 0 && value.height > 0
    && value.right === value.left + value.width && value.bottom === value.top + value.height;
}

function finitePoint(value) {
  return exactKeys(value, ["x", "y"])
    && Number.isFinite(value.x) && Number.isFinite(value.y);
}

function validateInputObservation(value, request) {
  if (!DOM_CONTROL_STEPS.has(request.step)) {
    if (value !== null) fail("provider_input_observation_invalid", "control",
      "native control step must not claim a passive DOM observation");
    return value;
  }
  const keys = ["eventRef", "observedAt", "eventType", "isTrusted", "selector", "tagName",
    "visible", "enabled", "viewport", "rect", "clientPoint", "hitTargetMatches",
    "key", "button", "repeat"];
  const ref = value && value.eventRef;
  const viewport = value && value.viewport;
  if (!exactKeys(value, keys) || !exactKeys(ref, ["observerId", "sequence", "eventSha256"])
      || !OPAQUE_ID_RE.test(String(ref.observerId || ""))
      || !Number.isInteger(ref.sequence) || ref.sequence < 1
      || !SHA256_RE.test(String(ref.eventSha256 || ""))
      || !Number.isFinite(Date.parse(value.observedAt))
      || !["click", "keydown"].includes(value.eventType) || value.isTrusted !== true
      || typeof value.selector !== "string" || !request.selectors.includes(value.selector)
      || typeof value.tagName !== "string" || !value.tagName
      || value.visible !== true || value.enabled !== true
      || !exactKeys(viewport, ["width", "height", "devicePixelRatio", "scrollX", "scrollY"])
      || !Object.values(viewport).every(Number.isFinite) || viewport.width < 320
      || viewport.height < 180 || viewport.devicePixelRatio <= 0
      || !finiteRect(value.rect) || !finitePoint(value.clientPoint)
      || value.clientPoint.x < value.rect.left || value.clientPoint.x > value.rect.right
      || value.clientPoint.y < value.rect.top || value.clientPoint.y > value.rect.bottom
      || value.clientPoint.x < 0 || value.clientPoint.x > viewport.width
      || value.clientPoint.y < 0 || value.clientPoint.y > viewport.height
      || value.hitTargetMatches !== true || typeof value.repeat !== "boolean"
      || value.eventType === "click" && (value.button !== 0 || value.key !== null
        || value.repeat !== false)
      || value.eventType === "keydown" && (typeof value.key !== "string" || !value.key
        || value.button !== null)) {
    fail("provider_input_observation_invalid", "control",
      "provider receipt lacks one exact trusted DOM target/geometry/hit-test/key contract", {
        step: request.step,
      });
  }
  return value;
}

function validateProviderReceipt(receipt, request, evidenceMode, expectedRequestArtifact) {
  const keys = ["schema", "operationId", "issuer", "toolResultSource", "transport",
    "requestId", "runId", "step", "action", "result", "startedAt", "completedAt",
    "requestBindingSha256", "requestArtifact", "inputObservation", "operationEvents",
    "capture", "receiptSha256"];
  const payload = Object.assign({}, receipt);
  delete payload.receiptSha256;
  if (!exactKeys(receipt, keys) || receipt.schema !== PROVIDER_RECEIPT_SCHEMA
      || !OPAQUE_ID_RE.test(String(receipt.operationId || ""))
      || [request.requestId, request.runId, request.step, request.domainIntent.action]
        .includes(receipt.operationId)
      || receipt.requestId !== request.requestId || receipt.runId !== request.runId
      || receipt.step !== request.step || receipt.action !== request.domainIntent.action
      || !request.allowedTransports.includes(receipt.transport)
      || !RESULTS.has(receipt.result)
      || receipt.requestBindingSha256 !== sha256Text(canonicalJson(request))
      || !Number.isFinite(Date.parse(receipt.startedAt))
      || !Number.isFinite(Date.parse(receipt.completedAt))
      || Date.parse(receipt.startedAt) <= Date.parse(request.issuedAt)
      || Date.parse(receipt.completedAt) < Date.parse(receipt.startedAt)
      || Date.parse(receipt.completedAt) > Date.parse(request.expiresAt)
      || receipt.receiptSha256 !== sha256Text(canonicalJson(payload))) {
    fail("provider_receipt_invalid", "control",
      "provider operation receipt is malformed or detached from the exact request");
  }
  const requestArtifact = receipt.requestArtifact;
  if (!exactKeys(requestArtifact, ["relativePath", "sha256", "bytes"])
      || String(requestArtifact.relativePath || "").replace(/\\/g, "/")
        !== path.posix.join("control", "requests", request.requestId + ".json")
      || !SHA256_RE.test(String(requestArtifact.sha256 || ""))
      || !Number.isInteger(requestArtifact.bytes) || requestArtifact.bytes < 1
      || expectedRequestArtifact
        && canonicalJson(requestArtifact) !== canonicalJson(expectedRequestArtifact)) {
    fail("provider_request_artifact_invalid", "control",
      "provider receipt is detached from the exact persisted request bytes");
  }
  validateInputObservation(receipt.inputObservation, request);
  if ((request.requiresCaptureSha256 && !isPlainObject(receipt.capture))
      || (!request.requiresCaptureSha256 && receipt.capture !== null)) {
    fail("provider_receipt_capture_contract_invalid", "control",
      "provider receipt capture ownership differs from the exact request requirement");
  }
  validateProviderOperationEvents(receipt, request);
  if (evidenceMode === "offline_fixture") {
    if (receipt.issuer !== "offline.fixture" || receipt.toolResultSource !== "fixture.contract") {
      fail("provider_receipt_provenance_invalid", "control",
        "offline fixture receipt has non-fixture provenance");
    }
  } else {
    const profile = PROVIDER_PROFILES[receipt.transport];
    if (!profile || receipt.issuer !== profile.issuer
        || receipt.toolResultSource !== profile.toolResultSource) {
      fail("provider_receipt_provenance_invalid", "control",
        "live receipt issuer/tool-result source differs from its selected provider", {
          transport: receipt.transport,
        });
    }
  }
  return receipt;
}

function validateProviderOperationEvents(receipt, request) {
  const events = receipt.operationEvents;
  const expectedKinds = request.requiresCaptureSha256
    ? ["provider_started", "action_completed", "capture_created", "provider_completed"]
    : ["provider_started", "action_completed", "provider_completed"];
  const keys = ["schema", "sequence", "eventId", "kind", "occurredAt", "operationId",
    "requestId", "evidence", "eventSha256"];
  if (!Array.isArray(events) || events.length !== expectedKinds.length
      || new Set(events.map((entry) => entry && entry.eventId)).size !== events.length) {
    fail("provider_operation_event_set_invalid", "control",
      "provider operation lacks one exact ordered start/action/capture/complete event set");
  }
  events.forEach((event, index) => {
    if (!exactKeys(event, keys) || event.schema !== PROVIDER_EVENT_SCHEMA
        || event.sequence !== index + 1 || !OPAQUE_ID_RE.test(String(event.eventId || ""))
        || event.kind !== expectedKinds[index]
        || event.operationId !== receipt.operationId || event.requestId !== request.requestId
        || !Number.isFinite(Date.parse(event.occurredAt)) || !isPlainObject(event.evidence)
        || event.eventSha256 !== providerEventSha256(event)) {
      fail("provider_operation_event_invalid", "control",
        "provider operation event is malformed, reordered, or detached", {
          step: request.step, index, kind: event && event.kind,
        });
    }
  });
  const start = events[0];
  const action = events[1];
  const captureEvent = request.requiresCaptureSha256 ? events[2] : null;
  const complete = events.at(-1);
  const ordered = events.every((event, index) => index === 0
    || Date.parse(events[index - 1].occurredAt) < Date.parse(event.occurredAt));
  if (!ordered || start.occurredAt !== receipt.startedAt
      || complete.occurredAt !== receipt.completedAt
      || !exactKeys(start.evidence, ["kind"])
      || start.evidence.kind !== "provider_operation_started"
      || !exactKeys(complete.evidence, ["kind", "result"])
      || complete.evidence.kind !== "provider_operation_completed"
      || complete.evidence.result !== receipt.result) {
    fail("provider_operation_event_timeline_invalid", "control",
      "provider events do not form the exact strict start→action→capture→complete timeline");
  }
  if (DOM_CONTROL_STEPS.has(request.step)) {
    const ref = receipt.inputObservation && receipt.inputObservation.eventRef;
    if (action.occurredAt !== receipt.inputObservation.observedAt
        || !exactKeys(action.evidence,
          ["kind", "observerId", "sequence", "eventSha256"])
        || action.evidence.kind !== "trusted_dom_input"
        || !ref || action.evidence.observerId !== ref.observerId
        || action.evidence.sequence !== ref.sequence
        || action.evidence.eventSha256 !== ref.eventSha256) {
      fail("provider_action_event_binding_invalid", "control",
        "DOM provider action event does not reference the exact passive observer event");
    }
  } else if (!exactKeys(action.evidence,
    ["kind", "issuer", "toolResultSource", "operationId", "action"])
      || action.evidence.kind !== "provider_tool_result_action"
      || action.evidence.issuer !== receipt.issuer
      || action.evidence.toolResultSource !== receipt.toolResultSource
      || action.evidence.operationId !== receipt.operationId
      || action.evidence.action !== receipt.action) {
    fail("provider_action_event_binding_invalid", "control",
      "native provider action event is detached from the trusted tool result");
  }
  if (captureEvent) {
    const capture = receipt.capture;
    if (!capture || capture.capturedAt !== captureEvent.occurredAt
        || !exactKeys(capture.eventRef, ["eventId", "eventSha256"])
        || capture.eventRef.eventId !== captureEvent.eventId
        || capture.eventRef.eventSha256 !== captureEvent.eventSha256
        || !exactKeys(captureEvent.evidence, ["kind", "relativePath", "sha256", "bytes"])
        || captureEvent.evidence.kind !== "provider_capture"
        || captureEvent.evidence.relativePath !== capture.relativePath
        || captureEvent.evidence.sha256 !== capture.sha256
        || captureEvent.evidence.bytes !== capture.bytes) {
      fail("provider_capture_event_binding_invalid", "control",
        "capture bytes/time do not reference the exact provider capture event");
    }
  }
  return events;
}

function verifyProviderCaptureFile(root, runDir, receipt, request) {
  if (receipt.capture == null) return null;
  const capture = receipt.capture;
  if (!exactKeys(capture, ["relativePath", "sha256", "bytes", "mediaType", "decoded",
    "capturedAt", "fileModifiedAt", "eventRef"])
      || capture.mediaType !== "image/png" || !SHA256_RE.test(String(capture.sha256 || ""))
      || !Number.isInteger(capture.bytes) || capture.bytes < 1 || capture.bytes > 64 * 1024 * 1024
      || !isPlainObject(capture.decoded) || !Number.isFinite(Date.parse(capture.capturedAt))
      || !Number.isFinite(Date.parse(capture.fileModifiedAt))
      || !isPlainObject(capture.eventRef)) {
    fail("provider_capture_reference_invalid", "control",
      "provider capture reference lacks exact path/bytes/hash/media/decode facts");
  }
  const resolvedRun = assertOwnedRunDirectory(root, runDir);
  const expectedRelative = path.posix.join("control", "captures", request.requestId + ".png");
  if (String(capture.relativePath).replace(/\\/g, "/") !== expectedRelative) {
    fail("provider_capture_reference_invalid", "control",
      "provider capture is outside its exact request-owned path");
  }
  const filePath = path.resolve(resolvedRun, capture.relativePath.replace(/\//g, path.sep));
  let stat;
  let real;
  try { stat = fs.lstatSync(filePath); real = fs.realpathSync.native(filePath); }
  catch (error) { fail("provider_capture_file_missing", "control", error.message); }
  if (!stat.isFile() || stat.isSymbolicLink() || path.resolve(real).toLowerCase() !== filePath.toLowerCase()
      || stat.size !== capture.bytes || !filePath.toLowerCase().startsWith(
        (path.resolve(resolvedRun, "control", "captures") + path.sep).toLowerCase())) {
    fail("provider_capture_file_invalid", "control",
      "provider capture is not one exact request-owned regular file");
  }
  const bytes = fs.readFileSync(filePath);
  const decoded = decodePng(bytes, "provider_capture");
  const modifiedAt = new Date(stat.mtimeMs).toISOString();
  const captureEpoch = Date.parse(capture.capturedAt);
  if (sha256Bytes(bytes) !== capture.sha256
      || canonicalJson(decoded) !== canonicalJson(capture.decoded)
      || modifiedAt !== capture.fileModifiedAt
      || Math.abs(Date.parse(modifiedAt) - captureEpoch) > 2000) {
    fail("provider_capture_digest_invalid", "control",
      "provider capture bytes, decoded dimensions, or fresh file time differ from its receipt");
  }
  return { path: filePath, capture, decoded };
}

function verifyProviderReceiptFile(root, runDir, ack, request, evidenceMode) {
  const reference = ack.providerReceiptRef;
  const referenceKeys = ["relativePath", "sha256", "bytes", "operationId"];
  if (!exactKeys(reference, referenceKeys) || !SHA256_RE.test(String(reference.sha256 || ""))
      || !Number.isInteger(reference.bytes) || reference.bytes < 1 || reference.bytes > 64 * 1024
      || !OPAQUE_ID_RE.test(String(reference.operationId || ""))) {
    fail("provider_receipt_reference_invalid", "control",
      "acknowledgement lacks one exact provider receipt reference");
  }
  const resolvedRun = assertOwnedRunDirectory(root, runDir);
  const expectedRelative = path.posix.join("control", "provider-receipts", request.requestId + ".json");
  if (String(reference.relativePath).replace(/\\/g, "/") !== expectedRelative) {
    fail("provider_receipt_reference_invalid", "control",
      "provider receipt reference is outside its exact request-owned path");
  }
  const filePath = path.resolve(resolvedRun, reference.relativePath.replace(/\//g, path.sep));
  let stat;
  let real;
  try { stat = fs.lstatSync(filePath); real = fs.realpathSync.native(filePath); }
  catch (error) { fail("provider_receipt_file_missing", "control", error.message); }
  if (!stat.isFile() || stat.isSymbolicLink() || path.resolve(real).toLowerCase() !== filePath.toLowerCase()
      || stat.size !== reference.bytes || !filePath.toLowerCase().startsWith(
        (path.resolve(resolvedRun, "control", "provider-receipts") + path.sep).toLowerCase())) {
    fail("provider_receipt_file_invalid", "control",
      "provider receipt is not one exact request-owned regular file");
  }
  const bytes = fs.readFileSync(filePath);
  if (sha256Bytes(bytes) !== reference.sha256) {
    fail("provider_receipt_digest_mismatch", "control",
      "provider receipt reference differs from its exact bytes");
  }
  let receipt;
  try { receipt = JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) { fail("provider_receipt_json_invalid", "control", error.message); }
  const requestArtifact = requestArtifactReference(root, runDir, request);
  validateProviderReceipt(receipt, request, evidenceMode, requestArtifact);
  if (receipt.operationId !== reference.operationId || receipt.transport !== ack.transport
      || receipt.result !== ack.result || receipt.completedAt !== ack.completedAt) {
    fail("provider_receipt_ack_binding_invalid", "control",
      "acknowledgement does not exactly reference the provider operation result");
  }
  verifyProviderCaptureFile(root, runDir, receipt, request);
  return receipt;
}

function verifyAckCaptureFile(root, runDir, ack, request, providerReceipt) {
  if (!providerReceipt) fail("control_ack_capture_binding_invalid", "control",
    "acknowledgement lacks its provider-owned evidence reference");
  return verifyProviderCaptureFile(root, runDir, providerReceipt, request);
}

function referenceProviderReceipt(channel, request, rawAck) {
  if (!rawAck.providerReceiptFile) {
    fail("provider_receipt_required", "control", "--provider-receipt-file is required");
  }
  const sourcePath = path.resolve(rawAck.providerReceiptFile);
  const expectedPath = path.resolve(channel.providerReceiptsDir, request.requestId + ".json");
  let stat;
  let real;
  try { stat = fs.lstatSync(sourcePath); real = fs.realpathSync.native(sourcePath); }
  catch (error) { fail("provider_receipt_source_missing", "control", error.message); }
  if (!stat.isFile() || stat.isSymbolicLink() || path.resolve(real) !== sourcePath
      || sourcePath.toLowerCase() !== expectedPath.toLowerCase()
      || stat.size < 1 || stat.size > 64 * 1024) {
    fail("provider_receipt_source_invalid", "control",
      "provider must prewrite one bounded exact receipt at its request-owned path");
  }
  const bytes = fs.readFileSync(sourcePath);
  let receipt;
  try { receipt = JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) { fail("provider_receipt_json_invalid", "control", error.message); }
  validateProviderReceipt(receipt, request, "live_capture",
    requestArtifactReference(channel.root, channel.runDir, request));
  if (receipt.transport !== rawAck.transport || receipt.result !== rawAck.result) {
    fail("provider_receipt_result_mismatch", "control",
      "provider receipt transport/result differs from the acknowledgement request");
  }
  return { receipt, reference: { relativePath: path.posix.join("control", "provider-receipts",
    request.requestId + ".json"), sha256: sha256Bytes(bytes), bytes: bytes.length,
    operationId: receipt.operationId } };
}

function writeAck(root, runDir, requestIdValue, rawAck) {
  const allowedInputKeys = ["transport", "result", "providerReceiptFile",
    "authorizationDecisionId"];
  if (!isPlainObject(rawAck) || Object.keys(rawAck).some((key) => !allowedInputKeys.includes(key))
      || !Object.prototype.hasOwnProperty.call(rawAck, "transport")
      || !Object.prototype.hasOwnProperty.call(rawAck, "result")
      || !Object.prototype.hasOwnProperty.call(rawAck, "providerReceiptFile")) {
    fail("control_ack_input_invalid", "control",
      "ack helper input is not one exact provider-reference contract");
  }
  const channel = new ControlChannel(root, runDir);
  const requestPath = path.join(channel.requestsDir, String(requestIdValue) + ".json");
  const request = validateRequest(readJson(requestPath, "control request"));
  if (Date.now() > Date.parse(request.expiresAt)) {
    fail("control_request_expired", "control", "control request has expired");
  }
  const provider = referenceProviderReceipt(channel, request, rawAck);
  verifyProviderCaptureFile(channel.root, channel.runDir, provider.receipt, request);
  const ack = validateAck({
    schema: ACK_SCHEMA,
    requestId: request.requestId,
    completedAt: provider.receipt.completedAt,
    runId: request.runId,
    step: request.step,
    action: request.domainIntent.action,
    requestBindingSha256: sha256Text(canonicalJson(request)),
    transport: rawAck.transport,
    result: rawAck.result,
    authorizationDecisionId: rawAck.authorizationDecisionId || null,
    providerReceiptRef: provider.reference,
  }, request);
  verifyAckCaptureFile(channel.root, channel.runDir, ack, request, provider.receipt);
  writeNewJson(channel.ackPath(request.requestId), ack);
  return { request, ack };
}

module.exports = {
  ControlChannel,
  RESULTS,
  TRANSPORTS,
  assertOwnedRunDirectory,
  captureKind,
  DOM_CONTROL_STEPS,
  requestArtifactBytes,
  requestArtifactReference,
  validateInputObservation,
  validateProviderReceipt,
  validateProviderOperationEvents,
  providerEventSha256,
  verifyProviderReceiptFile,
  verifyProviderCaptureFile,
  verifyAckCaptureFile,
  validateAck,
  validateRequest,
  writeAck,
};
