import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import type { WeaponBalanceAuditRecord } from "@cf7-balance-tool/core";
import {
  buildWeaponAcquisitionIndex,
  validateWeaponBalanceEvidence,
  type WeaponPriceEvidenceContext
} from "../src/index.js";

function createRecord(
  code:
    | "acquisition.crafting"
    | "acquisition.gold-standard"
    | "acquisition.kshop"
    | "acquisition.high-price"
    | "acquisition.unverified",
  evidenceRef: string
): WeaponBalanceAuditRecord {
  const positiveLayer =
    code === "acquisition.crafting" ||
    code === "acquisition.kshop" ||
    code === "acquisition.high-price";
  const ruleRef =
    code === "acquisition.gold-standard"
      ? "WBR-WL-003"
      : code === "acquisition.unverified"
        ? "WBR-WL-005"
        : "WBR-WL-001";
  return {
    auditRef: "weapon:test:data",
    itemName: "test",
    profileKey: "data",
    dualWield: 1,
    pierce: 1,
    damageType: 1,
    shotgun: 1,
    magPrice: 200,
    weightLayers: positiveLayer ? 1 : 0,
    category: 1,
    formula: 1,
    status: "confirmed",
    displayEligible: true,
    inputDigest: "fnv1a32:00000000",
    sourceDigest: `sha256:${"0".repeat(64)}`,
    budgetBreakdown: [
      {
        code,
        delta: positiveLayer ? 1 : 0,
        ruleRef,
        evidenceRef
      }
    ],
    ruleRefs: [
      {
        id: ruleRef,
        target: "input.weightLayers",
        evidenceRef
      }
    ]
  };
}

describe("weapon balance project evidence", () => {
  function highPriceFixture(root: string) {
    writeJson(root, "data/shops/npcs/Pig.json", { catalog: { "53": "QJZ171" } });
    const record = createRecord("acquisition.high-price", "data/shops/npcs/Pig.json#catalog.53");
    record.itemName = "QJZ171";
    record.priceLayers = 1;
    record.category = 2;
    for (const [id, target] of [
      ["WBR-MAP-002", "pricing.priceLayers"], ["WBR-PL-001", "pricing.priceLayers"],
      ["WBR-PL-003", "pricing.priceLayers"], ["WBR-PRICE-001", "pricing.goldPrice"],
      ["WBR-PRICE-002", "pricing.priceRatio"], ["WBR-PRICE-003", "pricing.priceLayers"]
    ] as const) record.ruleRefs.push({ id, target, evidenceRef: "data/shops/npcs/Pig.json" });
    const context: WeaponPriceEvidenceContext = {
      itemName: "QJZ171", profileKey: "data", itemUse: "长枪", itemPrice: 460000,
      runtimeInputs: { level: 37, power: 888, interval: 240, capacity: 60, weight: 24, impact: 4 }
    };
    return { record, context };
  }

  it("confirms independent gold price mapping against current acquisition and price", () => {
    withFixtureRepository((root) => {
      const { record, context } = highPriceFixture(root);
      writeJson(root, "data/items/test.json", { item: { name: "QJZ171", type: "武器" } });
      expect(validateWeaponBalanceEvidence("QJZ171", record, buildWeaponAcquisitionIndex(root), context))
        .toEqual({ valid: true, displayEligible: true, issues: [] });
      const cheap = validateWeaponBalanceEvidence("QJZ171", record, buildWeaponAcquisitionIndex(root),
        { ...context, itemPrice: 280000 });
      expect(cheap.issues.map((issue) => issue.code)).toContain("high_price_outside_audit_band");
      const expensive = validateWeaponBalanceEvidence("QJZ171", record, buildWeaponAcquisitionIndex(root),
        { ...context, itemPrice: 600000 });
      expect(expensive.displayEligible).toBe(false);
      delete record.priceLayers;
      expect(validateWeaponBalanceEvidence("QJZ171", record, buildWeaponAcquisitionIndex(root), context)
        .issues.map((issue) => issue.code)).toContain("high_price_mapping_unverified");
    });
  });

  it("uses price dual wield 1.5, independently of DPS dual wield 2", () => {
    withFixtureRepository((root) => {
      const { record, context } = highPriceFixture(root);
      record.dualWield = 2;
      context.itemUse = "手枪";
      context.itemPrice = 370000; // 1.5 yields ratio 1.202; DPS divisor 2 would incorrectly reject.
      expect(validateWeaponBalanceEvidence("QJZ171", record, buildWeaponAcquisitionIndex(root), context).valid)
        .toBe(true);
    });
  });

  it.each([
    ["data/crafting/recipe.json", [{ name: "QJZ171" }]],
    ["data/kshop/shop.json", [{ item: "QJZ171" }]],
    ["data/tasks/reward.json", { rewards: [["QJZ171", 1]] }],
    ["data/items/gift.json", { name: "赠品包", type: "消耗品", items: ["QJZ171"] }]
  ])("rejects other or unreviewed acquisition at %s", (file, value) => {
    withFixtureRepository((root) => {
      const { record, context } = highPriceFixture(root);
      writeJson(root, file, value);
      const result = validateWeaponBalanceEvidence("QJZ171", record, buildWeaponAcquisitionIndex(root), context);
      expect(result.displayEligible).toBe(false);
      expect(result.issues.map((issue) => issue.code)).toContain("high_price_unreviewed_acquisition");
    });
  });

  it("rejects the wrong vendor or missing live price context despite valid mapping", () => {
    withFixtureRepository((root) => {
      const { record, context } = highPriceFixture(root);
      writeJson(root, "data/shops/npcs/other.json", { catalog: { "53": "另一把枪" } });
      record.budgetBreakdown[0]!.evidenceRef = "data/shops/npcs/other.json";
      expect(validateWeaponBalanceEvidence("QJZ171", record, buildWeaponAcquisitionIndex(root), context)
        .issues.map((issue) => issue.code)).toContain("high_price_gold_shop_mismatch");
      expect(validateWeaponBalanceEvidence("QJZ171", record, buildWeaponAcquisitionIndex(root))
        .issues.map((issue) => issue.code)).toContain("high_price_context_invalid");
    });
  });

  it("verifies an exact crafting output and repository evidence path", () => {
    withFixtureRepository((root) => {
      writeJson(root, "data/crafting/武器合成.json", [
        { name: "测试步枪", materials: [] }
      ]);
      writeJson(root, "data/shops/npcs/shop.json", {
        schema: "npc-shop.v2",
        catalog: {}
      });
      writeJson(root, "data/kshop/shop.json", []);

      const index = buildWeaponAcquisitionIndex(root);
      const result = validateWeaponBalanceEvidence(
        "测试步枪",
        createRecord(
          "acquisition.crafting",
          "data/crafting/武器合成.json#name=测试步枪"
        ),
        index
      );

      expect(result).toEqual({ valid: true, displayEligible: true, issues: [] });
    });
  });

  it("rejects gold-standard when the item also has crafting and K-shop paths", () => {
    withFixtureRepository((root) => {
      writeJson(root, "data/crafting/武器合成.json", [{ name: "多源步枪" }]);
      writeJson(root, "data/shops/npcs/shop.json", {
        schema: "npc-shop.v2",
        catalog: { "0": "多源步枪" }
      });
      writeJson(root, "data/kshop/shop.json", [{ item: "多源步枪" }]);

      const index = buildWeaponAcquisitionIndex(root);
      const result = validateWeaponBalanceEvidence(
        "多源步枪",
        createRecord(
          "acquisition.gold-standard",
          "data/shops/npcs/shop.json#catalog.0"
        ),
        index
      );
      const codes = result.issues.map((issue) => issue.code);

      expect(result.displayEligible).toBe(false);
      expect(codes).toEqual(
        expect.arrayContaining([
          "gold_standard_has_crafting_source",
          "gold_standard_has_kshop_source"
        ])
      );
    });
  });

  it("rejects a missing or non-repository evidence file", () => {
    withFixtureRepository((root) => {
      writeJson(root, "data/crafting/武器合成.json", [{ name: "测试步枪" }]);
      const index = buildWeaponAcquisitionIndex(root);
      const record = createRecord(
        "acquisition.crafting",
        "data/crafting/不存在.json#name=测试步枪"
      );
      const result = validateWeaponBalanceEvidence("测试步枪", record, index);

      expect(result.issues.map((issue) => issue.code)).toContain(
        "evidence_ref_not_found"
      );
    });
  });

  it("verifies acquisition.kshop against the exact item and evidence file", () => {
    withFixtureRepository((root) => {
      writeJson(root, "data/kshop/exact.json", [{ item: "K点手枪" }]);
      writeJson(root, "data/kshop/other.json", [{ item: "别的手枪" }]);
      const index = buildWeaponAcquisitionIndex(root);

      const exact = validateWeaponBalanceEvidence(
        "K点手枪",
        createRecord("acquisition.kshop", "data/kshop/exact.json#item=K点手枪"),
        index
      );
      expect(exact).toEqual({ valid: true, displayEligible: true, issues: [] });

      const mismatch = validateWeaponBalanceEvidence(
        "K点手枪",
        createRecord("acquisition.kshop", "data/kshop/other.json#item=别的手枪"),
        index
      );
      expect(mismatch.issues.map((issue) => issue.code)).toContain(
        "kshop_evidence_mismatch"
      );
    });
  });

  it("fails confirmed unverified/high-price records closed", () => {
    withFixtureRepository((root) => {
      writeJson(root, "data/kshop/evidence.json", [{ item: "测试步枪" }]);
      const index = buildWeaponAcquisitionIndex(root);
      const evidenceRef = "data/kshop/evidence.json#item=测试步枪";

      const unverified = validateWeaponBalanceEvidence(
        "测试步枪",
        createRecord("acquisition.unverified", evidenceRef),
        index
      );
      expect(unverified.issues.map((issue) => issue.code)).toContain(
        "unverified_acquisition_confirmed"
      );

      const highPrice = validateWeaponBalanceEvidence(
        "测试步枪",
        createRecord("acquisition.high-price", evidenceRef),
        index
      );
      expect(highPrice.issues.map((issue) => issue.code)).toContain(
        "high_price_mapping_unverified"
      );
    });
  });

  it("rejects evidence budget codes outside the closed set", () => {
    withFixtureRepository((root) => {
      writeJson(root, "data/kshop/evidence.json", [{ item: "测试步枪" }]);
      const index = buildWeaponAcquisitionIndex(root);
      const record = createRecord(
        "acquisition.kshop",
        "data/kshop/evidence.json#item=测试步枪"
      );
      record.budgetBreakdown[0]!.code = "acquisition.guessed";
      const result = validateWeaponBalanceEvidence("测试步枪", record, index);
      expect(result.issues.map((issue) => issue.code)).toContain(
        "budget_code_unknown"
      );
    });
  });
});

function withFixtureRepository(run: (root: string) => void): void {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-balance-evidence-"));
  try {
    run(root);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

function writeJson(root: string, relativePath: string, value: unknown): void {
  const target = path.join(root, ...relativePath.split("/"));
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, JSON.stringify(value), "utf8");
}
