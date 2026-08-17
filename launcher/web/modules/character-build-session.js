/** Character-build loadout session: bounded authority, writes and close reconcile.
 * The injected request mux keeps this module independent of Bridge, Panels and DOM. */
(function(root, factory) {
    'use strict';
    var mutation = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-mutation.js')
        : root && root.CharacterBuildMutation;
    var contract = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-session-contract.js')
        : root && root.CharacterBuildSessionContract;
    var api = factory(mutation, contract);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildSession = api;
        root.CharacterBuildSession = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function(Mutation, Contract) {
    'use strict';

    if (!Mutation) throw new Error('CharacterBuildMutation is required');
    if (!Contract || !Contract.validators) throw new Error('CharacterBuildSessionContract is required');
    var COMMANDS = Contract.commands.slice(), noop = Contract.noop,
        integer = Contract.integer, positive = Contract.positive, token = Contract.token, copy = Contract.copy;
    var targetKey = Contract.targetKey, candidateScope = Contract.candidateScope, validators = Contract.validators;
    var validProjection = validators.projection, validCandidates = validators.candidates,
        validTooltip = validators.tooltip, validStats = validators.stats,
        definitiveOpenFailure = Contract.definitiveOpenFailure;

    function CharacterBuildSession(options) {
        options = options || {};
        if (!options.mux || typeof options.mux.request !== 'function'
                || typeof options.mux.openSession !== 'function') {
            throw new Error('CharacterBuildSession requires an injected PanelRequestMux port');
        }
        this._mux = options.mux;
        this._onState = typeof options.onState === 'function' ? options.onState : noop;
        this._onError = typeof options.onError === 'function' ? options.onError : noop;
        this._onCandidateAuthorityReset =
            typeof options.onCandidateAuthorityReset === 'function'
                ? options.onCandidateAuthorityReset : noop;
        this._state = 'closed';
        this._candidateScope = 'compatible';
        this._panelInstanceId = '';
        this._sessionGeneration = null;
        this._writeEpoch = 0;
        this._loadoutRevision = 0;
        this._liveRevision = 0;
        this._drugRevision = 0;
        this._liveRefreshDirty = false;
        this._snapshot = null;
        this._unknown = null;
        this._openingCallId = '';
        this._openingAttempts = 0;
        this._reconcileCallId = '';
        this._reconcileIntent = null;
        this._loadoutTooltipPending = null;
        this._destroyed = false;
    }
    CharacterBuildSession.prototype._emit = function(reason) {
        this._onState(this._state, reason || '', this.debugState());
    };

    CharacterBuildSession.prototype._basePayload = function() { return {v:1, sessionGeneration:this._sessionGeneration}; };

    CharacterBuildSession.prototype._commonValid = function(response, entry, allowClosed) {
        if (!response || response.v !== 1 || typeof response.success !== 'boolean'
                || String(response.callId || '') !== entry.callId
                || String(response.cmd || '') !== entry.cmd
                || String(response.panelInstanceId || '') !== this._panelInstanceId
                || integer(response.writeEpoch, -1) < this._writeEpoch
                || positive(response.sessionGeneration) === null
                || integer(response.loadoutRevision, -1) < 0
                || integer(response.liveRevision, -1) < 0
                || integer(response.drugRevision, -1) < 0
                || typeof response.liveRefreshDirty !== 'boolean'
                || typeof response.active !== 'boolean') return false;
        if (!allowClosed && response.active !== true) return false;
        if (Number(response.liveRevision) > Number(response.loadoutRevision)) return false;
        if (response.liveRefreshDirty
                !== (Number(response.loadoutRevision) !== Number(response.liveRevision))) return false;
        if (this._sessionGeneration !== null
                && Number(response.sessionGeneration) !== this._sessionGeneration) return false;
        return true;
    };

    CharacterBuildSession.prototype._applyCommon = function(response) {
        var loadout = Number(response.loadoutRevision);
        var live = Number(response.liveRevision);
        var drug = Number(response.drugRevision);
        var epoch = Number(response.writeEpoch);
        if (epoch < this._writeEpoch || loadout < this._loadoutRevision
                || live < this._liveRevision || drug < this._drugRevision) return false;
        this._sessionGeneration = Number(response.sessionGeneration);
        this._writeEpoch = epoch;
        this._loadoutRevision = loadout;
        this._liveRevision = live;
        this._drugRevision = drug;
        this._liveRefreshDirty = response.liveRefreshDirty === true;
        return true;
    };

    CharacterBuildSession.prototype._malformed = function(response, entry, write) {
        var failure = {
            success:false,
            error:'malformed_response',
            callId:entry && entry.callId || '',
            requiresReconcile:!!write,
            reconcileAfterCallId:write && entry ? entry.callId : ''
        };
        this._onError(failure, entry && entry.cmd || 'response');
        return failure;
    };

    CharacterBuildSession.prototype._requestInitialSnapshot = function(callback, autoRetry) {
        if (this._state !== 'opening' && this._state !== 'opening_reconcile') return null;
        var self = this;
        this._openingAttempts++;
        var callId = this._mux.request('snapshot', {v:1}, {
            kind:'snapshot',
            singleFlight:true,
            metadata:{initial:true, attempt:this._openingAttempts},
            onIssued:function(entry) { self._openingCallId = entry.callId; }
        }, function(response, entry) {
            if (self._openingCallId !== entry.callId
                    || (self._state !== 'opening' && self._state !== 'opening_reconcile')) return;
            self._openingCallId = '';
            var accepted = self._commonValid(response, entry, false)
                && response.success === true && validProjection(response.payload);
            if (accepted) accepted = self._applyCommon(response);
            if (accepted) {
                self._snapshot = response.payload;
                self._state = 'idle';
                self._emit('opened');
                if (callback) callback(response, true);
                return;
            }
            var definitelyNotOpened = definitiveOpenFailure(response);
            if (definitelyNotOpened) {
                self._state = 'closed';
                self._panelInstanceId = '';
                self._mux.closeSession();
                self._onError(response, 'snapshot');
                self._emit('open_failed');
                if (callback) callback(response, false);
                return;
            }
            self._state = 'opening_reconcile';
            if (response && response.success === true) self._malformed(response, entry, false);
            else self._onError(response, 'snapshot_unknown');
            self._emit('open_unknown');
            if (autoRetry) {
                self._requestInitialSnapshot(callback, false);
            } else if (callback) {
                callback(response, false);
            }
        });
        if (this._state === 'opening' || this._state === 'opening_reconcile') {
            this._openingCallId = callId || '';
        }
        if (!callId) {
            this._state = 'opening_reconcile';
            this._emit('open_retry_not_issued');
            if (callback) callback({success:false, error:'not_issued'}, false);
        }
        return this._state === 'closed' ? null : callId;
    };

    CharacterBuildSession.prototype.open = function(panelInstanceId, callback) {
        if (this._destroyed || !token(panelInstanceId)) return null;
        if (this._state !== 'closed') {
            if (this._panelInstanceId === String(panelInstanceId)
                    && this._state === 'opening_reconcile') {
                return this.recoverOpen(callback);
            }
            return null;
        }
        this._panelInstanceId = String(panelInstanceId);
        if (!this._mux.openSession({panelInstanceId:this._panelInstanceId})) return null;
        this._state = 'opening';
        this._openingAttempts = 0;
        this._emit('open');
        return this._requestInitialSnapshot(callback, true);
    };

    CharacterBuildSession.prototype.recoverOpen = function(callback) {
        if (this._state !== 'opening_reconcile' || this._openingCallId) return null;
        return this._requestInitialSnapshot(callback, false);
    };

    CharacterBuildSession.prototype.refreshSnapshot = function(options, callback) {
        if (typeof options === 'function') { callback = options; options = {}; }
        options = options || {};
        var ordinaryRefresh = !options.reconcile
            && (this._state === 'idle' || this._state === 'flush_failed');
        if (!ordinaryRefresh
                && !(this._state === 'needs_reconcile' && options.reconcile)) return null;
        this._cancelLoadoutTooltip('snapshot_refresh');
        var payload = this._basePayload();
        var watermark = token(options.reconcileAfterCallId);
        if (watermark) payload.reconcileAfterCallId = watermark;
        this._onCandidateAuthorityReset('snapshot');
        var self = this;
        return this._mux.request('snapshot', payload, {
            kind:options.reconcile ? 'reconcile' : 'snapshot',
            latestWins:!options.reconcile,
            singleFlight:!!options.reconcile,
            metadata:{watermark:watermark}
        }, function(response, entry) {
            var mutationReconcile = options.reconcile && self._unknown
                && self._unknown.kind === 'mutation';
            var accepted = self._commonValid(response, entry, false)
                && response.success === true && validProjection(response.payload);
            if (accepted && mutationReconcile) {
                accepted = self._unknown.callId === watermark
                    && token(response.reconcileAfterCallId) === watermark
                    && Mutation.validFullBackpackSnapshots(response.inventorySnapshots);
            } else if (accepted && options.reconcile) {
                accepted = !!self._unknown && self._unknown.kind === 'flushLive'
                    && self._unknown.callId === watermark && !response.liveRefreshDirty
                    && Number(response.loadoutRevision) === Number(response.liveRevision);
            }
            if (accepted) accepted = self._applyCommon(response);
            if (accepted) {
                self._snapshot = response.payload;
                self._unknown = null;
                self._state = 'idle';
                self._emit(mutationReconcile ? 'mutation_reconciled'
                    : options.reconcile ? 'flush_reconciled' : 'snapshot');
            } else if (response && response.success === true) {
                self._malformed(response, entry, mutationReconcile);
                if (mutationReconcile) self._emit('mutation_reconcile_failed');
            } else {
                self._onError(response, options.reconcile ? 'reconcile' : 'snapshot');
            }
            if (callback) callback(response, accepted);
        });
    };

    CharacterBuildSession.prototype.requestCandidates = function(target, scope, callback) {
        if (typeof scope === 'function') {
            callback = scope;
            scope = this._candidateScope;
        }
        scope = candidateScope(scope || this._candidateScope);
        if (this._state !== 'idle' || !targetKey(target) || !scope) return null;
        var payload = this._basePayload();
        if (target.kind === 'equipment') payload.slotKey = target.slotKey;
        else if (target.kind === 'drug') payload.drugSlot = integer(target.drugSlot, -1);
        payload.candidateScope = scope;
        payload.expectedLoadoutRevision = this._loadoutRevision;
        payload.expectedDrugRevision = this._drugRevision;
        this._onCandidateAuthorityReset('candidates');
        var self = this;
        return this._mux.request('candidates', payload, {
            kind:'candidates',
            latestWins:true,
            metadata:{target:copy(target), targetKey:targetKey(target), candidateScope:scope}
        }, function(response, entry) {
            var accepted = self._state === 'idle'
                && self._commonValid(response, entry, false)
                && response.success === true
                && validCandidates(
                    response.payload,
                    entry.metadata.target,
                    entry.metadata.candidateScope)
                && self._applyCommon(response);
            if (!accepted) {
                if (response && response.success === true) self._malformed(response, entry, false);
                else self._onError(response, 'candidates');
            }
            if (callback) callback(
                response,
                accepted,
                entry.metadata.targetKey,
                entry.metadata.candidateScope);
        });
    };

    CharacterBuildSession.prototype.requestLoadoutTooltip = function(target, callback) {
        var key = targetKey(target);
        if (this._state !== 'idle' || !key) return null;
        this._cancelLoadoutTooltip('superseded');
        var payload = this._basePayload();
        if (target.kind === 'equipment') payload.slotKey = target.slotKey;
        else if (target.kind === 'drug') payload.drugSlot = integer(target.drugSlot, -1);
        payload.expectedLoadoutRevision = this._loadoutRevision;
        payload.expectedDrugRevision = this._drugRevision;
        var self = this;
        var expectedLoadoutRevision = this._loadoutRevision;
        var expectedDrugRevision = this._drugRevision;
        return this._mux.request('tooltip', payload, {
            kind:'loadout-tooltip',
            singleFlight:true,
            metadata:{
                target:copy(target),
                targetKey:key,
                loadoutRevision:expectedLoadoutRevision,
                drugRevision:expectedDrugRevision
            },
            onIssued:function(entry) {
                self._loadoutTooltipPending = {
                    callId:entry.callId,
                    callback:callback,
                    targetKey:key
                };
            }
        }, function(response, entry) {
            if (!self._loadoutTooltipPending
                    || self._loadoutTooltipPending.callId !== entry.callId) return;
            self._loadoutTooltipPending = null;
            var accepted = self._state === 'idle'
                && self._commonValid(response, entry, false)
                && response.success === true
                && Number(response.loadoutRevision) === entry.metadata.loadoutRevision
                && Number(response.drugRevision) === entry.metadata.drugRevision
                && self._loadoutRevision === entry.metadata.loadoutRevision
                && self._drugRevision === entry.metadata.drugRevision
                && validTooltip(response.payload, entry.metadata.target);
            if (!accepted) {
                if (response && response.success === true) self._malformed(response, entry, false);
                else self._onError(response, 'tooltip');
            }
            if (callback) callback(response, accepted, entry.metadata.targetKey);
        });
    };

    CharacterBuildSession.prototype._cancelLoadoutTooltip = function(reason) {
        var pending = this._loadoutTooltipPending;
        this._loadoutTooltipPending = null;
        var canceled = this._mux.cancelKind('loadout-tooltip');
        if (pending && typeof pending.callback === 'function') {
            pending.callback({
                success:false,
                error:String(reason || 'canceled'),
                clientSynthetic:true
            }, false, pending.targetKey);
        }
        return canceled || !!pending;
    };

    CharacterBuildSession.prototype.setCandidateScope = function(scope) {
        scope = candidateScope(scope);
        if (!scope) return false;
        this._candidateScope = scope;
        return true;
    };

    CharacterBuildSession.prototype.getCandidateScope = function() {
        return this._candidateScope;
    };

    CharacterBuildSession.prototype._requestMutation = function(intent, callback) {
        if (this._state !== 'idle') return null;
        var payload = Mutation.buildPayload(intent, {
            sessionGeneration:this._sessionGeneration,
            loadoutRevision:this._loadoutRevision,
            drugRevision:this._drugRevision
        });
        if (!payload) return null;
        this._cancelLoadoutTooltip('mutation_start');
        this._state = 'write_pending';
        this._emit('mutation_start');
        var self = this;
        return this._mux.request(intent.cmd, payload, {
            kind:'mutation',
            singleFlight:true,
            write:true,
            metadata:{sourceSlot:payload.source ? payload.source.slot : null}
        }, function(response, entry) {
            var accepted = self._commonValid(response, entry, false)
                && response.success === true
                && Mutation.validMutationResult(
                    response, entry.cmd, validProjection, entry.metadata.sourceSlot)
                && self._applyCommon(response);
            if (accepted) {
                self._snapshot = response.payload;
                self._unknown = null;
                self._state = 'idle';
                self._emit('mutation_success');
                if (callback) callback(response, true, false);
                return;
            }
            var unknown = response && (response.success === true
                || (response.requiresReconcile === true
                    && token(response.reconcileAfterCallId) === entry.callId));
            if (unknown) {
                self._state = 'needs_reconcile';
                self._unknown = {kind:'mutation', callId:entry.callId, command:entry.cmd};
                if (response.success === true) self._malformed(response, entry, true);
                self._emit('mutation_unknown');
            } else {
                self._state = 'idle';
                self._onError(response, entry.cmd);
                self._emit('mutation_failed');
            }
            if (callback) callback(response, false, !!unknown);
        });
    };

    CharacterBuildSession.prototype.equipEquipment = function(slotKey, source, callback) {
        return this._requestMutation(
            {cmd:'equipEquipment', slotKey:slotKey, source:source}, callback);
    };
    CharacterBuildSession.prototype.unequipEquipment = function(slotKey, callback) {
        return this._requestMutation({cmd:'unequipEquipment', slotKey:slotKey}, callback);
    };
    CharacterBuildSession.prototype.equipDrug = function(drugSlot, source, callback) {
        return this._requestMutation(
            {cmd:'equipDrug', drugSlot:drugSlot, source:source}, callback);
    };
    CharacterBuildSession.prototype.unequipDrug = function(drugSlot, callback) {
        return this._requestMutation({cmd:'unequipDrug', drugSlot:drugSlot}, callback);
    };
    CharacterBuildSession.prototype.reconcileMutation = function(callback) {
        if (this._state !== 'needs_reconcile' || !this._unknown
                || this._unknown.kind !== 'mutation') return null;
        return this.refreshSnapshot({
            reconcile:true,
            reconcileAfterCallId:this._unknown.callId
        }, function(response, accepted) {
            if (callback) callback(response, accepted, !accepted);
        });
    };

    CharacterBuildSession.prototype._recoverUnknownFlush = function(kind, callback) {
        if (this._state !== 'needs_reconcile' || !this._unknown
                || this._unknown.kind !== 'flushLive') return null;
        var priority = kind === 'finalize' ? 2 : kind === 'leave' ? 1 : 0;
        if (!this._reconcileIntent || priority >= this._reconcileIntent.priority) {
            this._reconcileIntent = {priority:priority, callback:callback};
        }
        if (this._reconcileCallId) return this._reconcileCallId;
        var self = this, completed = false, watermark = this._unknown.callId;
        var callId = this.refreshSnapshot({
            reconcile:true,
            reconcileAfterCallId:watermark
        }, function(response, reconciled) {
            completed = true;
            self._reconcileCallId = '';
            var intent = self._reconcileIntent;
            self._reconcileIntent = null;
            if (intent && typeof intent.callback === 'function') {
                intent.callback(response, reconciled);
            }
        });
        if (!completed) this._reconcileCallId = callId || '';
        if (!callId && !completed) {
            var intent = this._reconcileIntent;
            this._reconcileIntent = null;
            if (intent && typeof intent.callback === 'function') {
                intent.callback({success:false, error:'reconcile_not_issued'}, false);
            }
        }
        return callId;
    };

    CharacterBuildSession.prototype._requestStats = function(callback) {
        if (this._state !== 'idle') return null;
        var payload = this._basePayload();
        payload.expectedLoadoutRevision = this._loadoutRevision;
        payload.expectedLiveRevision = this._liveRevision;
        var self = this;
        return this._mux.request('statsSnapshot', payload, {
            kind:'stats',
            singleFlight:true
        }, function(response, entry) {
            var accepted = self._commonValid(response, entry, false)
                && response.success === true && validStats(response.payload)
                && !response.liveRefreshDirty
                && Number(response.loadoutRevision) === Number(response.liveRevision)
                && self._applyCommon(response);
            if (!accepted) {
                if (response && response.success === true) self._malformed(response, entry, false);
                else self._onError(response, 'statsSnapshot');
            }
            if (callback) callback(response, accepted);
        });
    };

    CharacterBuildSession.prototype.prepareStats = function(callback) {
        if (this._state !== 'idle') return null;
        if (!this._liveRefreshDirty && this._loadoutRevision === this._liveRevision) {
            return this._requestStats(callback);
        }
        var self = this;
        return this._requestFlush(function(response, accepted, unknown) {
            if (accepted) {
                self._requestStats(callback);
                return;
            }
            if (!unknown) {
                if (callback) callback(response, false);
                return;
            }
            self._recoverUnknownFlush('stats', function(reconcileResponse, reconciled) {
                if (reconciled) self._requestStats(callback);
                else if (callback) callback(reconcileResponse, false);
            });
        });
    };

    CharacterBuildSession.prototype.prepareLeave = function(callback) {
        if (this._state === 'idle' || this._state === 'flush_failed') {
            if (callback) callback(null, true);
            return true;
        }
        return this._recoverUnknownFlush('leave', callback);
    };

    CharacterBuildSession.prototype._requestFlush = function(callback) {
        if (this._state !== 'idle' && this._state !== 'flush_failed') return null;
        this._cancelLoadoutTooltip('flush_start');
        this._state = 'flush_pending';
        this._emit('flush_start');
        var payload = this._basePayload();
        payload.expectedLoadoutRevision = this._loadoutRevision;
        var self = this;
        return this._mux.request('flushLive', payload, {
            kind:'flushLive',
            singleFlight:true,
            write:true
        }, function(response, entry) {
            var common = self._commonValid(response, entry, false);
            var accepted = common && response.success === true
                && typeof response.changed === 'boolean'
                && !response.liveRefreshDirty
                && Number(response.loadoutRevision) === Number(response.liveRevision)
                && self._applyCommon(response);
            if (accepted) {
                self._state = 'idle';
                self._unknown = null;
                self._emit('flush_success');
                if (callback) callback(response, true, false);
                return;
            }
            var unknown = response && response.requiresReconcile === true
                && token(response.reconcileAfterCallId) === entry.callId;
            if (unknown) {
                self._state = 'needs_reconcile';
                self._unknown = {kind:'flushLive', callId:entry.callId};
                self._emit('flush_unknown');
            } else {
                self._state = 'flush_failed';
                self._onError(response, 'flushLive');
                self._emit('flush_failed');
            }
            if (callback) callback(response, false, unknown);
        });
    };

    CharacterBuildSession.prototype.finalize = function(callback) {
        if (this._state === 'opening_reconcile') {
            var self = this;
            return this.recoverOpen(function(response, accepted) {
                if (accepted) self.finalize(callback);
                else if (callback) callback(response, false, true);
            });
        }
        if (this._state === 'needs_reconcile' && this._unknown
                && this._unknown.kind === 'flushLive') {
            var self = this;
            return this._recoverUnknownFlush('finalize', function(response, reconciled) {
                if (reconciled) self.finalize(callback);
                else if (callback) callback(response, false, true);
            });
        }
        var retry = this._state === 'needs_reconcile' && this._unknown
            && this._unknown.kind === 'finalize';
        if (this._state !== 'idle' && this._state !== 'flush_failed' && !retry) return null;
        this._cancelLoadoutTooltip('finalize_start');
        var payload = this._basePayload();
        payload.expectedLoadoutRevision = this._loadoutRevision;
        if (retry) payload.reconcileAfterCallId = this._unknown.callId;
        this._state = 'flush_pending';
        this._emit(retry ? 'finalize_retry' : 'finalize_start');
        var self = this;
        return this._mux.request('finalize', payload, {
            kind:'finalize',
            singleFlight:true,
            write:true,
            metadata:{retry:retry}
        }, function(response, entry) {
            var persistence = response && response.persistence;
            var accepted = self._commonValid(response, entry, true)
                && response.success === true && response.closed === true
                && response.active === false && typeof response.liveChanged === 'boolean'
                && persistence && persistence.success === true
                && typeof persistence.changed === 'boolean'
                && !Object.prototype.hasOwnProperty.call(response, 'persistenceSucceeded')
                && !response.liveRefreshDirty
                && Number(response.loadoutRevision) === Number(response.liveRevision)
                && self._applyCommon(response);
            if (accepted) {
                self._state = 'finalized';
                self._unknown = null;
                self._emit('finalized');
                if (callback) callback(response, true, false);
                return;
            }
            var unknown = response && response.requiresReconcile === true
                && token(response.reconcileAfterCallId) === entry.callId;
            if (unknown) {
                self._state = 'needs_reconcile';
                self._unknown = {kind:'finalize', callId:entry.callId};
                self._emit('finalize_unknown');
            } else {
                self._state = 'flush_failed';
                if (response && response.success === true) self._malformed(response, entry, true);
                else self._onError(response, 'finalize');
                self._emit('finalize_failed');
            }
            if (callback) callback(response, false, unknown);
        });
    };

    CharacterBuildSession.prototype.retryFinalize = function(callback) {
        return this.finalize(callback);
    };

    CharacterBuildSession.prototype.suspendView = function() {
        this._mux.cancelKind('candidates');
        this._cancelLoadoutTooltip('view_suspended');
        this._mux.cancelKind('snapshot');
        this._mux.cancelKind('stats');
        return this._state !== 'closed' && this._state !== 'finalized';
    };

    CharacterBuildSession.prototype.close = function() {
        this._cancelLoadoutTooltip('session_closed');
        if (this._mux && this._mux.closeSession) this._mux.closeSession();
        this._state = 'closed';
        this._panelInstanceId = '';
        this._sessionGeneration = null;
        this._writeEpoch = 0;
        this._loadoutRevision = 0;
        this._liveRevision = 0;
        this._drugRevision = 0;
        this._liveRefreshDirty = false;
        this._snapshot = null;
        this._unknown = null;
        this._openingCallId = '';
        this._openingAttempts = 0;
        this._reconcileCallId = '';
        this._reconcileIntent = null;
        this._loadoutTooltipPending = null;
    };

    CharacterBuildSession.prototype.destroy = function() {
        if (this._destroyed) return false;
        this.close();
        if (this._mux && this._mux.destroy) this._mux.destroy();
        this._destroyed = true;
        return true;
    };

    CharacterBuildSession.prototype.canClose = function() {
        return this._state === 'finalized' && !this._liveRefreshDirty
            && this._loadoutRevision === this._liveRevision;
    };

    CharacterBuildSession.prototype.getSnapshot = function() { return this._snapshot; };
    CharacterBuildSession.prototype.getState = function() { return this._state; };
    CharacterBuildSession.prototype.getSessionGeneration = function() {
        return this._sessionGeneration;
    };
    CharacterBuildSession.prototype.debugState = function() {
        return {
            state:this._state,
            panelInstanceId:this._panelInstanceId,
            sessionGeneration:this._sessionGeneration,
            writeEpoch:this._writeEpoch,
            loadoutRevision:this._loadoutRevision,
            liveRevision:this._liveRevision,
            drugRevision:this._drugRevision,
            candidateScope:this._candidateScope,
            liveRefreshDirty:this._liveRefreshDirty,
            unknown:this._unknown ? {kind:this._unknown.kind, callId:this._unknown.callId} : null,
            openingAttempts:this._openingAttempts,
            hasSnapshot:!!this._snapshot,
            mux:this._mux && this._mux.debugState ? this._mux.debugState() : null
        };
    };

    return {
        CharacterBuildSession:CharacterBuildSession,
        commands:COMMANDS.slice(),
        targetKey:targetKey,
        candidateScope:candidateScope,
        validators:{
            projection:validProjection,
            candidates:validCandidates,
            tooltip:validTooltip,
            stats:validStats
        }
    };
});
