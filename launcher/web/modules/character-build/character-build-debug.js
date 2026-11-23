/** Read-only diagnostic projections for the loadout session and its controller. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CharacterBuildDebug = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function sessionState() {
        return {
            state:this._state,
            panelInstanceId:this._panelInstanceId,
            sessionGeneration:this._sessionGeneration,
            writeEpoch:this._writeEpoch,
            loadoutRevision:this._loadoutRevision,
            liveRevision:this._liveRevision,
            drugRevision:this._drugRevision,
            candidateScope:this._candidateScope,
            candidateFailureCode:this._candidateFailureCode,
            liveRefreshDirty:this._liveRefreshDirty,
            unknown:this._unknown ? {kind:this._unknown.kind, callId:this._unknown.callId} : null,
            openingAttempts:this._openingAttempts,
            hasSnapshot:!!this._snapshot,
            mux:this._mux && this._mux.debugState ? this._mux.debugState() : null
        };
    }

    function controllerState() {
        return {
            mounted:!!this._view,
            rendererCount:this._renderer ? 1 : 0,
            selectedTarget:this._selectedTarget,
            selectedSlotKey:this._selectedSlotKey,
            mutationPending:this._mutations.isPending(),
            tuning:this._tuning ? this._tuning.debugState() : null,
            candidateTooltip:this._candidateTooltip
                ? this._candidateTooltip.debugState() : null,
            candidateCacheCount:this._candidateCache ? 1 : 0,
            itemUseResumeSelection:this._itemUseResumeSelection ? {
                physicalSlot:this._itemUseResumeSelection.physicalSlot,
                itemName:this._itemUseResumeSelection.itemName,
                requestKey:this._itemUseResumeSelection.requestKey || ''
            } : null,
            itemUse:this._itemUse.debugState(),
            session:this._session.debugState(),
            view:this._view ? this._view.debugState() : null
        };
    }

    return {sessionState:sessionState, controllerState:controllerState};
});
