// 候选道路和水系的地表投影；道路宽度用于读图，不宣称真实路幅或通行能力。
const STYLES = {
  region: { road: 0.42, water: 0.28, step: 0.26, lift: 3.2, dash: 1.0 },
  city: { road: 0.12, water: 0.1, step: 0.075, lift: 0.9, dash: 0.42 },
  base: { road: 0.016, water: 0.012, step: 0.012, lift: 0.18, dash: 0.055 },
};
const COLORS = { civil: '#d8c6a0', military: '#865b4c', danger: '#a27c4d', boat: '#439ca4', surface: '#75a9ac', candidate: '#76c7c7', impaired: '#869fa3', optional: '#79afa0' };

const lengthOf = points => points.slice(1).reduce((sum, point, i) => sum + Math.hypot(point[0] - points[i][0], point[1] - points[i][1]), 0);
const lerp = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];

function clippedSegment(a, b, bounds, margin = 0) {
  const dx = b[0] - a[0], dy = b[1] - a[1];
  const p = [-dx, dx, -dy, dy];
  const q = [a[0] - bounds[0] - margin, bounds[1] - margin - a[0], a[1] - bounds[2] - margin, bounds[3] - margin - a[1]];
  let start = 0, end = 1;
  for (let i = 0; i < 4; i++) {
    if (Math.abs(p[i]) < 1e-12) { if (q[i] < 0) return null; continue; }
    const t = q[i] / p[i];
    if (p[i] < 0) start = Math.max(start, t); else end = Math.min(end, t);
    if (start > end) return null;
  }
  return [lerp(a, b, start), lerp(a, b, end)];
}

function visiblePaths(points, bounds, margin) {
  const paths = [];
  let current = null;
  for (let i = 1; i < points.length; i++) {
    const clipped = clippedSegment(points[i - 1], points[i], bounds, margin);
    if (!clipped) { current = null; continue; }
    if (current && Math.hypot(current.at(-1)[0] - clipped[0][0], current.at(-1)[1] - clipped[0][1]) < 1e-7) current.push(clipped[1]);
    else { current = clipped; paths.push(current); }
  }
  return paths;
}

function resolvedPoints(route, places) {
  return route.points.map(point => {
    if (Array.isArray(point)) return [...point];
    const place = places.get(point);
    if (!place) throw new Error(`道路 ${route.id} 引用未知地点：${point}`);
    return [...place.xy];
  });
}

function refinement(route, data, places, mode) {
  const points = resolvedPoints(route, places);
  if (mode !== 'base') return { points, refinement: null };
  if (route.id === 'a-waste') {
    const training = data.areas.find(area => area.id === 'training');
    const junctionIndex = route.points.indexOf('eastjunction');
    if (training && junctionIndex >= 0) {
      // 草图训练区南缘为 polygon[5]→[4]→[3]，外移路幅半宽及缓冲；不改场景锚点。
      const south = [training.polygon[5], training.polygon[4], training.polygon[3]];
      const clearance = STYLES.base.road / 2 + 0.045;
      const refined = [places.get('frontgate').xy,
        [south[0][0] - 0.28, south[0][1] - clearance],
        ...south.map(point => [point[0], point[1] - clearance]),
        ...points.slice(junctionIndex)];
      return {
        points: refined,
        refinement: { id: 'base-civil-training-south-edge', name: '日常道路沿训练区南缘的本地细化',
          unchangedAnchors: ['frontgate', 'field1', 'field2', 'field3', 'eastjunction'],
          note: '图1/2为场景锚点；日常路不必穿过炮位与弹着区。区域图保留同一接合关系，本图展开路侧距离。' },
      };
    }
  }
  if (route.id === 'assault') {
    const index = route.points.indexOf('eastjunction');
    if (index >= 0 && route.points[index + 1] === 'field2' && places.has('field3')) {
      points.splice(index + 1, 0, [...places.get('field3').xy]);
      return { points, refinement: { id: 'base-field3-return-link', name: '明确图3→图2→图1返程连接',
        unchangedAnchors: ['field3', 'field2', 'field1', 'frontgate'],
        note: '使原折线经过原位的图3锚点；不增加关卡或改变任何锚点坐标。' } };
    }
  }
  return { points, refinement: null };
}

function ribbonGeometry(THREE, paths, width, terrain, style, dashed) {
  const positions = [];
  let totalVisible = 0, maxExtraLiftM = 0;
  const emit = (a, b) => {
    const length = Math.hypot(b[0] - a[0], b[1] - a[1]);
    if (length < 1e-10) return;
    const nx = -(b[1] - a[1]) / length * width / 2;
    const ny = (b[0] - a[0]) / length * width / 2;
    const xy = [[a[0] + nx, a[1] + ny], [a[0] - nx, a[1] - ny], [b[0] + nx, b[1] + ny], [b[0] - nx, b[1] - ny]];
    const heights = xy.map(point => terrain.heightAt(...point));
    // 跨越地形三角形边界时，局部碎面需要额外的毫米至米级余量，避免路面插进坡折。
    let extra = 0;
    for (const t of [0.25, 0.5, 0.75]) for (const side of [0, 0.5, 1]) {
      const left = lerp(xy[0], xy[2], t), right = lerp(xy[1], xy[3], t);
      const point = lerp(left, right, side);
      // Render triangles: left-start/right-start/left-end, then right-start/right-end/left-end.
      const face = t + side <= 1
        ? heights[0] * (1 - t - side) + heights[1] * side + heights[2] * t
        : heights[1] * (1 - t) + heights[3] * (t + side - 1) + heights[2] * (1 - side);
      extra = Math.max(extra, terrain.heightAt(...point) - face);
    }
    maxExtraLiftM = Math.max(maxExtraLiftM, extra);
    const vertices = xy.map(point => terrain.world(point, style.lift + extra + 0.015));
    for (const index of [0, 1, 2, 1, 3, 2]) {
      const v = vertices[index]; positions.push(v.x, v.y, v.z);
    }
  };
  for (const path of paths) {
    let walked = 0;
    for (let i = 1; i < path.length; i++) {
      const a = path[i - 1], b = path[i];
      const length = Math.hypot(b[0] - a[0], b[1] - a[1]);
      const steps = Math.max(1, Math.ceil(length / style.step));
      totalVisible += length;
      for (let step = 0; step < steps; step++) {
        const t0 = step / steps, t1 = (step + 1) / steps;
        if (!dashed || Math.floor((walked + length * (t0 + t1) / 2) / style.dash) % 2 === 0) emit(lerp(a, b, t0), lerp(a, b, t1));
      }
      walked += length;
    }
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geometry.computeVertexNormals();
  geometry.computeBoundingSphere();
  return { geometry, totalVisible, maxExtraLiftM };
}

// Reuse the same draping for environmental field/canal traces; avoids a competing height sampler.
export function createGroundRibbon(THREE,points,terrain,options={}) {
  const width=options.width??.1;
  const paths=visiblePaths(points,terrain.bounds,width*.6);
  if(!paths.length)return null;
  return ribbonGeometry(THREE,paths,width,terrain,{step:options.step??.1,lift:options.lift??.3,dash:options.dash??.4},!!options.dashed);
}

/** Roads, visible surface water and a separately togglable subsurface/reference layer. */
export function createRoutes(THREE, data, mode, terrain) {
  const style = STYLES[mode];
  if (!style) throw new Error(`未知道路视图：${mode}`);
  const places = new Map(data.places.map(place => [place.id, place]));
  const group = new THREE.Group(), waterGroup = new THREE.Group(), surfaceGroup = new THREE.Group();
  group.name = `desert-roads-${mode}`; waterGroup.name = `desert-water-${mode}`;
  surfaceGroup.name=`SURFACE_WATER_${mode}`;
  const metrics = { mode, routes: [], water: [], localRefinements: [], roadCount: 0, waterCount: 0,
    note: 'lengthKm为候选折线平面长度；visibleLengthKm为当前裁切内长度；路幅符号放大，不代表实测道路。' };
  const materialCache = new Map();
  const add = (route, target, isWater) => {
    const result = isWater ? { points: resolvedPoints(route, places), refinement: null } : refinement(route, data, places, mode);
    const dashed = ['boat', 'candidate', 'optional', 'impaired'].includes(route.kind);
    const width = (isWater ? style.water : style.road) * (route.kind === 'military' ? 1.18 : route.kind === 'danger' ? 0.72 : 1);
    const paths = visiblePaths(result.points, terrain.bounds, width * 0.6);
    if (!paths.length) return;
    const built = ribbonGeometry(THREE, paths, width, terrain, style, dashed);
    const color = COLORS[route.kind] || COLORS.civil;
    const key = `${color}-${isWater}`;
    if (!materialCache.has(key)) materialCache.set(key, new THREE.MeshStandardMaterial({
      color, roughness: isWater && route.kind === 'surface' ? 0.65 : 1, metalness: 0,
      side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -1,
    }));
    const mesh = new THREE.Mesh(built.geometry, materialCache.get(key));
    mesh.name = route.id;
    mesh.renderOrder = isWater ? 3 : route.kind === 'military' ? 2 : 1;
    mesh.userData = { id: route.id, name: route.name, kind: route.kind, schematicSubsurface: dashed,
      localRefinement: result.refinement?.id || null, note: route.note || '', widthKm: width };
    target.add(mesh);
    const entry = { id: route.id, name: route.name, kind: route.kind, lengthKm: lengthOf(result.points),
      sourceLengthKm: lengthOf(resolvedPoints(route, places)), visibleLengthKm: built.totalVisible,
      widthKm: width, triangles: built.geometry.attributes.position.count / 3,
      maxDrapeLiftMeters: style.lift + built.maxExtraLiftM + 0.015,
      localRefinement: result.refinement?.id || null };
    (isWater ? metrics.water : metrics.routes).push(entry);
    if (result.refinement) metrics.localRefinements.push(result.refinement);
  };
  for (const route of data.routes) {
    if (!route.views?.includes(mode)) continue;
    add(route, route.kind === 'boat' ? waterGroup : group, route.kind === 'boat');
  }
  for (const water of data.water || []) add(water, water.kind==='surface'?surfaceGroup:waterGroup, true);
  metrics.roadCount = group.children.length; metrics.waterCount = waterGroup.children.length+surfaceGroup.children.length;
  group.userData = { kind: 'candidate-road-network', metrics };
  waterGroup.userData = { kind: 'water-network-overlay', note: '地下、失养或可选设施参考线；不能据高度证明重力流向。' };
  surfaceGroup.userData={kind:'surface-water-candidate',note:'沿母图的地表水候选；水质、通航和安全取用均未由灰模证明。'};
  return { group, waterGroup, surfaceGroup, metrics };
}
