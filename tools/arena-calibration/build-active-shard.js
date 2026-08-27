#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const {
  normalizeManifest,
  readJsonFile,
} = require("./lib/arena-calibration-core");
const { writeJsonAtomic } = require("./lib/durable-campaign-journal");
const { rosterIdentity } = require("./lib/paired-strength");
const { assertSchemaInstance } = require("./lib/schema-registry");

function fail(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const options = {
    input: null,
    plan: null,
    output: null,
    batchId: "gate-d-active-shard",
    createdAt: null,
    bridgeRepeat: 2,
    anomalyRepeat: 3,
    bridgeTimeoutFrames: 1800,
    anomalyTimeoutFrames: 3600,
    check: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--input") options.input = path.resolve(argv[++index]);
    else if (token === "--plan") options.plan = path.resolve(argv[++index]);
    else if (token === "--output") options.output = path.resolve(argv[++index]);
    else if (token === "--batch-id") options.batchId = String(argv[++index]);
    else if (token === "--created-at") options.createdAt = String(argv[++index]);
    else if (token === "--bridge-repeat") options.bridgeRepeat = Number(argv[++index]);
    else if (token === "--anomaly-repeat") options.anomalyRepeat = Number(argv[++index]);
    else if (token === "--bridge-timeout-frames") options.bridgeTimeoutFrames = Number(argv[++index]);
    else if (token === "--anomaly-timeout-frames") options.anomalyTimeoutFrames = Number(argv[++index]);
    else if (token === "--check") options.check = true;
    else fail(`unknown argument: ${token}`);
  }
  ["bridgeRepeat", "anomalyRepeat", "bridgeTimeoutFrames", "anomalyTimeoutFrames"].forEach((field) => {
    if (!Number.isInteger(options[field]) || options[field] < 1) fail(`--${field.replace(/[A-Z]/g, (char) => `-${char.toLowerCase()}`)} must be a positive integer`);
  });
  return options;
}

function stableClone(value) {
  if (Array.isArray(value)) return value.map(stableClone);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stableClone(value[key])]));
  }
  return value;
}

function stableStringify(value) {
  return JSON.stringify(stableClone(value));
}

function loadRosterCatalog(manifests) {
  const catalog = new Map();
  manifests.forEach((manifest) => {
    assertSchemaInstance("arena-calibration.case-manifest.v1", manifest, "active-shard source manifest");
    manifest.cases.forEach((testCase) => {
      ["blue", "red"].forEach((side) => {
        const nodeId = rosterIdentity(testCase, side);
        const semantic = {
          roster: testCase[`${side}Roster`],
          formation: testCase[`${side}Formation`],
          formationSpacing: testCase.formationSpacing,
          spawnDistance: testCase.spawnDistance,
        };
        if (catalog.has(nodeId) && stableStringify(catalog.get(nodeId)) !== stableStringify(semantic)) {
          throw new Error(`roster node has inconsistent execution semantics: ${nodeId}`);
        }
        catalog.set(nodeId, semantic);
      });
    });
  });
  return catalog;
}

function resolvePair(catalog, leftNodeId, rightNodeId) {
  const left = catalog.get(leftNodeId);
  const right = catalog.get(rightNodeId);
  if (!left || !right) throw new Error(`sampling pair is missing from the source roster catalog: ${leftNodeId}/${rightNodeId}`);
  if (left.formationSpacing !== right.formationSpacing) throw new Error("sampling pair has incompatible formation spacing");
  if (left.spawnDistance !== right.spawnDistance) throw new Error("sampling pair has incompatible spawn distance");
  return { left, right };
}

function makeCase(caseId, blue, red, repeat, timeoutFrames, tags, reason) {
  return {
    caseId,
    blueRoster: JSON.parse(JSON.stringify(blue.roster)),
    redRoster: JSON.parse(JSON.stringify(red.roster)),
    repeat,
    timeoutFrames,
    spawnDistance: blue.spawnDistance,
    blueFormation: blue.formation,
    redFormation: red.formation,
    formationSpacing: blue.formationSpacing,
    tags,
    plannerReason: reason,
  };
}

function addPairedCases(cases, pair, options) {
  const { left, right } = resolvePair(options.catalog, pair.leftNodeId, pair.rightNodeId);
  cases.push(makeCase(
    pair.caseId,
    left,
    right,
    pair.repeat,
    pair.timeoutFrames,
    pair.tags,
    pair.reason,
  ));
  cases.push(makeCase(
    `${pair.caseId}-side-swap`,
    right,
    left,
    pair.repeat,
    pair.timeoutFrames,
    [...pair.tags, "side-swap"],
    `${pair.reason}; deterministic side swap`,
  ));
}

function buildActiveManifest(sourceManifests, plan, options) {
  options = options || {};
  assertSchemaInstance("arena-calibration.active-sampling-plan.v1", plan, "active sampling plan");
  const bridgeRepeat = options.bridgeRepeat || 2;
  const anomalyRepeat = options.anomalyRepeat || 3;
  const bridgeTimeoutFrames = options.bridgeTimeoutFrames || 1800;
  const anomalyTimeoutFrames = options.anomalyTimeoutFrames || 3600;
  const catalog = loadRosterCatalog(sourceManifests);
  const cases = [];
  const bridges = plan.actions.filter((entry) => entry.action === "create_bridge");
  bridges.forEach((entry, index) => addPairedCases(cases, {
    leftNodeId: entry.leftNodeId,
    rightNodeId: entry.rightNodeId,
    caseId: `gate-d-bridge-${String(index + 1).padStart(2, "0")}`,
    repeat: bridgeRepeat,
    timeoutFrames: bridgeTimeoutFrames,
    tags: ["gate-d", "active-bridge", entry.actionId],
    reason: `${entry.reason}; source plan ${plan.planHash}`,
  }, { catalog }));
  const anomalies = plan.anomalyDisposition.filter((entry) => entry.disposition === "stability_investigate");
  anomalies.forEach((entry, index) => {
    const parts = entry.matchupId.split("|");
    if (parts.length !== 2) throw new Error(`invalid anomaly matchupId: ${entry.matchupId}`);
    addPairedCases(cases, {
      leftNodeId: parts[0],
      rightNodeId: parts[1],
      caseId: `gate-d-long-timeout-${String(index + 1).padStart(2, "0")}`,
      repeat: anomalyRepeat,
      timeoutFrames: anomalyTimeoutFrames,
      tags: ["gate-d", "timeout-investigation", "long-timeout"],
      reason: `stability investigation for ${entry.matchupId}; prior timeoutRate=${entry.timeoutRate}; source plan ${plan.planHash}`,
    }, { catalog });
  });
  const freshRunCount = cases.reduce((sum, entry) => sum + entry.repeat, 0);
  const expectedRunCount = bridges.length * bridgeRepeat * 2 + anomalies.length * anomalyRepeat * 2;
  if (freshRunCount !== expectedRunCount) throw new Error("active shard run-count closure failed");
  const manifest = normalizeManifest({
    schema: "arena-calibration.case-manifest.v1",
    batchId: options.batchId || "gate-d-active-shard",
    createdAt: options.createdAt || new Date().toISOString(),
    buildCommit: options.buildCommit,
    planner: {
      name: "gate-d-active-sampling",
      version: 1,
      sourcePlanHash: plan.planHash,
      bridgePairs: bridges.length,
      anomalyPairs: anomalies.length,
      bridgeRepeat,
      anomalyRepeat,
      bridgeTimeoutFrames,
      anomalyTimeoutFrames,
      freshRunCount,
    },
    arenaMode: "calibration",
    repeat: 1,
    timeoutFrames: bridgeTimeoutFrames,
    blueBench: null,
    cases,
  });
  assertSchemaInstance(manifest.schema, manifest, "active shard manifest");
  return manifest;
}

function checkContract() {
  const source = normalizeManifest({
    schema: "arena-calibration.case-manifest.v1",
    batchId: "active-shard-check-source",
    createdAt: "2026-08-27T00:00:00.000Z",
    buildCommit: "fixture",
    arenaMode: "calibration",
    repeat: 1,
    timeoutFrames: 1800,
    blueBench: null,
    cases: [{
      caseId: "pair-one",
      blueRoster: [{ type: "兵种1", level: 20 }],
      redRoster: [{ type: "兵种2", level: 20 }],
      repeat: 1,
      timeoutFrames: 1800,
      spawnDistance: 650,
      blueFormation: "line",
      redFormation: "line",
      formationSpacing: 54,
      tags: ["fixture"],
      plannerReason: "fixture",
    }],
  });
  const leftNodeId = rosterIdentity(source.cases[0], "blue");
  const rightNodeId = rosterIdentity(source.cases[0], "red");
  const plan = {
    schema: "arena-calibration.active-sampling-plan.v1",
    planId: "active-shard-check",
    strengthReportHash: `sha256:${"a".repeat(64)}`,
    actions: [{ action: "create_bridge", actionId: "bridge-1", leftNodeId, rightNodeId, reason: "fixture" }],
    sideSwapReview: [],
    anomalyDisposition: [{ matchupId: [leftNodeId, rightNodeId].sort().join("|"), disposition: "stability_investigate", timeoutRate: 0.1, errorCount: 0 }],
    createdAt: "2026-08-27T00:00:00.000Z",
    planHash: `sha256:${"b".repeat(64)}`,
  };
  const manifest = buildActiveManifest([source], plan, { batchId: "active-shard-check", createdAt: "2026-08-27T00:00:00.000Z" });
  if (manifest.cases.length !== 4 || manifest.planner.freshRunCount !== 10) throw new Error("active shard fixture run-count mismatch");
  process.stdout.write(`${JSON.stringify({ ok: true, check: "active-shard-contract", cases: 4, freshRuns: 10 })}\n`);
}

function main(argv) {
  const options = parseArgs(argv);
  if (options.check) return checkContract();
  if (!options.input || !options.plan || !options.output) fail("--input, --plan, and --output are required");
  const input = readJsonFile(options.input);
  const plan = readJsonFile(options.plan);
  if (!Array.isArray(input.shards) || input.shards.length === 0) throw new Error("paired-strength input has no source shards");
  const sourceManifests = input.shards.map((shard) => readJsonFile(path.resolve(shard.manifestPath)));
  const manifest = buildActiveManifest(sourceManifests, plan, options);
  if (fs.existsSync(options.output)) {
    const existing = readJsonFile(options.output);
    if (stableStringify(existing) !== stableStringify(manifest)) throw new Error(`output already exists with different bytes: ${options.output}`);
  } else {
    writeJsonAtomic(options.output, manifest);
  }
  process.stdout.write(`${JSON.stringify({ ok: true, batchId: manifest.batchId, manifestHash: manifest.manifestHash, cases: manifest.cases.length, freshRuns: manifest.planner.freshRunCount, output: options.output }, null, 2)}\n`);
}

try {
  main(process.argv.slice(2));
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exit(error.isUsageError ? 2 : 1);
}

module.exports = { buildActiveManifest, loadRosterCatalog, parseArgs };
