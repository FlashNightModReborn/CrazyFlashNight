#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const guidanceBuild = require("./build-framing-guidance");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");

function readJson(filePath, label) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    throw new reviewBuild.ReviewError(`${label} 缺失：${filePath}`);
  }
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    throw new reviewBuild.ReviewError(`${label} 不是合法 JSON：${error.message}`);
  }
}

function ensurePilotChild(target, label, allowExisting = false) {
  const resolved = path.resolve(ROOT, target);
  const relative = path.relative(PILOT_ROOT, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new reviewBuild.ReviewError(`${label} 必须位于 tmp/portrait-pilot 下`);
  }
  if (!allowExisting && fs.existsSync(resolved)) {
    throw new reviewBuild.ReviewError(`${label} 已存在，禁止覆盖：${resolved}`);
  }
  return resolved;
}

function artifact(filePath) {
  const resolved = path.resolve(filePath);
  const relative = path.relative(ROOT, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative) || !fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    throw new reviewBuild.ReviewError(`artifact 越出仓库或缺失：${filePath}`);
  }
  return {
    path: relative.replaceAll("\\", "/"),
    bytes: fs.statSync(resolved).size,
    sha256: reviewBuild.sha256File(resolved),
  };
}

function parseInteger(value, label, minimum, maximum) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new reviewBuild.ReviewError(`${label} 必须位于 ${minimum}..${maximum}`);
  }
  return parsed;
}

function parseArgs(argv) {
  const options = {
    source: null,
    output: null,
    batchId: null,
    chunkIndex: null,
    chunkSize: 6,
    excludedReviewKeys: [],
    check: false,
    help: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--source", "--output", "--batch-id", "--chunk-index", "--chunk-size", "--exclude-review-key"].includes(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new reviewBuild.ReviewError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--source") options.source = value;
      else if (argument === "--output") options.output = value;
      else if (argument === "--batch-id") options.batchId = value;
      else if (argument === "--chunk-index") options.chunkIndex = parseInteger(value, "chunk-index", 1, 9999);
      else if (argument === "--chunk-size") options.chunkSize = parseInteger(value, "chunk-size", 1, 6);
      else options.excludedReviewKeys.push(value);
    } else if (argument === "--check") options.check = true;
    else if (argument === "--help") options.help = true;
    else throw new reviewBuild.ReviewError(`未知参数：${argument}`);
  }
  return options;
}

function reviewerEvidence(sourceReviewer) {
  const filesByPath = new Map(sourceReviewer.files.map((record) => [record.path, record]));
  const controller = artifact(__filename);
  filesByPath.set(controller.path, controller);
  const files = [...filesByPath.values()];
  return {
    files,
    sourceClosureDigest: require("node:crypto")
      .createHash("sha256")
      .update(reviewBuild.stableStringify(files))
      .digest("hex")
      .toUpperCase(),
  };
}

function buildPartition(source, sourcePath, options) {
  guidanceBuild.verifyGuidanceDataset(source);
  const sourceKeys = source.items.map((item) => item.reviewKey);
  const sourceKeySet = new Set(sourceKeys);
  const excluded = new Set(options.excludedReviewKeys);
  if (excluded.size !== options.excludedReviewKeys.length) throw new reviewBuild.ReviewError("exclude-review-key 重复");
  for (const reviewKey of excluded) {
    if (!sourceKeySet.has(reviewKey)) throw new reviewBuild.ReviewError(`排除的 reviewKey 不在来源 guidance：${reviewKey}`);
  }
  const partitionable = source.items.filter((item) => !excluded.has(item.reviewKey));
  if (partitionable.length < 1) throw new reviewBuild.ReviewError("排除后没有可框选行");
  const chunkCount = Math.ceil(partitionable.length / options.chunkSize);
  if (options.chunkIndex > chunkCount) throw new reviewBuild.ReviewError(`chunk-index 超出 1..${chunkCount}`);
  const start = (options.chunkIndex - 1) * options.chunkSize;
  const items = partitionable.slice(start, start + options.chunkSize);
  const sourceRecord = artifact(sourcePath);
  const dataset = {
    ...source,
    generatedAt: new Date().toISOString(),
    batchId: options.batchId,
    parent: {
      ...source.parent,
      files: {
        ...source.parent.files,
        partitionSourceGuidanceData: sourceRecord,
      },
      guidancePartition: {
        schema: "cf7.portrait-pilot-guidance-partition.v1",
        sourceBatchId: source.batchId,
        sourceGuidanceDigest: source.guidanceDigest,
        totalAdjustmentRows: source.items.length,
        partitionableRows: partitionable.length,
        excludedReviewKeys: [...excluded],
        excludedRoute: "non_crop_adjustment",
        chunkSize: options.chunkSize,
        chunkIndex: options.chunkIndex,
        chunkCount,
        reviewKeys: items.map((item) => item.reviewKey),
      },
    },
    reviewer: reviewerEvidence(source.reviewer),
    items,
    gates: {
      ...source.gates,
      parentAdjustmentPartitionBound: true,
      allParentAdjustmentRowsInThisChunk: items.length === source.items.length,
      maximumHumanRevisionRows: 6,
    },
  };
  delete dataset.guidanceDigest;
  dataset.guidanceDigest = guidanceBuild.computeGuidanceDigest(dataset);
  return dataset;
}

function verifyPartition(dataset) {
  const artifactCount = guidanceBuild.verifyGuidanceDataset(dataset);
  const partition = dataset.parent?.guidancePartition;
  if (partition?.schema !== "cf7.portrait-pilot-guidance-partition.v1") {
    throw new reviewBuild.ReviewError("guidance partition schema 缺失");
  }
  if (
    !Number.isInteger(partition.chunkSize) || partition.chunkSize < 1 || partition.chunkSize > 6 ||
    !Number.isInteger(partition.chunkIndex) || !Number.isInteger(partition.chunkCount) ||
    partition.chunkIndex < 1 || partition.chunkIndex > partition.chunkCount ||
    dataset.items.length < 1 || dataset.items.length > partition.chunkSize || dataset.items.length > 6
  ) throw new reviewBuild.ReviewError("guidance partition 分片尺寸非法");
  const itemKeys = dataset.items.map((item) => item.reviewKey);
  if (reviewBuild.stableStringify(itemKeys) !== reviewBuild.stableStringify(partition.reviewKeys)) {
    throw new reviewBuild.ReviewError("guidance partition reviewKeys 与 items 不一致");
  }
  const sourcePath = reviewBuild.resolveRepoArtifact(dataset.parent.files.partitionSourceGuidanceData, "partition source guidance");
  const source = readJson(sourcePath, "partition source guidance");
  guidanceBuild.verifyGuidanceDataset(source);
  if (source.batchId !== partition.sourceBatchId || source.guidanceDigest !== partition.sourceGuidanceDigest) {
    throw new reviewBuild.ReviewError("guidance partition 与来源 guidance 不一致");
  }
  if (source.items.length !== partition.totalAdjustmentRows) throw new reviewBuild.ReviewError("guidance partition 总行数漂移");
  const excluded = new Set(partition.excludedReviewKeys || []);
  const partitionable = source.items.filter((item) => !excluded.has(item.reviewKey));
  if (partitionable.length !== partition.partitionableRows) throw new reviewBuild.ReviewError("guidance partition 可框选行数漂移");
  const expected = partitionable.slice((partition.chunkIndex - 1) * partition.chunkSize, partition.chunkIndex * partition.chunkSize).map((item) => item.reviewKey);
  if (reviewBuild.stableStringify(expected) !== reviewBuild.stableStringify(itemKeys)) {
    throw new reviewBuild.ReviewError("guidance partition 不是确定性连续分片");
  }
  return artifactCount;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.output || !options.batchId || !options.chunkIndex || (!options.source && !options.check)) {
    process.stdout.write("用法：node tools/portrait-pilot/partition-framing-guidance.js --source <full framing batch> --output <fresh chunk> --batch-id <ascii id> --chunk-index <1..n> [--chunk-size <1..6>] [--exclude-review-key <key>] [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(options.batchId)) {
    throw new reviewBuild.ReviewError("batch id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符");
  }
  const outputRoot = ensurePilotChild(options.output, "输出目录", options.check);
  const outputPath = path.join(outputRoot, "framing-guidance-data.json");
  if (options.check) {
    const dataset = readJson(outputPath, "framing guidance partition");
    if (dataset.batchId !== options.batchId) throw new reviewBuild.ReviewError("check batch-id 与数据不一致");
    const artifactCount = verifyPartition(dataset);
    process.stdout.write(`${JSON.stringify({ status: "framing_guidance_partition_verified", guidanceDigest: dataset.guidanceDigest, rows: dataset.items.length, chunk: dataset.parent.guidancePartition, artifactCount })}\n`);
    return;
  }
  const sourceRoot = ensurePilotChild(options.source, "来源 guidance batch", true);
  const sourcePath = path.join(sourceRoot, "framing-guidance-data.json");
  const source = readJson(sourcePath, "来源 framing guidance data");
  const dataset = buildPartition(source, sourcePath, options);
  fs.mkdirSync(outputRoot, { recursive: false });
  fs.writeFileSync(outputPath, `${JSON.stringify(dataset, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  const artifactCount = verifyPartition(dataset);
  process.stdout.write(`${JSON.stringify({ status: "framing_guidance_partition_built", path: path.relative(ROOT, outputPath).replaceAll("\\", "/"), guidanceDigest: dataset.guidanceDigest, rows: dataset.items.length, chunk: dataset.parent.guidancePartition, artifactCount })}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = { buildPartition, verifyPartition };
