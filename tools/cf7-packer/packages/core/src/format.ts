/** 格式化字节大小为人类可读字符串 */
export function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

/** 基于已完成进度估算剩余时间（毫秒） */
export function estimateEtaMs(startedAtMs: number, completed: number, total: number): number | undefined {
  if (completed <= 0 || total <= completed) return undefined;
  const elapsed = Date.now() - startedAtMs;
  if (elapsed <= 0) return undefined;
  const avgPerUnit = elapsed / completed;
  return Math.max(0, Math.round(avgPerUnit * (total - completed)));
}
