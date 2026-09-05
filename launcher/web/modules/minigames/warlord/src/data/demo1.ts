import type {
  MapDefinitionAuthoringV1,
  MapPresentationDefinitionV1,
  WarlordScenarioAuthoringV1,
} from '../strategy/definitions.js';
import { RULES_VERSION } from './config.js';
import { DEMO_1_ENCOUNTER } from './encounter.js';

export const DEMO_1_MAP_AUTHORING = {
  schemaVersion: 1,
  id: 'demo-nine-node',
  rulesVersion: RULES_VERSION,
  encounterDefinitionRef: DEMO_1_ENCOUNTER.id,
  nodes: [
    { id: 'R-HQ', kind: 'hq', garrisonCapacity: 5, attackWidth: 3, defenseBonus: 0, nodeAPBonus: 0, encounterProfileRef: 'encounter.near' },
    { id: 'R-Supply', kind: 'supply', garrisonCapacity: 4, attackWidth: 3, defenseBonus: 0, nodeAPBonus: 0, encounterProfileRef: 'encounter.medium' },
    { id: 'R-Economy', kind: 'economy', garrisonCapacity: 3, attackWidth: 3, defenseBonus: 0, nodeAPBonus: 0, encounterProfileRef: 'encounter.medium' },
    { id: 'North-Choke', kind: 'choke', garrisonCapacity: 4, attackWidth: 2, defenseBonus: 0.2, nodeAPBonus: 0, encounterProfileRef: 'encounter.far' },
    { id: 'Center-Command', kind: 'command', garrisonCapacity: 4, attackWidth: 4, defenseBonus: 0, nodeAPBonus: 2, encounterProfileRef: 'encounter.far' },
    { id: 'South-Depot', kind: 'depot', garrisonCapacity: 3, attackWidth: 3, defenseBonus: 0, nodeAPBonus: 0, encounterProfileRef: 'encounter.far' },
    { id: 'B-Economy', kind: 'economy', garrisonCapacity: 3, attackWidth: 3, defenseBonus: 0, nodeAPBonus: 0, encounterProfileRef: 'encounter.medium' },
    { id: 'B-Supply', kind: 'supply', garrisonCapacity: 4, attackWidth: 3, defenseBonus: 0, nodeAPBonus: 0, encounterProfileRef: 'encounter.medium' },
    { id: 'B-HQ', kind: 'hq', garrisonCapacity: 5, attackWidth: 3, defenseBonus: 0, nodeAPBonus: 0, encounterProfileRef: 'encounter.near' },
  ],
  edges: [
    { id: 'edge.01', a: 'R-HQ', b: 'R-Supply' },
    { id: 'edge.02', a: 'R-HQ', b: 'R-Economy' },
    { id: 'edge.03', a: 'R-Supply', b: 'North-Choke' },
    { id: 'edge.04', a: 'R-Supply', b: 'Center-Command' },
    { id: 'edge.05', a: 'R-Economy', b: 'Center-Command' },
    { id: 'edge.06', a: 'R-Economy', b: 'South-Depot' },
    { id: 'edge.07', a: 'North-Choke', b: 'B-Supply' },
    { id: 'edge.08', a: 'Center-Command', b: 'B-Supply' },
    { id: 'edge.09', a: 'Center-Command', b: 'B-Economy' },
    { id: 'edge.10', a: 'South-Depot', b: 'B-Economy' },
    { id: 'edge.11', a: 'B-Supply', b: 'B-HQ' },
    { id: 'edge.12', a: 'B-Economy', b: 'B-HQ' },
  ],
} as const satisfies MapDefinitionAuthoringV1;

export const DEMO_1_MAP_PRESENTATION = {
  schemaVersion: 1,
  id: 'demo-nine-node.desert',
  mapRef: 'demo-nine-node',
  themeRef: 'desert',
  nodes: [
    { nodeRef: 'R-HQ', x: 90, y: 210, visualAnchor: 'left' },
    { nodeRef: 'R-Supply', x: 250, y: 110 },
    { nodeRef: 'R-Economy', x: 250, y: 310 },
    { nodeRef: 'North-Choke', x: 470, y: 70 },
    { nodeRef: 'Center-Command', x: 470, y: 210 },
    { nodeRef: 'South-Depot', x: 470, y: 350 },
    { nodeRef: 'B-Economy', x: 690, y: 310 },
    { nodeRef: 'B-Supply', x: 690, y: 110 },
    { nodeRef: 'B-HQ', x: 850, y: 210, visualAnchor: 'right' },
  ],
} as const satisfies MapPresentationDefinitionV1;

export const DEMO_1_SCENARIO_AUTHORING = {
  schemaVersion: 1,
  id: 'warlord_tutorial_v1',
  rulesVersion: RULES_VERSION,
  mapRef: 'demo-nine-node',
  mapPresentationRef: 'demo-nine-node.desert',
  playerFactionRef: 'red',
  turnOrder: ['red', 'blue'],
  factions: [
    {
      id: 'red',
      displayName: '红方军阀',
      controller: 'player',
      headquartersNodeRef: 'R-HQ',
      supplyNodeRef: 'R-Supply',
    },
    {
      id: 'blue',
      displayName: '蓝方军阀',
      controller: 'ai',
      headquartersNodeRef: 'B-HQ',
      supplyNodeRef: 'B-Supply',
    },
  ],
  nodeRules: [
    { nodeRef: 'R-HQ', displayName: '红方总部', strategicValue: 5, goldIncome: 5, population: 5, productionSlots: 2 },
    { nodeRef: 'R-Supply', displayName: '红方补给', strategicValue: 3, goldIncome: 0, population: 6, productionSlots: 2 },
    { nodeRef: 'R-Economy', displayName: '红方经济', strategicValue: 2, goldIncome: 8, population: 0, productionSlots: 0 },
    { nodeRef: 'North-Choke', displayName: '北部关隘', strategicValue: 1, goldIncome: 0, population: 0, productionSlots: 0 },
    { nodeRef: 'Center-Command', displayName: '中央指挥', strategicValue: 3, goldIncome: 0, population: 0, productionSlots: 0 },
    { nodeRef: 'South-Depot', displayName: '南部军需', strategicValue: 2, goldIncome: 6, population: 0, productionSlots: 0 },
    { nodeRef: 'B-Economy', displayName: '蓝方经济', strategicValue: 2, goldIncome: 8, population: 0, productionSlots: 0 },
    { nodeRef: 'B-Supply', displayName: '蓝方补给', strategicValue: 3, goldIncome: 0, population: 6, productionSlots: 2 },
    { nodeRef: 'B-HQ', displayName: '蓝方总部', strategicValue: 5, goldIncome: 5, population: 5, productionSlots: 2 },
  ],
  initialState: {
    nodeControls: [
      { nodeRef: 'R-HQ', factionRef: 'red' },
      { nodeRef: 'R-Supply', factionRef: 'red' },
      { nodeRef: 'R-Economy', factionRef: 'red' },
      { nodeRef: 'B-Economy', factionRef: 'blue' },
      { nodeRef: 'B-Supply', factionRef: 'blue' },
      { nodeRef: 'B-HQ', factionRef: 'blue' },
    ],
    standardDeployments: [
      { nodeRef: 'R-HQ', factionRef: 'red', cardIds: [14, 14, 12, 13] },
      { nodeRef: 'B-HQ', factionRef: 'blue', cardIds: [14, 14, 12, 13] },
    ],
    allUnitsDeployments: [
      { nodeRef: 'R-Supply', factionRef: 'red', cardIds: [14, 15, 82] },
      { nodeRef: 'R-Economy', factionRef: 'red', cardIds: [12, 13] },
      { nodeRef: 'R-HQ', factionRef: 'red', cardIds: [83, 84, 85] },
      { nodeRef: 'North-Choke', factionRef: 'blue', cardIds: [12, 84] },
      { nodeRef: 'B-Supply', factionRef: 'blue', cardIds: [14, 15, 82, 13] },
      { nodeRef: 'B-HQ', factionRef: 'blue', cardIds: [83, 85] },
    ],
  },
} as const satisfies WarlordScenarioAuthoringV1;
