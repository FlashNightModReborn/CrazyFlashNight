/** Pure candidate eligibility copy and universal-backpack reprojection. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildCandidateEligibility = api;
        root.CharacterBuildCandidateEligibility = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function blockedCopy(reason, overview) {
        reason = String(reason || '');
        if (reason === 'incompatible_item') {
            if (overview === true) {
                return '此物品不能用于角色构筑；可查看说明，但没有可装入栏位。';
            }
            return '与当前槽位不兼容；可查看说明，但不能装备。';
        }
        if (reason === 'level_locked') {
            return '角色等级不足；可查看说明，但当前不能装备。';
        }
        if (reason === 'cooldown_active') {
            return '该药剂槽仍在冷却；可查看说明，但当前不能装入。';
        }
        if (reason === 'cooldown_unavailable') {
            return '暂时无法确认药剂冷却状态；可查看说明，但当前不能装入。';
        }
        return reason || '此候选当前不可装备；仍可查看说明。';
    }

    function rowForTarget(row, payload, target) {
        var eligibility = row && row.equipmentEligibility;
        if (!payload || payload.candidateScope !== 'backpack'
                || !target || target.kind !== 'equipment'
                || !eligibility || !Array.isArray(eligibility.slots)) return row;
        var allowed = eligibility.slots.indexOf(String(target.slotKey || '')) >= 0;
        var blockedReason = allowed
            ? String(eligibility.blockedReason || '') : 'incompatible_item';
        var projected = {};
        for (var key in row) {
            if (Object.prototype.hasOwnProperty.call(row, key)) projected[key] = row[key];
        }
        projected.disabled = blockedReason !== '';
        projected.blockedReason = blockedReason;
        return projected;
    }

    return {blockedCopy:blockedCopy, rowForTarget:rowForTarget};
});
