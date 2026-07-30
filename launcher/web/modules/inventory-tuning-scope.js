/** Standalone tuning's backpack projection and exact return-state boundary. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryTuningScope = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function clone(value) {
        return value == null ? value : JSON.parse(JSON.stringify(value));
    }

    function scopedRequest() {
        return {containerId:'背包', offset:0, limit:50, filterKey:'all', scope:'equipment'};
    }

    function Transition(options) {
        options = options || {};
        if (!options.coordinator || typeof options.getRoot !== 'function') {
            throw new Error('Inventory tuning scope requires coordinator and backpack root');
        }
        this._coordinator = options.coordinator;
        this._getRoot = options.getRoot;
        this._returnState = null;
        this._lastFocus = clone(options.initialFocus);
        this._root = null;
        this._focusListener = this._onFocus.bind(this);
    }

    Transition.prototype.prepareInitial = function(request, initialView) {
        request = clone(request);
        if (initialView !== 'tuning') return request;
        this._returnState = {request:clone(request), viewport:null};
        return scopedRequest();
    };

    Transition.prototype.attach = function() {
        var root = this._getRoot();
        if (root === this._root) return;
        this.detach();
        this._root = root || null;
        if (this._root) this._root.addEventListener('focusin', this._focusListener);
    };

    Transition.prototype.detach = function() {
        if (this._root) this._root.removeEventListener('focusin', this._focusListener);
        this._root = null;
    };

    Transition.prototype._onFocus = function(event) {
        var root = this._getRoot();
        var tile = event.target && event.target.closest
            ? event.target.closest('[data-workbench-key]') : null;
        if (!root || !tile || !root.contains(tile)) return;
        this._lastFocus = {
            key:String(tile.getAttribute('data-workbench-key')),
            role:event.target.closest('.inventory-discard-btn') ? 'discard' : 'tile'
        };
    };

    Transition.prototype._captureViewport = function() {
        var root = this._getRoot();
        return {
            scrollTop:root ? Number(root.scrollTop || 0) : 0,
            scrollLeft:root ? Number(root.scrollLeft || 0) : 0,
            focus:clone(this._lastFocus)
        };
    };

    Transition.prototype.enter = function(callback) {
        if (this._returnState) return false;
        var request = this._coordinator.getRequest('背包');
        if (!request) return false;
        this._returnState = {request:clone(request), viewport:this._captureViewport()};
        var self = this;
        var started = this._coordinator.replaceWindowRequest('背包', scopedRequest(), function(result) {
            if (!result || !result.success) self._returnState = null;
            if (typeof callback === 'function') callback(result || {success:false});
        });
        if (!started) this._returnState = null;
        return started;
    };

    Transition.prototype.leave = function(callback) {
        if (!this._returnState || !this._returnState.request) return false;
        return this._coordinator.replaceWindowRequest(
            '背包', clone(this._returnState.request), callback);
    };

    Transition.prototype.resume = function(callback) {
        if (!this._returnState) return false;
        return this._coordinator.replaceWindowRequest('背包', scopedRequest(), callback);
    };

    Transition.prototype.restore = function() {
        if (!this._returnState) return false;
        var viewport = this._returnState.viewport;
        var root = this._getRoot();
        if (root && viewport) {
            var focus = viewport.focus, target = null;
            if (focus) {
                var nodes = root.querySelectorAll('[data-workbench-key]');
                for (var i = 0; i < nodes.length; i++) {
                    if (nodes[i].getAttribute('data-workbench-key') === focus.key) {
                        target = focus.role === 'discard'
                            ? nodes[i].querySelector('.inventory-discard-btn') : nodes[i];
                        break;
                    }
                }
            }
            if (target && typeof target.focus === 'function') {
                try { target.focus({preventScroll:true}); } catch (_) { target.focus(); }
            }
            root.scrollTop = viewport.scrollTop;
            root.scrollLeft = viewport.scrollLeft;
        }
        this._returnState = null;
        return true;
    };

    Transition.prototype.debugState = function() {
        return {hasReturnState:!!this._returnState, returnState:clone(this._returnState)};
    };

    Transition.prototype.destroy = function() {
        this.detach();
        this._returnState = null;
        this._lastFocus = null;
    };

    return {Transition:Transition, scopedRequest:scopedRequest};
});
