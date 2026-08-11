#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const OUTPUT_NAME = "selection-stage-model-report.json";
const SCHEMA = "cf7.portrait-pilot-reboot-selection-normalization.v1";

class NormalizeError extends Error {}

function fail(message) {
  throw new NormalizeError(message);
}

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function sha256File(filePath) {
  return sha256Bytes(fs.readFileSync(filePath));
}

function artifact(filePath) {
  const resolved = path.resolve(filePath);
  const relative = path.relative(ROOT, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative) || !fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    fail(`artifact 越界或缺失：${filePath}`);
  }
  return {
    path: relative.replaceAll("\\", "/"),
    bytes: fs.statSync(resolved).size,
    sha256: sha256File(resolved),
  };
}

function verifyArtifact(record, label) {
  if (!record || typeof record.path !== "string" || !Number.isInteger(record.bytes) || typeof record.sha256 !== "string") {
    fail(`${label} artifact 记录非法`);
  }
  const filePath = path.resolve(ROOT, record.path);
  const actual = artifact(filePath);
  if (actual.bytes !== record.bytes || actual.sha256 !== record.sha256) fail(`${label} artifact 字节闭包不匹配`);
  return filePath;
}

function readJson(filePath, label) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    fail(`${label} 不是合法 JSON：${error.message}`);
  }
}

function verifyDigest(value, field, label) {
  const envelope = structuredClone(value);
  const digest = envelope[field];
  delete envelope[field];
  if (typeof digest !== "string" || sha256Bytes(reviewBuild.stableStringify(envelope)) !== digest) {
    fail(`${label} ${field} 不匹配`);
  }
}

function parseArgs(argv) {
  const options = { input: null, output: null, check: false, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--input", "--output"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) fail(`${argument} 缺少值`);
      if (argument === "--input") options.input = value;
      else options.output = value;
      index += 1;
    } else if (argument === "--check") options.check = true;
    else if (argument === "--help") options.help = true;
    else fail(`未知参数：${argument}`);
  }
  return options;
}

function resolveInput(value) {
  const filePath = path.resolve(ROOT, value);
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) fail("输入模型报告缺失");
  return filePath;
}

function resolveOutput(value, mustExist) {
  const filePath = path.resolve(ROOT, value);
  const relative = path.relative(PILOT_ROOT, filePath);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative) || path.basename(filePath) !== OUTPUT_NAME) {
    fail(`输出必须是 tmp/portrait-pilot 子目录中的 ${OUTPUT_NAME}`);
  }
  if (mustExist && (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile())) fail("归一化报告缺失");
  if (!mustExist && fs.existsSync(filePath)) fail("归一化报告已存在，禁止覆盖");
  return filePath;
}

function acceptedAttempts(report) {
  const attempts = [];
  for (const run of report.runs || []) {
    if (run.status !== "accepted") fail(`模型角色没有 accepted：${run.role}`);
    for (const batchRun of run.batchRuns || run.batches || []) {
      const attempt = (batchRun.attempts || []).find((entry) => entry.attemptNumber === batchRun.acceptedAttempt);
      if (!attempt || attempt.status !== "accepted") fail(`模型小批次缺 accepted attempt：${run.role}/${batchRun.modelBatchId}`);
      attempts.push({ role: run.role, modelBatchId: batchRun.modelBatchId, attempt });
    }
  }
  if (attempts.length !== report.input?.scheduling?.independentRunCount) fail("accepted attempt 数量不闭合");
  return attempts;
}

function verifyAttemptArtifacts(report, attempts) {
  const manifestPath = path.resolve(ROOT, report.input.manifestPath);
  const batchRoot = path.dirname(manifestPath);
  for (const { role, modelBatchId, attempt } of attempts) {
    for (const [field, hashField, bytesField] of [
      ["stdoutArtifact", "stdoutSha256", "stdoutBytes"],
      ["stderrArtifact", "stderrSha256", "stderrBytes"],
    ]) {
      const filePath = path.resolve(batchRoot, attempt[field]);
      const relative = path.relative(batchRoot, filePath);
      if (relative.startsWith("..") || path.isAbsolute(relative) || !fs.existsSync(filePath)) {
        fail(`attempt artifact 越界或缺失：${role}/${modelBatchId}/${field}`);
      }
      if (sha256File(filePath) !== attempt[hashField] || fs.statSync(filePath).size !== attempt[bytesField]) {
        fail(`attempt artifact 字节闭包不匹配：${role}/${modelBatchId}/${field}`);
      }
    }
  }
}

function normalize(parent, parentPath) {
  verifyDigest(parent, "reportDigest", "父模型报告");
  if (
    parent.schema !== "cf7.portrait-pilot-feature-model-report.v1" ||
    parent.status !== "candidate_proposed" ||
    parent.productionReady !== false ||
    parent.gates?.selectionOnlyFirstAnswerAcceptance !== true ||
    parent.gates?.firstStageGeometryDiscarded !== true
  ) fail("父模型报告不是 selection-only 首答闭包");
  for (const record of parent.controller?.files || []) verifyArtifact(record, "父模型控制器");
  const attempts = acceptedAttempts(parent);
  verifyAttemptArtifacts(parent, attempts);
  const identities = attempts.map(({ attempt }) => Number.isInteger(attempt.pid)
    ? `pid:${attempt.pid}`
    : attempt.runIdentity);
  if (identities.some((identity) => typeof identity !== "string") || new Set(identities).size !== identities.length) {
    fail("进程或恢复 thread 身份不唯一");
  }
  const recovered = attempts.filter(({ attempt }) => attempt.recoveredAfterHostReboot === true);
  if (recovered.length < 1) fail("没有需要归一化的重启恢复 attempt");
  for (const { attempt } of recovered) {
    if (attempt.pid !== null || typeof attempt.threadId !== "string" || attempt.runIdentity !== `thread:${attempt.threadId}`) {
      fail("重启恢复 attempt 的 PID/thread 语义非法");
    }
  }
  const normalized = structuredClone(parent);
  normalized.gates.separateProcessIds = false;
  normalized.gates.orphanProcessGate = false;
  normalized.gates.separateProcessIdsPreserved = false;
  normalized.gates.distinctRecoveredThreadOrProcessIdentities = true;
  normalized.gates.rebootRecoveryEvidenceLimitedToCompletedTurnAndArtifacts = true;
  normalized.gates.freshAttemptOrphanProcessGate = true;
  normalized.gates.rebootRecoveryNormalized = true;
  normalized.rebootRecoveryNormalization = {
    schema: SCHEMA,
    parentModelReport: artifact(parentPath),
    controllerSource: artifact(__filename),
    totalAcceptedAttempts: attempts.length,
    recoveredAttemptCount: recovered.length,
    freshAttemptCount: attempts.length - recovered.length,
    distinctRunIdentities: identities,
    evidenceBoundary: "recovered attempts retain complete turn, prompt, result and artifact hashes; pre-reboot PID and orphan-process observations are not preserved",
    productionWrites: false,
  };
  delete normalized.reportDigest;
  normalized.reportDigest = sha256Bytes(reviewBuild.stableStringify(normalized));
  return normalized;
}

function verifyNormalized(report) {
  verifyDigest(report, "reportDigest", "归一化报告");
  const recovery = report.rebootRecoveryNormalization;
  if (
    recovery?.schema !== SCHEMA || recovery.productionWrites !== false ||
    report.gates?.separateProcessIds !== false || report.gates?.orphanProcessGate !== false ||
    report.gates?.rebootRecoveryNormalized !== true
  ) fail("恢复归一化 gates 不闭合");
  const parentPath = verifyArtifact(recovery.parentModelReport, "父模型报告");
  verifyArtifact(recovery.controllerSource, "恢复归一化控制器");
  const expected = normalize(readJson(parentPath, "父模型报告"), parentPath);
  if (reviewBuild.stableStringify(expected) !== reviewBuild.stableStringify(report)) {
    fail("恢复归一化报告不可由父报告确定性重放");
  }
  return acceptedAttempts(report).length;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.output || (!options.input && !options.check)) {
    process.stdout.write(`用法：node tools/portrait-pilot/normalize-reboot-selection-report-v1.js --input <model-report.json> --output <.../${OUTPUT_NAME}> [--check]\n`);
    if (!options.help) process.exitCode = 1;
    return;
  }
  const outputPath = resolveOutput(options.output, options.check);
  if (options.check) {
    const report = readJson(outputPath, "归一化报告");
    const attempts = verifyNormalized(report);
    process.stdout.write(`${JSON.stringify({ status: "reboot_selection_report_verified", reportDigest: report.reportDigest, attempts, recovery: report.rebootRecoveryNormalization })}\n`);
    return;
  }
  const inputPath = resolveInput(options.input);
  const report = normalize(readJson(inputPath, "父模型报告"), inputPath);
  fs.mkdirSync(path.dirname(outputPath), { recursive: false });
  fs.writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  verifyNormalized(report);
  process.stdout.write(`${JSON.stringify({ status: "reboot_selection_report_normalized", path: path.relative(ROOT, outputPath).replaceAll("\\", "/"), reportDigest: report.reportDigest, recovery: report.rebootRecoveryNormalization })}\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
  process.exitCode = 1;
}
