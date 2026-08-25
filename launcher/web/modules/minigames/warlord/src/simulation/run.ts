import { runAiActionPhase, runAiPlanning } from '../ai/heuristic.js';
import { createGame } from '../core/state.js';
import type { CardId, Difficulty, FactionId, GameState } from '../core/types.js';
import { CARD_IDS } from '../data/cards.js';
import { AI_POLICY_VERSION, TUNING_VERSION } from '../data/config.js';
import { makeReplay, type ReplayFile } from '../replay/replay.js';

export interface SimulationTelemetry {
  battleCount: number;
  battleRounds: number;
  battleRoundLimits: number;
  suppressions: number;
  sniperVolleyDamage: number;
  totalDamage: number;
}

export interface SingleSimulationResult {
  state: GameState;
  invalidCommands: number;
  commandGuardHit: boolean;
  rebuilds: Record<FactionId, number>;
  telemetry: SimulationTelemetry;
}

function deployedCount(state: GameState, factionId: FactionId): number {
  return Object.values(state.pieces).filter((piece) => piece.factionId === factionId).length;
}

function canRebuild(state: GameState, factionId: FactionId): boolean {
  const faction = state.factions[factionId];
  const queueExists = Object.values(faction.productionQueues).some((slots) => slots?.some((slot) => slot.orders.length > 0));
  const productionNodeExists = (Object.keys(state.map.nodes) as Array<keyof typeof state.map.nodes>).some((nodeId) => {
    const node = state.map.nodes[nodeId];
    return node.ownerFactionId === factionId && node.productionSlots > 0 && node.activeFromRound !== null && node.activeFromRound <= state.strategicRound;
  });
  return queueExists || productionNodeExists;
}

export function runSingleSimulation(
  seed: string,
  difficulty: Difficulty = 'normal',
  preset: 'standard' | 'all-units' = 'standard',
  compactLogs = false,
): SingleSimulationResult {
  let state = createGame({ seed, difficulty, preset });
  let invalidCommands = 0;
  let guard = 0;
  const wipedWithRebuildPotential: Record<FactionId, boolean> = { red: false, blue: false };
  const rebuilds: Record<FactionId, number> = { red: 0, blue: 0 };
  const telemetry: SimulationTelemetry = {
    battleCount: 0,
    battleRounds: 0,
    battleRoundLimits: 0,
    suppressions: 0,
    sniperVolleyDamage: 0,
    totalDamage: 0,
  };
  let observedBattleCount = 0;

  const collectTelemetry = (): void => {
    const newBattles = state.battles.slice(observedBattleCount);
    for (const battle of newBattles) {
      telemetry.battleCount += 1;
      telemetry.battleRounds += battle.result.battleRounds;
      if (battle.result.reason === 'battle_round_limit') telemetry.battleRoundLimits += 1;
      for (const event of battle.result.eventLog) {
        if (event.type === 'suppression') telemetry.suppressions += 1;
        if (event.damage) {
          telemetry.totalDamage += event.damage;
          if (event.phase === 'opening_volley') telemetry.sniperVolleyDamage += event.damage;
        }
      }
    }
    if (compactLogs) {
      state.battles = [];
      state.eventLog = [];
      state.commandHistory = [];
      state.casualtyLedger = state.casualtyLedger.filter((entry) => !entry.settled);
      observedBattleCount = 0;
    } else {
      observedBattleCount = state.battles.length;
    }
  };

  while (!state.result && guard < 5_000) {
    guard += 1;
    for (const factionId of ['red', 'blue'] as const) {
      const count = deployedCount(state, factionId);
      if (count === 0 && canRebuild(state, factionId)) wipedWithRebuildPotential[factionId] = true;
      if (count > 0 && wipedWithRebuildPotential[factionId]) {
        rebuilds[factionId] += 1;
        wipedWithRebuildPotential[factionId] = false;
      }
    }

    if (state.phase === 'FIRST_FACTION_ACTION' || state.phase === 'SECOND_FACTION_ACTION') {
      const active = state.activeFactionId;
      if (!active) {
        invalidCommands += 1;
        break;
      }
      const result = runAiActionPhase(state, active);
      state = result.state;
      invalidCommands += result.invalidGenerated;
      collectTelemetry();
      continue;
    }
    if (state.phase === 'SETTLEMENT_PLANNING') {
      if (!state.factions.red.planningCommitted) {
        const result = runAiPlanning(state, 'red');
        state = result.state;
        invalidCommands += result.invalidGenerated;
        collectTelemetry();
        continue;
      }
      if (!state.factions.blue.planningCommitted) {
        const result = runAiPlanning(state, 'blue');
        state = result.state;
        invalidCommands += result.invalidGenerated;
        collectTelemetry();
        continue;
      }
    }
  }

  collectTelemetry();
  const commandGuardHit = !state.result;
  if (commandGuardHit) state.diagnostics.maxCommandsGuardHit = true;
  return { state, invalidCommands, commandGuardHit, rebuilds, telemetry };
}

export interface SimulationSummary {
  schemaVersion: 1;
  rulesVersion: string;
  configDigest: string;
  tuningVersion: string;
  aiPolicyVersion: string;
  generatedAt: string;
  gameCount: number;
  completedGames: number;
  terminalReasons: Record<string, number>;
  winners: Record<'red' | 'blue' | 'draw', number>;
  mirrorWinRate: {
    red: number;
    blue: number;
    draw: number;
  };
  firstSecondBias: {
    initialFirstFaction: 'red';
    initialFirstWinRate: number;
    initialSecondWinRate: number;
    delta: number;
  };
  averageStrategicRound: number;
  cards: Record<string, {
    produced: number;
    lost: number;
    finalAverageLevel: number;
    promotionsPurchased: number;
  }>;
  controlEffects: {
    suppressions: number;
    sniperVolleyDamage: number;
    totalDamage: number;
  };
  battles: {
    total: number;
    averageBattleRounds: number;
    roundLimitCount: number;
    roundLimitRate: number;
  };
  rebuildsAfterFieldWipe: Record<FactionId, number>;
  invalidStateCount: number;
  commandGuardHitCount: number;
  seeds: string[];
}

export interface BatchSimulationResult {
  summary: SimulationSummary;
  sampleReplay: ReplayFile;
  finalStates: GameState[];
}

export function runBatchSimulation(gameCount = 32): BatchSimulationResult {
  const seeds = Array.from({ length: gameCount }, (_, index) => `warlord-batch-${String(index + 1).padStart(3, '0')}`);
  const results = seeds.map((seed, index) => runSingleSimulation(seed, 'normal', 'standard', index !== 0));
  const states = results.map((result) => result.state);
  const completed = states.filter((state) => state.result !== null);
  const winners = { red: 0, blue: 0, draw: 0 };
  const terminalReasons: Record<string, number> = { elimination: 0, round_limit: 0, incomplete: 0 };
  for (const state of states) {
    if (!state.result) {
      terminalReasons.incomplete = (terminalReasons.incomplete ?? 0) + 1;
      continue;
    }
    winners[state.result.winner] += 1;
    terminalReasons[state.result.reason] = (terminalReasons[state.result.reason] ?? 0) + 1;
  }

  const cardStats = Object.fromEntries(CARD_IDS.map((cardId) => {
    let produced = 0;
    let lost = 0;
    let levels = 0;
    let promotions = 0;
    for (const state of states) {
      for (const factionId of ['red', 'blue'] as const) {
        const card = state.factions[factionId].cards[cardId];
        produced += card.producedCount;
        lost += card.lostCount;
        levels += card.level;
        promotions += card.purchasedPromotions.length;
      }
    }
    return [String(cardId), {
      produced,
      lost,
      finalAverageLevel: states.length > 0 ? levels / (states.length * 2) : 0,
      promotionsPurchased: promotions,
    }];
  })) as SimulationSummary['cards'];

  const suppressions = results.reduce((sum, result) => sum + result.telemetry.suppressions, 0);
  const sniperVolleyDamage = results.reduce((sum, result) => sum + result.telemetry.sniperVolleyDamage, 0);
  const totalDamage = results.reduce((sum, result) => sum + result.telemetry.totalDamage, 0);
  const battleRounds = results.reduce((sum, result) => sum + result.telemetry.battleRounds, 0);
  const battleCount = results.reduce((sum, result) => sum + result.telemetry.battleCount, 0);
  const battleRoundLimits = results.reduce((sum, result) => sum + result.telemetry.battleRoundLimits, 0);

  const invalidStateCount = results.reduce((sum, result) => sum + result.invalidCommands, 0)
    + states.filter((state) => Object.values(state.factions).some((faction) => (
      !Number.isFinite(faction.gold)
      || !Number.isFinite(faction.populationUsed)
      || faction.populationUsed < 0
      || faction.populationReserved < 0
    ))).length;
  const rebuilds: Record<FactionId, number> = {
    red: results.reduce((sum, result) => sum + result.rebuilds.red, 0),
    blue: results.reduce((sum, result) => sum + result.rebuilds.blue, 0),
  };
  const denominator = Math.max(1, completed.length);
  const redRate = winners.red / denominator;
  const blueRate = winners.blue / denominator;
  const summary: SimulationSummary = {
    schemaVersion: 1,
    rulesVersion: states[0]?.rulesVersion ?? 'wargame-demo-v0.1.1',
    configDigest: states[0]?.configDigest ?? '',
    tuningVersion: TUNING_VERSION,
    aiPolicyVersion: AI_POLICY_VERSION,
    generatedAt: new Date().toISOString(),
    gameCount,
    completedGames: completed.length,
    terminalReasons,
    winners,
    mirrorWinRate: { red: redRate, blue: blueRate, draw: winners.draw / denominator },
    firstSecondBias: {
      initialFirstFaction: 'red',
      initialFirstWinRate: redRate,
      initialSecondWinRate: blueRate,
      delta: redRate - blueRate,
    },
    averageStrategicRound: completed.length > 0
      ? completed.reduce((sum, state) => sum + state.strategicRound, 0) / completed.length
      : 0,
    cards: cardStats,
    controlEffects: { suppressions, sniperVolleyDamage, totalDamage },
    battles: {
      total: battleCount,
      averageBattleRounds: battleCount > 0 ? battleRounds / battleCount : 0,
      roundLimitCount: battleRoundLimits,
      roundLimitRate: battleCount > 0 ? battleRoundLimits / battleCount : 0,
    },
    rebuildsAfterFieldWipe: rebuilds,
    invalidStateCount,
    commandGuardHitCount: results.filter((result) => result.commandGuardHit).length,
    seeds,
  };

  return {
    summary,
    sampleReplay: makeReplay(states[0] ?? createGame()),
    finalStates: states,
  };
}
