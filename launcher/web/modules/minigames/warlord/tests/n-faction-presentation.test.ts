import assert from 'node:assert/strict';
import test from 'node:test';

import { buildActionPreviews, projectNodes } from '../src/app/presenter.js';
import { createDefaultRelations } from '../src/core/factions.js';
import { movePiecesInPlace } from '../src/core/pieces.js';
import { adjacentNodeIds } from '../src/core/selectors.js';
import { createGame } from '../src/core/state.js';
import { DEMO_2_ALLIED_PACT_FACTIONS } from '../src/data/demo2.js';
import { DEMO_2_RUNTIME } from '../src/data/map.js';
import { runQuickBattle } from '../src/dev/quickBattle.js';
import { makeReplay, replayGame } from '../src/replay/replay.js';
import { factionVisualStyle } from '../src/scene/map-theme.js';

test('N-faction presentation keeps Demo 1 colours and gives Demo 2 four colour-independent identities', () => {
  assert.equal(factionVisualStyle('red').base, 0xa64331);
  assert.equal(factionVisualStyle('blue').base, 0x2f6f91);

  const demo2Ids = DEMO_2_RUNTIME.scenario.turnOrder;
  const styles = demo2Ids.map((factionId) => factionVisualStyle(factionId));
  assert.equal(new Set(styles.map((style) => style.base)).size, 4);
  assert.equal(new Set(styles.map((style) => style.markerIndex)).size, 4);
  assert.equal(new Set(styles.map((style) => style.shortMark)).size, 4);
  assert.deepEqual(factionVisualStyle('opaque-faction-7'), factionVisualStyle('opaque-faction-7'));
});

test('Demo 2 projections and command previews use the runtime player and opaque faction ids', () => {
  const relations = createDefaultRelations(DEMO_2_RUNTIME.scenario.turnOrder);
  const [pactA, pactB] = DEMO_2_ALLIED_PACT_FACTIONS;
  relations[pactA]![pactB] = 'allied';
  relations[pactB]![pactA] = 'allied';
  const state = createGame({
    seed: 'n-faction-presentation',
    runtimeBundle: DEMO_2_RUNTIME,
    relations,
  });
  const nodes = projectNodes(state);
  assert.equal(nodes.length, 80);
  assert.ok(nodes.every((node) => node.redCount === node.playerCount));
  assert.ok(nodes.every((node) => node.blueCount === node.hostileCount));

  const playerFaction = state.factions[state.playerFactionId];
  assert.ok(playerFaction);
  const playerHome = nodes.find((node) => node.nodeId === playerFaction.commandPostNodeId);
  assert.ok(playerHome);
  assert.match(playerHome.ownerLabel, /^我方/);
  assert.equal(playerHome.factionCounts[state.playerFactionId], playerHome.playerCount);

  const playerPiece = Object.values(state.pieces).find((piece) => piece.factionId === state.playerFactionId);
  assert.ok(playerPiece);
  const elementId = state.organization.memberToElementId[playerPiece.pieceId];
  assert.ok(elementId);
  const element = state.organization.commandElements[elementId];
  assert.ok(element);
  const previews = buildActionPreviews(state, playerPiece.nodeId, element.memberIds);
  assert.ok(previews.length > 0);
  assert.ok(previews.every((preview) => preview.reasonCode !== 'active_faction_mismatch'));
});

test('quick battle and replay no longer collapse Demo 2 to red versus blue or Demo 1', () => {
  const state = createGame({ seed: 'n-faction-quick-battle', runtimeBundle: DEMO_2_RUNTIME });
  const playerPiece = Object.values(state.pieces).find((piece) => piece.factionId === state.playerFactionId);
  const hostilePiece = Object.values(state.pieces).find((piece) => piece.factionId !== state.playerFactionId);
  assert.ok(playerPiece);
  assert.ok(hostilePiece);
  const targetNodeId = adjacentNodeIds(state, playerPiece.nodeId)[0];
  assert.ok(targetNodeId);
  movePiecesInPlace(state, [hostilePiece.pieceId], targetNodeId);

  const stats = runQuickBattle(state, playerPiece.nodeId, 4);
  assert.equal(stats.runs, 4);
  assert.equal(stats.attackerWins + stats.defenderWins, 4);

  const fresh = createGame({ seed: 'n-faction-replay', runtimeBundle: DEMO_2_RUNTIME });
  const replay = makeReplay(fresh);
  assert.equal(replay.scenarioId, DEMO_2_RUNTIME.scenario.id);
  assert.equal(replay.mapDefinitionId, DEMO_2_RUNTIME.mapDefinition.id);
  assert.deepEqual(replayGame(replay), fresh);
});
