#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const guidanceBuild = require("./build-framing-guidance");

const ROOT = path.resolve(__dirname, "..", "..");
const RECEIPT_SCHEMA = "cf7.portrait-pilot-human-framing-guidance-receipt.v1";

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
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    throw new reviewBuild.ReviewError(`${label} 不是合法 JSON：${error.message}`);
  }
}

function loadGuidanceBatch(batchPath) {
  const batchRoot = path.resolve(ROOT, batchPath);
  const relative = path.relative(path.join(ROOT, "tmp", "portrait-pilot"), batchRoot);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new reviewBuild.ReviewError("框选批次必须位于 tmp/portrait-pilot 下");
  }
  const dataPath = path.join(batchRoot, "framing-guidance-data.json");
  const dataset = readJson(dataPath, "framing guidance data");
  const artifactCount = guidanceBuild.verifyGuidanceDataset(dataset);
  return { batchRoot, dataPath, dataset, artifactCount };
}

function validateCropBox(choice, cropBox, label) {
  if (!Array.isArray(cropBox) || cropBox.length !== 4 || cropBox.some((value) => typeof value !== "number" || !Number.isFinite(value))) {
    throw new reviewBuild.ReviewError(`${label} cropBox 必须是四个有限数字`);
  }
  const [x0, y0, x1, y1] = cropBox;
  if (cropBox.some((value) => value < -0.5 || value > 1.5) || x0 >= x1 || y0 >= y1) {
    throw new reviewBuild.ReviewError(`${label} cropBox 越界或顺序错误`);
  }
  const pixelWidth = (x1 - x0) * choice.candidateWidth;
  const pixelHeight = (y1 - y0) * choice.candidateHeight;
  if (Math.abs(pixelWidth - pixelHeight) > 1.5) {
    throw new reviewBuild.ReviewError(`${label} cropBox 不是像素正方形`);
  }
  const minimumSide = Math.max(48, choice.minimumCandidateCropSide, Math.min(choice.candidateWidth, choice.candidateHeight) * 0.1);
  if (Math.min(pixelWidth, pixelHeight) < minimumSide) {
    throw new reviewBuild.ReviewError(`${label} cropBox 过小`);
  }
  const ix0 = Math.max(0, x0);
  const iy0 = Math.max(0, y0);
  const ix1 = Math.min(1, x1);
  const iy1 = Math.min(1, y1);
  const visibleArea = Math.max(0, ix1 - ix0) * choice.candidateWidth * Math.max(0, iy1 - iy0) * choice.candidateHeight;
  if (visibleArea / (pixelWidth * pixelHeight) < 0.2) {
    throw new reviewBuild.ReviewError(`${label} cropBox 可见候选面积不足 20%`);
  }
  return { pixelSide: (pixelWidth + pixelHeight) / 2, visibleFraction: visibleArea / (pixelWidth * pixelHeight) };
}

function validateGuidance(dataset, value) {
  exactKeys(value, ["schema", "batchId", "guidanceDigest", "parentReceiptDigest", "complete", "exportedAt", "guidance"], "框选指导文件");
  if (
    value.schema !== guidanceBuild.GUIDANCE_SCHEMA ||
    value.batchId !== dataset.batchId ||
    value.guidanceDigest !== dataset.guidanceDigest ||
    value.parentReceiptDigest !== dataset.parent.receiptDigest
  ) throw new reviewBuild.ReviewError("框选指导属于旧批次或其他父回执");
  if (value.complete !== true || Number.isNaN(Date.parse(value.exportedAt))) {
    throw new reviewBuild.ReviewError("框选指导没有完整导出时间或 complete=true");
  }
  exactKeys(value.guidance, dataset.items.map((item) => item.reviewKey), "框选指导映射");
  const rows = [];
  for (const item of dataset.items) {
    const entry = value.guidance[item.reviewKey];
    exactKeys(entry, ["sourceRole", "candidateId", "sourceCandidateSha256", "cropBox", "updatedAt"], `框选指导 ${item.reviewKey}`);
    const choice = item.choices.find((candidate) => candidate.sourceRole === entry.sourceRole);
    if (!choice || entry.candidateId !== choice.candidateId || entry.sourceCandidateSha256 !== choice.sourceCandidate.sha256) {
      throw new reviewBuild.ReviewError(`框选指导来源角色、候选或 hash 不闭合：${item.reviewKey}`);
    }
    if (Number.isNaN(Date.parse(entry.updatedAt))) throw new reviewBuild.ReviewError(`框选指导更新时间非法：${item.reviewKey}`);
    const geometry = validateCropBox(choice, entry.cropBox, item.reviewKey);
    rows.push({
      reviewKey: item.reviewKey,
      sourceRole: entry.sourceRole,
      candidateId: entry.candidateId,
      sourceCandidateSha256: entry.sourceCandidateSha256,
      cropBox: entry.cropBox,
      pixelSide: geometry.pixelSide,
      visibleFraction: geometry.visibleFraction,
      updatedAt: entry.updatedAt,
    });
  }
  return { rows };
}

function parseArgs(argv) {
  const options = { batch: null, guidance: null, check: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--batch" || argument === "--guidance") {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new reviewBuild.ReviewError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--batch") options.batch = value;
      if (argument === "--guidance") options.guidance = value;
    } else if (argument === "--check") options.check = true;
    else if (argument === "--help") options.help = true;
    else throw new reviewBuild.ReviewError(`未知参数：${argument}`);
  }
  return options;
}

function buildReceipt(loaded, guidancePath, guidance, validation) {
  const receipt = {
    schema: RECEIPT_SCHEMA,
    status: "human_framing_guidance_verified",
    productionReady: false,
    batchId: loaded.dataset.batchId,
    guidanceDigest: loaded.dataset.guidanceDigest,
    parentReceiptDigest: loaded.dataset.parent.receiptDigest,
    exportedAt: guidance.exportedAt,
    verifiedAt: new Date().toISOString(),
    inputs: {
      guidanceData: {
        path: path.relative(ROOT, loaded.dataPath).replaceAll("\\", "/"),
        bytes: fs.statSync(loaded.dataPath).size,
        sha256: reviewBuild.sha256File(loaded.dataPath),
      },
      guidance: {
        path: path.relative(ROOT, guidancePath).replaceAll("\\", "/"),
        bytes: fs.statSync(guidancePath).size,
        sha256: reviewBuild.sha256File(guidancePath),
      },
    },
    rows: validation.rows,
    gates: {
      exactParentReceiptBinding: true,
      allAdjustmentRowsGuided: true,
      exactCandidateHashBinding: true,
      pixelSquareCropChecked: true,
      humanFramingAccepted: true,
      humanAcceptanceScope: "selected source frame and square crop viewed from the bound high-resolution frame at live 80px",
      productionWrites: false,
    },
  };
  receipt.receiptDigest = sha256Bytes(reviewBuild.stableStringify(receipt));
  return receipt;
}

function verifyReceipt(receipt, expected) {
  if (receipt.schema !== RECEIPT_SCHEMA) throw new reviewBuild.ReviewError("框选指导回执 schema 不受支持");
  const envelope = { ...receipt };
  delete envelope.receiptDigest;
  if (sha256Bytes(reviewBuild.stableStringify(envelope)) !== receipt.receiptDigest) throw new reviewBuild.ReviewError("框选指导回执 digest 不匹配");
  if (
    receipt.guidanceDigest !== expected.guidanceDigest ||
    receipt.parentReceiptDigest !== expected.parentReceiptDigest ||
    receipt.inputs.guidanceData.sha256 !== expected.dataSha256 ||
    receipt.inputs.guidance.sha256 !== expected.guidanceSha256
  ) throw new reviewBuild.ReviewError("框选指导回执与当前输入不一致");
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.batch) {
    process.stdout.write("用法：node tools/portrait-pilot/verify-framing-guidance.js --batch <guidance batch> [--guidance <json>] [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const loaded = loadGuidanceBatch(options.batch);
  const guidancePath = path.resolve(ROOT, options.guidance || path.join(loaded.batchRoot, "portrait-pilot-framing-guidance.json"));
  const relative = path.relative(ROOT, guidancePath);
  if (relative.startsWith("..") || path.isAbsolute(relative)) throw new reviewBuild.ReviewError("框选指导文件必须位于仓库内");
  const guidance = readJson(guidancePath, "框选指导文件");
  const validation = validateGuidance(loaded.dataset, guidance);
  const receiptPath = path.join(loaded.batchRoot, "human-framing-guidance-receipt.json");
  const expected = {
    guidanceDigest: loaded.dataset.guidanceDigest,
    parentReceiptDigest: loaded.dataset.parent.receiptDigest,
    dataSha256: reviewBuild.sha256File(loaded.dataPath),
    guidanceSha256: reviewBuild.sha256File(guidancePath),
  };
  if (options.check) {
    const receipt = readJson(receiptPath, "框选指导回执");
    verifyReceipt(receipt, expected);
    process.stdout.write(`${JSON.stringify({ status: "human_framing_guidance_receipt_verified", receiptDigest: receipt.receiptDigest, rows: receipt.rows.length })}\n`);
    return;
  }
  if (fs.existsSync(receiptPath)) throw new reviewBuild.ReviewError("human-framing-guidance-receipt.json 已存在，禁止覆盖");
  const receipt = buildReceipt(loaded, guidancePath, guidance, validation);
  fs.writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  process.stdout.write(`${JSON.stringify({ status: receipt.status, receiptPath: path.relative(ROOT, receiptPath).replaceAll("\\", "/"), receiptDigest: receipt.receiptDigest, rows: receipt.rows.length })}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = { loadGuidanceBatch, validateGuidance, validateCropBox, verifyReceipt };
