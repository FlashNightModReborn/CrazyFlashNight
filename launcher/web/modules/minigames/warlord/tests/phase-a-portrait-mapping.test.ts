import assert from 'node:assert/strict';
import test from 'node:test';
import { CARD_IDS, getCardDefinition } from '../src/data/cards.js';
import {
  WARLORD_PORTRAIT_IDENTIFIERS,
  identifierForCard,
  mercActorFromPlayerAvatarPortrait,
  normalizePlayerAvatarPortrait,
  resolvePortraitDescriptors,
  textureUrlFor,
  textureUrlsFor,
  type EnemyPortraitResolver,
} from '../src/assets/portrait-texture-source.js';

const PLAYER_AVATAR_PORTRAIT = {
  schema: 'warlord.player-avatar-portrait.v1',
  gender: '男',
  face: 'face.hero.1',
  hair: 'hair.hero.2',
  equipment: {
    head: 'hat.hero.3',
    body: 'body.hero.4',
    hand: '',
    leg: 'leg.hero.5',
    foot: 'foot.hero.6',
    neck: '',
  },
} as const;

const EXPECTED = [
  '敌人-军阀狙击兵',
  '敌人-军阀弹药兵',
  '敌人-军阀突击兵',
  '敌人-军阀重装兵',
  '敌人-军阀精英突击兵',
  '敌人-军阀精英狙击兵',
  '敌人-军阀精英弹药兵',
  '敌人-军阀精英重装兵',
  '敌人-Itinerant',
  '敌人-Gazer',
  '敌人-Surveyor',
];

test('PHASE-A-PORTRAIT all troop and commander identities come from frozen card definitions without copied URLs', () => {
  assert.deepEqual(WARLORD_PORTRAIT_IDENTIFIERS, EXPECTED);
  assert.deepEqual(CARD_IDS.map(identifierForCard), EXPECTED);
  assert.deepEqual(CARD_IDS.map((cardId) => getCardDefinition(cardId).identifier), EXPECTED);
  assert.equal(new Set(WARLORD_PORTRAIT_IDENTIFIERS).size, 11);
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
  assert.equal(descriptors.size, 11);
  for (const identifier of EXPECTED) {
    assert.equal(textureUrlFor(descriptors.get(identifier) ?? null), `manifest/${identifier}.png`);
    assert.deepEqual(textureUrlsFor(descriptors.get(identifier) ?? null), [
      `manifest/${identifier}.png`,
      `manifest/${identifier}.svg`,
    ]);
  }
});

test('Warlord player avatar portrait accepts only the Host-safe paper-doll tuple', () => {
  assert.deepEqual(normalizePlayerAvatarPortrait(PLAYER_AVATAR_PORTRAIT), PLAYER_AVATAR_PORTRAIT);
  assert.deepEqual(mercActorFromPlayerAvatarPortrait(PLAYER_AVATAR_PORTRAIT), {
    gender: PLAYER_AVATAR_PORTRAIT.gender,
    face: PLAYER_AVATAR_PORTRAIT.face,
    hair: PLAYER_AVATAR_PORTRAIT.hair,
    equipment: PLAYER_AVATAR_PORTRAIT.equipment,
  });
  assert.equal(normalizePlayerAvatarPortrait({
    ...PLAYER_AVATAR_PORTRAIT,
    portraitUrl: 'https://untrusted.example/portrait.png',
  }), null);
  assert.equal(normalizePlayerAvatarPortrait({
    ...PLAYER_AVATAR_PORTRAIT,
    equipment: {
      ...PLAYER_AVATAR_PORTRAIT.equipment,
      hand: 'weapon\\unsafe',
    },
  }), null);
});
