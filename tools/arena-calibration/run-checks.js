#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const { checkRuntimeIdentityContract } = require("../lib/runtime-process-identity");
const {
  analyzeRows,
  createPilotManifest,
  normalizeManifest,
  normalizeResultRow,
} = require("./lib/arena-calibration-core");
const {
  EMBEDDED_SCHEMA_IDS,
  loadSchemaRegistry,
  validateSchemaInstance,
} = require("./lib/schema-registry");

const scripts = [
  "test-custom-match-code.js",
  "test-campaign-contracts.js",
  "test-campaign-gate-b.js",
  "test-campaign-gates-cde.js",
  "test-campaign-gate-f.js",
  "run-shadow-models.js",
  "run-blind-review.js",
  "build-pve-readiness.js",
  "run-human-pve-session.js",
  "finalize-human-pve.js",
  "build-active-shard.js",
  "build-confirmatory-shard.js",
  "build-gate-f-week-plan.js",
  "intake-workbook.js",
  "build-candidates.js",
  "analyze-results.js",
  "plan-next-batch.js",
  "run-unattended.js",
  "gate-fctl.js",
];

function run(script) {
  const scriptPath = path.join(__dirname, script);
  const result = childProcess.spawnSync(process.execPath, [scriptPath, "--check"], {
    cwd: path.resolve(__dirname, "../.."),
    encoding: "utf8",
  });
  if (result.status !== 0) {
    process.stderr.write(result.stdout || "");
    process.stderr.write(result.stderr || "");
    throw new Error(`${script} --check failed with exit code ${result.status}`);
  }
  process.stdout.write(result.stdout);
}

function checkSchemas() {
  const registry = loadSchemaRegistry();
  registry.schemas.forEach(({ name, schema }) => {
    if (!schema.$id || !schema.properties || !schema.properties.schema) {
      throw new Error(`${name} is missing required schema metadata`);
    }
    if (!registry.ajv.getSchema(schema.$id)) throw new Error(`${name} did not compile to a validator`);
  });
  Object.entries(EMBEDDED_SCHEMA_IDS).forEach(([schemaId, target]) => {
    if (!registry.ajv.getSchema(target)) throw new Error(`${schemaId} embedded validator is missing`);
  });

  const valid = createPilotManifest({ batchId: "schema-instance-contract", repeat: 1 });
  const invalid = JSON.parse(JSON.stringify(valid));
  invalid.repeat = "1";
  if (validateSchemaInstance(valid.schema, valid).ok !== true) {
    throw new Error("valid case manifest instance was rejected");
  }
  if (validateSchemaInstance(invalid.schema, invalid).ok !== false) {
    throw new Error("invalid case manifest instance was not rejected");
  }
  return registry.schemas.length + Object.keys(EMBEDDED_SCHEMA_IDS).length;
}

function checkBatchIdContract() {
  normalizeManifest(createPilotManifest({ batchId: "pilot-contract" }));
  let rejected = false;
  try {
    normalizeManifest(createPilotManifest({ batchId: "..\\..\\escape" }));
  } catch (_error) {
    rejected = true;
  }
  if (!rejected) {
    throw new Error("path-like batchId was not rejected");
  }
}

function expectRejected(label, callback) {
  let rejected = false;
  try {
    callback();
  } catch (_error) {
    rejected = true;
  }
  if (!rejected) {
    throw new Error(`${label} was not rejected`);
  }
}

function checkPositiveIntegerContract() {
  const manifest = createPilotManifest({
    batchId: "pilot-positive-contract",
    createdAt: "2026-07-02T00:00:00.000Z",
    buildCommit: "fixture",
    repeat: 1,
    timeoutFrames: 1,
  });
  if (
    manifest.repeat !== 1 ||
    manifest.timeoutFrames !== 1 ||
    manifest.cases[0].repeat !== 1 ||
    manifest.cases[0].timeoutFrames !== 1 ||
    manifest.cases[0].spawnDistance !== 650
  ) {
    throw new Error("explicit positive integer overrides or default spawnDistance were not preserved");
  }

  expectRejected("manifest repeat=0", () =>
    createPilotManifest({ batchId: "pilot-zero-repeat", repeat: 0 })
  );
  expectRejected("manifest timeoutFrames=0", () =>
    createPilotManifest({ batchId: "pilot-zero-timeout", timeoutFrames: 0 })
  );

  const caseRepeatZero = JSON.parse(JSON.stringify(manifest));
  caseRepeatZero.batchId = "pilot-case-zero-repeat";
  caseRepeatZero.cases[0].caseId = "pilot-case-zero-repeat-case";
  caseRepeatZero.cases[0].repeat = 0;
  expectRejected("case repeat=0", () => normalizeManifest(caseRepeatZero));

  const caseTimeoutZero = JSON.parse(JSON.stringify(manifest));
  caseTimeoutZero.batchId = "pilot-case-zero-timeout";
  caseTimeoutZero.cases[0].caseId = "pilot-case-zero-timeout-case";
  caseTimeoutZero.cases[0].timeoutFrames = 0;
  expectRejected("case timeoutFrames=0", () => normalizeManifest(caseTimeoutZero));

  const caseSpawnDistanceZero = JSON.parse(JSON.stringify(manifest));
  caseSpawnDistanceZero.batchId = "pilot-case-zero-spawn-distance";
  caseSpawnDistanceZero.cases[0].caseId = "pilot-case-zero-spawn-distance-case";
  caseSpawnDistanceZero.cases[0].spawnDistance = 0;
  expectRejected("case spawnDistance=0", () => normalizeManifest(caseSpawnDistanceZero));

  const resultRow = {
    schema: "arena-calibration.result.v1",
    batchId: manifest.batchId,
    manifestHash: manifest.manifestHash,
    caseId: manifest.cases[0].caseId,
    caseHash: manifest.cases[0].caseHash,
    runId: "pilot-positive-contract-r0",
    repeatIndex: 0,
    status: "finished",
    winner: "blue",
  };
  expectRejected("result repeatIndex=0", () => normalizeResultRow(resultRow));
}

function checkTimeoutClassification() {
  const manifest = createPilotManifest({
    batchId: "pilot-timeout-classification",
    createdAt: "2026-07-02T00:00:00.000Z",
    buildCommit: "fixture",
    repeat: 5,
  });
  const testCase = manifest.cases[0];
  const rows = ["finished", "finished", "finished", "timeout", "timeout"].map((status, index) => ({
    schema: "arena-calibration.result.v1",
    batchId: manifest.batchId,
    manifestHash: manifest.manifestHash,
    caseId: testCase.caseId,
    caseHash: testCase.caseHash,
    runId: `${testCase.caseId}-r${index + 1}`,
    repeatIndex: index + 1,
    status,
    winner: status === "timeout" ? "timeout" : "blue",
    frames: status === "timeout" ? null : 1200,
    durationMs: status === "timeout" ? null : 40000,
    blue: { maxHp: 1000, remainHp: 200, aliveCount: 1, startMaxHp: 1000, startCount: 4 },
    red: { maxHp: 1000, remainHp: 0, aliveCount: 0, startMaxHp: 1000, startCount: 4 },
    errors: status === "timeout" ? [{ code: "timeout", message: "fixture" }] : [],
    startedAt: "2026-07-02T00:00:00.000Z",
    completedAt: "2026-07-02T00:01:00.000Z",
  }));

  const summary = analyzeRows(rows, {});
  const analyzedCase = summary.cases[0];
  if (analyzedCase.timeoutRate !== 0.4) {
    throw new Error(`expected timeoutRate=0.4, got ${analyzedCase.timeoutRate}`);
  }
  if (analyzedCase.errorCount !== 0) {
    throw new Error(`expected timeout rows not to count as errors, got ${analyzedCase.errorCount}`);
  }
  if (analyzedCase.classification !== "unstable_timeout") {
    throw new Error(`expected unstable_timeout classification, got ${analyzedCase.classification}`);
  }
}

function createSpawnDistanceManifest(batchId, spawnDistance) {
  const thiefRoster = [
    { type: "兵种44", level: 30 },
    { type: "兵种45", level: 30 },
    { type: "兵种48", level: 30 },
    { type: "兵种49", level: 30 },
  ];
  return normalizeManifest({
    schema: "arena-calibration.case-manifest.v1",
    batchId,
    createdAt: "2026-07-04T00:00:00.000Z",
    buildCommit: "fixture",
    planner: { name: "spawn-distance-contract", version: 1 },
    arenaMode: "calibration",
    repeat: 1,
    timeoutFrames: 600,
    blueBench: null,
    cases: [
      {
        caseId: "spawn-distance-contract",
        blueRoster: thiefRoster,
        redRoster: thiefRoster,
        repeat: 1,
        timeoutFrames: 600,
        spawnDistance,
      },
    ],
  });
}

function checkSpawnDistanceContract() {
  const dist600 = createSpawnDistanceManifest("pilot-spawn-distance-600", 600);
  const dist620 = createSpawnDistanceManifest("pilot-spawn-distance-620", 620);
  if (dist600.cases[0].spawnDistance !== 600 || dist620.cases[0].spawnDistance !== 620) {
    throw new Error("spawnDistance was not preserved during manifest normalization");
  }
  if (dist600.cases[0].caseHash === dist620.cases[0].caseHash) {
    throw new Error("spawnDistance did not affect caseHash");
  }

  const row = normalizeResultRow({
    schema: "arena-calibration.result.v1",
    batchId: dist620.batchId,
    manifestHash: dist620.manifestHash,
    caseId: dist620.cases[0].caseId,
    caseHash: dist620.cases[0].caseHash,
    runId: "spawn-distance-contract-r001",
    repeatIndex: 1,
    status: "finished",
    winner: "blue",
    requestedSpawnDistance: 620,
    spawnDistance: 620,
    blueX: 585,
    redX: 1205,
  });
  if (row.requestedSpawnDistance !== 620 || row.spawnDistance !== 620) {
    throw new Error("spawnDistance result metadata was not preserved");
  }
}

try {
  checkRuntimeIdentityContract();
  const schemaCount = checkSchemas();
  checkBatchIdContract();
  checkPositiveIntegerContract();
  checkTimeoutClassification();
  checkSpawnDistanceContract();
  scripts.forEach(run);
  console.log(JSON.stringify({ ok: true, checked: scripts.length + schemaCount + 5, schemaInstancesValidated: true }, null, 2));
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
