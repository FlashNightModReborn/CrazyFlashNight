import { describe, it, expect } from "vitest";
import { validateGitRef, validateGitPath } from "../src/git-utils.js";

describe("validateGitRef", () => {
  it("accepts HEAD", () => {
    expect(() => validateGitRef("HEAD")).not.toThrow();
  });

  it("accepts HEAD~N and HEAD^N", () => {
    expect(() => validateGitRef("HEAD~3")).not.toThrow();
    expect(() => validateGitRef("HEAD^2")).not.toThrow();
  });

  it("accepts 40-char SHA", () => {
    expect(() => validateGitRef("abc123def456abc123def456abc123def456abc1")).not.toThrow();
  });

  it("accepts Chinese tag names", () => {
    expect(() => validateGitRef("闪客快打7重置计划2.71整包")).not.toThrow();
  });

  it("accepts branch names with slashes", () => {
    expect(() => validateGitRef("feature/new-stuff")).not.toThrow();
    expect(() => validateGitRef("main")).not.toThrow();
  });

  it("rejects empty string", () => {
    expect(() => validateGitRef("")).toThrow("不安全的 git 引用");
  });

  it("rejects ref starting with -", () => {
    expect(() => validateGitRef("-flag")).toThrow("不安全的 git 引用");
    expect(() => validateGitRef("--evil")).toThrow("不安全的 git 引用");
  });

  it("rejects ref containing ..", () => {
    expect(() => validateGitRef("tag1..tag2")).toThrow("不安全的 git 引用");
    expect(() => validateGitRef("tag1...tag2")).toThrow("不安全的 git 引用");
  });

  it("rejects ref with control characters", () => {
    expect(() => validateGitRef("tag\x00evil")).toThrow("不安全的 git 引用");
    expect(() => validateGitRef("tag\nnewline")).toThrow("不安全的 git 引用");
  });
});

describe("validateGitPath", () => {
  it("accepts normal paths", () => {
    expect(() => validateGitPath("data/items/weapon.xml")).not.toThrow();
    expect(() => validateGitPath("README.md")).not.toThrow();
  });

  it("rejects empty string", () => {
    expect(() => validateGitPath("")).toThrow("不能为空");
  });

  it("rejects path starting with -", () => {
    expect(() => validateGitPath("-evil.txt")).toThrow("以 - 开头");
  });

  it("rejects path with .. as path segment (directory traversal)", () => {
    expect(() => validateGitPath("../etc/passwd")).toThrow("含 .. 路径段");
    expect(() => validateGitPath("foo/../bar")).toThrow("含 .. 路径段");
    expect(() => validateGitPath("foo/..")).toThrow("含 .. 路径段");
  });

  it("accepts filenames containing .. as substring (not traversal)", () => {
    expect(() => validateGitPath("foo..bar.txt")).not.toThrow();
    expect(() => validateGitPath("data/v2..3-changelog.xml")).not.toThrow();
    expect(() => validateGitPath("release...notes")).not.toThrow();
  });

  it("rejects path with NUL", () => {
    expect(() => validateGitPath("file\x00.txt")).toThrow("含 NUL");
  });
});
