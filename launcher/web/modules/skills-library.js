/** Pure skill-library projection, filtering and reorder rules. */
(function(root, factory) {
    'use strict';
    var itemFilter = typeof module !== 'undefined' && module.exports
        ? require('./item-filter.js') : root && root.ItemFilter;
    var api = factory(itemFilter);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.SkillsLibrary = api;
})(typeof window !== 'undefined' ? window : globalThis, function(ItemFilter) {
    'use strict';
    if (!ItemFilter) throw new Error('SkillsLibrary requires ItemFilter.');

    function emptyFilterPaths() { return {form:[], status:[], school:[]}; }

    function sourceEntries(snapshot, view) {
        if (!snapshot) return [];
        if (view === 'trainer') {
            return snapshot.trainer && Array.isArray(snapshot.trainer.entries)
                ? snapshot.trainer.entries : [];
        }
        return Array.isArray(snapshot.learned) ? snapshot.learned : [];
    }

    function entryByKey(snapshot, view, skillKey) {
        var entries = sourceEntries(snapshot, view);
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].skillKey === skillKey) return entries[i];
        }
        return null;
    }

    function visibleEntries(snapshot, view, query, paths) {
        var source = sourceEntries(snapshot, view);
        query = String(query || '').toLowerCase();
        return source.slice().filter(function(entry) {
            if (query && String(entry.skillKey || '').toLowerCase().indexOf(query) < 0
                    && String(entry.type || '').toLowerCase().indexOf(query) < 0) return false;
            return matches(entry, paths, view);
        }).sort(function(a, b) {
            var ai = a.orderIndex != null ? Number(a.orderIndex) : source.indexOf(a);
            var bi = b.orderIndex != null ? Number(b.orderIndex) : source.indexOf(b);
            return ai - bi;
        });
    }

    function facet(id, label, order) { return [{id:id, label:label, order:order}]; }

    function formPath(entry) {
        if (entry.passive && !entry.equippable) return facet('passive', '纯被动', 20);
        if (entry.passive && entry.equippable) return facet('hybrid', '主动 / 被动', 30);
        if (entry.equippable) return facet('equippable', '主动可装备', 10);
        return facet('unsupported', '不可配置', 90);
    }

    function statusPath(entry, view) {
        if (entry.writeBlocked || entry.stateHealth !== 'ok') return facet('blocked', '异常', 90);
        if (view === 'trainer') {
            var current = Number(entry.currentLevel || 0), max = Number(entry.maxLevel || 0);
            if (current <= 0) return facet('unlearned', '未学习', 10);
            if (max > 0 && current >= max) return facet('maxed', '已满级', 30);
            return facet('learned', '已学习', 20);
        }
        if (entry.passive && !entry.equippable) {
            return facet(entry.enabled ? 'passive_on' : 'passive_off',
                entry.enabled ? '被动启用' : '被动停用', entry.enabled ? 30 : 40);
        }
        return entry.equippedSlots && entry.equippedSlots.length
            ? facet('equipped', '已装备', 10) : facet('unequipped', '未装备', 20);
    }

    function schoolPath(entry) {
        var type = String(entry.type || '');
        var schools = [
            ['武术','武术',10],['剑术','剑术',20],['枪术','枪术',30],['内功','内功',40],['神功','神功',50],
            ['科技','科技',60],['超能力','超能力',70],['投技','投技',80],['龙吼','龙吼',90]
        ];
        var selected = null, selectedIndex = 9999;
        for (var i = 0; i < schools.length; i++) {
            var index = type.indexOf(schools[i][0]);
            if (index >= 0 && index < selectedIndex) {
                selected = schools[i];
                selectedIndex = index;
            }
        }
        return selected ? facet(selected[0], selected[1], selected[2]) : [];
    }

    function matches(entry, paths, view) {
        paths = paths && !Array.isArray(paths) ? paths : emptyFilterPaths();
        return ItemFilter.matchesPath(entry, paths.form, formPath)
            && ItemFilter.matchesPath(entry, paths.status, function(value) { return statusPath(value, view); })
            && ItemFilter.matchesPath(entry, paths.school, schoolPath);
    }

    function filterDefinitions(view) {
        return [
            {id:'form', label:'形态', classifier:formPath},
            {id:'status', label:view === 'trainer' ? '学习' : '配置',
                classifier:function(entry) { return statusPath(entry, view); }},
            {id:'school', label:'流派', classifier:schoolPath, collapsed:true}
        ];
    }

    function adjacent(entries, entry, delta) {
        entries = entries || [];
        var index = entries.indexOf(entry);
        return entries[index + Number(delta || 0)] || null;
    }

    function reorderBlockReason(entry, role, options) {
        options = options || {};
        if (options.writesDisabled === true) return 'skill_locked';
        if (entry && entry.equippedSlots && entry.equippedSlots.length
                && (role === 'target' || options.easyMode !== true)) return 'equipped_skill_locked';
        return '';
    }

    function safeNumber(value) {
        var number = Number(value);
        return isFinite(number) ? String(number) : '—';
    }

    function trainerState(entry, player) {
        if (!entry || typeof entry !== 'object') return {id:'blocked', label:'异常', compactLabel:'!'};
        if (entry.stateHealth === 'duplicate') return {id:'duplicate', label:'重复', compactLabel:'!'};
        if (entry.stateHealth !== 'ok' || entry.writeBlocked) return {id:'blocked', label:'异常', compactLabel:'!'};
        var current = Number(entry.currentLevel || 0);
        var max = Number(entry.maxLevel || 1);
        if (!isFinite(current) || current < 0) current = 0;
        if (!isFinite(max) || max < 1) max = 1;
        if (current >= max) return {id:'maxed', label:'已满级', compactLabel:'已满级'};
        var unlockLevel = Number(entry.unlockLevel != null ? entry.unlockLevel : 0);
        var hasLevel = !!(player && player.level != null && isFinite(Number(player.level)));
        var hasSP = !!(player && player.skillPoints != null && isFinite(Number(player.skillPoints)));
        var playerLevel = hasLevel ? Math.floor(Number(player.level)) : NaN;
        var skillPoints = hasSP ? Math.max(0, Math.floor(Number(player.skillPoints))) : NaN;
        if (current <= 0) {
            if (hasLevel && isFinite(unlockLevel) && playerLevel < unlockLevel) {
                var reqLabel = '需 Lv.' + safeNumber(unlockLevel);
                return {id:'level_locked', label:reqLabel, compactLabel:reqLabel};
            }
            var unlockSP = Number(entry.unlockSP != null ? entry.unlockSP : 0);
            if (hasSP && (!isFinite(unlockSP) || unlockSP < 0 || skillPoints < unlockSP)) {
                return {id:'insufficient_sp', label:'SP不足', compactLabel:'SP不足'};
            }
            if (hasLevel && hasSP) return {id:'learnable', label:'可学', compactLabel:'可学'};
            return {id:'unlearned', label:'未学', compactLabel:'未学'};
        }
        var upgradeSP = Number(entry.upgradeSP != null ? entry.upgradeSP : 0);
        var levelOk = !isFinite(unlockLevel) || (hasLevel && playerLevel >= unlockLevel);
        var spOk = hasSP && isFinite(upgradeSP) && upgradeSP >= 0 && (upgradeSP === 0 || skillPoints >= upgradeSP);
        if (levelOk && spOk) return {id:'upgradable', label:'可升级', compactLabel:'可升级'};
        return {id:'learned', label:'已学', compactLabel:'已学'};
    }

    function healthLabel(entry, view, player) {
        if (entry.stateHealth === 'duplicate') return '重复';
        if (entry.stateHealth !== 'ok' || entry.writeBlocked) return '异常';
        if (view === 'trainer') return trainerState(entry, player).label;
        if (entry.passive && !entry.equippable) return entry.enabled ? '被动 ON' : '被动 OFF';
        return entry.equippedSlots && entry.equippedSlots.length ? '槽 ' + entry.equippedSlots.join('/') : '可装备';
    }

    function compactStateLabel(entry, view, player) {
        if (entry.stateHealth !== 'ok' || entry.writeBlocked) return '!';
        if (view === 'trainer') return trainerState(entry, player).label;
        if (entry.passive && !entry.equippable) return entry.enabled ? 'ON' : 'OFF';
        return entry.equippedSlots && entry.equippedSlots.length ? entry.equippedSlots.join('/') : '';
    }

    function ariaLabel(entry, view, player) {
        var level = entry.currentLevel != null ? entry.currentLevel : entry.level;
        return String(entry.skillKey || '未知技能') + '，等级 ' + safeNumber(level) + '/'
            + safeNumber(entry.maxLevel) + '，' + healthLabel(entry, view, player) + '；悬停查看技能说明';
    }

    return {
        emptyFilterPaths:emptyFilterPaths,
        sourceEntries:sourceEntries,
        entryByKey:entryByKey,
        visibleEntries:visibleEntries,
        formPath:formPath,
        statusPath:statusPath,
        schoolPath:schoolPath,
        matches:matches,
        filterDefinitions:filterDefinitions,
        adjacent:adjacent,
        reorderBlockReason:reorderBlockReason,
        trainerState:trainerState,
        healthLabel:healthLabel,
        compactStateLabel:compactStateLabel,
        ariaLabel:ariaLabel
    };
});
