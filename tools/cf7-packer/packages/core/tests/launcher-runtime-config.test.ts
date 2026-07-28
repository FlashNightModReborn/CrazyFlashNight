import { describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { loadConfig } from "../src/config-loader.js";
import { filterFiles } from "../src/filter.js";

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

function getManifestRuntimePaths(): string[] {
  return fs.readFileSync(RUNTIME_MANIFEST_PATH, "utf8")
    .split(/\r?\n/)
    .filter((line) => line.startsWith("file\truntime/"))
    .map((line) => line.split("\t")[1]!)
    .filter(Boolean);
}

describe("launcher-runtime pack config", () => {
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
});
