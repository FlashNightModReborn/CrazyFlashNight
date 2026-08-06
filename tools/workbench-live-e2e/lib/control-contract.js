"use strict";

const {
  canonicalJson,
  contractFail,
  isPlainObject,
  sha256Text,
  verifyOwnedCapture,
} = require("./evidence-artifact");

const API_VERSION = "FROZEN-v1";
const ID_RE = /^[A-Za-z0-9._~-]{1,160}$/;
const SHA256_RE = /^[A-Fa-f0-9]{64}$/;

function asSet(value) {
  return value instanceof Set ? value : new Set(value || []);
}

function validateControlRequest(request, options) {
  const settings = options || {};
  const transports = asSet(settings.allowedTransports);
  if (!isPlainObject(request) || request.schema !== settings.requestSchema
      || !ID_RE.test(String(request.requestId || "")) || !ID_RE.test(String(request.step || ""))
      || !Array.isArray(request.allowedTransports) || request.allowedTransports.length < 1
      || request.allowedTransports.some((entry) => !transports.has(entry))
      || typeof request.requiresCommitAuthorization !== "boolean"
      || typeof request.requiresCaptureSha256 !== "boolean"
      || !Number.isFinite(Date.parse(request.issuedAt))
      || !Number.isFinite(Date.parse(request.expiresAt))) {
    contractFail("control_request_invalid", "control", "control request envelope is malformed");
  }
  const ttlMs = Date.parse(request.expiresAt) - Date.parse(request.issuedAt);
  const maximumTtlMs = Number(settings.maximumTtlMs || 3600000);
  if (ttlMs < 1000 || ttlMs > maximumTtlMs) {
    contractFail("control_request_ttl_invalid", "control", "control request TTL is outside policy", { ttlMs });
  }
  if (request.requiresCommitAuthorization) {
    if (!isPlainObject(request.authorizationRef)
        || !ID_RE.test(String(request.authorizationRef.decisionId || ""))
        || !SHA256_RE.test(String(request.authorizationRef.decisionSha256 || ""))) {
      contractFail("control_authorization_ref_invalid", "control",
        "commit-authorized request lacks an exact decision reference");
    }
  } else if (request.authorizationRef != null) {
    contractFail("control_authorization_ref_unexpected", "control",
      "non-authorized request carries an authorization reference");
  }
  return request;
}

function validateControlAck(ack, request, options) {
  const settings = options || {};
  const results = asSet(settings.allowedResults);
  if (!isPlainObject(ack) || ack.schema !== settings.ackSchema
      || ack.requestId !== request.requestId
      || !request.allowedTransports.includes(ack.transport)
      || !results.has(ack.result)
      || !Number.isFinite(Date.parse(ack.completedAt))) {
    contractFail("control_ack_invalid", "control", "control acknowledgement envelope is malformed");
  }
  if (ack.captureSha256 != null && !SHA256_RE.test(String(ack.captureSha256))) {
    contractFail("control_ack_capture_invalid", "control", "capture digest is malformed");
  }
  if (ack.capture != null && (!isPlainObject(ack.capture)
      || typeof ack.capture.relativePath !== "string"
      || !SHA256_RE.test(String(ack.capture.sha256 || ""))
      || !Number.isInteger(ack.capture.bytes) || ack.capture.bytes < 1
      || ack.captureSha256 !== ack.capture.sha256)) {
    contractFail("control_ack_capture_invalid", "control", "capture envelope is malformed");
  }
  if (request.requiresCaptureSha256
      && (!isPlainObject(ack.capture) || ack.captureSha256 !== ack.capture.sha256)) {
    contractFail("control_ack_capture_required", "control", "control step requires staged capture bytes");
  }
  if (request.requiresCommitAuthorization) {
    if (ack.authorizationDecisionId !== request.authorizationRef.decisionId) {
      contractFail("control_authorization_ack_invalid", "control",
        "acknowledgement did not consume the referenced decision");
    }
  } else if (ack.authorizationDecisionId != null) {
    contractFail("control_authorization_ack_unexpected", "control",
      "non-authorized acknowledgement carries a decision id");
  }
  return ack;
}

function assertAckWithinTtl(request, ack) {
  const issued = Date.parse(request.issuedAt);
  const expires = Date.parse(request.expiresAt);
  const completed = Date.parse(ack.completedAt);
  if (completed < issued || completed > expires) {
    contractFail("control_ack_time_invalid", "control", "acknowledgement is outside the request TTL");
  }
  return true;
}

function verifyControlExchange(options) {
  const request = validateControlRequest(options.request, options);
  const ack = validateControlAck(options.ack, request, options);
  assertAckWithinTtl(request, ack);
  let capture = null;
  if (ack.capture != null) {
    capture = verifyOwnedCapture({
      root: options.root,
      runDir: options.runDir,
      ownedBaseRelative: options.ownedBaseRelative,
      capture: ack.capture,
      phase: "control_capture",
      maximumBytes: options.maximumCaptureBytes,
    });
  }
  return { request, ack, capture };
}

function assertExactControlSet(options) {
  const requests = Array.isArray(options.requests) ? options.requests : [];
  const acks = Array.isArray(options.acks) ? options.acks : [];
  const requiredSteps = Array.from(options.requiredSteps || []);
  if (requests.length !== requiredSteps.length || acks.length !== requiredSteps.length
      || new Set(requests.map((entry) => entry.requestId)).size !== requests.length
      || new Set(acks.map((entry) => entry.requestId)).size !== acks.length) {
    contractFail("control_set_count_invalid", "control",
      "control evidence must contain exactly the required one-shot exchanges");
  }
  const byStep = new Map();
  requiredSteps.forEach((step) => {
    const matching = requests.filter((entry) => entry.step === step);
    if (matching.length !== 1) {
      contractFail("control_step_request_invalid", "control", "required control step is missing/duplicated", { step });
    }
    const ackMatches = acks.filter((entry) => entry.requestId === matching[0].requestId);
    if (ackMatches.length !== 1) {
      contractFail("control_step_ack_invalid", "control", "control acknowledgement is missing/duplicated", { step });
    }
    const verified = verifyControlExchange(Object.assign({}, options, {
      request: matching[0],
      ack: ackMatches[0],
    }));
    byStep.set(step, verified);
  });
  return byStep;
}

function verifyCapabilityDecision(options) {
  const capability = options.capability;
  const trustedSources = asSet(options.trustedSources);
  if (!isPlainObject(capability) || typeof capability.available !== "boolean"
      || !trustedSources.has(capability.source)
      || !isPlainObject(capability.artifact)
      || !SHA256_RE.test(String(capability.artifactSha256 || ""))
      || sha256Text(canonicalJson(capability.artifact)) !== capability.artifactSha256) {
    contractFail("capability_evidence_untrusted", "control",
      "capability decision must bind a trusted non-operator artifact");
  }
  if (capability.available) {
    if (options.selectedTransport !== options.preferredTransport) {
      contractFail("capability_preference_violated", "control",
        "available preferred transport was not selected");
    }
  } else if (options.selectedTransport !== options.fallbackTransport
      || options.fallbackAllowed !== true) {
    contractFail("capability_fallback_invalid", "control",
      "unavailable preferred transport lacks an authorized fallback");
  }
  return { available: capability.available, source: capability.source,
    artifactSha256: capability.artifactSha256, selectedTransport: options.selectedTransport };
}

function verifyOneShotAuthorization(options) {
  const decision = options.decision;
  const digest = String(options.decisionSha256 || "");
  if (!isPlainObject(decision) || decision.schema !== options.decisionSchema
      || !ID_RE.test(String(decision.decisionId || "")) || decision.oneShot !== true
      || !asSet(options.trustedSources).has(decision.source)
      || !SHA256_RE.test(digest) || sha256Text(canonicalJson(decision)) !== digest) {
    contractFail("authorization_decision_invalid", "control",
      "one-shot authorization decision artifact is missing, untrusted, or tampered");
  }
  const requests = Array.isArray(options.requests) ? options.requests : [];
  const acks = Array.isArray(options.acks) ? options.acks : [];
  const consumers = requests.filter((request) => request.requiresCommitAuthorization === true
    && request.authorizationRef && request.authorizationRef.decisionId === decision.decisionId
    && request.authorizationRef.decisionSha256 === digest);
  if (consumers.length !== 1 || (options.expectedStep && consumers[0].step !== options.expectedStep)) {
    contractFail("authorization_decision_consumption_invalid", "control",
      "authorization decision must be referenced by one exact control step");
  }
  const ack = acks.filter((entry) => entry.requestId === consumers[0].requestId
    && entry.authorizationDecisionId === decision.decisionId);
  if (ack.length !== 1) {
    contractFail("authorization_decision_ack_invalid", "control",
      "authorization decision was not consumed by one exact acknowledgement");
  }
  return { decisionId: decision.decisionId, decisionSha256: digest,
    requestId: consumers[0].requestId, step: consumers[0].step };
}

module.exports = {
  API_VERSION,
  ID_RE,
  SHA256_RE,
  assertAckWithinTtl,
  assertExactControlSet,
  validateControlAck,
  validateControlRequest,
  verifyCapabilityDecision,
  verifyControlExchange,
  verifyOneShotAuthorization,
};
