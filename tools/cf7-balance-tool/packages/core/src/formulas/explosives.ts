/** 爆炸类公式引擎 — 对应 Excel "爆炸类" sheet */

export interface ExplosivesInput {
  magPrice: number;   // 弹夹价格
  magSize: number;    // 弹容量
  level: number;      // 限制等级
  weightLayers: number; // 加权层级
}

export interface ExplosivesOutput {
  recommendedPower: number; // 推荐单发威力
  recommendedGoldPrice: number;  // 推荐金币价格
  recommendedKPointPrice: number; // 推荐K点价格
}

export function computeExplosivesRow(input: ExplosivesInput): ExplosivesOutput {
  const raw =
    2.1 *
    input.magPrice *
    Math.pow(1.25, input.weightLayers) *
    Math.sqrt(input.level / 30) /
    Math.pow(input.magSize + 0.5, 0.95);

  const cap = input.level * 400;

  const recommendedPower = raw <= cap
    ? raw
    : cap + 0.2 * cap * (1 - Math.exp(-(raw - cap) / cap));

  // 爆炸类使用武器定价公式 (dualWieldFactor=1, categoryFactor=1, damageTypeFactor=1)
  const recommendedGoldPrice = input.level * 3900 * Math.pow(1.6, input.weightLayers);
  const recommendedKPointPrice = input.level * 120 * Math.pow(1.5, input.weightLayers);

  return { recommendedPower, recommendedGoldPrice, recommendedKPointPrice };
}
