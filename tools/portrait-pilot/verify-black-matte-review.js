#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const DATA_SCHEMA = "cf7.enemy-portrait-black-matte-candidates.v1";
const DECISION_SCHEMA = "cf7.enemy-portrait-black-matte-decisions.v1";
const RECEIPT_SCHEMA = "cf7.enemy-portrait-black-matte-receipt.v1";
const DATA_NAME = "black-matte-review-data.json";
const DECISIONS_NAME = "portrait-pilot-black-matte-decisions.json";
const RECEIPT_NAME = "human-black-matte-review-receipt.json";

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

function verifyDigest(value, field, label) {
  const digest = value?.[field];
  if (typeof digest !== "string") throw new reviewBuild.ReviewError(`${label} 缺 ${field}`);
  const envelope = { ...value };
  delete envelope[field];
  if (sha256Bytes(reviewBuild.stableStringify(envelope)) !== digest) throw new reviewBuild.ReviewError(`${label} ${field} 不匹配`);
}

function verifyArtifact(record, label) {
  reviewBuild.resolveRepoArtifact(record, label);
  return 1;
}

function verifyDataset(dataset) {
  if (
    dataset?.schema !== DATA_SCHEMA ||
    dataset.phase !== "BLACK_MATTE_HUMAN_REVIEW" ||
    dataset.status !== "black_matte_candidates_ready" ||
    dataset.productionReady !== false ||
    dataset.decisionSchema !== DECISION_SCHEMA
  ) throw new reviewBuild.ReviewError("black matte dataset schema 或状态非法");
  verifyDigest(dataset, "datasetDigest", "black matte dataset");
  const expectedGates = {
    onlyFrozenHumanPostprocessRow: true,
    currentFrameRetained: true,
    noModelCall: true,
    exactFormulaRecorded: true,
    highResolution4096Retained: true,
    blackCompositeMaximumErrorLte2: true,
    humanCandidateSelectionRequired: true,
    productionWrites: false,
  };
  if (reviewBuild.stableStringify(dataset.gates) !== reviewBuild.stableStringify(expectedGates)) throw new reviewBuild.ReviewError("black matte gates 漂移");
  if (!dataset.parent || !dataset.reviewer || !dataset.policy) throw new reviewBuild.ReviewError("black matte parent/reviewer/policy 缺失");
  let artifactCount = 0;
  for (const [name, record] of Object.entries(dataset.parent.files || {})) artifactCount += verifyArtifact(record, `black matte parent ${name}`);
  if (!Array.isArray(dataset.reviewer.files) || !dataset.reviewer.files.length) throw new reviewBuild.ReviewError("black matte reviewer files 为空");
  for (const record of dataset.reviewer.files) artifactCount += verifyArtifact(record, "black matte reviewer file");
  if (sha256Bytes(reviewBuild.stableStringify(dataset.reviewer.files)) !== dataset.reviewer.sourceClosureDigest) throw new reviewBuild.ReviewError("black matte reviewer source closure 漂移");
  if (
    dataset.policy.formula !== "v=max(R,G,B)/255; m=v^gamma; A'=A*m; RGB'=RGB/m when m>0 else 0" ||
    dataset.policy.applicationStage !== "4096px retained supersample before 512/80/48/32 output pyramid" ||
    !Array.isArray(dataset.policy.variants) || dataset.policy.variants.length !== 3
  ) throw new reviewBuild.ReviewError("black matte 公式或输出阶段漂移");
  if (!Array.isArray(dataset.items) || dataset.items.length !== 1) throw new reviewBuild.ReviewError("black matte 必须恰有一个审核项");
  const item = dataset.items[0];
  if (
    !item.reviewKey || item.variantKey !== "default" || item.category !== "postprocess_black_matte" ||
    item.humanDecision?.status !== "wrong_pose" || !Array.isArray(item.originals) || item.originals.length !== 2 ||
    !Array.isArray(item.candidates) || item.candidates.length !== 6
  ) throw new reviewBuild.ReviewError("black matte 审核项非法");
  for (const original of item.originals) {
    if (!["proposal", "independent_review"].includes(original.role)) throw new reviewBuild.ReviewError("black matte original role 非法");
    artifactCount += verifyArtifact(original.master, "black matte original master");
    artifactCount += verifyArtifact(original.sourceSupersample, "black matte original supersample");
    if (reviewBuild.stableStringify(Object.keys(original.previews || {}).sort()) !== reviewBuild.stableStringify(["32", "48", "80"])) {
      throw new reviewBuild.ReviewError("black matte original preview 集合漂移");
    }
    for (const record of Object.values(original.previews)) artifactCount += verifyArtifact(record, "black matte original preview");
  }
  const ids = new Set();
  const roleGamma = new Set();
  for (const candidate of item.candidates) {
    verifyDigest(candidate, "candidateDigest", `black matte candidate ${candidate.candidateId}`);
    const key = `${candidate.role}:${candidate.gamma}`;
    if (
      typeof candidate.candidateId !== "string" || ids.has(candidate.candidateId) ||
      !["proposal", "independent_review"].includes(candidate.role) ||
      ![0.5, 0.75, 1].includes(candidate.gamma) || roleGamma.has(key) ||
      candidate.recommended !== (candidate.gamma === 0.75)
    ) throw new reviewBuild.ReviewError("black matte candidate id/role/gamma 非法");
    ids.add(candidate.candidateId);
    roleGamma.add(key);
    artifactCount += verifyArtifact(candidate.sourceSupersample, "black matte candidate source");
    artifactCount += verifyArtifact(candidate.sourceGeometrySvg, "black matte candidate SVG");
    const outputKeys = Object.keys(candidate.outputs || {}).sort();
    if (reviewBuild.stableStringify(outputKeys) !== reviewBuild.stableStringify(["master512", "preview32", "preview48", "preview80", "supersample4096"])) {
      throw new reviewBuild.ReviewError("black matte candidate 输出金字塔漂移");
    }
    for (const record of Object.values(candidate.outputs)) artifactCount += verifyArtifact(record, "black matte candidate output");
    if (
      typeof candidate.metrics?.blackCompositeMeanAbsoluteError !== "number" ||
      candidate.metrics.blackCompositeMaximumAbsoluteError > 2 ||
      candidate.metrics.transparentPixelFraction < 0 || candidate.metrics.transparentPixelFraction > 1
    ) throw new reviewBuild.ReviewError("black matte candidate 指标非法");
  }
  const expectedCounts = { identityCount: 1, originalCount: 2, candidateCount: 6, roleCount: 2, recommendedCandidateCount: 2 };
  if (reviewBuild.stableStringify(dataset.counts) !== reviewBuild.stableStringify(expectedCounts)) throw new reviewBuild.ReviewError("black matte counts 不闭合");
  return artifactCount;
}

function loadBatch(batchPath) {
  const batchRoot = path.resolve(ROOT, batchPath);
  const relative = path.relative(PILOT_ROOT, batchRoot);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) throw new reviewBuild.ReviewError("black matte 批次必须位于 tmp/portrait-pilot 下");
  const dataPath = path.join(batchRoot, DATA_NAME);
  const dataset = readJson(dataPath, "black matte data");
  const artifactCount = verifyDataset(dataset);
  return { batchRoot, dataPath, dataset, artifactCount };
}

function candidateFor(item, candidateId) {
  return item.candidates.find((candidate) => candidate.candidateId === candidateId) || null;
}

function validateDecisions(dataset, value) {
  exactKeys(value, ["schema", "batchId", "sourceDigest", "datasetDigest", "complete", "exportedAt", "choices"], "black matte 决定文件");
  if (
    value.schema !== DECISION_SCHEMA || value.batchId !== dataset.batchId || value.sourceDigest !== dataset.sourceDigest ||
    value.datasetDigest !== dataset.datasetDigest || value.complete !== true || Number.isNaN(Date.parse(value.exportedAt))
  ) throw new reviewBuild.ReviewError("black matte 决定未完整导出或属于其他闭包");
  exactKeys(value.choices, dataset.items.map((item) => item.reviewKey), "black matte 决定映射");
  const rows = [];
  for (const item of dataset.items) {
    const choice = value.choices[item.reviewKey];
    exactKeys(choice, ["status", "candidateId", "candidateDigest", "outputSupersampleSha256", "master512Sha256", "notes", "updatedAt"], `black matte 决定 ${item.reviewKey}`);
    if (!['selected', 'refine'].includes(choice.status) || Number.isNaN(Date.parse(choice.updatedAt)) || typeof choice.notes !== "string" || choice.notes.length > 1000) {
      throw new reviewBuild.ReviewError(`black matte 状态、时间或备注非法：${item.reviewKey}`);
    }
    const candidate = choice.candidateId === null ? null : candidateFor(item, choice.candidateId);
    if (choice.status === "selected") {
      if (
        !candidate || choice.candidateDigest !== candidate.candidateDigest ||
        choice.outputSupersampleSha256 !== candidate.outputs.supersample4096.sha256 ||
        choice.master512Sha256 !== candidate.outputs.master512.sha256
      ) throw new reviewBuild.ReviewError(`black matte 选择未知或 hash 漂移：${item.reviewKey}`);
    } else if (
      choice.candidateId !== null || choice.candidateDigest !== null || choice.outputSupersampleSha256 !== null ||
      choice.master512Sha256 !== null || !choice.notes.trim()
    ) throw new reviewBuild.ReviewError(`black matte 继续调参必须清空候选并填写备注：${item.reviewKey}`);
    rows.push({
      reviewKey: item.reviewKey,
      portraitRef: item.portraitRef,
      variantKey: item.variantKey,
      status: choice.status,
      candidateId: candidate?.candidateId || null,
      candidateDigest: candidate?.candidateDigest || null,
      role: candidate?.role || null,
      gamma: candidate?.gamma ?? null,
      selectedOutputs: candidate?.outputs || null,
      notes: choice.notes,
      updatedAt: choice.updatedAt,
    });
  }
  return { rows, refineCount: rows.filter((row) => row.status === "refine").length };
}

function buildReceipt(loaded, decisionsPath, decisions, validation) {
  const receipt = {
    schema: RECEIPT_SCHEMA,
    status: validation.refineCount ? "human_black_matte_refinement_required" : "human_black_matte_candidate_verified",
    productionReady: false,
    batchId: loaded.dataset.batchId,
    sourceDigest: loaded.dataset.sourceDigest,
    datasetDigest: loaded.dataset.datasetDigest,
    parentReceiptDigest: loaded.dataset.parent.receiptDigest,
    exportedAt: decisions.exportedAt,
    verifiedAt: new Date().toISOString(),
    inputs: {
      blackMatteData: { path: path.relative(ROOT, loaded.dataPath).replaceAll("\\", "/"), bytes: fs.statSync(loaded.dataPath).size, sha256: reviewBuild.sha256File(loaded.dataPath) },
      decisions: { path: path.relative(ROOT, decisionsPath).replaceAll("\\", "/"), bytes: fs.statSync(decisionsPath).size, sha256: reviewBuild.sha256File(decisionsPath) },
    },
    counts: { rows: validation.rows.length, selected: validation.rows.length - validation.refineCount, refine: validation.refineCount },
    rows: validation.rows,
    gates: {
      exactParentReceiptBinding: true,
      everyPostprocessRowDecidedExactlyOnce: true,
      selectedCandidateHashesClosed: true,
      exactFormulaAnd4096SourceBound: true,
      humanBlackMatteSelectionAccepted: true,
      productionWrites: false,
    },
  };
  receipt.receiptDigest = sha256Bytes(reviewBuild.stableStringify(receipt));
  return receipt;
}

function verifyReceipt(receipt, expected) {
  if (receipt.schema !== RECEIPT_SCHEMA || receipt.productionReady !== false) throw new reviewBuild.ReviewError("black matte 回执 schema 或状态不受支持");
  verifyDigest(receipt, "receiptDigest", "black matte 回执");
  if (
    receipt.sourceDigest !== expected.sourceDigest || receipt.datasetDigest !== expected.datasetDigest ||
    receipt.inputs.blackMatteData.sha256 !== expected.dataSha256 || receipt.inputs.decisions.sha256 !== expected.decisionsSha256 ||
    receipt.gates?.productionWrites !== false
  ) throw new reviewBuild.ReviewError("black matte 回执与当前输入不一致");
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
    process.stdout.write("用法：node tools/portrait-pilot/verify-black-matte-review.js --batch <black matte batch> [--decisions <json>] [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const loaded = loadBatch(options.batch);
  const decisionsPath = path.resolve(ROOT, options.decisions || path.join(loaded.batchRoot, DECISIONS_NAME));
  const relative = path.relative(ROOT, decisionsPath);
  if (relative.startsWith("..") || path.isAbsolute(relative)) throw new reviewBuild.ReviewError("black matte 决定必须位于仓库内");
  const decisions = readJson(decisionsPath, "black matte 决定");
  const validation = validateDecisions(loaded.dataset, decisions);
  const receiptPath = path.join(loaded.batchRoot, RECEIPT_NAME);
  const expected = {
    sourceDigest: loaded.dataset.sourceDigest,
    datasetDigest: loaded.dataset.datasetDigest,
    dataSha256: reviewBuild.sha256File(loaded.dataPath),
    decisionsSha256: reviewBuild.sha256File(decisionsPath),
  };
  if (options.check) {
    const receipt = readJson(receiptPath, "black matte 回执");
    verifyReceipt(receipt, expected);
    process.stdout.write(`${JSON.stringify({ status: "human_black_matte_receipt_verified", receiptDigest: receipt.receiptDigest, rows: receipt.counts.rows, refine: receipt.counts.refine })}\n`);
    return;
  }
  if (fs.existsSync(receiptPath)) throw new reviewBuild.ReviewError(`${RECEIPT_NAME} 已存在，禁止覆盖`);
  const receipt = buildReceipt(loaded, decisionsPath, decisions, validation);
  fs.writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  process.stdout.write(`${JSON.stringify({ status: receipt.status, receiptPath: path.relative(ROOT, receiptPath).replaceAll("\\", "/"), receiptDigest: receipt.receiptDigest, rows: receipt.counts.rows, refine: receipt.counts.refine })}\n`);
}

if (require.main === module) {
  try { main(); } catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  DATA_SCHEMA,
  DECISION_SCHEMA,
  RECEIPT_SCHEMA,
  DATA_NAME,
  DECISIONS_NAME,
  RECEIPT_NAME,
  verifyDataset,
  loadBatch,
  validateDecisions,
  verifyReceipt,
};
