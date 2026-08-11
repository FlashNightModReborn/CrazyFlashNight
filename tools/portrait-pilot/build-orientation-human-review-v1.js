#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { sha256Bytes, sha256File, stableStringify } = require("../portrait-worker/lib/codex-cli-luna-worker");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const DATA_NAME = "orientation-human-review-data.json";
const UI_FILES = [
  "launcher/web/modules/portrait-pilot-review/dev/orientation-audit.html",
  "launcher/web/modules/portrait-pilot-review/dev/orientation-audit.css",
  "launcher/web/modules/portrait-pilot-review/dev/orientation-audit.js",
  "tools/portrait-pilot/verify-orientation-human-decisions-v1.js",
];

class ReviewError extends Error {}

function parseArgs(argv) {
  const options = { command: argv[0], source: null, output: null, batchId: null };
  for (let index = 1; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--source", "--output", "--batch-id"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new ReviewError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--source") options.source = value;
      if (argument === "--output") options.output = value;
      if (argument === "--batch-id") options.batchId = value;
    } else if (argument === "--help") options.help = true;
    else throw new ReviewError(`未知参数：${argument}`);
  }
  return options;
}

function pilotPath(value, label, allowExisting) {
  const resolved = path.resolve(ROOT, value);
  const relative = path.relative(PILOT_ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) throw new ReviewError(`${label}必须位于 tmp/portrait-pilot 下`);
  if (fs.existsSync(resolved) !== allowExisting) throw new ReviewError(allowExisting ? `${label}不存在` : `${label}已存在，禁止覆盖`);
  return resolved;
}

function readJson(filePath, label) {
  try {
    const value = JSON.parse(fs.readFileSync(filePath, "utf8"));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("顶层不是对象");
    return value;
  } catch (error) {
    throw new ReviewError(`${label}不可读：${filePath}: ${error.message}`);
  }
}

function artifact(filePath) {
  const resolved = path.resolve(filePath);
  const relative = path.relative(ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative) || !fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    throw new ReviewError(`artifact 越界或缺失：${filePath}`);
  }
  return { path: relative.replaceAll("\\", "/"), bytes: fs.statSync(resolved).size, sha256: sha256File(resolved) };
}

function verifyArtifact(record, label) {
  if (!record || typeof record.path !== "string" || typeof record.bytes !== "number" || typeof record.sha256 !== "string") {
    throw new ReviewError(`${label} artifact 记录非法`);
  }
  const resolved = path.resolve(ROOT, record.path);
  const actual = artifact(resolved);
  if (actual.bytes !== record.bytes || actual.sha256 !== record.sha256) throw new ReviewError(`${label}字节闭包漂移`);
  return resolved;
}

function digestObject(value, field) {
  const clone = { ...value };
  delete clone[field];
  return sha256Bytes(stableStringify(clone));
}

function loadSource(sourceRoot) {
  const reportPath = path.join(sourceRoot, "orientation-visual-model-report.json");
  const auditPath = path.join(sourceRoot, "orientation-visual-audit-manifest.json");
  const report = readJson(reportPath, "orientation model report");
  const audit = readJson(auditPath, "orientation audit manifest");
  if (
    report.schema !== "cf7.production-portrait-orientation-visual-model-report.v1" ||
    report.status !== "orientation_visual_audit_completed" ||
    digestObject(report, "reportDigest") !== report.reportDigest ||
    report.counts?.assessedVariants !== 217 || report.counts?.humanReviewTotal !== 39 ||
    report.counts?.humanReviewFlipCandidates !== 11 || report.counts?.humanReviewAmbiguousOrDisagreed !== 28
  ) throw new ReviewError("orientation model report schema/digest/counts 未闭合");
  if (
    audit.schema !== "cf7.production-portrait-orientation-visual-audit-manifest.v1" ||
    digestObject(audit, "auditDigest") !== audit.auditDigest ||
    report.input?.auditDigest !== audit.auditDigest ||
    report.sourceDigest !== audit.sourceDigest
  ) throw new ReviewError("orientation audit manifest 与 model report 未闭合");
  for (const comparison of report.comparisons || []) verifyArtifact(comparison.png, `comparison PNG ${comparison.reviewKey}`);
  return { report, reportPath, audit, auditPath };
}

function buildData(source, batchId) {
  const risky = source.report.comparisons.filter((row) => row.disposition !== "model_verified_keep");
  if (
    risky.length !== 39 ||
    risky.filter((row) => row.disposition === "human_review_flip_candidate").length !== 11 ||
    new Set(risky.map((row) => row.reviewKey)).size !== 39
  ) throw new ReviewError("方向真人复核风险集合不闭合");
  const auditRows = new Map(source.audit.rows.map((row) => [row.reviewKey, row]));
  const files = [__filename, ...UI_FILES.map((relative) => path.join(ROOT, relative))].map(artifact);
  const items = risky.map((row) => {
    const auditRow = auditRows.get(row.reviewKey);
    if (!auditRow) throw new ReviewError(`audit manifest 缺 reviewKey：${row.reviewKey}`);
    return {
      reviewCode: row.reviewCode,
      reviewKey: row.reviewKey,
      portraitRef: auditRow.portraitRef,
      variantKey: auditRow.variantKey,
      currentProductionOrientationAction: row.currentProductionOrientationAction,
      orientationSource: row.orientationSource,
      disposition: row.disposition,
      proposal: row.proposal,
      independentReview: row.independentReview,
      minimumConfidence: row.minimumConfidence,
      png: row.png,
    };
  });
  const data = {
    schema: "cf7.portrait-orientation-human-review-data.v1",
    partial: false,
    productionReady: false,
    generatedAt: new Date().toISOString(),
    batchId,
    sourceDigest: source.report.sourceDigest,
    modelReportDigest: source.report.reportDigest,
    decisionSchema: "cf7.portrait-orientation-human-decisions.v1",
    input: {
      auditManifest: artifact(source.auditPath),
      auditDigest: source.audit.auditDigest,
      modelReport: artifact(source.reportPath),
      modelReportDigest: source.report.reportDigest,
      reviewer: { files, sourceClosureDigest: sha256Bytes(stableStringify(files)) },
    },
    counts: {
      reviewItems: items.length,
      flipCandidates: items.filter((row) => row.disposition === "human_review_flip_candidate").length,
      ambiguousOrDisagreed: items.filter((row) => row.disposition !== "human_review_flip_candidate").length,
      modelClosedKeepOutsideReview: source.report.counts.modelVerifiedKeep,
    },
    items,
    gates: {
      onlyModelRiskRowsIncluded: true,
      currentAndMirroredPixelsShareExactSource: true,
      noDefaultHumanDecision: true,
      allChangesRequireHumanChoice: true,
      modelClosedKeepRowsExcluded: true,
      productionWrites: false,
    },
  };
  data.reviewDigest = digestObject(data, "reviewDigest");
  return data;
}

function verifyData(data) {
  if (
    data.schema !== "cf7.portrait-orientation-human-review-data.v1" || data.partial !== false ||
    data.productionReady !== false || digestObject(data, "reviewDigest") !== data.reviewDigest ||
    data.counts?.reviewItems !== 39 || data.counts?.flipCandidates !== 11 || data.counts?.ambiguousOrDisagreed !== 28 ||
    data.counts?.modelClosedKeepOutsideReview !== 178 || data.items?.length !== 39 ||
    data.gates?.noDefaultHumanDecision !== true || data.gates?.productionWrites !== false
  ) throw new ReviewError("orientation human review data schema/digest/counts 未闭合");
  verifyArtifact(data.input.auditManifest, "human review audit manifest");
  verifyArtifact(data.input.modelReport, "human review model report");
  for (const record of data.input.reviewer?.files || []) verifyArtifact(record, "human reviewer source");
  if (sha256Bytes(stableStringify(data.input.reviewer.files)) !== data.input.reviewer.sourceClosureDigest) {
    throw new ReviewError("human reviewer source closure 漂移");
  }
  for (const item of data.items) verifyArtifact(item.png, `human review PNG ${item.reviewKey}`);
  return data;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !["build", "check"].includes(options.command) || !options.output) {
    process.stdout.write("用法：node tools/portrait-pilot/build-orientation-human-review-v1.js build --source <r202> --output <fresh> --batch-id <id> | check --output <batch>\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  if (options.command === "build") {
    if (!options.source || !options.batchId || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(options.batchId)) throw new ReviewError("build 缺合法 source/batch-id");
    const sourceRoot = pilotPath(options.source, "source", true);
    const output = pilotPath(options.output, "output", false);
    const data = verifyData(buildData(loadSource(sourceRoot), options.batchId));
    fs.mkdirSync(output);
    const dataPath = path.join(output, DATA_NAME);
    fs.writeFileSync(dataPath, `${JSON.stringify(data, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
    process.stdout.write(`${JSON.stringify({ status: "orientation_human_review_built", data: path.relative(ROOT, dataPath).replaceAll("\\", "/"), reviewDigest: data.reviewDigest, counts: data.counts })}\n`);
    return;
  }
  const output = pilotPath(options.output, "output", true);
  const data = verifyData(readJson(path.join(output, DATA_NAME), "orientation human review data"));
  process.stdout.write(`${JSON.stringify({ status: "orientation_human_review_verified", reviewDigest: data.reviewDigest, counts: data.counts })}\n`);
}

if (require.main === module) {
  try { main(); }
  catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = { ReviewError, readJson, verifyData };
