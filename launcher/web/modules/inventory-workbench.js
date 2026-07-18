/**
 * Standalone owned-inventory workbench（背包—仓库 / 背包—战备箱）。
 *
 * This panel never enters the shop lifecycle. InventoryPanelService remains the
 * authority; the Web layer only renders leased windows and emits operation intents.
 */
var InventoryWorkbench = (function() {
    'use strict';

    var _el, _shellEl, _shell, _backpackView, _rightView, _tuningView, _pager, _retryButton;
    var _backpackSortControls, _rightSortControls;
    var _quickDepositButton, _quickWithdrawButton, _quickStatusNode;
    var _broker, _dragControllers = [], _scaleHandle = null;
    var _state = {opened:false, ready:false, busyOwner:null, refreshRequired:false};
    var _tooltipCache = {}, _tooltipSuppressed = false;
    var _layoutMode = 'full', _densityController = null;
    var _openGeneration = 0;
    var _profile = 'battlebox';
    var _viewMode = 'storage', _panelInstanceId = '', _tuningOrigin = false;
    var _viewSwitchButton = null, _tuningHelpButton = null, _modConfirmationToggle = null;
    var _modConfirmationMode = 'safe';
    var _returnTarget = null;
    var _rightContainerId = '战备箱';
    var _rightLimit = 40;
    var _quickMode = null, _quickPending = [], _quickInFlight = null, _quickKeys = {};
    var _quickCompleted = 0, _quickAccepted = 0;
    var QUICK_QUEUE_LIMIT = 24;
    var MOD_CONFIRMATION_STORAGE_KEY = 'cf7.equipmentTuning.modConfirmationMode';
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
        onRebind: onRebind,
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
        var profile = initData && initData.profile != null ? String(initData.profile) : 'battlebox';
        if (profile !== 'warehouse' && profile !== 'battlebox') return null;
        return profile === 'warehouse'
            ? {profile:'warehouse', title:'仓库', rightContainerId:'仓库', rightLimit:50, rightCapacity:1200, pageColumns:6}
            : {profile:'battlebox', title:'战备箱', rightContainerId:'战备箱', rightLimit:40, rightCapacity:0, pageColumns:3};
    }

    function resolveView(initData) {
        var view = initData && initData.view != null ? String(initData.view) : 'storage';
        return view === 'storage' || view === 'tuning' ? view : null;
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

    function readModConfirmationMode() {
        try {
            return window.localStorage.getItem(MOD_CONFIRMATION_STORAGE_KEY) === 'fast' ? 'fast' : 'safe';
        } catch (_) {
            return 'safe';
        }
    }

    function setModConfirmationMode(mode, silent) {
        _modConfirmationMode = mode === 'fast' ? 'fast' : 'safe';
        try { window.localStorage.setItem(MOD_CONFIRMATION_STORAGE_KEY, _modConfirmationMode); } catch (_) {}
        if (_tuningView && _tuningView.setModConfirmationMode) {
            _tuningView.setModConfirmationMode(_modConfirmationMode);
        }
        refreshModConfirmationToggle();
        if (!silent) toast(_modConfirmationMode === 'fast'
            ? '配件快速模式：无连带变化时预览后自动提交。'
            : '配件安全模式：所有操作均停在预览等待确认。');
        return true;
    }

    function createModConfirmationToggle() {
        var root = document.createElement('div');
        root.className = 'equipment-tuning-mode-switch equipment-tuning-confirmation-toggle';
        var label = document.createElement('span');
        label.className = 'equipment-tuning-mode-label';
        label.textContent = '配件';
        root.appendChild(label);
        [['safe','安全'],['fast','快速']].forEach(function(pair) {
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'equipment-tuning-mode-option equipment-tuning-confirmation-option';
            button.textContent = pair[1];
            button.setAttribute('data-confirmation-mode', pair[0]);
            button.setAttribute('aria-label', '配件操作' + pair[1] + '模式');
            button.addEventListener('click', function() { setModConfirmationMode(pair[0], false); });
            root.appendChild(button);
        });
        return root;
    }

    function refreshModConfirmationToggle() {
        if (!_modConfirmationToggle) return;
        _modConfirmationToggle.hidden = _viewMode !== 'tuning';
        var options = _modConfirmationToggle.querySelectorAll('[data-confirmation-mode]');
        for (var i = 0; i < options.length; i++) {
            options[i].setAttribute('aria-pressed', options[i].getAttribute('data-confirmation-mode') === _modConfirmationMode
                ? 'true' : 'false');
        }
    }

    function buildProfileDOM(config, initialView) {
        if (typeof Workbench === 'undefined') throw new Error('Workbench runtime is required');
        if (!config || (initialView !== 'storage' && initialView !== 'tuning')) throw new Error('Inventory workbench initData rejected');
        if (_pager) _pager.detach();
        for (var oldDrag = 0; oldDrag < _dragControllers.length; oldDrag++) _dragControllers[oldDrag].cancel();
        if (_broker) _broker.clearSelection();
        disposeInventoryControls();
        if (_tuningView) { _tuningView.destroy(); _tuningView = null; }
        if (_shell) _shell.destroy();
        while (_shellEl.firstChild) _shellEl.removeChild(_shellEl.firstChild);
        _shell = null;
        _el = null;
        _backpackView = null;
        _rightView = null;
        _viewSwitchButton = null;
        _tuningHelpButton = null;
        _modConfirmationToggle = null;
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
        _viewMode = initialView;
        _rightContainerId = config.rightContainerId;
        _rightLimit = config.rightLimit;
        _modConfirmationMode = readModConfirmationMode();
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
        _el.setAttribute('data-workbench-view', _viewMode);

        if (_profile === 'warehouse') installQuickTransferActions();

        if (_densityController) _densityController.destroy();
        _densityController = new Workbench.GridDensityController({panelId:'workbench'});
        _layoutMode = _densityController.mode;
        _el.setAttribute('data-layout-mode', _layoutMode);
        var layoutToggle = _densityController.createToggle(function(mode) {
            _layoutMode = mode;
            if (_el) _el.setAttribute('data-layout-mode', mode);
        });
        _shell.addHeaderAction(layoutToggle);

        _retryButton = document.createElement('button');
        _retryButton.type = 'button';
        _retryButton.className = 'workbench-mode-btn warning';
        _retryButton.textContent = '重试同步';
        _retryButton.style.display = 'none';
        _retryButton.addEventListener('click', retryRefresh);
        _shell.addHeaderAction(_retryButton);

        if (_tuningOrigin) {
            _modConfirmationToggle = createModConfirmationToggle();
            _shell.addHeaderAction(_modConfirmationToggle);

            _viewSwitchButton = document.createElement('button');
            _viewSwitchButton.type = 'button';
            _viewSwitchButton.className = 'workbench-mode-btn equipment-tuning-view-switch';
            _viewSwitchButton.addEventListener('click', function() {
                switchWorkbenchView(_viewMode === 'tuning' ? 'storage' : 'tuning');
            });
            _shell.addHeaderAction(_viewSwitchButton);

            _tuningHelpButton = document.createElement('button');
            _tuningHelpButton.type = 'button';
            _tuningHelpButton.className = 'workbench-mode-btn equipment-tuning-help-btn';
            _tuningHelpButton.textContent = '?';
            _tuningHelpButton.setAttribute('aria-label', '查看装备调制帮助');
            _tuningHelpButton.addEventListener('click', openTuningHelp);
            _shell.addHeaderAction(_tuningHelpButton);
        }

        if (_returnTarget) {
            var returnButton = document.createElement('button');
            returnButton.type = 'button';
            returnButton.className = 'workbench-mode-btn inventory-return-crafting-btn';
            returnButton.textContent = '返回合成';
            returnButton.setAttribute('aria-label', '返回合成并重新核算原配方与份数');
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
        _tuningView = EquipmentTuningView.create({
            instanceKey:'equipment-tuning:' + _profile,
            send:function(message) { return Bridge.send(message); },
            timeoutMs:_runtimeConfig.requestTimeoutMs,
            sessionNonce:_runtimeConfig.sessionNonce,
            beginWrite:function(owner) { return _coordinator.beginExternalWrite(owner); },
            completeWrite:function(needsRefresh, callback) { return _coordinator.completeExternalWrite(needsRefresh, callback); },
            refreshInventory:function(callback) {
                return _coordinator.debugState().refreshRequired
                    ? _coordinator.retryRefresh(callback) : _coordinator.refresh(callback);
            },
            resolveSlot:function(containerId, physicalSlot) { return findCurrentSlot(containerId, physicalSlot); },
            onStateChange:function() { refreshControls(); },
            densityController:_densityController,
            modConfirmationMode:_modConfirmationMode,
            loadConversionCandidates:loadTuningConversionCandidates,
            toast:toast
        });

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

        if (_viewMode === 'tuning') _tuningView.openSession(_panelInstanceId);
        if (!_shell.mountInitial(_backpackView, _viewMode === 'tuning' ? _tuningView : _rightView)) {
            throw new Error('Inventory workbench initial view configuration rejected');
        }
        updateWorkbenchViewChrome(config);
        installInteractions();
        _shellEl.appendChild(_el);
    }

    function switchWorkbenchView(nextView, preferredSlot) {
        if (!_tuningOrigin || !_shell || !_tuningView || !_rightView
                || (nextView !== 'storage' && nextView !== 'tuning') || nextView === _viewMode) return false;
        if (_state.busyOwner || _quickInFlight || _quickPending.length) {
            toast('库存或调制写入尚未完成，请稍候切换。');
            return false;
        }
        if (_viewMode === 'tuning' && !_tuningView.canClose()) {
            toast('调制请求或对账尚未完成，请稍候切换。');
            return false;
        }
        if (_viewMode === 'tuning' && nextView === 'storage') {
            var started = _tuningView.detachSession(function(detached) {
                if (!detached) {
                    toast('未能撤销调制令牌，仍停留在调制视图。');
                    return;
                }
                finishWorkbenchViewSwitch('storage');
            });
            if (!started) toast('当前无法撤销调制令牌，请稍候重试。');
            return started;
        }
        return finishWorkbenchViewSwitch(nextView, preferredSlot);
    }

    function finishWorkbenchViewSwitch(nextView, preferredSlot) {
        exitQuickMode();
        for (var i = 0; i < _dragControllers.length; i++) _dragControllers[i].cancel();
        clearSelection();
        hideTooltip();
        if (nextView === 'tuning') {
            if (!_tuningView.openSession(_panelInstanceId) || !_shell.moveView('R', _tuningView)) {
                _tuningView.closeSession();
                toast('无法建立装备调制会话。');
                return false;
            }
        } else {
            if (!_shell.moveView('R', _rightView)) return false;
        }
        _viewMode = nextView;
        _el.setAttribute('data-workbench-view', _viewMode);
        updateWorkbenchViewChrome(resolveProfile({profile:_profile}));
        renderInventories();
        refreshControls();
        if (_viewMode === 'tuning') {
            if (preferredSlot && preferredSlot.occupied && preferredSlot.item
                    && preferredSlot.item.itemKind === 'equipment') {
                _tuningView.handleInventorySelection(preferredSlot);
            } else maybeSelectFirstTunable();
        }
        return true;
    }

    function updateWorkbenchViewChrome(config) {
        if (!_shell || !config) return;
        if (_viewMode === 'tuning') {
            _shell.setTitle('装备调制', '背包装备 · D.L.S. 调制终端');
            _shell.setSlotLabel('R', '调制操作');
        } else {
            _shell.setTitle(config.title, '');
            _shell.setSlotLabel('R', config.title);
        }
        if (_viewSwitchButton) {
            _viewSwitchButton.textContent = _viewMode === 'tuning' ? '返回收纳' : '装备调制';
            _viewSwitchButton.setAttribute('aria-pressed', _viewMode === 'tuning' ? 'true' : 'false');
        }
        if (_tuningHelpButton) _tuningHelpButton.hidden = _viewMode !== 'tuning';
        refreshModConfirmationToggle();
    }

    function maybeSelectFirstTunable() {
        if (_viewMode !== 'tuning' || !_tuningView || !_state.ready) return false;
        var debug = _tuningView.debugState();
        if (debug.source) return false;
        var snapshot = _coordinator.getWindow('背包');
        var slots = snapshot && snapshot.slots || [];
        for (var i = 0; i < slots.length; i++) {
            if (slots[i].occupied && slots[i].item && slots[i].item.itemKind === 'equipment') {
                return _tuningView.handleInventorySelection(slots[i]);
            }
        }
        return false;
    }

    function loadTuningConversionCandidates(sourceItem, sourceRef, callback) {
        callback = typeof callback === 'function' ? callback : function() {};
        var useName = String(sourceItem && sourceItem.use || '');
        var major = ItemFilter.majorDefinition(sourceItem && sourceItem.majorType).id;
        if (!useName || (major !== 'weapon' && major !== 'armor')) {
            callback({success:false, error:'invalid_equipment'});
            return false;
        }
        return _coordinator.readProjection({
            containerId:'背包', offset:0, limit:50,
            filterKey:major, filterSpec:{branch:'category', major:major, use:useName}
        }, function(result) {
            if (!result || result.success !== true || !result.snapshot) {
                callback({success:false, error:result && result.error || 'inventory_projection_failed'});
                return;
            }
            var slots = result.snapshot.slots || [], candidates = [];
            for (var i = 0; i < slots.length; i++) {
                var slot = slots[i], item = slot && slot.item;
                if (!slot || !slot.occupied || !item || item.itemKind !== 'equipment'
                        || String(item.use || '') !== useName
                        || (sourceRef && Number(slot.physicalSlot) === Number(sourceRef.slot))) continue;
                candidates.push(slot);
            }
            callback({success:true, candidates:candidates, count:candidates.length});
        });
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
        button.setAttribute('aria-label', label + '（' + direction + '）；也可随时 Ctrl+单击单件快速转移');
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
            if (event.target && event.target.closest
                    && event.target.closest('.inventory-discard-btn')) return;
            if (_viewMode === 'tuning' && containerId === '背包') {
                if (_state.busyOwner || _state.refreshRequired) return;
                if (!slot.occupied || !slot.item || slot.item.itemKind !== 'equipment') {
                    toast('装备调制只接受背包内武器与防具。');
                    return;
                }
                clearSelection();
                _tuningView.handleInventorySelection(slot);
                return;
            }
            if (handleQuickTransferClick(event, containerId, slot)) return;
            if (_state.busyOwner || _state.refreshRequired) return;
            var view = containerId === '背包' ? _backpackView : _rightView;
            if (_broker.debugState().selectedInstanceKey && !_broker.isSelectedNode(node)) _broker.activateSelected(view, {item:slot, node:node}, 'click');
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
                if (_viewMode === 'tuning' || _quickMode || !_state.ready || _state.busyOwner || _state.refreshRequired) return null;
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
        if (_viewMode === 'tuning') return false;
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
        applyTuningConversionSlotState();
    }

    function applyTuningConversionSlotState() {
        if (!_backpackView || !_tuningView) return;
        var nodes = _backpackView.root.querySelectorAll('.inventory-slot-card');
        for (var i = 0; i < nodes.length; i++) nodes[i].classList.remove('equipment-conversion-source');
        var debug = _tuningView.debugState();
        if (_viewMode !== 'tuning' || debug.operation !== 'convert' || !debug.source) return;
        var source = _backpackView.root.querySelector('[data-physical-slot="' + Number(debug.source.slot) + '"]');
        if (source) source.classList.add('equipment-conversion-source');
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
        var discardButtons = _el.querySelectorAll('.inventory-discard-btn');
        for (var d = 0; d < discardButtons.length; d++) discardButtons[d].style.display = _viewMode === 'tuning' ? 'none' : '';
        if (_pager) _pager.setDisabled(blocked);
        if (_backpackSortControls) _backpackSortControls.setDisabled(blocked);
        if (_rightSortControls) {
            _rightSortControls.setDisabled(blocked);
            var rightSnapshot = _coordinator.getWindow(_rightContainerId);
            _rightSortControls.setAuthorityDisabled(blocked
                || !rightSnapshot || Number(rightSnapshot.accessibleCapacity) <= 0);
        }
        if (_retryButton) _retryButton.style.display = _state.refreshRequired ? '' : 'none';
        var quickBlocked = _viewMode === 'tuning' || !_state.ready || !!_state.refreshRequired
            || (!!_state.busyOwner && _state.busyOwner !== 'inventory.autoTransfer');
        if (_quickDepositButton) _quickDepositButton.disabled = quickBlocked;
        if (_quickWithdrawButton) _quickWithdrawButton.disabled = quickBlocked;
        if (_viewSwitchButton) _viewSwitchButton.disabled = !!_state.busyOwner || !!_state.refreshRequired;
        updateQuickTransferUI();
        if (!_shell) return;
        if (_state.refreshRequired) _shell.setStatus('同步失败', 'warning');
        else if (_state.busyOwner) _shell.setStatus('处理中', 'busy');
        else if (_state.ready) _shell.setStatus('已同步', 'ready');
        else _shell.setStatus('同步中', 'busy');
    }

    function confirmDiscard(containerId, slot) {
        if (_viewMode === 'tuning' || containerId !== '背包' || !slot.occupied || !_state.ready) return;
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
        initData = initData || {};
        var profileConfig = resolveProfile(initData);
        var requestedView = resolveView(initData);
        if (!profileConfig || !requestedView) {
            toast('物品工作台启动参数无效。');
            closePanel(true);
            return;
        }
        _panelInstanceId = String(initData.panelInstanceId || '');
        if (requestedView === 'tuning' && !EquipmentTuningRuntime.safeToken(_panelInstanceId)) {
            toast('装备调制缺少 Host 面板实例。');
            closePanel(true);
            return;
        }
        // battlebox 就是玩家正常装备调制入口，不接受 Host/debug capability 制造无调制分支。
        _tuningOrigin = profileConfig.profile === 'battlebox';
        _returnTarget = resolveReturnTarget(initData);
        buildProfileDOM(profileConfig, requestedView);
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
            else maybeSelectFirstTunable();
        });
    }

    function openTuningHelp() {
        if (!_shell || _viewMode !== 'tuning') return false;
        return !!_shell.openModal({
            kind:'equipment-tuning-help',
            title:'装备调制帮助',
            message:'从左侧装备开始\n• 选择背包内的武器或防具，右侧会显示当前调制状态。\n• “强化度”可直接选择目标等级；顶部强化石核心会显示持有量、消耗与强化后剩余。\n• “交换”只列出同类且强化度不同的装备；选择目标即可预览。',
            detail:'进阶与配件\n• 进阶和配件候选由当前装备、持有材料及游戏进度共同决定。\n• D.L.S. 分类导航可按档级、用途、定位和状态逐层筛选。\n• 点击已安装配件可选择新配件直接替换；配件右上角 × 可直接卸下单件。\n• 紧凑模式使用物品格同尺寸图标，一屏浏览更多候选；悬停或聚焦可查看完整说明。\n\n安全 / 快速\n• 安全模式：选择候选不会立刻修改存档；所有操作都停在权威预览，确认材料和前后结果后再提交。\n• 快速模式：仅单件安装、无连带变化的单件替换或卸下会在权威预览后自动提交。\n• 依赖级联、材料异常、卸下全部、强化、交换与进阶始终停在预览等待确认。\n• 显示为不可用的候选不能选择；交换候选显示在右侧，不改变左侧筛选和面包屑。',
            actions:[{id:'close', label:'知道了', primary:true, audioCue:'confirm'}]
        });
    }

    function onRebind(el, initData) {
        // Host 已为同名 reopen 盖新 panelInstanceId；旧 tuning 子会话和所有 token 必须先失效。
        cleanup();
        onOpen(el, initData || {});
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
        if (_tuningView) _tuningView.closeSession();
        disposeInventoryControls();
        if (_densityController) { _densityController.destroy(); _densityController = null; }
    }

    function disposeInventoryControls() {
        if (_backpackSortControls && typeof _backpackSortControls.destroy === 'function') _backpackSortControls.destroy();
        if (_rightSortControls && typeof _rightSortControls.destroy === 'function') _rightSortControls.destroy();
        _backpackSortControls = null;
        _rightSortControls = null;
    }

    function closePanel(forceClose) {
        if (_shell && _shell.hasModal()) { _shell.closeModal(); return; }
        if (_state.busyOwner || _quickInFlight || _quickPending.length) {
            toast(_viewMode === 'tuning' ? '调制写入与对账尚未完成，请稍候关闭。' : '库存写入尚未完成，请稍候关闭。');
            return;
        }
        if (_viewMode === 'tuning' && _tuningView && !_tuningView.canClose()) {
            toast('调制请求或对账尚未完成，请稍候关闭。');
            return;
        }
        if (!forceClose && exitQuickMode()) return;
        if (_viewMode === 'tuning' && _tuningView) {
            var started = _tuningView.detachSession(function(detached) {
                if (detached) finishClosePanel(forceClose);
                else toast('未能撤销调制令牌，面板保持打开。');
            });
            if (!started) toast('当前无法撤销调制令牌，请稍候重试。');
            return;
        }
        finishClosePanel(forceClose);
    }

    function finishClosePanel(forceClose) {
        if (!forceClose && _returnTarget) { returnToPanel(); return; }
        Panels.close();
        var closeMessage = {type:'panel', cmd:'close', panel:'workbench'};
        if (_panelInstanceId) closeMessage.panelInstanceId = _panelInstanceId;
        Bridge.send(closeMessage);
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
        if (_tuningView && _tuningView.retryInventoryRefresh()) return;
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
                view:_viewMode,
                panelInstanceId:_panelInstanceId,
                rightContainerId:_rightContainerId,
                coordinator:_coordinator.debugState(),
                rightAccessibleCapacity:right ? Number(right.accessibleCapacity) : null,
                battleboxAccessibleCapacity:_profile === 'battlebox' && right ? Number(right.accessibleCapacity) : null,
                returnTarget:_returnTarget ? {panel:_returnTarget.panel, initData:_returnTarget.initData} : null,
                tuning:_tuningView ? _tuningView.debugState() : null,
                modConfirmationMode:_modConfirmationMode,
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
