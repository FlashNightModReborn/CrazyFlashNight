#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const reviewVerifier = require("./verify-review-decisions");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const DATA_SCHEMA = "cf7.enemy-portrait-frame-reselection-candidates.v1";
const DECISION_SCHEMA = "cf7.enemy-portrait-frame-reselection-decisions.v1";
const REVIEWER_FILES = [
  path.join(__dirname, "build-frame-reselection.js"),
  path.join(__dirname, "verify-frame-reselection.js"),
  path.join(__dirname, "open-frame-reselection.js"),
  path.join(__dirname, "test-frame-reselection.js"),
  path.join(ROOT, "launcher", "web", "modules", "portrait-pilot-review", "dev", "frame-reselection.html"),
  path.join(ROOT, "launcher", "web", "modules", "portrait-pilot-review", "dev", "frame-reselection.js"),
  path.join(ROOT, "launcher", "web", "modules", "portrait-pilot-review", "dev", "source-choice.css"),
  path.join(ROOT, "launcher", "web", "modules", "portrait-pilot-review", "dev", "review.css"),
];

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
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) throw new reviewBuild.ReviewError(`${label} 缺失：${filePath}`);
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    throw new reviewBuild.ReviewError(`${label} 不是合法 JSON：${error.message}`);
  }
}

function parseArgs(argv) {
  const options = { sourceBatch: null, output: null, batchId: null, reviewKeys: [], check: false, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--source-batch", "--output", "--batch-id", "--review-key"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new reviewBuild.ReviewError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--source-batch") options.sourceBatch = value;
      else if (argument === "--output") options.output = value;
      else if (argument === "--batch-id") options.batchId = value;
      else options.reviewKeys.push(value);
    } else if (argument === "--check") options.check = true;
    else if (argument === "--help") options.help = true;
    else throw new reviewBuild.ReviewError(`未知参数：${argument}`);
  }
  return options;
}

function ensurePilotChild(target, label, allowExisting = false) {
  const resolved = path.resolve(ROOT, target);
  const relative = path.relative(PILOT_ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) throw new reviewBuild.ReviewError(`${label} 必须位于 tmp/portrait-pilot 下`);
  if (!allowExisting && fs.existsSync(resolved)) throw new reviewBuild.ReviewError(`${label} 已存在，禁止覆盖`);
  return resolved;
}

function loadParent(sourceBatch) {
  const loaded = reviewBuild.loadBatch(sourceBatch);
  const reviewDataPath = path.join(loaded.batchRoot, "review-data.json");
  const decisionsPath = path.join(loaded.batchRoot, "portrait-pilot-review-decisions.json");
  const receiptPath = path.join(loaded.batchRoot, "human-review-receipt.json");
  const reviewData = readJson(reviewDataPath, "父 review data");
  reviewBuild.verifyReviewDataset(reviewData);
  const decisions = readJson(decisionsPath, "父人审决定");
  const receipt = readJson(receiptPath, "父人审回执");
  reviewVerifier.verifyReceipt(receipt, {
    sourceDigest: reviewData.sourceDigest,
    reviewDigest: reviewData.reviewDigest,
    decisionsSha256: reviewBuild.sha256File(decisionsPath),
    reviewDataSha256: reviewBuild.sha256File(reviewDataPath),
  });
  if (receipt.receiptDigest !== sha256Bytes(reviewBuild.stableStringify(Object.fromEntries(Object.entries(receipt).filter(([key]) => key !== "receiptDigest"))))) {
    throw new reviewBuild.ReviewError("父人审回执 digest 不匹配");
  }
  return { ...loaded, reviewData, decisions, receipt, reviewDataPath, decisionsPath, receiptPath };
}

function buildDataset(parent, options) {
  const requested = new Set(options.reviewKeys);
  const wrongPose = parent.receipt.decisions.filter((row) => row.status === "wrong_pose" && (!requested.size || requested.has(row.reviewKey)));
  if (!wrongPose.length) throw new reviewBuild.ReviewError("没有匹配的 wrong_pose 人审行");
  if (requested.size && wrongPose.length !== requested.size) throw new reviewBuild.ReviewError("指定 reviewKey 未全部命中 wrong_pose 行");
  const itemsByKey = new Map(parent.manifest.reviewItems.map((item) => [item.reviewKey, item]));
  const selectedByKey = new Map();
  for (const run of parent.modelReport.runs) {
    for (const selection of run.result.selections) {
      if (!selectedByKey.has(selection.reviewKey)) selectedByKey.set(selection.reviewKey, new Set());
      selectedByKey.get(selection.reviewKey).add(selection.candidateId);
    }
  }
  const reviewDataByKey = new Map(parent.reviewData.items.map((item) => [item.reviewKey, item]));
  const items = wrongPose.map((decision) => {
    const item = itemsByKey.get(decision.reviewKey);
    const reviewItem = reviewDataByKey.get(decision.reviewKey);
    if (!item || item.blocked || !reviewItem) throw new reviewBuild.ReviewError(`wrong_pose 找不到可选审核项：${decision.reviewKey}`);
    const rejectedCandidateIds = [...(selectedByKey.get(decision.reviewKey) || [])].sort();
    if (!rejectedCandidateIds.length || rejectedCandidateIds.length >= item.candidates.length) {
      throw new reviewBuild.ReviewError(`wrong_pose 没有可用替代帧：${decision.reviewKey}`);
    }
    return {
      reviewCode: item.reviewCode,
      reviewKey: item.reviewKey,
      portraitRef: item.portraitRef,
      variantKey: item.variantKey,
      category: item.category,
      humanDecision: {
        status: decision.status,
        notes: decision.notes,
        updatedAt: decision.updatedAt,
      },
      rejectedCandidateIds,
      candidates: item.candidates.map((candidate) => ({
        candidateId: candidate.candidateId,
        frame: candidate.frame,
        width: candidate.width,
        height: candidate.height,
        sourceSize: candidate.sourceSize,
        sourceCropBounds: candidate.sourceCropBounds,
        vectorCanvasSize: candidate.vectorCanvasSize,
        artifact: candidate.artifact,
        vectorArtifact: candidate.vectorArtifact,
      })),
    };
  });
  const reviewerFiles = REVIEWER_FILES.map(artifact);
  const parentFiles = {
    candidateManifest: artifact(path.join(parent.batchRoot, "candidate-manifest.json")),
    modelReport: artifact(path.join(parent.batchRoot, "model-report.json")),
    renderReport: artifact(path.join(parent.batchRoot, "render-report.json")),
    reviewData: artifact(parent.reviewDataPath),
    decisions: artifact(parent.decisionsPath),
    humanReviewReceipt: artifact(parent.receiptPath),
  };
  const dataset = {
    schema: DATA_SCHEMA,
    phase: "FRAME_RESELECTION",
    status: "frame_candidates_ready",
    productionReady: false,
    batchId: options.batchId,
    createdAt: new Date().toISOString(),
    decisionSchema: DECISION_SCHEMA,
    sourceDigest: parent.manifest.sourceDigest,
    parent: {
      batchId: parent.manifest.batchId,
      manifestDigest: parent.manifest.manifestDigest,
      modelReportDigest: parent.modelReport.reportDigest,
      reviewDigest: parent.reviewData.reviewDigest,
      receiptDigest: parent.receipt.receiptDigest,
      files: parentFiles,
    },
    reviewer: {
      files: reviewerFiles,
      sourceClosureDigest: sha256Bytes(reviewBuild.stableStringify(reviewerFiles)),
    },
    counts: {
      identityCount: items.length,
      candidateCount: items.reduce((sum, item) => sum + item.candidates.length, 0),
      rejectedCandidateCount: items.reduce((sum, item) => sum + item.rejectedCandidateIds.length, 0),
      selectableCandidateCount: items.reduce((sum, item) => sum + item.candidates.length - item.rejectedCandidateIds.length, 0),
    },
    items,
    gates: {
      onlyFrozenWrongPoseRows: true,
      rejectedCurrentFramesNotSelectable: true,
      vectorFramesShownAtLargeSize: true,
      humanFrameSelectionRequired: true,
      localizationRerunRequiredAfterSelection: true,
      modelGeometryNotReused: true,
      productionWrites: false,
    },
  };
  dataset.datasetDigest = sha256Bytes(reviewBuild.stableStringify(dataset));
  return dataset;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.output || (!options.check && (!options.sourceBatch || !options.batchId))) {
    process.stdout.write("用法：node tools/portrait-pilot/build-frame-reselection.js --source-batch <verified review batch> --output <fresh batch> --batch-id <ascii id> [--review-key <wrong_pose key>] [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const verifier = require("./verify-frame-reselection");
  const outputRoot = ensurePilotChild(options.output, "输出目录", options.check);
  const dataPath = path.join(outputRoot, "frame-reselection-data.json");
  if (options.check) {
    const dataset = readJson(dataPath, "frame reselection data");
    const artifactCount = verifier.verifyDataset(dataset);
    process.stdout.write(`${JSON.stringify({ status: "frame_reselection_data_verified", datasetDigest: dataset.datasetDigest, rows: dataset.items.length, candidates: dataset.counts.candidateCount, artifactCount })}\n`);
    return;
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(options.batchId)) throw new reviewBuild.ReviewError("batch id 非法");
  const parent = loadParent(options.sourceBatch);
  const dataset = buildDataset(parent, options);
  fs.mkdirSync(outputRoot, { recursive: false });
  fs.writeFileSync(dataPath, `${JSON.stringify(dataset, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  const artifactCount = verifier.verifyDataset(dataset);
  process.stdout.write(`${JSON.stringify({
    status: dataset.status,
    path: path.relative(ROOT, dataPath).replaceAll("\\", "/"),
    datasetDigest: dataset.datasetDigest,
    rows: dataset.items.length,
    candidates: dataset.counts.candidateCount,
    selectable: dataset.counts.selectableCandidateCount,
    artifactCount,
  })}\n`);
}

if (require.main === module) {
  try { main(); } catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = { DATA_SCHEMA, DECISION_SCHEMA, buildDataset, loadParent };
