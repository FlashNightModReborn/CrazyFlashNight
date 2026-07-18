/** NPC shop/inventory request facade backed by the shared panel runtime. */
(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports
        ? require('./panel-runtime.js') : root && root.PanelRuntime;
    var api = factory(shared);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.NpcShopRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';
    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) throw new Error('PanelRuntime is required');

    function RequestMux(options) {
        options = options || {};
        var domain = String(options.domain || 'npcshop');
        var panel = String(options.panel || 'npcshop');
        var prefix = String(options.callPrefix || (domain === 'npcshop' ? 'npc' : 'npc-' + domain));
        this._domain = domain;
        this._mux = new PanelRuntime.PanelRequestMux({
            send:options.send,
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce,
            setTimer:options.setTimer,
            clearTimer:options.clearTimer,
            callPrefix:prefix,
            router:options.router || PanelRuntime.sharedResponseRouter,
            createMessage:function(context) {
                return {type:'panel', domain:domain, panel:panel, cmd:context.entry.cmd,
                    callId:context.entry.callId, payload:context.payload || {}};
            },
            validateResponse:function(data, entry) {
                return data && data.type === 'panel_resp' && data.domain === domain
                    && data.callId === entry.callId && data.cmd === entry.cmd;
            },
            createSynthetic:function(context) {
                return {type:'panel_resp', domain:domain, panel:panel, cmd:context.entry.cmd,
                    callId:context.entry.callId, success:false, error:context.error,
                    clientSynthetic:true};
            }
        });
    }

    RequestMux.prototype.openSession = function() { return this._mux.openSession({}); };
    RequestMux.prototype.closeSession = function() { this._mux.closeSession(); };
    RequestMux.prototype.request = function(cmd, payload, callback) {
        return this._mux.request(cmd, payload, {sendError:'disconnected'}, callback);
    };
    RequestMux.prototype.handleResponse = function(data) { return this._mux.handleResponse(data); };
    RequestMux.prototype.destroy = function() { this._mux.destroy(); };
    RequestMux.prototype.debugState = function() {
        var state = this._mux.debugState();
        return {domain:this._domain, generation:state.generation, sequence:state.sequence,
            active:state.active, pendingCount:state.pendingCount};
    };

    return {RequestMux:RequestMux};
});
