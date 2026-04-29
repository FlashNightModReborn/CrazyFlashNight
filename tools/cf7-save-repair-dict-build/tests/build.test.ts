import { describe, it, expect } from "vitest";
import { writeFileSync, mkdirSync, readFileSync, existsSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { build } from "../src/build.js";

/**
 * End-to-end build test against a synthetic mini project tree.
 */
describe("build (integration)", () => {
  function makeProject(name: string): string {
    const root = join(tmpdir(), "cf7-build-int-" + name + "-" + Date.now() + "-" + Math.random().toString(36).slice(2, 6));
    mkdirSync(join(root, "data", "items", "equipment_mods"), { recursive: true });
    mkdirSync(join(root, "data", "enemy_properties"), { recursive: true });
    mkdirSync(join(root, "scripts", "类定义", "org", "flashNight", "neur", "Server"), { recursive: true });
    mkdirSync(join(root, "launcher", "data"), { recursive: true });

    writeFileSync(join(root, "data", "items", "weapons.xml"), `<?xml version="1.0"?>
<root><item><name>烬灭裁决</name></item></root>`);
    writeFileSync(join(root, "data", "items", "equipment_mods", "common.xml"), `<?xml version="1.0"?>
<root><mod><name>碳纤维布料</name></mod></root>`);
    writeFileSync(join(root, "data", "enemy_properties", "e.xml"), `<?xml version="1.0"?>
<root><默认/><敌人-黑铁会大叔><displayname>大叔</displayname></敌人-黑铁会大叔></root>`);
    writeFileSync(join(root, "data", "items", "hairstyle.xml"), `<?xml version="1.0"?>
<HairStyle><Hair id="0"><Identifier>光头</Identifier></Hair></HairStyle>`);

    writeFileSync(
      join(root, "scripts", "类定义", "org", "flashNight", "neur", "Server", "SaveManager.as"),
      `class Foo {
    public static var REPAIR_DICT_SKILLS:Array = ["拳脚攻击"];
    public static var REPAIR_DICT_TASK_CHAINS:Array = ["主线"];
    public static var REPAIR_DICT_STAGES:Array = ["A兵团试炼场"];
}`,
    );
    return root;
  }

  it("writes save_repair_dict.json with expected shape", () => {
    const root = makeProject("write");
    const result = build({ projectRoot: root });
    const output = join(root, "launcher", "data", "save_repair_dict.json");
    expect(existsSync(output)).toBe(true);
    const dict = JSON.parse(readFileSync(output, "utf-8"));
    expect(dict.schemaVersion).toBe(1);
    expect(dict.items).toContain("烬灭裁决");
    expect(dict.mods).toContain("碳纤维布料");
    expect(dict.enemies).toContain("敌人-黑铁会大叔");
    expect(dict.hairstyles).toContain("光头");
    expect(dict.skills).toEqual(["拳脚攻击"]);
    expect(dict.taskChains).toEqual(["主线"]);
    expect(dict.stages).toEqual(["A兵团试炼场"]);
    expect(result.dict.generated.sourceFiles.length).toBeGreaterThan(0);
    rmSync(root, { recursive: true, force: true });
  });

  it("verify mode passes when dict is up-to-date, fails when stale", () => {
    const root = makeProject("verify");
    build({ projectRoot: root });

    const ok = build({ projectRoot: root, verify: true });
    expect(ok.verified).toBe(true);

    // Mutate AS2 source: add a new skill
    const saveManagerPath = join(
      root,
      "scripts", "类定义", "org", "flashNight", "neur", "Server", "SaveManager.as",
    );
    const src = readFileSync(saveManagerPath, "utf-8")
      .replace('REPAIR_DICT_SKILLS:Array = ["拳脚攻击"]', 'REPAIR_DICT_SKILLS:Array = ["拳脚攻击", "升龙拳"]');
    writeFileSync(saveManagerPath, src);

    const stale = build({ projectRoot: root, verify: true });
    expect(stale.verified).toBe(false);
    expect(stale.diff).toMatch(/skills/);

    rmSync(root, { recursive: true, force: true });
  });

  it("does not write the file in verify mode", () => {
    const root = makeProject("verify-no-write");
    const output = join(root, "launcher", "data", "save_repair_dict.json");
    expect(existsSync(output)).toBe(false);
    const res = build({ projectRoot: root, verify: true });
    expect(res.verified).toBe(false);
    expect(res.diff).toMatch(/does not exist/);
    expect(existsSync(output)).toBe(false);
    rmSync(root, { recursive: true, force: true });
  });
});
