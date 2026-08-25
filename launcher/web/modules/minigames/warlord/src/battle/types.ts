import type { BehaviorId, CardId, FactionId } from '../core/types.js';

export type BattleSide = 'attacker' | 'defender';

export interface BattleUnitSnapshot {
  pieceId: string;
  factionId: FactionId;
  cardId: CardId;
  displayName: string;
  behaviorId: BehaviorId;
  tags: string[];
  formationRank: number;
  hp: number;
  maxHp: number;
  attack: number;
  defense: number;
  speed: number;
  frozenCardLevel: number;
}

export interface ResolveBattleInput {
  battleId: string;
  seed: string;
  strategicRound: number;
  commandSequence: number;
  nodeId: string;
  nodeDefenseBonus: number;
  attackerOriginNodeId: string;
  attackerUnits: BattleUnitSnapshot[];
  defenderUnits: BattleUnitSnapshot[];
  maxBattleRounds?: number;
}

export type BattleEventType =
  | 'round_start'
  | 'sniper_volley'
  | 'reload'
  | 'attack'
  | 'miss'
  | 'damage'
  | 'special'
  | 'suppression'
  | 'death'
  | 'round_end'
  | 'battle_end';

export interface BattleEvent {
  eventId: string;
  battleId: string;
  battleRound: number;
  phase: 'opening_volley' | 'normal' | 'system';
  type: BattleEventType;
  actorPieceId?: string;
  targetPieceId?: string;
  actorFactionId?: FactionId;
  targetFactionId?: FactionId;
  damage?: number;
  hpAfter?: number;
  hitChance?: number;
  roll?: number;
  tagMultiplier?: number;
  message: string;
}

export interface BattlePieceResult {
  pieceId: string;
  factionId: FactionId;
  cardId: CardId;
  hpAfter: number;
  dead: boolean;
  damageDealt: number;
  attacksMade: number;
  suppressionsApplied: number;
  frozenCardLevel: number;
}

export interface BattleCasualty {
  pieceId: string;
  factionId: FactionId;
  killerFactionId: FactionId;
  cardId: CardId;
  frozenCardLevel: number;
}

export interface BattleResult {
  winner: BattleSide;
  reason: 'wiped' | 'mutual_wipe' | 'battle_round_limit';
  battleRounds: number;
  pieceResults: BattlePieceResult[];
  casualties: BattleCasualty[];
  eventLog: readonly BattleEvent[];
  finalRngState: number;
}

export interface BattleAuthorityAudit {
  authority: 'as2';
  requestSchema: 'warlord.as2-battle-request.v1';
  receiptSchema: 'warlord.as2-battle-receipt.v1';
  sessionId: string;
  requestId: string;
  inputDigest: string;
  frames: number;
  durationMs: number;
  economyObservation: Readonly<Record<string, unknown>>;
}

export interface BattleRecord {
  battleId: string;
  seed: string;
  strategicRound: number;
  commandSequence: number;
  nodeId: string;
  attackerOriginNodeId: string;
  attackerPieceIds: string[];
  defenderPieceIds: string[];
  attackerSnapshots: BattleUnitSnapshot[];
  defenderSnapshots: BattleUnitSnapshot[];
  authority?: BattleAuthorityAudit;
  result: BattleResult;
}
