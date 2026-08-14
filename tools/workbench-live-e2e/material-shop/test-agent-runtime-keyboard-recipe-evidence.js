#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const Evidence = require("../lib/evidence-artifact");
const Verifier = require("./journey-verifier");
const Protocol = require("./protocol");

const STEP_METHODS = [
  ["open_materials", ["panel.open", "observation.capture", "content.read"], true],
  ["materials_visual_current_window", ["observation.capture", "content.read"], true],
  ["materials_keyboard", ["input.press_key", "observation.capture", "content.read"], true],
  ["recipe_jump_intent", ["input.press_key"], false],
  ["materials_recipe_jump", ["observation.capture", "content.read"], true],
  ["recipe_escape_close", ["input.press_key", "observation.capture", "content.read"], true],
  ["recipe_reopen_materials", ["panel.open", "observation.capture", "content.read"], true],
  ["ordinary_close", ["input.click", "observation.capture", "content.read"], true],
  ["reopen_materials", ["panel.open", "observation.capture", "content.read"], true],
];

function sha(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex");
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function fixture() {
  let actionOrdinal = 0;
  let captureOrdinal = 0;
  const ledger = [];
  const captures = [];
  const plan = { schema: Protocol.AGENT_RUNTIME_PLAN_SCHEMA,
    authorization: { decisionId: "a5-keyboard-test" },
    steps: STEP_METHODS.map(([id, methods, requiresCapture], ordinal) => ({
      id, ordinal, driverMethods: methods, requiresCapture,
    })) };
  const controls = plan.steps.map((step) => {
    const control = { stepId: step.id, ordinal: step.ordinal,
      transport: Protocol.AGENT_RUNTIME_TRANSPORT,
      methods: step.driverMethods.slice(), actionIntents: [], actionReceipts: [],
      captureRefs: [], completedAt: "2026-08-13T12:00:00.000Z" };
    if (step.requiresCapture) {
      captureOrdinal += 1;
      const captureSha256 = sha("capture:" + step.id);
      const observationId = "observation-" + captureOrdinal;
      const grantId = "grant-" + captureOrdinal;
      const targetId = "target-" + captureOrdinal;
      const frameId = "frame-" + captureOrdinal;
      const handle = "content-" + captureOrdinal;
      const contentHash = sha("pixels:" + step.id);
      captures.push({ sessionLabel: "first", stepId: step.id, captureSha256,
        observationId, grantId, targetId, frameId, frameContentHash: contentHash,
        width: 2, height: 2, source: { pixelFormat: "bgra8_premultiplied",
          bytes: 16, sha256: contentHash } });
      control.captureRefs.push(captureSha256);
    }
    return control;
  });
  const byStep = new Map(controls.map((control) => [control.stepId, control]));
  function action(stepId, role, method, argumentsValue) {
    actionOrdinal += 1;
    const actionId = "action-" + actionOrdinal;
    const receipt = { actionId, terminal: true, outcome: "input_dispatched",
      evidenceKind: "broker_dispatch", reasonCode: "none", reconcileKind: "none",
      retryable: false };
    const intent = { role, method, arguments: clone(argumentsValue), actionId,
      receiptSha256: Evidence.sha256Text(Evidence.canonicalJson(receipt)) };
    const control = byStep.get(stepId);
    control.actionIntents.push(intent);
    control.actionReceipts.push(receipt);
    ledger.push({ request: { method, params: { actionId, operation: method,
      arguments: clone(argumentsValue) } }, result: clone(receipt), error: null });
  }
  function capture(stepId) {
    const receipt = captures.find((entry) => entry.stepId === stepId);
    const handle = "content-" + (captures.indexOf(receipt) + 1);
    ledger.push({ request: { method: "observation.capture", params: {
      observationGrantId: receipt.grantId, sessionId: "session-first",
      targetId: receipt.targetId, dataScope: "pixels",
      allowValidatedFlashKeyframeFallback: false } },
      result: { observationId: receipt.observationId,
        observationGrantId: receipt.grantId, targetId: receipt.targetId,
        sessionId: "session-first",
        visible: true, minimized: false, panelInstanceId: "panel-" + receipt.stepId,
        documentGeneration: 1,
        frames: [{ observationId: receipt.observationId, frameId: receipt.frameId,
          targetId: receipt.targetId, contentHash: receipt.frameContentHash,
          opaqueContentHandle: handle, width: receipt.width, height: receipt.height,
          sourceLayer: "web_overlay", pixelFormat: "bgra8_premultiplied" }] },
      error: null });
    ledger.push({ request: { method: "content.read", params: { handle,
      totalLength: receipt.source.bytes, contentHash: receipt.frameContentHash } },
    result: { returnedBytes: receipt.source.bytes, contentHash: receipt.frameContentHash },
    error: null });
  }
  action("open_materials", "open_materials", "panel.open", { panel: "materials" });
  capture("open_materials");
  capture("materials_visual_current_window");
  Protocol.AGENT_RUNTIME_RECIPE_JUMP.keyboardActions.forEach((entry) => action(
    entry.stepId, entry.role, "input.press_key",
    { key: entry.key, modifiers: entry.modifiers, repeat: entry.repeat }));
  capture("materials_keyboard");
  capture("materials_recipe_jump");
  action("recipe_reopen_materials", "open_materials", "panel.open", { panel: "materials" });
  capture("recipe_reopen_materials");
  capture("ordinary_close");
  action("ordinary_close", "npcshop_close", "input.click", {
    coordinateSpace: "observation_px", x: 10, y: 10, button: "primary", clickCount: 1,
  });
  action("reopen_materials", "open_materials", "panel.open", { panel: "materials" });
  capture("reopen_materials");
  return { raw: { controls, sessions: [{ label: "first", ledger },
    { label: "restart", ledger: [] }] }, plan, captures };
}

test("first stable v2 material snapshot safely focuses the canonical tree root", () => {
  const source = fs.readFileSync(path.join(__dirname, "..", "..", "..", "launcher",
    "web", "modules", "crafting-materials.js"), "utf8");
  assert.match(source, /firstSnapshot && state\.protocolVersion === 2 && visible\.length/);
  assert.match(source, /active === catalogRoot\.ownerDocument\.body/);
  assert.match(source, /active === catalogRoot\.ownerDocument\.documentElement/);
  assert.match(source, /filterNavigator\.focusPath\(\[\]\);/);
});

test("exact key-only recipe route binds intents, receipts, ledger RPCs, and captures", () => {
  const value = fixture();
  const verified = Verifier.verifyAgentRuntimeControls(
    value.raw, value.plan, value.captures);
  assert.equal(verified.keyboard.count,
    Protocol.AGENT_RUNTIME_RECIPE_JUMP.keyboardActions.length);
  assert.match(verified.keyboard.sha256, /^[a-f0-9]{64}$/);
  assert.equal(verified.summary.keyboardActionIntentCount, 16);
  assert.equal(verified.byStep.get("materials_recipe_jump").captureRefs.length, 1);
});

test("a visible recipe capture cannot substitute for a missing key receipt", () => {
  const value = fixture();
  const control = value.raw.controls.find((entry) => entry.stepId === "recipe_jump_intent");
  control.actionIntents.pop();
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    value.raw, value.plan, value.captures), {
    code: "material_shop_agent_runtime_action_intent_invalid",
  });
});

test("key argument or trusted-ledger drift fails mechanical recipe proof", () => {
  const argumentDrift = fixture();
  const intent = argumentDrift.raw.controls.find(
    (entry) => entry.stepId === "recipe_jump_intent").actionIntents[0];
  intent.arguments.repeat = 2;
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    argumentDrift.raw, argumentDrift.plan, argumentDrift.captures), {
    code: "material_shop_agent_runtime_action_intent_invalid",
  });

  const ledgerDrift = fixture();
  const actionId = ledgerDrift.raw.controls.find(
    (entry) => entry.stepId === "recipe_escape_close").actionIntents[0].actionId;
  const entry = ledgerDrift.raw.sessions[0].ledger.find(
    (candidate) => candidate.request.params.actionId === actionId);
  entry.request.params.arguments.key = "enter";
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    ledgerDrift.raw, ledgerDrift.plan, ledgerDrift.captures), {
    code: "material_shop_agent_runtime_action_intent_invalid",
  });

  const reopenDrift = fixture();
  const reopenIntent = reopenDrift.raw.controls.find(
    (entry) => entry.stepId === "recipe_reopen_materials").actionIntents[0];
  reopenIntent.arguments.panel = "crafting";
  const reopenLedger = reopenDrift.raw.sessions[0].ledger.find(
    (candidate) => candidate.request.params.actionId === reopenIntent.actionId);
  reopenLedger.request.params.arguments.panel = "crafting";
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    reopenDrift.raw, reopenDrift.plan, reopenDrift.captures), {
    code: "material_shop_agent_runtime_action_intent_invalid",
  });
});

test("cross-step receipt reuse or reordered intents cannot counterfeit the key sequence", () => {
  const reused = fixture();
  const materialControl = reused.raw.controls.find(
    (entry) => entry.stepId === "materials_keyboard");
  const recipeControl = reused.raw.controls.find(
    (entry) => entry.stepId === "recipe_jump_intent");
  const sourceIndex = materialControl.actionIntents.findIndex(
    (intent) => intent.role === "materials_tab_to_search");
  recipeControl.actionIntents[0].actionId = materialControl.actionIntents[sourceIndex].actionId;
  recipeControl.actionIntents[0].receiptSha256 =
    materialControl.actionIntents[sourceIndex].receiptSha256;
  recipeControl.actionReceipts[0] = clone(materialControl.actionReceipts[sourceIndex]);
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    reused.raw, reused.plan, reused.captures), {
    code: "material_shop_agent_runtime_action_sequence_invalid",
  });

  const reordered = fixture();
  const reorderedControl = reordered.raw.controls.find(
    (entry) => entry.stepId === "materials_keyboard");
  [reorderedControl.actionIntents[0], reorderedControl.actionIntents[1]] =
    [reorderedControl.actionIntents[1], reorderedControl.actionIntents[0]];
  [reorderedControl.actionReceipts[0], reorderedControl.actionReceipts[1]] =
    [reorderedControl.actionReceipts[1], reorderedControl.actionReceipts[0]];
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    reordered.raw, reordered.plan, reordered.captures), {
    code: "material_shop_agent_runtime_action_sequence_invalid",
  });
});

test("close outcome requires a post-open visible WebOverlay capture and exact content read", () => {
  const beforeOpen = fixture();
  const ledger = beforeOpen.raw.sessions[0].ledger;
  const openIndex = ledger.findIndex((entry) => entry.request.method === "panel.open"
    && entry.request.params.actionId === beforeOpen.raw.controls.find(
      (control) => control.stepId === "recipe_reopen_materials").actionIntents[0].actionId);
  const observationIndex = ledger.findIndex((entry) => entry.request.method === "observation.capture"
    && entry.result.observationId === beforeOpen.captures.find(
      (capture) => capture.stepId === "recipe_reopen_materials").observationId);
  const pair = ledger.splice(observationIndex, 2);
  ledger.splice(openIndex - 1, 0, ...pair);
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    beforeOpen.raw, beforeOpen.plan, beforeOpen.captures), {
    code: "material_shop_agent_runtime_close_outcome_invalid",
  });

  const foreignSurface = fixture();
  const successorCapture = foreignSurface.captures.find(
    (capture) => capture.stepId === "recipe_reopen_materials");
  const observation = foreignSurface.raw.sessions[0].ledger.find(
    (entry) => entry.request.method === "observation.capture"
      && entry.result.observationId === successorCapture.observationId);
  observation.result.frames[0].sourceLayer = "launcher";
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    foreignSurface.raw, foreignSurface.plan, foreignSurface.captures), {
    code: "material_shop_agent_runtime_close_outcome_invalid",
  });

  const foreignRequest = fixture();
  const requestCapture = foreignRequest.captures.find(
    (capture) => capture.stepId === "recipe_reopen_materials");
  const requestObservation = foreignRequest.raw.sessions[0].ledger.find(
    (entry) => entry.request.method === "observation.capture"
      && entry.result.observationId === requestCapture.observationId);
  requestObservation.request.params.observationGrantId = "foreign-grant";
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    foreignRequest.raw, foreignRequest.plan, foreignRequest.captures), {
    code: "material_shop_agent_runtime_close_outcome_invalid",
  });

  const contentDrift = fixture();
  const driftCapture = contentDrift.captures.find(
    (capture) => capture.stepId === "recipe_reopen_materials");
  const driftRead = contentDrift.raw.sessions[0].ledger.find((entry) =>
    entry.request.method === "content.read"
      && entry.request.params.contentHash === driftCapture.frameContentHash);
  driftRead.result.returnedBytes += 4;
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    contentDrift.raw, contentDrift.plan, contentDrift.captures), {
    code: "material_shop_agent_runtime_close_outcome_invalid",
  });
});

test("close outcome normalizes SHA-256 hex case but rejects digest drift", () => {
  const caseVariant = fixture();
  const successorCapture = caseVariant.captures.find(
    (capture) => capture.stepId === "recipe_reopen_materials");
  const observation = caseVariant.raw.sessions[0].ledger.find(
    (entry) => entry.request.method === "observation.capture"
      && entry.result.observationId === successorCapture.observationId);
  const read = caseVariant.raw.sessions[0].ledger.find(
    (entry) => entry.request.method === "content.read"
      && entry.request.params.contentHash === successorCapture.frameContentHash);
  observation.result.frames[0].contentHash =
    observation.result.frames[0].contentHash.toUpperCase();
  read.request.params.contentHash = read.request.params.contentHash.toUpperCase();
  read.result.contentHash = read.result.contentHash.toUpperCase();
  assert.doesNotThrow(() => Verifier.verifyAgentRuntimeControls(
    caseVariant.raw, caseVariant.plan, caseVariant.captures));

  const digestDrift = fixture();
  const driftCapture = digestDrift.captures.find(
    (capture) => capture.stepId === "recipe_reopen_materials");
  const driftObservation = digestDrift.raw.sessions[0].ledger.find(
    (entry) => entry.request.method === "observation.capture"
      && entry.result.observationId === driftCapture.observationId);
  const original = driftObservation.result.frames[0].contentHash;
  driftObservation.result.frames[0].contentHash =
    (original[0] === "0" ? "1" : "0") + original.slice(1);
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    digestDrift.raw, digestDrift.plan, digestDrift.captures), {
    code: "material_shop_agent_runtime_close_outcome_invalid",
  });
});

test("close and successor must remain adjacent in the first session with its own capture", () => {
  const sessionDrift = fixture();
  sessionDrift.captures.find(
    (capture) => capture.stepId === "recipe_reopen_materials").sessionLabel = "restart";
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    sessionDrift.raw, sessionDrift.plan, sessionDrift.captures), {
    code: "material_shop_agent_runtime_close_outcome_invalid",
  });

  const actionGap = fixture();
  const firstLedger = actionGap.raw.sessions[0].ledger;
  const successor = actionGap.raw.controls.find(
    (control) => control.stepId === "recipe_reopen_materials").actionIntents[0];
  const successorIndex = firstLedger.findIndex((entry) => entry.request.method === "panel.open"
    && entry.request.params.actionId === successor.actionId);
  firstLedger.splice(successorIndex, 0, {
    request: { method: "input.press_key", params: { actionId: "foreign-action",
      operation: "input.press_key", arguments: { key: "tab", modifiers: [], repeat: 1 } } },
    result: { actionId: "foreign-action", terminal: true, outcome: "input_dispatched",
      evidenceKind: "broker_dispatch", reasonCode: "none", reconcileKind: "none",
      retryable: false }, error: null,
  });
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    actionGap.raw, actionGap.plan, actionGap.captures), {
    code: "material_shop_agent_runtime_action_sequence_invalid",
  });

  const clickDrift = fixture();
  const closeIntent = clickDrift.raw.controls.find(
    (control) => control.stepId === "ordinary_close").actionIntents[0];
  closeIntent.arguments.button = "secondary";
  const closeLedger = clickDrift.raw.sessions[0].ledger.find((entry) =>
    entry.request.params && entry.request.params.actionId === closeIntent.actionId);
  closeLedger.request.params.arguments.button = "secondary";
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    clickDrift.raw, clickDrift.plan, clickDrift.captures), {
    code: "material_shop_agent_runtime_close_outcome_invalid",
  });

  const crossSession = fixture();
  const reopenIntent = crossSession.raw.controls.find(
    (control) => control.stepId === "reopen_materials").actionIntents[0];
  const reopenIndex = crossSession.raw.sessions[0].ledger.findIndex((entry) =>
    entry.request.params && entry.request.params.actionId === reopenIntent.actionId);
  crossSession.raw.sessions[1].ledger.push(
    crossSession.raw.sessions[0].ledger.splice(reopenIndex, 1)[0]);
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    crossSession.raw, crossSession.plan, crossSession.captures), {
    code: "material_shop_agent_runtime_close_outcome_invalid",
  });

  const emptyHandle = fixture();
  const handleCapture = emptyHandle.captures.find(
    (capture) => capture.stepId === "reopen_materials");
  const handleObservation = emptyHandle.raw.sessions[0].ledger.find(
    (entry) => entry.request.method === "observation.capture"
      && entry.result.observationId === handleCapture.observationId);
  const priorHandle = handleObservation.result.frames[0].opaqueContentHandle;
  handleObservation.result.frames[0].opaqueContentHandle = "";
  const handleRead = emptyHandle.raw.sessions[0].ledger.find((entry) =>
    entry.request.method === "content.read" && entry.request.params.handle === priorHandle);
  handleRead.request.params.handle = "";
  assert.throws(() => Verifier.verifyAgentRuntimeControls(
    emptyHandle.raw, emptyHandle.plan, emptyHandle.captures), {
    code: "material_shop_agent_runtime_close_outcome_invalid",
  });
});
