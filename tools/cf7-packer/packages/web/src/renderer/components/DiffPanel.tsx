import { useState, useCallback } from "react";
import type { DiffResult } from "../../shared/ipc-types.js";

interface Props {
  tags: string[];
  onDiff: (baseTag: string | null, targetTag: string | null) => Promise<DiffResult>;
}

export default function DiffPanel({ tags, onDiff }: Props) {
  const [baseTag, setBaseTag] = useState<string>(tags[tags.length - 1] ?? "");
  const [targetTag, setTargetTag] = useState<string>("__worktree__");
  const [result, setResult] = useState<DiffResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [showAdded, setShowAdded] = useState(true);
  const [showRemoved, setShowRemoved] = useState(true);
  const [showModified, setShowModified] = useState(true);

  const handleDiff = useCallback(async () => {
    setLoading(true);
    try {
      const base = baseTag === "__worktree__" ? null : baseTag;
      const target = targetTag === "__worktree__" ? null : targetTag;
      const r = await onDiff(base, target);
      setResult(r);
    } finally {
      setLoading(false);
    }
  }, [baseTag, targetTag, onDiff]);

  const options = [
    { value: "__worktree__", label: "当前工作区" },
    ...tags.map((t) => ({ value: t, label: t }))
  ];

  return (
    <div className="diff-panel">
      <div className="diff-controls">
        <div className="diff-select-group">
          <label title="对比的起点——旧版本">基线:</label>
          <select value={baseTag} onChange={(e) => setBaseTag(e.target.value)}>
            {options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
          </select>
        </div>
        <span className="diff-arrow" title="从基线到目标，查看有什么变化">→</span>
        <div className="diff-select-group">
          <label title="对比的终点——新版本或当前文件">目标:</label>
          <select value={targetTag} onChange={(e) => setTargetTag(e.target.value)}>
            {options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
          </select>
        </div>
        <button className="btn-small" onClick={() => void handleDiff()} disabled={loading}
          title="对比两个版本之间文件的增删改情况">
          {loading ? "对比中..." : "执行对比"}
        </button>
      </div>

      {result && (
        <div className="diff-result">
          <div className="diff-summary" title="点击颜色标签可显示/隐藏对应类别">
            <span className="diff-stat diff-added-stat" onClick={() => setShowAdded(!showAdded)}
              title="目标版本中新出现的文件">
              +{result.added.length} 新增
            </span>
            <span className="diff-stat diff-removed-stat" onClick={() => setShowRemoved(!showRemoved)}
              title="目标版本中被删除的文件">
              -{result.removed.length} 删除
            </span>
            {result.modified.length > 0 && (
              <span className="diff-stat diff-modified-stat" onClick={() => setShowModified(!showModified)}>
                ~{result.modified.length} 修改
              </span>
            )}
            <span className="diff-stat diff-unchanged-stat">
              {result.unchanged} 不变
            </span>
          </div>
          <div className="diff-file-list">
            {showAdded && result.added.map((f) => (
              <div key={f} className="diff-file diff-file-added">+ {f}</div>
            ))}
            {showModified && result.modified.map((f) => (
              <div key={f} className="diff-file diff-file-modified">~ {f}</div>
            ))}
            {showRemoved && result.removed.map((f) => (
              <div key={f} className="diff-file diff-file-removed">- {f}</div>
            ))}
            {result.added.length === 0 && result.removed.length === 0 && result.modified.length === 0 && (
              <div className="diff-file diff-no-changes">无差异</div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
