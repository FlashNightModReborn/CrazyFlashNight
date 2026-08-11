#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {
  ReviewError,
  computeReviewDigest,
  loadBatch,
  sha256File,
  stableStringify,
  verifyCurrentSource,
  verifyReviewDataset,
} = require("./build-review");

const ROOT = path.resolve(__dirname, "..", "..");
const DECISION_SCHEMA = "cf7.portrait-pilot-review-decisions.v1";
const RECEIPT_SCHEMA = "cf7.portrait-pilot-human-review-receipt.v1";

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function exactKeys(value, expected, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ReviewError(`${label} 必须是对象`);
  }
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (stableStringify(actual) !== stableStringify(wanted)) {
    throw new ReviewError(`${label} 字段不闭合`);
  }
}

function parseArgs(argv) {
  const options = { batch: null, decisions: null, check: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--batch" || argument === "--decisions") {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new ReviewError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--batch") options.batch = value;
      if (argument === "--decisions") options.decisions = value;
    } else if (argument === "--check") {
      options.check = true;
    } else if (argument === "--help") {
      options.help = true;
    } else {
      throw new ReviewError(`未知参数：${argument}`);
    }
  }
  return options;
}

function readJson(filePath, label) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    throw new ReviewError(`${label} 缺失：${filePath}`);
  }
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    throw new ReviewError(`${label} 不是合法 JSON：${error.message}`);
  }
}

function validateDecisions(dataset, value) {
  exactKeys(
    value,
    ["schema", "batchId", "sourceDigest", "reviewDigest", "complete", "exportedAt", "decisions"],
    "决定文件",
  );
  if (
    value.schema !== DECISION_SCHEMA ||
    value.batchId !== dataset.batchId ||
    value.sourceDigest !== dataset.sourceDigest ||
    value.reviewDigest !== dataset.reviewDigest
  ) {
    throw new ReviewError("决定文件属于旧批次或其他证据摘要");
  }
  if (value.complete !== true || Number.isNaN(Date.parse(value.exportedAt))) {
    throw new ReviewError("决定文件没有完整导出时间或 complete=true");
  }
  exactKeys(value.decisions, dataset.items.map((item) => item.reviewKey), "决定映射");

  const statusCounts = Object.fromEntries(dataset.statuses.map((status) => [status.value, 0]));
  const rows = [];
  for (const item of dataset.items) {
    const decision = value.decisions[item.reviewKey];
    exactKeys(decision, ["status", "notes", "updatedAt"], `决定 ${item.reviewKey}`);
    if (!item.allowedStatuses.includes(decision.status)) {
      throw new ReviewError(`决定状态不允许：${item.reviewKey}/${decision.status}`);
    }
    if (typeof decision.notes !== "string" || (decision.status !== "pass" && decision.notes.trim() === "")) {
      throw new ReviewError(`非通过项缺备注：${item.reviewKey}`);
    }
    if (Number.isNaN(Date.parse(decision.updatedAt))) {
      throw new ReviewError(`决定更新时间非法：${item.reviewKey}`);
    }
    statusCounts[decision.status] += 1;
    rows.push({
      reviewKey: item.reviewKey,
      blocked: item.blocked,
      status: decision.status,
      notes: decision.notes.trim(),
      updatedAt: decision.updatedAt,
    });
  }
  const eligibleRows = rows.filter((row) => !row.blocked);
  const eligiblePassed = eligibleRows.filter((row) => row.status === "pass").length;
  return {
    rows,
    statusCounts,
    eligiblePassed,
    eligibleTotal: eligibleRows.length,
    refinementRequired: eligiblePassed !== eligibleRows.length,
  };
}

function buildReceipt(loaded, dataset, decisionsPath, decisions, validation) {
  const receipt = {
    schema: RECEIPT_SCHEMA,
    status: validation.refinementRequired ? "human_reviewed_refinement_required" : "human_reviewed_approved",
    productionReady: false,
    batchId: dataset.batchId,
    sourceDigest: dataset.sourceDigest,
    reviewDigest: dataset.reviewDigest,
    exportedAt: decisions.exportedAt,
    verifiedAt: new Date().toISOString(),
    inputs: {
      decisions: {
        path: path.relative(ROOT, decisionsPath).replaceAll("\\", "/"),
        bytes: fs.statSync(decisionsPath).size,
        sha256: sha256File(decisionsPath),
      },
      reviewData: {
        path: path.relative(ROOT, path.join(loaded.batchRoot, "review-data.json")).replaceAll("\\", "/"),
        bytes: fs.statSync(path.join(loaded.batchRoot, "review-data.json")).size,
        sha256: sha256File(path.join(loaded.batchRoot, "review-data.json")),
      },
    },
    counts: {
      total: validation.rows.length,
      eligible: validation.eligibleTotal,
      eligiblePassed: validation.eligiblePassed,
      blocked: validation.rows.filter((row) => row.blocked).length,
      statuses: validation.statusCounts,
    },
    decisions: validation.rows,
    gates: {
      exactDigestBinding: true,
      allRowsReviewed: true,
      nonPassNotesPresent: true,
      sourceBlockersRestricted: true,
      artAcceptance: !validation.refinementRequired,
      productionWrites: false,
    },
  };
  receipt.receiptDigest = sha256Bytes(stableStringify(receipt));
  return receipt;
}

function verifyReceipt(receipt, expected) {
  if (receipt.schema !== RECEIPT_SCHEMA) throw new ReviewError("人审收据 schema 不受支持");
  const copy = { ...receipt };
  delete copy.receiptDigest;
  if (sha256Bytes(stableStringify(copy)) !== receipt.receiptDigest) {
    throw new ReviewError("人审收据 receiptDigest 不匹配");
  }
  if (
    receipt.sourceDigest !== expected.sourceDigest ||
    receipt.reviewDigest !== expected.reviewDigest ||
    receipt.inputs.decisions.sha256 !== expected.decisionsSha256 ||
    receipt.inputs.reviewData.sha256 !== expected.reviewDataSha256
  ) {
    throw new ReviewError("人审收据与当前决定文件不一致");
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.batch) {
    process.stdout.write(
      "用法：node tools/portrait-pilot/verify-review-decisions.js --batch <tmp/portrait-pilot/...> [--decisions <json>] [--check]\n",
    );
    if (!options.help) process.exitCode = 1;
    return;
  }
  const loaded = loadBatch(options.batch);
  const reviewDataPath = path.join(loaded.batchRoot, "review-data.json");
  const dataset = readJson(reviewDataPath, "review data");
  const decisionsPath = path.resolve(
    ROOT,
    options.decisions || path.join(loaded.batchRoot, "portrait-pilot-review-decisions.json"),
  );
  const relative = path.relative(ROOT, decisionsPath);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new ReviewError("决定文件必须位于仓库内");
  }
  const decisions = readJson(decisionsPath, "决定文件");
  const validation = validateDecisions(dataset, decisions);
  const receiptPath = path.join(loaded.batchRoot, "human-review-receipt.json");
  const expected = {
    sourceDigest: dataset.sourceDigest,
    reviewDigest: dataset.reviewDigest,
    decisionsSha256: sha256File(decisionsPath),
    reviewDataSha256: sha256File(reviewDataPath),
  };
  if (options.check) {
    if (computeReviewDigest(dataset) !== dataset.reviewDigest) {
      throw new ReviewError("冻结 reviewDigest 不匹配");
    }
    const receipt = readJson(receiptPath, "人审收据");
    verifyReceipt(receipt, expected);
    process.stdout.write(`${JSON.stringify({
      status: "human_review_receipt_verified",
      receiptDigest: receipt.receiptDigest,
      outcome: receipt.status,
      counts: receipt.counts,
    })}\n`);
    return;
  }
  verifyCurrentSource(loaded.manifest);
  verifyReviewDataset(dataset);
  if (fs.existsSync(receiptPath)) throw new ReviewError("human-review-receipt.json 已存在，禁止覆盖");
  const receipt = buildReceipt(loaded, dataset, decisionsPath, decisions, validation);
  fs.writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  process.stdout.write(`${JSON.stringify({
    status: receipt.status,
    receiptPath: path.relative(ROOT, receiptPath).replaceAll("\\", "/"),
    receiptDigest: receipt.receiptDigest,
    counts: receipt.counts,
  })}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = { validateDecisions, verifyReceipt };
