/** Pure quick-loadout lookup, write planning and confirmation preference rules. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.SkillsLoadout = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function slotByNumber(snapshot, number) {
        var slots = snapshot && snapshot.loadout || [];
        for (var i = 0; i < slots.length; i++) {
            if (Number(slots[i].slot) === Number(number)) return slots[i];
        }
        return null;
    }

    function moveBlockReason(source, target, writeBlocked) {
        if (!source || !target || Number(source.slot) === Number(target.slot) || !source.skillKey) return 'invalid_skill';
        if (source.stateHealth !== 'ok' || source.writeBlocked || target.writeBlocked
                || (target.skillKey && target.stateHealth !== 'ok') || writeBlocked === true) return 'slot_locked';
        return '';
    }

    function equipPlan(entry, slot, options) {
        options = options || {};
        if (!entry || options.writesDisabled === true || !slot || slot.writeBlocked) {
            return {allowed:false, reason:'slot_locked'};
        }
        var replacingSkill = !!(slot.skillKey && slot.skillKey !== entry.skillKey);
        return {
            allowed:true,
            direct:true,
            replacingSkill:replacingSkill,
            payload:{skillKey:entry.skillKey, slot:Number(slot.slot), expectedRevision:Number(options.revision)}
        };
    }

    function unequipPlan(slot, options) {
        options = options || {};
        if (!slot || !slot.skillKey || slot.writeBlocked || options.writeBlocked === true) {
            return {allowed:false, reason:'slot_locked'};
        }
        return {
            allowed:true,
            direct:true,
            payload:{slot:Number(slot.slot), expectedRevision:Number(options.revision)}
        };
    }

    function helpDetail(canReturnTrainer) {
        if (arguments.length >= 2) canReturnTrainer = arguments[1];
        return '管理技能\n• 选中技能后点击快捷槽直接装备或替换；双击技能格可直接装入首个空槽。\n• 快捷槽可互相拖动：拖到空槽会移动，拖到已有技能会直接交换。\n• 右键快捷槽、点击右上角 × 或将快捷槽拖回技能库均可直接卸载。\n• 聚焦快捷槽后按 Alt + ← / → 可与相邻槽交换。\n• 纯被动技能可以启用或停用；聚焦技能后按 Alt + ↑ / ↓ 可交换列表顺序。'
            + '\n\n查找与布局\n• 形态、配置和流派都可直接筛选，也可以组合使用。\n• 按 / 可以展开名称搜索。\n• 完整/紧凑只改变技能库；下方 12 格快捷技能保持固定。'
            + (canReturnTrainer === true ? '\n• “返回研习”只在本次教师入口中可用。' : '');
    }

    return {
        slotByNumber:slotByNumber,
        moveBlockReason:moveBlockReason,
        equipPlan:equipPlan,
        unequipPlan:unequipPlan,
        helpDetail:helpDetail
    };
});
