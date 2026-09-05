import assert from 'node:assert/strict';
import test from 'node:test';
import { requireNode } from '../src/core/access.js';
import { applyCommand } from '../src/core/engine.js';
import {
  captureEncircledNodesAtTurnStartInPlace,
  captureOccupiedNodesAtActionEndInPlace,
  finishPlanningAndAdvanceInPlace,
} from '../src/core/lifecycle.js';
import { createPieceInPlace } from '../src/core/pieces.js';
import type { FactionId, GameEvent, GameState, NodeId } from '../src/core/types.js';
import { clearAllPieces, faction, makeState, moveCommand, setAction } from './helpers.js';

function setOwner(state: GameState, nodeId: NodeId, ownerFactionId: FactionId | null): void {
  const node = requireNode(state, nodeId);
  node.ownerFactionId = ownerFactionId;
  node.activeFromRound = ownerFactionId === null ? null : 1;
}

function captureEvents(state: GameState, nodeId?: NodeId): GameEvent[] {
  return state.eventLog.filter((event) => (
    event.type === 'node_captured'
    && (nodeId === undefined || event.nodeId === nodeId)
  ));
}

test('驻点直占与下一阵营包围占领按边界依次发生，敌军驻守不阻止包围也不删除单位', () => {
  let state = makeState('capture-boundary-order');
  clearAllPieces(state);
  for (const nodeId of Object.keys(state.map.nodes) as NodeId[]) setOwner(state, nodeId, 'blue');
  setOwner(state, 'Center-Command', null);
  const redPiece = createPieceInPlace(state, 'red', 14, 'Center-Command', 1, { pieceId: 'surrounded-red' });
  setAction(state, 'red');

  const ended = applyCommand(state, { type: 'END_ACTION', factionId: 'red' });
  assert.ok(ended.ok);
  state = ended.state;

  assert.equal(state.activeFactionId, 'blue');
  assert.equal(requireNode(state, 'Center-Command').ownerFactionId, 'blue');
  assert.equal(state.pieces[redPiece.pieceId]?.nodeId, 'Center-Command');
  assert.deepEqual(
    captureEvents(state, 'Center-Command').map((event) => [event.factionId, event.captureCause]),
    [
      ['red', 'direct_end_turn'],
      ['blue', 'encirclement_turn_start'],
    ],
  );
});

test('进攻胜利只移动幸存者；总部控制权与胜负延迟到行动结束驻点占领', () => {
  let state = makeState('capture-hq-boundary');
  clearAllPieces(state);
  faction(state, 'red').cards[15].level = 50;
  const attacker = createPieceInPlace(state, 'red', 15, 'B-Supply', 1, { pieceId: 'hq-attacker' });
  const defender = createPieceInPlace(state, 'blue', 14, 'B-HQ', 1, { pieceId: 'hq-defender' });
  defender.hp = 1;
  setAction(state, 'red', 10);

  const attacked = applyCommand(state, moveCommand(state, [attacker.pieceId], 'B-Supply', 'B-HQ'));
  assert.ok(attacked.ok);
  state = attacked.state;
  assert.equal(state.pieces[attacker.pieceId]?.nodeId, 'B-HQ');
  assert.equal(requireNode(state, 'B-HQ').ownerFactionId, 'blue');
  assert.equal(faction(state, 'blue').defeatedAtRound, null);
  assert.equal(state.result, null);
  assert.equal(captureEvents(state, 'B-HQ').length, 0);

  const ended = applyCommand(state, { type: 'END_ACTION', factionId: 'red' });
  assert.ok(ended.ok);
  state = ended.state;
  assert.equal(requireNode(state, 'B-HQ').ownerFactionId, 'red');
  assert.equal(faction(state, 'blue').defeatReason, 'command_post_captured');
  assert.equal(state.result?.reasonCode, 'CommandPostCaptured');
  assert.equal(captureEvents(state, 'B-HQ')[0]?.captureCause, 'direct_end_turn');
});

test('包围要求 degree > 0 且全部邻点严格同属待行动阵营，联盟颜色不合并', () => {
  const state = makeState('capture-strict-owner');
  clearAllPieces(state);
  for (const nodeId of Object.keys(state.map.nodes) as NodeId[]) setOwner(state, nodeId, 'red');
  setOwner(state, 'Center-Command', null);
  setOwner(state, 'B-Economy', 'blue');
  const redRelations = state.relations.red;
  const blueRelations = state.relations.blue;
  assert.ok(redRelations && blueRelations);
  redRelations.blue = 'allied';
  blueRelations.red = 'allied';

  const isolatedNodeId: NodeId = 'Isolated';
  state.map.nodes[isolatedNodeId] = {
    ...structuredClone(requireNode(state, 'South-Depot')),
    nodeId: isolatedNodeId,
    displayName: '孤立节点',
    ownerFactionId: null,
    activeFromRound: null,
    pieceIds: [],
  };

  captureEncircledNodesAtTurnStartInPlace(state, 'red');
  assert.equal(requireNode(state, 'Center-Command').ownerFactionId, null);
  assert.equal(requireNode(state, isolatedNodeId).ownerFactionId, null);
  assert.equal(captureEvents(state, 'Center-Command').length, 0);
  assert.equal(captureEvents(state, isolatedNodeId).length, 0);
});

test('包围批次先原子改色再统一处理总部，早先总部胜负不会截断同批后续节点', () => {
  const state = makeState('capture-atomic-hq');
  clearAllPieces(state);
  for (const nodeId of Object.keys(state.map.nodes) as NodeId[]) setOwner(state, nodeId, 'red');
  setOwner(state, 'B-HQ', 'blue');
  setOwner(state, 'South-Depot', null);

  captureEncircledNodesAtTurnStartInPlace(state, 'red');

  assert.equal(requireNode(state, 'B-HQ').ownerFactionId, 'red');
  assert.equal(requireNode(state, 'South-Depot').ownerFactionId, 'red');
  assert.equal(state.result?.reasonCode, 'CommandPostCaptured');
  const hqCaptureIndex = state.eventLog.findIndex((event) => event.type === 'node_captured' && event.nodeId === 'B-HQ');
  const depotCaptureIndex = state.eventLog.findIndex((event) => event.type === 'node_captured' && event.nodeId === 'South-Depot');
  const defeatIndex = state.eventLog.findIndex((event) => event.type === 'faction_defeated' && event.factionId === 'blue');
  assert.ok(hqCaptureIndex >= 0 && depotCaptureIndex > hqCaptureIndex && defeatIndex > depotCaptureIndex);
  assert.ok(captureEvents(state).every((event) => event.captureCause === 'encirclement_turn_start'));
});

test('有双方驻军的争夺节点不执行行动末直占', () => {
  const state = makeState('capture-contested');
  clearAllPieces(state);
  setOwner(state, 'South-Depot', 'blue');
  createPieceInPlace(state, 'red', 14, 'South-Depot', 1, { pieceId: 'contested-red' });
  createPieceInPlace(state, 'blue', 14, 'South-Depot', 1, { pieceId: 'contested-blue' });

  captureOccupiedNodesAtActionEndInPlace(state, 'red');

  assert.equal(requireNode(state, 'South-Depot').ownerFactionId, 'blue');
  assert.equal(captureEvents(state, 'South-Depot').length, 0);
});

test('统一结算后首行动阵营也在获得行动权前执行包围判定', () => {
  const state = makeState('capture-next-round-first');
  clearAllPieces(state);
  for (const nodeId of Object.keys(state.map.nodes) as NodeId[]) setOwner(state, nodeId, 'red');
  setOwner(state, 'Center-Command', null);

  finishPlanningAndAdvanceInPlace(state);

  assert.equal(state.strategicRound, 2);
  assert.equal(state.activeFactionId, 'red');
  assert.equal(requireNode(state, 'Center-Command').ownerFactionId, 'red');
  assert.equal(captureEvents(state, 'Center-Command')[0]?.captureCause, 'encirclement_turn_start');
});
