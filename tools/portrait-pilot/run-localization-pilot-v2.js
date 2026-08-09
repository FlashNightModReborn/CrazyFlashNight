#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const Module = require("node:module");
const path = require("node:path");

const BASE_CONTROLLER = path.join(__dirname, "run-visual-pilot.js");
const ORIENTATION_SCHEMA = path.join(__dirname, "schemas", "feature-selection-orientation-v2.schema.json");
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

function transformedSource() {
  const bytes = fs.readFileSync(BASE_CONTROLLER);
  if (sha256(bytes) !== EXPECTED_BASE_SHA256) {
    throw new Error("基础视觉控制器字节已漂移；拒绝运行未经复核的方向定位变换");
  }
  if (!fs.existsSync(ORIENTATION_SCHEMA)) throw new Error("方向定位输出 schema 缺失");
  let source = bytes.toString("utf8");
  source = replaceExactly(
    source,
    'const FEATURE_SCHEMA_PATH = path.join(__dirname, "schemas", "feature-selection.schema.json");',
    'const FEATURE_SCHEMA_PATH = path.join(__dirname, "schemas", "feature-selection.schema.json");\n' +
      'const ORIENTATION_SCHEMA_PATH = path.join(__dirname, "schemas", "feature-selection-orientation-v2.schema.json");\n' +
      'const BASE_ORIENTATION_CONTROLLER_PATH = ' + JSON.stringify(BASE_CONTROLLER) + ';',
    "orientation constants",
  );
  source = replaceExactly(
    source,
    'const FEATURE_RESULT_SCHEMA = "cf7.portrait-pilot-feature-selection.v1";',
    'const FEATURE_RESULT_SCHEMA = "cf7.portrait-pilot-feature-selection-orientation.v2";',
    "orientation result schema",
  );
  source = replaceExactly(
    source,
    "    outputSchemaPath: feature ? FEATURE_SCHEMA_PATH : LEGACY_SCHEMA_PATH,",
    "    outputSchemaPath: feature ? ORIENTATION_SCHEMA_PATH : LEGACY_SCHEMA_PATH,",
    "orientation output schema path",
  );
  source = replaceExactly(
    source,
    "    __filename,\n    LEGACY_SCHEMA_PATH,\n    FEATURE_SCHEMA_PATH,",
    "    __filename,\n    BASE_ORIENTATION_CONTROLLER_PATH,\n    LEGACY_SCHEMA_PATH,\n    FEATURE_SCHEMA_PATH,\n    ORIENTATION_SCHEMA_PATH,",
    "orientation controller evidence",
  );
  source = replaceExactly(
    source,
    '    version: "portrait-pilot-p2-p3-feature-v9-two-stage-selection-localization",',
    '    version: "portrait-pilot-localization-v2-canonical-right-orientation",',
    "orientation controller version",
  );
  source = replaceExactly(
    source,
    '    "The feature must be the first visual focus and fill the avatar while retaining safety above it and toward its facing direction. Weak shoulders, weapon ends, tails, legs, and effects may touch or cross the crop edge.",',
    '    "The feature must be the first visual focus and fill the avatar while retaining safety above it and toward its facing direction. Weak shoulders, weapon ends, tails, legs, and effects may touch or cross the crop edge.",\n' +
      '    "Infer the current horizontal direction from visible anatomy, not filenames or canvas position. The accumulated human preference is canonical portrait-right: if a face, gaze, snout, beak, head-front, or directional body axis clearly points toward the viewer\\\'s left, return orientationAction=flip_x; if it already points right, return keep. A weapon alone does not override a visible face or gaze. For non-humanoids use the leading sensory/anatomical or movement axis. Symmetric, frontal, or genuinely directionless units stay keep.",\n' +
      '    "orientationReason must name the concrete visible landmark and current direction. orientationConfidence rates only the direction inference. The renderer applies flip_x after the original-space crop and before 512/80/48/32 outputs, so never mirror featureBox or mustIncludeBox coordinates yourself.",',
    "orientation prompt contract",
  );
  source = replaceExactly(
    source,
    '["reviewKey", "candidateId", "featureLabel", "framingMode", "featureBox", "mustIncludeBox", "confidence", "flags"],',
    '["reviewKey", "candidateId", "featureLabel", "framingMode", "featureBox", "mustIncludeBox", "orientationAction", "orientationReason", "orientationConfidence", "confidence", "flags"],',
    "orientation selection closure",
  );
  source = replaceExactly(
    source,
    "      validateRequiredRegions(selection, item);\n      validateFeatureOccupancy(selection, item, expected.manifest);",
    "      validateRequiredRegions(selection, item);\n" +
      "      validateFeatureOccupancy(selection, item, expected.manifest);\n" +
      "      if (![\"keep\", \"flip_x\"].includes(selection.orientationAction)) {\n" +
      "        fail(\"RESULT_VALUE_INVALID\", \"closure\", \"orientationAction 非法\", { reviewKey: selection.reviewKey });\n" +
      "      }\n" +
      "      if (typeof selection.orientationReason !== \"string\" || !selection.orientationReason.trim() || selection.orientationReason.length > 160) {\n" +
      "        fail(\"RESULT_VALUE_INVALID\", \"closure\", \"orientationReason 为空或过长\", { reviewKey: selection.reviewKey });\n" +
      "      }\n" +
      "      if (typeof selection.orientationConfidence !== \"number\" || !Number.isFinite(selection.orientationConfidence) || selection.orientationConfidence < 0 || selection.orientationConfidence > 1) {\n" +
      "        fail(\"RESULT_VALUE_INVALID\", \"closure\", \"orientationConfidence 越界\", { reviewKey: selection.reviewKey });\n" +
      "      }",
    "orientation result validation",
  );
  source = replaceExactly(
    source,
    "        featureLabelAgreement: left.featureLabel.trim().toLocaleLowerCase(\"zh-CN\") === right.featureLabel.trim().toLocaleLowerCase(\"zh-CN\"),\n        featureIoU:",
    "        featureLabelAgreement: left.featureLabel.trim().toLocaleLowerCase(\"zh-CN\") === right.featureLabel.trim().toLocaleLowerCase(\"zh-CN\"),\n        orientationAgreement: left.orientationAction === right.orientationAction,\n        featureIoU:",
    "orientation comparison field",
  );
  source = replaceExactly(
    source,
    "          left.framingMode !== right.framingMode ||\n          featureIou < 0.65 ||",
    "          left.framingMode !== right.framingMode ||\n          left.orientationAction !== right.orientationAction ||\n          featureIou < 0.65 ||",
    "orientation disagreement highlight",
  );
  source = replaceExactly(
    source,
    "      candidateAgreement: comparisons.filter((row) => row.candidateAgreement).length,\n      highlightedForHuman:",
    "      candidateAgreement: comparisons.filter((row) => row.candidateAgreement).length,\n      orientationAgreement: comparisons.filter((row) => row.orientationAgreement !== false).length,\n      proposedFlipX: proposal.result.selections.filter((row) => row.orientationAction === \"flip_x\").length,\n      independentFlipX: independentReview.result.selections.filter((row) => row.orientationAction === \"flip_x\").length,\n      highlightedForHuman:",
    "orientation report counts",
  );
  source = replaceExactly(
    source,
    "      humanArtAcceptance: false,",
    "      canonicalPortraitDirectionRight: true,\n" +
      "      modelOrientationDecisionClosed: loaded.selectionMode === \"semantic_feature\",\n" +
      "      cropCoordinatesRemainOriginalSpace: true,\n" +
      "      orientationAppliedAfterCropByVersionedRenderer: true,\n" +
      "      humanArtAcceptance: false,",
    "orientation report gates",
  );
  source = replaceExactly(
    source,
    "  const baseLoaded = loadManifest(options.manifest);\n  const loaded = options.localizationViews",
    "  const baseLoaded = loadManifest(options.manifest);\n" +
      "  if (!options.localizationViews || baseLoaded.selectionMode !== \"semantic_feature\") {\n" +
      "    fail(\"LOCALIZATION_ORIENTATION_REQUIRED\", \"arguments\", \"方向定位 v2 仅允许带 --localization-views 的特征定位阶段\");\n" +
      "  }\n" +
      "  const loaded = options.localizationViews",
    "orientation localization-only gate",
  );
  source = replaceExactly(source, "if (require.main === module) {", "if (true) {", "orientation entrypoint");
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
