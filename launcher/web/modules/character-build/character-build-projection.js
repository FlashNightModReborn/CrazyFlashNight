/**
 * Character Build wire payload -> view-model projection.
 *
 * The Host has already validated the wire shape. This leaf only removes
 * protocol framing and derives presentation capability from the shared tuning
 * policy; it never owns transport or gameplay decisions.
 */
(function(root, factory) {
    'use strict';
    var tuningAdapter = typeof module !== 'undefined' && module.exports
        ? require('./character-build-tuning-adapter.js')
        : root && root.CharacterBuildTuningAdapter;
    var eligibility = typeof module !== 'undefined' && module.exports
        ? require('./character-build-candidate-eligibility.js')
        : root && root.CharacterBuildCandidateEligibility;
    var drugLayout = typeof module !== 'undefined' && module.exports
        ? require('./character-build-drug-layout.js')
        : root && root.CharacterBuildDrugLayout;
    var api = factory(tuningAdapter, eligibility, drugLayout);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildProjection = api;
        root.CharacterBuildProjection = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(TuningAdapter, CandidateEligibility, DrugLayout) {
    'use strict';

    if (!TuningAdapter
            || typeof TuningAdapter.tuningCapability !== 'function') {
        throw new Error(
            'character-build-projection.js requires CharacterBuildTuningAdapter');
    }
    if (!CandidateEligibility
            || typeof CandidateEligibility.rowForTarget !== 'function') {
        throw new Error(
            'character-build-projection.js requires CharacterBuildCandidateEligibility');
    }
    if (!DrugLayout || typeof DrugLayout.projectRows !== 'function') {
        throw new Error(
            'character-build-projection.js requires CharacterBuildDrugLayout');
    }

    function finite(value, fallback) {
        value = Number(value);
        return isFinite(value) && Math.floor(value) === value
            ? value : fallback;
    }

    function safeItem(row) {
        if (!row || row.occupied !== true || !row.item) return null;
        var item = row.item;
        var capability = TuningAdapter.tuningCapability(item);
        var suffix = [];
        if (Number(item.enhancementLevel) > 0) {
            suffix.push('+' + Number(item.enhancementLevel));
        }
        if (Number(row.quantity || item.quantity) > 1) {
            suffix.push('× ' + Number(row.quantity || item.quantity));
        }
        return {
            name:String(item.displayName || '未知物品'),
            meta:suffix.join(' · ')
                || String(item.use || item.itemKind || '已装备'),
            type:String(item.use || item.itemKind || ''),
            presentation:item,
            // Cooldown changes whether a potion can fire, not whether its
            // physical slot can be selected and inspected.  The in-tile shade
            // owns cooldown feedback; red blocked styling is reserved for an
            // actual slot-data failure.
            blocked:row.disabled === true,
            tunable:capability.available,
            tuningReason:capability.reason
        };
    }

    function useBlockedCopy(reason) {
        reason = String(reason || '');
        if (reason === 'no_available_lane') {
            return '四条药剂通道当前都不能承接：没有空闲通道，也没有可用的同名药剂通道。';
        }
        if (reason === 'player_dead' || reason === 'player_unavailable') {
            return '角色当前不可用，无法服用药剂。';
        }
        if (reason === 'authority_unavailable' || reason === 'service_not_ready'
                || reason === 'cooldown_unavailable') {
            return '暂时无法确认背包与冷却状态，请稍后重试。';
        }
        if (reason === 'reward_inbox_full') {
            return '待领取区已满，请先领取其中的物品。';
        }
        return reason ? '当前不能使用：' + reason : '';
    }

    function viewSnapshot(payload) {
        var equipment = {};
        var rows = payload && payload.equipment || [];
        for (var i = 0; i < rows.length; i++) {
            equipment[String(rows[i].slotKey || '')] = safeItem(rows[i]);
        }
        var drugs = DrugLayout.projectRows(payload && payload.drugs, safeItem);
        return {
            equipment:equipment,
            drugs:drugs.drugs,
            drugMeta:drugs.drugMeta,
            drugLayout:payload && payload.drugLayout || null,
            portrait:payload && payload.portrait || {},
            candidateFacets:payload && payload.candidateFacets || null,
            blocked:payload && payload.stateHealth !== 'ok',
            blockedReason:payload && payload.stateHealth !== 'ok'
                ? '部分角色数据不可用；请检查候选阻断原因，当前装备尚未改变。'
                : ''
        };
    }

    function viewCandidates(payload, targetOverride) {
        var rows = payload && payload.candidates || [];
        var target = targetOverride || payload && payload.target || null;
        var overview = target && target.kind === 'backpack';
        var result = [];
        for (var i = 0; i < rows.length; i++) {
            var row = CandidateEligibility.rowForTarget(
                rows[i] || {}, payload, target);
            var item = row.item || {};
            var source = row.source || {};
            var rawUseAction = overview && row.useAction || null;
            var useCommand = rawUseAction && String(rawUseAction.command || '');
            var useAction = useCommand === 'open' || useCommand === 'consume' ? {
                command:useCommand,
                label:String(rawUseAction.label
                    || (useCommand === 'open' ? '打开' : '服用'))
            } : null;
            var useBlockedReason = useAction
                ? useBlockedCopy(row.useBlockedReason) : '';
            var blocked = row.disabled === true && !useAction;
            var blockedReason = blocked
                ? CandidateEligibility.blockedCopy(
                    row.blockedReason, overview) : '';
            var candidate = {
                key:'backpack:' + finite(row.physicalSlot, i)
                    + ':' + String(source.expectedLease || i),
                name:String(item.displayName || '未命名候选'),
                type:String(item.use || item.itemKind || '背包候选'),
                delta:overview ? '总览' : '预览',
                summary:useBlockedReason || blockedReason
                    || (overview
                        ? useAction
                            ? useAction.command === 'open'
                                ? '选中后点击“打开”；内容会进入待领取页。'
                                : '选中后点击“服用”；系统会选择符合规则的冷却通道。'
                            : '来自背包总览；拖到高亮栏位可直接配装。'
                        : '来自背包；首次选择只更新临时纸娃娃预览。'),
                blockedReason:blockedReason,
                useAction:useAction,
                useBlockedReason:useBlockedReason,
                presentation:item,
                physicalSlot:finite(row.physicalSlot, i),
                backpackVersion:finite(source.backpackVersion,
                    finite(row.backpackVersion,
                        finite(payload && payload.backpackVersion, -1))),
                badgeKind:'preview',
                blocked:blocked,
                raw:row
            };
            var tuning = TuningAdapter.capability(candidate);
            candidate.tunable = tuning.available;
            candidate.tuningReason = tuning.reason;
            candidate.tuningSource = tuning.source;
            result.push(candidate);
        }
        return result;
    }

    function targetForSelection(selection) {
        if (!selection) return null;
        if (selection.kind === 'backpack') return {kind:'backpack'};
        if (selection.kind === 'drug') return DrugLayout.targetForSelection(selection);
        return /^(armor|weapon)$/.test(String(selection.kind || ''))
                && selection.id
            ? {kind:'equipment', slotKey:String(selection.id)}
            : null;
    }

    return {
        viewSnapshot:viewSnapshot,
        viewCandidates:viewCandidates,
        targetForSelection:targetForSelection
    };
});
