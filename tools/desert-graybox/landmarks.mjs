import { refineCivil } from './civil-massing.mjs';
import { refineMilitary } from './military-massing.mjs';

/**
 * Editable low-poly study masses. Geographic anchors are the design JSON's
 * coordinates; enlarged regional symbols are explicitly not building surveys.
 * The module has no renderer, browser, network, random, or file-system dependency.
 */
export function createLandmarks(THREE, data, mode, terrain) {
  if (!['region', 'city', 'base'].includes(mode)) throw new Error(`Unknown landmark mode: ${mode}`);
  const group = new THREE.Group();
  group.name = `LANDMARKS_${mode}`;
  group.userData = { placeId: '__landmarks__', designStatus: data.status, mode };
  const anchors = [];
  const pickMeshes = [];
  const places = new Map(data.places.map(place => [place.id, place]));
  const stages = new Map();
  for (const stage of data.stageMapping || []) {
    if (!stage.place) continue;
    if (!stages.has(stage.place)) stages.set(stage.place, []);
    stages.get(stage.place).push(stage.id);
  }
  const ve = terrain.verticalExaggeration || 1;
  const materials = Object.fromEntries(Object.entries({
    concrete: 0xaeb3b6, light: 0xd3d6d7, roof: 0x81898e,
    dark: 0x555e65, dry: 0x94999b, pale: 0xc1c5c6, water: 0x737e85,
  }).map(([name, color]) => [name, new THREE.MeshStandardMaterial({ color, roughness: 0.96, metalness: 0 })]));
  const cube = new THREE.BoxGeometry(1, 1, 1);
  const cylinder = new THREE.CylinderGeometry(1, 1, 1, 8);
  const cone = new THREE.ConeGeometry(1, 1, 5);
  const tentRoof = new THREE.ConeGeometry(1, 1, 4);

  function hash(id, index) {
    let h = (2166136261 ^ index) >>> 0;
    for (let i = 0; i < id.length; i++) h = Math.imul(h ^ id.charCodeAt(i), 16777619) >>> 0;
    return (h % 10007) / 10007;
  }
  function inside(point, polygon) {
    let hit = false;
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      const a = polygon[i], b = polygon[j];
      if ((a[1] > point[1]) !== (b[1] > point[1]) &&
          point[0] < (b[0] - a[0]) * (point[1] - a[1]) / (b[1] - a[1]) + a[0]) hit = !hit;
    }
    return hit;
  }

  function makeContext(place, footprint) {
    const object = new THREE.Group();
    object.name = `PLACE_${place.id}`;
    const origin = terrain.world(place.xy);
    object.position.copy(origin);
    object.userData = {
      placeId: place.id, geographicXY: [...place.xy], stageIds: stages.get(place.id) || [],
      mode, footprint,
      geographicAnchorIsMetric: true, physicalFootprintEstablished: false,
      footprintIsSymbolic: mode !== 'base', elevationExaggeration: ve,
      buildingHeightTreatment: 'Independent candidate masses; no single inverse scale unless explicitly recorded',
      representation: mode === 'base' ? 'proposed_local_massing' : 'enlarged_identification_masses',
    };
    group.add(object);
    let serial = 0;
    function mesh(geometry, east, north, width, depth, heightM, material = 'concrete', liftM = 0, rotation = 0) {
      const item = new THREE.Mesh(geometry, materials[material]);
      item.name = `${place.id}_${material}_${++serial}`;
      item.scale.set(width, heightM * ve / 1000, depth);
      item.position.copy(terrain.world([place.xy[0] + east, place.xy[1] + north], liftM + heightM / 2)).sub(origin);
      item.rotation.y = rotation;
      item.castShadow = true;
      item.receiveShadow = true;
      item.userData = { placeId: place.id, component: item.name, schematic: true };
      object.add(item);
      pickMeshes.push(item);
      return item;
    }
    const box = (...args) => mesh(cube, ...args);
    const drum = (x, y, radius, heightM, material = 'light', liftM = 0) =>
      mesh(cylinder, x, y, radius, radius, heightM, material, liftM);
    function house(x, y, w, d, heightM, material = 'concrete') {
      box(x, y, w, d, heightM, material);
      box(x, y, w * 1.06, d * 1.06, Math.max(1, heightM * 0.08), 'roof', heightM);
    }
    function tent(x, y, radius, heightM) {
      box(x, y, radius * 1.25, radius * 1.25, Math.max(1, heightM * 0.22), 'dark');
      mesh(tentRoof, x, y, radius, radius, heightM, 'pale', heightM * 0.22, Math.PI / 4);
    }
    function fence(x, y, width, depth, heightM, thickness, gap = 0.22) {
      box(x, y + depth / 2, width, thickness, heightM, 'roof');
      box(x - width / 2, y, thickness, depth, heightM, 'roof');
      box(x + width / 2, y, thickness, depth, heightM, 'roof');
      const section = width * (1 - gap) / 2;
      box(x - width * (1 + gap) / 4, y - depth / 2, section, thickness, heightM, 'roof');
      box(x + width * (1 + gap) / 4, y - depth / 2, section, thickness, heightM, 'roof');
    }
    return { place, object, origin, mesh, box, drum, house, tent, fence };
  }

  function prison(c) {
    const s = mode === 'region' ? 12 : mode === 'city' ? 4 : 1;
    const h = mode === 'region' ? 9 : mode === 'city' ? 3 : 1;
    const box = (x, y, w, d, ht, mat = 'concrete', lift = 0) => c.box(x * s, y * s, w * s, d * s, ht * h, mat, lift * h);
    // Continuous north/south walls, split east entrance and southwest garage gate.
    box(0, 0.22, 0.49, 0.009, 9);
    box(0, -0.22, 0.49, 0.009, 9);
    box(0.24, 0.135, 0.009, 0.17, 9);
    box(0.24, -0.135, 0.009, 0.17, 9);
    box(-0.24, 0.0525, 0.009, 0.335, 9);
    box(-0.24, -0.2125, 0.009, 0.015, 9);
    for (const x of [-0.24, 0.24]) for (const y of [-0.22, 0.22]) {
      box(x, y, 0.027, 0.027, 15);
      box(x, y, 0.033, 0.033, 2, 'roof', 15);
    }
    // Cell wings and service court leave the east-west arrival space clear.
    box(-0.1, 0.135, 0.2, 0.045, 13);
    box(0.035, 0.14, 0.035, 0.095, 13);
    box(-0.135, -0.05, 0.038, 0.145, 11);
    box(0.03, -0.085, 0.18, 0.11, 14);
    box(0.03, -0.085, 0.185, 0.115, 1, 'roof', 14);
    box(0.14, 0.13, 0.075, 0.045, 8);
    for (let i = 0; i < 4; i++) box(-0.165 + i * 0.045, 0.135, 0.005, 0.047, 1.2, 'dark', 13);
    // Raised roof pad and simple H are geometric masses, not external textures.
    c.drum(0.03 * s, -0.085 * s, 0.041 * s, 0.5 * h, 'light', 15 * h);
    box(0.016, -0.085, 0.004, 0.036, 0.35, 'dark', 15.5);
    box(0.044, -0.085, 0.004, 0.036, 0.35, 'dark', 15.5);
    box(0.03, -0.085, 0.028, 0.004, 0.35, 'dark', 15.5);
    c.object.userData.footprintScale = s;
    c.object.userData.buildingHeightScale = h;
    c.object.userData.buildingHeightTreatment = 'Authored prison heights multiplied by buildingHeightScale and elevationExaggeration';
    c.object.userData.gateOpenings = { east: [0.24, 0], southwest: [-0.24, -0.16] };
    c.object.userData.footprint = 'Same 480 x 440 m proposed prison enclosure; regional/city symbol enlarges it explicitly.';
  }

  function ruins(c) {
    for (let i = 0; i < 9; i++) {
      const x = ((i % 3) - 1) * 1.25, y = (Math.floor(i / 3) - 1) * 1.1;
      c.box(x, y, 0.8, 0.7, 8, 'dark');
      c.box(x - 0.4, y, 0.12, 0.7, 35 + (i % 3) * 20, 'dry');
      if (i % 2 === 0) c.box(x, y + 0.35, 0.8, 0.12, 65, 'concrete');
      c.box(x + 0.3, y - 0.24, 0.37, 0.23, 15, 'roof', 0, i * 0.4);
    }
    c.drum(-2, 0.7, 0.4, 38, 'roof');
    c.box(-2, -0.05, 0.15, 0.9, 12, 'dark');
    c.object.userData.history = 'Abandoned settlement, violence and sand damage retained; old ecology equipment is a candidate';
  }

  function forest(c) {
    const area = data.areas.find(area => area.id === 'forestenvironment');
    if (!area) throw new Error('Forest landmark requires forestenvironment polygon');
    const xs = area.polygon.map(p => p[0]), ys = area.polygon.map(p => p[1]);
    let accepted = 0;
    for (let i = 0; i < 300 && accepted < 64; i++) {
      const xy = [Math.min(...xs) + hash('forest-east', i) * (Math.max(...xs) - Math.min(...xs)),
        Math.min(...ys) + hash('forest-north', i) * (Math.max(...ys) - Math.min(...ys))];
      if (!inside(xy, area.polygon) || Math.hypot(xy[0] - c.place.xy[0], xy[1] - c.place.xy[1]) < 2.4) continue;
      const x = xy[0] - c.place.xy[0], y = xy[1] - c.place.xy[1];
      c.mesh(cone, x, y, 0.65 + hash('canopy', i) * 0.4, 0.65 + hash('canopy', i) * 0.4,
        150 + hash('tree-height', i) * 180, accepted % 3 === 0 ? 'roof' : 'dry');
      accepted++;
    }
    c.house(-0.5, 0.35, 1.25, 0.75, 65);
    c.drum(0.9, 0.55, 0.35, 55, 'pale');
    c.house(0.7, -0.5, 0.5, 0.6, 35);
    c.object.userData.footprint = 'Tree centers confined to forestenvironment candidate polygon; enlarged canopies are symbols.';
    c.object.userData.ecology = 'Bounded autonomous research environment candidate, not unlimited regional water treatment';
  }

  function field(c, index) {
    // Open scene extents and small objects sit north of the civilian approach.
    // The place anchor remains on the JSON chain; it does not become a building.
    const y = index === 3 ? -0.14 : 0.15;
    const extent = index === 3 ? 0.4 : 0.31;
    for (const x of [-extent / 2, extent / 2]) {
      c.box(x, y, 0.013, 0.065, 1.5, 'light');
      c.box(x, y + 0.16, 0.06, 0.013, 1.5, 'light');
    }
    if (index === 1) {
      for (let i = 0; i < 4; i++) c.box(-0.11 + i * 0.068, 0.32, 0.045, 0.025, 3, 'dark');
      c.box(-0.2, 0.18, 0.06, 0.022, 2, 'roof');
      c.object.userData.role = 'Scene 1 open approach and training-edge positions, not a fort';
    } else if (index === 2) {
      c.box(0.02, 0.15, 0.055, 0.038, 3.2, 'roof');
      c.box(0.005, 0.15, 0.03, 0.027, 2, 'concrete', 3.2);
      c.box(-0.036, 0.15, 0.065, 0.005, 0.8, 'dark', 4.1);
      for (const yy of [0.128, 0.172]) c.box(0.02, yy, 0.062, 0.009, 2.6, 'dark');
      c.object.userData.role = 'Scene 2 mobile artillery deployment placeholder, not measured Rhino vehicle geometry';
    } else {
      c.box(0, y, 0.085, 0.032, 3, 'roof', 0, 0.35);
      c.box(0.052, y + 0.017, 0.075, 0.009, 1.5, 'dark', 1.2, 0.35);
      c.box(-0.005, y, 0.13, 0.006, 0.5, 'dark', 3.5, 0.6);
      c.box(-0.005, y, 0.006, 0.13, 0.5, 'dark', 3.5, 0.6);
      c.object.userData.role = 'Scene 3 landing incident extent and broken rotor mass, not another military compound';
    }
  }

  function localService(c, id) {
    if (id === 'frontgate') {
      c.box(0, 0.058, 0.018, 0.025, 10, 'light');
      c.box(0, -0.058, 0.018, 0.025, 10, 'light');
      c.house(0.036, 0.078, 0.028, 0.025, 5);
    } else if (id === 'garage') {
      c.house(0.057, 0.03, 0.075, 0.045, 8);
      c.box(0.008, 0.036, 0.005, 0.03, 3, 'dark');
    } else if (id === 'dock') {
      c.box(0, 0, 0.13, 0.075, 1, 'water');
      c.box(-0.06, 0, 0.025, 0.14, 3, 'roof');
      c.box(0.012, 0.035, 0.08, 0.007, 7, 'concrete');
      c.box(0.012, -0.035, 0.08, 0.007, 7, 'concrete');
      c.box(0.012, 0, 0.08, 0.08, 1, 'roof', 7);
      c.object.userData.representation = 'Surface cutaway symbol for underground dock; depth and locks unresolved';
    } else if (id === 'storage') {
      c.drum(0, 0, 0.015, 6, 'pale');
      c.drum(0.035, 0, 0.015, 6, 'pale');
      c.house(-0.025, 0.006, 0.016, 0.025, 5);
    } else if (id === 'well') {
      c.drum(0, 0, 0.009, 2, 'dark');
      c.house(0.017, 0, 0.018, 0.022, 4);
    }
  }

  function interfaceMarker(c, id) {
    const s = mode === 'region' ? 1 : mode === 'city' ? 0.32 : 0.025;
    const h = mode === 'region' ? 65 : mode === 'city' ? 20 : 2;
    if (id === 'snow') {
      for (let i = 0; i < 3; i++) c.mesh(cone, (i - 1) * 2.2, (i % 2) * 1.2, 2.2, 1.9, 400 + i * 100, 'light');
      c.object.userData.role = 'Schematic mountain crest landmark; landing is the separate foothill node';
    } else if (id === 'front' || id === 'restricted') {
      for (let i = 0; i < 5; i++) c.box((i - 2) * 0.65 * s, (i % 2) * 0.28 * s, 0.42 * s, 0.16 * s, h * 0.5, 'dark', 0, i % 2 ? 0.3 : -0.3);
      c.box(0, 0.8 * s, 0.06 * s, 0.06 * s, h * 2, 'roof');
    } else if (id === 'ambush') {
      c.box(-0.7 * s, 0.6 * s, 1.1 * s, 0.13 * s, h * 0.65, 'dry');
      c.box(0.6 * s, -0.5 * s, 0.9 * s, 0.12 * s, h * 0.5, 'dry');
      c.box(0, 0.24 * s, 0.7 * s, 0.35 * s, h * 0.45, 'roof');
      c.box(0.45 * s, 0.24 * s, 0.25 * s, 0.32 * s, h * 0.4, 'concrete');
    } else if (id === 'foothill') {
      c.drum(0, 0, 0.65 * s, 4, 'light');
      c.house(-0.9 * s, 0.6 * s, 0.7 * s, 0.45 * s, h * 0.65);
      c.box(-0.12 * s, 0, 0.05 * s, 0.55 * s, 2, 'dark', 4);
      c.box(0.12 * s, 0, 0.05 * s, 0.55 * s, 2, 'dark', 4);
      c.box(0, 0, 0.24 * s, 0.05 * s, 2, 'dark', 4);
    } else if (id === 'landing') {
      c.box(0, 0, 1.5 * s, 0.45 * s, h * 0.2, 'roof');
      c.house(-0.5 * s, 0.55 * s, 0.6 * s, 0.4 * s, h * 0.75);
    } else if (id === 'receiving') {
      c.house(-0.5 * s, 0.35 * s, 1.2 * s, 0.7 * s, h);
      for (let i = 0; i < 4; i++) c.box((0.4 + (i % 2) * 0.4) * s, (Math.floor(i / 2) * 0.5) * s, 0.28 * s, 0.35 * s, h * 0.55, 'roof');
    } else {
      c.box(-0.38 * s, 0.45 * s, 0.3 * s, 0.16 * s, h * 0.3, 'roof');
      c.box(0.4 * s, -0.35 * s, 0.1 * s, 0.1 * s, h, 'light');
    }
  }

  const regionalContext = new Set(['waste', 'fallen', 'commune', 'constitutional', 'landing']);
  const extras = mode === 'region' ? new Set([...stages.keys(), ...regionalContext]) :
    mode === 'city' ? new Set(['depot', 'refugees']) : new Set(['eastjunction', 'well', 'storage']);
  const visible = data.places.filter(place => place.views.includes(mode) || extras.has(place.id));
  for (const place of visible) {
    const c = makeContext(place, 'Schematic footprint for geographic review, not surveyed building extent');
    if (place.id === 'supplygroup') {
      // This is a UI aggregate only. Its members already have separate masses.
      c.object.userData.representation = 'aggregate_anchor_only';
      c.object.userData.members = [...place.members];
      c.object.userData.footprintIsSymbolic = false;
    } else if (refineCivil(c,{THREE,data,mode,terrain}) || refineMilitary(c,{THREE,data,mode,terrain})) {
      // Functional groups own their assembly; the generic geographic anchor remains unchanged.
    } else if (place.id === 'base') prison(c);
    else if (['frontgate', 'garage', 'dock', 'well', 'storage'].includes(place.id)) localService(c, place.id);
    else if (['field1', 'field2', 'field3'].includes(place.id)) field(c, Number(place.id.slice(-1)));
    else if (place.id === 'ruins') ruins(c);
    else if (place.id === 'forest') forest(c);
    else interfaceMarker(c, place.id);
    const focusSpan = mode === 'base' ? (place.id === 'base' ? 0.95 : place.id.startsWith('field') ? 0.8 : 0.35) :
      place.id === 'forest' ? 48 : ['waste', 'fallen'].includes(place.id) ? 20 :
        place.id === 'snow' ? 17 : place.id === 'supplygroup' ? 8 : mode === 'region' ? 10 : 6;
    anchors.push({ id: place.id, name: place.name, object: c.object, world: c.origin.clone(), focusSpan });
  }
  group.updateMatrixWorld(true);
  return { group, anchors, pickMeshes };
}
