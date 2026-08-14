#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const Module = require("module");
const path = require("path");
const CloneGuard = require("../lib/clone-save-guard");
const Evidence = require("../lib/evidence-artifact");
const ExternalToolchain = require("../lib/playwright-websocket-toolchain");
const LauncherObservation = require("../lib/launcher-observation");
const PngContract = require("../kshop/png-contract");
const SharedAdapter = require("../npc/shared-adapter");
const NpcProduction = require("../npc/production-closure");
const Accept = require("./accept-run");
const AckControl = require("./ack-control");
const Admission = require("./admission");
const Applicability = require("./applicability");
const Build = require("./build-candidate");
const CandidateLifecycle = require("./candidate-lifecycle");
const Capture = require("./capture-verifier");
const Common = require("./common");
const Control = require("./control-channel");
const DiscardBuilt = require("./discard-built-run");
const FinalizeCloneRelease = require("./finalize-clone-release");
const Materialize = require("./materialize");
const Production = require("./production-closure");
const Protocol = require("./protocol");
const Prepare = require("./prepare");
const LiveRun = require("./run-live-journey");
const Release = require("./release-worktree");
const RunOperationLease = require("./run-operation-lease");
const Scope = require("./scope-manifest");

let passed = 0;
let total = 0;

function test(name, fn) {
  total += 1;
  fn();
  passed += 1;
  process.stdout.write("ok " + total + " - " + name + "\n");
}

function negative(name, code, fn) {
  test(name, () => {
    let thrown = null;
    try { fn(); } catch (error) { thrown = error; }
    assert(thrown, name + " did not fail closed");
    assert.strictEqual(thrown.code, code, thrown && thrown.stack);
  });
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function reseal(value, key) {
  delete value[key];
  value[key] = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function environmentCapability(mode, available) {
  const artifact = { schema: "material-shop-self-test-capability.v1",
    available: available === true };
  return { available: available === true,
    source: mode === "offline_fixture"
      ? "offline_fixture_capability" : "environment_tool_preflight",
    artifact, artifactSha256: Evidence.sha256Text(Evidence.canonicalJson(artifact)) };
}

function writeOperatorArtifact(directory, name, value) {
  fs.mkdirSync(directory, { recursive: true });
  const filePath = path.join(directory, name + ".json");
  fs.writeFileSync(filePath, JSON.stringify(value) + "\n", { encoding: "utf8", flag: "wx" });
  return filePath;
}

function operationArtifactAfter(filePath, issuedAt) {
  let artifact = Admission.captureRawOperationArtifact(filePath);
  if (Date.parse(artifact.sourceLastWriteUtc) < Date.parse(issuedAt)) {
    const time = new Date(Date.parse(issuedAt) + 1);
    fs.utimesSync(filePath, time, time);
    artifact = Admission.captureRawOperationArtifact(filePath);
  }
  return artifact;
}

function completedAfterOperation(artifact) {
  return new Date(Date.parse(artifact.sourceLastWriteUtc) + 1).toISOString();
}

function environmentProviderReceipt(available, artifactPath, observedAt) {
  const artifact = Admission.captureRawOperationArtifact(artifactPath);
  const defaultObservedAt = new Date(Date.parse(artifact.sourceLastWriteUtc) + 1).toISOString();
  return { schema: Admission.ENVIRONMENT_RECEIPT_SCHEMA,
    issuer: Admission.OPERATOR_ISSUER, operationId: "self-test-environment-probe",
    observedAt: observedAt || defaultObservedAt, available: available === true,
    toolName: "computer-use", businessApiCalls: 0, rawOperationArtifact: artifact,
    trustBoundary: Admission.OPERATOR_TRUST_BOUNDARY, independentlyVerifiable: false,
    nativeInputVisibleClaim: false };
}

function lockInspection(slot, overrides) {
  const value = Object.assign({ schema: "workbench-live-e2e.clone-lock-inspection.v1",
    apiVersion: "FROZEN-v1", observedAt: "2026-08-11T00:02:00.000Z", slot,
    lockPath: "C:\\owned\\" + slot + ".clone.lock", lockPresent: false,
    recordSha256: null, ownerPid: null, ownerProcessStartUtcTicks: null,
    observedProcessStartUtcTicks: null, ownerState: "absent", recoveryPresent: false,
    recoveryStatus: null, recoveryRecordSha256: null }, overrides || {});
  value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function materialNpcState(panelInstanceId, callId, command, balance, owned, target, unitPrice) {
  const view = (viewId, slots) => ({ containerId: viewId === "material" ? "材料" : "情报",
    capacity: slots.length, accessibleCapacity: slots.length, viewCapacity: slots.length,
    offset: 0, limit: slots.length, filterKey: viewId, slots });
  const materialSlots = owned > 0 ? [{ physicalSlot: 0, collectionKey: target.itemName,
    occupied: true, slotLease: "material.self-test.0", item: { itemKind: "stack",
      name: target.itemName, displayName: target.itemName, icon: target.itemName,
      majorType: "", use: "材料", quantity: owned, enhancementLevel: 0, rarity: "" } }] : [];
  const value = { type: "panel_resp", domain: "npcshop", panel: "npcshop",
    panelInstanceId, cmd: command, callId, success: true, v: 1,
    shopId: target.shopId, balance, buyMultiplier: 1,
    catalog: [{ catalogIndex: target.catalogIndex, itemName: target.itemName,
      displayName: target.itemName, icon: target.itemName, majorType: "", use: "材料",
      actionType: "", weaponType: "", setId: "", setName: "", setOrder: 0,
      basePrice: target.basePrice, unitPrice, maxQuantity: 999999,
      requiredInfo: "", locked: false }],
    layout: { title: target.shopId, defaultSection: "", sections: [] },
    views: { material: view("material", materialSlots), intelligence: view("intelligence", []) } };
  if (command === "tradeCommit") {
    value.operation = "tradeCommit";
    value.trade = { buyTotal: unitPrice, sellTotal: 0, netDelta: -unitPrice };
  }
  return value;
}

function settlementFixture(applicability) {
  const target = applicability.selectedUnlockedTarget;
  const panelInstanceId = "npcshop.self-test.settlement";
  const baseline = applicability.sourceFixture.money;
  const unitPrice = target.basePrice;
  const event = (sequence, observedAt, message) => ({ event: { sequence, observedAt }, message });
  const owner = event(1, "2026-08-11T00:00:01.000Z",
    materialNpcState(panelInstanceId, "snapshot.self-test", "snapshot",
      baseline, 0, target, unitPrice));
  const previewMessage = { type: "panel", domain: "npcshop", panel: "npcshop",
    panelInstanceId, cmd: "tradePreview", callId: "preview.self-test",
    payload: { v: 1, shopId: target.shopId,
      purchases: [{ catalogIndex: target.catalogIndex, quantity: 1 }], sales: [] } };
  const preview = event(2, "2026-08-11T00:00:02.000Z", previewMessage);
  const previewResponse = event(3, "2026-08-11T00:00:03.000Z", {
    type: "panel_resp", domain: "npcshop", panel: "npcshop", panelInstanceId,
    cmd: "tradePreview", callId: previewMessage.callId, success: true, v: 1,
    shopId: target.shopId, tradeToken: "trade.self-test.token",
    purchaseLines: [{ catalogIndex: target.catalogIndex, itemName: target.itemName,
      displayName: target.itemName, icon: target.itemName, quantity: 1,
      unitPrice, total: unitPrice, maxQuantity: 999999, purchaseLimit: 999999,
      maxAffordable: Math.floor(baseline / unitPrice), maxByCapacity: 999999,
      maxPurchasable: Math.floor(baseline / unitPrice), limitingReason: "insufficient_money",
      itemKind: "stack", destinationView: "material" }], saleLines: [],
    buyTotal: unitPrice, sellTotal: 0, netDelta: -unitPrice,
    projectedBalance: baseline - unitPrice, requiredSlots: 0, availableSlots: 0,
    missingSlots: 0, canCommit: true, blockingError: "" });
  const commitMessage = { type: "panel", domain: "npcshop", panel: "npcshop",
    panelInstanceId, cmd: "tradeCommit", callId: "commit.self-test",
    payload: { v: 1, shopId: target.shopId,
      expectedTradeToken: previewResponse.message.tradeToken } };
  const commit = event(4, "2026-08-11T00:00:04.000Z", commitMessage);
  const commitResponse = event(5, "2026-08-11T00:00:05.000Z",
    materialNpcState(panelInstanceId, commitMessage.callId, "tradeCommit",
      baseline - unitPrice, 1, target, unitPrice));
  return { preview, commit, inbound: [owner, previewResponse, commitResponse],
    owner, previewResponse, commitResponse };
}

function hostRecord(lineNumber, body) {
  return { lifecycle: "first", lineNumber, body,
    observedAt: new Date(Date.UTC(2026, 7, 11, 0, 0, lineNumber)).toISOString(),
    hostTimeOfDayMs: lineNumber * 1000 };
}

function scopeBinding(closure) {
  return { head: closure.head, scopeSha256: closure.scope.scopeSha256,
    closureSha256: closure.closureSha256, materializationSha256: "b".repeat(64) };
}

function planFor(applicability, closure, allowFallback, available) {
  const mode = "offline_fixture";
  const authorization = Protocol.createAuthorization({ evidenceMode: mode,
    decisionId: "material-shop-self-test-qty1" });
  return Protocol.createControlPlan({ runId: "material-shop-self-test", evidenceMode: mode,
    seedSlot: "cf7_agent_a5_material_shop_seed_test",
    targetSlot: "cf7_agent_a5_material_shop_run_test",
    recoverySlot: "cf7_agent_a5_material_shop_recovery_test",
    scope: scopeBinding(closure), applicability,
    environmentCapability: environmentCapability(mode, available),
    allowPanelCdpFallback: allowFallback === true, authorization });
}

function agentRuntimePlanFor(applicability, closure) {
  const runId = "material-shop-agent-runtime-self-test";
  const authorization = Protocol.createAgentRuntimeAuthorization({
    evidenceMode: "candidate_capture",
    decisionId: "material-shop-agent-runtime-self-test-qty1",
    runId,
    applicabilitySha256: applicability.applicabilitySha256,
    target: applicability.selectedUnlockedTarget,
  });
  return Protocol.createAgentRuntimeControlPlan({
    runId, evidenceMode: "candidate_capture",
    seedSlot: "cf7_agent_a5_material_shop_seed",
    targetSlot: Protocol.AGENT_RUNTIME_SLOT,
    recoverySlot: "cf7_agent_a5_material_shop_recovery",
    scope: scopeBinding(closure), applicability, authorization,
  });
}

function agentRuntimeEvidenceFixture(plan, applicability) {
  const target = applicability.selectedUnlockedTarget;
  const unitPrice = target.basePrice;
  const baselineBalance = applicability.sourceFixture.money;
  const projectedBalance = baselineBalance - unitPrice;
  const na = (summary) => ({ status: "not_applicable_current_data",
    applicabilitySha256: plan.applicability.applicabilitySha256,
    qualifyingOccurrenceCount: summary.qualifyingOccurrenceCount });
  const closeOutcome = (closeStepId, closeRole, closeMethod, successorStepId,
    closeReceiptDigit, openReceiptDigit, captureDigit) => ({
    closeStepId, closeRole, closeMethod,
    closeActionReceiptSha256: closeReceiptDigit.repeat(64),
    successorStepId, successorMethod: "panel.open",
    successorActionReceiptSha256: openReceiptDigit.repeat(64),
    successorCaptureSha256: captureDigit.repeat(64),
    successorSessionLabel: "first", successorObservationId: "observation-close-1",
    successorFrameId: "frame-close-1", successorFrameContentHash: "7".repeat(64),
    admissionFence: "prior_tracked_visual_idle_required", successorPanel: "materials",
  });
  return {
    plan,
    controls: { completedSteps: plan.steps.map((step) => step.id),
      provider: Protocol.AGENT_RUNTIME_PROVIDER,
      transport: Protocol.AGENT_RUNTIME_TRANSPORT,
      authorizationDecisionId: plan.authorization.decisionId,
      controllerBusinessApiCalls: 0, sessionCount: 2, visibleCaptureCount: 16,
      actionIntentCount: 32,
      keyboardActionIntentCount: Protocol.AGENT_RUNTIME_RECIPE_JUMP.keyboardActions.length,
      keyboardSequenceSha256: "9".repeat(64) },
    journey: {
      operationLease: { leaseSha256: "a".repeat(64), mode: "live_execution",
        activeAtCapture: true },
      agentRuntime: { provider: Protocol.AGENT_RUNTIME_PROVIDER,
        transport: Protocol.AGENT_RUNTIME_TRANSPORT,
        trustedRunnerSlot: Protocol.AGENT_RUNTIME_SLOT,
        candidateLeaf: Protocol.AGENT_RUNTIME_CANDIDATE_LEAF, sessionCount: 2,
        firstCompletionSha256: "b".repeat(64), restartCompletionSha256: "c".repeat(64) },
      materials: { archiveOrder: "authored_xml", visualVerified: true,
        keyboardJourneyVerified: true, candidateViewport: "current_window",
        responsiveThreeViewportGateBound: true,
        multiVariant: { enemyType: "self-test-enemy", occurrenceIndices: [0, 1],
          allVisible: true },
        portraits: Protocol.createAgentRuntimePortraitEvidence(plan, true),
        recipeJump: { materialName: Protocol.AGENT_RUNTIME_RECIPE_JUMP.materialName,
          category: Protocol.AGENT_RUNTIME_RECIPE_JUMP.category,
          recipeIndex: Protocol.AGENT_RUNTIME_RECIPE_JUMP.recipeIndex,
          productName: Protocol.AGENT_RUNTIME_RECIPE_JUMP.productName,
          keyboardSequenceSha256: "9".repeat(64),
          visibleCaptureSha256: "8".repeat(64), keySequenceVerified: true,
          escapeCloseOutcome: closeOutcome("recipe_escape_close",
            "recipe_close_with_escape", "input.press_key", "recipe_reopen_materials",
            "1", "2", "3") } },
      routes: { locked: na(plan.applicability.locked),
        ordinaryClose: { target: { shopId: target.shopId,
          catalogIndex: target.catalogIndex, itemName: target.itemName },
        forwardCommitted: true, ordinaryCloseCommitted: true,
        closeOutcome: closeOutcome("ordinary_close", "npcshop_close", "input.click",
          "reopen_materials", "4", "5", "6") },
        unlocked: { target: { shopId: target.shopId, catalogIndex: target.catalogIndex,
          itemName: target.itemName }, forwardCommitted: true, locatedExact: true,
        navigationFocus: "data-navigation-focus", quantity: 1, saleCount: 0,
        settlementProjectionCount: 1, commitDispatchCount: 1,
        settled: true, returnCommitted: true,
        settlement: { baselineBalance, unitPrice, buyTotal: unitPrice,
          projectedBalance, beforeOwned: 0, afterOwned: 1 } },
        max: na(plan.applicability.max) },
      persistence: { trustedPersistenceShutdown: true, trustedFinalShutdown: true,
        seedReadOnly: true, targetIsolated: true, recoveryAvailable: true,
        restartFreshProcess: true, restartReadbackEqual: true,
        baselineMoney: baselineBalance, settledMoney: projectedBalance, beforeOwned: 0,
        archiveOwned: 1, restartOwned: 1, archiveSha256: "d".repeat(64),
        restartSha256: "e".repeat(64), archiveSemanticSha256: "f".repeat(64),
        restartSemanticSha256: "f".repeat(64) },
      authorityCounts: { settlementProjection: 1, commitDispatch: 1, sale: 0 },
    },
    boundaries: { realGuiExecuted: true, candidateBuilt: true, candidateExecuted: true,
      e2eVerified: false, promoted: false, standardEntryVerified: false },
  };
}

function syntheticScope(sourceRoot, relativePath, bytes, head) {
  const file = { ordinal: 0, relativePath, roles: ["fixture"], origins: ["self_test"],
    bytes: bytes.length, sha256: Evidence.sha256Bytes(bytes) };
  const value = { schema: Scope.SCOPE_SCHEMA, capturedAt: "2026-08-11T00:00:00.000Z",
    root: sourceRoot, head, composition: { fixture: true }, fileCount: 1,
    totalBytes: bytes.length, files: [file] };
  value.scopeSha256 = Evidence.sha256Text(Evidence.canonicalJson(Scope.stableProjection(value)));
  return value;
}

function subsetScope(sourceRoot, sourceEntries, head) {
  const files = sourceEntries.slice().sort((left, right) =>
    left.relativePath.localeCompare(right.relativePath)).map((entry, index) => ({
    ordinal: index,
    relativePath: entry.relativePath,
    roles: entry.roles.slice(),
    origins: entry.origins.slice(),
    bytes: entry.bytes,
    sha256: entry.sha256,
  }));
  const value = { schema: Scope.SCOPE_SCHEMA,
    capturedAt: "2026-08-11T00:00:00.000Z", root: sourceRoot, head,
    composition: { fixture: "ignored_protected_scope_inputs" },
    fileCount: files.length,
    totalBytes: files.reduce((sum, entry) => sum + entry.bytes, 0), files };
  value.scopeSha256 = Evidence.sha256Text(Evidence.canonicalJson(Scope.stableProjection(value)));
  return Scope.verifyScopeManifest(value, { currentTree: false });
}

function providerReceipt(request, artifactPath, observedAt) {
  const rawOperationArtifact = operationArtifactAfter(artifactPath, request.issuedAt);
  const defaultObservedAt = new Date(Math.max(Date.now(), Date.parse(request.issuedAt),
    Date.parse(rawOperationArtifact.sourceLastWriteUtc)) + 1).toISOString();
  return { schema: Admission.CANDIDATE_RECEIPT_SCHEMA,
    issuer: Admission.OPERATOR_ISSUER, operationId: "self-test-candidate-probe",
    observedAt: observedAt || defaultObservedAt,
    available: true, runId: request.runId, planSha256: request.planSha256,
    requestSha256: request.requestSha256,
    candidateIdentitySha256: Evidence.sha256Text(
      Evidence.canonicalJson(request.candidateIdentity)),
    pid: request.candidateIdentity.pid,
    window: { handle: "window-100", title: "CF7 candidate", visible: true },
    attestedNativeInputVisible: true, businessApiCalls: 0,
    rawOperationArtifact,
    trustBoundary: Admission.OPERATOR_TRUST_BOUNDARY, independentlyVerifiable: false,
    independentEvidenceRequired: true };
}

function fakeBrowserReceipt() {
  const digest = "d".repeat(64);
  const receipt = { schema: "workbench-live-e2e.crafting.browser-gate-receipt.v1",
    status: "OFFLINE_VERIFIED", moduleAdmission: "ADMITTED",
    journalVerification: "VERIFIED", manifestSha256: digest,
    moduleJournalSha256: digest, moduleEntryCount: 1,
    browserBinary: { locator: "external:edge", sha256: digest, bytes: 1 },
    servedResourceClosure: { evidenceSha256: digest, requiredResourceCount: 1,
      failureCount: 4 },
    result: { viewports: [{ width: 1024, height: 576 },
      { width: 1366, height: 768 }, { width: 1920, height: 1080 }],
    scenarioCounts: { baseline: 150, coverage: 15, fault: 8, identity: 10 },
    materialShopScenarioCount: 11,
    materialShopScenarioNamesSha256: [digest, digest, digest],
    scenarioNamesSha256: { baseline: digest, coverage: digest,
      fault: digest, identity: digest },
    faultChecks: Array.from({ length: 8 }, (_, index) => ({ name: "fault-" + index,
      ok: true })), resultSha256: digest } };
  receipt.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(receipt));
  return receipt;
}

function fakeReviewReceipt(request) {
  const value = { schema: Accept.REVIEW_RECEIPT_SCHEMA,
    reviewedAt: "2026-08-11T00:01:00.000Z", requestSha256: request.requestSha256,
    captureSetSha256: request.captureSetSha256,
    reviewer: { reviewerId: "independent-reviewer", operationId: "review-operation-1",
      reviewMethod: "independent_visible_png_review",
      reviewScope: "visible_png_content_only_not_input_or_capture_provenance",
      independenceAttested: true,
      businessApiCalls: 0 },
    verdicts: request.claims.map((claim) => ({ claimId: claim.claimId, status: "pass",
      captureStepsReviewed: claim.captureSteps,
      observation: "Visible claim reviewed against every bound PNG." })),
    decision: "accepted" };
  value.reviewReceiptSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function safeCleanup(testBase) {
  const expected = path.resolve(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE);
  if (!Evidence.pathInside(expected, testBase)
      || !path.basename(testBase).startsWith("self-test-")) {
    throw new Error("refusing unsafe material-shop self-test cleanup");
  }
  if (fs.existsSync(testBase)) fs.rmSync(testBase, { recursive: true, force: true });
}

function main() {
  const owned = path.resolve(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE);
  fs.mkdirSync(owned, { recursive: true });
  const testBase = path.join(owned, "runs",
    "self-test-" + process.pid + "-" + Date.now());
  const discardTestBase = path.join(owned, "runs",
    "self-test-discard-" + process.pid + "-" + Date.now());
  const operationCancelBase = path.join(owned, "runs",
    "self-test-operation-cancel-" + process.pid + "-" + Date.now());
  const producerLeaseBase = path.join(owned, "runs",
    "self-test-producer-lease-" + process.pid + "-" + Date.now());
  const producerReuseBase = path.join(owned, "runs",
    "self-test-producer-reuse-" + process.pid + "-" + Date.now());
  const preControlBase = path.join(owned, "runs",
    "self-test-pre-control-" + process.pid + "-" + Date.now());
  fs.mkdirSync(testBase, { recursive: true });
  fs.mkdirSync(discardTestBase, { recursive: true });
  fs.mkdirSync(operationCancelBase, { recursive: true });
  fs.mkdirSync(producerLeaseBase, { recursive: true });
  fs.mkdirSync(producerReuseBase, { recursive: true });
  fs.mkdirSync(preControlBase, { recursive: true });
  try {
    const applicability = Applicability.captureCurrentDataApplicability(Common.CANONICAL_ROOT, {
      appData: process.env.APPDATA, capturedAt: "2026-08-11T00:00:00.000Z",
    });
    const fixtureAuthorityBinding = Applicability.createFixtureAuthorityBinding(
      Common.CANONICAL_ROOT, applicability, applicability.capturedAt);
    test("current material applicability exact set", () => {
      assert.deepStrictEqual(applicability.counts, { materialCount: 224, shopFileCount: 35,
        materialOccurrenceCount: 104, uniqueMaterialItemCount: 101,
        requiredInfoOccurrenceCount: 0, purchaseLimitOccurrenceCount: 0,
        seedCount: 4, seedMaterialPairCount: 416,
        affordableSeedOccurrenceCount: 416, atDefaultLimitSeedOccurrenceCount: 0 });
      assert.strictEqual(applicability.locked.status, "not_applicable_current_data");
      assert.strictEqual(applicability.max.status, "not_applicable_current_data");
      assert.strictEqual(applicability.selectedUnlockedTarget.shopId, "厨师");
      assert.strictEqual(applicability.selectedUnlockedTarget.catalogIndex, 24);
      assert.strictEqual(applicability.selectedUnlockedTarget.itemName, "食用油");
      assert.strictEqual(applicability.selectedUnlockedTarget.basePrice, 300);
      assert.strictEqual(applicability.selectedUnlockedTarget.owned, 0);
    });
    test("four exact seed JSON and complete SOL sets are bound", () => {
      assert.deepStrictEqual(applicability.seedAudit.map((entry) => entry.slot), [
        "cf7_agent_arena_calibration", "cf7_agent_character_build_b4",
        "cf7_agent_character_build_final", "cf7_agent_equipment_tuning",
      ]);
      applicability.seedAudit.forEach((entry) => {
        assert.strictEqual(entry.artifacts.filter((artifact) => artifact.kind === "json").length, 1);
        assert(entry.artifacts.filter((artifact) => artifact.kind === "sol").length >= 1);
      });
    });
    test("candidate lifecycle keeps materialized data and canonical fixture authority roots distinct", () => {
      const materializedDataRoot = path.join(testBase, "distinct-materialized-data-root");
      fs.mkdirSync(materializedDataRoot);
      const roots = Applicability.resolveApplicabilityRoots(materializedDataRoot, {
        fixtureAuthorityRoot: Common.CANONICAL_ROOT,
      });
      assert.strictEqual(path.resolve(roots.dataRoot), path.resolve(materializedDataRoot));
      assert.strictEqual(path.resolve(roots.fixtureAuthorityRoot),
        path.resolve(Common.CANONICAL_ROOT));
      const lifecycleSource = fs.readFileSync(path.join(__dirname, "candidate-lifecycle.js"),
        "utf8");
      const liveSource = fs.readFileSync(path.join(__dirname, "run-live-journey.js"), "utf8");
      const verifierSource = fs.readFileSync(path.join(__dirname, "journey-verifier.js"), "utf8");
      assert(lifecycleSource.includes("Applicability.replayFixtureAuthorityBinding("));
      assert(lifecycleSource.includes("importSeed(sourceFixtureRoot, resourcesRoot"));
      assert(liveSource.includes("canonicalRoot: preparation.resourcesRoot"));
      assert(liveSource.includes("fixtureAuthorityBinding: lifecycleAuthority.fixtureAuthorityBinding"));
      assert(liveSource.indexOf("const preflightApplicability = verifyLifecycleApplicability")
        < liveSource.indexOf("RunOperationLease.acquire"));
      assert(verifierSource.includes("Common.assertCanonicalRoot(value.fixtureAuthorityBinding"));
    });
    negative("materialized data root cannot become fixture JSON/SOL authority",
      "material_shop_canonical_root_mismatch", () => {
        Applicability.resolveApplicabilityRoots(path.join(testBase,
          "distinct-materialized-data-root"), {
          fixtureAuthorityRoot: path.join(testBase, "distinct-materialized-data-root"),
        });
      });
    let applicabilityFixture = null;
    test("materialized production bytes replay with canonical-only JSON and SOL authority", () => {
      const dataRoot = path.join(testBase, "materialized-applicability-data");
      fs.mkdirSync(dataRoot);
      const descriptors = NpcProduction.productionFiles(Common.CANONICAL_ROOT)
        .filter((entry) => entry.role === "shop_data" || entry.role === "item_data")
        .map((entry) => ({ role: entry.role, relativePath: entry.relativePath }));
      const required = [Applicability.MATERIAL_CATALOG, Applicability.PURCHASE_AUTHORITY,
        Applicability.HOST_AUTHORITY].concat(descriptors.map((entry) => entry.relativePath));
      Array.from(new Set(required)).forEach((relativePath) => {
        const source = path.join(Common.CANONICAL_ROOT,
          relativePath.replace(/\//g, path.sep));
        const destination = path.join(dataRoot, relativePath.replace(/\//g, path.sep));
        fs.mkdirSync(path.dirname(destination), { recursive: true });
        fs.copyFileSync(source, destination);
      });
      const fakeSave = path.join(dataRoot, "saves", Common.SOURCE_FIXTURE_SLOT + ".json");
      fs.mkdirSync(path.dirname(fakeSave), { recursive: true });
      fs.writeFileSync(fakeSave, "{}\n", "utf8");
      const originalProductionFiles = NpcProduction.productionFiles;
      NpcProduction.productionFiles = () => descriptors.map((entry) => Object.assign({}, entry));
      try {
        const replay = Applicability.verifyCurrentDataApplicability(dataRoot, applicability, {
          appData: process.env.APPDATA,
          fixtureAuthorityRoot: Common.CANONICAL_ROOT,
        });
        assert.strictEqual(replay.applicabilitySha256, applicability.applicabilitySha256);
        assert.strictEqual(replay.sourceFixture.artifactSetSha256,
          applicability.sourceFixture.artifactSetSha256);
        const authorityReplay = Applicability.replayFixtureAuthorityBinding(
          fixtureAuthorityBinding, replay, { resourcesRoot: dataRoot,
            appData: process.env.APPDATA });
        assert.strictEqual(authorityReplay.root, path.resolve(Common.CANONICAL_ROOT));
        assert.strictEqual(authorityReplay.binding.bindingSha256,
          fixtureAuthorityBinding.bindingSha256);
        applicabilityFixture = { dataRoot, descriptors };
      } finally {
        NpcProduction.productionFiles = originalProductionFiles;
      }
    });
    test("fresh materialized Applicability module replays outer canonical authority", () => {
      const moduleRoot = path.join(testBase, "materialized-authority-module");
      const relativeFiles = [
        "tools/workbench-live-e2e/material-shop/applicability.js",
        "tools/workbench-live-e2e/material-shop/common.js",
        "tools/workbench-live-e2e/lib/evidence-artifact.js",
        "tools/workbench-live-e2e/lib/clone-save-guard.js",
        "tools/workbench-live-e2e/npc/production-closure.js",
        "tools/workbench-live-e2e/npc/common.js",
      ];
      relativeFiles.forEach((relativePath) => {
        const source = path.join(Common.CANONICAL_ROOT,
          relativePath.replace(/\//g, path.sep));
        const destination = path.join(moduleRoot, relativePath.replace(/\//g, path.sep));
        fs.mkdirSync(path.dirname(destination), { recursive: true });
        fs.copyFileSync(source, destination);
      });
      const materializedApplicability = require(path.join(moduleRoot, "tools",
        "workbench-live-e2e", "material-shop", "applicability.js"));
      const replay = materializedApplicability.replayFixtureAuthorityBinding(
        fixtureAuthorityBinding, applicability, { resourcesRoot: moduleRoot,
          appData: process.env.APPDATA });
      assert.strictEqual(path.resolve(replay.root), path.resolve(Common.CANONICAL_ROOT));
      const forged = JSON.parse(JSON.stringify(fixtureAuthorityBinding));
      forged.root = moduleRoot;
      forged.bindingSha256 = Evidence.sha256Text(Evidence.canonicalJson(
        materializedApplicability.stableFixtureAuthorityBinding(forged)));
      assert.throws(() => materializedApplicability.replayFixtureAuthorityBinding(
        forged, applicability, { resourcesRoot: moduleRoot, appData: process.env.APPDATA }),
      (error) => error && error.code === "material_shop_fixture_authority_root_invalid");
    });
    negative("materialized resources cannot self-issue fixture authority",
      "material_shop_fixture_authority_root_invalid", () => {
        const forged = JSON.parse(JSON.stringify(fixtureAuthorityBinding));
        forged.root = applicabilityFixture.dataRoot;
        forged.bindingSha256 = Evidence.sha256Text(Evidence.canonicalJson(
          Applicability.stableFixtureAuthorityBinding(forged)));
        Applicability.replayFixtureAuthorityBinding(forged, applicability, {
          resourcesRoot: applicabilityFixture.dataRoot, appData: process.env.APPDATA,
        });
      });
    negative("fixture authority cannot hide inside materialized resources",
      "material_shop_fixture_authority_root_invalid", () => {
        const nested = path.join(applicabilityFixture.dataRoot, "nested-fixture-authority");
        fs.mkdirSync(nested);
        const forged = JSON.parse(JSON.stringify(fixtureAuthorityBinding));
        forged.root = nested;
        forged.bindingSha256 = Evidence.sha256Text(Evidence.canonicalJson(
          Applicability.stableFixtureAuthorityBinding(forged)));
        Applicability.replayFixtureAuthorityBinding(forged, applicability, {
          resourcesRoot: applicabilityFixture.dataRoot, appData: process.env.APPDATA,
        });
      });
    negative("fixture authority binding cannot be detached from applicability",
      "material_shop_fixture_authority_binding_invalid", () => {
        const drift = JSON.parse(JSON.stringify(fixtureAuthorityBinding));
        drift.artifactProjection.sourceFixture.artifacts[0].sha256 = "0".repeat(64);
        drift.bindingSha256 = Evidence.sha256Text(Evidence.canonicalJson(
          Applicability.stableFixtureAuthorityBinding(drift)));
        Applicability.replayFixtureAuthorityBinding(drift, applicability, {
          resourcesRoot: applicabilityFixture.dataRoot, appData: process.env.APPDATA,
        });
      });
    negative("canonical fixture SOL absence cannot be replaced by materialized saves",
      "material_shop_seed_audit_incomplete", () => {
        const originalProductionFiles = NpcProduction.productionFiles;
        const originalCapture = CloneGuard.captureSlotArtifactSet;
        NpcProduction.productionFiles = () => applicabilityFixture.descriptors
          .map((entry) => Object.assign({}, entry));
        CloneGuard.captureSlotArtifactSet = (options) => {
          const captured = originalCapture(options);
          if (path.resolve(options.root).toLowerCase()
              !== path.resolve(Common.CANONICAL_ROOT).toLowerCase()) return captured;
          return Object.assign({}, captured, {
            artifacts: captured.artifacts.filter((entry) => entry.kind !== "sol"),
          });
        };
        try {
          Applicability.captureCurrentDataApplicability(applicabilityFixture.dataRoot, {
            appData: process.env.APPDATA,
            fixtureAuthorityRoot: Common.CANONICAL_ROOT,
          });
        } finally {
          CloneGuard.captureSlotArtifactSet = originalCapture;
          NpcProduction.productionFiles = originalProductionFiles;
        }
      });
    negative("dirty materialized applicability data cannot reuse canonical fixture evidence",
      "material_shop_applicability_drift", () => {
        fs.appendFileSync(path.join(applicabilityFixture.dataRoot,
          Applicability.MATERIAL_CATALOG.replace(/\//g, path.sep)), "\n", "utf8");
        const originalProductionFiles = NpcProduction.productionFiles;
        NpcProduction.productionFiles = () => applicabilityFixture.descriptors
          .map((entry) => Object.assign({}, entry));
        try {
          Applicability.verifyCurrentDataApplicability(applicabilityFixture.dataRoot,
            applicability, { appData: process.env.APPDATA,
              fixtureAuthorityRoot: Common.CANONICAL_ROOT });
        } finally {
          NpcProduction.productionFiles = originalProductionFiles;
        }
      });

    const first = Production.captureProductionClosure(Common.CANONICAL_ROOT,
      "2026-08-11T00:00:00.000Z");
    const second = Production.captureProductionClosure(Common.CANONICAL_ROOT,
      "2026-08-11T00:01:00.000Z");
    test("two current-tree closure captures are stable after timestamp normalization", () => {
      Production.verifyProductionClosure(first, { currentTree: true });
      assert.strictEqual(Evidence.canonicalJson(Production.stableProjection(first)),
        Evidence.canonicalJson(Production.stableProjection(second)));
      const paths = new Set(first.scope.files.map((entry) => entry.relativePath));
      Scope.A5_TOOL_FILES.forEach((relativePath) => assert(paths.has(relativePath), relativePath));
      const materialShopToolRoot = path.join(Common.CANONICAL_ROOT,
        "tools", "workbench-live-e2e", "material-shop");
      const listedA5Tools = new Set(Scope.A5_TOOL_FILES);
      const unlistedFocusedTests = fs.readdirSync(materialShopToolRoot,
        { withFileTypes: true })
        .filter((entry) => entry.isFile() && /^test-.*\.js$/.test(entry.name))
        .map((entry) => "tools/workbench-live-e2e/material-shop/" + entry.name)
        .filter((relativePath) => !listedA5Tools.has(relativePath));
      assert.deepStrictEqual(unlistedFocusedTests, [],
        "every material-shop focused test must be explicitly sealed in A5_TOOL_FILES");
      Scope.MATERIALIZED_BUILD_DRIVER_FILES.forEach((relativePath) =>
        assert(paths.has(relativePath), relativePath));
      assert(paths.has("launcher/perf/package-lock.json"));
      assert(paths.has("tools/workbench-live-e2e/lib/playwright-websocket-toolchain.js"));
    });
    function writeToolchainFixture(name, implementationSource, extra) {
      const fixtureRoot = path.join(testBase, name);
      const perf = path.join(fixtureRoot, "launcher", "perf");
      const core = path.join(perf, "node_modules", "playwright-core");
      const impl = path.join(core, "lib", "utilsBundleImpl");
      fs.mkdirSync(impl, { recursive: true });
      const version = "1.59.1";
      fs.writeFileSync(path.join(perf, "package-lock.json"), JSON.stringify({
        name: "fixture", version: "1.0.0", lockfileVersion: 3, packages: {
          "": { name: "fixture", version: "1.0.0", dependencies: { playwright: "^1.49.0" } },
          "node_modules/playwright": { version,
            resolved: "https://registry.invalid/playwright.tgz", integrity: "sha512-fixture",
            dependencies: { "playwright-core": version } },
          "node_modules/playwright-core": { version,
            resolved: "https://registry.invalid/playwright-core.tgz",
            integrity: "sha512-core-fixture" },
        },
      }), "utf8");
      fs.writeFileSync(path.join(core, "package.json"), JSON.stringify({
        name: "playwright-core", version,
      }), "utf8");
      fs.writeFileSync(path.join(core, "lib", "utilsBundle.js"),
        "module.exports={ws:require('./utilsBundleImpl').ws};\n", "utf8");
      fs.writeFileSync(path.join(impl, "index.js"), implementationSource
        || "class FixtureWebSocket{};FixtureWebSocket.OPEN=1;module.exports={ws:FixtureWebSocket};\n",
      "utf8");
      if (extra && extra.optionalNative) {
        const nativeRoot = path.join(perf, "node_modules", extra.optionalNative);
        fs.mkdirSync(nativeRoot, { recursive: true });
        fs.writeFileSync(path.join(nativeRoot, "index.js"), "module.exports={};\n", "utf8");
      }
      if (extra && extra.foreignModule) {
        fs.writeFileSync(path.join(impl, "foreign.js"), "module.exports={};\n", "utf8");
      }
      return fixtureRoot;
    }
    const toolchainRoot = writeToolchainFixture("playwright-toolchain");
    const toolchainDescriptor = ExternalToolchain.captureDescriptor(toolchainRoot);
    test("external Playwright descriptor binds lock manifest entry and implementation", () => {
      ExternalToolchain.validateDescriptor(toolchainDescriptor, toolchainRoot);
      assert.strictEqual(toolchainDescriptor.files.length, 4);
      assert.deepStrictEqual(toolchainDescriptor.files.map((entry) => entry.role), [
        "package_lock", "installed_package_manifest", "websocket_entry",
        "websocket_implementation",
      ]);
      assert.strictEqual(toolchainDescriptor.package.playwrightCoreVersion, "1.59.1");
    });
    test("guarded Playwright load admits exact two files and restores fallback environment", () => {
      const beforeBuffer = process.env.WS_NO_BUFFER_UTIL;
      const beforeUtf8 = process.env.WS_NO_UTF_8_VALIDATE;
      process.env.WS_NO_BUFFER_UTIL = "prior-buffer-value";
      process.env.WS_NO_UTF_8_VALIDATE = "prior-utf8-value";
      try {
        const loaded = ExternalToolchain.guardedLoad(toolchainDescriptor);
        assert.strictEqual(typeof loaded.WebSocket, "function");
        assert.strictEqual(loaded.WebSocket.OPEN, 1);
        assert.strictEqual(loaded.binding.moduleCache.length, 2);
        assert.strictEqual(process.env.WS_NO_BUFFER_UTIL, "prior-buffer-value");
        assert.strictEqual(process.env.WS_NO_UTF_8_VALIDATE, "prior-utf8-value");
        ExternalToolchain.reverifyLoaded(toolchainDescriptor, loaded.binding);
        toolchainDescriptor.files.filter((entry) => ["websocket_entry",
          "websocket_implementation"].includes(entry.role)).forEach((entry) => {
          delete require.cache[entry.absolutePath];
        });
        const replay = ExternalToolchain.replayRuntimeBinding(
          toolchainDescriptor, loaded.binding);
        assert.strictEqual(replay.binding.bindingSha256, loaded.binding.bindingSha256);
      } finally {
        toolchainDescriptor.files.filter((entry) => ["websocket_entry",
          "websocket_implementation"].includes(entry.role)).forEach((entry) => {
          delete require.cache[entry.absolutePath];
        });
        if (beforeBuffer !== undefined) process.env.WS_NO_BUFFER_UTIL = beforeBuffer;
        else delete process.env.WS_NO_BUFFER_UTIL;
        if (beforeUtf8 !== undefined) process.env.WS_NO_UTF_8_VALIDATE = beforeUtf8;
        else delete process.env.WS_NO_UTF_8_VALIDATE;
      }
    });
    test("guarded load executes retained fd-verified bytes across a path swap", () => {
      const root = writeToolchainFixture("playwright-toolchain-toctou");
      const descriptor = ExternalToolchain.captureDescriptor(root);
      const entry = descriptor.files.find((item) => item.role === "websocket_entry");
      const implementation = descriptor.files.find((item) =>
        item.role === "websocket_implementation");
      const originalBytes = fs.readFileSync(implementation.absolutePath);
      const originalCompile = Module.prototype._compile;
      let swapped = false;
      delete global.__materialShopForeignWebSocketExecuted;
      Module.prototype._compile = function swapDuringCompile(content, filename) {
        if (!swapped && path.resolve(filename).toLowerCase()
            === path.resolve(entry.absolutePath).toLowerCase()) {
          swapped = true;
          fs.writeFileSync(implementation.absolutePath,
            "global.__materialShopForeignWebSocketExecuted=true;"
              + "class Foreign{};Foreign.OPEN=1;module.exports={ws:Foreign};\n", "utf8");
          try { return originalCompile.call(this, content, filename); }
          finally { fs.writeFileSync(implementation.absolutePath, originalBytes); }
        }
        return originalCompile.call(this, content, filename);
      };
      try {
        const loaded = ExternalToolchain.guardedLoad(descriptor);
        assert.strictEqual(swapped, true);
        assert.strictEqual(global.__materialShopForeignWebSocketExecuted, undefined);
        ExternalToolchain.reverifyLoaded(descriptor, loaded.binding);
      } finally {
        Module.prototype._compile = originalCompile;
        fs.writeFileSync(implementation.absolutePath, originalBytes);
        [entry, implementation].forEach((item) => { delete require.cache[item.absolutePath]; });
        delete global.__materialShopForeignWebSocketExecuted;
      }
    });
    negative("external toolchain cannot reuse a foreign protected package lock",
      "playwright_toolchain_package_lock_unbound", () => {
        ExternalToolchain.validateDescriptor(toolchainDescriptor, toolchainRoot, {
          expectedPackageLock: { bytes: 1, sha256: "0".repeat(64) },
        });
      });
    negative("preseeded Playwright require cache fails before guarded load",
      "playwright_toolchain_cache_preseeded", () => {
        const root = writeToolchainFixture("playwright-toolchain-preseed");
        const descriptor = ExternalToolchain.captureDescriptor(root);
        const entry = descriptor.files.find((item) => item.role === "websocket_entry");
        require.cache[entry.absolutePath] = { filename: entry.absolutePath, exports: {} };
        try { ExternalToolchain.guardedLoad(descriptor); }
        finally { delete require.cache[entry.absolutePath]; }
      });
    negative("Playwright descriptor byte drift fails closed",
      "playwright_toolchain_descriptor_drift", () => {
        const root = writeToolchainFixture("playwright-toolchain-drift");
        const descriptor = ExternalToolchain.captureDescriptor(root);
        const impl = descriptor.files.find((item) => item.role === "websocket_implementation");
        fs.appendFileSync(impl.absolutePath, "// drift\n");
        ExternalToolchain.validateDescriptor(descriptor, root);
      });
    negative("foreign Playwright transitive module fails guarded load",
      "playwright_toolchain_transitive_module_forbidden", () => {
        const root = writeToolchainFixture("playwright-toolchain-foreign",
          "require('./foreign');class FixtureWebSocket{};FixtureWebSocket.OPEN=1;"
            + "module.exports={ws:FixtureWebSocket};\n", { foreignModule: true });
        ExternalToolchain.guardedLoad(ExternalToolchain.captureDescriptor(root));
      });
    negative("optional native WebSocket acceleration fails exact fallback policy",
      "playwright_toolchain_optional_native_present", () => {
        const root = writeToolchainFixture("playwright-toolchain-optional", null,
          { optionalNative: "bufferutil" });
        ExternalToolchain.guardedLoad(ExternalToolchain.captureDescriptor(root));
      });
    negative("runtime binding digest swap fails replay",
      "playwright_toolchain_runtime_binding_invalid", () => {
        const root = writeToolchainFixture("playwright-toolchain-binding-swap");
        const descriptor = ExternalToolchain.captureDescriptor(root);
        const loaded = ExternalToolchain.guardedLoad(descriptor);
        const drift = clone(loaded.binding);
        drift.descriptorSha256 = "0".repeat(64);
        reseal(drift, "bindingSha256");
        try { ExternalToolchain.replayRuntimeBinding(descriptor, drift); }
        finally {
          descriptor.files.filter((entry) => ["websocket_entry",
            "websocket_implementation"].includes(entry.role)).forEach((entry) => {
            delete require.cache[entry.absolutePath];
          });
        }
      });
    negative("loaded WebSocket export identity swap fails revalidation",
      "playwright_toolchain_runtime_cache_drift", () => {
        const root = writeToolchainFixture("playwright-toolchain-export-swap");
        const descriptor = ExternalToolchain.captureDescriptor(root);
        const loaded = ExternalToolchain.guardedLoad(descriptor);
        const entry = descriptor.files.find((item) => item.role === "websocket_entry");
        const implementation = descriptor.files.find((item) =>
          item.role === "websocket_implementation");
        const originalExports = require.cache[entry.absolutePath].exports;
        class ForeignWebSocket {}
        ForeignWebSocket.OPEN = 1;
        require.cache[entry.absolutePath].exports = { ws: ForeignWebSocket };
        try { ExternalToolchain.reverifyLoaded(descriptor, loaded.binding); }
        finally {
          require.cache[entry.absolutePath].exports = originalExports;
          [entry, implementation].forEach((item) => { delete require.cache[item.absolutePath]; });
        }
      });
    test("passive recorder has no node_modules resolver and requires explicit injection", () => {
      const passive = fs.readFileSync(path.join(__dirname, "..", "npc",
        "passive-recorder.js"), "utf8");
      assert(!passive.includes("node_modules/playwright-core"));
      assert(passive.includes("options.webSocketImplementation"));
      const runSource = fs.readFileSync(path.join(__dirname, "run-live-journey.js"), "utf8");
      const scopeFence = runSource.indexOf("Materialize.verifyPostBuildProtectedScope");
      const materializedRequire = runSource.indexOf("const NpcPassive = require(passivePath)");
      const guardedLoad = runSource.indexOf("ExternalToolchain.guardedLoad(externalToolchain)");
      const transcript = runSource.indexOf("new NpcPassive.TranscriptWriter(runDir)");
      assert(scopeFence >= 0 && materializedRequire > scopeFence
        && guardedLoad > materializedRequire && transcript > guardedLoad);
    });
    test("build raw journey review and acceptance bind one external descriptor", () => {
      const buildSource = fs.readFileSync(path.join(__dirname, "build-candidate.js"), "utf8");
      const rawSource = fs.readFileSync(path.join(__dirname, "run-live-journey.js"), "utf8");
      const verifierSource = fs.readFileSync(path.join(__dirname, "journey-verifier.js"), "utf8");
      const acceptanceSource = fs.readFileSync(path.join(__dirname, "accept-run.js"), "utf8");
      assert(buildSource.includes("externalToolchain,"));
      assert(rawSource.includes("externalToolchainRuntime: externalRuntime.binding"));
      assert(verifierSource.includes("ExternalToolchain.replayRuntimeBinding"));
      assert(verifierSource.includes("runtimeBindingSha256"));
      assert(acceptanceSource.match(/externalToolchainSha256/g).length >= 6);
    });
    negative("pre-toolchain preparation cannot enter the current live/build loader",
      "material_shop_preparation_invalid", () => {
        const legacyPath = path.join(testBase, "legacy-preparation.json");
        const legacy = { schema: DiscardBuilt.LEGACY_PREPARATION_SCHEMA,
          createdAt: "2026-08-11T00:00:00.000Z", runId: path.basename(testBase),
          root: Common.CANONICAL_ROOT, runDir: testBase,
          resourcesRoot: path.join(testBase, "resources"), slots: {},
          scopeSha256: "1".repeat(64), closureSha256: "2".repeat(64),
          applicabilitySha256: "3".repeat(64), materializationSha256: "4".repeat(64),
          planSha256: "5".repeat(64), artifacts: {}, boundaries: {} };
        legacy.preparationSha256 = Evidence.sha256Text(Evidence.canonicalJson(
          DiscardBuilt.loadAnyPreparation ? legacy : legacy));
        fs.writeFileSync(legacyPath, JSON.stringify(legacy), "utf8");
        Build.loadPreparation(legacyPath);
      });
    negative("current preparation cannot redirect materialized require outside its canonical run",
      "material_shop_preparation_invalid", () => {
        const currentPath = path.join(testBase, "foreign-current-preparation.json");
        const current = { schema: Prepare.PREPARATION_SCHEMA,
          createdAt: "2026-08-11T00:00:00.000Z", runId: "foreign-current-run",
          root: Common.CANONICAL_ROOT, runDir: testBase,
          resourcesRoot: path.join(testBase, "resources"), slots: {},
          scopeSha256: "1".repeat(64), closureSha256: "2".repeat(64),
          externalToolchainSha256: "3".repeat(64), applicabilitySha256: "4".repeat(64),
          materializationSha256: "5".repeat(64), planSha256: "6".repeat(64),
          artifacts: {}, boundaries: {} };
        current.preparationSha256 = Evidence.sha256Text(
          Evidence.canonicalJson(Prepare.stablePreparation(current)));
        fs.writeFileSync(currentPath, JSON.stringify(current), "utf8");
        Build.loadPreparation(currentPath);
      });
    const operationContext = { runDir: testBase, runId: path.basename(testBase),
      preparationSha256: "a".repeat(64), buildSha256: "b".repeat(64) };
    let liveOperationHandle;
    let discardOperationHandle;
    test("live execution atomically acquires the shared per-run operation lease", () => {
      liveOperationHandle = RunOperationLease.acquire(Object.assign({}, operationContext, {
        mode: "live_execution",
      }));
      assert.strictEqual(RunOperationLease.readLease(testBase).lease.mode, "live_execution");
    });
    negative("live-held operation lease rejects concurrent built-only discard",
      "material_shop_run_operation_busy", () => {
        RunOperationLease.acquire(Object.assign({}, operationContext, {
          mode: "built_only_discard",
        }));
      });
    let liveOperationTerminal;
    test("exact live owner release leaves terminal evidence", () => {
      liveOperationTerminal = RunOperationLease.release(liveOperationHandle);
      const terminal = liveOperationTerminal;
      RunOperationLease.validateTerminal(terminal, Object.assign({}, operationContext, {
        mode: "live_execution",
      }));
    });
    negative("terminal live execution cannot re-enter the same run",
      "material_shop_run_operation_live_reentry_forbidden", () => {
        RunOperationLease.acquire(Object.assign({}, operationContext, {
          mode: "live_execution",
        }));
      });
    test("live terminal still permits the discard side to acquire its mutex", () => {
      assert.strictEqual(liveOperationTerminal.mode, "live_execution");
      discardOperationHandle = RunOperationLease.acquire(Object.assign({}, operationContext, {
        mode: "built_only_discard",
      }));
    });
    negative("discard-held operation lease rejects concurrent live execution",
      "material_shop_run_operation_busy", () => {
        RunOperationLease.acquire(Object.assign({}, operationContext, {
          mode: "live_execution",
        }));
      });
    test("discard owner release leaves terminal evidence and zero active lease", () => {
      const terminal = RunOperationLease.release(discardOperationHandle);
      assert.strictEqual(terminal.mode, "built_only_discard");
      assert.strictEqual(RunOperationLease.readLease(testBase).active, false);
      assert(RunOperationLease.historyMarkers(testBase).some((entry) =>
        entry.name === terminal.archiveName && entry.kind === "terminal"));
    });
    test("operation lease byte drift blocks release by the original owner", () => {
      const handle = RunOperationLease.acquire(Object.assign({}, operationContext, {
        mode: "built_only_discard",
      }));
      const original = fs.readFileSync(handle.leasePath);
      fs.appendFileSync(handle.leasePath, "\n");
      let error = null;
      try { RunOperationLease.release(handle); } catch (failure) { error = failure; }
      assert(error);
      assert.strictEqual(error.code, "material_shop_run_operation_lease_drift");
      fs.writeFileSync(handle.leasePath, original);
      RunOperationLease.release(handle);
    });
    negative("stale operation recovery requires explicit acknowledgement",
      "material_shop_run_operation_recovery_ack_required", () => {
        RunOperationLease.recoverStale(testBase, false);
      });
    let staleLeasePath;
    let staleLeaseBytes;
    test("dead-owner operation lease fixture is exact and still active", () => {
      const stale = { schema: RunOperationLease.LEASE_SCHEMA,
        createdAt: "2026-08-11T00:00:00.000Z", runId: path.basename(testBase),
        runDir: testBase, mode: "live_execution",
        preparationSha256: operationContext.preparationSha256,
        buildSha256: operationContext.buildSha256,
        ownerPid: 2147483000, ownerProcessStartUtcTicks: "638900000000000001",
        ownerNonceSha256: "c".repeat(64) };
      reseal(stale, "leaseSha256");
      staleLeasePath = path.join(testBase, RunOperationLease.LEASE_NAME);
      fs.writeFileSync(staleLeasePath,
        JSON.stringify(stale, null, 2) + "\n", { encoding: "utf8", flag: "wx" });
      staleLeaseBytes = fs.readFileSync(staleLeasePath);
    });
    negative("process-probe command failure cannot recover or move an operation lease",
      "material_shop_run_operation_not_stale", () => {
      const originalSpawn = childProcess.spawnSync;
      try {
        childProcess.spawnSync = () => ({ error: new Error("probe unavailable"),
          status: null, stdout: "", stderr: "" });
        RunOperationLease.recoverStale(testBase, true);
      } finally {
        childProcess.spawnSync = originalSpawn;
        assert.deepStrictEqual(fs.readFileSync(staleLeasePath), staleLeaseBytes);
      }
    });
    negative("unverifiable process StartTime cannot recover or move an operation lease",
      "material_shop_run_operation_not_stale", () => {
      const originalSpawn = childProcess.spawnSync;
      try {
        childProcess.spawnSync = () => ({ error: null, status: 0,
          stdout: '{"state":"unverifiable","ticks":null}\n', stderr: "" });
        RunOperationLease.recoverStale(testBase, true);
      } finally {
        childProcess.spawnSync = originalSpawn;
        assert.deepStrictEqual(fs.readFileSync(staleLeasePath), staleLeaseBytes);
      }
    });
    negative("nonzero process-probe result cannot recover or move an operation lease",
      "material_shop_run_operation_not_stale", () => {
      const originalSpawn = childProcess.spawnSync;
      try {
        childProcess.spawnSync = () => ({ error: null, status: 5,
          stdout: "", stderr: "access denied" });
        RunOperationLease.recoverStale(testBase, true);
      } finally {
        childProcess.spawnSync = originalSpawn;
        assert.deepStrictEqual(fs.readFileSync(staleLeasePath), staleLeaseBytes);
      }
    });
    negative("malformed process-probe output cannot recover or move an operation lease",
      "material_shop_run_operation_not_stale", () => {
      const originalSpawn = childProcess.spawnSync;
      try {
        childProcess.spawnSync = () => ({ error: null, status: 0,
          stdout: "not-json\n", stderr: "" });
        RunOperationLease.recoverStale(testBase, true);
      } finally {
        childProcess.spawnSync = originalSpawn;
        assert.deepStrictEqual(fs.readFileSync(staleLeasePath), staleLeaseBytes);
      }
    });
    test("explicit stale recovery archives a definitely missing owner without deleting worktree data", () => {
      const recovered = RunOperationLease.recoverStale(testBase, true);
      assert.strictEqual(recovered.active, false);
      assert.strictEqual(RunOperationLease.readLease(testBase).active, false);
      assert(RunOperationLease.historyMarkers(testBase).some((entry) =>
        entry.name === recovered.resolvedPath && entry.kind === "stale_recovery"));
    });
    test("explicit stale recovery admits one exact PID-reused owner identity", () => {
      const reused = { schema: RunOperationLease.LEASE_SCHEMA,
        createdAt: "2026-08-11T00:00:01.000Z", runId: path.basename(testBase),
        runDir: testBase, mode: "live_execution",
        preparationSha256: operationContext.preparationSha256,
        buildSha256: operationContext.buildSha256,
        ownerPid: process.pid, ownerProcessStartUtcTicks: "100000000000",
        ownerNonceSha256: "8".repeat(64) };
      reseal(reused, "leaseSha256");
      fs.writeFileSync(path.join(testBase, RunOperationLease.LEASE_NAME),
        JSON.stringify(reused, null, 2) + "\n", { encoding: "utf8", flag: "wx" });
      const recovered = RunOperationLease.recoverStale(testBase, true);
      assert.strictEqual(recovered.ownerState, "pid_reused");
      assert.strictEqual(recovered.leaseSha256, reused.leaseSha256);
    });
    negative("stale-recovered live execution cannot re-enter the same run",
      "material_shop_run_operation_live_reentry_forbidden", () => {
        RunOperationLease.acquire(Object.assign({}, operationContext, {
          mode: "live_execution",
        }));
      });
    test("pre-execution fence cancellation leaves no live terminal evidence", () => {
      const cancelContext = { runDir: operationCancelBase,
        runId: path.basename(operationCancelBase), preparationSha256: "f".repeat(64),
        buildSha256: "9".repeat(64), mode: "live_execution" };
      const handle = RunOperationLease.acquire(cancelContext);
      const blocker = path.join(operationCancelBase, DiscardBuilt.RECEIPT_NAME);
      fs.writeFileSync(blocker, "{}\n", { encoding: "utf8", flag: "wx" });
      let fenceError = null;
      try { DiscardBuilt.assertLiveExecutionAvailable(operationCancelBase); }
      catch (error) {
        fenceError = error;
        RunOperationLease.cancelBeforeExecution(handle);
      } finally { fs.unlinkSync(blocker); }
      assert(fenceError);
      assert.strictEqual(fenceError.code, "material_shop_run_blocked_by_built_discard");
      assert.strictEqual(RunOperationLease.readLease(operationCancelBase).active, false);
      assert.deepStrictEqual(RunOperationLease.historyMarkers(operationCancelBase), []);
    });
    negative("execution-started live lease cannot be cancelled as admission-only",
      "material_shop_run_operation_cancel_forbidden", () => {
        const handle = RunOperationLease.acquire({ runDir: operationCancelBase,
          runId: path.basename(operationCancelBase), preparationSha256: "f".repeat(64),
          buildSha256: "9".repeat(64), mode: "live_execution" });
        RunOperationLease.markExecutionStarted(handle);
        try { RunOperationLease.cancelBeforeExecution(handle); }
        finally { RunOperationLease.release(handle); }
      });
    test("live and discard hold one lease across materialized require and exact removal windows", () => {
      const liveSource = fs.readFileSync(path.join(__dirname, "run-live-journey.js"), "utf8");
      const ownedDefinition = liveSource.indexOf("async function executeOwned");
      const materializedRequire = liveSource.indexOf("loadMaterializedRuntimeModules",
        ownedDefinition);
      const cloneReleaseReceipt = liveSource.indexOf("FinalizeCloneRelease.writeReleaseReceipt",
        materializedRequire);
      const liveRelease = liveSource.indexOf("RunOperationLease.release(operationHandle)",
        cloneReleaseReceipt);
      const liveAcquire = liveSource.indexOf("RunOperationLease.acquire");
      const ownedCall = liveSource.indexOf("executeOwned(args, preparation, operationHandle,",
        liveAcquire);
      const discardSource = fs.readFileSync(path.join(__dirname, "discard-built-run.js"), "utf8");
      const discardAcquire = discardSource.indexOf("RunOperationLease.acquire");
      const firstContext = discardSource.indexOf("const context = loadContext", discardAcquire);
      const exactRemove = discardSource.indexOf("runGitRemove(fresh.preparation.resourcesRoot)");
      const discardRelease = discardSource.indexOf("RunOperationLease.release(operationHandle)",
        exactRemove);
      assert(ownedDefinition >= 0 && materializedRequire > ownedDefinition
        && cloneReleaseReceipt > materializedRequire && liveRelease > cloneReleaseReceipt);
      assert(liveAcquire >= 0 && ownedCall > liveAcquire);
      assert(discardAcquire >= 0 && firstContext > discardAcquire
        && exactRemove > firstContext && discardRelease > exactRemove);
    });
    test("materialized BuildOnly driver closure reads every exact current file", () => {
      const descriptors = Scope.buildDriverDescriptors(Common.CANONICAL_ROOT);
      assert.deepStrictEqual(descriptors.map((entry) => entry.relativePath),
        Scope.MATERIALIZED_BUILD_DRIVER_FILES);
    });
    test("every materialized BuildOnly driver is individually required", () => {
      Scope.MATERIALIZED_BUILD_DRIVER_FILES.forEach((missingPath, index) => {
        const missingRoot = path.join(testBase, "missing-build-driver-" + index);
        Scope.MATERIALIZED_BUILD_DRIVER_FILES.filter((entry) => entry !== missingPath)
          .forEach((relativePath) => {
            const source = Common.resolveWithin(Common.CANONICAL_ROOT, relativePath,
              "self_test").absolute;
            const target = Common.resolveWithin(missingRoot, relativePath,
              "self_test").absolute;
            fs.mkdirSync(path.dirname(target), { recursive: true });
            fs.copyFileSync(source, target);
          });
        let thrown = null;
        try { Scope.buildDriverDescriptors(missingRoot); } catch (error) { thrown = error; }
        assert(thrown, missingPath + " did not fail closed when absent");
        assert.strictEqual(thrown.code, "material_shop_scope_file_missing", thrown.stack);
      });
    });
    test("each materialized BuildOnly driver rejects a HEAD-stale byte", () => {
      Scope.MATERIALIZED_BUILD_DRIVER_FILES.forEach((relativePath, index) => {
        const staleRoot = path.join(testBase, "head-stale-build-driver-" + index);
        const stalePath = Common.resolveWithin(staleRoot, relativePath, "self_test").absolute;
        fs.mkdirSync(path.dirname(stalePath), { recursive: true });
        const head = childProcess.spawnSync("git", ["show", "HEAD:" + relativePath], {
          cwd: Common.CANONICAL_ROOT, windowsHide: true, encoding: null,
          maxBuffer: 16 * 1024 * 1024,
        });
        assert.strictEqual(head.status, 0, String(head.stderr || ""));
        const currentTreeOnly = Buffer.concat([head.stdout,
          Buffer.from("\n# material-shop-current-tree-only\n", "utf8")]);
        fs.writeFileSync(stalePath, head.stdout);
        let thrown = null;
        try {
          Materialize.verifyScopeFiles(staleRoot,
            syntheticScope(staleRoot, relativePath, currentTreeOnly, first.head));
        } catch (error) { thrown = error; }
        assert(thrown, relativePath + " accepted a HEAD-stale byte");
        assert.strictEqual(thrown.code, "material_shop_worktree_scope_mismatch", thrown.stack);
      });
    });
    test("shared producer/static entrypoints expand to an exact local require closure", () => {
      const descriptors = Scope.sharedProducerDescriptors(Common.CANONICAL_ROOT);
      const paths = new Set(descriptors.map((entry) => entry.relativePath));
      Scope.SHARED_PRODUCER_ENTRYPOINTS.forEach((entry) =>
        assert(paths.has(entry.relativePath), entry.relativePath));
      assert(paths.has("tools/run-crafting-harness.js"));
      assert(paths.has("tools/workbench-live-e2e/npc/production-closure.js"));
      assert(paths.has("tools/workbench-live-e2e/npc/shared-adapter.js"));
      assert(descriptors.length > Scope.SHARED_PRODUCER_ENTRYPOINTS.length);
      const binding = Production.captureMaterializedSharedProducers(Common.CANONICAL_ROOT, first);
      Production.verifyMaterializedSharedProducers(binding, Common.CANONICAL_ROOT, first);
      assert.strictEqual(binding.files.length, first.sharedProducers.fileCount);
      assert(first.sharedProducers.fileCount > Scope.SHARED_PRODUCER_ENTRYPOINTS.length);
      assert.strictEqual(Build.loadMaterializedProduction({ resourcesRoot: Common.CANONICAL_ROOT },
        first).binding.bindingSha256, binding.bindingSha256);
      const runtime = LiveRun.loadMaterializedRuntimeModules({
        resourcesRoot: Common.CANONICAL_ROOT }, first);
      assert.strictEqual(runtime.producerBinding.bindingSha256, binding.bindingSha256);
    });
    negative("missing static local producer dependency fails scope capture",
      "material_shop_shared_producer_dependency_missing", () => {
        const dependencyRoot = path.join(testBase, "missing-producer-dependency");
        fs.mkdirSync(dependencyRoot);
        fs.writeFileSync(path.join(dependencyRoot, "entry.js"),
          "require('./missing-dependency');\n", "utf8");
        Scope.sharedProducerDescriptors(dependencyRoot,
          [{ role: "fixture_entrypoint", relativePath: "entry.js" }]);
      });
    negative("HEAD-stale transitive producer byte cannot bind materialized evidence",
      "material_shop_materialized_producer_drift", () => {
        const staleRoot = path.join(testBase, "head-stale-producer");
        first.sharedProducers.files.forEach((entry) => {
          const source = Common.resolveWithin(Common.CANONICAL_ROOT, entry.relativePath,
            "self_test").absolute;
          const target = Common.resolveWithin(staleRoot, entry.relativePath, "self_test").absolute;
          fs.mkdirSync(path.dirname(target), { recursive: true });
          fs.copyFileSync(source, target);
        });
        const dependency = "tools/workbench-live-e2e/npc/production-closure.js";
        const head = childProcess.spawnSync("git", ["show", "HEAD:" + dependency], {
          cwd: Common.CANONICAL_ROOT, windowsHide: true, encoding: null,
          maxBuffer: 16 * 1024 * 1024,
        });
        assert.strictEqual(head.status, 0, String(head.stderr || ""));
        const stalePath = Common.resolveWithin(staleRoot, dependency, "self_test").absolute;
        assert.notStrictEqual(Evidence.sha256Bytes(head.stdout),
          Evidence.sha256File(stalePath));
        fs.writeFileSync(stalePath, head.stdout);
        Production.captureMaterializedSharedProducers(staleRoot, first);
      });
    negative("closure byte digest drift fails", "material_shop_production_closure_invalid", () => {
      const drift = clone(first);
      drift.scope.files[0].sha256 = "0".repeat(64);
      Production.verifyProductionClosure(drift, { currentTree: false });
    });

    test("canonical root passes real Worktree build identity probe", () => {
      const identity = Materialize.captureWorktreeBuildIdentity(Common.CANONICAL_ROOT);
      assert.strictEqual(identity.schema, "cf7-runtime-build-identity.v2");
      assert(/^[A-F0-9]{64}$/.test(identity.buildIdentityHash));
    });

    const productionLikeBase = path.join(testBase, "production-like-zero-base");
    fs.mkdirSync(path.join(productionLikeBase, "CRAZYFLASHER7MercenaryEmpire"), {
      recursive: true,
    });
    const zeroBaseFile = path.join(productionLikeBase,
      "CRAZYFLASHER7MercenaryEmpire", "MobileSettings.xml");
    fs.writeFileSync(zeroBaseFile, Buffer.alloc(0));
    test("production-like tracked base accepts exact zero-byte regular files", () => {
      const exact = Materialize.readExactTreeFile(zeroBaseFile, { maximumBytes: 1 });
      assert.strictEqual(exact.length, 0);
      assert.strictEqual(exact.sha256,
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
      assert.deepStrictEqual(Materialize.collectDestinationFiles(productionLikeBase), [{
        relativePath: "CRAZYFLASHER7MercenaryEmpire/MobileSettings.xml",
        bytes: 0, sha256: exact.sha256,
      }]);
    });
    negative("shared evidence artifacts remain non-empty after tree reader specialization",
      "exact_file_invalid", () => {
        Evidence.readExactRegularFile(zeroBaseFile, { phase: "self_test", maximumBytes: 1 });
      });
    const oversizeBaseFile = path.join(productionLikeBase, "oversize.bin");
    fs.writeFileSync(oversizeBaseFile, Buffer.from([1, 2]));
    negative("production base exact reader rejects bytes above its declared limit",
      "material_shop_tree_file_invalid", () => {
        Materialize.readExactTreeFile(oversizeBaseFile, { maximumBytes: 1 });
      });
    negative("production base exact reader rejects a zero byte limit",
      "material_shop_tree_file_limit_invalid", () => {
        Materialize.readExactTreeFile(zeroBaseFile, { maximumBytes: 0 });
      });
    const reparseTarget = path.join(testBase, "tree-reader-reparse-target");
    const reparseParent = path.join(testBase, "tree-reader-reparse-parent");
    const reparseLink = path.join(reparseParent, "redirect");
    fs.mkdirSync(reparseTarget);
    fs.mkdirSync(reparseParent);
    fs.writeFileSync(path.join(reparseTarget, "empty.bin"), Buffer.alloc(0));
    fs.symlinkSync(reparseTarget, reparseLink, "junction");
    negative("production base exact reader rejects a reparse-parent path",
      "material_shop_tree_file_invalid", () => {
        Materialize.readExactTreeFile(path.join(reparseLink, "empty.bin"), {
          maximumBytes: 1,
        });
      });
    fs.unlinkSync(reparseLink);

    const unicodeTreeRoot = path.join(testBase, "unicode-tree-root");
    fs.mkdirSync(unicodeTreeRoot);
    test("scope-bound repository parents admit production-like Unicode names", () => {
      const parent = Materialize.ensureDestinationParent(unicodeTreeRoot,
        "data/crafting/公社装备/公社防具.json");
      assert.strictEqual(parent, path.join(unicodeTreeRoot, "data", "crafting", "公社装备"));
      ["data", path.join("data", "crafting"),
        path.join("data", "crafting", "公社装备")].forEach((relative) => {
        const directory = path.join(unicodeTreeRoot, relative);
        const stat = fs.lstatSync(directory);
        assert(stat.isDirectory());
        assert.strictEqual(stat.isSymbolicLink(), false);
        assert.strictEqual(fs.realpathSync.native(directory).toLowerCase(),
          path.resolve(directory).toLowerCase());
      });
    });
    negative("scope-bound repository parent rejects traversal",
      "material_shop_relative_path_invalid", () => {
        Materialize.ensureDestinationParent(unicodeTreeRoot,
          "data/crafting/../../foreign/公社防具.json");
      });
    negative("scope-bound repository parent rejects a foreign absolute path",
      "material_shop_relative_path_invalid", () => {
        Materialize.ensureDestinationParent(unicodeTreeRoot,
          path.resolve(testBase, "foreign-tree", "公社防具.json"));
      });
    const unicodeReparseRoot = path.join(testBase, "unicode-reparse-root");
    const unicodeReparseTarget = path.join(testBase, "unicode-reparse-target");
    const unicodeReparseLink = path.join(unicodeReparseRoot, "data");
    fs.mkdirSync(unicodeReparseRoot);
    fs.mkdirSync(unicodeReparseTarget);
    fs.symlinkSync(unicodeReparseTarget, unicodeReparseLink,
      process.platform === "win32" ? "junction" : "dir");
    negative("scope-bound repository parent rejects a reparse directory",
      "material_shop_materialize_directory_invalid", () => {
        Materialize.ensureDestinationParent(unicodeReparseRoot,
          "data/crafting/公社防具.json");
      });
    fs.unlinkSync(unicodeReparseLink);
    negative("owned control directory names remain an ASCII closed set",
      "material_shop_materialize_directory_name_invalid", () => {
        Materialize.ensureDirectDirectoryChain(unicodeTreeRoot,
          path.join(unicodeTreeRoot, "中文控制目录"), "self_test");
      });

    const recoveryRunId = path.basename(testBase);
    const recoveryDestination = path.join(owned, Materialize.MATERIALIZED_DIRECTORY,
      recoveryRunId, "resources");
    const creationIntent = Materialize.createCreationIntent({ runId: recoveryRunId,
      runDir: testBase, ownedBase: owned, destination: recoveryDestination,
      scope: first.scope });
    test("materialization intent binds exact run destination scope and argv", () => {
      assert.strictEqual(Materialize.validateCreationIntent(creationIntent), creationIntent);
      assert.deepStrictEqual(creationIntent.removeCommand,
        ["git", "worktree", "remove", "--force", recoveryDestination]);
      assert.deepStrictEqual(creationIntent.cleanupCommand.slice(0, 3),
        ["node", "tools/workbench-live-e2e/material-shop/materialize.js",
          "--cleanup-failed-materialization"]);
    });
    negative("sibling destination cannot reuse materialization recovery intent",
      "material_shop_materialization_intent_invalid", () => {
        const drift = clone(creationIntent);
        drift.destination = path.join(owned, Materialize.MATERIALIZED_DIRECTORY,
          recoveryRunId + "-sibling", "resources");
        drift.removeCommand[4] = drift.destination;
        reseal(drift, "intentSha256");
        Materialize.validateCreationIntent(drift);
      });
    negative("materialization marker byte drift fails its sealed digest",
      "material_shop_materialization_intent_invalid", () => {
        const drift = clone(creationIntent);
        drift.head = "0".repeat(40);
        Materialize.validateCreationIntent(drift);
      });
    negative("case-folded duplicate scope path cannot enter recovery authority",
      "material_shop_materialization_intent_invalid", () => {
        const drift = clone(creationIntent);
        drift.scopePaths.push(drift.scopePaths[0].toUpperCase());
        drift.scopePaths.sort();
        drift.scopePathsSha256 = Evidence.sha256Text(Evidence.canonicalJson(drift.scopePaths));
        reseal(drift, "intentSha256");
        Materialize.validateCreationIntent(drift);
      });
    test("cleanup presence admits only both-present retry or both-absent finalization", () => {
      assert.strictEqual(Materialize.cleanupPresence(true, true), "present");
      assert.strictEqual(Materialize.cleanupPresence(false, false), "absent");
    });
    negative("filesystem-only failed worktree state blocks cleanup",
      "material_shop_materialization_cleanup_partial_state", () => {
        Materialize.cleanupPresence(true, false);
      });
    negative("Git-only failed worktree state blocks cleanup",
      "material_shop_materialization_cleanup_partial_state", () => {
        Materialize.cleanupPresence(false, true);
      });
    negative("scope-external dirty path blocks failed worktree cleanup",
      "material_shop_materialization_cleanup_tree_invalid", () => {
        Materialize.assertCleanupDirtyPaths(creationIntent, { staged: [], modified: [],
          untracked: ["foreign.bin"], ignored: [] });
      });
    negative("staged path blocks failed worktree cleanup",
      "material_shop_materialization_cleanup_tree_invalid", () => {
        Materialize.assertCleanupDirtyPaths(creationIntent, {
          staged: [creationIntent.scopePaths[0]], modified: [], untracked: [], ignored: [],
        });
      });
    const allowedProbePath = creationIntent.scopePaths[0];
    function cleanupProbe(bytes, sha256) {
      const files = [{ relativePath: allowedProbePath, bytes, sha256 }];
      return { identity: { head: creationIntent.head }, modified: [allowedProbePath],
        untracked: [], ignored: [], fileCount: 1, totalBytes: bytes,
        filesSha256: Materialize.filesDigest(files) };
    }
    negative("same allowed cleanup path changing zero to nonzero bytes blocks removal",
      "material_shop_materialization_cleanup_tree_invalid", () => {
        Materialize.assertStableCleanupProbes(cleanupProbe(0,
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        cleanupProbe(1, Evidence.sha256Bytes(Buffer.from([1]))));
      });
    negative("same allowed cleanup path changing nonzero to zero bytes blocks removal",
      "material_shop_materialization_cleanup_tree_invalid", () => {
        Materialize.assertStableCleanupProbes(
          cleanupProbe(1, Evidence.sha256Bytes(Buffer.from([1]))), cleanupProbe(0,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"));
      });
    const stagedCreation = path.join(testBase,
      Materialize.CREATION_INTENT_NAME + ".staged-" + "0".repeat(16));
    fs.writeFileSync(stagedCreation, "staged\n", "utf8");
    negative("interrupted staged creation marker blocks silent recovery",
      "material_shop_materialization_recovery_state_invalid", () => {
        Materialize.loadCreationState(testBase);
      });
    fs.unlinkSync(stagedCreation);
    Materialize.writeJsonAtomicNew(path.join(testBase, Materialize.CREATION_INTENT_NAME),
      creationIntent);
    let producerHandle;
    test("materialization producer lease is active before any worktree side effect", () => {
      producerHandle = Materialize.acquireMaterializationProducer(testBase);
      const producer = Materialize.readMaterializationProducer(testBase);
      assert.strictEqual(producer.kind, "active");
      assert.strictEqual(producer.ownerState, "same_process");
      assert.strictEqual(producer.lease.intentSha256, creationIntent.intentSha256);
    });
    negative("active materialization producer blocks failed-worktree cleanup",
      "material_shop_materialization_producer_busy", () => {
        Materialize.cleanupFailedMaterialization(testBase, { acknowledge: true });
      });
    negative("shallow fake materialization cannot resolve a creation marker",
      "material_shop_materialization_receipt_invalid", () => {
        Materialize.resolveCreationIntent(testBase, { mode: Materialize.PRODUCTION_MODE,
          destination: recoveryDestination, head: first.head,
          scopeSha256: first.scope.scopeSha256 }, first.scope);
      });
    negative("failed worktree cleanup requires explicit acknowledgement",
      "material_shop_materialization_cleanup_ack_required", () => {
        Materialize.cleanupFailedMaterialization(testBase);
      });
    test("failed resolution archives the exact producer and permits failed-worktree cleanup", () => {
      const terminal = Materialize.readMaterializationProducer(testBase);
      assert.strictEqual(terminal.kind, "terminal");
      assert.strictEqual(producerHandle.active, false);
      assert.strictEqual(terminal.lease.intentSha256, creationIntent.intentSha256);
    });
    test("post-remove receipt failure keeps intent and finalizes idempotently", () => {
      let writeError = null;
      try {
        Materialize.cleanupFailedMaterialization(testBase, { acknowledge: true,
          writeReceipt: () => {
            throw Object.assign(new Error("simulated materialization cleanup receipt failure"), {
              code: "simulated_materialization_cleanup_receipt_failure",
            });
          } });
      } catch (error) { writeError = error; }
      assert(writeError);
      assert.strictEqual(writeError.code,
        "simulated_materialization_cleanup_receipt_failure");
      assert(fs.existsSync(path.join(testBase, Materialize.CREATION_INTENT_NAME)));
      assert(!fs.existsSync(path.join(testBase, Materialize.CLEANUP_RECEIPT_NAME)));
      const receipt = Materialize.cleanupFailedMaterialization(testBase, {
        acknowledge: true,
      });
      const replay = Materialize.cleanupFailedMaterialization(testBase, {
        acknowledge: true,
      });
      assert.strictEqual(replay.cleanupSha256, receipt.cleanupSha256);
      assert(fs.existsSync(path.join(testBase,
        Materialize.cleanupResolvedName(creationIntent))));
    });
    test("active and resolved materialization markers cannot coexist", () => {
      const resolved = path.join(testBase, Materialize.cleanupResolvedName(creationIntent));
      fs.copyFileSync(resolved, path.join(testBase, Materialize.CREATION_INTENT_NAME));
      let error = null;
      try { Materialize.loadCreationState(testBase); } catch (failure) { error = failure; }
      finally { fs.unlinkSync(path.join(testBase, Materialize.CREATION_INTENT_NAME)); }
      assert(error);
      assert.strictEqual(error.code, "material_shop_materialization_recovery_state_invalid");
    });
    negative("cleanup CLI without destructive acknowledgement fails",
      "material_shop_materialization_recovery_arguments_invalid", () => {
        Materialize.parseRecoveryArgs(["--cleanup-failed-materialization",
          "--run-dir", testBase]);
      });
    test("creation intent precedes worktree add and cleanup never prunes or recursively deletes",
      () => {
        const source = fs.readFileSync(path.join(__dirname, "materialize.js"), "utf8");
        const materialize = source.indexOf("function materializeScope");
        const intentWrite = source.indexOf("writeJsonAtomicNew(path.join(runDir",
          materialize);
        const producerLease = source.indexOf("acquireMaterializationProducer(runDir)",
          intentWrite);
        const add = source.indexOf('["worktree", "add", "--detach"', intentWrite);
        const cleanup = source.indexOf("function cleanupFailedMaterialization");
        const verify = source.indexOf("verifyFailedMaterializationWorktree(intent)", cleanup);
        const remove = source.indexOf('["worktree", "remove", "--force"', verify);
        assert(materialize >= 0 && intentWrite > materialize
          && producerLease > intentWrite && add > producerLease);
        const resolve = source.indexOf("function resolveCreationIntent");
        const resolveArchive = source.indexOf("fs.renameSync(state.markerPath",
          resolve);
        const producerArchive = source.indexOf(
          "releaseMaterializationProducer(producerHandle)", resolveArchive);
        assert(resolve >= 0 && resolveArchive > resolve
          && producerArchive > resolveArchive && producerArchive < materialize);
        assert(cleanup >= 0 && verify > cleanup && remove > verify);
        assert(!source.includes('"worktree", "prune"'));
        assert(!source.includes("fs.rmSync"));
      });

    const producerRunId = path.basename(producerLeaseBase);
    const producerDestination = path.join(owned, Materialize.MATERIALIZED_DIRECTORY,
      producerRunId, "resources");
    const producerIntent = Materialize.createCreationIntent({ runId: producerRunId,
      runDir: producerLeaseBase, ownedBase: owned, destination: producerDestination,
      scope: first.scope });
    Materialize.writeJsonAtomicNew(path.join(producerLeaseBase,
      Materialize.CREATION_INTENT_NAME), producerIntent);
    const staleProducerLease = Materialize.createMaterializationProducerLease(producerIntent, {
      createdAt: "2026-08-12T00:00:00.000Z", ownerPid: 2147483000,
      ownerProcessStartUtcTicks: "638900000000000001",
      ownerNonceSha256: "7".repeat(64),
    });
    fs.writeFileSync(path.join(producerLeaseBase, Materialize.PRODUCER_LEASE_NAME),
      JSON.stringify(staleProducerLease, null, 2) + "\n", { encoding: "utf8", flag: "wx" });
    negative("unverifiable materialization producer cannot be recovered or cleaned",
      "material_shop_materialization_producer_not_stale", () => {
        Materialize.recoverStaleMaterializationProducer(producerLeaseBase, {
          acknowledge: true, processProbe: () => ({ state: "unverifiable", ticks: null }),
        });
      });
    negative("definitely missing producer still requires explicit stale acknowledgement",
      "material_shop_materialization_producer_recovery_ack_required", () => {
        Materialize.recoverStaleMaterializationProducer(producerLeaseBase, {
          acknowledge: false, processProbe: () => ({ state: "not_found", ticks: null }),
        });
      });
    negative("stale active producer blocks cleanup until its explicit recovery",
      "material_shop_materialization_producer_recovery_required", () => {
        Materialize.cleanupFailedMaterialization(producerLeaseBase, { acknowledge: true,
          producerOptions: { processProbe: () => ({ state: "not_found", ticks: null }) } });
      });
    test("explicit stale producer recovery archives exact owner evidence", () => {
      const recovered = Materialize.recoverStaleMaterializationProducer(producerLeaseBase, {
        acknowledge: true, processProbe: () => ({ state: "not_found", ticks: null }),
      });
      assert.strictEqual(recovered.kind, "stale_recovery");
      assert.strictEqual(recovered.lease.leaseSha256, staleProducerLease.leaseSha256);
      assert.strictEqual(fs.existsSync(path.join(producerLeaseBase,
        Materialize.PRODUCER_LEASE_NAME)), false);
    });
    test("stale-recovered producer permits exact absent-worktree cleanup", () => {
      const receipt = Materialize.cleanupFailedMaterialization(producerLeaseBase, {
        acknowledge: true,
      });
      assert.strictEqual(receipt.producerKind, "stale_recovery");
      assert.strictEqual(receipt.producerLeaseSha256, staleProducerLease.leaseSha256);
      assert.strictEqual(receipt.worktreeAbsent, true);
    });
    negative("producer inspection cannot be combined with destructive acknowledgement",
      "material_shop_materialization_recovery_arguments_invalid", () => {
        Materialize.parseRecoveryArgs(["--inspect-materialization-producer",
          "--run-dir", producerLeaseBase, "--acknowledge-stale-materialization-producer"]);
      });
    test("producer recovery CLI requires one explicit typed mode", () => {
      assert.deepStrictEqual(Materialize.parseRecoveryArgs([
        "--recover-stale-materialization-producer", "--run-dir", producerLeaseBase,
        "--acknowledge-stale-materialization-producer"]), {
        mode: "recover_producer", runDir: producerLeaseBase, acknowledge: true,
      });
    });
    const preparedFinalizationContext = {
      state: { runDir: producerLeaseBase, intent: producerIntent },
      preparation: { runId: producerRunId, preparationSha256: "9".repeat(64) },
      preparationFile: { sha256: "a".repeat(64) },
      materialization: { materializationSha256: "b".repeat(64) },
      scope: { scopeSha256: first.scope.scopeSha256 },
      producer: { kind: "stale_recovery",
        name: Materialize.producerStaleName(staleProducerLease),
        lease: staleProducerLease, artifact: { sha256: "c".repeat(64) } },
    };
    const preparedFinalization = Materialize.preparedMaterializationFinalizationReceipt(
      preparedFinalizationContext, "2026-08-12T00:02:00.000Z");
    test("typed stale preparation finalization binds preparation materialization and producer", () => {
      assert.strictEqual(Materialize.validatePreparedMaterializationFinalization(
        preparedFinalization, preparedFinalizationContext), preparedFinalization);
      assert.strictEqual(preparedFinalization.producerKind, "stale_recovery");
      assert.strictEqual(preparedFinalization.intentSha256, producerIntent.intentSha256);
    });
    negative("terminal producer cannot masquerade as typed stale finalization",
      "material_shop_preparation_finalization_invalid", () => {
        const context = clone(preparedFinalizationContext);
        context.producer.kind = "terminal";
        context.producer.name = Materialize.producerTerminalName(staleProducerLease);
        Materialize.preparedMaterializationFinalizationReceipt(context,
          "2026-08-12T00:02:00.000Z");
      });
    negative("typed preparation finalization digest drift fails closed",
      "material_shop_preparation_finalization_invalid", () => {
        const drift = clone(preparedFinalization);
        drift.preparationArtifactSha256 = "d".repeat(64);
        Materialize.validatePreparedMaterializationFinalization(drift,
          preparedFinalizationContext);
      });
    test("stale preparation finalization CLI is explicit and acknowledged", () => {
      assert.deepStrictEqual(Materialize.parseRecoveryArgs([
        "--finalize-stale-preparation", "--run-dir", producerLeaseBase,
        "--acknowledge-stale-preparation-finalization"]), {
        mode: "finalize_preparation", runDir: producerLeaseBase, acknowledge: true,
      });
    });
    negative("stale preparation finalization CLI requires acknowledgement",
      "material_shop_materialization_recovery_arguments_invalid", () => {
        Materialize.parseRecoveryArgs([
          "--finalize-stale-preparation", "--run-dir", producerLeaseBase]);
      });
    negative("producer recovery cannot borrow failed-worktree acknowledgement",
      "material_shop_materialization_recovery_arguments_invalid", () => {
        Materialize.parseRecoveryArgs([
          "--recover-stale-materialization-producer", "--run-dir", producerLeaseBase,
          "--acknowledge-remove-failed-worktree"]);
      });
    negative("preparation finalization cannot borrow producer acknowledgement",
      "material_shop_materialization_recovery_arguments_invalid", () => {
        Materialize.parseRecoveryArgs([
          "--finalize-stale-preparation", "--run-dir", producerLeaseBase,
          "--acknowledge-stale-materialization-producer"]);
      });
    negative("materialization recovery rejects multiple acknowledgement flags",
      "material_shop_materialization_recovery_arguments_invalid", () => {
        Materialize.parseRecoveryArgs([
          "--cleanup-failed-materialization", "--run-dir", producerLeaseBase,
          "--acknowledge-remove-failed-worktree",
          "--acknowledge-stale-materialization-producer"]);
      });
    negative("materialization recovery rejects multiple mode flags",
      "material_shop_materialization_recovery_arguments_invalid", () => {
        Materialize.parseRecoveryArgs([
          "--cleanup-failed-materialization",
          "--recover-stale-materialization-producer", "--run-dir", producerLeaseBase,
          "--acknowledge-stale-materialization-producer"]);
      });
    test("foreign finalization output is fenced before creation marker resolution", () => {
      const source = fs.readFileSync(path.join(__dirname, "materialize.js"), "utf8");
      const start = source.indexOf("function finalizeStalePreparedMaterialization");
      const outputFence = source.indexOf("context.state.active && fs.existsSync(output)", start);
      const markerRename = source.indexOf("fs.renameSync(context.state.markerPath", start);
      assert(start >= 0 && outputFence > start && markerRename > outputFence);
    });
    test("Build accepts stale producer only through exact finalization replay", () => {
      const source = fs.readFileSync(path.join(__dirname, "build-candidate.js"), "utf8");
      const producer = source.indexOf("readMaterializationProducer(value.runDir");
      const finalization = source.indexOf("loadPreparedMaterializationFinalization", producer);
      const reject = source.indexOf("material_shop_preparation_incomplete", finalization);
      assert(producer >= 0 && finalization > producer && reject > finalization);
    });
    test("preparation is atomically persisted before normal materialization resolution", () => {
      const source = fs.readFileSync(path.join(__dirname, "prepare.js"), "utf8");
      const write = source.indexOf("Materialize.writeJsonAtomicNew(path.join(runDir, \"preparation.json\")");
      const resolve = source.indexOf("Materialize.resolveCreationIntent", write);
      assert(write >= 0 && resolve > write);
    });
    const reusedRunId = path.basename(producerReuseBase);
    const reusedDestination = path.join(owned, Materialize.MATERIALIZED_DIRECTORY,
      reusedRunId, "resources");
    const reusedIntent = Materialize.createCreationIntent({ runId: reusedRunId,
      runDir: producerReuseBase, ownedBase: owned, destination: reusedDestination,
      scope: first.scope });
    Materialize.writeJsonAtomicNew(path.join(producerReuseBase,
      Materialize.CREATION_INTENT_NAME), reusedIntent);
    const reusedLease = Materialize.createMaterializationProducerLease(reusedIntent, {
      createdAt: "2026-08-12T00:00:01.000Z", ownerPid: process.pid,
      ownerProcessStartUtcTicks: "100000000000",
      ownerNonceSha256: "8".repeat(64),
    });
    fs.writeFileSync(path.join(producerReuseBase, Materialize.PRODUCER_LEASE_NAME),
      JSON.stringify(reusedLease, null, 2) + "\n", { encoding: "utf8", flag: "wx" });
    test("explicit producer recovery admits exact PID reuse", () => {
      const recovered = Materialize.recoverStaleMaterializationProducer(producerReuseBase, {
        acknowledge: true,
      });
      assert.strictEqual(recovered.kind, "stale_recovery");
      assert.strictEqual(recovered.lease.leaseSha256, reusedLease.leaseSha256);
    });
    test("PID-reused producer receipt remains bound through absent-worktree cleanup", () => {
      const receipt = Materialize.cleanupFailedMaterialization(producerReuseBase, {
        acknowledge: true,
      });
      assert.strictEqual(receipt.producerKind, "stale_recovery");
      assert.strictEqual(receipt.producerLeaseSha256, reusedLease.leaseSha256);
    });

    const sourceRoot = path.join(testBase, "fixture-source");
    const fixtureRelativePath = "data/crafting/公社装备/公社防具.json";
    fs.mkdirSync(path.dirname(path.join(sourceRoot, fixtureRelativePath)), { recursive: true });
    const fixtureBytes = Buffer.from("candidate-ready fixture\n", "utf8");
    fs.writeFileSync(path.join(sourceRoot, fixtureRelativePath), fixtureBytes);
    const fixtureScope = syntheticScope(sourceRoot, fixtureRelativePath, fixtureBytes, first.head);
    const destination = path.join(testBase, "materialized", "fixture", "resources");
    const fixtureMaterialization = Materialize.materializeScope({
      root: Common.CANONICAL_ROOT, sourceRoot, scope: fixtureScope, destination,
      ownedBase: testBase, fixtureMode: true,
    });
    test("fixture materialization copies exact closed scope", () => {
      Materialize.verifyMaterialization(fixtureMaterialization, fixtureScope,
        { ownedBase: testBase, fixtureMode: true });
      assert.strictEqual(fs.existsSync(path.join(destination, ".git")), false);
    });
    negative("materialization never overwrites a pre-existing destination",
      "material_shop_destination_exists", () => {
        Materialize.materializeScope({ root: Common.CANONICAL_ROOT, sourceRoot,
          scope: fixtureScope, destination, ownedBase: testBase, fixtureMode: true });
      });
    fs.appendFileSync(path.join(destination, fixtureRelativePath), "drift");
    negative("materialized byte drift fails", "material_shop_materialization_tree_mismatch", () => {
      Materialize.verifyMaterialization(fixtureMaterialization, fixtureScope,
        { ownedBase: testBase, fixtureMode: true });
    });
    const releaseScope = path.join(testBase, "release-scope");
    fs.mkdirSync(path.join(releaseScope, "tmp", "runtime-candidates", "v2", "fixture"),
      { recursive: true });
    fs.mkdirSync(path.dirname(path.join(releaseScope, fixtureRelativePath)), { recursive: true });
    fs.writeFileSync(path.join(releaseScope, fixtureRelativePath), fixtureBytes);
    fs.writeFileSync(path.join(releaseScope, "tmp", "runtime-candidates", "v2", "fixture",
      "generated.bin"), "candidate output");
    test("post-build release scope admits generated output but replays protected bytes", () => {
      assert.strictEqual(Materialize.verifyScopeFiles(releaseScope, fixtureScope), 1);
    });
    const releaseScopeDrift = Buffer.from(fixtureBytes);
    releaseScopeDrift[0] ^= 1;
    fs.writeFileSync(path.join(releaseScope, fixtureRelativePath), releaseScopeDrift);
    negative("post-build release scope rejects protected-byte drift",
      "material_shop_worktree_scope_mismatch", () => {
        Materialize.verifyScopeFiles(releaseScope, fixtureScope);
      });
    test("materialized require and raw acceptance paths fence full protected scope first",
      () => {
        const buildSource = fs.readFileSync(path.join(__dirname, "build-candidate.js"), "utf8");
        const buildLoader = buildSource.indexOf("function loadMaterializedProduction");
        const buildFence = buildSource.indexOf("Materialize.verifyPostBuildProtectedScope",
          buildLoader);
        const buildRequire = buildSource.indexOf("const producer = require(resolved)",
          buildLoader);
        assert(buildLoader >= 0 && buildFence > buildLoader && buildFence < buildRequire);
        const runSource = fs.readFileSync(path.join(__dirname, "run-live-journey.js"), "utf8");
        const runLoader = runSource.indexOf("function loadMaterializedRuntimeModules");
        const runFence = runSource.indexOf("Materialize.verifyPostBuildProtectedScope", runLoader);
        const runRequire = runSource.indexOf("const NpcPassive = require(passivePath)", runLoader);
        assert(runLoader >= 0 && runFence > runLoader && runFence < runRequire);
        ["verify-run.js", "accept-run.js"].forEach((name) => {
          const source = fs.readFileSync(path.join(__dirname, name), "utf8");
          assert(source.indexOf("Build.loadBuildReceipt") >= 0);
          assert(source.indexOf("Build.loadBuildReceipt")
            < source.indexOf("JourneyVerifier.verifyRawCandidateJourney"));
        });
      });
    const ignoredSlots = {
      seedSlot: "cf7_agent_a5_material_shop_seed_test",
      targetSlot: "cf7_agent_a5_material_shop_run_test",
      recoverySlot: "cf7_agent_a5_material_shop_recovery_test",
    };
    const ignoredPolicy = Materialize.ignoredOutputPolicy(Common.CANONICAL_ROOT, {
      runId: "material-shop-self-test",
      seedSlot: ignoredSlots.seedSlot,
      targetSlot: ignoredSlots.targetSlot,
      recoverySlot: ignoredSlots.recoverySlot,
      candidateRoot: path.join(Common.CANONICAL_ROOT, "tmp", "runtime-candidates", "v2",
        Build.CANDIDATE_LEAF),
      scope: first.scope,
    });
    test("ignored release outputs admit only the exact sealed A5 runtime closure",
      () => {
      assert.strictEqual(Materialize.assertIgnoredOutputPath(
        "tmp/runtime-dev/active.v1.json", ignoredPolicy, first.scope),
      "tmp/runtime-dev/active.v1.json");
      assert.strictEqual(Materialize.assertIgnoredOutputPath(
        "tmp/runtime-candidates/v2/a5/runtime/core.dll", ignoredPolicy, first.scope),
      "tmp/runtime-candidates/v2/a5/runtime/core.dll");
      assert.strictEqual(Materialize.assertIgnoredOutputPath(
        "tmp/workbench-live-e2e/material-shop/material-shop-self-test/target/a.json",
        ignoredPolicy, first.scope),
      "tmp/workbench-live-e2e/material-shop/material-shop-self-test/target/a.json");
      [ignoredPolicy.seedRelativePath, ignoredPolicy.targetRelativePath,
        ignoredPolicy.recoveryRelativePath, ignoredPolicy.launcherVersionMarkerRelativePath,
        ...ignoredPolicy.runtimeLogRelativePaths,
        "launcher/webview2_overlay_userdata/EBWebView/BrowserMetrics-spare.pma",
        "launcher/webview2_userdata/EBWebView/Default/Preferences"].forEach(
        (relativePath) => assert.strictEqual(Materialize.assertIgnoredOutputPath(
          relativePath, ignoredPolicy, first.scope), relativePath));
      Scope.SEED_FIXTURE_FILES.forEach((relativePath) => assert.strictEqual(
        Materialize.assertIgnoredOutputPath(relativePath, ignoredPolicy, first.scope),
        relativePath));
    });
    negative("foreign ignored output cannot be deleted with the worktree",
      "material_shop_ignored_output_foreign", () => {
        Materialize.assertIgnoredOutputPath(
          "tmp/foreign-cache/private.bin", ignoredPolicy, first.scope);
      });
    negative("near-match candidate sibling is outside ignored release closure",
      "material_shop_ignored_output_foreign", () => {
        Materialize.assertIgnoredOutputPath(
          "tmp/runtime-candidates/v2/a5-near/runtime/core.dll", ignoredPolicy, first.scope);
      });
    negative("near-match WebView2 userdata prefix is outside ignored release closure",
      "material_shop_ignored_output_foreign", () => {
        Materialize.assertIgnoredOutputPath(
          "launcher/webview2_userdata-near/EBWebView/Default/Preferences",
          ignoredPolicy, first.scope);
      });
    negative("extra launcher log is outside ignored release closure",
      "material_shop_ignored_output_foreign", () => {
        Materialize.assertIgnoredOutputPath(
          "logs/launcher-extra.log", ignoredPolicy, first.scope);
      });
    negative("offline recovery receipt is outside ignored release closure",
      "material_shop_ignored_output_foreign", () => {
        Materialize.assertIgnoredOutputPath(
          "tmp/workbench-live-e2e/offline-recovery-receipts/material-shop-self-test.json",
          ignoredPolicy, first.scope);
      });

    const ignoredFixtureRoot = path.join(testBase, "ignored-protected-inputs");
    fs.mkdirSync(ignoredFixtureRoot);
    const gitInit = childProcess.spawnSync("git", ["-C", ignoredFixtureRoot, "init", "--quiet"], {
      windowsHide: true, encoding: "utf8",
    });
    assert.strictEqual(gitInit.status, 0, String(gitInit.stderr || ""));
    fs.writeFileSync(path.join(ignoredFixtureRoot, ".gitignore"),
      ["saves/*.json", "saves/.launcher-version-marker.json", "logs/",
        "launcher/webview2_overlay_userdata/", "launcher/webview2_userdata/", "tmp/", ""]
        .join("\n"), "utf8");
    const protectedSaveEntries = first.scope.files.filter((entry) =>
      Scope.SEED_FIXTURE_FILES.includes(entry.relativePath));
    assert.strictEqual(protectedSaveEntries.length, 4);
    protectedSaveEntries.forEach((entry) => {
      const source = Common.resolveWithin(
        Common.CANONICAL_ROOT, entry.relativePath, "self_test").absolute;
      const target = Common.resolveWithin(
        ignoredFixtureRoot, entry.relativePath, "self_test").absolute;
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.copyFileSync(source, target);
    });
    const ignoredFixtureScope = subsetScope(
      ignoredFixtureRoot, protectedSaveEntries, first.head);
    const ignoredFixtureCandidate = path.join(
      ignoredFixtureRoot, "tmp", "runtime-candidates", "v2", Build.CANDIDATE_LEAF);
    fs.mkdirSync(path.join(ignoredFixtureCandidate, "runtime"), { recursive: true });
    fs.writeFileSync(path.join(ignoredFixtureCandidate, "runtime", "core.dll"),
      "candidate-output", "utf8");
    const ignoredGeneratedOutputs = [
      { relativePath: "saves/" + ignoredSlots.seedSlot + ".json", bytes: "{}\n" },
      { relativePath: "saves/" + ignoredSlots.targetSlot + ".json", bytes: "{}\n" },
      { relativePath: "saves/" + ignoredSlots.recoverySlot + ".json", bytes: "{}\n" },
      { relativePath: "saves/.launcher-version-marker.json", bytes: "{}\n" },
      { relativePath: "logs/bootstrap.log", bytes: "bootstrap\n" },
      { relativePath: "logs/launcher.log", bytes: "launcher\n" },
      { relativePath: "logs/perf-latest.jsonl", bytes: "{}\n" },
      { relativePath: "launcher/webview2_userdata/EBWebView/Default/Preferences",
        bytes: "bootstrap-userdata" },
      { relativePath:
          "launcher/webview2_overlay_userdata/EBWebView/BrowserMetrics-spare.pma",
        bytes: Buffer.alloc(0) },
    ];
    ignoredGeneratedOutputs.forEach((entry) => {
      const target = Common.resolveWithin(
        ignoredFixtureRoot, entry.relativePath, "self_test").absolute;
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, entry.bytes);
    });
    const ignoredFixtureOptions = { runId: "material-shop-self-test",
      seedSlot: ignoredSlots.seedSlot, targetSlot: ignoredSlots.targetSlot,
      recoverySlot: ignoredSlots.recoverySlot,
      candidateRoot: ignoredFixtureCandidate, scope: ignoredFixtureScope };
    const ignoredFixtureInventory = Materialize.captureIgnoredOutputInventory(
      ignoredFixtureRoot, ignoredFixtureOptions);
    test("protected inputs and exact A5 outputs are byte-hash sealed including zero bytes", () => {
      Materialize.verifyIgnoredOutputInventory(
        ignoredFixtureInventory, ignoredFixtureRoot, ignoredFixtureOptions);
      const protectedFiles = ignoredFixtureInventory.files.filter((entry) =>
        entry.kind === "protected_scope_input");
      assert.deepStrictEqual(protectedFiles.map((entry) => entry.relativePath),
        Scope.SEED_FIXTURE_FILES.slice().sort());
      assert.strictEqual(protectedFiles.length, 4);
      assert.strictEqual(ignoredFixtureInventory.files.filter((entry) =>
        entry.kind === "generated_output").length, 10);
      const emptyOutput = ignoredFixtureInventory.files.find((entry) =>
        entry.relativePath.endsWith("BrowserMetrics-spare.pma"));
      assert.strictEqual(emptyOutput.bytes, 0);
      assert.strictEqual(emptyOutput.sha256, Evidence.sha256Bytes(Buffer.alloc(0)));
      const forged = clone(ignoredFixtureInventory);
      forged.files.find((entry) => entry.kind === "protected_scope_input").kind
        = "generated_output";
      forged.filesSha256 = Evidence.sha256Text(Evidence.canonicalJson(forged.files));
      reseal(forged, "inventorySha256");
      let error = null;
      try {
        Materialize.validateIgnoredOutputInventory(
          forged, ignoredFixtureRoot, ignoredFixtureOptions);
      } catch (failure) { error = failure; }
      assert(error);
      assert.strictEqual(error.code, "material_shop_ignored_output_inventory_invalid");
    });
    const supplementalRelativePath =
      "tmp/workbench-live-e2e/offline-recovery-receipts/material-shop-self-test.json";
    const supplementalAbsolutePath = Common.resolveWithin(
      ignoredFixtureRoot, supplementalRelativePath, "self_test").absolute;
    const supplementalBytes = Buffer.from("{\"operation\":\"inspect\"}\n", "utf8");
    const supplementalDescriptor = { relativePath: supplementalRelativePath,
      bytes: supplementalBytes.length, sha256: Evidence.sha256Bytes(supplementalBytes) };
    test("eligibility-bound supplemental output is exact, present, and byte-hash sealed", () => {
      fs.mkdirSync(path.dirname(supplementalAbsolutePath), { recursive: true });
      fs.writeFileSync(supplementalAbsolutePath, supplementalBytes);
      try {
        const options = Object.assign({}, ignoredFixtureOptions, {
          supplementalGeneratedOutputs: [supplementalDescriptor],
        });
        const inventory = Materialize.captureIgnoredOutputInventory(
          ignoredFixtureRoot, options);
        Materialize.verifyIgnoredOutputInventory(inventory, ignoredFixtureRoot, options);
        assert.deepStrictEqual(inventory.policy.supplementalGeneratedOutputs,
          [supplementalDescriptor]);
        assert.deepStrictEqual(inventory.files.find((entry) =>
          entry.relativePath === supplementalRelativePath), Object.assign({
          kind: "generated_output",
        }, supplementalDescriptor));
      } finally {
        fs.unlinkSync(supplementalAbsolutePath);
      }
    });
    negative("missing supplemental output cannot be declared by eligibility",
      "material_shop_ignored_output_inventory_invalid", () => {
        Materialize.captureIgnoredOutputInventory(ignoredFixtureRoot,
          Object.assign({}, ignoredFixtureOptions, {
            supplementalGeneratedOutputs: [supplementalDescriptor],
          }));
      });
    negative("supplemental output hash drift fails before inventory sealing",
      "material_shop_ignored_output_inventory_invalid", () => {
        fs.mkdirSync(path.dirname(supplementalAbsolutePath), { recursive: true });
        fs.writeFileSync(supplementalAbsolutePath, supplementalBytes);
        try {
          Materialize.captureIgnoredOutputInventory(ignoredFixtureRoot,
            Object.assign({}, ignoredFixtureOptions, {
              supplementalGeneratedOutputs: [Object.assign({}, supplementalDescriptor, {
                sha256: "f".repeat(64),
              })],
            }));
        } finally {
          fs.unlinkSync(supplementalAbsolutePath);
        }
      });
    negative("supplemental output near-match path remains foreign",
      "material_shop_ignored_output_foreign", () => {
        const near = supplementalAbsolutePath.replace(/\.json$/, "-near.json");
        fs.mkdirSync(path.dirname(near), { recursive: true });
        fs.writeFileSync(near, supplementalBytes);
        try {
          Materialize.captureIgnoredOutputInventory(ignoredFixtureRoot,
            Object.assign({}, ignoredFixtureOptions, {
              supplementalGeneratedOutputs: [supplementalDescriptor],
            }));
        } finally {
          fs.unlinkSync(near);
        }
      });
    negative("duplicate supplemental descriptors are rejected",
      "material_shop_ignored_output_policy_invalid", () => {
        Materialize.ignoredOutputPolicy(ignoredFixtureRoot,
          Object.assign({}, ignoredFixtureOptions, {
            supplementalGeneratedOutputs: [supplementalDescriptor,
              clone(supplementalDescriptor)],
            }));
      });
    test("ordinary Build protected-scope options remain free of supplemental output policy", () => {
      assert.deepStrictEqual(Build.protectedScopeOptions({ runId: "material-shop-self-test",
        slots: ignoredSlots }, ignoredFixtureCandidate), {
        runId: "material-shop-self-test", seedSlot: ignoredSlots.seedSlot,
        targetSlot: ignoredSlots.targetSlot, recoverySlot: ignoredSlots.recoverySlot,
        candidateRoot: ignoredFixtureCandidate,
      });
    });
    negative("Build rejects a bare supplemental output bootstrap bypass",
      "material_shop_build_bootstrap_invalid", () => {
        Build.protectedScopeOptions({ runId: "material-shop-self-test", slots: ignoredSlots },
          ignoredFixtureCandidate, { supplementalGeneratedOutputs: [supplementalDescriptor] });
      });
    test("frozen bootstrap remains upstream of strict finalization and acceptance replay", () => {
      const buildSource = fs.readFileSync(path.join(__dirname, "build-candidate.js"), "utf8");
      const finalizerSource = fs.readFileSync(
        path.join(__dirname, "finalize-clone-release.js"), "utf8");
      const acceptSource = fs.readFileSync(path.join(__dirname, "accept-run.js"), "utf8");
      const adapterValidation = buildSource.indexOf("adapter.validateProtectedScopeBootstrap");
      const supplementProjection = buildSource.indexOf(
        "value.supplementalGeneratedOutputs", adapterValidation);
      assert(adapterValidation >= 0 && supplementProjection > adapterValidation);
      assert(!buildSource.includes("options.supplementalGeneratedOutputs"));
      const finalizerMain = finalizerSource.indexOf("function main()");
      const bootstrapContext = finalizerSource.indexOf(
        "loadContext(args, { allowFrozenPostReleaseBootstrap: true })", finalizerMain);
      const markerReplay = finalizerSource.indexOf("loadFinalizationMarker(", bootstrapContext);
      const receiptWrite = finalizerSource.indexOf("writeReleaseReceipt(", markerReplay);
      assert(bootstrapContext > finalizerMain && markerReplay > bootstrapContext
        && receiptWrite > markerReplay);
      const acceptLoad = acceptSource.indexOf("function loadContext(options)");
      const acceptBootstrap = acceptSource.indexOf("captureProtectedScopeBootstrap(", acceptLoad);
      const acceptBuild = acceptSource.indexOf("Build.loadBuildReceipt(", acceptBootstrap);
      const releaseReplay = acceptSource.indexOf("validateCloneRelease(", acceptBuild);
      const blockerReplay = acceptSource.indexOf("unresolvedBlockerFiles(", releaseReplay);
      assert(acceptBootstrap > acceptLoad && acceptBuild > acceptBootstrap
        && releaseReplay > acceptBuild && blockerReplay > releaseReplay);
    });
    negative("zero-byte generated output hash drift fails sealed inventory replay",
      "material_shop_ignored_output_inventory_invalid", () => {
        const forged = clone(ignoredFixtureInventory);
        forged.files.find((entry) => entry.bytes === 0).sha256 = "f".repeat(64);
        forged.filesSha256 = Evidence.sha256Text(Evidence.canonicalJson(forged.files));
        reseal(forged, "inventorySha256");
        Materialize.verifyIgnoredOutputInventory(
          forged, ignoredFixtureRoot, ignoredFixtureOptions);
      });
    negative("protected scope inputs retain the non-empty v2 byte constraint",
      "material_shop_ignored_output_inventory_invalid", () => {
        const forged = clone(ignoredFixtureInventory);
        const protectedEntry = forged.files.find((entry) =>
          entry.kind === "protected_scope_input");
        forged.totalBytes -= protectedEntry.bytes;
        protectedEntry.bytes = 0;
        forged.filesSha256 = Evidence.sha256Text(Evidence.canonicalJson(forged.files));
        reseal(forged, "inventorySha256");
        Materialize.validateIgnoredOutputInventory(
          forged, ignoredFixtureRoot, ignoredFixtureOptions);
      });
    test("legacy v2 ignored-output receipts remain validation-compatible", () => {
      const legacyOptions = { runId: ignoredFixtureOptions.runId,
        seedSlot: ignoredFixtureOptions.seedSlot,
        candidateRoot: ignoredFixtureCandidate, scope: ignoredFixtureScope };
      const legacyFiles = ignoredFixtureInventory.files.filter((entry) =>
        entry.kind === "protected_scope_input"
          || entry.relativePath.startsWith("tmp/runtime-candidates/v2/a5/"));
      const legacyInventory = {
        schema: Materialize.LEGACY_IGNORED_OUTPUT_SCHEMA,
        policy: Materialize.legacyIgnoredOutputPolicy(ignoredFixtureRoot, legacyOptions),
        fileCount: legacyFiles.length,
        totalBytes: legacyFiles.reduce((sum, entry) => sum + entry.bytes, 0),
        files: legacyFiles,
        filesSha256: Evidence.sha256Text(Evidence.canonicalJson(legacyFiles)),
      };
      reseal(legacyInventory, "inventorySha256");
      Materialize.validateIgnoredOutputInventory(
        legacyInventory, ignoredFixtureRoot, legacyOptions);
    });
    negative("foreign ignored save is not admitted by the protected scope",
      "material_shop_ignored_output_foreign", () => {
        const foreign = path.join(ignoredFixtureRoot, "saves", "cf7_agent_foreign.json");
        fs.writeFileSync(foreign, "{}\n", "utf8");
        try {
          Materialize.captureIgnoredOutputInventory(ignoredFixtureRoot, ignoredFixtureOptions);
        } finally {
          fs.unlinkSync(foreign);
        }
      });
    negative("ignored protected save byte drift fails before candidate acceptance",
      "material_shop_worktree_scope_mismatch", () => {
        const target = Common.resolveWithin(ignoredFixtureRoot,
          Scope.SEED_FIXTURE_FILES[0], "self_test").absolute;
        const original = fs.readFileSync(target);
        fs.appendFileSync(target, "drift", "utf8");
        try {
          Materialize.captureIgnoredOutputInventory(ignoredFixtureRoot, ignoredFixtureOptions);
        } finally {
          fs.writeFileSync(target, original);
        }
      });

    const plan = planFor(applicability, first, true, true);
    test("current plan is 21 steps with one live viewport and NA locked/max", () => {
      assert.strictEqual(plan.steps.length, 21);
      assert(plan.steps.some((step) => step.id === "materials_visual_current_window"));
      assert(!plan.steps.some((step) => /^materials_visual_\d/.test(step.id)));
      assert.strictEqual(plan.applicability.locked.status, "not_applicable_current_data");
      assert.strictEqual(plan.applicability.max.status, "not_applicable_current_data");
    });
    test("native steps are Computer Use only and CDP is panel-only", () => {
      plan.steps.forEach((step) => {
        if (step.transportClass === "native_visible_input") {
          assert.deepStrictEqual(step.allowedTransports, [Protocol.PREFERRED_TRANSPORT]);
          assert.deepStrictEqual(step.driverMethods, ["computer_use"]);
        }
        if (step.allowedTransports.includes(Protocol.FALLBACK_TRANSPORT)) {
          assert.strictEqual(step.transportClass, "panel_visible_input");
        }
      });
    });
    const agentRuntimePlan = agentRuntimePlanFor(applicability, first);
    test("Agent Runtime live plan binds one exact project JSONL provider", () => {
      assert.strictEqual(agentRuntimePlan.schema, Protocol.AGENT_RUNTIME_PLAN_SCHEMA);
      assert.deepStrictEqual(agentRuntimePlan.transportPolicy, {
        provider: Protocol.AGENT_RUNTIME_PROVIDER,
        transport: Protocol.AGENT_RUNTIME_TRANSPORT,
        trustedRunnerSlot: Protocol.AGENT_RUNTIME_SLOT,
        candidateLeaf: Protocol.AGENT_RUNTIME_CANDIDATE_LEAF,
        panelOpen: { method: "panel.open", name: "materials" },
        allowedRpcMethods: Protocol.AGENT_RUNTIME_RPC_METHODS.slice(),
        runnerOperations: ["trusted_runner_finish", "restart_candidate"],
        liveAdmission: "candidate_ui_probe_required",
      });
      assert(Protocol.AGENT_RUNTIME_RPC_METHODS.includes("input.type_text"));
      assert.strictEqual(agentRuntimePlan.steps.length, 24);
      assert.deepStrictEqual(agentRuntimePlan.recipeJump,
        Protocol.AGENT_RUNTIME_RECIPE_JUMP);
      assert(!agentRuntimePlan.steps.some((step) => ["safeexit", "exit_confirm",
        "supported_shutdown"].includes(step.id)));
      assert(agentRuntimePlan.steps.some((step) =>
        step.id === "trusted_runner_persistence_shutdown"));
      assert(agentRuntimePlan.steps.some((step) =>
        step.id === "trusted_runner_final_shutdown"));
      agentRuntimePlan.steps.forEach((step) => {
        assert.deepStrictEqual(step.allowedTransports, [Protocol.AGENT_RUNTIME_TRANSPORT]);
        step.driverMethods.forEach((method) => assert(
          ["restart_candidate", "trusted_runner_finish"].includes(method)
          || Protocol.AGENT_RUNTIME_RPC_METHODS.includes(method)));
      });
      const open = agentRuntimePlan.steps.find((step) => step.id === "open_materials");
      assert.deepStrictEqual(open.driverMethods,
        ["panel.open", "observation.capture", "content.read"]);
      const materialsKeyboard = agentRuntimePlan.steps.find(
        (step) => step.id === "materials_keyboard");
      assert.deepStrictEqual(materialsKeyboard.driverMethods,
        ["input.press_key", "observation.capture", "content.read"]);
      const recipeIntent = agentRuntimePlan.steps.find(
        (step) => step.id === "recipe_jump_intent");
      assert.deepStrictEqual(recipeIntent.driverMethods, ["input.press_key"]);
      const recipeReopen = agentRuntimePlan.steps.find(
        (step) => step.id === "recipe_reopen_materials");
      assert.deepStrictEqual(recipeReopen.driverMethods,
        ["panel.open", "observation.capture", "content.read"]);
      const unlockedForward = agentRuntimePlan.steps.find(
        (step) => step.id === "unlocked_forward");
      assert.deepStrictEqual(unlockedForward.driverMethods,
        ["input.click", "input.type_text"]);
      const unlockedIntent = agentRuntimePlan.steps.find(
        (step) => step.id === "unlocked_intent_qty1");
      assert.deepStrictEqual(unlockedIntent.driverMethods,
        ["input.press_key", "input.click", "observation.capture", "content.read"]);
      assert.strictEqual(unlockedIntent.action, "send_visible_keyboard_input");
      assert.strictEqual(unlockedIntent.requiresCapture, true);
      const forgedIntent = clone(agentRuntimePlan);
      const forgedIntentStep = forgedIntent.steps.find(
        (step) => step.id === "unlocked_intent_qty1");
      forgedIntentStep.action = "activate_visible_control";
      forgedIntentStep.driverMethods = ["input.click", "observation.capture", "content.read"];
      reseal(forgedIntent, "planSha256");
      assert.throws(() => Protocol.validateControlPlan(forgedIntent), {
        code: "material_shop_control_step_invalid",
      });
      const restartReadback = agentRuntimePlan.steps.find(
        (step) => step.id === "restart_readback");
      assert.deepStrictEqual(restartReadback.driverMethods,
        ["input.click", "input.type_text", "observation.capture", "content.read"]);
      const restartClose = agentRuntimePlan.steps.find(
        (step) => step.id === "restart_close");
      assert.strictEqual(restartClose.action, "activate_visible_control");
      assert.deepStrictEqual(restartClose.driverMethods, ["input.click"]);
      const unlockedReturn = agentRuntimePlan.steps.find(
        (step) => step.id === "unlocked_return");
      assert.deepStrictEqual(unlockedReturn.driverMethods,
        ["input.click", "observation.capture", "content.read"]);
      agentRuntimePlan.steps.forEach((step) => assert.strictEqual(
        new Set(step.driverMethods).size, step.driverMethods.length));
      const purchase = agentRuntimePlan.steps.find((step) => step.id === "unlocked_commit");
      assert.deepStrictEqual(purchase.driverMethods, ["input.click"]);
      assert.strictEqual(purchase.authorizationRef.decisionId,
        agentRuntimePlan.authorization.decisionId);
    });
    test("Agent Runtime v9 binds key/recipe proof and separate restart persistence", () => {
      const fixture = agentRuntimeEvidenceFixture(agentRuntimePlan, applicability);
      const evidence = Protocol.createAgentRuntimeJourneyEvidence(fixture);
      assert.strictEqual(evidence.schema, Protocol.AGENT_RUNTIME_EVIDENCE_SCHEMA);
      assert.strictEqual(evidence.journey.materials.recipeJump.keySequenceVerified, true);
      assert.strictEqual(evidence.journey.persistence.trustedPersistenceShutdown, true);
      assert.strictEqual(evidence.journey.persistence.trustedFinalShutdown, true);
      assert.notStrictEqual(evidence.journey.persistence.archiveSha256,
        evidence.journey.persistence.restartSha256);
      assert.strictEqual(evidence.journey.persistence.archiveSemanticSha256,
        evidence.journey.persistence.restartSemanticSha256);
      assert.strictEqual(Object.prototype.hasOwnProperty.call(
        evidence.journey.persistence, "safeExitCommitted"), false);
      assert.strictEqual(evidence.controls.transport, Protocol.AGENT_RUNTIME_TRANSPORT);
    });
    negative("Agent Runtime v9 rejects a forged SAFEEXIT persistence field",
      "material_shop_persistence_invalid", () => {
        const fixture = agentRuntimeEvidenceFixture(agentRuntimePlan, applicability);
        fixture.journey.persistence.safeExitCommitted = true;
        Protocol.createAgentRuntimeJourneyEvidence(fixture);
      });
    negative("Agent Runtime v9 rejects a foreign provider",
      "material_shop_control_evidence_invalid", () => {
        const fixture = agentRuntimeEvidenceFixture(agentRuntimePlan, applicability);
        fixture.controls.provider = "codex_computer_use";
        Protocol.createAgentRuntimeJourneyEvidence(fixture);
      });
    negative("Agent Runtime v9 rejects semantic restart drift",
      "material_shop_persistence_invalid", () => {
        const fixture = agentRuntimeEvidenceFixture(agentRuntimePlan, applicability);
        fixture.journey.persistence.restartSemanticSha256 = "0".repeat(64);
        Protocol.createAgentRuntimeJourneyEvidence(fixture);
      });
    negative("Agent Runtime v9 rejects malformed restart raw seal",
      "material_shop_persistence_invalid", () => {
        const fixture = agentRuntimeEvidenceFixture(agentRuntimePlan, applicability);
        fixture.journey.persistence.restartSha256 = "not-a-sha256";
        Protocol.createAgentRuntimeJourneyEvidence(fixture);
      });
    negative("Agent Runtime plan rejects a near A5 target slot",
      "material_shop_agent_runtime_policy_invalid", () => {
        Protocol.createAgentRuntimeControlPlan({
          runId: "material-shop-agent-runtime-near-slot", evidenceMode: "candidate_capture",
          seedSlot: "cf7_agent_a5_material_shop_seed",
          targetSlot: "cf7_agent_a5_material_shop_run_near",
          recoverySlot: "cf7_agent_a5_material_shop_recovery",
          scope: scopeBinding(first), applicability,
          authorization: Protocol.createAgentRuntimeAuthorization({
            evidenceMode: "candidate_capture",
            decisionId: "material-shop-agent-runtime-near-slot-qty1",
            runId: "material-shop-agent-runtime-near-slot",
            applicabilitySha256: applicability.applicabilitySha256,
            target: applicability.selectedUnlockedTarget,
          }),
        });
      });
    negative("Agent Runtime plan rejects Computer Use or CDP method injection",
      "material_shop_control_step_invalid", () => {
        const forged = clone(agentRuntimePlan);
        forged.steps[0].driverMethods.push("computer_use");
        reseal(forged, "planSha256");
        Protocol.validateControlPlan(forged);
      });
    negative("Agent Runtime plan rejects non-allowlisted key injection method",
      "material_shop_control_step_invalid", () => {
        const forged = clone(agentRuntimePlan);
        const materialsKeyboard = forged.steps.find(
          (step) => step.id === "materials_keyboard");
        materialsKeyboard.driverMethods[
          materialsKeyboard.driverMethods.indexOf("input.press_key")] = "Input.dispatchKeyEvent";
        reseal(forged, "planSha256");
        Protocol.validateControlPlan(forged);
      });
    negative("Agent Runtime plan rejects an incomplete visible journey method set",
      "material_shop_control_step_invalid", () => {
        const forged = clone(agentRuntimePlan);
        const unlockedForward = forged.steps.find(
          (step) => step.id === "unlocked_forward");
        unlockedForward.driverMethods = ["input.type_text"];
        reseal(forged, "planSha256");
        Protocol.validateControlPlan(forged);
      });
    negative("Agent Runtime plan rejects keyboard Escape for restart close",
      "material_shop_control_step_invalid", () => {
        const forged = clone(agentRuntimePlan);
        const restartClose = forged.steps.find((step) => step.id === "restart_close");
        restartClose.action = "send_visible_keyboard_input";
        restartClose.driverMethods = ["input.press_key"];
        reseal(forged, "planSha256");
        Protocol.validateControlPlan(forged);
      });
    test("Agent Runtime prepare CLI needs no capability file and fixes slot a5", () => {
      const parsed = Prepare.parseArgs(["--run-id", "material-shop-agent-runtime-cli",
        "--agent-runtime-jsonl", "--authorize-quantity-one-purchase"]);
      assert.strictEqual(parsed.agentRuntimeJsonl, true);
      assert.strictEqual(parsed.capabilityFile, null);
      assert.strictEqual(parsed.allowCdpFallback, false);
      assert.strictEqual(parsed.targetSlot, Protocol.AGENT_RUNTIME_SLOT);
    });
    negative("Agent Runtime prepare CLI forbids a capability file",
      "material_shop_prepare_arguments_invalid", () => {
        Prepare.parseArgs(["--run-id", "material-shop-agent-runtime-capability",
          "--agent-runtime-jsonl", "--environment-capability-file", "cu.json",
          "--authorize-quantity-one-purchase"]);
      });
    negative("Agent Runtime prepare CLI forbids CDP fallback",
      "material_shop_prepare_arguments_invalid", () => {
        Prepare.parseArgs(["--run-id", "material-shop-agent-runtime-cdp",
          "--agent-runtime-jsonl", "--allow-panel-cdp-input-fallback",
          "--authorize-quantity-one-purchase"]);
      });
    test("environment unavailability permits BuildOnly but blocks live admission", () => {
      const unavailable = planFor(applicability, first, false, false);
      assert.strictEqual(unavailable.transportPolicy.liveAdmission,
        "blocked_environment_computer_use_unavailable");
      assert.strictEqual(Build.assertBuildAdmission(unavailable.transportPolicy.liveAdmission),
        "blocked_environment_computer_use_unavailable");
    });
    const environmentOperationPath = writeOperatorArtifact(testBase,
      "environment-cu-operation", { tool: "computer-use", available: true,
        operationId: "self-test-environment-probe" });
    test("prepare capability reuses the operator-attested Computer Use validator", () => {
      const attested = Admission.createEnvironmentCapability(
        environmentProviderReceipt(true, environmentOperationPath));
      assert.deepStrictEqual(Prepare.assertCapability(attested), attested);
    });
    test("environment and source preflights precede run/worktree creation", () => {
      const prepareSource = fs.readFileSync(path.join(__dirname, "prepare.js"), "utf8");
      const prepareStart = prepareSource.indexOf("function prepare(options)");
      const capability = prepareSource.indexOf("assertCapability(settings.capability)",
        prepareStart);
      const runCreate = prepareSource.indexOf("fs.mkdirSync(runDir)", capability);
      const materialize = prepareSource.indexOf("Materialize.materializeScope", runCreate);
      assert(prepareStart >= 0 && capability > prepareStart && runCreate > capability
        && materialize > runCreate);
      const materializeSource = fs.readFileSync(path.join(__dirname, "materialize.js"), "utf8");
      const materializeStart = materializeSource.indexOf("function materializeScope(options)");
      const sourcePreflight = materializeSource.indexOf(
        "settings.scope.files.forEach((entry) => readExactSource", materializeStart);
      const worktreeAdd = materializeSource.indexOf('["worktree", "add", "--detach"',
        sourcePreflight);
      assert(sourcePreflight > materializeStart && worktreeAdd > sourcePreflight);
    });
    negative("self-hashed boolean cannot replace an operator raw artifact",
      "material_shop_capability_invalid", () => {
        const artifact = { schema: "forged.v1", available: true };
        Prepare.assertCapability({ available: true, source: "environment_tool_preflight",
          artifact, artifactSha256: Evidence.sha256Text(Evidence.canonicalJson(artifact)) });
      });
    negative("unresolved seed route blocks BuildOnly", "material_shop_candidate_build_admission_blocked",
      () => Build.assertBuildAdmission("blocked_route_seed_probe_required"));
    negative("unknown build admission fails closed", "material_shop_candidate_build_admission_invalid",
      () => Build.assertBuildAdmission("available"));
    const productionLikeResources = path.join(Common.CANONICAL_ROOT, "tmp",
      "workbench-live-e2e", "material-shop", "materialized",
      "a5-material-shop-20260812t0125", "resources");
    const buildPreparation = { resourcesRoot: productionLikeResources,
      preparationSha256: "a".repeat(64) };
    const buildMaterialization = { materializationSha256: "b".repeat(64) };
    test("candidate build command targets one exact short direct child", () => {
      const command = Build.buildCommand(buildPreparation);
      const contract = Build.candidateContract(buildPreparation);
      assert.strictEqual(path.basename(command.cwd).toLowerCase(), "resources");
      assert.deepStrictEqual(command.args.slice(-4),
        ["-ForceBuild", "-BuildOnly", "-CandidateLeaf", "a5"]);
      assert.strictEqual(contract.candidateRoot,
        path.join(productionLikeResources, "tmp", "runtime-candidates", "v2", "a5"));
      assert(contract.projectedLength < 260);
      assert.strictEqual(path.dirname(contract.candidateRoot), contract.candidateBase);
      Build.validateExecutedCommand(Object.assign({}, command, {
        stdoutSha256: "1".repeat(64), stderrSha256: "2".repeat(64), exitCode: 0,
      }), buildPreparation, "self_test");
    });
    negative("near-match candidate leaf cannot enter the build receipt command",
      "material_shop_build_command_invalid", () => {
        const command = Build.buildCommand(buildPreparation);
        command.args[command.args.length - 1] = "a5-near";
        Build.validateExecutedCommand(Object.assign({}, command, {
          stdoutSha256: "1".repeat(64), stderrSha256: "2".repeat(64), exitCode: 0,
        }), buildPreparation, "self_test");
      });
    const currentProjectedLength = Build.candidateContract(buildPreparation).projectedLength;
    const overlongPreparation = { resourcesRoot: productionLikeResources
      + "x".repeat(260 - currentProjectedLength), preparationSha256: "c".repeat(64) };
    test("overlong materialized root fails before spawn with exact path diagnostics", () => {
      let error = null;
      try { Build.buildCommand(overlongPreparation); } catch (failure) { error = failure; }
      assert(error);
      assert.strictEqual(error.code, "material_shop_candidate_path_budget_exceeded");
      assert(error.message.includes("candidateRoot=") && error.message.includes("projected=260")
        && error.message.includes("maximum=259"));
    });
    const buildCommand = Build.buildCommand(buildPreparation);
    const failureStdout = "x".repeat(Build.MAXIMUM_FAILURE_TAIL_BYTES + 17);
    const failureStderr = "构建失败".repeat(1600);
    const buildFailure = Build.createBuildFailure(buildPreparation, buildMaterialization,
      buildCommand, { status: 1, signal: null, error: null,
        stdout: failureStdout, stderr: failureStderr },
      "2026-08-12T00:00:00.000Z", "2026-08-12T00:00:01.000Z");
    test("failed BuildOnly writes bounded full-stream diagnostics and never candidate_built", () => {
      Build.validateBuildFailure(buildFailure, buildPreparation, buildMaterialization);
      assert.strictEqual(buildFailure.failureStage, "producer");
      assert.strictEqual(buildFailure.producerExitCode, 1);
      assert.strictEqual(buildFailure.candidateAcceptance, false);
      assert.strictEqual(buildFailure.diagnosticOnly, true);
      assert.strictEqual(buildFailure.candidateBuilt, false);
      assert.strictEqual(buildFailure.stdout.bytes, Buffer.byteLength(failureStdout));
      assert.strictEqual(buildFailure.stdout.sha256,
        Evidence.sha256Text(failureStdout));
      assert.strictEqual(buildFailure.stderr.sha256,
        Evidence.sha256Text(failureStderr));
      assert(Buffer.byteLength(buildFailure.stdout.tail, "utf8")
        <= Build.MAXIMUM_FAILURE_TAIL_BYTES);
      assert(Buffer.byteLength(buildFailure.stderr.tail, "utf8")
        <= Build.MAXIMUM_FAILURE_TAIL_BYTES);
    });
    const preflightError = new Error("projected=260 maximum=259");
    preflightError.code = "material_shop_candidate_path_budget_exceeded";
    const preflightFailure = Build.createBuildFailure(overlongPreparation,
      buildMaterialization, Build.uncheckedBuildCommand(overlongPreparation), {
        status: null, signal: null, error: null, stdout: "", stderr: "",
      }, "2026-08-12T00:00:00.000Z", "2026-08-12T00:00:01.000Z", {
        commandExecuted: false,
        failureStage: "preflight",
        failureCode: "material_shop_candidate_path_budget_exceeded",
        validationError: preflightError,
      });
    test("pre-spawn path rejection is a diagnostic-only commandExecuted=false receipt", () => {
      Build.validateBuildFailure(preflightFailure, overlongPreparation,
        buildMaterialization);
      assert.strictEqual(preflightFailure.commandExecuted, false);
      assert.strictEqual(preflightFailure.failureStage, "preflight");
      assert.strictEqual(preflightFailure.status, null);
      assert.strictEqual(preflightFailure.producerExitCode, null);
      assert.strictEqual(preflightFailure.signal, null);
      assert.strictEqual(preflightFailure.candidateObserved, false);
      assert.strictEqual(preflightFailure.candidateAcceptance, false);
      assert(preflightFailure.validationError.includes("projected=260"));
      assert.strictEqual(preflightFailure.stdout.bytes, 0);
      assert.strictEqual(preflightFailure.stderr.bytes, 0);
      assert.strictEqual(preflightFailure.projectedPathLength, 260);
      assert.strictEqual(preflightFailure.maximumPathLength, 259);
    });
    const postSpawnValidationError = new Error(
      "ignored file is outside the exact protected-input/candidate/A5 output closure");
    postSpawnValidationError.code = "material_shop_ignored_output_foreign";
    const postSpawnFailure = Build.createBuildFailure(buildPreparation,
      buildMaterialization, buildCommand, { status: 0, signal: null, error: null,
        stdout: "candidate built\n", stderr: "" },
      "2026-08-12T00:00:00.000Z", "2026-08-12T00:00:01.000Z", {
        commandExecuted: true, failureStage: "postspawn_acceptance",
        failureCode: postSpawnValidationError.code,
        validationError: postSpawnValidationError, candidateObserved: true,
      });
    test("exit-zero postspawn validation failure is diagnostic and never candidate_built", () => {
      Build.validateBuildFailure(postSpawnFailure, buildPreparation, buildMaterialization);
      assert.strictEqual(postSpawnFailure.commandExecuted, true);
      assert.strictEqual(postSpawnFailure.failureStage, "postspawn_acceptance");
      assert.strictEqual(postSpawnFailure.status, 0);
      assert.strictEqual(postSpawnFailure.producerExitCode, 0);
      assert.strictEqual(postSpawnFailure.candidateObserved, true);
      assert.strictEqual(postSpawnFailure.candidateAcceptance, false);
      assert.strictEqual(postSpawnFailure.candidateBuilt, false);
      assert.strictEqual(postSpawnFailure.failureCode,
        "material_shop_ignored_output_foreign");
    });
    negative("postspawn diagnostic cannot claim candidate acceptance",
      "material_shop_build_failure_invalid", () => {
        const forged = clone(postSpawnFailure);
        forged.candidateAcceptance = true;
        reseal(forged, "failureSha256");
        Build.validateBuildFailure(forged, buildPreparation, buildMaterialization);
      });
    negative("diagnostic build failure cannot be promoted to candidate_built",
      "material_shop_build_failure_invalid", () => {
        const forged = clone(buildFailure);
        forged.candidateBuilt = true;
        reseal(forged, "failureSha256");
        Build.validateBuildFailure(forged, buildPreparation, buildMaterialization);
      });
    negative("diagnostic build failure cannot pass the success receipt schema",
      "material_shop_build_receipt_invalid", () => {
        Build.validateBuildReceipt(buildFailure, buildPreparation, first, "self_test");
      });
    test("candidate build failure artifact is CreateNew and cannot overwrite diagnostics", () => {
      const filePath = path.join(testBase, Build.BUILD_FAILURE_NAME);
      Build.writeBuildFailureNew(testBase, buildFailure);
      const before = fs.readFileSync(filePath);
      let error = null;
      try { Build.writeBuildFailureNew(testBase, buildFailure); } catch (failure) { error = failure; }
      assert(error);
      assert.deepStrictEqual(fs.readFileSync(filePath), before);
    });
    test("build failure diagnostics are persisted before the public failure is thrown", () => {
      const source = fs.readFileSync(path.join(__dirname, "build-candidate.js"), "utf8");
      const contract = source.indexOf("candidate = candidateContract(preparation)");
      const preflightCreate = source.indexOf("createBuildFailure(preparation", contract);
      const preflightWrite = source.indexOf("writeBuildFailureNew(preparation.runDir", preflightCreate);
      const preflightFail = source.indexOf("Common.fail(failureCode", preflightWrite);
      const spawn = source.indexOf("childProcess.spawnSync");
      const create = source.indexOf("createBuildFailure(preparation", spawn);
      const write = source.indexOf("writeBuildFailureNew(preparation.runDir", create);
      const fail = source.indexOf('Common.fail("material_shop_candidate_build_failed"', write);
      const pointer = source.indexOf("const pointerPath", fail);
      const protectedFence = source.indexOf("Materialize.verifyPostBuildProtectedScope", pointer);
      const successWrite = source.indexOf("Prepare.writeJsonNew(buildArtifactPath", protectedFence);
      const acceptanceCatch = source.indexOf("} catch (error) {", successWrite);
      const acceptanceCreate = source.indexOf("createBuildFailure(preparation", acceptanceCatch);
      const acceptanceWrite = source.indexOf(
        "writeBuildFailureNew(preparation.runDir", acceptanceCreate);
      const acceptanceFail = source.indexOf("Common.fail(failureCode", acceptanceWrite);
      assert(contract >= 0 && preflightCreate > contract && preflightWrite > preflightCreate
        && preflightFail > preflightWrite && spawn > preflightFail);
      assert(spawn >= 0 && create > spawn && write > create && fail > write);
      assert(pointer > fail && protectedFence > pointer && successWrite > protectedFence
        && acceptanceCatch > successWrite && acceptanceCreate > acceptanceCatch
        && acceptanceWrite > acceptanceCreate && acceptanceFail > acceptanceWrite);
    });

    const runtimeCandidateRoot = path.join(testBase, "runtime-shape");
    const runtimeRequest = Admission.createCandidateRequest({ runId: "material-shop-self-test",
      planSha256: plan.planSha256,
      candidateIdentity: LiveRun.publicRunningIdentity({ identity: {
        runtimeMode: "isolated_candidate",
        processPath: path.join(runtimeCandidateRoot, "runtime",
          "CRAZYFLASHER7MercenaryEmpire.Core.exe"),
        coreSha256: "1".repeat(64), buildIdentity: "2".repeat(64),
        payloadClosure: "3".repeat(64), pid: 100, httpPort: 1192,
      } }),
    });
    const request = Admission.createCandidateRequest({ runId: "material-shop-self-test",
      planSha256: plan.planSha256,
      candidateIdentity: { pid: 100, processPath: "C:\\candidate\\core.exe",
        buildIdentityHash: "A".repeat(64) } });
    const candidateOperationPath = writeOperatorArtifact(testBase,
      "candidate-cu-operation", { tool: "computer-use", operationId: "self-test-candidate-probe",
        pid: 100, window: "window-100" });
    const candidateAdmission = Admission.createCandidateAdmissionBundle(request,
      providerReceipt(request, candidateOperationPath));
    test("candidate admission binds request, identity, PID, window, and freshness", () => {
      Admission.validateCandidateAdmissionBundle(candidateAdmission);
      assert.strictEqual(candidateAdmission.operatorAttestation.pid, 100);
      assert.strictEqual(candidateAdmission.operatorAttestation.independentlyVerifiable, false);
      assert.strictEqual(runtimeRequest.candidateIdentity.installRoot,
        path.resolve(runtimeCandidateRoot));
    });
    negative("stale candidate probe fails", "material_shop_candidate_ui_not_admitted", () => {
      const stale = new Date(Date.parse(request.issuedAt) + 16 * 60 * 1000).toISOString();
      Admission.createCandidateAdmissionBundle(request,
        providerReceipt(request, candidateOperationPath, stale));
    });
    negative("foreign candidate PID fails", "material_shop_candidate_ui_not_admitted", () => {
      const receipt = providerReceipt(request, candidateOperationPath);
      receipt.pid = 101;
      Admission.createCandidateAdmissionBundle(request, receipt);
    });
    negative("foreign candidate request digest fails", "material_shop_candidate_ui_not_admitted", () => {
      const receipt = providerReceipt(request, candidateOperationPath);
      receipt.requestSha256 = "e".repeat(64);
      Admission.createCandidateAdmissionBundle(request, receipt);
    });
    negative("operator attestation cannot claim independent cryptographic verification",
      "material_shop_provider_receipt_invalid", () => {
        const receipt = providerReceipt(request, candidateOperationPath);
        receipt.independentlyVerifiable = true;
        Admission.createCandidateAdmissionBundle(request, receipt);
      });
    negative("raw Computer Use artifact byte drift invalidates candidate admission",
      "material_shop_raw_operation_artifact_invalid", () => {
        const driftPath = writeOperatorArtifact(testBase, "candidate-cu-operation-drift",
          { tool: "computer-use", operationId: "self-test-candidate-probe", pid: 100 });
        const receipt = providerReceipt(request, driftPath);
        fs.appendFileSync(driftPath, "drift");
        Admission.createCandidateAdmissionBundle(request, receipt);
      });
    const restartRequest = Admission.createCandidateRequest({ runId: "material-shop-self-test",
      planSha256: plan.planSha256,
      candidateIdentity: { pid: 101, processPath: "C:\\candidate\\core.exe",
        buildIdentityHash: "A".repeat(64) } });
    const restartOperationPath = writeOperatorArtifact(testBase,
      "restart-candidate-cu-operation", { tool: "computer-use",
        operationId: "self-test-restart-candidate-probe", pid: 101 });
    const restartAdmission = Admission.createCandidateAdmissionBundle(restartRequest,
      providerReceipt(restartRequest, restartOperationPath));
    test("candidate admission replay binds two fresh PIDs and retained raw artifacts", () => {
      require("./journey-verifier").verifyAdmissions({ admissions: [candidateAdmission,
        restartAdmission] }, plan, { candidateIdentity: {
          processPath: "C:\\candidate\\core.exe", buildIdentityHash: "A".repeat(64),
        } }, testBase);
    });
    negative("candidate raw operation artifact cannot escape the exact run",
      "material_shop_candidate_operation_artifact_foreign", () => {
        require("./journey-verifier").verifyAdmissions({ admissions: [candidateAdmission,
          restartAdmission] }, plan, { candidateIdentity: {
          processPath: "C:\\candidate\\core.exe", buildIdentityHash: "A".repeat(64),
        } }, path.join(testBase, "foreign-run"));
      });

    const seedRoot = path.join(testBase, "seed-positive");
    const sourceJson = applicability.sourceFixture.artifacts.find((entry) => entry.kind === "json");
    const imported = CandidateLifecycle.importSeed(Common.CANONICAL_ROOT, seedRoot,
      Common.SOURCE_FIXTURE_SLOT, "cf7_agent_a5_material_shop_seed_test", sourceJson.sha256);
    test("b4 source copies exact bytes into dedicated A5 seed", () => {
      assert.strictEqual(imported.transformId, "exact-byte-copy");
      assert.strictEqual(imported.sourceSha256, imported.destinationSha256);
      assert.strictEqual(imported.sourceSha256, sourceJson.sha256);
    });
    negative("foreign source fixture is rejected", "material_shop_seed_mapping_invalid", () => {
      CandidateLifecycle.importSeed(Common.CANONICAL_ROOT, path.join(testBase, "seed-foreign"),
        "cf7_agent_character_build_final", "cf7_agent_a5_material_shop_seed_test", sourceJson.sha256);
    });
    const missingRoot = path.join(testBase, "missing-source");
    fs.mkdirSync(path.join(missingRoot, "saves"), { recursive: true });
    negative("missing b4 source is rejected", "exact_file_unavailable", () => {
      CandidateLifecycle.importSeed(missingRoot, path.join(testBase, "seed-missing"),
        Common.SOURCE_FIXTURE_SLOT, "cf7_agent_a5_material_shop_seed_test", sourceJson.sha256);
    });
    negative("transformed source digest is rejected", "material_shop_seed_source_drift", () => {
      CandidateLifecycle.importSeed(Common.CANONICAL_ROOT, path.join(testBase, "seed-drift"),
        Common.SOURCE_FIXTURE_SLOT, "cf7_agent_a5_material_shop_seed_test", "f".repeat(64));
    });

    const sealedSave = CandidateLifecycle.captureSaveStateArtifact({
      resourcesRoot: Common.CANONICAL_ROOT, appData: process.env.APPDATA,
      evidenceRoot: Common.CANONICAL_ROOT, evidenceRunDir: testBase,
      runId: path.basename(testBase), slot: Common.SOURCE_FIXTURE_SLOT,
      itemName: applicability.selectedUnlockedTarget.itemName, stage: "baseline",
    });
    test("sealed baseline save bytes independently prove money and owned zero", () => {
      const verified = CandidateLifecycle.verifySaveStateArtifact(testBase, sealedSave,
        "baseline", Common.SOURCE_FIXTURE_SLOT,
        applicability.selectedUnlockedTarget.itemName);
      assert.strictEqual(verified.projection.money, applicability.sourceFixture.money);
      assert.strictEqual(verified.projection.owned, 0);
      assert.strictEqual(verified.semanticSha256, sealedSave.semanticSha256);
    });
    test("legacy v1 sealed save remains replayable with a recomputed semantic digest", () => {
      const legacy = clone(sealedSave);
      legacy.schema = CandidateLifecycle.LEGACY_SAVE_STATE_SCHEMA;
      delete legacy.semanticSha256;
      reseal(legacy, "evidenceSha256");
      const verified = CandidateLifecycle.verifySaveStateArtifact(testBase, legacy,
        "baseline", Common.SOURCE_FIXTURE_SLOT,
        applicability.selectedUnlockedTarget.itemName);
      assert.strictEqual(verified.semanticSha256, sealedSave.semanticSha256);
    });
    test("save semantic digest ignores only timestamp and four registered set orders", () => {
      const firstSemantic = { lastSaved: "first", version: "3.0",
        others: { "物品来源缓存": { completedChallengeQuests: ["2", "1", "1"],
          discoveredEnemies: ["乙", "甲"], discoveredQuests: ["3", "1"],
          discoveredStages: ["后", "前"] }, ordered: ["a", "b"] },
        nested: { lastSaved: "preserved" } };
      const secondSemantic = { nested: { lastSaved: "preserved" }, version: "3.0",
        others: { ordered: ["a", "b"], "物品来源缓存": {
          discoveredStages: ["前", "后"], discoveredQuests: ["1", "3"],
          discoveredEnemies: ["甲", "乙"], completedChallengeQuests: ["1", "2", "1"] } },
        lastSaved: "second" };
      assert.strictEqual(CandidateLifecycle.saveSemanticSha256(firstSemantic),
        CandidateLifecycle.saveSemanticSha256(secondSemantic));
      const duplicateDrift = clone(secondSemantic);
      duplicateDrift.others["物品来源缓存"].discoveredQuests.push("1");
      assert.notStrictEqual(CandidateLifecycle.saveSemanticSha256(firstSemantic),
        CandidateLifecycle.saveSemanticSha256(duplicateDrift));
      const orderedDrift = clone(secondSemantic);
      orderedDrift.others.ordered.reverse();
      assert.notStrictEqual(CandidateLifecycle.saveSemanticSha256(firstSemantic),
        CandidateLifecycle.saveSemanticSha256(orderedDrift));
      const nestedTimestampDrift = clone(secondSemantic);
      nestedTimestampDrift.nested.lastSaved = "changed";
      assert.notStrictEqual(CandidateLifecycle.saveSemanticSha256(firstSemantic),
        CandidateLifecycle.saveSemanticSha256(nestedTimestampDrift));
    });
    negative("registered source-cache values must remain string arrays",
      "material_shop_save_semantic_source_cache_invalid", () => {
        CandidateLifecycle.saveSemanticSha256({ others: { "物品来源缓存": {
          discoveredStages: ["ok", 1] } } });
      });
    negative("forged full-save semantic digest cannot override sealed JSON bytes",
      "material_shop_save_state_projection_drift", () => {
        const drift = clone(sealedSave);
        drift.semanticSha256 = "0".repeat(64);
        reseal(drift, "evidenceSha256");
        CandidateLifecycle.verifySaveStateArtifact(testBase, drift, "baseline",
          Common.SOURCE_FIXTURE_SLOT, applicability.selectedUnlockedTarget.itemName);
      });
    negative("self-reported save projection cannot override sealed JSON bytes",
      "material_shop_save_state_projection_drift", () => {
        const drift = clone(sealedSave);
        drift.money -= 1;
        drift.stateSha256 = Evidence.sha256Text(Evidence.canonicalJson({ slot: drift.slot,
          itemName: drift.itemName, money: drift.money, owned: drift.owned }));
        reseal(drift, "evidenceSha256");
        CandidateLifecycle.verifySaveStateArtifact(testBase, drift, "baseline",
          Common.SOURCE_FIXTURE_SLOT, applicability.selectedUnlockedTarget.itemName);
      });

    const settlement = settlementFixture(applicability);
    test("material settlement binds exact target, q1, zero sale, price, balance, and owned 0 to 1",
      () => {
        const verified = require("./journey-verifier").assertSettlement(settlement.preview,
          settlement.commit, settlement.inbound, applicability);
        assert.deepStrictEqual({ unitPrice: verified.unitPrice,
          beforeOwned: verified.beforeOwned, afterOwned: verified.afterOwned,
          projectedBalance: verified.projectedBalance }, {
          unitPrice: 300, beforeOwned: 0, afterOwned: 1,
          projectedBalance: applicability.sourceFixture.money - 300 });
      });
    negative("projected balance drift cannot sign settlement",
      "material_shop_trade_preview_projection_invalid", () => {
        const drift = settlementFixture(applicability);
        drift.previewResponse.message.projectedBalance += 1;
        require("./journey-verifier").assertSettlement(drift.preview, drift.commit,
          drift.inbound, applicability);
      });
    negative("commit without material owned one cannot sign settlement",
      "material_shop_trade_commit_state_invalid", () => {
        const drift = settlementFixture(applicability);
        drift.commitResponse.message.views.material = { containerId: "材料", capacity: 0,
          accessibleCapacity: 0, viewCapacity: 0, offset: 0, limit: 0,
          filterKey: "material", slots: [] };
        require("./journey-verifier").assertSettlement(drift.preview, drift.commit,
          drift.inbound, applicability);
      });
    negative("preview and commit cannot cross NPCShop owners",
      "material_shop_trade_owner_invalid", () => {
        const drift = settlementFixture(applicability);
        drift.commit.message.panelInstanceId = "npcshop.self-test.foreign";
        drift.commitResponse.message.panelInstanceId = "npcshop.self-test.foreign";
        require("./journey-verifier").assertSettlement(drift.preview, drift.commit,
          drift.inbound, applicability);
      });
    negative("commit cannot precede the authoritative preview response",
      "material_shop_trade_order_invalid", () => {
        const drift = settlementFixture(applicability);
        drift.commit.event.sequence = drift.previewResponse.event.sequence - 1;
        require("./journey-verifier").assertSettlement(drift.preview, drift.commit,
          drift.inbound, applicability);
      });
    test("Host settlement order binds one owner after preview response", () => {
      const owner = settlement.preview.message.panelInstanceId;
      const order = require("./journey-verifier").assertSettlementHostOrder({
        panelInstanceId: owner, requestSequence: 2, responseLine: 20,
      }, { panelInstanceId: owner, requestSequence: 4, panelLine: 21 }, owner);
      assert.strictEqual(order.previewResponseLine, 20);
      assert.strictEqual(order.commitRequestLine, 21);
    });
    negative("Host commit mapping cannot precede preview response",
      "material_shop_host_trade_order_invalid", () => {
        const owner = settlement.preview.message.panelInstanceId;
        require("./journey-verifier").assertSettlementHostOrder({
          panelInstanceId: owner, requestSequence: 2, responseLine: 20,
        }, { panelInstanceId: owner, requestSequence: 4, panelLine: 19 }, owner);
      });

    const controlRun = path.join(testBase, "control-run");
    fs.mkdirSync(controlRun);
    const channel = new Control.ControlChannel(Common.CANONICAL_ROOT, controlRun, plan);
    const originalPlan = Evidence.canonicalJson(plan);
    const runnerRequest = channel.issue("restart_candidate", 60000);
    test("runner-owned restart acknowledgement closes under runner transport", () => {
      const ack = Control.createAck({ root: Common.CANONICAL_ROOT, runDir: controlRun,
        plan, request: runnerRequest, transport: Protocol.RUNNER_TRANSPORT,
        result: "completed", operationId: "runner-restart-test",
        completedAt: new Date().toISOString(),
        capturePath: null, captureSha256: null });
      assert.strictEqual(ack.provider.issuer, "cf7.material-shop.runner");
      assert.strictEqual(Evidence.canonicalJson(plan), originalPlan);
    });
    negative("external provider cannot acknowledge runner-owned lifecycle",
      "material_shop_runner_ack_external_forbidden", () => {
        AckControl.validateProviderReceipt({}, runnerRequest);
      });
    const nativeRequest = channel.issue("open_materials", 60000);
    negative("CDP cannot acknowledge Native HUD input", "control_transport_not_allowed", () => {
      Control.createAck({ root: Common.CANONICAL_ROOT, runDir: controlRun,
        plan, request: nativeRequest, transport: Protocol.FALLBACK_TRANSPORT,
        result: "completed", operationId: "native-cdp-test",
        completedAt: new Date().toISOString(), capturePath: null, captureSha256: null });
    });
    const pageRequest = channel.issue("ordinary_forward", 60000);
    const pageOperationPath = writeOperatorArtifact(controlRun, "ordinary-forward-operation",
      { tool: "computer-use", operationId: "page-cdp-test",
        requestId: pageRequest.requestId, pid: 100, window: "window-100" });
    const pageOperation = operationArtifactAfter(pageOperationPath, pageRequest.issuedAt);
    const pageCandidateBinding = AckControl.candidateBinding(pageRequest, candidateAdmission);
    test("explicit CDP fallback can acknowledge page input only", () => {
      const ack = Control.createAck({ root: Common.CANONICAL_ROOT, runDir: controlRun,
        plan, request: pageRequest, transport: Protocol.FALLBACK_TRANSPORT,
        result: "completed", operationId: "page-cdp-test",
        rawOperationArtifact: pageOperation, candidateBinding: pageCandidateBinding,
        completedAt: completedAfterOperation(pageOperation), capturePath: null, captureSha256: null });
      assert.strictEqual(ack.provider.issuer, Admission.OPERATOR_ISSUER);
      assert.strictEqual(ack.provider.candidateBinding.pid, 100);
    });
    negative("operator acknowledgement cannot reuse a foreign request binding",
      "material_shop_control_candidate_binding_invalid", () => {
        const binding = clone(pageCandidateBinding);
        binding.requestSha256 = "0".repeat(64);
        Control.createAck({ root: Common.CANONICAL_ROOT, runDir: controlRun,
          plan, request: pageRequest, transport: Protocol.FALLBACK_TRANSPORT,
          result: "completed", operationId: "page-cdp-foreign-request",
          rawOperationArtifact: pageOperation, candidateBinding: binding,
          completedAt: completedAfterOperation(pageOperation), capturePath: null, captureSha256: null });
      });
    negative("stale per-step raw operation artifact cannot acknowledge input",
      "material_shop_control_operation_stale", () => {
        const stalePath = writeOperatorArtifact(controlRun, "stale-page-operation",
          { tool: "computer-use", requestId: pageRequest.requestId });
        const staleTime = new Date(Date.parse(pageRequest.issuedAt) - 1000);
        fs.utimesSync(stalePath, staleTime, staleTime);
        Control.createAck({ root: Common.CANONICAL_ROOT, runDir: controlRun,
          plan, request: pageRequest, transport: Protocol.FALLBACK_TRANSPORT,
          result: "completed", operationId: "stale-page-operation",
          rawOperationArtifact: Admission.captureRawOperationArtifact(stalePath),
          candidateBinding: pageCandidateBinding,
          completedAt: completedAfterOperation(Admission.captureRawOperationArtifact(stalePath)),
          capturePath: null, captureSha256: null });
      });
    test("control result vocabulary includes exact timeout and completed is the only continuation", () => {
      assert.deepStrictEqual(Control.RESULTS,
        ["completed", "unavailable", "cancelled", "failed", "timeout"]);
      assert.strictEqual(LiveRun.assertCompletedControlAck({ result: "completed" },
        "ordinary_forward").result, "completed");
    });
    ["failed", "unavailable", "cancelled", "timeout"].forEach((result) => {
      negative("control " + result + " halts immediately", "material_shop_control_not_completed",
        () => LiveRun.assertCompletedControlAck({ result }, "ordinary_forward"));
    });
    test("unlocked commit risk begins before request publication", () => {
      assert.strictEqual(LiveRun.authorityRiskBeforeIssue("unlocked_commit", false), true);
      assert.strictEqual(LiveRun.authorityRiskBeforeIssue("unlocked_settlement", false), false);
      assert.strictEqual(LiveRun.authorityRiskBeforeIssue("ordinary_close", true), true);
      assert.strictEqual(LiveRun.requiresRecoveryBlocker(true,
        { releasedBeforeCommit: true }, null), true);
      assert.strictEqual(LiveRun.requiresRecoveryBlocker(false,
        { releasedBeforeCommit: true }, null), false);
      assert.strictEqual(LiveRun.requiresRecoveryBlocker(false,
        { preservedForManualRecovery: true }, null), true);
    });
    test("commit risk assignment precedes control-channel publication in live runner source", () => {
      const source = fs.readFileSync(path.join(__dirname, "run-live-journey.js"), "utf8");
      const issue = source.indexOf("const request = channel.issue(step.id, args.timeoutMs)");
      const risk = source.lastIndexOf("authorityRiskBeforeIssue(step.id", issue);
      const exposed = source.indexOf("visible_control_required", issue);
      assert(issue >= 0 && risk >= 0 && risk < issue && exposed > issue);
    });
    test("post-issue commit failure writes one durable manual-recovery blocker", () => {
      const blockerDir = path.join(testBase, "blocker-behavior");
      fs.mkdirSync(blockerDir);
      const persisted = LiveRun.writeRecoveryBlocker({ runDir: blockerDir,
        plan: { runId: "material-shop-self-test" },
        preparation: { resourcesRoot: "C:\\owned\\resources",
          slots: { targetSlot: "cf7_agent_a5_material_shop_run_test" } },
        commitMayHaveReachedAuthority: true,
        error: Object.assign(new Error("provider failed after click"), { code: "provider_failed" }),
        cleanupResult: { preservedForManualRecovery: true }, cleanupError: null });
      assert(fs.existsSync(persisted.blockerPath));
      assert.strictEqual(persisted.blocker.commitMayHaveReachedAuthority, true);
      assert.strictEqual(persisted.blocker.cleanupResult.preservedForManualRecovery, true);
      const unsigned = clone(persisted.blocker);
      delete unsigned.blockerSha256;
      assert.strictEqual(persisted.blocker.blockerSha256,
        Evidence.sha256Text(Evidence.canonicalJson(unsigned)));
    });
    test("post-release failure reports actual durable recovery state", () => {
      const released = SharedAdapter.recoveryDisposition({
        lockPresent: false, recoveryPresent: false,
      });
      assert.strictEqual(released.preservedForManualRecovery, false);
      assert.strictEqual(released.cloneAlreadyReleased, true);
      const preserved = SharedAdapter.recoveryDisposition({
        lockPresent: true, recoveryPresent: true,
      });
      assert.strictEqual(preserved.preservedForManualRecovery, true);
      assert.strictEqual(preserved.cloneAlreadyReleased, false);
    });
    test("A5 replays partial-start shutdown and clone-release gating behavior", () => {
      const npcSelfTest = path.join(__dirname, "..", "npc", "self-test.js");
      const script = [
        "const suite=require(" + JSON.stringify(npcSelfTest) + ");",
        "suite.run({quiet:true,filter:(t)=>/shared adapter retains exact ownership|partial-start|unbound partial start/.test(t.name)})",
        ".then((r)=>process.stdout.write(JSON.stringify(r)))",
        ".catch((e)=>{console.error(e.stack||String(e));process.exit(1);});",
      ].join("");
      const result = childProcess.spawnSync(process.execPath, ["-e", script], {
        cwd: Common.CANONICAL_ROOT, encoding: "utf8", windowsHide: true,
        maxBuffer: 4 * 1024 * 1024,
      });
      assert.strictEqual(result.status, 0, String(result.stderr || result.stdout || ""));
      assert.deepStrictEqual(JSON.parse(String(result.stdout || "{}")), { passed: 5, total: 5 });
    });
    let preControlReceipt;
    test("pre-control failure receipt binds terminal cleanup and unchanged sealed save", () => {
      const transcript = path.join(preControlBase, "passive-transcript.jsonl");
      fs.writeFileSync(transcript, "", { encoding: "utf8", flag: "wx" });
      ["requests", "acks", "captures"].forEach((name) =>
        fs.mkdirSync(path.join(preControlBase, "control", name), { recursive: true }));
      const itemName = "食用油";
      const slot = "cf7_agent_a5_material_shop_pre_control";
      const save = { version: "3.0",
        "0": ["self-test", 0, 2403069, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "1": [], inventory: {}, collection: { "材料": { "食用油": 0 } } };
      const saveBytes = Buffer.from(JSON.stringify(save), "utf8");
      const evidenceDir = path.join(preControlBase, "save-state-artifacts");
      fs.mkdirSync(evidenceDir);
      fs.writeFileSync(path.join(evidenceDir, "target-baseline.json"), saveBytes,
        { flag: "wx" });
      const jsonArtifact = { kind: "json", locator: "root:saves/" + slot + ".json",
        sha256: Evidence.sha256Bytes(saveBytes), bytes: saveBytes.length,
        regularFile: true, exactRealPath: true };
      const targetEnd = { schema: CloneGuard.ARTIFACT_SET_SCHEMA, slot,
        appDataRoot: path.resolve(process.env.APPDATA), artifacts: [jsonArtifact],
        capturedAt: "2026-08-12T00:01:00.000Z" };
      targetEnd.setSha256 = Evidence.sha256Text(Evidence.canonicalJson({
        schema: targetEnd.schema, slot: targetEnd.slot,
        appDataRoot: targetEnd.appDataRoot, artifacts: targetEnd.artifacts,
      }));
      const baseline = { schema: CandidateLifecycle.SAVE_STATE_SCHEMA,
        capturedAt: "2026-08-12T00:00:00.000Z", stage: "baseline", slot, itemName,
        relativePath: "save-state-artifacts/target-baseline.json",
        bytes: saveBytes.length, sha256: jsonArtifact.sha256,
        artifactSetSha256: targetEnd.setSha256, money: 2403069, owned: 0 };
      baseline.stateSha256 = Evidence.sha256Text(Evidence.canonicalJson({
        slot, itemName, money: baseline.money, owned: baseline.owned,
      }));
      baseline.semanticSha256 = CandidateLifecycle.saveSemanticSha256(save);
      baseline.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(baseline));
      const candidatePath = path.join(preControlBase, "candidate", "LauncherCore.exe");
      const pid = 43210;
      const session = { schema: LauncherObservation.SESSION_SCHEMA,
        apiVersion: LauncherObservation.API_VERSION,
        openedAt: "2026-08-12T00:00:01.000Z", pid, httpPort: 40101,
        socketPort: 40102, portsFile: "tmp/ports.json", portsFileSha256: "1".repeat(64),
        portsFileBytes: 1, credentialFile: path.join(preControlBase, "credential.json"),
        credentialFileSha256: "2".repeat(64), credentialFileBytes: 1,
        credentialTokenSha256: "3".repeat(64),
        credentialHeader: "X-CF7-Automation-Token",
        processStartUtcTicks: "638900000000000001", lifecycleId: "lifecycle-pre-control",
        capabilities: ["legacy.console", "legacy.logs", "legacy.status", "legacy.task"] };
      session.sessionEvidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(session));
      const residue = { schema: LauncherObservation.RESIDUE_SCHEMA,
        apiVersion: LauncherObservation.API_VERSION,
        observedAt: "2026-08-12T00:00:03.000Z", expectedPid: pid,
        expectedProcessPath: candidatePath, pidAbsent: true, candidateProcessAbsent: true,
        observedLauncherPids: [], ports: [{ port: 40101, open: false },
          { port: 40102, open: false }, { port: 40103, open: false }],
        portsFile: path.join(preControlBase, "ports.json"), portsFileAbsent: true,
        credentialFile: session.credentialFile, credentialFileAbsent: true, stableSamples: 3 };
      residue.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(residue));
      const shutdown = { schema: "workbench-live-e2e.npc.failure-cleanup-shutdown.v1",
        requestedAt: "2026-08-12T00:00:02.000Z",
        completedAt: "2026-08-12T00:00:03.000Z", pid,
        runtimeIdentity: { pid, candidateRoot: path.dirname(candidatePath),
          processPath: candidatePath }, sessionEvidence: session,
        cdpBinding: { runtimePid: pid, port: 40103 }, response: { success: true },
        responseSha256: Evidence.sha256Text(Evidence.canonicalJson({ success: true })),
        responseSucceeded: true };
      shutdown.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(shutdown));
      const cloneRelease = { schema: CloneGuard.RELEASE_SCHEMA,
        apiVersion: CloneGuard.API_VERSION, releasedAt: "2026-08-12T00:00:04.000Z",
        seedEnd: null, targetEnd, backupsVerified: true,
        preparedRecoveryRecordSha256: "4".repeat(64),
        lockRelease: { lockFileAbsent: true },
        recoveryClear: { recoveryFileAbsent: true } };
      cloneRelease.releaseSha256 = Evidence.sha256Text(Evidence.canonicalJson(cloneRelease));
      const cleanupResult = { runtimeCleanupVerified: true, shutdownSucceeded: true,
        preservedForManualRecovery: false, shutdown, residue, releasedBeforeCommit: true,
        cloneAlreadyReleased: true, cloneRelease };
      const operationHandle = RunOperationLease.acquire({ runDir: preControlBase,
        runId: path.basename(preControlBase), mode: "live_execution",
        preparationSha256: "a".repeat(64), buildSha256: "b".repeat(64) });
      RunOperationLease.markExecutionStarted(operationHandle);
      const operationTerminal = RunOperationLease.release(operationHandle);
      preControlReceipt = LiveRun.writePreControlFailureCleanupReceipt({
        runDir: preControlBase,
        preparation: { runId: path.basename(preControlBase),
          preparationSha256: "a".repeat(64), slots: { targetSlot: slot } },
        build: { buildSha256: "b".repeat(64) },
        plan: { planSha256: "c".repeat(64) }, operationHandle, operationTerminal,
        error: Object.assign(new Error("ready failed"), { code: "runtime_title_frame_missing" }),
        cleanupResult, firstRuntime: null, admissions: [], itemName,
        baselineSaveState: baseline,
      });
      assert(fs.existsSync(preControlReceipt.receiptPath));
      assert.strictEqual(preControlReceipt.receipt.operationTerminal.active, false);
      assert.strictEqual(preControlReceipt.receipt.baselineSaveState.money, 2403069);
      assert.strictEqual(preControlReceipt.receipt.baselineSaveState.owned, 0);
    });
    negative("pre-control receipt cannot hide target save mutation",
      "material_shop_pre_control_baseline_changed", () => {
        const drift = clone(preControlReceipt.receipt);
        drift.cleanup.cloneRelease.targetEnd.artifacts[0].sha256 = "d".repeat(64);
        const target = drift.cleanup.cloneRelease.targetEnd;
        target.setSha256 = Evidence.sha256Text(Evidence.canonicalJson({
          schema: target.schema, slot: target.slot,
          appDataRoot: target.appDataRoot, artifacts: target.artifacts,
        }));
        delete drift.cleanup.cloneRelease.releaseSha256;
        drift.cleanup.cloneRelease.releaseSha256 = Evidence.sha256Text(
          Evidence.canonicalJson(drift.cleanup.cloneRelease));
        LiveRun.verifyPreControlBaselineInvariant(preControlBase, drift);
      });
    test("pre-control cleanup archives the live operation before receipt persistence", () => {
      const source = fs.readFileSync(path.join(__dirname, "run-live-journey.js"), "utf8");
      const catchStart = source.indexOf("const preControlCleanupEligible");
      const terminal = source.indexOf("RunOperationLease.release(operationHandle)", catchStart);
      const receipt = source.indexOf("writePreControlFailureCleanupReceipt", terminal);
      assert(catchStart >= 0 && terminal > catchStart && receipt > terminal);
    });
    const releaseIntentContext = { plan,
      preparation: { preparationSha256: "1".repeat(64),
        resourcesRoot: Common.CANONICAL_ROOT },
      build: { buildSha256: "2".repeat(64), candidateRoot: path.join(
        Common.CANONICAL_ROOT, "tmp", "runtime-candidates", "v2", "candidate-self-test") },
      raw: { rawSha256: "3".repeat(64) },
      evidence: { evidenceSha256: "4".repeat(64) } };
    const releaseIntent = FinalizeCloneRelease.createIntent(releaseIntentContext,
      "2026-08-11T00:00:00.000Z");
    test("clone release intent durably binds the resumable finalization context", () => {
      assert.strictEqual(FinalizeCloneRelease.validateIntent(releaseIntent,
        releaseIntentContext), releaseIntent);
    });
    negative("foreign raw evidence cannot reuse clone release intent",
      "material_shop_clone_release_intent_invalid", () => {
        const foreign = clone(releaseIntentContext);
        foreign.raw.rawSha256 = "5".repeat(64);
        FinalizeCloneRelease.validateIntent(releaseIntent, foreign);
      });
    test("post-release receipt failure resumes through one durable finalization marker", () => {
      const finalizationDir = path.join(testBase, "release-finalization-behavior");
      fs.mkdirSync(finalizationDir);
      const finalizationContext = Object.assign({}, releaseIntentContext, {
        preparation: Object.assign({}, releaseIntentContext.preparation, {
          runDir: finalizationDir,
        }),
      });
      const args = {
        preparation: path.join(finalizationDir, "preparation.json"),
        build: path.join(finalizationDir, "candidate-build.json"),
        raw: path.join(finalizationDir, "raw-candidate-journey.json"),
        evidence: path.join(finalizationDir, "journey-evidence.json"),
        intent: path.join(finalizationDir, "clone-release-intent.json"),
        out: path.join(finalizationDir, "release.json"),
      };
      const persisted = LiveRun.writeRecoveryBlocker({ runDir: finalizationDir,
        plan, preparation: { resourcesRoot: Common.CANONICAL_ROOT, slots: plan.slots },
        preparationPath: args.preparation, buildPath: args.build,
        releaseIntentPath: args.intent, commitMayHaveReachedAuthority: true,
        error: Object.assign(new Error("release receipt write failed"), {
          code: "receipt_write_failed",
        }), cleanupResult: { preservedForManualRecovery: false,
          cloneAlreadyReleased: true, cloneInspection: null }, cleanupError: null });
      assert.strictEqual(path.basename(persisted.blockerPath),
        FinalizeCloneRelease.FINALIZATION_REQUIRED_NAME);
      const marker = FinalizeCloneRelease.loadFinalizationMarker(finalizationDir,
        finalizationContext, args);
      assert.strictEqual(marker.active, true);
      const markerEvidence = FinalizeCloneRelease.createMarkerEvidence(marker);
      FinalizeCloneRelease.validateMarkerEvidence(markerEvidence,
        finalizationContext, "required");
      const resolvedPath = FinalizeCloneRelease.resolveFinalizationMarker(marker);
      assert(!fs.existsSync(marker.requiredPath));
      assert(fs.existsSync(resolvedPath));
      const replay = FinalizeCloneRelease.loadFinalizationMarker(finalizationDir,
        finalizationContext, args);
      assert.strictEqual(replay.active, false);
      assert.strictEqual(replay.resolvedPath, resolvedPath);
      FinalizeCloneRelease.validateMarkerEvidence(markerEvidence,
        finalizationContext, "final");
      const original = fs.readFileSync(resolvedPath);
      fs.unlinkSync(resolvedPath);
      let missingError = null;
      try {
        FinalizeCloneRelease.validateMarkerEvidence(markerEvidence,
          finalizationContext, "final");
      } catch (error) { missingError = error; }
      finally { fs.writeFileSync(resolvedPath, original, { flag: "wx" }); }
      assert(missingError);
      assert.strictEqual(missingError.code,
        "material_shop_clone_release_marker_evidence_invalid");
      const foreign = clone(persisted.blocker);
      foreign.originalError.code = "foreign_marker";
      fs.writeFileSync(resolvedPath, JSON.stringify(foreign, null, 2) + "\n", "utf8");
      let driftError = null;
      try {
        FinalizeCloneRelease.validateMarkerEvidence(markerEvidence,
          finalizationContext, "final");
      } catch (error) { driftError = error; }
      finally { fs.writeFileSync(resolvedPath, original); }
      assert(driftError);
      assert.strictEqual(driftError.code,
        "material_shop_clone_release_marker_evidence_invalid");
    });
    test("live clone release requires zero finalization markers", () => {
      const liveDir = path.join(testBase, "live-release-marker-none");
      fs.mkdirSync(liveDir);
      const liveContext = Object.assign({}, releaseIntentContext, {
        preparation: Object.assign({}, releaseIntentContext.preparation, { runDir: liveDir }),
      });
      const none = FinalizeCloneRelease.createMarkerEvidence(null);
      FinalizeCloneRelease.validateMarkerEvidence(none, liveContext, "final");
      fs.writeFileSync(path.join(liveDir,
        FinalizeCloneRelease.FINALIZATION_RESOLVED_PREFIX + "0".repeat(16) + ".json"),
      "{}\n", "utf8");
      let error = null;
      try { FinalizeCloneRelease.validateMarkerEvidence(none, liveContext, "final"); }
      catch (failure) { error = failure; }
      assert(error);
      assert.strictEqual(error.code, "material_shop_clone_release_marker_evidence_invalid");
    });
    negative("controller business API text is forbidden", "material_shop_controller_api_forbidden",
      () => Protocol.assertNoControllerApi("Bridge.send({cmd:'tradeCommit'})", "self-test"));

    const captureRequest = channel.issue("materials_visual_current_window", 60000);
    const captureOperationPath = writeOperatorArtifact(controlRun,
      "materials-visual-operation", { tool: "computer-use",
        operationId: "capture-self-test", requestId: captureRequest.requestId,
        pid: 100, window: "window-100" });
    const captureOperation = operationArtifactAfter(captureOperationPath,
      captureRequest.issuedAt);
    const captureCandidateBinding = AckControl.candidateBinding(
      captureRequest, candidateAdmission);
    const pngSource = path.join(testBase, "capture-source.png");
    fs.writeFileSync(pngSource, PngContract.createSolidPngForFixture(800, 450, [1, 2, 3, 255]));
    if (fs.statSync(pngSource).mtimeMs < Date.parse(captureRequest.issuedAt)) {
      const sourceTime = new Date(Date.parse(captureRequest.issuedAt) + 1);
      fs.utimesSync(pngSource, sourceTime, sourceTime);
    }
    const capturedAt = new Date(Math.max(Date.now(), fs.statSync(pngSource).mtimeMs) + 1)
      .toISOString();
    const captureAck = Control.createAck({ root: Common.CANONICAL_ROOT,
      runDir: controlRun, plan, request: captureRequest,
      transport: Protocol.PREFERRED_TRANSPORT, result: "completed",
      operationId: "capture-self-test", rawOperationArtifact: captureOperation,
      candidateBinding: captureCandidateBinding, completedAt: capturedAt,
      capturePath: pngSource, captureSha256: Evidence.sha256File(pngSource) });
    const capture = captureAck.captureReceipt;
    test("strict PNG capture stages and replays", () => {
      Capture.verifyCapture(Common.CANONICAL_ROOT, controlRun, capture);
      assert.strictEqual(capture.width, 800);
      assert.strictEqual(capture.height, 450);
      assert.strictEqual(capture.operationArtifactSha256, captureOperation.sha256);
      assert.strictEqual(capture.candidateBinding.pid, 100);
    });
    negative("capture cannot claim a foreign candidate binding",
      "material_shop_control_candidate_binding_drift", () => {
        const ack = clone(captureAck);
        ack.provider.candidateBinding.pid = 101;
        ack.captureReceipt.candidateBinding.pid = 101;
        ack.captureReceipt.captureReceiptSha256 = Evidence.sha256Text(
          Evidence.canonicalJson(Capture.stableCapture(ack.captureReceipt)));
        Control.validateAck(ack, captureRequest, plan, controlRun);
        require("./journey-verifier").assertControlCandidateBinding(
          { request: captureRequest, ack }, candidateAdmission,
          "materials_visual_current_window");
      });
    const staleCaptureRequest = channel.issue("materials_keyboard", 60000);
    const staleCaptureOperationPath = writeOperatorArtifact(controlRun,
      "stale-capture-operation", { tool: "computer-use",
        requestId: staleCaptureRequest.requestId, pid: 100 });
    const staleCaptureOperation = operationArtifactAfter(staleCaptureOperationPath,
      staleCaptureRequest.issuedAt);
    const stalePng = path.join(testBase, "stale-capture-source.png");
    fs.writeFileSync(stalePng, PngContract.createSolidPngForFixture(800, 450,
      [3, 2, 1, 255]));
    const stalePngTime = new Date(Date.parse(staleCaptureRequest.issuedAt) - 1000);
    fs.utimesSync(stalePng, stalePngTime, stalePngTime);
    negative("stale screenshot source cannot be staged for a new request",
      "material_shop_capture_provenance_invalid", () => {
        Control.createAck({ root: Common.CANONICAL_ROOT, runDir: controlRun,
          plan, request: staleCaptureRequest, transport: Protocol.PREFERRED_TRANSPORT,
          result: "completed", operationId: "stale-capture-operation",
          rawOperationArtifact: staleCaptureOperation,
          candidateBinding: AckControl.candidateBinding(staleCaptureRequest,
            candidateAdmission), completedAt: completedAfterOperation(staleCaptureOperation),
          capturePath: stalePng, captureSha256: Evidence.sha256File(stalePng) });
      });
    const capturePath = path.join(controlRun, capture.capture.relativePath.replace(/\//g, path.sep));
    fs.appendFileSync(capturePath, "tamper");
    negative("PNG byte drift fails", "capture_digest_mismatch", () => {
      Capture.verifyCapture(Common.CANONICAL_ROOT, controlRun, capture);
    });

    const browserReceipt = fakeBrowserReceipt();
    test("static gate validates three viewports and material-shop 11", () => {
      Accept.validateCraftingBrowserReceipt(browserReceipt);
    });
    negative("static gate cannot omit material-shop scenario", "material_shop_static_gate_receipt_invalid",
      () => {
        const drift = clone(browserReceipt);
        drift.result.materialShopScenarioCount = 0;
        reseal(drift, "evidenceSha256");
        Accept.validateCraftingBrowserReceipt(drift);
      });

    const staticToolchainSource = path.join(testBase, "static-toolchain-source");
    const staticToolchainResources = path.join(testBase, "static-toolchain-resources");
    const staticToolchainFiles = [
      "launcher/perf/node_modules/playwright-core/browsers.json",
      "launcher/perf/node_modules/playwright/index.js",
    ];
    for (const relative of staticToolchainFiles) {
      const source = path.join(staticToolchainSource, relative.replace(/\//g, path.sep));
      fs.mkdirSync(path.dirname(source), { recursive: true });
      fs.writeFileSync(source, "sealed:" + relative + "\n", { flag: "wx" });
    }
    fs.mkdirSync(path.join(staticToolchainResources, "launcher", "perf"), { recursive: true });
    const staticToolchainInventory = path.join(staticToolchainResources, "tools",
      "workbench-live-e2e", "crafting", "browser-module-inventory.v1.json");
    fs.mkdirSync(path.dirname(staticToolchainInventory), { recursive: true });
    fs.writeFileSync(staticToolchainInventory, JSON.stringify({
      schema: "workbench-live-e2e.crafting.browser-module-inventory.v1",
      nodeVersion: process.version, files: staticToolchainFiles,
    }) + "\n", { flag: "wx" });
    const staticFixtureRelative = "launcher/web/modules/crafting/dev/harness.html";
    const staticFixtureSource = path.join(staticToolchainSource,
      staticFixtureRelative.replace(/\//g, path.sep));
    const staticFixtureDestination = path.join(staticToolchainResources,
      staticFixtureRelative.replace(/\//g, path.sep));
    fs.mkdirSync(path.dirname(staticFixtureSource), { recursive: true });
    fs.mkdirSync(path.dirname(staticFixtureDestination), { recursive: true });
    fs.writeFileSync(staticFixtureSource, "canonical verifier fixture\n", { flag: "wx" });
    fs.writeFileSync(staticFixtureDestination, "materialized verifier fixture\n", { flag: "wx" });
    const staticBrowserInventory = path.join(staticToolchainResources, "tools",
      "workbench-live-e2e", "crafting", "browser-resource-inventory.v1.json");
    fs.writeFileSync(staticBrowserInventory, JSON.stringify({
      schema: "workbench-live-e2e.browser-resource-inventory.v1",
      files: ["modules/crafting/dev/harness.html"], optionalFiles: [],
    }) + "\n", { flag: "wx" });
    const staticToolchainContext = { preparation: { resourcesRoot: staticToolchainResources },
      build: { externalToolchain: { canonicalRoot: staticToolchainSource } } };
    test("static gate projects only inventory-listed Playwright files and removes them", () => {
      const value = Accept.withStaticGateToolchainProjection(staticToolchainContext, () => {
        for (const relative of staticToolchainFiles) {
          assert.strictEqual(fs.readFileSync(path.join(staticToolchainResources,
            relative.replace(/\//g, path.sep)), "utf8"), "sealed:" + relative + "\n");
        }
        assert.strictEqual(fs.readFileSync(staticFixtureDestination, "utf8"),
          "canonical verifier fixture\n");
        return "gate-complete";
      });
      assert.strictEqual(value, "gate-complete");
      assert.strictEqual(fs.existsSync(path.join(staticToolchainResources,
        "launcher", "perf", "node_modules")), false);
      assert.strictEqual(fs.readFileSync(staticFixtureDestination, "utf8"),
        "materialized verifier fixture\n");
    });
    test("static gate removes the transient toolchain when the browser gate fails", () => {
      assert.throws(() => Accept.withStaticGateToolchainProjection(staticToolchainContext,
        () => { throw new Error("fixture gate failure"); }), /fixture gate failure/);
      assert.strictEqual(fs.existsSync(path.join(staticToolchainResources,
        "launcher", "perf", "node_modules")), false);
      assert.strictEqual(fs.readFileSync(staticFixtureDestination, "utf8"),
        "materialized verifier fixture\n");
    });
    negative("static gate refuses a preexisting materialized node_modules",
      "material_shop_static_toolchain_destination_present", () => {
        const destination = path.join(staticToolchainResources,
          "launcher", "perf", "node_modules");
        fs.mkdirSync(destination, { recursive: false });
        try { Accept.withStaticGateToolchainProjection(staticToolchainContext, () => null); }
        finally { fs.rmSync(destination, { recursive: true, force: false }); }
      });

    const reviewRequest = { requestedAt: "2026-08-11T00:00:00.000Z",
      requestSha256: "4".repeat(64), captureSetSha256: "5".repeat(64),
      reviewScope: "visible_png_content_only_not_input_or_capture_provenance",
      claims: [{ claimId: "materials_current_window_layout",
        captureSteps: ["materials_visual_current_window"] }] };
    const reviewReceipt = fakeReviewReceipt(reviewRequest);
    test("independent visible PNG review receipt is exact and sealed", () => {
      Accept.validateReviewReceipt(reviewReceipt, reviewRequest);
    });
    negative("review without independence attestation fails", "material_shop_review_receipt_invalid",
      () => {
        const drift = clone(reviewReceipt);
        drift.reviewer.independenceAttested = false;
        reseal(drift, "reviewReceiptSha256");
        Accept.validateReviewReceipt(drift, reviewRequest);
      });
    negative("visual reviewer cannot claim input or capture provenance",
      "material_shop_review_receipt_invalid", () => {
        const drift = clone(reviewReceipt);
        drift.reviewer.reviewScope = "visible_png_and_input_provenance";
        reseal(drift, "reviewReceiptSha256");
        Accept.validateReviewReceipt(drift, reviewRequest);
      });
    negative("review cannot silently omit a claim", "material_shop_review_receipt_invalid", () => {
      const drift = clone(reviewReceipt);
      drift.verdicts = [];
      reseal(drift, "reviewReceiptSha256");
      Accept.validateReviewReceipt(drift, reviewRequest);
    });

    test("release-worktree has exact remove and no global prune", () => {
      const source = fs.readFileSync(path.join(__dirname, "release-worktree.js"), "utf8");
      assert(source.includes('["worktree", "remove", "--force", destination]'));
      assert(!source.includes('"worktree", "prune"'));
      const intentWrite = source.indexOf("writeJsonAtomicNew(path.join(context.preparation.runDir",
        source.indexOf("function release(options)"));
      const remove = source.indexOf('["worktree", "remove", "--force", destination]',
        intentWrite);
      const finalize = source.indexOf("return finalizeRemoval(context.preparation.runDir)",
        remove);
      assert(intentWrite >= 0 && intentWrite < remove && remove < finalize);
    });
    test("ordinary NPCShop close owner is captured before Host settlement wait", () => {
      const close = LiveRun.latestNpcshopClose({ events: [{ kind: "bridge_send",
        message: { type: "panel", panel: "npcshop", cmd: "close",
          panelInstanceId: "npcshop.self-test", reason: "button" } }] });
      assert.strictEqual(close.panelInstanceId, "npcshop.self-test");
    });
    negative("duplicate ordinary close owner fails", "material_shop_ordinary_close_capture_invalid",
      () => LiveRun.latestNpcshopClose({ events: [
        { kind: "bridge_send", message: { type: "panel", panel: "npcshop", cmd: "close",
          panelInstanceId: "npcshop.one", reason: "button" } },
        { kind: "bridge_send", message: { type: "panel", panel: "npcshop", cmd: "close",
          panelInstanceId: "npcshop.two", reason: "escape" } },
      ] }));

    const Verifier = require("./journey-verifier");
    const forward = { event: { sequence: 1, observedAt: "2026-08-11T00:00:00.000Z" },
      message: { type: "panel", panel: "crafting", cmd: "open_npc_shop",
        callId: "material.forward.self-test", panelInstanceId: "crafting.self-test",
        source: "crafting_materials", materialSnapshotId: "materials.self-test",
        materialName: "食用油", shopId: "厨师", catalogIndex: 24 } };
    const targetOpen = { event: { sequence: 2, observedAt: "2026-08-11T00:00:05.000Z" },
      message: { type: "panel_cmd", panel: "npcshop", cmd: "open" } };
    const forwardRecords = [
      hostRecord(1, "[Panel] HandlePanelMessage: task=panel panel=crafting domain=other"
        + " cmd=open_npc_shop callId=" + forward.message.callId + " payload=redacted len=301"),
      hostRecord(2, "event=authority_flash_call_bound domain=material_shop_access webCallIdRef="
        + Verifier.authorityReference(forward.message.callId)
        + " flashCallId=41 panel=crafting panelInstanceIdRef="
        + Verifier.authorityReference(forward.message.panelInstanceId)
        + " cmd=open_npc_shop action=craftingMaterialShopAuthorize"),
      hostRecord(3, "[MaterialShopAccessTask] -> Flash: task=cmd"
        + " cmd=craftingMaterialShopAuthorize callId=41 payload=redacted len=188"),
      hostRecord(4, "[XmlSocket:JSON] task=material_shop_access_response"
        + " cmd=craftingMaterialShopAuthorize callId=41 success=true payload=redacted len=220"),
    ];
    test("material forward Host mapping binds hashed call/owner refs and one same fid", () => {
      const mapping = Verifier.materialForwardMapping(forward, targetOpen, forwardRecords);
      assert.strictEqual(mapping.flashCallId, 41);
      assert.strictEqual(mapping.panelInstanceId, forward.message.panelInstanceId);
    });
    negative("foreign material forward reference cannot bind", "material_shop_forward_host_binding_count_invalid",
      () => {
        const records = clone(forwardRecords);
        records[1].body = records[1].body.replace(
          Verifier.authorityReference(forward.message.callId), "sha256_" + "0".repeat(24));
        Verifier.materialForwardMapping(forward, targetOpen, records);
      });
    negative("material forward fid mismatch cannot bind", "material_shop_forward_host_send_count_invalid",
      () => {
        const records = clone(forwardRecords);
        records[2].body = records[2].body.replace("callId=41", "callId=42");
        Verifier.materialForwardMapping(forward, targetOpen, records);
      });
    negative("duplicate material forward binding cannot bind",
      "material_shop_forward_host_binding_count_invalid", () => {
        const records = clone(forwardRecords);
        records.push(Object.assign({}, records[1], { lineNumber: 5,
          observedAt: "2026-08-11T00:00:05.000Z" }));
        Verifier.materialForwardMapping(forward, Object.assign({}, targetOpen, {
          event: { sequence: 2, observedAt: "2026-08-11T00:00:06.000Z" } }), records);
      });

    const reverse = { event: { sequence: 3, observedAt: "2026-08-11T00:00:09.000Z" },
      message: { type: "panel", panel: "npcshop", cmd: "return_crafting_materials",
        callId: "material.reverse.self-test", panelInstanceId: "npcshop.self-test" } };
    const reverseTarget = { event: { sequence: 4, observedAt: "2026-08-11T00:00:13.000Z" },
      message: { type: "panel_cmd", panel: "crafting", cmd: "open" } };
    const reverseRecords = [
      hostRecord(10, "[Panel] HandlePanelMessage: task=panel panel=npcshop domain=other"
        + " cmd=return_crafting_materials callId=" + reverse.message.callId
        + " payload=redacted len=170"),
      hostRecord(11, "[PanelHost] closed: npcshop"),
      hostRecord(12, "[PanelHost] opened: crafting rect=1024x576"),
    ];
    test("reverse Host mapping proves NPC source retire and crafting target open", () => {
      const mapping = Verifier.reverseHostMapping(reverse, reverseTarget, reverseRecords);
      assert.strictEqual(mapping.closedLine, 11);
      assert.strictEqual(mapping.openedLine, 12);
    });
    negative("reverse without exact crafting target Host open fails",
      "material_shop_reverse_host_open_invalid", () => {
        const records = clone(reverseRecords);
        records[2].body = "[PanelHost] opened: npcshop rect=1024x576";
        Verifier.reverseHostMapping(reverse, reverseTarget, records);
      });

    const closeEvent = { event: { sequence: 5, observedAt: "2026-08-11T00:00:19.000Z" },
      message: { type: "panel", panel: "npcshop", cmd: "close",
        panelInstanceId: "npcshop.self-test", reason: "button" } };
    const closeRecords = [
      hostRecord(20, "[Panel] HandlePanelMessage: task=panel panel=npcshop domain=other"
        + " cmd=close callId=other payload=redacted len=119"),
      hostRecord(21, "[PanelHost] closed: npcshop"),
      hostRecord(22, "event=panel_exact_close_completed panel=npcshop"
        + " panelInstanceId=npcshop.self-test"),
    ];
    test("real domain=other ordinary close maps request retire and exact owner completion", () => {
      const mapping = Verifier.closeHostMapping(closeEvent, "npcshop", closeRecords,
        closeRecords);
      assert.strictEqual(mapping.completionLine, 22);
    });
    negative("legacy domain=none close projection is rejected",
      "material_shop_close_host_panel_count_invalid", () => {
        const records = clone(closeRecords);
        records[0].body = records[0].body.replace("domain=other", "domain=none");
        Verifier.closeHostMapping(closeEvent, "npcshop", records, records);
      });

    const releaseSlot = "cf7_agent_a5_material_shop_run_test";
    const rawForRelease = { boundaries: { candidateExecuted: true, e2eVerified: false },
      persistence: { archive: {}, shutdown: {} },
      controls: ["safeexit", "exit_confirm", "restart_candidate", "restart_readback",
        "restart_close", "supported_shutdown"].map((step) => ({ request: { step },
        ack: { result: "completed" } })) };
    const acceptanceForRelease = { status: "e2e_verified", deployment: "NOT_DEPLOYED",
      boundaries: { e2eVerified: true, promoted: false } };
    const cloneRelease = { cloneLockReleased: true, recoveryCleared: true };
    test("worktree release safety requires accepted SAFEEXIT/restart and absent lock/recovery", () => {
      assert.strictEqual(Release.assertReleaseSafetySignals({
        acceptance: acceptanceForRelease, raw: rawForRelease, cloneRelease,
        blockerFiles: [], lockInspection: lockInspection(releaseSlot),
        targetSlot: releaseSlot }).accepted, true);
    });
    negative("recovery blocker prevents worktree release",
      "material_shop_worktree_release_not_admitted", () => {
        Release.assertReleaseSafetySignals({ acceptance: acceptanceForRelease,
          raw: rawForRelease, cloneRelease, blockerFiles: ["recovery-blocker-1.json"],
          lockInspection: lockInspection(releaseSlot), targetSlot: releaseSlot });
      });
    negative("active release finalization marker prevents worktree release",
      "material_shop_worktree_release_not_admitted", () => {
        Release.assertReleaseSafetySignals({ acceptance: acceptanceForRelease,
          raw: rawForRelease, cloneRelease,
          blockerFiles: [FinalizeCloneRelease.FINALIZATION_REQUIRED_NAME],
          lockInspection: lockInspection(releaseSlot), targetSlot: releaseSlot });
      });
    negative("active clone lock prevents worktree release",
      "material_shop_release_clone_inspection_invalid", () => {
        Release.assertReleaseSafetySignals({ acceptance: acceptanceForRelease,
          raw: rawForRelease, cloneRelease, blockerFiles: [], targetSlot: releaseSlot,
          lockInspection: lockInspection(releaseSlot, { lockPresent: true,
            ownerState: "owner_active", ownerPid: 123, recordSha256: "a".repeat(64),
            ownerProcessStartUtcTicks: "1234567890123456",
            observedProcessStartUtcTicks: "1234567890123456" }) });
      });
    negative("missing SAFEEXIT completion prevents worktree release",
      "material_shop_worktree_release_not_admitted", () => {
        const raw = clone(rawForRelease);
        raw.controls = raw.controls.filter((entry) => entry.request.step !== "safeexit");
        Release.assertReleaseSafetySignals({ acceptance: acceptanceForRelease,
          raw, cloneRelease, blockerFiles: [], lockInspection: lockInspection(releaseSlot),
          targetSlot: releaseSlot });
      });
    negative("non-e2e acceptance prevents worktree release",
      "material_shop_worktree_release_not_admitted", () => {
        const acceptance = clone(acceptanceForRelease);
        acceptance.status = "candidate_captured";
        Release.assertReleaseSafetySignals({ acceptance, raw: rawForRelease,
          cloneRelease, blockerFiles: [], lockInspection: lockInspection(releaseSlot),
          targetSlot: releaseSlot });
      });
    const completion = (label) => ({ schema: "completion", label });
    const completionSha = (label) => Evidence.sha256Text(
      Evidence.canonicalJson(completion(label)));
    const rawAgentForRelease = { schema: Verifier.AGENT_RUNTIME_RAW_SCHEMA,
      boundaries: { candidateExecuted: true, e2eVerified: false },
      controls: ["trusted_runner_persistence_shutdown", "restart_candidate",
        "restart_readback", "restart_close", "trusted_runner_final_shutdown"]
        .map((stepId) => ({ stepId, completedAt: "2026-08-13T00:00:00.000Z" })),
      sessions: ["first", "restart"].map((label) => ({ label, cleanExit: true,
        completion: completion(label) })),
      persistence: {
        firstShutdown: { sessionLabel: "first", completionSha256: completionSha("first"),
          cleanExit: true },
        restartShutdown: { sessionLabel: "restart",
          completionSha256: completionSha("restart"), cleanExit: true },
        targetAfterRestart: { jsonSha256: "e".repeat(64) },
        saveStates: {
          archive: { sha256: "d".repeat(64), semanticSha256: "f".repeat(64) },
          restart: { sha256: "e".repeat(64), semanticSha256: "f".repeat(64) },
        },
      } };
    test("Agent Runtime release accepts separate raw seals with exact restart target", () => {
      const value = Release.assertReleaseSafetySignals({ acceptance: acceptanceForRelease,
        raw: rawAgentForRelease, cloneRelease, blockerFiles: [],
        lockInspection: lockInspection(releaseSlot), targetSlot: releaseSlot });
      assert.strictEqual(value.targetRestartExact, true);
      assert.strictEqual(value.archiveRestartSemanticEqual, true);
    });
    negative("Agent Runtime release rejects semantic restart drift",
      "material_shop_worktree_release_not_admitted", () => {
        const raw = clone(rawAgentForRelease);
        raw.persistence.saveStates.restart.semanticSha256 = "0".repeat(64);
        Release.assertReleaseSafetySignals({ acceptance: acceptanceForRelease, raw,
          cloneRelease, blockerFiles: [], lockInspection: lockInspection(releaseSlot),
          targetSlot: releaseSlot });
      });
    negative("Agent Runtime release rejects target detached from restart bytes",
      "material_shop_worktree_release_not_admitted", () => {
        const raw = clone(rawAgentForRelease);
        raw.persistence.targetAfterRestart.jsonSha256 = "d".repeat(64);
        Release.assertReleaseSafetySignals({ acceptance: acceptanceForRelease, raw,
          cloneRelease, blockerFiles: [], lockInspection: lockInspection(releaseSlot),
          targetSlot: releaseSlot });
      });
    const releaseBase = path.join(testBase, "release-binding", "materialized");
    const releaseDestination = path.join(releaseBase, "run-1", "resources");
    const releaseCommonDir = path.join(testBase, "canonical.git");
    const releaseContext = { preparation: { materializationSha256: "a".repeat(64),
      resourcesRoot: releaseDestination }, closure: { head: "1".repeat(40) } };
    const releaseMaterialization = { mode: Materialize.PRODUCTION_MODE,
      materializationSha256: "a".repeat(64), gitWorktree: { detached: true,
        head: "1".repeat(40), commonDir: releaseCommonDir } };
    test("release binding admits only exact accepted resources/head/commonDir", () => {
      assert.strictEqual(Release.validateReleaseBinding({ materialization: releaseMaterialization,
        context: releaseContext, destination: releaseDestination, expectedBase: releaseBase,
        canonicalCommonDir: releaseCommonDir, gitMetadataPresent: true }),
      releaseMaterialization);
    });
    negative("sibling resources destination cannot reuse release acceptance",
      "material_shop_worktree_release_target_invalid", () => {
        Release.validateReleaseBinding({ materialization: releaseMaterialization,
          context: releaseContext, destination: path.join(releaseBase, "run-2", "resources"),
          expectedBase: releaseBase, canonicalCommonDir: releaseCommonDir,
          gitMetadataPresent: true });
      });
    negative("foreign worktree HEAD cannot reuse release acceptance",
      "material_shop_worktree_release_target_invalid", () => {
        const drift = clone(releaseMaterialization);
        drift.gitWorktree.head = "2".repeat(40);
        Release.validateReleaseBinding({ materialization: drift, context: releaseContext,
          destination: releaseDestination, expectedBase: releaseBase,
          canonicalCommonDir: releaseCommonDir, gitMetadataPresent: true });
      });
    negative("foreign Git commonDir cannot reuse release acceptance",
      "material_shop_worktree_release_target_invalid", () => {
        const drift = clone(releaseMaterialization);
        drift.gitWorktree.commonDir = path.join(testBase, "foreign.git");
        Release.validateReleaseBinding({ materialization: drift, context: releaseContext,
          destination: releaseDestination, expectedBase: releaseBase,
          canonicalCommonDir: releaseCommonDir, gitMetadataPresent: true });
      });
    negative("release CLI without independent acceptance closure fails",
      "material_shop_release_arguments_invalid", () => {
        Release.parseArgs(["--materialization", "materialization.json", "--out", "release.json",
          "--acknowledge-discard-isolated-worktree"]);
      });
    const removalRunId = path.basename(testBase);
    const removalDestination = path.join(owned, Materialize.MATERIALIZED_DIRECTORY,
      removalRunId, "resources");
    const removalOutput = path.join(testBase, Release.REMOVAL_OUTPUT_NAME);
    const commonDirText = childProcess.execFileSync("git", ["-C", Common.CANONICAL_ROOT,
      "rev-parse", "--git-common-dir"], { encoding: "utf8" }).trim();
    const firstRemovalInspection = lockInspection(releaseSlot, {
      observedAt: "2026-08-11T00:03:00.000Z",
    });
    const resumedRemovalInspection = lockInspection(releaseSlot, {
      observedAt: "2026-08-11T00:04:00.000Z",
    });
    const removalIntent = Release.createRemovalIntent({ runId: removalRunId,
      runDir: testBase, destination: removalDestination, outputPath: removalOutput,
      materializationSha256: "1".repeat(64), preparationSha256: "2".repeat(64),
      closureSha256: "3".repeat(64), buildSha256: "4".repeat(64),
      rawSha256: "5".repeat(64), journeyEvidenceSha256: "6".repeat(64),
      cloneReleaseSha256: "7".repeat(64), acceptanceSha256: "8".repeat(64),
      cloneInspectionSha256: Release.cloneInspectionStateSha256(firstRemovalInspection,
        releaseSlot), gitWorktreeIdentitySha256: "a".repeat(64),
      head: first.head, commonDir: path.resolve(Common.CANONICAL_ROOT, commonDirText) });
    test("fresh lock observation keeps stable state binding and resumes exact intent", () => {
      assert.notStrictEqual(firstRemovalInspection.evidenceSha256,
        resumedRemovalInspection.evidenceSha256);
      const resumedExpected = clone(removalIntent);
      resumedExpected.cloneInspectionSha256 = Release.cloneInspectionStateSha256(
        resumedRemovalInspection, releaseSlot);
      reseal(resumedExpected, "intentSha256");
      assert.strictEqual(resumedExpected.intentSha256, removalIntent.intentSha256);
      const resumed = Release.bindRemovalAttempt(removalIntent, resumedExpected, {
        destinationPresent: true, worktreeListed: true,
      });
      assert.strictEqual(resumed.resumed, true);
      assert.strictEqual(resumed.intent.intentSha256, removalIntent.intentSha256);
    });
    negative("fresh clone inspection state drift cannot resume active removal intent",
      "material_shop_worktree_removal_resume_binding_invalid", () => {
        const driftInspection = lockInspection(releaseSlot, {
          observedAt: "2026-08-11T00:05:00.000Z",
          lockPath: "C:\\foreign\\" + releaseSlot + ".clone.lock",
        });
        const driftExpected = clone(removalIntent);
        driftExpected.cloneInspectionSha256 = Release.cloneInspectionStateSha256(
          driftInspection, releaseSlot);
        reseal(driftExpected, "intentSha256");
        Release.bindRemovalAttempt(removalIntent, driftExpected, {
          destinationPresent: true, worktreeListed: true,
        });
      });
    negative("stale active removal intent cannot reuse a newer acceptance context",
      "material_shop_worktree_removal_resume_binding_invalid", () => {
        const current = clone(removalIntent);
        current.acceptanceSha256 = "b".repeat(64);
        reseal(current, "intentSha256");
        Release.bindRemovalAttempt(removalIntent, current, {
          destinationPresent: true, worktreeListed: true,
        });
      });
    negative("byte-drifted active removal intent fails before resume",
      "material_shop_worktree_removal_intent_invalid", () => {
        const drift = clone(removalIntent);
        drift.rawSha256 = "c".repeat(64);
        Release.bindRemovalAttempt(drift, removalIntent, {
          destinationPresent: true, worktreeListed: true,
        });
      });
    negative("filesystem-only partial removal state cannot retry deletion",
      "material_shop_worktree_removal_partial_state_invalid", () => {
        Release.bindRemovalAttempt(removalIntent, removalIntent, {
          destinationPresent: true, worktreeListed: false,
        });
      });
    negative("Git-only partial removal state cannot retry deletion",
      "material_shop_worktree_removal_partial_state_invalid", () => {
        Release.bindRemovalAttempt(removalIntent, removalIntent, {
          destinationPresent: false, worktreeListed: true,
        });
      });
    negative("completed removal must use the receipt finalizer rather than delete again",
      "material_shop_worktree_removal_already_completed", () => {
        Release.bindRemovalAttempt(removalIntent, removalIntent, {
          destinationPresent: false, worktreeListed: false,
        });
      });
    fs.writeFileSync(path.join(testBase, Release.REMOVAL_INTENT_NAME),
      JSON.stringify(removalIntent, null, 2) + "\n", { encoding: "utf8", flag: "wx" });
    test("post-remove receipt failure preserves durable intent for idempotent finalization", () => {
      let writeError = null;
      try {
        Release.finalizeRemoval(testBase, { writeReceipt: () => {
          throw Object.assign(new Error("simulated receipt failure"), {
            code: "simulated_receipt_failure",
          });
        } });
      } catch (error) { writeError = error; }
      assert(writeError);
      assert.strictEqual(writeError.code, "simulated_receipt_failure");
      assert(fs.existsSync(path.join(testBase, Release.REMOVAL_INTENT_NAME)));
      assert(!fs.existsSync(removalOutput));
      const receipt = Release.finalizeRemoval(testBase);
      assert(fs.existsSync(removalOutput));
      assert(!fs.existsSync(path.join(testBase, Release.REMOVAL_INTENT_NAME)));
      assert(fs.existsSync(path.join(testBase, Release.resolvedRemovalName(removalIntent))));
      const replay = Release.finalizeRemoval(testBase);
      assert.strictEqual(replay.releaseSha256, receipt.releaseSha256);
    });
    negative("foreign removal intent cannot authorize finalization",
      "material_shop_worktree_removal_intent_invalid", () => {
        const drift = clone(removalIntent);
        drift.runId = "foreign-run";
        reseal(drift, "intentSha256");
        Release.validateRemovalIntent(drift);
      });
    negative("pre-existing canonical release output blocks worktree deletion",
      "material_shop_worktree_release_output_invalid", () => {
        const occupiedDir = path.join(testBase, "occupied-output");
        fs.mkdirSync(occupiedDir);
        const occupied = path.join(occupiedDir, Release.REMOVAL_OUTPUT_NAME);
        fs.writeFileSync(occupied, "occupied\n", "utf8");
        Release.assertRemovalOutputsAvailable(occupiedDir, occupied);
      });
    test("resolved worktree removal marker is required after finalization", () => {
      const resolved = path.join(testBase, Release.resolvedRemovalName(removalIntent));
      const bytes = fs.readFileSync(resolved);
      fs.unlinkSync(resolved);
      let error = null;
      try { Release.finalizeRemoval(testBase); } catch (failure) { error = failure; }
      finally { fs.writeFileSync(resolved, bytes, { flag: "wx" }); }
      assert(error);
      assert.strictEqual(error.code, "material_shop_worktree_removal_state_invalid");
    });
    test("raw verifier requires exact build receipt argument", () => {
      assert.strictEqual(require("./journey-verifier").verifyRawCandidateJourney.length, 5);
    });
    const builtDiscardRunId = path.basename(discardTestBase);
    const builtDiscardDestination = path.join(owned, Materialize.MATERIALIZED_DIRECTORY,
      builtDiscardRunId, "resources");
    const discardArtifactNames = ["candidate-build.json",
      "materialization-create-resolved-aaaaaaaaaaaaaaaa.json", "preparation.json"];
    discardArtifactNames.forEach((name, index) => fs.writeFileSync(
      path.join(discardTestBase, name), JSON.stringify({ fixture: index + 1 }) + "\n", "utf8"));
    const discardRunArtifacts = discardArtifactNames.slice().sort().map((name) => {
      const file = Evidence.readExactRegularFile(path.join(discardTestBase, name), {
        phase: "self_test", maximumBytes: 1024 * 1024,
      });
      return { name, bytes: file.length, sha256: file.sha256 };
    });
    const priorDiscardOperationHandle = RunOperationLease.acquire({
      runDir: discardTestBase, runId: builtDiscardRunId, mode: "built_only_discard",
      preparationSha256: "1".repeat(64), buildSha256: "5".repeat(64),
    });
    RunOperationLease.release(priorDiscardOperationHandle);
    const builtDiscardOperationHandle = RunOperationLease.acquire({
      runDir: discardTestBase, runId: builtDiscardRunId, mode: "built_only_discard",
      preparationSha256: "1".repeat(64), buildSha256: "5".repeat(64),
    });
    const builtDiscardOperation = {
      lease: clone(builtDiscardOperationHandle.lease),
      leaseArtifact: clone(builtDiscardOperationHandle.artifact),
      preexistingHistory: clone(RunOperationLease.historyMarkers(discardTestBase)),
    };
    reseal(builtDiscardOperation, "operationSha256");
    const builtDiscardContext = {
      preparation: { runId: builtDiscardRunId, runDir: discardTestBase,
        resourcesRoot: builtDiscardDestination, preparationSha256: "1".repeat(64) },
      materialization: { materializationSha256: "2".repeat(64),
        gitWorktree: { head: first.head,
          commonDir: path.join(Common.CANONICAL_ROOT, ".git") } },
      closure: { closureSha256: "3".repeat(64),
        scope: { scopeSha256: "4".repeat(64) } },
      build: { buildSha256: "5".repeat(64),
        candidateRoot: path.join(builtDiscardDestination, "tmp", "runtime-candidates",
          "v2", Build.CANDIDATE_LEAF) },
      probe: { probeSha256: "6".repeat(64),
        gitWorktreeIdentitySha256: "7".repeat(64),
        operation: builtDiscardOperation,
        runArtifacts: { files: discardRunArtifacts,
          filesSha256: Evidence.sha256Text(Evidence.canonicalJson(discardRunArtifacts)) } },
    };
    const builtDiscardIntent = DiscardBuilt.createIntent(builtDiscardContext,
      "2026-08-11T00:00:00.000Z");
    const builtDiscardOperationTerminal = RunOperationLease.release(
      builtDiscardOperationHandle);
    test("built-never-executed discard intent seals exact candidate and worktree", () => {
      assert.strictEqual(DiscardBuilt.validateIntent(builtDiscardIntent), builtDiscardIntent);
      assert.strictEqual(builtDiscardIntent.command, "git worktree remove --force");
      assert.strictEqual(builtDiscardIntent.acknowledgedBuiltNeverExecutedDiscard, true);
      assert.strictEqual(builtDiscardIntent.operation.lease.leaseSha256,
        builtDiscardOperationTerminal.leaseSha256);
      assert.strictEqual(builtDiscardIntent.operation.preexistingHistory.length, 1);
    });
    negative("foreign destination cannot reuse built-only discard intent",
      "material_shop_built_discard_intent_invalid", () => {
        const drift = clone(builtDiscardIntent);
        drift.destination = path.join(owned, Materialize.MATERIALIZED_DIRECTORY,
          builtDiscardRunId + "-foreign", "resources");
        reseal(drift, "intentSha256");
        DiscardBuilt.validateIntent(drift);
      });
    negative("built-only discard CLI requires explicit destructive acknowledgement",
      "material_shop_built_discard_arguments_invalid", () => {
        DiscardBuilt.parseArgs(["--discard-built-never-executed", "--preparation",
          path.join(testBase, "preparation.json"), "--build",
          path.join(testBase, "candidate-build.json")]);
      });
    fs.writeFileSync(path.join(discardTestBase, DiscardBuilt.INTENT_NAME),
      JSON.stringify(builtDiscardIntent, null, 2) + "\n", { encoding: "utf8", flag: "wx" });
    negative("active built-only discard intent blocks live execution re-entry",
      "material_shop_run_blocked_by_built_discard", () => {
        DiscardBuilt.assertLiveExecutionAvailable(discardTestBase);
      });
    negative("built-only finalizer rejects sealed run artifact byte drift",
      "material_shop_built_discard_artifact_drift", () => {
        const target = path.join(discardTestBase, discardArtifactNames[0]);
        const original = fs.readFileSync(target);
        fs.appendFileSync(target, "drift");
        try { DiscardBuilt.finalize(discardTestBase); }
        finally { fs.writeFileSync(target, original); }
      });
    negative("built-only finalizer rejects foreign raw artifacts after removal",
      "material_shop_built_discard_live_side_effect", () => {
        const foreign = path.join(discardTestBase, "raw-candidate-journey.json");
        fs.writeFileSync(foreign, "{}\n", "utf8");
        try { DiscardBuilt.finalize(discardTestBase); }
        finally { fs.unlinkSync(foreign); }
      });
    negative("built-only finalizer rejects live-execution operation history",
      "material_shop_built_discard_candidate_may_have_executed", () => {
        const liveLease = clone(builtDiscardIntent.operation.lease);
        liveLease.createdAt = new Date(Date.parse(liveLease.createdAt) + 1000).toISOString();
        liveLease.mode = "live_execution";
        liveLease.ownerNonceSha256 = "d".repeat(64);
        reseal(liveLease, "leaseSha256");
        const marker = path.join(discardTestBase,
          RunOperationLease.terminalName(liveLease));
        fs.writeFileSync(marker, JSON.stringify(liveLease, null, 2) + "\n", "utf8");
        try { DiscardBuilt.finalize(discardTestBase); }
        finally { fs.unlinkSync(marker); }
      });
    negative("built-only finalizer rejects dynamically appended discard history",
      "material_shop_built_discard_operation_drift", () => {
        const extraLease = clone(builtDiscardIntent.operation.lease);
        extraLease.createdAt = new Date(Date.parse(extraLease.createdAt) + 2000).toISOString();
        extraLease.ownerNonceSha256 = "e".repeat(64);
        reseal(extraLease, "leaseSha256");
        const marker = path.join(discardTestBase,
          RunOperationLease.terminalName(extraLease));
        fs.writeFileSync(marker, JSON.stringify(extraLease, null, 2) + "\n", "utf8");
        try { DiscardBuilt.finalize(discardTestBase); }
        finally { fs.unlinkSync(marker); }
      });
    negative("built-only marker cannot finalize from a sibling run directory",
      "material_shop_built_discard_state_invalid", () => {
        const siblingMarker = path.join(testBase, DiscardBuilt.INTENT_NAME);
        fs.writeFileSync(siblingMarker, JSON.stringify(builtDiscardIntent) + "\n", "utf8");
        try { DiscardBuilt.loadState(testBase); }
        finally { fs.unlinkSync(siblingMarker); }
      });
    test("post-remove built-only finalizer is durable and idempotent", () => {
      const firstReceipt = DiscardBuilt.finalize(discardTestBase);
      const replay = DiscardBuilt.finalize(discardTestBase);
      assert.strictEqual(replay.receiptSha256, firstReceipt.receiptSha256);
      assert.strictEqual(firstReceipt.candidateExecuted, false);
      assert.strictEqual(firstReceipt.rawEvidenceCreated, false);
      assert(fs.existsSync(path.join(discardTestBase,
        DiscardBuilt.resolvedName(builtDiscardIntent))));
    });
    test("built-only discard source revalidates twice and never prunes or recursively deletes", () => {
      const source = fs.readFileSync(path.join(__dirname, "discard-built-run.js"), "utf8");
      const liveSource = fs.readFileSync(path.join(__dirname, "run-live-journey.js"), "utf8");
      const firstLoad = source.indexOf("const context = loadContext");
      const intentWrite = source.indexOf("Materialize.writeJsonAtomicNew", firstLoad);
      const secondLoad = source.indexOf("const fresh = loadContext", intentWrite);
      const remove = source.indexOf("runGitRemove(fresh.preparation.resourcesRoot)", secondLoad);
      assert(firstLoad >= 0 && intentWrite > firstLoad && secondLoad > intentWrite
        && remove > secondLoad);
      const livePreFence = liveSource.indexOf("DiscardBuilt.assertLiveExecutionAvailable");
      const liveAcquire = liveSource.indexOf("RunOperationLease.acquire");
      const livePostFence = liveSource.indexOf("DiscardBuilt.assertLiveExecutionAvailable",
        liveAcquire);
      const cancelBeforeExecution = liveSource.indexOf(
        "RunOperationLease.cancelBeforeExecution(operationHandle)", livePostFence);
      const executionStart = liveSource.indexOf(
        "RunOperationLease.markExecutionStarted(operationHandle)", cancelBeforeExecution);
      const liveOwned = liveSource.indexOf(
        "executeOwned(args, preparation, operationHandle, preflightApplicability)",
        executionStart);
      assert(livePreFence >= 0 && liveAcquire > livePreFence
        && livePostFence > liveAcquire && cancelBeforeExecution > livePostFence
        && executionStart > cancelBeforeExecution && liveOwned > executionStart);
      assert(source.includes('"worktree", "remove", "--force", destination'));
      assert(!source.includes('"worktree", "prune"'));
      assert(!source.includes("fs.rmSync"));
    });
    test("seed-audit pre-candidate cleanup resume harness is production-closed", () => {
      const script = path.join(__dirname, "test-discard-seed-audit-failed-run.js");
      const result = childProcess.spawnSync(process.execPath, [script], {
        cwd: Common.CANONICAL_ROOT, encoding: "utf8", windowsHide: true,
        maxBuffer: 16 * 1024 * 1024,
      });
      assert.strictEqual(result.status, 0, String(result.stderr || result.stdout || ""));
      const lines = String(result.stdout || "").trim().split(/\r?\n/);
      const receipt = JSON.parse(lines[lines.length - 1]);
      assert.deepStrictEqual({ ok: receipt.ok, passed: receipt.passed,
        total: receipt.total, actualCleanupExecuted: receipt.actualCleanupExecuted },
      { ok: true, passed: 27, total: 27, actualCleanupExecuted: false });
    });
    test("pre-control failure cleanup discard resume harness is production-closed", () => {
      const script = path.join(__dirname, "test-discard-pre-control-failed-run.js");
      const result = childProcess.spawnSync(process.execPath, [script], {
        cwd: Common.CANONICAL_ROOT, encoding: "utf8", windowsHide: true,
        maxBuffer: 16 * 1024 * 1024,
      });
      assert.strictEqual(result.status, 0, String(result.stderr || result.stdout || ""));
      const lines = String(result.stdout || "").trim().split(/\r?\n/);
      const receipt = JSON.parse(lines[lines.length - 1]);
      assert.deepStrictEqual({ ok: receipt.ok, passed: receipt.passed,
        total: receipt.total,
        fixtureWorktreeRemovalExecuted: receipt.fixtureWorktreeRemovalExecuted,
        productionRunCleanupExecuted: receipt.productionRunCleanupExecuted },
      { ok: true, passed: 22, total: 22,
        fixtureWorktreeRemovalExecuted: true,
        productionRunCleanupExecuted: false });
    });

    process.stdout.write(JSON.stringify({ ok: true, status: "OFFLINE_VERIFIED",
      passed, total, applicabilitySha256: applicability.applicabilitySha256,
      closureSha256: first.closureSha256, fileCount: first.scope.fileCount,
      candidateBuilt: false, realGuiExecuted: false, e2eVerified: false,
      deployment: "NOT_DEPLOYED" }) + "\n");
  } finally {
    safeCleanup(testBase);
    safeCleanup(discardTestBase);
    safeCleanup(operationCancelBase);
    safeCleanup(producerLeaseBase);
    safeCleanup(producerReuseBase);
    safeCleanup(preControlBase);
  }
}

try { main(); }
catch (error) {
  process.stderr.write((error && error.stack || String(error)) + "\n");
  process.exitCode = 1;
}
