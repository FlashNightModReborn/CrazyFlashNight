/** 近战武器（刀）公式引擎 — 对应 Excel "刀" sheet */

export interface MeleeInput {
  level: number;
  weight: number;
  damageTypeFactor: number; // 伤害类型系数
  weightLayers: number;     // 加权层数
  /** 种类系数 (用于定价，默认1) */
  categoryFactor?: number;
}

export interface MeleeOutput {
  recommendedSharpness: number; // 推荐锋利度
  recommendedGoldPrice: number;  // 推荐金币价格
  recommendedKPointPrice: number; // 推荐K点价格
}

export function computeMeleeRow(input: MeleeInput): MeleeOutput {
  const catFactor = input.categoryFactor ?? 1;
  const dtMult = Math.pow(1.6, input.damageTypeFactor - 1);

  const recommendedSharpness =
    (input.level * 10 * Math.pow(1.25, input.weightLayers) + input.weight * 3) / dtMult;

  // 近战使用武器定价公式 (dualWieldFactor=1)
  const recommendedGoldPrice = input.level * 3900 * Math.pow(1.6, input.weightLayers) * catFactor * dtMult;
  const recommendedKPointPrice = input.level * 120 * Math.pow(1.5, input.weightLayers) * catFactor * dtMult;

  return { recommendedSharpness, recommendedGoldPrice, recommendedKPointPrice };
}
