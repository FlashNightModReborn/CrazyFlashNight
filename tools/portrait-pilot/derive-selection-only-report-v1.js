#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const {
  createPrompt,
  loadManifest,
  validateResult,
} = require("./run-visual-pilot");

const ROOT = path.resolve(__dirname, "..", "..");
const PORTRAIT_TMP = path.join(ROOT, "tmp", "portrait-pilot");
const OUTPUT_NAME = "selection-stage-model-report.json";
const REPORT_SCHEMA = "cf7.portrait-pilot-feature-model-report.v1";
const RESULT_SCHEMA = "cf7.portrait-pilot-feature-selection.v1";
const FAILURE_SCHEMA = "cf7.portrait-pilot-model-failure-report.v1";
const ROLES = ["proposal", "independent_review"];
const FRAMING_MODES = new Set(["head_closeup", "feature_closeup", "feature_group", "full_subject"]);
const FLAGS = new Set([
  "effect_occlusion",
  "multiple_subjects",
  "variant_uncertain",
  "low_resolution",
  "feature_uncertain",
  "safe_margin_risk",
  "none",
]);

class SelectionOnlyError extends Error {}

function fail(message) {
  throw new SelectionOnlyError(message);
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
  if (actual.bytes !== record.bytes || actual.sha256 !== record.sha256) fail(`${label} artifact 字节闭包不匹配`);
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
  const options = { manifest: null, failureReport: null, output: null, check: false, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--manifest", "--failure-report", "--output"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) fail(`${argument} 缺少值`);
      if (argument === "--manifest") options.manifest = value;
      if (argument === "--failure-report") options.failureReport = value;
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

function resolveRepoFile(value, label) {
  const filePath = path.resolve(ROOT, value);
  const rel = path.relative(ROOT, filePath);
  if (!rel || rel.startsWith("..") || path.isAbsolute(rel) || !fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    fail(`${label} 越界或缺失`);
  }
  return filePath;
}

function resolveOutput(value, mustExist, manifestPath = null) {
  const output = path.resolve(ROOT, value);
  const rel = path.relative(PORTRAIT_TMP, output);
  if (!rel || rel.startsWith("..") || path.isAbsolute(rel) || path.basename(output) !== OUTPUT_NAME) {
    fail(`output 必须是 tmp/portrait-pilot 子目录中的 ${OUTPUT_NAME}`);
  }
  if (manifestPath && path.dirname(output) !== path.dirname(manifestPath)) {
    fail("selection-stage report 必须与 manifest 位于同一批目录");
  }
  if (mustExist && (!fs.existsSync(output) || !fs.statSync(output).isFile())) fail(`${OUTPUT_NAME} 缺失`);
  if (!mustExist && fs.existsSync(output)) fail(`${OUTPUT_NAME} 已存在，禁止覆盖`);
  return output;
}

function exactKeys(value, expected, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(`${label} 必须是对象`);
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (reviewBuild.stableStringify(actual) !== reviewBuild.stableStringify(wanted)) {
    fail(`${label} 字段不闭合`);
  }
}

function validateBox(value, label) {
  if (!Array.isArray(value) || value.length !== 4 || value.some((entry) => typeof entry !== "number" || !Number.isFinite(entry) || entry < 0 || entry > 1)) {
    fail(`${label} 必须是四个 0..1 有限数`);
  }
}

function validateSelectionOnlyResult(value, expected) {
  exactKeys(value, ["schema", "batchId", "sourceDigest", "promptDigest", "runRole", "selections"], "result");
  if (value.schema !== RESULT_SCHEMA || value.batchId !== expected.manifest.batchId || value.sourceDigest !== expected.manifest.sourceDigest) {
    fail("result schema/batch/source closure 不匹配");
  }
  if (value.promptDigest !== expected.promptDigest || value.runRole !== expected.role) {
    fail("result prompt/role closure 不匹配");
  }
  if (!Array.isArray(value.selections) || value.selections.length !== expected.reviewItems.length) {
    fail("selection-only 行数不闭合");
  }
  const itemByKey = new Map(expected.reviewItems.map((item) => [item.reviewKey, item]));
  const seen = new Set();
  for (const selection of value.selections) {
    exactKeys(selection, [
      "reviewKey",
      "candidateId",
      "featureLabel",
      "framingMode",
      "featureBox",
      "mustIncludeBox",
      "confidence",
      "flags",
    ], `selection ${selection?.reviewKey || "?"}`);
    const item = itemByKey.get(selection.reviewKey);
    if (!item || seen.has(selection.reviewKey)) fail(`reviewKey 未知或重复：${selection.reviewKey}`);
    seen.add(selection.reviewKey);
    if (!(item.candidates || []).some((candidate) => candidate.candidateId === selection.candidateId)) {
      fail(`candidateId 不在白名单：${selection.reviewKey}/${selection.candidateId}`);
    }
    if (typeof selection.featureLabel !== "string" || !selection.featureLabel.trim() || selection.featureLabel.length > 80) {
      fail(`featureLabel 非法：${selection.reviewKey}`);
    }
    if (!FRAMING_MODES.has(selection.framingMode)) fail(`framingMode 非法：${selection.reviewKey}`);
    validateBox(selection.featureBox, `${selection.reviewKey} featureBox`);
    validateBox(selection.mustIncludeBox, `${selection.reviewKey} mustIncludeBox`);
    if (typeof selection.confidence !== "number" || !Number.isFinite(selection.confidence) || selection.confidence < 0 || selection.confidence > 1) {
      fail(`confidence 非法：${selection.reviewKey}`);
    }
    if (!Array.isArray(selection.flags) || selection.flags.length < 1 || selection.flags.some((flag) => !FLAGS.has(flag))) {
      fail(`flags 非法：${selection.reviewKey}`);
    }
    if (new Set(selection.flags).size !== selection.flags.length || (selection.flags.includes("none") && selection.flags.length !== 1)) {
      fail(`flags 重复或 none 混用：${selection.reviewKey}`);
    }
  }
  if (seen.size !== itemByKey.size) fail("selection-only reviewKey 未闭合");
  return {
    ...value,
    selections: [...value.selections].sort((left, right) => left.reviewKey.localeCompare(right.reviewKey, "zh-CN")),
  };
}

function parseFirstAgentResult(stdoutPath) {
  const lines = fs.readFileSync(stdoutPath, "utf8").split(/\r?\n/).filter(Boolean);
  const events = lines.map((line, index) => {
    try {
      return JSON.parse(line);
    } catch (error) {
      fail(`stdout JSONL 第 ${index + 1} 行非法：${error.message}`);
    }
  });
  if (!events.some((event) => event.type === "turn.started") || !events.some((event) => event.type === "turn.completed")) {
    fail(`首答未形成完整 turn：${relative(stdoutPath)}`);
  }
  const messages = events.filter((event) => event.type === "item.completed" && event.item?.type === "agent_message");
  if (messages.length !== 1 || typeof messages[0].item.text !== "string") {
    fail(`首答 agent_message 数量非法：${relative(stdoutPath)}`);
  }
  let result;
  try {
    result = JSON.parse(messages[0].item.text);
  } catch (error) {
    fail(`首答 agent_message 不是 JSON：${error.message}`);
  }
  const started = events.find((event) => event.type === "thread.started");
  const completed = events.find((event) => event.type === "turn.completed");
  return {
    result,
    threadId: started?.thread_id || null,
    usage: completed?.usage || null,
    recoverableDiagnostics: events
      .filter((event) => event.type === "error" || (event.type === "item.completed" && event.item?.type === "error"))
      .map((event) => event.type === "error" ? event.message : event.item.message),
  };
}

function strictVerdict(value, expected) {
  try {
    validateResult(structuredClone(value), {
      manifest: expected.manifest,
      reviewItems: expected.reviewItems,
      promptDigest: expected.promptDigest,
      runRole: expected.role,
      selectionMode: "semantic_feature",
      resultSchema: RESULT_SCHEMA,
    });
    return { status: "accepted" };
  } catch (error) {
    return {
      status: "rejected",
      code: error.code || "UNKNOWN",
      phase: error.phase || "unknown",
      message: error.message,
      details: Object.fromEntries(Object.entries(error.details || {}).filter(([key]) => key !== "attempt")),
    };
  }
}

function inventoryMap(failureReport) {
  const records = new Map();
  for (const record of failureReport.modelArtifacts || []) {
    if (records.has(record.path)) fail(`failure report artifact 重复：${record.path}`);
    verifyArtifact(record, `failure report ${record.path}`);
    records.set(record.path, record);
  }
  return records;
}

function firstAttemptBatch(loaded, failureReport, inventory, batch, role) {
  const base = `${role}-${batch.modelBatchId}-attempt-1`;
  const stdoutRel = `${path.posix.dirname(failureReport.input.manifestPath)}/model-artifacts/${base}.stdout.jsonl`;
  const stderrRel = `${path.posix.dirname(failureReport.input.manifestPath)}/model-artifacts/${base}.stderr.log`;
  const stdoutRecord = inventory.get(stdoutRel);
  const stderrRecord = inventory.get(stderrRel);
  if (!stdoutRecord || !stderrRecord) fail(`首答 artifact 缺失：${role}/${batch.modelBatchId}`);
  const stdoutPath = verifyArtifact(stdoutRecord, `${role}/${batch.modelBatchId} stdout`);
  verifyArtifact(stderrRecord, `${role}/${batch.modelBatchId} stderr`);
  const prompt = createPrompt(
    loaded.manifest,
    batch.reviewItems,
    role,
    batch.modelBatchId,
    batch.contactSheet,
    batch.imageInputs,
    null,
  );
  const parsed = parseFirstAgentResult(stdoutPath);
  const result = validateSelectionOnlyResult(parsed.result, {
    manifest: loaded.manifest,
    reviewItems: batch.reviewItems,
    promptDigest: prompt.promptDigest,
    role,
  });
  const strictGeometryVerdict = strictVerdict(parsed.result, {
    manifest: loaded.manifest,
    reviewItems: batch.reviewItems,
    promptDigest: prompt.promptDigest,
    role,
  });
  return {
    role,
    modelBatchId: batch.modelBatchId,
    status: "accepted_selection_only",
    acceptedAttempt: 1,
    selectionPolicy: "earliest_transport_complete_schema_valid_attempt",
    geometryPolicy: "feature_geometry_is_diagnostic_and_discarded_before_selection_lock",
    attempts: [{
      attemptNumber: 1,
      status: "accepted_selection_only",
      promptDigest: prompt.promptDigest,
      transmittedPromptSha256: prompt.transmittedPromptSha256,
      threadId: parsed.threadId,
      usage: parsed.usage,
      recoverableDiagnostics: parsed.recoverableDiagnostics,
      recoverableDiagnosticDigest: sha256Bytes(reviewBuild.stableStringify(parsed.recoverableDiagnostics)),
      resultSha256: sha256Bytes(reviewBuild.stableStringify(result)),
      stdoutArtifact: stdoutRecord,
      stderrArtifact: stderrRecord,
      originalStrictGeometryVerdict: strictGeometryVerdict,
    }],
    result,
  };
}

function flagCount(selection) {
  return selection.flags.filter((flag) => flag !== "none").length;
}

function buildComparisons(proposal, independent) {
  const rightByKey = new Map(independent.result.selections.map((selection) => [selection.reviewKey, selection]));
  return proposal.result.selections.map((left) => {
    const right = rightByKey.get(left.reviewKey);
    if (!right) fail(`独立复核缺行：${left.reviewKey}`);
    return {
      reviewKey: left.reviewKey,
      candidateAgreement: left.candidateId === right.candidateId,
      geometryCompared: false,
      geometryAccepted: false,
      highlightedForHuman:
        left.candidateId !== right.candidateId ||
        flagCount(left) > 0 ||
        flagCount(right) > 0,
    };
  });
}

function controllerEvidence() {
  const files = [
    __filename,
    path.join(__dirname, "run-visual-pilot.js"),
    path.join(__dirname, "schemas", "feature-selection.schema.json"),
  ].map(artifact);
  return {
    version: "portrait-pilot-selection-only-report-v1",
    files,
    sourceClosureDigest: sha256Bytes(reviewBuild.stableStringify(files)),
  };
}

function mergeRole(role, batches, manifest, expectedCount) {
  const selections = batches.flatMap((batch) => batch.result.selections);
  if (selections.length !== expectedCount || new Set(selections.map((selection) => selection.reviewKey)).size !== expectedCount) {
    fail(`${role} selection-only 合并行数不闭合`);
  }
  return {
    role,
    status: "accepted",
    acceptanceScope: "candidate_identity_and_frame_only",
    batches,
    result: {
      schema: RESULT_SCHEMA,
      batchId: manifest.batchId,
      sourceDigest: manifest.sourceDigest,
      runRole: role,
      selectionMode: "semantic_feature",
      selections: [...selections].sort((left, right) => left.reviewKey.localeCompare(right.reviewKey, "zh-CN")),
    },
  };
}

function loadFailureReport(filePath, loaded) {
  const report = JSON.parse(fs.readFileSync(filePath, "utf8"));
  verifyDigestObject(report, "reportDigest", "model failure report");
  if (report.schema !== FAILURE_SCHEMA || report.status !== "model_run_failed" || report.productionReady !== false) {
    fail("model failure report schema/status 非法");
  }
  if (report.manifestDigest !== loaded.manifest.manifestDigest || report.sourceDigest !== loaded.manifest.sourceDigest) {
    fail("model failure report 与 manifest digest 不一致");
  }
  if (report.input?.manifestPath !== relative(loaded.manifestPath) || report.input?.manifestSha256 !== sha256File(loaded.manifestPath)) {
    fail("model failure report manifest artifact 不匹配");
  }
  if (report.input?.localizationViews !== null || report.input?.expectedIndependentRuns !== loaded.modelBatches.length * ROLES.length) {
    fail("selection-only 只接受未进入 localization 的完整 A/B 失败批");
  }
  if (report.gates?.failurePersisted !== true || report.gates?.partialSuccessNotPromoted !== true || report.gates?.productionWrites !== false) {
    fail("model failure report fail-closed gates 不完整");
  }
  return report;
}

function deriveReport(loaded, failureReportPath, generatedAt) {
  const failureReport = loadFailureReport(failureReportPath, loaded);
  const inventory = inventoryMap(failureReport);
  const collected = { proposal: [], independent_review: [] };
  for (const batch of loaded.modelBatches) {
    for (const role of ROLES) {
      collected[role].push(firstAttemptBatch(loaded, failureReport, inventory, batch, role));
    }
  }
  const proposal = mergeRole("proposal", collected.proposal, loaded.manifest, loaded.reviewItems.length);
  const independent = mergeRole("independent_review", collected.independent_review, loaded.manifest, loaded.reviewItems.length);
  const comparisons = buildComparisons(proposal, independent);
  const firstAttempts = [...proposal.batches, ...independent.batches].map((batch) => batch.attempts[0]);
  const promptDigests = firstAttempts.map((attempt) => attempt.promptDigest);
  if (new Set(promptDigests).size !== promptDigests.length) fail("A/B 小批首答 prompt digest 不独立");
  const report = {
    schema: REPORT_SCHEMA,
    status: "candidate_proposed",
    productionReady: false,
    humanReviewRequired: true,
    generatedAt,
    batchId: loaded.manifest.batchId,
    sourceDigest: loaded.manifest.sourceDigest,
    manifestDigest: loaded.manifest.manifestDigest,
    selectionMode: "semantic_feature",
    acceptanceScope: "candidate_identity_and_frame_only",
    controller: controllerEvidence(),
    probe: failureReport.probe,
    input: {
      manifest: artifact(loaded.manifestPath),
      failureReport: artifact(failureReportPath),
      failureReportDigest: failureReport.reportDigest,
      outputSchema: artifact(loaded.outputSchemaPath),
      originalScheduling: failureReport.input,
      firstAttemptPolicy: "earliest_transport_complete_schema_valid_attempt_per_role_and_model_batch",
      currentHumanTargetGeometryUsed: false,
    },
    runs: [proposal, independent],
    comparisons,
    counts: {
      candidateAgreement: comparisons.filter((row) => row.candidateAgreement).length,
      highlightedForHuman: comparisons.filter((row) => row.highlightedForHuman).length,
      firstAttemptsConsumed: firstAttempts.length,
      firstAttemptsRejectedOnlyByStrictGeometry: firstAttempts.filter((attempt) =>
        ["RESULT_FEATURE_TOO_SMALL", "RESULT_REQUIRED_REGION_OMITTED"].includes(attempt.originalStrictGeometryVerdict.code)).length,
    },
    gates: {
      exactFailedRunClosureBound: true,
      earliestAttemptNoOutcomeCherryPicking: true,
      distinctRoleAndBatchPromptDigests: true,
      candidateWhitelistClosed: true,
      featureGeometryAccepted: false,
      featureGeometryForwardedToSelectionLock: false,
      secondStageLocalizationStillRequired: true,
      currentHumanTargetGeometryExcluded: true,
      humanArtAcceptance: false,
      productionWrites: false,
    },
  };
  report.reportDigest = sha256Bytes(reviewBuild.stableStringify(report));
  return report;
}

function build(options) {
  const loaded = loadManifest(options.manifest);
  const failureReportPath = resolveRepoFile(options.failureReport, "failure report");
  const output = resolveOutput(options.output, false, loaded.manifestPath);
  const report = deriveReport(loaded, failureReportPath, new Date().toISOString());
  fs.writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  return report;
}

function check(options) {
  const output = resolveOutput(options.output, true);
  const report = JSON.parse(fs.readFileSync(output, "utf8"));
  verifyDigestObject(report, "reportDigest", "selection-stage model report");
  if (report.schema !== REPORT_SCHEMA || report.productionReady !== false || report.gates?.featureGeometryAccepted !== false) {
    fail("selection-stage model report schema/gates 非法");
  }
  const manifestPath = verifyArtifact(report.input?.manifest, "input manifest");
  const failureReportPath = verifyArtifact(report.input?.failureReport, "input failure report");
  verifyArtifact(report.input?.outputSchema, "input output schema");
  for (const file of report.controller?.files || []) verifyArtifact(file, "controller");
  const loaded = loadManifest(manifestPath);
  const expected = deriveReport(loaded, failureReportPath, report.generatedAt);
  if (reviewBuild.stableStringify(expected) !== reviewBuild.stableStringify(report)) {
    fail("selection-stage model report 不可由冻结首答确定性重放");
  }
  return report;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.output || (!options.check && (!options.manifest || !options.failureReport))) {
    process.stdout.write(`用法：node tools/portrait-pilot/derive-selection-only-report-v1.js --manifest <candidate-manifest.json> --failure-report <model-failure-report.json> --output <tmp/portrait-pilot/.../${OUTPUT_NAME}> [--check]\n`);
    if (!options.help) process.exitCode = 1;
    return;
  }
  const report = options.check ? check(options) : build(options);
  process.stdout.write(`${JSON.stringify({
    status: options.check ? "selection_stage_model_report_verified" : report.status,
    reportDigest: report.reportDigest,
    acceptanceScope: report.acceptanceScope,
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

module.exports = { deriveReport, validateSelectionOnlyResult };
