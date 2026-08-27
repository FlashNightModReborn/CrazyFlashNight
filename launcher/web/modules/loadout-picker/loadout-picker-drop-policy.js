/**
 * Loadout picker drop policy: pure candidate drop-target resolution.
 *
 * `candidate.blocked` only describes the relationship with the currently
 * selected slot. Both browse scopes may carry an authoritative per-item slot
 * allowlist via the injected eligibility provider. This leaf derives accepted
 * drop slots from that allowlist without touching the DOM or transport.
 *
 * The kind vocabulary, drug-row detection, eligibility source, operation id
 * and reject copy are ports; the defaults preserve the character-build
 * vocabulary (`armor`/`weapon`/`drug`, `equipmentEligibility.slots`,
 * `character-build.equip-candidate`) verbatim.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.LoadoutPickerDropPolicy = api;
        root.LoadoutPickerDropPolicy = api;
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
     * 两组同 lane 槽位共享冷却，目标节点的 data-blocked 由严格投影给出。 */
    function defaultIsDrugRow(candidate) {
        var item = candidate && candidate.raw && candidate.raw.item || {};
        return item.itemKind === 'stack' && item.use === '药剂'
            && Number(item.quantity) > 0;
    }

    var DEFAULT_TEXTS = {
        write_locked:'构筑正在处理写入，当前拖拽已取消。',
        target_blocked:'当前目标不可装备此候选，现有装备保持不变。',
        item_blocked:'该物品当前不可装备（如等级不足），现有装备保持不变。',
        target_mismatch:'该物品与这个槽位不兼容；请拖到高亮的兼容槽位。'
    };

    function defaultEligibilityProvider(candidate) {
        return candidate && candidate.raw && candidate.raw.equipmentEligibility;
    }

    function create(options) {
        options = options || {};
        var equipmentKinds = Array.isArray(options.equipmentKinds)
                && options.equipmentKinds.length
            ? options.equipmentKinds.slice() : ['armor', 'weapon'];
        var drugKind = typeof options.drugKind === 'string' && options.drugKind !== ''
            ? options.drugKind : 'drug';
        var isDrugRow = typeof options.isDrugRow === 'function'
            ? options.isDrugRow : defaultIsDrugRow;
        var eligibilityProvider = typeof options.eligibilityProvider === 'function'
            ? options.eligibilityProvider : defaultEligibilityProvider;
        var operationId = typeof options.operationId === 'string'
                && options.operationId !== ''
            ? options.operationId : 'character-build.equip-candidate';
        var texts = {};
        for (var key in DEFAULT_TEXTS) {
            if (!Object.prototype.hasOwnProperty.call(DEFAULT_TEXTS, key)) continue;
            texts[key] = options.texts && typeof options.texts[key] === 'string'
                && options.texts[key] !== '' ? options.texts[key] : DEFAULT_TEXTS[key];
        }

        /**
         * scope: 'compatible' | 'backpack'.
         * slots: [{rovingKey, kind, id}] for every loadout slot node.
         * Returns {slots:[rovingKey...], reason:''|'item_blocked'|'no_target'}.
         */
        function resolve(scope, selectedSlotKey, candidate, slots) {
            if (!candidate) return noTarget('no_target');
            var eligibility = eligibilityProvider(candidate);
            if (eligibility && Array.isArray(eligibility.slots)
                    && eligibility.slots.length) {
                if (String(eligibility.blockedReason || '') !== '') {
                    return noTarget('item_blocked');
                }
                var accepted = [];
                for (var i = 0; i < slots.length; i++) {
                    var slot = slots[i] || {};
                    if (equipmentKinds.indexOf(slot.kind) < 0) continue;
                    if (eligibility.slots.indexOf(slot.id) < 0) continue;
                    accepted.push(String(slot.rovingKey));
                }
                return accepted.length ? {slots:accepted, reason:''} : noTarget('no_target');
            }
            if (isDrugRow(candidate)) {
                var drugSlots = [];
                for (var j = 0; j < slots.length; j++) {
                    if (slots[j] && slots[j].kind === drugKind) {
                        drugSlots.push(String(slots[j].rovingKey));
                    }
                }
                return drugSlots.length ? {slots:drugSlots, reason:''} : noTarget('no_target');
            }
            if (eligibility && Array.isArray(eligibility.slots)) {
                return noTarget(candidate.blocked === true
                    ? 'item_blocked' : 'no_target');
            }
            // 未迁移的兼容作用域消费方仍退回当前槽；背包总览没有可猜测落点。
            if (scope !== 'backpack') {
                return selectedSlotKey
                    ? pinned(selectedSlotKey, candidate) : noTarget('no_target');
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
            return {accepted:true, operationId:operationId,
                targetRef:{slotKey:String(hit.slotKey)}};
        }

        function rejectCopy(reason) {
            if (reason === 'write_locked') return texts.write_locked;
            if (reason === 'target_blocked' || reason === 'build_blocked') {
                return texts.target_blocked;
            }
            if (reason === 'item_blocked') {
                return texts.item_blocked;
            }
            return texts.target_mismatch;
        }

        return {
            resolve:resolve,
            decide:decide,
            rejectCopy:rejectCopy,
            isDrugRow:isDrugRow,
            operationId:operationId
        };
    }

    var defaultPolicy = create();

    return {
        create:create,
        resolve:defaultPolicy.resolve,
        decide:defaultPolicy.decide,
        rejectCopy:defaultPolicy.rejectCopy,
        isDrugRow:defaultIsDrugRow,
        operationId:defaultPolicy.operationId
    };
});
