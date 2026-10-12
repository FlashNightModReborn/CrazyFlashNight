import { describe, it, expect, afterEach } from "vitest";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { createRequire } from "node:module";
import { filterFiles } from "../src/filter.js";
import { execFileSync } from "node:child_process";
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

function writeMinifyFixtures(repoRoot: string): Buffer {
  const preserved = Buffer.from('{\r\n  "runtime": true,\r\n  "note": "keep bytes"\r\n}\r\n', "utf8");
  fs.mkdirSync(path.join(repoRoot, "runtime"), { recursive: true });
  fs.mkdirSync(path.join(repoRoot, "data"), { recursive: true });
  fs.writeFileSync(path.join(repoRoot, "runtime", "metadata.json"), preserved);
  fs.writeFileSync(path.join(repoRoot, "data", "items.json"), '{\n  "data": true,\n  "items": [1, 2]\n}\n', "utf8");
  return preserved;
}

function makeMinifyConfig(source: PackConfig["source"]): PackConfig {
  return {
    ...makeConfig(),
    source,
    output: {
      dir: "./out",
      clean: true,
      minify: {
        enabled: true,
        extensions: [".json"],
        exclude: ["runtime/**"]
      }
    }
  };
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
      expect(path.dirname(path.resolve(dir))).toBe(path.resolve(os.tmpdir()));
      expect(path.basename(dir)).toMatch(/^cf7-packer-test-/);
      fs.rmSync(dir, { recursive: true, force: true });
    }
    tempDirs.length = 0;
  });

  function ownershipFixture(): { repoRoot: string; paths: string[] } {
    const repoRoot = path.join(getTempDir(), "repo");
    const word = (n: number) => { const b = Buffer.alloc(2); b.writeUInt16LE(n); return b; };
    const tag = (code: number, body: Buffer) => {
      if (body.length < 63) return Buffer.concat([word((code << 6) | body.length), body]);
      const size = Buffer.alloc(4); size.writeUInt32LE(body.length);
      return Buffer.concat([word((code << 6) | 63), size, body]);
    };
    const swf = (className?: string, imported?: string) => {
      const tags: Buffer[] = [];
      if (className) tags.push(tag(39, Buffer.concat([word(1), word(1), word(0)])),
        tag(56, Buffer.concat([word(1), word(1), Buffer.from("__Packages." + className + "\0")])),
        tag(59, Buffer.concat([word(1), Buffer.from([0])])));
      if (imported) tags.push(tag(71, Buffer.concat([Buffer.from(imported + "\0"), Buffer.from([1, 0]), word(0)])));
      const body = Buffer.concat([Buffer.from([8, 0, 0, 30, 1, 0]), ...tags, word(0)]);
      const header = Buffer.alloc(8); header.write("FWS"); header[3] = 8; header.writeUInt32LE(body.length + 8, 4);
      return Buffer.concat([header, body]);
    };
    const paths = ["CRAZYFLASHER7MercenaryEmpire.swf", "scripts/asLoader.swf", "flashswf/asset.swf"];
    const bodies = [swf(undefined, paths[2]), swf("org.flashNight.Authority"), swf()];
    paths.forEach((rel, i) => { const file = path.join(repoRoot, rel); fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, bodies[i]); });
    fs.mkdirSync(path.join(repoRoot, "tools"), { recursive: true });
    for (const name of ["swf-metadata.js", "audit-as2-class-embedding.js"]) {
      fs.copyFileSync(path.resolve(REPO_ROOT, "..", name), path.join(repoRoot, "tools", name));
    }
    return { repoRoot, paths };
  }

  it("game delivery gate accepts the complete copied classless resource closure", async () => {
    const { repoRoot, paths } = ownershipFixture();
    const outputDir = path.join(getTempDir(), "output");
    const result = await pack(makeFilterResult(paths), { ...makeConfig(), source: { mode: "worktree", repoRoot } },
      { dryRun: false, outputDir, clean: true });
    expect(result.errors).toEqual([]);
    expect(result.copiedFiles).toBe(3);
  });

  it("game delivery gate reads final copied bytes and rejects an embedded authority class", async () => {
    const { repoRoot, paths } = ownershipFixture();
    const outputDir = path.join(getTempDir(), "output");
    const result = await pack(makeFilterResult(paths), { ...makeConfig(), source: { mode: "worktree", repoRoot } },
      { dryRun: false, outputDir, clean: true, onProgress(progress) {
        if (progress.phase === "pack" && progress.current === 3) {
          fs.copyFileSync(path.join(repoRoot, paths[1]), path.join(outputDir, paths[2]));
        }
      } });
    expect(result.errors).toHaveLength(1);
    expect(result.errors[0].error).toContain("duplicates asLoader authority");
  });

  it("game delivery gate rejects an RSL missing from the final file list", async () => {
    const { repoRoot, paths } = ownershipFixture();
    const result = await pack(makeFilterResult(paths.slice(0, 2)), { ...makeConfig(), source: { mode: "worktree", repoRoot } },
      { dryRun: false, outputDir: path.join(getTempDir(), "output"), clean: true });
    expect(result.errors).toHaveLength(1);
    expect(result.errors[0].error).toContain("missing/ambiguous RSL");
  });

  it("ownership discovery uses the same first matching layer and exclusions as packer", () => {
    const config = { ...makeConfig(), layers: [
      { name: "assets", source: "flashswf", include: ["**/*.swf"], exclude: ["private/**"] },
      { name: "root", source: ".", include: ["**/*.swf"], exclude: [] }
    ], globalExclude: ["**/ignored.swf"] };
    const files = ["flashswf/private/no.swf", "flashswf/yes.swf", "root.swf", "flashswf/ignored.swf"];
    const audit = createRequire(import.meta.url)(path.resolve(REPO_ROOT, "..", "audit-as2-class-embedding.js"));
    expect(audit.filterProductionFiles(files, config)).toEqual(filterFiles(files, config).included.map(entry => entry.path));
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

  it("worktree mode: preserves excluded JSON bytes while minifying ordinary JSON", async () => {
    const repoRoot = path.join(getTempDir(), "repo");
    const preserved = writeMinifyFixtures(repoRoot);
    const outputDir = path.join(getTempDir(), "output");
    const filterResult = makeFilterResult(["runtime/metadata.json", "data/items.json"]);

    const result = await pack(
      filterResult,
      makeMinifyConfig({ mode: "worktree", repoRoot }),
      { dryRun: false, outputDir, clean: true }
    );

    expect(result.errors).toEqual([]);
    expect(fs.readFileSync(path.join(outputDir, "runtime", "metadata.json"))).toEqual(preserved);
    expect(fs.readFileSync(path.join(outputDir, "data", "items.json"), "utf8"))
      .toBe('{"data":true,"items":[1,2]}');
  });

  it("git-tag mode: applies the same byte-preservation policy", async () => {
    const repoRoot = path.join(getTempDir(), "repo");
    fs.mkdirSync(repoRoot, { recursive: true });
    const preserved = writeMinifyFixtures(repoRoot);
    execFileSync("git", ["init"], { cwd: repoRoot, stdio: "pipe" });
    execFileSync("git", ["config", "core.autocrlf", "false"], { cwd: repoRoot, stdio: "pipe" });
    execFileSync("git", ["config", "user.email", "cf7-packer@example.invalid"], { cwd: repoRoot, stdio: "pipe" });
    execFileSync("git", ["config", "user.name", "CF7 Packer Test"], { cwd: repoRoot, stdio: "pipe" });
    execFileSync("git", ["add", "."], { cwd: repoRoot, stdio: "pipe" });
    execFileSync("git", ["commit", "-m", "fixture"], { cwd: repoRoot, stdio: "pipe" });
    execFileSync("git", ["tag", "fixture"], { cwd: repoRoot, stdio: "pipe" });

    const outputDir = path.join(getTempDir(), "output");
    const filterResult = makeFilterResult(["runtime/metadata.json", "data/items.json"]);
    const result = await pack(
      filterResult,
      makeMinifyConfig({ mode: "git-tag", repoRoot, tag: "fixture" }),
      { dryRun: false, outputDir, clean: true }
    );

    expect(result.errors).toEqual([]);
    expect(fs.readFileSync(path.join(outputDir, "runtime", "metadata.json"))).toEqual(preserved);
    expect(fs.readFileSync(path.join(outputDir, "data", "items.json"), "utf8"))
      .toBe('{"data":true,"items":[1,2]}');
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

  it("clean:false does NOT write marker to pre-existing directory", async () => {
    const outputDir = path.join(getTempDir(), "output");
    fs.mkdirSync(outputDir, { recursive: true });
    fs.writeFileSync(path.join(outputDir, "keep.txt"), "should survive");

    const filterResult = makeFilterResult(["package.json"]);
    await pack(filterResult, makeConfig(), {
      dryRun: false,
      outputDir,
      clean: false
    });

    // 旧文件应保留
    expect(fs.existsSync(path.join(outputDir, "keep.txt"))).toBe(true);
    // 新文件应被写入
    expect(fs.existsSync(path.join(outputDir, "package.json"))).toBe(true);
    // 标记不应被写入（不能静默领养已有目录）
    expect(fs.existsSync(path.join(outputDir, OUTPUT_DIR_MARKER))).toBe(false);
  });

  it("clean:false writes marker when directory is newly created", async () => {
    const outputDir = path.join(getTempDir(), "fresh-output");
    // 目录不存在

    const filterResult = makeFilterResult(["package.json"]);
    await pack(filterResult, makeConfig(), {
      dryRun: false,
      outputDir,
      clean: false
    });

    // 新目录应有标记（本工具创建的）
    expect(fs.existsSync(path.join(outputDir, OUTPUT_DIR_MARKER))).toBe(true);
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
