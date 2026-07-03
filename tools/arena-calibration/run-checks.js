#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const {
  analyzeRows,
  createPilotManifest,
  normalizeManifest,
  normalizeResultRow,
} = require("./lib/arena-calibration-core");

const scripts = [
  "test-custom-match-code.js",
  "build-candidates.js",
  "analyze-results.js",
  "plan-next-batch.js",
];

const schemas = [
  "case-manifest.schema.json",
  "result.schema.json",
  "summary.schema.json",
  "next-batch.schema.json",
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
  schemas.forEach((schema) => {
    const schemaPath = path.join(__dirname, "schemas", schema);
    const parsed = JSON.parse(fs.readFileSync(schemaPath, "utf8"));
    if (!parsed.$id || !parsed.properties || !parsed.properties.schema) {
      throw new Error(`${schema} is missing required schema metadata`);
    }
  });
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
    manifest.cases[0].timeoutFrames !== 1
  ) {
    throw new Error("explicit positive integer overrides were not preserved");
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

try {
  checkSchemas();
  checkBatchIdContract();
  checkPositiveIntegerContract();
  checkTimeoutClassification();
  scripts.forEach(run);
  console.log(JSON.stringify({ ok: true, checked: scripts.length + schemas.length + 3 }, null, 2));
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
