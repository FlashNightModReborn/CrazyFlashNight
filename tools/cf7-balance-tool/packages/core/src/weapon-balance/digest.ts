import type { WeaponBalanceFormulaInputs } from "./record.js";

export const WEAPON_BALANCE_INPUT_DIGEST_PREFIX = "fnv1a32:";
export const WEAPON_BALANCE_INPUT_CANONICAL_PREFIX = "weapon-v1";

export const WEAPON_BALANCE_INPUT_DIGEST_KEYS = [
  "itemName",
  "profileKey",
  "workbookVersion",
  "use",
  "bullet",
  "clipname",
  "split",
  "damagetype",
  "magictype",
  "singleshoot",
  "level",
  "power",
  "interval",
  "capacity",
  "weight",
  "impact",
  "dualWield",
  "pierce",
  "damageType",
  "shotgun",
  "magPrice",
  "weightLayers",
  "category",
  "formula"
] as const;

export const WEAPON_BALANCE_NUMERIC_DIGEST_KEYS = [
  "workbookVersion",
  "level",
  "power",
  "interval",
  "capacity",
  "weight",
  "impact",
  "dualWield",
  "pierce",
  "damageType",
  "shotgun",
  "magPrice",
  "weightLayers",
  "category",
  "formula"
] as const;

export type WeaponBalanceInputDigestKey =
  (typeof WEAPON_BALANCE_INPUT_DIGEST_KEYS)[number];

export type WeaponBalanceInputDigestSource = Partial<
  Record<WeaponBalanceInputDigestKey, unknown>
>;

export interface WeaponBalanceRuntimeInputs {
  level: number;
  power: number;
  interval: number;
  capacity: number;
  weight: number;
  impact: number;
}

export interface WeaponBalanceMechanicalInputs {
  bullet?: unknown;
  clipname?: unknown;
  split?: unknown;
  damagetype?: unknown;
  magictype?: unknown;
  singleshoot?: unknown;
}

export interface WeaponBalanceDigestContext
  extends WeaponBalanceRuntimeInputs,
    WeaponBalanceMechanicalInputs {
  itemName: string;
  profileKey: string;
  workbookVersion: number;
  use?: unknown;
}

/**
 * v1 canonical 串同时绑定物品/profile/工作簿版本身份、关键机械源、6 个
 * 运行数值和 8 个公式数值。每个值都带 UTF-16 code-unit 长度，避免分隔符歧义。
 */
export function canonicalizeWeaponBalanceInput(
  source: WeaponBalanceInputDigestSource
): string {
  const parts = WEAPON_BALANCE_INPUT_DIGEST_KEYS.map((key) => {
    const value = isNumericDigestKey(key)
      ? normalizeDigestNumber(source[key])
      : normalizeDigestText(source[key]);
    return `${key}#${value.length}=${value}`;
  });
  return `${WEAPON_BALANCE_INPUT_CANONICAL_PREFIX}|${parts.join("|")}`;
}

/** FNV-1a 32-bit，逐个 UTF-16 code unit 处理，便于 AS2 无损复算。 */
export function fnv1a32Utf16(value: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

export function computeWeaponBalanceInputDigest(
  source: WeaponBalanceInputDigestSource
): string {
  return `${WEAPON_BALANCE_INPUT_DIGEST_PREFIX}${fnv1a32Utf16(
    canonicalizeWeaponBalanceInput(source)
  )}`;
}

export function buildWeaponBalanceInputDigestSource(
  context: WeaponBalanceDigestContext,
  inputs: WeaponBalanceFormulaInputs
): WeaponBalanceInputDigestSource {
  return {
    itemName: context.itemName,
    profileKey: context.profileKey,
    workbookVersion: context.workbookVersion,
    use: context.use,
    bullet: context.bullet,
    clipname: context.clipname,
    split: context.split,
    damagetype: context.damagetype,
    magictype: context.magictype,
    singleshoot: context.singleshoot,
    level: context.level,
    power: context.power,
    interval: context.interval,
    capacity: context.capacity,
    weight: context.weight,
    impact: context.impact,
    dualWield: inputs.dualWield,
    pierce: inputs.pierce,
    damageType: inputs.damageType,
    shotgun: inputs.shotgun,
    magPrice: inputs.magPrice,
    weightLayers: inputs.weightLayers,
    category: inputs.category,
    formula: inputs.formula
  };
}

export function hasCompleteWeaponBalanceDigestInput(
  source: WeaponBalanceInputDigestSource
): boolean {
  if (normalizeDigestText(source.itemName) === "") return false;
  if (normalizeDigestText(source.profileKey) === "") return false;
  return WEAPON_BALANCE_NUMERIC_DIGEST_KEYS.every(
    (key) => normalizeDigestNumber(source[key]) !== ""
  );
}

export function isWeaponBalanceInputDigest(value: string): boolean {
  return /^fnv1a32:[0-9a-f]{8}$/.test(value);
}

export function isWeaponBalanceSourceDigest(value: string): boolean {
  return /^sha256:[0-9a-f]{64}$/.test(value);
}

function isNumericDigestKey(
  key: WeaponBalanceInputDigestKey
): key is (typeof WEAPON_BALANCE_NUMERIC_DIGEST_KEYS)[number] {
  return (WEAPON_BALANCE_NUMERIC_DIGEST_KEYS as readonly string[]).includes(key);
}

function normalizeDigestNumber(value: unknown): string {
  if (value === undefined || value === null || value === "") return "";
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? String(parsed) : "";
}

function normalizeDigestText(value: unknown): string {
  if (value === undefined || value === null) return "";
  if (
    typeof value !== "string" &&
    typeof value !== "number" &&
    typeof value !== "boolean"
  ) {
    return "";
  }
  return String(value);
}
