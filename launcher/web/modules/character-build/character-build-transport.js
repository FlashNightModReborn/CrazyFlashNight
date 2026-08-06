/** Character Build PanelRequestMux transport framing. */
(function(root, factory) {
    'use strict';
    var runtime = typeof module !== 'undefined' && module.exports
        ? require('../panel-runtime.js') : root && root.PanelRuntime;
    var api = factory(runtime);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildTransport = api;
        root.CharacterBuildTransport = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';
    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) {
        throw new Error('CharacterBuildTransport requires PanelRuntime');
    }

    function copy(value) {
        var result = {};
        value = value && typeof value === 'object' ? value : {};
        for (var key in value) {
            if (Object.prototype.hasOwnProperty.call(value, key)) result[key] = value[key];
        }
        return result;
    }
    function createRequestMux(options) {
        options = options || {};
        return new PanelRuntime.PanelRequestMux({
            send:options.send,
            setTimer:options.setTimer,
            clearTimer:options.clearTimer,
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce,
            callPrefix:'character-build',
            router:options.router || PanelRuntime.sharedResponseRouter,
            validateSession:function(session) { return !!String(session.panelInstanceId || ''); },
            createMessage:function(context) {
                var payload = copy(context.payload);
                payload.v = 1;
                return {
                    type:'panel',
                    panel:'workbench',
                    domain:'loadout',
                    cmd:context.entry.cmd,
                    callId:context.entry.callId,
                    panelInstanceId:context.session.panelInstanceId,
                    payload:payload
                };
            },
            validateResponse:function(data, entry, session) {
                return !!data && data.type === 'panel_resp' && data.panel === 'workbench'
                    && data.domain === 'loadout' && data.cmd === entry.cmd
                    && data.callId === entry.callId
                    && String(data.panelInstanceId || '') === session.panelInstanceId;
            },
            createSynthetic:function(context) {
                var unknown = context.entry.write === true && context.error === 'client_timeout';
                return {
                    type:'panel_resp',
                    panel:'workbench',
                    domain:'loadout',
                    cmd:context.entry.cmd,
                    callId:context.entry.callId,
                    panelInstanceId:context.session.panelInstanceId,
                    success:false,
                    error:context.error,
                    clientSynthetic:true,
                    requiresReconcile:unknown,
                    reconcileAfterCallId:unknown ? context.entry.callId : ''
                };
            }
        });
    }

    return {copy:copy, createRequestMux:createRequestMux};
});
