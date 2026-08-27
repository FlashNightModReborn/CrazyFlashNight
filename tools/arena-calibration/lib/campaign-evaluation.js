"use strict";

const {
  sha256OfValue,
} = require("./arena-calibration-core");
const {
  validateProposalAgainstSnapshot,
} = require("./campaign-contracts");
const {
  assertSchemaInstance,
  validateSchemaInstance,
} = require("./schema-registry");

const SHADOW_PROFILES = Object.freeze([
  "A_sol_manager_only",
  "B_luna_manager_only",
  "C_luna_propose_sol_adjudicate",
]);
const ACTION_NAMES = Object.freeze([
  "schedule_shard", "append_samples", "create_side_swap", "create_bridge", "prune_sampling",
  "quarantine_candidate", "enqueue_pve_packet", "complete_candidate", "pause_campaign", "abstain",
  "request_method_change", "propose_recommendation_bundle", "request_formal_apply",
]);

function withoutHash(value, field) {
  const clone = JSON.parse(JSON.stringify(value));
  delete clone[field];
  return clone;
}

function baseCandidateId(testCase) {
  return String(testCase.caseId).replace(/-side-swap(?:-.*)?$/, "");
}

function caseTemplate(testCase) {
  const template = JSON.parse(JSON.stringify(testCase));
  delete template.caseHash;
  return template;
}

function evidenceForRows(rows) {
  const samples = rows.length;
  const timeouts = rows.filter((row) => row.status === "timeout").length;
  const errorCount = rows.filter((row) => !["finished", "timeout"].includes(row.status)).length;
  return {
    samples,
    timeouts,
    timeoutRate: samples > 0 ? timeouts / samples : 0,
    errorCount,
  };
}

function buildDecisionSnapshot(options) {
  options = options || {};
  const caseCatalog = [];
  const grouped = new Map();
  const committedResultRefs = [];
  (options.shards || []).forEach((shard) => {
    assertSchemaInstance("arena-calibration.case-manifest.v1", shard.manifest, "snapshot manifest");
    (shard.rows || []).forEach((row) => assertSchemaInstance("arena-calibration.result.v1", row, "snapshot result"));
    if (shard.artifactHash) committedResultRefs.push(shard.artifactHash);
    shard.manifest.cases.forEach((testCase) => {
      const candidateId = baseCandidateId(testCase);
      const orientation = (testCase.tags || []).includes("side-swap") ? "swapped" : "original";
      if (!grouped.has(candidateId)) grouped.set(candidateId, { original: [], swapped: [], template: null, caseHash: null });
      const entry = grouped.get(candidateId);
      if (orientation === "original" && !entry.template) {
        entry.template = caseTemplate(testCase);
        entry.caseHash = testCase.caseHash;
        caseCatalog.push({ candidateId, caseHash: testCase.caseHash, caseTemplate: entry.template });
      }
      const matching = shard.rows.filter((row) => row.caseId === testCase.caseId && row.caseHash === testCase.caseHash);
      entry[orientation].push(...matching);
    });
  });

  const candidateEvidence = [];
  grouped.forEach((entry, candidateId) => {
    if (!entry.template || !entry.caseHash) return;
    const original = evidenceForRows(entry.original);
    const swapped = evidenceForRows(entry.swapped);
    const total = original.samples + swapped.samples;
    const timeoutRate = total > 0 ? (original.timeouts + swapped.timeouts) / total : 1;
    const seed = {
      candidateId,
      caseHash: entry.caseHash,
      original,
      swapped,
      sideSwapReviewed: original.samples > 0 && swapped.samples > 0,
      timeoutDisposition: timeoutRate <= 0.05 ? "low_rate" : "provisional",
      timeoutExplanationRef: null,
    };
    candidateEvidence.push({ ...seed, completionGateRef: sha256OfValue(seed) });
  });

  const createdAt = options.createdAt || new Date().toISOString();
  const snapshot = {
    schema: "arena-calibration.decision-snapshot.v1",
    decisionSnapshotId: options.decisionSnapshotId || `snapshot-${options.epochId || "gate-c"}`,
    snapshotHash: "",
    campaignId: options.campaignId,
    epochId: options.epochId || "epoch-gate-c-1",
    createdAt,
    runtimeCohort: {
      executionArtifactIdentity: sha256OfValue(committedResultRefs.slice().sort()),
      battleSemanticsCohortId: options.battleSemanticsCohortId,
    },
    caseCatalog,
    candidateEvidence,
    committedResultRefs: committedResultRefs.slice().sort(),
    excludedResultRefs: (options.excludedResultRefs || []).slice().sort(),
    posteriorSummary: options.posteriorSummary || { status: "provisional", reason: "Gate B sample count is intentionally small" },
    remainingBudget: options.remainingBudget || {
      maxRuns: 100,
      maxFrames: 180000,
      maxWallClockMinutes: 120,
      maxHumanMinutes: 15,
    },
    allowedActions: ACTION_NAMES.slice(),
    stopConditions: options.stopConditions || { minimumSamples: 30, maxTimeoutRate: 0.05, requireSideSwap: true },
    versions: {
      codeCommit: options.codeCommit,
      schemaVersion: "campaign-evaluation-v1",
      statisticsVersion: options.statisticsVersion || "paired-strength-v1",
      policyVersion: options.policyVersion || "gate-c-shadow-v1",
    },
  };
  snapshot.snapshotHash = sha256OfValue(withoutHash(snapshot, "snapshotHash"));
  assertSchemaInstance(snapshot.schema, snapshot, "decision snapshot");
  return snapshot;
}

function createShadowExperiment(snapshot, options) {
  options = options || {};
  assertSchemaInstance(snapshot.schema, snapshot, "shadow snapshot");
  const createdAt = options.createdAt || new Date().toISOString();
  const experiment = {
    schema: "arena-calibration.shadow-experiment.v1",
    experimentId: options.experimentId || `shadow-${snapshot.epochId}`,
    decisionSnapshotId: snapshot.decisionSnapshotId,
    snapshotHash: snapshot.snapshotHash,
    profiles: SHADOW_PROFILES.slice(),
    sharedActionWhitelist: snapshot.allowedActions.slice(),
    sharedBudget: JSON.parse(JSON.stringify(snapshot.remainingBudget)),
    selectionPolicy: {
      hardSafetyRequired: true,
      minimumQualityDelta: options.minimumQualityDelta === undefined ? 5 : options.minimumQualityDelta,
      complexityPenalty: options.complexityPenalty === undefined ? 2 : options.complexityPenalty,
      insufficientEvidenceOutcome: "provisional",
    },
    hiddenUntilAdjudicated: ["model_identity", "profile_identity", "source", "prior_tier", "historical_conclusion"],
    status: "awaiting_model_outputs",
    createdAt,
    experimentHash: "",
  };
  experiment.experimentHash = sha256OfValue(withoutHash(experiment, "experimentHash"));
  assertSchemaInstance(experiment.schema, experiment, "shadow experiment");
  return experiment;
}

function createShadowRequests(snapshot, experiment) {
  assertSchemaInstance(snapshot.schema, snapshot, "shadow request snapshot");
  assertSchemaInstance(experiment.schema, experiment, "shadow request experiment");
  return experiment.profiles.map((profile) => ({
    schema: "arena-calibration.shadow-request.v1",
    requestId: `request-${experiment.experimentId}-${profile}`,
    experimentId: experiment.experimentId,
    profile,
    decisionSnapshot: snapshot,
    outputSchema: "arena-calibration.controller-proposal.v1",
    constraints: {
      actionWhitelist: experiment.sharedActionWhitelist,
      totalBudget: experiment.sharedBudget,
      executePlan: false,
      preserveAbstain: true,
      doNotModifySnapshot: true,
    },
  }));
}

function aliasOrder(experiment, proposals) {
  return proposals
    .map((proposal) => ({ proposal, sortKey: sha256OfValue({ experimentHash: experiment.experimentHash, profile: proposal.modelProfile }) }))
    .sort((left, right) => left.sortKey.localeCompare(right.sortKey))
    .map((entry, index) => ({ alias: ["A", "B", "C"][index], proposal: entry.proposal }));
}

function actionCoverage(actions) {
  const candidateIds = new Set();
  actions.forEach((action) => {
    if (action.candidateId) candidateIds.add(action.candidateId);
    (action.caseRefs || []).forEach((entry) => candidateIds.add(entry.candidateId));
    if (action.leftCandidateId) candidateIds.add(action.leftCandidateId);
    if (action.rightCandidateId) candidateIds.add(action.rightCandidateId);
  });
  return {
    sideSwapActions: actions.filter((action) => action.action === "create_side_swap" || (action.sideAssignment === "swapped")).length,
    bridgeActions: actions.filter((action) => action.action === "create_bridge").length,
    boundaryActions: actions.filter((action) => ["quarantine_candidate", "abstain", "enqueue_pve_packet"].includes(action.action)).length,
    candidateCount: candidateIds.size,
  };
}

function redactProposal(alias, proposal) {
  const candidateAliases = new Map();
  let candidateCounter = 0;
  function candidateAlias(value) {
    if (!candidateAliases.has(value)) {
      candidateCounter += 1;
      candidateAliases.set(value, `candidate-${candidateCounter}`);
    }
    return candidateAliases.get(value);
  }
  const actions = JSON.parse(JSON.stringify(proposal.actions)).map((action) => {
    const output = { ...action };
    delete output.actionId;
    delete output.evidenceRefs;
    delete output.preconditions;
    ["candidateId", "leftCandidateId", "rightCandidateId"].forEach((field) => {
      if (output[field]) output[field] = candidateAlias(output[field]);
    });
    if (output.caseHash) output.caseHash = "hidden-case";
    if (output.bridgeCaseHash) output.bridgeCaseHash = "hidden-bridge-case";
    if (output.completionGateRef) output.completionGateRef = "hidden-completion-gate";
    if (output.caseRefs) {
      output.caseRefs = output.caseRefs.map((entry) => ({
        candidateId: candidateAlias(entry.candidateId),
        caseHash: "hidden-case",
        sideAssignment: entry.sideAssignment,
      }));
    }
    return output;
  });
  return {
    alias,
    actions,
    risks: proposal.risks.slice(),
    counterexamples: proposal.counterexamples.slice(),
    confidence: proposal.confidence,
  };
}

function scoreShadowProposals(snapshot, experiment, proposals, receipts, options) {
  options = options || {};
  if (!Array.isArray(proposals) || proposals.length !== 3) throw new Error("exactly three shadow proposals are required");
  const profileSet = new Set(proposals.map((proposal) => proposal.modelProfile));
  SHADOW_PROFILES.forEach((profile) => {
    if (!profileSet.has(profile)) throw new Error(`shadow proposal is missing profile ${profile}`);
  });
  const receiptMap = new Map((receipts || []).map((receipt) => [receipt.proposalId, receipt]));
  const aliased = aliasOrder(experiment, proposals);
  const scores = aliased.map(({ alias, proposal }) => {
    const validation = validateSchemaInstance("arena-calibration.controller-proposal.v1", proposal);
    const violations = validation.errors.map((entry) => `${entry.instancePath || "$"} ${entry.message}`);
    if (validation.ok) {
      try { validateProposalAgainstSnapshot(proposal, snapshot, "RUNNING"); } catch (error) { violations.push(error.message); }
    }
    const coverage = actionCoverage(proposal.actions || []);
    const receipt = receiptMap.get(proposal.proposalId) || {};
    const tokenCount = Number(receipt.usage && (receipt.usage.totalTokens || receipt.usage.total_tokens)) || 0;
    const durationMs = Number(receipt.durationMs) || 0;
    const expectedInformationGain = (proposal.actions || []).reduce((sum, action) => sum + (Number(action.expectedInformationGain) || 0), 0);
    const hardGatePass = validation.ok && violations.length === 0;
    const qualityScore = hardGatePass
      ? 50 + coverage.sideSwapActions * 4 + coverage.bridgeActions * 6 + coverage.boundaryActions * 2
        + coverage.candidateCount * 2 + expectedInformationGain * 5
        - experiment.selectionPolicy.complexityPenalty * Math.log10(Math.max(1, tokenCount + durationMs / 10))
      : -100;
    return {
      alias,
      proposalHash: sha256OfValue(proposal),
      schemaValid: validation.ok,
      hardGatePass,
      violations,
      coverage,
      expectedInformationGain,
      durationMs,
      tokenCount,
      qualityScore,
      eligible: hardGatePass,
    };
  });
  const allEligible = scores.every((score) => score.eligible);
  const ranked = scores.filter((score) => score.eligible).sort((left, right) => right.qualityScore - left.qualityScore);
  const delta = ranked.length >= 2 ? ranked[0].qualityScore - ranked[1].qualityScore : 0;
  const mechanicalLeader = allEligible && delta >= experiment.selectionPolicy.minimumQualityDelta ? ranked[0].alias : null;
  const scorecard = {
    schema: "arena-calibration.shadow-scorecard.v1",
    experimentId: experiment.experimentId,
    snapshotHash: snapshot.snapshotHash,
    scores,
    mechanicalLeader,
    selectionStatus: !allEligible ? "hard_gate_failure" : "ready_for_blind_human",
    createdAt: options.createdAt || new Date().toISOString(),
    scorecardHash: "",
  };
  scorecard.scorecardHash = sha256OfValue(withoutHash(scorecard, "scorecardHash"));
  assertSchemaInstance(scorecard.schema, scorecard, "shadow scorecard");
  if (!allEligible) return { scorecard, blindPacket: null, secretMapping: null };

  const blindPacket = {
    schema: "arena-calibration.blind-adjudication-packet.v1",
    packetId: `blind-${experiment.experimentId}`,
    experimentId: experiment.experimentId,
    snapshotHash: snapshot.snapshotHash,
    rubricVersion: options.rubricVersion || "gate-c-blind-rubric-v1",
    hiddenFields: experiment.hiddenUntilAdjudicated.slice(),
    proposals: aliased.map(({ alias, proposal }) => redactProposal(alias, proposal)),
    humanResponseSchema: {
      required: ["ranking", "selectedAlias", "safetyConcerns", "usefulnessReason"],
      ranking: ["A", "B", "C"],
      selectedAlias: ["A", "B", "C", "insufficient_evidence"],
      safetyConcerns: "array of concise strings",
      usefulnessReason: "one concise paragraph",
    },
    status: "awaiting_blind_human",
    createdAt: options.createdAt || new Date().toISOString(),
    packetHash: "",
  };
  blindPacket.packetHash = sha256OfValue(withoutHash(blindPacket, "packetHash"));
  assertSchemaInstance(blindPacket.schema, blindPacket, "blind adjudication packet");
  const secretMapping = {
    schema: "arena-calibration.blind-mapping.v1",
    packetId: blindPacket.packetId,
    mappings: aliased.map(({ alias, proposal }) => ({
      alias,
      proposalId: proposal.proposalId,
      modelProfile: proposal.modelProfile,
      proposalHash: sha256OfValue(proposal),
    })),
    mappingHash: "",
  };
  secretMapping.mappingHash = sha256OfValue(withoutHash(secretMapping, "mappingHash"));
  return { scorecard, blindPacket, secretMapping };
}

function createPvePacket(options) {
  options = options || {};
  if (!Array.isArray(options.candidates) || options.candidates.length < 2 || options.candidates.length > 4) {
    throw new Error("PVE packet requires 2..4 candidate encounters");
  }
  if (!Array.isArray(options.playerBuildProfiles) || options.playerBuildProfiles.length === 0) {
    throw new Error("PVE packet requires at least one approved player build profile");
  }
  const createdAt = options.createdAt || new Date().toISOString();
  const ordered = options.candidates
    .map((candidate) => ({ candidate, key: sha256OfValue({ packetId: options.packetId, candidateId: candidate.candidateId }) }))
    .sort((left, right) => left.key.localeCompare(right.key));
  const aliases = ["opponent-A", "opponent-B", "opponent-C", "opponent-D"];
  const encounters = ordered.map(({ candidate }, index) => ({
    encounterId: `encounter-${options.packetId}-${index + 1}`,
    candidateAlias: aliases[index],
    playerBuildProfile: options.playerBuildProfiles[index % options.playerBuildProfiles.length],
    order: index + 1,
    holdout: candidate.candidateId === options.holdoutCandidateId,
    objectiveTelemetry: ["duration", "player_death", "failure", "damage_taken", "damage_dealt", "remaining_hp", "abnormal_events"],
  }));
  if (!encounters.some((entry) => entry.holdout)) throw new Error("PVE packet must contain at least one declared holdout");
  const packet = {
    schema: "arena-calibration.pve-packet.v1",
    packetId: options.packetId,
    campaignId: options.campaignId,
    candidatePairId: options.candidatePairId,
    encounters,
    targetActiveMinutes: options.targetActiveMinutes || 8,
    hardLimitMinutes: 15,
    checkpointAtEncounterBoundary: true,
    hiddenFields: ["candidate_identity", "model_identity", "prior_tier", "source", "historical_conclusion"],
    subjectiveLabelContract: {
      calibrationObjective: "monster_group_to_humanoid_mercenary_equivalence",
      equivalentHumanoidCountRange: [1, 20],
      equivalentHumanoidLevelRange: [1, 100],
      pressureTagsMaximum: 2,
      confidenceRange: [0, 1, null],
      objectiveTelemetryIsAutomatic: true,
    },
    status: "ready",
    createdAt,
    packetHash: "",
  };
  packet.packetHash = sha256OfValue(withoutHash(packet, "packetHash"));
  assertSchemaInstance(packet.schema, packet, "PVE packet");
  const secretMapping = {
    schema: "arena-calibration.pve-mapping.v1",
    packetId: packet.packetId,
    mappings: ordered.map(({ candidate }, index) => ({
      encounterId: encounters[index].encounterId,
      candidateAlias: aliases[index],
      candidateId: candidate.candidateId,
      evidenceRef: candidate.evidenceRef,
      holdout: candidate.candidateId === options.holdoutCandidateId,
    })),
    mappingHash: "",
  };
  secretMapping.mappingHash = sha256OfValue(withoutHash(secretMapping, "mappingHash"));
  return { packet, secretMapping };
}

function validatePveResponse(packet, response) {
  assertSchemaInstance(packet.schema, packet, "PVE packet");
  assertSchemaInstance(response.schema, response, "PVE response");
  if (response.packetId !== packet.packetId) throw new Error("PVE response packetId mismatch");
  if (response.schema === "arena-calibration.pve-equivalence-response.v1"
      && response.packetHash !== packet.packetHash) {
    throw new Error("PVE equivalence response packetHash mismatch");
  }
  if (response.responseHash !== sha256OfValue(withoutHash(response, "responseHash"))) {
    throw new Error("PVE response hash mismatch");
  }
  const expected = new Set(packet.encounters.map((entry) => entry.encounterId));
  const actual = new Set(response.labels.map((entry) => entry.encounterId));
  if (actual.size !== expected.size || Array.from(expected).some((entry) => !actual.has(entry))) {
    throw new Error("PVE response labels do not cover the exact packet encounters");
  }
  return true;
}

module.exports = {
  ACTION_NAMES,
  SHADOW_PROFILES,
  buildDecisionSnapshot,
  createPvePacket,
  createShadowExperiment,
  createShadowRequests,
  scoreShadowProposals,
  validatePveResponse,
};
