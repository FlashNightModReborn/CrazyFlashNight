import { describe, it, expect } from "vitest";
import { writeFileSync, mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { extractAs2DictConstant } from "../src/as2-constants.js";

function tmpFile(name: string, content: string): string {
  const dir = join(tmpdir(), "cf7-as2-test-" + Date.now() + "-" + Math.random().toString(36).slice(2, 8));
  mkdirSync(dir, { recursive: true });
  const f = join(dir, name);
  writeFileSync(f, content);
  return f;
}

describe("extractAs2DictConstant", () => {
  it("parses a simple multi-line literal array", () => {
    const f = tmpFile("a.as", `class Foo {
    public static var REPAIR_DICT_SKILLS:Array = [
        "拳脚攻击",
        "升龙拳",
        "龟派气功"
    ];
}`);
    const out = extractAs2DictConstant(f, "REPAIR_DICT_SKILLS");
    expect(out).toEqual(["拳脚攻击", "升龙拳", "龟派气功"]);
  });

  it("handles inline arrays and trailing commas", () => {
    const f = tmpFile("b.as", `class Foo {
    public static var REPAIR_DICT_TASK_CHAINS:Array = ["主线", "支线", "彩蛋"];
}`);
    expect(extractAs2DictConstant(f, "REPAIR_DICT_TASK_CHAINS")).toEqual(["主线", "支线", "彩蛋"]);
  });

  it("ignores // line comments inside the literal", () => {
    const f = tmpFile("c.as", `class Foo {
    public static var REPAIR_DICT_STAGES:Array = [
        // 主线关
        "A兵团试炼场",
        "深入禁区",
        // BOSS
        "通缉任务之异形"
    ];
}`);
    expect(extractAs2DictConstant(f, "REPAIR_DICT_STAGES")).toEqual([
      "A兵团试炼场",
      "深入禁区",
      "通缉任务之异形",
    ]);
  });

  it("supports single-quoted strings", () => {
    const f = tmpFile("d.as", `class Foo {
    public static var REPAIR_DICT_SKILLS:Array = ['拳脚攻击', '升龙拳'];
}`);
    expect(extractAs2DictConstant(f, "REPAIR_DICT_SKILLS")).toEqual(["拳脚攻击", "升龙拳"]);
  });

  it("throws when constant is missing", () => {
    const f = tmpFile("e.as", `class Foo {}`);
    expect(() => extractAs2DictConstant(f, "REPAIR_DICT_SKILLS")).toThrow(/REPAIR_DICT_SKILLS not found/);
  });

  it("throws when array is unterminated", () => {
    const f = tmpFile("f.as", `public static var REPAIR_DICT_SKILLS:Array = [
        "拳脚攻击",
        "升龙拳"`);
    expect(() => extractAs2DictConstant(f, "REPAIR_DICT_SKILLS")).toThrow(/Unterminated/);
  });
});
