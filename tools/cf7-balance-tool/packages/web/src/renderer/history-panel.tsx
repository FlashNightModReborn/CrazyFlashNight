import { useMemo, useState } from "react";

import {
  filterReportHistoryEntries,
  getDefaultReportHistoryFilters,
  getReportHistoryCategoryLabel,
  type ReportHistoryEntry,
  type ReportHistoryFilter
} from "./report-history";

const TEXT = {
  title: "最近产物",
  subtitle: "reports 历史",
  hint: "这里展示 reports 目录下最近生成的文件，便于回看预览、批量写出和镜像 XML。",
  empty: "当前还没有可显示的产物历史。",
  updatedAt: "更新时间",
  size: "大小",
  copyPath: "复制路径",
  revealPath: "定位产物",
  refresh: "刷新历史"
} as const;

export function HistoryPanel({
  entries,
  canCopyPath,
  canRevealPath,
  canRefresh,
  onCopyPath,
  onRevealPath,
  onRefresh
}: {
  entries: ReportHistoryEntry[];
  canCopyPath: boolean;
  canRevealPath: boolean;
  canRefresh: boolean;
  onCopyPath: (targetPath: string) => Promise<void>;
  onRevealPath: (targetPath: string) => Promise<void>;
  onRefresh: () => Promise<void>;
}) {
  const [selectedFilter, setSelectedFilter] = useState<ReportHistoryFilter>("all");
  const filters = useMemo(() => getDefaultReportHistoryFilters(), []);
  const filteredEntries = filterReportHistoryEntries(entries, selectedFilter);

  return (
    <section className="detail-section">
      <div className="detail-section-header history-header">
        <div>
          <h4>{TEXT.title}</h4>
          <p className="panel-caption">{TEXT.subtitle}</p>
          <p className="panel-caption">{TEXT.hint}</p>
        </div>
        <button
          className="mini-button mini-button-ghost"
          disabled={!canRefresh}
          onClick={() => void onRefresh()}
          type="button"
        >
          {TEXT.refresh}
        </button>
      </div>

      <div className="history-filter-list">
        {filters.map((filter) => (
          <button
            className={`mini-button ${selectedFilter === filter ? "history-filter-active" : "mini-button-ghost"}`}
            key={filter}
            onClick={() => setSelectedFilter(filter)}
            type="button"
          >
            {getReportHistoryCategoryLabel(filter)}
          </button>
        ))}
      </div>

      {filteredEntries.length === 0 ? (
        <div className="empty-state">{TEXT.empty}</div>
      ) : (
        <div className="artifact-list">
          {filteredEntries.map((entry) => (
            <article className="artifact-card" key={`${entry.relativePath}:${entry.updatedAt}`}>
              <div className="detail-card-topline">
                <strong>{entry.relativePath}</strong>
                <span>{getReportHistoryCategoryLabel(entry.category)}</span>
              </div>
              <div className="artifact-meta">
                <span>
                  {TEXT.updatedAt}：{formatDateTime(entry.updatedAt)}
                </span>
                <span>
                  {TEXT.size}：{formatBytes(entry.size)}
                </span>
              </div>
              <div className="artifact-actions">
                <button
                  className="mini-button mini-button-ghost"
                  disabled={!canCopyPath}
                  onClick={() => void onCopyPath(entry.path)}
                  type="button"
                >
                  {TEXT.copyPath}
                </button>
                <button
                  className="mini-button"
                  disabled={!canRevealPath}
                  onClick={() => void onRevealPath(entry.path)}
                  type="button"
                >
                  {TEXT.revealPath}
                </button>
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
    minute: "2-digit"
  }).format(new Date(value));
}

function formatBytes(value: number): string {
  if (value < 1024) {
    return `${value} B`;
  }

  if (value < 1024 * 1024) {
    return `${new Intl.NumberFormat("zh-CN", { maximumFractionDigits: 1 }).format(
      value / 1024
    )} KB`;
  }

  return `${new Intl.NumberFormat("zh-CN", { maximumFractionDigits: 1 }).format(
    value / (1024 * 1024)
  )} MB`;
}
