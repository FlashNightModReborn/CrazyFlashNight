#!/usr/bin/env node

import path from "node:path";
import fs from "node:fs";
import { parseArgs } from "node:util";
import { execFileSync } from "node:child_process";
import {
  loadConfig, withSourceOverride, PackerEngine, collect, filterFiles,
  diffFilterResults, getModifiedPathsBetweenTags, resolveOutputDir, formatSize,
  OutputDirNotOwnedError
} from "@cf7-packer/core";
import type { PackerLogEvent } from "@cf7-packer/core";

const VERSION = "0.1.0";

const { values: flags, positionals } = parseArgs({
  args: process.argv.slice(2),
  options: {
    config: { type: "string" },
    tag: { type: "string" },
    output: { type: "string" },
    base: { type: "string" },
    target: { type: "string" },
    "dry-run": { type: "boolean", default: false },
    "force-clean": { type: "boolean", default: false },
    all: { type: "boolean", default: false },
    version: { type: "boolean", short: "V", default: false },
    help: { type: "boolean", short: "h", default: false }
  },
  allowPositionals: true,
  strict: true
});

const command = positionals[0] ?? (flags.version ? "--version" : flags.help ? "help" : "help");

function findDefaultConfig(): string {
  let dir = path.resolve(import.meta.dirname, "../../..");
  for (let i = 0; i < 5; i++) {
    const candidate = path.join(dir, "pack.config.yaml");
    if (fs.existsSync(candidate)) return candidate;
    dir = path.dirname(dir);
  }
  throw new Error("找不到 pack.config.yaml，请用 --config 指定");
}

function formatLog(event: PackerLogEvent): string {
  const prefix = event.level === "error" ? "[ERROR]" : event.level === "warn" ? "[WARN]" : "[INFO]";
  return `${prefix} ${event.layer}: ${event.message}`;
}

async function runPack(): Promise<void> {
  const configPath = flags.config ?? findDefaultConfig();
  const dryRun = flags["dry-run"]!;
  const tag = flags.tag;
  const outputDir = flags.output;
  const forceClean = flags["force-clean"]!;

  const config = withSourceOverride(loadConfig(configPath), tag ? { tag } : undefined);

  const resolvedOutput = outputDir
    ? resolveOutputDir(config, configPath, outputDir)
    : resolveOutputDir(config, configPath);

  const engine = new PackerEngine(config);

  engine.on("log", (event) => {
    console.log(formatLog(event));
  });

  engine.on("progress", (event) => {
    if (event.phase === "pack" && event.total > 0) {
      process.stdout.write(`\r  进度: ${event.current}/${event.total}`);
    }
  });

  process.on("SIGINT", () => {
    console.log("\n正在取消...");
    engine.cancel();
  });

  let result;
  try {
    result = await engine.run({
      dryRun,
      outputDir: resolvedOutput,
      clean: config.output.clean,
      forceClean
    });
  } catch (err) {
    if (err instanceof OutputDirNotOwnedError) {
      console.error(`\n[X] ${err.message}`);
      console.error("    使用 --force-clean 可跳过此检查。");
      process.exitCode = 1;
      return;
    }
    throw err;
  }

  if (result.mode !== "dry-run") {
    console.log("");
  }

  console.log(`\n=== ${dryRun ? "预览" : "打包"}结果 ===`);
  console.log(`模式: ${result.mode}`);
  console.log(`文件数: ${result.copiedFiles}/${result.totalFiles}`);
  console.log(`总大小: ${formatSize(result.totalSize)}`);
  console.log(`耗时: ${result.duration}ms`);
  console.log(`输出: ${result.outputDir}`);

  if (result.cancelled) {
    console.log("状态: 已取消");
    process.exitCode = 130;
  }
  if (result.errors.length > 0) {
    console.log(`错误: ${result.errors.length} 个`);
    for (const err of result.errors.slice(0, 10)) {
      console.log(`  - ${err.path}: ${err.error}`);
    }
    process.exitCode = 1;
  }

  console.log("\n层级统计:");
  for (const layer of result.layers) {
    console.log(`  ${layer.name}: ${layer.includedCount} 文件`);
  }
}

function runValidateConfig(): void {
  const configPath = flags.config ?? findDefaultConfig();
  try {
    const config = loadConfig(configPath);
    console.log(`配置有效: ${configPath}`);
    console.log(`  名称: ${config.meta.name}`);
    console.log(`  模式: ${config.source.mode}`);
    console.log(`  层级: ${config.layers.map((l) => l.name).join(", ")}`);
    console.log(`  全局排除: ${config.globalExclude.length} 条`);
  } catch (err) {
    console.error(`配置无效: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }
}

function runListTags(): void {
  const configPath = flags.config ?? findDefaultConfig();
  const config = loadConfig(configPath);

  try {
    const output = execFileSync("git", ["tag", "-l"], {
      cwd: config.source.repoRoot,
      encoding: "utf8"
    });
    const tags = output.trim().split("\n").filter(Boolean);
    console.log(`Git 标签 (${tags.length} 个):`);
    for (const tag of tags) {
      console.log(`  ${tag}`);
    }
  } catch (err) {
    console.error(`获取标签失败: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }
}

async function runDiff(): Promise<void> {
  const configPath = flags.config ?? findDefaultConfig();
  const baseTag = flags.base;
  const targetTag = flags.target;
  const showAll = flags.all!;

  if (!baseTag || !targetTag) {
    console.error("diff 命令需要 --base 和 --target 两个 tag");
    process.exit(1);
  }

  const config = loadConfig(configPath);

  console.log(`比较 [${baseTag}] vs [${targetTag}]...`);

  const baseConfig = withSourceOverride(config, { tag: baseTag });
  const targetConfig = withSourceOverride(config, { tag: targetTag });

  const [baseCollected, targetCollected] = await Promise.all([
    collect(baseConfig),
    collect(targetConfig)
  ]);

  const baseFiltered = filterFiles(baseCollected.files, baseConfig);
  const targetFiltered = filterFiles(targetCollected.files, targetConfig);

  let modifiedPaths: Set<string> | undefined;
  try {
    modifiedPaths = await getModifiedPathsBetweenTags(config.source.repoRoot, baseTag, targetTag);
  } catch {
    // 检测失败不阻塞
  }

  const diff = diffFilterResults(baseFiltered, targetFiltered, modifiedPaths);
  const limit = showAll ? Infinity : 50;

  console.log(`\n=== Diff: [${baseTag}] → [${targetTag}] ===`);
  console.log(`新增: ${diff.added.length} 文件`);
  console.log(`删除: ${diff.removed.length} 文件`);
  console.log(`修改: ${diff.modified.length} 文件`);
  console.log(`不变: ${diff.unchanged} 文件`);

  if (diff.added.length > 0 && diff.added.length <= limit) {
    console.log("\n新增文件:");
    for (const f of diff.added) console.log(`  + ${f}`);
  } else if (diff.added.length > limit) {
    console.log(`\n新增文件（显示前 ${limit} 个，使用 --all 查看全部）:`);
    for (const f of diff.added.slice(0, limit)) console.log(`  + ${f}`);
  }
  if (diff.removed.length > 0 && diff.removed.length <= limit) {
    console.log("\n删除文件:");
    for (const f of diff.removed) console.log(`  - ${f}`);
  } else if (diff.removed.length > limit) {
    console.log(`\n删除文件（显示前 ${limit} 个，使用 --all 查看全部）:`);
    for (const f of diff.removed.slice(0, limit)) console.log(`  - ${f}`);
  }
  if (diff.modified.length > 0 && diff.modified.length <= limit) {
    console.log("\n修改文件:");
    for (const f of diff.modified) console.log(`  ~ ${f}`);
  } else if (diff.modified.length > limit) {
    console.log(`\n修改文件（显示前 ${limit} 个，使用 --all 查看全部）:`);
    for (const f of diff.modified.slice(0, limit)) console.log(`  ~ ${f}`);
  }
}

function printHelp(): void {
  console.log(`cf7-packer v${VERSION} — CF7 发行打包工具

用法:
  cf7-packer pack [--dry-run] [--config path] [--output dir] [--tag tag] [--force-clean]
  cf7-packer diff --base <tag> --target <tag> [--config path] [--all]
  cf7-packer validate-config [--config path]
  cf7-packer list-tags [--config path]
  cf7-packer help

选项:
  --dry-run       只统计，不实际复制
  --config        指定 pack.config.yaml 路径
  --output        覆盖输出目录
  --tag           使用指定 git tag 的文件快照
  --force-clean   强制清理未标记的输出目录
  --all           显示全部 diff 文件（不截断）
  -V, --version   显示版本号
  -h, --help      显示帮助信息
`);
}

async function main(): Promise<void> {
  switch (command) {
    case "pack":
      await runPack();
      break;
    case "diff":
      await runDiff();
      break;
    case "validate-config":
      runValidateConfig();
      break;
    case "list-tags":
      runListTags();
      break;
    case "help":
    case "--help":
      printHelp();
      break;
    case "--version":
      console.log(`cf7-packer v${VERSION}`);
      break;
    default:
      console.error(`未知命令: ${command}`);
      printHelp();
      process.exit(1);
  }
}

void main();
