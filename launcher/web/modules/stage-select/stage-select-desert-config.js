// Validate only visual data. This module cannot change the authoritative stage catalog.
export const WORLD_STAGE_IDS = Object.freeze([
    'stage_34_0', 'stage_34_1', 'stage_34_2', 'stage_34_3', 'stage_34_4',
    'stage_34_5', 'stage_34_6', 'stage_34_7', 'stage_34_10'
]);

const SHORT_LABELS = ['难民营地', '临时补给点', '残垣断壁', 'A兵团基地', '军阀据点',
    '前线基地', '西谷秘密基地', '袭杀与圈套', '军阀外交'];
const SUBAREA_COUNTS = { stage_34_1: 3, stage_34_4: 4, stage_34_5: 4 };
export const MAX_DESERT_TRANSPORT_BYTES = 100 * 1024 * 1024;
export const MAX_DESERT_SCENE_BYTES = 256 * 1024 * 1024;

export function normalizeDesertTransport(value) {
    if (value === undefined) return null;
    if (!value || value.path !== 'scene.glb.gz' || value.encoding !== 'gzip'
        || typeof value.sha256 !== 'string' || !/^[a-f0-9]{64}$/i.test(value.sha256)
        || !Number.isSafeInteger(value.bytes) || value.bytes < 18 || value.bytes > MAX_DESERT_TRANSPORT_BYTES
        || !Number.isSafeInteger(value.decodedBytes) || value.decodedBytes < 20 || value.decodedBytes > MAX_DESERT_SCENE_BYTES) {
        throw new Error('Invalid desert scene transport');
    }
    return { path: value.path, encoding: value.encoding, sha256: value.sha256.toLowerCase(), bytes: value.bytes, decodedBytes: value.decodedBytes };
}

function vector(value, label) {
    if (!Array.isArray(value) || value.length !== 3 || value.some(n => !Number.isFinite(n) || Math.abs(n) >= 10000)) {
        throw new Error('Invalid desert visual vector: ' + label);
    }
    return value.slice();
}

export function normalizeDesertConfig(source) {
    if (!source || source.schema !== 1 || !source.camera || !source.pins) throw new Error('Invalid desert visual config');
    const ids = Object.keys(source.pins).sort();
    if (JSON.stringify(ids) !== JSON.stringify([...WORLD_STAGE_IDS].sort())) throw new Error('Desert visual stage identity mismatch');
    const camera = {
        gltfPosition: vector(source.camera.gltfPosition, 'camera position'),
        gltfTarget: vector(source.camera.gltfTarget, 'camera target'),
        horizontalSpan: source.camera.horizontalSpan,
        minSpan: source.camera.minSpan === undefined ? 1.5 : source.camera.minSpan,
        maxSpan: source.camera.maxSpan || Math.max(600, source.camera.horizontalSpan * 2)
    };
    if (!Number.isFinite(camera.minSpan) || camera.minSpan < 1.5 || camera.minSpan > camera.horizontalSpan
        || !Number.isFinite(camera.horizontalSpan) || camera.horizontalSpan < camera.minSpan || !Number.isFinite(camera.maxSpan)
        || camera.horizontalSpan > camera.maxSpan || camera.maxSpan > 5000
        || Math.hypot(...camera.gltfPosition.map((n, i) => n - camera.gltfTarget[i])) <= 1) {
        throw new Error('Invalid desert visual camera');
    }
    const pins = {};
    WORLD_STAGE_IDS.forEach((id, index) => {
        const pin = source.pins[id], bounds = pin.focusBounds;
        if (!bounds) throw new Error('Missing desert focus bounds: ' + id);
        const min = vector(bounds.min, id + ' minimum'), max = vector(bounds.max, id + ' maximum');
        if (min.some((n, i) => max[i] < n) || Math.hypot(...max.map((n, i) => n - min[i])) < 0.001) {
            throw new Error('Empty desert focus bounds: ' + id);
        }
        pins[id] = {
            worldAnchor: vector(pin.worldAnchor, id), focusBounds: { min, max },
            labelAnchor: 'DESERT_ANCHOR_' + id, building: 'DESERT_FOCUS_' + id,
            labelX: Number.isFinite(pin.labelX) ? pin.labelX : 0,
            labelY: Number.isFinite(pin.labelY) ? pin.labelY : -42,
            shortLabel: typeof pin.shortLabel === 'string' ? pin.shortLabel : SHORT_LABELS[index],
            labelWidth: Number.isFinite(pin.labelWidth) ? Math.max(80, Math.min(160, pin.labelWidth)) : 112,
            labelHeight: 30
        };
        if (pin.placeId !== undefined) {
            if (typeof pin.placeId !== 'string' || !/^[a-z][a-z0-9_-]{0,63}$/.test(pin.placeId)) throw new Error('Invalid desert place owner: ' + id);
            pins[id].placeId = pin.placeId;
        }
        if (pin.subareas !== undefined) {
            if (!Array.isArray(pin.subareas) || pin.subareas.length !== SUBAREA_COUNTS[id]) throw new Error('Invalid desert subarea count: ' + id);
            const names = new Set();
            pins[id].subareas = pin.subareas.map((area, index) => {
                if (!area || typeof area.id !== 'string' || !/^[a-z][a-z0-9_-]{0,63}$/.test(area.id) || area.id === 'whole'
                    || names.has(area.id) || area.subStageIndex !== index
                    || typeof area.label !== 'string' || !area.label.trim() || area.label.length > 80
                    || typeof area.sourceBackground !== 'string' || !area.sourceBackground || area.sourceBackground.length > 512
                    || !area.worldBounds) throw new Error('Invalid desert subarea identity: ' + id);
                names.add(area.id);
                const low = vector(area.worldBounds.min, area.id + ' minimum'), high = vector(area.worldBounds.max, area.id + ' maximum');
                if (low.some((n, i) => high[i] < n) || Math.hypot(...high.map((n, i) => n - low[i])) < 0.001) {
                    throw new Error('Empty desert subarea bounds: ' + id + '/' + area.id);
                }
                return { id: area.id, label: area.label, subStageIndex: area.subStageIndex, sourceBackground: area.sourceBackground,
                    worldBounds: { min: low, max: high }, worldCenter: vector(area.worldCenter, area.id + ' center') };
            });
        }
        if (pin.screenOffset !== undefined) {
            if (!Array.isArray(pin.screenOffset) || pin.screenOffset.length !== 2
                || pin.screenOffset.some(value => !Number.isFinite(value) || Math.abs(value) > 300)) {
                throw new Error('Invalid desert screen offset: ' + id);
            }
            pins[id].screenOffset = pin.screenOffset.slice();
        }
        if (Number.isFinite(pin.x)) pins[id].x = pin.x;
        if (Number.isFinite(pin.y)) pins[id].y = pin.y;
    });
    const sceneHash = source.assetHashes?.['scene.glb'] || source.sceneSha256;
    if (typeof sceneHash !== 'string' || !/^[a-f0-9]{64}$/i.test(sceneHash)) throw new Error('Missing desert scene fingerprint');
    return { camera, pins, assetHashes: { 'scene.glb': sceneHash.toLowerCase() }, lighting: source.lighting || {},
        sceneTransport: normalizeDesertTransport(source.sceneTransport) };
}

// Keep the GLB closure local and self-contained before GLTFLoader resolves resources.
export function validateEmbeddedGlb(bytes) {
    const view = new DataView(bytes);
    if (view.byteLength < 20 || view.getUint32(0, true) !== 0x46546c67 || view.getUint32(4, true) !== 2
        || view.getUint32(8, true) !== view.byteLength || view.getUint32(16, true) !== 0x4e4f534a) {
        throw new Error('Invalid desert GLB container');
    }
    const jsonLength = view.getUint32(12, true);
    if (jsonLength > view.byteLength - 20) throw new Error('Truncated desert GLB');
    const gltf = JSON.parse(new TextDecoder().decode(new Uint8Array(bytes, 20, jsonLength)));
    for (const resource of [...(gltf.buffers || []), ...(gltf.images || [])]) {
        if (resource.uri && !resource.uri.startsWith('data:')) throw new Error('Desert GLB has an external resource');
    }
    return gltf;
}

function overlaps(a, b, margin = 4) {
    return a.x < b.x + b.w + margin && b.x < a.x + a.w + margin
        && a.y < b.y + b.h + margin && b.y < a.y + a.h + margin;
}

// Move labels only. Their geographic markers remain exactly where the camera projects them.
export function layoutDesertPins(projected, screenPins, width = 1024, height = 576) {
    const pins = Object.fromEntries(Object.entries(projected).map(([id, pin]) => [id, { ...pin }]));
    const markers = Object.entries({ ...pins, ...screenPins }).map(([id, pin]) => ({ id, x: pin.x - 21, y: pin.y - 21, w: 42, h: 42 }));
    const placed = [
        { x: 0, y: 0, w: width, h: 56 }, { x: width - 112, y: 60, w: 108, h: 86 },
        { x: 620, y: 463, w: 404, h: 110 }, { x: 12, y: 520, w: 110, h: 50 }
    ];
    const failures = [];
    const order = ['stage_34_3', 'stage_34_5', 'stage_34_4', 'stage_34_6', 'stage_34_0',
        'stage_34_1', 'stage_34_2', 'stage_34_7', 'stage_34_10'];
    for (const id of order) {
        const pin = pins[id];
        if (!pin) continue;
        const half = pin.labelWidth / 2;
        const offsets = [[pin.labelX, pin.labelY], [0, -44], [0, 44], [-half - 28, 0], [half + 28, 0],
            [-half - 25, -46], [half + 25, -46], [-half - 25, 46], [half + 25, 46],
            [0, -82], [0, 82], [-half - 48, -80], [half + 48, -80], [-half - 48, 80], [half + 48, 80]];
        const choice = offsets.find(([dx, dy]) => {
            const rect = { x: pin.x + dx - half, y: pin.y + dy - 15, w: pin.labelWidth, h: 30 };
            return rect.x >= 8 && rect.y >= 58 && rect.x + rect.w <= width - 8 && rect.y + rect.h <= height - 8
                && placed.every(other => !overlaps(rect, other))
                && markers.every(other => !overlaps(rect, other));
        });
        if (choice) [pin.labelX, pin.labelY] = choice;
        else failures.push(id);
        placed.push({ x: pin.x + pin.labelX - half, y: pin.y + pin.labelY - 15, w: pin.labelWidth, h: 30 });
    }
    return { pins: { ...pins, ...screenPins }, failures };
}
