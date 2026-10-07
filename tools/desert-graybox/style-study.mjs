import { createTerrainStudy } from './terrain-study.mjs';
import { createLandmarkStudy } from './landmark-study.mjs';

// A reversible browser presentation study. The geographic model and GLB exporter
// remain authoritative for the spatial graybox, not these display treatments.
export function createStyleStudy(THREE, model, data) {
  const terrain = createTerrainStudy(THREE, model, data);
  const landmarks = createLandmarkStudy(THREE, model, data);
  const changes = [];
  for (const root of [model.routes.group, model.routes.surfaceGroup, model.environment.group]) root.traverse(mesh => {
    if (!mesh.isMesh) return;
    const original = mesh.material, styled = original.clone();
    const kind = mesh.userData.kind;
    const palette = { civil: '#736049', military: '#675745', danger: '#8b7150', surface: '#50655c' };
    if (palette[kind]) styled.color.set(palette[kind]);
    else styled.color.lerp(new THREE.Color('#746047'), .55).multiplyScalar(.8);
    changes.push({ mesh, original, styled, castShadow: mesh.castShadow });
  });
  return {
    setEnabled(enabled) {
      terrain.setEnabled(enabled); landmarks.setEnabled(enabled);
      for (const c of changes) { c.mesh.material = enabled ? c.styled : c.original; c.mesh.castShadow = enabled ? false : c.castShadow; }
    },
    dispose() {
      this.setEnabled(false); terrain.dispose(); landmarks.dispose();
      for (const c of changes) c.styled.dispose();
    },
  };
}
