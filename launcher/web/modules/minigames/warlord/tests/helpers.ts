import type { BattleUnitSnapshot } from '../src/battle/types.js';
import { applyCommand } from '../src/core/engine.js';
import { requireFaction } from '../src/core/factions.js';
import { getRuntimeStats } from '../src/core/math.js';
import { removePieceInPlace } from '../src/core/pieces.js';
import { createGame } from '../src/core/state.js';
import type { CardId, FactionId, GameCommand, GameState, NodeId, PresetId } from '../src/core/types.js';
import { getCardDefinition } from '../src/data/cards.js';

export function makeState(seed = 'test-seed', preset: PresetId = 'standard'): GameState {
  return createGame({ seed, preset, difficulty: 'normal' });
}

export function clearAllPieces(state: GameState): void {
  for (const pieceId of Object.keys(state.pieces)) removePieceInPlace(state, pieceId);
}

export function setAction(state: GameState, factionId: FactionId = 'red', ap = 99): void {
  state.phase = 'FIRST_FACTION_ACTION';
  state.initiativeFactionId = factionId;
  state.activeFactionId = factionId;
  const faction = requireFaction(state, factionId);
  faction.apLedger = {
    baseGenerated: ap,
    baseRemaining: ap,
    baseSpent: 0,
    fieldGenerated: 0,
    fieldRemaining: 0,
    fieldSpent: 0,
  };
  faction.actionPoints = ap;
  faction.apGeneratedThisRound = ap;
  faction.apSpentThisRound = 0;
}

export function setPlanning(state: GameState): void {
  state.phase = 'SETTLEMENT_PLANNING';
  state.activeFactionId = null;
  requireFaction(state, 'red').planningCommitted = false;
  requireFaction(state, 'blue').planningCommitted = false;
}

export function faction(state: GameState, factionId: FactionId) {
  return requireFaction(state, factionId);
}

export function applyOk(state: GameState, command: GameCommand): GameState {
  const result = applyCommand(state, command);
  if (!result.ok) throw new Error(`Expected legal command ${command.type}: ${result.error}`);
  return result.state;
}

export function makeUnit(
  pieceId: string,
  factionId: FactionId,
  cardId: CardId,
  overrides: Partial<BattleUnitSnapshot> = {},
): BattleUnitSnapshot {
  const definition = getCardDefinition(cardId);
  const stats = getRuntimeStats(cardId, { level: 1, purchasedPromotions: [] });
  return {
    pieceId,
    factionId,
    cardId,
    displayName: definition.displayName,
    behaviorId: definition.behaviorId,
    tags: [...definition.tags],
    formationRank: definition.formationRank,
    hp: stats.maxHp,
    maxHp: stats.maxHp,
    attack: stats.attack,
    defense: stats.defense,
    speed: stats.speed,
    frozenCardLevel: 1,
    ...overrides,
  };
}

export function moveCommand(
  state: GameState,
  pieceIds: string[],
  originNodeId: NodeId,
  targetNodeId: NodeId,
  factionId: FactionId = 'red',
): GameCommand {
  return { type: 'MOVE_OR_ATTACK', factionId, pieceIds, originNodeId, targetNodeId };
}

export function recursivelySwapFactions(value: unknown): unknown {
  if (value === 'red') return 'blue';
  if (value === 'blue') return 'red';
  if (Array.isArray(value)) return value.map(recursivelySwapFactions);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, recursivelySwapFactions(child)]));
  }
  return value;
}
