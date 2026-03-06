/** 伤害公式引擎 — 对应 Excel "伤害公式" sheet */

export interface PhysicalDamageInput {
  damage: number;
  defence: number;
  penetration: number; // 防御穿透 (0-1)
  hp: number;
}

export interface PhysicalDamageOutput {
  effectiveDefence: number; // 最终防御
  reductionRatio: number;   // 减伤比例
  remainRatio: number;      // 剩余比例
  effectiveHP: number;      // 等效血量
  finalDamage: number;      // 最终伤害
  hitsToKill: number;       // 承伤次数
}

export function computePhysicalDamage(input: PhysicalDamageInput): PhysicalDamageOutput {
  const effectiveDefence = input.defence * (1 - input.penetration);
  const reductionRatio = effectiveDefence / (effectiveDefence + 300);
  const remainRatio = 1 - reductionRatio;
  const effectiveHP = input.hp / remainRatio;
  const finalDamage = input.damage * remainRatio;
  const hitsToKill = effectiveHP / input.damage;

  return { effectiveDefence, reductionRatio, remainRatio, effectiveHP, finalDamage, hitsToKill };
}

export interface MagicDamageInput {
  damage: number;
  magicResist: number; // 魔抗 (0-100)
  hp: number;
}

export interface MagicDamageOutput {
  effectiveHP: number; // 等效血量 = damage / ((100-魔抗)/100)
  finalDamage: number; // 最终伤害
}

export function computeMagicDamage(input: MagicDamageInput): MagicDamageOutput {
  const ratio = (100 - input.magicResist) / 100;
  return {
    effectiveHP: input.damage / ratio,
    finalDamage: input.damage * ratio,
  };
}
