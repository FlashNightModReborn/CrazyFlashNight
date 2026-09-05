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

export interface ActionCameraFollowOptions {
  aspect: number;
  reducedMotion: boolean;
  comfortRatio?: number;
}

export class ActionCameraLeaseRegistry {
  private serial = 0;
  private active: { token: number; returnView: CameraView; cancelled: boolean } | null = null;

  public begin(returnView: CameraView): number {
    const token = ++this.serial;
    this.active = { token, returnView: { ...returnView }, cancelled: false };
    return token;
  }

  /**
   * Consecutive AI movements share one presentation lease. The first movement
   * captures the player's complete view; later movements retain both that
   * token and that immutable return target instead of treating the followed
   * camera position as a new player view.
   */
  public beginOrContinue(returnView: CameraView): { token: number; continued: boolean } {
    if (this.active && !this.active.cancelled) {
      return { token: this.active.token, continued: true };
    }
    return { token: this.begin(returnView), continued: false };
  }

  public cancel(token?: number): boolean {
    if (!this.active || (token !== undefined && this.active.token !== token)) return false;
    this.active.cancelled = true;
    return true;
  }

  public returnView(token: number): CameraView | null {
    if (!this.active || this.active.token !== token || this.active.cancelled) return null;
    return { ...this.active.returnView };
  }

  public isCancelled(token: number): boolean {
    return this.active?.token === token && this.active.cancelled;
  }

  public release(token: number): boolean {
    if (!this.active || this.active.token !== token) return false;
    this.active = null;
    return true;
  }

  public activeToken(): number | null {
    return this.active?.token ?? null;
  }
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

function closestComfortCenter(
  current: number,
  coordinates: readonly number[],
  comfortableHalfSpan: number,
): number {
  let lower = -Infinity;
  let upper = Infinity;
  for (const coordinate of coordinates) {
    lower = Math.max(lower, coordinate - comfortableHalfSpan);
    upper = Math.min(upper, coordinate + comfortableHalfSpan);
  }
  if (lower <= upper) return Math.min(upper, Math.max(lower, current));

  // An unusually long authored path cannot fit at the player's current zoom.
  // Prefer the command target (the last point) while still moving only as far
  // as necessary to bring that target into the comfort frame.
  const target = coordinates[coordinates.length - 1] ?? current;
  return Math.min(target + comfortableHalfSpan, Math.max(target - comfortableHalfSpan, current));
}

/**
 * Returns a same-zoom camera view that contains an action path inside a central
 * comfort frame. The current center is retained whenever possible; otherwise
 * each axis moves only to the nearest valid boundary. Passive action following
 * is intentionally disabled under reduced-motion instead of snapping.
 */
export function actionCameraViewForPoints(
  view: CameraView,
  points: readonly WorldPoint[],
  options: ActionCameraFollowOptions,
): CameraView {
  if (options.reducedMotion) return { ...view };
  const validPoints = points.filter((point) => Number.isFinite(point.x) && Number.isFinite(point.z));
  if (validPoints.length === 0) return { ...view };

  const aspect = Math.max(0.1, finite(options.aspect, 1));
  const comfortRatio = Math.min(0.9, Math.max(0.4, finite(options.comfortRatio ?? 0.7, 0.7)));
  const halfHeight = Math.max(0.0001, finite(view.halfHeight, 0.5));
  const comfortableHalfHeight = halfHeight * comfortRatio;
  const comfortableHalfWidth = halfHeight * aspect * comfortRatio;
  return {
    centerX: closestComfortCenter(
      finite(view.centerX, 0),
      validPoints.map((point) => point.x),
      comfortableHalfWidth,
    ),
    centerZ: closestComfortCenter(
      finite(view.centerZ, 0),
      validPoints.map((point) => point.z),
      comfortableHalfHeight,
    ),
    halfHeight: view.halfHeight,
  };
}

export function cameraZoomPercent(view: CameraView, limits: CameraLimits): number {
  return Math.round((limits.fitHalfHeight / Math.max(0.0001, view.halfHeight)) * 100);
}

export function tacticalMarkerScale(zoomPercent: number): number {
  const zoomRatio = Math.max(1, finite(zoomPercent, 100) / 100);
  // Overview stays compact, while deliberate close inspection reveals enough
  // portrait art to identify a commander. The cap still prevents a token from
  // consuming the whole tactical viewport at maximum zoom.
  const screenGrowth = Math.min(3.4, Math.pow(zoomRatio, 0.72));
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
