import { describe, expect, it } from "vitest";

import {
  canonicalizeArmorBalanceInput,
  computeArmorBalanceInputDigest,
  isArmorBalanceInputDigest,
  isArmorBalanceSourceDigest
} from "../../src/index.js";

describe("armor balance v1 input digest", () => {
  // 钛合金61式头部装甲的实读数值（data/items/防具_40+级.xml）+ plan 人工输入。
  const source = {
    formulaFamily: "armor",
    formulaVersion: 1,
    itemName: "钛合金61式头部装甲",
    level: 45,
    defence: 500,
    hp: 500,
    mp: 150,
    damage: 80,
    weaponBonus: 0,
    weight: 8,
    punch: 0,
    magicDefence: 30,
    weightLayers: 3,
    priceLayers: 1,
    category: 1,
    damageTypeFactor: 1,
    adoptedGoldPrice: 200000
  };

  it("serializes a fixed key order JSON canonical string", () => {
    expect(canonicalizeArmorBalanceInput(source)).toBe(
      '{"formulaFamily":"armor","formulaVersion":1,"itemName":"钛合金61式头部装甲","level":45,"defence":500,"hp":500,"mp":150,"damage":80,"weaponBonus":0,"weight":8,"punch":0,"magicDefence":30,"weightLayers":3,"priceLayers":1,"category":1,"damageTypeFactor":1,"adoptedGoldPrice":200000}'
    );
  });

  it("exposes a fixed cross-stack digest vector", () => {
    expect(computeArmorBalanceInputDigest(source)).toBe("fnv1a32:017ded45");
    expect(isArmorBalanceInputDigest(computeArmorBalanceInputDigest(source))).toBe(true);
    expect(isArmorBalanceInputDigest("fnv1a32:017DED45")).toBe(false);
    expect(isArmorBalanceSourceDigest(`sha256:${"a".repeat(64)}`)).toBe(true);
  });

  it("binds item stats and human inputs against silent drift", () => {
    const baseline = computeArmorBalanceInputDigest(source);
    expect(computeArmorBalanceInputDigest({ ...source, defence: 501 })).not.toBe(baseline);
    expect(computeArmorBalanceInputDigest({ ...source, weightLayers: 2 })).not.toBe(baseline);
    expect(computeArmorBalanceInputDigest({ ...source, adoptedGoldPrice: 187200 })).not.toBe(baseline);
    expect(computeArmorBalanceInputDigest({ ...source, itemName: "钛合金61式胸甲" })).not.toBe(baseline);
  });

  it("rejects incomplete or non-finite input", () => {
    expect(() => canonicalizeArmorBalanceInput({ ...source, level: Number.NaN })).toThrow();
    expect(() =>
      canonicalizeArmorBalanceInput({ ...source, itemName: "" })
    ).toThrow();
  });
});
