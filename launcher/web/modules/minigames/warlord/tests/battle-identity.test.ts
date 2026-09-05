import assert from 'node:assert/strict';
import test from 'node:test';

import { createBattleIdentity } from '../src/battle/identity.js';

test('battle identity matches the cross-authority canonical wire example', () => {
  assert.deepEqual(createBattleIdentity({
    gameSeed: 'phase-c-as2-authority',
    strategicRound: 1,
    battleOrdinal: 1,
    attackerIds: ['pet-red-12'],
    defenderIds: ['pet-blue-15'],
  }), {
    battleId: 'b-r1-o1',
    seed: 'phase-c-as2-authority|1|1|["pet-red-12"]|["pet-blue-15"]',
  });
});

test('battle identity canonicalizes piece order without mutating caller arrays', () => {
  const attackerIds = ['red-z', 'red-a'];
  const defenderIds = ['blue-z', 'blue-a'];
  const first = createBattleIdentity({
    gameSeed: 'canonical-order',
    strategicRound: 3,
    battleOrdinal: 7,
    attackerIds,
    defenderIds,
  });
  const second = createBattleIdentity({
    gameSeed: 'canonical-order',
    strategicRound: 3,
    battleOrdinal: 7,
    attackerIds: [...attackerIds].reverse(),
    defenderIds: [...defenderIds].reverse(),
  });

  assert.deepEqual(first, second);
  assert.deepEqual(attackerIds, ['red-z', 'red-a']);
  assert.deepEqual(defenderIds, ['blue-z', 'blue-a']);
});
