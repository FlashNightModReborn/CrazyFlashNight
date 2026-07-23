import { describe, expect, it } from "vitest";

import {
  CURRENT_WEAPON_BALANCE_WORKBOOK_SHA256,
  CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION,
  buildWeaponBalanceInputDigestSource,
  computeWeaponBalanceInputDigest,
  derivePlayerWeaponBalanceProjection,
  type WeaponBalanceAuditLedger,
  type WeaponBalanceAuditRecord,
  type WeaponBalanceContainer,
  type WeaponBalanceDigestContext,
  type WeaponBalanceProfile
} from "../../src/index.js";

function fixture() {
  const context: WeaponBalanceDigestContext = {
    itemName: "投影手枪",
    profileKey: "data",
    workbookVersion: CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION,
    use: "长枪",
    level: 10,
    power: 135,
    interval: 110,
    capacity: 30,
    weight: 4,
    impact: 20
  };
  const inputs = {
    dualWield: 1,
    pierce: 1,
    damageType: 1,
    shotgun: 1,
    magPrice: 200,
    weightLayers: 0,
    category: 1,
    formula: 1
  };
  const inputDigest = computeWeaponBalanceInputDigest(
    buildWeaponBalanceInputDigestSource(context, inputs)
  );
  const profile: WeaponBalanceProfile = {
    profileKey: "data",
    ...inputs,
    status: "confirmed",
    displayEligible: true,
    inputDigest,
    auditRef: "weapon:投影手枪:data"
  };
  const audit: WeaponBalanceAuditRecord = {
    auditRef: profile.auditRef,
    itemName: "投影手枪",
    profileKey: "data",
    ...inputs,
    status: "confirmed",
    displayEligible: true,
    inputDigest,
    sourceDigest: `sha256:${"a".repeat(64)}`,
    budgetBreakdown: [
      {
        code: "acquisition.gold-standard",
        delta: 0,
        ruleRef: "WBR-WL-003",
        evidenceRef: "data/shops/npcs/test.json#投影手枪"
      }
    ],
    ruleRefs: [
      { id: "WBR-DUAL-001", target: "input.dualWield", evidenceRef: "data/items/test.xml#use" },
      { id: "WBR-PIERCE-001", target: "input.pierce", evidenceRef: "data/items/test.xml#bullet" },
      { id: "WBR-DMG-001", target: "input.damageType", evidenceRef: "data/items/test.xml#damage" },
      { id: "WBR-SHOT-001", target: "input.shotgun", evidenceRef: "data/items/test.xml#split" },
      { id: "WBR-AMMO-001", target: "input.magPrice", evidenceRef: "data/items/test.xml#clip" },
      { id: "WBR-WL-003", target: "input.weightLayers", evidenceRef: "data/shops/npcs/test.json#投影手枪" },
      { id: "WBR-CAT-001", target: "input.category", evidenceRef: "workbook#category" },
      { id: "WBR-AUTH-001", target: "input.formula", evidenceRef: "workbook#formula" }
    ]
  };
  const container: WeaponBalanceContainer = {
    formulaFamily: "weapon",
    schemaVersion: 1,
    workbookVersion: CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION,
    profiles: { data: profile }
  };
  const ledger: WeaponBalanceAuditLedger = {
    formulaFamily: "weapon",
    schemaVersion: 1,
    workbookVersion: CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION,
    workbookSha256: CURRENT_WEAPON_BALANCE_WORKBOOK_SHA256,
    records: [audit]
  };
  const runtimeInputs = {
    level: context.level,
    power: context.power,
    interval: context.interval,
    capacity: context.capacity,
    weight: context.weight,
    impact: context.impact
  };
  return { context, runtimeInputs, profile, audit, container, ledger };
}

describe("derivePlayerWeaponBalanceProjection", () => {
  it("projects only the exact confirmed four-field player boundary", () => {
    const value = fixture();
    const projection = derivePlayerWeaponBalanceProjection(value.profile, {
      container: value.container,
      ledger: value.ledger,
      auditRecord: value.audit,
      itemName: "投影手枪",
      profileKey: "data",
      digestInput: buildWeaponBalanceInputDigestSource(value.context, value.profile),
      currentSourceDigest: value.audit.sourceDigest,
      runtimeInputs: value.runtimeInputs
    });

    expect(projection).toEqual({
      state: "confirmed",
      weightLayers: 0,
      formula: 1,
      level: 10
    });
    expect(Object.keys(projection ?? {}).sort()).toEqual(
      ["formula", "level", "state", "weightLayers"].sort()
    );
  });

  it("hides an inline digest that no longer matches its ledger/source", () => {
    const value = fixture();
    value.profile.inputDigest = "fnv1a32:00000000";
    const projection = derivePlayerWeaponBalanceProjection(value.profile, {
      container: value.container,
      ledger: value.ledger,
      auditRecord: value.audit,
      itemName: "投影手枪",
      profileKey: "data",
      digestInput: buildWeaponBalanceInputDigestSource(value.context, value.profile),
      currentSourceDigest: value.audit.sourceDigest,
      runtimeInputs: value.runtimeInputs
    });
    expect(projection).toBeNull();
  });

  it("returns null when runtimeInputs are unavailable", () => {
    const value = fixture();
    expect(
      derivePlayerWeaponBalanceProjection(value.profile, {
        container: value.container,
        ledger: value.ledger,
        auditRecord: value.audit,
        itemName: "投影手枪",
        profileKey: "data",
        digestInput: buildWeaponBalanceInputDigestSource(value.context, value.profile),
        currentSourceDigest: value.audit.sourceDigest,
        metrics: { averageDPS: 100, weightedDPS: 100 }
      })
    ).toBeNull();
  });
});
