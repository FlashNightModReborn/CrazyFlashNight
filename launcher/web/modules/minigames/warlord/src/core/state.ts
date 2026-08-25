import { CARD_IDS, getCardDefinition } from '../data/cards.js';
import { CONFIG_DIGEST, DIFFICULTY_GOLD_MULTIPLIER, RULES_VERSION } from '../data/config.js';
import { MAP_EDGES, NODE_CONFIGS } from '../data/map.js';
import { addGameEvent } from './events.js';
import { startStrategicRoundInPlace } from './lifecycle.js';
import { createPieceInPlace } from './pieces.js';
import type {
  CardId,
  CardState,
  Difficulty,
  FactionId,
  FactionState,
  GameState,
  NodeId,
  NodeState,
  PresetId,
  ProductionSlot,
} from './types.js';

function createCardStates(preset: PresetId): Record<CardId, CardState> {
  return Object.fromEntries(CARD_IDS.map((cardId) => {
    const definition = getCardDefinition(cardId);
    const level = preset === 'all-units' ? Math.max(1, definition.deploymentLevel) : 1;
    return [cardId, {
      level,
      xpIntoLevel: 0,
      totalXpAllocated: 0,
      purchasedPromotions: [],
      promotedThisSettlement: false,
      producedCount: 0,
      lostCount: 0,
    } satisfies CardState];
  })) as unknown as Record<CardId, CardState>;
}

function createSlots(nodeId: NodeId): ProductionSlot[] {
  return Array.from({ length: NODE_CONFIGS[nodeId].productionSlots }, (_, index) => ({
    slotId: `${nodeId}:${index + 1}`,
    nodeId,
    orders: [],
  }));
}

function createFaction(
  factionId: FactionId,
  difficulty: Difficulty,
  preset: PresetId,
): FactionState {
  const baseGold = preset === 'all-units' ? 500 : 20;
  const multiplier = factionId === 'blue' ? DIFFICULTY_GOLD_MULTIPLIER[difficulty] : 1;
  const ownHq: NodeId = factionId === 'red' ? 'R-HQ' : 'B-HQ';
  const ownSupply: NodeId = factionId === 'red' ? 'R-Supply' : 'B-Supply';
  return {
    factionId,
    displayName: factionId === 'red' ? '红方军阀' : '蓝方军阀',
    gold: Math.floor(baseGold * multiplier),
    xpPool: preset === 'all-units' ? 30_000 : 0,
    populationUsed: 0,
    populationReserved: 0,
    populationCap: 0,
    scenarioPopulationBonus: preset === 'all-units' ? 20 : 0,
    actionPoints: 0,
    apGeneratedThisRound: 0,
    apSpentThisRound: 0,
    cards: createCardStates(preset),
    productionQueues: {
      [ownHq]: createSlots(ownHq),
      [ownSupply]: createSlots(ownSupply),
    },
    planningCommitted: false,
  };
}

function createMapNodes(): Record<NodeId, NodeState> {
  const entries = (Object.keys(NODE_CONFIGS) as NodeId[]).map((nodeId) => {
    const config = NODE_CONFIGS[nodeId];
    const ownerFactionId: FactionId | null = nodeId.startsWith('R-') ? 'red' : nodeId.startsWith('B-') ? 'blue' : null;
    return [nodeId, {
      ...config,
      ownerFactionId,
      activeFromRound: ownerFactionId ? 1 : null,
      pieceIds: [],
    } satisfies NodeState];
  });
  return Object.fromEntries(entries) as Record<NodeId, NodeState>;
}

function spawnStandardPieces(state: GameState): void {
  for (const factionId of ['red', 'blue'] as const) {
    const nodeId: NodeId = factionId === 'red' ? 'R-HQ' : 'B-HQ';
    createPieceInPlace(state, factionId, 14, nodeId, 1);
    createPieceInPlace(state, factionId, 14, nodeId, 1);
    createPieceInPlace(state, factionId, 12, nodeId, 1);
    createPieceInPlace(state, factionId, 13, nodeId, 1);
  }
}

function spawnAllUnitsPreset(state: GameState): void {
  const redPlacements: Array<[CardId, NodeId]> = [
    [14, 'R-Supply'], [15, 'R-Supply'], [82, 'R-Supply'],
    [12, 'R-Economy'], [13, 'R-Economy'],
    [83, 'R-HQ'], [84, 'R-HQ'], [85, 'R-HQ'],
  ];
  const bluePlacements: Array<[CardId, NodeId]> = [
    [12, 'North-Choke'], [84, 'North-Choke'],
    [14, 'B-Supply'], [15, 'B-Supply'], [82, 'B-Supply'], [13, 'B-Supply'],
    [83, 'B-HQ'], [85, 'B-HQ'],
  ];
  for (const [cardId, nodeId] of redPlacements) createPieceInPlace(state, 'red', cardId, nodeId, 1);
  for (const [cardId, nodeId] of bluePlacements) createPieceInPlace(state, 'blue', cardId, nodeId, 1);
}

export interface CreateGameOptions {
  seed?: string;
  difficulty?: Difficulty;
  preset?: PresetId;
}

export function createGame(options: CreateGameOptions = {}): GameState {
  const difficulty = options.difficulty ?? 'normal';
  const preset = options.preset ?? 'standard';
  const seed = options.seed?.trim() || 'warlord-demo-seed-001';
  const state: GameState = {
    schemaVersion: 1,
    rulesVersion: RULES_VERSION,
    configDigest: CONFIG_DIGEST,
    gameSeed: seed,
    difficulty,
    preset,
    strategicRound: 1,
    phase: 'FIRST_FACTION_ACTION',
    initiativeFactionId: 'red',
    activeFactionId: 'red',
    commandSequence: 0,
    battleOrdinal: 0,
    nextPieceOrdinal: 0,
    nextOrderOrdinal: 0,
    nextEventOrdinal: 0,
    map: { nodes: createMapNodes(), edges: MAP_EDGES.map((edge) => ({ ...edge })) },
    factions: {
      red: createFaction('red', difficulty, preset),
      blue: createFaction('blue', difficulty, preset),
    },
    pieces: {},
    casualtyLedger: [],
    eventLog: [],
    battles: [],
    commandHistory: [],
    result: null,
    diagnostics: { invalidCommandCount: 0, maxCommandsGuardHit: false },
  };

  if (preset === 'standard') spawnStandardPieces(state);
  else spawnAllUnitsPreset(state);

  addGameEvent(state, {
    type: 'game_started',
    message: `以种子 ${seed} 开始${preset === 'standard' ? '标准对局' : '全兵种演习'}。`,
    data: { difficulty, preset },
  });
  startStrategicRoundInPlace(state);
  return state;
}
