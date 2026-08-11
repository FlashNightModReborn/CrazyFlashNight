#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const v4 = require("./build-feedback-calibration-v4");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const SCHEMA = "cf7.portrait-pilot-human-feedback-calibration.v5";

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function artifact(filePath) {
  const resolved = path.resolve(filePath);
  const relative = path.relative(ROOT, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative) || !fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    throw new reviewBuild.ReviewError(`artifact 越出仓库或缺失：${filePath}`);
  }
  return { path: relative.replaceAll("\\", "/"), bytes: fs.statSync(resolved).size, sha256: reviewBuild.sha256File(resolved) };
}

function readJson(filePath, label) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) throw new reviewBuild.ReviewError(`${label} 缺失`);
  try { return JSON.parse(fs.readFileSync(filePath, "utf8")); }
  catch (error) { throw new reviewBuild.ReviewError(`${label} 不是合法 JSON：${error.message}`); }
}

function verifyDigest(value, field, label) {
  const envelope = { ...value };
  const digest = envelope[field];
  delete envelope[field];
  if (typeof digest !== "string" || sha256Bytes(reviewBuild.stableStringify(envelope)) !== digest) {
    throw new reviewBuild.ReviewError(`${label} ${field} 不匹配`);
  }
}

function verifyConcurrencyEvidence(filePath) {
  const report = readJson(filePath, "Fast6 并发证据");
  verifyDigest(report, "reportDigest", "Fast6 并发证据");
  if (
    report.schema !== "cf7.portrait-pilot-feature-model-report.v1" || report.status !== "candidate_proposed" ||
    report.productionReady !== false || report.counts?.firstAttemptsConsumed !== 12 ||
    report.gates?.nonOccupancySchemaAndOrientationValidated !== true ||
    report.gates?.completeTurnEvidenceForEveryFirstAttempt !== true ||
    report.gates?.strictFeatureOccupancyAccepted !== false ||
    report.gates?.fullProcessExitAndOrphanEvidenceAvailable !== false
  ) throw new reviewBuild.ReviewError("Fast6 并发证据必须证明 12/12 首答闭合，同时保留质量/进程 false gate");
  return report;
}

function buildReport(options) {
  const report = v4.buildReport(options);
  const evidence = verifyConcurrencyEvidence(path.resolve(ROOT, options.concurrencyEvidence));
  const scaling = report.adaptiveScaling;
  const baselineExecutionProfile = JSON.parse(JSON.stringify(scaling.executionProfile));
  report.schema = SCHEMA;
  report.inputs.v4ControllerSource = report.inputs.controllerSource;
  report.inputs.controllerSource = artifact(__filename);
  report.inputs.concurrencyEvidence = artifact(path.resolve(ROOT, options.concurrencyEvidence));
  scaling.baselineExecutionProfile = baselineExecutionProfile;
  scaling.maximumConcurrency = 6;
  scaling.executionProfile = {
    model: "Luna Max",
    serviceTier: "fast",
    maximumConcurrency: 6,
    timeoutSeconds: 600,
    concurrencyIncreaseEligible: true,
    mode: "controlled_fast6_pilot_with_automatic_fallback",
    fallbackMaximumConcurrency: 3,
  };
  scaling.concurrencyPilot = {
    policy: "bounded_fast6_with_fail_closed_fallback_v1",
    baselineMaximumConcurrency: 3,
    targetMaximumConcurrency: 6,
    modelItemsPerGroup: 4,
    timeoutSeconds: 600,
    evidenceReportDigest: evidence.reportDigest,
    evidenceFirstAttempts: evidence.counts.firstAttemptsConsumed,
    evidenceStrictOccupancyAccepted: false,
    evidenceFullProcessExitAndOrphanAvailable: false,
    fallbackTriggers: ["http_429", "transport_failure", "timeout", "orphan_or_survivor", "first_answer_closure_regression"],
    qualityGatesUnchanged: true,
    rationale: "Recent failures were geometry/direction gates rather than quota transport; double process concurrency for the 48-identity shard while preserving an automatic Fast3 fallback.",
  };
  report.gates.controlledFast6PilotBound = true;
  report.gates.fast3FallbackBound = true;
  report.gates.modelBatchSizeUnchanged = true;
  delete report.feedbackDigest;
  report.feedbackDigest = sha256Bytes(reviewBuild.stableStringify(report));
  return report;
}

function reconstructV4(report) {
  const reconstructed = JSON.parse(JSON.stringify(report));
  reconstructed.schema = "cf7.portrait-pilot-human-feedback-calibration.v4";
  reconstructed.inputs.controllerSource = reconstructed.inputs.v4ControllerSource;
  delete reconstructed.inputs.v4ControllerSource;
  delete reconstructed.inputs.concurrencyEvidence;
  const scaling = reconstructed.adaptiveScaling;
  scaling.maximumConcurrency = scaling.baselineExecutionProfile.maximumConcurrency;
  scaling.executionProfile = scaling.baselineExecutionProfile;
  delete scaling.baselineExecutionProfile;
  delete scaling.concurrencyPilot;
  delete reconstructed.gates.controlledFast6PilotBound;
  delete reconstructed.gates.fast3FallbackBound;
  delete reconstructed.gates.modelBatchSizeUnchanged;
  delete reconstructed.feedbackDigest;
  reconstructed.feedbackDigest = sha256Bytes(reviewBuild.stableStringify(reconstructed));
  return reconstructed;
}

function verifyReport(report) {
  if (report.schema !== SCHEMA || report.status !== "human_feedback_calibrated" || report.productionReady !== false) {
    throw new reviewBuild.ReviewError("feedback calibration v5 schema 或状态非法");
  }
  verifyDigest(report, "feedbackDigest", "feedback calibration v5");
  const artifactCount = v4.verifyReport(reconstructV4(report));
  reviewBuild.resolveRepoArtifact(report.inputs.v4ControllerSource, "feedback calibration v4 controller");
  reviewBuild.resolveRepoArtifact(report.inputs.controllerSource, "feedback calibration v5 controller");
  const evidencePath = reviewBuild.resolveRepoArtifact(report.inputs.concurrencyEvidence, "Fast6 并发证据");
  const evidence = verifyConcurrencyEvidence(evidencePath);
  const scaling = report.adaptiveScaling;
  const profile = scaling.executionProfile;
  const pilot = scaling.concurrencyPilot;
  if (
    scaling.maximumConcurrency !== 6 || profile?.model !== "Luna Max" || profile.serviceTier !== "fast" ||
    profile.maximumConcurrency !== 6 || profile.timeoutSeconds !== 600 || profile.concurrencyIncreaseEligible !== true ||
    profile.mode !== "controlled_fast6_pilot_with_automatic_fallback" || profile.fallbackMaximumConcurrency !== 3 ||
    pilot?.policy !== "bounded_fast6_with_fail_closed_fallback_v1" || pilot.baselineMaximumConcurrency !== 3 ||
    pilot.targetMaximumConcurrency !== 6 || pilot.modelItemsPerGroup !== 4 || pilot.timeoutSeconds !== 600 ||
    pilot.evidenceReportDigest !== evidence.reportDigest || pilot.qualityGatesUnchanged !== true ||
    !Array.isArray(pilot.fallbackTriggers) || pilot.fallbackTriggers.length !== 5 ||
    report.gates.controlledFast6PilotBound !== true || report.gates.fast3FallbackBound !== true ||
    report.gates.modelBatchSizeUnchanged !== true
  ) throw new reviewBuild.ReviewError("feedback calibration v5 Fast6/fallback 配置不闭合");
  return artifactCount + 3;
}

function parseArgs(argv) {
  const options = { reviewBatch: null, guidanceBatches: [], output: null, batchId: null, concurrencyEvidence: null, check: false, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--review-batch", "--guidance-batch", "--output", "--batch-id", "--concurrency-evidence"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new reviewBuild.ReviewError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--review-batch") options.reviewBatch = value;
      else if (argument === "--guidance-batch") options.guidanceBatches.push(value);
      else if (argument === "--output") options.output = value;
      else if (argument === "--batch-id") options.batchId = value;
      else options.concurrencyEvidence = value;
    } else if (argument === "--check") options.check = true;
    else if (argument === "--help") options.help = true;
    else throw new reviewBuild.ReviewError(`未知参数：${argument}`);
  }
  return options;
}

function ensurePilotChild(target, allowExisting) {
  const resolved = path.resolve(ROOT, target);
  const relative = path.relative(PILOT_ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) throw new reviewBuild.ReviewError("输出必须位于 tmp/portrait-pilot 下");
  if (!allowExisting && fs.existsSync(resolved)) throw new reviewBuild.ReviewError("输出已存在，禁止覆盖");
  return resolved;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.output || !options.batchId || (!options.check && (!options.reviewBatch || !options.concurrencyEvidence))) {
    process.stdout.write("用法：node tools/portrait-pilot/build-feedback-calibration-v5.js --review-batch <verified review batch> --output <fresh batch> --batch-id <ascii id> --concurrency-evidence <r121 model report> [--guidance-batch <verified guidance batch>] [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(options.batchId)) throw new reviewBuild.ReviewError("batch id 非法");
  const outputRoot = ensurePilotChild(options.output, options.check);
  const reportPath = path.join(outputRoot, "human-feedback-calibration.json");
  if (options.check) {
    const report = readJson(reportPath, "feedback calibration v5");
    if (report.batchId !== options.batchId) throw new reviewBuild.ReviewError("check batch-id 与 report 不一致");
    const artifactCount = verifyReport(report);
    process.stdout.write(`${JSON.stringify({ status: "human_feedback_calibration_v5_verified", feedbackDigest: report.feedbackDigest, adaptiveScaling: report.adaptiveScaling, artifactCount })}\n`);
    return;
  }
  const report = buildReport(options);
  fs.mkdirSync(outputRoot, { recursive: false });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  const artifactCount = verifyReport(report);
  process.stdout.write(`${JSON.stringify({ status: "human_feedback_calibrated_v5", path: path.relative(ROOT, reportPath).replaceAll("\\", "/"), feedbackDigest: report.feedbackDigest, adaptiveScaling: report.adaptiveScaling, artifactCount })}\n`);
}

if (require.main === module) {
  try { main(); } catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = { buildReport, verifyReport };
