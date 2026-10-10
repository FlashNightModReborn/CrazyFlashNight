import { describe, expect, it } from "vitest";

import {
  buildMonsterCsvText,
  countMonsterChanges,
  createMonsterRows,
  isEditableColumn,
  isMonsterRowChanged,
  parseMonsterCsv,
  revertMonsterRow,
  serializeMonsterCsv,
  updateMonsterCell,
  validateMonsterCell
} from "../src/renderer/monster-table-model";

const HEADERS = [
  "\u6a21\u677f", "\u522b\u540d", "\u4e3b\u7ebf\u8fdb\u5ea6", "\u6863\u6b21\u63cf\u8ff0",
  "\u9636\u6bb5", "\u6863\u6b21\u7cfb\u6570", "\u6210\u957f\u7cfb\u6570", "\u653b\u901f\u7cfb\u6570",
  "\u653b\u51fb\u500d\u7387", "\u6bb5\u6570\u7cfb\u6570", "\u901f\u5ea6\u7cfb\u6570",
  "\u9ad8\u653b\u4f4e\u8840\u9632\u7cfb\u6570", "\u9738\u4f53\u7cfb\u6570",
  "\u9ad8\u9632\u4f4e\u8840\u7cfb\u6570", "\u8d85\u51fa\u8303\u56f4", "\u8bef\u5dee\u503c"
];

const ROW_A = ["\u654c\u4eba-\u9aa8\u523a\u50f5\u5c38", "\u9aa8\u523a", "\u5e9f\u57ce", "\u4e2d\u578b\u5c0f\u602a", "1", "0.5", "1", "3", "1", "11.8", "1", "0.9", "1", "0.2", "\u6bb5\u6570\u7cfb\u6570 11.8", "24.2%"];
const ROW_B = ["\u654c\u4eba-\u4f53\u80b2\u8001\u5e08", "\u4f53\u80b2\u8001\u5e08", "\u76d7\u8d3c", "\u4e2d\u7ea7\u7cbe\u82f1", "2", "4", "1.5", "2", "1", "4", "2.5", "1", "2", "3", "", "5.1%"];

const SAMPLE_CSV = "\ufeff" + HEADERS.join(",") + "\r\n" + ROW_A.join(",") + "\r\n" + ROW_B.join(",") + "\r\n";

describe("parseMonsterCsv", () => {
  it("strips BOM and reads headers + rows", () => {
    const table = parseMonsterCsv(SAMPLE_CSV);
    expect(table.headers).toHaveLength(16);
    expect(table.rows).toHaveLength(2);
    expect(table.rows[0][0]).toBe("\u654c\u4eba-\u9aa8\u523a\u50f5\u5c38");
    expect(table.rows[1][10]).toBe("2.5");
  });

  it("skips trailing empty lines", () => {
    const table = parseMonsterCsv(HEADERS.join(",") + "\r\n" + ROW_A.join(",") + "\r\n\r\n\r\n");
    expect(table.rows).toHaveLength(1);
  });

  it("tolerates quoted cells with commas and escaped quotes", () => {
    const text = "a,b\r\n\"x,y\",\"say \"\"hi\"\"\"\r\n";
    const table = parseMonsterCsv(text);
    expect(table.rows[0]).toEqual(["x,y", 'say "hi"']);
  });
});

describe("serializeMonsterCsv / roundtrip", () => {
  it("serializes with CRLF and trailing newline", () => {
    const text = serializeMonsterCsv(HEADERS, [ROW_A]);
    expect(text.endsWith("\r\n")).toBe(true);
    expect(text).toContain("\r\n");
    const back = parseMonsterCsv(text);
    expect(back.headers).toEqual(HEADERS);
    expect(back.rows).toEqual([ROW_A]);
  });

  it("quotes cells containing commas", () => {
    const text = serializeMonsterCsv(["a", "b"], [["x,y", "z"]]);
    expect(text).toContain('"x,y"');
  });
});

describe("validateMonsterCell", () => {
  it("accepts empty (no-change marker) in any column", () => {
    expect(validateMonsterCell("\u9636\u6bb5", "")).toBeNull();
    expect(validateMonsterCell("\u6a21\u677f", "")).toBeNull();
  });

  it("rejects edits on key/derived columns", () => {
    expect(validateMonsterCell("\u6a21\u677f", "x")).not.toBeNull();
    expect(validateMonsterCell("\u8bef\u5dee\u503c", "1")).not.toBeNull();
  });

  it("accepts non-negative numbers in coefficient columns", () => {
    expect(validateMonsterCell("\u6863\u6b21\u7cfb\u6570", "0.3")).toBeNull();
    expect(validateMonsterCell("\u6210\u957f\u7cfb\u6570", "12")).toBeNull();
  });

  it("rejects non-numbers and negatives", () => {
    expect(validateMonsterCell("\u6863\u6b21\u7cfb\u6570", "abc")).not.toBeNull();
    expect(validateMonsterCell("\u6863\u6b21\u7cfb\u6570", "-1")).not.toBeNull();
  });

  it("accepts stage=0 (row exclusion marker) and rejects fractional stage", () => {
    expect(validateMonsterCell("\u9636\u6bb5", "0")).toBeNull();
    expect(validateMonsterCell("\u9636\u6bb5", "3.5")).not.toBeNull();
    expect(validateMonsterCell("\u9636\u6bb5", "\u540e\u671f")).not.toBeNull();
  });
});

describe("isEditableColumn", () => {
  it("marks the ten coefficient columns editable", () => {
    for (const col of ["\u9636\u6bb5", "\u6863\u6b21\u7cfb\u6570", "\u6210\u957f\u7cfb\u6570", "\u653b\u901f\u7cfb\u6570", "\u653b\u51fb\u500d\u7387", "\u6bb5\u6570\u7cfb\u6570", "\u901f\u5ea6\u7cfb\u6570", "\u9ad8\u653b\u4f4e\u8840\u9632\u7cfb\u6570", "\u9738\u4f53\u7cfb\u6570", "\u9ad8\u9632\u4f4e\u8840\u7cfb\u6570"]) {
      expect(isEditableColumn(col)).toBe(true);
    }
  });
  it("marks key and derived columns locked", () => {
    for (const col of ["\u6a21\u677f", "\u522b\u540d", "\u4e3b\u7ebf\u8fdb\u5ea6", "\u6863\u6b21\u63cf\u8ff0", "\u8d85\u51fa\u8303\u56f4", "\u8bef\u5dee\u503c"]) {
      expect(isEditableColumn(col)).toBe(false);
    }
  });
});

describe("row state", () => {
  it("tracks edits and counts changed cells only", () => {
    let rows = createMonsterRows([ROW_A, ROW_B]);
    const update = updateMonsterCell(rows, HEADERS, rows[0].id, 5, "0.6");
    expect(update.error).toBeNull();
    rows = update.rows;
    expect(countMonsterChanges(rows)).toBe(1);
    expect(isMonsterRowChanged(rows[0])).toBe(true);
    expect(isMonsterRowChanged(rows[1])).toBe(false);
  });

  it("reverts an entire row", () => {
    let rows = createMonsterRows([ROW_A]);
    rows = updateMonsterCell(rows, HEADERS, rows[0].id, 5, "0.6").rows;
    rows = updateMonsterCell(rows, HEADERS, rows[0].id, 6, "2").rows;
    rows = revertMonsterRow(rows, rows[0].id);
    expect(countMonsterChanges(rows)).toBe(0);
  });

  it("rejects invalid edits without mutating rows", () => {
    const rows = createMonsterRows([ROW_A]);
    const update = updateMonsterCell(rows, HEADERS, rows[0].id, 4, "2.5");
    expect(update.error).not.toBeNull();
    expect(update.rows).toBe(rows);
  });

  it("serializes edited rows back to identical-on-unchanged CSV", () => {
    const rows = createMonsterRows([ROW_A, ROW_B]);
    const text = buildMonsterCsvText(HEADERS, rows);
    const back = parseMonsterCsv(text);
    expect(back.rows).toEqual([ROW_A, ROW_B]);
  });
});
