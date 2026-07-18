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
            direct:options.mode === 'fast' || !replacingSkill,
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
            direct:options.mode === 'fast',
            payload:{slot:Number(slot.slot), expectedRevision:Number(options.revision)}
        };
    }

    function readConfirmationMode(storage, key) {
        try {
            return storage && storage.getItem(key) === 'fast' ? 'fast' : 'safe';
        } catch (error) {
            return 'safe';
        }
    }

    function writeConfirmationMode(storage, key, mode) {
        mode = mode === 'fast' ? 'fast' : 'safe';
        try {
            if (storage) storage.setItem(key, mode);
        } catch (error) {}
        return mode;
    }

    function helpDetail(mode, canReturnTrainer) {
        mode = mode === 'fast' ? 'fast' : 'safe';
        var label = mode === 'fast' ? '快速' : '安全';
        var behavior = mode === 'fast'
            ? '装备、替换和卸载直接执行。技能学习仍须确认。'
            : '空槽直接装备；替换和卸载需要确认。';
        return '管理技能\n• 装备到已有槽位会替换原技能；是否确认由顶栏“快捷栏”的安全/快速选项决定。\n• 快捷槽可互相拖动：拖到空槽会移动，拖到已有技能会直接交换。\n• 聚焦快捷槽后按 Alt + ← / → 可与相邻槽交换。\n• 纯被动技能可以启用或停用。\n• 聚焦技能后按 Alt + ↑ / ↓ 也可交换相邻顺序。'
            + '\n\n查找与布局\n• 形态、配置和流派都可直接筛选，也可以组合使用。\n• 按 / 可以展开名称搜索。\n• 完整/紧凑只改变技能库；下方 12 格快捷技能保持固定。'
            + '\n\n快捷栏操作确认\n• 顶栏始终显示当前模式，可随时在“安全 / 快速”之间切换。\n• 当前：'
            + label + '模式。' + behavior
            + '\n• 快捷槽之间的移动或交换无需确认；技能学习始终需要确认。'
            + (canReturnTrainer === true ? '\n• “返回研习”只在本次教师入口中可用。' : '');
    }

    return {
        slotByNumber:slotByNumber,
        moveBlockReason:moveBlockReason,
        equipPlan:equipPlan,
        unequipPlan:unequipPlan,
        readConfirmationMode:readConfirmationMode,
        writeConfirmationMode:writeConfirmationMode,
        helpDetail:helpDetail
    };
});
