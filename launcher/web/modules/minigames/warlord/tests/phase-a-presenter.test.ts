import assert from 'node:assert/strict';
import test from 'node:test';
import { createGame } from '../src/core/state.js';
import { piecesAtNode } from '../src/core/selectors.js';
import { buildActionPreviews, projectNodes, stateProjectionDigest } from '../src/app/presenter.js';

test('PHASE-A-PRESENTER nine-node sandtable projection is read-only and identity complete', () => {
  const state = createGame({ seed: 'phase-a-presenter' });
  const before = structuredClone(state);
  const nodes = projectNodes(state);
  const digest = stateProjectionDigest(state);
  assert.equal(nodes.length, 9);
  assert.equal(new Set(nodes.map((node) => node.nodeId)).size, 9);
  assert.match(digest, /R-HQ/);
  assert.deepEqual(state, before);
});

test('PHASE-A-PRESENTER legal route and AP preview delegates to the canonical validator', () => {
  const state = createGame({ seed: 'phase-a-route' });
  const piece = piecesAtNode(state, 'R-HQ', 'red')[0];
  assert.ok(piece);
  const before = structuredClone(state);
  const previews = buildActionPreviews(state, 'R-HQ', [piece.pieceId]);
  assert.deepEqual(previews.map((preview) => preview.targetNodeId), ['R-Economy', 'R-Supply']);
  assert.equal(previews.every((preview) => preview.ok), true);
  assert.equal(previews.every((preview) => preview.apCost === 1), true);
  assert.deepEqual(state, before);
});

test('PHASE-A-PRESENTER empty selection remains a visible rejected command preview', () => {
  const state = createGame({ seed: 'phase-a-empty-route' });
  const previews = buildActionPreviews(state, 'R-HQ', []);
  assert.equal(previews.length, 2);
  assert.equal(previews.every((preview) => !preview.ok), true);
  assert.equal(previews.every((preview) => preview.error === '至少选择一枚棋子。'), true);
});

test('PHASE-A-PRESENTER capacity-limited movement exposes the exact ordered X/Y subset', () => {
  const state = createGame({ seed: 'phase-a-capacity-preview' });
  const selected = piecesAtNode(state, 'R-HQ', 'red').slice(0, 2).map((piece) => piece.pieceId);
  assert.equal(selected.length, 2);
  const target = state.map.nodes['R-Supply'];
  target.capacity = target.pieceIds.length + 1;
  const before = structuredClone(state);
  const preview = buildActionPreviews(state, 'R-HQ', selected)
    .find((candidate) => candidate.targetNodeId === 'R-Supply');
  assert.ok(preview);
  assert.equal(preview.ok, true);
  assert.deepEqual(preview.actualPieceIds, [selected[0]]);
  assert.equal(preview.apCost, 1);
  assert.deepEqual(state, before);
});
