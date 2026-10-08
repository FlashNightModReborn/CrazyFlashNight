// 草图地形：高程仅为设计剖面；不代表实测海拔、地质或弹道结论。
const VIEW_STYLE = {
  region: { exaggeration: 3.2, floorMeters: -620 },
  city: { exaggeration: 12, floorMeters: -85 },
  base: { exaggeration: 8, floorMeters: -24 },
};

const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
const smooth = (lo, hi, v) => {
  const t = clamp((v - lo) / (hi - lo), 0, 1);
  return t * t * (3 - 2 * t);
};
const bump = (x, y, cx, cy, sx, sy) => Math.exp(-(((x - cx) / sx) ** 2) - ((y - cy) / sy) ** 2);

function segmentDistance(x, y, a, b) {
  const dx = b[0] - a[0], dy = b[1] - a[1];
  const t = clamp(((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy || 1), 0, 1);
  return Math.hypot(x - a[0] - t * dx, y - a[1] - t * dy);
}

function pathDistance(x, y, points) {
  let distance = Infinity;
  for (let i = 1; i < points.length; i++) distance = Math.min(distance, segmentDistance(x, y, points[i - 1], points[i]));
  return distance;
}

function polygonDistance(x, y, polygon) {
  let inside = false, distance = Infinity;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const a = polygon[j], b = polygon[i];
    distance = Math.min(distance, segmentDistance(x, y, a, b));
    if ((a[1] > y) !== (b[1] > y) && x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
  }
  return inside ? distance : -distance;
}

function locate(axis, value) {
  let lo = 0, hi = axis.length - 1;
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1;
    if (axis[mid] <= value) lo = mid; else hi = mid;
  }
  return lo;
}

// 所有视图共用这一组采样坐标；切换视图不会重新发明高度或移动锚点。
function sharedAxes(data) {
  const globalBounds = [Infinity, -Infinity, Infinity, -Infinity];
  for (const view of Object.values(data.views)) {
    globalBounds[0] = Math.min(globalBounds[0], view.bounds[0]);
    globalBounds[1] = Math.max(globalBounds[1], view.bounds[1]);
    globalBounds[2] = Math.min(globalBounds[2], view.bounds[2]);
    globalBounds[3] = Math.max(globalBounds[3], view.bounds[3]);
  }
  const axes = [new Set(), new Set()];
  const add = (axis, value) => axes[axis].add(Number(value.toFixed(7)));
  const fill = (bounds, spacing) => {
    for (let axis = 0; axis < 2; axis++) {
      const start = bounds[axis * 2], end = bounds[axis * 2 + 1];
      const steps = Math.ceil((end - start) / spacing);
      for (let i = 0; i <= steps; i++) add(axis, start + (end - start) * i / steps);
    }
  };
  fill(globalBounds, 6);
  if (data.views.city) fill(data.views.city.bounds, 2.5);
  if (data.views.base) fill(data.views.base.bounds, 0.14);
  const plateau = data.areas.find(area => area.id === 'plateau')?.polygon;
  if (plateau) {
    // 坡顶、坡脚及斜边中点进入共享网格，避免粗网格把低台地重新插成整片缓坡。
    for (let i = 0; i < plateau.length; i++) {
      const a = plateau[i], b = plateau[(i + 1) % plateau.length];
      for (const offset of [-0.04, 0, 0.04]) {
        add(0, a[0] + offset); add(1, a[1] + offset);
      }
      add(0, (a[0] + b[0]) / 2); add(1, (a[1] + b[1]) / 2);
    }
  }
  for (const place of data.places) {
    add(0, place.xy[0]);
    add(1, place.xy[1]);
  }
  for (const view of Object.values(data.views)) {
    add(0, view.bounds[0]); add(0, view.bounds[1]);
    add(1, view.bounds[2]); add(1, view.bounds[3]);
  }
  return axes.map(axis => [...axis].sort((a, b) => a - b));
}

function physicalField(data, places) {
  const snow = places.get('snow')?.xy || [-65, 93];
  const foothill = places.get('foothill')?.xy || [-39, 72];
  const west = places.get('secret')?.xy || [-44, 14];
  const industry = places.get('industry')?.xy || [50, 55];
  const river = (data.water?.find(item => item.id === 'surface-river')?.points || [])
    .map(point => typeof point === 'string' ? places.get(point)?.xy : point).filter(Boolean);
  const profile = data.baseProfile.samples.map(sample => {
    const place = places.get(sample.place);
    if (!place) throw new Error(`地形剖面引用未知地点：${sample.place}`);
    return { xy: place.xy, height: sample.heightM };
  }).sort((a, b) => a.xy[0] - b.xy[0]);
  const profilePath = profile.map(sample => sample.xy);
  const plateau = data.areas.find(area => area.id === 'plateau')?.polygon;
  const eastAccess = [places.get('frontgate').xy, places.get('field1').xy];
  const rearRoute = data.routes.find(route => route.id === 'rear-city');
  const rearAccess = rearRoute?.points.slice(0, 2).map(point => typeof point === 'string' ? places.get(point).xy : point);
  const garageHeight = profile.find(sample => sample.xy === places.get('garage').xy)?.height || 27;

  return (east, north) => {
    const peaks = 3650 * bump(east, north, snow[0], snow[1], 16, 17)
      + 2180 * bump(east, north, snow[0] + 21, snow[1] + 11, 14, 14)
      + 1720 * bump(east, north, snow[0] - 18, snow[1] + 4, 11, 15);
    const piedmont = 710 * bump(east, north, foothill[0], foothill[1], 33, 24);
    const northUpland = 130 * smooth(12, 75, north)
      + 245 * bump(east, north, industry[0], industry[1], 42, 32);
    const westernRidges = 260 * bump(east, north, west[0] - 8, west[1] + 9, 5, 28)
      + 185 * bump(east, north, west[0] + 8, west[1] + 7, 4.5, 25);
    const valleyCut = river.length > 1 ? 56 * Math.exp(-((pathDistance(east, north, river) / 3.4) ** 2)) : 0;
    const undulation = 8 * Math.sin(east * 0.21 + north * 0.11) * Math.sin(north * 0.18)
      + 3 * Math.sin(east * 0.6 - north * 0.25);
    let height = Math.max(2, 16 + peaks + piedmont + northUpland + westernRidges + undulation - valleyCut);

    // 城市低地保留连续坡势；不依据视图切换抹平同一地理位置。
    const cityLowland = 0.68 * Math.max(bump(east, north, 13, -10, 14, 12), bump(east, north, -14, -10, 13, 11));
    height = height * (1 - cityLowland) + (9 + 0.12 * Math.max(0, north + 10)) * cityLowland;

    let section = profile[0].height;
    if (east >= profile.at(-1).xy[0]) section = profile.at(-1).height;
    else for (let i = 1; i < profile.length; i++) {
      if (east <= profile[i].xy[0]) {
        const a = profile[i - 1], b = profile[i];
        const t = clamp((east - a.xy[0]) / (b.xy[0] - a.xy[0]), 0, 1);
        section = a.height + (b.height - a.height) * t;
        break;
      }
    }
    const lateral = pathDistance(east, north, profilePath);
    let local;
    if (plateau) {
      const edgeDistance = polygonDistance(east, north, plateau);
      const rimDrop = 1 - smooth(-0.045, 0.035, edgeDistance);
      const outerShelf = 1 - smooth(0.55, 1.05, Math.max(0, -edgeDistance));
      const eastOpening = smooth(0.08, 0.3, east) * (1 - smooth(0.12, 0.34, pathDistance(east, north, eastAccess)));
      // 边界内保留台面，北/西/南缘集中落差；东进路留开口而非四面绝壁。
      local = Math.max(3, section - 22 * rimDrop * outerShelf * (1 - eastOpening));
      if (rearAccess?.length === 2) {
        const [a, b] = rearAccess, dx = b[0] - a[0], dy = b[1] - a[1];
        const t = clamp(((east - a[0]) * dx + (north - a[1]) * dy) / (dx * dx + dy * dy), 0, 1);
        const corridor = 1 - smooth(0.045, 0.115, segmentDistance(east, north, a, b));
        const ramp = garageHeight + (10 - garageHeight) * smooth(0, 1, t);
        local = local * (1 - corridor) + ramp * corridor;
      }
    } else {
      const plateauShoulder = 20 * Math.exp(-(((east + 0.08) / 0.58) ** 2)) * smooth(0.22, 0.72, lateral);
      local = Math.max(3, section - plateauShoulder);
    }
    const localBlend = 1 - smooth(0.48, 1.8, lateral);
    height = height * (1 - localBlend) + local * localBlend;
    return height;
  };
}

function triangleMesh(THREE, positions, colors, material, name) {
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  if (colors) geometry.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
  geometry.computeVertexNormals();
  geometry.computeBoundingSphere();
  const mesh = new THREE.Mesh(geometry, material);
  mesh.name = name;
  mesh.receiveShadow = true;
  return mesh;
}

/** A continuous, shared triangulated height field, cropped to the requested view. */
export function createTerrain(THREE, data, mode) {
  if (!VIEW_STYLE[mode] || !data.views?.[mode]) throw new Error(`未知地形视图：${mode}`);
  const bounds = [...data.views[mode].bounds];
  const verticalExaggeration = VIEW_STYLE[mode].exaggeration;
  const places = new Map(data.places.map(place => [place.id, place]));
  const [xs, ys] = sharedAxes(data);
  const rawHeight = physicalField(data, places);
  const samples = new Map();
  const sampled = (ix, iy) => {
    const key = iy * xs.length + ix;
    if (!samples.has(key)) samples.set(key, rawHeight(xs[ix], ys[iy]));
    return samples.get(key);
  };
  const heightAt = (eastKm, northKm) => {
    const x = clamp(eastKm, xs[0], xs.at(-1)), y = clamp(northKm, ys[0], ys.at(-1));
    const ix = locate(xs, x), iy = locate(ys, y);
    const tx = (x - xs[ix]) / (xs[ix + 1] - xs[ix]);
    const ty = (y - ys[iy]) / (ys[iy + 1] - ys[iy]);
    const h00 = sampled(ix, iy), h11 = sampled(ix + 1, iy + 1);
    // Same diagonal and triangle interpolation as the rendered solid below.
    if (ty <= tx) return h00 * (1 - tx) + sampled(ix + 1, iy) * (tx - ty) + h11 * ty;
    return h00 * (1 - ty) + h11 * tx + sampled(ix, iy + 1) * (ty - tx);
  };
  const world = (xy, liftMeters = 0) => new THREE.Vector3(xy[0], (heightAt(xy[0], xy[1]) + liftMeters) / 1000 * verticalExaggeration, -xy[1]);
  const vx = xs.filter(x => x >= bounds[0] - 1e-7 && x <= bounds[1] + 1e-7);
  const vy = ys.filter(y => y >= bounds[2] - 1e-7 && y <= bounds[3] + 1e-7);
  const positions = [], colors = [];
  const rock = new THREE.Color('#8e918c'), sand = new THREE.Color('#a6a18e');
  const snowColor = new THREE.Color('#dce0db'), valleyColor = new THREE.Color('#899389');
  let minHeight = Infinity, maxHeight = -Infinity;
  const emitTop = (points, ix, iy) => {
    const average = points.reduce((sum, point) => sum + heightAt(point[0], point[1]), 0) / 3;
    const color = sand.clone().lerp(rock, smooth(160, 1900, average));
    if (average > 2600) color.lerp(snowColor, smooth(2600, 4000, average));
    const centerX = points.reduce((sum, point) => sum + point[0], 0) / 3;
    if (centerX < -20 && average < 150) color.lerp(valleyColor, 0.22);
    color.multiplyScalar(0.95 + 0.08 * ((Math.sin(ix * 12.9898 + iy * 78.233) * 43758.5453) % 1 + 1) / 2);
    for (const point of points) {
      const v = world(point);
      positions.push(v.x, v.y, v.z);
      colors.push(color.r, color.g, color.b);
      const height = heightAt(point[0], point[1]);
      minHeight = Math.min(minHeight, height); maxHeight = Math.max(maxHeight, height);
    }
  };
  for (let iy = 0; iy < vy.length - 1; iy++) for (let ix = 0; ix < vx.length - 1; ix++) {
    const a = [vx[ix], vy[iy]], b = [vx[ix + 1], vy[iy]], c = [vx[ix + 1], vy[iy + 1]], d = [vx[ix], vy[iy + 1]];
    emitTop([a, b, c], ix, iy); emitTop([a, c, d], ix, iy);
  }
  const group = new THREE.Group();
  group.name = `desert-terrain-${mode}`;
  const surfaceMaterial = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1, metalness: 0, flatShading: true });
  group.add(triangleMesh(THREE, positions, colors, surfaceMaterial, 'shared-heightfield-surface'));

  const floor = VIEW_STYLE[mode].floorMeters / 1000 * verticalExaggeration;
  const perimeter = [
    ...vx.map(x => [x, bounds[2]]),
    ...vy.slice(1).map(y => [bounds[1], y]),
    ...vx.slice(0, -1).reverse().map(x => [x, bounds[3]]),
    ...vy.slice(1, -1).reverse().map(y => [bounds[0], y]),
  ];
  const sidePositions = [];
  for (let i = 0; i < perimeter.length; i++) {
    const a = world(perimeter[i]), b = world(perimeter[(i + 1) % perimeter.length]);
    sidePositions.push(a.x, a.y, a.z, a.x, floor, a.z, b.x, floor, b.z,
      a.x, a.y, a.z, b.x, floor, b.z, b.x, b.y, b.z);
  }
  const sideMaterial = new THREE.MeshStandardMaterial({ color: '#727873', roughness: 1, flatShading: true, side: THREE.DoubleSide });
  group.add(triangleMesh(THREE, sidePositions, null, sideMaterial, 'cut-earth-sidewalls'));
  const bottom = [bounds[0], floor, -bounds[2], bounds[1], floor, -bounds[3], bounds[1], floor, -bounds[2],
    bounds[0], floor, -bounds[2], bounds[0], floor, -bounds[3], bounds[1], floor, -bounds[3]];
  group.add(triangleMesh(THREE, bottom, null, sideMaterial, 'solid-bottom'));
  group.userData = {
    kind: 'candidate-terrain', verticalExaggeration, physicalDatum: '草图相对高程，非实测海拔',
    triangles: positions.length / 9 + sidePositions.length / 9 + 2,
    heightRangeMeters: [minHeight, maxHeight],
    profile: data.baseProfile.samples.map(sample => ({ ...sample, actualHeightM: heightAt(...places.get(sample.place).xy) })),
  };
  return { group, bounds, verticalExaggeration, heightAt, world };
}
