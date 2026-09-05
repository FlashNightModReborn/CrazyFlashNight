import assert from 'node:assert/strict';
import test from 'node:test';
import {
  DEMO_2_ARM_NODE_IDS,
  DEMO_2_CENTRAL_NODE_IDS,
  DEMO_2_HOME_NODE_IDS,
  DEMO_2_MAP_AUTHORING,
  DEMO_2_MAP_PRESENTATION,
  DEMO_2_SCENARIO_AUTHORING,
  DEMO_2_SECTORS,
  type Demo2HomeKey,
} from '../src/data/demo2.js';
import { DEMO_1_ENCOUNTER_BINDING } from '../src/data/encounter.js';
import { validateWarlordScenario } from '../src/strategy/scenario.js';
import { validateMapDefinition } from '../src/strategy/validator.js';

const HOME_KEYS: readonly Demo2HomeKey[] = ['player', 'pact-a', 'independent', 'pact-b'];

function adjacencyWithout(removedNodeId: string | null = null): Map<string, Set<string>> {
  const adjacency = new Map<string, Set<string>>();
  for (const node of DEMO_2_MAP_AUTHORING.nodes) {
    if (node.id !== removedNodeId) adjacency.set(node.id, new Set());
  }
  for (const edge of DEMO_2_MAP_AUTHORING.edges) {
    if (edge.a === removedNodeId || edge.b === removedNodeId) continue;
    adjacency.get(edge.a)?.add(edge.b);
    adjacency.get(edge.b)?.add(edge.a);
  }
  return adjacency;
}

function isConnectedWithout(removedNodeId: string | null = null): boolean {
  const adjacency = adjacencyWithout(removedNodeId);
  const first = adjacency.keys().next().value as string | undefined;
  if (!first) return true;
  const visited = new Set([first]);
  const queue = [first];
  while (queue.length > 0) {
    const current = queue.shift();
    if (!current) continue;
    for (const next of adjacency.get(current) ?? []) {
      if (visited.has(next)) continue;
      visited.add(next);
      queue.push(next);
    }
  }
  return visited.size === adjacency.size;
}

function shortestDistance(origin: string, targets: ReadonlySet<string>): number {
  const adjacency = adjacencyWithout();
  const visited = new Set([origin]);
  const queue: Array<{ nodeId: string; distance: number }> = [{ nodeId: origin, distance: 0 }];
  while (queue.length > 0) {
    const current = queue.shift();
    if (!current) continue;
    if (targets.has(current.nodeId)) return current.distance;
    for (const next of adjacency.get(current.nodeId) ?? []) {
      if (visited.has(next)) continue;
      visited.add(next);
      queue.push({ nodeId: next, distance: current.distance + 1 });
    }
  }
  return Number.POSITIVE_INFINITY;
}

test('Slice 6 Demo 2 validates an 80-node four-faction thick-X scenario', () => {
  const mapResult = validateMapDefinition(DEMO_2_MAP_AUTHORING, DEMO_1_ENCOUNTER_BINDING);
  assert.equal(mapResult.ok, true, mapResult.ok ? undefined : JSON.stringify(mapResult.issues));
  if (!mapResult.ok) throw new Error(JSON.stringify(mapResult.issues));
  const scenarioResult = validateWarlordScenario(
    DEMO_2_SCENARIO_AUTHORING,
    mapResult.definition,
    DEMO_2_MAP_PRESENTATION.id,
  );
  assert.equal(scenarioResult.ok, true, scenarioResult.ok ? undefined : JSON.stringify(scenarioResult.issues));
  if (!scenarioResult.ok) throw new Error(JSON.stringify(scenarioResult.issues));

  assert.equal(mapResult.definition.nodes.length, 80);
  assert.equal(scenarioResult.definition.factions.length, 4);
  assert.equal(scenarioResult.definition.factions.filter((faction) => faction.controller === 'player').length, 1);
  assert.equal(new Set(scenarioResult.definition.factions.map((faction) => faction.headquartersNodeRef)).size, 4);
  for (const faction of scenarioResult.definition.factions) {
    const headquarters = mapResult.definition.nodes.find((node) => node.id === faction.headquartersNodeRef);
    assert.equal(headquarters?.kind, 'hq');
    assert.equal(headquarters?.distanceBand, 'near');
  }
});

test('Slice 6 Demo 2 sector catalog covers 56 home, 16 arm and 8 central nodes exactly once', () => {
  assert.equal(DEMO_2_SECTORS.length, 9);
  assert.equal(HOME_KEYS.reduce((sum, key) => sum + DEMO_2_HOME_NODE_IDS[key].length, 0), 56);
  assert.equal(HOME_KEYS.reduce((sum, key) => sum + DEMO_2_ARM_NODE_IDS[key].length, 0), 16);
  assert.equal(DEMO_2_CENTRAL_NODE_IDS.length, 8);
  const catalogNodes = DEMO_2_SECTORS.flatMap((sector) => sector.nodeRefs);
  assert.equal(catalogNodes.length, 80);
  assert.equal(new Set(catalogNodes).size, 80);
  assert.deepEqual(
    [...catalogNodes].sort(),
    DEMO_2_MAP_AUTHORING.nodes.map((node) => node.id).sort(),
  );
});

test('Slice 6 Demo 2 gives every home sector two independent exits and a 4-6 hop front', () => {
  for (const key of HOME_KEYS) {
    const home = new Set(DEMO_2_HOME_NODE_IDS[key]);
    const arm = new Set(DEMO_2_ARM_NODE_IDS[key]);
    const exits = DEMO_2_MAP_AUTHORING.edges.filter((edge) => (
      (home.has(edge.a) && arm.has(edge.b)) || (home.has(edge.b) && arm.has(edge.a))
    ));
    assert.equal(exits.length, 2, key + ' must have exactly two authored home-to-arm exits');
    assert.equal(new Set(exits.map((edge) => home.has(edge.a) ? edge.a : edge.b)).size, 2);
    assert.equal(new Set(exits.map((edge) => arm.has(edge.a) ? edge.a : edge.b)).size, 2);

    const hq = DEMO_2_HOME_NODE_IDS[key][0];
    if (!hq) throw new Error('Missing Demo 2 headquarters for ' + key + '.');
    const distance = shortestDistance(hq, new Set(DEMO_2_ARM_NODE_IDS[key].slice(0, 2)));
    assert.ok(distance >= 4 && distance <= 6, key + ' HQ-to-front distance was ' + distance);
  }
});

test('Slice 6 Demo 2 central industry is high value and the whole graph has no articulation node', () => {
  const central = new Set(DEMO_2_CENTRAL_NODE_IDS);
  const centralRules = DEMO_2_SCENARIO_AUTHORING.nodeRules.filter((rule) => central.has(rule.nodeRef));
  assert.equal(centralRules.length, 8);
  for (const rule of centralRules) {
    assert.ok(rule.strategicValue >= 8);
    assert.ok(rule.goldIncome >= 10);
    assert.ok(rule.productionSlots >= 3);
  }
  const centralNodes = DEMO_2_MAP_AUTHORING.nodes.filter((node) => central.has(node.id));
  assert.deepEqual(new Set(centralNodes.map((node) => node.encounterProfileRef)), new Set([
    'encounter.medium',
    'encounter.far',
  ]));
  assert.equal(isConnectedWithout(), true);
  for (const node of DEMO_2_MAP_AUTHORING.nodes) {
    assert.equal(isConnectedWithout(node.id), true, node.id + ' is an unintended global articulation node');
  }
});

test('Slice 6 Demo 2 presentation keeps four readable inward arms and opposing diagonals', () => {
  const positions = new Map(DEMO_2_MAP_PRESENTATION.nodes.map((node) => [node.nodeRef, node]));
  const expectedQuadrants: Readonly<Record<Demo2HomeKey, readonly [number, number]>> = {
    player: [-1, -1],
    'pact-a': [1, -1],
    independent: [1, 1],
    'pact-b': [-1, 1],
  };
  for (const key of HOME_KEYS) {
    const armPositions = DEMO_2_ARM_NODE_IDS[key].map((nodeId) => positions.get(nodeId));
    assert.equal(armPositions.every(Boolean), true);
    const outer = armPositions.slice(0, 2).reduce((sum, point) => (
      sum + Math.hypot((point?.x ?? 600) - 600, (point?.y ?? 450) - 450)
    ), 0) / 2;
    const inner = armPositions.slice(2).reduce((sum, point) => (
      sum + Math.hypot((point?.x ?? 600) - 600, (point?.y ?? 450) - 450)
    ), 0) / 2;
    assert.ok(inner < outer, key + ' arm must advance inward');
    const averageX = armPositions.reduce((sum, point) => sum + (point?.x ?? 600), 0) / 4;
    const averageY = armPositions.reduce((sum, point) => sum + (point?.y ?? 450), 0) / 4;
    const quadrant = expectedQuadrants[key];
    assert.ok(quadrant);
    assert.equal(Math.sign(averageX - 600), quadrant[0]);
    assert.equal(Math.sign(averageY - 450), quadrant[1]);
  }

  const factionById = new Map(DEMO_2_SCENARIO_AUTHORING.factions.map((faction) => [faction.id, faction]));
  const playerPosition = positions.get(factionById.get('player')?.headquartersNodeRef ?? '');
  const independentPosition = positions.get(factionById.get('boss-independent')?.headquartersNodeRef ?? '');
  const pactAPosition = positions.get(factionById.get('boss-pact-a')?.headquartersNodeRef ?? '');
  const pactBPosition = positions.get(factionById.get('boss-pact-b')?.headquartersNodeRef ?? '');
  if (!playerPosition || !independentPosition || !pactAPosition || !pactBPosition) {
    throw new Error('Demo 2 faction headquarters positions are incomplete.');
  }
  assert.ok(playerPosition.x < 600 && playerPosition.y < 450);
  assert.ok(independentPosition.x > 600 && independentPosition.y > 450);
  assert.ok(pactAPosition.x > 600 && pactAPosition.y < 450);
  assert.ok(pactBPosition.x < 600 && pactBPosition.y > 450);
});
