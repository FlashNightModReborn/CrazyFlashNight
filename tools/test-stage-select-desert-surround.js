'use strict';
// Exercise presentation geometry separately from the source asset and gameplay catalog.
const assert = require('assert/strict');
const path = require('path');
const { pathToFileURL } = require('url');
const rootPath = path.resolve(__dirname, '..');
async function main() {
    const THREE = await import(pathToFileURL(path.join(rootPath, 'launcher/web/assets/stage-diorama/base-gate/vendor/three.module.js')).href);
    const { createDesertSurround } = await import(pathToFileURL(path.join(rootPath, 'launcher/web/modules/stage-select/stage-select-desert-surround.js')).href);
    const root = new THREE.Group(), points = [[-95, .04, 65], [90, .06, 65], [90, .5, -110], [-95, 2, -110]];
    const soil = new THREE.Texture(); soil.name = 'R10 normalized soil grain';
    const palette = new THREE.Texture(); palette.name = 'terrain-geographic-palette.png';
    const terrain = new THREE.BufferGeometry();
    terrain.setAttribute('position', new THREE.Float32BufferAttribute(points.flat(), 3));
    terrain.setAttribute('color', new THREE.Float32BufferAttribute(points.flatMap(() => [.44, .32, .2]), 3));
    terrain.setAttribute('uv', new THREE.Float32BufferAttribute(points.flatMap(([x, , z]) => [-z * .24, 1 + x * .24]), 2));
    terrain.setIndex([0, 2, 1, 0, 3, 2]);
    const top = new THREE.Mesh(terrain, new THREE.MeshBasicMaterial({ map: soil, vertexColors: true }));
    top.userData.placeId = 'environment'; root.add(top);
    const walls = new THREE.BufferGeometry(), wallPoints = [];
    for (let i = 0; i < 4; i++) {
        const a = points[i], b = points[(i + 1) % 4], c = [a[0], -2, a[2]], d = [b[0], -2, b[2]];
        wallPoints.push(...a, ...b, ...c, ...c, ...b, ...d);
    }
    walls.setAttribute('position', new THREE.Float32BufferAttribute(wallPoints, 3));
    const cut = new THREE.Mesh(walls, new THREE.MeshBasicMaterial({ map: palette }));
    cut.name = 'unstable_batch_77'; cut.userData.placeId = 'environment'; root.add(cut);
    const cityWall = cut.clone(); cityWall.name = 'city_wall'; cityWall.userData = { placeId: 'fallen' }; root.add(cityWall);
    const platform = cut.clone(); platform.name = 'real_local_platform'; platform.userData = { placeId: 'environment' };
    platform.scale.set(.1, 1, .1); root.add(platform);
    const before = Object.fromEntries(Object.entries(terrain.attributes).map(([key, value]) => [key, [...value.array]]));
    const surround = createDesertSurround(root);
    assert.equal(cut.visible, false, 'Only the proven rectangular cut-earth walls are hidden');
    assert.equal(cityWall.visible, true, 'City walls must remain visible');
    assert.equal(platform.visible, true, 'Local platform walls must remain visible');
    for (const [key, value] of Object.entries(terrain.attributes)) assert.deepEqual([...value.array], before[key]);
    assert.equal(surround.object.material.map, soil, 'Presentation apron reuses the exact source grain texture');
    assert.equal(surround.object.userData.presentationOnly, true);
    const hits = []; surround.object.raycast(null, hits); assert.deepEqual(hits, [], 'Presentation apron cannot select a stage');
    const camera = new THREE.OrthographicCamera(-163.434 / 2, 163.434 / 2, 163.434 * 576 / 1024 / 2, -163.434 * 576 / 1024 / 2, .01, 5000);
    camera.position.set(-134.786, 196.878, 223.472); camera.lookAt(-4.262, .164, -2.603); camera.updateMatrixWorld(true);
    const stats = surround.stats(camera);
    assert.equal(stats.groundPlaneViewportCovered, true);
    assert.equal(stats.hiddenCutWalls.length, 1); assert.equal(stats.hiddenCutWalls[0].triangles, 8);
    assert.ok(stats.uvFitMaxError < .0001);
    assert.equal(stats.sourceBoundaryVertices, 4);
    assert.ok(stats.outerBounds.min[0] < stats.sourceTopBounds.min[0] && stats.outerBounds.max[2] > stats.sourceTopBounds.max[2]);
    console.log(JSON.stringify({ pass: true, scope: 'Derived perimeter continuation, UV continuity, wall identity, source invariance and default viewport coverage', ...stats }));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
