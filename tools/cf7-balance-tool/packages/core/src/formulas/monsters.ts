/** 怪物面板公式引擎 — 对应 Excel "怪物大致面板" sheet */

export interface MonsterInput {
  stage: number;           // C: 阶段
  tierFactor: number;      // D: 档次系数
  growthFactor: number;    // E: 成长系数
  atkSpeedFactor: number;  // F: 攻速系数
  atkMultiplier: number;   // G: 攻击倍率
  segmentFactor: number;   // H: 段数系数
  speedFactor: number;     // I: 速度系数
  highAtkFactor: number;   // J: 高攻低血防系数
  superArmorFactor: number; // K: 霸体系数
  highDefFactor: number;   // L: 高防低血系数
}

export interface MonsterOutput {
  atkMin: number;       // 空手攻击MIN
  atkMax: number;       // 空手攻击MAX
  hpMin: number;        // HP最小值
  hpMax: number;        // HP最大值
  defMin: number;       // 防御力MIN
  defMax: number;       // 防御力MAX
  expMin: number;       // 经验MIN
  expMax: number;       // 经验MAX
  goldPrice: number;    // 金币价格
  kPointPrice: number;  // K点价格
}

export function computeMonsterRow(input: MonsterInput): MonsterOutput {
  const { stage: C, tierFactor: D, growthFactor: E, atkSpeedFactor: F,
          atkMultiplier: G, segmentFactor: H, speedFactor: I,
          highAtkFactor: J, superArmorFactor: K, highDefFactor: L } = input;

  const sqrtE = Math.sqrt(E);
  const growth125 = Math.pow(1.25, 1 - E);
  const growth130 = Math.pow(1.3, 1 - E);
  const atkSpeedMod = Math.pow(1.2, F - 3);
  const speedMod11 = Math.pow(1.1, I - 2); // atk/def/exp use 1.1 base
  const speedMod12 = Math.pow(1.2, I - 2); // HP uses 1.2 base
  const sqrtH = Math.sqrt(H);

  // N: 空手攻击MIN
  const atkMin = 5 + C * D * 9 * growth125 * J / (G * sqrtH * atkSpeedMod * speedMod11 * sqrtE);

  // O: 空手攻击MAX
  const atkMax = 40 + (50 + C * D * 23) * sqrtE * growth125 * J / (G * sqrtH * atkSpeedMod * speedMod11);

  // P: HP最小值 (with 霸体 modifiers)
  const hpMinBase = Math.max(
    200 * (D - 2) + C * D * 293 * growth130 / (speedMod12 * sqrtE * J * Math.sqrt(L)),
    50
  );
  const hpSuperArmorLow = (K > 3 && D < 9) ? 1 - K / 50 : 1;
  const hpSuperArmorHigh = (K < 5 && D > 12) ? 1 + 1 / K : 1;
  const hpMin = hpMinBase * hpSuperArmorLow * hpSuperArmorHigh;

  // Q: HP最大值
  const hpMaxBase = Math.max(
    180 * (D - 2) + C * D * 900 * sqrtE * growth130 / (speedMod12 * J * Math.sqrt(L)),
    100
  );
  const hpMax = hpMaxBase * hpSuperArmorLow * hpSuperArmorHigh;

  // R: 防御力MIN
  const defMin = 30 / sqrtE + (50 + C * D) * L / (J * sqrtE) + 30 * (L - 1);

  // S: 防御力MAX
  const defMax = 210 + (190 + C * D) * L * sqrtE / (J * speedMod11);

  // T: 经验MIN
  const expMin = C ** 1.15 * D ** 1.2 * 12 * growth125 / sqrtE * (D > 17 ? Math.pow(1.2, D - 15) : 1);

  // U: 经验MAX
  const expMax = 95 + C ** 1 * D ** 1.58 * 33 * growth125 * sqrtE + (C >= 6 ? C * 200 : 0);

  // V: 金币价格
  const goldPrice = Math.floor(
    2 * C ** 1.3 * D ** 1.3 +
    (D > 2 ? D * 10 : 0) +
    (D > 8 ? C ** 0.5 * D ** 0.7 : 0) +
    (D > 16 ? C ** 1.2 * (D - 15) ** 2.5 : 0)
  ) * 500;

  // W: K点价格
  const kPointPrice = Math.floor(goldPrice / 700) * 20;

  return { atkMin, atkMax, hpMin, hpMax, defMin, defMax, expMin, expMax, goldPrice, kPointPrice };
}
