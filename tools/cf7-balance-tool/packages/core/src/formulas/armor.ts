/** 防具公式引擎 — 对应 Excel "防具" sheet */

export type ArmorType = "standard" | "glove" | "necklace";

export interface ArmorInput {
  level: number;
  defence: number;
  hp: number;
  mp: number;
  damageBonus: number;
  weaponBonus: number; // 刀/枪总加成
  weight: number;
  punchBonus: number; // 空手加成
  magicDefence: number; // 法抗
  extraWeightLayers: number;
  type?: ArmorType;
  /** 种类系数 (用于定价，默认1) */
  categoryFactor?: number;
  /** 伤害类型系数 (用于定价，默认1) */
  damageTypeFactor?: number;
}

export interface ArmorOutput {
  currentScore: number;   // 当前总分
  balanceScore: number;   // 平衡总分
  weightedScore: number;  // 加权总分
  magicDefAvgCap: number; // 法抗均值上限
  magicDefMaxCap: number; // 法抗最高上限
  recommendedGoldPrice: number;  // 推荐金币价格
  recommendedKPointPrice: number; // 推荐K点价格
}

function penalize(value: number, threshold: number): number {
  return value < threshold ? value : value + 2 * (value - threshold);
}

export function computeArmorRow(input: ArmorInput): ArmorOutput {
  const type = input.type ?? "standard";
  const catFactor = input.categoryFactor ?? 1;
  const dtFactor = input.damageTypeFactor ?? 1;

  // 项链: 平衡总分不含重量
  const balanceScore = type === "necklace"
    ? input.level * 20
    : input.level * 20 + input.weight * 10;
  const weightedScore = balanceScore * Math.pow(1.25, input.extraWeightLayers);

  // 偏科阈值: 手套用 0.7/0.3, 其他用 0.5/0.25
  const dmgThreshold = type === "glove" ? weightedScore * 0.7 : weightedScore * 0.5;
  const weaponThreshold = type === "glove" ? weightedScore * 0.3 : weightedScore * 0.25;
  const half = weightedScore * 0.5;

  const defPart = input.defence * 2;
  const hpPart = penalize(input.hp, half);
  const mpPart = penalize(input.mp, half);

  const dmgBase = input.damageBonus * 3 + input.weaponBonus * 3;
  const dmgPart = penalize(dmgBase, dmgThreshold);
  const weaponPenalty = input.weaponBonus * 3 > weaponThreshold
    ? 2 * (input.weaponBonus * 3 - weaponThreshold)
    : 0;

  // 手套: 空手无惩罚
  const punchPart = type === "glove"
    ? input.punchBonus * 4
    : penalize(input.punchBonus * 4, half);

  const currentScore = defPart + hpPart + mpPart + dmgPart + weaponPenalty + punchPart + input.magicDefence;

  // 项链: 法抗上限为0
  const magicDefAvgCap = type === "necklace" ? 0 : 10 + input.level * 0.2;
  const magicDefMaxCap = type === "necklace" ? 0 : 25 + input.level * 0.2;

  // 推荐价格
  const dtMult = Math.pow(1.6, dtFactor - 1);
  const recommendedGoldPrice = input.level * 2600 * Math.pow(1.6, input.extraWeightLayers) * catFactor * dtMult;
  const recommendedKPointPrice = input.level * 90 * Math.pow(1.5, input.extraWeightLayers) * dtMult;

  return {
    currentScore,
    balanceScore,
    weightedScore,
    magicDefAvgCap,
    magicDefMaxCap,
    recommendedGoldPrice,
    recommendedKPointPrice,
  };
}
