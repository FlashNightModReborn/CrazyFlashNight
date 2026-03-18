import { ipcMain } from "electron";
import { execFileSync } from "node:child_process";
import {
  collect,
  filterFiles,
  enrichWithSize,
  diffFilterResults,
  applyEstimatedSizes,
  getTagBlobInfo,
  getWorktreeBlobHashes,
  getModifiedPathsBetweenTags,
  withSourceOverride
} from "@cf7-packer/core";
import type { DiffResult } from "@cf7-packer/core";
import type { PackerConfigSummary, PreviewFilesResult, PreviewFilesOptions, DiffOptions } from "../shared/ipc-types.js";
import type { IpcContext } from "./ipc-context.js";

export function registerConfigHandlers(ctx: IpcContext): void {
  ipcMain.handle("cf7-packer:load-config", (): PackerConfigSummary => {
    const config = ctx.getConfig();
    return {
      name: config.meta.name,
      mode: config.source.mode,
      tag: config.source.tag ?? undefined,
      layers: config.layers.map((l) => ({
        name: l.name,
        description: l.description
      })),
      globalExcludeCount: config.globalExclude.length,
      outputDir: config.output.dir
    };
  });

  ipcMain.handle("cf7-packer:get-tags", (): string[] => {
    const config = ctx.getConfig();
    try {
      const output = execFileSync("git", ["tag", "-l"], {
        cwd: config.source.repoRoot,
        encoding: "utf8"
      });
      return output.trim().split("\n").filter(Boolean);
    } catch {
      return [];
    }
  });

  ipcMain.handle("cf7-packer:preview-files", async (_event, opts?: PreviewFilesOptions): Promise<PreviewFilesResult> => {
    if (opts?.tag !== undefined && opts.tag !== null && !opts.tag) {
      throw new Error("git-tag 模式需要指定非空的 tag 名称");
    }
    const config = withSourceOverride(ctx.getConfig(), opts?.tag ? { tag: opts.tag } : undefined);
    const collected = await collect(config);
    const filtered = filterFiles(collected.files, config);
    if (config.source.mode === "worktree") {
      enrichWithSize(filtered.included, config.source.repoRoot);
    } else if (config.source.mode === "git-tag" && config.source.tag) {
      try {
        const blobInfo = await getTagBlobInfo(config.source.repoRoot, config.source.tag);
        for (const entry of filtered.included) {
          const info = blobInfo.get(entry.path);
          if (info) entry.size = info.size;
        }
      } catch {
        // 获取失败不阻塞预览
      }
    }
    return {
      included: filtered.included,
      excluded: filtered.excluded,
      layers: applyEstimatedSizes(filtered.layers, filtered.included),
      unmatchedCount: filtered.unmatchedCount
    };
  });

  ipcMain.handle("cf7-packer:diff-files", async (_event, opts: DiffOptions): Promise<DiffResult> => {
    const config = ctx.getConfig();
    const repoRoot = config.source.repoRoot;

    async function collectFiltered(tag: string | null | undefined) {
      const cfg = tag
        ? withSourceOverride(ctx.getConfig(), { tag })
        : ctx.getConfig();
      const collected = await collect(cfg);
      return filterFiles(collected.files, cfg);
    }

    const [baseline, target] = await Promise.all([
      collectFiltered(opts.baseTag),
      collectFiltered(opts.targetTag)
    ]);

    let modifiedPaths: Set<string> | undefined;
    const baseIsTag = !!opts.baseTag;
    const targetIsTag = !!opts.targetTag;

    try {
      if (baseIsTag && targetIsTag) {
        modifiedPaths = await getModifiedPathsBetweenTags(repoRoot, opts.baseTag!, opts.targetTag!);
      } else if (baseIsTag !== targetIsTag) {
        const tag = baseIsTag ? opts.baseTag! : opts.targetTag!;
        const tagInfo = await getTagBlobInfo(repoRoot, tag);
        const baselineSet = new Set(baseline.included.map(f => f.path));
        const targetSet = new Set(target.included.map(f => f.path));
        const commonPaths = [...baselineSet].filter(p => targetSet.has(p));
        const worktreeHashes = await getWorktreeBlobHashes(repoRoot, commonPaths);
        modifiedPaths = new Set<string>();
        for (const p of commonPaths) {
          const tagHash = tagInfo.get(p)?.hash;
          const wtHash = worktreeHashes.get(p);
          if (tagHash && wtHash && tagHash !== wtHash) {
            modifiedPaths.add(p);
          }
        }
      }
    } catch {
      // 内容检测失败不阻塞，退化为纯路径 diff
    }

    return diffFilterResults(baseline, target, modifiedPaths);
  });
}
