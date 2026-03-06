import { describe, it, expect } from "vitest";
import { computeMeleeRow, type MeleeInput } from "../../src/formulas/melee.js";
import baseline from "../../../../baseline/baseline-extracted.json" with { type: "json" };

interface BaselineRow {
  _row: number;
  input: Record<string, number | string | null>;
  cached: Record<string, number | null>;
}

function toMeleeInput(raw: Record<string, number | string | null>): MeleeInput {
  return {
    level: raw["限制等级"] as number,
    weight: raw["重量"] as number,
    damageTypeFactor: raw["伤害类型系数"] as number,
    weightLayers: raw["加权层数"] as number,
  };
}

const dataRows = (baseline.melee as BaselineRow[]).filter(
  (r) => r.input["限制等级"] != null
);

describe("melee calibration", () => {
  for (const row of dataRows) {
    const name = String(row.input["C"] ?? `row${row._row}`);
    it(`${name} — 推荐锋利度`, () => {
      const input = toMeleeInput(row.input);
      const result = computeMeleeRow(input);
      const cached = row.cached["推荐锋利度"]!;
      const relErr = Math.abs(result.recommendedSharpness - cached) / (Math.abs(cached) + 1e-10);
      expect(relErr).toBeLessThan(0.001);
    });
  }
});
