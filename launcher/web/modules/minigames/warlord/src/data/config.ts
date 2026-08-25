import type { Difficulty, PromotionId } from '../core/types.js';

export const RULES_VERSION = 'wargame-demo-v0.1.1';
export const RULES_EXTENSION_VERSION = 'phase-a-production-cancel-v1';
export const TUNING_VERSION = 'warlord-demo-tuning-v0.1.1';
export const AI_POLICY_VERSION = 'deterministic-heuristic-v1.1';
export const CONFIG_DIGEST = 'sha256:9DA8013D3B7D1C1F5C5B27BDA813F1ADC9E2C8C5C80F3680B9FFDF773A9B76B0';
export const MAX_STRATEGIC_ROUNDS = 24;
export const MAX_BATTLE_ROUNDS = 16;
export const DAMAGE_SCALE = 6;
export const HIT_MIN = 0.65;
export const HIT_MAX = 0.98;
export const DAMAGE_RANDOM_MIN = 0.9;
export const DAMAGE_RANDOM_MAX = 1.1;

export const DIFFICULTY_GOLD_MULTIPLIER: Record<Difficulty, number> = {
  easy: 0.8,
  normal: 1,
  hard: 1.25,
  extreme: 1.5,
};

export const PROMOTIONS: Record<PromotionId, {
  level: number;
  cost: number;
  hp: number;
  attack: number;
  defense: number;
}> = {
  基础训练: { level: 10, cost: 25, hp: 2000, attack: 30, defense: 100 },
  强化药剂: { level: 25, cost: 50, hp: 3500, attack: 100, defense: 100 },
  超级血清: { level: 50, cost: 100, hp: 10000, attack: 150, defense: 50 },
};
