#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const selectionOnly = require("./derive-selection-only-report-v1");
const { createPrompt, loadManifest } = require("./run-visual-pilot");

const ROOT = path.resolve(__dirname, "..", "..");
const PORTRAIT_TMP = path.join(ROOT, "tmp", "portrait-pilot");
const RECOVERY_NAME = "adjacent-digest-recovery.json";
const MANIFEST_NAME = "candidate-manifest.json";
const FAILURE_NAME = "model-failure-report.json";
const RECOVERY_SCHEMA = "cf7.portrait-pilot-adjacent-digest-recovery.v1";
const FAILURE_SCHEMA = "cf7.portrait-pilot-model-failure-report.v1";

class RecoveryError extends Error {}

function fail(message) {
  throw new RecoveryError(message);
}

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function sha256File(filePath) {
  return sha256Bytes(fs.readFileSync(filePath));
}

function relative(filePath) {
  return path.relative(ROOT, filePath).replaceAll("\\", "/");
}

function artifact(filePath) {
  return {
    path: relative(filePath),
    bytes: fs.statSync(filePath).size,
    sha256: sha256File(filePath),
  };
}

function byteArtifact(filePath, bytes) {
  return {
    path: relative(filePath),
    bytes: bytes.length,
    sha256: sha256Bytes(bytes),
  };
}

function verifyArtifact(record, label) {
  if (!record || typeof record.path !== "string" || !Number.isInteger(record.bytes) || typeof record.sha256 !== "string") {
    fail(`${label} artifact 非法`);
  }
  const filePath = path.resolve(ROOT, record.path);
  const rel = path.relative(ROOT, filePath);
  if (!rel || rel.startsWith("..") || path.isAbsolute(rel) || !fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    fail(`${label} artifact 越界或缺失`);
  }
  const actual = artifact(filePath);
  if (reviewBuild.stableStringify(actual) !== reviewBuild.stableStringify(record)) {
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
  const options = { manifest: null, failureReport: null, outputDir: null, check: false, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--manifest", "--failure-report", "--output-dir"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) fail(`${argument} 缺少值`);
      if (argument === "--manifest") options.manifest = value;
      if (argument === "--failure-report") options.failureReport = value;
      if (argument === "--output-dir") options.outputDir = value;
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

function resolveRepoFile(value, label) {
  const filePath = path.resolve(ROOT, value);
  const rel = path.relative(ROOT, filePath);
  if (!rel || rel.startsWith("..") || path.isAbsolute(rel) || !fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    fail(`${label} 越界或缺失`);
  }
  return filePath;
}

function resolveOutputDir(value, mustExist) {
  const outputDir = path.resolve(ROOT, value);
  const rel = path.relative(PORTRAIT_TMP, outputDir);
  if (!rel || rel.startsWith("..") || path.isAbsolute(rel)) {
    fail("output-dir 必须是 tmp/portrait-pilot 下的独立批目录");
  }
  if (mustExist && (!fs.existsSync(outputDir) || !fs.statSync(outputDir).isDirectory())) {
    fail("recovery output-dir 缺失");
  }
  if (!mustExist && fs.existsSync(outputDir)) fail("recovery output-dir 已存在，禁止覆盖");
  return outputDir;
}

function parseAgentResult(stdoutPath) {
  const text = fs.readFileSync(stdoutPath, "utf8");
  const sourceLines = text.split(/\r?\n/).filter(Boolean);
  const events = sourceLines.map((line, index) => {
    try {
      return JSON.parse(line);
    } catch (error) {
      fail(`stdout JSONL 第 ${index + 1} 行非法：${error.message}`);
    }
  });
  if (!events.some((event) => event.type === "turn.started") || !events.some((event) => event.type === "turn.completed")) {
    fail("失败首答没有完整 turn");
  }
  const messages = events.filter((event) => event.type === "item.completed" && event.item?.type === "agent_message");
  if (messages.length !== 1 || typeof messages[0].item.text !== "string") {
    fail("失败首答必须恰好含一个 agent_message");
  }
  let result;
  try {
    result = JSON.parse(messages[0].item.text);
  } catch (error) {
    fail(`失败首答 agent_message 不是 JSON：${error.message}`);
  }
  const diagnostics = events
    .filter((event) => event.type === "error" || (event.type === "item.completed" && event.item?.type === "error"))
    .map((event) => event.type === "error" ? event.message : event.item.message);
  return { events, messages, result, diagnostics };
}

function adjacentTransposition(actual, expected) {
  if (!/^[0-9A-F]{64}$/.test(actual || "") || !/^[0-9A-F]{64}$/.test(expected || "") || actual === expected) {
    fail("promptDigest 不是两个不同的 64 位大写十六进制值");
  }
  const mismatches = [];
  for (let index = 0; index < expected.length; index += 1) {
    if (actual[index] !== expected[index]) mismatches.push(index);
  }
  if (
    mismatches.length !== 2 ||
    mismatches[1] !== mismatches[0] + 1 ||
    actual[mismatches[0]] !== expected[mismatches[1]] ||
    actual[mismatches[1]] !== expected[mismatches[0]]
  ) {
    fail("promptDigest 差异不是唯一一次相邻字符换位");
  }
  return mismatches;
}

function controllerEvidence() {
  const files = [
    __filename,
    path.join(__dirname, "derive-selection-only-report-v1.js"),
    path.join(__dirname, "run-visual-pilot.js"),
    path.join(__dirname, "schemas", "feature-selection.schema.json"),
  ].map(artifact);
  return {
    version: "portrait-pilot-adjacent-digest-recovery-v1",
    files,
    sourceClosureDigest: sha256Bytes(reviewBuild.stableStringify(files)),
  };
}

function loadSource(manifestPath, failureReportPath) {
  const loaded = loadManifest(relative(manifestPath));
  const failureReport = JSON.parse(fs.readFileSync(failureReportPath, "utf8"));
  verifyDigestObject(failureReport, "reportDigest", "source model failure report");
  if (
    failureReport.schema !== FAILURE_SCHEMA ||
    failureReport.status !== "model_run_failed" ||
    failureReport.productionReady !== false ||
    failureReport.input?.manifestPath !== relative(manifestPath) ||
    failureReport.input?.manifestSha256 !== sha256File(manifestPath) ||
    failureReport.manifestDigest !== loaded.manifest.manifestDigest ||
    failureReport.sourceDigest !== loaded.manifest.sourceDigest
  ) {
    fail("source failure report 与 manifest 闭包不匹配");
  }
  if (
    failureReport.input?.localizationViews !== null ||
    failureReport.input?.expectedIndependentRuns !== loaded.modelBatches.length * 2 ||
    failureReport.gates?.failurePersisted !== true ||
    failureReport.gates?.partialSuccessNotPromoted !== true ||
    failureReport.gates?.productionWrites !== false
  ) {
    fail("source failure report 不是 selection-only fail-closed 批");
  }
  for (const record of failureReport.modelArtifacts || []) verifyArtifact(record, `source ${record?.path || "artifact"}`);
  return { loaded, failureReport };
}

function validateFailedAttempt(source, manifestPath) {
  const { loaded, failureReport } = source;
  const failed = failureReport.failedRun;
  const details = failed?.error?.details;
  const attempts = details?.attempts;
  const terminal = details?.terminalError;
  if (
    failed?.error?.code !== "RUN_RETRIES_EXHAUSTED" ||
    failed.error.phase !== "closure" ||
    terminal?.code !== "RESULT_CLOSURE_MISMATCH" ||
    terminal.phase !== "closure" ||
    !Array.isArray(attempts) || attempts.length !== 1
  ) {
    fail("只允许恢复唯一一次 RESULT_CLOSURE_MISMATCH 首答");
  }
  const attempt = attempts[0];
  if (
    attempt.attemptNumber !== 1 || attempt.status !== "rejected" ||
    attempt.error?.code !== "RESULT_CLOSURE_MISMATCH" || attempt.error?.phase !== "closure" ||
    attempt.exitCode !== 0 || attempt.signal !== null || attempt.timedOut !== false || attempt.terminationReason !== null ||
    (attempt.normalExitOrphanPids || []).length !== 0 || (attempt.survivorPids || []).length !== 0
  ) {
    fail("失败首答的退出/进程/错误证据不满足无副作用恢复条件");
  }
  const role = failed.role;
  const modelBatchId = details.modelBatchId;
  const batch = loaded.modelBatches.find((entry) => entry.modelBatchId === modelBatchId);
  if (!batch || !["proposal", "independent_review"].includes(role) || attempt.modelBatchId !== modelBatchId) {
    fail("失败首答 role/modelBatchId 不闭合");
  }
  const sourceDirRel = path.posix.dirname(relative(manifestPath));
  const stdoutRel = `${sourceDirRel}/model-artifacts/${role}-${modelBatchId}-attempt-1.stdout.jsonl`;
  const stderrRel = `${sourceDirRel}/model-artifacts/${role}-${modelBatchId}-attempt-1.stderr.log`;
  const stdoutRecord = failureReport.modelArtifacts.find((record) => record.path === stdoutRel);
  const stderrRecord = failureReport.modelArtifacts.find((record) => record.path === stderrRel);
  if (!stdoutRecord || !stderrRecord) fail("失败首答 stdout/stderr inventory 缺失");
  const stdoutPath = verifyArtifact(stdoutRecord, "failed stdout");
  verifyArtifact(stderrRecord, "failed stderr");
  if (
    attempt.stdoutSha256 !== stdoutRecord.sha256 || attempt.stdoutBytes !== stdoutRecord.bytes ||
    attempt.stderrSha256 !== stderrRecord.sha256 || attempt.stderrBytes !== stderrRecord.bytes
  ) {
    fail("失败首答 attempt 与 artifact inventory 不一致");
  }
  const prompt = createPrompt(
    loaded.manifest,
    batch.reviewItems,
    role,
    batch.modelBatchId,
    batch.contactSheet,
    batch.imageInputs,
    null,
  );
  if (attempt.promptDigest !== prompt.promptDigest) fail("失败 attempt 记录的 expected promptDigest 不匹配");
  const parsed = parseAgentResult(stdoutPath);
  if (
    !parsed.diagnostics.some((message) => /request timed out/i.test(message || "")) ||
    !parsed.diagnostics.some((message) => /Falling back from WebSockets to HTTPS transport/i.test(message || ""))
  ) {
    fail("失败首答缺少超时与 HTTPS 回退诊断，拒绝扩大恢复边界");
  }
  const mismatchIndices = adjacentTransposition(parsed.result?.promptDigest, prompt.promptDigest);
  if (
    parsed.result?.schema !== "cf7.portrait-pilot-feature-selection.v1" ||
    parsed.result.batchId !== loaded.manifest.batchId ||
    parsed.result.sourceDigest !== loaded.manifest.sourceDigest ||
    parsed.result.runRole !== role
  ) {
    fail("失败首答除 promptDigest 外仍有闭包字段不匹配");
  }
  const normalizedResult = structuredClone(parsed.result);
  normalizedResult.promptDigest = prompt.promptDigest;
  const validatedResult = selectionOnly.validateSelectionOnlyResult(normalizedResult, {
    manifest: loaded.manifest,
    reviewItems: batch.reviewItems,
    promptDigest: prompt.promptDigest,
    role,
  });
  const rawWithoutDigest = structuredClone(parsed.result);
  const normalizedWithoutDigest = structuredClone(normalizedResult);
  delete rawWithoutDigest.promptDigest;
  delete normalizedWithoutDigest.promptDigest;
  if (reviewBuild.stableStringify(rawWithoutDigest) !== reviewBuild.stableStringify(normalizedWithoutDigest)) {
    fail("规范化意外改变了 promptDigest 之外的结果字段");
  }
  return {
    role,
    modelBatchId,
    batch,
    attempt,
    prompt,
    stdoutPath,
    stdoutRecord,
    stderrRecord,
    parsed,
    normalizedResult,
    validatedResult,
    mismatchIndices,
  };
}

function normalizedStdoutBytes(target) {
  let changed = 0;
  const lines = target.parsed.events.map((event) => {
    const clone = structuredClone(event);
    if (clone.type === "item.completed" && clone.item?.type === "agent_message") {
      clone.item.text = JSON.stringify(target.normalizedResult);
      changed += 1;
    }
    return JSON.stringify(clone);
  });
  if (changed !== 1) fail("规范化必须只改一个 agent_message");
  return Buffer.from(`${lines.join("\n")}\n`, "utf8");
}

function createBundle(manifestPath, failureReportPath, outputDir, generatedAt) {
  const source = loadSource(manifestPath, failureReportPath);
  const target = validateFailedAttempt(source, manifestPath);
  const outputManifestPath = path.join(outputDir, MANIFEST_NAME);
  const outputFailurePath = path.join(outputDir, FAILURE_NAME);
  const outputRecoveryPath = path.join(outputDir, RECOVERY_NAME);
  const sourceDir = path.dirname(manifestPath);
  const manifestBytes = fs.readFileSync(manifestPath);
  const normalizedBytes = normalizedStdoutBytes(target);
  const copiedArtifacts = [];
  for (const record of source.failureReport.modelArtifacts) {
    const sourcePath = path.resolve(ROOT, record.path);
    const within = path.relative(sourceDir, sourcePath);
    if (!within || within.startsWith("..") || path.isAbsolute(within) || within.split(path.sep)[0] !== "model-artifacts") {
      fail(`source model artifact 不在批目录 model-artifacts 下：${record.path}`);
    }
    const outputPath = path.join(outputDir, within);
    const isTarget = sourcePath === target.stdoutPath;
    const bytes = isTarget ? normalizedBytes : fs.readFileSync(sourcePath);
    copiedArtifacts.push({ sourcePath, outputPath, bytes, record: byteArtifact(outputPath, bytes), isTarget });
  }
  if (copiedArtifacts.filter((entry) => entry.isTarget).length !== 1) fail("规范化目标 artifact 数量不是 1");
  const controller = controllerEvidence();
  const repair = {
    kind: "single_adjacent_prompt_digest_transposition",
    role: target.role,
    modelBatchId: target.modelBatchId,
    attemptNumber: 1,
    rawPromptDigest: target.parsed.result.promptDigest,
    expectedPromptDigest: target.prompt.promptDigest,
    mismatchIndices: target.mismatchIndices,
    rawResultSha256: sha256Bytes(reviewBuild.stableStringify(target.parsed.result)),
    normalizedResultSha256: sha256Bytes(reviewBuild.stableStringify(target.normalizedResult)),
    selectionsSha256: sha256Bytes(reviewBuild.stableStringify(target.validatedResult.selections)),
    changedResultFields: ["promptDigest"],
    diagnosticDigest: sha256Bytes(reviewBuild.stableStringify(target.parsed.diagnostics)),
  };
  const replayFailure = structuredClone(source.failureReport);
  replayFailure.input.manifestPath = relative(outputManifestPath);
  replayFailure.input.manifestSha256 = sha256Bytes(manifestBytes);
  replayFailure.modelArtifacts = copiedArtifacts.map((entry) => entry.record);
  replayFailure.closureRecovery = {
    schema: RECOVERY_SCHEMA,
    status: "normalized_replay_input",
    generatedAt,
    controller,
    sourceManifest: artifact(manifestPath),
    sourceFailureReport: artifact(failureReportPath),
    sourceRawStdout: artifact(target.stdoutPath),
    normalizedStdout: byteArtifact(copiedArtifacts.find((entry) => entry.isTarget).outputPath, normalizedBytes),
    repair,
    gates: {
      sourceEvidencePreserved: true,
      exactlyOneAgentMessage: true,
      exactlyOneAdjacentTransposition: true,
      resultFieldsOtherThanPromptDigestUnchanged: true,
      selectionsUnchanged: true,
      processExitedZeroWithoutSurvivors: true,
      timeoutAndHttpsFallbackObserved: true,
      humanReviewStillRequired: true,
      productionWrites: false,
    },
  };
  delete replayFailure.reportDigest;
  replayFailure.reportDigest = sha256Bytes(reviewBuild.stableStringify(replayFailure));
  const replayFailureBytes = Buffer.from(`${JSON.stringify(replayFailure, null, 2)}\n`, "utf8");
  const recoveryReport = {
    schema: RECOVERY_SCHEMA,
    status: "normalized_replay_bundle_ready",
    productionReady: false,
    humanReviewRequired: true,
    generatedAt,
    batchId: source.loaded.manifest.batchId,
    sourceDigest: source.loaded.manifest.sourceDigest,
    manifestDigest: source.loaded.manifest.manifestDigest,
    controller,
    source: {
      manifest: artifact(manifestPath),
      failureReport: artifact(failureReportPath),
      rawStdout: artifact(target.stdoutPath),
    },
    output: {
      manifest: byteArtifact(outputManifestPath, manifestBytes),
      failureReport: byteArtifact(outputFailurePath, replayFailureBytes),
      normalizedStdout: replayFailure.closureRecovery.normalizedStdout,
      copiedModelArtifactCount: copiedArtifacts.length,
    },
    repair,
    gates: replayFailure.closureRecovery.gates,
  };
  recoveryReport.reportDigest = sha256Bytes(reviewBuild.stableStringify(recoveryReport));
  const recoveryBytes = Buffer.from(`${JSON.stringify(recoveryReport, null, 2)}\n`, "utf8");
  return {
    source,
    copiedArtifacts,
    outputManifestPath,
    outputFailurePath,
    outputRecoveryPath,
    manifestBytes,
    replayFailureBytes,
    recoveryBytes,
    recoveryReport,
  };
}

function build(options) {
  const manifestPath = resolveRepoFile(options.manifest, "manifest");
  const failureReportPath = resolveRepoFile(options.failureReport, "failure report");
  const outputDir = resolveOutputDir(options.outputDir, false);
  const bundle = createBundle(manifestPath, failureReportPath, outputDir, new Date().toISOString());
  fs.mkdirSync(path.join(outputDir, "model-artifacts"), { recursive: true });
  fs.writeFileSync(bundle.outputManifestPath, bundle.manifestBytes, { flag: "wx" });
  for (const entry of bundle.copiedArtifacts) {
    fs.mkdirSync(path.dirname(entry.outputPath), { recursive: true });
    fs.writeFileSync(entry.outputPath, entry.bytes, { flag: "wx" });
  }
  fs.writeFileSync(bundle.outputFailurePath, bundle.replayFailureBytes, { flag: "wx" });
  fs.writeFileSync(bundle.outputRecoveryPath, bundle.recoveryBytes, { flag: "wx" });
  return bundle.recoveryReport;
}

function check(options) {
  const outputDir = resolveOutputDir(options.outputDir, true);
  const recoveryPath = path.join(outputDir, RECOVERY_NAME);
  if (!fs.existsSync(recoveryPath) || !fs.statSync(recoveryPath).isFile()) fail(`${RECOVERY_NAME} 缺失`);
  const report = JSON.parse(fs.readFileSync(recoveryPath, "utf8"));
  verifyDigestObject(report, "reportDigest", "adjacent digest recovery report");
  if (
    report.schema !== RECOVERY_SCHEMA || report.status !== "normalized_replay_bundle_ready" ||
    report.productionReady !== false || report.humanReviewRequired !== true
  ) {
    fail("adjacent digest recovery report schema/status 非法");
  }
  for (const file of report.controller?.files || []) verifyArtifact(file, "recovery controller");
  const manifestPath = verifyArtifact(report.source?.manifest, "source manifest");
  const failureReportPath = verifyArtifact(report.source?.failureReport, "source failure report");
  verifyArtifact(report.source?.rawStdout, "source raw stdout");
  const expected = createBundle(manifestPath, failureReportPath, outputDir, report.generatedAt);
  if (reviewBuild.stableStringify(expected.recoveryReport) !== reviewBuild.stableStringify(report)) {
    fail("adjacent digest recovery report 不可由原始失败证据确定性重放");
  }
  const outputs = [
    [expected.outputManifestPath, expected.manifestBytes, "output manifest"],
    [expected.outputFailurePath, expected.replayFailureBytes, "output failure report"],
    [expected.outputRecoveryPath, expected.recoveryBytes, "output recovery report"],
    ...expected.copiedArtifacts.map((entry) => [entry.outputPath, entry.bytes, `output ${relative(entry.outputPath)}`]),
  ];
  for (const [filePath, bytes, label] of outputs) {
    if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile() || !fs.readFileSync(filePath).equals(bytes)) {
      fail(`${label} 与确定性重放结果不一致`);
    }
  }
  return report;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.outputDir || (!options.check && (!options.manifest || !options.failureReport))) {
    process.stdout.write("用法：node tools/portrait-pilot/recover-selection-adjacent-digest-v1.js --manifest <candidate-manifest.json> --failure-report <model-failure-report.json> --output-dir <tmp/portrait-pilot/...> [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const report = options.check ? check(options) : build(options);
  process.stdout.write(`${JSON.stringify({
    status: options.check ? "adjacent_digest_recovery_verified" : report.status,
    reportDigest: report.reportDigest,
    repair: report.repair,
    gates: report.gates,
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

module.exports = { adjacentTransposition, createBundle };
