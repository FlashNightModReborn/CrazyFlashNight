import { getCardDefinition } from '../data/cards.js';
import { getEnemyPortraitResolver, resolvePortraitDescriptors, textureUrlsFor, } from '../assets/portrait-texture-source.js';
import { projectNodes } from '../app/presenter.js';
import { GenerationFence } from '../app/lifecycle.js';
import { selectMarqueeCandidates, } from '../app/selection-policy.js';
import { cameraDetailTier, cameraLimitsFor, cameraZoomPercent, clampCameraView, computeWorldBounds, expandWorldBounds, fitCameraToBounds, tacticalMarkerScale, zoomCameraView, } from './camera-policy.js';
import { MAP_THEMES } from './map-theme.js';
import THREE from '../vendor/three-runtime.js';
function deterministicHeight(x, z) {
    return Math.sin(x * 1.17 + z * 0.41) * 0.13
        + Math.cos(z * 1.43 - x * 0.23) * 0.09
        + Math.sin((x + z) * 2.7) * 0.025;
}
function deterministicShade(x, z) {
    return Math.sin(x * 0.37 + z * 0.83) * 0.035
        + Math.cos(x * 1.43 - z * 0.29) * 0.018;
}
function ownerColor(owner, neutralColor) {
    return owner === 'red' ? 0xa64331 : owner === 'blue' ? 0x2f6f91 : neutralColor;
}
function landmarkColor(owner, theme) {
    return new THREE.Color(ownerColor(owner, theme.neutralNode))
        .lerp(new THREE.Color(theme.neutralBeacon), owner ? 0.2 : 0.28)
        .getHex();
}
// 地标点缀色：在主色基础上向信标色再靠一档，作为屋顶 / 闸门 / 管线等高光构件
function landmarkAccentColor(owner, theme) {
    return new THREE.Color(landmarkColor(owner, theme))
        .lerp(new THREE.Color(theme.neutralBeacon), 0.4)
        .getHex();
}
// 节点顶盖提亮：明度按比例上浮，封顶避免过曝
function liftLightness(hex, factor) {
    const color = new THREE.Color(hex);
    const hsl = { h: 0, s: 0, l: 0 };
    color.getHSL(hsl);
    color.setHSL(hsl.h, hsl.s, Math.min(1, hsl.l * factor));
    return color.getHex();
}
function cssColor(hex, scale) {
    const color = new THREE.Color(hex);
    const channel = (value) => Math.max(0, Math.min(255, Math.round(value * scale * 255)));
    return `rgb(${channel(color.r)}, ${channel(color.g)}, ${channel(color.b)})`;
}
// 正交相机下的全屏背景：上深下暖、近地平线微亮的垂直渐变，色值全部从主题令牌派生
function makeBackdropTexture(theme) {
    const canvas = document.createElement('canvas');
    canvas.width = 512;
    canvas.height = 256;
    const context = canvas.getContext('2d');
    if (!context)
        return null;
    const horizon = new THREE.Color(theme.background).lerp(new THREE.Color(theme.skyLight), 0.16).getHex();
    const foot = new THREE.Color(theme.background).lerp(new THREE.Color(theme.sunLight), 0.1).getHex();
    const gradient = context.createLinearGradient(0, 0, 0, canvas.height);
    gradient.addColorStop(0, cssColor(theme.background, 0.45));
    gradient.addColorStop(0.38, cssColor(horizon, 1));
    gradient.addColorStop(0.58, cssColor(theme.background, 1));
    gradient.addColorStop(1, cssColor(foot, 0.92));
    context.fillStyle = gradient;
    context.fillRect(0, 0, canvas.width, canvas.height);
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    return texture;
}
// 64×32 等距柱状环境图：暖色地平线带 + 暗地面 + 一团太阳亮斑，供 PMREM 预滤波
function makeEnvironmentTexture(theme) {
    const canvas = document.createElement('canvas');
    canvas.width = 64;
    canvas.height = 32;
    const context = canvas.getContext('2d');
    if (!context)
        return null;
    const gradient = context.createLinearGradient(0, 0, 0, canvas.height);
    gradient.addColorStop(0, cssColor(theme.skyLight, 0.5));
    gradient.addColorStop(0.5, cssColor(theme.sunLight, 0.8));
    gradient.addColorStop(0.6, cssColor(theme.groundLight, 2.2));
    gradient.addColorStop(1, cssColor(theme.groundLight, 0.9));
    context.fillStyle = gradient;
    context.fillRect(0, 0, canvas.width, canvas.height);
    const sunSpot = context.createRadialGradient(20, 14, 1, 20, 14, 7);
    sunSpot.addColorStop(0, cssColor(theme.sunLight, 1.6));
    sunSpot.addColorStop(0.45, cssColor(theme.sunLight, 1.05));
    sunSpot.addColorStop(1, 'rgba(0, 0, 0, 0)');
    context.fillStyle = sunSpot;
    context.fillRect(0, 0, canvas.width, canvas.height);
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.mapping = THREE.EquirectangularReflectionMapping;
    return texture;
}
// 行军带箭头纹：纯白 chevron 供材质 color 着色，沿带长方向 RepeatWrapping 重复
function makeRouteMarkTexture() {
    const canvas = document.createElement('canvas');
    canvas.width = 64;
    canvas.height = 64;
    const context = canvas.getContext('2d');
    if (!context)
        return null;
    context.clearRect(0, 0, canvas.width, canvas.height);
    context.strokeStyle = '#ffffff';
    context.lineCap = 'round';
    context.lineJoin = 'round';
    context.lineWidth = 10;
    context.beginPath();
    context.moveTo(16, 12);
    context.lineTo(44, 32);
    context.lineTo(16, 52);
    context.stroke();
    context.globalAlpha = 0.45;
    context.lineWidth = 6;
    context.beginPath();
    context.moveTo(4, 20);
    context.lineTo(20, 32);
    context.lineTo(4, 44);
    context.stroke();
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.wrapS = THREE.RepeatWrapping;
    texture.wrapT = THREE.ClampToEdgeWrapping;
    return texture;
}
function makeFallbackTexture(identifier) {
    const canvas = document.createElement('canvas');
    canvas.width = 128;
    canvas.height = 160;
    const context = canvas.getContext('2d');
    if (!context)
        return null;
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
function makeTacticalBadgeTexture(factionId) {
    const canvas = document.createElement('canvas');
    canvas.width = 192;
    canvas.height = 240;
    const context = canvas.getContext('2d');
    if (!context)
        return null;
    const accent = factionId === 'red' ? '#bd4735' : '#3d82aa';
    const edge = factionId === 'red' ? '#f0a17e' : '#8fd6f1';
    const points = [
        [22, 16], [170, 16], [184, 34], [178, 180], [96, 228], [14, 180], [8, 34],
    ];
    const traceBadge = (inset = 0) => {
        context.beginPath();
        points.forEach(([x, y], index) => {
            const px = x < 96 ? x + inset : x - inset;
            const py = y < 120 ? y + inset : y - inset;
            if (index === 0)
                context.moveTo(px, py);
            else
                context.lineTo(px, py);
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
    for (const [x, y] of [[29, 46], [163, 46], [35, 170], [157, 170]]) {
        context.beginPath();
        context.arc(x, y, 3, 0, Math.PI * 2);
        context.fillStyle = edge;
        context.fill();
    }
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.minFilter = THREE.LinearMipmapLinearFilter;
    texture.magFilter = THREE.LinearFilter;
    return texture;
}
function makePortraitBadgeMaskTexture() {
    const canvas = document.createElement('canvas');
    canvas.width = 160;
    canvas.height = 200;
    const context = canvas.getContext('2d');
    if (!context)
        return null;
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
    texture.minFilter = THREE.LinearMipmapLinearFilter;
    texture.magFilter = THREE.LinearFilter;
    return texture;
}
function makeSurfaceGrainTexture(theme) {
    const canvas = document.createElement('canvas');
    canvas.width = 512;
    canvas.height = 512;
    const context = canvas.getContext('2d');
    if (!context)
        return null;
    const pixels = context.createImageData(canvas.width, canvas.height);
    let state = 0x4b48524b;
    const nextRandom = () => {
        state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
        return (state >>> 24) / 255;
    };
    for (let index = 0; index < pixels.data.length; index += 4) {
        // 主噪点之外再叠一倍 4x 频率、1/4 幅度的细砂砾，全部走同一条确定性 LCG
        const grain = (nextRandom() - 0.5) * 18 + (nextRandom() - 0.5) * 4.5;
        pixels.data[index] = theme.grainRgb[0] + grain;
        pixels.data[index + 1] = theme.grainRgb[1] + grain;
        pixels.data[index + 2] = theme.grainRgb[2] + grain;
        pixels.data[index + 3] = 255;
    }
    context.putImageData(pixels, 0, 0);
    context.strokeStyle = theme.grainLine;
    context.lineWidth = 1;
    const rows = 14;
    for (let row = 0; row < rows; row += 1) {
        // 行距 / 相位 / 透明度抖动，少量行反相，保持波纹不死板
        const jitter = nextRandom() - 0.5;
        const phase = nextRandom() * Math.PI * 2;
        const amplitude = nextRandom() < 0.22 ? -4 : 4;
        context.globalAlpha = 0.08 + nextRandom() * 0.08;
        const baseY = ((row + 0.5) / rows) * canvas.height + jitter * 12;
        context.beginPath();
        for (let x = -16; x <= 528; x += 8) {
            const y = baseY + Math.sin(x * 0.055 + phase) * amplitude;
            if (x === -16)
                context.moveTo(x, y);
            else
                context.lineTo(x, y);
        }
        context.stroke();
    }
    context.globalAlpha = 1;
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.wrapS = THREE.RepeatWrapping;
    texture.wrapT = THREE.RepeatWrapping;
    return texture;
}
export class SandtableScene {
    container;
    options;
    theme;
    scene;
    camera;
    renderer;
    marqueeElement;
    raycaster;
    pointer;
    groundPlane;
    nodeVisuals = new Map();
    nodePositions = new Map();
    routeVisuals = [];
    pieceVisuals = new Map();
    portraitTextures = new Map();
    sharedGeometry = [];
    sharedMaterials = [];
    sharedTextures = [];
    landmarkGeometry = new Map();
    pieceBadgeTextures = new Map();
    textureFence = new GenerationFence();
    pieceBaseGeometry = null;
    pieceCapGeometry = null;
    pieceSupportGeometry = null;
    pieceShadowGeometry = null;
    pieceSelectionGeometry = null;
    piecePortraitMaskTexture = null;
    sunLight = null;
    environmentTarget = null;
    resizeObserver = null;
    animationFrame = null;
    disposed = false;
    mapInstalled = false;
    currentState = null;
    selectedNodeId = 'R-HQ';
    hoveredNodeId = null;
    hoveredPieceId = null;
    selectedPieceIds = new Set();
    commandTargets = new Map();
    // 棋子移动/选择环脉冲窗口的起始帧时间；null = 待下一帧 rAF 时间闩锁（统一帧时钟，见 renderFrame）
    animationStartedAt = null;
    viewportAspect = 16 / 9;
    mapBounds = computeWorldBounds([]);
    cameraLimits = cameraLimitsFor(this.mapBounds, this.viewportAspect);
    cameraView = fitCameraToBounds(this.mapBounds, this.viewportAspect);
    drag = null;
    lastPieceTap = null;
    // 程序性相机运镜：三通道插值快照，拖拽/滚轮入场即取消
    cameraTween = null;
    cameraTweenTimer = null;
    lastLayoutWidth = 0;
    lastLayoutHeight = 0;
    constructor(container, options) {
        this.container = container;
        this.options = options;
        this.theme = MAP_THEMES[options.mapTheme];
        try {
            this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, powerPreference: 'high-performance' });
        }
        catch (error) {
            throw new Error(`WebGL 沙盘初始化失败：${error instanceof Error ? error.message : String(error)}`);
        }
        this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
        this.renderer.outputColorSpace = THREE.SRGBColorSpace;
        this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
        this.renderer.toneMappingExposure = this.theme.exposure;
        this.renderer.shadowMap.enabled = true;
        this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
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
        const backdropTexture = makeBackdropTexture(this.theme);
        if (backdropTexture) {
            this.scene.background = backdropTexture;
            this.sharedTextures.push(backdropTexture);
        }
        else {
            this.scene.background = new THREE.Color(this.theme.background);
        }
        this.scene.fog = new THREE.Fog(this.theme.fog, this.theme.fogNear, this.theme.fogFar);
        // 程序化环境贴图：PMREM 预滤波后交给 scene.environment，生成器与源纹理用毕即弃
        const environmentSource = makeEnvironmentTexture(this.theme);
        if (environmentSource) {
            const pmrem = new THREE.PMREMGenerator(this.renderer);
            this.environmentTarget = pmrem.fromEquirectangular(environmentSource);
            this.scene.environment = this.environmentTarget.texture;
            pmrem.dispose();
            environmentSource.dispose();
        }
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
        this.renderer.domElement.addEventListener('contextmenu', this.onContextMenu);
        this.renderer.domElement.addEventListener('keydown', this.onKeyDown);
        this.resizeObserver = new ResizeObserver(() => this.resize());
        this.resizeObserver.observe(this.container);
        this.resize();
        void this.loadPortraitTextures();
    }
    buildLights() {
        const sky = new THREE.HemisphereLight(this.theme.skyLight, this.theme.groundLight, this.theme.skyIntensity);
        const sun = new THREE.DirectionalLight(this.theme.sunLight, this.theme.sunIntensity);
        sun.position.set(-10, 16, 7);
        sun.castShadow = true;
        sun.shadow.mapSize.set(2048, 2048);
        sun.shadow.camera.left = -16;
        sun.shadow.camera.right = 16;
        sun.shadow.camera.top = 16;
        sun.shadow.camera.bottom = -16;
        sun.shadow.camera.near = 4;
        sun.shadow.camera.far = 44;
        sun.shadow.bias = -0.0005;
        sun.shadow.normalBias = 0.02;
        const rim = new THREE.DirectionalLight(this.theme.rimLight, this.theme.rimIntensity);
        rim.position.set(11, 7, -10);
        this.sunLight = sun;
        this.scene.add(sky, sun, sun.target, rim);
    }
    installMap(state) {
        if (this.mapInstalled)
            return;
        const projections = projectNodes(state);
        this.container.dataset.mapTheme = this.theme.id;
        this.container.dataset.nodeKinds = Array.from(new Set(projections.map((node) => node.kind))).sort().join(',');
        this.container.dataset.landmarkCount = String(projections.length);
        this.mapBounds = computeWorldBounds(projections);
        // 太阳与 shadow camera 跟随地图中心，保证紧凑正交范围覆盖整张沙盘
        if (this.sunLight) {
            this.sunLight.position.set(this.mapBounds.centerX - 10, 16, this.mapBounds.centerZ + 7);
            this.sunLight.target.position.set(this.mapBounds.centerX, 0, this.mapBounds.centerZ);
            this.sunLight.target.updateMatrixWorld();
        }
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
    buildTerrain(bounds) {
        const slabGeometry = new THREE.BoxGeometry(bounds.width + 0.7, 0.42, bounds.height + 0.7);
        const slabMaterial = new THREE.MeshStandardMaterial({
            color: this.theme.slab,
            roughness: 0.9,
            metalness: 0.22,
            envMapIntensity: 0.5,
        });
        const slab = new THREE.Mesh(slabGeometry, slabMaterial);
        slab.position.set(bounds.centerX, -0.48, bounds.centerZ);
        slab.receiveShadow = true;
        this.scene.add(slab);
        this.sharedGeometry.push(slabGeometry);
        this.sharedMaterials.push(slabMaterial);
        const segmentsX = Math.min(128, Math.max(36, Math.ceil(bounds.width * 3.5)));
        const segmentsZ = Math.min(96, Math.max(24, Math.ceil(bounds.height * 3.5)));
        const geometry = new THREE.PlaneGeometry(bounds.width, bounds.height, segmentsX, segmentsZ);
        const positions = geometry.attributes.position;
        const colors = [];
        const color = new THREE.Color();
        for (let index = 0; index < positions.count; index += 1) {
            const worldX = positions.getX(index) + bounds.centerX;
            const worldZ = -positions.getY(index) + bounds.centerZ;
            positions.setZ(index, deterministicHeight(worldX, worldZ));
            color.setHSL(this.theme.terrainHue, this.theme.terrainSaturation, this.theme.terrainLightness + deterministicShade(worldX, worldZ));
            colors.push(color.r, color.g, color.b);
        }
        geometry.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
        positions.needsUpdate = true;
        geometry.computeVertexNormals();
        const material = new THREE.MeshStandardMaterial({
            vertexColors: true,
            roughness: 0.97,
            metalness: 0.01,
            envMapIntensity: 0.35,
        });
        const surfaceTexture = makeSurfaceGrainTexture(this.theme);
        if (surfaceTexture) {
            surfaceTexture.repeat.set(Math.max(1, bounds.width / 5.2), Math.max(1, bounds.height / 5.2));
            surfaceTexture.anisotropy = Math.min(8, this.renderer.capabilities.getMaxAnisotropy());
            material.map = surfaceTexture;
            this.sharedTextures.push(surfaceTexture);
        }
        const terrain = new THREE.Mesh(geometry, material);
        terrain.rotation.x = -Math.PI / 2;
        terrain.position.set(bounds.centerX, 0.1, bounds.centerZ);
        terrain.receiveShadow = true;
        this.scene.add(terrain);
        this.sharedGeometry.push(geometry);
        this.sharedMaterials.push(material);
        this.buildGroundGrid(bounds);
        this.buildContourLines(bounds);
    }
    // 贴地网格：逐顶点跟随地形起伏，x/z 各自按世界步长取偶数等分，保证视觉方格
    buildGroundGrid(bounds) {
        const step = 1.25;
        const countX = Math.min(36, Math.max(16, Math.round(bounds.width / step / 2) * 2));
        const countZ = Math.min(36, Math.max(12, Math.round(bounds.height / step / 2) * 2));
        const positions = [];
        const colors = [];
        const centerColor = new THREE.Color(this.theme.gridCenter);
        const lineColor = new THREE.Color(this.theme.gridLine);
        // 网格面抬到地表（0.1 基座）上方 0.012，配合 depthWrite:false 避免与地形 z-fight
        const pushVertex = (x, z, color) => {
            positions.push(x, deterministicHeight(x, z) + 0.112, z);
            colors.push(color.r, color.g, color.b);
        };
        const subX = Math.max(8, Math.round(bounds.width / 0.6));
        const subZ = Math.max(8, Math.round(bounds.height / 0.6));
        for (let ix = 0; ix <= countX; ix += 1) {
            const x = bounds.minX + (bounds.width * ix) / countX;
            const color = ix * 2 === countX ? centerColor : lineColor;
            for (let sub = 0; sub < subZ; sub += 1) {
                pushVertex(x, bounds.minZ + (bounds.height * sub) / subZ, color);
                pushVertex(x, bounds.minZ + (bounds.height * (sub + 1)) / subZ, color);
            }
        }
        for (let iz = 0; iz <= countZ; iz += 1) {
            const z = bounds.minZ + (bounds.height * iz) / countZ;
            const color = iz * 2 === countZ ? centerColor : lineColor;
            for (let sub = 0; sub < subX; sub += 1) {
                pushVertex(bounds.minX + (bounds.width * sub) / subX, z, color);
                pushVertex(bounds.minX + (bounds.width * (sub + 1)) / subX, z, color);
            }
        }
        const geometry = new THREE.BufferGeometry();
        geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
        geometry.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
        const material = new THREE.LineBasicMaterial({
            vertexColors: true,
            transparent: true,
            opacity: 0.11,
            depthWrite: false,
        });
        const grid = new THREE.LineSegments(geometry, material);
        this.scene.add(grid);
        this.sharedGeometry.push(geometry);
        this.sharedMaterials.push(material);
    }
    // 真等高线：对 deterministicHeight 做 marching squares，取 4 个等值面生成 iso 折线
    buildContourLines(bounds) {
        const levels = [-0.15, -0.05, 0.05, 0.15];
        const cell = 0.3;
        const countX = Math.max(8, Math.ceil(bounds.width / cell));
        const countZ = Math.max(8, Math.ceil(bounds.height / cell));
        const stepX = bounds.width / countX;
        const stepZ = bounds.height / countZ;
        const heights = [];
        for (let iz = 0; iz <= countZ; iz += 1) {
            for (let ix = 0; ix <= countX; ix += 1) {
                heights.push(deterministicHeight(bounds.minX + ix * stepX, bounds.minZ + iz * stepZ));
            }
        }
        const heightAt = (ix, iz) => heights[iz * (countX + 1) + ix];
        const positions = [];
        const pushSegment = (p, q, level) => {
            // 等值线贴地：地形面 0.1 基座 + 0.02 余量
            positions.push(p[0], level + 0.12, p[1], q[0], level + 0.12, q[1]);
        };
        for (const level of levels) {
            for (let iz = 0; iz < countZ; iz += 1) {
                for (let ix = 0; ix < countX; ix += 1) {
                    const x0 = bounds.minX + ix * stepX;
                    const z0 = bounds.minZ + iz * stepZ;
                    const h0 = heightAt(ix, iz);
                    const h1 = heightAt(ix + 1, iz);
                    const h2 = heightAt(ix + 1, iz + 1);
                    const h3 = heightAt(ix, iz + 1);
                    const mask = (h0 > level ? 8 : 0) | (h1 > level ? 4 : 0) | (h2 > level ? 2 : 0) | (h3 > level ? 1 : 0);
                    if (mask === 0 || mask === 15)
                        continue;
                    const top = [x0 + stepX * ((level - h0) / (h1 - h0)), z0];
                    const right = [x0 + stepX, z0 + stepZ * ((level - h1) / (h2 - h1))];
                    const bottom = [x0 + stepX * ((level - h3) / (h2 - h3)), z0 + stepZ];
                    const left = [x0, z0 + stepZ * ((level - h0) / (h3 - h0))];
                    const centerHigh = (h0 + h1 + h2 + h3) / 4 > level;
                    if (mask === 1 || mask === 14)
                        pushSegment(bottom, left, level);
                    else if (mask === 2 || mask === 13)
                        pushSegment(right, bottom, level);
                    else if (mask === 3 || mask === 12)
                        pushSegment(right, left, level);
                    else if (mask === 4 || mask === 11)
                        pushSegment(top, right, level);
                    else if (mask === 6 || mask === 9)
                        pushSegment(top, bottom, level);
                    else if (mask === 7 || mask === 8)
                        pushSegment(top, left, level);
                    else if (mask === 5) {
                        // 鞍点按中心均值消解歧义
                        if (centerHigh) {
                            pushSegment(top, left, level);
                            pushSegment(right, bottom, level);
                        }
                        else {
                            pushSegment(top, right, level);
                            pushSegment(bottom, left, level);
                        }
                    }
                    else if (mask === 10) {
                        if (centerHigh) {
                            pushSegment(top, right, level);
                            pushSegment(bottom, left, level);
                        }
                        else {
                            pushSegment(top, left, level);
                            pushSegment(right, bottom, level);
                        }
                    }
                }
            }
        }
        const geometry = new THREE.BufferGeometry();
        geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
        const material = new THREE.LineBasicMaterial({
            color: this.theme.contour,
            transparent: true,
            opacity: 0.14,
            depthWrite: false,
        });
        const contour = new THREE.LineSegments(geometry, material);
        this.scene.add(contour);
        this.sharedGeometry.push(geometry);
        this.sharedMaterials.push(material);
    }
    getLandmarkGeometry(key, create) {
        const existing = this.landmarkGeometry.get(key);
        if (existing)
            return existing;
        const geometry = create();
        this.landmarkGeometry.set(key, geometry);
        this.sharedGeometry.push(geometry);
        return geometry;
    }
    addLandmarkMesh(group, key, create, material, position, rotation) {
        const mesh = new THREE.Mesh(this.getLandmarkGeometry(key, create), material);
        mesh.position.set(...position);
        if (rotation)
            mesh.rotation.set(...rotation);
        mesh.castShadow = true;
        group.add(mesh);
        return mesh;
    }
    createNodeLandmark(kind, material, accentMaterial, signalMaterial) {
        const landmark = new THREE.Group();
        if (kind === 'hq') {
            this.addLandmarkMesh(landmark, 'hq-bunker', () => new THREE.BoxGeometry(0.62, 0.28, 0.5), material, [0, 0.34, 0]);
            this.addLandmarkMesh(landmark, 'hq-roof', () => new THREE.ConeGeometry(0.43, 0.24, 10), accentMaterial, [0, 0.59, 0]);
            this.addLandmarkMesh(landmark, 'thin-mast', () => new THREE.CylinderGeometry(0.025, 0.035, 0.4, 10), signalMaterial, [0.2, 0.86, 0]);
            this.addLandmarkMesh(landmark, 'signal-tip', () => new THREE.SphereGeometry(0.065, 12, 8), signalMaterial, [0.2, 1.08, 0]);
            // 护墙矮墙四面围合 + 压扁沙袋圈
            this.addLandmarkMesh(landmark, 'hq-wall-long', () => new THREE.BoxGeometry(0.96, 0.09, 0.06), material, [0, 0.25, 0.36]);
            this.addLandmarkMesh(landmark, 'hq-wall-long', () => new THREE.BoxGeometry(0.96, 0.09, 0.06), material, [0, 0.25, -0.36]);
            this.addLandmarkMesh(landmark, 'hq-wall-short', () => new THREE.BoxGeometry(0.06, 0.09, 0.66), material, [0.45, 0.25, 0]);
            this.addLandmarkMesh(landmark, 'hq-wall-short', () => new THREE.BoxGeometry(0.06, 0.09, 0.66), material, [-0.45, 0.25, 0]);
            this.addLandmarkMesh(landmark, 'hq-sandbag', () => new THREE.TorusGeometry(0.56, 0.05, 6, 20).scale(1, 1, 0.55), accentMaterial, [0, 0.22, 0], [Math.PI / 2, 0, 0]);
        }
        else if (kind === 'supply') {
            this.addLandmarkMesh(landmark, 'supply-crate', () => new THREE.BoxGeometry(0.34, 0.28, 0.32), material, [-0.23, 0.34, 0.04]);
            this.addLandmarkMesh(landmark, 'supply-crate', () => new THREE.BoxGeometry(0.34, 0.28, 0.32), material, [0.17, 0.34, -0.08]);
            this.addLandmarkMesh(landmark, 'supply-small-crate', () => new THREE.BoxGeometry(0.3, 0.23, 0.28), accentMaterial, [0.02, 0.59, 0.02]);
            this.addLandmarkMesh(landmark, 'thin-mast', () => new THREE.CylinderGeometry(0.025, 0.035, 0.4, 10), signalMaterial, [-0.36, 0.66, -0.12]);
            // 第三层错堆箱 + 防水布 + 油桶
            this.addLandmarkMesh(landmark, 'supply-top-crate', () => new THREE.BoxGeometry(0.24, 0.18, 0.22), material, [-0.12, 0.78, -0.06], [0, 0.42, 0]);
            this.addLandmarkMesh(landmark, 'supply-tarp', () => new THREE.SphereGeometry(0.24, 10, 8).scale(1, 0.45, 1), accentMaterial, [0.19, 0.52, -0.08]);
            this.addLandmarkMesh(landmark, 'supply-barrel', () => new THREE.CylinderGeometry(0.09, 0.09, 0.2, 10), material, [0.44, 0.3, 0.14]);
        }
        else if (kind === 'economy') {
            this.addLandmarkMesh(landmark, 'economy-tank', () => new THREE.CylinderGeometry(0.18, 0.2, 0.5, 10), material, [-0.2, 0.44, 0]);
            this.addLandmarkMesh(landmark, 'economy-tank', () => new THREE.CylinderGeometry(0.18, 0.2, 0.5, 10), material, [0.23, 0.44, 0.04]);
            this.addLandmarkMesh(landmark, 'economy-pipe', () => new THREE.BoxGeometry(0.52, 0.055, 0.065), accentMaterial, [0.02, 0.63, 0]);
            // 阀门轮 ×2 + 第二根纵向横管
            this.addLandmarkMesh(landmark, 'economy-valve', () => new THREE.TorusGeometry(0.075, 0.018, 5, 12), accentMaterial, [0.3, 0.63, 0]);
            this.addLandmarkMesh(landmark, 'economy-valve', () => new THREE.TorusGeometry(0.075, 0.018, 5, 12), accentMaterial, [-0.26, 0.63, 0]);
            this.addLandmarkMesh(landmark, 'economy-pipe', () => new THREE.BoxGeometry(0.52, 0.055, 0.065), material, [0.02, 0.5, 0.1], [0, Math.PI / 2, 0]);
        }
        else if (kind === 'choke') {
            this.addLandmarkMesh(landmark, 'choke-tower', () => new THREE.BoxGeometry(0.24, 0.5, 0.34), material, [-0.31, 0.43, 0]);
            this.addLandmarkMesh(landmark, 'choke-tower', () => new THREE.BoxGeometry(0.24, 0.5, 0.34), material, [0.31, 0.43, 0]);
            this.addLandmarkMesh(landmark, 'choke-gate', () => new THREE.BoxGeometry(0.42, 0.09, 0.13), accentMaterial, [0, 0.65, 0]);
            // 门前拒马：三根交叉梁
            this.addLandmarkMesh(landmark, 'choke-hedgehog', () => new THREE.BoxGeometry(0.34, 0.045, 0.045), material, [0, 0.26, 0.3], [0, 0.5, 0.62]);
            this.addLandmarkMesh(landmark, 'choke-hedgehog', () => new THREE.BoxGeometry(0.34, 0.045, 0.045), material, [0, 0.26, 0.3], [0, -0.5, -0.62]);
            this.addLandmarkMesh(landmark, 'choke-hedgehog', () => new THREE.BoxGeometry(0.34, 0.045, 0.045), material, [0, 0.26, 0.3], [0.62, 0, 0]);
        }
        else if (kind === 'command') {
            this.addLandmarkMesh(landmark, 'command-mast', () => new THREE.CylinderGeometry(0.04, 0.06, 0.54, 10), material, [0, 0.48, 0]);
            this.addLandmarkMesh(landmark, 'command-dish', () => new THREE.CylinderGeometry(0.4, 0.08, 0.09, 14), accentMaterial, [0, 0.79, 0], [0, 0, -0.58]);
            this.addLandmarkMesh(landmark, 'command-ring', () => new THREE.TorusGeometry(0.23, 0.025, 5, 20), signalMaterial, [0, 0.31, 0], [Math.PI / 2, 0, 0]);
            // 天线锅支杆 + 配重箱 + 设备柜
            this.addLandmarkMesh(landmark, 'command-strut', () => new THREE.CylinderGeometry(0.018, 0.018, 0.32, 10), material, [0.1, 0.6, 0], [0, 0, -0.52]);
            this.addLandmarkMesh(landmark, 'command-weight', () => new THREE.BoxGeometry(0.16, 0.12, 0.16), accentMaterial, [0.16, 0.26, 0.1]);
            this.addLandmarkMesh(landmark, 'command-cabinet', () => new THREE.BoxGeometry(0.14, 0.2, 0.1), material, [-0.16, 0.3, 0.08]);
        }
        else {
            this.addLandmarkMesh(landmark, 'depot-tent', () => new THREE.ConeGeometry(0.4, 0.34, 10), material, [-0.12, 0.42, 0]);
            this.addLandmarkMesh(landmark, 'depot-crate', () => new THREE.BoxGeometry(0.26, 0.22, 0.25), accentMaterial, [0.34, 0.32, 0.1]);
            this.addLandmarkMesh(landmark, 'thin-mast', () => new THREE.CylinderGeometry(0.025, 0.035, 0.4, 10), signalMaterial, [-0.38, 0.64, -0.08]);
            // 帐篷脊杆 + 侧箱 + 矮桶
            this.addLandmarkMesh(landmark, 'depot-ridge', () => new THREE.CylinderGeometry(0.015, 0.015, 0.5, 10), accentMaterial, [-0.12, 0.58, 0], [Math.PI / 2, 0, 0]);
            this.addLandmarkMesh(landmark, 'depot-side-crate', () => new THREE.BoxGeometry(0.2, 0.16, 0.18), material, [-0.44, 0.28, 0.16]);
            this.addLandmarkMesh(landmark, 'depot-barrel', () => new THREE.CylinderGeometry(0.08, 0.08, 0.18, 10), accentMaterial, [-0.4, 0.29, -0.16]);
        }
        return landmark;
    }
    // 贴地行军带：沿曲线路径采样，切线法向 offsets 出左右顶点，TriangleStrip 成带；
    // 每顶点按落点重算地形高度，中段不再穿透地形起伏
    buildRouteRibbon(a, b, halfWidth) {
        const midpoint = a.clone().lerp(b, 0.5);
        midpoint.y += 0.16;
        const curve = new THREE.CatmullRomCurve3([a.clone(), midpoint, b.clone()]);
        const segments = 32;
        const samples = curve.getPoints(segments);
        const positions = [];
        const uvs = [];
        const indices = [];
        let length = 0;
        for (let index = 0; index <= segments; index += 1) {
            const point = samples[index];
            const before = samples[Math.max(0, index - 1)];
            const after = samples[Math.min(segments, index + 1)];
            if (index > 0)
                length += Math.hypot(point.x - before.x, point.z - before.z);
            let tangentX = after.x - before.x;
            let tangentZ = after.z - before.z;
            const tangentLength = Math.hypot(tangentX, tangentZ) || 1;
            tangentX /= tangentLength;
            tangentZ /= tangentLength;
            const normalX = -tangentZ;
            const normalZ = tangentX;
            for (const side of [-1, 1]) {
                const x = point.x + normalX * halfWidth * side;
                const z = point.z + normalZ * halfWidth * side;
                positions.push(x, deterministicHeight(x, z) + 0.16, z);
                uvs.push(length / 0.55, side * 0.5 + 0.5);
            }
            if (index < segments) {
                const base = index * 2;
                indices.push(base, base + 1, base + 2, base + 1, base + 3, base + 2);
            }
        }
        const geometry = new THREE.BufferGeometry();
        geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
        geometry.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
        geometry.setIndex(indices);
        geometry.computeVertexNormals();
        return geometry;
    }
    buildRoutesAndNodes(state, projections) {
        for (const projection of projections) {
            this.nodePositions.set(projection.nodeId, new THREE.Vector3(projection.x, deterministicHeight(projection.x, projection.z) + 0.26, projection.z));
        }
        for (const edge of state.map.edges) {
            const a = this.nodePositions.get(edge.a);
            const b = this.nodePositions.get(edge.b);
            if (!a || !b)
                continue;
            // 底带 + 箭头纹带共用同一份带几何，纹带抬高 0.008 防共面
            const geometry = this.buildRouteRibbon(a, b, 0.07);
            const bodyMaterial = new THREE.MeshBasicMaterial({
                color: this.theme.routeBase,
                transparent: true,
                opacity: 0.34,
                depthWrite: false,
            });
            const markTexture = makeRouteMarkTexture();
            const markMaterial = new THREE.MeshBasicMaterial({
                color: this.theme.route,
                map: markTexture,
                transparent: true,
                opacity: 0.5,
                depthWrite: false,
            });
            const body = new THREE.Mesh(geometry, bodyMaterial);
            const mark = new THREE.Mesh(geometry, markMaterial);
            mark.position.y += 0.008;
            this.scene.add(body, mark);
            this.sharedGeometry.push(geometry);
            this.sharedMaterials.push(bodyMaterial, markMaterial);
            if (markTexture)
                this.sharedTextures.push(markTexture);
            this.routeVisuals.push({ a: edge.a, b: edge.b, bodyMaterial, markMaterial, markTexture, flow: false });
        }
        const bodyGeometry = new THREE.CylinderGeometry(0.68, 0.84, 0.22, 6);
        const capGeometry = new THREE.CylinderGeometry(0.47, 0.6, 0.09, 6);
        const ringGeometry = new THREE.TorusGeometry(0.9, 0.045, 6, 36);
        const beaconGeometry = new THREE.CylinderGeometry(0.035, 0.055, 0.58, 8);
        this.sharedGeometry.push(bodyGeometry, capGeometry, ringGeometry, beaconGeometry);
        for (const projection of projections) {
            const position = this.nodePositions.get(projection.nodeId);
            if (!position)
                continue;
            const baseColor = ownerColor(projection.ownerFactionId, this.theme.neutralNode);
            const bodyMaterial = new THREE.MeshStandardMaterial({
                color: baseColor,
                emissive: 0x000000,
                roughness: 0.62,
                metalness: 0.34,
                envMapIntensity: 0.6,
            });
            const capMaterial = new THREE.MeshStandardMaterial({
                color: liftLightness(baseColor, 1.15),
                emissive: 0x000000,
                roughness: 0.48,
                metalness: 0.42,
                envMapIntensity: 0.7,
            });
            const landmarkMaterial = new THREE.MeshStandardMaterial({
                color: landmarkColor(projection.ownerFactionId, this.theme),
                emissive: 0x000000,
                roughness: 0.5,
                metalness: 0.24,
                envMapIntensity: 0.55,
            });
            const landmarkAccentMaterial = new THREE.MeshStandardMaterial({
                color: landmarkAccentColor(projection.ownerFactionId, this.theme),
                emissive: 0x000000,
                roughness: 0.42,
                metalness: 0.3,
                envMapIntensity: 0.7,
            });
            const ringMaterial = new THREE.MeshBasicMaterial({
                color: 0xf2c466,
                transparent: true,
                opacity: 0.2,
                depthWrite: false,
                fog: false,
                toneMapped: false,
            });
            const beaconMaterial = new THREE.MeshBasicMaterial({
                color: this.theme.neutralBeacon,
                transparent: true,
                opacity: 0.44,
                depthWrite: false,
                fog: false,
                toneMapped: false,
            });
            this.sharedMaterials.push(bodyMaterial, capMaterial, landmarkMaterial, landmarkAccentMaterial, ringMaterial, beaconMaterial);
            const group = new THREE.Group();
            group.position.copy(position);
            const body = new THREE.Mesh(bodyGeometry, bodyMaterial);
            body.userData.nodeId = projection.nodeId;
            body.castShadow = true;
            const cap = new THREE.Mesh(capGeometry, capMaterial);
            cap.position.y = 0.14;
            cap.castShadow = true;
            const ring = new THREE.Mesh(ringGeometry, ringMaterial);
            ring.rotation.x = Math.PI / 2;
            ring.position.y = 0.13;
            const beacon = new THREE.Mesh(beaconGeometry, beaconMaterial);
            beacon.position.y = 0.43;
            const landmark = this.createNodeLandmark(projection.kind, landmarkMaterial, landmarkAccentMaterial, beaconMaterial);
            group.add(body, cap, landmark, ring, beacon);
            this.scene.add(group);
            this.nodeVisuals.set(projection.nodeId, {
                group,
                hit: body,
                bodyMaterial,
                capMaterial,
                landmarkMaterial,
                landmarkAccentMaterial,
                ringMaterial,
                beaconMaterial,
            });
        }
    }
    update(state, selectedNodeId, selectedPieceIds, actionPreviews = []) {
        if (this.disposed)
            return;
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
        this.animationStartedAt = null;
        this.requestRender(true);
    }
    updateNodes(state) {
        for (const projection of projectNodes(state)) {
            const visual = this.nodeVisuals.get(projection.nodeId);
            if (!visual)
                continue;
            const selected = projection.nodeId === this.selectedNodeId;
            const hovered = projection.nodeId === this.hoveredNodeId;
            const commandTarget = this.commandTargets.get(projection.nodeId);
            const commandPartial = commandTarget?.ok === true
                && commandTarget.actualPieceIds.length < this.selectedPieceIds.size;
            const baseColor = ownerColor(projection.ownerFactionId, this.theme.neutralNode);
            visual.bodyMaterial.color.setHex(baseColor);
            visual.capMaterial.color.setHex(liftLightness(baseColor, 1.15));
            visual.landmarkMaterial.color.setHex(landmarkColor(projection.ownerFactionId, this.theme));
            visual.landmarkAccentMaterial.color.setHex(landmarkAccentColor(projection.ownerFactionId, this.theme));
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
            visual.landmarkAccentMaterial.emissive.setHex(emissive);
            visual.bodyMaterial.emissiveIntensity = intensity;
            visual.capMaterial.emissiveIntensity = intensity;
            visual.landmarkMaterial.emissiveIntensity = intensity * 0.72;
            visual.landmarkAccentMaterial.emissiveIntensity = intensity * 0.72;
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
            route.markMaterial.color.setHex(target?.ok
                ? target.isBattle ? 0xdf665b : 0x78bc73
                : target ? 0x7d4641
                    : relevant ? 0xf2c466 : this.theme.route);
            route.markMaterial.opacity = target?.ok ? 0.98 : target ? 0.28 : relevant ? 0.94 : 0.46;
            route.bodyMaterial.opacity = target?.ok ? 0.62 : relevant ? 0.52 : 0.34;
            // 蚂蚁线只在指令合法高亮时滚动，纹向始终指向目标节点；reducedMotion 全程定格
            route.flow = target?.ok === true && !this.options.reducedMotion;
            if (route.markTexture) {
                route.markTexture.repeat.x = route.a === this.selectedNodeId ? 1 : -1;
            }
        }
        this.updateVisualScale(this.getCameraState().zoomPercent);
    }
    piecePosition(piece, index) {
        const center = (this.nodePositions.get(piece.nodeId) ?? new THREE.Vector3()).clone();
        const formation = [
            [-0.66, 0.18],
            [-0.22, 0.48],
            [0.22, 0.48],
            [0.66, 0.18],
            [0, -0.52],
        ];
        const slot = formation[index % formation.length] ?? formation[0];
        const ring = Math.floor(index / formation.length);
        center.x += slot[0] * (1 + ring * 0.35);
        center.z += slot[1] * (1 + ring * 0.35);
        // 编队偏移会让棋子离开节点平台，按偏移后的落点重算地形高度，避免坡上悬浮 / 陷入
        center.y = deterministicHeight(center.x, center.z) + 0.24;
        return center;
    }
    updatePieces(state) {
        const alive = new Set(Object.keys(state.pieces));
        for (const [pieceId, visual] of this.pieceVisuals) {
            if (alive.has(pieceId))
                continue;
            visual.group.removeFromParent();
            for (const material of new Set(visual.materials))
                material.dispose();
            this.pieceVisuals.delete(pieceId);
        }
        const byNode = new Map();
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
                visual.start.copy(visual.current);
                const selected = this.selectedPieceIds.has(piece.pieceId);
                const hovered = piece.pieceId === this.hoveredPieceId;
                visual.baseMaterial.emissive.setHex(selected ? 0xf3c45b : hovered ? 0x8f7442 : 0x000000);
                visual.baseMaterial.emissiveIntensity = selected ? 0.85 : hovered ? 0.5 : 0;
                visual.accentMaterial.emissive.setHex(selected ? 0xf3c45b : hovered ? 0x6f5a34 : 0x000000);
                visual.accentMaterial.emissiveIntensity = selected ? 0.7 : hovered ? 0.36 : 0;
                visual.badgeMaterial.color.setHex(selected ? 0xffedbd : hovered ? 0xfff8e6 : 0xffffff);
                visual.selectionBaseOpacity = selected ? 0.95 : hovered ? 0.48 : 0.16;
                visual.selectionMaterial.opacity = visual.selectionBaseOpacity;
                visual.selection.scale.setScalar(1);
            });
        }
        this.container.dataset.pieceVisualStyle = 'tactical-badge-v1';
        this.container.dataset.pieceBadgeCount = String(this.pieceVisuals.size);
        this.updateVisualScale(this.getCameraState().zoomPercent);
    }
    updatePieceHighlights(state) {
        for (const [pieceId, visual] of this.pieceVisuals) {
            if (!state.pieces[pieceId])
                continue;
            const selected = this.selectedPieceIds.has(pieceId);
            const hovered = pieceId === this.hoveredPieceId;
            visual.baseMaterial.emissive.setHex(selected ? 0xf3c45b : hovered ? 0x8f7442 : 0x000000);
            visual.baseMaterial.emissiveIntensity = selected ? 0.85 : hovered ? 0.5 : 0;
            visual.accentMaterial.emissive.setHex(selected ? 0xf3c45b : hovered ? 0x6f5a34 : 0x000000);
            visual.accentMaterial.emissiveIntensity = selected ? 0.7 : hovered ? 0.36 : 0;
            visual.badgeMaterial.color.setHex(selected ? 0xffedbd : hovered ? 0xfff8e6 : 0xffffff);
            visual.selectionBaseOpacity = selected ? 0.95 : hovered ? 0.48 : 0.16;
            visual.selectionMaterial.opacity = visual.selectionBaseOpacity;
            visual.selection.scale.setScalar(1);
        }
    }
    updateVisualScale(zoomPercent) {
        // Keep operational markers readable without letting them consume the
        // tactical viewport. They still grow slightly on screen as detail rises.
        const nodeCompensation = Math.max(0.52, Math.min(1, Math.sqrt(100 / Math.max(100, zoomPercent))));
        const pieceCompensation = tacticalMarkerScale(zoomPercent);
        for (const [nodeId, visual] of this.nodeVisuals) {
            const selectedScale = nodeId === this.selectedNodeId ? 1.08 : 1;
            const activeScale = visual.group.userData.active === false ? 0.8 : 1;
            visual.group.scale.set(nodeCompensation * selectedScale, nodeCompensation * activeScale, nodeCompensation * selectedScale);
        }
        for (const visual of this.pieceVisuals.values()) {
            visual.group.scale.setScalar(pieceCompensation);
        }
        this.container.dataset.pieceScale = pieceCompensation.toFixed(3);
        this.container.dataset.pieceScreenGrowth = (pieceCompensation * Math.max(1, zoomPercent / 100)).toFixed(3);
        this.container.dataset.pieceScalePolicy = 'progressive-art-detail-v1';
    }
    createPieceVisual(piece, position) {
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
            envMapIntensity: 0.65,
        });
        const accentMaterial = new THREE.MeshStandardMaterial({
            color: factionId === 'red' ? 0xd95a3e : 0x4d9bc5,
            emissive: 0x000000,
            roughness: 0.32,
            metalness: 0.7,
            envMapIntensity: 0.75,
        });
        // 假阴影圆片保留作接触暗部，但降到轻量级，避免与真实阴影双重变暗
        const shadowMaterial = new THREE.MeshBasicMaterial({
            color: 0x090806,
            transparent: true,
            opacity: 0.2,
            depthWrite: false,
            fog: false,
            toneMapped: false,
        });
        const shadow = new THREE.Mesh(this.pieceShadowGeometry, shadowMaterial);
        shadow.rotation.x = -Math.PI / 2;
        // 棋组原点在地表上方 0.24，圆片下沉回地面（地形面 0.1）并留 0.004 防共面闪烁
        shadow.position.y = -0.136;
        shadow.renderOrder = 1;
        group.add(shadow);
        const base = new THREE.Mesh(this.pieceBaseGeometry, baseMaterial);
        base.position.y = 0.06;
        base.castShadow = true;
        base.userData.pieceId = piece.pieceId;
        group.add(base);
        const cap = new THREE.Mesh(this.pieceCapGeometry, accentMaterial);
        cap.position.y = 0.138;
        cap.castShadow = true;
        cap.userData.pieceId = piece.pieceId;
        group.add(cap);
        const support = new THREE.Mesh(this.pieceSupportGeometry, accentMaterial);
        support.position.y = 0.31;
        support.castShadow = true;
        support.userData.pieceId = piece.pieceId;
        group.add(support);
        const selectionMaterial = new THREE.MeshBasicMaterial({
            color: 0xffd77d,
            transparent: true,
            opacity: 0.16,
            depthWrite: false,
            fog: false,
            toneMapped: false,
        });
        const selection = new THREE.Mesh(this.pieceSelectionGeometry, selectionMaterial);
        selection.rotation.x = Math.PI / 2;
        selection.position.y = 0.025;
        selection.renderOrder = 2;
        group.add(selection);
        const identifier = getCardDefinition(piece.cardId).identifier;
        const texture = this.portraitTextures.get(identifier) ?? makeFallbackTexture(identifier);
        if (texture && !this.portraitTextures.has(identifier))
            this.portraitTextures.set(identifier, texture);
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
            if (this.piecePortraitMaskTexture)
                this.sharedTextures.push(this.piecePortraitMaskTexture);
        }
        const badgeMaterial = new THREE.SpriteMaterial({
            map: badgeTexture,
            transparent: true,
            depthTest: true,
            depthWrite: false,
            alphaTest: 0.02,
            fog: false,
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
            fog: false,
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
            selection,
            selectionBaseOpacity: 0.16,
            materials: [baseMaterial, accentMaterial, shadowMaterial, selectionMaterial, badgeMaterial, portraitMaterial],
            target: position.clone(),
            current: position.clone(),
            start: position.clone(),
        };
    }
    async loadPortraitTextures() {
        const resolver = getEnemyPortraitResolver();
        if (!resolver) {
            this.options.onError('正式头像解析器尚未加载，沙盘临时使用识别牌。');
            return;
        }
        const generation = this.textureFence.next();
        try {
            const descriptors = await resolvePortraitDescriptors(resolver);
            for (const [identifier, descriptor] of descriptors) {
                if (!this.textureFence.isCurrent(generation))
                    return;
                const urls = textureUrlsFor(descriptor);
                let texture = null;
                for (const url of urls) {
                    try {
                        texture = await this.loadTexture(url);
                        break;
                    }
                    catch {
                        // PNG -> SVG -> legacy. Presentation fallback never touches state.
                    }
                }
                if (!texture)
                    continue;
                if (!this.textureFence.isCurrent(generation)) {
                    texture.dispose();
                    return;
                }
                texture.colorSpace = THREE.SRGBColorSpace;
                const previous = this.portraitTextures.get(identifier);
                if (previous)
                    previous.dispose();
                this.portraitTextures.set(identifier, texture);
                for (const visual of this.pieceVisuals.values()) {
                    if (visual.identifier !== identifier)
                        continue;
                    visual.portraitMaterial.map = texture;
                    visual.portraitMaterial.needsUpdate = true;
                }
                this.requestRender();
            }
        }
        catch (error) {
            if (this.textureFence.isCurrent(generation)) {
                this.options.onError(`头像纹理加载失败：${error instanceof Error ? error.message : String(error)}`);
            }
        }
    }
    loadTexture(url) {
        return new Promise((resolve, reject) => {
            const loader = new THREE.TextureLoader();
            loader.load(url, resolve, undefined, reject);
        });
    }
    pointerToNdc(clientX, clientY) {
        const rect = this.renderer.domElement.getBoundingClientRect();
        if (!rect.width || !rect.height)
            return false;
        this.pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
        this.pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
        return true;
    }
    screenToGround(clientX, clientY) {
        if (!this.pointerToNdc(clientX, clientY))
            return null;
        this.raycaster.setFromCamera(this.pointer, this.camera);
        return this.raycaster.ray.intersectPlane(this.groundPlane, new THREE.Vector3());
    }
    pickNode(clientX, clientY) {
        if (!this.pointerToNdc(clientX, clientY))
            return null;
        this.raycaster.setFromCamera(this.pointer, this.camera);
        const hits = this.raycaster.intersectObjects(Array.from(this.nodeVisuals.values()).map((visual) => visual.hit), false);
        return hits[0]?.object?.userData?.nodeId ?? null;
    }
    pickPiece(clientX, clientY) {
        if (!this.pointerToNdc(clientX, clientY))
            return null;
        this.raycaster.setFromCamera(this.pointer, this.camera);
        const hits = this.raycaster.intersectObjects(Array.from(this.pieceVisuals.values()).flatMap((visual) => visual.hits), false);
        return hits[0]?.object?.userData?.pieceId ?? null;
    }
    updateHover(clientX, clientY) {
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
        // 悬停钩子只在目标变化时发射一次；anchor 取发射时刻的指针位置，不随同目标内移动重复推送
        if (changed)
            this.emitHoverInfo(clientX, clientY);
        const target = nextNodeId ? this.commandTargets.get(nextNodeId) : undefined;
        this.renderer.domElement.style.cursor = piece?.factionId === 'red'
            ? 'pointer'
            : target?.ok ? 'crosshair'
                : target ? 'not-allowed'
                    : nextNodeId ? 'pointer' : 'grab';
    }
    emitHoverInfo(clientX, clientY) {
        if (!this.options.onHoverInfo)
            return;
        const rect = this.renderer.domElement.getBoundingClientRect();
        const anchor = { x: clientX - rect.left, y: clientY - rect.top };
        if (this.hoveredPieceId)
            this.options.onHoverInfo({ kind: 'piece', pieceId: this.hoveredPieceId }, anchor);
        else if (this.hoveredNodeId)
            this.options.onHoverInfo({ kind: 'node', nodeId: this.hoveredNodeId }, anchor);
        else
            this.options.onHoverInfo(null, anchor);
    }
    updateMarquee(startX, startY, endX, endY) {
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
    marqueeCandidates() {
        if (!this.currentState)
            return [];
        const rect = this.renderer.domElement.getBoundingClientRect();
        this.scene.updateMatrixWorld(true);
        this.camera.updateMatrixWorld(true);
        const candidates = [];
        for (const [pieceId, visual] of this.pieceVisuals) {
            const piece = this.currentState.pieces[pieceId];
            if (!piece)
                continue;
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
    onPointerDown = (event) => {
        if (this.disposed || (event.button !== 0 && event.button !== 1 && event.button !== 2))
            return;
        event.preventDefault();
        this.renderer.domElement.focus({ preventScroll: true });
        // 任何直接输入都打断进行中的运镜，以当前实际位置继续
        this.cameraTween = null;
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
        try {
            this.renderer.domElement.setPointerCapture(event.pointerId);
        }
        catch { /* synthetic QA pointers */ }
    };
    onPointerMove = (event) => {
        if (this.disposed)
            return;
        if (!this.drag || this.drag.pointerId !== event.pointerId) {
            this.updateHover(event.clientX, event.clientY);
            return;
        }
        const totalDistance = Math.hypot(event.clientX - this.drag.startX, event.clientY - this.drag.startY);
        if (!this.drag.moved && totalDistance >= 4) {
            this.drag.moved = true;
            this.container.classList.add(this.drag.mode === 'marquee' ? 'is-selecting' : 'is-panning');
        }
        if (!this.drag.moved)
            return;
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
        if (!before || !after)
            return;
        this.cameraView.centerX += before.x - after.x;
        this.cameraView.centerZ += before.z - after.z;
        this.cameraView = clampCameraView(this.cameraView, this.mapBounds, this.viewportAspect, this.cameraLimits, this.cameraEdgeMargin());
        this.applyCamera();
    };
    finishPointer(event, cancelled) {
        if (!this.drag || this.drag.pointerId !== event.pointerId)
            return;
        const drag = this.drag;
        const click = !cancelled && !drag.moved && (drag.button === 0 || drag.button === 2);
        this.drag = null;
        this.container.classList.remove('is-panning');
        this.container.classList.remove('is-selecting');
        this.marqueeElement.hidden = true;
        try {
            this.renderer.domElement.releasePointerCapture(event.pointerId);
        }
        catch { /* synthetic QA pointers */ }
        if (!cancelled && drag.moved && drag.mode === 'marquee') {
            const selection = selectMarqueeCandidates(this.marqueeCandidates(), { startX: drag.startX, startY: drag.startY, endX: event.clientX, endY: event.clientY }, this.selectedPieceIds.size > 0 ? this.selectedNodeId : undefined);
            this.container.dataset.marqueeIgnoredCount = String(selection.ignoredCount);
            this.options.onMarqueeSelected({ ...selection, additive: drag.additive });
            this.updateHover(event.clientX, event.clientY);
            return;
        }
        if (click && drag.button === 2) {
            // 右键单击 = 沙盘空白点击语义（RTS 惯例取消编组）；右键拖拽已在 pan 分支按平移处理
            this.lastPieceTap = null;
            this.options.onEmptyPicked();
        }
        else if (click) {
            const pieceId = this.pickPiece(event.clientX, event.clientY);
            if (pieceId) {
                const tapTime = Number.isFinite(event.timeStamp) ? event.timeStamp : performance.now();
                const isDouble = this.lastPieceTap?.pieceId === pieceId && tapTime - this.lastPieceTap.time <= 320;
                this.lastPieceTap = isDouble ? null : { pieceId, time: tapTime };
                if (isDouble) {
                    const nodeId = this.currentState?.pieces[pieceId]?.nodeId;
                    if (nodeId)
                        this.options.onNodeDoublePicked(nodeId);
                }
                else {
                    this.options.onPiecePicked(pieceId, event.shiftKey || event.ctrlKey || event.metaKey);
                }
            }
            else {
                this.lastPieceTap = null;
                const nodeId = this.pickNode(event.clientX, event.clientY);
                if (nodeId)
                    this.options.onNodePicked(nodeId);
                else
                    this.options.onEmptyPicked();
            }
        }
        this.updateHover(event.clientX, event.clientY);
    }
    onPointerUp = (event) => this.finishPointer(event, false);
    onPointerCancel = (event) => this.finishPointer(event, true);
    onWheel = (event) => {
        if (this.disposed || !this.mapInstalled)
            return;
        event.preventDefault();
        // 滚轮缩放保持即时手感，直接取消进行中的运镜
        this.cameraTween = null;
        const factor = Math.exp(-Math.max(-240, Math.min(240, event.deltaY)) * 0.0018);
        this.zoomAt(factor, event.clientX, event.clientY);
    };
    // WebView2 下右键会弹原生菜单，统一压住；右键语义由 pointer 路径承担
    onContextMenu = (event) => {
        event.preventDefault();
    };
    onKeyDown = (event) => {
        if (this.disposed || !this.mapInstalled)
            return;
        const key = event.key.toLowerCase();
        const panStep = this.cameraView.halfHeight * (event.shiftKey ? 0.28 : 0.12);
        let handled = true;
        if (key === '+' || key === '=')
            this.zoomBy(1.25);
        else if (key === '-' || key === '_')
            this.zoomBy(0.8);
        else if (key === '0' || key === 'home')
            this.fitToMap();
        else if (key === 'arrowleft' || key === 'a')
            this.panBy(-panStep, 0);
        else if (key === 'arrowright' || key === 'd')
            this.panBy(panStep, 0);
        else if (key === 'arrowup' || key === 'w')
            this.panBy(0, -panStep);
        else if (key === 'arrowdown' || key === 's')
            this.panBy(0, panStep);
        else
            handled = false;
        if (handled)
            event.preventDefault();
    };
    cameraEdgeMargin() {
        const zoomProgress = Math.max(0, Math.min(1, (cameraZoomPercent(this.cameraView, this.cameraLimits) - 100) / 100));
        const tacticalHalfSpan = Math.max(this.cameraView.halfHeight, this.cameraView.halfHeight * this.viewportAspect);
        return 1.3 + Math.max(0, tacticalHalfSpan - 1.3) * zoomProgress;
    }
    recomputeCameraLimits(reset) {
        const paddedBounds = expandWorldBounds(this.mapBounds, 1.2);
        this.cameraLimits = cameraLimitsFor(paddedBounds, this.viewportAspect);
        if (reset)
            this.cameraView = fitCameraToBounds(paddedBounds, this.viewportAspect);
        this.cameraView = clampCameraView(this.cameraView, this.mapBounds, this.viewportAspect, this.cameraLimits, this.cameraEdgeMargin());
        this.applyCamera();
    }
    applyCamera(notify = true) {
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
        if (notify)
            this.options.onCameraChanged?.(snapshot);
        this.requestRender();
    }
    zoomAt(factor, clientX, clientY) {
        const anchored = typeof clientX === 'number' && typeof clientY === 'number';
        const before = anchored ? this.screenToGround(clientX, clientY) : null;
        this.cameraView = zoomCameraView(this.cameraView, factor, this.cameraLimits);
        this.applyCamera(false);
        const after = anchored ? this.screenToGround(clientX, clientY) : null;
        if (before && after) {
            this.cameraView.centerX += before.x - after.x;
            this.cameraView.centerZ += before.z - after.z;
        }
        this.cameraView = clampCameraView(this.cameraView, this.mapBounds, this.viewportAspect, this.cameraLimits, this.cameraEdgeMargin());
        this.applyCamera();
    }
    // 程序性相机移动统一走 240ms ease-out 运镜；目标先过 clamp，新目标以当前实际位置为起点，
    // reducedMotion 与零距离目标直接跳变。过渡期间逐帧 applyCamera 连发快照属预期
    glideCameraTo(target, notify = true) {
        const clamped = clampCameraView(target, this.mapBounds, this.viewportAspect, this.cameraLimits, this.cameraEdgeMargin());
        this.cameraTween = null;
        const settled = Math.abs(clamped.centerX - this.cameraView.centerX) < 0.0001
            && Math.abs(clamped.centerZ - this.cameraView.centerZ) < 0.0001
            && Math.abs(clamped.halfHeight - this.cameraView.halfHeight) < 0.0001;
        if (this.options.reducedMotion || settled) {
            this.cameraView = clamped;
            this.applyCamera(notify);
            return;
        }
        this.cameraTween = {
            startX: this.cameraView.centerX,
            startZ: this.cameraView.centerZ,
            startHalfHeight: this.cameraView.halfHeight,
            targetX: clamped.centerX,
            targetZ: clamped.centerZ,
            targetHalfHeight: clamped.halfHeight,
            startedAt: null,
            duration: 240,
        };
        // 帧饥饿环境（headless QA / 后台标签节流）下 rAF 可能长期不流动；
        // 兜底计时器保证运镜在真实时间内落位，data-camera-* 快照消费者得以收敛。
        // 正常浏览器中 rAF 先完成，本回调因 identity 失配直接空转
        const tween = this.cameraTween;
        if (this.cameraTweenTimer !== null)
            window.clearTimeout(this.cameraTweenTimer);
        this.cameraTweenTimer = window.setTimeout(() => {
            this.cameraTweenTimer = null;
            if (this.disposed || this.cameraTween !== tween)
                return;
            this.cameraTween = null;
            this.cameraView = { centerX: tween.targetX, centerZ: tween.targetZ, halfHeight: tween.targetHalfHeight };
            this.applyCamera();
        }, tween.duration + 60);
        this.requestRender();
    }
    // 程序性输入的基准视图：运镜进行中取“意图位置”（tween 目标），否则取渲染位置。
    // 连按 ＋/方向键要在意图上叠加（每次一整步），渲染位置只作插值起点保证画面不回跳
    cameraIntentView() {
        const tween = this.cameraTween;
        return tween
            ? { centerX: tween.targetX, centerZ: tween.targetZ, halfHeight: tween.targetHalfHeight }
            : this.cameraView;
    }
    zoomBy(factor) {
        if (!this.mapInstalled || this.disposed)
            return;
        this.glideCameraTo(zoomCameraView(this.cameraIntentView(), factor, this.cameraLimits));
    }
    panBy(deltaX, deltaZ) {
        if (!this.mapInstalled || this.disposed)
            return;
        const base = this.cameraIntentView();
        this.glideCameraTo({
            ...base,
            centerX: base.centerX + deltaX,
            centerZ: base.centerZ + deltaZ,
        });
    }
    fitToMap(notify = true) {
        if (!this.mapInstalled || this.disposed)
            return;
        this.glideCameraTo(fitCameraToBounds(expandWorldBounds(this.mapBounds, 1.2), this.viewportAspect), notify);
    }
    focusNode(nodeId) {
        if (!this.mapInstalled || this.disposed)
            return;
        const point = this.nodePositions.get(nodeId);
        if (!point)
            return;
        const base = this.cameraIntentView();
        this.glideCameraTo({
            ...base,
            centerX: point.x,
            centerZ: point.z,
            halfHeight: Math.min(base.halfHeight, this.cameraLimits.fitHalfHeight / 2.2),
        });
    }
    getCameraState() {
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
    resize() {
        if (this.disposed)
            return;
        const width = Math.max(1, this.container.clientWidth || 720);
        const height = Math.max(1, this.container.clientHeight || 390);
        // ResizeObserver 噪声（尺寸未变的重复回调）不得打断进行中的运镜；
        // 只有真实尺寸变化才落位并取消 tween（headless QA 实测 RO 会同尺寸连发）
        if (width === this.lastLayoutWidth && height === this.lastLayoutHeight)
            return;
        this.lastLayoutWidth = width;
        this.lastLayoutHeight = height;
        // 布局变化直接落位，不与进行中的运镜争夺 halfHeight
        this.cameraTween = null;
        const previousAspect = this.viewportAspect;
        this.viewportAspect = width / height;
        this.renderer.setSize(width, height, false);
        if (this.mapInstalled && Math.abs(previousAspect - this.viewportAspect) > 0.001) {
            const zoomRatio = this.cameraLimits.fitHalfHeight / Math.max(0.0001, this.cameraView.halfHeight);
            this.cameraLimits = cameraLimitsFor(expandWorldBounds(this.mapBounds, 1.2), this.viewportAspect);
            this.cameraView.halfHeight = this.cameraLimits.fitHalfHeight / Math.max(0.0001, zoomRatio);
            this.cameraView = clampCameraView(this.cameraView, this.mapBounds, this.viewportAspect, this.cameraLimits, this.cameraEdgeMargin());
        }
        this.applyCamera();
    }
    requestRender(animate = false) {
        if (this.disposed || this.animationFrame !== null)
            return;
        this.animationFrame = requestAnimationFrame((time) => this.renderFrame(time, animate));
    }
    renderFrame(time, animate) {
        this.animationFrame = null;
        if (this.disposed)
            return;
        let moving = false;
        const reducedMotion = this.options.reducedMotion;
        // 相机运镜：三通道 ease-out 插值，落位即出窗
        if (this.cameraTween) {
            const tween = this.cameraTween;
            // 运镜时钟统一用 rAF 帧时间：headless/节流下 performance.now() 与帧时间可相差秒级，
            // 混用会让进度长期冻结在 0（Edge headless QA 实测复现）
            if (tween.startedAt === null)
                tween.startedAt = time;
            const cameraProgress = Math.min(1, Math.max(0, time - tween.startedAt) / tween.duration);
            const cameraEased = 1 - Math.pow(1 - cameraProgress, 3);
            this.cameraView.centerX = tween.startX + (tween.targetX - tween.startX) * cameraEased;
            this.cameraView.centerZ = tween.startZ + (tween.targetZ - tween.startZ) * cameraEased;
            this.cameraView.halfHeight = tween.startHalfHeight + (tween.targetHalfHeight - tween.startHalfHeight) * cameraEased;
            if (cameraProgress >= 1)
                this.cameraTween = null;
            this.applyCamera();
        }
        const moveDuration = reducedMotion ? 1 : 420;
        // 选择环脉冲窗口比移动补间长，但同样有限，窗结束即回静态
        const pulseDuration = reducedMotion ? 1 : 900;
        // 与相机运镜同一 rAF 帧时钟：update() 只把起点置 null，在首帧闩锁
        if (this.animationStartedAt === null)
            this.animationStartedAt = time;
        const elapsed = Math.max(0, time - this.animationStartedAt);
        const moveStep = Math.min(1, elapsed / moveDuration);
        const pulseStep = Math.min(1, elapsed / pulseDuration);
        const eased = 1 - Math.pow(1 - moveStep, 3);
        const pulse = 1 + 0.1 * Math.exp(-3 * pulseStep) * Math.sin(8 * Math.PI * pulseStep);
        for (const [pieceId, visual] of this.pieceVisuals) {
            if (visual.current.distanceToSquared(visual.target) > 0.0001) {
                // 绝对进度必须作用于补间起点的快照；直接 lerp 已推进的 current 会让等效曲线过陡
                visual.current.lerpVectors(visual.start, visual.target, eased);
                if (moveStep < 1 && !reducedMotion) {
                    visual.current.y += Math.sin(Math.PI * moveStep) * 0.12;
                }
                visual.group.position.copy(visual.current);
                moving = moveStep < 1;
                if (moveStep >= 1)
                    visual.current.copy(visual.target);
            }
            if (this.selectedPieceIds.has(pieceId)) {
                visual.selectionMaterial.opacity = Math.min(1, visual.selectionBaseOpacity * pulse);
                visual.selection.scale.setScalar(pulse);
            }
        }
        // 蚂蚁线：只在有界渲染窗内滚动，窗结束 offset 定格在最后一帧
        if (!reducedMotion && pulseStep < 1) {
            for (const route of this.routeVisuals) {
                if (route.flow && route.markTexture)
                    route.markTexture.offset.x = -elapsed * 0.0011;
            }
        }
        this.renderer.render(this.scene, this.camera);
        if (moving || this.cameraTween !== null || (animate && pulseStep < 1))
            this.requestRender(true);
    }
    dispose() {
        if (this.disposed)
            return;
        this.disposed = true;
        this.textureFence.dispose();
        if (this.animationFrame !== null)
            cancelAnimationFrame(this.animationFrame);
        this.animationFrame = null;
        if (this.cameraTweenTimer !== null)
            window.clearTimeout(this.cameraTweenTimer);
        this.cameraTweenTimer = null;
        this.resizeObserver?.disconnect();
        this.resizeObserver = null;
        this.renderer.domElement.removeEventListener('pointerdown', this.onPointerDown);
        this.renderer.domElement.removeEventListener('pointermove', this.onPointerMove);
        this.renderer.domElement.removeEventListener('pointerup', this.onPointerUp);
        this.renderer.domElement.removeEventListener('pointercancel', this.onPointerCancel);
        this.renderer.domElement.removeEventListener('wheel', this.onWheel);
        this.renderer.domElement.removeEventListener('contextmenu', this.onContextMenu);
        this.renderer.domElement.removeEventListener('keydown', this.onKeyDown);
        this.container.classList.remove('is-panning');
        this.container.classList.remove('is-selecting');
        this.marqueeElement.remove();
        for (const visual of this.pieceVisuals.values()) {
            for (const material of new Set(visual.materials))
                material.dispose();
        }
        this.pieceVisuals.clear();
        for (const geometry of new Set(this.sharedGeometry))
            geometry.dispose?.();
        for (const material of new Set(this.sharedMaterials))
            material.dispose?.();
        for (const texture of new Set(this.sharedTextures))
            texture.dispose?.();
        for (const texture of new Set(this.portraitTextures.values()))
            texture.dispose?.();
        this.portraitTextures.clear();
        this.scene.environment = null;
        this.environmentTarget?.dispose?.();
        this.environmentTarget = null;
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
//# sourceMappingURL=sandtable-scene.js.map