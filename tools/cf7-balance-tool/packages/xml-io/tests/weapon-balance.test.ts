import { describe, expect, it } from "vitest";
import { XMLParser } from "fast-xml-parser";

import {
  CURRENT_WEAPON_BALANCE_WORKBOOK_SHA256,
  CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION,
  type WeaponBalanceAuditLedger,
  type WeaponBalanceAuditRecord
} from "@cf7-balance-tool/core";
import {
  applyWeaponBalanceSyncPlansToXml,
  assertWeaponBalanceSyncCoverage,
  buildWeaponBalanceSyncPlanForItemObject,
  enumerateWeaponItemEffectiveProfileKeys,
  mergeWeaponBalanceSyncPlanIntoLedger,
  parseWeaponBalanceAuditLedgerFromXml,
  parseWeaponBalanceItemsFromXml,
  resolveWeaponItemEffectiveProfile,
  serializeWeaponBalanceAuditLedgerXml
} from "../src/index.js";

const itemXml = `<?xml version="1.0" encoding="UTF-8"?>
<root>
  <item weapontype="手枪">
    <name>变体测试手枪</name>
    <use>手枪</use>
    <skill><id>base-skill</id></skill>
    <lifecycle><id>base-life</id></lifecycle>
    <data>
      <level>10</level><power>135</power><interval>110</interval>
      <capacity>30</capacity><weight>4</weight><impact>20</impact>
      <bullet>普通子弹</bullet><clipname>手枪弹药</clipname><split>1</split>
    </data>
    <data_ice>
      <level>20</level><power>210</power><bullet>冰冻子弹</bullet>
      <skill><id>ice-skill</id></skill>
    </data_ice>
  </item>
</root>
`;

function audit(profileKey: string): WeaponBalanceAuditRecord {
  return {
    auditRef: `weapon:变体测试手枪:${profileKey}`,
    itemName: "变体测试手枪",
    profileKey,
    dualWield: 2,
    pierce: 1,
    damageType: profileKey === "data_ice" ? 2 : 1,
    shotgun: 1,
    magPrice: 200,
    weightLayers: 0,
    category: 1,
    formula: 1,
    status: "unresolved",
    displayEligible: false,
    inputDigest: "fnv1a32:00000000",
    sourceDigest: `sha256:${"0".repeat(64)}`,
    budgetBreakdown: [],
    ruleRefs: [],
    note: "测试夹具等待人类裁定"
  };
}

function ledger(): WeaponBalanceAuditLedger {
  return {
    formulaFamily: "weapon",
    schemaVersion: 1,
    workbookVersion: CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION,
    workbookSha256: CURRENT_WEAPON_BALANCE_WORKBOOK_SHA256,
    records: [audit("data"), audit("data_ice")]
  };
}

describe("weapon balance v1 profile resolver and sync", () => {
  it("expands base and variant with TierSystem shallow override semantics", () => {
    const parsed = parseFixtureItemObject(itemXml);
    expect(enumerateWeaponItemEffectiveProfileKeys(parsed)).toEqual([
      "data",
      "data_ice"
    ]);

    const base = resolveWeaponItemEffectiveProfile(
      parsed,
      "data",
      CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION
    );
    const ice = resolveWeaponItemEffectiveProfile(
      parsed,
      "data_ice",
      CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION
    );
    expect(base.runtimeInputs).toMatchObject({ level: 10, power: 135 });
    expect(ice.runtimeInputs).toMatchObject({
      level: 20,
      power: 210,
      interval: 110,
      capacity: 30
    });
    expect(ice.effectiveData.bullet).toBe("冰冻子弹");
    expect(ice.effectiveSkill).toEqual({ id: "ice-skill" });
    expect(ice.effectiveLifecycle).toEqual({ id: "base-life" });
    expect(ice.currentSourceDigest).not.toBe(base.currentSourceDigest);
  });

  it("generates canonical runtime profiles and refreshed ledger digests", () => {
    const applied = applyWeaponBalanceSyncPlansToXml(itemXml, ledger());
    expect(applied.plans).toHaveLength(1);
    expect(applied.plans[0]?.profileKeys).toEqual(["data", "data_ice"]);
    expect(applied.source).toContain("<schemaVersion>1</schemaVersion>");
    expect(applied.source).toContain("<workbookVersion>1</workbookVersion>");
    expect(applied.source).not.toContain("<workbookSha256>");
    expect(applied.source).toContain("<data_ice>");

    const updatedLedger = mergeWeaponBalanceSyncPlanIntoLedger(
      ledger(),
      applied.plans
    );
    const parsedProfiles = parseWeaponBalanceItemsFromXml(applied.source);
    expect(parsedProfiles).toHaveLength(2);
    expect(parsedProfiles.map((item) => item.profileKey)).toEqual([
      "data",
      "data_ice"
    ]);
    for (const profile of parsedProfiles) {
      const updated = updatedLedger.records.find(
        (record) => record.auditRef === profile.profile.auditRef
      );
      expect(profile.profile.inputDigest).toBe(profile.currentInputDigest);
      expect(updated?.inputDigest).toBe(profile.currentInputDigest);
      expect(updated?.sourceDigest).toBe(profile.currentSourceDigest);
    }
  });

  it("preserves combat data text while replacing only item-root balance", () => {
    const first = applyWeaponBalanceSyncPlansToXml(itemXml, ledger());
    const beforeData = itemXml.match(/    <data>[\s\S]*?    <\/data>/)?.[0];
    const afterData = first.source.match(/    <data>[\s\S]*?    <\/data>/)?.[0];
    expect(afterData).toBe(beforeData);

    const updatedLedger = mergeWeaponBalanceSyncPlanIntoLedger(
      ledger(),
      first.plans
    );
    const second = applyWeaponBalanceSyncPlansToXml(first.source, updatedLedger);
    expect(second.plans[0]?.inSync).toBe(true);
    expect(second.source).toBe(first.source);
  });

  it("fails closed when an existing data_* has no independent profile", () => {
    const applied = applyWeaponBalanceSyncPlansToXml(itemXml, ledger());
    const missingIce = applied.source.replace(
      /      <data_ice>[\s\S]*?      <\/data_ice>\n/,
      ""
    );
    expect(() => parseWeaponBalanceItemsFromXml(missingIce)).toThrow(
      /missing data_ice/
    );
  });

  it("rejects old v2 without a fallback", () => {
    const v2 = itemXml.replace(
      "    <data_ice>",
      `    <balance><formulaFamily>weapon</formulaFamily><schemaVersion>2</schemaVersion></balance>\n    <data_ice>`
    );
    expect(() => parseWeaponBalanceItemsFromXml(v2)).toThrow(/expected 1/);
  });

  it("round-trips the external ledger canonical XML", () => {
    const source = serializeWeaponBalanceAuditLedgerXml(ledger());
    const parsed = parseWeaponBalanceAuditLedgerFromXml(source);
    expect(parsed).toEqual(ledger());
  });

  it("rejects generation if any active profile lacks a ledger truth record", () => {
    const item = parseFixtureItemObject(itemXml);
    const missing = ledger();
    missing.records = missing.records.filter((record) => record.profileKey === "data");
    expect(() => buildWeaponBalanceSyncPlanForItemObject(item, missing)).toThrow(
      /data_ice: ledger record missing/
    );
  });

  it("rejects orphan or multiply joined ledger records before any write", () => {
    const value = ledger();
    const applied = applyWeaponBalanceSyncPlansToXml(itemXml, value);
    const orphan: WeaponBalanceAuditRecord = {
      ...audit("data"),
      auditRef: "weapon:不存在:data",
      itemName: "不存在"
    };
    expect(() =>
      assertWeaponBalanceSyncCoverage(
        { ...value, records: [...value.records, orphan] },
        applied.plans
      )
    ).toThrow(/不存在:data.*joined 0/);
    expect(() =>
      assertWeaponBalanceSyncCoverage(value, [
        ...applied.plans,
        ...applied.plans
      ])
    ).toThrow(/joined 2/);
  });
});

function parseFixtureItemObject(source: string): Record<string, unknown> {
  const match = source.match(/<item\b[\s\S]*<\/item>/);
  if (!match) throw new Error("fixture item missing");
  const parsed = new XMLParser({ parseTagValue: true, trimValues: true }).parse(
    `<root>${match[0]}</root>`
  ) as { root: { item: Record<string, unknown> } };
  return parsed.root.item;
}
