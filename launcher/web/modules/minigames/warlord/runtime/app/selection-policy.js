export function canonicalPieceIds(pieceIds) {
    return Array.from(new Set(pieceIds)).sort((a, b) => a.localeCompare(b));
}
function normalizedRect(rect) {
    return {
        left: Math.min(rect.startX, rect.endX),
        top: Math.min(rect.startY, rect.endY),
        right: Math.max(rect.startX, rect.endX),
        bottom: Math.max(rect.startY, rect.endY),
    };
}
export function selectMarqueeCandidates(candidates, rect, preferredNodeId) {
    const bounds = normalizedRect(rect);
    const inside = candidates.filter((candidate) => candidate.factionId === 'red'
        && Number.isFinite(candidate.screenX)
        && Number.isFinite(candidate.screenY)
        && candidate.screenX >= bounds.left
        && candidate.screenX <= bounds.right
        && candidate.screenY >= bounds.top
        && candidate.screenY <= bounds.bottom);
    const groups = new Map();
    for (const candidate of inside) {
        const group = groups.get(candidate.nodeId) ?? [];
        group.push(candidate.pieceId);
        groups.set(candidate.nodeId, group);
    }
    if (groups.size === 0)
        return { nodeId: null, pieceIds: [], ignoredCount: 0 };
    const chosenNodeId = preferredNodeId && groups.has(preferredNodeId)
        ? preferredNodeId
        : Array.from(groups.entries())
            .sort(([leftNodeId, left], [rightNodeId, right]) => right.length - left.length
            || leftNodeId.localeCompare(rightNodeId))[0][0];
    const pieceIds = canonicalPieceIds(groups.get(chosenNodeId) ?? []);
    return {
        nodeId: chosenNodeId,
        pieceIds,
        ignoredCount: Math.max(0, inside.length - pieceIds.length),
    };
}
export function followCommandSelection(state, commandedPieceIds, fallbackNodeId) {
    const groups = new Map();
    for (const pieceId of canonicalPieceIds(commandedPieceIds)) {
        const piece = state.pieces[pieceId];
        if (!piece || piece.factionId !== 'red' || piece.hp <= 0)
            continue;
        const group = groups.get(piece.nodeId) ?? [];
        group.push(pieceId);
        groups.set(piece.nodeId, group);
    }
    if (groups.size === 0)
        return { selectedNodeId: fallbackNodeId, pieceIds: [] };
    const [selectedNodeId, pieceIds] = Array.from(groups.entries())
        .sort(([leftNodeId, left], [rightNodeId, right]) => right.length - left.length
        || Number(rightNodeId === fallbackNodeId) - Number(leftNodeId === fallbackNodeId)
        || leftNodeId.localeCompare(rightNodeId))[0];
    return { selectedNodeId, pieceIds: canonicalPieceIds(pieceIds) };
}
//# sourceMappingURL=selection-policy.js.map