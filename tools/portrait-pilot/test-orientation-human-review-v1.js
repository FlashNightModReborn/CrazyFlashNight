#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const verifier = require("./verify-orientation-human-decisions-v1");

const ROOT = path.resolve(__dirname, "..", "..");

function main() {
  const reviewArgument = process.argv[2];
  if (!reviewArgument) throw new Error("用法：node tools/portrait-pilot/test-orientation-human-review-v1.js <orientation-human-review-data.json>");
  const dataset = JSON.parse(fs.readFileSync(path.resolve(ROOT, reviewArgument), "utf8"));
  const now = new Date().toISOString();
  const valid = {
    schema: dataset.decisionSchema,
    batchId: dataset.batchId,
    sourceDigest: dataset.sourceDigest,
    modelReportDigest: dataset.modelReportDigest,
    reviewDigest: dataset.reviewDigest,
    complete: true,
    exportedAt: now,
    decisions: dataset.items.map((item, index) => ({
      reviewKey: item.reviewKey,
      action: index % 2 === 0 ? "keep" : "flip_x",
      updatedAt: now,
    })),
  };
  const result = verifier.validateDecisions(dataset, valid);
  assert.deepEqual(result.counts, { total: 39, keep: 20, flipX: 19 });
  assert.throws(() => verifier.validateDecisions(dataset, { ...valid, reviewDigest: "0".repeat(64) }), /reviewDigest/);
  assert.throws(() => verifier.validateDecisions(dataset, { ...valid, decisions: valid.decisions.slice(1) }), /完整裁决/);
  assert.throws(() => verifier.validateDecisions(dataset, {
    ...valid,
    decisions: valid.decisions.map((decision, index) => index === 1 ? { ...decision, reviewKey: valid.decisions[0].reviewKey } : decision),
  }), /未知或重复/);
  process.stdout.write(`${JSON.stringify({
    status: "orientation_human_review_contract_verified",
    rows: dataset.items.length,
    staleDigestRejected: true,
    partialExportRejected: true,
    duplicateKeyRejected: true,
  })}\n`);
}

try { main(); }
catch (error) {
  process.stderr.write(`${error && error.stack ? error.stack : String(error)}\n`);
  process.exitCode = 1;
}
