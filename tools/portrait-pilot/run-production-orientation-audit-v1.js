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
  sha256Bytes,
  sha256File,
  spawnCaptured,
  stableStringify,
} = require("../portrait-worker/lib/codex-cli-luna-worker");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const WEB_ROOT = path.join(ROOT, "launcher", "web");
const DEFAULT_MANIFEST = path.join(WEB_ROOT, "assets", "enemy-portraits", "manifest.json");
const OUTPUT_SCHEMA = path.join(__dirname, "schemas", "portrait-orientation-audit-v1.schema.json");
const WORKER_SOURCE = path.join(ROOT, "tools", "portrait-worker", "lib", "codex-cli-luna-worker.js");
const AUDIT_MANIFEST_NAME = "orientation-visual-audit-manifest.json";
const MODEL_REPORT_NAME = "orientation-visual-model-report.json";
const MODEL = "gpt-5.6-luna";
const EFFORT = "max";
const ASSESSMENT_SCHEMA = "cf7.portrait-orientation-visual-assessment.v1";

function fail(code, phase, message, details = {}) {
  throw new WorkerError(code, phase, message, details);
}

function parseArgs(argv) {
  const command = argv[0];
  const options = {
    command,
    manifest: DEFAULT_MANIFEST,
    output: null,
    batchId: null,
    itemsPerBatch: 8,
    codexExe: process.env.CF7_PORTRAIT_CODEX_EXE || null,
    maxConcurrency: 6,
    timeoutMs: 600_000,
    serviceTier: "fast",
    supersessionReceipt: null,
  };
  for (let index = 1; index < argv.length; index += 1) {
    const argument = argv[index];
    const valued = new Set([
      "--manifest", "--output", "--batch-id", "--items-per-batch", "--codex-exe",
      "--max-concurrency", "--timeout-ms", "--service-tier", "--supersession-receipt",
    ]);
    if (valued.has(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) fail("ARGUMENT_MISSING", "arguments", `${argument} 缺少值`);
      index += 1;
      if (argument === "--manifest") options.manifest = value;
      if (argument === "--output") options.output = value;
      if (argument === "--batch-id") options.batchId = value;
      if (argument === "--items-per-batch") options.itemsPerBatch = Number(value);
      if (argument === "--codex-exe") options.codexExe = value;
      if (argument === "--max-concurrency") options.maxConcurrency = Number(value);
      if (argument === "--timeout-ms") options.timeoutMs = Number(value);
      if (argument === "--service-tier") options.serviceTier = value;
      if (argument === "--supersession-receipt") options.supersessionReceipt = value;
    } else if (argument === "--help") {
      options.help = true;
    } else {
      fail("ARGUMENT_UNKNOWN", "arguments", `未知参数：${argument}`);
    }
  }
  if (!["build", "run", "check"].includes(command)) options.help = true;
  if (!Number.isInteger(options.itemsPerBatch) || options.itemsPerBatch < 1 || options.itemsPerBatch > 8) {
    fail("BATCH_SIZE_INVALID", "arguments", "items-per-batch 必须是 1–8 的整数");
  }
  if (!Number.isInteger(options.maxConcurrency) || options.maxConcurrency < 1 || options.maxConcurrency > 12) {
    fail("CONCURRENCY_INVALID", "arguments", "max-concurrency 必须是 1–12 的整数");
  }
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs < 30_000 || options.timeoutMs > 600_000) {
    fail("TIMEOUT_INVALID", "arguments", "timeout-ms 必须是 30000–600000 的整数");
  }
  if (!new Set(["standard", "fast"]).has(options.serviceTier)) {
    fail("SERVICE_TIER_INVALID", "arguments", "service-tier 必须是 standard 或 fast");
  }
  if (options.supersessionReceipt && command !== "check") {
    fail("ARGUMENT_INVALID", "arguments", "--supersession-receipt 仅允许用于 check");
  }
  return options;
}

function usage() {
  return [
    "用法：",
    "  node tools/portrait-pilot/run-production-orientation-audit-v1.js build --output <fresh tmp batch> --batch-id <id>",
    "  node tools/portrait-pilot/run-production-orientation-audit-v1.js run --output <built batch> --codex-exe <absolute path>",
    "  node tools/portrait-pilot/run-production-orientation-audit-v1.js check --output <completed batch> [--supersession-receipt <explicit frozen-artifact receipt>]",
  ].join("\n");
}

function readJson(filePath, label) {
  try {
    const value = JSON.parse(fs.readFileSync(filePath, "utf8"));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("顶层不是对象");
    return value;
  } catch (error) {
    fail("JSON_INVALID", "preflight", `${label}不可读：${filePath}: ${error.message}`);
  }
}

function ensureRepoFile(filePath, label) {
  const resolved = path.resolve(filePath);
  const relative = path.relative(ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative) || !fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    fail("ARTIFACT_INVALID", "preflight", `${label}越出仓库或缺失：${filePath}`);
  }
  return resolved;
}

function pilotOutput(value, label, allowExisting) {
  const resolved = path.resolve(ROOT, value);
  const relative = path.relative(PILOT_ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    fail("OUTPUT_PATH_INVALID", "output", `${label}必须位于 tmp/portrait-pilot 下`);
  }
  if (fs.existsSync(resolved) !== allowExisting) {
    fail("OUTPUT_STATE_INVALID", "output", allowExisting ? `${label}不存在：${resolved}` : `${label}已存在，禁止覆盖：${resolved}`);
  }
  return resolved;
}

function artifact(filePath) {
  const resolved = ensureRepoFile(filePath, "artifact");
  return {
    path: path.relative(ROOT, resolved).replaceAll("\\", "/"),
    bytes: fs.statSync(resolved).size,
    sha256: sha256File(resolved),
  };
}

function verifyArtifact(record, label) {
  if (!record || typeof record.path !== "string" || typeof record.bytes !== "number" || typeof record.sha256 !== "string") {
    fail("ARTIFACT_RECORD_INVALID", "preflight", `${label} artifact 记录不闭合`);
  }
  const resolved = ensureRepoFile(path.resolve(ROOT, record.path), label);
  if (fs.statSync(resolved).size !== record.bytes || sha256File(resolved) !== record.sha256) {
    fail("ARTIFACT_HASH_MISMATCH", "preflight", `${label}字节闭包漂移`, { path: record.path });
  }
  return resolved;
}

function artifactKey(record, label = "artifact") {
  if (!record || typeof record.path !== "string" || typeof record.bytes !== "number" || typeof record.sha256 !== "string") {
    fail("ARTIFACT_RECORD_INVALID", "preflight", `${label} artifact 记录不闭合`);
  }
  return `${record.path}\u0000${record.bytes}\u0000${record.sha256}`;
}

function sameArtifactBytes(left, right) {
  return left?.bytes === right?.bytes && left?.sha256 === right?.sha256;
}

function sameArtifactRecord(left, right) {
  return left?.path === right?.path && sameArtifactBytes(left, right);
}

function verifyArtifactOrSuperseded(record, label, mappings) {
  artifactKey(record, label);
  const resolved = path.resolve(ROOT, record.path);
  const relative = path.relative(ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    fail("PATH_OUTSIDE_REPO", "preflight", `${label}越过仓库边界`, { path: record.path });
  }
  if (
    fs.existsSync(resolved) &&
    fs.statSync(resolved).isFile() &&
    fs.statSync(resolved).size === record.bytes &&
    sha256File(resolved) === record.sha256
  ) return resolved;

  const entry = mappings?.get(artifactKey(record, label));
  if (!entry) fail("ARTIFACT_HASH_MISMATCH", "preflight", `${label}字节闭包漂移`, { path: record.path });
  const frozen = verifyArtifact(entry.frozen, `${label} frozen supersession`);
  if (!sameArtifactBytes(record, entry.frozen)) {
    fail("SUPERSESSION_BYTES_MISMATCH", "preflight", `${label}冻结副本并非原始字节`, { path: record.path });
  }
  return frozen;
}

function objectDigest(value, field) {
  const clone = { ...value };
  delete clone[field];
  return sha256Bytes(stableStringify(clone));
}

function loadSupersessionReceipt(receiptArgument, audit, auditPath) {
  if (!receiptArgument) return null;
  const receiptPath = ensureRepoFile(path.resolve(ROOT, receiptArgument), "supersession receipt");
  const receipt = readJson(receiptPath, "orientation audit supersession receipt");
  if (
    receipt.schema !== "cf7.portrait-orientation-artifact-supersession-receipt.v1" ||
    receipt.status !== "orientation_audit_artifacts_frozen" ||
    receipt.productionReady !== false ||
    objectDigest(receipt, "receiptDigest") !== receipt.receiptDigest ||
    receipt.sourceDigest !== audit.sourceDigest ||
    receipt.sourceAuditDigest !== audit.auditDigest ||
    receipt.gates?.originalBytesPreserved !== true ||
    receipt.gates?.supersessionIsExplicitOnly !== true ||
    receipt.gates?.productionWrites !== false
  ) fail("SUPERSESSION_RECEIPT_INVALID", "preflight", "orientation audit supersession receipt 未闭合");

  const frozenAuditPath = verifyArtifact(receipt.inputs?.auditManifest, "supersession source audit manifest");
  if (!sameArtifactRecord(receipt.inputs.auditManifest, artifact(auditPath)) || frozenAuditPath !== auditPath) {
    fail("SUPERSESSION_SOURCE_MISMATCH", "preflight", "supersession receipt 未绑定当前待验 r202 audit");
  }
  const reportPath = verifyArtifact(receipt.inputs?.modelReport, "supersession source model report");
  const report = readJson(reportPath, "supersession source model report");
  const humanReceiptPath = verifyArtifact(receipt.inputs?.humanReviewReceipt, "supersession human review receipt");
  const humanReceipt = readJson(humanReceiptPath, "supersession human review receipt");
  verifyArtifact(receipt.inputs?.controller, "supersession freeze controller");
  if (
    report.schema !== "cf7.production-portrait-orientation-visual-model-report.v1" ||
    objectDigest(report, "reportDigest") !== report.reportDigest ||
    report.reportDigest !== receipt.sourceModelReportDigest ||
    report.input?.auditDigest !== audit.auditDigest ||
    humanReceipt.schema !== "cf7.portrait-orientation-human-review-receipt.v1" ||
    objectDigest(humanReceipt, "receiptDigest") !== humanReceipt.receiptDigest ||
    humanReceipt.receiptDigest !== receipt.humanReviewReceiptDigest ||
    humanReceipt.modelReportDigest !== report.reportDigest ||
    humanReceipt.sourceDigest !== audit.sourceDigest
  ) fail("SUPERSESSION_SOURCE_MISMATCH", "preflight", "supersession receipt 的 r202/r204 源摘要未闭合");

  const requiredReferences = [
    audit.input?.productionManifest,
    ...(audit.input?.controller?.files || []),
    ...(report.controller?.files || []),
  ];
  const required = new Map(requiredReferences.map((record) => [artifactKey(record, "supersession required original"), record]));
  const mappings = new Map();
  for (const entry of receipt.entries || []) {
    const key = artifactKey(entry?.original, "supersession original");
    if (mappings.has(key)) fail("SUPERSESSION_RECEIPT_INVALID", "preflight", `重复 supersession mapping：${entry.original.path}`);
    verifyArtifact(entry.frozen, "supersession frozen artifact");
    if (!sameArtifactBytes(entry.original, entry.frozen)) {
      fail("SUPERSESSION_BYTES_MISMATCH", "preflight", `supersession 冻结字节不一致：${entry.original.path}`);
    }
    mappings.set(key, entry);
  }
  if (
    receipt.counts?.artifactReferences !== requiredReferences.length ||
    receipt.counts?.uniqueArtifacts !== required.size ||
    mappings.size !== required.size ||
    [...required.keys()].some((key) => !mappings.has(key)) ||
    [...mappings.keys()].some((key) => !required.has(key))
  ) fail("SUPERSESSION_RECEIPT_INVALID", "preflight", "supersession artifact 映射未精确覆盖 r202 引用");
  return { receipt, receiptPath, mappings, reportPath };
}

function exactKeys(value, keys, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("RESULT_SCHEMA_INVALID", "closure", `${label}必须是对象`);
  }
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (stableStringify(actual) !== stableStringify(expected)) {
    fail("RESULT_SCHEMA_INVALID", "closure", `${label}字段不闭合`, { actual, expected });
  }
}

function controllerEvidence() {
  const files = [__filename, OUTPUT_SCHEMA, WORKER_SOURCE].map(artifact);
  return {
    version: "production-orientation-audit-v1-final-pixel-independent-ab",
    nodeVersion: process.version,
    model: MODEL,
    reasoningEffort: EFFORT,
    files,
    sourceClosureDigest: sha256Bytes(stableStringify(files)),
  };
}

function validateProductionManifest(manifestPath) {
  const resolved = ensureRepoFile(manifestPath, "production portrait manifest");
  const manifest = readJson(resolved, "production portrait manifest");
  if (
    manifest.schema !== "cf7.enemy-portrait-manifest.v1" ||
    manifest.status !== "human_accepted_portraits_promoted" ||
    objectDigest(manifest, "manifestDigest") !== manifest.manifestDigest ||
    manifest.counts?.humanAcceptedVariantCount !== 217
  ) {
    fail("PRODUCTION_MANIFEST_INVALID", "preflight", "生产头像 manifest schema/status/digest/counts 未闭合");
  }
  return { manifest, manifestPath: resolved };
}

function collectAcceptedRows(manifest) {
  const rows = [];
  for (const [portraitRef, entry] of Object.entries(manifest.entries || {})) {
    for (const [variantKey, variant] of Object.entries(entry.variants || {})) {
      if (variant.status !== "human_accepted") continue;
      const reviewKey = `${portraitRef}::${variantKey}`;
      const png = variant.subject?.pngFallback;
      if (!png || typeof png.url !== "string" || typeof png.bytes !== "number" || typeof png.sha256 !== "string") {
        fail("ARTIFACT_RECORD_INVALID", "preflight", `production PNG ${reviewKey} 记录不闭合`);
      }
      const pngPath = ensureRepoFile(path.join(WEB_ROOT, png.url), `production PNG ${reviewKey}`);
      if (fs.statSync(pngPath).size !== png.bytes || sha256File(pngPath) !== png.sha256) {
        fail("ARTIFACT_HASH_MISMATCH", "preflight", `production PNG ${reviewKey} 字节闭包漂移`);
      }
      rows.push({
        reviewKey,
        portraitRef,
        variantKey,
        currentProductionOrientationAction: variant.provenance?.orientationAction,
        orientationSource: variant.provenance?.orientationSource,
        png: { ...png, path: path.relative(ROOT, pngPath).replaceAll("\\", "/") },
      });
    }
  }
  rows.sort((left, right) => left.reviewKey.localeCompare(right.reviewKey, "zh-CN"));
  if (rows.length !== 217 || new Set(rows.map((row) => row.reviewKey)).size !== 217) {
    fail("ACCEPTED_SET_INVALID", "preflight", `接受头像集合不闭合：${rows.length}`);
  }
  return rows.map((row, index) => ({
    reviewCode: `O${String(index + 1).padStart(3, "0")}`,
    ...row,
  }));
}

function buildAudit(options) {
  if (!options.output || !options.batchId || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(options.batchId)) {
    fail("ARGUMENT_REQUIRED", "arguments", "build 需要合法 --output 与 --batch-id");
  }
  const output = pilotOutput(options.output, "审计输出", false);
  const { manifest, manifestPath } = validateProductionManifest(path.resolve(ROOT, options.manifest));
  const rows = collectAcceptedRows(manifest);
  const batches = [];
  for (let index = 0; index < rows.length; index += options.itemsPerBatch) {
    const batchRows = rows.slice(index, index + options.itemsPerBatch);
    batches.push({
      modelBatchId: `${options.batchId}-b${String(batches.length + 1).padStart(2, "0")}`,
      rows: batchRows.map((row, attachmentIndex) => ({
        reviewCode: row.reviewCode,
        reviewKey: row.reviewKey,
        attachmentIndex: attachmentIndex + 1,
        png: row.png,
      })),
    });
  }
  const audit = {
    schema: "cf7.production-portrait-orientation-visual-audit-manifest.v1",
    status: "orientation_visual_audit_ready",
    productionReady: false,
    generatedAt: new Date().toISOString(),
    batchId: options.batchId,
    sourceDigest: manifest.manifestDigest,
    input: {
      productionManifest: artifact(manifestPath),
      productionManifestDigest: manifest.manifestDigest,
      controller: controllerEvidence(),
    },
    contract: {
      targetDirection: "viewer_right",
      flipRule: "flip only when the current final portrait's primary anatomical direction clearly points viewer-left",
      directionlessRule: "frontal, symmetric, or genuinely directionless subjects keep",
      weaponRule: "a detached or secondary weapon direction never overrides visible face, gaze, snout, sensory front, or body movement axis",
      assessmentScope: "final 512px transparent production PNG only; no prior direction labels are shown to Luna",
    },
    rows,
    batches,
    counts: {
      acceptedVariants: rows.length,
      modelBatches: batches.length,
      itemsPerBatchMaximum: options.itemsPerBatch,
      expectedIndependentRuns: batches.length * 2,
    },
    gates: {
      allAcceptedVariantsIncluded: rows.length === 217,
      finalProductionPixelsOnly: true,
      priorOrientationHiddenFromPrompt: true,
      independentABRequired: true,
      modelSuggestionsRequireHumanAcceptanceBeforeWrites: true,
      productionWrites: false,
    },
  };
  audit.auditDigest = objectDigest(audit, "auditDigest");
  fs.mkdirSync(output);
  fs.writeFileSync(path.join(output, AUDIT_MANIFEST_NAME), `${JSON.stringify(audit, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  process.stdout.write(`${JSON.stringify({
    status: audit.status,
    manifest: path.relative(ROOT, path.join(output, AUDIT_MANIFEST_NAME)).replaceAll("\\", "/"),
    auditDigest: audit.auditDigest,
    counts: audit.counts,
  })}\n`);
}

function loadAudit(output, supersessionReceiptArgument = null) {
  const auditPath = path.join(output, AUDIT_MANIFEST_NAME);
  const audit = readJson(auditPath, "orientation visual audit manifest");
  if (
    audit.schema !== "cf7.production-portrait-orientation-visual-audit-manifest.v1" ||
    audit.status !== "orientation_visual_audit_ready" ||
    audit.productionReady !== false ||
    objectDigest(audit, "auditDigest") !== audit.auditDigest ||
    audit.counts?.acceptedVariants !== 217 ||
    audit.gates?.allAcceptedVariantsIncluded !== true ||
    audit.gates?.modelSuggestionsRequireHumanAcceptanceBeforeWrites !== true
  ) {
    fail("AUDIT_MANIFEST_INVALID", "preflight", "orientation visual audit manifest 未闭合");
  }
  const supersession = loadSupersessionReceipt(supersessionReceiptArgument, audit, auditPath);
  verifyArtifactOrSuperseded(audit.input.productionManifest, "audit production manifest", supersession?.mappings);
  for (const record of audit.input.controller.files || []) {
    verifyArtifactOrSuperseded(record, "audit controller source", supersession?.mappings);
  }
  if (sha256Bytes(stableStringify(audit.input.controller.files)) !== audit.input.controller.sourceClosureDigest) {
    fail("CONTROLLER_CLOSURE_INVALID", "preflight", "audit controller source closure 漂移");
  }
  const rowKeys = new Set();
  for (const row of audit.rows || []) {
    if (rowKeys.has(row.reviewKey)) fail("AUDIT_ROW_INVALID", "preflight", `重复 audit row：${row.reviewKey}`);
    rowKeys.add(row.reviewKey);
    verifyArtifact(row.png, `audit PNG ${row.reviewKey}`);
  }
  const batched = new Set();
  for (const batch of audit.batches || []) {
    if (!Array.isArray(batch.rows) || batch.rows.length < 1 || batch.rows.length > 8) {
      fail("AUDIT_BATCH_INVALID", "preflight", `audit batch 行数非法：${batch.modelBatchId}`);
    }
    batch.rows.forEach((row, index) => {
      if (row.attachmentIndex !== index + 1 || !rowKeys.has(row.reviewKey) || batched.has(row.reviewKey)) {
        fail("AUDIT_BATCH_INVALID", "preflight", `audit batch 映射非法：${row.reviewKey}`);
      }
      batched.add(row.reviewKey);
      verifyArtifact(row.png, `audit batch PNG ${row.reviewKey}`);
    });
  }
  if (rowKeys.size !== 217 || batched.size !== 217) fail("AUDIT_BATCH_INVALID", "preflight", "audit batches 未覆盖 217 行");
  return { audit, auditPath, supersession };
}

function createPrompt(audit, batch, role) {
  const input = {
    batchId: audit.batchId,
    modelBatchId: batch.modelBatchId,
    sourceDigest: audit.sourceDigest,
    runRole: role,
    targetDirection: "viewer_right",
    rows: batch.rows.map((row) => ({
      reviewKey: row.reviewKey,
      attachmentIndex: row.attachmentIndex,
      imageSha256: row.png.sha256,
    })),
  };
  const body = [
    "Audit only the horizontal orientation of final game portrait pixels. Do not use tools, files, filenames, prior proposals, or external knowledge.",
    `Your independent role is ${role}.`,
    role === "independent_review"
      ? "Recompute every judgement independently; no proposal result is supplied."
      : "Produce the first independent orientation proposal.",
    "Each attached image maps exactly to the row with the same attachmentIndex. It is the complete current 512px transparent portrait.",
    "Canonical target is viewer-right. Determine current direction from the primary visible anatomy: face, gaze, snout, beak, sensory front, vehicle front/rear structure, or coherent body movement axis.",
    "If that primary direction clearly points viewer-left, use currentDirection=left.",
    "If it clearly points viewer-right, use currentDirection=right.",
    "If frontal, symmetric, or genuinely directionless, use currentDirection=frontal_or_symmetric.",
    "If the pixels are insufficient or cues conflict, use currentDirection=ambiguous.",
    "The controller derives keep/flip_x/human_review from currentDirection; do not output a redundant action field.",
    "A weapon, tail, effect, empty-space composition, or secondary object alone must not override a visible anatomical/front landmark. For multi-subject portraits, use the identity-defining group axis and mark ambiguous when no coherent axis exists.",
    "landmark must name the concrete visible cue and its current direction. confidence rates only this direction judgement.",
    "Return every supplied reviewKey exactly once and only output schema JSON.",
    `Canonical controller input: ${stableStringify(input)}`,
  ].join("\n");
  const promptDigest = sha256Bytes(body);
  const prompt = [
    body,
    "Echo these closure fields exactly:",
    `schema=${ASSESSMENT_SCHEMA}`,
    `batchId=${audit.batchId}`,
    `sourceDigest=${audit.sourceDigest}`,
    `promptDigest=${promptDigest}`,
    `runRole=${role}`,
  ].join("\n");
  return { prompt, promptDigest, transmittedPromptSha256: sha256Bytes(prompt) };
}

function validateAssessment(value, audit, batch, role, promptDigest) {
  exactKeys(value, ["schema", "batchId", "sourceDigest", "promptDigest", "runRole", "assessments"], "assessment result");
  for (const [field, expected] of [
    ["schema", ASSESSMENT_SCHEMA],
    ["batchId", audit.batchId],
    ["sourceDigest", audit.sourceDigest],
    ["promptDigest", promptDigest],
    ["runRole", role],
  ]) {
    if (value[field] !== expected) fail("RESULT_CLOSURE_MISMATCH", "closure", `${field}与 controller 不一致`, { field });
  }
  if (!Array.isArray(value.assessments) || value.assessments.length !== batch.rows.length) {
    fail("RESULT_COUNT_INVALID", "closure", "assessments 数量不闭合");
  }
  const expectedKeys = new Set(batch.rows.map((row) => row.reviewKey));
  const seen = new Set();
  const directionAction = {
    left: "flip_x",
    right: "keep",
    frontal_or_symmetric: "keep",
    ambiguous: "human_review",
  };
  for (const row of value.assessments) {
    exactKeys(row, ["reviewKey", "currentDirection", "landmark", "confidence"], "assessment row");
    if (!expectedKeys.has(row.reviewKey) || seen.has(row.reviewKey)) {
      fail("RESULT_REVIEW_KEY_INVALID", "closure", `reviewKey 未知或重复：${row.reviewKey}`);
    }
    seen.add(row.reviewKey);
    if (!directionAction[row.currentDirection]) fail("RESULT_VALUE_INVALID", "closure", `方向非法：${row.reviewKey}`);
    if (typeof row.landmark !== "string" || !row.landmark.trim() || row.landmark.length > 180) {
      fail("RESULT_VALUE_INVALID", "closure", `landmark 非法：${row.reviewKey}`);
    }
    if (typeof row.confidence !== "number" || !Number.isFinite(row.confidence) || row.confidence < 0 || row.confidence > 1) {
      fail("RESULT_VALUE_INVALID", "closure", `confidence 非法：${row.reviewKey}`);
    }
  }
  return {
    ...value,
    assessments: [...value.assessments]
      .map((row) => ({ ...row, recommendedAction: directionAction[row.currentDirection] }))
      .sort((left, right) => left.reviewKey.localeCompare(right.reviewKey, "zh-CN")),
  };
}

function classifyExit(capture) {
  const text = `${capture.stderr}\n${capture.stdout}`;
  if (/unauthorized|authentication|login required|status[=: ]+401/iu.test(text)) return "AUTHENTICATION_FAILED";
  if (/model.{0,80}(not available|not supported|not found|unsupported|invalid)/iu.test(text)) return "MODEL_UNAVAILABLE";
  if (/invalid_json_schema|Invalid schema for response_format/iu.test(text)) return "OUTPUT_SCHEMA_REJECTED";
  return "PROCESS_EXIT_NONZERO";
}

async function runAttempt(worker, options, batch, role, attemptNumber) {
  const prompt = createPrompt(options.audit, batch, role);
  const imagePaths = batch.rows.map((row) => verifyArtifact(row.png, `model input ${row.reviewKey}`));
  const args = [
    "exec", "--ephemeral", "--ignore-user-config", "--ignore-rules",
    "--model", MODEL,
    "--config", `model_reasoning_effort=${JSON.stringify(EFFORT)}`,
    "--config", 'approval_policy="never"',
    ...(options.serviceTier === "fast" ? ["--config", 'service_tier="fast"', "--config", "features.fast_mode=true"] : []),
    "--sandbox", "read-only", "--cd", options.isolatedCwd, "--skip-git-repo-check",
    ...imagePaths.flatMap((imagePath) => ["--image", imagePath]),
    "--output-schema", OUTPUT_SCHEMA, "--json", "-",
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
    modelRequested: MODEL,
    reasoningEffort: EFFORT,
    serviceTier: options.serviceTier,
    modelBatchId: batch.modelBatchId,
    promptDigest: prompt.promptDigest,
    transmittedPromptSha256: prompt.transmittedPromptSha256,
    imageSha256s: batch.rows.map((row) => row.png.sha256),
    outputSchemaSha256: sha256File(OUTPUT_SCHEMA),
    stdoutSha256: sha256Bytes(capture.stdout),
    stderrSha256: sha256Bytes(capture.stderr),
    stdoutBytes: capture.stdoutBytes,
    stderrBytes: capture.stderrBytes,
  };
  const reject = (code, phase, message, details = {}) => {
    throw new WorkerError(code, phase, message, {
      ...details,
      attempt: { evidence, stdout: capture.stdout, stderr: capture.stderr },
    });
  };
  try {
    if (capture.spawnError) reject("PROCESS_SPAWN_FAILED", "transport", capture.spawnError.message);
    if (capture.timedOut) reject("PROCESS_TIMEOUT", "transport", "Luna 方向审计超时");
    if (capture.overflowStream) reject("CAPTURE_OVERFLOW", "transport", "Luna 输出超过有界缓冲");
    if (capture.termination.survivorPids.length > 0) reject("ORPHAN_PROCESS_SURVIVED", "transport", "终止后仍有存活 PID");
    if (capture.normalExitOrphanPids.length > 0) reject("ORPHAN_PROCESS_OBSERVED", "transport", "正常退出后留下子进程");
    if (capture.exitCode !== 0) reject(classifyExit(capture), "transport", "Luna CLI 非零退出", { exitCode: capture.exitCode });
    const events = parseJsonl(capture.stdout);
    const finalMessage = extractFinalAgentMessage(events);
    let parsed;
    try {
      parsed = JSON.parse(finalMessage.text);
    } catch (error) {
      reject("RESULT_JSON_INVALID", "closure", "最终 agent_message 不是 JSON", { cause: error.message });
    }
    const result = validateAssessment(parsed, options.audit, batch, role, prompt.promptDigest);
    evidence.threadId = finalMessage.threadId;
    evidence.agentMessageCount = finalMessage.agentMessageCount;
    evidence.resultSha256 = sha256Bytes(stableStringify(result));
    evidence.status = "accepted";
    return { evidence, result, stdout: capture.stdout, stderr: capture.stderr };
  } catch (error) {
    if (error instanceof WorkerError && error.details?.attempt) throw error;
    reject(error.code || "UNEXPECTED_ATTEMPT_ERROR", error.phase || "internal", error.message);
  }
}

function writeExclusive(filePath, content) {
  fs.writeFileSync(filePath, content, { encoding: "utf8", flag: "wx" });
}

async function runRole(worker, options, batch, role) {
  const attempts = [];
  for (let attemptNumber = 1; attemptNumber <= 2; attemptNumber += 1) {
    try {
      const accepted = await runAttempt(worker, options, batch, role, attemptNumber);
      const base = `${role}-${batch.modelBatchId}-attempt-${attemptNumber}`;
      const stdoutPath = path.join(options.artifactsDirectory, `${base}.stdout.jsonl`);
      const stderrPath = path.join(options.artifactsDirectory, `${base}.stderr.log`);
      writeExclusive(stdoutPath, accepted.stdout);
      writeExclusive(stderrPath, accepted.stderr);
      attempts.push({
        ...accepted.evidence,
        stdoutArtifact: artifact(stdoutPath),
        stderrArtifact: artifact(stderrPath),
      });
      return { modelBatchId: batch.modelBatchId, role, status: "accepted", attempts, acceptedAttempt: attemptNumber, result: accepted.result };
    } catch (error) {
      const normalized = publicError(error);
      const attempt = error.details?.attempt;
      if (attempt) {
        const base = `${role}-${batch.modelBatchId}-attempt-${attemptNumber}`;
        const stdoutPath = path.join(options.artifactsDirectory, `${base}.stdout.jsonl`);
        const stderrPath = path.join(options.artifactsDirectory, `${base}.stderr.log`);
        writeExclusive(stdoutPath, attempt.stdout);
        writeExclusive(stderrPath, attempt.stderr);
        attempts.push({
          ...attempt.evidence,
          status: "rejected",
          error: normalized,
          stdoutArtifact: artifact(stdoutPath),
          stderrArtifact: artifact(stderrPath),
        });
      }
      if (attemptNumber === 2 || ["AUTHENTICATION_FAILED", "MODEL_UNAVAILABLE", "OUTPUT_SCHEMA_REJECTED"].includes(normalized.code)) {
        throw new WorkerError("RUN_RETRIES_EXHAUSTED", normalized.phase, normalized.message, {
          role,
          modelBatchId: batch.modelBatchId,
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
  let next = 0;
  async function consume() {
    while (true) {
      const index = next;
      next += 1;
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

function aggregate(audit, runs) {
  const byRole = new Map();
  for (const run of runs) {
    for (const assessment of run.result.assessments) {
      byRole.set(`${run.role}:${assessment.reviewKey}`, assessment);
    }
  }
  const comparisons = audit.rows.map((row) => {
    const proposal = byRole.get(`proposal:${row.reviewKey}`);
    const independent = byRole.get(`independent_review:${row.reviewKey}`);
    if (!proposal || !independent) fail("MERGE_INVALID", "closure", `A/B 缺行：${row.reviewKey}`);
    const actionAgreement = proposal.recommendedAction === independent.recommendedAction;
    const directionAgreement = proposal.currentDirection === independent.currentDirection;
    const minimumConfidence = Math.min(proposal.confidence, independent.confidence);
    let disposition;
    if (actionAgreement && proposal.recommendedAction === "keep" && minimumConfidence >= 0.75) {
      disposition = "model_verified_keep";
    } else if (actionAgreement && proposal.recommendedAction === "flip_x") {
      disposition = "human_review_flip_candidate";
    } else {
      disposition = "human_review_ambiguous_or_disagreed";
    }
    return {
      reviewKey: row.reviewKey,
      reviewCode: row.reviewCode,
      currentProductionOrientationAction: row.currentProductionOrientationAction,
      orientationSource: row.orientationSource,
      png: row.png,
      proposal,
      independentReview: independent,
      directionAgreement,
      actionAgreement,
      minimumConfidence,
      disposition,
    };
  });
  const count = (predicate) => comparisons.filter(predicate).length;
  return {
    comparisons,
    counts: {
      assessedVariants: comparisons.length,
      directionAgreement: count((row) => row.directionAgreement),
      actionAgreement: count((row) => row.actionAgreement),
      modelVerifiedKeep: count((row) => row.disposition === "model_verified_keep"),
      humanReviewFlipCandidates: count((row) => row.disposition === "human_review_flip_candidate"),
      humanReviewAmbiguousOrDisagreed: count((row) => row.disposition === "human_review_ambiguous_or_disagreed"),
      humanReviewTotal: count((row) => row.disposition !== "model_verified_keep"),
    },
  };
}

async function runAudit(options) {
  if (!options.output || !options.codexExe) fail("ARGUMENT_REQUIRED", "arguments", "run 需要 --output 与 --codex-exe");
  const output = pilotOutput(options.output, "审计输出", true);
  const { audit, auditPath } = loadAudit(output);
  const reportPath = path.join(output, MODEL_REPORT_NAME);
  const failurePath = path.join(output, "orientation-visual-model-failure.json");
  const artifactsDirectory = path.join(output, "model-artifacts");
  const isolatedCwd = path.join(output, "model-isolated-cwd");
  if (fs.existsSync(reportPath) || fs.existsSync(failurePath) || fs.existsSync(artifactsDirectory)) {
    fail("OUTPUT_EXISTS", "output", "模型报告或 artifacts 已存在，禁止覆盖");
  }
  fs.mkdirSync(artifactsDirectory);
  fs.mkdirSync(isolatedCwd);
  const worker = new CodexCliLunaWorker({ executablePath: path.resolve(options.codexExe), model: MODEL, reasoningEffort: EFFORT });
  const probe = await worker.probe(30_000);
  const jobs = audit.batches.flatMap((batch) => ["proposal", "independent_review"].map((role) => ({
    batch,
    role,
    run: () => runRole(worker, {
      audit,
      artifactsDirectory,
      isolatedCwd,
      serviceTier: options.serviceTier,
      timeoutMs: options.timeoutMs,
    }, batch, role),
  })));
  const settled = await settleWithConcurrency(jobs.map((job) => job.run), options.maxConcurrency);
  const failed = settled.findIndex((result) => result.status === "rejected");
  if (failed >= 0) {
    const failure = {
      schema: "cf7.production-portrait-orientation-model-failure.v1",
      status: "orientation_model_run_failed",
      productionReady: false,
      generatedAt: new Date().toISOString(),
      input: { auditManifest: artifact(auditPath), auditDigest: audit.auditDigest },
      probe,
      execution: { maxConcurrency: options.maxConcurrency, serviceTier: options.serviceTier, timeoutMs: options.timeoutMs },
      completedRuns: settled.flatMap((result) => result.status === "fulfilled" ? [result.value] : []),
      failedRun: { modelBatchId: jobs[failed].batch.modelBatchId, role: jobs[failed].role, error: publicError(settled[failed].reason) },
      gates: { partialSuccessNotPromoted: true, humanReviewOpened: false, productionWrites: false },
    };
    failure.failureDigest = objectDigest(failure, "failureDigest");
    writeExclusive(failurePath, `${JSON.stringify(failure, null, 2)}\n`);
    throw settled[failed].reason;
  }
  const runs = settled.map((result) => result.value);
  const acceptedPids = runs.map((run) => run.attempts.find((attempt) => attempt.attemptNumber === run.acceptedAttempt)?.pid);
  if (acceptedPids.some((pid) => !pid) || new Set(acceptedPids).size !== acceptedPids.length) {
    fail("RUN_INDEPENDENCE_FAILED", "closure", "56 个 A/B 审计运行没有独立 PID");
  }
  for (const batch of audit.batches) {
    const left = runs.find((run) => run.modelBatchId === batch.modelBatchId && run.role === "proposal");
    const right = runs.find((run) => run.modelBatchId === batch.modelBatchId && run.role === "independent_review");
    const leftAttempt = left.attempts.find((attempt) => attempt.attemptNumber === left.acceptedAttempt);
    const rightAttempt = right.attempts.find((attempt) => attempt.attemptNumber === right.acceptedAttempt);
    if (leftAttempt.promptDigest === rightAttempt.promptDigest) {
      fail("RUN_INDEPENDENCE_FAILED", "closure", `同批 A/B prompt digest 相同：${batch.modelBatchId}`);
    }
  }
  const aggregated = aggregate(audit, runs);
  const report = {
    schema: "cf7.production-portrait-orientation-visual-model-report.v1",
    status: "orientation_visual_audit_completed",
    productionReady: false,
    humanReviewRequired: aggregated.counts.humanReviewTotal > 0,
    generatedAt: new Date().toISOString(),
    batchId: audit.batchId,
    sourceDigest: audit.sourceDigest,
    input: { auditManifest: artifact(auditPath), auditDigest: audit.auditDigest },
    controller: controllerEvidence(),
    probe,
    execution: {
      model: MODEL,
      reasoningEffort: EFFORT,
      maxConcurrency: options.maxConcurrency,
      serviceTier: options.serviceTier,
      timeoutMs: options.timeoutMs,
      expectedIndependentRuns: jobs.length,
      completedIndependentRuns: runs.length,
    },
    runs,
    comparisons: aggregated.comparisons,
    counts: aggregated.counts,
    gates: {
      all217FinalPortraitsAssessedTwice: aggregated.counts.assessedVariants === 217 && runs.length === jobs.length,
      proposalAndIndependentReviewProcessesDistinct: true,
      priorOrientationHiddenFromPrompt: true,
      modelSuggestionsNotApplied: true,
      humanAcceptanceRequiredForAnyChange: true,
      productionWrites: false,
    },
  };
  report.reportDigest = objectDigest(report, "reportDigest");
  writeExclusive(reportPath, `${JSON.stringify(report, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify({ status: report.status, report: path.relative(ROOT, reportPath).replaceAll("\\", "/"), reportDigest: report.reportDigest, counts: report.counts })}\n`);
}

function checkAudit(options) {
  if (!options.output) fail("ARGUMENT_REQUIRED", "arguments", "check 需要 --output");
  const output = pilotOutput(options.output, "审计输出", true);
  const { audit, auditPath, supersession } = loadAudit(output, options.supersessionReceipt);
  const reportPath = path.join(output, MODEL_REPORT_NAME);
  const report = readJson(reportPath, "orientation visual model report");
  if (
    report.schema !== "cf7.production-portrait-orientation-visual-model-report.v1" ||
    report.status !== "orientation_visual_audit_completed" ||
    objectDigest(report, "reportDigest") !== report.reportDigest ||
    report.input?.auditManifest?.sha256 !== artifact(auditPath).sha256 ||
    report.input?.auditDigest !== audit.auditDigest ||
    report.counts?.assessedVariants !== 217 ||
    report.gates?.all217FinalPortraitsAssessedTwice !== true ||
    report.gates?.modelSuggestionsNotApplied !== true ||
    report.gates?.productionWrites !== false
  ) {
    fail("MODEL_REPORT_INVALID", "closure", "orientation visual model report 未闭合");
  }
  if (supersession && !sameArtifactRecord(supersession.receipt.inputs.modelReport, artifact(reportPath))) {
    fail("SUPERSESSION_SOURCE_MISMATCH", "closure", "supersession receipt 未绑定当前 model report");
  }
  for (const record of report.controller?.files || []) {
    verifyArtifactOrSuperseded(record, "model report controller", supersession?.mappings);
  }
  const comparisons = report.comparisons || [];
  if (comparisons.length !== 217 || new Set(comparisons.map((row) => row.reviewKey)).size !== 217) {
    fail("MODEL_REPORT_INVALID", "closure", "model comparisons 未覆盖 217 行");
  }
  for (const run of report.runs || []) {
    for (const attempt of run.attempts || []) {
      verifyArtifact(attempt.stdoutArtifact, "model stdout");
      verifyArtifact(attempt.stderrArtifact, "model stderr");
    }
  }
  process.stdout.write(`${JSON.stringify({
    status: "orientation_visual_model_report_verified",
    reportDigest: report.reportDigest,
    supersessionReceiptDigest: supersession?.receipt.receiptDigest || null,
    counts: report.counts,
  })}\n`);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    if (!["build", "run", "check"].includes(options.command)) process.exitCode = 1;
    return;
  }
  if (options.command === "build") buildAudit(options);
  if (options.command === "run") await runAudit(options);
  if (options.command === "check") checkAudit(options);
}

main().catch((error) => {
  process.stderr.write(`${JSON.stringify(publicError(error))}\n`);
  process.exitCode = 1;
});
