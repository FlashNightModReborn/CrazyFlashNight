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

    function primitiveProjection(item) {
        var projection = {};
        item = item || {};
        for (var key in item) {
            if (!Object.prototype.hasOwnProperty.call(item, key)) continue;
            var value = item[key];
            if (value == null || typeof value === 'string' || typeof value === 'number'
                    || typeof value === 'boolean') projection[key] = value;
        }
        return projection;
    }

    function basicTooltip(item, escapeHtml) {
        item = item || {};
        var safe = typeof escapeHtml === 'function' ? escapeHtml : String;
        var type = item.majorType || item.use || item.itemKind || '物品';
        return '<div class="kshop-tt-header"><b>' + safe(item.displayName || item.name || '未知物品') + '</b></div>'
            + '<div class="kshop-tt-divider"></div><span class="kshop-tt-dim">类型</span> ' + safe(type) + '<br>'
            + (Number(item.quantity) > 1 ? '<span class="kshop-tt-dim">数量</span> ' + Number(item.quantity) + '<br>' : '')
            + (Number(item.enhancementLevel) > 0 ? '<span class="kshop-tt-dim">强化</span> +' + Number(item.enhancementLevel) + '<br>' : '')
            + '<div class="kshop-tt-loading">加载中…</div>';
    }

    function richTooltip(item, data, tooltip) {
        item = item || {};
        data = data || {};
        var iconKey = data.iconName || item.icon || item.name;
        return tooltip.buildItemRichHtml({
            iconHtml:tooltip.dynamicIconHtml(iconKey),
            iconUrl:tooltip.staticIconUrl(iconKey),
            introHTML:data.introHTML || '',
            descHTML:data.descHTML || '',
            rootClass:'kshop-tt-rich-context inventory-owned-tt-context',
            layoutType:tooltip.inferLayoutType(data.itemType || item.majorType || item.use)
        });
    }

    function iconHtml(iconName, className, icons) {
        var html = icons && icons.html
            ? icons.html(iconName, className || 'kshop-icon', ' onerror="this.style.display=\'none\'"') : '';
        return html || '<div class="' + (className || 'kshop-icon') + ' kshop-icon-placeholder"></div>';
    }

    function errorMessage(error) {
        if (error === 'slot_locked') return '该容器槽位尚未解锁。';
        if (error === 'stale_state') return '库存已经变化，请重试。';
        if (error === 'client_timeout' || error === 'timeout') return '库存响应超时，请重试。';
        if (error === 'inventory_refresh_failed') return '库存同步失败，请重试。';
        return '操作失败，请重试。';
    }

    function presentationFor(containerId, snapshot) {
        var equipmentScope = snapshot && String(snapshot.scope || 'all') === 'equipment';
        var filtered = snapshot && (String(snapshot.filterKey || 'all') !== 'all' || equipmentScope);
        var emptyText = equipmentScope ? '背包中暂无可调制装备'
            : filtered ? '当前分类暂无物品' : '本页暂无物品';
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

    return {
        countOccupied:countOccupied,
        presentationFor:presentationFor,
        primitiveProjection:primitiveProjection,
        basicTooltip:basicTooltip,
        richTooltip:richTooltip,
        iconHtml:iconHtml,
        errorMessage:errorMessage,
        createView:createView,
        createToolbar:createToolbar
    };
});
