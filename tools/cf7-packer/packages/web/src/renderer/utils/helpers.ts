import type { PackerLogEvent, PackerProgressEvent } from "../../shared/ipc-types.js";

export function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

export function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

export function formatEta(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  const seconds = Math.ceil(ms / 1000);
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  const remainSeconds = seconds % 60;
  if (minutes < 60) return remainSeconds > 0 ? `${minutes}m ${remainSeconds}s` : `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const remainMinutes = minutes % 60;
  return remainMinutes > 0 ? `${hours}h ${remainMinutes}m` : `${hours}h`;
}

export function resolveProgressPhaseLabel(phase?: PackerProgressEvent["phase"]): string {
  switch (phase) {
    case "collect":
      return "枚举文件";
    case "filter":
      return "过滤规则";
    case "pack":
      return "执行打包";
    case "sfx":
      return "构建安装包";
    default:
      return "处理中";
  }
}

export function isProgressOnlyLog(event: PackerLogEvent): boolean {
  return event.layer === "sfx" && /^\s*压缩中\.\.\.\s+\d+%$/.test(event.message);
}
