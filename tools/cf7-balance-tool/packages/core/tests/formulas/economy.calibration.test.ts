import { describe, it, expect } from "vitest";
import { computeArmorPrice, computeSynthesis, computeDungeonReward } from "../../src/formulas/economy.js";
import baseline from "../../../../baseline/baseline-extracted.json" with { type: "json" };

interface BaselineRow {
  _row: number;
  input: Record<string, number | string | null>;
  cached: Record<string, number | null>;
}

describe("economy calibration", () => {
  describe("armor prices", () => {
    // baseline equipmentPrices row 1 is armor (row 0 is header)
    const armorRows = (baseline.equipmentPrices as BaselineRow[]).filter(
      (r) => typeof r.input["D"] === "number" && r.input["B"] === "防具"
    );
    for (const row of armorRows) {
      const name = String(row.input["C"] ?? `row${row._row}`);
      it(name, () => {
        const result = computeArmorPrice({
          level: row.input["D"] as number,
          weightLayers: row.input["E"] as number,
          categoryFactor: row.input["G"] as number,
          damageTypeFactor: row.input["H"] as number,
        });
        const cachedGold = row.cached["J"] as number;
        const cachedK = row.cached["K"] as number;
        const cachedRate = row.cached["N"] as number;

        if (cachedGold != null) expect(Math.abs(result.goldPrice - cachedGold) / (cachedGold + 1e-10)).toBeLessThan(0.001);
        if (cachedK != null) expect(Math.abs(result.kPointPrice - cachedK) / (cachedK + 1e-10)).toBeLessThan(0.001);
        if (cachedRate != null) expect(Math.abs(result.exchangeRate - cachedRate) / (cachedRate + 1e-10)).toBeLessThan(0.001);
      });
    }
  });

  describe("synthesis costs", () => {
    const rows = (baseline.synthesis as BaselineRow[]).filter(
      (r) => typeof r.input["限制等级"] === "number"
    );
    for (const row of rows) {
      const name = String(row.input["具体装备"] ?? `row${row._row}`);
      describe(name, () => {
        const input = {
          level: row.input["限制等级"] as number,
          weightLayers: row.input["加权层数"] as number,
          raceFactor: row.input["种族系数"] as number,
          goldCost: row.input["金币需求"] as number,
          kPointCost: row.input["K点需求"] as number,
          materialPrice: row.input["材料价格"] as number,
          equipmentPrice: (row.cached["装备折算价格"] as number) ?? 0,
          dropPrice: row.input["掉落物折算价格"] as number,
        };
        const result = computeSynthesis(input);

        const checks: Array<[string, number | null, number]> = [
          ["当前成本", row.cached["当前成本"], result.currentCost],
          ["平衡成本", row.cached["平衡成本"], result.balanceCost],
          ["加权成本", row.cached["加权成本"], result.weightedCost],
        ];
        for (const [label, cached, computed] of checks) {
          if (cached == null) continue;
          it(label, () => {
            const relErr = Math.abs(computed - cached) / (Math.abs(cached) + 1e-10);
            expect(relErr).toBeLessThan(0.001);
          });
        }
      });
    }
  });

  describe("dungeon rewards", () => {
    const rows = (baseline.dungeonRewards as BaselineRow[]).filter(
      (r) => typeof r.input["阶段系数"] === "number"
    );
    for (const row of rows) {
      const name = String(row.input["C"] ?? `row${row._row}`);
      describe(name, () => {
        const input = {
          stageFactor: row.input["阶段系数"] as number,
          lengthFactor: row.input["长度系数"] as number,
          diffFactor: row.input["难度系数"] as number,
          goldReward: row.input["金币奖励"] as number,
          consumableValue: row.input["消耗品等效价值"] as number,
          exp: row.input["经验"] as number,
          equipmentValue: row.input["装备等效价值"] as number,
          enhanceStone: row.input["强化石"] as number,
        };
        const result = computeDungeonReward(input);

        const checks: Array<[string, number | null, number]> = [
          ["当前收益", row.cached["当前收益"], result.currentReward],
          ["期望收益", row.cached["期望收益"], result.expectedReward],
        ];
        for (const [label, cached, computed] of checks) {
          if (cached == null) continue;
          it(label, () => {
            const relErr = Math.abs(computed - cached) / (Math.abs(cached) + 1e-10);
            expect(relErr).toBeLessThan(0.001);
          });
        }
      });
    }
  });
});
