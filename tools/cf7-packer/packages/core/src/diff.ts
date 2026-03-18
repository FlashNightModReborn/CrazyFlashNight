import type { DiffResult, FilterResult } from "./types.js";

/**
 * 比较两个 FilterResult 的 included 文件列表差异。
 *
 * modifiedPaths 可选：传入时从 "unchanged" 中分离出 "modified"。
 * 不传入时 modified 为空数组（向后兼容）。
 */
export function diffFilterResults(
  baseline: FilterResult,
  target: FilterResult,
  modifiedPaths?: Set<string>
): DiffResult {
  const baselineSet = new Set(baseline.included.map((f) => f.path));
  const targetSet = new Set(target.included.map((f) => f.path));

  const added: string[] = [];
  const removed: string[] = [];
  const modified: string[] = [];
  let unchanged = 0;

  for (const path of targetSet) {
    if (baselineSet.has(path)) {
      if (modifiedPaths?.has(path)) {
        modified.push(path);
      } else {
        unchanged++;
      }
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
  modified.sort();

  return { added, removed, modified, unchanged };
}
