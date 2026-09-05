import { getCardDefinition } from '../data/cards.js';
import { requireNode } from './access.js';
import { getRuntimeStats } from './math.js';
import { registerOrganizationMemberInPlace, removeOrganizationMemberInPlace, syncCommandElementLocationsInPlace, } from './organization.js';
import { syncCommanderNodeInPlace } from './commanders.js';
import { requireFaction } from './factions.js';
export function createPieceInPlace(state, factionId, cardId, nodeId, commandReadyFromRound, options = {}) {
    const faction = requireFaction(state, factionId);
    const cardState = faction.cards[cardId];
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
    registerOrganizationMemberInPlace(state, piece);
    const node = requireNode(state, nodeId);
    node.pieceIds.push(pieceId);
    node.pieceIds.sort();
    faction.populationUsed += definition.populationCost;
    return piece;
}
export function removePieceInPlace(state, pieceId) {
    const piece = state.pieces[pieceId];
    if (!piece)
        return;
    const definition = getCardDefinition(piece.cardId);
    const node = requireNode(state, piece.nodeId);
    node.pieceIds = node.pieceIds.filter((id) => id !== pieceId);
    const faction = requireFaction(state, piece.factionId);
    faction.populationUsed = Math.max(0, faction.populationUsed - definition.populationCost);
    faction.cards[piece.cardId].lostCount += 1;
    removeOrganizationMemberInPlace(state, pieceId);
    delete state.pieces[pieceId];
}
function moveMemberWithoutOrganizationSync(state, pieceId, targetNodeId) {
    const piece = state.pieces[pieceId];
    if (!piece)
        return;
    const originNode = requireNode(state, piece.nodeId);
    originNode.pieceIds = originNode.pieceIds.filter((id) => id !== pieceId);
    piece.nodeId = targetNodeId;
    syncCommanderNodeInPlace(state, pieceId, targetNodeId);
    piece.movesThisRound += 1;
    piece.maxDistanceInRound = Math.max(piece.maxDistanceInRound, piece.movesThisRound);
    const targetNode = requireNode(state, targetNodeId);
    targetNode.pieceIds.push(pieceId);
    targetNode.pieceIds.sort();
}
export function movePieceInPlace(state, pieceId, targetNodeId) {
    moveMemberWithoutOrganizationSync(state, pieceId, targetNodeId);
    syncCommandElementLocationsInPlace(state, [pieceId]);
}
export function movePiecesInPlace(state, pieceIds, targetNodeId) {
    for (const pieceId of pieceIds)
        moveMemberWithoutOrganizationSync(state, pieceId, targetNodeId);
    syncCommandElementLocationsInPlace(state, pieceIds);
}
export function syncAllPieceStatsInPlace(state) {
    for (const piece of Object.values(state.pieces)) {
        const oldMax = Math.max(1, piece.maxHp);
        const ratio = piece.hp / oldMax;
        const cardState = requireFaction(state, piece.factionId).cards[piece.cardId];
        const stats = getRuntimeStats(piece.cardId, cardState);
        piece.maxHp = stats.maxHp;
        piece.hp = Math.max(1, Math.round(stats.maxHp * ratio));
    }
}
//# sourceMappingURL=pieces.js.map