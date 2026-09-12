/** Storage source routing and shared write ownership; rendering stays in OwnedView. */
(function(root, factory) {
    'use strict';
    var api = factory(root);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryWorkbenchStorageSource = api;
})(typeof window !== 'undefined' ? window : globalThis, function(root) {
    'use strict';
    function create(options) {
        var coordinator = options.coordinator, source = 'container', adapter = null, itemUse = null;
        var destroyed = false, generation = 0, opening = false, pending = null;
        var page = null, projection = null;
        function changed() { if (!destroyed && options.onChange) options.onChange(); }
        function live(epoch) { return !destroyed && epoch === generation; }
        function baseState() { return coordinator.debugState(); }
        function available() {
            var base = baseState();
            var leaf = adapter && adapter.getState();
            return !destroyed && !opening && !pending && base.ready && !base.busyOwner && !base.refreshRequired
                && !(leaf && (leaf.loading || /^(write_pending|query_pending|needs_reconcile)$/.test(leaf.itemState)));
        }
        function getWindow(id) {
            if (id !== 'stash') return coordinator.getWindow(id);
            var current = adapter && adapter.getSnapshot();
            if (!current) return null;
            if (current !== page) {
                page = current;
                var spec = current.filterSpec || {major:'all'};
                var total = current.unfilteredTotal == null ? current.total : current.unfilteredTotal;
                projection = Object.assign({}, current, {containerId:'stash', limit:32,
                    capacity:total, accessibleCapacity:total, viewCapacity:current.total,
                    filterKey:spec.branch === 'set' ? 'all' : spec.major === 'collection' ? 'other' : spec.major});
            }
            return projection;
        }
        function getRequest(id) {
            if (id !== 'stash') return coordinator.getRequest(id);
            var snapshot = getWindow(id);
            return {containerId:'stash', offset:snapshot ? snapshot.offset : 0, limit:32,
                filterSpec:snapshot ? snapshot.filterSpec : {major:'all'},
                filterKey:snapshot ? snapshot.filterKey : 'all'};
        }
        function getRow(id, key) {
            if (id === 'stash') return adapter ? adapter.getRow(key) : null;
            var snapshot = coordinator.getWindow(id), rows = snapshot && snapshot.slots || [];
            for (var i = 0; i < rows.length; i++) if (rows[i].physicalSlot === Number(key)) return rows[i];
            return null;
        }
        function slotRef(id, row, quantity) {
            if (!row) return null;
            if (id === 'stash') {
                var ref = adapter && adapter.ref(row, quantity), snapshot = getWindow(id);
                return ref && snapshot ? Object.assign({kind:'stash', storeId:snapshot.storeId,
                    item:row.item, occupied:true}, ref) : null;
            }
            var physical = {containerId:id, slot:row.physicalSlot, expectedLease:row.slotLease,
                occupied:!!row.occupied, item:row.item};
            if (quantity !== undefined) physical.quantity = quantity;
            return physical;
        }
        function state(base) {
            var result = Object.assign({}, base);
            if (opening) { result.ready = false; return result; }
            if (source !== 'stash' || !adapter) return result;
            var leaf = adapter.getState(), snapshot = getWindow('stash');
            var recovery = snapshot && snapshot.pendingOperationId;
            var migration = snapshot && snapshot.migrationRequired;
            result.needsReconcile = !!leaf.needsReconcile || !!recovery;
            if (!leaf.ready || leaf.loading || pending || recovery || migration) result.ready = false;
            if (pending || recovery || leaf.needsReconcile) result.busyOwner = result.busyOwner || 'stash.take';
            if (leaf.needsReconcile || recovery) result.repairLabel = '核对领取结果';
            else if (pending && pending.phase !== 'writing' || leaf.error) result.repairLabel = '重试同步';
            else if (migration) result.repairLabel = '恢复暂存物资';
            return result;
        }
        function switchSource(next, args, callback) {
            if (next !== 'container' && next !== 'stash' || !available()) return false;
            if (source === next) { if (callback) callback(true); return true; }
            var epoch = ++generation;
            if (next === 'container') {
                if (adapter) adapter.destroy();
                adapter = null; itemUse = null; page = projection = null; source = next;
                changed(); if (callback) callback(true); return true;
            }
            itemUse = args && args.itemUse;
            var factory = options.adapterFactory || function(args) { return root.InventoryWorkbenchStashSource.create(args); };
            opening = true;
            try { adapter = factory({itemUse:itemUse, onChange:changed}); }
            catch (_) { opening = false; adapter = null; itemUse = null; changed(); if (callback) callback(false); return false; }
            changed();
            var completed = false;
            var started = adapter.refresh(function(snapshot) {
                if (!live(epoch) || completed) return;
                completed = true; opening = false;
                if (snapshot) source = 'stash';
                else { adapter.destroy(); adapter = null; itemUse = null; }
                changed(); if (callback) callback(!!snapshot);
            });
            if (!started && !completed) {
                opening = false; adapter.destroy(); adapter = null; itemUse = null;
                changed(); if (callback) callback(false);
            }
            return !!started || completed;
        }
        function read(method, value, callback) {
            if (!available() || !adapter) return false;
            var epoch = generation;
            return !!adapter[method](value, function(snapshot, response) {
                if (!live(epoch)) return;
                changed(); if (callback) callback(snapshot ? {success:true} : response || {success:false, error:'unavailable'});
            });
        }
        function setWindow(id, offset, limit, callback) {
            return id === 'stash' ? read('setPage', offset, callback) : coordinator.setWindow(id, offset, limit, callback);
        }
        function setFilterSpec(id, spec, callback) {
            return id === 'stash' ? read('setFilter', spec, callback) : coordinator.setFilterSpec(id, spec, callback);
        }
        function finish(operation) {
            if (pending !== operation || !live(operation.epoch)) return;
            pending = null; changed();
            if (operation.callback) operation.callback(operation.result);
        }
        function bagAdopted(operation, result) {
            if (pending !== operation || !live(operation.epoch)) return;
            if (!result || !result.success) { operation.phase = 'bagRetry'; changed(); return; }
            finish(operation);
        }
        function refreshAfterWrite(operation) {
            if (pending !== operation || !live(operation.epoch)) return false;
            operation.phase = 'stash'; changed();
            return adapter.refresh(function(snapshot) {
                if (pending !== operation || !live(operation.epoch)) return;
                if (!snapshot) { operation.phase = 'stashRetry'; changed(); return; }
                if (snapshot.pendingOperationId) {
                    operation.recoveryId = snapshot.pendingOperationId;
                    operation.phase = 'recovery'; changed(); return;
                }
                operation.phase = 'bag'; changed();
                if (!coordinator.completeExternalWrite(operation.owner, true, function(result) { bagAdopted(operation, result); })) {
                    operation.phase = 'bagRetry'; changed();
                }
            });
        }
        function begin(callback) {
            var owner = coordinator.beginExternalWrite('stash.take');
            if (!owner) return null;
            pending = {owner:owner, epoch:generation, phase:'writing', callback:callback,
                result:{success:true, refreshed:true}};
            changed(); return pending;
        }
        function settle(operation, result, committed) {
            if (pending !== operation || !live(operation.epoch) || operation.phase !== 'writing') return;
            operation.result = Object.assign({}, result, {success:committed === true || !!(result && result.success)});
            refreshAfterWrite(operation);
        }
        function cancelUnsent(operation) {
            if (pending !== operation || operation.phase !== 'writing') return;
            coordinator.completeExternalWrite(operation.owner, false, function() {
                operation.result = {success:false, error:'invalid_payload'}; finish(operation);
            });
        }
        function take(refs, target, callback) {
            if (!available() || source !== 'stash' || !state(baseState()).ready) return false;
            var snapshot = getWindow('stash');
            if (!Array.isArray(refs) || refs.some(function(ref) { return !ref || ref.storeId !== snapshot.storeId; })) return false;
            var entries = refs.map(function(ref) { return {entryId:ref.entryId, revision:ref.revision, quantity:ref.quantity}; });
            var exactTarget = target == null ? null : {containerId:target.containerId, slot:target.slot, expectedLease:target.expectedLease};
            var operation = begin(callback);
            if (!operation) return false;
            var started = adapter.take(entries, exactTarget, function(result, committed) { settle(operation, result, committed); });
            if (!started) cancelUnsent(operation);
            return !!started;
        }
        function resume(operation) {
            operation.phase = 'recovery'; changed();
            return itemUse.resumeStash(operation.recoveryId, function(result) {
                if (pending !== operation || !live(operation.epoch)) return;
                if (!result || !result.success) { changed(); return; }
                refreshAfterWrite(operation);
            });
        }
        function retry(callback) {
            if (destroyed || opening || source !== 'stash' || !adapter) return false;
            if (pending) {
                if (pending.phase === 'writing') return adapter.getState().needsReconcile ? !!adapter.reconcile() : false;
                if (pending.phase === 'recovery') return !!resume(pending);
                if (pending.phase === 'stashRetry') return !!refreshAfterWrite(pending);
                if (pending.phase === 'bagRetry') {
                    var current = pending;
                    return coordinator.retryRefresh(function(result) { bagAdopted(current, result); });
                }
                return false;
            }
            if (baseState().refreshRequired) return coordinator.retryRefresh(callback);
            if (!available()) return false;
            var snapshot = getWindow('stash'), operation = begin(callback);
            if (!operation) return false;
            if (snapshot && snapshot.pendingOperationId) {
                operation.recoveryId = snapshot.pendingOperationId;
                return !!resume(operation);
            }
            if (snapshot && snapshot.migrationRequired) {
                var started = itemUse.invokeStash('stashMigrate', {storeId:snapshot.storeId,
                    expectedRevision:snapshot.revision}, function(result, committed) { settle(operation, result, committed); });
                if (!started) cancelUnsent(operation);
                return !!started;
            }
            return !!refreshAfterWrite(operation);
        }
        function destroy() {
            destroyed = true; generation++;
            if (adapter) adapter.destroy();
            adapter = null; itemUse = null; pending = null; page = projection = null;
        }
        return {getSource:function() { return source; }, switchSource:switchSource,
            getWindow:getWindow, getRequest:getRequest, getRow:getRow, slotRef:slotRef, state:state,
            setWindow:setWindow, setFilterSpec:setFilterSpec, take:take, retry:retry, destroy:destroy,
            tooltip:function(row, callback) { return adapter ? adapter.tooltip(row, callback) : null; }};
    }
    return {create:create};
});
