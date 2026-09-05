import assert from 'node:assert/strict';
import test from 'node:test';
import { createGame } from '../src/core/state.js';
import { mapProjectionFrame, projectNodes } from '../src/app/presenter.js';
import {
  ActionCameraLeaseRegistry,
  actionCameraViewForPoints,
  cameraDetailTier,
  cameraLimitsFor,
  cameraZoomPercent,
  clampCameraView,
  computeWorldBounds,
  fitCameraToBounds,
  tacticalMarkerScale,
  zoomCameraView,
} from '../src/scene/camera-policy.js';

test('PHASE-A-CAMERA action leases retain the complete pre-action view by value', () => {
  const leases = new ActionCameraLeaseRegistry();
  const original = { centerX: 12, centerZ: -7, halfHeight: 4.5 };
  const token = leases.begin(original);
  original.centerX = 99;
  assert.deepEqual(leases.returnView(token), { centerX: 12, centerZ: -7, halfHeight: 4.5 });
  assert.equal(leases.release(token), true);
  assert.equal(leases.returnView(token), null);
});

test('PHASE-A-CAMERA consecutive AI movements reuse one token and the first player return view', () => {
  const leases = new ActionCameraLeaseRegistry();
  const first = leases.beginOrContinue({ centerX: -8, centerZ: 3, halfHeight: 2.5 });
  const continued = leases.beginOrContinue({ centerX: 24, centerZ: -11, halfHeight: 7 });
  assert.deepEqual(first, { token: 1, continued: false });
  assert.deepEqual(continued, { token: 1, continued: true });
  assert.deepEqual(leases.returnView(first.token), { centerX: -8, centerZ: 3, halfHeight: 2.5 });
  assert.equal(leases.activeToken(), first.token);
  assert.equal(leases.release(first.token), true);
  const nextBlock = leases.beginOrContinue({ centerX: 5, centerZ: 6, halfHeight: 4 });
  assert.deepEqual(nextBlock, { token: 2, continued: false });
});

test('PHASE-A-CAMERA cancelled and stale action lease tokens can never restore a newer view', () => {
  const leases = new ActionCameraLeaseRegistry();
  const stale = leases.begin({ centerX: 1, centerZ: 2, halfHeight: 3 });
  const current = leases.begin({ centerX: 4, centerZ: 5, halfHeight: 6 });
  assert.equal(leases.cancel(stale), false);
  assert.deepEqual(leases.returnView(current), { centerX: 4, centerZ: 5, halfHeight: 6 });
  assert.equal(leases.cancel(current), true);
  assert.equal(leases.isCancelled(current), true);
  assert.equal(leases.returnView(current), null);
  assert.equal(leases.release(stale), false);
  assert.equal(leases.release(current), true);
});

test('PHASE-A-CAMERA AI action path inside the comfort frame leaves the camera untouched', () => {
  const view = { centerX: 3, centerZ: -2, halfHeight: 10 };
  const next = actionCameraViewForPoints(view, [
    { x: -5, z: -7 },
    { x: 4, z: -2 },
    { x: 16, z: 4 },
  ], { aspect: 2, reducedMotion: false });
  assert.deepEqual(next, view);
});

test('PHASE-A-CAMERA AI action follow minimally shifts both axes and preserves zoom', () => {
  const view = { centerX: 0, centerZ: 0, halfHeight: 10 };
  const next = actionCameraViewForPoints(view, [
    { x: 0, z: 0 },
    { x: 8, z: 0 },
    { x: 18, z: 9 },
  ], { aspect: 2, reducedMotion: false });
  assert.deepEqual(next, { centerX: 4, centerZ: 2, halfHeight: 10 });
  assert.equal(Math.abs(18 - next.centerX), 14);
  assert.equal(Math.abs(9 - next.centerZ), 7);
});

test('PHASE-A-CAMERA reduced motion disables passive AI follow instead of snapping', () => {
  const view = { centerX: -4, centerZ: 3, halfHeight: 6 };
  const next = actionCameraViewForPoints(view, [
    { x: -4, z: 3 },
    { x: 40, z: -30 },
  ], { aspect: 16 / 9, reducedMotion: true });
  assert.deepEqual(next, view);
});

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

test('PHASE-A-CAMERA tactical badges reveal identifiable art at maximum zoom', () => {
  const atFit = tacticalMarkerScale(100);
  const tactical = tacticalMarkerScale(220);
  const maximum = tacticalMarkerScale(625);
  assert.equal(atFit, 1);
  assert.ok(tactical < 0.81 && tactical > 0.79);
  assert.ok(maximum < 0.55 && maximum > 0.54);
  assert.ok(tactical * 2.2 > 1.75 && tactical * 2.2 < 1.78);
  assert.ok(maximum * 6.25 > 3.39 && maximum * 6.25 < 3.401);
  assert.equal(tacticalMarkerScale(Number.NaN), 1);
});
