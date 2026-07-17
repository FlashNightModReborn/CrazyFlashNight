/** Equipment tuning request/session primitives. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.EquipmentTuningRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var TOKEN = /^[A-Za-z0-9._-]{1,160}$/;

    function makeNonce() {
        return (Date.now().toString(36) + Math.floor(Math.random() * 0x7fffffff).toString(36))
            .replace(/[^A-Za-z0-9_-]/g, '').slice(0, 28) || 'tuning';
    }

    function safeToken(value) {
        value = String(value || '');
        return TOKEN.test(value) ? value : '';
    }

    function RequestMux(options) {
        options = options || {};
        this._send = typeof options.send === 'function' ? options.send : function() { return false; };
        this._setTimer = options.setTimer || function(callback, delay) { return setTimeout(callback, delay); };
        this._clearTimer = options.clearTimer || function(timer) { clearTimeout(timer); };
        this._timeoutMs = Math.max(100, Number(options.timeoutMs) || 12000);
        this._nonce = safeToken(options.sessionNonce) || makeNonce();
        this._generation = 0;
        this._sequence = 0;
        this._active = false;
        this._panelInstanceId = '';
        this._viewSessionId = '';
        this._pending = {};
    }

    RequestMux.prototype.openSession = function(panelInstanceId, viewSessionId) {
        this.closeSession();
        panelInstanceId = safeToken(panelInstanceId);
        viewSessionId = safeToken(viewSessionId);
        if (!panelInstanceId || !viewSessionId) return false;
        this._generation += 1;
        this._panelInstanceId = panelInstanceId;
        this._viewSessionId = viewSessionId;
        this._active = true;
        return true;
    };

    RequestMux.prototype.closeSession = function() {
        for (var callId in this._pending) {
            if (!Object.prototype.hasOwnProperty.call(this._pending, callId)) continue;
            this._clearTimer(this._pending[callId].timer);
        }
        this._pending = {};
        this._active = false;
        this._panelInstanceId = '';
        this._viewSessionId = '';
    };

    RequestMux.prototype.request = function(cmd, payload, callback) {
        if (!this._active || !/^(snapshot|preview|commit|tooltip|detach)$/.test(String(cmd || ''))) return null;
        payload = payload && typeof payload === 'object' && !Array.isArray(payload) ? copyOwn(payload) : {};
        payload.v = 1;
        payload.viewSessionId = this._viewSessionId;
        var callId = 'tune.' + this._nonce + '.' + this._generation + '.' + (++this._sequence);
        var message = {
            type:'panel', panel:'workbench', domain:'equipment_tuning', cmd:String(cmd), callId:callId,
            panelInstanceId:this._panelInstanceId, payload:payload
        };
        var self = this;
        var entry = {
            cmd:String(cmd), generation:this._generation, panelInstanceId:this._panelInstanceId,
            viewSessionId:this._viewSessionId, callback:typeof callback === 'function' ? callback : function() {}, timer:null
        };
        entry.timer = this._setTimer(function() {
            if (self._pending[callId] !== entry) return;
            delete self._pending[callId];
            entry.callback({type:'panel_resp', panel:'workbench', domain:'equipment_tuning', cmd:entry.cmd,
                callId:callId, panelInstanceId:entry.panelInstanceId, viewSessionId:entry.viewSessionId,
                success:false, error:'client_timeout', requiresReconcile:entry.cmd === 'commit'});
        }, this._timeoutMs);
        this._pending[callId] = entry;
        var delivered = false;
        try { delivered = this._send(message) !== false; } catch (error) { delivered = false; }
        if (!delivered) {
            this._clearTimer(entry.timer);
            delete this._pending[callId];
            entry.callback({type:'panel_resp', panel:'workbench', domain:'equipment_tuning', cmd:entry.cmd,
                callId:callId, panelInstanceId:entry.panelInstanceId, viewSessionId:entry.viewSessionId,
                success:false, error:'not_sent', requiresReconcile:false});
        }
        return callId;
    };

    RequestMux.prototype.handleResponse = function(data) {
        if (!data || data.type !== 'panel_resp' || data.domain !== 'equipment_tuning' || !data.callId) return false;
        var entry = this._pending[data.callId];
        if (!entry || !this._active || entry.generation !== this._generation) return false;
        if (data.cmd !== entry.cmd || data.panelInstanceId !== entry.panelInstanceId
                || data.viewSessionId !== entry.viewSessionId) return false;
        this._clearTimer(entry.timer);
        delete this._pending[data.callId];
        entry.callback(data);
        return true;
    };

    RequestMux.prototype.debugState = function() {
        return {active:this._active, generation:this._generation, sequence:this._sequence,
            panelInstanceId:this._panelInstanceId, viewSessionId:this._viewSessionId,
            pendingCount:Object.keys(this._pending).length};
    };

    function copyOwn(value) {
        var copy = {};
        for (var key in value) if (Object.prototype.hasOwnProperty.call(value, key)) copy[key] = value[key];
        return copy;
    }

    function isAmbiguous(response) {
        var error = response && response.error;
        // A disconnected preflight is definitive when Host explicitly says that the
        // command never entered its write watermark. Do not manufacture a barrier for
        // a callId that AS2 never observed.
        if (error === 'disconnected') return !!(response && response.requiresReconcile === true);
        return !!(response && response.requiresReconcile)
            || error === 'timeout' || error === 'client_timeout'
            || error === 'malformed_response' || error === 'reconcile_required';
    }

    return {RequestMux:RequestMux, isAmbiguous:isAmbiguous, safeToken:safeToken};
});
