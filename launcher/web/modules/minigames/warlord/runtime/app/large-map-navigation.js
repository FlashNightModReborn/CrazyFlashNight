export const ABSOLUTE_MAXIMUM_RENDERED_NODES = 32;
function nonEmptyText(value, label) {
    const normalized = value.trim();
    if (normalized.length === 0)
        throw new Error(label + ' must not be empty.');
    return normalized;
}
function boundedPositiveInteger(value, label, hardMaximum) {
    if (!Number.isInteger(value) || value <= 0) {
        throw new Error(label + ' must be a positive integer.');
    }
    return Math.min(value, hardMaximum);
}
function nonNegativeInteger(value, label) {
    if (!Number.isInteger(value) || value < 0) {
        throw new Error(label + ' must be a non-negative integer.');
    }
    return value;
}
function normalizeSearchText(value) {
    return value.normalize('NFKC').trim().toLocaleLowerCase('zh-CN');
}
export function buildLargeMapSectorIndex(sectors, expectedNodeIds = []) {
    const sectorIds = [];
    const seenSectors = new Set();
    const sectorByNodeId = Object.create(null);
    const nodeIdsBySectorId = Object.create(null);
    for (const sector of sectors) {
        const sectorId = nonEmptyText(sector.id, 'sector.id');
        nonEmptyText(sector.displayName, 'sector.displayName');
        if (seenSectors.has(sectorId))
            throw new Error('Duplicate large-map sector ' + sectorId + '.');
        seenSectors.add(sectorId);
        sectorIds.push(sectorId);
        const nodeIds = [];
        for (const rawNodeId of sector.nodeIds) {
            const nodeId = nonEmptyText(rawNodeId, 'sector.nodeIds[]');
            if (sectorByNodeId[nodeId] !== undefined) {
                throw new Error('Large-map node ' + nodeId + ' belongs to more than one sector.');
            }
            sectorByNodeId[nodeId] = sectorId;
            nodeIds.push(nodeId);
        }
        nodeIdsBySectorId[sectorId] = Object.freeze(nodeIds);
    }
    if (expectedNodeIds.length > 0) {
        const expected = new Set();
        for (const rawNodeId of expectedNodeIds) {
            const nodeId = nonEmptyText(rawNodeId, 'expectedNodeIds[]');
            if (expected.has(nodeId))
                throw new Error('Duplicate expected large-map node ' + nodeId + '.');
            expected.add(nodeId);
            if (sectorByNodeId[nodeId] === undefined) {
                throw new Error('Large-map node ' + nodeId + ' has no sector.');
            }
        }
        for (const nodeId of Object.keys(sectorByNodeId)) {
            if (!expected.has(nodeId))
                throw new Error('Sector catalog references unknown node ' + nodeId + '.');
        }
    }
    return Object.freeze({
        sectorIds: Object.freeze(sectorIds),
        sectorByNodeId: Object.freeze(sectorByNodeId),
        nodeIdsBySectorId: Object.freeze(nodeIdsBySectorId),
    });
}
export function searchLargeMapNodes(nodes, sectors, query, maximumResults = 20) {
    const limit = boundedPositiveInteger(maximumResults, 'maximumResults', 64);
    const normalizedQuery = normalizeSearchText(query);
    if (normalizedQuery.length === 0) {
        return Object.freeze({ query: '', matches: Object.freeze([]), totalMatches: 0, truncated: false });
    }
    const sectorNames = new Map();
    for (const sector of sectors) {
        if (sectorNames.has(sector.id))
            throw new Error('Duplicate large-map sector ' + sector.id + '.');
        sectorNames.set(sector.id, nonEmptyText(sector.displayName, 'sector.displayName'));
    }
    const ranked = [];
    const seenNodes = new Set();
    for (const [authoredIndex, node] of nodes.entries()) {
        if (seenNodes.has(node.nodeId))
            throw new Error('Duplicate searchable large-map node ' + node.nodeId + '.');
        seenNodes.add(node.nodeId);
        const sectorDisplayName = sectorNames.get(node.sectorId);
        if (!sectorDisplayName)
            throw new Error('Searchable node ' + node.nodeId + ' references unknown sector.');
        const fields = [
            ['nodeId', node.nodeId],
            ['displayName', node.displayName],
            ['kind', node.kind],
            ['sector', sectorDisplayName],
            ['ownerFactionId', node.ownerFactionId ?? ''],
            ['searchTerms', (node.searchTerms ?? []).join(' ')],
        ];
        const matchedFields = fields
            .filter((field) => normalizeSearchText(field[1]).includes(normalizedQuery))
            .map((field) => field[0]);
        if (matchedFields.length === 0)
            continue;
        const normalizedId = normalizeSearchText(node.nodeId);
        const normalizedName = normalizeSearchText(node.displayName);
        const score = normalizedId === normalizedQuery || normalizedName === normalizedQuery
            ? 0
            : normalizedId.startsWith(normalizedQuery) || normalizedName.startsWith(normalizedQuery)
                ? 1
                : 2;
        ranked.push({
            authoredIndex,
            score,
            match: Object.freeze({
                nodeId: node.nodeId,
                displayName: node.displayName,
                sectorId: node.sectorId,
                sectorDisplayName,
                ownerFactionId: node.ownerFactionId ?? null,
                matchedFields: Object.freeze(matchedFields),
            }),
        });
    }
    ranked.sort((left, right) => left.score - right.score || left.authoredIndex - right.authoredIndex);
    const matches = ranked.slice(0, limit).map((entry) => entry.match);
    return Object.freeze({
        query: normalizedQuery,
        matches: Object.freeze(matches),
        totalMatches: ranked.length,
        truncated: ranked.length > matches.length,
    });
}
function alertForSignal(signal, category) {
    const shared = {
        id: category + ':' + signal.nodeId,
        category,
        nodeId: signal.nodeId,
        sectorId: signal.sectorId,
    };
    switch (category) {
        case 'command-post-threatened':
            return Object.freeze({
                ...shared,
                priority: 0,
                title: '指挥所受到威胁',
                detail: signal.nodeDisplayName + '可能失守。',
                nextStep: '定位据点并调派可用部队增援。',
            });
        case 'encounter-pending':
            return Object.freeze({
                ...shared,
                priority: 1,
                title: '交战等待处理',
                detail: signal.nodeDisplayName + '有待处理的交战。',
                nextStep: '定位据点并处理交战结果。',
            });
        case 'production-blocked':
            return Object.freeze({
                ...shared,
                priority: 2,
                title: '生产受阻',
                detail: signal.nodeDisplayName + '：' + (signal.productionBlockedReason ?? '原因未提供'),
                nextStep: '查看生产队列并解除阻断条件。',
            });
        case 'current-action':
            return Object.freeze({
                ...shared,
                priority: 3,
                title: '行动进行中',
                detail: signal.nodeDisplayName + '：' + (signal.currentAction ?? '行动状态未提供'),
                nextStep: '定位据点查看当前行动。',
            });
    }
}
export function deriveLargeMapAlerts(signals, maximumAlerts = 12) {
    const limit = boundedPositiveInteger(maximumAlerts, 'maximumAlerts', 32);
    const candidates = [];
    const seen = new Set();
    for (const signal of signals) {
        nonEmptyText(signal.nodeId, 'signal.nodeId');
        nonEmptyText(signal.nodeDisplayName, 'signal.nodeDisplayName');
        nonEmptyText(signal.sectorId, 'signal.sectorId');
        const categories = [];
        if (signal.commandPostThreatened)
            categories.push('command-post-threatened');
        if (signal.encounterPending)
            categories.push('encounter-pending');
        if (signal.productionBlockedReason)
            categories.push('production-blocked');
        if (signal.currentAction)
            categories.push('current-action');
        for (const category of categories) {
            const key = category + ':' + signal.nodeId;
            if (seen.has(key))
                continue;
            seen.add(key);
            candidates.push(alertForSignal(signal, category));
        }
    }
    candidates.sort((left, right) => (left.priority - right.priority
        || left.sectorId.localeCompare(right.sectorId)
        || left.nodeId.localeCompare(right.nodeId)
        || left.category.localeCompare(right.category)));
    const alerts = candidates.slice(0, limit);
    return Object.freeze({
        alerts: Object.freeze(alerts),
        totalAlerts: candidates.length,
        truncated: candidates.length > alerts.length,
    });
}
export function buildVirtualNodeWindow(input) {
    const requestedStart = nonNegativeInteger(input.requestedStart, 'requestedStart');
    const viewportSize = boundedPositiveInteger(input.viewportSize, 'viewportSize', ABSOLUTE_MAXIMUM_RENDERED_NODES);
    const overscan = nonNegativeInteger(input.overscan ?? 2, 'overscan');
    const maximumRendered = boundedPositiveInteger(input.maximumRendered ?? ABSOLUTE_MAXIMUM_RENDERED_NODES, 'maximumRendered', ABSOLUTE_MAXIMUM_RENDERED_NODES);
    const capacity = Math.max(1, Math.min(maximumRendered, ABSOLUTE_MAXIMUM_RENDERED_NODES));
    const totalNodes = input.nodeIds.length;
    const anchor = Math.min(requestedStart, totalNodes);
    const desiredViewport = Math.min(viewportSize, capacity);
    const before = Math.min(overscan, Math.max(0, capacity - desiredViewport));
    let start = Math.max(0, anchor - before);
    let endExclusive = Math.min(totalNodes, start + capacity);
    if (endExclusive - start < capacity)
        start = Math.max(0, endExclusive - capacity);
    if (anchor + desiredViewport > endExclusive) {
        endExclusive = Math.min(totalNodes, anchor + desiredViewport);
        start = Math.max(0, endExclusive - capacity);
    }
    const nodeIds = input.nodeIds.slice(start, endExclusive);
    return Object.freeze({
        start,
        endExclusive,
        nodeIds: Object.freeze(nodeIds),
        totalNodes,
        hasBefore: start > 0,
        hasAfter: endExclusive < totalNodes,
        renderedCount: nodeIds.length,
    });
}
//# sourceMappingURL=large-map-navigation.js.map