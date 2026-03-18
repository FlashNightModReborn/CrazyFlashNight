import { describe, it, expect, afterEach } from "vitest";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { pack, validateOutputDir } from "../src/packer.js";
import { OutputDirNotOwnedError } from "../src/types.js";
import type { FilterResult, PackConfig, FileEntry, LayerSummary } from "../src/types.js";

const OUTPUT_DIR_MARKER = ".cf7-packer-output";

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

  it("execute mode: clean option removes existing owned output", async () => {
    const outputDir = path.join(getTempDir(), "output");
    fs.mkdirSync(outputDir, { recursive: true });
    fs.writeFileSync(path.join(outputDir, OUTPUT_DIR_MARKER), "created=test\n");
    fs.writeFileSync(path.join(outputDir, "stale.txt"), "should be removed");

    const filterResult = makeFilterResult(["package.json"]);
    await pack(filterResult, makeConfig(), {
      dryRun: false,
      outputDir,
      clean: true
    });

    expect(fs.existsSync(path.join(outputDir, "stale.txt"))).toBe(false);
    expect(fs.existsSync(path.join(outputDir, "package.json"))).toBe(true);
    // 标记文件应被重新创建
    expect(fs.existsSync(path.join(outputDir, OUTPUT_DIR_MARKER))).toBe(true);
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

  it("fills estimated layer size in pack result", async () => {
    const outputDir = path.join(getTempDir(), "output");
    const filterResult = makeFilterResult(["package.json"]);

    const result = await pack(filterResult, makeConfig(), {
      dryRun: false,
      outputDir,
      clean: true
    });

    expect(result.layers[0]?.estimatedSize).toBeGreaterThan(0);
  });

  it("emits staged pack progress with detail updates", async () => {
    const outputDir = path.join(getTempDir(), "output");
    const filterResult = makeFilterResult(["package.json", "vitest.config.ts"]);
    const progressEvents: Array<{ current: number; total: number; label?: string; detail?: string }> = [];

    await pack(filterResult, makeConfig(), {
      dryRun: false,
      outputDir,
      clean: true,
      onProgress: (event) => {
        progressEvents.push({
          current: event.current,
          total: event.total,
          label: event.label,
          detail: event.detail
        });
      }
    });

    expect(progressEvents[0]).toMatchObject({
      current: 0,
      total: 2,
      label: "复制打包文件"
    });
    expect(progressEvents.at(-1)).toMatchObject({
      current: 2,
      total: 2,
      detail: "vitest.config.ts"
    });
  });

  // ── 输出目录安全校验 ──

  it("validateOutputDir: rejects outputDir equal to repoRoot", () => {
    expect(() => validateOutputDir(REPO_ROOT, REPO_ROOT)).toThrow("不能等于仓库根目录");
  });

  it("validateOutputDir: rejects outputDir that contains repoRoot", () => {
    const parent = path.dirname(REPO_ROOT);
    expect(() => validateOutputDir(parent, REPO_ROOT)).toThrow("不能包含仓库根目录");
  });

  it("validateOutputDir: rejects system root", () => {
    const root = path.parse(REPO_ROOT).root;
    expect(() => validateOutputDir(root, REPO_ROOT)).toThrow("系统根目录");
  });

  it("validateOutputDir: rejects user home directory", () => {
    expect(() => validateOutputDir(os.homedir(), REPO_ROOT)).toThrow("用户主目录");
  });

  it("validateOutputDir: accepts valid output path", () => {
    const validDir = path.join(os.tmpdir(), "cf7-test-output");
    expect(() => validateOutputDir(validDir, REPO_ROOT)).not.toThrow();
  });

  it("clean: throws OutputDirNotOwnedError for unmarked directory without forceClean", async () => {
    const outputDir = path.join(getTempDir(), "output");
    fs.mkdirSync(outputDir, { recursive: true });
    fs.writeFileSync(path.join(outputDir, "some-file.txt"), "data");

    const filterResult = makeFilterResult(["package.json"]);
    await expect(pack(filterResult, makeConfig(), {
      dryRun: false,
      outputDir,
      clean: true
    })).rejects.toThrow(OutputDirNotOwnedError);
  });

  it("clean: forceClean bypasses marker check for unmarked directory", async () => {
    const outputDir = path.join(getTempDir(), "output");
    fs.mkdirSync(outputDir, { recursive: true });
    fs.writeFileSync(path.join(outputDir, "some-file.txt"), "data");

    const filterResult = makeFilterResult(["package.json"]);
    const result = await pack(filterResult, makeConfig(), {
      dryRun: false,
      outputDir,
      clean: true,
      forceClean: true
    });

    expect(result.copiedFiles).toBe(1);
    expect(fs.existsSync(path.join(outputDir, "some-file.txt"))).toBe(false);
    // 标记文件应被写入
    expect(fs.existsSync(path.join(outputDir, OUTPUT_DIR_MARKER))).toBe(true);
  });

  it("clean: creates marker when output directory does not exist", async () => {
    const outputDir = path.join(getTempDir(), "new-output");
    const filterResult = makeFilterResult(["package.json"]);

    await pack(filterResult, makeConfig(), {
      dryRun: false,
      outputDir,
      clean: true
    });

    expect(fs.existsSync(path.join(outputDir, OUTPUT_DIR_MARKER))).toBe(true);
    expect(fs.existsSync(path.join(outputDir, "package.json"))).toBe(true);
  });

  it.skipIf(process.platform === "win32")("preserves executable bits for worktree files", async () => {
    const repoRoot = path.join(getTempDir(), "repo");
    fs.mkdirSync(repoRoot, { recursive: true });
    const scriptPath = path.join(repoRoot, "run.sh");
    fs.writeFileSync(scriptPath, "#!/usr/bin/env bash\necho ok\n", "utf8");
    fs.chmodSync(scriptPath, 0o755);

    const outputDir = path.join(getTempDir(), "output");
    const config: PackConfig = {
      ...makeConfig(),
      source: { mode: "worktree", repoRoot }
    };
    const filterResult = makeFilterResult(["run.sh"]);

    await pack(filterResult, config, {
      dryRun: false,
      outputDir,
      clean: true
    });

    const mode = fs.statSync(path.join(outputDir, "run.sh")).mode & 0o777;
    expect(mode & 0o111).not.toBe(0);
  });
});
