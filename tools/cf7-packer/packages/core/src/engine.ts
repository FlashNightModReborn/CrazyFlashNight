import { EventEmitter } from "node:events";
import type {
  PackConfig,
  CollectorResult,
  FilterResult,
  PackerOptions,
  PackResult,
  PackerLogEvent,
  PackerProgressEvent
} from "./types.js";
import { collect } from "./collector.js";
import { filterFiles } from "./filter.js";
import { pack } from "./packer.js";
import { formatSize } from "./format.js";

export interface PackerEngineEvents {
  log: [event: PackerLogEvent];
  progress: [event: PackerProgressEvent];
}

/**
 * 打包引擎：整合 collector → filter → packer 三层流水线。
 * 支持 cancel() 中止正在进行的任务。
 */
export class PackerEngine extends EventEmitter<PackerEngineEvents> {
  private abortController: AbortController | null = null;
  private readonly config: PackConfig;

  constructor(config: PackConfig) {
    super();
    this.config = config;
  }

  /** 中止当前运行。安全幂等。 */
  cancel(): void {
    this.abortController?.abort();
  }

  /** 是否正在运行 */
  get running(): boolean {
    return this.abortController !== null && !this.abortController.signal.aborted;
  }

  /** 全流水线运行 */
  async run(opts: Omit<PackerOptions, "signal">): Promise<PackResult> {
    if (this.running) {
      throw new Error("PackerEngine 正在运行中，请等待完成或 cancel() 后再调用 run()");
    }
    this.abortController = new AbortController();
    const { signal } = this.abortController;

    try {
      // 1. Collect
      this.log("collector", "info", `开始${this.config.source.mode === "git-tag" ? `从 tag [${this.config.source.tag ?? ""}] 枚举` : "扫描文件系统"}...`);
      const collected = await this.collectInternal(signal);

      if (signal.aborted) {
        return this.cancelledResult(opts.outputDir, opts.dryRun);
      }

      this.log("collector", "info", `枚举完成: ${collected.fileCount} 个文件`);
      this.emitProgress("collect", collected.fileCount, collected.fileCount, undefined, {
        label: "枚举文件",
        detail: `共发现 ${collected.fileCount} 个文件`
      });

      // 2. Filter
      this.log("filter", "info", "开始过滤...");
      const filtered = this.filterInternal(collected);

      if (signal.aborted) {
        return this.cancelledResult(opts.outputDir, opts.dryRun);
      }

      for (const layer of filtered.layers) {
        if (layer.excludedCount > 0) {
          this.log("filter", "warn", `${layer.name}: 排除 ${layer.excludedCount} 个文件`);
        }
        this.log("filter", "info", `${layer.name}: ${layer.includedCount} 个文件`);
      }

      if (filtered.unmatchedCount > 0) {
        this.log("filter", "info", `${filtered.unmatchedCount} 个文件不匹配任何层级`);
      }

      this.emitProgress("filter", filtered.included.length, filtered.included.length, undefined, {
        label: "过滤规则",
        detail: `保留 ${filtered.included.length} 个文件`
      });

      // 3. Pack
      const mode = opts.dryRun ? "预览" : "打包";
      this.log("packer", "info", `开始${mode}... 共 ${filtered.included.length} 个文件`);

      const result = await pack(filtered, this.config, {
        ...opts,
        signal,
        onProgress: (event) => this.emit("progress", event)
      });

      if (result.cancelled) {
        this.log("packer", "warn", `用户取消，已完成 ${result.copiedFiles}/${result.totalFiles}`);
      } else {
        this.log("packer", "info", `${mode}完成: ${result.copiedFiles} 个文件, ${formatSize(result.totalSize)}, 耗时 ${result.duration}ms`);
      }

      if (result.errors.length > 0) {
        this.log("packer", "error", `${result.errors.length} 个文件处理失败`);
      }

      return result;
    } finally {
      this.abortController = null;
    }
  }

  /** 分步调用 — collect */
  async collectStep(signal?: AbortSignal): Promise<CollectorResult> {
    return this.collectInternal(signal);
  }

  /** 分步调用 — filter */
  filterStep(collected: CollectorResult): FilterResult {
    return this.filterInternal(collected);
  }

  /** 分步调用 — pack */
  async packStep(filtered: FilterResult, opts: PackerOptions): Promise<PackResult> {
    return pack(filtered, this.config, opts);
  }

  private async collectInternal(signal?: AbortSignal): Promise<CollectorResult> {
    return collect(this.config, signal);
  }

  private filterInternal(collected: CollectorResult): FilterResult {
    return filterFiles(collected.files, this.config);
  }

  private log(layer: string, level: PackerLogEvent["level"], message: string): void {
    this.emit("log", { layer, level, message });
  }

  private emitProgress(
    phase: PackerProgressEvent["phase"],
    current: number,
    total: number,
    filePath?: string,
    extras?: Omit<PackerProgressEvent, "phase" | "current" | "total" | "path">
  ): void {
    const event: PackerProgressEvent = { phase, current, total };
    if (filePath !== undefined) {
      event.path = filePath;
    }
    if (extras?.label !== undefined) {
      event.label = extras.label;
    }
    if (extras?.detail !== undefined) {
      event.detail = extras.detail;
    }
    if (extras?.etaMs !== undefined) {
      event.etaMs = extras.etaMs;
    }
    this.emit("progress", event);
  }

  private cancelledResult(outputDir: string, dryRun: boolean): PackResult {
    return {
      mode: dryRun ? "dry-run" : "execute",
      cancelled: true,
      totalFiles: 0,
      copiedFiles: 0,
      totalSize: 0,
      layers: [],
      outputDir,
      duration: 0,
      errors: []
    };
  }
}
