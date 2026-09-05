import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';
import { DEMO_2_MAP_AUTHORING } from '../src/data/demo2.js';

test('idle coaching and modal backdrops do not require continuous blur or shadow repaint', () => {
  const css = String(readFileSync(resolve(process.cwd(), 'warlord.css'), 'utf8'));
  assert.equal(/backdrop-filter\s*:\s*[^;]*blur\(/.test(css), false);
  assert.equal(/warlord-coach-pulse/.test(css), false);
  for (const selector of ['.warlord-coach-tip', '.warlord-command-intent.is-coach']) {
    const start = css.indexOf(selector + ' {');
    assert.ok(start >= 0);
    const rule = css.slice(start, css.indexOf('}', start));
    assert.equal(/animation\s*:/.test(rule), false);
    assert.match(rule, /box-shadow\s*:/);
  }
});

interface ScenePerformanceModule {
  PLAYER_AVATAR_PORTRAIT_IDENTIFIER: string;
  portraitIdentifierForPiece(
    state: { commanders: Record<string, { role: string; status: string; pieceInstanceId: string | null }> },
    piece: { pieceId: string; cardId: 83 },
  ): string;
  planSandtableBatches(nodeCount: number, edgeCount: number): {
    nodeCount: number;
    edgeCount: number;
    legacyRouteDrawCalls: number;
    routeGeometryCount: number;
    routeTextureCount: number;
    routeStaticDrawCalls: number;
    routeDynamicDrawCallUpperBound: number;
    routeDrawCallUpperBound: number;
    routeVertexCapacity: number;
    routeIndexCapacity: number;
    overviewNodeInstancing: boolean;
    overviewNodeInstanceDrawCalls: number;
  };
  disposeSandtableResourceGroups(
    groups: Array<Array<{ dispose?: () => void }>>,
  ): number;
}

test('player commander map token bypasses the shared sniper card texture only for its bound instance', async () => {
  const { PLAYER_AVATAR_PORTRAIT_IDENTIFIER, portraitIdentifierForPiece } = await loadScenePerformanceModule();
  const state = {
    commanders: {
      player: { role: 'player_avatar', status: 'fielded', pieceInstanceId: 'player-piece' },
    },
  };
  assert.equal(
    portraitIdentifierForPiece(state as never, { pieceId: 'player-piece', cardId: 83 } as never),
    PLAYER_AVATAR_PORTRAIT_IDENTIFIER,
  );
  assert.notEqual(
    portraitIdentifierForPiece(state as never, { pieceId: 'ordinary-sniper', cardId: 83 } as never),
    PLAYER_AVATAR_PORTRAIT_IDENTIFIER,
  );
});

async function loadScenePerformanceModule(): Promise<ScenePerformanceModule> {
  // Tests run after build-runtime.mjs. Importing the generated module keeps its
  // ../../vendor route pointed at the audited root vendor copy instead of the
  // intentionally source-only .test-dist tree.
  // @ts-expect-error generated runtime is created before the test process starts
  return import('../../runtime/scene/sandtable-scene.js') as Promise<ScenePerformanceModule>;
}

test('Demo 1 keeps detailed nodes while route batching replaces per-edge draw calls', async () => {
  const { planSandtableBatches } = await loadScenePerformanceModule();
  const plan = planSandtableBatches(9, 12);
  assert.equal(plan.overviewNodeInstancing, false);
  assert.equal(plan.overviewNodeInstanceDrawCalls, 0);
  assert.equal(plan.legacyRouteDrawCalls, 24);
  assert.equal(plan.routeStaticDrawCalls, 2);
  assert.equal(plan.routeDynamicDrawCallUpperBound, 2);
  assert.equal(plan.routeDrawCallUpperBound, 4);
  assert.equal(plan.routeGeometryCount, 3);
  assert.equal(plan.routeTextureCount, 2);
});

test('Demo 2 thick-X map has constant route batches and two overview node instances', async () => {
  const { planSandtableBatches } = await loadScenePerformanceModule();
  const plan = planSandtableBatches(
    DEMO_2_MAP_AUTHORING.nodes.length,
    DEMO_2_MAP_AUTHORING.edges.length,
  );
  assert.equal(plan.nodeCount, 80);
  assert.equal(plan.edgeCount, DEMO_2_MAP_AUTHORING.edges.length);
  assert.equal(plan.overviewNodeInstancing, true);
  assert.equal(plan.overviewNodeInstanceDrawCalls, 2);
  assert.equal(plan.routeDrawCallUpperBound, 4);
  assert.ok(plan.routeDrawCallUpperBound < plan.legacyRouteDrawCalls / 10);
  assert.equal(
    plan.routeVertexCapacity,
    DEMO_2_MAP_AUTHORING.edges.length * 66 * 3,
  );
  assert.equal(
    plan.routeIndexCapacity,
    DEMO_2_MAP_AUTHORING.edges.length * 192 * 3,
  );
});

test('route draw-call and texture bounds do not grow with edge count', async () => {
  const { planSandtableBatches } = await loadScenePerformanceModule();
  const small = planSandtableBatches(9, 12);
  const large = planSandtableBatches(500, 2_000);
  assert.equal(large.routeDrawCallUpperBound, small.routeDrawCallUpperBound);
  assert.equal(large.routeGeometryCount, small.routeGeometryCount);
  assert.equal(large.routeTextureCount, small.routeTextureCount);
  assert.equal(large.legacyRouteDrawCalls, 4_000);
});

test('shared scene disposal releases duplicates exactly once and empties all owners', async () => {
  const { disposeSandtableResourceGroups } = await loadScenePerformanceModule();
  let firstDisposals = 0;
  let secondDisposals = 0;
  const first = { dispose: (): void => { firstDisposals += 1; } };
  const second = { dispose: (): void => { secondDisposals += 1; } };
  const geometry = [first, second];
  const material = [first];
  const texture = [second, second];

  assert.equal(disposeSandtableResourceGroups([geometry, material, texture]), 2);
  assert.equal(firstDisposals, 1);
  assert.equal(secondDisposals, 1);
  assert.deepEqual(geometry, []);
  assert.deepEqual(material, []);
  assert.deepEqual(texture, []);
});

test('shared scene disposal continues after one resource throws and still empties every owner', async () => {
  const { disposeSandtableResourceGroups } = await loadScenePerformanceModule();
  let laterDisposals = 0;
  const broken = { dispose: (): void => { throw new Error('synthetic dispose failure'); } };
  const later = { dispose: (): void => { laterDisposals += 1; } };
  const first = [broken, later];
  const duplicate = [broken];

  assert.equal(disposeSandtableResourceGroups([first, duplicate]), 2);
  assert.equal(laterDisposals, 1);
  assert.deepEqual(first, []);
  assert.deepEqual(duplicate, []);
});
