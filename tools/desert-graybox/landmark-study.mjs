/**
 * Reversible regional appearance study. No source materials/geometries are edited.
 * X/Z positions, horizontal scales, geographic anchors and road geometry remain fixed.
 * Display-height multipliers are pictorial, not new physical heights or adopted lore.
 */
const PALETTES = {
  common: { concrete: '#92917e', light: '#b3ad95', roof: '#535e50', dark: '#343c34', dry: '#887960', pale: '#a59c80', water: '#536c65' },
  base: { concrete: '#9d9c88', light: '#c2b99d', roof: '#475d50', dark: '#303a32', dry: '#8d7c60', pale: '#afa587', water: '#506f69' },
  fort: { concrete: '#929580', light: '#b5ae91', roof: '#4e6050', dark: '#303a32', dry: '#827c65', pale: '#a99a79', water: '#52685f' },
  frontbase: { concrete: '#a6a58e', light: '#beb699', roof: '#536a58', dark: '#354037', dry: '#897a61', pale: '#aaa07f', water: '#586f65' },
  industry: { concrete: '#868879', light: '#aaa48d', roof: '#515c55', dark: '#343b36', dry: '#806952', pale: '#9e967d', water: '#526a65' },
  fallen: { concrete: '#94917d', light: '#b1aa92', roof: '#50594c', dark: '#343a32', dry: '#7d7864', pale: '#938d77', water: '#516960' },
  waste: { concrete: '#a0937e', light: '#b5aa91', roof: '#6b6b57', dark: '#4c4b3e', dry: '#85715a', pale: '#9e8d71', water: '#5d7065' },
  secret: { concrete: '#8b8872', light: '#a9a084', roof: '#736652', dark: '#3c4034', dry: '#806b50', pale: '#a09270', water: '#546e62' },
  forest: { concrete: '#899080', light: '#afb29a', roof: '#4e6152', dark: '#344438', dry: '#73775c', pale: '#a2a181', water: '#55756b' },
  camp: { concrete: '#9a9177', light: '#b7ac8a', roof: '#736955', dark: '#454838', dry: '#917857', pale: '#ad9b76', water: '#5d786c' },
};

const PLACE_HEIGHT = {
  base: 4.1, fort: 3.55, frontbase: 3.2, industry: 3.05,
  fallen: 6.4, waste: 5.5, commune: 3.6, constitutional: 3.5,
  depot: 2.35, secret: 2.65, diplomacy: 1.95, receiving: 2.8,
  communes: 2.35, refugees: 1.75, ruins: 3.0, forest: 2.3,
  landing: 2.2, foothill: 1.8, front: 1.3, restricted: 1.2, snow: 1,
};

const AREA_HEIGHT = {
  occupied_core_blocks: 6.7, damaged_core_blocks: 5.8,
  transition_blocks: 5.1, peripheral_fragments: 3.9, institutional_courtyard: 5.7,
  factory_quarter: 3.9, workers_housing: 3.1,
  'fort-entry_and_exit': 3.0, 'fort-armor_and_open_court': 1.9,
  'frontbase-operations_and_comms': 2.85, 'frontbase-forward_support': 3.1,
  'frontbase-route_interfaces': 2.15, 'industry-logistics_perimeter': 2.1,
};

function paletteFor(placeId) {
  if (PALETTES[placeId]) return placeId;
  if (['refugees', 'communes', 'depot', 'ruins'].includes(placeId)) return 'camp';
  return 'common';
}

function componentSlot(mesh) {
  return /(?:^|_)(concrete|light|roof|dark|dry|pale|water)(?:_|$)/.exec(mesh.name)?.[1] || 'concrete';
}

function areaOf(mesh, root) {
  let parent = mesh;
  while (parent && parent !== root) {
    if (parent.userData?.subareaId) return parent.userData.subareaId;
    parent = parent.parent;
  }
  return '';
}

function localBox(THREE, mesh) {
  // Avoid computeBoundingBox() because shared source geometry must remain untouched.
  if (mesh.geometry.boundingBox) return mesh.geometry.boundingBox.clone();
  return new THREE.Box3().setFromBufferAttribute(mesh.geometry.getAttribute('position'));
}

/**
 * Starts disabled. Call dispose() before disposing the original graybox model.
 * The controller only owns its cloned materials; it never disposes original resources.
 */
export function createLandmarkStudy(THREE, model, data) {
  if (!model?.landmarks?.group || !model?.terrain || !model?.group) {
    throw new Error('Landmark study requires the graybox model and its landmark/terrain groups.');
  }
  const mode = model.metrics?.mode || model.group.userData.mode;
  if (mode !== 'region') throw new Error('Landmark appearance study only supports the regional overview.');
  const knownPlaces = new Set(data.places.map(place => place.id));
  const snapshots = [];
  const materialCache = new Map(), ownedMaterials = new Set();
  const ve = model.terrain.verticalExaggeration;
  let enabled = false, disposed = false;
  model.group.updateMatrixWorld(true);
  const modelInverse = model.group.matrixWorld.clone().invert();
  const modelUp = new THREE.Vector3(0, 1, 0).transformDirection(model.group.matrixWorld);

  model.landmarks.group.traverse(mesh => {
    if (!mesh.isMesh || !mesh.geometry?.getAttribute('position')) return;
    const placeId = mesh.userData.placeId;
    if (!knownPlaces.has(placeId)) return;
    const box = localBox(THREE, mesh);
    const centerModel = new THREE.Vector3().setFromMatrixPosition(mesh.matrixWorld).applyMatrix4(modelInverse);
    const groundModel = model.terrain.world([centerModel.x, -centerModel.z]);
    const groundWorld = groundModel.clone().applyMatrix4(model.group.matrixWorld);
    const groundInParent = mesh.parent.worldToLocal(groundWorld.clone());
    const up = new THREE.Vector3(0, 1, 0).transformDirection(mesh.matrixWorld);
    const canScaleVertically = up.dot(modelUp) > 0.999999;
    const matrixInModel = modelInverse.clone().multiply(mesh.matrixWorld);
    const boxInModel = box.clone().applyMatrix4(matrixInModel);
    const heightM = (boxInModel.max.y - boxInModel.min.y) / ve * 1000;
    const groundGapM = (boxInModel.min.y - groundModel.y) / ve * 1000;
    const area = areaOf(mesh, model.landmarks.group);
    const tree = placeId === 'forest' && mesh.geometry.type === 'ConeGeometry';
    let multiplier = tree ? 1.4 : AREA_HEIGHT[area] || PLACE_HEIGHT[placeId] || 1.65;
    // Street marks, court slabs, cultivation ridges and ground rubble remain thin.
    // Raised roof caps are not mistaken for ground slabs: their bottom is above ground.
    // Tent plinths belong to the same assembly as their raised roofs.
    if (heightM < 4 && groundGapM < 1.1 && area !== 'household_clusters') multiplier = 1;
    if (!canScaleVertically) multiplier = 1;

    const slot = componentSlot(mesh), paletteName = paletteFor(placeId);
    const spatialVariant = ['fallen', 'waste'].includes(placeId)
      ? ((Math.floor(centerModel.x / 3.2) + Math.floor(-centerModel.z / 3.2)) % 3 + 3) % 3 : 1;
    const treeVariant = tree ? (Number(mesh.name.match(/_(\d+)$/)?.[1] || 0) % 3) : 0;
    function studyMaterial(source) {
      const key = `${source.uuid}:${paletteName}:${slot}:${spatialVariant}:${tree ? treeVariant : 'solid'}`;
      if (materialCache.has(key)) return materialCache.get(key);
      const material = source.clone();
      material.name = `DESERT_STUDY_${paletteName}_${tree ? 'canopy' : slot}_${tree ? treeVariant : spatialVariant}`;
      material.color.set(tree ? ['#52634f', '#627058', '#485b4a'][treeVariant] : PALETTES[paletteName][slot]);
      if (!tree && ['fallen', 'waste'].includes(placeId)) material.color.multiplyScalar([0.93, 1, 1.055][spatialVariant]);
      if ('roughness' in material) material.roughness = tree ? 1 : 0.94;
      if ('metalness' in material) material.metalness = slot === 'roof' && !tree ? 0.035 : 0;
      if ('emissive' in material) material.emissive.setRGB(0, 0, 0);
      material.flatShading = true;
      material.needsUpdate = true;
      materialCache.set(key, material); ownedMaterials.add(material);
      return material;
    }
    const studyMaterials = Array.isArray(mesh.material) ? mesh.material.map(studyMaterial) : studyMaterial(mesh.material);
    snapshots.push({ mesh, material: mesh.material, studyMaterials,
      position: mesh.position.clone(), scale: mesh.scale.clone(),
      groundY: groundInParent.y, multiplier });
  });

  function setEnabled(value) {
    if (disposed || enabled === Boolean(value)) return;
    enabled = Boolean(value);
    for (const snapshot of snapshots) {
      const { mesh, position, scale } = snapshot;
      if (enabled) {
        mesh.material = snapshot.studyMaterials;
        // Transform above each existing terrain contact, including raised roof parts.
        // X/Z and horizontal dimensions are never assigned or recomputed here.
        mesh.scale.y = scale.y * snapshot.multiplier;
        mesh.position.y = snapshot.groundY + (position.y - snapshot.groundY) * snapshot.multiplier;
      } else {
        mesh.material = snapshot.material;
        mesh.position.copy(position);
        mesh.scale.copy(scale);
      }
      mesh.updateMatrix();
    }
    model.group.updateMatrixWorld(true);
  }

  function dispose() {
    if (disposed) return;
    setEnabled(false);
    disposed = true;
    for (const material of ownedMaterials) material.dispose();
    ownedMaterials.clear(); materialCache.clear(); snapshots.length = 0;
  }

  return { setEnabled, dispose };
}
