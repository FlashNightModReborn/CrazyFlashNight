import { describe, expect, it } from "vitest";
import { sortRows } from "../src/renderer/data-grid";
import type { EditorRow } from "../src/renderer/editor-model";

function makeRow(overrides: Partial<EditorRow> & { id: string }): EditorRow {
  return {
    sourceFile: "data/items/test.xml",
    outputFile: "output/test.xml",
    writeMode: "preview",
    xmlPath: "root.item",
    beforeValue: "0",
    suggestedValue: "1",
    stagedValue: "1",
    sourceLine: 1,
    ...overrides
  };
}

describe("sortRows", () => {
  const rows: EditorRow[] = [
    makeRow({ id: "a", sourceFile: "b.xml", xmlPath: "root.z", sourceLine: 10, beforeValue: "5" }),
    makeRow({ id: "b", sourceFile: "a.xml", xmlPath: "root.a", sourceLine: 3, beforeValue: "20" }),
    makeRow({ id: "c", sourceFile: "c.xml", xmlPath: "root.m", sourceLine: 1, beforeValue: "100" })
  ];

  it("sorts by file ascending", () => {
    const sorted = sortRows(rows, "file", "asc");
    expect(sorted.map((r) => r.id)).toEqual(["b", "a", "c"]);
  });

  it("sorts by file descending", () => {
    const sorted = sortRows(rows, "file", "desc");
    expect(sorted.map((r) => r.id)).toEqual(["c", "a", "b"]);
  });

  it("sorts by xmlPath ascending", () => {
    const sorted = sortRows(rows, "xmlPath", "asc");
    expect(sorted.map((r) => r.id)).toEqual(["b", "c", "a"]);
  });

  it("sorts by line ascending", () => {
    const sorted = sortRows(rows, "line", "asc");
    expect(sorted.map((r) => r.id)).toEqual(["c", "b", "a"]);
  });

  it("sorts by before value numerically", () => {
    const sorted = sortRows(rows, "before", "asc");
    expect(sorted.map((r) => r.beforeValue)).toEqual(["5", "20", "100"]);
  });

  it("sorts by before value numerically descending", () => {
    const sorted = sortRows(rows, "before", "desc");
    expect(sorted.map((r) => r.beforeValue)).toEqual(["100", "20", "5"]);
  });

  it("does not mutate original array", () => {
    const original = [...rows];
    sortRows(rows, "file", "asc");
    expect(rows.map((r) => r.id)).toEqual(original.map((r) => r.id));
  });
});
