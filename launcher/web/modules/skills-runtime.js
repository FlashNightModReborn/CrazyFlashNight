/**
 * Skill panel request mux and write coordinator.
 *
 * This module deliberately knows nothing about AS2 rows or DOM. It owns the
 * browser-side half of the frozen skills v1 envelope, late-response rejection,
 * single-write gate and explicit unknown-write reconciliation handshake.
 */
(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports
        ? require('./panel-runtime.js') : root && root.PanelRuntime;
    var api = factory(shared);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.SkillRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';
    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) throw new Error('PanelRuntime is required');

    var WRITE_COMMANDS = {
        learnCommit: true,
        equip: true,
        unequip: true,
        moveSlot: true,
        setPassive: true,
        reorder: true
    };

    function ownCount(object) {
        return object ? Object.keys(object).length : 0;
    }

    function finiteInt(value, fallback) {
        var number = Number(value);
        return isFinite(number) && Math.floor(number) === number ? number : fallback;
    }

    function nonce(prefix) {
        var value = Date.now().toString(36) + '.' + Math.floor(Math.random() * 0x7fffffff).toString(36);
        return (prefix + '.' + value).replace(/[^A-Za-z0-9._~-]/g, '').slice(0, 80);
    }

    function clonePayload(payload) {
        var result = {};
        payload = payload && typeof payload === 'object' ? payload : {};
        for (var key in payload) {
            if (Object.prototype.hasOwnProperty.call(payload, key)) result[key] = payload[key];
        }
        result.v = 1;
        return result;
    }

    function synthetic(cmd, callId, error, requiresReconcile) {
        return {
            type: 'panel_resp',
            panel: 'skills',
            domain: 'skills',
            cmd: cmd,
            callId: callId,
            success: false,
            error: error,
            requiresReconcile: !!requiresReconcile,
            clientSynthetic: true
        };
    }

    function RequestMux(options) {
        options = options || {};
        this._panelInstanceId = '';
        this._mux = new PanelRuntime.PanelRequestMux({
            send:options.send,
            timeoutMs:Math.max(100, finiteInt(options.timeoutMs, 12000)),
            sessionNonce:String(options.sessionNonce || nonce('skills')).slice(0, 80),
            callPrefix:'skills',
            router:options.router || PanelRuntime.sharedResponseRouter,
            validateSession:function(session) { return !!String(session.panelInstanceId || ''); },
            createMessage:function(context) {
                return {type:'panel', panel:'skills', domain:'skills', cmd:context.entry.cmd,
                    callId:context.entry.callId, panelInstanceId:context.session.panelInstanceId,
                    payload:clonePayload(context.payload)};
            },
            validateResponse:function(data, entry, session) {
                return data && data.type === 'panel_resp' && data.panel === 'skills'
                    && data.domain === 'skills' && data.callId === entry.callId
                    && data.cmd === entry.cmd
                    && String(data.panelInstanceId || '') === session.panelInstanceId;
            },
            transformResponse:function(data, entry, session) {
                if (finiteInt(data.writeEpoch, -1) >= 0 && typeof data.success === 'boolean') return data;
                var malformed = synthetic(entry.cmd, entry.callId, 'malformed_response', entry.kind === 'write');
                malformed.panelInstanceId = session.panelInstanceId;
                return malformed;
            },
            createSynthetic:function(context) {
                var response = synthetic(context.entry.cmd, context.entry.callId,
                    context.error === 'not_sent' ? 'disconnect' : context.error,
                    !!context.entry.write);
                response.panelInstanceId = context.session.panelInstanceId;
                return response;
            }
        });
    }

    RequestMux.prototype.openSession = function(panelInstanceId) {
        this._panelInstanceId = String(panelInstanceId || '');
        return this._mux.openSession({panelInstanceId:this._panelInstanceId});
    };

    RequestMux.prototype.closeSession = function() {
        this._mux.closeSession();
        this._panelInstanceId = '';
    };

    RequestMux.prototype.cancelKind = function(kind) {
        return this._mux.cancelKind(kind);
    };

    RequestMux.prototype.hasKind = function(kind) {
        return this._mux.hasKind(kind);
    };

    RequestMux.prototype.request = function(cmd, payload, options, callback) {
        options = options || {};
        var issued = options.onIssued;
        var wrapped = {
            kind:String(options.kind || cmd),
            latestWins:options.latestWins === true,
            singleFlight:options.latestWins !== true,
            write:options.write === true,
            sendError:'not_sent',
            onIssued:function(entry) {
                entry.panelInstanceId = entry.session.panelInstanceId;
                if (typeof issued === 'function') issued(entry);
            }
        };
        return this._mux.request(cmd, payload, wrapped, function(response, entry) {
            entry.panelInstanceId = entry.session.panelInstanceId;
            if (typeof callback === 'function') callback(response, entry);
        });
    };

    RequestMux.prototype.handleResponse = function(data) {
        return this._mux.handleResponse(data);
    };

    RequestMux.prototype.debugState = function() {
        var state = this._mux.debugState();
        return {
            generation: state.generation,
            sequence: state.sequence,
            issueOrdinal: state.issueOrdinal,
            active: state.active,
            panelInstanceId: this._panelInstanceId,
            pendingCount: state.pendingCount,
            pendingKinds: state.pendingKinds
        };
    };

    RequestMux.prototype.destroy = function() { this._mux.destroy(); };

    function SkillCoordinator(options) {
        options = options || {};
        this._onState = typeof options.onState === 'function' ? options.onState : function() {};
        this._onSnapshot = typeof options.onSnapshot === 'function' ? options.onSnapshot : function() {};
        this._onError = typeof options.onError === 'function' ? options.onError : function() {};
        this._validateSnapshot = typeof options.validateSnapshot === 'function' ? options.validateSnapshot : function() { return true; };
        this._mux = new RequestMux({
            send: options.send,
            timeoutMs: options.timeoutMs,
            sessionNonce: options.sessionNonce
        });
        this._state = 'closed';
        this._panelInstanceId = '';
        this._view = 'manage';
        this._trainerSession = '';
        this._lastAppliedRevision = -1;
        this._lastAppliedWriteEpoch = 0;
        this._previewOrdinal = 0;
        this._activeWrite = null;
        this._activeReconcile = null;
        this._queuedRebind = null;
        this._lastApplyReason = '';
        this._lastValidationError = '';
    }

    SkillCoordinator.prototype._emitState = function(reason) {
        this._onState(this._state, reason || '', this.debugState());
    };

    SkillCoordinator.prototype.open = function(initData) {
        initData = initData || {};
        var instanceId = String(initData.panelInstanceId || '');
        if (!instanceId) return false;
        this.close();
        this._panelInstanceId = instanceId;
        this._view = initData.view === 'trainer' ? 'trainer' : 'manage';
        this._trainerSession = this._view === 'trainer' ? String(initData.trainerSession || '') : '';
        this._lastAppliedRevision = -1;
        this._lastAppliedWriteEpoch = Math.max(0, finiteInt(initData.writeEpoch, 0));
        this._state = initData.writeState === 'needs_reconcile' ? 'needs_reconcile'
            : initData.writeState === 'write_pending' ? 'write_pending' : 'idle';
        if (this._state === 'needs_reconcile' && (initData.reconcileAfterCallId || initData.pendingWriteCallId)) {
            this._activeReconcile = {
                id: String(initData.reconcileId || nonce('reconcile')),
                afterCallId: String(initData.reconcileAfterCallId || initData.pendingWriteCallId)
            };
        }
        this._mux.openSession(instanceId);
        this._emitState('open');
        return true;
    };

    SkillCoordinator.prototype.close = function() {
        this._mux.closeSession();
        this._state = 'closed';
        this._panelInstanceId = '';
        this._trainerSession = '';
        this._activeWrite = null;
        this._activeReconcile = null;
        this._queuedRebind = null;
    };

    SkillCoordinator.prototype.queueRebind = function(initData, apply) {
        if (this._state === 'closed' || this._state === 'idle') {
            apply(initData);
            return 'applied';
        }
        this._queuedRebind = { initData: initData, apply: apply };
        this._emitState('rebind_queued');
        return 'queued';
    };

    SkillCoordinator.prototype._flushRebind = function() {
        if (this._state !== 'idle' || !this._queuedRebind) return false;
        var queued = this._queuedRebind;
        this._queuedRebind = null;
        queued.apply(queued.initData);
        return true;
    };

    SkillCoordinator.prototype._baseSnapshotPayload = function() {
        var payload = { view: this._view };
        if (this._view === 'trainer') payload.trainerSession = this._trainerSession;
        return payload;
    };

    SkillCoordinator.prototype._isLate = function(response, snapshot) {
        var revision = finiteInt(snapshot && snapshot.revision, finiteInt(response && response.revision, -1));
        var writeEpoch = finiteInt(response && response.writeEpoch, -1);
        if (revision >= 0 && revision < this._lastAppliedRevision) return true;
        if (writeEpoch >= 0 && writeEpoch < this._lastAppliedWriteEpoch) return true;
        return false;
    };

    SkillCoordinator.prototype._applySnapshot = function(snapshot, response, source) {
        this._lastApplyReason = '';
        this._lastValidationError = '';
        if (!snapshot || typeof snapshot !== 'object') { this._lastApplyReason = 'invalid'; return false; }
        if (this._isLate(response, snapshot)) { this._lastApplyReason = 'late'; return false; }
        var validation = this._validateSnapshot(snapshot);
        if (validation === false || validation && validation.ok === false) {
            this._lastApplyReason = 'invalid';
            this._lastValidationError = validation && validation.error ? String(validation.error) : '';
            return false;
        }
        var revision = finiteInt(snapshot.revision, finiteInt(response && response.revision, -1));
        var writeEpoch = finiteInt(response && response.writeEpoch, -1);
        if (revision >= 0) this._lastAppliedRevision = Math.max(this._lastAppliedRevision, revision);
        if (writeEpoch >= 0) this._lastAppliedWriteEpoch = Math.max(this._lastAppliedWriteEpoch, writeEpoch);
        this._onSnapshot(snapshot, source || 'snapshot', response || {});
        return true;
    };

    SkillCoordinator.prototype.requestSnapshot = function(callback) {
        if (this._state !== 'idle') return null;
        var self = this;
        return this._mux.request('snapshot', this._baseSnapshotPayload(), {kind:'snapshot'}, function(response) {
            var accepted = false;
            if (response.success === true) accepted = self._applySnapshot(response, response, 'snapshot');
            else self._onError(response, 'snapshot');
            if (!accepted && response.success === true && self._lastApplyReason === 'invalid') {
                var malformed = synthetic('snapshot', response.callId, 'malformed_response', false);
                malformed.validationError = self._lastValidationError;
                self._onError(malformed, 'snapshot');
            }
            if (callback) callback(response, accepted);
        });
    };

    SkillCoordinator.prototype.requestPreview = function(payload, callback) {
        if (this._state !== 'idle' || this._view !== 'trainer') return null;
        var self = this;
        var ordinal = ++this._previewOrdinal;
        return this._mux.request('learnPreview', payload, {kind:'preview', latestWins:true}, function(response) {
            if (ordinal !== self._previewOrdinal) return;
            if (self._isLate(response, response)) return;
            if (response.success !== true) self._onError(response, 'preview');
            if (callback) callback(response);
        });
    };

    SkillCoordinator.prototype.write = function(cmd, payload, callback) {
        if (!WRITE_COMMANDS[cmd] || this._state !== 'idle' || this._activeWrite) return null;
        var self = this;
        this._state = 'write_pending';
        this._emitState('write_start');
        var callId = this._mux.request(cmd, payload, {
            kind:'write',
            write:true,
            onIssued:function(entry) { self._activeWrite = { callId: entry.callId, cmd: cmd }; }
        }, function(response, entry) {
            var active = self._activeWrite;
            if (!active || active.callId !== entry.callId) return;
            self._activeWrite = null;
            if (response.success === true && response.snapshot && typeof response.snapshot === 'object') {
                if (self._applySnapshot(response.snapshot, response, 'write')) {
                    self._state = 'idle';
                    self._emitState('write_success');
                    if (callback) callback(response);
                    self._flushRebind();
                    return;
                }
                response = synthetic(cmd, entry.callId, 'malformed_response', true);
                response.panelInstanceId = self._panelInstanceId;
                response.validationError = self._lastValidationError;
            }
            if (response.success === true) {
                response = synthetic(cmd, entry.callId, 'malformed_response', true);
                response.panelInstanceId = self._panelInstanceId;
            }
            if (response.requiresReconcile === true || response.clientSynthetic === true) {
                self._onError(response, 'write_unknown');
                if (callback) callback(response);
                self._enterNeedsReconcile(entry.callId);
                return;
            }
            var responseEpoch = finiteInt(response.writeEpoch, -1);
            if (responseEpoch >= 0) self._lastAppliedWriteEpoch = Math.max(self._lastAppliedWriteEpoch, responseEpoch);
            var responseRevision = finiteInt(response.revision, -1);
            if (responseRevision >= 0) self._lastAppliedRevision = Math.max(self._lastAppliedRevision, responseRevision);
            self._state = 'idle';
            self._onError(response, 'write_rejected');
            self._emitState('write_rejected');
            if (callback) callback(response);
            self._flushRebind();
        });
        if (!callId) {
            this._state = 'idle';
            this._emitState('write_not_sent');
            return null;
        }
        return callId;
    };

    SkillCoordinator.prototype._enterNeedsReconcile = function(originalCallId) {
        this._state = 'needs_reconcile';
        this._activeReconcile = {
            id: nonce('reconcile'),
            afterCallId: String(originalCallId || '')
        };
        this._emitState('write_unknown');
        this.retryReconcile();
    };

    SkillCoordinator.prototype.retryReconcile = function(callback) {
        if (this._state !== 'needs_reconcile' || !this._activeReconcile) return null;
        var self = this;
        var reconcile = this._activeReconcile;
        var payload = this._baseSnapshotPayload();
        payload.reconcileId = reconcile.id;
        payload.reconcileAfterCallId = reconcile.afterCallId;
        return this._mux.request('snapshot', payload, {kind:'reconcile'}, function(response) {
            var matches = response.success === true && response.reconciled === true
                && String(response.reconcileId || '') === reconcile.id
                && String(response.panelInstanceId || '') === self._panelInstanceId;
            if (!matches || !self._applySnapshot(response, response, 'reconcile')) {
                self._onError(response, 'reconcile');
                if (callback) callback(response, false);
                return;
            }
            self._activeReconcile = null;
            self._state = 'idle';
            self._emitState('reconciled');
            if (callback) callback(response, true);
            self._flushRebind();
        });
    };

    SkillCoordinator.prototype.handleResponse = function(data) {
        return this._mux.handleResponse(data);
    };

    SkillCoordinator.prototype.isWriteBlocked = function() {
        return this._state !== 'idle';
    };

    SkillCoordinator.prototype.getState = function() { return this._state; };
    SkillCoordinator.prototype.getPanelInstanceId = function() { return this._panelInstanceId; };
    SkillCoordinator.prototype.getRevision = function() { return this._lastAppliedRevision; };
    SkillCoordinator.prototype.debugState = function() {
        return {
            state: this._state,
            panelInstanceId: this._panelInstanceId,
            view: this._view,
            trainerSession: this._trainerSession,
            lastAppliedRevision: this._lastAppliedRevision,
            lastAppliedWriteEpoch: this._lastAppliedWriteEpoch,
            activeWrite: this._activeWrite,
            activeReconcile: this._activeReconcile,
            queuedRebind: !!this._queuedRebind,
            mux: this._mux.debugState()
        };
    };

    return {
        RequestMux: RequestMux,
        SkillCoordinator: SkillCoordinator,
        WRITE_COMMANDS: WRITE_COMMANDS
    };
});
