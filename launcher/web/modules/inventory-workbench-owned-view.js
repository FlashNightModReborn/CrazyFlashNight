/** Owned-inventory view composition; all reads and writes arrive through explicit ports. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryWorkbenchOwnedView = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function countOccupied(slots) {
        var count = 0;
        slots = slots || [];
        for (var i = 0; i < slots.length; i++) if (slots[i].occupied) count++;
        return count;
    }

    function presentationFor(containerId, snapshot) {
        var filtered = snapshot && String(snapshot.filterKey || 'all') !== 'all';
        var emptyText = filtered ? '当前分类暂无物品' : '本页暂无物品';
        if (containerId === '战备箱' && snapshot && Number(snapshot.accessibleCapacity) <= 0) {
            emptyText = '战备箱尚未解锁';
        }
        var meta = !snapshot ? '同步中'
            : containerId === '战备箱' && Number(snapshot.accessibleCapacity) <= 0 ? '未解锁'
            : containerId === '背包' ? countOccupied(snapshot.slots) + ' / ' + Number(snapshot.accessibleCapacity || snapshot.capacity) : '';
        return {emptyText:emptyText, meta:meta};
    }

    function createView(options) {
        options = options || {};
        var UI = options.inventoryUI;
        var Components = options.components;
        if (!UI || !Components || typeof options.getSnapshot !== 'function'
                || typeof options.getAuthorityState !== 'function' || typeof options.slotRef !== 'function'
                || typeof options.bindSlot !== 'function' || typeof options.iconHtml !== 'function'
                || typeof options.samePhysicalSlot !== 'function') {
            throw new Error('Inventory owned view requires presentation adapters and explicit state ports');
        }
        var containerId = String(options.containerId);
        var ownedShell = new UI.OwnedInventoryViewShell({
            containerId:containerId,
            instanceKey:'inventory:' + containerId,
            itemModel:'owned',
            getItems:function() {
                var snapshot = options.getSnapshot(containerId);
                return snapshot ? snapshot.slots : [];
            },
            keyOf:function(slot) { return slot.physicalSlot; },
            renderItem:function(slot) {
                return UI.renderOwnedSlot(containerId, slot, {
                    iconHtml:options.iconHtml,
                    allowDiscard:containerId === '背包'
                });
            },
            bindItem:function(node, slot) { options.bindSlot(containerId, node, slot); },
            exportOffer:function(slot) {
                var state = options.getAuthorityState() || {};
                if (!slot || !slot.occupied || !state.ready || state.busyOwner || state.refreshRequired) return null;
                return {subjectKind:'ownedSlot', sourceRef:options.slotRef(containerId, slot),
                    offeredOperations:['inventory.transfer']};
            },
            probeAccept:function(offer, hit) {
                var target = hit && hit.item;
                if (!offer || offer.subjectKind !== 'ownedSlot' || !target) return {accepted:false, reason:'unsupported'};
                var targetRef = options.slotRef(containerId, target);
                if (options.samePhysicalSlot(offer.sourceRef, targetRef)) return {accepted:false, reason:'same_slot'};
                return {accepted:true, operationId:'inventory.transfer', targetRef:targetRef,
                    hint:target.occupied ? 'merge-or-swap' : 'move'};
            },
            title:options.title,
            meta:'同步中',
            className:'inventory-owned-view inventory-owned-' + (containerId === '背包' ? 'backpack' : 'warehouse')
                + (containerId === '战备箱' ? ' inventory-owned-battlebox' : ''),
            gridClassName:'inventory-owned-grid',
            emptyText:'正在同步库存…',
            allowedSlots:containerId === '背包' ? ['L'] : ['R'],
            layoutMode:options.layoutMode || 'full',
            densityController:options.densityController
        });
        var pane = new Components.OwnedInventoryPane({
            view:ownedShell.view,
            shell:ownedShell,
            getSnapshot:function() { return options.getSnapshot(containerId); },
            keyOf:function(slot) { return slot && slot.physicalSlot; }
        });
        return {view:pane.view, pane:pane};
    }

    function createToolbar(options) {
        options = options || {};
        var UI = options.inventoryUI;
        var document = options.document;
        if (!UI || !document || !options.view || typeof options.beforeFilter !== 'function'
                || typeof options.setFilter !== 'function' || typeof options.setFilterSpec !== 'function') {
            throw new Error('Inventory toolbar requires presentation adapters and filter ports');
        }
        var containerId = String(options.containerId);
        var toolbar = document.createElement('div');
        toolbar.className = 'inventory-warehouse-toolbar inventory-container-toolbar'
            + (options.pager ? ' inventory-battlebox-toolbar' : ' inventory-no-pager');
        var controls = new UI.InventorySortControls({
            filterOptions:UI.categoryFilterOptions(), filterLabel:'', filterAriaLabel:containerId + '分类筛选',
            authorityOptions:UI.authoritySortOptions(), authorityLabel:'', authorityAriaLabel:containerId + '整理方式',
            commitLabel:'整理' + containerId,
            onFilterChange:function(filterKey) {
                options.beforeFilter();
                if (!options.setFilter(containerId, filterKey, function(result) {
                    options.render();
                    if (!result.success) {
                        var request = options.getRequest(containerId);
                        controls.setFilterKey(request ? request.filterKey : 'all');
                        options.toast(containerId + '筛选失败，请重试。');
                    }
                })) {
                    var request = options.getRequest(containerId);
                    controls.setFilterKey(request ? request.filterKey : 'all');
                }
            },
            onFilterSpecChange:function(filterSpec) {
                options.beforeFilter();
                if (!options.setFilterSpec(containerId, filterSpec, function(result) {
                    options.render();
                    if (!result.success) {
                        controls.rejectFilterChange(options.getSnapshot(containerId));
                        options.toast(containerId + '筛选失败，请重试。');
                    }
                })) controls.rejectFilterChange(options.getSnapshot(containerId));
            },
            onAuthorityCommit:function(methodName, label) { options.confirmSort(containerId, methodName, label); }
        });
        if (options.pager) toolbar.appendChild(options.pager.root);
        toolbar.appendChild(controls.root);
        if (options.view.ownedInventoryShell) options.view.ownedInventoryShell.setToolbar(toolbar, controls, options.pager);
        return {root:toolbar, controls:controls};
    }

    return {countOccupied:countOccupied, presentationFor:presentationFor,
        createView:createView, createToolbar:createToolbar};
});
