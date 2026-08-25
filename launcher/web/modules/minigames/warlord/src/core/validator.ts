import { getCardDefinition } from '../data/cards.js';
import { PROMOTIONS } from '../data/config.js';
import { nodeIsAdjacent, nodeOccupyingFactions, isNodeActive, isNodeStable } from './selectors.js';
import type { GameCommand, GameState, MoveOrAttackCommand, NodeId } from './types.js';

export interface ValidationResult {
  ok: boolean;
  error?: string;
  actualPieceIds?: string[];
  isBattle?: boolean;
}

function fail(error: string): ValidationResult {
  return { ok: false, error };
}

function validateMove(state: GameState, command: MoveOrAttackCommand): ValidationResult {
  if (state.phase !== 'FIRST_FACTION_ACTION' && state.phase !== 'SECOND_FACTION_ACTION') {
    return fail('当前不是行动阶段。');
  }
  if (state.activeFactionId !== command.factionId) return fail('当前不是该阵营的行动时机。');
  if (command.originNodeId === command.targetNodeId) return fail('起点与目标节点不能相同。');
  if (!nodeIsAdjacent(command.originNodeId, command.targetNodeId)) return fail('目标节点与起点不相邻。');
  if (command.pieceIds.length === 0) return fail('至少选择一枚棋子。');
  if (new Set(command.pieceIds).size !== command.pieceIds.length) return fail('棋子列表包含重复项。');

  for (const pieceId of command.pieceIds) {
    const piece = state.pieces[pieceId];
    if (!piece || piece.hp <= 0) return fail(`棋子 ${pieceId} 不存在或已阵亡。`);
    if (piece.factionId !== command.factionId) return fail(`棋子 ${pieceId} 不属于当前阵营。`);
    if (piece.nodeId !== command.originNodeId) return fail(`棋子 ${pieceId} 不在起点节点。`);
  }

  const occupiers = nodeOccupyingFactions(state, command.targetNodeId);
  const enemies = occupiers.filter((factionId) => factionId !== command.factionId);
  const allies = occupiers.filter((factionId) => factionId === command.factionId);
  if (enemies.length > 0 && allies.length > 0) return fail('节点存在混合阵营驻军，状态非法。');
  const isBattle = enemies.length > 0;

  if (isBattle) {
    const node = state.map.nodes[command.targetNodeId];
    if (command.pieceIds.length > node.attackWidth) {
      return fail(`进攻宽度为 ${node.attackWidth}，当前选择 ${command.pieceIds.length} 枚棋子。`);
    }
    for (const pieceId of command.pieceIds) {
      const piece = state.pieces[pieceId];
      if (piece?.failedAssaultLocks.includes(command.targetNodeId)) {
        return fail(`${pieceId} 本战略回合已进攻该节点失败，不能立即重入。`);
      }
    }
    if (state.factions[command.factionId].actionPoints < command.pieceIds.length) {
      return fail(`公共 AP 不足，需要 ${command.pieceIds.length}。`);
    }
    return { ok: true, actualPieceIds: [...command.pieceIds], isBattle: true };
  }

  const node = state.map.nodes[command.targetNodeId];
  const available = Math.max(0, node.capacity - node.pieceIds.length);
  const actualPieceIds = command.pieceIds.slice(0, available);
  if (actualPieceIds.length === 0) return fail(`${node.displayName}已达到驻军容量。`);
  if (state.factions[command.factionId].actionPoints < actualPieceIds.length) {
    return fail(`公共 AP 不足，需要 ${actualPieceIds.length}。`);
  }
  return { ok: true, actualPieceIds, isBattle: false };
}

export function validateCommand(state: GameState, command: GameCommand): ValidationResult {
  if (state.phase === 'GAME_OVER') return fail('对局已经结束。');
  switch (command.type) {
    case 'MOVE_OR_ATTACK':
      return validateMove(state, command);
    case 'END_ACTION':
      if (state.phase !== 'FIRST_FACTION_ACTION' && state.phase !== 'SECOND_FACTION_ACTION') return fail('当前不是行动阶段。');
      if (state.activeFactionId !== command.factionId) return fail('当前不是该阵营的行动时机。');
      return { ok: true };
    case 'ALLOCATE_XP': {
      if (state.phase !== 'SETTLEMENT_PLANNING') return fail('当前不是结算规划阶段。');
      const faction = state.factions[command.factionId];
      if (faction.planningCommitted) return fail('该阵营已经提交规划。');
      if (!Number.isInteger(command.amount) || command.amount <= 0) return fail('经验分配量必须是正整数。');
      if (command.amount > faction.xpPool) return fail('待分配经验不足。');
      if (!faction.cards[command.cardId]) return fail('未知卡牌。');
      return { ok: true };
    }
    case 'PURCHASE_PROMOTION': {
      if (state.phase !== 'SETTLEMENT_PLANNING') return fail('当前不是结算规划阶段。');
      const faction = state.factions[command.factionId];
      if (faction.planningCommitted) return fail('该阵营已经提交规划。');
      const cardState = faction.cards[command.cardId];
      const definition = getCardDefinition(command.cardId);
      if (cardState.promotedThisSettlement) return fail('每张卡每个战略结算最多升阶一次。');
      const expected = definition.allowedPromotions[cardState.purchasedPromotions.length];
      if (!expected) return fail('该卡牌没有后续可购买升阶。');
      if (expected !== command.promotionId) return fail(`必须按序购买 ${expected}。`);
      const promotion = PROMOTIONS[command.promotionId];
      if (cardState.level < promotion.level) return fail(`需要卡牌达到 Lv.${promotion.level}。`);
      if (faction.gold < promotion.cost) return fail(`金币不足，需要 ${promotion.cost}G。`);
      return { ok: true };
    }
    case 'ENQUEUE_PRODUCTION': {
      if (state.phase !== 'SETTLEMENT_PLANNING') return fail('当前不是结算规划阶段。');
      const faction = state.factions[command.factionId];
      if (faction.planningCommitted) return fail('该阵营已经提交规划。');
      const node = state.map.nodes[command.nodeId];
      if (!node || node.productionSlots <= 0) return fail('目标节点不是生产节点。');
      if (!isNodeActive(state, command.nodeId) || !isNodeStable(state, command.nodeId, command.factionId)) {
        return fail('只有稳定、激活的己方生产节点可以接收订单。');
      }
      const slot = faction.productionQueues[command.nodeId]?.find((candidate) => candidate.slotId === command.slotId);
      if (!slot) return fail('生产槽不存在。');
      const definition = getCardDefinition(command.cardId);
      const cardState = faction.cards[command.cardId];
      if (cardState.level < definition.deploymentLevel) return fail(`卡牌需要 Lv.${definition.deploymentLevel} 才能生产。`);
      if (faction.gold < definition.productionCost) return fail(`金币不足，需要 ${definition.productionCost}G。`);
      if (faction.populationUsed + faction.populationReserved + definition.populationCost > faction.populationCap) {
        return fail('人口容量不足（含预留人口）。');
      }
      return { ok: true };
    }
    case 'CANCEL_PRODUCTION': {
      if (state.phase !== 'SETTLEMENT_PLANNING') return fail('当前不是结算规划阶段。');
      const faction = state.factions[command.factionId];
      if (faction.planningCommitted) return fail('该阵营已经提交规划。');
      const slot = faction.productionQueues[command.nodeId]?.find((candidate) => candidate.slotId === command.slotId);
      if (!slot) return fail('生产槽不存在。');
      const order = slot.orders.find((candidate) => candidate.orderId === command.orderId);
      if (!order) return fail('生产订单不存在或已离开该槽。');
      if (order.factionId !== command.factionId || order.nodeId !== command.nodeId || order.slotId !== command.slotId) {
        return fail('生产订单归属与目标槽不一致。');
      }
      const definition = getCardDefinition(order.cardId);
      if (order.status !== 'building' || order.remainingRounds !== definition.buildRounds) {
        return fail('订单已经获得生产进度，不能撤销。');
      }
      if (faction.populationReserved < order.populationCost) return fail('生产预留人口状态异常，不能撤销。');
      return { ok: true };
    }
    case 'COMMIT_PLANNING': {
      if (state.phase !== 'SETTLEMENT_PLANNING') return fail('当前不是结算规划阶段。');
      if (state.factions[command.factionId].planningCommitted) return fail('该阵营已经提交规划。');
      return { ok: true };
    }
  }
}

export function firstProductionSlotId(state: GameState, factionId: 'red' | 'blue', nodeId: NodeId): string | null {
  return state.factions[factionId].productionQueues[nodeId]?.[0]?.slotId ?? null;
}
