/**
 * Workbench lifecycle and deterministic teardown primitives.
 *
 * This module is intentionally DOM-agnostic except for DisposableStack.listen().
 * It gives every panel/view one vocabulary for ownership:
 *   mount -> activate -> deactivate -> unmount -> destroy.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.WorkbenchLifecycle = api;
        // Compatibility alias for the existing IIFE module style.
        root.WorkbenchLifecycle = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function defaultErrorHandler(error) {
        if (typeof console !== 'undefined' && console.error) console.error(error);
    }

    function DisposableStack(options) {
        options = options || {};
        this._entries = [];
        this._disposed = false;
        this._onError = typeof options.onError === 'function' ? options.onError : defaultErrorHandler;
    }

    DisposableStack.prototype.defer = function(dispose) {
        if (typeof dispose !== 'function') throw new TypeError('dispose callback is required');
        if (this._disposed) {
            try { dispose(); } catch (error) { this._onError(error); }
            return dispose;
        }
        this._entries.push(dispose);
        return dispose;
    };

    DisposableStack.prototype.use = function(resource, methodName) {
        if (!resource) return resource;
        var method = methodName || (typeof resource.destroy === 'function' ? 'destroy'
            : typeof resource.dispose === 'function' ? 'dispose' : '');
        if (!method || typeof resource[method] !== 'function') {
            throw new TypeError('resource has no disposable method');
        }
        this.defer(function() { resource[method](); });
        return resource;
    };

    DisposableStack.prototype.listen = function(target, type, handler, options) {
        if (!target || typeof target.addEventListener !== 'function'
                || typeof target.removeEventListener !== 'function') {
            throw new TypeError('event target is required');
        }
        target.addEventListener(type, handler, options);
        this.defer(function() { target.removeEventListener(type, handler, options); });
        return handler;
    };

    DisposableStack.prototype.timeout = function(callback, delay, timers) {
        timers = timers || {};
        var setTimer = timers.setTimer || function(fn, ms) { return setTimeout(fn, ms); };
        var clearTimer = timers.clearTimer || function(id) { clearTimeout(id); };
        var active = true;
        var timer = setTimer(function() {
            if (!active) return;
            active = false;
            callback();
        }, delay);
        this.defer(function() {
            if (!active) return;
            active = false;
            clearTimer(timer);
        });
        return timer;
    };

    DisposableStack.prototype.dispose = function() {
        if (this._disposed) return false;
        this._disposed = true;
        var entries = this._entries;
        this._entries = [];
        for (var i = entries.length - 1; i >= 0; i--) {
            try { entries[i](); } catch (error) { this._onError(error); }
        }
        return true;
    };

    DisposableStack.prototype.isDisposed = function() { return this._disposed; };
    DisposableStack.prototype.size = function() { return this._entries.length; };

    function PanelLifecycle(options) {
        options = options || {};
        this._options = options;
        this._state = 'created';
        this._host = null;
        this._context = null;
        this._lifetime = new DisposableStack({onError: options.onError});
        this._mountSession = null;
        this._session = null;
        this._destroying = false;
    }

    PanelLifecycle.prototype.mount = function(host) {
        if (this._state === 'destroyed' || this._destroying || !host) return false;
        if (this._host === host && (this._state === 'mounted' || this._state === 'active')) return true;
        if (this._host) this.unmount('remount');
        var mountSession = new DisposableStack({onError: this._options.onError});
        this._mountSession = mountSession;
        this._host = host;
        this._state = 'mounted';
        try {
            if (typeof this._options.mount === 'function') this._options.mount(host, mountSession);
        } catch (error) {
            this._mountSession = null;
            this._host = null;
            this._state = 'unmounted';
            mountSession.dispose();
            throw error;
        }
        return true;
    };

    PanelLifecycle.prototype.activate = function(context) {
        if (this._state === 'destroyed' || this._destroying || !this._host) return false;
        if (this._state === 'active') this.deactivate('reactivate');
        this._session = new DisposableStack({onError: this._options.onError});
        this._context = context || {};
        this._state = 'active';
        try {
            if (typeof this._options.activate === 'function') {
                this._options.activate(this._context, this._session, this._lifetime);
            }
        } catch (error) {
            this._session.dispose();
            this._session = null;
            this._context = null;
            this._state = 'mounted';
            throw error;
        }
        return true;
    };

    PanelLifecycle.prototype.deactivate = function(reason) {
        if (this._state !== 'active') return false;
        var error = null;
        try {
            if (typeof this._options.deactivate === 'function') {
                this._options.deactivate(reason || 'deactivate', this._context);
            }
        } catch (caught) { error = caught; }
        if (this._session) this._session.dispose();
        this._session = null;
        this._context = null;
        this._state = this._host ? 'mounted' : 'unmounted';
        if (error) throw error;
        return true;
    };

    PanelLifecycle.prototype.unmount = function(reason) {
        if (this._state === 'destroyed' || !this._host) return false;
        var error = null;
        if (this._state === 'active') {
            try { this.deactivate(reason || 'unmount'); } catch (caught) { error = caught; }
        }
        var host = this._host;
        var mountSession = this._mountSession;
        this._mountSession = null;
        this._host = null;
        this._state = 'unmounted';
        try {
            if (typeof this._options.unmount === 'function') this._options.unmount(host, reason || 'unmount');
        } catch (caughtUnmount) {
            if (!error) error = caughtUnmount;
        }
        if (mountSession) mountSession.dispose();
        if (error) throw error;
        return true;
    };

    PanelLifecycle.prototype.destroy = function(reason) {
        if (this._state === 'destroyed' || this._destroying) return false;
        this._destroying = true;
        var error = null;
        try { this.unmount(reason || 'destroy'); } catch (caught) { error = caught; }
        try {
            if (typeof this._options.destroy === 'function') this._options.destroy(reason || 'destroy');
        } catch (caughtDestroy) {
            if (!error) error = caughtDestroy;
        }
        this._lifetime.dispose();
        this._state = 'destroyed';
        this._host = null;
        this._context = null;
        this._mountSession = null;
        this._session = null;
        this._destroying = false;
        if (error) throw error;
        return true;
    };

    PanelLifecycle.prototype.own = function(resource, methodName) {
        return this._lifetime.use(resource, methodName);
    };
    PanelLifecycle.prototype.state = function() { return this._state; };
    PanelLifecycle.prototype.host = function() { return this._host; };
    PanelLifecycle.prototype.isActive = function() { return this._state === 'active'; };

    return {
        DisposableStack: DisposableStack,
        PanelLifecycle: PanelLifecycle
    };
});
