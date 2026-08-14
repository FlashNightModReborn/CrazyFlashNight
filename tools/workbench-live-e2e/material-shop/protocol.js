"use strict";

const Evidence = require("../lib/evidence-artifact");
const Applicability = require("./applicability");
const Common = require("./common");

const PLAN_SCHEMA = "workbench-live-e2e.material-shop.control-plan.v2";
const LEGACY_AGENT_RUNTIME_PLAN_SCHEMA = "workbench-live-e2e.material-shop.control-plan.v3";
const AGENT_RUNTIME_PLAN_SCHEMA = "workbench-live-e2e.material-shop.control-plan.v4";
const EVIDENCE_SCHEMA = "workbench-live-e2e.material-shop.journey-evidence.v4";
const LEGACY_AGENT_RUNTIME_EVIDENCE_SCHEMA =
  "workbench-live-e2e.material-shop.journey-evidence.v6";
const AGENT_RUNTIME_EVIDENCE_SCHEMA = "workbench-live-e2e.material-shop.journey-evidence.v9";
const LEGACY_AGENT_RUNTIME_V6_RUN_ID = "a5-material-shop-agent-20260813t1903";
const LEGACY_AGENT_RUNTIME_V6_PLAN_SHA256 =
  "9f8f85a6b9602ca088c10ba08e08b59b18865629bef846bea11774e9c9f2ed37";
const LEGACY_AGENT_RUNTIME_V6_EVIDENCE_SHA256 =
  "6d0f61b7f7964809d0ae0ec15a65e69a3d868270d9c7eec0338c4a66868c71b5";
const PORTRAIT_REVIEW_PENDING = "pending_independent_visible_png_review";
const AUTHORIZATION_SCHEMA = "workbench-live-e2e.material-shop.purchase-authorization.v1";
const AGENT_RUNTIME_AUTHORIZATION_SCHEMA =
  "workbench-live-e2e.material-shop.purchase-authorization.v2";
const PREFERRED_TRANSPORT = "codex_computer_use";
const FALLBACK_TRANSPORT = "cdp_input_dispatch";
const RUNNER_TRANSPORT = "material_shop_runner";
const AGENT_RUNTIME_PROVIDER = "cf7_agent_runtime_jsonl";
const AGENT_RUNTIME_TRANSPORT = "project_agent_runtime_jsonl";
const AGENT_RUNTIME_SLOT = "cf7_agent_a5_material_shop_run";
const AGENT_RUNTIME_CANDIDATE_LEAF = "a5";
const FALLBACK_METHODS = Object.freeze([
  "Input.dispatchMouseEvent",
  "Input.dispatchKeyEvent",
]);
const EVIDENCE_MODES = Object.freeze(["offline_fixture", "candidate_capture"]);
const RESULT_BY_MODE = Object.freeze({
  offline_fixture: "OFFLINE_VERIFIED",
  candidate_capture: "CANDIDATE_CAPTURED",
});
const CLOSE_REASONS = Object.freeze(["button", "escape", "backdrop", "toggle"]);
const AGENT_RUNTIME_RECIPE_JUMP = Object.freeze({
  materialName: "军用帆布",
  category: "属性武器",
  recipeIndex: 0,
  productName: "二阶复合防御组件",
  initialFocusPath: Object.freeze([]),
  keyboardActions: Object.freeze([
    Object.freeze({ stepId: "materials_keyboard", role: "materials_tree_next_root",
      key: "arrow_right", modifiers: Object.freeze([]), repeat: 1 }),
    Object.freeze({ stepId: "materials_keyboard", role: "materials_tree_open_type",
      key: "enter", modifiers: Object.freeze([]), repeat: 1 }),
    Object.freeze({ stepId: "materials_keyboard", role: "materials_tree_next_type",
      key: "arrow_right", modifiers: Object.freeze([]), repeat: 1 }),
    Object.freeze({ stepId: "materials_keyboard", role: "materials_tree_open_equipment_mod",
      key: "enter", modifiers: Object.freeze([]), repeat: 1 }),
    Object.freeze({ stepId: "materials_keyboard", role: "materials_tree_back_type",
      key: "escape", modifiers: Object.freeze([]), repeat: 1 }),
    Object.freeze({ stepId: "materials_keyboard", role: "materials_tree_back_root",
      key: "escape", modifiers: Object.freeze([]), repeat: 1 }),
    Object.freeze({ stepId: "materials_keyboard", role: "materials_tab_to_search",
      key: "tab", modifiers: Object.freeze([]), repeat: 3 }),
    Object.freeze({ stepId: "materials_keyboard", role: "materials_tab_to_sort",
      key: "tab", modifiers: Object.freeze([]), repeat: 4 }),
    Object.freeze({ stepId: "materials_keyboard", role: "materials_sort_open",
      key: "arrow_down", modifiers: Object.freeze([]), repeat: 1 }),
    Object.freeze({ stepId: "materials_keyboard", role: "materials_sort_close",
      key: "escape", modifiers: Object.freeze([]), repeat: 1 }),
    Object.freeze({ stepId: "materials_keyboard", role: "materials_tab_to_first_card",
      key: "tab", modifiers: Object.freeze([]), repeat: 1 }),
    Object.freeze({ stepId: "materials_keyboard", role: "materials_grid_next",
      key: "arrow_right", modifiers: Object.freeze([]), repeat: 1 }),
    Object.freeze({ stepId: "materials_keyboard", role: "materials_grid_previous",
      key: "arrow_left", modifiers: Object.freeze([]), repeat: 1 }),
    Object.freeze({ stepId: "recipe_jump_intent", role: "materials_tab_to_exact_recipe",
      key: "tab", modifiers: Object.freeze([]), repeat: 3 }),
    Object.freeze({ stepId: "recipe_jump_intent", role: "materials_open_exact_recipe",
      key: "enter", modifiers: Object.freeze([]), repeat: 1 }),
    Object.freeze({ stepId: "recipe_escape_close", role: "recipe_close_with_escape",
      key: "escape", modifiers: Object.freeze([]), repeat: 1 }),
  ]),
});

function agentRuntimeEvidenceSchemaForPlan(plan) {
  if (plan && plan.runId === LEGACY_AGENT_RUNTIME_V6_RUN_ID) {
    if (plan.planSha256 !== LEGACY_AGENT_RUNTIME_V6_PLAN_SHA256) {
      Common.fail("material_shop_legacy_agent_evidence_identity_invalid", "evidence",
        "legacy Agent Runtime v6 is restricted to the exact frozen t1903 plan");
    }
    return LEGACY_AGENT_RUNTIME_EVIDENCE_SCHEMA;
  }
  return AGENT_RUNTIME_EVIDENCE_SCHEMA;
}

function createAgentRuntimePortraitEvidence(plan, capturePresent) {
  const schema = agentRuntimeEvidenceSchemaForPlan(plan);
  if (capturePresent !== true) {
    Common.fail("material_shop_portrait_evidence_invalid", "evidence",
      "Agent Runtime portrait evidence requires its exact capture, not portrait resolution");
  }
  // v6 field names are preserved only so the frozen t1903 evidence bytes can replay.
  // Their historical meaning is capture presence; they are never a visible-resolution verdict.
  if (schema === LEGACY_AGENT_RUNTIME_EVIDENCE_SCHEMA) {
    return { enemyResolved: true, shopResolved: true,
      fallbackHarnessBound: true, identityLeak: false };
  }
  return { capturePresent: true, resolutionStatus: PORTRAIT_REVIEW_PENDING,
    independentReviewRequired: true };
}

function agentRuntimePortraitReviewBoundary(plan, capturePresent) {
  agentRuntimeEvidenceSchemaForPlan(plan);
  if (capturePresent !== true) {
    Common.fail("material_shop_portrait_evidence_invalid", "evidence",
      "portrait review boundary requires its exact visible capture");
  }
  return { status: PORTRAIT_REVIEW_PENDING, capturePresent: true,
    independentVisiblePngReviewRequired: true, portraitResolutionVerified: false };
}

const BASE_STEPS = Object.freeze([
  "open_materials",
  "materials_visual_current_window",
  "materials_keyboard",
  "materials_multi_variant",
  "materials_portraits",
  "ordinary_forward",
  "ordinary_close",
  "reopen_materials",
  "unlocked_forward",
  "unlocked_exact_focus",
  "unlocked_intent_qty1",
  "unlocked_settlement",
  "unlocked_commit",
  "unlocked_return",
  "safeexit",
  "exit_confirm",
  "restart_candidate",
  "restart_open_materials",
  "restart_readback",
  "restart_close",
  "supported_shutdown",
]);
const AGENT_RUNTIME_BASE_STEPS = Object.freeze([
  "open_materials",
  "materials_visual_current_window",
  "materials_keyboard",
  "recipe_jump_intent",
  "materials_recipe_jump",
  "recipe_escape_close",
  "recipe_reopen_materials",
  "materials_multi_variant",
  "materials_portraits",
  "ordinary_forward",
  "ordinary_close",
  "reopen_materials",
  "unlocked_forward",
  "unlocked_exact_focus",
  "unlocked_intent_qty1",
  "unlocked_settlement",
  "unlocked_commit",
  "unlocked_return",
  "trusted_runner_persistence_shutdown",
  "restart_candidate",
  "restart_open_materials",
  "restart_readback",
  "restart_close",
  "trusted_runner_final_shutdown",
]);
const LEGACY_AGENT_RUNTIME_BASE_STEPS = Object.freeze([
  "open_materials", "materials_visual_current_window", "materials_keyboard",
  "materials_multi_variant", "materials_portraits", "ordinary_forward", "ordinary_close",
  "reopen_materials", "unlocked_forward", "unlocked_exact_focus", "unlocked_intent_qty1",
  "unlocked_settlement", "unlocked_commit", "unlocked_return",
  "trusted_runner_persistence_shutdown", "restart_candidate", "restart_open_materials",
  "restart_readback", "restart_close", "trusted_runner_final_shutdown",
]);
const LOCKED_STEPS = Object.freeze([
  "locked_forward", "locked_exact_focus", "locked_purchase_blocked", "locked_return",
]);
const MAX_STEPS = Object.freeze([
  "max_forward", "max_exact_focus", "max_purchase_blocked", "max_return",
]);
const NATIVE_STEPS = new Set([
  "open_materials", "reopen_materials", "safeexit", "exit_confirm",
  "restart_open_materials",
]);
const RUNNER_STEPS = new Set(["restart_candidate", "supported_shutdown"]);
const KEYBOARD_STEPS = new Set([
  "materials_keyboard", "recipe_jump_intent", "recipe_escape_close",
  "locked_return", "unlocked_return", "max_return", "restart_close",
]);
const CAPTURE_STEPS = new Set([
  "open_materials", "materials_visual_current_window", "materials_keyboard",
  "materials_multi_variant",
  "materials_portraits", "locked_exact_focus", "locked_purchase_blocked",
  "ordinary_close", "unlocked_exact_focus", "unlocked_settlement",
  "max_exact_focus", "max_purchase_blocked", "safeexit", "restart_readback",
]);
const AGENT_RUNTIME_CAPTURE_STEPS = new Set(Array.from(CAPTURE_STEPS)
  .filter((stepId) => stepId !== "safeexit")
  .concat(["materials_recipe_jump", "recipe_escape_close", "recipe_reopen_materials",
    "reopen_materials", "unlocked_intent_qty1", "unlocked_return",
    "restart_open_materials"]));
const AGENT_RUNTIME_LIFECYCLE_STEPS = new Set([
  "trusted_runner_persistence_shutdown", "restart_candidate", "trusted_runner_final_shutdown",
]);
const AGENT_RUNTIME_OBSERVATION_ONLY_STEPS = new Set([
  "materials_visual_current_window", "materials_recipe_jump",
  "materials_multi_variant", "materials_portraits",
  "locked_exact_focus", "locked_purchase_blocked", "unlocked_exact_focus",
  "unlocked_settlement", "max_exact_focus", "max_purchase_blocked",
]);
const FORBIDDEN_CONTROLLER_SURFACES = Object.freeze([
  /\bBridge\s*\.\s*send\b/i,
  /\bPanels\s*\.\s*(?:open|close)\b/i,
  /\bRuntime\s*\.\s*evaluate\b/i,
  /\bexecuteScript\b/i,
  /\bpostMessage\b/i,
  /\bbusiness\s*api\b/i,
  /\btogglePurchase\b/i,
  /\bopenSettlement\b/i,
  /\btradeCommit\b/i,
  /\bshopCheckout\b/i,
  /\bdocument\s*\./i,
  /\bwindow\s*\./i,
  /\bxpath\b/i,
  /\bselector\b/i,
]);

const VISIBLE_TARGETS = Object.freeze({
  open_materials: "Native HUD MATERIALS control; confirm the material archive is visibly open",
  materials_visual_current_window: "Material archive in the current candidate window: tree, catalog, detail, sources, and uses",
  materials_keyboard: "Visible keyboard path through material tree, search, sort, catalog, and detail",
  recipe_jump_intent: "Key-only exact recipe activation for 军用帆布",
  materials_recipe_jump: "Exact 属性武器 recipe 0 destination for 二阶复合防御组件",
  recipe_escape_close: "Exact recipe destination immediately before the Escape outer-close action",
  recipe_reopen_materials: "Material archive reopened after the exact recipe route closes",
  materials_multi_variant: "All structured drop rows for one enemy identity are simultaneously visible",
  materials_portraits: "Naturally reachable enemy and NPC-shop portraits are visibly rendered",
  locked_forward: "Locked material shop-source navigation control",
  locked_exact_focus: "Exact locked catalog row navigation highlight and keyboard focus",
  locked_purchase_blocked: "Locked catalog row purchase surface remains disabled",
  locked_return: "Visible Return to Materials control from the locked route",
  ordinary_forward: "Ordinary-close sample material shop-source navigation control",
  ordinary_close: "Visible NPC shop outer close control",
  reopen_materials: "Native HUD MATERIALS control after ordinary close",
  unlocked_forward: "Unlocked material shop-source navigation control",
  unlocked_exact_focus: "Exact unlocked catalog row navigation highlight and keyboard focus",
  unlocked_intent_qty1: "Visible purchase intent for quantity one on the exact unlocked material",
  unlocked_settlement: "Visible settlement containing quantity one purchase and zero sale",
  unlocked_commit: "Explicit visible confirm control for the authorized quantity-one purchase",
  unlocked_return: "Visible Return to Materials control after settlement",
  max_forward: "At-limit material shop-source navigation control",
  max_exact_focus: "Exact at-limit catalog row navigation highlight and keyboard focus",
  max_purchase_blocked: "At-limit catalog row purchase surface remains disabled",
  max_return: "Visible Return to Materials control from the at-limit route",
  safeexit: "Native HUD SAFEEXIT control and visible save completion state",
  exit_confirm: "Native SAFEEXIT completion panel exit control",
  restart_candidate: "Runner-owned fresh candidate process restart",
  restart_open_materials: "Native HUD MATERIALS control in the fresh candidate process",
  restart_readback: "Fresh-process material archive readback of the purchased quantity",
  restart_close: "Visible material archive outer close control after restart readback",
  supported_shutdown: "Runner-owned supported candidate shutdown control",
  trusted_runner_persistence_shutdown: "Trusted runner persistence fence and exact clean process exit; this is not GUI SAFEEXIT",
  trusted_runner_final_shutdown: "Trusted runner final persistence fence and exact clean process exit",
});
const AGENT_RUNTIME_VISIBLE_TARGETS = Object.freeze(Object.assign({}, VISIBLE_TARGETS, {
  open_materials: "Project Agent Runtime panel.open with exact name materials; then visibly capture the material archive",
  materials_keyboard: "Key-only default archive route through material tree, sort, and first catalog card",
  recipe_jump_intent: "Project Agent Runtime key-only activation of the first exact 军用帆布 recipe action",
  materials_recipe_jump: "Visible exact recipe destination: 属性武器 index 0, 二阶复合防御组件",
  recipe_escape_close: "Visible exact recipe destination immediately before guarded Escape closes it",
  recipe_reopen_materials: "Project Agent Runtime panel.open with exact name materials after recipe Escape close",
  reopen_materials: "Project Agent Runtime panel.open with exact name materials after ordinary close",
  restart_open_materials: "Project Agent Runtime panel.open with exact name materials in the fresh candidate process",
}));
const LEGACY_AGENT_RUNTIME_VISIBLE_TARGETS = Object.freeze(Object.assign({},
  AGENT_RUNTIME_VISIBLE_TARGETS, {
    materials_keyboard: "Visible keyboard path through material tree, search, sort, catalog, and detail",
  }));
const AGENT_RUNTIME_RPC_METHODS = Object.freeze([
  "panel.open", "input.click", "input.press_key", "input.type_text",
  "observation.capture", "content.read",
]);

function exactString(value, maximum) {
  return typeof value === "string" && value.length > 0 && value.length <= maximum
    && value === value.trim() && !/[\u0000-\u001f\u007f]/.test(value);
}

function assertNoControllerApi(text, context) {
  const value = String(text || "");
  FORBIDDEN_CONTROLLER_SURFACES.forEach((pattern) => {
    if (pattern.test(value)) {
      Common.fail("material_shop_controller_api_forbidden", "protocol",
        "journey controller may operate only visible input surfaces", { context });
    }
  });
}

function validateScopeBinding(value) {
  Common.exactKeys(value, ["head", "scopeSha256", "closureSha256",
    "materializationSha256"], "material_shop_plan_scope_invalid", "protocol");
  if (!Common.GIT_OID_RE.test(String(value.head || ""))
      || !Common.SHA256_RE.test(String(value.scopeSha256 || ""))
      || !Common.SHA256_RE.test(String(value.closureSha256 || ""))
      || !Common.SHA256_RE.test(String(value.materializationSha256 || ""))) {
    Common.fail("material_shop_plan_scope_invalid", "protocol",
      "journey plan is not bound to one current-tree materialization");
  }
  return value;
}

function validateEnvironmentCapability(value, mode) {
  Common.exactKeys(value, ["available", "source", "artifact", "artifactSha256"],
    "material_shop_environment_capability_invalid", "protocol");
  const expectedSource = mode === "offline_fixture"
    ? "offline_fixture_capability" : "operator_attested_computer_use_environment";
  if (typeof value.available !== "boolean" || value.source !== expectedSource
      || !Evidence.isPlainObject(value.artifact)
      || value.artifactSha256 !== Evidence.sha256Text(Evidence.canonicalJson(value.artifact))) {
    Common.fail("material_shop_environment_capability_invalid", "protocol",
      "environment capability must bind one explicit operator-attested tool artifact");
  }
  return value;
}

function validateLegacyAuthorization(value, mode) {
  Common.exactKeys(value, ["schema", "decisionId", "source", "oneShot", "stepId",
    "quantity", "saleCount", "decisionSha256"],
  "material_shop_authorization_invalid", "protocol");
  const source = mode === "offline_fixture"
    ? "offline_fixture_authorization" : "operator_authorization";
  const unsigned = Object.assign({}, value);
  delete unsigned.decisionSha256;
  if (value.schema !== AUTHORIZATION_SCHEMA || !Common.ID_RE.test(String(value.decisionId || ""))
      || value.source !== source || value.oneShot !== true || value.stepId !== "unlocked_commit"
      || value.quantity !== 1 || value.saleCount !== 0
      || value.decisionSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_authorization_invalid", "protocol",
      "isolated quantity-one purchase lacks one exact one-shot authorization");
  }
  return value;
}

function authorizationTarget(value, phase) {
  Common.exactKeys(value, ["shopId", "catalogIndex", "itemName"],
    "material_shop_authorization_invalid", phase || "protocol");
  if (!exactString(value.shopId, 80) || !Number.isInteger(value.catalogIndex)
      || value.catalogIndex < 0 || value.catalogIndex > 10000
      || !exactString(value.itemName, 128)) {
    Common.fail("material_shop_authorization_invalid", phase || "protocol",
      "purchase authorization target identity is malformed");
  }
  return value;
}

function validateAgentRuntimeAuthorization(value, mode, binding) {
  Common.exactKeys(value, ["schema", "decisionId", "source", "oneShot", "stepId",
    "quantity", "saleCount", "runId", "applicabilitySha256", "target", "decisionSha256"],
  "material_shop_authorization_invalid", "protocol");
  const source = mode === "offline_fixture"
    ? "offline_fixture_authorization" : "operator_authorization";
  const unsigned = Object.assign({}, value);
  delete unsigned.decisionSha256;
  authorizationTarget(value.target, "protocol");
  if (value.schema !== AGENT_RUNTIME_AUTHORIZATION_SCHEMA
      || !Common.ID_RE.test(String(value.decisionId || ""))
      || !Common.ID_RE.test(String(value.runId || ""))
      || !Common.SHA256_RE.test(String(value.applicabilitySha256 || ""))
      || value.source !== source || value.oneShot !== true || value.stepId !== "unlocked_commit"
      || value.quantity !== 1 || value.saleCount !== 0
      || value.decisionSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_authorization_invalid", "protocol",
      "current Agent Runtime purchase lacks one exact bound authorization");
  }
  if (binding) {
    authorizationTarget(binding.target, "protocol");
    if (value.runId !== binding.runId
        || value.applicabilitySha256 !== binding.applicabilitySha256
        || Evidence.canonicalJson(value.target) !== Evidence.canonicalJson(binding.target)) {
      Common.fail("material_shop_authorization_binding_invalid", "protocol",
        "current Agent Runtime authorization is detached from its run, applicability, or target");
    }
  }
  return value;
}

function validateAuthorization(value, mode) {
  if (value && value.schema === AUTHORIZATION_SCHEMA) {
    return validateLegacyAuthorization(value, mode);
  }
  if (value && value.schema === AGENT_RUNTIME_AUTHORIZATION_SCHEMA) {
    return validateAgentRuntimeAuthorization(value, mode);
  }
  Common.fail("material_shop_authorization_invalid", "protocol",
    "purchase authorization schema is unsupported");
}

function applicabilitySummary(value, includeSelectedTarget) {
  Applicability.validateApplicability(value);
  const summary = {
    applicabilitySha256: value.applicabilitySha256,
    counts: value.counts,
    unlocked: value.unlocked,
    locked: value.locked,
    max: value.max,
  };
  if (includeSelectedTarget === true) {
    summary.selectedUnlockedTarget = {
      shopId: value.selectedUnlockedTarget.shopId,
      catalogIndex: value.selectedUnlockedTarget.catalogIndex,
      itemName: value.selectedUnlockedTarget.itemName,
    };
  }
  return summary;
}

function validateApplicabilitySummary(value, includeSelectedTarget) {
  Common.exactKeys(value, ["applicabilitySha256", "counts", "unlocked", "locked", "max",
    ...(includeSelectedTarget === true ? ["selectedUnlockedTarget"] : [])],
    "material_shop_plan_applicability_invalid", "protocol");
  if (!Common.SHA256_RE.test(String(value.applicabilitySha256 || ""))) {
    Common.fail("material_shop_plan_applicability_invalid", "protocol",
      "plan applicability digest is malformed");
  }
  Common.exactKeys(value.counts, ["materialCount", "shopFileCount",
    "materialOccurrenceCount", "uniqueMaterialItemCount", "requiredInfoOccurrenceCount",
    "purchaseLimitOccurrenceCount", "seedCount", "seedMaterialPairCount",
    "affordableSeedOccurrenceCount", "atDefaultLimitSeedOccurrenceCount"],
  "material_shop_plan_applicability_invalid", "protocol");
  ["unlocked", "locked", "max"].forEach((route) => {
    Common.exactKeys(value[route], ["status", "qualifyingOccurrenceCount"],
      "material_shop_plan_applicability_invalid", "protocol");
  });
  if (value.unlocked.status !== "required_candidate_journey"
      || value.unlocked.qualifyingOccurrenceCount < 1
      || !["not_applicable_current_data", "requires_seed_probe"].includes(value.locked.status)
      || !["not_applicable_current_data", "requires_seed_probe"].includes(value.max.status)) {
    Common.fail("material_shop_plan_applicability_invalid", "protocol",
      "plan contains an unsupported live-route applicability state");
  }
  if (includeSelectedTarget === true) {
    authorizationTarget(value.selectedUnlockedTarget, "protocol");
  }
  return value;
}

function requiredSteps(summary) {
  validateApplicabilitySummary(summary);
  const steps = BASE_STEPS.slice();
  const ordinaryIndex = steps.indexOf("ordinary_forward");
  if (summary.locked.status === "required_candidate_journey") {
    steps.splice(ordinaryIndex, 0, ...LOCKED_STEPS);
  }
  const safeExitIndex = steps.indexOf("safeexit");
  if (summary.max.status === "required_candidate_journey") {
    steps.splice(safeExitIndex, 0, ...MAX_STEPS);
  }
  return steps;
}

function requiredAgentRuntimeSteps(summary, legacy) {
  validateApplicabilitySummary(summary, legacy !== true);
  const steps = (legacy === true
    ? LEGACY_AGENT_RUNTIME_BASE_STEPS : AGENT_RUNTIME_BASE_STEPS).slice();
  const ordinaryIndex = steps.indexOf("ordinary_forward");
  if (summary.locked.status === "required_candidate_journey") {
    steps.splice(ordinaryIndex, 0, ...LOCKED_STEPS);
  }
  const shutdownIndex = steps.indexOf("trusted_runner_persistence_shutdown");
  if (summary.max.status === "required_candidate_journey") {
    steps.splice(shutdownIndex, 0, ...MAX_STEPS);
  }
  return steps;
}

function transportClass(stepId) {
  if (RUNNER_STEPS.has(stepId)) return "runner_owned";
  if (NATIVE_STEPS.has(stepId)) return "native_visible_input";
  return "panel_visible_input";
}

function actionForStep(stepId) {
  if (stepId === "restart_candidate") return "restart_candidate";
  if (stepId === "supported_shutdown") return "supported_shutdown";
  if (CAPTURE_STEPS.has(stepId)) return "capture_visible_ui";
  if (KEYBOARD_STEPS.has(stepId)) return "send_visible_keyboard_input";
  return "activate_visible_control";
}

function allowedTransports(stepId, policy) {
  if (RUNNER_STEPS.has(stepId)) return [RUNNER_TRANSPORT];
  if (NATIVE_STEPS.has(stepId)) return [PREFERRED_TRANSPORT];
  return policy.panelFallbackExplicitlyAuthorized
    ? [PREFERRED_TRANSPORT, FALLBACK_TRANSPORT] : [PREFERRED_TRANSPORT];
}

function driverMethods(stepId, policy) {
  if (stepId === "restart_candidate") return ["runner_candidate_restart"];
  if (stepId === "supported_shutdown") return ["runner_supported_shutdown"];
  const methods = ["computer_use"];
  if (transportClass(stepId) === "panel_visible_input"
      && policy.panelFallbackExplicitlyAuthorized) {
    methods.push(KEYBOARD_STEPS.has(stepId)
      ? "Input.dispatchKeyEvent" : "Input.dispatchMouseEvent");
  }
  return methods;
}

function validateTransportPolicy(value, mode, routeProbeRequired) {
  Common.exactKeys(value, ["preferredTransport", "nativeTransport", "panelPrimaryTransport",
    "panelFallbackTransport", "panelFallbackExplicitlyAuthorized", "environmentCapability",
    "liveAdmission"], "material_shop_transport_policy_invalid", "protocol");
  validateEnvironmentCapability(value.environmentCapability, mode);
  const expectedAdmission = !value.environmentCapability.available
    ? "blocked_environment_computer_use_unavailable"
    : routeProbeRequired ? "blocked_route_seed_probe_required"
      : "candidate_ui_probe_required";
  if (value.preferredTransport !== PREFERRED_TRANSPORT
      || value.nativeTransport !== PREFERRED_TRANSPORT
      || value.panelPrimaryTransport !== PREFERRED_TRANSPORT
      || value.panelFallbackTransport !== (value.panelFallbackExplicitlyAuthorized
        ? FALLBACK_TRANSPORT : null)
      || typeof value.panelFallbackExplicitlyAuthorized !== "boolean"
      || value.liveAdmission !== expectedAdmission) {
    Common.fail("material_shop_transport_policy_invalid", "protocol",
      "native input and panel fallback policy is malformed");
  }
  return value;
}

function validateAgentRuntimeTransportPolicy(value, routeProbeRequired) {
  Common.exactKeys(value, ["provider", "transport", "trustedRunnerSlot", "candidateLeaf",
    "panelOpen", "allowedRpcMethods", "runnerOperations", "liveAdmission"],
  "material_shop_agent_runtime_policy_invalid", "protocol");
  Common.exactKeys(value.panelOpen, ["method", "name"],
    "material_shop_agent_runtime_policy_invalid", "protocol");
  const expectedAdmission = routeProbeRequired
    ? "blocked_route_seed_probe_required" : "candidate_ui_probe_required";
  if (value.provider !== AGENT_RUNTIME_PROVIDER
      || value.transport !== AGENT_RUNTIME_TRANSPORT
      || value.trustedRunnerSlot !== AGENT_RUNTIME_SLOT
      || value.candidateLeaf !== AGENT_RUNTIME_CANDIDATE_LEAF
      || value.panelOpen.method !== "panel.open" || value.panelOpen.name !== "materials"
      || Evidence.canonicalJson(value.allowedRpcMethods)
        !== Evidence.canonicalJson(AGENT_RUNTIME_RPC_METHODS)
      || Evidence.canonicalJson(value.runnerOperations)
        !== Evidence.canonicalJson(["trusted_runner_finish", "restart_candidate"])
      || value.liveAdmission !== expectedAdmission) {
    Common.fail("material_shop_agent_runtime_policy_invalid", "protocol",
      "A5 live plan must bind the exact project Agent Runtime JSONL slot and candidate");
  }
  return value;
}

function agentRuntimeActionForStep(stepId, legacy) {
  if (stepId === "open_materials" || stepId === "reopen_materials"
      || stepId === "recipe_reopen_materials"
      || stepId === "restart_open_materials") return "panel_open_materials";
  if (stepId === "restart_candidate") return "restart_candidate";
  if (stepId === "trusted_runner_persistence_shutdown"
      || stepId === "trusted_runner_final_shutdown") return "trusted_runner_shutdown";
  if (stepId === "unlocked_intent_qty1") return "send_visible_keyboard_input";
  if (stepId === "restart_close") return "activate_visible_control";
  if (legacy !== true && KEYBOARD_STEPS.has(stepId)) return "send_visible_keyboard_input";
  if (AGENT_RUNTIME_CAPTURE_STEPS.has(stepId)) return "capture_visible_ui";
  if (KEYBOARD_STEPS.has(stepId)) return "send_visible_keyboard_input";
  return "activate_visible_control";
}

function agentRuntimeDriverMethods(stepId, legacy) {
  if (stepId === "restart_candidate") return ["restart_candidate"];
  if (stepId === "trusted_runner_persistence_shutdown"
      || stepId === "trusted_runner_final_shutdown") return ["trusted_runner_finish"];
  if (stepId === "open_materials" || stepId === "reopen_materials"
      || stepId === "recipe_reopen_materials"
      || stepId === "restart_open_materials") {
    return ["panel.open", "observation.capture", "content.read"];
  }
  if (stepId === "materials_keyboard") {
    return legacy === true
      ? ["input.click", "input.type_text", "observation.capture", "content.read"]
      : ["input.press_key", "observation.capture", "content.read"];
  }
  if (stepId === "recipe_jump_intent") return ["input.press_key"];
  if (stepId === "recipe_escape_close") {
    return ["input.press_key", "observation.capture", "content.read"];
  }
  if (stepId === "ordinary_forward") {
    return ["input.click", "input.press_key", "input.type_text"];
  }
  if (stepId === "unlocked_forward") {
    return ["input.click", "input.type_text"];
  }
  if (stepId === "unlocked_intent_qty1") {
    return ["input.press_key", "input.click", "observation.capture", "content.read"];
  }
  if (stepId === "restart_readback") {
    return ["input.click", "input.type_text", "observation.capture", "content.read"];
  }
  if (stepId === "restart_close") {
    return ["input.click"];
  }
  if (stepId === "unlocked_return") {
    return ["input.click", "observation.capture", "content.read"];
  }
  const methods = AGENT_RUNTIME_OBSERVATION_ONLY_STEPS.has(stepId)
    ? [] : [KEYBOARD_STEPS.has(stepId) ? "input.press_key" : "input.click"];
  if (AGENT_RUNTIME_CAPTURE_STEPS.has(stepId)) {
    methods.push("observation.capture", "content.read");
  }
  return methods;
}

function validateAgentRuntimeStep(step, index, expectedId, authorization, legacy) {
  Common.exactKeys(step, ["ordinal", "id", "action", "visibleTarget", "transportClass",
    "allowedTransports", "driverMethods", "requiresCapture", "requiresCommitAuthorization",
    "authorizationRef"], "material_shop_control_step_invalid", "protocol");
  const commit = expectedId === "unlocked_commit";
  const methods = agentRuntimeDriverMethods(expectedId, legacy);
  const visibleTargets = legacy === true
    ? LEGACY_AGENT_RUNTIME_VISIBLE_TARGETS : AGENT_RUNTIME_VISIBLE_TARGETS;
  if (step.ordinal !== index || step.id !== expectedId
      || step.action !== agentRuntimeActionForStep(expectedId, legacy)
      || step.visibleTarget !== visibleTargets[expectedId]
      || !exactString(step.visibleTarget, 240)
      || step.transportClass !== (AGENT_RUNTIME_LIFECYCLE_STEPS.has(expectedId)
        ? "trusted_runner_lifecycle" : "agent_runtime_visible_input")
      || Evidence.canonicalJson(step.allowedTransports)
        !== Evidence.canonicalJson([AGENT_RUNTIME_TRANSPORT])
      || Evidence.canonicalJson(step.driverMethods) !== Evidence.canonicalJson(methods)
      || step.requiresCapture !== AGENT_RUNTIME_CAPTURE_STEPS.has(expectedId)
      || step.requiresCommitAuthorization !== commit
      || methods.some((method) => !["restart_candidate", "trusted_runner_finish"].includes(method)
        && !AGENT_RUNTIME_RPC_METHODS.includes(method))) {
    Common.fail("material_shop_control_step_invalid", "protocol",
      "Agent Runtime step differs from the frozen A5 JSONL route", { index, expectedId });
  }
  if (commit) {
    Common.exactKeys(step.authorizationRef, ["decisionId", "decisionSha256"],
      "material_shop_authorization_ref_invalid", "protocol");
    if (step.authorizationRef.decisionId !== authorization.decisionId
        || step.authorizationRef.decisionSha256 !== authorization.decisionSha256) {
      Common.fail("material_shop_authorization_ref_invalid", "protocol",
        "purchase step is detached from its one-shot authorization");
    }
  } else if (step.authorizationRef !== null) {
    Common.fail("material_shop_authorization_ref_unexpected", "protocol",
      "non-purchase step carries a purchase authorization", { expectedId });
  }
  assertNoControllerApi(Evidence.canonicalJson(step), expectedId + ":agent_runtime_step");
  return step;
}

function validateAgentRuntimeRecipeJump(value) {
  Common.exactKeys(value, ["materialName", "category", "recipeIndex", "productName",
    "initialFocusPath", "keyboardActions"],
  "material_shop_agent_runtime_recipe_jump_invalid", "protocol");
  if (Evidence.canonicalJson(value) !== Evidence.canonicalJson(AGENT_RUNTIME_RECIPE_JUMP)) {
    Common.fail("material_shop_agent_runtime_recipe_jump_invalid", "protocol",
      "Agent Runtime recipe route differs from the exact key-only 军用帆布 jump");
  }
  return value;
}

function validateStep(step, index, expectedId, policy, authorization) {
  Common.exactKeys(step, ["ordinal", "id", "action", "visibleTarget", "transportClass",
    "allowedTransports", "driverMethods", "requiresCapture", "requiresCommitAuthorization",
    "authorizationRef"], "material_shop_control_step_invalid", "protocol");
  const commit = expectedId === "unlocked_commit";
  if (step.ordinal !== index || step.id !== expectedId || step.action !== actionForStep(expectedId)
      || !exactString(step.visibleTarget, 240) || step.visibleTarget !== VISIBLE_TARGETS[expectedId]
      || step.transportClass !== transportClass(expectedId)
      || Evidence.canonicalJson(step.allowedTransports)
        !== Evidence.canonicalJson(allowedTransports(expectedId, policy))
      || Evidence.canonicalJson(step.driverMethods)
        !== Evidence.canonicalJson(driverMethods(expectedId, policy))
      || step.requiresCapture !== CAPTURE_STEPS.has(expectedId)
      || step.requiresCommitAuthorization !== commit) {
    Common.fail("material_shop_control_step_invalid", "protocol",
      "journey step differs from the frozen visible-input route", { index, expectedId });
  }
  if (step.transportClass === "native_visible_input"
      && (step.allowedTransports.length !== 1
        || step.allowedTransports[0] !== PREFERRED_TRANSPORT
        || step.driverMethods.length !== 1 || step.driverMethods[0] !== "computer_use")) {
    Common.fail("material_shop_native_fallback_forbidden", "protocol",
      "CDP must never substitute for Native HUD input", { expectedId });
  }
  if (step.driverMethods.some((method) => method.startsWith("Input.")
      && !FALLBACK_METHODS.includes(method))) {
    Common.fail("material_shop_cdp_method_forbidden", "protocol",
      "CDP fallback is limited to Input.dispatch mouse/key methods", { expectedId });
  }
  if (commit) {
    Common.exactKeys(step.authorizationRef, ["decisionId", "decisionSha256"],
      "material_shop_authorization_ref_invalid", "protocol");
    if (step.authorizationRef.decisionId !== authorization.decisionId
        || step.authorizationRef.decisionSha256 !== authorization.decisionSha256) {
      Common.fail("material_shop_authorization_ref_invalid", "protocol",
        "purchase step is detached from its one-shot authorization");
    }
  } else if (step.authorizationRef !== null) {
    Common.fail("material_shop_authorization_ref_unexpected", "protocol",
      "non-purchase step carries a purchase authorization", { expectedId });
  }
  assertNoControllerApi(Evidence.canonicalJson(step), expectedId + ":step");
  return step;
}

function stablePlan(value) {
  const stable = { schema: value.schema, runId: value.runId, evidenceMode: value.evidenceMode,
    sourceFixtureSlot: value.sourceFixtureSlot, slots: value.slots, scope: value.scope,
    applicability: value.applicability, transportPolicy: value.transportPolicy,
    authorization: value.authorization, steps: value.steps, boundaries: value.boundaries };
  if (value.schema === AGENT_RUNTIME_PLAN_SCHEMA) stable.recipeJump = value.recipeJump;
  return stable;
}

function validateControlPlan(value) {
  if (value && [AGENT_RUNTIME_PLAN_SCHEMA, LEGACY_AGENT_RUNTIME_PLAN_SCHEMA]
    .includes(value.schema)) {
    return validateAgentRuntimeControlPlan(value);
  }
  Common.exactKeys(value, ["schema", "runId", "evidenceMode", "sourceFixtureSlot", "slots",
    "scope", "applicability", "transportPolicy", "authorization", "steps", "boundaries",
    "planSha256"], "material_shop_control_plan_invalid", "protocol");
  if (value.schema !== PLAN_SCHEMA || !Common.ID_RE.test(String(value.runId || ""))
      || !EVIDENCE_MODES.includes(value.evidenceMode)
      || value.sourceFixtureSlot !== Common.SOURCE_FIXTURE_SLOT
      || value.planSha256 !== Evidence.sha256Text(Evidence.canonicalJson(stablePlan(value)))) {
    Common.fail("material_shop_control_plan_invalid", "protocol",
      "control plan envelope, fixture source, or digest is invalid");
  }
  Common.exactKeys(value.slots, ["seedSlot", "targetSlot", "recoverySlot"],
    "material_shop_control_slots_invalid", "protocol");
  Common.assertDedicatedSlots(value.slots.seedSlot, value.slots.targetSlot,
    value.slots.recoverySlot);
  validateScopeBinding(value.scope);
  const summary = validateApplicabilitySummary(value.applicability);
  const routeProbeRequired = summary.locked.status === "requires_seed_probe"
    || summary.max.status === "requires_seed_probe";
  validateTransportPolicy(value.transportPolicy, value.evidenceMode, routeProbeRequired);
  validateLegacyAuthorization(value.authorization, value.evidenceMode);
  const expectedSteps = requiredSteps(summary);
  if (!Array.isArray(value.steps) || value.steps.length !== expectedSteps.length) {
    Common.fail("material_shop_control_steps_invalid", "protocol",
      "control plan does not contain the applicability-derived exact step sequence");
  }
  value.steps.forEach((step, index) => validateStep(step, index, expectedSteps[index],
    value.transportPolicy, value.authorization));
  Common.exactKeys(value.boundaries, ["controllerMayCallBusinessApis", "realGuiExecuted",
    "candidateBuilt", "candidateExecuted", "deployed"],
  "material_shop_plan_boundary_invalid", "protocol");
  if (value.boundaries.controllerMayCallBusinessApis !== false
      || Object.keys(value.boundaries).filter((key) => key !== "controllerMayCallBusinessApis")
        .some((key) => value.boundaries[key] !== false)) {
    Common.fail("material_shop_plan_boundary_invalid", "protocol",
      "an unexecuted plan cannot claim runtime or deployment evidence");
  }
  return value;
}

function validateAgentRuntimeControlPlan(value) {
  const legacy = value && value.schema === LEGACY_AGENT_RUNTIME_PLAN_SCHEMA;
  const current = value && value.schema === AGENT_RUNTIME_PLAN_SCHEMA;
  Common.exactKeys(value, ["schema", "runId", "evidenceMode", "sourceFixtureSlot", "slots",
    "scope", "applicability", "transportPolicy", "authorization", "steps", "boundaries",
    ...(current ? ["recipeJump"] : []), "planSha256"],
  "material_shop_control_plan_invalid", "protocol");
  if ((!legacy && !current)
      || !Common.ID_RE.test(String(value.runId || ""))
      || value.evidenceMode !== "candidate_capture"
      || value.sourceFixtureSlot !== Common.SOURCE_FIXTURE_SLOT
      || value.planSha256 !== Evidence.sha256Text(Evidence.canonicalJson(stablePlan(value)))) {
    Common.fail("material_shop_control_plan_invalid", "protocol",
      "Agent Runtime control plan envelope, fixture source, or digest is invalid");
  }
  if (legacy && (value.runId !== LEGACY_AGENT_RUNTIME_V6_RUN_ID
      || value.planSha256 !== LEGACY_AGENT_RUNTIME_V6_PLAN_SHA256)) {
    Common.fail("material_shop_legacy_agent_plan_identity_invalid", "protocol",
      "legacy Agent Runtime v3 is readable only for the exact frozen t1903 plan");
  }
  if (current) validateAgentRuntimeRecipeJump(value.recipeJump);
  Common.exactKeys(value.slots, ["seedSlot", "targetSlot", "recoverySlot"],
    "material_shop_control_slots_invalid", "protocol");
  Common.assertDedicatedSlots(value.slots.seedSlot, value.slots.targetSlot,
    value.slots.recoverySlot);
  if (value.slots.targetSlot !== AGENT_RUNTIME_SLOT) {
    Common.fail("material_shop_agent_runtime_policy_invalid", "protocol",
      "Agent Runtime A5 plan requires its exact dedicated target slot");
  }
  validateScopeBinding(value.scope);
  const summary = validateApplicabilitySummary(value.applicability, current);
  const routeProbeRequired = summary.locked.status === "requires_seed_probe"
    || summary.max.status === "requires_seed_probe";
  validateAgentRuntimeTransportPolicy(value.transportPolicy, routeProbeRequired);
  if (legacy) {
    validateLegacyAuthorization(value.authorization, value.evidenceMode);
  } else {
    validateAgentRuntimeAuthorization(value.authorization, value.evidenceMode, {
      runId: value.runId,
      applicabilitySha256: summary.applicabilitySha256,
      target: summary.selectedUnlockedTarget,
    });
  }
  const expectedSteps = requiredAgentRuntimeSteps(summary, legacy);
  if (!Array.isArray(value.steps) || value.steps.length !== expectedSteps.length) {
    Common.fail("material_shop_control_steps_invalid", "protocol",
      "Agent Runtime plan does not contain the applicability-derived exact step sequence");
  }
  value.steps.forEach((step, index) => validateAgentRuntimeStep(step, index,
    expectedSteps[index], value.authorization, legacy));
  Common.exactKeys(value.boundaries, ["controllerMayCallBusinessApis", "realGuiExecuted",
    "candidateBuilt", "candidateExecuted", "deployed"],
  "material_shop_plan_boundary_invalid", "protocol");
  if (value.boundaries.controllerMayCallBusinessApis !== false
      || Object.keys(value.boundaries).filter((key) => key !== "controllerMayCallBusinessApis")
        .some((key) => value.boundaries[key] !== false)) {
    Common.fail("material_shop_plan_boundary_invalid", "protocol",
      "an unexecuted Agent Runtime plan cannot claim runtime or deployment evidence");
  }
  return value;
}

function createAuthorization(options) {
  const settings = options || {};
  const mode = String(settings.evidenceMode || "");
  if (!EVIDENCE_MODES.includes(mode) || !Common.ID_RE.test(String(settings.decisionId || ""))) {
    Common.fail("material_shop_authorization_invalid", "protocol",
      "authorization creation requires one closed mode and decision id");
  }
  const value = { schema: AUTHORIZATION_SCHEMA, decisionId: String(settings.decisionId),
    source: mode === "offline_fixture" ? "offline_fixture_authorization" : "operator_authorization",
    oneShot: true, stepId: "unlocked_commit", quantity: 1, saleCount: 0 };
  value.decisionSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateLegacyAuthorization(value, mode);
}

function createAgentRuntimeAuthorization(options) {
  const settings = options || {};
  const mode = String(settings.evidenceMode || "");
  if (mode !== "candidate_capture"
      || !Common.ID_RE.test(String(settings.decisionId || ""))
      || !Common.ID_RE.test(String(settings.runId || ""))
      || !Common.SHA256_RE.test(String(settings.applicabilitySha256 || ""))) {
    Common.fail("material_shop_authorization_invalid", "protocol",
      "current Agent Runtime authorization requires one run and applicability binding");
  }
  const target = {
    shopId: settings.target && settings.target.shopId,
    catalogIndex: settings.target && settings.target.catalogIndex,
    itemName: settings.target && settings.target.itemName,
  };
  authorizationTarget(target, "protocol");
  const value = {
    schema: AGENT_RUNTIME_AUTHORIZATION_SCHEMA,
    decisionId: String(settings.decisionId),
    source: "operator_authorization",
    oneShot: true,
    stepId: "unlocked_commit",
    quantity: 1,
    saleCount: 0,
    runId: String(settings.runId),
    applicabilitySha256: String(settings.applicabilitySha256),
    target,
  };
  value.decisionSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateAgentRuntimeAuthorization(value, mode, {
    runId: value.runId,
    applicabilitySha256: value.applicabilitySha256,
    target: value.target,
  });
}

function createControlPlan(options) {
  const settings = options || {};
  const mode = String(settings.evidenceMode || "");
  const summary = applicabilitySummary(settings.applicability);
  const environmentCapability = settings.environmentCapability;
  validateEnvironmentCapability(environmentCapability, mode);
  const transportPolicy = {
    preferredTransport: PREFERRED_TRANSPORT,
    nativeTransport: PREFERRED_TRANSPORT,
    panelPrimaryTransport: PREFERRED_TRANSPORT,
    panelFallbackTransport: settings.allowPanelCdpFallback === true ? FALLBACK_TRANSPORT : null,
    panelFallbackExplicitlyAuthorized: settings.allowPanelCdpFallback === true,
    environmentCapability,
    liveAdmission: !environmentCapability.available
      ? "blocked_environment_computer_use_unavailable"
      : summary.locked.status === "requires_seed_probe"
        || summary.max.status === "requires_seed_probe"
        ? "blocked_route_seed_probe_required" : "candidate_ui_probe_required",
  };
  const authorization = settings.authorization;
  validateLegacyAuthorization(authorization, mode);
  const stepIds = requiredSteps(summary);
  const steps = stepIds.map((id, ordinal) => ({
    ordinal, id, action: actionForStep(id), visibleTarget: VISIBLE_TARGETS[id],
    transportClass: transportClass(id), allowedTransports: allowedTransports(id, transportPolicy),
    driverMethods: driverMethods(id, transportPolicy),
    requiresCapture: CAPTURE_STEPS.has(id),
    requiresCommitAuthorization: id === "unlocked_commit",
    authorizationRef: id === "unlocked_commit"
      ? { decisionId: authorization.decisionId,
        decisionSha256: authorization.decisionSha256 } : null,
  }));
  const value = {
    schema: PLAN_SCHEMA, runId: String(settings.runId || ""), evidenceMode: mode,
    sourceFixtureSlot: Common.SOURCE_FIXTURE_SLOT,
    slots: Common.assertDedicatedSlots(settings.seedSlot, settings.targetSlot,
      settings.recoverySlot),
    scope: settings.scope, applicability: summary, transportPolicy, authorization, steps,
    boundaries: { controllerMayCallBusinessApis: false, realGuiExecuted: false,
      candidateBuilt: false, candidateExecuted: false, deployed: false },
  };
  value.planSha256 = Evidence.sha256Text(Evidence.canonicalJson(stablePlan(value)));
  return validateControlPlan(value);
}

function createAgentRuntimeControlPlan(options) {
  const settings = options || {};
  const mode = String(settings.evidenceMode || "");
  if (mode !== "candidate_capture") {
    Common.fail("material_shop_control_plan_invalid", "protocol",
      "project Agent Runtime JSONL is a candidate-live provider only");
  }
  const summary = applicabilitySummary(settings.applicability, true);
  const routeProbeRequired = summary.locked.status === "requires_seed_probe"
    || summary.max.status === "requires_seed_probe";
  const transportPolicy = {
    provider: AGENT_RUNTIME_PROVIDER,
    transport: AGENT_RUNTIME_TRANSPORT,
    trustedRunnerSlot: AGENT_RUNTIME_SLOT,
    candidateLeaf: AGENT_RUNTIME_CANDIDATE_LEAF,
    panelOpen: { method: "panel.open", name: "materials" },
    allowedRpcMethods: AGENT_RUNTIME_RPC_METHODS.slice(),
    runnerOperations: ["trusted_runner_finish", "restart_candidate"],
    liveAdmission: routeProbeRequired
      ? "blocked_route_seed_probe_required" : "candidate_ui_probe_required",
  };
  const authorization = settings.authorization;
  validateAgentRuntimeAuthorization(authorization, mode, {
    runId: String(settings.runId || ""),
    applicabilitySha256: summary.applicabilitySha256,
    target: summary.selectedUnlockedTarget,
  });
  const stepIds = requiredAgentRuntimeSteps(summary);
  const steps = stepIds.map((id, ordinal) => ({
    ordinal, id, action: agentRuntimeActionForStep(id, false),
    visibleTarget: AGENT_RUNTIME_VISIBLE_TARGETS[id],
    transportClass: AGENT_RUNTIME_LIFECYCLE_STEPS.has(id)
      ? "trusted_runner_lifecycle" : "agent_runtime_visible_input",
    allowedTransports: [AGENT_RUNTIME_TRANSPORT],
    driverMethods: agentRuntimeDriverMethods(id, false),
    requiresCapture: AGENT_RUNTIME_CAPTURE_STEPS.has(id),
    requiresCommitAuthorization: id === "unlocked_commit",
    authorizationRef: id === "unlocked_commit"
      ? { decisionId: authorization.decisionId,
        decisionSha256: authorization.decisionSha256 } : null,
  }));
  const value = {
    schema: AGENT_RUNTIME_PLAN_SCHEMA,
    runId: String(settings.runId || ""), evidenceMode: mode,
    sourceFixtureSlot: Common.SOURCE_FIXTURE_SLOT,
    slots: Common.assertDedicatedSlots(settings.seedSlot, settings.targetSlot,
      settings.recoverySlot),
    scope: settings.scope, applicability: summary, transportPolicy, authorization,
    recipeJump: JSON.parse(JSON.stringify(AGENT_RUNTIME_RECIPE_JUMP)), steps,
    boundaries: { controllerMayCallBusinessApis: false, realGuiExecuted: false,
      candidateBuilt: false, candidateExecuted: false, deployed: false },
  };
  value.planSha256 = Evidence.sha256Text(Evidence.canonicalJson(stablePlan(value)));
  return validateAgentRuntimeControlPlan(value);
}

function validateTarget(value, label) {
  Common.exactKeys(value, ["shopId", "catalogIndex", "itemName"],
    "material_shop_target_invalid", "evidence");
  if (!exactString(value.shopId, 80) || !Number.isInteger(value.catalogIndex)
      || value.catalogIndex < 0 || value.catalogIndex > 10000 || !exactString(value.itemName, 128)) {
    Common.fail("material_shop_target_invalid", "evidence",
      "journey target identity is malformed", { label });
  }
  return value;
}

function validateAgentRuntimeCloseOutcome(value, expected) {
  Common.exactKeys(value, ["closeStepId", "closeRole", "closeMethod",
    "closeActionReceiptSha256", "successorStepId", "successorMethod",
    "successorActionReceiptSha256", "successorCaptureSha256", "successorSessionLabel",
    "successorObservationId", "successorFrameId", "successorFrameContentHash",
    "admissionFence", "successorPanel"],
  "material_shop_agent_runtime_close_outcome_invalid", "evidence");
  if (value.closeStepId !== expected.closeStepId || value.closeRole !== expected.closeRole
      || value.closeMethod !== expected.closeMethod
      || value.successorStepId !== expected.successorStepId
      || value.successorMethod !== "panel.open"
      || value.successorSessionLabel !== "first"
      || !Common.ID_RE.test(String(value.successorObservationId || ""))
      || !Common.ID_RE.test(String(value.successorFrameId || ""))
      || !Common.SHA256_RE.test(String(value.successorFrameContentHash || ""))
      || value.admissionFence !== "prior_tracked_visual_idle_required"
      || value.successorPanel !== "materials"
      || !Common.SHA256_RE.test(String(value.closeActionReceiptSha256 || ""))
      || !Common.SHA256_RE.test(String(value.successorActionReceiptSha256 || ""))
      || !Common.SHA256_RE.test(String(value.successorCaptureSha256 || ""))
      || value.closeActionReceiptSha256 === value.successorActionReceiptSha256) {
    Common.fail("material_shop_agent_runtime_close_outcome_invalid", "evidence",
      "close outcome is not bound to its exact ordered idle-gated visible successor", {
        closeStepId: expected.closeStepId, successorStepId: expected.successorStepId,
      });
  }
  return value;
}

function validateOptionalBlockedRoute(value, route, summary) {
  if (summary.status === "not_applicable_current_data") {
    Common.exactKeys(value, ["status", "applicabilitySha256", "qualifyingOccurrenceCount"],
      "material_shop_route_na_invalid", "evidence");
    if (value.status !== summary.status || value.applicabilitySha256 == null
        || value.qualifyingOccurrenceCount !== 0) {
      Common.fail("material_shop_route_na_invalid", "evidence",
        "not-applicable route lacks exact current-data evidence", { route });
    }
    return value;
  }
  Common.exactKeys(value, ["status", "target", "forwardCommitted", "locatedExact",
    "navigationFocus", "purchaseBlocked", "tradePreviewCount", "tradeCommitCount",
    "returnCommitted"], "material_shop_blocked_route_invalid", "evidence");
  validateTarget(value.target, route);
  if (value.status !== "executed" || value.forwardCommitted !== true
      || value.locatedExact !== true || value.navigationFocus !== "data-navigation-focus"
      || value.purchaseBlocked !== true || value.tradePreviewCount !== 0
      || value.tradeCommitCount !== 0 || value.returnCommitted !== true) {
    Common.fail("material_shop_blocked_route_invalid", "evidence",
      "blocked route must navigate and return without purchase authority", { route });
  }
  return value;
}

function validateJourney(journey, plan) {
  Common.exactKeys(journey, ["operationLease", "externalToolchain", "materials", "routes", "persistence",
    "authorityCounts"],
    "material_shop_journey_invalid", "evidence");
  Common.exactKeys(journey.operationLease, ["leaseSha256", "mode", "activeAtCapture"],
    "material_shop_journey_invalid", "evidence");
  if (!Common.SHA256_RE.test(String(journey.operationLease.leaseSha256 || ""))
      || journey.operationLease.mode !== "live_execution"
      || journey.operationLease.activeAtCapture !== true) {
    Common.fail("material_shop_journey_invalid", "evidence",
      "journey evidence does not bind the shared lease held through raw capture");
  }
  Common.exactKeys(journey.externalToolchain, ["descriptorSha256", "runtimeBindingSha256",
    "guardedExactTwoFileLoad"], "material_shop_journey_invalid", "evidence");
  if (!Common.SHA256_RE.test(String(journey.externalToolchain.descriptorSha256 || ""))
      || !Common.SHA256_RE.test(String(
        journey.externalToolchain.runtimeBindingSha256 || ""))
      || journey.externalToolchain.guardedExactTwoFileLoad !== true) {
    Common.fail("material_shop_journey_invalid", "evidence",
      "journey evidence lacks the guarded external WebSocket toolchain binding");
  }
  const materials = journey.materials;
  Common.exactKeys(materials, ["archiveOrder", "visualVerified", "keyboardJourneyVerified",
    "candidateViewport", "responsiveThreeViewportGateBound", "multiVariant", "portraits"],
  "material_shop_materials_evidence_invalid", "evidence");
  Common.exactKeys(materials.multiVariant, ["enemyType", "occurrenceIndices", "allVisible"],
    "material_shop_multi_variant_invalid", "evidence");
  Common.exactKeys(materials.portraits, ["enemyResolved", "shopResolved",
    "fallbackHarnessBound", "identityLeak"], "material_shop_portrait_evidence_invalid", "evidence");
  if (materials.archiveOrder !== "authored_xml" || materials.visualVerified !== true
      || materials.keyboardJourneyVerified !== true
      || materials.candidateViewport !== "current_window"
      || materials.responsiveThreeViewportGateBound !== true
      || !exactString(materials.multiVariant.enemyType, 128)
      || !Array.isArray(materials.multiVariant.occurrenceIndices)
      || materials.multiVariant.occurrenceIndices.length < 2
      || materials.multiVariant.occurrenceIndices.some((entry, index) => entry !== index)
      || materials.multiVariant.allVisible !== true
      || materials.portraits.enemyResolved !== true || materials.portraits.shopResolved !== true
      || materials.portraits.fallbackHarnessBound !== true
      || materials.portraits.identityLeak !== false) {
    Common.fail("material_shop_materials_evidence_invalid", "evidence",
      "material visual/keyboard/multi-drop/portrait evidence is incomplete");
  }
  const routes = journey.routes;
  Common.exactKeys(routes, ["locked", "ordinaryClose", "unlocked", "max"],
    "material_shop_route_evidence_invalid", "evidence");
  validateOptionalBlockedRoute(routes.locked, "locked", plan.applicability.locked);
  validateOptionalBlockedRoute(routes.max, "max", plan.applicability.max);
  [routes.locked, routes.max].forEach((route) => {
    if (route.status === "not_applicable_current_data"
        && route.applicabilitySha256 !== plan.applicability.applicabilitySha256) {
      Common.fail("material_shop_route_na_invalid", "evidence",
        "not-applicable route is detached from the plan applicability artifact");
    }
  });
  Common.exactKeys(routes.ordinaryClose, ["target", "forwardCommitted", "reason",
    "reverseSent", "ordinaryCloseCommitted"],
  "material_shop_ordinary_close_invalid", "evidence");
  validateTarget(routes.ordinaryClose.target, "ordinary_close");
  if (routes.ordinaryClose.forwardCommitted !== true
      || !CLOSE_REASONS.includes(routes.ordinaryClose.reason)
      || routes.ordinaryClose.reverseSent !== false
      || routes.ordinaryClose.ordinaryCloseCommitted !== true) {
    Common.fail("material_shop_ordinary_close_invalid", "evidence",
      "ordinary close must return to game without consuming reverse capability");
  }
  Common.exactKeys(routes.unlocked, ["target", "forwardCommitted", "locatedExact",
    "navigationFocus", "quantity", "saleCount", "tradePreviewCount", "tradeCommitCount",
    "settled", "returnCommitted", "settlement"],
  "material_shop_unlocked_route_invalid", "evidence");
  Common.exactKeys(routes.unlocked.settlement, ["baselineBalance", "unitPrice", "buyTotal",
    "projectedBalance", "beforeOwned", "afterOwned"],
  "material_shop_unlocked_settlement_invalid", "evidence");
  validateTarget(routes.unlocked.target, "unlocked");
  if (routes.unlocked.forwardCommitted !== true || routes.unlocked.locatedExact !== true
      || routes.unlocked.navigationFocus !== "data-navigation-focus"
      || routes.unlocked.quantity !== 1 || routes.unlocked.saleCount !== 0
      || routes.unlocked.tradePreviewCount !== 1
      || routes.unlocked.tradeCommitCount !== 1
      || routes.unlocked.settled !== true || routes.unlocked.returnCommitted !== true
      || !Number.isFinite(routes.unlocked.settlement.baselineBalance)
      || !Number.isFinite(routes.unlocked.settlement.unitPrice)
      || routes.unlocked.settlement.unitPrice < 0
      || routes.unlocked.settlement.buyTotal !== routes.unlocked.settlement.unitPrice
      || routes.unlocked.settlement.projectedBalance
        !== routes.unlocked.settlement.baselineBalance - routes.unlocked.settlement.buyTotal
      || routes.unlocked.settlement.beforeOwned !== 0
      || routes.unlocked.settlement.afterOwned !== 1) {
    Common.fail("material_shop_unlocked_route_invalid", "evidence",
      "unlocked route must settle one explicit quantity-one purchase and zero sale");
  }
  Common.exactKeys(journey.persistence, ["safeExitCommitted", "seedReadOnly", "targetIsolated",
    "recoveryAvailable", "restartFreshProcess", "restartReadbackEqual", "supportedShutdown",
    "baselineMoney", "settledMoney", "beforeOwned", "archiveOwned", "restartOwned",
    "archiveSha256", "restartSha256"],
  "material_shop_persistence_invalid", "evidence");
  if ([journey.persistence.safeExitCommitted, journey.persistence.seedReadOnly,
    journey.persistence.targetIsolated, journey.persistence.recoveryAvailable,
    journey.persistence.restartFreshProcess, journey.persistence.restartReadbackEqual,
    journey.persistence.supportedShutdown].some((entry) => entry !== true)
      || journey.persistence.baselineMoney !== routes.unlocked.settlement.baselineBalance
      || journey.persistence.settledMoney !== routes.unlocked.settlement.projectedBalance
      || journey.persistence.beforeOwned !== 0 || journey.persistence.archiveOwned !== 1
      || journey.persistence.restartOwned !== 1
      || !Common.SHA256_RE.test(String(journey.persistence.archiveSha256 || ""))
      || journey.persistence.restartSha256 !== journey.persistence.archiveSha256) {
    Common.fail("material_shop_persistence_invalid", "evidence",
      "SAFEEXIT/restart/readback/recovery closure is incomplete");
  }
  const lockedRequired = plan.applicability.locked.status === "required_candidate_journey";
  const maxRequired = plan.applicability.max.status === "required_candidate_journey";
  const expectedForward = 2 + (lockedRequired ? 1 : 0) + (maxRequired ? 1 : 0);
  const expectedReverse = 1 + (lockedRequired ? 1 : 0) + (maxRequired ? 1 : 0);
  Common.exactKeys(journey.authorityCounts, ["forward", "reverse", "ordinaryClose",
    "tradePreview", "tradeCommit", "sale"],
  "material_shop_authority_counts_invalid", "evidence");
  if (journey.authorityCounts.forward !== expectedForward
      || journey.authorityCounts.reverse !== expectedReverse
      || journey.authorityCounts.ordinaryClose !== 1
      || journey.authorityCounts.tradePreview !== 1
      || journey.authorityCounts.tradeCommit !== 1 || journey.authorityCounts.sale !== 0) {
    Common.fail("material_shop_authority_counts_invalid", "evidence",
      "journey authority counts do not match applicability-derived routes");
  }
  return journey;
}

function stableEvidence(value) {
  return { schema: value.schema, runId: value.runId, evidenceMode: value.evidenceMode,
    planSha256: value.planSha256, scope: value.scope, controls: value.controls,
    journey: value.journey, result: value.result, boundaries: value.boundaries };
}

function createJourneyEvidence(options) {
  const settings = options || {};
  const plan = validateControlPlan(settings.plan);
  const value = { schema: EVIDENCE_SCHEMA, runId: plan.runId,
    evidenceMode: plan.evidenceMode, planSha256: plan.planSha256, scope: plan.scope,
    controls: settings.controls, journey: settings.journey,
    result: RESULT_BY_MODE[plan.evidenceMode], boundaries: settings.boundaries };
  value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(stableEvidence(value)));
  return validateJourneyEvidence(value, plan);
}

function validateAgentRuntimeJourney(journey, plan, evidenceSchema) {
  const expectedEvidenceSchema = agentRuntimeEvidenceSchemaForPlan(plan);
  if (evidenceSchema !== expectedEvidenceSchema) {
    Common.fail("material_shop_legacy_agent_evidence_identity_invalid", "evidence",
      "Agent Runtime journey schema must be derived from the exact plan identity");
  }
  Common.exactKeys(journey, ["operationLease", "agentRuntime", "materials", "routes",
    "persistence", "authorityCounts"],
  "material_shop_agent_runtime_journey_invalid", "evidence");
  Common.exactKeys(journey.operationLease, ["leaseSha256", "mode", "activeAtCapture"],
    "material_shop_agent_runtime_journey_invalid", "evidence");
  if (!Common.SHA256_RE.test(String(journey.operationLease.leaseSha256 || ""))
      || journey.operationLease.mode !== "live_execution"
      || journey.operationLease.activeAtCapture !== true) {
    Common.fail("material_shop_agent_runtime_journey_invalid", "evidence",
      "Agent Runtime journey does not bind the active shared operation lease");
  }
  Common.exactKeys(journey.agentRuntime, ["provider", "transport", "trustedRunnerSlot",
    "candidateLeaf", "sessionCount", "firstCompletionSha256", "restartCompletionSha256"],
  "material_shop_agent_runtime_journey_invalid", "evidence");
  if (journey.agentRuntime.provider !== AGENT_RUNTIME_PROVIDER
      || journey.agentRuntime.transport !== AGENT_RUNTIME_TRANSPORT
      || journey.agentRuntime.trustedRunnerSlot !== AGENT_RUNTIME_SLOT
      || journey.agentRuntime.candidateLeaf !== AGENT_RUNTIME_CANDIDATE_LEAF
      || journey.agentRuntime.sessionCount !== 2
      || !Common.SHA256_RE.test(String(journey.agentRuntime.firstCompletionSha256 || ""))
      || !Common.SHA256_RE.test(String(journey.agentRuntime.restartCompletionSha256 || ""))) {
    Common.fail("material_shop_agent_runtime_journey_invalid", "evidence",
      "Agent Runtime identity or two-session closure is incomplete");
  }
  const materials = journey.materials;
  const legacyProjection = evidenceSchema === LEGACY_AGENT_RUNTIME_EVIDENCE_SCHEMA;
  Common.exactKeys(materials, ["archiveOrder", "visualVerified", "keyboardJourneyVerified",
    "candidateViewport", "responsiveThreeViewportGateBound", "multiVariant", "portraits",
    ...(legacyProjection ? [] : ["recipeJump"])],
  "material_shop_materials_evidence_invalid", "evidence");
  Common.exactKeys(materials.multiVariant, ["enemyType", "occurrenceIndices", "allVisible"],
    "material_shop_multi_variant_invalid", "evidence");
  const legacyPortraitProjection = legacyProjection;
  Common.exactKeys(materials.portraits, legacyPortraitProjection
    ? ["enemyResolved", "shopResolved", "fallbackHarnessBound", "identityLeak"]
    : ["capturePresent", "resolutionStatus", "independentReviewRequired"],
  "material_shop_portrait_evidence_invalid", "evidence");
  const portraitsValid = legacyPortraitProjection
    ? materials.portraits.enemyResolved === true
      && materials.portraits.shopResolved === true
      && materials.portraits.fallbackHarnessBound === true
      && materials.portraits.identityLeak === false
    : materials.portraits.capturePresent === true
      && materials.portraits.resolutionStatus === PORTRAIT_REVIEW_PENDING
      && materials.portraits.independentReviewRequired === true;
  let recipeJumpValid = legacyProjection;
  if (!legacyProjection) {
    Common.exactKeys(materials.recipeJump, ["materialName", "category", "recipeIndex",
      "productName", "keyboardSequenceSha256", "visibleCaptureSha256",
      "keySequenceVerified", "escapeCloseOutcome"],
    "material_shop_recipe_jump_evidence_invalid", "evidence");
    const recipe = plan.recipeJump;
    validateAgentRuntimeCloseOutcome(materials.recipeJump.escapeCloseOutcome, {
      closeStepId: "recipe_escape_close", closeRole: "recipe_close_with_escape",
      closeMethod: "input.press_key", successorStepId: "recipe_reopen_materials",
    });
    recipeJumpValid = materials.recipeJump.materialName === recipe.materialName
      && materials.recipeJump.category === recipe.category
      && materials.recipeJump.recipeIndex === recipe.recipeIndex
      && materials.recipeJump.productName === recipe.productName
      && Common.SHA256_RE.test(String(materials.recipeJump.keyboardSequenceSha256 || ""))
      && Common.SHA256_RE.test(String(materials.recipeJump.visibleCaptureSha256 || ""))
      && materials.recipeJump.keySequenceVerified === true;
  }
  if (materials.archiveOrder !== "authored_xml" || materials.visualVerified !== true
      || materials.keyboardJourneyVerified !== true
      || materials.candidateViewport !== "current_window"
      || materials.responsiveThreeViewportGateBound !== true
      || !exactString(materials.multiVariant.enemyType, 128)
      || !Array.isArray(materials.multiVariant.occurrenceIndices)
      || materials.multiVariant.occurrenceIndices.length < 2
      || materials.multiVariant.occurrenceIndices.some((entry, index) => entry !== index)
      || materials.multiVariant.allVisible !== true || !portraitsValid || !recipeJumpValid) {
    Common.fail("material_shop_materials_evidence_invalid", "evidence",
      "Agent Runtime material evidence or pending portrait-review boundary is incomplete");
  }
  const routes = journey.routes;
  Common.exactKeys(routes, ["locked", "ordinaryClose", "unlocked", "max"],
    "material_shop_route_evidence_invalid", "evidence");
  validateOptionalBlockedRoute(routes.locked, "locked", plan.applicability.locked);
  validateOptionalBlockedRoute(routes.max, "max", plan.applicability.max);
  [routes.locked, routes.max].forEach((route) => {
    if (route.status === "not_applicable_current_data"
        && route.applicabilitySha256 !== plan.applicability.applicabilitySha256) {
      Common.fail("material_shop_route_na_invalid", "evidence",
        "not-applicable Agent Runtime route is detached from plan applicability");
    }
  });
  Common.exactKeys(routes.ordinaryClose, ["target", "forwardCommitted",
    "ordinaryCloseCommitted", ...(legacyProjection ? [] : ["closeOutcome"])],
  "material_shop_ordinary_close_invalid", "evidence");
  validateTarget(routes.ordinaryClose.target, "ordinary_close");
  if (!legacyProjection) {
    validateAgentRuntimeCloseOutcome(routes.ordinaryClose.closeOutcome, {
      closeStepId: "ordinary_close", closeRole: "npcshop_close",
      closeMethod: "input.click", successorStepId: "reopen_materials",
    });
  }
  if (routes.ordinaryClose.forwardCommitted !== true
      || routes.ordinaryClose.ordinaryCloseCommitted !== true) {
    Common.fail("material_shop_ordinary_close_invalid", "evidence",
      "Agent Runtime ordinary-close visible route is incomplete");
  }
  Common.exactKeys(routes.unlocked, ["target", "forwardCommitted", "locatedExact",
    "navigationFocus", "quantity", "saleCount", "settlementProjectionCount",
    "commitDispatchCount", "settled", "returnCommitted", "settlement"],
  "material_shop_unlocked_route_invalid", "evidence");
  Common.exactKeys(routes.unlocked.settlement, ["baselineBalance", "unitPrice", "buyTotal",
    "projectedBalance", "beforeOwned", "afterOwned"],
  "material_shop_unlocked_settlement_invalid", "evidence");
  validateTarget(routes.unlocked.target, "unlocked");
  const settlement = routes.unlocked.settlement;
  if (routes.unlocked.forwardCommitted !== true || routes.unlocked.locatedExact !== true
      || routes.unlocked.navigationFocus !== "data-navigation-focus"
      || routes.unlocked.quantity !== 1 || routes.unlocked.saleCount !== 0
      || routes.unlocked.settlementProjectionCount !== 1
      || routes.unlocked.commitDispatchCount !== 1
      || routes.unlocked.settled !== true || routes.unlocked.returnCommitted !== true
      || !Number.isFinite(settlement.baselineBalance)
      || !Number.isFinite(settlement.unitPrice) || settlement.unitPrice < 0
      || settlement.buyTotal !== settlement.unitPrice
      || settlement.projectedBalance !== settlement.baselineBalance - settlement.buyTotal
      || settlement.beforeOwned !== 0 || settlement.afterOwned !== 1) {
    Common.fail("material_shop_unlocked_route_invalid", "evidence",
      "Agent Runtime authority projection does not prove one exact zero-sale purchase");
  }
  const persistence = journey.persistence;
  Common.exactKeys(persistence, ["trustedPersistenceShutdown", "trustedFinalShutdown",
    "seedReadOnly", "targetIsolated", "recoveryAvailable", "restartFreshProcess",
    "restartReadbackEqual", "baselineMoney", "settledMoney", "beforeOwned",
    "archiveOwned", "restartOwned", "archiveSha256", "restartSha256",
    "archiveSemanticSha256", "restartSemanticSha256"],
  "material_shop_persistence_invalid", "evidence");
  if ([persistence.trustedPersistenceShutdown, persistence.trustedFinalShutdown,
    persistence.seedReadOnly, persistence.targetIsolated, persistence.recoveryAvailable,
    persistence.restartFreshProcess, persistence.restartReadbackEqual]
    .some((entry) => entry !== true)
      || persistence.baselineMoney !== settlement.baselineBalance
      || persistence.settledMoney !== settlement.projectedBalance
      || persistence.beforeOwned !== 0 || persistence.archiveOwned !== 1
      || persistence.restartOwned !== 1
      || !Common.SHA256_RE.test(String(persistence.archiveSha256 || ""))
      || !Common.SHA256_RE.test(String(persistence.restartSha256 || ""))
      || !Common.SHA256_RE.test(String(persistence.archiveSemanticSha256 || ""))
      || persistence.restartSemanticSha256 !== persistence.archiveSemanticSha256) {
    Common.fail("material_shop_persistence_invalid", "evidence",
      "trusted runner exact-byte seals and semantic restart closure are incomplete");
  }
  Common.exactKeys(journey.authorityCounts, ["settlementProjection", "commitDispatch", "sale"],
    "material_shop_authority_counts_invalid", "evidence");
  if (journey.authorityCounts.settlementProjection !== 1
      || journey.authorityCounts.commitDispatch !== 1 || journey.authorityCounts.sale !== 0) {
    Common.fail("material_shop_authority_counts_invalid", "evidence",
      "Agent Runtime authority counts differ from the exact settlement projection");
  }
  return journey;
}

function createAgentRuntimeJourneyEvidence(options) {
  const settings = options || {};
  const plan = validateAgentRuntimeControlPlan(settings.plan);
  const value = { schema: agentRuntimeEvidenceSchemaForPlan(plan), runId: plan.runId,
    evidenceMode: plan.evidenceMode, planSha256: plan.planSha256, scope: plan.scope,
    controls: settings.controls, journey: settings.journey,
    result: RESULT_BY_MODE[plan.evidenceMode], boundaries: settings.boundaries };
  value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(stableEvidence(value)));
  return validateAgentRuntimeJourneyEvidence(value, plan);
}

function validateAgentRuntimeJourneyEvidence(value, plan) {
  validateAgentRuntimeControlPlan(plan);
  if (plan.transportPolicy.liveAdmission === "blocked_route_seed_probe_required") {
    Common.fail("material_shop_route_seed_probe_required", "evidence",
      "candidate evidence is forbidden until locked/max applicability is seed-resolved");
  }
  Common.exactKeys(value, ["schema", "runId", "evidenceMode", "planSha256", "scope",
    "controls", "journey", "result", "boundaries", "evidenceSha256"],
  "material_shop_journey_evidence_invalid", "evidence");
  const legacyV6 = value.schema === LEGACY_AGENT_RUNTIME_EVIDENCE_SCHEMA;
  const currentV9 = value.schema === AGENT_RUNTIME_EVIDENCE_SCHEMA;
  if (!legacyV6 && !currentV9) {
    Common.fail("material_shop_journey_evidence_invalid", "evidence",
      "Agent Runtime journey evidence schema is unsupported");
  }
  if (legacyV6 && (value.runId !== LEGACY_AGENT_RUNTIME_V6_RUN_ID
      || plan.runId !== LEGACY_AGENT_RUNTIME_V6_RUN_ID
      || plan.planSha256 !== LEGACY_AGENT_RUNTIME_V6_PLAN_SHA256
      || value.evidenceSha256 !== LEGACY_AGENT_RUNTIME_V6_EVIDENCE_SHA256)) {
    Common.fail("material_shop_legacy_agent_evidence_identity_invalid", "evidence",
      "legacy Agent Runtime v6 is readable only for the exact frozen t1903 evidence");
  }
  if (currentV9 && value.runId === LEGACY_AGENT_RUNTIME_V6_RUN_ID) {
    Common.fail("material_shop_legacy_agent_evidence_identity_invalid", "evidence",
      "the frozen t1903 identity cannot be re-signed as current Agent Runtime evidence");
  }
  if (value.runId !== plan.runId
      || value.evidenceMode !== "candidate_capture" || value.planSha256 !== plan.planSha256
      || value.result !== RESULT_BY_MODE.candidate_capture
      || value.evidenceSha256 !== Evidence.sha256Text(Evidence.canonicalJson(stableEvidence(value)))
      || Evidence.canonicalJson(value.scope) !== Evidence.canonicalJson(plan.scope)) {
    Common.fail("material_shop_journey_evidence_invalid", "evidence",
      "Agent Runtime journey evidence is malformed or detached");
  }
  Common.exactKeys(value.controls, ["completedSteps", "provider", "transport",
    "authorizationDecisionId", "controllerBusinessApiCalls", "sessionCount",
    "visibleCaptureCount", ...(legacyV6 ? [] : ["actionIntentCount",
      "keyboardActionIntentCount", "keyboardSequenceSha256"])],
  "material_shop_control_evidence_invalid", "evidence");
  if (Evidence.canonicalJson(value.controls.completedSteps)
      !== Evidence.canonicalJson(plan.steps.map((step) => step.id))
      || value.controls.provider !== AGENT_RUNTIME_PROVIDER
      || value.controls.transport !== AGENT_RUNTIME_TRANSPORT
      || value.controls.authorizationDecisionId !== plan.authorization.decisionId
      || value.controls.controllerBusinessApiCalls !== 0
      || value.controls.sessionCount !== 2
      || !Number.isInteger(value.controls.visibleCaptureCount)
      || value.controls.visibleCaptureCount < 1
      || !legacyV6 && (!Number.isInteger(value.controls.actionIntentCount)
        || value.controls.actionIntentCount < 1
        || value.controls.keyboardActionIntentCount
          !== AGENT_RUNTIME_RECIPE_JUMP.keyboardActions.length
        || !Common.SHA256_RE.test(String(value.controls.keyboardSequenceSha256 || "")))) {
    Common.fail("material_shop_control_evidence_invalid", "evidence",
      "Agent Runtime controller evidence is incomplete or crossed its boundary");
  }
  validateAgentRuntimeJourney(value.journey, plan, value.schema);
  Common.exactKeys(value.boundaries, ["realGuiExecuted", "candidateBuilt", "candidateExecuted",
    "e2eVerified", "promoted", "standardEntryVerified"],
  "material_shop_evidence_boundary_invalid", "evidence");
  if (value.boundaries.realGuiExecuted !== true || value.boundaries.candidateBuilt !== true
      || value.boundaries.candidateExecuted !== true || value.boundaries.e2eVerified !== false
      || value.boundaries.promoted !== false || value.boundaries.standardEntryVerified !== false) {
    Common.fail("material_shop_candidate_claim_invalid", "evidence",
      "Agent Runtime raw capture has exact non-release evidence boundaries");
  }
  return value;
}

function validateJourneyEvidence(value, plan) {
  if (value && [AGENT_RUNTIME_EVIDENCE_SCHEMA,
      LEGACY_AGENT_RUNTIME_EVIDENCE_SCHEMA].includes(value.schema)) {
    return validateAgentRuntimeJourneyEvidence(value, plan);
  }
  validateControlPlan(plan);
  if (plan.transportPolicy.liveAdmission === "blocked_route_seed_probe_required") {
    Common.fail("material_shop_route_seed_probe_required", "evidence",
      "candidate evidence is forbidden until locked/max applicability is seed-resolved");
  }
  Common.exactKeys(value, ["schema", "runId", "evidenceMode", "planSha256", "scope",
    "controls", "journey", "result", "boundaries", "evidenceSha256"],
  "material_shop_journey_evidence_invalid", "evidence");
  if (value.schema !== EVIDENCE_SCHEMA || value.runId !== plan.runId
      || value.evidenceMode !== plan.evidenceMode || value.planSha256 !== plan.planSha256
      || value.result !== RESULT_BY_MODE[value.evidenceMode]
      || value.evidenceSha256 !== Evidence.sha256Text(Evidence.canonicalJson(stableEvidence(value)))
      || Evidence.canonicalJson(value.scope) !== Evidence.canonicalJson(plan.scope)) {
    Common.fail("material_shop_journey_evidence_invalid", "evidence",
      "journey evidence is malformed or detached from its plan/current tree");
  }
  Common.exactKeys(value.controls, ["completedSteps", "transports", "authorizationDecisionId",
    "controllerBusinessApiCalls"], "material_shop_control_evidence_invalid", "evidence");
  if (Evidence.canonicalJson(value.controls.completedSteps)
      !== Evidence.canonicalJson(plan.steps.map((step) => step.id))
      || !Array.isArray(value.controls.transports)
      || value.controls.transports.some((entry) => ![PREFERRED_TRANSPORT,
        FALLBACK_TRANSPORT, RUNNER_TRANSPORT].includes(entry))
      || value.controls.authorizationDecisionId !== plan.authorization.decisionId
      || value.controls.controllerBusinessApiCalls !== 0) {
    Common.fail("material_shop_control_evidence_invalid", "evidence",
      "controller trace is incomplete or crossed a business API boundary");
  }
  validateJourney(value.journey, plan);
  Common.exactKeys(value.boundaries, ["realGuiExecuted", "candidateBuilt", "candidateExecuted",
    "e2eVerified", "promoted", "standardEntryVerified"],
  "material_shop_evidence_boundary_invalid", "evidence");
  if (value.evidenceMode === "offline_fixture"
      && Object.values(value.boundaries).some((flag) => flag !== false)) {
    Common.fail("material_shop_offline_claim_invalid", "evidence",
      "offline fixtures cannot claim GUI/candidate/E2E/release execution");
  }
  if (value.evidenceMode === "candidate_capture"
      && (value.boundaries.realGuiExecuted !== true || value.boundaries.candidateBuilt !== true
        || value.boundaries.candidateExecuted !== true || value.boundaries.e2eVerified !== false
        || value.boundaries.promoted !== false || value.boundaries.standardEntryVerified !== false)) {
    Common.fail("material_shop_candidate_claim_invalid", "evidence",
      "raw candidate capture has exact non-release evidence boundaries");
  }
  return value;
}

module.exports = {
  AGENT_RUNTIME_BASE_STEPS,
  AGENT_RUNTIME_AUTHORIZATION_SCHEMA,
  AGENT_RUNTIME_CANDIDATE_LEAF,
  AGENT_RUNTIME_EVIDENCE_SCHEMA,
  AGENT_RUNTIME_RECIPE_JUMP,
  LEGACY_AGENT_RUNTIME_EVIDENCE_SCHEMA,
  LEGACY_AGENT_RUNTIME_PLAN_SCHEMA,
  LEGACY_AGENT_RUNTIME_V6_RUN_ID,
  LEGACY_AGENT_RUNTIME_V6_PLAN_SHA256,
  LEGACY_AGENT_RUNTIME_V6_EVIDENCE_SHA256,
  PORTRAIT_REVIEW_PENDING,
  AGENT_RUNTIME_PLAN_SCHEMA,
  AGENT_RUNTIME_PROVIDER,
  AGENT_RUNTIME_RPC_METHODS,
  AGENT_RUNTIME_SLOT,
  AGENT_RUNTIME_TRANSPORT,
  AUTHORIZATION_SCHEMA,
  BASE_STEPS,
  CAPTURE_STEPS,
  CLOSE_REASONS,
  EVIDENCE_MODES,
  EVIDENCE_SCHEMA,
  FALLBACK_METHODS,
  FALLBACK_TRANSPORT,
  FORBIDDEN_CONTROLLER_SURFACES,
  KEYBOARD_STEPS,
  LOCKED_STEPS,
  MAX_STEPS,
  NATIVE_STEPS,
  PLAN_SCHEMA,
  PREFERRED_TRANSPORT,
  RESULT_BY_MODE,
  RUNNER_STEPS,
  RUNNER_TRANSPORT,
  assertNoControllerApi,
  agentRuntimeEvidenceSchemaForPlan,
  agentRuntimePortraitReviewBoundary,
  createAgentRuntimeControlPlan,
  createAgentRuntimeAuthorization,
  createAgentRuntimePortraitEvidence,
  createAgentRuntimeJourneyEvidence,
  createAuthorization,
  createControlPlan,
  createJourneyEvidence,
  requiredSteps,
  requiredAgentRuntimeSteps,
  stableEvidence,
  stablePlan,
  transportClass,
  validateAuthorization,
  validateAgentRuntimeAuthorization,
  validateAgentRuntimeControlPlan,
  validateAgentRuntimeJourney,
  validateAgentRuntimeJourneyEvidence,
  validateControlPlan,
  validateJourney,
  validateJourneyEvidence,
};
