import assert from 'node:assert/strict';
import test from 'node:test';
import { requireFaction } from '../src/core/factions.js';
import { createPieceInPlace } from '../src/core/pieces.js';
import type { ProductionOrder } from '../src/core/types.js';
import { getCardDefinition } from '../src/data/cards.js';
import {
  flattenProductionOrders,
  projectProductionNodes,
  recommendProductionLane,
  resolveProductionChoice,
} from '../src/app/production-presenter.js';
import { applyOk, makeState, setPlanning } from './helpers.js';

function order(overrides: Partial<ProductionOrder> = {}): ProductionOrder {
  return {
    orderId: 'order-fixture',
    factionId: 'red',
    nodeId: 'R-HQ',
    slotId: 'R-HQ:1',
    cardId: 14,
    remainingRounds: 1,
    status: 'building',
    populationCost: 1,
    goldCost: 8,
    enqueuedRound: 1,
    ...overrides,
  };
}

test('PHASE-A-PRODUCTION initial network is read-only and recommends an empty site with deployment room', () => {
  const state = makeState('production-network');
  const before = structuredClone(state);
  const nodes = projectProductionNodes(state, 'red');
  const recommendation = recommendProductionLane(state, 'red');
  assert.deepEqual(nodes.map((node) => node.nodeId), ['R-HQ', 'R-Supply']);
  assert.equal(nodes.every((node) => node.lanes.length === 2), true);
  assert.equal(nodes.reduce((total, node) => total + node.orderCount, 0), 0);
  assert.deepEqual(recommendation, {
    nodeId: 'R-Supply',
    slotId: 'R-Supply:1',
    reason: '空闲槽 · 部署余量 4/4',
  });
  assert.deepEqual(state, before);
});

test('PHASE-A-PRODUCTION automatic choice balances the whole network while exact mode keeps authority', () => {
  const state = makeState('production-balancing');
  setPlanning(state);
  const red = requireFaction(state, 'red');
  red.gold = 100;
  red.productionQueues['R-Supply']?.[0]?.orders.push(order({
    orderId: 'supply-head', nodeId: 'R-Supply', slotId: 'R-Supply:1', remainingRounds: 2,
  }));
  red.productionQueues['R-Supply']?.[1]?.orders.push(order({
    orderId: 'supply-second', nodeId: 'R-Supply', slotId: 'R-Supply:2', remainingRounds: 1,
  }));
  const automatic = resolveProductionChoice(state, 'red', 14, 'auto', 'R-Supply', 'R-Supply:1');
  assert.equal(automatic.ok, true);
  assert.equal(automatic.nodeId, 'R-HQ');
  assert.equal(automatic.slotId, 'R-HQ:1');
  assert.match(automatic.reason, /空闲槽/);

  const exact = resolveProductionChoice(state, 'red', 14, 'exact', 'R-Supply', 'R-Supply:1');
  assert.equal(exact.ok, true);
  assert.equal(exact.nodeId, 'R-Supply');
  assert.equal(exact.slotId, 'R-Supply:1');
  assert.equal(exact.reason, '人工指定槽位');
});

test('PHASE-A-PRODUCTION waiting head exposes both deployment blockers and freezes the tail', () => {
  const state = makeState('production-blockers');
  const red = requireFaction(state, 'red');
  const slot = red.productionQueues['R-HQ']?.[0];
  assert.ok(slot);
  slot.orders.push(
    order({ orderId: 'waiting-head', remainingRounds: 0, status: 'waiting_deployment' }),
    order({ orderId: 'queued-tail', cardId: 13, remainingRounds: 2 }),
  );
  createPieceInPlace(state, 'red', 14, 'R-HQ', 1, { pieceId: 'capacity-blocker' });
  red.populationCap = red.populationUsed;
  const node = projectProductionNodes(state, 'red').find((candidate) => candidate.nodeId === 'R-HQ');
  const lane = node?.lanes[0];
  assert.ok(lane);
  assert.equal(lane.state, 'waiting_deployment');
  assert.equal(lane.blocked, true);
  assert.deepEqual(lane.blockerLabels, ['驻军 5 / 上限 5', '人口 5+1/5']);
  assert.equal(lane.head?.phaseLabel, '等待部署');
  assert.equal(lane.head?.progressPercent, 100);
  assert.equal(lane.tail[0]?.phaseLabel, '待开工');
  assert.equal(lane.workRounds, getCardDefinition(13).buildRounds);
  const network = flattenProductionOrders(projectProductionNodes(state, 'red'));
  assert.deepEqual(network.map((entry) => ({
    orderId: entry.orderId,
    nodeId: entry.nodeId,
    slotNumber: entry.slotNumber,
    queuePosition: entry.queuePosition,
    portraitRef: entry.portraitRef,
  })), [
    { orderId: 'waiting-head', nodeId: 'R-HQ', slotNumber: 1, queuePosition: 0, portraitRef: '敌人-军阀突击兵' },
    { orderId: 'queued-tail', nodeId: 'R-HQ', slotNumber: 1, queuePosition: 1, portraitRef: '敌人-军阀弹药兵' },
  ]);
});

test('PHASE-A-PRODUCTION canonical validator remains the only legality source', () => {
  const state = makeState('production-validation');
  setPlanning(state);
  const red = requireFaction(state, 'red');
  red.gold = 0;
  const noGold = resolveProductionChoice(state, 'red', 14, 'auto', 'R-HQ', 'R-HQ:1');
  assert.equal(noGold.ok, false);
  assert.equal(noGold.reasonCode, 'military_funds_insufficient');
  assert.deepEqual(noGold.reasonParams, { required: 8, available: 0 });

  red.gold = 100;
  const nonProduction = resolveProductionChoice(state, 'red', 14, 'exact', 'R-Economy', 'R-Economy:1');
  assert.equal(nonProduction.ok, false);
  assert.equal(nonProduction.reasonCode, 'production_node_invalid');
});

test('PHASE-A-PRODUCTION cancellation affordance is projected only for canonical unstarted orders', () => {
  let state = makeState('production-cancel-projection');
  setPlanning(state);
  requireFaction(state, 'red').gold = 100;
  state = applyOk(state, {
    type: 'ENQUEUE_PRODUCTION', factionId: 'red', nodeId: 'R-Supply', slotId: 'R-Supply:1', cardId: 14,
  });
  let lane = projectProductionNodes(state, 'red')
    .find((node) => node.nodeId === 'R-Supply')?.lanes[0];
  assert.equal(lane?.head?.cancellable, true);
  assert.equal(lane?.head?.cancelReason, null);
  assert.equal(lane?.head?.goldCost, 8);
  assert.equal(lane?.head?.populationCost, 1);

  requireFaction(state, 'red').planningCommitted = true;
  lane = projectProductionNodes(state, 'red')
    .find((node) => node.nodeId === 'R-Supply')?.lanes[0];
  assert.equal(lane?.head?.cancellable, false);
  assert.equal(lane?.head?.cancelReason, '本轮结算安排已经提交。 等待下一回合开始。');
});
