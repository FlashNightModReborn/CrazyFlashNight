/**
 * Tests for the save-config validation pipeline used in ipc-watch-handler.ts.
 * The actual IPC handler does: parseYaml → packConfigSchema.safeParse → writeConfigToDisk.
 * We test the first two stages (pure logic, no Electron dependency).
 */
import { describe, it, expect } from "vitest";
import { parse as parseYaml } from "yaml";
import { packConfigSchema } from "@cf7-packer/core";

/** Helper: runs the same validation pipeline as the save-config handler */
function validateConfig(yamlContent: string): {
  success: boolean;
  errors?: Array<{ path: string; message: string }>;
} {
  let raw: unknown;
  try {
    raw = parseYaml(yamlContent);
  } catch (err) {
    return {
      success: false,
      errors: [{ path: "", message: `YAML syntax error: ${err instanceof Error ? err.message : String(err)}` }]
    };
  }

  const result = packConfigSchema.safeParse(raw);
  if (!result.success) {
    return {
      success: false,
      errors: result.error.issues.map(issue => ({
        path: issue.path.join("."),
        message: issue.message
      }))
    };
  }
  return { success: true };
}

const VALID_YAML = `
version: 1
meta:
  name: test-config
source:
  mode: worktree
  repoRoot: "."
output:
  dir: ./out
layers:
  - name: data
    source: data/
    include:
      - "**/*"
`;

const VALID_YAML_GIT_TAG = `
version: 1
meta:
  name: tag-config
source:
  mode: git-tag
  repoRoot: "."
  tag: v1.0.0
output:
  dir: ./out
layers:
  - name: scripts
    source: scripts/
    include:
      - "**/*.as"
`;

describe("save-config validation pipeline", () => {
  describe("valid configs", () => {
    it("accepts minimal worktree config", () => {
      const result = validateConfig(VALID_YAML);
      expect(result.success).toBe(true);
      expect(result.errors).toBeUndefined();
    });

    it("accepts git-tag config with tag", () => {
      const result = validateConfig(VALID_YAML_GIT_TAG);
      expect(result.success).toBe(true);
    });

    it("accepts config with globalExclude", () => {
      const yaml = `
version: 1
meta:
  name: test
source:
  mode: worktree
  repoRoot: "."
output:
  dir: ./out
globalExclude:
  - "*.tmp"
  - ".git/**"
layers:
  - name: all
    source: ./
    include: ["**/*"]
`;
      const result = validateConfig(yaml);
      expect(result.success).toBe(true);
    });

    it("accepts config with layer-level exclude", () => {
      const yaml = `
version: 1
meta:
  name: test
source:
  mode: worktree
  repoRoot: "."
output:
  dir: ./out
layers:
  - name: data
    source: data/
    include: ["**/*"]
    exclude: ["*.bak"]
`;
      const result = validateConfig(yaml);
      expect(result.success).toBe(true);
    });
  });

  describe("YAML syntax errors", () => {
    it("rejects truncated YAML", () => {
      const result = validateConfig(":\n  : {invalid");
      expect(result.success).toBe(false);
      expect(result.errors).toHaveLength(1);
      expect(result.errors![0]!.path).toBe("");
      expect(result.errors![0]!.message).toContain("YAML syntax error");
    });

    it("rejects YAML with tab indentation", () => {
      const result = validateConfig("version: 1\n\tmeta:\n\t\tname: test");
      expect(result.success).toBe(false);
      expect(result.errors![0]!.message).toContain("YAML syntax error");
    });

    it("rejects completely empty input", () => {
      const result = validateConfig("");
      expect(result.success).toBe(false);
    });
  });

  describe("Zod schema validation errors", () => {
    it("rejects missing layers", () => {
      const yaml = `
version: 1
meta:
  name: test
source:
  mode: worktree
  repoRoot: "."
output:
  dir: ./out
`;
      const result = validateConfig(yaml);
      expect(result.success).toBe(false);
      expect(result.errors!.some(e => e.path.includes("layers"))).toBe(true);
    });

    it("rejects missing meta.name", () => {
      const yaml = `
version: 1
meta: {}
source:
  mode: worktree
  repoRoot: "."
output:
  dir: ./out
layers:
  - name: data
    source: data/
    include: ["**/*"]
`;
      const result = validateConfig(yaml);
      expect(result.success).toBe(false);
      expect(result.errors!.some(e => e.path.includes("meta"))).toBe(true);
    });

    it("rejects invalid source mode", () => {
      const yaml = `
version: 1
meta:
  name: test
source:
  mode: invalid-mode
  repoRoot: "."
output:
  dir: ./out
layers:
  - name: data
    source: data/
    include: ["**/*"]
`;
      const result = validateConfig(yaml);
      expect(result.success).toBe(false);
      expect(result.errors!.some(e => e.path.includes("source"))).toBe(true);
    });

    it("rejects layer without name", () => {
      const yaml = `
version: 1
meta:
  name: test
source:
  mode: worktree
  repoRoot: "."
output:
  dir: ./out
layers:
  - source: data/
    include: ["**/*"]
`;
      const result = validateConfig(yaml);
      expect(result.success).toBe(false);
    });

    it("accepts layer without include (defaults to empty)", () => {
      const yaml = `
version: 1
meta:
  name: test
source:
  mode: worktree
  repoRoot: "."
output:
  dir: ./out
layers:
  - name: data
    source: data/
`;
      const result = validateConfig(yaml);
      expect(result.success).toBe(true);
    });

    it("returns multiple errors for multiple violations", () => {
      const yaml = `
version: 1
source:
  mode: worktree
  repoRoot: "."
output:
  dir: ./out
`;
      const result = validateConfig(yaml);
      expect(result.success).toBe(false);
      expect(result.errors!.length).toBeGreaterThan(1);
    });
  });
});
