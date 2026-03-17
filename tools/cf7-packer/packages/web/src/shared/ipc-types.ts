import type { PackResult, PackerLogEvent, PackerProgressEvent, LayerSummary, FileEntry, DiffResult } from "@cf7-packer/core";

export interface PackerRunOptions {
  dryRun: boolean;
  tag?: string | undefined;
  outputDir?: string | undefined;
}

export interface PackerConfigSummary {
  name: string;
  mode: "worktree" | "git-tag";
  tag?: string | undefined;
  layers: Array<{ name: string; description?: string | undefined }>;
  globalExcludeCount: number;
  outputDir: string;
}

export interface PreviewFilesResult {
  included: FileEntry[];
  excluded: FileEntry[];
  layers: LayerSummary[];
  unmatchedCount: number;
}

export interface PreviewFilesOptions {
  tag?: string | undefined;
}

export interface DiffOptions {
  /** baseline tag（null = 当前工作区） */
  baseTag?: string | null | undefined;
  /** target tag（null = 当前工作区） */
  targetTag?: string | null | undefined;
}

export interface BuildSfxOptions {
  version: string;
  packOutput: string;
  unityDataDir?: string | undefined;
}

export interface ExcludeRequest {
  /** 相对于 repoRoot 的文件/目录路径 */
  filePath: string;
  /** 是否是目录 */
  isDir: boolean;
  /** layer hint（文件节点携带，目录可能为空） */
  layer?: string | undefined;
  /** 是否同时从磁盘删除 */
  deleteFromDisk: boolean;
}

export interface ExcludeResult {
  success: boolean;
  /** 添加的排除模式 */
  pattern: string;
  /** 添加到哪个 layer（或 "__global__"） */
  layerName: string;
  error?: string | undefined;
}

export interface PackerIpcApi {
  runtime: string;
  loadConfig: () => Promise<PackerConfigSummary>;
  getTags: () => Promise<string[]>;
  previewFiles: (opts?: PreviewFilesOptions) => Promise<PreviewFilesResult>;
  diffFiles: (opts: DiffOptions) => Promise<DiffResult>;
  run: (opts: PackerRunOptions) => Promise<PackResult>;
  buildSfx: (opts: BuildSfxOptions) => Promise<{ success: boolean; outputPath?: string; error?: string }>;
  cancel: () => Promise<void>;
  openFile: (relativePath: string) => Promise<void>;
  revealFile: (relativePath: string) => Promise<void>;
  pickOutputDir: (currentPath?: string) => Promise<{ canceled: boolean; path?: string }>;
  revealOutput: (targetPath: string) => Promise<void>;
  excludeFile: (req: ExcludeRequest) => Promise<ExcludeResult>;
  onLog: (callback: (event: PackerLogEvent) => void) => () => void;
  onProgress: (callback: (event: PackerProgressEvent) => void) => () => void;
}

export type { PackResult, PackerLogEvent, PackerProgressEvent, LayerSummary, FileEntry, DiffResult };
