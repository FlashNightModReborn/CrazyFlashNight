/** Exact backpack item-use transport and unknown-write reconciliation. */
(function(root, factory) {
    'use strict';
    var runtime = typeof module !== 'undefined' && module.exports
        ? require('../panel-runtime.js') : root && root.PanelRuntime;
    var cooldown = typeof module !== 'undefined' && module.exports
        ? require('./character-build-cooldown-channel.js')
        : root && root.CharacterBuildCooldownChannel;
    var api = factory(runtime, cooldown);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildItemUse = api;
        root.CharacterBuildItemUse = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime, Cooldown) {
    'use strict';

    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) {
        throw new Error('CharacterBuildItemUse requires PanelRuntime');
    }
    if (!Cooldown || typeof Cooldown.normalize !== 'function') {
        throw new Error('CharacterBuildItemUse requires CharacterBuildCooldownChannel');
    }

    var WRITE_ERRORS = {
        client_timeout:true,
        not_sent:true,
        disconnected:true,
        malformed_response:true,
        reconcile_required:true
    };
    function own(value, key) {
        return !!value && Object.prototype.hasOwnProperty.call(value, key);
    }
    function opaque(value) {
        value = typeof value === 'string' ? value : '';
        return value && value.length <= 128 && /^[A-Za-z0-9._~-]+$/.test(value)
            ? value : '';
    }
    function whole(value, minimum, maximum) {
        value = Number(value);
        return isFinite(value) && Math.floor(value) === value
                && value >= minimum && value <= maximum ? value : null;
    }
    function normalizedAction(candidate) {
        var raw = candidate && candidate.raw || {};
        var value = candidate && candidate.useAction || raw.useAction;
        var command = value && String(value.command || '');
        if (command !== 'open' && command !== 'openMany' && command !== 'consume') return null;
        var action = {
            command:command,
            label:String(value.label || (command === 'open' ? '打开'
                : command === 'openMany' ? '全部打开' : '服用'))
        };
        if (command === 'openMany') {
            // exact count 2..64 随 envelope 下发；1 继续走单包 open
            var count = whole(value.count, 2, 64);
            if (count === null) return null;
            action.count = count;
        }
        return action;
    }
    function exactSource(candidate) {
        var raw = candidate && candidate.raw || {};
        var action = raw.useAction || candidate && candidate.useAction || {};
        var source = action.source || raw.useSource || {};
        var item = raw.item || candidate && candidate.presentation || {};
        var physicalSlot = whole(
            own(raw, 'physicalSlot') ? raw.physicalSlot : candidate && candidate.physicalSlot,
            0, 49);
        var slotLease = opaque(source.slotLease || source.expectedLease);
        var itemName = String(source.itemName || item.name || '');
        var backpackVersion = whole(
            own(source, 'backpackVersion') ? source.backpackVersion
                : own(raw, 'backpackVersion') ? raw.backpackVersion
                    : candidate && candidate.backpackVersion,
            0, 2147483647);
        return physicalSlot === null || !slotLease || !itemName
                || backpackVersion === null ? null : {
            physicalSlot:physicalSlot,
            slotLease:slotLease,
            itemName:itemName,
            backpackVersion:backpackVersion
        };
    }
    function isAmbiguous(response) {
        return !!response && (response.requiresReconcile === true
            || WRITE_ERRORS[String(response.error || '')] === true);
    }

    function createMux(options) {
        options = options || {};
        return new PanelRuntime.PanelRequestMux({
            send:options.send,
            setTimer:options.setTimer,
            clearTimer:options.clearTimer,
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce,
            callPrefix:'item-use',
            router:options.router || PanelRuntime.sharedResponseRouter,
            validateSession:function(session) {
                return !!opaque(session.panelInstanceId)
                    && whole(session.sessionGeneration, 1, 2147483647) !== null;
            },
            createMessage:function(context) {
                return {
                    type:'panel',
                    panel:'workbench',
                    domain:'item_use',
                    cmd:context.entry.cmd,
                    callId:context.entry.callId,
                    panelInstanceId:context.session.panelInstanceId,
                    payload:context.payload
                };
            },
            validateResponse:function(data, entry, session) {
                return !!data && data.type === 'panel_resp'
                    && data.panel === 'workbench' && data.domain === 'item_use'
                    && data.cmd === entry.cmd && data.callId === entry.callId
                    && data.panelInstanceId === session.panelInstanceId
                    && typeof data.success === 'boolean';
            },
            createSynthetic:function(context) {
                return {
                    type:'panel_resp', panel:'workbench', domain:'item_use',
                    cmd:context.entry.cmd, callId:context.entry.callId,
                    panelInstanceId:context.session.panelInstanceId,
                    success:false, error:context.error, clientSynthetic:true,
                    requiresReconcile:context.entry.write === true
                };
            }
        });
    }

    function Controller(options) {
        options = options || {};
        this._mux = options.mux || createMux(options);
        this._onState = typeof options.onState === 'function'
            ? options.onState : function() {};
        this._onSettled = typeof options.onSettled === 'function'
            ? options.onSettled : function() {};
        this._onInbox = typeof options.onInbox === 'function'
            ? options.onInbox : function() {};
        this._onCooldown = typeof options.onCooldown === 'function'
            ? options.onCooldown : function() {};
        this._cooldownLanes = null;
        this._state = 'closed';
        this._panelInstanceId = '';
        this._sessionGeneration = null;
        this._operationSequence = 0;
        this._operationNonce = opaque(options.operationNonce)
            || PanelRuntime.makeNonce('itemuse');
        this._pending = null;
        this._inbox = null;
        this._destroyed = false;
    }
    Controller.prototype._emit = function(reason) {
        this._onState(this._state, reason || '', this.debugState());
    };
    Controller.prototype.bind = function(panelInstanceId, sessionGeneration) {
        panelInstanceId = opaque(panelInstanceId);
        sessionGeneration = whole(sessionGeneration, 1, 2147483647);
        if (this._destroyed || !panelInstanceId || sessionGeneration === null) return false;
        if (this._panelInstanceId === panelInstanceId
                && this._sessionGeneration === sessionGeneration
                && this._state !== 'closed') return true;
        this._mux.closeSession();
        this._panelInstanceId = panelInstanceId;
        this._sessionGeneration = sessionGeneration;
        this._pending = null;
        this._inbox = null;
        this._cooldownLanes = null;
        if (!this._mux.openSession({
            panelInstanceId:panelInstanceId,
            sessionGeneration:sessionGeneration
        })) return false;
        this._state = 'idle';
        this._emit('bound');
        return true;
    };
    Controller.prototype._base = function() {
        return {
            v:1,
            panelInstanceId:this._panelInstanceId,
            sessionGeneration:this._sessionGeneration
        };
    };
    Controller.prototype._acceptInbox = function(response) {
        var hasAuthority = response && Object.prototype.hasOwnProperty.call(
            response, 'rewardAuthority');
        var authority = hasAuthority ? response.rewardAuthority : undefined;
        var accepted = response && response.success === true
            && response.inboxSummary
            && typeof response.rewardReady === 'boolean'
            && hasAuthority
            && (authority === null || authority && typeof authority === 'object'
                && !Array.isArray(authority));
        if (!accepted || response.rewardReady === false && authority !== null) {
            return false;
        }
        this._inbox = {
            summary:response.inboxSummary,
            authority:authority || null
        };
        this._onInbox(this._inbox, response);
        return true;
    };
    Controller.prototype.refreshInbox = function(callback) {
        if (this._destroyed || this._state === 'closed') return null;
        var self = this;
        return this._mux.request('inboxSnapshot', this._base(), {
            kind:'inbox_snapshot', latestWins:true
        }, function(response) {
            var accepted = self._acceptInbox(response);
            if (callback) callback(response, !!accepted);
        });
    };
    Controller.prototype.refreshCooldowns = function(callback) {
        if (this._destroyed || this._state === 'closed') return null;
        var self = this;
        return this._mux.request('cooldownSnapshot', this._base(), {
            kind:'cooldown_snapshot', latestWins:true
        }, function(response) {
            var lanes = response && response.success === true
                ? Cooldown.normalize(response.cooldownLanes) : null;
            var accepted = lanes !== null;
            if (accepted) {
                self._cooldownLanes = lanes;
                self._onCooldown(lanes, response);
            }
            if (callback) callback(response, accepted, lanes);
        });
    };
    Controller.prototype.invoke = function(candidate) {
        if (this._destroyed) return null;
        if (this._state === 'needs_reconcile') return this.reconcile();
        if (this._state !== 'idle') return null;
        var action = normalizedAction(candidate);
        var source = exactSource(candidate);
        if (!action || !source) {
            this._onSettled({success:false, error:'invalid_source'}, false, null);
            return null;
        }
        var operationId = 'itemuse.' + this._operationNonce + '.'
            + (++this._operationSequence).toString(36);
        // An open write may replace the exact Loot authority. Do not let an
        // unknown result reuse an authority cached before this operation.
        if (action.command === 'open' || action.command === 'openMany') this._inbox = null;
        var payload = this._base();
        payload.operationId = operationId;
        payload.source = source;
        if (action.count != null) payload.count = action.count;
        this._pending = {
            operationId:operationId,
            command:action.command,
            candidate:candidate
        };
        this._state = 'write_pending';
        this._emit('write_issued');
        var self = this;
        var callId = this._mux.request(action.command, payload, {
            kind:'write', singleFlight:true, write:true
        }, function(response) { self._settleWrite(response); });
        return callId;
    };
    Controller.prototype._settleWrite = function(response) {
        var pending = this._pending;
        if (!pending) return;
        if (isAmbiguous(response)) {
            this._state = 'needs_reconcile';
            this._emit('write_unknown');
            this.reconcile();
            return;
        }
        this._pending = null;
        this._state = 'idle';
        if ((pending.command === 'open' || pending.command === 'openMany')
                && response && response.success === true) {
            this._acceptInbox(response);
        }
        this._emit(response && response.success === true
            ? 'write_committed' : 'write_rejected');
        this._onSettled(response || {success:false, error:'malformed_response'},
            !!(response && response.success === true), pending);
    };
    Controller.prototype.reconcile = function() {
        if (this._destroyed || this._state !== 'needs_reconcile' || !this._pending) return null;
        var pending = this._pending;
        var payload = this._base();
        payload.operationId = pending.operationId;
        this._state = 'query_pending';
        this._emit('query_issued');
        var self = this;
        return this._mux.request('query', payload, {
            kind:'query', singleFlight:true
        }, function(response) {
            if (!self._pending || self._pending.operationId !== pending.operationId) return;
            if (!response || response.success !== true || typeof response.found !== 'boolean') {
                self._state = 'needs_reconcile';
                self._emit('query_failed');
                return;
            }
            self._pending = null;
            self._state = 'idle';
            self._emit(response.found ? 'query_committed' : 'query_not_committed');
            var settled = response;
            if (response.found !== true) {
                settled = {
                    success:false,
                    error:'not_committed',
                    found:false,
                    inboxSummary:response.inboxSummary
                };
            }
            self._onSettled(settled, response.found === true, pending);
        });
    };
    Controller.prototype.inbox = function() { return this._inbox; };
    Controller.prototype.cooldownLanes = function() { return this._cooldownLanes; };
    Controller.prototype.close = function() {
        if (this._destroyed) return false;
        this._mux.closeSession();
        this._panelInstanceId = '';
        this._sessionGeneration = null;
        this._pending = null;
        this._inbox = null;
        this._cooldownLanes = null;
        this._state = 'closed';
        this._emit('closed');
        return true;
    };
    Controller.prototype.destroy = function() {
        if (this._destroyed) return false;
        this.close();
        this._mux.destroy();
        this._destroyed = true;
        return true;
    };
    Controller.prototype.debugState = function() {
        return {
            state:this._state,
            panelInstanceId:this._panelInstanceId,
            sessionGeneration:this._sessionGeneration,
            pending:this._pending ? {
                operationId:this._pending.operationId,
                command:this._pending.command
            } : null,
            inboxRemaining:this._inbox && this._inbox.summary
                ? Number(this._inbox.summary.remainingCount) : null,
            cooldownActive:this._cooldownLanes ? this._cooldownLanes.some(function(row) {
                return row.ready !== true;
            }) : null,
            mux:this._mux.debugState ? this._mux.debugState() : null
        };
    };

    return {
        Controller:Controller,
        createMux:createMux,
        normalizedAction:normalizedAction,
        exactSource:exactSource,
        isAmbiguous:isAmbiguous,
        normalizeCooldownLanes:Cooldown.normalize
    };
});
