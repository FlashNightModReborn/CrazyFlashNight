#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const { loadManifest } = require("./run-visual-pilot");

const ROOT = path.resolve(__dirname, "..", "..");
const PORTRAIT_TMP = path.join(ROOT, "tmp", "portrait-pilot");
const RUN_CONTROLLER = path.join(__dirname, "run-visual-pilot.js");

function fail(message) {
  throw new reviewBuild.ReviewError(message);
}

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function relativePath(filePath) {
  return path.relative(ROOT, filePath).replaceAll("\\", "/");
}

function artifactRecord(filePath) {
  return {
    path: relativePath(filePath),
    bytes: fs.statSync(filePath).size,
    sha256: reviewBuild.sha256File(filePath),
  };
}

function parseArgs(argv) {
  const options = { manifest: null, output: null, batchId: null, hypothesis: null, minimumLong: null, minimumShort: null };
  const flags = new Map([
    ["--manifest", "manifest"],
    ["--output", "output"],
    ["--batch-id", "batchId"],
    ["--hypothesis", "hypothesis"],
    ["--minimum-long", "minimumLong"],
    ["--minimum-short", "minimumShort"],
  ]);
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (flags.has(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) fail(`${argument} 缺少值`);
      const field = flags.get(argument);
      options[field] = ["minimumLong", "minimumShort"].includes(field) ? Number(value) : value;
      index += 1;
    } else if (argument === "--help") {
      options.help = true;
    } else {
      fail(`未知参数：${argument}`);
    }
  }
  return options;
}

function resolveOutput(value) {
  const outputPath = path.resolve(ROOT, value);
  const relative = path.relative(PORTRAIT_TMP, outputPath);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    fail("output 必须位于 tmp/portrait-pilot 下");
  }
  if (path.basename(outputPath) !== "candidate-manifest.json") fail("output 文件名必须是 candidate-manifest.json");
  return outputPath;
}

function derive(options) {
  const loaded = loadManifest(options.manifest);
  const inputPath = loaded.manifestPath;
  const outputPath = resolveOutput(options.output);
  if (fs.existsSync(outputPath)) fail("输出 manifest 已存在，禁止覆盖");
  if (!/^[a-z0-9][a-z0-9._-]{7,127}$/i.test(options.batchId)) fail("batch-id 格式非法");
  if (options.hypothesis.trim().length < 12 || options.hypothesis.length > 500) fail("hypothesis 长度必须为 12–500");
  const overridesPresent = options.minimumLong !== null || options.minimumShort !== null;
  if (
    overridesPresent &&
    (!Number.isFinite(options.minimumLong) || !Number.isFinite(options.minimumShort) ||
      options.minimumShort < 0.2 || options.minimumLong > 0.9 || options.minimumShort > options.minimumLong)
  ) {
    fail("occupancy override 必须满足 0.2 <= short <= long <= 0.9");
  }

  const derived = structuredClone(loaded.manifest);
  delete derived.manifestDigest;
  const parent = {
    path: relativePath(inputPath),
    bytes: fs.statSync(inputPath).size,
    sha256: reviewBuild.sha256File(inputPath),
    manifestDigest: loaded.manifest.manifestDigest,
    sourceDigest: loaded.manifest.sourceDigest,
  };
  const controller = artifactRecord(RUN_CONTROLLER);
  const derivationController = artifactRecord(__filename);
  const sourceFiles = derived.sourceEnvelope.sourceFiles.map((record) =>
    record.path === controller.path ? controller : record);
  if (!sourceFiles.some((record) => record.path === controller.path && record.sha256 === controller.sha256)) {
    fail("父 manifest sourceFiles 没有 run-visual-pilot.js");
  }
  if (!sourceFiles.some((record) => record.path === derivationController.path)) {
    sourceFiles.push(derivationController);
  }
  derived.batchId = options.batchId;
  derived.createdAt = new Date().toISOString();
  derived.status = "prompt_experiment_ready";
  derived.productionReady = false;
  derived.sourceEnvelope.batchId = options.batchId;
  derived.sourceEnvelope.sourceFiles = sourceFiles;
  derived.sourceEnvelope.promptExperiment = {
    schema: "cf7.portrait-pilot-prompt-experiment.v1",
    parentManifest: parent,
    hypothesis: options.hypothesis.trim(),
    runController: controller,
    derivationController,
    candidatePixelsReusedWithoutChange: true,
    targetHumanGeometryTransmittedToModel: false,
    productionWrites: false,
    geometryGateOverride: overridesPresent ? {
      minimumRenderedFeatureLongAxisOccupancy: options.minimumLong,
      minimumRenderedFeatureShortAxisOccupancy: options.minimumShort,
      purpose: "structural_invalidity_only_human_alignment_scored_offline",
    } : null,
  };
  if (overridesPresent) {
    for (const config of Object.values(derived.featureContract.geometry.modes)) {
      config.minimumRenderedFeatureLongAxisOccupancy = options.minimumLong;
      config.minimumRenderedFeatureShortAxisOccupancy = options.minimumShort;
    }
  }
  derived.sourceDigest = sha256Bytes(reviewBuild.stableStringify(derived.sourceEnvelope));
  derived.campaign = {
    ...derived.campaign,
    promptExperiment: {
      parentManifestDigest: parent.manifestDigest,
      candidatePixelsReusedWithoutChange: true,
      targetHumanGeometryTransmittedToModel: false,
    },
  };
  derived.manifestDigest = sha256Bytes(reviewBuild.stableStringify(derived));
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(derived, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  loadManifest(outputPath);
  return { outputPath, manifest: derived };
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.manifest || !options.output || !options.batchId || !options.hypothesis) {
    process.stdout.write("用法：node tools/portrait-pilot/derive-prompt-experiment.js --manifest <parent> --output <tmp/portrait-pilot/.../candidate-manifest.json> --batch-id <id> --hypothesis <text> [--minimum-long <0.2..0.9> --minimum-short <0.2..long>]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const result = derive(options);
  process.stdout.write(`${JSON.stringify({ status: result.manifest.status, output: relativePath(result.outputPath), sourceDigest: result.manifest.sourceDigest, manifestDigest: result.manifest.manifestDigest })}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = { derive };
