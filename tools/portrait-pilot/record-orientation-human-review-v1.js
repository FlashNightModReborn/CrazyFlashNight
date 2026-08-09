#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { sha256Bytes, sha256File, stableStringify } = require("../portrait-worker/lib/codex-cli-luna-worker");
const reviewBuild = require("./build-orientation-human-review-v1");
const decisionVerifier = require("./verify-orientation-human-decisions-v1");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const MANIFEST_PATH = path.join(ROOT, "launcher", "web", "assets", "enemy-portraits", "manifest.json");
const PROMOTION_RECEIPT_PATH = path.join(ROOT, "launcher", "web", "assets", "enemy-portraits", "promotion-receipt.json");
const REVIEW_NAME = "orientation-human-review-data.json";
const DECISIONS_NAME = "portrait-orientation-human-decisions.json";
const RECEIPT_NAME = "orientation-human-review-receipt.json";
const SOURCE_MANIFEST_NAME = "source-production-manifest.json";
const SOURCE_PROMOTION_RECEIPT_NAME = "source-production-promotion-receipt.json";

class RecordError extends Error {}

function parseArgs(argv) {
  const options = { command: argv[0], reviewRoot: null, decisions: null };
  for (let index = 1; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--review-root", "--decisions"].includes(argument)) {
      const next = argv[index + 1];
      if (!next || next.startsWith("--")) throw new RecordError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--review-root") options.reviewRoot = next;
      else options.decisions = next;
    } else if (argument === "--help") options.help = true;
    else throw new RecordError(`未知参数：${argument}`);
  }
  return options;
}

function reviewRoot(value) {
  const resolved = path.resolve(ROOT, value);
  const relative = path.relative(PILOT_ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative) || !fs.existsSync(resolved)) {
    throw new RecordError("review-root 必须是 tmp/portrait-pilot 下的现有批次");
  }
  return resolved;
}

function readObject(filePath, label) {
  try {
    const value = JSON.parse(fs.readFileSync(filePath, "utf8"));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("顶层不是对象");
    return value;
  } catch (error) {
    throw new RecordError(`${label}不可读：${filePath}: ${error.message}`);
  }
}

function artifact(filePath) {
  const resolved = path.resolve(filePath);
  const relative = path.relative(ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative) || !fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    throw new RecordError(`artifact 越界或缺失：${filePath}`);
  }
  return {
    path: relative.replaceAll("\\", "/"),
    bytes: fs.statSync(resolved).size,
    sha256: sha256File(resolved),
  };
}

function verifyArtifact(record, label) {
  if (!record || typeof record.path !== "string" || typeof record.bytes !== "number" || typeof record.sha256 !== "string") {
    throw new RecordError(`${label} artifact 非法`);
  }
  const resolved = path.resolve(ROOT, record.path);
  const actual = artifact(resolved);
  if (actual.bytes !== record.bytes || actual.sha256 !== record.sha256) throw new RecordError(`${label} artifact 漂移`);
  return resolved;
}

function digestObject(value, field) {
  const clone = { ...value };
  delete clone[field];
  return sha256Bytes(stableStringify(clone));
}

function writeExclusive(filePath, bytes) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, bytes, { flag: "wx" });
}

function copyExclusive(source, target) {
  writeExclusive(target, fs.readFileSync(source));
}

function sourceManifestDigest(manifest) {
  if (manifest.schema !== "cf7.enemy-portrait-manifest.v1" || typeof manifest.manifestDigest !== "string") {
    throw new RecordError("当前生产 manifest schema/digest 非法");
  }
  return manifest.manifestDigest;
}

function validateReceipt(batchRoot, receipt) {
  if (
    receipt.schema !== "cf7.portrait-orientation-human-review-receipt.v1" ||
    receipt.status !== "human_orientation_reviewed" ||
    receipt.productionReady !== false ||
    digestObject(receipt, "receiptDigest") !== receipt.receiptDigest
  ) throw new RecordError("方向真人回执 schema/status/digest 非法");
  const reviewPath = verifyArtifact(receipt.inputs.reviewData, "review data");
  const dataset = reviewBuild.verifyData(readObject(reviewPath, "review data"));
  const decisionsPath = verifyArtifact(receipt.inputs.decisions, "canonical decisions");
  const archivedPath = verifyArtifact(receipt.inputs.archivedDecisions, "archived decisions");
  if (!fs.readFileSync(decisionsPath).equals(fs.readFileSync(archivedPath))) throw new RecordError("canonical/archive decisions 字节不一致");
  const decisions = readObject(decisionsPath, "orientation decisions");
  const verified = decisionVerifier.validateDecisions(dataset, decisions);
  const sourceManifestPath = verifyArtifact(receipt.inputs.sourceProductionManifest, "source production manifest");
  const sourceManifest = readObject(sourceManifestPath, "source production manifest");
  verifyArtifact(receipt.inputs.sourceProductionPromotionReceipt, "source production receipt");
  verifyArtifact(receipt.inputs.modelReport, "model report");
  verifyArtifact(receipt.inputs.visualAuditManifest, "visual audit manifest");
  for (const record of receipt.inputs.controllers || []) verifyArtifact(record, "orientation receipt controller");
  if (
    sourceManifestDigest(sourceManifest) !== dataset.sourceDigest ||
    receipt.sourceDigest !== dataset.sourceDigest ||
    receipt.modelReportDigest !== dataset.modelReportDigest ||
    receipt.reviewDigest !== dataset.reviewDigest ||
    receipt.counts.total !== verified.counts.total ||
    receipt.counts.keep !== verified.counts.keep ||
    receipt.counts.flipX !== verified.counts.flipX ||
    receipt.counts.modelClosedKeepOutsideReview !== dataset.counts.modelClosedKeepOutsideReview
  ) throw new RecordError("方向真人回执摘要或计数未闭合");
  const expectedFlips = decisions.decisions.filter((row) => row.action === "flip_x").map((row) => row.reviewKey).sort();
  if (JSON.stringify(receipt.flipReviewKeys) !== JSON.stringify(expectedFlips)) throw new RecordError("方向真人回执 flip 集合漂移");
  if (
    receipt.gates?.allRiskRowsHumanReviewed !== true ||
    receipt.gates?.modelClosedKeepsRemainModelEvidence !== true ||
    receipt.gates?.relativeFlipSemanticsFrozen !== true ||
    receipt.gates?.noProductionWrites !== true
  ) throw new RecordError("方向真人回执 gates 未闭合");
  return { dataset, decisions, counts: verified.counts };
}

function record(batchRoot, decisionsArgument) {
  const reviewPath = path.join(batchRoot, REVIEW_NAME);
  const dataset = reviewBuild.verifyData(readObject(reviewPath, "orientation review data"));
  const decisionsSource = path.resolve(ROOT, decisionsArgument);
  const decisions = readObject(decisionsSource, "orientation decisions export");
  const verified = decisionVerifier.validateDecisions(dataset, decisions);
  const currentManifest = readObject(MANIFEST_PATH, "current production manifest");
  if (sourceManifestDigest(currentManifest) !== dataset.sourceDigest) {
    throw new RecordError(`导出绑定的 sourceDigest 已不是当前生产包：${dataset.sourceDigest} != ${currentManifest.manifestDigest}`);
  }
  const currentPromotionReceipt = readObject(PROMOTION_RECEIPT_PATH, "current production promotion receipt");
  if (currentPromotionReceipt.manifestDigest !== currentManifest.manifestDigest) throw new RecordError("当前 promotion receipt 与 manifest 不一致");

  const canonicalPath = path.join(batchRoot, DECISIONS_NAME);
  const stamp = decisions.exportedAt.replace(/[^0-9A-Za-z]/g, "");
  const archivePath = path.join(batchRoot, "orientation-decision-exports", `portrait-orientation-human-decisions-${stamp}.json`);
  const sourceManifestPath = path.join(batchRoot, SOURCE_MANIFEST_NAME);
  const sourcePromotionReceiptPath = path.join(batchRoot, SOURCE_PROMOTION_RECEIPT_NAME);
  const receiptPath = path.join(batchRoot, RECEIPT_NAME);
  for (const target of [canonicalPath, archivePath, sourceManifestPath, sourcePromotionReceiptPath, receiptPath]) {
    if (fs.existsSync(target)) throw new RecordError(`输出已存在，拒绝覆盖：${target}`);
  }
  copyExclusive(decisionsSource, canonicalPath);
  copyExclusive(decisionsSource, archivePath);
  copyExclusive(MANIFEST_PATH, sourceManifestPath);
  copyExclusive(PROMOTION_RECEIPT_PATH, sourcePromotionReceiptPath);

  const receipt = {
    schema: "cf7.portrait-orientation-human-review-receipt.v1",
    status: "human_orientation_reviewed",
    productionReady: false,
    generatedAt: new Date().toISOString(),
    batchId: dataset.batchId,
    sourceDigest: dataset.sourceDigest,
    modelReportDigest: dataset.modelReportDigest,
    reviewDigest: dataset.reviewDigest,
    decisionSchema: dataset.decisionSchema,
    counts: {
      total: verified.counts.total,
      keep: verified.counts.keep,
      flipX: verified.counts.flipX,
      modelClosedKeepOutsideReview: dataset.counts.modelClosedKeepOutsideReview,
    },
    flipReviewKeys: decisions.decisions.filter((row) => row.action === "flip_x").map((row) => row.reviewKey).sort(),
    inputs: {
      reviewData: artifact(reviewPath),
      modelReport: dataset.input.modelReport,
      visualAuditManifest: dataset.input.auditManifest,
      decisions: artifact(canonicalPath),
      archivedDecisions: artifact(archivePath),
      sourceProductionManifest: artifact(sourceManifestPath),
      sourceProductionPromotionReceipt: artifact(sourcePromotionReceiptPath),
      controllers: [
        artifact(__filename),
        artifact(path.join(__dirname, "build-orientation-human-review-v1.js")),
        artifact(path.join(__dirname, "verify-orientation-human-decisions-v1.js")),
      ],
    },
    semantics: {
      keep: "retain the exact source production orientation",
      flip_x: "mirror the exact source production orientation once; toggle rather than overwrite the underlying action",
    },
    gates: {
      allRiskRowsHumanReviewed: true,
      modelClosedKeepsRemainModelEvidence: true,
      relativeFlipSemanticsFrozen: true,
      canonicalAndArchiveByteIdentical: true,
      sourceProductionSnapshotFrozen: true,
      noProductionWrites: true,
    },
  };
  receipt.receiptDigest = digestObject(receipt, "receiptDigest");
  writeExclusive(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`);
  validateReceipt(batchRoot, readObject(receiptPath, "orientation receipt"));
  return { receipt, receiptPath };
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !["record", "check"].includes(options.command) || !options.reviewRoot || (options.command === "record" && !options.decisions)) {
    process.stdout.write("用法：node tools/portrait-pilot/record-orientation-human-review-v1.js record --review-root <r204> --decisions <export.json> | check --review-root <r204>\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const batchRoot = reviewRoot(options.reviewRoot);
  if (options.command === "record") {
    const result = record(batchRoot, options.decisions);
    process.stdout.write(`${JSON.stringify({
      status: "orientation_human_review_recorded",
      receipt: path.relative(ROOT, result.receiptPath).replaceAll("\\", "/"),
      receiptDigest: result.receipt.receiptDigest,
      counts: result.receipt.counts,
      flipReviewKeys: result.receipt.flipReviewKeys,
    })}\n`);
    return;
  }
  const receiptPath = path.join(batchRoot, RECEIPT_NAME);
  const receipt = readObject(receiptPath, "orientation receipt");
  const verified = validateReceipt(batchRoot, receipt);
  process.stdout.write(`${JSON.stringify({
    status: "orientation_human_review_receipt_verified",
    receiptDigest: receipt.receiptDigest,
    counts: { ...verified.counts, modelClosedKeepOutsideReview: receipt.counts.modelClosedKeepOutsideReview },
    flipReviewKeys: receipt.flipReviewKeys,
  })}\n`);
}

if (require.main === module) {
  try { main(); }
  catch (error) {
    process.stderr.write(`${error && error.stack ? error.stack : String(error)}\n`);
    process.exitCode = 1;
  }
}

module.exports = { RecordError, validateReceipt };
