import { useState, useCallback } from "react";
import type { PackerIpcApi, PackResult, PackerProgressEvent, LayerSummary, FileEntry } from "../../shared/ipc-types.js";
import { nextLogId, type LogEntry } from "./usePackerEvents.js";

export type AppStatus = "idle" | "running" | "cancelled" | "done" | "error";

export interface UsePackExecutionOptions {
  api: PackerIpcApi | undefined;
  sourceMode: "worktree" | "git-tag";
  selectedTag: string;
  outputDir: string;
  buildSfxAfterPack: boolean;
  sfxVersion: string;
  unityDataDir: string;
  previewFilesCount: number;
  loadPreview: () => Promise<void>;
  setLogs: React.Dispatch<React.SetStateAction<LogEntry[]>>;
  setProgress: React.Dispatch<React.SetStateAction<PackerProgressEvent | null>>;
  setLayers: React.Dispatch<React.SetStateAction<LayerSummary[]>>;
  setPreviewFiles: React.Dispatch<React.SetStateAction<FileEntry[]>>;
}

export function usePackExecution(options: UsePackExecutionOptions) {
  const {
    api, sourceMode, selectedTag, outputDir,
    buildSfxAfterPack, sfxVersion, unityDataDir,
    previewFilesCount, loadPreview,
    setLogs, setProgress, setLayers
  } = options;

  const [status, setStatus] = useState<AppStatus>("idle");
  const [result, setResult] = useState<PackResult | null>(null);
  const [sfxBuilding, setSfxBuilding] = useState(false);

  const runPack = useCallback(async (dryRun: boolean) => {
    if (!api || status === "running") return;
    setStatus("running");
    setLogs([]);
    setProgress(null);
    setResult(null);

    try {
      const packResult = await api.run({
        dryRun,
        tag: sourceMode === "git-tag" ? selectedTag : undefined,
        outputDir: outputDir || undefined
      });
      setResult(packResult);
      setLayers(packResult.layers);

      if (packResult.cancelled) {
        setStatus("cancelled");
      } else if (packResult.errors.length > 0) {
        setStatus("error");
      } else {
        setStatus("done");
      }
      // 干跑后自动加载预览
      if (dryRun && previewFilesCount === 0) {
        void loadPreview();
      }
      // 实际打包后自动构建 SFX
      if (!dryRun && buildSfxAfterPack && !packResult.cancelled && packResult.errors.length === 0) {
        setSfxBuilding(true);
        setProgress({ phase: "sfx", current: 0, total: 100, label: "构建安装包", detail: "准备压缩资源" });
        setLogs((prev) => [...prev, { id: nextLogId(), event: { layer: "sfx", level: "info", message: "开始构建自解压安装包..." } }]);
        const ver = sfxVersion || "update";
        const sfxRes = await api.buildSfx({ version: ver, packOutput: packResult.outputDir, unityDataDir: unityDataDir || undefined });
        if (sfxRes.success) {
          setLogs((prev) => [...prev, { id: nextLogId(), event: { layer: "sfx", level: "info", message: `SFX 构建完成: ${sfxRes.outputPath ?? ""}` } }]);
        } else {
          setLogs((prev) => [...prev, { id: nextLogId(), event: { layer: "sfx", level: "error", message: `SFX 构建失败: ${sfxRes.error ?? ""}` } }]);
        }
        setSfxBuilding(false);
      }
    } catch (err) {
      setLogs((prev) => [...prev, {
        id: nextLogId(),
        event: { layer: "system", level: "error", message: String(err) }
      }]);
      setStatus("error");
    }
  }, [api, status, sourceMode, selectedTag, outputDir, previewFilesCount, loadPreview,
      buildSfxAfterPack, sfxVersion, unityDataDir, setLogs, setProgress, setLayers]);

  const handleCancel = useCallback(() => { api?.cancel(); }, [api]);

  return { status, result, sfxBuilding, setSfxBuilding, runPack, handleCancel };
}
