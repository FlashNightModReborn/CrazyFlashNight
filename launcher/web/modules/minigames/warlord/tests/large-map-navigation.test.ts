import assert from 'node:assert/strict';
import test from 'node:test';
import {
  ABSOLUTE_MAXIMUM_RENDERED_NODES,
  buildLargeMapSectorIndex,
  buildVirtualNodeWindow,
  deriveLargeMapAlerts,
  searchLargeMapNodes,
  type LargeMapNodeSummary,
  type LargeMapSector,
} from '../src/app/large-map-navigation.js';
import {
  DEMO_2_MAP_AUTHORING,
  DEMO_2_SCENARIO_AUTHORING,
  DEMO_2_SECTORS,
} from '../src/data/demo2.js';

const sectors: readonly LargeMapSector[] = DEMO_2_SECTORS.map((sector) => ({
  id: sector.id,
  displayName: sector.displayName,
  nodeIds: sector.nodeRefs,
}));

function searchableNodes(): LargeMapNodeSummary[] {
  const sectorIndex = buildLargeMapSectorIndex(
    sectors,
    DEMO_2_MAP_AUTHORING.nodes.map((node) => node.id),
  );
  const rulesByNode = new Map(DEMO_2_SCENARIO_AUTHORING.nodeRules.map((rule) => [rule.nodeRef, rule]));
  return DEMO_2_MAP_AUTHORING.nodes.map((node) => ({
    nodeId: node.id,
    displayName: rulesByNode.get(node.id)?.displayName ?? node.id,
    kind: node.kind,
    sectorId: sectorIndex.sectorByNodeId[node.id] ?? '',
  }));
}

test('large-map sector index gives all 80 Demo 2 nodes one and only one sector', () => {
  const nodeIds = DEMO_2_MAP_AUTHORING.nodes.map((node) => node.id);
  const index = buildLargeMapSectorIndex(sectors, nodeIds);
  assert.equal(index.sectorIds.length, 9);
  assert.equal(Object.keys(index.sectorByNodeId).length, 80);
  assert.equal(Object.values(index.nodeIdsBySectorId).flat().length, 80);
  assert.throws(() => buildLargeMapSectorIndex([
    ...sectors,
    { id: 'duplicate-membership', displayName: '重复归属', nodeIds: [nodeIds[0] ?? ''] },
  ], nodeIds), /belongs to more than one sector/);
});

test('large-map search understands Chinese node and sector names with deterministic bounds', () => {
  const nodes = searchableNodes();
  const central = searchLargeMapNodes(nodes, sectors, '中央高价值工业环', 3);
  assert.equal(central.totalMatches, 8);
  assert.equal(central.matches.length, 3);
  assert.equal(central.truncated, true);
  assert.equal(central.matches.every((match) => match.sectorId === 'sector.central-industry'), true);

  const ammunition = searchLargeMapNodes(nodes, sectors, '弹药厂', 20);
  assert.equal(ammunition.totalMatches, 4);
  assert.equal(ammunition.matches.every((match) => match.matchedFields.includes('displayName')), true);
  assert.deepEqual(searchLargeMapNodes(nodes, sectors, '弹药厂', 20), ammunition);
  assert.deepEqual(searchLargeMapNodes(nodes, sectors, '　 ', 20).matches, []);
});

test('large-map alerts deduplicate, prioritize danger and always provide a next step', () => {
  const result = deriveLargeMapAlerts([
    {
      nodeId: 'd2-player-01',
      nodeDisplayName: '西北远征军·总部',
      sectorId: 'sector.player-home',
      commandPostThreatened: true,
      productionBlockedReason: '人口不足',
      currentAction: '正在调兵',
    },
    {
      nodeId: 'd2-central-01',
      nodeDisplayName: '中央工业环·1',
      sectorId: 'sector.central-industry',
      encounterPending: true,
    },
    {
      nodeId: 'd2-player-01',
      nodeDisplayName: '西北远征军·总部',
      sectorId: 'sector.player-home',
      commandPostThreatened: true,
    },
  ], 3);
  assert.equal(result.totalAlerts, 4);
  assert.equal(result.alerts.length, 3);
  assert.equal(result.truncated, true);
  assert.deepEqual(result.alerts.map((alert) => alert.category), [
    'command-post-threatened',
    'encounter-pending',
    'production-blocked',
  ]);
  assert.equal(new Set(result.alerts.map((alert) => alert.id)).size, result.alerts.length);
  assert.equal(result.alerts.every((alert) => alert.nextStep.length > 0), true);
});

test('large-map virtual navigation never materializes more than its hard bound', () => {
  const nodeIds = Array.from({ length: 100 }, (_, index) => 'node-' + String(index + 1).padStart(3, '0'));
  const middle = buildVirtualNodeWindow({
    nodeIds,
    requestedStart: 40,
    viewportSize: 10,
    overscan: 5,
    maximumRendered: 24,
  });
  assert.ok(middle.renderedCount <= 24);
  assert.equal(middle.nodeIds.includes(nodeIds[40] ?? ''), true);
  assert.equal(middle.nodeIds.includes(nodeIds[49] ?? ''), true);
  assert.equal(middle.hasBefore, true);
  assert.equal(middle.hasAfter, true);

  const tail = buildVirtualNodeWindow({
    nodeIds,
    requestedStart: 98,
    viewportSize: 12,
    maximumRendered: 1_000,
  });
  assert.equal(tail.endExclusive, 100);
  assert.ok(tail.renderedCount <= ABSOLUTE_MAXIMUM_RENDERED_NODES);
  assert.equal(tail.hasAfter, false);
  assert.throws(() => buildVirtualNodeWindow({
    nodeIds,
    requestedStart: -1,
    viewportSize: 10,
  }), /requestedStart/);
});
