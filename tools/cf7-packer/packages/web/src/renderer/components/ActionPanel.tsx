import { useState } from "react";
import type { PackerIpcApi, PackResult, PackerProgressEvent } from "../../shared/ipc-types.js";
import type { AppStatus } from "../hooks/usePackExecution.js";
import { nextLogId, type LogEntry } from "../hooks/usePackerEvents.js";
import { formatSize, formatEta, resolveProgressPhaseLabel } from "../utils/helpers.js";

interface ActionPanelProps {
  api: PackerIpcApi | undefined;
  status: AppStatus;
  result: PackResult | null;
  isRunning: boolean;
  isTagModeWithoutTag: boolean;
  cannotExecute: boolean;
  hasPreview: boolean;
  loadingPreview: boolean;
  sfxBuilding: boolean;
  sfxVersion: string;
  unityDataDir: string;
  progress: PackerProgressEvent | null;
  onRunPack: (dryRun: boolean) => void;
  onLoadPreview: () => void;
  onCancel: () => void;
  onReveal: () => void;
  setSfxBuilding: React.Dispatch<React.SetStateAction<boolean>>;
  setLogs: React.Dispatch<React.SetStateAction<LogEntry[]>>;
  setProgress: React.Dispatch<React.SetStateAction<PackerProgressEvent | null>>;
}

export default function ActionPanel({
  api, status, result, isRunning, isTagModeWithoutTag, cannotExecute,
  hasPreview, loadingPreview, sfxBuilding, sfxVersion, unityDataDir,
  progress,
  onRunPack, onLoadPreview, onCancel, onReveal,
  setSfxBuilding, setLogs, setProgress
}: ActionPanelProps) {
  const [sfxOutputPath, setSfxOutputPath] = useState<string | null>(null);
  const progressPercent = progress && progress.total > 0
    ? Math.round((progress.current / progress.total) * 100) : 0;
  const showProgressPanel = Boolean(progress && progress.total > 0 && (isRunning || sfxBuilding));
  const progressTitle = progress?.label ?? resolveProgressPhaseLabel(progress?.phase);
  const progressDetail = progress?.detail ?? progress?.path ?? "";
  const progressEtaText = progress?.etaMs !== undefined
    ? `预计剩余 ${formatEta(progress.etaMs)}`
    : progress && progress.total > 0
      ? `已处理 ${progress.current}/${progress.total}`
      : "";

  return (
    <section className="section action-section control-pane motion-surface">
      <div className="panel-title-row">
        <h2>执行操作</h2>
        <span className="panel-hint">先预览确认，再执行打包</span>
      </div>
      <div className="action-buttons">
        <button onClick={() => onRunPack(true)} disabled={cannotExecute} className="btn btn-preview"
          title={isTagModeWithoutTag ? "请先选择 Git 标签" : "只扫描和统计，不复制文件，用来确认打包范围是否正确"}>
          ▶ 预览（干跑）
        </button>
        <button onClick={() => onRunPack(false)} disabled={cannotExecute} className="btn btn-execute"
          title={isTagModeWithoutTag ? "请先选择 Git 标签" : "实际复制文件到输出目录，完成后可直接发布"}>
          ▶▶ 执行打包
        </button>
        {!hasPreview && !isRunning && !isTagModeWithoutTag && (
          <button onClick={onLoadPreview} disabled={loadingPreview} className="btn btn-browse"
            title="快速查看哪些文件会被打包，不执行任何操作">
            {loadingPreview ? "加载中..." : "📂 浏览文件"}
          </button>
        )}
        {isRunning && (
          <button onClick={onCancel} className="btn btn-cancel">✕ 取消</button>
        )}
      </div>
      {showProgressPanel && progress && (
        <div className="progress-panel">
          <div className="progress-meta">
            <div className="progress-title-row">
              <span className="progress-phase-label">{progressTitle}</span>
              <span className="progress-phase-stats">{progressPercent}%</span>
            </div>
            <div className="progress-subtitle-row">
              <span className="progress-detail" title={progressDetail}>{progressDetail || "正在准备..."}</span>
              <span className="progress-eta">{progressEtaText}</span>
            </div>
          </div>
          <div className="progress-bar-container">
            <div className="progress-bar" style={{ width: `${progressPercent}%` }} />
            <span className="progress-text">{progress.current}/{progress.total}</span>
          </div>
        </div>
      )}
      {status === "done" && result && (
        <div className="status-done">
          <span>打包完成: {result.copiedFiles} 文件, {formatSize(result.totalSize)}, 耗时 {result.duration}ms</span>
          <button onClick={onReveal} className="btn-small">打开输出目录</button>
          {!result.cancelled && result.mode === "execute" && (
            <button
              className="btn-small"
              disabled={sfxBuilding}
              onClick={async () => {
                if (!api) return;
                setSfxBuilding(true);
                setProgress({ phase: "sfx", current: 0, total: 100, label: "构建安装包", detail: "准备压缩资源" });
                setLogs((prev) => [...prev, { id: nextLogId(), event: { layer: "sfx", level: "info", message: "开始构建自解压安装包..." } }]);
                const ver = sfxVersion || "update";
                const res = await api.buildSfx({ version: ver, packOutput: result.outputDir, unityDataDir: unityDataDir || undefined });
                if (res.success) {
                  setLogs((prev) => [...prev, { id: nextLogId(), event: { layer: "sfx", level: "info", message: `SFX 构建完成: ${res.outputPath ?? ""}` } }]);
                  setSfxOutputPath(res.outputPath ?? null);
                } else {
                  setLogs((prev) => [...prev, { id: nextLogId(), event: { layer: "sfx", level: "error", message: `SFX 构建失败: ${res.error ?? ""}` } }]);
                }
                setSfxBuilding(false);
              }}
            >
              {sfxBuilding ? "构建中..." : "📦 构建安装包"}
            </button>
          )}
          {sfxOutputPath && !sfxBuilding && (
            <button className="btn-small" onClick={() => api?.revealOutput(sfxOutputPath)}
              title={sfxOutputPath}>
              打开安装包
            </button>
          )}
        </div>
      )}
      {status === "cancelled" && (
        <div className="status-cancelled">已取消 ({result?.copiedFiles ?? 0} 文件已处理)</div>
      )}
      {status === "error" && result && (
        <div className="status-error">{result.errors.length} 个文件处理失败</div>
      )}
    </section>
  );
}
