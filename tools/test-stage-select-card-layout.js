'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert/strict');
const root = path.resolve(__dirname, '..');
const context = {};
vm.runInNewContext(fs.readFileSync(path.join(root, 'launcher/web/modules/stage-select/stage-select-card-layout.js'), 'utf8'), context);
const layout = context.StageSelectCardLayout;
const checks = [];

function obstacles(point, withLabel) {
    const result = [{ x: point.x - 22, y: point.y - 22, width: 44, height: 44 }];
    if (withLabel) result.push({ x: point.x - 68.5, y: point.y + 14, width: 137, height: 34 });
    return result;
}

function sizes(verticalHeight, sideHeight) {
    return {
        above: { width: 180, height: verticalHeight },
        below: { width: 180, height: verticalHeight },
        left: { width: 230, height: sideHeight },
        right: { width: 230, height: sideHeight }
    };
}

function place(point, preferredSide, withLabel) {
    return layout.place({
        point,
        obstacles: obstacles(point, withLabel !== false),
        sizes: sizes(150, 190),
        preferredSide,
        bounds: { width: 1024, height: 576, top: 54, inset: 8 }
    });
}

for (const [point, expected] of [
    [{ x: 512, y: 300 }, 'above'],
    [{ x: 512, y: 90 }, 'below'],
    [{ x: 512, y: 530 }, 'above']
]) {
    const result = place(point, 'above', true);
    assert.equal(result.side, expected);
    assert.equal(result.valid, true);
    for (const obstacle of obstacles(point, true)) assert.equal(layout.intersects(
        { x: result.left, y: result.top, width: result.width, height: result.height }, obstacle), false);
}
checks.push('vertical placement respects node/label geometry and stage bounds');

const side = place({ x: 110, y: 300 }, 'right', true);
assert.equal(side.side, 'right');
const remembered = place({ x: 110, y: 300 }, side.side, true);
assert.equal(remembered.side, side.side);
assert.equal(remembered.left, side.left);
assert.equal(remembered.top, side.top);
checks.push('a valid preferred side remains stable across layout passes');

for (const x of [90, 512, 934]) for (const y of [120, 300, 510]) {
    const result = place({ x, y }, '', true);
    assert.equal(result.valid, true, `unresolved placement at ${x},${y}: ${result.side}`);
    assert.ok(result.left >= 8 && result.top >= 54);
    assert.ok(result.left + result.width <= 1016 && result.top + result.height <= 568);
}
checks.push('representative edge/corner points always retain a non-overlapping placement');

for (const [sideName, actionPosition] of [['above', 'bottom'], ['below', 'top'], ['left', 'bottom'], ['right', 'bottom']]) {
    const result = place({ x: 512, y: 300 }, sideName, false);
    assert.equal(result.side, sideName);
    assert.equal(result.connection.actionPosition, actionPosition, 'center ties keep the bottom action row');
    const midpoint = { x: (result.connection.x1 + result.connection.x2) / 2, y: (result.connection.y1 + result.connection.y2) / 2 };
    assert.equal(layout.contains(result.connection, midpoint), true);
    assert.equal(layout.contains(result.connection, { x: -100, y: -100 }), false);
    assert.equal(layout.contains(result.connection, { x: 512, y: 300 }), false, 'bridge must not replace the node hit area');
}
checks.push('all four connection paths accept the route without covering the origin node');

for (const [y, expected] of [[80, 'top'], [500, 'bottom']]) {
    const result = place({ x: 650, y }, 'right', false);
    assert.equal(result.side, 'right');
    assert.equal(result.valid, true);
    assert.equal(result.connection.actionPosition, expected);
    if (expected === 'top') assert.ok(result.connection.y2 >= result.top && result.connection.y2 <= result.top + 40);
    else assert.ok(result.connection.y2 >= result.top + result.height - 40 && result.connection.y2 <= result.top + result.height);
}
checks.push('side cards use the nearer vertical action edge and the connector targets that row');

assert.equal(layout.intersects({ x: 0, y: 0, width: 10, height: 10 }, { x: 9, y: 9, width: 10, height: 10 }), true);
assert.equal(layout.intersects({ x: 0, y: 0, width: 10, height: 10 }, { x: 20, y: 20, width: 10, height: 10 }), false);
checks.push('rectangle intersection primitive');

console.log(JSON.stringify({ pass: true, checks }, null, 2));
