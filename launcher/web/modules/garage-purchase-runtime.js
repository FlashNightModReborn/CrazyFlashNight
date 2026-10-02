(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports ? require('./panel-runtime.js') : root.PanelRuntime;
    var api = factory(shared);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.GaragePurchaseRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';
    function validVehicle(id) { return /^(bicycle|motorcycle|offroad)$/.test(id); }
    function normalizeState(v) {
        if (!v || v.v !== 1 || typeof v.token !== 'string' || !/^[A-Za-z0-9._~-]{1,128}$/.test(v.token)
            || !validVehicle(v.vehicleId) || !v.draft || v.draft.vehicleId !== v.vehicleId
            || Object.keys(v.draft).join(',') !== 'vehicleId' || typeof v.name !== 'string' || !v.name
            || typeof v.description !== 'string' || !Number.isSafeInteger(v.cost) || v.cost <= 0
            || !Number.isSafeInteger(v.balance) || v.balance < 0 || !Number.isSafeInteger(v.drivingLevel) || v.drivingLevel < 0
            || !Number.isInteger(v.requiredDrivingLevel) || v.requiredDrivingLevel < 0 || v.requiredDrivingLevel > 2
            || typeof v.owned !== 'boolean' || typeof v.canPurchase !== 'boolean') return null;
        var eligible = !v.owned && v.balance >= v.cost && v.drivingLevel >= v.requiredDrivingLevel;
        if (v.canPurchase !== eligible) return null;
        var valid = v.phase === 'editing' && v.success === true && !v.owned && v.changed === false && v.saved === false;
        valid = valid || v.phase === 'owned' && v.success === true && v.owned && v.changed === false && v.saved === false;
        valid = valid || v.phase === 'applied' && v.success === true && v.owned && v.changed === true && v.saved === true;
        valid = valid || v.phase === 'save_pending' && v.success === false && v.owned && v.error === 'save_pending'
            && v.changed === true && v.saved === false;
        return valid ? JSON.parse(JSON.stringify(v)) : null;
    }
    function RequestMux(options) {
        var instance = options.panelInstanceId;
        this._mux = new PanelRuntime.PanelRequestMux({
            send:options.send, timeoutMs:options.timeoutMs || 12000, callPrefix:'garage', router:options.router || PanelRuntime.sharedResponseRouter,
            createMessage:function(context) {
                return {type:'panel', panel:'garage', domain:'garage', cmd:context.entry.cmd,
                    panelInstanceId:instance, callId:context.entry.callId, payload:context.payload};
            },
            validateResponse:function(data, entry) {
                return data && data.type === 'panel_resp' && data.panel === 'garage' && data.domain === 'garage'
                    && data.cmd === entry.cmd && data.callId === entry.callId && (!data.panelInstanceId || data.panelInstanceId === instance);
            },
            createSynthetic:function(context) {
                return {type:'panel_resp', panel:'garage', domain:'garage', cmd:context.entry.cmd, callId:context.entry.callId,
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
    return {validVehicle:validVehicle, normalizeState:normalizeState, RequestMux:RequestMux};
});
