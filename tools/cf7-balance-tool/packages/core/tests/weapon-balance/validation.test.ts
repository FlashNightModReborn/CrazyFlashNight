import { describe, expect, it } from "vitest";

import {
  CURRENT_WEAPON_BALANCE_WORKBOOK_SHA256,
  CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION,
  buildWeaponBalanceInputDigestSource,
  computeWeaponBalanceInputDigest,
  validateWeaponBalanceRecord,
  type WeaponBalanceAuditLedger,
  type WeaponBalanceAuditRecord,
  type WeaponBalanceContainer,
  type WeaponBalanceDigestContext,
  type WeaponBalanceProfile
} from "../../src/index.js";

const context: WeaponBalanceDigestContext = {
  itemName: "测试手枪",
  profileKey: "data",
  workbookVersion: CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION,
  use: "手枪",
  bullet: "普通子弹",
  clipname: "手枪弹药",
  split: 1,
  singleshoot: false,
  level: 10,
  power: 135,
  interval: 110,
  capacity: 30,
  weight: 4,
  impact: 20
};
const sourceDigest = `sha256:${"a".repeat(64)}`;

function createFixture(status: "confirmed" | "unresolved" | "invalid" = "confirmed") {
  const inputs = {
    dualWield: 2,
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
    status,
    displayEligible: status === "confirmed",
    inputDigest,
    auditRef: "weapon:测试手枪:data"
  };
  const audit: WeaponBalanceAuditRecord = {
    auditRef: profile.auditRef,
    itemName: "测试手枪",
    profileKey: "data",
    ...inputs,
    status,
    displayEligible: status === "confirmed",
    inputDigest,
    sourceDigest,
    budgetBreakdown: [
      {
        code: "acquisition.gold-standard",
        delta: 0,
        ruleRef: "WBR-WL-003",
        evidenceRef: "data/shops/npcs/shop.json#测试手枪"
      }
    ],
    ruleRefs: [
      { id: "WBR-DUAL-001", target: "input.dualWield", evidenceRef: "data/items/test.xml#use" },
      { id: "WBR-PIERCE-001", target: "input.pierce", evidenceRef: "data/items/bullets_cases.xml#普通子弹" },
      { id: "WBR-DMG-001", target: "input.damageType", evidenceRef: "data/items/test.xml#damagetype" },
      { id: "WBR-SHOT-001", target: "input.shotgun", evidenceRef: "data/items/test.xml#split" },
      { id: "WBR-AMMO-001", target: "input.magPrice", evidenceRef: "data/items/消耗品_弹夹.xml#手枪弹药" },
      { id: "WBR-WL-003", target: "input.weightLayers", evidenceRef: "data/shops/npcs/shop.json#测试手枪" },
      { id: "WBR-CAT-001", target: "input.category", evidenceRef: "0.说明文件与教程/workbook.xlsx#枪械" },
      { id: "WBR-AUTH-001", target: "input.formula", evidenceRef: "0.说明文件与教程/workbook.xlsx#枪械" }
    ]
  };
  if (status !== "confirmed") audit.note = "等待人类裁定特殊机制";
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
  return { profile, audit, container, ledger, inputDigest };
}

function validateFixture(fixture = createFixture()) {
  return validateWeaponBalanceRecord(fixture.profile, {
    container: fixture.container,
    ledger: fixture.ledger,
    auditRecord: fixture.audit,
    itemName: "测试手枪",
    profileKey: "data",
    digestInput: buildWeaponBalanceInputDigestSource(context, fixture.profile),
    currentSourceDigest: sourceDigest,
    metrics: { averageDPS: 100, weightedDPS: 100 }
  });
}

describe("validateWeaponBalanceRecord strict v1", () => {
  it("accepts a closed confirmed ledger record without requiring a note", () => {
    const result = validateFixture();
    expect(result.valid).toBe(true);
    expect(result.displayEligible).toBe(true);
    expect(result.currentInputDigest).toMatch(/^fnv1a32:/);
    expect(result.metrics?.residualRatio).toBe(0);
  });

  it("fails closed when inline decisions diverge from ledger truth", () => {
    const fixture = createFixture();
    fixture.profile.weightLayers = 1;
    const result = validateFixture(fixture);
    expect(result.displayEligible).toBe(false);
    expect(result.issues.map((issue) => issue.code)).toEqual(
      expect.arrayContaining([
        "inline_ledger_field_mismatch",
        "input_digest_mismatch"
      ])
    );
  });

  it("detects ledger input and complete source digest drift", () => {
    const fixture = createFixture();
    fixture.audit.inputDigest = "fnv1a32:00000000";
    fixture.audit.sourceDigest = `sha256:${"b".repeat(64)}`;
    const result = validateFixture(fixture);
    expect(result.issues.map((issue) => issue.code)).toEqual(
      expect.arrayContaining([
        "inline_ledger_digest_mismatch",
        "ledger_input_digest_mismatch",
        "source_digest_mismatch"
      ])
    );
  });

  it("requires the external ledger join and workbook identity", () => {
    const fixture = createFixture();
    const withoutLedger = validateWeaponBalanceRecord(fixture.profile, {
      container: fixture.container,
      itemName: "测试手枪",
      profileKey: "data",
      digestInput: buildWeaponBalanceInputDigestSource(context, fixture.profile),
      currentSourceDigest: sourceDigest,
      metrics: { averageDPS: 100, weightedDPS: 100 }
    });
    expect(withoutLedger.issues.map((issue) => issue.code)).toContain(
      "audit_record_missing"
    );

    fixture.ledger.workbookSha256 = "0".repeat(64);
    const stale = validateFixture(fixture);
    expect(stale.issues.map((issue) => issue.code)).toContain(
      "ledger_workbook_sha_mapping_mismatch"
    );
  });

  it("fails closed when the runtime workbook version drifts from the ledger", () => {
    const fixture = createFixture();
    fixture.container.workbookVersion = 2;
    const result = validateFixture(fixture);
    expect(result.issues.map((issue) => issue.code)).toEqual(
      expect.arrayContaining([
        "workbook_version_unknown",
        "workbook_version_stale",
        "ledger_container_workbook_mismatch",
        "input_digest_workbook_context_mismatch"
      ])
    );
  });

  it.each(["unresolved", "invalid"] as const)(
    "%s is valid but hidden only with a non-empty decision note",
    (status) => {
      const fixture = createFixture(status);
      const valid = validateFixture(fixture);
      expect(valid.valid).toBe(true);
      expect(valid.displayEligible).toBe(false);

      delete fixture.audit.note;
      const missing = validateFixture(fixture);
      expect(missing.valid).toBe(false);
      expect(missing.issues.map((issue) => issue.code)).toContain(
        "pending_note_missing"
      );
    }
  );

  it("does not allow a pending record to request player display", () => {
    const fixture = createFixture("unresolved");
    fixture.profile.displayEligible = true;
    fixture.audit.displayEligible = true;
    const result = validateFixture(fixture);
    expect(result.issues.map((issue) => issue.code)).toEqual(
      expect.arrayContaining([
        "display_eligibility_status_mismatch",
        "ledger_display_eligibility_status_mismatch"
      ])
    );
  });

  it("rejects formula=2 even when inline, ledger and digest agree", () => {
    const fixture = createFixture();
    fixture.profile.formula = 2;
    fixture.audit.formula = 2;
    const digest = computeWeaponBalanceInputDigest(
      buildWeaponBalanceInputDigestSource(context, fixture.profile)
    );
    fixture.profile.inputDigest = digest;
    fixture.audit.inputDigest = digest;

    const result = validateFixture(fixture);
    expect(result.displayEligible).toBe(false);
    expect(result.issues.map((issue) => issue.code)).toEqual(
      expect.arrayContaining([
        "formula_version_invalid",
        "ledger_formula_version_invalid"
      ])
    );
  });

  it("rejects a ledger join whose item/profile identity does not match runtime", () => {
    const fixture = createFixture();
    fixture.audit.itemName = "另一把手枪";
    fixture.audit.profileKey = "data_ice";
    const result = validateFixture(fixture);
    expect(result.issues.map((issue) => issue.code)).toEqual(
      expect.arrayContaining(["audit_item_mismatch", "audit_profile_mismatch"])
    );
  });

  it("rejects budget codes outside the strict closed set", () => {
    const fixture = createFixture();
    fixture.audit.budgetBreakdown[0]!.code = "acquisition.guessed";
    const result = validateFixture(fixture);
    expect(result.valid).toBe(false);
    expect(result.issues.map((issue) => issue.code)).toContain(
      "budget_code_unknown"
    );
  });
});
