import fs from "node:fs";
import path from "node:path";
import { execFile } from "node:child_process";
import type { FilterResult, PackerOptions, PackResult, LayerSummary, PackConfig, MinifyConfig } from "./types.js";
import { minifyByExtension } from "./minify.js";

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
  const { dryRun, outputDir, clean, signal } = options;
  const repoRoot = config.source.repoRoot;
  const isGitTag = config.source.mode === "git-tag";
  const tag = config.source.tag;

  const resolvedOutputDir = path.resolve(outputDir);
  const minify = config.output.minify;
  const minifyExts = new Set(minify?.enabled ? minify.extensions : []);

  if (!dryRun) {
    if (clean && fs.existsSync(resolvedOutputDir)) {
      fs.rmSync(resolvedOutputDir, { recursive: true, force: true });
    }
    fs.mkdirSync(resolvedOutputDir, { recursive: true });
  }

  const errors: Array<{ path: string; error: string }> = [];
  let copiedFiles = 0;
  let totalSize = 0;
  let cancelled = false;

  for (const entry of filterResult.included) {
    if (signal?.aborted) {
      cancelled = true;
      break;
    }

    if (dryRun) {
      // dry-run: 统计文件大小
      if (!isGitTag) {
        try {
          const stat = fs.statSync(path.join(repoRoot, entry.path));
          totalSize += stat.size;
        } catch {
          // 文件不可读，跳过大小统计
        }
      }
      copiedFiles++;
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
      } else {
        const srcPath = path.join(repoRoot, entry.path);
        const ext = path.extname(entry.path).toLowerCase();
        if (minifyExts.has(ext)) {
          const raw = fs.readFileSync(srcPath, "utf8");
          const minified = minifyByExtension(raw, ext);
          if (minified !== null) {
            fs.writeFileSync(destPath, minified, "utf8");
            totalSize += Buffer.byteLength(minified, "utf8");
          } else {
            fs.copyFileSync(srcPath, destPath);
            totalSize += fs.statSync(destPath).size;
          }
        } else {
          fs.copyFileSync(srcPath, destPath);
          totalSize += fs.statSync(destPath).size;
        }
      }
      copiedFiles++;
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      errors.push({ path: entry.path, error: message });
    }
  }

  const layers: LayerSummary[] = filterResult.layers.map((l) => ({ ...l }));

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
