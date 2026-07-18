/** Pure drag/drop offers and acceptance decisions for the skills workbench. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.SkillsInteractions = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function skillOffer(entry, writesDisabled) {
        return entry && writesDisabled !== true
            ? {subjectKind:'skill', sourceRef:{skillKey:entry.skillKey, equippable:entry.equippable === true}}
            : null;
    }

    function quickSlotOffer(slot) {
        return slot && slot.skillKey && slot.stateHealth === 'ok' && !slot.writeBlocked
            ? {subjectKind:'quick_slot', sourceRef:{slot:Number(slot.slot), skillKey:String(slot.skillKey)}}
            : null;
    }

    function probeEquip(offer, slot, writeBlocked) {
        if (!offer || offer.subjectKind !== 'skill') return {accepted:false, reason:'invalid_skill'};
        if (!offer.sourceRef || offer.sourceRef.equippable !== true) {
            return {accepted:false, reason:'skill_not_equippable'};
        }
        if (!slot || slot.writeBlocked || writeBlocked === true) return {accepted:false, reason:'slot_locked'};
        return {accepted:true, operationId:'equip_skill', targetRef:{slot:Number(slot.slot)}};
    }

    function probeMove(offer, target, lookupSlot, writeBlocked) {
        var source = offer && offer.sourceRef && typeof lookupSlot === 'function'
            ? lookupSlot(Number(offer.sourceRef.slot)) : null;
        if (!offer || offer.subjectKind !== 'quick_slot' || !source || !source.skillKey) {
            return {accepted:false, reason:'invalid_skill'};
        }
        if (!target || source.slot === target.slot || source.writeBlocked || target.writeBlocked
                || source.stateHealth !== 'ok' || (target.skillKey && target.stateHealth !== 'ok')
                || writeBlocked === true) return {accepted:false, reason:'slot_locked'};
        return {accepted:true, operationId:'move_quick_slot',
            targetRef:{sourceSlot:Number(source.slot), targetSlot:Number(target.slot)}};
    }

    function probeReorder(offer, target, lookupEntry, blockReason) {
        var source = offer && offer.sourceRef && typeof lookupEntry === 'function'
            ? lookupEntry(offer.sourceRef.skillKey) : null;
        if (!source || !target || source.skillKey === target.skillKey) {
            return {accepted:false, reason:'invalid_skill'};
        }
        var reason = typeof blockReason === 'function'
            ? blockReason(source, 'source') || blockReason(target, 'target') : '';
        if (reason) return {accepted:false, reason:reason};
        return {accepted:true, operationId:'reorder_skill',
            targetRef:{skillKey:target.skillKey, targetIndex:Number(target.orderIndex)}};
    }

    function rejectMessage(reason) {
        if (reason === 'slot_locked') return '该快捷槽当前不可写。';
        if (reason === 'skill_not_equippable') return '该技能不能装备到快捷栏。';
        if (reason === 'equipped_skill_locked') return '已装备技能需先卸载，才能交换列表顺序。';
        return '该技能当前无法调整顺序。';
    }

    return {
        skillOffer:skillOffer,
        quickSlotOffer:quickSlotOffer,
        probeEquip:probeEquip,
        probeMove:probeMove,
        probeReorder:probeReorder,
        rejectMessage:rejectMessage
    };
});
