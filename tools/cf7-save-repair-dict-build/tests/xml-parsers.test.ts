import { describe, it, expect } from "vitest";
import { writeFileSync, mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { parseItemsDir, parseModsDir, parseEnemiesDir, parseHairstyleFile } from "../src/xml-parsers.js";

function makeFixture(name: string): string {
  const dir = join(tmpdir(), "cf7-dict-build-test-" + name + "-" + Date.now());
  mkdirSync(dir, { recursive: true });
  return dir;
}

describe("parseItemsDir", () => {
  it("extracts <name> from each <item> across XMLs, dedupes, skips list/asset_source_map", () => {
    const dir = makeFixture("items");
    writeFileSync(join(dir, "weapons.xml"), `<?xml version="1.0" encoding="UTF-8"?>
<root>
  <item><name>破旧的军刀</name></item>
  <item><name>烬灭裁决</name></item>
</root>`);
    writeFileSync(join(dir, "armor.xml"), `<?xml version="1.0"?>
<root>
  <item><name>芬里尔头甲</name></item>
  <item><name>烬灭裁决</name></item>
</root>`);
    writeFileSync(join(dir, "list.xml"), `<root><items>weapons.xml</items></root>`);
    writeFileSync(join(dir, "asset_source_map.xml"), `<root><foo>bar</foo></root>`);

    const res = parseItemsDir(dir);
    expect(res.names).toContain("破旧的军刀");
    expect(res.names).toContain("烬灭裁决");
    expect(res.names).toContain("芬里尔头甲");
    expect(res.names.filter((n) => n === "烬灭裁决")).toHaveLength(1);
    expect(res.sourceFiles).toHaveLength(2);

    rmSync(dir, { recursive: true, force: true });
  });

  it("filters out names containing U+FFFD (already corrupted entries)", () => {
    const dir = makeFixture("items-fffd");
    writeFileSync(join(dir, "a.xml"), `<?xml version="1.0"?>
<root>
  <item><name>正常物品</name></item>
  <item><name>坏�名字</name></item>
</root>`);
    const res = parseItemsDir(dir);
    expect(res.names).toEqual(["正常物品"]);
    rmSync(dir, { recursive: true, force: true });
  });
});

describe("parseModsDir", () => {
  it("extracts <mod><name> from equipment_mods XMLs", () => {
    const dir = makeFixture("mods");
    writeFileSync(join(dir, "common.xml"), `<?xml version="1.0"?>
<root>
  <mod><name>增效剂</name></mod>
  <mod><name>碳纤维布料</name></mod>
</root>`);
    const res = parseModsDir(dir);
    expect(res.names).toContain("增效剂");
    expect(res.names).toContain("碳纤维布料");
    rmSync(dir, { recursive: true, force: true });
  });
});

describe("parseEnemiesDir", () => {
  it("extracts top-level enemy element names (敌人-/主角-/修改器 prefix), skips 默认", () => {
    const dir = makeFixture("enemies");
    writeFileSync(join(dir, "e.xml"), `<?xml version="1.0"?>
<root>
    <默认>
        <hp_min>100</hp_min>
    </默认>
    <敌人-黑铁会大叔>
        <displayname>大叔</displayname>
    </敌人-黑铁会大叔>
    <敌人-黑铁武士>
        <displayname>武士</displayname>
    </敌人-黑铁武士>
    <主角-男>
        <displayname>主角</displayname>
    </主角-男>
</root>`);
    const res = parseEnemiesDir(dir);
    expect(res.names).toContain("敌人-黑铁会大叔");
    expect(res.names).toContain("敌人-黑铁武士");
    expect(res.names).toContain("主角-男");
    expect(res.names).not.toContain("默认");
    rmSync(dir, { recursive: true, force: true });
  });
});

describe("parseHairstyleFile", () => {
  it("extracts <Hair><Identifier> values", () => {
    const dir = makeFixture("hair");
    const file = join(dir, "hairstyle.xml");
    writeFileSync(file, `<?xml version="1.0" encoding="utf-8"?>
<HairStyle>
    <Hair id="0"><Identifier>光头</Identifier><Name>光头</Name></Hair>
    <Hair id="1"><Identifier>发型-男式-黑暴走头</Identifier><Name>发型-男式-黑暴走头</Name></Hair>
</HairStyle>`);
    const res = parseHairstyleFile(file);
    expect(res).toContain("光头");
    expect(res).toContain("发型-男式-黑暴走头");
    rmSync(dir, { recursive: true, force: true });
  });
});
