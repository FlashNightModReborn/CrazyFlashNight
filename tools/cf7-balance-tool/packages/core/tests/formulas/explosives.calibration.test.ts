import { describe, it, expect } from "vitest";
import { computeExplosivesRow, type ExplosivesInput } from "../../src/formulas/explosives.js";
import baseline from "../../../../baseline/baseline-extracted.json" with { type: "json" };

interface BaselineRow {
  _row: number;
  input: Record<string, number | string | null>;
  cached: Record<string, number | null>;
}

// Only gun-type explosives (Excel rows 3-5); grenades (rows 12+) use a different formula
const dataRows = (baseline.explosives as BaselineRow[]).filter(
  (r) => r.input["弹夹价格"] != null && typeof r.input["弹夹价格"] === "number" && r._row <= 10
);

describe("explosives calibration", () => {
  for (const row of dataRows) {
    const name = String(row.input["C"] ?? `row${row._row}`);
    it(`${name} — 推荐单发威力`, () => {
      const input: ExplosivesInput = {
        magPrice: row.input["弹夹价格"] as number,
        magSize: row.input["弹容量"] as number,
        level: row.input["限制等级"] as number,
        weightLayers: (row.input["加权层级"] as number) ?? 0,
      };
      const result = computeExplosivesRow(input);
      const cached = row.cached["推荐单发威力"]!;
      if (cached == null) return;
      const relErr = Math.abs(result.recommendedPower - cached) / (Math.abs(cached) + 1e-10);
      expect(relErr).toBeLessThan(0.001);
    });
  }
});
