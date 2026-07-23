import { describe, expect, it } from "vitest";

import {
  canonicalizeWeaponBalanceInput,
  computeWeaponBalanceInputDigest,
  fnv1a32Utf16,
  hasCompleteWeaponBalanceDigestInput
} from "../../src/index.js";

describe("weapon balance v1 input digest", () => {
  const source = {
    itemName: "测试手枪",
    profileKey: "data",
    workbookVersion: 1,
    use: "手枪",
    bullet: "普通子弹",
    clipname: "手枪弹药",
    split: 1,
    damagetype: undefined,
    magictype: undefined,
    singleshoot: true,
    level: "10",
    power: 135,
    interval: 110,
    capacity: 30,
    weight: 4,
    impact: 20,
    dualWield: 2,
    pierce: 1,
    damageType: 1,
    shotgun: 1,
    magPrice: 200,
    weightLayers: 0,
    category: 1,
    formula: 1
  };

  it("uses fixed identity/mechanics/numeric order with UTF-16 lengths", () => {
    expect(canonicalizeWeaponBalanceInput(source)).toBe(
      "weapon-v1|itemName#4=测试手枪|profileKey#4=data|workbookVersion#1=1|use#2=手枪|bullet#4=普通子弹|clipname#4=手枪弹药|split#1=1|damagetype#0=|magictype#0=|singleshoot#4=true|level#2=10|power#3=135|interval#3=110|capacity#2=30|weight#1=4|impact#2=20|dualWield#1=2|pierce#1=1|damageType#1=1|shotgun#1=1|magPrice#3=200|weightLayers#1=0|category#1=1|formula#1=1"
    );
  });

  it("hashes UTF-16 code units and exposes a fixed cross-stack vector", () => {
    expect(fnv1a32Utf16("hello")).toBe("4f9f2cab");
    expect(computeWeaponBalanceInputDigest(source)).toBe("fnv1a32:4bbce563");
  });

  it("requires identity plus workbook version and all fourteen formula/runtime numbers", () => {
    expect(hasCompleteWeaponBalanceDigestInput(source)).toBe(true);
    expect(
      hasCompleteWeaponBalanceDigestInput({ ...source, impact: Infinity })
    ).toBe(false);
    expect(
      hasCompleteWeaponBalanceDigestInput({ ...source, profileKey: "" })
    ).toBe(false);
    expect(
      hasCompleteWeaponBalanceDigestInput({
        ...source,
        workbookVersion: undefined
      })
    ).toBe(false);
  });

  it("keeps absent strings empty and binds mechanics against silent drift", () => {
    const baseline = computeWeaponBalanceInputDigest(source);
    expect(
      computeWeaponBalanceInputDigest({ ...source, bullet: "穿刺子弹" })
    ).not.toBe(baseline);
    expect(
      computeWeaponBalanceInputDigest({ ...source, workbookVersion: 2 })
    ).not.toBe(baseline);
    expect(canonicalizeWeaponBalanceInput({})).toContain("itemName#0=");
  });
});
