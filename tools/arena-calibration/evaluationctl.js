#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const {
  readJsonFile,
  readJsonLines,
  sha256OfValue,
} = require("./lib/arena-calibration-core");
const {
  buildDecisionSnapshot,
  createPvePacket,
  createShadowExperiment,
  createShadowRequests,
  scoreShadowProposals,
  validatePveResponse,
} = require("./lib/campaign-evaluation");
const { adjudicateControllerProposal } = require("./lib/campaign-contracts");
const { analyzePairedStrength } = require("./lib/paired-strength");
const { sha256File } = require("./lib/campaign-supervisor");
const { writeJsonAtomic } = require("./lib/durable-campaign-journal");

function fail(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const args = { command: argv[0] || "help", input: null, outputDir: null, snapshot: null, experiment: null, proposals: [], receipts: [], packet: null, response: null };
  for (let index = 1; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--input") args.input = path.resolve(argv[++index]);
    else if (token === "--output-dir") args.outputDir = path.resolve(argv[++index]);
    else if (token === "--snapshot") args.snapshot = path.resolve(argv[++index]);
    else if (token === "--experiment") args.experiment = path.resolve(argv[++index]);
    else if (token === "--proposals") args.proposals = String(argv[++index] || "").split(",").filter(Boolean).map((entry) => path.resolve(entry));
    else if (token === "--receipts") args.receipts = String(argv[++index] || "").split(",").filter(Boolean).map((entry) => path.resolve(entry));
    else if (token === "--packet") args.packet = path.resolve(argv[++index]);
    else if (token === "--response") args.response = path.resolve(argv[++index]);
    else fail(`unknown argument: ${token}`);
  }
  return args;
}

function requireArg(args, field) {
  if (!args[field]) fail(`--${field.replace(/[A-Z]/g, (char) => `-${char.toLowerCase()}`)} is required`);
  return args[field];
}

function ensureOutput(args) {
  const outputDir = requireArg(args, "outputDir");
  fs.mkdirSync(outputDir, { recursive: true });
  return outputDir;
}

function loadShards(input) {
  return input.shards.map((shard) => {
    const manifestPath = path.resolve(shard.manifestPath);
    const resultPath = path.resolve(shard.resultPath);
    const artifact = shard.artifactPath ? readJsonFile(path.resolve(shard.artifactPath)) : null;
    return {
      manifest: readJsonFile(manifestPath),
      rows: readJsonLines(resultPath),
      artifactHash: artifact ? artifact.artifactHash : shard.artifactHash,
      inputRef: sha256OfValue({ manifestSha256: sha256File(manifestPath), resultSha256: sha256File(resultPath) }),
    };
  });
}

function freezeShadow(args) {
  const input = readJsonFile(requireArg(args, "input"));
  const outputDir = ensureOutput(args);
  const snapshot = buildDecisionSnapshot({
    ...input,
    shards: loadShards(input),
  });
  const experiment = createShadowExperiment(snapshot, {
    experimentId: input.experimentId,
    minimumQualityDelta: input.minimumQualityDelta,
    complexityPenalty: input.complexityPenalty,
    createdAt: input.createdAt,
  });
  const requests = createShadowRequests(snapshot, experiment);
  writeJsonAtomic(path.join(outputDir, "decision-snapshot.json"), snapshot);
  writeJsonAtomic(path.join(outputDir, "shadow-experiment.json"), experiment);
  requests.forEach((request) => writeJsonAtomic(path.join(outputDir, `${request.profile}-request.json`), request));
  return {
    status: experiment.status,
    snapshotHash: snapshot.snapshotHash,
    experimentHash: experiment.experimentHash,
    requestCount: requests.length,
    profiles: experiment.profiles,
  };
}

function scoreShadow(args) {
  const outputDir = ensureOutput(args);
  const snapshot = readJsonFile(requireArg(args, "snapshot"));
  const experiment = readJsonFile(requireArg(args, "experiment"));
  const proposals = args.proposals.map(readJsonFile);
  const receipts = args.receipts.map(readJsonFile);
  const result = scoreShadowProposals(snapshot, experiment, proposals, receipts);
  writeJsonAtomic(path.join(outputDir, "shadow-scorecard.json"), result.scorecard);
  if (result.blindPacket) {
    writeJsonAtomic(path.join(outputDir, "blind-adjudication-packet.json"), result.blindPacket);
    const secretDir = path.join(outputDir, "private");
    fs.mkdirSync(secretDir, { recursive: true });
    writeJsonAtomic(path.join(secretDir, "blind-mapping.json"), result.secretMapping);
  }
  return {
    selectionStatus: result.scorecard.selectionStatus,
    mechanicalLeader: result.scorecard.mechanicalLeader,
    blindPacketReady: Boolean(result.blindPacket),
  };
}

function pairedStrength(args) {
  const input = readJsonFile(requireArg(args, "input"));
  const outputDir = ensureOutput(args);
  const result = analyzePairedStrength(loadShards(input), input);
  writeJsonAtomic(path.join(outputDir, "paired-strength-report.json"), result.report);
  writeJsonAtomic(path.join(outputDir, "active-sampling-plan.json"), result.plan);
  writeJsonAtomic(path.join(outputDir, "excluded-results.json"), result.excluded);
  return {
    reportHash: result.report.reportHash,
    eligibleResults: result.report.eligibleResults,
    excludedResults: result.report.excludedResults,
    nodes: result.report.nodes.length,
    componentCount: result.report.componentCount,
    bridgeSuggestions: result.report.bridgeSuggestions.length,
    sideSwapItems: result.plan.sideSwapReview.length,
    anomalyItems: result.plan.anomalyDisposition.length,
  };
}

function preparePve(args) {
  const input = readJsonFile(requireArg(args, "input"));
  const outputDir = ensureOutput(args);
  const result = createPvePacket(input);
  writeJsonAtomic(path.join(outputDir, "pve-packet.json"), result.packet);
  const secretDir = path.join(outputDir, "private");
  fs.mkdirSync(secretDir, { recursive: true });
  writeJsonAtomic(path.join(secretDir, "pve-mapping.json"), result.secretMapping);
  return {
    packetHash: result.packet.packetHash,
    encounterCount: result.packet.encounters.length,
    targetActiveMinutes: result.packet.targetActiveMinutes,
    hardLimitMinutes: result.packet.hardLimitMinutes,
    holdoutCount: result.packet.encounters.filter((entry) => entry.holdout).length,
    status: result.packet.status,
  };
}

function validatePve(args) {
  const packet = readJsonFile(requireArg(args, "packet"));
  const response = readJsonFile(requireArg(args, "response"));
  validatePveResponse(packet, response);
  return { packetId: packet.packetId, responseHash: response.responseHash, labels: response.labels.length };
}

function completeCandidate(args) {
  const input = readJsonFile(requireArg(args, "input"));
  const snapshot = readJsonFile(requireArg(args, "snapshot"));
  const outputDir = ensureOutput(args);
  const candidateId = String(input.candidateId || "");
  const finalState = String(input.finalState || "provisional");
  const campaignState = String(input.campaignState || "PAUSED");
  const evidence = (snapshot.candidateEvidence || []).find((entry) => entry.candidateId === candidateId);
  if (!evidence) fail(`candidate evidence is missing: ${candidateId}`);
  const zeroBudget = { maxRuns: 0, maxFrames: 0, maxWallClockMinutes: 0, maxHumanMinutes: 0 };
  const generatedAt = input.createdAt || new Date().toISOString();
  const action = {
    actionId: `complete-${candidateId}`,
    action: "complete_candidate",
    riskLevel: "auto_execute",
    budget: zeroBudget,
    expectedInformationGain: 0,
    evidenceRefs: [snapshot.snapshotHash, evidence.completionGateRef],
    confidence: 1,
    preconditions: {
      campaignStates: [campaignState],
      requiresIdleGrant: false,
      snapshotHash: snapshot.snapshotHash,
    },
    candidateId,
    caseHash: evidence.caseHash,
    completionGateRef: evidence.completionGateRef,
    finalState,
  };
  const proposal = {
    schema: "arena-calibration.controller-proposal.v1",
    proposalId: input.proposalId || `proposal-complete-${candidateId}`,
    decisionSnapshotId: snapshot.decisionSnapshotId,
    modelProfile: "rule-completion-gate-v1",
    role: "rule_fallback",
    generatedAt,
    actions: [action],
    totalBudget: zeroBudget,
    evidenceRefs: action.evidenceRefs.slice(),
    risks: ["Machine completion does not replace the pending human PVE experience check."],
    counterexamples: ["A later human PVE abnormality can keep the final calibration recommendation provisional."],
    confidence: 1,
    abstain: false,
    requiresHuman: true,
  };
  const result = adjudicateControllerProposal(proposal, snapshot, {
    campaignState,
    now: generatedAt,
    promptPolicyVersion: "gate-d-completion-v1",
  });
  writeJsonAtomic(path.join(outputDir, "completion-proposal.json"), proposal);
  writeJsonAtomic(path.join(outputDir, "completion-receipt.json"), result.receipt);
  if (result.l0) writeJsonAtomic(path.join(outputDir, "completion-l0.json"), result.l0);
  if (result.exception) writeJsonAtomic(path.join(outputDir, "completion-exception.json"), result.exception);
  if (result.outcome !== "accepted") {
    throw new Error(`completion gate rejected ${candidateId}: ${result.receipt.validation && result.receipt.validation.error || result.outcome}`);
  }
  return {
    candidateId,
    finalState,
    outcome: result.outcome,
    receiptId: result.receipt.receiptId,
    proposalHash: result.receipt.proposalHash,
    completionGateRef: evidence.completionGateRef,
    originalSamples: evidence.original.samples,
    swappedSamples: evidence.swapped.samples,
    timeouts: evidence.original.timeouts + evidence.swapped.timeouts,
    errors: evidence.original.errorCount + evidence.swapped.errorCount,
  };
}

function printHelp() {
  console.log(`Usage: node tools/arena-calibration/evaluationctl.js <command> [options]

Commands:
  freeze-shadow  Freeze a real decision snapshot and three profile request artifacts.
  score-shadow   Validate three returned proposals and generate a blind human packet.
  paired-strength  Fit paired strength/intervals and create bridge/side-swap planning.
  prepare-pve    Create a blinded 2..4 encounter Gate E packet plus private mapping.
  validate-pve   Validate a human response against the exact packet.
  complete-candidate  Mechanically validate and receipt one frozen completion candidate.
`);
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.command === "help" || args.command === "--help" || args.command === "-h") return printHelp();
  let result;
  if (args.command === "freeze-shadow") result = freezeShadow(args);
  else if (args.command === "score-shadow") result = scoreShadow(args);
  else if (args.command === "paired-strength") result = pairedStrength(args);
  else if (args.command === "prepare-pve") result = preparePve(args);
  else if (args.command === "validate-pve") result = validatePve(args);
  else if (args.command === "complete-candidate") result = completeCandidate(args);
  else fail(`unknown command: ${args.command}`);
  console.log(JSON.stringify({ ok: true, command: args.command, ...result }, null, 2));
}

try {
  main(process.argv.slice(2));
} catch (error) {
  console.error(error.message);
  process.exit(error.isUsageError ? 2 : 1);
}
