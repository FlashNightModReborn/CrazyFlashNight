/** Exact loot-domain transport built on the shared PanelResponseRouter/PanelRequestMux. */
(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports
        ? require('../panel-runtime.js') : root && root.PanelRuntime;
    var api = factory(shared);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.LootRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';
    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) throw new Error('PanelRuntime is required');

    var COMMANDS = {snapshot:true, tooltip:true, claim:true, claimBatch:true, close:true, query:true,
        materials:true};
    var RESERVED = {
        type:true, task:true, domain:true, panel:true, v:true, cmd:true, callId:true,
        panelInstanceId:true, chestSessionId:true, lootContainerId:true, containerEpoch:true,
        sourceKind:true
    };
    var RESPONSE_KEYS = {
        type:true, task:true, domain:true, panel:true, cmd:true, callId:true,
        panelInstanceId:true, success:true, error:true, chestSessionId:true,
        lootContainerId:true, containerEpoch:true, authorityRevision:true,
        lastAppliedOperationId:true, state:true, remainingCount:true, closeLease:true,
        snapshots:true, tooltip:true, materials:true, terminal:true
    };

    function hasExactKeys(value, expected) {
        if (!value || typeof value !== 'object') return false;
        var keys = Object.keys(value), expectedKeys = Object.keys(expected);
        if (keys.length !== expectedKeys.length) return false;
        for (var i = 0; i < keys.length; i++)
            if (!Object.prototype.hasOwnProperty.call(expected,keys[i])) return false;
        return true;
    }

    function boundedText(value, limit) {
        if (typeof value !== 'string') return '';
        value = value.trim();
        return value && value.length <= limit ? value : '';
    }

    function opaque(value, limit) {
        value = boundedText(value, limit);
        return value && /^[A-Za-z0-9._~-]+$/.test(value) ? value : '';
    }

    function normalizeIdentity(value) {
        value = value || {};
        var epoch = value.containerEpoch;
        var identity = {
            panelInstanceId:opaque(value.panelInstanceId, 128),
            chestSessionId:opaque(value.chestSessionId, 128),
            lootContainerId:opaque(value.lootContainerId, 128),
            containerEpoch:epoch,
            source:value.source === 'map_chest' || value.source === 'stage_settlement'
                    || value.source === 'reward_inbox'
                ? value.source : ''
        };
        return identity.panelInstanceId && identity.chestSessionId && identity.lootContainerId && identity.source
            && typeof epoch === 'number' && isFinite(epoch)
            && Math.floor(epoch) === epoch && epoch >= 1 ? identity : null;
    }

    function sameIdentity(data, identity) {
        return !!data && data.panelInstanceId === identity.panelInstanceId
            && data.chestSessionId === identity.chestSessionId
            && data.lootContainerId === identity.lootContainerId
            && Number(data.containerEpoch) === identity.containerEpoch
            && data.source === identity.source;
    }

    function sameResponseIdentity(data, identity) {
        return !!data && data.panelInstanceId === identity.panelInstanceId
            && data.chestSessionId === identity.chestSessionId
            && data.lootContainerId === identity.lootContainerId
            && data.containerEpoch === identity.containerEpoch;
    }

    function copyFields(target, fields) {
        fields = fields && typeof fields === 'object' ? fields : {};
        for (var key in fields) {
            if (!Object.prototype.hasOwnProperty.call(fields, key)
                    || Object.prototype.hasOwnProperty.call(RESERVED,key)) continue;
            target[key] = fields[key];
        }
        return target;
    }

    function RequestMux(options) {
        options = options || {};
        var identity = normalizeIdentity(options.identity);
        if (!identity) throw new Error('valid loot identity is required');
        this.identity = identity;
        this._mux = new PanelRuntime.PanelRequestMux({
            send:options.send,
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce,
            setTimer:options.setTimer,
            clearTimer:options.clearTimer,
            callPrefix:'loot',
            router:options.router || PanelRuntime.sharedResponseRouter,
            validateSession:function(session) { return sameIdentity(session, identity); },
            createMessage:function(context) {
                var message = {
                    type:'task', task:'loot_request', domain:'loot', panel:'loot', v:2,
                    cmd:context.entry.cmd, callId:context.entry.callId,
                    panelInstanceId:identity.panelInstanceId,
                    chestSessionId:identity.chestSessionId,
                    lootContainerId:identity.lootContainerId,
                    containerEpoch:identity.containerEpoch,
                };
                if (identity.source === 'reward_inbox') message.sourceKind = 'reward_inbox';
                return copyFields(message, context.payload);
            },
            validateResponse:function(data, entry) {
                return hasExactKeys(data, RESPONSE_KEYS)
                    && data.type === 'panel_resp' && data.task === 'loot_response'
                    && data.domain === 'loot'
                    && data.panel === 'loot'
                    && data.cmd === entry.cmd && data.callId === entry.callId
                    && sameResponseIdentity(data, identity);
            },
            createSynthetic:function(context) {
                return {
                    type:'panel_resp', task:'loot_response', domain:'loot', panel:'loot', v:2,
                    cmd:context.entry.cmd, callId:context.entry.callId,
                    panelInstanceId:identity.panelInstanceId,
                    chestSessionId:identity.chestSessionId,
                    lootContainerId:identity.lootContainerId,
                    containerEpoch:identity.containerEpoch,
                    success:false,
                    error:context.error === 'not_sent' ? 'disconnected' : context.error,
                    authorityRevision:-1,
                    lastAppliedOperationId:'',
                    state:'',
                    remainingCount:0,
                    snapshots:[],
                    tooltip:null,
                    materials:null,
                    terminal:null,
                    clientSynthetic:true,
                    requiresReconcile:context.entry.write === true,
                    operationId:context.entry.metadata.operationId || ''
                };
            },
            onProtocolError:options.onProtocolError
        });
    }

    RequestMux.prototype.openSession = function() {
        return this._mux.openSession(this.identity);
    };
    RequestMux.prototype.closeSession = function() { this._mux.closeSession(); };
    RequestMux.prototype.request = function(cmd, fields, options, callback) {
        if (typeof options === 'function') { callback = options; options = {}; }
        options = options || {};
        if (!Object.prototype.hasOwnProperty.call(COMMANDS,String(cmd))) return null;
        return this._mux.request(String(cmd), fields || {}, {
            kind:options.kind || cmd,
            singleFlight:options.singleFlight === true,
            latestWins:options.latestWins === true,
            write:options.write === true,
            sendError:'not_sent',
            metadata:{operationId:String(options.operationId || '')},
            onIssued:options.onIssued
        }, callback);
    };
    RequestMux.prototype.cancelKind = function(kind) { return this._mux.cancelKind(kind); };
    RequestMux.prototype.hasKind = function(kind) { return this._mux.hasKind(kind); };
    RequestMux.prototype.destroy = function() { this._mux.destroy(); };
    RequestMux.prototype.debugState = function() { return this._mux.debugState(); };

    return {
        RequestMux:RequestMux,
        normalizeIdentity:normalizeIdentity,
        sameIdentity:sameIdentity,
        sameResponseIdentity:sameResponseIdentity,
        hasExactKeys:hasExactKeys
    };
});
