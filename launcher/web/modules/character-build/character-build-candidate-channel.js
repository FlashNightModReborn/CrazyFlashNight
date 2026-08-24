/** Optimistic read-only candidate cache and authoritative refresh orchestration. */
(function(root, factory) {
    'use strict';
    var session = typeof module !== 'undefined' && module.exports
        ? require('../character-build-session.js') : root && root.CharacterBuildSession;
    var projection = typeof module !== 'undefined' && module.exports
        ? require('./character-build-projection.js') : root && root.CharacterBuildProjection;
    var transition = typeof module !== 'undefined' && module.exports
        ? require('./character-build-slot-transition.js') : root && root.CharacterBuildSlotTransition;
    var tuning = typeof module !== 'undefined' && module.exports
        ? require('./character-build-tuning.js') : root && root.CharacterBuildTuning;
    var dropTargets = typeof module !== 'undefined' && module.exports
        ? require('../loadout-picker/loadout-picker-drop-policy.js')
        : root && root.LoadoutPickerDropPolicy;
    var api = factory(session, projection, transition, tuning, dropTargets);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildCandidateChannel = api;
        root.CharacterBuildCandidateChannel = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(SessionModule, Projection, SlotTransition, TuningModule, DropTargetsModule) {
    'use strict';
    if (!SessionModule || typeof SessionModule.candidateScope !== 'function') {
        throw new Error('CharacterBuildCandidateChannel requires CharacterBuildSession');
    }
    if (!Projection || typeof Projection.viewCandidates !== 'function') {
        throw new Error('CharacterBuildCandidateChannel requires CharacterBuildProjection');
    }
    if (!SlotTransition || typeof SlotTransition.handle !== 'function') {
        throw new Error('CharacterBuildCandidateChannel requires CharacterBuildSlotTransition');
    }
    if (!TuningModule || !TuningModule.CharacterBuildTuning) {
        throw new Error('CharacterBuildCandidateChannel requires CharacterBuildTuning');
    }
    if (!DropTargetsModule || typeof DropTargetsModule.isDrugRow !== 'function') {
        throw new Error('CharacterBuildCandidateChannel requires LoadoutPickerDropPolicy');
    }

    function definitiveCandidateStale(response) {
        return !!response && response.success === false
            && String(response.error || '') === 'stale_state';
    }
    function candidateCacheTarget(target, scope) {
        if (!target || typeof target !== 'object') return '';
        if (target.kind === 'backpack') {
            return SessionModule.candidateScope(scope) === 'backpack'
                ? 'backpack' : '';
        }
        if (target.kind === 'equipment') {
            scope = SessionModule.candidateScope(scope || 'compatible');
            if (scope === 'backpack') return 'equipment:backpack';
            var slotKey = String(target.slotKey || '');
            // Both handgun holders consume the same `use=手枪` candidate rule.
            // Reusing their read model is safe; the eventual write still carries
            // the exact selected holder and source lease.
            return slotKey === '手枪' || slotKey === '手枪2'
                ? 'equipment:手枪' : '';
        }
        // Drug readiness can change with time without advancing a revision. Do
        // not cache it, and do not generalize this exception into a multi-key LRU.
        return '';
    }

    function install(controller) {
        if (!controller) {
            throw new Error('CharacterBuildCandidateChannel.install requires a controller method target');
        }
        controller._candidateCacheKey = function(target, scope) {
            var targetKey = candidateCacheTarget(target, scope);
            var state = this._session && this._session.debugState
                ? this._session.debugState() : null;
            if (!targetKey || !state || !state.sessionGeneration) return '';
            return [this._panelInstanceId, state.sessionGeneration,
                state.loadoutRevision, state.drugRevision,
                SessionModule.candidateScope(scope), targetKey].join('\n');
        };
        controller._readCandidateCache = function(target, scope) {
            var key = this._candidateCacheKey(target, scope);
            var entry = this._candidateCache;
            if (!key || !entry || entry.key !== key) return null;
            return entry.payload
                ? Projection.viewCandidates(entry.payload, target)
                : Array.isArray(entry.candidates) ? entry.candidates.slice() : null;
        };
        controller._storeCandidateCache = function(
                target, scope, payload, candidates) {
            var key = this._candidateCacheKey(target, scope);
            this._candidateCache = null;
            if (!key || !payload || payload.stateHealth !== 'ok'
                    || !Array.isArray(candidates)) return false;
            this._candidateCache = {
                key:key,
                backpackVersion:Number(payload.backpackVersion),
                payload:scope === 'backpack' && target
                        && (target.kind === 'equipment'
                            || target.kind === 'backpack') ? payload : null,
                candidates:candidates.slice()
            };
            return true;
        };
        controller._selectSlot = function(selection) {
            var target = Projection.targetForSelection(selection);
            var scope = SessionModule.candidateScope(
                selection && selection.candidateScope || 'compatible');
            if (!target || !scope) return false;
            var previousScope = this._candidateScope;
            var previousSlotKey = this._selectedSlotKey;
            var previousTarget = this._selectedTarget;
            this._candidateScope = scope;
            if (!this._session.setCandidateScope(scope)) {
                this._candidateScope = previousScope;
                return false;
            }
            var tuningResult = SlotTransition.handle(this, selection, target, TuningModule);
            if (tuningResult !== null) {
                if (tuningResult && tuningResult.deferCandidates === true) {
                    this._selectedSlotKey = selection && String(selection.key || '');
                    this._selectedTarget = target;
                    this._renderPortrait(null);
                }
                if (!tuningResult) {
                    this._candidateScope = previousScope;
                    this._session.setCandidateScope(previousScope);
                }
                return tuningResult;
            }
            this._selectedSlotKey = selection && String(selection.key || '');
            this._selectedTarget = target;
            this._renderPortrait(null);
            var cachedCandidates = this._readCandidateCache(target, scope);
            if (cachedCandidates) return cachedCandidates;
            var self = this, sendRefused = false;
            var callId = this._session.requestCandidates(target, scope, function(
                    response, accepted, targetKey, responseScope) {
                sendRefused = !accepted && response && response.clientSynthetic === true && response.error === 'not_sent';
                if (!self._view || self._candidateScope !== scope
                        || responseScope !== scope) return;
                if (accepted) {
                    var candidates = Projection.viewCandidates(response.payload, target);
                    self._storeCandidateCache(target, scope, response.payload, candidates);
                    self._view.setCandidates(
                        selection.requestKey,
                        candidates);
                } else if (definitiveCandidateStale(response)
                        && self._recoverCandidateSelection(selection)) {
                    return;
                } else {
                    self._view.setCandidateFailure(
                        selection.requestKey, response && response.error);
                }
            });
            if (!callId || sendRefused) {
                // Keep controller and View rollback transactional when transport admission fails.
                this._selectedSlotKey = previousSlotKey;
                this._selectedTarget = previousTarget;
                this._candidateScope = previousScope;
                this._session.setCandidateScope(previousScope);
                this._renderPortrait(null);
            }
            return sendRefused ? null : callId;
        };

        controller._changeCandidateScope = function(scope, selection) {
            scope = SessionModule.candidateScope(scope);
            if (!scope) return false;
            var previousScope = this._candidateScope;
            var previousSlotKey = this._selectedSlotKey;
            var previousTarget = this._selectedTarget;
            this._candidateScope = scope;
            if (!this._session.setCandidateScope(scope)) {
                this._candidateScope = previousScope;
                return false;
            }
            this._selectedCandidate = null;
            this._renderPortrait(null);
            if (!selection) return true;

            var target = Projection.targetForSelection(selection);
            if (!target) {
                this._candidateScope = previousScope;
                this._session.setCandidateScope(previousScope);
                return false;
            }
            if (target.kind === 'backpack') {
                this._selectedSlotKey = '';
                this._selectedTarget = null;
            } else if (SessionModule.targetKey(target)
                    !== SessionModule.targetKey(this._selectedTarget)) {
                this._candidateScope = previousScope;
                this._session.setCandidateScope(previousScope);
                return false;
            }
            var cachedCandidates = this._readCandidateCache(target, scope);
            if (cachedCandidates) return cachedCandidates;
            var self = this, sendRefused = false;
            var callId = this._session.requestCandidates(target, scope, function(
                    response, accepted, targetKey, responseScope) {
                sendRefused = !accepted && response && response.clientSynthetic === true
                    && response.error === 'not_sent';
                if (!self._view || self._candidateScope !== scope
                        || responseScope !== scope) return;
                if (accepted) {
                    var candidates = Projection.viewCandidates(response.payload, target);
                    self._storeCandidateCache(target, scope, response.payload, candidates);
                    self._view.setCandidates(
                        selection.requestKey,
                        candidates);
                } else if (definitiveCandidateStale(response)
                        && self._recoverCandidateSelection(selection)) {
                    return;
                } else {
                    self._view.setCandidateFailure(
                        selection.requestKey, response && response.error);
                }
            });
            if (!callId || sendRefused) {
                this._candidateScope = previousScope;
                this._session.setCandidateScope(previousScope);
                this._selectedSlotKey = previousSlotKey;
                this._selectedTarget = previousTarget;
                this._renderPortrait(null);
            }
            return sendRefused ? false : callId;
        };
        /**
     * Drop-commit path. The view supplies the exact drop slot and the mutation
     * carries its own target, so the write does not depend on the browse anchor.
     * A write never changes scope/anchor: `_applySnapshot` restores the explicit
     * pre-drop browsing context, while the exact drop slot only receives data.
     */
    controller._equipDroppedCandidate = function(slotKey, candidate) {
        if (!candidate || this._session.getState() !== 'idle') return false;
        var parts = String(slotKey || '').split(':');
        var target = Projection.targetForSelection({
            key:String(slotKey || ''), kind:parts.shift(), id:parts.join(':')
        });
        if (!target) return false;
        if (candidate.blocked === true) {
            // blocked 只描述与当前选中槽位的关系；落点提交以该物品的槽位
            // 白名单（装备）或协议药剂判别（药剂槽）为本地门禁，Host 仍是最终权威。
            var allowed = target.kind === 'drug'
                ? DropTargetsModule.isDrugRow(candidate)
                : (function() {
                    var eligibility = candidate.raw && candidate.raw.equipmentEligibility;
                    var slots = eligibility && Array.isArray(eligibility.slots)
                        ? eligibility.slots : [];
                    return target.kind === 'equipment'
                        && slots.indexOf(String(target.slotKey || '')) >= 0
                        && String(eligibility && eligibility.blockedReason || '') === '';
                })();
            if (!allowed) return false;
            candidate = Object.create(candidate);
            candidate.blocked = false;
            candidate.blockedReason = '';
        }
        return !!this._mutations.equip(target, candidate);
    };
    controller._recoverCandidateSelection = function(selection) {
            if (!this._view || !selection
                    || !this._view.beginCandidateRecovery(selection.requestKey)) return false;
            var self = this;
            var recovery = ++this._candidateRecoverySequence;
            var generation = this._mountGeneration;
            var panelInstanceId = this._panelInstanceId;
            this._view.setInteractionState('opening');
            var callId = this._session.refreshSnapshot({}, function(response, accepted) {
                if (!self._view || recovery !== self._candidateRecoverySequence
                        || generation !== self._mountGeneration
                        || panelInstanceId !== self._panelInstanceId) return;
                if (accepted) self._applySnapshot(response.payload, true);
                else self._view.setCandidateFailure(
                    selection.requestKey, 'snapshot_refresh_failed');
                if (self._view) {
                    self._view.setInteractionState(self._session.getState());
                }
            });
            if (!callId && this._view && recovery === this._candidateRecoverySequence) {
                this._view.setCandidateFailure(
                    selection.requestKey, 'snapshot_refresh_failed');
                this._view.setInteractionState(this._session.getState());
            }
            return !!callId;
        };
        return controller;
    }

    return {install:install, candidateCacheTarget:candidateCacheTarget};
});
