import fs from "node:fs";
import path from "node:path";
import { execFile } from "node:child_process";
import type { CollectorResult, PackConfig } from "./types.js";
import { validateGitRef } from "./git-utils.js";

/** worktree 模式下硬编码排除的目录名 */
const HARDCODED_EXCLUDE_DIRS = new Set([
  ".git",
  "node_modules",
  ".vscode",
  "__pycache__",
  ".claude"
]);

/**
 * 递归扫描文件系统，收集所有文件路径（相对于 rootDir）。
 * 跳过 HARDCODED_EXCLUDE_DIRS 中的目录。
 */
function walkDirectory(rootDir: string, signal?: AbortSignal): string[] {
  const results: string[] = [];

  function walk(currentDir: string): void {
    if (signal?.aborted) return;

    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(currentDir, { withFileTypes: true });
    } catch {
      return;
    }

    for (const entry of entries) {
      if (signal?.aborted) return;

      if (entry.isDirectory()) {
        if (HARDCODED_EXCLUDE_DIRS.has(entry.name)) continue;
        walk(path.join(currentDir, entry.name));
      } else if (entry.isFile()) {
        const fullPath = path.join(currentDir, entry.name);
        const relativePath = path.relative(rootDir, fullPath).replace(/\\/g, "/");
        results.push(relativePath);
      }
    }
  }

  walk(rootDir);
  return results;
}

/**
 * 通过 git ls-tree 获取指定 tag 的所有文件路径。
 */
function gitLsTree(repoRoot: string, tag: string, signal?: AbortSignal): Promise<string[]> {
  return new Promise((resolve, reject) => {
    const child = execFile(
      "git",
      ["ls-tree", "-r", "--name-only", tag],
      { cwd: repoRoot, maxBuffer: 50 * 1024 * 1024, signal },
      (error, stdout) => {
        if (error) {
          if (signal?.aborted) {
            resolve([]);
            return;
          }
          reject(new Error(`git ls-tree failed: ${error.message}`));
          return;
        }
        const files = stdout.trim().split("\n").filter(Boolean);
        resolve(files);
      }
    );

    // 附加 signal 中止时 kill 子进程
    if (signal) {
      const onAbort = () => child.kill();
      signal.addEventListener("abort", onAbort, { once: true });
    }
  });
}

/**
 * 采集文件列表。
 *
 * - worktree 模式：文件系统递归扫描（不依赖 git 状态）
 * - git-tag 模式：git ls-tree 精确还原
 */
export async function collect(config: PackConfig, signal?: AbortSignal): Promise<CollectorResult> {
  const repoRoot = config.source.repoRoot;

  if (config.source.mode === "git-tag") {
    const tag = config.source.tag;
    if (!tag) {
      throw new Error("git-tag 模式需要指定 tag 名称");
    }
    validateGitRef(tag);
    const files = await gitLsTree(repoRoot, tag, signal);
    return {
      files,
      source: "git-tag",
      tag,
      fileCount: files.length
    };
  }

  // worktree 模式：文件系统扫描
  const files = walkDirectory(repoRoot, signal);
  return {
    files,
    source: "worktree",
    fileCount: files.length
  };
}
