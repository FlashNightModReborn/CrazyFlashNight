"use strict";

// 生成/刷新已冻结 internal-subject 批次的「源码超越收条」。
//
// 背景：批次的历史记录（internal-subject-model-report.json 的 controller.files
// 与 internal-subject-review-data.json 的 reviewer.files）逐字节钉住了产生批次
// 时的控制器/审阅器源码。工具源码的后续正当漂移（进程清理修复、审阅页加固等）
// 会让 loadBatch / verifyReviewDataset 的字节闭包永不匹配。本工具不重写历史
// 批次，而是生成 internal-subject-source-supersession-v1.json，把「哪条历史
// 记录被哪个当前字节精确替代」逐条钉死并自摘要；验证端只接受收条内的精确
// 替代，其余漂移依旧 fail-closed。
//
// 用法：
//   node tools/portrait-pilot/build-internal-subject-source-supersession-v1.js \
//     --batch <tmp/portrait-pilot/...> [--add controller:tools/... --reason 文本] [--commit 文本]
// 不带 --add 时为刷新模式：按磁盘现状重算全部已有条目的 current*。
// 条目对应的源码一旦恢复历史字节（不再漂移），本工具拒绝继续携带该条目，
// 须用 --drop <layer:path> 移除，保持收条最小。

const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-internal-subject-review-v1");

const ROOT = path.resolve(__dirname, "..", "..");
const RECEIPT_SCHEMA = "cf7.internal-subject-source-supersession.v1";
const RECEIPT_NAME = "internal-subject-source-supersession-v1.json";

class SupersessionError extends Error {}

function parseArgs(argv) {
  const options = { add: [], drop: [] };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === "--batch") options.batch = argv[++index];
    else if (arg === "--add") options.add.push(argv[++index]);
    else if (arg === "--drop") options.drop.push(argv[++index]);
    else if (arg === "--reason") options.reason = argv[++index];
    else if (arg === "--commit") options.commit = argv[++index];
    else if (arg === "--help") options.help = true;
    else throw new SupersessionError(`未知参数：${arg}`);
  }
  return options;
}

function parseLayerPath(value, flag) {
  const match = /^(controller|reviewer):(.+)$/.exec(String(value || ""));
  if (!match) throw new SupersessionError(`${flag} 需要 <layer>:<repo 相对路径>，layer 为 controller|reviewer`);
  return { layer: match[1], path: match[2].replaceAll("\\", "/") };
}

function historicalRecords(batchRoot) {
  const reportPath = path.join(batchRoot, "internal-subject-model-report.json");
  const reviewPath = path.join(batchRoot, "internal-subject-review-data.json");
  if (!fs.existsSync(reportPath) || !fs.existsSync(reviewPath)) {
    throw new SupersessionError("批次缺 internal-subject-model-report.json 或 internal-subject-review-data.json");
  }
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  const dataset = JSON.parse(fs.readFileSync(reviewPath, "utf8"));
  const records = { controller: new Map(), reviewer: new Map() };
  for (const record of report.controller?.files || []) records.controller.set(record.path, record);
  for (const record of dataset.reviewer?.files || []) records.reviewer.set(record.path, record);
  return { records, batchId: report.batchId || dataset.batchId || "" };
}

function diskState(repoRelativePath) {
  const absolute = path.resolve(ROOT, repoRelativePath);
  const relative = path.relative(ROOT, absolute);
  if (relative.startsWith("..") || path.isAbsolute(relative)) throw new SupersessionError(`越出仓库：${repoRelativePath}`);
  if (!fs.existsSync(absolute) || !fs.statSync(absolute).isFile()) throw new SupersessionError(`源码缺失：${repoRelativePath}`);
  return { bytes: fs.statSync(absolute).size, sha256: reviewBuild.sha256File(absolute) };
}

function buildEntry(records, layer, repoPath, extra) {
  const record = records[layer].get(repoPath);
  if (!record) throw new SupersessionError(`${layer} 历史记录中不存在：${repoPath}`);
  const current = diskState(repoPath);
  if (current.sha256 === record.sha256 && current.bytes === record.bytes) {
    throw new SupersessionError(`${repoPath} 与历史记录一致，无需超越条目`);
  }
  return {
    layer,
    path: repoPath,
    supersededBytes: record.bytes,
    supersededSha256: record.sha256,
    currentBytes: current.bytes,
    currentSha256: current.sha256,
    ...extra,
  };
}

function loadExisting(receiptPath) {
  if (!fs.existsSync(receiptPath)) return [];
  const receipt = JSON.parse(fs.readFileSync(receiptPath, "utf8"));
  if (receipt?.schema !== RECEIPT_SCHEMA || receipt.status !== "source_supersession_recorded" || !Array.isArray(receipt.entries)) {
    throw new SupersessionError("既有收条 schema/status 不受支持，拒绝改写");
  }
  const copy = { ...receipt };
  delete copy.receiptDigest;
  if (reviewBuild.sha256Bytes(reviewBuild.stableStringify(copy)) !== receipt.receiptDigest) {
    throw new SupersessionError("既有收条 receiptDigest 漂移，拒绝改写");
  }
  return receipt.entries;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.batch) {
    process.stdout.write("用法：node tools/portrait-pilot/build-internal-subject-source-supersession-v1.js --batch <dir> [--add <layer:path> --reason 文本 [--commit 文本]] [--drop <layer:path>]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const batchRoot = path.resolve(ROOT, options.batch);
  const pilotRoot = path.join(ROOT, "tmp", "portrait-pilot");
  const relative = path.relative(pilotRoot, batchRoot);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new SupersessionError("batch 必须是 tmp/portrait-pilot 下的批次目录");
  }
  if (options.add.length && !options.reason) throw new SupersessionError("新增条目必须提供 --reason");
  const { records, batchId } = historicalRecords(batchRoot);
  const receiptPath = path.join(batchRoot, RECEIPT_NAME);
  const entries = loadExisting(receiptPath).map((entry) => ({ ...entry }));

  for (const value of options.drop) {
    const { layer, path: dropPath } = parseLayerPath(value, "--drop");
    const index = entries.findIndex((entry) => entry.layer === layer && entry.path === dropPath);
    if (index < 0) throw new SupersessionError(`收条中不存在待移除条目：${layer}:${dropPath}`);
    entries.splice(index, 1);
  }
  for (const value of options.add) {
    const { layer, path: addPath } = parseLayerPath(value, "--add");
    if (entries.some((entry) => entry.layer === layer && entry.path === addPath)) {
      throw new SupersessionError(`条目已存在，改用无 --add 的刷新模式：${layer}:${addPath}`);
    }
    entries.push(buildEntry(records, layer, addPath, {
      reason: options.reason,
      ...(options.commit ? { supersededByCommit: options.commit } : {}),
    }));
  }
  // 刷新模式：全部既有条目按磁盘现状重算 current*，并复核条目仍然必要。
  const refreshed = entries.map((entry) => {
    const current = diskState(entry.path);
    if (current.sha256 === entry.supersededSha256 && current.bytes === entry.supersededBytes) {
      throw new SupersessionError(`${entry.path} 已恢复历史字节，请用 --drop ${entry.layer}:${entry.path} 移除该条目`);
    }
    return { ...entry, currentBytes: current.bytes, currentSha256: current.sha256 };
  });

  const receipt = {
    schema: RECEIPT_SCHEMA,
    status: "source_supersession_recorded",
    generatedAt: new Date().toISOString(),
    batchId,
    entries: refreshed,
  };
  receipt.receiptDigest = reviewBuild.sha256Bytes(reviewBuild.stableStringify(receipt));
  const temporary = `${receiptPath}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(receipt, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  fs.renameSync(temporary, receiptPath);
  process.stdout.write(`${JSON.stringify({
    status: "source_supersession_written",
    receipt: path.relative(ROOT, receiptPath).replaceAll("\\", "/"),
    entries: refreshed.length,
    receiptDigest: receipt.receiptDigest,
  })}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error && error.stack ? error.stack : String(error)}\n`);
    process.exitCode = 1;
  }
}

module.exports = { buildEntry, parseLayerPath };
