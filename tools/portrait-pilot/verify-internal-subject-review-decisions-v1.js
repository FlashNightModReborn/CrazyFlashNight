#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-internal-subject-review-v1");

const ROOT = path.resolve(__dirname, "..", "..");
const DECISION_SCHEMA = "cf7.enemy-portrait-internal-subject-human-decisions.v1";

class DecisionError extends Error {}

function exactKeys(value, expected, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new DecisionError(`${label} 必须是对象`);
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (JSON.stringify(actual) !== JSON.stringify(wanted)) throw new DecisionError(`${label} 字段不闭合`);
}

function validateDecisions(dataset, value) {
  exactKeys(value, [
    "schema",
    "batchId",
    "sourceDigest",
    "manifestDigest",
    "modelReportDigest",
    "reviewDigest",
    "reviewedAt",
    "decisions",
  ], "decisions");
  for (const [field, expected] of [
    ["schema", DECISION_SCHEMA],
    ["batchId", dataset.batchId],
    ["sourceDigest", dataset.sourceDigest],
    ["manifestDigest", dataset.manifestDigest],
    ["modelReportDigest", dataset.modelReportDigest],
    ["reviewDigest", dataset.reviewDigest],
  ]) {
    if (value[field] !== expected) throw new DecisionError(`${field} 与 review-data 不一致`);
  }
  if (typeof value.reviewedAt !== "string" || !Number.isFinite(Date.parse(value.reviewedAt))) {
    throw new DecisionError("reviewedAt 不是有效时间");
  }
  if (!Array.isArray(value.decisions) || value.decisions.length !== dataset.items.length) {
    throw new DecisionError(`必须完整裁决 ${dataset.items.length} 项`);
  }
  const itemByKey = new Map(dataset.items.map((item) => [item.reviewKey, item]));
  const seen = new Set();
  for (const decision of value.decisions) {
    exactKeys(decision, ["reviewKey", "decision", "candidateId", "note"], "decision");
    const item = itemByKey.get(decision.reviewKey);
    if (!item || seen.has(decision.reviewKey)) throw new DecisionError(`reviewKey 未知或重复：${decision.reviewKey}`);
    seen.add(decision.reviewKey);
    if (!["select", "none"].includes(decision.decision)) throw new DecisionError(`decision 非法：${decision.reviewKey}`);
    if (typeof decision.note !== "string" || decision.note.length > 500) throw new DecisionError(`note 非法：${decision.reviewKey}`);
    if (decision.decision === "none") {
      if (decision.candidateId !== null) throw new DecisionError(`none 必须使用 null candidateId：${decision.reviewKey}`);
    } else if (!item.candidates.some((candidate) => candidate.candidateId === decision.candidateId)) {
      throw new DecisionError(`candidateId 不在当前行白名单：${decision.reviewKey}`);
    }
  }
  return value;
}

function parseArgs(argv) {
  const options = { review: null, decisions: null };
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--review") {
      options.review = argv[index + 1];
      index += 1;
    } else if (argv[index] === "--decisions") {
      options.decisions = argv[index + 1];
      index += 1;
    } else if (argv[index] === "--help") {
      options.help = true;
    } else {
      throw new DecisionError(`未知参数：${argv[index]}`);
    }
  }
  return options;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.review || !options.decisions) {
    process.stdout.write("用法：node tools/portrait-pilot/verify-internal-subject-review-decisions-v1.js --review <review-data.json> --decisions <decisions.json>\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const reviewPath = path.resolve(ROOT, options.review);
  const decisionsPath = path.resolve(ROOT, options.decisions);
  const dataset = JSON.parse(fs.readFileSync(reviewPath, "utf8"));
  reviewBuild.verifyReviewDataset(dataset);
  const decisions = JSON.parse(fs.readFileSync(decisionsPath, "utf8"));
  validateDecisions(dataset, decisions);
  process.stdout.write(`${JSON.stringify({ status: "human_decisions_verified", rows: decisions.decisions.length, reviewDigest: dataset.reviewDigest })}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error && error.stack ? error.stack : String(error)}\n`);
    process.exitCode = 1;
  }
}

module.exports = { validateDecisions };
