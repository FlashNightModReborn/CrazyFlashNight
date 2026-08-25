import assert from 'node:assert/strict';
import test from 'node:test';
import { applyCommand } from '../src/core/engine.js';
import { progressProductionInPlace } from '../src/core/lifecycle.js';
import { makeReplay, replayGame } from '../src/replay/replay.js';
import { validateCommand } from '../src/core/validator.js';
import { applyOk, makeState, setPlanning } from './helpers.js';

test('PHASE-A-CANCEL 未开工订单可全额撤销并释放预留人口', () => {
  let state = makeState('cancel-unstarted');
  setPlanning(state);
  state.factions.red.gold = 100;
  const populationBefore = state.factions.red.populationReserved;
  state = applyOk(state, {
    type: 'ENQUEUE_PRODUCTION', factionId: 'red', nodeId: 'R-Supply', slotId: 'R-Supply:1', cardId: 14,
  });
  const order = state.factions.red.productionQueues['R-Supply']?.[0]?.orders[0];
  assert.ok(order);
  assert.equal(state.factions.red.gold, 100 - order.goldCost);
  assert.equal(state.factions.red.populationReserved, populationBefore + order.populationCost);

  state = applyOk(state, {
    type: 'CANCEL_PRODUCTION', factionId: 'red', nodeId: 'R-Supply', slotId: 'R-Supply:1', orderId: order.orderId,
  });
  assert.equal(state.factions.red.gold, 100);
  assert.equal(state.factions.red.populationReserved, populationBefore);
  assert.equal(state.factions.red.productionQueues['R-Supply']?.[0]?.orders.length, 0);
  assert.equal(state.commandHistory.at(-1)?.command.type, 'CANCEL_PRODUCTION');
  const event = state.eventLog.at(-1);
  assert.equal(event?.type, 'production_cancelled');
  assert.deepEqual(event?.data, {
    orderId: order.orderId,
    reason: 'player_undo',
    refundGold: order.goldCost,
    releasedPopulation: order.populationCost,
  });
});

test('PHASE-A-CANCEL 已获得生产进度的订单保持锁定', () => {
  let state = makeState('cancel-progressed');
  setPlanning(state);
  state.factions.red.gold = 100;
  state.factions.red.cards[15].level = 10;
  state = applyOk(state, {
    type: 'ENQUEUE_PRODUCTION', factionId: 'red', nodeId: 'R-HQ', slotId: 'R-HQ:1', cardId: 15,
  });
  const order = state.factions.red.productionQueues['R-HQ']?.[0]?.orders[0];
  assert.ok(order);
  progressProductionInPlace(state);
  assert.equal(order.remainingRounds, 1);

  const command = {
    type: 'CANCEL_PRODUCTION' as const,
    factionId: 'red' as const,
    nodeId: 'R-HQ' as const,
    slotId: 'R-HQ:1',
    orderId: order.orderId,
  };
  const validation = validateCommand(state, command);
  assert.equal(validation.ok, false);
  assert.equal(validation.error, '订单已经获得生产进度，不能撤销。');
  const result = applyCommand(state, command);
  assert.equal(result.ok, false);
  assert.equal(result.state, state);
});

test('PHASE-A-CANCEL 可精确撤销待开工队尾而不改变队首', () => {
  let state = makeState('cancel-tail');
  setPlanning(state);
  state.factions.red.gold = 100;
  state.factions.red.cards[15].level = 10;
  state = applyOk(state, {
    type: 'ENQUEUE_PRODUCTION', factionId: 'red', nodeId: 'R-HQ', slotId: 'R-HQ:1', cardId: 15,
  });
  state = applyOk(state, {
    type: 'ENQUEUE_PRODUCTION', factionId: 'red', nodeId: 'R-HQ', slotId: 'R-HQ:1', cardId: 14,
  });
  const slot = state.factions.red.productionQueues['R-HQ']?.[0];
  assert.ok(slot);
  const [head, tail] = slot.orders;
  assert.ok(head && tail);
  const goldBeforeCancel = state.factions.red.gold;
  const reservedBeforeCancel = state.factions.red.populationReserved;

  state = applyOk(state, {
    type: 'CANCEL_PRODUCTION', factionId: 'red', nodeId: 'R-HQ', slotId: 'R-HQ:1', orderId: tail.orderId,
  });
  const remaining = state.factions.red.productionQueues['R-HQ']?.[0]?.orders;
  assert.deepEqual(remaining?.map((order) => order.orderId), [head.orderId]);
  assert.equal(state.factions.red.gold, goldBeforeCancel + tail.goldCost);
  assert.equal(state.factions.red.populationReserved, reservedBeforeCancel - tail.populationCost);
});

test('PHASE-A-CANCEL 仅在本阵营尚未提交的结算规划中开放', () => {
  let state = makeState('cancel-phase-gate');
  setPlanning(state);
  state.factions.red.gold = 100;
  state = applyOk(state, {
    type: 'ENQUEUE_PRODUCTION', factionId: 'red', nodeId: 'R-Supply', slotId: 'R-Supply:1', cardId: 14,
  });
  const orderId = state.factions.red.productionQueues['R-Supply']?.[0]?.orders[0]?.orderId;
  assert.ok(orderId);
  const command = {
    type: 'CANCEL_PRODUCTION' as const,
    factionId: 'red' as const,
    nodeId: 'R-Supply' as const,
    slotId: 'R-Supply:1',
    orderId,
  };

  state.factions.red.planningCommitted = true;
  assert.equal(validateCommand(state, command).error, '该阵营已经提交规划。');
  state.factions.red.planningCommitted = false;
  state.phase = 'FIRST_FACTION_ACTION';
  state.activeFactionId = 'red';
  assert.equal(validateCommand(state, command).error, '当前不是结算规划阶段。');
});

test('PHASE-A-CANCEL 撤销命令进入录像并可逐字段重放', () => {
  let state = makeState('cancel-replay');
  const firstFaction = state.activeFactionId;
  assert.ok(firstFaction);
  state = applyOk(state, { type: 'END_ACTION', factionId: firstFaction });
  const secondFaction = state.activeFactionId;
  assert.ok(secondFaction);
  state = applyOk(state, { type: 'END_ACTION', factionId: secondFaction });
  const orderSlot = state.factions.red.productionQueues['R-Supply']?.[0];
  assert.ok(orderSlot);
  state = applyOk(state, {
    type: 'ENQUEUE_PRODUCTION', factionId: 'red', nodeId: 'R-Supply', slotId: orderSlot.slotId, cardId: 14,
  });
  const orderId = state.factions.red.productionQueues['R-Supply']?.[0]?.orders[0]?.orderId;
  assert.ok(orderId);
  state = applyOk(state, {
    type: 'CANCEL_PRODUCTION', factionId: 'red', nodeId: 'R-Supply', slotId: orderSlot.slotId, orderId,
  });

  assert.deepEqual(replayGame(makeReplay(state)), state);
});
