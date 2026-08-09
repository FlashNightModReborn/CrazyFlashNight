#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const DATA_SCHEMA = "cf7.enemy-portrait-frame-reselection-candidates.v1";
const DECISION_SCHEMA = "cf7.enemy-portrait-frame-reselection-decisions.v1";
const RECEIPT_SCHEMA = "cf7.enemy-portrait-frame-reselection-receipt.v1";

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function exactKeys(value, expected, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new reviewBuild.ReviewError(`${label} 必须是对象`);
  if (reviewBuild.stableStringify(Object.keys(value).sort()) !== reviewBuild.stableStringify([...expected].sort())) {
    throw new reviewBuild.ReviewError(`${label} 字段不闭合`);
  }
}

function readJson(filePath, label) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) throw new reviewBuild.ReviewError(`${label} 缺失：${filePath}`);
  try { return JSON.parse(fs.readFileSync(filePath, "utf8")); }
  catch (error) { throw new reviewBuild.ReviewError(`${label} 不是合法 JSON：${error.message}`); }
}

function verifyDataset(dataset) {
  if (dataset.schema !== DATA_SCHEMA || dataset.phase !== "FRAME_RESELECTION" || dataset.productionReady !== false) {
    throw new reviewBuild.ReviewError("frame reselection data schema 或状态非法");
  }
  const digestInput = { ...dataset };
  delete digestInput.datasetDigest;
  if (sha256Bytes(reviewBuild.stableStringify(digestInput)) !== dataset.datasetDigest) throw new reviewBuild.ReviewError("frame reselection datasetDigest 不匹配");
  if (dataset.decisionSchema !== DECISION_SCHEMA || !Array.isArray(dataset.items) || !dataset.items.length) throw new reviewBuild.ReviewError("frame reselection 决定 schema 或行非法");
  const expectedGates = {
    onlyFrozenWrongPoseRows: true,
    rejectedCurrentFramesNotSelectable: true,
    vectorFramesShownAtLargeSize: true,
    humanFrameSelectionRequired: true,
    localizationRerunRequiredAfterSelection: true,
    modelGeometryNotReused: true,
    productionWrites: false,
  };
  if (reviewBuild.stableStringify(dataset.gates) !== reviewBuild.stableStringify(expectedGates)) throw new reviewBuild.ReviewError("frame reselection gates 漂移");
  let artifactCount = 0;
  for (const record of [...Object.values(dataset.parent.files), ...dataset.reviewer.files]) {
    reviewBuild.resolveRepoArtifact(record, "frame reselection closure");
    artifactCount += 1;
  }
  if (sha256Bytes(reviewBuild.stableStringify(dataset.reviewer.files)) !== dataset.reviewer.sourceClosureDigest) throw new reviewBuild.ReviewError("frame reselection reviewer closure 漂移");
  const reviewKeys = new Set();
  const candidateIds = new Set();
  let candidateCount = 0;
  let rejectedCount = 0;
  for (const item of dataset.items) {
    if (!item.reviewKey || reviewKeys.has(item.reviewKey) || item.variantKey !== "default" || item.humanDecision?.status !== "wrong_pose") throw new reviewBuild.ReviewError("frame reselection 审核行非法");
    reviewKeys.add(item.reviewKey);
    if (!Array.isArray(item.candidates) || item.candidates.length < 2 || !Array.isArray(item.rejectedCandidateIds) || !item.rejectedCandidateIds.length) throw new reviewBuild.ReviewError(`frame reselection 候选或否决集合为空：${item.reviewKey}`);
    const localIds = new Set(item.candidates.map((candidate) => candidate.candidateId));
    if (item.rejectedCandidateIds.some((candidateId) => !localIds.has(candidateId)) || item.rejectedCandidateIds.length >= item.candidates.length) throw new reviewBuild.ReviewError(`frame reselection 否决集合非法：${item.reviewKey}`);
    for (const candidate of item.candidates) {
      if (candidateIds.has(candidate.candidateId) || !Number.isInteger(candidate.frame)) throw new reviewBuild.ReviewError("frame reselection candidateId 重复或帧号非法");
      candidateIds.add(candidate.candidateId);
      reviewBuild.resolveRepoArtifact(candidate.artifact, `frame PNG ${candidate.candidateId}`);
      reviewBuild.resolveRepoArtifact(candidate.vectorArtifact, `frame SVG ${candidate.candidateId}`);
      artifactCount += 2;
      candidateCount += 1;
    }
    rejectedCount += item.rejectedCandidateIds.length;
  }
  const expectedCounts = {
    identityCount: dataset.items.length,
    candidateCount,
    rejectedCandidateCount: rejectedCount,
    selectableCandidateCount: candidateCount - rejectedCount,
  };
  if (reviewBuild.stableStringify(dataset.counts) !== reviewBuild.stableStringify(expectedCounts)) throw new reviewBuild.ReviewError("frame reselection counts 不闭合");
  return artifactCount;
}

function loadBatch(batchPath) {
  const batchRoot = path.resolve(ROOT, batchPath);
  const relative = path.relative(PILOT_ROOT, batchRoot);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) throw new reviewBuild.ReviewError("frame reselection 批次必须位于 tmp/portrait-pilot 下");
  const dataPath = path.join(batchRoot, "frame-reselection-data.json");
  const dataset = readJson(dataPath, "frame reselection data");
  const artifactCount = verifyDataset(dataset);
  return { batchRoot, dataPath, dataset, artifactCount };
}

function validateDecisions(dataset, value) {
  exactKeys(value, ["schema", "batchId", "sourceDigest", "datasetDigest", "complete", "exportedAt", "choices"], "重选帧决定文件");
  if (value.schema !== DECISION_SCHEMA || value.batchId !== dataset.batchId || value.sourceDigest !== dataset.sourceDigest || value.datasetDigest !== dataset.datasetDigest) throw new reviewBuild.ReviewError("重选帧决定属于旧批次或其他闭包");
  if (value.complete !== true || Number.isNaN(Date.parse(value.exportedAt))) throw new reviewBuild.ReviewError("重选帧决定未完整导出");
  exactKeys(value.choices, dataset.items.map((item) => item.reviewKey), "重选帧决定映射");
  const rows = [];
  for (const item of dataset.items) {
    const choice = value.choices[item.reviewKey];
    exactKeys(choice, ["status", "candidateId", "candidateSha256", "vectorArtifactSha256", "frame", "notes", "updatedAt"], `重选帧决定 ${item.reviewKey}`);
    if (!["selected", "expand_search"].includes(choice.status) || Number.isNaN(Date.parse(choice.updatedAt)) || typeof choice.notes !== "string" || choice.notes.length > 1000) throw new reviewBuild.ReviewError(`重选帧状态、时间或备注非法：${item.reviewKey}`);
    const candidate = choice.candidateId === null ? null : item.candidates.find((entry) => entry.candidateId === choice.candidateId);
    if (choice.status === "selected") {
      if (!candidate || item.rejectedCandidateIds.includes(choice.candidateId) || choice.candidateSha256 !== candidate.artifact.sha256 || choice.vectorArtifactSha256 !== candidate.vectorArtifact.sha256 || choice.frame !== candidate.frame) throw new reviewBuild.ReviewError(`选择了未知、已否决或 hash 漂移帧：${item.reviewKey}`);
    } else if (choice.candidateId !== null || choice.candidateSha256 !== null || choice.vectorArtifactSha256 !== null || choice.frame !== null || !choice.notes.trim()) {
      throw new reviewBuild.ReviewError(`继续抽帧必须清空候选并填写备注：${item.reviewKey}`);
    }
    rows.push({
      reviewKey: item.reviewKey,
      portraitRef: item.portraitRef,
      variantKey: "default",
      status: choice.status,
      candidateId: candidate?.candidateId || null,
      frame: candidate?.frame ?? null,
      selectedCandidate: candidate ? { artifact: candidate.artifact, vectorArtifact: candidate.vectorArtifact } : null,
      rejectedCandidateIds: item.rejectedCandidateIds,
      notes: choice.notes,
      updatedAt: choice.updatedAt,
    });
  }
  return { rows, expansionCount: rows.filter((row) => row.status === "expand_search").length };
}

function buildReceipt(loaded, decisionsPath, decisions, validation) {
  const receipt = {
    schema: RECEIPT_SCHEMA,
    status: validation.expansionCount ? "human_frame_search_expansion_required" : "human_frame_reselection_verified",
    productionReady: false,
    batchId: loaded.dataset.batchId,
    sourceDigest: loaded.dataset.sourceDigest,
    datasetDigest: loaded.dataset.datasetDigest,
    parentReceiptDigest: loaded.dataset.parent.receiptDigest,
    exportedAt: decisions.exportedAt,
    verifiedAt: new Date().toISOString(),
    inputs: {
      frameReselectionData: { path: path.relative(ROOT, loaded.dataPath).replaceAll("\\", "/"), bytes: fs.statSync(loaded.dataPath).size, sha256: reviewBuild.sha256File(loaded.dataPath) },
      decisions: { path: path.relative(ROOT, decisionsPath).replaceAll("\\", "/"), bytes: fs.statSync(decisionsPath).size, sha256: reviewBuild.sha256File(decisionsPath) },
    },
    counts: { rows: validation.rows.length, selected: validation.rows.length - validation.expansionCount, expandSearch: validation.expansionCount },
    rows: validation.rows,
    gates: {
      exactParentReceiptBinding: true,
      everyWrongPoseRowDecidedExactlyOnce: true,
      rejectedFramesNotSelected: true,
      selectedFrameHashesClosed: true,
      modelGeometryDiscarded: true,
      localizationRerunRequired: true,
      humanFrameSelectionAccepted: true,
      productionWrites: false,
    },
  };
  receipt.receiptDigest = sha256Bytes(reviewBuild.stableStringify(receipt));
  return receipt;
}

function verifyReceipt(receipt, expected) {
  if (receipt.schema !== RECEIPT_SCHEMA) throw new reviewBuild.ReviewError("重选帧回执 schema 不受支持");
  const digestInput = { ...receipt };
  delete digestInput.receiptDigest;
  if (sha256Bytes(reviewBuild.stableStringify(digestInput)) !== receipt.receiptDigest) throw new reviewBuild.ReviewError("重选帧回执 digest 不匹配");
  if (receipt.sourceDigest !== expected.sourceDigest || receipt.datasetDigest !== expected.datasetDigest || receipt.inputs.frameReselectionData.sha256 !== expected.dataSha256 || receipt.inputs.decisions.sha256 !== expected.decisionsSha256) throw new reviewBuild.ReviewError("重选帧回执与当前输入不一致");
}

function parseArgs(argv) {
  const options = { batch: null, decisions: null, check: false, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--batch", "--decisions"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new reviewBuild.ReviewError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--batch") options.batch = value;
      else options.decisions = value;
    } else if (argument === "--check") options.check = true;
    else if (argument === "--help") options.help = true;
    else throw new reviewBuild.ReviewError(`未知参数：${argument}`);
  }
  return options;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.batch) {
    process.stdout.write("用法：node tools/portrait-pilot/verify-frame-reselection.js --batch <frame reselection batch> [--decisions <json>] [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const loaded = loadBatch(options.batch);
  const decisionsPath = path.resolve(ROOT, options.decisions || path.join(loaded.batchRoot, "portrait-pilot-frame-reselection.json"));
  const relative = path.relative(ROOT, decisionsPath);
  if (relative.startsWith("..") || path.isAbsolute(relative)) throw new reviewBuild.ReviewError("重选帧决定必须位于仓库内");
  const decisions = readJson(decisionsPath, "重选帧决定");
  const validation = validateDecisions(loaded.dataset, decisions);
  const receiptPath = path.join(loaded.batchRoot, "human-frame-reselection-receipt.json");
  const expected = { sourceDigest: loaded.dataset.sourceDigest, datasetDigest: loaded.dataset.datasetDigest, dataSha256: reviewBuild.sha256File(loaded.dataPath), decisionsSha256: reviewBuild.sha256File(decisionsPath) };
  if (options.check) {
    const receipt = readJson(receiptPath, "重选帧回执");
    verifyReceipt(receipt, expected);
    process.stdout.write(`${JSON.stringify({ status: "human_frame_reselection_receipt_verified", receiptDigest: receipt.receiptDigest, rows: receipt.counts.rows, expandSearch: receipt.counts.expandSearch })}\n`);
    return;
  }
  if (fs.existsSync(receiptPath)) throw new reviewBuild.ReviewError("human-frame-reselection-receipt.json 已存在，禁止覆盖");
  const receipt = buildReceipt(loaded, decisionsPath, decisions, validation);
  fs.writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  process.stdout.write(`${JSON.stringify({ status: receipt.status, receiptPath: path.relative(ROOT, receiptPath).replaceAll("\\", "/"), receiptDigest: receipt.receiptDigest, rows: receipt.counts.rows, expandSearch: receipt.counts.expandSearch })}\n`);
}

if (require.main === module) {
  try { main(); } catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = { DATA_SCHEMA, DECISION_SCHEMA, RECEIPT_SCHEMA, verifyDataset, loadBatch, validateDecisions, verifyReceipt };
