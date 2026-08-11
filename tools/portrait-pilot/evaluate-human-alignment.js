#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const reviewVerify = require("./verify-review-decisions");
const guidanceVerify = require("./verify-framing-guidance");
const { loadManifest } = require("./run-visual-pilot");

const ROOT = path.resolve(__dirname, "..", "..");
const PORTRAIT_TMP = path.join(ROOT, "tmp", "portrait-pilot");
const REPORT_SCHEMA = "cf7.portrait-pilot-human-alignment-evaluation.v1";
const CONTROLLER_VERSION = "portrait-pilot-human-alignment-evaluator-v1";
const ROLES = ["proposal", "independent_review"];

function fail(message) {
  throw new reviewBuild.ReviewError(message);
}

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function relativePath(filePath) {
  return path.relative(ROOT, filePath).replaceAll("\\", "/");
}

function readJson(filePath, label) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) fail(`${label} 缺失：${filePath}`);
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    fail(`${label} 不是合法 JSON：${error.message}`);
  }
}

function resolvePortraitPath(value, label, requireExisting = true) {
  if (!value) fail(`${label} 缺少路径`);
  const resolved = path.resolve(ROOT, value);
  const relative = path.relative(PORTRAIT_TMP, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    fail(`${label} 必须位于 tmp/portrait-pilot 下`);
  }
  if (requireExisting && (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile())) {
    fail(`${label} 缺失：${resolved}`);
  }
  return resolved;
}

function verifyDigestObject(value, digestField, label) {
  if (!value || typeof value !== "object" || typeof value[digestField] !== "string") {
    fail(`${label} 缺 ${digestField}`);
  }
  const envelope = { ...value };
  delete envelope[digestField];
  const actual = sha256Bytes(reviewBuild.stableStringify(envelope));
  if (actual !== value[digestField]) fail(`${label} ${digestField} 不匹配`);
}

function verifyModelReport(report, manifestPath, modelReportPath, loadedManifest) {
  verifyDigestObject(report, "reportDigest", "experimental model report");
  if (
    report.productionReady !== false ||
    report.humanReviewRequired !== true ||
    report.batchId !== loadedManifest.manifest.batchId ||
    report.sourceDigest !== loadedManifest.manifest.sourceDigest ||
    report.manifestDigest !== loadedManifest.manifest.manifestDigest ||
    report.input?.manifestSha256 !== reviewBuild.sha256File(manifestPath)
  ) {
    fail("experimental manifest/model report 跨层闭包不匹配");
  }
  if (!Array.isArray(report.runs) || report.runs.length !== ROLES.length) {
    fail("experimental model report 必须含 proposal 与 independent_review");
  }
  for (const role of ROLES) {
    const run = report.runs.find((entry) => entry.role === role);
    if (!run || run.status !== "accepted" || run.result?.runRole !== role || !Array.isArray(run.batches)) {
      fail(`experimental ${role} run 不闭合`);
    }
    const flattened = run.batches.flatMap((batch) => {
      if (batch.role !== role || batch.status !== "accepted" || !Array.isArray(batch.result?.selections)) {
        fail(`experimental ${role} batch 不闭合`);
      }
      const accepted = batch.attempts?.find((attempt) => attempt.attemptNumber === batch.acceptedAttempt);
      if (!accepted || accepted.status !== "accepted") fail(`experimental ${role} batch 缺 accepted attempt`);
      if (accepted.resultSha256 !== sha256Bytes(reviewBuild.stableStringify(batch.result))) {
        fail(`experimental ${role} accepted result hash 不匹配`);
      }
      for (const [artifactField, digestField, label] of [
        ["stdoutArtifact", "stdoutSha256", "stdout"],
        ["stderrArtifact", "stderrSha256", "stderr"],
      ]) {
        const artifactPath = path.resolve(path.dirname(modelReportPath), accepted[artifactField]);
        const relative = path.relative(ROOT, artifactPath);
        if (
          relative.startsWith("..") ||
          path.isAbsolute(relative) ||
          !fs.existsSync(artifactPath) ||
          reviewBuild.sha256File(artifactPath) !== accepted[digestField]
        ) {
          fail(`experimental ${role} accepted ${label} artifact 不闭合`);
        }
      }
      return batch.result.selections;
    });
    if (reviewBuild.stableStringify(flattened.sort(sortReviewKey)) !== reviewBuild.stableStringify([...run.result.selections].sort(sortReviewKey))) {
      fail(`experimental ${role} merged selections 与 batches 不一致`);
    }
  }
}

function sortReviewKey(left, right) {
  return left.reviewKey.localeCompare(right.reviewKey, "zh-CN");
}

function parseArgs(argv) {
  const options = {
    reviewBatch: null,
    guidanceBatch: null,
    manifest: null,
    modelReport: null,
    output: null,
    check: false,
  };
  const valueFlags = new Map([
    ["--review-batch", "reviewBatch"],
    ["--guidance-batch", "guidanceBatch"],
    ["--manifest", "manifest"],
    ["--model-report", "modelReport"],
    ["--output", "output"],
  ]);
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (valueFlags.has(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) fail(`${argument} 缺少值`);
      options[valueFlags.get(argument)] = value;
      index += 1;
    } else if (argument === "--check") {
      options.check = true;
    } else if (argument === "--help") {
      options.help = true;
    } else {
      fail(`未知参数：${argument}`);
    }
  }
  return options;
}

function usage() {
  return [
    "用法：node tools/portrait-pilot/evaluate-human-alignment.js --review-batch <已冻结人审批次>",
    "  --guidance-batch <对应调整项框选批次>",
    "  --manifest <待评估 candidate-manifest.json>",
    "  --model-report <待评估 model-report.json>",
    "  --output <新报告路径，必须位于 tmp/portrait-pilot>",
    "  --check  重新回放输入并核对已有报告的确定性 evaluationDigest",
  ].join("\n");
}

function loadHumanGroundTruth(reviewBatchPath, guidanceBatchPath) {
  const loaded = reviewBuild.loadBatch(reviewBatchPath);
  const reviewDataPath = path.join(loaded.batchRoot, "review-data.json");
  const decisionsPath = path.join(loaded.batchRoot, "portrait-pilot-review-decisions.json");
  const receiptPath = path.join(loaded.batchRoot, "human-review-receipt.json");
  const dataset = readJson(reviewDataPath, "review data");
  reviewBuild.verifyReviewDataset(dataset);
  const decisions = readJson(decisionsPath, "human review decisions");
  const decisionValidation = reviewVerify.validateDecisions(dataset, decisions);
  const receipt = readJson(receiptPath, "human review receipt");
  reviewVerify.verifyReceipt(receipt, {
    sourceDigest: dataset.sourceDigest,
    reviewDigest: dataset.reviewDigest,
    decisionsSha256: reviewBuild.sha256File(decisionsPath),
    reviewDataSha256: reviewBuild.sha256File(reviewDataPath),
  });
  if (reviewBuild.stableStringify(receipt.decisions) !== reviewBuild.stableStringify(decisionValidation.rows)) {
    fail("human review receipt decisions 与导出决定不一致");
  }

  const guidanceLoaded = guidanceVerify.loadGuidanceBatch(guidanceBatchPath);
  const guidancePath = path.join(guidanceLoaded.batchRoot, "portrait-pilot-framing-guidance.json");
  const guidanceReceiptPath = path.join(guidanceLoaded.batchRoot, "human-framing-guidance-receipt.json");
  const guidance = readJson(guidancePath, "human framing guidance");
  const guidanceValidation = guidanceVerify.validateGuidance(guidanceLoaded.dataset, guidance);
  const guidanceReceipt = readJson(guidanceReceiptPath, "human framing guidance receipt");
  guidanceVerify.verifyReceipt(guidanceReceipt, {
    guidanceDigest: guidanceLoaded.dataset.guidanceDigest,
    parentReceiptDigest: guidanceLoaded.dataset.parent.receiptDigest,
    dataSha256: reviewBuild.sha256File(guidanceLoaded.dataPath),
    guidanceSha256: reviewBuild.sha256File(guidancePath),
  });
  if (
    guidanceLoaded.dataset.parent.receiptDigest !== receipt.receiptDigest ||
    guidanceReceipt.parentReceiptDigest !== receipt.receiptDigest ||
    reviewBuild.stableStringify(guidanceReceipt.rows) !== reviewBuild.stableStringify(guidanceValidation.rows)
  ) {
    fail("framing guidance 没有精确绑定目标人审回执");
  }

  const decisionsByKey = new Map(receipt.decisions.map((row) => [row.reviewKey, row]));
  const guidanceByKey = new Map(guidanceReceipt.rows.map((row) => [row.reviewKey, row]));
  const guidanceItems = new Map(guidanceLoaded.dataset.items.map((item) => [item.reviewKey, item]));
  const targets = [];
  const excluded = [];
  for (const item of dataset.items) {
    const decision = decisionsByKey.get(item.reviewKey);
    if (!decision || item.blocked) {
      excluded.push({ reviewKey: item.reviewKey, status: decision?.status || "blocked", reason: "blocked_or_missing_decision" });
      continue;
    }
    if (decision.status === "pass") {
      const proposal = item.proposals?.proposal;
      const candidate = item.candidates.find((entry) => entry.candidateId === proposal?.candidateId);
      if (!proposal?.geometry?.candidateCropWindow || !candidate || candidate.artifact.sha256 !== proposal.sourceCandidate.sha256) {
        fail(`pass target 缺 proposal 几何或候选闭包：${item.reviewKey}`);
      }
      const [left, top, sideX, sideY] = proposal.geometry.candidateCropWindow;
      targets.push({
        reviewKey: item.reviewKey,
        humanStatus: "pass",
        acceptedRole: "proposal",
        candidateId: proposal.candidateId,
        sourceCandidateSha256: proposal.sourceCandidate.sha256,
        candidateWidth: candidate.width,
        candidateHeight: candidate.height,
        cropBox: [left / candidate.width, top / candidate.height, (left + sideX) / candidate.width, (top + sideY) / candidate.height],
        humanNotes: decision.notes,
      });
      continue;
    }
    if (decision.status === "adjustment") {
      const row = guidanceByKey.get(item.reviewKey);
      const guidanceItem = guidanceItems.get(item.reviewKey);
      const choice = guidanceItem?.choices.find((entry) => entry.sourceRole === row?.sourceRole);
      if (
        !row ||
        !choice ||
        row.candidateId !== choice.candidateId ||
        row.sourceCandidateSha256 !== choice.sourceCandidate.sha256
      ) {
        fail(`adjustment target 缺精确人类框选：${item.reviewKey}`);
      }
      targets.push({
        reviewKey: item.reviewKey,
        humanStatus: "adjustment",
        acceptedRole: row.sourceRole,
        candidateId: row.candidateId,
        sourceCandidateSha256: row.sourceCandidateSha256,
        candidateWidth: choice.candidateWidth,
        candidateHeight: choice.candidateHeight,
        cropBox: row.cropBox,
        humanNotes: decision.notes,
      });
      continue;
    }
    excluded.push({ reviewKey: item.reviewKey, status: decision.status, reason: "no_accepted_geometry" });
  }

  const adjustmentKeys = new Set(targets.filter((target) => target.humanStatus === "adjustment").map((target) => target.reviewKey));
  if (
    guidanceReceipt.rows.length !== adjustmentKeys.size ||
    guidanceReceipt.rows.some((row) => !adjustmentKeys.has(row.reviewKey))
  ) {
    fail("guidance rows 与 adjustment decisions 不是精确集合");
  }
  return {
    loaded,
    dataset,
    receipt,
    guidanceLoaded,
    guidanceReceipt,
    targets: targets.sort(sortReviewKey),
    excluded: excluded.sort(sortReviewKey),
    inputs: {
      reviewData: artifactRecord(reviewDataPath),
      decisions: artifactRecord(decisionsPath),
      humanReviewReceipt: artifactRecord(receiptPath),
      guidanceData: artifactRecord(guidanceLoaded.dataPath),
      guidance: artifactRecord(guidancePath),
      guidanceReceipt: artifactRecord(guidanceReceiptPath),
    },
  };
}

function artifactRecord(filePath) {
  return {
    path: relativePath(filePath),
    bytes: fs.statSync(filePath).size,
    sha256: reviewBuild.sha256File(filePath),
  };
}

function normalizeBox(box, label) {
  if (!Array.isArray(box) || box.length !== 4 || box.some((value) => typeof value !== "number" || !Number.isFinite(value))) {
    fail(`${label} 必须是四个有限数字`);
  }
  if (box[0] >= box[2] || box[1] >= box[3]) fail(`${label} 顺序非法`);
  return box.map(Number);
}

function deriveCropBox(selection, candidate, geometryContract) {
  const feature = normalizeBox(selection.featureBox, `${selection.reviewKey} featureBox`);
  const must = normalizeBox(selection.mustIncludeBox, `${selection.reviewKey} mustIncludeBox`);
  if (
    must[0] > feature[0] || must[1] > feature[1] ||
    must[2] < feature[2] || must[3] < feature[3]
  ) {
    fail(`${selection.reviewKey} mustIncludeBox 没有包含 featureBox`);
  }
  const config = geometryContract?.modes?.[selection.framingMode];
  const safe = geometryContract?.mustIncludeSafeMargin;
  if (!config || typeof safe !== "number") fail(`${selection.reviewKey} framingMode/geometry contract 非法`);
  const width = Number(candidate.width);
  const height = Number(candidate.height);
  if (!(width > 0) || !(height > 0)) fail(`${selection.reviewKey} candidate 尺寸非法`);
  const [fx0, fy0, fx1, fy1] = [feature[0] * width, feature[1] * height, feature[2] * width, feature[3] * height];
  const [mx0, my0, mx1, my1] = [must[0] * width, must[1] * height, must[2] * width, must[3] * height];
  const featureWidth = fx1 - fx0;
  const featureHeight = fy1 - fy0;
  const mustWidth = mx1 - mx0;
  const mustHeight = my1 - my0;
  const usable = 1 - 2 * safe;
  const side = Math.max(
    featureWidth / config.featureWidthOccupancy,
    featureHeight / config.featureHeightOccupancy,
    mustWidth / usable,
    mustHeight / usable,
    8,
  );
  const [anchorX, anchorY] = config.featureAnchor;
  const featureCenterX = (fx0 + fx1) / 2;
  const featureCenterY = (fy0 + fy1) / 2;
  const desiredLeft = featureCenterX - anchorX * side;
  const desiredTop = featureCenterY - anchorY * side;
  const leftLower = mx1 - (1 - safe) * side;
  const leftUpper = mx0 - safe * side;
  const topLower = my1 - (1 - safe) * side;
  const topUpper = my0 - safe * side;
  if (leftLower > leftUpper + 1e-6 || topLower > topUpper + 1e-6) {
    fail(`${selection.reviewKey} 安全边距几何不可满足`);
  }
  const left = Math.min(Math.max(desiredLeft, leftLower), leftUpper);
  const top = Math.min(Math.max(desiredTop, topLower), topUpper);
  return [left / width, top / height, (left + side) / width, (top + side) / height];
}

function pixelRect(box, width, height) {
  return [box[0] * width, box[1] * height, box[2] * width, box[3] * height];
}

function rectangleIou(left, right) {
  const x0 = Math.max(left[0], right[0]);
  const y0 = Math.max(left[1], right[1]);
  const x1 = Math.min(left[2], right[2]);
  const y1 = Math.min(left[3], right[3]);
  const intersection = Math.max(0, x1 - x0) * Math.max(0, y1 - y0);
  const leftArea = (left[2] - left[0]) * (left[3] - left[1]);
  const rightArea = (right[2] - right[0]) * (right[3] - right[1]);
  return intersection / (leftArea + rightArea - intersection);
}

function round(value, digits = 6) {
  return value === null ? null : Number(value.toFixed(digits));
}

function scoreBoxes(predictedBox, targetBox, width, height) {
  const predicted = pixelRect(normalizeBox(predictedBox, "predicted crop"), width, height);
  const target = pixelRect(normalizeBox(targetBox, "target crop"), width, height);
  const predictedSide = ((predicted[2] - predicted[0]) + (predicted[3] - predicted[1])) / 2;
  const targetSide = ((target[2] - target[0]) + (target[3] - target[1])) / 2;
  const predictedCenter = [(predicted[0] + predicted[2]) / 2, (predicted[1] + predicted[3]) / 2];
  const targetCenter = [(target[0] + target[2]) / 2, (target[1] + target[3]) / 2];
  const zoomCorrection = predictedSide / targetSide;
  const shift = [
    (targetCenter[0] - predictedCenter[0]) / targetSide,
    (targetCenter[1] - predictedCenter[1]) / targetSide,
  ];
  const centerDistance = Math.hypot(...shift);
  const cropIou = rectangleIou(predicted, target);
  const absLog2ScaleError = Math.abs(Math.log2(zoomCorrection));
  const loss = absLog2ScaleError + centerDistance + (1 - cropIou);
  return {
    predictedCropBox: predictedBox.map((value) => round(value, 9)),
    targetCropBox: targetBox.map((value) => round(value, 9)),
    predictedPixelSide: round(predictedSide),
    targetPixelSide: round(targetSide),
    zoomCorrectionToHuman: round(zoomCorrection),
    centerShiftToHumanInHumanSides: shift.map((value) => round(value)),
    centerDistanceInHumanSides: round(centerDistance),
    cropIoU: round(cropIou),
    absLog2ScaleError: round(absLog2ScaleError),
    loss: round(loss),
    nearHumanTarget:
      zoomCorrection >= 0.85 && zoomCorrection <= 1.15 &&
      centerDistance <= 0.15 && cropIou >= 0.7,
  };
}

function median(values) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function mean(values) {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null;
}

function aggregateRows(rows) {
  const comparable = rows.filter((row) => row.candidateMatch);
  const losses = rows.map((row) => row.loss);
  const aggregate = {
    total: rows.length,
    candidateMatches: comparable.length,
    candidateMatchRate: round(comparable.length / Math.max(1, rows.length)),
    comparable: comparable.length,
    nearHumanTarget: comparable.filter((row) => row.nearHumanTarget).length,
    nearHumanTargetRate: round(comparable.filter((row) => row.nearHumanTarget).length / Math.max(1, rows.length)),
    medianZoomCorrectionToHuman: round(median(comparable.map((row) => row.zoomCorrectionToHuman))),
    meanAbsLog2ScaleError: round(mean(comparable.map((row) => row.absLog2ScaleError))),
    meanCenterDistanceInHumanSides: round(mean(comparable.map((row) => row.centerDistanceInHumanSides))),
    meanCropIoU: round(mean(comparable.map((row) => row.cropIoU))),
    meanLoss: round(mean(losses)),
  };
  aggregate.alignmentScore = round(1 / (1 + aggregate.meanLoss));
  return aggregate;
}

function evaluateRole(role, run, targets, manifest) {
  const selections = new Map(run.result.selections.map((selection) => [selection.reviewKey, selection]));
  const manifestItems = new Map(manifest.reviewItems.filter((item) => !item.blocked).map((item) => [item.reviewKey, item]));
  const rows = targets.map((target) => {
    const selection = selections.get(target.reviewKey);
    const item = manifestItems.get(target.reviewKey);
    if (!selection || !item) fail(`${role} 缺目标 reviewKey：${target.reviewKey}`);
    const candidate = item.candidates.find((entry) => entry.candidateId === selection.candidateId);
    if (!candidate) fail(`${role} 选择了 manifest 外候选：${target.reviewKey}/${selection.candidateId}`);
    const candidateMatch = candidate.artifact.sha256 === target.sourceCandidateSha256;
    const common = {
      reviewKey: target.reviewKey,
      humanStatus: target.humanStatus,
      humanAcceptedRole: target.acceptedRole,
      humanNotes: target.humanNotes,
      selectedCandidateId: selection.candidateId,
      selectedCandidateSha256: candidate.artifact.sha256,
      targetCandidateId: target.candidateId,
      targetCandidateSha256: target.sourceCandidateSha256,
      candidateMatch,
      featureLabel: selection.featureLabel,
      framingMode: selection.framingMode,
    };
    if (!candidateMatch) {
      return {
        ...common,
        predictedCropBox: null,
        targetCropBox: target.cropBox,
        zoomCorrectionToHuman: null,
        centerShiftToHumanInHumanSides: null,
        centerDistanceInHumanSides: null,
        cropIoU: 0,
        absLog2ScaleError: null,
        loss: 4,
        nearHumanTarget: false,
      };
    }
    if (candidate.width !== target.candidateWidth || candidate.height !== target.candidateHeight) {
      fail(`${role} 同 hash 候选尺寸与人类目标不一致：${target.reviewKey}`);
    }
    const predictedCrop = deriveCropBox(selection, candidate, manifest.featureContract.geometry);
    return { ...common, ...scoreBoxes(predictedCrop, target.cropBox, candidate.width, candidate.height) };
  });
  const byHumanStatus = {};
  for (const status of ["pass", "adjustment"]) {
    byHumanStatus[status] = aggregateRows(rows.filter((row) => row.humanStatus === status));
  }
  return { aggregate: aggregateRows(rows), byHumanStatus, rows };
}

function controllerEvidence() {
  const files = [__filename].map((filePath) => artifactRecord(filePath));
  return {
    version: CONTROLLER_VERSION,
    nodeVersion: process.version,
    files,
    sourceClosureDigest: sha256Bytes(reviewBuild.stableStringify(files)),
  };
}

function evaluationEnvelope(report) {
  return {
    schema: report.schema,
    status: report.status,
    productionReady: report.productionReady,
    humanReviewReplaced: report.humanReviewReplaced,
    controller: report.controller,
    inputs: report.inputs,
    humanGroundTruth: report.humanGroundTruth,
    roles: report.roles,
    gates: report.gates,
  };
}

function buildEvaluation(options) {
  const groundTruth = loadHumanGroundTruth(options.reviewBatch, options.guidanceBatch);
  const manifestPath = resolvePortraitPath(options.manifest, "experimental manifest");
  const modelReportPath = resolvePortraitPath(options.modelReport, "experimental model report");
  const loadedManifest = loadManifest(manifestPath);
  const modelReport = readJson(modelReportPath, "experimental model report");
  verifyModelReport(modelReport, manifestPath, modelReportPath, loadedManifest);
  const targetKeys = groundTruth.targets.map((target) => target.reviewKey);
  const experimentalKeys = loadedManifest.reviewItems.map((item) => item.reviewKey).sort((left, right) => left.localeCompare(right, "zh-CN"));
  const expectedKeys = [...groundTruth.dataset.items.filter((item) => !item.blocked).map((item) => item.reviewKey)]
    .sort((left, right) => left.localeCompare(right, "zh-CN"));
  if (reviewBuild.stableStringify(experimentalKeys) !== reviewBuild.stableStringify(expectedKeys)) {
    fail("experimental manifest 与人审批次的 eligible reviewKey 集合不一致");
  }
  const roles = {};
  for (const role of ROLES) {
    roles[role] = evaluateRole(role, modelReport.runs.find((run) => run.role === role), groundTruth.targets, loadedManifest.manifest);
  }
  const eligible = groundTruth.receipt.counts.eligible;
  const passed = groundTruth.receipt.counts.eligiblePassed;
  const report = {
    schema: REPORT_SCHEMA,
    status: "human_alignment_evaluated",
    productionReady: false,
    humanReviewReplaced: false,
    generatedAt: new Date().toISOString(),
    controller: controllerEvidence(),
    inputs: {
      ...groundTruth.inputs,
      targetHumanReviewReceiptDigest: groundTruth.receipt.receiptDigest,
      targetHumanGuidanceReceiptDigest: groundTruth.guidanceReceipt.receiptDigest,
      experimentalManifest: artifactRecord(manifestPath),
      experimentalManifestDigest: loadedManifest.manifest.manifestDigest,
      experimentalModelReport: artifactRecord(modelReportPath),
      experimentalModelReportDigest: modelReport.reportDigest,
    },
    humanGroundTruth: {
      eligible,
      passed,
      passRate: round(passed / Math.max(1, eligible)),
      targetableGeometryRows: groundTruth.targets.length,
      targetableReviewKeys: targetKeys,
      excluded: groundTruth.excluded,
      statusCounts: groundTruth.receipt.counts.statuses,
    },
    roles,
    gates: {
      frozenHumanReviewVerified: true,
      frozenHumanGuidanceVerified: true,
      allAdjustmentRowsGuided: true,
      exactReviewKeySet: true,
      exactCandidateHashComparison: true,
      deterministicGeometryRecomputed: true,
      modelArtifactsVerified: true,
      humanReviewReplaced: false,
      productionWrites: false,
    },
  };
  report.evaluationDigest = sha256Bytes(reviewBuild.stableStringify(evaluationEnvelope(report)));
  report.reportDigest = sha256Bytes(reviewBuild.stableStringify(report));
  return report;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.reviewBatch || !options.guidanceBatch || !options.manifest || !options.modelReport || !options.output) {
    process.stdout.write(`${usage()}\n`);
    if (!options.help) process.exitCode = 1;
    return;
  }
  const outputPath = resolvePortraitPath(options.output, "evaluation output", options.check);
  const report = buildEvaluation(options);
  if (options.check) {
    const existing = readJson(outputPath, "human alignment report");
    verifyDigestObject(existing, "reportDigest", "human alignment report");
    if (existing.evaluationDigest !== report.evaluationDigest) fail("回放 evaluationDigest 与已有报告不一致");
    process.stdout.write(`${JSON.stringify({ status: "human_alignment_evaluation_verified", evaluationDigest: existing.evaluationDigest, roles: existing.roles.proposal.aggregate })}\n`);
    return;
  }
  if (fs.existsSync(outputPath)) fail("evaluation output 已存在，禁止覆盖");
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  process.stdout.write(`${JSON.stringify({ status: report.status, output: relativePath(outputPath), evaluationDigest: report.evaluationDigest, roles: Object.fromEntries(ROLES.map((role) => [role, report.roles[role].aggregate])) })}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  aggregateRows,
  buildEvaluation,
  deriveCropBox,
  scoreBoxes,
};
