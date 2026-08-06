"use strict";

const fs = require("fs");
const {
  CONTROL_ACK_SCHEMA,
  CONTROL_REQUEST_SCHEMA,
  PROVIDER_RECEIPT_SCHEMA,
  SHA256_RE,
  canonicalJson,
  decodePng,
  fail,
  isPlainObject,
  readManifestJson,
  requireOne,
  sha256Bytes,
} = require("./common");
const {
  captureRelativePath,
  domInputEvidence,
  providerReceiptRelativePath,
  validateAck,
  validateProviderReceipt,
  validateRequest,
} = require("./control-channel");

const TRANSPORTS = new Set(["launcher_agent_runtime", "codex_computer_use"]);
const RESULTS = new Set(["completed", "unavailable", "cancelled", "failed"]);

function parseTime(value, code, phase, label) {
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) fail(code, phase, label + " timestamp is invalid", { value });
  return timestamp;
}

function transcriptPrefix(transcript, count) {
  if (!Number.isInteger(count) || count < 0 || count > transcript.events.length) {
    fail("control_prefix_invalid", "control", "control transcript prefix count is invalid", { count });
  }
  return count === 0 ? "0".repeat(64) : transcript.events[count - 1].eventHash;
}

function verifyBindingEvents(binding, request, ack, transcript) {
  const eventBindings = Array.isArray(binding.events) ? binding.events : [];
  const issuedAt = parseTime(request.issuedAt, "control_request_time_invalid", "control", "request issuedAt");
  const completedAt = parseTime(ack.completedAt, "control_ack_time_invalid", "control", "ack completedAt");
  const prefixCount = request.transcriptPrefix.eventCount;
  const seen = new Set();
  eventBindings.forEach((bound) => {
    if (!isPlainObject(bound) || !Number.isInteger(bound.sequence)
        || bound.sequence <= prefixCount || bound.sequence > transcript.events.length
        || typeof bound.role !== "string" || !bound.role || seen.has(bound.sequence)) {
      fail("control_event_binding_invalid", "control", "control event binding is invalid or duplicated", {
        step: request.step,
        binding: bound,
      });
    }
    const event = transcript.events[bound.sequence - 1];
    if (bound.eventHash !== event.eventHash) {
      fail("control_event_hash_mismatch", "control", "control event binding hash is invalid", {
        step: request.step,
        sequence: bound.sequence,
      });
    }
    const observedAt = parseTime(event.observedAt, "event_time_invalid", "control", "event observedAt");
    if (observedAt <= issuedAt || observedAt >= completedAt) {
      fail("control_event_outside_window", "control", "bound event falls outside request/ack window", {
        step: request.step,
        sequence: bound.sequence,
      });
    }
    seen.add(bound.sequence);
  });
  if (request.actionClass === "business" && eventBindings.length < 1) {
    fail("business_control_unbound", "control", "business control has no exact passive-event binding", {
      step: request.step,
    });
  }
  return eventBindings;
}

function verifyCapture(ack, artifacts, step) {
  if (!isPlainObject(ack.capture) || typeof ack.capture.artifact !== "string"
      || !SHA256_RE.test(String(ack.capture.sha256 || ""))) {
    fail("control_capture_missing", "control", "control acknowledgement lacks an actual capture digest", { step });
  }
  const artifact = artifacts.get(ack.capture.artifact);
  if (!artifact || artifact.role !== "control_capture") {
    fail("control_capture_reference_invalid", "control", "control capture is absent from the sealed manifest", {
      step,
      artifact: ack.capture.artifact,
    });
  }
  const bytes = fs.readFileSync(artifact.absolutePath);
  const actual = sha256Bytes(bytes);
  if (actual !== ack.capture.sha256 || actual !== artifact.sha256) {
    fail("control_capture_hash_mismatch", "control", "control capture digest does not match actual bytes", { step });
  }
  if (!/\.png$/i.test(ack.capture.artifact)) {
    fail("control_capture_media_invalid", "control", "control capture must be a PNG artifact", { step });
  }
  const decoded = decodePng(bytes);
  if (decoded.width < 320 || decoded.height < 180) {
    fail("control_capture_dimensions_invalid", "control",
      "control capture does not contain a useful visible viewport", {
        step, width: decoded.width, height: decoded.height,
      });
  }
  return { sha256: actual, bytes: bytes.length, width: decoded.width, height: decoded.height };
}

function verifyProvider(ack, request, requestSha256, requestBytes, artifacts, step, capture) {
  if (!isPlainObject(ack.providerReceipt)
      || typeof ack.providerReceipt.artifact !== "string"
      || !SHA256_RE.test(String(ack.providerReceipt.sha256 || ""))) {
    fail("provider_receipt_missing", "control",
      "control acknowledgement lacks an immutable provider observation", { step });
  }
  const artifact = artifacts.get(ack.providerReceipt.artifact);
  if (!artifact || artifact.role !== "provider_receipt") {
    fail("provider_receipt_reference_invalid", "control",
      "provider observation is absent from the sealed manifest", { step });
  }
  const actual = sha256Bytes(fs.readFileSync(artifact.absolutePath));
  if (actual !== ack.providerReceipt.sha256 || actual !== artifact.sha256) {
    fail("provider_receipt_hash_mismatch", "control",
      "provider observation digest does not match sealed bytes", { step });
  }
  const receipt = readManifestJson(artifacts, ack.providerReceipt.artifact,
    "provider_receipt", "control");
  if (receipt.schema !== PROVIDER_RECEIPT_SCHEMA) {
    fail("provider_receipt_invalid", "control", "provider receipt schema is invalid", { step });
  }
  validateProviderReceipt(receipt, request, requestSha256, requestBytes, ack.transport, ack.result,
    ack.completedAt);
  if (receipt.ownedArtifact !== providerReceiptRelativePath(request.requestId)
      || receipt.captureArtifact !== captureRelativePath(request.requestId)
      || receipt.captureSha256 !== capture.sha256
      || receipt.captureBytes !== capture.bytes
      || receipt.captureWidth !== capture.width || receipt.captureHeight !== capture.height) {
    fail("provider_capture_binding_invalid", "control",
      "provider tool result is detached from the exact owned capture", { step });
  }
  return receipt;
}

function verifyProviderInputBinding(receipt, request, eventBindings, transcript) {
  const boundDom = eventBindings.map((binding) => transcript.events[binding.sequence - 1])
    .filter((event) => event && event.kind === "dom_input");
  if (boundDom.length > 1) {
    fail("provider_dom_binding_ambiguous", "control",
      "one provider operation cannot own multiple bound DOM input events", { step: request.step });
  }
  if (boundDom.length === 1) {
    const event = boundDom[0];
    const target = event.target;
    if (!target || (event.eventType === "click"
      && (!Number.isFinite(event.clientX) || !Number.isFinite(event.clientY)
        || !target.clientPoint || event.clientX !== target.clientPoint.x
        || event.clientY !== target.clientPoint.y))) {
      fail("dom_input_coordinate_binding_invalid", "control",
        "raw DOM client coordinates are not independently bound to target geometry", {
          step: request.step, sequence: event.sequence,
        });
    }
    if (canonicalJson(receipt.inputEvidence)
        !== canonicalJson(domInputEvidence(transcript.observerId, event))) {
      fail("provider_dom_binding_invalid", "control",
        "provider input receipt does not bind the exact observer DOM event", {
          step: request.step, sequence: event.sequence,
        });
    }
    return;
  }
  const expectedKind = ["capability_probe", "authorize_codex_fallback"].includes(request.step)
    ? "non_input_operation" : "native_input";
  if (receipt.inputEvidence.kind !== expectedKind || receipt.inputEvidence.eventRef !== null) {
    fail("provider_input_binding_invalid", "control",
      "non-DOM control step has the wrong exact provider input class", { step: request.step });
  }
}

function loadControl(binding, bundle, artifacts, transcript) {
  if (!isPlainObject(binding) || typeof binding.requestArtifact !== "string"
      || typeof binding.ackArtifact !== "string") {
    fail("control_binding_invalid", "control", "control binding is malformed");
  }
  const request = readManifestJson(artifacts, binding.requestArtifact, "control_request", "control");
  const ack = readManifestJson(artifacts, binding.ackArtifact, "control_ack", "control");
  validateRequest(request);
  const requestArtifact = artifacts.get(binding.requestArtifact);
  if (!requestArtifact) {
    fail("control_request_missing", "control", "control request artifact is absent");
  }
  validateAck(ack, request, requestArtifact.sha256);
  if (request.schema !== CONTROL_REQUEST_SCHEMA || ack.schema !== CONTROL_ACK_SCHEMA
      || request.runId !== bundle.runId || ack.runId !== bundle.runId
      || request.requestId !== ack.requestId || request.step !== ack.step
      || binding.step !== request.step) {
    fail("control_identity_mismatch", "control", "control request/ack/run identities do not match", {
      step: binding.step,
    });
  }
  if (!requestArtifact || ack.requestSha256 !== requestArtifact.sha256) {
    fail("control_request_hash_mismatch", "control", "ack does not bind the actual request artifact", {
      step: request.step,
    });
  }
  if (!Array.isArray(request.allowedTransports) || request.allowedTransports.length < 1
      || request.allowedTransports.some((transport) => !TRANSPORTS.has(transport))
      || !TRANSPORTS.has(ack.transport) || !request.allowedTransports.includes(ack.transport)
      || !RESULTS.has(ack.result)) {
    fail("control_transport_invalid", "control", "control transport/result is invalid", { step: request.step });
  }
  const issuedAt = parseTime(request.issuedAt, "control_request_time_invalid", "control", "request issuedAt");
  const expiresAt = parseTime(request.expiresAt, "control_request_time_invalid", "control", "request expiresAt");
  const completedAt = parseTime(ack.completedAt, "control_ack_time_invalid", "control", "ack completedAt");
  if (!Number.isInteger(request.ttlMs) || request.ttlMs < 1000 || request.ttlMs > 600000
      || expiresAt - issuedAt !== request.ttlMs || completedAt < issuedAt || completedAt > expiresAt) {
    fail("control_ttl_invalid", "control", "control acknowledgement is outside the exact request TTL", {
      step: request.step,
    });
  }
  if (!isPlainObject(request.transcriptPrefix)
      || transcriptPrefix(transcript, request.transcriptPrefix.eventCount)
        !== request.transcriptPrefix.chainHead) {
    fail("control_prefix_invalid", "control", "control request does not bind the actual transcript prefix", {
      step: request.step,
    });
  }
  if (request.transcriptPrefix.eventCount > 0) {
    const prefixTail = transcript.events[request.transcriptPrefix.eventCount - 1];
    const prefixTailAt = parseTime(prefixTail.observedAt,
      "control_prefix_time_invalid", "control", "control prefix tail");
    if (prefixTailAt >= issuedAt) {
      fail("control_prefix_time_invalid", "control",
        "control request must be issued after its exact transcript prefix", {
          step: request.step, sequence: prefixTail.sequence,
        });
    }
  }
  const capture = verifyCapture(ack, artifacts, request.step);
  const providerReceipt = verifyProvider(ack, request, requestArtifact.sha256,
    requestArtifact.bytes,
    artifacts, request.step, capture);
  const events = verifyBindingEvents(binding, request, ack, transcript);
  verifyProviderInputBinding(providerReceipt, request, events, transcript);
  return { binding, request, ack, events, captureSha256: capture.sha256,
    capture, providerReceipt };
}

function expectedBusinessSteps(mode, saleQuantityAdjustment) {
  const steps = [
    "open_first",
    "select_purchase",
    "open_purchase_settlement",
    "commit_purchase",
  ];
  if (mode === "purchase_then_explicit_sale") {
    steps.push("select_sale", "open_sale_settlement");
    if (saleQuantityAdjustment) steps.push("set_sale_quantity");
    steps.push("commit_sale");
  }
  steps.push("close_before_exit", "safe_exit", "exit_confirm",
    "open_restart_readback", "close_restart_readback");
  return steps;
}

function verifyControls(bundle, artifacts, transcript) {
  if (!Array.isArray(bundle.controls)) fail("controls_missing", "control", "control bindings are missing");
  const loaded = bundle.controls.map((binding) => loadControl(binding, bundle, artifacts, transcript));
  const capability = requireOne(loaded.filter((entry) => entry.request.step === "capability_probe"),
    "capability_probe_count_invalid", "control", "Launcher Agent capability must be probed exactly once");
  if (capability.request.actionClass !== "capability_probe"
      || canonicalJson(capability.request.allowedTransports) !== canonicalJson(["launcher_agent_runtime"])
      || !["completed", "unavailable"].includes(capability.ack.result)
      || capability.ack.transport !== "launcher_agent_runtime") {
    fail("capability_probe_invalid", "control", "Launcher Agent capability probe contract is invalid");
  }
  let selectedTransport;
  let fallbackAuthorization = null;
  if (capability.ack.result === "completed") {
    if (canonicalJson(Object.keys(capability.providerReceipt.details).sort())
        !== canonicalJson(["capabilities"])
        || !Array.isArray(capability.providerReceipt.details.capabilities)
        || !capability.providerReceipt.details.capabilities.includes("npc_input")) {
      fail("capability_provider_details_invalid", "control",
        "completed Launcher capability must be asserted by the provider-owned receipt");
    }
    selectedTransport = "launcher_agent_runtime";
    if (loaded.some((entry) => entry.request.step === "authorize_codex_fallback")) {
      fail("unexpected_fallback_authorization", "control", "Codex fallback was authorized even though Launcher Agent was available");
    }
  } else {
    const capabilityDetails = capability.providerReceipt.details;
    if (canonicalJson(Object.keys(capabilityDetails).sort()) !== canonicalJson(["reasonCode"])
        || typeof capabilityDetails.reasonCode !== "string" || !capabilityDetails.reasonCode) {
      fail("capability_unavailable_reason_missing", "control", "unavailable Launcher capability lacks a reason code");
    }
    fallbackAuthorization = requireOne(loaded.filter((entry) => entry.request.step === "authorize_codex_fallback"),
      "fallback_authorization_count_invalid", "control", "Codex fallback must be explicitly authorized exactly once");
    if (fallbackAuthorization.request.actionClass !== "authorization"
        || canonicalJson(fallbackAuthorization.request.allowedTransports) !== canonicalJson(["codex_computer_use"])
        || fallbackAuthorization.ack.result !== "completed"
        || fallbackAuthorization.ack.transport !== "codex_computer_use"
        || canonicalJson(Object.keys(fallbackAuthorization.providerReceipt.details).sort())
          !== canonicalJson(["capabilityReasonCode", "capabilityRequestId", "explicitAuthorization"].sort())
        || fallbackAuthorization.providerReceipt.details.explicitAuthorization !== true
        || fallbackAuthorization.providerReceipt.details.capabilityRequestId !== capability.request.requestId
        || fallbackAuthorization.providerReceipt.details.capabilityReasonCode !== capabilityDetails.reasonCode) {
      fail("fallback_authorization_invalid", "control", "Codex fallback authorization is not tied to the unavailable capability probe");
    }
    selectedTransport = "codex_computer_use";
  }

  const expected = expectedBusinessSteps(bundle.journeyMode,
    !!(bundle.salePolicy && bundle.salePolicy.requiresQuantityAdjustment));
  const business = loaded.filter((entry) => ["business", "lifecycle"].includes(entry.request.actionClass));
  const exactOrder = ["capability_probe"]
    .concat(fallbackAuthorization ? ["authorize_codex_fallback"] : [], expected);
  if (canonicalJson(loaded.map((entry) => entry.request.step)) !== canonicalJson(exactOrder)
      || loaded.some((entry, index) => index > 0
        && Date.parse(loaded[index - 1].ack.completedAt) >= Date.parse(entry.request.issuedAt))) {
    fail("control_operation_order_invalid", "control",
      "control operations must be one exact serial request/provider/ack sequence", {
        actual: loaded.map((entry) => entry.request.step), expected: exactOrder,
      });
  }
  const inputDigests = loaded.map((entry) => canonicalJson(entry.providerReceipt.inputEvidence));
  const domEventRefs = loaded.filter((entry) => entry.providerReceipt.inputEvidence.eventRef)
    .map((entry) => canonicalJson(entry.providerReceipt.inputEvidence.eventRef));
  if (new Set(loaded.map((entry) => entry.request.requestId)).size !== loaded.length
      || new Set(loaded.map((entry) => entry.requestArtifact && entry.requestArtifact.sha256
        || entry.ack.requestSha256)).size !== loaded.length
      || new Set(loaded.map((entry) => entry.ack.capture.artifact.toLowerCase())).size !== loaded.length
      || new Set(loaded.map((entry) => entry.ack.providerReceipt.artifact.toLowerCase())).size !== loaded.length
      || new Set(loaded.map((entry) => entry.providerReceipt.providerOperationId)).size !== loaded.length
      || new Set(loaded.map((entry) => entry.captureSha256)).size !== loaded.length
      || new Set(inputDigests).size !== inputDigests.length
      || new Set(domEventRefs).size !== domEventRefs.length) {
    fail("control_capture_reused", "control",
      "each control request needs unique provider/capture evidence, and journey steps need distinct image bytes");
  }
  expected.forEach((step) => {
    const entry = requireOne(business.filter((candidate) => candidate.request.step === step),
      "business_control_count_invalid", "control", "required business control is absent or duplicated", { step });
    const expectedClass = ["safe_exit", "exit_confirm"].includes(step) ? "lifecycle" : "business";
    if (entry.request.actionClass !== expectedClass
        || entry.ack.result !== "completed" || entry.ack.transport !== selectedTransport
        || canonicalJson(entry.request.allowedTransports) !== canonicalJson([selectedTransport])) {
      fail("business_control_transport_mismatch", "control", "business control did not use the selected input transport", { step });
    }
  });
  const unexpected = business.filter((entry) => !expected.includes(entry.request.step));
  if (unexpected.length) {
    fail("unexpected_business_control", "control", "unexpected business control step is present", {
      steps: unexpected.map((entry) => entry.request.step),
    });
  }
  return {
    selectedTransport,
    capability: { requestId: capability.request.requestId, result: capability.ack.result,
      providerOperationId: capability.providerReceipt.providerOperationId },
    fallbackAuthorization: fallbackAuthorization
      ? { requestId: fallbackAuthorization.request.requestId,
        reason: capability.providerReceipt.details.reasonCode,
        providerOperationId: fallbackAuthorization.providerReceipt.providerOperationId }
      : null,
    businessSteps: expected,
    loaded,
  };
}

module.exports = {
  RESULTS,
  TRANSPORTS,
  expectedBusinessSteps,
  loadControl,
  verifyControls,
};
