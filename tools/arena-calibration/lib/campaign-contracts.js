"use strict";

const {
  NEXT_BATCH_SCHEMA,
  normalizeManifest,
  sha256OfValue,
  validateNextBatch,
} = require("./arena-calibration-core");
const { assertSchemaInstance } = require("./schema-registry");

const SNAPSHOT_SCHEMA = "arena-calibration.decision-snapshot.v1";
const PROPOSAL_SCHEMA = "arena-calibration.controller-proposal.v1";
const RECEIPT_SCHEMA = "arena-calibration.decision-receipt.v1";
const EXCEPTION_SCHEMA = "arena-calibration.exception-inbox-item.v1";
const RUN_ACTIONS = new Set(["schedule_shard", "append_samples", "create_side_swap", "create_bridge"]);

class TrustedL0InvariantError extends Error {
  constructor(message, details) {
    super(message);
    this.name = "TrustedL0InvariantError";
    this.details = details || null;
  }
}

function safeId(value, fallback) {
  const normalized = String(value || "").replace(/[^A-Za-z0-9._:-]+/g, "-").slice(0, 128);
  return normalized && /^[A-Za-z0-9]/.test(normalized) ? normalized : fallback;
}

function nowIso(options) {
  return options.now || new Date().toISOString();
}

function zeroBudget() {
  return { maxRuns: 0, maxFrames: 0, maxWallClockMinutes: 0, maxHumanMinutes: 0 };
}

function sumBudgets(actions) {
  return actions.reduce((sum, action) => {
    const budget = action.budget || zeroBudget();
    return {
      maxRuns: sum.maxRuns + budget.maxRuns,
      maxFrames: sum.maxFrames + budget.maxFrames,
      maxWallClockMinutes: sum.maxWallClockMinutes + budget.maxWallClockMinutes,
      maxHumanMinutes: sum.maxHumanMinutes + budget.maxHumanMinutes,
    };
  }, zeroBudget());
}

function assertBudgetWithin(actual, limit, label) {
  ["maxRuns", "maxFrames", "maxWallClockMinutes", "maxHumanMinutes"].forEach((field) => {
    if (actual[field] > limit[field]) {
      throw new Error(`${label}.${field} ${actual[field]} exceeds ${limit[field]}`);
    }
  });
}

function validateProposalAgainstSnapshot(proposal, snapshot, campaignState) {
  if (proposal.decisionSnapshotId !== snapshot.decisionSnapshotId) {
    throw new Error("proposal decisionSnapshotId does not match trusted snapshot");
  }
  const allowed = new Set(snapshot.allowedActions);
  const snapshotCatalog = new Map(snapshot.caseCatalog.map((entry) => [entry.caseHash, entry]));
  const snapshotCandidates = new Set(snapshot.caseCatalog.map((entry) => entry.candidateId));
  proposal.actions.forEach((action) => {
    if (!allowed.has(action.action)) throw new Error(`action is not allowed by snapshot: ${action.action}`);
    if (action.preconditions.snapshotHash !== snapshot.snapshotHash) {
      throw new Error(`${action.action} precondition snapshotHash does not match`);
    }
    if (!action.preconditions.campaignStates.includes(campaignState)) {
      throw new Error(`${action.action} precondition does not allow campaign state ${campaignState}`);
    }
    if (RUN_ACTIONS.has(action.action) && action.preconditions.requiresIdleGrant !== true) {
      throw new Error(`${action.action} must declare requiresIdleGrant=true`);
    }
    if (["append_samples", "create_side_swap"].includes(action.action)) {
      const catalogEntry = snapshotCatalog.get(action.caseHash);
      if (!catalogEntry || catalogEntry.candidateId !== action.candidateId) {
        throw new Error(`${action.action} candidateId/caseHash is not present in the frozen catalog`);
      }
    }
    if (action.action === "schedule_shard") {
      action.caseRefs.forEach((reference) => {
        const catalogEntry = snapshotCatalog.get(reference.caseHash);
        if (!catalogEntry || catalogEntry.candidateId !== reference.candidateId) {
          throw new Error("schedule_shard candidateId/caseHash is not present in the frozen catalog");
        }
      });
    }
    if (action.action === "create_bridge") {
      if (!snapshotCatalog.has(action.bridgeCaseHash)) throw new Error("create_bridge bridgeCaseHash is not present in the frozen catalog");
      if (!snapshotCandidates.has(action.leftCandidateId) || !snapshotCandidates.has(action.rightCandidateId)) {
        throw new Error("create_bridge endpoint is not present in the frozen catalog");
      }
      if (action.leftCandidateId === action.rightCandidateId) throw new Error("create_bridge endpoints must be different candidates");
    }
    if (action.action === "complete_candidate") {
      const evidence = (snapshot.candidateEvidence || []).find((entry) =>
        entry.candidateId === action.candidateId && entry.caseHash === action.caseHash
      );
      if (!evidence) throw new Error(`completion evidence is missing for ${action.candidateId}/${action.caseHash}`);
      if (evidence.completionGateRef !== action.completionGateRef) {
        throw new Error("completionGateRef does not match the frozen candidate evidence");
      }
      const totalSamples = evidence.original.samples + evidence.swapped.samples;
      if (totalSamples < 30 || evidence.original.samples < 1 || evidence.swapped.samples < 1) {
        throw new Error("complete_candidate requires at least 30 total samples with both side assignments represented");
      }
      if (evidence.original.errorCount !== 0 || evidence.swapped.errorCount !== 0) {
        throw new Error("complete_candidate requires errorCount=0 on both side assignments");
      }
      if (evidence.sideSwapReviewed !== true) {
        throw new Error("complete_candidate requires sideSwapReviewed=true");
      }
      ["original", "swapped"].forEach((orientation) => {
        const sample = evidence[orientation];
        if (sample.timeouts > sample.samples) {
          throw new Error(`complete_candidate ${orientation} timeouts cannot exceed samples`);
        }
        const calculatedRate = sample.samples > 0 ? sample.timeouts / sample.samples : 0;
        if (Math.abs(sample.timeoutRate - calculatedRate) > 1e-9) {
          throw new Error(`complete_candidate ${orientation} timeoutRate does not match samples/timeouts`);
        }
      });
      const combinedTimeoutRate = totalSamples > 0
        ? (evidence.original.timeouts + evidence.swapped.timeouts) / totalSamples
        : 1;
      const timeoutLimit = Math.min(snapshot.stopConditions.maxTimeoutRate, 0.05);
      if (combinedTimeoutRate > timeoutLimit) {
        throw new Error(`complete_candidate timeout gate exceeded: ${combinedTimeoutRate} > ${timeoutLimit}`);
      }
      if (evidence.timeoutDisposition === "explained_long_timeout" && !evidence.timeoutExplanationRef) {
        throw new Error("complete_candidate explained timeout requires timeoutExplanationRef");
      }
      if (evidence.timeoutDisposition === "provisional") {
        throw new Error("complete_candidate cannot use provisional timeout evidence");
      }
    }
  });
  const summed = sumBudgets(proposal.actions);
  assertBudgetWithin(summed, proposal.totalBudget, "proposal action budget");
  assertBudgetWithin(proposal.totalBudget, snapshot.remainingBudget, "proposal total budget");
  return true;
}

function catalogMap(snapshot) {
  const byHash = new Map();
  snapshot.caseCatalog.forEach((entry) => byHash.set(entry.caseHash, entry));
  return byHash;
}

function resolveCase(snapshotMap, candidateId, caseHash) {
  const entry = snapshotMap.get(caseHash);
  if (!entry || entry.candidateId !== candidateId) {
    throw new Error(`snapshot case reference not found: ${candidateId}/${caseHash}`);
  }
  return entry;
}

function cloneCase(entry, actionId, repeat, sideAssignment) {
  const testCase = JSON.parse(JSON.stringify(entry.caseTemplate));
  testCase.caseId = `${safeId(testCase.caseId, "case")}-${safeId(actionId, "action")}`.slice(0, 120);
  testCase.repeat = repeat;
  testCase.tags = Array.from(new Set([...(testCase.tags || []), `proposal-${actionId}`]));
  if (sideAssignment === "swapped") {
    const blueRoster = testCase.blueRoster;
    const blueFormation = testCase.blueFormation;
    testCase.blueRoster = testCase.redRoster;
    testCase.redRoster = blueRoster;
    testCase.blueFormation = testCase.redFormation;
    testCase.redFormation = blueFormation;
    testCase.caseId = `${testCase.caseId}-side-swap`.slice(0, 120);
    testCase.tags.push("side-swap");
  }
  return testCase;
}

function adaptControllerProposal(proposal, snapshot, options) {
  options = options || {};
  const byHash = catalogMap(snapshot);
  const cases = [];
  const decisions = [];
  const directives = [];

  proposal.actions.forEach((action) => {
    if (action.action === "schedule_shard") {
      action.caseRefs.forEach((reference) => {
        const entry = resolveCase(byHash, reference.candidateId, reference.caseHash);
        cases.push(cloneCase(entry, action.actionId, 1, reference.sideAssignment));
        decisions.push({
          caseId: entry.caseTemplate.caseId,
          caseHash: reference.caseHash,
          action: reference.sideAssignment === "swapped" ? "append_counter_case" : "append_repeat",
          suggestedRepeat: 1,
          reason: `controller proposal ${proposal.proposalId}: schedule_shard`,
        });
      });
    } else if (action.action === "append_samples") {
      const entry = resolveCase(byHash, action.candidateId, action.caseHash);
      cases.push(cloneCase(entry, action.actionId, action.additionalRuns, action.sideAssignment));
      decisions.push({
        caseId: entry.caseTemplate.caseId,
        caseHash: action.caseHash,
        action: action.sideAssignment === "swapped" ? "append_counter_case" : "append_repeat",
        suggestedRepeat: action.additionalRuns,
        reason: `controller proposal ${proposal.proposalId}: append_samples`,
      });
    } else if (action.action === "create_side_swap") {
      const entry = resolveCase(byHash, action.candidateId, action.caseHash);
      cases.push(cloneCase(entry, action.actionId, Math.max(1, action.budget.maxRuns), "swapped"));
      decisions.push({
        caseId: entry.caseTemplate.caseId,
        caseHash: action.caseHash,
        action: "append_counter_case",
        suggestedRepeat: Math.max(1, action.budget.maxRuns),
        reason: `controller proposal ${proposal.proposalId}: create_side_swap`,
      });
    } else if (action.action === "create_bridge") {
      const entry = byHash.get(action.bridgeCaseHash);
      if (!entry) throw new Error(`trusted bridge case not found: ${action.bridgeCaseHash}`);
      const candidateIds = new Set(snapshot.caseCatalog.map((item) => item.candidateId));
      if (!candidateIds.has(action.leftCandidateId) || !candidateIds.has(action.rightCandidateId)) {
        throw new Error("bridge endpoint candidate is not present in snapshot");
      }
      cases.push(cloneCase(entry, action.actionId, Math.max(1, action.budget.maxRuns), "original"));
      decisions.push({
        caseId: entry.caseTemplate.caseId,
        caseHash: action.bridgeCaseHash,
        action: "append_counter_case",
        suggestedRepeat: Math.max(1, action.budget.maxRuns),
        reason: `controller proposal ${proposal.proposalId}: create_bridge`,
      });
    } else if (action.action === "prune_sampling") {
      const entry = resolveCase(byHash, action.candidateId, action.caseHash);
      decisions.push({
        caseId: entry.caseTemplate.caseId,
        caseHash: action.caseHash,
        action: "prune",
        suggestedRepeat: 0,
        reason: `${action.reasonCode}; controller proposal ${proposal.proposalId}`,
      });
    } else {
      directives.push({ actionId: action.actionId, action: action.action, disposition: "supervisor_control_only" });
    }
  });

  const nextBatch = {
    schema: NEXT_BATCH_SCHEMA,
    generatedAt: nowIso(options),
    planner: { name: "campaign-supervisor-adapter", version: 1 },
    sourceBatchId: safeId(snapshot.epochId, "epoch"),
    sourceManifestHash: snapshot.snapshotHash,
    sourceSummaryHash: snapshot.snapshotHash,
    decisions,
  };
  validateNextBatch(nextBatch);

  let manifest = null;
  if (cases.length > 0) {
    manifest = normalizeManifest({
      schema: "arena-calibration.case-manifest.v1",
      batchId: safeId(options.batchId || `proposal-${proposal.proposalId}`, "proposal-batch").slice(0, 64),
      createdAt: nowIso(options),
      buildCommit: options.buildCommit || snapshot.versions.codeCommit,
      planner: {
        name: "campaign-supervisor-adapter",
        version: 1,
        proposalId: proposal.proposalId,
        decisionSnapshotId: snapshot.decisionSnapshotId,
      },
      arenaMode: "calibration",
      repeat: 1,
      timeoutFrames: 1800,
      blueBench: null,
      cases,
    });
    if (options.faultInjection && options.faultInjection.kind === "trusted_l0_mutation") {
      if (options.faultInjection.testOnly !== true) throw new Error("trusted L0 fault injection requires testOnly=true");
      manifest = options.faultInjection.transform(JSON.parse(JSON.stringify(manifest)));
    }
    try {
      assertSchemaInstance("arena-calibration.case-manifest.v1", manifest, "trusted L0 manifest");
    } catch (error) {
      throw new TrustedL0InvariantError(`trusted L0 manifest is invalid: ${error.message}`, error.validationErrors);
    }
  }
  return { nextBatch, manifest, directives };
}

function makeReceipt(proposal, snapshot, outcome, campaignState, options) {
  const timestamp = nowIso(options);
  const proposalId = safeId(proposal && proposal.proposalId, "invalid-proposal");
  const receipt = {
    schema: RECEIPT_SCHEMA,
    receiptId: `receipt-${proposalId}-${sha256OfValue(proposal || {}).slice(7, 15)}`,
    proposalId,
    proposalHash: sha256OfValue(proposal || {}),
    decisionSnapshotId: safeId(
      proposal && proposal.decisionSnapshotId || snapshot && snapshot.decisionSnapshotId,
      "unknown-snapshot"
    ),
    modelProfile: safeId(proposal && proposal.modelProfile, "unknown-model"),
    role: String(proposal && proposal.role || "unknown"),
    promptPolicyVersion: options.promptPolicyVersion || "gate-a-v1",
    durationMs: options.durationMs || 0,
    usage: options.usage || {},
    validation: options.validation || {},
    outcome,
    campaignState,
    acceptedActionIds: outcome === "accepted" ? (proposal.actions || []).map((action) => action.actionId) : [],
    rejectedActionIds: outcome === "rejected" ? (proposal.actions || []).map((action) => safeId(action.actionId, "unknown-action")) : [],
    fallback: options.fallback || "none",
    createdAt: timestamp,
  };
  assertSchemaInstance(RECEIPT_SCHEMA, receipt, "decision receipt");
  return receipt;
}

function makeProposalException(proposal, snapshot, error, options) {
  const timestamp = nowIso(options);
  const evidenceRef = sha256OfValue(proposal || {});
  const dedupeKey = `proposal|${safeId(proposal && proposal.proposalId, "invalid")}|${error.schemaId || error.name || "validation"}`;
  const exception = {
    schema: EXCEPTION_SCHEMA,
    exceptionId: `exception-${evidenceRef.slice(7, 23)}`,
    campaignId: safeId(options.campaignId || snapshot.campaignId, "campaign"),
    dedupeKey,
    category: "proposal_rejected",
    severity: "warning",
    status: "open",
    summary: error.message,
    affectedScopes: [`snapshot:${snapshot.decisionSnapshotId}`],
    occurrences: [{ occurrenceId: `occurrence-${evidenceRef.slice(7, 19)}`, observedAt: timestamp, evidenceRef }],
    defaultAction: options.fallback === "rule_fallback" ? "keep_provisional" : "quarantine",
    reviewDeadline: new Date(Date.parse(timestamp) + 14 * 24 * 60 * 60 * 1000).toISOString(),
    createdAt: timestamp,
    updatedAt: timestamp,
  };
  assertSchemaInstance(EXCEPTION_SCHEMA, exception, "proposal exception");
  return exception;
}

function adjudicateControllerProposal(proposal, snapshot, options) {
  options = options || {};
  try {
    assertSchemaInstance(SNAPSHOT_SCHEMA, snapshot, "trusted decision snapshot");
  } catch (error) {
    const receipt = makeReceipt(proposal, snapshot || {}, "failed_closed", "FAILED_CLOSED", {
      ...options,
      validation: { stage: "trusted_snapshot", error: error.message },
    });
    return { outcome: "failed_closed", campaignState: "FAILED_CLOSED", receipt, exception: null, l0: null };
  }

  try {
    assertSchemaInstance(PROPOSAL_SCHEMA, proposal, "controller proposal");
    validateProposalAgainstSnapshot(proposal, snapshot, options.campaignState || "RUNNING");
  } catch (error) {
    const fallback = options.ruleFallbackAvailable === false ? "abstain" : "rule_fallback";
    const exception = makeProposalException(proposal, snapshot, error, { ...options, fallback });
    const receipt = makeReceipt(proposal, snapshot, "rejected", "EXCEPTIONS_PENDING", {
      ...options,
      fallback,
      validation: { stage: "proposal", error: error.message },
    });
    return { outcome: "rejected", campaignState: "EXCEPTIONS_PENDING", fallback, receipt, exception, l0: null };
  }

  try {
    const l0 = adaptControllerProposal(proposal, snapshot, options);
    const receipt = makeReceipt(proposal, snapshot, "accepted", options.campaignState || "RUNNING", {
      ...options,
      validation: { stage: "adapter", ok: true },
    });
    return { outcome: "accepted", campaignState: options.campaignState || "RUNNING", receipt, exception: null, l0 };
  } catch (error) {
    if (!(error instanceof TrustedL0InvariantError)) {
      const fallback = options.ruleFallbackAvailable === false ? "abstain" : "rule_fallback";
      const exception = makeProposalException(proposal, snapshot, error, { ...options, fallback });
      const receipt = makeReceipt(proposal, snapshot, "rejected", "EXCEPTIONS_PENDING", {
        ...options,
        fallback,
        validation: { stage: "adapter_input", error: error.message },
      });
      return { outcome: "rejected", campaignState: "EXCEPTIONS_PENDING", fallback, receipt, exception, l0: null };
    }
    const receipt = makeReceipt(proposal, snapshot, "failed_closed", "FAILED_CLOSED", {
      ...options,
      validation: { stage: "trusted_l0", error: error.message },
    });
    return { outcome: "failed_closed", campaignState: "FAILED_CLOSED", receipt, exception: null, l0: null };
  }
}

module.exports = {
  EXCEPTION_SCHEMA,
  PROPOSAL_SCHEMA,
  RECEIPT_SCHEMA,
  RUN_ACTIONS,
  SNAPSHOT_SCHEMA,
  TrustedL0InvariantError,
  adaptControllerProposal,
  adjudicateControllerProposal,
  validateProposalAgainstSnapshot,
};
