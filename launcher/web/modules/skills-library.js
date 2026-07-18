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

    function healthLabel(entry, view) {
        if (entry.stateHealth === 'duplicate') return '重复';
        if (entry.stateHealth !== 'ok' || entry.writeBlocked) return '异常';
        if (view === 'trainer') return Number(entry.currentLevel || 0) > 0 ? '已学' : '可学';
        if (entry.passive && !entry.equippable) return entry.enabled ? '被动 ON' : '被动 OFF';
        return entry.equippedSlots && entry.equippedSlots.length ? '槽 ' + entry.equippedSlots.join('/') : '可装备';
    }

    function compactStateLabel(entry, view) {
        if (entry.stateHealth !== 'ok' || entry.writeBlocked) return '!';
        if (view === 'trainer') return Number(entry.currentLevel || 0) > 0 ? '已学' : '可学';
        if (entry.passive && !entry.equippable) return entry.enabled ? 'ON' : 'OFF';
        return entry.equippedSlots && entry.equippedSlots.length ? entry.equippedSlots.join('/') : '';
    }

    function ariaLabel(entry, view) {
        var level = entry.currentLevel != null ? entry.currentLevel : entry.level;
        return String(entry.skillKey || '未知技能') + '，等级 ' + safeNumber(level) + '/'
            + safeNumber(entry.maxLevel) + '，' + healthLabel(entry, view) + '；悬停查看技能说明';
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
        healthLabel:healthLabel,
        compactStateLabel:compactStateLabel,
        ariaLabel:ariaLabel
    };
});
