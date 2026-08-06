"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const {
  CONTROL_ACK_SCHEMA,
  CONTROL_REQUEST_SCHEMA,
  PROVIDER_RECEIPT_SCHEMA,
  assertPlainFileInside,
  canonicalJson,
  decodePng,
  fail,
  isPlainObject,
  readJson,
  SHA256_RE,
  sha256File,
  sha256Text,
  sleep,
} = require("./common");

const TRANSPORTS = new Set(["launcher_agent_runtime", "codex_computer_use"]);
const RESULTS = new Set(["completed", "unavailable", "cancelled", "failed"]);
const OPERATION_RE = /^[A-Za-z0-9._~-]{8,160}$/;
const REQUEST_KEYS = Object.freeze(["schema", "runId", "requestId", "step", "actionClass",
  "allowedTransports", "issuedAt", "expiresAt", "ttlMs", "nonce", "transcriptPrefix",
  "instruction", "captureRequired", "expected"]);
const ACK_KEYS = Object.freeze(["schema", "runId", "requestId", "requestSha256", "step",
  "transport", "result", "completedAt", "capture", "providerReceipt"]);
const PROVIDER_KEYS = Object.freeze(["schema", "runId", "requestId", "requestSha256", "step",
  "requestBytes", "transport", "issuer", "toolResultSource", "providerOperationId", "action",
  "result", "startedAt", "inputAt", "captureAt", "completedAt", "inputEvidence",
  "ownedArtifact", "captureArtifact",
  "captureSha256", "captureBytes", "captureWidth", "captureHeight", "details",
  "receiptSha256"]);
const INPUT_EVIDENCE_KEYS = Object.freeze(["kind", "observedAt", "eventRef", "eventType", "isTrusted",
  "selector", "tagName", "origin", "visible", "enabled", "viewport", "rect",
  "clientPoint", "hitTargetMatches", "key", "button", "repeat"]);

function sameKeys(value, expected) {
  return isPlainObject(value)
    && canonicalJson(Object.keys(value).sort()) === canonicalJson(expected.slice().sort());
}

function captureIdentity(filePath) {
  const decoded = decodePng(fs.readFileSync(filePath));
  if (decoded.width < 320 || decoded.height < 180) {
    fail("control_capture_dimensions_invalid", "control_capture",
      "provider capture must contain a useful visible viewport", {
        width: decoded.width, height: decoded.height,
      });
  }
  return decoded;
}

function finitePoint(value) {
  return isPlainObject(value)
    && sameKeys(value, ["x", "y"])
    && Number.isFinite(value.x) && Number.isFinite(value.y);
}

function finiteRect(value) {
  return isPlainObject(value)
    && sameKeys(value, ["x", "y", "width", "height"])
    && Object.values(value).every(Number.isFinite)
    && value.width > 0 && value.height > 0;
}

function validEventRef(value) {
  return isPlainObject(value) && sameKeys(value, ["observerId", "sequence", "eventSha256"])
    && OPERATION_RE.test(String(value.observerId || ""))
    && Number.isInteger(value.sequence) && value.sequence > 0
    && SHA256_RE.test(String(value.eventSha256 || ""));
}

function validateInputEvidence(value) {
  if (!sameKeys(value, INPUT_EVIDENCE_KEYS)) {
    fail("provider_input_evidence_invalid", "control",
      "provider input evidence is not one exact closed interaction contract");
  }
  if (value.kind === "non_input_operation") {
    if (!Number.isFinite(Date.parse(value.observedAt))
        || new Date(Date.parse(value.observedAt)).toISOString() !== value.observedAt
        || value.eventRef !== null || value.eventType !== "provider_operation"
        || value.isTrusted !== null || value.selector !== null || value.tagName !== null
        || value.origin !== null || value.visible !== null || value.enabled !== null
        || value.viewport !== null || value.rect !== null || value.clientPoint !== null
        || value.hitTargetMatches !== null || value.key !== null || value.button !== null
        || value.repeat !== false) {
      fail("provider_input_evidence_invalid", "control",
        "non-input provider evidence must use the exact null projection");
    }
    return value;
  }
  const web = value.kind === "web_dom_event";
  const native = value.kind === "native_input";
  const viewport = value.viewport;
  const viewportValid = isPlainObject(viewport) && sameKeys(viewport, ["width", "height"])
    && Number.isFinite(viewport.width) && viewport.width >= 320
    && Number.isFinite(viewport.height) && viewport.height >= 180;
  const observed = Date.parse(value.observedAt);
  if ((!web && !native) || !Number.isFinite(observed)
      || new Date(observed).toISOString() !== value.observedAt
      || (web ? !validEventRef(value.eventRef) : value.eventRef !== null)
      || !["click", "keydown", "input", "change"].includes(value.eventType)
      || value.isTrusted !== true || typeof value.selector !== "string" || !value.selector
      || typeof value.tagName !== "string" || !value.tagName
      || typeof value.origin !== "string" || !value.origin
      || value.visible !== true || value.enabled !== true || !viewportValid
      || !finiteRect(value.rect)
      || !(value.key === null || typeof value.key === "string")
      || !(value.button === null || Number.isInteger(value.button))
      || typeof value.repeat !== "boolean"
      || (value.eventType === "click" && (value.button !== 0 || value.key !== null
        || !finitePoint(value.clientPoint)
        || value.clientPoint.x < value.rect.x
        || value.clientPoint.x > value.rect.x + value.rect.width
        || value.clientPoint.y < value.rect.y
        || value.clientPoint.y > value.rect.y + value.rect.height
        || value.hitTargetMatches !== true))
      || (value.eventType !== "click"
        && (value.clientPoint !== null || value.hitTargetMatches !== null))
      || (value.eventType === "keydown" && (!value.key || value.button !== null))
      || (["input", "change"].includes(value.eventType)
        && (value.key !== null || value.button !== null))) {
    fail("provider_input_evidence_invalid", "control",
      "provider input evidence lacks exact target, geometry, hit-test, key, or event ownership");
  }
  return value;
}

function expectedProviderOperationId(receipt) {
  const operation = Object.assign({}, receipt);
  delete operation.providerOperationId;
  delete operation.receiptSha256;
  return "npcop-" + sha256Text(canonicalJson(operation));
}

function domInputEvidence(observerId, event) {
  const target = event && event.target;
  const pointer = event && event.eventType === "click";
  if (!isPlainObject(event) || !isPlainObject(target)) return null;
  return {
    kind: "web_dom_event",
    observedAt: event.observedAt,
    eventRef: { observerId, sequence: event.sequence, eventSha256: event.eventHash },
    eventType: event.eventType,
    isTrusted: event.isTrusted === true,
    selector: target.selector,
    tagName: target.tagName,
    origin: target.origin,
    visible: target.visible === true,
    enabled: target.enabled === true,
    viewport: target.viewport,
    rect: target.rect,
    clientPoint: pointer ? { x: event.clientX, y: event.clientY } : null,
    hitTargetMatches: pointer && target.hitTest
      ? target.hitTest.matchesTarget === true : null,
    key: event.eventType === "keydown" ? String(event.key || "") : null,
    button: pointer ? event.button : null,
    repeat: event.eventType === "keydown" ? event.repeat === true : false,
  };
}

function providerReceiptRelativePath(requestIdValue) {
  return "controls/provider-receipts/" + String(requestIdValue) + ".json";
}

function captureRelativePath(requestIdValue) {
  return "controls/captures/" + String(requestIdValue) + ".png";
}

function expectedInputTarget(request) {
  const step = String(request && request.step || "");
  if (["capability_probe", "authorize_codex_fallback"].includes(step)) {
    return { kind: "non_input_operation", eventType: "provider_operation",
      selector: null, tagName: null, origin: null };
  }
  if (["open_first", "safe_exit", "exit_confirm", "open_restart_readback"].includes(step)) {
    return { kind: "native_input", eventType: "click",
      selector: "native-control[data-step=\"" + step + "\"]",
      tagName: "BUTTON", origin: "launcher://native" };
  }
  const fixed = {
    open_purchase_settlement: ["button.npcshop-checkout-btn", "BUTTON", "click"],
    open_sale_settlement: ["button.npcshop-checkout-btn", "BUTTON", "click"],
    commit_purchase: ["button[data-trade-commit]", "BUTTON", "click"],
    commit_sale: ["button[data-trade-commit]", "BUTTON", "click"],
    set_sale_quantity: ["input.workbench-quantity-number", "INPUT", "input"],
    close_before_exit: ["button[aria-label=\"关闭 NPC 商店\"]", "BUTTON", "click"],
    close_restart_readback: ["button[aria-label=\"关闭 NPC 商店\"]", "BUTTON", "click"],
  };
  let target = fixed[step];
  if (step === "select_purchase") {
    const catalogIndex = request && request.expected && request.expected.catalogIndex;
    if (!Number.isInteger(catalogIndex) || catalogIndex < 0) {
      fail("provider_target_contract_invalid", "control",
        "purchase input target requires the frozen catalog index", { step });
    }
    target = ["article[data-workbench-key=\"" + catalogIndex + "\"]", "ARTICLE", "click"];
  }
  if (step === "select_sale") {
    const slot = request && request.expected && request.expected.slot;
    if (!Number.isInteger(slot) || slot < 0 || slot > 49) {
      fail("provider_target_contract_invalid", "control",
        "sale input target requires the frozen physical slot", { step });
    }
    target = ["article[data-workbench-key=\"" + slot + "\"]", "ARTICLE", "click"];
  }
  if (!target) {
    fail("provider_target_contract_invalid", "control",
      "control step has no frozen provider input target", { step });
  }
  return { kind: "web_dom_event", selector: target[0], tagName: target[1],
    eventType: target[2], origin: "https://overlay.local" };
}

function validateExpectedInputTarget(evidence, request) {
  const expected = expectedInputTarget(request);
  if (evidence.kind !== expected.kind || evidence.eventType !== expected.eventType
      || evidence.selector !== expected.selector || evidence.tagName !== expected.tagName
      || evidence.origin !== expected.origin) {
    fail("provider_input_target_mismatch", "control",
      "provider input evidence does not match the step-specific frozen target", {
        step: request.step, expected,
      });
  }
}

function validateProviderReceipt(receipt, request, requestSha256, requestBytes,
  transport, result, completedAt) {
  const expectedSource = transport === "launcher_agent_runtime"
    ? "launcher_agent_runtime_tool_result" : "codex_computer_use_tool_result";
  const issued = Date.parse(request.issuedAt);
  const expires = Date.parse(request.expiresAt);
  const ackCompleted = completedAt == null ? null : Date.parse(completedAt);
  validateInputEvidence(receipt && receipt.inputEvidence);
  validateExpectedInputTarget(receipt && receipt.inputEvidence, request);
  const started = Date.parse(receipt && receipt.startedAt);
  const input = Date.parse(receipt && receipt.inputAt);
  const capture = Date.parse(receipt && receipt.captureAt);
  const providerCompleted = Date.parse(receipt && receipt.completedAt);
  if (!sameKeys(receipt, PROVIDER_KEYS)
      || receipt.schema !== PROVIDER_RECEIPT_SCHEMA || receipt.runId !== request.runId
      || receipt.requestId !== request.requestId || receipt.requestSha256 !== requestSha256
      || receipt.requestBytes !== requestBytes
      || receipt.step !== request.step || receipt.transport !== transport
      || receipt.issuer !== transport || receipt.toolResultSource !== expectedSource
      || receipt.action !== request.step || receipt.result !== result
      || !OPERATION_RE.test(String(receipt.providerOperationId || ""))
      || receipt.providerOperationId !== expectedProviderOperationId(receipt)
      || receipt.ownedArtifact !== providerReceiptRelativePath(request.requestId)
      || receipt.captureArtifact !== captureRelativePath(request.requestId)
      || !SHA256_RE.test(String(receipt.captureSha256 || ""))
      || !Number.isInteger(receipt.captureBytes) || receipt.captureBytes < 1
      || !Number.isInteger(receipt.captureWidth) || receipt.captureWidth < 320
      || !Number.isInteger(receipt.captureHeight) || receipt.captureHeight < 180
      || !isPlainObject(receipt.details)
      || ![started, input, capture, providerCompleted].every(Number.isFinite)
      || new Date(started).toISOString() !== receipt.startedAt
      || new Date(input).toISOString() !== receipt.inputAt
      || new Date(capture).toISOString() !== receipt.captureAt
      || new Date(providerCompleted).toISOString() !== receipt.completedAt
      || receipt.inputEvidence.observedAt !== receipt.inputAt
      || !(issued < started && started < input && input < capture
        && capture < providerCompleted && providerCompleted <= expires)
      || ackCompleted !== null && (!Number.isFinite(ackCompleted)
        || providerCompleted >= ackCompleted || ackCompleted > expires)) {
    fail("provider_receipt_invalid", "control",
      "control acknowledgement lacks one exact provider-owned tool-result receipt", {
        step: request.step,
      });
  }
  const unsigned = Object.assign({}, receipt);
  delete unsigned.receiptSha256;
  if (receipt.receiptSha256 !== sha256Text(canonicalJson(unsigned))) {
    fail("provider_receipt_digest_invalid", "control",
      "provider tool-result receipt digest is detached", { step: request.step });
  }
  return receipt;
}

function exactRunDirectory(root, runDir) {
  const expected = path.resolve(root, "tmp", "workbench-live-e2e", "npc");
  const resolved = path.resolve(runDir);
  const relative = path.relative(expected, resolved);
  if (!relative || relative.startsWith(".." + path.sep) || path.isAbsolute(relative)
      || relative.includes(path.sep)) {
    fail("run_directory_invalid", "control",
      "NPC run directory must be one exact child of tmp/workbench-live-e2e/npc");
  }
  const stat = fs.lstatSync(resolved);
  if (!stat.isDirectory() || stat.isSymbolicLink()
      || fs.realpathSync.native(resolved).toLowerCase() !== resolved.toLowerCase()) {
    fail("run_directory_invalid", "control", "NPC run directory must be a plain exact directory");
  }
  return resolved;
}

function immutableJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", {
    encoding: "utf8", mode: 0o600, flag: "wx",
  });
}

function requestId(step) {
  return "npc." + String(step).replace(/[^A-Za-z0-9._-]/g, "-") + "."
    + Date.now().toString(36) + "." + crypto.randomBytes(8).toString("hex");
}

function validateRequest(request) {
  if (!sameKeys(request, REQUEST_KEYS) || request.schema !== CONTROL_REQUEST_SCHEMA
      || typeof request.runId !== "string" || !request.runId
      || typeof request.requestId !== "string" || !request.requestId
      || typeof request.step !== "string" || !request.step
      || !["capability_probe", "authorization", "business", "lifecycle"].includes(request.actionClass)
      || !Array.isArray(request.allowedTransports) || request.allowedTransports.length < 1
      || new Set(request.allowedTransports).size !== request.allowedTransports.length
      || request.allowedTransports.some((entry) => !TRANSPORTS.has(entry))
      || !Number.isInteger(request.ttlMs) || request.ttlMs < 1000 || request.ttlMs > 600000
      || typeof request.nonce !== "string" || !request.nonce
      || typeof request.instruction !== "string" || !request.instruction.trim()
      || request.captureRequired !== true || !isPlainObject(request.transcriptPrefix)
      || !Number.isInteger(request.transcriptPrefix.eventCount) || request.transcriptPrefix.eventCount < 0
      || !/^[a-f0-9]{64}$/.test(String(request.transcriptPrefix.chainHead || ""))) {
    fail("control_request_invalid", "control", "control request is not one exact closed contract");
  }
  const issued = Date.parse(request.issuedAt);
  const expires = Date.parse(request.expiresAt);
  if (!Number.isFinite(issued) || new Date(issued).toISOString() !== request.issuedAt
      || !Number.isFinite(expires) || new Date(expires).toISOString() !== request.expiresAt
      || expires - issued !== request.ttlMs) {
    fail("control_request_invalid", "control", "control request TTL is invalid");
  }
  return request;
}

function validateAck(ack, request, requestSha256) {
  if (!sameKeys(ack, ACK_KEYS) || ack.schema !== CONTROL_ACK_SCHEMA
      || ack.runId !== request.runId || ack.requestId !== request.requestId
      || ack.requestSha256 !== requestSha256 || ack.step !== request.step
      || !TRANSPORTS.has(ack.transport) || !request.allowedTransports.includes(ack.transport)
      || !RESULTS.has(ack.result) || !isPlainObject(ack.capture)
      || canonicalJson(Object.keys(ack.capture).sort()) !== canonicalJson(["artifact", "sha256"])
      || ack.capture.artifact !== captureRelativePath(request.requestId)
      || !SHA256_RE.test(String(ack.capture.sha256 || ""))
      || !isPlainObject(ack.providerReceipt)
      || canonicalJson(Object.keys(ack.providerReceipt).sort()) !== canonicalJson(["artifact", "sha256"])
      || ack.providerReceipt.artifact !== providerReceiptRelativePath(request.requestId)
      || !SHA256_RE.test(String(ack.providerReceipt.sha256 || ""))) {
    fail("control_ack_invalid", "control", "control acknowledgement is not one exact reference contract");
  }
  const issued = Date.parse(request.issuedAt);
  const expires = Date.parse(request.expiresAt);
  const completed = Date.parse(ack.completedAt);
  if (!Number.isFinite(completed) || new Date(completed).toISOString() !== ack.completedAt
      || completed < issued || completed > expires) {
    fail("control_ack_expired", "control", "control acknowledgement is outside request TTL");
  }
  return ack;
}

function exactProviderEvidence(runDir, request, requestSha256, transport, result, completedAt) {
  const providerRelative = providerReceiptRelativePath(request.requestId);
  const captureRelative = captureRelativePath(request.requestId);
  const providerSnapshot = assertPlainFileInside(runDir, providerRelative, "provider_receipt");
  const captureSnapshot = assertPlainFileInside(runDir, captureRelative, "control_capture");
  const capture = captureIdentity(captureSnapshot.filePath);
  const provider = validateProviderReceipt(readJson(providerSnapshot.filePath, "provider_receipt"),
    request, requestSha256, requestSnapshotBytes(runDir, request), transport, result, completedAt);
  if (provider.captureSha256 !== sha256File(captureSnapshot.filePath)
      || provider.captureBytes !== captureSnapshot.stat.size
      || provider.captureWidth !== capture.width || provider.captureHeight !== capture.height) {
    fail("provider_capture_binding_invalid", "control",
      "provider receipt is detached from its exact visible capture", { step: request.step });
  }
  return { providerSnapshot, captureSnapshot, provider, capture };
}

function requestSnapshotBytes(runDir, request) {
  return assertPlainFileInside(runDir,
    "controls/requests/" + request.requestId + ".json", "control_request").stat.size;
}

class ControlChannel {
  constructor(root, runDir, runId) {
    this.root = path.resolve(root);
    this.runDir = exactRunDirectory(this.root, runDir);
    this.runId = String(runId);
    this.requestsDir = path.join(this.runDir, "controls", "requests");
    this.acksDir = path.join(this.runDir, "controls", "acks");
    this.capturesDir = path.join(this.runDir, "controls", "captures");
    this.providerReceiptsDir = path.join(this.runDir, "controls", "provider-receipts");
    [this.requestsDir, this.acksDir, this.capturesDir, this.providerReceiptsDir]
      .forEach((directory) => fs.mkdirSync(directory, { recursive: true }));
  }

  issue(step, options) {
    const settings = options || {};
    const ttlMs = Number(settings.ttlMs || 300000);
    const issued = new Date();
    const request = validateRequest({
      schema: CONTROL_REQUEST_SCHEMA, runId: this.runId, requestId: requestId(step),
      step: String(step), actionClass: String(settings.actionClass || "business"),
      allowedTransports: Array.from(new Set(settings.allowedTransports || [])),
      issuedAt: issued.toISOString(), expiresAt: new Date(issued.getTime() + ttlMs).toISOString(),
      ttlMs, nonce: crypto.randomBytes(24).toString("hex"),
      transcriptPrefix: settings.transcriptPrefix, instruction: String(settings.instruction || ""),
      captureRequired: true, expected: settings.expected || null,
    });
    const requestPath = path.join(this.requestsDir, request.requestId + ".json");
    immutableJson(requestPath, request);
    return Object.assign({ requestPath, requestSha256: sha256File(requestPath) }, request);
  }

  ackPath(id) { return path.join(this.acksDir, String(id) + ".json"); }

  async wait(request, pollMs) {
    validateRequest(request);
    const requestPath = path.join(this.requestsDir, request.requestId + ".json");
    const requestSha256 = sha256File(requestPath);
    const deadline = Date.parse(request.expiresAt);
    while (Date.now() <= deadline) {
      const ackPath = this.ackPath(request.requestId);
      if (fs.existsSync(ackPath)) {
        const ack = validateAck(readJson(ackPath, "control_ack"), request, requestSha256);
        const evidence = exactProviderEvidence(this.runDir, request, requestSha256,
          ack.transport, ack.result, ack.completedAt);
        if (ack.capture.sha256 !== sha256File(evidence.captureSnapshot.filePath)
            || ack.providerReceipt.sha256 !== sha256File(evidence.providerSnapshot.filePath)) {
          fail("control_evidence_hash_mismatch", "control",
            "ack references differ from exact provider-owned evidence");
        }
        return Object.assign({ ackPath, providerEvidence: evidence.provider }, ack);
      }
      await sleep(Number(pollMs || 250));
    }
    fail("control_ack_timeout", "control", "control request expired without acknowledgement", {
      requestId: request.requestId, step: request.step,
    });
  }
}

function writeAck(root, runDir, requestIdValue, rawAck) {
  const allowed = ["transport", "result", "providerReceiptArtifact"];
  if (!isPlainObject(rawAck) || canonicalJson(Object.keys(rawAck).sort())
      !== canonicalJson(allowed.slice().sort())) {
    fail("control_ack_input_invalid", "control",
      "ack helper accepts only provider receipt references and acknowledgement metadata");
  }
  const resolvedRun = exactRunDirectory(root, runDir);
  const requestRelative = path.join("controls", "requests", String(requestIdValue) + ".json");
  const requestSnapshot = assertPlainFileInside(resolvedRun, requestRelative, "control_ack");
  const requestSha256 = sha256File(requestSnapshot.filePath);
  const request = validateRequest(readJson(requestSnapshot.filePath, "control_request"));
  const expectedProvider = providerReceiptRelativePath(request.requestId);
  const givenProvider = path.relative(resolvedRun, path.resolve(resolvedRun,
    String(rawAck.providerReceiptArtifact || ""))).replace(/\\/g, "/");
  if (givenProvider !== expectedProvider) {
    fail("provider_receipt_reference_invalid", "control",
      "ack helper only references the provider-prewritten exact receipt path");
  }
  const completedAt = new Date().toISOString();
  const evidence = exactProviderEvidence(resolvedRun, request, requestSha256,
    rawAck.transport, rawAck.result, completedAt);
  const ack = validateAck({
    schema: CONTROL_ACK_SCHEMA, runId: request.runId, requestId: request.requestId,
    requestSha256, step: request.step, transport: rawAck.transport, result: rawAck.result,
    completedAt,
    capture: { artifact: captureRelativePath(request.requestId),
      sha256: sha256File(evidence.captureSnapshot.filePath) },
    providerReceipt: { artifact: expectedProvider,
      sha256: sha256File(evidence.providerSnapshot.filePath) },
  }, request, requestSha256);
  const ackPath = path.join(resolvedRun, "controls", "acks", request.requestId + ".json");
  immutableJson(ackPath, ack);
  return { ackPath, ack, sha256: sha256File(ackPath) };
}

module.exports = {
  ACK_KEYS,
  ControlChannel,
  PROVIDER_KEYS,
  INPUT_EVIDENCE_KEYS,
  REQUEST_KEYS,
  RESULTS,
  TRANSPORTS,
  captureIdentity,
  captureRelativePath,
  exactProviderEvidence,
  exactRunDirectory,
  domInputEvidence,
  expectedProviderOperationId,
  providerReceiptRelativePath,
  validateAck,
  validateInputEvidence,
  validateProviderReceipt,
  validateRequest,
  writeAck,
};
