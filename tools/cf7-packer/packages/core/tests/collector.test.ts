import { describe, it, expect } from "vitest";
import path from "node:path";
import { collect } from "../src/collector.js";
import type { PackConfig } from "../src/types.js";

// 用项目自身目录作为测试目标（已知存在的文件）
const REPO_ROOT = path.resolve(import.meta.dirname, "../../..");
// 也就是 cf7-packer 根目录

function makeConfig(mode: "worktree" | "git-tag" = "worktree", tag?: string): PackConfig {
  return {
    version: 1,
    meta: { name: "test" },
    source: { mode, tag, repoRoot: REPO_ROOT },
    output: { dir: "./out", clean: true },
    layers: [{ name: "all", source: ".", include: ["**/*"], exclude: [] }],
    globalExclude: []
  };
}

describe("collector", () => {
  it("worktree mode: scans filesystem and finds known files", async () => {
    const config = makeConfig("worktree");
    const result = await collect(config);

    expect(result.source).toBe("worktree");
    expect(result.fileCount).toBeGreaterThan(10);

    // 应该找到 pack.config.yaml
    expect(result.files).toContain("pack.config.yaml");
    // 应该找到 package.json
    expect(result.files).toContain("package.json");
  });

  it("worktree mode: excludes .git and node_modules dirs", async () => {
    const config = makeConfig("worktree");
    const result = await collect(config);

    const hasGitFiles = result.files.some((f) => f.startsWith(".git/"));
    const hasNodeModules = result.files.some((f) => f.startsWith("node_modules/"));

    expect(hasGitFiles).toBe(false);
    expect(hasNodeModules).toBe(false);
  });

  it("worktree mode: uses forward slashes on all platforms", async () => {
    const config = makeConfig("worktree");
    const result = await collect(config);

    const hasBackslash = result.files.some((f) => f.includes("\\"));
    expect(hasBackslash).toBe(false);
  });

  it("worktree mode: respects AbortSignal", async () => {
    const controller = new AbortController();
    controller.abort(); // 立即中止

    const config = makeConfig("worktree");
    const result = await collect(config, controller.signal);

    // 中止后应该返回很少或没有文件
    expect(result.fileCount).toBeLessThan(5);
  });
});
