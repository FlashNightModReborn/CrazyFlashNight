"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const test = require("node:test");
const Journey = require("./agent-runtime-journey");
const Protocol = require("./protocol");

const STEPS = [
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
  ["restart_readback", ["input.click", "input.type_text", "observation.capture", "content.read"]],
  ["restart_close", ["input.click"]],
  ["trusted_runner_final_shutdown", ["trusted_runner_finish"]],
];

function sha(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex");
}

function plan() {
  return {
    schema: Protocol.AGENT_RUNTIME_PLAN_SCHEMA,
    recipeJump: JSON.parse(JSON.stringify(Protocol.AGENT_RUNTIME_RECIPE_JUMP)),
    authorization: {
      decisionId: "a5-test-qty1",
      decisionSha256: "a".repeat(64),
    },
    steps: STEPS.map((entry, ordinal) => ({
      ordinal,
      id: entry[0],
      transportClass: [18, 19, 23].includes(ordinal)
        ? "trusted_runner_lifecycle" : "agent_runtime_visible_input",
      allowedTransports: [Protocol.AGENT_RUNTIME_TRANSPORT],
      driverMethods: entry[1].slice(),
    })),
  };
}

function capture(label, ordinal) {
  return {
    width: 1024,
    height: 576,
    frame: { width: 1024, height: 576, frameId: label + "-frame-" + ordinal },
  };
}

class FakeController {
  constructor(label, events, failure) {
    this.label = label;
    this.events = events;
    this.failure = failure;
    this.ordinal = 0;
    this.status = {
      projectRunning: true,
      qualificationState: "verified",
      lifecycleRef: "lifecycle-" + label,
    };
    this.ledger = [];
  }

  nextCapture() {
    this.ordinal += 1;
    return capture(this.label, this.ordinal);
  }

  receipt(method, reason, argumentsValue) {
    const actionId = sha(this.label + method + reason).slice(0, 24);
    const action = { actionId, operation: method, arguments: argumentsValue };
    const result = {
      terminal: true,
      outcome: "input_dispatched",
      evidenceKind: "broker_dispatch",
      reasonCode: "none",
      reconcileKind: "none",
      retryable: false,
      actionId,
    };
    this.ledger.push({ request: { method, params: action }, result, error: null });
    return { action, receipt: result };
  }

  maybeFail(role) {
    if (this.failure === role) {
      const error = new Error("fake failure at " + role);
      error.code = "fake_" + role;
      throw error;
    }
  }

  async openMaterials(reason) {
    this.events.push("open:" + this.label + ":" + reason.split(":")[0].slice(3));
    return this.receipt("panel.open", reason, { panel: "materials" });
  }

  async capture() {
    const value = this.nextCapture();
    this.ledger.push({ request: { method: "observation.capture" }, result: {}, error: null });
    this.ledger.push({ request: { method: "content.read" }, result: {}, error: null });
    return value;
  }

  async click(options) {
    const role = options.reason.split(": ")[1];
    this.events.push("click:" + this.label + ":" + role);
    this.maybeFail(role);
    const fresh = this.nextCapture();
    const point = options.coordinateProvider(fresh);
    assert.deepEqual(point, { x: 512, y: 288 });
    return this.receipt("input.click", options.reason, {
      coordinateSpace: "observation_px", x: point.x, y: point.y,
      button: "primary", clickCount: 1,
    });
  }

  async typeText(options) {
    const role = options.reason.split(": ")[1];
    this.events.push("type:" + this.label + ":" + role + ":" + options.text);
    this.maybeFail(role);
    return this.receipt("input.type_text", options.reason, { text: options.text });
  }

  async pressKey(options) {
    const role = options.reason.split(": ")[1];
    if (role === "unlocked_focused_catalog_card") {
      assert.equal(options.key, "enter");
      assert.deepEqual(options.modifiers, []);
      assert.equal(options.repeat, 1);
    }
    this.events.push("key:" + this.label + ":" + role + ":" + options.key);
    this.maybeFail(role);
    return this.receipt("input.press_key", options.reason, {
      key: options.key, modifiers: options.modifiers, repeat: options.repeat,
    });
  }

  async finish() {
    this.events.push("finish:" + this.label);
    this.maybeFail("finish_" + this.label);
    const transcript = [{ label: this.label, event: "complete" }];
    return {
      completion: { schema: "fake-completion", label: this.label },
      transcript,
      transcriptSha256: sha(JSON.stringify(transcript)),
      exitCode: 0,
      ledger: this.ledger.slice(),
    };
  }
}

function fixture(failure) {
  const events = [];
  let captureOrdinal = 0;
  const options = {
    plan: plan(),
    preparation: { root: "E:\\repo" },
    runDir: "E:\\repo\\tmp\\run",
    controllerFactory: ({ sessionLabel }) => {
      events.push("start:" + sessionLabel);
      return new FakeController(sessionLabel, events, failure);
    },
    captureWriter: (_runDir, value) => {
      captureOrdinal += 1;
      events.push("capture:" + value.sessionLabel + ":" + value.stepId);
      return { stepId: value.stepId, captureSha256: sha(value.stepId + captureOrdinal) };
    },
    coordinateProvider: (step, fresh, role) => {
      assert.notEqual(role, "unlocked_focused_catalog_card");
      events.push("coordinate:" + step.id + ":" + role + ":" + fresh.frame.frameId);
      return Journey.designPoint(fresh, 512, 288);
    },
    onFirstFinished: (state) => {
      events.push("callback:first:" + state.session.label);
    },
    onRestartFinished: (state) => {
      events.push("callback:restart:" + state.session.label);
    },
  };
  return { events, options };
}

test("executes exact frozen order in two sessions with one commit write", async () => {
  const value = fixture();
  const result = await Journey.execute(value.options);
  assert.deepEqual(result.controls.map((entry) => entry.stepId), STEPS.map((entry) => entry[0]));
  assert.deepEqual(result.sessions.map((entry) => entry.label), ["first", "restart"]);
  assert.equal(result.controls.length, 24);
  assert.equal(result.captures.length, 16);
  assert.equal(result.commitMayHaveReachedAuthority, true);
  assert.equal(result.commitDispatch.stepId, "unlocked_commit");
  assert.equal(result.controls[16].actionReceipts.length, 1);
  assert.equal(result.controls[2].actionIntents.length, 13);
  assert.equal(result.controls[3].actionIntents.length, 2);
  assert.deepEqual(result.controls[14].actionIntents.map((entry) => ({
    role: entry.role, method: entry.method,
  })), [
    { role: "unlocked_focused_catalog_card", method: "input.press_key" },
    { role: "npcshop_checkout", method: "input.click" },
  ]);
  assert.deepEqual(result.controls[3].actionIntents.map((entry) => ({
    role: entry.role, method: entry.method, arguments: entry.arguments,
  })), [
    { role: "materials_tab_to_exact_recipe", method: "input.press_key",
      arguments: { key: "tab", modifiers: [], repeat: 3 } },
    { role: "materials_open_exact_recipe", method: "input.press_key",
      arguments: { key: "enter", modifiers: [], repeat: 1 } },
  ]);
  assert.equal(value.events.filter((entry) => entry === "click:first:settlement_commit").length, 1);
  assert.ok(value.events.indexOf("finish:first") < value.events.indexOf("start:restart"));
  assert.ok(value.events.indexOf("callback:first:first") < value.events.indexOf("start:restart"));
  assert.ok(value.events.indexOf("finish:restart") < value.events.indexOf("callback:restart:restart"));
  assert.ok(result.controls.every((entry, index) =>
    JSON.stringify(entry.methods) === JSON.stringify(STEPS[index][1])));
  assert.ok(result.controls.flatMap((entry) => entry.actionReceipts)
    .every((receipt) => receipt.terminal === true
      && receipt.outcome === "input_dispatched"
      && receipt.evidenceKind === "broker_dispatch"
      && receipt.reasonCode === "none"
      && receipt.reconcileKind === "none"
      && receipt.retryable === false));
  assert.deepEqual(value.events.filter((entry) => !entry.startsWith("coordinate:")), [
    "start:first",
    "open:first:open_materials",
    "capture:first:open_materials",
    "capture:first:materials_visual_current_window",
    "key:first:materials_tree_next_root:arrow_right",
    "key:first:materials_tree_open_type:enter",
    "key:first:materials_tree_next_type:arrow_right",
    "key:first:materials_tree_open_equipment_mod:enter",
    "key:first:materials_tree_back_type:escape",
    "key:first:materials_tree_back_root:escape",
    "key:first:materials_tab_to_search:tab",
    "key:first:materials_tab_to_sort:tab",
    "key:first:materials_sort_open:arrow_down",
    "key:first:materials_sort_close:escape",
    "key:first:materials_tab_to_first_card:tab",
    "key:first:materials_grid_next:arrow_right",
    "key:first:materials_grid_previous:arrow_left",
    "capture:first:materials_keyboard",
    "key:first:materials_tab_to_exact_recipe:tab",
    "key:first:materials_open_exact_recipe:enter",
    "capture:first:materials_recipe_jump",
    "capture:first:recipe_escape_close",
    "key:first:recipe_close_with_escape:escape",
    "open:first:recipe_reopen_materials",
    "capture:first:recipe_reopen_materials",
    "capture:first:materials_multi_variant",
    "capture:first:materials_portraits",
    "click:first:ordinary_search_input",
    "key:first:ordinary_search_select_all:A",
    "type:first:ordinary_search_text:食用油",
    "click:first:ordinary_filtered_card",
    "click:first:ordinary_shop_cta",
    "capture:first:ordinary_close",
    "click:first:npcshop_close",
    "open:first:reopen_materials",
    "capture:first:reopen_materials",
    "click:first:unlocked_search_input",
    "type:first:unlocked_search_text:食用油",
    "click:first:unlocked_filtered_card",
    "click:first:chef_shop_cta",
    "capture:first:unlocked_exact_focus",
    "key:first:unlocked_focused_catalog_card:enter",
    "capture:first:unlocked_intent_qty1",
    "click:first:npcshop_checkout",
    "capture:first:unlocked_settlement",
    "click:first:settlement_commit",
    "capture:first:unlocked_return",
    "click:first:return_to_materials",
    "finish:first",
    "callback:first:first",
    "start:restart",
    "open:restart:restart_open_materials",
    "capture:restart:restart_open_materials",
    "click:restart:restart_search_input",
    "type:restart:restart_search_text:食用油",
    "click:restart:restart_filtered_card",
    "capture:restart:restart_readback",
    "click:restart:crafting_close",
    "finish:restart",
    "callback:restart:restart",
  ]);
});

test("focused Enter failure stops before checkout and commit authority", async () => {
  const value = fixture("unlocked_focused_catalog_card");
  await assert.rejects(Journey.execute(value.options), (error) => {
    assert.equal(error.code, "fake_unlocked_focused_catalog_card");
    assert.equal(error.agentRuntimeState.commitMayHaveReachedAuthority, false);
    assert.equal(error.agentRuntimeState.controller.label, "first");
    assert.equal(error.agentRuntimeState.sessions.length, 0);
    assert.deepEqual(error.agentRuntimeState.controls.map((entry) => entry.stepId),
      STEPS.slice(0, 14).map((entry) => entry[0]));
    return true;
  });
  assert.equal(value.events.filter((entry) =>
    entry === "key:first:unlocked_focused_catalog_card:enter").length, 1);
  assert.equal(value.events.some((entry) => entry === "click:first:npcshop_checkout"), false);
  assert.equal(value.events.some((entry) => entry === "click:first:settlement_commit"), false);
});

test("commit dispatch failure is conservatively authority-risking", async () => {
  const value = fixture("settlement_commit");
  await assert.rejects(Journey.execute(value.options), (error) => {
    assert.equal(error.code, "fake_settlement_commit");
    assert.equal(error.agentRuntimeState.commitMayHaveReachedAuthority, true);
    assert.equal(error.agentRuntimeState.controller.label, "first");
    assert.equal(error.agentRuntimeState.sessions.length, 0);
    assert.equal(error.agentRuntimeState.controls.some((entry) => entry.stepId === "unlocked_commit"),
      false);
    return true;
  });
  assert.equal(value.events.filter((entry) => entry === "click:first:settlement_commit").length, 1);
});

test("terminal rejected visible action fails at the exact pre-commit role", async () => {
  const value = fixture();
  const originalFactory = value.options.controllerFactory;
  value.options.controllerFactory = (settings) => {
    const controller = originalFactory(settings);
    const originalClick = controller.click.bind(controller);
    controller.click = async (options) => {
      const result = await originalClick(options);
      if (options.reason.endsWith(": settlement_commit")) {
        result.receipt.outcome = "rejected";
        result.receipt.evidenceKind = "none";
        result.receipt.reasonCode = "hit_test_mismatch";
        result.receipt.reconcileKind = "not_dispatched";
      }
      return result;
    };
    return controller;
  };
  await assert.rejects(Journey.execute(value.options), (error) => {
    assert.equal(error.code, "material_shop_agent_action_receipt_invalid");
    assert.equal(error.details.stepId, "unlocked_commit");
    assert.equal(error.details.role, "settlement_commit");
    assert.equal(error.details.terminal, true);
    assert.equal(error.details.outcome, "rejected");
    assert.equal(error.details.evidenceKind, "none");
    assert.equal(error.details.reasonCode, "hit_test_mismatch");
    assert.equal(error.details.reconcileKind, "not_dispatched");
    assert.equal(error.details.retryable, false);
    assert.equal(error.agentRuntimeState.commitMayHaveReachedAuthority, true);
    return true;
  });
});

test("designPoint is frame-bound and rejects invalid design coordinates", () => {
  assert.deepEqual(Journey.designPoint({ width: 512, height: 288 }, 512, 288),
    { x: 256, y: 144 });
  assert.throws(() => Journey.designPoint({ width: 512, height: 288 }, 1024, 10), {
    code: "material_shop_agent_design_point_invalid",
  });
});
