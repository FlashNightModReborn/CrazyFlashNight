import { describe, it, expect } from "vitest";
import { computeWeaponRow, type WeaponInput } from "../../src/formulas/weapons.js";
import baseline from "../../../../baseline/baseline-extracted.json" with { type: "json" };

/**
 * 枪械公式校准测试
 * 用 baseline.json 中的 Excel 缓存值逐列验证 computeWeaponRow 的输出
 */

/** baseline 中文列名 → WeaponOutput 字段映射 */
const COLUMN_MAP: Array<[string, string]> = [
  ["伤害加成", "damageBonus"],
  ["剧毒", "poison"],
  ["单段伤害", "singleShotDamage"],
  ["周期伤害", "cycleDamage"],
  ["平均dps", "averageDPS"],
  ["平均射速", "averageFireRate"],
  ["吃拐率", "hitRate"],
  ["吃拐系数", "hitRateCoeff"],
  ["冲击力系数", "impactCoeff"],
  ["裸伤dps", "nakedDPS"],
  ["经济加成dps", "economicDPS"],
  ["平衡裸伤dps", "balanceNakedDPS"],
  ["增益dps", "boostDPS"],
  ["平衡增益dps", "balanceBoostDPS"],
  ["平衡dps", "balanceDPS"],
  ["加权dps", "weightedDPS"],
  ["平衡周期伤害", "balanceCycleDamage"],
  ["加权周期伤害", "weightedCycleDamage"],
  ["周期伤害系数", "cycleDamageCoeff"],
  ["平衡基础dps", "balanceBaseDPS"],
  ["旧平衡dps", "oldBalanceDPS"],
  ["周期dps", "cycleDPS"],
  ["周期dps系数", "cycleDPSCoeff"],
  ["dps总公式", "dpsFormula"],
];

interface BaselineRow {
  _row: number;
  input: Record<string, number | string | null>;
  cached: Record<string, number | null>;
}

function toWeaponInput(raw: Record<string, number | string | null>): WeaponInput {
  return {
    level: raw["限制等级"] as number,
    bulletPower: raw["子弹威力"] as number,
    shootInterval: raw["射击间隔"] as number,
    magSize: raw["弹容量"] as number,
    magPrice: raw["弹夹价格"] as number,
    weight: raw["重量"] as number,
    dualWieldFactor: raw["双枪系数"] as number,
    pierceFactor: raw["穿刺系数"] as number,
    damageTypeFactor: raw["伤害类型系数"] as number,
    shotgunValue: raw["霰弹值"] as number,
    impact: raw["冲击力"] as number,
    extraWeightLayers: raw["额外加权层数"] as number,
  };
}

const dataRows = (baseline.weapons as BaselineRow[]).filter(
  (r) => r.input["子弹威力"] != null
);

describe("weapons calibration", () => {
  for (const row of dataRows) {
    const weaponName = String(row.input["具体武器"] ?? `row${row._row}`);

    describe(weaponName, () => {
      const input = toWeaponInput(row.input);
      const result = computeWeaponRow(input);

      for (const [cnName, fieldKey] of COLUMN_MAP) {
        const cached = row.cached[cnName];
        if (cached == null) continue;

        it(`${cnName} (${fieldKey})`, () => {
          const computed = (result as Record<string, number>)[fieldKey]!;
          // 相对误差 < 0.1%
          const relErr = Math.abs(computed - cached) / (Math.abs(cached) + 1e-10);
          expect(relErr).toBeLessThan(0.001);
        });
      }
    });
  }
});
