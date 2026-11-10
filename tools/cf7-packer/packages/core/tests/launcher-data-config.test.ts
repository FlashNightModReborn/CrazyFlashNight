import { describe, expect, it } from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { loadConfig } from "../src/config-loader.js";
import { filterFiles } from "../src/filter.js";
import { pack } from "../src/packer.js";

const CONFIG_PATH = path.resolve(import.meta.dirname, "../../../pack.config.yaml");
const RUNTIME_DATA = [
  "launcher/data/save_repair_dict.json",
  "launcher/data/save_schema.json",
  "launcher/data/guidance-catalog.json",
  "launcher/data/tutorial-journeys.json",
  "launcher/data/scene-transition/catalog.manifest.json"
];
// launcher/data 整目录收（6568d4c299）：逐文件白名单曾漏掉 world-lighting 导致启动即崩，
// 因此唯一允许落选的是运行期生成的画像缓存，它们由本机对话/换装管线写出。
const RUNTIME_CACHES = [
  "launcher/data/dialogue-portraits/npc-sample.webp",
  "launcher/data/doll-portraits/doll-sample.png"
];

function listWorktreeDataFiles(repoRoot: string): string[] {
  const files: string[] = [];
  const walk = (dir: string) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else files.push(path.relative(repoRoot, full).replace(/\\/g, "/"));
    }
  };
  walk(path.join(repoRoot, "launcher/data"));
  return files;
}

describe("launcher startup data in the player package", () => {
  it("ships every launcher/data file and drops only the runtime portrait caches", () => {
    const config = loadConfig(CONFIG_PATH);
    const selected = filterFiles([...RUNTIME_DATA, ...RUNTIME_CACHES], config);
    expect(selected.included.map(entry => [entry.path, entry.layer])).toEqual(
      RUNTIME_DATA.map(file => [file, "launcher-data"])
    );
    expect(selected.excluded.map(entry => [entry.path, entry.layer])).toEqual(
      RUNTIME_CACHES.map(file => [file, "launcher-data"])
    );
    expect(selected.unmatchedCount).toBe(0);
  });

  it("keeps every worktree file under launcher/data except the caches in the package", () => {
    const config = loadConfig(CONFIG_PATH);
    const all = listWorktreeDataFiles(config.source.repoRoot);
    const caches = all.filter(file => /^launcher\/data\/(dialogue|doll)-portraits\//.test(file));
    const selected = filterFiles(all, config);
    expect(selected.included.map(entry => entry.path).sort()).toEqual(
      all.filter(file => !caches.includes(file)).sort()
    );
    expect(selected.excluded.map(entry => entry.path).sort()).toEqual(caches.sort());
    expect(selected.unmatchedCount).toBe(0);
  });

  it("copies every required JSON into a real output and preserves its content", async () => {
    const config = loadConfig(CONFIG_PATH);
    const selected = filterFiles(RUNTIME_DATA, config);
    const outputDir = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-launcher-data-"));
    try {
      const result = await pack(selected, config, { dryRun: false, outputDir, clean: false });
      expect(result.errors).toEqual([]);
      expect(result.copiedFiles).toBe(RUNTIME_DATA.length);
      for (const file of RUNTIME_DATA) {
        expect(JSON.parse(fs.readFileSync(path.join(outputDir, file), "utf8"))).toEqual(
          JSON.parse(fs.readFileSync(path.join(config.source.repoRoot, file), "utf8"))
        );
      }
    } finally {
      if (path.dirname(path.resolve(outputDir)) !== path.resolve(os.tmpdir())
          || !path.basename(outputDir).startsWith("cf7-launcher-data-")) {
        throw new Error("Unexpected temporary package directory");
      }
      fs.rmSync(outputDir, { recursive: true, force: true });
    }
  });
});
