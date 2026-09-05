import { CARD_IDS, getCardDefinition } from '../data/cards.js';
import { CONFIG_DIGEST, DIFFICULTY_GOLD_MULTIPLIER, RULES_VERSION } from '../data/config.js';
import { DEMO_1_RUNTIME, type RuntimeMapBundle } from '../data/map.js';
import { scenarioRuntimeRules } from '../data/scenario-runtime.js';
import type { ScenarioFactionDefinitionV1 } from '../strategy/definitions.js';
import { createEncounterRuntimeState } from './encounter.js';
import { addGameEvent } from './events.js';
import { createDefaultRelations, createDefaultVictoryGroups } from './factions.js';
import { startStrategicRoundInPlace } from './lifecycle.js';
import { createOrganizationRuntimeState } from './organization.js';
import { createPieceInPlace } from './pieces.js';
import type {
  CardId,
  CardState,
  CommanderState,
  Difficulty,
  FactionId,
  FactionState,
  GameState,
  NodeId,
  NodeState,
  PresetId,
  ProductionSlot,
  StrategicRelation,
  VictoryGroupState,
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

function runtimeNodeConfig(bundle: RuntimeMapBundle, nodeId: NodeId) {
  const config = bundle.nodeConfigs[nodeId];
  if (!config) throw new Error(`Scenario references unknown node ${nodeId}.`);
  return config;
}

function createSlots(bundle: RuntimeMapBundle, nodeId: NodeId): ProductionSlot[] {
  return Array.from({ length: runtimeNodeConfig(bundle, nodeId).productionSlots }, (_, index) => ({
    slotId: `${nodeId}:${index + 1}`,
    nodeId,
    orders: [],
  }));
}

function createFaction(
  definition: ScenarioFactionDefinitionV1,
  bundle: RuntimeMapBundle,
  difficulty: Difficulty,
  preset: PresetId,
  victoryGroupId: string,
): FactionState {
  const factionId = definition.id as unknown as FactionId;
  const baseGold = preset === 'all-units' ? 500 : 20;
  const multiplier = definition.controller === 'ai' ? DIFFICULTY_GOLD_MULTIPLIER[difficulty] : 1;
  const ownHq = definition.headquartersNodeRef as unknown as NodeId;
  const ownSupply = definition.supplyNodeRef as unknown as NodeId;
  return {
    factionId,
    displayName: definition.displayName,
    controller: definition.controller,
    victoryGroupId,
    commandPostNodeId: ownHq,
    defeatedAtRound: null,
    defeatReason: null,
    gold: Math.floor(baseGold * multiplier),
    xpPool: preset === 'all-units' ? 30_000 : 0,
    populationUsed: 0,
    populationReserved: 0,
    populationCap: 0,
    scenarioPopulationBonus: preset === 'all-units' ? 20 : 0,
    actionPoints: 0,
    apGeneratedThisRound: 0,
    apSpentThisRound: 0,
    apLedger: {
      baseGenerated: 0,
      fieldGenerated: 0,
      baseRemaining: 0,
      fieldRemaining: 0,
      baseSpent: 0,
      fieldSpent: 0,
    },
    cards: createCardStates(preset),
    productionQueues: {
      [ownHq]: createSlots(bundle, ownHq),
      [ownSupply]: createSlots(bundle, ownSupply),
    },
    planningCommitted: false,
  };
}

function createMapNodes(bundle: RuntimeMapBundle): Record<NodeId, NodeState> {
  const entries = bundle.mapDefinition.nodes.map((definition) => {
    const nodeId = definition.id as unknown as NodeId;
    const config = runtimeNodeConfig(bundle, nodeId);
    const authoredOwner = bundle.initialControlByNode[nodeId];
    const ownerFactionId: FactionId | null = authoredOwner ?? null;
    return [nodeId, {
      ...config,
      ownerFactionId,
      activeFromRound: ownerFactionId ? 1 : null,
      pieceIds: [],
    } satisfies NodeState];
  });
  return Object.fromEntries(entries) as Record<NodeId, NodeState>;
}

function isCardId(value: number): value is CardId {
  return (CARD_IDS as readonly number[]).includes(value);
}

function initialDeployments(bundle: RuntimeMapBundle, preset: PresetId) {
  return preset === 'all-units'
    ? bundle.scenario.initialState.allUnitsDeployments
    : bundle.scenario.initialState.standardDeployments;
}

function spawnScenarioPieces(state: GameState, preset: PresetId, bundle: RuntimeMapBundle): void {
  for (const deployment of initialDeployments(bundle, preset)) {
    const factionId = deployment.factionRef as unknown as FactionId;
    if (!state.factions[factionId]) throw new Error(`Deployment uses unknown faction ${factionId}.`);
    const nodeId = deployment.nodeRef as unknown as NodeId;
    for (const cardValue of deployment.cardIds) {
      if (!isCardId(cardValue)) throw new Error(`Deployment uses unknown card ${cardValue}.`);
      createPieceInPlace(state, factionId, cardValue, nodeId, 1);
    }
  }
}

function bindScenarioCommandersInPlace(state: GameState): void {
  for (const commander of Object.values(state.commanders)) {
    if (commander.status !== 'fielded') continue;
    if (commander.pieceInstanceId !== null) {
      const bound = state.pieces[commander.pieceInstanceId];
      if (!bound || bound.factionId !== commander.factionId || bound.cardId !== commander.cardId) {
        throw new Error(`Commander ${commander.commanderId} has an invalid piece binding.`);
      }
      commander.nodeId = bound.nodeId;
      continue;
    }
    const candidates = Object.values(state.pieces)
      .filter((piece) => (
        piece.factionId === commander.factionId
        && piece.cardId === commander.cardId
        && (commander.nodeId === null || piece.nodeId === commander.nodeId)
      ))
      .sort((left, right) => left.pieceId.localeCompare(right.pieceId));
    if (candidates.length !== 1) {
      throw new Error(
        `Commander ${commander.commanderId} requires exactly one deployed piece at its authored node; found ${candidates.length}.`,
      );
    }
    const candidate = candidates[0];
    if (!candidate) throw new Error(`Commander ${commander.commanderId} has no deployed piece.`);
    commander.pieceInstanceId = candidate.pieceId;
    commander.nodeId = candidate.nodeId;
  }
}

export interface CreateGameOptions {
  seed?: string;
  difficulty?: Difficulty;
  preset?: PresetId;
  runtimeBundle?: RuntimeMapBundle;
  relations?: Record<FactionId, Record<FactionId, StrategicRelation>>;
  victoryGroups?: Record<string, VictoryGroupState>;
  commanders?: Record<string, CommanderState>;
  scenarioBaseAp?: number;
}

export function createGame(options: CreateGameOptions = {}): GameState {
  const difficulty = options.difficulty ?? 'normal';
  const preset = options.preset ?? 'standard';
  const seed = options.seed?.trim() || 'warlord-demo-seed-001';
  const bundle = options.runtimeBundle ?? DEMO_1_RUNTIME;
  const turnOrder = bundle.scenario.turnOrder.map((factionId) => factionId as unknown as FactionId);
  const playerFactionId = bundle.scenario.playerFactionRef as unknown as FactionId;
  const scenarioRules = scenarioRuntimeRules(bundle);
  const displayNameByFaction = Object.fromEntries(bundle.scenario.factions.map((faction) => [
    faction.id as string,
    faction.displayName,
  ]));
  const victoryGroups = options.victoryGroups
    ?? scenarioRules.victoryGroups
    ?? createDefaultVictoryGroups(turnOrder, displayNameByFaction);
  const victoryGroupByFaction = new Map<string, string>();
  for (const group of Object.values(victoryGroups)) {
    for (const factionId of group.factionIds) victoryGroupByFaction.set(factionId, group.victoryGroupId);
  }
  const factions = Object.fromEntries(bundle.scenario.factions.map((definition) => {
    const factionId = definition.id as unknown as FactionId;
    return [factionId, createFaction(
      definition,
      bundle,
      difficulty,
      preset,
      victoryGroupByFaction.get(factionId) ?? factionId,
    )];
  })) as Record<FactionId, FactionState>;
  const firstFactionId = turnOrder[0];
  if (!firstFactionId || firstFactionId !== playerFactionId) {
    throw new Error('Validated scenario must place the player faction first.');
  }

  const state: GameState = {
    schemaVersion: 1,
    rulesVersion: RULES_VERSION,
    configDigest: CONFIG_DIGEST,
    scenarioId: bundle.scenario.id,
    mapDefinitionId: bundle.mapDefinition.id,
    mapPresentationId: bundle.scenario.mapPresentationRef,
    encounter: createEncounterRuntimeState(bundle.encounter),
    gameSeed: seed,
    difficulty,
    preset,
    playerFactionId,
    turnOrder,
    activeTurnIndex: 0,
    scenarioBaseAp: options.scenarioBaseAp ?? 0,
    relations: structuredClone(options.relations ?? scenarioRules.relations ?? createDefaultRelations(turnOrder)),
    victoryGroups: structuredClone(victoryGroups),
    commanders: structuredClone(options.commanders ?? scenarioRules.commanders),
    capturedCommandPostNodeIds: [],
    strategicRound: 1,
    phase: 'FIRST_FACTION_ACTION',
    initiativeFactionId: playerFactionId,
    activeFactionId: playerFactionId,
    commandSequence: 0,
    battleOrdinal: 0,
    nextPieceOrdinal: 0,
    nextOrderOrdinal: 0,
    nextEventOrdinal: 0,
    map: {
      nodes: createMapNodes(bundle),
      edges: bundle.edges.map((edge) => ({ ...edge })),
    },
    factions,
    pieces: {},
    organization: createOrganizationRuntimeState(),
    casualtyLedger: [],
    eventLog: [],
    battles: [],
    commandHistory: [],
    result: null,
    diagnostics: { invalidCommandCount: 0, maxCommandsGuardHit: false },
  };

  spawnScenarioPieces(state, preset, bundle);
  bindScenarioCommandersInPlace(state);
  addGameEvent(state, {
    type: 'game_started',
    message: `以种子 ${seed} 开始${preset === 'standard' ? '标准对局' : '全兵种演习'}。`,
    data: { difficulty, preset, scenarioId: state.scenarioId, factionCount: turnOrder.length },
  });
  startStrategicRoundInPlace(state);
  return state;
}
