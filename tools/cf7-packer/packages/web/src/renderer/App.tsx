import { useState, useEffect, useCallback, useMemo, useRef } from "react";
import type { CSSProperties } from "react";
import type {
  PackerConfigSummary, PackerProgressEvent, LayerSummary, FileEntry
} from "../shared/ipc-types.js";
import FileTreePanel from "./components/FileTreePanel.js";
import DiffPanel from "./components/DiffPanel.js";
import ConfigPanel from "./components/ConfigPanel.js";
import ResizeHandle from "./components/ResizeHandle.js";
import Header from "./components/Header.js";
import ControlPanel from "./components/ControlPanel.js";
import ActionPanel from "./components/ActionPanel.js";
import OverviewPanel from "./components/OverviewPanel.js";
import LogPanel from "./components/LogPanel.js";
import {
  getMotionProfile,
  resolveMotionLevel,
  type MotionLevel
} from "./components/motion-utils.js";
import { useStoredNumber, useStoredString } from "./hooks/useLocalStorage.js";
import { usePrefersReducedMotion } from "./hooks/usePrefersReducedMotion.js";
import { usePackerEvents, nextLogId, type LogEntry } from "./hooks/usePackerEvents.js";
import { usePackExecution } from "./hooks/usePackExecution.js";
import { useScopeNavigation, type DetailTab } from "./hooks/useScopeNavigation.js";
import { useLayoutResize, DEFAULT_LAYOUT } from "./hooks/useLayoutResize.js";

export default function App() {
  const api = window.cf7Packer;
  const isElectron = api?.runtime === "electron";

  const [config, setConfig] = useState<PackerConfigSummary | null>(null);
  const [tags, setTags] = useState<string[]>([]);
  const [sourceMode, setSourceMode] = useState<"worktree" | "git-tag">("worktree");
  const [selectedTag, setSelectedTag] = useState<string>("");
  const [outputDir, setOutputDir] = useState<string>("");
  const [layers, setLayers] = useState<LayerSummary[]>([]);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [progress, setProgress] = useState<PackerProgressEvent | null>(null);

  const [previewFiles, setPreviewFiles] = useState<FileEntry[]>([]);
  const [expandedLayer, setExpandedLayer] = useState<string | null>(null);
  const [detailTab, setDetailTab] = useState<DetailTab>("tree");
  const [loadingPreview, setLoadingPreview] = useState(false);

  const [buildSfxAfterPack, setBuildSfxAfterPack] = useState(false);
  const [sfxVersion, setSfxVersion] = useState("");
  const [unityDataDir, setUnityDataDir] = useState("");

  // Motion preferences
  const [motionPreference, setMotionPreference] = useStoredString<MotionLevel>("cf7-packer:motion-level", "light");
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

  // Layout resize
  const {
    isLayoutResizing, isLayoutSettling, activeResizeHandle,
    controlShellRef, mainContentRef, overviewRef, bottomSplitRef,
    beginResize, startLayoutSettle
  } = useLayoutResize(motionProfile);

  const [controlSplit, setControlSplit] = useStoredNumber("cf7-packer:layout:control-split", DEFAULT_LAYOUT.controlSplit, !isLayoutResizing);
  const [overviewSplit, setOverviewSplit] = useStoredNumber("cf7-packer:layout:overview-split", DEFAULT_LAYOUT.overviewSplit, !isLayoutResizing);
  const [layerSplit, setLayerSplit] = useStoredNumber("cf7-packer:layout:layer-split", DEFAULT_LAYOUT.layerSplit, !isLayoutResizing);
  const [detailSplit, setDetailSplit] = useStoredNumber("cf7-packer:layout:detail-split", DEFAULT_LAYOUT.detailSplit, !isLayoutResizing);

  // Event listeners + auto-scroll
  const { logEndRef } = usePackerEvents(api, logs, setLogs, setProgress, motionLevel);

  // R13: request token for concurrent fullReload cancellation
  const reloadTokenRef = useRef(0);

  // Unified reload: config + tags + preview (R2, R3, R9, R11, R13)
  const fullReload = useCallback(async () => {
    if (!api) return;
    const token = ++reloadTokenRef.current;

    const [cfg, newTags] = await Promise.all([
      api.loadConfig(),
      api.getTags()
    ]);
    if (reloadTokenRef.current !== token) return; // R13: stale

    setConfig(cfg);
    setTags(newTags);
    setSourceMode(cfg.mode);
    setOutputDir(cfg.outputDir);

    // R9: strict tag validation — no silent fallback
    if (cfg.mode === "git-tag") {
      const cfgTag = cfg.tag ?? "";
      if (!cfgTag || !newTags.includes(cfgTag)) {
        setSelectedTag(cfgTag);
        setPreviewFiles([]);
        setLayers([]);
        setLogs(prev => [...prev, {
          id: nextLogId(),
          event: {
            layer: "system", level: "warn",
            message: cfgTag
              ? `配置指定的 tag "${cfgTag}" 不在当前仓库中，预览已清空`
              : `git-tag 模式未指定 tag，预览已清空`
          }
        }]);
        return;
      }
      setSelectedTag(cfgTag);
    } else {
      if (newTags.length > 0 && !newTags.includes(selectedTag)) {
        setSelectedTag(newTags[newTags.length - 1]!);
      }
    }

    // R2: refresh preview
    if (reloadTokenRef.current !== token) return;
    try {
      const preview = await api.previewFiles(
        cfg.mode === "git-tag" ? { tag: cfg.tag! } : undefined
      );
      if (reloadTokenRef.current !== token) return;
      setPreviewFiles(preview.included);
      setLayers(preview.layers);
    } catch (err) {
      if (reloadTokenRef.current !== token) return;
      setLogs(prev => [...prev, {
        id: nextLogId(),
        event: { layer: "system", level: "error", message: `预览刷新失败: ${String(err)}` }
      }]);
    }
  }, [api, selectedTag, setLogs]);

  // R11: first-screen uses fullReload instead of separate useEffects
  useEffect(() => {
    void fullReload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [api]);

  // External config change auto-sync
  useEffect(() => {
    if (!api?.onConfigChanged) return;
    return api.onConfigChanged(() => {
      void fullReload();
    });
  }, [api, fullReload]);

  // Preview loading (kept for lightweight refresh, e.g. after exclude)
  // Shares reloadTokenRef with fullReload — last caller wins, stale results discarded
  const loadPreview = useCallback(async () => {
    if (!api || loadingPreview) return;
    const token = ++reloadTokenRef.current;
    setLoadingPreview(true);
    try {
      const preview = await api.previewFiles(
        sourceMode === "git-tag" ? { tag: selectedTag } : undefined
      );
      if (reloadTokenRef.current !== token) return;
      setPreviewFiles(preview.included);
      setLayers(preview.layers);
    } catch (err) {
      if (reloadTokenRef.current !== token) return;
      setLogs((prev) => [...prev, {
        id: nextLogId(),
        event: { layer: "system", level: "error", message: `预览失败: ${String(err)}` }
      }]);
    } finally {
      setLoadingPreview(false);
    }
  }, [api, loadingPreview, sourceMode, selectedTag, setLogs]);

  // Pack execution
  const { status, result, sfxBuilding, setSfxBuilding, runPack, handleCancel } = usePackExecution({
    api, sourceMode, selectedTag, outputDir,
    buildSfxAfterPack, sfxVersion, unityDataDir,
    previewFilesCount: previewFiles.length,
    loadPreview,
    setLogs, setProgress, setLayers, setPreviewFiles
  });

  // Scope navigation
  const {
    selectedScopeLayer, selectedScopePath,
    handleLayerScopeChange, handleTreemapScopeChange,
    handleScopeNavigate, handleResetScope, handleNavigateUp
  } = useScopeNavigation(previewFiles, setExpandedLayer, setDetailTab);

  // Actions
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

  const appClassName = [
    "app",
    `motion-${motionLevel}`,
    isLayoutResizing ? "is-layout-resizing" : "",
    isLayoutSettling ? "is-layout-settling" : ""
  ].filter(Boolean).join(" ");

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
  const hasPreview = previewFiles.length > 0;
  const showOverview = layers.length > 0;
  const hasActiveScope = Boolean(selectedScopeLayer || selectedScopePath);

  return (
    <div className={appClassName} style={motionStyle}>
      <Header
        config={config}
        motionPreference={motionPreference}
        onMotionChange={setMotionPreference}
        onResetLayout={handleResetLayout}
        onForceReload={() => void fullReload()}
      />

      <div className="control-shell" ref={controlShellRef}>
        <ControlPanel
          sourceMode={sourceMode}
          onSourceModeChange={setSourceMode}
          selectedTag={selectedTag}
          onSelectedTagChange={setSelectedTag}
          tags={tags}
          outputDir={outputDir}
          onOutputDirChange={setOutputDir}
          onPickDir={handlePickDir}
          buildSfxAfterPack={buildSfxAfterPack}
          onBuildSfxChange={setBuildSfxAfterPack}
          sfxVersion={sfxVersion}
          onSfxVersionChange={setSfxVersion}
          unityDataDir={unityDataDir}
          onUnityDataDirChange={setUnityDataDir}
          isRunning={isRunning}
          controlSplit={controlSplit}
        />
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
        <ActionPanel
          api={api}
          status={status}
          result={result}
          isRunning={isRunning}
          isTagModeWithoutTag={isTagModeWithoutTag}
          cannotExecute={cannotExecute}
          hasPreview={hasPreview}
          loadingPreview={loadingPreview}
          sfxBuilding={sfxBuilding}
          sfxVersion={sfxVersion}
          unityDataDir={unityDataDir}
          progress={progress}
          onRunPack={(dryRun) => void runPack(dryRun)}
          onLoadPreview={() => void loadPreview()}
          onCancel={handleCancel}
          onReveal={handleReveal}
          setSfxBuilding={setSfxBuilding}
          setLogs={setLogs}
          setProgress={setProgress}
        />
      </div>

      <div className="main-content" ref={mainContentRef}>
        {showOverview && (
          <OverviewPanel
            layers={layers}
            previewFiles={previewFiles}
            hasPreview={hasPreview}
            expandedLayer={expandedLayer}
            overviewSplit={overviewSplit}
            layerSplit={layerSplit}
            selectedScopeLayer={selectedScopeLayer}
            selectedScopePath={selectedScopePath}
            hasActiveScope={hasActiveScope}
            isLayoutResizing={isLayoutResizing}
            isLayoutSettling={isLayoutSettling}
            motionLevel={motionLevel}
            motionSettleMs={motionProfile.settleMs}
            activeResizeHandle={activeResizeHandle}
            overviewRef={overviewRef}
            loadPreview={loadPreview}
            onLayerScopeChange={handleLayerScopeChange}
            onTreemapScopeChange={handleTreemapScopeChange}
            onScopeNavigate={handleScopeNavigate}
            onNavigateUp={handleNavigateUp}
            onResetScope={handleResetScope}
            onBeginResize={beginResize}
            setLayerSplit={setLayerSplit}
          />
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
              <button className={`detail-tab ${detailTab === "config" ? "active" : ""}`}
                onClick={() => setDetailTab("config")}>⚙ 配置</button>
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
              {/* ConfigPanel always mounted to preserve editor draft state across tab switches */}
              <div style={{ display: detailTab === "config" ? "contents" : "none" }}>
                <ConfigPanel
                  api={api}
                  onSaveAndRefresh={fullReload}
                  isRunning={isRunning}
                />
              </div>
            </div>
          </section>
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

          <LogPanel logs={logs} logEndRef={logEndRef} />
        </div>
      </div>
    </div>
  );
}
