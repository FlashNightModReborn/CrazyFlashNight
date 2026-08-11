#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const decisionVerifier = require("./verify-review-decisions");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const DATA_SCHEMA = "cf7.portrait-pilot-framing-guidance-data.v1";
const GUIDANCE_SCHEMA = "cf7.portrait-pilot-framing-guidance.v1";
const REVIEWER_FILES = [
  "launcher/web/modules/portrait-pilot-review/dev/framing-guidance.html",
  "launcher/web/modules/portrait-pilot-review/dev/framing-guidance.js",
  "launcher/web/modules/portrait-pilot-review/dev/framing-guidance.css",
  "launcher/web/modules/portrait-pilot-review/dev/review.css",
];

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function ensureBelow(target, parent, label) {
  const resolved = path.resolve(target);
  const relative = path.relative(path.resolve(parent), resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new reviewBuild.ReviewError(`${label} 必须是 ${path.relative(ROOT, parent).replaceAll("\\", "/")} 下的新目录`);
  }
  return resolved;
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
  const options = { sourceBatch: null, output: null, batchId: null, check: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--source-batch", "--output", "--batch-id"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new reviewBuild.ReviewError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--source-batch") options.sourceBatch = value;
      if (argument === "--output") options.output = value;
      if (argument === "--batch-id") options.batchId = value;
    } else if (argument === "--check") {
      options.check = true;
    } else if (argument === "--help") {
      options.help = true;
    } else {
      throw new reviewBuild.ReviewError(`未知参数：${argument}`);
    }
  }
  return options;
}

function computeGuidanceDigest(dataset) {
  return sha256Bytes(reviewBuild.stableStringify({
    schema: dataset.schema,
    batchId: dataset.batchId,
    parent: dataset.parent,
    guidanceSchema: dataset.guidanceSchema,
    renderContract: dataset.renderContract,
    reviewer: dataset.reviewer,
    items: dataset.items,
    gates: dataset.gates,
  }));
}

function currentCropBox(proposal, candidate) {
  const window = proposal.geometry?.candidateCropWindow;
  if (!Array.isArray(window) || window.length !== 4 || window.some((value) => typeof value !== "number" || !Number.isFinite(value))) {
    throw new reviewBuild.ReviewError(`提案缺 candidateCropWindow：${proposal.reviewKey}/${proposal.role}`);
  }
  const [left, top, width, height] = window;
  if (width <= 0 || Math.abs(width - height) > 1e-5) {
    throw new reviewBuild.ReviewError(`提案 crop window 不是正方形：${proposal.reviewKey}/${proposal.role}`);
  }
  return [
    left / candidate.width,
    top / candidate.height,
    (left + width) / candidate.width,
    (top + height) / candidate.height,
  ].map((value) => Number(value.toFixed(9)));
}

function reviewerEvidence() {
  const files = REVIEWER_FILES.map((relative) => artifact(path.join(ROOT, relative)));
  return {
    files,
    sourceClosureDigest: sha256Bytes(reviewBuild.stableStringify(files)),
  };
}

function verifyParent(sourceBatch) {
  const loaded = reviewBuild.loadBatch(sourceBatch);
  const reviewPath = path.join(loaded.batchRoot, "review-data.json");
  const decisionsPath = path.join(loaded.batchRoot, "portrait-pilot-review-decisions.json");
  const receiptPath = path.join(loaded.batchRoot, "human-review-receipt.json");
  const dataset = readJson(reviewPath, "父 review data");
  if (reviewBuild.computeReviewDigest(dataset) !== dataset.reviewDigest) {
    throw new reviewBuild.ReviewError("父 reviewDigest 不匹配");
  }
  const decisions = readJson(decisionsPath, "父决定文件");
  const validation = decisionVerifier.validateDecisions(dataset, decisions);
  const receipt = readJson(receiptPath, "父人审收据");
  decisionVerifier.verifyReceipt(receipt, {
    sourceDigest: dataset.sourceDigest,
    reviewDigest: dataset.reviewDigest,
    decisionsSha256: reviewBuild.sha256File(decisionsPath),
    reviewDataSha256: reviewBuild.sha256File(reviewPath),
  });
  if (receipt.status !== "human_reviewed_refinement_required") {
    throw new reviewBuild.ReviewError("父人审结论不是 refinement_required");
  }
  return { ...loaded, dataset, decisions, validation, receipt, reviewPath, decisionsPath, receiptPath };
}

function choiceFor(item, role, renderContract) {
  const proposal = item.proposals?.[role];
  if (!proposal) throw new reviewBuild.ReviewError(`缺 ${role} 提案：${item.reviewKey}`);
  const candidate = item.candidates.find((entry) => entry.candidateId === proposal.candidateId);
  if (!candidate) throw new reviewBuild.ReviewError(`提案候选不在审核白名单：${item.reviewKey}/${proposal.candidateId}`);
  if (reviewBuild.stableStringify(candidate.artifact) !== reviewBuild.stableStringify(proposal.sourceCandidate)) {
    throw new reviewBuild.ReviewError(`提案 sourceCandidate 与候选 artifact 不一致：${item.reviewKey}/${role}`);
  }
  const sourceScale = proposal.cropMapping?.sourceScale;
  if (!Array.isArray(sourceScale) || sourceScale.length !== 2 || sourceScale.some((value) => typeof value !== "number" || !Number.isFinite(value) || value <= 0)) {
    throw new reviewBuild.ReviewError(`提案缺高分辨率 sourceScale：${item.reviewKey}/${role}`);
  }
  for (const [label, record] of [
    ["source candidate", proposal.sourceCandidate],
    ["source high resolution", proposal.sourceHighResolution],
    ["current master", proposal.master],
    ["preview 80", proposal.previews?.["80"]],
    ["preview 48", proposal.previews?.["48"]],
    ["preview 32", proposal.previews?.["32"]],
  ]) reviewBuild.resolveRepoArtifact(record, `${label} ${item.reviewKey}/${role}`);
  return {
    sourceRole: role,
    label: role === "proposal" ? "Luna A 提案" : "Luna B 独立复核",
    candidateId: candidate.candidateId,
    frame: candidate.frame,
    candidateWidth: candidate.width,
    candidateHeight: candidate.height,
    sourceCandidate: proposal.sourceCandidate,
    sourceHighResolution: proposal.sourceHighResolution,
    currentMaster: proposal.master,
    currentPreviews: proposal.previews,
    selectedFrameZoom: proposal.selectedFrameZoom,
    sourceSize: candidate.sourceSize,
    sourceCropBounds: candidate.sourceCropBounds,
    sourceScale,
    minimumCandidateCropSide: renderContract.minimumSourceCropSize / Math.min(...sourceScale),
    initialCropBox: currentCropBox(proposal, candidate),
  };
}

function explicitRoleHint(notes) {
  const value = String(notes || "").toLocaleLowerCase("zh-CN");
  if (/luna\s*b|luna\s*ｂ/u.test(value)) return "independent_review";
  if (/luna\s*a|luna\s*ａ/u.test(value)) return "proposal";
  return null;
}

function buildDataset(parent, batchId) {
  const decisions = parent.decisions.decisions;
  const renderContract = {
    targetSupersampleSize: parent.renderReport.renderer?.targetSupersampleSize,
    minimumSourceCropSize: parent.renderReport.renderer?.minimumSourceCropSize,
    fidelityMeanAbsoluteErrorLimit: parent.renderReport.fidelitySummary?.meanAbsoluteErrorLimit,
  };
  if (
    !Number.isInteger(renderContract.targetSupersampleSize) ||
    !Number.isInteger(renderContract.minimumSourceCropSize) ||
    typeof renderContract.fidelityMeanAbsoluteErrorLimit !== "number"
  ) throw new reviewBuild.ReviewError("父高分辨率渲染合同不闭合");
  const items = parent.dataset.items
    .filter((item) => !item.blocked && decisions[item.reviewKey]?.status === "adjustment")
    .map((item) => {
      const choices = [choiceFor(item, "proposal", renderContract), choiceFor(item, "independent_review", renderContract)];
      return {
        reviewCode: item.reviewCode,
        reviewKey: item.reviewKey,
        portraitRef: item.portraitRef,
        variantKey: item.variantKey,
        category: item.category,
        notes: item.notes,
        humanDecision: decisions[item.reviewKey],
        preferredRoleHint: explicitRoleHint(decisions[item.reviewKey].notes),
        oldReference: item.oldReference,
        choices,
      };
    });
  if (items.length < 1) throw new reviewBuild.ReviewError("父批没有可框选的 adjustment 行");
  const parentFiles = {
    candidateManifest: artifact(path.join(parent.batchRoot, "candidate-manifest.json")),
    modelReport: artifact(path.join(parent.batchRoot, "model-report.json")),
    renderReport: artifact(path.join(parent.batchRoot, "render-report.json")),
    reviewData: artifact(parent.reviewPath),
    decisions: artifact(parent.decisionsPath),
    humanReviewReceipt: artifact(parent.receiptPath),
  };
  const dataset = {
    schema: DATA_SCHEMA,
    partial: false,
    productionReady: false,
    generatedAt: new Date().toISOString(),
    batchId,
    parent: {
      batchId: parent.dataset.batchId,
      sourceDigest: parent.dataset.sourceDigest,
      reviewDigest: parent.dataset.reviewDigest,
      receiptDigest: parent.receipt.receiptDigest,
      files: parentFiles,
    },
    guidanceSchema: GUIDANCE_SCHEMA,
    renderContract,
    reviewer: reviewerEvidence(),
    items,
    gates: {
      onlyFrozenAdjustmentRows: true,
      explicitSourceRoleRequired: true,
      exactCandidateHashRequired: true,
      pixelSquareCropRequired: true,
      liveLowResolutionPreviewRequired: true,
      humanConfirmationRequired: true,
      modelRerunRequired: false,
      productionWrites: false,
    },
  };
  dataset.guidanceDigest = computeGuidanceDigest(dataset);
  return dataset;
}

function verifyGuidanceDataset(dataset) {
  if (dataset.schema !== DATA_SCHEMA || dataset.partial !== false || dataset.productionReady !== false) {
    throw new reviewBuild.ReviewError("framing guidance data schema 或状态非法");
  }
  if (!Array.isArray(dataset.items) || dataset.items.length < 1 || computeGuidanceDigest(dataset) !== dataset.guidanceDigest) {
    throw new reviewBuild.ReviewError("framing guidance data 行数或 digest 不闭合");
  }
  if (dataset.guidanceSchema !== GUIDANCE_SCHEMA) throw new reviewBuild.ReviewError("guidance schema 不受支持");
  if (
    !Number.isInteger(dataset.renderContract?.targetSupersampleSize) ||
    !Number.isInteger(dataset.renderContract?.minimumSourceCropSize) ||
    typeof dataset.renderContract?.fidelityMeanAbsoluteErrorLimit !== "number"
  ) throw new reviewBuild.ReviewError("framing guidance render contract 不闭合");
  if (dataset.reviewer?.sourceClosureDigest !== sha256Bytes(reviewBuild.stableStringify(dataset.reviewer?.files))) {
    throw new reviewBuild.ReviewError("framing reviewer source closure 不闭合");
  }
  let artifactCount = 0;
  for (const record of Object.values(dataset.parent?.files || {})) {
    reviewBuild.resolveRepoArtifact(record, "guidance parent artifact");
    artifactCount += 1;
  }
  for (const record of dataset.reviewer.files) {
    reviewBuild.resolveRepoArtifact(record, "guidance reviewer source");
    artifactCount += 1;
  }
  const keys = new Set();
  for (const item of dataset.items) {
    if (!item.reviewKey || keys.has(item.reviewKey) || item.humanDecision?.status !== "adjustment") {
      throw new reviewBuild.ReviewError("guidance item 键或父决定非法");
    }
    keys.add(item.reviewKey);
    if (!Array.isArray(item.choices) || item.choices.length !== 2 || new Set(item.choices.map((choice) => choice.sourceRole)).size !== 2) {
      throw new reviewBuild.ReviewError(`guidance choices 不闭合：${item.reviewKey}`);
    }
    if (item.preferredRoleHint !== null && !item.choices.some((choice) => choice.sourceRole === item.preferredRoleHint)) {
      throw new reviewBuild.ReviewError(`preferredRoleHint 非法：${item.reviewKey}`);
    }
    for (const choice of item.choices) {
      if (!Number.isInteger(choice.candidateWidth) || !Number.isInteger(choice.candidateHeight) || choice.candidateWidth < 1 || choice.candidateHeight < 1) {
        throw new reviewBuild.ReviewError(`candidate 尺寸非法：${item.reviewKey}/${choice.sourceRole}`);
      }
      if (
        !Array.isArray(choice.sourceScale) ||
        choice.sourceScale.length !== 2 ||
        choice.sourceScale.some((value) => typeof value !== "number" || !Number.isFinite(value) || value <= 0) ||
        typeof choice.minimumCandidateCropSide !== "number" ||
        !Number.isFinite(choice.minimumCandidateCropSide) ||
        choice.minimumCandidateCropSide <= 0
      ) throw new reviewBuild.ReviewError(`candidate 高分辨率缩放合同非法：${item.reviewKey}/${choice.sourceRole}`);
      for (const [label, record] of [
        ["candidate", choice.sourceCandidate],
        ["high resolution", choice.sourceHighResolution],
        ["master", choice.currentMaster],
        ["preview 80", choice.currentPreviews?.["80"]],
        ["preview 48", choice.currentPreviews?.["48"]],
        ["preview 32", choice.currentPreviews?.["32"]],
      ]) {
        reviewBuild.resolveRepoArtifact(record, `${label} ${item.reviewKey}/${choice.sourceRole}`);
        artifactCount += 1;
      }
    }
    if (item.oldReference) {
      reviewBuild.resolveRepoArtifact(item.oldReference, `old reference ${item.reviewKey}`);
      artifactCount += 1;
    }
  }
  return artifactCount;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.output || (!options.sourceBatch && !options.check) || !options.batchId) {
    process.stdout.write("用法：node tools/portrait-pilot/build-framing-guidance.js --source-batch <reviewed batch> --output <fresh batch> --batch-id <ascii id> [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(options.batchId)) {
    throw new reviewBuild.ReviewError("batch id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符");
  }
  const outputRoot = ensureBelow(options.output, PILOT_ROOT, "输出目录");
  const dataPath = path.join(outputRoot, "framing-guidance-data.json");
  if (options.check) {
    const dataset = readJson(dataPath, "framing guidance data");
    const artifactCount = verifyGuidanceDataset(dataset);
    process.stdout.write(`${JSON.stringify({ status: "framing_guidance_data_verified", guidanceDigest: dataset.guidanceDigest, rows: dataset.items.length, artifactCount })}\n`);
    return;
  }
  if (fs.existsSync(outputRoot)) throw new reviewBuild.ReviewError(`输出目录已存在，禁止覆盖：${outputRoot}`);
  const parent = verifyParent(options.sourceBatch);
  const dataset = buildDataset(parent, options.batchId);
  fs.mkdirSync(outputRoot, { recursive: false });
  fs.writeFileSync(dataPath, `${JSON.stringify(dataset, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  const artifactCount = verifyGuidanceDataset(dataset);
  process.stdout.write(`${JSON.stringify({ status: "framing_guidance_data_built", path: path.relative(ROOT, dataPath).replaceAll("\\", "/"), guidanceDigest: dataset.guidanceDigest, rows: dataset.items.length, artifactCount })}\n`);
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
  DATA_SCHEMA,
  GUIDANCE_SCHEMA,
  computeGuidanceDigest,
  verifyGuidanceDataset,
};
