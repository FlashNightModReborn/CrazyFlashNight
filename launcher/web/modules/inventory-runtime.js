/**
 * inventory-domain Web runtime.
 * Owns visible range projections, one write owner, round-trip transfer/discard/auto-transfer, and failure refresh.
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
            var cloned = {
                containerId: String(requests[i].containerId),
                offset: Number(requests[i].offset),
                limit: Number(requests[i].limit),
                filterKey: normalizeFilterKey(requests[i].filterKey)
            };
            if (requests[i].filterSpec != null) cloned.filterSpec = normalizeFilterSpec(requests[i].filterSpec, cloned.filterKey);
            out.push(cloned);
        }
        return out;
    }

    var SORT_METHODS = {
        byType: true, byUse: true, byPrice: true, byLevel: true,
        byID: true, byName: true, byValue: true, byTime: true
    };

    var FILTER_KEYS = {
        all: true, weapon: true, armor: true, consumable: true, material: true, other: true
    };

    function normalizeFilterKey(value) {
        value = String(value || 'all');
        return FILTER_KEYS[value] ? value : 'all';
    }

    var FILTER_MAJORS = {
        all:true, weapon:true, armor:true, consumable:true,
        material:true, collection:true, other:true
    };

    function isSafeFilterValue(value) {
        return typeof value === 'string' && value.length <= 64 && !/[\u0000-\u001f\u007f]/.test(value);
    }

    function isValidFilterSpec(value) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
        var major = String(value.major || 'all');
        var use = value.use == null ? '' : String(value.use);
        var subtype = value.subtype == null ? '' : String(value.subtype);
        return FILTER_MAJORS[major] === true
            && isSafeFilterValue(use) && isSafeFilterValue(subtype)
            && !(major === 'all' && (use || subtype))
            && !(subtype && (major !== 'weapon' || !use));
    }

    function normalizeFilterSpec(value, fallbackKey) {
        if (value == null) return null;
        var candidate = {
            major:String(value.major || fallbackKey || 'all'),
            use:value.use == null ? '' : String(value.use),
            subtype:value.subtype == null ? '' : String(value.subtype)
        };
        if (!isValidFilterSpec(candidate)) return null;
        var normalized = {major:candidate.major};
        if (candidate.use) normalized.use = candidate.use;
        if (candidate.subtype) normalized.subtype = candidate.subtype;
        return normalized;
    }

    function filterKeyForSpec(spec) {
        spec = normalizeFilterSpec(spec, 'all');
        if (!spec) return 'all';
        if (spec.major === 'collection') return 'other';
        return FILTER_KEYS[spec.major] ? spec.major : 'all';
    }

    function sameFilterSpec(a, b) {
        a = normalizeFilterSpec(a, 'all');
        b = normalizeFilterSpec(b, 'all');
        if (!a || !b) return a === b;
        return a.major === b.major && String(a.use || '') === String(b.use || '')
            && String(a.subtype || '') === String(b.subtype || '');
    }

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
        var accessible = snapshot && snapshot.accessibleCapacity != null
            ? Number(snapshot.accessibleCapacity) : Number(snapshot && snapshot.capacity);
        var viewCapacity = snapshot && snapshot.viewCapacity != null
            ? Number(snapshot.viewCapacity) : accessible;
        return !!snapshot
            && typeof snapshot.containerId === 'string'
            && isFinite(Number(snapshot.capacity))
            && isFinite(accessible)
            && accessible >= 0
            && accessible <= Number(snapshot.capacity)
            && isFinite(viewCapacity)
            && viewCapacity >= 0
            && viewCapacity <= accessible
            && FILTER_KEYS[String(snapshot.filterKey || 'all')] === true
            && (snapshot.filterSpec == null || isValidFilterSpec(snapshot.filterSpec))
            && (snapshot.filterFacets == null || Array.isArray(snapshot.filterFacets))
            && (snapshot.filterItemCount == null || (isFinite(Number(snapshot.filterItemCount)) && Number(snapshot.filterItemCount) >= 0))
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
                var result = {
                    containerId: containerId,
                    offset: Number(this._requests[i].offset),
                    limit: Number(this._requests[i].limit),
                    filterKey: normalizeFilterKey(this._requests[i].filterKey)
                };
                if (this._requests[i].filterSpec != null) result.filterSpec = normalizeFilterSpec(this._requests[i].filterSpec, result.filterKey);
                return result;
            }
        }
        return null;
    };

    InventoryCoordinator.prototype.configureRequests = function(requests) {
        if (this._opened || !Array.isArray(requests) || requests.length < 1 || requests.length > 4) return false;
        var normalized = cloneRequests(requests);
        var seen = {};
        for (var i = 0; i < normalized.length; i++) {
            var request = normalized[i];
            if (!request.containerId || seen[request.containerId]
                    || !isFinite(request.offset) || Math.floor(request.offset) !== request.offset || request.offset < 0
                    || !isFinite(request.limit) || Math.floor(request.limit) !== request.limit
                    || request.limit < 1 || request.limit > 100) return false;
            seen[request.containerId] = true;
        }
        this._requests = normalized;
        this._windows = {};
        this._ready = false;
        this._refreshRequired = false;
        this._owner = null;
        this._emitState();
        return true;
    };

    InventoryCoordinator.prototype.resetWindow = function(containerId, offset, limit, filterKey) {
        if (this._opened) return false;
        containerId = String(containerId);
        offset = Number(offset);
        limit = Number(limit);
        if (!isFinite(offset) || Math.floor(offset) !== offset || offset < 0
                || !isFinite(limit) || Math.floor(limit) !== limit || limit < 1 || limit > 100) return false;
        filterKey = filterKey == null ? null : String(filterKey);
        if (filterKey != null && !FILTER_KEYS[filterKey]) return false;
        for (var i = 0; i < this._requests.length; i++) {
            if (this._requests[i].containerId !== containerId) continue;
            this._requests[i].offset = offset;
            this._requests[i].limit = limit;
            if (filterKey != null) {
                this._requests[i].filterKey = filterKey;
                delete this._requests[i].filterSpec;
            }
            return true;
        }
        return false;
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
            if (response && response.success === true && self._hasActiveFilter()) {
                self._refreshWhileOwned(function(refreshResult) {
                    response.viewRefreshSucceeded = !!refreshResult.success;
                    if (typeof callback === 'function') callback(response);
                });
                return;
            }
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

    /**
     * Lease-bound source + authority-selected destination. The Web supplies its current windows only so
     * AS2 can return fresh leases without moving the user's pager to the physical destination slot.
     */
    InventoryCoordinator.prototype.autoTransfer = function(sourceRef, targetContainerId, callback) {
        if (!sourceRef || !sourceRef.occupied || !sourceRef.item
                || !this.beginExternalWrite('inventory.autoTransfer')) return false;
        var self = this;
        this._request('autoTransfer', {
            v: 1,
            source: wireRef(sourceRef),
            targetContainerId: String(targetContainerId),
            policy: 'mergeThenEmpty',
            windows: cloneRequests(this._requests)
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
            // target_full/slot_locked are authoritative no-op failures. Releasing locally preserves the
            // source lease and avoids an unnecessary second round trip; all ambiguous failures reconcile.
            if (original.error === 'target_full' || original.error === 'slot_locked') {
                self._owner = null;
                self._refreshRequired = false;
                self._ready = true;
                self._emitState();
                if (typeof callback === 'function') callback(original);
                return;
            }
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

    InventoryCoordinator.prototype.discard = function(slotRef, callback) {
        if (!slotRef || !this.beginExternalWrite('inventory.discard')) return false;
        var self = this;
        this._request('discard', {v: 1, source: wireRef(slotRef)}, function(response) {
            if (response && response.success === true && self._hasActiveFilter()) {
                self._refreshWhileOwned(function(refreshResult) {
                    response.viewRefreshSucceeded = !!refreshResult.success;
                    if (typeof callback === 'function') callback(response);
                });
                return;
            }
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
        var viewCapacity = snapshot && snapshot.viewCapacity != null
            ? Number(snapshot.viewCapacity) : snapshot && snapshot.accessibleCapacity != null
                ? Number(snapshot.accessibleCapacity) : Number(snapshot && snapshot.capacity);
        if (snapshot && (viewCapacity <= 0 ? offset !== 0 : offset >= viewCapacity)) return false;
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
        var viewCapacity = snapshot.viewCapacity != null
            ? Number(snapshot.viewCapacity) : snapshot.accessibleCapacity != null
                ? Number(snapshot.accessibleCapacity) : Number(snapshot.capacity);
        var maxOffset = Math.max(0, Math.floor((viewCapacity - 1) / pageSize) * pageSize);
        var nextOffset = Math.max(0, Math.min(maxOffset, request.offset + Number(direction) * pageSize));
        if (nextOffset === request.offset) return false;
        return this.setWindow(containerId, nextOffset, pageSize, callback);
    };

    InventoryCoordinator.prototype.setFilter = function(containerId, filterKey, callback) {
        if (!this._opened || !this._ready || this._owner || this._refreshRequired) return false;
        containerId = String(containerId);
        filterKey = String(filterKey || 'all');
        if (!FILTER_KEYS[filterKey]) return false;
        var request = null;
        for (var i = 0; i < this._requests.length; i++) {
            if (this._requests[i].containerId === containerId) {
                request = this._requests[i];
                break;
            }
        }
        if (!request || (normalizeFilterKey(request.filterKey) === filterKey && request.filterSpec == null)) return false;
        request.filterKey = filterKey;
        delete request.filterSpec;
        request.offset = 0;
        this._owner = 'filter.' + containerId;
        this._emitState();
        this._refreshWhileOwned(callback);
        return true;
    };

    InventoryCoordinator.prototype.setFilterSpec = function(containerId, filterSpec, callback) {
        if (!this._opened || !this._ready || this._owner || this._refreshRequired) return false;
        containerId = String(containerId);
        var normalized = normalizeFilterSpec(filterSpec, 'all');
        if (!normalized) return false;
        var request = null;
        for (var i = 0; i < this._requests.length; i++) {
            if (this._requests[i].containerId === containerId) { request = this._requests[i]; break; }
        }
        if (!request || sameFilterSpec(request.filterSpec, normalized)) return false;
        request.filterSpec = normalized;
        request.filterKey = filterKeyForSpec(normalized);
        request.offset = 0;
        this._owner = 'filter.' + containerId;
        this._emitState();
        this._refreshWhileOwned(callback);
        return true;
    };

    InventoryCoordinator.prototype._hasActiveFilter = function() {
        for (var i = 0; i < this._requests.length; i++) {
            var spec = normalizeFilterSpec(this._requests[i].filterSpec, 'all');
            if ((spec && (spec.major !== 'all' || spec.use || spec.subtype))
                    || normalizeFilterKey(this._requests[i].filterKey) !== 'all') return true;
        }
        return false;
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
            if (response && response.success === true && self._hasActiveFilter()) {
                self._refreshWhileOwned(function(refreshResult) {
                    response.viewRefreshSucceeded = !!refreshResult.success;
                    if (typeof callback === 'function') callback(response);
                });
                return;
            }
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
            for (var q = 0; q < this._requests.length; q++) {
                if (this._requests[q].containerId === snapshots[i].containerId
                        && normalizeFilterKey(this._requests[q].filterKey) !== String(snapshots[i].filterKey || 'all')) {
                    return false;
                }
                if (this._requests[q].containerId === snapshots[i].containerId
                        && this._requests[q].filterSpec != null
                        && !sameFilterSpec(this._requests[q].filterSpec, snapshots[i].filterSpec)) return false;
            }
        }
        for (i = 0; i < snapshots.length; i++) {
            var snapshot = snapshots[i];
            var request = null;
            for (var r = 0; r < this._requests.length; r++) {
                if (this._requests[r].containerId === snapshot.containerId) {
                    request = this._requests[r];
                    break;
                }
            }
            var old = this._windows[snapshot.containerId];
            if (!old || Number(snapshot.snapshotSeq) >= Number(old.snapshotSeq)) {
                this._windows[snapshot.containerId] = snapshot;
                if (request) {
                    request.offset = Number(snapshot.offset);
                    request.filterKey = String(snapshot.filterKey || 'all');
                    if (snapshot.filterSpec != null) request.filterSpec = normalizeFilterSpec(snapshot.filterSpec, request.filterKey);
                }
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
        sortMethods: SORT_METHODS,
        filterKeys: FILTER_KEYS
        ,filterMajors: FILTER_MAJORS
        ,normalizeFilterSpec: normalizeFilterSpec
        ,filterKeyForSpec: filterKeyForSpec
    };
});
