import assert from 'node:assert/strict';
import test from 'node:test';
import { requireNode } from '../src/core/access.js';
import { applyCommand } from '../src/core/engine.js';
import {
  isFactionEliminated,
  progressProductionInPlace,
  runSettlementAutoInPlace,
  startStrategicRoundInPlace,
} from '../src/core/lifecycle.js';
import { createPieceInPlace, removePieceInPlace } from '../src/core/pieces.js';
import { hasStableSupplyPath, isNodeStable, piecesAtNode, stableProductionNodeIds } from '../src/core/selectors.js';
import type { GameState, ProductionOrder } from '../src/core/types.js';
import { validateCommand } from '../src/core/validator.js';
import { getCardDefinition } from '../src/data/cards.js';
import { applyOk, clearAllPieces, faction, makeState, moveCommand, setAction, setPlanning } from './helpers.js';

function makeGuaranteedTwoBattleState(seed: string): GameState {
  const state = makeState(seed);
  clearAllPieces(state);
  faction(state, 'red').cards[15].level = 50;
  const attacker = createPieceInPlace(state, 'red', 15, 'R-Supply', 1, { pieceId: 'red-veteran' });
  const first = createPieceInPlace(state, 'blue', 14, 'North-Choke', 1, { pieceId: 'blue-screen-1' });
  const second = createPieceInPlace(state, 'blue', 13, 'B-Supply', 1, { pieceId: 'blue-screen-2' });
  first.hp = 1;
  second.hp = 1;
  attacker.hp = attacker.maxHp;
  setAction(state, 'red', 10);
  return state;
}

test('AC-09 节点战斗在命令返回前写回，经验延迟，同一幸存者可继续参战', () => {
  let state: GameState | null = null;
  for (let index = 0; index < 64; index += 1) {
    const candidate = makeGuaranteedTwoBattleState(`ac-09-${index}`);
    const first = applyCommand(candidate, moveCommand(candidate, ['red-veteran'], 'R-Supply', 'North-Choke'));
    if (first.ok && first.state.pieces['red-veteran']?.nodeId === 'North-Choke' && first.state.casualtyLedger.length === 1) {
      state = first.state;
      break;
    }
  }
  assert.ok(state);
  assert.equal(state.battles.length, 1);
  assert.equal(state.pieces['blue-screen-1'], undefined);
  assert.equal(state.casualtyLedger[0]?.settled, false);
  assert.equal(faction(state, 'red').xpPool, 0);
  assert.equal(faction(state, 'blue').xpPool, 0);
  const hpAfterFirst = state.pieces['red-veteran']?.hp;
  assert.ok(hpAfterFirst && hpAfterFirst > 0);
  const second = applyCommand(state, moveCommand(state, ['red-veteran'], 'North-Choke', 'B-Supply'));
  assert.ok(second.ok);
  assert.equal(second.state.battles.length, 2);
  assert.equal(second.state.pieces['blue-screen-2'], undefined);
  assert.equal(second.state.pieces['red-veteran']?.nodeId, 'B-Supply');
});

test('AC-10 失败攻击者当战略回合不能重攻同一节点', () => {
  const state = makeState('ac-10');
  clearAllPieces(state);
  const red = createPieceInPlace(state, 'red', 15, 'R-Supply', 1, { pieceId: 'red-tank' });
  const blue = createPieceInPlace(state, 'blue', 15, 'North-Choke', 1, { pieceId: 'blue-tank' });
  red.hp = red.maxHp = 1_000_000_000;
  blue.hp = blue.maxHp = 1_000_000_000;
  setAction(state, 'red', 10);
  const first = applyCommand(state, moveCommand(state, [red.pieceId], 'R-Supply', 'North-Choke'));
  assert.ok(first.ok);
  assert.equal(first.state.battles[0]?.result.reason, 'battle_round_limit');
  assert.ok(first.state.pieces[red.pieceId]?.failedAssaultLocks.includes('North-Choke'));
  const retry = validateCommand(first.state, moveCommand(first.state, [red.pieceId], 'R-Supply', 'North-Choke'));
  assert.ok(!retry.ok);
  assert.match(retry.error ?? '', /不能立即重入/);
});

test('AC-11 容量按有序列表截断；超出进攻宽度整条命令非法', () => {
  let state = makeState('ac-11');
  const extra = createPieceInPlace(state, 'red', 14, 'R-HQ', 1, { pieceId: 'red-extra' });
  setAction(state, 'red', 10);
  const ids = [...piecesAtNode(state, 'R-HQ', 'red').map((piece) => piece.pieceId)];
  assert.equal(ids.length, 5);
  const expectedMoved = ids.slice(0, 4);
  state = applyOk(state, moveCommand(state, ids, 'R-HQ', 'R-Supply'));
  assert.deepEqual(piecesAtNode(state, 'R-Supply', 'red').map((piece) => piece.pieceId), [...expectedMoved].sort());
  assert.equal(state.pieces[ids[4] ?? extra.pieceId]?.nodeId, 'R-HQ');
  assert.equal(faction(state, 'red').actionPoints, 6);

  createPieceInPlace(state, 'blue', 14, 'North-Choke', 1, { pieceId: 'width-defender' });
  const threeAttackers = piecesAtNode(state, 'R-Supply', 'red').slice(0, 3).map((piece) => piece.pieceId);
  const tooWide = validateCommand(state, moveCommand(state, threeAttackers, 'R-Supply', 'North-Choke'));
  assert.ok(!tooWide.ok);
  assert.match(tooWide.error ?? '', /进攻宽度为 2/);
});

test('AC-12 经过但未在结算时停留的节点不会占领', () => {
  let state = makeState('ac-12');
  const pieceId = piecesAtNode(state, 'R-HQ', 'red')[0]?.pieceId;
  assert.ok(pieceId);
  state = applyOk(state, moveCommand(state, [pieceId], 'R-HQ', 'R-Economy'));
  state = applyOk(state, moveCommand(state, [pieceId], 'R-Economy', 'South-Depot'));
  assert.equal(requireNode(state, 'South-Depot').ownerFactionId, null);
  state = applyOk(state, moveCommand(state, [pieceId], 'South-Depot', 'R-Economy'));
  state = applyOk(state, { type: 'END_ACTION', factionId: 'red' });
  state = applyOk(state, { type: 'END_ACTION', factionId: 'blue' });
  assert.equal(requireNode(state, 'South-Depot').ownerFactionId, null);
});

test('AC-13 行动结束按驻点直接占领，不要求稳定或补给路径', () => {
  let state = makeState('ac-13');
  clearAllPieces(state);
  createPieceInPlace(state, 'red', 14, 'Center-Command', 1, { pieceId: 'capture-layer-1' });
  createPieceInPlace(state, 'red', 14, 'B-Supply', 1, { pieceId: 'capture-layer-2' });
  setAction(state, 'red');
  state = applyOk(state, { type: 'END_ACTION', factionId: 'red' });
  assert.equal(requireNode(state, 'Center-Command').ownerFactionId, 'red');
  assert.equal(requireNode(state, 'Center-Command').activeFromRound, 2);
  assert.equal(requireNode(state, 'B-Supply').ownerFactionId, 'red');
  assert.equal(requireNode(state, 'B-Supply').activeFromRound, 2);
});

test('AC-14 敌军占据仍属己方的节点会立即切断补给路径和生产锚点', () => {
  const state = makeState('ac-14');
  requireNode(state, 'Center-Command').ownerFactionId = 'red';
  requireNode(state, 'Center-Command').activeFromRound = 1;
  createPieceInPlace(state, 'blue', 14, 'Center-Command', 1, { pieceId: 'cut-center' });
  createPieceInPlace(state, 'red', 14, 'B-Supply', 1, { pieceId: 'behind-lines' });
  assert.ok(!isNodeStable(state, 'Center-Command', 'red'));
  assert.ok(!hasStableSupplyPath(state, 'red', 'Center-Command'));

  createPieceInPlace(state, 'blue', 14, 'R-Supply', 1, { pieceId: 'cut-anchor' });
  assert.ok(!stableProductionNodeIds(state, 'red').includes('R-Supply'));
  runSettlementAutoInPlace(state);
  assert.equal(requireNode(state, 'B-Supply').ownerFactionId, 'blue');
});

test('AC-15 行动末新夺节点未激活，只恢复三分之一差值且本轮不产出', () => {
  let state = makeState('ac-15');
  const piece = createPieceInPlace(state, 'red', 14, 'South-Depot', 1, { pieceId: 'depot-capturer' });
  piece.maxHp = 1000;
  piece.hp = 100;
  faction(state, 'red').gold = 0;
  state = applyOk(state, { type: 'END_ACTION', factionId: 'red' });
  state = applyOk(state, { type: 'END_ACTION', factionId: 'blue' });
  assert.equal(state.pieces[piece.pieceId]?.hp, 400);
  assert.equal(requireNode(state, 'South-Depot').ownerFactionId, 'red');
  assert.equal(requireNode(state, 'South-Depot').activeFromRound, 2);
  // Initial stable HQ + Economy yield 13G; the newly captured 6G depot must not pay this settlement.
  assert.equal(faction(state, 'red').gold, 13);
});

test('AC-16 失稳生产节点取消订单：金币不退，全部预留人口原子释放', () => {
  let state = makeState('ac-16');
  setPlanning(state);
  faction(state, 'red').gold = 100;
  state = applyOk(state, { type: 'ENQUEUE_PRODUCTION', factionId: 'red', nodeId: 'R-Supply', slotId: 'R-Supply:1', cardId: 14 });
  const goldAfterOrder = faction(state, 'red').gold;
  assert.equal(faction(state, 'red').populationReserved, 1);
  for (const node of Object.values(state.map.nodes)) node.goldIncome = 0;
  createPieceInPlace(state, 'blue', 14, 'R-Supply', 1, { pieceId: 'queue-raider' });
  state.phase = 'SECOND_FACTION_ACTION';
  state.activeFactionId = 'blue';
  runSettlementAutoInPlace(state);
  assert.equal(faction(state, 'red').gold, goldAfterOrder);
  assert.equal(faction(state, 'red').populationReserved, 0);
  assert.equal(faction(state, 'red').productionQueues['R-Supply']?.[0]?.orders.length, 0);
});

test('AC-17 ROUND_START 先重算人口；超限同时阻止新订单和等待部署', () => {
  const state = makeState('ac-17');
  // Initial 4 population + seven extra T1 = cap 11, while HQ still has one physical slot.
  for (let i = 0; i < 4; i += 1) createPieceInPlace(state, 'red', 14, 'R-Supply', 1, { pieceId: `pop-s-${i}` });
  for (let i = 0; i < 3; i += 1) createPieceInPlace(state, 'red', 14, 'R-Economy', 1, { pieceId: `pop-e-${i}` });
  assert.equal(faction(state, 'red').populationUsed, 11);
  const order: ProductionOrder = {
    orderId: 'waiting-pop', factionId: 'red', nodeId: 'R-HQ', slotId: 'R-HQ:1', cardId: 14,
    remainingRounds: 0, status: 'waiting_deployment', populationCost: 1, goldCost: 8, enqueuedRound: 1,
  };
  const slot = faction(state, 'red').productionQueues['R-HQ']?.[0];
  assert.ok(slot);
  slot.orders.push(order);
  faction(state, 'red').populationReserved = 1;
  faction(state, 'red').populationCap = 99;
  startStrategicRoundInPlace(state);
  assert.equal(faction(state, 'red').populationCap, 11);
  assert.equal(slot.orders[0]?.status, 'waiting_deployment');
  assert.equal(faction(state, 'red').populationReserved, 1);
  setPlanning(state);
  faction(state, 'red').gold = 100;
  const enqueue = validateCommand(state, { type: 'ENQUEUE_PRODUCTION', factionId: 'red', nodeId: 'R-HQ', slotId: 'R-HQ:2', cardId: 14 });
  assert.ok(!enqueue.ok);
  assert.match(enqueue.error ?? '', /人口容量不足/);
});

test('AC-18 阵亡立即减少 populationUsed，且结算恢复不会复活', () => {
  let state: GameState | null = null;
  for (let index = 0; index < 64; index += 1) {
    const candidate = makeGuaranteedTwoBattleState(`ac-18-${index}`);
    const before = faction(candidate, 'blue').populationUsed;
    const result = applyCommand(candidate, moveCommand(candidate, ['red-veteran'], 'R-Supply', 'North-Choke'));
    if (result.ok && result.state.pieces['blue-screen-1'] === undefined) {
      assert.equal(faction(result.state, 'blue').populationUsed, before - getCardDefinition(14).populationCost);
      state = result.state;
      break;
    }
  }
  assert.ok(state);
  runSettlementAutoInPlace(state);
  assert.equal(state.pieces['blue-screen-1'], undefined);
});

test('AC-19 待部署单位保留预留人口并堵塞生产槽，条件恢复后才部署', () => {
  const state = makeState('ac-19');
  const slot = faction(state, 'red').productionQueues['R-HQ']?.[0];
  assert.ok(slot);
  const head: ProductionOrder = {
    orderId: 'head', factionId: 'red', nodeId: 'R-HQ', slotId: slot.slotId, cardId: 14,
    remainingRounds: 0, status: 'waiting_deployment', populationCost: 1, goldCost: 8, enqueuedRound: 1,
  };
  const tail: ProductionOrder = {
    orderId: 'tail', factionId: 'red', nodeId: 'R-HQ', slotId: slot.slotId, cardId: 14,
    remainingRounds: 1, status: 'building', populationCost: 1, goldCost: 8, enqueuedRound: 1,
  };
  slot.orders.push(head, tail);
  faction(state, 'red').populationReserved = 2;
  // Fill the HQ's fifth slot so the waiting head cannot deploy.
  const blocker = createPieceInPlace(state, 'red', 14, 'R-HQ', 1, { pieceId: 'deployment-blocker' });
  progressProductionInPlace(state);
  assert.equal(slot.orders[0]?.orderId, 'head');
  assert.equal(slot.orders[1]?.remainingRounds, 1);
  assert.equal(faction(state, 'red').populationReserved, 2);
  removePieceInPlace(state, blocker.pieceId);
  progressProductionInPlace(state);
  assert.equal(slot.orders[0]?.orderId, 'tail');
  assert.equal(slot.orders[0]?.remainingRounds, 1);
  assert.equal(faction(state, 'red').populationReserved, 1);
});

test('AC-20 幸存 HP 被下一场节点战斗按精确值继承', () => {
  let state: GameState | null = null;
  for (let index = 0; index < 64; index += 1) {
    const candidate = makeGuaranteedTwoBattleState(`ac-20-${index}`);
    // Force visible persistent damage before the first battle.
    const veteran = candidate.pieces['red-veteran'];
    if (!veteran) continue;
    veteran.hp = Math.floor(veteran.maxHp * 0.6);
    const first = applyCommand(candidate, moveCommand(candidate, ['red-veteran'], 'R-Supply', 'North-Choke'));
    if (!first.ok || first.state.pieces['red-veteran']?.nodeId !== 'North-Choke') continue;
    const hpAfterFirst = first.state.pieces['red-veteran']?.hp;
    if (!hpAfterFirst) continue;
    const second = applyCommand(first.state, moveCommand(first.state, ['red-veteran'], 'North-Choke', 'B-Supply'));
    if (!second.ok || second.state.battles.length < 2) continue;
    assert.equal(second.state.battles[1]?.attackerSnapshots[0]?.hp, hpAfterFirst);
    state = second.state;
    break;
  }
  assert.ok(state);
});

test('AC-32 野战团灭但仍有稳定生产节点时对局不结束', () => {
  const state = makeState('ac-32');
  for (const piece of Object.values(state.pieces).filter((candidate) => candidate.factionId === 'red')) {
    removePieceInPlace(state, piece.pieceId);
  }
  assert.equal(Object.values(state.pieces).filter((piece) => piece.factionId === 'red').length, 0);
  assert.ok(!isFactionEliminated(state, 'red'));
  runSettlementAutoInPlace(state);
  assert.equal(state.result, null);
  assert.equal(state.phase, 'SETTLEMENT_PLANNING');
});

test('AC-34 只有部队、待部署、有效队列与稳定生产能力同时消失才彻底消灭', () => {
  const state = makeState('ac-34');
  for (const piece of Object.values(state.pieces).filter((candidate) => candidate.factionId === 'blue')) {
    removePieceInPlace(state, piece.pieceId);
  }
  assert.ok(!isFactionEliminated(state, 'blue'));
  for (const nodeId of ['B-HQ', 'B-Supply'] as const) {
    requireNode(state, nodeId).ownerFactionId = 'red';
    requireNode(state, nodeId).activeFromRound = 1;
    for (const slot of faction(state, 'blue').productionQueues[nodeId] ?? []) slot.orders = [];
  }
  assert.ok(isFactionEliminated(state, 'blue'));
  runSettlementAutoInPlace(state);
  assert.equal(state.result?.winner, 'red');
  assert.equal(state.result?.reason, 'elimination');
});
