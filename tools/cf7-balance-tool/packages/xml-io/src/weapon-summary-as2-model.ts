import { createHash } from "node:crypto";
import type { PlayerWeaponBalanceProjection } from "@cf7-balance-tool/core";

/** Reviewed source model, not an AVM1 execution or an alternative production reader. */
export const AS2_WEAPON_SUMMARY_SOURCE =
  "scripts/类定义/org/flashNight/arki/item/InventoryPanelService.as";
export const AS2_WEAPON_SUMMARY_SOURCE_SHA256 =
  "2344e6ccba4014187045ce29a0a513d2b5b53129e3d002b7e335168b84fabf39";
const INPUT_FIELDS = [
  "dualWield", "pierce", "damageType", "shotgun", "magPrice", "weightLayers", "category", "formula"
] as const;
const DATA_NUMBERS = ["level", "power", "interval", "capacity", "weight", "impact"] as const;
const MECHANICS = ["bullet", "clipname", "split", "damagetype", "magictype", "singleshoot"] as const;
const PROFILE_FIELDS = [...INPUT_FIELDS, "status", "displayEligible", "inputDigest", "auditRef"];

type Node = Record<string, unknown>;
export interface As2WeaponSummaryModelResult {
  projection: PlayerWeaponBalanceProjection | null;
  reason: string;
}

/** Fail on source drift instead of silently claiming the old model describes new AS2. */
export function verifyAs2WeaponSummaryModelSource(source: string): string {
  const text = source.replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n");
  const constantsStart = text.indexOf("    private static var _weaponBalanceWorkbookVersion");
  const constantsEnd = text.indexOf("    private static var _containerEpochs", constantsStart);
  const modelStart = text.indexOf("    public static function buildBalanceSummary");
  const modelEnd = text.indexOf("    /** 将存档中的插件名", modelStart);
  if ([constantsStart, constantsEnd, modelStart, modelEnd].some((offset) => offset < 0)) {
    throw new Error("AS2 summary source boundaries changed; review the offline model");
  }
  const digest = createHash("sha256")
    .update(text.slice(constantsStart, constantsEnd) + text.slice(modelStart, modelEnd), "utf8")
    .digest("hex");
  if (digest !== AS2_WEAPON_SUMMARY_SOURCE_SHA256) {
    throw new Error(`AS2 summary source changed (${digest}); review the offline model`);
  }
  return digest;
}

/** A direct TS model of buildBalanceSummary and its private helpers. */
export function modelAs2WeaponSummary(
  rawItem: unknown, balanceRoot: unknown, profileKey: string
): As2WeaponSummaryModelResult {
  const hidden = (reason: string): As2WeaponSummaryModelResult => ({ projection: null, reason });
  const item = object(rawItem);
  if (!item || item.type !== "武器") return hidden("not_weapon");
  if (!profileKeyValid(profileKey)) return hidden("invalid_profile_key");
  const balance = single(balanceRoot);
  if (!balance || !only(balance, ["formulaFamily", "schemaVersion", "workbookVersion", "profiles"])) {
    return hidden("missing_or_malformed_balance");
  }
  if (!finite(balance.schemaVersion) || Number(balance.schemaVersion) !== 1
    || balance.formulaFamily !== "weapon" || typeof balance.workbookVersion !== "number"
    || !finite(balance.workbookVersion) || balance.workbookVersion !== 1) {
    return hidden("family_schema_or_workbook");
  }
  const profiles = single(balance.profiles);
  if (!profiles) return hidden("malformed_profiles");
  const dataKeys = Object.keys(item).filter(profileKeyValid);
  if (dataKeys.length === 0 || dataKeys.some((key) => !single(item[key]) || !own(profiles, key)
      || !single(profiles[key]))) return hidden("profile_coverage");
  const keys = Object.keys(profiles);
  if (keys.length !== dataKeys.length || keys.some((key) => !profileKeyValid(key)
      || !own(item, key) || !single(item[key]) || !strictProfile(single(profiles[key])))) {
    return hidden("profile_coverage_or_shape");
  }
  const profile = single(profiles[profileKey]);
  if (!profile || profile.status !== "confirmed" || profile.displayEligible !== true
      || !textPresent(profile.auditRef)) return hidden("not_display_eligible");
  const base = single(item.data);
  if (!base) return hidden("missing_base_data");
  const data: Node = {};
  // AS2 uses for-in, including inherited data fields; coverage above uses own fields.
  for (const key in base) data[key] = base[key];
  if (profileKey !== "data") {
    const variant = single(item[profileKey]);
    if (!variant) return hidden("missing_selected_variant");
    for (const key in variant) data[key] = variant[key];
  }
  if (text(item.name) === "" || DATA_NUMBERS.some((key) => !finite(data[key]))
    || INPUT_FIELDS.some((key) => !finite(profile[key]))) return hidden("incomplete_digest_input");
  const parts = ["weapon-v1"];
  const append = (key: string, value: string): void => { parts.push(`${key}#${value.length}=${value}`); };
  append("itemName", text(item.name));
  append("profileKey", profileKey);
  append("workbookVersion", String(Number(balance.workbookVersion)));
  append("use", text(item.use));
  for (const key of MECHANICS) append(key, text(data[key]));
  for (const key of DATA_NUMBERS) append(key, String(Number(data[key])));
  for (const key of INPUT_FIELDS) append(key, String(Number(profile[key])));
  // Deliberately use AS2's shift/add implementation, independent of tool Math.imul.
  let hash = 2166136261;
  const canonical = parts.join("|");
  for (let index = 0; index < canonical.length; index++) {
    hash ^= canonical.charCodeAt(index);
    hash = hash + (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
    hash |= 0;
  }
  const digest = `fnv1a32:${(hash >>> 0).toString(16).padStart(8, "0")}`;
  if (profile.inputDigest !== digest) return hidden("input_digest_mismatch");
  return {
    projection: { state: "confirmed", weightLayers: Number(profile.weightLayers), formula: 1,
      level: Number(data.level) },
    reason: "visible"
  };
}

function strictProfile(profile: Node | null): boolean {
  return Boolean(profile && only(profile, PROFILE_FIELDS)
    && INPUT_FIELDS.every((key) => finite(profile[key])) && Number(profile.formula) === 1
    && textPresent(profile.inputDigest) && textPresent(profile.auditRef)
    && ["confirmed", "unresolved", "invalid"].includes(String(profile.status))
    && (profile.displayEligible === true || profile.displayEligible === false)
    && (profile.status === "confirmed" || profile.displayEligible === false));
}
function only(value: Node, keys: readonly string[]): boolean {
  return Object.keys(value).every((key) => keys.includes(key));
}
function own(value: Node, key: string): boolean { return Object.prototype.hasOwnProperty.call(value, key); }
function profileKeyValid(key: string): boolean { return key === "data" || (key.startsWith("data_") && key.length > 5); }
function object(value: unknown): Node | null {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Node : null;
}
function single(value: unknown): Node | null {
  return object(Array.isArray(value) ? (value.length === 1 ? value[0] : null) : value);
}
function textPresent(value: unknown): value is string {
  return typeof value === "string" && [...value].some((char) => char.charCodeAt(0) > 32 && char.charCodeAt(0) !== 160);
}
function finite(value: unknown): boolean {
  return (typeof value === "number" || (typeof value === "string" && textPresent(value)))
    && Number.isFinite(Number(value));
}
function text(value: unknown): string {
  return ["string", "number", "boolean"].includes(typeof value) ? String(value) : "";
}
