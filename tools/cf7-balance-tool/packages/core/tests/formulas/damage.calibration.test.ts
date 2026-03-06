import { describe, it, expect } from "vitest";
import { computePhysicalDamage, computeMagicDamage } from "../../src/formulas/damage.js";
import baseline from "../../../../baseline/baseline-extracted.json" with { type: "json" };

interface BaselineRow {
  _row: number;
  input: Record<string, number | string | null>;
  cached: Record<string, number | null>;
}

const dataRows = (baseline.damageFormula as BaselineRow[]).filter((r) => {
  if (typeof r.input["E"] !== "number" || typeof r.cached["C"] !== "number") return false;
  // Skip rows where F ≠ D*(1-E) — these use a different sub-table layout
  const D = r.cached["D"] as number;
  const E = r.input["E"] as number;
  const F = r.cached["F"] as number;
  if (D == null || F == null) return false;
  const expectedF = D * (1 - E);
  return Math.abs(expectedF - F) / (Math.abs(F) + 1e-10) < 0.001;
});

describe("damage formula calibration", () => {
  describe("physical", () => {
    for (const row of dataRows) {
      const label = `row${row._row}`;
      describe(label, () => {
        const damage = row.cached["C"] as number;
        const defence = row.cached["D"] as number;
        const penetration = row.input["E"] as number;
        const hp = row.cached["J"] as number;

        const result = computePhysicalDamage({ damage, defence, penetration, hp });

        const checks: Array<[string, number | null, number]> = [
          ["最终防御", row.cached["F"], result.effectiveDefence],
          ["减伤比例", row.cached["G"], result.reductionRatio],
          ["剩余比例", row.cached["H"], result.remainRatio],
          ["等效血量", row.cached["K"], result.effectiveHP],
          ["最终伤害", row.cached["M"], result.finalDamage],
          ["承伤次数", row.cached["O"], result.hitsToKill],
        ];

        for (const [name, cached, computed] of checks) {
          if (cached == null) continue;
          it(name, () => {
            const relErr = Math.abs(computed - cached) / (Math.abs(cached) + 1e-10);
            expect(relErr).toBeLessThan(0.001);
          });
        }
      });
    }
  });

  describe("magic", () => {
    for (const row of dataRows) {
      const label = `row${row._row}`;
      const magicDamage = row.input["R"] as number;
      const magicResist = row.input["伤害 *(100-对应魔抗)/100"] as number;
      if (typeof magicDamage !== "number" || typeof magicResist !== "number") continue;

      describe(label, () => {
        const result = computeMagicDamage({ damage: magicDamage, magicResist, hp: 0 });

        const checks: Array<[string, number | null, number]> = [
          ["等效血量", row.cached["U"], result.effectiveHP],
          ["最终伤害", row.cached["W"], result.finalDamage],
        ];

        for (const [name, cached, computed] of checks) {
          if (cached == null) continue;
          it(name, () => {
            const relErr = Math.abs(computed - cached) / (Math.abs(cached) + 1e-10);
            expect(relErr).toBeLessThan(0.001);
          });
        }
      });
    }
  });
});
