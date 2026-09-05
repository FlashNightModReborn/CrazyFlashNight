import { resolveBattle } from '../battle/resolver.js';
import { createBattleIdentity } from '../battle/identity.js';
import { getCardDefinition } from '../data/cards.js';
import { PROMOTIONS } from '../data/config.js';
import { requireNode } from './access.js';
import { enqueueCommanderProductionInPlace, handleCommanderCasualtyInPlace, redeployPlayerAvatarInPlace, } from './commanders.js';
import { addGameEvent } from './events.js';
import { activeFactionIds, nextActiveTurnIndex, requireFaction, spendFactionActionPointsInPlace, } from './factions.js';
import { captureEncircledNodesAtTurnStartInPlace, captureOccupiedNodesAtActionEndInPlace, finishPlanningAndAdvanceInPlace, runSettlementAutoInPlace, } from './lifecycle.js';
import { bounty, getRuntimeStats, needXp } from './math.js';
import { mergeTaskGroupInPlace, setFormationInPlace, splitTaskGroupInPlace, } from './organization.js';
import { movePiecesInPlace, removePieceInPlace } from './pieces.js';
import { piecesAtNode } from './selectors.js';
import { validateCommand } from './validator.js';
function cloneState(state) {
    return structuredClone(state);
}
function battleSnapshot(state, pieceId) {
    const piece = state.pieces[pieceId];
    if (!piece)
        throw new Error(`Missing piece ${pieceId}`);
    const cardState = requireFaction(state, piece.factionId).cards[piece.cardId];
    const definition = getCardDefinition(piece.cardId);
    const stats = getRuntimeStats(piece.cardId, cardState);
    return {
        pieceId: piece.pieceId,
        factionId: piece.factionId,
        cardId: piece.cardId,
        displayName: definition.displayName,
        behaviorId: definition.behaviorId,
        tags: [...definition.tags],
        formationRank: definition.formationRank,
        hp: piece.hp,
        maxHp: piece.maxHp,
        attack: stats.attack,
        defense: stats.defense,
        speed: stats.speed,
        frozenCardLevel: cardState.level,
    };
}
function executeMoveOrAttack(state, command, actualPieceIds, isBattle, commandLoad, defenderFactionId) {
    const faction = requireFaction(state, command.factionId);
    spendFactionActionPointsInPlace(faction, commandLoad);
    if (!isBattle) {
        movePiecesInPlace(state, actualPieceIds, command.targetNodeId);
        addGameEvent(state, {
            type: 'move',
            factionId: command.factionId,
            nodeId: command.targetNodeId,
            amount: actualPieceIds.length,
            message: `${faction.displayName}移动 ${actualPieceIds.length} 枚棋子至 ${requireNode(state, command.targetNodeId).displayName}。`,
            data: { originNodeId: command.originNodeId, pieceIds: actualPieceIds },
        });
        return undefined;
    }
    const defenderIds = piecesAtNode(state, command.targetNodeId)
        .filter((piece) => piece.factionId === defenderFactionId)
        .map((piece) => piece.pieceId);
    state.battleOrdinal += 1;
    const { battleId, seed } = createBattleIdentity({
        gameSeed: state.gameSeed,
        strategicRound: state.strategicRound,
        battleOrdinal: state.battleOrdinal,
        attackerIds: actualPieceIds,
        defenderIds,
    });
    const node = requireNode(state, command.targetNodeId);
    const attackerSnapshots = actualPieceIds.map((pieceId) => battleSnapshot(state, pieceId));
    const defenderSnapshots = defenderIds.map((pieceId) => battleSnapshot(state, pieceId));
    const result = resolveBattle({
        battleId,
        seed,
        strategicRound: state.strategicRound,
        commandSequence: state.commandSequence,
        nodeId: command.targetNodeId,
        nodeDefenseBonus: node.defenseBonus,
        attackerOriginNodeId: command.originNodeId,
        attackerUnits: attackerSnapshots,
        defenderUnits: defenderSnapshots,
    });
    const record = {
        battleId,
        seed,
        strategicRound: state.strategicRound,
        commandSequence: state.commandSequence,
        nodeId: command.targetNodeId,
        attackerOriginNodeId: command.originNodeId,
        attackerPieceIds: [...actualPieceIds],
        defenderPieceIds: defenderIds,
        attackerSnapshots: structuredClone(attackerSnapshots),
        defenderSnapshots: structuredClone(defenderSnapshots),
        result,
    };
    state.battles.push(record);
    for (const pieceResult of result.pieceResults) {
        const piece = state.pieces[pieceResult.pieceId];
        if (piece)
            piece.hp = pieceResult.hpAfter;
    }
    for (const pieceId of actualPieceIds) {
        const piece = state.pieces[pieceId];
        if (piece)
            piece.battlesThisRound += 1;
    }
    for (const pieceId of defenderIds) {
        const piece = state.pieces[pieceId];
        if (piece)
            piece.battlesThisRound += 1;
    }
    for (const casualty of result.casualties) {
        const value = bounty(casualty.cardId, casualty.frozenCardLevel);
        state.casualtyLedger.push({
            casualtyId: `${battleId}:${casualty.pieceId}`,
            strategicRound: state.strategicRound,
            battleId,
            deadPieceId: casualty.pieceId,
            deadFactionId: casualty.factionId,
            killerFactionId: casualty.killerFactionId,
            cardId: casualty.cardId,
            frozenCardLevel: casualty.frozenCardLevel,
            bounty: value,
            killerXp: value,
            loserXp: value * 3,
            settled: false,
        });
        addGameEvent(state, {
            type: 'piece_died',
            factionId: casualty.factionId,
            pieceId: casualty.pieceId,
            cardId: casualty.cardId,
            message: `${casualty.pieceId}阵亡；击杀方待结算 ${value} XP，损失方待结算 ${value * 3} XP。`,
            data: { battleId, killerFactionId: casualty.killerFactionId },
        });
        handleCommanderCasualtyInPlace(state, casualty.pieceId);
        removePieceInPlace(state, casualty.pieceId);
    }
    if (result.winner === 'attacker') {
        movePiecesInPlace(state, actualPieceIds.filter((pieceId) => state.pieces[pieceId] !== undefined), command.targetNodeId);
    }
    else if (result.reason !== 'mutual_wipe') {
        for (const pieceId of actualPieceIds) {
            const piece = state.pieces[pieceId];
            if (piece && !piece.failedAssaultLocks.includes(command.targetNodeId)) {
                piece.failedAssaultLocks.push(command.targetNodeId);
            }
        }
    }
    addGameEvent(state, {
        type: 'battle_resolved',
        factionId: command.factionId,
        nodeId: command.targetNodeId,
        message: `${node.displayName}战斗结束：${result.winner === 'attacker' ? '进攻方胜利' : '守方守住'}，${result.battleRounds} 个战斗回合。`,
        data: { battleId, reason: result.reason, attackerPieceIds: actualPieceIds, defenderPieceIds: defenderIds },
    });
    return battleId;
}
function executeAllocateXp(state, command) {
    const faction = requireFaction(state, command.factionId);
    const card = faction.cards[command.cardId];
    const beforeLevel = card.level;
    faction.xpPool -= command.amount;
    card.totalXpAllocated += command.amount;
    card.xpIntoLevel += command.amount;
    while (card.level < 50) {
        const required = needXp(command.cardId, card.level);
        if (card.xpIntoLevel < required)
            break;
        card.xpIntoLevel -= required;
        card.level += 1;
    }
    addGameEvent(state, {
        type: 'xp_allocated', factionId: command.factionId, cardId: command.cardId, amount: command.amount,
        message: `${faction.displayName}向${getCardDefinition(command.cardId).displayName}投入 ${command.amount} XP。`,
    });
    if (card.level !== beforeLevel) {
        addGameEvent(state, {
            type: 'card_level_up', factionId: command.factionId, cardId: command.cardId, amount: card.level - beforeLevel,
            message: `${getCardDefinition(command.cardId).displayName}从 Lv.${beforeLevel} 升至 Lv.${card.level}，溢出经验保留。`,
        });
    }
}
function executePromotion(state, command) {
    const faction = requireFaction(state, command.factionId);
    const card = faction.cards[command.cardId];
    const promotion = PROMOTIONS[command.promotionId];
    faction.gold -= promotion.cost;
    card.purchasedPromotions.push(command.promotionId);
    card.promotedThisSettlement = true;
    addGameEvent(state, {
        type: 'promotion_purchased', factionId: command.factionId, cardId: command.cardId, amount: promotion.cost,
        message: `${faction.displayName}为${getCardDefinition(command.cardId).displayName}购买${command.promotionId}（-${promotion.cost}G）。`,
    });
}
function executeEnqueueProduction(state, command) {
    const faction = requireFaction(state, command.factionId);
    const definition = getCardDefinition(command.cardId);
    const slot = faction.productionQueues[command.nodeId]?.find((candidate) => candidate.slotId === command.slotId);
    if (!slot)
        throw new Error(`Validated production slot disappeared: ${command.slotId}`);
    state.nextOrderOrdinal += 1;
    const orderId = `o${state.nextOrderOrdinal}`;
    slot.orders.push({
        orderId,
        factionId: command.factionId,
        nodeId: command.nodeId,
        slotId: command.slotId,
        cardId: command.cardId,
        remainingRounds: definition.buildRounds,
        status: 'building',
        populationCost: definition.populationCost,
        goldCost: definition.productionCost,
        enqueuedRound: state.strategicRound,
    });
    faction.gold -= definition.productionCost;
    faction.populationReserved += definition.populationCost;
    addGameEvent(state, {
        type: 'production_enqueued', factionId: command.factionId, nodeId: command.nodeId,
        cardId: command.cardId, amount: definition.productionCost,
        message: `${faction.displayName}在 ${requireNode(state, command.nodeId).displayName}/${command.slotId} 下达${definition.displayName}订单。`,
        data: { orderId },
    });
}
function executeCancelProduction(state, command) {
    const faction = requireFaction(state, command.factionId);
    const slot = faction.productionQueues[command.nodeId]?.find((candidate) => candidate.slotId === command.slotId);
    if (!slot)
        throw new Error(`Validated production slot disappeared: ${command.slotId}`);
    const orderIndex = slot.orders.findIndex((candidate) => candidate.orderId === command.orderId);
    if (orderIndex < 0)
        throw new Error(`Validated production order disappeared: ${command.orderId}`);
    const [order] = slot.orders.splice(orderIndex, 1);
    if (!order)
        throw new Error(`Validated production order disappeared: ${command.orderId}`);
    faction.gold += order.goldCost;
    faction.populationReserved -= order.populationCost;
    addGameEvent(state, {
        type: 'production_cancelled',
        factionId: command.factionId,
        nodeId: command.nodeId,
        cardId: order.cardId,
        amount: order.goldCost,
        message: `${faction.displayName}主动撤销${getCardDefinition(order.cardId).displayName}订单；返还 ${order.goldCost}G，释放 ${order.populationCost} 预留人口。`,
        data: {
            orderId: order.orderId,
            reason: 'player_undo',
            refundGold: order.goldCost,
            releasedPopulation: order.populationCost,
        },
    });
}
export function applyCommand(state, command) {
    const validation = validateCommand(state, command);
    if (!validation.ok) {
        return {
            ok: false,
            state,
            reasonCode: validation.reasonCode,
            reasonParams: validation.reasonParams,
            error: validation.error ?? '命令非法。',
        };
    }
    const next = cloneState(state);
    next.commandSequence += 1;
    next.commandHistory.push({ sequence: next.commandSequence, command: structuredClone(command) });
    let battleId;
    switch (command.type) {
        case 'MOVE_OR_ATTACK':
            battleId = executeMoveOrAttack(next, command, validation.actualPieceIds ?? command.pieceIds, validation.isBattle ?? false, validation.commandLoad ?? command.pieceIds.length, validation.defenderFactionId);
            break;
        case 'MERGE_TASK_GROUP': {
            const element = mergeTaskGroupInPlace(next, command.commandElementIds, command.taskGroupTemplateId, command.formationProfileId);
            addGameEvent(next, {
                type: 'task_group_merged',
                factionId: command.factionId,
                nodeId: command.nodeId,
                amount: element.memberIds.length,
                message: `${requireFaction(next, command.factionId).displayName}在${requireNode(next, command.nodeId).displayName}合并为 ${element.memberIds.length} 人任务编组。`,
                data: {
                    commandElementId: element.elementId,
                    memberIds: [...element.memberIds],
                    formationProfileId: element.formationProfileId,
                },
            });
            break;
        }
        case 'SPLIT_TASK_GROUP': {
            const split = splitTaskGroupInPlace(next, command.commandElementId, command.memberIds);
            addGameEvent(next, {
                type: 'task_group_split',
                factionId: command.factionId,
                nodeId: command.nodeId,
                amount: split.extracted.length,
                message: `${requireFaction(next, command.factionId).displayName}在${requireNode(next, command.nodeId).displayName}拆出 ${split.extracted.length} 支独立部队。`,
                data: {
                    sourceCommandElementId: command.commandElementId,
                    extractedMemberIds: [...command.memberIds],
                    remainingCommandElementId: split.remaining?.elementId ?? null,
                },
            });
            break;
        }
        case 'SET_FORMATION':
            setFormationInPlace(next, command.commandElementId, command.formationProfileId);
            addGameEvent(next, {
                type: 'formation_changed',
                factionId: command.factionId,
                nodeId: command.nodeId,
                message: `${requireFaction(next, command.factionId).displayName}完成阵型调整。`,
                data: {
                    commandElementId: command.commandElementId,
                    formationProfileId: command.formationProfileId,
                },
            });
            break;
        case 'END_ACTION':
            addGameEvent(next, { type: 'action_ended', factionId: command.factionId, message: `${requireFaction(next, command.factionId).displayName}结束行动。` });
            captureOccupiedNodesAtActionEndInPlace(next, command.factionId);
            if (next.result)
                break;
            {
                const nextIndex = nextActiveTurnIndex(next, next.activeTurnIndex);
                if (nextIndex !== null) {
                    const nextFactionId = next.turnOrder[nextIndex];
                    if (nextFactionId === undefined)
                        throw new Error('Turn order cursor escaped its bounds.');
                    captureEncircledNodesAtTurnStartInPlace(next, nextFactionId);
                    if (!next.result) {
                        next.activeTurnIndex = nextIndex;
                        next.phase = nextIndex === 0 ? 'FIRST_FACTION_ACTION' : 'SECOND_FACTION_ACTION';
                        next.activeFactionId = nextFactionId;
                    }
                }
                else {
                    next.activeFactionId = null;
                    runSettlementAutoInPlace(next);
                }
            }
            break;
        case 'ALLOCATE_XP':
            executeAllocateXp(next, command);
            break;
        case 'PURCHASE_PROMOTION':
            executePromotion(next, command);
            break;
        case 'ENQUEUE_PRODUCTION':
            executeEnqueueProduction(next, command);
            break;
        case 'CANCEL_PRODUCTION':
            executeCancelProduction(next, command);
            break;
        case 'COMMIT_PLANNING':
            requireFaction(next, command.factionId).planningCommitted = true;
            addGameEvent(next, { type: 'planning_committed', factionId: command.factionId, message: `${requireFaction(next, command.factionId).displayName}提交结算规划。` });
            if (activeFactionIds(next).every((factionId) => requireFaction(next, factionId).planningCommitted)) {
                finishPlanningAndAdvanceInPlace(next);
            }
            break;
        case 'ENQUEUE_COMMANDER_PRODUCTION':
            enqueueCommanderProductionInPlace(next, command.commanderId);
            break;
        case 'REDEPLOY_PLAYER_AVATAR':
            redeployPlayerAvatarInPlace(next, command.commanderId, command.nodeId);
            break;
    }
    return { ok: true, state: next, battleId };
}
export function applyCommands(state, commands) {
    let current = state;
    let lastBattleId;
    for (const command of commands) {
        const result = applyCommand(current, command);
        if (!result.ok)
            return result;
        current = result.state;
        if (result.battleId)
            lastBattleId = result.battleId;
    }
    return { ok: true, state: current, battleId: lastBattleId };
}
//# sourceMappingURL=engine.js.map