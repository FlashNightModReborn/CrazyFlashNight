/** 礼包「全部打开」按钮：数量 ≥2 的礼包候选才可见，count 冻结为 min(数量, 64)。 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CharacterBuildItemUseOpenManyView = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    /** 礼包数量 ≥2 时的批量打开入口；count 冻结为 min(数量, 64)。 */
    function quantity(candidate, action) {
        if (!candidate || !action || String(action.command || '') !== 'open') return 0;
        var raw = candidate.raw || {};
        var presentation = candidate.presentation || {};
        var value = Number(raw.quantity != null
            ? raw.quantity : presentation.quantity);
        if (!isFinite(value) || Math.floor(value) !== value
                || value < 2) return 0;
        return Math.min(value, 64);
    }

    function tryUse(view, candidate) {
        if (!candidate || !candidate.useAction) return false;
        if (candidate.useBlockedReason) {
            view._showStatusNotice('blocked', candidate.useBlockedReason);
            return false;
        }
        if (view._itemUseState !== 'idle'
                && view._itemUseState !== 'needs_reconcile') return false;
        var count = quantity(candidate, candidate.useAction);
        if (count < 2) return false;
        var manyCandidate = {};
        for (var key in candidate) {
            if (Object.prototype.hasOwnProperty.call(candidate, key)) {
                manyCandidate[key] = candidate[key];
            }
        }
        manyCandidate.useAction = {command:'openMany',
            label:'全部打开×' + count, count:count};
        return view._onUseCandidate(manyCandidate) !== false;
    }

    function syncButton(view, context) {
        if (!view._useManyButton) return false;
        var candidate = context.candidate;
        var count = quantity(candidate, context.action);
        view._useManyButton.hidden = count < 2;
        view._useManyButton.textContent = context.reconciling ? '重新确认'
            : context.submitting || context.confirming ? context.pendingLabel
            : '全部打开×' + count;
        view._useManyButton.disabled = count < 2
            || !!candidate.useBlockedReason
            || (view._itemUseState !== 'idle' && !context.reconciling)
            || (view._interactionState !== 'idle' && !context.reconciling);
        view._useManyButton.setAttribute('aria-label', count < 2
            ? '打开全部所选礼包'
            : '全部打开' + count + ' 个'
                + String(candidate && candidate.name || '所选礼包'));
        return true;
    }

    return {quantity:quantity, tryUse:tryUse, syncButton:syncButton};
});
