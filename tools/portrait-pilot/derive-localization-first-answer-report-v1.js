#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const Module = require("node:module");
const path = require("node:path");
const reviewBuild = require("./build-review");

const ROOT = path.resolve(__dirname, "..", "..");
const PORTRAIT_TMP = path.join(ROOT, "tmp", "portrait-pilot");
const OUTPUT_NAME = "model-report.json";
const REPORT_SCHEMA = "cf7.portrait-pilot-feature-model-report.v1";
const RESULT_SCHEMA = "cf7.portrait-pilot-feature-selection-orientation.v2";
const FAILURE_SCHEMA = "cf7.portrait-pilot-model-failure-report.v1";
const RECOVERY_VERSION = "portrait-pilot-localization-first-answer-human-review-v1";
const ORIENTATION_CONTROLLER = path.join(__dirname, "run-localization-pilot-v2.js");
const BASE_CONTROLLER = path.join(__dirname, "run-visual-pilot.js");
const ORIENTATION_SCHEMA = path.join(__dirname, "schemas", "feature-selection-orientation-v2.schema.json");
const WORKER = path.join(ROOT, "tools", "portrait-worker", "lib", "codex-cli-luna-worker.js");
const ROLES = ["proposal", "independent_review"];

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
  if (actual.path !== record.path || actual.bytes !== record.bytes || actual.sha256 !== record.sha256) {
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
    fail("恢复模型报告必须与 manifest 位于同一批目录");
  }
  if (mustExist && (!fs.existsSync(output) || !fs.statSync(output).isFile())) fail(`${OUTPUT_NAME} 缺失`);
  if (!mustExist && fs.existsSync(output)) fail(`${OUTPUT_NAME} 已存在，禁止覆盖`);
  return output;
}

function compileModule(source, filename) {
  const compiled = new Module(filename, module.parent);
  compiled.filename = filename;
  compiled.paths = Module._nodeModulePaths(path.dirname(filename));
  compiled._compile(source, filename);
  return compiled.exports;
}

function loadOrientationApi() {
  let wrapper = fs.readFileSync(ORIENTATION_CONTROLLER, "utf8");
  const entrypoint = "try {\n  main();\n} catch (error) {";
  const offset = wrapper.indexOf(entrypoint);
  if (offset < 0 || offset !== wrapper.lastIndexOf(entrypoint)) fail("方向定位控制器导出锚点漂移");
  wrapper = `${wrapper.slice(0, offset)}module.exports = { transformedSource };\n`;
  const transformer = compileModule(wrapper, ORIENTATION_CONTROLLER);
  if (typeof transformer.transformedSource !== "function") fail("方向定位 source transform 不可用");
  let transformed = transformer.transformedSource();
  const enabled = "if (true) {";
  const enabledOffset = transformed.indexOf(enabled);
  if (enabledOffset < 0 || enabledOffset !== transformed.lastIndexOf(enabled)) fail("方向定位 entrypoint 抑制锚点漂移");
  transformed = `${transformed.slice(0, enabledOffset)}if (false) {${transformed.slice(enabledOffset + enabled.length)}`;
  const api = compileModule(transformed, ORIENTATION_CONTROLLER);
  for (const name of ["applyLocalizationViews", "createPrompt", "loadManifest", "validateResult"]) {
    if (typeof api[name] !== "function") fail(`方向定位 API 缺失：${name}`);
  }
  return api;
}

function controllerEvidence() {
  const files = [__filename, ORIENTATION_CONTROLLER, BASE_CONTROLLER, ORIENTATION_SCHEMA, WORKER].map(artifact);
  return {
    version: RECOVERY_VERSION,
    nodeVersion: process.version,
    platform: process.platform,
    arch: process.arch,
    files,
    sourceClosureDigest: sha256Bytes(reviewBuild.stableStringify(files)),
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
  if (
    !report.input?.localizationViews ||
    report.input.expectedIndependentRuns !== loaded.modelBatches.length * ROLES.length ||
    report.gates?.failurePersisted !== true ||
    report.gates?.partialSuccessNotPromoted !== true ||
    report.gates?.productionWrites !== false
  ) {
    fail("只接受带 localization views 的完整 fail-closed 批");
  }
  return report;
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

function parseFinalAgentResult(stdoutPath) {
  const events = fs.readFileSync(stdoutPath, "utf8").split(/\r?\n/).filter(Boolean).map((line, index) => {
    try {
      return { line: index + 1, event: JSON.parse(line) };
    } catch (error) {
      fail(`stdout JSONL 第 ${index + 1} 行非法：${error.message}`);
    }
  });
  const completions = events.filter(({ event }) => event.type === "turn.completed");
  if (completions.length !== 1 || events.some(({ event }) => event.type === "turn.failed")) {
    fail(`首答没有唯一完整 turn：${relative(stdoutPath)}`);
  }
  const completionLine = completions[0].line;
  const postCompletionError = events.find(({ line, event }) => line >= completionLine && (
    event.type === "error" || (event.type === "item.completed" && event.item?.type === "error")
  ));
  if (postCompletionError) fail(`turn.completed 后仍有 error：${relative(stdoutPath)}`);
  const messages = events.filter(({ line, event }) =>
    line < completionLine && event.type === "item.completed" && event.item?.type === "agent_message" && typeof event.item.text === "string");
  if (messages.length < 1) fail(`首答没有 agent_message：${relative(stdoutPath)}`);
  let result;
  try {
    result = JSON.parse(messages[messages.length - 1].event.item.text);
  } catch (error) {
    fail(`首答最终 agent_message 不是 JSON：${error.message}`);
  }
  const diagnostics = events
    .filter(({ line, event }) => line < completionLine && (
      event.type === "error" || (event.type === "item.completed" && event.item?.type === "error")
    ))
    .map(({ line, event }) => ({
      line,
      type: event.type === "error" ? "error" : "item_error",
      messageSha256: sha256Bytes(event.type === "error" ? (event.message || "") : (event.item.message || "")),
    }));
  return {
    result,
    threadId: events.find(({ event }) => event.type === "thread.started")?.event.thread_id || null,
    usage: completions[0].event.usage || null,
    agentMessageCount: messages.length,
    finalAgentMessageOrdinal: messages.length,
    recoverableDiagnostics: diagnostics,
  };
}

function relaxedManifest(manifest) {
  const relaxed = structuredClone(manifest);
  for (const config of Object.values(relaxed.featureContract.geometry.modes)) {
    config.minimumRenderedFeatureLongAxisOccupancy = 0;
    config.minimumRenderedFeatureShortAxisOccupancy = 0;
  }
  return relaxed;
}

function occupancyMetrics(selection, item, manifest) {
  const candidate = item.candidates.find((entry) => entry.candidateId === selection.candidateId);
  const geometry = manifest.featureContract.geometry;
  const config = geometry.modes[selection.framingMode];
  const safe = geometry.mustIncludeSafeMargin;
  const [fx0, fy0, fx1, fy1] = selection.featureBox;
  const [mx0, my0, mx1, my1] = selection.mustIncludeBox;
  const featureWidth = (fx1 - fx0) * candidate.width;
  const featureHeight = (fy1 - fy0) * candidate.height;
  const mustWidth = (mx1 - mx0) * candidate.width;
  const mustHeight = (my1 - my0) * candidate.height;
  const usable = 1 - 2 * safe;
  const side = Math.max(
    featureWidth / config.featureWidthOccupancy,
    featureHeight / config.featureHeightOccupancy,
    mustWidth / usable,
    mustHeight / usable,
    8,
  );
  const renderedWidth = featureWidth / side;
  const renderedHeight = featureHeight / side;
  const renderedLong = Math.max(renderedWidth, renderedHeight);
  const renderedShort = Math.min(renderedWidth, renderedHeight);
  return {
    reviewKey: selection.reviewKey,
    candidateId: selection.candidateId,
    framingMode: selection.framingMode,
    renderedLong,
    renderedShort,
    minimumLong: config.minimumRenderedFeatureLongAxisOccupancy,
    minimumShort: config.minimumRenderedFeatureShortAxisOccupancy,
    violatesLong: renderedLong + 1e-6 < config.minimumRenderedFeatureLongAxisOccupancy,
    violatesShort: renderedShort + 1e-6 < config.minimumRenderedFeatureShortAxisOccupancy,
  };
}

function processEvidenceFor(failureReport, role, modelBatchId) {
  const completed = (failureReport.completedRuns || []).find((entry) =>
    entry.role === role && entry.run?.modelBatchId === modelBatchId);
  let evidence = completed?.run?.attempts?.find((attempt) => attempt.attemptNumber === 1) || null;
  if (!evidence) {
    const failed = failureReport.failedRun;
    if (failed?.role === role && failed.error?.details?.modelBatchId === modelBatchId) {
      evidence = failed.error.details.attempts?.find((attempt) => attempt.attemptNumber === 1) || null;
    }
  }
  if (!evidence) return null;
  if (
    evidence.exitCode !== 0 || evidence.signal !== null || evidence.timedOut !== false || evidence.terminationReason !== null ||
    (evidence.normalExitOrphanPids || []).length !== 0 || (evidence.survivorPids || []).length !== 0
  ) {
    fail(`首答进程证据不满足恢复条件：${role}/${modelBatchId}`);
  }
  return {
    pid: evidence.pid,
    startedAt: evidence.startedAt,
    endedAt: evidence.endedAt,
    durationMs: evidence.durationMs,
    exitCode: evidence.exitCode,
    timedOut: evidence.timedOut,
    normalExitOrphanPids: evidence.normalExitOrphanPids || [],
    survivorPids: evidence.survivorPids || [],
    originalStatus: evidence.status,
    originalError: evidence.error || null,
  };
}

function firstAttemptBatch(api, loaded, failureReport, inventory, batch, role) {
  const base = `${role}-${batch.modelBatchId}-attempt-1`;
  const prefix = path.posix.dirname(failureReport.input.manifestPath);
  const stdoutRel = `${prefix}/model-artifacts/${base}.stdout.jsonl`;
  const stderrRel = `${prefix}/model-artifacts/${base}.stderr.log`;
  const stdoutRecord = inventory.get(stdoutRel);
  const stderrRecord = inventory.get(stderrRel);
  if (!stdoutRecord || !stderrRecord) fail(`首答 artifact 缺失：${role}/${batch.modelBatchId}`);
  const stdoutPath = verifyArtifact(stdoutRecord, `${role}/${batch.modelBatchId} stdout`);
  verifyArtifact(stderrRecord, `${role}/${batch.modelBatchId} stderr`);
  const prompt = api.createPrompt(
    loaded.manifest,
    batch.reviewItems,
    role,
    batch.modelBatchId,
    batch.contactSheet,
    batch.imageInputs,
    null,
  );
  const parsed = parseFinalAgentResult(stdoutPath);
  let strictVerdict = { status: "accepted" };
  try {
    api.validateResult(structuredClone(parsed.result), {
      manifest: loaded.manifest,
      reviewItems: batch.reviewItems,
      promptDigest: prompt.promptDigest,
      runRole: role,
      selectionMode: loaded.selectionMode,
      resultSchema: loaded.resultSchema,
    });
  } catch (error) {
    strictVerdict = {
      status: "rejected",
      code: error.code || "UNKNOWN",
      phase: error.phase || "unknown",
      message: error.message,
      details: Object.fromEntries(Object.entries(error.details || {}).filter(([key]) => key !== "attempt")),
    };
    if (strictVerdict.code !== "RESULT_FEATURE_TOO_SMALL") {
      fail(`首答含非占比错误，拒绝恢复：${role}/${batch.modelBatchId}/${strictVerdict.code}`);
    }
  }
  const result = api.validateResult(structuredClone(parsed.result), {
    manifest: relaxedManifest(loaded.manifest),
    reviewItems: batch.reviewItems,
    promptDigest: prompt.promptDigest,
    runRole: role,
    selectionMode: loaded.selectionMode,
    resultSchema: loaded.resultSchema,
  });
  const items = new Map(batch.reviewItems.map((item) => [item.reviewKey, item]));
  const occupancy = result.selections.map((selection) => occupancyMetrics(selection, items.get(selection.reviewKey), loaded.manifest));
  const violations = occupancy.filter((entry) => entry.violatesLong || entry.violatesShort);
  if ((strictVerdict.status === "accepted") !== (violations.length === 0)) {
    fail(`严格判定与占比重算不一致：${role}/${batch.modelBatchId}`);
  }
  const processEvidence = processEvidenceFor(failureReport, role, batch.modelBatchId);
  if (processEvidence) {
    if (
      processEvidence.originalStatus === "accepted" && strictVerdict.status !== "accepted" ||
      processEvidence.originalError?.code && processEvidence.originalError.code !== strictVerdict.code
    ) {
      fail(`failure report 进程证据与首答严格判定不一致：${role}/${batch.modelBatchId}`);
    }
  }
  return {
    role,
    modelBatchId: batch.modelBatchId,
    status: "accepted_for_human_review",
    acceptedAttempt: 1,
    acceptanceScope: "locked_candidate_feature_geometry_and_orientation_for_human_review_only",
    attemptPolicy: "attempt_1_final_agent_message_before_single_turn_completed",
    attempts: [{
      attemptNumber: 1,
      status: strictVerdict.status === "accepted" ? "strictly_accepted" : "accepted_for_human_review_geometry",
      promptDigest: prompt.promptDigest,
      transmittedPromptSha256: prompt.transmittedPromptSha256,
      threadId: parsed.threadId,
      usage: parsed.usage,
      agentMessageCount: parsed.agentMessageCount,
      finalAgentMessageOrdinal: parsed.finalAgentMessageOrdinal,
      recoverableDiagnostics: parsed.recoverableDiagnostics,
      recoverableDiagnosticDigest: sha256Bytes(reviewBuild.stableStringify(parsed.recoverableDiagnostics)),
      resultSha256: sha256Bytes(reviewBuild.stableStringify(result)),
      stdoutArtifact: stdoutRecord,
      stderrArtifact: stderrRecord,
      processEvidenceAvailable: processEvidence !== null,
      processEvidence,
      originalStrictGeometryVerdict: strictVerdict,
      occupancyViolations: violations,
    }],
    result,
  };
}

function mergeRole(role, batches, manifest, expectedCount) {
  const selections = batches.flatMap((batch) => batch.result.selections);
  if (selections.length !== expectedCount || new Set(selections.map((selection) => selection.reviewKey)).size !== expectedCount) {
    fail(`${role} 首答合并行数不闭合`);
  }
  return {
    role,
    status: "accepted_for_human_review",
    acceptanceScope: "locked_candidate_feature_geometry_and_orientation_for_human_review_only",
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

function iou(left, right) {
  const x0 = Math.max(left[0], right[0]);
  const y0 = Math.max(left[1], right[1]);
  const x1 = Math.min(left[2], right[2]);
  const y1 = Math.min(left[3], right[3]);
  const intersection = Math.max(0, x1 - x0) * Math.max(0, y1 - y0);
  const leftArea = (left[2] - left[0]) * (left[3] - left[1]);
  const rightArea = (right[2] - right[0]) * (right[3] - right[1]);
  return intersection / (leftArea + rightArea - intersection);
}

function violationKeys(run) {
  return new Set(run.batches.flatMap((batch) => batch.attempts[0].occupancyViolations.map((entry) => entry.reviewKey)));
}

function buildComparisons(proposal, independent) {
  const rightByKey = new Map(independent.result.selections.map((selection) => [selection.reviewKey, selection]));
  const proposalViolations = violationKeys(proposal);
  const independentViolations = violationKeys(independent);
  return proposal.result.selections.map((left) => {
    const right = rightByKey.get(left.reviewKey);
    if (!right) fail(`独立复核缺行：${left.reviewKey}`);
    const featureIou = iou(left.featureBox, right.featureBox);
    const mustIncludeIou = iou(left.mustIncludeBox, right.mustIncludeBox);
    const geometryHardGateViolation = proposalViolations.has(left.reviewKey) || independentViolations.has(left.reviewKey);
    return {
      reviewKey: left.reviewKey,
      candidateAgreement: left.candidateId === right.candidateId,
      framingAgreement: left.framingMode === right.framingMode,
      featureLabelAgreement: left.featureLabel.trim().toLocaleLowerCase("zh-CN") === right.featureLabel.trim().toLocaleLowerCase("zh-CN"),
      orientationAgreement: left.orientationAction === right.orientationAction,
      featureIoU: Number(featureIou.toFixed(6)),
      mustIncludeIoU: Number(mustIncludeIou.toFixed(6)),
      geometryHardGateViolation,
      highlightedForHuman:
        left.candidateId !== right.candidateId ||
        left.framingMode !== right.framingMode ||
        left.orientationAction !== right.orientationAction ||
        featureIou < 0.65 ||
        mustIncludeIou < 0.65 ||
        geometryHardGateViolation ||
        left.flags.some((flag) => flag !== "none") ||
        right.flags.some((flag) => flag !== "none"),
    };
  });
}

function deriveReport(manifestPath, failureReportPath, generatedAt) {
  const api = loadOrientationApi();
  const baseLoaded = api.loadManifest(relative(manifestPath));
  const initialFailure = JSON.parse(fs.readFileSync(failureReportPath, "utf8"));
  const localizationRecord = initialFailure.input?.localizationViews;
  const localizationPath = verifyArtifact(localizationRecord, "localization views");
  const loaded = api.applyLocalizationViews(baseLoaded, relative(localizationPath));
  const failureReport = loadFailureReport(failureReportPath, loaded);
  if (
    loaded.localizationViews?.viewDigest !== localizationRecord.viewDigest ||
    loaded.resultSchema !== RESULT_SCHEMA || loaded.selectionMode !== "semantic_feature"
  ) {
    fail("方向定位 views/result schema 闭包不匹配");
  }
  const inventory = inventoryMap(failureReport);
  const collected = { proposal: [], independent_review: [] };
  for (const batch of loaded.modelBatches) {
    for (const role of ROLES) {
      collected[role].push(firstAttemptBatch(api, loaded, failureReport, inventory, batch, role));
    }
  }
  const proposal = mergeRole("proposal", collected.proposal, loaded.manifest, loaded.reviewItems.length);
  const independent = mergeRole("independent_review", collected.independent_review, loaded.manifest, loaded.reviewItems.length);
  const comparisons = buildComparisons(proposal, independent);
  const firstAttempts = [...proposal.batches, ...independent.batches].map((batch) => batch.attempts[0]);
  const promptDigests = firstAttempts.map((attempt) => attempt.promptDigest);
  if (new Set(promptDigests).size !== promptDigests.length) fail("A/B 小批首答 prompt digest 不独立");
  const violationRows = firstAttempts.flatMap((attempt) => attempt.occupancyViolations);
  const processEvidenceCount = firstAttempts.filter((attempt) => attempt.processEvidenceAvailable).length;
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
    acceptanceScope: "locked_candidate_feature_geometry_and_orientation_for_human_review_only",
    controller: controllerEvidence(),
    probe: failureReport.probe,
    input: {
      manifestPath: relative(loaded.manifestPath),
      manifestSha256: sha256File(loaded.manifestPath),
      failureReport: artifact(failureReportPath),
      failureReportDigest: failureReport.reportDigest,
      localizationViews: loaded.localizationViews,
      contactSheet: loaded.manifest.contactSheet,
      modelBatches: loaded.manifest.modelBatches,
      modelImageInputs: loaded.modelBatches.map((batch) => ({
        modelBatchId: batch.modelBatchId,
        layout: batch.imageLayout,
        images: batch.imageInputs.map((entry) => ({ role: entry.role, artifact: entry.artifact })),
      })),
      outputSchemaPath: relative(loaded.outputSchemaPath),
      outputSchemaSha256: sha256File(loaded.outputSchemaPath),
      eligibleReviewUnitCount: loaded.reviewItems.length,
      blockedReviewUnitCount: loaded.manifest.reviewItems.filter((item) => item.blocked).length,
      scheduling: {
        maxConcurrency: failureReport.input.maxConcurrency,
        serviceTier: failureReport.input.serviceTier,
        independentRunCount: failureReport.input.expectedIndependentRuns,
        batchBarrier: false,
      },
      firstAttemptPolicy: "attempt_1_final_agent_message_before_single_turn_completed_per_role_and_model_batch",
      strictOccupancyPolicy: "retained_as_diagnostic_and_human_review_highlight_not_art_acceptance",
      currentHumanTargetGeometryUsed: false,
    },
    runs: [proposal, independent],
    comparisons,
    counts: {
      candidateAgreement: comparisons.filter((row) => row.candidateAgreement).length,
      orientationAgreement: comparisons.filter((row) => row.orientationAgreement).length,
      proposedFlipX: proposal.result.selections.filter((row) => row.orientationAction === "flip_x").length,
      independentFlipX: independent.result.selections.filter((row) => row.orientationAction === "flip_x").length,
      highlightedForHuman: comparisons.filter((row) => row.highlightedForHuman).length,
      firstAttemptsConsumed: firstAttempts.length,
      strictlyAcceptedFirstAttempts: firstAttempts.filter((attempt) => attempt.originalStrictGeometryVerdict.status === "accepted").length,
      firstAttemptsRejectedOnlyByFeatureOccupancy: firstAttempts.filter((attempt) => attempt.originalStrictGeometryVerdict.code === "RESULT_FEATURE_TOO_SMALL").length,
      occupancyViolationSelections: violationRows.length,
      occupancyViolationReviewKeys: new Set(violationRows.map((row) => row.reviewKey)).size,
      processEvidenceAvailable: processEvidenceCount,
      processEvidenceUnavailable: firstAttempts.length - processEvidenceCount,
    },
    gates: {
      exactFailedRunClosureBound: true,
      attemptOneFinalAgentMessageNoOutcomeCherryPicking: true,
      distinctRoleAndBatchPromptDigests: true,
      candidateWhitelistClosed: true,
      lockedCandidateIdsClosed: comparisons.every((row) => row.candidateAgreement),
      nonOccupancySchemaAndOrientationValidated: true,
      strictFeatureOccupancyAccepted: violationRows.length === 0,
      featureGeometryForwardedOnlyForHumanReview: true,
      completeTurnEvidenceForEveryFirstAttempt: true,
      fullProcessExitAndOrphanEvidenceAvailable: processEvidenceCount === firstAttempts.length,
      partialProcessExitAndOrphanEvidenceBound: processEvidenceCount > 0,
      canonicalPortraitDirectionRight: true,
      modelOrientationDecisionClosed: true,
      cropCoordinatesRemainOriginalSpace: true,
      orientationAppliedAfterCropByVersionedRenderer: true,
      selectedHighResolutionLocalizationBound: true,
      humanAtlasOmittedDuringPreciseLocalization: true,
      currentHumanTargetGeometryExcluded: true,
      humanArtAcceptance: false,
      productionWrites: false,
    },
  };
  report.reportDigest = sha256Bytes(reviewBuild.stableStringify(report));
  return report;
}

function build(options) {
  const manifestPath = resolveRepoFile(options.manifest, "manifest");
  const failureReportPath = resolveRepoFile(options.failureReport, "failure report");
  const output = resolveOutput(options.output, false, manifestPath);
  const report = deriveReport(manifestPath, failureReportPath, new Date().toISOString());
  fs.writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  return report;
}

function check(options) {
  const output = resolveOutput(options.output, true);
  const report = JSON.parse(fs.readFileSync(output, "utf8"));
  verifyDigestObject(report, "reportDigest", "localization first-answer model report");
  if (
    report.schema !== REPORT_SCHEMA || report.status !== "candidate_proposed" || report.productionReady !== false ||
    report.humanReviewRequired !== true || report.gates?.humanArtAcceptance !== false || report.gates?.productionWrites !== false
  ) {
    fail("localization first-answer model report schema/status/gates 非法");
  }
  for (const file of report.controller?.files || []) verifyArtifact(file, "recovery controller");
  const manifestPath = resolveRepoFile(report.input?.manifestPath, "input manifest");
  if (sha256File(manifestPath) !== report.input.manifestSha256) fail("input manifest hash 不匹配");
  const failureReportPath = verifyArtifact(report.input?.failureReport, "input failure report");
  verifyArtifact(report.input?.localizationViews, "input localization views");
  const expected = deriveReport(manifestPath, failureReportPath, report.generatedAt);
  if (reviewBuild.stableStringify(expected) !== reviewBuild.stableStringify(report)) {
    fail("localization first-answer model report 不可由冻结失败批确定性重放");
  }
  return report;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.output || (!options.check && (!options.manifest || !options.failureReport))) {
    process.stdout.write(`用法：node tools/portrait-pilot/derive-localization-first-answer-report-v1.js --manifest <candidate-manifest.json> --failure-report <model-failure-report.json> --output <tmp/portrait-pilot/.../${OUTPUT_NAME}> [--check]\n`);
    if (!options.help) process.exitCode = 1;
    return;
  }
  const report = options.check ? check(options) : build(options);
  process.stdout.write(`${JSON.stringify({
    status: options.check ? "localization_first_answer_report_verified" : report.status,
    reportDigest: report.reportDigest,
    acceptanceScope: report.acceptanceScope,
    counts: report.counts,
    gates: {
      strictFeatureOccupancyAccepted: report.gates.strictFeatureOccupancyAccepted,
      fullProcessExitAndOrphanEvidenceAvailable: report.gates.fullProcessExitAndOrphanEvidenceAvailable,
      humanArtAcceptance: report.gates.humanArtAcceptance,
      productionWrites: report.gates.productionWrites,
    },
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

module.exports = { deriveReport, occupancyMetrics, parseFinalAgentResult };
