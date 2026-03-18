import type { PackResult, PackerLogEvent, PackerProgressEvent, LayerSummary, FileEntry, DiffResult } from "@cf7-packer/core";

export interface PackerRunOptions {
  dryRun: boolean;
  tag?: string | undefined;
  outputDir?: string | undefined;
  /** 跳过输出目录标记检查（调用方已确认）。不可绕过路径安全校验。 */
  forceClean?: boolean | undefined;
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

/** 原始 YAML 配置内容（配置编辑器用） */
export interface RawConfigResult {
  content: string;
  /** 单调递增版本号，每次磁盘读取后递增 */
  version: number;
}

/** 配置保存请求 */
export interface SaveConfigRequest {
  /** 原始 YAML 文本，由后端校验后写盘 */
  content: string;
}

/** 配置保存结果 */
export interface SaveConfigResult {
  success: boolean;
  /** Zod 校验错误（success=false 时） */
  errors?: Array<{ path: string; message: string }>;
}

/** 配置变更推送事件 */
export interface ConfigChangedEvent {
  /** 新版本号 */
  version: number;
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
  confirmDelete: (filePath: string, isDir: boolean) => Promise<boolean>;
  excludeFile: (req: ExcludeRequest) => Promise<ExcludeResult>;
  /** 读取 pack.config.yaml 原始文本 */
  readRawConfig: () => Promise<RawConfigResult>;
  /** 校验并保存配置到磁盘 */
  saveConfig: (req: SaveConfigRequest) => Promise<SaveConfigResult>;
  onLog: (callback: (event: PackerLogEvent) => void) => () => void;
  onProgress: (callback: (event: PackerProgressEvent) => void) => () => void;
  /** 外部修改检测（fs.watch 触发） */
  onConfigChanged: (callback: (event: ConfigChangedEvent) => void) => () => void;
  /** 内部修改通知（如右键排除），ConfigPanel 应无条件重载，不走冲突逻辑 */
  onConfigMutated: (callback: (event: ConfigChangedEvent) => void) => () => void;
}

export type { PackResult, PackerLogEvent, PackerProgressEvent, LayerSummary, FileEntry, DiffResult };
