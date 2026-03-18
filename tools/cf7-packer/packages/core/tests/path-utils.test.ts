import { describe, it, expect } from "vitest";
import path from "node:path";
import { normalizeRepoRelativePath, normalizeLayerSource, isPathInsideRoot } from "../src/path-utils.js";

describe("normalizeRepoRelativePath", () => {
  it("accepts simple relative path", () => {
    expect(normalizeRepoRelativePath("data/items/weapon.xml")).toBe("data/items/weapon.xml");
  });

  it("strips leading ./", () => {
    expect(normalizeRepoRelativePath("./data/items/weapon.xml")).toBe("data/items/weapon.xml");
  });

  it("strips multiple leading ./", () => {
    expect(normalizeRepoRelativePath("././data/file.txt")).toBe("data/file.txt");
  });

  it("normalizes backslashes to forward slashes", () => {
    expect(normalizeRepoRelativePath("data\\items\\weapon.xml")).toBe("data/items/weapon.xml");
  });

  it("rejects empty path", () => {
    expect(() => normalizeRepoRelativePath("")).toThrow("不能为空");
  });

  it("rejects path with ..", () => {
    expect(() => normalizeRepoRelativePath("data/../secrets.txt")).toThrow("不能包含 ..");
    expect(() => normalizeRepoRelativePath("../outside")).toThrow("不能包含 ..");
  });

  it("ignores single dots in path", () => {
    expect(normalizeRepoRelativePath("data/./items/file.txt")).toBe("data/items/file.txt");
  });

  it("rejects absolute Unix path", () => {
    expect(() => normalizeRepoRelativePath("/etc/passwd")).toThrow("相对路径");
  });

  it("rejects Windows drive letter", () => {
    expect(() => normalizeRepoRelativePath("C:\\Users\\file.txt")).toThrow("相对路径");
    expect(() => normalizeRepoRelativePath("D:/data/file.txt")).toThrow("相对路径");
  });

  it("handles deeply nested paths", () => {
    expect(normalizeRepoRelativePath("a/b/c/d/e/f.txt")).toBe("a/b/c/d/e/f.txt");
  });

  it("strips duplicate slashes", () => {
    expect(normalizeRepoRelativePath("data//items///file.txt")).toBe("data/items/file.txt");
  });
});

describe("normalizeLayerSource", () => {
  it("recognizes '.' as root", () => {
    const result = normalizeLayerSource(".");
    expect(result.isRoot).toBe(true);
    expect(result.prefix).toBe("");
    expect(result.sourceRoot).toBe("");
  });

  it("recognizes './' as root", () => {
    const result = normalizeLayerSource("./");
    expect(result.isRoot).toBe(true);
  });

  it("returns prefix with trailing slash for non-root", () => {
    const result = normalizeLayerSource("data");
    expect(result.isRoot).toBe(false);
    expect(result.prefix).toBe("data/");
    expect(result.sourceRoot).toBe("data");
  });

  it("handles source already ending with /", () => {
    const result = normalizeLayerSource("data/");
    expect(result.isRoot).toBe(false);
    expect(result.prefix).toBe("data/");
  });

  it("normalizes backslashes", () => {
    const result = normalizeLayerSource("flashswf\\arts");
    expect(result.prefix).toBe("flashswf/arts/");
  });
});

describe("isPathInsideRoot", () => {
  const root = path.resolve("/test/root");

  it("returns true for child path", () => {
    expect(isPathInsideRoot(root, path.join(root, "sub", "file.txt"))).toBe(true);
  });

  it("returns true for same path (root itself)", () => {
    expect(isPathInsideRoot(root, root)).toBe(true);
  });

  it("returns false for parent path", () => {
    expect(isPathInsideRoot(root, path.dirname(root))).toBe(false);
  });

  it("returns false for sibling path", () => {
    expect(isPathInsideRoot(root, path.resolve("/test/other"))).toBe(false);
  });

  it("returns false for .. escape", () => {
    expect(isPathInsideRoot(root, path.resolve(root, "..", "other"))).toBe(false);
  });
});
