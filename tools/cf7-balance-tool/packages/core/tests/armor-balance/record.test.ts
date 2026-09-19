import { describe, expect, it } from "vitest";

import {
  ARMOR_BALANCE_WORKBOOK_SHA256,
  ARMOR_BALANCE_WORKBOOK_VERSION,
  ArmorBalanceParseError,
  parseArmorBalancePlan,
  parseArmorBalancePlanRecord
} from "../../src/index.js";

const sha = ARMOR_BALANCE_WORKBOOK_SHA256;
const workbookVersion = ARMOR_BALANCE_WORKBOOK_VERSION;

function budget() {
  return {
    entry: [
      { code: "acquisition.kshop", delta: 1, ruleRef: "ABR-LAYER-001" },
      { code: "acquisition.high-price", delta: 1, ruleRef: "ABR-LAYER-001" },
      { code: "level-band.40plus-float", delta: 1, ruleRef: "ABR-LAYER-004" }
    ]
  };
}

function record() {
  return {
    itemName: "钛合金61式头部装甲",
    sourceFile: "data/items/防具_40+级.xml",
    weightLayers: 3,
    priceLayers: 1,
    category: 1,
    damageTypeFactor: 1,
    adoptedGoldPrice: 200000,
    expectedKPointPrice: 6000,
    kpointEvidenceRef: "data/kshop/A兵团官方周边直营店.json",
    status: "confirmed",
    budgetBreakdown: budget()
  };
}

function plan() {
  return {
    armorBalancePlan: {
      formulaFamily: "armor",
      schemaVersion: 1,
      formulaVersion: 1,
      workbookVersion,
      workbookSha256: sha,
      records: { record: [record()] }
    }
  };
}

describe("strict armor balance plan parsing", () => {
  it("accepts a well-formed plan with attribute-style records", () => {
    const attributeStyle = plan();
    const raw = attributeStyle.armorBalancePlan.records.record[0]!;
    attributeStyle.armorBalancePlan.records.record[0] = Object.fromEntries(
      Object.entries(raw).map(([key, value]) => [`@_${key}`, value])
    );
    const parsed = parseArmorBalancePlan(attributeStyle);
    expect(parsed.records).toHaveLength(1);
    expect(parsed.records[0]).toMatchObject({
      itemName: "钛合金61式头部装甲",
      weightLayers: 3,
      priceLayers: 1,
      status: "confirmed"
    });
    expect(parsed.records[0]!.budgetBreakdown.map((entry) => entry.code)).toEqual([
      "acquisition.kshop",
      "acquisition.high-price",
      "level-band.40plus-float"
    ]);
  });

  it("rejects header, identity and schema violations", () => {
    expect(() => parseArmorBalancePlan({})).toThrow(ArmorBalanceParseError);
    const wrongFamily = plan();
    wrongFamily.armorBalancePlan.formulaFamily = "potion";
    expect(() => parseArmorBalancePlan(wrongFamily)).toThrow(/formulaFamily/);
    const wrongSha = plan();
    wrongSha.armorBalancePlan.workbookSha256 = "A".repeat(64);
    expect(() => parseArmorBalancePlan(wrongSha)).toThrow(/workbookSha256/);
    const duplicate = plan();
    duplicate.armorBalancePlan.records.record.push(record());
    expect(() => parseArmorBalancePlan(duplicate)).toThrow(/duplicate itemName/);
    const badStatus = plan();
    badStatus.armorBalancePlan.records.record[0]!.status = "proposed";
    expect(() => parseArmorBalancePlan(badStatus)).toThrow(/status/);
    const outsideFamily = plan();
    outsideFamily.armorBalancePlan.records.record[0]!.sourceFile =
      "data/items/武器_枪械.xml";
    expect(() => parseArmorBalancePlan(outsideFamily)).toThrow(/sourceFile/);
  });

  it("rejects unknown fields and unknown budget codes", () => {
    expect(() =>
      parseArmorBalancePlanRecord({ ...record(), authorityStatus: "x" })
    ).toThrow(/unexpected field/);
    const badCode = record();
    badCode.budgetBreakdown = {
      entry: [{ code: "acquisition.unverified", delta: 3, ruleRef: "ABR-LAYER-001" }]
    };
    expect(() => parseArmorBalancePlanRecord(badCode)).toThrow(/code/);
  });

  it("enforces budget closure: delta sum equals weightLayers", () => {
    const under = record();
    under.budgetBreakdown = {
      entry: [
        { code: "acquisition.kshop", delta: 1, ruleRef: "ABR-LAYER-001" },
        { code: "acquisition.high-price", delta: 1, ruleRef: "ABR-LAYER-001" }
      ]
    };
    expect(() => parseArmorBalancePlanRecord(under)).toThrow(/does not close/);
    const over = record();
    over.weightLayers = 2;
    expect(() => parseArmorBalancePlanRecord(over)).toThrow(/does not close/);
  });

  it("enforces priceLayers equal to the high-price entry delta", () => {
    const drifted = record();
    drifted.priceLayers = 2;
    expect(() => parseArmorBalancePlanRecord(drifted)).toThrow(/priceLayers/);
    const free = record();
    free.weightLayers = 2;
    free.priceLayers = 0;
    free.budgetBreakdown = {
      entry: [
        { code: "acquisition.kshop", delta: 1, ruleRef: "ABR-LAYER-001" },
        { code: "level-band.40plus-float", delta: 1, ruleRef: "ABR-LAYER-004" }
      ]
    };
    expect(parseArmorBalancePlanRecord(free).priceLayers).toBe(0);
  });
});
