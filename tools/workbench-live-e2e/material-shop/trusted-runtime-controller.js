"use strict";

const crypto = require("crypto");

const EXACT_SLOT = "cf7_agent_a5_material_shop_run";
const TARGET_KINDS = Object.freeze({
  launcher: "launcher",
  webOverlay: "web_overlay",
  nativeHud: "native_hud",
});
const PIXEL_FORMAT = "bgra8_premultiplied";
const OPAQUE_ID_RE = /^[A-Za-z0-9_-]{22,128}$/;
const SHA256_RE = /^[A-Fa-f0-9]{64}$/;
const INPUT_KINDS = new Set([TARGET_KINDS.webOverlay, TARGET_KINDS.nativeHud]);
const BOUNDED_VISIBLE_WAIT_KINDS = new Set([
  TARGET_KINDS.launcher,
  TARGET_KINDS.webOverlay,
]);
const TARGET_VISIBLE_WAIT_MS = 30_000;
const TARGET_VISIBLE_POLL_MS = 100;
const WEB_OVERLAY_CAPTURE_RETRY_DELAYS_MS = Object.freeze([750, 1250, 2000]);
const INPUT_NOT_QUIESCENT_RETRY_DELAYS_MS = Object.freeze([100, 200, 400]);
const STALE_FOCUS_RETRY_DELAYS_MS = Object.freeze([100, 200, 400]);
// The first request includes immutable bundle verification, PowerShell
// wrapper startup, Guardian construction, and A5 credential gating. Keep
// ordinary RPC/write actions at 30s; only initial session.status receives a
// bounded startup budget.
const INITIAL_STATUS_TIMEOUT_MS = 90_000;

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function fail(code, message, details) {
  const error = new Error(message);
  error.code = code;
  if (details !== undefined) error.details = details;
  throw error;
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function cloneJson(value) {
  if (value === undefined) return undefined;
  return JSON.parse(JSON.stringify(value));
}

function opaqueId() {
  return crypto.randomBytes(18).toString("base64url");
}

function assertOpaque(value, label) {
  if (!OPAQUE_ID_RE.test(String(value || ""))) {
    fail("trusted_runtime_opaque_id_invalid", label + " is not an opaque protocol ID");
  }
  return value;
}

function assertPositiveSafeInteger(value, label) {
  if (!Number.isSafeInteger(value) || value < 1) {
    fail("trusted_runtime_generation_invalid", label + " must be a positive safe integer");
  }
  return value;
}

function exactStringSet(actual, expected, label) {
  if (!Array.isArray(actual)
      || actual.length !== expected.length
      || [...actual].sort().some((value, index) => value !== [...expected].sort()[index])) {
    fail("trusted_runtime_scope_invalid", label + " differs from the exact requested scope", {
      actual, expected,
    });
  }
}

function publicError(error) {
  return {
    name: error && error.name || "Error",
    code: error && error.code || null,
    message: error && error.message || String(error),
  };
}

function requiresActionLookup(error) {
  const data = error && error.details && error.details.rpcError
    && error.details.rpcError.data;
  return error && error.code === "trusted_runner_rpc_error"
    && isObject(data)
    && data.reasonCode === "reconcile_required"
    && ["domain_authoritative", "visual_ambiguous", "manual_required"]
      .includes(data.reconcileKind)
    && data.retryable === false;
}

function isRetryableWebOverlayCaptureUnavailable(error) {
  const data = error && error.details && error.details.rpcError
    && error.details.rpcError.data;
  return error && error.code === "trusted_runner_rpc_error"
    && isObject(data)
    && data.reasonCode === "capture_unavailable"
    && data.retryable === true
    && data.reconcileKind === "none";
}

function isRetryableInputNotQuiescent(error) {
  const data = error && error.details && error.details.rpcError
    && error.details.rpcError.data;
  return error && error.code === "trusted_runner_rpc_error"
    && isObject(data)
    && data.reasonCode === "input_not_quiescent"
    && data.retryable === true
    && data.reconcileKind === "none";
}

function isRetryableStaleFocus(error) {
  const data = error && error.details && error.details.rpcError
    && error.details.rpcError.data;
  return error && error.code === "trusted_runner_rpc_error"
    && isObject(data)
    && data.reasonCode === "stale_focus"
    && data.retryable === true
    && data.reconcileKind === "none";
}

function actionRetryDelays(error) {
  if (isRetryableInputNotQuiescent(error)) {
    return INPUT_NOT_QUIESCENT_RETRY_DELAYS_MS;
  }
  if (isRetryableStaleFocus(error)) return STALE_FOCUS_RETRY_DELAYS_MS;
  return null;
}

function assertPreparation(preparation) {
  if (!isObject(preparation)
      || typeof preparation.resourcesRoot !== "string"
      || !isObject(preparation.slots)
      || preparation.slots.targetSlot !== EXACT_SLOT) {
    fail("trusted_runtime_preparation_invalid",
      "trusted Runtime controller requires the materialized A5 preparation and exact target slot");
  }
  return preparation;
}

function assertStatus(status) {
  if (!isObject(status)
      || status.projectRunning !== true
      || status.qualificationState !== "verified") {
    fail("trusted_runtime_session_unavailable",
      "trusted Runtime does not report one verified running project session");
  }
  assertOpaque(status.lifecycleRef, "session lifecycleRef");
  return status;
}

function optionalGenerationCopy(target, source, sourceName, targetName) {
  if (source[sourceName] !== undefined && source[sourceName] !== null) {
    target[targetName] = assertPositiveSafeInteger(source[sourceName], sourceName);
  }
}

function actionBindings(observation, frame) {
  const value = {
    observationGrantId: assertOpaque(observation.observationGrantId,
      "observation observationGrantId"),
    observationId: assertOpaque(observation.observationId, "observation observationId"),
    expectedLifecycleGeneration: assertPositiveSafeInteger(
      observation.lifecycleGeneration, "observation lifecycleGeneration"),
    targetId: assertOpaque(observation.targetId, "observation targetId"),
    expectedSurfaceEpoch: assertPositiveSafeInteger(
      observation.surfaceEpoch, "observation surfaceEpoch"),
    expectedCoordinateSpaceVersion: assertPositiveSafeInteger(
      observation.coordinateSpaceVersion, "observation coordinateSpaceVersion"),
    expectedFocusEpoch: assertPositiveSafeInteger(observation.focusEpoch,
      "observation focusEpoch"),
    expectedModalEpoch: assertPositiveSafeInteger(observation.modalEpoch,
      "observation modalEpoch"),
    frameId: assertOpaque(frame.frameId, "frame frameId"),
  };
  const hasAttemptId = observation.attemptId !== undefined
    && observation.attemptId !== null;
  const hasAttemptGeneration = observation.attemptGeneration !== undefined
    && observation.attemptGeneration !== null;
  if (hasAttemptId !== hasAttemptGeneration) {
    fail("trusted_runtime_attempt_binding_invalid",
      "observation attempt ID and generation must be present together");
  }
  if (hasAttemptId) {
    value.expectedAttemptId = assertOpaque(observation.attemptId,
      "observation attemptId");
    value.expectedAttemptGeneration = assertPositiveSafeInteger(
      observation.attemptGeneration, "observation attemptGeneration");
  }
  if (observation.panelInstanceId !== undefined
      && observation.panelInstanceId !== null) {
    value.expectedPanelInstanceId = assertOpaque(observation.panelInstanceId,
      "observation panelInstanceId");
  }
  optionalGenerationCopy(value, observation, "semanticGeneration",
    "expectedSemanticGeneration");
  optionalGenerationCopy(value, observation, "documentGeneration",
    "expectedDocumentGeneration");
  return value;
}

class TrustedRuntimeController {
  constructor(preparation, runner, options) {
    this.preparation = preparation;
    this.runner = runner;
    this.options = options || {};
    this.status = null;
    this.ledger = [];
    this.finished = false;
  }

  async initialize() {
    this.status = assertStatus(await this._call(
      "session.status", {}, false, INITIAL_STATUS_TIMEOUT_MS));
    return this;
  }

  getLedger() {
    return cloneJson(this.ledger);
  }

  getRpcTranscript() {
    return typeof this.runner.getTranscript === "function"
      ? this.runner.getTranscript() : [];
  }

  async _call(method, params, writeAuthority, timeoutMs) {
    if (this.finished) {
      fail("trusted_runtime_controller_finished", "trusted Runtime controller is already finished");
    }
    const entry = {
      ordinal: this.ledger.length,
      request: {
        method,
        params: cloneJson(params),
        writeAuthority: writeAuthority === true,
        timeoutMs: timeoutMs || null,
      },
      result: null,
      error: null,
    };
    this.ledger.push(entry);
    try {
      const callOptions = {};
      if (writeAuthority === true) callOptions.writeAuthority = true;
      if (timeoutMs !== undefined) callOptions.timeoutMs = timeoutMs;
      const result = await this.runner.call(method, params, callOptions);
      entry.result = cloneJson(result);
      return result;
    } catch (error) {
      entry.error = publicError(error);
      throw error;
    }
  }

  async _readContent(frame) {
    const expectedLength = frame.width * frame.height * 4;
    if (!Number.isSafeInteger(expectedLength) || expectedLength < 4) {
      fail("trusted_runtime_pixel_dimensions_invalid",
        "frame dimensions do not define a bounded BGRA object");
    }
    const request = {
      handle: assertOpaque(frame.opaqueContentHandle, "frame opaqueContentHandle"),
      totalLength: expectedLength,
      contentHash: frame.contentHash,
    };
    const entry = {
      ordinal: this.ledger.length,
      request: {
        method: "content.read",
        params: cloneJson(request),
        writeAuthority: false,
        timeoutMs: null,
      },
      result: null,
      error: null,
    };
    this.ledger.push(entry);
    try {
      const bytes = await this.runner.readContent(request.handle, {
        totalLength: request.totalLength,
        contentHash: request.contentHash,
      });
      if (!Buffer.isBuffer(bytes) || bytes.length !== expectedLength) {
        fail("trusted_runtime_pixel_length_mismatch",
          "captured content is not the exact width*height*4 BGRA object", {
            expectedLength, actualLength: Buffer.isBuffer(bytes) ? bytes.length : null,
          });
      }
      const actualHash = crypto.createHash("sha256").update(bytes).digest("hex");
      if (!SHA256_RE.test(String(frame.contentHash || ""))
          || actualHash !== String(frame.contentHash).toLowerCase()) {
        fail("trusted_runtime_pixel_hash_mismatch",
          "captured BGRA content does not match the frame contentHash");
      }
      entry.result = { returnedBytes: bytes.length, contentHash: actualHash };
      return bytes;
    } catch (error) {
      entry.error = publicError(error);
      throw error;
    }
  }

  async _issueGrant(kind) {
    if (!Object.values(TARGET_KINDS).includes(kind)) {
      fail("trusted_runtime_target_kind_invalid", "target kind is outside the narrow controller scope");
    }
    const grant = await this._call("observation.grant.issue", {
      lifecycleRef: this.status.lifecycleRef,
      targetKinds: [kind],
      dataScopes: ["window_metadata", "pixels"],
      requestedTtlMs: 60000,
      allowEphemeralKeyframes: false,
      allowPersistence: false,
      allowExport: false,
    }, false);
    if (!isObject(grant) || !isObject(grant.sessionScope)
        || grant.state !== "active" || grant.allowEphemeralKeyframes !== false
        || grant.allowPersistence !== false || grant.allowExport !== false) {
      fail("trusted_runtime_grant_invalid", "observation grant is not an active non-exporting grant");
    }
    assertOpaque(grant.observationGrantId, "grant observationGrantId");
    assertOpaque(grant.sessionScope.sessionId, "grant sessionId");
    assertPositiveSafeInteger(grant.sessionScope.lifecycleGeneration,
      "grant lifecycleGeneration");
    if (grant.sessionScope.crossAttempt !== false
        || !Array.isArray(grant.targetScope) || grant.targetScope.length < 1
        || grant.targetScope.some((targetId) => !OPAQUE_ID_RE.test(String(targetId || "")))) {
      fail("trusted_runtime_grant_scope_invalid",
        "observation grant does not bind a non-empty exact current-attempt target scope");
    }
    exactStringSet(grant.dataScope, ["window_metadata", "pixels"], "grant dataScope");
    return grant;
  }

  async _selectTarget(kind) {
    const grant = await this._issueGrant(kind);
    const targetSet = new Set(grant.targetScope);
    const deadline = Date.now() + TARGET_VISIBLE_WAIT_MS;
    for (;;) {
      const listed = await this._call("window.list", {
        sessionId: grant.sessionScope.sessionId,
        observationGrantId: grant.observationGrantId,
        dataScope: "window_metadata",
      }, false);
      if (!isObject(listed)
          || listed.sessionId !== grant.sessionScope.sessionId
          || listed.lifecycleGeneration !== grant.sessionScope.lifecycleGeneration
          || !Array.isArray(listed.surfaces)) {
        fail("trusted_runtime_window_list_invalid",
          "window.list is detached from the exact grant lifecycle");
      }
      const matches = listed.surfaces.filter((surface) => isObject(surface)
        && surface.kind === kind && targetSet.has(surface.targetId));
      if (matches.length !== 1) {
        fail("trusted_runtime_target_not_unique",
          "grant and window.list do not select exactly one target of the requested kind", {
            kind, matches: matches.length,
          });
      }
      const surface = matches[0];
      const wgcAvailable = Array.isArray(surface.observationModes)
        && surface.observationModes.includes("window_graphics_capture");
      if (INPUT_KINDS.has(kind)
          && (!Array.isArray(surface.inputModes)
            || !surface.inputModes.includes("send_input_guarded"))) {
        fail("trusted_runtime_target_not_input_capable",
          "selected input target lacks guarded Runtime input authority");
      }
      if (surface.visible === true && wgcAvailable) return { kind, grant, surface };
      if (!BOUNDED_VISIBLE_WAIT_KINDS.has(kind) || Date.now() >= deadline) {
        fail("trusted_runtime_target_not_observable",
          "selected target is not a visible WGC production surface");
      }
      await wait(TARGET_VISIBLE_POLL_MS);
    }
  }

  async capture(kind) {
    const selected = await this._selectTarget(kind);
    const captureRequest = {
      observationGrantId: selected.grant.observationGrantId,
      sessionId: selected.grant.sessionScope.sessionId,
      targetId: selected.surface.targetId,
      dataScope: "pixels",
      allowValidatedFlashKeyframeFallback: false,
    };
    let observation;
    for (let attempt = 0;; attempt += 1) {
      try {
        observation = await this._call("observation.capture", captureRequest, false);
        break;
      } catch (error) {
        if (kind !== TARGET_KINDS.webOverlay
            || !isRetryableWebOverlayCaptureUnavailable(error)
            || attempt >= WEB_OVERLAY_CAPTURE_RETRY_DELAYS_MS.length) {
          throw error;
        }
        await wait(WEB_OVERLAY_CAPTURE_RETRY_DELAYS_MS[attempt]);
      }
    }
    if (!isObject(observation)
        || observation.observationGrantId !== selected.grant.observationGrantId
        || observation.sessionId !== selected.grant.sessionScope.sessionId
        || observation.lifecycleGeneration !== selected.grant.sessionScope.lifecycleGeneration
        || observation.targetId !== selected.surface.targetId
        || !Array.isArray(observation.frames)) {
      fail("trusted_runtime_observation_invalid",
        "capture is detached from the exact grant, lifecycle, or target");
    }
    const frames = observation.frames.filter((frame) => isObject(frame)
      && frame.targetId === observation.targetId && frame.sourceLayer === kind);
    if (frames.length !== 1) {
      fail("trusted_runtime_frame_not_unique",
        "capture does not contain exactly one frame for the selected target");
    }
    const frame = frames[0];
    if (frame.observationId !== observation.observationId
        || frame.surfaceEpoch !== observation.surfaceEpoch
        || frame.coordinateSpaceVersion !== observation.coordinateSpaceVersion
        || frame.pixelFormat !== PIXEL_FORMAT
        || !Number.isSafeInteger(frame.width) || frame.width < 1
        || !Number.isSafeInteger(frame.height) || frame.height < 1) {
      fail("trusted_runtime_frame_invalid",
        "capture frame is detached or is not raw premultiplied BGRA");
    }
    const pixels = await this._readContent(frame);
    return { kind, grant: selected.grant, surface: selected.surface,
      observation, frame, binding: actionBindings(observation, frame),
      width: frame.width, height: frame.height, pixels };
  }

  async _lease(capture, method, kind) {
    const lease = await this._call("lease.acquire", {
      sessionId: capture.observation.sessionId,
      kind,
      capabilities: [method],
      targetScope: [capture.observation.targetId],
      requestedTtlMs: 30000,
      requestedActionLimit: 1,
    }, false);
    if (!isObject(lease) || lease.state !== "active" || lease.purpose !== kind
        || !isObject(lease.scope) || !isObject(lease.scope.session)) {
      fail("trusted_runtime_lease_invalid", "one-shot lease is not active or correctly typed");
    }
    assertOpaque(lease.leaseId, "lease leaseId");
    exactStringSet(lease.capabilities, [method], "lease capabilities");
    exactStringSet(lease.scope.operationScope, [method], "lease operationScope");
    exactStringSet(lease.scope.targetScope, [capture.observation.targetId],
      "lease targetScope");
    if (lease.scope.maximumActions !== 1
        || lease.scope.session.sessionId !== capture.observation.sessionId
        || lease.scope.session.lifecycleGeneration !== capture.observation.lifecycleGeneration
        || lease.scope.session.crossAttempt !== false) {
      fail("trusted_runtime_lease_scope_invalid",
        "lease does not exactly bind the fresh observation lifecycle and target");
    }
    const observationHasAttempt = capture.observation.attemptId != null;
    const leaseHasAttempt = lease.scope.session.attemptId != null;
    if (observationHasAttempt !== leaseHasAttempt
        || observationHasAttempt
          && (lease.scope.session.attemptId !== capture.observation.attemptId
            || lease.scope.session.attemptGeneration !== capture.observation.attemptGeneration)) {
      fail("trusted_runtime_lease_attempt_invalid",
        "lease attempt differs from the fresh observation attempt");
    }
    if (kind === "structured_action" && lease.renewAfter !== undefined) {
      fail("trusted_runtime_structured_lease_renewable",
        "structured-action one-shot lease must omit renewal");
    }
    return lease;
  }

  async _reconcileAction(action, initialError) {
    let result;
    try {
      result = await this._call("action.get", {
        sessionId: action.sessionId,
        actionId: action.actionId,
      }, false);
    } catch (error) {
      const failure = new Error("uncertain action could not be reconciled with action.get");
      failure.code = "trusted_runtime_action_reconcile_failed";
      failure.cause = initialError || error;
      failure.reconcileError = publicError(error);
      throw failure;
    }
    if (isObject(result) && result.terminal === true
        && result.actionId === action.actionId) {
      return result;
    }
    const failure = new Error("uncertain action lacks a terminal action.get receipt");
    failure.code = "trusted_runtime_action_unresolved";
    failure.cause = initialError;
    failure.reconciliation = cloneJson(result);
    throw failure;
  }

  async _perform(method, capture, leaseKind, argumentsValue, reason) {
    if (typeof reason !== "string" || reason.length < 1 || reason.length > 512) {
      fail("trusted_runtime_action_reason_invalid", "action reason must be non-empty and bounded");
    }
    const lease = await this._lease(capture, method, leaseKind);
    const action = Object.assign({
      actionId: opaqueId(),
      idempotencyKey: opaqueId(),
      deadlineMs: 30000,
      sessionId: capture.observation.sessionId,
      leaseId: lease.leaseId,
    }, actionBindings(capture.observation, capture.frame), {
      operation: method,
      arguments: argumentsValue,
      reason,
    });
    let receipt;
    let reconciled = false;
    let dispatchError = null;
    try {
      receipt = await this._call(method, action, true, 30000);
    } catch (error) {
      dispatchError = publicError(error);
      // Transport failures poison and close the JSONL child, so they cannot be
      // reconciled on this connection. Only an authoritative server response
      // that explicitly requires lookup keeps the session usable for action.get.
      if (!requiresActionLookup(error)) throw error;
      receipt = await this._reconcileAction(action, error);
      reconciled = true;
    }
    if (!isObject(receipt) || receipt.actionId !== action.actionId
        || receipt.terminal !== true) {
      fail("trusted_runtime_action_receipt_invalid",
        "action response is not the exact terminal receipt");
    }
    if (receipt.outcome === "unknown" && !reconciled) {
      receipt = await this._reconcileAction(action, null);
      reconciled = true;
    }
    return { action, receipt, reconciled, dispatchError, capture,
      lease, ledger: this.getLedger(), rpcTranscript: this.getRpcTranscript() };
  }

  async openMaterials(reason) {
    return this._withFreshActionCapture(TARGET_KINDS.launcher, (capture) =>
      this._perform("panel.open", capture, "structured_action", {
        panel: "materials",
      }, reason || "Open the allow-listed materials route"));
  }

  async _withFreshActionCapture(kind, operation) {
    for (let attempt = 0;; attempt += 1) {
      try {
        const capture = await this.capture(kind);
        return await operation(capture);
      } catch (error) {
        const delays = actionRetryDelays(error);
        if (!delays || attempt >= delays.length) {
          throw error;
        }
        await wait(delays[attempt]);
      }
    }
  }

  async click(options) {
    const settings = options || {};
    const kind = settings.targetKind || TARGET_KINDS.webOverlay;
    if (!INPUT_KINDS.has(kind)) {
      fail("trusted_runtime_input_kind_invalid",
        "guarded click is restricted to WebOverlay or NativeHud");
    }
    return this._withFreshActionCapture(kind, async (capture) => {
      const point = typeof settings.coordinateProvider === "function"
        ? settings.coordinateProvider(capture) : settings;
      const x = point && point.x;
      const y = point && point.y;
      if (!Number.isInteger(x) || !Number.isInteger(y)
          || x < 0 || y < 0 || x >= capture.frame.width || y >= capture.frame.height) {
        fail("trusted_runtime_click_coordinate_invalid",
          "click coordinates must be integer pixels inside the fresh observation frame");
      }
      return this._perform("input.click", capture, "gui_input", {
        coordinateSpace: "observation_px",
        x, y,
        button: "primary",
        clickCount: 1,
      }, settings.reason || "Activate the observed material workbench control");
    });
  }

  async pressKey(options) {
    const settings = options || {};
    const kind = settings.targetKind || TARGET_KINDS.webOverlay;
    if (!INPUT_KINDS.has(kind)) {
      fail("trusted_runtime_input_kind_invalid",
        "guarded key input is restricted to WebOverlay or NativeHud");
    }
    const key = settings.key;
    const modifiers = settings.modifiers || [];
    const repeat = settings.repeat === undefined ? 1 : settings.repeat;
    if (typeof key !== "string" || key.length < 1 || key.length > 64
        || !Array.isArray(modifiers) || new Set(modifiers).size !== modifiers.length
        || modifiers.some((value) => !["ctrl", "alt", "shift"].includes(value))
        || !Number.isInteger(repeat) || repeat < 1 || repeat > 16) {
      fail("trusted_runtime_key_invalid", "key, modifiers, or repeat is outside the exact input contract");
    }
    return this._withFreshActionCapture(kind, (capture) =>
      this._perform("input.press_key", capture, "gui_input", {
        key, modifiers: modifiers.slice(), repeat,
      }, settings.reason || "Use the observed material workbench keyboard control"));
  }

  async typeText(options) {
    const settings = options || {};
    const kind = settings.targetKind || TARGET_KINDS.webOverlay;
    if (!INPUT_KINDS.has(kind)) {
      fail("trusted_runtime_input_kind_invalid",
        "guarded text input is restricted to WebOverlay or NativeHud");
    }
    const text = settings.text;
    if (typeof text !== "string" || text.length < 1 || text.length > 32768) {
      fail("trusted_runtime_text_invalid",
        "text must be a non-empty string inside the exact input.type_text contract");
    }
    return this._withFreshActionCapture(kind, (capture) =>
      this._perform("input.type_text", capture, "gui_input", {
        text,
      }, settings.reason || "Type into the observed material workbench control"));
  }

  async finish() {
    if (this.finished) {
      fail("trusted_runtime_controller_finished", "trusted Runtime controller is already finished");
    }
    const finished = await this.runner.finish();
    this.finished = true;
    return Object.assign({}, finished, { ledger: this.getLedger() });
  }
}

async function start(preparation, options) {
  const exactPreparation = assertPreparation(preparation);
  const settings = options || {};
  const createRunner = settings.createRunner
    || require("./trusted-runner-jsonl").createTrustedRunner;
  if (typeof createRunner !== "function") {
    fail("trusted_runtime_runner_factory_invalid", "createTrustedRunner factory is required");
  }
  const runner = await Promise.resolve(createRunner(exactPreparation,
    settings.runnerOptions || {}));
  if (!runner || typeof runner.call !== "function"
      || typeof runner.readContent !== "function" || typeof runner.finish !== "function") {
    fail("trusted_runtime_runner_invalid", "trusted runner does not implement the frozen JSONL contract");
  }
  const controller = new TrustedRuntimeController(exactPreparation, runner, settings);
  try {
    return await controller.initialize();
  } catch (error) {
    if (typeof runner.abortBeforeAuthority === "function"
        && runner.uncertainWrite !== true) {
      try { await runner.abortBeforeAuthority(); }
      catch (abortError) { error.abortError = publicError(abortError); }
    }
    throw error;
  }
}

module.exports = {
  EXACT_SLOT,
  TARGET_KINDS,
  INITIAL_STATUS_TIMEOUT_MS,
  INPUT_NOT_QUIESCENT_RETRY_DELAYS_MS,
  STALE_FOCUS_RETRY_DELAYS_MS,
  WEB_OVERLAY_CAPTURE_RETRY_DELAYS_MS,
  TrustedRuntimeController,
  start,
};
