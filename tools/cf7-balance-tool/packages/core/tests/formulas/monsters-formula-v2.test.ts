import { describe, expect, it } from "vitest";

import {
  MONSTER_DEF_TRANSFER_EXPONENT,
  MONSTER_FORMULA_VERSION,
  MONSTER_PHYSICAL_EHP_EXPONENT,
  computeMonsterRow,
  monsterMixedEhp,
  monsterPhysicalEhp,
} from "../../src/formulas/monsters.js";
import type { MonsterInput } from "../../src/formulas/monsters.js";

/**
 * v2 口径的硬约束：
 * - 默认口径是 v2；
 * - L=1 时与 v1 完全一致（切公式不改动任何 L=1 的怪）；
 * - 物理等效血量只按 m=L^γ 变化，与单位自身防御基数无关；
 * - 防御不会被压到非正数，血量不破地板；
 * - 7:2:1（法抗 30）下，L=10 的综合等效血量低于 L=1。
 */
const BASE: MonsterInput = {
  stage: 2,
  tierFactor: 1.5,
  growthFactor: 1,
  atkSpeedFactor: 3,
  atkMultiplier: 1,
  segmentFactor: 3,
  speedFactor: 1,
  highAtkFactor: 1,
  superArmorFactor: 1,
  highDefFactor: 1,
};

const CASES: Array<{ name: string; input: MonsterInput }> = [
  { name: "小型小怪", input: { ...BASE, tierFactor: 1 } },
  { name: "中型小怪", input: { ...BASE, tierFactor: 1.5 } },
  { name: "精英", input: { ...BASE, tierFactor: 3, growthFactor: 1.2, highAtkFactor: 1.2 } },
  { name: "boss", input: { ...BASE, stage: 4, tierFactor: 13, growthFactor: 1.5, superArmorFactor: 3 } },
  { name: "高L越界", input: { ...BASE, stage: 3, tierFactor: 20, growthFactor: 1.5, superArmorFactor: 4, highDefFactor: 34 } },
];

describe("monsters formula v2", () => {
  it("默认口径是 v2", () => {
    expect(MONSTER_FORMULA_VERSION).toBe("v2");
    expect(MONSTER_DEF_TRANSFER_EXPONENT).toBe(0.5);
    expect(MONSTER_PHYSICAL_EHP_EXPONENT).toBe(0.05);
  });

  it("L=1 时与 v1 逐字段一致", () => {
    for (const { input } of CASES) {
      const v1 = computeMonsterRow({ ...input, highDefFactor: 1 }, "v1");
      const v2 = computeMonsterRow({ ...input, highDefFactor: 1 }, "v2");
      for (const key of Object.keys(v1) as Array<keyof typeof v1>) {
        expect(v2[key], `${key}`).toBeCloseTo(v1[key], 9);
      }
    }
  });

  it("物理 EHP 只随 L^γ 变化，与基础防御无关", () => {
    for (const { input } of CASES) {
      const base = computeMonsterRow({ ...input, highDefFactor: 1 }, "v2");
      const ehpMin0 = monsterPhysicalEhp(base.hpMin, base.defMin);
      const ehpMax0 = monsterPhysicalEhp(base.hpMax, base.defMax);
      for (const L of [0.1, 0.3, 2, 5, 10]) {
        const row = computeMonsterRow({ ...input, highDefFactor: L }, "v2");
        const expected = Math.pow(L, MONSTER_PHYSICAL_EHP_EXPONENT);
        expect(monsterPhysicalEhp(row.hpMin, row.defMin) / ehpMin0).toBeCloseTo(expected, 6);
        expect(monsterPhysicalEhp(row.hpMax, row.defMax) / ehpMax0).toBeCloseTo(expected, 6);
      }
    }
  });

  it("防御不为负、血量不破地板，且 0.1 端平滑", () => {
    for (const { input } of CASES) {
      const low = computeMonsterRow({ ...input, highDefFactor: 0.1 }, "v2");
      expect(low.defMin).toBeGreaterThan(0);
      expect(low.defMax).toBeGreaterThan(0);
      expect(low.hpMin).toBeGreaterThanOrEqual(50);
      expect(low.hpMax).toBeGreaterThanOrEqual(100);
      const high = computeMonsterRow({ ...input, highDefFactor: 10 }, "v2");
      expect(high.defMin).toBeGreaterThan(0);
      expect(high.hpMin).toBeGreaterThanOrEqual(50);
    }
  });

  it("7:2:1 下高 L 的综合等效血量低于 L=1", () => {
    for (const { input } of CASES.slice(0, 4)) {
      const base = computeMonsterRow({ ...input, highDefFactor: 1 }, "v2");
      const high = computeMonsterRow({ ...input, highDefFactor: 10 }, "v2");
      const mixedBase = monsterMixedEhp(base.hpMax, base.defMax, { magicResist: 30 });
      const mixedHigh = monsterMixedEhp(high.hpMax, high.defMax, { magicResist: 30 });
      expect(mixedHigh).toBeLessThan(mixedBase);
    }
  });
});
