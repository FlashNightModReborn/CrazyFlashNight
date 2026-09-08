(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports ? require('./panel-runtime.js') : root.PanelRuntime;
    var controls = typeof module !== 'undefined' && module.exports ? require('./character-identity-controls.js') : root.CharacterIdentityControls;
    var api = factory(shared, controls);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.PlasticSurgeryRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime, Controls) {
    'use strict';
    function profile(value) {
        return value && typeof value === 'object' && !Array.isArray(value)
            && Object.keys(value).sort().join(',') === 'characterName,gender,height'
            && Object.keys(Controls.validateProfile(value)).length === 0;
    }
    function normalizeState(value) {
        if (!value || value.v !== 1 || typeof value.token !== 'string' || !/^[A-Za-z0-9._~-]{1,128}$/.test(value.token)
                || !profile(value.current) || !profile(value.draft) || value.cost !== 5
                || !Number.isSafeInteger(value.balance) || value.balance < 0
                || !value.portrait || !value.portrait.equipment || typeof value.portrait.hair !== 'string'
                || typeof value.portrait.face !== 'string') return null;
        var equipment = value.portrait.equipment;
        var slots = ['头部装备','上装装备','下装装备','手部装备','脚部装备','颈部装备','长枪','手枪','手枪2','刀','手雷'];
        if (Array.isArray(equipment) || Object.keys(equipment).some(function(key) {
            return slots.indexOf(key) < 0 || typeof equipment[key] !== 'string' || !equipment[key] || equipment[key].length > 160;
        })) return null;
        var same = value.current.characterName === value.draft.characterName && value.current.gender === value.draft.gender
            && value.current.height === value.draft.height;
        var valid = value.phase === 'editing' && value.success === true && value.changed === false && value.saved === false;
        valid = valid || same && value.phase === 'save_pending' && value.success === false && value.error === 'save_pending'
            && value.changed === true && value.saved === false;
        valid = valid || same && value.phase === 'applied' && value.success === true && value.changed === true && value.saved === true;
        return valid ? JSON.parse(JSON.stringify(value)) : null;
    }
    function RequestMux(options) {
        var instance = options.panelInstanceId;
        this._mux = new PanelRuntime.PanelRequestMux({
            send:options.send, timeoutMs:options.timeoutMs || 12000, callPrefix:'surgery', router:options.router || PanelRuntime.sharedResponseRouter,
            createMessage:function(context) {
                return {type:'panel', panel:'surgery', domain:'surgery', cmd:context.entry.cmd,
                    panelInstanceId:instance, callId:context.entry.callId, payload:context.payload};
            },
            validateResponse:function(data, entry) {
                return data && data.type === 'panel_resp' && data.domain === 'surgery' && data.cmd === entry.cmd
                    && data.callId === entry.callId && (!data.panelInstanceId || data.panelInstanceId === instance);
            },
            createSynthetic:function(context) {
                return {type:'panel_resp', domain:'surgery', cmd:context.entry.cmd, callId:context.entry.callId,
                    success:false, error:context.error, clientSynthetic:true,
                    requiresReconcile:context.entry.write === true && context.error === 'client_timeout'};
            }
        });
        this._mux.openSession({});
    }
    RequestMux.prototype.request = function(cmd, payload, callback) {
        if (!/^(snapshot|commit|query)$/.test(cmd)) return null;
        return this._mux.request(cmd, payload, {kind:cmd, singleFlight:true, write:cmd === 'commit', sendError:'not_sent'}, callback);
    };
    RequestMux.prototype.destroy = function() { this._mux.destroy(); };
    return {normalizeState:normalizeState, RequestMux:RequestMux};
});
