/** Selected-place architectural detail for the regional appearance study only. */
const COLORS = {
  opening: '#303c35', glass: '#485a50', trim: '#b5b09a', seam: '#687565',
  steel: '#6c786c', rust: '#81684f', fabric: '#b5a788', tear: '#66654d',
};
const SLOT = /(?:^|_)(concrete|light|roof|dark|dry|pale|water)(?:_|$)/;
const PRIMARY = new Set(['base', 'fort', 'frontbase', 'industry', 'depot', 'secret', 'diplomacy', 'refugees', 'ruins', 'waste', 'fallen']);

function inherited(mesh, key, stop) {
  for (let item = mesh; item && item !== stop; item = item.parent) {
    if (item.userData?.[key]) return item.userData[key];
  }
  return '';
}

/**
 * Place group is attached to model.group, initially hidden. show() rebuilds from
 * the currently displayed mesh transforms, so enable the appearance study first.
 * No input geometry/material/transform is changed or disposed by this controller.
 */
export function createLocalDetail(THREE, model, data) {
  if (!model?.group || !model?.landmarks?.group || !model?.terrain) throw new Error('Local detail requires a graybox model.');
  if ((model.metrics?.mode || model.group.userData.mode) !== 'region') throw new Error('Local detail only supports the regional study.');
  const knownPlaces = new Map(data.places.map(place => [place.id, place]));
  const group = new THREE.Group();
  group.name = 'LOCAL_LANDMARK_DETAIL';
  group.visible = false;
  group.userData = { layerRole: 'selected_place_local_detail', candidate: true, notGameplayEntry: true };
  model.group.add(group);
  const ownedGeometries = new Set();
  const materials = {
    structure: new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.96, metalness: 0.025,
      flatShading: true, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -1 }),
    opening: new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.DoubleSide,
      polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 }),
  };
  let disposed = false;

  function clearGeometry() {
    group.clear();
    for (const geometry of ownedGeometries) geometry.dispose();
    ownedGeometries.clear();
  }

  function hide() {
    if (!disposed) group.visible = false;
  }

  function show(placeId) {
    if (disposed) return null;
    hide(); clearGeometry();
    const place = knownPlaces.get(placeId);
    const source = model.landmarks.anchors?.find(anchor => anchor.id === placeId)?.object
      || model.landmarks.group.children.find(child => child.userData.placeId === placeId);
    if (!place || !source) return null;
    model.group.updateMatrixWorld(true);
    const inverseModel = model.group.matrixWorld.clone().invert();
    const limit = placeId === 'base' ? 3000 : 2200;
    const stats = { placeId, triangles: 0, budget: limit, budgetHit: false, treatedBuildings: 0,
      windows: 0, doors: 0, roofDetails: 0, wallSections: 0, tentDetails: 0, cargoDetails: 0,
      visibleOnlyWhenSelected: true, detailsAreCandidate: true };
    const buckets = { structure: { positions: [], colors: [] }, opening: { positions: [], colors: [] } };
    const colors = Object.fromEntries(Object.entries(COLORS).map(([name, value]) => [name, new THREE.Color(value)]));
    const records = [];

    source.traverse(mesh => {
      if (!mesh.isMesh || !mesh.geometry?.getAttribute('position')) return;
      const bounds = mesh.geometry.boundingBox?.clone()
        || new THREE.Box3().setFromBufferAttribute(mesh.geometry.getAttribute('position'));
      const matrix = inverseModel.clone().multiply(mesh.matrixWorld);
      const normalMatrix = new THREE.Matrix3().getNormalMatrix(matrix);
      const dx = bounds.max.x - bounds.min.x, dy = bounds.max.y - bounds.min.y, dz = bounds.max.z - bounds.min.z;
      const sx = new THREE.Vector3().setFromMatrixColumn(matrix, 0).length();
      const sy = new THREE.Vector3().setFromMatrixColumn(matrix, 1).length();
      const sz = new THREE.Vector3().setFromMatrixColumn(matrix, 2).length();
      const center = bounds.getCenter(new THREE.Vector3()).applyMatrix4(matrix);
      const modelBounds = bounds.clone().applyMatrix4(matrix);
      const groundY = model.terrain.world([center.x, -center.z]).y;
      records.push({ mesh, bounds, matrix, normalMatrix, center, width: dx * sx, depth: dz * sz,
        height: dy * sy, gap: modelBounds.min.y - groundY, sx, sy, sz,
        role: inherited(mesh, 'designRole', model.landmarks.group),
        subareaId: inherited(mesh, 'subareaId', model.landmarks.group),
        slot: SLOT.exec(mesh.name)?.[1] || 'concrete',
        epsilon: Math.max(0.0008, Math.min(0.0025, Math.min(dx * sx, dz * sz) * 0.006)) });
    });

    function triangle(a, b, c, colorName, bucket = 'structure') {
      if (stats.triangles >= limit) { stats.budgetHit = true; return false; }
      const target = buckets[bucket], color = colors[colorName] || colors.trim;
      for (const point of [a, b, c]) {
        target.positions.push(point.x, point.y, point.z);
        target.colors.push(color.r, color.g, color.b);
      }
      stats.triangles++; return true;
    }
    function quad(points, colorName, bucket = 'structure') {
      if (stats.triangles + 2 > limit) { stats.budgetHit = true; return false; }
      triangle(points[0], points[1], points[2], colorName, bucket);
      triangle(points[0], points[2], points[3], colorName, bucket);
      return true;
    }
    function point(record, local, normal, extra = 0) {
      const result = new THREE.Vector3(...local).applyMatrix4(record.matrix);
      if (normal) result.addScaledVector(new THREE.Vector3(...normal).applyMatrix3(record.normalMatrix).normalize(), record.epsilon + extra);
      return result;
    }
    function faceRect(record, face, u0, v0, u1, v1, colorName, bucket = 'structure', extra = 0) {
      const { min, max } = record.bounds;
      const lerp = (a, b, t) => a + (b - a) * t;
      const local = (u, v) => {
        if (face === 'front' || face === 'back') return [lerp(min.x, max.x, u), lerp(min.y, max.y, v), face === 'front' ? max.z : min.z];
        if (face === 'left' || face === 'right') return [face === 'right' ? max.x : min.x, lerp(min.y, max.y, v), lerp(min.z, max.z, u)];
        return [lerp(min.x, max.x, u), max.y, lerp(min.z, max.z, v)];
      };
      const normal = face === 'front' ? [0, 0, 1] : face === 'back' ? [0, 0, -1]
        : face === 'right' ? [1, 0, 0] : face === 'left' ? [-1, 0, 0] : [0, 1, 0];
      const points = [[u0, v0], [u1, v0], [u1, v1], [u0, v1]].map(([u, v]) => point(record, local(u, v), normal, extra));
      if (['back', 'right', 'top'].includes(face)) points.reverse();
      return quad(points, colorName, bucket);
    }
    function window(record, face, u, v, width, height, damaged) {
      if (stats.triangles + 4 > limit) { stats.budgetHit = true; return; }
      faceRect(record, face, u - width / 2, v, u + width / 2, v + height, damaged ? 'seam' : 'trim');
      faceRect(record, face, u - width * 0.4, v + height * 0.12, u + width * 0.4, v + height * 0.85,
        damaged ? 'opening' : 'glass', 'opening', 0.00025);
      stats.windows++;
    }
    function facingCourt(record) {
      const target = new THREE.Vector3(place.xy[0] - record.center.x, 0, -place.xy[1] - record.center.z).normalize();
      let face = 'front', best = -Infinity;
      for (const [name, axis] of [['front', [0, 0, 1]], ['back', [0, 0, -1]], ['right', [1, 0, 0]], ['left', [-1, 0, 0]]]) {
        const dot = new THREE.Vector3(...axis).applyMatrix3(record.normalMatrix).normalize().dot(target);
        if (dot > best) { best = dot; face = name; }
      }
      return face;
    }
    function body(record) {
      const damaged = placeId === 'ruins' || (placeId === 'waste' && /残损|过渡|城缘/.test(record.role));
      const industrial = ['industry', 'depot'].includes(placeId) || /厂|仓|维修|装卸|物资/.test(record.role);
      const doorFace = facingCourt(record), doorWidth = industrial ? 0.46 : 0.17, doorHeight = industrial ? 0.58 : 0.31;
      const rows = industrial ? 1 : record.height > 0.85 ? 3 : 2;
      for (const face of ['front', 'back', 'left', 'right']) {
        const span = ['front', 'back'].includes(face) ? record.width : record.depth;
        const columns = Math.max(1, Math.min(placeId === 'base' ? 6 : 4, Math.floor(span / 0.24)));
        for (let row = 0; row < rows; row++) for (let col = 0; col < columns; col++) {
          const u = (col + 1) / (columns + 1), v = industrial ? 0.76 : 0.2 + row * (0.6 / rows);
          if (face === doorFace && v < doorHeight + 0.05 && Math.abs(u - 0.5) < doorWidth * 0.65) continue;
          if (damaged && (col + row) % 3 === 1) continue;
          window(record, face, u, v, Math.min(0.17, 0.54 / columns), industrial ? 0.1 : 0.11, damaged);
        }
        // A low band separates the wall from the ground without adding a foundation.
        faceRect(record, face, 0.02, 0.045, 0.98, 0.072, damaged ? 'rust' : 'seam');
      }
      if (!damaged) {
        faceRect(record, doorFace, 0.5 - doorWidth / 2 - 0.025, 0.015, 0.5 + doorWidth / 2 + 0.025, doorHeight + 0.035, 'trim');
        faceRect(record, doorFace, 0.5 - doorWidth / 2, 0.015, 0.5 + doorWidth / 2, doorHeight, 'opening', 'opening', 0.00025);
        if (industrial) for (const v of [0.12, 0.26, 0.4]) faceRect(record, doorFace, 0.5 - doorWidth * 0.47, v, 0.5 + doorWidth * 0.47, v + 0.013, 'steel', 'structure', 0.0004);
        stats.doors++;
      }
      stats.treatedBuildings++;
    }
    function roof(record) {
      // Existing flat cap only: parapet bands, seams and low vent footprints, no new roof volume.
      for (const [u0, v0, u1, v1] of [[0.025, 0.025, 0.975, 0.055], [0.025, 0.945, 0.975, 0.975], [0.025, 0.055, 0.055, 0.945], [0.945, 0.055, 0.975, 0.945]]) faceRect(record, 'top', u0, v0, u1, v1, 'seam');
      const industrial = ['industry', 'depot', 'commune'].includes(placeId) || /厂|仓|维修/.test(record.role);
      if (record.width > record.depth) faceRect(record, 'top', 0.07, 0.487, 0.93, 0.513, 'steel');
      else faceRect(record, 'top', 0.487, 0.07, 0.513, 0.93, 'steel');
      if (industrial) for (const u of [0.27, 0.68]) {
        faceRect(record, 'top', u - 0.065, 0.2, u + 0.065, 0.37, 'trim');
        for (const v of [0.235, 0.29, 0.345]) faceRect(record, 'top', u - 0.05, v, u + 0.05, v + 0.014, 'opening', 'opening', 0.00025);
      }
      stats.roofDetails++;
    }
    function wall(record) {
      const longX = record.width >= record.depth;
      const faces = longX ? ['front', 'back'] : ['left', 'right'];
      const damaged = ['ruins', 'waste'].includes(placeId);
      const count = Math.max(2, Math.min(12, Math.floor(Math.max(record.width, record.depth) / 0.22)));
      for (const face of faces) {
        faceRect(record, face, 0.02, 0.9, 0.98, 0.96, damaged ? 'rust' : 'trim');
        for (let i = 1; i < count; i++) {
          const u = i / count;
          faceRect(record, face, u - 0.008, damaged && i % 2 ? 0.22 : 0.06, u + 0.008, damaged ? 0.83 : 0.91, damaged ? 'opening' : 'seam');
        }
        if (damaged) faceRect(record, face, 0.15, 0.44, 0.83, 0.46, 'tear');
      }
      stats.wallSections++;
    }
    function cargo(record) {
      for (const face of ['front', 'right']) {
        faceRect(record, face, 0.045, 0.045, 0.955, 0.075, 'trim');
        for (const u of [0.24, 0.49, 0.74]) faceRect(record, face, u, 0.08, u + 0.019, 0.92, 'seam');
      }
      stats.cargoDetails++;
    }
    function tent(record) {
      const { min, max } = record.bounds, attribute = record.mesh.geometry.getAttribute('position');
      const ring = new Map();
      for (let i = 0; i < attribute.count; i++) {
        const p = [attribute.getX(i), attribute.getY(i), attribute.getZ(i)];
        if (Math.abs(p[1] - min.y) > 1e-5 || Math.hypot(p[0], p[2]) < 0.1) continue;
        ring.set(`${p[0].toFixed(5)},${p[2].toFixed(5)}`, p);
      }
      const base = [...ring.values()].sort((a, b) => Math.atan2(a[2], a[0]) - Math.atan2(b[2], b[0]));
      if (base.length < 3) return;
      const apex = [0, max.y, 0];
      for (let i = 0; i < base.length; i++) {
        const a = base[i], b = base[(i + 1) % base.length];
        const normal = new THREE.Vector3(...b).sub(new THREE.Vector3(...a)).cross(new THREE.Vector3(...apex).sub(new THREE.Vector3(...a))).normalize();
        if (normal.y < 0) normal.negate();
        const n = normal.toArray();
        const interpolate = (p, q, t) => p.map((v, k) => v + (q[k] - v) * t);
        const lowerA = interpolate(a, b, 0.04), lowerB = interpolate(a, b, 0.08);
        quad([point(record, lowerA, n), point(record, lowerB, n), point(record, interpolate(lowerB, apex, 0.94), n), point(record, interpolate(lowerA, apex, 0.94), n)], 'seam');
        if (i === 0) {
          const left = interpolate(a, b, 0.35), right = interpolate(a, b, 0.65);
          const mid = interpolate(interpolate(a, b, 0.5), apex, 0.64);
          triangle(point(record, left, n), point(record, right, n), point(record, mid, n), 'opening', 'opening');
        }
      }
      stats.tentDetails++;
    }

    const boxes = records.filter(record => record.mesh.geometry.type === 'BoxGeometry');
    const isWall = record => record.gap < 0.045 && record.height > 0.045
      && Math.max(record.width, record.depth) > 0.36 && Math.min(record.width, record.depth) / Math.max(record.width, record.depth) <= 0.2;
    const bodies = boxes.filter(record => record.gap < 0.035 && !isWall(record)
      && record.height > 0.12 && (record.width * record.depth > 0.17
        || (placeId === 'base' && record.width * record.depth > 0.08 && record.height > 1))
      && record.height / Math.max(record.width, record.depth) > 0.13)
      .sort((a, b) => b.width * b.depth * b.height - a.width * a.depth * a.height);
    for (const record of bodies.slice(0, PRIMARY.has(placeId) ? 12 : 7)) body(record);
    for (const record of records.filter(record => placeId === 'refugees' && record.mesh.geometry.type === 'ConeGeometry').slice(0, 12)) tent(record);
    for (const record of boxes.filter(record => record.slot === 'roof' && record.gap > 0.08
      && record.width * record.depth > 0.19 && record.height / Math.min(record.width, record.depth) < 0.2).slice(0, 14)) roof(record);
    for (const record of boxes.filter(isWall).sort((a, b) => Math.max(b.width, b.depth) - Math.max(a.width, a.depth)).slice(0, placeId === 'base' ? 12 : 10)) wall(record);
    for (const record of boxes.filter(record => ['depot', 'industry'].includes(placeId) && /物资|仓储/.test(record.role)
      && record.gap < 0.03 && record.width < 0.31 && record.depth < 0.35 && record.height > 0.05).slice(0, 12)) cargo(record);

    for (const [kind, bucket] of Object.entries(buckets)) {
      if (!bucket.positions.length) continue;
      const geometry = new THREE.BufferGeometry();
      geometry.setAttribute('position', new THREE.Float32BufferAttribute(bucket.positions, 3));
      geometry.setAttribute('color', new THREE.Float32BufferAttribute(bucket.colors, 3));
      geometry.computeVertexNormals(); geometry.computeBoundingSphere();
      ownedGeometries.add(geometry);
      const mesh = new THREE.Mesh(geometry, materials[kind]);
      mesh.name = `${placeId}_LOCAL_${kind}`;
      mesh.castShadow = false; mesh.receiveShadow = kind === 'structure'; mesh.renderOrder = 7;
      mesh.userData = { placeId, localDetail: true, candidate: true, notGameplayEntry: true };
      group.add(mesh);
    }
    group.userData.placeId = placeId;
    group.userData.metrics = stats;
    group.userData.binding = 'Generated from displayed source mesh matrixWorld into model-local coordinates; no input resource was changed.';
    group.visible = group.children.length > 0;
    group.updateMatrixWorld(true);
    return stats;
  }

  function dispose() {
    if (disposed) return;
    hide(); clearGeometry();
    for (const material of Object.values(materials)) material.dispose();
    group.removeFromParent();
    disposed = true;
  }
  return { show, hide, dispose, group };
}
