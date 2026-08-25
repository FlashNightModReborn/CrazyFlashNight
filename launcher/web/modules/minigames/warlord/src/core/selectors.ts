import { adjacentNodeIds } from '../data/map.js';
import type { FactionId, GameState, NodeId, PieceState } from './types.js';

export function otherFaction(factionId: FactionId): FactionId {
  return factionId === 'red' ? 'blue' : 'red';
}

export function nodeOccupyingFactions(state: GameState, nodeId: NodeId): FactionId[] {
  const factions = new Set<FactionId>();
  for (const pieceId of state.map.nodes[nodeId].pieceIds) {
    const piece = state.pieces[pieceId];
    if (piece && piece.hp > 0) factions.add(piece.factionId);
  }
  return [...factions].sort();
}

export function nodeOccupiedByEnemy(state: GameState, nodeId: NodeId, factionId: FactionId): boolean {
  return nodeOccupyingFactions(state, nodeId).some((occupier) => occupier !== factionId);
}

export function isNodeActive(state: GameState, nodeId: NodeId): boolean {
  const node = state.map.nodes[nodeId];
  return node.ownerFactionId !== null
    && node.activeFromRound !== null
    && state.strategicRound >= node.activeFromRound;
}

export function isNodeStable(state: GameState, nodeId: NodeId, factionId: FactionId): boolean {
  const node = state.map.nodes[nodeId];
  return node.ownerFactionId === factionId
    && isNodeActive(state, nodeId)
    && !nodeOccupiedByEnemy(state, nodeId, factionId);
}

export function isProductionNode(state: GameState, nodeId: NodeId): boolean {
  return state.map.nodes[nodeId].productionSlots > 0;
}

export function stableNodeIds(state: GameState, factionId: FactionId): NodeId[] {
  return (Object.keys(state.map.nodes) as NodeId[])
    .filter((nodeId) => isNodeStable(state, nodeId, factionId))
    .sort();
}

export function stableProductionNodeIds(state: GameState, factionId: FactionId): NodeId[] {
  return stableNodeIds(state, factionId).filter((nodeId) => isProductionNode(state, nodeId));
}

export function hasStableSupplyPath(
  state: GameState,
  factionId: FactionId,
  fromNodeId: NodeId,
  stableOverride?: Set<NodeId>,
): boolean {
  const stable = stableOverride ?? new Set(stableNodeIds(state, factionId));
  if (!stable.has(fromNodeId)) return false;
  const productionTargets = new Set(
    [...stable].filter((nodeId) => state.map.nodes[nodeId].productionSlots > 0),
  );
  if (productionTargets.has(fromNodeId)) return true;

  const queue: NodeId[] = [fromNodeId];
  const visited = new Set<NodeId>(queue);
  while (queue.length > 0) {
    const current = queue.shift();
    if (!current) break;
    for (const next of adjacentNodeIds(current)) {
      if (!stable.has(next) || visited.has(next)) continue;
      if (productionTargets.has(next)) return true;
      visited.add(next);
      queue.push(next);
    }
  }
  return false;
}

export function piecesAtNode(state: GameState, nodeId: NodeId, factionId?: FactionId): PieceState[] {
  return state.map.nodes[nodeId].pieceIds
    .map((pieceId) => state.pieces[pieceId])
    .filter((piece): piece is PieceState => Boolean(piece && piece.hp > 0))
    .filter((piece) => factionId === undefined || piece.factionId === factionId)
    .sort((a, b) => a.pieceId.localeCompare(b.pieceId));
}

export function countNodePieces(state: GameState, nodeId: NodeId): number {
  return piecesAtNode(state, nodeId).length;
}

export function factionPieceIds(state: GameState, factionId: FactionId): string[] {
  return Object.values(state.pieces)
    .filter((piece) => piece.factionId === factionId && piece.hp > 0)
    .map((piece) => piece.pieceId)
    .sort();
}

export function nodeIsAdjacent(a: NodeId, b: NodeId): boolean {
  return adjacentNodeIds(a).includes(b);
}
