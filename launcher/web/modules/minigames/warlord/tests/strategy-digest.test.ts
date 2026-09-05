import assert from 'node:assert/strict';
import test from 'node:test';
import { canonicalJson } from '../src/core/canonical.js';
import { DEMO_1_ENCOUNTER_BINDING } from '../src/data/encounter.js';
import type { MapDefinition } from '../src/strategy/definitions.js';
import { computeMapContractDigests } from '../src/strategy/digest.js';
import { validateMapDefinition } from '../src/strategy/validator.js';
import {
  DEMO_9_MAP,
  DEMO_DESERT_PRESENTATION,
  DEMO_TUNDRA_PRESENTATION,
} from './fixtures/strategy-maps.js';

function validated(source: unknown): MapDefinition {
  const result = validateMapDefinition(source, DEMO_1_ENCOUNTER_BINDING);
  if (!result.ok) throw new Error(JSON.stringify(result.issues));
  return result.definition;
}

test('strategy digest canonical JSON is independent of object key insertion order', () => {
  assert.equal(
    canonicalJson({ z: 1, nested: { b: 2, a: 3 } }),
    canonicalJson({ nested: { a: 3, b: 2 }, z: 1 }),
  );
});

test('strategy digest keeps integer-shaped object keys in ordinal canonical order', () => {
  assert.equal(
    canonicalJson({ cards: { 12: 'sniper', 111: 'commander-a', 2: 'legacy' } }),
    '{"cards":{"111":"commander-a","12":"sniper","2":"legacy"}}',
  );
});

test('strategy digest keeps rules and presentation fault domains independent', async () => {
  const definition = validated(DEMO_9_MAP);
  const desert = await computeMapContractDigests(definition, DEMO_DESERT_PRESENTATION);
  const tundra = await computeMapContractDigests(definition, DEMO_TUNDRA_PRESENTATION);

  assert.match(desert.rulesDigest, /^sha256:[0-9a-f]{64}$/);
  assert.match(desert.presentationDigest, /^sha256:[0-9a-f]{64}$/);
  assert.equal(desert.rulesDigest, tundra.rulesDigest);
  assert.notEqual(desert.presentationDigest, tundra.presentationDigest);
  assert.equal(Object.isFrozen(desert), true);
});

test('strategy digest changes only rules digest when only a rule value changes', async () => {
  const baseline = validated(DEMO_9_MAP);
  const changed = validated({
    ...DEMO_9_MAP,
    nodes: DEMO_9_MAP.nodes.map((node) => (
      node.id === 'North-Choke' ? { ...node, defenseBonus: 0.25 } : node
    )),
  });
  const baselineDigests = await computeMapContractDigests(baseline, DEMO_DESERT_PRESENTATION);
  const changedDigests = await computeMapContractDigests(changed, DEMO_DESERT_PRESENTATION);

  assert.notEqual(baselineDigests.rulesDigest, changedDigests.rulesDigest);
  assert.equal(baselineDigests.presentationDigest, changedDigests.presentationDigest);
});
