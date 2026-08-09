#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {
  CodexCliLunaWorker,
  WorkerError,
  extractFinalAgentMessage,
  parseJsonl,
  publicError,
  requireAbsoluteFile,
  sha256Bytes,
  sha256File,
  spawnCaptured,
  stableStringify,
} = require("../portrait-worker/lib/codex-cli-luna-worker");

const ROOT = path.resolve(__dirname, "..", "..");
const INPUT_SCHEMA = "cf7.enemy-portrait-internal-subject-rescue-candidates.v1";
const RESULT_SCHEMA = "cf7.enemy-portrait-internal-subject-rescue-selection.v1";
const REPORT_SCHEMA = "cf7.enemy-portrait-internal-subject-rescue-model-report.v1";
const FAILURE_SCHEMA = "cf7.enemy-portrait-internal-subject-rescue-model-failure.v1";
const OUTPUT_SCHEMA_PATH = path.join(__dirname, "schemas", "internal-subject-rescue-selection-v1.schema.json");
const WORKER_PATH = path.join(ROOT, "tools", "portrait-worker", "lib", "codex-cli-luna-worker.js");
const MODEL = "gpt-5.6-luna";
const EFFORT = "max";
const ROLES = ["proposal", "independent_review"];

// Python's sort_keys=True keeps string keys lexicographically ordered, even
// when every key looks like an integer.  Building an intermediate JS object
// would re-enumerate those keys numerically, so serialize the sorted pairs
// directly when validating manifests emitted by the Python candidate builder.
function pythonStableStringify(value) {
  if (Array.isArray(value)) return `[${value.map(pythonStableStringify).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${pythonStableStringify(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function fail(code, phase, message, details = {}) {
  throw new WorkerError(code, phase, message, details);
}

function exactKeys(value, expected, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("RESULT_SCHEMA_INVALID", "closure", `${label} 必须是对象`);
  }
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (stableStringify(actual) !== stableStringify(wanted)) {
    fail("RESULT_SCHEMA_INVALID", "closure", `${label} 字段不闭合`, { actual, wanted });
  }
}

function parseArgs(argv) {
  const options = {
    codexExe: process.env.CF7_PORTRAIT_CODEX_EXE || null,
    manifest: null,
    output: null,
    timeoutMs: 600_000,
    maxConcurrency: 6,
    serviceTier: "fast",
    check: false,
  };
  const valued = new Set([
    "--codex-exe",
    "--manifest",
    "--output",
    "--timeout-ms",
    "--max-concurrency",
    "--service-tier",
  ]);
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (valued.has(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) fail("ARGUMENT_MISSING", "arguments", `${argument} 缺少值`);
      index += 1;
      if (argument === "--codex-exe") options.codexExe = value;
      if (argument === "--manifest") options.manifest = value;
      if (argument === "--output") options.output = value;
      if (argument === "--timeout-ms") options.timeoutMs = Number(value);
      if (argument === "--max-concurrency") options.maxConcurrency = Number(value);
      if (argument === "--service-tier") options.serviceTier = value;
    } else if (argument === "--check") {
      options.check = true;
    } else if (argument === "--help") {
      options.help = true;
    } else {
      fail("ARGUMENT_UNKNOWN", "arguments", `未知参数：${argument}`);
    }
  }
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs < 30_000 || options.timeoutMs > 600_000) {
    fail("TIMEOUT_INVALID", "arguments", "timeout 必须是 30000–600000 的整数毫秒");
  }
  if (!Number.isInteger(options.maxConcurrency) || options.maxConcurrency < 1 || options.maxConcurrency > 12) {
    fail("CONCURRENCY_INVALID", "arguments", "max concurrency 必须是 1–12 的整数");
  }
  if (!["standard", "fast"].includes(options.serviceTier)) {
    fail("SERVICE_TIER_INVALID", "arguments", "service tier 必须是 standard 或 fast");
  }
  return options;
}

function usage() {
  return [
    "用法：node tools/portrait-pilot/run-internal-subject-rescue-v1.js --manifest <manifest.json> --codex-exe <绝对路径>",
    "  --output <path>       默认写入候选包/internal-subject-model-report.json；禁止覆盖",
    "  --timeout-ms <ms>     每个独立 Luna 进程上限；默认 600000",
    "  --max-concurrency <n> 全局并发；默认 6，范围 1–12",
    "  --service-tier <tier> fast（默认）或 standard",
    "  --check               只校验候选包与控制器闭包，不调用模型",
  ].join("\n");
}

function resolveInsideRepo(relativePath, label) {
  if (typeof relativePath !== "string" || !relativePath) fail("ARTIFACT_PATH_INVALID", "preflight", `${label} 路径无效`);
  const absolute = path.resolve(ROOT, relativePath);
  const relative = path.relative(ROOT, absolute);
  if (relative.startsWith("..") || path.isAbsolute(relative)) fail("ARTIFACT_PATH_ESCAPE", "preflight", `${label} 越出仓库`);
  return absolute;
}

function verifyArtifact(record, label) {
  if (!record || typeof record.path !== "string" || typeof record.sha256 !== "string" || !Number.isInteger(record.bytes)) {
    fail("ARTIFACT_RECORD_INVALID", "preflight", `${label} artifact 记录不闭合`);
  }
  const absolute = requireAbsoluteFile(resolveInsideRepo(record.path, label), label);
  const stat = fs.statSync(absolute);
  if (stat.size !== record.bytes || sha256File(absolute) !== record.sha256) {
    fail("ARTIFACT_HASH_MISMATCH", "preflight", `${label} 字节闭包不匹配`, { path: record.path });
  }
  return absolute;
}

function loadManifest(manifestArgument) {
  if (!manifestArgument) fail("ARGUMENT_REQUIRED", "arguments", "必须提供 --manifest");
  const manifestPath = requireAbsoluteFile(path.resolve(ROOT, manifestArgument), "internal subject rescue manifest");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (
    manifest.schema !== INPUT_SCHEMA ||
    manifest.phase !== "P4_INTERNAL_SUBJECT_RESCUE" ||
    manifest.status !== "internal_subject_candidates_ready" ||
    manifest.productionReady !== false ||
    manifest.humanReviewRequired !== true
  ) {
    fail("MANIFEST_SCHEMA_INVALID", "preflight", "内部主体候选 manifest 状态或 schema 不受支持");
  }
  const digestEnvelope = { ...manifest };
  delete digestEnvelope.manifestDigest;
  if (sha256Bytes(pythonStableStringify(digestEnvelope)) !== manifest.manifestDigest) {
    fail("MANIFEST_DIGEST_MISMATCH", "preflight", "manifestDigest 不匹配");
  }
  if (sha256Bytes(pythonStableStringify(manifest.inputs)) !== manifest.sourceDigest) {
    fail("SOURCE_DIGEST_MISMATCH", "preflight", "sourceDigest 不匹配");
  }
  const gates = manifest.gates || {};
  if (
    gates.allRootsLackNamedMan !== true ||
    gates.complexitySelectsProductionSubject !== false ||
    gates.rootFallbackRendered !== false ||
    gates.vectorExportDeferredUntilHumanSubjectSelection !== true ||
    gates.humanArtAcceptance !== false ||
    gates.productionWrites !== false
  ) {
    fail("MANIFEST_GATE_INVALID", "preflight", "缺失 man 补救包的安全门不闭合");
  }
  if (
    manifest.rankingContract?.complexityUse !== "candidate_recall_prior_only" ||
    manifest.rankingContract?.multimodalSubjectDecisionRequired !== true ||
    manifest.rankingContract?.humanFinalDecisionRequired !== true
  ) {
    fail("RANKING_CONTRACT_INVALID", "preflight", "复杂度必须仅用于召回且需要多模态与人工裁决");
  }
  verifyArtifact(manifest.contactSheet, "complete contact sheet");
  if (!Array.isArray(manifest.reviewItems) || manifest.reviewItems.length < 1) {
    fail("MANIFEST_REVIEW_INVALID", "preflight", "候选包没有审核项");
  }
  const itemByKey = new Map();
  let candidateCount = 0;
  for (const item of manifest.reviewItems) {
    if (!item?.reviewKey || itemByKey.has(item.reviewKey) || !Array.isArray(item.candidates) || item.candidates.length < 1) {
      fail("MANIFEST_REVIEW_INVALID", "preflight", "审核键重复或候选为空", { reviewKey: item?.reviewKey });
    }
    const candidateIds = new Set();
    for (const candidate of item.candidates) {
      if (!candidate?.candidateId || candidateIds.has(candidate.candidateId)) {
        fail("MANIFEST_CANDIDATE_INVALID", "preflight", "候选 ID 缺失或重复", { reviewKey: item.reviewKey });
      }
      if (!["high", "medium", "low"].includes(candidate.complexityTier)) {
        fail("MANIFEST_CANDIDATE_INVALID", "preflight", "候选复杂度层无效", { candidateId: candidate.candidateId });
      }
      if (candidate.hardUiExcluded !== false || candidate.definitionType !== "DefineSpriteTag") {
        fail("MANIFEST_CANDIDATE_INVALID", "preflight", "候选不是安全的内部影片剪辑", { candidateId: candidate.candidateId });
      }
      verifyArtifact(candidate.artifact, `candidate ${candidate.candidateId}`);
      candidateIds.add(candidate.candidateId);
      candidateCount += 1;
    }
    itemByKey.set(item.reviewKey, item);
  }
  if (
    manifest.counts?.targetIdentityCount !== manifest.reviewItems.length ||
    manifest.counts?.candidateCount !== candidateCount ||
    manifest.counts?.modelBatchCount !== manifest.modelBatches?.length ||
    manifest.counts?.expectedIndependentModelJobs !== manifest.modelBatches.length * ROLES.length
  ) {
    fail("MANIFEST_COUNT_INVALID", "preflight", "manifest counts 不闭合");
  }
  const batched = new Set();
  const modelBatches = manifest.modelBatches.map((batch) => {
    if (!batch?.modelBatchId || !Array.isArray(batch.reviewKeys) || batch.reviewKeys.length < 1 || batch.reviewKeys.length > 4) {
      fail("MANIFEST_BATCH_INVALID", "preflight", "模型批次必须含 1–4 个审核项");
    }
    const reviewItems = batch.reviewKeys.map((reviewKey) => {
      const item = itemByKey.get(reviewKey);
      if (!item || batched.has(reviewKey)) fail("MANIFEST_BATCH_INVALID", "preflight", "模型批次含未知或重复审核键", { reviewKey });
      batched.add(reviewKey);
      return item;
    });
    return {
      modelBatchId: batch.modelBatchId,
      contactSheet: batch.contactSheet,
      contactSheetPath: verifyArtifact(batch.contactSheet, `model batch ${batch.modelBatchId}`),
      reviewItems,
    };
  });
  if (batched.size !== manifest.reviewItems.length) fail("MANIFEST_BATCH_INVALID", "preflight", "模型批次未覆盖全部审核项");
  requireAbsoluteFile(OUTPUT_SCHEMA_PATH, "internal subject rescue output schema");
  return { manifest, manifestPath, modelBatches, candidateCount };
}

function createPrompt(manifest, batch, runRole) {
  const canonicalInput = {
    batchId: manifest.batchId,
    modelBatchId: batch.modelBatchId,
    sourceDigest: manifest.sourceDigest,
    contactSheetSha256: batch.contactSheet.sha256,
    complexityContract: "recall_prior_only_never_a_selection_rule",
    rows: batch.reviewItems.map((item) => ({
      reviewCode: item.reviewCode,
      reviewKey: item.reviewKey,
      portraitRef: item.portraitRef,
      sourceSwf: item.sourceSwf,
      candidates: item.candidates.map((candidate, index) => ({
        contactSheetLabel: `C${String(index + 1).padStart(2, "0")}`,
        candidateId: candidate.candidateId,
        spriteId: candidate.spriteId,
        frame: candidate.frame,
        width: candidate.width,
        height: candidate.height,
        complexityTier: candidate.complexityTier,
        complexityRank: candidate.complexityRank,
        initialRootFrameCandidate: candidate.initialRootFrameCandidate,
        softEffectHint: candidate.softEffectHint,
      })),
    })),
  };
  const body = [
    "You are reviewing internal Flash movie clips that were recalled because the root monster symbol has no consistently named man instance.",
    "Do not use tools, modify files, infer acceptance, or propose production writes. Inspect only the attached current-candidate contact sheet.",
    `Independent run role: ${runRole}.`,
    runRole === "independent_review"
      ? "Recompute independently. No proposal answer is supplied or trusted."
      : "Produce the first independent proposal.",
    "For every row, visually compare every C candidate, including high, medium, and low complexity tiers. Complexity is only a recall prior; never choose a candidate because its rank or tier is higher.",
    "Select the DefineSprite that depicts the coherent recognizable unit/monster itself. A valid subject can be humanoid, creature, vehicle, elemental, or abstract game unit, but it must contain enough connected anatomy or silhouette to act as the raw character layer for later portrait framing.",
    "Reject isolated weapons, muzzle flashes, particles, shadows, hit areas, rectangles, text, HP/level UI, and effect-only clips. A candidate with effects is acceptable only when the coherent unit itself remains the dominant connected subject and uiContamination/effectOnly/weaponOnly are all false.",
    "completeUnit means a coherent character/unit movie clip rather than a detached component; it does not require every limb to be visible in the sampled frame.",
    "When selected, identityFeatures must list 1–5 concrete visible landmarks from that candidate. Do not repeat the unit name as a feature.",
    "Use decision=none only when none of the listed candidates is a defensible coherent subject. Then candidateId must be null, completeUnit false, and identityFeatures empty.",
    "Return every reviewKey exactly once and only the JSON required by the output schema.",
    `Canonical controller input: ${stableStringify(canonicalInput)}`,
  ].join("\n");
  const promptDigest = sha256Bytes(body);
  const prompt = [
    body,
    "Echo these controller-owned closure fields exactly:",
    `schema=${RESULT_SCHEMA}`,
    `batchId=${manifest.batchId}`,
    `sourceDigest=${manifest.sourceDigest}`,
    `promptDigest=${promptDigest}`,
    `runRole=${runRole}`,
  ].join("\n");
  return { canonicalInput, promptDigest, transmittedPromptSha256: sha256Bytes(prompt), prompt };
}

function finiteUnitInterval(value, field, reviewKey) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 1) {
    fail("RESULT_VALUE_INVALID", "closure", `${field} 必须是 0..1`, { reviewKey, value });
  }
}

function validateResult(value, expected) {
  exactKeys(value, ["schema", "batchId", "sourceDigest", "promptDigest", "runRole", "selections"], "result");
  for (const [field, target] of [
    ["schema", RESULT_SCHEMA],
    ["batchId", expected.manifest.batchId],
    ["sourceDigest", expected.manifest.sourceDigest],
    ["promptDigest", expected.promptDigest],
    ["runRole", expected.runRole],
  ]) {
    if (value[field] !== target) fail("RESULT_CLOSURE_MISMATCH", "closure", `${field} 与 controller 不一致`, { field });
  }
  if (!Array.isArray(value.selections) || value.selections.length !== expected.reviewItems.length) {
    fail("RESULT_COUNT_INVALID", "closure", "selections 数量不闭合");
  }
  const itemByKey = new Map(expected.reviewItems.map((item) => [item.reviewKey, item]));
  const seen = new Set();
  for (const selection of value.selections) {
    exactKeys(selection, [
      "reviewKey",
      "decision",
      "candidateId",
      "subjectLikeness",
      "completeUnit",
      "uiContamination",
      "effectOnly",
      "weaponOnly",
      "identityFeatures",
      "confidence",
      "reason",
    ], "selection");
    const item = itemByKey.get(selection.reviewKey);
    if (!item || seen.has(selection.reviewKey)) {
      fail("RESULT_REVIEW_KEY_INVALID", "closure", "reviewKey 未知或重复", { reviewKey: selection.reviewKey });
    }
    seen.add(selection.reviewKey);
    if (!["select", "none"].includes(selection.decision)) {
      fail("RESULT_VALUE_INVALID", "closure", "decision 非法", { reviewKey: selection.reviewKey });
    }
    finiteUnitInterval(selection.subjectLikeness, "subjectLikeness", selection.reviewKey);
    finiteUnitInterval(selection.confidence, "confidence", selection.reviewKey);
    for (const field of ["completeUnit", "uiContamination", "effectOnly", "weaponOnly"]) {
      if (typeof selection[field] !== "boolean") fail("RESULT_VALUE_INVALID", "closure", `${field} 必须是布尔值`, { reviewKey: selection.reviewKey });
    }
    if (typeof selection.reason !== "string" || !selection.reason.trim() || selection.reason.length > 240) {
      fail("RESULT_VALUE_INVALID", "closure", "reason 必须是 1–240 字符", { reviewKey: selection.reviewKey });
    }
    if (
      !Array.isArray(selection.identityFeatures) ||
      selection.identityFeatures.length > 5 ||
      selection.identityFeatures.some((feature) => typeof feature !== "string" || !feature.trim() || feature.length > 80) ||
      new Set(selection.identityFeatures.map((feature) => feature.trim().toLocaleLowerCase("zh-CN"))).size !== selection.identityFeatures.length
    ) {
      fail("RESULT_VALUE_INVALID", "closure", "identityFeatures 非法", { reviewKey: selection.reviewKey });
    }
    if (selection.decision === "none") {
      if (selection.candidateId !== null || selection.completeUnit !== false || selection.identityFeatures.length !== 0) {
        fail("RESULT_NONE_INVALID", "closure", "none 必须使用 null candidateId、completeUnit=false、空特征", { reviewKey: selection.reviewKey });
      }
    } else {
      const candidate = item.candidates.find((entry) => entry.candidateId === selection.candidateId);
      if (!candidate) fail("RESULT_CANDIDATE_INVALID", "closure", "candidateId 不在当前行白名单", { reviewKey: selection.reviewKey, candidateId: selection.candidateId });
      if (
        selection.completeUnit !== true ||
        selection.uiContamination ||
        selection.effectOnly ||
        selection.weaponOnly ||
        selection.subjectLikeness < 0.55 ||
        selection.confidence < 0.5 ||
        selection.identityFeatures.length < 1
      ) {
        fail("RESULT_SELECTION_UNSAFE", "closure", "select 未通过主体完整性与最低置信门", {
          reviewKey: selection.reviewKey,
          candidateId: selection.candidateId,
        });
      }
    }
  }
  if (seen.size !== itemByKey.size) fail("RESULT_COUNT_INVALID", "closure", "reviewKey 未闭合");
  return {
    ...value,
    selections: [...value.selections].sort((left, right) => left.reviewKey.localeCompare(right.reviewKey, "zh-CN")),
  };
}

function classifyExit(capture) {
  const text = `${capture.stderr}\n${capture.stdout}`;
  if (/unauthorized|authentication|login required|status[=: ]+401/iu.test(text)) return "AUTHENTICATION_FAILED";
  if (/model.{0,80}(not available|not supported|not found|unsupported|invalid)/iu.test(text)) return "MODEL_UNAVAILABLE";
  if (/invalid_json_schema|Invalid schema for response_format/iu.test(text)) return "OUTPUT_SCHEMA_REJECTED";
  return "PROCESS_EXIT_NONZERO";
}

async function runAttempt(worker, options, role, attemptNumber) {
  const prompt = createPrompt(options.manifest, options.batch, role);
  const args = [
    "exec",
    "--ephemeral",
    "--ignore-user-config",
    "--ignore-rules",
    "--model",
    MODEL,
    "--config",
    `model_reasoning_effort=${JSON.stringify(EFFORT)}`,
    "--config",
    'approval_policy="never"',
    ...(options.serviceTier === "fast"
      ? ["--config", 'service_tier="fast"', "--config", "features.fast_mode=true"]
      : []),
    "--sandbox",
    "read-only",
    "--cd",
    options.isolatedCwd,
    "--skip-git-repo-check",
    "--image",
    options.batch.contactSheetPath,
    "--output-schema",
    OUTPUT_SCHEMA_PATH,
    "--json",
    "-",
  ];
  const capture = await spawnCaptured({
    command: worker.executablePath,
    args: worker.commandArgs(args),
    cwd: options.isolatedCwd,
    env: worker.environment,
    stdin: prompt.prompt,
    timeoutMs: options.timeoutMs,
  });
  const evidence = {
    attemptNumber,
    pid: capture.pid,
    startedAt: capture.startedAt,
    endedAt: capture.endedAt,
    durationMs: capture.durationMs,
    exitCode: capture.exitCode,
    signal: capture.signal,
    timedOut: capture.timedOut,
    terminationReason: capture.terminationReason,
    observedDescendantPids: capture.knownDescendantPids,
    normalExitOrphanPids: capture.normalExitOrphanPids,
    terminatedTreePids: capture.termination.targetPids,
    survivorPids: capture.termination.survivorPids,
    modelRequested: MODEL,
    reasoningEffort: EFFORT,
    serviceTier: options.serviceTier,
    modelBatchId: options.batch.modelBatchId,
    sourceDigest: options.manifest.sourceDigest,
    contactSheetPath: path.relative(ROOT, options.batch.contactSheetPath).replaceAll("\\", "/"),
    contactSheetSha256: sha256File(options.batch.contactSheetPath),
    promptDigest: prompt.promptDigest,
    transmittedPromptSha256: prompt.transmittedPromptSha256,
    outputSchemaSha256: sha256File(OUTPUT_SCHEMA_PATH),
    stdoutSha256: sha256Bytes(capture.stdout),
    stderrSha256: sha256Bytes(capture.stderr),
    stdoutBytes: capture.stdoutBytes,
    stderrBytes: capture.stderrBytes,
  };
  const attach = (error) => {
    error.details = { ...error.details, attempt: { evidence, stdout: capture.stdout, stderr: capture.stderr } };
    throw error;
  };
  try {
    if (capture.spawnError) fail("PROCESS_SPAWN_FAILED", "transport", capture.spawnError.message);
    if (capture.timedOut) fail("PROCESS_TIMEOUT", "transport", "Luna 主体判断进程超时");
    if (capture.overflowStream) fail("CAPTURE_OVERFLOW", "transport", "Luna 输出超过有界缓冲");
    if (capture.termination.survivorPids.length > 0) fail("ORPHAN_PROCESS_SURVIVED", "transport", "终止后仍有存活 PID");
    if (capture.normalExitOrphanPids.length > 0) fail("ORPHAN_PROCESS_OBSERVED", "transport", "正常退出后留下子进程");
    if (capture.exitCode !== 0) fail(classifyExit(capture), "transport", "Luna CLI 非零退出", { exitCode: capture.exitCode });
    const finalMessage = extractFinalAgentMessage(parseJsonl(capture.stdout));
    let parsed;
    try {
      parsed = JSON.parse(finalMessage.text);
    } catch (error) {
      fail("RESULT_JSON_INVALID", "closure", "最终 agent_message 不是 JSON", { cause: error.message });
    }
    const result = validateResult(parsed, {
      manifest: options.manifest,
      reviewItems: options.batch.reviewItems,
      promptDigest: prompt.promptDigest,
      runRole: role,
    });
    evidence.threadId = finalMessage.threadId;
    evidence.agentMessageCount = finalMessage.agentMessageCount;
    evidence.recoverableDiagnostics = finalMessage.recoverableDiagnostics;
    evidence.recoverableDiagnosticDigest = sha256Bytes(stableStringify(finalMessage.recoverableDiagnostics));
    evidence.resultSha256 = sha256Bytes(stableStringify(result));
    evidence.status = "accepted";
    return { evidence, result, stdout: capture.stdout, stderr: capture.stderr };
  } catch (error) {
    if (error instanceof WorkerError) attach(error);
    attach(new WorkerError("UNEXPECTED_ATTEMPT_ERROR", "internal", error.message));
  }
}

const RETRIABLE = new Set([
  "PROCESS_TIMEOUT",
  "PROCESS_EXIT_NONZERO",
  "STDOUT_JSONL_INVALID",
  "TURN_FAILED",
  "TERMINAL_ERROR_EVENT",
  "TURN_COMPLETION_INVALID",
  "AGENT_MESSAGE_MISSING",
  "RESULT_JSON_INVALID",
  "RESULT_SCHEMA_INVALID",
  "RESULT_CLOSURE_MISMATCH",
  "RESULT_COUNT_INVALID",
  "RESULT_REVIEW_KEY_INVALID",
  "RESULT_CANDIDATE_INVALID",
  "RESULT_VALUE_INVALID",
  "RESULT_NONE_INVALID",
  "RESULT_SELECTION_UNSAFE",
]);

function writeExclusive(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content, { encoding: "utf8", flag: "wx" });
}

async function runRole(worker, options, role, artifactsDirectory) {
  const attempts = [];
  const seenPids = new Set();
  const maximumAttempts = 2;
  for (let attemptNumber = 1; attemptNumber <= maximumAttempts; attemptNumber += 1) {
    try {
      const accepted = await runAttempt(worker, options, role, attemptNumber);
      if (seenPids.has(accepted.evidence.pid)) fail("PROCESS_ID_REUSED", "transport", "重试没有新 PID");
      const base = `${role}-${options.batch.modelBatchId}-attempt-${attemptNumber}`;
      writeExclusive(path.join(artifactsDirectory, `${base}.stdout.jsonl`), accepted.stdout);
      writeExclusive(path.join(artifactsDirectory, `${base}.stderr.log`), accepted.stderr);
      accepted.evidence.stdoutArtifact = `model-artifacts/${base}.stdout.jsonl`;
      accepted.evidence.stderrArtifact = `model-artifacts/${base}.stderr.log`;
      attempts.push(accepted.evidence);
      return {
        modelBatchId: options.batch.modelBatchId,
        role,
        status: "accepted",
        attempts,
        acceptedAttempt: attemptNumber,
        result: accepted.result,
      };
    } catch (error) {
      const normalized = publicError(error);
      const attempt = error instanceof WorkerError ? error.details.attempt : null;
      if (attempt) {
        if (seenPids.has(attempt.evidence.pid)) fail("PROCESS_ID_REUSED", "transport", "重试没有新 PID");
        seenPids.add(attempt.evidence.pid);
        const base = `${role}-${options.batch.modelBatchId}-attempt-${attemptNumber}`;
        writeExclusive(path.join(artifactsDirectory, `${base}.stdout.jsonl`), attempt.stdout);
        writeExclusive(path.join(artifactsDirectory, `${base}.stderr.log`), attempt.stderr);
        attempts.push({
          ...attempt.evidence,
          status: "rejected",
          stdoutArtifact: `model-artifacts/${base}.stdout.jsonl`,
          stderrArtifact: `model-artifacts/${base}.stderr.log`,
          error: { code: normalized.code, phase: normalized.phase, message: normalized.message },
        });
      }
      if (attemptNumber === maximumAttempts || !RETRIABLE.has(normalized.code)) {
        fail("RUN_RETRIES_EXHAUSTED", normalized.phase, normalized.message, {
          role,
          modelBatchId: options.batch.modelBatchId,
          attempts,
          terminalError: normalized,
        });
      }
    }
  }
  fail("RUN_RETRIES_EXHAUSTED", "internal", "不可达的重试终态");
}

async function settleWithConcurrency(jobs, maximumConcurrency) {
  const results = new Array(jobs.length);
  let nextIndex = 0;
  async function consume() {
    while (true) {
      const index = nextIndex;
      nextIndex += 1;
      if (index >= jobs.length) return;
      try {
        results[index] = { status: "fulfilled", value: await jobs[index]() };
      } catch (reason) {
        results[index] = { status: "rejected", reason };
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(maximumConcurrency, jobs.length) }, () => consume()));
  return results;
}

function artifactInventory(directory) {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => {
      const filePath = path.join(directory, entry.name);
      return {
        path: path.relative(ROOT, filePath).replaceAll("\\", "/"),
        bytes: fs.statSync(filePath).size,
        sha256: sha256File(filePath),
      };
    })
    .sort((left, right) => left.path.localeCompare(right.path));
}

function controllerEvidence() {
  const files = [__filename, OUTPUT_SCHEMA_PATH, WORKER_PATH].map((filePath) => ({
    path: path.relative(ROOT, filePath).replaceAll("\\", "/"),
    bytes: fs.statSync(filePath).size,
    sha256: sha256File(filePath),
  }));
  return {
    version: "internal-subject-rescue-luna-ab-v1",
    nodeVersion: process.version,
    platform: process.platform,
    arch: process.arch,
    files,
    sourceClosureDigest: sha256Bytes(stableStringify(files)),
  };
}

function mergeRole(role, runs, loaded) {
  const selections = runs.flatMap((run) => run.result.selections);
  const keys = new Set(selections.map((selection) => selection.reviewKey));
  if (selections.length !== loaded.manifest.reviewItems.length || keys.size !== selections.length) {
    fail("MERGED_RESULT_INVALID", "closure", "角色合并后审核键不闭合", { role });
  }
  return {
    role,
    status: "accepted",
    batches: runs,
    selections: [...selections].sort((left, right) => left.reviewKey.localeCompare(right.reviewKey, "zh-CN")),
  };
}

function compareRoles(proposal, independentReview) {
  const rightByKey = new Map(independentReview.selections.map((row) => [row.reviewKey, row]));
  return proposal.selections.map((left) => {
    const right = rightByKey.get(left.reviewKey);
    const decisionAgreement = left.decision === right.decision;
    const candidateAgreement = decisionAgreement && left.candidateId === right.candidateId;
    const minimumConfidence = Math.min(left.confidence, right.confidence);
    const minimumSubjectLikeness = Math.min(left.subjectLikeness, right.subjectLikeness);
    const highlightedForHuman =
      !candidateAgreement ||
      left.decision === "none" ||
      minimumConfidence < 0.75 ||
      minimumSubjectLikeness < 0.7;
    return {
      reviewKey: left.reviewKey,
      decisionAgreement,
      candidateAgreement,
      minimumConfidence: Number(minimumConfidence.toFixed(6)),
      minimumSubjectLikeness: Number(minimumSubjectLikeness.toFixed(6)),
      highlightedForHuman,
    };
  });
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  const loaded = loadManifest(options.manifest);
  if (options.check) {
    process.stdout.write(`${JSON.stringify({
      status: "internal_subject_rescue_preflight_verified",
      batchId: loaded.manifest.batchId,
      manifestDigest: loaded.manifest.manifestDigest,
      identities: loaded.manifest.reviewItems.length,
      candidates: loaded.candidateCount,
      modelBatches: loaded.modelBatches.length,
      expectedIndependentRuns: loaded.modelBatches.length * ROLES.length,
    })}\n`);
    return;
  }
  if (!options.codexExe) fail("ARGUMENT_REQUIRED", "arguments", "模型运行必须显式提供 --codex-exe");
  const outputRoot = path.dirname(loaded.manifestPath);
  const outputPath = path.resolve(ROOT, options.output || path.join(outputRoot, "internal-subject-model-report.json"));
  const relativeOutput = path.relative(outputRoot, outputPath);
  if (relativeOutput.startsWith("..") || path.isAbsolute(relativeOutput)) {
    fail("OUTPUT_PATH_INVALID", "output", "模型报告必须位于当前候选包目录");
  }
  if (fs.existsSync(outputPath)) fail("OUTPUT_EXISTS", "output", "模型报告已存在，拒绝覆盖");
  const artifactsDirectory = path.join(outputRoot, "model-artifacts");
  const isolatedCwd = path.join(outputRoot, "model-isolated-cwd");
  if (fs.existsSync(artifactsDirectory)) fail("OUTPUT_EXISTS", "output", "model-artifacts 已存在，拒绝覆盖");
  fs.mkdirSync(artifactsDirectory);
  fs.mkdirSync(isolatedCwd, { recursive: true });

  const worker = new CodexCliLunaWorker({
    executablePath: path.resolve(options.codexExe),
    model: MODEL,
    reasoningEffort: EFFORT,
  });
  const probe = await worker.probe(Math.min(options.timeoutMs, 30_000));
  const jobs = loaded.modelBatches.flatMap((batch) => ROLES.map((role) => ({
    batch,
    role,
    run: () => runRole(worker, {
      manifest: loaded.manifest,
      batch,
      isolatedCwd,
      timeoutMs: options.timeoutMs,
      serviceTier: options.serviceTier,
    }, role, artifactsDirectory),
  })));
  const settled = await settleWithConcurrency(jobs.map((job) => job.run), options.maxConcurrency);
  const failedIndex = settled.findIndex((entry) => entry.status === "rejected");
  if (failedIndex >= 0) {
    const failure = {
      schema: FAILURE_SCHEMA,
      status: "model_run_failed",
      productionReady: false,
      humanReviewRequired: false,
      generatedAt: new Date().toISOString(),
      batchId: loaded.manifest.batchId,
      sourceDigest: loaded.manifest.sourceDigest,
      manifestDigest: loaded.manifest.manifestDigest,
      controller: controllerEvidence(),
      probe,
      scheduling: {
        maxConcurrency: options.maxConcurrency,
        serviceTier: options.serviceTier,
        timeoutMs: options.timeoutMs,
        expectedIndependentRuns: jobs.length,
      },
      completedRuns: settled.flatMap((entry, index) => entry.status === "fulfilled"
        ? [{ role: jobs[index].role, run: entry.value }]
        : []),
      failedRun: {
        modelBatchId: jobs[failedIndex].batch.modelBatchId,
        role: jobs[failedIndex].role,
        error: publicError(settled[failedIndex].reason),
      },
      modelArtifacts: artifactInventory(artifactsDirectory),
      gates: {
        failurePersisted: true,
        partialSuccessNotPromoted: true,
        humanReviewOpened: false,
        productionWrites: false,
      },
    };
    failure.reportDigest = sha256Bytes(stableStringify(failure));
    writeExclusive(path.join(outputRoot, "internal-subject-model-failure.json"), `${JSON.stringify(failure, null, 2)}\n`);
    throw settled[failedIndex].reason;
  }

  const acceptedAttempts = settled.map((entry) => {
    const run = entry.value;
    return run.attempts.find((attempt) => attempt.attemptNumber === run.acceptedAttempt);
  });
  const acceptedPids = acceptedAttempts.map((attempt) => attempt?.pid);
  if (acceptedPids.some((pid) => !Number.isInteger(pid)) || new Set(acceptedPids).size !== acceptedPids.length) {
    fail("RUN_INDEPENDENCE_FAILED", "closure", "所有 A/B 小批次必须使用不同 PID");
  }
  for (const batch of loaded.modelBatches) {
    const pair = settled
      .map((entry) => entry.value)
      .filter((run) => run.modelBatchId === batch.modelBatchId)
      .map((run) => run.attempts.find((attempt) => attempt.attemptNumber === run.acceptedAttempt));
    if (pair.length !== 2 || pair[0].promptDigest === pair[1].promptDigest) {
      fail("RUN_INDEPENDENCE_FAILED", "closure", "同批 A/B 必须有不同角色 prompt digest");
    }
  }

  const byRole = Object.fromEntries(ROLES.map((role) => [
    role,
    settled.map((entry) => entry.value).filter((run) => run.role === role),
  ]));
  const proposal = mergeRole("proposal", byRole.proposal, loaded);
  const independentReview = mergeRole("independent_review", byRole.independent_review, loaded);
  const comparisons = compareRoles(proposal, independentReview);
  const report = {
    schema: REPORT_SCHEMA,
    status: "subject_candidates_proposed",
    productionReady: false,
    humanReviewRequired: true,
    generatedAt: new Date().toISOString(),
    batchId: loaded.manifest.batchId,
    sourceDigest: loaded.manifest.sourceDigest,
    manifestDigest: loaded.manifest.manifestDigest,
    controller: controllerEvidence(),
    probe,
    input: {
      manifest: {
        path: path.relative(ROOT, loaded.manifestPath).replaceAll("\\", "/"),
        bytes: fs.statSync(loaded.manifestPath).size,
        sha256: sha256File(loaded.manifestPath),
      },
      outputSchema: {
        path: path.relative(ROOT, OUTPUT_SCHEMA_PATH).replaceAll("\\", "/"),
        bytes: fs.statSync(OUTPUT_SCHEMA_PATH).size,
        sha256: sha256File(OUTPUT_SCHEMA_PATH),
      },
      identityCount: loaded.manifest.reviewItems.length,
      candidateCount: loaded.candidateCount,
      modelBatches: loaded.manifest.modelBatches,
      scheduling: {
        maxConcurrency: options.maxConcurrency,
        serviceTier: options.serviceTier,
        timeoutMs: options.timeoutMs,
        independentRunCount: jobs.length,
      },
    },
    runs: [proposal, independentReview],
    comparisons,
    counts: {
      identityCount: comparisons.length,
      decisionAgreement: comparisons.filter((row) => row.decisionAgreement).length,
      candidateAgreement: comparisons.filter((row) => row.candidateAgreement).length,
      highlightedForHuman: comparisons.filter((row) => row.highlightedForHuman).length,
      proposalNone: proposal.selections.filter((row) => row.decision === "none").length,
      independentReviewNone: independentReview.selections.filter((row) => row.decision === "none").length,
    },
    modelArtifacts: artifactInventory(artifactsDirectory),
    gates: {
      complexityUsedForRecallOnly: true,
      allCandidatesComparedByMultimodalModel: true,
      candidateWhitelistClosed: true,
      exactControllerClosure: true,
      separateProcessIds: true,
      distinctRolePromptDigests: true,
      boundedGlobalConcurrency: true,
      humanArtAcceptance: false,
      automaticPromotion: false,
      vectorExportDeferred: true,
      productionWrites: false,
    },
  };
  report.reportDigest = sha256Bytes(stableStringify(report));
  writeExclusive(outputPath, `${JSON.stringify(report, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify({
    status: report.status,
    reportPath: outputPath,
    reportDigest: report.reportDigest,
    counts: report.counts,
  })}\n`);
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${JSON.stringify(publicError(error))}\n`);
    process.exitCode = 1;
  });
}

module.exports = { compareRoles, createPrompt, loadManifest, parseArgs, pythonStableStringify, validateResult };
