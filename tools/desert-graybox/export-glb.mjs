// Untextured graybox export only. Preserves editable groups, local transforms and semantic extras.
// Display coordinates are kilometres; the synthetic root converts all three axes to glTF metres.
export function encodeGlb(root, metadata = {}) {
  const doc = { asset: { version: '2.0', generator: 'CF7 desert graybox' }, scene: 0,
    scenes: [{ name: root.name, nodes: [0] }],
    nodes: [{ name: 'METRES_DISPLAY_HEIGHT_EXAGGERATED', scale: [1000, 1000, 1000], children: [], extras: metadata }],
    meshes: [], materials: [], accessors: [], bufferViews: [], buffers: [{ byteLength: 0 }] };
  const segments = [], geometryCache = new Map(), materialCache = new Map(); let byteLength = 0;
  function access(array, itemSize, componentType, target, extrema = false) {
    const bytes = new Uint8Array(array.buffer, array.byteOffset, array.byteLength);
    const padding = (4 - byteLength % 4) % 4;
    if (padding) { segments.push(new Uint8Array(padding)); byteLength += padding; }
    const view = doc.bufferViews.length;
    doc.bufferViews.push({ buffer: 0, byteOffset: byteLength, byteLength: bytes.byteLength, target });
    segments.push(bytes); byteLength += bytes.byteLength;
    const acc = { bufferView: view, componentType, count: array.length / itemSize, type: itemSize === 1 ? 'SCALAR' : 'VEC' + itemSize };
    if (extrema) {
      acc.min = Array(itemSize).fill(Infinity); acc.max = Array(itemSize).fill(-Infinity);
      for (let i = 0; i < array.length; i++) { const c = i % itemSize; acc.min[c] = Math.min(acc.min[c], array[i]); acc.max[c] = Math.max(acc.max[c], array[i]); }
    }
    doc.accessors.push(acc); return doc.accessors.length - 1;
  }
  function materialId(material) {
    if (materialCache.has(material)) return materialCache.get(material);
    if (material.map || material.normalMap || material.isShaderMaterial) throw new Error('Graybox exporter does not support textures or shaders');
    const color = material.color || { r: .5, g: .5, b: .5 };
    const item = { name: material.name || 'Graybox material',
      pbrMetallicRoughness: { baseColorFactor: [color.r, color.g, color.b, material.opacity ?? 1], metallicFactor: 0, roughnessFactor: .9 },
      doubleSided: material.side === 2 };
    if (material.transparent && material.opacity < 1) item.alphaMode = 'BLEND';
    doc.materials.push(item); materialCache.set(material, doc.materials.length - 1); return doc.materials.length - 1;
  }
  function attributes(geometry) {
    if (geometryCache.has(geometry)) return geometryCache.get(geometry);
    const output = {};
    for (const [name, semantic] of [['position', 'POSITION'], ['normal', 'NORMAL'], ['color', 'COLOR_0']]) {
      const a = geometry.getAttribute(name); if (!a) continue;
      const values = new Float32Array(a.count * a.itemSize);
      for (let i = 0; i < a.count; i++) for (let j = 0; j < a.itemSize; j++) values[i * a.itemSize + j] = a.getComponent(i, j);
      output[semantic] = access(values, a.itemSize, 5126, 34962, name === 'position');
    }
    geometryCache.set(geometry, output); return output;
  }
  function meshId(object) {
    if (object.isInstancedMesh || object.isSkinnedMesh) throw new Error('Expand instances before graybox export');
    const g = object.geometry, materials = [].concat(object.material), attr = attributes(g);
    const count = g.index ? g.index.count : g.attributes.position.count;
    const groups = Array.isArray(object.material) && g.groups.length ? g.groups : [{ start: 0, count, materialIndex: 0 }];
    const primitives = groups.map(part => {
      let max = 0; const indices = [];
      for (let i = part.start; i < Math.min(count, part.start + part.count); i++) { const v = g.index ? g.index.getX(i) : i; indices.push(v); max = Math.max(max, v); }
      const values = max <= 65535 ? new Uint16Array(indices) : new Uint32Array(indices);
      return { attributes: attr, indices: access(values, 1, max <= 65535 ? 5123 : 5125, 34963),
        material: materialId(materials[part.materialIndex] || materials[0]), mode: object.isLineSegments ? 1 : object.isLine ? 3 : 4 };
    });
    doc.meshes.push({ name: object.name || 'Graybox mesh', primitives }); return doc.meshes.length - 1;
  }
  function visit(object, parent) {
    if (object.userData?.reviewOnly) return;
    const n = { name: object.name || object.type };
    n.translation = object.position.toArray(); n.rotation = object.quaternion.toArray(); n.scale = object.scale.toArray();
    if (Object.keys(object.userData || {}).length) n.extras = JSON.parse(JSON.stringify(object.userData));
    if (!object.visible) n.extras = { ...n.extras, defaultVisible: false };
    if (object.isMesh || object.isLine) n.mesh = meshId(object);
    const id = doc.nodes.length; doc.nodes.push(n); (doc.nodes[parent].children ||= []).push(id);
    for (const child of object.children) visit(child, id);
  }
  visit(root, 0);
  const binaryPadding = (4 - byteLength % 4) % 4;
  if (binaryPadding) { segments.push(new Uint8Array(binaryPadding)); byteLength += binaryPadding; }
  doc.buffers[0].byteLength = byteLength;
  const jsonBytes = new TextEncoder().encode(JSON.stringify(doc)); const jsonLength = Math.ceil(jsonBytes.length / 4) * 4;
  const result = new Uint8Array(12 + 8 + jsonLength + 8 + byteLength), view = new DataView(result.buffer);
  view.setUint32(0, 0x46546c67, true); view.setUint32(4, 2, true); view.setUint32(8, result.length, true);
  view.setUint32(12, jsonLength, true); view.setUint32(16, 0x4e4f534a, true); result.fill(32, 20, 20 + jsonLength); result.set(jsonBytes, 20);
  const binaryOffset = 20 + jsonLength; view.setUint32(binaryOffset, byteLength, true); view.setUint32(binaryOffset + 4, 0x004e4942, true);
  let offset = binaryOffset + 8; for (const segment of segments) { result.set(segment, offset); offset += segment.length; }
  return result;
}
