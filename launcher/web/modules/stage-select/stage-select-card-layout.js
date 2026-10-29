var StageSelectCardLayout = (function() {
    'use strict';

    // 快捷卡停靠合同（2026-10-29 Flash 手感回归）：默认只在节点上方，放不下才翻到下方；
    // 不做左右停靠、不记忆上次方向——难度行相对节点的方向与偏移必须可盲点（老玩家肌肉记忆），
    // 侧向停靠会把最远难度键拉到 200px 以外。左右分支仅在调用方显式传 options.sides 时启用。
    var SIDES = ['above', 'below'];
    var ALL_SIDES = ['above', 'below', 'right', 'left'];

    function clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }

    function number(value, fallback) {
        return Number.isFinite(value) ? value : fallback;
    }

    function rect(input) {
        return {
            x: number(input && input.x, 0),
            y: number(input && input.y, 0),
            width: Math.max(0, number(input && input.width, 0)),
            height: Math.max(0, number(input && input.height, 0))
        };
    }

    function right(value) { return value.x + value.width; }
    function bottom(value) { return value.y + value.height; }

    function overlapArea(a, b) {
        return Math.max(0, Math.min(right(a), right(b)) - Math.max(a.x, b.x))
            * Math.max(0, Math.min(bottom(a), bottom(b)) - Math.max(a.y, b.y));
    }

    function intersects(a, b) {
        return overlapArea(a, b) > 0.5;
    }

    function union(obstacles) {
        var result = obstacles.length ? rect(obstacles[0]) : null;
        if (!result) return null;
        obstacles.slice(1).forEach(function(item) {
            var next = rect(item), x = Math.min(result.x, next.x), y = Math.min(result.y, next.y);
            result = {
                x: x,
                y: y,
                width: Math.max(right(result), right(next)) - x,
                height: Math.max(bottom(result), bottom(next)) - y
            };
        });
        return result;
    }

    function distanceToRect(point, value) {
        var dx = Math.max(value.x - point.x, 0, point.x - right(value));
        var dy = Math.max(value.y - point.y, 0, point.y - bottom(value));
        return Math.hypot(dx, dy);
    }

    function connectionFor(point, value, side, nodeRadius, bridgeWidth) {
        var end, actionPosition = 'bottom';
        if (side === 'above' || side === 'below') {
            actionPosition = side === 'above' ? 'bottom' : 'top';
            end = {
                x: clamp(point.x, value.x + 8, right(value) - 8),
                y: side === 'above' ? bottom(value) : value.y
            };
        } else {
            actionPosition = point.y - value.y < bottom(value) - point.y ? 'top' : 'bottom';
            var bandMin = value.y + 8, bandMax = bottom(value) - 8;
            if (actionPosition === 'top') bandMax = Math.min(bandMax, value.y + 40);
            else bandMin = Math.max(bandMin, bottom(value) - 40);
            end = {
                x: side === 'left' ? right(value) : value.x,
                y: clamp(point.y, Math.min(bandMin, bandMax), Math.max(bandMin, bandMax))
            };
        }
        var dx = end.x - point.x, dy = end.y - point.y, length = Math.hypot(dx, dy);
        var offset = Math.min(number(nodeRadius, 22) + 2, Math.max(0, length - 4));
        var start = length ? { x: point.x + dx / length * offset, y: point.y + dy / length * offset } : { x: point.x, y: point.y };
        return {
            x1: start.x,
            y1: start.y,
            x2: end.x,
            y2: end.y,
            width: Math.max(12, number(bridgeWidth, 28)),
            actionPosition: actionPosition
        };
    }

    function contains(connection, point, tolerance) {
        if (!connection) return false;
        var dx = connection.x2 - connection.x1, dy = connection.y2 - connection.y1;
        var lengthSquared = dx * dx + dy * dy;
        var t = lengthSquared ? ((point.x - connection.x1) * dx + (point.y - connection.y1) * dy) / lengthSquared : 0;
        t = clamp(t, 0, 1);
        var x = connection.x1 + dx * t, y = connection.y1 + dy * t;
        return Math.hypot(point.x - x, point.y - y) <= connection.width / 2 + number(tolerance, 0);
    }

    function place(options) {
        var point = { x: number(options.point && options.point.x, 0), y: number(options.point && options.point.y, 0) };
        var obstacles = (options.obstacles || []).map(rect);
        var node = obstacles.length ? union(obstacles) : { x: point.x - 22, y: point.y - 22, width: 44, height: 44 };
        var bounds = options.bounds || {};
        var frame = {
            left: number(bounds.inset, 8),
            top: number(bounds.top, 54),
            right: number(bounds.width, 1024) - number(bounds.inset, 8),
            bottom: number(bounds.height, 576) - number(bounds.inset, 8)
        };
        var gap = number(options.gap, 8);
        // 上/下停靠的水平中心：默认信标；三维地名常偏离信标，调用方可传信标+地名的并集中心，
        // 让悬停在信标或地名上的光标到难度行都保持短行程。连接桥仍从信标出发。
        var centerX = number(options.centerX, point.x);
        var sides = Array.isArray(options.sides) && options.sides.length
            ? options.sides.filter(function(side) { return ALL_SIDES.indexOf(side) >= 0; })
            : SIDES;
        if (!sides.length) sides = SIDES;
        var order = sides.slice();
        if (sides.indexOf(options.preferredSide) >= 0) {
            order = [options.preferredSide].concat(sides.filter(function(side) { return side !== options.preferredSide; }));
        }
        var candidates = order.map(function(side, index) {
            var size = options.sizes && (options.sizes[side] || options.sizes.above) || { width: 220, height: 240 };
            var width = Math.max(1, number(size.width, 220)), height = Math.max(1, number(size.height, 240));
            var value;
            if (side === 'above') value = { x: centerX - width / 2, y: node.y - gap - height, width: width, height: height };
            else if (side === 'below') value = { x: centerX - width / 2, y: bottom(node) + gap, width: width, height: height };
            else if (side === 'left') value = { x: node.x - gap - width, y: point.y - height / 2, width: width, height: height };
            else value = { x: right(node) + gap, y: point.y - height / 2, width: width, height: height };
            value.x = clamp(value.x, frame.left, Math.max(frame.left, frame.right - width));
            value.y = clamp(value.y, frame.top, Math.max(frame.top, frame.bottom - height));
            var collision = obstacles.reduce(function(sum, obstacle) { return sum + overlapArea(value, obstacle); }, 0);
            var outside = Math.max(0, frame.left - value.x) + Math.max(0, right(value) - frame.right)
                + Math.max(0, frame.top - value.y) + Math.max(0, bottom(value) - frame.bottom);
            return {
                side: side,
                left: value.x,
                top: value.y,
                width: width,
                height: height,
                valid: collision <= 0.5 && outside <= 0.5,
                score: collision * 1000 + outside * 100 + distanceToRect(point, value) + index * 0.01
            };
        });
        var chosen = candidates.filter(function(candidate) { return candidate.valid; })[0];
        if (!chosen) chosen = candidates.slice().sort(function(a, b) { return a.score - b.score; })[0];
        chosen.connection = connectionFor(point, { x: chosen.left, y: chosen.top, width: chosen.width, height: chosen.height }, chosen.side, options.nodeRadius, options.bridgeWidth);
        return chosen;
    }

    return { place: place, contains: contains, intersects: intersects };
})();
