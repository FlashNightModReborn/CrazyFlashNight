import { describe, expect, it } from "vitest";

import {
  CURRENT_WEAPON_BALANCE_WORKBOOK_SHA256,
  CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION,
  parseWeaponBalanceAuditLedger,
  parseWeaponBalanceAuditRecord,
  parseWeaponBalanceContainer,
  WeaponBalanceParseError
} from "../../src/index.js";

const sha = CURRENT_WEAPON_BALANCE_WORKBOOK_SHA256;
const workbookVersion = CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION;

function profile() {
  return {
    dualWield: 2,
    pierce: 1,
    damageType: 1,
    shotgun: 1,
    magPrice: 200,
    weightLayers: 0,
    category: 1,
    formula: 1,
    status: "confirmed",
    displayEligible: true,
    inputDigest: "fnv1a32:1234abcd",
    auditRef: "weapon:测试手枪:data"
  };
}

describe("strict weapon balance v1 parsing", () => {
  it("accepts finite audit-only priceLayers and rejects it in runtime profiles", () => {
    const record = { ...profile(), itemName: "测试手枪", profileKey: "data",
      sourceDigest: `sha256:${"a".repeat(64)}`, budgetBreakdown: {}, ruleRefs: {}, priceLayers: 1 };
    expect(parseWeaponBalanceAuditRecord(record).priceLayers).toBe(1);
    for (const value of [true, "", [1, 1], "NaN", Infinity]) {
      expect(() => parseWeaponBalanceAuditRecord({ ...record, priceLayers: value })).toThrow();
    }
    expect(() => parseWeaponBalanceContainer({ formulaFamily: "weapon", schemaVersion: 1,
      workbookVersion, profiles: { data: { ...profile(), priceLayers: 1 } } })).toThrow(/unexpected field/);
  });
  it("parses profiles keyed by effective data tags without duplicating key", () => {
    const container = parseWeaponBalanceContainer({
      formulaFamily: "weapon",
      schemaVersion: 1,
      workbookVersion,
      profiles: {
        data: profile(),
        data_ice: { ...profile(), auditRef: "weapon:测试手枪:data_ice" }
      }
    });

    expect(container.schemaVersion).toBe(1);
    expect(container.profiles.data).toMatchObject({
      profileKey: "data",
      auditRef: "weapon:测试手枪:data"
    });
    expect(container.profiles.data_ice?.profileKey).toBe("data_ice");
  });

  it("rejects old v2 and legacy flat balances instead of reading compatibility", () => {
    expect(() =>
      parseWeaponBalanceContainer({
        formulaFamily: "weapon",
        schemaVersion: 2,
        workbookVersion,
        profiles: { data: profile() }
      })
    ).toThrow(/expected 1/);

    expect(() =>
      parseWeaponBalanceContainer({
        dualWield: 2,
        pierce: 1,
        damageType: 1,
        shotgun: 1,
        magPrice: 200,
        weightLayers: 0,
        category: 1,
        formula: 1
      })
    ).toThrow(WeaponBalanceParseError);
  });

  it("rejects an unimplemented formula version in both runtime and ledger", () => {
    expect(() =>
      parseWeaponBalanceContainer({
        formulaFamily: "weapon",
        schemaVersion: 1,
        workbookVersion,
        profiles: { data: { ...profile(), formula: 2 } }
      })
    ).toThrow(/formula.*implemented formula version 1/);

    expect(() =>
      parseWeaponBalanceAuditLedger({
        formulaFamily: "weapon",
        schemaVersion: 1,
        workbookVersion,
        workbookSha256: sha,
        records: {
          record: {
            ...profile(),
            itemName: "测试手枪",
            profileKey: "data",
            formula: 2,
            sourceDigest: `sha256:${"a".repeat(64)}`,
            budgetBreakdown: {},
            ruleRefs: {}
          }
        }
      })
    ).toThrow(/formula.*implemented formula version 1/);
  });

  it("rejects surplus runtime fields instead of silently carrying audit payload", () => {
    expect(() =>
      parseWeaponBalanceContainer({
        formulaFamily: "weapon",
        schemaVersion: 1,
        workbookVersion,
        profiles: {
          data: {
            ...profile(),
            sourceDigest: `sha256:${"a".repeat(64)}`
          }
        }
      })
    ).toThrow(/sourceDigest: unexpected field/);
  });

  it("rejects boolean values in strict numeric fields", () => {
    expect(() =>
      parseWeaponBalanceContainer({
        formulaFamily: "weapon",
        schemaVersion: 1,
        workbookVersion,
        profiles: {
          data: { ...profile(), dualWield: true }
        }
      })
    ).toThrow(/dualWield: expected a finite number/);

    expect(() =>
      parseWeaponBalanceContainer({
        formulaFamily: "weapon",
        schemaVersion: 1,
        workbookVersion,
        profiles: {
          data: { ...profile(), formula: true }
        }
      })
    ).toThrow(/formula: expected a finite number/);
  });

  it("parses the ledger truth record including repeated decisions", () => {
    const ledger = parseWeaponBalanceAuditLedger({
      formulaFamily: "weapon",
      schemaVersion: 1,
      workbookVersion,
      workbookSha256: sha,
      records: {
        record: {
          auditRef: "weapon:测试手枪:data",
          itemName: "测试手枪",
          profileKey: "data",
          ...profile(),
          sourceDigest: `sha256:${"a".repeat(64)}`,
          budgetBreakdown: {
            entry: {
              code: "acquisition.gold-standard",
              delta: 0,
              ruleRef: "WBR-WL-003",
              evidenceRef: "data/shops/npcs/shop.json#测试手枪"
            }
          },
          ruleRefs: {
            ref: {
              id: "WBR-DUAL-001",
              target: "input.dualWield",
              evidenceRef: "data/items/test.xml#测试手枪/use"
            }
          }
        }
      }
    });

    expect(ledger.records).toHaveLength(1);
    expect(ledger.records[0]).toMatchObject({
      itemName: "测试手枪",
      profileKey: "data",
      dualWield: 2,
      status: "confirmed",
      displayEligible: true
    });
  });

  it("rejects duplicate ledger item/profile identities", () => {
    const record = {
      itemName: "测试手枪",
      profileKey: "data",
      ...profile(),
      auditRef: "one",
      sourceDigest: `sha256:${"a".repeat(64)}`,
      budgetBreakdown: {},
      ruleRefs: {}
    };
    expect(() =>
      parseWeaponBalanceAuditLedger({
        formulaFamily: "weapon",
        schemaVersion: 1,
        workbookVersion,
        workbookSha256: sha,
        records: {
          record: [record, { ...record, auditRef: "two" }]
        }
      })
    ).toThrow(/duplicate item\/profile/);
  });

  it("rejects the unreleased runtime SHA field and mismatched ledger mapping", () => {
    expect(() =>
      parseWeaponBalanceContainer({
        formulaFamily: "weapon",
        schemaVersion: 1,
        workbookVersion,
        workbookSha256: sha,
        profiles: { data: profile() }
      })
    ).toThrow(/workbookSha256: unexpected field/);

    expect(() =>
      parseWeaponBalanceAuditLedger({
        formulaFamily: "weapon",
        schemaVersion: 1,
        workbookVersion,
        workbookSha256: "0".repeat(64),
        records: {}
      })
    ).toThrow(/does not match workbookVersion 1/);
  });
});
