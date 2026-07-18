/**
 * KShop — K点商城面板
 *
 * 数据流: SHOP 按钮 → C# shopPanelOpen → panel_cmd open → KShop.onOpen
 *         → bulkQuery → Flash 回包 → 渲染商品列表
 * 关闭:   ESC/遮罩/关闭按钮 → requestClose → 写协调器收口/对账 → close → shopPanelClose
 *
 * 商城行为:
 *   - 等级限制: item.level <= playerLevel + reverseLevel 才可购买
 *   - 购买分流: 消耗品/收集品 → 数量+/-, 其他(装备) → 单次加购(qty固定1)
 *   - 新购买: checkoutPreview 权威核算 → checkoutCommit 原子直接入包
 *   - 旧存档: 商城已购买物品仅保留历史 claim 兼容，不再增长
 */
var KShop = (function() {
    'use strict';

    var _catalog = [];
    var _cart = [];           // [{idx, qty}, ...]
    var _purchased = [];
    var _purchasedToken = '';
    var _kpoints = 0;
    var _playerLevel = 0;
    var _reverseLevel = 0;
    var _shopReady = false;
    var _closing = false;
    var _loading = false;
    var _writeState = null;
    var _runtimeConfig = (typeof window !== 'undefined' && window.__KSHOP_RUNTIME_CONFIG__) || {};
    var _mux = new KShopRequestMux({
        send: function(message) { Bridge.send(message); },
        timeoutMs: _runtimeConfig.requestTimeoutMs,
        sessionNonce: _runtimeConfig.sessionNonce,
        onProtocolError: function(message) {
            if (typeof console !== 'undefined' && console.warn) console.warn(message);
        }
    });
    var _writeCoordinator = new KShopWriteCoordinator({
        request: requestShop,
        getCart: buildCartPayload,
        getPurchasedToken: function() { return _purchasedToken; },
        applyBulkSnapshot: applyBulkSnapshot,
        onStateChange: refreshWriteControls,
        debounceMs: _runtimeConfig.cartSaveDebounceMs
    });
    var _inventoryState = { opened: false, ready: false, busyOwner: null, refreshRequired: false };
    var _inventoryCoordinator = new InventoryRuntime.InventoryCoordinator({
        request: requestInventory,
        onStateChange: function(state) {
            _inventoryState = state;
            if (_ownedPresenter) _ownedPresenter.render();
            refreshWriteControls(_writeState || _writeCoordinator.debugState());
        },
        requests: [
            {containerId: '背包', offset: 0, limit: 50},
            {containerId: '战备箱', offset: 0, limit: 40}
        ]
    });

    // Workbench orchestration refs. Presenters own local DOM and interaction details.
    var _workbenchShell, _catalogView, _orderView, _backpackView, _warehouseView;
    var _cartGridView, _purchasedGridView, _catalogRenderer, _interactionBroker, _dragController;
    var _shopModeButton, _inventoryModeButton, _inventoryRetryButton, _modeChoiceGroup;
    var _cartDropTarget, _selectedCatalogIdx = null;
    var _dragTooltipSuppressed = false;
    var _ownedTooltipSelectionSuppressed = false;
    var _layoutMode = 'full', _densityController = null;
    var _el, _shellEl, _grid, _balanceEl, _checkoutBtn, _loadingEl;
    var _scaleHandle = null;   // 沉浸全屏化：PanelScale 句柄

    var _catalogPresenter = new KShopCatalogPresenter.CatalogPresenter({
        state:{
            getCatalog:function() { return _catalog; },
            getPlayerLevel:function() { return _playerLevel; },
            getReverseLevel:function() { return _reverseLevel; },
            getSelectedIdx:function() { return _selectedCatalogIdx; },
            canEdit:canEditCart
        },
        intent:{
            clearSelection:function() { if (_interactionBroker) _interactionBroker.clearSelection(); },
            select:function(item, node) { if (_interactionBroker) _interactionBroker.select(_catalogView, item, node); },
            dispatchAdd:function(item, origin) {
                if (_interactionBroker) _interactionBroker.dispatch(_catalogView, item, _orderView, {binding:'shop:cart'}, origin);
            },
            addFromButton:function(event) { _cartController.onAddFromButton(event); },
            consumeDragClick:function() { return !!(_dragController && _dragController.consumeClick()); },
            bindTooltip:function(node, item) { _tooltipPresenter.bindCatalog(node, item); },
            iconHtml:iconHtml,
            playCue:playCue,
            renderComplete:function() { refreshWriteControls(_writeState || _writeCoordinator.debugState()); },
            iconsReady:function() { _cartController.render(); renderClaimed(); }
        }
    });

    var _tooltipPresenter = new KShopTooltipPresenter.TooltipPresenter({
        state:{
            isLocked:isLocked,
            isOpen:isKShopOpen,
            isDragSuppressed:function() { return _dragTooltipSuppressed; },
            isOwnedSelectionSuppressed:function() { return _ownedTooltipSelectionSuppressed; },
            findCatalogItem:findCatalogItem
        },
        intent:{
            requestShop:requestShop,
            requestInventory:requestInventory,
            ownedSlotRef:KShopOwnedInventoryPresenter.ownedSlotRef
        }
    });

    var _cartController = new KShopCartController.CartController({
        state:{
            getCart:function() { return _cart; },
            getBalance:function() { return _kpoints; },
            findCatalogItem:findCatalogItem,
            isStackable:isStackable,
            isLocked:isLocked,
            canEdit:canEditCart,
            canStartWrite:canStartShopWrite,
            getShellElement:function() { return _shellEl; }
        },
        intent:{
            replaceCart:function(next) { _cart = next; },
            markDirty:markCartDirty,
            refreshControls:function() { refreshWriteControls(_writeState || _writeCoordinator.debugState()); },
            toast:toast,
            playCue:playCue,
            iconHtml:iconHtml,
            escapeHtml:escHtml,
            inspect:function(idx, anchor) { _tooltipPresenter.showItemDetail(idx, anchor); },
            requestShop:requestShop,
            errorMessage:messageForError,
            commitCheckout:commitCheckout,
            activateSelected:function() {
                return _interactionBroker.activateSelected(_orderView, {binding:'shop:cart'}, 'click');
            }
        }
    });

    var _ownedPresenter = new KShopOwnedInventoryPresenter.OwnedInventoryPresenter({
        state:{
            getWindow:function(containerId) { return _inventoryCoordinator.getWindow(containerId); },
            getRequest:function(containerId) { return _inventoryCoordinator.getRequest(containerId); },
            getStatus:function() { return _inventoryState; },
            getInteractionBroker:function() { return _interactionBroker; },
            getWorkbenchShell:function() { return _workbenchShell; },
            isOpen:isKShopOpen,
            isInventoryModeActive:function() {
                return !!(_inventoryModeButton && _inventoryModeButton.classList.contains('active'));
            },
            getDragTimeout:function() { return _runtimeConfig.dragTimeoutMs || 1400; }
        },
        intent:{
            setWindow:function(containerId, offset, limit, callback) {
                return _inventoryCoordinator.setWindow(containerId, offset, limit, callback);
            },
            setFilter:function(containerId, key, callback) { return _inventoryCoordinator.setFilter(containerId, key, callback); },
            setFilterSpec:function(containerId, spec, callback) { return _inventoryCoordinator.setFilterSpec(containerId, spec, callback); },
            resetWindow:function(containerId, offset, limit, key) { return _inventoryCoordinator.resetWindow(containerId, offset, limit, key); },
            sortAndMerge:function(containerId, method, callback) { return _inventoryCoordinator.sortAndMerge(containerId, method, callback); },
            discard:function(source, callback) { return _inventoryCoordinator.discard(source, callback); },
            transfer:function(payload, callback) { return _inventoryCoordinator.transfer(payload, callback); },
            bindTooltip:function(node, containerId, slot) { _tooltipPresenter.bindOwned(node, containerId, slot); },
            hideTooltip:function() { _tooltipPresenter.hide(); },
            setDragSuppressed:function(value) { _dragTooltipSuppressed = !!value; },
            iconHtml:iconHtml,
            escapeHtml:escHtml,
            toast:toast,
            playCue:playCue
        }
    });

    var _kHandler = function(v) { _kpoints = Number(v); if (_balanceEl) _balanceEl.textContent = _kpoints; };

    // ── Helpers ──
    function isStackable(item) {
        return KShopCatalogPresenter.isStackable(item);
    }
    function isLocked(item) {
        return KShopCatalogPresenter.isLocked(item, _playerLevel, _reverseLevel);
    }
    function findCatalogItem(idx) {
        return KShopCatalogPresenter.findCatalogItem(_catalog, idx);
    }
    function escHtml(s) {
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }
    function iconHtml(iconName, cls) {
        var icon = (typeof Icons !== 'undefined' && Icons.html)
            ? Icons.html(iconName, cls || 'kshop-icon', ' onerror="this.style.display=\'none\'"')
            : '';
        return icon
            ? icon
            : '<div class="' + (cls||'kshop-icon') + ' kshop-icon-placeholder"></div>';
    }
    function toast(msg) { if (typeof Toast !== 'undefined') Toast.add(msg); }
    function playCue(name) {
        if (typeof BootstrapAudio === 'undefined' || !BootstrapAudio || !name) return;
        var method = 'play' + name.charAt(0).toUpperCase() + name.slice(1);
        if (typeof BootstrapAudio[method] === 'function') BootstrapAudio[method]();
    }
    function buildCartPayload() {
        return _cartController.buildPayload();
    }
    function messageForError(scope, error) {
        var code = error || 'unknown';
        if (scope === 'checkout') {
            if (code === 'insufficient_kpoints') return 'K点不足！';
            if (code === 'inventory_full') return '背包容量不足，整单未扣款。';
            if (code === 'stale_state') return '商品、余额或背包状态已变化，请重新核对。';
            if (code === 'busy') return '商城正在处理另一笔写入，请稍后再试。';
            if (code === 'timeout' || code === 'client_timeout' || code === 'reconcile_required') return '结账结果不确定，已按服务器状态刷新，未自动重试。';
            if (code === 'disconnected') return '商城连接已断开，结账不会自动重试。';
            if (typeof console !== 'undefined' && console.warn) console.warn('[KShop checkout]', code);
            return '购买失败，请重试。';
        }
        if (scope === 'claim') {
            if (code === 'inventory_full') return '物品栏已满，无法领取！';
            if (code === 'acquire_failed') return '背包空间不足，无法领取！';
            if (code === 'item_not_found') return '商品不存在或已被领取。';
            if (code === 'stale_state') return '待领取列表已变化，已刷新。';
            if (code === 'busy') return '商城正在处理另一笔写入，请稍后再试。';
            if (code === 'timeout' || code === 'client_timeout' || code === 'reconcile_required') return '领取结果不确定，已刷新已购买列表，未自动领取。';
            if (code === 'disconnected') return '商城连接已断开，领取不会自动重试。';
            if (typeof console !== 'undefined' && console.warn) console.warn('[KShop claim]', code);
            return '领取失败，请重试。';
        }
        if (scope === 'save') {
            if (code === 'busy') return '商城正在处理另一笔写入';
            if (code === 'timeout' || code === 'client_timeout' || code === 'reconcile_required') return '购物车保存结果未知，必须先完成对账';
            if (code === 'disconnected') return '商城连接已断开，购物车尚未确认保存';
            if (code !== 'unknown' && typeof console !== 'undefined' && console.warn) console.warn('[KShop save]', code);
            return '购物车保存失败';
        }
        return code;
    }
    function markCartDirty() {
        if (!_shopReady) return false;
        return _writeCoordinator.markCartChanged();
    }

    function canEditCart() {
        return _shopReady && _writeCoordinator.canEditCart();
    }

    function canStartShopWrite() {
        return _shopReady && _writeCoordinator.debugState().canStartWrite;
    }

    function requestShop(cmd, payload, callback) {
        return _mux.request('shop', cmd, payload || {}, callback);
    }

    function requestInventory(cmd, payload, callback) {
        return _mux.request('inventory', cmd, {panel: 'kshop', payload: payload || {}}, callback);
    }

    function isKShopOpen() {
        return Panels.getActive ? Panels.getActive() === 'kshop' : Panels.isOpen();
    }

    function applyBulkSnapshot(resp, options) {
        options = options || {};
        _catalog = resp.catalog || _catalog || [];
        if (!options.preserveCart) _cart = resp.cart || [];
        _purchased = resp.purchased || [];
        _purchasedToken = String(resp.purchasedToken || '');
        _kpoints = Number(resp.kpoints || 0);
        _playerLevel = Number(resp.playerLevel || 0);
        _reverseLevel = Number(resp.reverseLevel || 0);
        if (_balanceEl) _balanceEl.textContent = _kpoints;
        _catalogPresenter.rebuildCategories();
        _catalogPresenter.render();
        _cartController.render();
        renderClaimed();
    }

    function refreshWriteControls(state) {
        _writeState = state;
        if (!_el) return;
        var blockEdits = !_shopReady || (state && !state.canEditCart);
        var inventoryBlocked = !_inventoryState.ready || !!_inventoryState.busyOwner || !!_inventoryState.refreshRequired;
        var blockWrites = !_shopReady || (state && !state.canStartWrite);
        var claimBlocked = !!blockWrites || inventoryBlocked;
        _el.classList.toggle('kshop-write-busy', !!blockWrites || !!(state && state.saveInFlight));
        var editButtons = _el.querySelectorAll('.kshop-add-btn,.kshop-qty-btn,.kshop-qty-pop-btn,.kshop-qty-confirm');
        for (var i = 0; i < editButtons.length; i++) editButtons[i].disabled = !!blockEdits;
        if (_checkoutBtn) _checkoutBtn.disabled = _cart.length === 0 || !!blockWrites;
        if (_cartController.getSettlement()) _cartController.getSettlement().render();
        var claimButtons = _el.querySelectorAll('.kshop-claim-btn');
        for (var j = 0; j < claimButtons.length; j++) claimButtons[j].disabled = claimBlocked;
        var ownedNodes = _el.querySelectorAll('.inventory-slot-card');
        for (var k = 0; k < ownedNodes.length; k++) ownedNodes[k].classList.toggle('write-locked', inventoryBlocked);
        _ownedPresenter.setDisabled(inventoryBlocked);
        if (_inventoryRetryButton) _inventoryRetryButton.style.display = _inventoryState.refreshRequired ? '' : 'none';
        if (_cartDropTarget) {
            _cartDropTarget.classList.toggle('disabled', !!blockEdits);
            _cartDropTarget.setAttribute('aria-disabled', blockEdits ? 'true' : 'false');
        }
        if (_dragController && blockEdits) _dragController.cancel();
        if (_workbenchShell) {
            if (!_shopReady) _workbenchShell.setStatus(_loading ? '同步中' : '商城暂不可用', _loading ? 'busy' : 'warning');
            else if (_inventoryState.refreshRequired) _workbenchShell.setStatus('背包同步失败', 'warning');
            else if (_inventoryState.busyOwner) _workbenchShell.setStatus('处理中', 'busy');
            else if (state && state.reconcileBlocked) _workbenchShell.setStatus('同步失败', 'warning');
            else if (state && state.reconciling) _workbenchShell.setStatus('正在恢复', 'busy');
            else if (state && state.exclusive) _workbenchShell.setStatus('正在提交', 'busy');
            else if (state && (state.saveInFlight || state.dirty)) _workbenchShell.setStatus('正在保存', state.saveInFlight ? 'busy' : 'pending');
            else _workbenchShell.setStatus('已同步', 'ready');
        }
        if (blockEdits) _cartController.dismissQuantityInput();
        if (state && state.reconcileBlocked) {
            showSaveFailedDialog('商城对账失败，写操作保持锁定', true);
        }
    }

    // ══════════════════════════════════════════
    //  Panel registration
    // ══════════════════════════════════════════
    Panels.register('kshop', {
        create: createDOM,
        onOpen: onOpen,
        onClose: onClose,
        onRequestClose: function() { requestClose(); },
        onForceClose: onForceClose
    });

    function createDOM() {
        if (typeof Workbench === 'undefined') throw new Error('Workbench runtime is required before KShop');
        if (typeof KShopViews === 'undefined') throw new Error('KShop view composition is required before KShop');
        _workbenchShell = new Workbench.DualPaneShell({
            eyebrow: '',
            title: 'K点商城',
            subtitle: '',
            status: '同步中',
            flowLabel: '',
            leftLabel: '商品',
            rightLabel: '购物车'
        });
        _el = _workbenchShell.getRoot();
        _el.classList.add('kshop-workbench');
        _balanceEl = _workbenchShell.setMetric('kpoints', 'K', 0);

        _modeChoiceGroup = new WorkbenchComponents.ChoiceGroup({
            document:document,
            className:'workbench-mode-switch',
            ariaLabel:'商城工作区',
            value:'shop',
            choices:[
                {value:'shop', label:'商城', className:'workbench-mode-btn', dataAttribute:'data-mode'},
                {value:'inventory', label:'战备箱', className:'workbench-mode-btn', dataAttribute:'data-mode'}
            ],
            onChange:function(mode) { if (mode === 'inventory') showInventoryMode(); else showShopMode(); }
        });
        var modeSwitch = _modeChoiceGroup.root;
        _shopModeButton = _modeChoiceGroup.getButton('shop');
        _inventoryModeButton = _modeChoiceGroup.getButton('inventory');
        _inventoryRetryButton = document.createElement('button');
        _inventoryRetryButton.type = 'button';
        _inventoryRetryButton.className = 'workbench-mode-btn warning';
        _inventoryRetryButton.textContent = '重试库存同步';
        _inventoryRetryButton.style.display = 'none';
        _inventoryRetryButton.addEventListener('click', function() {
            _inventoryCoordinator.retryRefresh(function(result) {
                if (!result.success) {
                    if (typeof console !== 'undefined' && console.warn) console.warn('[KShop inventory retry]', result.error || 'unknown');
                    toast('库存同步仍然失败，请稍后重试。');
                }
            });
        });
        modeSwitch.appendChild(_shopModeButton);
        modeSwitch.appendChild(_inventoryModeButton);
        modeSwitch.appendChild(_inventoryRetryButton);
        _workbenchShell.addHeaderAction(modeSwitch);

        if (_densityController) _densityController.destroy();
        _densityController = new Workbench.GridDensityController({panelId:'kshop'});
        _layoutMode = _densityController.mode;
        var layoutToggle = _densityController.createToggle(function(mode) { _layoutMode = mode; });
        _workbenchShell.addHeaderAction(layoutToggle);

        var closeButton = document.createElement('button');
        closeButton.className = 'kshop-close-btn workbench-close-btn';
        closeButton.type = 'button';
        closeButton.textContent = '×';
        closeButton.setAttribute('aria-label', '关闭商城');
        closeButton.setAttribute('data-audio-cue', 'cancel');
        closeButton.addEventListener('click', function() { requestClose(); });
        _workbenchShell.addHeaderAction(closeButton);

        _catalogView = _catalogPresenter.createView(_densityController);
        var catalogComposition = _catalogPresenter.getComposition();
        _catalogRenderer = catalogComposition.renderer;
        _grid = catalogComposition.grid;
        _loadingEl = catalogComposition.loading;

        _orderView = _cartController.createOrderView({
            getPurchased:function() { return _purchased; },
            renderPurchasedItem:renderClaimRow,
            bindPurchasedItem:bindClaimRow,
            renderPurchased:renderClaimed
        });
        var orderComposition = _cartController.getComposition();
        _cartGridView = orderComposition.cartGridView;
        _purchasedGridView = orderComposition.purchasedGridView;
        _cartDropTarget = orderComposition.dropTarget;
        _checkoutBtn = orderComposition.checkoutButton;

        var ownedViews = _ownedPresenter.createViews(_layoutMode, _densityController);
        _backpackView = ownedViews.backpack;
        _warehouseView = ownedViews.warehouse;

        _workbenchShell.registerView(_backpackView);
        _workbenchShell.registerView(_warehouseView);
        _workbenchShell.setDefault('L', _catalogView);
        _workbenchShell.setDefault('R', _orderView);
        if (!_workbenchShell.mountInitial(_catalogView, _orderView)) {
            throw new Error('KShop workbench initial view configuration rejected');
        }
        _cartController.mountSettlement(_el);
        installWorkbenchInteractions();

        // 沉浸全屏化 2026-06-11：把固定 1024×576 画布(.kshop-panel)包进共享 .panel-scale-shell，
        // 由 PanelScale 整体等比缩放，取代旧的 fluid 跟分辨率 reflow（kshop 是最早实现的 panel，配套最不全）。
        _shellEl = document.createElement('div');
        _shellEl.className = 'panel-scale-shell kshop-scale-shell';
        _shellEl.appendChild(_el);
        return _shellEl;
    }

    function showShopMode() {
        if (!_workbenchShell) return;
        _el.setAttribute('data-workbench-skin', 'shop');
        _ownedPresenter.setMenuOpen(false);
        _workbenchShell.moveView('L', _catalogView);
        _workbenchShell.moveView('R', _orderView);
        if (_modeChoiceGroup) _modeChoiceGroup.update({value:'shop'});
        _workbenchShell.setSlotLabel('L', '商品');
        _workbenchShell.setSlotLabel('R', '购物车');
        _workbenchShell.setTitle('K点商城', '');
    }

    function showInventoryMode() {
        if (!_workbenchShell) return;
        _cartController.closeSettlement();
        _el.setAttribute('data-workbench-skin', 'inventory');
        _workbenchShell.moveView('L', _backpackView);
        _workbenchShell.moveView('R', _warehouseView);
        if (_modeChoiceGroup) _modeChoiceGroup.update({value:'inventory'});
        _workbenchShell.setSlotLabel('L', '背包');
        _workbenchShell.setSlotLabel('R', '战备箱');
        _workbenchShell.setTitle('物品管理', '');
        _ownedPresenter.render();
    }

    function installWorkbenchInteractions() {
        _interactionBroker = new Workbench.InteractionBroker({
            onIntent: handleWorkbenchIntent,
            onReject: function(result) {
                if (result && result.reason === 'write_locked') toast('商城正在处理写入，请稍后再加购。');
                else if (result && result.reason === 'same_slot' && _interactionBroker) _interactionBroker.clearSelection();
            },
            onSelectionChange: function(selection) {
                _selectedCatalogIdx = selection && selection.view === _catalogView && selection.item ? selection.item.idx : null;
                _ownedTooltipSelectionSuppressed = _ownedPresenter.selectionIsOwned(selection);
                if (_ownedTooltipSelectionSuppressed) hideTooltip();
                _catalogPresenter.setSelected(_selectedCatalogIdx);
                _cartController.setDropSelection(_selectedCatalogIdx != null ? findCatalogItem(_selectedCatalogIdx) : null);
            }
        });
        _dragController = new Workbench.PointerDragController({
            sourceElement: _grid,
            broker: _interactionBroker,
            timeoutMs: _runtimeConfig.dragTimeoutMs || 1400,
            getSource: function(target) {
                if (!canEditCart()) return null;
                var hit = _catalogRenderer.itemFromTarget(target);
                if (!hit || isLocked(hit.item) || hit.item.type === '非卖品') return null;
                return { view: _catalogView, item: hit.item, node: hit.node };
            },
            resolveTarget: function(clientX, clientY) {
                var target = document.elementFromPoint(clientX, clientY);
                if (!target || !_cartGridView.root.contains(target)) return null;
                return { view: _orderView, hit: { binding: 'shop:cart' }, node: _cartDropTarget };
            },
            renderGhost: function(source) {
                var ghost = document.createElement('div');
                ghost.className = 'workbench-drag-ghost kshop-drag-ghost';
                ghost.innerHTML = iconHtml(source.item.icon, 'kshop-row-icon') + '<span>' + escHtml(source.item.displayname) + '</span>';
                return ghost;
            },
            onDragStart: function() {
                _dragTooltipSuppressed = true;
                hideTooltip();
            },
            onDragEnd: function() {
                _dragTooltipSuppressed = false;
            }
        });
        _ownedPresenter.installDragControllers(_interactionBroker);
    }

    // ══════════════════════════════════════════
    //  Open / Data load
    // ══════════════════════════════════════════
    function onOpen(el) {
        if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = (typeof PanelScale !== 'undefined') ? PanelScale.attach(_shellEl, 1024, 576) : null;
        _closing = false;
        _shopReady = false;
        _loading = true;
        _catalog = [];
        _cart = [];
        _purchased = [];
        _purchasedToken = '';
        _catalogPresenter.reset();
        _tooltipPresenter.reset();
        _ownedTooltipSelectionSuppressed = false;
        _ownedPresenter.resetSession();
        dismissDialog();
        _cartController.closeSettlement();
        if (_interactionBroker) _interactionBroker.clearSelection();
        _catalogPresenter.rebuildCategories();
        _cartController.render();
        renderClaimed();
        _mux.openSession();
        _writeCoordinator.open();
        showShopMode();
        // 页码继续按会话记忆；分类筛选不跨打开/存档保留，避免新存档初始视图被旧筛选隐藏。
        _inventoryCoordinator.open(function(result) {
            if (!isKShopOpen()) return;
            _ownedPresenter.render();
            if (!result.success) {
                if (typeof console !== 'undefined' && console.warn) console.warn('[KShop inventory load]', result.error || 'inventory_refresh_failed');
                toast('库存同步失败，请重试。');
            }
        });
        if (_workbenchShell) _workbenchShell.setStatus('同步中', 'busy');
        UiData.on('k', _kHandler);
        if (_loadingEl) _loadingEl.style.display = '';
        if (_grid) _grid.style.opacity = '0.3';

        requestShop('bulkQuery', {}, function(resp) {
            if (!isKShopOpen()) return;
            _loading = false;
            if (_loadingEl) _loadingEl.style.display = 'none';
            if (_grid) _grid.style.opacity = '';
            if (resp.success && Array.isArray(resp.catalog) && Array.isArray(resp.cart)
                    && Array.isArray(resp.purchased) && isFinite(Number(resp.kpoints))
                    && isFinite(Number(resp.playerLevel)) && isFinite(Number(resp.reverseLevel))
                    && typeof resp.purchasedToken === 'string' && resp.purchasedToken.length > 0) {
                _shopReady = true;
                applyBulkSnapshot(resp);
                _writeCoordinator.acceptAuthoritativeCart();
            } else {
                _shopReady = false;
                refreshWriteControls(_writeCoordinator.debugState());
                toast('商城加载失败：' + messageForError('save', resp.error || 'invalid_response'));
            }
        });
    }

    function handleWorkbenchIntent(intent) {
        if (!intent || !intent.sourceRef) return;
        if (intent.operationId === 'shop.addCartIntent') {
            _cartController.addCatalogIntent(Number(intent.sourceRef.catalogIdx), 1);
            return;
        }
        if (intent.operationId === 'inventory.transfer') {
            if (!_ownedPresenter.quickTransfer(intent)) {
                toast('库存正在处理另一笔写入。');
            }
        }
    }

    // Checkout authority stays here; the controller supplies a validated preview token.
    function commitCheckout(token) {
        var inventoryWrite = _inventoryCoordinator.beginExternalWrite('shop.checkoutCommit');
        if (!inventoryWrite) {
            toast('背包尚未同步或正在处理另一笔写入。');
            _cartController.requestPreview();
            return;
        }
        if (!_writeCoordinator.checkout(token, function(resp) {
            if (!isKShopOpen()) return;
            var needsInventoryRefresh = !!resp.success || !!resp.reconciled;
            if (!_inventoryCoordinator.completeExternalWrite(inventoryWrite, needsInventoryRefresh, function(refreshResult) {
                if (!isKShopOpen()) return;
                if (resp.success) {
                    _kpoints = resp.newBalance;
                    if (_balanceEl) _balanceEl.textContent = _kpoints;
                    _purchased = resp.purchased || [];
                    _purchasedToken = String(resp.purchasedToken || _purchasedToken);
                    _cart = [];
                    _writeCoordinator.acceptAuthoritativeCart();
                    _cartController.closeSettlement();
                    _cartController.render();
                    renderClaimed();
                }
                _ownedPresenter.render();
                if (resp.success && refreshResult.success) {
                    toast('购买成功，商品已直接交付！');
                    playCue('success');
                } else if (resp.success) {
                    toast('购买已成功，但背包刷新失败；请点击“重试库存同步”。');
                    playCue('error');
                } else {
                    toast(messageForError('checkout', resp.error));
                    playCue('error');
                    if (_cartController.getSettlement().isActive()) _cartController.requestPreview();
                }
            })) return;
        })) {
            _inventoryCoordinator.completeExternalWrite(inventoryWrite, false);
            toast('商城正在处理另一笔写入，请稍后再结账。');
            _cartController.requestPreview();
        }
    }

    // ══════════════════════════════════════════
    //  Claimed items — 带图标
    // ══════════════════════════════════════════
    // 通过 itemName 反查 catalog 条目（用于已购列表取 displayname/icon）
    function findCatalogByName(name) {
        for (var i = 0; i < _catalog.length; i++) {
            if (_catalog[i].item === name) return _catalog[i];
        }
        return null;
    }

    function renderClaimed() {
        if (_purchasedGridView) {
            _purchasedGridView.renderer.render(_purchased);
            var totalPending = 0;
            for (var p = 0; p < _purchased.length; p++) {
                totalPending += Number(_purchased[p][_purchased[p].length - 1]) || 0;
            }
            _purchasedGridView.chrome.setMeta(totalPending > 0 ? totalPending + ' 件' : '');
        }
        refreshWriteControls(_writeState || _writeCoordinator.debugState());
    }

    function renderClaimRow(purchasedItem, purchasedIndex) {
        var itemName = String(purchasedItem[1]);
        var qty = purchasedItem[purchasedItem.length - 1];
        var catItem = findCatalogByName(itemName);
        var displayName = catItem ? catItem.displayname : itemName;
        var iconName = catItem ? catItem.icon : itemName;
        var row = document.createElement('article');
        row.className = 'kshop-claim-row';
        row.setAttribute('data-pidx', purchasedIndex);
        if (catItem) row.setAttribute('data-idx', catItem.idx);
        row.innerHTML =
            '<span class="kshop-cart-thumb">' + iconHtml(iconName, 'kshop-row-icon') + '</span>' +
            '<span class="kshop-claim-copy"><b class="kshop-claim-name">' + escHtml(displayName) + '</b><small>待领取 × ' + qty + '</small></span>' +
            '<button class="kshop-claim-btn" data-pidx="' + purchasedIndex + '" data-audio-cue="confirm">领取</button>';
        return row;
    }

    function bindClaimRow(row, purchasedItem, purchasedIndex) {
        var button = row.querySelector('.kshop-claim-btn');
        if (button) button.addEventListener('click', onClaim);
        if (!isNaN(Number(row.getAttribute('data-idx')))) row.addEventListener('click', onClaimRowClick);
    }

    function onClaimRowClick(e) {
        if (e.target.classList.contains('kshop-claim-btn')) return;
        var idx = Number(e.currentTarget.getAttribute('data-idx'));
        if (!isNaN(idx)) _tooltipPresenter.showItemDetail(idx, e.currentTarget);
    }

    function onClaim(e) {
        e.stopPropagation();
        if (!canStartShopWrite()) {
            toast('商城尚未同步，请稍后再领取。');
            return;
        }
        var pidx = Number(e.target.getAttribute('data-pidx'));
        var inventoryWrite = _inventoryCoordinator.beginExternalWrite('shop.claim');
        if (!inventoryWrite) {
            toast('背包尚未同步或正在处理另一笔写入。');
            return;
        }
        if (!_writeCoordinator.claim(pidx, function(resp) {
            if (!isKShopOpen()) return;
            var needsInventoryRefresh = !!resp.success
                || (!!resp.reconciled && resp.error !== 'item_not_found' && resp.error !== 'stale_state');
            if (!_inventoryCoordinator.completeExternalWrite(inventoryWrite, needsInventoryRefresh, function(refreshResult) {
                if (!isKShopOpen()) return;
                if (resp.success) {
                    _purchased = resp.purchased || [];
                    _purchasedToken = String(resp.purchasedToken || _purchasedToken);
                    renderClaimed();
                }
                _ownedPresenter.render();
                if (resp.success && refreshResult.success) {
                    toast('领取成功，背包已刷新！');
                    playCue('success');
                } else if (resp.success) {
                    toast('领取已成功，但背包刷新失败；请点击“重试库存同步”。');
                    playCue('error');
                } else {
                    toast(messageForError('claim', resp.error));
                    playCue('error');
                }
            })) return;
        })) {
            _inventoryCoordinator.completeExternalWrite(inventoryWrite, false);
            toast('商城正在处理另一笔写入，请稍后再领取。');
        }
    }

    // ══════════════════════════════════════════
    //  Close — saveCart 失败对话框
    // ══════════════════════════════════════════
    function requestClose() {
        if (_cartController.getSettlement() && _cartController.getSettlement().isActive()) {
            _cartController.closeSettlement();
            return;
        }
        if (_workbenchShell && _workbenchShell.getModalKind() === 'commit') {
            dismissDialog();
            return;
        }
        if (_closing) return;
        _closing = true;
        if (!_writeCoordinator.close(function(resp) {
            if (!isKShopOpen()) return;
            if (resp.success) {
                doClose();
            } else {
                _closing = false;
                showSaveFailedDialog(messageForError('save', resp.error),
                    resp.error === 'timeout' || resp.error === 'client_timeout' || resp.error === 'reconcile_required');
            }
        })) {
            _closing = false;
        }
    }

    function onClose() {
        // 任何关闭路径（doClose→Panels.close / C# close / 切面板 / force_close→close）都经此 detach，防 resize/RO 泄漏
        if (_scaleHandle) { _scaleHandle.detach(); _scaleHandle = null; }
        // 统一解绑 K 点订阅，避免 C# 直接关闭路径下重复累积
        UiData.off('k', _kHandler);
        if (_dragController) _dragController.cancel();
        _ownedPresenter.closeSession();
        if (_interactionBroker) _interactionBroker.clearSelection();
        dismissDialog();
        _cartController.closeSettlement();
        hideTooltip();
        _shopReady = false;
        _loading = false;
        _writeCoordinator.forceClose();
        _inventoryCoordinator.close();
        _mux.closeSession();
        _closing = false;
    }

    function doClose() {
        dismissDialog();
        _cartController.closeSettlement();
        _cartController.dismissQuantityInput();
        hideTooltip();
        Panels.close();
        Bridge.send({type:'panel', cmd:'close', panel:'kshop'});
        _closing = false;
    }

    function hideTooltip() {
        _tooltipPresenter.hide();
    }

    function showSaveFailedDialog(msg, timeoutMode) {
        playCue('modalOpen');
        var actions = [
            {
                id: 'retry', label: '重新对账', primary: true, audioCue: 'select',
                onSelect: function() { if (!_writeCoordinator.retryReconcile()) requestClose(); }
            }
        ];
        if (!timeoutMode) {
            actions.push({ id: 'cancel', label: '继续购物', audioCue: 'cancel', onSelect: function() { _closing = false; } });
        }
        actions.push({ id: 'force', label: '强制关闭', danger: true, audioCue: 'error', onSelect: doClose });
        _workbenchShell.openModal({
            kind: 'reconcile',
            kicker: '',
            title: msg,
            message: timeoutMode ? '购物车状态暂时无法确认。' : '可以重新同步，或返回继续购物。',
            detail: '强制关闭可能丢失尚未保存的购物车修改。',
            actions: actions
        });
    }

    function dismissDialog() {
        if (_workbenchShell) _workbenchShell.closeModal();
    }

    function onForceClose() {
        _closing = false;
        _shopReady = false;
        _loading = false;
        if (_dragController) _dragController.cancel();
        _ownedPresenter.closeSession();
        if (_interactionBroker) _interactionBroker.clearSelection();
        _writeCoordinator.forceClose();
        _inventoryCoordinator.close();
        _mux.closeSession();
        dismissDialog();
        _cartController.closeSettlement();
        _cartController.dismissQuantityInput();
        hideTooltip();
        toast('连接断开，商城已关闭');
    }

    return {
        debugState: function() {
            var cartDebug = _cartController.debugState();
            return {
                shell: _workbenchShell ? {
                    left: _workbenchShell.getHost('L').currentView && _workbenchShell.getHost('L').currentView.instanceKey,
                    right: _workbenchShell.getHost('R').currentView && _workbenchShell.getHost('R').currentView.instanceKey,
                    modal: _workbenchShell.hasModal()
                } : null,
                requestMux: _mux.debugState(),
                write: _writeCoordinator.debugState(),
                inventory: _inventoryCoordinator.debugState(),
                drag: _dragController ? _dragController.debugState() : null,
                selectedCatalogIdx: _selectedCatalogIdx,
                shopReady: _shopReady,
                cartCount: _cart.length,
                purchasedCount: _purchased.length,
                settling: cartDebug.settling,
                previewBusy: cartDebug.previewBusy,
                hasCheckoutPreview: cartDebug.hasCheckoutPreview,
                settlement: cartDebug.settlement
            };
        }
    };
})();
