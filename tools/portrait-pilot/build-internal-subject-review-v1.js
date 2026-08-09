#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..", "..");
const MANIFEST_SCHEMA = "cf7.enemy-portrait-internal-subject-rescue-candidates.v1";
const REPORT_SCHEMA = "cf7.enemy-portrait-internal-subject-rescue-model-report.v1";
const REVIEW_SCHEMA = "cf7.enemy-portrait-internal-subject-rescue-review-data.v1";
const REVIEWER_SOURCES = [
  path.join(__dirname, "build-internal-subject-review-v1.js"),
  path.join(__dirname, "verify-internal-subject-review-decisions-v1.js"),
  path.join(__dirname, "open-internal-subject-review-v1.js"),
  path.join(ROOT, "launcher", "web", "modules", "portrait-pilot-review", "dev", "internal-subject.html"),
  path.join(ROOT, "launcher", "web", "modules", "portrait-pilot-review", "dev", "internal-subject.css"),
  path.join(ROOT, "launcher", "web", "modules", "portrait-pilot-review", "dev", "internal-subject.js"),
];

class ReviewBuildError extends Error {}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stableValue(value[key])]));
  }
  return value;
}

function stableStringify(value) {
  return JSON.stringify(stableValue(value));
}

function pythonStableStringify(value) {
  if (Array.isArray(value)) return `[${value.map(pythonStableStringify).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${pythonStableStringify(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function sha256File(filePath) {
  return sha256Bytes(fs.readFileSync(filePath));
}

function parseArgs(argv) {
  const options = { batch: null, check: false };
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--batch") {
      options.batch = argv[index + 1];
      index += 1;
    } else if (argv[index] === "--check") {
      options.check = true;
    } else if (argv[index] === "--help") {
      options.help = true;
    } else {
      throw new ReviewBuildError(`未知参数：${argv[index]}`);
    }
  }
  return options;
}

function resolveBatch(batchArgument) {
  if (!batchArgument) throw new ReviewBuildError("必须提供 --batch");
  const absolute = path.resolve(ROOT, batchArgument);
  const pilotRoot = path.join(ROOT, "tmp", "portrait-pilot");
  const relative = path.relative(pilotRoot, absolute);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new ReviewBuildError("batch 必须是 tmp/portrait-pilot 下的具体候选包目录");
  }
  if (!fs.existsSync(absolute) || !fs.statSync(absolute).isDirectory()) {
    throw new ReviewBuildError(`候选包目录不存在：${batchArgument}`);
  }
  return absolute;
}

function resolveArtifact(record, label) {
  if (!record || typeof record.path !== "string" || typeof record.sha256 !== "string" || !Number.isInteger(record.bytes)) {
    throw new ReviewBuildError(`${label} artifact 记录不闭合`);
  }
  const absolute = path.resolve(ROOT, record.path);
  const relative = path.relative(ROOT, absolute);
  if (relative.startsWith("..") || path.isAbsolute(relative)) throw new ReviewBuildError(`${label} 越出仓库`);
  if (!fs.existsSync(absolute) || !fs.statSync(absolute).isFile()) throw new ReviewBuildError(`${label} 缺失：${record.path}`);
  if (fs.statSync(absolute).size !== record.bytes || sha256File(absolute) !== record.sha256) {
    throw new ReviewBuildError(`${label} 字节闭包不匹配：${record.path}`);
  }
  return absolute;
}

function verifyManifest(manifest) {
  if (
    manifest?.schema !== MANIFEST_SCHEMA ||
    manifest.status !== "internal_subject_candidates_ready" ||
    manifest.productionReady !== false ||
    manifest.humanReviewRequired !== true
  ) {
    throw new ReviewBuildError("候选 manifest schema/status 不受支持");
  }
  const copy = { ...manifest };
  delete copy.manifestDigest;
  if (sha256Bytes(pythonStableStringify(copy)) !== manifest.manifestDigest) throw new ReviewBuildError("manifestDigest 漂移");
  if (sha256Bytes(pythonStableStringify(manifest.inputs)) !== manifest.sourceDigest) throw new ReviewBuildError("sourceDigest 漂移");
  if (
    manifest.gates?.complexitySelectsProductionSubject !== false ||
    manifest.gates?.productionWrites !== false ||
    manifest.rankingContract?.complexityUse !== "candidate_recall_prior_only" ||
    manifest.rankingContract?.humanFinalDecisionRequired !== true
  ) {
    throw new ReviewBuildError("候选 manifest 安全门不闭合");
  }
  resolveArtifact(manifest.contactSheet, "complete contact sheet");
  for (const batch of manifest.modelBatches || []) resolveArtifact(batch.contactSheet, `model batch ${batch.modelBatchId}`);
  for (const item of manifest.reviewItems || []) {
    for (const candidate of item.candidates || []) resolveArtifact(candidate.artifact, `candidate ${candidate.candidateId}`);
  }
}

function verifyReport(report, manifest, manifestPath) {
  if (
    report?.schema !== REPORT_SCHEMA ||
    report.status !== "subject_candidates_proposed" ||
    report.productionReady !== false ||
    report.humanReviewRequired !== true ||
    report.batchId !== manifest.batchId ||
    report.sourceDigest !== manifest.sourceDigest ||
    report.manifestDigest !== manifest.manifestDigest
  ) {
    throw new ReviewBuildError("模型报告 schema/status/source 绑定不闭合");
  }
  const copy = { ...report };
  delete copy.reportDigest;
  if (sha256Bytes(stableStringify(copy)) !== report.reportDigest) throw new ReviewBuildError("模型 reportDigest 漂移");
  if (
    report.gates?.complexityUsedForRecallOnly !== true ||
    report.gates?.allCandidatesComparedByMultimodalModel !== true ||
    report.gates?.automaticPromotion !== false ||
    report.gates?.humanArtAcceptance !== false ||
    report.gates?.productionWrites !== false
  ) {
    throw new ReviewBuildError("模型报告安全门不闭合");
  }
  if (
    report.input?.manifest?.sha256 !== sha256File(manifestPath) ||
    report.input?.manifest?.bytes !== fs.statSync(manifestPath).size
  ) {
    throw new ReviewBuildError("模型报告未绑定当前 manifest 字节");
  }
  if (!Array.isArray(report.runs) || report.runs.length !== 2 || report.runs.map((run) => run.role).sort().join(",") !== "independent_review,proposal") {
    throw new ReviewBuildError("模型报告缺 A/B 独立角色");
  }
  for (const record of report.controller?.files || []) resolveArtifact(record, "model controller source");
  for (const record of report.modelArtifacts || []) resolveArtifact(record, "model process artifact");
}

function reviewerEvidence() {
  const files = REVIEWER_SOURCES.map((filePath) => {
    if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
      throw new ReviewBuildError(`reviewer source 缺失：${path.relative(ROOT, filePath)}`);
    }
    return {
      path: path.relative(ROOT, filePath).replaceAll("\\", "/"),
      bytes: fs.statSync(filePath).size,
      sha256: sha256File(filePath),
    };
  });
  return {
    version: "internal-subject-human-review-v1",
    files,
    sourceClosureDigest: sha256Bytes(stableStringify(files)),
  };
}

function loadBatch(batchArgument) {
  const batchRoot = resolveBatch(batchArgument);
  const manifestPath = path.join(batchRoot, "internal-subject-rescue-manifest.json");
  const reportPath = path.join(batchRoot, "internal-subject-model-report.json");
  if (!fs.existsSync(manifestPath) || !fs.existsSync(reportPath)) {
    throw new ReviewBuildError("候选包缺 manifest 或 Luna A/B 模型报告");
  }
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  verifyManifest(manifest);
  verifyReport(report, manifest, manifestPath);
  return { batchRoot, manifestPath, reportPath, manifest, report };
}

function buildDataset(loaded) {
  const runByRole = new Map(loaded.report.runs.map((run) => [run.role, run]));
  const proposal = new Map(runByRole.get("proposal").selections.map((row) => [row.reviewKey, row]));
  const independent = new Map(runByRole.get("independent_review").selections.map((row) => [row.reviewKey, row]));
  const comparisons = new Map(loaded.report.comparisons.map((row) => [row.reviewKey, row]));
  const items = loaded.manifest.reviewItems.map((item) => {
    const left = proposal.get(item.reviewKey);
    const right = independent.get(item.reviewKey);
    const comparison = comparisons.get(item.reviewKey);
    if (!left || !right || !comparison) throw new ReviewBuildError(`模型报告缺审核项：${item.reviewKey}`);
    return {
      reviewCode: item.reviewCode,
      reviewKey: item.reviewKey,
      portraitRef: item.portraitRef,
      variantKey: item.variantKey,
      sourceSwf: item.sourceSwf,
      rootCharacterId: item.rootCharacterId,
      candidates: item.candidates.map((candidate, index) => ({
        contactSheetLabel: `C${String(index + 1).padStart(2, "0")}`,
        candidateId: candidate.candidateId,
        spriteId: candidate.spriteId,
        frame: candidate.frame,
        width: candidate.width,
        height: candidate.height,
        complexityTier: candidate.complexityTier,
        complexityRank: candidate.complexityRank,
        initialRootFrameCandidate: candidate.initialRootFrameCandidate,
        displayPathText: candidate.displayPathText,
        artifact: candidate.artifact,
      })),
      model: {
        proposal: left,
        independentReview: right,
        comparison,
      },
    };
  });
  const dataset = {
    schema: REVIEW_SCHEMA,
    status: "awaiting_human_subject_selection",
    productionReady: false,
    humanReviewRequired: true,
    generatedAt: new Date().toISOString(),
    batchId: loaded.manifest.batchId,
    sourceDigest: loaded.manifest.sourceDigest,
    manifestDigest: loaded.manifest.manifestDigest,
    modelReportDigest: loaded.report.reportDigest,
    reviewer: reviewerEvidence(),
    decisionSchema: "cf7.enemy-portrait-internal-subject-human-decisions.v1",
    instructions: {
      complexitySemantics: "复杂度仅决定候选召回顺序，不代表美术正确性。",
      selectionSemantics: "选择包含完整连贯怪物主体的内部影片剪辑；拒绝纯武器、纯特效、阴影、矩形与 UI。",
      persistenceSemantics: "每次点击会在专用浏览器配置中自动暂存；17 项全部裁决后才能保存正式决策文件。",
      productionSemantics: "本页只冻结主体影片剪辑，不导出 SVG、不裁剪头像、不写入生产清单。",
    },
    counts: {
      identityCount: items.length,
      candidateCount: items.reduce((sum, item) => sum + item.candidates.length, 0),
      candidateAgreement: items.filter((item) => item.model.comparison.candidateAgreement).length,
      highlightedForHuman: items.filter((item) => item.model.comparison.highlightedForHuman).length,
    },
    items,
    gates: {
      noModelPreselectionApplied: true,
      explicitHumanClickRequiredPerIdentity: true,
      modelDisagreementHighlighted: true,
      modelReasonsVisible: true,
      allComplexityTiersVisible: true,
      automaticPromotion: false,
      vectorExportDeferred: true,
      productionWrites: false,
    },
  };
  dataset.reviewDigest = sha256Bytes(stableStringify(dataset));
  return dataset;
}

function verifyReviewDataset(dataset) {
  if (
    dataset?.schema !== REVIEW_SCHEMA ||
    dataset.status !== "awaiting_human_subject_selection" ||
    dataset.productionReady !== false ||
    dataset.humanReviewRequired !== true ||
    !Array.isArray(dataset.items) ||
    dataset.items.length < 1
  ) {
    throw new ReviewBuildError("review-data schema/status 非法");
  }
  const copy = { ...dataset };
  delete copy.reviewDigest;
  if (sha256Bytes(stableStringify(copy)) !== dataset.reviewDigest) throw new ReviewBuildError("reviewDigest 漂移");
  for (const record of dataset.reviewer?.files || []) resolveArtifact(record, "reviewer source");
  for (const item of dataset.items) {
    for (const candidate of item.candidates) resolveArtifact(candidate.artifact, `review candidate ${candidate.candidateId}`);
  }
  return dataset.items.reduce((sum, item) => sum + item.candidates.length, 0) + dataset.reviewer.files.length;
}

function writeExclusive(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.batch) {
    process.stdout.write("用法：node tools/portrait-pilot/build-internal-subject-review-v1.js --batch <tmp/portrait-pilot/...> [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const loaded = loadBatch(options.batch);
  const reviewPath = path.join(loaded.batchRoot, "internal-subject-review-data.json");
  if (options.check) {
    if (!fs.existsSync(reviewPath)) throw new ReviewBuildError("internal-subject-review-data.json 缺失");
    const dataset = JSON.parse(fs.readFileSync(reviewPath, "utf8"));
    const artifactCount = verifyReviewDataset(dataset);
    if (
      dataset.sourceDigest !== loaded.manifest.sourceDigest ||
      dataset.manifestDigest !== loaded.manifest.manifestDigest ||
      dataset.modelReportDigest !== loaded.report.reportDigest
    ) {
      throw new ReviewBuildError("review-data 未绑定当前 manifest/model report");
    }
    process.stdout.write(`${JSON.stringify({
      status: "internal_subject_review_verified",
      reviewDigest: dataset.reviewDigest,
      identities: dataset.items.length,
      candidates: dataset.counts.candidateCount,
      artifactCount,
    })}\n`);
    return;
  }
  if (fs.existsSync(reviewPath)) throw new ReviewBuildError("internal-subject-review-data.json 已存在，拒绝覆盖");
  const dataset = buildDataset(loaded);
  verifyReviewDataset(dataset);
  writeExclusive(reviewPath, dataset);
  process.stdout.write(`${JSON.stringify({
    status: dataset.status,
    reviewPath,
    reviewDigest: dataset.reviewDigest,
    counts: dataset.counts,
  })}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error && error.stack ? error.stack : String(error)}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  buildDataset,
  loadBatch,
  sha256Bytes,
  stableStringify,
  verifyReviewDataset,
};
