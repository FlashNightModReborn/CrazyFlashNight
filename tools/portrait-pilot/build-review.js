#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..", "..");
const REVIEWER_SOURCE_PATHS = [
  path.join(ROOT, "tools", "portrait-pilot", "build-review.js"),
  path.join(ROOT, "tools", "portrait-pilot", "open-review.js"),
  path.join(ROOT, "launcher", "web", "modules", "portrait-pilot-review", "dev", "review.html"),
  path.join(ROOT, "launcher", "web", "modules", "portrait-pilot-review", "dev", "review.css"),
  path.join(ROOT, "launcher", "web", "modules", "portrait-pilot-review", "dev", "review.js"),
];

class ReviewError extends Error {}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stableValue(value[key])]));
  }
  return value;
}

function stableStringify(value) {
  return JSON.stringify(stableValue(value));
}

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function sha256File(filePath) {
  return sha256Bytes(fs.readFileSync(filePath));
}

function resolveRepoArtifact(record, label) {
  if (!record || typeof record.path !== "string" || typeof record.sha256 !== "string" || !Number.isInteger(record.bytes)) {
    throw new ReviewError(`${label} artifact 记录不闭合`);
  }
  const filePath = path.resolve(ROOT, record.path);
  const relative = path.relative(ROOT, filePath);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new ReviewError(`${label} artifact 越出仓库`);
  }
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    throw new ReviewError(`${label} artifact 缺失：${record.path}`);
  }
  const stat = fs.statSync(filePath);
  if (stat.size !== record.bytes || sha256File(filePath) !== record.sha256) {
    throw new ReviewError(`${label} artifact 字节闭包不匹配：${record.path}`);
  }
  return filePath;
}

function resolveExternalArtifact(record, label) {
  if (!record || typeof record.path !== "string" || typeof record.sha256 !== "string" || !Number.isInteger(record.bytes)) {
    throw new ReviewError(`${label} artifact 记录不闭合`);
  }
  if (!path.isAbsolute(record.path) || !fs.existsSync(record.path) || !fs.statSync(record.path).isFile()) {
    throw new ReviewError(`${label} 外部 artifact 缺失：${record.path}`);
  }
  const stat = fs.statSync(record.path);
  if (stat.size !== record.bytes || sha256File(record.path) !== record.sha256) {
    throw new ReviewError(`${label} 外部 artifact 字节闭包不匹配：${record.path}`);
  }
  return record.path;
}

function verifyRunArtifacts(run, label) {
  let count = 0;
  for (const field of ["stdout", "stderr", "commandRecord", "sourceSwf"]) {
    if (run?.[field]) {
      resolveRepoArtifact(run[field], `${label} ${field}`);
      count += 1;
    }
  }
  for (const record of run?.outputs || []) {
    resolveRepoArtifact(record, `${label} output`);
    count += 1;
  }
  return count;
}

function verifyDigestObject(value, digestField, label) {
  if (!value || typeof value !== "object" || typeof value[digestField] !== "string") {
    throw new ReviewError(`${label} 缺 ${digestField}`);
  }
  const copy = { ...value };
  delete copy[digestField];
  const computed = sha256Bytes(stableStringify(copy));
  if (computed !== value[digestField]) {
    throw new ReviewError(`${label} ${digestField} 不匹配`);
  }
}

function verifyCurrentSource(manifest) {
  const envelope = manifest.sourceEnvelope;
  if (!envelope || sha256Bytes(stableStringify(envelope)) !== manifest.sourceDigest) {
    throw new ReviewError("sourceEnvelope/sourceDigest 不匹配");
  }
  const records = [
    ...(envelope.sourceFiles || []),
    ...(envelope.ffdec?.files || []),
    ...(envelope.sourceSwfs || []),
  ];
  for (const record of records) resolveRepoArtifact(record, "current source");
  if (envelope.font?.path && envelope.font.path !== "Pillow.default") {
    const fontPath = path.resolve(envelope.font.path);
    if (!fs.existsSync(fontPath) || sha256File(fontPath) !== envelope.font.sha256) {
      throw new ReviewError("联系表字体已漂移");
    }
  }
  return records.length;
}

function verifyManifestArtifacts(manifest) {
  let count = 0;
  resolveRepoArtifact(manifest.contactSheet, "full contact sheet");
  count += 1;
  for (const batch of manifest.modelBatches || []) {
    resolveRepoArtifact(batch.contactSheet, `model batch ${batch.modelBatchId}`);
    count += 1;
  }
  for (const item of manifest.reviewItems || []) {
    if (item.oldReference) {
      resolveRepoArtifact(item.oldReference, `old reference ${item.reviewKey}`);
      count += 1;
    }
    for (const candidate of item.candidates || []) {
      resolveRepoArtifact(candidate.artifact, `candidate ${candidate.candidateId}`);
      count += 1;
      if (candidate.vectorArtifact) {
        resolveRepoArtifact(candidate.vectorArtifact, `vector candidate ${candidate.candidateId}`);
        count += 1;
      }
    }
  }
  return count;
}

function verifyRenderArtifacts(renderReport) {
  let count = 0;
  const controllerSource = renderReport.renderer?.controllerSource;
  if (renderReport.schema === "cf7.portrait-pilot-render-report.v4") {
    if (!controllerSource) {
      throw new ReviewError("v4 render report 缺 Python renderer source closure");
    }
    resolveRepoArtifact(controllerSource, "Python renderer controller source");
    count += 1;
  } else if (controllerSource) {
    resolveRepoArtifact(controllerSource, "Python renderer controller source");
    count += 1;
  }
  const adapter = renderReport.selectedFrameAdapter;
  if (adapter) {
    resolveExternalArtifact(adapter.java, "selected frame java");
    resolveExternalArtifact(adapter.javac, "selected frame javac");
    resolveRepoArtifact(adapter.source, "selected frame adapter source");
    count += 3;
    for (const record of [...(adapter.classes || []), ...(adapter.classpathFiles || [])]) {
      resolveRepoArtifact(record, "selected frame adapter closure");
      count += 1;
    }
    count += verifyRunArtifacts(adapter.compileRun, "selected frame adapter compile");
  }
  for (const run of renderReport.highResolutionRuns || []) {
    count += verifyRunArtifacts(run, `selected frame run ${run.groupId || run.characterId}`);
  }
  for (const row of renderReport.rows || []) {
    resolveRepoArtifact(row.sourceCandidate, `render source ${row.role}/${row.reviewKey}`);
    resolveRepoArtifact(row.master, `render master ${row.role}/${row.reviewKey}`);
    resolveRepoArtifact(row.webp80Lossless, `render webp ${row.role}/${row.reviewKey}`);
    count += 3;
    if (row.sourceVector) {
      resolveRepoArtifact(row.sourceVector, `render vector source ${row.role}/${row.reviewKey}`);
      count += 1;
    }
    if (row.vectorSupersample) {
      resolveRepoArtifact(row.vectorSupersample, `render vector supersample ${row.role}/${row.reviewKey}`);
      count += 1;
    }
    for (const [field, label] of [
      ["sourceGeometrySvg", "geometry SVG"],
      ["sourceHighResolution", "selected high-resolution frame"],
      ["sourceSupersample", "source supersample"],
    ]) {
      if (row[field]) {
        resolveRepoArtifact(row[field], `render ${label} ${row.role}/${row.reviewKey}`);
        count += 1;
      }
    }
    for (const [size, record] of Object.entries(row.previews || {})) {
      resolveRepoArtifact(record, `render preview ${size} ${row.role}/${row.reviewKey}`);
      count += 1;
    }
  }
  return count;
}

function reviewerEvidence() {
  const files = REVIEWER_SOURCE_PATHS.map((filePath) => {
    if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
      throw new ReviewError(`reviewer source 缺失：${path.relative(ROOT, filePath)}`);
    }
    return {
      path: path.relative(ROOT, filePath).replaceAll("\\", "/"),
      bytes: fs.statSync(filePath).size,
      sha256: sha256File(filePath),
    };
  });
  return {
    version: "portrait-pilot-reviewer-v1",
    files,
    sourceClosureDigest: sha256Bytes(stableStringify(files)),
  };
}

function computeReviewDigest(dataset) {
  const envelope = {
    schema: dataset.schema,
    sourceDigest: dataset.sourceDigest,
    manifestDigest: dataset.manifestDigest,
    modelReportDigest: dataset.modelReportDigest,
    renderDigest: dataset.renderDigest,
    decisionSchema: dataset.decisionSchema,
    reviewer: dataset.reviewer,
    statuses: dataset.statuses,
    items: dataset.items,
  };
  if (dataset.schema === "cf7.portrait-pilot-review-data.v2") {
    envelope.decisionSemantics = dataset.decisionSemantics;
    envelope.counts = dataset.counts;
  }
  return sha256Bytes(stableStringify(envelope));
}

function verifyReviewDataset(dataset) {
  if (
    !["cf7.portrait-pilot-review-data.v1", "cf7.portrait-pilot-review-data.v2"].includes(dataset.schema) ||
    dataset.partial !== false
  ) {
    throw new ReviewError("review data schema 或 partial 状态非法");
  }
  if (computeReviewDigest(dataset) !== dataset.reviewDigest) {
    throw new ReviewError("reviewDigest 不匹配");
  }
  if (
    !Array.isArray(dataset.items) ||
    dataset.items.length < 1 ||
    !dataset.counts ||
    dataset.counts.total !== dataset.items.length ||
    dataset.counts.eligible + dataset.counts.blocked !== dataset.items.length ||
    dataset.items.filter((item) => !item.blocked).length !== dataset.counts.eligible ||
    dataset.items.filter((item) => item.blocked).length !== dataset.counts.blocked
  ) {
    throw new ReviewError("review data 行数或 counts 不闭合");
  }
  if (
    dataset.schema === "cf7.portrait-pilot-review-data.v2" &&
    (
      dataset.decisionSemantics?.passAcceptsRole !== "proposal" ||
      dataset.decisionSemantics?.independentReviewIsAuditOnly !== true
    )
  ) {
    throw new ReviewError("v2 review data 决策语义不闭合");
  }
  const keys = new Set(dataset.items.map((item) => item.reviewKey));
  if (keys.size !== dataset.items.length) throw new ReviewError("review data 含重复 reviewKey");
  if (
    !dataset.reviewer ||
    !Array.isArray(dataset.reviewer.files) ||
    dataset.reviewer.sourceClosureDigest !== sha256Bytes(stableStringify(dataset.reviewer.files))
  ) {
    throw new ReviewError("reviewer source closure 不闭合");
  }
  for (const record of dataset.reviewer.files) resolveRepoArtifact(record, "reviewer source");
  resolveRepoArtifact(dataset.fullContactSheet, "review full contact sheet");
  let count = 1 + dataset.reviewer.files.length;
  for (const item of dataset.items) {
    if (item.oldReference) {
      resolveRepoArtifact(item.oldReference, `review old reference ${item.reviewKey}`);
      count += 1;
    }
    for (const candidate of item.candidates || []) {
      resolveRepoArtifact(candidate.artifact, `review candidate ${candidate.candidateId}`);
      count += 1;
      if (candidate.vectorArtifact) {
        resolveRepoArtifact(candidate.vectorArtifact, `review vector candidate ${candidate.candidateId}`);
        count += 1;
      }
    }
    for (const proposal of Object.values(item.proposals || {})) {
      resolveRepoArtifact(proposal.master, `review master ${item.reviewKey}`);
      resolveRepoArtifact(proposal.sourceCandidate, `review selected source ${item.reviewKey}`);
      resolveRepoArtifact(proposal.webp80Lossless, `review webp ${item.reviewKey}`);
      count += 3;
      if (proposal.sourceVector) {
        resolveRepoArtifact(proposal.sourceVector, `review vector source ${item.reviewKey}`);
        count += 1;
      }
      if (proposal.vectorSupersample) {
        resolveRepoArtifact(proposal.vectorSupersample, `review vector supersample ${item.reviewKey}`);
        count += 1;
      }
      for (const [field, label] of [
        ["sourceGeometrySvg", "geometry SVG"],
        ["sourceHighResolution", "selected high-resolution frame"],
        ["sourceSupersample", "source supersample"],
      ]) {
        if (proposal[field]) {
          resolveRepoArtifact(proposal[field], `review ${label} ${item.reviewKey}`);
          count += 1;
        }
      }
      for (const record of Object.values(proposal.previews || {})) {
        resolveRepoArtifact(record, `review preview ${item.reviewKey}`);
        count += 1;
      }
    }
  }
  return count;
}

function parseArgs(argv) {
  const options = { batch: null, check: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--batch") {
      options.batch = argv[index + 1];
      index += 1;
    } else if (argument === "--check") {
      options.check = true;
    } else if (argument === "--help") {
      options.help = true;
    } else {
      throw new ReviewError(`未知参数：${argument}`);
    }
  }
  return options;
}

function loadBatch(batchPath) {
  const batchRoot = path.resolve(ROOT, batchPath);
  const relative = path.relative(path.join(ROOT, "tmp", "portrait-pilot"), batchRoot);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new ReviewError("batch 必须位于 tmp/portrait-pilot");
  }
  const read = (name) => {
    const filePath = path.join(batchRoot, name);
    if (!fs.existsSync(filePath)) throw new ReviewError(`批次缺文件：${name}`);
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  };
  const manifest = read("candidate-manifest.json");
  const modelReport = read("model-report.json");
  const renderReport = read("render-report.json");
  verifyDigestObject(manifest, "manifestDigest", "candidate manifest");
  verifyDigestObject(modelReport, "reportDigest", "model report");
  verifyDigestObject(renderReport, "renderDigest", "render report");
  if (
    modelReport.sourceDigest !== manifest.sourceDigest ||
    modelReport.manifestDigest !== manifest.manifestDigest ||
    renderReport.sourceDigest !== manifest.sourceDigest ||
    renderReport.manifestDigest !== manifest.manifestDigest ||
    renderReport.modelReportDigest !== modelReport.reportDigest
  ) {
    throw new ReviewError("manifest/model/render 跨层 digest 不闭合");
  }
  let vectorReport = null;
  if (renderReport.vectorRenderReportDigest) {
    vectorReport = read("vector-render-report.json");
    verifyDigestObject(vectorReport, "reportDigest", "vector render report");
    if (
      vectorReport.reportDigest !== renderReport.vectorRenderReportDigest ||
      vectorReport.sourceDigest !== manifest.sourceDigest ||
      vectorReport.modelReportDigest !== modelReport.reportDigest
    ) {
      throw new ReviewError("vector report 与 manifest/model/render 摘要不闭合");
    }
  }
  return { batchRoot, manifest, modelReport, renderReport, vectorReport };
}

function buildDataset(loaded) {
  const { manifest, modelReport, renderReport } = loaded;
  const entities = new Map(manifest.entities.map((entity) => [entity.entityCode, entity]));
  const renderRows = new Map(renderReport.rows.map((row) => [`${row.role}:${row.reviewKey}`, row]));
  const comparisons = new Map(modelReport.comparisons.map((row) => [row.reviewKey, row]));
  const statuses = [
    { value: "pass", label: "通过（采用 Luna A）" },
    { value: "adjustment", label: "调整裁切" },
    { value: "wrong_pose", label: "姿态不对" },
    { value: "wrong_subject", label: "主体不对" },
    { value: "source", label: "来源问题" },
    { value: "variant_mismatch", label: "变体不符" },
  ];
  const items = manifest.reviewItems.map((item) => {
    const entity = entities.get(item.entityCode);
    const comparison = item.blocked ? null : comparisons.get(item.reviewKey);
    const proposals = {};
    const risks = [];
    if (item.blocked) {
      risks.push(`source_${item.sourceClassification}`);
    } else {
      for (const role of ["proposal", "independent_review"]) {
        const row = renderRows.get(`${role}:${item.reviewKey}`);
        if (!row) throw new ReviewError(`缺确定性渲染：${role}/${item.reviewKey}`);
        proposals[role] = row;
        for (const flag of row.flags || []) {
          if (flag !== "none") risks.push(`${role}:${flag}`);
        }
      }
      if (!comparison) throw new ReviewError(`缺 A/B comparison：${item.reviewKey}`);
      if (!comparison.candidateAgreement) risks.push("ab_candidate_disagreement");
      if (typeof comparison.cropIoU === "number" && comparison.cropIoU < 0.8) risks.push("ab_crop_disagreement");
      if (typeof comparison.featureIoU === "number" && comparison.featureIoU < 0.65) risks.push("ab_feature_disagreement");
      if (typeof comparison.mustIncludeIoU === "number" && comparison.mustIncludeIoU < 0.65) risks.push("ab_context_disagreement");
      if (comparison.framingAgreement === false) risks.push("ab_framing_disagreement");
    }
    if (item.variantResolution === "timeline_visual_proposal_human_verified") {
      risks.push("variant_human_confirmation_required");
    }
    return {
      reviewCode: item.reviewCode,
      reviewKey: item.reviewKey,
      portraitRef: item.portraitRef,
      variantKey: item.variantKey,
      variantResolution: item.variantResolution,
      category: item.category,
      notes: entity.notes,
      humanFeedback: item.humanFeedback || null,
      intentPolicy: item.intentPolicy || null,
      blocked: item.blocked,
      blockReason: item.blockReason,
      sourceClassification: item.sourceClassification,
      sources: entity.sources,
      consumers: entity.consumers,
      renderStrategy: entity.renderStrategy || null,
      oldReference: item.oldReference,
      candidates: item.candidates,
      proposals,
      comparison,
      risks: [...new Set(risks)].sort(),
      allowedStatuses: item.blocked ? ["source"] : statuses.map((status) => status.value),
    };
  });
  const dataset = {
    schema: "cf7.portrait-pilot-review-data.v2",
    partial: false,
    productionReady: false,
    generatedAt: new Date().toISOString(),
    batchId: manifest.batchId,
    sourceDigest: manifest.sourceDigest,
    manifestDigest: manifest.manifestDigest,
    modelReportDigest: modelReport.reportDigest,
    renderDigest: renderReport.renderDigest,
    decisionSchema: "cf7.portrait-pilot-review-decisions.v1",
    decisionSemantics: {
      passAcceptsRole: "proposal",
      independentReviewIsAuditOnly: true,
    },
    reviewer: reviewerEvidence(),
    statuses,
    counts: {
      total: items.length,
      eligible: items.filter((item) => !item.blocked).length,
      blocked: items.filter((item) => item.blocked).length,
      riskRows: items.filter((item) => item.risks.length > 0).length,
    },
    fullContactSheet: manifest.contactSheet,
    items,
    gates: {
      sourceBlockersCannotPass: true,
      decisionsMustCoverEveryRow: true,
      nonPassNotesRequired: true,
      staleDigestRejected: true,
      productionWrites: false,
    },
  };
  dataset.reviewDigest = computeReviewDigest(dataset);
  return dataset;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.batch) {
    process.stdout.write("用法：node tools/portrait-pilot/build-review.js --batch <tmp/portrait-pilot/...> [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const loaded = loadBatch(options.batch);
  const currentSourceCount = verifyCurrentSource(loaded.manifest);
  const manifestArtifactCount = verifyManifestArtifacts(loaded.manifest);
  const renderArtifactCount = verifyRenderArtifacts(loaded.renderReport);
  const outputPath = path.join(loaded.batchRoot, "review-data.json");
  if (options.check) {
    if (!fs.existsSync(outputPath)) throw new ReviewError("review-data.json 尚未构建");
    const dataset = JSON.parse(fs.readFileSync(outputPath, "utf8"));
    const reviewArtifactCount = verifyReviewDataset(dataset);
    process.stdout.write(`${JSON.stringify({
      status: "review_data_verified",
      sourceDigest: dataset.sourceDigest,
      reviewDigest: dataset.reviewDigest,
      rows: dataset.items.length,
      currentSourceCount,
      artifactCount: reviewArtifactCount,
    })}\n`);
    return;
  }
  if (fs.existsSync(outputPath)) throw new ReviewError("review-data.json 已存在，禁止覆盖");
  const dataset = buildDataset(loaded);
  fs.writeFileSync(outputPath, `${JSON.stringify(dataset, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  process.stdout.write(`${JSON.stringify({
    status: "review_data_built",
    path: path.relative(ROOT, outputPath).replaceAll("\\", "/"),
    sourceDigest: dataset.sourceDigest,
    reviewDigest: dataset.reviewDigest,
    rows: dataset.items.length,
    currentSourceCount,
    manifestArtifactCount,
    renderArtifactCount,
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

module.exports = {
  ReviewError,
  computeReviewDigest,
  loadBatch,
  resolveRepoArtifact,
  sha256File,
  stableStringify,
  verifyCurrentSource,
  verifyReviewDataset,
};
