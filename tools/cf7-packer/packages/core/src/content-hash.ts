import { execFile } from "node:child_process";
import { validateGitRef } from "./git-utils.js";

/**
 * 从 git ls-tree -rl 输出中解析文件的 object hash 和大小。
 * 单次调用获取 tag 下所有文件信息，避免逐文件起子进程。
 *
 * 输出格式示例: "100644 blob abc123def456...    1234\tpath/to/file"
 */
export function getTagBlobInfo(
  repoRoot: string,
  tag: string,
  signal?: AbortSignal
): Promise<Map<string, { hash: string; size: number }>> {
  validateGitRef(tag);
  return new Promise((resolve, reject) => {
    const child = execFile(
      "git",
      ["ls-tree", "-rl", tag],
      { cwd: repoRoot, maxBuffer: 50 * 1024 * 1024, signal },
      (error, stdout) => {
        if (error) {
          if (signal?.aborted) { resolve(new Map()); return; }
          reject(new Error(`git ls-tree -rl failed: ${error.message}`));
          return;
        }
        const result = new Map<string, { hash: string; size: number }>();
        for (const line of stdout.split("\n")) {
          if (!line) continue;
          // 格式: "<mode> <type> <hash>    <size>\t<path>"
          // 注意 size 和 path 之间是 tab 分隔，其余是空格
          const tabIdx = line.indexOf("\t");
          if (tabIdx === -1) continue;
          const meta = line.slice(0, tabIdx).trim();
          const filePath = line.slice(tabIdx + 1);
          // meta: "100644 blob <hash> <size>"  (size 前可能有多个空格)
          const parts = meta.split(/\s+/);
          if (parts.length < 4) continue;
          const hash = parts[2]!;
          const size = parseInt(parts[3]!, 10);
          if (!isNaN(size)) {
            result.set(filePath, { hash, size });
          }
        }
        resolve(result);
      }
    );

    if (signal) {
      const onAbort = () => child.kill();
      signal.addEventListener("abort", onAbort, { once: true });
    }
  });
}

/**
 * 批量计算工作区文件的 git object hash。
 * 使用 git hash-object --stdin-paths 单次进程处理所有文件。
 */
export function getWorktreeBlobHashes(
  repoRoot: string,
  filePaths: string[],
  signal?: AbortSignal
): Promise<Map<string, string>> {
  if (filePaths.length === 0) return Promise.resolve(new Map());

  return new Promise((resolve, reject) => {
    const child = execFile(
      "git",
      ["hash-object", "--stdin-paths"],
      { cwd: repoRoot, maxBuffer: 50 * 1024 * 1024, signal },
      (error, stdout) => {
        if (error) {
          if (signal?.aborted) { resolve(new Map()); return; }
          reject(new Error(`git hash-object failed: ${error.message}`));
          return;
        }
        const hashes = stdout.trim().split("\n");
        const result = new Map<string, string>();
        for (let i = 0; i < filePaths.length && i < hashes.length; i++) {
          result.set(filePaths[i]!, hashes[i]!);
        }
        resolve(result);
      }
    );

    // 通过 stdin 传入文件路径列表
    child.stdin?.write(filePaths.join("\n") + "\n");
    child.stdin?.end();

    if (signal) {
      const onAbort = () => child.kill();
      signal.addEventListener("abort", onAbort, { once: true });
    }
  });
}

/**
 * 比较两个 tag 之间的变更文件列表。
 * 单次 git diff --name-only 调用。
 */
export function getModifiedPathsBetweenTags(
  repoRoot: string,
  baseTag: string,
  targetTag: string,
  signal?: AbortSignal
): Promise<Set<string>> {
  validateGitRef(baseTag);
  validateGitRef(targetTag);
  return new Promise((resolve, reject) => {
    const child = execFile(
      "git",
      ["diff", "--name-only", baseTag, targetTag],
      { cwd: repoRoot, maxBuffer: 50 * 1024 * 1024, signal },
      (error, stdout) => {
        if (error) {
          if (signal?.aborted) { resolve(new Set()); return; }
          reject(new Error(`git diff --name-only failed: ${error.message}`));
          return;
        }
        const paths = new Set(stdout.trim().split("\n").filter(Boolean));
        resolve(paths);
      }
    );

    if (signal) {
      const onAbort = () => child.kill();
      signal.addEventListener("abort", onAbort, { once: true });
    }
  });
}
