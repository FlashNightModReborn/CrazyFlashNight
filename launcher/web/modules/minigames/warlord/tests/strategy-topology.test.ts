import assert from 'node:assert/strict';
import test from 'node:test';
import { DEMO_1_ENCOUNTER, DEMO_1_ENCOUNTER_BINDING } from '../src/data/encounter.js';
import type { MapDefinition } from '../src/strategy/definitions.js';
import { buildMapIndexes, computeMapTopologyMetrics } from '../src/strategy/topology.js';
import { validateMapDefinition } from '../src/strategy/validator.js';
import {
  DEMO_9_MAP,
  GRID_24_MAP,
  GRID_96_MAP,
  GRID_128_MAP,
} from './fixtures/strategy-maps.js';

function validated(source: unknown): MapDefinition {
  const result = validateMapDefinition(source, DEMO_1_ENCOUNTER_BINDING);
  if (!result.ok) throw new Error(JSON.stringify(result.issues));
  return result.definition;
}

test('strategy topology builds immutable indexes and Demo 1 metrics', () => {
  const definition = validated(DEMO_9_MAP);
  const indexes = buildMapIndexes(definition);
  const metrics = computeMapTopologyMetrics(definition, indexes);

  assert.equal(Object.isFrozen(indexes), true);
  assert.equal(Object.isFrozen(indexes.nodeById), true);
  assert.equal(Object.isFrozen(indexes.edgeById), true);
  assert.equal(Object.isFrozen(indexes.adjacencyByNode), true);
  assert.equal(Object.isFrozen(indexes.adjacencyByNode['R-HQ']), true);
  assert.equal(indexes.nodeById['R-HQ']?.kind, 'hq');
  assert.equal(indexes.adjacencyByNode['R-HQ']?.length, 2);

  assert.equal(metrics.nodeCount, 9);
  assert.equal(metrics.edgeCount, 12);
  assert.equal(metrics.componentCount, 1);
  assert.equal(metrics.minimumDegree, 2);
  assert.equal(metrics.maximumDegree, 4);
  assert.equal(metrics.averageDegree, 24 / 9);
  assert.equal(metrics.diameter, 4);
  assert.deepEqual(metrics.articulationNodeIds, []);
});

test('strategy topology scales deterministically across 24/96/128-node fixtures', () => {
  const cases = [
    { source: GRID_24_MAP, nodes: 24, edges: 38, diameter: 8 },
    { source: GRID_96_MAP, nodes: 96, edges: 172, diameter: 18 },
    { source: GRID_128_MAP, nodes: 128, edges: 232, diameter: 22 },
  ] as const;

  for (const fixture of cases) {
    const metrics = computeMapTopologyMetrics(validated(fixture.source));
    assert.equal(metrics.nodeCount, fixture.nodes);
    assert.equal(metrics.edgeCount, fixture.edges);
    assert.equal(metrics.componentCount, 1);
    assert.equal(metrics.maximumDegree, 4);
    assert.equal(metrics.diameter, fixture.diameter);
    assert.deepEqual(metrics.articulationNodeIds, []);
  }
});

test('strategy topology reports articulation nodes in authoring order', () => {
  const definition = validated({
    schemaVersion: 1,
    id: 'chain-four',
    rulesVersion: 'chain.v1',
    encounterDefinitionRef: DEMO_1_ENCOUNTER.id,
    nodes: ['a', 'b', 'c', 'd'].map((id) => ({
      id,
      kind: 'field',
      garrisonCapacity: 2,
      attackWidth: 1,
      defenseBonus: 0,
      encounterProfileRef: 'encounter.far',
    })),
    edges: [
      { id: 'ab', a: 'a', b: 'b' },
      { id: 'bc', a: 'b', b: 'c' },
      { id: 'cd', a: 'c', b: 'd' },
    ],
  });
  const metrics = computeMapTopologyMetrics(definition);
  assert.equal(metrics.diameter, 3);
  assert.deepEqual(metrics.articulationNodeIds, ['b', 'c']);
});
