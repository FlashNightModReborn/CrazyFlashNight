import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  CURRENT_WEAPON_BALANCE_WORKBOOK_SHA256,
  computeWeaponBalanceInputDigest,
  type WeaponBalanceAuditLedger,
  type WeaponBalanceAuditRecord
} from "@cf7-balance-tool/core";
import {
  AS2_WEAPON_SUMMARY_SOURCE, modelAs2WeaponSummary, verifyAs2WeaponSummaryModelSource
} from "../src/weapon-summary-as2-model.js";
import { compareWeaponSummaryItem } from "../src/weapon-summary-parity.js";
import {
  buildWeaponBalanceProfileDigestInput, resolveWeaponItemEffectiveProfile,
  parseWeaponBalanceAuditLedgerFromXml, serializeWeaponBalanceAuditLedgerXml
} from "../src/weapon-balance.js";

type Node = Record<string, unknown>;
const repo = fileURLToPath(new URL("../../../../../", import.meta.url));
const at = (source: Node, ...keys: string[]): Node => keys.reduce((node, key) => node[key] as Node, source);
function fixture() {
  const inputs = { dualWield: 1, pierce: 1, damageType: 1, shotgun: 1,
    magPrice: 200, weightLayers: 0, category: 1, formula: 1 };
  const profile = { ...inputs, status: "confirmed", displayEligible: true,
    inputDigest: "", auditRef: "weapon:投影手枪:data" };
  const item: Node = {
    name: "投影手枪", type: "武器", use: "长枪",
    data: { level: 10, power: 135, interval: 110, capacity: 30, weight: 4, impact: 20 },
    balance: { formulaFamily: "weapon", schemaVersion: 1, workbookVersion: 1, profiles: { data: profile } }
  };
  const resolved = resolveWeaponItemEffectiveProfile(item, "data", 1);
  profile.inputDigest = computeWeaponBalanceInputDigest(buildWeaponBalanceProfileDigestInput(resolved, inputs));
  const audit: WeaponBalanceAuditRecord = {
    ...profile, ...inputs, profileKey: "data", itemName: "投影手枪", status: "confirmed",
    sourceDigest: resolved.currentSourceDigest,
    budgetBreakdown: [{ code: "acquisition.gold-standard", delta: 0, ruleRef: "WBR-WL-003", evidenceRef: "fixture#source" }],
    ruleRefs: [
      { id: "WBR-DUAL-001", target: "input.dualWield" },
      { id: "WBR-PIERCE-001", target: "input.pierce" },
      { id: "WBR-DMG-001", target: "input.damageType" },
      { id: "WBR-SHOT-001", target: "input.shotgun" },
      { id: "WBR-AMMO-001", target: "input.magPrice" },
      { id: "WBR-WL-003", target: "input.weightLayers" },
      { id: "WBR-CAT-001", target: "input.category" },
      { id: "WBR-AUTH-001", target: "input.formula" }
    ]
  };
  audit.ruleRefs.forEach((ref) => { ref.evidenceRef = "fixture#source"; });
  const ledger: WeaponBalanceAuditLedger = {
    formulaFamily: "weapon", schemaVersion: 1, workbookVersion: 1,
    workbookSha256: CURRENT_WEAPON_BALANCE_WORKBOOK_SHA256, records: [audit]
  };
  return { item, ledger, profile, audit };
}
const compare = (value: ReturnType<typeof fixture>, key = "data") => compareWeaponSummaryItem(value.item, key, value.ledger);

describe("offline AS2 summary model versus unchanged tool projection", () => {
  it("pins the reviewed source helpers and rejects source drift", () => {
    const source = fs.readFileSync(path.join(repo, AS2_WEAPON_SUMMARY_SOURCE), "utf8");
    expect(verifyAs2WeaponSummaryModelSource(source)).toMatch(/^[0-9a-f]{64}$/);
    expect(() => verifyAs2WeaponSummaryModelSource(source.replace('var parts:Array = ["weapon-v1"]', 'var parts:Array = ["weapon-next"]'))).toThrow(/source changed/);
  });

  it("matches the existing AS2 frozen fnv1a32:4bbce563 vector independently", () => {
    const value = fixture();
    value.item.name = "测试手枪";
    value.item.use = "手枪";
    Object.assign(at(value.item, "data"), { bullet: "普通子弹", clipname: "手枪弹药", split: 1, singleshoot: true });
    Object.assign(value.profile, { dualWield: 2, inputDigest: "fnv1a32:4bbce563" });
    expect(modelAs2WeaponSummary(value.item, value.item.balance, "data").projection)
      .toEqual({ state: "confirmed", weightLayers: 0, formula: 1, level: 10 });
  });

  it("compares visibility and all four fields for a confirmed exact generation", () => {
    const result = compare(fixture());
    expect(result.as2Model.projection).toEqual({ state: "confirmed", weightLayers: 0, formula: 1, level: 10 });
    expect(result.tool.issueCodes).toEqual([]);
    expect(result.tool.projection).toEqual(result.as2Model.projection);
    expect(result.equal).toBe(true);
  });

  it.each(["unresolved", "invalid"] as const)("preserves legal absent summaries for %s", (status) => {
    const value = fixture();
    Object.assign(value.profile, { status, displayEligible: false });
    Object.assign(value.audit, { status, displayEligible: false });
    const result = compare(value);
    expect(result.equal).toBe(true);
    expect(result.tool.projection).toBeNull();
    expect(result.as2Model.reason).toBe("not_display_eligible");
  });

  it("keeps a missing optional balance legal and does not use an embedded fallback", () => {
    const value = fixture();
    expect(modelAs2WeaponSummary(value.item, null, "data").projection).toBeNull();
    delete value.item.balance;
    expect(compare(value)).toMatchObject({ equal: true, tool: { projection: null, parseError: null } });
  });

  it("does not fall back for unknown/missing data_* and requires complete coverage", () => {
    const value = fixture();
    expect(compare(value, "data_future").as2Model.projection).toBeNull();
    value.item.data_ice = { power: 210 };
    expect(compare(value).as2Model.projection).toBeNull();
    expect(compare(value).tool.issueCodes).toContain("parse_error");
  });

  it("evaluates each data_* with shallow effective data and its own digest", () => {
    const value = fixture();
    value.item.data_ice = { power: 135 };
    const variant = { ...value.profile, auditRef: "weapon:投影手枪:data_ice" };
    const resolved = resolveWeaponItemEffectiveProfile(value.item, "data_ice", 1);
    variant.inputDigest = computeWeaponBalanceInputDigest(buildWeaponBalanceProfileDigestInput(resolved, variant));
    at(value.item, "balance", "profiles").data_ice = variant;
    value.ledger.records.push({ ...value.audit, ...variant, profileKey: "data_ice", sourceDigest: resolved.currentSourceDigest });
    expect(compare(value, "data_ice")).toMatchObject({ equal: true, as2Model: { projection: { level: 10 } } });
    at(value.item, "data_ice").power = 210;
    expect(compare(value, "data_ice")).toMatchObject({ equal: true, as2Model: { projection: null }, tool: { projection: null } });
    expect(compare(value).as2Model.projection).not.toBeNull();
  });

  it.each([null, "broken", [], [{}, {}]])("rejects corrupt/duplicate balance %j", (balance) => {
    const value = fixture();
    value.item.balance = balance;
    expect(compare(value)).toMatchObject({ equal: true, as2Model: { projection: null }, tool: { projection: null } });
  });

  it("reports singleton-array acceptance as a rule difference", () => {
    const value = fixture();
    value.item.balance = [value.item.balance];
    expect(compare(value)).toMatchObject({ equal: false, as2Model: { reason: "visible" }, tool: { projection: null } });
  });

  it("rejects duplicate profiles and duplicate ledger identities", () => {
    const value = fixture();
    at(value.item, "balance", "profiles").data = [value.profile, value.profile];
    expect(compare(value)).toMatchObject({ equal: true, as2Model: { projection: null }, tool: { projection: null } });
    value.ledger.records.push({ ...value.audit });
    expect(() => parseWeaponBalanceAuditLedgerFromXml(serializeWeaponBalanceAuditLedgerXml(value.ledger))).toThrow(/duplicate/);
  });

  it.each(["schemaVersion", "workbookVersion"])("rejects unknown %s without hiding the reason", (key) => {
    const value = fixture();
    at(value.item, "balance")[key] = 2;
    expect(compare(value)).toMatchObject({ equal: true, as2Model: { projection: null }, tool: { projection: null } });
  });

  it("reports tool boolean/workbook coercions that differ from AS2", () => {
    for (const mutate of [
      (value: ReturnType<typeof fixture>) => { at(value.item, "balance").workbookVersion = "1"; },
      (value: ReturnType<typeof fixture>) => { at(value.item, "balance", "profiles", "data").displayEligible = 1; }
    ]) {
      const value = fixture(); mutate(value);
      expect(compare(value)).toMatchObject({ equal: false, as2Model: { projection: null }, tool: { projection: { state: "confirmed" } } });
    }
  });

  it("retains parser differences for hexadecimal numbers and #text", () => {
    const hex = fixture();
    at(hex.item, "balance", "profiles", "data").magPrice = "0xc8";
    expect(compare(hex)).toMatchObject({ equal: false, as2Model: { reason: "visible" }, tool: { projection: null } });
    const text = fixture();
    at(text.item, "balance")["#text"] = "text";
    expect(compare(text)).toMatchObject({ equal: false, as2Model: { projection: null }, tool: { projection: { state: "confirmed" } } });
  });

  it("rejects stale inputDigest and all fourteen numeric input changes on both paths", () => {
    for (const key of ["level", "power", "interval", "capacity", "weight", "impact"]) {
      const value = fixture();
      const data = at(value.item, "data"); data[key] = Number(data[key]) + 1;
      expect(compare(value)).toMatchObject({ equal: true, as2Model: { reason: "input_digest_mismatch" }, tool: { projection: null } });
    }
    for (const key of ["dualWield", "pierce", "damageType", "shotgun", "magPrice", "weightLayers", "category", "formula"]) {
      const value = fixture();
      const profile = at(value.item, "balance", "profiles", "data"); profile[key] = Number(profile[key]) + 1;
      expect(compare(value)).toMatchObject({ equal: true, as2Model: { projection: null }, tool: { projection: null } });
    }
    const value = fixture(); value.profile.inputDigest = "fnv1a32:00000000";
    expect(compare(value).tool.projection).toBeNull();
  });

  it("invalidates the digest after identity, use, or mechanical input changes", () => {
    for (const key of ["bullet", "clipname", "split", "damagetype", "magictype", "singleshoot"]) {
      const value = fixture(); at(value.item, "data")[key] = "changed";
      expect(compare(value)).toMatchObject({ equal: true, as2Model: { reason: "input_digest_mismatch" }, tool: { projection: null } });
    }
    for (const key of ["name", "use"]) {
      const value = fixture(); value.item[key] = "changed";
      expect(compare(value)).toMatchObject({ equal: true, as2Model: { reason: "input_digest_mismatch" }, tool: { projection: null } });
    }
  });

  it("reports same-generation source-only mutation and ledger join mismatches", () => {
    for (const mutate of [
      (value: ReturnType<typeof fixture>) => { value.item.skill = { id: "changed-runtime-skill" }; },
      (value: ReturnType<typeof fixture>) => { value.audit.sourceDigest = `sha256:${"0".repeat(64)}`; },
      (value: ReturnType<typeof fixture>) => { value.audit.itemName = "另一把枪"; },
      (value: ReturnType<typeof fixture>) => { value.audit.weightLayers = 1; },
      (value: ReturnType<typeof fixture>) => { value.ledger.workbookSha256 = "0".repeat(64); }
    ]) {
      const value = fixture(); mutate(value);
      expect(compare(value)).toMatchObject({ equal: false, as2Model: { reason: "visible" }, tool: { projection: null } });
    }
    const value = fixture();
    expect(compareWeaponSummaryItem(value.item, "data")).toMatchObject({ equal: false, as2Model: { reason: "visible" }, tool: { projection: null } });
  });

  it("keeps the tool DPS gate visible after both digests are refreshed", () => {
    const value = fixture();
    at(value.item, "data").power = 100000;
    const resolved = resolveWeaponItemEffectiveProfile(value.item, "data", 1);
    value.profile.inputDigest = computeWeaponBalanceInputDigest(buildWeaponBalanceProfileDigestInput(resolved, value.profile));
    value.audit.inputDigest = value.profile.inputDigest;
    value.audit.sourceDigest = resolved.currentSourceDigest;
    const result = compare(value);
    expect(result).toMatchObject({ equal: false, as2Model: { reason: "visible" }, tool: { projection: null } });
    expect(result.tool.issueCodes).toContain("dps_residual_out_of_band");
  });
});
