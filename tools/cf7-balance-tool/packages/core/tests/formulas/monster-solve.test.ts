import { describe, expect, it } from "vitest";
import { computeMonsterRow } from "../../src/formulas/monsters.js";
import type { MonsterInput } from "../../src/formulas/monsters.js";
import {
  MONSTER_COEFFICIENT_DEFAULTS,
  MONSTER_FIT_FREE_COEFFICIENTS,
  MONSTER_FIT_PANEL_FIELDS,
  MONSTER_OBSERVED_COEFFICIENTS,
  fitMonsterCoefficients,
  snapMonsterCoefficient,
  speedBandOf,
  speedFactorFromMoveSpeed,
  superArmorDecimalFromTenacity,
  superArmorHpFactor,
  tierFitCandidates,
} from "../../src/formulas/monster-solve.js";
import type { CoefficientConfidence, MonsterCoefficientName } from "../../src/formulas/monster-solve.js";

/** 大学.xml 体育老师的真实标注，四元联立用它做闭环基准。 */
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

/**
 * 观测五项：攻速系数/攻击倍率/段数系数 来自攻击动作实测，霸体系数 来自击退与击飞元件观测，
 * 速度系数 来自移动速度定义档或标识。它们一律钉住，不参与面板反推。
 */
function observedOf(input: MonsterInput): Partial<MonsterInput> {
  return {
    atkSpeedFactor: input.atkSpeedFactor,
    atkMultiplier: input.atkMultiplier,
    segmentFactor: input.segmentFactor,
    superArmorFactor: input.superArmorFactor,
    speedFactor: input.speedFactor,
  };
}

function estimateOf(result: ReturnType<typeof fitMonsterCoefficients>, name: MonsterCoefficientName) {
  return result.estimates.find((entry) => entry.name === name);
}

describe("monster panel fit", () => {
  it("只钉观测五项时，四元联立能把档次/成长/血防系数解回标注", () => {
    const result = fitMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      panel: computeMonsterRow(PHYSICS_TEACHER),
      known: observedOf(PHYSICS_TEACHER),
    });

    expect(result.freeCoefficients).toEqual(MONSTER_FIT_FREE_COEFFICIENTS);
    expect(result.equations).toBe(MONSTER_FIT_PANEL_FIELDS.length);
    expect(result.coefficients.tierFactor).toBe(12);
    expect(result.coefficients.growthFactor).toBeCloseTo(1, 1);
    expect(result.coefficients.highAtkFactor).toBeCloseTo(1, 1);
    expect(result.coefficients.highDefFactor).toBeCloseTo(2.5, 1);
    expect(result.fitError).toBeLessThan(0.05);
    for (const residual of result.residuals) expect(residual.relativeError).toBeLessThan(0.1);
  });

  it("人工钉住档次系数后它退出搜索，只解其余三个自由量", () => {
    const result = fitMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      panel: computeMonsterRow(PHYSICS_TEACHER),
      known: { ...observedOf(PHYSICS_TEACHER), tierFactor: 9 },
    });

    expect(result.coefficients.tierFactor).toBe(9);
    expect(result.freeCoefficients).toEqual(["growthFactor", "highAtkFactor", "highDefFactor"]);
    expect(estimateOf(result, "tierFactor")?.confidence).toBe("given");
  });

  it("经验两项不进误差：面板经验改十倍，六个系数与误差值都不动", () => {
    const panel = computeMonsterRow(PHYSICS_TEACHER);
    const known = observedOf(PHYSICS_TEACHER);
    const baseline = fitMonsterCoefficients({ stage: PHYSICS_TEACHER.stage, panel, known });
    const withExp = fitMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      panel: { ...panel, expMin: panel.expMin * 10, expMax: panel.expMax * 10 },
      known,
    });

    expect(withExp.coefficients).toEqual(baseline.coefficients);
    expect(withExp.fitError).toBeCloseTo(baseline.fitError, 10);
    // 经验只对照：面板读到多少就报多少，由人工决定要不要按标识重算
    expect(withExp.expResiduals.map((entry) => entry.observed).sort()).toEqual([panel.expMin * 10, panel.expMax * 10].sort());
    expect(withExp.expResiduals.every((entry) => entry.relativeError > 0.5)).toBe(true);
  });

  it("面板项数少于自由量时报警解不唯一", () => {
    const result = fitMonsterCoefficients({ stage: 2, panel: { atkMin: 60, atkMax: 210 }, known: observedOf(PHYSICS_TEACHER) });

    expect(result.equations).toBe(2);
    expect(result.freeCoefficients.length).toBe(4);
    expect(result.notes.join("\n")).toContain("方程数少于自由量，解不唯一");
  });

  it("缺观测的攻速/倍率/段数按工作簿默认参与拟合，并记进未定清单让写盘侧跳过", () => {
    const result = fitMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      panel: computeMonsterRow(PHYSICS_TEACHER),
      known: { speedFactor: PHYSICS_TEACHER.speedFactor, superArmorFactor: PHYSICS_TEACHER.superArmorFactor },
    });

    expect(result.unresolved).toEqual(expect.arrayContaining(["atkSpeedFactor", "atkMultiplier", "segmentFactor"]));
    for (const name of result.unresolved) {
      expect(result.coefficients[name]).toBe(MONSTER_COEFFICIENT_DEFAULTS[name]);
    }
    expect(result.notes.join("\n")).toContain("只以乘积进入空手攻击，面板定不了它们");
  });

  it("反推值超出参考区间时按实算登记，不夹紧", () => {
    const input: MonsterInput = { ...PHYSICS_TEACHER, highAtkFactor: 5 };
    const result = fitMonsterCoefficients({
      stage: input.stage,
      panel: computeMonsterRow(input),
      known: { ...observedOf(input), tierFactor: input.tierFactor },
    });

    expect(result.coefficients.highAtkFactor).toBeGreaterThan(4.5);
    expect(result.outOfRange).toEqual([
      expect.objectContaining({ name: "highAtkFactor", range: [0.5, 2] }),
    ]);
    // 区间只用来列待人工复核的名单，夹紧才会把面板误差伪装成反推误差
    expect(result.fitError).toBeLessThan(0.05);
  });

  it("档次解贴住初始网格上界时按块加长继续搜：参考区间不是上限", () => {
    const known = observedOf(PHYSICS_TEACHER);
    // 面板按 档次系数 60 正算，旧网格只能在 25 顶格收口；放开后应解回 60 附近并登记越界。
    const aboveTop = fitMonsterCoefficients({
      stage: 15,
      panel: computeMonsterRow({ ...PHYSICS_TEACHER, stage: 15, tierFactor: 60 }),
      known,
    });
    expect(aboveTop.coefficients.tierFactor).toBeGreaterThan(25);
    expect(Math.abs(aboveTop.coefficients.tierFactor - 60)).toBeLessThanOrEqual(3);
    expect(aboveTop.fitError).toBeLessThan(0.1);
    expect(aboveTop.outOfRange).toEqual([
      expect.objectContaining({ name: "tierFactor", range: [1, 25] }),
    ]);
    expect(aboveTop.notes.join("\n")).toContain("高于参考区间上限");
    expect(aboveTop.notes.join("\n")).not.toContain("停在搜索网格上界");
  });

  it("面板要的非正数顶给人工判断，档次解在参考区间下沿也只报警不夹紧", () => {
    const panel = computeMonsterRow(PHYSICS_TEACHER);
    const broken = fitMonsterCoefficients({
      stage: 2,
      panel: { ...panel, atkMin: -6, hpMin: -83 },
      known: observedOf(PHYSICS_TEACHER),
    });
    expect(broken.notes.join("\n")).toContain("不是正数");
    expect(broken.notes.join("\n")).toContain("低于参考区间下限");
  });

  it("阶段非法直接报错，没有面板的行不产出解", () => {
    expect(() => fitMonsterCoefficients({ stage: 0, panel: { atkMin: 100 } })).toThrow();
    const empty = fitMonsterCoefficients({ stage: 4, panel: {}, known: observedOf(PHYSICS_TEACHER) });
    expect(empty.equations).toBe(0);
    expect(empty.residuals).toEqual([]);
  });

  it("除阶段外每个系数都带来源标签，标签只用给定/定义档/面板反推三种", () => {
    const result = fitMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      panel: computeMonsterRow(PHYSICS_TEACHER),
      known: { ...observedOf(PHYSICS_TEACHER), tierFactor: PHYSICS_TEACHER.tierFactor },
    });
    const expected = [...Object.keys(MONSTER_COEFFICIENT_DEFAULTS), "tierFactor"] as MonsterCoefficientName[];

    expect(result.estimates.map((entry) => entry.name).sort()).toEqual([...expected].sort());
    for (const estimate of result.estimates) {
      expect(["given", "definition-band", "panel-fit"]).toContain(estimate.confidence as CoefficientConfidence);
      expect(estimate.basis.length).toBeGreaterThan(0);
    }
    for (const name of MONSTER_OBSERVED_COEFFICIENTS) expect(estimateOf(result, name)?.confidence).toBe("given");
  });
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

  it("移动速度区间只定取值，面板反推不覆盖定义档", () => {
    const result = fitMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      panel: computeMonsterRow(PHYSICS_TEACHER),
      known: { ...observedOf({ ...PHYSICS_TEACHER, speedFactor: 1 }) },
      // 观测值 1 已经在盘上，定义档不再插手：钉住的系数优先级高于移动速度。
      moveSpeed: { min: 50, max: 75 },
    });

    expect(result.coefficients.speedFactor).toBe(1);
    expect(estimateOf(result, "speedFactor")?.confidence).toBe("given");
  });

  it("没有标识的速度系数才走移动速度定义档", () => {
    const result = fitMonsterCoefficients({
      stage: PHYSICS_TEACHER.stage,
      panel: computeMonsterRow(PHYSICS_TEACHER),
      known: { atkSpeedFactor: 5, atkMultiplier: 1.5, segmentFactor: 2.5, superArmorFactor: 4 },
      moveSpeed: { min: 50, max: 75 },
    });

    expect(result.coefficients.speedFactor).toBe(3);
    expect(estimateOf(result, "speedFactor")?.confidence).toBe("definition-band");
    expect(estimateOf(result, "speedFactor")?.basis).toContain("跨档可取两档中点 2.5");
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

  it("取值词表没有 0 档：再小的解也落到 0.1，免得把面板算成无穷大", () => {
    expect(snapMonsterCoefficient(0.0395)).toEqual({ value: 0.1, grid: "tenth" });
    expect(snapMonsterCoefficient(0.0602)).toEqual({ value: 0.1, grid: "tenth" });
    expect(snapMonsterCoefficient(0)).toEqual({ value: 0.1, grid: "tenth" });
  });

  it("档次搜索网格下到取值词表下界 0.1、初始上界 25，步距是词表的十分档/半档/整数档", () => {
    const candidates = tierFitCandidates();
    expect(candidates[0]).toBe(0.1);
    expect(candidates).toContain(0.4);
    expect(candidates).toContain(1.5);
    expect(candidates).toContain(9.5);
    expect(candidates.at(-1)).toBe(25);
    expect(candidates.filter((value) => value > 10)).toEqual(candidates.filter((value) => value > 10).map(Math.round));
  });

  it("面板要得比最低档还弱时，档次跟着下探到 1 以下并报警，不夹回 1", () => {
    const weak = fitMonsterCoefficients({
      stage: 2,
      panel: computeMonsterRow({ ...PHYSICS_TEACHER, stage: 2, tierFactor: 0.4 }),
      known: observedOf(PHYSICS_TEACHER),
    });
    expect(weak.coefficients.tierFactor).toBeLessThan(1);
    expect(weak.fitError).toBeLessThan(0.1);
    expect(weak.outOfRange).toEqual([expect.objectContaining({ name: "tierFactor", range: [1, 25] })]);
    expect(weak.notes.join("\n")).toContain("低于参考区间下限");
  });
});
