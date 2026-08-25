export interface WorldPoint {
  x: number;
  z: number;
}

export interface WorldBounds {
  minX: number;
  maxX: number;
  minZ: number;
  maxZ: number;
  width: number;
  height: number;
  centerX: number;
  centerZ: number;
}

export interface CameraView {
  centerX: number;
  centerZ: number;
  halfHeight: number;
}

export interface CameraLimits {
  fitHalfHeight: number;
  minHalfHeight: number;
  maxHalfHeight: number;
}

const MIN_SPAN = 1;

function finite(value: number, fallback: number): number {
  return Number.isFinite(value) ? value : fallback;
}

export function computeWorldBounds(points: readonly WorldPoint[]): WorldBounds {
  if (points.length === 0) {
    return {
      minX: -MIN_SPAN / 2,
      maxX: MIN_SPAN / 2,
      minZ: -MIN_SPAN / 2,
      maxZ: MIN_SPAN / 2,
      width: MIN_SPAN,
      height: MIN_SPAN,
      centerX: 0,
      centerZ: 0,
    };
  }
  let minX = Infinity;
  let maxX = -Infinity;
  let minZ = Infinity;
  let maxZ = -Infinity;
  for (const point of points) {
    const x = finite(point.x, 0);
    const z = finite(point.z, 0);
    minX = Math.min(minX, x);
    maxX = Math.max(maxX, x);
    minZ = Math.min(minZ, z);
    maxZ = Math.max(maxZ, z);
  }
  const centerX = (minX + maxX) / 2;
  const centerZ = (minZ + maxZ) / 2;
  const width = Math.max(MIN_SPAN, maxX - minX);
  const height = Math.max(MIN_SPAN, maxZ - minZ);
  return {
    minX: centerX - width / 2,
    maxX: centerX + width / 2,
    minZ: centerZ - height / 2,
    maxZ: centerZ + height / 2,
    width,
    height,
    centerX,
    centerZ,
  };
}

export function expandWorldBounds(bounds: WorldBounds, padding: number): WorldBounds {
  const safePadding = Math.max(0, finite(padding, 0));
  return computeWorldBounds([
    { x: bounds.minX - safePadding, z: bounds.minZ - safePadding },
    { x: bounds.maxX + safePadding, z: bounds.maxZ + safePadding },
  ]);
}

export function fitCameraToBounds(
  bounds: WorldBounds,
  aspect: number,
  paddingScale = 1.16,
): CameraView {
  const safeAspect = Math.max(0.1, finite(aspect, 1));
  const scale = Math.max(1, finite(paddingScale, 1.16));
  const halfHeight = Math.max(bounds.height / 2, bounds.width / (2 * safeAspect)) * scale;
  return {
    centerX: bounds.centerX,
    centerZ: bounds.centerZ,
    halfHeight: Math.max(0.5, halfHeight),
  };
}

export function cameraLimitsFor(bounds: WorldBounds, aspect: number): CameraLimits {
  const fit = fitCameraToBounds(bounds, aspect);
  return {
    fitHalfHeight: fit.halfHeight,
    minHalfHeight: Math.max(0.58, fit.halfHeight * 0.16),
    maxHalfHeight: fit.halfHeight * 1.28,
  };
}

export function clampCameraView(
  view: CameraView,
  bounds: WorldBounds,
  aspect: number,
  limits: CameraLimits,
  edgeMargin = 1.3,
): CameraView {
  const safeAspect = Math.max(0.1, finite(aspect, 1));
  const halfHeight = Math.min(limits.maxHalfHeight, Math.max(limits.minHalfHeight, view.halfHeight));
  const halfWidth = halfHeight * safeAspect;
  const expanded = expandWorldBounds(bounds, Math.max(0, edgeMargin));
  const minCenterX = expanded.minX + halfWidth;
  const maxCenterX = expanded.maxX - halfWidth;
  const minCenterZ = expanded.minZ + halfHeight;
  const maxCenterZ = expanded.maxZ - halfHeight;
  return {
    centerX: minCenterX > maxCenterX
      ? expanded.centerX
      : Math.min(maxCenterX, Math.max(minCenterX, finite(view.centerX, expanded.centerX))),
    centerZ: minCenterZ > maxCenterZ
      ? expanded.centerZ
      : Math.min(maxCenterZ, Math.max(minCenterZ, finite(view.centerZ, expanded.centerZ))),
    halfHeight,
  };
}

export function zoomCameraView(
  view: CameraView,
  zoomFactor: number,
  limits: CameraLimits,
): CameraView {
  const factor = Math.min(4, Math.max(0.25, finite(zoomFactor, 1)));
  return {
    ...view,
    halfHeight: Math.min(limits.maxHalfHeight, Math.max(limits.minHalfHeight, view.halfHeight / factor)),
  };
}

export function cameraZoomPercent(view: CameraView, limits: CameraLimits): number {
  return Math.round((limits.fitHalfHeight / Math.max(0.0001, view.halfHeight)) * 100);
}

export function tacticalMarkerScale(zoomPercent: number): number {
  const zoomRatio = Math.max(1, finite(zoomPercent, 100) / 100);
  // Art remains worth inspecting: screen size follows sqrt(zoom) through the
  // ordinary tactical range, then caps before extreme zoom can bury a node.
  const screenGrowth = Math.min(1.8, Math.sqrt(zoomRatio));
  return Math.min(1, screenGrowth / zoomRatio);
}

export function cameraDetailTier(
  nodeCount: number,
  zoomPercent: number,
): 'overview' | 'operational' | 'tactical' {
  if (nodeCount >= 72 && zoomPercent < 145) return 'overview';
  if (nodeCount >= 28 && zoomPercent < 115) return 'overview';
  if (zoomPercent >= 220) return 'tactical';
  return 'operational';
}
