export type ReportHistoryCategory =
  | "payload"
  | "preview-report"
  | "apply-report"
  | "mirrored-xml"
  | "json"
  | "other";

export type ReportHistoryFilter = "all" | ReportHistoryCategory;

export interface ReportHistoryEntry {
  path: string;
  relativePath: string;
  category: ReportHistoryCategory;
  updatedAt: string;
  size: number;
}

export function filterReportHistoryEntries(
  entries: ReportHistoryEntry[],
  selectedFilter: ReportHistoryFilter
): ReportHistoryEntry[] {
  if (selectedFilter === "all") {
    return entries;
  }

  return entries.filter((entry) => entry.category === selectedFilter);
}

export function getReportHistoryCategoryLabel(category: ReportHistoryFilter): string {
  switch (category) {
    case "all":
      return "全部";
    case "payload":
      return "手动 JSON";
    case "preview-report":
      return "preview 报告";
    case "apply-report":
      return "batch-set 报告";
    case "mirrored-xml":
      return "镜像 XML";
    case "json":
      return "其他 JSON";
    default:
      return "其他文件";
  }
}

export function getDefaultReportHistoryFilters(): ReportHistoryFilter[] {
  return [
    "all",
    "payload",
    "preview-report",
    "apply-report",
    "mirrored-xml",
    "json",
    "other"
  ];
}
