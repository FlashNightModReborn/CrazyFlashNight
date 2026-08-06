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
            var scope = normalizeProjectionScope(requests[i].scope);
            var cloned = {
                containerId: String(requests[i].containerId),
                offset: Number(requests[i].offset),
                limit: Number(requests[i].limit),
                filterKey: normalizeFilterKey(requests[i].filterKey)
            };
            if (scope === 'equipment') cloned.scope = scope;
            else if (scope == null && requests[i].scope != null) cloned.scope = String(requests[i].scope);
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

    var PROJECTION_SCOPES = {all:true, equipment:true};

    function normalizeProjectionScope(value) {
        value = value == null ? 'all' : String(value);
        return PROJECTION_SCOPES[value] ? value : null;
    }

    function isValidProjectionScope(containerId, value) {
        var scope = normalizeProjectionScope(value);
        return scope != null && (scope !== 'equipment' || String(containerId) === '背包');
    }

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

    var MAX_SAFE_PROJECTION_NUMBER = 9007199254740991;
    var ITEM_KEYS = [
        'name', 'displayName', 'icon', 'majorType', 'use', 'actionType', 'weaponType',
        'setId', 'setName', 'setOrder', 'itemKind', 'quantity', 'enhancementLevel',
        'maxEnhancementLevel', 'isMaxEnhancement', 'tierSlotAvailable', 'tierSlotUsed',
        'modSlotCapacity', 'modSlotUsed', 'modSlots', 'modMeta', 'rarity'
    ];
    var STABLE_CONFIRM_KEYS = [
        'itemKind', 'name', 'displayName', 'quantity', 'enhancementLevel', 'rarity',
        'tier', 'modSignature'
    ];
    var CONFIRM_KEYS = STABLE_CONFIRM_KEYS.concat(['lastUpdate']);
    var MOD_KEYS = [
        'name', 'displayName', 'icon', 'grade', 'gradeLabel', 'gradeColor',
        'role', 'roleLabel', 'symbol', 'scope'
    ];
    var FACET_KEYS = ['id', 'label', 'order', 'count', 'children'];
    var SNAPSHOT_KEYS = [
        'containerId', 'capacity', 'accessibleCapacity', 'viewCapacity', 'filterKey',
        'pageSizeHint', 'locked', 'snapshotSeq', 'containerEpoch', 'containerVersion',
        'offset', 'limit', 'slots', 'filterFacets', 'filterItemCount', 'setFacets',
        'setFilterItemCount'
    ];

    function own(value, key) {
        return Object.prototype.hasOwnProperty.call(value || {}, key);
    }

    function isProjectionObject(value) {
        return !!value && typeof value === 'object' && !Array.isArray(value);
    }

    function hasExactKeys(value, expected) {
        if (!isProjectionObject(value)) return false;
        var keys = Object.keys(value);
        if (keys.length !== expected.length) return false;
        for (var i = 0; i < keys.length; i++) {
            if (expected.indexOf(keys[i]) < 0) return false;
        }
        return true;
    }

    function cloneSafeProjection(value) {
        if (value == null || typeof value !== 'object') return value;
        if (Array.isArray(value)) {
            var array = [];
            for (var i = 0; i < value.length; i++) array.push(cloneSafeProjection(value[i]));
            return array;
        }
        var result = {};
        var keys = Object.keys(value);
        for (var k = 0; k < keys.length; k++) {
            result[keys[k]] = cloneSafeProjection(value[keys[k]]);
        }
        return result;
    }

    function isIntegerIn(value, minimum, maximum) {
        return typeof value === 'number' && isFinite(value) && Math.floor(value) === value
            && value >= minimum && value <= maximum;
    }

    function isFiniteIn(value, minimum, maximum) {
        return typeof value === 'number' && isFinite(value)
            && value >= minimum && value <= maximum;
    }

    function isBoundedText(value, maximumLength, allowEmpty) {
        return typeof value === 'string'
            && value.length <= maximumLength
            && (allowEmpty || value.length > 0)
            && !/[\u0000-\u001f\u007f]/.test(value);
    }

    function isIdentityText(value, maximumLength) {
        return isBoundedText(value, maximumLength, false)
            && value.trim().length > 0 && value.trim().toLowerCase() !== 'undefined';
    }

    function isOpaqueLease(value) {
        return typeof value === 'string' && value.length > 0 && value.length <= 128
            && /^[A-Za-z0-9._~-]+$/.test(value);
    }

    /** Response-side proof is strict and never coerces leaves like the request normalizer does. */
    function isValidProjectedFilterSpec(value) {
        if (!isProjectionObject(value)) return false;
        if (value.branch === 'set') {
            var setKeys = own(value, 'setId') ? ['branch', 'setId'] : ['branch'];
            return hasExactKeys(value, setKeys)
                && (!own(value, 'setId') || isSafeFilterValue(value.setId) && value.setId.length > 0);
        }
        var categoryKeys = ['major'];
        if (own(value, 'branch')) categoryKeys.push('branch');
        if (own(value, 'use')) categoryKeys.push('use');
        if (own(value, 'subtype')) categoryKeys.push('subtype');
        if (!hasExactKeys(value, categoryKeys)
                || own(value, 'branch') && value.branch !== 'category'
                || typeof value.major !== 'string' || FILTER_MAJORS[value.major] !== true
                || own(value, 'use') && (!isSafeFilterValue(value.use) || !value.use.length)
                || own(value, 'subtype') && (!isSafeFilterValue(value.subtype) || !value.subtype.length)) {
            return false;
        }
        return !(value.major === 'all' && (own(value, 'use') || own(value, 'subtype')))
            && !(own(value, 'subtype') && (value.major !== 'weapon' || !own(value, 'use')));
    }

    function isValidModProjection(value) {
        if (!hasExactKeys(value, MOD_KEYS)) return false;
        for (var i = 0; i < MOD_KEYS.length; i++) {
            var key = MOD_KEYS[i];
            var identity = key === 'name' || key === 'displayName' || key === 'icon';
            if (identity ? !isIdentityText(value[key], 256)
                    : !isBoundedText(value[key], 128, true)) return false;
        }
        return true;
    }

    function isValidBalanceSummary(value) {
        return hasExactKeys(value, ['state', 'weightLayers', 'formula', 'level'])
            && value.state === 'confirmed'
            && isFiniteIn(value.weightLayers, -1000000, 1000000)
            && isFiniteIn(value.formula, 1, 1)
            && isFiniteIn(value.level, 0, 2147483647);
    }

    function isValidItemProjection(item) {
        var expectedKeys = ITEM_KEYS.slice(0);
        if (own(item, 'balanceSummary')) expectedKeys.push('balanceSummary');
        if (!hasExactKeys(item, expectedKeys)) return false;

        var requiredText = ['name', 'displayName', 'icon'];
        var optionalText = [
            'majorType', 'use', 'actionType', 'weaponType', 'setId', 'setName', 'rarity'
        ];
        var i;
        for (i = 0; i < requiredText.length; i++) {
            if (!isIdentityText(item[requiredText[i]], 256)) return false;
        }
        for (i = 0; i < optionalText.length; i++) {
            if (!isBoundedText(item[optionalText[i]], optionalText[i] === 'use' ? 64 : 256, true)) {
                return false;
            }
        }
        if (item.itemKind !== 'equipment' && item.itemKind !== 'stack') return false;
        if (!isFiniteIn(item.quantity, 0, MAX_SAFE_PROJECTION_NUMBER)
                || !isIntegerIn(item.setOrder, 0, 2147483647)
                || !isIntegerIn(item.enhancementLevel, 0, 2147483647)
                || !isIntegerIn(item.maxEnhancementLevel, 0, 2147483647)
                || !isIntegerIn(item.modSlotCapacity, 0, 2147483647)
                || !isIntegerIn(item.modSlotUsed, 0, 2147483647)
                || typeof item.isMaxEnhancement !== 'boolean'
                || typeof item.tierSlotAvailable !== 'boolean'
                || typeof item.tierSlotUsed !== 'boolean'
                || item.tierSlotUsed && !item.tierSlotAvailable
                || !Array.isArray(item.modSlots) || item.modSlots.length > 3
                || item.modSlots.length > item.modSlotUsed) {
            return false;
        }
        for (i = 0; i < item.modSlots.length; i++) {
            if (!isValidModProjection(item.modSlots[i])) return false;
        }
        if (item.modMeta !== null && !isValidModProjection(item.modMeta)) return false;

        if (item.itemKind === 'equipment') {
            if (item.quantity !== 1
                    || item.isMaxEnhancement !== (item.enhancementLevel >= item.maxEnhancementLevel)) {
                return false;
            }
        } else if (item.quantity <= 0 || item.enhancementLevel !== 0 || item.isMaxEnhancement
                || item.tierSlotAvailable || item.tierSlotUsed || item.modSlotCapacity !== 0
                || item.modSlotUsed !== 0 || item.modSlots.length !== 0) {
            return false;
        }
        return !own(item, 'balanceSummary') || isValidBalanceSummary(item.balanceSummary);
    }

    function isValidConfirmProjectionCore(confirm, item, withLastUpdate) {
        return hasExactKeys(confirm, withLastUpdate ? CONFIRM_KEYS : STABLE_CONFIRM_KEYS)
            && confirm.itemKind === item.itemKind
            && confirm.name === item.name
            && confirm.displayName === item.displayName
            && confirm.rarity === item.rarity
            && isFiniteIn(confirm.quantity, 0, MAX_SAFE_PROJECTION_NUMBER)
            && confirm.quantity === item.quantity
            && isIntegerIn(confirm.enhancementLevel, 0, 2147483647)
            && confirm.enhancementLevel === item.enhancementLevel
            && isBoundedText(confirm.tier, 256, true)
            && isBoundedText(confirm.modSignature, 1024, true)
            && (!withLastUpdate
                || isIntegerIn(confirm.lastUpdate, 0, MAX_SAFE_PROJECTION_NUMBER));
    }

    function isValidConfirmProjection(confirm, item) {
        return isValidConfirmProjectionCore(confirm, item, true);
    }

    function isValidStableConfirmProjection(confirm, item) {
        return isValidConfirmProjectionCore(confirm, item, false);
    }

    function validateFacetArray(facets, depth, sets, maximumCount) {
        if (!Array.isArray(facets) || facets.length > 64 || depth > 2) return null;
        var seen = {};
        var total = 0;
        for (var i = 0; i < facets.length; i++) {
            var facet = facets[i];
            if (!hasExactKeys(facet, FACET_KEYS)
                    || !isBoundedText(facet.id, 128, false)
                    || !isBoundedText(facet.label, 128, false)
                    || own(seen, '$' + facet.id)
                    || !isFiniteIn(facet.order, -1000000, 1000000)
                    || !isIntegerIn(facet.count, 0, maximumCount)
                    || !Array.isArray(facet.children)) return null;
            seen['$' + facet.id] = true;
            if (sets) {
                if (facet.children.length !== 0) return null;
            } else if (facet.children.length) {
                if (depth >= 2) return null;
                var children = validateFacetArray(facet.children, depth + 1, false, maximumCount);
                if (!children || children.total > facet.count) return null;
            }
            total += facet.count;
            if (total > maximumCount) return null;
        }
        return {total:total};
    }

    function hasSparsePhysicalSlots(snapshot) {
        return String(snapshot.filterKey || 'all') !== 'all'
            || snapshot.filterSpec != null
            || normalizeProjectionScope(snapshot.scope) === 'equipment';
    }

    function hasValidSlots(snapshot, accessible, offset, limit) {
        var sparse = hasSparsePhysicalSlots(snapshot);
        var previous = -1;
        for (var i = 0; i < snapshot.slots.length; i++) {
            var slot = snapshot.slots[i];
            if (!isProjectionObject(slot)
                    || !isIntegerIn(slot.physicalSlot, 0, Math.max(-1, accessible - 1))
                    || slot.physicalSlot <= previous
                    || !sparse && slot.physicalSlot !== offset + i
                    || typeof slot.occupied !== 'boolean'
                    || !isOpaqueLease(slot.slotLease)) return false;
            previous = slot.physicalSlot;
            if (slot.occupied) {
                if (!hasExactKeys(slot, ['physicalSlot', 'occupied', 'slotLease', 'item', 'confirmProjection'])
                        || !isValidItemProjection(slot.item)
                        || !isValidConfirmProjection(slot.confirmProjection, slot.item)) return false;
            } else if (!hasExactKeys(slot, ['physicalSlot', 'occupied', 'slotLease'])) {
                return false;
            }
        }
        return true;
    }

    function isValidSnapshot(snapshot) {
        if (!isProjectionObject(snapshot)) return false;
        var expectedKeys = SNAPSHOT_KEYS.slice(0);
        if (own(snapshot, 'filterSpec')) expectedKeys.push('filterSpec');
        if (own(snapshot, 'scope')) expectedKeys.push('scope');
        if (!hasExactKeys(snapshot, expectedKeys)) return false;

        var capacity = snapshot.capacity;
        var accessible = snapshot.accessibleCapacity;
        var viewCapacity = snapshot.viewCapacity;
        var offset = snapshot.offset;
        var limit = snapshot.limit;
        var valid = isBoundedText(snapshot.containerId, 64, false)
            && (!own(snapshot, 'scope') || snapshot.scope === 'equipment')
            && isValidProjectionScope(snapshot.containerId, snapshot.scope)
            && isIntegerIn(capacity, 0, 2147483647)
            && isIntegerIn(accessible, 0, capacity)
            && isIntegerIn(viewCapacity, 0, accessible)
            && typeof snapshot.filterKey === 'string'
            && FILTER_KEYS[snapshot.filterKey] === true
            && isIntegerIn(snapshot.pageSizeHint, 1, 100)
            && typeof snapshot.locked === 'boolean'
            && snapshot.locked === (accessible <= 0)
            && isIntegerIn(snapshot.snapshotSeq, 1, MAX_SAFE_PROJECTION_NUMBER)
            && isIntegerIn(snapshot.containerEpoch, 1, MAX_SAFE_PROJECTION_NUMBER)
            && isIntegerIn(snapshot.containerVersion, 0, MAX_SAFE_PROJECTION_NUMBER)
            && isIntegerIn(offset, 0, Math.max(0, viewCapacity - 1))
            && isIntegerIn(limit, 0, 100)
            && (viewCapacity > 0 || offset === 0)
            && limit <= Math.max(0, viewCapacity - offset)
            && Array.isArray(snapshot.slots)
            && snapshot.slots.length === limit
            && Array.isArray(snapshot.filterFacets)
            && isIntegerIn(snapshot.filterItemCount, 0, accessible)
            && Array.isArray(snapshot.setFacets)
            && isIntegerIn(snapshot.setFilterItemCount, 0, accessible)
            && snapshot.setFilterItemCount <= snapshot.filterItemCount
            && (!own(snapshot, 'filterSpec')
                || isValidProjectedFilterSpec(snapshot.filterSpec)
                    && filterKeyForSpec(snapshot.filterSpec) === snapshot.filterKey);
        if (!valid || !hasValidSlots(snapshot, accessible, offset, limit)) return false;

        var facets = validateFacetArray(snapshot.filterFacets, 0, false, accessible);
        var setFacets = validateFacetArray(snapshot.setFacets, 0, true, accessible);
        return !!facets && facets.total === snapshot.filterItemCount
            && !!setFacets && setFacets.total === snapshot.setFilterItemCount;
    }

    /**
     * InventoryPanelService may clamp a now-out-of-range requested offset after an authority mutation.
     * Apart from that deterministic clamp, the returned projection must exactly describe the request.
     * snapshot.limit is the returned slice length; request.limit remains the desired page size.
     */
    function snapshotMatchesRequest(snapshot, request) {
        if (!isValidSnapshot(snapshot) || !request
                || snapshot.containerId !== String(request.containerId)
                || String(snapshot.filterKey || 'all') !== normalizeFilterKey(request.filterKey)
                || normalizeProjectionScope(snapshot.scope) !== normalizeProjectionScope(request.scope)) return false;

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
            // Store a detached, already-proven projection so later mutation of the transport
            // response cannot alter the authoritative window after validation.
            received[snapshotId] = cloneSafeProjection(snapshot);
        }
        for (i = 0; i < requests.length; i++) {
            var id = String(requests[i].containerId);
            if (!received[id]) return null;
            ordered.push(received[id]);
        }
        return ordered;
    }

    var PHYSICAL_SURFACE_SCHEMA = 'inventory-runtime.physical-surface.v1';
    var PHYSICAL_BATTLE_ACCESS = {0:true,40:true,80:true,120:true,160:true,200:true,240:true};

    function physicalSurfaceRequests(accessibleCapacity) {
        var batches = [[
            {containerId:'背包',offset:0,limit:50,filterKey:'all'},
            {containerId:'战备箱',offset:0,limit:100,filterKey:'all'}
        ]];
        if (accessibleCapacity > 100) {
            batches.push([{containerId:'战备箱',offset:100,limit:100,filterKey:'all'}]);
        }
        if (accessibleCapacity > 200) {
            batches.push([{containerId:'战备箱',offset:200,
                limit:accessibleCapacity - 200,filterKey:'all'}]);
        }
        return batches;
    }

    function exactPhysicalMetadata(snapshot, containerId, accessibleCapacity) {
        var bag = containerId === '背包';
        return !!snapshot
            && snapshot.containerId === containerId
            && snapshot.capacity === (bag ? 50 : 400)
            && snapshot.accessibleCapacity === (bag ? 50 : accessibleCapacity)
            && snapshot.viewCapacity === (bag ? 50 : accessibleCapacity)
            && snapshot.pageSizeHint === (bag ? 50 : 40)
            && snapshot.locked === (!bag && accessibleCapacity === 0)
            && snapshot.filterKey === 'all'
            && snapshot.filterSpec == null
            && normalizeProjectionScope(snapshot.scope) === 'all';
    }

    function samePhysicalWindowContract(left, right) {
        return left.capacity === right.capacity
            && left.accessibleCapacity === right.accessibleCapacity
            && left.viewCapacity === right.viewCapacity
            && left.pageSizeHint === right.pageSizeHint
            && left.locked === right.locked
            && left.filterKey === right.filterKey
            && left.containerEpoch === right.containerEpoch
            && left.containerVersion === right.containerVersion
            && left.filterItemCount === right.filterItemCount
            && left.setFilterItemCount === right.setFilterItemCount
            && JSON.stringify(left.filterFacets) === JSON.stringify(right.filterFacets)
            && JSON.stringify(left.setFacets) === JSON.stringify(right.setFacets);
    }

    /**
     * Reads the complete production bag+battle-box physical surface without changing the
     * caller's visible 40-slot battle-box page.  The first probe is exact and supplements
     * are issued only after its authority response declares A. expectedPanel is mandatory;
     * expectedPanelInstanceId should be supplied when the consumer owns it.  When it is not
     * available, the consumer's request mux has already bound each callback to its call owner,
     * and this helper additionally captures the first response instance and requires every
     * supplemental response to use that exact same instance.  Each request must synchronously
     * return its bounded callId, and the corresponding response must echo that exact value.  The
     * synchronous return is true only after the initial request returned a valid callId; invalid
     * arguments or an invalid request return contract call the callback exactly once with an error
     * and return false.
     */
    function readPhysicalInventorySurface(request, options, callback) {
        options = options || {};
        var active = typeof options.isActive === 'function' ? options.isActive : function() { return true; };
        var expectedPanel = options.expectedPanel;
        var expectedPanelInstanceId = options.expectedPanelInstanceId;
        var done = false;
        var sessionNonce = null;
        var accessibleCapacity = null;
        var battleAnchor = null;
        var lastBattleSnapshotSeq = null;
        var responseOwner = expectedPanelInstanceId == null ? null
            : expectedPanel + '|' + expectedPanelInstanceId;
        var responseCallIds = {};
        var windows = [];
        var batches = null;
        function finish(result, ignoreInactive) {
            if (done || (!ignoreInactive && !active())) return false;
            done = true;
            if (typeof callback === 'function') callback(result);
            return true;
        }
        function reject(error, ignoreInactive) {
            return finish({success:false,error:error || 'inventory_surface_invalid'}, ignoreInactive);
        }
        function validateResponse(response, expectedRequests, ordinal, expectedCallId) {
            if (!hasExactKeys(response, ['success','v','sessionNonce','snapshots','type','domain',
                    'cmd','callId','panel','panelInstanceId'])
                    || response.success !== true || response.v !== 1
                    || response.type !== 'panel_resp' || response.domain !== 'inventory'
                    || response.cmd !== 'snapshot' || response.panel !== expectedPanel
                    || !isIdentityText(response.callId, 160)
                    || response.callId !== expectedCallId
                    || !isIdentityText(response.panel, 64)
                    || !isIdentityText(response.panelInstanceId, 128)
                    || !isIdentityText(response.sessionNonce, 128)
                    || !Array.isArray(response.snapshots)
                    || response.snapshots.length !== expectedRequests.length) return null;
            if (expectedPanelInstanceId != null
                    && response.panelInstanceId !== expectedPanelInstanceId) return null;
            if (responseCallIds[response.callId]) return null;
            responseCallIds[response.callId] = true;
            var owner = response.panel + '|' + response.panelInstanceId;
            if (responseOwner == null) responseOwner = owner;
            if (owner !== responseOwner) return null;
            if (sessionNonce == null) sessionNonce = response.sessionNonce;
            if (response.sessionNonce !== sessionNonce) return null;
            for (var responseIndex = 0; responseIndex < expectedRequests.length; responseIndex++) {
                if (!response.snapshots[responseIndex]
                        || response.snapshots[responseIndex].containerId
                            !== expectedRequests[responseIndex].containerId) return null;
            }
            var ordered = validateSnapshotBatch(response.snapshots, expectedRequests, null);
            if (!ordered) return null;
            if (ordinal === 0) {
                accessibleCapacity = Number(ordered[1] && ordered[1].accessibleCapacity);
                if (PHYSICAL_BATTLE_ACCESS[accessibleCapacity] !== true) return null;
                batches = physicalSurfaceRequests(accessibleCapacity);
            }
            if (!batches || expectedRequests.length !== batches[ordinal].length) return null;
            for (var index = 0; index < ordered.length; index++) {
                var snapshot = ordered[index];
                var expected = expectedRequests[index];
                var expectedLimit = expected.containerId === '背包' ? 50
                    : Math.min(expected.limit, Math.max(0, accessibleCapacity - expected.offset));
                if (!exactPhysicalMetadata(snapshot, expected.containerId, accessibleCapacity)
                        || snapshot.offset !== expected.offset || snapshot.limit !== expectedLimit
                        || snapshot.slots.length !== expectedLimit) return null;
                for (var slotIndex = 0; slotIndex < snapshot.slots.length; slotIndex++) {
                    if (snapshot.slots[slotIndex].physicalSlot !== expected.offset + slotIndex) return null;
                }
                if (snapshot.containerId === '战备箱') {
                    if (battleAnchor == null) battleAnchor = snapshot;
                    else if (!samePhysicalWindowContract(snapshot, battleAnchor)) return null;
                    if (lastBattleSnapshotSeq != null
                            && snapshot.snapshotSeq <= lastBattleSnapshotSeq) return null;
                    lastBattleSnapshotSeq = snapshot.snapshotSeq;
                }
                windows.push(cloneSafeProjection(snapshot));
            }
            return ordered;
        }
        function complete() {
            var bagWindows = windows.filter(function(entry) { return entry.containerId === '背包'; });
            var battleWindows = windows.filter(function(entry) { return entry.containerId === '战备箱'; });
            var bag = bagWindows[0];
            var battle = battleWindows[0];
            var battleSlots = [];
            for (var windowIndex = 0; windowIndex < battleWindows.length; windowIndex++) {
                battleSlots = battleSlots.concat(battleWindows[windowIndex].slots);
            }
            if (bagWindows.length !== 1 || !bag || bag.slots.length !== 50 || !battle
                    || battleSlots.length !== accessibleCapacity) return reject('inventory_surface_incomplete');
            for (var slotIndex = 0; slotIndex < battleSlots.length; slotIndex++) {
                if (battleSlots[slotIndex].physicalSlot !== slotIndex) {
                    return reject('inventory_surface_incomplete');
                }
            }
            var mergedBattle = cloneSafeProjection(battle);
            mergedBattle.offset = 0;
            mergedBattle.limit = accessibleCapacity;
            mergedBattle.slots = cloneSafeProjection(battleSlots);
            var visibleBattle = cloneSafeProjection(battle);
            visibleBattle.offset = 0;
            visibleBattle.limit = Math.min(40, accessibleCapacity);
            visibleBattle.slots = visibleBattle.slots.slice(0, visibleBattle.limit);
            finish({success:true,snapshots:[cloneSafeProjection(bag),visibleBattle],surface:{
                schema:PHYSICAL_SURFACE_SCHEMA,sessionNonce:sessionNonce,
                accessibleCapacity:accessibleCapacity,responseCount:batches.length,
                windows:cloneSafeProjection(windows),
                snapshots:[cloneSafeProjection(bag),mergedBattle]
            }});
        }
        function issue(ordinal) {
            if (!active()) return false;
            var expectedRequests = cloneRequests(batches ? batches[ordinal]
                : physicalSurfaceRequests(0)[0]);
            var returned = false;
            var queued = false;
            var queuedDuplicate = false;
            var queuedResponse = null;
            var expectedCallId = null;
            function handleResponse(response) {
                if (done || !active()) return;
                if (!validateResponse(response, expectedRequests, ordinal, expectedCallId)) {
                    reject('inventory_surface_invalid');
                    return;
                }
                if (ordinal + 1 < batches.length) issue(ordinal + 1);
                else complete();
            }
            try {
                expectedCallId = request('snapshot', {v:1,requests:expectedRequests}, function(response) {
                    if (!returned) {
                        if (queued) queuedDuplicate = true;
                        else { queued = true; queuedResponse = response; }
                        return;
                    }
                    handleResponse(response);
                });
            } catch (_error) {
                returned = true;
                if (ordinal === 0) reject('inventory_surface_request_contract_invalid', true);
                else reject('inventory_surface_request_contract_invalid');
                return false;
            }
            returned = true;
            if (!isIdentityText(expectedCallId, 160) || queuedDuplicate) {
                if (ordinal === 0) reject('inventory_surface_request_contract_invalid', true);
                else reject('inventory_surface_request_contract_invalid');
                return false;
            }
            if (queued) handleResponse(queuedResponse);
            return true;
        }
        if (typeof request !== 'function') {
            reject('inventory_surface_unavailable', true);
            return false;
        }
        if (!isIdentityText(expectedPanel, 64)
                || (expectedPanelInstanceId != null
                    && !isIdentityText(expectedPanelInstanceId, 128))) {
            reject('inventory_surface_owner_invalid', true);
            return false;
        }
        if (!active()) {
            reject('inventory_surface_inactive', true);
            return false;
        }
        return issue(0);
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
        this._readPhysicalSurface = typeof options.readPhysicalSurface === 'function'
            ? options.readPhysicalSurface : null;
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
        this._physicalSurface = null;
        this._refreshRequiredMode = null;
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
        if (this._readPhysicalSurface) this._refreshPhysicalSurfaceWhileOwned(callback);
        else this._refreshWhileOwned(callback);
    };

    InventoryCoordinator.prototype.close = function() {
        this._sessionEpoch += 1;
        this._opened = false;
        this._invalidateOwner();
        this._refreshRequired = false;
        this._ready = false;
        this._windows = {};
        this._physicalSurface = null;
        this._refreshRequiredMode = null;
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
                if (this._requests[i].scope === 'equipment') result.scope = 'equipment';
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
                    || !isValidProjectionScope(request.containerId, request.scope)
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

    InventoryCoordinator.prototype.replaceWindowRequest = function(containerId, replacement, callback) {
        if (!this._opened || !this._ready || this._owner || this._refreshRequired) return false;
        containerId = String(containerId);
        var normalized = cloneRequests([replacement || {}])[0];
        if (!normalized || normalized.containerId !== containerId
                || !isValidProjectionScope(containerId, normalized.scope)
                || !isFinite(normalized.offset) || Math.floor(normalized.offset) !== normalized.offset
                || normalized.offset < 0
                || !isFinite(normalized.limit) || Math.floor(normalized.limit) !== normalized.limit
                || normalized.limit < 1 || normalized.limit > 100) return false;
        var index = -1;
        for (var i = 0; i < this._requests.length; i++) {
            if (this._requests[i].containerId === containerId) { index = i; break; }
        }
        if (index < 0) return false;
        var previous = cloneRequests([this._requests[index]])[0];
        this._requests[index] = normalized;
        var operation = this._setOwner('request.' + containerId);
        this._emitState();
        var self = this;
        return this._refreshWhileOwned(function(result) {
            if (!result.success) {
                self._requests[index] = previous;
                self._emitState();
                result.rolledBack = true;
            }
            if (typeof callback === 'function') callback(result);
        }, operation);
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
        if (this._readPhysicalSurface) this._refreshPhysicalSurfaceWhileOwned(callback, operation);
        else this._refreshWhileOwned(callback, operation);
        return true;
    };

    InventoryCoordinator.prototype.completeExternalSnapshots = function(operation, snapshots, callback) {
        if (!this._isActiveOperation(operation) || this._ownerCompletionStarted) return false;
        this._ownerCompletionStarted = true;
        var valid = this._applySnapshots(snapshots, [
            {containerId:'背包', offset:0, limit:50}
        ]);
        this._clearOwner(operation);
        this._ready = !!valid;
        this._refreshRequired = !valid;
        this._emitState();
        if (typeof callback === 'function') callback(valid
            ? {success:true, refreshed:false, applied:true}
            : {success:false, error:'inventory_snapshot_invalid'});
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
        if (this._readPhysicalSurface && this._refreshRequiredMode === 'physical_surface') {
            this._refreshPhysicalSurfaceWhileOwned(callback);
        } else this._refreshWhileOwned(callback);
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
                || !isValidProjectionScope(request.containerId, request.scope)
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
            if (requestNeedsAuthorityProjection(this._requests[i])) return true;
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
        if (request.scope === 'equipment') {
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
            self._refreshRequiredMode = valid ? null : 'window';
            self._emitState();
            if (typeof callback === 'function') callback(valid
                ? {success: true, refreshed: true, response: response}
                : {success: false, error: response && response.error ? response.error : 'inventory_refresh_failed'});
        });
        return true;
    };

    function sameProjectionValue(left, right) {
        if (left === right) return true;
        if (left == null || right == null || typeof left !== typeof right) return false;
        if (Array.isArray(left) || Array.isArray(right)) {
            if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length) return false;
            for (var arrayIndex = 0; arrayIndex < left.length; arrayIndex++) {
                if (!sameProjectionValue(left[arrayIndex], right[arrayIndex])) return false;
            }
            return true;
        }
        if (typeof left !== 'object') return false;
        var leftKeys = Object.keys(left).sort();
        var rightKeys = Object.keys(right).sort();
        if (leftKeys.length !== rightKeys.length) return false;
        for (var keyIndex = 0; keyIndex < leftKeys.length; keyIndex++) {
            if (leftKeys[keyIndex] !== rightKeys[keyIndex]
                    || !sameProjectionValue(left[leftKeys[keyIndex]], right[rightKeys[keyIndex]])) return false;
        }
        return true;
    }

    function requestNeedsAuthorityProjection(request) {
        return normalizeFilterKey(request && request.filterKey) !== 'all'
            || !!request && own(request, 'filterSpec')
            || normalizeProjectionScope(request && request.scope) !== 'all';
    }

    function requestsNeedAuthorityProjection(requests) {
        for (var requestIndex = 0; requestIndex < requests.length; requestIndex++) {
            if (requestNeedsAuthorityProjection(requests[requestIndex])) return true;
        }
        return false;
    }

    function authorityProjectionMatchesPhysicalSurface(response, surface, desiredRequests, currentWindows) {
        if (!surface || surface.schema !== PHYSICAL_SURFACE_SCHEMA
                || !isIdentityText(surface.sessionNonce, 128)
                || !Array.isArray(surface.windows) || !Array.isArray(surface.snapshots)
                || !response || response.success !== true || response.v !== 1
                || !isIdentityText(response.sessionNonce, 128)
                || response.sessionNonce !== surface.sessionNonce) return false;
        var ordered = validateSnapshotBatch(response.snapshots, desiredRequests, currentWindows);
        if (!ordered) return false;
        var fullByContainer = {};
        var maximumSurfaceSequence = 0;
        for (var fullIndex = 0; fullIndex < surface.snapshots.length; fullIndex++) {
            var full = surface.snapshots[fullIndex];
            if (!full || !Array.isArray(full.slots) || fullByContainer[full.containerId]) return false;
            fullByContainer[full.containerId] = full;
        }
        for (var windowIndex = 0; windowIndex < surface.windows.length; windowIndex++) {
            var surfaceWindow = surface.windows[windowIndex];
            if (!surfaceWindow || !isIntegerIn(surfaceWindow.snapshotSeq, 1, MAX_SAFE_PROJECTION_NUMBER)) return false;
            maximumSurfaceSequence = Math.max(maximumSurfaceSequence, surfaceWindow.snapshotSeq);
        }
        for (var snapshotIndex = 0; snapshotIndex < ordered.length; snapshotIndex++) {
            var snapshot = ordered[snapshotIndex];
            full = fullByContainer[snapshot.containerId];
            if (!full || snapshot.capacity !== full.capacity
                    || snapshot.accessibleCapacity !== full.accessibleCapacity
                    || snapshot.pageSizeHint !== full.pageSizeHint
                    || snapshot.locked !== full.locked
                    || snapshot.containerEpoch !== full.containerEpoch
                    || snapshot.containerVersion !== full.containerVersion
                    || snapshot.snapshotSeq <= maximumSurfaceSequence) return false;
            if (normalizeProjectionScope(snapshot.scope) === 'all'
                    && (!sameProjectionValue(snapshot.filterFacets, full.filterFacets)
                        || snapshot.filterItemCount !== full.filterItemCount
                        || !sameProjectionValue(snapshot.setFacets, full.setFacets)
                        || snapshot.setFilterItemCount !== full.setFilterItemCount)) return false;
            for (var slotIndex = 0; slotIndex < snapshot.slots.length; slotIndex++) {
                var visibleSlot = snapshot.slots[slotIndex];
                var physicalSlot = Number(visibleSlot.physicalSlot);
                if (!isIntegerIn(physicalSlot, 0, full.slots.length - 1)
                        || !sameProjectionValue(visibleSlot, full.slots[physicalSlot])) return false;
            }
        }
        return true;
    }

    function projectPhysicalSurfaceToVisibleRequests(surface, desiredRequests) {
        if (!surface || surface.schema !== PHYSICAL_SURFACE_SCHEMA
                || !Array.isArray(surface.snapshots) || !Array.isArray(desiredRequests)) return null;
        var authoritative = {};
        for (var sourceIndex = 0; sourceIndex < surface.snapshots.length; sourceIndex++) {
            var source = surface.snapshots[sourceIndex];
            if (!source || authoritative[source.containerId]) return null;
            authoritative[source.containerId] = source;
        }
        var requests = cloneRequests(desiredRequests);
        var snapshots = [];
        for (var requestIndex = 0; requestIndex < requests.length; requestIndex++) {
            var request = requests[requestIndex];
            if (requestNeedsAuthorityProjection(request)) return null;
            var full = authoritative[request.containerId];
            if (!full || !Array.isArray(full.slots)) return null;
            var pageSize = Number(request.limit);
            if (!isIntegerIn(pageSize, 1, 100)) return null;
            var viewCapacity = Number(full.viewCapacity);
            if (!isIntegerIn(viewCapacity, 0, 2147483647)) return null;
            var offset = Number(request.offset);
            if (!isIntegerIn(offset, 0, 2147483647)) return null;
            if (viewCapacity <= 0) offset = 0;
            else if (offset >= viewCapacity) {
                offset = Math.floor((viewCapacity - 1) / pageSize) * pageSize;
            }
            var limit = Math.min(pageSize, Math.max(0, viewCapacity - offset));
            var snapshot = cloneSafeProjection(full);
            snapshot.offset = offset;
            snapshot.limit = limit;
            snapshot.slots = full.slots.slice(offset, offset + limit).map(cloneSafeProjection);
            if (snapshot.slots.length !== limit) return null;
            for (var slotIndex = 0; slotIndex < snapshot.slots.length; slotIndex++) {
                if (snapshot.slots[slotIndex].physicalSlot !== offset + slotIndex) return null;
            }
            request.offset = offset;
            snapshots.push(snapshot);
        }
        return {requests:requests, snapshots:snapshots};
    }

    InventoryCoordinator.prototype._refreshPhysicalSurfaceWhileOwned = function(callback, operation) {
        var self = this;
        operation = operation || this._captureOperation();
        if (!this._readPhysicalSurface || !this._isActiveOperation(operation)) return false;
        var desiredRequests = cloneRequests(this._requests);
        function finish(result, surface) {
            if (!self._isActiveOperation(operation)) return;
            var valid = result && result.success === true;
            self._clearOwner(operation);
            self._ready = !!valid;
            self._refreshRequired = !valid;
            self._refreshRequiredMode = valid ? null : 'physical_surface';
            self._physicalSurface = valid ? cloneSafeProjection(surface) : null;
            self._emitState();
            if (typeof callback === 'function') callback(valid
                ? {success:true,refreshed:true,surface:cloneSafeProjection(surface)}
                : {success:false,error:result && result.error
                    ? result.error : 'inventory_surface_refresh_failed'});
        }
        this._readPhysicalSurface(function() { return self._isActiveOperation(operation); },
            function(result) {
                if (!self._isActiveOperation(operation)) return;
                if (!result || result.success !== true || !result.surface) {
                    finish(result || {success:false,error:'inventory_surface_refresh_failed'}, null);
                    return;
                }
                if (requestsNeedAuthorityProjection(desiredRequests)) {
                    var returned = false;
                    var queued = false;
                    var queuedDuplicate = false;
                    var queuedResponse = null;
                    var expectedCallId = null;
                    var projectionDone = false;
                    function failProjectionRequestContract() {
                        if (projectionDone || !self._isActiveOperation(operation)) return;
                        projectionDone = true;
                        finish({success:false,error:'inventory_surface_projection_request_contract_invalid'}, null);
                    }
                    function handleProjectionResponse(response) {
                        if (projectionDone || !self._isActiveOperation(operation)) return;
                        projectionDone = true;
                        if (!response || response.callId !== expectedCallId) {
                            finish({success:false,error:'inventory_surface_projection_request_contract_invalid'}, null);
                            return;
                        }
                        var valid = authorityProjectionMatchesPhysicalSurface(response, result.surface,
                            desiredRequests, self._windows)
                            && self._applySnapshots(response.snapshots, desiredRequests);
                        finish(valid ? {success:true} : {success:false,error:'inventory_surface_projection_invalid'},
                            result.surface);
                    }
                    try {
                        expectedCallId = self._request('snapshot',
                            {v:1,requests:cloneRequests(desiredRequests)}, function(response) {
                                if (!returned) {
                                    if (queued) queuedDuplicate = true;
                                    else { queued = true; queuedResponse = response; }
                                    return;
                                }
                                handleProjectionResponse(response);
                            });
                    } catch (_projectionRequestError) {
                        returned = true;
                        failProjectionRequestContract();
                        return;
                    }
                    returned = true;
                    if (!isIdentityText(expectedCallId, 160) || queuedDuplicate) {
                        failProjectionRequestContract();
                        return;
                    }
                    if (queued) handleProjectionResponse(queuedResponse);
                    return;
                }
                var visible = projectPhysicalSurfaceToVisibleRequests(result.surface, desiredRequests);
                var valid = !!visible && self._applySnapshots(visible.snapshots, visible.requests);
                finish(valid ? {success:true} : {success:false,error:'inventory_surface_projection_invalid'},
                    result.surface);
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
                if (normalizeProjectionScope(snapshot.scope) === 'equipment') {
                    this._requests[r].scope = 'equipment';
                } else {
                    delete this._requests[r].scope;
                }
                break;
            }
        }
        return true;
    };

    InventoryCoordinator.prototype.debugState = function() {
        var state = {
            opened: this._opened,
            ready: this._ready,
            busyOwner: this._owner,
            refreshRequired: this._refreshRequired,
            containers: Object.keys(this._windows),
            requests: cloneRequests(this._requests)
        };
        if (this._readPhysicalSurface) {
            state.physicalSurface = this._physicalSurface ? {
                schema:this._physicalSurface.schema,
                accessibleCapacity:this._physicalSurface.accessibleCapacity,
                responseCount:this._physicalSurface.responseCount
            } : null;
        }
        return state;
    };

    InventoryCoordinator.prototype._emitState = function() {
        this._onStateChange(this.debugState());
    };

    return {
        InventoryCoordinator: InventoryCoordinator,
        operationForIntent: operationForIntent,
        samePhysicalSlot: samePhysicalSlot,
        wireRef: wireRef,
        readPhysicalInventorySurface: readPhysicalInventorySurface,
        physicalSurfaceSchema: PHYSICAL_SURFACE_SCHEMA,
        isValidSnapshot: isValidSnapshot,
        sortMethods: SORT_METHODS,
        filterKeys: FILTER_KEYS
        ,filterMajors: FILTER_MAJORS
        ,normalizeFilterSpec: normalizeFilterSpec
        ,filterKeyForSpec: filterKeyForSpec
        ,projectionScopes: PROJECTION_SCOPES
        ,normalizeProjectionScope: normalizeProjectionScope
        ,isValidItemProjection: isValidItemProjection
        ,isValidConfirmProjection: isValidConfirmProjection
        ,isValidStableConfirmProjection: isValidStableConfirmProjection
    };
});
