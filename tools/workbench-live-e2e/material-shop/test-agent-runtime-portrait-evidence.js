#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const Protocol = require("./protocol");

let passed = 0;
function test(name, callback) {
  callback();
  passed += 1;
  process.stdout.write("ok - " + name + "\n");
}

function currentPlan() {
  return { runId: "a5-0813-1904", planSha256: "a".repeat(64),
    schema: Protocol.AGENT_RUNTIME_PLAN_SCHEMA,
    recipeJump: JSON.parse(JSON.stringify(Protocol.AGENT_RUNTIME_RECIPE_JUMP)),
    applicability: {
      applicabilitySha256: "b".repeat(64),
      locked: { status: "not_applicable_current_data", qualifyingOccurrenceCount: 0 },
      max: { status: "not_applicable_current_data", qualifyingOccurrenceCount: 0 },
    } };
}

function currentJourney(plan) {
  const target = { shopId: "厨师", catalogIndex: 24, itemName: "食用油" };
  const na = { status: "not_applicable_current_data",
    applicabilitySha256: plan.applicability.applicabilitySha256,
    qualifyingOccurrenceCount: 0 };
  const closeOutcome = (closeStepId, closeRole, closeMethod, successorStepId,
    closeDigit, openDigit, captureDigit) => ({
    closeStepId, closeRole, closeMethod, closeActionReceiptSha256: closeDigit.repeat(64),
    successorStepId, successorMethod: "panel.open",
    successorActionReceiptSha256: openDigit.repeat(64),
    successorCaptureSha256: captureDigit.repeat(64), successorSessionLabel: "first",
    successorObservationId: "observation-1", successorFrameId: "frame-1",
    successorFrameContentHash: "7".repeat(64),
    admissionFence: "prior_tracked_visual_idle_required", successorPanel: "materials",
  });
  return {
    operationLease: { leaseSha256: "c".repeat(64), mode: "live_execution",
      activeAtCapture: true },
    agentRuntime: { provider: Protocol.AGENT_RUNTIME_PROVIDER,
      transport: Protocol.AGENT_RUNTIME_TRANSPORT,
      trustedRunnerSlot: Protocol.AGENT_RUNTIME_SLOT,
      candidateLeaf: Protocol.AGENT_RUNTIME_CANDIDATE_LEAF, sessionCount: 2,
      firstCompletionSha256: "d".repeat(64), restartCompletionSha256: "e".repeat(64) },
    materials: { archiveOrder: "authored_xml", visualVerified: true,
      keyboardJourneyVerified: true, candidateViewport: "current_window",
      responsiveThreeViewportGateBound: true,
      multiVariant: { enemyType: "fixture-enemy", occurrenceIndices: [0, 1],
        allVisible: true },
      portraits: Protocol.createAgentRuntimePortraitEvidence(plan, true),
      recipeJump: { materialName: Protocol.AGENT_RUNTIME_RECIPE_JUMP.materialName,
        category: Protocol.AGENT_RUNTIME_RECIPE_JUMP.category,
        recipeIndex: Protocol.AGENT_RUNTIME_RECIPE_JUMP.recipeIndex,
        productName: Protocol.AGENT_RUNTIME_RECIPE_JUMP.productName,
        keyboardSequenceSha256: "8".repeat(64),
        visibleCaptureSha256: "9".repeat(64), keySequenceVerified: true,
        escapeCloseOutcome: closeOutcome("recipe_escape_close",
          "recipe_close_with_escape", "input.press_key", "recipe_reopen_materials",
          "2", "3", "4") } },
    routes: { locked: Object.assign({}, na),
      ordinaryClose: { target, forwardCommitted: true, ordinaryCloseCommitted: true,
        closeOutcome: closeOutcome("ordinary_close", "npcshop_close", "input.click",
          "reopen_materials", "5", "6", "7") },
      unlocked: { target, forwardCommitted: true, locatedExact: true,
        navigationFocus: "data-navigation-focus", quantity: 1, saleCount: 0,
        settlementProjectionCount: 1, commitDispatchCount: 1, settled: true,
        returnCommitted: true,
        settlement: { baselineBalance: 1000, unitPrice: 300, buyTotal: 300,
          projectedBalance: 700, beforeOwned: 0, afterOwned: 1 } },
      max: Object.assign({}, na) },
    persistence: { trustedPersistenceShutdown: true, trustedFinalShutdown: true,
      seedReadOnly: true, targetIsolated: true, recoveryAvailable: true,
      restartFreshProcess: true, restartReadbackEqual: true,
      baselineMoney: 1000, settledMoney: 700, beforeOwned: 0,
      archiveOwned: 1, restartOwned: 1, archiveSha256: "f".repeat(64),
      restartSha256: "0".repeat(64), archiveSemanticSha256: "1".repeat(64),
      restartSemanticSha256: "1".repeat(64) },
    authorityCounts: { settlementProjection: 1, commitDispatch: 1, sale: 0 },
  };
}

test("current Agent evidence v9 records only capture presence and pending review", () => {
  const plan = currentPlan();
  assert.strictEqual(Protocol.agentRuntimeEvidenceSchemaForPlan(plan),
    Protocol.AGENT_RUNTIME_EVIDENCE_SCHEMA);
  assert.deepStrictEqual(Protocol.createAgentRuntimePortraitEvidence(plan, true), {
    capturePresent: true,
    resolutionStatus: Protocol.PORTRAIT_REVIEW_PENDING,
    independentReviewRequired: true,
  });
  assert.deepStrictEqual(Protocol.agentRuntimePortraitReviewBoundary(plan, true), {
    status: Protocol.PORTRAIT_REVIEW_PENDING,
    capturePresent: true,
    independentVisiblePngReviewRequired: true,
    portraitResolutionVerified: false,
  });
  Protocol.validateAgentRuntimeJourney(currentJourney(plan), plan,
    Protocol.AGENT_RUNTIME_EVIDENCE_SCHEMA);
});

test("current v9 rejects legacy resolved field names and a forged passed status", () => {
  const plan = currentPlan();
  const legacyShape = currentJourney(plan);
  legacyShape.materials.portraits = { enemyResolved: true, shopResolved: true,
    fallbackHarnessBound: true, identityLeak: false };
  assert.throws(() => Protocol.validateAgentRuntimeJourney(legacyShape, plan,
    Protocol.AGENT_RUNTIME_EVIDENCE_SCHEMA), {
    code: "material_shop_portrait_evidence_invalid",
  });
  const forged = currentJourney(plan);
  forged.materials.portraits.resolutionStatus = "passed";
  assert.throws(() => Protocol.validateAgentRuntimeJourney(forged, plan,
    Protocol.AGENT_RUNTIME_EVIDENCE_SCHEMA), {
    code: "material_shop_materials_evidence_invalid",
  });
});

test("legacy v6 creator identity is exact-plan-only and remains pending for review", () => {
  const plan = { runId: Protocol.LEGACY_AGENT_RUNTIME_V6_RUN_ID,
    planSha256: Protocol.LEGACY_AGENT_RUNTIME_V6_PLAN_SHA256 };
  assert.strictEqual(Protocol.agentRuntimeEvidenceSchemaForPlan(plan),
    Protocol.LEGACY_AGENT_RUNTIME_EVIDENCE_SCHEMA);
  assert.deepStrictEqual(Protocol.createAgentRuntimePortraitEvidence(plan, true), {
    enemyResolved: true, shopResolved: true, fallbackHarnessBound: true,
    identityLeak: false,
  });
  assert.strictEqual(Protocol.agentRuntimePortraitReviewBoundary(plan, true)
    .portraitResolutionVerified, false);
  assert.throws(() => Protocol.agentRuntimeEvidenceSchemaForPlan({
    runId: Protocol.LEGACY_AGENT_RUNTIME_V6_RUN_ID, planSha256: "9".repeat(64),
  }), { code: "material_shop_legacy_agent_evidence_identity_invalid" });
});

test("a foreign plan cannot select the legacy v6 journey validator", () => {
  const plan = currentPlan();
  const journey = currentJourney(plan);
  journey.materials.portraits = { enemyResolved: true, shopResolved: true,
    fallbackHarnessBound: true, identityLeak: false };
  assert.throws(() => Protocol.validateAgentRuntimeJourney(journey, plan,
    Protocol.LEGACY_AGENT_RUNTIME_EVIDENCE_SCHEMA), {
    code: "material_shop_legacy_agent_evidence_identity_invalid",
  });
});

test("capture absence cannot be projected as portrait evidence", () => {
  assert.throws(() => Protocol.createAgentRuntimePortraitEvidence(currentPlan(), false), {
    code: "material_shop_portrait_evidence_invalid",
  });
});

function historicalRunDir(argv) {
  const index = argv.indexOf("--historical-run-dir");
  if (index < 0) return null;
  if (!argv[index + 1]) throw new Error("--historical-run-dir requires a value");
  return path.resolve(argv[index + 1]);
}

const historical = historicalRunDir(process.argv.slice(2));
if (historical) {
  test("frozen t1903 v6 validates and recreates byte-for-byte without becoming accepted", () => {
    const plan = JSON.parse(fs.readFileSync(path.join(historical, "control-plan.json"), "utf8"));
    const stored = JSON.parse(fs.readFileSync(
      path.join(historical, "journey-evidence.json"), "utf8"));
    const validated = Protocol.validateAgentRuntimeJourneyEvidence(stored, plan);
    const recreated = Protocol.createAgentRuntimeJourneyEvidence({ plan,
      controls: stored.controls, journey: stored.journey, boundaries: stored.boundaries });
    assert.strictEqual(Evidence.canonicalJson(validated), Evidence.canonicalJson(stored));
    assert.strictEqual(Evidence.canonicalJson(recreated), Evidence.canonicalJson(stored));
    assert.strictEqual(stored.evidenceSha256,
      Protocol.LEGACY_AGENT_RUNTIME_V6_EVIDENCE_SHA256);
    assert.strictEqual(Protocol.agentRuntimePortraitReviewBoundary(plan, true)
      .portraitResolutionVerified, false);

    const foreignLegacyPlan = JSON.parse(JSON.stringify(plan));
    foreignLegacyPlan.runId = "a5-0813-1904";
    foreignLegacyPlan.planSha256 = Evidence.sha256Text(Evidence.canonicalJson(
      Protocol.stablePlan(foreignLegacyPlan)));
    assert.throws(() => Protocol.validateAgentRuntimeControlPlan(foreignLegacyPlan), {
      code: "material_shop_legacy_agent_plan_identity_invalid",
    });
  });
}

process.stdout.write(passed + "/" + passed
  + " Agent Runtime portrait-evidence tests passed\n");
