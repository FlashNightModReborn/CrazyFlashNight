import { describe, it, expect } from "vitest";
import { packConfigSchema } from "../src/config-schema.js";

describe("packConfigSchema", () => {
  const minimal = {
    version: 1,
    meta: { name: "test" },
    source: { mode: "worktree", repoRoot: "." },
    output: { dir: "./out" },
    layers: [{ name: "data", source: "data/", include: ["**/*"] }]
  };

  it("accepts minimal valid config", () => {
    const result = packConfigSchema.safeParse(minimal);
    expect(result.success).toBe(true);
  });

  it("fills defaults for optional fields", () => {
    const result = packConfigSchema.parse(minimal);
    expect(result.output.clean).toBe(true);
    expect(result.source.tag).toBeNull();
    expect(result.globalExclude).toEqual([]);
    expect(result.layers[0]!.exclude).toEqual([]);
  });

  it("rejects missing meta.name", () => {
    const result = packConfigSchema.safeParse({
      ...minimal,
      meta: {}
    });
    expect(result.success).toBe(false);
  });

  it("rejects empty layers array", () => {
    const result = packConfigSchema.safeParse({
      ...minimal,
      layers: []
    });
    expect(result.success).toBe(false);
  });

  it("rejects invalid source.mode", () => {
    const result = packConfigSchema.safeParse({
      ...minimal,
      source: { mode: "invalid", repoRoot: "." }
    });
    expect(result.success).toBe(false);
  });

  it("accepts git-tag mode with tag", () => {
    const result = packConfigSchema.safeParse({
      ...minimal,
      source: { mode: "git-tag", tag: "v1.0", repoRoot: "." }
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.source.tag).toBe("v1.0");
    }
  });

  it("rejects negative version", () => {
    const result = packConfigSchema.safeParse({
      ...minimal,
      version: -1
    });
    expect(result.success).toBe(false);
  });

  it("accepts multiple layers with descriptions", () => {
    const result = packConfigSchema.safeParse({
      ...minimal,
      layers: [
        { name: "data", source: "data/", include: ["**/*"], description: "游戏数据" },
        { name: "scripts", source: "scripts/", include: ["**/*"], exclude: ["test/**"] }
      ]
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.layers).toHaveLength(2);
      expect(result.data.layers[0]!.description).toBe("游戏数据");
    }
  });

  it("accepts globalExclude patterns", () => {
    const result = packConfigSchema.parse({
      ...minimal,
      globalExclude: ["**/.DS_Store", "**/*.bak"]
    });
    expect(result.globalExclude).toEqual(["**/.DS_Store", "**/*.bak"]);
  });
});
