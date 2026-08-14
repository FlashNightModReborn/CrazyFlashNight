#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const Applicability = require("./applicability");
const Build = require("./build-candidate");
const Capture = require("./capture-verifier");
const Common = require("./common");
const FinalizeCloneRelease = require("./finalize-clone-release");
const JourneyVerifier = require("./journey-verifier");
const Materialize = require("./materialize");
const Prepare = require("./prepare");
const Production = require("./production-closure");
const Protocol = require("./protocol");
const VerifyRun = require("./verify-run");

const STATIC_GATE_SCHEMA = "workbench-live-e2e.material-shop.static-gate.v1";
const LEGACY_REVIEW_REQUEST_SCHEMA = "workbench-live-e2e.material-shop.review-request.v3";
const REVIEW_REQUEST_SCHEMA = "workbench-live-e2e.material-shop.review-request.v4";
const REVIEW_RECEIPT_SCHEMA = "workbench-live-e2e.material-shop.review-receipt.v1";
const ACCEPTANCE_SCHEMA = "workbench-live-e2e.material-shop.acceptance.v3";
const LEGACY_REVIEW_SCOPE = "visible_png_content_only_not_input_or_capture_provenance";
const AGENT_RUNTIME_REVIEW_SCOPE =
  "visible_png_content_only_not_runtime_interaction_or_capture_provenance";

const CLAIMS = Object.freeze([
  { claimId: "native_materials_open", steps: ["open_materials"] },
  { claimId: "materials_current_window_layout", steps: ["materials_visual_current_window"] },
  { claimId: "materials_keyboard_focus", steps: ["materials_keyboard"] },
  { claimId: "all_enemy_drop_occurrences_visible", steps: ["materials_multi_variant"] },
  { claimId: "reachable_enemy_and_shop_portraits_visible", steps: ["materials_portraits"] },
  { claimId: "ordinary_outer_close_returns_to_game", steps: ["ordinary_close"] },
  { claimId: "exact_catalog_navigation_focus", steps: ["unlocked_exact_focus"] },
  { claimId: "quantity_one_zero_sale_settlement", steps: ["unlocked_settlement"] },
  { claimId: "native_safeexit_completion", steps: ["safeexit"] },
  { claimId: "fresh_restart_purchase_readback", steps: ["restart_readback"] },
]);

const LEGACY_AGENT_RUNTIME_CLAIMS = Object.freeze([
  { claimId: "materials_archive_layout_visible",
    steps: ["open_materials", "materials_visual_current_window"] },
  { claimId: "materials_search_result_visible", steps: ["materials_keyboard"] },
  { claimId: "all_enemy_drop_occurrences_visible", steps: ["materials_multi_variant"] },
  { claimId: "reachable_enemy_and_shop_portraits_visible", steps: ["materials_portraits"] },
  { claimId: "chef_shop_catalog_destination_visible", steps: ["ordinary_close"] },
  { claimId: "materials_archive_catalog_and_sources_visible", steps: ["reopen_materials"] },
  { claimId: "chef_shop_food_oil_card_visible", steps: ["unlocked_exact_focus"] },
  { claimId: "chef_shop_food_oil_cart_quantity_one_visible",
    steps: ["unlocked_intent_qty1"] },
  { claimId: "chef_shop_food_oil_zero_sale_settlement_visible",
    steps: ["unlocked_settlement"] },
  { claimId: "chef_shop_balance_2402769_visible", steps: ["unlocked_return"] },
  { claimId: "materials_archive_owned_species_129_visible",
    steps: ["restart_open_materials"] },
  { claimId: "food_oil_owned_one_and_recipe_usage_visible", steps: ["restart_readback"] },
]);
const AGENT_RUNTIME_CLAIMS = Object.freeze([
  { claimId: "materials_archive_layout_visible",
    steps: ["open_materials", "materials_visual_current_window"] },
  { claimId: "military_canvas_default_archive_detail_visible", steps: ["materials_keyboard"] },
  { claimId: "exact_military_canvas_recipe_destination_visible",
    steps: ["materials_recipe_jump", "recipe_escape_close"] },
  { claimId: "materials_archive_second_view_visible", steps: ["recipe_reopen_materials"] },
  { claimId: "all_enemy_drop_occurrences_visible", steps: ["materials_multi_variant"] },
  { claimId: "reachable_enemy_and_shop_portraits_visible", steps: ["materials_portraits"] },
  { claimId: "chef_shop_catalog_destination_visible", steps: ["ordinary_close"] },
  { claimId: "materials_archive_catalog_and_sources_visible", steps: ["reopen_materials"] },
  { claimId: "chef_shop_food_oil_card_visible", steps: ["unlocked_exact_focus"] },
  { claimId: "chef_shop_food_oil_cart_quantity_one_visible",
    steps: ["unlocked_intent_qty1"] },
  { claimId: "chef_shop_food_oil_zero_sale_settlement_visible",
    steps: ["unlocked_settlement"] },
  { claimId: "chef_shop_balance_2402769_visible", steps: ["unlocked_return"] },
  { claimId: "materials_archive_owned_species_129_visible",
    steps: ["restart_open_materials"] },
  { claimId: "food_oil_owned_one_and_recipe_usage_visible", steps: ["restart_readback"] },
]);

function writeJsonNew(filePath, value) {
  fs.writeFileSync(path.resolve(filePath), JSON.stringify(value, null, 2) + "\n", {
    encoding: "utf8", mode: 0o600, flag: "wx",
  });
}

function readJson(filePath, phase) {
  return Prepare.readJson(path.resolve(filePath), phase || "material_shop_acceptance");
}

function unsignedDigest(value, digestKey) {
  const unsigned = Object.assign({}, value);
  delete unsigned[digestKey];
  return Evidence.sha256Text(Evidence.canonicalJson(unsigned));
}

function validateCloneRelease(value, context, intent) {
  return FinalizeCloneRelease.validateReleaseReceipt(value, context, intent, {
    markerPhase: "final",
    verifyIgnoredOutputInventory: true,
  });
}

function loadContext(options) {
  const preparation = Build.loadPreparation(path.resolve(options.preparation));
  const PostReleaseAdapter = require("./admit-post-release-finalization");
  const bootstrap = PostReleaseAdapter.captureProtectedScopeBootstrap(
    preparation, { optional: true });
  const buildOptions = bootstrap ? { protectedScopeBootstrap: bootstrap } : undefined;
  const closure = VerifyRun.artifact(preparation.runDir, preparation.artifacts.closure);
  const plan = Protocol.validateControlPlan(VerifyRun.artifact(preparation.runDir,
    preparation.artifacts.plan));
  const applicability = Applicability.validateApplicability(VerifyRun.artifact(
    preparation.runDir, preparation.artifacts.applicability));
  const build = Build.loadBuildReceipt(path.resolve(options.build), preparation, closure,
    "acceptance", buildOptions);
  if (build.liveAdmission !== plan.transportPolicy.liveAdmission
      || build.liveAdmission !== "candidate_ui_probe_required") {
    Common.fail("material_shop_acceptance_live_admission_invalid", "acceptance",
      "acceptance requires a build whose candidate UI admission remained required");
  }
  const raw = VerifyRun.readRawCandidateJourney(options.raw, "acceptance");
  const verified = JourneyVerifier.verifyRawCandidateJourney(raw, plan, applicability,
    preparation.runDir, build);
  const operationTerminal = JourneyVerifier.verifyOperationTerminal(raw,
    preparation.runDir, build);
  const storedEvidence = readJson(options.evidence, "acceptance");
  if (Evidence.canonicalJson(storedEvidence) !== Evidence.canonicalJson(verified.evidence)) {
    Common.fail("material_shop_acceptance_evidence_drift", "acceptance",
      "stored candidate evidence differs from strict raw replay");
  }
  const context = { preparation, closure, plan, applicability, build, raw,
    evidence: storedEvidence, operationTerminal };
  const intent = FinalizeCloneRelease.validateIntent(readJson(path.join(preparation.runDir,
    "clone-release-intent.json"), "acceptance"), context);
  const release = validateCloneRelease(readJson(options.release, "acceptance"), context,
    intent);
  const blockerFiles = FinalizeCloneRelease.unresolvedBlockerFiles(
    preparation.runDir, context, release.markerEvidence);
  if (blockerFiles.length !== 0) {
    Common.fail("material_shop_release_finalization_incomplete", "acceptance",
      "candidate acceptance requires zero unbound recovery/finalization blockers", {
        blockerFiles,
      });
  }
  return Object.assign(context, { intent, release });
}

function validateCraftingBrowserReceipt(receipt) {
  Common.exactKeys(receipt, ["schema", "status", "moduleAdmission", "journalVerification",
    "manifestSha256", "moduleJournalSha256", "moduleEntryCount", "browserBinary",
    "servedResourceClosure", "result", "evidenceSha256"],
  "material_shop_static_gate_receipt_invalid", "static_gate");
  Common.exactKeys(receipt.result, ["viewports", "scenarioCounts",
    "materialShopScenarioCount", "materialShopScenarioNamesSha256",
    "scenarioNamesSha256", "faultChecks", "resultSha256"],
  "material_shop_static_gate_receipt_invalid", "static_gate");
  const expectedViewports = [
    { width: 1024, height: 576 },
    { width: 1366, height: 768 },
    { width: 1920, height: 1080 },
  ];
  if (receipt.schema !== "workbench-live-e2e.crafting.browser-gate-receipt.v1"
      || receipt.status !== "OFFLINE_VERIFIED" || receipt.moduleAdmission !== "ADMITTED"
      || receipt.journalVerification !== "VERIFIED"
      || !Common.SHA256_RE.test(String(receipt.manifestSha256 || ""))
      || !Common.SHA256_RE.test(String(receipt.moduleJournalSha256 || ""))
      || !Number.isInteger(receipt.moduleEntryCount) || receipt.moduleEntryCount < 1
      || !receipt.browserBinary || !String(receipt.browserBinary.locator || "").startsWith("external:")
      || !Common.SHA256_RE.test(String(receipt.browserBinary.sha256 || ""))
      || !Number.isInteger(receipt.browserBinary.bytes) || receipt.browserBinary.bytes < 1
      || !receipt.servedResourceClosure
      || !Common.SHA256_RE.test(String(receipt.servedResourceClosure.evidenceSha256 || ""))
      || !Number.isInteger(receipt.servedResourceClosure.requiredResourceCount)
      || receipt.servedResourceClosure.requiredResourceCount < 1
      || receipt.servedResourceClosure.failureCount !== 4
      || receipt.evidenceSha256 !== unsignedDigest(receipt, "evidenceSha256")
      || Evidence.canonicalJson(receipt.result.viewports)
        !== Evidence.canonicalJson(expectedViewports)
      || Evidence.canonicalJson(receipt.result.scenarioCounts)
        !== Evidence.canonicalJson({ baseline: 150, coverage: 15, fault: 8, identity: 10 })
      || receipt.result.materialShopScenarioCount !== 11
      || !Array.isArray(receipt.result.materialShopScenarioNamesSha256)
      || receipt.result.materialShopScenarioNamesSha256.length !== 3
      || new Set(receipt.result.materialShopScenarioNamesSha256).size !== 1
      || receipt.result.materialShopScenarioNamesSha256.some((digest) =>
        !Common.SHA256_RE.test(String(digest || "")))
      || !receipt.result.scenarioNamesSha256
      || Evidence.canonicalJson(Object.keys(receipt.result.scenarioNamesSha256).sort())
        !== Evidence.canonicalJson(["baseline", "coverage", "fault", "identity"])
      || Object.values(receipt.result.scenarioNamesSha256).some((digest) =>
        !Common.SHA256_RE.test(String(digest || "")))
      || !Common.SHA256_RE.test(String(receipt.result.resultSha256 || ""))
      || !Array.isArray(receipt.result.faultChecks) || receipt.result.faultChecks.length !== 8
      || receipt.result.faultChecks.some((entry) => entry.ok !== true)) {
    Common.fail("material_shop_static_gate_receipt_invalid", "static_gate",
      "crafting three-viewport/material-shop/fallback browser gate is incomplete");
  }
  return receipt;
}

function validateStaticGate(value, context) {
  Common.exactKeys(value, ["schema", "executedAt", "preparationSha256",
    "closureSha256", "materializationSha256", "materializedProducerBinding", "command",
    "receipt", "staticGateSha256"],
  "material_shop_static_gate_invalid", "static_gate");
  Common.exactKeys(value.command, ["executable", "script", "scriptSha256", "cwd",
    "exitCode", "stderrSha256"], "material_shop_static_gate_invalid", "static_gate");
  const expectedScript = path.join(context.preparation.resourcesRoot, "tools",
    "workbench-live-e2e", "crafting", "browser-bootstrap.js");
  const script = Evidence.readExactRegularFile(expectedScript, {
    phase: "static_gate", maximumBytes: 4 * 1024 * 1024,
  });
  Production.verifyMaterializedSharedProducers(value.materializedProducerBinding,
    context.preparation.resourcesRoot, context.closure);
  if (value.schema !== STATIC_GATE_SCHEMA || !Number.isFinite(Date.parse(value.executedAt))
      || value.preparationSha256 !== context.preparation.preparationSha256
      || value.closureSha256 !== context.closure.closureSha256
      || value.materializationSha256 !== context.preparation.materializationSha256
      || path.resolve(value.command.script) !== path.resolve(expectedScript)
      || value.command.scriptSha256 !== script.sha256
      || path.resolve(value.command.cwd) !== path.resolve(context.preparation.resourcesRoot)
      || value.command.exitCode !== 0 || !Common.SHA256_RE.test(value.command.stderrSha256)
      || value.staticGateSha256 !== unsignedDigest(value, "staticGateSha256")) {
    Common.fail("material_shop_static_gate_invalid", "static_gate",
      "static browser gate is detached from the exact materialized candidate source");
  }
  validateCraftingBrowserReceipt(value.receipt);
  return value;
}

function staticGateToolchainProjection(context) {
  const canonicalRoot = path.resolve(context.build.externalToolchain.canonicalRoot);
  const resourcesRoot = path.resolve(context.preparation.resourcesRoot);
  const inventoryPath = path.join(resourcesRoot, "tools", "workbench-live-e2e",
    "crafting", "browser-module-inventory.v1.json");
  const inventory = readJson(inventoryPath, "static_gate_toolchain");
  const prefix = "launcher/perf/node_modules/";
  const files = inventory && Array.isArray(inventory.files)
    ? inventory.files.filter((relative) => relative.startsWith(prefix)) : [];
  const sorted = files.slice().sort();
  if (!inventory
      || inventory.schema !== "workbench-live-e2e.crafting.browser-module-inventory.v1"
      || inventory.nodeVersion !== process.version
      || files.length < 1 || new Set(files).size !== files.length
      || Evidence.canonicalJson(files) !== Evidence.canonicalJson(sorted)
      || files.some((relative) => !/^launcher\/perf\/node_modules\/(?:playwright|playwright-core)\//
        .test(relative))) {
    Common.fail("material_shop_static_toolchain_inventory_invalid", "static_gate",
      "browser module inventory does not define an exact Playwright projection");
  }
  const destinationRoot = path.join(resourcesRoot, "launcher", "perf", "node_modules");
  if (!Evidence.pathInside(resourcesRoot, destinationRoot)) {
    Common.fail("material_shop_static_toolchain_path_invalid", "static_gate",
      "temporary Playwright projection escaped the materialized resources root");
  }
  const verifierFixtureRelative = "launcher/web/modules/crafting/dev/harness.html";
  const browserInventoryPath = path.join(resourcesRoot, "tools", "workbench-live-e2e",
    "crafting", "browser-resource-inventory.v1.json");
  const browserInventory = readJson(browserInventoryPath, "static_gate_fixture");
  if (!browserInventory
      || browserInventory.schema !== "workbench-live-e2e.browser-resource-inventory.v1"
      || !Array.isArray(browserInventory.files)
      || browserInventory.files.filter((relative) =>
        relative === "modules/crafting/dev/harness.html").length !== 1) {
    Common.fail("material_shop_static_fixture_inventory_invalid", "static_gate",
      "browser inventory does not bind the exact crafting verifier fixture");
  }
  const verifierFixture = {
    relative: verifierFixtureRelative,
    source: path.join(canonicalRoot, verifierFixtureRelative.replace(/\//g, path.sep)),
    destination: path.join(resourcesRoot, verifierFixtureRelative.replace(/\//g, path.sep)),
  };
  if (!Evidence.pathInside(canonicalRoot, verifierFixture.source)
      || !Evidence.pathInside(resourcesRoot, verifierFixture.destination)) {
    Common.fail("material_shop_static_fixture_path_invalid", "static_gate",
      "temporary verifier fixture projection escaped an owned root");
  }
  return { canonicalRoot, resourcesRoot, destinationRoot, files, verifierFixture };
}

function withStaticGateToolchainProjection(context, callback) {
  if (typeof callback !== "function") {
    Common.fail("material_shop_static_toolchain_callback_invalid", "static_gate",
      "static toolchain projection requires one synchronous gate callback");
  }
  const projection = staticGateToolchainProjection(context);
  if (projection.canonicalRoot === projection.resourcesRoot) return callback();
  if (fs.existsSync(projection.destinationRoot)) {
    Common.fail("material_shop_static_toolchain_destination_present", "static_gate",
      "materialized node_modules must be absent before the transient static gate projection");
  }
  let created = false;
  let fixtureChanged = false;
  let originalFixture = null;
  try {
    const sourceFixture = Evidence.readExactRegularFile(projection.verifierFixture.source, {
      phase: "static_gate_fixture", maximumBytes: 4 * 1024 * 1024,
    });
    originalFixture = Evidence.readExactRegularFile(projection.verifierFixture.destination, {
      phase: "static_gate_fixture", maximumBytes: 4 * 1024 * 1024,
    });
    fixtureChanged = sourceFixture.sha256 !== originalFixture.sha256;
    if (fixtureChanged) {
      fs.writeFileSync(projection.verifierFixture.destination, sourceFixture.bytes, { flag: "w" });
      const projectedFixture = Evidence.readExactRegularFile(
        projection.verifierFixture.destination, {
          phase: "static_gate_fixture", maximumBytes: 4 * 1024 * 1024,
        });
      if (projectedFixture.length !== sourceFixture.length
          || projectedFixture.sha256 !== sourceFixture.sha256) {
        Common.fail("material_shop_static_fixture_copy_invalid", "static_gate",
          "transient crafting verifier fixture differs from its canonical source");
      }
    }
    fs.mkdirSync(projection.destinationRoot, { recursive: false });
    created = true;
    for (const relative of projection.files) {
      const source = path.join(projection.canonicalRoot, relative.replace(/\//g, path.sep));
      const destination = path.join(projection.resourcesRoot,
        relative.replace(/\//g, path.sep));
      const sourceFile = Evidence.readExactRegularFile(source, {
        phase: "static_gate_toolchain", maximumBytes: 32 * 1024 * 1024,
      });
      fs.mkdirSync(path.dirname(destination), { recursive: true });
      fs.copyFileSync(source, destination, fs.constants.COPYFILE_EXCL);
      const projectedFile = Evidence.readExactRegularFile(destination, {
        phase: "static_gate_toolchain", maximumBytes: 32 * 1024 * 1024,
      });
      if (projectedFile.length !== sourceFile.length
          || projectedFile.sha256 !== sourceFile.sha256) {
        Common.fail("material_shop_static_toolchain_copy_invalid", "static_gate",
          "transient Playwright projection differs from its sealed canonical source", {
            relative,
          });
      }
    }
    return callback();
  } finally {
    if (fixtureChanged && originalFixture) {
      const fixtureStat = fs.lstatSync(projection.verifierFixture.destination);
      if (!fixtureStat.isFile() || fixtureStat.isSymbolicLink()
          || path.resolve(fs.realpathSync.native(projection.verifierFixture.destination))
            !== path.resolve(projection.verifierFixture.destination)) {
        Common.fail("material_shop_static_fixture_cleanup_invalid", "static_gate",
          "refusing to restore a non-regular crafting verifier fixture");
      }
      fs.writeFileSync(projection.verifierFixture.destination, originalFixture.bytes, { flag: "w" });
      const restoredFixture = Evidence.readExactRegularFile(
        projection.verifierFixture.destination, {
          phase: "static_gate_fixture", maximumBytes: 4 * 1024 * 1024,
        });
      if (restoredFixture.length !== originalFixture.length
          || restoredFixture.sha256 !== originalFixture.sha256) {
        Common.fail("material_shop_static_fixture_cleanup_invalid", "static_gate",
          "crafting verifier fixture was not restored byte-for-byte");
      }
    }
    if (created && fs.existsSync(projection.destinationRoot)) {
      const stat = fs.lstatSync(projection.destinationRoot);
      if (!stat.isDirectory() || stat.isSymbolicLink()) {
        Common.fail("material_shop_static_toolchain_cleanup_invalid", "static_gate",
          "refusing to recursively remove a non-directory or reparse projection root");
      }
      fs.rmSync(projection.destinationRoot, { recursive: true, force: false });
      if (fs.existsSync(projection.destinationRoot)) {
        Common.fail("material_shop_static_toolchain_cleanup_invalid", "static_gate",
          "transient Playwright projection remained after the static gate");
      }
    }
  }
}

function captureStaticGate(context) {
  const script = path.join(context.preparation.resourcesRoot, "tools",
    "workbench-live-e2e", "crafting", "browser-bootstrap.js");
  const scriptFile = Evidence.readExactRegularFile(script, {
    phase: "static_gate", maximumBytes: 4 * 1024 * 1024,
  });
  const result = withStaticGateToolchainProjection(context, () =>
    childProcess.spawnSync(process.execPath, [script], {
      cwd: context.preparation.resourcesRoot, encoding: "utf8", windowsHide: true,
      timeout: 20 * 60 * 1000, maxBuffer: 128 * 1024 * 1024,
    }));
  if (result.error || result.status !== 0) {
    Common.fail("material_shop_static_gate_failed", "static_gate",
      "candidate-source crafting browser gate failed", { status: result.status,
        stderr: String(result.stderr || result.error && result.error.message || "").slice(-8000) });
  }
  const lines = String(result.stdout || "").split(/\r?\n/).filter(Boolean);
  if (lines.length !== 1) {
    Common.fail("material_shop_static_gate_stdout_invalid", "static_gate",
      "crafting browser gate must emit one receipt document");
  }
  let receipt;
  try { receipt = JSON.parse(lines[0]); }
  catch (error) { Common.fail("material_shop_static_gate_stdout_invalid", "static_gate", error.message); }
  validateCraftingBrowserReceipt(receipt);
  const value = { schema: STATIC_GATE_SCHEMA, executedAt: new Date().toISOString(),
    preparationSha256: context.preparation.preparationSha256,
    closureSha256: context.closure.closureSha256,
    materializationSha256: context.preparation.materializationSha256,
    materializedProducerBinding: Production.captureMaterializedSharedProducers(
      context.preparation.resourcesRoot, context.closure),
    command: { executable: process.execPath, script, scriptSha256: scriptFile.sha256,
      cwd: context.preparation.resourcesRoot, exitCode: result.status,
      stderrSha256: Evidence.sha256Text(String(result.stderr || "")) },
    receipt };
  value.staticGateSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateStaticGate(value, context);
}

function isAgentRuntimePlan(plan) {
  return !!plan && [Protocol.AGENT_RUNTIME_PLAN_SCHEMA,
    Protocol.LEGACY_AGENT_RUNTIME_PLAN_SCHEMA].includes(plan.schema);
}

function isAgentRuntimeContext(context) {
  return !!context && isAgentRuntimePlan(context.plan);
}

function reviewRequestSchema(plan) {
  return isAgentRuntimePlan(plan)
    ? REVIEW_REQUEST_SCHEMA : LEGACY_REVIEW_REQUEST_SCHEMA;
}

function reviewScope(plan) {
  return isAgentRuntimePlan(plan)
    ? AGENT_RUNTIME_REVIEW_SCOPE : LEGACY_REVIEW_SCOPE;
}

function agentRuntimeCaptureInventory(context) {
  const required = context.plan.steps.map((step, ordinal) => ({ step, ordinal }))
    .filter((entry) => entry.step.requiresCapture);
  const requiredByStep = new Map(required.map((entry) => [entry.step.id, entry]));
  const controlsByStep = new Map(context.raw.controls.map((entry) => [entry.stepId, entry]));
  const inventoryByStep = new Map();
  if (!Array.isArray(context.raw.captures)) {
    Common.fail("material_shop_review_capture_set_invalid", "review_request",
      "Agent Runtime review request lacks capture receipts");
  }
  context.raw.captures.forEach((receipt) => {
    Capture.verifyAgentRuntimeCapture(Common.CANONICAL_ROOT, context.preparation.runDir,
      receipt);
    const requiredEntry = requiredByStep.get(receipt.stepId);
    const control = controlsByStep.get(receipt.stepId);
    if (!requiredEntry || inventoryByStep.has(receipt.stepId) || !control
        || !Array.isArray(control.captureRefs)
        || !control.captureRefs.includes(receipt.captureSha256)) {
      Common.fail("material_shop_review_capture_set_invalid", "review_request",
        "Agent Runtime review captures must map one-to-one to capture-required steps", {
          stepId: receipt.stepId,
        });
    }
    inventoryByStep.set(receipt.stepId, {
      ordinal: requiredEntry.ordinal,
      step: receipt.stepId,
      sessionLabel: receipt.sessionLabel,
      observationId: receipt.observationId,
      captureSha256: receipt.captureSha256,
      relativePath: receipt.png.relativePath,
      sha256: receipt.png.sha256,
      bytes: receipt.png.bytes,
      width: receipt.width,
      height: receipt.height,
    });
  });
  if (inventoryByStep.size !== required.length
      || required.some((entry) => !inventoryByStep.has(entry.step.id))) {
    Common.fail("material_shop_review_capture_set_invalid", "review_request",
      "review request lacks one Agent Runtime capture receipt for every required step");
  }
  return required.map((entry) => inventoryByStep.get(entry.step.id));
}

function captureInventory(context) {
  if (isAgentRuntimeContext(context)) return agentRuntimeCaptureInventory(context);
  const captures = [];
  context.plan.steps.forEach((step, ordinal) => {
    if (!step.requiresCapture) return;
    const exchange = context.raw.controls[ordinal];
    const ack = exchange.ack;
    Capture.verifyCapture(Common.CANONICAL_ROOT, context.preparation.runDir,
      ack.captureReceipt);
    captures.push({ ordinal, step: step.id, requestId: exchange.request.requestId,
      transport: ack.transport, providerOperationId: ack.provider.operationId,
      captureReceiptSha256: ack.captureReceipt.captureReceiptSha256,
      relativePath: ack.capture.relativePath, sha256: ack.capture.sha256,
      bytes: ack.capture.bytes, width: ack.captureReceipt.width,
      height: ack.captureReceipt.height });
  });
  if (captures.length !== context.plan.steps.filter((step) => step.requiresCapture).length) {
    Common.fail("material_shop_review_capture_set_invalid", "review_request",
      "review request lacks an exact capture for every capture-required step");
  }
  return captures;
}

function reviewClaims(plan) {
  const steps = Array.isArray(plan && plan.steps) ? plan.steps : [];
  const stepById = new Map(steps.map((step) => [step.id, step]));
  if (isAgentRuntimePlan(plan)) {
    const sourceClaims = plan.schema === Protocol.LEGACY_AGENT_RUNTIME_PLAN_SCHEMA
      ? LEGACY_AGENT_RUNTIME_CLAIMS : AGENT_RUNTIME_CLAIMS;
    const claims = sourceClaims.map((claim) => ({ claimId: claim.claimId,
      captureSteps: claim.steps.slice() }));
    const claimedSteps = new Set();
    claims.forEach((claim) => {
      if (!claim.captureSteps.length) {
        Common.fail("material_shop_review_claim_set_invalid", "review_request",
          "Agent Runtime visible review claim has no capture step", {
            claimId: claim.claimId,
          });
      }
      claim.captureSteps.forEach((stepId) => {
        const step = stepById.get(stepId);
        if (!step || step.requiresCapture !== true || claimedSteps.has(stepId)) {
          Common.fail("material_shop_review_claim_set_invalid", "review_request",
            "Agent Runtime visible review claims must map one-to-one onto capture steps", {
              claimId: claim.claimId, stepId,
            });
        }
        claimedSteps.add(stepId);
      });
    });
    const requiredSteps = steps.filter((step) => step.requiresCapture === true)
      .map((step) => step.id);
    if (claimedSteps.size !== requiredSteps.length
        || requiredSteps.some((stepId) => !claimedSteps.has(stepId))) {
      Common.fail("material_shop_review_claim_set_invalid", "review_request",
        "Agent Runtime visible review claims must exactly cover the capture inventory", {
          requiredSteps, claimedSteps: Array.from(claimedSteps),
        });
    }
    return claims;
  }
  const stepIds = new Set(steps.map((step) => step.id));
  return CLAIMS.map((claim) => ({ claimId: claim.claimId,
    captureSteps: claim.steps.slice() })).filter((claim) =>
    claim.captureSteps.every((step) => stepIds.has(step)));
}

function trustedRunnerSessions(context) {
  const sessions = context.raw.sessions;
  const expectedLabels = ["first", "restart"];
  if (!Array.isArray(sessions) || sessions.length !== expectedLabels.length) {
    Common.fail("material_shop_review_trusted_sessions_invalid", "review_request",
      "review request requires exact first and restart trusted-runner sessions");
  }
  return sessions.map((session, index) => {
    const completionSha256 = Evidence.sha256Text(
      Evidence.canonicalJson(session.completion));
    const transcriptSha256 = Evidence.sha256Text(
      Evidence.canonicalJson(session.transcript));
    const ledgerSha256 = Evidence.sha256Text(Evidence.canonicalJson(session.ledger));
    if (session.label !== expectedLabels[index] || session.cleanExit !== true
        || session.transcriptSha256 !== transcriptSha256
        || session.ledgerSha256 !== ledgerSha256) {
      Common.fail("material_shop_review_trusted_sessions_invalid", "review_request",
        "review request trusted-runner hashes are malformed or detached", {
          label: expectedLabels[index],
        });
    }
    return { label: session.label, completionSha256, transcriptSha256, ledgerSha256 };
  });
}

function settlementSha256(context) {
  const projection = { settlement: context.evidence.journey.routes.unlocked.settlement,
    persistence: context.evidence.journey.persistence };
  return Evidence.sha256Text(Evidence.canonicalJson(projection));
}

function createReviewRequest(context, staticGate, requestedAt) {
  validateStaticGate(staticGate, context);
  const captures = captureInventory(context);
  const agentRuntime = isAgentRuntimeContext(context);
  const value = { schema: reviewRequestSchema(context.plan),
    requestedAt: requestedAt || new Date().toISOString(),
    runId: context.plan.runId, planSha256: context.plan.planSha256,
    preparationSha256: context.preparation.preparationSha256,
    closureSha256: context.closure.closureSha256,
    materializationSha256: context.preparation.materializationSha256,
    applicabilitySha256: context.applicability.applicabilitySha256,
    buildSha256: context.build.buildSha256,
    externalToolchainSha256: context.build.externalToolchain.descriptorSha256,
    candidateIdentitySha256: Evidence.sha256Text(
      Evidence.canonicalJson(context.build.candidateIdentity)),
    rawSha256: context.raw.rawSha256,
    operationTerminalSha256: context.operationTerminal.terminalSha256,
    journeyEvidenceSha256: context.evidence.evidenceSha256,
    settlementSha256: settlementSha256(context),
    cloneReleaseSha256: context.release.releaseSha256,
    staticGateSha256: staticGate.staticGateSha256 };
  if (agentRuntime) value.trustedRunnerSessions = trustedRunnerSessions(context);
  else value.admissionBundleSha256 = context.raw.admissions.map((entry) => entry.bundleSha256);
  Object.assign(value, {
    captureSetSha256: Evidence.sha256Text(Evidence.canonicalJson(captures)),
    captures, claims: reviewClaims(context.plan),
    reviewScope: reviewScope(context.plan),
    deployment: "NOT_DEPLOYED" });
  value.requestSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateReviewRequest(value, context, staticGate);
}

function validateReviewRequest(value, context, staticGate) {
  const agentRuntime = isAgentRuntimeContext(context);
  const requestKeys = ["schema", "requestedAt", "runId", "planSha256",
    "preparationSha256", "closureSha256", "materializationSha256",
    "applicabilitySha256", "buildSha256", "externalToolchainSha256",
    "candidateIdentitySha256", "rawSha256", "operationTerminalSha256",
    "journeyEvidenceSha256", "settlementSha256", "cloneReleaseSha256", "staticGateSha256",
    agentRuntime ? "trustedRunnerSessions" : "admissionBundleSha256",
    "captureSetSha256", "captures", "claims", "deployment", "reviewScope", "requestSha256"];
  Common.exactKeys(value, requestKeys, "material_shop_review_request_invalid", "review_request");
  const captures = captureInventory(context);
  if (value.schema !== reviewRequestSchema(context.plan)
      || !Number.isFinite(Date.parse(value.requestedAt))
      || value.runId !== context.plan.runId || value.planSha256 !== context.plan.planSha256
      || value.preparationSha256 !== context.preparation.preparationSha256
      || value.closureSha256 !== context.closure.closureSha256
      || value.materializationSha256 !== context.preparation.materializationSha256
      || value.applicabilitySha256 !== context.applicability.applicabilitySha256
      || value.buildSha256 !== context.build.buildSha256
      || value.externalToolchainSha256
        !== context.build.externalToolchain.descriptorSha256
      || value.candidateIdentitySha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(context.build.candidateIdentity))
      || value.rawSha256 !== context.raw.rawSha256
      || value.operationTerminalSha256 !== context.operationTerminal.terminalSha256
      || value.journeyEvidenceSha256 !== context.evidence.evidenceSha256
      || value.settlementSha256 !== settlementSha256(context)
      || value.cloneReleaseSha256 !== context.release.releaseSha256
      || value.staticGateSha256 !== staticGate.staticGateSha256
      || agentRuntime && Evidence.canonicalJson(value.trustedRunnerSessions)
        !== Evidence.canonicalJson(trustedRunnerSessions(context))
      || !agentRuntime && Evidence.canonicalJson(value.admissionBundleSha256)
        !== Evidence.canonicalJson(context.raw.admissions.map((entry) => entry.bundleSha256))
      || value.captureSetSha256 !== Evidence.sha256Text(Evidence.canonicalJson(captures))
      || Evidence.canonicalJson(value.captures) !== Evidence.canonicalJson(captures)
      || Evidence.canonicalJson(value.claims)
        !== Evidence.canonicalJson(reviewClaims(context.plan))
      || value.reviewScope !== reviewScope(context.plan)
      || value.deployment !== "NOT_DEPLOYED"
      || value.requestSha256 !== unsignedDigest(value, "requestSha256")) {
    Common.fail("material_shop_review_request_invalid", "review_request",
      "independent review request is malformed or detached from candidate captures");
  }
  return value;
}

function validateReviewReceipt(value, request) {
  Common.exactKeys(value, ["schema", "reviewedAt", "requestSha256", "captureSetSha256",
    "reviewer", "verdicts", "decision", "reviewReceiptSha256"],
  "material_shop_review_receipt_invalid", "review_receipt");
  Common.exactKeys(value.reviewer, ["reviewerId", "operationId", "reviewMethod",
    "reviewScope", "independenceAttested", "businessApiCalls"],
  "material_shop_review_receipt_invalid", "review_receipt");
  const reviewed = Date.parse(value.reviewedAt);
  const requested = Date.parse(request.requestedAt);
  if (value.schema !== REVIEW_RECEIPT_SCHEMA || !Number.isFinite(reviewed)
      || reviewed < requested || value.requestSha256 !== request.requestSha256
      || value.captureSetSha256 !== request.captureSetSha256
      || !Common.ID_RE.test(String(value.reviewer.reviewerId || ""))
      || !Common.ID_RE.test(String(value.reviewer.operationId || ""))
      || value.reviewer.reviewMethod !== "independent_visible_png_review"
      || value.reviewer.reviewScope !== request.reviewScope
      || value.reviewer.independenceAttested !== true
      || value.reviewer.businessApiCalls !== 0 || value.decision !== "accepted"
      || !Array.isArray(value.verdicts) || value.verdicts.length !== request.claims.length
      || value.reviewReceiptSha256 !== unsignedDigest(value, "reviewReceiptSha256")) {
    Common.fail("material_shop_review_receipt_invalid", "review_receipt",
      "independent visible-capture review receipt is malformed or detached");
  }
  value.verdicts.forEach((verdict, index) => {
    Common.exactKeys(verdict, ["claimId", "status", "captureStepsReviewed", "observation"],
      "material_shop_review_verdict_invalid", "review_receipt");
    const claim = request.claims[index];
    if (verdict.claimId !== claim.claimId || verdict.status !== "pass"
        || Evidence.canonicalJson(verdict.captureStepsReviewed)
          !== Evidence.canonicalJson(claim.captureSteps)
        || typeof verdict.observation !== "string" || verdict.observation.length < 8
        || verdict.observation.length > 1000) {
      Common.fail("material_shop_review_verdict_invalid", "review_receipt",
        "review verdict is missing one exact claim/capture observation", { index });
    }
  });
  return value;
}

function createAcceptance(context, staticGate, request, reviewReceipt, acceptedAt) {
  validateStaticGate(staticGate, context);
  validateReviewRequest(request, context, staticGate);
  validateReviewReceipt(reviewReceipt, request);
  const value = { schema: ACCEPTANCE_SCHEMA, acceptedAt: acceptedAt || new Date().toISOString(),
    status: "e2e_verified", deployment: "NOT_DEPLOYED", runId: context.plan.runId,
    planSha256: context.plan.planSha256,
    preparationSha256: context.preparation.preparationSha256,
    closureSha256: context.closure.closureSha256,
    materializationSha256: context.preparation.materializationSha256,
    buildSha256: context.build.buildSha256,
    externalToolchainSha256: context.build.externalToolchain.descriptorSha256,
    candidateIdentitySha256: request.candidateIdentitySha256,
    applicabilitySha256: context.applicability.applicabilitySha256,
    rawSha256: context.raw.rawSha256,
    operationTerminalSha256: context.operationTerminal.terminalSha256,
    journeyEvidenceSha256: context.evidence.evidenceSha256,
    settlementSha256: settlementSha256(context),
    cloneReleaseSha256: context.release.releaseSha256,
    staticGateSha256: staticGate.staticGateSha256,
    reviewRequestSha256: request.requestSha256,
    reviewReceiptSha256: reviewReceipt.reviewReceiptSha256,
    captureSetSha256: request.captureSetSha256,
    boundaries: { realGuiExecuted: true, candidateBuilt: true, candidateExecuted: true,
      e2eVerified: true, promoted: false, standardEntryVerified: false } };
  value.acceptanceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateAcceptance(value, context, staticGate, request, reviewReceipt);
}

function validateAcceptance(value, context, staticGate, request, reviewReceipt) {
  Common.exactKeys(value, ["schema", "acceptedAt", "status", "deployment", "runId",
    "planSha256", "preparationSha256", "closureSha256", "materializationSha256",
    "buildSha256", "externalToolchainSha256", "candidateIdentitySha256", "applicabilitySha256",
    "rawSha256", "operationTerminalSha256", "journeyEvidenceSha256", "settlementSha256", "cloneReleaseSha256", "staticGateSha256",
    "reviewRequestSha256", "reviewReceiptSha256", "captureSetSha256", "boundaries",
    "acceptanceSha256"], "material_shop_acceptance_invalid", "acceptance");
  Common.exactKeys(value.boundaries, ["realGuiExecuted", "candidateBuilt",
    "candidateExecuted", "e2eVerified", "promoted", "standardEntryVerified"],
  "material_shop_acceptance_invalid", "acceptance");
  if (value.schema !== ACCEPTANCE_SCHEMA || !Number.isFinite(Date.parse(value.acceptedAt))
      || Date.parse(value.acceptedAt) < Date.parse(reviewReceipt.reviewedAt)
      || value.status !== "e2e_verified" || value.deployment !== "NOT_DEPLOYED"
      || value.runId !== context.plan.runId || value.planSha256 !== context.plan.planSha256
      || value.preparationSha256 !== context.preparation.preparationSha256
      || value.closureSha256 !== context.closure.closureSha256
      || value.materializationSha256 !== context.preparation.materializationSha256
      || value.buildSha256 !== context.build.buildSha256
      || value.externalToolchainSha256
        !== context.build.externalToolchain.descriptorSha256
      || value.candidateIdentitySha256 !== request.candidateIdentitySha256
      || value.applicabilitySha256 !== context.applicability.applicabilitySha256
      || value.rawSha256 !== context.raw.rawSha256
      || value.operationTerminalSha256 !== context.operationTerminal.terminalSha256
      || value.journeyEvidenceSha256 !== context.evidence.evidenceSha256
      || value.settlementSha256 !== settlementSha256(context)
      || value.cloneReleaseSha256 !== context.release.releaseSha256
      || value.staticGateSha256 !== staticGate.staticGateSha256
      || value.reviewRequestSha256 !== request.requestSha256
      || value.reviewReceiptSha256 !== reviewReceipt.reviewReceiptSha256
      || value.captureSetSha256 !== request.captureSetSha256
      || value.boundaries.realGuiExecuted !== true || value.boundaries.candidateBuilt !== true
      || value.boundaries.candidateExecuted !== true || value.boundaries.e2eVerified !== true
      || value.boundaries.promoted !== false || value.boundaries.standardEntryVerified !== false
      || value.acceptanceSha256 !== unsignedDigest(value, "acceptanceSha256")) {
    Common.fail("material_shop_acceptance_invalid", "acceptance",
      "final acceptance is malformed, overclaims deployment, or is detached");
  }
  return value;
}

function parseArgs(argv) {
  const args = { mode: null, preparation: null, build: null, raw: null, evidence: null,
    release: null, staticGate: null, reviewRequest: null, reviewReceipt: null,
    acceptance: null, out: null };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    const take = () => { index += 1; return argv[index]; };
    if (token === "--capture-static-gate") args.mode = "static";
    else if (token === "--create-review-request") args.mode = "request";
    else if (token === "--accept") args.mode = "accept";
    else if (token === "--verify-acceptance") args.mode = "verify";
    else if (token === "--preparation") args.preparation = take();
    else if (token === "--build") args.build = take();
    else if (token === "--raw") args.raw = take();
    else if (token === "--evidence") args.evidence = take();
    else if (token === "--release") args.release = take();
    else if (token === "--static-gate") args.staticGate = take();
    else if (token === "--review-request") args.reviewRequest = take();
    else if (token === "--review-receipt") args.reviewReceipt = take();
    else if (token === "--acceptance") args.acceptance = take();
    else if (token === "--out") args.out = take();
    else Common.fail("material_shop_accept_argument_unknown", "acceptance", token);
  }
  const base = args.preparation && args.build && args.raw && args.evidence && args.release;
  const valid = base && args.mode && (args.mode === "static" && args.out
    || args.mode === "request" && args.staticGate && args.out
    || args.mode === "accept" && args.staticGate && args.reviewRequest
      && args.reviewReceipt && args.out
    || args.mode === "verify" && args.staticGate && args.reviewRequest
      && args.reviewReceipt && args.acceptance);
  if (!valid) {
    Common.fail("material_shop_accept_arguments_invalid", "acceptance",
      "mode and exact candidate/static-review artifacts are required");
  }
  return args;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const context = loadContext(args);
    let value;
    if (args.mode === "static") value = captureStaticGate(context);
    else {
      const staticGate = validateStaticGate(readJson(args.staticGate, "static_gate"), context);
      if (args.mode === "request") value = createReviewRequest(context, staticGate);
      else {
        const request = validateReviewRequest(readJson(args.reviewRequest, "review_request"),
          context, staticGate);
        const receipt = validateReviewReceipt(readJson(args.reviewReceipt, "review_receipt"),
          request);
        value = args.mode === "accept" ? createAcceptance(context, staticGate, request, receipt)
          : validateAcceptance(readJson(args.acceptance, "acceptance"), context,
            staticGate, request, receipt);
      }
    }
    if (args.out) writeJsonNew(args.out, value);
    process.stdout.write(JSON.stringify({ ok: true,
      result: value.status || value.schema,
      sha256: value.acceptanceSha256 || value.requestSha256 || value.staticGateSha256,
      deployment: value.deployment || "NOT_DEPLOYED" }) + "\n");
  } catch (error) {
    process.stderr.write(JSON.stringify(Common.publicError(error)) + "\n");
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = {
  ACCEPTANCE_SCHEMA,
  AGENT_RUNTIME_REVIEW_SCOPE,
  AGENT_RUNTIME_CLAIMS,
  CLAIMS,
  LEGACY_REVIEW_REQUEST_SCHEMA,
  LEGACY_REVIEW_SCOPE,
  REVIEW_RECEIPT_SCHEMA,
  REVIEW_REQUEST_SCHEMA,
  STATIC_GATE_SCHEMA,
  captureInventory,
  captureStaticGate,
  createAcceptance,
  createReviewRequest,
  isAgentRuntimeContext,
  loadContext,
  parseArgs,
  reviewClaims,
  reviewRequestSchema,
  reviewScope,
  settlementSha256,
  trustedRunnerSessions,
  validateAcceptance,
  validateCloneRelease,
  validateCraftingBrowserReceipt,
  validateReviewReceipt,
  validateReviewRequest,
  validateStaticGate,
  withStaticGateToolchainProjection,
};
