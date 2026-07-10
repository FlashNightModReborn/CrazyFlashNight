/**
 * KShop — K点商城面板
 *
 * 数据流: SHOP 按钮 → C# shopPanelOpen → panel_cmd open → KShop.onOpen
 *         → bulkQuery → Flash 回包 → 渲染商品列表
 * 关闭:   ESC/遮罩/关闭按钮 → requestClose → 写协调器收口/对账 → close → shopPanelClose
 *
 * 旧系统行为保留:
 *   - 等级限制: item.level <= playerLevel + reverseLevel 才可购买
 *   - 购买分流: 消耗品/收集品 → 数量+/-, 其他(装备) → 单次加购(qty固定1)
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
    var _closing = false;
    var _activeCategory = null;
    var _categories = [];
    var _iconsLoaded = false;
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
            renderOwnedInventories();
            refreshWriteControls(_writeState || _writeCoordinator.debugState());
        },
        requests: [
            {containerId: '背包', offset: 0, limit: 50},
            {containerId: '仓库', offset: 0, limit: 50}
        ]
    });

    // Gate A1 workbench primitives + DOM refs
    var _workbenchShell, _catalogView, _orderView, _catalogChrome, _backpackView, _warehouseView;
    var _cartGridView, _purchasedGridView, _catalogRenderer, _interactionBroker, _dragController;
    var _ownedViews = [], _ownedDragControllers = [];
    var _shopModeButton, _inventoryModeButton, _inventoryRetryButton;
    var _warehousePrevButton, _warehouseNextButton, _warehousePageLabel;
    var _warehouseDisplaySortSelect, _warehouseAuthoritySortSelect, _warehouseSortButton;
    var _cartDropTarget, _cartDropLabel, _selectedCatalogIdx = null;
    var _dragTooltipSuppressed = false;
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
            if (code === 'busy') return '商城正在处理另一笔写入，请稍后再试。';
            if (code === 'timeout' || code === 'client_timeout' || code === 'reconcile_required') return '结账结果不确定，已按服务器状态刷新，未自动重试。';
            if (code === 'disconnected') return '商城连接已断开，结账不会自动重试。';
            return '购买失败：' + code;
        }
        if (scope === 'claim') {
            if (code === 'inventory_full') return '物品栏已满，无法领取！';
            if (code === 'acquire_failed') return '背包空间不足，无法领取！';
            if (code === 'item_not_found') return '商品不存在或已被领取。';
            if (code === 'stale_state') return '待领取列表已变化，已按权威状态刷新。';
            if (code === 'busy') return '商城正在处理另一笔写入，请稍后再试。';
            if (code === 'timeout' || code === 'client_timeout' || code === 'reconcile_required') return '领取结果不确定，已刷新已购买列表，未自动领取。';
            if (code === 'disconnected') return '商城连接已断开，领取不会自动重试。';
            return '领取失败：' + code;
        }
        if (scope === 'save') {
            if (code === 'busy') return '商城正在处理另一笔写入';
            if (code === 'timeout' || code === 'client_timeout' || code === 'reconcile_required') return '购物车保存结果未知，必须先完成对账';
            if (code === 'disconnected') return '商城连接已断开，购物车尚未确认保存';
            return code === 'unknown' ? '保存失败' : code;
        }
        return code;
    }
    function markCartDirty() {
        return _writeCoordinator.markCartChanged();
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
        var blockEdits = state && !state.canEditCart;
        var inventoryBlocked = !_inventoryState.ready || !!_inventoryState.busyOwner || !!_inventoryState.refreshRequired;
        var blockWrites = state && !state.canStartWrite;
        var claimBlocked = !!blockWrites || inventoryBlocked;
        _el.classList.toggle('kshop-write-busy', !!blockWrites || !!(state && state.saveInFlight));
        var editButtons = _el.querySelectorAll('.kshop-add-btn,.kshop-qty-btn,.kshop-qty-pop-btn,.kshop-qty-confirm');
        for (var i = 0; i < editButtons.length; i++) editButtons[i].disabled = !!blockEdits;
        if (_checkoutBtn) _checkoutBtn.disabled = _cart.length === 0 || !!blockWrites;
        var claimButtons = _el.querySelectorAll('.kshop-claim-btn');
        for (var j = 0; j < claimButtons.length; j++) claimButtons[j].disabled = claimBlocked;
        var ownedNodes = _el.querySelectorAll('.inventory-slot-card');
        for (var k = 0; k < ownedNodes.length; k++) ownedNodes[k].classList.toggle('write-locked', inventoryBlocked);
        if (_warehousePrevButton) _warehousePrevButton.disabled = inventoryBlocked || _warehousePrevButton.getAttribute('data-boundary') === 'start';
        if (_warehouseNextButton) _warehouseNextButton.disabled = inventoryBlocked || _warehouseNextButton.getAttribute('data-boundary') === 'end';
        if (_warehouseDisplaySortSelect) _warehouseDisplaySortSelect.disabled = inventoryBlocked;
        if (_warehouseAuthoritySortSelect) _warehouseAuthoritySortSelect.disabled = inventoryBlocked;
        if (_warehouseSortButton) _warehouseSortButton.disabled = inventoryBlocked;
        if (_inventoryRetryButton) _inventoryRetryButton.style.display = _inventoryState.refreshRequired ? '' : 'none';
        if (_cartDropTarget) {
            _cartDropTarget.classList.toggle('disabled', !!blockEdits);
            _cartDropTarget.setAttribute('aria-disabled', blockEdits ? 'true' : 'false');
        }
        if (_dragController && blockEdits) _dragController.cancel();
        if (_workbenchShell) {
            if (_inventoryState.refreshRequired) _workbenchShell.setStatus('库存投影刷新失败 · 写入锁定', 'warning');
            else if (_inventoryState.busyOwner) _workbenchShell.setStatus('库存事务 · ' + _inventoryState.busyOwner, 'busy');
            else if (state && state.reconcileBlocked) _workbenchShell.setStatus('对账失败 · 写入锁定', 'warning');
            else if (state && state.reconciling) _workbenchShell.setStatus('正在重建权威投影', 'busy');
            else if (state && state.exclusive) _workbenchShell.setStatus('正在提交 ' + state.exclusive, 'busy');
            else if (state && state.saveInFlight) _workbenchShell.setStatus('正在同步购物车', 'busy');
            else if (state && state.dirty) _workbenchShell.setStatus('购物车等待同步', 'pending');
            else _workbenchShell.setStatus('权威状态已同步', 'ready');
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
        _workbenchShell = new Workbench.DualPaneShell({
            eyebrow: 'CF7 / PROCUREMENT WORKBENCH',
            title: 'K点采购工作台',
            subtitle: '目录意图、结算与待领取状态均由 AS2 权威裁决',
            leftLabel: 'CATALOG SOURCE',
            rightLabel: 'ORDER STAGING'
        });
        _el = _workbenchShell.getRoot();
        _el.classList.add('kshop-workbench');
        _balanceEl = _workbenchShell.setMetric('kpoints', 'K 点', 0);

        var modeSwitch = document.createElement('div');
        modeSwitch.className = 'workbench-mode-switch';
        _shopModeButton = document.createElement('button');
        _shopModeButton.type = 'button';
        _shopModeButton.className = 'workbench-mode-btn active';
        _shopModeButton.setAttribute('data-mode', 'shop');
        _shopModeButton.textContent = '采购';
        _shopModeButton.addEventListener('click', showShopMode);
        _inventoryModeButton = document.createElement('button');
        _inventoryModeButton.type = 'button';
        _inventoryModeButton.className = 'workbench-mode-btn';
        _inventoryModeButton.setAttribute('data-mode', 'inventory');
        _inventoryModeButton.textContent = '背包 ↔ 仓库';
        _inventoryModeButton.addEventListener('click', showInventoryMode);
        _inventoryRetryButton = document.createElement('button');
        _inventoryRetryButton.type = 'button';
        _inventoryRetryButton.className = 'workbench-mode-btn warning';
        _inventoryRetryButton.textContent = '重试库存同步';
        _inventoryRetryButton.style.display = 'none';
        _inventoryRetryButton.addEventListener('click', function() {
            _inventoryCoordinator.retryRefresh(function(result) {
                if (!result.success) toast('库存刷新仍失败：' + result.error);
            });
        });
        modeSwitch.appendChild(_shopModeButton);
        modeSwitch.appendChild(_inventoryModeButton);
        modeSwitch.appendChild(_inventoryRetryButton);
        _workbenchShell.addHeaderAction(modeSwitch);

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
        _backpackView = createOwnedInventoryView('背包', 'PLAYER OWNED', '背包');
        _warehouseView = createOwnedInventoryView('仓库', 'STORAGE OWNED', '仓库 · 当前页');
        _warehouseView.displaySortMethod = 'physicalSlot';
        _warehouseView.chrome.setToolbar(createWarehouseToolbar());
        _ownedViews = [_backpackView, _warehouseView];
        _workbenchShell.registerView(_backpackView);
        _workbenchShell.registerView(_warehouseView);
        _workbenchShell.setDefault('L', _catalogView);
        _workbenchShell.setDefault('R', _orderView);
        if (!_workbenchShell.mountInitial(_catalogView, _orderView)) {
            throw new Error('KShop workbench initial view configuration rejected');
        }
        installWorkbenchInteractions();

        // 沉浸全屏化 2026-06-11：把固定 1024×576 画布(.kshop-panel)包进共享 .panel-scale-shell，
        // 由 PanelScale 整体等比缩放，取代旧的 fluid 跟分辨率 reflow（kshop 是最早实现的 panel，配套最不全）。
        _shellEl = document.createElement('div');
        _shellEl.className = 'panel-scale-shell kshop-scale-shell';
        _shellEl.appendChild(_el);
        return _shellEl;
    }

    function createCatalogWorkbenchView() {
        var root = document.createElement('div');
        root.className = 'workbench-view kshop-catalog-view';
        root.setAttribute('data-view-binding', 'shop:catalog');
        _catalogChrome = new Workbench.ViewChrome({
            kicker: 'SOURCE / CATALOG ENTRY',
            title: '供应目录',
            meta: '等待权威目录'
        });
        _catBar = document.createElement('div');
        _catBar.className = 'kshop-categories';
        _catBar.id = 'kshop-cat-bar';
        _catalogChrome.setToolbar(_catBar);

        var gridWrap = document.createElement('div');
        gridWrap.className = 'kshop-grid-wrap workbench-grid-wrap';
        _loadingEl = document.createElement('div');
        _loadingEl.className = 'kshop-loading';
        _loadingEl.id = 'kshop-loading';
        _loadingEl.textContent = '读取权威目录…';
        _catalogRenderer = new Workbench.GridRenderer({
            className: 'kshop-grid workbench-catalog-grid',
            emptyText: '当前分类没有可显示的商品',
            keyOf: function(item) { return item.idx; },
            renderItem: renderCatalogCard,
            bindItem: bindCatalogCard
        });
        _grid = _catalogRenderer.root;
        _grid.id = 'kshop-grid';
        gridWrap.appendChild(_loadingEl);
        gridWrap.appendChild(_grid);
        root.appendChild(_catalogChrome.root);
        root.appendChild(gridWrap);

        return {
            instanceKey: 'shop:catalog',
            instancePolicy: 'singletonByBinding',
            allowedSlots: ['L'],
            viewKind: 'catalog',
            mount: function(container) { container.appendChild(root); },
            unmount: function() { if (root.parentNode) root.parentNode.removeChild(root); },
            render: renderGrid,
            exportOffer: function(item) {
                if (!item || isLocked(item) || item.type === '非卖品') return null;
                return {
                    subjectKind: 'catalogEntry',
                    sourceRef: { catalogIdx: item.idx },
                    offeredOperations: ['shop.addCartIntent']
                };
            },
            getRoot: function() { return root; }
        };
    }

    function createOrderWorkbenchView() {
        var root = document.createElement('div');
        root.className = 'workbench-view kshop-order-view';
        root.setAttribute('data-view-binding', 'shop:cart');

        var cartAdapter = new Workbench.ContainerViewAdapter({
            instanceKey: 'shop:cart-items',
            itemModel: 'intent',
            getItems: function() { return _cart; },
            keyOf: function(item) { return item.idx; },
            renderItem: renderCartRow,
            bindItem: bindCartRow,
            probeAccept: probeCartAccept
        });
        _cartGridView = new Workbench.GridContainerView({
            adapter: cartAdapter,
            title: '购物车',
            kicker: 'INTENT BUFFER',
            meta: '0 种商品',
            className: 'kshop-cart-section',
            gridClassName: 'kshop-cart-list',
            emptyText: '购物车为空 · 从左栏加入采购意图'
        });
        _cartList = _cartGridView.renderer.root;
        _cartList.id = 'kshop-cart-list';

        _cartDropTarget = document.createElement('button');
        _cartDropTarget.type = 'button';
        _cartDropTarget.className = 'kshop-cart-drop-target';
        _cartDropTarget.setAttribute('data-audio-cue', 'select');
        _cartDropTarget.innerHTML = '<span class="kshop-drop-glyph">＋</span><span class="kshop-drop-copy"><b>加入采购队列</b><small>选择商品后点击，或直接拖入此处</small></span>';
        _cartDropLabel = _cartDropTarget.querySelector('small');
        _cartDropTarget.addEventListener('click', onCartSinkClick);
        _cartGridView.root.insertBefore(_cartDropTarget, _cartGridView.renderer.root);

        var footer = document.createElement('div');
        footer.className = 'kshop-cart-footer workbench-commit-bar';
        footer.innerHTML =
            '<span class="workbench-commit-summary">预计结算 <b id="kshop-cart-total">0</b> K</span>' +
            '<button class="kshop-checkout-btn" id="kshop-checkout" data-audio-cue="confirm">核对并结账</button>';
        _cartTotal = footer.querySelector('#kshop-cart-total');
        _checkoutBtn = footer.querySelector('#kshop-checkout');
        _checkoutBtn.addEventListener('click', showCheckoutConfirm);
        _cartGridView.root.appendChild(footer);

        var purchasedAdapter = new Workbench.ContainerViewAdapter({
            instanceKey: 'shop:purchased-items',
            itemModel: 'owned-pending',
            getItems: function() { return _purchased; },
            keyOf: function(item, index) { return index + ':' + String(item && item[1]); },
            renderItem: renderClaimRow,
            bindItem: bindClaimRow
        });
        _purchasedGridView = new Workbench.GridContainerView({
            adapter: purchasedAdapter,
            title: '待领取',
            kicker: 'PURCHASE RECEIPTS',
            meta: '0 条回执',
            className: 'kshop-purchased-section',
            gridClassName: 'kshop-claim-list',
            emptyText: '暂无待领取商品'
        });
        _claimList = _purchasedGridView.renderer.root;
        _claimList.id = 'kshop-claim-list';

        _cartGridView.mount(root);
        _purchasedGridView.mount(root);

        return {
            instanceKey: 'shop:cart',
            instancePolicy: 'singletonByBinding',
            allowedSlots: ['L', 'R'],
            viewKind: 'intent-composite',
            mount: function(container) { container.appendChild(root); },
            unmount: function() { if (root.parentNode) root.parentNode.removeChild(root); },
            render: function() { renderCart(); renderClaimed(); },
            probeAccept: probeCartAccept,
            getRoot: function() { return root; }
        };
    }

    function appendSelectOption(select, value, label) {
        var option = document.createElement('option');
        option.value = value;
        option.textContent = label;
        select.appendChild(option);
    }

    function createWarehouseToolbar() {
        var toolbar = document.createElement('div');
        toolbar.className = 'inventory-warehouse-toolbar';

        var pager = document.createElement('div');
        pager.className = 'inventory-warehouse-pager';
        _warehousePrevButton = document.createElement('button');
        _warehousePrevButton.type = 'button';
        _warehousePrevButton.className = 'inventory-toolbar-btn inventory-page-prev';
        _warehousePrevButton.textContent = '‹';
        _warehousePrevButton.setAttribute('aria-label', '上一页仓库');
        _warehousePrevButton.addEventListener('click', function() { changeWarehousePage(-1); });
        _warehousePageLabel = document.createElement('span');
        _warehousePageLabel.className = 'inventory-page-label';
        _warehousePageLabel.textContent = '1 / 24';
        _warehouseNextButton = document.createElement('button');
        _warehouseNextButton.type = 'button';
        _warehouseNextButton.className = 'inventory-toolbar-btn inventory-page-next';
        _warehouseNextButton.textContent = '›';
        _warehouseNextButton.setAttribute('aria-label', '下一页仓库');
        _warehouseNextButton.addEventListener('click', function() { changeWarehousePage(1); });
        pager.appendChild(_warehousePrevButton);
        pager.appendChild(_warehousePageLabel);
        pager.appendChild(_warehouseNextButton);

        var displayGroup = document.createElement('label');
        displayGroup.className = 'inventory-toolbar-field';
        displayGroup.appendChild(document.createTextNode('显示'));
        _warehouseDisplaySortSelect = document.createElement('select');
        _warehouseDisplaySortSelect.className = 'inventory-display-sort';
        _warehouseDisplaySortSelect.setAttribute('aria-label', '当前页展示排序');
        appendSelectOption(_warehouseDisplaySortSelect, 'physicalSlot', '物理槽位');
        appendSelectOption(_warehouseDisplaySortSelect, 'name', '名称');
        appendSelectOption(_warehouseDisplaySortSelect, 'quantity', '数量');
        _warehouseDisplaySortSelect.addEventListener('change', function() {
            _warehouseView.displaySortMethod = _warehouseDisplaySortSelect.value;
            if (_interactionBroker) _interactionBroker.clearSelection();
            renderOwnedInventories();
        });
        displayGroup.appendChild(_warehouseDisplaySortSelect);

        var authorityGroup = document.createElement('label');
        authorityGroup.className = 'inventory-toolbar-field authority';
        authorityGroup.appendChild(document.createTextNode('权威整理'));
        _warehouseAuthoritySortSelect = document.createElement('select');
        _warehouseAuthoritySortSelect.className = 'inventory-authority-sort';
        _warehouseAuthoritySortSelect.setAttribute('aria-label', '仓库权威整理策略');
        appendSelectOption(_warehouseAuthoritySortSelect, 'byType', '类型');
        appendSelectOption(_warehouseAuthoritySortSelect, 'byUse', '用途');
        appendSelectOption(_warehouseAuthoritySortSelect, 'byPrice', '总价');
        appendSelectOption(_warehouseAuthoritySortSelect, 'byLevel', '等级');
        appendSelectOption(_warehouseAuthoritySortSelect, 'byID', 'ID');
        appendSelectOption(_warehouseAuthoritySortSelect, 'byName', '名称');
        appendSelectOption(_warehouseAuthoritySortSelect, 'byValue', '数量');
        appendSelectOption(_warehouseAuthoritySortSelect, 'byTime', '时间');
        authorityGroup.appendChild(_warehouseAuthoritySortSelect);
        _warehouseSortButton = document.createElement('button');
        _warehouseSortButton.type = 'button';
        _warehouseSortButton.className = 'inventory-toolbar-btn inventory-sort-commit';
        _warehouseSortButton.textContent = '整理并合并';
        _warehouseSortButton.addEventListener('click', showWarehouseSortConfirm);

        toolbar.appendChild(pager);
        toolbar.appendChild(displayGroup);
        toolbar.appendChild(authorityGroup);
        toolbar.appendChild(_warehouseSortButton);
        return toolbar;
    }

    function createOwnedInventoryView(containerId, kicker, title) {
        var adapter = new Workbench.ContainerViewAdapter({
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
            }
        });
        var view = new Workbench.GridContainerView({
            adapter: adapter,
            title: title,
            kicker: kicker,
            meta: '等待 inventory snapshot',
            className: 'inventory-owned-view inventory-owned-' + (containerId === '背包' ? 'backpack' : 'warehouse'),
            gridClassName: 'inventory-owned-grid',
            emptyText: '库存投影尚未就绪',
            allowedSlots: ['L', 'R']
        });
        view.containerId = containerId;
        return view;
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
        var node = document.createElement('article');
        node.className = 'inventory-slot-card ' + (slot.occupied ? 'occupied' : 'empty');
        node.setAttribute('data-container-id', containerId);
        node.setAttribute('data-physical-slot', slot.physicalSlot);
        if (!slot.occupied) {
            node.innerHTML = '<span class="inventory-slot-index">' + (Number(slot.physicalSlot) + 1) + '</span><span class="inventory-empty-mark">EMPTY</span>';
            return node;
        }
        var item = slot.item || {};
        node.innerHTML =
            '<span class="inventory-slot-index">' + (Number(slot.physicalSlot) + 1) + '</span>' +
            '<span class="inventory-slot-icon">' + iconHtml(item.icon || item.name, 'inventory-owned-icon') + '</span>' +
            '<span class="inventory-slot-copy"><b>' + escHtml(item.displayName || item.name || '未知物品') + '</b>' +
            '<small>' + escHtml(item.itemKind || 'owned') + (Number(item.quantity) > 1 ? ' × ' + Number(item.quantity) : '') + '</small></span>' +
            (containerId === '背包' ? '<button class="inventory-discard-btn" type="button" title="丢弃整槽" data-audio-cue="cancel">×</button>' : '');
        return node;
    }

    function bindOwnedSlot(containerId, node, slot) {
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
            var slots = snapshot ? snapshot.slots : [];
            if (view.displaySortMethod && typeof InventoryRuntime.displaySortSlots === 'function') {
                slots = InventoryRuntime.displaySortSlots(slots, view.displaySortMethod);
            }
            view.renderer.render(slots);
            view.chrome.setMeta(snapshot
                ? (snapshot.offset + 1) + '–' + (snapshot.offset + snapshot.slots.length) + ' / ' + snapshot.capacity
                : '等待 inventory snapshot');
        }
        refreshWarehouseToolbar();
    }

    function refreshWarehouseToolbar() {
        if (!_warehousePageLabel) return;
        var snapshot = _inventoryCoordinator.getWindow('仓库');
        var request = _inventoryCoordinator.getRequest('仓库');
        var offset = snapshot ? Number(snapshot.offset) : (request ? Number(request.offset) : 0);
        var limit = request ? Number(request.limit) : 50;
        var capacity = snapshot ? Number(snapshot.capacity) : 1200;
        var pageCount = Math.max(1, Math.ceil(capacity / limit));
        var page = Math.min(pageCount, Math.floor(offset / limit) + 1);
        _warehousePageLabel.textContent = page + ' / ' + pageCount;
        if (_warehousePrevButton) _warehousePrevButton.setAttribute('data-boundary', page <= 1 ? 'start' : '');
        if (_warehouseNextButton) _warehouseNextButton.setAttribute('data-boundary', page >= pageCount ? 'end' : '');
    }

    function changeWarehousePage(direction) {
        if (_interactionBroker) _interactionBroker.clearSelection();
        if (!_inventoryCoordinator.page('仓库', direction, function(result) {
            renderOwnedInventories();
            if (!result.success) toast('仓库翻页失败：' + (result.error || 'inventory_refresh_failed'));
        })) {
            refreshWarehouseToolbar();
        }
    }

    function showWarehouseSortConfirm() {
        if (!_inventoryState.ready || _inventoryState.busyOwner || _inventoryState.refreshRequired) return;
        var methodName = _warehouseAuthoritySortSelect ? _warehouseAuthoritySortSelect.value : 'byType';
        var label = _warehouseAuthoritySortSelect
            ? _warehouseAuthoritySortSelect.options[_warehouseAuthoritySortSelect.selectedIndex].textContent
            : methodName;
        _workbenchShell.openModal({
            kind: 'warehouse-sort',
            kicker: 'AUTHORITATIVE REBUILD / CONFIRM',
            title: '按' + label + '整理整个仓库？',
            message: '将重排全部 1200 个 physicalSlot，并合并可堆叠物品。',
            detail: '当前页保持不变；仓库全部旧 slot lease 会失效，结果以 AS2 回包为准。',
            actions: [
                {id: 'cancel', label: '取消', audioCue: 'cancel'},
                {id: 'sort', label: '整理并合并', primary: true, audioCue: 'confirm', onSelect: function() {
                    if (_interactionBroker) _interactionBroker.clearSelection();
                    if (!_inventoryCoordinator.sortAndMerge('仓库', methodName, function(result) {
                        renderOwnedInventories();
                        if (result.success) toast('仓库已完成权威整理。');
                        else toast('仓库整理未确认：' + (result.error || 'unknown'));
                    })) toast('库存正在处理另一笔写入。');
                }}
            ]
        });
    }

    function showShopMode() {
        if (!_workbenchShell) return;
        _workbenchShell.moveView('L', _catalogView);
        _workbenchShell.moveView('R', _orderView);
        _shopModeButton.classList.add('active');
        _inventoryModeButton.classList.remove('active');
        _workbenchShell.setSlotLabel('L', 'CATALOG SOURCE');
        _workbenchShell.setSlotLabel('R', 'ORDER STAGING');
        _workbenchShell.setTitle('K点采购工作台', '目录意图、结算与待领取状态均由 AS2 权威裁决');
    }

    function showInventoryMode() {
        if (!_workbenchShell) return;
        _workbenchShell.moveView('L', _backpackView);
        _workbenchShell.moveView('R', _warehouseView);
        _shopModeButton.classList.remove('active');
        _inventoryModeButton.classList.add('active');
        _workbenchShell.setSlotLabel('L', 'OWNED / BACKPACK');
        _workbenchShell.setSlotLabel('R', 'OWNED / WAREHOUSE');
        _workbenchShell.setTitle('物品转移工作台', 'windowed snapshot · whole-slot · container epoch');
        renderOwnedInventories();
    }

    function showDiscardConfirm(containerId, slot) {
        if (containerId !== '背包' || !slot.occupied || !_inventoryState.ready) return;
        var projection = slot.confirmProjection || slot.item || {};
        _workbenchShell.openModal({
            kind: 'discard',
            kicker: 'DESTRUCTIVE WRITE / CONFIRM',
            title: '丢弃 ' + String(projection.displayName || '该物品') + '？',
            message: '数量 × ' + Number(projection.quantity || 1) + ' · 将删除整个物品槽。',
            detail: '确认只对当前 slot lease 有效；物品或可见数量变化后 AS2 会拒绝。',
            actions: [
                {id: 'cancel', label: '取消', audioCue: 'cancel'},
                {id: 'discard', label: '确认丢弃', danger: true, audioCue: 'error', onSelect: function() {
                    if (!_inventoryCoordinator.discard(ownedSlotRef(containerId, slot), function(result) {
                        renderOwnedInventories();
                        if (result.success) toast('已丢弃并刷新背包。');
                        else toast('丢弃未提交：' + (result.error || 'unknown'));
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
                if (_catalogRenderer) _catalogRenderer.setSelectedKey(_selectedCatalogIdx);
                if (_cartDropTarget) {
                    _cartDropTarget.classList.toggle('has-selection', _selectedCatalogIdx != null);
                    var item = _selectedCatalogIdx != null ? findCatalogItem(_selectedCatalogIdx) : null;
                    _cartDropLabel.textContent = item ? ('已选择：' + item.displayname + ' · 点击或拖入') : '选择商品后点击，或直接拖入此处';
                }
            }
        });
        _dragController = new Workbench.PointerDragController({
            sourceElement: _grid,
            broker: _interactionBroker,
            timeoutMs: _runtimeConfig.dragTimeoutMs || 1400,
            getSource: function(target) {
                if (!_writeCoordinator.canEditCart()) return null;
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
        dismissDialog();
        if (_interactionBroker) _interactionBroker.clearSelection();
        _mux.openSession();
        _writeCoordinator.open();
        showShopMode();
        _inventoryCoordinator.open(function(result) {
            if (!isKShopOpen()) return;
            renderOwnedInventories();
            if (!result.success) toast('库存加载失败：' + (result.error || 'inventory_refresh_failed'));
        });
        _loading = true;
        if (_workbenchShell) _workbenchShell.setStatus('正在读取权威状态', 'busy');
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
                applyBulkSnapshot(resp);
                _writeCoordinator.acceptAuthoritativeCart();
            } else {
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
        var seen = {};
        _categories = [];
        for (var i = 0; i < _catalog.length; i++) {
            var t = _catalog[i].type;
            if (!seen[t]) { seen[t] = true; _categories.push(t); }
        }
        _activeCategory = _categories[0] || null;
        renderCatBar();
    }

    function renderCatBar() {
        _catBar.innerHTML = '';
        for (var i = 0; i < _categories.length; i++) {
            var btn = document.createElement('button');
            btn.className = 'kshop-cat-btn' + (_categories[i] === _activeCategory ? ' active' : '');
            btn.textContent = _categories[i];
            btn.setAttribute('data-cat', _categories[i]);
            btn.setAttribute('data-audio-cue', 'select');
            btn.addEventListener('click', onCatClick);
            _catBar.appendChild(btn);
        }
    }

    function onCatClick(e) {
        var cat = e.target.getAttribute('data-cat');
        if (cat === _activeCategory) return;
        _activeCategory = cat;
        if (_interactionBroker) _interactionBroker.clearSelection();
        renderCatBar();
        _grid.scrollTop = 0; // 切类回顶
        renderGrid();
    }

    // ══════════════════════════════════════════
    //  Grid — 等级锁定 + 购买分流
    // ══════════════════════════════════════════
    function renderGrid() {
        if (!_catalogRenderer) return;
        var visible = [];
        for (var i = 0; i < _catalog.length; i++) {
            var item = _catalog[i];
            if (item.type !== _activeCategory) continue;
            visible.push(item);
        }
        _catalogRenderer.render(visible);
        _catalogRenderer.setSelectedKey(_selectedCatalogIdx);
        if (_catalogChrome) _catalogChrome.setMeta((visible.length || 0) + ' 项 · ' + (_activeCategory || '未分类'));
        if (!_iconsLoaded) {
            Icons.load(function() { _iconsLoaded = true; renderGrid(); renderCart(); renderClaimed(); });
        }
        refreshWriteControls(_writeState || _writeCoordinator.debugState());
    }

    function renderCatalogCard(item) {
        var locked = isLocked(item);
        var nosale = item.type === '非卖品';
        var stackable = isStackable(item);
        var card = document.createElement('article');
        card.className = 'kshop-card';
        if (nosale) card.classList.add('kshop-card-nosale');
        if (locked) card.classList.add('kshop-card-locked');
        card.setAttribute('data-idx', item.idx);
        card.setAttribute('tabindex', locked || nosale ? '-1' : '0');
        card.setAttribute('aria-label', item.displayname + '，K ' + item.price);
        var actionHtml = '';
        if (!nosale && !locked) {
            actionHtml = '<button class="kshop-add-btn' + (stackable ? '' : ' kshop-add-single') + '" data-idx="' + item.idx + '" data-audio-cue="select" title="加入购物车">' + (stackable ? '+' : '加入') + '</button>';
        }
        var lockHtml = locked
            ? '<div class="kshop-lock" title="Lv.' + item.level + ' 解锁">LOCKED · LV.' + item.level + '</div>'
            : '<div class="kshop-card-type">' + escHtml(item.subType || item.majorType || item.type) + '</div>';
        card.innerHTML =
            '<div class="kshop-card-icon-frame">' + iconHtml(item.icon) + '</div>' +
            '<div class="kshop-card-info">' +
                '<div class="kshop-card-name">' + escHtml(item.displayname) + '</div>' +
                lockHtml +
                '<div class="kshop-card-price"><span>K</span> ' + item.price + '</div>' +
            '</div>' +
            actionHtml +
            '<span class="kshop-card-drag-hint">DRAG</span>';
        return card;
    }

    function bindCatalogCard(card) {
        card.addEventListener('mouseenter', onCardHover);
        card.addEventListener('mouseleave', onCardLeave);
        card.addEventListener('mousemove', onCardMove);
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
        if (!_writeCoordinator.canEditCart()) return;
        var idx = Number(event.currentTarget.getAttribute('data-idx'));
        var item = findCatalogItem(idx);
        if (!item) return;
        _interactionBroker.dispatch(_catalogView, item, _orderView, { binding: 'shop:cart' }, 'double_click');
    }

    function probeCartAccept(offer) {
        if (!_writeCoordinator.canEditCart()) return { accepted: false, reason: 'write_locked' };
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
        if (!_writeCoordinator.canEditCart()) {
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
                    toast('库存转移已提交：' + (result.operation || 'transfer'));
                    playCue('success');
                } else {
                    toast('库存转移未提交：' + (result.error || 'unknown') + (result.reconciled ? ' · 已刷新' : ''));
                    playCue('error');
                }
            })) toast('库存正在处理另一笔写入。');
        }
    }

    function addCatalogIntent(idx, qty) {
        if (!_writeCoordinator.canEditCart()) return false;
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
    var _tooltipHovering = -1; // 当前 hover 的 idx，离开时置 -1

    function onCardHover(e) {
        if (_dragTooltipSuppressed) return;
        var idx = Number(e.currentTarget.getAttribute('data-idx'));
        var item = findCatalogItem(idx);
        if (!item) return;
        _tooltipHovering = idx;

        var html = _tooltipCache[idx]
            ? buildRichHtml(item, _tooltipCache[idx])
            : buildBasicHtml(item);
        PanelTooltip.showAtMouse(html, e);
        if (!_tooltipCache[idx]) requestFlashTooltip(idx);
    }

    function onCardLeave() {
        _tooltipHovering = -1;
        PanelTooltip.hide();
    }

    function onCardMove(e) {
        if (_dragTooltipSuppressed) return;
        PanelTooltip.followMouse(e);
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

    function requestFlashTooltip(idx) {
        requestShop('tooltip', { idx: idx }, function(resp) {
            if (!isKShopOpen()) return;
            if (resp.success) {
                _tooltipCache[idx] = { descHTML: resp.descHTML || '', introHTML: resp.introHTML || '' };
                if (_tooltipHovering === idx && PanelTooltip.isVisible() && isKShopOpen()) {
                    var item = findCatalogItem(idx);
                    if (item) PanelTooltip.updateContent(buildRichHtml(item, _tooltipCache[idx]));
                }
            }
        });
    }

    // ══════════════════════════════════════════
    //  Cart — 购买分流：装备qty固定1，消耗品/收集品可叠加
    // ══════════════════════════════════════════
    function onAddToCart(e) {
        e.stopPropagation();
        if (!_writeCoordinator.canEditCart()) {
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
        if (!_writeCoordinator.canEditCart()) return;
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
            if (!_writeCoordinator.canEditCart()) return;
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
        if (!_writeCoordinator.canEditCart()) return;
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
            _cartGridView.chrome.setMeta(_cart.length + ' 种 · ' + cartQuantity() + ' 件');
        }
        _cartTotal.textContent = total;
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
                    if (!_writeCoordinator.canEditCart()) return;
                    for (var j = 0; j < _cart.length; j++) {
                        if (_cart[j].idx === cidx) {
                            _cart[j].qty += delta;
                            if (_cart[j].qty <= 0) _cart.splice(j, 1);
                            renderCart();
                            markCartDirty();
                            return;
                        }
                    }
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
        if (!_writeCoordinator.canEditCart()) return;
        var idx = Number(e.target.getAttribute('data-idx'));
        var delta = Number(e.target.getAttribute('data-delta'));
        for (var i = 0; i < _cart.length; i++) {
            if (_cart[i].idx === idx) {
                _cart[i].qty += delta;
                if (_cart[i].qty <= 0) _cart.splice(i, 1);
                renderCart();
                markCartDirty();
                return;
            }
        }
    }

    // ══════════════════════════════════════════
    //  Item detail (tooltip-style, triggered by row click)
    //  使用 PanelTooltip.showAnchored，生命周期由通用模块管理
    // ══════════════════════════════════════════
    function showItemDetail(idx, anchorEl) {
        var item = findCatalogItem(idx);
        if (!item) return;

        _tooltipHovering = idx;
        var html = _tooltipCache[idx]
            ? buildRichHtml(item, _tooltipCache[idx])
            : buildBasicHtml(item);
        PanelTooltip.showAnchored(html, anchorEl);
        if (!_tooltipCache[idx]) requestFlashTooltip(idx);
    }

    // ══════════════════════════════════════════
    //  Checkout
    // ══════════════════════════════════════════
    function showCheckoutConfirm() {
        if (_cart.length === 0 || !_writeCoordinator.debugState().canStartWrite) return;
        var total = 0;
        for (var i = 0; i < _cart.length; i++) {
            var item = findCatalogItem(_cart[i].idx);
            if (item) total += Number(item.price) * Number(_cart[i].qty);
        }
        playCue('modalOpen');
        _workbenchShell.openModal({
            kind: 'commit',
            kicker: 'MODAL ② / BATCH COMMIT',
            title: '确认结算采购队列',
            message: _cart.length + ' 种商品，共 ' + cartQuantity() + ' 件',
            detail: '预计扣除 K ' + total + '。提交后购物车将清空，商品进入待领取区。',
            actions: [
                { id: 'cancel', label: '返回核对', audioCue: 'cancel' },
                { id: 'confirm', label: '确认结账', primary: true, audioCue: 'confirm', onSelect: checkout }
            ]
        });
    }

    function checkout() {
        if (_cart.length === 0) return;
        if (!_writeCoordinator.checkout(function(resp) {
            if (!isKShopOpen()) return;
            if (resp.success) {
                _kpoints = resp.newBalance;
                if (_balanceEl) _balanceEl.textContent = _kpoints;
                _purchased = resp.purchased || [];
                _purchasedToken = String(resp.purchasedToken || _purchasedToken);
                _cart = [];
                _writeCoordinator.acceptAuthoritativeCart();
                renderCart();
                renderClaimed();
                toast('购买成功！');
                playCue('success');
            } else if (resp.reconciled) {
                toast(messageForError('checkout', resp.error));
                playCue('error');
            } else {
                toast(messageForError('checkout', resp.error));
                playCue('error');
            }
        })) {
            toast('商城正在处理另一笔写入，请稍后再结账。');
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
            _purchasedGridView.chrome.setMeta(_purchased.length + ' 条回执');
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
        for (var i = 0; i < _ownedDragControllers.length; i++) _ownedDragControllers[i].cancel();
        if (_interactionBroker) _interactionBroker.clearSelection();
        dismissDialog();
        hideTooltip();
        _writeCoordinator.forceClose();
        _inventoryCoordinator.close();
        _mux.closeSession();
        _closing = false;
    }

    function doClose() {
        dismissDialog();
        dismissQtyInput();
        hideTooltip();
        Panels.close();
        Bridge.send({type:'panel', cmd:'close', panel:'kshop'});
        _closing = false;
    }

    function hideTooltip() {
        _tooltipHovering = -1;
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
            kicker: 'WRITE GATE / RECONCILE',
            title: msg,
            message: timeoutMode ? '购物车状态未知，写入口保持锁定。' : '可重新对账，或返回继续购物。',
            detail: '强制关闭不会重放任何已下发写请求；重新打开时仍以权威状态为准。',
            actions: actions
        });
    }

    function dismissDialog() {
        if (_workbenchShell) _workbenchShell.closeModal();
    }

    function onForceClose() {
        _closing = false;
        if (_dragController) _dragController.cancel();
        for (var i = 0; i < _ownedDragControllers.length; i++) _ownedDragControllers[i].cancel();
        if (_interactionBroker) _interactionBroker.clearSelection();
        _writeCoordinator.forceClose();
        _inventoryCoordinator.close();
        _mux.closeSession();
        dismissDialog();
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
                cartCount: _cart.length,
                purchasedCount: _purchased.length
            };
        }
    };
})();
