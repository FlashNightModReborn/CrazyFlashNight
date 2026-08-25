import { getCardDefinition } from '../data/cards.js';
import { getRuntimeStats } from './math.js';
export function createPieceInPlace(state, factionId, cardId, nodeId, commandReadyFromRound, options = {}) {
    const cardState = state.factions[factionId].cards[cardId];
    const definition = getCardDefinition(cardId);
    const stats = getRuntimeStats(cardId, cardState);
    const pieceId = options.pieceId ?? `${factionId[0]}-${cardId}-${state.nextPieceOrdinal + 1}`;
    state.nextPieceOrdinal += 1;
    const piece = {
        pieceId,
        factionId,
        cardId,
        nodeId,
        hp: Math.max(1, Math.round(stats.maxHp * (options.hpRatio ?? 1))),
        maxHp: stats.maxHp,
        commandReadyFromRound,
        failedAssaultLocks: [],
        createdRound: state.strategicRound,
        productionGoldValue: definition.productionCost,
        movesThisRound: 0,
        battlesThisRound: 0,
        maxDistanceInRound: 0,
    };
    state.pieces[pieceId] = piece;
    state.map.nodes[nodeId].pieceIds.push(pieceId);
    state.map.nodes[nodeId].pieceIds.sort();
    state.factions[factionId].populationUsed += definition.populationCost;
    return piece;
}
export function removePieceInPlace(state, pieceId) {
    const piece = state.pieces[pieceId];
    if (!piece)
        return;
    const definition = getCardDefinition(piece.cardId);
    state.map.nodes[piece.nodeId].pieceIds = state.map.nodes[piece.nodeId].pieceIds.filter((id) => id !== pieceId);
    state.factions[piece.factionId].populationUsed = Math.max(0, state.factions[piece.factionId].populationUsed - definition.populationCost);
    state.factions[piece.factionId].cards[piece.cardId].lostCount += 1;
    delete state.pieces[pieceId];
}
export function movePieceInPlace(state, pieceId, targetNodeId) {
    const piece = state.pieces[pieceId];
    if (!piece)
        return;
    state.map.nodes[piece.nodeId].pieceIds = state.map.nodes[piece.nodeId].pieceIds.filter((id) => id !== pieceId);
    piece.nodeId = targetNodeId;
    piece.movesThisRound += 1;
    piece.maxDistanceInRound = Math.max(piece.maxDistanceInRound, piece.movesThisRound);
    state.map.nodes[targetNodeId].pieceIds.push(pieceId);
    state.map.nodes[targetNodeId].pieceIds.sort();
}
export function syncAllPieceStatsInPlace(state) {
    for (const piece of Object.values(state.pieces)) {
        const oldMax = Math.max(1, piece.maxHp);
        const ratio = piece.hp / oldMax;
        const cardState = state.factions[piece.factionId].cards[piece.cardId];
        const stats = getRuntimeStats(piece.cardId, cardState);
        piece.maxHp = stats.maxHp;
        piece.hp = Math.max(1, Math.round(stats.maxHp * ratio));
    }
}
//# sourceMappingURL=pieces.js.map