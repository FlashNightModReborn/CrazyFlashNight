/**
 * inventory-domain Web runtime.
 * Owns visible range projections, one write owner, round-trip transfer/discard, and failure refresh.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function cloneRequests(requests) {
        var out = [];
        requests = requests || [];
        for (var i = 0; i < requests.length; i++) {
            out.push({
                containerId: String(requests[i].containerId),
                offset: Number(requests[i].offset),
                limit: Number(requests[i].limit)
            });
        }
        return out;
    }

    var SORT_METHODS = {
        byType: true, byUse: true, byPrice: true, byLevel: true,
        byID: true, byName: true, byValue: true, byTime: true
    };

    function displaySortSlots(slots, methodName) {
        var sorted = (slots || []).slice();
        methodName = methodName || 'physicalSlot';
        sorted.sort(function(a, b) {
            if (methodName === 'name') {
                var aName = a && a.item ? String(a.item.displayName || a.item.name || '') : '\uffff';
                var bName = b && b.item ? String(b.item.displayName || b.item.name || '') : '\uffff';
                var byName = aName.localeCompare(bName, 'zh-CN');
                if (byName) return byName;
            } else if (methodName === 'quantity') {
                var aQuantity = a && a.item ? Number(a.item.quantity || 1) : -1;
                var bQuantity = b && b.item ? Number(b.item.quantity || 1) : -1;
                if (aQuantity !== bQuantity) return bQuantity - aQuantity;
            }
            return Number(a.physicalSlot) - Number(b.physicalSlot);
        });
        return sorted;
    }

    function isValidSnapshot(snapshot) {
        return !!snapshot
            && typeof snapshot.containerId === 'string'
            && isFinite(Number(snapshot.capacity))
            && isFinite(Number(snapshot.snapshotSeq))
            && isFinite(Number(snapshot.offset))
            && Array.isArray(snapshot.slots);
    }

    function samePhysicalSlot(source, target) {
        return !!source && !!target
            && String(source.containerId) === String(target.containerId)
            && isFinite(Number(source.slot))
            && Number(source.slot) === Number(target.slot);
    }

    function operationForIntent(intent) {
        var source = intent && intent.sourceRef;
        var target = intent && intent.targetRef;
        if (!source || !target || !source.item || !source.occupied) return null;
        if (samePhysicalSlot(source, target)) return null;
        if (!target.occupied) return 'move';
        if (source.item.itemKind === 'stack'
                && target.item
                && target.item.itemKind === 'stack'
                && source.item.name === target.item.name) return 'merge';
        return 'swap';
    }

    function wireRef(ref) {
        return {
            containerId: String(ref.containerId),
            slot: Number(ref.slot),
            expectedLease: String(ref.expectedLease)
        };
    }

    function InventoryCoordinator(options) {
        options = options || {};
        this._request = options.request || function(cmd, payload, callback) {
            callback({success: false, error: 'disconnected'});
        };
        this._onStateChange = options.onStateChange || function() {};
        this._requests = cloneRequests(options.requests || [
            {containerId: '背包', offset: 0, limit: 50},
            {containerId: '仓库', offset: 0, limit: 50}
        ]);
        this._windows = {};
        this._owner = null;
        this._refreshRequired = false;
        this._ready = false;
        this._opened = false;
    }

    InventoryCoordinator.prototype.open = function(callback) {
        this.close();
        this._opened = true;
        this._owner = 'bootstrap';
        this._emitState();
        this._refreshWhileOwned(callback);
    };

    InventoryCoordinator.prototype.close = function() {
        this._opened = false;
        this._owner = null;
        this._refreshRequired = false;
        this._ready = false;
        this._windows = {};
        this._emitState();
    };

    InventoryCoordinator.prototype.getWindow = function(containerId) {
        return this._windows[String(containerId)] || null;
    };

    InventoryCoordinator.prototype.getRequest = function(containerId) {
        containerId = String(containerId);
        for (var i = 0; i < this._requests.length; i++) {
            if (this._requests[i].containerId === containerId) {
                return {
                    containerId: containerId,
                    offset: Number(this._requests[i].offset),
                    limit: Number(this._requests[i].limit)
                };
            }
        }
        return null;
    };

    InventoryCoordinator.prototype.isReady = function() { return this._ready; };

    InventoryCoordinator.prototype.beginExternalWrite = function(owner) {
        if (!this._opened || !this._ready || this._owner || this._refreshRequired) return false;
        this._owner = String(owner || 'external');
        this._emitState();
        return true;
    };

    InventoryCoordinator.prototype.completeExternalWrite = function(needsRefresh, callback) {
        if (!this._owner) return false;
        if (!needsRefresh) {
            this._owner = null;
            this._emitState();
            if (typeof callback === 'function') callback({success: true, refreshed: false});
            return true;
        }
        this._refreshWhileOwned(callback);
        return true;
    };

    InventoryCoordinator.prototype.transfer = function(intent, callback) {
        if (!intent || intent.operationId !== 'inventory.transfer') return false;
        if (!this.beginExternalWrite('inventory.transfer')) return false;
        var command = operationForIntent(intent);
        if (!command) {
            this._owner = null;
            this._emitState();
            if (typeof callback === 'function') callback({success: false, error: 'invalid_intent'});
            return true;
        }
        var self = this;
        this._request(command, {
            v: 1,
            source: wireRef(intent.sourceRef),
            target: wireRef(intent.targetRef)
        }, function(response) {
            if (response && response.success === true && self._applySnapshots(response.snapshots)) {
                self._owner = null;
                self._refreshRequired = false;
                self._ready = true;
                self._emitState();
                if (typeof callback === 'function') callback(response);
                return;
            }
            var original = response || {success: false, error: 'invalid_response'};
            self._refreshWhileOwned(function(refreshResult) {
                var result = {
                    success: false,
                    error: original.error || 'invalid_response',
                    reconciled: !!refreshResult.success,
                    refreshError: refreshResult.success ? null : refreshResult.error
                };
                if (typeof callback === 'function') callback(result);
            });
        });
        return true;
    };

    InventoryCoordinator.prototype.discard = function(slotRef, callback) {
        if (!slotRef || !this.beginExternalWrite('inventory.discard')) return false;
        var self = this;
        this._request('discard', {v: 1, source: wireRef(slotRef)}, function(response) {
            if (response && response.success === true && self._applySnapshots(response.snapshots)) {
                self._owner = null;
                self._refreshRequired = false;
                self._ready = true;
                self._emitState();
                if (typeof callback === 'function') callback(response);
                return;
            }
            var original = response || {success: false, error: 'invalid_response'};
            self._refreshWhileOwned(function(refreshResult) {
                if (typeof callback === 'function') callback({
                    success: false,
                    error: original.error || 'invalid_response',
                    reconciled: !!refreshResult.success,
                    refreshError: refreshResult.success ? null : refreshResult.error
                });
            });
        });
        return true;
    };

    InventoryCoordinator.prototype.retryRefresh = function(callback) {
        if (!this._opened || this._owner || !this._refreshRequired) return false;
        this._owner = 'refresh.retry';
        this._emitState();
        this._refreshWhileOwned(callback);
        return true;
    };

    InventoryCoordinator.prototype.refresh = function(callback) {
        if (!this._opened || !this._ready || this._owner || this._refreshRequired) return false;
        this._owner = 'refresh';
        this._emitState();
        this._refreshWhileOwned(callback);
        return true;
    };

    InventoryCoordinator.prototype.setWindow = function(containerId, offset, limit, callback) {
        if (!this._opened || !this._ready || this._owner || this._refreshRequired) return false;
        containerId = String(containerId);
        offset = Number(offset);
        limit = Number(limit);
        if (!isFinite(offset) || Math.floor(offset) !== offset || offset < 0
                || !isFinite(limit) || Math.floor(limit) !== limit || limit < 1 || limit > 100) return false;
        var request = null;
        for (var i = 0; i < this._requests.length; i++) {
            if (this._requests[i].containerId === containerId) {
                request = this._requests[i];
                break;
            }
        }
        if (!request) return false;
        var snapshot = this.getWindow(containerId);
        if (snapshot && offset >= Number(snapshot.capacity)) return false;
        request.offset = offset;
        request.limit = limit;
        this._owner = 'window.' + containerId;
        this._emitState();
        this._refreshWhileOwned(callback);
        return true;
    };

    InventoryCoordinator.prototype.page = function(containerId, direction, callback) {
        var request = this.getRequest(containerId);
        var snapshot = this.getWindow(containerId);
        if (!request || !snapshot) return false;
        var pageSize = request.limit;
        var maxOffset = Math.max(0, Math.floor((Number(snapshot.capacity) - 1) / pageSize) * pageSize);
        var nextOffset = Math.max(0, Math.min(maxOffset, request.offset + Number(direction) * pageSize));
        if (nextOffset === request.offset) return false;
        return this.setWindow(containerId, nextOffset, pageSize, callback);
    };

    InventoryCoordinator.prototype.sortAndMerge = function(containerId, methodName, callback) {
        containerId = String(containerId);
        if (!SORT_METHODS[methodName] || !this.beginExternalWrite('inventory.sortAndMerge')) return false;
        var request = this.getRequest(containerId);
        if (!request) {
            this._owner = null;
            this._emitState();
            return false;
        }
        var self = this;
        this._request('sortAndMerge', {
            v: 1,
            container: request,
            methodName: methodName
        }, function(response) {
            if (response && response.success === true && self._applySnapshots(response.snapshots)) {
                self._owner = null;
                self._refreshRequired = false;
                self._ready = true;
                self._emitState();
                if (typeof callback === 'function') callback(response);
                return;
            }
            var original = response || {success: false, error: 'invalid_response'};
            self._refreshWhileOwned(function(refreshResult) {
                if (typeof callback === 'function') callback({
                    success: false,
                    error: original.error || 'invalid_response',
                    reconciled: !!refreshResult.success,
                    refreshError: refreshResult.success ? null : refreshResult.error
                });
            });
        });
        return true;
    };

    InventoryCoordinator.prototype._refreshWhileOwned = function(callback) {
        var self = this;
        this._request('snapshot', {v: 1, requests: cloneRequests(this._requests)}, function(response) {
            var valid = response && response.success === true && self._applySnapshots(response.snapshots);
            self._owner = null;
            self._ready = !!valid;
            self._refreshRequired = !valid;
            self._emitState();
            if (typeof callback === 'function') callback(valid
                ? {success: true, refreshed: true, response: response}
                : {success: false, error: response && response.error ? response.error : 'inventory_refresh_failed'});
        });
    };

    InventoryCoordinator.prototype._applySnapshots = function(snapshots) {
        if (!Array.isArray(snapshots) || !snapshots.length) return false;
        for (var i = 0; i < snapshots.length; i++) {
            if (!isValidSnapshot(snapshots[i])) return false;
        }
        for (i = 0; i < snapshots.length; i++) {
            var snapshot = snapshots[i];
            var old = this._windows[snapshot.containerId];
            if (!old || Number(snapshot.snapshotSeq) >= Number(old.snapshotSeq)) {
                this._windows[snapshot.containerId] = snapshot;
            }
        }
        return true;
    };

    InventoryCoordinator.prototype.debugState = function() {
        return {
            opened: this._opened,
            ready: this._ready,
            busyOwner: this._owner,
            refreshRequired: this._refreshRequired,
            containers: Object.keys(this._windows),
            requests: cloneRequests(this._requests)
        };
    };

    InventoryCoordinator.prototype._emitState = function() {
        this._onStateChange(this.debugState());
    };

    return {
        InventoryCoordinator: InventoryCoordinator,
        operationForIntent: operationForIntent,
        samePhysicalSlot: samePhysicalSlot,
        wireRef: wireRef,
        isValidSnapshot: isValidSnapshot,
        displaySortSlots: displaySortSlots,
        sortMethods: SORT_METHODS
    };
});
