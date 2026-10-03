import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { applyMonsterFlagUpdates, censusMonsterFlags } from "../src/monster-flags.js";
import { buildStageIndex, resolveFirstAppearance } from "../src/monster-stage.js";
import type { MonsterCensusConfig } from "../src/monster-stage.js";

/** 与 data/monster-census.json 同构的最小配置，只保留测试需要的区间与目录。 */
const CONFIG: MonsterCensusConfig = {
  version: 1,
  flagFields: ["阶段", "档次系数", "成长系数", "攻速系数", "攻击倍率", "段数系数", "速度系数", "高攻低血防系数", "霸体系数", "高防低血系数"],
  panelFields: {
    空手攻击力_min: "atkMin",
    空手攻击力_max: "atkMax",
    hp_min: "hpMin",
    hp_max: "hpMax",
    基本防御力_min: "defMin",
    基本防御力_max: "defMax",
    最小经验值: "expMin",
    最大经验值: "expMax",
  },
  moveSpeedFields: { min: "速度_min", max: "速度_max" },
  tenacityField: "韧性系数",
  displayNameField: "displayname",
  flagElement: "标识",
  templatePrefix: "敌人-",
  excludedSourceFiles: ["魔神.xml"],
  excludedStagePatterns: ["菲尼克斯"],
  mainlineCompletedUntil: 77,
  mainlineBands: [
    { from: 1, to: 22, stage: 1, label: "废城" },
    { from: 23, to: 29, stage: 2, label: "盗贼" },
  ],
  chapters: { 基地门口: 1, 基地车库: 2 },
  stageChapterOverrides: {},
};

describe("monster stage index", () => {
  it("主线/支线/解锁三条路径各自给出阶段与依据", () => {
    const index = buildStageIndex(writeFixtureRepo(), CONFIG);

    expect(resolveFirstAppearance("敌人-主线怪", index).resolution).toMatchObject({ status: "mainline", stageNumber: 1 });
    expect(resolveFirstAppearance("敌人-支线怪", index).resolution).toMatchObject({ status: "subquest", stageNumber: 2, mainlineId: 2 });
    expect(resolveFirstAppearance("敌人-解锁怪", index).resolution).toMatchObject({ status: "unlock", stageNumber: 2 });
    expect(resolveFirstAppearance("敌人-远期怪", index).resolution?.status).toBe("deferred");
  });

  it("被排除关卡与从未登场的模板都拿不到阶段", () => {
    const index = buildStageIndex(writeFixtureRepo(), CONFIG);

    expect(resolveFirstAppearance("敌人-魔神boss", index).candidates).toEqual([]);
    expect(resolveFirstAppearance("敌人-未登场", index).resolution?.status).toBe("unresolved");
  });
});

describe("monster flag census", () => {
  it("按标识完备度分档，并登记阶段来源与缺项", () => {
    const census = censusMonsterFlags(writeFixtureRepo(), CONFIG);

    expect(census.sourceFiles).toEqual(["测试.xml"]);
    expect(census.excludedSourceFiles).toEqual(["魔神.xml"]);
    expect(census.totals).toMatchObject({ templates: 4, complete: 1, partial: 1, missing: 2 });

    const partial = census.rows.find((row) => row.status === "partial");
    expect(partial?.spritename).toBe("敌人-残缺怪");
    expect(partial?.missingFlags).toEqual(["速度系数"]);
    expect(partial?.stageSource).toBe("flag");
    expect(partial?.moveSpeed).toEqual({ min: 45, max: 65 });

    const unflagged = census.rows.find((row) => row.spritename === "敌人-主线怪");
    expect(unflagged?.stageSource).toBe("first-appearance");
    expect(unflagged?.stageNumber).toBe(1);
    expect(unflagged?.skipReason).toBe("档次系数待人工标注");
    expect(unflagged?.solve).toBeUndefined();

    expect(census.unreferencedSprites).toEqual(["敌人-未登场"]);
  });

  it("档次提示到位后产出可复核的反推候选", () => {
    const census = censusMonsterFlags(writeFixtureRepo(), CONFIG, { tierHints: { "敌人-主线怪": 2 } });
    const row = census.rows.find((entry) => entry.spritename === "敌人-主线怪");

    expect(row?.solve?.tierSource).toBe("hint");
    expect(row?.solve?.unresolved).toEqual(expect.arrayContaining(["atkSpeedFactor", "atkMultiplier", "segmentFactor"]));
    expect(row?.solve?.attackTempoTarget).toBeGreaterThan(0);
    expect(row?.skipReason).toBeUndefined();
  });

  it("扫描档次只作排序参考", () => {
    const census = censusMonsterFlags(writeFixtureRepo(), CONFIG, { scanTier: true, tierCandidateCount: 2 });
    const row = census.rows.find((entry) => entry.spritename === "敌人-主线怪");

    expect(row?.tierCandidates?.length).toBeLessThanOrEqual(2);
    expect(row?.tierCandidates?.every((candidate) => candidate.fitError > 0)).toBe(true);
  });

  it("写回标识时保留中文注释并补齐缺失字段", () => {
    const repo = writeFixtureRepo();
    const written = applyMonsterFlagUpdates(
      repo,
      [
        { sourceFile: "测试.xml", spritename: "敌人-主线怪", flags: { 阶段: 1, 档次系数: 2, 成长系数: 1 } },
        { sourceFile: "测试.xml", spritename: "敌人-残缺怪", flags: { 速度系数: 2.5 } },
      ],
      CONFIG,
    );

    expect(written.length).toBe(1);
    const text = fs.readFileSync(path.join(repo, "data", "enemy_properties", "测试.xml"), "utf8");
    expect(text).toContain("<!-- 废城登场 -->");
    expect(text).toMatch(/<敌人-主线怪>[\s\S]*?<标识>[\s\S]*?<阶段>1<\/阶段>[\s\S]*?<档次系数>2<\/档次系数>[\s\S]*?<\/标识>[\s\S]*?<\/敌人-主线怪>/);
    expect(text).toMatch(/<敌人-残缺怪>[\s\S]*?<速度系数>2\.5<\/速度系数>[\s\S]*?<\/标识>[\s\S]*?<\/敌人-残缺怪>/);
    expect(censusMonsterFlags(repo, CONFIG).totals.complete).toBe(2);

    // 写回不能留下只有空白的行；新字段按兄弟行缩进对齐，即使标识块本身用制表符（天网.xml 就是这样）。
    expect(text).not.toMatch(/^[ \t]+$/m);
    expect(text).toContain("            <速度系数>2.5</速度系数>\n\t\t</标识>");
    expect(text).toMatch(/\n        <标识>\n            <阶段>1<\/阶段>[\s\S]*?\n        <\/标识>\n    <\/敌人-主线怪>/);
  });
});

const PANEL = [
  "<displayname>废城流民</displayname>",
  "<最小经验值>120</最小经验值>",
  "<最大经验值>600</最大经验值>",
  "<hp_min>800</hp_min>",
  "<hp_max>2400</hp_max>",
  "<速度_min>20</速度_min>",
  "<速度_max>35</速度_max>",
  "<空手攻击力_min>40</空手攻击力_min>",
  "<空手攻击力_max>150</空手攻击力_max>",
  "<基本防御力_min>120</基本防御力_min>",
  "<基本防御力_max>420</基本防御力_max>",
  "<韧性系数>1</韧性系数>",
].map((line) => `        ${line}`);

/** 残缺怪已标注九个系数，只差速度系数，用来验证补写与分档。 */
const NEAR_COMPLETE_FLAGS = [
  ["阶段", 2],
  ["档次系数", 3],
  ["成长系数", 1],
  ["攻速系数", 3],
  ["攻击倍率", 1],
  ["段数系数", 3],
  ["高攻低血防系数", 1],
  ["霸体系数", 1],
  ["高防低血系数", 1],
] as const;

function writeFixtureRepo(): string {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-monster-"));

  write(repo, "data/stages/基地门口/__list__.xml", `<?xml version='1.0' encoding='UTF-8'?>
<root>
    <StageInfo><Name>废城街头</Name><Type>主线</Type><UnlockCondition>1</UnlockCondition></StageInfo>
    <StageInfo><Name>支线矿洞</Name><Type>支线</Type><UnlockCondition>2</UnlockCondition></StageInfo>
    <StageInfo><Name>无任务关卡</Name><Type>副本</Type><UnlockCondition>9</UnlockCondition></StageInfo>
</root>
`);
  write(repo, "data/stages/基地门口/废城街头.xml", stageXml([1]));
  write(repo, "data/stages/基地门口/支线矿洞.xml", stageXml([2]));
  write(repo, "data/stages/基地门口/无任务关卡.xml", stageXml([3, 5]));

  write(repo, "data/stages/基地车库/__list__.xml", `<root>
    <StageInfo><Name>诺亚前哨</Name><Type>主线</Type><UnlockCondition>80</UnlockCondition></StageInfo>
    <StageInfo><Name>菲尼克斯Lv10</Name><Type>挑战</Type></StageInfo>
</root>
`);
  write(repo, "data/stages/基地车库/诺亚前哨.xml", stageXml([4]));
  write(repo, "data/stages/基地车库/菲尼克斯Lv10.xml", stageXml([], ["敌人-魔神boss"]));

  write(repo, "data/units/units.json", JSON.stringify([
    { id: 1, spritename: "敌人-主线怪" },
    { id: 2, spritename: "敌人-支线怪" },
    { id: 3, spritename: "敌人-解锁怪" },
    { id: 4, spritename: "敌人-远期怪" },
    { id: 5, spritename: "敌人-残缺怪" },
  ]));

  write(repo, "data/task/list.xml", "<root>\n    <task>tasks1.json</task>\n</root>\n");
  write(repo, "data/task/tasks1.json", JSON.stringify({
    tasks: [
      { id: 100, chain: "主线#2", get_requirements: [], finish_requirements: ["废城街头#0"] },
      { id: 200, chain: "支线#5", get_requirements: [100], finish_requirements: ["支线矿洞#0"] },
    ],
  }));

  write(repo, "data/enemy_properties/list.xml", "<root>\n    <items>测试.xml</items>\n    <items>魔神.xml</items>\n</root>\n");
  write(repo, "data/enemy_properties/测试.xml", `<?xml version='1.0' encoding='UTF-8'?>
<root>
    <!-- 废城登场 -->
    <敌人-主线怪>
${PANEL.join("\n")}
    </敌人-主线怪>
    <敌人-残缺怪>
        <最小经验值>200</最小经验值>
        <速度_min>45</速度_min>
        <速度_max>65</速度_max>
\t\t<标识>
${NEAR_COMPLETE_FLAGS.map(([field, value]) => `            <${field}>${value}</${field}>`).join("\n")}
\t\t</标识>
    </敌人-残缺怪>
    <敌人-支线怪>
        <hp_min>500</hp_min>
        <标识>
${NEAR_COMPLETE_FLAGS.map(([field, value]) => `            <${field}>${value}</${field}>`).join("\n")}
            <速度系数>2</速度系数>
        </标识>
    </敌人-支线怪>
    <敌人-未登场/>
</root>
`);
  write(repo, "data/enemy_properties/魔神.xml", "<root>\n    <敌人-魔神boss><hp_min>99999</hp_min></敌人-魔神boss>\n</root>\n");

  return repo;
}

function stageXml(unitIds: number[], spriteNames: string[] = []): string {
  const enemies = [
    ...unitIds.map((id) => `            <Enemy id="${id}">\n                <Type>兵种${id}</Type>\n            </Enemy>`),
    ...spriteNames.map((name) => `            <Enemy id="90">\n                <spritename>${name}</spritename>\n            </Enemy>`),
  ].join("\n");
  return `<?xml version='1.0' encoding='UTF-8'?>
<GameStage>
    <SubStage id="0">
        <EnemyGroup>
${enemies}
        </EnemyGroup>
    </SubStage>
</GameStage>
`;
}

function write(repo: string, relative: string, text: string): void {
  const target = path.join(repo, relative);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, text, "utf8");
}
