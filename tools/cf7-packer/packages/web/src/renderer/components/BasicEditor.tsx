import { useState, useMemo, useCallback } from "react";
import { parseDocument, isSeq, isMap } from "yaml";
import type { Document, YAMLSeq } from "yaml";
import PatternListEditor from "./PatternListEditor.js";

interface BasicEditorProps {
  rawYaml: string;
  onChange: (yaml: string) => void;
  disabled?: boolean;
}

/** Parsed view of the config for display */
interface ConfigView {
  name: string;
  mode: string;
  tag: string;
  repoRoot: string;
  outputDir: string;
  globalExclude: string[];
  layers: Array<{
    name: string;
    description: string;
    source: string;
    include: string[];
    exclude: string[];
  }>;
  parseError: string | null;
}

/**
 * Parse YAML into plain JS objects for display.
 * Uses doc.toJSON() to get real JS arrays/strings — NOT raw YAML nodes.
 * (YAML nodes like YAMLSeq lack Array.prototype.map and crash React rendering.)
 */
function parseConfigView(rawYaml: string): ConfigView {
  const empty: ConfigView = {
    name: "", mode: "", tag: "", repoRoot: "", outputDir: "",
    globalExclude: [], layers: [], parseError: null
  };
  if (!rawYaml.trim()) return { ...empty, parseError: "配置为空" };

  try {
    const doc = parseDocument(rawYaml);
    if (!isMap(doc.contents)) return { ...empty, parseError: "配置根节点不是映射" };

    // Convert to plain JS — safe for React rendering
    const json = doc.toJSON() as Record<string, unknown>;
    const meta = (json.meta ?? {}) as Record<string, unknown>;
    const source = (json.source ?? {}) as Record<string, unknown>;
    const output = (json.output ?? {}) as Record<string, unknown>;

    const toStrArr = (v: unknown): string[] =>
      Array.isArray(v) ? v.map(String) : [];

    const rawLayers = Array.isArray(json.layers) ? json.layers as Record<string, unknown>[] : [];
    const layers = rawLayers.map(l => ({
      name: String(l.name ?? ""),
      description: String(l.description ?? ""),
      source: String(l.source ?? ""),
      include: toStrArr(l.include),
      exclude: toStrArr(l.exclude)
    }));

    return {
      name: String(meta.name ?? ""),
      mode: String(source.mode ?? ""),
      tag: String(source.tag ?? ""),
      repoRoot: String(source.repoRoot ?? ""),
      outputDir: String(output.dir ?? ""),
      globalExclude: toStrArr(json.globalExclude),
      layers,
      parseError: null
    };
  } catch (err) {
    return { ...empty, parseError: `YAML 解析失败: ${err instanceof Error ? err.message : String(err)}` };
  }
}

/**
 * Modifies the YAML AST and returns the new string.
 * All mutations go through parseDocument to preserve comments.
 */
function mutateYaml(
  rawYaml: string,
  mutator: (doc: Document) => void
): string {
  const doc = parseDocument(rawYaml);
  mutator(doc);
  return doc.toString();
}

/* ─── Help reference card ─── */

function PatternHelp() {
  const [open, setOpen] = useState(false);
  return (
    <div className="help-card">
      <button
        className="help-toggle"
        onClick={() => setOpen(!open)}
        type="button"
      >
        {open ? "- 收起帮助" : "? 匹配规则速查"}
      </button>
      {open && (
        <div className="help-body">
          <table className="help-table">
            <thead>
              <tr><th>写法</th><th>含义</th><th>举例</th></tr>
            </thead>
            <tbody>
              <tr>
                <td className="help-code">*</td>
                <td>匹配文件名中的任意字符</td>
                <td><code>*.xml</code> = 所有 .xml 文件</td>
              </tr>
              <tr>
                <td className="help-code">**</td>
                <td>匹配任意层级的子目录</td>
                <td><code>**/*.swf</code> = 所有目录下的 .swf 文件</td>
              </tr>
              <tr>
                <td className="help-code">**/*</td>
                <td>所有目录下的所有文件</td>
                <td>常用于「包含」规则，表示全部收集</td>
              </tr>
              <tr>
                <td className="help-code">目录名/**</td>
                <td>某个目录下的全部内容</td>
                <td><code>test/**</code> = test 目录下所有文件</td>
              </tr>
              <tr>
                <td className="help-code">*.后缀</td>
                <td>按文件类型匹配</td>
                <td><code>*.bak</code> = 所有备份文件</td>
              </tr>
            </tbody>
          </table>
          <p className="help-tip">
            打包流程：先用「包含」规则收集文件，再用「排除」规则过滤掉不要的，最后把所有层的文件合在一起输出。
          </p>
        </div>
      )}
    </div>
  );
}

export default function BasicEditor({ rawYaml, onChange, disabled }: BasicEditorProps) {
  const view = useMemo(() => parseConfigView(rawYaml), [rawYaml]);

  const handleGlobalExcludeAdd = useCallback((pattern: string) => {
    onChange(mutateYaml(rawYaml, (doc) => {
      let seq = doc.getIn(["globalExclude"]) as YAMLSeq | undefined;
      if (!seq || !isSeq(seq)) {
        doc.setIn(["globalExclude"], [pattern]);
      } else {
        seq.add(pattern);
      }
    }));
  }, [rawYaml, onChange]);

  const handleGlobalExcludeRemove = useCallback((index: number) => {
    onChange(mutateYaml(rawYaml, (doc) => {
      const seq = doc.getIn(["globalExclude"]) as YAMLSeq | undefined;
      if (seq && isSeq(seq)) {
        seq.delete(index);
      }
    }));
  }, [rawYaml, onChange]);

  const handleLayerAdd = useCallback((layerIndex: number, field: "include" | "exclude", pattern: string) => {
    onChange(mutateYaml(rawYaml, (doc) => {
      const path = ["layers", layerIndex, field];
      let seq = doc.getIn(path) as YAMLSeq | undefined;
      if (!seq || !isSeq(seq)) {
        doc.setIn(path, [pattern]);
      } else {
        seq.add(pattern);
      }
    }));
  }, [rawYaml, onChange]);

  const handleLayerRemove = useCallback((layerIndex: number, field: "include" | "exclude", patternIndex: number) => {
    onChange(mutateYaml(rawYaml, (doc) => {
      const seq = doc.getIn(["layers", layerIndex, field]) as YAMLSeq | undefined;
      if (seq && isSeq(seq)) {
        seq.delete(patternIndex);
      }
    }));
  }, [rawYaml, onChange]);

  const handleOutputDirChange = useCallback((value: string) => {
    onChange(mutateYaml(rawYaml, (doc) => {
      doc.setIn(["output", "dir"], value);
    }));
  }, [rawYaml, onChange]);

  if (view.parseError) {
    return (
      <div className="basic-editor-error">
        <p>{view.parseError}</p>
        <p className="basic-editor-hint">请切换到「高级」模式手动修复 YAML</p>
      </div>
    );
  }

  return (
    <div className="basic-editor">
      {/* Help reference */}
      <PatternHelp />

      {/* Meta info */}
      <div className="basic-section basic-meta">
        <div className="basic-meta-row">
          <span className="basic-label">名称</span>
          <span className="basic-value">{view.name}</span>
        </div>
        <div className="basic-meta-row">
          <span className="basic-label">模式</span>
          <span className="basic-value">
            {view.mode === "git-tag"
              ? `git-tag — 打包指定版本 (${view.tag || "未指定 tag"})`
              : "worktree — 打包当前工作区文件"}
          </span>
        </div>
        <div className="basic-meta-row">
          <span className="basic-label">输出</span>
          <input
            className="basic-input"
            value={view.outputDir}
            onChange={(e) => handleOutputDirChange(e.target.value)}
            disabled={disabled}
          />
          <span className="basic-field-hint">打包结果保存到这个目录</span>
        </div>
      </div>

      {/* Global exclude */}
      <div className="basic-section">
        <h3 className="basic-section-title">全局排除</h3>
        <p className="basic-section-desc">
          匹配这些规则的文件不会被打包，无论它属于哪个层。适合排除临时文件、系统文件等。
        </p>
        <PatternListEditor
          patterns={view.globalExclude}
          onAdd={handleGlobalExcludeAdd}
          onRemove={handleGlobalExcludeRemove}
          disabled={disabled}
          placeholder="输入规则后按回车添加，例: *.tmp"
        />
        {view.globalExclude.length === 0 && (
          <span className="basic-empty-hint">无全局排除规则</span>
        )}
      </div>

      {/* Layers */}
      {view.layers.length > 0 && (
        <p className="basic-section-desc basic-layers-intro">
          下方每个「层」负责收集一类文件。打包时所有层的文件会合并输出。
        </p>
      )}
      {view.layers.map((layer, li) => (
        <div key={li} className="basic-section basic-layer-card">
          <h3 className="basic-section-title">
            <span className="basic-layer-name">{layer.name}</span>
            <span className="basic-layer-source">
              来源: {layer.source}
            </span>
          </h3>
          {layer.description && (
            <p className="basic-layer-desc">{layer.description}</p>
          )}
          <div className="basic-layer-field">
            <h4 className="basic-field-label">
              包含 (include)
              <span className="basic-field-hint">— 从来源目录中收集哪些文件</span>
            </h4>
            <PatternListEditor
              patterns={layer.include}
              onAdd={(p) => handleLayerAdd(li, "include", p)}
              onRemove={(i) => handleLayerRemove(li, "include", i)}
              disabled={disabled}
              placeholder="输入规则后按回车添加，例: **/*"
            />
            {layer.include.length === 0 && (
              <span className="basic-empty-hint">未设置包含规则 — 不会收集任何文件</span>
            )}
          </div>
          <div className="basic-layer-field">
            <h4 className="basic-field-label">
              排除 (exclude)
              <span className="basic-field-hint">— 从已收集的文件中去掉哪些</span>
            </h4>
            <PatternListEditor
              patterns={layer.exclude}
              onAdd={(p) => handleLayerAdd(li, "exclude", p)}
              onRemove={(i) => handleLayerRemove(li, "exclude", i)}
              disabled={disabled}
              placeholder="输入规则后按回车添加，例: *.bak"
            />
            {layer.exclude.length === 0 && (
              <span className="basic-empty-hint">无排除规则 — 收集到的文件全部保留</span>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
