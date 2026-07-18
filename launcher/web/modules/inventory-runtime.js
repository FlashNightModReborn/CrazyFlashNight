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
        var branch = String(value.branch || 'category');
        if (branch === 'set') {
            var setId = value.setId == null ? '' : String(value.setId);
            return isSafeFilterValue(setId) && value.use == null && value.subtype == null;
        }
        if (branch !== 'category') return false;
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
        var branch = String(value.branch || 'category');
        if (branch === 'set') {
            var setCandidate = {branch:'set', setId:value.setId == null ? '' : String(value.setId)};
            if (!isValidFilterSpec(setCandidate)) return null;
            return setCandidate.setId ? setCandidate : {branch:'set'};
        }
        var candidate = {
            branch:branch,
            major:String(value.major || fallbackKey || 'all'),
            use:value.use == null ? '' : String(value.use),
            subtype:value.subtype == null ? '' : String(value.subtype)
        };
        if (!isValidFilterSpec(candidate)) return null;
        var normalized = {major:candidate.major};
        if (value.branch === 'category') normalized.branch = 'category';
        if (candidate.use) normalized.use = candidate.use;
        if (candidate.subtype) normalized.subtype = candidate.subtype;
        return normalized;
    }

    function filterKeyForSpec(spec) {
        spec = normalizeFilterSpec(spec, 'all');
        if (!spec) return 'all';
        if (spec.branch === 'set') return 'all';
        if (spec.major === 'collection') return 'other';
        return FILTER_KEYS[spec.major] ? spec.major : 'all';
    }

    function sameFilterSpec(a, b) {
        a = normalizeFilterSpec(a, 'all');
        b = normalizeFilterSpec(b, 'all');
        if (!a || !b) return a === b;
        if (String(a.branch || 'category') !== String(b.branch || 'category')) return false;
        if (a.branch === 'set') return String(a.setId || '') === String(b.setId || '');
        return a.major === b.major && String(a.use || '') === String(b.use || '')
            && String(a.subtype || '') === String(b.subtype || '');
    }

    function isValidSnapshot(snapshot) {
        var accessible = snapshot && snapshot.accessibleCapacity != null
            ? Number(snapshot.accessibleCapacity) : Number(snapshot && snapshot.capacity);
        var viewCapacity = snapshot && snapshot.viewCapacity != null
            ? Number(snapshot.viewCapacity) : accessible;
        var offset = Number(snapshot && snapshot.offset);
        var limit = Number(snapshot && snapshot.limit);
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
            && (snapshot.setFacets == null || Array.isArray(snapshot.setFacets))
            && (snapshot.filterItemCount == null || (isFinite(Number(snapshot.filterItemCount)) && Number(snapshot.filterItemCount) >= 0))
            && (snapshot.setFilterItemCount == null || (isFinite(Number(snapshot.setFilterItemCount)) && Number(snapshot.setFilterItemCount) >= 0))
            && isFinite(Number(snapshot.snapshotSeq))
            && isFinite(offset) && Math.floor(offset) === offset && offset >= 0
            && isFinite(limit) && Math.floor(limit) === limit && limit >= 0 && limit <= 100
            && Array.isArray(snapshot.slots)
            && snapshot.slots.length === limit;
    }

    /**
     * InventoryPanelService may clamp a now-out-of-range requested offset after an authority mutation.
     * Apart from that deterministic clamp, the returned projection must exactly describe the request.
     * snapshot.limit is the returned slice length; request.limit remains the desired page size.
     */
    function snapshotMatchesRequest(snapshot, request) {
        if (!isValidSnapshot(snapshot) || !request
                || snapshot.containerId !== String(request.containerId)
                || String(snapshot.filterKey || 'all') !== normalizeFilterKey(request.filterKey)) return false;

        var requestHasSpec = request.filterSpec != null;
        var snapshotHasSpec = snapshot.filterSpec != null;
        if (requestHasSpec !== snapshotHasSpec
                || (requestHasSpec && !sameFilterSpec(request.filterSpec, snapshot.filterSpec))) return false;

        var requestedOffset = Number(request.offset);
        var requestedLimit = Number(request.limit);
        var viewCapacity = snapshot.viewCapacity != null
            ? Number(snapshot.viewCapacity) : snapshot.accessibleCapacity != null
                ? Number(snapshot.accessibleCapacity) : Number(snapshot.capacity);
        if (!isFinite(requestedOffset) || Math.floor(requestedOffset) !== requestedOffset || requestedOffset < 0
                || !isFinite(requestedLimit) || Math.floor(requestedLimit) !== requestedLimit
                || requestedLimit < 1 || requestedLimit > 100) return false;

        var expectedOffset = requestedOffset;
        if (viewCapacity <= 0) expectedOffset = 0;
        else if (expectedOffset >= viewCapacity) {
            expectedOffset = Math.floor((viewCapacity - 1) / requestedLimit) * requestedLimit;
        }
        var expectedLimit = Math.min(requestedLimit, Math.max(0, viewCapacity - expectedOffset));
        return Number(snapshot.offset) === expectedOffset && Number(snapshot.limit) === expectedLimit;
    }

    /** Returns snapshots ordered like requests, or null. Validation is side-effect free. */
    function validateSnapshotBatch(snapshots, requests, currentWindows) {
        if (!Array.isArray(snapshots) || !Array.isArray(requests)
                || !requests.length || snapshots.length !== requests.length) return null;
        var requested = {};
        var received = {};
        var ordered = [];
        var i;
        for (i = 0; i < requests.length; i++) {
            var requestId = String(requests[i].containerId);
            if (!requestId || requested[requestId]) return null;
            requested[requestId] = requests[i];
        }
        for (i = 0; i < snapshots.length; i++) {
            var snapshot = snapshots[i];
            var snapshotId = snapshot && String(snapshot.containerId);
            if (!snapshotId || received[snapshotId] || !requested[snapshotId]
                    || !snapshotMatchesRequest(snapshot, requested[snapshotId])) return null;
            var old = currentWindows && currentWindows[snapshotId];
            if (old && Number(snapshot.snapshotSeq) < Number(old.snapshotSeq)) return null;
            received[snapshotId] = snapshot;
        }
        for (i = 0; i < requests.length; i++) {
            var id = String(requests[i].containerId);
            if (!received[id]) return null;
            ordered.push(received[id]);
        }
        return ordered;
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
        this._sessionEpoch = 0;
        this._ownerIdentity = 0;
        this._ownerHandle = null;
        this._ownerCompletionStarted = false;
    }

    InventoryCoordinator.prototype._setOwner = function(owner) {
        this._owner = String(owner || 'external');
        this._ownerIdentity += 1;
        this._ownerHandle = {
            sessionEpoch: this._sessionEpoch,
            ownerIdentity: this._ownerIdentity,
            owner: this._owner
        };
        if (Object.freeze) Object.freeze(this._ownerHandle);
        this._ownerCompletionStarted = false;
        return this._ownerHandle;
    };

    InventoryCoordinator.prototype._captureOperation = function() {
        return this._ownerHandle;
    };

    InventoryCoordinator.prototype._isActiveOperation = function(operation) {
        return !!operation && operation === this._ownerHandle && this._opened
            && operation.sessionEpoch === this._sessionEpoch
            && operation.ownerIdentity === this._ownerIdentity
            && operation.owner === this._owner;
    };

    InventoryCoordinator.prototype._clearOwner = function(operation) {
        if (!this._isActiveOperation(operation)) return false;
        this._owner = null;
        this._ownerHandle = null;
        this._ownerCompletionStarted = false;
        this._ownerIdentity += 1;
        return true;
    };

    InventoryCoordinator.prototype._invalidateOwner = function() {
        this._owner = null;
        this._ownerHandle = null;
        this._ownerCompletionStarted = false;
        this._ownerIdentity += 1;
    };

    InventoryCoordinator.prototype._requestsForContainers = function(containerIds) {
        var wanted = {};
        var out = [];
        var i;
        for (i = 0; i < containerIds.length; i++) wanted[String(containerIds[i])] = true;
        for (i = 0; i < this._requests.length; i++) {
            if (wanted[this._requests[i].containerId]) out.push(this._requests[i]);
        }
        return cloneRequests(out);
    };

    InventoryCoordinator.prototype.open = function(callback) {
        this.close();
        this._opened = true;
        this._setOwner('bootstrap');
        this._emitState();
        this._refreshWhileOwned(callback);
    };

    InventoryCoordinator.prototype.close = function() {
        this._sessionEpoch += 1;
        this._opened = false;
        this._invalidateOwner();
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
        this._invalidateOwner();
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
        var operation = this._setOwner(owner);
        this._emitState();
        return operation;
    };

    InventoryCoordinator.prototype.completeExternalWrite = function(operation, needsRefresh, callback) {
        if (!this._isActiveOperation(operation) || this._ownerCompletionStarted) return false;
        this._ownerCompletionStarted = true;
        if (!needsRefresh) {
            this._clearOwner(operation);
            this._emitState();
            if (typeof callback === 'function') callback({success: true, refreshed: false});
            return true;
        }
        this._refreshWhileOwned(callback, operation);
        return true;
    };

    InventoryCoordinator.prototype.transfer = function(intent, callback) {
        if (!intent || intent.operationId !== 'inventory.transfer') return false;
        var operation = this.beginExternalWrite('inventory.transfer');
        if (!operation) return false;
        var command = operationForIntent(intent);
        if (!command) {
            this._clearOwner(operation);
            this._emitState();
            if (typeof callback === 'function') callback({success: false, error: 'invalid_intent'});
            return true;
        }
        var self = this;
        var expectedRequests = this._requestsForContainers([
            intent.sourceRef.containerId, intent.targetRef.containerId
        ]);
        this._request(command, {
            v: 1,
            source: wireRef(intent.sourceRef),
            target: wireRef(intent.targetRef)
        }, function(response) {
            if (!self._isActiveOperation(operation)) return;
            if (response && response.success === true && self._hasActiveFilter()) {
                self._refreshWhileOwned(function(refreshResult) {
                    response.viewRefreshSucceeded = !!refreshResult.success;
                    if (typeof callback === 'function') callback(response);
                }, operation);
                return;
            }
            if (response && response.success === true
                    && self._applySnapshots(response.snapshots, expectedRequests)) {
                self._clearOwner(operation);
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
            }, operation);
        });
        return true;
    };

    /**
     * Lease-bound source + authority-selected destination. The Web supplies its current windows only so
     * AS2 can return fresh leases without moving the user's pager to the physical destination slot.
     */
    InventoryCoordinator.prototype.autoTransfer = function(sourceRef, targetContainerId, callback) {
        if (!sourceRef || !sourceRef.occupied || !sourceRef.item) return false;
        var operation = this.beginExternalWrite('inventory.autoTransfer');
        if (!operation) return false;
        var self = this;
        var expectedRequests = this._requestsForContainers([sourceRef.containerId, targetContainerId]);
        this._request('autoTransfer', {
            v: 1,
            source: wireRef(sourceRef),
            targetContainerId: String(targetContainerId),
            policy: 'mergeThenEmpty',
            windows: cloneRequests(this._requests)
        }, function(response) {
            if (!self._isActiveOperation(operation)) return;
            if (response && response.success === true
                    && self._applySnapshots(response.snapshots, expectedRequests)) {
                self._clearOwner(operation);
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
                self._clearOwner(operation);
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
            }, operation);
        });
        return true;
    };

    InventoryCoordinator.prototype.discard = function(slotRef, callback) {
        if (!slotRef) return false;
        var operation = this.beginExternalWrite('inventory.discard');
        if (!operation) return false;
        var self = this;
        var expectedRequests = this._requestsForContainers([slotRef.containerId]);
        this._request('discard', {v: 1, source: wireRef(slotRef)}, function(response) {
            if (!self._isActiveOperation(operation)) return;
            if (response && response.success === true && self._hasActiveFilter()) {
                self._refreshWhileOwned(function(refreshResult) {
                    response.viewRefreshSucceeded = !!refreshResult.success;
                    if (typeof callback === 'function') callback(response);
                }, operation);
                return;
            }
            if (response && response.success === true
                    && self._applySnapshots(response.snapshots, expectedRequests)) {
                self._clearOwner(operation);
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
            }, operation);
        });
        return true;
    };

    InventoryCoordinator.prototype.retryRefresh = function(callback) {
        if (!this._opened || this._owner || !this._refreshRequired) return false;
        this._setOwner('refresh.retry');
        this._emitState();
        this._refreshWhileOwned(callback);
        return true;
    };

    InventoryCoordinator.prototype.refresh = function(callback) {
        if (!this._opened || !this._ready || this._owner || this._refreshRequired) return false;
        this._setOwner('refresh');
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
        this._setOwner('window.' + containerId);
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
        this._setOwner('filter.' + containerId);
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
        this._setOwner('filter.' + containerId);
        this._emitState();
        this._refreshWhileOwned(callback);
        return true;
    };

    /**
     * Reads an authority-backed side projection without replacing the visible request/window.
     * This is used by contextual candidate pickers (for example equipment conversion) that
     * need fresh slot leases while preserving the player's current inventory breadcrumbs.
     */
    InventoryCoordinator.prototype.readProjection = function(projection, callback) {
        if (!this._opened || !this._ready || this._owner || this._refreshRequired) return false;
        var request = cloneRequests([projection || {}])[0];
        if (!request || !request.containerId
                || !isFinite(request.offset) || Math.floor(request.offset) !== request.offset || request.offset < 0
                || !isFinite(request.limit) || Math.floor(request.limit) !== request.limit
                || request.limit < 1 || request.limit > 100) return false;
        if (!this.getRequest(request.containerId)) return false;

        var self = this;
        var operation = this._setOwner('projection.' + request.containerId);
        this._emitState();
        this._request('snapshot', {v:1, requests:[request]}, function(response) {
            if (!self._isActiveOperation(operation)) return;
            var snapshots = response && response.snapshots;
            var ordered = response && response.success === true
                ? validateSnapshotBatch(snapshots, [request], null) : null;
            var valid = !!ordered;
            var snapshot = valid ? ordered[0] : null;
            self._clearOwner(operation);
            self._emitState();
            if (typeof callback === 'function') callback(valid
                ? {success:true, snapshot:snapshot, response:response}
                : {success:false, error:response && response.error ? response.error : 'inventory_projection_failed'});
        });
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
        if (!SORT_METHODS[methodName]) return false;
        var operation = this.beginExternalWrite('inventory.sortAndMerge');
        if (!operation) return false;
        var request = this.getRequest(containerId);
        if (!request) {
            this._clearOwner(operation);
            this._emitState();
            return false;
        }
        var self = this;
        var expectedRequests = [request];
        this._request('sortAndMerge', {
            v: 1,
            container: request,
            methodName: methodName
        }, function(response) {
            if (!self._isActiveOperation(operation)) return;
            if (response && response.success === true && self._hasActiveFilter()) {
                self._refreshWhileOwned(function(refreshResult) {
                    response.viewRefreshSucceeded = !!refreshResult.success;
                    if (typeof callback === 'function') callback(response);
                }, operation);
                return;
            }
            if (response && response.success === true
                    && self._applySnapshots(response.snapshots, expectedRequests)) {
                self._clearOwner(operation);
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
            }, operation);
        });
        return true;
    };

    InventoryCoordinator.prototype._refreshWhileOwned = function(callback, operation) {
        var self = this;
        operation = operation || this._captureOperation();
        if (!this._isActiveOperation(operation)) return false;
        var requested = cloneRequests(this._requests);
        this._request('snapshot', {v: 1, requests: requested}, function(response) {
            if (!self._isActiveOperation(operation)) return;
            var valid = response && response.success === true
                && self._applySnapshots(response.snapshots, requested);
            self._clearOwner(operation);
            self._ready = !!valid;
            self._refreshRequired = !valid;
            self._emitState();
            if (typeof callback === 'function') callback(valid
                ? {success: true, refreshed: true, response: response}
                : {success: false, error: response && response.error ? response.error : 'inventory_refresh_failed'});
        });
        return true;
    };

    InventoryCoordinator.prototype._applySnapshots = function(snapshots, expectedRequests) {
        var ordered = validateSnapshotBatch(snapshots, expectedRequests, this._windows);
        if (!ordered) return false;

        // Commit only after the whole exact-set batch is known valid.
        for (var i = 0; i < ordered.length; i++) {
            this._windows[ordered[i].containerId] = ordered[i];
        }
        for (i = 0; i < ordered.length; i++) {
            var snapshot = ordered[i];
            for (var r = 0; r < this._requests.length; r++) {
                if (this._requests[r].containerId !== snapshot.containerId) continue;
                this._requests[r].offset = Number(snapshot.offset);
                this._requests[r].filterKey = String(snapshot.filterKey || 'all');
                if (snapshot.filterSpec != null) {
                    this._requests[r].filterSpec = normalizeFilterSpec(snapshot.filterSpec, this._requests[r].filterKey);
                } else {
                    delete this._requests[r].filterSpec;
                }
                break;
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
        sortMethods: SORT_METHODS,
        filterKeys: FILTER_KEYS
        ,filterMajors: FILTER_MAJORS
        ,normalizeFilterSpec: normalizeFilterSpec
        ,filterKeyForSpec: filterKeyForSpec
    };
});
