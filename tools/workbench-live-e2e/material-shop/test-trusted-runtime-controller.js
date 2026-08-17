"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const test = require("node:test");
const Controller = require("./trusted-runtime-controller");

function id(label) {
  return String(label).replace(/[^A-Za-z0-9_-]/g, "_").padEnd(22, "X");
}

function preparation() {
  return {
    resourcesRoot: "C:\\materialized\\a5\\resources",
    slots: { targetSlot: Controller.EXACT_SLOT },
  };
}

class FakeRunner {
  constructor(options) {
    this.options = options || {};
    this.calls = [];
    this.reads = [];
    this.finishCalls = 0;
    this.captureOrdinal = 0;
    this.captureAttempts = new Map();
    this.windowListCounts = new Map();
    this.grants = new Map();
    this.actions = new Map();
    this.inputLeaseAttempts = 0;
    this.panelOpenAttempts = 0;
    this._uncertainWrite = false;
  }

  get uncertainWrite() {
    return this._uncertainWrite;
  }

  async call(method, params, options) {
    this.calls.push({ method, params: JSON.parse(JSON.stringify(params)),
      options: Object.assign({}, options) });
    if (method === "session.status") {
      return {
        projectRunning: true,
        qualificationState: "verified",
        lifecycleRef: id("lifecycle"),
      };
    }
    if (method === "observation.grant.issue") {
      const kind = params.targetKinds[0];
      const grantId = id("grant_" + kind + "_" + this.calls.length);
      const targetId = id("target_" + kind);
      this.grants.set(grantId, { kind, targetId });
      return {
        observationGrantId: grantId,
        ownerClientId: id("owner"),
        securityPrincipalId: id("principal"),
        sessionScope: {
          sessionId: id("session"), lifecycleGeneration: 7,
          attemptId: id("attempt"), attemptGeneration: 11, crossAttempt: false,
        },
        targetScope: [targetId],
        dataScope: ["pixels", "window_metadata"],
        issuedMonotonic: 1,
        expiresMonotonic: 60001,
        allowEphemeralKeyframes: false,
        allowPersistence: false,
        allowExport: false,
        state: "active",
      };
    }
    if (method === "window.list") {
      const binding = this.grants.get(params.observationGrantId);
      const listCount = (this.windowListCounts.get(binding.kind) || 0) + 1;
      this.windowListCounts.set(binding.kind, listCount);
      const surface = {
        targetId: binding.targetId,
        kind: binding.kind,
        surfaceEpoch: 13,
        boundsPhysical: { x: 0, y: 0, width: 800, height: 600 },
        dpi: 96,
        zIndex: 1,
        visible: !((binding.kind === "launcher"
          && listCount <= (this.options.hiddenLauncherLists || 0))
          || (binding.kind === "web_overlay"
            && listCount <= (this.options.hiddenWebOverlayLists || 0))),
        coordinateSpaceVersion: 17,
        focusEpoch: 19,
        modalEpoch: 23,
        observationModes: ["window_graphics_capture"],
        inputModes: binding.kind === "launcher" ? [] : ["send_input_guarded"],
      };
      if (binding.kind === "web_overlay") surface.documentGeneration = 29;
      return {
        sessionId: id("session"),
        lifecycleGeneration: 7,
        surfaces: this.options.duplicateTarget ? [surface, Object.assign({}, surface)] : [surface],
      };
    }
    if (method === "observation.capture") {
      const binding = this.grants.get(params.observationGrantId);
      const captureAttempt = (this.captureAttempts.get(binding.kind) || 0) + 1;
      this.captureAttempts.set(binding.kind, captureAttempt);
      if (binding.kind === "web_overlay"
          && captureAttempt <= (this.options.webOverlayCaptureFailures || 0)) {
        const error = new Error("capture unavailable");
        error.code = "trusted_runner_rpc_error";
        error.details = { rpcError: { code: -32000, message: "capture unavailable", data:
          Object.assign({
            reasonCode: "capture_unavailable",
            reconcileKind: "none",
            retryable: true,
          }, this.options.captureErrorData || {}) } };
        throw error;
      }
      this.captureOrdinal += 1;
      const observationId = id("observation_" + this.captureOrdinal);
      const content = Buffer.from([
        0, 1, 2, 255, 3, 4, 5, 255,
        6, 7, 8, 255, 9, 10, 11, 255,
      ]);
      const contentHash = crypto.createHash("sha256").update(content).digest("hex");
      const frame = {
        frameId: id("frame_" + this.captureOrdinal),
        observationId,
        targetId: binding.targetId,
        surfaceEpoch: 13,
        sourceLayer: binding.kind,
        zIndex: 1,
        capturedAtMonotonic: 31 + this.captureOrdinal,
        coordinateSpaceId: id("coordinates"),
        coordinateSpaceVersion: 17,
        captureRectPhysical: { x: 0, y: 0, width: 2, height: 2 },
        clientRectPhysical: { x: 0, y: 0, width: 2, height: 2 },
        contentRectPhysical: { x: 0, y: 0, width: 2, height: 2 },
        frameToTargetContentTransform: { m11: 1, m12: 0, m21: 0, m22: 1, dx: 0, dy: 0 },
        width: 2,
        height: 2,
        dpi: 96,
        pixelFormat: "bgra8_premultiplied",
        contentHash,
        opaqueContentHandle: id("content_" + this.captureOrdinal),
      };
      this.reads.push({ handle: frame.opaqueContentHandle, content,
        corrupt: this.options.corruptContent === true });
      const observation = {
        observationId,
        observationGrantId: params.observationGrantId,
        sessionId: id("session"),
        lifecycleGeneration: 7,
        capturedUtc: "2026-08-12T00:00:00.000Z",
        capturedAtMonotonic: 31 + this.captureOrdinal,
        attemptId: id("attempt"),
        attemptGeneration: 11,
        targetId: binding.targetId,
        surfaceEpoch: 13,
        coordinateSpaceVersion: 17,
        focusEpoch: 19,
        modalEpoch: 23,
        visible: true,
        minimized: false,
        active: true,
        blockingModalKind: "none",
        frames: [frame],
      };
      if (binding.kind === "web_overlay") {
        observation.panelInstanceId = id("panel_instance");
        observation.documentGeneration = 29;
      }
      return observation;
    }
    if (method === "lease.acquire") {
      if (params.kind === "gui_input") {
        this.inputLeaseAttempts += 1;
        if (this.inputLeaseAttempts
            <= (this.options.inputNotQuiescentFailures || 0)) {
          const error = new Error("input is not quiescent");
          error.code = "trusted_runner_rpc_error";
          error.details = { rpcError: { code: -32000,
            message: "input is not quiescent", data: Object.assign({
              reasonCode: "input_not_quiescent",
              reconcileKind: "none",
              retryable: true,
            }, this.options.inputNotQuiescentErrorData || {}) } };
          throw error;
        }
      }
      return {
        leaseId: id("lease_" + this.calls.length),
        ownerClientId: id("owner"),
        securityPrincipalId: id("principal"),
        sessionMode: "unattended_test",
        purpose: params.kind,
        scope: {
          session: {
            sessionId: id("session"), lifecycleGeneration: 7,
            attemptId: id("attempt"), attemptGeneration: 11, crossAttempt: false,
          },
          targetScope: params.targetScope.slice(),
          operationScope: params.capabilities.slice(),
          maximumActions: 1,
        },
        capabilities: params.capabilities.slice(),
        issuedMonotonic: 40,
        expiresMonotonic: 30040,
        humanOverridePolicy: "always_preempt",
        state: "active",
      };
    }
    if (["panel.open", "input.click", "input.press_key", "input.type_text"].includes(method)) {
      if (method === "panel.open") {
        this.panelOpenAttempts += 1;
        if (this.panelOpenAttempts <= (this.options.panelOpenStaleFocusFailures || 0)) {
          const error = new Error("focus changed after the Launcher observation");
          error.code = "trusted_runner_rpc_error";
          error.details = { rpcError: { code: -32000,
            message: "focus changed after the Launcher observation", data: Object.assign({
              reasonCode: "stale_focus",
              reconcileKind: "none",
              retryable: true,
            }, this.options.staleFocusErrorData || {}) } };
          throw error;
        }
      }
      this.actions.set(params.actionId, params);
      if (method === "input.click" && this.options.authoritativeClickError) {
        const error = new Error("authoritative click rejection");
        error.code = "trusted_runner_rpc_error";
        error.details = { rpcError: { data: {
          reasonCode: "stale_observation",
          reconcileKind: "none",
          retryable: false,
        } } };
        throw error;
      }
      if (method === "input.click" && this.options.reconcileClickError) {
        const error = new Error("click response requires lookup");
        error.code = "trusted_runner_rpc_error";
        error.details = { rpcError: { data: {
          reasonCode: "reconcile_required",
          reconcileKind: "manual_required",
          retryable: false,
        } } };
        throw error;
      }
      if (method === "input.press_key" && this.options.uncertainPressKey) {
        this._uncertainWrite = true;
        const error = new Error("simulated response loss after possible dispatch");
        error.code = "trusted_runner_response_unknown";
        throw error;
      }
      return this.receipt(params.actionId);
    }
    if (method === "action.get") {
      assert.ok(this.actions.has(params.actionId));
      return this.receipt(params.actionId);
    }
    throw new Error("unexpected fake method " + method);
  }

  receipt(actionId) {
    return {
      actionId,
      auditSequence: 101,
      terminal: true,
      outcome: "input_dispatched",
      evidenceKind: "broker_dispatch",
      reasonCode: "input_dispatched",
      reconcileKind: "none",
      retryable: false,
      actualTargetId: this.actions.get(actionId).targetId,
      focusVerified: true,
      beforeObservationId: this.actions.get(actionId).observationId,
      leaseState: "consumed",
    };
  }

  async readContent(handle, options) {
    const found = this.reads.find((entry) => entry.handle === handle);
    assert.ok(found);
    assert.equal(options.totalLength, found.content.length);
    assert.equal(options.contentHash,
      crypto.createHash("sha256").update(found.content).digest("hex"));
    if (!found.corrupt) return Buffer.from(found.content);
    const value = Buffer.from(found.content);
    value[0] ^= 0xff;
    return value;
  }

  async finish() {
    this.finishCalls += 1;
    return {
      completion: { schema: "cf7.trusted_runner.completion.v1", exitCode: 0 },
      transcript: this.calls.slice(),
      transcriptSha256: "a".repeat(64),
    };
  }

  getTranscript() {
    return this.calls.map((entry) => JSON.parse(JSON.stringify(entry)));
  }

  async abortBeforeAuthority() {
    return { completion: null, transcript: this.getTranscript(),
      transcriptSha256: "b".repeat(64), exitCode: 0 };
  }
}

test("uses fresh exact Runtime observations and one-shot leases for typed actions", async () => {
  const runner = new FakeRunner();
  const controller = await Controller.start(preparation(), {
    createRunner: () => runner,
  });

  assert.deepEqual(runner.calls.map((entry) => entry.method), ["session.status"]);
  assert.deepEqual(runner.calls[0].options, {
    timeoutMs: Controller.INITIAL_STATUS_TIMEOUT_MS,
  });
  assert.equal(Controller.INITIAL_STATUS_TIMEOUT_MS, 90000);

  const opened = await controller.openMaterials();
  assert.equal(opened.action.operation, "panel.open");
  assert.deepEqual(opened.action.arguments, { panel: "materials" });
  assert.equal(opened.action.expectedAttemptId, id("attempt"));
  assert.equal(opened.action.expectedAttemptGeneration, 11);
  assert.equal(Object.hasOwn(opened.action, "expectedPanelInstanceId"), false);

  const clicked = await controller.click({ x: 1, y: 0, reason: "Click exact observed row" });
  assert.deepEqual(clicked.action.arguments, {
    coordinateSpace: "observation_px", x: 1, y: 0,
    button: "primary", clickCount: 1,
  });
  assert.equal(clicked.action.expectedPanelInstanceId, id("panel_instance"));
  assert.equal(clicked.action.expectedDocumentGeneration, 29);
  assert.notEqual(clicked.action.observationId, opened.action.observationId);

  const pressed = await controller.pressKey({
    key: "Escape", modifiers: [], repeat: 1, reason: "Close exact observed panel",
  });
  assert.equal(pressed.reconciled, false);
  assert.equal(pressed.dispatchError, null);
  assert.notEqual(pressed.action.observationId, clicked.action.observationId);
  assert.ok(!pressed.rpcTranscript.some((entry) => entry.method === "action.get"));

  const typed = await controller.typeText({
    text: "铜", reason: "Type exact observed search query",
  });
  assert.deepEqual(typed.action.arguments, { text: "铜" });
  assert.notEqual(typed.action.observationId, pressed.action.observationId);

  const nativeCapture = await controller.capture(Controller.TARGET_KINDS.nativeHud);
  assert.equal(nativeCapture.kind, "native_hud");
  assert.equal(nativeCapture.pixels.length, 16);
  assert.equal(nativeCapture.width, 2);
  assert.equal(nativeCapture.height, 2);
  assert.equal(nativeCapture.binding.frameId, nativeCapture.frame.frameId);

  const writeCalls = runner.calls.filter((entry) => entry.options.writeAuthority === true);
  assert.deepEqual(writeCalls.map((entry) => entry.method),
    ["panel.open", "input.click", "input.press_key", "input.type_text"]);
  assert.ok(runner.calls.filter((entry) => entry.method === "lease.acquire")
    .every((entry) => entry.params.requestedActionLimit === 1));
  assert.deepEqual(runner.calls.filter((entry) => entry.method === "observation.grant.issue")
    .map((entry) => entry.params.targetKinds[0]),
  ["launcher", "web_overlay", "web_overlay", "web_overlay", "native_hud"]);
  assert.equal(runner.calls.filter((entry) => entry.method === "action.get").length, 0);
  assert.equal(runner.calls.filter((entry) => entry.method === "input.press_key").length, 1);

  const finished = await controller.finish();
  assert.equal(finished.completion.exitCode, 0);
  assert.equal(finished.transcriptSha256, "a".repeat(64));
  assert.deepEqual(finished.ledger, controller.getLedger());
  assert.equal(runner.finishCalls, 1);
});

test("typeText locks exact typed arguments and rejects near-invalid text before authority", async () => {
  const runner = new FakeRunner();
  const controller = await Controller.start(preparation(), {
    createRunner: () => runner,
  });
  const result = await controller.typeText({
    targetKind: Controller.TARGET_KINDS.webOverlay,
    text: "绷带",
    reason: "Type exact material name",
  });
  assert.equal(result.action.operation, "input.type_text");
  assert.deepEqual(result.action.arguments, { text: "绷带" });
  const writesBeforeInvalid = runner.calls
    .filter((entry) => entry.options.writeAuthority === true).length;
  await assert.rejects(controller.typeText({ text: "" }), {
    code: "trusted_runtime_text_invalid",
  });
  assert.equal(runner.calls
    .filter((entry) => entry.options.writeAuthority === true).length,
  writesBeforeInvalid);
});

test("authoritative action rejection propagates without synthetic action.get", async () => {
  const runner = new FakeRunner({ authoritativeClickError: true });
  const controller = await Controller.start(preparation(), {
    createRunner: () => runner,
  });
  await assert.rejects(controller.click({ x: 1, y: 0, reason: "Rejected click" }), {
    code: "trusted_runner_rpc_error",
  });
  assert.equal(runner.calls.filter((entry) => entry.method === "action.get").length, 0);
});

test("explicit reconcile-required action error uses exact action.get", async () => {
  const runner = new FakeRunner({ reconcileClickError: true });
  const controller = await Controller.start(preparation(), {
    createRunner: () => runner,
  });
  const result = await controller.click({ x: 1, y: 0, reason: "Lookup click" });
  assert.equal(result.reconciled, true);
  assert.equal(result.receipt.outcome, "input_dispatched");
  assert.equal(runner.calls.filter((entry) => entry.method === "action.get").length, 1);
});

test("transport-uncertain action fails closed without querying a poisoned connection", async () => {
  const runner = new FakeRunner({ uncertainPressKey: true });
  const controller = await Controller.start(preparation(), {
    createRunner: () => runner,
  });
  await assert.rejects(controller.pressKey({
    key: "Escape", modifiers: [], repeat: 1, reason: "Ambiguous transport",
  }), { code: "trusted_runner_response_unknown" });
  assert.equal(runner.uncertainWrite, true);
  assert.equal(runner.calls.filter((entry) => entry.method === "action.get").length, 0);
});

test("fails closed when exact target selection is ambiguous", async () => {
  const runner = new FakeRunner({ duplicateTarget: true });
  const controller = await Controller.start(preparation(), {
    createRunner: () => runner,
  });
  await assert.rejects(controller.openMaterials(), {
    code: "trusted_runtime_target_not_unique",
  });
  assert.equal(runner.calls.some((entry) => entry.method === "lease.acquire"), false);
  assert.equal(runner.calls.some((entry) => entry.options.writeAuthority === true), false);
});

test("waits for the exact WGC Launcher surface to cross the bounded reveal gate", async () => {
  const runner = new FakeRunner({ hiddenLauncherLists: 1 });
  const controller = await Controller.start(preparation(), {
    createRunner: () => runner,
  });
  const opened = await controller.openMaterials();
  assert.equal(opened.action.operation, "panel.open");
  assert.equal(runner.calls.filter((entry) => entry.method === "window.list").length, 2);
  assert.equal(runner.calls.filter((entry) => entry.method === "observation.capture").length, 1);
  assert.equal(runner.calls.filter((entry) => entry.method === "panel.open").length, 1);
});

test("waits for the exact WGC WebOverlay after one materials dispatch", async () => {
  const runner = new FakeRunner({ hiddenWebOverlayLists: 1 });
  const controller = await Controller.start(preparation(), {
    createRunner: () => runner,
  });
  await controller.openMaterials();
  const capture = await controller.capture(Controller.TARGET_KINDS.webOverlay);
  assert.equal(capture.kind, "web_overlay");
  assert.equal(runner.calls.filter((entry) => entry.method === "panel.open").length, 1);
  assert.equal(runner.calls.filter((entry) => entry.method === "window.list"
    && runner.grants.get(entry.params.observationGrantId).kind === "web_overlay").length, 2);
});

test("retries only exact transient WebOverlay capture unavailability on one binding", async () => {
  const runner = new FakeRunner({ webOverlayCaptureFailures: 3 });
  const controller = await Controller.start(preparation(), {
    createRunner: () => runner,
  });
  const capture = await controller.capture(Controller.TARGET_KINDS.webOverlay);
  assert.equal(capture.kind, "web_overlay");
  const calls = runner.calls.filter((entry) => entry.method === "observation.capture");
  assert.equal(calls.length, 4);
  assert.ok(calls.every((entry) => assert.deepEqual(entry.params, calls[0].params) === undefined));
  assert.equal(runner.calls.filter((entry) => entry.method === "observation.grant.issue").length, 1);
  assert.equal(runner.calls.filter((entry) => entry.method === "window.list").length, 1);
});

test("retries exact input-not-quiescent with a fresh WGC observation", async () => {
  const runner = new FakeRunner({ inputNotQuiescentFailures: 2 });
  const controller = await Controller.start(preparation(), {
    createRunner: () => runner,
  });
  const result = await controller.pressKey({
    key: "ArrowRight", modifiers: [], repeat: 1,
    reason: "Move after transient tooltip activity",
  });
  assert.equal(result.action.operation, "input.press_key");
  assert.equal(runner.calls.filter((entry) => entry.method === "lease.acquire").length, 3);
  assert.equal(runner.calls.filter((entry) => entry.method === "observation.capture").length, 3);
  assert.equal(runner.calls.filter((entry) => entry.method === "input.press_key").length, 1);
  assert.equal(result.action.observationId, id("observation_3"));
  assert.deepEqual(Controller.INPUT_NOT_QUIESCENT_RETRY_DELAYS_MS, [100, 200, 400]);
});

test("retries exact rejected stale-focus panel.open with a fresh Launcher observation", async () => {
  const runner = new FakeRunner({ panelOpenStaleFocusFailures: 2 });
  const controller = await Controller.start(preparation(), {
    createRunner: () => runner,
  });
  const result = await controller.openMaterials("Open after transient focus churn");
  assert.equal(result.action.operation, "panel.open");
  assert.equal(runner.calls.filter((entry) => entry.method === "panel.open").length, 3);
  assert.equal(runner.calls.filter((entry) => entry.method === "lease.acquire").length, 3);
  assert.equal(runner.calls.filter((entry) => entry.method === "observation.capture").length, 3);
  assert.equal(result.action.observationId, id("observation_3"));
  assert.deepEqual(Controller.STALE_FOCUS_RETRY_DELAYS_MS, [100, 200, 400]);
});

test("does not retry near stale-focus panel.open errors", async (t) => {
  for (const [name, staleFocusErrorData] of [
    ["reason", { reasonCode: "stale_observation" }],
    ["retryable", { retryable: false }],
    ["reconcile", { reconcileKind: "visual_ambiguous" }],
  ]) {
    await t.test(name, async () => {
      const runner = new FakeRunner({
        panelOpenStaleFocusFailures: 1,
        staleFocusErrorData,
      });
      const controller = await Controller.start(preparation(), {
        createRunner: () => runner,
      });
      await assert.rejects(controller.openMaterials("Reject near stale-focus tuple"), {
        code: "trusted_runner_rpc_error",
      });
      assert.equal(runner.calls.filter((entry) => entry.method === "panel.open").length, 1);
      assert.equal(runner.calls.filter((entry) => entry.method === "lease.acquire").length, 1);
      assert.equal(runner.calls.filter((entry) => entry.method === "observation.capture").length, 1);
    });
  }
});

test("bounds exact stale-focus retries at four total panel.open attempts", async () => {
  const runner = new FakeRunner({ panelOpenStaleFocusFailures: 4 });
  const controller = await Controller.start(preparation(), {
    createRunner: () => runner,
  });
  await assert.rejects(controller.openMaterials("Bound persistent stale focus"), {
    code: "trusted_runner_rpc_error",
  });
  assert.equal(runner.calls.filter((entry) => entry.method === "panel.open").length, 4);
  assert.equal(runner.calls.filter((entry) => entry.method === "observation.capture").length, 4);
});

test("does not retry near input-not-quiescent errors", async (t) => {
  for (const [name, inputNotQuiescentErrorData] of [
    ["reason", { reasonCode: "stale_observation" }],
    ["retryable", { retryable: false }],
    ["reconcile", { reconcileKind: "visual_ambiguous" }],
  ]) {
    await t.test(name, async () => {
      const runner = new FakeRunner({
        inputNotQuiescentFailures: 1,
        inputNotQuiescentErrorData,
      });
      const controller = await Controller.start(preparation(), {
        createRunner: () => runner,
      });
      await assert.rejects(controller.pressKey({
        key: "ArrowRight", modifiers: [], repeat: 1,
        reason: "Reject near transient tuple",
      }), { code: "trusted_runner_rpc_error" });
      assert.equal(runner.calls.filter((entry) => entry.method === "lease.acquire").length, 1);
      assert.equal(runner.calls.filter((entry) => entry.method === "observation.capture").length, 1);
      assert.equal(runner.calls.filter((entry) => entry.method === "input.press_key").length, 0);
    });
  }
});

test("bounds WebOverlay capture-unavailable retries at four total attempts", async () => {
  const runner = new FakeRunner({ webOverlayCaptureFailures: 4 });
  const controller = await Controller.start(preparation(), {
    createRunner: () => runner,
  });
  await assert.rejects(controller.capture(Controller.TARGET_KINDS.webOverlay), {
    code: "trusted_runner_rpc_error",
  });
  assert.equal(runner.calls.filter((entry) => entry.method === "observation.capture").length, 4);
});

test("does not retry capture errors outside the exact transient tuple", async (t) => {
  for (const [name, captureErrorData] of [
    ["reason", { reasonCode: "stale_observation" }],
    ["retryable", { retryable: false }],
    ["reconcile", { reconcileKind: "visual_ambiguous" }],
  ]) {
    await t.test(name, async () => {
      const runner = new FakeRunner({ webOverlayCaptureFailures: 1, captureErrorData });
      const controller = await Controller.start(preparation(), {
        createRunner: () => runner,
      });
      await assert.rejects(controller.capture(Controller.TARGET_KINDS.webOverlay), {
        code: "trusted_runner_rpc_error",
      });
      assert.equal(runner.calls.filter((entry) => entry.method === "observation.capture").length, 1);
    });
  }
});

test("rejects content whose bytes do not match the frame hash", async () => {
  const runner = new FakeRunner({ corruptContent: true });
  const controller = await Controller.start(preparation(), {
    createRunner: () => runner,
  });
  await assert.rejects(controller.capture(Controller.TARGET_KINDS.launcher), {
    code: "trusted_runtime_pixel_hash_mismatch",
  });
  assert.equal(runner.calls.some((entry) => entry.method === "lease.acquire"), false);
});
