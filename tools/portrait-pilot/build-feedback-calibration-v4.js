#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const baseCalibration = require("./build-feedback-calibration-v3");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const SCHEMA = "cf7.portrait-pilot-human-feedback-calibration.v4";

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

function ensurePilotChild(target, label, allowExisting = false) {
  const resolved = path.resolve(ROOT, target);
  const relative = path.relative(PILOT_ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new reviewBuild.ReviewError(`${label} 必须位于 tmp/portrait-pilot 下`);
  }
  if (!allowExisting && fs.existsSync(resolved)) throw new reviewBuild.ReviewError(`${label} 已存在，禁止覆盖`);
  return resolved;
}

function readJson(filePath, label) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) throw new reviewBuild.ReviewError(`${label} 缺失`);
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    throw new reviewBuild.ReviewError(`${label} 不是合法 JSON：${error.message}`);
  }
}

function buildReport(options) {
  const report = baseCalibration.buildReport(options);
  const scaling = report.adaptiveScaling;
  const estimateEligibleToDouble = scaling.eligibleToDouble;
  const estimateRecommendedNextShardSize = scaling.recommendedNextShardSize;
  const estimateRecommendedSourceGroups = scaling.recommendedSourceGroups;
  report.schema = SCHEMA;
  report.inputs.v3ControllerSource = report.inputs.controllerSource;
  report.inputs.controllerSource = artifact(__filename);
  scaling.policy = "human_scale_directive_v1";
  scaling.expectedRevisionBudgetIsGate = false;
  scaling.expectedRevisionBudgetRole = "tracking_benchmark_only";
  scaling.eligibleToDoubleByEstimate = estimateEligibleToDouble;
  scaling.estimateRecommendedNextShardSize = estimateRecommendedNextShardSize;
  scaling.estimateRecommendedSourceGroups = estimateRecommendedSourceGroups;
  scaling.eligibleToDouble = true;
  scaling.recommendedNextShardSize = scaling.doubledShardSize;
  scaling.recommendedSourceGroups = scaling.doubledShardSize / 4;
  scaling.humanScaleOverride = {
    active: true,
    directive: "double_next_identity_batch",
    targetShardSize: scaling.doubledShardSize,
    targetSourceGroups: scaling.doubledShardSize / 4,
    reviewPageLimit: null,
    expectedRevisionBudgetBlocksScale: false,
    rationale: "Human review cost is dominated by round trips rather than a 6-vs-8 row page difference; use the estimate as telemetry while doubling identity throughput.",
  };
  report.gates.humanScaleDirectiveApplied = true;
  report.gates.revisionEstimateTelemetryOnly = true;
  report.gates.identityBatchDoublingIndependentFromModelConcurrency = true;
  report.feedbackDigest = undefined;
  delete report.feedbackDigest;
  report.feedbackDigest = sha256Bytes(reviewBuild.stableStringify(report));
  return report;
}

function reconstructV3(report) {
  const reconstructed = JSON.parse(JSON.stringify(report));
  reconstructed.schema = "cf7.portrait-pilot-human-feedback-calibration.v3";
  reconstructed.inputs.controllerSource = reconstructed.inputs.v3ControllerSource;
  delete reconstructed.inputs.v3ControllerSource;
  const scaling = reconstructed.adaptiveScaling;
  scaling.eligibleToDouble = scaling.eligibleToDoubleByEstimate;
  scaling.recommendedNextShardSize = scaling.estimateRecommendedNextShardSize;
  scaling.recommendedSourceGroups = scaling.estimateRecommendedSourceGroups;
  for (const field of [
    "policy",
    "expectedRevisionBudgetIsGate",
    "expectedRevisionBudgetRole",
    "eligibleToDoubleByEstimate",
    "estimateRecommendedNextShardSize",
    "estimateRecommendedSourceGroups",
    "humanScaleOverride",
  ]) delete scaling[field];
  delete reconstructed.gates.humanScaleDirectiveApplied;
  delete reconstructed.gates.revisionEstimateTelemetryOnly;
  delete reconstructed.gates.identityBatchDoublingIndependentFromModelConcurrency;
  delete reconstructed.feedbackDigest;
  reconstructed.feedbackDigest = sha256Bytes(reviewBuild.stableStringify(reconstructed));
  return reconstructed;
}

function verifyReport(report) {
  if (report.schema !== SCHEMA || report.status !== "human_feedback_calibrated" || report.productionReady !== false) {
    throw new reviewBuild.ReviewError("feedback calibration v4 schema 或状态非法");
  }
  const envelope = { ...report };
  delete envelope.feedbackDigest;
  if (sha256Bytes(reviewBuild.stableStringify(envelope)) !== report.feedbackDigest) {
    throw new reviewBuild.ReviewError("feedback calibration v4 digest 不匹配");
  }
  const artifactCount = baseCalibration.verifyReport(reconstructV3(report));
  reviewBuild.resolveRepoArtifact(report.inputs.v3ControllerSource, "feedback calibration v3 controller");
  reviewBuild.resolveRepoArtifact(report.inputs.controllerSource, "feedback calibration v4 controller");
  const scaling = report.adaptiveScaling;
  const directive = scaling.humanScaleOverride;
  if (
    scaling.policy !== "human_scale_directive_v1" ||
    scaling.expectedRevisionBudget !== 6 ||
    scaling.expectedRevisionBudgetIsGate !== false ||
    scaling.expectedRevisionBudgetRole !== "tracking_benchmark_only" ||
    scaling.humanReviewPageLimit !== null ||
    scaling.expectedRevisionsAtDoubledSize !== Number((scaling.doubledShardSize * scaling.estimatedFailureRate).toFixed(6)) ||
    scaling.recommendedNextShardSize !== scaling.currentShardSize * 2 ||
    scaling.recommendedNextShardSize !== scaling.doubledShardSize ||
    scaling.recommendedSourceGroups !== scaling.recommendedNextShardSize / 4 ||
    scaling.eligibleToDouble !== true ||
    directive?.active !== true ||
    directive.targetShardSize !== scaling.recommendedNextShardSize ||
    directive.targetSourceGroups !== scaling.recommendedSourceGroups ||
    directive.reviewPageLimit !== null ||
    directive.expectedRevisionBudgetBlocksScale !== false ||
    report.gates.humanScaleDirectiveApplied !== true ||
    report.gates.revisionEstimateTelemetryOnly !== true ||
    report.gates.identityBatchDoublingIndependentFromModelConcurrency !== true
  ) {
    throw new reviewBuild.ReviewError("feedback calibration v4 人类扩容指令不闭合");
  }
  return artifactCount + 2;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.output || !options.batchId || (!options.reviewBatch && !options.check)) {
    process.stdout.write("用法：node tools/portrait-pilot/build-feedback-calibration-v4.js --review-batch <verified review batch> --output <fresh batch> --batch-id <ascii id> [--guidance-batch <verified guidance batch>] [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(options.batchId)) throw new reviewBuild.ReviewError("batch id 非法");
  const outputRoot = ensurePilotChild(options.output, "输出目录", options.check);
  const reportPath = path.join(outputRoot, "human-feedback-calibration.json");
  if (options.check) {
    const report = readJson(reportPath, "feedback calibration v4");
    if (report.batchId !== options.batchId) throw new reviewBuild.ReviewError("check batch-id 与 report 不一致");
    const artifactCount = verifyReport(report);
    process.stdout.write(`${JSON.stringify({
      status: "human_feedback_calibration_v4_verified",
      feedbackDigest: report.feedbackDigest,
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
    status: "human_feedback_calibrated_v4",
    path: path.relative(ROOT, reportPath).replaceAll("\\", "/"),
    feedbackDigest: report.feedbackDigest,
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
