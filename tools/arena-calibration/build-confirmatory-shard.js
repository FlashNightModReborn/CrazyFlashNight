#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const {
  normalizeManifest,
  readJsonFile,
} = require("./lib/arena-calibration-core");
const { writeJsonAtomic } = require("./lib/durable-campaign-journal");
const { assertSchemaInstance } = require("./lib/schema-registry");

function fail(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const options = {
    source: null,
    output: null,
    candidateId: null,
    batchId: "gate-d-confirmatory",
    originalRepeat: 10,
    swappedRepeat: 11,
    timeoutFrames: 1800,
    sourceReportHash: null,
    createdAt: null,
    check: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--source") options.source = path.resolve(argv[++index]);
    else if (token === "--output") options.output = path.resolve(argv[++index]);
    else if (token === "--candidate-id") options.candidateId = String(argv[++index]);
    else if (token === "--batch-id") options.batchId = String(argv[++index]);
    else if (token === "--original-repeat") options.originalRepeat = Number(argv[++index]);
    else if (token === "--swapped-repeat") options.swappedRepeat = Number(argv[++index]);
    else if (token === "--timeout-frames") options.timeoutFrames = Number(argv[++index]);
    else if (token === "--source-report-hash") options.sourceReportHash = String(argv[++index]);
    else if (token === "--created-at") options.createdAt = String(argv[++index]);
    else if (token === "--check") options.check = true;
    else fail(`unknown argument: ${token}`);
  }
  ["originalRepeat", "swappedRepeat", "timeoutFrames"].forEach((field) => {
    if (!Number.isInteger(options[field]) || options[field] < 1) fail(`${field} must be a positive integer`);
  });
  return options;
}

function withoutCaseHash(testCase) {
  const clone = JSON.parse(JSON.stringify(testCase));
  delete clone.caseHash;
  return clone;
}

function buildConfirmatoryManifest(source, options) {
  assertSchemaInstance("arena-calibration.case-manifest.v1", source, "confirmatory source manifest");
  const candidateId = options.candidateId;
  const original = source.cases.find((entry) => entry.caseId === candidateId);
  const swapped = source.cases.find((entry) => entry.caseId === `${candidateId}-side-swap`);
  if (!original || !swapped) throw new Error(`source manifest is missing both orientations for ${candidateId}`);
  const originalCase = withoutCaseHash(original);
  const swappedCase = withoutCaseHash(swapped);
  originalCase.repeat = options.originalRepeat;
  swappedCase.repeat = options.swappedRepeat;
  originalCase.timeoutFrames = options.timeoutFrames;
  swappedCase.timeoutFrames = options.timeoutFrames;
  originalCase.tags = Array.from(new Set([...(originalCase.tags || []), "confirmatory", "single-candidate"]));
  swappedCase.tags = Array.from(new Set([...(swappedCase.tags || []), "confirmatory", "single-candidate", "side-swap"]));
  originalCase.plannerReason = `${originalCase.plannerReason}; selected single candidate; source report ${options.sourceReportHash}`;
  swappedCase.plannerReason = `${swappedCase.plannerReason}; selected single candidate; source report ${options.sourceReportHash}`;
  const freshRunCount = options.originalRepeat + options.swappedRepeat;
  const manifest = normalizeManifest({
    schema: "arena-calibration.case-manifest.v1",
    batchId: options.batchId,
    createdAt: options.createdAt || new Date().toISOString(),
    buildCommit: source.buildCommit,
    planner: {
      name: "gate-d-single-candidate-confirmatory",
      version: 1,
      sourceManifestHash: source.manifestHash,
      sourceReportHash: options.sourceReportHash,
      candidateId,
      priorOriginalSamples: options.priorOriginalSamples,
      priorSwappedSamples: options.priorSwappedSamples,
      targetOriginalSamples: options.targetOriginalSamples,
      targetSwappedSamples: options.targetSwappedSamples,
      freshRunCount,
    },
    arenaMode: "calibration",
    repeat: 1,
    timeoutFrames: options.timeoutFrames,
    blueBench: null,
    cases: [originalCase, swappedCase],
  });
  assertSchemaInstance(manifest.schema, manifest, "confirmatory manifest");
  if (manifest.cases.reduce((sum, entry) => sum + entry.repeat, 0) !== freshRunCount) {
    throw new Error("confirmatory run-count closure failed");
  }
  return manifest;
}

function checkContract() {
  const source = normalizeManifest({
    schema: "arena-calibration.case-manifest.v1",
    batchId: "confirmatory-source",
    createdAt: "2026-08-27T00:00:00.000Z",
    buildCommit: "fixture",
    arenaMode: "calibration",
    repeat: 1,
    timeoutFrames: 1800,
    blueBench: null,
    cases: [
      { caseId: "candidate-one", blueRoster: [{ type: "兵种1", level: 20 }], redRoster: [{ type: "兵种2", level: 20 }], repeat: 1, timeoutFrames: 1800, tags: ["fixture"], plannerReason: "fixture" },
      { caseId: "candidate-one-side-swap", blueRoster: [{ type: "兵种2", level: 20 }], redRoster: [{ type: "兵种1", level: 20 }], repeat: 1, timeoutFrames: 1800, tags: ["fixture", "side-swap"], plannerReason: "fixture" },
    ],
  });
  const reportHash = `sha256:${"a".repeat(64)}`;
  const manifest = buildConfirmatoryManifest(source, {
    candidateId: "candidate-one",
    batchId: "confirmatory-check",
    originalRepeat: 10,
    swappedRepeat: 11,
    timeoutFrames: 1800,
    sourceReportHash: reportHash,
    priorOriginalSamples: 5,
    priorSwappedSamples: 4,
    targetOriginalSamples: 15,
    targetSwappedSamples: 15,
    createdAt: "2026-08-27T00:00:00.000Z",
  });
  if (manifest.planner.freshRunCount !== 21 || manifest.cases.length !== 2) throw new Error("confirmatory fixture closure failed");
  process.stdout.write(`${JSON.stringify({ ok: true, check: "confirmatory-shard-contract", freshRuns: 21, targetSamples: 30 })}\n`);
}

function main(argv) {
  const options = parseArgs(argv);
  if (options.check) return checkContract();
  if (!options.source || !options.output || !options.candidateId || !options.sourceReportHash) {
    fail("--source, --output, --candidate-id, and --source-report-hash are required");
  }
  options.priorOriginalSamples = 5;
  options.priorSwappedSamples = 4;
  options.targetOriginalSamples = options.priorOriginalSamples + options.originalRepeat;
  options.targetSwappedSamples = options.priorSwappedSamples + options.swappedRepeat;
  if (options.targetOriginalSamples !== 15 || options.targetSwappedSamples !== 15) {
    throw new Error("this confirmatory contract requires a balanced 15/15 final sample target");
  }
  const source = readJsonFile(options.source);
  const manifest = buildConfirmatoryManifest(source, options);
  if (fs.existsSync(options.output)) {
    const existing = readJsonFile(options.output);
    if (JSON.stringify(existing) !== JSON.stringify(manifest)) throw new Error(`output already exists with different bytes: ${options.output}`);
  } else {
    writeJsonAtomic(options.output, manifest);
  }
  process.stdout.write(`${JSON.stringify({ ok: true, batchId: manifest.batchId, candidateId: options.candidateId, manifestHash: manifest.manifestHash, freshRuns: manifest.planner.freshRunCount, targetOriginalSamples: manifest.planner.targetOriginalSamples, targetSwappedSamples: manifest.planner.targetSwappedSamples, output: options.output }, null, 2)}\n`);
}

try {
  main(process.argv.slice(2));
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exit(error.isUsageError ? 2 : 1);
}

module.exports = { buildConfirmatoryManifest, parseArgs };
