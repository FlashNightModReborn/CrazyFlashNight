export type NodeNavigatorMode = 'context' | 'all';

export interface NavigatorEdge<TNodeId extends string> {
  a: TNodeId;
  b: TNodeId;
}

export interface NodeNavigatorWindow<TNodeId extends string> {
  mode: NodeNavigatorMode;
  nodeIds: TNodeId[];
  pageIndex: number;
  pageCount: number;
  totalCount: number;
  hasPrevious: boolean;
  hasNext: boolean;
}

export const NODE_NAVIGATOR_PAGE_SIZE = 6;

function uniqueAuthoredOrder<TNodeId extends string>(nodeIds: readonly TNodeId[]): TNodeId[] {
  return Array.from(new Set(nodeIds));
}

export function nodePageIndexFor<TNodeId extends string>(
  nodeIds: readonly TNodeId[],
  nodeId: TNodeId,
  pageSize = NODE_NAVIGATOR_PAGE_SIZE,
): number {
  const safeSize = Math.max(1, Math.floor(pageSize));
  const index = uniqueAuthoredOrder(nodeIds).indexOf(nodeId);
  return index < 0 ? 0 : Math.floor(index / safeSize);
}

export function contextualNodeIds<TNodeId extends string>(
  nodeIds: readonly TNodeId[],
  edges: readonly NavigatorEdge<TNodeId>[],
  selectedNodeId: TNodeId,
  limit = NODE_NAVIGATOR_PAGE_SIZE,
): TNodeId[] {
  const authored = uniqueAuthoredOrder(nodeIds);
  const authoredIndex = new Map(authored.map((nodeId, index) => [nodeId, index]));
  const safeLimit = Math.max(1, Math.floor(limit));
  const start = authoredIndex.has(selectedNodeId) ? selectedNodeId : authored[0];
  if (!start) return [];

  const adjacent = new Map<TNodeId, TNodeId[]>();
  for (const edge of edges) {
    if (!authoredIndex.has(edge.a) || !authoredIndex.has(edge.b)) continue;
    adjacent.set(edge.a, [...(adjacent.get(edge.a) ?? []), edge.b]);
    adjacent.set(edge.b, [...(adjacent.get(edge.b) ?? []), edge.a]);
  }
  for (const neighbors of adjacent.values()) {
    neighbors.sort((a, b) => (authoredIndex.get(a) ?? 0) - (authoredIndex.get(b) ?? 0));
  }

  const result: TNodeId[] = [];
  const queued = new Set<TNodeId>([start]);
  const queue: TNodeId[] = [start];
  while (queue.length > 0 && result.length < safeLimit) {
    const current = queue.shift();
    if (!current) break;
    result.push(current);
    for (const neighbor of adjacent.get(current) ?? []) {
      if (queued.has(neighbor)) continue;
      queued.add(neighbor);
      queue.push(neighbor);
    }
  }
  return result;
}

export function buildNodeNavigatorWindow<TNodeId extends string>(options: {
  nodeIds: readonly TNodeId[];
  edges: readonly NavigatorEdge<TNodeId>[];
  selectedNodeId: TNodeId;
  mode: NodeNavigatorMode;
  requestedPage?: number;
  pageSize?: number;
}): NodeNavigatorWindow<TNodeId> {
  const authored = uniqueAuthoredOrder(options.nodeIds);
  const pageSize = Math.max(1, Math.floor(options.pageSize ?? NODE_NAVIGATOR_PAGE_SIZE));
  if (options.mode === 'context') {
    return {
      mode: 'context',
      nodeIds: contextualNodeIds(authored, options.edges, options.selectedNodeId, pageSize),
      pageIndex: 0,
      pageCount: 1,
      totalCount: authored.length,
      hasPrevious: false,
      hasNext: false,
    };
  }

  const pageCount = Math.max(1, Math.ceil(authored.length / pageSize));
  const pageIndex = Math.max(0, Math.min(pageCount - 1, Math.floor(options.requestedPage ?? 0)));
  return {
    mode: 'all',
    nodeIds: authored.slice(pageIndex * pageSize, (pageIndex + 1) * pageSize),
    pageIndex,
    pageCount,
    totalCount: authored.length,
    hasPrevious: pageIndex > 0,
    hasNext: pageIndex + 1 < pageCount,
  };
}
