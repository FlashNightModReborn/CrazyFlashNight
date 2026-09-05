import type {
  EdgeId,
  MapDefinition,
  MapEdgeDefinition,
  MapNodeDefinition,
  NodeId,
} from './definitions.js';

export interface MapAdjacencyEntry {
  readonly nodeId: NodeId;
  readonly edgeId: EdgeId;
}

export interface MapIndexes {
  readonly nodeById: Readonly<Record<string, MapNodeDefinition>>;
  readonly edgeById: Readonly<Record<string, MapEdgeDefinition>>;
  readonly adjacencyByNode: Readonly<Record<string, readonly MapAdjacencyEntry[]>>;
}

export interface MapTopologyMetrics {
  readonly nodeCount: number;
  readonly edgeCount: number;
  readonly componentCount: number;
  readonly components: readonly (readonly NodeId[])[];
  readonly degreeByNode: Readonly<Record<string, number>>;
  readonly minimumDegree: number;
  readonly maximumDegree: number;
  readonly averageDegree: number;
  readonly diameter: number | null;
  readonly articulationNodeIds: readonly NodeId[];
}

export function buildMapIndexes(definition: MapDefinition): MapIndexes {
  const nodeById: Record<string, MapNodeDefinition> = Object.create(null) as Record<string, MapNodeDefinition>;
  const edgeById: Record<string, MapEdgeDefinition> = Object.create(null) as Record<string, MapEdgeDefinition>;
  const mutableAdjacency: Record<string, MapAdjacencyEntry[]> = Object.create(null) as Record<string, MapAdjacencyEntry[]>;

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

  const adjacencyByNode: Record<string, readonly MapAdjacencyEntry[]> = Object.create(null) as Record<string, readonly MapAdjacencyEntry[]>;
  for (const node of definition.nodes) {
    adjacencyByNode[node.id] = Object.freeze([...(mutableAdjacency[node.id] ?? [])]);
  }
  return Object.freeze({
    nodeById: Object.freeze(nodeById),
    edgeById: Object.freeze(edgeById),
    adjacencyByNode: Object.freeze(adjacencyByNode),
  });
}

function connectedComponents(
  definition: MapDefinition,
  indexes: MapIndexes,
): readonly (readonly NodeId[])[] {
  const visited = new Set<NodeId>();
  const components: (readonly NodeId[])[] = [];
  for (const startNode of definition.nodes) {
    if (visited.has(startNode.id)) continue;
    const component: NodeId[] = [];
    const queue: NodeId[] = [startNode.id];
    visited.add(startNode.id);
    for (let cursor = 0; cursor < queue.length; cursor += 1) {
      const current = queue[cursor];
      if (current === undefined) continue;
      component.push(current);
      for (const entry of indexes.adjacencyByNode[current] ?? []) {
        if (visited.has(entry.nodeId)) continue;
        visited.add(entry.nodeId);
        queue.push(entry.nodeId);
      }
    }
    components.push(Object.freeze(component));
  }
  return Object.freeze(components);
}

function graphDiameter(definition: MapDefinition, indexes: MapIndexes): number {
  let diameter = 0;
  for (const startNode of definition.nodes) {
    const distances = new Map<NodeId, number>([[startNode.id, 0]]);
    const queue: NodeId[] = [startNode.id];
    for (let cursor = 0; cursor < queue.length; cursor += 1) {
      const current = queue[cursor];
      if (current === undefined) continue;
      const currentDistance = distances.get(current);
      if (currentDistance === undefined) continue;
      diameter = Math.max(diameter, currentDistance);
      for (const entry of indexes.adjacencyByNode[current] ?? []) {
        if (distances.has(entry.nodeId)) continue;
        distances.set(entry.nodeId, currentDistance + 1);
        queue.push(entry.nodeId);
      }
    }
  }
  return diameter;
}

function articulationNodes(definition: MapDefinition, indexes: MapIndexes): readonly NodeId[] {
  let clock = 0;
  const discovery = new Map<NodeId, number>();
  const low = new Map<NodeId, number>();
  const parent = new Map<NodeId, NodeId | null>();
  const articulation = new Set<NodeId>();

  const visit = (nodeId: NodeId): void => {
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
        if (neighborLow === undefined || nodeLow === undefined) continue;
        low.set(nodeId, Math.min(nodeLow, neighborLow));

        const nodeParent = parent.get(nodeId) ?? null;
        const nodeDiscovery = discovery.get(nodeId);
        if (nodeParent === null && childCount > 1) articulation.add(nodeId);
        if (nodeParent !== null && nodeDiscovery !== undefined && neighborLow >= nodeDiscovery) {
          articulation.add(nodeId);
        }
      } else if (neighbor !== (parent.get(nodeId) ?? null)) {
        const nodeLow = low.get(nodeId);
        const neighborDiscovery = discovery.get(neighbor);
        if (nodeLow !== undefined && neighborDiscovery !== undefined) {
          low.set(nodeId, Math.min(nodeLow, neighborDiscovery));
        }
      }
    }
  };

  for (const node of definition.nodes) {
    if (discovery.has(node.id)) continue;
    parent.set(node.id, null);
    visit(node.id);
  }
  return Object.freeze(definition.nodes
    .map((node) => node.id)
    .filter((nodeId) => articulation.has(nodeId)));
}

export function computeMapTopologyMetrics(
  definition: MapDefinition,
  providedIndexes?: MapIndexes,
): MapTopologyMetrics {
  const indexes = providedIndexes ?? buildMapIndexes(definition);
  const components = connectedComponents(definition, indexes);
  const degreeByNode: Record<string, number> = Object.create(null) as Record<string, number>;
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
