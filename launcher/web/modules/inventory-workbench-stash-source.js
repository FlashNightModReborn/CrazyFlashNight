/**
 * 暂存物资来源适配器：把 CharacterBuildItemUse 的 stash 通道收敛为共享收纳
 * 工作台可消费的只读取出来源。真实身份始终来自 AS2 页面（storeId +
 * commitRevision + entryId + revision）；本模块不伪造 physicalSlot/slotLease，
 * 读路径绝不发写——migrationRequired/pendingOperationId 原样进入快照，
 * 由上层在同一 owner 下恢复；写结清后的 stash/背包双刷也由主控统一编排。
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryWorkbenchStashSource = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var PAGE_SIZE = 32;
    var OBSERVE_MS = 250;
    // UI 层统一来源标识；仅作面板内分派键，绝不进入 inventory wire。
    var CONTAINER_ID = 'stash';
    var FILTER_MAJORS = {
        all:true, weapon:true, armor:true, consumable:true,
        material:true, collection:true, other:true
    };
    var FILTER_KEYS = {
        all:true, weapon:true, armor:true, consumable:true, material:true, other:true
    };
    var TARGET_KEYS = {containerId:true, slot:true, expectedLease:true};

    function isSafeFilterValue(value) {
        return typeof value === 'string' && value.length <= 64
            && !/[\x00-\x1f\x7f]/.test(value);
    }

    /** 与 InventoryRuntime.normalizeFilterSpec 同形的最小校验，保持本模块独立可测。 */
    function normalizeSpec(spec) {
        if (spec == null) return {major:'all'};
        if (typeof spec !== 'object' || Array.isArray(spec)) return null;
        var branch = String(spec.branch || 'category');
        if (branch === 'set') {
            var setId = spec.setId == null ? '' : String(spec.setId);
            if (!isSafeFilterValue(setId) || spec.use != null || spec.subtype != null) return null;
            return setId ? {branch:'set', setId:setId} : {branch:'set'};
        }
        if (branch !== 'category') return null;
        var major = String(spec.major || 'all');
        var use = spec.use == null ? '' : String(spec.use);
        var subtype = spec.subtype == null ? '' : String(spec.subtype);
        if (FILTER_MAJORS[major] !== true
                || !isSafeFilterValue(use) || !isSafeFilterValue(subtype)
                || (major === 'all' && (use || subtype))
                || (subtype && (major !== 'weapon' || !use))) return null;
        var normalized = {major:major};
        if (spec.branch === 'category') normalized.branch = 'category';
        if (use) normalized.use = use;
        if (subtype) normalized.subtype = subtype;
        return normalized;
    }

    function filterKeyForSpec(spec) {
        if (!spec || spec.branch === 'set') return 'all';
        var major = String(spec.major || 'all');
        if (major === 'collection') return 'other';
        return FILTER_KEYS[major] === true ? major : 'all';
    }

    function sameSpec(a, b) {
        a = normalizeSpec(a); b = normalizeSpec(b);
        if (!a || !b) return a === b;
        if (String(a.branch || 'category') !== String(b.branch || 'category')) return false;
        if (a.branch === 'set') return String(a.setId || '') === String(b.setId || '');
        return String(a.major || 'all') === String(b.major || 'all')
            && String(a.use || '') === String(b.use || '')
            && String(a.subtype || '') === String(b.subtype || '');
    }

    function whole(value, min, max) {
        value = Number(value);
        if (!isFinite(value) || Math.floor(value) !== value) return null;
        if (value < min || value > max) return null;
        return value;
    }

    function normalizeTarget(target) {
        if (target == null) return null;
        if (typeof target !== 'object' || Array.isArray(target)) return false;
        for (var key in target) {
            if (!Object.prototype.hasOwnProperty.call(target, key)) continue;
            if (TARGET_KEYS[key] !== true) return false;
        }
        var slot = whole(target.slot, 0, 49);
        var lease = String(target.expectedLease || '');
        if (String(target.containerId) !== '背包' || slot === null || !lease) return false;
        return {containerId:'背包', slot:slot, expectedLease:lease};
    }

    function normalizeRef(ref) {
        if (!ref || typeof ref !== 'object') return null;
        var entryId = String(ref.entryId || '');
        var revision = whole(ref.revision, 0, 9007199254740991);
        var quantity = whole(ref.quantity, 1, 9007199254740991);
        if (!entryId || revision === null || quantity === null) return null;
        return {entryId:entryId, revision:revision, quantity:quantity};
    }

    /** 页面条目 → 展示行：只携带真实身份与物品投影，不补物理槽字段。 */
    function projectRow(entry) {
        if (!entry || typeof entry !== 'object') return null;
        var entryId = String(entry.entryId || '');
        var revision = whole(entry.revision, 0, 9007199254740991);
        var quantity = whole(entry.quantity, 1, 9007199254740991);
        if (!entryId || revision === null || quantity === null) return null;
        var item = entry.item;
        if (!item || typeof item !== 'object' || Array.isArray(item)) return null;
        return {
            occupied:true,
            containerId:CONTAINER_ID,
            entryId:entryId,
            revision:revision,
            quantity:quantity,
            item:item
        };
    }

    function create(options) {
        options = options || {};
        var itemUse = options.itemUse || null;
        if (!itemUse || typeof itemUse.requestStashPage !== 'function'
                || typeof itemUse.invokeStash !== 'function'
                || typeof itemUse.requestStashTooltip !== 'function'
                || typeof itemUse.debugState !== 'function') {
            throw new Error('Stash source requires an item-use controller with stash ports');
        }
        var onChange = typeof options.onChange === 'function' ? options.onChange : function() {};

        var _destroyed = false;
        var _generation = 0;
        var _snapshot = null;
        var _loading = false;
        var _error = null;
        var _filterSpec = {major:'all'};
        var _observedItemState = null;

        function itemState() {
            var debug = itemUse.debugState();
            return debug && debug.state ? String(debug.state) : '';
        }
        function getState() {
            var state = itemState();
            return {
                ready:!!_snapshot && !_error && state !== 'closed',
                loading:_loading,
                needsReconcile:state === 'needs_reconcile',
                error:_error,
                itemState:state
            };
        }
        function notify() {
            if (_destroyed) return;
            onChange(getState(), _snapshot);
        }

        function adopt(data) {
            var offset = whole(data.offset, 0, 9007199254740991);
            var total = whole(data.total, 0, 9007199254740991);
            var revision = whole(data.revision, 0, 9007199254740991);
            if (offset === null || total === null || revision === null
                    || typeof data.storeId !== 'string'
                    || !Array.isArray(data.entries) || data.entries.length > PAGE_SIZE) {
                return null;
            }
            // 纯空页（含 legacy 迁移前置页）允许空身份；有数据缺 storeId 才是坏页。
            if (data.entries.length > 0 && !data.storeId) return null;
            var slots = [];
            for (var i = 0; i < data.entries.length; i++) {
                var row = projectRow(data.entries[i]);
                if (!row) return null;
                slots.push(row);
            }
            var snapshot = {};
            for (var key in data) {
                if (Object.prototype.hasOwnProperty.call(data, key)) snapshot[key] = data[key];
            }
            var spec = data.filterSpec != null ? data.filterSpec : _filterSpec;
            snapshot.containerId = CONTAINER_ID;
            snapshot.limit = PAGE_SIZE;
            snapshot.capacity = total;
            snapshot.accessibleCapacity = total;
            snapshot.viewCapacity = total;
            snapshot.filterSpec = spec;
            snapshot.filterKey = filterKeyForSpec(spec);
            snapshot.slots = slots;
            return snapshot;
        }

        function load(offset, callback) {
            if (typeof callback !== 'function') callback = function() {};
            // 每次 load 至多回调一次；同步失败与异步结清共用同一闸门。
            var called = false;
            function done(snapshot, response) {
                if (called) return;
                called = true;
                callback(snapshot, response);
            }
            if (_destroyed || itemState() === 'closed') {
                done(null, null);
                return null;
            }
            var generation = ++_generation;
            _loading = true;
            _error = null;
            notify();
            function settle(snapshot, response) {
                if (_destroyed || generation !== _generation) return;
                _loading = false;
                if (snapshot) {
                    _snapshot = snapshot;
                    _error = null;
                } else {
                    _error = response && response.error
                        ? String(response.error) : 'invalid_response';
                }
                notify();
                done(snapshot, response);
            }
            var started;
            try {
                // filterSpec 始终显式随请求上行（含 {major:'all'}），换取全局
                // filterFacets/filterItemCount/unfilteredTotal；无参旧指纹由
                // transport 层按需保留，与本适配器无关。
                started = itemUse.requestStashPage(offset, function(data, response) {
                    if (_destroyed || generation !== _generation) return;
                    if (!data) {
                        settle(null, response);
                        return;
                    }
                    var snapshot = adopt(data);
                    if (!snapshot) {
                        settle(null, response || {success:false, error:'invalid_response'});
                        return;
                    }
                    // 权威页翻空时收敛到最后有效页；新请求升代，迟到回包仍被隔离。
                    if (snapshot.offset > 0 && !snapshot.slots.length) {
                        load(Math.max(0,
                            Math.floor((snapshot.capacity - 1) / PAGE_SIZE) * PAGE_SIZE),
                            done);
                        return;
                    }
                    settle(snapshot, response);
                }, _filterSpec);
            } catch (error) {
                started = null;
            }
            if (!started) {
                if (generation === _generation && !_destroyed) {
                    _loading = false;
                    _error = 'unavailable';
                    notify();
                }
                done(null, null);
                return null;
            }
            return started;
        }

        function getRow(entryId) {
            entryId = String(entryId || '');
            if (!entryId || !_snapshot) return null;
            var slots = _snapshot.slots || [];
            for (var i = 0; i < slots.length; i++) {
                if (slots[i].entryId === entryId) return slots[i];
            }
            return null;
        }

        function ref(row, quantity) {
            if (!row || typeof row !== 'object') return null;
            var current = getRow(row.entryId);
            if (!current || current.revision !== row.revision) return null;
            var equipment = current.item && String(current.item.itemKind) === 'equipment';
            var amount;
            if (equipment) {
                if (quantity != null && quantity !== 1) return null;
                amount = 1;
            } else if (quantity == null) {
                amount = current.quantity;
            } else {
                amount = whole(quantity, 1, current.quantity);
                if (amount === null) return null;
            }
            return {
                entryId:current.entryId,
                revision:current.revision,
                quantity:amount
            };
        }

        function take(refs, target, callback) {
            if (_destroyed || !_snapshot) return null;
            if (!Array.isArray(refs) || !refs.length || refs.length > PAGE_SIZE) return null;
            var entries = [];
            for (var i = 0; i < refs.length; i++) {
                var entry = normalizeRef(refs[i]);
                if (!entry) return null;
                var row = getRow(entry.entryId);
                if (!row || row.revision !== entry.revision || entry.quantity > row.quantity) {
                    return null;
                }
                entries.push(entry);
            }
            var fields = {
                storeId:String(_snapshot.storeId),
                expectedRevision:Number(_snapshot.revision),
                entries:entries
            };
            if (target != null) {
                if (entries.length !== 1) return null;
                var normalizedTarget = normalizeTarget(target);
                if (!normalizedTarget) return null;
                fields.target = normalizedTarget;
            }
            // 原样透传：不自动刷新、不释放主控 conflict owner；
            // callback(result, committed) 与启动返回值都保持 ItemUse 原契约。
            return itemUse.invokeStash('stashTake', fields, callback);
        }

        function tooltip(row, callback) {
            if (typeof callback !== 'function') callback = function() {};
            if (_destroyed || !_snapshot || !row || getRow(row.entryId) !== row) {
                callback(null);
                return null;
            }
            var started;
            try {
                started = itemUse.requestStashTooltip(String(_snapshot.storeId), row, function(data) {
                    callback(data && data.success === true && data.tooltip
                        ? Object.assign({success:true}, data.tooltip) : null);
                });
            } catch (error) {
                started = null;
            }
            if (!started) callback(null);
            return started;
        }

        function reconcile() {
            return typeof itemUse.reconcile === 'function' ? itemUse.reconcile() : null;
        }

        // 唯一的轻量观察：ItemUse 无公开订阅口，250ms 轮询只在权威状态翻变时通告。
        var _timer = typeof setInterval === 'function' ? setInterval(function() {
            if (_destroyed) return;
            var state = itemState();
            if (state !== _observedItemState) {
                _observedItemState = state;
                notify();
            }
        }, OBSERVE_MS) : null;
        if (_timer && typeof _timer.unref === 'function') _timer.unref();
        _observedItemState = itemState();

        function destroy() {
            if (_destroyed) return false;
            _destroyed = true;
            _generation++;
            if (_timer) clearInterval(_timer);
            _timer = null;
            _loading = false;
            return true;
        }

        return {
            containerId:CONTAINER_ID,
            pageSize:PAGE_SIZE,
            refresh:function(callback) {
                return load(_snapshot ? Number(_snapshot.offset) || 0 : 0, callback);
            },
            setPage:function(offset, callback) {
                var next = whole(offset, 0, 9007199254740991);
                if (next === null) {
                    if (typeof callback === 'function') callback(null, null);
                    return null;
                }
                return load(next, callback);
            },
            setFilter:function(filterSpec, callback) {
                var normalized = normalizeSpec(filterSpec);
                if (normalized === null) {
                    if (typeof callback === 'function') callback(null, null);
                    return null;
                }
                _filterSpec = normalized;
                return load(0, callback);
            },
            getSnapshot:function() { return _snapshot; },
            getState:getState,
            getRow:getRow,
            ref:ref,
            take:take,
            tooltip:tooltip,
            reconcile:reconcile,
            sameFilterSpec:function(a, b) { return sameSpec(a, b); },
            destroy:destroy
        };
    }

    return {
        CONTAINER_ID:CONTAINER_ID,
        PAGE_SIZE:PAGE_SIZE,
        create:create,
        normalizeFilterSpec:normalizeSpec,
        normalizeTarget:normalizeTarget
    };
});
