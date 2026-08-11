#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const historicalV6 = require("./build-feedback-calibration-v6");
const currentV3 = require("./build-feedback-calibration-v3");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const SCHEMA = "cf7.portrait-pilot-human-feedback-calibration.v7";

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

function batches(report) {
  return (report.runs || []).flatMap((run) => run.batches || []);
}

function attempts(report) {
  return batches(report).flatMap((batch) => batch.attempts || []);
}

function cleanProcessEvidence(attempt) {
  return attempt.exitCode === 0 && attempt.timedOut === false &&
    (attempt.normalExitOrphanPids || []).length === 0 && (attempt.survivorPids || []).length === 0;
}

function verifySelectionEvidence(filePath) {
  const report = readJson(filePath, "selection Fast6 evidence");
  verifyDigest(report, "reportDigest", "selection Fast6 evidence");
  const allBatches = batches(report);
  const allAttempts = attempts(report);
  if (
    report.schema !== "cf7.portrait-pilot-feature-model-report.v1" || report.status !== "candidate_proposed" ||
    report.productionReady !== false || report.selectionMode !== "semantic_feature" ||
    report.controller?.version !== "portrait-pilot-selection-v1-first-answer-candidate-only" ||
    report.input?.scheduling?.maxConcurrency !== 6 || report.input?.scheduling?.serviceTier !== "fast" ||
    report.input?.scheduling?.independentRunCount !== 8 || allBatches.length !== 8 || allAttempts.length !== 8 ||
    allBatches.some((batch) => batch.status !== "accepted" || batch.attempts?.length !== 1) ||
    allAttempts.some((attempt) => !cleanProcessEvidence(attempt))
  ) throw new reviewBuild.ReviewError("selection Fast6 evidence 未证明 8/8 首答、exit 0 和零残留");
  return report;
}

function verifyLocalizationFailure(filePath) {
  const report = readJson(filePath, "localization Fast6 failure");
  verifyDigest(report, "reportDigest", "localization Fast6 failure");
  const failed = report.failedRun || {};
  const serialized = JSON.stringify(failed);
  if (
    report.schema !== "cf7.portrait-pilot-model-failure-report.v1" || report.status !== "model_run_failed" ||
    report.productionReady !== false || failed.error?.code !== "RUN_RETRIES_EXHAUSTED" ||
    !serialized.includes("RESULT_FEATURE_TOO_SMALL") ||
    !serialized.includes("Falling back from WebSockets to HTTPS") ||
    report.gates?.failurePersisted !== true || report.gates?.partialSuccessNotPromoted !== true ||
    report.gates?.humanReviewOpened !== false || report.gates?.productionWrites !== false
  ) throw new reviewBuild.ReviewError("localization Fast6 failure 未闭合质量/传输回退证据");
  return report;
}

function verifyLocalizationSuccess(filePath) {
  const report = readJson(filePath, "localization Fast3 success");
  verifyDigest(report, "reportDigest", "localization Fast3 success");
  const allBatches = batches(report);
  const allAttempts = attempts(report);
  if (
    report.schema !== "cf7.portrait-pilot-feature-model-report.v1" || report.status !== "candidate_proposed" ||
    report.productionReady !== false || report.input?.scheduling?.maxConcurrency !== 3 ||
    report.input?.scheduling?.serviceTier !== "fast" || report.input?.scheduling?.independentRunCount !== 8 ||
    allBatches.length !== 8 || allAttempts.length !== 11 || allBatches.some((batch) => batch.status !== "accepted") ||
    allAttempts.some((attempt) => !cleanProcessEvidence(attempt)) ||
    report.counts?.candidateAgreement !== 13 || report.counts?.orientationAgreement !== 13
  ) throw new reviewBuild.ReviewError("localization Fast3 success 未闭合 8 作业/11 attempt/13 行一致性");
  return report;
}

function verifyGuidedRender(filePath) {
  const report = readJson(filePath, "latest guided render");
  verifyDigest(report, "reportDigest", "latest guided render");
  if (
    report.schema !== "cf7.portrait-pilot-human-framing-render-report.v1" ||
    report.status !== "human_guided_automated_checked" || report.productionReady !== false ||
    !Array.isArray(report.rows) || report.rows.length !== 1 || report.gates?.modelRerun !== false ||
    report.gates?.productionWrites !== false
  ) throw new reviewBuild.ReviewError("latest guided render 未证明单行无模型重跑");
  return report;
}

function mergeGeometry(historical, current) {
  const rows = new Map();
  for (const row of historical.geometryCalibration?.rows || []) rows.set(row.reviewKey, JSON.parse(JSON.stringify(row)));
  for (const row of current.geometryCalibration?.rows || []) rows.set(row.reviewKey, JSON.parse(JSON.stringify(row)));
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
  const selectionPath = path.resolve(ROOT, options.selectionEvidence);
  const failurePath = path.resolve(ROOT, options.localizationFailure);
  const successPath = path.resolve(ROOT, options.localizationSuccess);
  const guidedPath = path.resolve(ROOT, options.guidedRender);
  const historical = readJson(historicalPath, "historical feedback v6");
  const current = readJson(currentPath, "current feedback v3");
  historicalV6.verifyReport(historical);
  currentV3.verifyReport(current);
  const selection = verifySelectionEvidence(selectionPath);
  const failure = verifyLocalizationFailure(failurePath);
  const success = verifyLocalizationSuccess(successPath);
  verifyGuidedRender(guidedPath);
  if (historical.geometryCalibration?.cumulativeRowCount !== 105 || current.geometryCalibration?.rows?.length !== 1) {
    throw new reviewBuild.ReviewError("v7 geometry parent 必须闭合为 105 + 1")
  }
  const geometryRows = mergeGeometry(historical, current);
  if (geometryRows.length !== 106) throw new reviewBuild.ReviewError("v7 geometry 去重后必须为 106 条");
  const zooms = geometryRows.map((row) => row.zoomIn);
  const report = JSON.parse(JSON.stringify(current));
  report.schema = SCHEMA;
  report.batchId = options.batchId;
  report.generatedAt = new Date().toISOString();
  report.inputs.currentControllerSource = report.inputs.controllerSource;
  report.inputs.controllerSource = artifact(__filename);
  report.inputs.historicalFeedbackReport = artifact(historicalPath);
  report.inputs.currentFeedbackReport = artifact(currentPath);
  report.inputs.selectionFast6Evidence = artifact(selectionPath);
  report.inputs.localizationFast6Failure = artifact(failurePath);
  report.inputs.localizationFast3Success = artifact(successPath);
  report.inputs.latestGuidedRender = artifact(guidedPath);
  report.geometryCalibration = {
    guidanceBatchCount: Number(historical.geometryCalibration.guidanceBatchCount || 0) + 1,
    historicalRowCount: 105,
    currentRowCount: 1,
    cumulativeRowCount: 106,
    rows: geometryRows,
    medianZoomIn: rounded(median(zooms)),
    minimumZoomIn: rounded(Math.min(...zooms)),
    maximumZoomIn: rounded(Math.max(...zooms)),
    mergePolicy: "review_key_latest_current_wins_without_dropping_disjoint_history",
  };
  const failureRate = report.counts.adjustments / report.counts.eligible;
  const futureCeiling = 48;
  report.adaptiveScaling = {
    expectedRevisionBudget: 6,
    humanReviewPageLimit: null,
    reviewConsolidationPolicy: "single_page_preferred",
    currentShardSize: report.counts.eligible,
    observedFirstPassRate: rounded(report.counts.passed / report.counts.eligible),
    estimatedFailureRate: rounded(failureRate),
    futureIdentityCeiling: futureCeiling,
    expectedRevisionsAtFutureCeiling: rounded(futureCeiling * failureRate),
    futureCeilingEligibleByEstimate: futureCeiling * failureRate <= 6 && report.counts.nonAdjustmentFailures === 0,
    recommendedNextShardSize: futureCeiling,
    recommendedSourceGroups: 12,
    modelItemsPerGroup: 4,
    serviceTier: "fast",
    timeoutSeconds: 600,
    concurrencyPolicy: "stage_specific_fast6_selection_fast3_localization_v1",
    selectionExecutionProfile: {
      model: "Luna Max",
      serviceTier: "fast",
      maximumConcurrency: 6,
      timeoutSeconds: 600,
      evidenceReportDigest: selection.reportDigest,
      firstAnswerJobs: 8,
    },
    localizationExecutionProfile: {
      model: "Luna Max",
      serviceTier: "fast",
      maximumConcurrency: 3,
      timeoutSeconds: 600,
      failedFast6ReportDigest: failure.reportDigest,
      successfulFast3ReportDigest: success.reportDigest,
      successfulJobs: 8,
      successfulAttempts: 11,
    },
    maximumConcurrencyIsStageSpecific: true,
    concurrencyEightAuthorized: false,
  };
  report.gates.allHistoricalGeometryRowsBound = true;
  report.gates.currentGeometryRowsBound = true;
  report.gates.cumulativeGeometryDeduplicated = true;
  report.gates.selectionFast6StrictlyVerified = true;
  report.gates.localizationFast6Rejected = true;
  report.gates.localizationFast3StrictlyVerified = true;
  report.gates.stageSpecificConcurrencyRequired = true;
  report.gates.concurrencyEightNotAuthorized = true;
  report.gates.latestGuidedRenderBound = true;
  delete report.feedbackDigest;
  report.feedbackDigest = sha256Bytes(reviewBuild.stableStringify(report));
  return report;
}

function verifyReport(report) {
  if (report.schema !== SCHEMA || report.status !== "human_feedback_calibrated" || report.productionReady !== false) {
    throw new reviewBuild.ReviewError("feedback calibration v7 schema 或状态非法");
  }
  verifyDigest(report, "feedbackDigest", "feedback calibration v7");
  const historicalPath = reviewBuild.resolveRepoArtifact(report.inputs.historicalFeedbackReport, "v7 historical feedback");
  const currentPath = reviewBuild.resolveRepoArtifact(report.inputs.currentFeedbackReport, "v7 current feedback");
  const selectionPath = reviewBuild.resolveRepoArtifact(report.inputs.selectionFast6Evidence, "v7 selection evidence");
  const failurePath = reviewBuild.resolveRepoArtifact(report.inputs.localizationFast6Failure, "v7 localization failure");
  const successPath = reviewBuild.resolveRepoArtifact(report.inputs.localizationFast3Success, "v7 localization success");
  const guidedPath = reviewBuild.resolveRepoArtifact(report.inputs.latestGuidedRender, "v7 guided render");
  reviewBuild.resolveRepoArtifact(report.inputs.controllerSource, "v7 controller");
  reviewBuild.resolveRepoArtifact(report.inputs.currentControllerSource, "v7 current controller");
  const historical = readJson(historicalPath, "v7 historical feedback");
  const current = readJson(currentPath, "v7 current feedback");
  historicalV6.verifyReport(historical);
  currentV3.verifyReport(current);
  const selection = verifySelectionEvidence(selectionPath);
  const failure = verifyLocalizationFailure(failurePath);
  const success = verifyLocalizationSuccess(successPath);
  verifyGuidedRender(guidedPath);
  const expectedRows = mergeGeometry(historical, current);
  const geometry = report.geometryCalibration;
  const scaling = report.adaptiveScaling;
  if (
    geometry.historicalRowCount !== 105 || geometry.currentRowCount !== 1 || geometry.cumulativeRowCount !== 106 ||
    reviewBuild.stableStringify(geometry.rows) !== reviewBuild.stableStringify(expectedRows) ||
    scaling.currentShardSize !== 13 || scaling.observedFirstPassRate !== 0.923077 ||
    scaling.estimatedFailureRate !== 0.076923 || scaling.futureIdentityCeiling !== 48 ||
    scaling.expectedRevisionsAtFutureCeiling !== 3.692308 || scaling.futureCeilingEligibleByEstimate !== true ||
    scaling.recommendedNextShardSize !== 48 || scaling.recommendedSourceGroups !== 12 ||
    scaling.concurrencyPolicy !== "stage_specific_fast6_selection_fast3_localization_v1" ||
    scaling.selectionExecutionProfile?.maximumConcurrency !== 6 ||
    scaling.selectionExecutionProfile?.evidenceReportDigest !== selection.reportDigest ||
    scaling.localizationExecutionProfile?.maximumConcurrency !== 3 ||
    scaling.localizationExecutionProfile?.failedFast6ReportDigest !== failure.reportDigest ||
    scaling.localizationExecutionProfile?.successfulFast3ReportDigest !== success.reportDigest ||
    scaling.maximumConcurrencyIsStageSpecific !== true || scaling.concurrencyEightAuthorized !== false ||
    report.gates?.allHistoricalGeometryRowsBound !== true || report.gates?.currentGeometryRowsBound !== true ||
    report.gates?.cumulativeGeometryDeduplicated !== true || report.gates?.selectionFast6StrictlyVerified !== true ||
    report.gates?.localizationFast6Rejected !== true || report.gates?.localizationFast3StrictlyVerified !== true ||
    report.gates?.stageSpecificConcurrencyRequired !== true || report.gates?.concurrencyEightNotAuthorized !== true ||
    report.gates?.latestGuidedRenderBound !== true
  ) throw new reviewBuild.ReviewError("feedback calibration v7 几何/扩容/分阶段并发闭包非法");
  return 10;
}

function parseArgs(argv) {
  const options = {
    historicalFeedback: null, currentFeedback: null, selectionEvidence: null,
    localizationFailure: null, localizationSuccess: null, guidedRender: null,
    output: null, batchId: null, check: false, help: false,
  };
  const fields = {
    "--historical-feedback": "historicalFeedback",
    "--current-feedback": "currentFeedback",
    "--selection-evidence": "selectionEvidence",
    "--localization-failure": "localizationFailure",
    "--localization-success": "localizationSuccess",
    "--guided-render": "guidedRender",
    "--output": "output",
    "--batch-id": "batchId",
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (fields[argument]) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new reviewBuild.ReviewError(`${argument} 缺少值`);
      options[fields[argument]] = value;
      index += 1;
    } else if (argument === "--check") options.check = true;
    else if (argument === "--help") options.help = true;
    else throw new reviewBuild.ReviewError(`未知参数：${argument}`);
  }
  return options;
}

function ensureOutput(target, allowExisting) {
  const resolved = path.resolve(ROOT, target);
  const relative = path.relative(PILOT_ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) throw new reviewBuild.ReviewError("输出必须位于 tmp/portrait-pilot 下");
  if (!allowExisting && fs.existsSync(resolved)) throw new reviewBuild.ReviewError("输出已存在，禁止覆盖");
  return resolved;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const required = ["historicalFeedback", "currentFeedback", "selectionEvidence", "localizationFailure", "localizationSuccess", "guidedRender"];
  if (options.help || !options.output || !options.batchId || (!options.check && required.some((field) => !options[field]))) {
    process.stdout.write("用法：node tools/portrait-pilot/build-feedback-calibration-v7.js --historical-feedback <v6> --current-feedback <v3> --selection-evidence <json> --localization-failure <json> --localization-success <json> --guided-render <json> --output <fresh> --batch-id <ascii> [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(options.batchId)) throw new reviewBuild.ReviewError("batch id 非法");
  const outputRoot = ensureOutput(options.output, options.check);
  const reportPath = path.join(outputRoot, "human-feedback-calibration.json");
  if (options.check) {
    const report = readJson(reportPath, "feedback calibration v7");
    if (report.batchId !== options.batchId) throw new reviewBuild.ReviewError("check batch-id 与 report 不一致");
    const artifactCount = verifyReport(report);
    process.stdout.write(`${JSON.stringify({ status: "human_feedback_calibration_v7_verified", feedbackDigest: report.feedbackDigest, geometryRows: 106, firstPassRate: report.adaptiveScaling.observedFirstPassRate, selectionMaximumConcurrency: 6, localizationMaximumConcurrency: 3, artifactCount })}\n`);
    return;
  }
  const report = buildReport(options);
  fs.mkdirSync(outputRoot, { recursive: false });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  const artifactCount = verifyReport(report);
  process.stdout.write(`${JSON.stringify({ status: "human_feedback_calibrated_v7", path: path.relative(ROOT, reportPath).replaceAll("\\", "/"), feedbackDigest: report.feedbackDigest, geometryRows: 106, firstPassRate: report.adaptiveScaling.observedFirstPassRate, selectionMaximumConcurrency: 6, localizationMaximumConcurrency: 3, artifactCount })}\n`);
}

if (require.main === module) {
  try { main(); }
  catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = { buildReport, verifyReport };
