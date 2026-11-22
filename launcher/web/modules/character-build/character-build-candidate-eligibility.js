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

    var MUTATION_ERRORS = {
        backpack_full:'背包已满（50/50），无法卸下装备；请先通过「整备 → 战备箱」或收纳整理空位。',
        level_locked:'角色等级不足，无法装备该物品。',
        cooldown_active:'该药剂槽仍在冷却中，暂时无法更换或卸下。',
        cooldown_unavailable:'暂时无法确认药剂冷却状态，请稍后重试。',
        incompatible_item:'该物品与目标栏位不兼容，无法执行操作。',
        stale_state:'背包或装备状态已变化，请重新选择后再试。',
        stale_container:'背包内容已变化，请重新选择后再试。',
        stale_drug_revision:'药剂栏状态已变化，请重新选择后再试。',
        stale_session:'角色构筑会话已更新，请重试。',
        stale_panel_instance:'面板会话已失效，请重新打开角色构筑。',
        write_busy:'背包或构筑正在处理另一项操作，请稍候再试。',
        invalid_slot:'目标槽位状态已变化，无法完成操作。',
        invalid_loadout:'当前装备数据异常，操作已取消。',
        service_not_ready:'角色数据尚未就绪，请稍后重试。',
        live_unavailable:'角色状态尚未就绪，请稍后重试。',
        write_failed:'装备写入未完成，原装备保持不变，请重试。',
        not_sent:'角色构筑连接不可用。'
    };
    var ITEM_USE_ERRORS = {
        not_committed:'刚才的使用未执行，可重新点击。',
        invalid_source:'物品来源已变化，请刷新后重试。',
        no_eligible_choices:'请先保留一件可安装候选插件的装备，再开启这个箱子。箱子尚未消耗。',
        no_available_lane:'四条药剂通道当前均不可用，暂时无法服用。',
        cooldown_active:'药剂通道仍在冷却中，暂时无法服用。',
        cooldown_unavailable:'暂时无法确认药剂冷却状态，请稍后重试。',
        reward_inbox_full:'暂存区已满，请先领取后再打开礼包。',
        inventory_full:'背包已满，无法领取该物品，请先整理背包。',
        player_dead:'角色当前不可用，无法使用该物品。',
        player_unavailable:'角色当前不可用，无法使用该物品。',
        insufficient_quantity:'物品数量不足，无法继续使用。',
        insufficient_kpoints:'K 点不足，无法领取该自选配给。',
        stale_source:'背包物品已变化，请重新选择后再试。',
        stale_stash:'暂存区状态已变化，请重新打开后再试。',
        stale_choice:'自选配给选项已变化，请重新查看后再选。',
        choice_limit:'该自选配给已达到领取次数上限。',
        commit_pending:'上一笔领取仍在确认中，请稍候。',
        service_not_ready:'背包状态尚未就绪，请稍后重试。'
    };
    function mutationErrorCopy(error, command) {
        error = String(error || '');
        if (command === 'finalize') return '当前构筑尚未完成应用与保存，请重试关闭。';
        if (error === 'backpack_full' && command === 'unequipDrug') {
            return '背包已满（50/50），无法卸下药剂；请先整理背包或清理空位。';
        }
        return MUTATION_ERRORS[error] || '角色构筑同步失败，请重试。';
    }
    function itemUseErrorCopy(error) {
        return ITEM_USE_ERRORS[String(error || '')] || '物品使用失败，请重试。';
    }

    return {
        blockedCopy:blockedCopy,
        rowForTarget:rowForTarget,
        mutationErrorCopy:mutationErrorCopy,
        itemUseErrorCopy:itemUseErrorCopy
    };
});
