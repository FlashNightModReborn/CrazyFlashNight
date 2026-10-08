/**
 * Browser-only terrain appearance study. It does not edit the shared heightfield,
 * vertex positions/colors, geographic anchors, route objects or exported graybox.
 * The generated color field is a visual grouping of existing candidate geography,
 * not a simulation or an assertion about new water sources or land ownership.
 */

const clamp = (value, low = 0, high = 1) => Math.max(low, Math.min(high, value));
const smooth = (low, high, value) => {
  const t = clamp((value - low) / (high - low));
  return t * t * (3 - 2 * t);
};

function hash(x, y) {
  let n = Math.imul(x | 0, 374761393) ^ Math.imul(y | 0, 668265263);
  n = Math.imul(n ^ (n >>> 13), 1274126177);
  return ((n ^ (n >>> 16)) >>> 0) / 4294967295;
}

function noise(x, y) {
  const ix = Math.floor(x), iy = Math.floor(y);
  const fx = x - ix, fy = y - iy;
  const tx = fx * fx * (3 - 2 * fx), ty = fy * fy * (3 - 2 * fy);
  const a = hash(ix, iy), b = hash(ix + 1, iy), c = hash(ix, iy + 1), d = hash(ix + 1, iy + 1);
  return (a + (b - a) * tx) * (1 - ty) + (c + (d - c) * tx) * ty;
}

function segmentDistanceSquared(x, y, a, b) {
  const dx = b[0] - a[0], dy = b[1] - a[1];
  const t = clamp(((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy || 1));
  return (x - a[0] - t * dx) ** 2 + (y - a[1] - t * dy) ** 2;
}

function pathDistance(x, y, path) {
  let result = Infinity;
  for (let i = 1; i < path.length; i++) result = Math.min(result, segmentDistanceSquared(x, y, path[i - 1], path[i]));
  return Math.sqrt(result);
}

function signedPolygonDistance(x, y, polygon) {
  if (!polygon?.length) return -Infinity;
  let inside = false, distance = Infinity;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const a = polygon[j], b = polygon[i];
    distance = Math.min(distance, segmentDistanceSquared(x, y, a, b));
    if ((a[1] > y) !== (b[1] > y) && x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
  }
  return Math.sqrt(distance) * (inside ? 1 : -1);
}

function colorField(THREE, terrain, data, extent) {
  const places = new Map(data.places.map(place => [place.id, place.xy]));
  const areas = new Map((data.areas || []).map(area => [area.id, area.polygon]));
  const points = list => (list || []).map(point => typeof point === 'string' ? places.get(point) : point).filter(Boolean);
  const river = points(data.water?.find(water => water.id === 'surface-river')?.points);
  const canal = points(data.water?.find(water => water.id === 'old-canal')?.points);
  const foothill = places.get('foothill');
  const palette = Object.fromEntries(Object.entries({
    sand: '#aa9274', paleSand: '#c1aa88', ochre: '#8e775f', clay: '#95836b',
    rock: '#858d85', shadedRock: '#69766e', alluvium: '#a3a18a', channel: '#818573',
    oldFields: '#97987a', settlement: '#b0a58d', forestEdge: '#82896b', forest: '#53694c',
    snow: '#e2e1d6',
  }).map(([name, hex]) => {
    const color = new THREE.Color(hex);
    return [name, [color.r, color.g, color.b]];
  }));
  const width = 512, height = 512;
  const bytes = new Uint8Array(width * height * 4);
  const delta = 0.62;
  let minLight = Infinity, maxLight = -Infinity;
  for (let row = 0; row < height; row++) {
    const north = extent[2] + (row + 0.5) / height * (extent[3] - extent[2]);
    for (let col = 0; col < width; col++) {
      const east = extent[0] + (col + 0.5) / width * (extent[1] - extent[0]);
      const elevation = terrain.heightAt(east, north);
      const hW = terrain.heightAt(east - delta, north), hE = terrain.heightAt(east + delta, north);
      const hS = terrain.heightAt(east, north - delta), hN = terrain.heightAt(east, north + delta);
      const slopeEast = (hE - hW) / (2 * delta * 1000), slopeNorth = (hN - hS) / (2 * delta * 1000);
      const slope = Math.hypot(slopeEast, slopeNorth);
      const curvature = elevation - (hW + hE + hS + hN) / 4;
      const warp = noise(east / 24 + 12.8, north / 24 - 8.9) - 0.5;
      const broad = noise(east / 14 + warp * 2.8, north / 19 - warp * 2.1);
      const mid = noise(east / 5.5 + warp * 3.1, north / 7.2 + warp * 1.8);
      const fine = noise(east / 1.55 - 12.7, north / 1.7 + 9.3);
      const duneFlow = 0.5 + 0.5 * Math.sin(east * 0.3 + north * 0.17 + warp * 10 + broad * 5);
      const color = [...palette.sand];
      const mix = (target, amount) => {
        const t = clamp(amount), value = palette[target];
        color[0] += (value[0] - color[0]) * t;
        color[1] += (value[1] - color[1]) * t;
        color[2] += (value[2] - color[2]) * t;
      };
      // Broad patches and warped wind-aligned strokes remain visible at overview
      // scale; no square tiling, regular checker colors or new dune geometry.
      mix('ochre', smooth(0.27, 0.76, broad) * 0.38);
      mix('paleSand', smooth(0.37, 0.83, mid) * 0.22 + smooth(0.65, 0.95, duneFlow) * 0.08);
      mix('clay', smooth(60, 500, elevation) * (1 - smooth(0.035, 0.12, slope)) * 0.3);

      const mountainMask = smooth(-5, 5, signedPolygonDistance(east, north, areas.get('mountains')));
      const rocky = Math.max(smooth(0.035, 0.135, slope), smooth(550, 2100, elevation) * 0.78);
      mix('rock', rocky * (0.7 + mountainMask * 0.18));
      const face = slope > 0.0001 ? clamp((slopeEast * -0.55 + slopeNorth * 0.83) / slope * 0.5 + 0.5) : 0.5;
      mix('shadedRock', rocky * face * (0.12 + mid * 0.13));
      mix('paleSand', smooth(2, 22, curvature) * smooth(250, 2100, elevation) * 0.16);

      // Existing river geometry remains authoritative. This only separates its
      // surrounding sediment corridor from the upland, never drawing extra water.
      const riverDistance = pathDistance(east, north, river);
      const valley = (1 - smooth(1.7, 7.8, riverDistance)) * (1 - smooth(0.09, 0.21, slope));
      mix('alluvium', valley * (0.44 + broad * 0.2));
      mix('channel', (1 - smooth(0.5, 1.65, riverDistance)) * 0.43);

      // A sediment fan uses the already authored mountain-front/river direction.
      // It is a paint hierarchy on unchanged ground, not a new drainage channel.
      if (foothill) {
        const x = east - foothill[0], y = north - foothill[1];
        const along = x * 0.5 - y * 0.8660254;
        const across = x * 0.8660254 + y * 0.5;
        const fanWidth = 2.4 + Math.max(0, along) * 0.33;
        const fan = smooth(-2, 7, along) * (1 - smooth(28, 43, along)) *
          (1 - smooth(fanWidth * 0.65, fanWidth * 1.35, Math.abs(across))) * (1 - smooth(0.05, 0.15, slope));
        const wash = noise(across / 2.4 + warp, along / 11) * 0.65 + mid * 0.35;
        mix('alluvium', fan * (0.27 + wash * 0.24));
        mix('paleSand', fan * smooth(0.5, 0.85, wash) * 0.19);
      }

      const oldFields = smooth(-1.5, 1.5, signedPolygonDistance(east, north, areas.get('oldirrigation')));
      mix('oldFields', oldFields * (0.25 + mid * 0.18));
      mix('clay', (1 - smooth(0.28, 1.0, pathDistance(east, north, canal))) * 0.23);
      const urban = Math.max(smooth(-1.8, 1.8, signedPolygonDistance(east, north, areas.get('wastecity'))),
        smooth(-1.8, 1.8, signedPolygonDistance(east, north, areas.get('fallencity'))));
      mix('settlement', urban * 0.42);

      // The forest remains a bounded candidate environment. Edges are soil-tone
      // transitions only; no additional trees or ecology facilities are invented.
      const forestDistance = signedPolygonDistance(east, north, areas.get('forestenvironment'));
      mix('forestEdge', smooth(-2.2, 1.5, forestDistance) * 0.6);
      mix('forest', smooth(-0.3, 3.2, forestDistance) * (0.68 + mid * 0.15));
      mix('snow', smooth(2450 + (mid - 0.5) * 280, 3550, elevation) * 0.95);

      const light = 0.96 + (fine - 0.5) * 0.06 + (mid - 0.5) * 0.06;
      const index = (row * width + col) * 4;
      for (let channel = 0; channel < 3; channel++) bytes[index + channel] = Math.round(clamp(color[channel] * light) * 255);
      bytes[index + 3] = 255;
      const luminance = color[0] * 0.2126 + color[1] * 0.7152 + color[2] * 0.0722;
      minLight = Math.min(minLight, luminance); maxLight = Math.max(maxLight, luminance);
    }
  }
  const texture = new THREE.DataTexture(bytes, width, height, THREE.RGBAFormat, THREE.UnsignedByteType);
  texture.name = 'DESERT_TERRAIN_STUDY_LINEAR_COLOR_FIELD';
  // Color values were generated in Three's linear working space. A custom
  // sampler reads them directly, so an extra sRGB decode would be incorrect.
  texture.colorSpace = THREE.NoColorSpace;
  texture.magFilter = THREE.LinearFilter;
  texture.minFilter = THREE.LinearFilter;
  texture.wrapS = texture.wrapT = THREE.ClampToEdgeWrapping;
  texture.generateMipmaps = false;
  texture.flipY = false;
  texture.needsUpdate = true;
  texture.userData = { role: 'browser-only candidate terrain palette', resolution: [width, height], extent,
    workingColorSpace: 'linear', minLuminance: minLight, maxLuminance: maxLight, deterministic: true };
  return texture;
}

const shaderCommon = `
varying vec3 vTerrainStudyPosition;
uniform sampler2D uTerrainStudyField;
uniform vec4 uTerrainStudyExtent;
uniform float uTerrainStudySidewall;
float terrainStudyHash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453123);
}
float terrainStudyNoise(vec2 p) {
  vec2 a = floor(p), f = fract(p), u = f*f*(3.0-2.0*f);
  return mix(mix(terrainStudyHash(a),terrainStudyHash(a+vec2(1.0,0.0)),u.x),
    mix(terrainStudyHash(a+vec2(0.0,1.0)),terrainStudyHash(a+vec2(1.0,1.0)),u.x),u.y);
}
`;

const shaderColor = `
vec2 studyXY = vec2(vTerrainStudyPosition.x, -vTerrainStudyPosition.z);
vec2 studyUV = clamp((studyXY-uTerrainStudyExtent.xz)/(uTerrainStudyExtent.yw-uTerrainStudyExtent.xz),0.0,1.0);
vec3 studyBase = texture2D(uTerrainStudyField,studyUV).rgb;
float studyWarp = terrainStudyNoise(studyXY*0.19+vec2(31.7,-12.4));
vec2 studyGrainP = studyXY*8.0+vec2(studyWarp*3.1,studyWarp*-2.7);
float studyPixelSize = max(length(dFdx(studyGrainP)),length(dFdy(studyGrainP)));
float studyFineWeight = 1.0-smoothstep(0.6,2.0,studyPixelSize);
float studyGrain = terrainStudyNoise(studyGrainP)-0.5;
float studySpeck = terrainStudyNoise(studyXY*2.1+vec2(studyWarp*1.4,-studyWarp))-0.5;
float studyStipple = smoothstep(0.59,0.83,terrainStudyNoise(studyXY*3.5+vec2(studyWarp,-studyWarp)));
// Overview texture cells must not become hundred-metre checker patches on zoom.
// Fade that pictorial grain out and introduce finer, pixel-filtered local soil.
float studyWorldPixel=max(length(dFdx(studyXY)),length(dFdy(studyXY)));
float studyOverviewWeight=smoothstep(0.012,0.075,studyWorldPixel);
float studyLocalWeight=(1.0-studyOverviewWeight)*(1.0-smoothstep(0.65,2.0,studyWorldPixel*140.0));
float studyLocalGrain=terrainStudyNoise(studyXY*140.0+vec2(studyWarp*8.0,-studyWarp*6.0))-0.5;
studyBase *= 1.0+(studySpeck*0.16+studyGrain*0.15*studyFineWeight-studyStipple*0.16)*studyOverviewWeight+studyLocalGrain*0.1*studyLocalWeight;
// Cross-section walls remain an understated warm earth material when the cut
// is visible; this is not a newly claimed geological stratum.
vec3 studySide = studyBase*vec3(0.67,0.62,0.58);
studyBase = mix(studyBase,studySide,uTerrainStudySidewall);
diffuseColor.rgb *= studyBase;
`;

/**
 * Construct once after createGraybox. It starts disabled. No-op for city/base.
 * Call dispose before disposing the graybox so original material ownership is
 * restored; this controller disposes only its own clones and generated texture.
 */
export function createTerrainStudy(THREE, model, data) {
  const mode = model.metrics?.mode || model.group?.userData?.mode;
  if (mode !== 'region') return { setEnabled() {}, dispose() {} };
  const terrain = model.terrain;
  const surface = terrain?.group?.getObjectByName('shared-heightfield-surface');
  if (!surface?.isMesh) throw new Error('Terrain style study requires the existing shared-heightfield-surface');
  const [x0, x1, y0, y1] = terrain.bounds;
  // Include the same presentation-only apron as createSurroundings. Its height
  // still comes from heightAt's clamping; the appearance adds no authored land.
  const pad = Math.max(x1 - x0, y1 - y0) * 0.45;
  const extent = [x0 - pad, x1 + pad, y0 - pad, y1 + pad];
  const texture = colorField(THREE, terrain, data, extent);
  const extentUniform = new THREE.Vector4(...extent);
  const records = [], ownedMaterials = new Set(), materialCache = new Map();
  function replacement(original, sidewall) {
    let variants = materialCache.get(original);
    if (!variants) { variants = new Map(); materialCache.set(original, variants); }
    if (variants.has(sidewall)) return variants.get(sidewall);
    const material = original.clone();
    material.name = `TERRAIN_STUDY_${sidewall ? 'CUT_EARTH' : 'SURFACE'}`;
    material.color.setRGB(1, 1, 1);
    material.vertexColors = false;
    material.roughness = 0.98;
    material.metalness = 0;
    material.dithering = true;
    material.userData = { ...material.userData, browserOnlyStyleStudy: true, sourceMaterialName: original.name || '',
      geometryChanged: false, physicalHeightChanged: false };
    material.onBeforeCompile = shader => {
      shader.uniforms.uTerrainStudyField = { value: texture };
      shader.uniforms.uTerrainStudyExtent = { value: extentUniform };
      shader.uniforms.uTerrainStudySidewall = { value: sidewall ? 1 : 0 };
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', '#include <common>\nvarying vec3 vTerrainStudyPosition;')
        .replace('#include <worldpos_vertex>', '#include <worldpos_vertex>\nvTerrainStudyPosition=(modelMatrix*vec4(transformed,1.0)).xyz;');
      shader.fragmentShader = shader.fragmentShader
        .replace('#include <common>', '#include <common>\n' + shaderCommon)
        .replace('#include <color_fragment>', '#include <color_fragment>\n' + shaderColor);
    };
    material.customProgramCacheKey = () => 'desert-terrain-study-v1';
    material.needsUpdate = true;
    variants.set(sidewall, material); ownedMaterials.add(material);
    return material;
  }
  function register(mesh, sidewall = false) {
    if (!mesh?.isMesh || !mesh.material) return;
    const original = mesh.material;
    const study = Array.isArray(original) ? original.map(item => replacement(item, sidewall)) : replacement(original, sidewall);
    records.push({ mesh, original, study });
  }
  register(surface);
  register(terrain.group.getObjectByName('cut-earth-sidewalls'), true);
  register(terrain.group.getObjectByName('solid-bottom'), true);
  model.surroundings?.traverse(object => { if (object.isMesh) register(object); });
  let enabled = false, disposed = false;
  function setEnabled(value) {
    if (disposed) return;
    const next = Boolean(value);
    if (enabled === next) return;
    for (const record of records) record.mesh.material = next ? record.study : record.original;
    enabled = next;
  }
  function dispose() {
    if (disposed) return;
    setEnabled(false);
    for (const material of ownedMaterials) material.dispose();
    texture.dispose();
    records.length = 0; materialCache.clear(); ownedMaterials.clear();
    disposed = true;
  }
  return { setEnabled, dispose };
}
