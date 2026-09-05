import assert from 'node:assert/strict';
import test from 'node:test';
import { DEMO_1_ENCOUNTER, DEMO_1_ENCOUNTER_BINDING } from '../src/data/encounter.js';
import { normalizeOneOrMany } from '../src/strategy/normalize.js';
import { validateMapDefinition } from '../src/strategy/validator.js';
import { DEMO_9_MAP } from './fixtures/strategy-maps.js';

test('strategy map contract normalizes one-or-many without coercing opaque IDs', () => {
  const single = { id: '007' };
  assert.deepEqual(normalizeOneOrMany(single), [single]);
  assert.deepEqual(normalizeOneOrMany([single, { id: '008' }]), [single, { id: '008' }]);

  const result = validateMapDefinition({
    schemaVersion: 1,
    id: '007',
    rulesVersion: '1',
    encounterDefinitionRef: DEMO_1_ENCOUNTER.id,
    nodes: {
      id: '007',
      kind: 'hq',
      garrisonCapacity: 1,
      attackWidth: 1,
      defenseBonus: 0,
      encounterProfileRef: 'encounter.near',
    },
    edges: [],
  }, DEMO_1_ENCOUNTER_BINDING);
  assert(result.ok, JSON.stringify(result.issues));
  assert.equal(result.definition.id, '007');
  assert.equal(result.definition.nodes[0]?.id, '007');
  assert.equal(result.definition.nodes[0]?.nodeAPBonus, 0);
});

test('strategy map contract accepts the exact nine-node Demo 1 rule fixture', () => {
  const result = validateMapDefinition(DEMO_9_MAP, DEMO_1_ENCOUNTER_BINDING);
  assert(result.ok, JSON.stringify(result.issues));
  assert.equal(result.definition.nodes.length, 9);
  assert.equal(result.definition.edges.length, 12);
  assert.equal(Object.isFrozen(result.definition), true);
  assert.equal(Object.isFrozen(result.definition.nodes), true);
  assert.equal(Object.isFrozen(result.definition.nodes[0]), true);
});

test('strategy map contract emits only strict structured issues for malformed topology', () => {
  const firstNode = DEMO_9_MAP.nodes[0];
  const firstEdge = DEMO_9_MAP.edges[0];
  const result = validateMapDefinition({
    ...DEMO_9_MAP,
    nodes: [
      ...DEMO_9_MAP.nodes,
      { ...firstNode, id: 'R-HQ' },
      {
        id: 'isolated-node',
        kind: 'field',
        garrisonCapacity: 2,
        attackWidth: 3,
        defenseBonus: 0,
        x: 900,
      },
    ],
    edges: [
      ...DEMO_9_MAP.edges,
      { id: firstEdge.id, a: 'R-HQ', b: 'Center-Command' },
      { id: 'edge.reverse', a: firstEdge.b, b: firstEdge.a },
      { id: 'edge.loop', a: 'R-HQ', b: 'R-HQ' },
      { id: 'edge.unknown', a: 'R-HQ', b: 'missing-node' },
    ],
  }, DEMO_1_ENCOUNTER_BINDING);
  assert.equal(result.ok, false);
  if (result.ok) throw new Error('Expected validation failure.');

  const reasonCodes = new Set(result.issues.map((issue) => issue.reasonCode));
  for (const expected of [
    'unexpected_field',
    'duplicate_id',
    'duplicate_edge',
    'unknown_reference',
    'self_loop',
    'attack_width_exceeds_garrison_capacity',
    'map_disconnected',
  ] as const) {
    assert.equal(reasonCodes.has(expected), true, `missing ${expected}`);
  }
  for (const issue of result.issues) {
    assert.deepEqual(Object.keys(issue).sort(), ['params', 'path', 'reasonCode']);
    assert.equal(typeof issue.path, 'string');
    assert.equal(Object.isFrozen(issue), true);
    assert.equal(Object.isFrozen(issue.params), true);
  }
});

test('strategy map contract rejects empty maps and unsupported schemas', () => {
  const result = validateMapDefinition({
    schemaVersion: 2,
    id: 'empty-map',
    rulesVersion: 'rules.v2',
    encounterDefinitionRef: DEMO_1_ENCOUNTER.id,
    nodes: [],
    edges: [],
  }, DEMO_1_ENCOUNTER_BINDING);
  assert.equal(result.ok, false);
  if (result.ok) throw new Error('Expected validation failure.');
  assert.deepEqual(
    result.issues.map((issue) => issue.reasonCode),
    ['unsupported_schema_version', 'map_empty'],
  );
});
