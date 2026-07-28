/** Interaction offers, acceptance decisions and navigation policies for the skills workbench. */
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

    function canReturnCharacterBuild(view, initData) {
        return view === 'manage' && initData
            && initData.canReturnCharacterBuild === true
            && initData.canReturnTrainer !== true;
    }

    function requestCharacterBuild(context) {
        context = context || {};
        var view = context.view;
        var initData = context.initData;
        var switchPending = context.switchPending;
        var state = context.state;
        var panelInstanceId = context.panelInstanceId;
        var send = context.send;
        if (!canReturnCharacterBuild(view, initData) || switchPending || state !== 'idle') return false;
        panelInstanceId = String(panelInstanceId || initData.panelInstanceId || '');
        if (!panelInstanceId || typeof send !== 'function') return false;
        var sent = send({type:'panel', panel:'skills', cmd:'close',
            panelInstanceId:panelInstanceId, reason:'navigate_character_build'});
        if (sent === false) {
            if (typeof context.onUnavailable === 'function') {
                context.onUnavailable('启动器连接不可用，暂时无法返回角色构筑。');
            }
            return false;
        }
        if (typeof context.onSent === 'function') context.onSent({
            buttonText:'返回中…',
            timeoutMessage:'返回角色构筑未完成，请重试。',
            statusText:'正在返回角色构筑'
        });
        return true;
    }

    function requestSkillView(context) {
        context = context || {};
        var trainer = context.target === 'trainer';
        if ((context.target !== 'manage' && !trainer) || !context.initData
                || (trainer
                    ? context.view !== 'manage' || context.initData.canReturnTrainer !== true
                    : context.view !== 'trainer' || context.trainerExpired)
                || context.state !== 'idle' || typeof context.send !== 'function') return false;
        var panelInstanceId = String(context.panelInstanceId
            || context.initData.panelInstanceId || '');
        if (!panelInstanceId) return false;
        var sent = context.send({
            type:'panel', panel:'skills',
            cmd:trainer ? 'switch_trainer' : 'switch_manage',
            panelInstanceId:panelInstanceId,
            payload:{v:1, focusSkillKey:String(context.focusSkillKey || '')}
        });
        if (sent === false) {
            if (typeof context.onUnavailable === 'function') {
                context.onUnavailable('启动器连接不可用，暂时无法切换页面。');
            }
            return false;
        }
        if (typeof context.onSent === 'function') context.onSent({
            buttonText:trainer ? '返回中…' : '切换中…',
            timeoutMessage:trainer
                ? '返回研习未完成；若教师入口已失效，请重新与教师对话。'
                : '切换到技能管理未完成，请重试。',
            statusText:trainer ? '正在返回技能研习' : '正在切换到技能管理'
        });
        return true;
    }

    function requestNavigation(context) {
        return context && context.target === 'character_build'
            ? requestCharacterBuild(context)
            : requestSkillView(context);
    }

    function popFilterPath(paths, definitions, navigators, activeElement) {
        paths = paths || {};
        var group = activeElement && activeElement.closest
            ? activeElement.closest('.skills-filter-group[data-skill-filter]') : null;
        var id = group ? group.getAttribute('data-skill-filter') : '';
        definitions = definitions || [];
        if (!id || !paths[id] || !paths[id].length) {
            for (var i = definitions.length - 1; i >= 0; i--) {
                if (paths[definitions[i].id] && paths[definitions[i].id].length) {
                    id = definitions[i].id;
                    break;
                }
            }
        }
        var navigator = id && navigators && navigators[id];
        if (!navigator || !navigator.setPath || !paths[id] || !paths[id].length) return false;
        navigator.setPath(paths[id].slice(0, -1), false);
        var focusTarget = navigator.root && navigator.root.querySelector('button:not([disabled])');
        if (focusTarget) focusTarget.focus();
        return true;
    }

    function consumeClose(context) {
        context = context || {};
        var reason = context.reason;
        var shell = context.shell;
        if (shell && shell.hasModal()) {
            shell.closeModal(reason);
            return true;
        }
        if (reason !== 'escape') return false;
        if (context.searchExpanded) {
            if (typeof context.collapseSearch === 'function') context.collapseSearch(false);
            if (context.searchToggle) context.searchToggle.focus();
            return true;
        }
        return popFilterPath(context.paths, context.definitions, context.navigators,
            context.activeElement);
    }

    return {
        skillOffer:skillOffer,
        quickSlotOffer:quickSlotOffer,
        probeEquip:probeEquip,
        probeMove:probeMove,
        probeReorder:probeReorder,
        rejectMessage:rejectMessage,
        canReturnCharacterBuild:canReturnCharacterBuild,
        requestCharacterBuild:requestCharacterBuild,
        requestSkillView:requestSkillView,
        requestNavigation:requestNavigation,
        consumeClose:consumeClose
    };
});
