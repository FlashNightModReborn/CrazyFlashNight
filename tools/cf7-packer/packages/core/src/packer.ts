import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import type { FilterResult, PackerOptions, PackResult, LayerSummary, PackConfig } from "./types.js";
import { OutputDirNotOwnedError } from "./types.js";
import { isPathInsideRoot } from "./path-utils.js";
import { getTagBlobInfo } from "./content-hash.js";
import { minifyByExtension } from "./minify.js";
import { applyEstimatedSizes } from "./summary.js";
import { estimateEtaMs } from "./format.js";

const OUTPUT_DIR_MARKER = ".cf7-packer-output";

/**
 * 校验输出目录安全性。此校验无论 forceClean 如何，一律执行，不可跳过。
 */
export function validateOutputDir(outputDir: string, repoRoot: string): void {
  const resolved = path.resolve(outputDir);
  const resolvedRepo = path.resolve(repoRoot);

  // 拒绝: 系统根目录
  const root = path.parse(resolved).root;
  if (resolved === root) {
    throw new Error(`输出目录不能是系统根目录: ${resolved}`);
  }

  // 拒绝: 用户主目录
  const home = path.resolve(os.homedir());
  if (resolved === home) {
    throw new Error(`输出目录不能是用户主目录: ${resolved}`);
  }

  // 拒绝: outputDir 等于 repoRoot
  if (resolved === resolvedRepo) {
    throw new Error(`输出目录不能等于仓库根目录: ${resolved}`);
  }

  // 拒绝: outputDir 是 repoRoot 的祖先（即 repoRoot 在 outputDir 内部）
  if (isPathInsideRoot(resolved, resolvedRepo)) {
    throw new Error(`输出目录不能包含仓库根目录: ${resolved}`);
  }
}

/**
 * 处理 clean 逻辑: 标记文件检查 + 清理 + 创建。
 * 仅在 !dryRun 时调用。
 */
function prepareOutputDir(resolvedOutputDir: string, clean: boolean, forceClean: boolean): void {
  if (clean && fs.existsSync(resolvedOutputDir)) {
    const markerPath = path.join(resolvedOutputDir, OUTPUT_DIR_MARKER);
    if (!fs.existsSync(markerPath) && !forceClean) {
      throw new OutputDirNotOwnedError(resolvedOutputDir);
    }
    fs.rmSync(resolvedOutputDir, { recursive: true, force: true });
  }
  fs.mkdirSync(resolvedOutputDir, { recursive: true });
  // 写入标记文件
  fs.writeFileSync(
    path.join(resolvedOutputDir, OUTPUT_DIR_MARKER),
    `created=${new Date().toISOString()}\n`,
    "utf8"
  );
}

/**
 * 执行打包：将 filter 结果中的 included 文件复制到输出目录。
 *
 * - dry-run 模式：只统计，不复制
 * - execute 模式：实际复制，每个文件前检查 signal.aborted
 */
export async function pack(
  filterResult: FilterResult,
  config: PackConfig,
  options: PackerOptions
): Promise<PackResult> {
  const startTime = Date.now();
  const { dryRun, outputDir, clean, forceClean, signal, onProgress } = options;
  const repoRoot = config.source.repoRoot;
  const isGitTag = config.source.mode === "git-tag";
  const tag = config.source.tag;

  const resolvedOutputDir = path.resolve(outputDir);
  const minify = config.output.minify;
  const minifyExts = new Set(minify?.enabled ? minify.extensions : []);

  // 安全校验（无论 dryRun/forceClean 均执行）
  validateOutputDir(resolvedOutputDir, repoRoot);

  if (!dryRun) {
    prepareOutputDir(resolvedOutputDir, clean, forceClean ?? false);
  }

  // git-tag 模式下预取文件大小（单次 git ls-tree -rl）
  let gitBlobSizes: Map<string, number> | undefined;
  if (isGitTag && tag) {
    try {
      const blobInfo = await getTagBlobInfo(repoRoot, tag, signal);
      gitBlobSizes = new Map<string, number>();
      for (const [p, info] of blobInfo) {
        gitBlobSizes.set(p, info.size);
      }
    } catch {
      // 获取失败不阻塞打包
    }
  }

  const errors: Array<{ path: string; error: string }> = [];
  let copiedFiles = 0;
  let totalSize = 0;
  let cancelled = false;
  const packedEntries = new Map<string, number>();
  const progressLabel = dryRun ? "预览打包内容" : "复制打包文件";
  let lastProgressEmitAt = 0;

  onProgress?.({
    phase: "pack",
    current: 0,
    total: filterResult.included.length,
    label: progressLabel,
    detail: `共 ${filterResult.included.length} 个文件`
  });

  for (const entry of filterResult.included) {
    if (signal?.aborted) {
      cancelled = true;
      break;
    }

    if (dryRun) {
      // dry-run: 统计文件大小
      if (isGitTag && gitBlobSizes) {
        const size = gitBlobSizes.get(entry.path);
        if (size !== undefined) {
          totalSize += size;
          packedEntries.set(entry.path, size);
        }
      } else if (!isGitTag) {
        try {
          const stat = fs.statSync(path.join(repoRoot, entry.path));
          totalSize += stat.size;
          packedEntries.set(entry.path, stat.size);
        } catch {
          // 文件不可读，跳过大小统计
        }
      }
      copiedFiles++;
      emitPackProgress(onProgress, progressLabel, startTime, copiedFiles, filterResult.included.length, entry.path, () => lastProgressEmitAt, (value) => {
        lastProgressEmitAt = value;
      });
      continue;
    }

    // 实际复制
    const destPath = path.join(resolvedOutputDir, entry.path);
    const destDir = path.dirname(destPath);

    try {
      fs.mkdirSync(destDir, { recursive: true });

      if (isGitTag && tag) {
        // 从 git tag 提取文件内容
        let content = await gitShowFile(repoRoot, tag, entry.path, signal);
        if (signal?.aborted) {
          cancelled = true;
          break;
        }
        const ext = path.extname(entry.path).toLowerCase();
        if (minifyExts.has(ext)) {
          const minified = minifyByExtension(content.toString("utf8"), ext);
          if (minified !== null) content = Buffer.from(minified, "utf8");
        }
        fs.writeFileSync(destPath, content);
        totalSize += content.length;
        packedEntries.set(entry.path, content.length);
      } else {
        const srcPath = path.join(repoRoot, entry.path);
        const ext = path.extname(entry.path).toLowerCase();
        const srcStat = fs.statSync(srcPath);
        if (minifyExts.has(ext)) {
          const raw = fs.readFileSync(srcPath, "utf8");
          const minified = minifyByExtension(raw, ext);
          if (minified !== null) {
            fs.writeFileSync(destPath, minified, "utf8");
            fs.chmodSync(destPath, srcStat.mode);
            totalSize += Buffer.byteLength(minified, "utf8");
            packedEntries.set(entry.path, Buffer.byteLength(minified, "utf8"));
          } else {
            fs.copyFileSync(srcPath, destPath);
            fs.chmodSync(destPath, srcStat.mode);
            totalSize += srcStat.size;
            packedEntries.set(entry.path, srcStat.size);
          }
        } else {
          fs.copyFileSync(srcPath, destPath);
          fs.chmodSync(destPath, srcStat.mode);
          totalSize += srcStat.size;
          packedEntries.set(entry.path, srcStat.size);
        }
      }
      copiedFiles++;
      emitPackProgress(onProgress, progressLabel, startTime, copiedFiles, filterResult.included.length, entry.path, () => lastProgressEmitAt, (value) => {
        lastProgressEmitAt = value;
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      errors.push({ path: entry.path, error: message });
    }
  }

  const layers: LayerSummary[] = applyEstimatedSizes(
    filterResult.layers.map((l) => ({ ...l })),
    filterResult.included.map((entry) => ({
      ...entry,
      size: packedEntries.get(entry.path)
    }))
  );

  return {
    mode: dryRun ? "dry-run" : "execute",
    cancelled,
    totalFiles: filterResult.included.length,
    copiedFiles,
    totalSize,
    layers,
    outputDir: resolvedOutputDir,
    duration: Date.now() - startTime,
    errors
  };
}

function gitShowFile(repoRoot: string, tag: string, filePath: string, signal?: AbortSignal): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const child = execFile(
      "git",
      ["show", `${tag}:${filePath}`],
      { cwd: repoRoot, maxBuffer: 50 * 1024 * 1024, encoding: "buffer" as unknown as string, signal },
      (error, stdout) => {
        if (error) {
          if (signal?.aborted) {
            resolve(Buffer.alloc(0));
            return;
          }
          reject(new Error(`git show failed for ${filePath}: ${error.message}`));
          return;
        }
        resolve(stdout as unknown as Buffer);
      }
    );

    if (signal) {
      const onAbort = () => child.kill();
      signal.addEventListener("abort", onAbort, { once: true });
    }
  });
}

function emitPackProgress(
  onProgress: PackerOptions["onProgress"],
  label: string,
  startedAtMs: number,
  current: number,
  total: number,
  path: string,
  getLastEmitAt: () => number,
  setLastEmitAt: (value: number) => void
): void {
  if (!onProgress) return;

  const now = Date.now();
  const shouldEmit = current === total || current === 1 || now - getLastEmitAt() >= 80;
  if (!shouldEmit) return;

  setLastEmitAt(now);
  onProgress({
    phase: "pack",
    current,
    total,
    path,
    label,
    detail: path,
    etaMs: estimateEtaMs(startedAtMs, current, total)
  });
}
