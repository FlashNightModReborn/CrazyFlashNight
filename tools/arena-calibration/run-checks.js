#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const {
  analyzeRows,
  createPilotManifest,
  normalizeManifest,
} = require("./lib/arena-calibration-core");

const scripts = [
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
  checkTimeoutClassification();
  scripts.forEach(run);
  console.log(JSON.stringify({ ok: true, checked: scripts.length + schemas.length + 2 }, null, 2));
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
