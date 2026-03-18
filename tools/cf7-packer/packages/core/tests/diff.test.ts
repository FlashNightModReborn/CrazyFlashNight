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
    expect(result.modified).toEqual([]);
    expect(result.unchanged).toBe(2);
  });

  it("detects removed files", () => {
    const base = makeResult(["a.txt", "b.txt", "c.txt"]);
    const target = makeResult(["a.txt"]);

    const result = diffFilterResults(base, target);
    expect(result.added).toEqual([]);
    expect(result.removed).toEqual(["b.txt", "c.txt"]);
    expect(result.modified).toEqual([]);
    expect(result.unchanged).toBe(1);
  });

  it("detects both added and removed", () => {
    const base = makeResult(["a.txt", "b.txt"]);
    const target = makeResult(["b.txt", "c.txt"]);

    const result = diffFilterResults(base, target);
    expect(result.added).toEqual(["c.txt"]);
    expect(result.removed).toEqual(["a.txt"]);
    expect(result.modified).toEqual([]);
    expect(result.unchanged).toBe(1);
  });

  it("identical results yield no diff", () => {
    const base = makeResult(["a.txt", "b.txt"]);
    const target = makeResult(["a.txt", "b.txt"]);

    const result = diffFilterResults(base, target);
    expect(result.added).toEqual([]);
    expect(result.removed).toEqual([]);
    expect(result.modified).toEqual([]);
    expect(result.unchanged).toBe(2);
  });

  it("empty baseline: all target files are added", () => {
    const base = makeResult([]);
    const target = makeResult(["a.txt", "b.txt"]);

    const result = diffFilterResults(base, target);
    expect(result.added).toEqual(["a.txt", "b.txt"]);
    expect(result.modified).toEqual([]);
    expect(result.unchanged).toBe(0);
  });

  it("results are sorted", () => {
    const base = makeResult(["z.txt"]);
    const target = makeResult(["c.txt", "a.txt", "b.txt"]);

    const result = diffFilterResults(base, target);
    expect(result.added).toEqual(["a.txt", "b.txt", "c.txt"]);
    expect(result.removed).toEqual(["z.txt"]);
    expect(result.modified).toEqual([]);
  });

  // ── 内容变更检测 ──

  it("separates modified from unchanged when modifiedPaths provided", () => {
    const base = makeResult(["a.txt", "b.txt", "c.txt"]);
    const target = makeResult(["a.txt", "b.txt", "c.txt"]);
    const modifiedPaths = new Set(["b.txt"]);

    const result = diffFilterResults(base, target, modifiedPaths);
    expect(result.added).toEqual([]);
    expect(result.removed).toEqual([]);
    expect(result.modified).toEqual(["b.txt"]);
    expect(result.unchanged).toBe(2);
  });

  it("modified + added + removed + unchanged equals total", () => {
    const base = makeResult(["a.txt", "b.txt", "c.txt", "d.txt"]);
    const target = makeResult(["a.txt", "b.txt", "e.txt"]);
    const modifiedPaths = new Set(["a.txt"]);

    const result = diffFilterResults(base, target, modifiedPaths);
    expect(result.added).toEqual(["e.txt"]);
    expect(result.removed).toEqual(["c.txt", "d.txt"]);
    expect(result.modified).toEqual(["a.txt"]);
    expect(result.unchanged).toBe(1);

    // 总和校验: added + removed + modified + unchanged = |base ∪ target|
    const total = result.added.length + result.removed.length + result.modified.length + result.unchanged;
    const uniquePaths = new Set([...base.included.map(f => f.path), ...target.included.map(f => f.path)]);
    expect(total).toBe(uniquePaths.size);
  });

  it("modifiedPaths only affects common files, not added/removed", () => {
    const base = makeResult(["a.txt", "b.txt"]);
    const target = makeResult(["b.txt", "c.txt"]);
    // "c.txt" 在 modifiedPaths 中但它是 added，不应出现在 modified
    const modifiedPaths = new Set(["b.txt", "c.txt"]);

    const result = diffFilterResults(base, target, modifiedPaths);
    expect(result.added).toEqual(["c.txt"]);
    expect(result.modified).toEqual(["b.txt"]);
    expect(result.unchanged).toBe(0);
  });

  it("modified results are sorted", () => {
    const base = makeResult(["z.txt", "a.txt", "m.txt"]);
    const target = makeResult(["z.txt", "a.txt", "m.txt"]);
    const modifiedPaths = new Set(["z.txt", "a.txt"]);

    const result = diffFilterResults(base, target, modifiedPaths);
    expect(result.modified).toEqual(["a.txt", "z.txt"]);
    expect(result.unchanged).toBe(1);
  });
});
