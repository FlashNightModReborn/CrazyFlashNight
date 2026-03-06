/** 药剂公式引擎 — 对应 Excel "药剂面板" sheet */

export interface PotionInput {
  hp: number;
  mp: number;
  sustainFrames: number;   // 缓释持续帧 (0 = 非缓释)
  playerLevel: number;     // 玩家等级
  isGroup: number;         // 是否群体 (0 or 1)
  purifyValue: number;     // 净化值
  toxicity: number;        // 剧毒性
  buffHp: number;
  buffMp: number;
  buffDefence: number;
  buffMagicResist: number; // 全属性时 ×2
  buffDamage: number;
  buffPunch: number;       // 空手
  buffSpeed: number;
  buffDuration: number;    // buff持续帧 (0 = 无限)
}

export interface PotionOutput {
  recoveryStrength: number;  // 恢复药强度 Y
  purifyStrength: number;    // 净化强度 Z
  toxicStrength: number;     // 剧毒强度 AA
  buffStrength: number;      // buff强度 AB
  currentValue: number;      // 当前数值 T
  valueCap: number;          // 数值上限 U
  rawPrice: number;          // 原始推荐价格 AC
  recommendedPrice: number;  // 推荐价格 V
}

export function computePotionRow(input: PotionInput): PotionOutput {
  // Y: 恢复药强度
  const recoveryStrength = input.hp + input.mp;

  // Z: 净化强度
  const purifyStrength = input.purifyValue * 60;

  // AA: 剧毒强度
  const toxicStrength = Math.pow(input.toxicity, 1.05) * 9.9;

  // AB: buff强度
  const buffBase =
    input.buffHp + input.buffMp +
    input.buffDefence * 2 +
    input.buffMagicResist * 50 +
    input.buffDamage * 3 +
    input.buffSpeed * 50 +
    input.buffPunch * 4;
  const buffMult = input.buffDuration > 0 ? 0.1 + input.buffDuration / 300 : 12;
  const buffStrength = buffBase * buffMult;

  // T: 当前数值
  const sustainDecay = (Math.min(input.sustainFrames / 30, 10) + (input.sustainFrames > 10 ? 5 : 0)) / 15;
  const currentValue =
    recoveryStrength * Math.pow(2, input.isGroup) / Math.pow(2, sustainDecay) +
    purifyStrength + toxicStrength + buffStrength;

  // U: 数值上限
  const valueCap = 100 + input.playerLevel * 100;

  // AC: 原始推荐价格
  const recoverySustainDecay = (Math.min(input.sustainFrames / 30, 20) + (input.sustainFrames > 10 ? 5 : 0)) / 25;
  const recoveryPrice =
    recoveryStrength *
    Math.pow(2, Math.min(recoveryStrength, 1500) / 850) /
    Math.pow(2, recoverySustainDecay) /
    2 *
    Math.pow(2, input.isGroup);
  const purifyPrice = purifyStrength * 2;
  const toxicPrice = toxicStrength * Math.pow(2, Math.min(toxicStrength, 3650) / 850) / 3;
  const buffPrice = buffStrength * Math.pow(2, Math.min(buffStrength, 3650) / 2000);

  const rawPrice = recoveryPrice + purifyPrice + toxicPrice + buffPrice;
  const recommendedPrice = Math.round(rawPrice / 50) * 50;

  return {
    recoveryStrength,
    purifyStrength,
    toxicStrength,
    buffStrength,
    currentValue,
    valueCap,
    rawPrice,
    recommendedPrice,
  };
}
