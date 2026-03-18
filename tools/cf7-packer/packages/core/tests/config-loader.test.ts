import { describe, it, expect, afterEach } from "vitest";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { loadConfig, parseConfig } from "../src/config-loader.js";

describe("config-loader", () => {
  const tempDirs: string[] = [];

  function getTempDir(): string {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-config-test-"));
    tempDirs.push(dir);
    return dir;
  }

  afterEach(() => {
    for (const dir of tempDirs) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
    tempDirs.length = 0;
  });

  it("loads a valid YAML config", () => {
    const dir = getTempDir();
    const yaml = `
version: 1
meta:
  name: "test"
source:
  mode: worktree
  repoRoot: "."
output:
  dir: "./out"
  clean: true
layers:
  - name: data
    source: "data/"
    include: ["**/*"]
    exclude: []
globalExclude: []
`;
    fs.writeFileSync(path.join(dir, "pack.config.yaml"), yaml, "utf8");
    const config = loadConfig(path.join(dir, "pack.config.yaml"));
    expect(config.meta.name).toBe("test");
    expect(config.source.mode).toBe("worktree");
    expect(config.source.repoRoot).toBe(path.resolve(dir, "."));
    expect(config.layers).toHaveLength(1);
    expect(config.layers[0]!.name).toBe("data");
  });

  it("resolves repoRoot relative to config file directory", () => {
    const dir = getTempDir();
    const yaml = `
version: 1
meta:
  name: "test"
source:
  mode: worktree
  repoRoot: "../../"
output:
  dir: "./out"
  clean: true
layers:
  - name: all
    source: "."
    include: ["**/*"]
    exclude: []
`;
    fs.writeFileSync(path.join(dir, "pack.config.yaml"), yaml, "utf8");
    const config = loadConfig(path.join(dir, "pack.config.yaml"));
    expect(config.source.repoRoot).toBe(path.resolve(dir, "../../"));
  });

  it("throws on missing file", () => {
    expect(() => loadConfig("/nonexistent/pack.config.yaml")).toThrow();
  });

  it("throws on invalid YAML", () => {
    const dir = getTempDir();
    fs.writeFileSync(path.join(dir, "bad.yaml"), "{{invalid yaml", "utf8");
    expect(() => loadConfig(path.join(dir, "bad.yaml"))).toThrow();
  });

  it("throws on schema validation failure (missing required fields)", () => {
    const dir = getTempDir();
    const yaml = `
version: 1
meta:
  name: "test"
source:
  mode: worktree
  repoRoot: "."
output:
  dir: "./out"
layers: []
`;
    fs.writeFileSync(path.join(dir, "pack.config.yaml"), yaml, "utf8");
    // layers requires at least 1 element
    expect(() => loadConfig(path.join(dir, "pack.config.yaml"))).toThrow();
  });

  it("parseConfig works with raw JS object", () => {
    const raw = {
      version: 1,
      meta: { name: "test" },
      source: { mode: "worktree", repoRoot: "." },
      output: { dir: "./out", clean: true },
      layers: [{ name: "all", source: ".", include: ["**/*"], exclude: [] }]
    };
    const dir = os.tmpdir();
    const config = parseConfig(raw, dir);
    expect(config.meta.name).toBe("test");
    expect(config.source.repoRoot).toBe(path.resolve(dir, "."));
  });
});
