// Pure acceptance test. Run: node web/modules/layout-core.test.mjs
import assert from 'node:assert/strict';
import { layoutFor, chooseLayout, validateLayout, aabbOverlap, LAYOUT_KEYS } from './layout-core.mjs';
const expected = {
  wide: { width: 23.8, height: 17.15, tiers: 2, archives: 1, reserves: 8 },
  medium: { width: 16, height: 26.9, tiers: 3, archives: 2, reserves: 9 },
  narrow: { width: 11.6, height: 34, tiers: 4, archives: 2, reserves: 6 }
};
const dimensions = new Map();
for (const key of LAYOUT_KEYS) {
  const l = layoutFor(key), want = expected[key], result = validateLayout(l);
  assert.equal(result.ok, true, result.errors.join('\n'));
  assert.equal(l.width, want.width); assert.equal(l.height, want.height);
  assert.equal(l.bookTierCount, want.tiers); assert.equal(l.archiveRowCount, want.archives);
  assert.equal(l.reserveSlots.length, want.reserves);
  assert.ok(Object.isFrozen(l) && Object.isFrozen(l.placements));
  for (const item of l.items.filter(v => v.kind === 'book' || v.kind === 'collection')) {
    if (dimensions.has(item.name)) assert.deepEqual(item.size, dimensions.get(item.name));
    dimensions.set(item.name, item.size);
    assert.ok(item.size[1] <= 6.55);
  }
  assert.deepEqual(l.placements.DISC_CF1, [-2.21, 0.23, 0]);
  assert.deepEqual(l.placements.DISC_CF6, [2.19, 0.23, 0]);
}
for (const [aspect, previous, expected] of [
  [1.6, '', 'wide'], [1, '', 'medium'], [.6, '', 'narrow'],
  [1.35, 'wide', 'wide'], [1.33, 'wide', 'medium'],
  [1.49, 'medium', 'medium'], [1.51, 'medium', 'wide'],
  [.75, 'medium', 'medium'], [.73, 'medium', 'narrow'],
  [.89, 'narrow', 'narrow'], [.91, 'narrow', 'medium'],
  [NaN, 'medium', 'medium'], [0, '', 'wide']
]) assert.equal(chooseLayout(aspect, previous), expected);
assert.equal(aabbOverlap({ min: [0, 0, 0], max: [1, 1, 1] }, { min: [1, 0, 0], max: [2, 1, 1] }), false);
assert.throws(() => layoutFor('missing'), RangeError);
console.log('PASS: all 3 layouts; object dimensions; shelf clearances; book/collection/archive/reserve AABBs; board intersections; hysteresis.');
