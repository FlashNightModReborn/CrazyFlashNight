import type { GameState, NodeId, NodeKind, PieceState } from '../core/types.js';
import { getCardDefinition } from '../data/cards.js';
import {
  getEnemyPortraitResolver,
  resolvePortraitDescriptors,
  textureUrlsFor,
} from '../assets/portrait-texture-source.js';
import { projectNodes, type ActionPreview, type NodeProjection } from '../app/presenter.js';
import { GenerationFence } from '../app/lifecycle.js';
import {
  selectMarqueeCandidates,
  type ScreenSelectionCandidate,
} from '../app/selection-policy.js';
import {
  cameraDetailTier,
  cameraLimitsFor,
  cameraZoomPercent,
  clampCameraView,
  computeWorldBounds,
  expandWorldBounds,
  fitCameraToBounds,
  tacticalMarkerScale,
  zoomCameraView,
  type CameraLimits,
  type CameraView,
  type WorldBounds,
} from './camera-policy.js';
import { MAP_THEMES, type MapTheme, type MapThemeId } from './map-theme.js';
import THREE from '../vendor/three-runtime.js';

interface PieceVisual {
  group: any;
  hits: any[];
  identifier: string;
  baseMaterial: any;
  accentMaterial: any;
  badgeMaterial: any;
  portraitMaterial: any;
  selectionMaterial: any;
  materials: any[];
  target: any;
  current: any;
}

interface NodeVisual {
  group: any;
  hit: any;
  bodyMaterial: any;
  capMaterial: any;
  landmarkMaterial: any;
  ringMaterial: any;
  beaconMaterial: any;
}

interface RouteVisual {
  a: NodeId;
  b: NodeId;
  material: any;
}

interface DragState {
  pointerId: number;
  button: number;
  mode: 'pan' | 'marquee';
  additive: boolean;
  startX: number;
  startY: number;
  lastX: number;
  lastY: number;
  moved: boolean;
}

export interface SandtableCameraSnapshot {
  centerX: number;
  centerZ: number;
  zoomPercent: number;
  atFit: boolean;
  detailTier: 'overview' | 'operational' | 'tactical';
  nodeCount: number;
}

export interface SandtableOptions {
  reducedMotion: boolean;
  mapTheme: MapThemeId;
  onNodePicked(nodeId: NodeId): void;
  onPiecePicked(pieceId: string, additive: boolean): void;
  onNodeDoublePicked(nodeId: NodeId): void;
  onMarqueeSelected(selection: {
    nodeId: NodeId | null;
    pieceIds: string[];
    ignoredCount: number;
    additive: boolean;
  }): void;
  onEmptyPicked(): void;
  onCameraChanged?(snapshot: SandtableCameraSnapshot): void;
  onError(message: string): void;
}

function deterministicHeight(x: number, z: number): number {
  return Math.sin(x * 1.17 + z * 0.41) * 0.13
    + Math.cos(z * 1.43 - x * 0.23) * 0.09
    + Math.sin((x + z) * 2.7) * 0.025;
}

function deterministicShade(x: number, z: number): number {
  return Math.sin(x * 0.37 + z * 0.83) * 0.035
    + Math.cos(x * 1.43 - z * 0.29) * 0.018;
}

function ownerColor(owner: 'red' | 'blue' | null, neutralColor: number): number {
  return owner === 'red' ? 0xa64331 : owner === 'blue' ? 0x2f6f91 : neutralColor;
}

function landmarkColor(owner: 'red' | 'blue' | null, theme: MapTheme): number {
  return new THREE.Color(ownerColor(owner, theme.neutralNode))
    .lerp(new THREE.Color(theme.neutralBeacon), owner ? 0.2 : 0.28)
    .getHex();
}

function makeFallbackTexture(identifier: string): any {
  const canvas = document.createElement('canvas');
  canvas.width = 128;
  canvas.height = 160;
  const context = canvas.getContext('2d');
  if (!context) return null;
  const gradient = context.createLinearGradient(0, 0, 0, canvas.height);
  gradient.addColorStop(0, '#c7a66a');
  gradient.addColorStop(1, '#3c3020');
  context.fillStyle = gradient;
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.strokeStyle = '#f1d39a';
  context.lineWidth = 5;
  context.strokeRect(5, 5, canvas.width - 10, canvas.height - 10);
  context.fillStyle = '#17130e';
  context.font = '700 30px sans-serif';
  context.textAlign = 'center';
  context.fillText(identifier.replace('敌人-军阀', '').slice(0, 3), 64, 88);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function makeTacticalBadgeTexture(factionId: 'red' | 'blue'): any {
  const canvas = document.createElement('canvas');
  canvas.width = 192;
  canvas.height = 240;
  const context = canvas.getContext('2d');
  if (!context) return null;
  const accent = factionId === 'red' ? '#bd4735' : '#3d82aa';
  const edge = factionId === 'red' ? '#f0a17e' : '#8fd6f1';
  const points: Array<readonly [number, number]> = [
    [22, 16], [170, 16], [184, 34], [178, 180], [96, 228], [14, 180], [8, 34],
  ];
  const traceBadge = (inset = 0): void => {
    context.beginPath();
    points.forEach(([x, y], index) => {
      const px = x < 96 ? x + inset : x - inset;
      const py = y < 120 ? y + inset : y - inset;
      if (index === 0) context.moveTo(px, py);
      else context.lineTo(px, py);
    });
    context.closePath();
  };
  context.save();
  context.shadowColor = 'rgba(0, 0, 0, .72)';
  context.shadowBlur = 13;
  context.shadowOffsetY = 7;
  traceBadge();
  context.fillStyle = '#111318';
  context.fill();
  context.restore();
  traceBadge();
  context.lineJoin = 'bevel';
  context.lineWidth = 10;
  context.strokeStyle = '#211d18';
  context.stroke();
  context.lineWidth = 5;
  context.strokeStyle = accent;
  context.stroke();
  traceBadge(9);
  const panel = context.createLinearGradient(0, 28, 0, 208);
  panel.addColorStop(0, 'rgba(50, 50, 47, .96)');
  panel.addColorStop(0.58, 'rgba(22, 24, 27, .98)');
  panel.addColorStop(1, 'rgba(12, 14, 18, .98)');
  context.fillStyle = panel;
  context.fill();
  context.lineWidth = 2;
  context.strokeStyle = 'rgba(239, 213, 158, .28)';
  context.stroke();
  context.fillStyle = accent;
  context.fillRect(28, 27, 136, 7);
  context.fillStyle = edge;
  context.globalAlpha = 0.86;
  context.fillRect(47, 39, 98, 2);
  context.globalAlpha = 1;
  context.beginPath();
  context.moveTo(65, 198);
  context.lineTo(96, 216);
  context.lineTo(127, 198);
  context.lineTo(117, 194);
  context.lineTo(96, 205);
  context.lineTo(75, 194);
  context.closePath();
  context.fillStyle = accent;
  context.fill();
  for (const [x, y] of [[29, 46], [163, 46], [35, 170], [157, 170]] as Array<readonly [number, number]>) {
    context.beginPath();
    context.arc(x, y, 3, 0, Math.PI * 2);
    context.fillStyle = edge;
    context.fill();
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.minFilter = THREE.LinearFilter;
  texture.magFilter = THREE.LinearFilter;
  return texture;
}

function makePortraitBadgeMaskTexture(): any {
  const canvas = document.createElement('canvas');
  canvas.width = 160;
  canvas.height = 200;
  const context = canvas.getContext('2d');
  if (!context) return null;
  context.fillStyle = '#000';
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.beginPath();
  context.moveTo(22, 9);
  context.lineTo(138, 9);
  context.lineTo(149, 21);
  context.lineTo(143, 157);
  context.lineTo(80, 191);
  context.lineTo(17, 157);
  context.lineTo(11, 21);
  context.closePath();
  context.fillStyle = '#fff';
  context.fill();
  const texture = new THREE.CanvasTexture(canvas);
  texture.minFilter = THREE.LinearFilter;
  texture.magFilter = THREE.LinearFilter;
  return texture;
}

function makeSurfaceGrainTexture(theme: MapTheme): any {
  const canvas = document.createElement('canvas');
  canvas.width = 256;
  canvas.height = 256;
  const context = canvas.getContext('2d');
  if (!context) return null;
  const pixels = context.createImageData(canvas.width, canvas.height);
  let state = 0x4b48524b;
  for (let index = 0; index < pixels.data.length; index += 4) {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    const grain = ((state >>> 24) / 255 - 0.5) * 18;
    pixels.data[index] = theme.grainRgb[0] + grain;
    pixels.data[index + 1] = theme.grainRgb[1] + grain;
    pixels.data[index + 2] = theme.grainRgb[2] + grain;
    pixels.data[index + 3] = 255;
  }
  context.putImageData(pixels, 0, 0);
  context.globalAlpha = 0.12;
  context.strokeStyle = theme.grainLine;
  context.lineWidth = 1;
  for (let row = 0; row < 8; row += 1) {
    context.beginPath();
    for (let x = -16; x <= 272; x += 8) {
      const y = row * 34 + Math.sin((x + row * 17) * 0.055) * 4;
      if (x === -16) context.moveTo(x, y);
      else context.lineTo(x, y);
    }
    context.stroke();
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.wrapS = THREE.RepeatWrapping;
  texture.wrapT = THREE.RepeatWrapping;
  return texture;
}

export class SandtableScene {
  private readonly theme: MapTheme;
  private readonly scene: any;
  private readonly camera: any;
  private readonly renderer: any;
  private readonly marqueeElement: HTMLDivElement;
  private readonly raycaster: any;
  private readonly pointer: any;
  private readonly groundPlane: any;
  private readonly nodeVisuals = new Map<NodeId, NodeVisual>();
  private readonly nodePositions = new Map<NodeId, any>();
  private readonly routeVisuals: RouteVisual[] = [];
  private readonly pieceVisuals = new Map<string, PieceVisual>();
  private readonly portraitTextures = new Map<string, any>();
  private readonly sharedGeometry: any[] = [];
  private readonly sharedMaterials: any[] = [];
  private readonly sharedTextures: any[] = [];
  private readonly landmarkGeometry = new Map<string, any>();
  private readonly pieceBadgeTextures = new Map<'red' | 'blue', any>();
  private readonly textureFence = new GenerationFence();
  private pieceBaseGeometry: any | null = null;
  private pieceCapGeometry: any | null = null;
  private pieceSupportGeometry: any | null = null;
  private pieceShadowGeometry: any | null = null;
  private pieceSelectionGeometry: any | null = null;
  private piecePortraitMaskTexture: any | null = null;
  private resizeObserver: ResizeObserver | null = null;
  private animationFrame: number | null = null;
  private disposed = false;
  private mapInstalled = false;
  private currentState: GameState | null = null;
  private selectedNodeId: NodeId = 'R-HQ';
  private hoveredNodeId: NodeId | null = null;
  private hoveredPieceId: string | null = null;
  private selectedPieceIds = new Set<string>();
  private commandTargets = new Map<NodeId, ActionPreview>();
  private animationStartedAt = 0;
  private viewportAspect = 16 / 9;
  private mapBounds: WorldBounds = computeWorldBounds([]);
  private cameraLimits: CameraLimits = cameraLimitsFor(this.mapBounds, this.viewportAspect);
  private cameraView: CameraView = fitCameraToBounds(this.mapBounds, this.viewportAspect);
  private drag: DragState | null = null;
  private lastPieceTap: { pieceId: string; time: number } | null = null;

  public constructor(
    private readonly container: HTMLElement,
    private readonly options: SandtableOptions,
  ) {
    this.theme = MAP_THEMES[options.mapTheme];
    try {
      this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, powerPreference: 'high-performance' });
    } catch (error) {
      throw new Error(`WebGL 沙盘初始化失败：${error instanceof Error ? error.message : String(error)}`);
    }
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = this.theme.exposure;
    this.renderer.setClearColor(this.theme.background, 1);
    this.renderer.domElement.className = 'warlord-sandtable-canvas';
    this.renderer.domElement.tabIndex = 0;
    this.renderer.domElement.setAttribute('role', 'application');
    this.renderer.domElement.setAttribute('aria-label', '战术沙盘。点击棋子选择，Shift 拖拽框选，点击高亮据点下令；普通拖拽平移，滚轮缩放。');
    this.renderer.domElement.style.touchAction = 'none';
    this.container.append(this.renderer.domElement);
    this.marqueeElement = document.createElement('div');
    this.marqueeElement.className = 'warlord-selection-marquee';
    this.marqueeElement.hidden = true;
    this.marqueeElement.setAttribute('aria-hidden', 'true');
    this.container.append(this.marqueeElement);

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(this.theme.background);
    this.scene.fog = new THREE.Fog(this.theme.fog, 24, 120);
    this.camera = new THREE.OrthographicCamera(-10, 10, 5.4, -5.4, 0.1, 500);
    this.raycaster = new THREE.Raycaster();
    this.pointer = new THREE.Vector2();
    this.groundPlane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);

    this.buildLights();
    this.renderer.domElement.addEventListener('pointerdown', this.onPointerDown);
    this.renderer.domElement.addEventListener('pointermove', this.onPointerMove);
    this.renderer.domElement.addEventListener('pointerup', this.onPointerUp);
    this.renderer.domElement.addEventListener('pointercancel', this.onPointerCancel);
    this.renderer.domElement.addEventListener('wheel', this.onWheel, { passive: false });
    this.renderer.domElement.addEventListener('dblclick', this.onDoubleClick);
    this.renderer.domElement.addEventListener('keydown', this.onKeyDown);
    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(this.container);
    this.resize();
    void this.loadPortraitTextures();
  }

  private buildLights(): void {
    const sky = new THREE.HemisphereLight(this.theme.skyLight, this.theme.groundLight, this.theme.skyIntensity);
    const sun = new THREE.DirectionalLight(this.theme.sunLight, this.theme.sunIntensity);
    sun.position.set(-10, 16, 7);
    const rim = new THREE.DirectionalLight(this.theme.rimLight, this.theme.rimIntensity);
    rim.position.set(11, 7, -10);
    this.scene.add(sky, sun, rim);
  }

  private installMap(state: GameState): void {
    if (this.mapInstalled) return;
    const projections = projectNodes(state);
    this.container.dataset.mapTheme = this.theme.id;
    this.container.dataset.nodeKinds = Array.from(new Set(projections.map((node) => node.kind))).sort().join(',');
    this.container.dataset.landmarkCount = String(projections.length);
    this.mapBounds = computeWorldBounds(projections);
    const terrainPadding = Math.max(3.8, Math.min(10, Math.max(this.mapBounds.width, this.mapBounds.height) * 0.19));
    const terrainPaddingX = Math.max(5.2, terrainPadding);
    this.buildTerrain(computeWorldBounds([
      { x: this.mapBounds.minX - terrainPaddingX, z: this.mapBounds.minZ - terrainPadding * 1.28 },
      { x: this.mapBounds.maxX + terrainPaddingX, z: this.mapBounds.maxZ + terrainPadding * 1.28 },
    ]));
    this.buildRoutesAndNodes(state, projections);
    this.mapInstalled = true;
    this.recomputeCameraLimits(true);
  }

  private buildTerrain(bounds: WorldBounds): void {
    const slabGeometry = new THREE.BoxGeometry(bounds.width + 0.7, 0.42, bounds.height + 0.7);
    const slabMaterial = new THREE.MeshStandardMaterial({
      color: this.theme.slab,
      roughness: 0.9,
      metalness: 0.22,
    });
    const slab = new THREE.Mesh(slabGeometry, slabMaterial);
    slab.position.set(bounds.centerX, -0.48, bounds.centerZ);
    this.scene.add(slab);
    this.sharedGeometry.push(slabGeometry);
    this.sharedMaterials.push(slabMaterial);

    const segmentsX = Math.min(128, Math.max(36, Math.ceil(bounds.width * 3.5)));
    const segmentsZ = Math.min(96, Math.max(24, Math.ceil(bounds.height * 3.5)));
    const geometry = new THREE.PlaneGeometry(bounds.width, bounds.height, segmentsX, segmentsZ);
    const positions = geometry.attributes.position;
    const colors: number[] = [];
    const color = new THREE.Color();
    for (let index = 0; index < positions.count; index += 1) {
      const worldX = positions.getX(index) + bounds.centerX;
      const worldZ = -positions.getY(index) + bounds.centerZ;
      positions.setZ(index, deterministicHeight(worldX, worldZ));
      color.setHSL(
        this.theme.terrainHue,
        this.theme.terrainSaturation,
        this.theme.terrainLightness + deterministicShade(worldX, worldZ),
      );
      colors.push(color.r, color.g, color.b);
    }
    geometry.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
    positions.needsUpdate = true;
    geometry.computeVertexNormals();
    const material = new THREE.MeshStandardMaterial({
      vertexColors: true,
      roughness: 0.97,
      metalness: 0.01,
    });
    const surfaceTexture = makeSurfaceGrainTexture(this.theme);
    if (surfaceTexture) {
      surfaceTexture.repeat.set(Math.max(1, bounds.width / 5.2), Math.max(1, bounds.height / 5.2));
      surfaceTexture.anisotropy = Math.min(4, this.renderer.capabilities.getMaxAnisotropy());
      material.map = surfaceTexture;
      this.sharedTextures.push(surfaceTexture);
    }
    const terrain = new THREE.Mesh(geometry, material);
    terrain.rotation.x = -Math.PI / 2;
    terrain.position.set(bounds.centerX, 0.1, bounds.centerZ);
    this.scene.add(terrain);
    this.sharedGeometry.push(geometry);
    this.sharedMaterials.push(material);

    const gridSize = Math.max(bounds.width, bounds.height);
    const grid = new THREE.GridHelper(
      gridSize,
      Math.min(36, Math.max(16, Math.ceil(gridSize / 1.25))),
      this.theme.gridCenter,
      this.theme.gridLine,
    );
    grid.position.set(bounds.centerX, 0.4, bounds.centerZ);
    grid.scale.set(bounds.width / gridSize, 1, bounds.height / gridSize);
    const gridMaterials = Array.isArray(grid.material) ? grid.material : [grid.material];
    for (const entry of gridMaterials) {
      entry.transparent = true;
      entry.opacity = 0.11;
      entry.depthWrite = false;
      this.sharedMaterials.push(entry);
    }
    this.sharedGeometry.push(grid.geometry);
    this.scene.add(grid);

    const contourMaterial = new THREE.LineDashedMaterial({
      color: this.theme.contour,
      dashSize: 0.2,
      gapSize: 0.28,
      transparent: true,
      opacity: 0.12,
      depthWrite: false,
    });
    this.sharedMaterials.push(contourMaterial);
    for (let row = 1; row < 8; row += 1) {
      const z = bounds.minZ + (bounds.height * row) / 8;
      const points = Array.from({ length: 65 }, (_, index) => {
        const x = bounds.minX + (bounds.width * index) / 64;
        return new THREE.Vector3(x, deterministicHeight(x, z) + 0.15, z);
      });
      const contourGeometry = new THREE.BufferGeometry().setFromPoints(points);
      const contour = new THREE.Line(contourGeometry, contourMaterial);
      contour.computeLineDistances();
      this.scene.add(contour);
      this.sharedGeometry.push(contourGeometry);
    }
  }

  private getLandmarkGeometry(key: string, create: () => any): any {
    const existing = this.landmarkGeometry.get(key);
    if (existing) return existing;
    const geometry = create();
    this.landmarkGeometry.set(key, geometry);
    this.sharedGeometry.push(geometry);
    return geometry;
  }

  private addLandmarkMesh(
    group: any,
    key: string,
    create: () => any,
    material: any,
    position: readonly [number, number, number],
    rotation?: readonly [number, number, number],
  ): any {
    const mesh = new THREE.Mesh(this.getLandmarkGeometry(key, create), material);
    mesh.position.set(...position);
    if (rotation) mesh.rotation.set(...rotation);
    group.add(mesh);
    return mesh;
  }

  private createNodeLandmark(kind: NodeKind, material: any, signalMaterial: any): any {
    const landmark = new THREE.Group();
    if (kind === 'hq') {
      this.addLandmarkMesh(landmark, 'hq-bunker', () => new THREE.BoxGeometry(0.62, 0.28, 0.5), material, [0, 0.34, 0]);
      this.addLandmarkMesh(landmark, 'hq-roof', () => new THREE.ConeGeometry(0.43, 0.24, 4), material, [0, 0.59, 0], [0, Math.PI / 4, 0]);
      this.addLandmarkMesh(landmark, 'thin-mast', () => new THREE.CylinderGeometry(0.025, 0.035, 0.4, 6), signalMaterial, [0.2, 0.86, 0]);
      this.addLandmarkMesh(landmark, 'signal-tip', () => new THREE.SphereGeometry(0.065, 8, 6), signalMaterial, [0.2, 1.08, 0]);
    } else if (kind === 'supply') {
      this.addLandmarkMesh(landmark, 'supply-crate', () => new THREE.BoxGeometry(0.34, 0.28, 0.32), material, [-0.23, 0.34, 0.04]);
      this.addLandmarkMesh(landmark, 'supply-crate', () => new THREE.BoxGeometry(0.34, 0.28, 0.32), material, [0.17, 0.34, -0.08]);
      this.addLandmarkMesh(landmark, 'supply-small-crate', () => new THREE.BoxGeometry(0.3, 0.23, 0.28), material, [0.02, 0.59, 0.02]);
      this.addLandmarkMesh(landmark, 'thin-mast', () => new THREE.CylinderGeometry(0.025, 0.035, 0.4, 6), signalMaterial, [-0.36, 0.66, -0.12]);
    } else if (kind === 'economy') {
      this.addLandmarkMesh(landmark, 'economy-tank', () => new THREE.CylinderGeometry(0.18, 0.2, 0.5, 10), material, [-0.2, 0.44, 0]);
      this.addLandmarkMesh(landmark, 'economy-tank', () => new THREE.CylinderGeometry(0.18, 0.2, 0.5, 10), material, [0.23, 0.44, 0.04]);
      this.addLandmarkMesh(landmark, 'economy-pipe', () => new THREE.BoxGeometry(0.52, 0.055, 0.065), material, [0.02, 0.63, 0]);
    } else if (kind === 'choke') {
      this.addLandmarkMesh(landmark, 'choke-tower', () => new THREE.BoxGeometry(0.24, 0.5, 0.34), material, [-0.31, 0.43, 0]);
      this.addLandmarkMesh(landmark, 'choke-tower', () => new THREE.BoxGeometry(0.24, 0.5, 0.34), material, [0.31, 0.43, 0]);
      this.addLandmarkMesh(landmark, 'choke-gate', () => new THREE.BoxGeometry(0.42, 0.09, 0.13), material, [0, 0.65, 0]);
    } else if (kind === 'command') {
      this.addLandmarkMesh(landmark, 'command-mast', () => new THREE.CylinderGeometry(0.04, 0.06, 0.54, 8), material, [0, 0.48, 0]);
      this.addLandmarkMesh(landmark, 'command-dish', () => new THREE.CylinderGeometry(0.4, 0.08, 0.09, 14), material, [0, 0.79, 0], [0, 0, -0.58]);
      this.addLandmarkMesh(landmark, 'command-ring', () => new THREE.TorusGeometry(0.23, 0.025, 5, 20), signalMaterial, [0, 0.31, 0], [Math.PI / 2, 0, 0]);
    } else {
      this.addLandmarkMesh(landmark, 'depot-tent', () => new THREE.ConeGeometry(0.4, 0.34, 4), material, [-0.12, 0.42, 0], [0, Math.PI / 4, 0]);
      this.addLandmarkMesh(landmark, 'depot-crate', () => new THREE.BoxGeometry(0.26, 0.22, 0.25), material, [0.34, 0.32, 0.1]);
      this.addLandmarkMesh(landmark, 'thin-mast', () => new THREE.CylinderGeometry(0.025, 0.035, 0.4, 6), signalMaterial, [-0.38, 0.64, -0.08]);
    }
    return landmark;
  }

  private buildRoutesAndNodes(state: GameState, projections: NodeProjection[]): void {
    for (const projection of projections) {
      this.nodePositions.set(
        projection.nodeId,
        new THREE.Vector3(projection.x, deterministicHeight(projection.x, projection.z) + 0.26, projection.z),
      );
    }

    for (const edge of state.map.edges) {
      const a = this.nodePositions.get(edge.a);
      const b = this.nodePositions.get(edge.b);
      if (!a || !b) continue;
      const midpoint = a.clone().lerp(b, 0.5);
      midpoint.y += 0.16;
      const curve = new THREE.CatmullRomCurve3([a.clone(), midpoint, b.clone()]);
      const points = curve.getPoints(24);
      const baseGeometry = new THREE.BufferGeometry().setFromPoints(points);
      const baseMaterial = new THREE.LineBasicMaterial({
        color: this.theme.routeBase,
        transparent: true,
        opacity: 0.38,
        depthWrite: false,
      });
      const base = new THREE.Line(baseGeometry, baseMaterial);
      base.position.y -= 0.025;
      const geometry = new THREE.BufferGeometry().setFromPoints(points);
      const material = new THREE.LineDashedMaterial({
        color: this.theme.route,
        dashSize: 0.48,
        gapSize: 0.14,
        transparent: true,
        opacity: 0.5,
        depthWrite: false,
      });
      const line = new THREE.Line(geometry, material);
      line.computeLineDistances();
      this.scene.add(base, line);
      this.sharedGeometry.push(baseGeometry, geometry);
      this.sharedMaterials.push(baseMaterial, material);
      this.routeVisuals.push({ a: edge.a, b: edge.b, material });
    }

    const bodyGeometry = new THREE.CylinderGeometry(0.68, 0.84, 0.22, 6);
    const capGeometry = new THREE.CylinderGeometry(0.47, 0.6, 0.09, 6);
    const ringGeometry = new THREE.TorusGeometry(0.9, 0.045, 6, 36);
    const beaconGeometry = new THREE.CylinderGeometry(0.035, 0.055, 0.58, 8);
    this.sharedGeometry.push(bodyGeometry, capGeometry, ringGeometry, beaconGeometry);
    for (const projection of projections) {
      const position = this.nodePositions.get(projection.nodeId);
      if (!position) continue;
      const bodyMaterial = new THREE.MeshStandardMaterial({
        color: ownerColor(projection.ownerFactionId, this.theme.neutralNode),
        emissive: 0x000000,
        roughness: 0.62,
        metalness: 0.34,
      });
      const capMaterial = new THREE.MeshStandardMaterial({
        color: ownerColor(projection.ownerFactionId, this.theme.neutralNode),
        emissive: 0x000000,
        roughness: 0.48,
        metalness: 0.42,
      });
      const landmarkMaterial = new THREE.MeshStandardMaterial({
        color: landmarkColor(projection.ownerFactionId, this.theme),
        emissive: 0x000000,
        roughness: 0.5,
        metalness: 0.24,
      });
      const ringMaterial = new THREE.MeshBasicMaterial({
        color: 0xf2c466,
        transparent: true,
        opacity: 0.2,
        depthWrite: false,
      });
      const beaconMaterial = new THREE.MeshBasicMaterial({
        color: this.theme.neutralBeacon,
        transparent: true,
        opacity: 0.44,
        depthWrite: false,
      });
      this.sharedMaterials.push(bodyMaterial, capMaterial, landmarkMaterial, ringMaterial, beaconMaterial);

      const group = new THREE.Group();
      group.position.copy(position);
      const body = new THREE.Mesh(bodyGeometry, bodyMaterial);
      body.userData.nodeId = projection.nodeId;
      const cap = new THREE.Mesh(capGeometry, capMaterial);
      cap.position.y = 0.14;
      const ring = new THREE.Mesh(ringGeometry, ringMaterial);
      ring.rotation.x = Math.PI / 2;
      ring.position.y = 0.13;
      const beacon = new THREE.Mesh(beaconGeometry, beaconMaterial);
      beacon.position.y = 0.43;
      const landmark = this.createNodeLandmark(projection.kind, landmarkMaterial, beaconMaterial);
      group.add(body, cap, landmark, ring, beacon);
      this.scene.add(group);
      this.nodeVisuals.set(projection.nodeId, {
        group,
        hit: body,
        bodyMaterial,
        capMaterial,
        landmarkMaterial,
        ringMaterial,
        beaconMaterial,
      });
    }
  }

  public update(
    state: GameState,
    selectedNodeId: NodeId,
    selectedPieceIds: string[],
    actionPreviews: ActionPreview[] = [],
  ): void {
    if (this.disposed) return;
    this.currentState = state;
    this.selectedNodeId = selectedNodeId;
    this.selectedPieceIds = new Set(selectedPieceIds);
    this.commandTargets = new Map(actionPreviews.map((preview) => [preview.targetNodeId, preview]));
    this.container.dataset.selectedPieceCount = String(selectedPieceIds.length);
    this.container.dataset.commandTargetCount = String(actionPreviews.length);
    this.container.dataset.legalCommandTargets = actionPreviews
      .filter((preview) => preview.ok)
      .map((preview) => preview.targetNodeId)
      .sort()
      .join(',');
    this.container.dataset.invalidCommandTargets = actionPreviews
      .filter((preview) => !preview.ok)
      .map((preview) => preview.targetNodeId)
      .sort()
      .join(',');
    this.installMap(state);
    this.updateNodes(state);
    this.updatePieces(state);
    this.animationStartedAt = performance.now();
    this.requestRender(true);
  }

  private updateNodes(state: GameState): void {
    for (const projection of projectNodes(state)) {
      const visual = this.nodeVisuals.get(projection.nodeId);
      if (!visual) continue;
      const selected = projection.nodeId === this.selectedNodeId;
      const hovered = projection.nodeId === this.hoveredNodeId;
      const commandTarget = this.commandTargets.get(projection.nodeId);
      const commandPartial = commandTarget?.ok === true
        && commandTarget.actualPieceIds.length < this.selectedPieceIds.size;
      const baseColor = ownerColor(projection.ownerFactionId, this.theme.neutralNode);
      visual.bodyMaterial.color.setHex(baseColor);
      visual.capMaterial.color.setHex(baseColor);
      visual.landmarkMaterial.color.setHex(landmarkColor(projection.ownerFactionId, this.theme));
      const emissive = selected ? 0xc87d24
        : commandTarget?.ok && commandTarget.isBattle ? 0xa93d31
          : commandTarget?.ok ? (commandPartial ? 0xb87928 : 0x3b865b)
            : commandTarget && hovered ? 0x772c27
              : projection.contested ? 0x8a280f : hovered ? 0x5f5234 : 0x000000;
      const intensity = selected ? 0.78
        : commandTarget?.ok ? (hovered ? 0.86 : 0.62)
          : commandTarget && hovered ? 0.52
            : projection.contested ? 0.5 : hovered ? 0.34 : 0;
      visual.bodyMaterial.emissive.setHex(emissive);
      visual.capMaterial.emissive.setHex(emissive);
      visual.landmarkMaterial.emissive.setHex(emissive);
      visual.bodyMaterial.emissiveIntensity = intensity;
      visual.capMaterial.emissiveIntensity = intensity;
      visual.landmarkMaterial.emissiveIntensity = intensity * 0.72;
      visual.ringMaterial.color.setHex(selected ? 0xf2c466
        : commandTarget?.ok && commandTarget.isBattle ? 0xdf665b
          : commandTarget?.ok ? (commandPartial ? 0xe5a64d : 0x78bc73)
            : commandTarget ? 0x9f4f48
              : projection.contested ? 0xe25e42 : 0xf2c466);
      visual.ringMaterial.opacity = selected ? 0.98
        : commandTarget?.ok ? (hovered ? 1 : 0.84)
          : commandTarget ? (hovered ? 0.62 : 0.24)
            : hovered ? 0.62 : projection.contested ? 0.48 : 0.14;
      visual.beaconMaterial.color.setHex(projection.ownerFactionId === 'red' ? 0xff6c4f : projection.ownerFactionId === 'blue' ? 0x69b8e8 : this.theme.neutralBeacon);
      visual.beaconMaterial.opacity = projection.active ? (selected ? 0.95 : 0.58) : 0.2;
      visual.group.userData.active = projection.active;
      visual.group.userData.commandState = commandTarget?.ok
        ? commandTarget.isBattle ? 'attack' : commandPartial ? 'partial' : 'move'
        : commandTarget ? 'invalid' : 'none';
    }
    for (const route of this.routeVisuals) {
      const target = route.a === this.selectedNodeId
        ? this.commandTargets.get(route.b)
        : route.b === this.selectedNodeId ? this.commandTargets.get(route.a) : undefined;
      const relevant = route.a === this.selectedNodeId || route.b === this.selectedNodeId;
      route.material.color.setHex(target?.ok
        ? target.isBattle ? 0xdf665b : 0x78bc73
        : target ? 0x7d4641
          : relevant ? 0xf2c466 : this.theme.route);
      route.material.opacity = target?.ok ? 0.98 : target ? 0.28 : relevant ? 0.94 : 0.46;
    }
    this.updateVisualScale(this.getCameraState().zoomPercent);
  }

  private piecePosition(piece: PieceState, index: number): any {
    const center = (this.nodePositions.get(piece.nodeId) ?? new THREE.Vector3()).clone();
    const formation: Array<readonly [number, number]> = [
      [-0.66, 0.18],
      [-0.22, 0.48],
      [0.22, 0.48],
      [0.66, 0.18],
      [0, -0.52],
    ];
    const slot = formation[index % formation.length] ?? formation[0]!;
    const ring = Math.floor(index / formation.length);
    center.x += slot[0] * (1 + ring * 0.35);
    center.z += slot[1] * (1 + ring * 0.35);
    center.y += 0.22;
    return center;
  }

  private updatePieces(state: GameState): void {
    const alive = new Set(Object.keys(state.pieces));
    for (const [pieceId, visual] of this.pieceVisuals) {
      if (alive.has(pieceId)) continue;
      visual.group.removeFromParent();
      for (const material of new Set(visual.materials)) material.dispose();
      this.pieceVisuals.delete(pieceId);
    }

    const byNode = new Map<NodeId, PieceState[]>();
    for (const piece of Object.values(state.pieces).sort((a, b) => a.pieceId.localeCompare(b.pieceId))) {
      const list = byNode.get(piece.nodeId) ?? [];
      list.push(piece);
      byNode.set(piece.nodeId, list);
    }
    for (const pieces of byNode.values()) {
      pieces.forEach((piece, index) => {
        const target = this.piecePosition(piece, index);
        let visual = this.pieceVisuals.get(piece.pieceId);
        if (!visual) {
          visual = this.createPieceVisual(piece, target);
          this.pieceVisuals.set(piece.pieceId, visual);
        }
        visual.target.copy(target);
        const selected = this.selectedPieceIds.has(piece.pieceId);
        const hovered = piece.pieceId === this.hoveredPieceId;
        visual.baseMaterial.emissive.setHex(selected ? 0xf3c45b : hovered ? 0x8f7442 : 0x000000);
        visual.baseMaterial.emissiveIntensity = selected ? 0.85 : hovered ? 0.5 : 0;
        visual.accentMaterial.emissive.setHex(selected ? 0xf3c45b : hovered ? 0x6f5a34 : 0x000000);
        visual.accentMaterial.emissiveIntensity = selected ? 0.7 : hovered ? 0.36 : 0;
        visual.badgeMaterial.color.setHex(selected ? 0xffedbd : hovered ? 0xfff8e6 : 0xffffff);
        visual.selectionMaterial.opacity = selected ? 0.95 : hovered ? 0.48 : 0.16;
      });
    }
    this.container.dataset.pieceVisualStyle = 'tactical-badge-v1';
    this.container.dataset.pieceBadgeCount = String(this.pieceVisuals.size);
    this.updateVisualScale(this.getCameraState().zoomPercent);
  }

  private updatePieceHighlights(state: GameState): void {
    for (const [pieceId, visual] of this.pieceVisuals) {
      if (!state.pieces[pieceId]) continue;
      const selected = this.selectedPieceIds.has(pieceId);
      const hovered = pieceId === this.hoveredPieceId;
      visual.baseMaterial.emissive.setHex(selected ? 0xf3c45b : hovered ? 0x8f7442 : 0x000000);
      visual.baseMaterial.emissiveIntensity = selected ? 0.85 : hovered ? 0.5 : 0;
      visual.accentMaterial.emissive.setHex(selected ? 0xf3c45b : hovered ? 0x6f5a34 : 0x000000);
      visual.accentMaterial.emissiveIntensity = selected ? 0.7 : hovered ? 0.36 : 0;
      visual.badgeMaterial.color.setHex(selected ? 0xffedbd : hovered ? 0xfff8e6 : 0xffffff);
      visual.selectionMaterial.opacity = selected ? 0.95 : hovered ? 0.48 : 0.16;
    }
  }

  private updateVisualScale(zoomPercent: number): void {
    // Keep operational markers readable without letting them consume the
    // tactical viewport. They still grow slightly on screen as detail rises.
    const nodeCompensation = Math.max(0.52, Math.min(1, Math.sqrt(100 / Math.max(100, zoomPercent))));
    const pieceCompensation = tacticalMarkerScale(zoomPercent);
    for (const [nodeId, visual] of this.nodeVisuals) {
      const selectedScale = nodeId === this.selectedNodeId ? 1.08 : 1;
      const activeScale = visual.group.userData.active === false ? 0.8 : 1;
      visual.group.scale.set(
        nodeCompensation * selectedScale,
        nodeCompensation * activeScale,
        nodeCompensation * selectedScale,
      );
    }
    for (const visual of this.pieceVisuals.values()) {
      visual.group.scale.setScalar(pieceCompensation);
    }
    this.container.dataset.pieceScale = pieceCompensation.toFixed(3);
    this.container.dataset.pieceScreenGrowth = (pieceCompensation * Math.max(1, zoomPercent / 100)).toFixed(3);
    this.container.dataset.pieceScalePolicy = 'progressive-art-detail-v1';
  }

  private createPieceVisual(piece: PieceState, position: any): PieceVisual {
    const group = new THREE.Group();
    if (!this.pieceBaseGeometry) {
      this.pieceBaseGeometry = new THREE.CylinderGeometry(0.25, 0.32, 0.12, 8);
      this.sharedGeometry.push(this.pieceBaseGeometry);
    }
    if (!this.pieceCapGeometry) {
      this.pieceCapGeometry = new THREE.CylinderGeometry(0.22, 0.25, 0.035, 8);
      this.sharedGeometry.push(this.pieceCapGeometry);
    }
    if (!this.pieceSupportGeometry) {
      this.pieceSupportGeometry = new THREE.BoxGeometry(0.11, 0.33, 0.08);
      this.sharedGeometry.push(this.pieceSupportGeometry);
    }
    if (!this.pieceShadowGeometry) {
      this.pieceShadowGeometry = new THREE.CircleGeometry(0.36, 24);
      this.sharedGeometry.push(this.pieceShadowGeometry);
    }
    if (!this.pieceSelectionGeometry) {
      this.pieceSelectionGeometry = new THREE.TorusGeometry(0.35, 0.026, 5, 28);
      this.sharedGeometry.push(this.pieceSelectionGeometry);
    }
    const factionId = piece.factionId === 'blue' ? 'blue' : 'red';
    const baseMaterial = new THREE.MeshStandardMaterial({
      color: factionId === 'red' ? 0x7c271f : 0x214f6d,
      emissive: 0x000000,
      roughness: 0.38,
      metalness: 0.64,
    });
    const accentMaterial = new THREE.MeshStandardMaterial({
      color: factionId === 'red' ? 0xd95a3e : 0x4d9bc5,
      emissive: 0x000000,
      roughness: 0.32,
      metalness: 0.7,
    });
    const shadowMaterial = new THREE.MeshBasicMaterial({
      color: 0x090806,
      transparent: true,
      opacity: 0.34,
      depthWrite: false,
    });
    const shadow = new THREE.Mesh(this.pieceShadowGeometry, shadowMaterial);
    shadow.rotation.x = -Math.PI / 2;
    shadow.position.y = -0.002;
    shadow.renderOrder = 1;
    group.add(shadow);
    const base = new THREE.Mesh(this.pieceBaseGeometry, baseMaterial);
    base.position.y = 0.06;
    base.userData.pieceId = piece.pieceId;
    group.add(base);
    const cap = new THREE.Mesh(this.pieceCapGeometry, accentMaterial);
    cap.position.y = 0.138;
    cap.userData.pieceId = piece.pieceId;
    group.add(cap);
    const support = new THREE.Mesh(this.pieceSupportGeometry, accentMaterial);
    support.position.y = 0.31;
    support.userData.pieceId = piece.pieceId;
    group.add(support);
    const selectionMaterial = new THREE.MeshBasicMaterial({
      color: 0xffd77d,
      transparent: true,
      opacity: 0.16,
      depthWrite: false,
    });
    const selection = new THREE.Mesh(this.pieceSelectionGeometry, selectionMaterial);
    selection.rotation.x = Math.PI / 2;
    selection.position.y = 0.025;
    selection.renderOrder = 2;
    group.add(selection);
    const identifier = getCardDefinition(piece.cardId).identifier;
    const texture = this.portraitTextures.get(identifier) ?? makeFallbackTexture(identifier);
    if (texture && !this.portraitTextures.has(identifier)) this.portraitTextures.set(identifier, texture);
    let badgeTexture = this.pieceBadgeTextures.get(factionId);
    if (!badgeTexture) {
      badgeTexture = makeTacticalBadgeTexture(factionId);
      if (badgeTexture) {
        this.pieceBadgeTextures.set(factionId, badgeTexture);
        this.sharedTextures.push(badgeTexture);
      }
    }
    if (!this.piecePortraitMaskTexture) {
      this.piecePortraitMaskTexture = makePortraitBadgeMaskTexture();
      if (this.piecePortraitMaskTexture) this.sharedTextures.push(this.piecePortraitMaskTexture);
    }
    const badgeMaterial = new THREE.SpriteMaterial({
      map: badgeTexture,
      transparent: true,
      depthTest: true,
      depthWrite: false,
      alphaTest: 0.02,
    });
    const badge = new THREE.Sprite(badgeMaterial);
    badge.position.set(0, 0.59, 0);
    badge.scale.set(0.76, 0.94, 1);
    badge.renderOrder = 5;
    badge.userData.pieceId = piece.pieceId;
    group.add(badge);
    const portraitMaterial = new THREE.SpriteMaterial({
      map: texture,
      alphaMap: this.piecePortraitMaskTexture,
      transparent: true,
      depthTest: true,
      depthWrite: false,
      alphaTest: 0.035,
    });
    const portrait = new THREE.Sprite(portraitMaterial);
    portrait.position.set(0, 0.61, 0.018);
    portrait.scale.set(0.58, 0.72, 1);
    portrait.renderOrder = 6;
    portrait.userData.identifier = identifier;
    portrait.userData.pieceId = piece.pieceId;
    group.add(portrait);
    group.position.copy(position);
    this.scene.add(group);
    return {
      group,
      hits: [base, cap, support, badge, portrait],
      identifier,
      baseMaterial,
      accentMaterial,
      badgeMaterial,
      portraitMaterial,
      selectionMaterial,
      materials: [baseMaterial, accentMaterial, shadowMaterial, selectionMaterial, badgeMaterial, portraitMaterial],
      target: position.clone(),
      current: position.clone(),
    };
  }

  private async loadPortraitTextures(): Promise<void> {
    const resolver = getEnemyPortraitResolver();
    if (!resolver) {
      this.options.onError('正式头像解析器尚未加载，沙盘临时使用识别牌。');
      return;
    }
    const generation = this.textureFence.next();
    try {
      const descriptors = await resolvePortraitDescriptors(resolver);
      for (const [identifier, descriptor] of descriptors) {
        if (!this.textureFence.isCurrent(generation)) return;
        const urls = textureUrlsFor(descriptor);
        let texture: any = null;
        for (const url of urls) {
          try {
            texture = await this.loadTexture(url);
            break;
          } catch {
            // PNG -> SVG -> legacy. Presentation fallback never touches state.
          }
        }
        if (!texture) continue;
        if (!this.textureFence.isCurrent(generation)) {
          texture.dispose();
          return;
        }
        texture.colorSpace = THREE.SRGBColorSpace;
        const previous = this.portraitTextures.get(identifier);
        if (previous) previous.dispose();
        this.portraitTextures.set(identifier, texture);
        for (const visual of this.pieceVisuals.values()) {
          if (visual.identifier !== identifier) continue;
          visual.portraitMaterial.map = texture;
          visual.portraitMaterial.needsUpdate = true;
        }
        this.requestRender();
      }
    } catch (error) {
      if (this.textureFence.isCurrent(generation)) {
        this.options.onError(`头像纹理加载失败：${error instanceof Error ? error.message : String(error)}`);
      }
    }
  }

  private loadTexture(url: string): Promise<any> {
    return new Promise((resolve, reject) => {
      const loader = new THREE.TextureLoader();
      loader.load(url, resolve, undefined, reject);
    });
  }

  private pointerToNdc(clientX: number, clientY: number): boolean {
    const rect = this.renderer.domElement.getBoundingClientRect();
    if (!rect.width || !rect.height) return false;
    this.pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
    this.pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
    return true;
  }

  private screenToGround(clientX: number, clientY: number): any | null {
    if (!this.pointerToNdc(clientX, clientY)) return null;
    this.raycaster.setFromCamera(this.pointer, this.camera);
    return this.raycaster.ray.intersectPlane(this.groundPlane, new THREE.Vector3());
  }

  private pickNode(clientX: number, clientY: number): NodeId | null {
    if (!this.pointerToNdc(clientX, clientY)) return null;
    this.raycaster.setFromCamera(this.pointer, this.camera);
    const hits = this.raycaster.intersectObjects(
      Array.from(this.nodeVisuals.values()).map((visual) => visual.hit),
      false,
    );
    return (hits[0]?.object?.userData?.nodeId as NodeId | undefined) ?? null;
  }

  private pickPiece(clientX: number, clientY: number): string | null {
    if (!this.pointerToNdc(clientX, clientY)) return null;
    this.raycaster.setFromCamera(this.pointer, this.camera);
    const hits = this.raycaster.intersectObjects(
      Array.from(this.pieceVisuals.values()).flatMap((visual) => visual.hits),
      false,
    );
    return (hits[0]?.object?.userData?.pieceId as string | undefined) ?? null;
  }

  private updateHover(clientX: number, clientY: number): void {
    const nextPieceId = this.pickPiece(clientX, clientY);
    const nextNodeId = nextPieceId
      ? this.currentState?.pieces[nextPieceId]?.nodeId ?? null
      : this.pickNode(clientX, clientY);
    const piece = nextPieceId && this.currentState ? this.currentState.pieces[nextPieceId] : null;
    const changed = nextPieceId !== this.hoveredPieceId || nextNodeId !== this.hoveredNodeId;
    this.hoveredPieceId = nextPieceId;
    this.hoveredNodeId = nextNodeId;
    this.container.dataset.hoveredPiece = nextPieceId ?? '';
    this.container.dataset.hoveredPieceFaction = piece?.factionId ?? '';
    this.container.dataset.hoveredNode = nextNodeId ?? '';
    if (changed && this.currentState) {
      this.updateNodes(this.currentState);
      this.updatePieceHighlights(this.currentState);
      this.requestRender();
    }
    const target = nextNodeId ? this.commandTargets.get(nextNodeId) : undefined;
    this.renderer.domElement.style.cursor = piece?.factionId === 'red'
      ? 'pointer'
      : target?.ok ? 'crosshair'
        : target ? 'not-allowed'
          : nextNodeId ? 'pointer' : 'grab';
  }

  private updateMarquee(startX: number, startY: number, endX: number, endY: number): void {
    const bounds = this.container.getBoundingClientRect();
    const left = Math.max(0, Math.min(startX, endX) - bounds.left);
    const top = Math.max(0, Math.min(startY, endY) - bounds.top);
    const right = Math.min(bounds.width, Math.max(startX, endX) - bounds.left);
    const bottom = Math.min(bounds.height, Math.max(startY, endY) - bounds.top);
    this.marqueeElement.hidden = false;
    this.marqueeElement.style.left = `${left}px`;
    this.marqueeElement.style.top = `${top}px`;
    this.marqueeElement.style.width = `${Math.max(0, right - left)}px`;
    this.marqueeElement.style.height = `${Math.max(0, bottom - top)}px`;
  }

  private marqueeCandidates(): ScreenSelectionCandidate[] {
    if (!this.currentState) return [];
    const rect = this.renderer.domElement.getBoundingClientRect();
    this.scene.updateMatrixWorld(true);
    this.camera.updateMatrixWorld(true);
    const candidates: ScreenSelectionCandidate[] = [];
    for (const [pieceId, visual] of this.pieceVisuals) {
      const piece = this.currentState.pieces[pieceId];
      if (!piece) continue;
      const world = new THREE.Vector3(0, 0.59, 0);
      visual.group.localToWorld(world);
      const projected = world.project(this.camera);
      candidates.push({
        pieceId,
        nodeId: piece.nodeId,
        factionId: piece.factionId,
        screenX: rect.left + (projected.x + 1) * rect.width / 2,
        screenY: rect.top + (1 - projected.y) * rect.height / 2,
      });
    }
    return candidates;
  }

  private readonly onPointerDown = (event: PointerEvent): void => {
    if (this.disposed || (event.button !== 0 && event.button !== 1)) return;
    event.preventDefault();
    this.renderer.domElement.focus({ preventScroll: true });
    this.drag = {
      pointerId: event.pointerId,
      button: event.button,
      mode: event.button === 0 && event.shiftKey ? 'marquee' : 'pan',
      additive: event.ctrlKey || event.metaKey,
      startX: event.clientX,
      startY: event.clientY,
      lastX: event.clientX,
      lastY: event.clientY,
      moved: false,
    };
    try { this.renderer.domElement.setPointerCapture(event.pointerId); } catch { /* synthetic QA pointers */ }
  };

  private readonly onPointerMove = (event: PointerEvent): void => {
    if (this.disposed) return;
    if (!this.drag || this.drag.pointerId !== event.pointerId) {
      this.updateHover(event.clientX, event.clientY);
      return;
    }
    const totalDistance = Math.hypot(event.clientX - this.drag.startX, event.clientY - this.drag.startY);
    if (!this.drag.moved && totalDistance >= 4) {
      this.drag.moved = true;
      this.container.classList.add(this.drag.mode === 'marquee' ? 'is-selecting' : 'is-panning');
    }
    if (!this.drag.moved) return;
    if (this.drag.mode === 'marquee') {
      this.drag.lastX = event.clientX;
      this.drag.lastY = event.clientY;
      this.updateMarquee(this.drag.startX, this.drag.startY, event.clientX, event.clientY);
      this.renderer.domElement.style.cursor = 'crosshair';
      return;
    }
    const before = this.screenToGround(this.drag.lastX, this.drag.lastY);
    const after = this.screenToGround(event.clientX, event.clientY);
    this.drag.lastX = event.clientX;
    this.drag.lastY = event.clientY;
    if (!before || !after) return;
    this.cameraView.centerX += before.x - after.x;
    this.cameraView.centerZ += before.z - after.z;
    this.cameraView = clampCameraView(
      this.cameraView,
      this.mapBounds,
      this.viewportAspect,
      this.cameraLimits,
      this.cameraEdgeMargin(),
    );
    this.applyCamera();
  };

  private finishPointer(event: PointerEvent, cancelled: boolean): void {
    if (!this.drag || this.drag.pointerId !== event.pointerId) return;
    const drag = this.drag;
    const click = !cancelled && !drag.moved && drag.button === 0;
    this.drag = null;
    this.container.classList.remove('is-panning');
    this.container.classList.remove('is-selecting');
    this.marqueeElement.hidden = true;
    try { this.renderer.domElement.releasePointerCapture(event.pointerId); } catch { /* synthetic QA pointers */ }
    if (!cancelled && drag.moved && drag.mode === 'marquee') {
      const selection = selectMarqueeCandidates(
        this.marqueeCandidates(),
        { startX: drag.startX, startY: drag.startY, endX: event.clientX, endY: event.clientY },
        this.selectedPieceIds.size > 0 ? this.selectedNodeId : undefined,
      );
      this.container.dataset.marqueeIgnoredCount = String(selection.ignoredCount);
      this.options.onMarqueeSelected({ ...selection, additive: drag.additive });
      this.updateHover(event.clientX, event.clientY);
      return;
    }
    if (click) {
      const pieceId = this.pickPiece(event.clientX, event.clientY);
      if (pieceId) {
        const tapTime = Number.isFinite(event.timeStamp) ? event.timeStamp : performance.now();
        const isDouble = this.lastPieceTap?.pieceId === pieceId && tapTime - this.lastPieceTap.time <= 320;
        this.lastPieceTap = isDouble ? null : { pieceId, time: tapTime };
        if (isDouble) {
          const nodeId = this.currentState?.pieces[pieceId]?.nodeId;
          if (nodeId) this.options.onNodeDoublePicked(nodeId);
        } else {
          this.options.onPiecePicked(pieceId, event.shiftKey || event.ctrlKey || event.metaKey);
        }
      } else {
        this.lastPieceTap = null;
        const nodeId = this.pickNode(event.clientX, event.clientY);
        if (nodeId) this.options.onNodePicked(nodeId);
        else this.options.onEmptyPicked();
      }
    }
    this.updateHover(event.clientX, event.clientY);
  }

  private readonly onPointerUp = (event: PointerEvent): void => this.finishPointer(event, false);
  private readonly onPointerCancel = (event: PointerEvent): void => this.finishPointer(event, true);

  private readonly onWheel = (event: WheelEvent): void => {
    if (this.disposed || !this.mapInstalled) return;
    event.preventDefault();
    const factor = Math.exp(-Math.max(-240, Math.min(240, event.deltaY)) * 0.0018);
    this.zoomAt(factor, event.clientX, event.clientY);
  };

  private readonly onDoubleClick = (event: MouseEvent): void => {
    event.preventDefault();
    if (!this.pickPiece(event.clientX, event.clientY) && !this.pickNode(event.clientX, event.clientY)) {
      this.fitToMap();
    }
  };

  private readonly onKeyDown = (event: KeyboardEvent): void => {
    if (this.disposed || !this.mapInstalled) return;
    const key = event.key.toLowerCase();
    const panStep = this.cameraView.halfHeight * (event.shiftKey ? 0.28 : 0.12);
    let handled = true;
    if (key === '+' || key === '=') this.zoomBy(1.25);
    else if (key === '-' || key === '_') this.zoomBy(0.8);
    else if (key === '0' || key === 'home') this.fitToMap();
    else if (key === 'arrowleft' || key === 'a') this.panBy(-panStep, 0);
    else if (key === 'arrowright' || key === 'd') this.panBy(panStep, 0);
    else if (key === 'arrowup' || key === 'w') this.panBy(0, -panStep);
    else if (key === 'arrowdown' || key === 's') this.panBy(0, panStep);
    else handled = false;
    if (handled) event.preventDefault();
  };

  private cameraEdgeMargin(): number {
    const zoomProgress = Math.max(0, Math.min(1, (cameraZoomPercent(this.cameraView, this.cameraLimits) - 100) / 100));
    const tacticalHalfSpan = Math.max(
      this.cameraView.halfHeight,
      this.cameraView.halfHeight * this.viewportAspect,
    );
    return 1.3 + Math.max(0, tacticalHalfSpan - 1.3) * zoomProgress;
  }

  private recomputeCameraLimits(reset: boolean): void {
    const paddedBounds = expandWorldBounds(this.mapBounds, 1.2);
    this.cameraLimits = cameraLimitsFor(paddedBounds, this.viewportAspect);
    if (reset) this.cameraView = fitCameraToBounds(paddedBounds, this.viewportAspect);
    this.cameraView = clampCameraView(
      this.cameraView,
      this.mapBounds,
      this.viewportAspect,
      this.cameraLimits,
      this.cameraEdgeMargin(),
    );
    this.applyCamera();
  }

  private applyCamera(notify = true): void {
    const halfWidth = this.cameraView.halfHeight * this.viewportAspect;
    this.camera.left = -halfWidth;
    this.camera.right = halfWidth;
    this.camera.top = this.cameraView.halfHeight;
    this.camera.bottom = -this.cameraView.halfHeight;
    this.camera.position.set(this.cameraView.centerX, 12.5, this.cameraView.centerZ + 13.5);
    this.camera.lookAt(this.cameraView.centerX, 0, this.cameraView.centerZ);
    this.camera.updateProjectionMatrix();
    const snapshot = this.getCameraState();
    this.updateVisualScale(snapshot.zoomPercent);
    this.container.dataset.cameraZoom = String(snapshot.zoomPercent);
    this.container.dataset.cameraX = snapshot.centerX.toFixed(3);
    this.container.dataset.cameraZ = snapshot.centerZ.toFixed(3);
    this.container.dataset.cameraFit = snapshot.atFit ? 'true' : 'false';
    this.container.dataset.cameraDetail = snapshot.detailTier;
    if (notify) this.options.onCameraChanged?.(snapshot);
    this.requestRender();
  }

  private zoomAt(factor: number, clientX?: number, clientY?: number): void {
    const anchored = typeof clientX === 'number' && typeof clientY === 'number';
    const before = anchored ? this.screenToGround(clientX, clientY) : null;
    this.cameraView = zoomCameraView(this.cameraView, factor, this.cameraLimits);
    this.applyCamera(false);
    const after = anchored ? this.screenToGround(clientX, clientY) : null;
    if (before && after) {
      this.cameraView.centerX += before.x - after.x;
      this.cameraView.centerZ += before.z - after.z;
    }
    this.cameraView = clampCameraView(
      this.cameraView,
      this.mapBounds,
      this.viewportAspect,
      this.cameraLimits,
      this.cameraEdgeMargin(),
    );
    this.applyCamera();
  }

  public zoomBy(factor: number): void {
    if (!this.mapInstalled || this.disposed) return;
    this.zoomAt(factor);
  }

  public panBy(deltaX: number, deltaZ: number): void {
    if (!this.mapInstalled || this.disposed) return;
    this.cameraView.centerX += deltaX;
    this.cameraView.centerZ += deltaZ;
    this.cameraView = clampCameraView(
      this.cameraView,
      this.mapBounds,
      this.viewportAspect,
      this.cameraLimits,
      this.cameraEdgeMargin(),
    );
    this.applyCamera();
  }

  public fitToMap(notify = true): void {
    if (!this.mapInstalled || this.disposed) return;
    this.cameraView = fitCameraToBounds(expandWorldBounds(this.mapBounds, 1.2), this.viewportAspect);
    this.cameraView = clampCameraView(
      this.cameraView,
      this.mapBounds,
      this.viewportAspect,
      this.cameraLimits,
      this.cameraEdgeMargin(),
    );
    this.applyCamera(notify);
  }

  public focusNode(nodeId: NodeId): void {
    if (!this.mapInstalled || this.disposed) return;
    const point = this.nodePositions.get(nodeId);
    if (!point) return;
    this.cameraView.centerX = point.x;
    this.cameraView.centerZ = point.z;
    this.cameraView.halfHeight = Math.min(this.cameraView.halfHeight, this.cameraLimits.fitHalfHeight / 2.2);
    this.cameraView = clampCameraView(
      this.cameraView,
      this.mapBounds,
      this.viewportAspect,
      this.cameraLimits,
      this.cameraEdgeMargin(),
    );
    this.applyCamera();
  }

  public getCameraState(): SandtableCameraSnapshot {
    const zoomPercent = cameraZoomPercent(this.cameraView, this.cameraLimits);
    return {
      centerX: this.cameraView.centerX,
      centerZ: this.cameraView.centerZ,
      zoomPercent,
      atFit: Math.abs(zoomPercent - 100) <= 2
        && Math.abs(this.cameraView.centerX - this.mapBounds.centerX) < 0.05
        && Math.abs(this.cameraView.centerZ - this.mapBounds.centerZ) < 0.05,
      detailTier: cameraDetailTier(this.nodeVisuals.size, zoomPercent),
      nodeCount: this.nodeVisuals.size,
    };
  }

  public resize(): void {
    if (this.disposed) return;
    const width = Math.max(1, this.container.clientWidth || 720);
    const height = Math.max(1, this.container.clientHeight || 390);
    const previousAspect = this.viewportAspect;
    this.viewportAspect = width / height;
    this.renderer.setSize(width, height, false);
    if (this.mapInstalled && Math.abs(previousAspect - this.viewportAspect) > 0.001) {
      const zoomRatio = this.cameraLimits.fitHalfHeight / Math.max(0.0001, this.cameraView.halfHeight);
      this.cameraLimits = cameraLimitsFor(expandWorldBounds(this.mapBounds, 1.2), this.viewportAspect);
      this.cameraView.halfHeight = this.cameraLimits.fitHalfHeight / Math.max(0.0001, zoomRatio);
      this.cameraView = clampCameraView(
        this.cameraView,
        this.mapBounds,
        this.viewportAspect,
        this.cameraLimits,
        this.cameraEdgeMargin(),
      );
    }
    this.applyCamera();
  }

  private requestRender(animate = false): void {
    if (this.disposed || this.animationFrame !== null) return;
    this.animationFrame = requestAnimationFrame((time) => this.renderFrame(time, animate));
  }

  private renderFrame(time: number, animate: boolean): void {
    this.animationFrame = null;
    if (this.disposed) return;
    let moving = false;
    const duration = this.options.reducedMotion ? 1 : 420;
    const elapsed = Math.max(0, time - this.animationStartedAt);
    const step = Math.min(1, elapsed / duration);
    const eased = 1 - Math.pow(1 - step, 3);
    for (const visual of this.pieceVisuals.values()) {
      if (visual.current.distanceToSquared(visual.target) > 0.0001) {
        visual.current.lerp(visual.target, eased);
        visual.group.position.copy(visual.current);
        moving = step < 1;
        if (step >= 1) visual.current.copy(visual.target);
      }
    }
    this.renderer.render(this.scene, this.camera);
    if ((animate || moving) && moving) this.requestRender(true);
  }

  public dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.textureFence.dispose();
    if (this.animationFrame !== null) cancelAnimationFrame(this.animationFrame);
    this.animationFrame = null;
    this.resizeObserver?.disconnect();
    this.resizeObserver = null;
    this.renderer.domElement.removeEventListener('pointerdown', this.onPointerDown);
    this.renderer.domElement.removeEventListener('pointermove', this.onPointerMove);
    this.renderer.domElement.removeEventListener('pointerup', this.onPointerUp);
    this.renderer.domElement.removeEventListener('pointercancel', this.onPointerCancel);
    this.renderer.domElement.removeEventListener('wheel', this.onWheel);
    this.renderer.domElement.removeEventListener('dblclick', this.onDoubleClick);
    this.renderer.domElement.removeEventListener('keydown', this.onKeyDown);
    this.container.classList.remove('is-panning');
    this.container.classList.remove('is-selecting');
    this.marqueeElement.remove();
    for (const visual of this.pieceVisuals.values()) {
      for (const material of new Set(visual.materials)) material.dispose();
    }
    this.pieceVisuals.clear();
    for (const geometry of new Set(this.sharedGeometry)) geometry.dispose?.();
    for (const material of new Set(this.sharedMaterials)) material.dispose?.();
    for (const texture of new Set(this.sharedTextures)) texture.dispose?.();
    for (const texture of new Set(this.portraitTextures.values())) texture.dispose?.();
    this.portraitTextures.clear();
    this.renderer.renderLists?.dispose?.();
    this.renderer.setAnimationLoop?.(null);
    this.renderer.dispose();
    this.renderer.forceContextLoss?.();
    this.renderer.domElement.remove();
    this.nodeVisuals.clear();
    this.nodePositions.clear();
    this.routeVisuals.splice(0);
  }
}
