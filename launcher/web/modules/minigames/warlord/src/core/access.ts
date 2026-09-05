import type { GameState, NodeId, NodeState } from './types.js';

/**
 * Dynamic MapDefinition IDs make missing references a runtime possibility.
 * Consumers must fail closed at the first bad reference instead of relying on a fixed union.
 */
export function requireNode(state: GameState, nodeId: NodeId): NodeState {
  const node = state.map.nodes[nodeId];
  if (!node) throw new Error(`Validated game state is missing node ${nodeId}.`);
  return node;
}
