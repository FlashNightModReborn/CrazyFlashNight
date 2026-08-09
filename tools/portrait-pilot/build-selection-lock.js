#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const { loadManifest } = require("./run-visual-pilot");

const ROOT = path.resolve(__dirname, "..", "..");
const PORTRAIT_TMP = path.join(ROOT, "tmp", "portrait-pilot");
const SCHEMA = "cf7.portrait-pilot-selection-lock.v1";
const ROLES = ["proposal", "independent_review"];

function fail(message) {
  throw new reviewBuild.ReviewError(message);
}

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function relative(filePath) {
  return path.relative(ROOT, filePath).replaceAll("\\", "/");
}

function artifact(filePath) {
  return {
    path: relative(filePath),
    bytes: fs.statSync(filePath).size,
    sha256: reviewBuild.sha256File(filePath),
  };
}

function verifyArtifact(record, label) {
  if (!record || typeof record !== "object" || typeof record.path !== "string") fail(`${label} artifact 非法`);
  const filePath = path.resolve(ROOT, record.path);
  const rel = path.relative(ROOT, filePath);
  if (!rel || rel.startsWith("..") || path.isAbsolute(rel) || !fs.statSync(filePath).isFile()) {
    fail(`${label} artifact 越界或缺失`);
  }
  if (fs.statSync(filePath).size !== record.bytes || reviewBuild.sha256File(filePath) !== record.sha256) {
    fail(`${label} artifact 字节闭包不匹配`);
  }
  return filePath;
}

function verifyDigestObject(value, field, label) {
  const envelope = structuredClone(value);
  const digest = envelope[field];
  delete envelope[field];
  if (typeof digest !== "string" || sha256Bytes(reviewBuild.stableStringify(envelope)) !== digest) {
    fail(`${label} ${field} 不匹配`);
  }
}

function parseArgs(argv) {
  const options = { manifest: null, modelReport: null, output: null, check: false, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--manifest", "--model-report", "--output"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) fail(`${argument} 缺少值`);
      if (argument === "--manifest") options.manifest = value;
      if (argument === "--model-report") options.modelReport = value;
      if (argument === "--output") options.output = value;
      index += 1;
    } else if (argument === "--check") {
      options.check = true;
    } else if (argument === "--help") {
      options.help = true;
    } else {
      fail(`未知参数：${argument}`);
    }
  }
  return options;
}

function resolveOutput(value, mustExist) {
  const output = path.resolve(ROOT, value);
  const rel = path.relative(PORTRAIT_TMP, output);
  if (!rel || rel.startsWith("..") || path.isAbsolute(rel) || path.basename(output) !== "selection-lock.json") {
    fail("output 必须是 tmp/portrait-pilot 子目录中的 selection-lock.json");
  }
  if (mustExist && !fs.existsSync(output)) fail("selection-lock.json 缺失");
  if (!mustExist && fs.existsSync(output)) fail("selection-lock.json 已存在，禁止覆盖");
  return output;
}

function flagCount(selection) {
  const flags = Array.isArray(selection.flags) ? selection.flags : [];
  return flags.filter((flag) => flag !== "none").length;
}

function chooseRole(proposal, independent) {
  const proposalFlags = flagCount(proposal);
  const independentFlags = flagCount(independent);
  if (proposalFlags !== independentFlags) {
    return {
      role: proposalFlags < independentFlags ? "proposal" : "independent_review",
      reason: "fewer_non_none_flags",
    };
  }
  const proposalConfidence = Number(proposal.confidence);
  const independentConfidence = Number(independent.confidence);
  if (proposalConfidence !== independentConfidence) {
    return {
      role: proposalConfidence > independentConfidence ? "proposal" : "independent_review",
      reason: "higher_confidence_after_flag_tie",
    };
  }
  return { role: "proposal", reason: "proposal_stable_tie_break" };
}

function selectionMaps(modelReport) {
  if (modelReport.schema !== "cf7.portrait-pilot-feature-model-report.v1") {
    fail("model report schema 不受支持");
  }
  const runs = new Map();
  for (const run of modelReport.runs || []) {
    if (!ROLES.includes(run.role) || runs.has(run.role) || run.status !== "accepted") {
      fail(`model report 角色闭包非法：${run.role}`);
    }
    const selections = new Map();
    for (const selection of run.result?.selections || []) {
      if (selections.has(selection.reviewKey)) fail(`重复模型选择：${run.role}/${selection.reviewKey}`);
      selections.set(selection.reviewKey, selection);
    }
    runs.set(run.role, selections);
  }
  if (runs.size !== ROLES.length) fail("model report 缺 A/B 独立角色");
  return runs;
}

function buildRows(manifest, modelReport) {
  const eligible = (manifest.reviewItems || []).filter((item) => !item.blocked);
  const runs = selectionMaps(modelReport);
  const rows = [];
  for (const item of [...eligible].sort((a, b) => a.reviewKey.localeCompare(b.reviewKey, "zh-CN"))) {
    const proposal = runs.get("proposal").get(item.reviewKey);
    const independent = runs.get("independent_review").get(item.reviewKey);
    if (!proposal || !independent) fail(`模型选择缺行：${item.reviewKey}`);
    const picked = chooseRole(proposal, independent);
    const selected = picked.role === "proposal" ? proposal : independent;
    const candidate = (item.candidates || []).find((entry) => entry.candidateId === selected.candidateId);
    if (!candidate) fail(`锁定候选不在 manifest：${item.reviewKey}/${selected.candidateId}`);
    rows.push({
      reviewCode: item.reviewCode,
      reviewKey: item.reviewKey,
      candidateAgreement: proposal.candidateId === independent.candidateId,
      proposal: {
        candidateId: proposal.candidateId,
        nonNoneFlagCount: flagCount(proposal),
        confidence: proposal.confidence,
      },
      independentReview: {
        candidateId: independent.candidateId,
        nonNoneFlagCount: flagCount(independent),
        confidence: independent.confidence,
      },
      lockedRole: picked.role,
      candidateId: selected.candidateId,
      candidateArtifact: candidate.artifact,
      arbitrationReason: picked.reason,
    });
  }
  if (rows.length !== eligible.length) fail("selection lock 行数不闭合");
  return rows;
}

function build(options) {
  const loaded = loadManifest(options.manifest);
  const manifestPath = loaded.manifestPath;
  const manifest = loaded.manifest;
  const modelReportPath = path.resolve(ROOT, options.modelReport);
  const rel = path.relative(ROOT, modelReportPath);
  if (!rel || rel.startsWith("..") || path.isAbsolute(rel) || !fs.existsSync(modelReportPath)) fail("model report 越界或缺失");
  const modelReport = JSON.parse(fs.readFileSync(modelReportPath, "utf8"));
  verifyDigestObject(modelReport, "reportDigest", "model report");
  if (modelReport.manifestDigest !== manifest.manifestDigest || modelReport.sourceDigest !== manifest.sourceDigest) {
    fail("model report 与 manifest digest 不一致");
  }
  const rows = buildRows(manifest, modelReport);
  const output = resolveOutput(options.output, false);
  fs.mkdirSync(path.dirname(output), { recursive: true });
  const report = {
    schema: SCHEMA,
    status: "selection_locked",
    productionReady: false,
    generatedAt: new Date().toISOString(),
    input: {
      manifest: artifact(manifestPath),
      manifestDigest: manifest.manifestDigest,
      sourceDigest: manifest.sourceDigest,
      modelReport: artifact(modelReportPath),
      modelReportDigest: modelReport.reportDigest,
    },
    arbitrationPolicy: {
      order: ["fewer non-none flags", "higher confidence", "proposal stable tie-break"],
      candidatePixelsChanged: false,
      featureGeometryAccepted: false,
      humanTargetGeometryUsed: false,
    },
    controller: artifact(__filename),
    rows,
    counts: {
      rows: rows.length,
      candidateAgreements: rows.filter((row) => row.candidateAgreement).length,
      proposalLocks: rows.filter((row) => row.lockedRole === "proposal").length,
      independentReviewLocks: rows.filter((row) => row.lockedRole === "independent_review").length,
    },
    gates: {
      exactCandidateHashBinding: true,
      deterministicArbitration: true,
      localizationRequired: true,
      humanTargetGeometryExcluded: true,
      productionWrites: false,
    },
  };
  report.selectionDigest = sha256Bytes(reviewBuild.stableStringify(report));
  fs.writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  return report;
}

function check(options) {
  const output = resolveOutput(options.output, true);
  const report = JSON.parse(fs.readFileSync(output, "utf8"));
  verifyDigestObject(report, "selectionDigest", "selection lock");
  if (report.schema !== SCHEMA || report.productionReady !== false) fail("selection lock schema/productionReady 非法");
  const manifestPath = verifyArtifact(report.input?.manifest, "input manifest");
  const modelReportPath = verifyArtifact(report.input?.modelReport, "input model report");
  verifyArtifact(report.controller, "controller");
  const { manifest } = loadManifest(manifestPath);
  const modelReport = JSON.parse(fs.readFileSync(modelReportPath, "utf8"));
  verifyDigestObject(modelReport, "reportDigest", "model report");
  const expectedRows = buildRows(manifest, modelReport);
  if (reviewBuild.stableStringify(expectedRows) !== reviewBuild.stableStringify(report.rows)) {
    fail("selection lock 不可由输入确定性重放");
  }
  for (const row of report.rows) verifyArtifact(row.candidateArtifact, `candidate ${row.reviewKey}`);
  return report;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.output || (!options.check && (!options.manifest || !options.modelReport))) {
    process.stdout.write("用法：node tools/portrait-pilot/build-selection-lock.js --manifest <candidate-manifest.json> --model-report <model-report.json> --output <tmp/portrait-pilot/.../selection-lock.json> [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const report = options.check ? check(options) : build(options);
  process.stdout.write(`${JSON.stringify({
    status: options.check ? "selection_lock_verified" : report.status,
    selectionDigest: report.selectionDigest,
    counts: report.counts,
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

module.exports = { buildRows, chooseRole, flagCount };
