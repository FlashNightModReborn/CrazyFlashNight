/** Pure Character Build request/response contract validation. */
(function(root, factory) {
    'use strict';
    var mutation = typeof module !== 'undefined' && module.exports
        ? require('./character-build-mutation.js')
        : root && root.CharacterBuildMutation;
    var api = factory(mutation);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildSessionContract = api;
        root.CharacterBuildSessionContract = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function(Mutation) {
    'use strict';
    if (!Mutation) throw new Error('CharacterBuildSessionContract requires CharacterBuildMutation');

    var COMMANDS = ['snapshot', 'candidates', 'tooltip', 'flushLive', 'statsSnapshot', 'finalize']
        .concat(Mutation.commands);
    var EQUIPMENT_SLOTS = [
        '头部装备', '上装装备', '下装装备', '手部装备', '脚部装备', '颈部装备',
        '长枪', '手枪', '手枪2', '刀', '手雷'
    ];
    function noop() {}
    function integer(value, fallback) {
        value = Number(value);
        return isFinite(value) && Math.floor(value) === value ? value : fallback;
    }
    function positive(value) {
        value = integer(value, -1);
        return value > 0 ? value : null;
    }
    function token(value) {
        value = String(value || '');
        return /^[A-Za-z0-9._~-]{1,128}$/.test(value) ? value : '';
    }
    function copy(value) {
        var result = {};
        value = value && typeof value === 'object' ? value : {};
        for (var key in value) {
            if (Object.prototype.hasOwnProperty.call(value, key)) result[key] = value[key];
        }
        return result;
    }
    function ownKeys(value, expected) {
        if (!value || typeof value !== 'object'
                || Object.keys(value).length !== expected.length) return false;
        for (var i = 0; i < expected.length; i++) {
            if (!Object.prototype.hasOwnProperty.call(value, expected[i])) return false;
        }
        return true;
    }
    function boundedString(value, maximum, allowEmpty) {
        return typeof value === 'string' && value.length <= maximum
            && (allowEmpty === true || value.length > 0);
    }
    function targetKey(target) {
        if (!target || typeof target !== 'object') return '';
        if (target.kind === 'equipment' && typeof target.slotKey === 'string' && target.slotKey) {
            return 'equipment:' + target.slotKey;
        }
        if (target.kind === 'backpack' && ownKeys(target, ['kind'])) return 'backpack';
        var slot = integer(target.drugSlot, -1);
        return target.kind === 'drug' && slot >= 0 && slot < 4 ? 'drug:' + slot : '';
    }
    function sameTarget(left, right) {
        return targetKey(left) !== '' && targetKey(left) === targetKey(right);
    }
    function candidateScope(value) {
        value = String(value || '');
        return value === 'compatible' || value === 'backpack' ? value : '';
    }
    function validLoadoutItems(rows) {
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i];
            if (!row || typeof row !== 'object') return false;
            if (row.occupied === true && !Mutation.validItemIdentity(row.item)) return false;
            if (row.item != null && !Mutation.validItemIdentity(row.item)) return false;
        }
        return true;
    }
    function validProjection(payload) {
        return !!payload && typeof payload === 'object'
            && Array.isArray(payload.equipment) && payload.equipment.length === 11
            && Array.isArray(payload.drugs) && payload.drugs.length === 4
            && validLoadoutItems(payload.equipment)
            && validLoadoutItems(payload.drugs)
            && payload.portrait && typeof payload.portrait === 'object'
            && typeof payload.stateHealth === 'string'
            && Array.isArray(payload.diagnostics);
    }
    function validCandidates(payload, target, scope) {
        scope = candidateScope(scope);
        var expectedTargetKeys = target && target.kind === 'equipment'
            ? ['kind', 'slotKey'] : target && target.kind === 'drug'
                ? ['kind', 'drugSlot'] : ['kind'];
        if (!payload || typeof payload !== 'object'
                || !sameTarget(payload.target, target)
                || !ownKeys(payload.target, expectedTargetKeys)
                || !scope || payload.candidateScope !== scope
                || !Array.isArray(payload.candidates)
                || integer(payload.backpackVersion, -1) < 0
                || typeof payload.stateHealth !== 'string'
                || !Array.isArray(payload.diagnostics)) return false;
        for (var i = 0; i < payload.candidates.length; i++) {
            var row = payload.candidates[i];
            if (!row || typeof row !== 'object'
                    || !Mutation.validItemIdentity(row.item)) return false;
            var equipmentEligibilityRequired = target && (target.kind === 'equipment'
                || (scope === 'backpack' && target.kind === 'backpack'));
            var hasEligibility = Object.prototype.hasOwnProperty.call(
                row, 'equipmentEligibility');
            if (hasEligibility !== equipmentEligibilityRequired) return false;
            if (equipmentEligibilityRequired) {
                var eligibility = row.equipmentEligibility;
                if (!ownKeys(eligibility, ['slots', 'blockedReason'])
                        || !Array.isArray(eligibility.slots)
                        || eligibility.slots.length > EQUIPMENT_SLOTS.length
                        || (eligibility.blockedReason !== ''
                            && eligibility.blockedReason !== 'level_locked')) return false;
                var previousSlotIndex = -1;
                for (var slotIndex = 0;
                        slotIndex < eligibility.slots.length;
                        slotIndex++) {
                    var canonicalIndex = EQUIPMENT_SLOTS.indexOf(
                        eligibility.slots[slotIndex]);
                    if (canonicalIndex <= previousSlotIndex) return false;
                    previousSlotIndex = canonicalIndex;
                }
            }
        }
        return true;
    }
    function validTooltip(payload, target) {
        if (!ownKeys(payload, [
                'v', 'target', 'itemName', 'displayName', 'iconName', 'itemType',
                'descHTML', 'introHTML'
            ]) || payload.v !== 1 || !sameTarget(payload.target, target)) return false;
        var expectedTargetKeys = target && target.kind === 'equipment'
            ? ['kind', 'slotKey'] : ['kind', 'drugSlot'];
        return ownKeys(payload.target, expectedTargetKeys)
            && boundedString(payload.itemName, 256, false)
            && boundedString(payload.displayName, 256, false)
            && boundedString(payload.iconName, 256, false)
            && boundedString(payload.itemType, 128, true)
            && boundedString(payload.descHTML, 131072, true)
            && boundedString(payload.introHTML, 131072, true)
            && (payload.descHTML.length > 0 || payload.introHTML.length > 0);
    }
    function validStats(payload) {
        return !!payload && typeof payload === 'object' && payload.v === 1
            && typeof payload.stateHealth === 'string'
            && Array.isArray(payload.diagnostics) && Array.isArray(payload.groups);
    }
    function definitiveOpenFailure(response) {
        if (!response) return false;
        if (response.clientSynthetic === true) return response.error === 'not_sent';
        if (response.requiresReconcile === true || response.active !== false
                || positive(response.sessionGeneration) !== null) return false;
        return /^(service_not_ready|invalid_payload|unsupported_cmd|panel_instance_expired|stale_session|not_allowed|source_not_allowed)$/
            .test(String(response.error || ''));
    }

    return {
        commands:COMMANDS.slice(), noop:noop, integer:integer, positive:positive,
        token:token, copy:copy, targetKey:targetKey, candidateScope:candidateScope,
        definitiveOpenFailure:definitiveOpenFailure,
        validators:{projection:validProjection, candidates:validCandidates,
            tooltip:validTooltip, stats:validStats}
    };
});
