/** Pure two-bank potion layout validation and view projection. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildDrugLayout = api;
        root.CharacterBuildDrugLayout = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var BANK_COUNT = 2;
    var LANE_COUNT = 4;
    var PHYSICAL_SLOT_COUNT = 8;
    var MAX_INTEGER = 2147483647;
    var MAX_SAFE_PROJECTION_NUMBER = 9007199254740991;
    var CONTROL_CHARACTERS = /[\u0000-\u001f\u007f-\u009f]/;
    var COOLDOWN_KEYS = [
        'ready', 'totalSteps', 'currentStep', 'progressPercent',
        'animationFrame', 'remainingMs'
    ];

    function integer(value, fallback) {
        return typeof value === 'number' && isFinite(value)
            && Math.floor(value) === value && value <= MAX_INTEGER
            ? value : fallback;
    }
    function ownKeys(value, expected) {
        if (!value || typeof value !== 'object'
                || Object.keys(value).length !== expected.length) return false;
        for (var i = 0; i < expected.length; i++) {
            if (!Object.prototype.hasOwnProperty.call(value, expected[i])) return false;
        }
        return true;
    }
    function boundedString(value, maximum) {
        return typeof value === 'string' && value.length <= maximum
            && !CONTROL_CHARACTERS.test(value);
    }
    function nonnegativeFinite(value) {
        return typeof value === 'number' && isFinite(value) && value >= 0
            && value <= MAX_SAFE_PROJECTION_NUMBER;
    }
    function validCooldown(value) {
        return ownKeys(value, COOLDOWN_KEYS)
            && typeof value.ready === 'boolean'
            && integer(value.totalSteps, -1) >= 0
            && integer(value.currentStep, -1) >= 0
            && value.currentStep <= value.totalSteps
            && integer(value.progressPercent, -1) >= 0
            && value.progressPercent <= 100
            && integer(value.animationFrame, -1) >= 0
            && nonnegativeFinite(value.remainingMs)
            && (value.ready !== true || value.remainingMs === 0);
    }
    function validLayout(layout) {
        return ownKeys(layout, [
                'v', 'bankCount', 'laneCount', 'physicalSlotCount',
                'activeBank', 'switchKeyLabel', 'switchCooldown'
            ])
            && layout.v === 2
            && layout.bankCount === BANK_COUNT
            && layout.laneCount === LANE_COUNT
            && layout.physicalSlotCount === PHYSICAL_SLOT_COUNT
            && integer(layout.activeBank, -1) >= 0
            && layout.activeBank < BANK_COUNT
            && boundedString(layout.switchKeyLabel, 64)
            && validCooldown(layout.switchCooldown);
    }
    function validRow(row, slot, activeBank, validItemIdentity) {
        var occupied = row && row.occupied === true;
        var expected = [
            'slot', 'bank', 'lane', 'active', 'keyLabel', 'ready',
            'totalSteps', 'currentStep', 'progressPercent', 'animationFrame',
            'remainingMs', 'occupied', 'quantity'
        ];
        if (occupied) expected.push('item');
        return ownKeys(row, expected)
            && row.slot === slot
            && row.bank === Math.floor(slot / LANE_COUNT)
            && row.lane === slot % LANE_COUNT
            && typeof row.active === 'boolean'
            && row.active === (row.bank === activeBank)
            && boundedString(row.keyLabel, 64)
            && validCooldown({
                ready:row.ready,
                totalSteps:row.totalSteps,
                currentStep:row.currentStep,
                progressPercent:row.progressPercent,
                animationFrame:row.animationFrame,
                remainingMs:row.remainingMs
            })
            && typeof row.occupied === 'boolean'
            && nonnegativeFinite(row.quantity)
            && (occupied
                ? validItemIdentity(row.item)
                    && row.item.itemKind === 'stack'
                    && row.item.use === '药剂'
                    && nonnegativeFinite(row.item.quantity)
                    && row.item.quantity > 0
                    && row.item.quantity === row.quantity
                : row.quantity === 0 && row.item == null);
    }
    function sameCooldown(left, right) {
        for (var i = 0; i < COOLDOWN_KEYS.length; i++) {
            if (left[COOLDOWN_KEYS[i]] !== right[COOLDOWN_KEYS[i]]) return false;
        }
        return true;
    }
    function validSnapshot(rows, layout, validItemIdentity) {
        if (!Array.isArray(rows) || rows.length !== PHYSICAL_SLOT_COUNT
                || !validLayout(layout)
                || typeof validItemIdentity !== 'function') return false;
        var slot;
        for (slot = 0; slot < PHYSICAL_SLOT_COUNT; slot++) {
            if (!validRow(rows[slot], slot, layout.activeBank, validItemIdentity)) {
                return false;
            }
        }
        for (slot = 0; slot < LANE_COUNT; slot++) {
            if (!sameCooldown(rows[slot], rows[slot + LANE_COUNT])) return false;
        }
        return true;
    }

    function projectRows(rows, projectItem) {
        rows = Array.isArray(rows) ? rows : [];
        var drugs = {};
        var meta = {};
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i] || {};
            var id = 'drug' + (Number(row.slot) + 1);
            drugs[id] = projectItem(row);
            meta[id] = {
                slot:Number(row.slot), bank:Number(row.bank), lane:Number(row.lane),
                active:row.active === true, keyLabel:String(row.keyLabel || ''),
                ready:row.ready === true, totalSteps:Number(row.totalSteps),
                currentStep:Number(row.currentStep),
                progressPercent:Number(row.progressPercent),
                animationFrame:Number(row.animationFrame),
                remainingMs:Number(row.remainingMs)
            };
        }
        return {drugs:drugs, drugMeta:meta};
    }
    function targetForSelection(selection) {
        if (!selection || selection.kind !== 'drug') return null;
        var match = /^drug([1-8])$/.exec(String(selection.id || ''));
        return match ? {kind:'drug', drugSlot:Number(match[1]) - 1} : null;
    }

    return {
        bankCount:BANK_COUNT,
        laneCount:LANE_COUNT,
        physicalSlotCount:PHYSICAL_SLOT_COUNT,
        validSnapshot:validSnapshot,
        projectRows:projectRows,
        targetForSelection:targetForSelection
    };
});
