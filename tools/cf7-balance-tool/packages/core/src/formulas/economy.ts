/** 经济公式引擎 — 对应 Excel "装备价格" / "合成表成本" / "副本收益" sheets */

// ─── 装备价格 ───

export interface WeaponPriceInput {
  level: number;
  weightLayers: number;     // 加权层数
  dualWieldFactor: number;  // 双枪系数
  categoryFactor: number;   // 种类系数
  damageTypeFactor: number; // 伤害类型系数
}

export interface EquipmentPriceOutput {
  goldPrice: number;
  kPointPrice: number;
  exchangeRate: number; // 金币/k点换算
}

export function computeWeaponPrice(input: WeaponPriceInput): EquipmentPriceOutput {
  const dtMult = Math.pow(1.6, input.damageTypeFactor - 1);
  const goldPrice = input.level * 3900 * Math.pow(1.6, input.weightLayers) * input.categoryFactor * dtMult / input.dualWieldFactor;
  const kPointPrice = input.level * 120 * Math.pow(1.5, input.weightLayers) * input.categoryFactor * dtMult / input.dualWieldFactor;
  return { goldPrice, kPointPrice, exchangeRate: goldPrice / kPointPrice };
}

export interface ArmorPriceInput {
  level: number;
  weightLayers: number;
  categoryFactor: number;
  damageTypeFactor: number;
}

export function computeArmorPrice(input: ArmorPriceInput): EquipmentPriceOutput {
  const dtMult = Math.pow(1.6, input.damageTypeFactor - 1);
  const goldPrice = input.level * 2600 * Math.pow(1.6, input.weightLayers) * input.categoryFactor * dtMult;
  const kPointPrice = input.level * 90 * Math.pow(1.5, input.weightLayers) * dtMult;
  return { goldPrice, kPointPrice, exchangeRate: goldPrice / kPointPrice };
}

// ─── 合成表成本 ───

export interface SynthesisInput {
  level: number;
  weightLayers: number;
  raceFactor: number;  // 种族系数
  goldCost: number;
  kPointCost: number;
  materialPrice: number;
  equipmentPrice: number; // 装备折算价格
  dropPrice: number;      // 掉落物折算价格
}

export interface SynthesisOutput {
  currentCost: number;  // 当前成本
  balanceCost: number;  // 平衡成本
  weightedCost: number; // 加权成本
}

export function computeSynthesis(input: SynthesisInput): SynthesisOutput {
  const currentCost = input.goldCost + input.kPointCost * 30 + input.materialPrice + input.equipmentPrice + input.dropPrice;
  const balanceCost = input.level * 2000 * input.raceFactor;
  const weightedCost = input.weightLayers >= 1
    ? balanceCost * Math.pow(1.6, input.weightLayers - 1)
    : balanceCost * Math.pow(1.6, input.weightLayers * 3 - 3);

  return { currentCost, balanceCost, weightedCost };
}

// ─── 副本收益 ───

export interface DungeonInput {
  stageFactor: number;  // 阶段系数
  lengthFactor: number; // 长度系数
  diffFactor: number;   // 难度系数
  goldReward: number;
  consumableValue: number; // 消耗品等效价值
  exp: number;
  equipmentValue: number;
  enhanceStone: number; // 强化石
}

export interface DungeonOutput {
  currentReward: number;  // 当前收益
  expectedReward: number; // 期望收益
}

export function computeDungeonReward(input: DungeonInput): DungeonOutput {
  const stoneValue = input.stageFactor > 4
    ? input.enhanceStone * 300 / (input.stageFactor - 3)
    : input.enhanceStone * 300;

  const currentReward =
    input.goldReward +
    input.consumableValue * 0.5 +
    input.exp / input.stageFactor +
    stoneValue +
    input.equipmentValue * 0.5;

  const expectedReward = input.stageFactor * 13000 * input.lengthFactor * input.diffFactor;

  return { currentReward, expectedReward };
}
