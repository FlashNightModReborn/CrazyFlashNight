import assert from 'node:assert/strict';
import test from 'node:test';
import { CARD_IDS, getCardDefinition } from '../src/data/cards.js';
import {
  WARLORD_PORTRAIT_IDENTIFIERS,
  identifierForCard,
  resolvePortraitDescriptors,
  textureUrlFor,
  textureUrlsFor,
  type EnemyPortraitResolver,
} from '../src/assets/portrait-texture-source.js';

const EXPECTED = [
  '敌人-军阀狙击兵',
  '敌人-军阀弹药兵',
  '敌人-军阀突击兵',
  '敌人-军阀重装兵',
  '敌人-军阀精英突击兵',
  '敌人-军阀精英狙击兵',
  '敌人-军阀精英弹药兵',
  '敌人-军阀精英重装兵',
];

test('PHASE-A-PORTRAIT eight identities come from frozen card definitions without copied URLs', () => {
  assert.deepEqual(WARLORD_PORTRAIT_IDENTIFIERS, EXPECTED);
  assert.deepEqual(CARD_IDS.map(identifierForCard), EXPECTED);
  assert.deepEqual(CARD_IDS.map((cardId) => getCardDefinition(cardId).identifier), EXPECTED);
  assert.equal(new Set(WARLORD_PORTRAIT_IDENTIFIERS).size, 8);
});

test('PHASE-A-PORTRAIT resolver contract covers all identities and prefers manifest PNG for WebGL', async () => {
  let loaded = false;
  const seen: string[] = [];
  const resolver: EnemyPortraitResolver = {
    async loadManifest() { loaded = true; return {}; },
    resolve(context) {
      seen.push(context.identifier);
      return {
        portraitRef: context.identifier,
        status: 'human_accepted',
        svgUrl: `manifest/${context.identifier}.svg`,
        pngUrl: `manifest/${context.identifier}.png`,
      };
    },
  };
  const descriptors = await resolvePortraitDescriptors(resolver);
  assert.equal(loaded, true);
  assert.deepEqual(seen, EXPECTED);
  assert.equal(descriptors.size, 8);
  for (const identifier of EXPECTED) {
    assert.equal(textureUrlFor(descriptors.get(identifier) ?? null), `manifest/${identifier}.png`);
    assert.deepEqual(textureUrlsFor(descriptors.get(identifier) ?? null), [
      `manifest/${identifier}.png`,
      `manifest/${identifier}.svg`,
    ]);
  }
});
