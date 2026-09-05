import assert from 'node:assert/strict';
import test from 'node:test';
import { requireNode } from '../src/core/access.js';
import { createGame } from '../src/core/state.js';
import { piecesAtNode } from '../src/core/selectors.js';
import { getCardDefinition } from '../src/data/cards.js';
import {
  buildActionPreviews,
  projectBattleUnitPresentation,
  projectNodes,
  stateProjectionDigest,
} from '../src/app/presenter.js';
import { makeUnit } from './helpers.js';

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
  assert.equal(previews.every((preview) => preview.reasonCode === 'selection_empty'), true);
});

test('PHASE-A-PRESENTER player avatar settlement does not inherit its strategic surrogate card', () => {
  const surrogate = makeUnit('player-avatar-piece', 'red', 83, {
    displayName: '我方主角',
    encounterProjectionKind: 'player_avatar',
  });
  const avatar = projectBattleUnitPresentation(surrogate);
  assert.deepEqual(avatar, {
    displayName: '我方主角',
    roleLabel: '主角指挥官',
    portraitKind: 'player_avatar',
    portraitIdentifier: null,
  });
  assert.notEqual(avatar.displayName, getCardDefinition(83).displayName);

  const catalog = projectBattleUnitPresentation(makeUnit('elite-sniper', 'red', 83));
  assert.equal(catalog.displayName, '精锐狙击兵');
  assert.equal(catalog.portraitKind, 'catalog');
  assert.equal(catalog.portraitIdentifier, getCardDefinition(83).identifier);
});

test('PHASE-A-PRESENTER capacity-limited movement exposes the exact ordered X/Y subset', () => {
  const state = createGame({ seed: 'phase-a-capacity-preview' });
  const selected = piecesAtNode(state, 'R-HQ', 'red').slice(0, 2).map((piece) => piece.pieceId);
  assert.equal(selected.length, 2);
  const target = requireNode(state, 'R-Supply');
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
