import { describe, it, expect } from "vitest";
import { computeArmorRow, type ArmorInput, type ArmorType } from "../../src/formulas/armor.js";
import baseline from "../../../../baseline/baseline-extracted.json" with { type: "json" };

const COLUMN_MAP: Array<[string, string]> = [
  ["当前总分", "currentScore"],
  ["平衡总分", "balanceScore"],
  ["加权总分", "weightedScore"],
  ["法抗均值上限", "magicDefAvgCap"],
  ["法抗最高上限", "magicDefMaxCap"],
];

interface BaselineRow {
  _row: number;
  input: Record<string, number | string | null>;
  cached: Record<string, number | null>;
}

function detectType(raw: Record<string, number | string | null>): ArmorType {
  const t = String(raw["类型"] ?? "");
  const name = String(raw["具体装备"] ?? "");
  if (t.includes("手套")) return "glove";
  if (t === "项链" || name.includes("项链")) return "necklace";
  return "standard";
}

function toArmorInput(raw: Record<string, number | string | null>): ArmorInput {
  return {
    level: raw["限制等级"] as number,
    defence: raw["防御"] as number,
    hp: raw["HP"] as number,
    mp: raw["MP"] as number,
    damageBonus: raw["伤害加成"] as number,
    weaponBonus: raw["刀/枪总加成"] as number,
    weight: raw["重量"] as number,
    punchBonus: raw["空手加成"] as number,
    magicDefence: raw["法抗"] as number,
    extraWeightLayers: raw["额外加权层数"] as number,
    type: detectType(raw),
  };
}

const dataRows = (baseline.armor as BaselineRow[]).filter(
  (r) => r.input["防御"] != null
);

describe("armor calibration", () => {
  for (const row of dataRows) {
    const name = String(row.input["具体装备"] ?? `row${row._row}`);
    describe(name, () => {
      const input = toArmorInput(row.input);
      const result = computeArmorRow(input);
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
