import { PROMOTIONS } from '../data/config.js';
import { getCardDefinition } from '../data/cards.js';
import type { CardId, CardState, PromotionId } from './types.js';

export interface RuntimeStats {
  maxHp: number;
  attack: number;
  defense: number;
  speed: number;
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

export function interpolateStat(min: number, max: number, level: number): number {
  return Math.max(1, Math.floor(min + ((max - min) / 59) * level));
}

export function getRuntimeStats(cardId: CardId, cardState: Pick<CardState, 'level' | 'purchasedPromotions'>): RuntimeStats {
  const definition = getCardDefinition(cardId);
  let maxHp = interpolateStat(definition.statRanges.hp.min, definition.statRanges.hp.max, cardState.level);
  let attack = interpolateStat(definition.statRanges.unarmedAttack.min, definition.statRanges.unarmedAttack.max, cardState.level);
  let defense = interpolateStat(definition.statRanges.baseDefense.min, definition.statRanges.baseDefense.max, cardState.level);
  const speed = interpolateStat(definition.statRanges.speed.min, definition.statRanges.speed.max, cardState.level);

  for (const promotionId of cardState.purchasedPromotions) {
    const promotion = PROMOTIONS[promotionId];
    maxHp += promotion.hp;
    attack += promotion.attack;
    defense += promotion.defense;
  }

  return { maxHp, attack, defense, speed };
}

export function baseBounty(cardId: CardId, level: number): number {
  const { expRange } = getCardDefinition(cardId);
  return Math.floor(expRange.min + ((expRange.max - expRange.min) / 59) * level);
}

export function bounty(cardId: CardId, level: number): number {
  return Math.max(1, Math.round(baseBounty(cardId, level) * 5));
}

export function needXp(cardId: CardId, level: number): number {
  const { expRange } = getCardDefinition(cardId);
  return Math.floor((expRange.min + ((expRange.max - expRange.min) / 59) * level) * level);
}

export function promotionStats(promotions: PromotionId[]): Pick<RuntimeStats, 'maxHp' | 'attack' | 'defense'> {
  return promotions.reduce(
    (acc, promotionId) => {
      const promotion = PROMOTIONS[promotionId];
      acc.maxHp += promotion.hp;
      acc.attack += promotion.attack;
      acc.defense += promotion.defense;
      return acc;
    },
    { maxHp: 0, attack: 0, defense: 0 },
  );
}
