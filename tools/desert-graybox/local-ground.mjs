/**
 * Disposable close-view ground accents derived from existing graybox footprints.
 * No buildings, routes, water facilities, elevations or geographic anchors are
 * created or edited. These browser-only traces suggest the already named uses.
 */
const SUPPORTED = new Set(['base', 'fort', 'frontbase', 'depot', 'secret', 'diplomacy', 'industry',
  'ruins', 'ambush', 'refugees', 'commune', 'constitutional', 'receiving', 'communes', 'waste', 'fallen']);
const MAX_TRIANGLES = 1600;
const LIFT_METERS = 0.9;
const clamp = (v, lo = 0, hi = 1) => Math.max(lo, Math.min(hi, v));
const midpoint = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2];
const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
const cross = (a, b, c) => (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);

function pointSegmentDistance(p, a, b) {
  const dx = b[0] - a[0], dy = b[1] - a[1];
  const t = clamp(((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy || 1));
  return Math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy);
}

function insideTriangle(p, a, b, c) {
  const signs = [cross(a, b, p), cross(b, c, p), cross(c, a, p)];
  return !signs.some(v => v < -1e-9) || !signs.some(v => v > 1e-9);
}

function segmentDistance(a, b, c, d) {
  const abC = cross(a, b, c), abD = cross(a, b, d), cdA = cross(c, d, a), cdB = cross(c, d, b);
  if (abC * abD < 0 && cdA * cdB < 0) return 0;
  return Math.min(pointSegmentDistance(a, c, d), pointSegmentDistance(b, c, d),
    pointSegmentDistance(c, a, b), pointSegmentDistance(d, a, b));
}

function triangleSegmentDistance(a, b, c, start, end) {
  if (insideTriangle(start, a, b, c) || insideTriangle(end, a, b, c)) return 0;
  return Math.min(segmentDistance(a, b, start, end), segmentDistance(b, c, start, end), segmentDistance(c, a, start, end));
}

function makeMaterial(THREE, name, color, opacity) {
  const material = new THREE.MeshStandardMaterial({ color, opacity, transparent: true,
    roughness: 1, metalness: 0, depthWrite: false, side: THREE.DoubleSide,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 });
  material.name = `LOCAL_GROUND_${name}`;
  material.userData = { browserOnly: true, localGroundAccent: true };
  material.onBeforeCompile = shader => {
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nattribute float localGroundAlpha;\nvarying float vGroundAlpha;\nvarying vec2 vGroundXY;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvGroundAlpha=localGroundAlpha;\nvGroundXY=position.xz;');
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', '#include <common>\nvarying float vGroundAlpha;\nvarying vec2 vGroundXY;')
      .replace('#include <color_fragment>', `#include <color_fragment>
        float localGrain=sin(vGroundXY.x*25.3+sin(vGroundXY.y*17.1))*sin(vGroundXY.y*23.7+vGroundXY.x*7.9);
        float localPixel=max(length(dFdx(vGroundXY*25.3)),length(dFdy(vGroundXY*25.3)));
        diffuseColor.rgb*=1.0+localGrain*0.035*(1.0-smoothstep(0.6,2.0,localPixel));
        diffuseColor.a*=clamp(vGroundAlpha,0.0,1.0);`);
  };
  material.customProgramCacheKey = () => 'desert-local-ground-v1';
  return material;
}

export function createLocalGround(THREE, model, data) {
  const group = new THREE.Group();
  group.name = 'BROWSER_LOCAL_GROUND';
  group.visible = false;
  group.userData = { role: 'Browser-only close-view ground traces from existing functional masses',
    localGroundOnly: true, candidate: true, noNewFacilities: true, triangleBudget: MAX_TRIANGLES };
  model.group.add(group);
  const materials = {
    foundation: makeMaterial(THREE, 'FOUNDATION', '#645f52', 0.28),
    work: makeMaterial(THREE, 'WORK_APRON', '#777362', 0.33),
    worn: makeMaterial(THREE, 'WORN_EARTH', '#b4a185', 0.42),
    court: makeMaterial(THREE, 'COURT_EDGE', '#a99d85', 0.35),
  };
  const places = new Map(data.places.map(place => [place.id, place]));
  const roadMetrics = new Map((model.routes?.metrics?.routes || []).map(route => [route.id, route]));
  const point = p => typeof p === 'string' ? places.get(p)?.xy : p;
  const protectedLines = [];
  for (const route of data.routes || []) {
    if (route.kind === 'boat') continue;
    const points = route.points.map(point).filter(Boolean);
    const width = roadMetrics.get(route.id)?.widthKm ?? 0.42 * (route.kind === 'military' ? 1.18 : route.kind === 'danger' ? 0.72 : 1);
    for (let i = 1; i < points.length; i++) protectedLines.push({ a: points[i - 1], b: points[i], clearance: width / 2 + 0.055, kind: 'road' });
  }
  for (const water of data.water || []) {
    if (water.kind !== 'surface') continue;
    const points = water.points.map(point).filter(Boolean);
    for (let i = 1; i < points.length; i++) protectedLines.push({ a: points[i - 1], b: points[i], clearance: 0.23, kind: 'surface-water' });
  }
  let currentId = null, disposed = false;
  function clearGeometry() {
    for (const child of [...group.children]) {
      child.geometry?.dispose();
      group.remove(child);
    }
  }
  function hide() { if (!disposed) group.visible = false; }

  function show(placeId) {
    if (disposed) return false;
    if ((model.metrics?.mode || model.group.userData.mode) !== 'region' || !SUPPORTED.has(placeId)) {
      hide(); return false;
    }
    const anchor = model.anchors.find(item => item.id === placeId);
    const place = places.get(placeId);
    if (!anchor || !place) { hide(); return false; }
    if (currentId === placeId && group.children.length) { group.visible = true; return true; }
    clearGeometry(); currentId = placeId;
    model.group.updateMatrixWorld(true);
    const terrain = model.terrain, exaggeration = terrain.verticalExaggeration || 1;
    const buffers = Object.fromEntries(Object.keys(materials).map(key => [key, { positions: [], alpha: [], roles: new Set() }]));
    const metrics = { placeId, triangles: 0, patches: 0, traces: 0, rejectedRoadOrGate: 0, rejectedSlope: 0,
      maxSampledDrapeErrorMeters: 0, liftMeters: LIFT_METERS, maxTriangles: MAX_TRIANGLES };
    const meshBox = new THREE.Box3(), dimensions = new THREE.Vector3(), center = new THREE.Vector3();
    const placeBounds = new THREE.Box3().setFromObject(anchor.object);
    const gateDiscs = [];
    const recordedGates = anchor.object.userData.gateOpenings;
    if (Array.isArray(recordedGates)) {
      for (const gate of recordedGates) if (gate.geographicXY) gateDiscs.push({ xy: gate.geographicXY, radius: (gate.symbolicOpeningKm || 0.4) / 2 + 0.085 });
    } else if (placeId === 'base' && recordedGates) {
      const scale = anchor.object.userData.footprintScale || 1;
      for (const xy of Object.values(recordedGates)) if (Array.isArray(xy)) gateDiscs.push({
        xy: [place.xy[0] + xy[0] * scale, place.xy[1] + xy[1] * scale], radius: scale * 0.065 });
    }
    const localLines = protectedLines.filter(line => {
      const middle = [(placeBounds.min.x + placeBounds.max.x) / 2, -(placeBounds.min.z + placeBounds.max.z) / 2];
      const radius = Math.hypot(placeBounds.max.x - placeBounds.min.x, placeBounds.max.z - placeBounds.min.z) / 2 + 2;
      return pointSegmentDistance(middle, line.a, line.b) < radius;
    });
    function protectedTriangle(a, b, c) {
      if (localLines.some(line => triangleSegmentDistance(a, b, c, line.a, line.b) < line.clearance)) return true;
      return gateDiscs.some(gate => insideTriangle(gate.xy, a, b, c) ||
        Math.min(pointSegmentDistance(gate.xy, a, b), pointSegmentDistance(gate.xy, b, c), pointSegmentDistance(gate.xy, c, a)) < gate.radius);
    }

    function emitTriangle(style, role, a, b, c, depth = 0) {
      if (metrics.triangles >= MAX_TRIANGLES || Math.abs(cross(a, b, c)) < 1e-11) return;
      const heights = [a, b, c].map(p => terrain.heightAt(p[0], p[1]));
      const ab = midpoint(a, b), bc = midpoint(b, c), ca = midpoint(c, a);
      const centroid = [(a[0] + b[0] + c[0]) / 3, (a[1] + b[1] + c[1]) / 3];
      const errors = [[ab, (heights[0] + heights[1]) / 2], [bc, (heights[1] + heights[2]) / 2],
        [ca, (heights[2] + heights[0]) / 2], [centroid, (heights[0] + heights[1] + heights[2]) / 3]];
      const drapeError = Math.max(...errors.map(([p, h]) => Math.abs(terrain.heightAt(p[0], p[1]) - h)));
      const lengths = [distance(a, b), distance(b, c), distance(c, a)];
      const longest = Math.max(...lengths), blocked = protectedTriangle(a, b, c);
      if (depth < 7 && (longest > 0.34 || drapeError > 0.18 || (blocked && longest > 0.1))) {
        const edge = lengths.indexOf(longest);
        if (edge === 0) { emitTriangle(style, role, a, ab, c, depth + 1); emitTriangle(style, role, ab, b, c, depth + 1); }
        else if (edge === 1) { emitTriangle(style, role, a, b, bc, depth + 1); emitTriangle(style, role, a, bc, c, depth + 1); }
        else { emitTriangle(style, role, a, b, ca, depth + 1); emitTriangle(style, role, ca, b, c, depth + 1); }
        return;
      }
      if (blocked) { metrics.rejectedRoadOrGate++; return; }
      if (drapeError > 0.48) { metrics.rejectedSlope++; return; }
      const bounds = terrain.bounds;
      if ([a, b, c].some(p => p[0] < bounds[0] || p[0] > bounds[1] || p[1] < bounds[2] || p[1] > bounds[3])) return;
      const buffer = buffers[style];
      for (const p of [a, b, c]) {
        const world = terrain.world([p[0], p[1]], LIFT_METERS);
        buffer.positions.push(world.x, world.y, world.z); buffer.alpha.push(p[2]);
      }
      buffer.roles.add(role); metrics.triangles++;
      metrics.maxSampledDrapeErrorMeters = Math.max(metrics.maxSampledDrapeErrorMeters, drapeError);
    }

    function patch(style, role, xy, rx, ry, rotation, seed = 0) {
      if (rx < 0.025 || ry < 0.025) return;
      const cs = Math.cos(rotation), sn = Math.sin(rotation), outer = [], inner = [];
      for (let i = 0; i < 8; i++) {
        const angle = i * Math.PI / 4;
        const irregular = 0.89 + Math.sin(i * 2.07 + seed * 1.31) * 0.08;
        const x = Math.cos(angle) * rx * irregular, y = Math.sin(angle) * ry * irregular;
        outer.push([xy[0] + x * cs - y * sn, xy[1] + x * sn + y * cs, 0]);
        inner.push([xy[0] + (x * cs - y * sn) * 0.64, xy[1] + (x * sn + y * cs) * 0.64, 0.8]);
      }
      for (let i = 0; i < 8; i++) {
        const j = (i + 1) % 8;
        emitTriangle(style, role, [...xy, 0.9], inner[i], inner[j]);
        emitTriangle(style, role, inner[i], outer[i], outer[j]);
        emitTriangle(style, role, inner[i], outer[j], inner[j]);
      }
      metrics.patches++;
    }

    function trace(style, role, points, width, strength = 0.65) {
      for (let i = 1; i < points.length; i++) {
        const a = points[i - 1], b = points[i], len = distance(a, b);
        if (len < 1e-7) continue;
        const offset = [-(b[1] - a[1]) / len * width / 2, (b[0] - a[0]) / len * width / 2];
        const leftA = [a[0] + offset[0], a[1] + offset[1], 0], leftB = [b[0] + offset[0], b[1] + offset[1], 0];
        const rightA = [a[0] - offset[0], a[1] - offset[1], 0], rightB = [b[0] - offset[0], b[1] - offset[1], 0];
        const midA = [...a, strength], midB = [...b, strength];
        emitTriangle(style, role, leftA, midA, leftB); emitTriangle(style, role, midA, midB, leftB);
        emitTriangle(style, role, midA, rightA, midB); emitTriangle(style, role, rightA, rightB, midB);
      }
      metrics.traces++;
    }

    const knownZones = anchor.object.children.filter(child => child.isGroup && child.userData.designRole);
    const zones = knownZones.length ? knownZones : [anchor.object];
    const footprints = [];
    for (const zone of zones) {
      const role = zone.userData.designRole || (placeId === 'ruins' ? '残损聚落' : placeId === 'base' ? '基地院区' : place.name);
      const subareaId = zone.userData.subareaId || '';
      // Land-use traces and water-point pieces are already separate systems.
      if (/田|耕地|街坊联系|水点|水源/.test(role)) continue;
      zone.traverse(mesh => {
        if (!mesh.isMesh || mesh.userData.localGroundOnly || mesh.userData.facadeDetail || mesh.userData.styleDetail) return;
        meshBox.setFromObject(mesh); meshBox.getSize(dimensions); meshBox.getCenter(center);
        if (![...dimensions.toArray(), ...center.toArray()].every(Number.isFinite)) return;
        const width = dimensions.x, depth = dimensions.z, heightM = dimensions.y / exaggeration * 1000;
        const baseGapM = (meshBox.min.y - terrain.world([center.x, -center.z]).y) / exaggeration * 1000;
        const minimumHeight = placeId === 'refugees' && /住/.test(role) ? 1.2 : 5;
        if (Math.min(width, depth) < 0.065 || Math.max(width, depth) > 4.4 || heightM < minimumHeight || baseGapM > 2.3) return;
        footprints.push({ role, subareaId, xy: [center.x, -center.z], width, depth,
          area: width * depth, heightM, rotation: 0 });
      });
    }
    // Deduplicate coincident sub-masses, then bound work independently of city size.
    footprints.sort((a, b) => b.area - a.area);
    const chosen = [];
    for (const footprint of footprints) {
      if (chosen.some(other => distance(footprint.xy, other.xy) < Math.min(footprint.width, footprint.depth) * 0.35)) continue;
      chosen.push(footprint); if (chosen.length === (placeId === 'refugees' ? 9 : 12)) break;
    }
    chosen.forEach((f, index) => {
      const housing = /住|村/.test(f.role) || placeId === 'refugees';
      const style = housing ? 'worn' : 'foundation';
      const radiusX = Math.min(1.5, f.width * 0.72), radiusY = Math.min(1.15, f.depth * 0.78);
      patch(style, f.role, f.xy, radiusX, radiusY, f.rotation, index + 3);
      if (/维修|生产|仓|转运/.test(f.role)) {
        const towardAnchor = [place.xy[0] - f.xy[0], place.xy[1] - f.xy[1]];
        const length = Math.hypot(...towardAnchor) || 1;
        const direction = towardAnchor.map(value => value / length);
        const side = [-direction[1], direction[0]];
        const front = [f.xy[0] + direction[0] * radiusX * 0.78, f.xy[1] + direction[1] * radiusY * 0.78];
        patch('work', f.role, front, Math.min(0.42, radiusX * 0.48), Math.min(0.23, radiusY * 0.35), Math.atan2(side[1], side[0]), index);
        if (index < 5) for (const sign of [-1, 1]) {
          const a = [front[0] + side[0] * 0.035 * sign, front[1] + side[1] * 0.035 * sign];
          const b = [a[0] + direction[0] * 0.32, a[1] + direction[1] * 0.32];
          trace('work', f.role, [a, b], 0.035, 0.52);
        }
      }
    });

    // Existing explicitly unbuilt courts supply useful empty space without
    // inventing buildings or turning an entire compound into a paved rectangle.
    const yards = anchor.object.userData.openYards || [];
    const mainRoute = data.routes.find(route => route.id === anchor.object.userData.geographicHeadingFromRoute);
    let heading = 0;
    if (mainRoute) {
      const at = mainRoute.points.indexOf(placeId), next = point(mainRoute.points[at + 1] ?? mainRoute.points[at - 1]);
      if (next) heading = Math.atan2(next[0] - place.xy[0], -(next[1] - place.xy[1]));
    }
    yards.slice(0, 3).forEach((yard, index) => {
      const role = yard.designRole || '既有场坪';
      patch(/维修|调车|货|生产/.test(role) ? 'work' : 'court', role, yard.centerXY,
        yard.symbolicWidthKm * 0.42, yard.symbolicDepthKm * 0.33, heading, index + 11);
      const dx = Math.cos(heading) * yard.symbolicWidthKm * 0.3, dy = Math.sin(heading) * yard.symbolicWidthKm * 0.3;
      trace('worn', role, [[yard.centerXY[0] - dx, yard.centerXY[1] - dy], yard.centerXY,
        [yard.centerXY[0] + dx, yard.centerXY[1] + dy]], 0.065, 0.6);
    });

    if (placeId === 'refugees') {
      chosen.slice(0, 6).forEach((f, index) => {
        const dx = place.xy[0] - f.xy[0], dy = place.xy[1] - f.xy[1];
        const start = [f.xy[0] + dx * 0.24, f.xy[1] + dy * 0.24];
        const elbow = [f.xy[0] + dx * 0.7 + (index % 2 ? 0.04 : -0.04), f.xy[1] + dy * 0.72];
        trace('worn', '临时住区到达痕迹', [start, elbow], 0.047, 0.58);
      });
    }
    if (placeId === 'ruins') chosen.slice(0, 5).forEach((f, index) => {
      const a = [f.xy[0] - f.width * 0.38, f.xy[1] - f.depth * 0.32];
      const b = [f.xy[0] + f.width * 0.35, f.xy[1] - f.depth * 0.32];
      const d = [b[0], f.xy[1] + f.depth * (index % 2 ? 0.18 : 0.35)];
      trace('court', '既有残损基址的断续边缘', [a, b, d], 0.06, 0.57);
    });
    for (const zone of zones) {
      const role = zone.userData.designRole || '';
      if (!/前场|空地|交割面|公共院落/.test(role)) continue;
      const box = new THREE.Box3().setFromObject(zone), size = box.getSize(new THREE.Vector3()), at = box.getCenter(new THREE.Vector3());
      if (box.isEmpty()) continue;
      patch('court', role, [at.x, -at.z], Math.min(0.6, size.x * 0.34), Math.min(0.48, size.z * 0.3), 0, 23);
    }

    for (const [style, buffer] of Object.entries(buffers)) {
      if (!buffer.positions.length) continue;
      const geometry = new THREE.BufferGeometry();
      geometry.setAttribute('position', new THREE.Float32BufferAttribute(buffer.positions, 3));
      geometry.setAttribute('localGroundAlpha', new THREE.Float32BufferAttribute(buffer.alpha, 1));
      geometry.computeVertexNormals(); geometry.computeBoundingSphere();
      const mesh = new THREE.Mesh(geometry, materials[style]);
      mesh.name = `LOCAL_GROUND_${placeId}_${style}`;
      mesh.castShadow = false; mesh.receiveShadow = true; mesh.renderOrder = 0;
      mesh.userData = { placeId, localGroundOnly: true, style, sourceRoles: [...buffer.roles],
        source: 'existing functional groups, footprints and openYards', liftMeters: LIFT_METERS };
      group.add(mesh);
    }
    group.userData.placeId = placeId;
    group.userData.metrics = metrics;
    group.visible = group.children.length > 0;
    return group.visible;
  }

  function dispose() {
    if (disposed) return;
    clearGeometry();
    for (const material of Object.values(materials)) material.dispose();
    group.removeFromParent(); group.visible = false;
    currentId = null; disposed = true;
  }
  return { show, hide, dispose, group };
}
