import { describe, expect, it } from "vitest";
import { applyExcludeMutation, resolveExcludeMutation } from "../src/config-editor.js";
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
