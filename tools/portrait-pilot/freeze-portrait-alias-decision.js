#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const reviewBuild = require("./build-review");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const SCHEMA = "cf7.portrait-pilot-identity-alias-receipt.v1";

function parseArgs(argv) {
  const options = {
    sourceReviewBatch: null,
    targetGuidanceBatch: null,
    targetRenderBatch: null,
    sourceReviewKey: null,
    targetReviewKey: null,
    reason: null,
    output: null,
    batchId: null,
    check: false,
    help: false,
  };
  const valueArguments = new Map([
    ["--source-review-batch", "sourceReviewBatch"],
    ["--target-guidance-batch", "targetGuidanceBatch"],
    ["--target-render-batch", "targetRenderBatch"],
    ["--source-review-key", "sourceReviewKey"],
    ["--target-review-key", "targetReviewKey"],
    ["--reason", "reason"],
    ["--output", "output"],
    ["--batch-id", "batchId"],
  ]);
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (valueArguments.has(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new Error(`${argument} 缺少值`);
      options[valueArguments.get(argument)] = value;
      index += 1;
    } else if (argument === "--check") options.check = true;
    else if (argument === "--help") options.help = true;
    else throw new Error(`未知参数：${argument}`);
  }
  return options;
}

function ensurePilotChild(value, label, allowExisting = false) {
  const resolved = path.resolve(ROOT, value);
  const relative = path.relative(PILOT_ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(`${label} 必须位于 tmp/portrait-pilot 下`);
  }
  if (!allowExisting && fs.existsSync(resolved)) throw new Error(`${label} 已存在，禁止覆盖`);
  return resolved;
}

function readJson(filePath, label) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) throw new Error(`${label} 缺失：${filePath}`);
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    throw new Error(`${label} 不是合法 JSON：${error.message}`);
  }
}

function artifact(filePath) {
  const resolved = path.resolve(filePath);
  const relative = path.relative(ROOT, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative) || !fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    throw new Error(`artifact 越出仓库或缺失：${filePath}`);
  }
  return {
    path: relative.replaceAll("\\", "/"),
    bytes: fs.statSync(resolved).size,
    sha256: reviewBuild.sha256File(resolved),
  };
}

function resolveArtifact(record, label) {
  return reviewBuild.resolveRepoArtifact(record, label);
}

function runJson(command, args, label) {
  const completed = spawnSync(command, args, {
    cwd: ROOT,
    encoding: "utf8",
    windowsHide: true,
    timeout: 120_000,
  });
  if (completed.error || completed.status !== 0) {
    throw new Error(`${label} 失败：${completed.error?.message || completed.stderr.trim() || completed.stdout.trim()}`);
  }
  const line = completed.stdout.trim().split(/\r?\n/u).filter(Boolean).at(-1);
  try {
    return JSON.parse(line);
  } catch (error) {
    throw new Error(`${label} 未返回 JSON：${error.message}`);
  }
}

function splitReviewKey(reviewKey) {
  const separator = reviewKey.lastIndexOf("::");
  if (separator <= 0 || separator === reviewKey.length - 2) throw new Error(`reviewKey 非法：${reviewKey}`);
  return { portraitRef: reviewKey.slice(0, separator), variantKey: reviewKey.slice(separator + 2) };
}

function digestReceipt(receipt) {
  return crypto.createHash("sha256").update(reviewBuild.stableStringify(receipt)).digest("hex").toUpperCase();
}

function loadBoundInputs(options) {
  const sourceRoot = ensurePilotChild(options.sourceReviewBatch, "来源人审批次", true);
  const targetGuidanceRoot = ensurePilotChild(options.targetGuidanceBatch, "目标框选批次", true);
  const targetRenderRoot = ensurePilotChild(options.targetRenderBatch, "目标渲染批次", true);
  const sourceVerifier = runJson("node", [
    "tools/portrait-pilot/verify-review-decisions.js",
    "--batch",
    path.relative(ROOT, sourceRoot),
    "--check",
  ], "来源人审回执验证");
  const guidanceVerifier = runJson("node", [
    "tools/portrait-pilot/verify-framing-guidance.js",
    "--batch",
    path.relative(ROOT, targetGuidanceRoot),
    "--check",
  ], "目标框选回执验证");
  const renderVerifier = runJson("python", [
    "tools/portrait-pilot/render-framing-guidance-large-frame-fidelity-v1.py",
    "check",
    "--output",
    path.relative(ROOT, targetRenderRoot),
  ], "目标人工头像渲染验证");

  const sourceDecisionsPath = path.join(sourceRoot, "portrait-pilot-review-decisions.json");
  const sourceReceiptPath = path.join(sourceRoot, "human-review-receipt.json");
  const sourceReviewDataPath = path.join(sourceRoot, "review-data.json");
  const targetGuidanceDataPath = path.join(targetGuidanceRoot, "framing-guidance-data.json");
  const targetGuidancePath = path.join(targetGuidanceRoot, "portrait-pilot-framing-guidance.json");
  const targetGuidanceReceiptPath = path.join(targetGuidanceRoot, "human-framing-guidance-receipt.json");
  const targetRenderReportPath = path.join(targetRenderRoot, "human-framing-render-report.json");
  const sourceDecisions = readJson(sourceDecisionsPath, "来源决定");
  const sourceReceipt = readJson(sourceReceiptPath, "来源回执");
  const guidanceData = readJson(targetGuidanceDataPath, "目标框选数据");
  const guidance = readJson(targetGuidancePath, "目标框选决定");
  const guidanceReceipt = readJson(targetGuidanceReceiptPath, "目标框选回执");
  const renderReport = readJson(targetRenderReportPath, "目标人工头像渲染报告");
  if (sourceVerifier.receiptDigest !== sourceReceipt.receiptDigest) throw new Error("来源回执 digest 与 verifier 不一致");
  if (guidanceVerifier.receiptDigest !== guidanceReceipt.receiptDigest) throw new Error("目标框选回执 digest 与 verifier 不一致");
  if (renderVerifier.reportDigest !== renderReport.reportDigest) throw new Error("目标渲染 digest 与 verifier 不一致");
  return {
    sourceRoot,
    targetGuidanceRoot,
    targetRenderRoot,
    sourceDecisionsPath,
    sourceReceiptPath,
    sourceReviewDataPath,
    targetGuidanceDataPath,
    targetGuidancePath,
    targetGuidanceReceiptPath,
    targetRenderReportPath,
    sourceDecisions,
    sourceReceipt,
    guidanceData,
    guidance,
    guidanceReceipt,
    renderReport,
    sourceVerifier,
    guidanceVerifier,
    renderVerifier,
  };
}

function buildReceipt(options, inputs) {
  const sourceKey = splitReviewKey(options.sourceReviewKey);
  const targetKey = splitReviewKey(options.targetReviewKey);
  if (sourceKey.variantKey !== targetKey.variantKey) throw new Error("头像别名当前只允许相同 variantKey");
  const sourceDecision = inputs.sourceDecisions.decisions?.[options.sourceReviewKey];
  const sourceReceiptRow = inputs.sourceReceipt.decisions?.find((entry) => entry.reviewKey === options.sourceReviewKey);
  if (sourceDecision?.status !== "source" || sourceReceiptRow?.status !== "source") {
    throw new Error("别名来源必须是冻结的 source 决定");
  }
  const targetGuidance = inputs.guidance.guidance?.[options.targetReviewKey];
  const targetRow = inputs.renderReport.rows?.find((entry) => entry.reviewKey === options.targetReviewKey);
  if (!targetGuidance || !targetRow || targetRow.humanGuidance?.candidateId !== targetGuidance.candidateId) {
    throw new Error("别名目标必须是冻结并渲染的人类框选头像");
  }
  if (inputs.renderReport.productionReady !== false || inputs.renderReport.gates?.productionWrites !== false) {
    throw new Error("别名目标渲染 production gate 非法");
  }
  const receipt = {
    schema: SCHEMA,
    status: "human_identity_alias_verified",
    productionReady: false,
    batchId: options.batchId,
    generatedAt: new Date().toISOString(),
    humanInstruction: options.reason,
    source: {
      reviewKey: options.sourceReviewKey,
      portraitRef: sourceKey.portraitRef,
      variantKey: sourceKey.variantKey,
      frozenDecision: sourceDecision,
      files: {
        reviewData: artifact(inputs.sourceReviewDataPath),
        decisions: artifact(inputs.sourceDecisionsPath),
        humanReviewReceipt: artifact(inputs.sourceReceiptPath),
      },
      verifier: inputs.sourceVerifier,
    },
    target: {
      reviewKey: options.targetReviewKey,
      portraitRef: targetKey.portraitRef,
      variantKey: targetKey.variantKey,
      humanGuidance: targetGuidance,
      selectedChoice: targetRow.selectedChoice,
      outputs: {
        master: targetRow.master,
        previews: targetRow.previews,
        webp80Lossless: targetRow.webp80Lossless,
      },
      files: {
        guidanceData: artifact(inputs.targetGuidanceDataPath),
        guidance: artifact(inputs.targetGuidancePath),
        humanFramingGuidanceReceipt: artifact(inputs.targetGuidanceReceiptPath),
        humanFramingRenderReport: artifact(inputs.targetRenderReportPath),
      },
      guidanceVerifier: inputs.guidanceVerifier,
      renderVerifier: inputs.renderVerifier,
    },
    resolution: {
      mode: "reuse_human_accepted_target_portrait",
      sourceExtractionRequired: false,
      consumerPortraitRefOverrideRequired: true,
      excludedReviewKeys: ["敌人-黑无常索命::default"],
    },
    gates: {
      sourceHumanDecisionBound: true,
      targetHumanGuidanceBound: true,
      targetDeterministicRenderBound: true,
      sameVariantKey: true,
      blackWuchangExplicitlyExcluded: true,
      productionWrites: false,
    },
  };
  receipt.receiptDigest = digestReceipt(receipt);
  return receipt;
}

function verifyReceipt(receipt) {
  if (receipt.schema !== SCHEMA || receipt.status !== "human_identity_alias_verified" || receipt.productionReady !== false) {
    throw new Error("头像别名回执 schema 或状态非法");
  }
  const envelope = { ...receipt };
  const digest = envelope.receiptDigest;
  delete envelope.receiptDigest;
  if (digest !== digestReceipt(envelope)) throw new Error("头像别名 receiptDigest 不匹配");
  if (
    receipt.source.reviewKey === receipt.target.reviewKey ||
    receipt.source.variantKey !== receipt.target.variantKey ||
    receipt.source.frozenDecision?.status !== "source" ||
    receipt.resolution?.mode !== "reuse_human_accepted_target_portrait" ||
    receipt.resolution?.excludedReviewKeys?.includes("敌人-黑无常索命::default") !== true ||
    receipt.gates?.blackWuchangExplicitlyExcluded !== true ||
    receipt.gates?.productionWrites !== false
  ) throw new Error("头像别名语义不闭合");
  const records = [
    ...Object.values(receipt.source.files),
    ...Object.values(receipt.target.files),
    receipt.target.outputs.master,
    ...Object.values(receipt.target.outputs.previews),
    receipt.target.outputs.webp80Lossless,
  ];
  for (const record of records) resolveArtifact(record, "头像别名 artifact");
  return records.length;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.output || !options.batchId || (!options.check && [
    options.sourceReviewBatch,
    options.targetGuidanceBatch,
    options.targetRenderBatch,
    options.sourceReviewKey,
    options.targetReviewKey,
    options.reason,
  ].some((value) => !value))) {
    process.stdout.write("用法：node tools/portrait-pilot/freeze-portrait-alias-decision.js --source-review-batch <batch> --target-guidance-batch <batch> --target-render-batch <batch> --source-review-key <key> --target-review-key <key> --reason <text> --output <fresh-batch> --batch-id <ascii-id> [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(options.batchId)) throw new Error("batch id 非法");
  const outputRoot = ensurePilotChild(options.output, "头像别名输出", options.check);
  const receiptPath = path.join(outputRoot, "portrait-alias-receipt.json");
  if (options.check) {
    const receipt = readJson(receiptPath, "头像别名回执");
    if (receipt.batchId !== options.batchId) throw new Error("check batch-id 与回执不一致");
    const artifactCount = verifyReceipt(receipt);
    process.stdout.write(`${JSON.stringify({ status: "human_identity_alias_receipt_verified", receiptDigest: receipt.receiptDigest, source: receipt.source.reviewKey, target: receipt.target.reviewKey, artifactCount })}\n`);
    return;
  }
  const inputs = loadBoundInputs(options);
  const receipt = buildReceipt(options, inputs);
  fs.mkdirSync(outputRoot, { recursive: false });
  fs.writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  const artifactCount = verifyReceipt(receipt);
  process.stdout.write(`${JSON.stringify({ status: "human_identity_alias_receipt_frozen", path: path.relative(ROOT, receiptPath).replaceAll("\\", "/"), receiptDigest: receipt.receiptDigest, source: receipt.source.reviewKey, target: receipt.target.reviewKey, artifactCount })}\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
  process.exitCode = 1;
}
