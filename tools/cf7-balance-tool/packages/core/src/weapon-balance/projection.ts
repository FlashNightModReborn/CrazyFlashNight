import {
  WEAPON_BALANCE_FORMULA_VERSION,
  type WeaponBalanceProfile
} from "./record.js";
import {
  validateWeaponBalanceRecord,
  type WeaponBalanceValidationOptions
} from "./validation.js";

export interface PlayerWeaponBalanceProjectionOptions
  extends WeaponBalanceValidationOptions {}

/** 当前唯一允许进入玩家协议的 exact 四字段投影。 */
export interface PlayerWeaponBalanceProjection {
  state: "confirmed";
  weightLayers: number;
  formula: typeof WEAPON_BALANCE_FORMULA_VERSION;
  level: number;
}

/**
 * 审计失败、状态不可见或缺少已验证 runtimeInputs 时统一返回 null。
 * 预算明细、条款、DPS 和强度档位只留在审计工具，不属于玩家协议。
 */
export function derivePlayerWeaponBalanceProjection(
  profile: WeaponBalanceProfile,
  options: PlayerWeaponBalanceProjectionOptions = {}
): PlayerWeaponBalanceProjection | null {
  if (!options.runtimeInputs) return null;
  const validation = validateWeaponBalanceRecord(profile, options);
  if (!validation.displayEligible) return null;

  return {
    state: "confirmed",
    weightLayers: profile.weightLayers,
    formula: WEAPON_BALANCE_FORMULA_VERSION,
    level: options.runtimeInputs.level
  };
}
