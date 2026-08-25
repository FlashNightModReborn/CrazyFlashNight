import assert from 'node:assert/strict';
import test from 'node:test';
import { resolveBattle } from '../src/battle/resolver.js';
import { applyCommand } from '../src/core/engine.js';
import { runSettlementAutoInPlace } from '../src/core/lifecycle.js';
import { createPieceInPlace } from '../src/core/pieces.js';
import { hasStableSupplyPath, isNodeStable, piecesAtNode } from '../src/core/selectors.js';
import { createGame } from '../src/core/state.js';
import type { CardId, GameCommand, GameState, NodeId } from '../src/core/types.js';
import { validateCommand } from '../src/core/validator.js';
import { CARD_IDS, getCardDefinition } from '../src/data/cards.js';
import { NODE_CONFIGS } from '../src/data/map.js';
import { applyOk, makeState, makeUnit, moveCommand, recursivelySwapFactions, setPlanning } from './helpers.js';

test('AC-01 相同种子、状态和命令序列逐字段确定', () => {
  const a = createGame({ seed: 'ac-01', preset: 'all-units' });
  const b = createGame({ seed: 'ac-01', preset: 'all-units' });
  const ids = piecesAtNode(a, 'R-Supply', 'red').slice(0, 2).map((piece) => piece.pieceId);
  const commands: GameCommand[] = [
    moveCommand(a, ids, 'R-Supply', 'North-Choke'),
    { type: 'END_ACTION', factionId: 'red' },
  ];
  let left = a;
  let right = b;
  for (const command of commands) {
    left = applyOk(left, command);
    right = applyOk(right, command);
  }
  assert.deepEqual(left, right);
});

test('AC-02 红蓝阵营交换不会改变同侧战斗结果', () => {
  const input = {
    battleId: 'mirror', seed: 'mirror-seed', strategicRound: 1, commandSequence: 1,
    nodeId: 'Center-Command', nodeDefenseBonus: 0, attackerOriginNodeId: 'R-Supply',
    attackerUnits: [makeUnit('a1', 'red', 14), makeUnit('a2', 'red', 12)],
    defenderUnits: [makeUnit('d1', 'blue', 15), makeUnit('d2', 'blue', 13)],
  };
  const original = resolveBattle(input);
  const swapped = resolveBattle({
    ...input,
    attackerUnits: input.attackerUnits.map((unit) => ({ ...unit, factionId: 'blue' as const })),
    defenderUnits: input.defenderUnits.map((unit) => ({ ...unit, factionId: 'red' as const })),
  });
  assert.deepEqual(original, recursivelySwapFactions(swapped));
});

test('AC-03 八张卡的 cardId、unitTypeId、identifier、pieceId 语义唯一', () => {
  assert.equal(CARD_IDS.length, 8);
  const definitions = CARD_IDS.map(getCardDefinition);
  assert.equal(new Set(definitions.map((card) => card.cardId)).size, 8);
  assert.equal(new Set(definitions.map((card) => card.unitTypeId)).size, 8);
  assert.equal(new Set(definitions.map((card) => card.identifier)).size, 8);
  const state = makeState('ac-03', 'all-units');
  assert.equal(new Set(Object.keys(state.pieces)).size, Object.keys(state.pieces).length);
  assert.ok(Object.values(state.pieces).every((piece) => getCardDefinition(piece.cardId).cardId === piece.cardId));
});

test('AC-04 普通重装兵是带 elite 的 T2 越级产物', () => {
  const heavy = getCardDefinition(15);
  assert.equal(heavy.powerTier, 'T2 精锐级');
  assert.ok(heavy.tags.includes('elite'));
  assert.equal(heavy.productionCost, 60);
  assert.equal(heavy.populationCost, 2);
  assert.equal(heavy.buildRounds, 2);
  assert.equal(heavy.deploymentLevel, 10);
});

test('AC-05 精锐重装兵是带 boss 的 T3 终局产物', () => {
  const boss = getCardDefinition(85);
  assert.equal(boss.powerTier, 'T3 Boss级');
  assert.ok(boss.tags.includes('elite'));
  assert.ok(boss.tags.includes('boss'));
  assert.equal(boss.productionCost, 180);
  assert.equal(boss.populationCost, 5);
  assert.equal(boss.buildRounds, 4);
  assert.equal(boss.deploymentLevel, 25);
});

test('AC-06 标准开局六个己方节点激活稳定，人口 11、AP 4 且存在首次占领路径', () => {
  let state = makeState('ac-06');
  const initialNodes: Array<[NodeId, 'red' | 'blue']> = [
    ['R-HQ', 'red'], ['R-Supply', 'red'], ['R-Economy', 'red'],
    ['B-HQ', 'blue'], ['B-Supply', 'blue'], ['B-Economy', 'blue'],
  ];
  for (const [nodeId, factionId] of initialNodes) {
    assert.equal(state.map.nodes[nodeId].activeFromRound, 1);
    assert.ok(isNodeStable(state, nodeId, factionId));
  }
  assert.equal(state.factions.red.populationCap, 11);
  assert.equal(state.factions.blue.populationCap, 11);
  assert.equal(state.factions.red.actionPoints, 4);
  assert.equal(state.factions.blue.actionPoints, 4);
  const pieceId = piecesAtNode(state, 'R-HQ', 'red')[0]?.pieceId;
  assert.ok(pieceId);
  state = applyOk(state, moveCommand(state, [pieceId], 'R-HQ', 'R-Supply'));
  const captureMove = validateCommand(state, moveCommand(state, [pieceId], 'R-Supply', 'North-Choke'));
  assert.ok(captureMove.ok);
  assert.ok(hasStableSupplyPath(state, 'red', 'R-Supply'));
});

test('AC-07 状态与地图只有金币；南部军需稳定激活时提供 6G', () => {
  const state = makeState('ac-07');
  const serialized = JSON.stringify(state);
  assert.ok(!serialized.includes('"mana"'));
  assert.ok(!serialized.includes('"energy"'));
  assert.ok(!serialized.includes('"kPoint"'));
  assert.equal(NODE_CONFIGS['South-Depot'].goldIncome, 6);
  assert.equal(NODE_CONFIGS['South-Depot'].population, 0);
  assert.equal(NODE_CONFIGS['South-Depot'].productionSlots, 0);

  for (const node of Object.values(state.map.nodes)) {
    if (node.nodeId !== 'South-Depot') {
      node.ownerFactionId = null;
      node.activeFromRound = null;
    }
  }
  state.map.nodes['South-Depot'].ownerFactionId = 'red';
  state.map.nodes['South-Depot'].activeFromRound = 1;
  state.factions.red.gold = 0;
  // Keep both sides non-eliminated so settlement reaches income normally.
  createPieceInPlace(state, 'red', 14, 'South-Depot', 1, { pieceId: 'income-red' });
  createPieceInPlace(state, 'blue', 14, 'B-HQ', 1, { pieceId: 'income-blue' });
  const before = state.factions.red.gold;
  // Directly invoke through the public lifecycle to isolate income semantics.
  runSettlementAutoInPlace(state);
  assert.equal(state.factions.red.gold - before, 6);
});

test('AC-08 新部署棋子当轮不贡献 AP，但可以消耗既有公共 AP', () => {
  let state = makeState('ac-08');
  setPlanning(state);
  state.factions.red.gold = 100;
  state = applyOk(state, { type: 'ENQUEUE_PRODUCTION', factionId: 'red', nodeId: 'R-HQ', slotId: 'R-HQ:1', cardId: 14 });
  state = applyOk(state, { type: 'COMMIT_PLANNING', factionId: 'red' });
  state = applyOk(state, { type: 'COMMIT_PLANNING', factionId: 'blue' });
  assert.equal(state.strategicRound, 2);
  const deployed = piecesAtNode(state, 'R-HQ', 'red').find((piece) => piece.createdRound === 2);
  assert.ok(deployed);
  assert.equal(deployed.commandReadyFromRound, 3);
  assert.equal(state.factions.red.apGeneratedThisRound, 4);
  // Round 2 is blue-first; after blue ends, the freshly deployed red piece can spend the frozen pool.
  state = applyOk(state, { type: 'END_ACTION', factionId: 'blue' });
  const validation = validateCommand(state, moveCommand(state, [deployed.pieceId], 'R-HQ', 'R-Supply'));
  assert.ok(validation.ok);
  state = applyOk(state, moveCommand(state, [deployed.pieceId], 'R-HQ', 'R-Supply'));
  assert.equal(state.pieces[deployed.pieceId]?.nodeId, 'R-Supply');
  assert.equal(state.factions.red.actionPoints, 3);
});
