import assert from 'node:assert/strict';
import test from 'node:test';
import { createGame } from '../src/core/state.js';
import { projectNodes } from '../src/app/presenter.js';
import { MAP_THEMES, normalizeMapTheme } from '../src/scene/map-theme.js';

test('PHASE-A-THEME desert and tundra swap presentation tokens without changing topology', () => {
  const state = createGame({ seed: 'theme-contract' });
  const kinds = new Set(projectNodes(state).map((node) => node.kind));
  assert.deepEqual([...kinds].sort(), ['choke', 'command', 'depot', 'economy', 'hq', 'supply']);
  assert.equal(Object.keys(MAP_THEMES).length, 2);
  assert.notEqual(MAP_THEMES.desert.background, MAP_THEMES.tundra.background);
  assert.notEqual(MAP_THEMES.desert.terrainHue, MAP_THEMES.tundra.terrainHue);
  assert.equal(normalizeMapTheme('tundra'), 'tundra');
  assert.equal(normalizeMapTheme('unknown'), 'desert');
  assert.equal(Object.keys(state.map.nodes).length, 9);
  assert.equal(state.map.edges.length, 12);
});
