import assert from 'node:assert/strict';
import test from 'node:test';
import {
  enumerateLocalMoveOrAttackCommands,
} from '../src/core/command-enumerator.js';
import { createGame } from '../src/core/state.js';
import type { FactionId, GameState, NodeId } from '../src/core/types.js';
import { DEMO_2_RUNTIME } from '../src/data/map.js';

function makeState(seed: string): GameState {
  return createGame({ seed, preset: 'standard', difficulty: 'normal' });
}

function setAction(state: GameState, factionId: FactionId, actionPoints: number): void {
  const faction = state.factions[factionId];
  if (!faction) throw new Error('Missing test faction ' + factionId + '.');
  state.phase = 'FIRST_FACTION_ACTION';
  state.initiativeFactionId = factionId;
  state.activeFactionId = factionId;
  faction.actionPoints = actionPoints;
  faction.apGeneratedThisRound = actionPoints;
}

function stateAdjacency(state: GameState): Map<NodeId, Set<NodeId>> {
  const adjacency = new Map<NodeId, Set<NodeId>>();
  for (const edge of state.map.edges) {
    const fromA = adjacency.get(edge.a) ?? new Set<NodeId>();
    const fromB = adjacency.get(edge.b) ?? new Set<NodeId>();
    fromA.add(edge.b);
    fromB.add(edge.a);
    adjacency.set(edge.a, fromA);
    adjacency.set(edge.b, fromB);
  }
  return adjacency;
}

test('local command enumerator is deterministic and returns only complete legal command elements', () => {
  const state = makeState('slice-6-local-command-enumerator');
  setAction(state, 'red', 99);
  const first = enumerateLocalMoveOrAttackCommands(state, 'red');
  const second = enumerateLocalMoveOrAttackCommands(state, 'red');
  assert.deepEqual(second, first);
  assert.equal(first.work.guardHit, false);
  assert.equal(first.work.validationErrors, 0);
  assert.equal(first.work.mapEdgesInspected, state.map.edges.length);
  assert.equal(first.work.candidatesBuilt, first.work.validations);
  assert.ok(first.work.candidatesBuilt > 0);
  assert.ok(first.legalCommands.length > 0);

  const adjacency = stateAdjacency(state);
  for (const entry of first.legalCommands) {
    const element = state.organization.commandElements[entry.commandElementId];
    if (!element) throw new Error('Missing enumerated command element ' + entry.commandElementId + '.');
    assert.equal(element.factionId, 'red');
    assert.equal(entry.command.originNodeId, element.nodeId);
    assert.deepEqual(entry.command.pieceIds, [...element.memberIds].sort((a, b) => a.localeCompare(b)));
    assert.equal(adjacency.get(entry.command.originNodeId)?.has(entry.command.targetNodeId), true);
  }
});

test('local command enumeration work scales with command elements and adjacent edges, not all nodes', () => {
  const state = makeState('slice-6-local-work-receipt');
  setAction(state, 'blue', 99);
  const result = enumerateLocalMoveOrAttackCommands(state, 'blue');
  const adjacency = stateAdjacency(state);
  const inspectedElements = Object.values(state.organization.commandElements)
    .filter((element) => element.factionId === 'blue');
  const localUpperBound = inspectedElements.reduce((sum, element) => (
    sum + (adjacency.get(element.nodeId)?.size ?? 0)
  ), 0);

  assert.equal(result.work.eligibleCommandElements, inspectedElements.length);
  assert.equal(result.work.localEdgesVisited, localUpperBound);
  assert.equal(result.work.candidatesBuilt, localUpperBound);
  assert.ok(result.work.candidatesBuilt < inspectedElements.length * Object.keys(state.map.nodes).length);
  assert.ok(result.work.distinctOrigins <= result.work.eligibleCommandElements);
});

test('local command enumeration stops deterministically at explicit workload guards', () => {
  const state = makeState('slice-6-local-budget-guard');
  setAction(state, 'red', 99);
  const budget = {
    maximumCommandElementsInspected: 256,
    maximumMapEdgesInspected: 512,
    maximumLocalEdgesVisited: 1_024,
    maximumCandidates: 2,
    maximumValidations: 2,
  } as const;
  const first = enumerateLocalMoveOrAttackCommands(state, 'red', budget);
  const second = enumerateLocalMoveOrAttackCommands(state, 'red', budget);
  assert.deepEqual(second, first);
  assert.equal(first.work.guardHit, true);
  assert.equal(first.work.guardReasons.includes('maximumCandidates'), true);
  assert.equal(first.work.candidatesBuilt, 2);
  assert.equal(first.work.validations, 2);
  assert.ok(first.legalCommands.length <= 2);

  const edgeGuard = enumerateLocalMoveOrAttackCommands(state, 'red', {
    maximumMapEdgesInspected: 1,
  });
  assert.equal(edgeGuard.work.mapEdgesInspected, 1);
  assert.equal(edgeGuard.work.guardReasons.includes('maximumMapEdgesInspected'), true);
  assert.throws(() => enumerateLocalMoveOrAttackCommands(state, 'red', {
    maximumCandidates: -1,
  }), /maximumCandidates/);
});

test('Demo 2 allied AI enumerates an atomic two-edge transit through the shared validator', () => {
  const state = createGame({ seed: 'slice-6-allied-transit', runtimeBundle: DEMO_2_RUNTIME });
  const factionId = 'boss-pact-a';
  const alliedFactionId = 'boss-pact-b';
  setAction(state, factionId, 99);
  const originNodeId = state.factions[factionId]?.commandPostNodeId;
  if (!originNodeId) throw new Error('Missing pact A command post.');
  const adjacency = stateAdjacency(state);
  const viaNodeId = [...(adjacency.get(originNodeId) ?? [])]
    .sort()
    .find((nodeId) => state.map.nodes[nodeId]!.pieceIds.length === 0);
  const targetNodeId = [...(adjacency.get(viaNodeId ?? '') ?? [])]
    .sort()
    .find((nodeId) => nodeId !== originNodeId && !(adjacency.get(originNodeId)?.has(nodeId)));
  if (!viaNodeId || !targetNodeId) throw new Error('Demo 2 home sector lacks an allied transit fixture path.');

  const commanderPieceIds = new Set(Object.values(state.commanders)
    .map((commander) => commander.pieceInstanceId)
    .filter((pieceId): pieceId is string => pieceId !== null));
  const alliedPiece = Object.values(state.pieces).find((piece) => (
    piece.factionId === alliedFactionId && !commanderPieceIds.has(piece.pieceId)
  ));
  if (!alliedPiece) throw new Error('Missing allied transit fixture piece.');
  const previousNodeId = alliedPiece.nodeId;
  state.map.nodes[previousNodeId]!.pieceIds = state.map.nodes[previousNodeId]!.pieceIds
    .filter((pieceId) => pieceId !== alliedPiece.pieceId);
  alliedPiece.nodeId = viaNodeId;
  state.map.nodes[viaNodeId]!.pieceIds.push(alliedPiece.pieceId);
  state.map.nodes[viaNodeId]!.ownerFactionId = alliedFactionId;
  const alliedElementId = state.organization.memberToElementId[alliedPiece.pieceId];
  if (!alliedElementId) throw new Error('Missing allied command element.');
  state.organization.commandElements[alliedElementId]!.nodeId = viaNodeId;

  const result = enumerateLocalMoveOrAttackCommands(state, factionId);
  const transit = result.legalCommands.find((entry) => (
    entry.command.originNodeId === originNodeId
    && entry.command.viaNodeId === viaNodeId
    && entry.command.targetNodeId === targetNodeId
  ));
  assert.ok(transit, 'AI did not enumerate the legal allied transit path.');
  assert.equal(transit?.validation.isBattle, false);
  assert.equal(transit?.validation.commandLoad, 2);
  assert.equal(result.work.validationErrors, 0);
  assert.equal(result.work.guardHit, false);
});
