#!/usr/bin/env node
"use strict";

const assert = require("assert");
const {
  normalizeManifest,
  normalizeResultRow,
  sha256OfValue,
} = require("./lib/arena-calibration-core");
const {
  ACTION_NAMES,
  SHADOW_PROFILES,
  buildDecisionSnapshot,
  createPvePacket,
  createShadowExperiment,
  createShadowRequests,
  scoreShadowProposals,
  validatePveResponse,
} = require("./lib/campaign-evaluation");
const { analyzePairedStrength } = require("./lib/paired-strength");

const NOW = "2026-08-27T11:00:00.000Z";
const HASH = (text) => sha256OfValue({ text });

function roster(type) {
  return [{ type, level: 30 }];
}

function testCase(caseId, blue, red, repeat, tags) {
  return {
    caseId,
    blueRoster: roster(blue),
    redRoster: roster(red),
    repeat,
    timeoutFrames: 1800,
    spawnDistance: 650,
    blueFormation: "line",
    redFormation: "line",
    formationSpacing: 54,
    tags: tags || ["fixture"],
    plannerReason: "Gate CDE fixture",
  };
}

function buildManifest() {
  return normalizeManifest({
    schema: "arena-calibration.case-manifest.v1",
    batchId: "gate-cde-fixture",
    createdAt: NOW,
    buildCommit: "fixture",
    planner: { name: "gate-cde-fixture", version: 1 },
    arenaMode: "calibration",
    repeat: 1,
    timeoutFrames: 1800,
    blueBench: null,
    cases: [
      testCase("candidate-ab", "兵种1", "兵种2", 3),
      testCase("candidate-ab-side-swap", "兵种2", "兵种1", 3, ["fixture", "side-swap"]),
      testCase("candidate-bc", "兵种2", "兵种3", 3),
      testCase("candidate-de", "兵种4", "兵种5", 1),
    ],
  });
}

function resultRow(manifest, testCaseEntry, repeatIndex, winner, status) {
  return normalizeResultRow({
    schema: "arena-calibration.result.v1",
    batchId: manifest.batchId,
    manifestHash: manifest.manifestHash,
    caseId: testCaseEntry.caseId,
    caseHash: testCaseEntry.caseHash,
    runId: `${testCaseEntry.caseId}-r${String(repeatIndex).padStart(3, "0")}`,
    repeatIndex,
    status: status || "finished",
    winner: winner === undefined ? null : winner,
    frames: status === "timeout" ? 1800 : 500,
    durationMs: status === "timeout" ? 60000 : 16000,
    requestedSpawnDistance: 650,
    blueFormation: "line",
    redFormation: "line",
    formationSpacing: 54,
    phaseSpawnCount: 0,
    spawnedUnits: [],
    blueSpawnPositions: [],
    redSpawnPositions: [],
    formationAudit: {},
    authorityContext: {},
    blueUnitResults: [],
    redUnitResults: [],
    blue: { maxHp: 1000, remainHp: winner === "blue" ? 500 : 0, aliveCount: winner === "blue" ? 1 : 0, startMaxHp: 1000, startCount: 1 },
    red: { maxHp: 1000, remainHp: winner === "red" ? 500 : 0, aliveCount: winner === "red" ? 1 : 0, startMaxHp: 1000, startCount: 1 },
    errors: [],
    startedAt: NOW,
    completedAt: "2026-08-27T11:01:00.000Z",
  });
}

function buildRows(manifest) {
  const byId = new Map(manifest.cases.map((entry) => [entry.caseId, entry]));
  return [
    resultRow(manifest, byId.get("candidate-ab"), 1, "blue"),
    resultRow(manifest, byId.get("candidate-ab"), 2, "blue"),
    resultRow(manifest, byId.get("candidate-ab"), 3, "draw"),
    resultRow(manifest, byId.get("candidate-ab-side-swap"), 1, "red"),
    resultRow(manifest, byId.get("candidate-ab-side-swap"), 2, "red"),
    resultRow(manifest, byId.get("candidate-ab-side-swap"), 3, "draw"),
    resultRow(manifest, byId.get("candidate-bc"), 1, "blue"),
    resultRow(manifest, byId.get("candidate-bc"), 2, "red"),
    resultRow(manifest, byId.get("candidate-bc"), 3, "blue"),
    resultRow(manifest, byId.get("candidate-de"), 1, null, "timeout"),
  ];
}

function budget(maxRuns) {
  return { maxRuns, maxFrames: maxRuns * 1800, maxWallClockMinutes: maxRuns * 2, maxHumanMinutes: 0 };
}

function proposal(snapshot, profile, index) {
  const catalog = snapshot.caseCatalog[index % snapshot.caseCatalog.length];
  const actionBudget = budget(2);
  return {
    schema: "arena-calibration.controller-proposal.v1",
    proposalId: `proposal-${profile}`,
    decisionSnapshotId: snapshot.decisionSnapshotId,
    modelProfile: profile,
    role: profile.startsWith("C_") ? "adjudicator" : "manager",
    generatedAt: NOW,
    actions: [{
      actionId: `action-${index + 1}`,
      action: index === 1 ? "create_side_swap" : "append_samples",
      riskLevel: "auto_execute",
      budget: actionBudget,
      expectedInformationGain: 0.6 + index * 0.1,
      evidenceRefs: [HASH(`evidence-${index}`)],
      confidence: 0.7,
      preconditions: { campaignStates: ["RUNNING"], requiresIdleGrant: true, snapshotHash: snapshot.snapshotHash },
      candidateId: catalog.candidateId,
      caseHash: catalog.caseHash,
      ...(index === 1 ? {} : { sideAssignment: "original", additionalRuns: 2 }),
    }],
    totalBudget: actionBudget,
    evidenceRefs: [HASH(`proposal-evidence-${index}`)],
    risks: ["small_sample"],
    counterexamples: ["timeout_sensitive_matchup"],
    confidence: 0.7,
    abstain: false,
    requiresHuman: false,
  };
}

function main() {
  const manifest = buildManifest();
  const rows = buildRows(manifest);
  const shard = { manifest, rows, artifactHash: HASH("execution-artifact"), inputRef: HASH("input") };
  const snapshot = buildDecisionSnapshot({
    campaignId: "campaign-gate-cde-fixture",
    epochId: "epoch-gate-cde-1",
    decisionSnapshotId: "snapshot-gate-cde-1",
    battleSemanticsCohortId: "cohort-gate-cde-fixture",
    codeCommit: "fixture",
    createdAt: NOW,
    shards: [shard],
  });
  assert.strictEqual(snapshot.caseCatalog.length, 3);
  assert.strictEqual(snapshot.candidateEvidence.find((entry) => entry.candidateId === "candidate-ab").sideSwapReviewed, true);

  const experiment = createShadowExperiment(snapshot, { experimentId: "experiment-gate-c-fixture", createdAt: NOW });
  const requests = createShadowRequests(snapshot, experiment);
  assert.deepStrictEqual(requests.map((entry) => entry.profile), SHADOW_PROFILES);
  const proposals = SHADOW_PROFILES.map((profile, index) => proposal(snapshot, profile, index));
  const scored = scoreShadowProposals(snapshot, experiment, proposals, [], { createdAt: NOW });
  assert.strictEqual(scored.scorecard.selectionStatus, "ready_for_blind_human");
  assert(scored.blindPacket);
  assert(!JSON.stringify(scored.blindPacket).includes("modelProfile"));
  assert(!JSON.stringify(scored.blindPacket).includes("A_sol_manager_only"));
  assert.strictEqual(scored.secretMapping.mappings.length, 3);

  const invalid = JSON.parse(JSON.stringify(proposals));
  invalid[0].actions[0].preconditions.requiresIdleGrant = false;
  const rejected = scoreShadowProposals(snapshot, experiment, invalid, [], { createdAt: NOW });
  assert.strictEqual(rejected.scorecard.selectionStatus, "hard_gate_failure");
  assert.strictEqual(rejected.blindPacket, null);

  const unknownReference = JSON.parse(JSON.stringify(proposals));
  unknownReference[0].actions[0].candidateId = "candidate-not-in-snapshot";
  const unknownReferenceRejected = scoreShadowProposals(snapshot, experiment, unknownReference, [], { createdAt: NOW });
  assert.strictEqual(unknownReferenceRejected.scorecard.selectionStatus, "hard_gate_failure");
  assert(unknownReferenceRejected.scorecard.scores.some((entry) =>
    entry.violations.some((violation) => violation.includes("frozen catalog"))
  ));

  const paired = analyzePairedStrength([shard], {
    reportId: "paired-gate-d-fixture",
    planId: "plan-gate-d-fixture",
    cohortId: "cohort-gate-cde-fixture",
    createdAt: NOW,
  });
  assert.strictEqual(paired.report.eligibleResults, 9);
  assert.strictEqual(paired.report.excludedResults, 1);
  assert.strictEqual(paired.report.draws, 2);
  assert(paired.report.componentCount > 1);
  assert(paired.report.bridgeSuggestions.length > 0);
  assert(paired.plan.sideSwapReview.some((entry) => entry.sideSwapReviewed));
  assert(paired.plan.sideSwapReview.some((entry) => !entry.sideSwapReviewed));
  assert(paired.plan.anomalyDisposition.some((entry) => entry.disposition === "stability_investigate"));

  const pve = createPvePacket({
    packetId: "pve-gate-e-fixture",
    campaignId: "campaign-gate-cde-fixture",
    candidatePairId: "pair-gate-e-fixture",
    candidates: [
      { candidateId: "candidate-ab", evidenceRef: HASH("candidate-ab") },
      { candidateId: "candidate-bc", evidenceRef: HASH("candidate-bc") },
    ],
    holdoutCandidateId: "candidate-bc",
    playerBuildProfiles: ["approved-balanced-build-v1"],
    createdAt: NOW,
  });
  assert.strictEqual(pve.packet.encounters.length, 2);
  assert.strictEqual(pve.packet.encounters.filter((entry) => entry.holdout).length, 1);
  assert(!JSON.stringify(pve.packet).includes("candidate-ab"));
  const response = {
    schema: "arena-calibration.pve-equivalence-response.v1",
    packetId: pve.packet.packetId,
    packetHash: pve.packet.packetHash,
    calibrationObjective: "monster_group_to_humanoid_mercenary_equivalence",
    evidenceStatus: "human_equivalence_labels_complete",
    telemetryCompleteness: "equivalence_plus_objective",
    labels: pve.packet.encounters.map((entry, index) => ({
      encounterId: entry.encounterId,
      equivalentHumanoidCount: index + 1,
      equivalentHumanoidLevel: index === 0 ? 10 : 20,
      humanStatement: index === 0 ? "约等效一名十级人形佣兵" : "约等效两名二十级人形佣兵",
      pressureTags: index === 0 ? ["burst"] : ["sustain", "control"],
      confidence: 0.8,
      abnormalReported: false,
    })),
    evidenceRefs: [HASH("pve-session-a"), HASH("pve-session-b")],
    cleanup: {
      sourceSaveSha256: HASH("source-save"),
      sourceSaveUnchanged: true,
      nonTargetSaveUniverseUnchanged: true,
      activeDedicatedSlotArtifacts: 0,
      runtimeProcessCount: 0,
      cloneLockPresent: false,
      recoveryRecordPresent: false,
      quarantinedDedicatedArtifactHashes: [HASH("clone-json"), HASH("clone-sol")],
    },
    submittedAt: NOW,
    responseHash: "",
  };
  response.responseHash = sha256OfValue(Object.fromEntries(Object.entries(response).filter(([key]) => key !== "responseHash")));
  assert.strictEqual(validatePveResponse(pve.packet, response), true);
  const incomplete = JSON.parse(JSON.stringify(response));
  incomplete.labels.pop();
  incomplete.responseHash = sha256OfValue(Object.fromEntries(Object.entries(incomplete).filter(([key]) => key !== "responseHash")));
  assert.throws(() => validatePveResponse(pve.packet, incomplete), /fewer than 2 items|exact packet encounters/);

  console.log(JSON.stringify({
    ok: true,
    gates: ["C_machine_contract", "D_machine_contract", "E_packet_contract"],
    shadowProfiles: requests.length,
    blindPacketGenerated: true,
    hardGateFailureBlocksBlindPacket: true,
    pairedNodes: paired.report.nodes.length,
    disconnectedComponents: paired.report.componentCount,
    bridgeSuggestions: paired.report.bridgeSuggestions.length,
    pveEncounters: pve.packet.encounters.length,
    humanEvidenceFabricated: false,
  }, null, 2));
}

main();
