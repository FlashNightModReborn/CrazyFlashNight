import { addGameEvent } from './events.js';
export function factionIds(state) {
    return [...state.turnOrder];
}
export function requireFaction(state, factionId) {
    const faction = state.factions[factionId];
    if (!faction)
        throw new Error(`Unknown runtime faction ${factionId}.`);
    return faction;
}
export function createDefaultRelations(ids) {
    const matrix = Object.create(null);
    for (const left of ids) {
        const row = Object.create(null);
        for (const right of ids)
            row[right] = left === right ? 'allied' : 'hostile';
        matrix[left] = row;
    }
    return matrix;
}
export function createDefaultVictoryGroups(ids, displayNameByFaction) {
    return Object.fromEntries(ids.map((factionId) => [factionId, {
            victoryGroupId: factionId,
            displayName: displayNameByFaction[factionId] ?? factionId,
            factionIds: [factionId],
        }]));
}
export function relationBetween(state, left, right) {
    if (left === right)
        return 'allied';
    const relation = state.relations[left]?.[right];
    if (!relation || state.relations[right]?.[left] !== relation) {
        throw new Error(`Relation matrix is incomplete or asymmetric for ${left}/${right}.`);
    }
    return relation;
}
export function areHostile(state, left, right) {
    return relationBetween(state, left, right) === 'hostile';
}
export function areAllied(state, left, right) {
    return relationBetween(state, left, right) === 'allied';
}
export function isFactionDefeated(state, factionId) {
    return requireFaction(state, factionId).defeatedAtRound !== null;
}
export function activeFactionIds(state) {
    return factionIds(state).filter((factionId) => !isFactionDefeated(state, factionId));
}
export function refreshFactionActionPoints(faction) {
    faction.actionPoints = faction.apLedger.baseRemaining + faction.apLedger.fieldRemaining;
    faction.apGeneratedThisRound = faction.apLedger.baseGenerated + faction.apLedger.fieldGenerated;
    faction.apSpentThisRound = faction.apLedger.baseSpent + faction.apLedger.fieldSpent;
}
/** Field AP is deliberately consumed before the durable base pool. */
export function spendFactionActionPointsInPlace(faction, amount) {
    if (!Number.isInteger(amount) || amount < 0 || faction.actionPoints < amount) {
        throw new Error(`Invalid AP spend ${amount} for faction ${faction.factionId}.`);
    }
    const fieldSpend = Math.min(faction.apLedger.fieldRemaining, amount);
    faction.apLedger.fieldRemaining -= fieldSpend;
    faction.apLedger.fieldSpent += fieldSpend;
    const baseSpend = amount - fieldSpend;
    faction.apLedger.baseRemaining -= baseSpend;
    faction.apLedger.baseSpent += baseSpend;
    refreshFactionActionPoints(faction);
}
/** A commander leaving the field invalidates only unspent field AP immediately. */
export function clearUnspentFieldActionPointsInPlace(faction) {
    faction.apLedger.fieldRemaining = 0;
    refreshFactionActionPoints(faction);
}
export function defeatFactionInPlace(state, factionId, reason) {
    const faction = requireFaction(state, factionId);
    if (faction.defeatedAtRound !== null)
        return;
    faction.defeatedAtRound = state.strategicRound;
    faction.defeatReason = reason;
    faction.actionPoints = 0;
    faction.apLedger.baseRemaining = 0;
    faction.apLedger.fieldRemaining = 0;
    const removedPieceIds = Object.values(state.pieces)
        .filter((piece) => piece.factionId === factionId)
        .map((piece) => piece.pieceId)
        .sort();
    for (const pieceId of removedPieceIds) {
        const piece = state.pieces[pieceId];
        if (!piece)
            continue;
        const node = state.map.nodes[piece.nodeId];
        if (node)
            node.pieceIds = node.pieceIds.filter((candidate) => candidate !== pieceId);
        const elementId = state.organization.memberToElementId[pieceId];
        if (elementId) {
            const element = state.organization.commandElements[elementId];
            if (element) {
                element.memberIds = element.memberIds.filter((candidate) => candidate !== pieceId);
                if (element.memberIds.length === 0)
                    delete state.organization.commandElements[elementId];
            }
            delete state.organization.memberToElementId[pieceId];
        }
        delete state.pieces[pieceId];
    }
    let cancelledOrders = 0;
    for (const slots of Object.values(faction.productionQueues)) {
        if (!slots)
            continue;
        for (const slot of slots) {
            cancelledOrders += slot.orders.length;
            slot.orders = [];
        }
    }
    faction.populationReserved = 0;
    for (const node of Object.values(state.map.nodes)) {
        if (node.ownerFactionId !== factionId)
            continue;
        node.ownerFactionId = null;
        node.activeFromRound = null;
    }
    for (const commander of Object.values(state.commanders)) {
        if (commander.factionId !== factionId)
            continue;
        commander.pieceInstanceId = null;
        commander.nodeId = null;
        commander.status = commander.role === 'player_avatar' ? 'rear' : 'available';
    }
    addGameEvent(state, {
        type: 'faction_defeated',
        factionId,
        message: `${faction.displayName}的指挥体系已经瓦解。`,
        data: { reason },
    });
    addGameEvent(state, {
        type: 'surrender_cleanup',
        factionId,
        amount: removedPieceIds.length,
        message: `${faction.displayName}撤除 ${removedPieceIds.length} 支部队并取消 ${cancelledOrders} 个订单；不产生击杀、经验或战利品。`,
        data: { cancelledOrders, releasedNodes: true },
    });
}
export function nextActiveTurnIndex(state, afterIndex) {
    for (let index = afterIndex + 1; index < state.turnOrder.length; index += 1) {
        const factionId = state.turnOrder[index];
        if (factionId !== undefined && !isFactionDefeated(state, factionId))
            return index;
    }
    return null;
}
//# sourceMappingURL=factions.js.map