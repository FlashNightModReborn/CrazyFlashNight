import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildNodeNavigatorWindow,
  contextualNodeIds,
  nodePageIndexFor,
} from '../src/app/node-navigator.js';

function syntheticGrid(size: number): {
  nodeIds: string[];
  edges: Array<{ a: string; b: string }>;
} {
  const nodeIds = Array.from({ length: size * size }, (_, index) => `node-${index}`);
  const edges: Array<{ a: string; b: string }> = [];
  for (let row = 0; row < size; row += 1) {
    for (let column = 0; column < size; column += 1) {
      const index = row * size + column;
      if (column + 1 < size) edges.push({ a: nodeIds[index]!, b: nodeIds[index + 1]! });
      if (row + 1 < size) edges.push({ a: nodeIds[index]!, b: nodeIds[index + size]! });
    }
  }
  return { nodeIds, edges };
}

test('PHASE-A-NAVIGATOR context ribbon stays bounded around the selected node', () => {
  const grid = syntheticGrid(10);
  const context = contextualNodeIds(grid.nodeIds, grid.edges, 'node-55', 6);
  assert.equal(context[0], 'node-55');
  assert.equal(context.length, 6);
  assert.equal(new Set(context).size, context.length);
  assert.ok(context.includes('node-54'));
  assert.ok(context.includes('node-45'));
});

test('PHASE-A-NAVIGATOR a 100-node index renders one six-node page at a time', () => {
  const grid = syntheticGrid(10);
  const first = buildNodeNavigatorWindow({
    ...grid,
    selectedNodeId: 'node-55',
    mode: 'all',
    requestedPage: 0,
  });
  const last = buildNodeNavigatorWindow({
    ...grid,
    selectedNodeId: 'node-55',
    mode: 'all',
    requestedPage: 99,
  });
  assert.equal(first.pageCount, 17);
  assert.deepEqual(first.nodeIds, ['node-0', 'node-1', 'node-2', 'node-3', 'node-4', 'node-5']);
  assert.equal(last.pageIndex, 16);
  assert.deepEqual(last.nodeIds, ['node-96', 'node-97', 'node-98', 'node-99']);
  assert.equal(nodePageIndexFor(grid.nodeIds, 'node-99'), 16);
});
