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
    var _categoryPath = [];
    var _categoryTree = null;
    var _categoryNavigator = null;
    var _iconsLoaded = false;
    var _loading = false;
    var _writeState = null;
    var _checkoutPreview = null;
    var _previewBusy = false;
    var _previewQueued = false;
    var _previewRevision = 0;
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
            renderOwnedInventories();
            refreshWriteControls(_writeState || _writeCoordinator.debugState());
        },
        requests: [
            {containerId: '背包', offset: 0, limit: 50},
            {containerId: '战备箱', offset: 0, limit: 40}
        ]
    });

    // Gate A1 workbench primitives + DOM refs
    var _workbenchShell, _catalogView, _orderView, _catalogChrome, _backpackView, _warehouseView;
    var _cartGridView, _purchasedGridView, _catalogRenderer, _interactionBroker, _dragController, _settlementView;
    var _ownedViews = [], _ownedDragControllers = [];
    var _shopModeButton, _inventoryModeButton, _inventoryRetryButton;
    var _warehousePager, _backpackSortControls, _warehouseSortControls;
    var _cartDropTarget, _cartDropLabel, _selectedCatalogIdx = null;
    var _dragTooltipSuppressed = false;
    var _ownedTooltipSelectionSuppressed = false;
    var _layoutMode = 'full', _densityController = null;
    var _el, _shellEl, _catBar, _grid, _cartList, _cartTotal, _balanceEl;
    var _checkoutBtn, _claimList, _loadingEl;
    var _scaleHandle = null;   // 沉浸全屏化：PanelScale 句柄

    var _kHandler = function(v) { _kpoints = Number(v); if (_balanceEl) _balanceEl.textContent = _kpoints; };

    // ── Helpers ──
    function isStackable(item) {
        return item.majorType === '消耗品' || item.majorType === '收集品';
    }
    function isLocked(item) {
        return Number(item.level) > _playerLevel + _reverseLevel;
    }
    function findCatalogItem(idx) {
        for (var i = 0; i < _catalog.length; i++) {
            if (_catalog[i].idx === idx) return _catalog[i];
        }
        return null;
    }
    function escHtml(s) {
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }
    function escAttr(s) {
        return escHtml(s).replace(/"/g, '&quot;').replace(/'/g, '&#39;');
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
        var payload = [];
        for (var i = 0; i < _cart.length; i++) payload.push({idx: _cart[i].idx, qty: _cart[i].qty});
        return payload;
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
        buildCategories();
        renderGrid();
        renderCart();
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
        if (_settlementView) _settlementView.render();
        var claimButtons = _el.querySelectorAll('.kshop-claim-btn');
        for (var j = 0; j < claimButtons.length; j++) claimButtons[j].disabled = claimBlocked;
        var ownedNodes = _el.querySelectorAll('.inventory-slot-card');
        for (var k = 0; k < ownedNodes.length; k++) ownedNodes[k].classList.toggle('write-locked', inventoryBlocked);
        if (_warehousePager) _warehousePager.setDisabled(inventoryBlocked);
        if (_backpackSortControls) _backpackSortControls.setDisabled(inventoryBlocked);
        if (_warehouseSortControls) {
            _warehouseSortControls.setDisabled(inventoryBlocked);
            var battleboxSnapshot = _inventoryCoordinator.getWindow('战备箱');
            _warehouseSortControls.setAuthorityDisabled(inventoryBlocked
                || !battleboxSnapshot || Number(battleboxSnapshot.accessibleCapacity) <= 0);
        }
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
        if (blockEdits) dismissQtyInput();
        if (state && state.reconcileBlocked) {
            showSaveFailedDialog('商城对账失败，写操作保持锁定', true);
        }
    }

    // 长按加速：按住按钮自动重复触发，间隔逐步缩短
    // 初始 400ms → 加速到最快 50ms（每次 ×0.85）
    // 返回 stop 函数，供外部在 DOM 重建前主动停止
    var _activeHoldTimers = []; // 所有活跃的 holdRepeat stop 句柄
    function holdRepeat(el, callback) {
        var timer = null, interval = 400;
        function fire() {
            callback();
            interval = Math.max(50, interval * 0.85);
            timer = setTimeout(fire, interval);
        }
        function start(e) {
            e.preventDefault();
            interval = 400;
            callback();
            timer = setTimeout(fire, interval);
            // 全局 mouseup 兜底：即使按钮被销毁也能停止
            document.addEventListener('mouseup', stop);
        }
        function stop() {
            if (timer) { clearTimeout(timer); timer = null; }
            interval = 400;
            document.removeEventListener('mouseup', stop);
        }
        el.addEventListener('mousedown', start);
        el.addEventListener('mouseup', stop);
        el.addEventListener('mouseleave', stop);
        el.addEventListener('click', function(e) { e.stopPropagation(); });
        _activeHoldTimers.push(stop);
    }
    // 在 DOM 重建前调用，强制停止所有活跃的长按 timer
    function killAllHoldTimers() {
        for (var i = 0; i < _activeHoldTimers.length; i++) _activeHoldTimers[i]();
        _activeHoldTimers = [];
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

        var modeSwitch = document.createElement('div');
        modeSwitch.className = 'workbench-mode-switch';
        _shopModeButton = document.createElement('button');
        _shopModeButton.type = 'button';
        _shopModeButton.className = 'workbench-mode-btn active';
        _shopModeButton.setAttribute('data-mode', 'shop');
        _shopModeButton.textContent = '商城';
        _shopModeButton.addEventListener('click', showShopMode);
        _inventoryModeButton = document.createElement('button');
        _inventoryModeButton.type = 'button';
        _inventoryModeButton.className = 'workbench-mode-btn';
        _inventoryModeButton.setAttribute('data-mode', 'inventory');
        _inventoryModeButton.textContent = '战备箱';
        _inventoryModeButton.addEventListener('click', showInventoryMode);
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

        _catalogView = createCatalogWorkbenchView();
        _orderView = createOrderWorkbenchView();
        _backpackView = createOwnedInventoryView({containerId:'背包', kicker:'', title:'背包', layoutMode:_layoutMode});
        _warehouseView = createOwnedInventoryView({containerId:'战备箱', kicker:'', title:'战备箱', layoutMode:_layoutMode});
        _backpackView.chrome.setToolbar(createInventoryToolbar('背包', null));
        _warehouseView.chrome.setToolbar(createInventoryToolbar('战备箱', createWarehousePager()));
        _ownedViews = [_backpackView, _warehouseView];

        _workbenchShell.registerView(_backpackView);
        _workbenchShell.registerView(_warehouseView);
        _workbenchShell.setDefault('L', _catalogView);
        _workbenchShell.setDefault('R', _orderView);
        if (!_workbenchShell.mountInitial(_catalogView, _orderView)) {
            throw new Error('KShop workbench initial view configuration rejected');
        }
        _settlementView = new KShopViews.SettlementPage({
            panelRoot: _el,
            getCart: function() { return _cart; },
            getBalance: function() { return _kpoints; },
            findCatalogItem: findCatalogItem,
            isStackable: isStackable,
            iconHtml: iconHtml,
            canEditCart: canEditCart,
            canCheckout: canStartShopWrite,
            adjustQuantity: adjustCartQuantity,
            setQuantity: setCartQuantity,
            onInspect: showItemDetail,
            onBack: closeSettlement,
            onCommit: checkout
        });
        _settlementView.mount(_el);
        installWorkbenchInteractions();

        // 沉浸全屏化 2026-06-11：把固定 1024×576 画布(.kshop-panel)包进共享 .panel-scale-shell，
        // 由 PanelScale 整体等比缩放，取代旧的 fluid 跟分辨率 reflow（kshop 是最早实现的 panel，配套最不全）。
        _shellEl = document.createElement('div');
        _shellEl.className = 'panel-scale-shell kshop-scale-shell';
        _shellEl.appendChild(_el);
        return _shellEl;
    }

    function createCatalogWorkbenchView() {
        var composition = KShopViews.createCatalog({
            renderItem: renderCatalogCard,
            bindItem: bindCatalogCard,
            render: renderGrid,
            exportOffer: function(item) {
                if (!item || isLocked(item) || item.type === '非卖品') return null;
                return {
                    subjectKind: 'catalogEntry',
                    sourceRef: { catalogIdx: item.idx },
                    offeredOperations: ['shop.addCartIntent']
                };
            }
        });
        _catalogChrome = composition.chrome;
        _catBar = composition.categoryBar;
        _catalogRenderer = composition.renderer;
        _grid = composition.grid;
        _loadingEl = composition.loading;
        _categoryNavigator = new ItemFilter.FilterNavigator({
            className:'kshop-category-navigator item-filter-navigator',
            ariaLabel:'商城商品分类',
            presentation:'drilldown',
            visualStyle:'catalog',
            onChange:function(path) {
                _categoryPath = path;
                if (_interactionBroker) _interactionBroker.clearSelection();
                if (_grid) _grid.scrollTop = 0;
                renderGrid();
                decorateKShopCategoryButtons();
            }
        });
        while (_catBar.firstChild) _catBar.removeChild(_catBar.firstChild);
        _catBar.appendChild(_categoryNavigator.root);
        if (_densityController) _densityController.register(_catalogRenderer);
        return composition.view;
    }

    function createOrderWorkbenchView() {
        var composition = KShopViews.createOrder({
            getItems: function() { return _cart; },
            getCart: function() { return _cart; },
            getPurchased: function() { return _purchased; },
            renderCartItem: renderCartRow,
            bindCartItem: bindCartRow,
            renderPurchasedItem: renderClaimRow,
            bindPurchasedItem: bindClaimRow,
            probeAccept: probeCartAccept,
            onCartSinkClick: onCartSinkClick,
            onCheckout: openSettlement,
            render: function() { renderCart(); renderClaimed(); },
        });
        _cartGridView = composition.cartGridView;
        _purchasedGridView = composition.purchasedGridView;
        _cartList = composition.cartList;
        _claimList = composition.claimList;
        _cartDropTarget = composition.dropTarget;
        _cartDropLabel = composition.dropLabel;
        _cartTotal = composition.cartTotal;
        _checkoutBtn = composition.checkoutButton;
        return composition.view;
    }

    function createWarehousePager() {
        _warehousePager = new InventoryUI.InventoryWindowPager({
            containerId: '战备箱',
            containerLabel: '战备箱',
            columns: 3,
            defaultLimit: 40,
            defaultCapacity: 0,
            getSnapshot: function() { return _inventoryCoordinator.getWindow('战备箱'); },
            getRequest: function() { return _inventoryCoordinator.getRequest('战备箱'); },
            shortcutEnabled: warehouseShortcutsEnabled,
            onBeforeChange: function() {
                if (_interactionBroker) _interactionBroker.clearSelection();
                hideTooltip();
            },
            onRequest: function(offset, limit, callback) {
                return _inventoryCoordinator.setWindow('战备箱', offset, limit, callback);
            },
            onResult: function(result) {
                renderOwnedInventories();
                if (!result.success) {
                    if (typeof console !== 'undefined' && console.warn) console.warn('[KShop inventory page]', result.error || 'inventory_refresh_failed');
                    toast('战备箱翻页失败，请重试。');
                }
            }
        });
        return _warehousePager;
    }

    function createInventoryToolbar(containerId, pager) {
        var toolbar = document.createElement('div');
        toolbar.className = 'inventory-warehouse-toolbar inventory-container-toolbar'
            + (pager ? '' : ' inventory-no-pager');
        var view = containerId === '背包' ? _backpackView : _warehouseView;
        var controls = new InventoryUI.InventorySortControls({
            filterOptions: InventoryUI.categoryFilterOptions(),
            filterLabel: '',
            filterAriaLabel: containerId + '分类筛选',
            authorityAriaLabel: containerId + '整理方式',
            authorityLabel: '',
            commitLabel: '整理' + containerId,
            authorityOptions: InventoryUI.authoritySortOptions(),
            onFilterChange: function(filterKey) {
                if (_interactionBroker) _interactionBroker.clearSelection();
                hideTooltip();
                if (!_inventoryCoordinator.setFilter(containerId, filterKey, function(result) {
                    renderOwnedInventories();
                    if (!result.success) {
                        var request = _inventoryCoordinator.getRequest(containerId);
                        controls.setFilterKey(request ? request.filterKey : 'all');
                        toast(containerId + '筛选失败，请重试。');
                    }
                })) {
                    var request = _inventoryCoordinator.getRequest(containerId);
                    controls.setFilterKey(request ? request.filterKey : 'all');
                }
            },
            onFilterSpecChange: function(filterSpec) {
                if (_interactionBroker) _interactionBroker.clearSelection();
                hideTooltip();
                if (!_inventoryCoordinator.setFilterSpec(containerId, filterSpec, function(result) {
                    renderOwnedInventories();
                    if (!result.success) {
                        controls.rejectFilterChange(_inventoryCoordinator.getWindow(containerId));
                        toast(containerId + '筛选失败，请重试。');
                    }
                })) controls.rejectFilterChange(_inventoryCoordinator.getWindow(containerId));
            },
            onAuthorityCommit: function(methodName, label) {
                showInventorySortConfirm(containerId, methodName, label);
            }
        });
        if (containerId === '背包') _backpackSortControls = controls;
        else _warehouseSortControls = controls;
        if (pager) toolbar.appendChild(pager.root);
        toolbar.appendChild(controls.root);
        if (view.ownedInventoryShell) view.ownedInventoryShell.setToolbar(toolbar, controls, pager);
        return toolbar;
    }

    function createOwnedInventoryView(options) {
        options = options || {};
        var containerId = options.containerId;
        var ownedShell = new InventoryUI.OwnedInventoryViewShell({
            containerId: containerId,
            instanceKey: 'inventory:' + containerId,
            itemModel: 'owned',
            getItems: function() {
                var windowSnapshot = _inventoryCoordinator.getWindow(containerId);
                return windowSnapshot ? windowSnapshot.slots : [];
            },
            keyOf: function(slot) { return slot.physicalSlot; },
            renderItem: function(slot) { return renderOwnedSlot(containerId, slot); },
            bindItem: function(node, slot) { bindOwnedSlot(containerId, node, slot); },
            exportOffer: function(slot) {
                if (!slot || !slot.occupied || _inventoryState.busyOwner || _inventoryState.refreshRequired) return null;
                return {
                    subjectKind: 'ownedSlot',
                    sourceRef: ownedSlotRef(containerId, slot),
                    offeredOperations: ['inventory.transfer']
                };
            },
            probeAccept: function(offer, hit) {
                var targetSlot = hit && hit.item;
                if (!offer || offer.subjectKind !== 'ownedSlot' || !targetSlot) {
                    return {accepted: false, reason: 'unsupported'};
                }
                var targetRef = ownedSlotRef(containerId, targetSlot);
                if (InventoryRuntime.samePhysicalSlot(offer.sourceRef, targetRef)) {
                    return {accepted: false, reason: 'same_slot'};
                }
                return {
                    accepted: true,
                    operationId: 'inventory.transfer',
                    targetRef: targetRef,
                    hint: targetSlot.occupied ? 'merge-or-swap' : 'move'
                };
            },
            title: options.title,
            kicker: options.kicker,
            meta: '同步中',
            className: 'inventory-owned-view inventory-owned-' + (containerId === '背包' ? 'backpack' : 'warehouse'),
            gridClassName: 'inventory-owned-grid',
            emptyText: '正在同步库存…',
            allowedSlots: ['L', 'R'],
            layoutMode: options.layoutMode || 'full',
            densityController: _densityController
        });
        return ownedShell.view;
    }

    function ownedSlotRef(containerId, slot) {
        return {
            containerId: containerId,
            slot: Number(slot.physicalSlot),
            expectedLease: String(slot.slotLease),
            occupied: !!slot.occupied,
            item: slot.item || null
        };
    }

    function renderOwnedSlot(containerId, slot) {
        return InventoryUI.renderOwnedSlot(containerId, slot, {
            iconHtml: iconHtml,
            allowDiscard: containerId === '背包'
        });
    }

    function bindOwnedSlot(containerId, node, slot) {
        if (slot.occupied) bindOwnedTooltip(node, containerId, slot);
        node.addEventListener('click', function(event) {
            if (consumedOwnedClick()) return;
            if (event.target && event.target.closest && event.target.closest('.inventory-discard-btn')) return;
            var selected = _interactionBroker.debugState().selectedInstanceKey;
            if (selected && selected !== 'shop:catalog') {
                _interactionBroker.activateSelected(containerId === '背包' ? _backpackView : _warehouseView,
                    {item: slot, node: node}, 'click');
            } else if (slot.occupied) {
                _interactionBroker.select(containerId === '背包' ? _backpackView : _warehouseView, slot, node);
            }
        });
        var discardButton = node.querySelector('.inventory-discard-btn');
        if (discardButton) discardButton.addEventListener('click', function(event) {
            event.stopPropagation();
            showDiscardConfirm(containerId, slot);
        });
    }

    function renderOwnedInventories() {
        var views = [_backpackView, _warehouseView];
        for (var i = 0; i < views.length; i++) {
            var view = views[i];
            if (!view) continue;
            var snapshot = _inventoryCoordinator.getWindow(view.containerId);
            var filtered = snapshot && String(snapshot.filterKey || 'all') !== 'all';
            var emptyText = view.containerId === '战备箱'
                && snapshot && Number(snapshot.accessibleCapacity) <= 0
                ? '战备箱尚未解锁' : filtered ? '当前分类暂无物品' : '本页暂无物品';
            var meta = '同步中';
            if (snapshot && view.containerId === '战备箱' && Number(snapshot.accessibleCapacity) <= 0) meta = '未解锁';
            else if (snapshot && view.containerId === '背包') {
                var occupied = 0;
                for (var s = 0; s < snapshot.slots.length; s++) if (snapshot.slots[s].occupied) occupied++;
                meta = occupied + ' / ' + snapshot.capacity;
            } else if (snapshot) meta = '';
            if (view.ownedInventoryShell) {
                view.ownedInventoryShell.syncSnapshot(snapshot, {
                    emptyText:emptyText, meta:meta
                });
            }
        }
        refreshInventoryToolbar();
    }

    function warehouseShortcutsEnabled(event) {
        if (!isKShopOpen() || !_inventoryModeButton || !_inventoryModeButton.classList.contains('active')) return false;
        if (_workbenchShell && _workbenchShell.hasModal()) return false;
        var target = event.target;
        if (target && target.closest && target.closest('input,textarea,select,[contenteditable="true"],[data-browser-native]')) return false;
        return true;
    }

    function refreshInventoryToolbar() {
        if (_warehousePager) _warehousePager.refresh();
    }

    function showInventorySortConfirm(containerId, methodName, label) {
        if (!_inventoryState.ready || _inventoryState.busyOwner || _inventoryState.refreshRequired) return;
        methodName = methodName || 'byType';
        label = label || methodName;
        var isBattlebox = containerId === '战备箱';
        _workbenchShell.openModal({
            kind: 'warehouse-sort',
            kicker: '',
            title: '按' + label + '整理' + containerId + '？',
            message: '将重新排列' + (isBattlebox ? '当前已解锁区域' : containerId + '全部物品') + '，并合并可堆叠物品。',
            detail: isBattlebox
                ? '未解锁的存档保留区不会被读取或移动。'
                : '原有摆放顺序会改变，完成后仍停留在当前页。',
            actions: [
                {id: 'cancel', label: '取消', audioCue: 'cancel'},
                {id: 'sort', label: '整理并合并', primary: true, audioCue: 'confirm', onSelect: function() {
                    if (_interactionBroker) _interactionBroker.clearSelection();
                    if (!_inventoryCoordinator.sortAndMerge(containerId, methodName, function(result) {
                        renderOwnedInventories();
                        if (result.success) toast(containerId + '整理完成。');
                        else {
                            if (typeof console !== 'undefined' && console.warn) console.warn('[KShop inventory sort ' + containerId + ']', result.error || 'unknown');
                            toast(containerId + '整理失败，请重试。');
                        }
                    })) toast('库存正在处理另一笔写入。');
                }}
            ]
        });
    }

    function showShopMode() {
        if (!_workbenchShell) return;
        _el.setAttribute('data-workbench-skin', 'shop');
        if (_warehousePager) _warehousePager.setMenuOpen(false, false);
        _workbenchShell.moveView('L', _catalogView);
        _workbenchShell.moveView('R', _orderView);
        _shopModeButton.classList.add('active');
        _inventoryModeButton.classList.remove('active');
        _workbenchShell.setSlotLabel('L', '商品');
        _workbenchShell.setSlotLabel('R', '购物车');
        _workbenchShell.setTitle('K点商城', '');
    }

    function showInventoryMode() {
        if (!_workbenchShell) return;
        closeSettlement();
        _el.setAttribute('data-workbench-skin', 'inventory');
        _workbenchShell.moveView('L', _backpackView);
        _workbenchShell.moveView('R', _warehouseView);
        _shopModeButton.classList.remove('active');
        _inventoryModeButton.classList.add('active');
        _workbenchShell.setSlotLabel('L', '背包');
        _workbenchShell.setSlotLabel('R', '战备箱');
        _workbenchShell.setTitle('物品管理', '');
        renderOwnedInventories();
    }

    function showDiscardConfirm(containerId, slot) {
        if (containerId !== '背包' || !slot.occupied || !_inventoryState.ready) return;
        var projection = slot.confirmProjection || slot.item || {};
        _workbenchShell.openModal({
            kind: 'discard',
            kicker: '',
            title: '丢弃 ' + String(projection.displayName || '该物品') + '？',
            message: '将丢弃整组，共 ' + Number(projection.quantity || 1) + ' 件。',
            detail: '丢弃后无法找回。',
            actions: [
                {id: 'cancel', label: '取消', audioCue: 'cancel'},
                {id: 'discard', label: '确认丢弃', danger: true, audioCue: 'error', onSelect: function() {
                    if (!_inventoryCoordinator.discard(ownedSlotRef(containerId, slot), function(result) {
                        renderOwnedInventories();
                        if (result.success) toast('物品已丢弃。');
                        else {
                            if (typeof console !== 'undefined' && console.warn) console.warn('[KShop inventory discard]', result.error || 'unknown');
                            toast('丢弃失败，请重试。');
                        }
                    })) toast('库存正在处理另一笔写入。');
                }}
            ]
        });
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
                _ownedTooltipSelectionSuppressed = !!(selection
                    && (selection.view === _backpackView || selection.view === _warehouseView));
                if (_ownedTooltipSelectionSuppressed) hideTooltip();
                if (_catalogRenderer) _catalogRenderer.setSelectedKey(_selectedCatalogIdx);
                if (_cartDropTarget) {
                    _cartDropTarget.classList.toggle('has-selection', _selectedCatalogIdx != null);
                    var item = _selectedCatalogIdx != null ? findCatalogItem(_selectedCatalogIdx) : null;
                    _cartDropLabel.textContent = item ? (item.displayname + ' · 点击添加') : '选择或拖入';
                }
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
        _ownedDragControllers = [];
        for (var i = 0; i < _ownedViews.length; i++) {
            (function(view) {
                _ownedDragControllers.push(new Workbench.PointerDragController({
                    sourceElement: view.renderer.root,
                    broker: _interactionBroker,
                    timeoutMs: _runtimeConfig.dragTimeoutMs || 1400,
                    getSource: function(target) {
                        if (!_inventoryState.ready || _inventoryState.busyOwner || _inventoryState.refreshRequired) return null;
                        var hit = view.renderer.itemFromTarget(target);
                        if (!hit || !hit.item || !hit.item.occupied) return null;
                        return {view: view, item: hit.item, node: hit.node};
                    },
                    resolveTarget: resolveOwnedDropTarget,
                    renderGhost: function(source) {
                        var item = source.item.item || {};
                        var ghost = document.createElement('div');
                        ghost.className = 'workbench-drag-ghost inventory-drag-ghost';
                        ghost.innerHTML = iconHtml(item.icon || item.name, 'kshop-row-icon')
                            + '<span>' + escHtml(item.displayName || item.name || 'owned item') + '</span>';
                        return ghost;
                    },
                    onDragStart: function() { _dragTooltipSuppressed = true; hideTooltip(); },
                    onDragEnd: function() { _dragTooltipSuppressed = false; }
                }));
            })(_ownedViews[i]);
        }
    }

    function resolveOwnedDropTarget(clientX, clientY) {
        var target = document.elementFromPoint(clientX, clientY);
        for (var i = 0; i < _ownedViews.length; i++) {
            var view = _ownedViews[i];
            if (!view.root.contains(target)) continue;
            var hit = view.renderer.itemFromTarget(target);
            if (!hit) return null;
            return {view: view, hit: {item: hit.item, node: hit.node}, node: hit.node};
        }
        return null;
    }

    function consumedOwnedClick() {
        for (var i = 0; i < _ownedDragControllers.length; i++) {
            if (_ownedDragControllers[i].consumeClick()) return true;
        }
        return false;
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
        _checkoutPreview = null;
        _previewBusy = false;
        _previewQueued = false;
        _previewRevision++;
        _categoryPath = [];
        _tooltipCache = {};
        _ownedTooltipCache = {};
        _ownedTooltipSelectionSuppressed = false;
        if (_warehousePager) {
            _warehousePager.detach();
            _warehousePager.attach();
        }
        dismissDialog();
        closeSettlement();
        if (_interactionBroker) _interactionBroker.clearSelection();
        buildCategories();
        renderCart();
        renderClaimed();
        _mux.openSession();
        _writeCoordinator.open();
        showShopMode();
        // 页码继续按会话记忆；分类筛选不跨打开/存档保留，避免新存档初始视图被旧筛选隐藏。
        var backpackRequest = _inventoryCoordinator.getRequest('背包');
        var warehouseRequest = _inventoryCoordinator.getRequest('战备箱');
        _inventoryCoordinator.resetWindow('背包', backpackRequest ? backpackRequest.offset : 0, 50, 'all');
        _inventoryCoordinator.resetWindow('战备箱', warehouseRequest ? warehouseRequest.offset : 0, 40, 'all');
        if (_backpackSortControls) _backpackSortControls.setFilterKey('all');
        if (_warehouseSortControls) _warehouseSortControls.setFilterKey('all');
        _inventoryCoordinator.open(function(result) {
            if (!isKShopOpen()) return;
            renderOwnedInventories();
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

    // ── Bridge response listener ──
    Bridge.on('panel_resp', function(data) {
        _mux.handleResponse(data);
    });

    // ══════════════════════════════════════════
    //  Categories
    // ══════════════════════════════════════════
    function buildCategories() {
        if (_interactionBroker) _interactionBroker.clearSelection();
        var automaticTree = ItemFilter.build(_catalog, function(item) {
            return ItemFilter.catalogPath(item);
        });
        var curatedTree = ItemFilter.build(_catalog, function(item) {
            var group = String(item && item.type || '未分组');
            return [{id:group, label:group}];
        });
        var setTree = ItemFilter.buildSetTree(_catalog);
        var branches = [{id:'category', label:'类别', tree:automaticTree}];
        if (setTree.children.length) branches.push({id:'set', label:'套装', tree:setTree});
        branches.push({id:'curated', label:'专柜', tree:curatedTree});
        _categoryTree = ItemFilter.branchTree(branches, _catalog.length);
        _categoryPath = ItemFilter.validPath(_categoryTree, _categoryPath);
        if (_categoryNavigator) _categoryNavigator.setModel(_categoryTree, _categoryPath);
        decorateKShopCategoryButtons();
    }

    function decorateKShopCategoryButtons() {
        if (!_categoryNavigator) return;
        var buttons = _categoryNavigator.root.querySelectorAll('[data-filter-path]');
        for (var i = 0; i < buttons.length; i++) {
            var label = buttons[i].querySelector('span');
            buttons[i].setAttribute('data-cat', label ? label.textContent.replace(/^全部/, '') || '全部' : '全部');
            buttons[i].setAttribute('data-audio-cue', 'select');
        }
    }

    // ══════════════════════════════════════════
    //  Grid — 等级锁定 + 购买分流
    // ══════════════════════════════════════════
    function renderGrid() {
        if (!_catalogRenderer) return;
        var visible = [];
        for (var i = 0; i < _catalog.length; i++) {
            var item = _catalog[i];
            if (!matchesKShopCategory(item, _categoryPath)) continue;
            visible.push(item);
        }
        _catalogRenderer.render(visible);
        _catalogRenderer.setSelectedKey(_selectedCatalogIdx);
        if (_catalogChrome) _catalogChrome.setMeta((visible.length || 0) + ' 件');
        if (!_iconsLoaded) {
            Icons.load(function() { _iconsLoaded = true; renderGrid(); renderCart(); renderClaimed(); });
        }
        refreshWriteControls(_writeState || _writeCoordinator.debugState());
    }

    function matchesKShopCategory(item, path) {
        path = path || [];
        if (!path.length || path.length === 1) return true;
        if (path[0] === 'category') {
            return ItemFilter.matchesPath(item, path.slice(1), function(entry) { return ItemFilter.catalogPath(entry); });
        }
        if (path[0] === 'set') return ItemFilter.matchesPath(item, path.slice(1), ItemFilter.setPath);
        if (path[0] === 'curated') return String(item && item.type || '未分组') === String(path[1]);
        return false;
    }

    function renderCatalogCard(item) {
        var locked = isLocked(item);
        var nosale = item.type === '非卖品';
        var stackable = isStackable(item);
        var actionHtml = '';
        if (!nosale && !locked) {
            actionHtml = '<button class="kshop-add-btn' + (stackable ? '' : ' kshop-add-single') + '" data-idx="' + item.idx + '" data-audio-cue="select" title="加入购物车">' + (stackable ? '+' : '加入') + '</button>';
        }
        return Workbench.ItemCard.renderCatalog({
            skin: 'kshop',
            item: item,
            id: item.idx,
            iconHtml: iconHtml(item.icon),
            name: item.displayname,
            meta: item.subType || item.majorType || item.type,
            price: item.price,
            priceLabel: 'K',
            locked: locked,
            lockReason: 'Lv.' + item.level + ' 解锁',
            nosale: nosale,
            ariaLabel: item.displayname + '，K ' + item.price,
            extraHtml: actionHtml
        });
    }

    function bindCatalogCard(card) {
        var idx = Number(card.getAttribute('data-idx'));
        var item = findCatalogItem(idx);
        if (item) bindCatalogTooltip(card, item);
        card.addEventListener('click', onCatalogCardClick);
        card.addEventListener('dblclick', onCatalogCardDoubleClick);
        card.addEventListener('keydown', function(event) {
            if (event.key === 'Enter' || event.key === ' ') {
                event.preventDefault();
                selectCatalogCard(card);
            }
        });
        var addBtn = card.querySelector('.kshop-add-btn');
        if (addBtn) addBtn.addEventListener('click', onAddToCart);
    }

    function selectCatalogCard(card) {
        var idx = Number(card.getAttribute('data-idx'));
        var item = findCatalogItem(idx);
        if (!item || isLocked(item) || item.type === '非卖品') return false;
        _interactionBroker.select(_catalogView, item, card);
        playCue('select');
        return true;
    }

    function onCatalogCardClick(event) {
        if (event.target.closest && event.target.closest('button')) return;
        if (_dragController && _dragController.consumeClick()) return;
        selectCatalogCard(event.currentTarget);
    }

    function onCatalogCardDoubleClick(event) {
        if (!canEditCart()) return;
        var idx = Number(event.currentTarget.getAttribute('data-idx'));
        var item = findCatalogItem(idx);
        if (!item) return;
        _interactionBroker.dispatch(_catalogView, item, _orderView, { binding: 'shop:cart' }, 'double_click');
    }

    function probeCartAccept(offer) {
        if (!canEditCart()) return { accepted: false, reason: 'write_locked' };
        if (!offer || offer.subjectKind !== 'catalogEntry') return { accepted: false, reason: 'unsupported_subject' };
        var operations = offer.offeredOperations || [];
        var accepts = false;
        for (var i = 0; i < operations.length; i++) if (operations[i] === 'shop.addCartIntent') accepts = true;
        if (!accepts) return { accepted: false, reason: 'unsupported_operation' };
        return {
            accepted: true,
            operationId: 'shop.addCartIntent',
            targetRef: { binding: 'shop:cart' },
            hint: 'append'
        };
    }

    function onCartSinkClick() {
        if (!canEditCart()) {
            toast('商城正在处理写入，请稍后再加购。');
            return;
        }
        var result = _interactionBroker.activateSelected(_orderView, { binding: 'shop:cart' }, 'click');
        if (!result.accepted && result.reason === 'nothing_selected') toast('请先从左栏选择商品。');
    }

    function handleWorkbenchIntent(intent) {
        if (!intent || !intent.sourceRef) return;
        if (intent.operationId === 'shop.addCartIntent') {
            addCatalogIntent(Number(intent.sourceRef.catalogIdx), 1);
            return;
        }
        if (intent.operationId === 'inventory.transfer') {
            if (!_inventoryCoordinator.transfer(intent, function(result) {
                renderOwnedInventories();
                if (result.success) {
                    var operationLabel = result.operation === 'merge' ? '物品已合并。'
                        : result.operation === 'swap' ? '物品已交换。' : '物品已移动。';
                    toast(operationLabel);
                    playCue('success');
                } else {
                    if (typeof console !== 'undefined' && console.warn) console.warn('[KShop inventory transfer]', result.error || 'unknown');
                    toast(result.reconciled ? '移动失败，库存已刷新。' : '移动失败，请重试。');
                    playCue('error');
                }
            })) toast('库存正在处理另一笔写入。');
        }
    }

    function addCatalogIntent(idx, qty) {
        if (!canEditCart()) return false;
        var item = findCatalogItem(idx);
        if (!item || isLocked(item) || item.type === '非卖品') return false;
        if (!isStackable(item)) {
            for (var i = 0; i < _cart.length; i++) {
                if (_cart[i].idx === idx) {
                    toast('该装备已在购物车中');
                    playCue('error');
                    return false;
                }
            }
        }
        addToCartDirect(idx, Math.max(1, Number(qty) || 1));
        playCue('confirm');
        return true;
    }

    // ══════════════════════════════════════════
    //  Tooltip — Flash bridge + 缓存
    //  hover 即时显示基础信息，异步拉取 Flash TooltipComposer 的富文本
    // ══════════════════════════════════════════
    var _tooltipCache = {};  // idx → {descHTML, introHTML}
    var _ownedTooltipCache = {}; // container:slot:lease → 富文本；lease 变化即自然失效

    function bindCatalogTooltip(card, item) {
        PanelTooltip.bindAsyncHover(card, {
            cache: _tooltipCache,
            key: item.idx,
            item: item,
            isSuppressed: function() { return _dragTooltipSuppressed; },
            renderBasic: buildBasicHtml,
            renderRich: buildRichHtml,
            fetch: function(item, callback) {
                requestShop('tooltip', { idx: item.idx }, function(resp) {
                    if (!isKShopOpen()) return;
                    callback(resp);
                });
            }
        });
    }

    function bindOwnedTooltip(node, containerId, slot) {
        var key = ownedTooltipKey(containerId, slot);
        var item = slot.item || {};
        PanelTooltip.bindAsyncHover(node, {
            cache: _ownedTooltipCache,
            key: key,
            item: item,
            isSuppressed: function() { return _dragTooltipSuppressed || _ownedTooltipSelectionSuppressed; },
            renderBasic: buildOwnedBasicHtml,
            renderRich: buildOwnedRichHtml,
            fetch: function(_, callback) {
                requestInventory('tooltip', {v: 1, source: ownedSlotRef(containerId, slot)}, function(resp) {
                    if (!isKShopOpen()) return;
                    callback(resp);
                });
            }
        });
    }

    function buildBasicHtml(item) {
        var locked = isLocked(item);
        return '<div class="kshop-tt-header"><b>' + escHtml(item.displayname) + '</b></div>' +
            '<div class="kshop-tt-divider"></div>' +
            '<span class="kshop-tt-dim">类型</span> ' + escHtml(item.majorType) + ' / ' + escHtml(item.subType) + '<br>' +
            '<span class="kshop-tt-dim">等级</span> ' + item.level +
            (locked ? ' <span class="kshop-tt-locked">⚿ 锁定</span>' : '') + '<br>' +
            '<span class="kshop-tt-price">K ' + item.price + '</span>' +
            '<div class="kshop-tt-loading">加载中…</div>';
    }

    function buildRichHtml(item, data) {
        var locked = isLocked(item);
        var lockBanner = locked
            ? '<div class="flash-tt-lock-banner kshop-tt-lock-banner">⚿ 锁定 — 需要 Lv.' + item.level + '</div>'
            : '';
        var iconKey = item.icon;

        // layoutType: 对齐 AS2 TooltipLayout.applyIntroLayout 分支。
        // K 商城 item.majorType 来自 AS2 端的 item.type 字段，可直接喂给 inferLayoutType。
        // 武器/护甲/技能/药剂 → wide(200px)，消耗品/材料/收集品等 → narrow(120px)。
        var layoutType = PanelTooltip.inferLayoutType(item.majorType);

        return PanelTooltip.buildItemRichHtml({
            iconHtml:   PanelTooltip.dynamicIconHtml(iconKey),
            iconUrl:    PanelTooltip.staticIconUrl(iconKey),
            introHTML:  data.introHTML,
            descHTML:   data.descHTML,
            rootClass:  'kshop-tt-rich-context',
            suffix:     lockBanner,
            layoutType: layoutType
        });
    }

    function ownedTooltipKey(containerId, slot) {
        return String(containerId) + ':' + Number(slot.physicalSlot) + ':' + String(slot.slotLease || '');
    }

    function buildOwnedBasicHtml(item) {
        var typeLabel = item.majorType || item.use || item.itemKind || '物品';
        return '<div class="kshop-tt-header"><b>' + escHtml(item.displayName || item.name || '未知物品') + '</b></div>'
            + '<div class="kshop-tt-divider"></div>'
            + '<span class="kshop-tt-dim">类型</span> ' + escHtml(typeLabel) + '<br>'
            + (Number(item.quantity) > 1 ? '<span class="kshop-tt-dim">数量</span> ' + Number(item.quantity) + '<br>' : '')
            + (Number(item.enhancementLevel) > 0 ? '<span class="kshop-tt-dim">强化</span> +' + Number(item.enhancementLevel) + '<br>' : '')
            + '<div class="kshop-tt-loading">加载中…</div>';
    }

    function buildOwnedRichHtml(item, data) {
        var iconKey = data.iconName || item.icon || item.name;
        return PanelTooltip.buildItemRichHtml({
            iconHtml: PanelTooltip.dynamicIconHtml(iconKey),
            iconUrl: PanelTooltip.staticIconUrl(iconKey),
            introHTML: data.introHTML || '',
            descHTML: data.descHTML || '',
            rootClass: 'kshop-tt-rich-context inventory-owned-tt-context',
            layoutType: PanelTooltip.inferLayoutType(data.itemType || item.majorType || item.use)
        });
    }

    function requestFlashTooltip(idx) {
        requestShop('tooltip', { idx: idx }, function(resp) {
            if (!isKShopOpen()) return;
            if (resp.success) {
                _tooltipCache[idx] = { descHTML: resp.descHTML || '', introHTML: resp.introHTML || '' };
            }
        });
    }

    // ══════════════════════════════════════════
    //  Cart — 购买分流：装备qty固定1，消耗品/收集品可叠加
    // ══════════════════════════════════════════
    function onAddToCart(e) {
        e.stopPropagation();
        if (!canEditCart()) {
            toast('商城正在处理写入，请稍后再编辑购物车。');
            return;
        }
        var idx = Number(e.target.getAttribute('data-idx'));
        var item = findCatalogItem(idx);
        if (!item) return;

        if (isLocked(item)) {
            toast('等级不足，无法购买！');
            playCue('error');
            return;
        }

        var stackable = isStackable(item);

        if (!stackable) {
            // 装备：直接加1，重复提示
            for (var i = 0; i < _cart.length; i++) {
                if (_cart[i].idx === idx) {
                    toast('该装备已在购物车中');
                    playCue('error');
                    return;
                }
            }
            _cart.push({idx: idx, qty: 1});
            renderCart();
            markCartDirty();
        } else {
            // 消耗品/收集品：弹出数量输入
            showQtyInput(e.target, idx);
        }
    }

    // 消耗品批量数量输入弹窗
    var _qtyPopup = null;
    function showQtyInput(anchor, idx) {
        if (!canEditCart()) return;
        dismissQtyInput();
        var item = findCatalogItem(idx);
        if (!item) return;

        _qtyPopup = document.createElement('div');
        _qtyPopup.className = 'kshop-qty-popup';
        _qtyPopup.innerHTML =
            '<div class="kshop-qty-popup-title">' + escHtml(item.displayname) + '</div>' +
            '<div class="kshop-qty-popup-row">' +
                '<button class="kshop-qty-pop-btn" data-v="-10" data-audio-cue="click">−−</button>' +
                '<button class="kshop-qty-pop-btn" data-v="-1" data-audio-cue="click">−</button>' +
                '<input class="kshop-qty-input" type="number" value="1" min="1" max="999">' +
                '<button class="kshop-qty-pop-btn" data-v="1" data-audio-cue="click">+</button>' +
                '<button class="kshop-qty-pop-btn" data-v="10" data-audio-cue="click">++</button>' +
            '</div>' +
            '<div class="kshop-qty-popup-foot">' +
                '<span class="kshop-qty-subtotal">K ' + item.price + '</span>' +
                '<button class="kshop-qty-confirm" data-audio-cue="confirm">加购</button>' +
            '</div>';

        // 定位到按钮附近（anchor.getBoundingClientRect 已是缩放后的真实屏幕 px，定位无需再换算）
        var rect = anchor.getBoundingClientRect();
        _qtyPopup.style.left = (rect.right + 4) + 'px';
        _qtyPopup.style.top = rect.top + 'px';
        // 沉浸全屏化 2026-06-12：商城主体在 .panel-scale-shell 内整体缩放，本弹窗挂 document.body（在 shell 外，
        // 故不继承 transform），需手动套同一 --panel-scale 才能与缩放后的主体字号/控件比例一致；
        // transform-origin:top left 配合上面以真实 px 锚定的 left/top，向右下按比例展开、锚点不偏。
        var _qScale = parseFloat(_shellEl && _shellEl.style.getPropertyValue('--panel-scale')) || 1;
        if (_qScale && _qScale !== 1) {
            _qtyPopup.style.transformOrigin = 'top left';
            _qtyPopup.style.transform = 'scale(' + _qScale + ')';
        }
        document.body.appendChild(_qtyPopup);
        playCue('modalOpen');

        var input = _qtyPopup.querySelector('.kshop-qty-input');
        var subtotalEl = _qtyPopup.querySelector('.kshop-qty-subtotal');
        var price = Number(item.price);

        function updateSubtotal() {
            var v = Math.max(1, Math.floor(Number(input.value) || 1));
            input.value = v;
            subtotalEl.textContent = 'K ' + (v * price);
        }

        // +/- 按钮：长按加速
        var btns = _qtyPopup.querySelectorAll('.kshop-qty-pop-btn');
        for (var b = 0; b < btns.length; b++) {
            (function(btn) {
                var delta = Number(btn.getAttribute('data-v'));
                holdRepeat(btn, function() {
                    input.value = Math.max(1, (Number(input.value) || 1) + delta);
                    updateSubtotal();
                });
            })(btns[b]);
        }
        input.addEventListener('input', updateSubtotal);
        input.addEventListener('keydown', function(ev) {
            if (ev.key === 'Enter') confirmAdd();
        });

        // 确认按钮
        _qtyPopup.querySelector('.kshop-qty-confirm').addEventListener('click', confirmAdd);

        function confirmAdd() {
            if (!canEditCart()) return;
            var qty = Math.max(1, Math.floor(Number(input.value) || 1));
            addToCartDirect(idx, qty);
            dismissQtyInput();
        }

        // 点外部关闭
        setTimeout(function() {
            document.addEventListener('click', onQtyOutsideClick);
        }, 0);
        input.focus();
        input.select();
    }

    function onQtyOutsideClick(e) {
        if (_qtyPopup && !_qtyPopup.contains(e.target)) {
            dismissQtyInput();
        }
    }

    function dismissQtyInput() {
        killAllHoldTimers();
        document.removeEventListener('click', onQtyOutsideClick);
        if (_qtyPopup && _qtyPopup.parentNode) {
            _qtyPopup.parentNode.removeChild(_qtyPopup);
        }
        _qtyPopup = null;
    }

    function addToCartDirect(idx, qty) {
        if (!canEditCart()) return;
        for (var i = 0; i < _cart.length; i++) {
            if (_cart[i].idx === idx) {
                _cart[i].qty += qty;
                renderCart();
                markCartDirty();
                return;
            }
        }
        _cart.push({idx: idx, qty: qty});
        renderCart();
        markCartDirty();
    }

    function adjustCartQuantity(idx, delta, removeAll) {
        if (!canEditCart()) return;
        for (var i = 0; i < _cart.length; i++) {
            if (_cart[i].idx !== idx) continue;
            if (removeAll) _cart.splice(i, 1);
            else {
                _cart[i].qty += Number(delta) || 0;
                if (_cart[i].qty <= 0) _cart.splice(i, 1);
            }
            renderCart();
            markCartDirty();
            if (_settlementView && _settlementView.isActive()) requestCheckoutPreview();
            return;
        }
    }

    function setCartQuantity(idx, quantity) {
        if (!canEditCart()) return;
        var target = Math.max(1, Math.floor(Number(quantity) || 1));
        for (var i = 0; i < _cart.length; i++) {
            if (_cart[i].idx !== idx) continue;
            _cart[i].qty = target;
            renderCart();
            markCartDirty();
            if (_settlementView && _settlementView.isActive()) requestCheckoutPreview();
            return;
        }
    }

    function renderCart() {
        killAllHoldTimers();
        var total = 0;
        for (var i = 0; i < _cart.length; i++) {
            var c = _cart[i];
            var item = findCatalogItem(c.idx);
            if (!item) continue;
            total += Number(item.price) * c.qty;
        }
        if (_cartGridView) {
            _cartGridView.renderer.render(_cart);
            _cartGridView.chrome.setMeta(_cart.length + ' 种 / ' + cartQuantity() + ' 件');
        }
        if (_cartDropTarget) _cartDropTarget.classList.toggle('has-items', _cart.length > 0);
        _cartTotal.textContent = total;
        if (_settlementView) _settlementView.render();
        refreshWriteControls(_writeState || _writeCoordinator.debugState());
    }

    function cartQuantity() {
        var quantity = 0;
        for (var i = 0; i < _cart.length; i++) quantity += Number(_cart[i].qty) || 0;
        return quantity;
    }

    function renderCartRow(cartItem) {
        var item = findCatalogItem(cartItem.idx);
        var row = document.createElement('article');
        row.className = 'kshop-cart-row';
        row.setAttribute('data-idx', cartItem.idx);
        if (!item) {
            row.classList.add('kshop-cart-row-invalid');
            row.textContent = '目录已变化 · 商品 #' + cartItem.idx;
            return row;
        }
        var subtotal = Number(item.price) * cartItem.qty;
        var stackable = isStackable(item);
        var qtyHtml = stackable
            ? '<span class="kshop-cart-qty"><button class="kshop-qty-btn" data-idx="' + cartItem.idx + '" data-delta="-1" data-audio-cue="click">−</button><b>' + cartItem.qty + '</b><button class="kshop-qty-btn" data-idx="' + cartItem.idx + '" data-delta="1" data-audio-cue="click">＋</button></span>'
            : '<span class="kshop-cart-qty"><b>1</b></span><button class="kshop-qty-btn kshop-remove-btn" data-idx="' + cartItem.idx + '" data-delta="-1" data-audio-cue="cancel" title="移除">×</button>';
        row.innerHTML =
            '<span class="kshop-cart-thumb">' + iconHtml(item.icon, 'kshop-row-icon') + '</span>' +
            '<span class="kshop-cart-copy"><b class="kshop-cart-name">' + escHtml(item.displayname) + '</b><small>K ' + item.price + ' / 件</small></span>' +
            qtyHtml +
            '<span class="kshop-cart-sub">' + subtotal + '</span>';
        return row;
    }

    function bindCartRow(row) {
        row.addEventListener('click', onCartRowClick);
        var btns = row.querySelectorAll('.kshop-qty-btn');
        for (var b = 0; b < btns.length; b++) {
            (function(btn) {
                var cidx = Number(btn.getAttribute('data-idx'));
                var delta = Number(btn.getAttribute('data-delta'));
                holdRepeat(btn, function() {
                    adjustCartQuantity(cidx, delta, false);
                });
            })(btns[b]);
        }
    }

    function onCartRowClick(e) {
        if (e.target.classList.contains('kshop-qty-btn')) return;
        var idx = Number(e.currentTarget.getAttribute('data-idx'));
        showItemDetail(idx, e.currentTarget);
    }

    function onQtyChange(e) {
        e.stopPropagation();
        if (!canEditCart()) return;
        var idx = Number(e.target.getAttribute('data-idx'));
        var delta = Number(e.target.getAttribute('data-delta'));
        adjustCartQuantity(idx, delta, false);
    }

    // ══════════════════════════════════════════
    //  Item detail (tooltip-style, triggered by row click)
    //  使用 PanelTooltip.showAnchored，生命周期由通用模块管理
    // ══════════════════════════════════════════
    function showItemDetail(idx, anchorEl) {
        var item = findCatalogItem(idx);
        if (!item) return;

        var html = _tooltipCache[idx]
            ? buildRichHtml(item, _tooltipCache[idx])
            : buildBasicHtml(item);
        PanelTooltip.showAnchored(html, anchorEl);
        if (!_tooltipCache[idx]) requestFlashTooltip(idx);
    }

    // ══════════════════════════════════════════
    //  Checkout
    // ══════════════════════════════════════════
    function openSettlement() {
        if (_cart.length === 0 || !canStartShopWrite()) return;
        playCue('modalOpen');
        _settlementView.show();
        requestCheckoutPreview();
    }

    function closeSettlement() {
        _previewRevision++;
        _previewBusy = false;
        _previewQueued = false;
        _checkoutPreview = null;
        if (_settlementView) _settlementView.hide();
    }

    function isValidCheckoutPreview(resp) {
        return !!resp && resp.success === true && resp.v === 1
            && typeof resp.checkoutToken === 'string' && resp.checkoutToken.length > 0
            && Array.isArray(resp.purchaseLines) && typeof resp.canCommit === 'boolean'
            && isFinite(Number(resp.total)) && isFinite(Number(resp.balance))
            && isFinite(Number(resp.projectedBalance)) && typeof resp.blockingError === 'string';
    }

    function requestCheckoutPreview() {
        if (!_settlementView || !_settlementView.isActive()) return;
        if (_cart.length === 0) { closeSettlement(); return; }
        if (_previewBusy) { _previewQueued = true; return; }
        _previewBusy = true;
        _previewQueued = false;
        _checkoutPreview = null;
        _previewRevision++;
        var revision = _previewRevision;
        _settlementView.setLoading();
        requestShop('checkoutPreview', {v: 1, cart: buildCartPayload()}, function(resp) {
            if (revision !== _previewRevision || !_settlementView.isActive()) return;
            _previewBusy = false;
            if (isValidCheckoutPreview(resp)) {
                _checkoutPreview = resp;
                _settlementView.setPreview(resp);
            } else {
                _settlementView.setError(messageForError('checkout', resp && resp.error));
            }
            if (_previewQueued) requestCheckoutPreview();
        });
    }

    function checkout() {
        if (_cart.length === 0 || !canStartShopWrite() || !_checkoutPreview || !_checkoutPreview.canCommit) return;
        var token = _checkoutPreview.checkoutToken;
        _checkoutPreview = null;
        if (!_inventoryCoordinator.beginExternalWrite('shop.checkoutCommit')) {
            toast('背包尚未同步或正在处理另一笔写入。');
            requestCheckoutPreview();
            return;
        }
        _settlementView.setLoading();
        if (!_writeCoordinator.checkout(token, function(resp) {
            if (!isKShopOpen()) return;
            if (resp.success) {
                _kpoints = resp.newBalance;
                if (_balanceEl) _balanceEl.textContent = _kpoints;
                _purchased = resp.purchased || [];
                _purchasedToken = String(resp.purchasedToken || _purchasedToken);
                _cart = [];
                _writeCoordinator.acceptAuthoritativeCart();
                closeSettlement();
                renderCart();
                renderClaimed();
            }
            var needsInventoryRefresh = !!resp.success || !!resp.reconciled;
            _inventoryCoordinator.completeExternalWrite(needsInventoryRefresh, function(refreshResult) {
                renderOwnedInventories();
                if (resp.success && refreshResult.success) {
                    toast('购买成功，商品已直接交付！');
                    playCue('success');
                } else if (resp.success) {
                    toast('购买已成功，但背包刷新失败；请点击“重试库存同步”。');
                    playCue('error');
                } else {
                    toast(messageForError('checkout', resp.error));
                    playCue('error');
                    if (_settlementView && _settlementView.isActive()) requestCheckoutPreview();
                }
            });
        })) {
            _inventoryCoordinator.completeExternalWrite(false);
            toast('商城正在处理另一笔写入，请稍后再结账。');
            requestCheckoutPreview();
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
        if (!isNaN(idx)) showItemDetail(idx, e.currentTarget);
    }

    function onClaim(e) {
        e.stopPropagation();
        if (!canStartShopWrite()) {
            toast('商城尚未同步，请稍后再领取。');
            return;
        }
        var pidx = Number(e.target.getAttribute('data-pidx'));
        if (!_inventoryCoordinator.beginExternalWrite('shop.claim')) {
            toast('背包尚未同步或正在处理另一笔写入。');
            return;
        }
        if (!_writeCoordinator.claim(pidx, function(resp) {
            if (!isKShopOpen()) return;
            if (resp.success) {
                _purchased = resp.purchased || [];
                _purchasedToken = String(resp.purchasedToken || _purchasedToken);
                renderClaimed();
            }
            var needsInventoryRefresh = !!resp.success
                || (!!resp.reconciled && resp.error !== 'item_not_found' && resp.error !== 'stale_state');
            _inventoryCoordinator.completeExternalWrite(needsInventoryRefresh, function(refreshResult) {
                renderOwnedInventories();
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
            });
        })) {
            _inventoryCoordinator.completeExternalWrite(false);
            toast('商城正在处理另一笔写入，请稍后再领取。');
        }
    }

    // ══════════════════════════════════════════
    //  Close — saveCart 失败对话框
    // ══════════════════════════════════════════
    function requestClose() {
        if (_settlementView && _settlementView.isActive()) {
            closeSettlement();
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
        if (_warehousePager) _warehousePager.detach();
        if (_dragController) _dragController.cancel();
        for (var i = 0; i < _ownedDragControllers.length; i++) _ownedDragControllers[i].cancel();
        if (_interactionBroker) _interactionBroker.clearSelection();
        dismissDialog();
        closeSettlement();
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
        closeSettlement();
        dismissQtyInput();
        hideTooltip();
        Panels.close();
        Bridge.send({type:'panel', cmd:'close', panel:'kshop'});
        _closing = false;
    }

    function hideTooltip() {
        PanelTooltip.hide();
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
        if (_warehousePager) _warehousePager.detach();
        if (_dragController) _dragController.cancel();
        for (var i = 0; i < _ownedDragControllers.length; i++) _ownedDragControllers[i].cancel();
        if (_interactionBroker) _interactionBroker.clearSelection();
        _writeCoordinator.forceClose();
        _inventoryCoordinator.close();
        _mux.closeSession();
        dismissDialog();
        closeSettlement();
        dismissQtyInput();
        hideTooltip();
        toast('连接断开，商城已关闭');
    }

    return {
        debugState: function() {
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
                settling: !!(_settlementView && _settlementView.isActive()),
                previewBusy: _previewBusy,
                hasCheckoutPreview: !!_checkoutPreview,
                settlement: _settlementView ? _settlementView.debugState() : null
            };
        }
    };
})();
