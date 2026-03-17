import type { DiffResult, FilterResult } from "./types.js";

/**
 * 比较两个 FilterResult 的 included 文件列表差异。
 *
 * 典型用途：
 * - 配置 diff：同一源文件列表，两个不同的配置 → 两个 FilterResult
 * - 版本 diff：同一配置，两个不同的 tag → 两个 FilterResult
 */
export function diffFilterResults(baseline: FilterResult, target: FilterResult): DiffResult {
  const baselineSet = new Set(baseline.included.map((f) => f.path));
  const targetSet = new Set(target.included.map((f) => f.path));

  const added: string[] = [];
  const removed: string[] = [];
  let unchanged = 0;

  for (const path of targetSet) {
    if (baselineSet.has(path)) {
      unchanged++;
    } else {
      added.push(path);
    }
  }

  for (const path of baselineSet) {
    if (!targetSet.has(path)) {
      removed.push(path);
    }
  }

  added.sort();
  removed.sort();

  return { added, removed, unchanged };
}
