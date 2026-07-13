/**
 * Standalone owned-inventory workbench（背包—仓库 / 背包—战备箱）。
 *
 * This panel never enters the shop lifecycle. InventoryPanelService remains the
 * authority; the Web layer only renders leased windows and emits operation intents.
 */
var InventoryWorkbench = (function() {
    'use strict';

    var _el, _shellEl, _shell, _backpackView, _rightView, _pager, _retryButton;
    var _backpackSortControls, _rightSortControls;
    var _quickDepositButton, _quickWithdrawButton, _quickStatusNode;
    var _broker, _dragControllers = [], _scaleHandle = null;
    var _state = {opened:false, ready:false, busyOwner:null, refreshRequired:false};
    var _tooltipCache = {}, _tooltipSuppressed = false;
    var _layoutMode = 'full', _densityController = null;
    var _openGeneration = 0;
    var _profile = 'battlebox';
    var _returnTarget = null;
    var _rightContainerId = '战备箱';
    var _rightLimit = 40;
    var _quickMode = null, _quickPending = [], _quickInFlight = null, _quickKeys = {};
    var _quickCompleted = 0, _quickAccepted = 0;
    var QUICK_QUEUE_LIMIT = 24;
    var _runtimeConfig = (typeof window !== 'undefined' && window.__INVENTORY_WORKBENCH_CONFIG__) || {};
    var _mux = new KShopRequestMux({
        send: function(message) { Bridge.send(message); },
        timeoutMs: _runtimeConfig.requestTimeoutMs,
        sessionNonce: _runtimeConfig.sessionNonce,
        onProtocolError: function(message) {
            if (typeof console !== 'undefined' && console.warn) console.warn(message);
        }
    });
    var _coordinator = new InventoryRuntime.InventoryCoordinator({
        request: requestInventory,
        requests: [
            {containerId:'背包', offset:0, limit:50},
            {containerId:'战备箱', offset:0, limit:40}
        ],
        onStateChange: function(state) {
            _state = state;
            renderInventories();
            refreshControls();
        }
    });

    Panels.register('workbench', {
        create: createDOM,
        onOpen: onOpen,
        onClose: cleanup,
        onRequestClose: closePanel,
        onForceClose: function() { cleanup(); toast('连接断开，物品工作台已关闭'); }
    });

    function createDOM() {
        _shellEl = document.createElement('div');
        _shellEl.className = 'panel-scale-shell kshop-scale-shell inventory-workbench-scale-shell';
        return _shellEl;
    }

    function resolveProfile(initData) {
        var profile = initData && initData.profile === 'warehouse' ? 'warehouse' : 'battlebox';
        return profile === 'warehouse'
            ? {profile:'warehouse', title:'仓库', rightContainerId:'仓库', rightLimit:50, rightCapacity:1200, pageColumns:6}
            : {profile:'battlebox', title:'战备箱', rightContainerId:'战备箱', rightLimit:40, rightCapacity:0, pageColumns:3};
    }

    function resolveReturnTarget(initData) {
        var target = initData && initData.returnTo;
        if (!target || target.panel !== 'crafting' || !target.initData
                || typeof target.initData.category !== 'string' || !target.initData.category) return null;
        var recipeIndex = Math.floor(Number(target.initData.preferredRecipeIndex));
        var craftCount = Math.floor(Number(target.initData.preferredCraftCount));
        return {panel:'crafting', initData:{category:target.initData.category,
            preferredRecipeIndex:isNaN(recipeIndex) ? -1 : recipeIndex,
            preferredCraftCount:isNaN(craftCount) ? 1 : Math.max(1, Math.min(99, craftCount))}};
    }

    function buildProfileDOM(config) {
        if (typeof Workbench === 'undefined') throw new Error('Workbench runtime is required');
        if (_pager) _pager.detach();
        for (var oldDrag = 0; oldDrag < _dragControllers.length; oldDrag++) _dragControllers[oldDrag].cancel();
        if (_broker) _broker.clearSelection();
        if (_shell) _shell.destroy();
        while (_shellEl.firstChild) _shellEl.removeChild(_shellEl.firstChild);
        _shell = null;
        _el = null;
        _backpackView = null;
        _rightView = null;
        _pager = null;
        _backpackSortControls = null;
        _rightSortControls = null;
        _quickDepositButton = null;
        _quickWithdrawButton = null;
        _quickStatusNode = null;
        _broker = null;
        _dragControllers = [];
        resetQuickTransfer();

        _profile = config.profile;
        _rightContainerId = config.rightContainerId;
        _rightLimit = config.rightLimit;
        if (!_coordinator.configureRequests([
            {containerId:'背包', offset:0, limit:50, filterKey:'all'},
            {containerId:_rightContainerId, offset:0, limit:_rightLimit, filterKey:'all'}
        ])) throw new Error('Inventory workbench request profile rejected: ' + _profile);

        _shell = new Workbench.DualPaneShell({
            title:config.title, status:'同步中', leftLabel:'背包', rightLabel:config.title
        });
        _el = _shell.getRoot();
        _el.classList.add('kshop-workbench', 'inventory-workbench-panel');
        _el.setAttribute('data-workbench-skin', 'inventory');
        _el.setAttribute('data-inventory-profile', _profile);

        if (_profile === 'warehouse') installQuickTransferActions();

        if (_densityController) _densityController.destroy();
        _densityController = new Workbench.GridDensityController({panelId:'workbench'});
        _layoutMode = _densityController.mode;
        var layoutToggle = _densityController.createToggle(function(mode) { _layoutMode = mode; });
        _shell.addHeaderAction(layoutToggle);

        _retryButton = document.createElement('button');
        _retryButton.type = 'button';
        _retryButton.className = 'workbench-mode-btn warning';
        _retryButton.textContent = '重试同步';
        _retryButton.style.display = 'none';
        _retryButton.addEventListener('click', retryRefresh);
        _shell.addHeaderAction(_retryButton);

        if (_returnTarget) {
            var returnButton = document.createElement('button');
            returnButton.type = 'button';
            returnButton.className = 'workbench-mode-btn inventory-return-crafting-btn';
            returnButton.textContent = '返回合成';
            returnButton.title = '返回后重新核算原配方与份数';
            returnButton.addEventListener('click', returnToPanel);
            _shell.addHeaderAction(returnButton);
        }

        var closeButton = document.createElement('button');
        closeButton.type = 'button';
        closeButton.className = 'workbench-close-btn';
        closeButton.textContent = '×';
        closeButton.setAttribute('aria-label', '关闭' + config.title);
        closeButton.setAttribute('data-audio-cue', 'cancel');
        closeButton.addEventListener('click', function() { closePanel(true); });
        _shell.addHeaderAction(closeButton);

        _backpackView = createInventoryView('背包', '背包', _layoutMode);
        _rightView = createInventoryView(_rightContainerId, config.title, _layoutMode);

        _pager = new InventoryUI.InventoryWindowPager({
            containerId:_rightContainerId, containerLabel:config.title, columns:config.pageColumns,
            defaultOffset:0, defaultLimit:_rightLimit, defaultCapacity:config.rightCapacity,
            getSnapshot:function() { return _coordinator.getWindow(_rightContainerId); },
            getRequest:function() { return _coordinator.getRequest(_rightContainerId); },
            shortcutEnabled:shortcutsEnabled,
            onBeforeChange:function() { exitQuickMode(); clearSelection(); hideTooltip(); },
            onRequest:function(offset, limit, callback) {
                return _coordinator.setWindow(_rightContainerId, offset, limit, callback);
            },
            onResult:function(result) {
                renderInventories();
                if (!result || !result.success) toast(config.title + '翻页失败，请重试。');
            }
        });
        _backpackView.chrome.setToolbar(createInventoryToolbar('背包', null));
        _rightView.chrome.setToolbar(createInventoryToolbar(_rightContainerId, _pager));

        if (!_shell.mountInitial(_backpackView, _rightView)) {
            throw new Error('Inventory workbench initial view configuration rejected');
        }
        installInteractions();
        _shellEl.appendChild(_el);
    }

    function installQuickTransferActions() {
        _quickStatusNode = document.createElement('div');
        _quickStatusNode.className = 'inventory-quick-transfer-status';
        _quickStatusNode.setAttribute('role', 'status');
        _quickStatusNode.setAttribute('aria-live', 'polite');
        _shell.addHeaderAction(_quickStatusNode);

        _quickDepositButton = createQuickModeButton('deposit', '快速存入', '背包 → 仓库');
        _quickWithdrawButton = createQuickModeButton('withdraw', '快速取出', '仓库 → 背包');
        _shell.addHeaderAction(_quickDepositButton);
        _shell.addHeaderAction(_quickWithdrawButton);
        updateQuickTransferUI();
    }

    function createQuickModeButton(mode, label, direction) {
        var button = document.createElement('button');
        button.type = 'button';
        button.className = 'workbench-mode-btn inventory-quick-transfer-btn';
        button.setAttribute('data-quick-mode', mode);
        button.setAttribute('aria-pressed', 'false');
        button.textContent = label;
        button.title = label + '（' + direction + '）；也可随时 Ctrl+单击单件快速转移';
        button.addEventListener('click', function() { setQuickMode(mode); });
        return button;
    }

    function createInventoryToolbar(containerId, pager) {
        var toolbar = document.createElement('div');
        toolbar.className = 'inventory-warehouse-toolbar inventory-container-toolbar'
            + (pager ? ' inventory-battlebox-toolbar' : ' inventory-no-pager');
        var view = containerId === '背包' ? _backpackView : _rightView;
        var controls = new InventoryUI.InventorySortControls({
            filterOptions:InventoryUI.categoryFilterOptions(),
            filterLabel:'',
            filterAriaLabel:containerId + '分类筛选',
            authorityOptions:InventoryUI.authoritySortOptions(),
            authorityLabel:'',
            authorityAriaLabel:containerId + '整理方式',
            commitLabel:'整理' + containerId,
            onFilterChange:function(filterKey) {
                exitQuickMode();
                clearSelection();
                hideTooltip();
                if (!_coordinator.setFilter(containerId, filterKey, function(result) {
                    renderInventories();
                    if (!result.success) {
                        var request = _coordinator.getRequest(containerId);
                        controls.setFilterKey(request ? request.filterKey : 'all');
                        toast(containerId + '筛选失败，请重试。');
                    }
                })) {
                    var request = _coordinator.getRequest(containerId);
                    controls.setFilterKey(request ? request.filterKey : 'all');
                }
            },
            onFilterSpecChange:function(filterSpec) {
                exitQuickMode();
                clearSelection();
                hideTooltip();
                if (!_coordinator.setFilterSpec(containerId, filterSpec, function(result) {
                    renderInventories();
                    if (!result.success) {
                        controls.rejectFilterChange(_coordinator.getWindow(containerId));
                        toast(containerId + '筛选失败，请重试。');
                    }
                })) controls.rejectFilterChange(_coordinator.getWindow(containerId));
            },
            onAuthorityCommit:function(methodName, label) {
                confirmSort(containerId, methodName, label);
            }
        });
        if (containerId === '背包') _backpackSortControls = controls;
        else _rightSortControls = controls;
        if (pager) toolbar.appendChild(pager.root);
        toolbar.appendChild(controls.root);
        if (view.ownedInventoryShell) view.ownedInventoryShell.setToolbar(toolbar, controls, pager);
        return toolbar;
    }

    function createInventoryView(containerId, title, layoutMode) {
        var ownedShell = new InventoryUI.OwnedInventoryViewShell({
            containerId:containerId,
            instanceKey:'inventory:' + containerId,
            itemModel:'owned',
            getItems:function() {
                var snapshot = _coordinator.getWindow(containerId);
                return snapshot ? snapshot.slots : [];
            },
            keyOf:function(slot) { return slot.physicalSlot; },
            renderItem:function(slot) {
                return InventoryUI.renderOwnedSlot(containerId, slot, {
                    iconHtml:iconHtml,
                    allowDiscard:containerId === '背包'
                });
            },
            bindItem:function(node, slot) { bindSlot(containerId, node, slot); },
            exportOffer:function(slot) {
                if (!slot || !slot.occupied || !_state.ready || _state.busyOwner || _state.refreshRequired) return null;
                return {
                    subjectKind:'ownedSlot',
                    sourceRef:slotRef(containerId, slot),
                    offeredOperations:['inventory.transfer']
                };
            },
            probeAccept:function(offer, hit) {
                var target = hit && hit.item;
                if (!offer || offer.subjectKind !== 'ownedSlot' || !target) return {accepted:false, reason:'unsupported'};
                var targetRef = slotRef(containerId, target);
                if (InventoryRuntime.samePhysicalSlot(offer.sourceRef, targetRef)) return {accepted:false, reason:'same_slot'};
                return {
                    accepted:true,
                    operationId:'inventory.transfer',
                    targetRef:targetRef,
                    hint:target.occupied ? 'merge-or-swap' : 'move'
                };
            },
            title:title,
            meta:'同步中',
            className:'inventory-owned-view inventory-owned-' + (containerId === '背包' ? 'backpack' : 'warehouse')
                + (containerId === '战备箱' ? ' inventory-owned-battlebox' : ''),
            gridClassName:'inventory-owned-grid',
            emptyText:'正在同步库存…',
            allowedSlots:containerId === '背包' ? ['L'] : ['R'],
            layoutMode: layoutMode || 'full',
            densityController: _densityController
        });
        return ownedShell.view;
    }

    function bindSlot(containerId, node, slot) {
        if (slot.occupied) bindSlotTooltip(node, containerId, slot);
        node.addEventListener('click', function(event) {
            if (consumeDragClick()) return;
            if (event.target && event.target.closest && event.target.closest('.inventory-discard-btn')) return;
            if (handleQuickTransferClick(event, containerId, slot)) return;
            if (_state.busyOwner || _state.refreshRequired) return;
            var view = containerId === '背包' ? _backpackView : _rightView;
            if (_broker.debugState().selectedInstanceKey) _broker.activateSelected(view, {item:slot, node:node}, 'click');
            else if (slot.occupied) _broker.select(view, slot, node);
        });
        var discardButton = node.querySelector('.inventory-discard-btn');
        if (discardButton) discardButton.addEventListener('click', function(event) {
            event.stopPropagation();
            confirmDiscard(containerId, slot);
        });
    }

    function installInteractions() {
        _broker = new Workbench.InteractionBroker({
            onIntent:function(intent) {
                if (!_coordinator.transfer(intent, function(result) {
                    renderInventories();
                    if (result.success) toast(result.operation === 'merge' ? '物品已合并。'
                        : result.operation === 'swap' ? '物品已交换。' : '物品已移动。');
                    else toast(result.reconciled ? '操作失败，库存已刷新。' : errorMessage(result.error));
                })) toast('库存正在处理另一项操作。');
            },
            onReject:function(result) {
                if (result && result.reason === 'same_slot') clearSelection();
            },
            onSelectionChange:function(selection) {
                _tooltipSuppressed = !!selection;
                if (_tooltipSuppressed) hideTooltip();
            }
        });
        _dragControllers = [];
        var views = [_backpackView, _rightView];
        for (var i = 0; i < views.length; i++) installDragForView(views[i]);
    }

    function installDragForView(view) {
        _dragControllers.push(new Workbench.PointerDragController({
            sourceElement:view.renderer.root,
            broker:_broker,
            timeoutMs:_runtimeConfig.dragTimeoutMs || 1400,
            getSource:function(target) {
                if (_quickMode || !_state.ready || _state.busyOwner || _state.refreshRequired) return null;
                var hit = view.renderer.itemFromTarget(target);
                if (!hit || !hit.item || !hit.item.occupied) return null;
                return {view:view, item:hit.item, node:hit.node};
            },
            resolveTarget:resolveDropTarget,
            renderGhost:function(source) {
                var item = source.item.item || {};
                var ghost = document.createElement('div');
                ghost.className = 'workbench-drag-ghost inventory-drag-ghost';
                ghost.innerHTML = iconHtml(item.icon || item.name, 'kshop-row-icon')
                    + '<span>' + escapeHtml(item.displayName || item.name || '物品') + '</span>';
                return ghost;
            },
            onDragStart:function() { _tooltipSuppressed = true; hideTooltip(); },
            onDragEnd:function() { _tooltipSuppressed = false; }
        }));
    }

    function resolveDropTarget(clientX, clientY) {
        var target = document.elementFromPoint(clientX, clientY);
        var views = [_backpackView, _rightView];
        for (var i = 0; i < views.length; i++) {
            if (!views[i].root.contains(target)) continue;
            var hit = views[i].renderer.itemFromTarget(target);
            if (hit) return {view:views[i], hit:{item:hit.item, node:hit.node}, node:hit.node};
        }
        return null;
    }

    function consumeDragClick() {
        for (var i = 0; i < _dragControllers.length; i++) if (_dragControllers[i].consumeClick()) return true;
        return false;
    }

    function handleQuickTransferClick(event, containerId, slot) {
        if (_profile !== 'warehouse') return false;
        var modifierRequested = !!event.ctrlKey;
        if (!_quickMode && !modifierRequested) return false;
        event.preventDefault();
        event.stopPropagation();

        if (_quickMode === 'deposit' && containerId !== '背包') {
            toast('快速存入模式：请点击背包中的物品。');
            return true;
        }
        if (_quickMode === 'withdraw' && containerId !== _rightContainerId) {
            toast('快速取出模式：请点击仓库中的物品。');
            return true;
        }
        if (!slot || !slot.occupied) return true;
        enqueueQuickTransfer(containerId, slot);
        return true;
    }

    function setQuickMode(mode) {
        if (_profile !== 'warehouse' || (mode !== 'deposit' && mode !== 'withdraw')) return;
        if (_quickMode === mode) {
            exitQuickMode();
            return;
        }
        if (!_state.ready || _state.refreshRequired
                || (_state.busyOwner && _state.busyOwner !== 'inventory.autoTransfer')) {
            toast('库存尚未就绪。');
            return;
        }
        if (_quickInFlight) {
            toast('请等待当前快速转移完成。');
            return;
        }
        clearQuickPending();
        _quickMode = mode;
        _quickCompleted = 0;
        _quickAccepted = 0;
        clearSelection();
        hideTooltip();
        updateQuickTransferUI();
        renderInventories();
    }

    function exitQuickMode() {
        if (!_quickMode && !_quickPending.length) return false;
        _quickMode = null;
        clearQuickPending();
        updateQuickTransferUI();
        renderInventories();
        return true;
    }

    function resetQuickTransfer() {
        _quickMode = null;
        _quickPending = [];
        _quickInFlight = null;
        _quickKeys = {};
        _quickCompleted = 0;
        _quickAccepted = 0;
        updateQuickTransferUI();
    }

    function clearQuickPending() {
        for (var i = 0; i < _quickPending.length; i++) delete _quickKeys[_quickPending[i].key];
        _quickPending = [];
    }

    function enqueueQuickTransfer(containerId, slot) {
        if (!_state.ready || _state.refreshRequired
                || (_state.busyOwner && _state.busyOwner !== 'inventory.autoTransfer')) {
            toast('库存正在处理另一项操作。');
            return false;
        }
        var key = quickTransferKey(containerId, slot.physicalSlot);
        if (_quickInFlight && _quickInFlight.key === key) {
            toast('该物品正在转移，无法取消。');
            return false;
        }
        if (_quickKeys[key]) {
            for (var i = 0; i < _quickPending.length; i++) {
                if (_quickPending[i].key !== key) continue;
                _quickPending.splice(i, 1);
                delete _quickKeys[key];
                _quickAccepted = Math.max(_quickCompleted, _quickAccepted - 1);
                updateQuickTransferUI();
                renderInventories();
                return true;
            }
        }
        if (_quickPending.length + (_quickInFlight ? 1 : 0) >= QUICK_QUEUE_LIMIT) {
            toast('快速转移队列已满，请等待当前项目完成。');
            return false;
        }
        if (!_quickMode && !_quickInFlight && !_quickPending.length) {
            _quickCompleted = 0;
            _quickAccepted = 0;
        }
        var entry = {
            key:key,
            containerId:String(containerId),
            slot:Number(slot.physicalSlot),
            signature:slotSignature(slot),
            targetContainerId:containerId === '背包' ? _rightContainerId : '背包'
        };
        _quickKeys[key] = entry;
        _quickPending.push(entry);
        _quickAccepted++;
        clearSelection();
        hideTooltip();
        updateQuickTransferUI();
        renderInventories();
        drainQuickTransferQueue();
        return true;
    }

    function drainQuickTransferQueue() {
        if (_quickInFlight || !_quickPending.length) return;
        var entry = _quickPending.shift();
        var currentSlot = findCurrentSlot(entry.containerId, entry.slot);
        if (!currentSlot || !currentSlot.occupied || slotSignature(currentSlot) !== entry.signature) {
            delete _quickKeys[entry.key];
            haltQuickTransferQueue({success:false, error:'stale_state'});
            return;
        }
        _quickInFlight = entry;
        updateQuickTransferUI();
        renderInventories();
        var generation = _openGeneration;
        var started = _coordinator.autoTransfer(
            slotRef(entry.containerId, currentSlot),
            entry.targetContainerId,
            function(result) {
                if (generation !== _openGeneration) return;
                delete _quickKeys[entry.key];
                _quickInFlight = null;
                if (result && result.success === true) {
                    _quickCompleted++;
                    updateQuickTransferUI();
                    renderInventories();
                    drainQuickTransferQueue();
                } else {
                    haltQuickTransferQueue(result || {success:false, error:'invalid_response'});
                }
            }
        );
        if (!started) {
            delete _quickKeys[entry.key];
            _quickInFlight = null;
            haltQuickTransferQueue({success:false, error:'busy'});
        }
    }

    function haltQuickTransferQueue(result) {
        clearQuickPending();
        _quickMode = null;
        updateQuickTransferUI();
        renderInventories();
        var error = result && result.error;
        if (error === 'target_full') toast('目标容器已满，快速转移已停止。');
        else if (error === 'slot_locked') toast('目标容器尚未解锁，快速转移已停止。');
        else if (result && result.reconciled) toast('库存状态已变化；已重新同步并停止队列。');
        else toast(errorMessage(error));
    }

    function findCurrentSlot(containerId, physicalSlot) {
        var snapshot = _coordinator.getWindow(containerId);
        var slots = snapshot ? snapshot.slots : [];
        for (var i = 0; i < slots.length; i++) {
            if (Number(slots[i].physicalSlot) === Number(physicalSlot)) return slots[i];
        }
        return null;
    }

    function slotSignature(slot) {
        var item = slot && slot.item ? slot.item : {};
        var confirm = slot && slot.confirmProjection ? slot.confirmProjection : item;
        return [
            String(item.name || ''),
            String(confirm.itemKind || item.itemKind || ''),
            String(confirm.displayName || item.displayName || ''),
            Number(confirm.quantity == null ? item.quantity : confirm.quantity),
            Number(confirm.enhancementLevel == null ? item.enhancementLevel || 0 : confirm.enhancementLevel),
            String(confirm.rarity || item.rarity || '')
        ].join('|');
    }

    function quickTransferKey(containerId, physicalSlot) {
        return String(containerId) + ':' + Number(physicalSlot);
    }

    function updateQuickTransferUI() {
        if (_quickDepositButton) {
            _quickDepositButton.classList.toggle('active', _quickMode === 'deposit');
            _quickDepositButton.setAttribute('aria-pressed', _quickMode === 'deposit' ? 'true' : 'false');
        }
        if (_quickWithdrawButton) {
            _quickWithdrawButton.classList.toggle('active', _quickMode === 'withdraw');
            _quickWithdrawButton.setAttribute('aria-pressed', _quickMode === 'withdraw' ? 'true' : 'false');
        }
        if (_el) {
            if (_quickMode) _el.setAttribute('data-quick-transfer-mode', _quickMode);
            else _el.removeAttribute('data-quick-transfer-mode');
        }
        if (!_quickStatusNode) return;
        var queued = _quickPending.length + (_quickInFlight ? 1 : 0);
        if (_quickMode === 'deposit') _quickStatusNode.textContent = '快速存入：背包 → 仓库';
        else if (_quickMode === 'withdraw') _quickStatusNode.textContent = '快速取出：仓库 → 背包';
        else _quickStatusNode.textContent = 'Ctrl+单击：快速转移';
        if (queued || _quickCompleted) {
            _quickStatusNode.textContent += ' · 待处理 ' + queued + ' · 已完成 ' + _quickCompleted;
        }
    }

    function applyQuickTransferSlotState() {
        if (!_el) return;
        var nodes = _el.querySelectorAll('.inventory-slot-card');
        for (var i = 0; i < nodes.length; i++) {
            nodes[i].classList.remove('quick-transfer-pending', 'quick-transfer-inflight');
        }
        for (var key in _quickKeys) {
            var entry = _quickKeys[key];
            var view = entry.containerId === '背包' ? _backpackView : _rightView;
            if (!view) continue;
            var node = view.root.querySelector('[data-physical-slot="' + entry.slot + '"]');
            if (!node) continue;
            node.classList.add('quick-transfer-pending');
            if (_quickInFlight && _quickInFlight.key === key) node.classList.add('quick-transfer-inflight');
        }
    }

    function renderInventories() {
        if (!_backpackView || !_rightView) return;
        renderView(_backpackView);
        renderView(_rightView);
        if (_pager) _pager.refresh();
        applyQuickTransferSlotState();
    }

    function renderView(view) {
        var snapshot = _coordinator.getWindow(view.containerId);
        var filtered = snapshot && String(snapshot.filterKey || 'all') !== 'all';
        var emptyText;
        if (view.containerId === '战备箱') {
            emptyText = snapshot && Number(snapshot.accessibleCapacity) <= 0
                ? '战备箱尚未解锁' : filtered ? '当前分类暂无物品' : '本页暂无物品';
        } else {
            emptyText = filtered ? '当前分类暂无物品' : '本页暂无物品';
        }
        var meta = !snapshot ? '同步中'
            : view.containerId === '战备箱' && Number(snapshot.accessibleCapacity) <= 0 ? '未解锁'
            : view.containerId === '背包' ? countOccupied(snapshot.slots) + ' / ' + Number(snapshot.accessibleCapacity || snapshot.capacity) : '';
        if (view.ownedInventoryShell) view.ownedInventoryShell.syncSnapshot(snapshot, {
            emptyText:emptyText, meta:meta
        });
    }

    function refreshControls() {
        if (!_el) return;
        var blocked = !_state.ready || !!_state.busyOwner || !!_state.refreshRequired;
        var slotBlocked = !_state.ready || !!_state.refreshRequired
            || (!!_state.busyOwner && _state.busyOwner !== 'inventory.autoTransfer');
        var nodes = _el.querySelectorAll('.inventory-slot-card');
        for (var i = 0; i < nodes.length; i++) nodes[i].classList.toggle('write-locked', slotBlocked);
        if (_pager) _pager.setDisabled(blocked);
        if (_backpackSortControls) _backpackSortControls.setDisabled(blocked);
        if (_rightSortControls) {
            _rightSortControls.setDisabled(blocked);
            var rightSnapshot = _coordinator.getWindow(_rightContainerId);
            _rightSortControls.setAuthorityDisabled(blocked
                || !rightSnapshot || Number(rightSnapshot.accessibleCapacity) <= 0);
        }
        if (_retryButton) _retryButton.style.display = _state.refreshRequired ? '' : 'none';
        var quickBlocked = !_state.ready || !!_state.refreshRequired
            || (!!_state.busyOwner && _state.busyOwner !== 'inventory.autoTransfer');
        if (_quickDepositButton) _quickDepositButton.disabled = quickBlocked;
        if (_quickWithdrawButton) _quickWithdrawButton.disabled = quickBlocked;
        updateQuickTransferUI();
        if (!_shell) return;
        if (_state.refreshRequired) _shell.setStatus('同步失败', 'warning');
        else if (_state.busyOwner) _shell.setStatus('处理中', 'busy');
        else if (_state.ready) _shell.setStatus('已同步', 'ready');
        else _shell.setStatus('同步中', 'busy');
    }

    function confirmDiscard(containerId, slot) {
        if (containerId !== '背包' || !slot.occupied || !_state.ready) return;
        var projection = slot.confirmProjection || slot.item || {};
        _shell.openModal({
            kind:'discard',
            title:'丢弃 ' + String(projection.displayName || '该物品') + '？',
            message:'将丢弃整组，共 ' + Number(projection.quantity || 1) + ' 件。',
            detail:'丢弃后无法找回。',
            actions:[
                {id:'cancel', label:'取消', audioCue:'cancel'},
                {id:'discard', label:'确认丢弃', danger:true, audioCue:'error', onSelect:function() {
                    if (!_coordinator.discard(slotRef(containerId, slot), function(result) {
                        renderInventories();
                        toast(result.success ? '物品已丢弃。' : errorMessage(result.error));
                    })) toast('库存正在处理另一项操作。');
                }}
            ]
        });
    }

    function confirmSort(containerId, methodName, label) {
        if (!_state.ready || _state.busyOwner || _state.refreshRequired) return;
        exitQuickMode();
        methodName = methodName || 'byType';
        label = label || methodName;
        var scope = containerId === '战备箱' ? '当前已解锁区域' : '全部物品';
        _shell.openModal({
            kind:'inventory-sort',
            title:'按' + label + '整理' + containerId + '？',
            message:'将重新排列' + scope + '，并合并可堆叠物品。',
            detail:containerId === '战备箱'
                ? '未解锁的存档保留区不会被读取或移动。' : '原有摆放顺序会改变。',
            actions:[
                {id:'cancel', label:'取消', audioCue:'cancel'},
                {id:'sort', label:'整理并合并', primary:true, audioCue:'confirm', onSelect:function() {
                    clearSelection();
                    if (!_coordinator.sortAndMerge(containerId, methodName, function(result) {
                        renderInventories();
                        toast(result.success ? containerId + '整理完成。' : containerId + '整理失败，请重试。');
                    })) toast('库存正在处理另一项操作。');
                }}
            ]
        });
    }

    function bindSlotTooltip(node, containerId, slot) {
        var key = containerId + ':' + slot.physicalSlot + ':' + String(slot.slotLease || '');
        var item = slot.item || {};
        PanelTooltip.bindAsyncHover(node, {
            cache: _tooltipCache,
            key: key,
            item: item,
            isSuppressed: function() { return _tooltipSuppressed; },
            renderBasic: buildBasicTooltip,
            renderRich: buildRichTooltip,
            fetch: function(_, callback) {
                requestInventory('tooltip', {v:1, source:slotRef(containerId, slot)}, function(response) {
                    if (!isOpen()) return;
                    callback(response);
                });
            }
        });
    }

    function buildBasicTooltip(item) {
        var type = item.majorType || item.use || item.itemKind || '物品';
        return '<div class="kshop-tt-header"><b>' + escapeHtml(item.displayName || item.name || '未知物品') + '</b></div>'
            + '<div class="kshop-tt-divider"></div><span class="kshop-tt-dim">类型</span> ' + escapeHtml(type) + '<br>'
            + (Number(item.quantity) > 1 ? '<span class="kshop-tt-dim">数量</span> ' + Number(item.quantity) + '<br>' : '')
            + (Number(item.enhancementLevel) > 0 ? '<span class="kshop-tt-dim">强化</span> +' + Number(item.enhancementLevel) + '<br>' : '')
            + '<div class="kshop-tt-loading">加载中…</div>';
    }

    function buildRichTooltip(item, data) {
        var iconKey = data.iconName || item.icon || item.name;
        return PanelTooltip.buildItemRichHtml({
            iconHtml:PanelTooltip.dynamicIconHtml(iconKey),
            iconUrl:PanelTooltip.staticIconUrl(iconKey),
            introHTML:data.introHTML || '',
            descHTML:data.descHTML || '',
            rootClass:'kshop-tt-rich-context inventory-owned-tt-context',
            layoutType:PanelTooltip.inferLayoutType(data.itemType || item.majorType || item.use)
        });
    }

    function onOpen(el, initData) {
        var generation = ++_openGeneration;
        _returnTarget = resolveReturnTarget(initData);
        buildProfileDOM(resolveProfile(initData));
        resetQuickTransfer();
        if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = typeof PanelScale !== 'undefined' ? PanelScale.attach(_shellEl, 1024, 576) : null;
        _tooltipCache = {};
        _mux.openSession();
        if (_pager) { _pager.detach(); _pager.attach(); }
        clearSelection();
        // 不跨存档记忆剧情容器页码；换到解锁更少的存档时必须从合法首页重新取 lease。
        _coordinator.resetWindow('背包', 0, 50, 'all');
        _coordinator.resetWindow(_rightContainerId, 0, _rightLimit, 'all');
        if (_backpackSortControls) _backpackSortControls.setFilterKey('all');
        if (_rightSortControls) _rightSortControls.setFilterKey('all');
        // Panels 的共享 required-assets 门已保证 Icons manifest 先于任何 panel onOpen 就绪；
        // 这里仅负责 inventory session，避免每个物品面板各自复制一套图标加载竞态。
        openInventory(generation);
    }

    function openInventory(generation) {
        // Panels 在 onOpen 返回后才写 active id，因此启动只看本模块 generation；
        // coordinator 的异步回包仍同时校验 generation + isOpen。
        if (generation !== _openGeneration) return;
        _coordinator.open(function(result) {
            if (generation !== _openGeneration || !isOpen()) return;
            renderInventories();
            if (!result.success) toast(errorMessage(result.error));
        });
    }

    function cleanup() {
        _openGeneration += 1;
        if (_scaleHandle) { _scaleHandle.detach(); _scaleHandle = null; }
        if (_pager) _pager.detach();
        for (var i = 0; i < _dragControllers.length; i++) _dragControllers[i].cancel();
        clearSelection();
        hideTooltip();
        if (_shell) _shell.closeModal();
        resetQuickTransfer();
        _coordinator.close();
        _mux.closeSession();
        if (_densityController) { _densityController.destroy(); _densityController = null; }
    }

    function closePanel(forceClose) {
        if (_shell && _shell.hasModal()) { _shell.closeModal(); return; }
        if (!forceClose && exitQuickMode()) return;
        if (!forceClose && _returnTarget) { returnToPanel(); return; }
        Panels.close();
        Bridge.send({type:'panel', cmd:'close', panel:'workbench'});
    }

    function returnToPanel() {
        if (!_returnTarget) return false;
        if (_state.busyOwner || _quickInFlight || _quickPending.length) {
            toast('库存写入尚未完成，请稍候返回。'); return false;
        }
        var target = _returnTarget;
        _returnTarget = null;
        Panels.open(target.panel, target.initData);
        return true;
    }

    function retryRefresh() {
        if (!_coordinator.retryRefresh(function(result) {
            renderInventories();
            if (!result.success) toast(errorMessage(result.error));
        })) toast('当前无法重试同步。');
    }

    function requestInventory(cmd, payload, callback) {
        return _mux.request('inventory', cmd, {panel:'workbench', payload:payload || {}}, callback);
    }

    function slotRef(containerId, slot) {
        return {
            containerId:containerId,
            slot:Number(slot.physicalSlot),
            expectedLease:String(slot.slotLease),
            occupied:!!slot.occupied,
            item:slot.item || null
        };
    }

    function shortcutsEnabled(event) {
        if (!isOpen() || (_shell && _shell.hasModal())) return false;
        var target = event.target;
        return !(target && target.closest && target.closest('input,textarea,select,[contenteditable="true"],[data-browser-native]'));
    }

    function countOccupied(slots) {
        var count = 0;
        for (var i = 0; i < slots.length; i++) if (slots[i].occupied) count++;
        return count;
    }

    function clearSelection() { if (_broker) _broker.clearSelection(); }
    function hideTooltip() { if (typeof PanelTooltip !== 'undefined') PanelTooltip.hide(); }
    function isOpen() { return Panels.getActive ? Panels.getActive() === 'workbench' : Panels.isOpen(); }
    function toast(message) { if (typeof Toast !== 'undefined') Toast.add(message); }
    function escapeHtml(value) { return String(value == null ? '' : value).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
    function iconHtml(iconName, cls) {
        var icon = typeof Icons !== 'undefined' && Icons.html
            ? Icons.html(iconName, cls || 'kshop-icon', ' onerror="this.style.display=\'none\'"') : '';
        return icon || '<div class="' + (cls || 'kshop-icon') + ' kshop-icon-placeholder"></div>';
    }
    function errorMessage(error) {
        if (error === 'slot_locked') return '该容器槽位尚未解锁。';
        if (error === 'stale_state') return '库存已经变化，请重试。';
        if (error === 'client_timeout' || error === 'timeout') return '库存响应超时，请重试。';
        if (error === 'inventory_refresh_failed') return '库存同步失败，请重试。';
        return '操作失败，请重试。';
    }

    Bridge.on('panel_resp', function(data) { _mux.handleResponse(data); });

    return {
        debugState:function() {
            var right = _coordinator.getWindow(_rightContainerId);
            return {
                profile:_profile,
                rightContainerId:_rightContainerId,
                coordinator:_coordinator.debugState(),
                rightAccessibleCapacity:right ? Number(right.accessibleCapacity) : null,
                battleboxAccessibleCapacity:_profile === 'battlebox' && right ? Number(right.accessibleCapacity) : null,
                returnTarget:_returnTarget ? {panel:_returnTarget.panel, initData:_returnTarget.initData} : null,
                page:_pager ? _pager.getState() : null,
                quickTransfer:{
                    mode:_quickMode,
                    pending:_quickPending.length,
                    inFlight:_quickInFlight ? _quickInFlight.key : null,
                    completed:_quickCompleted,
                    accepted:_quickAccepted,
                    limit:QUICK_QUEUE_LIMIT
                }
            };
        }
    };
})();
