import { describe, expect, it } from "vitest";
import path from "node:path";
import { renderOutputDirTemplate, resolveOutputDir, sanitizePathToken } from "../src/output-path.js";
import type { PackConfig } from "../src/types.js";

function makeConfig(tag: string | null = "release/2.71:beta"): PackConfig {
  return {
    version: 271,
    meta: { name: "test" },
    source: { mode: tag ? "git-tag" : "worktree", tag, repoRoot: "." },
    output: { dir: "./output/{version}/{tag}", clean: true },
    layers: [{ name: "all", source: ".", include: ["**/*"], exclude: [] }],
    globalExclude: []
  };
}

describe("output-path", () => {
  it("sanitizes token values for cross-platform paths", () => {
    expect(sanitizePathToken("release/2.71:beta")).toBe("release-2.71-beta");
  });

  it("renders supported output tokens", () => {
    const rendered = renderOutputDirTemplate("./output/{version}/{mode}/{tag}/{date}/{timestamp}", makeConfig(), new Date("2026-03-18T10:20:30"));
    expect(rendered).toContain("./output/271/git-tag/release-2.71-beta/2026-03-18/20260318-102030");
  });

  it("resolves output paths relative to the config file directory", () => {
    const resolved = resolveOutputDir(makeConfig(null), path.join("C:\\repo", "tools", "cf7-packer", "pack.config.yaml"));
    expect(resolved).toBe(path.resolve("C:\\repo", "tools", "cf7-packer", "output", "271", "worktree"));
  });
});
