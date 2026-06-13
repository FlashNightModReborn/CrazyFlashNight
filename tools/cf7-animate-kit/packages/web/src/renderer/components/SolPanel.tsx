import { useCallback, useMemo, useState, useRef } from "react";
import type { AnkitApi, SolDocument, SolSavePreview, SolEdit } from "../../shared/ipc-types.js";
import type { MotionLevel, MotionProfile } from "./motion-utils.js";
import { type LayoutController, useResetLayoutSignal } from "../hooks/useLayoutResize.js";
import { useStoredNumber } from "../hooks/useLocalStorage.js";
import SolTreeView from "./SolTreeView.js";
import SolTreemap from "./SolTreemap.js";
import ResizeHandle from "./ResizeHandle.js";
import { filterTree, leafCount, descendantCount } from "./sol-tree-utils.js";

interface Props {
  api: AnkitApi;
  motionLevel: MotionLevel;
  motionProfile: MotionProfile;
  layout: LayoutController;
}

type EditMap = Map<string, string | number | boolean | null>;

const SPLIT_KEY = "ankit:sol:split";
const DEFAULT_SPLIT = 0.56;

/**
 * Tab B — "SOL 检视/编辑". Two resizable panes: the AMF0 tree (left, with a
 * type-badge per node, filter box and expand/collapse-all) and a detail pane
 * (right) carrying a read-only D3 treemap of the structure plus the
 * preview-diff → Save(backup) flow. Saving while the game runs can corrupt the
 * file; we warn but do not block.
 */
export default function SolPanel({ api, motionLevel, motionProfile, layout }: Props) {
  const [doc, setDoc] = useState<SolDocument | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [edits, setEdits] = useState<EditMap>(new Map());
  const [preview, setPreview] = useState<SolSavePreview | null>(null);
  const [savedNote, setSavedNote] = useState<string | null>(null);

  const [query, setQuery] = useState("");
  const [expandSignal, setExpandSignal] = useState(0);
  const [focusPath, setFocusPath] = useState<string | null>(null);

  const splitRef = useRef<HTMLDivElement>(null);
  const [split, setSplit] = useStoredNumber(SPLIT_KEY, DEFAULT_SPLIT, !layout.isLayoutResizing);
  useResetLayoutSignal(useCallback(() => setSplit(DEFAULT_SPLIT), [setSplit]));

  const resetTransient = useCallback(() => {
    setPreview(null);
    setSavedNote(null);
  }, []);

  const open = useCallback(async () => {
    setBusy(true);
    setError(null);
    resetTransient();
    try {
      const r = await api.openSol();
      if (r.canceled) return;
      if (r.error || !r.doc) {
        setError(r.error ?? "无法解析该 .sol 文件");
        return;
      }
      setDoc(r.doc);
      setEdits(new Map());
      setFocusPath(null);
      setQuery("");
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }, [api, resetTransient]);

  const onEdit = useCallback(
    (path: string, value: string | number | boolean | null) => {
      setEdits((prev) => {
        const next = new Map(prev);
        next.set(path, value);
        return next;
      });
      resetTransient();
    },
    [resetTransient]
  );

  const editList = useMemo<SolEdit[]>(
    () => Array.from(edits.entries()).map(([path, value]) => ({ path, value })),
    [edits]
  );

  const discardEdits = useCallback(() => {
    setEdits(new Map());
    resetTransient();
  }, [resetTransient]);

  const runPreview = useCallback(async () => {
    if (!doc || editList.length === 0) return;
    setBusy(true);
    setError(null);
    setSavedNote(null);
    try {
      const p = await api.previewSolSave({ filePath: doc.filePath, edits: editList, apply: false });
      setPreview(p);
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }, [api, doc, editList]);

  const save = useCallback(async () => {
    if (!doc || editList.length === 0) return;
    setBusy(true);
    setError(null);
    try {
      const r = await api.saveSol({ filePath: doc.filePath, edits: editList, apply: true });
      if (!r.ok) {
        setError(r.error ?? "保存失败");
        return;
      }
      if (r.doc) setDoc(r.doc);
      setEdits(new Map());
      setPreview(null);
      setSavedNote(
        r.backupPath ? `已保存。备份: ${r.backupPath}` : "已保存（无需备份：原文件不存在）。"
      );
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }, [api, doc, editList]);

  const handleSelect = useCallback((path: string) => setFocusPath(path), []);

  const editCount = edits.size;

  const filter = useMemo(
    () => (doc ? filterTree(doc.tree, query) : { matched: new Set<string>(), ancestors: new Set<string>() }),
    [doc, query]
  );
  const filtering = query.trim().length > 0;

  const topStats = useMemo(() => {
    if (!doc) return null;
    let leaves = 0;
    let nodes = 0;
    for (const n of doc.tree) {
      leaves += leafCount(n);
      nodes += 1 + descendantCount(n);
    }
    return { leaves, nodes };
  }, [doc]);

  if (!doc) {
    return (
      <div className="tab-body sol sol-empty">
        <section className="card motion-surface">
          <div className="card-head">
            <h2>SharedObject (.sol)</h2>
            <button className="btn btn-primary" onClick={() => void open()} disabled={busy}>
              {busy ? "打开中…" : "打开 .sol"}
            </button>
          </div>
          <div className="warn-note">
            ⚠ 游戏运行时切勿写入：Flash 退出时会用内存中的 SOL 覆盖磁盘，你的编辑将丢失或损坏存档。请在游戏关闭后保存。
          </div>
          {error && <div className="error-bar">⚠ {error}</div>}
          <div className="empty-hint">尚未打开存档。选择一个 .sol 文件以检视其 AMF0 结构。</div>
        </section>
      </div>
    );
  }

  return (
    <div className="sol-split" ref={splitRef}>
      {/* ---- Left: tree ---- */}
      <section
        className="section sol-tree-pane motion-surface motion-split-pane"
        style={{ flexBasis: `${split * 100}%`, flexGrow: 0, flexShrink: 0 }}
      >
        <div className="sol-pane-head">
          <div className="sol-pane-title">
            <h2>数据树</h2>
            {editCount > 0
              ? <span className="edit-badge">{editCount} 处待保存</span>
              : <span className="muted">无修改</span>}
          </div>
          {filtering && (
            <span className="sol-filter-count">
              {filter.matched.size} 项匹配
            </span>
          )}
        </div>

        <div className="sol-toolbar">
          <input
            className="sol-search"
            type="text"
            placeholder="筛选键 / 值 / 类型…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          {filtering && (
            <button className="btn-small btn-ghost" onClick={() => setQuery("")} title="清除筛选">
              清除
            </button>
          )}
          <span className="sol-toolbar-spacer" />
          <button className="btn-small" onClick={() => setExpandSignal((s) => (s + 2) - (s % 2))}
            title="展开全部节点">
            展开全部
          </button>
          <button className="btn-small" onClick={() => setExpandSignal((s) => (s + 2) - (s % 2) + 1)}
            title="折叠全部节点">
            折叠全部
          </button>
          <button className="btn-small btn-primary" onClick={() => void open()} disabled={busy}>
            重新打开
          </button>
        </div>

        <div className="sol-tree-body">
          {doc.tree.length === 0 ? (
            <div className="empty-hint">该 SOL 没有可显示的数据。</div>
          ) : (
            doc.tree.map((node) => (
              <SolTreeView
                key={node.path}
                node={node}
                depth={0}
                edits={edits}
                onEdit={onEdit}
                onSelect={handleSelect}
                focusPath={focusPath}
                query={filtering ? query : ""}
                matched={filter.matched}
                ancestors={filter.ancestors}
                expandSignal={expandSignal}
              />
            ))
          )}
        </div>
      </section>

      <ResizeHandle
        orientation="vertical"
        title="拖动调整数据树与详情宽度"
        isActive={layout.activeResizeHandle === "sol"}
        onStartResize={(clientX, clientY) => layout.beginResize(clientX, clientY, {
          handleId: "sol",
          container: splitRef,
          axis: "x",
          min: 0.32,
          max: 0.74,
          setValue: setSplit
        })}
      />

      {/* ---- Right: detail ---- */}
      <div className="sol-detail-pane">
        <section className="section sol-meta-card motion-surface">
          <div className="card-head">
            <h2>{doc.meta.name || "(unnamed)"}</h2>
            <span className="muted">{doc.meta.fileSize} B</span>
          </div>
          <div className="sol-meta">
            <span className="sol-meta-path" title={doc.filePath}>{doc.filePath}</span>
            <span>amfVersion: {doc.meta.amfVersion}</span>
            <span>顶层元素: {doc.meta.elementCount}</span>
            <span>叶子: {doc.meta.leafCount}</span>
            {topStats && <span>节点: {topStats.nodes}</span>}
          </div>
          {error && <div className="error-bar">⚠ {error}</div>}
          {savedNote && <div className="ok-bar">✓ {savedNote}</div>}
        </section>

        <section className="section sol-treemap-card motion-surface">
          <SolTreemap
            tree={doc.tree}
            focusPath={focusPath}
            onPick={handleSelect}
            motionLevel={motionLevel}
            motionDurationMs={motionProfile.settleMs}
          />
        </section>

        <section className="section sol-save-card motion-surface">
          <div className="card-head">
            <h2>保存</h2>
            <div className="warn-inline" title="游戏运行时保存会损坏存档">⚠ 游戏关闭后再保存</div>
          </div>
          <div className="btn-row">
            <button className="btn btn-primary" onClick={() => void runPreview()} disabled={busy || editCount === 0}>
              预览差异
            </button>
            <button
              className="btn btn-apply"
              onClick={() => void save()}
              disabled={busy || editCount === 0 || (preview !== null && !preview.ok)}
              title="先备份再写入"
            >
              保存 (先备份)
            </button>
            <button className="btn btn-ghost" onClick={discardEdits} disabled={busy || editCount === 0}>
              放弃修改
            </button>
          </div>

          {preview && (
            <div className="sol-preview">
              <div className={`op-heading ${preview.ok ? "op-plan" : "op-error"}`}>
                <span className="op-heading-tag">{preview.ok ? "差异预览" : "存在错误"}</span>
                {preview.error && <span className="op-summary">{preview.error}</span>}
                {!preview.error && <span className="op-summary">写入后大小: {preview.newFileSize} B</span>}
              </div>
              <table className="op-table">
                <thead>
                  <tr><th>路径</th><th>原值</th><th>新值</th></tr>
                </thead>
                <tbody>
                  {preview.diff.map((d, i) => (
                    <tr key={`${d.path}-${i}`} className={d.error ? "diff-row-error" : ""}>
                      <td className="op-path" title={d.path}>{d.path}</td>
                      <td className="diff-old">{d.oldValue}</td>
                      <td className="diff-new">
                        {d.newValue}
                        {d.error && <span className="diff-err"> · {d.error}</span>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      </div>
    </div>
  );
}
