#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const baseCalibration = require("./build-feedback-calibration-v2");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const SCHEMA = "cf7.portrait-pilot-human-feedback-calibration.v3";

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function artifact(filePath) {
  const resolved = path.resolve(filePath);
  const relative = path.relative(ROOT, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative) || !fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    throw new reviewBuild.ReviewError(`artifact 越出仓库或缺失：${filePath}`);
  }
  return {
    path: relative.replaceAll("\\", "/"),
    bytes: fs.statSync(resolved).size,
    sha256: reviewBuild.sha256File(resolved),
  };
}

function readJson(filePath, label) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    throw new reviewBuild.ReviewError(`${label} 缺失：${filePath}`);
  }
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    throw new reviewBuild.ReviewError(`${label} 不是合法 JSON：${error.message}`);
  }
}

function ensurePilotChild(target, label, allowExisting = false) {
  const resolved = path.resolve(ROOT, target);
  const relative = path.relative(PILOT_ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new reviewBuild.ReviewError(`${label} 必须位于 tmp/portrait-pilot 下`);
  }
  if (!allowExisting && fs.existsSync(resolved)) {
    throw new reviewBuild.ReviewError(`${label} 已存在，禁止覆盖：${resolved}`);
  }
  return resolved;
}

function parseArgs(argv) {
  const options = { reviewBatch: null, guidanceBatches: [], output: null, batchId: null, check: false, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--review-batch", "--guidance-batch", "--output", "--batch-id"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new reviewBuild.ReviewError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--review-batch") options.reviewBatch = value;
      else if (argument === "--guidance-batch") options.guidanceBatches.push(value);
      else if (argument === "--output") options.output = value;
      else options.batchId = value;
    } else if (argument === "--check") options.check = true;
    else if (argument === "--help") options.help = true;
    else throw new reviewBuild.ReviewError(`未知参数：${argument}`);
  }
  return options;
}

function categoryCounts(rows) {
  const counts = {};
  for (const row of rows) {
    for (const category of row.feedbackCategories) counts[category] = (counts[category] || 0) + 1;
  }
  return counts;
}

function patchExplicitReverse(rows) {
  for (const row of rows) {
    if (row.status !== "adjustment" || !/反转/u.test(String(row.notes || ""))) continue;
    if (!row.feedbackCategories.includes("orientation_mismatch")) {
      row.feedbackCategories.push("orientation_mismatch");
    }
    row.route = "orientation_transform";
  }
}

function buildReport(options) {
  const report = baseCalibration.buildReport(options);
  patchExplicitReverse(report.rows);
  report.counts.categoryCounts = categoryCounts(report.rows);
  report.schema = SCHEMA;
  report.inputs.v2ControllerSource = report.inputs.controllerSource;
  report.inputs.controllerSource = artifact(__filename);
  report.adaptiveScaling.maximumConcurrency = 3;
  report.adaptiveScaling.executionProfile = {
    model: "Luna Max",
    serviceTier: "fast",
    maximumConcurrency: 3,
    timeoutSeconds: 600,
    concurrencyIncreaseEligible: false,
    holdReason: "r80 required two bounded geometry repairs; no evidence yet supports concurrency 4-6",
  };
  report.gates.explicitReverseKeywordClassified = true;
  report.gates.executionProfileBound = true;
  delete report.feedbackDigest;
  report.feedbackDigest = sha256Bytes(reviewBuild.stableStringify(report));
  return report;
}

function verifyReport(report) {
  if (report.schema !== SCHEMA || report.status !== "human_feedback_calibrated" || report.productionReady !== false) {
    throw new reviewBuild.ReviewError("feedback calibration v3 schema 或状态非法");
  }
  const envelope = { ...report };
  delete envelope.feedbackDigest;
  if (sha256Bytes(reviewBuild.stableStringify(envelope)) !== report.feedbackDigest) {
    throw new reviewBuild.ReviewError("feedbackDigest 不匹配");
  }
  const records = [
    report.inputs.reviewData,
    report.inputs.decisions,
    report.inputs.humanReviewReceipt,
    report.inputs.analysisBaseSource,
    report.inputs.v2ControllerSource,
    report.inputs.controllerSource,
    ...report.inputs.guidanceBatches.flatMap((entry) => [entry.data, entry.guidance, entry.receipt]),
  ];
  for (const record of records) reviewBuild.resolveRepoArtifact(record, "feedback calibration v3 input");

  const expectedCategories = categoryCounts(report.rows);
  if (JSON.stringify(expectedCategories) !== JSON.stringify(report.counts.categoryCounts)) {
    throw new reviewBuild.ReviewError("feedback calibration v3 分类计数不闭合");
  }
  for (const row of report.rows) {
    if (
      row.status === "adjustment" && /反转/u.test(String(row.notes || "")) &&
      (!row.feedbackCategories.includes("orientation_mismatch") || row.route !== "orientation_transform")
    ) {
      throw new reviewBuild.ReviewError(`反转备注未进入方向变换：${row.reviewKey}`);
    }
  }
  const scaling = report.adaptiveScaling;
  const profile = scaling.executionProfile;
  if (
    scaling.expectedRevisionBudget !== 6 || scaling.humanReviewPageLimit !== null ||
    scaling.expectedRevisionsAtDoubledSize !== Number((scaling.doubledShardSize * scaling.estimatedFailureRate).toFixed(6)) ||
    scaling.eligibleToDouble !== (
      scaling.doubledShardSize > scaling.currentShardSize &&
      scaling.expectedRevisionsAtDoubledSize <= 6 && report.counts.nonAdjustmentFailures === 0
    ) ||
    scaling.maximumConcurrency !== 3 || profile.model !== "Luna Max" || profile.serviceTier !== "fast" ||
    profile.maximumConcurrency !== 3 || profile.timeoutSeconds !== 600 || profile.concurrencyIncreaseEligible !== false ||
    report.gates.explicitReverseKeywordClassified !== true || report.gates.executionProfileBound !== true
  ) {
    throw new reviewBuild.ReviewError("feedback calibration v3 扩容或执行配置不闭合");
  }
  return records.length;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.output || !options.batchId || (!options.reviewBatch && !options.check)) {
    process.stdout.write("用法：node tools/portrait-pilot/build-feedback-calibration-v3.js --review-batch <verified review batch> --output <fresh batch> --batch-id <ascii id> [--guidance-batch <verified guidance batch>] [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(options.batchId)) {
    throw new reviewBuild.ReviewError("batch id 非法");
  }
  const outputRoot = ensurePilotChild(options.output, "输出目录", options.check);
  const reportPath = path.join(outputRoot, "human-feedback-calibration.json");
  if (options.check) {
    const report = readJson(reportPath, "feedback calibration v3");
    if (report.batchId !== options.batchId) throw new reviewBuild.ReviewError("check batch-id 与 report 不一致");
    const artifactCount = verifyReport(report);
    process.stdout.write(`${JSON.stringify({
      status: "human_feedback_calibration_v3_verified",
      feedbackDigest: report.feedbackDigest,
      counts: report.counts,
      geometryCalibration: report.geometryCalibration,
      adaptiveScaling: report.adaptiveScaling,
      artifactCount,
    })}\n`);
    return;
  }
  const report = buildReport(options);
  fs.mkdirSync(outputRoot, { recursive: false });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  const artifactCount = verifyReport(report);
  process.stdout.write(`${JSON.stringify({
    status: "human_feedback_calibrated_v3",
    path: path.relative(ROOT, reportPath).replaceAll("\\", "/"),
    feedbackDigest: report.feedbackDigest,
    counts: report.counts,
    geometryCalibration: report.geometryCalibration,
    adaptiveScaling: report.adaptiveScaling,
    artifactCount,
  })}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = { buildReport, verifyReport };
