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
    var REWARD_ROOT_RESPONSE_KEYS = Object.assign({}, RESPONSE_KEYS, {
        rootOperationId:true, rootStatus:true, resultKind:true, result:true,
        appliedCount:true, stopReason:true
    });

    // Bounded loot diagnostic envelope. Every record that reaches the Host debug
    // channel is normalized through createDiagnosticMessage so the wire shape is a
    // fixed set of scalar fields; player-facing strings never leave the web side.
    var DIAGNOSTIC_EVENTS = {
        init_received:true, request_issued:true, send_failed:true,
        client_timeout:true, response_shape_mismatch:true,
        response_transform_failed:true, response_accepted:true,
        report_adopted:true, report_render:true, report_assets:true,
        mount_failed:true
    };
    var DIAGNOSTIC_OUTCOMES = {
        issued:true, accepted:true, received:true, rejected:true, adopted:true,
        complete:true, failed:true, timeout:true, interrupted:true,
        send_failed:true, client_timeout:true, shape_mismatch:true,
        transform_failed:true, host_error:true, other:true
    };
    var DIAGNOSTIC_COMMANDS = {
        '':true, snapshot:true, tooltip:true, claim:true, claimBatch:true,
        close:true, query:true, materials:true
    };
    var DIAGNOSTIC_ERRORS = {
        '':true, invalid_init:true, mount_failed:true, render_failed:true,
        client_timeout:true, disconnected:true, not_sent:true, rejected:true,
        reconcile_required:true, malformed_response:true, transport_lost:true,
        target_full:true, inventory_full:true, capacity_reached:true,
        cap_reached:true, session_changed:true, unsupported_command:true,
        other:true
    };
    var DIAGNOSTIC_SOURCES = {
        '':true, map_chest:true, stage_settlement:true, reward_inbox:true
    };
    var DIAGNOSTIC_ID_PATTERN = /^[A-Za-z0-9._~-]{0,128}$/;
    var DIAGNOSTIC_CALL_PATTERN = /^[A-Za-z0-9._~-]{0,160}$/;
    var DIAGNOSTIC_DETAIL_PATTERN = /[^A-Za-z0-9.,:;+=/_~-]/g;

    function diagnosticId(value) {
        value = typeof value === 'string' ? value : '';
        return DIAGNOSTIC_ID_PATTERN.test(value) ? value : '';
    }
    function diagnosticCount(value) {
        return Number.isInteger(value) && value >= -1 && value <= 100000 ? value : -1;
    }
    function diagnosticDetail(value) {
        if (typeof value !== 'string') return '';
        return value.replace(DIAGNOSTIC_DETAIL_PATTERN, '').slice(0, 96);
    }
    function diagnosticOutcome(event, outcome, error) {
        outcome = String(outcome || '');
        if (Object.prototype.hasOwnProperty.call(DIAGNOSTIC_OUTCOMES, outcome))
            return outcome;
        if (event === 'request_issued') return 'issued';
        if (event === 'client_timeout') return 'client_timeout';
        if (event === 'send_failed') return 'send_failed';
        if (event === 'response_shape_mismatch') return 'shape_mismatch';
        if (event === 'response_transform_failed') return 'transform_failed';
        if (event === 'response_accepted') return error ? 'host_error' : 'accepted';
        return error ? 'other' : 'other';
    }

    function createDiagnosticMessage(record) {
        record = record || {};
        var event = String(record.event || '');
        var error = String(record.error || '');
        var generation = record.generation;
        var containerEpoch = record.containerEpoch;
        if (!Object.prototype.hasOwnProperty.call(DIAGNOSTIC_EVENTS, event)
                || !Object.prototype.hasOwnProperty.call(DIAGNOSTIC_COMMANDS,
                    String(record.cmd || ''))
                || !DIAGNOSTIC_CALL_PATTERN.test(String(record.callId || ''))
                || !Number.isInteger(generation) || generation < 0
                || generation > 2147483647
                || !Number.isInteger(containerEpoch) || containerEpoch < 0
                || containerEpoch > 2147483647) return null;
        if (!Object.prototype.hasOwnProperty.call(DIAGNOSTIC_ERRORS, error))
            error = 'other';
        var source = String(record.source || '');
        if (!Object.prototype.hasOwnProperty.call(DIAGNOSTIC_SOURCES, source))
            source = '';
        return {
            type:'debug', scope:'loot', event:event,
            outcome:diagnosticOutcome(event, record.outcome, error),
            cmd:String(record.cmd || ''),
            callId:String(record.callId || ''),
            panelInstanceId:diagnosticId(record.panelInstanceId),
            chestSessionId:diagnosticId(record.chestSessionId),
            lootContainerId:diagnosticId(record.lootContainerId),
            containerEpoch:containerEpoch,
            generation:generation,
            source:source,
            report:diagnosticId(record.report),
            error:error,
            kills:diagnosticCount(record.kills),
            flows:diagnosticCount(record.flows),
            requested:diagnosticCount(record.requested),
            loaded:diagnosticCount(record.loaded),
            errors:diagnosticCount(record.errors),
            timeouts:diagnosticCount(record.timeouts),
            fallbacks:diagnosticCount(record.fallbacks),
            detail:diagnosticDetail(record.detail)
        };
    }

    // Local observer sees every record (including filtered ones); the Host wire
    // only receives whitelisted events, and only snapshot request/accept traffic —
    // write-command noise stays local. `budget` bounds Host sends per reset().
    function createDiagnosticEmitter(options) {
        options = options || {};
        var local = typeof options.local === 'function' ? options.local : null;
        var send = typeof options.send === 'function' ? options.send : null;
        var budget = Number.isInteger(options.budget) && options.budget > 0
            ? options.budget : 48;
        var remaining = budget;
        function emit(record) {
            if (local) { try { local(record); } catch (_) {} }
            if (!record || record.domain !== 'loot') return false;
            if ((record.event === 'request_issued' || record.event === 'response_accepted')
                    && record.cmd !== 'snapshot') return false;
            var message = createDiagnosticMessage(record);
            if (!message || !send || remaining <= 0) return false;
            remaining--;
            try { return send(message) !== false; } catch (_) { return false; }
        }
        emit.reset = function() { remaining = budget; };
        emit.remaining = function() { return remaining; };
        return emit;
    }

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
                var rewardRoot = identity.source === 'reward_inbox'
                    && (entry.cmd === 'claim' || entry.cmd === 'claimBatch'
                        || entry.cmd === 'query');
                return hasExactKeys(data, rewardRoot
                        ? REWARD_ROOT_RESPONSE_KEYS : RESPONSE_KEYS)
                    && data.type === 'panel_resp' && data.task === 'loot_response'
                    && data.domain === 'loot'
                    && data.panel === 'loot'
                    && data.cmd === entry.cmd && data.callId === entry.callId
                    && sameResponseIdentity(data, identity);
            },
            createSynthetic:function(context) {
                var response = {
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
                    closeLease:'',
                    snapshots:[],
                    tooltip:null,
                    materials:null,
                    terminal:null,
                    clientSynthetic:true,
                    requiresReconcile:context.entry.write === true,
                    operationId:context.entry.metadata.operationId || ''
                };
                if (identity.source === 'reward_inbox'
                        && (context.entry.cmd === 'claim'
                            || context.entry.cmd === 'claimBatch'
                            || context.entry.cmd === 'query')) {
                    response.rootOperationId=context.entry.metadata.operationId||'';
                    response.rootStatus='not_started';
                    response.resultKind='none';
                    response.result={appliedEntryIds:[],blockedEntries:[],remainingEntryIds:[]};
                    response.appliedCount=0;
                    response.stopReason='';
                }
                return response;
            },
            onProtocolError:options.onProtocolError,
            onDiagnostic:options.onDiagnostic
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
        hasExactKeys:hasExactKeys,
        createDiagnosticMessage:createDiagnosticMessage,
        createDiagnosticEmitter:createDiagnosticEmitter
    };
});
