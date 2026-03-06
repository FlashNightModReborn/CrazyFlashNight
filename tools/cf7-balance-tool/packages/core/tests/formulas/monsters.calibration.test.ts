import { describe, it, expect } from "vitest";
import { computeMonsterRow, type MonsterInput } from "../../src/formulas/monsters.js";
import baseline from "../../../../baseline/baseline-extracted.json" with { type: "json" };

const COLUMN_MAP: Array<[string, string]> = [
  ["空手攻击MIN", "atkMin"],
  ["空手攻击MAX", "atkMax"],
  ["HP最小值", "hpMin"],
  ["HP最大值", "hpMax"],
  ["防御力MIX", "defMin"],
  ["防御力MAX", "defMax"],
  ["经验MIN", "expMin"],
  ["经验MAX", "expMax"],
  ["金币价格", "goldPrice"],
  ["K点价格", "kPointPrice"],
];

interface BaselineRow {
  _row: number;
  input: Record<string, number | string | null>;
  cached: Record<string, number | null>;
}

function toMonsterInput(raw: Record<string, number | string | null>): MonsterInput {
  return {
    stage: raw["阶段"] as number,
    tierFactor: raw["档次系数"] as number,
    growthFactor: raw["成长系数"] as number,
    atkSpeedFactor: raw["攻速系数"] as number,
    atkMultiplier: raw["攻击倍率"] as number,
    segmentFactor: raw["段数系数"] as number,
    speedFactor: raw["速度系数"] as number,
    highAtkFactor: raw["高攻低血防系数"] as number,
    superArmorFactor: raw["霸体系数"] as number,
    highDefFactor: raw["高防低血系数"] as number,
  };
}

const dataRows = (baseline.monsters as BaselineRow[]).filter(
  (r) => typeof r.input["阶段"] === "number" && typeof r.input["档次系数"] === "number"
);

describe("monsters calibration", () => {
  for (const row of dataRows) {
    const name = String(row.input["B"] ?? `row${row._row}`);
    describe(name, () => {
      const input = toMonsterInput(row.input);
      const result = computeMonsterRow(input);

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
