#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const { createPilotManifest, normalizeManifest } = require("./lib/arena-calibration-core");

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

try {
  checkSchemas();
  checkBatchIdContract();
  scripts.forEach(run);
  console.log(JSON.stringify({ ok: true, checked: scripts.length + schemas.length + 1 }, null, 2));
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
