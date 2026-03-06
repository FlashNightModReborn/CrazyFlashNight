import { useCallback, useEffect, useState } from "react";

interface ChangelogEntry {
  timestamp: string;
  action: string;
  inputFile: string;
  summary: Record<string, unknown>;
  outputDir: string | null;
}

const TEXT = {
  title: "操作日志",
  subtitle: "changelog.jsonl",
  empty: "暂无操作日志。",
  refresh: "刷新"
} as const;

const ACTION_LABELS: Record<string, string> = {
  "batch-set": "批量写入",
  "batch-preview": "批量预览",
  "save-payload": "保存 payload"
};

export function ChangelogPanel() {
  const [entries, setEntries] = useState<ChangelogEntry[]>([]);
  const [loading, setLoading] = useState(false);
  const canLoad = typeof window.cf7Balance?.getChangelog === "function";

  const refresh = useCallback(async () => {
    if (!window.cf7Balance?.getChangelog) return;
    setLoading(true);
    try {
      const result = await window.cf7Balance.getChangelog();
      setEntries(result);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  return (
    <section className="detail-section">
      <div className="detail-section-header history-header">
        <div>
          <h4>{TEXT.title}</h4>
          <p className="panel-caption">{TEXT.subtitle}</p>
        </div>
        <button
          className="mini-button mini-button-ghost"
          disabled={!canLoad || loading}
          onClick={() => void refresh()}
          type="button"
        >
          {TEXT.refresh}
        </button>
      </div>
      {entries.length === 0 ? (
        <div className="empty-state">{TEXT.empty}</div>
      ) : (
        <div className="artifact-list">
          {entries.map((entry, i) => (
            <article className="artifact-card" key={`${entry.timestamp}-${i}`}>
              <div className="detail-card-topline">
                <strong>{ACTION_LABELS[entry.action] ?? entry.action}</strong>
                <span>{formatDateTime(entry.timestamp)}</span>
              </div>
              <div className="artifact-meta">
                {entry.summary.total != null && (
                  <span>共 {String(entry.summary.total)} 项</span>
                )}
                {entry.summary.applied != null && (
                  <span>已应用 {String(entry.summary.applied)} 项</span>
                )}
                {entry.outputDir && (
                  <span title={entry.outputDir}>输出目录已设置</span>
                )}
              </div>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}

function formatDateTime(value: string): string {
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  }).format(new Date(value));
}
