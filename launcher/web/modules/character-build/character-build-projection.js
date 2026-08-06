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
    var api = factory(tuningAdapter, eligibility);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildProjection = api;
        root.CharacterBuildProjection = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(TuningAdapter, CandidateEligibility) {
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
            blocked:row.disabled === true,
            tunable:capability.available,
            tuningReason:capability.reason
        };
    }

    function viewSnapshot(payload) {
        var equipment = {};
        var drugs = {};
        var rows = payload && payload.equipment || [];
        var i;
        for (i = 0; i < rows.length; i++) {
            equipment[String(rows[i].slotKey || '')] = safeItem(rows[i]);
        }
        rows = payload && payload.drugs || [];
        for (i = 0; i < rows.length; i++) {
            drugs['drug' + (Number(rows[i].slot) + 1)] =
                safeItem(rows[i]);
        }
        return {
            equipment:equipment,
            drugs:drugs,
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
        var result = [];
        for (var i = 0; i < rows.length; i++) {
            var row = CandidateEligibility.rowForTarget(
                rows[i] || {}, payload, target);
            var item = row.item || {};
            var source = row.source || {};
            var blocked = row.disabled === true;
            var blockedReason = blocked
                ? CandidateEligibility.blockedCopy(row.blockedReason) : '';
            var candidate = {
                key:'backpack:' + finite(row.physicalSlot, i)
                    + ':' + String(source.expectedLease || i),
                name:String(item.displayName || '未命名候选'),
                type:String(item.use || item.itemKind || '背包候选'),
                delta:'预览',
                summary:blockedReason
                    || '来自背包；首次选择只更新临时纸娃娃预览。',
                blockedReason:blockedReason,
                presentation:item,
                physicalSlot:finite(row.physicalSlot, i),
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
        if (selection.kind === 'drug') {
            var slot = /^drug([1-4])$/.exec(String(selection.id || ''));
            return slot
                ? {kind:'drug', drugSlot:Number(slot[1]) - 1}
                : null;
        }
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
