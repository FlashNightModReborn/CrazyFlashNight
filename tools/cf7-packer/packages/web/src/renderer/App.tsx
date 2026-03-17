import { useState, useEffect, useCallback, useRef } from "react";
import type {
  PackerConfigSummary, PackResult, PackerLogEvent,
  PackerProgressEvent, LayerSummary, FileEntry, DiffResult
} from "../shared/ipc-types.js";
import FileTreePanel from "./components/FileTreePanel.js";
import TreemapChart from "./components/TreemapChart.js";
import DiffPanel from "./components/DiffPanel.js";

type AppStatus = "idle" | "running" | "cancelled" | "done" | "error";
type DetailTab = "tree" | "diff";

interface LogEntry {
  id: number;
  event: PackerLogEvent;
}

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

  const logEndRef = useRef<HTMLDivElement>(null);

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
      setLogs((prev) => [...prev.slice(-500), { id: ++logId, event }]);
    });
    const offProgress = api.onProgress((event) => {
      setProgress(event);
    });
    return () => { offLog(); offProgress(); };
  }, [api]);

  useEffect(() => {
    logEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [logs]);

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

  if (!isElectron) {
    return (
      <div className="app-placeholder">
        <h1>CF7 发行打包工具</h1>
        <p>请通过 launch.bat 启动 Electron 环境</p>
      </div>
    );
  }

  const isRunning = status === "running";
  const progressPercent = progress && progress.total > 0
    ? Math.round((progress.current / progress.total) * 100) : 0;
  const hasPreview = previewFiles.length > 0;
  const layerNames = layers.map((l) => l.name);

  return (
    <div className="app">
      <header className="header">
        <h1>CF7 发行打包工具</h1>
        {config && <span className="config-name">{config.name}</span>}
      </header>

      <section className="section source-section">
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

      <section className="section action-section">
        <div className="action-buttons">
          <button onClick={() => void runPack(true)} disabled={isRunning} className="btn btn-preview">
            ▶ 预览（干跑）
          </button>
          <button onClick={() => void runPack(false)} disabled={isRunning} className="btn btn-execute">
            ▶▶ 执行打包
          </button>
          {!hasPreview && !isRunning && (
            <button onClick={() => void loadPreview()} disabled={loadingPreview} className="btn btn-browse">
              {loadingPreview ? "加载中..." : "📂 浏览文件"}
            </button>
          )}
          {isRunning && (
            <button onClick={handleCancel} className="btn btn-cancel">✕ 取消</button>
          )}
        </div>
        {isRunning && progress && progress.total > 0 && (
          <div className="progress-bar-container">
            <div className="progress-bar" style={{ width: `${progressPercent}%` }} />
            <span className="progress-text">{progressPercent}% {progress.current}/{progress.total}</span>
          </div>
        )}
        {status === "done" && result && (
          <div className="status-done">
            打包完成: {result.copiedFiles} 文件, {formatSize(result.totalSize)}, 耗时 {result.duration}ms
            <button onClick={handleReveal} className="btn-small">打开输出目录</button>
            {!result.cancelled && result.mode === "execute" && (
              <button
                className="btn-small"
                disabled={sfxBuilding}
                onClick={async () => {
                  if (!api) return;
                  setSfxBuilding(true);
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

      {layers.length > 0 && (
        <div className="layer-sunburst-split">
          <section className="section layer-section">
            <h2>层级统计 {hasPreview && <span className="layer-hint">（点击行查看详情）</span>}</h2>
            <table className="layer-table">
              <thead><tr><th>层级</th><th>文件数</th><th>排除</th></tr></thead>
              <tbody>
                {layers.map((l) => (
                  <tr key={l.name}
                    className={`${hasPreview ? "layer-clickable" : ""} ${expandedLayer === l.name ? "layer-active" : ""}`}
                    onClick={() => { if (!hasPreview) return; setExpandedLayer(expandedLayer === l.name ? null : l.name); setDetailTab("tree"); }}>
                    <td>{l.name}</td>
                    <td className="num">{l.includedCount}</td>
                    <td className="num excluded">{l.excludedCount > 0 ? l.excludedCount : ""}</td>
                  </tr>
                ))}
                <tr className={`total-row ${hasPreview ? "layer-clickable" : ""} ${expandedLayer === null && hasPreview ? "layer-active" : ""}`}
                  onClick={() => { if (hasPreview) { setExpandedLayer(null); setDetailTab("tree"); } }}>
                  <td>合计</td>
                  <td className="num">{layers.reduce((s, l) => s + l.includedCount, 0)}</td>
                  <td className="num excluded">{layers.reduce((s, l) => s + l.excludedCount, 0)}</td>
                </tr>
              </tbody>
            </table>
          </section>
          {hasPreview && (
            <section className="section treemap-inline-section">
              <TreemapChart files={previewFiles} layers={layerNames} />
            </section>
          )}
        </div>
      )}

      {/* 下半区：详情面板（左）+ 日志（右）左右分栏 */}
      <div className="bottom-split">
        {(hasPreview || tags.length > 0) && (
          <section className="section detail-section">
            <div className="detail-tabs">
              {hasPreview && (
                <button className={`detail-tab ${detailTab === "tree" ? "active" : ""}`}
                  onClick={() => setDetailTab("tree")}>📁 文件树</button>
              )}
              <button className={`detail-tab ${detailTab === "diff" ? "active" : ""}`}
                onClick={() => setDetailTab("diff")}>⚡ 差异对比</button>
            </div>
            <div className="detail-body">
              {detailTab === "tree" && hasPreview && <FileTreePanel files={previewFiles} layerFilter={expandedLayer} />}
              {detailTab === "diff" && (
                <DiffPanel
                  tags={tags}
                  onDiff={async (baseTag, targetTag) => api!.diffFiles({ baseTag, targetTag })}
                />
              )}
            </div>
          </section>
        )}

        <section className="section log-section">
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
  );
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}
