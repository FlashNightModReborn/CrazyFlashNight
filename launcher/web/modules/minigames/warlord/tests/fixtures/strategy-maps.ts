import {
  DEMO_1_MAP_AUTHORING,
  DEMO_1_MAP_PRESENTATION,
} from '../../src/data/demo1.js';
import { DEMO_1_ENCOUNTER } from '../../src/data/encounter.js';
import type {
  MapDefinitionAuthoringV1,
  MapEdgeAuthoringV1,
  MapNodeAuthoringV1,
  MapPresentationDefinitionV1,
} from '../../src/strategy/definitions.js';

export const DEMO_9_MAP = DEMO_1_MAP_AUTHORING;
export const DEMO_DESERT_PRESENTATION = DEMO_1_MAP_PRESENTATION;
export const DEMO_TUNDRA_PRESENTATION = {
  ...DEMO_1_MAP_PRESENTATION,
  id: 'demo-nine-node.tundra',
  themeRef: 'tundra',
} as const satisfies MapPresentationDefinitionV1;

function padded(value: number): string {
  return value.toString().padStart(2, '0');
}

export function createGridMapFixture(
  columns: number,
  rows: number,
): MapDefinitionAuthoringV1 & {
  readonly nodes: readonly MapNodeAuthoringV1[];
  readonly edges: readonly MapEdgeAuthoringV1[];
} {
  if (!Number.isInteger(columns) || !Number.isInteger(rows) || columns < 1 || rows < 1) {
    throw new Error('Grid fixture dimensions must be positive integers.');
  }
  const nodes: MapNodeAuthoringV1[] = [];
  const edges: MapEdgeAuthoringV1[] = [];
  const nodeId = (row: number, column: number): string => (
    `n-r${padded(row)}-c${padded(column)}`
  );

  for (let row = 0; row < rows; row += 1) {
    for (let column = 0; column < columns; column += 1) {
      nodes.push(Object.freeze({
        id: nodeId(row, column),
        kind: 'field',
        garrisonCapacity: 6,
        attackWidth: 3,
        defenseBonus: 0,
        nodeAPBonus: 0,
        encounterProfileRef: 'encounter.far',
      }));
      if (column > 0) {
        edges.push(Object.freeze({
          id: `edge.h-r${padded(row)}-c${padded(column - 1)}`,
          a: nodeId(row, column - 1),
          b: nodeId(row, column),
        }));
      }
      if (row > 0) {
        edges.push(Object.freeze({
          id: `edge.v-r${padded(row - 1)}-c${padded(column)}`,
          a: nodeId(row - 1, column),
          b: nodeId(row, column),
        }));
      }
    }
  }

  return Object.freeze({
    schemaVersion: 1,
    id: `fixture-grid-${columns * rows}`,
    rulesVersion: 'fixture-grid.v1',
    encounterDefinitionRef: DEMO_1_ENCOUNTER.id,
    nodes: Object.freeze(nodes),
    edges: Object.freeze(edges),
  });
}

export const GRID_24_MAP = createGridMapFixture(6, 4);
export const GRID_96_MAP = createGridMapFixture(12, 8);
export const GRID_128_MAP = createGridMapFixture(16, 8);
