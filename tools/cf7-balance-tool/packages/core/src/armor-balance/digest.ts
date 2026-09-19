import { fnv1a32Utf16 } from "../weapon-balance/digest.js";

export const ARMOR_BALANCE_INPUT_DIGEST_PREFIX = "fnv1a32:";

export const ARMOR_BALANCE_INPUT_DIGEST_KEYS = [
  "formulaFamily",
  "formulaVersion",
  "itemName",
  "level",
  "defence",
  "hp",
  "mp",
  "damage",
  "weaponBonus",
  "weight",
  "punch",
  "magicDefence",
  "weightLayers",
  "priceLayers",
  "category",
  "damageTypeFactor",
  "adoptedGoldPrice"
] as const;

export type ArmorBalanceInputDigestKey =
  (typeof ARMOR_BALANCE_INPUT_DIGEST_KEYS)[number];

export interface ArmorBalanceInputDigestSource {
  formulaFamily: string;
  formulaVersion: number;
  itemName: string;
  level: number;
  defence: number;
  hp: number;
  mp: number;
  damage: number;
  weaponBonus: number;
  weight: number;
  punch: number;
  magicDefence: number;
  weightLayers: number;
  priceLayers: number;
  category: number;
  damageTypeFactor: number;
  adoptedGoldPrice: number;
}

/**
 * canonical 串是固定键序的 JSON.stringify；数值全部从 item 块实读，
 * 任何数值或人工输入漂移都会改变 digest。
 */
export function canonicalizeArmorBalanceInput(
  source: ArmorBalanceInputDigestSource
): string {
  const ordered: Record<string, unknown> = {};
  for (const key of ARMOR_BALANCE_INPUT_DIGEST_KEYS) {
    const value = source[key];
    if (typeof value === "number") {
      if (!Number.isFinite(value)) {
        throw new Error(`armor balance digest: ${key} 需要有限数值`);
      }
    } else if (typeof value === "string") {
      if (value.trim() === "") {
        throw new Error(`armor balance digest: ${key} 需要非空文本`);
      }
    } else {
      throw new Error(`armor balance digest: ${key} 缺失`);
    }
    ordered[key] = value;
  }
  return JSON.stringify(ordered);
}

export function computeArmorBalanceInputDigest(
  source: ArmorBalanceInputDigestSource
): string {
  return `${ARMOR_BALANCE_INPUT_DIGEST_PREFIX}${fnv1a32Utf16(
    canonicalizeArmorBalanceInput(source)
  )}`;
}

export function isArmorBalanceInputDigest(value: string): boolean {
  return /^fnv1a32:[0-9a-f]{8}$/.test(value);
}

export function isArmorBalanceSourceDigest(value: string): boolean {
  return /^sha256:[0-9a-f]{64}$/.test(value);
}
