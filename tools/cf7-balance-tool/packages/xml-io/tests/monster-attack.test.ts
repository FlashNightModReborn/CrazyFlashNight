import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import {
  armorAccount,
  attackCountOf,
  DEFAULT_ARMOR_RULES,
  loadAssetSources,
  loadUnresolvedAssetSources,
  measureMonsterAttack,
  proposeAttackFlags,
  summarizeAttack,
} from "../src/monster-attack.js";
import type { ArmorRules, AttackSummary, MeleeBulletRules, MonsterArmorMeasure, PierceSegmentRules } from "../src/monster-attack.js";

/** 制作组口径的攻速档位，与 data/monster-census.json 一致：上界不含。 */
const BANDS = [
  { maxWindupFrames: 9, factor: 5, label: "极快" },
  { maxWindupFrames: 16, factor: 4, label: "快" },
  { maxWindupFrames: 26, factor: 3, label: "中等" },
  { maxWindupFrames: 41, factor: 2, label: "慢" },
  { maxWindupFrames: 999, factor: 1, label: "极慢" },
];

/** 段数的一次攻击换算窗口（帧）与后摇分量倍率：这里取什么是测试参数，不跟 data/monster-census.json 的现网口径值绑定。 */
const WINDOW = 15;
const TAIL = 0.2;

/** 近战颗数口径的取值：与现网配置同参数，但测试里显式传，不让配置改动牵动断言。 */
const MELEE: MeleeBulletRules = {
  kindWords: ["近战"],
  linkageWords: ["联弹"],
  linkageHorizontalWords: ["横向"],
  linkageVerticalWords: ["纵向"],
  linkageFactor: 0.6,
  clusterFrames: 2,
  clusterCap: 3,
  hitboxWidth: 80,
  hitboxHeight: 170,
  mode: "hitbox",
};

/** 穿刺段数口径的取值：与现网配置一致（穿刺 2 倍、次级穿刺 1.5 倍）。 */
const PIERCE: PierceSegmentRules = {
  pierceWords: ["穿刺"],
  secondaryPierceWords: ["次级穿刺"],
  pierceFactor: 2,
  secondaryPierceFactor: 1.5,
};

describe("monster attack measurement", () => {
  it("按子弹实例计命中，段数取霰弹值加总，前摇从标签起点算", () => {
    const measure = measureFixture();
    const skill = measure.skills.find((entry) => entry.label === "打一下");

    expect(measure.scope).toBe("placed");
    expect(measure.attackDesire).toEqual([3]);
    expect(measure.gates).toEqual(["*2"]);
    expect(skill).toMatchObject({
      frames: 30,
      attacks: 1,
      hits: 2,
      windupFrames: 5,
      firstBulletOffset: 5,
      lastBulletOffset: 9,
      bulletSpanFrames: 4,
      tailFrames: 16,
      tailBasis: "动画完毕",
      usable: true,
    });
    // 一颗 2 段、一颗没写 霰弹值 按 1 段算；倍率 (2 + 1) / 2
    expect(skill?.segments).toBeCloseTo(3, 6);
    expect(skill?.multiplier).toBeCloseTo(1.5, 6);
  });

  it("同一颗子弹里 霰弹值 多次赋值取均值，`+=` 才算追加，`最小霰弹值` 不算段数", () => {
    const byLabel = new Map(measureFixture().skills.map((skill) => [skill.label, skill]));

    // 脚本写的是 最小霰弹值=9、霰弹值=2、霰弹值=4、霰弹值+=1 → (2+4)/2 + 1 = 4，加总写法会给出 16
    expect(byLabel.get("打两下")?.segments).toBeCloseTo(4, 6);
  });

  it("子弹元件自带的脚本算命中，未被跳转的废弃标签与未摆放的特效都不进平均值", () => {
    const measure = measureFixture();
    const byLabel = new Map(measure.skills.map((skill) => [skill.label, skill]));

    expect(byLabel.get("打两下")).toMatchObject({ hits: 1, segments: 4, windupFrames: 5, usable: true });
    // 这一招从 30 帧放到 49 帧，末子弹在偏移 5：找不到 动画完毕 就按段尾折，后摇 14 帧
    expect(byLabel.get("打两下")).toMatchObject({ tailFrames: 14, tailBasis: "段尾" });
    expect(byLabel.get("打两下")?.concerns.join("；")).toContain("没有 动画完毕 调用");
    expect(byLabel.get("废弃连击")?.usable).toBe(false);
    expect(byLabel.get("废弃连击")?.concerns.join("；")).toContain("没被跳转引用");
    // 特效元件也写了 子弹威力，但容器没摆它，连候选都不算
    expect(measure.skills.some((skill) => skill.file.includes("刀光特效"))).toBe(false);

    const summary = summarizeAttack(measure);
    expect(summary.skills).toBe(2);
    expect(summary.candidates).toBe(3);
    expect(summary.segments).toBeCloseTo(3.5, 6);
    expect(summary.windupMean).toBeCloseTo(5, 6);
    expect(summary.tailMean).toBeCloseTo(15, 6);
    expect(summary.overCallSkills).toBe(1);
  });

  it("容器摆的动画没人按名调度时，标签顺播全部算有效招式", () => {
    const repo = writeComboRepo();
    const measure = measureMonsterAttack(
      { spritename: "敌人-连招怪", panelAtkMin: 100, panelAtkMax: 100, segmentWindowFrames: WINDOW },
      loadAssetSources(repo),
      repo,
    );
    const byLabel = new Map(measure.skills.map((skill) => [skill.label, skill]));

    // 一个合集靠 gotoAndPlay(招式名) 挑招、另一个连脚本都没有、还有一个只被 goto 到 受创 状态
    expect(measure.scope).toBe("placed");
    for (const label of ["1连招", "2连招", "3连招", "顺播-1连招", "顺播-2连招", "顺播-3连招", "大风雪"]) {
      expect(byLabel.get(label)?.usable).toBe(true);
      expect(byLabel.get(label)?.concerns.join("；")).toContain("按摆放放行");
    }
    // 受创 是被按名跳到的状态标签，不是招式
    expect(byLabel.get("受创")).toBeUndefined();
    // 同目录里兄弟怪的合集没被这只怪摆出去，仍然不算它的招式
    expect(measure.skills.some((skill) => skill.file.includes("兄弟合集"))).toBe(false);

    const summary = summarizeAttack(measure);
    expect(summary.skills).toBe(7);
    expect(summary.candidates).toBe(7);
    expect(summary.segments).toBeCloseTo(2, 6);
  });

  it("出手动画由中间层元件再摆时沿摆放链往里找一层，这一层不认顺播", () => {
    const measure = measureIn(writeOrphanComboRepo(), "敌人-孤儿怪");

    // 容器只摆了 出招壳，招式合集在里面一层 —— 这时不认"顺播"，免得共享元件串到兄弟怪身上
    expect(measure.scope).toBe("widened");
    expect(measure.skills.some((skill) => skill.depth === 2)).toBe(true);
    expect(measure.skills.every((skill) => !skill.usable)).toBe(true);
    expect(measure.skills.at(0)?.concerns.join("；")).toContain("没被跳转引用");
    expect(summarizeAttack(measure).skills).toBe(0);
  });

  it("容器没沿摆放链摆出元件时不给候选，也不捞同包别人的合集", () => {
    const measure = measureIn(writeOrphanComboRepo(), "敌人-空手怪");

    expect(measure.skills).toEqual([]);
    expect(measure.note).toContain("容器没沿摆放链摆出任何元件");
    expect(summarizeAttack(measure).skills).toBe(0);
  });

  it("同库里兄弟怪的动画不在摆放树里，就不算这只怪的招式", () => {
    const repo = writeSharedPackageRepo();
    const borrowed = measureIn(repo, "敌人-借招怪");
    const sibling = measureIn(repo, "敌人-兄弟");

    // 元件都住在包根，按"容器所在目录"划作用域时两边会互相串
    expect(borrowed.skills.map((skill) => skill.file)).toEqual(["自家合集.xml", "自家合集.xml", "自家合集.xml"]);
    expect(borrowed.skills.every((skill) => skill.usable)).toBe(true);
    expect(sibling.skills.map((skill) => skill.label)).toEqual(["兄弟弹幕"]);
    expect(sibling.skills.at(0)?.usable).toBe(true);
  });

  it("挂在受创/死亡一类状态段上的子弹不算招式", () => {
    const measure = measureIn(writeStateGateRepo(), "敌人-状态怪");
    const byLabel = new Map(measure.skills.map((skill) => [skill.label, skill]));

    expect(byLabel.get("出手")).toMatchObject({ usable: true, state: "近战", depth: 1 });
    // 挨打与死亡动画里确实摆了带参数的子弹，但它们挂在 被击/血腥死 上
    expect(byLabel.get("濒死反击")).toMatchObject({ usable: false, state: "血腥死" });
    expect(byLabel.get("濒死反击")?.concerns.join("；")).toContain("不在攻击样词表里");
    expect(byLabel.get("挨打反弹")).toMatchObject({ usable: false, state: "被击" });

    const summary = summarizeAttack(measure);
    expect(summary.skills).toBe(1);
    expect(summary.candidates).toBe(3);
  });

  it("同一份动画被攻击样状态与非攻击状态共用时，仍按攻击样放行", () => {
    const measure = measureIn(writeStateGateRepo(), "敌人-两用作");
    const skill = measure.skills.find((entry) => entry.label === "共用弹幕");

    expect(skill).toMatchObject({ usable: true });
    expect(skill?.state).toContain("近战");
  });

  it("标签没盖住的时间轴段落按顺播各算一招，够短的首尾段不算", () => {
    const measure = measureIn(writeGapRepo(), "敌人-空档怪");
    const labels = measure.skills.map((skill) => skill.label);

    // 头段 0~4 帧没人打标签、子弹摆在这里；尾段只剩 3 帧，太短不算独立招式
    expect(labels.some((label) => label.includes("未标注段 0~4"))).toBe(true);
    expect(labels).toContain("a0");
    expect(labels.some((label) => label.includes("未标注段 28"))).toBe(false);
    expect(measure.skills.filter((skill) => skill.usable).length).toBe(2);
  });

  it("容器住在库根时也能拿到子目录里的出手动画", () => {
    const measure = measureIn(writeRootContainerRepo(), "敌人-库根怪");

    // 老口径按"容器所在目录"划作用域，库根容器会把 素材/ 子树整个丢掉
    expect(measure.scope).toBe("placed");
    expect(measure.skills.map((skill) => skill.file)).toEqual(["素材/Symbol 154.xml", "素材/Symbol 154.xml", "素材/Symbol 154.xml"]);
    expect(measure.skills.every((skill) => skill.usable)).toBe(true);
    // 包根躺着的兄弟怪动画没被摆出去，连候选都不算
    expect(measure.skills.some((skill) => skill.file.includes("兄弟怪的动画"))).toBe(false);
  });

  it("攻速以前摇为主、后摇按分量折进去，倍率与段数按 0.5 网格归档", () => {
    const summary: AttackSummary = {
      segments: 6.67,
      multiplier: 1.24,
      windupMean: 15,
      tailMean: 10,
      overCallSkills: 2,
      tempoMedian: 33,
      skills: 2,
      candidates: 2,
      fixedValueSkills: 0,
    };
    const proposal = proposeAttackFlags(summary, BANDS, TAIL);

    // 15 + 10×0.2 = 17 帧，对放宽 1.2 倍的门槛（快档 16×1.2=19.2）仍取 快
    expect(proposal.flags).toEqual({ 攻速系数: 4, 攻击倍率: 1.2, 段数系数: 6.7 });
    expect(proposal.notes[0]).toContain("前摇 15 帧 + 后摇 10 帧×0.2 = 17 帧");
    expect(proposal.notes[0]).toContain("→ 攻速 4（快）");
  });

  it("后摇倍率设 0 时不看后摇，档位门槛就是制作组给的原值：8 极快、9 快、16 中等、26 慢、41 极慢", () => {
    const factor = (windupMean: number) =>
      proposeAttackFlags(
        { windupMean, skills: 1, candidates: 1, overCallSkills: 1, fixedValueSkills: 0 },
        BANDS,
        0,
      ).flags["攻速系数"];

    expect([factor(4), factor(8), factor(9), factor(15), factor(16), factor(25), factor(26), factor(40), factor(41)]).toEqual([5, 5, 4, 4, 3, 3, 2, 2, 1]);
  });

  it("后摇很长的怪降一档，但整档同步放宽 1.2 倍所以纯前摇贴边的不算慢", () => {
    const factor = (windupMean: number, tailMean: number) =>
      proposeAttackFlags(
        { windupMean, tailMean, skills: 1, candidates: 1, overCallSkills: 1, fixedValueSkills: 0 },
        BANDS,
        TAIL,
      ).flags["攻速系数"];

    expect(factor(9, 0)).toBe(5); // 9 < 9×1.2
    expect(factor(9, 30)).toBe(4); // 9+6=15 < 16×1.2
    expect(factor(11, 60)).toBe(3); // 11+12=23 < 26×1.2
  });

  it("有招式没找到 动画完毕 时在取档说明里写明后摇退回段尾", () => {
    const proposal = proposeAttackFlags(
      { windupMean: 5, tailMean: 12, skills: 3, candidates: 3, overCallSkills: 1, fixedValueSkills: 0 },
      BANDS,
      TAIL,
    );

    expect(proposal.notes.join("；")).toContain("2 招没找到 动画完毕 调用，后摇退回段尾折算");
  });

  it("攻击次数量子弹跨度折窗口：不满窗口算 1 次，满了取小数次数、不补成整数", () => {
    expect(attackCountOf(0, WINDOW)).toBe(1);
    expect(attackCountOf(14, WINDOW)).toBe(1);
    expect(attackCountOf(15, WINDOW)).toBeCloseTo(1, 6);
    expect(attackCountOf(24, WINDOW)).toBeCloseTo(1.6, 6);
    expect(attackCountOf(46, WINDOW)).toBeCloseTo(46 / 15, 6);
  });

  it("倍率或段数超出工作簿 D13 建议区间时报警，但不改观测值", () => {
    const summary: AttackSummary = { segments: 12.4, multiplier: 4.2, windupMean: 48, tailMean: 10, overCallSkills: 1, skills: 1, candidates: 1, fixedValueSkills: 0 };
    const proposal = proposeAttackFlags(summary, BANDS, TAIL);

    expect(proposal.flags).toEqual({ 攻速系数: 1, 攻击倍率: 4.2, 段数系数: 12.4 });
    expect(proposal.notes.join("；")).toContain("超出 D13 常用上限 3");
    expect(proposal.notes.join("；")).toContain("超出 D13 建议上限 10");
  });

  it("没有可用招式时不给候选值", () => {
    const empty: AttackSummary = { skills: 0, candidates: 3, overCallSkills: 0, fixedValueSkills: 0 };
    expect(proposeAttackFlags(empty, BANDS, TAIL)).toEqual({ flags: {}, notes: ["没有可用招式，不给候选值"] });
  });
});

describe("asset source map", () => {
  it("按 id 记下 swf 与元件路径，供容器定位", () => {
    const assets = loadAssetSources(writeFixtureRepo());

    expect(assets.get("敌人-测试怪")).toEqual([{ swf: "arts/测试包.swf", symbol: "测试/代码层/敌人-测试怪" }]);
  });

  it("<conflict> 里的多份源不替人选：注册表读不到 <asset> 就一条候选都不给", () => {
    const repo = writeFixtureRepo(`<conflict id="敌人-测试怪">
    <source swf="arts/测试包.swf" symbolName="测试/代码层/敌人-测试怪" />
    <source swf="arts/另一个包.swf" symbolName="敌人-测试怪" />
  </conflict>`);

    expect(loadAssetSources(repo).has("敌人-测试怪")).toBe(false);
    expect(loadUnresolvedAssetSources(repo).get("敌人-测试怪")).toEqual([
      { swf: "arts/测试包.swf", symbol: "测试/代码层/敌人-测试怪", kind: "conflict", orphan: false },
      { swf: "arts/另一个包.swf", symbol: "敌人-测试怪", kind: "conflict", orphan: false },
    ]);
  });

  it("attackSourceOverrides 顶掉注册表：定源之后同一只怪照常量出招式", () => {
    const repo = writeFixtureRepo(`<conflict id="敌人-测试怪">
    <source swf="arts/测试包.swf" symbolName="测试/代码层/敌人-测试怪" />
    <source swf="arts/另一个包.swf" symbolName="敌人-测试怪" orphan="true" />
  </conflict>`);
    const input = { spritename: "敌人-测试怪", panelAtkMin: 100, panelAtkMax: 100, segmentWindowFrames: WINDOW };

    const pinned = measureMonsterAttack(
      { ...input, unresolvedSources: loadUnresolvedAssetSources(repo).get("敌人-测试怪") },
      loadAssetSources(repo, { "敌人-测试怪": [{ swf: "arts/测试包.swf", symbolName: "测试/代码层/敌人-测试怪" }] }),
      repo,
    );
    expect(pinned.kind).toBe("xfl");
    expect(pinned.note ?? "").not.toContain("定源");
    expect(summarizeAttack(pinned).skills).toBe(2);

    // 没定源时说明要写"有源但没定源"，不能再说成注册表里查不到
    const unpinned = measureMonsterAttack(
      { ...input, unresolvedSources: loadUnresolvedAssetSources(repo).get("敌人-测试怪") },
      loadAssetSources(repo),
      repo,
    );
    expect(summarizeAttack(unpinned).skills).toBe(0);
    expect(unpinned.note).toContain("<conflict>");
    expect(unpinned.note).toContain("都有源");
    expect(unpinned.note).toContain("arts/另一个包.swf（敌人-测试怪），孤儿");
    expect(unpinned.note).not.toContain("查不到");
  });

  it("注册表里完全没有记录时说明写「没有任何记录」", () => {
    const repo = writeFixtureRepo("");
    const measure = measureMonsterAttack(
      { spritename: "敌人-测试怪", panelAtkMin: 100, panelAtkMax: 100, segmentWindowFrames: WINDOW },
      loadAssetSources(repo),
      repo,
    );

    expect(measure.note).toBe("asset_source_map 里没有 敌人-测试怪 的任何记录");
  });
});

describe("近战子弹有效颗数", () => {
  it("无区域近战子弹按拨折叠，几何法只数玩家命中框框得住的颗数", () => {
    const skill = meleeSkill("散拨");

    // 一拨 4 颗横向铺到 400 单位（80 宽的框最多框住 2 颗），另一拨 2 颗纵向隔 200（超过 170 高，只框住 1 颗）
    expect(skill).toMatchObject({ hits: 6, attacks: 1, usable: true });
    expect(skill.melee).toMatchObject({
      meleeHits: 6,
      areaHits: 0,
      spreadHits: 6,
      clusters: 2,
      countedCap: 5,
      countedHitbox: 3,
      unpositionedClusters: 0,
      segmentsUnfiltered: 6,
      segmentsCap: 5,
      segmentsHitbox: 3,
      mode: "hitbox",
    });
    expect(skill.segments).toBeCloseTo(3, 6);
    expect(skill.concerns.join("；")).toContain("6 颗无区域近战子弹分 2 摆，按玩家命中框 80×170 最多框住的颗数只算 3 颗");
  });

  it("区域判定的联弹只折 霰弹值 分量，不参与颗数过滤；纵向即使传了 area 也不折", () => {
    const skill = meleeSkill("区域联弹");

    // 近战联弹 5 段折成 3，纵向联弹 5 段保持全值；两颗都传了 area，颗数一层一颗不丢
    expect(skill.melee).toMatchObject({
      meleeHits: 2,
      areaHits: 2,
      linkageHorizontalHits: 0,
      linkageAreaHits: 1,
      linkageVerticalHits: 1,
      spreadHits: 0,
      clusters: 0,
      countedCap: 2,
      countedHitbox: 2,
      segmentsUnfiltered: 10,
      segmentsCap: 8,
    });
    expect(skill.segments).toBeCloseTo(8, 6);
    const concerns = skill.concerns.join("；");
    expect(concerns).toContain("0 颗横向联弹、1 颗传了 area 的联弹，霰弹值 按 0.6 折分量");
    expect(concerns).toContain("1 颗纵向联弹，霰弹值 不折分量");
  });

  it("横向联弹不传 区域定位area 也折分量，纵向联弹传了 area 也不折", () => {
    const skill = meleeSkill("方向联弹");

    // 一颗 横向联弹-加强普通子弹 折成 6 段，一颗 纵向联弹-普通子弹 仍是 5 段；两颗都摆在 近战子弹 元件上，颗数一层不丢
    expect(skill.melee).toMatchObject({
      meleeHits: 2,
      byNameHits: 2,
      areaHits: 0,
      linkageHorizontalHits: 1,
      linkageAreaHits: 0,
      linkageVerticalHits: 1,
      spreadHits: 2,
      clusters: 1,
      countedCap: 2,
      countedHitbox: 2,
      segmentsUnfiltered: 15,
      segmentsCap: 11,
      segmentsHitbox: 11,
    });
    expect(skill.segments).toBeCloseTo(11, 6);
    const concerns = skill.concerns.join("；");
    expect(concerns).toContain("1 颗横向联弹、0 颗传了 area 的联弹，霰弹值 按 0.6 折分量");
    expect(concerns).toContain("1 颗纵向联弹，霰弹值 不折分量");

    // 机枪联弹 靠 横向／纵向 前缀认，不必把整条名字写进词表（制作组 2026-10-06 定的方向口径）
    const gun = meleeSkill("机枪联弹");
    expect(gun.melee).toMatchObject({
      meleeHits: 0,
      linkageHorizontalHits: 1,
      linkageVerticalHits: 1,
      countedHitbox: 2,
      segmentsUnfiltered: 15,
      segmentsHitbox: 11,
    });
    expect(gun.segments).toBeCloseTo(11, 6);
  });

  it("非近战子弹不做颗数判定，同帧摆一把也照全算", () => {
    const skill = meleeSkill("非近战");

    // 线状判定不会同屏摆无效子弹，近战词表没命中就整条口径都不进
    expect(skill.hits).toBe(3);
    expect(skill.melee).toBeUndefined();
    expect(skill.segments).toBeCloseTo(12, 6);
  });

  it("非近战联弹不做颗数判定：联弹不写进 kindWords 就射出多少算多少，但 霰弹值 照折分量", () => {
    const skill = meleeSkill("非近战联弹");

    // 横向联弹-普通子弹 铺 6 颗在屏幕各处：既不是近战类 → 命中框一层不进，颗颗计入；横向 → 每颗 1 段折成 0.6
    expect(skill.melee).toMatchObject({
      meleeHits: 0,
      linkageHorizontalHits: 6,
      countedCap: 6,
      countedHitbox: 6,
      segmentsUnfiltered: 6,
      segmentsHitbox: 3.6,
    });
    expect(skill.segments).toBeCloseTo(3.6, 6);

    // 旧口径把 联弹 也当近战类，同一招会被命中框折成 3 颗（再打 0.6 折）—— 这条断言钉住 2026-10-06 的收紧
    const legacy = meleeSkill("非近战联弹", { ...MELEE, kindWords: ["近战", "联弹"] });
    expect(legacy.melee).toMatchObject({ meleeHits: 6, spreadHits: 6, clusters: 1, countedHitbox: 3 });
    expect(legacy.segments).toBeCloseTo(1.8, 6);
  });

  it("没声明 子弹种类 时按子弹元件名认近战，读不到坐标的拨退回简单法", () => {
    const skill = meleeSkill("认名");

    expect(skill.melee).toMatchObject({
      meleeHits: 4,
      byNameHits: 4,
      spreadHits: 4,
      clusters: 1,
      countedCap: 3,
      countedHitbox: 3,
      unpositionedClusters: 1,
    });
    expect(skill.segments).toBeCloseTo(3, 6);
    const concerns = skill.concerns.join("；");
    expect(concerns).toContain("4 颗没声明 子弹种类，按子弹元件名认成近战类");
    expect(concerns).toContain("1 拨读不到子弹坐标，几何法退回每拨最多 3 颗");
  });

  it("mode 设 off 就回到摆了颗数就算，命中框尺寸改动直接体现在颗数上", () => {
    const off = meleeSkill("散拨", { ...MELEE, mode: "off" });

    // 取哪种算法由配置 mode 定，但三种取法的对照值一直留在 melee 里给人工比
    expect(off.melee).toMatchObject({ countedCap: 5, countedHitbox: 3, mode: "off" });
    expect(off.melee?.segmentsUnfiltered).toBeCloseTo(6, 6);
    expect(off.segments).toBeCloseTo(6, 6);

    const wide = meleeSkill("散拨", { ...MELEE, hitboxWidth: 400, hitboxHeight: 400 });
    expect(wide.melee).toMatchObject({ countedHitbox: 6 });
    expect(wide.segments).toBeCloseTo(6, 6);
  });

  it("行均值把三种取法都摊开，段数系数按当前 mode 取", () => {
    const summary = summarizeAttack(measureMelee());

    // 散拨 6→3、区域联弹 10→8（纵向那颗不折了）、非近战 12 不动、认名 4→3、方向联弹 15→11、非近战联弹 6→3.6、机枪联弹 15→11
    expect(summary.skills).toBe(7);
    expect(summary.segmentsUnfiltered).toBeCloseTo(68 / 7, 6);
    expect(summary.segmentsCap).toBeCloseTo(53.6 / 7, 6);
    expect(summary.segmentsHitbox).toBeCloseTo(51.6 / 7, 6);
    expect(summary.segments).toBeCloseTo(51.6 / 7, 6);
  });
});

describe("穿刺子弹的段数放大", () => {
  it("命中 穿刺 的那颗子弹段数乘 2，与是不是近战类无关", () => {
    const skill = pierceSkill("穿刺");

    // 两颗 穿刺子弹 各 3 段：非近战不做颗数判定，但穿刺这一层照样乘
    expect(skill.hits).toBe(2);
    expect(skill.melee).toBeUndefined();
    expect(skill.segments).toBeCloseTo(12, 6);
    expect(skill.pierce).toEqual({
      pierceHits: 2,
      secondaryHits: 0,
      pierceKinds: ["穿刺子弹"],
      secondaryKinds: [],
      byNameHits: 0,
    });
    expect(skill.concerns.join("；")).toContain("2 颗穿刺子弹（穿刺子弹）段数按 2 倍计");
  });

  it("次级穿刺按 1.5 倍，不被 穿刺 词收走", () => {
    const skill = pierceSkill("次级穿刺");

    // 「次级穿刺子弹」里也含「穿刺」两字，先认次级才拿到 4×1.5=6 而不是 4×2=8
    expect(skill.segments).toBeCloseTo(6, 6);
    expect(skill.pierce).toMatchObject({ pierceHits: 0, secondaryHits: 1, secondaryKinds: ["次级穿刺子弹"] });
    expect(skill.concerns.join("；")).toContain("1 颗次级穿刺子弹（次级穿刺子弹）段数按 1.5 倍计");
  });

  it("同一拨里两档并存时各按各的倍数", () => {
    const skill = pierceSkill("两档同拨");

    // 穿刺 2×2 + 次级穿刺 2×1.5
    expect(skill.segments).toBeCloseTo(7, 6);
    expect(skill.pierce).toMatchObject({ pierceHits: 1, secondaryHits: 1, byNameHits: 0 });
  });

  it("近战类摆在穿刺子弹元件上：先按命中框折颗数，再乘穿刺倍数", () => {
    const skill = pierceSkill("近战穿刺");

    // 4 颗各 1 段、横铺到 400：命中框留 2 颗、简单法留 3 颗，再各乘 2
    expect(skill.melee).toMatchObject({
      meleeHits: 4,
      byNameHits: 0,
      countedCap: 3,
      countedHitbox: 2,
      segmentsUnfiltered: 4,
      segmentsCap: 6,
      segmentsHitbox: 4,
    });
    expect(skill.segments).toBeCloseTo(4, 6);
    expect(skill.pierce).toMatchObject({ pierceHits: 4, pierceKinds: ["子弹/穿刺子弹"], byNameHits: 4 });
    const concerns = skill.concerns.join("；");
    expect(concerns).toContain("4 颗无区域近战子弹分 1 摆，按玩家命中框 80×170 最多框住的颗数只算 2 颗");
    expect(concerns).toContain("4 颗穿刺子弹（子弹/穿刺子弹）段数按 2 倍计");
    expect(concerns).toContain("4 颗没声明 子弹种类，按子弹元件名认成穿刺");
  });

  it("联弹折分量与穿刺倍数叠在一颗上，纵向联弹不折只乘倍数，非近战联弹的账也留在复核块里", () => {
    const skill = pierceSkill("联弹穿刺");

    // 横向联弹-穿刺子弹 5 段：先折 0.6 再乘 2 → 6；纵向联弹-穿刺子弹 5 段：不折、乘 2 → 10。颗数一层都不进（不是近战类）
    expect(skill.melee).toMatchObject({
      meleeHits: 0,
      linkageHorizontalHits: 1,
      linkageAreaHits: 0,
      linkageVerticalHits: 1,
      countedHitbox: 2,
      segmentsUnfiltered: 10,
      segmentsHitbox: 16,
    });
    expect(skill.segments).toBeCloseTo(16, 6);
    expect(skill.pierce).toMatchObject({
      pierceHits: 2,
      pierceKinds: ["横向联弹-穿刺子弹", "纵向联弹-穿刺子弹"],
      byNameHits: 0,
    });
    const concerns = skill.concerns.join("；");
    expect(concerns).toContain("1 颗横向联弹、0 颗传了 area 的联弹，霰弹值 按 0.6 折分量");
    expect(concerns).toContain("1 颗纵向联弹，霰弹值 不折分量");
    expect(concerns).toContain("2 颗穿刺子弹（横向联弹-穿刺子弹、纵向联弹-穿刺子弹）段数按 2 倍计");
  });

  it("倍数与词表都由配置给：改 pierceFactor 或删词就回到不放大", () => {
    expect(pierceSkill("穿刺", { ...PIERCE, pierceFactor: 1 }).segments).toBeCloseTo(6, 6);
    expect(pierceSkill("穿刺", { ...PIERCE, pierceWords: [] }).pierce).toBeUndefined();
    // 词表里去掉 次级穿刺 就会被 穿刺 收走 —— 顺序敏感，所以两档词必须同时摆着
    expect(pierceSkill("次级穿刺", { ...PIERCE, secondaryPierceWords: [] }).segments).toBeCloseTo(8, 6);
  });
});

describe("函数式发弹的段数与倍率", () => {
  it("enterFrame 锚点按在台帧数逐帧触发，性能倍率 闸门每 2 次触发才发 1 弹", () => {
    const skill = shotSkill("逐帧连发");

    expect(skill.hits).toBe(5);
    expect(skill.functionShots).toMatchObject([
      { name: "射击", declaredIn: "发弹/动画/发弹合集.xml", pelletsPerShot: 3, throttle: 2, throttleBasis: "数值声明", calls: 10, emissions: 5, pelletSum: 15 },
    ]);
    // 5 颗 × 霰弹值 3；跨度只有 8 帧（2→10）不满 15 帧窗口 → 攻击次数 1
    expect(skill.segments).toBeCloseTo(15, 6);
    // 0.5 * 性能倍率 * 空手攻击力：性能倍率 从同文件数值声明读成 2，两者相乘正好 1 倍
    expect(skill.multiplier).toBeCloseTo(1, 6);
    expect(skill.concerns.join("；")).toContain("由函数发弹：有效帧内真实触发 10 次，闸门后折出 5 颗");
  });

  it("只声明发弹函数的那一帧不发弹：前摇从真实调用帧算起", () => {
    const skill = shotSkill("逐帧连发");

    // 函数声明写在第 0 帧，锚点从第 2 帧才在台上：把声明体当子弹就会把前摇量成 0
    expect(skill.firstBulletOffset).toBe(2);
    expect(skill.windupFrames).toBe(2);
    expect(skill.expressions.some((expr) => expr.includes("0.5 * 性能倍率"))).toBe(true);
  });

  it("帧脚本里的调用一个关键帧进一次，前置系数的威力写法也认得出来", () => {
    const skill = shotSkill("帧脚本点射");

    expect(skill.functionShots).toMatchObject([{ name: "毒刺射击", pelletsPerShot: 1, throttle: 1, throttleBasis: "无", calls: 4, emissions: 4 }]);
    expect(skill.hits).toBe(4);
    // 4 次调用落在第 5、10、15、20 帧：跨度正好 15 帧 → 攻击次数 1
    expect(skill).toMatchObject({ firstBulletOffset: 5, lastBulletOffset: 20, bulletSpanFrames: 15, attacks: 1 });
    expect(skill.segments).toBeCloseTo(4, 6);
    expect(skill.multiplier).toBeCloseTo(4, 6);
    expect(skill.expressions.some((expr) => expr.includes("乘积式系数 ×4"))).toBe(true);
  });

  it("闸门变量读不出数值时按每次调用都发一颗，并把这点写进疑点", () => {
    const skill = shotSkill("闸门读不出");

    expect(skill.functionShots).toMatchObject([
      { name: "慢射", throttle: 1, throttleBasis: "读不出", calls: 6, emissions: 6, pelletSum: 6 },
    ]);
    expect(skill.segments).toBeCloseTo(6, 6);
    expect(skill.concerns.join("；")).toContain("慢射 的闸门变量读不出数值，按每次调用都发一颗算");
  });

  it("函数体声明在容器、子动画只打一句调用时，颗数照样折出来并说明来源", () => {
    const skill = shotSkill("容器代声明");

    expect(skill.functionShots).toMatchObject([
      { name: "跨包射击", declaredIn: "发弹/代码层/敌人-发弹怪.xml", pelletsPerShot: 2, calls: 1, emissions: 1 },
    ]);
    expect(skill.segments).toBeCloseTo(2, 6);
    expect(skill.multiplier).toBeCloseTo(3, 6);
    expect(skill.concerns.join("；")).toContain("函数体在 发弹/代码层/敌人-发弹怪.xml 里声明，本文件只有调用");
  });

  it("自己就是子弹的实例不再按调用点重复计，纯特效函数压根不算发弹函数", () => {
    const measure = shotMeasure();
    const byLabel = new Map(measure.skills.map((skill) => [skill.label, skill]));

    // 第 162 帧摆出去的实例内联写了 子弹威力，同时 enterFrame 调 补射()：只按那颗子弹计一次
    expect(byLabel.get("自弹不复算")?.hits).toBe(1);
    expect(byLabel.get("自弹不复算")?.functionShots).toBeUndefined();
    expect(byLabel.get("自弹不复算")?.segments).toBeCloseTo(1, 6);
    // 火花() 的函数体没有 子弹威力，不认它是发弹函数 → 这一段一颗子弹都没有，连招式都不出
    expect(byLabel.get("特效函数")).toBeUndefined();
  });

  it("函数发弹的颗数进段数均值，也一起决定候选段数系数", () => {
    const measure = shotMeasure();
    const skills = measure.skills.filter((skill) => skill.file === "发弹/动画/发弹合集.xml");

    expect(skills.map((skill) => skill.label).sort((a, b) => a.localeCompare(b, "zh"))).toEqual(
      ["容器代声明", "帧脚本点射", "闸门读不出", "自弹不复算", "逐帧连发"].sort((a, b) => a.localeCompare(b, "zh")),
    );
    // 15、4、6、2、1：五招里有三招的子弹全部来自函数调用
    const summary = summarizeAttack({ ...measure, skills });
    expect(summary.skills).toBe(5);
    expect(summary.segments).toBeCloseTo(5.6, 6);
    expect(summary.multiplier).toBeCloseTo((1 + 4 + 2 + 3 + 2) / 5, 6);
  });
});

describe("霸体系数 的元件观测", () => {
  it("击倒/倒地 两段各有统一击飞函数、每发击退都超过 9 帧时取 1（长击退可击飞）", () => {
    const armor = armorFixture({ spans: [14, 10] });

    expect(armor).toMatchObject({
      factor: 1,
      band: "长击退可击飞",
      airborne: true,
      knockback: "长",
      hitStateFound: true,
      hitStates: "被击(11~19)",
      hitFiles: 1,
      concerns: [],
    });
    // 证据挂在容器自己的帧上：帧号就等于状态标签的帧号
    expect(armor.evidences).toEqual([
      { state: "击倒", frame: 19, word: "击飞浮空", via: "函数", item: "霸体/击倒动作" },
      { state: "倒地", frame: 27, word: "击飞倒地", via: "函数", item: "霸体/倒地动作" },
    ]);
    expect(armor.knockbackSpans).toEqual([
      { file: "霸体/受创动画.xml", label: "a0", start: 0, frames: 14, basis: "动画完毕" },
      { file: "霸体/受创动画.xml", label: "a1", start: 15, frames: 10, basis: "动画完毕" },
    ]);
  });

  it("没统一进那两个函数、内联写了浮空代码的同样算可击飞", () => {
    const armor = armorFixture({ knockdown: "内联", lying: "内联", spans: [12] });

    expect(armor).toMatchObject({ factor: 1, airborne: true, concerns: [] });
    expect(armor.evidences.map((entry) => [entry.state, entry.word, entry.via])).toEqual([
      ["击倒", "浮空 = true", "内联"],
      ["倒地", "倒地 = true", "内联"],
    ]);
  });

  it("只摆了名字叫击飞的元件、一处脚本都没写时不算可击飞：元件名不是击飞证据", () => {
    const armor = armorFixture({ knockdown: "元件名", lying: "元件名", spans: [4, 4] });

    expect(armor).toMatchObject({ factor: 4, band: "短击退不可击飞", airborne: false, evidences: [] });
    // 摆了 击飞 元件这件事仍然记进 concerns，人工据此去认这到底是没统一还是真没击飞
    expect(armor.concerns).toEqual([
      "击倒 状态段摆了 霸体/击飞特效 这类击飞元件，但没有生效击飞代码（元件名与注释里的代码都不算）",
      "倒地 状态段摆了 霸体/击飞特效 这类击飞元件，但没有生效击飞代码（元件名与注释里的代码都不算）",
    ]);
  });

  it("注释里的击飞代码不算：行注释与块注释都不给证据", () => {
    for (const style of ["行注释", "块注释"] as AirborneStyle[]) {
      const armor = armorFixture({ knockdown: style, lying: style, spans: [14] });

      expect(armor).toMatchObject({ factor: 3, band: "长击退不可击飞", airborne: false, evidences: [] });
      expect(armor.concerns).toContain("击倒 状态段摆了元件但没有击飞逻辑");
    }
  });

  it("有击飞代码但那帧没摆元件时也不算：判据是代码与元件都在段里", () => {
    const armor = armorFixture({ knockdown: "帧脚本", lying: "帧脚本", spans: [14] });

    expect(armor).toMatchObject({ factor: 3, airborne: false });
    // 证据仍然如实列出来，人工看得出「有代码、缺元件」
    expect(armor.evidences.map((entry) => [entry.state, entry.via])).toEqual([
      ["击倒", "函数"],
      ["倒地", "函数"],
    ]);
    expect(armor.concerns).toEqual(["击倒 状态段只有帧脚本、没摆元件", "倒地 状态段只有帧脚本、没摆元件"]);
  });

  it("阈值是「大于」不是「大于等于」：正好 9 帧算短击退，10 帧才算长击退", () => {
    expect(armorFixture({ spans: [9] }).factor).toBe(2);
    expect(armorFixture({ spans: [10] }).factor).toBe(1);
  });

  it("一发长一发短时按 knockbackReading 归一个判断", () => {
    const rules = (reading: "any" | "all" | "mean"): ArmorRules => ({ ...DEFAULT_ARMOR_RULES, knockbackReading: reading });
    const spans = [14, 5];

    expect(armorFixture({ spans, rules: rules("any") }).knockback).toBe("长");
    expect(armorFixture({ spans, rules: rules("all") }).knockback).toBe("短");
    // (14 + 5) / 2 = 9.5 > 9
    expect(armorFixture({ spans, rules: rules("mean") }).knockback).toBe("长");
  });

  it("缺 倒地 段、或 倒地 摆了元件但没有击飞逻辑，都算不可击飞", () => {
    const noState = armorFixture({ lying: "缺段", spans: [14] });
    expect(noState).toMatchObject({ factor: 3, band: "长击退不可击飞", airborne: false });
    expect(noState.concerns).toContain("容器状态段里没有倒地");

    const noLogic = armorFixture({ lying: "无", spans: [6] });
    expect(noLogic).toMatchObject({ factor: 4, band: "短击退不可击飞" });
    expect(noLogic.concerns).toContain("倒地 状态段摆了元件但没有击飞逻辑");
  });

  it("没有 被击 状态段、被击 段没摆元件、摆的元件解析不到库文件，都按不可击退取 5", () => {
    const noState = armorFixture({ hit: "缺段", spans: [14] });
    expect(noState).toMatchObject({ factor: 5, band: "不可击退不可击飞", hitStateFound: false, knockback: "不可" });
    expect(noState.concerns.join("；")).toContain("容器状态段里没有 被击");

    const emptyState = armorFixture({ hit: "不摆" });
    expect(emptyState.factor).toBe(5);
    expect(emptyState.concerns.join("；")).toContain("被击 段（被击(11~19)）盖住的 1 帧里没摆元件");

    const unresolvable = armorFixture({ hit: "解析不到" });
    expect(unresolvable.factor).toBe(5);
    expect(unresolvable.concerns.join("；")).toContain("解析不到库文件");
    // 读不出击退时长时连"可击飞"也照样如实记下来
    expect(unresolvable.airborne).toBe(true);
  });

  it("受创动画没有命名帧时从第一帧量到 动画完毕", () => {
    const armor = armorFixture({ spans: [14], unnamed: true });

    expect(armor.knockbackSpans).toEqual([
      { file: "霸体/受创动画.xml", label: "（整段）", start: 0, frames: 14, basis: "动画完毕" },
    ]);
    expect(armor.factor).toBe(1);
  });

  it("受创动画里找不到 动画完毕 时按时间轴末尾折算，并在账里标出来让人工复核", () => {
    const armor = armorFixture({ spans: [14], noOverCall: true });

    expect(armor.knockbackSpans[0]).toMatchObject({ label: "a0", frames: 15, basis: "段尾" });
    expect(armor.concerns.join("；")).toContain("之后没有 动画完毕，击退时长按动画末尾折算");
    expect(armorAccount(armor)).toContain("a0=15†");
  });

  it("状态段名带后缀变体（被击--/倒地-无）也按词表命中", () => {
    const armor = armorFixture({ spans: [14], hitLabel: "被击--", lyingLabel: "倒地-无" });

    expect(armor.hitStates).toBe("被击--(11~19)");
    expect(armor.factor).toBe(1);
    expect(armor.evidences.map((entry) => entry.state)).toEqual(["击倒", "倒地-无"]);
  });

  it("量到霸体证据时，一个招式都没量到也照样补 霸体系数", () => {
    const summary = summarizeAttack(measureIn(writeArmorRepo({}), "敌人-霸体怪"));

    expect(summary.skills).toBe(0);
    expect(summary.armor?.factor).toBe(1);

    const proposal = proposeAttackFlags(summary, BANDS, TAIL);
    expect(proposal.flags).toEqual({ 霸体系数: 1 });
    expect(proposal.notes.join("；")).toContain("没有可用招式，攻速/倍率/段数 不给候选值");
    expect(proposal.notes.join("；")).toContain("霸体：击倒/倒地 各有击飞逻辑（2 处证据）；击退时长 a0=14、a1=10 → 长击退；取 1（长击退可击飞）");
  });

  it("韧性系数 按 Excel H34 给 霸体系数 带小数位：高于 20 每 20 点加 0.1、上限 0.5", () => {
    const summary = summarizeAttack(measureIn(writeArmorRepo({}), "敌人-霸体怪"));
    expect(summary.armor?.factor).toBe(1);

    expect(proposeAttackFlags(summary, BANDS, TAIL, 50).flags).toEqual({ 霸体系数: 1.2 });
    expect(proposeAttackFlags(summary, BANDS, TAIL, 30).flags).toEqual({ 霸体系数: 1.1 });
    expect(proposeAttackFlags(summary, BANDS, TAIL, 200).flags).toEqual({ 霸体系数: 1.5 });
    // 20 本身不算「高于 20」，没给韧性也不硬造小数位
    expect(proposeAttackFlags(summary, BANDS, TAIL, 20).flags).toEqual({ 霸体系数: 1 });
    expect(proposeAttackFlags(summary, BANDS, TAIL).flags).toEqual({ 霸体系数: 1 });

    expect(proposeAttackFlags(summary, BANDS, TAIL, 50).notes.join("；")).toContain(
      "取 1（长击退可击飞）＋韧性 50 按 Excel H34 加 0.2 = 1.2",
    );
    expect(proposeAttackFlags(summary, BANDS, TAIL, 10).notes.join("；")).toContain("取 1（长击退可击飞）");
  });

  it("取档账把证据处数、每发击退时长与档位名逐条写出来", () => {
    expect(armorAccount(armorFixture({ lying: "无", spans: [14, 5] }))).toBe(
      "霸体：击倒/倒地 没凑齐击飞逻辑（不可击飞）；击退时长 a0=14、a1=5 → 长击退；取 3（长击退不可击飞）",
    );
    expect(armorAccount(armorFixture({ hit: "不摆" }))).toBe("霸体：击倒/倒地 各有击飞逻辑（2 处证据）；被击 读不出击退时长 → 不可击退；取 5（不可击退不可击飞）");
  });
});

function measureFixture(): ReturnType<typeof measureMonsterAttack> {
  return measureIn(writeFixtureRepo(), "敌人-测试怪");
}

function measureIn(repo: string, spritename: string): ReturnType<typeof measureMonsterAttack> {
  return measureMonsterAttack(
    { spritename, panelAtkMin: 100, panelAtkMax: 100, segmentWindowFrames: WINDOW },
    loadAssetSources(repo),
    repo,
  );
}

/**
 * 最小 XFL 包：容器（代码层）直接摆动画，动画再摆子弹实例。
 * 子弹脚本有三种落点 —— 实例内联、子弹元件自带、帧级 —— 都只算一次命中。
 */
function writeFixtureRepo(registry = `<asset id="敌人-测试怪" swf="arts/测试包.swf" symbolName="测试/代码层/敌人-测试怪" />`): string {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-attack-"));
  const library = "arts/测试包/LIBRARY";

  write(repo, "data/items/asset_source_map.xml", `<xml>
  <library>
    ${registry}
  </library>
</xml>
`);
  write(repo, "arts/测试包/DOMDocument.xml", `<DOMDocument version="2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>\n`);

  write(repo, `${library}/测试/代码层/敌人-测试怪.xml`, symbol('linkageIdentifier="敌人-测试怪"',
    // 状态机层：动作层摆在哪个状态段里，那段动画就是干什么的
    layer("状态", [
      frame(0, 1, "", "空手站立"),
      frame(1, 40, "", "近战"),
      frame(41, 1, "", "被击"),
      frame(42, 1, "", "血腥死"),
    ]),
    layer("代码", [
      frame(0, 1, script(`
        攻击欲望 = 3;
        if (random(_parent.攻击欲望 * 2) == 0) { 状态改变("打一下"); }
        if (random(_parent.攻击欲望) == 0) { 状态改变("打两下"); }`)),
    ]),
    layer("动作", [frame(1, 1, `<elements>${instance("测试/动画合集/普通攻击")}</elements>`)]),
  ));

  write(repo, `${library}/测试/动画合集/普通攻击.xml`, symbol("",
    layer("标签", [frame(0, 30, "", "打一下"), frame(30, 20, "", "打两下"), frame(50, 8, "", "废弃连击")]),
    layer("子弹", [      frame(5, 1, `<elements>${
        instance("子弹/近战子弹", "子弹属性.霰弹值 = 2; 子弹属性.子弹威力 = _parent._parent.空手攻击力 * 2;")
      }</elements>`),
      // 实例上没有脚本，取子弹元件自己的脚本
      frame(9, 1, `<elements>${instance("子弹/远程子弹")}</elements>`),
      frame(35, 1, `<elements>${instance(
        "子弹/近战子弹",
        // 分支写法（2 与 4）取均值，`+= 1` 追加，`最小霰弹值` 是随机区间的另一端、不算段数 → 3 + 1 = 4 段
        "子弹属性.最小霰弹值 = 9; 子弹属性.霰弹值 = 2; 子弹属性.霰弹值 = 4; 子弹属性.霰弹值 += 1; 子弹属性.子弹威力 = _parent._parent.空手攻击力;",
      )}</elements>`),
      // 帧级脚本兜底：没有实例只有帧脚本时也算一次命中
      frame(52, 1, script("子弹属性.霰弹值 = 1; 子弹属性.子弹威力 = _parent._parent.空手攻击力 * 6;")),
    ]),
    // 打一下 段末尾通知容器切状态，后摇量到这一帧；打两下 段没写，后摇退回段尾折算
    layer("结束", [frame(25, 1, script("_parent.动画完毕();"))]),
  ));

  write(repo, `${library}/子弹/近战子弹.xml`, symbol("", layer("外形", [frame(0, 1, "")])));
  write(repo, `${library}/子弹/远程子弹.xml`, symbol("",
    layer("代码", [frame(0, 1, script("子弹属性.霰弹值 = 1; 子弹属性.子弹威力 = _parent._parent.空手攻击力;"))]),
  ));

  // 容器没摆放的特效：带 子弹威力 也不该进这只怪的招式
  write(repo, `${library}/测试/动画合集/刀光特效.xml`, symbol("",
    layer("标签", [frame(0, 8, "", "消失")]),
    layer("子弹", [frame(2, 1, `<elements>${
      instance("子弹/近战子弹", '子弹属性.子弹威力 = 800; 子弹属性.伤害类型 = "魔法";')
    }</elements>`)]),
  ));

  return repo;
}

/**
 * 招式合集包：容器直接摆 `连招合集`（只有 `gotoAndPlay(招式名)` 这种变量跳转）、
 * `顺播合集`（一段脚本都没有，纯靠播放头顺播）和 `状态合集`（宿主只 goto 到 受创）。
 * 三份的招式标签都没人按名挑，都该算这只怪的有效招式。
 * 同目录的 `兄弟合集` 没被摆出去，仍不算这只怪的招式。
 */
function writeComboRepo(): string {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-combo-"));
  const library = "arts/连招包/LIBRARY";

  write(repo, "data/items/asset_source_map.xml", `<xml>
  <library>
    <asset id="敌人-连招怪" swf="arts/连招包.swf" symbolName="连招/代码层/敌人-连招怪" />
  </library>
</xml>
`);
  write(repo, "arts/连招包/DOMDocument.xml", `<DOMDocument version="2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>\n`);

  write(repo, `${library}/连招/代码层/敌人-连招怪.xml`, symbol('linkageIdentifier="敌人-连招怪"',
    layer("状态", [frame(0, 1, "", "空手站立"), frame(1, 40, "", "近战")]),
    layer("代码", [frame(0, 1, script("攻击欲望 = 3; 状态改变(\"受创\");"))]),
    layer("动作", [frame(1, 1, `<elements>${instance("连招/动画合集/连招合集")}${instance("连招/动画合集/顺播合集")}${instance("连招/动画合集/状态合集")}</elements>`)]),
  ));

  write(repo, `${library}/连招/动画合集/连招合集.xml`, comboSymbol());
  write(repo, `${library}/连招/动画合集/顺播合集.xml`, comboSymbol(false, "顺播-"));
  write(repo, `${library}/连招/动画合集/状态合集.xml`, stateSymbol());
  write(repo, `${library}/连招/动画合集/兄弟合集.xml`, comboSymbol());
  write(repo, `${library}/子弹/近战子弹.xml`, symbol("", layer("外形", [frame(0, 1, "")])));

  return repo;
}

/**
 * 出手动画藏在中间层元件里（容器 → 出招壳 → 招式合集）：沿摆放链往里再找一层能拿到，
 * 但这一层不认"顺播"。同包的 敌人-空手怪 什么都没摆，别人的合集不该变成它的招式。
 */
function writeOrphanComboRepo(): string {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-orphan-"));
  const library = "arts/孤儿包/LIBRARY";

  write(repo, "data/items/asset_source_map.xml", `<xml>
  <library>
    <asset id="敌人-孤儿怪" swf="arts/孤儿包.swf" symbolName="孤儿/代码层/敌人-孤儿怪" />
    <asset id="敌人-空手怪" swf="arts/孤儿包.swf" symbolName="孤儿/代码层/敌人-空手怪" />
  </library>
</xml>
`);
  write(repo, "arts/孤儿包/DOMDocument.xml", `<DOMDocument version="2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>\n`);

  write(repo, `${library}/孤儿/代码层/敌人-孤儿怪.xml`, symbol('linkageIdentifier="敌人-孤儿怪"',
    layer("状态", [frame(0, 1, "", "空手站立"), frame(1, 40, "", "近战")]),
    layer("代码", [frame(0, 1, script("攻击欲望 = 3;"))]),
    layer("动作", [frame(1, 1, `<elements>${instance("孤儿/中间层/出招壳")}</elements>`)]),
  ));
  write(repo, `${library}/孤儿/代码层/敌人-空手怪.xml`, symbol('linkageIdentifier="敌人-空手怪"',
    layer("状态", [frame(0, 1, "", "空手站立"), frame(1, 40, "", "近战")]),
    layer("代码", [frame(0, 1, script("攻击欲望 = 2;"))]),
  ));
  // 出招壳自己不打人，只把招式合集摆进去一层
  write(repo, `${library}/孤儿/中间层/出招壳.xml`, symbol("",
    layer("标签", [frame(0, 40, "", "出招")]),
    layer("动作", [frame(1, 1, `<elements>${instance("孤儿/动画合集/招式合集")}</elements>`)]),
  ));
  write(repo, `${library}/孤儿/动画合集/招式合集.xml`, comboSymbol());
  write(repo, `${library}/子弹/近战子弹.xml`, symbol("", layer("外形", [frame(0, 1, "")])));

  return repo;
}

/**
 * 同库多怪包：容器与动画都摆在包根。每只怪只认自己摆出去的那份合集，
 * 兄弟怪的动画即使同包同目录、即使代码里写着字面跳转，也不进这只怪的招式。
 */
function writeSharedPackageRepo(): string {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-share-"));
  const library = "arts/共用包/LIBRARY";

  write(repo, "data/items/asset_source_map.xml", `<xml>
  <library>
    <asset id="敌人-借招怪" swf="arts/共用包.swf" symbolName="敌人-借招怪" />
    <asset id="敌人-兄弟" swf="arts/共用包.swf" symbolName="敌人-兄弟" />
  </library>
</xml>
`);
  write(repo, "arts/共用包/DOMDocument.xml", `<DOMDocument version="2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>\n`);

  write(repo, `${library}/敌人-借招怪.xml`, symbol('linkageIdentifier="敌人-借招怪"',
    layer("状态", [frame(0, 1, "", "空手站立"), frame(1, 40, "", "近战")]),
    layer("代码", [frame(0, 1, script("攻击欲望 = 3;"))]),
    layer("动作", [frame(1, 1, `<elements>${instance("自家合集")}</elements>`)]),
  ));
  write(repo, `${library}/敌人-兄弟.xml`, symbol('linkageIdentifier="敌人-兄弟"',
    layer("状态", [frame(0, 1, "", "空手站立"), frame(1, 40, "", "近战")]),
    layer("代码", [frame(0, 1, script("攻击欲望 = 3; 状态改变(\"兄弟弹幕\");"))]),
    layer("动作", [frame(1, 1, `<elements>${instance("兄弟动画")}</elements>`)]),
  ));
  write(repo, `${library}/自家合集.xml`, comboSymbol(false, "自家"));
  write(repo, `${library}/兄弟动画.xml`, symbol("",
    layer("标签", [frame(0, 12, "", "兄弟弹幕")]),
    layer("子弹", [frame(4, 1, meleeHit())]),
  ));
  write(repo, `${library}/子弹/近战子弹.xml`, symbol("", layer("外形", [frame(0, 1, "")])));

  return repo;
}

/**
 * 状态硬门包：容器在 近战/被击/血腥死 三段状态里各摆一份带参数的动画。
 * 只有 近战 段那份算招式；`敌人-两用作` 把同一份动画既摆在 近战 又摆在 被击，仍然放行。
 */
function writeStateGateRepo(): string {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-state-"));
  const library = "arts/状态包/LIBRARY";

  write(repo, "data/items/asset_source_map.xml", `<xml>
  <library>
    <asset id="敌人-状态怪" swf="arts/状态包.swf" symbolName="状态/敌人-状态怪" />
    <asset id="敌人-两用作" swf="arts/状态包.swf" symbolName="状态/敌人-两用作" />
  </library>
</xml>
`);
  write(repo, "arts/状态包/DOMDocument.xml", `<DOMDocument version="2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>\n`);

  const states = [frame(0, 1, "", "空手站立"), frame(1, 10, "", "近战"), frame(11, 10, "", "被击"), frame(21, 20, "", "血腥死")];
  write(repo, `${library}/状态/敌人-状态怪.xml`, symbol('linkageIdentifier="敌人-状态怪"',
    layer("状态", states),
    layer("代码", [frame(0, 1, script("攻击欲望 = 3; 状态改变(\"出手\"); 状态改变(\"挨打反弹\"); 状态改变(\"濒死反击\");"))]),
    layer("动作", [
      frame(1, 1, `<elements>${instance("状态/近战弹幕")}</elements>`),
      frame(11, 1, `<elements>${instance("状态/挨打反弹")}</elements>`),
      frame(21, 1, `<elements>${instance("状态/濒死反击")}</elements>`),
    ]),
  ));
  write(repo, `${library}/状态/敌人-两用作.xml`, symbol('linkageIdentifier="敌人-两用作"',
    layer("状态", [frame(0, 1, "", "空手站立"), frame(1, 10, "", "近战"), frame(11, 10, "", "被击")]),
    layer("代码", [frame(0, 1, script("攻击欲望 = 3; 状态改变(\"共用弹幕\");"))]),
    layer("动作", [
      frame(1, 1, `<elements>${instance("状态/两用动画")}</elements>`),
      frame(11, 1, `<elements>${instance("状态/两用动画")}</elements>`),
    ]),
  ));

  // 三份动画都是"标签 + 一颗带参数的近战子弹"，只有摆放时所在的状态段不同
  write(repo, `${library}/状态/近战弹幕.xml`, hitSymbol("出手"));
  write(repo, `${library}/状态/挨打反弹.xml`, hitSymbol("挨打反弹"));
  write(repo, `${library}/状态/濒死反击.xml`, hitSymbol("濒死反击"));
  write(repo, `${library}/状态/两用动画.xml`, hitSymbol("共用弹幕"));
  write(repo, `${library}/子弹/近战子弹.xml`, symbol("", layer("外形", [frame(0, 1, "")])));

  return repo;
}

/** 一份只有一招、起手后 2 帧摆出一颗 2 段子弹的动画。 */
function hitSymbol(label: string): string {
  return symbol("",
    layer("标签", [frame(0, 20, "", label)]),
    layer("子弹", [frame(2, 1, meleeHit())]),
  );
}

/** 标签没盖住的时间轴段落：头段够长按顺播补一招，尾段太短不算。 */
function writeGapRepo(): string {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-gap-"));
  const library = "arts/空档包/LIBRARY";

  write(repo, "data/items/asset_source_map.xml", `<xml>
  <library>
    <asset id="敌人-空档怪" swf="arts/空档包.swf" symbolName="空档/敌人-空档怪" />
  </library>
</xml>
`);
  write(repo, "arts/空档包/DOMDocument.xml", `<DOMDocument version="2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>\n`);

  write(repo, `${library}/空档/敌人-空档怪.xml`, symbol('linkageIdentifier="敌人-空档怪"',
    layer("状态", [frame(0, 1, "", "空手站立"), frame(1, 40, "", "空手攻击")]),
    layer("代码", [frame(0, 1, script("攻击欲望 = 3; 状态改变(\"a0\");"))]),
    layer("动作", [frame(1, 1, `<elements>${instance("空档/空档动画")}</elements>`)]),
  ));
  write(repo, `${library}/空档/空档动画.xml`, symbol("",
    layer("标签", [frame(0, 8, ""), frame(8, 20, "", "a0"), frame(28, 3, "")]),
    layer("子弹", [frame(4, 1, meleeHit()), frame(20, 1, meleeHit())]),
  ));
  write(repo, `${library}/子弹/近战子弹.xml`, symbol("", layer("外形", [frame(0, 1, "")])));

  return repo;
}

/** 容器住在库根、出手动画在子目录 —— 老口径按目录划作用域会把 素材/ 子树整个丢掉。 */
function writeRootContainerRepo(): string {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-root-"));
  const library = "arts/库根包/LIBRARY";

  write(repo, "data/items/asset_source_map.xml", `<xml>
  <library>
    <asset id="敌人-库根怪" swf="arts/库根包.swf" symbolName="敌人-库根怪" />
  </library>
</xml>
`);
  write(repo, "arts/库根包/DOMDocument.xml", `<DOMDocument version="2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>\n`);

  write(repo, `${library}/敌人-库根怪.xml`, symbol('linkageIdentifier="敌人-库根怪"',
    layer("状态", [frame(0, 1, "", "空手站立"), frame(1, 40, "", "近战")]),
    layer("代码", [frame(0, 1, script("攻击欲望 = 3;"))]),
    layer("动作", [frame(1, 1, `<elements>${instance("素材/Symbol 154")}</elements>`)]),
  ));
  // 包根上躺着别人的动画，也带 子弹威力：以前靠目录兜底时它会把作用域钉在包根
  write(repo, `${library}/兄弟怪的动画.xml`, hitSymbol("兄弟弹幕"));
  write(repo, `${library}/素材/Symbol 154.xml`, comboSymbol(false));
  write(repo, `${library}/子弹/近战子弹.xml`, symbol("", layer("外形", [frame(0, 1, "")])));

  return repo;
}

type SkillMeasure = ReturnType<typeof measureMonsterAttack>["skills"][number];

/**
 * 近战颗数包：一招把无区域近战子弹铺在屏幕各处、一招走区域联弹、一招是非近战、
 * 一招不写 子弹种类 只靠子弹元件名认、一招同屏摆横向与纵向联弹、一招是把横向联弹铺满屏幕的非近战子弹、
 * 一招是把 横向/纵向机枪联弹 摆在一起的非近战子弹。
 * 合集由容器直接摆出，七段标签都顺播。
 */
function writeMeleeRepo(): string {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-melee-"));
  const library = "arts/颗数包/LIBRARY";

  write(repo, "data/items/asset_source_map.xml", `<xml>
  <library>
    <asset id="敌人-颗数怪" swf="arts/颗数包.swf" symbolName="颗数/代码层/敌人-颗数怪" />
  </library>
</xml>
`);
  write(repo, "arts/颗数包/DOMDocument.xml", `<DOMDocument version="2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>\n`);

  write(repo, `${library}/颗数/代码层/敌人-颗数怪.xml`, symbol('linkageIdentifier="敌人-颗数怪"',
    layer("状态", [frame(0, 1, "", "空手站立"), frame(1, 200, "", "近战")]),
    layer("代码", [frame(0, 1, script("攻击欲望 = 3;"))]),
    layer("动作", [frame(1, 1, `<elements>${instance("颗数/动画合集/颗数合集")}</elements>`)]),
  ));

  write(repo, `${library}/颗数/动画合集/颗数合集.xml`, symbol("",
    layer("标签", [
      frame(0, 20, "", "散拨"),
      frame(20, 20, "", "区域联弹"),
      frame(40, 20, "", "非近战"),
      frame(60, 20, "", "认名"),
      frame(80, 20, "", "方向联弹"),
      frame(100, 20, "", "非近战联弹"),
      frame(120, 20, "", "机枪联弹"),
    ]),
    layer("子弹", [
      // 同一拨 4 颗横向铺到 400 单位（80 宽的框最多框住相邻 2 颗），另一拨 2 颗纵向隔 200（超过 170 高）
      frame(5, 1, `<elements>${bulletAt("子弹/近战子弹", 0, 0, bulletScript("近战子弹", 1))}${bulletAt("子弹/近战子弹", 60, 0, bulletScript("近战子弹", 1))}</elements>`),
      frame(6, 1, `<elements>${bulletAt("子弹/近战子弹", 120, 0, bulletScript("近战子弹", 1))}${bulletAt("子弹/近战子弹", 400, 0, bulletScript("近战子弹", 1))}</elements>`),
      frame(12, 1, `<elements>${bulletAt("子弹/近战子弹", 0, 0, bulletScript("近战子弹", 1))}${bulletAt("子弹/近战子弹", 0, 200, bulletScript("近战子弹", 1))}</elements>`),
      // 区域判定不参与颗数过滤，但近战联弹的单元体铺开 → 霰弹值 只按分量算；同屏的纵向联弹即使传了 area 也不折
      frame(25, 1, `<elements>${bulletAt("子弹/近战子弹", 0, 0, bulletScript("近战联弹", 5, true))}</elements>`),
      frame(26, 1, `<elements>${bulletAt("子弹/近战子弹", 60, 0, bulletScript("纵向联弹", 5, true))}</elements>`),
      // 非近战是线状判定，同帧摆 3 颗也一颗不落
      frame(45, 1, `<elements>${[0, 300, 900].map((x) => bulletAt("子弹/远程子弹", x, 0, bulletScript("远程子弹", 4))).join("")}</elements>`),
      // 认名：4 颗都没写 子弹种类、也没有坐标，靠元件名认近战后只能退回简单法
      frame(65, 1, `<elements>${instance("子弹/近战子弹", bulletScript(undefined, 1))}${instance("子弹/近战子弹", bulletScript(undefined, 1))}${instance("子弹/近战子弹", bulletScript(undefined, 1))}</elements>`),
      frame(66, 1, `<elements>${instance("子弹/近战子弹", bulletScript(undefined, 1))}</elements>`),
      // 横向联弹 无条件折分量（10→6），纵向联弹 一律不折（5 段照旧）；两颗都没传 区域定位area。
      // 两颗都摆在 近战子弹 元件上（按元件名认近战），种类串里刻意不带 穿刺，让这一招只反映折分量与颗数两层。
      frame(85, 1, `<elements>${bulletAt("子弹/近战子弹", 0, 0, bulletScript("纵向联弹-普通子弹", 5))}${bulletAt("子弹/近战子弹", 20, 0, bulletScript("横向联弹-加强普通子弹", 10))}</elements>`),
      // 非近战联弹铺满屏幕：种类与元件名都不含 近战 → 颗数一层不进、射出多少颗就算多少颗，但 横向 那族照打 0.6 折
      // （旧口径把 联弹 也当近战类，这一招会被命中框折成每拨 3 颗）
      frame(105, 1, `<elements>${[0, 60, 120, 400, 0, 200].map((x, i) => bulletAt("子弹/远程子弹", x, i === 5 ? 200 : 0, bulletScript("横向联弹-普通子弹", 1))).join("")}</elements>`),
      // 机枪联弹 不带 联弹 方向词的完整名字（横向机枪联弹-…、纵向机枪联弹-…）：靠 横向／纵向 前缀认，不必逐条列名
      frame(125, 1, `<elements>${bulletAt("子弹/远程子弹", 0, 0, bulletScript("横向机枪联弹-加强普通子弹", 10))}${bulletAt("子弹/远程子弹", 300, 0, bulletScript("纵向机枪联弹-普通子弹", 5))}</elements>`),
    ]),
  ));

  write(repo, `${library}/子弹/近战子弹.xml`, symbol("", layer("外形", [frame(0, 1, "")])));
  write(repo, `${library}/子弹/远程子弹.xml`, symbol("", layer("外形", [frame(0, 1, "")])));

  return repo;
}

function measureMelee(rules: MeleeBulletRules = MELEE): ReturnType<typeof measureMonsterAttack> {
  const repo = writeMeleeRepo();
  return measureMonsterAttack(
    { spritename: "敌人-颗数怪", panelAtkMin: 100, panelAtkMax: 100, segmentWindowFrames: WINDOW, meleeRules: rules },
    loadAssetSources(repo),
    repo,
  );
}

function meleeSkill(label: string, rules: MeleeBulletRules = MELEE): SkillMeasure {
  const skill = measureMelee(rules).skills.find((entry) => entry.label === label);
  if (skill === undefined) throw new Error(`近战颗数包没有量到招式「${label}」`);
  return skill;
}

/**
 * 穿刺包：一招两颗 穿刺子弹、一招单颗 次级穿刺子弹、一招把 穿刺 与 次级穿刺 摆同一拨（定顺序的账）、
 * 一招近战类打在 穿刺子弹 元件上（颗数折叠 + 按元件名认穿刺）、一招把 横向与纵向联弹-穿刺子弹 摆同一拨（折分量与乘倍数叠在一起）。
 */
function writePierceRepo(): string {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-pierce-"));
  const library = "arts/穿刺包/LIBRARY";

  write(repo, "data/items/asset_source_map.xml", `<xml>
  <library>
    <asset id="敌人-穿刺怪" swf="arts/穿刺包.swf" symbolName="穿刺/代码层/敌人-穿刺怪" />
  </library>
</xml>
`);
  write(repo, "arts/穿刺包/DOMDocument.xml", `<DOMDocument version="2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>\n`);

  write(repo, `${library}/穿刺/代码层/敌人-穿刺怪.xml`, symbol('linkageIdentifier="敌人-穿刺怪"',
    layer("状态", [frame(0, 1, "", "空手站立"), frame(1, 200, "", "远程攻击")]),
    layer("代码", [frame(0, 1, script("攻击欲望 = 3;"))]),
    layer("动作", [frame(1, 1, `<elements>${instance("穿刺/动画合集/穿刺合集")}</elements>`)]),
  ));

  write(repo, `${library}/穿刺/动画合集/穿刺合集.xml`, symbol("",
    layer("标签", [
      frame(0, 20, "", "穿刺"),
      frame(20, 20, "", "次级穿刺"),
      frame(40, 20, "", "两档同拨"),
      frame(60, 20, "", "近战穿刺"),
      frame(80, 20, "", "联弹穿刺"),
    ]),
    layer("子弹", [
      // 两颗 穿刺子弹 铺在屏幕两头：非近战不做颗数判定，各按 2 倍计
      frame(5, 1, `<elements>${bulletAt("子弹/穿刺子弹", 0, 0, bulletScript("穿刺子弹", 3))}${bulletAt("子弹/穿刺子弹", 300, 0, bulletScript("穿刺子弹", 3))}</elements>`),
      // 次级穿刺只有 1.5 倍，且不能被 穿刺 词收走（不然这里是 8）
      frame(25, 1, `<elements>${bulletAt("子弹/次级穿刺子弹", 0, 0, bulletScript("次级穿刺子弹", 4))}</elements>`),
      // 同一拨里两档并存：穿刺 2×2、次级穿刺 2×1.5
      frame(45, 1, `<elements>${bulletAt("子弹/穿刺子弹", 0, 0, bulletScript("穿刺子弹", 2))}${bulletAt("子弹/次级穿刺子弹", 20, 0, bulletScript("次级穿刺子弹", 2))}</elements>`),
      // 近战类（种类含 近战）打在 穿刺子弹 元件上：先按命中框折颗数，再乘穿刺倍数
      frame(65, 1, `<elements>${[0, 60, 120, 400].map((x) => bulletAt("子弹/穿刺子弹", x, 0, bulletScript("近战子弹", 1))).join("")}</elements>`),
      // 联弹折分量与穿刺倍数叠在一颗上：横向联弹 先折 0.6（5→3）再乘 2＝6；纵向联弹 不折、只乘 2＝10
      frame(85, 1, `<elements>${bulletAt("子弹/远程子弹", 0, 0, bulletScript("横向联弹-穿刺子弹", 5))}${bulletAt("子弹/远程子弹", 300, 0, bulletScript("纵向联弹-穿刺子弹", 5))}</elements>`),
    ]),
  ));

  write(repo, `${library}/子弹/穿刺子弹.xml`, symbol("", layer("外形", [frame(0, 1, "")])));
  write(repo, `${library}/子弹/次级穿刺子弹.xml`, symbol("", layer("外形", [frame(0, 1, "")])));
  write(repo, `${library}/子弹/远程子弹.xml`, symbol("", layer("外形", [frame(0, 1, "")])));

  return repo;
}

function pierceSkill(label: string, pierce: PierceSegmentRules = PIERCE): SkillMeasure {
  const repo = writePierceRepo();
  const measure = measureMonsterAttack(
    {
      spritename: "敌人-穿刺怪",
      panelAtkMin: 100,
      panelAtkMax: 100,
      segmentWindowFrames: WINDOW,
      meleeRules: MELEE,
      pierceRules: pierce,
    },
    loadAssetSources(repo),
    repo,
  );
  const skill = measure.skills.find((entry) => entry.label === label);
  if (skill === undefined) throw new Error(`穿刺包没有量到招式「${label}」`);
  return skill;
}

/**
 * 函数式发弹的靶包：六段标签各摆一种发弹写法，颗数只能从函数调用次数折出来。
 * 面板空手 100，所以 威力 = N * 空手攻击力 就直接是 N 倍。
 */
function writeShotRepo(): string {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-shot-"));
  const library = "arts/发弹包/LIBRARY";

  write(repo, "data/items/asset_source_map.xml", `<xml>
  <library>
    <asset id="敌人-发弹怪" swf="arts/发弹包.swf" symbolName="发弹/代码层/敌人-发弹怪" />
  </library>
</xml>
`);
  write(repo, "arts/发弹包/DOMDocument.xml", `<DOMDocument version="2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>\n`);

  // 跨包射击 的函数体只在容器上，子动画里打一句调用
  write(repo, `${library}/发弹/代码层/敌人-发弹怪.xml`, symbol('linkageIdentifier="敌人-发弹怪"',
    layer("状态", [frame(0, 1, "", "空手站立"), frame(1, 400, "", "远程攻击")]),
    layer("代码", [
      frame(0, 1, script(["状态改变 = 1;", "攻击欲望 = 3;", shot("跨包射击", [kind("远程子弹"), pellets(2), power("3 * _parent.空手攻击力"), "子弹区域shoot传递(子弹属性);"]).join("\n")].join("\n"))),
    ]),
    layer("动作", [frame(1, 1, `<elements>${instance("发弹/动画/发弹合集")}</elements>`)]),
  ));

  write(repo, `${library}/发弹/动画/发弹合集.xml`, symbol("",
    layer("标签", [
      frame(0, 40, "", "逐帧连发"),
      frame(40, 40, "", "帧脚本点射"),
      frame(80, 40, "", "闸门读不出"),
      frame(120, 40, "", "容器代声明"),
      frame(160, 40, "", "自弹不复算"),
      frame(200, 40, "", "特效函数"),
    ]),
    layer("代码", [
      // 射击：性能倍率 从同文件数值声明读成 2，威力 0.5*2 正好 1 倍，闸门每 2 次触发发 1 弹
      frame(0, 1, script(["性能倍率 = 2;", "射击计数 = 0;", shot("射击", [kind("远程子弹"), pellets(3), power("0.5 * 性能倍率 * _parent.空手攻击力"), throttle("性能倍率"), "子弹区域shoot传递(子弹属性);"]).join("\n")].join("\n"))),
      frame(40, 1, script(shot("毒刺射击", [kind("毒刺"), pellets(1), power("4 * _parent.空手攻击力"), "子弹区域shoot传递(子弹属性);"]).join("\n"))),
      // 慢射：闸门写的是没给过数值的变量
      frame(80, 1, script(shot("慢射", [kind("远程子弹"), pellets(1), power("2 * _parent.空手攻击力"), throttle("未知闸门"), "子弹区域shoot传递(子弹属性);"]).join("\n"))),
      // 补射 有人调（就挂在下一行那颗自带 子弹威力 的实例上）；火花 压根不认作发弹函数
      frame(160, 1, script(shot("补射", [kind("远程子弹"), pellets(4), power("1 * _parent.空手攻击力")]).join("\n"))),
      frame(200, 1, script(shot("火花", ["特效.火花 = true;"]).join("\n"))),
    ]),
    layer("调用", [
      frame(45, 1, script("毒刺射击();")),
      frame(50, 1, script("毒刺射击();")),
      frame(55, 1, script("毒刺射击();")),
      frame(60, 1, script("毒刺射击();")),
      frame(125, 1, script("跨包射击();")),
    ]),
    layer("锚点", [
      // 枪口元件自己不发子弹：它只是发射点，颗数全从函数体来
      frame(2, 10, `<elements>${instance("发弹/其他/枪口", enterFrame("射击();"))}</elements>`),
      frame(82, 6, `<elements>${instance("发弹/其他/枪口", enterFrame("慢射();"))}</elements>`),
      frame(205, 3, `<elements>${instance("发弹/其他/枪口", enterFrame("火花();"))}</elements>`),
    ]),
    layer("子弹", [
      // 这一颗内联就写了 子弹威力，自己算子弹，不再按它的 enterFrame 调用重复计
      frame(162, 5, `<elements>${bulletAt("子弹/真子弹", 100, 0, [`子弹属性.霰弹值 = 1;`, "子弹属性.子弹威力 = _parent._parent.空手攻击力 * 2;", enterFrame("补射();")].join("\n"))}</elements>`),
    ]),
  ));

  write(repo, `${library}/发弹/其他/枪口.xml`, symbol("", layer("外形", [frame(0, 1, "")])));
  write(repo, `${library}/子弹/真子弹.xml`, symbol("", layer("外形", [frame(0, 1, "")])));

  return repo;
}

/** 发弹函数体：种类、霰弹值、威力各写一行，闸门可选。 */
function shot(name: string, lines: string[]): string[] {
  return [`function ${name}() {`, ...lines.map((line) => `\t${line}`), "}"];
}

function kind(value: string): string {
  return `子弹属性.子弹种类 = "${value}";`;
}

function pellets(value: number): string {
  return `子弹属性.霰弹值 = ${value};`;
}

function power(expr: string): string {
  return `子弹属性.子弹威力 = ${expr};`;
}

function throttle(gate: string): string {
  return `if ((射击计数 ++ % ${gate}) != 0) {\n\t\treturn;\n\t}`;
}

/** 挂在实例上的逐帧处理器：容器把它摆上台的每一帧都跑一次。 */
function enterFrame(body: string): string {
  return `onClipEvent (enterFrame) {\n\t_parent.${body}\n}`;
}

function shotMeasure(): ReturnType<typeof measureMonsterAttack> {
  const repo = writeShotRepo();
  return measureMonsterAttack(
    { spritename: "敌人-发弹怪", panelAtkMin: 100, panelAtkMax: 100, segmentWindowFrames: WINDOW, meleeRules: MELEE, pierceRules: PIERCE },
    loadAssetSources(repo),
    repo,
  );
}

function shotSkill(label: string): SkillMeasure {
  const skill = shotMeasure().skills.find((entry) => entry.label === label);
  if (skill === undefined) throw new Error(`发弹包没有量到招式「${label}」`);
  return skill;
}

/** 摆出坐标的子弹实例：几何法量的就是这对 centerPoint3DX/Y。 */
function bulletAt(item: string, x: number, y: number, as2: string): string {
  return `<DOMSymbolInstance libraryItemName="${item}" symbolType="movie_clip" centerPoint3DX="${x}" centerPoint3DY="${y}"><matrix><a>1</a></matrix>${script(as2)}</DOMSymbolInstance>`;
}

/** 子弹的内联脚本：种类可以不写（写了才走词表），区域判定靠 区域定位area 赋值认。 */
function bulletScript(kind: string | undefined, pellets: number, area = false): string {
  return [
    ...(kind === undefined ? [] : [`子弹属性.子弹种类 = "${kind}";`]),
    `子弹属性.霰弹值 = ${pellets};`,
    ...(area ? ["子弹属性.区域定位area = this.area;"] : []),
    "子弹属性.子弹威力 = _parent._parent.空手攻击力;",
  ].join(" ");
}

/** 一颗 2 段近战子弹，起手后摆出来。 */
function meleeHit(): string {
  return `<elements>${instance("子弹/近战子弹", "子弹属性.霰弹值 = 2; 子弹属性.子弹威力 = _parent._parent.空手攻击力;")}</elements>`;
}

/** 三段连招，每段一颗 2 段子弹、起手后 2 帧出弹；`withJumpLayer` 决定是否写那段变量跳转。 */
function comboSymbol(withJumpLayer = true, prefix = ""): string {
  return symbol("",
    layer("标签", [
      frame(0, 10, "", `${prefix}1连招`),
      frame(10, 10, "", `${prefix}2连招`),
      frame(20, 10, "", `${prefix}3连招`),
    ]),
    ...(withJumpLayer ? [layer("代码", [frame(0, 30, script("帧名 = _parent.兵器动作类型 + 招式序号; gotoAndPlay(帧名);"))])] : []),
    layer("子弹", [frame(2, 1, meleeHit()), frame(12, 1, meleeHit()), frame(22, 1, meleeHit())]),
  );
}

/** 宿主只按名跳到 受创 状态，招式段 大风雪 靠顺播打到 —— 状态跳转不该把整份动画判成废弃。 */
function stateSymbol(): string {
  return symbol("",
    layer("标签", [frame(0, 10, "", "受创"), frame(10, 10, "", "大风雪")]),
    layer("子弹", [frame(12, 1, meleeHit())]),
  );
}

/** 击倒/倒地 段里击飞逻辑的写法变体；缺段 = 容器连这个状态标签都没有。 */
type AirborneStyle = "函数" | "内联" | "元件名" | "行注释" | "块注释" | "帧脚本" | "无" | "缺段";

/** 被击 段的摆法；解析不到 = 摆了个库里没有的元件名。 */
type HitStyle = "摆" | "不摆" | "缺段" | "解析不到";

interface ArmorOptions {
  knockdown?: AirborneStyle;
  lying?: AirborneStyle;
  hit?: HitStyle;
  /** 受创动画里每发击退的帧数（命名帧到 动画完毕 的持续）。 */
  spans?: number[];
  /** 受创动画一个命名帧都没有，击退时长整段量。 */
  unnamed?: boolean;
  /** 受创动画里没有 动画完毕 调用，击退时长退到时间轴末尾。 */
  noOverCall?: boolean;
  hitLabel?: string;
  lyingLabel?: string;
  rules?: ArmorRules;
}

function armorFixture(options: ArmorOptions): MonsterArmorMeasure {
  const repo = writeArmorRepo(options);
  const measure = measureMonsterAttack(
    {
      spritename: "敌人-霸体怪",
      panelAtkMin: 100,
      panelAtkMax: 100,
      segmentWindowFrames: WINDOW,
      ...(options.rules === undefined ? {} : { armorRules: options.rules }),
    },
    loadAssetSources(repo),
    repo,
  );
  const armor = measure.armor;
  if (armor === undefined) throw new Error("霸体包没量到容器");
  return armor;
}

/**
 * 霸体包：容器状态层铺 空手站立/近战/被击/击倒/倒地/血腥死 六段，
 * 被击 段摆受创动画（命名帧 a0/a1 各带一发击退时长），击倒与倒地 段各摆一份击飞写法。
 */
function writeArmorRepo(options: ArmorOptions): string {
  const hit = options.hit ?? "摆";
  const knockdown = options.knockdown ?? "函数";
  const lying = options.lying ?? "函数";
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-armor-"));
  const library = "arts/霸体包/LIBRARY";

  write(repo, "data/items/asset_source_map.xml", `<xml>
  <library>
    <asset id="敌人-霸体怪" swf="arts/霸体包.swf" symbolName="霸体/代码层/敌人-霸体怪" />
  </library>
</xml>
`);
  write(repo, "arts/霸体包/DOMDocument.xml", `<DOMDocument version="2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>\n`);

  const states = [
    frame(0, 1, "", "空手站立"),
    frame(1, 10, "", "近战"),
    ...(hit === "缺段" ? [] : [frame(11, 8, "", options.hitLabel ?? "被击")]),
    ...(knockdown === "缺段" ? [] : [frame(19, 8, "", "击倒")]),
    ...(lying === "缺段" ? [] : [frame(27, 8, "", options.lyingLabel ?? "倒地")]),
    frame(35, 1, "", "血腥死"),
  ];
  const actions = [
    hit === "摆" ? frame(11, 1, `<elements>${instance("霸体/受创动画")}</elements>`) : undefined,
    hit === "解析不到" ? frame(11, 1, `<elements>${instance("霸体/库里没有的动画")}</elements>`) : undefined,
    airborneFrame(19, "击倒", knockdown),
    airborneFrame(27, "倒地", lying),
  ].filter((entry): entry is string => entry !== undefined);

  write(repo, `${library}/霸体/代码层/敌人-霸体怪.xml`, symbol('linkageIdentifier="敌人-霸体怪"',
    layer("状态", states),
    layer("代码", [frame(0, 1, script("攻击欲望 = 3;"))]),
    layer("动作", actions),
  ));
  write(repo, `${library}/霸体/受创动画.xml`, hurtSymbol(options.spans ?? [14, 10], options));
  for (const item of ["击倒动作", "倒地动作", "击飞特效"]) {
    write(repo, `${library}/霸体/${item}.xml`, symbol("", layer("外形", [frame(0, 1, "")])));
  }

  return repo;
}

/** 击倒/倒地 段那一份击飞写法：统一函数、没统一的内联浮空、只摆元件、注释里的废弃代码、帧脚本、摆了但没逻辑。 */
function airborneFrame(index: number, state: "击倒" | "倒地", style: AirborneStyle): string | undefined {
  if (style === "缺段") return undefined;
  if (style === "元件名") return frame(index, 1, `<elements>${instance("霸体/击飞特效")}</elements>`);
  // 帧打在帧上而这一帧没摆元件：制作组的判据要「有代码而且要有元件」，这种不算击飞逻辑
  if (style === "帧脚本") return frame(index, 1, `${script(CALLBACK[state])}<elements/>`);
  const as2 =
    style === "函数"
      ? CALLBACK[state]
      : style === "内联"
        ? INLINE[state]
        : style === "行注释"
          ? `// ${INLINE[state]}`
          : style === "块注释"
            ? `/* onClipEvent(load){\n${INLINE[state]}\n} */`
            : "";
  return frame(index, 1, `<elements>${instance(`霸体/${state}动作`, as2)}</elements>`);
}

const CALLBACK: Record<"击倒" | "倒地", string> = { 击倒: "_parent.击飞浮空();", 倒地: "_parent.击飞倒地();" };
const INLINE: Record<"击倒" | "倒地", string> = {
  击倒: "_parent.浮空 = true; _parent.浮空速度 = 12;",
  倒地: "_parent.倒地 = true; _parent.落地帧 = 30;",
};

/** 被击 段那份受创动画：一发击退做成一个命名帧 a{i}，收口帧打 动画完毕。 */
function hurtSymbol(spans: number[], options: ArmorOptions): string {
  if (options.unnamed === true) {
    const first = spans[0] ?? 1;
    return symbol("",
      layer("外形", [frame(0, first, "")]),
      ...(options.noOverCall === true ? [] : [layer("结束", [frame(first, 1, script("_parent.动画完毕();"))])]),
    );
  }
  const starts: number[] = [];
  const stops: number[] = [];
  let cursor = 0;
  for (const span of spans) {
    starts.push(cursor);
    cursor += span;
    stops.push(cursor);
    cursor += 1;
  }
  return symbol("",
    layer("外形", starts.map((start, index) => frame(start, stops[index] ?? start, "", `a${index}`))),
    ...(options.noOverCall === true ? [] : [layer("结束", stops.map((stop) => frame(stop, 1, script("_parent.动画完毕();"))))]),
  );
}

function symbol(extraAttributes: string, ...layers: string[]): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<DOMSymbolItem xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" name="Symbol" symbolType="movie_clip" ${extraAttributes}>
<timeline><layers>
${layers.join("\n")}
</layers></timeline>
</DOMSymbolItem>
`;
}

function layer(name: string, frames: string[]): string {
  return `<DOMLayer name="${name}" color="#00ffff">\n<frames>\n${frames.join("\n")}\n</frames>\n</DOMLayer>`;
}

function frame(index: number, duration: number, body: string, label?: string): string {
  const attrs = label === undefined ? `duration="${duration}"` : `duration="${duration}" labelType="name" name="${label}"`;
  return `<DOMFrame index="${index}" ${attrs}>${body}</DOMFrame>`;
}

function instance(item: string, as2 = ""): string {
  const action = as2 === "" ? "" : script(as2);
  return `<DOMSymbolInstance libraryItemName="${item}" symbolType="movie_clip"><matrix><a>1</a></matrix>${action}</DOMSymbolInstance>`;
}

function script(as2: string): string {
  return `<Actionscript><script><![CDATA[${as2};]]></script></Actionscript>`;
}

function write(root: string, relPath: string, text: string): void {
  const file = path.join(root, ...relPath.split("/"));
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text.replace(/^/, ""), "utf8");
}
