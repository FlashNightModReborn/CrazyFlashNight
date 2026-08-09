#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const reviewVerify = require("./verify-review-decisions");
const parentV7 = require("./build-feedback-calibration-v7");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const CONTROLLER = __filename;
const SCHEMA = "cf7.portrait-pilot-human-feedback-calibration.v8";

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function readJson(filePath, label) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    throw new reviewBuild.ReviewError(`${label} 缺失：${filePath}`);
  }
  try { return JSON.parse(fs.readFileSync(filePath, "utf8")); }
  catch (error) { throw new reviewBuild.ReviewError(`${label} 不是合法 JSON：${error.message}`); }
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

function artifactPath(record, label) {
  if (!record || typeof record.path !== "string" || typeof record.sha256 !== "string" || !Number.isInteger(record.bytes)) {
    throw new reviewBuild.ReviewError(`${label} artifact record 非法`);
  }
  const resolved = path.resolve(ROOT, record.path);
  if (path.relative(ROOT, resolved).startsWith("..") || !fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    throw new reviewBuild.ReviewError(`${label} artifact 缺失或越界`);
  }
  const current = artifact(resolved);
  if (reviewBuild.stableStringify(current) !== reviewBuild.stableStringify(record)) {
    throw new reviewBuild.ReviewError(`${label} artifact hash/size 漂移`);
  }
  return resolved;
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

function cleanAttempt(attempt) {
  return attempt.exitCode === 0 && attempt.timedOut === false &&
    (attempt.normalExitOrphanPids || []).length === 0 && (attempt.survivorPids || []).length === 0;
}

function verifyStageReport(filePath, stage) {
  const report = readJson(filePath, `${stage} report`);
  verifyDigest(report, "reportDigest", `${stage} report`);
  const allBatches = batches(report);
  const allAttempts = attempts(report);
  const expectedConcurrency = stage === "selection" ? 6 : 3;
  if (
    report.schema !== "cf7.portrait-pilot-feature-model-report.v1" || report.status !== "candidate_proposed" ||
    report.productionReady !== false || report.input?.scheduling?.maxConcurrency !== expectedConcurrency ||
    report.input?.scheduling?.serviceTier !== "fast" || report.input?.scheduling?.independentRunCount !== 4 ||
    allBatches.length !== 4 || allAttempts.length !== 4 ||
    allBatches.some((batch) => batch.status !== "accepted" || batch.attempts?.length !== 1) ||
    allAttempts.some((attempt) => !cleanAttempt(attempt))
  ) throw new reviewBuild.ReviewError(`${stage} report 未证明 Fast${expectedConcurrency} 4/4 首答与零残留`);
  if (stage === "selection") {
    if (report.selectionMode !== "semantic_feature" || report.counts?.candidateAgreement !== 3) {
      throw new reviewBuild.ReviewError("selection report 候选一致性证据漂移");
    }
  } else if (report.counts?.candidateAgreement !== 5 || report.counts?.orientationAgreement !== 5) {
    throw new reviewBuild.ReviewError("localization report 未证明 5/5 候选与方向一致");
  }
  return report;
}

function loadReview(batchPath) {
  const batch = path.resolve(ROOT, batchPath);
  const relative = path.relative(PILOT_ROOT, batch);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative) || !fs.statSync(batch).isDirectory()) {
    throw new reviewBuild.ReviewError("review batch 必须位于 tmp/portrait-pilot");
  }
  const reviewPath = path.join(batch, "review-data.json");
  const decisionsPath = path.join(batch, "portrait-pilot-review-decisions.json");
  const receiptPath = path.join(batch, "human-review-receipt.json");
  const review = readJson(reviewPath, "review data");
  const decisions = readJson(decisionsPath, "review decisions");
  const receipt = readJson(receiptPath, "human review receipt");
  const validation = reviewVerify.validateDecisions(review, decisions);
  reviewVerify.verifyReceipt(receipt, {
    sourceDigest: review.sourceDigest,
    reviewDigest: review.reviewDigest,
    decisionsSha256: reviewBuild.sha256File(decisionsPath),
    reviewDataSha256: reviewBuild.sha256File(reviewPath),
  });
  if (
    review.productionReady !== false || review.items?.length !== 5 || validation.eligibleTotal !== 5 ||
    validation.eligiblePassed !== 5 || validation.refinementRequired !== false ||
    receipt.status !== "human_reviewed_approved" || receipt.productionReady !== false ||
    receipt.counts?.statuses?.pass !== 5 || receipt.counts?.statuses?.adjustment !== 0 ||
    receipt.gates?.artAcceptance !== true || receipt.gates?.productionWrites !== false
  ) throw new reviewBuild.ReviewError("当前 5 行人审未闭合为 5/5 pass");
  return { batch, reviewPath, decisionsPath, receiptPath, review, decisions, receipt, validation };
}

function buildReport(options) {
  const parentPath = path.resolve(ROOT, options.parentFeedback);
  const selectionPath = path.resolve(ROOT, options.selectionEvidence);
  const localizationPath = path.resolve(ROOT, options.localizationEvidence);
  const parent = readJson(parentPath, "parent feedback v7");
  parentV7.verifyReport(parent);
  const current = loadReview(options.reviewBatch);
  const selection = verifyStageReport(selectionPath, "selection");
  const localization = verifyStageReport(localizationPath, "localization");
  const currentRows = current.validation.rows.map((row) => ({
    ...row,
    feedbackCategories: [],
    route: "accepted",
  }));
  const rollingEligible = Number(parent.counts?.eligible) + current.validation.eligibleTotal;
  const rollingPassed = Number(parent.counts?.passed) + current.validation.eligiblePassed;
  const rollingFailures = rollingEligible - rollingPassed;
  if (rollingEligible !== 18 || rollingPassed !== 17 || rollingFailures !== 1) {
    throw new reviewBuild.ReviewError("滚动 18 行通过率输入漂移");
  }
  const rollingFailureRate = rollingFailures / rollingEligible;
  const previousSize = Number(parent.adaptiveScaling?.recommendedNextShardSize);
  const identityCeiling = Math.floor(6 / rollingFailureRate);
  const nextSize = Math.min(previousSize * 2, identityCeiling);
  const geometry = JSON.parse(JSON.stringify(parent.geometryCalibration));
  geometry.historicalRowCount = geometry.cumulativeRowCount;
  geometry.currentRowCount = 0;
  geometry.cumulativeRowCount = 106;
  geometry.latestHumanGuidance = null;
  const adaptive = JSON.parse(JSON.stringify(parent.adaptiveScaling));
  adaptive.currentShardSize = 5;
  adaptive.observedFirstPassRate = 1;
  adaptive.estimatedFailureRate = 0;
  adaptive.rollingWindow = {
    eligible: rollingEligible,
    passed: rollingPassed,
    failures: rollingFailures,
    firstPassRate: Number((rollingPassed / rollingEligible).toFixed(6)),
    failureRate: Number(rollingFailureRate.toFixed(6)),
  };
  adaptive.futureIdentityCeiling = identityCeiling;
  adaptive.expectedRevisionsAtFutureCeiling = 6;
  adaptive.futureCeilingEligibleByEstimate = true;
  adaptive.recommendedNextShardSize = nextSize;
  adaptive.recommendedSourceGroups = Math.ceil(nextSize / adaptive.modelItemsPerGroup);
  adaptive.expectedRevisionsAtRecommendedNextShardSize = Number((nextSize * rollingFailureRate).toFixed(6));
  adaptive.selectionExecutionProfile.evidenceReportDigest = selection.reportDigest;
  adaptive.selectionExecutionProfile.firstAnswerJobs = 4;
  adaptive.localizationExecutionProfile.successfulFast3ReportDigest = localization.reportDigest;
  adaptive.localizationExecutionProfile.successfulJobs = 4;
  adaptive.localizationExecutionProfile.successfulAttempts = 4;
  const report = {
    schema: SCHEMA,
    status: "human_feedback_calibrated",
    productionReady: false,
    generatedAt: new Date().toISOString(),
    batchId: options.batchId,
    inputs: {
      controllerSource: artifact(CONTROLLER),
      parentFeedbackReport: artifact(parentPath),
      reviewData: artifact(current.reviewPath),
      decisions: artifact(current.decisionsPath),
      humanReviewReceipt: artifact(current.receiptPath),
      selectionFast6Evidence: artifact(selectionPath),
      localizationFast3Evidence: artifact(localizationPath),
    },
    parent: {
      batchId: parent.batchId,
      feedbackDigest: parent.feedbackDigest,
      geometryRows: parent.geometryCalibration.cumulativeRowCount,
    },
    counts: {
      eligible: 5,
      passed: 5,
      adjustments: 0,
      nonAdjustmentFailures: 0,
      categoryCounts: {},
      preferredIndependentReview: 0,
      preferredProposal: 0,
    },
    rows: currentRows,
    geometryCalibration: geometry,
    adaptiveScaling: adaptive,
    gates: {
      exactHumanReceiptBound: true,
      rawNotesPreserved: true,
      deterministicFeedbackCategories: true,
      geometryOnlyFromVerifiedGuidance: true,
      noAutomaticArtAcceptance: true,
      noModelTrainingClaim: true,
      productionWrites: false,
      allParentGeometryRowsBound: true,
      currentGeometryRowsAbsentBecauseAllPass: true,
      cumulativeGeometryCountUnchanged: true,
      currentFivePassBound: true,
      rollingEighteenBound: true,
      nextBatchDoubledWithinRevisionBudget: nextSize === 96 && nextSize * rollingFailureRate <= 6,
      selectionFast6StrictlyVerified: true,
      localizationFast3StrictlyVerified: true,
      stageSpecificConcurrencyRequired: true,
      concurrencyEightNotAuthorized: true,
    },
  };
  report.feedbackDigest = sha256Bytes(reviewBuild.stableStringify(report));
  return report;
}

function verifyReport(report) {
  verifyDigest(report, "feedbackDigest", "feedback calibration v8");
  if (report.schema !== SCHEMA || report.status !== "human_feedback_calibrated" || report.productionReady !== false) {
    throw new reviewBuild.ReviewError("feedback calibration v8 schema/status 非法");
  }
  const parentPath = artifactPath(report.inputs?.parentFeedbackReport, "parent feedback");
  const parent = readJson(parentPath, "parent feedback v7");
  parentV7.verifyReport(parent);
  const reviewPath = artifactPath(report.inputs?.reviewData, "review data");
  const decisionsPath = artifactPath(report.inputs?.decisions, "review decisions");
  const receiptPath = artifactPath(report.inputs?.humanReviewReceipt, "human review receipt");
  artifactPath(report.inputs?.controllerSource, "controller");
  const selectionPath = artifactPath(report.inputs?.selectionFast6Evidence, "selection Fast6 evidence");
  const localizationPath = artifactPath(report.inputs?.localizationFast3Evidence, "localization Fast3 evidence");
  const review = readJson(reviewPath, "review data");
  const decisions = readJson(decisionsPath, "review decisions");
  const receipt = readJson(receiptPath, "human review receipt");
  const validation = reviewVerify.validateDecisions(review, decisions);
  reviewVerify.verifyReceipt(receipt, {
    sourceDigest: review.sourceDigest,
    reviewDigest: review.reviewDigest,
    decisionsSha256: reviewBuild.sha256File(decisionsPath),
    reviewDataSha256: reviewBuild.sha256File(reviewPath),
  });
  verifyStageReport(selectionPath, "selection");
  verifyStageReport(localizationPath, "localization");
  if (
    validation.eligiblePassed !== 5 || report.counts?.eligible !== 5 || report.counts?.passed !== 5 ||
    report.rows?.length !== 5 || report.rows.some((row) => row.status !== "pass" || row.route !== "accepted") ||
    report.geometryCalibration?.historicalRowCount !== 106 || report.geometryCalibration?.currentRowCount !== 0 ||
    report.geometryCalibration?.cumulativeRowCount !== 106 || report.geometryCalibration?.rows?.length !== 106 ||
    report.adaptiveScaling?.rollingWindow?.eligible !== 18 || report.adaptiveScaling?.rollingWindow?.failures !== 1 ||
    report.adaptiveScaling?.recommendedNextShardSize !== 96 ||
    report.adaptiveScaling?.selectionExecutionProfile?.maximumConcurrency !== 6 ||
    report.adaptiveScaling?.localizationExecutionProfile?.maximumConcurrency !== 3 ||
    report.adaptiveScaling?.concurrencyEightAuthorized !== false ||
    Object.values(report.gates || {}).some((value) => value !== true && value !== false) ||
    report.gates?.currentFivePassBound !== true || report.gates?.nextBatchDoubledWithinRevisionBudget !== true ||
    report.gates?.productionWrites !== false
  ) throw new reviewBuild.ReviewError("feedback calibration v8 186-label/106-geometry/96 ceiling 闭包非法");
  return 7;
}

function parseArgs(argv) {
  const options = { check: false, help: false };
  const fields = {
    "--parent-feedback": "parentFeedback",
    "--review-batch": "reviewBatch",
    "--selection-evidence": "selectionEvidence",
    "--localization-evidence": "localizationEvidence",
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

function outputRoot(value, allowExisting) {
  const resolved = path.resolve(ROOT, value);
  const relative = path.relative(PILOT_ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new reviewBuild.ReviewError("输出必须位于 tmp/portrait-pilot 下");
  }
  if (!allowExisting && fs.existsSync(resolved)) throw new reviewBuild.ReviewError("输出已存在，禁止覆盖");
  return resolved;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const required = ["parentFeedback", "reviewBatch", "selectionEvidence", "localizationEvidence"];
  if (options.help || !options.output || !options.batchId || (!options.check && required.some((field) => !options[field]))) {
    process.stdout.write("用法：node tools/portrait-pilot/build-feedback-calibration-v8.js --parent-feedback <v7> --review-batch <5-pass batch> --selection-evidence <Fast6 report> --localization-evidence <Fast3 report> --output <fresh> --batch-id <ascii> [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(options.batchId)) throw new reviewBuild.ReviewError("batch id 非法");
  const output = outputRoot(options.output, options.check);
  const reportPath = path.join(output, "human-feedback-calibration.json");
  if (options.check) {
    const report = readJson(reportPath, "feedback calibration v8");
    if (report.batchId !== options.batchId) throw new reviewBuild.ReviewError("check batch-id 与 report 不一致");
    const artifactCount = verifyReport(report);
    process.stdout.write(`${JSON.stringify({ status: "human_feedback_calibration_v8_verified", feedbackDigest: report.feedbackDigest, humanLabels: 186, geometryRows: 106, recommendedNextShardSize: 96, selectionMaximumConcurrency: 6, localizationMaximumConcurrency: 3, artifactCount })}\n`);
    return;
  }
  const report = buildReport(options);
  fs.mkdirSync(output, { recursive: false });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  const artifactCount = verifyReport(report);
  process.stdout.write(`${JSON.stringify({ status: "human_feedback_calibrated_v8", path: path.relative(ROOT, reportPath).replaceAll("\\", "/"), feedbackDigest: report.feedbackDigest, humanLabels: 186, geometryRows: 106, recommendedNextShardSize: 96, selectionMaximumConcurrency: 6, localizationMaximumConcurrency: 3, artifactCount })}\n`);
}

if (require.main === module) {
  try { main(); }
  catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = { buildReport, verifyReport };
