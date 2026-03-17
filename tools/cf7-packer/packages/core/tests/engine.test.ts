import { describe, it, expect, afterEach } from "vitest";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { PackerEngine } from "../src/engine.js";
import type { PackConfig, PackerLogEvent } from "../src/types.js";

const REPO_ROOT = path.resolve(import.meta.dirname, "../../..");

function makeConfig(): PackConfig {
  return {
    version: 1,
    meta: { name: "test" },
    source: { mode: "worktree", repoRoot: REPO_ROOT },
    output: { dir: "./out", clean: true },
    layers: [
      { name: "root", source: ".", include: ["package.json", "pack.config.yaml"], exclude: [] }
    ],
    globalExclude: ["**/*.bak"]
  };
}

describe("PackerEngine", () => {
  const tempDirs: string[] = [];

  function getTempDir(): string {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-engine-test-"));
    tempDirs.push(dir);
    return dir;
  }

  afterEach(() => {
    for (const dir of tempDirs) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
    tempDirs.length = 0;
  });

  it("dry-run pipeline: collect → filter → pack", async () => {
    const outputDir = getTempDir();
    const engine = new PackerEngine(makeConfig());

    const logs: PackerLogEvent[] = [];
    engine.on("log", (event) => logs.push(event));

    const result = await engine.run({
      dryRun: true,
      outputDir,
      clean: false
    });

    expect(result.mode).toBe("dry-run");
    expect(result.cancelled).toBe(false);
    expect(result.copiedFiles).toBeGreaterThanOrEqual(2);
    expect(logs.length).toBeGreaterThan(0);
    expect(logs.some((l) => l.layer === "collector")).toBe(true);
    expect(logs.some((l) => l.layer === "filter")).toBe(true);
    expect(logs.some((l) => l.layer === "packer")).toBe(true);
  });

  it("execute pipeline: copies files", async () => {
    const outputDir = path.join(getTempDir(), "output");
    const engine = new PackerEngine(makeConfig());

    const result = await engine.run({
      dryRun: false,
      outputDir,
      clean: true
    });

    expect(result.mode).toBe("execute");
    expect(result.copiedFiles).toBeGreaterThanOrEqual(2);
    expect(fs.existsSync(path.join(outputDir, "package.json"))).toBe(true);
  });

  it("cancel: stops pipeline", async () => {
    const outputDir = getTempDir();
    const engine = new PackerEngine(makeConfig());

    // 启动后立即取消
    const promise = engine.run({ dryRun: false, outputDir, clean: false });
    engine.cancel();

    const result = await promise;
    expect(result.cancelled).toBe(true);
  });

  it("cancel is idempotent when not running", () => {
    const engine = new PackerEngine(makeConfig());
    // 不应该抛异常
    engine.cancel();
    engine.cancel();
  });
});
