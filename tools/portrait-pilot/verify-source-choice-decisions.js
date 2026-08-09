#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const DATA_SCHEMA = "cf7.enemy-portrait-source-choice-candidates.v1";
const DECISION_SCHEMA = "cf7.enemy-portrait-source-choice-decisions.v1";
const RECEIPT_SCHEMA = "cf7.enemy-portrait-source-choice-receipt.v1";

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

function verifyDataset(dataset) {
  if (dataset.schema !== DATA_SCHEMA || dataset.phase !== "SOURCE_CHOICE" || dataset.productionReady !== false) {
    throw new reviewBuild.ReviewError("source choice data schema 或状态非法");
  }
  const digestInput = { ...dataset };
  delete digestInput.manifestDigest;
  if (sha256Bytes(reviewBuild.stableStringify(digestInput)) !== dataset.manifestDigest) {
    throw new reviewBuild.ReviewError("source choice manifestDigest 不匹配");
  }
  if (sha256Bytes(reviewBuild.stableStringify(dataset.sourceEnvelope)) !== dataset.sourceDigest) {
    throw new reviewBuild.ReviewError("source choice sourceDigest 不匹配");
  }
  if (dataset.decisionSchema !== DECISION_SCHEMA || !Array.isArray(dataset.items) || dataset.items.length < 1) {
    throw new reviewBuild.ReviewError("source choice decision schema 或审核行非法");
  }
  const expectedGates = {
    enemyIdentityOnly: true,
    sourceCandidatesRemainIdentityAlternatives: true,
    selectedOutputVariantKey: "default",
    humanSelectionRequired: true,
    modelInferenceRequired: false,
    productionWrites: false,
  };
  if (reviewBuild.stableStringify(dataset.gates) !== reviewBuild.stableStringify(expectedGates)) {
    throw new reviewBuild.ReviewError("source choice gates 漂移");
  }

  let artifactCount = 0;
  const envelope = dataset.sourceEnvelope;
  for (const record of [
    envelope.assetMap,
    envelope.enemyList,
    envelope.pets,
    ...(envelope.enemyFiles || []),
    ...(envelope.sourceSwfs || []),
    ...(envelope.controllerFiles || []),
    ...(envelope.reviewerFiles || []),
    ...(envelope.ffdec?.files || []),
  ]) {
    reviewBuild.resolveRepoArtifact(record, "source choice source");
    artifactCount += 1;
  }
  for (const run of dataset.ffdecRuns || []) {
    for (const field of ["stdout", "stderr", "commandRecord"]) {
      reviewBuild.resolveRepoArtifact(run[field], `source choice FFDec ${field}`);
      artifactCount += 1;
    }
  }

  const reviewKeys = new Set();
  const sourceKeys = new Set();
  let renderable = 0;
  let manual = 0;
  let conflicts = 0;
  let duplicates = 0;
  for (const item of dataset.items) {
    if (!item.reviewKey || reviewKeys.has(item.reviewKey) || item.variantKey !== "default") {
      throw new reviewBuild.ReviewError("source choice reviewKey 缺失、重复或 variantKey 漂移");
    }
    reviewKeys.add(item.reviewKey);
    if (!item.portraitRef.startsWith("敌人-") || !["duplicate", "conflict"].includes(item.sourceClassification)) {
      throw new reviewBuild.ReviewError(`source choice 身份或分类非法：${item.reviewKey}`);
    }
    conflicts += Number(item.sourceClassification === "conflict");
    duplicates += Number(item.sourceClassification === "duplicate");
    if (!Array.isArray(item.sources) || item.sources.length < 2) throw new reviewBuild.ReviewError(`来源不足：${item.reviewKey}`);
    for (const source of item.sources) {
      if (!source.sourceCandidateKey || sourceKeys.has(source.sourceCandidateKey)) throw new reviewBuild.ReviewError("sourceCandidateKey 缺失或重复");
      sourceKeys.add(source.sourceCandidateKey);
      if (source.renderable === true) {
        renderable += 1;
        reviewBuild.resolveRepoArtifact(source.ffdecXml, `${source.sourceCandidateKey} xml`);
        reviewBuild.resolveRepoArtifact(source.ffdecGif, `${source.sourceCandidateKey} gif`);
        artifactCount += 2;
        if (!Array.isArray(source.frames) || source.frames.length < 1) throw new reviewBuild.ReviewError(`可渲染来源没有帧：${source.sourceCandidateKey}`);
        for (const frame of source.frames) {
          reviewBuild.resolveRepoArtifact(frame.artifact, `${source.sourceCandidateKey} frame`);
          artifactCount += 1;
        }
        if (!["first_frame_named_man_instance", "linkage_root_fallback"].includes(source.renderStrategy)) {
          throw new reviewBuild.ReviewError(`来源渲染策略非法：${source.sourceCandidateKey}`);
        }
      } else {
        manual += 1;
        if (source.unrenderableReason !== "orphan_without_symbol_name" || source.frames.length !== 0) {
          throw new reviewBuild.ReviewError(`人工来源状态非法：${source.sourceCandidateKey}`);
        }
      }
    }
  }
  const expectedCounts = {
    identityCount: dataset.items.length,
    sourceCandidateCount: sourceKeys.size,
    renderableSourceCandidateCount: renderable,
    manualSourceCandidateCount: manual,
    conflictIdentityCount: conflicts,
    duplicateIdentityCount: duplicates,
  };
  if (reviewBuild.stableStringify(dataset.counts) !== reviewBuild.stableStringify(expectedCounts)) {
    throw new reviewBuild.ReviewError("source choice counts 不闭合");
  }
  return artifactCount;
}

function loadSourceChoiceBatch(batchPath) {
  const batchRoot = path.resolve(ROOT, batchPath);
  const relative = path.relative(PILOT_ROOT, batchRoot);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new reviewBuild.ReviewError("source choice 批次必须位于 tmp/portrait-pilot 下");
  }
  const dataPath = path.join(batchRoot, "source-choice-data.json");
  const dataset = readJson(dataPath, "source choice data");
  const artifactCount = verifyDataset(dataset);
  return { batchRoot, dataPath, dataset, artifactCount };
}

function validateDecisions(dataset, value) {
  exactKeys(value, ["schema", "batchId", "sourceDigest", "manifestDigest", "complete", "exportedAt", "choices"], "选源决定文件");
  if (
    value.schema !== DECISION_SCHEMA ||
    value.batchId !== dataset.batchId ||
    value.sourceDigest !== dataset.sourceDigest ||
    value.manifestDigest !== dataset.manifestDigest
  ) throw new reviewBuild.ReviewError("选源决定属于旧批次或其他来源闭包");
  if (value.complete !== true || Number.isNaN(Date.parse(value.exportedAt))) throw new reviewBuild.ReviewError("选源决定未完整导出");
  exactKeys(value.choices, dataset.items.map((item) => item.reviewKey), "选源决定映射");
  const rows = [];
  for (const item of dataset.items) {
    const choice = value.choices[item.reviewKey];
    exactKeys(choice, ["status", "sourceCandidateKey", "notes", "updatedAt"], `选源决定 ${item.reviewKey}`);
    if (!["selected", "manual_maintenance"].includes(choice.status) || Number.isNaN(Date.parse(choice.updatedAt))) {
      throw new reviewBuild.ReviewError(`选源决定状态或时间非法：${item.reviewKey}`);
    }
    if (typeof choice.notes !== "string" || choice.notes.length > 1000) throw new reviewBuild.ReviewError(`选源备注非法：${item.reviewKey}`);
    const source = choice.sourceCandidateKey === null
      ? null
      : item.sources.find((candidate) => candidate.sourceCandidateKey === choice.sourceCandidateKey);
    if (choice.status === "selected" && (!source || source.renderable !== true)) {
      throw new reviewBuild.ReviewError(`自动选用必须绑定可渲染来源：${item.reviewKey}`);
    }
    if (choice.status === "manual_maintenance" && (choice.sourceCandidateKey !== null || !choice.notes.trim())) {
      throw new reviewBuild.ReviewError(`人工维护必须不绑定来源并填写备注：${item.reviewKey}`);
    }
    rows.push({
      reviewKey: item.reviewKey,
      portraitRef: item.portraitRef,
      variantKey: "default",
      status: choice.status,
      sourceCandidateKey: choice.sourceCandidateKey,
      selectedSource: source ? { swf: source.swf, symbolName: source.symbolName, orphan: source.orphan } : null,
      notes: choice.notes,
      updatedAt: choice.updatedAt,
    });
  }
  return { rows, manualCount: rows.filter((row) => row.status === "manual_maintenance").length };
}

function buildReceipt(loaded, decisionsPath, decisions, validation) {
  const receipt = {
    schema: RECEIPT_SCHEMA,
    status: validation.manualCount === 0 ? "human_source_choice_verified" : "human_source_choice_manual_maintenance_required",
    productionReady: false,
    batchId: loaded.dataset.batchId,
    sourceDigest: loaded.dataset.sourceDigest,
    manifestDigest: loaded.dataset.manifestDigest,
    exportedAt: decisions.exportedAt,
    verifiedAt: new Date().toISOString(),
    inputs: {
      sourceChoiceData: {
        path: path.relative(ROOT, loaded.dataPath).replaceAll("\\", "/"),
        bytes: fs.statSync(loaded.dataPath).size,
        sha256: reviewBuild.sha256File(loaded.dataPath),
      },
      decisions: {
        path: path.relative(ROOT, decisionsPath).replaceAll("\\", "/"),
        bytes: fs.statSync(decisionsPath).size,
        sha256: reviewBuild.sha256File(decisionsPath),
      },
    },
    counts: { rows: validation.rows.length, selected: validation.rows.length - validation.manualCount, manualMaintenance: validation.manualCount },
    rows: validation.rows,
    gates: {
      exactSourceClosureBinding: true,
      everyIdentityDecidedExactlyOnce: true,
      selectedSourceRenderable: true,
      identityAlternativesNotPromotedToVariants: true,
      selectedVariantKey: "default",
      humanSourceChoiceAccepted: true,
      modelInferenceUsed: false,
      productionWrites: false,
    },
  };
  receipt.receiptDigest = sha256Bytes(reviewBuild.stableStringify(receipt));
  return receipt;
}

function verifyReceipt(receipt, expected) {
  if (receipt.schema !== RECEIPT_SCHEMA) throw new reviewBuild.ReviewError("选源回执 schema 不受支持");
  const digestInput = { ...receipt };
  delete digestInput.receiptDigest;
  if (sha256Bytes(reviewBuild.stableStringify(digestInput)) !== receipt.receiptDigest) throw new reviewBuild.ReviewError("选源回执 digest 不匹配");
  if (
    receipt.sourceDigest !== expected.sourceDigest ||
    receipt.manifestDigest !== expected.manifestDigest ||
    receipt.inputs.sourceChoiceData.sha256 !== expected.dataSha256 ||
    receipt.inputs.decisions.sha256 !== expected.decisionsSha256
  ) throw new reviewBuild.ReviewError("选源回执与当前输入不一致");
}

function parseArgs(argv) {
  const options = { batch: null, decisions: null, check: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--batch", "--decisions"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new reviewBuild.ReviewError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--batch") options.batch = value;
      if (argument === "--decisions") options.decisions = value;
    } else if (argument === "--check") options.check = true;
    else if (argument === "--help") options.help = true;
    else throw new reviewBuild.ReviewError(`未知参数：${argument}`);
  }
  return options;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.batch) {
    process.stdout.write("用法：node tools/portrait-pilot/verify-source-choice-decisions.js --batch <source choice batch> [--decisions <json>] [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const loaded = loadSourceChoiceBatch(options.batch);
  const decisionsPath = path.resolve(ROOT, options.decisions || path.join(loaded.batchRoot, "portrait-pilot-source-choice-decisions.json"));
  const relative = path.relative(ROOT, decisionsPath);
  if (relative.startsWith("..") || path.isAbsolute(relative)) throw new reviewBuild.ReviewError("选源决定必须位于仓库内");
  const decisions = readJson(decisionsPath, "选源决定");
  const validation = validateDecisions(loaded.dataset, decisions);
  const receiptPath = path.join(loaded.batchRoot, "human-source-choice-receipt.json");
  const expected = {
    sourceDigest: loaded.dataset.sourceDigest,
    manifestDigest: loaded.dataset.manifestDigest,
    dataSha256: reviewBuild.sha256File(loaded.dataPath),
    decisionsSha256: reviewBuild.sha256File(decisionsPath),
  };
  if (options.check) {
    const receipt = readJson(receiptPath, "选源回执");
    verifyReceipt(receipt, expected);
    process.stdout.write(`${JSON.stringify({ status: "human_source_choice_receipt_verified", receiptDigest: receipt.receiptDigest, rows: receipt.counts.rows, manualMaintenance: receipt.counts.manualMaintenance })}\n`);
    return;
  }
  if (fs.existsSync(receiptPath)) throw new reviewBuild.ReviewError("human-source-choice-receipt.json 已存在，禁止覆盖");
  const receipt = buildReceipt(loaded, decisionsPath, decisions, validation);
  fs.writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  process.stdout.write(`${JSON.stringify({ status: receipt.status, receiptPath: path.relative(ROOT, receiptPath).replaceAll("\\", "/"), receiptDigest: receipt.receiptDigest, rows: receipt.counts.rows, manualMaintenance: receipt.counts.manualMaintenance })}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = { DATA_SCHEMA, DECISION_SCHEMA, RECEIPT_SCHEMA, verifyDataset, loadSourceChoiceBatch, validateDecisions, verifyReceipt };
