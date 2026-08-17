/**
 * Pure character-build candidate drop-target resolution.
 *
 * `candidate.blocked` only describes the relationship with the currently
 * selected slot; backpack rows carry the authoritative per-item slot
 * allowlist in `raw.equipmentEligibility`. This leaf derives the accepted
 * drop slots from that allowlist without touching the DOM or transport.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildDropTargets = api;
        root.CharacterBuildDropTargets = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function noTarget(reason) {
        return {slots:[], reason:String(reason || 'no_target')};
    }

    function pinned(selectedSlotKey, candidate) {
        return candidate.blocked === true
            ? noTarget('item_blocked')
            : {slots:[String(selectedSlotKey)], reason:''};
    }

    /* 与 Host `CharacterBuildProtocol.IsSlotCompatible` 的药剂判别完全一致；
     * 药剂冷却是逐槽状态，未选中槽位没有投影，统一交给 Host 在写入时裁决。 */
    function isDrugRow(candidate) {
        var item = candidate && candidate.raw && candidate.raw.item || {};
        return item.itemKind === 'stack' && item.use === '药剂'
            && Number(item.quantity) > 0;
    }

    /**
     * scope: 'compatible' | 'backpack'.
     * slots: [{rovingKey, kind, id}] for every loadout slot node.
     * Returns {slots:[rovingKey...], reason:''|'item_blocked'|'no_target'}.
     */
    function resolve(scope, selectedSlotKey, candidate, slots) {
        if (!candidate) return noTarget('no_target');
        if (scope !== 'backpack') {
            return selectedSlotKey
                ? pinned(selectedSlotKey, candidate) : noTarget('no_target');
        }
        var eligibility = candidate.raw && candidate.raw.equipmentEligibility;
        if (eligibility && Array.isArray(eligibility.slots)
                && eligibility.slots.length) {
            if (String(eligibility.blockedReason || '') !== '') {
                return noTarget('item_blocked');
            }
            var accepted = [];
            for (var i = 0; i < slots.length; i++) {
                var slot = slots[i] || {};
                if (slot.kind !== 'armor' && slot.kind !== 'weapon') continue;
                if (eligibility.slots.indexOf(slot.id) < 0) continue;
                accepted.push(String(slot.rovingKey));
            }
            return accepted.length ? {slots:accepted, reason:''} : noTarget('no_target');
        }
        if (isDrugRow(candidate)) {
            var drugSlots = [];
            for (var j = 0; j < slots.length; j++) {
                if (slots[j] && slots[j].kind === 'drug') {
                    drugSlots.push(String(slots[j].rovingKey));
                }
            }
            return drugSlots.length ? {slots:drugSlots, reason:''} : noTarget('no_target');
        }
        // 其余非装备行（材料等）没有合法构筑落点，只提供查看说明。
        return noTarget(candidate.blocked === true ? 'item_blocked' : 'no_target');
    }

    /**
     * state: {interactionState, snapshotBlocked}; hit: {slotKey, node}.
     * targets comes from resolve(). Returns the accepted intent or a
     * {accepted:false, reason} rejection the view can surface verbatim.
     */
    function decide(state, hit, candidate, targets) {
        state = state || {};
        if (state.interactionState !== 'idle') {
            return {accepted:false, reason:'write_locked'};
        }
        if (state.snapshotBlocked) return {accepted:false, reason:'build_blocked'};
        if (!hit || !hit.slotKey) return {accepted:false, reason:'target_mismatch'};
        var node = hit.node;
        if (!node || node.disabled || node.getAttribute('data-blocked') === 'true') {
            return {accepted:false, reason:'target_blocked'};
        }
        targets = targets || {slots:[], reason:'no_target'};
        if (targets.slots.indexOf(hit.slotKey) < 0) {
            return {accepted:false, reason:targets.reason === 'item_blocked'
                ? 'item_blocked' : 'target_mismatch'};
        }
        return {accepted:true, operationId:'character-build.equip-candidate',
            targetRef:{slotKey:String(hit.slotKey)}};
    }

    function rejectCopy(reason) {
        if (reason === 'write_locked') return '构筑正在处理写入，当前拖拽已取消。';
        if (reason === 'target_blocked' || reason === 'build_blocked') {
            return '当前目标不可装备此候选，现有装备保持不变。';
        }
        if (reason === 'item_blocked') {
            return '该物品当前不可装备（如等级不足），现有装备保持不变。';
        }
        return '该物品与这个槽位不兼容；请拖到高亮的兼容槽位。';
    }

    return {resolve:resolve, decide:decide, rejectCopy:rejectCopy, isDrugRow:isDrugRow};
});
