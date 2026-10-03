import { describe, expect, it } from "vitest";
import { computeMonsterRow } from "../../src/formulas/monsters.js";
import type { MonsterInput } from "../../src/formulas/monsters.js";
import {
  MONSTER_COEFFICIENT_DEFAULTS,
  defaultTierCandidates,
  scanTierFactor,
  snapMonsterCoefficient,
  solveMonsterCoefficients,
  speedBandOf,
  speedFactorFromMoveSpeed,
  superArmorDecimalFromTenacity,
  superArmorHpFactor,
} from "../../src/formulas/monster-solve.js";

/** 大学.xml 体育老师的真实标注，用作闭环基准。 */
const PHYSICS_TEACHER: MonsterInput = {
  stage: 4,
  tierFactor: 12,
  growthFactor: 1,
  atkSpeedFactor: 5,
  atkMultiplier: 1.5,
  segmentFactor: 2.5,
  speedFactor: 2.5,
  highAtkFactor: 1,
  superArmorFactor: 4,
  highDefFactor: 2.5,
};

const COEFFICIENT_NAMES = Object.keys(MONSTER_COEFFICIENT_DEFAULTS) as Array<keyof MonsterInput>;

describe("monster solve", () => {
  it("用面板加移动速度档次反推成长/速度/血防系数，误差在几个百分点内", () => {
    const panel = computeMonsterRow(PHYSICS_TEACHER);
    const result = solveMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      tierFactor: PHYSICS_TEACHER.tierFactor,
      panel,
      // 体育老师实操是 2.5，档次读法只能给整数档：50~70 的均值 60 读成中档 2（现网这类跨档怪多标 2）。
      moveSpeed: { min: 50, max: 70 },
    });

    expect(result.coefficients.growthFactor).toBeCloseTo(1, 2);
    expect(result.coefficients.speedFactor).toBeCloseTo(2, 2);
    // 差的半档不会被 J/L 吸收，只能由 HP 的霸体乘子承担，所以 J/L 偏差被放大。
    expect(result.coefficients.highAtkFactor).toBeGreaterThan(0.9);
    expect(result.coefficients.highAtkFactor).toBeLessThan(1.4);
    expect(result.coefficients.highDefFactor).toBeGreaterThan(2.4);
    expect(result.coefficients.highDefFactor).toBeLessThan(3.1);
    expect(result.notes.join("\n")).toContain("反推误差会被放大");
    for (const residual of result.residuals) {
      if (residual.field === "atkMin" || residual.field === "atkMax") continue;
      expect(residual.relativeError).toBeLessThan(0.15);
    }
  });

  it("速度_min/max 跨档时给出两档中点候选，体育老师的 2.5 就在其中", () => {
    const panel = computeMonsterRow(PHYSICS_TEACHER);
    const result = solveMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      tierFactor: PHYSICS_TEACHER.tierFactor,
      panel,
      moveSpeed: { min: 50, max: 75 },
    });
    const est = result.estimates.find((e) => e.name === "speedFactor");

    expect(est?.confidence).toBe("definition-band");
    expect(est?.basis).toContain("跨档可取两档中点 2.5");
    expect(result.coefficients.speedFactor).toBe(3);
  });

  it("速度系数按定义取自移动速度，防御MAX 反推不符时只报警不覆盖", () => {
    const panel = computeMonsterRow(PHYSICS_TEACHER);
    const { speedFactor: _speed, ...known } = PHYSICS_TEACHER;
    const result = solveMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      tierFactor: PHYSICS_TEACHER.tierFactor,
      panel,
      known,
      // 面板的防御MAX 指向 2.5 附近，但 15~25 的定义档是 1：定义优先，差距超过一档才报警。
      moveSpeed: { min: 15, max: 25 },
    });

    expect(result.coefficients.speedFactor).toBe(1);
    expect(result.estimates.find((entry) => entry.name === "speedFactor")?.confidence).toBe("definition-band");
    expect(result.notes.join("\n")).toContain("相差 1.5 档");
  });

  it("定义档与面板反推只差半档时也报警，但取值仍走定义档", () => {
    const panel = computeMonsterRow(PHYSICS_TEACHER);
    const { speedFactor: _speed, ...known } = PHYSICS_TEACHER;
    const result = solveMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      tierFactor: PHYSICS_TEACHER.tierFactor,
      panel,
      known,
      // 体育老师这类实操半档：50~70 的均值压 60 归中档 2，面板反推 2.5。
      moveSpeed: { min: 50, max: 70 },
    });

    expect(result.coefficients.speedFactor).toBe(2);
    expect(result.notes.join("\n")).toContain("相差 0.5 档");
  });

  it("查不到移动速度区间时，防御MAX 闭式解仍把速度系数解回真值", () => {
    const panel = computeMonsterRow(PHYSICS_TEACHER);
    const { speedFactor: _speed, ...known } = PHYSICS_TEACHER;
    const result = solveMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      tierFactor: PHYSICS_TEACHER.tierFactor,
      panel,
      known,
    });

    expect(result.coefficients.speedFactor).toBeCloseTo(PHYSICS_TEACHER.speedFactor, 4);
    expect(result.estimates.find((entry) => entry.name === "speedFactor")?.confidence).toBe("closed-form");
    expect(result.residuals.find((entry) => entry.field === "defMax")?.relativeError).toBeLessThan(0.001);
  });

  it("人工给定的速度系数与移动速度定义档差一档以上时报警", () => {
    const panel = computeMonsterRow(PHYSICS_TEACHER);
    const result = solveMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      tierFactor: PHYSICS_TEACHER.tierFactor,
      panel,
      // 体育老师标注 2.5，这里把移动速度换成慢档区间，模拟标识与速度数值脱节。
      known: { speedFactor: PHYSICS_TEACHER.speedFactor },
      moveSpeed: { min: 15, max: 25 },
    });

    expect(result.coefficients.speedFactor).toBe(2.5);
    expect(result.notes.join("\n")).toContain("人工给定 2.5");
  });

  it("给定攻击节奏三系数后复现整张面板", () => {
    const panel = computeMonsterRow(PHYSICS_TEACHER);
    const result = solveMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      tierFactor: PHYSICS_TEACHER.tierFactor,
      panel,
      known: {
        speedFactor: PHYSICS_TEACHER.speedFactor,
        atkSpeedFactor: PHYSICS_TEACHER.atkSpeedFactor,
        atkMultiplier: PHYSICS_TEACHER.atkMultiplier,
        segmentFactor: PHYSICS_TEACHER.segmentFactor,
      },
    });

    for (const residual of result.residuals) {
      expect(residual.relativeError).toBeLessThan(0.01);
    }
    expect(result.coefficients.growthFactor).toBeCloseTo(1, 3);
    expect(result.coefficients.highAtkFactor).toBeCloseTo(1, 3);
  });

  it("攻击倍率/段数系数/攻速系数只以乘积进入面板，恒列为未定并给出乘积目标", () => {
    const panel = computeMonsterRow(PHYSICS_TEACHER);
    const result = solveMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      tierFactor: PHYSICS_TEACHER.tierFactor,
      panel,
      moveSpeed: { min: 50, max: 75 },
    });

    expect(result.unresolved).toEqual(expect.arrayContaining(["atkSpeedFactor", "atkMultiplier", "segmentFactor"]));
    expect(result.attackTempoTarget).toBeGreaterThan(0);

    // 不变量：乘积目标与解出的 J、I、E 组合后必须精确复现空手攻击MIN。
    const { stage: C, tierFactor: D, growthFactor: E, highAtkFactor: J, speedFactor: I } = result.coefficients;
    const recomputed =
      5 + (C * D * 9 * 1.25 ** (1 - E) * J) / (result.attackTempoTarget! * 1.1 ** (I - 2) * Math.sqrt(E));
    expect(recomputed).toBeCloseTo(panel.atkMin, 3);
  });

  it("档次系数缺失时拒绝求解，阶段非法同样报错", () => {
    expect(() => solveMonsterCoefficients({ stage: 4, tierFactor: 0, panel: { atkMin: 100 } })).toThrow();
    expect(() => solveMonsterCoefficients({ stage: Number.NaN, tierFactor: 3, panel: {} })).toThrow();
  });

  it("成长系数多通道分歧时提示阶段或档次系数可疑", () => {
    const panel = computeMonsterRow(PHYSICS_TEACHER);
    const result = solveMonsterCoefficients({
      stage: 3,
      tierFactor: 12,
      panel,
      moveSpeed: { min: 50, max: 75 },
    });
    expect(result.notes.join("\n")).toContain("阶段或档次系数可疑");
  });

  it("面板字段残缺时只解可解部分并说明缺什么", () => {
    const result = solveMonsterCoefficients({
      stage: 2,
      tierFactor: 5,
      panel: { atkMin: 60, atkMax: 210 },
    });
    expect(result.coefficients.growthFactor).toBeGreaterThan(0);
    expect(result.notes.join("\n")).toContain("缺少成对防御字段");
    expect(result.unresolved).toEqual(expect.arrayContaining(["speedFactor", "superArmorFactor", "segmentFactor"]));
  });

  it("HP 落在公式下限时不使用霸体残差", () => {
    const result = solveMonsterCoefficients({
      stage: 1,
      tierFactor: 1,
      panel: { hpMin: 40, hpMax: 90, defMin: 60, defMax: 240 },
      moveSpeed: { min: 20, max: 30 },
    });
    expect(result.notes.join("\n")).toContain("HP 触及公式下限");
    expect(result.unresolved).toContain("superArmorFactor");
  });

  describe("workbook rules", () => {
    it("速度档次按 D15 的 10-40 / 40-60 / 60-90 分段，上限归本档", () => {
      expect(speedBandOf(39.9)).toBe(1);
      expect(speedBandOf(40)).toBe(1);
      expect(speedBandOf(40.1)).toBe(2);
      expect(speedBandOf(60)).toBe(2);
      expect(speedBandOf(60.1)).toBe(3);
    });

    it("速度系数取速度_min/max 均值档次，跨档另给两档中点", () => {
      // 均值 55 → 中档；45~65 跨中/快，中点 2.5 是体育老师这类跨档怪的实操写法。
      expect(speedFactorFromMoveSpeed(45, 65)).toEqual({ value: 2, upper: 2.5 });
      expect(speedFactorFromMoveSpeed(20, 35)).toEqual({ value: 1, upper: 1 });
      expect(speedFactorFromMoveSpeed(65, 90)).toEqual({ value: 3, upper: 3 });
      // 大学军校生这类 50~70 的现网标注是 2，均值正好压在 60 边界上，所以边界归中档。
      expect(speedFactorFromMoveSpeed(50, 70)).toEqual({ value: 2, upper: 2.5 });
      expect(speedFactorFromMoveSpeed(15, 25)).toEqual({ value: 1, upper: 1 });
    });

    it("霸体系数小数位每 20 点韧性加 0.1，上限 0.5", () => {
      expect(superArmorDecimalFromTenacity(20)).toBe(0);
      expect(superArmorDecimalFromTenacity(35)).toBeCloseTo(0.1, 10);
      expect(superArmorDecimalFromTenacity(200)).toBe(0.5);
    });

    it("HP 霸体乘子只在 Excel 的两个分支上生效", () => {
      expect(superArmorHpFactor(9, 3)).toBe(1);
      expect(superArmorHpFactor(8, 4)).toBeCloseTo(1 - 4 / 50, 10);
      expect(superArmorHpFactor(13, 4)).toBeCloseTo(1 + 1 / 4, 10);
      expect(superArmorHpFactor(13, 5)).toBe(1);
    });

    it("连续解按 整数 → 半档 → 十分档 归档，整数够用就不降档", () => {
      expect(snapMonsterCoefficient(2.014)).toEqual({ value: 2, grid: "integer" });
      expect(snapMonsterCoefficient(1.999)).toEqual({ value: 2, grid: "integer" });
      expect(snapMonsterCoefficient(2.5)).toEqual({ value: 2.5, grid: "half" });
      // 闪流步兵的闭式解 1.840 离整数 2 与半档 2.0 都超容差，只能落到十分档。
      expect(snapMonsterCoefficient(1.84)).toEqual({ value: 1.8, grid: "tenth" });
      expect(snapMonsterCoefficient(0.9)).toEqual({ value: 0.9, grid: "tenth" });
      expect(snapMonsterCoefficient(1.25)).toEqual({ value: 1.3, grid: "tenth" });
    });
  });

  it("每个系数的反推都带依据说明", () => {
    const panel = computeMonsterRow(PHYSICS_TEACHER);
    const result = solveMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      tierFactor: PHYSICS_TEACHER.tierFactor,
      panel,
      moveSpeed: { min: 50, max: 75 },
    });
    for (const estimate of result.estimates) {
      expect(estimate.basis.length).toBeGreaterThan(0);
      expect(COEFFICIENT_NAMES.concat(["stage", "tierFactor"])).toContain(estimate.name);
    }
  });
});

describe("monster tier scan", () => {
  it("其余标识齐备时能把档次系数排回真值", () => {
    const panel = computeMonsterRow(PHYSICS_TEACHER);
    const { tierFactor: _tier, ...known } = PHYSICS_TEACHER;
    const ranked = scanTierFactor({ stage: PHYSICS_TEACHER.stage, panel, known });

    expect(ranked[0]?.tierFactor).toBe(12);
    expect(ranked[0]?.fitError).toBeLessThan(0.05);
  });

  it("只给面板时档次排序不可靠，只能当人工定档的参考", () => {
    const panel = computeMonsterRow(PHYSICS_TEACHER);
    const blind = scanTierFactor({ stage: PHYSICS_TEACHER.stage, panel, moveSpeed: { min: 50, max: 75 } });
    const { tierFactor: _tier, ...known } = PHYSICS_TEACHER;
    const withFlags = scanTierFactor({ stage: PHYSICS_TEACHER.stage, panel, known });

    expect(blind[0]?.tierFactor).not.toBe(12);
    expect(blind[0]!.fitError).toBeGreaterThan(withFlags[0]!.fitError * 3);
  });

  it("候选网格覆盖 Excel 档次表的小档与 boss 档", () => {
    const candidates = defaultTierCandidates();
    expect(candidates[0]).toBe(1);
    expect(candidates).toContain(1.5);
    expect(candidates.at(-1)).toBe(25);
  });
});
