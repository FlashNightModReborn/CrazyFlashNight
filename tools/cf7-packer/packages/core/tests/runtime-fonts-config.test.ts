import { describe, expect, it } from "vitest";
import path from "node:path";
import { loadConfig } from "../src/config-loader.js";
import { filterFiles } from "../src/filter.js";

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
});
