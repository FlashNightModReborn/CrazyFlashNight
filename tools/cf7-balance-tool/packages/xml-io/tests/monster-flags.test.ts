import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import {
  applyMonsterFlagUpdates,
  censusMonsterFlags,
  fitPinnedCoefficients,
  isFullyHumanFlagged,
  readFlagsFromSource,
  stageProgressLabel,
  tierLabel,
  toolFlagProposal,
} from "../src/monster-flags.js";
import { buildStageIndex, parseCsvRows, resolveFirstAppearance } from "../src/monster-stage.js";
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
  noFlagTemplates: ["敌人-未登场"],
  humanTierFactors: { "敌人-支线怪": 3 },
  stageLabels: [
    { from: 1, to: 22, label: "废城" },
    { from: 23, to: 29, label: "盗贼" },
  ],
  tierLabels: [
    { from: 1, to: 1, label: "小型小怪" },
    { from: 1.5, to: 1.5, label: "中型小怪" },
    { from: 2, to: 2, label: "大型小怪" },
    { from: 3, to: 4, label: "低级精英" },
    { from: 8, to: 9, label: "高级精英" },
    { from: 9, to: 9, label: "低级boss" },
  ],
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
    const census = censusMonsterFlags(writeFixtureRepo(), CONFIG, { humanFlags: {} });

    expect(census.sourceFiles).toEqual(["测试.xml"]);
    expect(census.excludedSourceFiles).toEqual(["魔神.xml"]);
    expect(census.totals).toMatchObject({ templates: 5, complete: 1, partial: 2, missing: 2, fitted: 2, waived: 1, excluded: 1, skipped: 1 });

    const partial = census.rows.find((row) => row.status === "partial");
    expect(partial?.spritename).toBe("敌人-残缺怪");
    expect(partial?.missingFlags).toEqual(["速度系数"]);
    expect(partial?.stageSource).toBe("flag");
    expect(partial?.moveSpeed).toEqual({ min: 45, max: 65 });

    const unflagged = census.rows.find((row) => row.spritename === "敌人-主线怪");
    expect(unflagged?.stageSource).toBe("first-appearance");
    expect(unflagged?.stageNumber).toBe(1);
    expect(unflagged?.fit?.equations).toBe(6);
    expect(unflagged?.fit?.unresolved).toEqual(expect.arrayContaining(["atkSpeedFactor", "atkMultiplier", "segmentFactor", "superArmorFactor"]));

    expect(census.unreferencedSprites).toEqual(["敌人-未登场"]);
  });

  it("无需标识的模板不反查阶段、不拟合、不产出候选", () => {
    const census = censusMonsterFlags(writeFixtureRepo(), CONFIG, { humanFlags: {} });
    const waived = census.rows.find((row) => row.spritename === "敌人-未登场");

    expect(waived?.waived).toBe(true);
    expect(waived?.stageNumber).toBeUndefined();
    expect(waived?.fit).toBeUndefined();
    expect(waived?.skipReason).toBeUndefined();
    expect(toolFlagProposal(waived!)).toEqual({});
  });

  it("阶段 0 的行只留实测四项，不反推、不产候选", () => {
    const census = censusMonsterFlags(writeFixtureRepo(), CONFIG, { humanFlags: {} });
    const excluded = census.rows.find((row) => row.spritename === "敌人-下线怪")!;

    expect(excluded.excluded).toBe(true);
    expect(excluded.stageNumber).toBe(0);
    // 这只怪在废城街头有注册：阶段 0 必须压过首次出场反查，否则下次普查又自己长出阶段来
    expect(excluded.stageSource).toBe("flag");
    expect(excluded.spawnStages).toBeDefined();
    expect(excluded.fit).toBeUndefined();
    expect(excluded.skipReason).toBeUndefined();
    // 观测四项按盘上留档，反推四项不产出、机械项（阶段/速度系数）也不写
    expect(excluded.flags).toMatchObject({ 阶段: 0, 攻速系数: 4, 攻击倍率: 1.5, 段数系数: 6.2, 霸体系数: 3 });
    expect(toolFlagProposal(excluded)).toEqual({});
    expect(fitPinnedCoefficients(excluded)).toMatchObject({ atkSpeedFactor: 4, segmentFactor: 6.2 });
    expect(census.rows.filter((row) => row.excluded === true)).toHaveLength(1);
  });

  it("读不到面板的行只补机械项，不把默认值当反推结论", () => {
    const census = censusMonsterFlags(writeFixtureRepo(), CONFIG, { humanFlags: {}, only: ["敌人-残缺怪"] });
    const row = census.rows.find((entry) => entry.spritename === "敌人-残缺怪")!;

    expect(row.status).toBe("partial");
    // 残缺怪盘上只有 最小经验值 与移动速度，空手/HP/防御六项一项都没有
    expect(row.missingPanelFields.length).toBeGreaterThan(0);
    expect(row.fit).toBeUndefined();
    expect(row.skipReason).toBe("空手/HP/防御 六项面板一项都读不到，没有可拟合的方程");
    // 速度系数 仍按移动速度定义档补（45~65 均值 55 → 中档），档次/成长/血防一个都不编
    expect(toolFlagProposal(row)).toEqual({ 速度系数: 2 });
  });
});

describe("human authority and tool proposal", () => {
  it("观测系数只要盘上有值就钉住，人工没给的四个自由量重算", () => {
    const census = censusMonsterFlags(writeFixtureRepo(), CONFIG, { humanFlags: {}, only: ["敌人-残缺怪"] });
    const row = census.rows.find((entry) => entry.spritename === "敌人-残缺怪")!;

    expect(fitPinnedCoefficients(row)).toEqual({
      atkSpeedFactor: 3,
      atkMultiplier: 1,
      segmentFactor: 3,
      superArmorFactor: 1,
    });
  });

  it("人工给过的档次/成长/血防系数进钉住集合，阶段除外", () => {
    const census = censusMonsterFlags(writeFixtureRepo(), CONFIG, {
      humanFlags: { "敌人-残缺怪": { 档次系数: 3, 成长系数: 1, 阶段: 2 } },
      only: ["敌人-残缺怪"],
    });
    const row = census.rows.find((entry) => entry.spritename === "敌人-残缺怪")!;

    expect(fitPinnedCoefficients(row)).toMatchObject({ tierFactor: 3, growthFactor: 1, atkSpeedFactor: 3 });
    expect(fitPinnedCoefficients(row).stage).toBeUndefined();
  });

  it("配置点名的档次判定等同人工权威，候选里不再出现档次系数", () => {
    const census = censusMonsterFlags(writeFixtureRepo(), CONFIG, { humanFlags: {}, only: ["敌人-支线怪"] });
    const named = census.rows.find((entry) => entry.spritename === "敌人-支线怪")!;
    // humanTierFactors 点名 敌人-支线怪 = 3，档次退出搜索
    expect(named.humanFlags?.["档次系数"]).toBe(3);
    expect(named.fit?.freeCoefficients).toEqual(["growthFactor", "highAtkFactor", "highDefFactor"]);
    expect(named.fit?.coefficients.tierFactor).toBe(3);
    expect(Object.keys(toolFlagProposal(named))).not.toContain("档次系数");
  });

  it("freeTier 只把点名的档次放回搜索，git HEAD 已提交的档次照旧钉住", () => {
    const census = censusMonsterFlags(writeFixtureRepo(), CONFIG, { humanFlags: {}, only: ["敌人-支线怪"], freeTier: true });
    const row = census.rows.find((entry) => entry.spritename === "敌人-支线怪")!;

    expect(row.humanFlags?.["档次系数"]).toBeUndefined();
    expect(row.fit?.freeCoefficients).toEqual(["tierFactor", "growthFactor", "highAtkFactor", "highDefFactor"]);
    expect(Object.keys(toolFlagProposal(row))).toContain("档次系数");

    const committed = censusMonsterFlags(writeFixtureRepo(), CONFIG, {
      humanFlags: { "敌人-支线怪": { 档次系数: 5 } },
      only: ["敌人-支线怪"],
      freeTier: true,
    }).rows.find((entry) => entry.spritename === "敌人-支线怪")!;

    expect(committed.fit?.coefficients.tierFactor).toBe(5);
    expect(Object.keys(toolFlagProposal(committed))).not.toContain("档次系数");
  });

  it("estimatedTierTemplates 摘掉 HEAD 里预估的档次让本次重算，同一行其余已提交标识照旧钉住", () => {
    const given = { "敌人-残缺怪": { 阶段: 2, 档次系数: 3, 成长系数: 1 } };
    const rowFor = (config: MonsterCensusConfig) =>
      censusMonsterFlags(writeFixtureRepo(), config, { humanFlags: given, only: ["敌人-残缺怪"] })
        .rows.find((entry) => entry.spritename === "敌人-残缺怪")!;

    expect(fitPinnedCoefficients(rowFor(CONFIG)).tierFactor).toBe(3);

    const released = rowFor({ ...CONFIG, estimatedTierTemplates: ["敌人-残缺怪"] });
    expect(released.humanFlags).toEqual({ 阶段: 2, 成长系数: 1 });
    expect(fitPinnedCoefficients(released).tierFactor).toBeUndefined();
    expect(fitPinnedCoefficients(released).growthFactor).toBe(1);

    // 两份名单同时点到一行时按 humanTierFactors 钉住 —— 点名是「档次定死了」，比「那颗是预估」更强
    const named = rowFor({ ...CONFIG, humanTierFactors: { "敌人-残缺怪": 4 }, estimatedTierTemplates: ["敌人-残缺怪"] });
    expect(fitPinnedCoefficients(named).tierFactor).toBe(4);
  });

  it("整行标识都来自人工时不产出任何候选", () => {
    const census = censusMonsterFlags(writeFixtureRepo(), CONFIG, {
      only: ["敌人-支线怪"],
      humanFlags: {
        "敌人-支线怪": Object.fromEntries(CONFIG.flagFields.map((field) => [field, field === "阶段" ? 2 : 1])),
      },
    });
    const row = census.rows.find((entry) => entry.spritename === "敌人-支线怪")!;

    expect(row.fit?.freeCoefficients).toEqual([]);
    expect(toolFlagProposal(row)).toEqual({});
    // 同一批行就是查验表里要摘出去、只进人工表的那些
    expect(isFullyHumanFlagged(row, CONFIG)).toBe(true);
  });

  it("人工完整打标只看 git HEAD 那几项，速度系数 缺着也算齐", () => {
    const rowFor = (given: string[]) =>
      censusMonsterFlags(writeFixtureRepo(), CONFIG, {
        skipFit: true,
        only: ["敌人-支线怪"],
        humanFlags: {
          "敌人-支线怪": Object.fromEntries(
            CONFIG.flagFields.filter((field) => given.includes(field)).map((field) => [field, field === "阶段" ? 2 : 1]),
          ),
        },
      }).rows.find((entry) => entry.spritename === "敌人-支线怪")!;

    // 速度系数 是移动速度定义档补出来的，人工不填也仍算人工把这一行标完了
    expect(isFullyHumanFlagged(rowFor(CONFIG.flagFields.filter((field) => field !== "速度系数")), CONFIG)).toBe(true);
    // 只钉了阶段与档次：观测项与反推四项仍归工具识别，行照旧进统计面
    expect(isFullyHumanFlagged(rowFor(["阶段", "档次系数"]), CONFIG)).toBe(false);
    // 缺一项观测系数就不算完整打标，宁可让这行留在查验面上被人看见
    expect(isFullyHumanFlagged(rowFor(CONFIG.flagFields.filter((field) => field !== "攻击倍率")), CONFIG)).toBe(false);
  });

  it("候选=机械项加本次拟合的自由量，取整到词表档位", () => {
    const census = censusMonsterFlags(writeFixtureRepo(), CONFIG, { humanFlags: {}, only: ["敌人-主线怪"] });
    const row = census.rows.find((entry) => entry.spritename === "敌人-主线怪")!;
    const proposal = toolFlagProposal(row);

    expect(proposal["阶段"]).toBe(1);
    expect(proposal["速度系数"]).toBe(1);
    expect(Object.keys(proposal).sort()).toEqual(
      ["阶段", "速度系数", "档次系数", "成长系数", "高攻低血防系数", "高防低血系数"].sort(),
    );
    for (const value of Object.values(proposal)) {
      expect(Math.round(value * 10) / 10).toBe(value);
      expect(value).toBeGreaterThan(0);
    }
  });

  it("人工权威只认 git HEAD 那份原文，工作树里工具自写的值不算", () => {
    const flags = readFlagsFromSource(fixtureTemplateText(), CONFIG);

    expect(Object.keys(flags)).toEqual(["敌人-残缺怪"]);
    expect(flags["敌人-残缺怪"]).toMatchObject({ 阶段: 2, 档次系数: 3, 霸体系数: 1 });
    expect(flags["敌人-主线怪"]).toBeUndefined();
  });
});

describe("flag table labels", () => {
  it("阶段查主线进度，档次按门槛就近描述", () => {
    expect(stageProgressLabel(CONFIG, 1)).toBe("废城");
    expect(stageProgressLabel(CONFIG, 23)).toBe("盗贼");
    expect(stageProgressLabel(CONFIG, undefined)).toBe("");
    expect(stageProgressLabel(CONFIG, 99)).toBe("阶段 99 未列主线进度");

    expect(tierLabel(CONFIG, 1.5)).toBe("中型小怪");
    // 3.5 过了 低级精英 的门槛 3，离 高级精英 的门槛 8 还远 → 本档+
    expect(tierLabel(CONFIG, 3.5)).toBe("低级精英+");
    // 门槛只取各档下限：9 是 低级boss 的门槛，不再和 高级精英 8~9 并列
    expect(tierLabel(CONFIG, 9)).toBe("低级boss");
    expect(tierLabel(CONFIG, 8)).toBe("高级精英");
    // 2.5 正好压在 大型小怪 2 与 低级精英 3 的正中，四舍五入归上一档 → 上一档−
    expect(tierLabel(CONFIG, 2.5)).toBe("低级精英-");
    expect(tierLabel(CONFIG, 2.4)).toBe("大型小怪+");
    expect(tierLabel(CONFIG, 0.5)).toBe("小型小怪-");
    expect(tierLabel(CONFIG, 12)).toBe("低级boss+");
    expect(tierLabel(CONFIG, undefined)).toBe("");
  });
});

describe("flag table csv parsing", () => {
  it("容忍 BOM、CRLF、引号包裹与引号内换行", () => {
    expect(parseCsvRows(`\uFEFF模板,别名\r
敌人-未登场,"废城,流民",3\r
敌人-支线怪,"两\r
行",,\r
`)).toEqual([
      ["模板", "别名"],
      ["敌人-未登场", "废城,流民", "3"],
      ["敌人-支线怪", "两\r\n行", "", ""],
    ]);
  });

  it("空行与行尾空格不算数据", () => {
    expect(parseCsvRows("模板,别名\r\n敌人-残缺怪,\r\n\r\n")).toEqual([["模板", "别名"], ["敌人-残缺怪", ""]]);
  });
});

describe("flag write back", () => {
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
    expect(censusMonsterFlags(repo, CONFIG, { skipFit: true }).totals.complete).toBe(2);

    // 写回不能留下只有空白的行；新字段按兄弟行缩进对齐，即使标识块本身用制表符（天网.xml 就是这样）。
    expect(text).not.toMatch(/^[ \t]+$/m);
    expect(text).toContain("            <速度系数>2.5</速度系数>\n\t\t</标识>");
    expect(text).toMatch(/\n        <标识>\n            <阶段>1<\/阶段>[\s\S]*?\n        <\/标识>\n    <\/敌人-主线怪>/);
  });

  it("改写已有字段只换文本，重复写同一批值不再改动文件", () => {
    const repo = writeFixtureRepo();
    const target = path.join(repo, "data", "enemy_properties", "测试.xml");
    const update = [{ sourceFile: "测试.xml", spritename: "敌人-支线怪", flags: { 档次系数: 3, 成长系数: 1.25 } }];

    expect(applyMonsterFlagUpdates(repo, update, CONFIG).length).toBe(1);
    expect(fs.readFileSync(target, "utf8")).toContain("<成长系数>1.25</成长系数>");
    expect(applyMonsterFlagUpdates(repo, update, CONFIG)).toEqual([]);
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

function flagsElement(): string {
  return `\t\t<标识>\n${NEAR_COMPLETE_FLAGS.map(([field, value]) => `            <${field}>${value}</${field}>`).join("\n")}\n\t\t</标识>`;
}

function fixtureTemplateText(): string {
  return `<?xml version='1.0' encoding='UTF-8'?>
<root>
    <敌人-主线怪>
${PANEL.join("\n")}
    </敌人-主线怪>
    <敌人-残缺怪>
        <最小经验值>200</最小经验值>
        <速度_min>45</速度_min>
        <速度_max>65</速度_max>
${flagsElement()}
    </敌人-残缺怪>
</root>
`;
}

function writeFixtureRepo(): string {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-monster-"));

  write(repo, "data/stages/基地门口/__list__.xml", `<?xml version='1.0' encoding='UTF-8'?>
<root>
    <StageInfo><Name>废城街头</Name><Type>主线</Type><UnlockCondition>1</UnlockCondition></StageInfo>
    <StageInfo><Name>支线矿洞</Name><Type>支线</Type><UnlockCondition>2</UnlockCondition></StageInfo>
    <StageInfo><Name>无任务关卡</Name><Type>副本</Type><UnlockCondition>9</UnlockCondition></StageInfo>
</root>
`);
  write(repo, "data/stages/基地门口/废城街头.xml", stageXml([1, 6]));
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
    { id: 6, spritename: "敌人-下线怪" },
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
${flagsElement()}
    </敌人-残缺怪>
    <敌人-支线怪>
        <hp_min>500</hp_min>
        <标识>
${NEAR_COMPLETE_FLAGS.map(([field, value]) => `            <${field}>${value}</${field}>`).join("\n")}
            <速度系数>2</速度系数>
        </标识>
    </敌人-支线怪>
    <敌人-未登场/>
    <!-- 阶段 0 = 制作组把这行整只摘出面板体系：实测四项留档，反推与查验表都不算它 -->
    <敌人-下线怪>
        <hp_min>800</hp_min>
        <空手攻击力_min>30</空手攻击力_min>
        <标识>
            <阶段>0</阶段>
            <攻速系数>4</攻速系数>
            <攻击倍率>1.5</攻击倍率>
            <段数系数>6.2</段数系数>
            <霸体系数>3</霸体系数>
        </标识>
    </敌人-下线怪>
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
