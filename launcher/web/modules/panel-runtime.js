/**
 * Shared request multiplexing and panel-response routing.
 *
 * Domain runtimes provide message builders and strict response validators. This
 * module owns only session namespaces, pending calls, timeout/cancel mechanics
 * and the single Bridge.on('panel_resp') fan-out.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.PanelRuntime = api;
        root.PanelRuntime = api;
        if (root.Bridge) api.sharedResponseRouter.install(root.Bridge);
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function copyOwn(value) {
        var copy = {};
        value = value && typeof value === 'object' ? value : {};
        for (var key in value) {
            if (Object.prototype.hasOwnProperty.call(value, key)) copy[key] = value[key];
        }
        return copy;
    }

    function ownCount(value) { return value ? Object.keys(value).length : 0; }

    function safePart(value, fallback) {
        value = String(value || '').replace(/[^A-Za-z0-9._~-]/g, '').slice(0, 80);
        return value || fallback;
    }

    function makeNonce(prefix) {
        return safePart(String(prefix || 'panel') + '.' + Date.now().toString(36) + '.'
            + Math.floor(Math.random() * 0x7fffffff).toString(36), 'panel.session');
    }

    function defaultProtocolError(message) {
        if (typeof console !== 'undefined' && console.warn) console.warn(message);
    }

    function PanelResponseRouter(options) {
        options = options || {};
        this._handlers = [];
        this._bridge = null;
        this._listener = null;
        this._onError = typeof options.onError === 'function' ? options.onError : defaultProtocolError;
    }

    PanelResponseRouter.prototype.install = function(bridge) {
        if (!bridge || typeof bridge.on !== 'function') return false;
        if (this._bridge === bridge && this._listener) return true;
        this.uninstall();
        var self = this;
        this._bridge = bridge;
        this._listener = function(data) { self.handleResponse(data); };
        bridge.on('panel_resp', this._listener);
        return true;
    };

    PanelResponseRouter.prototype.uninstall = function() {
        if (!this._bridge || !this._listener) return false;
        if (typeof this._bridge.off === 'function') this._bridge.off('panel_resp', this._listener);
        this._bridge = null;
        this._listener = null;
        return true;
    };

    PanelResponseRouter.prototype.register = function(handler) {
        var callback = typeof handler === 'function' ? handler
            : handler && typeof handler.handleResponse === 'function'
                ? function(data) { return handler.handleResponse(data); } : null;
        if (!callback) throw new TypeError('response handler is required');
        var entry = {owner: handler, callback: callback};
        this._handlers.push(entry);
        var self = this;
        var active = true;
        return function() {
            if (!active) return false;
            active = false;
            var index = self._handlers.indexOf(entry);
            if (index >= 0) self._handlers.splice(index, 1);
            return index >= 0;
        };
    };

    PanelResponseRouter.prototype.handleResponse = function(data) {
        if (!data || data.type !== 'panel_resp') return false;
        var handlers = this._handlers.slice();
        for (var i = 0; i < handlers.length; i++) {
            try {
                if (handlers[i].callback(data) === true) return true;
            } catch (error) {
                this._onError(error && error.message ? error.message : String(error));
            }
        }
        return false;
    };

    PanelResponseRouter.prototype.debugState = function() {
        return {installed:!!this._listener, handlerCount:this._handlers.length};
    };

    var sharedResponseRouter = new PanelResponseRouter();

    function defaultSynthetic(context) {
        return {
            type: 'panel_resp',
            cmd: context.entry.cmd,
            callId: context.entry.callId,
            success: false,
            error: context.error,
            clientSynthetic: true,
            requiresReconcile: !!context.entry.write
        };
    }

    function defaultMessage(context) {
        return {
            type: 'panel',
            cmd: context.entry.cmd,
            callId: context.entry.callId,
            payload: copyOwn(context.payload)
        };
    }

    function defaultResponseValidator(data, entry) {
        return !!data && data.type === 'panel_resp' && data.callId === entry.callId
            && (!data.cmd || data.cmd === entry.cmd);
    }

    function PanelRequestMux(options) {
        options = options || {};
        this._send = typeof options.send === 'function' ? options.send : function() { return false; };
        this._setTimer = options.setTimer || function(callback, delay) { return setTimeout(callback, delay); };
        this._clearTimer = options.clearTimer || function(timer) { clearTimeout(timer); };
        this._timeoutMs = Math.max(100, Number(options.timeoutMs) || 12000);
        this._prefix = safePart(options.callPrefix, 'panel');
        this._nonce = safePart(options.sessionNonce, makeNonce(this._prefix));
        this._createMessage = typeof options.createMessage === 'function' ? options.createMessage : defaultMessage;
        this._validateResponse = typeof options.validateResponse === 'function'
            ? options.validateResponse : defaultResponseValidator;
        this._transformResponse = typeof options.transformResponse === 'function'
            ? options.transformResponse : function(data) { return data; };
        this._createSynthetic = typeof options.createSynthetic === 'function'
            ? options.createSynthetic : defaultSynthetic;
        this._validateSession = typeof options.validateSession === 'function'
            ? options.validateSession : function() { return true; };
        this._onProtocolError = typeof options.onProtocolError === 'function'
            ? options.onProtocolError : defaultProtocolError;
        this._generation = 0;
        this._sequence = 0;
        this._issueOrdinal = 0;
        this._active = false;
        this._session = {};
        this._pending = {};
        this._pendingByKind = {};
        this._disconnectRouter = null;
        if (options.router) this.connectRouter(options.router);
    }

    PanelRequestMux.prototype.connectRouter = function(router) {
        if (!router || typeof router.register !== 'function') return false;
        if (this._disconnectRouter) this._disconnectRouter();
        this._disconnectRouter = router.register(this);
        return true;
    };

    PanelRequestMux.prototype.openSession = function(session) {
        this.closeSession();
        this._generation += 1;
        this._session = copyOwn(session);
        this._active = this._validateSession(this._session) !== false;
        return this._active;
    };

    PanelRequestMux.prototype._dropEntry = function(entry) {
        if (!entry) return false;
        this._clearTimer(entry.timer);
        delete this._pending[entry.callId];
        if (this._pendingByKind[entry.kind] === entry.callId) delete this._pendingByKind[entry.kind];
        return true;
    };

    PanelRequestMux.prototype.closeSession = function() {
        var entries = [];
        for (var key in this._pending) {
            if (Object.prototype.hasOwnProperty.call(this._pending, key)) entries.push(this._pending[key]);
        }
        for (var i = 0; i < entries.length; i++) this._dropEntry(entries[i]);
        this._pending = {};
        this._pendingByKind = {};
        this._active = false;
        this._session = {};
    };

    PanelRequestMux.prototype.request = function(cmd, payload, options, callback) {
        if (typeof options === 'function') { callback = options; options = {}; }
        options = options || {};
        cmd = String(cmd || '');
        if (!this._active || !cmd) return null;
        var kind = String(options.kind || cmd);
        if (options.latestWins) this.cancelKind(kind);
        else if (options.singleFlight && this._pendingByKind[kind]) return null;

        var callId = this._prefix + '.' + this._nonce + '.' + this._generation + '.' + (++this._sequence);
        var entry = {
            callId: callId,
            cmd: cmd,
            kind: kind,
            generation: this._generation,
            session: copyOwn(this._session),
            issueOrdinal: ++this._issueOrdinal,
            write: options.write === true,
            metadata: copyOwn(options.metadata),
            callback: typeof callback === 'function' ? callback : function() {},
            timer: null
        };
        var context = {entry:entry, session:entry.session, payload:payload || {}, options:options};
        var message = this._createMessage(context);
        if (!message || typeof message !== 'object') return null;
        var self = this;
        entry.timer = this._setTimer(function() {
            if (self._pending[callId] !== entry) return;
            self._dropEntry(entry);
            entry.callback(self._createSynthetic({entry:entry, session:entry.session,
                error:'client_timeout', options:options}), entry);
        }, this._timeoutMs);
        this._pending[callId] = entry;
        this._pendingByKind[kind] = callId;
        if (typeof options.onIssued === 'function') options.onIssued(entry, message);
        try {
            if (this._send(message) === false) throw new Error('send returned false');
        } catch (error) {
            this._dropEntry(entry);
            entry.callback(this._createSynthetic({entry:entry, session:entry.session,
                error:String(options.sendError || 'not_sent'), cause:error, options:options}), entry);
        }
        return callId;
    };

    PanelRequestMux.prototype.handleResponse = function(data) {
        if (!data || data.type !== 'panel_resp' || !data.callId) return false;
        var entry = this._pending[data.callId];
        if (!entry || !this._active || entry.generation !== this._generation) return false;
        if (this._validateResponse(data, entry, entry.session) !== true) {
            this._onProtocolError('[PanelRequestMux] response shape mismatch for ' + data.callId);
            return false;
        }
        var response = this._transformResponse(data, entry, entry.session);
        if (!response || typeof response !== 'object') {
            this._onProtocolError('[PanelRequestMux] response transform failed for ' + data.callId);
            return false;
        }
        this._dropEntry(entry);
        entry.callback(response, entry);
        return true;
    };

    PanelRequestMux.prototype.cancel = function(callId) {
        return this._dropEntry(this._pending[callId]);
    };
    PanelRequestMux.prototype.cancelKind = function(kind) {
        var callId = this._pendingByKind[String(kind)];
        return callId ? this.cancel(callId) : false;
    };
    PanelRequestMux.prototype.hasKind = function(kind) {
        return !!this._pendingByKind[String(kind)];
    };
    PanelRequestMux.prototype.pendingCount = function() { return ownCount(this._pending); };

    PanelRequestMux.prototype.destroy = function() {
        this.closeSession();
        if (this._disconnectRouter) this._disconnectRouter();
        this._disconnectRouter = null;
    };

    PanelRequestMux.prototype.debugState = function() {
        return {
            sessionNonce:this._nonce,
            generation:this._generation,
            sequence:this._sequence,
            issueOrdinal:this._issueOrdinal,
            active:this._active,
            pendingCount:this.pendingCount(),
            pendingKinds:Object.keys(this._pendingByKind),
            session:copyOwn(this._session)
        };
    };

    return {
        PanelRequestMux: PanelRequestMux,
        PanelResponseRouter: PanelResponseRouter,
        sharedResponseRouter: sharedResponseRouter,
        copyOwn: copyOwn,
        makeNonce: makeNonce
    };
});
