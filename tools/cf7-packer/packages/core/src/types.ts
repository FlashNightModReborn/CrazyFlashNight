/** 单个打包层级的规则 */
export interface LayerRule {
  name: string;
  description?: string | undefined;
  /** 相对于 repoRoot 的源目录前缀（如 "data/"），"." 表示根目录 */
  source: string;
  /** include glob 模式列表 */
  include: string[];
  /** exclude glob 模式列表 */
  exclude: string[];
}

/** 打包配置（对应 pack.config.yaml） */
export interface PackConfig {
  version: number;
  meta: {
    name: string;
    description?: string | undefined;
  };
  source: {
    mode: "worktree" | "git-tag";
    tag?: string | null | undefined;
    repoRoot: string;
  };
  output: {
    dir: string;
    clean: boolean;
  };
  layers: LayerRule[];
  globalExclude: string[];
}

/** 文件条目 */
export interface FileEntry {
  /** 相对于 repoRoot 的路径 */
  path: string;
  /** 归属的 layer name */
  layer: string;
  /** 文件大小（字节），dry-run 时可选 */
  size?: number | undefined;
}

/** 层级汇总 */
export interface LayerSummary {
  name: string;
  description?: string | undefined;
  includedCount: number;
  excludedCount: number;
  estimatedSize?: number | undefined;
}

/** Collector 结果 */
export interface CollectorResult {
  files: string[];
  source: "worktree" | "git-tag";
  tag?: string | undefined;
  fileCount: number;
}

/** Filter 结果 */
export interface FilterResult {
  included: FileEntry[];
  excluded: FileEntry[];
  layers: LayerSummary[];
  unmatchedCount: number;
}

/** Packer 选项 */
export interface PackerOptions {
  dryRun: boolean;
  outputDir: string;
  clean: boolean;
  signal?: AbortSignal | undefined;
}

/** Packer 结果 */
export interface PackResult {
  mode: "dry-run" | "execute";
  cancelled: boolean;
  totalFiles: number;
  copiedFiles: number;
  totalSize: number;
  layers: LayerSummary[];
  outputDir: string;
  duration: number;
  errors: Array<{ path: string; error: string }>;
}

/** Diff 结果 */
export interface DiffResult {
  added: string[];
  removed: string[];
  unchanged: number;
}

/** 日志事件 */
export interface PackerLogEvent {
  layer: string;
  level: "info" | "warn" | "error";
  message: string;
}

/** 进度事件 */
export interface PackerProgressEvent {
  phase: "collect" | "filter" | "pack";
  current: number;
  total: number;
  path?: string | undefined;
}
