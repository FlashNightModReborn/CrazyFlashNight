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

describe("launcher startup data in the player package", () => {
  it("includes the runtime data without admitting arbitrary editor fixtures", () => {
    const config = loadConfig(CONFIG_PATH);
    const selected = filterFiles([...RUNTIME_DATA, "launcher/data/editor-fixture.json"], config);
    expect(selected.included.map(entry => [entry.path, entry.layer])).toEqual(
      RUNTIME_DATA.map(file => [file, "launcher-data"])
    );
    expect(selected.unmatchedCount).toBe(1);
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
