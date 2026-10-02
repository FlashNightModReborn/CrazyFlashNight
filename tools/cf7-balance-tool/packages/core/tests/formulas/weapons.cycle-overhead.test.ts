import { describe, expect, it } from "vitest";
import { computeWeaponRow, computeWeaponRowWithCycleOverhead, type WeaponInput } from "../../src/formulas/weapons.js";

const input: WeaponInput = { level: 55, bulletPower: 17420, shootInterval: 2000, magSize: 3,
  magPrice: 2500, weight: 150, dualWieldFactor: 1, pierceFactor: 1,
  damageTypeFactor: 1, shotgunValue: 3, impact: 1, extraWeightLayers: 0 };

describe("显式周期外时间，不改变工作簿默认入口", () => {
  it("零额外时间与全部原公式输出一致，包括单发弹匣", () => {
    for (const magSize of [1, 3, 30]) for (const dualWieldFactor of [1, 2]) {
      const sample = { ...input, magSize, dualWieldFactor };
      expect(computeWeaponRowWithCycleOverhead(sample, 0)).toEqual(computeWeaponRow(sample));
    }
  });
  it("单弹容原公式确实消去射击间隔，显式时间同时进入含换弹和不含换弹的周期", () => {
    const single = { ...input, magSize: 1 };
    const base = computeWeaponRow(single);
    expect(computeWeaponRow({ ...single, shootInterval: 20000 })).toEqual(base);
    const delayed = computeWeaponRowWithCycleOverhead(single, 3733.3333333333335);
    expect(delayed.cycleDamage).toBe(base.cycleDamage);
    expect(delayed.averageDPS).toBeCloseTo(1000 * base.cycleDamage / (900 + 3733.3333333333335), 8);
    expect(delayed.cycleDPS).toBeCloseTo(1000 * base.cycleDamage / 3733.3333333333335, 8);
    expect(delayed.economicDPS / base.economicDPS).toBeCloseTo(delayed.averageDPS / base.averageDPS, 12);
    expect(delayed.recommendedGoldPrice).toBe(base.recommendedGoldPrice);
    expect(delayed.recommendedKPointPrice).toBe(base.recommendedKPointPrice);
  });
  it("拒绝负值、无限值和NaN", () => {
    for (const value of [-1, Infinity, -Infinity, NaN]) expect(() => computeWeaponRowWithCycleOverhead(input, value)).toThrow();
  });
});
