/** KShop owned-inventory presentation and interaction adapter. */
(function(root, factory) {
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.KShopOwnedInventoryPresenter = api;
})(typeof window !== 'undefined' ? window : this, function() {
    'use strict';

    function ownedSlotRef(containerId, slot) {
        return {
            containerId:containerId,
            slot:Number(slot.physicalSlot),
            expectedLease:String(slot.slotLease),
            occupied:!!slot.occupied,
            item:slot.item || null
        };
    }

    function presentationForSnapshot(containerId, snapshot) {
        var filtered = snapshot && String(snapshot.filterKey || 'all') !== 'all';
        var emptyText = containerId === '战备箱' && snapshot && Number(snapshot.accessibleCapacity) <= 0
            ? '战备箱尚未解锁' : filtered ? '当前分类暂无物品' : '本页暂无物品';
        var meta = '同步中';
        if (snapshot && containerId === '战备箱' && Number(snapshot.accessibleCapacity) <= 0) meta = '未解锁';
        else if (snapshot && containerId === '背包') {
            var occupied = 0;
            for (var i = 0; i < snapshot.slots.length; i++) if (snapshot.slots[i].occupied) occupied++;
            meta = occupied + ' / ' + snapshot.capacity;
        } else if (snapshot) meta = '';
        return {emptyText:emptyText, meta:meta};
    }

    function interactionForStatus(status) {
        status = status || {};
        if (status.refreshRequired) return {inspectable:true, actionable:false, reason:'背包同步失败，请先重试。'};
        if (!status.ready) return {inspectable:true, actionable:false, reason:'背包正在同步，请稍候。'};
        if (status.busyOwner) return {inspectable:true, actionable:false, reason:'库存正在处理另一项操作。'};
        return {inspectable:true, actionable:true, reason:''};
    }

    function ensureReasonNode(node) {
        var reason = node.querySelector('.workbench-entity-lock-reason');
        if (!reason) {
            reason = document.createElement('span');
            reason.className = 'workbench-entity-lock-reason';
            reason.hidden = true;
            node.appendChild(reason);
        }
        return reason;
    }

    function projectNode(node, projection, reasonNode) {
        return Workbench.EntityTile.projectInteraction(node, {
            inspectable:projection.inspectable,
            actionable:projection.actionable,
            reason:projection.reason,
            reasonNode:reasonNode
        });
    }

    function OwnedInventoryPresenter(options) {
        options = options || {};
        this._state = options.state || {};
        this._intent = options.intent || {};
        this._views = [];
        this._panes = {};
        this._dragControllers = [];
        this._pager = null;
        this._backpackControls = null;
        this._warehouseControls = null;
        this._interaction = interactionForStatus(
            this._state.getStatus ? this._state.getStatus() : null);
    }

    OwnedInventoryPresenter.prototype.getViews = function() { return this._views.slice(); };
    OwnedInventoryPresenter.prototype.getView = function(containerId) {
        for (var i = 0; i < this._views.length; i++) if (this._views[i].containerId === containerId) return this._views[i];
        return null;
    };
    OwnedInventoryPresenter.prototype.getPane = function(containerId) { return this._panes[containerId] || null; };

    OwnedInventoryPresenter.prototype.createViews = function(layoutMode, densityController) {
        var backpack = this._createView('背包', layoutMode, densityController);
        var warehouse = this._createView('战备箱', layoutMode, densityController);
        this._views = [backpack, warehouse];
        backpack.chrome.setToolbar(this._createToolbar('背包', null));
        warehouse.chrome.setToolbar(this._createToolbar('战备箱', this._createPager()));
        return {backpack:backpack, warehouse:warehouse};
    };

    OwnedInventoryPresenter.prototype._createPager = function() {
        var self = this;
        this._pager = new InventoryUI.InventoryWindowPager({
            containerId:'战备箱', containerLabel:'战备箱', columns:3,
            defaultLimit:40, defaultCapacity:0,
            getSnapshot:function() { return self._state.getWindow('战备箱'); },
            getRequest:function() { return self._state.getRequest('战备箱'); },
            shortcutEnabled:function(event) { return self._shortcutEnabled(event); },
            onBeforeChange:function() { self._clearSelection(); self._intent.hideTooltip(); },
            onRequest:function(offset, limit, callback) { return self._intent.setWindow('战备箱', offset, limit, callback); },
            onResult:function(result) {
                self.render();
                if (!result.success) {
                    if (typeof console !== 'undefined' && console.warn) console.warn('[KShop inventory page]', result.error || 'inventory_refresh_failed');
                    self._intent.toast('战备箱翻页失败，请重试。');
                }
            }
        });
        return this._pager;
    };

    OwnedInventoryPresenter.prototype._createToolbar = function(containerId, pager) {
        var self = this;
        var toolbar = document.createElement('div');
        toolbar.className = 'inventory-warehouse-toolbar inventory-container-toolbar' + (pager ? '' : ' inventory-no-pager');
        var controls = new InventoryUI.InventorySortControls({
            filterOptions:InventoryUI.categoryFilterOptions(), filterLabel:'',
            filterAriaLabel:containerId + '分类筛选', authorityAriaLabel:containerId + '整理方式',
            authorityLabel:'', commitLabel:'整理' + containerId,
            authorityOptions:InventoryUI.authoritySortOptions(),
            onFilterChange:function(filterKey) {
                self._clearSelection(); self._intent.hideTooltip();
                if (!self._intent.setFilter(containerId, filterKey, function(result) {
                    self.render();
                    if (!result.success) {
                        var request = self._state.getRequest(containerId);
                        controls.setFilterKey(request ? request.filterKey : 'all');
                        self._intent.toast(containerId + '筛选失败，请重试。');
                    }
                })) {
                    var request = self._state.getRequest(containerId);
                    controls.setFilterKey(request ? request.filterKey : 'all');
                }
            },
            onFilterSpecChange:function(filterSpec) {
                self._clearSelection(); self._intent.hideTooltip();
                if (!self._intent.setFilterSpec(containerId, filterSpec, function(result) {
                    self.render();
                    if (!result.success) {
                        controls.rejectFilterChange(self._state.getWindow(containerId));
                        self._intent.toast(containerId + '筛选失败，请重试。');
                    }
                })) controls.rejectFilterChange(self._state.getWindow(containerId));
            },
            onAuthorityCommit:function(methodName, label) { self.showSortConfirm(containerId, methodName, label); }
        });
        if (containerId === '背包') this._backpackControls = controls;
        else this._warehouseControls = controls;
        if (pager) toolbar.appendChild(pager.root);
        toolbar.appendChild(controls.root);
        var view = this.getView(containerId);
        if (!view) view = containerId === '背包' ? this._views[0] : this._views[1];
        if (view && view.ownedInventoryShell) view.ownedInventoryShell.setToolbar(toolbar, controls, pager);
        return toolbar;
    };

    OwnedInventoryPresenter.prototype._createView = function(containerId, layoutMode, densityController) {
        var self = this;
        var ownedShell = new InventoryUI.OwnedInventoryViewShell({
            containerId:containerId, instanceKey:'inventory:' + containerId, itemModel:'owned',
            getItems:function() {
                var snapshot = self._state.getWindow(containerId);
                return snapshot ? snapshot.slots : [];
            },
            keyOf:function(slot) { return slot.physicalSlot; },
            renderItem:function(slot) {
                return InventoryUI.renderOwnedSlot(containerId, slot, {
                    iconHtml:self._intent.iconHtml,
                    allowDiscard:containerId === '背包'
                });
            },
            bindItem:function(node, slot) { self._bindSlot(containerId, node, slot); },
            exportOffer:function(slot) {
                var status = self._state.getStatus();
                if (!slot || !slot.occupied || !status.ready
                        || status.busyOwner || status.refreshRequired) return null;
                return {subjectKind:'ownedSlot', sourceRef:ownedSlotRef(containerId, slot), offeredOperations:['inventory.transfer']};
            },
            probeAccept:function(offer, hit) {
                var targetSlot = hit && hit.item;
                if (!offer || offer.subjectKind !== 'ownedSlot' || !targetSlot) return {accepted:false, reason:'unsupported'};
                var targetRef = ownedSlotRef(containerId, targetSlot);
                if (InventoryRuntime.samePhysicalSlot(offer.sourceRef, targetRef)) return {accepted:false, reason:'same_slot'};
                return {accepted:true, operationId:'inventory.transfer', targetRef:targetRef,
                    hint:targetSlot.occupied ? 'merge-or-swap' : 'move'};
            },
            title:containerId, kicker:'', meta:'同步中',
            className:'inventory-owned-view inventory-owned-' + (containerId === '背包' ? 'backpack' : 'warehouse'),
            gridClassName:'inventory-owned-grid', emptyText:'正在同步库存…',
            allowedSlots:['L', 'R'], layoutMode:layoutMode || 'full', densityController:densityController
        });
        var pane = new WorkbenchComponents.OwnedInventoryPane({
            view:ownedShell.view, shell:ownedShell,
            getSnapshot:function() { return self._state.getWindow(containerId); },
            keyOf:function(slot) { return slot && slot.physicalSlot; },
            interaction:this._interaction,
            onInteractionChange:function(projection) {
                self._interaction = projection;
                self._projectViewInteraction(containerId);
            },
            onQuickTransfer:function(transfer, done) {
                return self._intent.transfer({operationId:'inventory.transfer', sourceRef:transfer.source,
                    targetRef:transfer.target, hint:transfer.meta && transfer.meta.hint}, done);
            },
            onQuickTransferResult:function(result) {
                self.render();
                if (result && result.success) {
                    var label = result.operation === 'merge' ? '物品已合并。'
                        : result.operation === 'swap' ? '物品已交换。' : '物品已移动。';
                    self._intent.toast(label); self._intent.playCue('success');
                } else {
                    if (typeof console !== 'undefined' && console.warn) console.warn('[KShop inventory transfer]', result && result.error || 'unknown');
                    self._intent.toast(result && result.reconciled ? '移动失败，库存已刷新。' : '移动失败，请重试。');
                    self._intent.playCue('error');
                }
            }
        });
        this._panes[containerId] = pane;
        return pane.view;
    };

    OwnedInventoryPresenter.prototype._bindSlot = function(containerId, node, slot) {
        var self = this;
        if (slot.occupied) this._intent.bindTooltip(node, containerId, slot);
        var itemName = slot.occupied && slot.item
            ? String(slot.item.displayName || slot.item.name || '未知物品') : '空槽';
        var reasonNode = ensureReasonNode(node);
        Workbench.EntityTile.bindActivation(node, {
            itemName:itemName, label:node.getAttribute('aria-label') || itemName,
            selected:this._broker() ? this._broker().isSelectedNode(node) : false,
            inspectable:function() { return self._interaction.inspectable; },
            actionable:function() { return self._interaction.actionable; },
            reason:function() { return self._interaction.reason; },
            reasonNode:reasonNode,
            onBlocked:function() { self._intent.toast(self._interaction.reason); },
            onActivate:function(event, context) {
                var broker = self._broker();
                if (!broker || self.consumedClick()) return;
                var selected = broker.debugState().selectedInstanceKey;
                var view = self.getView(containerId);
                if (selected && selected !== 'shop:catalog') broker.activateSelected(view, {item:slot, node:node}, context.origin);
                else if (slot.occupied) broker.select(view, slot, node);
            }
        });
        var discardButton = node.querySelector('.inventory-discard-btn');
        if (discardButton) {
            Workbench.EntityTile.labelAction(discardButton, itemName, '丢弃整槽');
            discardButton.addEventListener('click', function(event) {
                event.stopPropagation();
                if (!self._interaction.actionable) {
                    self._intent.toast(self._interaction.reason);
                    return;
                }
                self.showDiscardConfirm(containerId, slot);
            });
        }
        node.__kshopOwnedInteractionRefresh = function() {
            projectNode(node, self._interaction, reasonNode);
            node.classList.toggle('write-locked', !self._interaction.actionable);
            if (discardButton) projectNode(discardButton, self._interaction, reasonNode);
        };
        node.__kshopOwnedInteractionRefresh();
    };

    OwnedInventoryPresenter.prototype._projectViewInteraction = function(containerId) {
        var view = this.getView(containerId);
        var nodes = view ? view.root.querySelectorAll('.inventory-slot-card') : [];
        for (var i = 0; i < nodes.length; i++) {
            if (nodes[i].__kshopOwnedInteractionRefresh) nodes[i].__kshopOwnedInteractionRefresh();
        }
    };

    OwnedInventoryPresenter.prototype._broker = function() {
        return this._state.getInteractionBroker ? this._state.getInteractionBroker() : null;
    };
    OwnedInventoryPresenter.prototype._clearSelection = function() {
        var broker = this._broker(); if (broker) broker.clearSelection();
    };

    OwnedInventoryPresenter.prototype.render = function() {
        for (var i = 0; i < this._views.length; i++) {
            var view = this._views[i];
            var snapshot = this._state.getWindow(view.containerId);
            if (view.ownedInventoryPane) view.ownedInventoryPane.update(snapshot, presentationForSnapshot(view.containerId, snapshot));
        }
        if (this._pager) this._pager.refresh();
    };

    OwnedInventoryPresenter.prototype._shortcutEnabled = function(event) {
        if (!this._state.isOpen() || !this._state.isInventoryModeActive()) return false;
        var shell = this._state.getWorkbenchShell();
        if (shell && shell.hasModal()) return false;
        var target = event.target;
        return !(target && target.closest && target.closest('input,textarea,select,[contenteditable="true"],[data-browser-native]'));
    };

    OwnedInventoryPresenter.prototype.showSortConfirm = function(containerId, methodName, label) {
        var self = this;
        var status = this._state.getStatus();
        if (!status.ready || status.busyOwner || status.refreshRequired) return;
        methodName = methodName || 'byType'; label = label || methodName;
        var battlebox = containerId === '战备箱';
        this._state.getWorkbenchShell().openModal({
            kind:'warehouse-sort', kicker:'', title:'按' + label + '整理' + containerId + '？',
            message:'将重新排列' + (battlebox ? '当前已解锁区域' : containerId + '全部物品') + '，并合并可堆叠物品。',
            detail:battlebox ? '未解锁的存档保留区不会被读取或移动。'
                : '原有摆放顺序会改变，完成后仍停留在当前页。',
            actions:[
                {id:'cancel', label:'取消', audioCue:'cancel'},
                {id:'sort', label:'整理并合并', primary:true, audioCue:'confirm', onSelect:function() {
                    self._clearSelection();
                    if (!self._intent.sortAndMerge(containerId, methodName, function(result) {
                        self.render();
                        if (result.success) self._intent.toast(containerId + '整理完成。');
                        else self._intent.toast(containerId + '整理失败，请重试。');
                    })) self._intent.toast('库存正在处理另一笔写入。');
                }}
            ]
        });
    };

    OwnedInventoryPresenter.prototype.showDiscardConfirm = function(containerId, slot) {
        var self = this;
        var interaction = interactionForStatus(this._state.getStatus());
        if (containerId !== '背包' || !slot.occupied || !interaction.actionable) {
            if (interaction.reason) this._intent.toast(interaction.reason);
            return;
        }
        var projection = slot.confirmProjection || slot.item || {};
        this._state.getWorkbenchShell().openModal({
            kind:'discard', kicker:'', title:'丢弃 ' + String(projection.displayName || '该物品') + '？',
            message:'将丢弃整组，共 ' + Number(projection.quantity || 1) + ' 件。',
            detail:'丢弃后无法找回。',
            actions:[
                {id:'cancel', label:'取消', audioCue:'cancel'},
                {id:'discard', label:'确认丢弃', danger:true, audioCue:'error', onSelect:function() {
                    var current = interactionForStatus(self._state.getStatus());
                    if (!current.actionable) { self._intent.toast(current.reason); return; }
                    if (!self._intent.discard(ownedSlotRef(containerId, slot), function(result) {
                        self.render();
                        self._intent.toast(result.success ? '物品已丢弃。' : '丢弃失败，请重试。');
                    })) self._intent.toast('库存正在处理另一笔写入。');
                }}
            ]
        });
    };

    OwnedInventoryPresenter.prototype.quickTransfer = function(intent) {
        var pane = intent && intent.sourceRef ? this._panes[intent.sourceRef.containerId] : null;
        if (!pane) return false;
        var key = String(intent.sourceRef.containerId) + ':' + String(intent.sourceRef.slot)
            + ':' + String(intent.sourceRef.expectedLease || '') + '>'
            + String(intent.targetRef && intent.targetRef.containerId || '') + ':'
            + String(intent.targetRef && intent.targetRef.slot);
        return pane.quickTransfer(intent.sourceRef, intent.targetRef, {key:key, hint:intent.hint});
    };

    OwnedInventoryPresenter.prototype.installDragControllers = function(broker) {
        var self = this;
        this.cancelDrags();
        this._dragControllers = [];
        for (var i = 0; i < this._views.length; i++) {
            (function(view) {
                self._dragControllers.push(new Workbench.PointerDragController({
                    sourceElement:view.renderer.root, broker:broker,
                    timeoutMs:self._state.getDragTimeout(),
                    getSource:function(target) {
                        var status = self._state.getStatus();
                        if (!status.ready || status.busyOwner || status.refreshRequired) return null;
                        var hit = view.renderer.itemFromTarget(target);
                        if (!hit || !hit.item || !hit.item.occupied) return null;
                        return {view:view, item:hit.item, node:hit.node};
                    },
                    resolveTarget:function(x, y) { return self._resolveDropTarget(x, y); },
                    renderGhost:function(source) {
                        var item = source.item.item || {};
                        var ghost = document.createElement('div');
                        ghost.className = 'workbench-drag-ghost inventory-drag-ghost';
                        ghost.innerHTML = self._intent.iconHtml(item.icon || item.name, 'kshop-row-icon')
                            + '<span>' + self._intent.escapeHtml(item.displayName || item.name || 'owned item') + '</span>';
                        return ghost;
                    },
                    onDragStart:function() { self._intent.setDragSuppressed(true); self._intent.hideTooltip(); },
                    onDragEnd:function() { self._intent.setDragSuppressed(false); }
                }));
            })(this._views[i]);
        }
    };

    OwnedInventoryPresenter.prototype._resolveDropTarget = function(x, y) {
        var target = document.elementFromPoint(x, y);
        for (var i = 0; i < this._views.length; i++) {
            var view = this._views[i];
            if (!view.root.contains(target)) continue;
            var hit = view.renderer.itemFromTarget(target);
            return hit ? {view:view, hit:{item:hit.item, node:hit.node}, node:hit.node} : null;
        }
        return null;
    };

    OwnedInventoryPresenter.prototype.consumedClick = function() {
        for (var i = 0; i < this._dragControllers.length; i++) if (this._dragControllers[i].consumeClick()) return true;
        return false;
    };

    OwnedInventoryPresenter.prototype.cancelDrags = function() {
        for (var i = 0; i < this._dragControllers.length; i++) this._dragControllers[i].cancel();
    };

    OwnedInventoryPresenter.prototype.setAuthorityState = function(status) {
        this._interaction = interactionForStatus(status);
        for (var key in this._panes) this._panes[key].setInteraction(this._interaction);
        var disabled = !this._interaction.actionable;
        if (this._pager) this._pager.setDisabled(disabled);
        if (this._backpackControls) this._backpackControls.setDisabled(disabled);
        if (this._warehouseControls) {
            this._warehouseControls.setDisabled(disabled);
            var snapshot = this._state.getWindow('战备箱');
            this._warehouseControls.setAuthorityDisabled(disabled || !snapshot || Number(snapshot.accessibleCapacity) <= 0);
        }
    };

    OwnedInventoryPresenter.prototype.setDisabled = function(disabled) {
        this.setAuthorityState({ready:!disabled, busyOwner:disabled ? 'legacy' : null});
    };

    OwnedInventoryPresenter.prototype.resetSession = function() {
        for (var key in this._panes) this._panes[key].cancelQuickTransfers();
        if (this._pager) { this._pager.detach(); this._pager.attach(); }
        var backpack = this._state.getRequest('背包');
        var warehouse = this._state.getRequest('战备箱');
        this._intent.resetWindow('背包', backpack ? backpack.offset : 0, 50, 'all');
        this._intent.resetWindow('战备箱', warehouse ? warehouse.offset : 0, 40, 'all');
        if (this._backpackControls) this._backpackControls.setFilterKey('all');
        if (this._warehouseControls) this._warehouseControls.setFilterKey('all');
    };

    OwnedInventoryPresenter.prototype.closeSession = function() {
        if (this._pager) this._pager.detach();
        this.cancelDrags();
        for (var key in this._panes) this._panes[key].cancelQuickTransfers();
    };

    OwnedInventoryPresenter.prototype.setMenuOpen = function(open) {
        if (this._pager) this._pager.setMenuOpen(!!open, false);
    };

    OwnedInventoryPresenter.prototype.selectionIsOwned = function(selection) {
        if (!selection) return false;
        for (var i = 0; i < this._views.length; i++) if (selection.view === this._views[i]) return true;
        return false;
    };

    return {
        OwnedInventoryPresenter:OwnedInventoryPresenter,
        ownedSlotRef:ownedSlotRef,
        presentationForSnapshot:presentationForSnapshot,
        interactionForStatus:interactionForStatus
    };
});
