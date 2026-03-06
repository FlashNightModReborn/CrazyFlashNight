import { describe, expect, it } from "vitest";

import {
  buildBatchUpdatesPayload,
  createEditorRows,
  filterEditorRows,
  restoreAllRowsToOriginal,
  summarizeEditorRows,
  updateRowStagedValue,
  type BatchPreviewReport
} from "../src/renderer/editor-model";

const sampleReport: BatchPreviewReport = {
  projectConfigPath: "C:/repo/tools/cf7-balance-tool/project.json",
  generatedAt: "2026-03-06T04:06:59.242Z",
  operations: 2,
  changedValues: 2,
  files: [
    {
      sourceFile: "C:/repo/data/items/a.xml",
      outputFile: "C:/repo/tools/cf7-balance-tool/reports/a.xml",
      writeMode: "mirrored-output",
      updates: 2,
      changedValues: 2,
      changes: [
        {
          xmlPath: "root.item[0].data.power",
          beforeValue: "40",
          afterValue: "58",
          sourceLine: 29,
          changed: true
        },
        {
          xmlPath: "root.item[0].data.interval",
          beforeValue: "200",
          afterValue: "180",
          sourceLine: 30,
          changed: true
        }
      ]
    }
  ]
};

describe("createEditorRows", () => {
  it("creates editable rows from the preview report", () => {
    const rows = createEditorRows(sampleReport);

    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({
      xmlPath: "root.item[0].data.power",
      beforeValue: "40",
      suggestedValue: "58",
      stagedValue: "58"
    });
  });
});

describe("summarizeEditorRows", () => {
  it("counts only rows that still differ from the original value", () => {
    const rows = restoreAllRowsToOriginal(createEditorRows(sampleReport));
    const summary = summarizeEditorRows(rows);

    expect(summary).toEqual({
      files: 0,
      operations: 2,
      changedValues: 0
    });
  });
});

describe("filterEditorRows", () => {
  it("filters by query text and changed-only state", () => {
    const rows = createEditorRows(sampleReport);
    const filteredRows = filterEditorRows(rows, "interval", true);

    expect(filteredRows).toHaveLength(1);
    expect(filteredRows[0]?.xmlPath).toBe("root.item[0].data.interval");
  });
});

describe("buildBatchUpdatesPayload", () => {
  it("only exports rows whose staged value still differs from the original", () => {
    let rows = createEditorRows(sampleReport);
    rows = updateRowStagedValue(rows, rows[0]!.id, "40");

    const payload = buildBatchUpdatesPayload(rows);

    expect(payload).toEqual([
      {
        filePath: "C:/repo/data/items/a.xml",
        xmlPath: "root.item[0].data.interval",
        value: "180"
      }
    ]);
  });
});