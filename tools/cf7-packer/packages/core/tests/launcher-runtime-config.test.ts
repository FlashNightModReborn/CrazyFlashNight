import { afterEach, describe, expect, it } from "vitest";
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { loadConfig } from "../src/config-loader.js";
import { filterFiles } from "../src/filter.js";
import { createMinifyPathMatcher } from "../src/minify.js";
import { pack } from "../src/packer.js";

const PACKER_ROOT = path.resolve(import.meta.dirname, "../../..");
const REPO_ROOT = path.resolve(PACKER_ROOT, "../..");
const CONFIG_PATH = path.join(PACKER_ROOT, "pack.config.yaml");
const RUNTIME_MANIFEST_PATH = path.join(REPO_ROOT, "runtime", "cf7-runtime-manifest.tsv");

const NATIVE_HUD_RUNTIME_CLOSURE = [
  "cf7-runtime-manifest.tsv",
  "SkiaSharp.dll",
  "libSkiaSharp.dll",
  "ExCSS.dll",
  "HarfBuzzSharp.dll",
  "libHarfBuzzSharp.dll",
  "ShimSkiaSharp.dll",
  "Svg.Animation.dll",
  "Svg.Custom.dll",
  "Svg.Model.dll",
  "Svg.SceneGraph.dll",
  "Svg.Skia.dll",
  "THIRD-PARTY-NOTICES.txt"
] as const;

function getLauncherRuntimeLayer() {
  const config = loadConfig(CONFIG_PATH);
  const layer = config.layers.find((candidate) => candidate.name === "launcher-runtime");
  expect(layer, "pack.config.yaml must define launcher-runtime").toBeDefined();
  return { config, layer: layer! };
}

interface RuntimeManifestEntry {
  path: string;
  size: number;
  sha256: string;
}

function getManifestRuntimeEntries(): RuntimeManifestEntry[] {
  return fs.readFileSync(RUNTIME_MANIFEST_PATH, "utf8")
    .split(/\r?\n/)
    .filter((line) => line.startsWith("file\truntime/"))
    .map((line) => {
      const [, runtimePath, size, sha256] = line.split("\t");
      return {
        path: runtimePath!,
        size: Number(size),
        sha256: sha256!
      };
    });
}

function getManifestRuntimePaths(): string[] {
  return getManifestRuntimeEntries().map((entry) => entry.path);
}

describe("launcher-runtime pack config", () => {
  const tempDirs: string[] = [];

  afterEach(() => {
    for (const dir of tempDirs) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
    tempDirs.length = 0;
  });

  it("selects the explicit NativeHud SVG dependency closure without a DLL glob", () => {
    const { config, layer } = getLauncherRuntimeLayer();

    expect(layer.include).toEqual(expect.arrayContaining(NATIVE_HUD_RUNTIME_CLOSURE));
    expect(
      layer.include.filter((entry) => entry.toLowerCase().endsWith(".dll"))
        .some((entry) => /[*?[\]{}]/.test(entry))
    ).toBe(false);

    const requiredPaths = NATIVE_HUD_RUNTIME_CLOSURE.map((fileName) => `runtime/${fileName}`);
    const unexpectedDll = "runtime/Unexpected.Dependency.dll";
    const result = filterFiles([...requiredPaths, unexpectedDll], config);
    const selectedPaths = result.included
      .filter((entry) => entry.layer === "launcher-runtime")
      .map((entry) => entry.path);

    expect(selectedPaths).toEqual(requiredPaths);
    expect(selectedPaths).not.toContain(unexpectedDll);
  });

  it("selects every runtime payload file required by the current runtime manifest", () => {
    const { config } = getLauncherRuntimeLayer();
    const manifestRuntimePaths = getManifestRuntimePaths();
    expect(manifestRuntimePaths.length).toBeGreaterThan(0);

    const result = filterFiles(manifestRuntimePaths, config);
    const selectedPaths = new Set(
      result.included
        .filter((entry) => entry.layer === "launcher-runtime")
        .map((entry) => entry.path)
    );

    expect(manifestRuntimePaths.filter((runtimePath) => !selectedPaths.has(runtimePath))).toEqual([]);
  });

  it("preserves exact bytes and manifest hashes for integrity-governed JSON payloads", async () => {
    const { config } = getLauncherRuntimeLayer();
    const manifestJsonEntries = getManifestRuntimeEntries()
      .filter((entry) => entry.path.toLowerCase().endsWith(".json"));
    const shouldMinify = createMinifyPathMatcher(config.output.minify);

    expect(config.output.minify?.enabled).toBe(true);
    expect(config.output.minify?.extensions).toContain(".json");
    expect(manifestJsonEntries.length).toBeGreaterThan(0);
    expect(manifestJsonEntries.every((entry) => !shouldMinify(entry.path))).toBe(true);
    expect(shouldMinify("config/build/runtime-release-consensus.json")).toBe(false);
    expect(shouldMinify("launcher/data/map_hud_data.json")).toBe(true);

    const filterResult = filterFiles(manifestJsonEntries.map((entry) => entry.path), config);
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-runtime-byte-test-"));
    tempDirs.push(tempRoot);
    const outputDir = path.join(tempRoot, "output");
    const result = await pack(filterResult, config, {
      dryRun: false,
      outputDir,
      clean: true
    });

    expect(result.errors).toEqual([]);
    expect(result.copiedFiles).toBe(manifestJsonEntries.length);
    for (const entry of manifestJsonEntries) {
      const sourceBytes = fs.readFileSync(path.join(REPO_ROOT, entry.path));
      const packedBytes = fs.readFileSync(path.join(outputDir, entry.path));
      expect(packedBytes).toEqual(sourceBytes);
      expect(packedBytes.byteLength).toBe(entry.size);
      expect(createHash("sha256").update(packedBytes).digest("hex").toUpperCase()).toBe(entry.sha256);
    }
  });
});
