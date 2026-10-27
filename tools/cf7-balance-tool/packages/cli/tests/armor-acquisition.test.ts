import { describe, expect, it } from "vitest";
import { armorAcquisitionFile, armorItemScope, readArmorKPointPrices } from "../src/armor-acquisition.js";

describe("armor K-point acquisition evidence", () => {
  it("requires an exact explicit scope and keeps full coverage as the default", () => {
    expect(armorItemScope([], ["甲", "乙"])).toBeUndefined();
    expect([...armorItemScope(["--items", "甲,乙"], ["甲", "乙"])!]).toEqual(["甲", "乙"]);
    for (const request of ["甲,未知", "甲,甲", "甲,", ""]) {
      expect(() => armorItemScope(["--items", request], ["甲", "乙"])).toThrow();
    }
  });
  const ref = "data/crafting/进阶防具.json#craft.unified61.chest";
  const recipe = { recipeId: "craft.unified61.chest", name: "统合61式胸甲", price: 60000, kprice: 5400 };
  it("reads the exact paid recipe, never its gold price or a different recipe for the same item", () => {
    expect(armorAcquisitionFile(ref)).toBe("data/crafting/进阶防具.json");
    const prices = readArmorKPointPrices([{ ...recipe, recipeId: "other", kprice: 1 }, recipe], ref);
    expect(prices.get(recipe.name)).toBe(5400);
  });
  it("retains the ordinary K shop format", () => {
    expect(readArmorKPointPrices([{ item: "钛合金61式胸甲", price: 6000 }], "data/kshop/A兵团官方周边直营店.json").get("钛合金61式胸甲")).toBe(6000);
    expect(readArmorKPointPrices([{ item: "钛合金61式胸甲", price: "6000" }], "data/kshop/A兵团官方周边直营店.json").get("钛合金61式胸甲")).toBe(6000);
  });
  it("rejects absent and ambiguous recipe identities", () => {
    expect(() => readArmorKPointPrices([recipe], "data/crafting/进阶防具.json")).toThrow(/recipeId/);
    expect(() => readArmorKPointPrices([], ref)).toThrow(/唯一/);
    expect(() => readArmorKPointPrices([recipe, recipe], ref)).toThrow(/重复/);
  });
  it("does not accept gold as K points or silently coerce malformed prices", () => {
    for (const kprice of [undefined, -1, 1.5, "5400", Infinity, NaN]) {
      expect(() => readArmorKPointPrices([{ ...recipe, kprice }], ref)).toThrow(/非负整数/);
    }
  });
  it("rejects evidence outside supported acquisition tables", () => {
    expect(() => armorAcquisitionFile("../secret.json")).toThrow();
    expect(() => armorAcquisitionFile("data/crafting/../../outside.json")).toThrow();
  });
});
