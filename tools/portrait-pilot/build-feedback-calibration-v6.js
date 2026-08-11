#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const v4 = require("./build-feedback-calibration-v4");
const v5 = require("./build-feedback-calibration-v5");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const SCHEMA = "cf7.portrait-pilot-human-feedback-calibration.v6";

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

function geometryRows(report) {
  const rows = report.geometryCalibration?.rows;
  if (!Array.isArray(rows)) throw new reviewBuild.ReviewError("feedback geometryCalibration.rows 缺失");
  return rows;
}

function cumulativeRows(historical, current) {
  const rows = new Map();
  for (const row of geometryRows(historical)) rows.set(row.reviewKey, JSON.parse(JSON.stringify(row)));
  for (const row of geometryRows(current)) rows.set(row.reviewKey, JSON.parse(JSON.stringify(row)));
  return [...rows.values()].sort((left, right) => left.reviewKey.localeCompare(right.reviewKey, "zh-CN"));
}

function median(values) {
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function rounded(value) {
  return Number(value.toFixed(6));
}

function buildReport(options) {
  const historicalPath = path.resolve(ROOT, options.historicalFeedback);
  const currentPath = path.resolve(ROOT, options.currentFeedback);
  const historical = readJson(historicalPath, "历史 feedback v4");
  const current = readJson(currentPath, "当前 feedback v5");
  v4.verifyReport(historical);
  v5.verifyReport(current);
  const rows = cumulativeRows(historical, current);
  const zooms = rows.map((row) => row.zoomIn);
  if (geometryRows(historical).length !== 99 || geometryRows(current).length !== 6 || rows.length !== 105) {
    throw new reviewBuild.ReviewError("累计 geometry 必须闭合为 99 + 6 = 105 条唯一偏好");
  }
  const report = JSON.parse(JSON.stringify(current));
  report.schema = SCHEMA;
  report.batchId = options.batchId;
  report.generatedAt = new Date().toISOString();
  report.inputs.v5ControllerSource = report.inputs.controllerSource;
  report.inputs.controllerSource = artifact(__filename);
  report.inputs.historicalFeedbackReport = artifact(historicalPath);
  report.inputs.currentFeedbackReport = artifact(currentPath);
  report.inputs.historicalControllerSource = artifact(path.resolve(ROOT, historical.inputs.controllerSource.path));
  report.geometryCalibration = {
    guidanceBatchCount: Number(historical.geometryCalibration.guidanceBatchCount || 0) + Number(current.geometryCalibration.guidanceBatchCount || 0),
    historicalRowCount: geometryRows(historical).length,
    currentRowCount: geometryRows(current).length,
    cumulativeRowCount: rows.length,
    rows,
    medianZoomIn: rounded(median(zooms)),
    minimumZoomIn: rounded(Math.min(...zooms)),
    maximumZoomIn: rounded(Math.max(...zooms)),
    mergePolicy: "review_key_latest_current_wins_without_dropping_disjoint_history",
  };
  report.gates.allHistoricalGeometryRowsBound = true;
  report.gates.currentGeometryRowsBound = true;
  report.gates.cumulativeGeometryDeduplicated = true;
  report.gates.controlledFast6ExecutionInherited = true;
  delete report.feedbackDigest;
  report.feedbackDigest = sha256Bytes(reviewBuild.stableStringify(report));
  return report;
}

function verifyReport(report) {
  if (report.schema !== SCHEMA || report.status !== "human_feedback_calibrated" || report.productionReady !== false) {
    throw new reviewBuild.ReviewError("feedback calibration v6 schema 或状态非法");
  }
  verifyDigest(report, "feedbackDigest", "feedback calibration v6");
  reviewBuild.resolveRepoArtifact(report.inputs.controllerSource, "feedback v6 controller");
  reviewBuild.resolveRepoArtifact(report.inputs.v5ControllerSource, "feedback v5 controller");
  reviewBuild.resolveRepoArtifact(report.inputs.historicalControllerSource, "historical feedback controller");
  const historicalPath = reviewBuild.resolveRepoArtifact(report.inputs.historicalFeedbackReport, "historical feedback report");
  const currentPath = reviewBuild.resolveRepoArtifact(report.inputs.currentFeedbackReport, "current feedback report");
  const historical = readJson(historicalPath, "historical feedback report");
  const current = readJson(currentPath, "current feedback report");
  v4.verifyReport(historical);
  v5.verifyReport(current);
  const expectedRows = cumulativeRows(historical, current);
  const geometry = report.geometryCalibration;
  const scaling = report.adaptiveScaling;
  const profile = scaling?.executionProfile;
  const pilot = scaling?.concurrencyPilot;
  if (
    geometry.historicalRowCount !== 99 || geometry.currentRowCount !== 6 || geometry.cumulativeRowCount !== 105 ||
    reviewBuild.stableStringify(geometry.rows) !== reviewBuild.stableStringify(expectedRows) ||
    geometry.mergePolicy !== "review_key_latest_current_wins_without_dropping_disjoint_history" ||
    scaling.recommendedNextShardSize !== 48 || scaling.recommendedSourceGroups !== 12 || scaling.maximumConcurrency !== 6 ||
    profile?.model !== "Luna Max" || profile.serviceTier !== "fast" || profile.maximumConcurrency !== 6 ||
    profile.timeoutSeconds !== 600 || profile.fallbackMaximumConcurrency !== 3 ||
    pilot?.policy !== "bounded_fast6_with_fail_closed_fallback_v1" || pilot.qualityGatesUnchanged !== true ||
    report.gates?.allHistoricalGeometryRowsBound !== true || report.gates.currentGeometryRowsBound !== true ||
    report.gates.cumulativeGeometryDeduplicated !== true || report.gates.controlledFast6ExecutionInherited !== true
  ) throw new reviewBuild.ReviewError("feedback calibration v6 累计偏好或 Fast6 闭包非法");
  return 8;
}

function parseArgs(argv) {
  const options = { historicalFeedback: null, currentFeedback: null, output: null, batchId: null, check: false, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--historical-feedback", "--current-feedback", "--output", "--batch-id"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new reviewBuild.ReviewError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--historical-feedback") options.historicalFeedback = value;
      else if (argument === "--current-feedback") options.currentFeedback = value;
      else if (argument === "--output") options.output = value;
      else options.batchId = value;
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
  if (options.help || !options.output || !options.batchId || (!options.check && (!options.historicalFeedback || !options.currentFeedback))) {
    process.stdout.write("用法：node tools/portrait-pilot/build-feedback-calibration-v6.js --historical-feedback <r115 v4> --current-feedback <r139 v5> --output <fresh batch> --batch-id <ascii id> [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(options.batchId)) throw new reviewBuild.ReviewError("batch id 非法");
  const outputRoot = ensurePilotChild(options.output, options.check);
  const reportPath = path.join(outputRoot, "human-feedback-calibration.json");
  if (options.check) {
    const report = readJson(reportPath, "feedback calibration v6");
    if (report.batchId !== options.batchId) throw new reviewBuild.ReviewError("check batch-id 与 report 不一致");
    const artifactCount = verifyReport(report);
    process.stdout.write(`${JSON.stringify({ status: "human_feedback_calibration_v6_verified", feedbackDigest: report.feedbackDigest, geometryRows: report.geometryCalibration.cumulativeRowCount, maximumConcurrency: 6, fallbackMaximumConcurrency: 3, artifactCount })}\n`);
    return;
  }
  const report = buildReport(options);
  fs.mkdirSync(outputRoot, { recursive: false });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  const artifactCount = verifyReport(report);
  process.stdout.write(`${JSON.stringify({ status: "human_feedback_calibrated_v6", path: path.relative(ROOT, reportPath).replaceAll("\\", "/"), feedbackDigest: report.feedbackDigest, geometryRows: report.geometryCalibration.cumulativeRowCount, maximumConcurrency: 6, fallbackMaximumConcurrency: 3, artifactCount })}\n`);
}

if (require.main === module) {
  try { main(); } catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = { buildReport, verifyReport };
