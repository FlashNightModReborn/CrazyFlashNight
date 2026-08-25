import assert from 'node:assert/strict';
import test from 'node:test';
import { createGame } from '../src/core/state.js';
import { mapProjectionFrame, projectNodes } from '../src/app/presenter.js';
import {
  cameraDetailTier,
  cameraLimitsFor,
  cameraZoomPercent,
  clampCameraView,
  computeWorldBounds,
  fitCameraToBounds,
  tacticalMarkerScale,
  zoomCameraView,
} from '../src/scene/camera-policy.js';

test('PHASE-A-CAMERA original nine-node projection remains pixel-composition compatible', () => {
  const state = createGame({ seed: 'camera-original-frame' });
  const frame = mapProjectionFrame(state);
  const nodes = new Map(projectNodes(state).map((node) => [node.nodeId, node]));
  assert.equal(frame.centerX, 470);
  assert.equal(frame.centerY, 210);
  assert.equal(nodes.get('R-HQ')?.x, -8.4);
  assert.equal(nodes.get('B-HQ')?.x, 8.4);
  assert.equal(nodes.get('North-Choke')?.z, -3.4);
  assert.equal(nodes.get('South-Depot')?.z, 3.4);
});

test('PHASE-A-CAMERA a synthetic 100-node field fits without coordinate compression', () => {
  const points = Array.from({ length: 100 }, (_, index) => ({
    x: (index % 10) * 4.2,
    z: Math.floor(index / 10) * 2.8,
  }));
  const bounds = computeWorldBounds(points);
  const aspect = 16 / 9;
  const fit = fitCameraToBounds(bounds, aspect);
  const halfWidth = fit.halfHeight * aspect;
  assert.ok(Math.abs(bounds.width - 37.8) < 1e-9);
  assert.ok(bounds.height > 25);
  assert.ok(points.every((point) => Math.abs(point.x - fit.centerX) <= halfWidth));
  assert.ok(points.every((point) => Math.abs(point.z - fit.centerZ) <= fit.halfHeight));
  assert.equal(cameraDetailTier(100, 100), 'overview');
});

test('PHASE-A-CAMERA zoom and pan stay bounded across overview and tactical levels', () => {
  const bounds = computeWorldBounds([
    { x: -18, z: -12 },
    { x: 18, z: 12 },
  ]);
  const aspect = 16 / 9;
  const limits = cameraLimitsFor(bounds, aspect);
  const fit = fitCameraToBounds(bounds, aspect);
  const tactical = zoomCameraView(fit, 2.5, limits);
  assert.ok(tactical.halfHeight < fit.halfHeight);
  assert.ok(cameraZoomPercent(tactical, limits) >= 240);
  assert.equal(cameraDetailTier(100, cameraZoomPercent(tactical, limits)), 'tactical');
  const clamped = clampCameraView(
    { ...tactical, centerX: 10_000, centerZ: -10_000 },
    bounds,
    aspect,
    limits,
  );
  assert.ok(Number.isFinite(clamped.centerX));
  assert.ok(Number.isFinite(clamped.centerZ));
  assert.ok(clamped.centerX < 10_000);
  assert.ok(clamped.centerZ > -10_000);

  const edgeFocus = clampCameraView(
    { ...tactical, centerX: bounds.minX, centerZ: bounds.centerZ },
    bounds,
    aspect,
    limits,
    Math.max(tactical.halfHeight, tactical.halfHeight * aspect),
  );
  assert.equal(edgeFocus.centerX, bounds.minX);
  assert.equal(edgeFocus.centerZ, bounds.centerZ);
});

test('PHASE-A-CAMERA tactical badges progressively reveal art with a bounded screen size', () => {
  const atFit = tacticalMarkerScale(100);
  const tactical = tacticalMarkerScale(220);
  const maximum = tacticalMarkerScale(625);
  assert.equal(atFit, 1);
  assert.ok(tactical < 0.68 && tactical > 0.67);
  assert.ok(maximum < 0.29 && maximum > 0.28);
  assert.ok(tactical * 2.2 > 1.47 && tactical * 2.2 < 1.5);
  assert.ok(maximum * 6.25 > 1.79 && maximum * 6.25 < 1.801);
  assert.equal(tacticalMarkerScale(Number.NaN), 1);
});
