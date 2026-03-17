import { describe, it, expect, afterEach } from "vitest";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { pack } from "../src/packer.js";
import type { FilterResult, PackConfig, FileEntry, LayerSummary } from "../src/types.js";

const REPO_ROOT = path.resolve(import.meta.dirname, "../../..");

function makeConfig(): PackConfig {
  return {
    version: 1,
    meta: { name: "test" },
    source: { mode: "worktree", repoRoot: REPO_ROOT },
    output: { dir: "./out", clean: true },
    layers: [{ name: "all", source: ".", include: ["**/*"], exclude: [] }],
    globalExclude: []
  };
}

function makeFilterResult(filePaths: string[]): FilterResult {
  const included: FileEntry[] = filePaths.map((p) => ({ path: p, layer: "test" }));
  const layers: LayerSummary[] = [{ name: "test", includedCount: filePaths.length, excludedCount: 0 }];
  return { included, excluded: [], layers, unmatchedCount: 0 };
}

describe("packer", () => {
  const tempDirs: string[] = [];

  function getTempDir(): string {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-packer-test-"));
    tempDirs.push(dir);
    return dir;
  }

  afterEach(() => {
    for (const dir of tempDirs) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
    tempDirs.length = 0;
  });

  it("dry-run mode: counts files without copying", async () => {
    const outputDir = getTempDir();
    const filterResult = makeFilterResult(["package.json", "pack.config.yaml"]);

    const result = await pack(filterResult, makeConfig(), {
      dryRun: true,
      outputDir,
      clean: false
    });

    expect(result.mode).toBe("dry-run");
    expect(result.cancelled).toBe(false);
    expect(result.copiedFiles).toBe(2);
    expect(result.totalSize).toBeGreaterThan(0);

    // dry-run 不应该创建文件
    const outputFiles = fs.readdirSync(outputDir);
    expect(outputFiles).toHaveLength(0);
  });

  it("execute mode: copies files to output directory", async () => {
    const outputDir = path.join(getTempDir(), "output");
    const filterResult = makeFilterResult(["package.json", "vitest.config.ts"]);

    const result = await pack(filterResult, makeConfig(), {
      dryRun: false,
      outputDir,
      clean: true
    });

    expect(result.mode).toBe("execute");
    expect(result.cancelled).toBe(false);
    expect(result.copiedFiles).toBe(2);

    // 验证文件已复制
    expect(fs.existsSync(path.join(outputDir, "package.json"))).toBe(true);
    expect(fs.existsSync(path.join(outputDir, "vitest.config.ts"))).toBe(true);
  });

  it("execute mode: clean option removes existing output", async () => {
    const outputDir = path.join(getTempDir(), "output");
    fs.mkdirSync(outputDir, { recursive: true });
    fs.writeFileSync(path.join(outputDir, "stale.txt"), "should be removed");

    const filterResult = makeFilterResult(["package.json"]);
    await pack(filterResult, makeConfig(), {
      dryRun: false,
      outputDir,
      clean: true
    });

    expect(fs.existsSync(path.join(outputDir, "stale.txt"))).toBe(false);
    expect(fs.existsSync(path.join(outputDir, "package.json"))).toBe(true);
  });

  it("respects AbortSignal: stops mid-copy", async () => {
    const outputDir = path.join(getTempDir(), "output");
    const controller = new AbortController();
    controller.abort(); // 立即中止

    const filterResult = makeFilterResult(["package.json", "vitest.config.ts"]);
    const result = await pack(filterResult, makeConfig(), {
      dryRun: false,
      outputDir,
      clean: true,
      signal: controller.signal
    });

    expect(result.cancelled).toBe(true);
    expect(result.copiedFiles).toBeLessThan(result.totalFiles);
  });
});
