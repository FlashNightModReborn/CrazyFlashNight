// Validate only visual data. Book identities and catalog stay authoritative elsewhere.
const MESH_NAME = /^(BOOK|LABEL|DISC|BOX)_[A-Za-z0-9_-]+$/;

function vector(value, label) {
    if (!Array.isArray(value) || value.length !== 3 || value.some(n => !Number.isFinite(n) || Math.abs(n) >= 10000)) {
        throw new Error('Invalid shelf visual vector: ' + label);
    }
    return value.slice();
}

export function normalizeShelfConfig(source) {
    if (!source || source.schema !== 'bookshelf-shelf.v1' || !source.camera || !source.entries) {
        throw new Error('Invalid shelf visual config');
    }
    const camera = {
        gltfPosition: vector(source.camera.gltfPosition, 'camera position'),
        gltfTarget: vector(source.camera.gltfTarget, 'camera target'),
        horizontalSpan: source.camera.horizontalSpan,
        minSpan: source.camera.minSpan,
        maxSpan: source.camera.maxSpan
    };
    if (!Number.isFinite(camera.horizontalSpan) || camera.horizontalSpan <= 0
        || !Number.isFinite(camera.minSpan) || camera.minSpan < 1 || camera.minSpan > camera.horizontalSpan
        || !Number.isFinite(camera.maxSpan) || camera.horizontalSpan > camera.maxSpan || camera.maxSpan > 5000
        || Math.hypot(...camera.gltfPosition.map((n, i) => n - camera.gltfTarget[i])) <= 1) {
        throw new Error('Invalid shelf visual camera');
    }
    const ids = Object.keys(source.entries);
    if (!ids.length || ids.length > 64) throw new Error('Invalid shelf visual entries');
    const entries = {};
    for (const id of ids) {
        const entry = source.entries[id];
        if (!/^[a-z0-9-]+$/.test(id) || !entry || !['book', 'box'].includes(entry.kind)
            || !Array.isArray(entry.meshes) || !entry.meshes.length || entry.meshes.length > 64
            || entry.meshes.some(name => typeof name !== 'string' || !MESH_NAME.test(name))) {
            throw new Error('Invalid shelf visual entry: ' + id);
        }
        entries[id] = { kind: entry.kind, meshes: entry.meshes.slice() };
    }
    const hoverPull = source.hoverPull;
    if (!Number.isFinite(hoverPull) || hoverPull < 0 || hoverPull > 10) throw new Error('Invalid shelf hover pull');
    const zone = source.archiveZone;
    if (!zone || !Number.isFinite(zone.leftEdge) || Math.abs(zone.leftEdge) >= 1000
        || !Number.isFinite(zone.width) || zone.width <= 0 || zone.width > 10
        || !Number.isFinite(zone.gap) || zone.gap < 0 || zone.gap > 5
        || !Number.isFinite(zone.height) || zone.height < 3 || zone.height > 30
        || !Number.isFinite(zone.depth) || zone.depth < 0.5 || zone.depth > 30
        || !Number.isFinite(zone.z) || Math.abs(zone.z) >= 1000
        || !Number.isFinite(zone.floorY) || zone.floorY < 0 || zone.floorY > 60
        || !Number.isInteger(zone.max) || zone.max < 1 || zone.max > 8
        || typeof zone.color !== 'string' || typeof zone.label !== 'string') {
        throw new Error('Invalid shelf archive zone');
    }
    const archiveZone = { leftEdge: zone.leftEdge, gap: zone.gap, width: zone.width, height: zone.height,
        depth: zone.depth, z: zone.z, floorY: zone.floorY, max: zone.max, color: zone.color, label: zone.label };
    const lighting = {};
    if (source.lighting && typeof source.lighting.background === 'string') lighting.background = source.lighting.background;
    const sceneHash = source.assetHashes && source.assetHashes['scene.glb'];
    if (typeof sceneHash !== 'string' || !/^[a-f0-9]{64}$/i.test(sceneHash)) throw new Error('Missing shelf scene fingerprint');
    return { camera, entries, hoverPull, archiveZone, lighting, assetHashes: { 'scene.glb': sceneHash.toLowerCase() } };
}

// Keep the GLB closure local and self-contained before GLTFLoader resolves resources.
export function validateEmbeddedGlb(bytes) {
    const view = new DataView(bytes);
    if (view.byteLength < 20 || view.getUint32(0, true) !== 0x46546c67 || view.getUint32(4, true) !== 2
        || view.getUint32(8, true) !== view.byteLength || view.getUint32(16, true) !== 0x4e4f534a) {
        throw new Error('Invalid shelf GLB container');
    }
    const jsonLength = view.getUint32(12, true);
    if (jsonLength > view.byteLength - 20) throw new Error('Truncated shelf GLB');
    const gltf = JSON.parse(new TextDecoder().decode(new Uint8Array(bytes, 20, jsonLength)));
    for (const resource of [...(gltf.buffers || []), ...(gltf.images || [])]) {
        if (resource.uri && !resource.uri.startsWith('data:')) throw new Error('Shelf GLB has an external resource');
    }
    return gltf;
}
