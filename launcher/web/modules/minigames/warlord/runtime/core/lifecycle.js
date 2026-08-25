import { DIFFICULTY_GOLD_MULTIPLIER, MAX_STRATEGIC_ROUNDS } from '../data/config.js';
import { getCardDefinition } from '../data/cards.js';
import { addGameEvent } from './events.js';
import { createPieceInPlace, syncAllPieceStatsInPlace } from './pieces.js';
import { hasStableSupplyPath, isNodeActive, isNodeStable, nodeOccupyingFactions, stableNodeIds, stableProductionNodeIds, } from './selectors.js';
function ensureProductionSlots(state, factionId, nodeId) {
    const faction = state.factions[factionId];
    const existing = faction.productionQueues[nodeId];
    if (existing)
        return existing;
    const count = state.map.nodes[nodeId].productionSlots;
    const slots = Array.from({ length: count }, (_, index) => ({
        slotId: `${nodeId}:${index + 1}`,
        nodeId,
        orders: [],
    }));
    faction.productionQueues[nodeId] = slots;
    return slots;
}
export function recomputePopulationCapInPlace(state) {
    for (const factionId of ['red', 'blue']) {
        const faction = state.factions[factionId];
        faction.populationCap = faction.scenarioPopulationBonus + stableNodeIds(state, factionId)
            .reduce((sum, nodeId) => sum + state.map.nodes[nodeId].population, 0);
    }
}
function deployHeadIfPossible(state, factionId, slot) {
    const order = slot.orders[0];
    if (!order || order.status !== 'waiting_deployment')
        return false;
    const node = state.map.nodes[order.nodeId];
    const faction = state.factions[factionId];
    if (node.pieceIds.length >= node.capacity)
        return false;
    if (faction.populationUsed + order.populationCost > faction.populationCap)
        return false;
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
export function progressProductionInPlace(state) {
    for (const factionId of ['red', 'blue']) {
        for (const nodeId of stableProductionNodeIds(state, factionId)) {
            const slots = ensureProductionSlots(state, factionId, nodeId);
            for (const slot of slots) {
                const order = slot.orders[0];
                if (!order)
                    continue;
                if (order.status === 'building') {
                    order.remainingRounds -= 1;
                    if (order.remainingRounds <= 0)
                        order.status = 'waiting_deployment';
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
export function computeActionPointsInPlace(state) {
    for (const factionId of ['red', 'blue']) {
        const pieceAp = Object.values(state.pieces).filter((piece) => (piece.factionId === factionId
            && piece.hp > 0
            && piece.commandReadyFromRound <= state.strategicRound)).length;
        const nodeAp = stableNodeIds(state, factionId)
            .reduce((sum, nodeId) => sum + state.map.nodes[nodeId].apBonus, 0);
        const total = pieceAp + nodeAp;
        const faction = state.factions[factionId];
        faction.actionPoints = total;
        faction.apGeneratedThisRound = total;
        faction.apSpentThisRound = 0;
    }
}
export function startStrategicRoundInPlace(state) {
    recomputePopulationCapInPlace(state);
    progressProductionInPlace(state);
    computeActionPointsInPlace(state);
    for (const piece of Object.values(state.pieces)) {
        piece.failedAssaultLocks = [];
        piece.movesThisRound = 0;
        piece.battlesThisRound = 0;
        piece.maxDistanceInRound = 0;
    }
    for (const factionId of ['red', 'blue']) {
        state.factions[factionId].planningCommitted = false;
        for (const card of Object.values(state.factions[factionId].cards))
            card.promotedThisSettlement = false;
    }
    state.initiativeFactionId = state.strategicRound % 2 === 1 ? 'red' : 'blue';
    state.activeFactionId = state.initiativeFactionId;
    state.phase = 'FIRST_FACTION_ACTION';
    addGameEvent(state, {
        type: 'round_started',
        message: `战略回合 ${state.strategicRound} 开始，${state.factions[state.initiativeFactionId].displayName}先手。`,
        data: {
            redAp: state.factions.red.actionPoints,
            blueAp: state.factions.blue.actionPoints,
            redPopulationCap: state.factions.red.populationCap,
            bluePopulationCap: state.factions.blue.populationCap,
        },
    });
}
function settleCasualtyXpInPlace(state) {
    for (const entry of state.casualtyLedger) {
        if (entry.settled)
            continue;
        state.factions[entry.killerFactionId].xpPool += entry.killerXp;
        state.factions[entry.deadFactionId].xpPool += entry.loserXp;
        entry.settled = true;
    }
    const current = state.casualtyLedger.filter((entry) => entry.strategicRound === state.strategicRound);
    for (const factionId of ['red', 'blue']) {
        const amount = current.reduce((sum, entry) => {
            if (entry.killerFactionId === factionId)
                sum += entry.killerXp;
            if (entry.deadFactionId === factionId)
                sum += entry.loserXp;
            return sum;
        }, 0);
        if (amount > 0) {
            addGameEvent(state, {
                type: 'xp_settled', factionId, amount,
                message: `${state.factions[factionId].displayName}获得 ${amount} 点待分配经验。`,
            });
        }
    }
}
function recoverPiecesInPlace(state) {
    for (const piece of Object.values(state.pieces)) {
        const node = state.map.nodes[piece.nodeId];
        const before = piece.hp;
        if (node.ownerFactionId === piece.factionId) {
            piece.hp = piece.maxHp;
        }
        else {
            piece.hp = Math.min(piece.maxHp, piece.hp + Math.ceil((piece.maxHp - piece.hp) / 3));
        }
        if (piece.hp !== before) {
            addGameEvent(state, {
                type: 'recovery', factionId: piece.factionId, nodeId: piece.nodeId, pieceId: piece.pieceId,
                amount: piece.hp - before,
                message: `${piece.pieceId}恢复 ${piece.hp - before} HP。`,
            });
        }
    }
}
function makeSettlementSnapshot(state) {
    const nodeIds = Object.keys(state.map.nodes);
    return {
        stable: {
            red: new Set(nodeIds.filter((nodeId) => isNodeStable(state, nodeId, 'red'))),
            blue: new Set(nodeIds.filter((nodeId) => isNodeStable(state, nodeId, 'blue'))),
        },
        occupants: Object.fromEntries(nodeIds.map((nodeId) => [nodeId, nodeOccupyingFactions(state, nodeId)])),
        owners: Object.fromEntries(nodeIds.map((nodeId) => [nodeId, state.map.nodes[nodeId].ownerFactionId])),
    };
}
function canCaptureFromSnapshot(state, snapshot, factionId, targetNodeId) {
    const adjacentStable = state.map.edges
        .flatMap((edge) => edge.a === targetNodeId ? [edge.b] : edge.b === targetNodeId ? [edge.a] : [])
        .filter((nodeId) => snapshot.stable[factionId].has(nodeId));
    return adjacentStable.some((nodeId) => hasStableSupplyPath(state, factionId, nodeId, snapshot.stable[factionId]));
}
function captureNodesInPlace(state, snapshot) {
    for (const nodeId of Object.keys(state.map.nodes).sort()) {
        const occupiers = snapshot.occupants[nodeId];
        if (occupiers.length !== 1)
            continue;
        const occupier = occupiers[0];
        if (!occupier || snapshot.owners[nodeId] === occupier)
            continue;
        if (!canCaptureFromSnapshot(state, snapshot, occupier, nodeId))
            continue;
        const node = state.map.nodes[nodeId];
        const previousOwner = node.ownerFactionId;
        node.ownerFactionId = occupier;
        node.activeFromRound = state.strategicRound + 1;
        addGameEvent(state, {
            type: 'node_captured', factionId: occupier, nodeId,
            message: `${state.factions[occupier].displayName}占领 ${node.displayName}；下一战略回合激活。`,
            data: { previousOwner },
        });
    }
}
function cancelInvalidProductionInPlace(state) {
    for (const factionId of ['red', 'blue']) {
        const faction = state.factions[factionId];
        for (const [nodeKey, slots] of Object.entries(faction.productionQueues)) {
            const nodeId = nodeKey;
            if (!slots)
                continue;
            const invalid = state.map.nodes[nodeId].ownerFactionId !== factionId
                || nodeOccupyingFactions(state, nodeId).some((occupier) => occupier !== factionId);
            if (!invalid)
                continue;
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
                    message: `${state.map.nodes[nodeId].displayName}失稳，取消 ${count} 个订单；金币不退，释放 ${released} 预留人口。`,
                });
            }
        }
    }
}
function settleIncomeInPlace(state) {
    for (const factionId of ['red', 'blue']) {
        const baseIncome = stableNodeIds(state, factionId)
            .filter((nodeId) => isNodeActive(state, nodeId))
            .reduce((sum, nodeId) => sum + state.map.nodes[nodeId].goldIncome, 0);
        const multiplier = factionId === 'blue' ? DIFFICULTY_GOLD_MULTIPLIER[state.difficulty] : 1;
        const income = Math.floor(baseIncome * multiplier);
        state.factions[factionId].gold += income;
        addGameEvent(state, {
            type: 'income', factionId, amount: income,
            message: `${state.factions[factionId].displayName}结算 ${income}G（基础 ${baseIncome}G，倍率 ${multiplier.toFixed(2)}）。`,
        });
    }
}
function hasWaitingUnit(state, factionId) {
    return Object.values(state.factions[factionId].productionQueues).some((slots) => (slots?.some((slot) => slot.orders.some((order) => order.status === 'waiting_deployment')) ?? false));
}
function hasValidQueue(state, factionId) {
    return stableProductionNodeIds(state, factionId).some((nodeId) => (state.factions[factionId].productionQueues[nodeId]?.some((slot) => slot.orders.length > 0) ?? false));
}
export function isFactionEliminated(state, factionId) {
    const hasPieces = Object.values(state.pieces).some((piece) => piece.factionId === factionId && piece.hp > 0);
    const hasProduction = stableProductionNodeIds(state, factionId).length > 0;
    return !hasPieces && !hasWaitingUnit(state, factionId) && !hasValidQueue(state, factionId) && !hasProduction;
}
function roundLimitScore(state, factionId) {
    const stableProduction = stableProductionNodeIds(state, factionId).length;
    const strategicValue = stableNodeIds(state, factionId)
        .reduce((sum, nodeId) => sum + state.map.nodes[nodeId].strategicValue, 0);
    const armyValue = Object.values(state.pieces)
        .filter((piece) => piece.factionId === factionId)
        .reduce((sum, piece) => sum + piece.productionGoldValue, 0);
    return [stableProduction, strategicValue, armyValue, state.factions[factionId].gold];
}
function compareScore(a, b) {
    for (let i = 0; i < a.length; i += 1) {
        const av = a[i] ?? 0;
        const bv = b[i] ?? 0;
        if (av !== bv)
            return av - bv;
    }
    return 0;
}
function setGameOverInPlace(state, result) {
    state.result = result;
    state.phase = 'GAME_OVER';
    state.activeFactionId = null;
    addGameEvent(state, {
        type: 'game_over',
        factionId: result.winner === 'draw' ? undefined : result.winner,
        message: result.winner === 'draw'
            ? `战略回合 ${result.decidedAtRound} 结束，双方平局。`
            : `${state.factions[result.winner].displayName}获胜（${result.reason === 'elimination' ? '彻底消灭' : '回合上限判定'}）。`,
    });
}
function checkVictoryInPlace(state) {
    const redEliminated = isFactionEliminated(state, 'red');
    const blueEliminated = isFactionEliminated(state, 'blue');
    if (redEliminated || blueEliminated) {
        const winner = redEliminated && blueEliminated ? 'draw' : redEliminated ? 'blue' : 'red';
        setGameOverInPlace(state, { winner, reason: 'elimination', decidedAtRound: state.strategicRound });
        return true;
    }
    if (state.strategicRound >= MAX_STRATEGIC_ROUNDS) {
        const red = roundLimitScore(state, 'red');
        const blue = roundLimitScore(state, 'blue');
        const comparison = compareScore(red, blue);
        setGameOverInPlace(state, {
            winner: comparison > 0 ? 'red' : comparison < 0 ? 'blue' : 'draw',
            reason: 'round_limit',
            decidedAtRound: state.strategicRound,
            score: { red, blue },
        });
        return true;
    }
    return false;
}
export function runSettlementAutoInPlace(state) {
    const snapshot = makeSettlementSnapshot(state);
    settleCasualtyXpInPlace(state);
    recoverPiecesInPlace(state);
    captureNodesInPlace(state, snapshot);
    cancelInvalidProductionInPlace(state);
    settleIncomeInPlace(state);
    if (checkVictoryInPlace(state))
        return;
    state.phase = 'SETTLEMENT_PLANNING';
    state.activeFactionId = null;
    state.factions.red.planningCommitted = false;
    state.factions.blue.planningCommitted = false;
}
export function finishPlanningAndAdvanceInPlace(state) {
    syncAllPieceStatsInPlace(state);
    for (const factionId of ['red', 'blue']) {
        for (const card of Object.values(state.factions[factionId].cards))
            card.promotedThisSettlement = false;
    }
    state.strategicRound += 1;
    startStrategicRoundInPlace(state);
}
//# sourceMappingURL=lifecycle.js.map