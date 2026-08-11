#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { resolveModelImageInputs } = require("./run-visual-pilot");

const ROOT = path.resolve(__dirname, "..", "..");
const manifestPath = path.resolve(
  ROOT,
  process.argv[2] || "tmp/portrait-pilot/campaign-shard-r52-v9-feedback-fast6-20260806T115116Z/candidate-manifest.json",
);
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
if (!manifest.humanPreferenceCalibration || !Array.isArray(manifest.modelBatches)) {
  throw new Error("fixture manifest 没有人类偏好图谱或模型小批");
}

const rows = manifest.modelBatches.map((batch) => {
  const compositePath = path.resolve(ROOT, batch.contactSheet.path);
  const resolved = resolveModelImageInputs(manifest, batch, compositePath);
  const compact = Boolean(manifest.humanPreferenceCalibration.modelAtlas);
  const expectedLayout = compact
    ? "separate_current_candidates_and_retrieved_human_atlas_v2"
    : "separate_current_candidates_and_full_human_atlas_v1";
  const expectedRole = compact
    ? "retrieved_human_preferences_not_candidates"
    : "human_preferences_not_candidates";
  const expectedAtlas = compact
    ? manifest.humanPreferenceCalibration.modelAtlas
    : manifest.humanPreferenceCalibration.atlas;
  if (
    resolved.layout !== expectedLayout ||
    resolved.imageInputs.length !== 2 ||
    resolved.imageInputs[0].role !== "current_candidates" ||
    resolved.imageInputs[1].role !== expectedRole ||
    resolved.imageInputs[0].artifact.path.includes("with-feedback") ||
    resolved.imageInputs[1].artifact.sha256 !== expectedAtlas.sha256
  ) {
    throw new Error(`模型图像拆分不闭合：${batch.modelBatchId}`);
  }
  if (compact) {
    const retrieval = manifest.humanPreferenceCalibration.modelAtlasRetrieval;
    if (
      retrieval.fullAtlas.sha256 !== manifest.humanPreferenceCalibration.atlas.sha256 ||
      retrieval.modelAtlasPatchCount >= retrieval.fullAtlasPatchCount ||
      retrieval.gates.fullHumanEvidenceBound !== true ||
      retrieval.gates.fullAtlasNotTransmittedPerModelCall !== true
    ) {
      throw new Error(`紧凑图谱没有完整绑定或未降 patch：${batch.modelBatchId}`);
    }
  }
  const binding = manifest.humanPreferenceCalibration.contactSheets.find((entry) =>
    entry.composite.path === batch.contactSheet.path);
  if (!binding || binding.baseDimensions[1] >= binding.compositeDimensions[1]) {
    throw new Error(`当前候选图没有从纵长合成图中分离：${batch.modelBatchId}`);
  }
  return {
    modelBatchId: batch.modelBatchId,
    currentHeight: binding.baseDimensions[1],
    oldCompositeHeight: binding.compositeDimensions[1],
    retainedVerticalShare: Number((binding.baseDimensions[1] / binding.compositeDimensions[1]).toFixed(6)),
    preferenceLayout: expectedLayout,
    preferencePatches: compact
      ? manifest.humanPreferenceCalibration.modelAtlasRetrieval.modelAtlasPatchCount
      : null,
  };
});

process.stdout.write(`${JSON.stringify({ status: "model_image_separation_verified", rows })}\n`);
