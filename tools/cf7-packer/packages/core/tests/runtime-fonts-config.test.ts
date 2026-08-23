import { describe, expect, it } from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { loadConfig } from "../src/config-loader.js";
import { filterFiles } from "../src/filter.js";
import { pack } from "../src/packer.js";

const PACKER_ROOT = path.resolve(import.meta.dirname, "../../..");
const CONFIG_PATH = path.join(PACKER_ROOT, "pack.config.yaml");

describe("runtime-fonts pack config", () => {
  it("ships the governed Gate E closure and excludes temporary and Flash-authoring fonts", () => {
    const config = loadConfig(CONFIG_PATH);
    const layer = config.layers.find((candidate) => candidate.name === "runtime-fonts");
    expect(layer).toBeDefined();

    const files = [
      "fonts/README.md",
      "fonts/fonts.xml",
      "fonts/fonts.xsd",
      "fonts/licenses/JetBrainsMono-OFL-1.1.txt",
      "fonts/licenses/SourceHanSerif-OFL-1.1.txt",
      "fonts/permanent/runtime/jetbrains-mono.woff2",
      "fonts/permanent/runtime/source-han-serif-cn-regular.otf",
      "fonts/temporary/custom/player.ttf",
      "fonts/temporary/cache/download.ttf",
      "闪7重置版字体/legacy.ttf"
    ];
    const result = filterFiles(files, config);
    const selected = result.included
      .filter((entry) => entry.layer === "runtime-fonts")
      .map((entry) => entry.path);

    expect(selected).toEqual(files.slice(0, 7));
    expect(result.included.map((entry) => entry.path)).not.toContain("fonts/temporary/custom/player.ttf");
    expect(result.included.map((entry) => entry.path)).not.toContain("fonts/temporary/cache/download.ttf");
    expect(result.included.map((entry) => entry.path)).not.toContain("闪7重置版字体/legacy.ttf");
  });

  it("filters and packages every generated Web font projection into the launcher closure", async () => {
    const config = loadConfig(CONFIG_PATH);
    const generatedClosure = [
      "launcher/web/generated/font-catalog.json",
      "launcher/web/generated/font-catalog.css",
      "launcher/web/generated/font-catalog.js",
      "launcher/web/assets/fonts/font-pack-manifest.json"
    ];
    const filtered = filterFiles(generatedClosure, config);

    expect(filtered.unmatchedCount).toBe(0);
    expect(filtered.excluded).toEqual([]);
    expect(filtered.included.map((entry) => [entry.path, entry.layer])).toEqual(
      generatedClosure.map((file) => [file, "launcher-web"])
    );

    const outputDir = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-packer-font-closure-"));
    try {
      const result = await pack(filtered, config, {
        dryRun: false,
        outputDir,
        clean: false
      });
      expect(result.errors).toEqual([]);
      expect(result.copiedFiles).toBe(generatedClosure.length);
      for (const file of generatedClosure) {
        expect(fs.statSync(path.join(outputDir, file)).isFile()).toBe(true);
      }
      const manifest = JSON.parse(fs.readFileSync(
        path.join(outputDir, "launcher/web/assets/fonts/font-pack-manifest.json"),
        "utf8"
      ));
      expect(manifest.generatedBy).toBe("tools/fontctl");
    } finally {
      fs.rmSync(outputDir, { recursive: true, force: true });
    }
  });
});
