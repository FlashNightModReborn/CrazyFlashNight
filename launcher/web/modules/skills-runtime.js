/**
 * Skill panel request mux and write coordinator.
 *
 * This module deliberately knows nothing about AS2 rows or DOM. It owns the
 * browser-side half of the frozen skills v1 envelope, late-response rejection,
 * single-write gate and explicit unknown-write reconciliation handshake.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.SkillRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var WRITE_COMMANDS = {
        learnCommit: true,
        equip: true,
        unequip: true,
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
        this._send = typeof options.send === 'function' ? options.send : function() {};
        this._timeoutMs = Math.max(100, finiteInt(options.timeoutMs, 12000));
        this._nonce = String(options.sessionNonce || nonce('skills')).slice(0, 80);
        this._generation = 0;
        this._sequence = 0;
        this._issueOrdinal = 0;
        this._panelInstanceId = '';
        this._active = false;
        this._pending = {};
        this._pendingByKind = {};
    }

    RequestMux.prototype.openSession = function(panelInstanceId) {
        this.closeSession();
        this._generation += 1;
        this._panelInstanceId = String(panelInstanceId || '');
        this._active = !!this._panelInstanceId;
        return this._active;
    };

    RequestMux.prototype._dropEntry = function(entry, notifyError) {
        if (!entry) return;
        clearTimeout(entry.timer);
        delete this._pending[entry.callId];
        if (this._pendingByKind[entry.kind] === entry.callId) delete this._pendingByKind[entry.kind];
        if (notifyError && typeof entry.callback === 'function') {
            entry.callback(synthetic(entry.cmd, entry.callId, notifyError, false), entry);
        }
    };

    RequestMux.prototype.closeSession = function() {
        var entries = [];
        for (var key in this._pending) entries.push(this._pending[key]);
        for (var i = 0; i < entries.length; i++) this._dropEntry(entries[i], null);
        this._pending = {};
        this._pendingByKind = {};
        this._active = false;
        this._panelInstanceId = '';
    };

    RequestMux.prototype.cancelKind = function(kind) {
        var callId = this._pendingByKind[kind];
        if (!callId) return false;
        this._dropEntry(this._pending[callId], null);
        return true;
    };

    RequestMux.prototype.hasKind = function(kind) {
        return !!this._pendingByKind[kind];
    };

    RequestMux.prototype.request = function(cmd, payload, options, callback) {
        options = options || {};
        if (!this._active || !cmd) return null;
        var kind = String(options.kind || cmd);
        if (options.latestWins) this.cancelKind(kind);
        else if (this._pendingByKind[kind]) return null;

        var callId = 'skills.' + this._nonce + '.' + this._generation + '.' + (++this._sequence);
        var entry = {
            callId: callId,
            cmd: String(cmd),
            kind: kind,
            generation: this._generation,
            panelInstanceId: this._panelInstanceId,
            issueOrdinal: ++this._issueOrdinal,
            callback: typeof callback === 'function' ? callback : function() {},
            timer: null
        };
        var message = {
            type: 'panel',
            panel: 'skills',
            domain: 'skills',
            cmd: entry.cmd,
            callId: callId,
            panelInstanceId: entry.panelInstanceId,
            payload: clonePayload(payload)
        };
        var self = this;
        entry.timer = setTimeout(function() {
            if (self._pending[callId] !== entry) return;
            self._dropEntry(entry, null);
            entry.callback(synthetic(entry.cmd, callId, 'client_timeout', !!options.write), entry);
        }, this._timeoutMs);
        this._pending[callId] = entry;
        this._pendingByKind[kind] = callId;
        if (typeof options.onIssued === 'function') options.onIssued(entry);
        try {
            var sent = this._send(message);
            if (sent === false) throw new Error('send returned false');
        } catch (error) {
            this._dropEntry(entry, null);
            entry.callback(synthetic(entry.cmd, callId, 'disconnect', !!options.write), entry);
        }
        return callId;
    };

    RequestMux.prototype.handleResponse = function(data) {
        if (!data || data.type !== 'panel_resp' || data.panel !== 'skills'
                || data.domain !== 'skills' || !data.callId) return false;
        var entry = this._pending[data.callId];
        if (!entry || !this._active || entry.generation !== this._generation
                || entry.panelInstanceId !== this._panelInstanceId || data.cmd !== entry.cmd) return false;
        if (String(data.panelInstanceId || '') !== entry.panelInstanceId) return false;
        if (finiteInt(data.writeEpoch, -1) < 0 || typeof data.success !== 'boolean') {
            this._dropEntry(entry, null);
            var malformed = synthetic(entry.cmd, entry.callId, 'malformed_response', entry.kind === 'write');
            malformed.panelInstanceId = entry.panelInstanceId;
            entry.callback(malformed, entry);
            return true;
        }
        this._dropEntry(entry, null);
        entry.callback(data, entry);
        return true;
    };

    RequestMux.prototype.debugState = function() {
        return {
            generation: this._generation,
            sequence: this._sequence,
            issueOrdinal: this._issueOrdinal,
            active: this._active,
            panelInstanceId: this._panelInstanceId,
            pendingCount: ownCount(this._pending),
            pendingKinds: Object.keys(this._pendingByKind)
        };
    };

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
