import { describe, it, expect } from "vitest";
import { diffFilterResults } from "../src/diff.js";
import type { FilterResult, FileEntry } from "../src/types.js";

function makeResult(paths: string[]): FilterResult {
  const included: FileEntry[] = paths.map((p) => ({ path: p, layer: "test" }));
  return { included, excluded: [], layers: [], unmatchedCount: 0 };
}

describe("diffFilterResults", () => {
  it("detects added files", () => {
    const base = makeResult(["a.txt", "b.txt"]);
    const target = makeResult(["a.txt", "b.txt", "c.txt"]);

    const result = diffFilterResults(base, target);
    expect(result.added).toEqual(["c.txt"]);
    expect(result.removed).toEqual([]);
    expect(result.unchanged).toBe(2);
  });

  it("detects removed files", () => {
    const base = makeResult(["a.txt", "b.txt", "c.txt"]);
    const target = makeResult(["a.txt"]);

    const result = diffFilterResults(base, target);
    expect(result.added).toEqual([]);
    expect(result.removed).toEqual(["b.txt", "c.txt"]);
    expect(result.unchanged).toBe(1);
  });

  it("detects both added and removed", () => {
    const base = makeResult(["a.txt", "b.txt"]);
    const target = makeResult(["b.txt", "c.txt"]);

    const result = diffFilterResults(base, target);
    expect(result.added).toEqual(["c.txt"]);
    expect(result.removed).toEqual(["a.txt"]);
    expect(result.unchanged).toBe(1);
  });

  it("identical results yield no diff", () => {
    const base = makeResult(["a.txt", "b.txt"]);
    const target = makeResult(["a.txt", "b.txt"]);

    const result = diffFilterResults(base, target);
    expect(result.added).toEqual([]);
    expect(result.removed).toEqual([]);
    expect(result.unchanged).toBe(2);
  });

  it("empty baseline: all target files are added", () => {
    const base = makeResult([]);
    const target = makeResult(["a.txt", "b.txt"]);

    const result = diffFilterResults(base, target);
    expect(result.added).toEqual(["a.txt", "b.txt"]);
    expect(result.unchanged).toBe(0);
  });

  it("results are sorted", () => {
    const base = makeResult(["z.txt"]);
    const target = makeResult(["c.txt", "a.txt", "b.txt"]);

    const result = diffFilterResults(base, target);
    expect(result.added).toEqual(["a.txt", "b.txt", "c.txt"]);
    expect(result.removed).toEqual(["z.txt"]);
  });
});
