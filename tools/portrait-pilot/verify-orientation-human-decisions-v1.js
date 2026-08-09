#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-orientation-human-review-v1");

const ROOT = path.resolve(__dirname, "..", "..");
const DECISION_SCHEMA = "cf7.portrait-orientation-human-decisions.v1";

class DecisionError extends Error {}

function exactKeys(value, expected, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new DecisionError(`${label} 必须是对象`);
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (JSON.stringify(actual) !== JSON.stringify(wanted)) throw new DecisionError(`${label} 字段不闭合`);
}

function validTimestamp(value) {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

function validateDecisions(dataset, value) {
  reviewBuild.verifyData(dataset);
  exactKeys(value, [
    "schema",
    "batchId",
    "sourceDigest",
    "modelReportDigest",
    "reviewDigest",
    "complete",
    "exportedAt",
    "decisions",
  ], "orientation decisions");
  for (const [field, expected] of [
    ["schema", DECISION_SCHEMA],
    ["batchId", dataset.batchId],
    ["sourceDigest", dataset.sourceDigest],
    ["modelReportDigest", dataset.modelReportDigest],
    ["reviewDigest", dataset.reviewDigest],
    ["complete", true],
  ]) {
    if (value[field] !== expected) throw new DecisionError(`${field} 与方向复核数据不一致`);
  }
  if (!validTimestamp(value.exportedAt)) throw new DecisionError("exportedAt 不是有效时间");
  if (!Array.isArray(value.decisions) || value.decisions.length !== dataset.items.length) {
    throw new DecisionError(`必须完整裁决 ${dataset.items.length} 项`);
  }
  const itemKeys = new Set(dataset.items.map((item) => item.reviewKey));
  const seen = new Set();
  let keep = 0;
  let flipX = 0;
  for (const decision of value.decisions) {
    exactKeys(decision, ["reviewKey", "action", "updatedAt"], "orientation decision");
    if (!itemKeys.has(decision.reviewKey) || seen.has(decision.reviewKey)) {
      throw new DecisionError(`reviewKey 未知或重复：${decision.reviewKey}`);
    }
    seen.add(decision.reviewKey);
    if (!['keep', 'flip_x'].includes(decision.action)) throw new DecisionError(`action 非法：${decision.reviewKey}`);
    if (!validTimestamp(decision.updatedAt)) throw new DecisionError(`updatedAt 非法：${decision.reviewKey}`);
    if (decision.action === "keep") keep += 1;
    else flipX += 1;
  }
  if (seen.size !== itemKeys.size) throw new DecisionError("方向裁决 reviewKey 集合不完整");
  return { value, counts: { total: seen.size, keep, flipX } };
}

function parseArgs(argv) {
  const options = { review: null, decisions: null };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--review", "--decisions"].includes(argument)) {
      const next = argv[index + 1];
      if (!next || next.startsWith("--")) throw new DecisionError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--review") options.review = next;
      else options.decisions = next;
    } else if (argument === "--help") options.help = true;
    else throw new DecisionError(`未知参数：${argument}`);
  }
  return options;
}

function readObject(filePath, label) {
  try {
    const value = JSON.parse(fs.readFileSync(filePath, "utf8"));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("顶层不是对象");
    return value;
  } catch (error) {
    throw new DecisionError(`${label}不可读：${error.message}`);
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.review || !options.decisions) {
    process.stdout.write("用法：node tools/portrait-pilot/verify-orientation-human-decisions-v1.js --review <orientation-human-review-data.json> --decisions <portrait-orientation-human-decisions.json>\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const dataset = readObject(path.resolve(ROOT, options.review), "orientation review data");
  const decisions = readObject(path.resolve(ROOT, options.decisions), "orientation human decisions");
  const verified = validateDecisions(dataset, decisions);
  process.stdout.write(`${JSON.stringify({
    status: "orientation_human_decisions_verified",
    reviewDigest: dataset.reviewDigest,
    counts: verified.counts,
  })}\n`);
}

if (require.main === module) {
  try { main(); }
  catch (error) {
    process.stderr.write(`${error && error.stack ? error.stack : String(error)}\n`);
    process.exitCode = 1;
  }
}

module.exports = { DecisionError, validateDecisions };
