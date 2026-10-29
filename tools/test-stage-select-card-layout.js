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

function place(point, preferredSide, withLabel, extra) {
    return layout.place(Object.assign({
        point,
        obstacles: obstacles(point, withLabel !== false),
        sizes: sizes(180, 190),
        preferredSide,
        bounds: { width: 1024, height: 576, top: 54, inset: 8 }
    }, extra || {}));
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

// Flash 手感合同：默认停靠只在上/下，且与调用历史（preferredSide）无关——同一几何恒得同一结果。
for (const x of [20, 90, 300, 512, 760, 934, 1004]) for (let y = 70; y <= 540; y += 20) {
    const baseline = place({ x, y }, 'above', true);
    assert.ok(baseline.side === 'above' || baseline.side === 'below', `side-facing card at ${x},${y}: ${baseline.side}`);
    for (const preferred of ['right', 'left', '', 'below-ish']) {
        const again = place({ x, y }, preferred, true);
        if (preferred !== 'below') {
            assert.equal(again.side, baseline.side, `history-dependent side at ${x},${y} (preferred ${preferred})`);
            assert.equal(again.top, baseline.top);
            assert.equal(again.left, baseline.left);
        }
    }
}
checks.push('default placement is vertical-only and deterministic regardless of remembered/preferred side');

// 卡片封顶高度下（≤180），任意舞台点都能找到不压节点的上/下停靠。
for (const x of [90, 512, 934]) for (const y of [80, 120, 200, 300, 400, 510]) {
    const result = place({ x, y }, 'above', true);
    assert.equal(result.valid, true, `unresolved vertical placement at ${x},${y}: ${result.side}`);
    assert.ok(result.left >= 8 && result.top >= 54);
    assert.ok(result.left + result.width <= 1016 && result.top + result.height <= 568);
}
checks.push('capped-height cards always retain a non-overlapping vertical placement');

for (const [sideName, actionPosition] of [['above', 'bottom'], ['below', 'top']]) {
    const result = place({ x: 512, y: 300 }, sideName, false, { sides: [sideName] });
    assert.equal(result.side, sideName);
    assert.equal(result.connection.actionPosition, actionPosition, 'difficulty row faces the node');
    const midpoint = { x: (result.connection.x1 + result.connection.x2) / 2, y: (result.connection.y1 + result.connection.y2) / 2 };
    assert.equal(layout.contains(result.connection, midpoint), true);
    assert.equal(layout.contains(result.connection, { x: -100, y: -100 }), false);
    assert.equal(layout.contains(result.connection, { x: 512, y: 300 }), false, 'bridge must not replace the node hit area');
}
checks.push('vertical connection paths put the action row on the node-facing edge without covering the origin node');

// 侧向停靠只在调用方显式 opt-in 时可用（保留几何能力，默认不启用）。
for (const [y, expected] of [[80, 'top'], [500, 'bottom']]) {
    const result = place({ x: 650, y }, 'right', false, { sides: ['right'] });
    assert.equal(result.side, 'right');
    assert.equal(result.valid, true);
    assert.equal(result.connection.actionPosition, expected);
    if (expected === 'top') assert.ok(result.connection.y2 >= result.top && result.connection.y2 <= result.top + 40);
    else assert.ok(result.connection.y2 >= result.top + result.height - 40 && result.connection.y2 <= result.top + result.height);
}
checks.push('explicit side opt-in keeps the nearer vertical action edge');

assert.equal(layout.intersects({ x: 0, y: 0, width: 10, height: 10 }, { x: 9, y: 9, width: 10, height: 10 }), true);
assert.equal(layout.intersects({ x: 0, y: 0, width: 10, height: 10 }, { x: 20, y: 20, width: 10, height: 10 }), false);
checks.push('rectangle intersection primitive');

console.log(JSON.stringify({ pass: true, checks }, null, 2));
