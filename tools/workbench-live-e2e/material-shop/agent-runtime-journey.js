"use strict";

const Evidence = require("../lib/evidence-artifact");
const Protocol = require("./protocol");

const DESIGN_WIDTH = 1024;
const DESIGN_HEIGHT = 576;
const WEB_OVERLAY = "web_overlay";
const PURCHASE_TEXT = "食用油";

const FROZEN_STEPS = Object.freeze([
  ["open_materials", ["panel.open", "observation.capture", "content.read"]],
  ["materials_visual_current_window", ["observation.capture", "content.read"]],
  ["materials_keyboard", ["input.press_key", "observation.capture", "content.read"]],
  ["recipe_jump_intent", ["input.press_key"]],
  ["materials_recipe_jump", ["observation.capture", "content.read"]],
  ["recipe_escape_close", ["input.press_key", "observation.capture", "content.read"]],
  ["recipe_reopen_materials", ["panel.open", "observation.capture", "content.read"]],
  ["materials_multi_variant", ["observation.capture", "content.read"]],
  ["materials_portraits", ["observation.capture", "content.read"]],
  ["ordinary_forward", ["input.click", "input.press_key", "input.type_text"]],
  ["ordinary_close", ["input.click", "observation.capture", "content.read"]],
  ["reopen_materials", ["panel.open", "observation.capture", "content.read"]],
  ["unlocked_forward", ["input.click", "input.type_text"]],
  ["unlocked_exact_focus", ["observation.capture", "content.read"]],
  ["unlocked_intent_qty1", ["input.press_key", "input.click",
    "observation.capture", "content.read"]],
  ["unlocked_settlement", ["observation.capture", "content.read"]],
  ["unlocked_commit", ["input.click"]],
  ["unlocked_return", ["input.click", "observation.capture", "content.read"]],
  ["trusted_runner_persistence_shutdown", ["trusted_runner_finish"]],
  ["restart_candidate", ["restart_candidate"]],
  ["restart_open_materials", ["panel.open", "observation.capture", "content.read"]],
  ["restart_readback", ["input.click", "input.type_text",
    "observation.capture", "content.read"]],
  ["restart_close", ["input.click"]],
  ["trusted_runner_final_shutdown", ["trusted_runner_finish"]],
]);

function fail(code, message, details) {
  const error = new Error(message);
  error.code = code;
  if (details !== undefined) error.details = details;
  throw error;
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function clone(value) {
  if (value === undefined) return undefined;
  return JSON.parse(JSON.stringify(value));
}

function exactJson(left, right) {
  return Evidence.canonicalJson(left) === Evidence.canonicalJson(right);
}

function frameSize(capture) {
  const width = capture && Number.isSafeInteger(capture.width)
    ? capture.width : capture && capture.frame && capture.frame.width;
  const height = capture && Number.isSafeInteger(capture.height)
    ? capture.height : capture && capture.frame && capture.frame.height;
  if (!Number.isSafeInteger(width) || width < 1
      || !Number.isSafeInteger(height) || height < 1) {
    fail("material_shop_agent_coordinate_frame_invalid",
      "coordinate calculation requires one bounded fresh WGC frame");
  }
  return { width, height };
}

function designPoint(capture, x, y) {
  const size = frameSize(capture);
  if (!Number.isFinite(x) || x < 0 || x >= DESIGN_WIDTH
      || !Number.isFinite(y) || y < 0 || y >= DESIGN_HEIGHT) {
    fail("material_shop_agent_design_point_invalid",
      "design coordinates must be inside the 1024x576 material workbench canvas");
  }
  const scale = Math.min(size.width / DESIGN_WIDTH, size.height / DESIGN_HEIGHT);
  return {
    x: Math.min(size.width - 1, Math.max(0, Math.round(x * scale))),
    y: Math.min(size.height - 1, Math.max(0, Math.round(y * scale))),
  };
}

function assertPlan(plan) {
  if (!isObject(plan) || plan.schema !== Protocol.AGENT_RUNTIME_PLAN_SCHEMA
      || !Array.isArray(plan.steps) || plan.steps.length !== FROZEN_STEPS.length
      || !isObject(plan.authorization)) {
    fail("material_shop_agent_journey_plan_invalid",
      "Agent Runtime journey requires the frozen 24-step A5 plan");
  }
  plan.steps.forEach((step, index) => {
    const expected = FROZEN_STEPS[index];
    if (!isObject(step) || step.ordinal !== index || step.id !== expected[0]
        || step.transportClass !== ([18, 19, 23].includes(index)
          ? "trusted_runner_lifecycle" : "agent_runtime_visible_input")
        || !exactJson(step.allowedTransports, [Protocol.AGENT_RUNTIME_TRANSPORT])
        || !exactJson(step.driverMethods, expected[1])) {
      fail("material_shop_agent_journey_plan_invalid",
        "Agent Runtime journey step differs from the frozen A5 route", {
          index, expectedStepId: expected[0],
        });
    }
  });
  return plan;
}

function assertController(controller, label) {
  if (!controller || !isObject(controller.status)
      || typeof controller.openMaterials !== "function"
      || typeof controller.capture !== "function"
      || typeof controller.click !== "function"
      || typeof controller.pressKey !== "function"
      || typeof controller.typeText !== "function"
      || typeof controller.finish !== "function") {
    fail("material_shop_agent_controller_invalid",
      "controller factory did not return the narrow trusted Runtime controller", { label });
  }
  return controller;
}

function assertPoint(point, capture, stepId, role) {
  const size = frameSize(capture);
  if (!isObject(point) || !Number.isInteger(point.x) || !Number.isInteger(point.y)
      || point.x < 0 || point.x >= size.width || point.y < 0 || point.y >= size.height) {
    fail("material_shop_agent_coordinate_invalid",
      "coordinate provider returned a point outside its fresh WGC frame", {
        stepId, role, width: size.width, height: size.height,
      });
  }
  return { x: point.x, y: point.y };
}

function assertActionResult(result, stepId, role) {
  const action = result && result.action;
  const receipt = result && result.receipt;
  if (!isObject(action) || typeof action.actionId !== "string"
      || action.actionId.length < 1 || action.operation == null || !isObject(action.arguments)
      || !isObject(receipt) || receipt.actionId !== action.actionId || receipt.terminal !== true
      || receipt.outcome !== "input_dispatched"
      || receipt.evidenceKind !== "broker_dispatch"
      || receipt.reasonCode !== "none"
      || receipt.reconcileKind !== "none"
      || receipt.retryable !== false) {
    fail("material_shop_agent_action_receipt_invalid",
      "visible action lacks one exact dispatched Runtime receipt", {
        stepId,
        role,
        actionId: receipt && receipt.actionId,
        terminal: receipt && receipt.terminal,
        outcome: receipt && receipt.outcome,
        evidenceKind: receipt && receipt.evidenceKind,
        reasonCode: receipt && receipt.reasonCode,
        reconcileKind: receipt && receipt.reconcileKind,
        retryable: receipt && receipt.retryable,
      });
  }
  return { action: clone(action), receipt: clone(receipt) };
}

function buildSession(label, controller, finished) {
  if (!finished || finished.exitCode !== 0 || !isObject(finished.completion)
      || !Array.isArray(finished.transcript) || !Array.isArray(finished.ledger)) {
    fail("material_shop_agent_session_finish_invalid",
      "trusted runner did not return one clean completion", { label });
  }
  const transcript = clone(finished.transcript);
  const ledger = clone(finished.ledger);
  return {
    label,
    status: clone(controller.status),
    completion: clone(finished.completion),
    transcript,
    transcriptSha256: Evidence.sha256Text(Evidence.canonicalJson(transcript)),
    ledger,
    ledgerSha256: Evidence.sha256Text(Evidence.canonicalJson(ledger)),
    cleanExit: true,
  };
}

function shutdownProjection(session) {
  return {
    sessionLabel: session.label,
    completionSha256: Evidence.sha256Text(Evidence.canonicalJson(session.completion)),
    cleanExit: session.cleanExit,
  };
}

async function execute(options) {
  const settings = options || {};
  const plan = assertPlan(settings.plan);
  if (!isObject(settings.preparation) || typeof settings.runDir !== "string"
      || settings.runDir.length < 1 || typeof settings.controllerFactory !== "function"
      || typeof settings.captureWriter !== "function"
      || typeof settings.coordinateProvider !== "function"
      || typeof settings.onFirstFinished !== "function"
      || typeof settings.onRestartFinished !== "function") {
    fail("material_shop_agent_journey_options_invalid",
      "journey requires injected Runtime, capture, coordinate, and persistence boundaries");
  }

  const sessions = [];
  const controls = [];
  const captures = [];
  let controller = null;
  let sessionLabel = "first";
  let commitMayHaveReachedAuthority = false;
  let commitDispatch = null;

  const stepAt = (index) => plan.steps[index];
  const beginControl = (step) => ({
    stepId: step.id,
    ordinal: step.ordinal,
    transport: Protocol.AGENT_RUNTIME_TRANSPORT,
    methods: clone(step.driverMethods),
    actionIntents: [],
    actionReceipts: [],
    captureRefs: [],
    completedAt: null,
  });
  const completeControl = (control) => {
    control.completedAt = new Date().toISOString();
    controls.push(control);
  };
  const startController = async (label) => assertController(await Promise.resolve(
    settings.controllerFactory({
      sessionLabel: label,
      plan,
      preparation: settings.preparation,
      runDir: settings.runDir,
    })), label);
  const saveCapture = async (step, control) => {
    const fresh = await controller.capture(WEB_OVERLAY);
    const receipt = await Promise.resolve(settings.captureWriter(settings.runDir, {
      root: settings.preparation.root,
      sessionLabel,
      stepId: step.id,
      capture: fresh,
    }));
    if (!isObject(receipt) || typeof receipt.captureSha256 !== "string"
        || !/^[a-fA-F0-9]{64}$/.test(receipt.captureSha256)) {
      fail("material_shop_agent_capture_receipt_invalid",
        "capture writer did not return one bound WGC receipt", { stepId: step.id });
    }
    const frozen = clone(receipt);
    captures.push(frozen);
    control.captureRefs.push(frozen.captureSha256);
    return frozen;
  };
  const click = async (step, control, role) => {
    const result = await controller.click({
      coordinateProvider: (fresh) => assertPoint(
        settings.coordinateProvider(step, fresh, role), fresh, step.id, role),
      reason: "A5 " + step.id + ": " + role,
    });
    const proven = assertActionResult(result, step.id, role);
    recordAction(control, step, role, proven);
    return proven.receipt;
  };
  const recordAction = (control, step, role, proven) => {
    control.actionIntents.push({ role, method: proven.action.operation,
      arguments: clone(proven.action.arguments), actionId: proven.action.actionId,
      receiptSha256: Evidence.sha256Text(Evidence.canonicalJson(proven.receipt)) });
    control.actionReceipts.push(proven.receipt);
  };
  const typeSearch = async (step, control, role, text) => {
    const proven = assertActionResult(await controller.typeText({
      text,
      reason: "A5 " + step.id + ": " + role,
    }), step.id, role);
    recordAction(control, step, role, proven);
  };
  const selectAll = async (step, control, role) => {
    const proven = assertActionResult(await controller.pressKey({
      key: "A",
      modifiers: ["ctrl"],
      repeat: 1,
      reason: "A5 " + step.id + ": " + role,
    }), step.id, role);
    recordAction(control, step, role, proven);
  };
  const pressKey = async (step, control, role, key, repeat) => {
    const proven = assertActionResult(await controller.pressKey({
      key, modifiers: [], repeat: repeat || 1,
      reason: "A5 " + step.id + ": " + role,
    }), step.id, role);
    recordAction(control, step, role, proven);
  };
  const openMaterials = async (step, control) => {
    const proven = assertActionResult(await controller.openMaterials(
      "A5 " + step.id + ": open exact materials route"), step.id, "open_materials");
    recordAction(control, step, "open_materials", proven);
  };
  const finishSession = async (label) => {
    const session = buildSession(label, controller, await controller.finish());
    sessions.push(session);
    return session;
  };

  try {
    controller = await startController("first");

    {
      const step = stepAt(0); const control = beginControl(step);
      await openMaterials(step, control);
      await saveCapture(step, control);
      completeControl(control);
    }
    {
      const step = stepAt(1); const control = beginControl(step);
      await saveCapture(step, control);
      completeControl(control);
    }
    {
      const step = stepAt(2); const control = beginControl(step);
      await pressKey(step, control, "materials_tree_next_root", "arrow_right", 1);
      await pressKey(step, control, "materials_tree_open_type", "enter", 1);
      await pressKey(step, control, "materials_tree_next_type", "arrow_right", 1);
      await pressKey(step, control, "materials_tree_open_equipment_mod", "enter", 1);
      await pressKey(step, control, "materials_tree_back_type", "escape", 1);
      await pressKey(step, control, "materials_tree_back_root", "escape", 1);
      await pressKey(step, control, "materials_tab_to_search", "tab", 3);
      await pressKey(step, control, "materials_tab_to_sort", "tab", 4);
      await pressKey(step, control, "materials_sort_open", "arrow_down", 1);
      await pressKey(step, control, "materials_sort_close", "escape", 1);
      await pressKey(step, control, "materials_tab_to_first_card", "tab", 1);
      await pressKey(step, control, "materials_grid_next", "arrow_right", 1);
      await pressKey(step, control, "materials_grid_previous", "arrow_left", 1);
      await saveCapture(step, control);
      completeControl(control);
    }
    {
      const step = stepAt(3); const control = beginControl(step);
      await pressKey(step, control, "materials_tab_to_exact_recipe", "tab", 3);
      await pressKey(step, control, "materials_open_exact_recipe", "enter", 1);
      completeControl(control);
    }
    {
      const step = stepAt(4); const control = beginControl(step);
      await saveCapture(step, control);
      completeControl(control);
    }
    {
      const step = stepAt(5); const control = beginControl(step);
      await saveCapture(step, control);
      await pressKey(step, control, "recipe_close_with_escape", "escape", 1);
      completeControl(control);
    }
    {
      const step = stepAt(6); const control = beginControl(step);
      await openMaterials(step, control);
      await saveCapture(step, control);
      completeControl(control);
    }
    for (const index of [7, 8]) {
      const step = stepAt(index); const control = beginControl(step);
      await saveCapture(step, control);
      completeControl(control);
    }
    {
      const step = stepAt(9); const control = beginControl(step);
      await click(step, control, "ordinary_search_input");
      await selectAll(step, control, "ordinary_search_select_all");
      await typeSearch(step, control, "ordinary_search_text", PURCHASE_TEXT);
      await click(step, control, "ordinary_filtered_card");
      await click(step, control, "ordinary_shop_cta");
      completeControl(control);
    }
    {
      const step = stepAt(10); const control = beginControl(step);
      await saveCapture(step, control);
      await click(step, control, "npcshop_close");
      completeControl(control);
    }
    {
      const step = stepAt(11); const control = beginControl(step);
      await openMaterials(step, control);
      await saveCapture(step, control);
      completeControl(control);
    }
    {
      const step = stepAt(12); const control = beginControl(step);
      await click(step, control, "unlocked_search_input");
      await typeSearch(step, control, "unlocked_search_text", PURCHASE_TEXT);
      await click(step, control, "unlocked_filtered_card");
      await click(step, control, "chef_shop_cta");
      completeControl(control);
    }
    {
      const step = stepAt(13); const control = beginControl(step);
      await saveCapture(step, control);
      completeControl(control);
    }
    {
      const step = stepAt(14); const control = beginControl(step);
      await pressKey(step, control, "unlocked_focused_catalog_card", "enter", 1);
      await saveCapture(step, control);
      await click(step, control, "npcshop_checkout");
      completeControl(control);
    }
    {
      const step = stepAt(15); const control = beginControl(step);
      await saveCapture(step, control);
      completeControl(control);
    }
    {
      const step = stepAt(16); const control = beginControl(step);
      commitMayHaveReachedAuthority = true;
      const receipt = await click(step, control, "settlement_commit");
      commitDispatch = {
        stepId: step.id,
        authorizationDecisionId: plan.authorization.decisionId,
        authorizationDecisionSha256: plan.authorization.decisionSha256,
        actionReceiptSha256: Evidence.sha256Text(Evidence.canonicalJson(receipt)),
      };
      completeControl(control);
    }
    {
      const step = stepAt(17); const control = beginControl(step);
      // Extra WGC evidence is allowed on this non-required-capture step and records
      // the post-commit settlement before the visible Return action.
      await saveCapture(step, control);
      await click(step, control, "return_to_materials");
      completeControl(control);
    }
    {
      const step = stepAt(18); const control = beginControl(step);
      const finishedController = controller;
      const session = await finishSession("first");
      completeControl(control);
      controller = null;
      await settings.onFirstFinished({
        sessionLabel: "first", controller: finishedController, session,
        sessions, controls, captures, commitDispatch,
        commitMayHaveReachedAuthority,
      });
    }
    {
      const step = stepAt(19); const control = beginControl(step);
      sessionLabel = "restart";
      controller = await startController("restart");
      completeControl(control);
    }
    {
      const step = stepAt(20); const control = beginControl(step);
      await openMaterials(step, control);
      await saveCapture(step, control);
      completeControl(control);
    }
    {
      const step = stepAt(21); const control = beginControl(step);
      await click(step, control, "restart_search_input");
      await typeSearch(step, control, "restart_search_text", PURCHASE_TEXT);
      await click(step, control, "restart_filtered_card");
      await saveCapture(step, control);
      completeControl(control);
    }
    {
      const step = stepAt(22); const control = beginControl(step);
      await click(step, control, "crafting_close");
      completeControl(control);
    }
    {
      const step = stepAt(23); const control = beginControl(step);
      const finishedController = controller;
      const session = await finishSession("restart");
      completeControl(control);
      controller = null;
      await settings.onRestartFinished({
        sessionLabel: "restart", controller: finishedController, session,
        sessions, controls, captures, commitDispatch,
        commitMayHaveReachedAuthority,
      });
    }

    if (controls.length !== FROZEN_STEPS.length || sessions.length !== 2
        || !commitDispatch) {
      fail("material_shop_agent_journey_incomplete",
        "Agent Runtime journey did not close the exact 24-step/two-session route");
    }
    const captureByStep = Object.fromEntries(captures.map((entry) => [entry.stepId, entry]));
    return { sessions, controls, captures, captureByStep, commitDispatch,
      firstShutdown: shutdownProjection(sessions[0]),
      restartShutdown: shutdownProjection(sessions[1]),
      commitMayHaveReachedAuthority };
  } catch (caught) {
    const error = caught && typeof caught === "object"
      ? caught : new Error(String(caught));
    error.agentRuntimeState = {
      commitMayHaveReachedAuthority,
      controller,
      sessions,
      controls,
      captures,
    };
    throw error;
  }
}

module.exports = {
  designPoint,
  execute,
};
