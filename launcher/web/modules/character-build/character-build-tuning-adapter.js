/**
 * Character Build loadout/candidate -> shared Equipment Tuning adapter.
 *
 * This leaf validates both authority shapes and owns candidate entry, refresh,
 * and deterministic return fencing through injected session/cache ports. It
 * owns no Bridge listener or tuning writer.
 */
(function(root, factory) {
    'use strict';
    var model = typeof module !== 'undefined' && module.exports
        ? require('../equipment-tuning-model.js') : root && root.EquipmentTuningModel;
    var actions = typeof module !== 'undefined' && module.exports
        ? require('../loadout-picker/loadout-picker-action-view.js') : root && root.LoadoutPickerActionView;
    var api = factory(model, actions);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildTuningAdapter = api;
        root.CharacterBuildTuningAdapter = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(EquipmentTuningModel, LoadoutPickerActionView) {
    'use strict';

    if (!EquipmentTuningModel || !EquipmentTuningModel.normalizeTuningSource
            || !LoadoutPickerActionView
            || !LoadoutPickerActionView.tuningCapability) {
        throw new Error('CharacterBuildTuningAdapter requires tuning model and action policy');
    }

    var SOURCE_KEYS = {containerId:true, slot:true, expectedLease:true};
    function findLoadoutItem(payload, slotKey) {
        var rows = payload && payload.equipment || [];
        for (var i = 0; i < rows.length; i++) {
            if (rows[i] && rows[i].slotKey === slotKey && rows[i].occupied === true
                    && rows[i].item) return rows[i].item;
        }
        return null;
    }
    function findEquipment(payload, slotKey) {
        var item = findLoadoutItem(payload, slotKey);
        return LoadoutPickerActionView.tuningCapability(item).available ? item : null;
    }
    function loadoutSourceFor(session, slotKey) {
        var state = session && session.debugState ? session.debugState() : null;
        return EquipmentTuningModel.normalizeTuningSource({
            sourceKind:'loadout',
            sessionGeneration:state && state.sessionGeneration,
            slotKey:String(slotKey || ''),
            expectedLoadoutRevision:state && state.loadoutRevision
        });
    }
    function refreshLoadout(options, source, callback) {
        var session = options.session;
        var requestedSource =
            EquipmentTuningModel.normalizeTuningSource(source);
        var currentSource = loadoutSourceFor(session, options.slotKey);
        if (!options.active() || !requestedSource || !options.entrySource
                || !EquipmentTuningModel.sameLoadoutIdentity(
                    requestedSource, options.entrySource)
                || !EquipmentTuningModel.sameLoadoutIdentity(
                    currentSource, options.entrySource)
                || session.getState() !== 'idle') return false;
        var callId = session.refreshSnapshot(function(response, accepted) {
            if (!options.active()) return;
            if (!accepted || !response || !response.payload) {
                callback({success:false, error:response && response.error
                    || 'loadout_snapshot_failed'});
                return;
            }
            var nextSource = loadoutSourceFor(session, options.slotKey);
            var item = findEquipment(response.payload, options.slotKey);
            if (!nextSource || !EquipmentTuningModel.sameLoadoutIdentity(
                    nextSource, options.entrySource) || !item) {
                callback({success:false, error:'loadout_projection_incomplete'});
                return;
            }
            options.adopt(response.payload);
            options.sync();
            callback({success:true, source:nextSource, item:item});
        });
        return !!callId;
    }
    function exactKeys(value, allowed, count) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
        var keys = Object.keys(value);
        if (keys.length !== count) return false;
        for (var i = 0; i < keys.length; i++) {
            if (allowed[keys[i]] !== true) return false;
        }
        return true;
    }
    function structuralSource(candidate) {
        var raw = candidate && candidate.raw;
        var source = raw && raw.source;
        if (!exactKeys(source, SOURCE_KEYS, 3)) return null;
        var physicalSlot = Number(candidate.physicalSlot);
        if (!isFinite(physicalSlot) || Math.floor(physicalSlot) !== physicalSlot
                || Number(raw.physicalSlot) !== physicalSlot
                || Number(source.slot) !== physicalSlot) return null;
        return EquipmentTuningModel.normalizeTuningSource({
            sourceKind:'inventory',
            containerId:source.containerId,
            slot:source.slot,
            expectedLease:source.expectedLease
        });
    }
    function blockedReason(candidate) {
        var raw = candidate && candidate.raw || {};
        var reason = String(raw.blockedReason || candidate && candidate.blockedReason || '');
        if (reason === 'level_locked') return '该候选当前等级不足，不能调制';
        return reason && !/^[a-z0-9_]+$/i.test(reason)
            ? reason : '该候选当前不可用，不能调制';
    }
    function sourceFor(candidate) {
        var projected = capability(candidate);
        return projected.available ? projected.source : null;
    }
    function capability(candidate) {
        if (!candidate) return {
            available:false, code:'empty', reason:'尚未选择候选装备', source:null
        };
        if (candidate.blocked === true
                || candidate.raw && candidate.raw.disabled === true) return {
            available:false, code:'blocked', reason:blockedReason(candidate), source:null
        };
        var itemCapability =
            LoadoutPickerActionView.tuningCapability(candidate.presentation);
        if (!itemCapability.available) return {
            available:false,
            code:itemCapability.code,
            reason:itemCapability.reason,
            source:null
        };
        var source = structuralSource(candidate);
        return source ? {
            available:true, code:'available', reason:'', source:source
        } : {
            available:false,
            code:'invalid_source',
            reason:'候选位置凭据已失效，请重新选择当前槽位',
            source:null
        };
    }
    function slotFor(candidate) {
        var projected = capability(candidate);
        return projected.available ? {
            occupied:true,
            physicalSlot:projected.source.slot,
            slotLease:projected.source.expectedLease,
            item:candidate.presentation
        } : null;
    }
    function returnState(candidate, index) {
        return {
            source:structuralSource(candidate),
            key:String(candidate && candidate.key || ''),
            name:String(candidate && candidate.name || ''),
            originalIndex:Math.max(0, Math.floor(Number(index) || 0))
        };
    }
    function sameExactSource(candidate, source) {
        var current = structuralSource(candidate);
        return !!current && !!source
            && current.sourceKind === source.sourceKind
            && current.containerId === source.containerId
            && current.slot === source.slot
            && current.expectedLease === source.expectedLease;
    }
    function availableFallback(candidates, start, direction) {
        for (var i = start; i >= 0 && i < candidates.length; i += direction) {
            if (candidates[i] && candidates[i].blocked !== true) return i;
        }
        return -1;
    }
    function resolveReturn(state, candidates, postSource) {
        candidates = Array.isArray(candidates) ? candidates : [];
        state = state || {};
        postSource = EquipmentTuningModel.normalizeTuningSource(postSource);
        if (postSource && postSource.sourceKind === 'inventory'
                && state.source && postSource.slot === state.source.slot) {
            var exactIndex = -1, slotMatches = 0;
            for (var i = 0; i < candidates.length; i++) {
                var current = structuralSource(candidates[i]);
                if (!current || current.slot !== state.source.slot) continue;
                slotMatches += 1;
                if (sameExactSource(candidates[i], postSource)) exactIndex = i;
            }
            if (slotMatches > 1) return {kind:'empty', index:-1, candidate:null};
            if (exactIndex >= 0) return {
                kind:'exact', index:exactIndex, candidate:candidates[exactIndex]
            };
        }
        var index = Math.min(
            Math.max(0, Number(state.originalIndex) || 0),
            Math.max(0, candidates.length - 1));
        index = availableFallback(candidates, index, 1);
        if (index < 0) {
            index = availableFallback(candidates,
                Math.min(candidates.length - 1,
                    Math.max(0, Number(state.originalIndex) - 1 || 0)), -1);
        }
        return index >= 0
            ? {kind:'adjacent', index:index, candidate:candidates[index]}
            : {kind:'empty', index:-1, candidate:null};
    }
    function CandidateFlow(options) {
        options = options || {};
        if (!options.session || !options.view
                || typeof options.projectCandidates !== 'function') {
            throw new Error('CandidateFlow requires session, view, and projection ports');
        }
        this._session = options.session;
        this._view = options.view;
        this._ports = options.ports || {};
        this._projectCandidates = options.projectCandidates;
        this._invalidateTooltip = options.invalidateTooltip || function() {};
        this._active = false;
        this._epoch = 0;
        this._requestGeneration = 0;
        this._entry = null;
    }
    CandidateFlow.prototype.begin = function(candidate, target, panelInstanceId) {
        var projected = capability(candidate);
        var session = this._session.debugState();
        var view = this._view.debugState();
        var candidates = this._view.getCandidates();
        var index = -1, sourceMatches = 0;
        for (var i = 0; i < candidates.length; i++) {
            if (candidates[i] && candidates[i].key === candidate.key) { index = i; break; }
        }
        for (var j = 0; j < candidates.length; j++) {
            var source = structuralSource(candidates[j]);
            if (source && projected.source
                    && source.slot === projected.source.slot) sourceMatches += 1;
        }
        if (this._active || !projected.available || index < 0 || sourceMatches !== 1
                || !target || target.kind !== 'equipment'
                || session.state !== 'idle'
                || session.panelInstanceId !== String(panelInstanceId || '')
                || view.selectedCandidateKey !== String(candidate.key || '')
                || !view.candidateRequestKey || !view.selectedSlotKey
                || view.selectedSlotKey.split(':').slice(1).join(':') !== target.slotKey) return null;
        var scroll = this._view.root.querySelector('.character-build-candidate-scroll');
        this._entry = returnState(candidate, index);
        this._entry.slotKey = view.selectedSlotKey;
        this._entry.requestKey = view.candidateRequestKey;
        this._entry.scrollTop = scroll ? scroll.scrollTop : 0;
        this._entry.target = {kind:'equipment', slotKey:String(target.slotKey)};
        this._entry.panelInstanceId = session.panelInstanceId;
        this._entry.sessionGeneration = session.sessionGeneration;
        this._active = true;
        this._epoch += 1;
        return {
            source:projected.source,
            slot:slotFor(candidate),
            item:candidate.presentation
        };
    };
    CandidateFlow.prototype._fenced = function(epoch, requestGeneration) {
        var session = this._session.debugState();
        var view = this._view.debugState();
        return this._active && epoch === this._epoch
            && (requestGeneration == null
                || requestGeneration === this._requestGeneration)
            && session.state === 'idle'
            && session.panelInstanceId === this._entry.panelInstanceId
            && session.sessionGeneration === this._entry.sessionGeneration
            && view.selectedSlotKey === this._entry.slotKey
            && view.candidateRequestKey === this._entry.requestKey;
    };
    CandidateFlow.prototype._refreshCandidates = function(callback) {
        var self = this, epoch = this._epoch;
        var generation = ++this._requestGeneration;
        var target = this._entry.target;
        this._invalidateTooltip();
        var callbackCalled = false;
        var callId = this._session.requestCandidates(target, function(response, accepted, targetKey) {
            callbackCalled = true;
            if (!self._fenced(epoch, generation)) return;
            if (!accepted || targetKey !== 'equipment:' + target.slotKey
                    || !response || !response.payload) {
                callback({success:false, error:response && response.error
                    || 'candidate_refresh_failed'});
                return;
            }
            var candidates;
            try { candidates = self._projectCandidates(response.payload); }
            catch (_) { callback({success:false, error:'candidate_projection_failed'}); return; }
            if (!self._view.setCandidates(self._entry.requestKey, candidates)) {
                callback({success:false, error:'candidate_view_stale'});
                return;
            }
            self._invalidateTooltip();
            callback({success:true, refreshed:true});
        });
        if (!callId && !callbackCalled && this._fenced(epoch, generation)) {
            callback({success:false, error:'candidate_refresh_not_sent'});
        }
        return !!callId;
    };
    CandidateFlow.prototype.completeWrite = function(operation, needsRefresh, callback) {
        if (!this._active || !operation) return false;
        var self = this, epoch = this._epoch;
        function cacheComplete(result) {
            if (!self._fenced(epoch)) return;
            if (!result || result.success !== true) { callback(result); return; }
            if (needsRefresh) self._refreshCandidates(callback);
            else callback({success:true, refreshed:false});
        }
        return this._ports.completeExternalWrite
            ? !!this._ports.completeExternalWrite(
                operation, null, cacheComplete, !!needsRefresh)
            : (cacheComplete({success:true, refreshed:false}), true);
    };
    CandidateFlow.prototype.refreshInventory = function(callback) {
        if (!this._active) return false;
        var self = this, epoch = this._epoch;
        function cacheComplete(result) {
            if (!self._fenced(epoch)) return;
            if (!result || result.success !== true) { callback(result); return; }
            self._refreshCandidates(callback);
        }
        return this._ports.refreshExternalInventory
            ? !!this._ports.refreshExternalInventory(cacheComplete)
            : (cacheComplete({success:true, refreshed:false}), true);
    };
    CandidateFlow.prototype.resolveSlot = function(containerId, physicalSlot) {
        if (!this._active || containerId !== '背包') return null;
        var candidates = this._view.getCandidates(), resolved = null, matches = 0;
        for (var i = 0; i < candidates.length; i++) {
            var source = structuralSource(candidates[i]);
            if (source && source.slot === Number(physicalSlot)) {
                matches += 1; resolved = slotFor(candidates[i]);
            }
        }
        return matches === 1 ? resolved : null;
    };
    CandidateFlow.prototype.postSource = function(tuningView) {
        var state = tuningView && tuningView.debugState ? tuningView.debugState() : null;
        return state && state.source && state.source.sourceKind === 'inventory'
            ? state.source : null;
    };
    CandidateFlow.prototype.deactivate = function() {
        var entry = this._entry;
        this._active = false;
        this._epoch += 1;
        this._entry = null;
        return entry;
    };
    CandidateFlow.prototype.returnPlan = function(entry, postSource) {
        return resolveReturn(entry, this._view.getCandidates(), postSource);
    };
    CandidateFlow.prototype.isActive = function() { return this._active; };
    return {
        sourceFor:sourceFor,
        capability:capability,
        tuningCapability:LoadoutPickerActionView.tuningCapability,
        slotFor:slotFor,
        returnState:returnState,
        resolveReturn:resolveReturn,
        CandidateFlow:CandidateFlow,
        loadoutSourceFor:loadoutSourceFor,
        refreshLoadout:refreshLoadout,
        findLoadoutItem:findLoadoutItem,
        findEquipment:findEquipment
    };
});
