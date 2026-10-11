/** THREE adapter for layout-core.mjs. No DOM, camera, animation, or disposal here. */
import { layoutFor, validateLayout } from './layout-core.mjs';

const STATES = new WeakMap();
const originalName = node => node.userData?.name || node.name || '';
const normalName = node => originalName(node).replace(/[._\s]/g, '').toLowerCase();
const starts = (node, prefix) => normalName(node).startsWith(prefix.replace(/[._\s]/g, '').toLowerCase());
const obsolete = node => ['Cabinet side', 'Cabinet foot', 'Structural shelf', 'Recessed back', 'Shelf leading lip', 'BOOKEND', 'Fixed drawer runner'].some(prefix => starts(node, prefix));

function addResources(object, state) {
  object.traverse(node => {
    if (node.geometry) state.ownedGeometries.add(node.geometry);
    for (const material of Array.isArray(node.material) ? node.material : node.material ? [node.material] : []) state.ownedMaterials.add(material);
  });
}
function findMaterial(nodes, prefix) {
  const found = nodes.find(node => starts(node, prefix) && node.material);
  return Array.isArray(found?.material) ? found.material[0] : found?.material;
}
function setup(root, THREE) {
  const shelfRoot = root.getObjectByName('CF7_BOOKSHELF_ROOT') || (root.userData?.entryKey === 'bookshelf' ? root : null);
  if (!shelfRoot) throw new Error('The modular layout requires the v3 CF7_BOOKSHELF_ROOT.');
  const nodes = []; shelfRoot.traverse(node => nodes.push(node));
  const state = {
    root, shelfRoot, semantic: new Map(), rest: new Map(), groups: new Map(), key: '',
    detachedObjects: [], retiredObjects: [], ownedGeometries: new Set(), ownedMaterials: new Set(), materials: {}, movedNodes: []
  };
  for (const node of nodes) {
    state.semantic.set(originalName(node), node);
    state.semantic.set(node.name, node);
    if (node.userData?.entryKey || node.name === 'ARCHIVE_BANK') state.rest.set(node, { quaternion: node.quaternion.clone(), scale: node.scale.clone(), position: node.position.clone() });
  }
  const specifications = {
    shelf: ['Structural shelf', 0x5d6774, 0.5, 0.37], side: ['Cabinet side', 0x5d6774, 0.5, 0.37],
    lip: ['Shelf leading lip', 0x9da8b2, 0.65, 0.28], back: ['Recessed back', 0x464d54, 0.15, 0.70],
    foot: ['Cabinet foot', 0x262c30, 0.12, 0.54]
  };
  for (const [kind, [prefix, color, metalness, roughness]] of Object.entries(specifications)) {
    const material = findMaterial(nodes, prefix) || new THREE.MeshStandardMaterial({ color, metalness, roughness });
    state.materials[kind] = material; state.ownedMaterials.add(material);
  }
  // Keep retired source geometry in the scene for one unified teardown. Callers
  // measuring visible bounds must skip invisible ancestors (Box3 alone does not).
  const retired = new THREE.Group(); retired.name = 'RETIRED_V3_STRUCTURE';
  retired.visible = false; retired.userData.kind = 'retiredStructure';
  shelfRoot.add(retired); state.retiredGroup = retired;
  // Collect first, then move whole subtrees (bookend child meshes stay together).
  for (const node of nodes.filter(node => obsolete(node) && !obsolete(node.parent || {}))) {
    addResources(node, state); retired.add(node); node.visible = false;
    state.retiredObjects.push(node);
  }
  STATES.set(root, state); return state;
}
function makeGroup(layout, state, THREE) {
  const group = new THREE.Group(); group.name = `MODULAR_CABINET_${layout.key.toUpperCase()}`;
  group.userData = { kind: 'modularCabinet', layoutKey: layout.key, boardThickness: layout.boardThickness };
  for (const board of layout.boards) {
    const geometry = new THREE.BoxGeometry(...board.size);
    const mesh = new THREE.Mesh(geometry, state.materials[board.kind]);
    mesh.name = board.name; mesh.position.fromArray(board.position);
    mesh.castShadow = true; mesh.receiveShadow = true;
    mesh.userData = { kind: 'modularBoard', boardKind: board.kind, size: [...board.size], layoutKey: layout.key };
    group.add(mesh); state.ownedGeometries.add(geometry);
  }
  state.groups.set(layout.key, group); state.shelfRoot.add(group); return group;
}
function transformedBounds(value, parent, THREE) {
  return new THREE.Box3(new THREE.Vector3().fromArray(value.min), new THREE.Vector3().fromArray(value.max)).applyMatrix4(parent.matrixWorld);
}

/**
 * Apply fixed-scale shelf layout and return geometry/bounds metadata.
 *
 * Call after GLTFLoader finishes and before saving interaction rest transforms.
 * Callers should close/cancel pulls before a layout change, then refresh their
 * rest-transform cache from movedNodes. Calling the same key again is a no-op:
 * it does not accidentally close a currently inspected book or opened drawer.
 *
 * Resource ownership: this function NEVER disposes anything. On final scene
 * teardown union ownedGeometries/ownedMaterials with resources collected by
 * traversing the live scene, then dispose each resource once. These Sets remain
 * live and include retired original boards and every cached modular group.
 * All owned objects remain under root, hidden when inactive, so an existing
 * whole-scene disposal traversal also works without special cleanup.
 */
export function applyLayout(root, key, THREE) {
  const layout = layoutFor(key), check = validateLayout(layout);
  if (!check.ok) throw new Error(check.errors.join(' '));
  const state = STATES.get(root) || setup(root, THREE);
  const missing = Object.keys(layout.placements).filter(name => !state.semantic.has(name));
  if (missing.length) throw new Error(`Shelf semantic objects are missing: ${missing.join(', ')}`);
  if (state.key !== key) {
    if (state.group) state.group.visible = false;
    state.group = state.groups.get(key) || makeGroup(layout, state, THREE);
    state.group.visible = true;
    state.movedNodes = [];
    for (const [name, position] of Object.entries(layout.placements)) {
      const node = state.semantic.get(name), rest = state.rest.get(node);
      node.position.fromArray(position);
      if (rest) { node.quaternion.copy(rest.quaternion); node.scale.copy(rest.scale); }
      node.updateMatrix();
      if (!node.userData.sourceRestTranslationGltf) node.userData.sourceRestTranslationGltf = rest ? rest.position.toArray() : position.slice();
      node.userData.restTranslationGltf = position.slice();
      node.userData.layoutRestTranslation = position.slice();
      node.userData.restLocation = [position[0], -position[2], position[1]];
      node.userData.layoutKey = key;
      if (rest) node.userData.restQuaternionGltf = rest.quaternion.toArray();
      state.movedNodes.push(node);
    }
    state.key = key; state.shelfRoot.userData.layoutKey = key;
  }
  root.updateMatrixWorld(true);
  // Pure layout.bounds stays immutable; result.bounds is a THREE world-space box.
  const bounds = transformedBounds(layout.bounds, state.shelfRoot, THREE);
  const interactionBounds = transformedBounds(layout.interactionBounds, state.shelfRoot, THREE);
  return {
    ...layout, layout, group: state.group, shelfRoot: state.shelfRoot,
    bounds, interactionBounds, movedNodes: state.movedNodes,
    ownedGeometries: state.ownedGeometries, ownedMaterials: state.ownedMaterials,
    detachedObjects: state.detachedObjects, retiredObjects: state.retiredObjects
  };
}

/** Return the live ownership state when the scene is disposed before another apply. */
export function layoutResources(root) {
  const state = STATES.get(root);
  return state ? { ownedGeometries: state.ownedGeometries, ownedMaterials: state.ownedMaterials, detachedObjects: state.detachedObjects, retiredObjects: state.retiredObjects } : null;
}
