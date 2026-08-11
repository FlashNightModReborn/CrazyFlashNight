#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { sha256Bytes, sha256File, stableStringify } = require("../portrait-worker/lib/codex-cli-luna-worker");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const AUDIT_NAME = "orientation-visual-audit-manifest.json";
const REPORT_NAME = "orientation-visual-model-report.json";
const HUMAN_RECEIPT_NAME = "orientation-human-review-receipt.json";
const RECEIPT_NAME = "orientation-audit-artifact-supersession-receipt.json";

class FreezeError extends Error {}

function parseArgs(argv) {
  const options = { command: argv[0], auditRoot: null, humanReviewRoot: null, output: null };
  for (let index = 1; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--audit-root", "--human-review-root", "--output"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new FreezeError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--audit-root") options.auditRoot = value;
      if (argument === "--human-review-root") options.humanReviewRoot = value;
      if (argument === "--output") options.output = value;
    } else if (argument === "--help") options.help = true;
    else throw new FreezeError(`未知参数：${argument}`);
  }
  return options;
}

function usage() {
  return [
    "用法：",
    "  node tools/portrait-pilot/freeze-orientation-audit-artifacts-v1.js record --audit-root <r202> --human-review-root <r204> --output <fresh tmp batch>",
    "  node tools/portrait-pilot/freeze-orientation-audit-artifacts-v1.js check --output <existing tmp batch>",
  ].join("\n");
}

function pilotPath(value, label, mustExist) {
  if (!value) throw new FreezeError(`${label}不能为空`);
  const resolved = path.resolve(ROOT, value);
  const relative = path.relative(PILOT_ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new FreezeError(`${label}必须位于 tmp/portrait-pilot 下`);
  }
  if (mustExist && !fs.existsSync(resolved)) throw new FreezeError(`${label}不存在：${resolved}`);
  return resolved;
}

function readObject(filePath, label) {
  try {
    const value = JSON.parse(fs.readFileSync(filePath, "utf8"));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("顶层不是对象");
    return value;
  } catch (error) {
    throw new FreezeError(`${label}不可读：${filePath}: ${error.message}`);
  }
}

function artifact(filePath) {
  const resolved = path.resolve(filePath);
  const relative = path.relative(ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative) || !fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    throw new FreezeError(`artifact 越界或缺失：${filePath}`);
  }
  return {
    path: relative.replaceAll("\\", "/"),
    bytes: fs.statSync(resolved).size,
    sha256: sha256File(resolved),
  };
}

function assertArtifactRecord(record, label) {
  if (!record || typeof record.path !== "string" || typeof record.bytes !== "number" || typeof record.sha256 !== "string") {
    throw new FreezeError(`${label} artifact 记录非法`);
  }
}

function verifyArtifact(record, label) {
  assertArtifactRecord(record, label);
  const resolved = path.resolve(ROOT, record.path);
  const current = artifact(resolved);
  if (current.bytes !== record.bytes || current.sha256 !== record.sha256) throw new FreezeError(`${label} artifact 漂移`);
  return resolved;
}

function digestObject(value, field) {
  const clone = { ...value };
  delete clone[field];
  return sha256Bytes(stableStringify(clone));
}

function artifactKey(record) {
  assertArtifactRecord(record, "supersession original");
  return `${record.path}\u0000${record.bytes}\u0000${record.sha256}`;
}

function exactArtifact(left, right) {
  return left?.path === right?.path && left?.bytes === right?.bytes && left?.sha256 === right?.sha256;
}

function sameBytes(left, right) {
  return left?.bytes === right?.bytes && left?.sha256 === right?.sha256;
}

function requiredOriginals(audit, report) {
  const records = [
    audit.input?.productionManifest,
    ...(audit.input?.controller?.files || []),
    ...(report.controller?.files || []),
  ];
  const unique = new Map();
  for (const record of records) {
    assertArtifactRecord(record, "required original");
    unique.set(artifactKey(record), record);
  }
  return { records, unique: [...unique.values()].sort((a, b) => artifactKey(a).localeCompare(artifactKey(b))) };
}

function validateSourceDocuments(audit, report, humanReceipt, auditPath, reportPath, humanReceiptPath) {
  if (
    audit.schema !== "cf7.production-portrait-orientation-visual-audit-manifest.v1" ||
    digestObject(audit, "auditDigest") !== audit.auditDigest ||
    report.schema !== "cf7.production-portrait-orientation-visual-model-report.v1" ||
    digestObject(report, "reportDigest") !== report.reportDigest ||
    humanReceipt.schema !== "cf7.portrait-orientation-human-review-receipt.v1" ||
    digestObject(humanReceipt, "receiptDigest") !== humanReceipt.receiptDigest
  ) throw new FreezeError("r202/r204 源文档 schema 或 digest 非法");
  if (
    report.input?.auditDigest !== audit.auditDigest ||
    !exactArtifact(report.input?.auditManifest, artifact(auditPath)) ||
    humanReceipt.modelReportDigest !== report.reportDigest ||
    humanReceipt.sourceDigest !== audit.sourceDigest ||
    !exactArtifact(humanReceipt.inputs?.visualAuditManifest, artifact(auditPath)) ||
    !exactArtifact(humanReceipt.inputs?.modelReport, artifact(reportPath))
  ) throw new FreezeError("r202/r204 摘要绑定不闭合");
  const frozenSourceManifest = humanReceipt.inputs?.sourceProductionManifest;
  assertArtifactRecord(frozenSourceManifest, "r204 source production manifest");
  if (!sameBytes(frozenSourceManifest, audit.input?.productionManifest)) {
    throw new FreezeError("r204 冻结生产 manifest 与 r202 原始记录不一致");
  }
  return verifyArtifact(frozenSourceManifest, "r204 frozen source production manifest");
}

function safeFrozenName(index, original) {
  const parsed = path.parse(original.path);
  const stem = parsed.name.replace(/[^0-9A-Za-z._-]+/g, "-").slice(0, 80) || "artifact";
  const extension = parsed.ext.replace(/[^0-9A-Za-z.]+/g, "") || ".bin";
  return `${String(index + 1).padStart(3, "0")}-${stem}-${original.sha256.slice(0, 16).toLowerCase()}${extension}`;
}

function writeExclusive(filePath, bytes) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, bytes, { flag: "wx" });
}

function loadReceipt(output) {
  const receiptPath = path.join(output, RECEIPT_NAME);
  const receipt = readObject(receiptPath, "orientation audit supersession receipt");
  if (
    receipt.schema !== "cf7.portrait-orientation-artifact-supersession-receipt.v1" ||
    receipt.status !== "orientation_audit_artifacts_frozen" ||
    receipt.productionReady !== false ||
    digestObject(receipt, "receiptDigest") !== receipt.receiptDigest ||
    receipt.gates?.originalBytesPreserved !== true ||
    receipt.gates?.supersessionIsExplicitOnly !== true ||
    receipt.gates?.productionWrites !== false
  ) throw new FreezeError("supersession receipt schema/status/digest/gates 非法");

  const auditPath = verifyArtifact(receipt.inputs.auditManifest, "source audit manifest");
  const reportPath = verifyArtifact(receipt.inputs.modelReport, "source model report");
  const humanReceiptPath = verifyArtifact(receipt.inputs.humanReviewReceipt, "source human review receipt");
  verifyArtifact(receipt.inputs.controller, "freeze controller");
  const audit = readObject(auditPath, "source audit manifest");
  const report = readObject(reportPath, "source model report");
  const humanReceipt = readObject(humanReceiptPath, "source human review receipt");
  validateSourceDocuments(audit, report, humanReceipt, auditPath, reportPath, humanReceiptPath);

  if (
    receipt.sourceDigest !== audit.sourceDigest ||
    receipt.sourceAuditDigest !== audit.auditDigest ||
    receipt.sourceModelReportDigest !== report.reportDigest ||
    receipt.humanReviewReceiptDigest !== humanReceipt.receiptDigest
  ) throw new FreezeError("supersession receipt 源摘要漂移");

  const required = requiredOriginals(audit, report);
  const entries = receipt.entries || [];
  if (entries.length !== required.unique.length || receipt.counts?.uniqueArtifacts !== required.unique.length || receipt.counts?.artifactReferences !== required.records.length) {
    throw new FreezeError("supersession receipt artifact 计数不闭合");
  }
  const mappings = new Map();
  for (const entry of entries) {
    assertArtifactRecord(entry.original, "supersession original");
    const frozenPath = verifyArtifact(entry.frozen, "supersession frozen artifact");
    if (!sameBytes(entry.original, entry.frozen)) throw new FreezeError(`冻结字节与原记录不一致：${entry.original.path}`);
    const key = artifactKey(entry.original);
    if (mappings.has(key)) throw new FreezeError(`重复 supersession mapping：${entry.original.path}`);
    mappings.set(key, { ...entry, frozenPath });
  }
  for (const original of required.unique) {
    if (!mappings.has(artifactKey(original))) throw new FreezeError(`缺少 supersession mapping：${original.path}`);
  }
  return { receipt, receiptPath, mappings };
}

function record(options) {
  const auditRoot = pilotPath(options.auditRoot, "audit-root", true);
  const humanReviewRoot = pilotPath(options.humanReviewRoot, "human-review-root", true);
  const output = pilotPath(options.output, "output", false);
  if (fs.existsSync(output)) throw new FreezeError(`输出必须是全新目录：${output}`);

  const auditPath = path.join(auditRoot, AUDIT_NAME);
  const reportPath = path.join(auditRoot, REPORT_NAME);
  const humanReceiptPath = path.join(humanReviewRoot, HUMAN_RECEIPT_NAME);
  const audit = readObject(auditPath, "r202 audit manifest");
  const report = readObject(reportPath, "r202 model report");
  const humanReceipt = readObject(humanReceiptPath, "r204 human review receipt");
  const frozenSourceManifestPath = validateSourceDocuments(audit, report, humanReceipt, auditPath, reportPath, humanReceiptPath);
  const required = requiredOriginals(audit, report);

  fs.mkdirSync(path.join(output, "artifacts"), { recursive: true });
  const entries = required.unique.map((original, index) => {
    const source = exactArtifact(original, audit.input.productionManifest)
      ? frozenSourceManifestPath
      : verifyArtifact(original, `live source ${original.path}`);
    const target = path.join(output, "artifacts", safeFrozenName(index, original));
    writeExclusive(target, fs.readFileSync(source));
    const frozen = artifact(target);
    if (!sameBytes(original, frozen)) throw new FreezeError(`冻结后字节不一致：${original.path}`);
    return { original, frozen };
  });

  const receipt = {
    schema: "cf7.portrait-orientation-artifact-supersession-receipt.v1",
    status: "orientation_audit_artifacts_frozen",
    productionReady: false,
    generatedAt: new Date().toISOString(),
    sourceDigest: audit.sourceDigest,
    sourceAuditDigest: audit.auditDigest,
    sourceModelReportDigest: report.reportDigest,
    humanReviewReceiptDigest: humanReceipt.receiptDigest,
    counts: {
      artifactReferences: required.records.length,
      uniqueArtifacts: required.unique.length,
    },
    inputs: {
      auditManifest: artifact(auditPath),
      modelReport: artifact(reportPath),
      humanReviewReceipt: artifact(humanReceiptPath),
      controller: artifact(__filename),
    },
    entries,
    semantics: {
      original: "the exact artifact record embedded by the immutable r202 audit/model report",
      frozen: "an immutable byte-identical copy used only when the original live path has legitimately advanced",
    },
    gates: {
      originalBytesPreserved: true,
      supersessionIsExplicitOnly: true,
      humanDecisionClosureBound: true,
      productionWrites: false,
    },
  };
  receipt.receiptDigest = digestObject(receipt, "receiptDigest");
  writeExclusive(path.join(output, RECEIPT_NAME), `${JSON.stringify(receipt, null, 2)}\n`);
  const verified = loadReceipt(output);
  process.stdout.write(`${JSON.stringify({ status: verified.receipt.status, receipt: artifact(verified.receiptPath), receiptDigest: verified.receipt.receiptDigest, counts: verified.receipt.counts })}\n`);
}

function check(options) {
  const output = pilotPath(options.output, "output", true);
  const verified = loadReceipt(output);
  process.stdout.write(`${JSON.stringify({ status: "orientation_audit_supersession_verified", receiptDigest: verified.receipt.receiptDigest, counts: verified.receipt.counts })}\n`);
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !["record", "check"].includes(options.command)) {
    process.stdout.write(`${usage()}\n`);
    if (!options.help) process.exitCode = 1;
    return;
  }
  if (options.command === "record") record(options);
  if (options.command === "check") check(options);
}

try {
  main();
} catch (error) {
  process.stderr.write(`${JSON.stringify({ status: "orientation_audit_supersession_failed", error: error.message })}\n`);
  process.exitCode = 1;
}
