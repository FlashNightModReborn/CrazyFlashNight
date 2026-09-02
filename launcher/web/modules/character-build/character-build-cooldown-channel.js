/** Read-only projection and polling for the four frame-authoritative drug lanes. */
(function(root, factory) {
    'use strict';
    var api = factory(root);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CharacterBuildCooldownChannel = api;
})(typeof window !== 'undefined' ? window : globalThis, function(global) {
    'use strict';

    var LANE_COUNT = 4;
    var MAX_SAFE_INTEGER = 9007199254740991;
    var KEYS = ['lane', 'ready', 'totalSteps', 'currentStep',
        'progressPercent', 'animationFrame', 'remainingMs'];

    function whole(value, minimum, maximum) {
        value = Number(value);
        return isFinite(value) && Math.floor(value) === value
            && value >= minimum && value <= maximum ? value : null;
    }
    function exact(value) {
        if (!value || typeof value !== 'object' || Array.isArray(value)
                || Object.keys(value).length !== KEYS.length) return false;
        for (var i = 0; i < KEYS.length; i++) {
            if (!Object.prototype.hasOwnProperty.call(value, KEYS[i])) return false;
        }
        return true;
    }
    function normalize(rows) {
        if (!Array.isArray(rows) || rows.length !== LANE_COUNT) return null;
        var result = [];
        for (var lane = 0; lane < LANE_COUNT; lane++) {
            var row = rows[lane];
            var total = whole(row && row.totalSteps, 0, 2147483647);
            var current = whole(row && row.currentStep, 0, 2147483647);
            var progress = whole(row && row.progressPercent, 0, 100);
            var frame = whole(row && row.animationFrame, 0, 101);
            var remaining = whole(row && row.remainingMs, 0, MAX_SAFE_INTEGER);
            if (!exact(row) || row.lane !== lane || typeof row.ready !== 'boolean'
                    || total === null || current === null || current > total
                    || progress === null || frame === null || remaining === null
                    || (row.ready && remaining !== 0)
                    || (!row.ready && (total < 1 || current >= total || remaining < 1))
                    || frame !== (row.ready ? 1 : 1 + progress)) return null;
            result.push({lane:lane, ready:row.ready, totalSteps:total,
                currentStep:current, progressPercent:progress,
                animationFrame:frame, remainingMs:remaining});
        }
        return result;
    }
    function rowsFromSnapshot(snapshot) {
        var meta = snapshot && snapshot.drugMeta || {}, lanes = [];
        for (var lane = 0; lane < LANE_COUNT; lane++) {
            var row = meta['drug' + String(lane + 1)]
                || meta['drug' + String(lane + 5)] || {};
            lanes.push({lane:lane, keyLabel:String(row.keyLabel || lane + 1),
                ready:row.ready === true, totalSteps:Number(row.totalSteps) || 0,
                currentStep:Number(row.currentStep) || 0,
                progressPercent:Number(row.progressPercent) || 0,
                remainingMs:Number(row.remainingMs) || 0});
        }
        return lanes;
    }
    function nodes(controller) {
        if (!controller._view || !controller._view.root) return [];
        // Character snapshots rebuild the eight slot buttons in place. Querying eight
        // nodes per sampled frame avoids retaining detached cards as a false projection.
        return Array.prototype.slice.call(controller._view.root.querySelectorAll(
            '.character-build-slot[data-slot-kind="drug"][data-drug-lane]'));
    }
    function updateSlotAria(node, value, unavailable) {
        if (!node || typeof node.getAttribute !== 'function') return;
        var base = node.getAttribute('data-drug-cooldown-aria-base');
        if (!base) {
            base = String(node.getAttribute('aria-label') || '药剂槽')
                .replace(/，冷却(?:就绪|中)$/, '');
            node.setAttribute('data-drug-cooldown-aria-base', base);
        }
        node.setAttribute('aria-label', base + (value.ready ? '，冷却就绪'
            : unavailable ? '，冷却状态不可用'
                : '，冷却中，已完成 ' + String(value.progressPercent) + '%'));
    }
    function render(controller, rows) {
        if (!Array.isArray(rows) || rows.length !== LANE_COUNT) return false;
        var previous = controller._itemUseCooldownLanes || [], values = [];
        for (var lane = 0; lane < LANE_COUNT; lane++) {
            var row = rows[lane] || {};
            if (Number(row.lane) !== lane || typeof row.ready !== 'boolean') return false;
            var total = Math.max(0, Math.floor(Number(row.totalSteps) || 0));
            values[lane] = {lane:lane,
                keyLabel:String(row.keyLabel
                    || previous[lane] && previous[lane].keyLabel || lane + 1),
                ready:row.ready, totalSteps:total,
                progressPercent:Math.max(0, Math.min(100,
                    Math.floor(Number(row.progressPercent) || 0))),
                remainingMs:Math.max(0, Number(row.remainingMs) || 0)};
        }
        controller._itemUseCooldownLanes = values;
        var recent = controller._itemUseLastCooldownLane;
        if (recent >= 0 && values[recent] && !values[recent].ready) {
            controller._itemUseLastCooldownObservedActive = true;
        } else if (recent >= 0 && controller._itemUseLastCooldownObservedActive) {
            controller._itemUseLastCooldownLane = -1;
            controller._itemUseLastCooldownObservedActive = false;
        }
        var laneNodes = nodes(controller);
        for (var index = 0; index < laneNodes.length; index++) {
            var node = laneNodes[index];
            lane = whole(node && node.getAttribute
                ? node.getAttribute('data-drug-lane') : null, 0, LANE_COUNT - 1);
            if (lane === null) continue;
            var value = values[lane];
            var unavailable = !value.ready && value.totalSteps < 1;
            var progress = value.ready ? 100 : value.progressPercent;
            node.setAttribute('data-drug-state', value.ready ? 'ready'
                : unavailable ? 'unavailable' : 'cooling');
            node.setAttribute('data-drug-ready', value.ready ? 'true' : 'false');
            node.setAttribute('data-recent',
                lane === controller._itemUseLastCooldownLane ? 'true' : 'false');
            node.setAttribute('data-cooldown-progress', String(progress));
            node.setAttribute('data-cooldown-remaining-ms',
                String(value.remainingMs));
            if (node.style && typeof node.style.setProperty === 'function') {
                node.style.setProperty(
                '--drug-cooldown-progress', String(progress) + '%');
            }
            updateSlotAria(node, value, unavailable);
        }
        return true;
    }
    function note(controller, lane) {
        lane = whole(lane, 0, LANE_COUNT - 1);
        if (lane === null) return false;
        controller._itemUseLastCooldownLane = lane;
        controller._itemUseLastCooldownObservedActive = false;
        return render(controller, controller._itemUseCooldownLanes
            || rowsFromSnapshot(null));
    }
    function stop(controller) {
        controller._itemUseCooldownGeneration =
            Number(controller._itemUseCooldownGeneration || 0) + 1;
        if (controller._itemUseCooldownTimer != null
                && global && typeof global.clearTimeout === 'function') {
            global.clearTimeout(controller._itemUseCooldownTimer);
        }
        controller._itemUseCooldownTimer = null;
        return true;
    }
    function start(controller) {
        if (!controller._view || !controller._itemUse) return false;
        stop(controller);
        var generation = controller._itemUseCooldownGeneration;
        function schedule(delay) {
            if (!global || typeof global.setTimeout !== 'function'
                    || generation !== controller._itemUseCooldownGeneration
                    || !controller._view) return;
            controller._itemUseCooldownTimer = global.setTimeout(function() {
                controller._itemUseCooldownTimer = null;
                sample();
            }, delay);
        }
        function sample() {
            if (generation !== controller._itemUseCooldownGeneration
                    || !controller._view) return;
            var callId = controller._itemUse.refreshCooldowns(
                function(_, accepted, lanes) {
                    if (generation !== controller._itemUseCooldownGeneration) return;
                    var active = accepted && lanes.some(function(row) {
                        return row.ready !== true;
                    });
                    if (active) schedule(200);
                    else if (!accepted) schedule(1000);
                });
            if (!callId && controller._itemUseCooldownTimer === null) schedule(1000);
        }
        sample();
        return true;
    }

    return {normalize:normalize, render:render,
        fromSnapshot:function(controller, snapshot) {
            return render(controller, rowsFromSnapshot(snapshot));
        }, note:note, start:start, stop:stop};
});
