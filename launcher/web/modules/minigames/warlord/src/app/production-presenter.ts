import { hasStableSupplyPath, isNodeActive, isNodeStable, nodeOccupyingFactions } from '../core/selectors.js';
import type {
  CardId,
  FactionId,
  GameState,
  NodeId,
  ProductionOrder,
  ProductionSlot,
} from '../core/types.js';
import { validateCommand } from '../core/validator.js';
import { getCardDefinition } from '../data/cards.js';

export type ProductionControlMode = 'auto' | 'exact';
export type ProductionLaneState = 'idle' | 'building' | 'waiting_deployment' | 'paused';

export interface ProductionOrderProjection {
  orderId: string;
  cardId: CardId;
  displayName: string;
  portraitRef: string;
  phaseLabel: string;
  remainingRounds: number;
  progressPercent: number;
  queuePosition: number;
  goldCost: number;
  populationCost: number;
  cancellable: boolean;
  cancelReason: string | null;
}

export interface ProductionLaneProjection {
  nodeId: NodeId;
  slotId: string;
  slotNumber: number;
  state: ProductionLaneState;
  stateLabel: string;
  queueLength: number;
  workRounds: number;
  blocked: boolean;
  blockerLabels: string[];
  head: ProductionOrderProjection | null;
  tail: ProductionOrderProjection[];
}

export interface ProductionNodeProjection {
  nodeId: NodeId;
  displayName: string;
  active: boolean;
  stable: boolean;
  occupied: number;
  capacity: number;
  freeCapacity: number;
  orderCount: number;
  lanes: ProductionLaneProjection[];
}

export interface ProductionNetworkOrderProjection extends ProductionOrderProjection {
  nodeId: NodeId;
  nodeDisplayName: string;
  slotId: string;
  slotNumber: number;
  laneState: ProductionLaneState;
}

export interface ProductionLaneRecommendation {
  nodeId: NodeId;
  slotId: string;
  reason: string;
}

export interface ProductionChoice {
  ok: boolean;
  error: string | null;
  mode: ProductionControlMode;
  nodeId: NodeId | null;
  slotId: string | null;
  nodeName: string | null;
  slotNumber: number | null;
  reason: string;
}

function slotNumber(slotId: string, fallback: number): number {
  const parsed = Number(slotId.split(':').at(-1));
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function nodePauseReasons(state: GameState, factionId: FactionId, nodeId: NodeId): string[] {
  const node = state.map.nodes[nodeId];
  if (node.ownerFactionId !== factionId) return ['据点已失守'];
  if (nodeOccupyingFactions(state, nodeId).some((occupier) => occupier !== factionId)) return ['敌军占据'];
  if (!isNodeActive(state, nodeId)) return ['据点尚未激活'];
  if (!hasStableSupplyPath(state, factionId, nodeId)) return ['补给线中断'];
  return isNodeStable(state, nodeId, factionId) ? [] : ['据点失稳'];
}

function deploymentBlockers(
  state: GameState,
  factionId: FactionId,
  order: ProductionOrder,
): string[] {
  const node = state.map.nodes[order.nodeId];
  const faction = state.factions[factionId];
  const blockers = nodePauseReasons(state, factionId, order.nodeId);
  if (node.pieceIds.length >= node.capacity) blockers.push(`驻军容量 ${node.pieceIds.length}/${node.capacity}`);
  if (faction.populationUsed + order.populationCost > faction.populationCap) {
    blockers.push(`人口 ${faction.populationUsed}+${order.populationCost}/${faction.populationCap}`);
  }
  return blockers;
}

function projectOrder(
  state: GameState,
  factionId: FactionId,
  order: ProductionOrder,
  queuePosition: number,
): ProductionOrderProjection {
  const definition = getCardDefinition(order.cardId);
  const isHead = queuePosition === 0;
  const waiting = isHead && order.status === 'waiting_deployment';
  const completedRounds = Math.max(0, definition.buildRounds - order.remainingRounds);
  const cancellation = validateCommand(state, {
    type: 'CANCEL_PRODUCTION',
    factionId,
    nodeId: order.nodeId,
    slotId: order.slotId,
    orderId: order.orderId,
  });
  return {
    orderId: order.orderId,
    cardId: order.cardId,
    displayName: definition.displayName,
    portraitRef: definition.identifier,
    phaseLabel: !isHead ? '待开工' : waiting ? '等待部署' : `剩余 ${Math.max(0, order.remainingRounds)} 回合`,
    remainingRounds: order.remainingRounds,
    progressPercent: waiting
      ? 100
      : Math.max(0, Math.min(100, Math.round((completedRounds / Math.max(1, definition.buildRounds)) * 100))),
    queuePosition,
    goldCost: order.goldCost,
    populationCost: order.populationCost,
    cancellable: cancellation.ok,
    cancelReason: cancellation.error ?? null,
  };
}

function projectLane(
  state: GameState,
  factionId: FactionId,
  slot: ProductionSlot,
  index: number,
): ProductionLaneProjection {
  const orders = slot.orders.map((order, queuePosition) => projectOrder(state, factionId, order, queuePosition));
  const sourceHead = slot.orders[0] ?? null;
  const head = orders[0] ?? null;
  const pauseReasons = nodePauseReasons(state, factionId, slot.nodeId);
  const blockerLabels = sourceHead?.status === 'waiting_deployment'
    ? deploymentBlockers(state, factionId, sourceHead)
    : pauseReasons;
  const paused = !!sourceHead && pauseReasons.length > 0;
  const stateLabel = !sourceHead
    ? '空闲'
    : paused ? '生产暂停' : sourceHead.status === 'waiting_deployment' ? '等待部署' : '生产中';
  const laneState: ProductionLaneState = !sourceHead
    ? 'idle'
    : paused ? 'paused' : sourceHead.status;
  const workRounds = slot.orders.reduce((total, order, orderIndex) => {
    if (orderIndex === 0 && order.status === 'building') return total + Math.max(0, order.remainingRounds);
    if (orderIndex === 0 && order.status === 'waiting_deployment') return total;
    return total + getCardDefinition(order.cardId).buildRounds;
  }, 0);
  return {
    nodeId: slot.nodeId,
    slotId: slot.slotId,
    slotNumber: slotNumber(slot.slotId, index + 1),
    state: laneState,
    stateLabel,
    queueLength: orders.length,
    workRounds,
    blocked: paused || sourceHead?.status === 'waiting_deployment',
    blockerLabels,
    head,
    tail: orders.slice(1),
  };
}

export function projectProductionNodes(state: GameState, factionId: FactionId): ProductionNodeProjection[] {
  return (Object.keys(state.map.nodes) as NodeId[])
    .filter((nodeId) => {
      const node = state.map.nodes[nodeId];
      return node.productionSlots > 0
        && (node.ownerFactionId === factionId || (state.factions[factionId].productionQueues[nodeId]?.length ?? 0) > 0);
    })
    .map((nodeId) => {
      const node = state.map.nodes[nodeId];
      const slots = state.factions[factionId].productionQueues[nodeId] ?? [];
      const lanes = slots.map((slot, index) => projectLane(state, factionId, slot, index));
      return {
        nodeId,
        displayName: node.displayName,
        active: isNodeActive(state, nodeId),
        stable: isNodeStable(state, nodeId, factionId),
        occupied: node.pieceIds.length,
        capacity: node.capacity,
        freeCapacity: Math.max(0, node.capacity - node.pieceIds.length),
        orderCount: lanes.reduce((total, lane) => total + lane.queueLength, 0),
        lanes,
      };
    })
    .sort((a, b) => a.nodeId.localeCompare(b.nodeId));
}

export function flattenProductionOrders(
  nodes: readonly ProductionNodeProjection[],
): ProductionNetworkOrderProjection[] {
  return nodes
    .flatMap((node) => node.lanes.flatMap((lane) => [lane.head, ...lane.tail]
      .filter((order): order is ProductionOrderProjection => order !== null)
      .map((order) => ({
        ...order,
        nodeId: node.nodeId,
        nodeDisplayName: node.displayName,
        slotId: lane.slotId,
        slotNumber: lane.slotNumber,
        laneState: lane.state,
      }))))
    .sort((a, b) => a.nodeId.localeCompare(b.nodeId)
      || a.slotNumber - b.slotNumber
      || a.queuePosition - b.queuePosition
      || a.orderId.localeCompare(b.orderId));
}

interface RankedLane {
  node: ProductionNodeProjection;
  lane: ProductionLaneProjection;
}

function compareRankedLanes(a: RankedLane, b: RankedLane): number {
  return Number(a.lane.blocked) - Number(b.lane.blocked)
    || a.lane.workRounds - b.lane.workRounds
    || a.lane.queueLength - b.lane.queueLength
    || b.node.freeCapacity - a.node.freeCapacity
    || a.node.nodeId.localeCompare(b.node.nodeId)
    || a.lane.slotId.localeCompare(b.lane.slotId);
}

function rankedStableLanes(state: GameState, factionId: FactionId): RankedLane[] {
  return projectProductionNodes(state, factionId)
    .filter((node) => node.active && node.stable)
    .flatMap((node) => node.lanes.map((lane) => ({ node, lane })))
    .sort(compareRankedLanes);
}

function recommendationReason(node: ProductionNodeProjection, lane: ProductionLaneProjection): string {
  if (lane.queueLength === 0) return `空闲槽 · 部署余量 ${node.freeCapacity}/${node.capacity}`;
  if (lane.blocked) return `其余槽同样受阻 · 当前 ${lane.queueLength} 单`;
  return `最低负载 · ${lane.workRounds} 回合 / ${lane.queueLength} 单`;
}

export function recommendProductionLane(
  state: GameState,
  factionId: FactionId,
): ProductionLaneRecommendation | null {
  const ranked = rankedStableLanes(state, factionId);
  const preferred = ranked.find((entry) => !entry.lane.blocked) ?? ranked[0];
  if (!preferred) return null;
  return {
    nodeId: preferred.node.nodeId,
    slotId: preferred.lane.slotId,
    reason: recommendationReason(preferred.node, preferred.lane),
  };
}

function choiceFrom(
  state: GameState,
  factionId: FactionId,
  cardId: CardId,
  mode: ProductionControlMode,
  nodeId: NodeId,
  slotId: string,
  reason: string,
): ProductionChoice {
  const validation = validateCommand(state, {
    type: 'ENQUEUE_PRODUCTION',
    factionId,
    nodeId,
    slotId,
    cardId,
  });
  return {
    ok: validation.ok,
    error: validation.error ?? null,
    mode,
    nodeId,
    slotId,
    nodeName: state.map.nodes[nodeId]?.displayName ?? nodeId,
    slotNumber: slotNumber(slotId, 1),
    reason,
  };
}

export function resolveProductionChoice(
  state: GameState,
  factionId: FactionId,
  cardId: CardId,
  mode: ProductionControlMode,
  exactNodeId: NodeId,
  exactSlotId: string,
): ProductionChoice {
  if (mode === 'exact') {
    return choiceFrom(state, factionId, cardId, mode, exactNodeId, exactSlotId, '人工指定槽位');
  }

  const ranked = rankedStableLanes(state, factionId);
  for (const entry of ranked) {
    const choice = choiceFrom(
      state,
      factionId,
      cardId,
      mode,
      entry.node.nodeId,
      entry.lane.slotId,
      recommendationReason(entry.node, entry.lane),
    );
    if (choice.ok) return choice;
  }

  const fallback = ranked[0]
    ?? projectProductionNodes(state, factionId).flatMap((node) => node.lanes.map((lane) => ({ node, lane })))[0];
  if (fallback) {
    return choiceFrom(
      state,
      factionId,
      cardId,
      mode,
      fallback.node.nodeId,
      fallback.lane.slotId,
      recommendationReason(fallback.node, fallback.lane),
    );
  }
  return choiceFrom(state, factionId, cardId, mode, exactNodeId, exactSlotId, '没有可用生产槽');
}
