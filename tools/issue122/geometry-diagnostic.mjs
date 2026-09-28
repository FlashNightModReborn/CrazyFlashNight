import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../..');
const OUT = path.join(ROOT, 'tmp', 'issue122-linux');
const CITY = path.join(ROOT, 'launcher/web/assets/stage-diorama/fallen-city/city.glb');
const EXPECTED_SHA256 = 'd59783a2c63007bbb236955bb0aa2f9d4236b953128d387a182101b47f9ccf81';

const COMPONENT = {
  5120: { bytes: 1, read: 'getInt8' },
  5121: { bytes: 1, read: 'getUint8' },
  5122: { bytes: 2, read: 'getInt16' },
  5123: { bytes: 2, read: 'getUint16' },
  5125: { bytes: 4, read: 'getUint32' },
  5126: { bytes: 4, read: 'getFloat32' },
};
const COMPONENTS = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT2: 4, MAT3: 9, MAT4: 16 };

function parseGlb(file) {
  const raw = fs.readFileSync(file);
  assert.equal(raw.readUInt32LE(0), 0x46546c67, 'GLB magic');
  assert.equal(raw.readUInt32LE(4), 2, 'GLB version');
  assert.equal(raw.readUInt32LE(8), raw.length, 'GLB declared length');
  let offset = 12, json = null, bin = null;
  while (offset < raw.length) {
    assert.ok(offset + 8 <= raw.length, 'complete GLB chunk header');
    const length = raw.readUInt32LE(offset);
    const type = raw.readUInt32LE(offset + 4);
    const start = offset + 8, end = start + length;
    assert.ok(end <= raw.length, 'GLB chunk in range');
    if (type === 0x4e4f534a) json = JSON.parse(raw.subarray(start, end).toString('utf8').replace(/\0+$/u, '').trim());
    if (type === 0x004e4942) bin = raw.subarray(start, end);
    offset = end;
  }
  assert.ok(json && bin, 'GLB JSON + BIN chunks');
  assert.equal(json.buffers?.length, 1, 'single embedded GLB buffer');
  assert.ok(!json.buffers[0].uri, 'buffer is embedded');
  return { raw, gltf: json, bin };
}

function layout(gltf, accessorIndex) {
  const accessor = gltf.accessors[accessorIndex];
  assert.ok(accessor, 'accessor exists: ' + accessorIndex);
  assert.equal(accessor.sparse, undefined, 'sparse accessor not expected: ' + accessorIndex);
  const view = gltf.bufferViews[accessor.bufferView];
  assert.ok(view, 'bufferView exists: ' + accessor.bufferView);
  const component = COMPONENT[accessor.componentType];
  const width = COMPONENTS[accessor.type];
  assert.ok(component && width, 'supported accessor format');
  const elementBytes = component.bytes * width;
  const stride = view.byteStride || elementBytes;
  const relative = accessor.byteOffset || 0;
  const absolute = (view.byteOffset || 0) + relative;
  const endInView = accessor.count ? relative + (accessor.count - 1) * stride + elementBytes : relative;
  return { accessor, view, component, width, elementBytes, stride, absolute, endInView };
}

function readComponent(bin, info, element, componentIndex = 0) {
  const at = info.absolute + element * info.stride + componentIndex * info.component.bytes;
  const view = new DataView(bin.buffer, bin.byteOffset, bin.byteLength);
  return view[info.component.read](at, true);
}

function readVec3(bin, info, index) {
  return [readComponent(bin, info, index, 0), readComponent(bin, info, index, 1), readComponent(bin, info, index, 2)];
}

function distance(a, b) {
  const x = a[0] - b[0], y = a[1] - b[1], z = a[2] - b[2];
  return Math.hypot(x, y, z);
}

function percentile(sorted, p) {
  if (!sorted.length) return 0;
  return sorted[Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * p))];
}

function edgeSummary(values, diagonal) {
  values.sort();
  const threshold = r => {
    const t = diagonal * r;
    let lo = 0, hi = values.length;
    while (lo < hi) {
      const mid = (lo + hi) >>> 1;
      if (values[mid] <= t) lo = mid + 1; else hi = mid;
    }
    return values.length - lo;
  };
  return {
    count: values.length,
    p50: percentile(values, 0.50),
    p95: percentile(values, 0.95),
    p99: percentile(values, 0.99),
    max: values.length ? values[values.length - 1] : 0,
    maxOverBBoxDiagonal: diagonal ? (values.length ? values[values.length - 1] / diagonal : 0) : null,
    over10pctBBox: threshold(0.10),
    over25pctBBox: threshold(0.25),
    over50pctBBox: threshold(0.50),
  };
}

function simulateEdges(indices, positions, positionCount, transform) {
  const triangleCount = Math.floor(indices.length / 3);
  const edges = new Float64Array(triangleCount * 3);
  let invalid = 0, degenerate = 0;
  for (let t = 0; t < triangleCount; t++) {
    const raw = [indices[t * 3], indices[t * 3 + 1], indices[t * 3 + 2]];
    const tri = transform ? raw.map((value, lane) => transform(value, t * 3 + lane)) : raw;
    if (tri.some(v => v < 0 || v >= positionCount)) { invalid++; continue; }
    if (tri[0] === tri[1] || tri[1] === tri[2] || tri[0] === tri[2]) degenerate++;
    const a = positions(tri[0]), b = positions(tri[1]), c = positions(tri[2]);
    edges[t * 3] = distance(a, b);
    edges[t * 3 + 1] = distance(b, c);
    edges[t * 3 + 2] = distance(c, a);
  }
  return { edges, invalidTriangles: invalid, degenerateTriangles: degenerate };
}

function inspectAccessorRanges(gltf, bin) {
  const problems = [];
  gltf.accessors.forEach((_, index) => {
    const info = layout(gltf, index);
    if (info.absolute % info.component.bytes !== 0) problems.push({ accessor: index, kind: 'component_alignment', absolute: info.absolute, bytes: info.component.bytes });
    if (info.stride < info.elementBytes || info.stride % info.component.bytes !== 0) problems.push({ accessor: index, kind: 'stride', stride: info.stride, elementBytes: info.elementBytes });
    if (info.endInView > info.view.byteLength) problems.push({ accessor: index, kind: 'buffer_view_overrun', endInView: info.endInView, byteLength: info.view.byteLength });
    const absoluteEnd = (info.view.byteOffset || 0) + info.endInView;
    if (absoluteEnd > bin.length) problems.push({ accessor: index, kind: 'bin_overrun', absoluteEnd, binLength: bin.length });
  });
  return problems;
}

function main() {
  fs.mkdirSync(OUT, { recursive: true });
  const { raw, gltf, bin } = parseGlb(CITY);
  const sha256 = crypto.createHash('sha256').update(raw).digest('hex');
  assert.equal(sha256, EXPECTED_SHA256, 'city.glb SHA-256 identity');
  const accessorProblems = inspectAccessorRanges(gltf, bin);
  assert.deepEqual(accessorProblems, [], 'all accessors stay inside aligned buffer views');

  const nodesByMesh = new Map();
  (gltf.nodes || []).forEach((node, index) => {
    if (node.mesh === undefined) return;
    if (!nodesByMesh.has(node.mesh)) nodesByMesh.set(node.mesh, []);
    nodesByMesh.get(node.mesh).push({ index, name: node.name || '' });
  });

  const primitives = [];
  const uint32 = [];
  (gltf.meshes || []).forEach((mesh, meshIndex) => {
    (mesh.primitives || []).forEach((primitive, primitiveIndex) => {
      const positionAccessor = primitive.attributes?.POSITION;
      assert.notEqual(positionAccessor, undefined, 'primitive POSITION');
      const p = layout(gltf, positionAccessor);
      let index = null;
      if (primitive.indices !== undefined) {
        const i = layout(gltf, primitive.indices);
        assert.equal(i.width, 1, 'index accessor scalar');
        let max = -1, min = Infinity, outOfRange = 0, above65535 = 0, changedTriangles = 0;
        const values = new Uint32Array(i.accessor.count);
        for (let n = 0; n < i.accessor.count; n++) {
          const value = readComponent(bin, i, n);
          values[n] = value;
          if (value < min) min = value;
          if (value > max) max = value;
          if (value >= p.accessor.count) outOfRange++;
          if (value > 65535) above65535++;
          if (n % 3 === 2 && (values[n - 2] > 65535 || values[n - 1] > 65535 || values[n] > 65535)) changedTriangles++;
        }
        index = {
          accessor: primitive.indices,
          componentType: i.accessor.componentType,
          count: i.accessor.count,
          min,
          max,
          outOfRange,
          above65535,
          trianglesTouchingAbove65535: changedTriangles,
          byteOffset: i.absolute,
          byteStride: i.stride,
        };
        assert.equal(outOfRange, 0, 'all indices in position range');
        assert.equal(i.accessor.normalized, undefined, 'indices are not normalized');

        if (i.accessor.componentType === 5125) {
          const bboxMin = [Infinity, Infinity, Infinity], bboxMax = [-Infinity, -Infinity, -Infinity];
          let nonFinitePositions = 0;
          for (let n = 0; n < p.accessor.count; n++) {
            const v = readVec3(bin, p, n);
            if (!v.every(Number.isFinite)) { nonFinitePositions++; continue; }
            for (let k = 0; k < 3; k++) { if (v[k] < bboxMin[k]) bboxMin[k] = v[k]; if (v[k] > bboxMax[k]) bboxMax[k] = v[k]; }
          }
          assert.equal(nonFinitePositions, 0, 'finite positions');
          const diagonal = distance(bboxMin, bboxMax);
          const pos = n => readVec3(bin, p, n);
          const original = simulateEdges(values, pos, p.accessor.count, null);

          const truncated = simulateEdges(values, pos, p.accessor.count, value => value & 0xffff);

          // Counterfactual for a GL_UNSIGNED_SHORT draw over the same raw Uint32 EBO:
          // with the original element count, the GPU would consume low16/high16 words
          // from the first half of the 32-bit index stream.
          const reinterpretedIndices = new Uint32Array(values.length);
          for (let n = 0; n < values.length; n++) {
            const source = values[n >>> 1];
            reinterpretedIndices[n] = (n & 1) ? (source >>> 16) : (source & 0xffff);
          }
          const reinterpreted = simulateEdges(reinterpretedIndices, pos, p.accessor.count, null);

          uint32.push({
            meshIndex,
            meshName: mesh.name || '',
            primitiveIndex,
            nodes: nodesByMesh.get(meshIndex) || [],
            material: primitive.material ?? null,
            positionAccessor,
            positionCount: p.accessor.count,
            index,
            bbox: { min: bboxMin, max: bboxMax, diagonal },
            original: { ...edgeSummary(original.edges, diagonal), invalidTriangles: original.invalidTriangles, degenerateTriangles: original.degenerateTriangles },
            low16PerIndexCounterfactual: { ...edgeSummary(truncated.edges, diagonal), invalidTriangles: truncated.invalidTriangles, degenerateTriangles: truncated.degenerateTriangles },
            uint32BufferReinterpretedAsUint16Counterfactual: { ...edgeSummary(reinterpreted.edges, diagonal), invalidTriangles: reinterpreted.invalidTriangles, degenerateTriangles: reinterpreted.degenerateTriangles },
          });
        }
      }
      primitives.push({
        meshIndex,
        meshName: mesh.name || '',
        primitiveIndex,
        nodes: nodesByMesh.get(meshIndex) || [],
        mode: primitive.mode ?? 4,
        positionAccessor,
        positionCount: p.accessor.count,
        index,
      });
    });
  });

  assert.equal(uint32.length, 1, 'exactly one Uint32 indexed primitive');
  const suspect = uint32[0];
  assert.ok(suspect.nodes.some(n => n.name === 'P4_RENDER_P4_Static_plain') || suspect.meshName === 'P4_RENDER_P4_Static_plain',
    'Uint32 primitive is P4_RENDER_P4_Static_plain');
  assert.equal(suspect.positionCount, 272907, 'known suspect vertex count');
  assert.equal(suspect.index.count / 3, 172371, 'known suspect triangle count');

  const report = {
    schema: 1,
    asset: { path: path.relative(ROOT, CITY).replaceAll('\\', '/'), bytes: raw.length, sha256 },
    gltf: {
      generator: gltf.asset?.generator || null,
      version: gltf.asset?.version || null,
      extensionsUsed: gltf.extensionsUsed || [],
      extensionsRequired: gltf.extensionsRequired || [],
      meshes: gltf.meshes?.length || 0,
      nodes: gltf.nodes?.length || 0,
      accessors: gltf.accessors?.length || 0,
      bufferViews: gltf.bufferViews?.length || 0,
      primitives: primitives.length,
      indexComponentTypes: primitives.reduce((m, p) => {
        const key = p.index ? String(p.index.componentType) : 'none';
        m[key] = (m[key] || 0) + 1; return m;
      }, {}),
    },
    accessorProblems,
    suspect,
    conclusionInputs: {
      structuralIndexErrors: suspect.index.outOfRange,
      referencesAbove65535: suspect.index.above65535,
      trianglesDependingOn32BitRange: suspect.index.trianglesTouchingAbove65535,
      originalMaxEdgeOverBBoxDiagonal: suspect.original.maxOverBBoxDiagonal,
      truncatedMaxEdgeOverBBoxDiagonal: suspect.low16PerIndexCounterfactual.maxOverBBoxDiagonal,
      reinterpretedMaxEdgeOverBBoxDiagonal: suspect.uint32BufferReinterpretedAsUint16Counterfactual.maxOverBBoxDiagonal,
    },
  };
  fs.writeFileSync(path.join(OUT, 'geometry.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report, null, 2));
}

main();
