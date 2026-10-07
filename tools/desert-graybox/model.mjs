import * as THREE from '../../launcher/web/assets/stage-diorama/base-gate/vendor/three.module.js';
import { createTerrain } from './terrain.mjs';
import { createRoutes } from './routes.mjs';
import { createLandmarks } from './landmarks.mjs';
import { createSurroundings } from './composition.mjs';
import { createEnvironment } from './environment.mjs';

export { THREE };
export const MODES = ['region', 'city', 'base'];

export function createGraybox(data, mode = 'region') {
  if (!MODES.includes(mode)) throw new Error('Unknown graybox scale: ' + mode);
  const terrain = createTerrain(THREE, data, mode);
  const routes = createRoutes(THREE, data, mode, terrain);
  const landmarks = createLandmarks(THREE, data, mode, terrain);
  const environment = createEnvironment(THREE,data,mode,terrain);
  const surroundings = createSurroundings(THREE, terrain);
  const group = new THREE.Group(); group.name = 'DESERT_GRAYBOX_' + mode;
  group.userData = {
    role: 'editable design graybox, not production game scene', mode,
    coordinates: 'X east km, Z negative north km, Y candidate elevation metres / 1000 * verticalExaggeration',
    verticalExaggeration: terrain.verticalExaggeration,
    source: 'docs/design-data/desert-spatial-draft.json',
    status: 'graybox_candidate',
  };
  terrain.group.name ||= 'TERRAIN'; routes.group.name ||= 'ROADS'; routes.waterGroup.name ||= 'WATER_REVIEW';
  routes.waterGroup.userData.defaultVisible = false;
  group.add(terrain.group,routes.group,routes.surfaceGroup,routes.waterGroup,landmarks.group,environment.group,surroundings);
  const anchorGroup = new THREE.Group(); anchorGroup.name = 'GEOGRAPHIC_ANCHORS';
  for (const item of landmarks.anchors) {
    const point = data.places.find(n => n.id === item.id);
    if (!point) throw new Error('Unknown landmark: ' + item.id);
    const anchor = new THREE.Object3D(); anchor.name = 'ANCHOR_' + item.id;
    anchor.position.copy(terrain.world(point.xy));
    anchor.userData = {
      placeId: item.id, name: point.name, geographicXY: point.xy,
      elevationM: terrain.heightAt(...point.xy), verticalExaggeration: terrain.verticalExaggeration,
      stageIds: data.stageMapping.filter(n => n.place === item.id).map(n => n.id),
      anchorPurpose: 'geographic reference; object footprint may be symbolically enlarged',
    };
    anchorGroup.add(anchor);
  }
  group.add(anchorGroup); group.updateMatrixWorld(true);
  let meshes = 0, triangles = 0, vertices = 0;
  group.traverse(object => {
    if (!object.isMesh) return;
    const positions = object.geometry.getAttribute('position');
    if (!positions) throw new Error('Mesh without positions: ' + object.name);
    if (Array.from(positions.array).some(v => !Number.isFinite(v))) throw new Error('Non-finite geometry: ' + object.name);
    meshes++; vertices += positions.count;
    triangles += (object.geometry.index?.count || positions.count) / 3;
    object.castShadow = true; object.receiveShadow = true;
  });
  const bounds = new THREE.Box3().setFromObject(group);
  return { group,terrain,routes,landmarks,environment,surroundings,anchors:landmarks.anchors,bounds,
    metrics: { mode, meshes, vertices, triangles, anchors: landmarks.anchors.length, verticalExaggeration: terrain.verticalExaggeration, routes: routes.metrics,environment:environment.metrics } };
}

export function disposeGraybox(model) {
  const geometries = new Set(), materials = new Set();
  model.group.traverse(o => {
    if (o.geometry) geometries.add(o.geometry);
    for (const m of [].concat(o.material || [])) materials.add(m);
  });
  geometries.forEach(g => g.dispose()); materials.forEach(m => m.dispose());
  model.group.removeFromParent();
}
