import type { PackResult, PackerLogEvent, PackerProgressEvent, LayerSummary } from "@cf7-packer/core";

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

export interface PackerIpcApi {
  runtime: string;
  loadConfig: () => Promise<PackerConfigSummary>;
  getTags: () => Promise<string[]>;
  run: (opts: PackerRunOptions) => Promise<PackResult>;
  cancel: () => Promise<void>;
  pickOutputDir: (currentPath?: string) => Promise<{ canceled: boolean; path?: string }>;
  revealOutput: (targetPath: string) => Promise<void>;
  onLog: (callback: (event: PackerLogEvent) => void) => () => void;
  onProgress: (callback: (event: PackerProgressEvent) => void) => () => void;
}

export type { PackResult, PackerLogEvent, PackerProgressEvent, LayerSummary };
