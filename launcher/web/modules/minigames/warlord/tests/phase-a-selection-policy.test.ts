import assert from 'node:assert/strict';
import test from 'node:test';
import {
  canonicalPieceIds,
  followCommandSelection,
  selectMarqueeCandidates,
} from '../src/app/selection-policy.js';
import { makeState } from './helpers.js';

test('PHASE-A-SELECTION canonical ids are unique and command-order deterministic', () => {
  assert.deepEqual(canonicalPieceIds(['r-3', 'r-1', 'r-3', 'r-2']), ['r-1', 'r-2', 'r-3']);
});

test('PHASE-A-SELECTION marquee keeps one origin and prefers the existing origin when hit', () => {
  const selection = selectMarqueeCandidates([
    { pieceId: 'r-hq-2', nodeId: 'R-HQ', factionId: 'red', screenX: 30, screenY: 30 },
    { pieceId: 'r-hq-1', nodeId: 'R-HQ', factionId: 'red', screenX: 20, screenY: 20 },
    { pieceId: 'r-supply-1', nodeId: 'R-Supply', factionId: 'red', screenX: 40, screenY: 40 },
    { pieceId: 'r-supply-2', nodeId: 'R-Supply', factionId: 'red', screenX: 50, screenY: 50 },
    { pieceId: 'r-supply-3', nodeId: 'R-Supply', factionId: 'red', screenX: 60, screenY: 60 },
    { pieceId: 'b-1', nodeId: 'B-HQ', factionId: 'blue', screenX: 25, screenY: 25 },
  ], { startX: 10, startY: 10, endX: 70, endY: 70 }, 'R-HQ');
  assert.equal(selection.nodeId, 'R-HQ');
  assert.deepEqual(selection.pieceIds, ['r-hq-1', 'r-hq-2']);
  assert.equal(selection.ignoredCount, 3);
});

test('PHASE-A-SELECTION marquee chooses the largest origin with a stable lexical tie break', () => {
  const selection = selectMarqueeCandidates([
    { pieceId: 's-1', nodeId: 'R-Supply', factionId: 'red', screenX: 5, screenY: 5 },
    { pieceId: 'h-1', nodeId: 'R-HQ', factionId: 'red', screenX: 6, screenY: 6 },
    { pieceId: 'e-1', nodeId: 'R-Economy', factionId: 'red', screenX: 7, screenY: 7 },
  ], { startX: 0, startY: 0, endX: 10, endY: 10 });
  assert.equal(selection.nodeId, 'R-Economy');
  assert.deepEqual(selection.pieceIds, ['e-1']);
  assert.equal(selection.ignoredCount, 2);
});

test('PHASE-A-SELECTION follows only surviving pieces that actually received the command', () => {
  const state = makeState('selection-follow');
  const redPieces = Object.values(state.pieces)
    .filter((piece) => piece.factionId === 'red')
    .sort((a, b) => a.pieceId.localeCompare(b.pieceId));
  assert.ok(redPieces.length >= 3);
  redPieces[0]!.nodeId = 'R-Supply';
  redPieces[1]!.nodeId = 'R-Supply';
  delete state.pieces[redPieces[1]!.pieceId];
  redPieces[2]!.nodeId = 'R-HQ';

  const followed = followCommandSelection(
    state,
    [redPieces[2]!.pieceId, redPieces[1]!.pieceId, redPieces[0]!.pieceId],
    'R-Supply',
  );
  assert.equal(followed.selectedNodeId, 'R-Supply');
  assert.deepEqual(followed.pieceIds, [redPieces[0]!.pieceId]);
});
