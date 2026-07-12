/** NPC shop request mux: one session namespace, strict npcshop response shape. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.NpcShopRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function nonce() {
        return (Date.now().toString(36) + Math.floor(Math.random() * 0x7fffffff).toString(36))
            .replace(/[^A-Za-z0-9_-]/g, '').slice(0, 30) || 'npcshop';
    }

    function RequestMux(options) {
        options = options || {};
        this._send = options.send || function() {};
        this._timeoutMs = Math.max(100, Number(options.timeoutMs) || 12000);
        this._nonce = String(options.sessionNonce || nonce());
        this._domain = String(options.domain || 'npcshop');
        this._panel = String(options.panel || 'npcshop');
        this._callPrefix = String(options.callPrefix || (this._domain === 'npcshop' ? 'npc' : 'npc-' + this._domain));
        this._generation = 0;
        this._seq = 0;
        this._pending = {};
        this._active = false;
    }

    RequestMux.prototype.openSession = function() {
        this.closeSession();
        this._generation++;
        this._active = true;
    };

    RequestMux.prototype.closeSession = function() {
        for (var key in this._pending) clearTimeout(this._pending[key].timer);
        this._pending = {};
        this._active = false;
    };

    RequestMux.prototype.request = function(cmd, payload, callback) {
        if (!this._active || !cmd) return null;
        var callId = this._callPrefix + '.' + this._nonce + '.' + this._generation + '.' + (++this._seq);
        var message = {type:'panel', domain:this._domain, panel:this._panel, cmd:cmd, callId:callId, payload:payload || {}};
        var self = this;
        var entry = {cmd:cmd, generation:this._generation, callback:callback || function(){}, timer:null};
        entry.timer = setTimeout(function() {
            if (self._pending[callId] !== entry) return;
            delete self._pending[callId];
            entry.callback({type:'panel_resp', domain:self._domain, cmd:cmd, callId:callId, success:false, error:'client_timeout'});
        }, this._timeoutMs);
        this._pending[callId] = entry;
        try { this._send(message); }
        catch (error) {
            clearTimeout(entry.timer);
            delete this._pending[callId];
            entry.callback({type:'panel_resp', domain:self._domain, cmd:cmd, callId:callId, success:false, error:'disconnected'});
        }
        return callId;
    };

    RequestMux.prototype.handleResponse = function(data) {
        if (!data || data.type !== 'panel_resp' || data.domain !== this._domain || !data.callId) return false;
        var entry = this._pending[data.callId];
        if (!entry || !this._active || entry.generation !== this._generation || data.cmd !== entry.cmd) return false;
        clearTimeout(entry.timer);
        delete this._pending[data.callId];
        entry.callback(data);
        return true;
    };

    RequestMux.prototype.debugState = function() {
        return {domain:this._domain, generation:this._generation, sequence:this._seq, active:this._active, pendingCount:Object.keys(this._pending).length};
    };

    return {RequestMux:RequestMux};
});
