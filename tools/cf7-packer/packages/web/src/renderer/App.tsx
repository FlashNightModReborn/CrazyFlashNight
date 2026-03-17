import { useState, useEffect, useCallback, useRef } from "react";
import type { PackerConfigSummary, PackResult, PackerLogEvent, PackerProgressEvent, LayerSummary } from "../shared/ipc-types.js";

type AppStatus = "idle" | "running" | "cancelled" | "done" | "error";

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

  const logEndRef = useRef<HTMLDivElement>(null);

  // 初始化
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

  // 订阅日志和进度
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

  // 自动滚动日志
  useEffect(() => {
    logEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [logs]);

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
    } catch (err) {
      setLogs((prev) => [...prev, {
        id: ++logId,
        event: { layer: "system", level: "error", message: String(err) }
      }]);
      setStatus("error");
    }
  }, [api, status, sourceMode, selectedTag, outputDir]);

  const handleCancel = useCallback(() => {
    api?.cancel();
  }, [api]);

  const handleReveal = useCallback(() => {
    if (result?.outputDir) {
      void api?.revealOutput(result.outputDir);
    }
  }, [api, result]);

  const handlePickDir = useCallback(async () => {
    if (!api) return;
    const picked = await api.pickOutputDir(outputDir || undefined);
    if (!picked.canceled && picked.path) {
      setOutputDir(picked.path);
    }
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
    ? Math.round((progress.current / progress.total) * 100)
    : 0;

  return (
    <div className="app">
      {/* 标题栏 */}
      <header className="header">
        <h1>CF7 发行打包工具</h1>
        {config && <span className="config-name">{config.name}</span>}
      </header>

      {/* 来源选择 */}
      <section className="section source-section">
        <div className="source-toggle">
          <label>
            <input
              type="radio"
              name="source"
              checked={sourceMode === "worktree"}
              onChange={() => setSourceMode("worktree")}
              disabled={isRunning}
            />
            工作区
          </label>
          <label>
            <input
              type="radio"
              name="source"
              checked={sourceMode === "git-tag"}
              onChange={() => setSourceMode("git-tag")}
              disabled={isRunning}
            />
            Git 标签
          </label>
          {sourceMode === "git-tag" && (
            <select
              value={selectedTag}
              onChange={(e) => setSelectedTag(e.target.value)}
              disabled={isRunning}
            >
              {tags.map((tag) => (
                <option key={tag} value={tag}>{tag}</option>
              ))}
            </select>
          )}
        </div>
        <div className="output-row">
          <label>输出:</label>
          <input
            type="text"
            value={outputDir}
            onChange={(e) => setOutputDir(e.target.value)}
            placeholder="./output/{version}"
            disabled={isRunning}
          />
          <button onClick={handlePickDir} disabled={isRunning} className="btn-small">浏览</button>
        </div>
      </section>

      {/* 层级预览 */}
      {layers.length > 0 && (
        <section className="section layer-section">
          <h2>层级统计</h2>
          <table className="layer-table">
            <thead>
              <tr><th>层级</th><th>文件数</th><th>排除</th></tr>
            </thead>
            <tbody>
              {layers.map((l) => (
                <tr key={l.name}>
                  <td>{l.name}</td>
                  <td className="num">{l.includedCount}</td>
                  <td className="num excluded">{l.excludedCount > 0 ? l.excludedCount : ""}</td>
                </tr>
              ))}
              <tr className="total-row">
                <td>合计</td>
                <td className="num">{layers.reduce((s, l) => s + l.includedCount, 0)}</td>
                <td className="num excluded">{layers.reduce((s, l) => s + l.excludedCount, 0)}</td>
              </tr>
            </tbody>
          </table>
        </section>
      )}

      {/* 操作按钮 */}
      <section className="section action-section">
        <div className="action-buttons">
          <button
            onClick={() => void runPack(true)}
            disabled={isRunning}
            className="btn btn-preview"
          >
            ▶ 预览（干跑）
          </button>
          <button
            onClick={() => void runPack(false)}
            disabled={isRunning}
            className="btn btn-execute"
          >
            ▶▶ 执行打包
          </button>
          {isRunning && (
            <button onClick={handleCancel} className="btn btn-cancel">
              ✕ 取消
            </button>
          )}
        </div>

        {/* 进度条 */}
        {isRunning && progress && progress.total > 0 && (
          <div className="progress-bar-container">
            <div className="progress-bar" style={{ width: `${progressPercent}%` }} />
            <span className="progress-text">{progressPercent}% {progress.current}/{progress.total}</span>
          </div>
        )}

        {/* 状态提示 */}
        {status === "done" && result && (
          <div className="status-done">
            打包完成: {result.copiedFiles} 文件, {formatSize(result.totalSize)}, 耗时 {result.duration}ms
            <button onClick={handleReveal} className="btn-small">打开输出目录</button>
          </div>
        )}
        {status === "cancelled" && (
          <div className="status-cancelled">已取消 ({result?.copiedFiles ?? 0} 文件已处理)</div>
        )}
        {status === "error" && result && (
          <div className="status-error">{result.errors.length} 个文件处理失败</div>
        )}
      </section>

      {/* 日志 */}
      <section className="section log-section">
        <h2>日志</h2>
        <div className="log-panel">
          {logs.map((entry) => (
            <div
              key={entry.id}
              className={`log-line log-${entry.event.level}`}
            >
              [{entry.event.level.toUpperCase()}] {entry.event.layer}: {entry.event.message}
            </div>
          ))}
          <div ref={logEndRef} />
        </div>
      </section>
    </div>
  );
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}
