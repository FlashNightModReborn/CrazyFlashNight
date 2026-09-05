import assert from 'node:assert/strict';
import test from 'node:test';
import { requireNode } from '../src/core/access.js';
import { piecesAtNode } from '../src/core/selectors.js';
import { createGame } from '../src/core/state.js';
import { DEMO_1_ENCOUNTER, DEMO_1_ENCOUNTER_BINDING } from '../src/data/encounter.js';
import {
  DEMO_1_MAP_AUTHORING,
  DEMO_1_MAP_PRESENTATION,
  DEMO_1_SCENARIO_AUTHORING,
} from '../src/data/demo1.js';
import { buildRuntimeMapBundle, DEMO_1_RUNTIME } from '../src/data/map.js';
import { validateWarlordScenario } from '../src/strategy/scenario.js';
import { validateMapDefinition } from '../src/strategy/validator.js';
import { GRID_24_MAP } from './fixtures/strategy-maps.js';

test('Slice 2 Demo 1 live state consumes validated map, presentation and scenario initial state', () => {
  const state = createGame({ seed: 'slice-2-live-demo-1' });
  assert.equal(state.mapDefinitionId, DEMO_1_MAP_AUTHORING.id);
  assert.equal(state.mapPresentationId, DEMO_1_MAP_PRESENTATION.id);
  assert.equal(state.scenarioId, DEMO_1_SCENARIO_AUTHORING.id);
  assert.equal(Object.keys(state.map.nodes).length, 9);
  assert.equal(state.map.edges.length, 12);
  assert.equal(requireNode(state, 'Center-Command').attackWidth, 4);
  assert.equal(requireNode(state, 'Center-Command').capacity, 4);
  assert.equal(requireNode(state, 'Center-Command').apBonus, 2);
  assert.equal(requireNode(state, 'R-HQ').ownerFactionId, 'red');
  assert.equal(requireNode(state, 'B-HQ').ownerFactionId, 'blue');
  assert.equal(requireNode(state, 'North-Choke').ownerFactionId, null);
  assert.deepEqual(piecesAtNode(state, 'R-HQ', 'red').map((piece) => piece.cardId), [12, 13, 14, 14]);
  assert.deepEqual(piecesAtNode(state, 'B-HQ', 'blue').map((piece) => piece.cardId), [12, 13, 14, 14]);
  assert.equal(DEMO_1_RUNTIME.mapIndexes.adjacencyByNode['R-HQ']?.length, 2);
});

test('Slice 2 runtime bundle treats opaque node IDs and scenario control as data, not prefixes', () => {
  const map = {
    schemaVersion: 1,
    id: 'opaque-two-node',
    rulesVersion: 'slice-2.test.v1',
    encounterDefinitionRef: DEMO_1_ENCOUNTER.id,
    nodes: [
      { id: 'alpha', kind: 'hq', garrisonCapacity: 2, attackWidth: 1, defenseBonus: 0, encounterProfileRef: 'encounter.far' },
      { id: 'omega', kind: 'hq', garrisonCapacity: 2, attackWidth: 1, defenseBonus: 0, encounterProfileRef: 'encounter.near' },
    ],
    edges: [{ id: 'alpha-omega', a: 'alpha', b: 'omega' }],
  } as const;
  const presentation = {
    schemaVersion: 1,
    id: 'opaque-two-node.visual',
    mapRef: 'opaque-two-node',
    themeRef: 'test',
    nodes: [{ nodeRef: 'alpha', x: 10, y: 20 }, { nodeRef: 'omega', x: 30, y: 40 }],
  } as const;
  const scenario = {
    schemaVersion: 1,
    id: 'opaque-two-node.scenario',
    rulesVersion: 'slice-2.test.v1',
    mapRef: 'opaque-two-node',
    mapPresentationRef: 'opaque-two-node.visual',
    playerFactionRef: 'red',
    turnOrder: ['red', 'blue'],
    factions: [
      { id: 'red', displayName: '红方', controller: 'player', headquartersNodeRef: 'omega', supplyNodeRef: 'omega' },
      { id: 'blue', displayName: '蓝方', controller: 'ai', headquartersNodeRef: 'alpha', supplyNodeRef: 'alpha' },
    ],
    nodeRules: [
      { nodeRef: 'alpha', displayName: '甲地', strategicValue: 1, goldIncome: 0, population: 1, productionSlots: 0 },
      { nodeRef: 'omega', displayName: '乙地', strategicValue: 1, goldIncome: 0, population: 1, productionSlots: 0 },
    ],
    initialState: {
      nodeControls: [{ nodeRef: 'alpha', factionRef: 'blue' }, { nodeRef: 'omega', factionRef: 'red' }],
      standardDeployments: [{ nodeRef: 'omega', factionRef: 'red', cardIds: 14 }, { nodeRef: 'alpha', factionRef: 'blue', cardIds: 14 }],
      allUnitsDeployments: [{ nodeRef: 'omega', factionRef: 'red', cardIds: 14 }, { nodeRef: 'alpha', factionRef: 'blue', cardIds: 14 }],
    },
  } as const;
  const bundle = buildRuntimeMapBundle(map, presentation, scenario);
  assert.equal(bundle.initialControlByNode.alpha, 'blue');
  assert.equal(bundle.initialControlByNode.omega, 'red');
  assert.deepEqual(bundle.adjacencyByNode.alpha, ['omega']);
  assert.equal(bundle.nodeConfigs.omega?.displayName, '乙地');
});

test('Slice 2 bridge fixture builds a 24-node runtime bundle through the same path', () => {
  const presentation = {
    schemaVersion: 1,
    id: 'fixture-grid-24.visual',
    mapRef: GRID_24_MAP.id,
    themeRef: 'fixture',
    nodes: GRID_24_MAP.nodes.map((node, index) => ({
      nodeRef: node.id,
      x: (index % 6) * 100,
      y: Math.floor(index / 6) * 100,
    })),
  } as const;
  const first = GRID_24_MAP.nodes[0]?.id;
  const last = GRID_24_MAP.nodes.at(-1)?.id;
  assert.ok(first && last);
  const scenario = {
    schemaVersion: 1,
    id: 'fixture-grid-24.scenario',
    rulesVersion: GRID_24_MAP.rulesVersion,
    mapRef: GRID_24_MAP.id,
    mapPresentationRef: presentation.id,
    playerFactionRef: 'red',
    turnOrder: ['red', 'blue'],
    factions: [
      { id: 'red', displayName: '红方', controller: 'player', headquartersNodeRef: first, supplyNodeRef: first },
      { id: 'blue', displayName: '蓝方', controller: 'ai', headquartersNodeRef: last, supplyNodeRef: last },
    ],
    nodeRules: GRID_24_MAP.nodes.map((node, index) => ({
      nodeRef: node.id,
      displayName: `桥接节点 ${index + 1}`,
      strategicValue: 1,
      goldIncome: 0,
      population: index === 0 || index === 23 ? 5 : 0,
      productionSlots: index === 0 || index === 23 ? 1 : 0,
    })),
    initialState: {
      nodeControls: [{ nodeRef: first, factionRef: 'red' }, { nodeRef: last, factionRef: 'blue' }],
      standardDeployments: [{ nodeRef: first, factionRef: 'red', cardIds: 14 }, { nodeRef: last, factionRef: 'blue', cardIds: 14 }],
      allUnitsDeployments: [{ nodeRef: first, factionRef: 'red', cardIds: 14 }, { nodeRef: last, factionRef: 'blue', cardIds: 14 }],
    },
  } as const;
  const bundle = buildRuntimeMapBundle(GRID_24_MAP, presentation, scenario);
  assert.equal(Object.keys(bundle.nodeConfigs).length, 24);
  assert.equal(bundle.edges.length, 38);
  assert.equal(bundle.mapIndexes.adjacencyByNode[first]?.length, 2);
  assert.equal(bundle.nodeConfigs[last]?.kind, 'field');
});

test('Slice 2 scenario validator rejects missing node coverage and invalid turn order', () => {
  const mapResult = validateMapDefinition(DEMO_1_MAP_AUTHORING, DEMO_1_ENCOUNTER_BINDING);
  if (!mapResult.ok) throw new Error(JSON.stringify(mapResult.issues));
  const result = validateWarlordScenario({
    ...DEMO_1_SCENARIO_AUTHORING,
    turnOrder: ['blue', 'red'],
    nodeRules: DEMO_1_SCENARIO_AUTHORING.nodeRules.slice(1),
  }, mapResult.definition, DEMO_1_MAP_PRESENTATION.id);
  assert.equal(result.ok, false);
  if (result.ok) throw new Error('Expected invalid scenario.');
  const reasons = new Set(result.issues.map((issue) => issue.reasonCode));
  assert.equal(reasons.has('turn_order_mismatch'), true);
  assert.equal(reasons.has('coverage_mismatch'), true);
});
