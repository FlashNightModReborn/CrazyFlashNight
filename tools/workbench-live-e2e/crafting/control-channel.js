"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const SharedControl = require("../lib/control-contract");
const SharedEvidence = require("../lib/evidence-artifact");
const {
  CONTROL_ACK_SCHEMA,
  CONTROL_REQUEST_SCHEMA,
  PROVIDER_CAPTURE_EVENT_SCHEMA,
  PROVIDER_RECEIPT_SCHEMA,
  ID_RE,
  OWNED_BASE_RELATIVE,
  assertNoRawAuthority,
  decodePng,
  fail,
} = require("./common");

const TRANSPORTS = new Set(["launcher_agent_runtime", "codex_computer_use"]);
const RESULTS = new Set(["completed", "unavailable", "cancelled", "failed"]);
const PROVIDER_OPERATION_ID_RE = /^[A-Za-z0-9._~-]{8,160}$/;
const REQUEST_KEYS = Object.freeze(["schema", "runId", "requestId", "step", "issuedAt",
  "expiresAt", "allowedTransports", "requiresCommitAuthorization",
  "requiresCaptureSha256", "authorizationRef", "instructions", "selectors",
  "expectedIndependentEvidence"]);
const ACK_KEYS = Object.freeze(["schema", "runId", "requestId", "step", "transport",
  "result", "completedAt", "captureSha256", "capture", "authorizationDecisionId",
  "providerReceipt", "details"]);
const PROVIDER_RECEIPT_KEYS = Object.freeze(["schema", "runId", "requestId", "step",
  "transport", "issuer", "toolResultSource", "requestSha256", "providerOperationId",
  "action", "result", "startedAt", "inputEvidence", "completedAt", "ownedArtifact",
  "captureEventRef", "receiptSha256"]);
const PROVIDER_CAPTURE_EVENT_KEYS = Object.freeze(["schema", "runId", "requestId", "step",
  "transport", "issuer", "toolResultSource", "providerEventId", "requestSha256",
  "captureArtifact", "capturedAt", "fileModifiedAt", "captureBytes", "captureSha256",
  "captureWidth", "captureHeight", "captureSemanticContentIndependentlyVerified",
  "eventSha256"]);
const INPUT_EVIDENCE_KEYS = Object.freeze(["kind", "eventRef", "eventType", "isTrusted",
  "selector", "tagName", "visible", "enabled", "viewport", "rect", "clientPoint",
  "hitTargetMatches", "key", "button", "repeat", "observedAt"]);
const PROVIDER_POLICIES = Object.freeze({
  launcher_agent_runtime: Object.freeze({ issuer: "launcher_agent_runtime",
    toolResultSource: "launcher_agent_runtime_tool_result" }),
  codex_computer_use: Object.freeze({ issuer: "codex_computer_use",
    toolResultSource: "codex_computer_use_tool_result" }),
});
const REQUIRED_CONTROL_STEPS = Object.freeze([
  "open_crafting",
  "select_recipe",
  "capture_inventory_before",
  "return_from_inventory_before",
  "commit_recipe",
  "capture_inventory_after",
  "return_from_inventory_after",
  "close_first_crafting",
  "safe_exit",
  "exit_confirm",
  "restart_open_crafting",
  "restart_select_recipe",
  "restart_capture_inventory",
  "restart_return_from_inventory",
  "restart_close_crafting",
]);


function expectedControlIntent(step, context) {
  const recipeIndex = context && context.recipeIndex;
  const recipeSelector = "button[data-workbench-key=\"" + recipeIndex + "\"]";
  const values = {
    open_crafting: ["Open the production Crafting workbench from the world Crafting entry exactly once.", ["world crafting entry"], ["world ingress", "Crafting snapshot and preview"]],
    select_recipe: ["Select recipeIndex " + recipeIndex + " exactly once.", [recipeSelector], ["trusted recipe input", "fresh Crafting preview"]],
    capture_inventory_before: ["Open the Crafting inventory organizer exactly once before commit.", ["button.crafting-organizer-btn"], ["Inventory full snapshot"]],
    return_from_inventory_before: ["Return to Crafting exactly once before commit.", ["button.inventory-return-crafting-btn"], ["fresh Crafting snapshot and preview"]],
    commit_recipe: ["Commit the selected recipe exactly once; never retry.", ["button[data-commit-primary]"], ["single authorized commit", "fresh snapshot and preview"]],
    capture_inventory_after: ["Open the Crafting inventory organizer exactly once after commit.", ["button.crafting-organizer-btn"], ["post-commit Inventory full snapshot"]],
    return_from_inventory_after: ["Return to Crafting exactly once after commit.", ["button.inventory-return-crafting-btn"], ["final Crafting postcondition"]],
    close_first_crafting: ["Close the first Crafting workbench exactly once.", ["button[data-header-action=\"close\"]"], ["trusted close", "Host exact close"]],
    safe_exit: ["Use Launcher SAFEEXIT exactly once after exact close.", ["native SAFEEXIT"], ["sv:1", "sv:2", "one exact archive"]],
    exit_confirm: ["Use Launcher EXIT_CONFIRM exactly once after save completion.", ["native EXIT_CONFIRM"], ["first runtime exits", "clean residue"]],
    restart_open_crafting: ["Open the same world Crafting entry exactly once after restart.", ["world crafting entry"], ["fresh owner", "fresh snapshot and preview"]],
    restart_select_recipe: ["Select recipeIndex " + recipeIndex + " once after restart; do not commit.", [recipeSelector], ["fresh readback preview", "zero restart commit"]],
    restart_capture_inventory: ["Open the organizer exactly once for restart readback.", ["button.crafting-organizer-btn"], ["restart Inventory full snapshot"]],
    restart_return_from_inventory: ["Return to Crafting exactly once after restart.", ["button.inventory-return-crafting-btn"], ["restart Crafting snapshot and preview"]],
    restart_close_crafting: ["Close restart Crafting exactly once without commit.", ["button[data-header-action=\"close\"]"], ["trusted close", "Host exact close", "zero restart commit"]],
  };
  const selected = values[step];
  if (!selected || ((step === "select_recipe" || step === "restart_select_recipe")
      && !Number.isInteger(recipeIndex))) {
    fail("control_intent_context_invalid", "control",
      "exact Crafting control intent cannot be derived", { step, recipeIndex });
  }
  return { instructions: selected[0], selectors: selected[1].slice(),
    expectedIndependentEvidence: selected[2].slice() };
}

function writeNewJson(filePath, value) {
  assertNoRawAuthority(value, "control");
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", {
    encoding: "utf8", mode: 0o600, flag: "wx",
  });
}

function randomId(step) {
  return step + "-" + Date.now().toString(36) + "-" + crypto.randomBytes(8).toString("hex");
}

function exactKeys(value, expected, code, message) {
  if (!SharedEvidence.isPlainObject(value)
      || SharedEvidence.canonicalJson(Object.keys(value).sort())
        !== SharedEvidence.canonicalJson(expected.slice().sort())) {
    fail(code, "control", message, { actual: SharedEvidence.isPlainObject(value)
      ? Object.keys(value).sort() : null, expected: expected.slice().sort() });
  }
  return value;
}

function finiteRect(value) {
  return SharedEvidence.isPlainObject(value)
    && SharedEvidence.canonicalJson(Object.keys(value).sort())
      === SharedEvidence.canonicalJson(["bottom", "height", "left", "right", "top", "width"])
    && Object.values(value).every(Number.isFinite)
    && value.width > 0 && value.height > 0
    && value.right === value.left + value.width && value.bottom === value.top + value.height;
}

function finitePoint(value) {
  return SharedEvidence.isPlainObject(value)
    && SharedEvidence.canonicalJson(Object.keys(value).sort())
      === SharedEvidence.canonicalJson(["x", "y"])
    && Number.isFinite(value.x) && Number.isFinite(value.y);
}

function validateInputEvidence(value, request) {
  exactKeys(value, INPUT_EVIDENCE_KEYS, "provider_input_evidence_invalid",
    "provider input evidence is not one exact closed interaction contract");
  const web = value.kind === "web_dom_event";
  const native = value.kind === "native_input";
  const eventRef = value.eventRef;
  const validEventRef = web && SharedEvidence.isPlainObject(eventRef)
    && SharedEvidence.canonicalJson(Object.keys(eventRef).sort())
      === SharedEvidence.canonicalJson(["eventSha256", "observerId", "sequence"])
    && ID_RE.test(String(eventRef.observerId || ""))
    && Number.isInteger(eventRef.sequence) && eventRef.sequence > 0
    && /^[a-f0-9]{64}$/.test(String(eventRef.eventSha256 || ""));
  const viewport = value.viewport;
  const inputObserved = Date.parse(value.observedAt);
  const validViewport = SharedEvidence.isPlainObject(viewport)
    && SharedEvidence.canonicalJson(Object.keys(viewport).sort())
      === SharedEvidence.canonicalJson(["height", "scrollX", "scrollY", "width"])
    && Number.isFinite(viewport.width) && viewport.width >= 320
    && Number.isFinite(viewport.height) && viewport.height >= 180
    && Number.isFinite(viewport.scrollX) && Number.isFinite(viewport.scrollY);
  if ((!web && !native) || web && !validEventRef || native && eventRef !== null
      || !["click", "keydown"].includes(value.eventType) || value.isTrusted !== true
      || !Number.isFinite(inputObserved)
      || new Date(inputObserved).toISOString() !== value.observedAt
      || value.selector !== request.selectors[0] || typeof value.tagName !== "string"
      || !value.tagName || value.visible !== true || value.enabled !== true
      || !validViewport || !finiteRect(value.rect) || !finitePoint(value.clientPoint)
      || value.clientPoint.x < value.rect.left || value.clientPoint.x > value.rect.right
      || value.clientPoint.y < value.rect.top || value.clientPoint.y > value.rect.bottom
      || value.clientPoint.x < 0 || value.clientPoint.x > value.viewport.width
      || value.clientPoint.y < 0 || value.clientPoint.y > value.viewport.height
      || value.hitTargetMatches !== true
      || !(value.key === null || typeof value.key === "string")
      || !(value.button === null || Number.isInteger(value.button))
      || typeof value.repeat !== "boolean"
      || value.eventType === "click" && (value.button !== 0 || value.key !== null)
      || value.eventType === "keydown" && (!value.key || value.button !== null)) {
    fail("provider_input_evidence_invalid", "control",
      "provider input evidence lacks exact target, geometry, hit-test, key, or event ownership", {
        step: request.step,
      });
  }
  return value;
}

function expectedProviderOperationId(receipt) {
  const projection = {
    schema: receipt.schema,
    runId: receipt.runId,
    requestId: receipt.requestId,
    step: receipt.step,
    transport: receipt.transport,
    issuer: receipt.issuer,
    toolResultSource: receipt.toolResultSource,
    requestSha256: receipt.requestSha256,
    action: receipt.action,
    result: receipt.result,
    startedAt: receipt.startedAt,
    inputEvidence: receipt.inputEvidence,
    captureEventRef: receipt.captureEventRef,
    completedAt: receipt.completedAt,
  };
  return "craftop-" + SharedEvidence.sha256Text(SharedEvidence.canonicalJson(projection));
}

function expectedProviderCaptureEventId(event) {
  const projection = Object.assign({}, event);
  delete projection.providerEventId;
  delete projection.eventSha256;
  return "craftcap-" + SharedEvidence.sha256Text(SharedEvidence.canonicalJson(projection));
}

function domInputEvidence(observerId, event) {
  const target = event && event.target;
  if (!SharedEvidence.isPlainObject(event) || !SharedEvidence.isPlainObject(target)) return null;
  return {
    kind: "web_dom_event",
    eventRef: { observerId, sequence: event.sequence, eventSha256: event.eventHash },
    eventType: event.eventType,
    isTrusted: event.isTrusted === true,
    selector: target.selector,
    tagName: target.tagName,
    visible: target.visible === true,
    enabled: target.enabled === true,
    viewport: target.viewport,
    rect: target.rect,
    clientPoint: target.clientPoint,
    hitTargetMatches: target.hitTargetMatches === true,
    key: event.eventType === "keydown" ? String(event.key || "") : null,
    button: event.eventType === "click" ? Number(event.button) : null,
    repeat: event.eventType === "keydown" ? event.repeat === true : false,
    observedAt: event.observedAt,
  };
}

function validateRequest(request) {
  exactKeys(request, REQUEST_KEYS, "control_request_invalid",
    "control request fields are not one exact closed contract");
  SharedControl.validateControlRequest(request, {
    requestSchema: CONTROL_REQUEST_SCHEMA,
    allowedTransports: TRANSPORTS,
    maximumTtlMs: 3600000,
  });
  if (!ID_RE.test(String(request.runId || ""))
      || !REQUIRED_CONTROL_STEPS.includes(request.step)
      || new Set(request.allowedTransports).size !== request.allowedTransports.length
      || typeof request.instructions !== "string" || !request.instructions.trim()
      || !Array.isArray(request.selectors)
      || request.selectors.some((entry) => typeof entry !== "string" || !entry)
      || !Array.isArray(request.expectedIndependentEvidence)
      || request.expectedIndependentEvidence.some((entry) => typeof entry !== "string" || !entry)) {
    fail("control_request_invalid", "control", "control request scope is malformed");
  }
  assertNoRawAuthority(request, "control");
  return request;
}

function validateAck(ack, request) {
  exactKeys(ack, ACK_KEYS, "control_ack_invalid",
    "control acknowledgement fields are not one exact closed contract");
  SharedControl.validateControlAck(ack, request, {
    ackSchema: CONTROL_ACK_SCHEMA,
    allowedResults: RESULTS,
  });
  SharedControl.assertAckWithinTtl(request, ack);
  if (ack.runId !== request.runId || ack.step !== request.step
      || !SharedEvidence.isPlainObject(ack.providerReceipt)
      || SharedEvidence.canonicalJson(Object.keys(ack.providerReceipt).sort())
        !== SharedEvidence.canonicalJson(["artifact", "sha256"])
      || typeof ack.providerReceipt.artifact !== "string"
      || !/^[a-f0-9]{64}$/.test(String(ack.providerReceipt.sha256 || ""))
      || !SharedEvidence.isPlainObject(ack.details) || Object.keys(ack.details).length !== 0
      || (request.requiresCaptureSha256
        ? (!SharedEvidence.isPlainObject(ack.capture)
          || ack.captureSha256 !== ack.capture.sha256)
        : (ack.capture !== null || ack.captureSha256 !== null))) {
    fail("control_ack_invalid", "control",
      "control acknowledgement identity, provider reference, capture, or details are invalid");
  }
  assertNoRawAuthority(ack, "control");
  return ack;
}

function validateProviderReceipt(receipt, request, transport, result, completedAt, binding) {
  exactKeys(receipt, PROVIDER_RECEIPT_KEYS, "provider_receipt_invalid",
    "provider receipt fields are not one exact closed contract");
  const policy = PROVIDER_POLICIES[transport];
  const expected = binding || {};
  const started = Date.parse(receipt.startedAt);
  const inputObserved = Date.parse(receipt.inputEvidence && receipt.inputEvidence.observedAt);
  const providerCompleted = Date.parse(receipt.completedAt);
  const issued = Date.parse(request.issuedAt);
  const expires = Date.parse(request.expiresAt);
  const acknowledged = completedAt == null ? null : Date.parse(completedAt);
  validateInputEvidence(receipt.inputEvidence, request);
  if (receipt.schema !== PROVIDER_RECEIPT_SCHEMA || receipt.runId !== request.runId
      || receipt.requestId !== request.requestId || receipt.step !== request.step
      || receipt.transport !== transport || !policy
      || receipt.issuer !== policy.issuer
      || receipt.toolResultSource !== policy.toolResultSource
      || receipt.requestSha256 !== expected.requestSha256
      || receipt.ownedArtifact !== expected.ownedArtifact
      || !SharedEvidence.isPlainObject(receipt.captureEventRef)
      || SharedEvidence.canonicalJson(receipt.captureEventRef)
        !== SharedEvidence.canonicalJson(expected.captureEventRef)
      || receipt.result !== result || receipt.action !== request.step
      || !PROVIDER_OPERATION_ID_RE.test(String(receipt.providerOperationId || ""))
      || receipt.providerOperationId !== expectedProviderOperationId(receipt)
      || ![started, inputObserved, providerCompleted].every(Number.isFinite)
      || new Date(started).toISOString() !== receipt.startedAt
      || new Date(providerCompleted).toISOString() !== receipt.completedAt
      || !(issued < started && started < inputObserved
        && inputObserved < expected.capturedAt && expected.fileModifiedAt < providerCompleted
        && providerCompleted <= expires)
      || !/^[a-f0-9]{64}$/.test(String(receipt.requestSha256 || ""))
      || acknowledged !== null && (!Number.isFinite(acknowledged)
        || !(providerCompleted < acknowledged) || acknowledged - providerCompleted > 2000)) {
    fail("provider_receipt_invalid", "control",
      "control acknowledgement lacks one exact request-to-start-to-input-to-capture-to-mtime-to-completion receipt", {
        step: request.step,
      });
  }
  const unsigned = Object.assign({}, receipt);
  delete unsigned.receiptSha256;
  if (receipt.receiptSha256 !== SharedEvidence.sha256Text(
    SharedEvidence.canonicalJson(unsigned))) {
    fail("provider_receipt_digest_invalid", "control",
      "provider receipt self-digest is detached", { step: request.step });
  }
  assertNoRawAuthority(receipt, "provider_receipt");
  return receipt;
}

class ControlChannel {
  constructor(root, runDir) {
    this.root = path.resolve(root);
    this.runDir = SharedEvidence.assertOwnedRunDirectory(this.root, runDir,
      OWNED_BASE_RELATIVE, "control");
    this.controlDir = SharedEvidence.ensureExactChildDirectory(this.runDir, "control", "control");
    this.requestsDir = SharedEvidence.ensureExactChildDirectory(this.controlDir, "requests", "control");
    this.acksDir = SharedEvidence.ensureExactChildDirectory(this.controlDir, "acks", "control");
    this.capturesDir = SharedEvidence.ensureExactChildDirectory(this.controlDir, "captures", "control");
    this.providerReceiptsDir = SharedEvidence.ensureExactChildDirectory(
      this.controlDir, "provider-receipts", "control");
    this.captureEventsDir = SharedEvidence.ensureExactChildDirectory(
      this.controlDir, "capture-events", "control");
    this.runId = path.basename(this.runDir);
    if (!ID_RE.test(this.runId)) {
      fail("control_run_id_invalid", "control", "owned run directory basename is not a valid run id");
    }
  }

  requestPath(requestId) { return path.join(this.requestsDir, requestId + ".json"); }
  ackPath(requestId) { return path.join(this.acksDir, requestId + ".json"); }

  issue(step, options) {
    const settings = options || {};
    if (!REQUIRED_CONTROL_STEPS.includes(step)) {
      fail("control_step_invalid", "control", "control step is outside the exact Crafting journey", { step });
    }
    const timeoutMs = Number(settings.timeoutMs || 300000);
    if (!Number.isFinite(timeoutMs) || timeoutMs < 1000 || timeoutMs > 3600000) {
      fail("control_timeout_invalid", "control", "control TTL is outside policy");
    }
    const allowedTransports = Array.from(new Set(settings.allowedTransports || []));
    if (!allowedTransports.length || allowedTransports.some((entry) => !TRANSPORTS.has(entry))) {
      fail("control_transport_invalid", "control", "control transport set is malformed");
    }
    const issuedAt = new Date();
    const request = validateRequest({
      schema: CONTROL_REQUEST_SCHEMA,
      runId: this.runId,
      requestId: randomId(step),
      step,
      issuedAt: issuedAt.toISOString(),
      expiresAt: new Date(issuedAt.getTime() + timeoutMs).toISOString(),
      allowedTransports,
      requiresCommitAuthorization: settings.requiresCommitAuthorization === true,
      requiresCaptureSha256: true,
      authorizationRef: settings.requiresCommitAuthorization === true
        ? settings.authorizationRef : null,
      instructions: String(settings.instructions || ""),
      selectors: Array.isArray(settings.selectors) ? settings.selectors.slice() : [],
      expectedIndependentEvidence: Array.isArray(settings.expectedIndependentEvidence)
        ? settings.expectedIndependentEvidence.slice() : [],
    });
    writeNewJson(this.requestPath(request.requestId), request);
    return request;
  }

  readAck(request) {
    validateRequest(request);
    if (request.runId !== this.runId) {
      fail("control_request_invalid", "control", "control request crossed the owned run identity");
    }
    const ackPath = this.ackPath(request.requestId);
    if (!fs.existsSync(ackPath)) return null;
    const parsed = JSON.parse(SharedEvidence.readExactRegularFile(ackPath, {
      phase: "control", maximumBytes: 2 * 1024 * 1024,
    }).bytes.toString("utf8"));
    const ack = validateAck(parsed, request);
    verifyAckCapture(this.root, this.runDir, request, ack);
    verifyProviderReceiptReference(this.root, this.runDir, request, ack);
    return ack;
  }

  async wait(request, options) {
    const settings = options || {};
    const pollMs = Number(settings.pollMs || 250);
    while (Date.now() <= Date.parse(request.expiresAt)) {
      const ack = this.readAck(request);
      if (ack) {
        if (ack.result !== "completed") {
          fail("control_not_completed", "control", "control step did not complete", {
            step: request.step, result: ack.result,
          });
        }
        return ack;
      }
      await new Promise((resolve) => setTimeout(resolve, pollMs));
    }
    fail("control_ack_timeout", "control", "control acknowledgement timed out", { step: request.step });
  }
}

function verifyAckCapture(root, runDir, request, ack) {
  if (ack.capture == null) return null;
  const capture = SharedEvidence.verifyOwnedCapture({
    root, runDir, ownedBaseRelative: OWNED_BASE_RELATIVE,
    capture: ack.capture, phase: "control_capture",
  });
  if (capture.mediaType !== "image/png") {
    fail("control_capture_media_invalid", "control_capture", "control capture must be PNG");
  }
  const decoded = decodePng(SharedEvidence.readExactRegularFile(capture.path, {
    phase: "control_capture", maximumBytes: 16 * 1024 * 1024,
  }).bytes);
  return Object.assign({}, capture, { width: decoded.width, height: decoded.height });
}

function providerReceiptRelativePath(requestId) {
  return "control/provider-receipts/" + requestId + ".json";
}

function providerCaptureEventRelativePath(requestId) {
  return "control/capture-events/" + requestId + ".json";
}

function readProviderCaptureEvent(root, runDir, request, receipt, requestSha256) {
  const exactRun = SharedEvidence.assertOwnedRunDirectory(path.resolve(root), runDir,
    OWNED_BASE_RELATIVE, "provider_capture_event");
  const reference = receipt && receipt.captureEventRef;
  const expectedRelative = providerCaptureEventRelativePath(request.requestId);
  if (!SharedEvidence.isPlainObject(reference)
      || SharedEvidence.canonicalJson(Object.keys(reference).sort())
        !== SharedEvidence.canonicalJson(["artifact", "eventSha256", "sha256"])
      || reference.artifact !== expectedRelative
      || !/^[a-f0-9]{64}$/.test(String(reference.sha256 || ""))
      || !/^[a-f0-9]{64}$/.test(String(reference.eventSha256 || ""))) {
    fail("provider_capture_event_reference_invalid", "control",
      "provider receipt does not reference the exact owned capture event", {
        step: request.step,
      });
  }
  const eventPath = path.resolve(exactRun, expectedRelative.replace(/\//g, path.sep));
  if (!SharedEvidence.pathInside(exactRun, eventPath)) {
    fail("provider_capture_event_path_escape", "control",
      "provider capture event escaped the owned run directory", { step: request.step });
  }
  const file = SharedEvidence.readExactRegularFile(eventPath, {
    phase: "provider_capture_event", maximumBytes: 64 * 1024,
  });
  if (file.sha256 !== reference.sha256) {
    fail("provider_capture_event_hash_mismatch", "control",
      "provider capture event reference does not bind the exact event bytes", {
        step: request.step,
      });
  }
  let event;
  try { event = JSON.parse(file.bytes.toString("utf8")); }
  catch (error) {
    fail("provider_capture_event_invalid", "control", "provider capture event JSON is malformed", {
      step: request.step, message: error.message,
    });
  }
  const captureRelative = "control/captures/" + request.requestId + ".png";
  const capturePath = path.resolve(exactRun, captureRelative.replace(/\//g, path.sep));
  const captureFile = SharedEvidence.readExactRegularFile(capturePath, {
    phase: "provider_capture", maximumBytes: 16 * 1024 * 1024,
  });
  const captureStat = fs.statSync(capturePath);
  const decoded = decodePng(captureFile.bytes);
  const policy = PROVIDER_POLICIES[receipt.transport];
  const capturedAt = Date.parse(event && event.capturedAt);
  const fileModifiedAt = Date.parse(event && event.fileModifiedAt);
  const issuedAt = Date.parse(request.issuedAt);
  const unsigned = Object.assign({}, event);
  delete unsigned.eventSha256;
  if (!SharedEvidence.isPlainObject(event)
      || SharedEvidence.canonicalJson(Object.keys(event).sort())
        !== SharedEvidence.canonicalJson(PROVIDER_CAPTURE_EVENT_KEYS.slice().sort())
      || event.schema !== PROVIDER_CAPTURE_EVENT_SCHEMA || event.runId !== request.runId
      || event.requestId !== request.requestId || event.step !== request.step
      || event.transport !== receipt.transport || !policy
      || event.issuer !== policy.issuer || event.toolResultSource !== policy.toolResultSource
      || event.requestSha256 !== requestSha256 || event.captureArtifact !== captureRelative
      || !Number.isFinite(capturedAt) || new Date(capturedAt).toISOString() !== event.capturedAt
      || !Number.isFinite(fileModifiedAt)
      || new Date(fileModifiedAt).toISOString() !== event.fileModifiedAt
      || !(issuedAt < capturedAt && capturedAt < fileModifiedAt)
      || event.fileModifiedAt !== captureStat.mtime.toISOString()
      || event.captureSha256 !== captureFile.sha256
      || event.captureBytes !== captureFile.bytes.length
      || event.captureWidth !== decoded.width || event.captureHeight !== decoded.height
      || event.captureSemanticContentIndependentlyVerified !== false
      || !PROVIDER_OPERATION_ID_RE.test(String(event.providerEventId || ""))
      || event.providerEventId !== expectedProviderCaptureEventId(event)
      || event.eventSha256 !== reference.eventSha256
      || event.eventSha256 !== SharedEvidence.sha256Text(SharedEvidence.canonicalJson(unsigned))) {
    fail("provider_capture_event_invalid", "control",
      "trusted capture event, actual PNG stat/bytes, and provider identity are not one exact event", {
        step: request.step,
      });
  }
  assertNoRawAuthority(event, "provider_capture_event");
  return { relativePath: expectedRelative, file, value: event,
    capture: { relativePath: captureRelative, sha256: captureFile.sha256,
      bytes: captureFile.bytes.length, mediaType: "image/png",
      width: decoded.width, height: decoded.height, fileModifiedAt: event.fileModifiedAt } };
}

function readProviderReceipt(root, runDir, request, providerReference) {
  const exactRun = SharedEvidence.assertOwnedRunDirectory(path.resolve(root), runDir,
    OWNED_BASE_RELATIVE, "provider_receipt");
  const expectedRelative = providerReceiptRelativePath(request.requestId);
  if (!SharedEvidence.isPlainObject(providerReference)
      || SharedEvidence.canonicalJson(Object.keys(providerReference).sort())
        !== SharedEvidence.canonicalJson(["artifact", "sha256"])
      || providerReference.artifact !== expectedRelative
      || !/^[a-f0-9]{64}$/.test(String(providerReference.sha256 || ""))) {
    fail("provider_receipt_reference_invalid", "control",
      "provider receipt reference is not the exact owned step path", { step: request.step });
  }
  const receiptPath = path.resolve(exactRun, expectedRelative.replace(/\//g, path.sep));
  if (!SharedEvidence.pathInside(exactRun, receiptPath)) {
    fail("provider_receipt_path_escape", "control", "provider receipt escaped the owned run directory");
  }
  const file = SharedEvidence.readExactRegularFile(receiptPath, {
    phase: "provider_receipt", maximumBytes: 64 * 1024,
  });
  if (file.sha256 !== providerReference.sha256) {
    fail("provider_receipt_hash_mismatch", "control",
      "provider receipt reference does not bind the exact file bytes", { step: request.step });
  }
  let receipt;
  try { receipt = JSON.parse(file.bytes.toString("utf8")); }
  catch (error) {
    fail("provider_receipt_invalid", "control", "provider receipt JSON is malformed", {
      step: request.step, message: error.message,
    });
  }
  const requestFile = SharedEvidence.readExactRegularFile(
    path.join(exactRun, "control", "requests", request.requestId + ".json"), {
      phase: "control_request", maximumBytes: 2 * 1024 * 1024,
    });
  let persistedRequest;
  try { persistedRequest = JSON.parse(requestFile.bytes.toString("utf8")); }
  catch (error) {
    fail("control_request_invalid", "control", "persisted control request JSON is malformed", {
      step: request.step, message: error.message,
    });
  }
  if (SharedEvidence.canonicalJson(persistedRequest) !== SharedEvidence.canonicalJson(request)) {
    fail("control_request_artifact_mismatch", "control",
      "persisted request bytes differ from the bundle request", { step: request.step });
  }
  const captureEvent = readProviderCaptureEvent(root, runDir, request, receipt,
    requestFile.sha256);
  return { file, receipt, relativePath: expectedRelative, requestFile,
    captureEvent, capture: captureEvent.capture };
}

function verifyProviderReceiptReference(root, runDir, request, ack) {
  const provider = readProviderReceipt(root, runDir, request, ack.providerReceipt);
  validateProviderReceipt(provider.receipt, request, ack.transport, ack.result, ack.completedAt, {
    requestSha256: provider.requestFile.sha256,
    ownedArtifact: provider.relativePath,
    captureEventRef: { artifact: provider.captureEvent.relativePath,
      sha256: provider.captureEvent.file.sha256,
      eventSha256: provider.captureEvent.value.eventSha256 },
    capturedAt: Date.parse(provider.captureEvent.value.capturedAt),
    fileModifiedAt: Date.parse(provider.captureEvent.value.fileModifiedAt),
  });
  if (!ack.capture || ack.capture.relativePath !== provider.capture.relativePath
      || ack.capture.sha256 !== provider.capture.sha256
      || ack.capture.bytes !== provider.capture.bytes
      || ack.capture.mediaType !== "image/png"
      || ack.captureSha256 !== provider.capture.sha256) {
    fail("provider_capture_reference_invalid", "control",
      "acknowledgement does not reference the provider-owned capture bytes", {
        step: request.step,
      });
  }
  return provider;
}

function writeAck(root, runDir, requestId, rawAck) {
  const input = rawAck || {};
  const allowedInputKeys = new Set(["transport", "result",
    "authorizationDecisionId", "providerReceiptArtifact"]);
  if (!SharedEvidence.isPlainObject(input)
      || Object.keys(input).some((key) => !allowedInputKeys.has(key))
      || !Object.prototype.hasOwnProperty.call(input, "transport")
      || !Object.prototype.hasOwnProperty.call(input, "result")
      || !Object.prototype.hasOwnProperty.call(input, "providerReceiptArtifact")) {
    fail("control_ack_input_invalid", "control",
      "ack helper input is not one exact provider-reference contract");
  }
  const channel = new ControlChannel(root, runDir);
  if (!ID_RE.test(String(requestId || ""))) {
    fail("control_request_id_invalid", "control", "request id is malformed");
  }
  const requestFile = SharedEvidence.readExactRegularFile(channel.requestPath(requestId), {
    phase: "control", maximumBytes: 2 * 1024 * 1024,
  });
  const request = validateRequest(JSON.parse(requestFile.bytes.toString("utf8")));
  if (request.runId !== channel.runId) {
    fail("control_request_invalid", "control", "control request crossed the owned run identity");
  }
  if (Date.now() > Date.parse(request.expiresAt)) {
    fail("control_request_expired", "control", "control request has expired");
  }
  const providerArtifact = String(input.providerReceiptArtifact || "");
  const providerAbsolute = path.isAbsolute(providerArtifact)
    ? path.resolve(providerArtifact) : path.resolve(channel.runDir, providerArtifact);
  const expectedProviderAbsolute = path.join(channel.providerReceiptsDir,
    request.requestId + ".json");
  if (!providerArtifact
      || !SharedEvidence.samePath(providerAbsolute, expectedProviderAbsolute)) {
    fail("provider_receipt_reference_invalid", "control",
      "ack helper requires the provider-prewritten exact step receipt path");
  }
  const providerFile = SharedEvidence.readExactRegularFile(providerAbsolute, {
    phase: "provider_receipt", maximumBytes: 64 * 1024,
  });
  const providerReference = { artifact: providerReceiptRelativePath(request.requestId),
    sha256: providerFile.sha256 };
  const provider = readProviderReceipt(root, runDir, request, providerReference);
  let providerValue;
  try { providerValue = JSON.parse(provider.file.bytes.toString("utf8")); }
  catch (error) {
    fail("provider_receipt_invalid", "control", "provider receipt JSON is malformed", {
      step: request.step, message: error.message,
    });
  }
  const completedAt = new Date().toISOString();
  validateProviderReceipt(providerValue, request, input.transport, input.result, completedAt, {
    requestSha256: provider.requestFile.sha256,
    ownedArtifact: provider.relativePath,
    captureEventRef: { artifact: provider.captureEvent.relativePath,
      sha256: provider.captureEvent.file.sha256,
      eventSha256: provider.captureEvent.value.eventSha256 },
    capturedAt: Date.parse(provider.captureEvent.value.capturedAt),
    fileModifiedAt: Date.parse(provider.captureEvent.value.fileModifiedAt),
  });
  const capture = { relativePath: provider.capture.relativePath,
    sha256: provider.capture.sha256, bytes: provider.capture.bytes, mediaType: "image/png" };
  const ack = validateAck({
    schema: CONTROL_ACK_SCHEMA,
    runId: request.runId,
    requestId: request.requestId,
    step: request.step,
    transport: input.transport,
    result: input.result,
    completedAt,
    capture,
    captureSha256: capture.sha256,
    authorizationDecisionId: input.authorizationDecisionId == null
      ? null : input.authorizationDecisionId,
    providerReceipt: providerReference,
    details: {},
  }, request);
  verifyAckCapture(root, runDir, request, ack);
  verifyProviderReceiptReference(root, runDir, request, ack);
  writeNewJson(channel.ackPath(request.requestId), ack);
  return { request, ack };
}

module.exports = {
  ControlChannel,
  REQUIRED_CONTROL_STEPS,
  expectedControlIntent,
  domInputEvidence,
  expectedProviderCaptureEventId,
  expectedProviderOperationId,
  providerCaptureEventRelativePath,
  RESULTS,
  TRANSPORTS,
  validateAck,
  validateInputEvidence,
  validateProviderReceipt,
  validateRequest,
  readProviderCaptureEvent,
  verifyAckCapture,
  verifyProviderReceiptReference,
  writeAck,
};
