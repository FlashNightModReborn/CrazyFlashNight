/** 近战武器（刀）公式引擎 — 对应 Excel "刀" sheet */

export interface MeleeInput {
  level: number;
  weight: number;
  damageTypeFactor: number; // 伤害类型系数
  weightLayers: number;     // 加权层数
}

export interface MeleeOutput {
  recommendedSharpness: number; // 推荐锋利度
}

export function computeMeleeRow(input: MeleeInput): MeleeOutput {
  const recommendedSharpness =
    (input.level * 10 * Math.pow(1.25, input.weightLayers) + input.weight * 3) /
    Math.pow(1.6, input.damageTypeFactor - 1);

  return { recommendedSharpness };
}
