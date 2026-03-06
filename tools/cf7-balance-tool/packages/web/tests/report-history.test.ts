import { describe, expect, it } from "vitest";

import {
  filterReportHistoryEntries,
  getDefaultReportHistoryFilters,
  getReportHistoryCategoryLabel,
  type ReportHistoryEntry
} from "../src/renderer/report-history";

const entries: ReportHistoryEntry[] = [
  {
    path: "C:/repo/reports/manual-updates.generated.json",
    relativePath: "reports/manual-updates.generated.json",
    category: "payload",
    updatedAt: "2026-03-06T07:20:00.000Z",
    size: 128
  },
  {
    path: "C:/repo/reports/batch-preview-report.json",
    relativePath: "reports/batch-preview-report.json",
    category: "preview-report",
    updatedAt: "2026-03-06T07:22:00.000Z",
    size: 256
  },
  {
    path: "C:/repo/reports/batch-output/data/items/test.xml",
    relativePath: "reports/batch-output/data/items/test.xml",
    category: "mirrored-xml",
    updatedAt: "2026-03-06T07:23:00.000Z",
    size: 512
  }
];

describe("filterReportHistoryEntries", () => {
  it("returns all entries for the all filter", () => {
    expect(filterReportHistoryEntries(entries, "all")).toHaveLength(3);
  });

  it("returns only entries that match the selected category", () => {
    const filtered = filterReportHistoryEntries(entries, "mirrored-xml");

    expect(filtered).toHaveLength(1);
    expect(filtered[0]?.relativePath).toContain("batch-output");
  });
});

describe("getReportHistoryCategoryLabel", () => {
  it("maps categories to Chinese labels", () => {
    expect(getReportHistoryCategoryLabel("preview-report")).toBe("preview 报告");
    expect(getReportHistoryCategoryLabel("other")).toBe("其他文件");
  });
});

describe("getDefaultReportHistoryFilters", () => {
  it("keeps a stable filter order for the UI", () => {
    expect(getDefaultReportHistoryFilters()).toEqual([
      "all",
      "payload",
      "preview-report",
      "apply-report",
      "mirrored-xml",
      "json",
      "other"
    ]);
  });
});