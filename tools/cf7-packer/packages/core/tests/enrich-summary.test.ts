import { describe, it, expect } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { enrichWithSize } from "../src/enrich.js";
import { applyEstimatedSizes } from "../src/summary.js";
import type { FileEntry, LayerSummary } from "../src/types.js";

const REPO_ROOT = path.resolve(import.meta.dirname, "../../..");

describe("enrichWithSize", () => {
  it("fills size for existing files", () => {
    const entries: FileEntry[] = [
      { path: "package.json", layer: "root" }
    ];
    enrichWithSize(entries, REPO_ROOT);
    expect(entries[0]!.size).toBeGreaterThan(0);
  });

  it("skips missing files without error", () => {
    const entries: FileEntry[] = [
      { path: "nonexistent-file-12345.txt", layer: "test" }
    ];
    enrichWithSize(entries, REPO_ROOT);
    expect(entries[0]!.size).toBeUndefined();
  });

  it("handles empty array", () => {
    const entries: FileEntry[] = [];
    enrichWithSize(entries, REPO_ROOT);
    expect(entries).toHaveLength(0);
  });
});

describe("applyEstimatedSizes", () => {
  it("aggregates sizes per layer", () => {
    const layers: LayerSummary[] = [
      { name: "data", includedCount: 2, excludedCount: 0 },
      { name: "scripts", includedCount: 1, excludedCount: 0 }
    ];
    const entries: FileEntry[] = [
      { path: "a.xml", layer: "data", size: 100 },
      { path: "b.xml", layer: "data", size: 200 },
      { path: "c.js", layer: "scripts", size: 50 }
    ];
    const result = applyEstimatedSizes(layers, entries);
    expect(result[0]!.estimatedSize).toBe(300);
    expect(result[1]!.estimatedSize).toBe(50);
  });

  it("leaves layers without size entries unchanged", () => {
    const layers: LayerSummary[] = [
      { name: "data", includedCount: 1, excludedCount: 0 }
    ];
    const entries: FileEntry[] = [
      { path: "a.xml", layer: "data" } // no size
    ];
    const result = applyEstimatedSizes(layers, entries);
    expect(result[0]!.estimatedSize).toBeUndefined();
  });

  it("handles empty entries", () => {
    const layers: LayerSummary[] = [
      { name: "data", includedCount: 0, excludedCount: 0 }
    ];
    const result = applyEstimatedSizes(layers, []);
    expect(result[0]!.estimatedSize).toBeUndefined();
  });
});
