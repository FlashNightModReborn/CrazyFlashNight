import { describe, expect, it } from "vitest";
import path from "node:path";
import { applyExcludeMutation, resolveExcludeMutation, prepareExcludeAction } from "../src/config-editor.js";
import type { PackConfig } from "../src/types.js";

function makeConfig(): PackConfig {
  return {
    version: 1,
    meta: { name: "test" },
    source: { mode: "worktree", repoRoot: "." },
    output: { dir: "./output/{version}", clean: true },
    layers: [
      { name: "data", source: "data/", include: ["**/*"], exclude: [] },
      { name: "root-dirs", source: ".", include: ["docs/**"], exclude: [] }
    ],
    globalExclude: ["**/*.bak"]
  };
}

const YAML = `version: 1
meta:
  name: "test"
source:
  mode: worktree
  tag: null
  repoRoot: "../../"
output:
  dir: "./output/{version}"
  clean: true
layers:
  - name: data
    source: "data/"
    include: ["**/*"]
    exclude: []
  - name: root-dirs
    source: "."
    include: ["docs/**"]
    exclude: []
globalExclude:
  - "**/*.bak"
`;

describe("config-editor", () => {
  it("maps top-level layer directories back to their own layer", () => {
    const result = resolveExcludeMutation(makeConfig(), {
      filePath: "data",
      isDir: true
    });

    expect(result.layerName).toBe("data");
    expect(result.pattern).toBe("**");
  });

  it("keeps nested paths relative to the matched layer", () => {
    const result = resolveExcludeMutation(makeConfig(), {
      filePath: "data/items/weapon.xml",
      isDir: false
    });

    expect(result.layerName).toBe("data");
    expect(result.pattern).toBe("items/weapon.xml");
  });

  it("writes exclude rules into the matched layer and avoids duplicates", () => {
    const config = makeConfig();

    const first = applyExcludeMutation(YAML, config, {
      filePath: "data/items",
      isDir: true
    });
    expect(first.result.layerName).toBe("data");
    expect(first.result.pattern).toBe("items/**");
    expect(first.content).toContain('"items/**"');

    const secondConfig: PackConfig = {
      ...config,
      layers: [
        { ...config.layers[0]!, exclude: ["items/**"] },
        config.layers[1]!
      ]
    };
    const second = applyExcludeMutation(first.content, secondConfig, {
      filePath: "data/items",
      isDir: true
    });

    expect(second.result.alreadyPresent).toBe(true);
    expect(second.content.match(/items\/\*\*/g)).toHaveLength(1);
  });

  it("rejects path traversal input", () => {
    expect(() => resolveExcludeMutation(makeConfig(), {
      filePath: "../secrets.txt",
      isDir: false
    })).toThrow("路径不能包含 ..");
  });
});

describe("prepareExcludeAction", () => {
  const repoRoot = path.resolve(import.meta.dirname, "../../..");

  it("returns shouldDelete true for valid path with deleteFromDisk", () => {
    const result = prepareExcludeAction(repoRoot, "data/items/weapon.xml", true);
    expect(result.shouldDelete).toBe(true);
    expect(result.normalizedPath).toBe("data/items/weapon.xml");
    expect(result.fullPath).toBe(path.resolve(repoRoot, "data/items/weapon.xml"));
    expect(result.error).toBeUndefined();
  });

  it("returns shouldDelete false when not requesting deletion", () => {
    const result = prepareExcludeAction(repoRoot, "data/items/weapon.xml", false);
    expect(result.shouldDelete).toBe(false);
    expect(result.error).toBeUndefined();
  });

  it("rejects path traversal with ..", () => {
    const result = prepareExcludeAction(repoRoot, "../etc/passwd", true);
    expect(result.shouldDelete).toBe(false);
    expect(result.error).toBe("路径无效");
  });

  it("rejects absolute paths", () => {
    const result = prepareExcludeAction(repoRoot, "/etc/passwd", true);
    expect(result.shouldDelete).toBe(false);
    expect(result.error).toBe("路径无效");
  });
});
