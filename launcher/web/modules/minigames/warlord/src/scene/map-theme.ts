import type { FactionId } from '../core/types.js';

export type MapThemeId = 'desert' | 'tundra';

export interface FactionVisualStyle {
  base: number;
  accent: number;
  edge: number;
  beacon: number;
  markerIndex: 0 | 1 | 2 | 3;
  shortMark: string;
}

const FACTION_STYLE_PALETTE: readonly FactionVisualStyle[] = Object.freeze([
  { base: 0xa64331, accent: 0xd95a3e, edge: 0xf0a17e, beacon: 0xff6c4f, markerIndex: 0, shortMark: '我' },
  { base: 0x2f6f91, accent: 0x4d9bc5, edge: 0x8fd6f1, beacon: 0x69b8e8, markerIndex: 1, shortMark: '甲' },
  { base: 0x47724f, accent: 0x6ba575, edge: 0xb0dab3, beacon: 0x85cf91, markerIndex: 2, shortMark: '独' },
  { base: 0x79558d, accent: 0xa577bd, edge: 0xd8b3e8, beacon: 0xc291dc, markerIndex: 3, shortMark: '乙' },
  { base: 0x9a6b28, accent: 0xc8953e, edge: 0xf0ca80, beacon: 0xe8b657, markerIndex: 0, shortMark: '戊' },
  { base: 0x376e6d, accent: 0x52a09e, edge: 0x99d6d2, beacon: 0x6fc5c1, markerIndex: 1, shortMark: '己' },
]);

const DEMO_FACTION_STYLE_INDEX: Readonly<Record<string, number>> = Object.freeze({
  red: 0,
  blue: 1,
  player: 0,
  'boss-pact-a': 1,
  'boss-independent': 2,
  'boss-pact-b': 3,
});

function stableFactionHash(factionId: string): number {
  let hash = 2166136261;
  for (let index = 0; index < factionId.length; index += 1) {
    hash ^= factionId.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

/**
 * Opaque faction ids receive deterministic, non-order-dependent visuals.
 * Demo 1 keeps its historical red/blue palette while Demo 2 has four distinct
 * colors and line patterns. The marker index and short mark are deliberately
 * independent of hue so the map does not rely on colour recognition alone.
 */
export function factionVisualStyle(factionId: FactionId): FactionVisualStyle {
  const knownIndex = DEMO_FACTION_STYLE_INDEX[factionId];
  const index = knownIndex ?? (stableFactionHash(factionId) % FACTION_STYLE_PALETTE.length);
  const source = FACTION_STYLE_PALETTE[index]!;
  if (knownIndex !== undefined) return source;
  const normalized = factionId.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
  return { ...source, shortMark: normalized.slice(0, 2) || source.shortMark };
}

export interface MapTheme {
  id: MapThemeId;
  label: string;
  theaterLabel: string;
  background: number;
  fog: number;
  fogNear: number;
  fogFar: number;
  exposure: number;
  skyLight: number;
  groundLight: number;
  skyIntensity: number;
  sunLight: number;
  sunIntensity: number;
  rimLight: number;
  rimIntensity: number;
  slab: number;
  terrainHue: number;
  terrainSaturation: number;
  terrainLightness: number;
  gridCenter: number;
  gridLine: number;
  contour: number;
  routeBase: number;
  route: number;
  neutralNode: number;
  neutralBeacon: number;
  grainRgb: readonly [number, number, number];
  grainLine: string;
}

export const MAP_THEMES: Record<MapThemeId, MapTheme> = {
  desert: {
    id: 'desert',
    label: '沙漠沙盘',
    theaterLabel: '沙漠战区',
    background: 0x15110c,
    fog: 0x15110c,
    fogNear: 19,
    fogFar: 36,
    exposure: 0.92,
    skyLight: 0xffe6b0,
    groundLight: 0x261b12,
    skyIntensity: 1.1,
    sunLight: 0xffd58c,
    sunIntensity: 2.5,
    rimLight: 0x5d8ba0,
    rimIntensity: 0.7,
    slab: 0x2c2419,
    terrainHue: 0.092,
    terrainSaturation: 0.46,
    terrainLightness: 0.31,
    gridCenter: 0x725b34,
    gridLine: 0x5c4c32,
    contour: 0xe3c07c,
    routeBase: 0x493c28,
    route: 0xd7bb7d,
    neutralNode: 0x85744f,
    neutralBeacon: 0xe4cc98,
    grainRgb: [244, 235, 214],
    grainLine: '#8f6d3e',
  },
  tundra: {
    id: 'tundra',
    label: '冻原预览',
    theaterLabel: '冻原战区预览',
    background: 0x0a1216,
    fog: 0x0a1216,
    fogNear: 20,
    fogFar: 38,
    exposure: 0.88,
    skyLight: 0xd8edf0,
    groundLight: 0x132026,
    skyIntensity: 1.0,
    sunLight: 0xeaf7f5,
    sunIntensity: 2.15,
    rimLight: 0x68a9c2,
    rimIntensity: 0.9,
    slab: 0x172328,
    terrainHue: 0.51,
    terrainSaturation: 0.13,
    terrainLightness: 0.39,
    gridCenter: 0x789398,
    gridLine: 0x587278,
    contour: 0xb9d7d8,
    routeBase: 0x35474c,
    route: 0xa8c9c7,
    neutralNode: 0x65777a,
    neutralBeacon: 0xc6dddc,
    grainRgb: [229, 237, 235],
    grainLine: '#688388',
  },
};

export function normalizeMapTheme(value: unknown): MapThemeId {
  return value === 'tundra' ? 'tundra' : 'desert';
}
