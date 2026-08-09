#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const decisionVerifier = require("./verify-review-decisions");
const guidanceVerifier = require("./verify-framing-guidance");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const SCHEMA = "cf7.portrait-pilot-human-feedback-calibration.v1";

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function readJson(filePath, label) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) throw new reviewBuild.ReviewError(`${label} 缺失：${filePath}`);
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    throw new reviewBuild.ReviewError(`${label} 不是合法 JSON：${error.message}`);
  }
}

function artifact(filePath) {
  const resolved = path.resolve(filePath);
  const relative = path.relative(ROOT, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative) || !fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    throw new reviewBuild.ReviewError(`artifact 越出仓库或缺失：${filePath}`);
  }
  return { path: relative.replaceAll("\\", "/"), bytes: fs.statSync(resolved).size, sha256: reviewBuild.sha256File(resolved) };
}

function ensurePilotChild(target, label, allowExisting = false) {
  const resolved = path.resolve(ROOT, target);
  const relative = path.relative(PILOT_ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) throw new reviewBuild.ReviewError(`${label} 必须位于 tmp/portrait-pilot 下`);
  if (!allowExisting && fs.existsSync(resolved)) throw new reviewBuild.ReviewError(`${label} 已存在，禁止覆盖：${resolved}`);
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

function classifyNote(notes) {
  const value = String(notes || "").toLocaleLowerCase("zh-CN");
  const categories = [];
  if (/右侧.*(空|空间|留)|右边.*(空|空间|留)/u.test(value)) categories.push("right_empty_space");
  if (/顶部.*(空|空间|留)|上部.*(空|空间|留)/u.test(value)) categories.push("top_empty_space");
  if (/全身像|半身像/u.test(value)) categories.push("insufficient_closeup");
  if (/视觉焦点.*(导弹|枪|武器)|抢走.*视觉|武器.*焦点/u.test(value)) categories.push("secondary_weapon_focus");
  if (/方向反转|头朝右|头朝左|朝向/u.test(value)) categories.push("orientation_mismatch");
  if (/放大|缩放更好|更紧/u.test(value)) categories.push("tighten_crop");
  if (/luna\s*b|luna\s*ｂ/u.test(value)) categories.push("prefer_independent_review");
  if (/luna\s*a|luna\s*ａ/u.test(value)) categories.push("prefer_proposal");
  return categories;
}

function median(values) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function geometryRows(guidanceBatch) {
  const loaded = guidanceVerifier.loadGuidanceBatch(guidanceBatch);
  const guidancePath = path.join(loaded.batchRoot, "portrait-pilot-framing-guidance.json");
  const receiptPath = path.join(loaded.batchRoot, "human-framing-guidance-receipt.json");
  const guidance = readJson(guidancePath, "框选指导");
  const validation = guidanceVerifier.validateGuidance(loaded.dataset, guidance);
  const receipt = readJson(receiptPath, "框选回执");
  const receiptEnvelope = { ...receipt };
  delete receiptEnvelope.receiptDigest;
  if (sha256Bytes(reviewBuild.stableStringify(receiptEnvelope)) !== receipt.receiptDigest) throw new reviewBuild.ReviewError("框选回执 digest 不闭合");
  const rows = validation.rows.map((row) => {
    const item = loaded.dataset.items.find((entry) => entry.reviewKey === row.reviewKey);
    const choice = item.choices.find((entry) => entry.sourceRole === row.sourceRole);
    const initial = choice.initialCropBox;
    const final = row.cropBox;
    const initialSide = ((initial[2] - initial[0]) * choice.candidateWidth + (initial[3] - initial[1]) * choice.candidateHeight) / 2;
    const finalSide = ((final[2] - final[0]) * choice.candidateWidth + (final[3] - final[1]) * choice.candidateHeight) / 2;
    const initialCenterX = ((initial[0] + initial[2]) / 2) * choice.candidateWidth;
    const initialCenterY = ((initial[1] + initial[3]) / 2) * choice.candidateHeight;
    const finalCenterX = ((final[0] + final[2]) / 2) * choice.candidateWidth;
    const finalCenterY = ((final[1] + final[3]) / 2) * choice.candidateHeight;
    return {
      reviewKey: row.reviewKey,
      sourceRole: row.sourceRole,
      candidateId: row.candidateId,
      zoomIn: Number((initialSide / finalSide).toFixed(6)),
      shiftXInFinalSides: Number(((finalCenterX - initialCenterX) / finalSide).toFixed(6)),
      shiftYInFinalSides: Number(((finalCenterY - initialCenterY) / finalSide).toFixed(6)),
    };
  });
  return {
    batchId: loaded.dataset.batchId,
    guidanceDigest: loaded.dataset.guidanceDigest,
    receiptDigest: receipt.receiptDigest,
    inputs: {
      data: artifact(loaded.dataPath),
      guidance: artifact(guidancePath),
      receipt: artifact(receiptPath),
    },
    rows,
  };
}

function buildReport(options) {
  const loaded = reviewBuild.loadBatch(options.reviewBatch);
  const reviewPath = path.join(loaded.batchRoot, "review-data.json");
  const decisionsPath = path.join(loaded.batchRoot, "portrait-pilot-review-decisions.json");
  const receiptPath = path.join(loaded.batchRoot, "human-review-receipt.json");
  const dataset = readJson(reviewPath, "review data");
  const decisions = readJson(decisionsPath, "review decisions");
  const receipt = readJson(receiptPath, "human review receipt");
  const validation = decisionVerifier.validateDecisions(dataset, decisions);
  decisionVerifier.verifyReceipt(receipt, {
    sourceDigest: dataset.sourceDigest,
    reviewDigest: dataset.reviewDigest,
    decisionsSha256: reviewBuild.sha256File(decisionsPath),
    reviewDataSha256: reviewBuild.sha256File(reviewPath),
  });
  const rows = validation.rows.map((row) => {
    const categories = classifyNote(row.notes);
    const route = row.status === "adjustment"
      ? (categories.includes("orientation_mismatch") ? "orientation_transform" : "framing_guidance")
      : (row.status === "pass" ? "accepted" : "anomaly_queue");
    return { ...row, feedbackCategories: categories, route };
  });
  const categoryCounts = {};
  for (const row of rows) for (const category of row.feedbackCategories) categoryCounts[category] = (categoryCounts[category] || 0) + 1;
  const geometry = options.guidanceBatches.map(geometryRows);
  const geometryRowsFlat = geometry.flatMap((entry) => entry.rows);
  const zoomValues = geometryRowsFlat.map((row) => row.zoomIn);
  const eligible = validation.eligibleTotal;
  const passed = validation.eligiblePassed;
  const passRate = eligible ? passed / eligible : 0;
  const revisionPageLimit = 6;
  const doubledSize = Math.min(48, eligible * 2);
  const requiredPassRate = doubledSize > eligible ? 1 - revisionPageLimit / doubledSize : 1;
  const nonAdjustmentFailures = rows.filter((row) => !row.blocked && !["pass", "adjustment"].includes(row.status)).length;
  const eligibleToDouble = doubledSize > eligible && passRate >= requiredPassRate && nonAdjustmentFailures === 0;
  const report = {
    schema: SCHEMA,
    status: "human_feedback_calibrated",
    productionReady: false,
    generatedAt: new Date().toISOString(),
    batchId: options.batchId,
    inputs: {
      reviewData: artifact(reviewPath),
      decisions: artifact(decisionsPath),
      humanReviewReceipt: artifact(receiptPath),
      controllerSource: artifact(__filename),
      guidanceBatches: geometry.map((entry) => ({ batchId: entry.batchId, ...entry.inputs })),
    },
    parent: {
      batchId: dataset.batchId,
      sourceDigest: dataset.sourceDigest,
      reviewDigest: dataset.reviewDigest,
      humanReviewReceiptDigest: receipt.receiptDigest,
    },
    counts: {
      eligible,
      passed,
      adjustments: rows.filter((row) => row.status === "adjustment").length,
      nonAdjustmentFailures,
      categoryCounts,
      preferredIndependentReview: rows.filter((row) => row.feedbackCategories.includes("prefer_independent_review")).length,
      preferredProposal: rows.filter((row) => row.feedbackCategories.includes("prefer_proposal")).length,
    },
    rows,
    geometryCalibration: {
      guidanceBatchCount: geometry.length,
      rows: geometryRowsFlat,
      medianZoomIn: median(zoomValues),
      minimumZoomIn: zoomValues.length ? Math.min(...zoomValues) : null,
      maximumZoomIn: zoomValues.length ? Math.max(...zoomValues) : null,
    },
    adaptiveScaling: {
      revisionPageLimit,
      currentShardSize: eligible,
      observedFirstPassRate: Number(passRate.toFixed(6)),
      doubledShardSize: doubledSize,
      requiredPassRateForDouble: Number(requiredPassRate.toFixed(6)),
      eligibleToDouble,
      recommendedNextShardSize: eligibleToDouble ? doubledSize : eligible,
      recommendedSourceGroups: (eligibleToDouble ? doubledSize : eligible) / 4,
      modelItemsPerGroup: 4,
      maximumConcurrency: 6,
    },
    gates: {
      exactHumanReceiptBound: true,
      rawNotesPreserved: true,
      deterministicFeedbackCategories: true,
      geometryOnlyFromVerifiedGuidance: true,
      noAutomaticArtAcceptance: true,
      noModelTrainingClaim: true,
      productionWrites: false,
    },
  };
  report.feedbackDigest = sha256Bytes(reviewBuild.stableStringify(report));
  return report;
}

function verifyReport(report) {
  if (report.schema !== SCHEMA || report.status !== "human_feedback_calibrated" || report.productionReady !== false) {
    throw new reviewBuild.ReviewError("feedback calibration schema 或状态非法");
  }
  const envelope = { ...report };
  delete envelope.feedbackDigest;
  if (sha256Bytes(reviewBuild.stableStringify(envelope)) !== report.feedbackDigest) throw new reviewBuild.ReviewError("feedbackDigest 不匹配");
  const records = [
    report.inputs.reviewData,
    report.inputs.decisions,
    report.inputs.humanReviewReceipt,
    report.inputs.controllerSource,
    ...report.inputs.guidanceBatches.flatMap((entry) => [entry.data, entry.guidance, entry.receipt]),
  ];
  for (const record of records) reviewBuild.resolveRepoArtifact(record, "feedback calibration input");
  if (report.rows.length !== report.counts.eligible || report.adaptiveScaling.revisionPageLimit !== 6) {
    throw new reviewBuild.ReviewError("feedback calibration 行数或复议上限非法");
  }
  return records.length;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.output || !options.batchId || (!options.reviewBatch && !options.check)) {
    process.stdout.write("用法：node tools/portrait-pilot/build-feedback-calibration.js --review-batch <verified review batch> --output <fresh batch> --batch-id <ascii id> [--guidance-batch <verified guidance batch>] [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(options.batchId)) throw new reviewBuild.ReviewError("batch id 非法");
  const outputRoot = ensurePilotChild(options.output, "输出目录", options.check);
  const reportPath = path.join(outputRoot, "human-feedback-calibration.json");
  if (options.check) {
    const report = readJson(reportPath, "feedback calibration");
    if (report.batchId !== options.batchId) throw new reviewBuild.ReviewError("check batch-id 与 report 不一致");
    const artifactCount = verifyReport(report);
    process.stdout.write(`${JSON.stringify({ status: "human_feedback_calibration_verified", feedbackDigest: report.feedbackDigest, counts: report.counts, adaptiveScaling: report.adaptiveScaling, artifactCount })}\n`);
    return;
  }
  const report = buildReport(options);
  fs.mkdirSync(outputRoot, { recursive: false });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  const artifactCount = verifyReport(report);
  process.stdout.write(`${JSON.stringify({ status: report.status, path: path.relative(ROOT, reportPath).replaceAll("\\", "/"), feedbackDigest: report.feedbackDigest, counts: report.counts, adaptiveScaling: report.adaptiveScaling, artifactCount })}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = { buildReport, classifyNote, verifyReport };
