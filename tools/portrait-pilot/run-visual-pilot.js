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
const LEGACY_SCHEMA_PATH = path.join(__dirname, "schemas", "visual-selection.schema.json");
const FEATURE_SCHEMA_PATH = path.join(__dirname, "schemas", "feature-selection.schema.json");
const LEGACY_RESULT_SCHEMA = "cf7.portrait-pilot-selection.v1";
const FEATURE_RESULT_SCHEMA = "cf7.portrait-pilot-feature-selection.v1";
const LEGACY_REPORT_SCHEMA = "cf7.portrait-pilot-model-report.v1";
const FEATURE_REPORT_SCHEMA = "cf7.portrait-pilot-feature-model-report.v1";
const MODEL = "gpt-5.6-luna";
const EFFORT = "max";
const ALLOWED_FLAGS = new Set([
  "effect_occlusion",
  "multiple_subjects",
  "variant_uncertain",
  "low_resolution",
  "feature_uncertain",
  "safe_margin_risk",
  "none",
]);

function fail(code, phase, message, details = {}) {
  throw new WorkerError(code, phase, message, details);
}

function exactKeys(value, keys, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("RESULT_SCHEMA_INVALID", "closure", `${label} 必须是对象`);
  }
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (stableStringify(actual) !== stableStringify(expected)) {
    fail("RESULT_SCHEMA_INVALID", "closure", `${label} 字段不闭合`, { actual, expected });
  }
}

function parseArgs(argv) {
  const options = {
    codexExe: process.env.CF7_PORTRAIT_CODEX_EXE || null,
    manifest: null,
    localizationViews: null,
    output: null,
    timeoutMs: 300_000,
    maxConcurrency: 2,
    serviceTier: "standard",
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--codex-exe", "--manifest", "--localization-views", "--output", "--timeout-ms", "--max-concurrency", "--service-tier"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) {
        fail("ARGUMENT_MISSING", "arguments", `${argument} 缺少值`);
      }
      index += 1;
      if (argument === "--codex-exe") options.codexExe = value;
      if (argument === "--manifest") options.manifest = value;
      if (argument === "--localization-views") options.localizationViews = value;
      if (argument === "--output") options.output = value;
      if (argument === "--timeout-ms") options.timeoutMs = Number(value);
      if (argument === "--max-concurrency") options.maxConcurrency = Number(value);
      if (argument === "--service-tier") options.serviceTier = value;
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
    "用法：node tools/portrait-pilot/run-visual-pilot.js --manifest <candidate-manifest.json> --codex-exe <绝对路径>",
    "  --output <path>      默认写入候选批目录/model-report.json，禁止覆盖",
    "  --localization-views <json> 可选：锁定候选后用逐行高分辨率网格图仅做特征定位",
    "  --timeout-ms <ms>    每条独立 Luna 进程上限，默认 300000",
    "  --max-concurrency <n> 全局独立进程并发上限，默认 2，范围 1–12",
    "  --service-tier <tier> standard（默认）或 fast；fast 会增加 ChatGPT 配额消耗",
  ].join("\n");
}

function verifyArtifact(record, label) {
  if (!record || typeof record.path !== "string" || typeof record.sha256 !== "string") {
    fail("ARTIFACT_RECORD_INVALID", "preflight", `${label} artifact 记录不闭合`);
  }
  const fullPath = path.resolve(ROOT, record.path);
  const relative = path.relative(ROOT, fullPath);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    fail("ARTIFACT_PATH_ESCAPE", "preflight", `${label} 越出仓库`);
  }
  requireAbsoluteFile(fullPath, label);
  const stat = fs.statSync(fullPath);
  if (stat.size !== record.bytes || sha256File(fullPath) !== record.sha256) {
    fail("ARTIFACT_HASH_MISMATCH", "preflight", `${label} 字节闭包不匹配`, { path: record.path });
  }
  return fullPath;
}

function resolveModelImageInputs(manifest, batch, compositeContactSheetPath) {
  const calibration = manifest.humanPreferenceCalibration;
  if (!calibration) {
    return {
      layout: "single_contact_sheet_v1",
      contactSheet: batch.contactSheet,
      contactSheetPath: compositeContactSheetPath,
      imageInputs: [
        {
          role: "current_candidates",
          artifact: batch.contactSheet,
          path: compositeContactSheetPath,
        },
      ],
    };
  }
  if (
    !calibration.atlas ||
    !Array.isArray(calibration.contactSheets) ||
    calibration.coverage?.allHumanLabelsVisualized !== true ||
    calibration.gates?.examplesAreNotCandidates !== true
  ) {
    fail("MANIFEST_FEEDBACK_INVALID", "preflight", "人类偏好图谱缺失或未闭合");
  }
  const binding = calibration.contactSheets.find((entry) =>
    entry?.composite?.path === batch.contactSheet.path &&
    entry.composite.sha256 === batch.contactSheet.sha256);
  if (!binding?.base) {
    fail("MANIFEST_FEEDBACK_INVALID", "preflight", "模型合成图没有对应的原始当前候选图", {
      modelBatchId: batch.modelBatchId,
    });
  }
  const currentPath = verifyArtifact(binding.base, `model batch ${batch.modelBatchId} current candidates`);
  const compact = calibration.modelAtlas;
  const preferenceArtifact = compact || calibration.atlas;
  if (compact) {
    const retrieval = calibration.modelAtlasRetrieval;
    const gates = retrieval?.gates || {};
    if (
      retrieval?.fullAtlas?.sha256 !== calibration.atlas.sha256 ||
      retrieval?.modelAtlasPatchCount >= retrieval?.fullAtlasPatchCount ||
      gates.fullHumanEvidenceBound !== true ||
      gates.aggregateStatisticsCoverAllHumanLabels !== true ||
      gates.visualExamplesRetrievedDeterministically !== true ||
      gates.fullAtlasNotTransmittedPerModelCall !== true ||
      gates.examplesAreNotCandidates !== true ||
      gates.productionWrites !== false
    ) {
      fail("MANIFEST_FEEDBACK_INVALID", "preflight", "紧凑人类偏好检索视图未绑定完整证据或未减少 patch");
    }
  }
  const preferencePath = verifyArtifact(
    preferenceArtifact,
    compact ? "retrieved compact human preference atlas" : "complete human preference atlas",
  );
  if (binding.base.sha256 === preferenceArtifact.sha256) {
    fail("MANIFEST_FEEDBACK_INVALID", "preflight", "当前候选图与历史偏好图谱不得为同一 artifact");
  }
  return {
    layout: compact
      ? "separate_current_candidates_and_retrieved_human_atlas_v2"
      : "separate_current_candidates_and_full_human_atlas_v1",
    contactSheet: binding.base,
    contactSheetPath: currentPath,
    imageInputs: [
      {
        role: "current_candidates",
        artifact: binding.base,
        path: currentPath,
      },
      {
        role: compact ? "retrieved_human_preferences_not_candidates" : "human_preferences_not_candidates",
        artifact: preferenceArtifact,
        path: preferencePath,
      },
    ],
  };
}

function loadManifest(manifestPath) {
  const absolutePath = requireAbsoluteFile(path.resolve(ROOT, manifestPath), "candidate manifest");
  const manifest = JSON.parse(fs.readFileSync(absolutePath, "utf8"));
  const legacy = manifest.schema === "cf7.enemy-portrait-candidates.v1" && manifest.phase === "P2";
  const feature =
    [
      "cf7.enemy-portrait-feature-refinement-candidates.v1",
      "cf7.enemy-portrait-feature-refinement-candidates.v2",
    ].includes(manifest.schema) &&
    manifest.phase === "P3_FEATURE_REFINEMENT";
  if (!legacy && !feature) {
    fail("MANIFEST_SCHEMA_INVALID", "preflight", "候选 manifest schema/phase 不受支持");
  }
  const copy = { ...manifest };
  delete copy.manifestDigest;
  if (sha256Bytes(stableStringify(copy)) !== manifest.manifestDigest) {
    fail("MANIFEST_DIGEST_MISMATCH", "preflight", "候选 manifestDigest 不匹配");
  }
  const contactSheetPath = verifyArtifact(manifest.contactSheet, "contact sheet");
  const reviewItems = manifest.reviewItems.filter((item) => !item.blocked);
  const blockedItems = manifest.reviewItems.filter((item) => item.blocked);
  if (
    reviewItems.length < 1 ||
    !manifest.counts ||
    manifest.counts.reviewUnitCount !== manifest.reviewItems.length ||
    manifest.counts.eligibleReviewUnitCount !== reviewItems.length ||
    manifest.counts.blockedReviewUnitCount !== blockedItems.length
  ) {
    fail("MANIFEST_COUNT_INVALID", "preflight", "审核单元 counts 不闭合或没有可运行项");
  }
  const keys = new Set();
  for (const item of reviewItems) {
    if (keys.has(item.reviewKey) || !Array.isArray(item.candidates) || item.candidates.length < 1) {
      fail("MANIFEST_REVIEW_INVALID", "preflight", "审核键重复或没有候选", { reviewKey: item.reviewKey });
    }
    keys.add(item.reviewKey);
    const candidateIds = new Set();
    for (const candidate of item.candidates) {
      if (candidateIds.has(candidate.candidateId)) {
        fail("MANIFEST_REVIEW_INVALID", "preflight", "候选 ID 重复", { candidateId: candidate.candidateId });
      }
      candidateIds.add(candidate.candidateId);
      verifyArtifact(candidate.artifact, `candidate ${candidate.candidateId}`);
      if (feature) verifyArtifact(candidate.vectorArtifact, `vector candidate ${candidate.candidateId}`);
    }
  }
  const expectedBatchCount = Math.ceil(reviewItems.length / 4);
  if (!Array.isArray(manifest.modelBatches) || manifest.modelBatches.length !== expectedBatchCount) {
    fail("MANIFEST_BATCH_INVALID", "preflight", `模型小批次数不闭合：expected=${expectedBatchCount}`);
  }
  const itemByKey = new Map(reviewItems.map((item) => [item.reviewKey, item]));
  const batchedKeys = new Set();
  const modelBatches = manifest.modelBatches.map((batch) => {
    if (!batch || typeof batch.modelBatchId !== "string" || !Array.isArray(batch.reviewKeys)) {
      fail("MANIFEST_BATCH_INVALID", "preflight", "模型批次字段不闭合");
    }
    if (batch.reviewKeys.length < 1 || batch.reviewKeys.length > 4) {
      fail("MANIFEST_BATCH_INVALID", "preflight", "模型批次必须为 1–4 行", { modelBatchId: batch.modelBatchId });
    }
    const batchItems = batch.reviewKeys.map((reviewKey) => {
      const item = itemByKey.get(reviewKey);
      if (!item || batchedKeys.has(reviewKey)) {
        fail("MANIFEST_BATCH_INVALID", "preflight", "模型批次含未知或重复审核键", { reviewKey });
      }
      batchedKeys.add(reviewKey);
      return item;
    });
    const compositeContactSheetPath = verifyArtifact(batch.contactSheet, `model batch ${batch.modelBatchId}`);
    const modelImages = resolveModelImageInputs(manifest, batch, compositeContactSheetPath);
    return {
      modelBatchId: batch.modelBatchId,
      reviewItems: batchItems,
      manifestContactSheet: batch.contactSheet,
      contactSheet: modelImages.contactSheet,
      contactSheetPath: modelImages.contactSheetPath,
      imageLayout: modelImages.layout,
      imageInputs: modelImages.imageInputs,
    };
  });
  if (batchedKeys.size !== reviewItems.length) {
    fail("MANIFEST_BATCH_INVALID", "preflight", "模型批次没有覆盖全部可选审核键");
  }
  return {
    manifest,
    manifestPath: absolutePath,
    contactSheetPath,
    reviewItems,
    modelBatches,
    selectionMode: feature ? "semantic_feature" : "legacy_crop",
    outputSchemaPath: feature ? FEATURE_SCHEMA_PATH : LEGACY_SCHEMA_PATH,
    resultSchema: feature ? FEATURE_RESULT_SCHEMA : LEGACY_RESULT_SCHEMA,
    reportSchema: feature ? FEATURE_REPORT_SCHEMA : LEGACY_REPORT_SCHEMA,
  };
}

function applyLocalizationViews(loaded, viewManifestPath) {
  const absolutePath = requireAbsoluteFile(path.resolve(ROOT, viewManifestPath), "localization view manifest");
  const relative = path.relative(path.join(ROOT, "tmp", "portrait-pilot"), absolutePath);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    fail("LOCALIZATION_VIEW_PATH_INVALID", "preflight", "localization view manifest 必须位于 tmp/portrait-pilot 下");
  }
  const viewManifest = JSON.parse(fs.readFileSync(absolutePath, "utf8"));
  const envelope = { ...viewManifest };
  delete envelope.viewDigest;
  if (
    viewManifest.schema !== "cf7.portrait-pilot-localization-views.v1" ||
    viewManifest.status !== "localization_views_ready" ||
    viewManifest.productionReady !== false ||
    sha256Bytes(stableStringify(envelope)) !== viewManifest.viewDigest
  ) {
    fail("LOCALIZATION_VIEW_INVALID", "preflight", "localization view manifest schema/digest 不匹配");
  }
  const boundManifestPath = verifyArtifact(viewManifest.input?.manifest, "localization bound manifest");
  if (
    boundManifestPath !== loaded.manifestPath ||
    viewManifest.input.manifestDigest !== loaded.manifest.manifestDigest ||
    viewManifest.gates?.humanTargetGeometryExcluded !== true ||
    viewManifest.gates?.normalizedCandidateMapping !== true
  ) {
    fail("LOCALIZATION_VIEW_INVALID", "preflight", "localization views 没有精确绑定当前 manifest 或泄漏真人目标");
  }
  verifyArtifact(viewManifest.input.sourceReviewData, "localization source review data");
  verifyArtifact(viewManifest.controller, "localization view controller");
  if (!Array.isArray(viewManifest.rows) || viewManifest.rows.length !== loaded.reviewItems.length) {
    fail("LOCALIZATION_VIEW_INVALID", "preflight", "localization view rows 数量不闭合");
  }
  const originalItems = new Map(loaded.reviewItems.map((item) => [item.reviewKey, item]));
  const rowsByKey = new Map();
  for (const row of viewManifest.rows) {
    const item = originalItems.get(row.reviewKey);
    const candidate = item?.candidates.find((entry) => entry.candidateId === row.candidateId);
    if (
      !item || rowsByKey.has(row.reviewKey) || !candidate ||
      row.normalizedCoordinatesMatchCandidate !== true ||
      candidate.artifact.sha256 !== row.candidateArtifact?.sha256 ||
      candidate.width !== row.candidateWidth || candidate.height !== row.candidateHeight
    ) {
      fail("LOCALIZATION_VIEW_INVALID", "preflight", "localization row 候选/hash/坐标不闭合", { reviewKey: row.reviewKey });
    }
    verifyArtifact(row.candidateArtifact, `localization candidate ${row.reviewKey}`);
    verifyArtifact(row.sourceHighResolution, `localization high resolution ${row.reviewKey}`);
    const viewPath = verifyArtifact(row.view, `localization view ${row.reviewKey}`);
    rowsByKey.set(row.reviewKey, { row, viewPath });
  }
  const lockedItems = loaded.reviewItems.map((item) => {
    const binding = rowsByKey.get(item.reviewKey);
    return {
      ...item,
      lockedCandidateId: binding.row.candidateId,
      localizationView: {
        artifact: binding.row.view,
        viewSize: binding.row.viewSize,
        sourceHighResolution: binding.row.sourceHighResolution,
      },
    };
  });
  const lockedByKey = new Map(lockedItems.map((item) => [item.reviewKey, item]));
  const modelBatches = loaded.modelBatches.map((batch) => {
    const reviewItems = batch.reviewItems.map((item, index) => ({
      ...lockedByKey.get(item.reviewKey),
      localizationView: {
        ...lockedByKey.get(item.reviewKey).localizationView,
        attachmentIndex: index + 1,
      },
    }));
    const imageInputs = reviewItems.map((item) => {
      const binding = rowsByKey.get(item.reviewKey);
      return {
        role: `selected_high_resolution_view:${item.reviewCode}`,
        artifact: binding.row.view,
        path: binding.viewPath,
      };
    });
    return {
      ...batch,
      reviewItems,
      contactSheet: imageInputs[0].artifact,
      contactSheetPath: imageInputs[0].path,
      imageLayout: "selected_high_resolution_views_v1",
      imageInputs,
    };
  });
  return {
    ...loaded,
    reviewItems: lockedItems,
    modelBatches,
    localizationViews: {
      path: path.relative(ROOT, absolutePath).replaceAll("\\", "/"),
      bytes: fs.statSync(absolutePath).size,
      sha256: sha256File(absolutePath),
      viewDigest: viewManifest.viewDigest,
      lockedRole: viewManifest.input.lockRole,
      maxDimension: viewManifest.renderContract.maxDimension,
    },
  };
}

function createPrompt(manifest, reviewItems, runRole, modelBatchId, contactSheet, imageInputs, repairFeedback = null) {
  const featureMode = manifest.phase === "P3_FEATURE_REFINEMENT";
  const localizationMode = featureMode && reviewItems.every((item) => item.lockedCandidateId);
  const humanCoverage = manifest.humanPreferenceCalibration?.coverage || null;
  const input = {
    batchId: manifest.batchId,
    modelBatchId,
    sourceDigest: manifest.sourceDigest,
    contactSheetSha256: contactSheet.sha256,
    imageInputs: imageInputs.map((entry) => ({ role: entry.role, sha256: entry.artifact.sha256 })),
    selectionMode: featureMode ? "semantic_feature" : "legacy_crop",
    globalFeatureContract: featureMode && !localizationMode ? manifest.featureContract.global : null,
    humanEvidenceSummary: featureMode && humanCoverage ? {
      decisionCount: humanCoverage.decisionCount,
      passAnchorCount: humanCoverage.passAnchorCount,
      guidedCorrectionCount: humanCoverage.guidedCorrectionCount,
      anomalyCount: humanCoverage.anomalyCount,
    } : null,
    rendererModes: featureMode ? Object.keys(manifest.featureContract.geometry.modes).sort() : null,
    rendererSafeMargin: featureMode ? manifest.featureContract.geometry.mustIncludeSafeMargin : null,
    repairFeedback: featureMode ? repairFeedback : null,
    rows: reviewItems.map((item) => ({
      reviewCode: item.reviewCode,
      reviewKey: item.reviewKey,
      portraitRef: item.portraitRef,
      variantKey: item.variantKey,
      variantResolution: item.variantResolution,
      category: item.category,
      humanFeedback: featureMode ? item.humanFeedback : null,
      intentPolicy: featureMode ? item.intentPolicy : null,
      oldReferencePresent: Boolean(item.oldReference),
      lockedCandidateId: item.lockedCandidateId || null,
      localizationView: item.localizationView ? {
        attachmentIndex: item.localizationView.attachmentIndex,
        sha256: item.localizationView.artifact.sha256,
        width: item.localizationView.viewSize[0],
        height: item.localizationView.viewSize[1],
        coordinateSpace: "locked candidate normalized 0..1",
      } : null,
      candidates: item.candidates
        .filter((candidate) => !item.lockedCandidateId || candidate.candidateId === item.lockedCandidateId)
        .map((candidate, index) => ({
        contactSheetLabel: `C${String(index + 1).padStart(2, "0")}`,
        candidateId: candidate.candidateId,
        frame: candidate.frame,
        width: candidate.width,
        height: candidate.height,
        vectorFrameSha256: featureMode ? candidate.vectorArtifact.sha256 : null,
        })),
    })),
  };
  const shared = [
    "Do not use tools, modify files, redraw pixels, or claim human art acceptance.",
    `Model batch: ${modelBatchId}.`,
    `Your independent role is ${runRole}.`,
    runRole === "independent_review"
      ? "Recompute independently. No proposal result or explanation is supplied."
      : "Produce the first independent proposal.",
    "Return every row exactly once, choose only its listed candidateId, and return only the output-schema JSON.",
    "If the orange/white JK state cannot be proven from the candidates, select the best composition but include variant_uncertain; never infer a state from the row label.",
    "Use flags=[\"none\"] only when no risk flag applies.",
  ];
  const featureInstructions = [
    localizationMode
      ? "Goal: frame selection is already locked. Use the enlarged selected-frame attachment to precisely localize the smallest visible feature that makes this unit recognizable in an 80px square avatar."
      : "Goal: select the clearest current frame and localize the smallest visible feature that makes this unit recognizable in an 80px square avatar.",
    localizationMode
      ? "Each attachment maps to exactly one canonical row by attachmentIndex. It is a high-resolution crop of that row's locked candidate with an exact normalized 0..1 grid. Output coordinates in that attachment/candidate space; do not change candidateId and do not infer coordinates from another attachment."
      : imageInputs[1]?.role === "retrieved_human_preferences_not_candidates"
      ? "Attachment 1 is the current candidate sheet. Attachment 2 is retrieved human-composition evidence only: never select an identity, candidateId, or coordinate from it."
      : imageInputs.length === 2
        ? "Attachment 1 is the current candidate sheet. Attachment 2 is historical human-composition evidence only: never select an identity, candidateId, or coordinate from it."
        : "The attachment is the current candidate sheet; OLD REF is context only.",
    "For a humanoid, use head_closeup and tightly bound the complete head (face, hair, headgear): stop at the jaw or lowest identity-defining hair, excluding chest, waist, limbs, and weapons. For a non-humanoid, reason from visible anatomy and tightly bound its strongest identity structure; use feature_group only for inseparable structures and full_subject only when the whole silhouette is the identity.",
    "Use the normalized grid on the chosen candidate. featureBox is the tight inner box around visible identity pixels. mustIncludeBox contains it and adds only truly inseparable context. Do not add aesthetic padding: every extra strip of torso, background, effect, or ordinary weapon is an error because the renderer adds safety margin.",
    localizationMode
      ? "The candidate is already proven by the selection stage; spend the visual reasoning budget on exact landmark boundaries and coordinates."
      : "Use this order: choose one clear subject and pose; scan the whole candidate for the head or strongest identity structure; name concrete visible landmarks; verify they belong to the current unit; only then draw boxes. The globalFeatureContract in the canonical input records the accumulated human rules and is binding.",
    "The feature must be the first visual focus and fill the avatar while retaining safety above it and toward its facing direction. Weak shoulders, weapon ends, tails, legs, and effects may touch or cross the crop edge.",
    localizationMode
      ? "Name concrete landmarks actually visible in the locked frame. If no head landmark is visible, use the strongest supported non-head identity feature and flag uncertainty; never call the torso center a head."
      : "Name concrete landmarks actually visible in the chosen current frame. If a claimed head landmark is not visible, choose another frame or a supported non-head mode; never call the torso center a head.",
    "Any intentPolicy required region and row-level humanFeedback is binding. Keep required regions inside the corresponding box.",
    repairFeedback
      ? `Repair only this controller rejection without broadening the true feature: ${stableStringify(repairFeedback)}`
      : "No repair feedback.",
  ];
  const legacyInstructions = [
    "You are selecting portrait source frames, focal points, and crops from one attached CF7 contact sheet.",
    "Prefer a recognizable head/upper body or non-humanoid focal core at 32/48/80px.",
    "Avoid frames dominated by HP bars, LV/name text, weapons detached from the subject, effects, prone/death poses, black shadows, or multiple subjects.",
    "cropBox and focalPoint are normalized to the selected candidate PNG, not to the contact sheet. Keep crop width and height at least 0.2.",
  ];
  const body = [
    ...(featureMode ? featureInstructions : legacyInstructions),
    ...shared,
    `Canonical controller input: ${stableStringify(input)}`,
  ].join("\n");
  const promptDigest = sha256Bytes(body);
  const prompt = [
    body,
    "Echo these closure fields exactly:",
    `schema=${featureMode ? FEATURE_RESULT_SCHEMA : LEGACY_RESULT_SCHEMA}`,
    `batchId=${manifest.batchId}`,
    `sourceDigest=${manifest.sourceDigest}`,
    `promptDigest=${promptDigest}`,
    `runRole=${runRole}`,
  ].join("\n");
  return { prompt, promptDigest, transmittedPromptSha256: sha256Bytes(prompt), input };
}

function validateNumberArray(value, length, label) {
  if (!Array.isArray(value) || value.length !== length || value.some((entry) => typeof entry !== "number" || !Number.isFinite(entry))) {
    fail("RESULT_VALUE_INVALID", "closure", `${label} 必须是 ${length} 个有限数字`);
  }
  if (value.some((entry) => entry < 0 || entry > 1)) {
    fail("RESULT_VALUE_INVALID", "closure", `${label} 越出 0..1`);
  }
}

function validateFeatureOccupancy(selection, item, manifest) {
  const candidate = item.candidates.find((entry) => entry.candidateId === selection.candidateId);
  const geometry = manifest.featureContract?.geometry;
  const config = geometry?.modes?.[selection.framingMode];
  const safe = geometry?.mustIncludeSafeMargin;
  if (!candidate || !config || typeof safe !== "number" || safe <= 0 || safe >= 0.5) {
    fail("MANIFEST_GEOMETRY_INVALID", "closure", "特征构图合同或候选尺寸缺失");
  }
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
  if (
    renderedLong + 1e-6 < config.minimumRenderedFeatureLongAxisOccupancy ||
    renderedShort + 1e-6 < config.minimumRenderedFeatureShortAxisOccupancy
  ) {
    fail("RESULT_FEATURE_TOO_SMALL", "closure", "文字构图模式与最终特征占比不一致；请收紧 featureBox/mustIncludeBox", {
      reviewKey: selection.reviewKey,
      candidateId: selection.candidateId,
      framingMode: selection.framingMode,
      renderedLong,
      renderedShort,
      minimumLong: config.minimumRenderedFeatureLongAxisOccupancy,
      minimumShort: config.minimumRenderedFeatureShortAxisOccupancy,
    });
  }
}

function validateRequiredRegions(selection, item) {
  const policy = item.intentPolicy;
  if (!policy || typeof policy !== "object") return;
  for (const [boxField, regionField] of [
    ["featureBox", "requiredFeatureRegion"],
    ["mustIncludeBox", "requiredMustIncludeRegion"],
  ]) {
    const requiredRegion = policy[regionField];
    if (requiredRegion === undefined) continue;
    validateNumberArray(requiredRegion, 4, regionField);
    const actualBox = selection[boxField];
    const tolerance = 1e-6;
    const contains =
      actualBox[0] <= requiredRegion[0] + tolerance &&
      actualBox[1] <= requiredRegion[1] + tolerance &&
      actualBox[2] >= requiredRegion[2] - tolerance &&
      actualBox[3] >= requiredRegion[3] - tolerance;
    if (!contains) {
      fail(
        "RESULT_REQUIRED_REGION_OMITTED",
        "closure",
        `${boxField} 未完整包含人工维护的 ${regionField}`,
        { reviewKey: selection.reviewKey, candidateId: selection.candidateId, boxField, actualBox, requiredRegion },
      );
    }
  }
}

function validateResult(value, expected) {
  exactKeys(value, ["schema", "batchId", "sourceDigest", "promptDigest", "runRole", "selections"], "result");
  for (const [field, target] of [
    ["schema", expected.resultSchema],
    ["batchId", expected.manifest.batchId],
    ["sourceDigest", expected.manifest.sourceDigest],
    ["promptDigest", expected.promptDigest],
    ["runRole", expected.runRole],
  ]) {
    if (value[field] !== target) {
      fail("RESULT_CLOSURE_MISMATCH", "closure", `${field} 与 controller 不一致`, { field });
    }
  }
  if (!Array.isArray(value.selections) || value.selections.length !== expected.reviewItems.length) {
    fail("RESULT_COUNT_INVALID", "closure", "selections 数量不闭合");
  }
  const itemByKey = new Map(expected.reviewItems.map((item) => [item.reviewKey, item]));
  const seen = new Set();
  for (const selection of value.selections) {
    if (expected.selectionMode === "semantic_feature") {
      exactKeys(
        selection,
        ["reviewKey", "candidateId", "featureLabel", "framingMode", "featureBox", "mustIncludeBox", "confidence", "flags"],
        "selection",
      );
    } else {
      exactKeys(selection, ["reviewKey", "candidateId", "focalPoint", "cropBox", "confidence", "flags"], "selection");
    }
    const item = itemByKey.get(selection.reviewKey);
    if (!item || seen.has(selection.reviewKey)) {
      fail("RESULT_REVIEW_KEY_INVALID", "closure", "reviewKey 未知或重复", { reviewKey: selection.reviewKey });
    }
    seen.add(selection.reviewKey);
    if (!item.candidates.some((candidate) => candidate.candidateId === selection.candidateId)) {
      fail("RESULT_CANDIDATE_INVALID", "closure", "candidateId 不在白名单", { candidateId: selection.candidateId });
    }
    if (item.lockedCandidateId && selection.candidateId !== item.lockedCandidateId) {
      fail("RESULT_CANDIDATE_INVALID", "closure", "localization-only pass 改动了锁定候选", {
        reviewKey: selection.reviewKey,
        candidateId: selection.candidateId,
        lockedCandidateId: item.lockedCandidateId,
      });
    }
    if (expected.selectionMode === "semantic_feature") {
      if (typeof selection.featureLabel !== "string" || selection.featureLabel.trim() === "" || selection.featureLabel.length > 80) {
        fail("RESULT_VALUE_INVALID", "closure", "featureLabel 为空或过长");
      }
      if (!["head_closeup", "feature_closeup", "feature_group", "full_subject"].includes(selection.framingMode)) {
        fail("RESULT_VALUE_INVALID", "closure", "framingMode 非法", { framingMode: selection.framingMode });
      }
      validateNumberArray(selection.featureBox, 4, "featureBox");
      validateNumberArray(selection.mustIncludeBox, 4, "mustIncludeBox");
      const [fx0, fy0, fx1, fy1] = selection.featureBox;
      const [mx0, my0, mx1, my1] = selection.mustIncludeBox;
      if (fx0 >= fx1 || fy0 >= fy1 || fx1 - fx0 < 0.02 || fy1 - fy0 < 0.02) {
        fail("RESULT_VALUE_INVALID", "closure", "featureBox 顺序错误或过窄", { featureBox: selection.featureBox });
      }
      if (mx0 >= mx1 || my0 >= my1 || mx1 - mx0 < 0.05 || my1 - my0 < 0.05) {
        fail("RESULT_VALUE_INVALID", "closure", "mustIncludeBox 顺序错误或过窄", { mustIncludeBox: selection.mustIncludeBox });
      }
      if (fx0 < mx0 || fy0 < my0 || fx1 > mx1 || fy1 > my1) {
        fail("RESULT_VALUE_INVALID", "closure", "featureBox 必须包含在 mustIncludeBox 内", {
          featureBox: selection.featureBox,
          mustIncludeBox: selection.mustIncludeBox,
        });
      }
      validateRequiredRegions(selection, item);
      validateFeatureOccupancy(selection, item, expected.manifest);
    } else {
      validateNumberArray(selection.focalPoint, 2, "focalPoint");
      validateNumberArray(selection.cropBox, 4, "cropBox");
      const [x0, y0, x1, y1] = selection.cropBox;
      if (x0 >= x1 || y0 >= y1 || x1 - x0 < 0.2 || y1 - y0 < 0.2) {
        fail("RESULT_VALUE_INVALID", "closure", "cropBox 顺序错误或过窄", { cropBox: selection.cropBox });
      }
    }
    if (typeof selection.confidence !== "number" || selection.confidence < 0 || selection.confidence > 1) {
      fail("RESULT_VALUE_INVALID", "closure", "confidence 越界");
    }
    if (!Array.isArray(selection.flags) || selection.flags.length < 1 || selection.flags.some((flag) => !ALLOWED_FLAGS.has(flag))) {
      fail("RESULT_VALUE_INVALID", "closure", "flags 非法", { flags: selection.flags });
    }
    if (new Set(selection.flags).size !== selection.flags.length || (selection.flags.includes("none") && selection.flags.length !== 1)) {
      fail("RESULT_VALUE_INVALID", "closure", "flags 重复或 none 与风险标记混用", { flags: selection.flags });
    }
  }
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
  const prompt = createPrompt(
    options.manifest,
    options.reviewItems,
    role,
    options.modelBatchId,
    options.contactSheet,
    options.imageInputs,
    options.repairFeedback,
  );
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
    ...options.imageInputs.flatMap((entry) => ["--image", entry.path]),
    "--output-schema",
    options.outputSchemaPath,
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
    if (capture.timedOut) fail("PROCESS_TIMEOUT", "transport", "Luna 视觉进程超时");
    if (capture.overflowStream) fail("CAPTURE_OVERFLOW", "transport", "Luna 输出超过有界缓冲");
    if (capture.termination.survivorPids.length > 0) fail("ORPHAN_PROCESS_SURVIVED", "transport", "终止后仍有存活 PID");
    if (capture.normalExitOrphanPids.length > 0) fail("ORPHAN_PROCESS_OBSERVED", "transport", "正常退出后留下子进程");
    if (capture.exitCode !== 0) fail(classifyExit(capture), "transport", "Luna CLI 非零退出", { exitCode: capture.exitCode });
    const events = parseJsonl(capture.stdout);
    const finalMessage = extractFinalAgentMessage(events);
    let parsed;
    try {
      parsed = JSON.parse(finalMessage.text);
    } catch (error) {
      fail("RESULT_JSON_INVALID", "closure", "最终 agent_message 不是 JSON", { cause: error.message });
    }
    const result = validateResult(parsed, {
      manifest: options.manifest,
      reviewItems: options.reviewItems,
      promptDigest: prompt.promptDigest,
      runRole: role,
      selectionMode: options.selectionMode,
      resultSchema: options.resultSchema,
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
  "RESULT_FEATURE_TOO_SMALL",
  "RESULT_REQUIRED_REGION_OMITTED",
]);

function repairFeedbackFor(error) {
  const details = error?.details || {};
  const feedback = {
    code: error?.code || "UNKNOWN",
    message: error?.message || "Previous attempt was rejected",
  };
  for (const field of [
    "field",
    "reviewKey",
    "candidateId",
    "framingMode",
    "renderedLong",
    "renderedShort",
    "minimumLong",
    "minimumShort",
    "boxField",
    "actualBox",
    "requiredRegion",
    "featureBox",
    "mustIncludeBox",
  ]) {
    if (details[field] !== undefined) feedback[field] = details[field];
  }
  if (feedback.code === "RESULT_FEATURE_TOO_SMALL") {
    feedback.requiredCorrection = "Keep featureBox on the true visible identity feature. Shrink mustIncludeBox toward featureBox without crossing inside it; never enlarge featureBox beyond visible pixels and never swap the two box meanings.";
  }
  if (feedback.code === "RESULT_VALUE_INVALID" && String(feedback.message).includes("featureBox")) {
    feedback.requiredRelationship = "featureBox is the inner box: mx0 <= fx0 < fx1 <= mx1 and my0 <= fy0 < fy1 <= my1. mustIncludeBox must never be smaller than featureBox.";
  }
  return feedback;
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
  const workers = Array.from(
    { length: Math.min(maximumConcurrency, jobs.length) },
    () => consume(),
  );
  await Promise.all(workers);
  return results;
}

function writeExclusive(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content, { encoding: "utf8", flag: "wx" });
}

function artifactInventory(directory) {
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

async function runRole(worker, options, role, artifactsDirectory) {
  const attempts = [];
  const seenPids = new Set();
  let repairFeedback = null;
  const maximumAttempts = 3;
  for (let attemptNumber = 1; attemptNumber <= maximumAttempts; attemptNumber += 1) {
    try {
      const accepted = await runAttempt(worker, { ...options, repairFeedback }, role, attemptNumber);
      if (seenPids.has(accepted.evidence.pid)) fail("PROCESS_ID_REUSED", "transport", "重试没有新 PID");
      attempts.push(accepted.evidence);
      const base = `${role}-${options.modelBatchId}-attempt-${attemptNumber}`;
      writeExclusive(path.join(artifactsDirectory, `${base}.stdout.jsonl`), accepted.stdout);
      writeExclusive(path.join(artifactsDirectory, `${base}.stderr.log`), accepted.stderr);
      accepted.evidence.stdoutArtifact = `model-artifacts/${base}.stdout.jsonl`;
      accepted.evidence.stderrArtifact = `model-artifacts/${base}.stderr.log`;
      return {
        modelBatchId: options.modelBatchId,
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
        const base = `${role}-${options.modelBatchId}-attempt-${attemptNumber}`;
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
          modelBatchId: options.modelBatchId,
          attempts,
          terminalError: normalized,
        });
      }
      repairFeedback = normalized.phase === "closure" ? repairFeedbackFor(normalized) : null;
    }
  }
  fail("RUN_RETRIES_EXHAUSTED", "internal", "不可达的重试终态");
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

function controllerEvidence() {
  const files = [
    __filename,
    LEGACY_SCHEMA_PATH,
    FEATURE_SCHEMA_PATH,
    path.join(ROOT, "tools", "portrait-worker", "lib", "codex-cli-luna-worker.js"),
  ]
    .map((filePath) => ({
      path: path.relative(ROOT, filePath).replaceAll("\\", "/"),
      bytes: fs.statSync(filePath).size,
      sha256: sha256File(filePath),
    }));
  return {
    version: "portrait-pilot-p2-p3-feature-v9-two-stage-selection-localization",
    nodeVersion: process.version,
    platform: process.platform,
    arch: process.arch,
    files,
    sourceClosureDigest: sha256Bytes(stableStringify(files)),
  };
}

function mergeBatchRuns(role, batches, manifest, expectedReviewCount, resultSchema, selectionMode) {
  const selections = batches.flatMap((batch) => batch.result.selections);
  const keys = new Set(selections.map((selection) => selection.reviewKey));
  if (selections.length !== expectedReviewCount || keys.size !== expectedReviewCount) {
    fail("MERGED_RESULT_INVALID", "closure", "模型小批次合并后审核键不闭合", {
      role,
      expectedReviewCount,
      actual: selections.length,
      unique: keys.size,
    });
  }
  return {
    role,
    status: "accepted",
    batches,
    result: {
      schema: resultSchema,
      batchId: manifest.batchId,
      sourceDigest: manifest.sourceDigest,
      runRole: role,
      selectionMode,
      selections: [...selections].sort((left, right) => left.reviewKey.localeCompare(right.reviewKey, "zh-CN")),
    },
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (!options.codexExe || !options.manifest) {
    fail("ARGUMENT_REQUIRED", "arguments", "必须显式提供 --manifest 与 --codex-exe");
  }
  const baseLoaded = loadManifest(options.manifest);
  const loaded = options.localizationViews
    ? applyLocalizationViews(baseLoaded, options.localizationViews)
    : baseLoaded;
  const outputPath = path.resolve(ROOT, options.output || path.join(path.dirname(loaded.manifestPath), "model-report.json"));
  const outputRoot = path.dirname(loaded.manifestPath);
  const relativeOutput = path.relative(outputRoot, outputPath);
  if (relativeOutput.startsWith("..") || path.isAbsolute(relativeOutput)) {
    fail("OUTPUT_PATH_INVALID", "output", "模型报告必须位于候选批目录");
  }
  if (fs.existsSync(outputPath)) fail("OUTPUT_EXISTS", "output", "model-report.json 已存在，禁止覆盖");
  const artifactsDirectory = path.join(outputRoot, "model-artifacts");
  const isolatedCwd = path.join(outputRoot, "model-isolated-cwd");
  if (fs.existsSync(artifactsDirectory)) fail("OUTPUT_EXISTS", "output", "model-artifacts 已存在，禁止覆盖");
  fs.mkdirSync(artifactsDirectory);
  fs.mkdirSync(isolatedCwd, { recursive: true });

  const worker = new CodexCliLunaWorker({ executablePath: path.resolve(options.codexExe), model: MODEL, reasoningEffort: EFFORT });
  const probe = await worker.probe(Math.min(options.timeoutMs, 30_000));
  const collected = { proposal: [], independent_review: [] };
  const jobs = loaded.modelBatches.flatMap((batch) =>
    ["proposal", "independent_review"].map((role) => ({
      role,
      run: () => runRole(
        worker,
        {
          ...loaded,
          ...batch,
          isolatedCwd,
          timeoutMs: options.timeoutMs,
          serviceTier: options.serviceTier,
        },
        role,
        artifactsDirectory,
      ),
    })),
  );
  const settled = await settleWithConcurrency(jobs.map((job) => job.run), options.maxConcurrency);
  const rejectedIndex = settled.findIndex((result) => result.status === "rejected");
  if (rejectedIndex >= 0) {
    const failureReport = {
      schema: "cf7.portrait-pilot-model-failure-report.v1",
      status: "model_run_failed",
      productionReady: false,
      humanReviewRequired: false,
      generatedAt: new Date().toISOString(),
      batchId: loaded.manifest.batchId,
      sourceDigest: loaded.manifest.sourceDigest,
      manifestDigest: loaded.manifest.manifestDigest,
      controller: controllerEvidence(),
      probe,
      input: {
        manifestPath: path.relative(ROOT, loaded.manifestPath).replaceAll("\\", "/"),
        manifestSha256: sha256File(loaded.manifestPath),
        localizationViews: loaded.localizationViews || null,
        maxConcurrency: options.maxConcurrency,
        serviceTier: options.serviceTier,
        timeoutMs: options.timeoutMs,
        expectedIndependentRuns: jobs.length,
      },
      completedRuns: settled.flatMap((result, index) => result.status === "fulfilled"
        ? [{ role: jobs[index].role, run: result.value }]
        : []),
      failedRun: {
        role: jobs[rejectedIndex].role,
        error: publicError(settled[rejectedIndex].reason),
      },
      modelArtifacts: artifactInventory(artifactsDirectory),
      gates: {
        failurePersisted: true,
        partialSuccessNotPromoted: true,
        humanReviewOpened: false,
        productionWrites: false,
      },
    };
    failureReport.reportDigest = sha256Bytes(stableStringify(failureReport));
    writeExclusive(path.join(outputRoot, "model-failure-report.json"), `${JSON.stringify(failureReport, null, 2)}\n`);
    throw settled[rejectedIndex].reason;
  }
  settled.forEach((result, index) => collected[jobs[index].role].push(result.value));
  const allBatchRuns = [...collected.proposal, ...collected.independent_review];
  const acceptedAttempts = allBatchRuns.map((batchRun) =>
    batchRun.attempts.find((attempt) => attempt.attemptNumber === batchRun.acceptedAttempt));
  if (acceptedAttempts.some((attempt) => !attempt)) {
    fail("RUN_INDEPENDENCE_FAILED", "closure", "模型小批次缺 accepted attempt");
  }
  const acceptedPids = acceptedAttempts.map((attempt) => attempt.pid);
  if (new Set(acceptedPids).size !== acceptedPids.length) {
    fail("RUN_INDEPENDENCE_FAILED", "closure", "所有 A/B 小批次必须使用不同 PID");
  }
  for (const modelBatch of loaded.modelBatches) {
    const proposalBatch = collected.proposal.find((batch) => batch.modelBatchId === modelBatch.modelBatchId);
    const reviewBatch = collected.independent_review.find((batch) => batch.modelBatchId === modelBatch.modelBatchId);
    const proposalAttempt = proposalBatch.attempts.find((attempt) => attempt.attemptNumber === proposalBatch.acceptedAttempt);
    const reviewAttempt = reviewBatch.attempts.find((attempt) => attempt.attemptNumber === reviewBatch.acceptedAttempt);
    if (proposalAttempt.promptDigest === reviewAttempt.promptDigest) {
      fail("RUN_INDEPENDENCE_FAILED", "closure", "同一模型小批次的 A/B prompt digest 必须不同");
    }
  }
  const proposal = mergeBatchRuns(
    "proposal",
    collected.proposal,
    loaded.manifest,
    loaded.reviewItems.length,
    loaded.resultSchema,
    loaded.selectionMode,
  );
  const independentReview = mergeBatchRuns(
    "independent_review",
    collected.independent_review,
    loaded.manifest,
    loaded.reviewItems.length,
    loaded.resultSchema,
    loaded.selectionMode,
  );

  const bByKey = new Map(independentReview.result.selections.map((selection) => [selection.reviewKey, selection]));
  const comparisons = proposal.result.selections.map((left) => {
    const right = bByKey.get(left.reviewKey);
    if (loaded.selectionMode === "semantic_feature") {
      const featureIou = iou(left.featureBox, right.featureBox);
      const mustIncludeIou = iou(left.mustIncludeBox, right.mustIncludeBox);
      return {
        reviewKey: left.reviewKey,
        candidateAgreement: left.candidateId === right.candidateId,
        framingAgreement: left.framingMode === right.framingMode,
        featureLabelAgreement: left.featureLabel.trim().toLocaleLowerCase("zh-CN") === right.featureLabel.trim().toLocaleLowerCase("zh-CN"),
        featureIoU: Number(featureIou.toFixed(6)),
        mustIncludeIoU: Number(mustIncludeIou.toFixed(6)),
        highlightedForHuman:
          left.candidateId !== right.candidateId ||
          left.framingMode !== right.framingMode ||
          featureIou < 0.65 ||
          mustIncludeIou < 0.65 ||
          left.flags.some((flag) => flag !== "none") ||
          right.flags.some((flag) => flag !== "none"),
      };
    }
    const cropIou = iou(left.cropBox, right.cropBox);
    return {
      reviewKey: left.reviewKey,
      candidateAgreement: left.candidateId === right.candidateId,
      cropIoU: Number(cropIou.toFixed(6)),
      focalDistance: Number(Math.hypot(left.focalPoint[0] - right.focalPoint[0], left.focalPoint[1] - right.focalPoint[1]).toFixed(6)),
      highlightedForHuman:
        left.candidateId !== right.candidateId ||
        cropIou < 0.8 ||
        left.flags.some((flag) => flag !== "none") ||
        right.flags.some((flag) => flag !== "none"),
    };
  });
  const report = {
    schema: loaded.reportSchema,
    status: "candidate_proposed",
    productionReady: false,
    humanReviewRequired: true,
    generatedAt: new Date().toISOString(),
    batchId: loaded.manifest.batchId,
    sourceDigest: loaded.manifest.sourceDigest,
    manifestDigest: loaded.manifest.manifestDigest,
    selectionMode: loaded.selectionMode,
    controller: controllerEvidence(),
    probe,
    input: {
      manifestPath: path.relative(ROOT, loaded.manifestPath).replaceAll("\\", "/"),
      manifestSha256: sha256File(loaded.manifestPath),
      localizationViews: loaded.localizationViews || null,
      contactSheet: loaded.manifest.contactSheet,
      modelBatches: loaded.manifest.modelBatches,
      modelImageInputs: loaded.modelBatches.map((batch) => ({
        modelBatchId: batch.modelBatchId,
        layout: batch.imageLayout,
        images: batch.imageInputs.map((entry) => ({ role: entry.role, artifact: entry.artifact })),
      })),
      outputSchemaPath: path.relative(ROOT, loaded.outputSchemaPath).replaceAll("\\", "/"),
      outputSchemaSha256: sha256File(loaded.outputSchemaPath),
      eligibleReviewUnitCount: loaded.reviewItems.length,
      blockedReviewUnitCount: loaded.manifest.reviewItems.filter((item) => item.blocked).length,
      scheduling: {
        maxConcurrency: options.maxConcurrency,
        serviceTier: options.serviceTier,
        independentRunCount: jobs.length,
        batchBarrier: false,
      },
    },
    runs: [proposal, independentReview],
    comparisons,
    counts: {
      candidateAgreement: comparisons.filter((row) => row.candidateAgreement).length,
      highlightedForHuman: comparisons.filter((row) => row.highlightedForHuman).length,
    },
    gates: {
      separateProcessIds: true,
      distinctRolePromptDigests: true,
      modelBatchSizeAtMostFour: true,
      exactControllerClosure: true,
      candidateWhitelistClosed: true,
      semanticFeatureExplicit: loaded.selectionMode === "semantic_feature",
      sourceBlockersExcluded: true,
      orphanProcessGate: true,
      boundedGlobalConcurrency: true,
      currentCandidatesSeparatedFromHumanAtlas: loaded.modelBatches.every((batch) =>
        !loaded.manifest.humanPreferenceCalibration ||
        (batch.imageLayout === "selected_high_resolution_views_v1" && batch.imageInputs.length === batch.reviewItems.length) ||
        ([
          "separate_current_candidates_and_full_human_atlas_v1",
          "separate_current_candidates_and_retrieved_human_atlas_v2",
        ].includes(batch.imageLayout) && batch.imageInputs.length === 2)),
      compactHumanAtlasRetrievalBound: !loaded.manifest.humanPreferenceCalibration?.modelAtlas ||
        loaded.modelBatches.every((batch) => batch.imageLayout === "selected_high_resolution_views_v1") ||
        loaded.modelBatches.every((batch) =>
          batch.imageLayout === "separate_current_candidates_and_retrieved_human_atlas_v2" &&
          batch.imageInputs[1]?.artifact.sha256 === loaded.manifest.humanPreferenceCalibration.modelAtlas.sha256),
      selectedHighResolutionLocalizationBound: !loaded.localizationViews ||
        loaded.modelBatches.every((batch) =>
          batch.imageLayout === "selected_high_resolution_views_v1" &&
          batch.reviewItems.every((item) => item.lockedCandidateId && item.localizationView)),
      humanAtlasOmittedDuringPreciseLocalization: !loaded.localizationViews ||
        loaded.modelBatches.every((batch) => batch.imageInputs.every((entry) => entry.role.startsWith("selected_high_resolution_view:"))),
      humanArtAcceptance: false,
      productionWrites: false,
    },
  };
  report.reportDigest = sha256Bytes(stableStringify(report));
  writeExclusive(outputPath, `${JSON.stringify(report, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify({ status: report.status, reportPath: outputPath, reportDigest: report.reportDigest, counts: report.counts })}\n`);
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${JSON.stringify(publicError(error))}\n`);
    process.exitCode = 1;
  });
}

module.exports = { applyLocalizationViews, createPrompt, loadManifest, repairFeedbackFor, resolveModelImageInputs, validateResult };
