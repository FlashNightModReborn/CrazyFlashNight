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
        return '<div class="kshop-tt-header"><b>' + safe(item.displayName || '未知物品') + '</b></div>'
            + '<div class="kshop-tt-divider"></div><span class="kshop-tt-dim">类型</span> ' + safe(type) + '<br>'
            + (Number(item.quantity) > 1 ? '<span class="kshop-tt-dim">数量</span> ' + Number(item.quantity) + '<br>' : '')
            + (Number(item.enhancementLevel) > 0 ? '<span class="kshop-tt-dim">强化</span> +' + Number(item.enhancementLevel) + '<br>' : '')
            + '<div class="kshop-tt-loading">加载中…</div>';
    }

    function richTooltip(item, data, tooltip) {
        item = item || {};
        data = data || {};
        var iconKey = data.iconName || item.icon || '';
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

    function storageHelpSpec(containerId) {
        var target = containerId === '战备箱' ? '战备箱' : '仓库';
        return {
            kind:'inventory-storage-help',
            title:target + '收纳帮助',
            message:'常用操作\n• 精确放置：先选择一侧物品，再选择另一侧目标格；也可以直接拖拽到目标位置。\n• 单件快移：按住 Ctrl 单击物品，系统会优先合并同名堆叠，再寻找首个空格。',
            detail:'批量处理\n• 点击下方“批量存入”或“批量取出”，再依次点击多个物品完成暂存；重复点击可取消。\n• 确认计数后点击“执行转移”，队列会逐件使用现有自动落位规则。\n• Esc 会先取消尚未执行的批次；任一物品状态过期、目标已满或同步失败时，队列会停止并重新核对。\n\n浏览\n• 紧凑模式适合快速收纳，完整模式显示名称与状态；筛选、分页和整理都基于完整权威容器。',
            actions:[{id:'close', label:'知道了', primary:true, audioCue:'confirm'}]
        };
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

    function authorityInteraction(state, allowAutoTransfer) {
        state = state || {};
        if (state.refreshRequired) {
            return {inspectable:true, actionable:false, reason:'库存同步失败，请先重试。'};
        }
        if (!state.ready) {
            return {inspectable:true, actionable:false, reason:'库存正在同步，请稍候。'};
        }
        if (state.busyOwner && !(allowAutoTransfer
                && state.busyOwner === 'inventory.autoTransfer')) {
            return {inspectable:true, actionable:false, reason:'库存正在处理另一项操作。'};
        }
        return {inspectable:true, actionable:true, reason:''};
    }

    function ensureReasonNode(node) {
        var reason = node && node.querySelector
            ? node.querySelector('.workbench-entity-lock-reason') : null;
        if (reason) return reason;
        reason = document.createElement('span');
        reason.className = 'workbench-entity-lock-reason';
        reason.hidden = true;
        node.appendChild(reason);
        return reason;
    }

    function ensureActionReasonNode(action) {
        if (action && action.__workbenchActionReasonNode) {
            return action.__workbenchActionReasonNode;
        }
        var reason = document.createElement('span');
        reason.className = 'workbench-entity-lock-reason workbench-entity-action-lock-reason';
        reason.hidden = true;
        if (action && action.parentNode) action.parentNode.insertBefore(reason, action.nextSibling);
        if (action) action.__workbenchActionReasonNode = reason;
        return reason;
    }

    function projectNode(entityTile, node, projection, reasonNode) {
        return entityTile.projectInteraction(node, {
            inspectable:projection.inspectable,
            actionable:projection.actionable,
            reason:projection.reason,
            reasonNode:reasonNode
        });
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
        var interaction = authorityInteraction(options.getAuthorityState(), false);
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
            bindItem:function(node, slot) {
                options.bindSlot(containerId, node, slot, function() { return interaction; });
            },
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
            keyOf:function(slot) { return slot && slot.physicalSlot; },
            interaction:interaction,
            onInteractionChange:function(projection) {
                interaction = projection;
                if (typeof options.onInteractionChange === 'function') {
                    options.onInteractionChange(containerId, projection, ownedShell.view);
                }
            }
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
        authorityInteraction:authorityInteraction,
        ensureReasonNode:ensureReasonNode,
        ensureActionReasonNode:ensureActionReasonNode,
        projectNode:projectNode,
        primitiveProjection:primitiveProjection,
        basicTooltip:basicTooltip,
        richTooltip:richTooltip,
        iconHtml:iconHtml,
        errorMessage:errorMessage,
        storageHelpSpec:storageHelpSpec,
        createView:createView,
        createToolbar:createToolbar
    };
});
