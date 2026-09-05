import { getCardDefinition } from '../data/cards.js';
import { DIFFICULTY_GOLD_MULTIPLIER, MAX_STRATEGIC_ROUNDS } from '../data/config.js';
import { requireNode } from './access.js';
import {
  evacuateDownedPlayerAvatarsInPlace,
  fieldCommanderAp,
  progressCommanderProductionInPlace,
} from './commanders.js';
import { addGameEvent } from './events.js';
import {
  activeFactionIds,
  defeatFactionInPlace,
  factionIds,
  isFactionDefeated,
  refreshFactionActionPoints,
  requireFaction,
} from './factions.js';
import {
  deploymentSizeForCard,
  memberApContribution,
  nodeDeploymentSize,
} from './organization.js';
import {
  applyGameResultInPlace,
  captureCommandPostInPlace,
  evaluateVictoryGroupsInPlace,
  makeRoundLimitResult,
} from './objectives.js';
import { createPieceInPlace, syncAllPieceStatsInPlace } from './pieces.js';
import {
  adjacentNodeIds,
  isNodeActive,
  nodeOccupyingFactions,
  stableNodeIds,
  stableProductionNodeIds,
} from './selectors.js';
import type {
  FactionId,
  GameState,
  NodeCaptureCause,
  NodeId,
  ProductionSlot,
} from './types.js';

function ensureProductionSlots(state: GameState, factionId: FactionId, nodeId: NodeId): ProductionSlot[] {
  const faction = requireFaction(state, factionId);
  const existing = faction.productionQueues[nodeId];
  if (existing) return existing;
  const count = requireNode(state, nodeId).productionSlots;
  const slots = Array.from({ length: count }, (_, index) => ({
    slotId: `${nodeId}:${index + 1}`,
    nodeId,
    orders: [],
  }));
  faction.productionQueues[nodeId] = slots;
  return slots;
}

export function recomputePopulationCapInPlace(state: GameState): void {
  for (const factionId of factionIds(state)) {
    const faction = requireFaction(state, factionId);
    faction.populationCap = faction.scenarioPopulationBonus + stableNodeIds(state, factionId)
      .reduce((sum, nodeId) => sum + requireNode(state, nodeId).population, 0);
  }
}

function deployHeadIfPossible(state: GameState, factionId: FactionId, slot: ProductionSlot): boolean {
  const order = slot.orders[0];
  if (!order || order.status !== 'waiting_deployment') return false;
  const node = requireNode(state, order.nodeId);
  const faction = requireFaction(state, factionId);
  if (nodeDeploymentSize(state, order.nodeId) + deploymentSizeForCard(order.cardId) > node.capacity) return false;
  if (faction.populationUsed + order.populationCost > faction.populationCap) return false;

  createPieceInPlace(state, factionId, order.cardId, order.nodeId, state.strategicRound + 1);
  faction.populationReserved = Math.max(0, faction.populationReserved - order.populationCost);
  faction.cards[order.cardId].producedCount += 1;
  slot.orders.shift();
  addGameEvent(state, {
    type: 'piece_deployed',
    factionId,
    nodeId: order.nodeId,
    cardId: order.cardId,
    message: `${faction.displayName}的${getCardDefinition(order.cardId).displayName}在 ${node.displayName} 部署完成；下战略回合开始贡献 AP。`,
  });
  return true;
}

export function progressProductionInPlace(state: GameState): void {
  progressCommanderProductionInPlace(state);
  for (const factionId of activeFactionIds(state)) {
    for (const nodeId of stableProductionNodeIds(state, factionId)) {
      const slots = ensureProductionSlots(state, factionId, nodeId);
      for (const slot of slots) {
        const order = slot.orders[0];
        if (!order) continue;
        if (order.status === 'building') {
          order.remainingRounds -= 1;
          if (order.remainingRounds <= 0) order.status = 'waiting_deployment';
          addGameEvent(state, {
            type: 'production_progressed',
            factionId,
            nodeId,
            cardId: order.cardId,
            message: `${getCardDefinition(order.cardId).displayName}生产推进，状态：${order.status === 'waiting_deployment' ? '等待部署' : `剩余 ${order.remainingRounds} 回合`}。`,
          });
        }
        deployHeadIfPossible(state, factionId, slot);
      }
    }
  }
}

export function computeActionPointsInPlace(state: GameState): void {
  const commanderPieceIds = new Set(Object.values(state.commanders)
    .map((commander) => commander.pieceInstanceId)
    .filter((pieceId): pieceId is string => pieceId !== null));
  for (const factionId of factionIds(state)) {
    const faction = requireFaction(state, factionId);
    if (faction.defeatedAtRound !== null) {
      faction.apLedger = {
        baseGenerated: 0,
        fieldGenerated: 0,
        baseRemaining: 0,
        fieldRemaining: 0,
        baseSpent: 0,
        fieldSpent: 0,
      };
      refreshFactionActionPoints(faction);
      continue;
    }
    const pieceAp = Object.values(state.pieces)
      .filter((piece) => (
        piece.factionId === factionId
        && piece.hp > 0
        && piece.commandReadyFromRound <= state.strategicRound
        && !commanderPieceIds.has(piece.pieceId)
      ))
      .reduce((sum, piece) => sum + memberApContribution(state, piece.pieceId), 0);
    const nodeAp = stableNodeIds(state, factionId)
      .reduce((sum, nodeId) => sum + requireNode(state, nodeId).apBonus, 0);
    const base = state.scenarioBaseAp + pieceAp + nodeAp;
    const field = fieldCommanderAp(state, factionId);
    faction.apLedger = {
      baseGenerated: base,
      fieldGenerated: field,
      baseRemaining: base,
      fieldRemaining: field,
      baseSpent: 0,
      fieldSpent: 0,
    };
    refreshFactionActionPoints(faction);
  }
}

export function startStrategicRoundInPlace(
  state: GameState,
  captureBeforeFirstFactionAction = false,
): void {
  if (captureBeforeFirstFactionAction) {
    const firstActiveFactionId = state.turnOrder.find((factionId) => !isFactionDefeated(state, factionId));
    if (firstActiveFactionId === undefined) {
      evaluateVictoryGroupsInPlace(state, 'VictoryGroupEliminated');
      return;
    }
    captureEncircledNodesAtTurnStartInPlace(state, firstActiveFactionId);
    if (state.result) return;
  }

  recomputePopulationCapInPlace(state);
  progressProductionInPlace(state);
  computeActionPointsInPlace(state);

  for (const piece of Object.values(state.pieces)) {
    piece.failedAssaultLocks = [];
    piece.movesThisRound = 0;
    piece.battlesThisRound = 0;
    piece.maxDistanceInRound = 0;
  }
  for (const factionId of factionIds(state)) {
    const faction = requireFaction(state, factionId);
    faction.planningCommitted = faction.defeatedAtRound !== null;
    for (const card of Object.values(faction.cards)) card.promotedThisSettlement = false;
  }

  const firstActiveIndex = state.turnOrder.findIndex((factionId) => !isFactionDefeated(state, factionId));
  if (firstActiveIndex < 0) {
    evaluateVictoryGroupsInPlace(state, 'VictoryGroupEliminated');
    return;
  }
  const firstFactionId = state.turnOrder[firstActiveIndex];
  if (firstFactionId === undefined) throw new Error('Turn order lost its first active faction.');
  state.activeTurnIndex = firstActiveIndex;
  state.initiativeFactionId = firstFactionId;
  state.activeFactionId = firstFactionId;
  state.phase = firstActiveIndex === 0 ? 'FIRST_FACTION_ACTION' : 'SECOND_FACTION_ACTION';
  addGameEvent(state, {
    type: 'round_started',
    message: `战略回合 ${state.strategicRound} 开始，${requireFaction(state, firstFactionId).displayName}率先行动。`,
    data: {
      factionOrder: [...state.turnOrder],
      factionAp: Object.fromEntries(factionIds(state).map((factionId) => [
        factionId,
        requireFaction(state, factionId).actionPoints,
      ])),
      redAp: state.factions.red?.actionPoints ?? 0,
      blueAp: state.factions.blue?.actionPoints ?? 0,
      redPopulationCap: state.factions.red?.populationCap ?? 0,
      bluePopulationCap: state.factions.blue?.populationCap ?? 0,
    },
  });
}

function settleCasualtyXpInPlace(state: GameState): void {
  for (const entry of state.casualtyLedger) {
    if (entry.settled) continue;
    requireFaction(state, entry.killerFactionId).xpPool += entry.killerXp;
    requireFaction(state, entry.deadFactionId).xpPool += entry.loserXp;
    entry.settled = true;
  }
  const current = state.casualtyLedger.filter((entry) => entry.strategicRound === state.strategicRound);
  for (const factionId of factionIds(state)) {
    const amount = current.reduce((sum, entry) => {
      if (entry.killerFactionId === factionId) sum += entry.killerXp;
      if (entry.deadFactionId === factionId) sum += entry.loserXp;
      return sum;
    }, 0);
    if (amount > 0) {
      addGameEvent(state, {
        type: 'xp_settled', factionId, amount,
        message: `${requireFaction(state, factionId).displayName}获得 ${amount} 点待分配经验。`,
      });
    }
  }
}

function recoverPiecesInPlace(state: GameState): void {
  for (const piece of Object.values(state.pieces)) {
    const node = requireNode(state, piece.nodeId);
    const before = piece.hp;
    if (node.ownerFactionId === piece.factionId && isNodeActive(state, piece.nodeId)) piece.hp = piece.maxHp;
    else piece.hp = Math.min(piece.maxHp, piece.hp + Math.ceil((piece.maxHp - piece.hp) / 3));
    if (piece.hp !== before) {
      addGameEvent(state, {
        type: 'recovery', factionId: piece.factionId, nodeId: piece.nodeId, pieceId: piece.pieceId,
        amount: piece.hp - before,
        message: `${piece.pieceId}恢复 ${piece.hp - before} HP。`,
      });
    }
  }
}

interface PendingNodeCapture {
  nodeId: NodeId;
  previousOwner: FactionId | null;
}

function applyNodeCaptureBatchInPlace(
  state: GameState,
  factionId: FactionId,
  captures: readonly PendingNodeCapture[],
  captureCause: NodeCaptureCause,
): void {
  if (captures.length === 0) return;

  // Eligibility is frozen before any write. Apply the full ownership batch first
  // so a captured command post cannot interrupt or influence sibling captures.
  for (const capture of captures) {
    const node = requireNode(state, capture.nodeId);
    node.ownerFactionId = factionId;
    node.activeFromRound = state.strategicRound + 1;
  }

  for (const capture of captures) {
    const node = requireNode(state, capture.nodeId);
    addGameEvent(state, {
      type: 'node_captured', factionId, nodeId: capture.nodeId, captureCause,
      message: captureCause === 'direct_end_turn'
        ? `${requireFaction(state, factionId).displayName}驻军占领 ${node.displayName}；下一战略回合激活。`
        : `${requireFaction(state, factionId).displayName}包围占领 ${node.displayName}；下一战略回合激活。`,
      data: { previousOwner: capture.previousOwner, captureCause },
    });
  }

  // Objective effects are another boundary step after the atomic color change.
  // Process every captured command post even if an earlier one forms a result.
  for (const capture of captures) captureCommandPostInPlace(state, factionId, capture.nodeId);
}

export function captureOccupiedNodesAtActionEndInPlace(state: GameState, factionId: FactionId): void {
  const captures = (Object.keys(state.map.nodes) as NodeId[])
    .sort()
    .flatMap((nodeId): PendingNodeCapture[] => {
      const previousOwner = requireNode(state, nodeId).ownerFactionId;
      if (previousOwner === factionId) return [];
      const occupiers = nodeOccupyingFactions(state, nodeId);
      return occupiers.length === 1 && occupiers[0] === factionId
        ? [{ nodeId, previousOwner }]
        : [];
    });
  applyNodeCaptureBatchInPlace(state, factionId, captures, 'direct_end_turn');
}

export function captureEncircledNodesAtTurnStartInPlace(state: GameState, factionId: FactionId): void {
  const nodeIds = (Object.keys(state.map.nodes) as NodeId[]).sort();
  const owners = new Map(nodeIds.map((nodeId) => [nodeId, requireNode(state, nodeId).ownerFactionId]));
  const captures = nodeIds.flatMap((nodeId): PendingNodeCapture[] => {
    const previousOwner = owners.get(nodeId) ?? null;
    if (previousOwner === factionId) return [];
    const adjacent = adjacentNodeIds(state, nodeId);
    if (adjacent.length === 0 || !adjacent.every((neighborId) => owners.get(neighborId) === factionId)) return [];
    return [{ nodeId, previousOwner }];
  });
  applyNodeCaptureBatchInPlace(state, factionId, captures, 'encirclement_turn_start');
}

function cancelInvalidProductionInPlace(state: GameState): void {
  for (const factionId of factionIds(state)) {
    const faction = requireFaction(state, factionId);
    for (const [nodeKey, slots] of Object.entries(faction.productionQueues)) {
      const nodeId = nodeKey as NodeId;
      if (!slots) continue;
      const node = requireNode(state, nodeId);
      const invalid = node.ownerFactionId !== factionId
        || nodeOccupyingFactions(state, nodeId).some((occupier) => occupier !== factionId);
      if (!invalid) continue;
      let released = 0;
      let count = 0;
      for (const slot of slots) {
        for (const order of slot.orders) {
          released += order.populationCost;
          count += 1;
        }
        slot.orders = [];
      }
      faction.populationReserved = Math.max(0, faction.populationReserved - released);
      if (count > 0) {
        addGameEvent(state, {
          type: 'production_cancelled', factionId, nodeId,
          amount: released,
          message: `${node.displayName}失稳，取消 ${count} 个订单；金币不退，释放 ${released} 预留人口。`,
        });
      }
    }
  }
}

function settleIncomeInPlace(state: GameState): void {
  for (const factionId of activeFactionIds(state)) {
    const faction = requireFaction(state, factionId);
    const baseIncome = stableNodeIds(state, factionId)
      .filter((nodeId) => isNodeActive(state, nodeId))
      .reduce((sum, nodeId) => sum + requireNode(state, nodeId).goldIncome, 0);
    const multiplier = faction.controller === 'ai' ? DIFFICULTY_GOLD_MULTIPLIER[state.difficulty] : 1;
    const income = Math.floor(baseIncome * multiplier);
    faction.gold += income;
    addGameEvent(state, {
      type: 'income', factionId, amount: income,
      message: `${faction.displayName}结算 ${income}G（基础 ${baseIncome}G，倍率 ${multiplier.toFixed(2)}）。`,
    });
  }
}

function hasWaitingUnit(state: GameState, factionId: FactionId): boolean {
  return Object.values(requireFaction(state, factionId).productionQueues).some((slots) => (
    slots?.some((slot) => slot.orders.some((order) => order.status === 'waiting_deployment')) ?? false
  ));
}

function hasValidQueue(state: GameState, factionId: FactionId): boolean {
  return stableProductionNodeIds(state, factionId).some((nodeId) => (
    requireFaction(state, factionId).productionQueues[nodeId]?.some((slot) => slot.orders.length > 0) ?? false
  ));
}

export function isFactionEliminated(state: GameState, factionId: FactionId): boolean {
  if (isFactionDefeated(state, factionId)) return true;
  const hasPieces = Object.values(state.pieces).some((piece) => piece.factionId === factionId && piece.hp > 0);
  const hasProduction = stableProductionNodeIds(state, factionId).length > 0;
  return !hasPieces && !hasWaitingUnit(state, factionId) && !hasValidQueue(state, factionId) && !hasProduction;
}

function roundLimitScore(state: GameState, factionId: FactionId): [number, number, number, number] {
  const stableProduction = stableProductionNodeIds(state, factionId).length;
  const strategicValue = stableNodeIds(state, factionId)
    .reduce((sum, nodeId) => sum + requireNode(state, nodeId).strategicValue, 0);
  const armyValue = Object.values(state.pieces)
    .filter((piece) => piece.factionId === factionId)
    .reduce((sum, piece) => sum + piece.productionGoldValue, 0);
  return [stableProduction, strategicValue, armyValue, requireFaction(state, factionId).gold];
}

function checkVictoryInPlace(state: GameState): boolean {
  for (const factionId of factionIds(state)) {
    if (!isFactionDefeated(state, factionId) && isFactionEliminated(state, factionId)) {
      defeatFactionInPlace(state, factionId, 'eliminated');
    }
  }
  if (evaluateVictoryGroupsInPlace(state)) return true;
  if (state.strategicRound >= MAX_STRATEGIC_ROUNDS) {
    const score = Object.fromEntries(factionIds(state).map((factionId) => [
      factionId,
      roundLimitScore(state, factionId),
    ])) as Record<FactionId, [number, number, number, number]>;
    applyGameResultInPlace(state, makeRoundLimitResult(state, score));
    return true;
  }
  return false;
}

export function runSettlementAutoInPlace(state: GameState): void {
  settleCasualtyXpInPlace(state);
  recoverPiecesInPlace(state);
  evacuateDownedPlayerAvatarsInPlace(state);
  if (state.result) return;
  cancelInvalidProductionInPlace(state);
  settleIncomeInPlace(state);
  if (checkVictoryInPlace(state)) return;
  state.phase = 'SETTLEMENT_PLANNING';
  state.activeFactionId = null;
  for (const factionId of factionIds(state)) {
    const faction = requireFaction(state, factionId);
    faction.planningCommitted = faction.defeatedAtRound !== null;
  }
}

export function finishPlanningAndAdvanceInPlace(state: GameState): void {
  syncAllPieceStatsInPlace(state);
  for (const factionId of factionIds(state)) {
    for (const card of Object.values(requireFaction(state, factionId).cards)) card.promotedThisSettlement = false;
  }
  state.strategicRound += 1;
  startStrategicRoundInPlace(state, true);
}
