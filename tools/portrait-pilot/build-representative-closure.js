#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const decisionVerifier = require("./verify-review-decisions");
const sourceChoiceVerifier = require("./verify-source-choice-decisions");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const REPORT_SCHEMA = "cf7.enemy-portrait-representative-closure.v1";

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function readJson(filePath, label) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) throw new reviewBuild.ReviewError(`${label} 缺失：${filePath}`);
  try { return JSON.parse(fs.readFileSync(filePath, "utf8")); }
  catch (error) { throw new reviewBuild.ReviewError(`${label} 不是合法 JSON：${error.message}`); }
}

function artifact(filePath) {
  const resolved = path.resolve(filePath);
  const relative = path.relative(ROOT, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative) || !fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    throw new reviewBuild.ReviewError(`closure artifact 越出仓库或缺失：${filePath}`);
  }
  return { path: relative.replaceAll("\\", "/"), bytes: fs.statSync(resolved).size, sha256: reviewBuild.sha256File(resolved) };
}

function ensureOutput(value) {
  const resolved = path.resolve(ROOT, value);
  const relative = path.relative(PILOT_ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) throw new reviewBuild.ReviewError("closure 输出必须是 tmp/portrait-pilot 下的新目录");
  return resolved;
}

function parseArgs(argv) {
  const options = { reviewedBatches: [], guidedRender: null, sourceChoiceBatch: null, output: null, batchId: null, check: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--reviewed-batch", "--guided-render", "--source-choice-batch", "--output", "--batch-id"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new reviewBuild.ReviewError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--reviewed-batch") options.reviewedBatches.push(value);
      if (argument === "--guided-render") options.guidedRender = value;
      if (argument === "--source-choice-batch") options.sourceChoiceBatch = value;
      if (argument === "--output") options.output = value;
      if (argument === "--batch-id") options.batchId = value;
    } else if (argument === "--check") options.check = true;
    else if (argument === "--help") options.help = true;
    else throw new reviewBuild.ReviewError(`未知参数：${argument}`);
  }
  return options;
}

function loadReviewedBatch(batchPath) {
  const loaded = reviewBuild.loadBatch(batchPath);
  const reviewPath = path.join(loaded.batchRoot, "review-data.json");
  const decisionsPath = path.join(loaded.batchRoot, "portrait-pilot-review-decisions.json");
  const receiptPath = path.join(loaded.batchRoot, "human-review-receipt.json");
  const dataset = readJson(reviewPath, "review data");
  if (reviewBuild.computeReviewDigest(dataset) !== dataset.reviewDigest) {
    throw new reviewBuild.ReviewError("冻结 reviewDigest 不匹配");
  }
  if (!Array.isArray(dataset.items) || dataset.items.length < 1) {
    throw new reviewBuild.ReviewError("冻结 review data 没有审核行");
  }
  const decisions = readJson(decisionsPath, "review decisions");
  const validation = decisionVerifier.validateDecisions(dataset, decisions);
  const receipt = readJson(receiptPath, "review receipt");
  decisionVerifier.verifyReceipt(receipt, {
    sourceDigest: dataset.sourceDigest,
    reviewDigest: dataset.reviewDigest,
    decisionsSha256: reviewBuild.sha256File(decisionsPath),
    reviewDataSha256: reviewBuild.sha256File(reviewPath),
  });
  return {
    dataset, decisions, validation, receipt,
    files: { reviewData: artifact(reviewPath), decisions: artifact(decisionsPath), receipt: artifact(receiptPath) },
  };
}

function verifyGuidedRender(renderRoot) {
  const reportPath = path.resolve(ROOT, renderRoot, "human-framing-render-report.json");
  const report = readJson(reportPath, "human guided render report");
  if (report.schema !== "cf7.portrait-pilot-human-framing-render-report.v1" || report.status !== "human_guided_automated_checked") {
    throw new reviewBuild.ReviewError("human guided render 状态非法");
  }
  const digestInput = { ...report };
  delete digestInput.reportDigest;
  if (sha256Bytes(reviewBuild.stableStringify(digestInput)) !== report.reportDigest) throw new reviewBuild.ReviewError("human guided render digest 不匹配");
  if (report.gates?.modelRerun !== false || report.gates?.productionWrites !== false) throw new reviewBuild.ReviewError("human guided render 安全门漂移");
  for (const record of Object.values(report.inputs || {})) {
    if (record && typeof record.path === "string") reviewBuild.resolveRepoArtifact(record, "guided render input");
  }
  for (const row of report.rows || []) {
    for (const record of [row.selectedChoice?.sourceCandidate, row.selectedChoice?.sourceHighResolution, row.sourceSupersample, row.master, row.webp80Lossless, ...Object.values(row.previews || {})]) {
      reviewBuild.resolveRepoArtifact(record, `guided render ${row.reviewKey}`);
    }
  }
  return { report, reportFile: artifact(reportPath) };
}

function verifyReport(report) {
  if (report.schema !== REPORT_SCHEMA || report.productionReady !== false || report.status !== "representative_visuals_resolved_source_choices_pending") {
    throw new reviewBuild.ReviewError("representative closure schema 或状态非法");
  }
  const digestInput = { ...report };
  delete digestInput.reportDigest;
  if (sha256Bytes(reviewBuild.stableStringify(digestInput)) !== report.reportDigest) throw new reviewBuild.ReviewError("representative closure digest 不匹配");
  if (
    report.counts.total !== 15 || report.counts.eligible !== 12 || report.counts.eligibleResolved !== 12 ||
    report.counts.eligibleUnresolved !== 0 || report.counts.sourceBlocked !== 3
  ) throw new reviewBuild.ReviewError("representative closure counts 不闭合");
  if (
    report.gates?.allEligibleVisualsResolved !== true ||
    report.gates?.sourceExceptionsRemainNonSignable !== true ||
    report.gates?.fullCampaignAuthorized !== false ||
    report.gates?.productionWrites !== false
  ) throw new reviewBuild.ReviewError("representative closure gates 漂移");
  for (const reviewed of report.inputs.reviewedBatches) for (const record of Object.values(reviewed.files)) reviewBuild.resolveRepoArtifact(record, "closure reviewed batch");
  reviewBuild.resolveRepoArtifact(report.inputs.guidedRender.reportFile, "closure guided render");
  reviewBuild.resolveRepoArtifact(report.inputs.sourceChoiceQueue.dataFile, "closure source choice queue");
  return report.rows.length + report.blockers.length;
}

function build(options) {
  if (options.reviewedBatches.length < 1 || !options.guidedRender || !options.sourceChoiceBatch || !options.batchId) {
    throw new reviewBuild.ReviewError("build 需要 reviewed batches、guided render、source choice batch 与 batch id");
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(options.batchId)) throw new reviewBuild.ReviewError("batch id 非法");
  const reviewed = options.reviewedBatches.map(loadReviewedBatch);
  const base = reviewed[0];
  if (base.dataset.items.length !== 15 || base.dataset.counts?.eligible !== 12 || base.dataset.counts?.blocked !== 3) {
    throw new reviewBuild.ReviewError("首个 reviewed batch 不是冻结代表集 15/12/3");
  }
  const resolution = new Map();
  for (const batch of reviewed) {
    for (const item of batch.dataset.items) {
      const decision = batch.decisions.decisions[item.reviewKey];
      if (decision.status === "pass") {
        resolution.set(item.reviewKey, {
          resolution: "human_passed_luna_a_proposal",
          batchId: batch.dataset.batchId,
          receiptDigest: batch.receipt.receiptDigest,
          reviewDigest: batch.dataset.reviewDigest,
        });
      } else if (!item.blocked) {
        resolution.delete(item.reviewKey);
      }
    }
  }
  const guided = verifyGuidedRender(options.guidedRender);
  for (const row of guided.report.rows) {
    resolution.set(row.reviewKey, {
      resolution: "human_guided_high_resolution_render",
      batchId: guided.report.batchId,
      reportDigest: guided.report.reportDigest,
      guidanceReceiptDigest: guided.report.framingGuidanceReceiptDigest,
      sourceRole: row.humanGuidance.sourceRole,
      candidateId: row.humanGuidance.candidateId,
      cropBox: row.humanGuidance.cropBox,
      master: row.master,
      preview80: row.previews["80"],
    });
  }
  const rows = [];
  const blockers = [];
  for (const item of base.dataset.items) {
    if (item.blocked) {
      const decision = base.decisions.decisions[item.reviewKey];
      if (decision.status !== "source") throw new reviewBuild.ReviewError(`代表集来源阻断未保持 source：${item.reviewKey}`);
      blockers.push({
        reviewKey: item.reviewKey,
        portraitRef: item.portraitRef,
        variantKey: item.variantKey,
        sourceClassification: item.sourceClassification,
        blockReason: item.blockReason,
        humanDecision: decision,
      });
      continue;
    }
    const resolved = resolution.get(item.reviewKey);
    if (!resolved) throw new reviewBuild.ReviewError(`代表集 eligible 尚未闭合：${item.reviewKey}`);
    rows.push({ reviewKey: item.reviewKey, portraitRef: item.portraitRef, variantKey: item.variantKey, ...resolved });
  }
  const sourceChoice = sourceChoiceVerifier.loadSourceChoiceBatch(options.sourceChoiceBatch);
  const report = {
    schema: REPORT_SCHEMA,
    status: "representative_visuals_resolved_source_choices_pending",
    productionReady: false,
    batchId: options.batchId,
    generatedAt: new Date().toISOString(),
    inputs: {
      reviewedBatches: reviewed.map((batch) => ({
        batchId: batch.dataset.batchId,
        sourceDigest: batch.dataset.sourceDigest,
        reviewDigest: batch.dataset.reviewDigest,
        receiptDigest: batch.receipt.receiptDigest,
        files: batch.files,
      })),
      guidedRender: { batchId: guided.report.batchId, reportDigest: guided.report.reportDigest, reportFile: guided.reportFile },
      sourceChoiceQueue: {
        batchId: sourceChoice.dataset.batchId,
        sourceDigest: sourceChoice.dataset.sourceDigest,
        manifestDigest: sourceChoice.dataset.manifestDigest,
        rows: sourceChoice.dataset.counts.identityCount,
        candidates: sourceChoice.dataset.counts.sourceCandidateCount,
        dataFile: artifact(sourceChoice.dataPath),
      },
    },
    counts: { total: 15, eligible: 12, eligibleResolved: rows.length, eligibleUnresolved: 12 - rows.length, sourceBlocked: blockers.length },
    rows,
    blockers,
    gates: {
      allEligibleVisualsResolved: rows.length === 12,
      sourceExceptionsRemainNonSignable: true,
      sourceChoiceQueuePrepared: true,
      missingSourcesRemainBlocked: true,
      fullCampaignAuthorized: false,
      productionWrites: false,
    },
  };
  report.reportDigest = sha256Bytes(reviewBuild.stableStringify(report));
  verifyReport(report);
  return report;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.output) {
    process.stdout.write("用法：node tools/portrait-pilot/build-representative-closure.js --reviewed-batch <r7> [--reviewed-batch <refinement> ...] --guided-render <r12> --source-choice-batch <batch> --output <fresh closure batch> --batch-id <ascii id> [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const outputRoot = ensureOutput(options.output);
  const reportPath = path.join(outputRoot, "representative-closure.json");
  if (options.check) {
    const report = readJson(reportPath, "representative closure");
    const rows = verifyReport(report);
    process.stdout.write(`${JSON.stringify({ status: "representative_closure_verified", reportDigest: report.reportDigest, eligibleResolved: report.counts.eligibleResolved, sourceBlocked: report.counts.sourceBlocked, rows })}\n`);
    return;
  }
  if (fs.existsSync(outputRoot)) throw new reviewBuild.ReviewError("closure 输出目录已存在，禁止覆盖");
  const report = build(options);
  fs.mkdirSync(outputRoot, { recursive: false });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  process.stdout.write(`${JSON.stringify({ status: report.status, path: path.relative(ROOT, reportPath).replaceAll("\\", "/"), reportDigest: report.reportDigest, eligibleResolved: report.counts.eligibleResolved, sourceBlocked: report.counts.sourceBlocked })}\n`);
}

try { main(); }
catch (error) {
  process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
  process.exitCode = 1;
}
