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
    rawYaml, isDirty, hasExternalConflict, errors, loading,
    loadFromDisk, saveAndRefresh, setRawYaml, dismissConflict
  } = useConfigEditor(api, onSaveAndRefresh);

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

      {hasExternalConflict && (
        <div className="config-conflict-bar">
          <span>配置文件已被外部修改</span>
          <button className="btn-small" onClick={() => void loadFromDisk()}>
            重新加载
          </button>
          <button className="btn-small" onClick={dismissConflict}>
            保留本地修改
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
