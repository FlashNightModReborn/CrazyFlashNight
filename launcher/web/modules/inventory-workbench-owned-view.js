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
            document:data.document,
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

    function resolveExactSourceSlot(item, source, resolveSlot) {
        if (!item || !source || source.sourceKind !== 'inventory'
                || source.containerId !== '背包' || typeof resolveSlot !== 'function') return null;
        var physicalSlot = Number(source.slot);
        var expectedLease = String(source.expectedLease || '');
        if (!isFinite(physicalSlot) || Math.floor(physicalSlot) !== physicalSlot
                || physicalSlot < 0 || physicalSlot > 49 || !expectedLease) return null;
        var slot = resolveSlot('背包', physicalSlot);
        if (!slot || !slot.occupied || !slot.item
                || String(slot.slotLease || '') !== expectedLease) return null;
        var sourceName = String(item.name || '');
        var slotName = String(slot.item.name || '');
        return sourceName && slotName && sourceName !== slotName ? null : slot;
    }

    function storageHelpSpec(containerId) {
        var target = containerId === 'stash' ? '暂存物资' : containerId === '战备箱' ? '战备箱' : '仓库';
        return {
            kind:'inventory-storage-help',
            title:target + '收纳帮助',
            message:'常用操作\n• 选中物品后，点击下方“' + (containerId === 'stash' ? '领取' : '存入 / 取出') + '”即可自动归位，也可按住 Ctrl 单击物品。\n• 精确放置：先选择物品，再选择另一侧目标格；也可以直接拖拽到目标位置。',
            detail:'数量与批量\n• 选中堆叠物品后，直接使用下方滑条或输入框调整数量，再领取或移动。\n• 点击下方批量模式，再依次选择本页物品；重复点击取消，点击“执行转移”一次提交所选项。\n• 切页、筛选或切换来源会清空未执行的选择。Esc 先取消选择，再返回。\n\n' + (containerId === 'stash' ? '暂存物资只取不存；材料、情报、药剂等点击“领取”会放入适用位置。背包放不下的物品继续保留，仍可领取能放下的其他物品。' : '自动归位优先合并同名堆叠，再寻找空格；批量在首个放不下的物品前停止。'),
            actions:[{id:'close', label:'知道了', primary:true, audioCue:'activate'}]
        };
    }

    function stashResultMessage(result) {
        if (!result || !result.success) return errorMessage(result && result.error);
        var data = result.data || result, accepted = data.accepted || [], blocked = data.blocked || [];
        if (!accepted.length && !blocked.length) return '暂存与背包已同步。';
        var destinations = {}, reasons = {}, parts = [];
        accepted.forEach(function(row) {
            var target = typeof row.destination === 'string' ? row.destination : row.destination && row.destination.containerId;
            target = target || '对应位置';
            destinations[target] = (destinations[target] || 0) + Number(row.quantity || 0);
        });
        Object.keys(destinations).forEach(function(key) { parts.push(destinations[key] + ' 件已放入' + key); });
        var labels = {inventory_full:'背包已满', target_full:'背包已满', target_stale:'目标格已变化',
            target_occupied:'目标格已被占用', target_incompatible:'需自动归位，请选中后点击“领取”'};
        blocked.forEach(function(row) { reasons[labels[row.reason] || '当前无法领取'] = true; });
        if (blocked.length) parts.push(blocked.length + ' 项仍保留在暂存（' + Object.keys(reasons).join('、') + '）');
        return parts.join('；') + '。';
    }

    function bindTooltip(options) {
        var slot = options.slot, item = slot.item || {};
        return options.tooltip.bindAsyncHover(options.node, {
            profile:'dense-inspect', cache:options.cache,
            key:options.containerId + ':' + (slot.entryId || slot.physicalSlot) + ':' + String(slot.revision || slot.slotLease || ''),
            item:item, isSuppressed:options.isSuppressed,
            renderBasic:function(value) { return basicTooltip(value, options.escapeHtml); },
            renderRich:function(value, data) { return richTooltip(value, data, options.richTooltip); },
            fetch:function(_, callback) { options.fetch(callback); }
        });
    }

    function projectQuickSelection(root, views, quick) {
        if (!root) return;
        var nodes = root.querySelectorAll('.inventory-slot-card');
        for (var i = 0; i < nodes.length; i++) nodes[i].classList.remove('quick-transfer-pending', 'quick-transfer-inflight');
        Object.keys(quick.entries).forEach(function(key) {
            var entry = quick.entries[key], view = views[entry.containerId];
            if (!view) return;
            var tiles = view.root.querySelectorAll('[data-workbench-key]');
            for (var n = 0; n < tiles.length; n++) {
                if (tiles[n].getAttribute('data-workbench-key') !== String(entry.slot)) continue;
                tiles[n].classList.add('quick-transfer-pending');
                if (entry.inflight) tiles[n].classList.add('quick-transfer-inflight');
                break;
            }
        });
    }

    function createPagedView(options) {
        var config = options.config, id = config.rightContainerId;
        var view = options.createView(id, config.title, options.layoutMode);
        var pager = new options.inventoryUI.InventoryWindowPager({
            containerId:id, containerLabel:config.title, columns:config.pageColumns,
            defaultOffset:0, defaultLimit:config.rightLimit, defaultCapacity:config.rightCapacity,
            getSnapshot:function() { return options.source.getWindow(id); },
            getRequest:function() { return options.source.getRequest(id); },
            shortcutEnabled:options.shortcutEnabled, onBeforeChange:options.beforeChange,
            onRequest:function(offset, limit, callback) { return options.source.setWindow(id, offset, limit, callback); },
            onResult:options.onResult
        });
        return {view:view, pager:pager};
    }

    function presentationFor(containerId, snapshot) {
        if (containerId === 'stash') return {
            emptyText:snapshot && snapshot.unfilteredTotal ? '当前分类暂无物品' : '暂存区是空的',
            meta:snapshot ? snapshot.total + ' 项 · 单向领取' : '同步中'
        };
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
                && (state.busyOwner === 'inventory.autoTransfer'
                    || state.busyOwner === 'inventory.autoTransferBatch'))) {
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
        var rowKey = options.keyOf || function(slot) { return slot.physicalSlot; };
        var interaction = authorityInteraction(options.getAuthorityState(), false);
        var ownedShell = new UI.OwnedInventoryViewShell({
            containerId:containerId,
            instanceKey:'inventory:' + containerId,
            itemModel:'owned',
            getItems:function() {
                var snapshot = options.getSnapshot(containerId);
                return snapshot ? snapshot.slots : [];
            },
            keyOf:rowKey,
            renderItem:function(slot) {
                return UI.renderOwnedSlot(containerId, slot, {
                    iconHtml:options.iconHtml,
                    containerLabel:options.title,
                    allowDiscard:containerId === '背包'
                });
            },
            bindItem:function(node, slot) {
                options.bindSlot(containerId, node, slot, function() { return interaction; });
            },
            exportOffer:function(slot) {
                if (options.exportOffer) return options.exportOffer(containerId, slot);
                var state = options.getAuthorityState() || {};
                if (!slot || !slot.occupied || !state.ready || state.busyOwner || state.refreshRequired) return null;
                var quantity = options.sourceQuantity ? options.sourceQuantity(containerId, slot) : undefined;
                return {subjectKind:containerId === 'stash' ? 'stashEntry' : 'ownedSlot',
                    sourceRef:options.slotRef(containerId, slot, quantity),
                    offeredOperations:['inventory.transfer']};
            },
            probeAccept:function(offer, hit) {
                if (options.probeAccept) return options.probeAccept(containerId, offer, hit);
                var target = hit && hit.item;
                if (containerId === 'stash') return {accepted:false, reason:'withdraw_only'};
                if (offer && offer.subjectKind === 'stashEntry' && target) {
                    var item = offer.sourceRef && offer.sourceRef.item || {};
                    if (containerId !== '背包' || item.majorType === '收集品' || item.majorType === '材料')
                        return {accepted:false, reason:'target_incompatible'};
                    if (target.occupied && (item.itemKind === 'equipment' || !target.item
                            || target.item.name !== item.name || target.item.itemKind === 'equipment'))
                        return {accepted:false, reason:'target_occupied'};
                    return {accepted:true,operationId:'inventory.transfer',
                        targetRef:options.slotRef(containerId, target),hint:target.occupied ? 'merge' : 'move'};
                }
                if (!offer || offer.subjectKind !== 'ownedSlot' || !target) return {accepted:false, reason:'unsupported'};
                var targetRef = options.slotRef(containerId, target);
                if (options.samePhysicalSlot(offer.sourceRef, targetRef)) return {accepted:false, reason:'same_slot'};
                return {accepted:true, operationId:'inventory.transfer', targetRef:targetRef,
                    hint:target.occupied ? 'merge-or-swap' : 'move'};
            },
            title:options.title,
            meta:'同步中',
            className:'inventory-owned-view inventory-owned-' + (containerId === '背包' ? 'backpack' : 'warehouse')
                + (containerId === '战备箱' || containerId === 'stash' ? ' inventory-owned-battlebox' : ''),
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
            keyOf:rowKey,
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
            authorityOptions:options.allowAuthority === false ? [] : UI.authoritySortOptions(), authorityLabel:'', authorityAriaLabel:containerId + '整理方式',
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
        resolveExactSourceSlot:resolveExactSourceSlot,
        storageHelpSpec:storageHelpSpec,
        stashResultMessage:stashResultMessage,
        bindTooltip:bindTooltip,
        projectQuickSelection:projectQuickSelection,
        createPagedView:createPagedView,
        createView:createView,
        createToolbar:createToolbar
    };
});
