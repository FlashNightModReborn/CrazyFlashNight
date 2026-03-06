import { describe, it, expect } from "vitest";
import { computePotionRow, type PotionInput } from "../../src/formulas/potions.js";
import baseline from "../../../../baseline/baseline-extracted.json" with { type: "json" };

interface BaselineRow {
  _row: number;
  input: Record<string, number | string | null>;
  cached: Record<string, number | null>;
}

const COLUMN_MAP: Array<[string, string]> = [
  ["恢复药强度", "recoveryStrength"],
  ["净化强度", "purifyStrength"],
  ["剧毒强度", "toxicStrength"],
  ["buff强度", "buffStrength"],
  ["当前数值", "currentValue"],
  ["数值上限", "valueCap"],
  ["原始推荐价格", "rawPrice"],
  ["推荐价格", "recommendedPrice"],
];

function toPotionInput(raw: Record<string, number | string | null>, cached: Record<string, number | null>): PotionInput {
  return {
    hp: cached["hp"] as number ?? 0,
    mp: cached["mp"] as number ?? 0,
    sustainFrames: cached["缓释持续帧"] as number ?? 0,
    playerLevel: raw["玩家等级"] as number,
    isGroup: raw["是否群体"] as number,
    purifyValue: raw["净化值"] as number ?? 0,
    toxicity: raw["剧毒性"] as number ?? 0,
    buffHp: raw["buff-hp"] as number ?? 0,
    buffMp: raw["buff-mp"] as number ?? 0,
    buffDefence: raw["buff-防御"] as number ?? 0,
    buffMagicResist: raw["buff-魔抗"] as number ?? 0,
    buffDamage: raw["buff-伤害"] as number ?? 0,
    buffPunch: raw["buff-空手"] as number ?? 0,
    buffSpeed: raw["buff-速度"] as number ?? 0,
    buffDuration: raw["buff-持续帧"] as number ?? 0,
  };
}

const dataRows = (baseline.potions as BaselineRow[]).filter(
  (r) => typeof r.input["玩家等级"] === "number"
);

describe("potions calibration", () => {
  for (const row of dataRows) {
    const name = String(row.input["C"] ?? `row${row._row}`);
    describe(name, () => {
      const input = toPotionInput(row.input, row.cached);
      const result = computePotionRow(input);

      for (const [cnName, fieldKey] of COLUMN_MAP) {
        const cached = row.cached[cnName];
        if (cached == null) continue;
        it(`${cnName} (${fieldKey})`, () => {
          const computed = (result as Record<string, number>)[fieldKey]!;
          const relErr = Math.abs(computed - cached) / (Math.abs(cached) + 1e-10);
          expect(relErr).toBeLessThan(0.001);
        });
      }
    });
  }
});
