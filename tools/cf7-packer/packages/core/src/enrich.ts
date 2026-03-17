import fs from "node:fs";
import path from "node:path";
import type { FileEntry } from "./types.js";

/**
 * 为 FileEntry 列表填充 size 字段（worktree 模式）。
 * git-tag 模式无法 stat，跳过。
 */
export function enrichWithSize(entries: FileEntry[], repoRoot: string): void {
  for (const entry of entries) {
    try {
      const stat = fs.statSync(path.join(repoRoot, entry.path));
      entry.size = stat.size;
    } catch {
      // 文件不可读，跳过
    }
  }
}
