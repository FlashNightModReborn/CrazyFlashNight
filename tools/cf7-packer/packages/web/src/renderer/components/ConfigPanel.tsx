import { useState } from "react";
import { useConfigEditor } from "../hooks/useConfigEditor.js";
import BasicEditor from "./BasicEditor.js";
import type { PackerIpcApi } from "../../shared/ipc-types.js";

type EditorMode = "basic" | "advanced";

interface ConfigPanelProps {
  api: PackerIpcApi | undefined;
  onSaveAndRefresh: () => Promise<void>;
  isRunning: boolean;
}

export default function ConfigPanel({ api, onSaveAndRefresh, isRunning }: ConfigPanelProps) {
  const [editorMode, setEditorMode] = useState<EditorMode>("basic");
  const {
    rawYaml, isDirty, conflictSource, errors, loading,
    loadFromDisk, saveAndRefresh, setRawYaml, dismissConflict
  } = useConfigEditor(api, onSaveAndRefresh);

  const isInternal = conflictSource === "internal";

  return (
    <div className="config-panel">
      <div className="config-toolbar">
        <div className="config-toolbar-left">
          <div className="config-mode-toggle" role="group" aria-label="编辑模式">
            <button
              className={`config-mode-btn ${editorMode === "basic" ? "active" : ""}`}
              onClick={() => setEditorMode("basic")}
            >
              基础
            </button>
            <button
              className={`config-mode-btn ${editorMode === "advanced" ? "active" : ""}`}
              onClick={() => setEditorMode("advanced")}
            >
              高级
            </button>
          </div>
          {isDirty && <span className="config-dirty-badge">* 未保存</span>}
          {loading && <span className="config-loading">加载中...</span>}
        </div>
        <div className="config-toolbar-right">
          <button
            className="btn-small"
            onClick={() => void loadFromDisk()}
            disabled={loading}
          >
            重置
          </button>
          <button
            className="btn-small config-save-btn"
            onClick={() => void saveAndRefresh()}
            disabled={loading || isRunning || !isDirty}
            title={isRunning ? "打包运行中，无法保存" : !isDirty ? "无修改" : "保存并刷新预览"}
          >
            保存并刷新预览
          </button>
        </div>
      </div>

      {conflictSource && (
        <div className={`config-conflict-bar ${isInternal ? "config-conflict-internal" : ""}`}>
          <span>
            {isInternal
              ? "你刚才的操作（如排除文件）已修改了配置文件"
              : "配置文件已被外部修改"}
          </span>
          <button className="btn-small" onClick={() => void loadFromDisk()}>
            {isInternal ? "加载最新版本" : "重新加载"}
          </button>
          <button
            className="btn-small"
            onClick={dismissConflict}
            title={isInternal
              ? "保留你正在编辑的内容，刚才的排除操作结果将在你下次保存时被覆盖"
              : "保留你正在编辑的内容，磁盘上的修改将在你下次保存时被覆盖"}
          >
            保留编辑中的内容
          </button>
        </div>
      )}

      {errors.length > 0 && (
        <div className="config-errors">
          {errors.map((err, i) => (
            <div key={i} className="config-error-item">
              {err.path && <span className="config-error-path">{err.path}: </span>}
              {err.message}
            </div>
          ))}
        </div>
      )}

      {editorMode === "basic" ? (
        <BasicEditor
          rawYaml={rawYaml}
          onChange={setRawYaml}
          disabled={loading}
        />
      ) : (
        <textarea
          className="config-editor"
          value={rawYaml}
          onChange={(e) => setRawYaml(e.target.value)}
          spellCheck={false}
          disabled={loading}
        />
      )}
    </div>
  );
}
