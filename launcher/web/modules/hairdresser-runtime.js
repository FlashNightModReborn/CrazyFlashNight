/**
 * Hairdresser request/session primitive.
 *
 * The browser owns local hairstyle preview only. The only write command in this
 * domain is commit; an uncertain commit must be reconciled by a fresh snapshot.
 */
(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports
        ? require('./panel-runtime.js') : root && root.PanelRuntime;
    var api = factory(shared);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.HairdresserRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';

    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) {
        throw new Error('PanelRuntime is required');
    }

    var COMMAND = /^(snapshot|commit)$/;

    function finiteTimeout(value) {
        value = Number(value);
        return isFinite(value) && value >= 100 ? value : 12000;
    }

    function shortNonce(value) {
        value = String(value || '').replace(/[^A-Za-z0-9._~-]/g, '').slice(0, 48);
        return value || undefined;
    }

    function RequestMux(options) {
        options = options || {};
        this._mux = new PanelRuntime.PanelRequestMux({
            send: options.send,
            setTimer: options.setTimer,
            clearTimer: options.clearTimer,
            timeoutMs: finiteTimeout(options.timeoutMs),
            sessionNonce: shortNonce(options.sessionNonce),
            callPrefix: 'hair',
            router: options.router || PanelRuntime.sharedResponseRouter,
            createMessage: function(context) {
                var payload = PanelRuntime.copyOwn(context.payload);
                payload.v = 1;
                return {
                    type: 'panel',
                    panel: 'hairdresser',
                    domain: 'hairdresser',
                    cmd: context.entry.cmd,
                    callId: context.entry.callId,
                    payload: payload
                };
            },
            validateResponse: function(data, entry) {
                return data && data.type === 'panel_resp'
                    && data.domain === 'hairdresser'
                    && data.cmd === entry.cmd
                    && data.callId === entry.callId;
            },
            transformResponse: function(data, entry) {
                if (typeof data.success === 'boolean') return data;
                return {
                    type: 'panel_resp',
                    panel: 'hairdresser',
                    domain: 'hairdresser',
                    cmd: entry.cmd,
                    callId: entry.callId,
                    success: false,
                    error: 'malformed_response',
                    requiresReconcile: entry.write === true,
                    clientSynthetic: true
                };
            },
            createSynthetic: function(context) {
                return {
                    type: 'panel_resp',
                    panel: 'hairdresser',
                    domain: 'hairdresser',
                    cmd: context.entry.cmd,
                    callId: context.entry.callId,
                    success: false,
                    error: context.error,
                    requiresReconcile: context.entry.write === true
                        && context.error === 'client_timeout',
                    clientSynthetic: true
                };
            }
        });
    }

    RequestMux.prototype.openSession = function() {
        return this._mux.openSession({});
    };

    RequestMux.prototype.closeSession = function() {
        this._mux.closeSession();
    };

    RequestMux.prototype.request = function(cmd, payload, callback) {
        cmd = String(cmd || '');
        if (!COMMAND.test(cmd)) return null;
        return this._mux.request(cmd, payload || {}, {
            kind: cmd,
            singleFlight: true,
            write: cmd === 'commit',
            sendError: 'not_sent'
        }, callback);
    };

    RequestMux.prototype.handleResponse = function(data) {
        return this._mux.handleResponse(data);
    };

    RequestMux.prototype.destroy = function() {
        this._mux.destroy();
    };

    RequestMux.prototype.debugState = function() {
        var state = this._mux.debugState();
        return {
            active: state.active,
            generation: state.generation,
            sequence: state.sequence,
            pendingCount: state.pendingCount,
            pendingKinds: state.pendingKinds
        };
    };

    return { RequestMux: RequestMux };
});
