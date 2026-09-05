import { requireNode } from './access.js';
export function adjacentNodeIds(state, nodeId) {
    return state.map.edges
        .flatMap((edge) => edge.a === nodeId ? [edge.b] : edge.b === nodeId ? [edge.a] : [])
        .sort();
}
export function nodeOccupyingFactions(state, nodeId) {
    const factions = new Set();
    for (const pieceId of requireNode(state, nodeId).pieceIds) {
        const piece = state.pieces[pieceId];
        if (piece && piece.hp > 0)
            factions.add(piece.factionId);
    }
    return [...factions].sort();
}
export function nodeOccupiedByEnemy(state, nodeId, factionId) {
    return nodeOccupyingFactions(state, nodeId).some((occupier) => occupier !== factionId);
}
export function isNodeActive(state, nodeId) {
    const node = requireNode(state, nodeId);
    return node.ownerFactionId !== null
        && node.activeFromRound !== null
        && state.strategicRound >= node.activeFromRound;
}
export function isNodeStable(state, nodeId, factionId) {
    const node = requireNode(state, nodeId);
    return node.ownerFactionId === factionId
        && isNodeActive(state, nodeId)
        && !nodeOccupiedByEnemy(state, nodeId, factionId);
}
export function isProductionNode(state, nodeId) {
    return requireNode(state, nodeId).productionSlots > 0;
}
export function stableNodeIds(state, factionId) {
    return Object.keys(state.map.nodes)
        .filter((nodeId) => isNodeStable(state, nodeId, factionId))
        .sort();
}
export function stableProductionNodeIds(state, factionId) {
    return stableNodeIds(state, factionId).filter((nodeId) => isProductionNode(state, nodeId));
}
export function hasStableSupplyPath(state, factionId, fromNodeId, stableOverride) {
    const stable = stableOverride ?? new Set(stableNodeIds(state, factionId));
    if (!stable.has(fromNodeId))
        return false;
    const productionTargets = new Set([...stable].filter((nodeId) => requireNode(state, nodeId).productionSlots > 0));
    if (productionTargets.has(fromNodeId))
        return true;
    const queue = [fromNodeId];
    const visited = new Set(queue);
    while (queue.length > 0) {
        const current = queue.shift();
        if (!current)
            break;
        for (const next of adjacentNodeIds(state, current)) {
            if (!stable.has(next) || visited.has(next))
                continue;
            if (productionTargets.has(next))
                return true;
            visited.add(next);
            queue.push(next);
        }
    }
    return false;
}
export function piecesAtNode(state, nodeId, factionId) {
    return requireNode(state, nodeId).pieceIds
        .map((pieceId) => state.pieces[pieceId])
        .filter((piece) => Boolean(piece && piece.hp > 0))
        .filter((piece) => factionId === undefined || piece.factionId === factionId)
        .sort((a, b) => a.pieceId.localeCompare(b.pieceId));
}
export function countNodePieces(state, nodeId) {
    return piecesAtNode(state, nodeId).length;
}
export function factionPieceIds(state, factionId) {
    return Object.values(state.pieces)
        .filter((piece) => piece.factionId === factionId && piece.hp > 0)
        .map((piece) => piece.pieceId)
        .sort();
}
export function nodeIsAdjacent(state, a, b) {
    return adjacentNodeIds(state, a).includes(b);
}
//# sourceMappingURL=selectors.js.map