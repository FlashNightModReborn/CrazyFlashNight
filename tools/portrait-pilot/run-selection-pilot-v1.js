#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const Module = require("node:module");
const path = require("node:path");

const BASE_CONTROLLER = path.join(__dirname, "run-visual-pilot.js");
const EXPECTED_BASE_SHA256 = "0C12D06E8DCE05D6E00C0156FED4773C602A0F2EB8291AF9D6048D9EB8ABD538";

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function replaceExactly(source, before, after, label) {
  const first = source.indexOf(before);
  const last = source.lastIndexOf(before);
  if (first < 0 || first !== last) throw new Error(`${label} 变换锚点必须精确出现一次`);
  return `${source.slice(0, first)}${after}${source.slice(first + before.length)}`;
}

const selectionValidator = String.raw`
function validateSelectionOnlyResultV1(value, expected) {
  const exactKeysSelection = (record, keys, label) => {
    if (!record || typeof record !== "object" || Array.isArray(record)) {
      fail("RESULT_SCHEMA_INVALID", "closure", label + " 必须是对象");
    }
    const actual = Object.keys(record).sort();
    const wanted = [...keys].sort();
    if (stableStringify(actual) !== stableStringify(wanted)) {
      fail("RESULT_SCHEMA_INVALID", "closure", label + " 字段不闭合", { actual, wanted });
    }
  };
  exactKeysSelection(value, ["schema", "batchId", "sourceDigest", "promptDigest", "runRole", "selections"], "result");
  if (
    value.schema !== expected.resultSchema ||
    value.batchId !== expected.manifest.batchId ||
    value.sourceDigest !== expected.manifest.sourceDigest ||
    value.promptDigest !== expected.promptDigest ||
    value.runRole !== expected.runRole
  ) {
    fail("RESULT_CLOSURE_MISMATCH", "closure", "selection-only result 与 batch/source/prompt/role 不闭合");
  }
  if (!Array.isArray(value.selections) || value.selections.length !== expected.reviewItems.length) {
    fail("RESULT_COUNT_INVALID", "closure", "selection-only 行数不闭合");
  }
  const itemByKey = new Map(expected.reviewItems.map((item) => [item.reviewKey, item]));
  const allowedModes = new Set(["head_closeup", "feature_closeup", "feature_group", "full_subject"]);
  const allowedFlags = new Set(["effect_occlusion", "multiple_subjects", "variant_uncertain", "low_resolution", "feature_uncertain", "safe_margin_risk", "none"]);
  const seen = new Set();
  const selections = value.selections.map((selection) => {
    exactKeysSelection(selection, ["reviewKey", "candidateId", "featureLabel", "framingMode", "featureBox", "mustIncludeBox", "confidence", "flags"], "selection");
    const item = itemByKey.get(selection.reviewKey);
    if (!item || seen.has(selection.reviewKey)) {
      fail("RESULT_REVIEW_KEY_INVALID", "closure", "selection-only reviewKey 未知或重复", { reviewKey: selection.reviewKey });
    }
    seen.add(selection.reviewKey);
    if (!item.candidates.some((candidate) => candidate.candidateId === selection.candidateId)) {
      fail("RESULT_CANDIDATE_INVALID", "closure", "selection-only candidateId 不在白名单", { reviewKey: selection.reviewKey, candidateId: selection.candidateId });
    }
    if (typeof selection.featureLabel !== "string" || !selection.featureLabel.trim() || selection.featureLabel.length > 80) {
      fail("RESULT_VALUE_INVALID", "closure", "selection-only featureLabel 非法", { reviewKey: selection.reviewKey });
    }
    if (!allowedModes.has(selection.framingMode)) {
      fail("RESULT_VALUE_INVALID", "closure", "selection-only framingMode 非法", { reviewKey: selection.reviewKey });
    }
    for (const [field, box] of [["featureBox", selection.featureBox], ["mustIncludeBox", selection.mustIncludeBox]]) {
      if (!Array.isArray(box) || box.length !== 4 || box.some((entry) => typeof entry !== "number" || !Number.isFinite(entry) || entry < 0 || entry > 1)) {
        fail("RESULT_VALUE_INVALID", "closure", "selection-only " + field + " 不是四个 0..1 有限数", { reviewKey: selection.reviewKey });
      }
    }
    if (typeof selection.confidence !== "number" || !Number.isFinite(selection.confidence) || selection.confidence < 0 || selection.confidence > 1) {
      fail("RESULT_VALUE_INVALID", "closure", "selection-only confidence 非法", { reviewKey: selection.reviewKey });
    }
    if (
      !Array.isArray(selection.flags) || selection.flags.length < 1 ||
      selection.flags.some((flag) => !allowedFlags.has(flag)) ||
      new Set(selection.flags).size !== selection.flags.length ||
      (selection.flags.includes("none") && selection.flags.length !== 1)
    ) {
      fail("RESULT_VALUE_INVALID", "closure", "selection-only flags 非法", { reviewKey: selection.reviewKey });
    }
    return {
      ...selection,
      featureBox: [0.25, 0.25, 0.75, 0.75],
      mustIncludeBox: [0.2, 0.2, 0.8, 0.8],
    };
  });
  if (seen.size !== itemByKey.size) fail("RESULT_COUNT_INVALID", "closure", "selection-only reviewKey 未闭合");
  return {
    ...value,
    selections: selections.sort((left, right) => left.reviewKey.localeCompare(right.reviewKey, "zh-CN")),
  };
}

`;

const rebootRecovery = String.raw`
function loadRebootRecoveredAttemptV1(options, role, artifactsDirectory) {
  const base = role + "-" + options.modelBatchId + "-attempt-1";
  const stdoutPath = path.join(artifactsDirectory, base + ".stdout.jsonl");
  const stderrPath = path.join(artifactsDirectory, base + ".stderr.log");
  const stdoutExists = fs.existsSync(stdoutPath);
  const stderrExists = fs.existsSync(stderrPath);
  if (!stdoutExists && !stderrExists) return null;
  if (!stdoutExists || !stderrExists) {
    fail("REBOOT_RECOVERY_ARTIFACT_INCOMPLETE", "closure", "重启恢复的 stdout/stderr 不成对", { role, modelBatchId: options.modelBatchId });
  }
  const stdout = fs.readFileSync(stdoutPath, "utf8");
  const stderr = fs.readFileSync(stderrPath, "utf8");
  const prompt = createPrompt(
    options.manifest,
    options.reviewItems,
    role,
    options.modelBatchId,
    options.contactSheet,
    options.imageInputs,
    null,
  );
  const events = parseJsonl(stdout);
  const finalMessage = extractFinalAgentMessage(events);
  let parsed;
  try {
    parsed = JSON.parse(finalMessage.text);
  } catch (error) {
    fail("RESULT_JSON_INVALID", "closure", "重启恢复的 agent_message 不是 JSON", { cause: error.message });
  }
  const result = validateSelectionOnlyResultV1(parsed, {
    manifest: options.manifest,
    reviewItems: options.reviewItems,
    promptDigest: prompt.promptDigest,
    runRole: role,
    selectionMode: options.selectionMode,
    resultSchema: options.resultSchema,
  });
  if (!finalMessage.threadId) {
    fail("REBOOT_RECOVERY_THREAD_ID_MISSING", "closure", "重启恢复首答缺少 thread id", { role, modelBatchId: options.modelBatchId });
  }
  const evidence = {
    attemptNumber: 1,
    pid: null,
    startedAt: null,
    endedAt: null,
    durationMs: null,
    exitCode: 0,
    signal: null,
    timedOut: false,
    terminationReason: "completed_before_host_reboot",
    observedDescendantPids: [],
    normalExitOrphanPids: [],
    terminatedTreePids: [],
    survivorPids: [],
    modelRequested: MODEL,
    reasoningEffort: EFFORT,
    serviceTier: options.serviceTier,
    modelBatchId: options.modelBatchId,
    sourceDigest: options.manifest.sourceDigest,
    contactSheetSha256: sha256File(options.contactSheetPath),
    imageLayout: options.imageLayout,
    imageInputs: options.imageInputs.map((entry) => ({
      role: entry.role,
      path: path.relative(ROOT, entry.path).replaceAll("\\", "/"),
      sha256: sha256File(entry.path),
    })),
    promptDigest: prompt.promptDigest,
    transmittedPromptSha256: prompt.transmittedPromptSha256,
    outputSchemaSha256: sha256File(options.outputSchemaPath),
    stdoutSha256: sha256Bytes(stdout),
    stderrSha256: sha256Bytes(stderr),
    stdoutBytes: Buffer.byteLength(stdout),
    stderrBytes: Buffer.byteLength(stderr),
    threadId: finalMessage.threadId,
    agentMessageCount: finalMessage.agentMessageCount,
    recoverableDiagnostics: finalMessage.recoverableDiagnostics,
    recoverableDiagnosticDigest: sha256Bytes(stableStringify(finalMessage.recoverableDiagnostics)),
    resultSha256: sha256Bytes(stableStringify(result)),
    status: "accepted",
    recoveredAfterHostReboot: true,
    runIdentity: "thread:" + finalMessage.threadId,
    stdoutArtifact: "model-artifacts/" + base + ".stdout.jsonl",
    stderrArtifact: "model-artifacts/" + base + ".stderr.log",
  };
  return {
    modelBatchId: options.modelBatchId,
    role,
    status: "accepted",
    attempts: [evidence],
    acceptedAttempt: 1,
    result,
  };
}

`;

function transformedSource() {
  const bytes = fs.readFileSync(BASE_CONTROLLER);
  if (sha256(bytes) !== EXPECTED_BASE_SHA256) {
    throw new Error("基础视觉控制器字节已漂移；拒绝运行未经复核的 selection 变换");
  }
  let source = bytes.toString("utf8");
  source = replaceExactly(
    source,
    "async function runAttempt(worker, options, role, attemptNumber) {",
    `${selectionValidator}${rebootRecovery}async function runAttempt(worker, options, role, attemptNumber) {`,
    "selection validator",
  );
  source = replaceExactly(
    source,
    "const result = validateResult(parsed, {",
    "const result = validateSelectionOnlyResultV1(parsed, {",
    "selection validation call",
  );
  source = replaceExactly(source, "const maximumAttempts = 3;", "const maximumAttempts = 1;", "single-attempt policy");
  source = replaceExactly(
    source,
    "async function runRole(worker, options, role, artifactsDirectory) {\n  const attempts = [];",
    "async function runRole(worker, options, role, artifactsDirectory) {\n  const recovered = loadRebootRecoveredAttemptV1(options, role, artifactsDirectory);\n  if (recovered) return recovered;\n  const attempts = [];",
    "reboot attempt reuse",
  );
  source = replaceExactly(
    source,
    '  if (fs.existsSync(artifactsDirectory)) fail("OUTPUT_EXISTS", "output", "model-artifacts 已存在，禁止覆盖");\n  fs.mkdirSync(artifactsDirectory);',
    '  if (!fs.existsSync(artifactsDirectory)) fs.mkdirSync(artifactsDirectory);',
    "reboot artifact reuse",
  );
  source = replaceExactly(
    source,
    '  const acceptedPids = acceptedAttempts.map((attempt) => attempt.pid);\n  if (new Set(acceptedPids).size !== acceptedPids.length) {\n    fail("RUN_INDEPENDENCE_FAILED", "closure", "所有 A/B 小批次必须使用不同 PID");\n  }',
    '  const acceptedRunIdentities = acceptedAttempts.map((attempt) => Number.isInteger(attempt.pid) ? "pid:" + attempt.pid : attempt.runIdentity);\n  if (acceptedRunIdentities.some((identity) => typeof identity !== "string") || new Set(acceptedRunIdentities).size !== acceptedRunIdentities.length) {\n    fail("RUN_INDEPENDENCE_FAILED", "closure", "所有 A/B 小批次必须保留不同进程或重启恢复 thread 身份");\n  }',
    "reboot run independence",
  );
  source = replaceExactly(
    source,
    "    __filename,\n    LEGACY_SCHEMA_PATH,",
    "    __filename,\n    BASE_SELECTION_CONTROLLER_PATH,\n    LEGACY_SCHEMA_PATH,",
    "controller evidence",
  );
  source = replaceExactly(
    source,
    "const FEATURE_SCHEMA_PATH =",
    `const BASE_SELECTION_CONTROLLER_PATH = ${JSON.stringify(BASE_CONTROLLER)};\nconst FEATURE_SCHEMA_PATH =`,
    "base controller binding",
  );
  source = replaceExactly(
    source,
    'version: "portrait-pilot-p2-p3-feature-v9-two-stage-selection-localization",',
    'version: "portrait-pilot-selection-v1-first-answer-candidate-only",',
    "controller version",
  );
  source = replaceExactly(
    source,
    "      humanArtAcceptance: false,",
    "      selectionOnlyFirstAnswerAcceptance: true,\n      firstStageGeometryDiscarded: true,\n      maximumAttemptsPerJob: 1,\n      separateProcessIdsPreserved: acceptedAttempts.every((attempt) => Number.isInteger(attempt.pid)),\n      distinctRecoveredThreadOrProcessIdentities: true,\n      rebootRecoveredAttemptCount: acceptedAttempts.filter((attempt) => attempt.recoveredAfterHostReboot === true).length,\n      humanArtAcceptance: false,",
    "selection gates",
  );
  source = replaceExactly(source, "if (require.main === module) {", "if (true) {", "entrypoint");
  return source;
}

function main() {
  const compiled = new Module(__filename, module.parent);
  compiled.filename = __filename;
  compiled.paths = Module._nodeModulePaths(__dirname);
  compiled._compile(transformedSource(), __filename);
}

try {
  main();
} catch (error) {
  process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
  process.exitCode = 1;
}
