import { useState, useEffect, useCallback, useRef, useMemo } from "react";
import type { CSSProperties } from "react";
import type {
  PackerConfigSummary, PackResult, PackerLogEvent,
  PackerProgressEvent, LayerSummary, FileEntry, DiffResult
} from "../shared/ipc-types.js";
import FileTreePanel from "./components/FileTreePanel.js";
import TreemapChart from "./components/TreemapChart.js";
import DiffPanel from "./components/DiffPanel.js";
import {
  getMotionProfile,
  resolveMotionLevel,
  type MotionLevel
} from "./components/motion-utils.js";
import {
  getParentScopePath,
  isFileInsideScope,
  resolveLayerForPath,
  resolveLayerScopePath
} from "./components/scope-utils.js";

type AppStatus = "idle" | "running" | "cancelled" | "done" | "error";
type DetailTab = "tree" | "diff";

interface LogEntry {
  id: number;
  event: PackerLogEvent;
}

const DEFAULT_LAYOUT = {
  controlSplit: 0.68,
  overviewSplit: 0.36,
  layerSplit: 0.23,
  detailSplit: 0.79
} as const;

const MOTION_OPTIONS: Array<{ value: MotionLevel; label: string }> = [
  { value: "off", label: "关闭" },
  { value: "light", label: "轻量" },
  { value: "standard", label: "标准" }
];

let logId = 0;

export default function App() {
  const api = window.cf7Packer;
  const isElectron = api?.runtime === "electron";

  const [config, setConfig] = useState<PackerConfigSummary | null>(null);
  const [tags, setTags] = useState<string[]>([]);
  const [sourceMode, setSourceMode] = useState<"worktree" | "git-tag">("worktree");
  const [selectedTag, setSelectedTag] = useState<string>("");
  const [outputDir, setOutputDir] = useState<string>("");
  const [status, setStatus] = useState<AppStatus>("idle");
  const [result, setResult] = useState<PackResult | null>(null);
  const [layers, setLayers] = useState<LayerSummary[]>([]);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [progress, setProgress] = useState<PackerProgressEvent | null>(null);

  // 文件浏览状态
  const [previewFiles, setPreviewFiles] = useState<FileEntry[]>([]);
  const [expandedLayer, setExpandedLayer] = useState<string | null>(null);
  const [detailTab, setDetailTab] = useState<DetailTab>("tree");
  const [loadingPreview, setLoadingPreview] = useState(false);

  // 打包选项
  const [buildSfxAfterPack, setBuildSfxAfterPack] = useState(false);
  const [sfxVersion, setSfxVersion] = useState("");
  const [unityDataDir, setUnityDataDir] = useState("");
  const [sfxBuilding, setSfxBuilding] = useState(false);
  const [isLayoutResizing, setIsLayoutResizing] = useState(false);
  const [isLayoutSettling, setIsLayoutSettling] = useState(false);
  const [activeResizeHandle, setActiveResizeHandle] = useState<string | null>(null);
  const [selectedScopeLayer, setSelectedScopeLayer] = useState<string | null>(null);
  const [selectedScopePath, setSelectedScopePath] = useState<string | null>(null);
  const [motionPreference, setMotionPreference] = useStoredString<MotionLevel>("cf7-packer:motion-level", "light");
  const [controlSplit, setControlSplit] = useStoredNumber("cf7-packer:layout:control-split", DEFAULT_LAYOUT.controlSplit, !isLayoutResizing);
  const [overviewSplit, setOverviewSplit] = useStoredNumber("cf7-packer:layout:overview-split", DEFAULT_LAYOUT.overviewSplit, !isLayoutResizing);
  const [layerSplit, setLayerSplit] = useStoredNumber("cf7-packer:layout:layer-split", DEFAULT_LAYOUT.layerSplit, !isLayoutResizing);
  const [detailSplit, setDetailSplit] = useStoredNumber("cf7-packer:layout:detail-split", DEFAULT_LAYOUT.detailSplit, !isLayoutResizing);

  const logEndRef = useRef<HTMLDivElement>(null);
  const controlShellRef = useRef<HTMLDivElement>(null);
  const mainContentRef = useRef<HTMLDivElement>(null);
  const overviewRef = useRef<HTMLDivElement>(null);
  const bottomSplitRef = useRef<HTMLDivElement>(null);
  const activeResizeCleanupRef = useRef<(() => void) | null>(null);
  const settleTimeoutRef = useRef<number | null>(null);

  const prefersReducedMotion = usePrefersReducedMotion();
  const motionLevel = useMemo(
    () => resolveMotionLevel(motionPreference, prefersReducedMotion),
    [motionPreference, prefersReducedMotion]
  );
  const motionProfile = useMemo(() => getMotionProfile(motionLevel), [motionLevel]);
  const motionStyle = useMemo(() => ({
    "--motion-settle-ms": `${motionProfile.settleMs}ms`,
    "--motion-emphasis-ms": `${motionProfile.emphasisMs}ms`,
    "--motion-overlay-opacity": String(motionProfile.overlayOpacity),
    "--motion-surface-lift": `${motionProfile.surfaceLift}px`
  }) as CSSProperties, [motionProfile]);
  const appClassName = [
    "app",
    `motion-${motionLevel}`,
    isLayoutResizing ? "is-layout-resizing" : "",
    isLayoutSettling ? "is-layout-settling" : ""
  ].filter(Boolean).join(" ");

  useEffect(() => {
    if (!api) return;
    void api.loadConfig().then((cfg) => {
      setConfig(cfg);
      setOutputDir(cfg.outputDir);
    });
    void api.getTags().then((t) => {
      setTags(t);
      if (t.length > 0) setSelectedTag(t[t.length - 1]!);
    });
  }, [api]);

  useEffect(() => {
    if (!api) return;
    const offLog = api.onLog((event) => {
      if (isProgressOnlyLog(event)) return;
      setLogs((prev) => [...prev.slice(-500), { id: ++logId, event }]);
    });
    const offProgress = api.onProgress((event) => {
      setProgress(event);
    });
    return () => { offLog(); offProgress(); };
  }, [api]);

  useEffect(() => {
    logEndRef.current?.scrollIntoView({ behavior: motionLevel === "standard" ? "smooth" : "auto" });
  }, [logs, motionLevel]);

  useEffect(() => {
    return () => {
      activeResizeCleanupRef.current?.();
      activeResizeCleanupRef.current = null;
      if (settleTimeoutRef.current !== null) {
        window.clearTimeout(settleTimeoutRef.current);
        settleTimeoutRef.current = null;
      }
    };
  }, []);

  const clearSettle = useCallback(() => {
    if (settleTimeoutRef.current !== null) {
      window.clearTimeout(settleTimeoutRef.current);
      settleTimeoutRef.current = null;
    }
  }, []);

  const startLayoutSettle = useCallback(() => {
    clearSettle();
    if (motionProfile.settleMs <= 0) {
      setIsLayoutSettling(false);
      return;
    }
    setIsLayoutSettling(true);
    settleTimeoutRef.current = window.setTimeout(() => {
      settleTimeoutRef.current = null;
      setIsLayoutSettling(false);
    }, motionProfile.settleMs);
  }, [clearSettle, motionProfile.settleMs]);

  useEffect(() => {
    if (motionProfile.settleMs > 0) return;
    clearSettle();
    setIsLayoutSettling(false);
  }, [clearSettle, motionProfile.settleMs]);

  const loadPreview = useCallback(async () => {
    if (!api || loadingPreview) return;
    setLoadingPreview(true);
    try {
      const preview = await api.previewFiles(
        sourceMode === "git-tag" ? { tag: selectedTag } : undefined
      );
      setPreviewFiles(preview.included);
      setLayers(preview.layers);
    } catch (err) {
      setLogs((prev) => [...prev, {
        id: ++logId,
        event: { layer: "system", level: "error", message: `预览失败: ${String(err)}` }
      }]);
    } finally {
      setLoadingPreview(false);
    }
  }, [api, loadingPreview, sourceMode, selectedTag]);

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
      if (dryRun && previewFiles.length === 0) {
        void loadPreview();
      }
      // 实际打包后自动构建 SFX
      if (!dryRun && buildSfxAfterPack && !packResult.cancelled && packResult.errors.length === 0) {
        setSfxBuilding(true);
        setProgress({ phase: "sfx", current: 0, total: 100, label: "构建安装包", detail: "准备压缩资源" });
        setLogs((prev) => [...prev, { id: ++logId, event: { layer: "sfx", level: "info", message: "开始构建自解压安装包..." } }]);
        const ver = sfxVersion || "update";
        const sfxRes = await api.buildSfx({ version: ver, packOutput: packResult.outputDir, unityDataDir: unityDataDir || undefined });
        if (sfxRes.success) {
          setLogs((prev) => [...prev, { id: ++logId, event: { layer: "sfx", level: "info", message: `SFX 构建完成: ${sfxRes.outputPath ?? ""}` } }]);
        } else {
          setLogs((prev) => [...prev, { id: ++logId, event: { layer: "sfx", level: "error", message: `SFX 构建失败: ${sfxRes.error ?? ""}` } }]);
        }
        setSfxBuilding(false);
      }
    } catch (err) {
      setLogs((prev) => [...prev, {
        id: ++logId,
        event: { layer: "system", level: "error", message: String(err) }
      }]);
      setStatus("error");
    }
  }, [api, status, sourceMode, selectedTag, outputDir, previewFiles.length, loadPreview]);

  const handleCancel = useCallback(() => { api?.cancel(); }, [api]);
  const handleReveal = useCallback(() => {
    if (result?.outputDir) void api?.revealOutput(result.outputDir);
  }, [api, result]);
  const handlePickDir = useCallback(async () => {
    if (!api) return;
    const picked = await api.pickOutputDir(outputDir || undefined);
    if (!picked.canceled && picked.path) setOutputDir(picked.path);
  }, [api, outputDir]);
  const handleResetLayout = useCallback(() => {
    setControlSplit(DEFAULT_LAYOUT.controlSplit);
    setOverviewSplit(DEFAULT_LAYOUT.overviewSplit);
    setLayerSplit(DEFAULT_LAYOUT.layerSplit);
    setDetailSplit(DEFAULT_LAYOUT.detailSplit);
    startLayoutSettle();
  }, [setControlSplit, setDetailSplit, setLayerSplit, setOverviewSplit, startLayoutSettle]);

  const applyScopeSelection = useCallback((nextPath: string | null, nextLayer: string | null) => {
    setSelectedScopePath(nextPath);
    setSelectedScopeLayer(nextLayer);
    setExpandedLayer(nextLayer);
    setDetailTab("tree");
  }, []);

  const handleLayerScopeChange = useCallback((nextLayer: string | null) => {
    applyScopeSelection(resolveLayerScopePath(previewFiles, nextLayer), nextLayer);
  }, [applyScopeSelection, previewFiles]);

  const handleTreemapScopeChange = useCallback((nextPath: string | null, nextLayer: string | null) => {
    applyScopeSelection(nextPath, nextLayer);
  }, [applyScopeSelection]);

  const handleScopeNavigate = useCallback((nextPath: string | null, nextLayer: string | null) => {
    applyScopeSelection(nextPath, nextLayer);
  }, [applyScopeSelection]);

  const handleResetScope = useCallback(() => {
    applyScopeSelection(null, null);
  }, [applyScopeSelection]);

  const handleNavigateUp = useCallback(() => {
    if (selectedScopePath) {
      const parentPath = getParentScopePath(selectedScopePath);
      if (!parentPath) {
        applyScopeSelection(null, null);
        return;
      }
      applyScopeSelection(parentPath, resolveLayerForPath(previewFiles, parentPath) ?? selectedScopeLayer);
      return;
    }

    if (selectedScopeLayer) {
      applyScopeSelection(null, null);
    }
  }, [applyScopeSelection, previewFiles, selectedScopeLayer, selectedScopePath]);

  useEffect(() => {
    if (!selectedScopeLayer && !selectedScopePath) return;

    const hasLayer = selectedScopeLayer
      ? previewFiles.some((file) => file.layer === selectedScopeLayer)
      : true;
    const hasPath = selectedScopePath
      ? previewFiles.some((file) => isFileInsideScope(file.path, selectedScopePath))
      : true;

    if (hasLayer && hasPath) return;

    if (!hasLayer) {
      setExpandedLayer(null);
      setSelectedScopeLayer(null);
    }
    if (!hasPath) {
      setSelectedScopePath(resolveLayerScopePath(previewFiles, hasLayer ? selectedScopeLayer : null));
    }
  }, [previewFiles, selectedScopeLayer, selectedScopePath]);

  const beginResize = useCallback((
    clientX: number,
    clientY: number,
    options: {
      handleId: string;
      container: React.RefObject<HTMLElement | null>;
      axis: "x" | "y";
      min: number;
      max: number;
      setValue: (value: number) => void;
    }
  ) => {
    const container = options.container.current;
    if (!container) return;
    activeResizeCleanupRef.current?.();

    const rect = container.getBoundingClientRect();
    const size = options.axis === "x" ? rect.width : rect.height;
    if (size <= 0) return;

    const updateValue = (nextClientX: number, nextClientY: number) => {
      const raw = options.axis === "x"
        ? (nextClientX - rect.left) / size
        : (nextClientY - rect.top) / size;
      options.setValue(clamp(raw, options.min, options.max));
    };

    const onMouseMove = (moveEvent: MouseEvent) => {
      updateValue(moveEvent.clientX, moveEvent.clientY);
    };

    const stop = () => {
      window.removeEventListener("mousemove", onMouseMove);
      window.removeEventListener("mouseup", stop);
      window.removeEventListener("blur", stop);
      document.body.classList.remove("is-resizing");
      document.body.style.cursor = "";
      setIsLayoutResizing(false);
      setActiveResizeHandle(null);
      startLayoutSettle();
      activeResizeCleanupRef.current = null;
    };

    clearSettle();
    setIsLayoutSettling(false);
    setIsLayoutResizing(true);
    setActiveResizeHandle(options.handleId);
    document.body.classList.add("is-resizing");
    document.body.style.cursor = options.axis === "x" ? "col-resize" : "row-resize";
    updateValue(clientX, clientY);
    activeResizeCleanupRef.current = stop;
    window.addEventListener("mousemove", onMouseMove);
    window.addEventListener("mouseup", stop);
    window.addEventListener("blur", stop);
  }, [clearSettle, startLayoutSettle]);

  if (!isElectron) {
    return (
      <div className="app-placeholder">
        <h1>CF7 发行打包工具</h1>
        <p>请通过 launch.bat 启动 Electron 环境</p>
      </div>
    );
  }

  const isRunning = status === "running";
  const isTagModeWithoutTag = sourceMode === "git-tag" && !selectedTag;
  const cannotExecute = isRunning || isTagModeWithoutTag;
  const progressPercent = progress && progress.total > 0
    ? Math.round((progress.current / progress.total) * 100) : 0;
  const hasPreview = previewFiles.length > 0;
  const showOverview = layers.length > 0;
  const showDetail = hasPreview || tags.length > 0;
  const layerNames = layers.map((l) => l.name);
  const hasActiveScope = Boolean(selectedScopeLayer || selectedScopePath);
  const showProgressPanel = Boolean(progress && progress.total > 0 && (isRunning || sfxBuilding));
  const progressTitle = progress?.label ?? resolveProgressPhaseLabel(progress?.phase);
  const progressDetail = progress?.detail ?? progress?.path ?? "";
  const progressEtaText = progress?.etaMs !== undefined
    ? `预计剩余 ${formatEta(progress.etaMs)}`
    : progress && progress.total > 0
      ? `已处理 ${progress.current}/${progress.total}`
      : "";

  return (
    <div className={appClassName} style={motionStyle}>
      <header className="header">
        <div className="header-title-group">
          <h1>CF7 发行打包工具</h1>
          {config && <span className="config-name">{config.name}</span>}
        </div>
        <div className="header-actions">
          <div className="motion-controls" aria-label="动效档位">
            <span className="motion-label">动效</span>
            <div className="motion-toggle" role="group" aria-label="动画强度">
              {MOTION_OPTIONS.map((option) => (
                <button
                  key={option.value}
                  type="button"
                  className={`motion-toggle-btn ${motionPreference === option.value ? "active" : ""}`}
                  onClick={() => setMotionPreference(option.value)}
                  aria-pressed={motionPreference === option.value}
                >
                  {option.label}
                </button>
              ))}
            </div>
          </div>
          <button className="btn-small" onClick={handleResetLayout}>重置布局</button>
        </div>
      </header>

      <div className="control-shell" ref={controlShellRef}>
        <section
          className="section source-section control-pane motion-surface motion-split-pane"
          style={{ flexBasis: `${controlSplit * 100}%`, flexGrow: 0, flexShrink: 0 }}
        >
          <div className="panel-title-row">
            <h2>打包来源与输出</h2>
            <span className="panel-hint">拖动中间分隔条可调整布局</span>
          </div>
          <div className="source-toggle">
            <label>
              <input type="radio" name="source" checked={sourceMode === "worktree"}
                onChange={() => setSourceMode("worktree")} disabled={isRunning} />
              工作区
            </label>
            <label>
              <input type="radio" name="source" checked={sourceMode === "git-tag"}
                onChange={() => setSourceMode("git-tag")} disabled={isRunning} />
              Git 标签
            </label>
            {sourceMode === "git-tag" && (
              <select value={selectedTag} onChange={(e) => setSelectedTag(e.target.value)} disabled={isRunning}>
                {tags.map((tag) => <option key={tag} value={tag}>{tag}</option>)}
              </select>
            )}
          </div>
          <div className="output-row">
            <label>输出:</label>
            <input type="text" value={outputDir} onChange={(e) => setOutputDir(e.target.value)}
              placeholder="./output/{version}" disabled={isRunning} />
            <button onClick={handlePickDir} disabled={isRunning} className="btn-small">浏览</button>
          </div>
          <div className="sfx-options-row">
            <label className="sfx-label">
              <input type="checkbox" checked={buildSfxAfterPack} onChange={(e) => setBuildSfxAfterPack(e.target.checked)} disabled={isRunning} />
              打包后自动构建安装包
            </label>
            {buildSfxAfterPack && <>
              <input type="text" value={sfxVersion} onChange={(e) => setSfxVersion(e.target.value)}
                placeholder="版本号 (如 2.72)" className="sfx-input" disabled={isRunning} />
              <input type="text" value={unityDataDir} onChange={(e) => setUnityDataDir(e.target.value)}
                placeholder="Unity _Data 目录 (可选)" className="sfx-input sfx-input-wide" disabled={isRunning} />
            </>}
          </div>
        </section>
        <ResizeHandle
          orientation="vertical"
          title="拖动调整控制区宽度"
          isActive={activeResizeHandle === "control"}
          onStartResize={(clientX, clientY) => beginResize(clientX, clientY, {
            handleId: "control",
            container: controlShellRef,
            axis: "x",
            min: 0.45,
            max: 0.8,
            setValue: setControlSplit
          })}
        />
        <section className="section action-section control-pane motion-surface">
          <div className="panel-title-row">
            <h2>执行操作</h2>
            <span className="panel-hint">可与左侧同栏显示，节省垂直空间</span>
          </div>
          <div className="action-buttons">
            <button onClick={() => void runPack(true)} disabled={cannotExecute} className="btn btn-preview"
              title={isTagModeWithoutTag ? "请先选择 Git 标签" : undefined}>
              ▶ 预览（干跑）
            </button>
            <button onClick={() => void runPack(false)} disabled={cannotExecute} className="btn btn-execute"
              title={isTagModeWithoutTag ? "请先选择 Git 标签" : undefined}>
              ▶▶ 执行打包
            </button>
            {!hasPreview && !isRunning && !isTagModeWithoutTag && (
              <button onClick={() => void loadPreview()} disabled={loadingPreview} className="btn btn-browse">
                {loadingPreview ? "加载中..." : "📂 浏览文件"}
              </button>
            )}
            {isRunning && (
              <button onClick={handleCancel} className="btn btn-cancel">✕ 取消</button>
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
              <button onClick={handleReveal} className="btn-small">打开输出目录</button>
              {!result.cancelled && result.mode === "execute" && (
                <button
                  className="btn-small"
                  disabled={sfxBuilding}
                  onClick={async () => {
                    if (!api) return;
                    setSfxBuilding(true);
                    setProgress({ phase: "sfx", current: 0, total: 100, label: "构建安装包", detail: "准备压缩资源" });
                    setLogs((prev) => [...prev, { id: ++logId, event: { layer: "sfx", level: "info", message: "开始构建自解压安装包..." } }]);
                    const ver = sfxVersion || "update";
                    const res = await api.buildSfx({ version: ver, packOutput: result.outputDir, unityDataDir: unityDataDir || undefined });
                    if (res.success) {
                      setLogs((prev) => [...prev, { id: ++logId, event: { layer: "sfx", level: "info", message: `SFX 构建完成: ${res.outputPath ?? ""}` } }]);
                    } else {
                      setLogs((prev) => [...prev, { id: ++logId, event: { layer: "sfx", level: "error", message: `SFX 构建失败: ${res.error ?? ""}` } }]);
                    }
                    setSfxBuilding(false);
                  }}
                >
                  {sfxBuilding ? "构建中..." : "📦 构建安装包"}
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
      </div>

      <div className="main-content" ref={mainContentRef}>
        {showOverview && (
          <div
            className="layer-sunburst-split motion-split-pane"
            ref={overviewRef}
            style={{ flexBasis: `${overviewSplit * 100}%`, flexGrow: 0, flexShrink: 0 }}
          >
            <section
              className="section layer-section motion-surface motion-split-pane"
              style={{ flexBasis: `${layerSplit * 100}%`, flexGrow: 0, flexShrink: 0 }}
            >
              <h2>层级统计 {hasPreview && <span className="layer-hint">（点击行查看详情）</span>}</h2>
              <div className="layer-table-wrapper">
                <table className="layer-table">
                  <thead><tr><th>层级</th><th>文件数</th><th>排除</th><th>估算大小</th></tr></thead>
                  <tbody>
                    {layers.map((l) => (
                      <tr key={l.name}
                        className={`${hasPreview ? "layer-clickable" : ""} ${expandedLayer === l.name ? "layer-active" : ""}`}
                        onClick={() => {
                          if (!hasPreview) return;
                          handleLayerScopeChange(expandedLayer === l.name ? null : l.name);
                        }}>
                        <td>{l.name}</td>
                        <td className="num">{l.includedCount}</td>
                        <td className="num excluded">{l.excludedCount > 0 ? l.excludedCount : ""}</td>
                        <td className="num">{typeof l.estimatedSize === "number" ? formatSize(l.estimatedSize) : ""}</td>
                      </tr>
                    ))}
                    <tr className={`total-row ${hasPreview ? "layer-clickable" : ""} ${expandedLayer === null && hasPreview ? "layer-active" : ""}`}
                      onClick={() => { if (hasPreview) handleLayerScopeChange(null); }}>
                      <td>合计</td>
                      <td className="num">{layers.reduce((s, l) => s + l.includedCount, 0)}</td>
                      <td className="num excluded">{layers.reduce((s, l) => s + l.excludedCount, 0)}</td>
                      <td className="num">{formatSize(layers.reduce((s, l) => s + (l.estimatedSize ?? 0), 0))}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </section>
            {hasPreview && (
              <>
                <ResizeHandle
                  orientation="vertical"
                  title="拖动调整层级统计与图表宽度"
                  isActive={activeResizeHandle === "layer"}
                  onStartResize={(clientX, clientY) => beginResize(clientX, clientY, {
                    handleId: "layer",
                    container: overviewRef,
                    axis: "x",
                    min: 0.18,
                    max: 0.42,
                    setValue: setLayerSplit
                  })}
                />
                <section className="section treemap-inline-section motion-surface">
                  <TreemapChart
                    files={previewFiles}
                    layers={layerNames}
                    onExcluded={loadPreview}
                    isLayoutResizing={isLayoutResizing}
                    isLayoutSettling={isLayoutSettling}
                    motionLevel={motionLevel}
                    motionDurationMs={motionProfile.settleMs}
                    focusPath={selectedScopePath}
                    activeLayer={selectedScopeLayer}
                    canNavigateUp={hasActiveScope}
                    onFocusPathChange={handleTreemapScopeChange}
                    onNavigate={handleScopeNavigate}
                    onNavigateUp={handleNavigateUp}
                    onResetScope={handleResetScope}
                  />
                </section>
              </>
            )}
          </div>
        )}

        {showOverview && (
          <ResizeHandle
            orientation="horizontal"
            title="拖动调整上方预览与下方面板高度"
            isActive={activeResizeHandle === "overview"}
            onStartResize={(clientX, clientY) => beginResize(clientX, clientY, {
              handleId: "overview",
              container: mainContentRef,
              axis: "y",
              min: 0.22,
              max: 0.7,
              setValue: setOverviewSplit
            })}
          />
        )}

        <div className="bottom-split" ref={bottomSplitRef}>
          {showDetail && (
            <section
              className="section detail-section motion-surface motion-split-pane"
              style={{ flexBasis: `${detailSplit * 100}%`, flexGrow: 0, flexShrink: 0 }}
            >
            <div className="detail-tabs">
              {hasPreview && (
                <button className={`detail-tab ${detailTab === "tree" ? "active" : ""}`}
                  onClick={() => setDetailTab("tree")}>📁 文件树</button>
              )}
              <button className={`detail-tab ${detailTab === "diff" ? "active" : ""}`}
                onClick={() => setDetailTab("diff")}>⚡ 差异对比</button>
            </div>
            <div className="detail-body">
              {detailTab === "tree" && hasPreview && (
                <FileTreePanel
                  files={previewFiles}
                  layerFilter={selectedScopeLayer}
                  focusPath={selectedScopePath}
                  onExcluded={loadPreview}
                />
              )}
              {detailTab === "diff" && (
                <DiffPanel
                  tags={tags}
                  onDiff={async (baseTag, targetTag) => api!.diffFiles({ baseTag, targetTag })}
                />
              )}
            </div>
            </section>
          )}
          {showDetail && (
            <ResizeHandle
              orientation="vertical"
              title="拖动调整文件树与日志宽度"
              isActive={activeResizeHandle === "detail"}
              onStartResize={(clientX, clientY) => beginResize(clientX, clientY, {
                handleId: "detail",
                container: bottomSplitRef,
                axis: "x",
                min: 0.52,
                max: 0.88,
                setValue: setDetailSplit
              })}
            />
          )}

          <section className="section log-section motion-surface">
            <h2>日志</h2>
            <div className="log-panel">
              {logs.map((entry) => (
                <div key={entry.id} className={`log-line log-${entry.event.level}`}>
                  [{entry.event.level.toUpperCase()}] {entry.event.layer}: {entry.event.message}
                </div>
              ))}
              <div ref={logEndRef} />
            </div>
          </section>
        </div>
      </div>
    </div>
  );
}

function useStoredNumber(key: string, fallback: number, persistEnabled = true) {
  const [value, setValue] = useState(() => {
    if (typeof window === "undefined") return fallback;
    const stored = window.localStorage.getItem(key);
    const parsed = stored ? Number(stored) : Number.NaN;
    return Number.isFinite(parsed) ? parsed : fallback;
  });

  useEffect(() => {
    if (!persistEnabled) return;
    window.localStorage.setItem(key, String(value));
  }, [key, persistEnabled, value]);

  return [value, setValue] as const;
}

function useStoredString<T extends string>(key: string, fallback: T, persistEnabled = true) {
  const [value, setValue] = useState<T>(() => {
    if (typeof window === "undefined") return fallback;
    const stored = window.localStorage.getItem(key);
    return stored ? stored as T : fallback;
  });

  useEffect(() => {
    if (!persistEnabled) return;
    window.localStorage.setItem(key, value);
  }, [key, persistEnabled, value]);

  return [value, setValue] as const;
}

function usePrefersReducedMotion() {
  const [prefersReducedMotion, setPrefersReducedMotion] = useState(false);

  useEffect(() => {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") return;

    const mediaQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setPrefersReducedMotion(mediaQuery.matches);
    update();

    if (typeof mediaQuery.addEventListener === "function") {
      mediaQuery.addEventListener("change", update);
      return () => mediaQuery.removeEventListener("change", update);
    }

    mediaQuery.addListener(update);
    return () => mediaQuery.removeListener(update);
  }, []);

  return prefersReducedMotion;
}

function ResizeHandle({
  orientation,
  title,
  isActive,
  onStartResize
}: {
  orientation: "horizontal" | "vertical";
  title: string;
  isActive?: boolean;
  onStartResize: (clientX: number, clientY: number) => void;
}) {
  return (
    <div
      className={`resize-handle resize-handle-${orientation} ${isActive ? "resize-handle-active" : ""}`}
      title={title}
      onMouseDown={(event) => {
        if (event.button !== 0) return;
        event.preventDefault();
        onStartResize(event.clientX, event.clientY);
      }}
    >
      <span className="resize-handle-grip" />
    </div>
  );
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

function formatEta(ms: number): string {
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

function resolveProgressPhaseLabel(phase?: PackerProgressEvent["phase"]): string {
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

function isProgressOnlyLog(event: PackerLogEvent): boolean {
  return event.layer === "sfx" && /^\s*压缩中\.\.\.\s+\d+%$/.test(event.message);
}
