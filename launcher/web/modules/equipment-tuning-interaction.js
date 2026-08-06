/** Pure interaction authority projection for the Equipment Tuning feature. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.EquipmentTuningInteraction = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function interactionLockProjection(state) {
        state = state || {};
        var pendingCount = state.mux
            ? Math.max(0, Number(state.mux.pendingCount) || 0) : 0;
        var pendingKinds = state.mux && state.mux.pendingKinds instanceof Array
            ? state.mux.pendingKinds : null;
        var authorityPending = pendingCount > 0;
        if (authorityPending && pendingKinds && pendingKinds.length) {
            authorityPending = false;
            for (var pendingIndex = 0; pendingIndex < pendingKinds.length; pendingIndex++) {
                if (String(pendingKinds[pendingIndex]) !== 'tooltip') {
                    authorityPending = true;
                    break;
                }
            }
        }
        var phase = 'idle';
        var reason = '';

        if (state.detaching) {
            phase = 'detaching';
            reason = '正在结束调制会话，完成后才能继续操作。';
        } else if (state.refreshRetryPending
                && (state.refreshRetryRequired || !state.loadoutBarrier)) {
            phase = 'retry_pending';
            reason = state.sourceKind === 'loadout'
                ? '正在重试同步构筑，完成后才能继续操作。'
                : '正在重试同步背包，完成后才能继续操作。';
        } else if (state.refreshRetryRequired) {
            phase = 'retry_required';
            reason = state.sourceKind === 'loadout'
                ? '构筑同步失败，只能先重试构筑同步。'
                : '背包同步失败，只能先重试背包刷新。';
        } else if (state.needsReconcile && !state.refreshRetryPending) {
            phase = 'reconcile_required';
            reason = '正在核对调制结果，只能先重新对账。';
        } else if (state.loadoutBarrier) {
            phase = 'loadout_barrier';
            reason = '正在核对调制结果，完成后才能继续操作。';
        } else if (state.busy || state.inventoryWritePending) {
            phase = 'write_pending';
            reason = '调制写入尚未完成，完成后才能继续操作。';
        } else if (state.conversionLoading) {
            phase = 'conversion_loading';
            reason = '正在读取可交换装备，请等待结果。';
        } else if (state.readPending || authorityPending || state.previewScheduled) {
            phase = 'read_pending';
            reason = '正在读取调制状态，完成后才能继续操作。';
        }

        var idle = phase === 'idle';
        var sourceRecovery = phase === 'reconcile_required'
            && state.allowSourceRecovery === true;
        var enhanceDraft = phase === 'read_pending'
            && state.operation === 'enhance'
            && (state.previewPendingOperation === 'enhance'
                || state.previewScheduled === true);
        var canChooseEnhancement = idle || enhanceDraft;
        return {
            phase:phase,
            reason:reason,
            blocked:!idle,
            source:idle || sourceRecovery,
            snapshot:idle,
            tabs:idle,
            tier:idle,
            stepper:canChooseEnhancement,
            number:canChooseEnhancement,
            range:canChooseEnhancement,
            mark:canChooseEnhancement,
            cap:canChooseEnhancement,
            candidate:idle,
            conversionCandidate:idle,
            slot:idle,
            detach:idle,
            confirmation:idle,
            inspect:idle,
            commit:idle && state.hasPreviewToken === true,
            retry:phase === 'retry_required',
            reconcile:phase === 'reconcile_required',
            enhanceDraft:enhanceDraft
        };
    }

    return {interactionLockProjection:interactionLockProjection};
});
