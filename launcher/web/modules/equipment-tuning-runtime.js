/** Equipment tuning request/session primitives backed by shared PanelRuntime. */
(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports
        ? require('./panel-runtime.js') : root && root.PanelRuntime;
    var api = factory(shared);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.EquipmentTuningRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';
    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) throw new Error('PanelRuntime is required');

    var TOKEN = /^[A-Za-z0-9._-]{1,160}$/;
    var COMMAND = /^(snapshot|preview|commit|tooltip|detach)$/;

    function safeToken(value) {
        value = String(value || '');
        return TOKEN.test(value) ? value : '';
    }

    function RequestMux(options) {
        options = options || {};
        this._mux = new PanelRuntime.PanelRequestMux({
            send:options.send,
            setTimer:options.setTimer,
            clearTimer:options.clearTimer,
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce,
            callPrefix:'tune',
            router:options.router || PanelRuntime.sharedResponseRouter,
            validateSession:function(session) {
                return !!safeToken(session.panelInstanceId) && !!safeToken(session.viewSessionId);
            },
            createMessage:function(context) {
                var payload = PanelRuntime.copyOwn(context.payload);
                payload.v = 1;
                payload.viewSessionId = context.session.viewSessionId;
                return {type:'panel', panel:'workbench', domain:'equipment_tuning',
                    cmd:context.entry.cmd, callId:context.entry.callId,
                    panelInstanceId:context.session.panelInstanceId, payload:payload};
            },
            validateResponse:function(data, entry, session) {
                return data && data.type === 'panel_resp' && data.domain === 'equipment_tuning'
                    && data.callId === entry.callId && data.cmd === entry.cmd
                    && data.panelInstanceId === session.panelInstanceId
                    && data.viewSessionId === session.viewSessionId;
            },
            createSynthetic:function(context) {
                var commitUnknown = context.entry.cmd === 'commit' && context.error === 'client_timeout';
                return {type:'panel_resp', panel:'workbench', domain:'equipment_tuning',
                    cmd:context.entry.cmd, callId:context.entry.callId,
                    panelInstanceId:context.session.panelInstanceId,
                    viewSessionId:context.session.viewSessionId,
                    success:false, error:context.error, requiresReconcile:commitUnknown,
                    clientSynthetic:true};
            }
        });
    }

    RequestMux.prototype.openSession = function(panelInstanceId, viewSessionId) {
        return this._mux.openSession({
            panelInstanceId:safeToken(panelInstanceId),
            viewSessionId:safeToken(viewSessionId)
        });
    };
    RequestMux.prototype.closeSession = function() { this._mux.closeSession(); };
    RequestMux.prototype.request = function(cmd, payload, callback) {
        cmd = String(cmd || '');
        if (!COMMAND.test(cmd)) return null;
        return this._mux.request(cmd, payload, {write:cmd === 'commit', sendError:'not_sent'}, callback);
    };
    RequestMux.prototype.handleResponse = function(data) { return this._mux.handleResponse(data); };
    RequestMux.prototype.destroy = function() { this._mux.destroy(); };
    RequestMux.prototype.debugState = function() {
        var state = this._mux.debugState();
        return {active:state.active, generation:state.generation, sequence:state.sequence,
            panelInstanceId:state.session.panelInstanceId || '',
            viewSessionId:state.session.viewSessionId || '', pendingCount:state.pendingCount};
    };

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
