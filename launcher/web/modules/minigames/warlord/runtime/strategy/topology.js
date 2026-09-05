export function buildMapIndexes(definition) {
    const nodeById = Object.create(null);
    const edgeById = Object.create(null);
    const mutableAdjacency = Object.create(null);
    for (const node of definition.nodes) {
        nodeById[node.id] = node;
        mutableAdjacency[node.id] = [];
    }
    for (const edge of definition.edges) {
        const aEntries = mutableAdjacency[edge.a];
        const bEntries = mutableAdjacency[edge.b];
        if (aEntries === undefined || bEntries === undefined) {
            throw new Error(`Map edge ${edge.id} references a node missing from the validated definition.`);
        }
        edgeById[edge.id] = edge;
        aEntries.push(Object.freeze({ nodeId: edge.b, edgeId: edge.id }));
        bEntries.push(Object.freeze({ nodeId: edge.a, edgeId: edge.id }));
    }
    const adjacencyByNode = Object.create(null);
    for (const node of definition.nodes) {
        adjacencyByNode[node.id] = Object.freeze([...(mutableAdjacency[node.id] ?? [])]);
    }
    return Object.freeze({
        nodeById: Object.freeze(nodeById),
        edgeById: Object.freeze(edgeById),
        adjacencyByNode: Object.freeze(adjacencyByNode),
    });
}
function connectedComponents(definition, indexes) {
    const visited = new Set();
    const components = [];
    for (const startNode of definition.nodes) {
        if (visited.has(startNode.id))
            continue;
        const component = [];
        const queue = [startNode.id];
        visited.add(startNode.id);
        for (let cursor = 0; cursor < queue.length; cursor += 1) {
            const current = queue[cursor];
            if (current === undefined)
                continue;
            component.push(current);
            for (const entry of indexes.adjacencyByNode[current] ?? []) {
                if (visited.has(entry.nodeId))
                    continue;
                visited.add(entry.nodeId);
                queue.push(entry.nodeId);
            }
        }
        components.push(Object.freeze(component));
    }
    return Object.freeze(components);
}
function graphDiameter(definition, indexes) {
    let diameter = 0;
    for (const startNode of definition.nodes) {
        const distances = new Map([[startNode.id, 0]]);
        const queue = [startNode.id];
        for (let cursor = 0; cursor < queue.length; cursor += 1) {
            const current = queue[cursor];
            if (current === undefined)
                continue;
            const currentDistance = distances.get(current);
            if (currentDistance === undefined)
                continue;
            diameter = Math.max(diameter, currentDistance);
            for (const entry of indexes.adjacencyByNode[current] ?? []) {
                if (distances.has(entry.nodeId))
                    continue;
                distances.set(entry.nodeId, currentDistance + 1);
                queue.push(entry.nodeId);
            }
        }
    }
    return diameter;
}
function articulationNodes(definition, indexes) {
    let clock = 0;
    const discovery = new Map();
    const low = new Map();
    const parent = new Map();
    const articulation = new Set();
    const visit = (nodeId) => {
        clock += 1;
        discovery.set(nodeId, clock);
        low.set(nodeId, clock);
        let childCount = 0;
        for (const entry of indexes.adjacencyByNode[nodeId] ?? []) {
            const neighbor = entry.nodeId;
            if (!discovery.has(neighbor)) {
                childCount += 1;
                parent.set(neighbor, nodeId);
                visit(neighbor);
                const neighborLow = low.get(neighbor);
                const nodeLow = low.get(nodeId);
                if (neighborLow === undefined || nodeLow === undefined)
                    continue;
                low.set(nodeId, Math.min(nodeLow, neighborLow));
                const nodeParent = parent.get(nodeId) ?? null;
                const nodeDiscovery = discovery.get(nodeId);
                if (nodeParent === null && childCount > 1)
                    articulation.add(nodeId);
                if (nodeParent !== null && nodeDiscovery !== undefined && neighborLow >= nodeDiscovery) {
                    articulation.add(nodeId);
                }
            }
            else if (neighbor !== (parent.get(nodeId) ?? null)) {
                const nodeLow = low.get(nodeId);
                const neighborDiscovery = discovery.get(neighbor);
                if (nodeLow !== undefined && neighborDiscovery !== undefined) {
                    low.set(nodeId, Math.min(nodeLow, neighborDiscovery));
                }
            }
        }
    };
    for (const node of definition.nodes) {
        if (discovery.has(node.id))
            continue;
        parent.set(node.id, null);
        visit(node.id);
    }
    return Object.freeze(definition.nodes
        .map((node) => node.id)
        .filter((nodeId) => articulation.has(nodeId)));
}
export function computeMapTopologyMetrics(definition, providedIndexes) {
    const indexes = providedIndexes ?? buildMapIndexes(definition);
    const components = connectedComponents(definition, indexes);
    const degreeByNode = Object.create(null);
    let degreeTotal = 0;
    let minimumDegree = definition.nodes.length === 0 ? 0 : Number.POSITIVE_INFINITY;
    let maximumDegree = 0;
    for (const node of definition.nodes) {
        const degree = indexes.adjacencyByNode[node.id]?.length ?? 0;
        degreeByNode[node.id] = degree;
        degreeTotal += degree;
        minimumDegree = Math.min(minimumDegree, degree);
        maximumDegree = Math.max(maximumDegree, degree);
    }
    const connected = definition.nodes.length > 0 && components.length === 1;
    return Object.freeze({
        nodeCount: definition.nodes.length,
        edgeCount: definition.edges.length,
        componentCount: components.length,
        components,
        degreeByNode: Object.freeze(degreeByNode),
        minimumDegree,
        maximumDegree,
        averageDegree: definition.nodes.length === 0 ? 0 : degreeTotal / definition.nodes.length,
        diameter: connected ? graphDiameter(definition, indexes) : null,
        articulationNodeIds: articulationNodes(definition, indexes),
    });
}
//# sourceMappingURL=topology.js.map