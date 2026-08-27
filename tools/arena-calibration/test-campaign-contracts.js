#!/usr/bin/env node
"use strict";

const assert = require("assert");
const {
  normalizeManifest,
  normalizeResultRow,
  sha256OfValue,
} = require("./lib/arena-calibration-core");
const {
  adjudicateControllerProposal,
} = require("./lib/campaign-contracts");
const {
  EMBEDDED_SCHEMA_IDS,
  assertSchemaInstance,
  loadSchemaRegistry,
  validateSchemaInstance,
} = require("./lib/schema-registry");

const NOW = "2026-08-27T08:00:00.000Z";
const HASH = (char) => `sha256:${char.repeat(64)}`;
const ACTION_NAMES = [
  "schedule_shard", "append_samples", "create_side_swap", "create_bridge", "prune_sampling",
  "quarantine_candidate", "enqueue_pve_packet", "complete_candidate", "pause_campaign", "abstain",
  "request_method_change", "propose_recommendation_bundle", "request_formal_apply",
];

function budget(maxRuns, maxFrames, maxWallClockMinutes, maxHumanMinutes) {
  return { maxRuns, maxFrames, maxWallClockMinutes, maxHumanMinutes };
}

function preconditions(snapshotHash, requiresIdleGrant) {
  return { campaignStates: ["RUNNING"], requiresIdleGrant, snapshotHash };
}

function actionBase(actionId, action, riskLevel, actionBudget, snapshotHash, requiresIdleGrant) {
  return {
    actionId,
    action,
    riskLevel,
    budget: actionBudget,
    expectedInformationGain: 0.5,
    evidenceRefs: [HASH("e")],
    confidence: 0.8,
    preconditions: preconditions(snapshotHash, requiresIdleGrant),
  };
}

function caseTemplate(caseId, blueType, redType, parameters) {
  const blue = { type: blueType, level: 30 };
  if (parameters) blue.parameters = parameters;
  return {
    caseId,
    blueRoster: [blue],
    redRoster: [{ type: redType, level: 30 }],
    repeat: 1,
    timeoutFrames: 1800,
    spawnDistance: 650,
    blueFormation: "line",
    redFormation: "line",
    formationSpacing: 54,
    tags: ["fixture"],
    plannerReason: "Gate A fixture",
  };
}

function createSnapshot() {
  return {
    schema: "arena-calibration.decision-snapshot.v1",
    decisionSnapshotId: "snapshot-gate-a",
    snapshotHash: HASH("a"),
    campaignId: "campaign-gate-a",
    epochId: "epoch-1",
    createdAt: NOW,
    runtimeCohort: {
      executionArtifactIdentity: HASH("f"),
      battleSemanticsCohortId: "cohort-fixture",
    },
    caseCatalog: [
      {
        candidateId: "candidate-a",
        caseHash: HASH("b"),
        caseTemplate: caseTemplate("case-a", "兵种44", "兵种11", { 手枪: "P90战术版" }),
      },
      {
        candidateId: "candidate-b",
        caseHash: HASH("c"),
        caseTemplate: caseTemplate("case-b", "兵种59", "兵种50", null),
      },
      {
        candidateId: "candidate-bridge",
        caseHash: HASH("d"),
        caseTemplate: caseTemplate("case-bridge", "兵种44", "兵种50", null),
      },
    ],
    candidateEvidence: [{
      candidateId: "candidate-a",
      caseHash: HASH("b"),
      original: { samples: 15, timeouts: 0, timeoutRate: 0, errorCount: 0 },
      swapped: { samples: 15, timeouts: 0, timeoutRate: 0, errorCount: 0 },
      sideSwapReviewed: true,
      timeoutDisposition: "low_rate",
      timeoutExplanationRef: null,
      completionGateRef: HASH("9"),
    }],
    committedResultRefs: [],
    excludedResultRefs: [],
    posteriorSummary: {},
    remainingBudget: budget(100, 900000, 240, 15),
    allowedActions: ACTION_NAMES,
    stopConditions: { maxTimeoutRate: 0.05 },
    versions: {
      codeCommit: "fixture",
      schemaVersion: "gate-a-v1",
      statisticsVersion: "v1",
      policyVersion: "gate-a-v1",
    },
  };
}

function createScheduleProposal(snapshot) {
  const shardBudget = budget(2, 18000, 10, 0);
  return {
    schema: "arena-calibration.controller-proposal.v1",
    proposalId: "proposal-schedule",
    decisionSnapshotId: snapshot.decisionSnapshotId,
    modelProfile: "rule-fixture",
    role: "rule_fallback",
    generatedAt: NOW,
    actions: [{
      ...actionBase("action-schedule", "schedule_shard", "auto_execute", shardBudget, snapshot.snapshotHash, true),
      shardId: "shard-fixture",
      shardKind: "unattended",
      caseRefs: [
        { candidateId: "candidate-a", caseHash: HASH("b"), sideAssignment: "original" },
        { candidateId: "candidate-a", caseHash: HASH("b"), sideAssignment: "swapped" },
      ],
    }],
    totalBudget: shardBudget,
    evidenceRefs: [HASH("e")],
    risks: ["fixture"],
    counterexamples: ["none"],
    confidence: 0.8,
    abstain: false,
    requiresHuman: false,
  };
}

function createAllActionProposal(snapshot) {
  const run = budget(2, 18000, 10, 0);
  const noRun = budget(0, 0, 0, 0);
  const base = (id, action, risk, b, idle) => actionBase(id, action, risk, b, snapshot.snapshotHash, idle);
  const actions = [
    { ...base("a1", "schedule_shard", "auto_execute", run, true), shardId: "s1", shardKind: "unattended", caseRefs: [{ candidateId: "candidate-a", caseHash: HASH("b"), sideAssignment: "original" }] },
    { ...base("a2", "append_samples", "auto_execute", run, true), candidateId: "candidate-a", caseHash: HASH("b"), sideAssignment: "original", additionalRuns: 2 },
    { ...base("a3", "create_side_swap", "auto_execute", run, true), candidateId: "candidate-a", caseHash: HASH("b") },
    { ...base("a4", "create_bridge", "auto_execute", run, true), leftCandidateId: "candidate-a", rightCandidateId: "candidate-b", bridgeCaseHash: HASH("d") },
    { ...base("a5", "prune_sampling", "auto_execute", noRun, false), candidateId: "candidate-a", caseHash: HASH("b"), reasonCode: "enough-samples" },
    { ...base("a6", "quarantine_candidate", "defer_and_continue", noRun, false), candidateId: "candidate-a", caseHash: HASH("b"), reasonCode: "contamination" },
    { ...base("a7", "enqueue_pve_packet", "auto_execute", budget(2, 0, 10, 10), false), packetId: "packet-1", candidateIds: ["candidate-a", "candidate-b"] },
    { ...base("a8", "complete_candidate", "auto_execute", noRun, false), candidateId: "candidate-a", caseHash: HASH("b"), completionGateRef: HASH("9"), finalState: "provisional" },
    { ...base("a9", "pause_campaign", "auto_execute", noRun, false), scope: "campaign", reasonCode: "development-preempt" },
    { ...base("a10", "abstain", "defer_and_continue", noRun, false), scope: "candidate-a", reasonCode: "insufficient-evidence" },
    { ...base("a11", "request_method_change", "human_approval_required", noRun, false), changeId: "method-1", summary: "fixture method change" },
    { ...base("a12", "propose_recommendation_bundle", "auto_execute", noRun, false), candidateId: "candidate-a", bundleId: "bundle-1", targetRefs: ["data/fixture.xml"] },
    { ...base("a13", "request_formal_apply", "human_approval_required", noRun, false), bundleId: "bundle-1", bundleHash: HASH("8") },
  ];
  return {
    schema: "arena-calibration.controller-proposal.v1",
    proposalId: "proposal-all-actions",
    decisionSnapshotId: snapshot.decisionSnapshotId,
    modelProfile: "rule-fixture",
    role: "rule_fallback",
    generatedAt: NOW,
    actions,
    totalBudget: budget(100, 900000, 240, 15),
    evidenceRefs: [HASH("e")],
    risks: [],
    counterexamples: [],
    confidence: 0.8,
    abstain: false,
    requiresHuman: true,
  };
}

function validateArtifactFixtures(snapshot, proposal, accepted) {
  const source = {
    kind: "xlsx_cell",
    workbookSha256: HASH("1"),
    workbookName: "fixture.xlsx",
    sheetName: "斗兽标定组合",
    cell: "B2",
    cellValueSha256: HASH("2"),
  };
  const raw = {
    schema: "arena-calibration.raw-submission.v1",
    submissionId: "submission-fixture",
    ingestedAt: NOW,
    provider: "test-group",
    source,
    rawValue: "fixture",
    rawSubmissionHash: HASH("3"),
    extractedMatchCode: "CF7ARENA:v1;mode=mvm;seed=1;blue=u44@30x1;red=u11@30x1",
    subjectiveTier: "1-5级",
    note: null,
  };
  const candidate = {
    schema: "arena-calibration.normalized-candidate.v1",
    candidateId: "candidate-a",
    candidateHash: HASH("4"),
    rawSubmissionId: raw.submissionId,
    rawSubmissionHash: raw.rawSubmissionHash,
    source,
    dataQuality: "complete",
    mode: "mvm",
    seed: 1,
    sourceMatchCode: raw.extractedMatchCode,
    canonicalMatchCode: `${raw.extractedMatchCode};timeout=1800`,
    timeout: { frames: 1800, source: "phase_default", policy: "exploration_1800" },
    caseTemplate: snapshot.caseCatalog[0].caseTemplate,
    riskTags: ["unit_payload"],
    correctionReceipts: [],
    weakPrior: "1-5级",
    initialSampleBudget: { pilotRuns: 2, explorationRuns: 30, confirmatoryMinPerSide: 30 },
    completionReceipt: { defaultsApplied: ["timeoutFrames=1800"], sourceBound: true, parametersPreserved: true, sideSwapPlanned: true },
  };
  const campaign = {
    schema: "arena-calibration.campaign.v1",
    campaignId: "campaign-gate-a",
    createdAt: NOW,
    state: "READY",
    candidateRegistryHash: HASH("5"),
    decisionPolicyId: "gate-a-v1",
    battleSemanticsCohortId: "cohort-fixture",
    budget: budget(100, 900000, 240, 15),
    journalPolicy: {
      rootTemplate: "logs/arena-calibration/campaigns/<campaignId>/",
      retentionDays: 90,
      retainWhileReferenced: true,
      oneWriter: true,
      writerLeaseFields: ["campaignId", "writerProcessIdentity", "writerEpoch", "expiresAt"],
      durableCommit: "event_flush_then_durable_commit_flush",
      closedSegmentsReopen: false,
      recoveryOrder: ["acquire_writer", "validate_closed_segments", "scan_open_segment", "accept_matching_durable_commits", "record_truncated_tail_in_new_segment", "rebuild_checkpoint", "reconcile_run_keys"],
    },
  };
  const adjudication = {
    schema: "arena-calibration.adjudication.v1",
    adjudicationId: "adjudication-1",
    decisionSnapshotId: snapshot.decisionSnapshotId,
    proposalIds: [proposal.proposalId],
    mechanicalScores: { schemaValid: true },
    blindHumanScores: null,
    disagreements: [],
    selectedProposalId: proposal.proposalId,
    finalReason: "fixture",
    createdAt: NOW,
  };
  const attention = {
    schema: "arena-calibration.attention-event.v1",
    eventId: "attention-1",
    campaignId: campaign.campaignId,
    shardId: "shard-1",
    shardKind: "unattended",
    shardKindDeclaredAt: NOW,
    shardStartedAt: NOW,
    shardHumanActionCount: 0,
    opsActiveMinutes: 0,
    humanBlockedMinutes: 0,
    interruptCount: 0,
    proposalWindow: { windowKind: "rolling_20", minimumDenominator: 20, eligibleEpochs: 0, humanTouches: 0, manualEdits: 0, touchRate: null, manualEditRate: null, status: "insufficient_data" },
    exceptionCounts: { items: 0, occurrences: 0, affectedScopes: 0 },
    createdAt: NOW,
  };
  const intake = {
    schema: "arena-calibration.workbook-intake.v1",
    generatedAt: NOW,
    workbookSha256: source.workbookSha256,
    workbookName: source.workbookName,
    sheetName: source.sheetName,
    timeoutPolicy: "exploration_1800",
    counts: { populatedCells: 1, rawSubmissions: 1, normalizedCandidates: 1, corrected: 0, quarantined: 0, selectedCases: 1, plannedRuns: 1 },
    corrections: [],
    quarantines: [],
    rawSubmissionIds: [raw.submissionId],
    candidateIds: [candidate.candidateId],
    exceptionIds: [],
    selectedCells: ["B2"],
    manifestHash: accepted.l0.manifest.manifestHash,
  };
  [raw, candidate, campaign, snapshot, proposal, accepted.receipt, adjudication, attention, intake].forEach((fixture) => {
    assertSchemaInstance(fixture.schema, fixture, `${fixture.schema} fixture`);
  });
}

function checkParametersClosure() {
  const build = (weapon) => normalizeManifest({
    schema: "arena-calibration.case-manifest.v1",
    batchId: `parameters-${weapon.toLowerCase()}`,
    createdAt: NOW,
    buildCommit: "fixture",
    planner: { name: "fixture", version: 1 },
    arenaMode: "calibration",
    repeat: 1,
    timeoutFrames: 1800,
    blueBench: null,
    cases: [{ ...caseTemplate("parameters-case", "兵种44", "兵种11", { 手枪: weapon }) }],
  });
  const p90 = build("P90");
  const m9 = build("M9");
  assert.strictEqual(p90.cases[0].blueRoster[0].parameters.手枪, "P90");
  assert.notStrictEqual(p90.cases[0].caseHash, m9.cases[0].caseHash);
  assert.notStrictEqual(p90.manifestHash, m9.manifestHash);
}

function checkContamination() {
  const row = normalizeResultRow({
    schema: "arena-calibration.result.v1",
    batchId: "contamination-fixture",
    manifestHash: HASH("6"),
    caseId: "case-contamination",
    caseHash: HASH("7"),
    runId: "run-contamination",
    repeatIndex: 1,
    status: "contamination",
    winner: "none",
    errors: [{ code: "player_present", message: "fixture" }],
  });
  assert.strictEqual(row.status, "contamination");
  assertSchemaInstance(row.schema, row, "contamination fixture");
}

function main() {
  const registry = loadSchemaRegistry();
  assertSchemaInstance("arena-calibration.campaign-contracts.v1", { schema: "arena-calibration.campaign-contracts.v1" });
  Object.keys(EMBEDDED_SCHEMA_IDS).forEach((id) => assert.ok(registry.ajv.getSchema(EMBEDDED_SCHEMA_IDS[id]), id));
  const snapshot = createSnapshot();
  const scheduleProposal = createScheduleProposal(snapshot);
  const allActions = createAllActionProposal(snapshot);
  assertSchemaInstance(snapshot.schema, snapshot, "snapshot fixture");
  assertSchemaInstance(allActions.schema, allActions, "closed action enum fixture");

  const accepted = adjudicateControllerProposal(scheduleProposal, snapshot, {
    campaignState: "RUNNING",
    batchId: "gate-a-adapter-fixture",
    buildCommit: "fixture",
    now: NOW,
  });
  assert.strictEqual(accepted.outcome, "accepted");
  assert.ok(accepted.l0.manifest);
  assert.strictEqual(accepted.l0.manifest.cases.length, 2);
  assert.strictEqual(accepted.l0.manifest.cases[0].blueRoster[0].parameters.手枪, "P90战术版");

  const unknown = JSON.parse(JSON.stringify(scheduleProposal));
  unknown.proposalId = "proposal-unknown-action";
  unknown.actions[0].action = "invent_magic";
  assert.strictEqual(validateSchemaInstance(unknown.schema, unknown).ok, false);
  const rejectedUnknown = adjudicateControllerProposal(unknown, snapshot, { campaignState: "RUNNING", now: NOW });
  assert.strictEqual(rejectedUnknown.outcome, "rejected");
  assert.strictEqual(rejectedUnknown.campaignState, "EXCEPTIONS_PENDING");
  assert.strictEqual(rejectedUnknown.fallback, "rule_fallback");

  const overBudget = JSON.parse(JSON.stringify(scheduleProposal));
  overBudget.proposalId = "proposal-over-budget";
  overBudget.totalBudget.maxRuns = 1;
  const rejectedBudget = adjudicateControllerProposal(overBudget, snapshot, { campaignState: "RUNNING", now: NOW });
  assert.strictEqual(rejectedBudget.outcome, "rejected");
  assert.strictEqual(rejectedBudget.campaignState, "EXCEPTIONS_PENDING");

  const completionProposal = JSON.parse(JSON.stringify(scheduleProposal));
  completionProposal.proposalId = "proposal-complete-candidate";
  completionProposal.actions = [JSON.parse(JSON.stringify(
    allActions.actions.find((action) => action.action === "complete_candidate")
  ))];
  completionProposal.totalBudget = budget(0, 0, 0, 0);
  const acceptedCompletion = adjudicateControllerProposal(completionProposal, snapshot, {
    campaignState: "RUNNING",
    now: NOW,
  });
  assert.strictEqual(acceptedCompletion.outcome, "accepted");
  const undersampledSnapshot = JSON.parse(JSON.stringify(snapshot));
  undersampledSnapshot.candidateEvidence[0].original.samples = 14;
  const rejectedCompletion = adjudicateControllerProposal(completionProposal, undersampledSnapshot, {
    campaignState: "RUNNING",
    now: NOW,
  });
  assert.strictEqual(rejectedCompletion.outcome, "rejected");

  const highTimeoutSnapshot = JSON.parse(JSON.stringify(snapshot));
  highTimeoutSnapshot.candidateEvidence[0].original.timeouts = 2;
  highTimeoutSnapshot.candidateEvidence[0].original.timeoutRate = 2 / 15;
  highTimeoutSnapshot.candidateEvidence[0].timeoutDisposition = "explained_long_timeout";
  highTimeoutSnapshot.candidateEvidence[0].timeoutExplanationRef = HASH("7");
  const rejectedHighTimeout = adjudicateControllerProposal(completionProposal, highTimeoutSnapshot, {
    campaignState: "RUNNING",
    now: NOW,
  });
  assert.strictEqual(rejectedHighTimeout.outcome, "rejected");

  const inconsistentTimeoutSnapshot = JSON.parse(JSON.stringify(snapshot));
  inconsistentTimeoutSnapshot.candidateEvidence[0].original.timeoutRate = 0.01;
  const rejectedInconsistentTimeout = adjudicateControllerProposal(
    completionProposal,
    inconsistentTimeoutSnapshot,
    { campaignState: "RUNNING", now: NOW }
  );
  assert.strictEqual(rejectedInconsistentTimeout.outcome, "rejected");

  const failedClosed = adjudicateControllerProposal(scheduleProposal, snapshot, {
    campaignState: "RUNNING",
    batchId: "gate-a-invalid-l0",
    buildCommit: "fixture",
    now: NOW,
    faultInjection: {
      kind: "trusted_l0_mutation",
      testOnly: true,
      transform(manifest) {
        manifest.cases = [];
        return manifest;
      },
    },
  });
  assert.strictEqual(failedClosed.outcome, "failed_closed");
  assert.strictEqual(failedClosed.campaignState, "FAILED_CLOSED");

  validateArtifactFixtures(snapshot, scheduleProposal, accepted);
  checkParametersClosure();
  checkContamination();
  console.log(JSON.stringify({
    ok: true,
    compiledSchemas: registry.schemas.length + Object.keys(EMBEDDED_SCHEMA_IDS).length,
    closedActions: ACTION_NAMES.length,
    proposalInvalidContinues: true,
    trustedL0InvalidFailedClosed: true,
    parametersHashClosed: true,
    contaminationSchemaValid: true,
    finalCandidateGateEnforced: true,
    lowTimeoutGateEnforced: true,
  }, null, 2));
}

main();
