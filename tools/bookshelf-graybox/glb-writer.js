// Minimal GLB writer for the bookshelf graybox scene: fully embedded buffer,
// Uint16 indices, KHR_materials_unlit, PNG images carried as bufferViews.
// Geometry arrays come from the vendored three r180 builders in generate.js.
'use strict';

const COMPONENT = { 5120: 1, 5121: 1, 5122: 1, 5123: 2, 5125: 4, 5126: 4 };
const TYPE_SIZE = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 };

function align4(value) { return (value + 3) & ~3; }

function accessorFor(array, type, minMax) {
    const componentType = array instanceof Float32Array ? 5126
        : array instanceof Uint16Array ? 5123
        : array instanceof Uint32Array ? 5125 : 0;
    if (!componentType) throw new Error('Unsupported accessor array');
    const accessor = { componentType, count: array.length / TYPE_SIZE[type], type };
    if (minMax && type === 'VEC3') {
        const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
        for (let i = 0; i < array.length; i += 3) {
            for (let axis = 0; axis < 3; axis++) {
                min[axis] = Math.min(min[axis], array[i + axis]);
                max[axis] = Math.max(max[axis], array[i + axis]);
            }
        }
        accessor.min = min; accessor.max = max;
    }
    return { array, accessor };
}

// spec: {
//   geometries: {key: {position, normal, uv, color?, indices}},
//   materials: [{name, baseColorFactor?, texture?, doubleSided?}],
//   images: [{name, png}],
//   nodes: [{name, geometry, material, translation, scale}],
//   generator: string
// }
export function buildGlb(spec) {
    const buffers = [], bufferViews = [], accessors = [];
    let byteLength = 0;
    function push(array) {
        const offset = align4(byteLength);
        const data = Buffer.from(array.buffer, array.byteOffset, array.byteLength);
        buffers.push({ offset, data });
        bufferViews.push({ buffer: 0, byteOffset: offset, byteLength: data.length });
        byteLength = offset + data.length;
        return bufferViews.length - 1;
    }
    const geometryAccessors = {};
    for (const [key, geometry] of Object.entries(spec.geometries)) {
        const entry = {};
        for (const [attribute, type] of [['position', 'VEC3'], ['normal', 'VEC3'], ['uv', 'VEC2'], ['color', 'VEC3']]) {
            if (!geometry[attribute]) continue;
            const { array, accessor } = accessorFor(geometry[attribute], type, attribute === 'position');
            accessor.bufferView = push(array);
            accessor.byteOffset = 0;
            accessors.push(accessor);
            entry[attribute] = accessors.length - 1;
        }
        const indices = accessorFor(geometry.indices, 'SCALAR');
        indices.accessor.bufferView = push(indices.array);
        indices.accessor.byteOffset = 0;
        accessors.push(indices.accessor);
        entry.indices = accessors.length - 1;
        geometryAccessors[key] = entry;
    }
    const imageViews = spec.images.map(image => {
        const view = push(image.png);
        return { name: image.name, mimeType: 'image/png', bufferView: view };
    });
    const textures = imageViews.map((_, index) => ({ source: index }));
    const materials = spec.materials.map(material => {
        const pbr = { metallicFactor: 0, roughnessFactor: 1 };
        if (material.baseColorFactor) pbr.baseColorFactor = material.baseColorFactor;
        if (material.texture !== undefined) pbr.baseColorTexture = { index: material.texture };
        return { name: material.name, pbrMetallicRoughness: pbr, doubleSided: !!material.doubleSided,
            extensions: { KHR_materials_unlit: {} } };
    });
    const meshCache = new Map(), meshes = [];
    function meshIndex(geometry, material) {
        const key = geometry + '/' + material;
        if (!meshCache.has(key)) {
            const accessorsFor = geometryAccessors[geometry];
            const attributes = {};
            if (accessorsFor.position !== undefined) attributes.POSITION = accessorsFor.position;
            if (accessorsFor.normal !== undefined) attributes.NORMAL = accessorsFor.normal;
            if (accessorsFor.uv !== undefined) attributes.TEXCOORD_0 = accessorsFor.uv;
            if (accessorsFor.color !== undefined) attributes.COLOR_0 = accessorsFor.color;
            meshCache.set(key, meshes.length);
            meshes.push({ name: key, primitives: [{ attributes, indices: accessorsFor.indices, material }] });
        }
        return meshCache.get(key);
    }
    const nodes = spec.nodes.map(node => ({
        name: node.name, mesh: meshIndex(node.geometry, node.material),
        translation: node.translation, scale: node.scale
    }));
    const document = {
        asset: { version: '2.0', generator: spec.generator },
        scene: 0,
        scenes: [{ nodes: nodes.map((_, index) => index) }],
        nodes, meshes, materials,
        textures, images: imageViews,
        samplers: [{ magFilter: 9729, minFilter: 9987, wrapS: 10497, wrapT: 10497 }],
        bufferViews, accessors,
        buffers: [{ byteLength: align4(byteLength) }],
        extensionsUsed: ['KHR_materials_unlit']
    };
    const json = Buffer.from(JSON.stringify(document));
    const jsonPadded = Buffer.alloc(align4(json.length), 0x20); json.copy(jsonPadded);
    const bin = Buffer.alloc(align4(byteLength), 0);
    for (const part of buffers) part.data.copy(bin, part.offset);
    const total = 12 + 8 + jsonPadded.length + 8 + bin.length;
    const head = Buffer.alloc(12);
    head.writeUInt32LE(0x46546c67, 0); head.writeUInt32LE(2, 4); head.writeUInt32LE(total, 8);
    const jsonHead = Buffer.alloc(8);
    jsonHead.writeUInt32LE(jsonPadded.length, 0); jsonHead.writeUInt32LE(0x4e4f534a, 4);
    const binHead = Buffer.alloc(8);
    binHead.writeUInt32LE(bin.length, 0); binHead.writeUInt32LE(0x004e4942, 4);
    return Buffer.concat([head, jsonHead, jsonPadded, binHead, bin]);
}
