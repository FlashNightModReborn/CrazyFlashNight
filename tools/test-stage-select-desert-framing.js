'use strict';
const assert = require('assert/strict');
const path = require('path');
const { pathToFileURL } = require('url');
const root = path.resolve(__dirname, '..');
async function main() {
    const THREE = await import(pathToFileURL(path.join(root, 'launcher/web/assets/stage-diorama/base-gate/vendor/three.module.js')).href);
    const { frameDesertOwner, reserveObservationFrame } = await import(pathToFileURL(path.join(root, 'launcher/web/modules/stage-select/stage-select-desert-scene.js')).href);
    // A courtyard and one tall mast: the other three corners have no tall geometry.
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.Float32BufferAttribute([-2, 0, -2, 2, 0, -2, 2, 0, 2, -2, 0, 2, 2, 6, 2], 3));
    const mesh = new THREE.Mesh(geometry); mesh.position.set(31, .4, -22); mesh.updateMatrixWorld(true);
    const before = [...geometry.attributes.position.array];
    const world = new THREE.Box3().setFromObject(mesh, true), bounds = { min: world.min.toArray(), max: world.max.toArray() };
    const config = { gltfPosition: [-40, 80, 100], gltfTarget: [0, 0, 0], minSpan: 1.5, maxSpan: 600 };
    const result = frameDesertOwner(config, bounds, [mesh]), fallback = frameDesertOwner(config, bounds);
    assert.equal(result.framing.source, 'owner-vertices'); assert.equal(result.framing.vertices, 5);
    assert.equal(fallback.framing.source, 'bounds-fallback');
    assert.ok(result.camera.span < fallback.camera.span * .9, 'Actual geometry must avoid imaginary high courtyard corners');
    const probe = new THREE.PerspectiveCamera(); probe.position.fromArray(result.camera.position);
    probe.lookAt(new THREE.Vector3(...result.camera.target)); probe.updateMatrixWorld(true);
    const projected = new THREE.Box3(), point = new THREE.Vector3();
    for (let i = 0; i < geometry.attributes.position.count; i++) {
        point.fromBufferAttribute(geometry.attributes.position, i).applyMatrix4(mesh.matrixWorld).applyMatrix4(probe.matrixWorldInverse);
        projected.expandByPoint(point);
        assert.ok(Math.abs(point.x) <= result.camera.span / 2 / 1.15 + 1e-6);
        assert.ok(Math.abs(point.y) <= result.camera.span / 1.17 / 2 / 1.15 + 1e-6, 'The full mast must stay inside the frame');
    }
    assert.ok(Math.abs(projected.min.x + projected.max.x) < 1e-6);
    assert.ok(Math.abs(projected.min.y + projected.max.y) < 1e-6);
    assert.deepEqual([...geometry.attributes.position.array], before, 'Framing must not alter source geometry');
    const rawFrame = JSON.stringify(result), reserved = reserveObservationFrame(result, config, 592, 504, 56);
    probe.position.fromArray(reserved.camera.position); probe.lookAt(new THREE.Vector3(...reserved.camera.target)); probe.updateMatrixWorld(true);
    for (let i = 0; i < geometry.attributes.position.count; i++) {
        point.fromBufferAttribute(geometry.attributes.position, i).applyMatrix4(mesh.matrixWorld).applyMatrix4(probe.matrixWorldInverse);
        const y = 504 / 2 - point.y * 592 / reserved.camera.span;
        assert.ok(y >= 0 && y <= 504 - 56, 'Real vertices, including the mast and courtyard floor, must avoid the bottom controls');
    }
    assert.equal(JSON.stringify(result), rawFrame, 'Reopening must reuse an unchanged source frame instead of accumulating offsets');
    assert.ok(reserved.framing.projectedPixels.bottom <= 448);
    mesh.scale.setScalar(.02); mesh.updateMatrixWorld(true);
    assert.equal(frameDesertOwner(config, bounds, [mesh]).camera.span, 1.5);
    console.log(JSON.stringify({ pass: true, scope: 'Actual transformed vertices, sparse tall-object framing, complete silhouette, centering, safe minimum and bounds fallback', actualSpan: result.camera.span, emptyBoxSpan: fallback.camera.span }));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
