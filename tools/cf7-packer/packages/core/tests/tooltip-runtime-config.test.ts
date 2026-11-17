import { describe, expect, it } from "vitest";
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { loadConfig } from "../src/config-loader.js";
import { filterFiles } from "../src/filter.js";
import { createMinifyPathMatcher } from "../src/minify.js";
import { pack } from "../src/packer.js";

const packerRoot = path.resolve(import.meta.dirname, "../../..");
const root = path.resolve(packerRoot, "../..");
const manifestPath = "data/tooltip/tooltip-catalog.manifest.json";
const catalogPath = "data/tooltip/tooltip-catalog.json";
const bundlePath = "launcher/scripts/dist/tooltip-bundle.js";

describe("Tooltip Logic runtime assets", () => {
  it("ships bundle, catalog, manifest and every runtime source without breaking their hashes", async () => {
    const config = loadConfig(path.join(packerRoot, "pack.config.yaml"));
    const manifest = JSON.parse(fs.readFileSync(path.join(root, manifestPath), "utf8"));
    const sourceFiles = Object.keys(manifest.sourceFiles).filter((name) => name.startsWith("data/"));
    const required = [...sourceFiles, bundlePath, catalogPath, manifestPath];
    const filtered = filterFiles(required, config);
    expect(filtered.included.map((entry) => entry.path).sort()).toEqual([...required].sort());
    const shouldMinify = createMinifyPathMatcher(config.output.minify);
    expect(required.filter(shouldMinify)).toEqual([]);
    // Ordinary unrelated data still uses the existing minification policy.
    expect(shouldMinify("data/map/map_definition.json")).toBe(true);

    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-tooltip-package-"));
    const outputDir = path.join(tempRoot, "output");
    try {
      const result = await pack(filtered, config, { dryRun: false, outputDir, clean: true });
      expect(result.errors).toEqual([]);
      expect(result.copiedFiles).toBe(required.length);
      for (const name of required) {
        const packed = fs.readFileSync(path.join(outputDir, name));
        expect(packed.equals(fs.readFileSync(path.join(root, name))), name).toBe(true);
        const expected = name === catalogPath ? manifest.outputSha256 : manifest.sourceFiles[name];
        if (expected) expect(createHash("sha256").update(packed).digest("hex")).toBe(expected);
      }
    } finally { fs.rmSync(tempRoot, { recursive: true, force: true }); }
  });
});
