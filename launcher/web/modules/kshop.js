/**
 * KShop — K点商城面板
 *
 * 数据流: SHOP 按钮 → C# shopPanelOpen → panel_cmd open → KShop.onOpen
 *         → bulkQuery → Flash 回包 → 渲染商品列表
 * 关闭:   ESC/遮罩/关闭按钮 → requestClose → 写协调器收口/对账 → close → shopPanelClose
 *
 * 商城行为:
 *   - 等级限制: item.level <= playerLevel + reverseLevel 才可购买
 *   - 目录与购物车只负责加购/移除；所有数量精调统一进入结算页
 *   - 新购买: checkoutPreview 权威核算 → checkoutCommit 原子直接入包
 *   - 旧存档: 商城已购买物品仅保留历史 claim 兼容，不再增长
 */
var KShop = (function() {
    'use strict';

    var _catalog = [];
    var _cart = [];           // [{idx, qty}, ...]
    var _purchased = [];
    var _purchasedToken = '';
    var _protocolCheckoutPreview = null;
    var _kpoints = 0;
    var _playerLevel = 0;
    var _reverseLevel = 0;
    var _shopReady = false;
    var _closing = false;
    var _loading = false;
    var _writeState = null;
    var _panelInstanceId = '';
    var _runtimeConfig = (typeof window !== 'undefined' && window.__KSHOP_RUNTIME_CONFIG__) || {};
    var _mux = new KShopRequestMux({
        send: function(message) { return Bridge.send(message); },
        timeoutMs: _runtimeConfig.requestTimeoutMs,
        sessionNonce: _runtimeConfig.sessionNonce,
        onProtocolError: function(message) {
            if (typeof console !== 'undefined' && console.warn) console.warn(message);
        }
    });
    function createInventoryRequestMux() {
        return new PanelRuntime.PanelRequestMux({
            send:function(message) { return Bridge.send(message); },
            timeoutMs:_runtimeConfig.requestTimeoutMs,
            sessionNonce:_runtimeConfig.sessionNonce,
            callPrefix:'kshop-inventory',
            router:PanelRuntime.sharedResponseRouter,
            validateSession:function(session) {
                return !!session && session.ownerPanel === 'kshop'
                    && /^[A-Za-z0-9._~-]{1,128}$/.test(
                        String(session.panelInstanceId || ''));
            },
            createMessage:function(context) {
                return {type:'panel', domain:'inventory', panel:'kshop',
                    panelInstanceId:context.session.panelInstanceId,
                    cmd:context.entry.cmd, callId:context.entry.callId,
                    payload:context.payload || {}};
            },
            validateResponse:function(data, entry) {
                return !!data && data.type === 'panel_resp'
                    && data.domain === 'inventory' && data.panel === 'kshop'
                    && data.panelInstanceId === entry.session.panelInstanceId
                    && data.callId === entry.callId && data.cmd === entry.cmd;
            },
            createSynthetic:function(context) {
                return {type:'panel_resp', domain:'inventory', panel:'kshop',
                    panelInstanceId:context.session.panelInstanceId,
                    cmd:context.entry.cmd, callId:context.entry.callId,
                    success:false, error:context.error, clientSynthetic:true};
            },
            onProtocolError:function(message) {
                if (typeof console !== 'undefined' && console.warn) console.warn(message);
            }
        });
    }
    var _inventoryMux = createInventoryRequestMux();
    var _writeCoordinator = new KShopWriteCoordinator({
        request: requestShop,
        getCart: buildCartPayload,
        acceptSavedCart: function(cart, adjusted) {
            _cart = Array.isArray(cart) ? JSON.parse(JSON.stringify(cart)) : [];
            if (_cartController) _cartController.render();
            if (adjusted) toast('购物车中超过当前持有上限或已失效的数量已自动调整。');
        },
        getPurchasedToken: function() { return _purchasedToken; },
        applyBulkSnapshot: applyBulkSnapshot,
        onStateChange: refreshWriteControls,
        debounceMs: _runtimeConfig.cartSaveDebounceMs
    });
    var _inventoryState = { opened: false, ready: false, busyOwner: null, refreshRequired: false };
    var _inventoryCoordinator = new InventoryRuntime.InventoryCoordinator({
        request: requestInventory,
        readPhysicalSurface:function(isActive, callback) {
            return InventoryRuntime.readPhysicalInventorySurface(requestInventory,
                {isActive:isActive,expectedPanel:'kshop',
                    expectedPanelInstanceId:_panelInstanceId}, callback);
        },
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
    var _workbenchShell, _workbenchHelp, _closeButton,
        _catalogView, _orderView, _backpackView, _warehouseView;
    var _cartGridView, _purchasedGridView, _catalogRenderer, _interactionBroker, _dragController;
    var _shopModeButton, _inventoryModeButton, _inventoryRetryButton, _modeChoiceGroup;
    var _cartDropTarget, _selectedCatalogIdx = null;
    var _dragTooltipSuppressed = false;
    var _ownedTooltipSelectionSuppressed = false;
    var _tooltipScope = null;
    var _layoutMode = 'full', _densityController = null, _layoutToggle = null;
    var _el, _shellEl, _grid, _balanceEl, _checkoutBtn, _loadingEl;
    var _scaleHandle = null;   // 沉浸全屏化：PanelScale 句柄
    var _procurementNavigation = KShopProcurementNavigation.create({
        protocol:KShopProtocol,
        bridge:Bridge,
        writeCoordinator:_writeCoordinator,
        getOwner:function() { return {panelInstanceId:_panelInstanceId}; },
        getCatalog:function() { return _catalog; },
        getRenderer:function() { return _catalogRenderer; },
        getShopReady:function() { return _shopReady; },
        getInventoryState:function() { return _inventoryState; },
        getWriteState:function() { return _writeState; },
        isOpen:isKShopOpen,
        refreshControls:function() {
            refreshWriteControls(_writeCoordinator.debugState());
        },
        toast:toast
    });

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
            renderComplete:function() {
                refreshWriteControls(_writeState || _writeCoordinator.debugState());
                _procurementNavigation.applyTarget(false);
            },
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
            ownedSlotRef:KShopOwnedInventoryPresenter.ownedSlotRef,
            bindAsyncHover:function(node, options) {
                return _tooltipScope
                    ? _tooltipScope.bindAsyncHover(node, options)
                    : PanelTooltip.bindAsyncHover(node, options);
            }
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
            canStartWrite:canStartShopWrite
        },
        intent:{
            replaceCart:function(next) { _cart = next; },
            markDirty:markCartDirty,
            refreshControls:function() { refreshWriteControls(_writeState || _writeCoordinator.debugState()); },
            toast:toast,
            iconHtml:iconHtml,
            escapeHtml:escHtml,
            inspect:function(idx, anchor) { _tooltipPresenter.showItemDetail(idx, anchor); },
            requestShop:requestShop,
            errorMessage:messageForError,
            commitCheckout:commitCheckout,
            openHelp:function(opener) { if (_workbenchHelp) _workbenchHelp.open(opener); },
            requestPanelClose:requestClose,
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
            toast:toast
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
    // 契约 §2 unknown: 超时/对账必需/断线 = 权威结果不可知, 与明确失败 (rejected) 区分
    function isUncertainResult(error) {
        return error === 'timeout' || error === 'client_timeout' || error === 'reconcile_required' || error === 'disconnected';
    }
    function buildCartPayload() {
        return _cartController.buildPayload();
    }
    function messageForError(scope, error) {
        var code = error || 'unknown';
        if (scope === 'checkout') {
            if (code === 'insufficient_kpoints') return 'K点不足！';
            if (code === 'inventory_full') return '背包容量不足，整单未扣款。';
            if (code === 'destination_full') return '对应收集项已达持有上限，整单未扣款。';
            if (code === 'invalid_quantity') return '购买数量超过当前商品上限，请按目录提示调整。';
            if (code === 'stale_state') return '商品、余额或背包状态已变化，请重新核对。';
            if (code === 'busy') return '商城正在处理另一笔写入，请稍后再试。';
            if (code === 'timeout' || code === 'client_timeout' || code === 'reconcile_required') return '结账结果不确定，已按服务器状态刷新，未自动重试。';
            if (code === 'disconnected') return '商城连接已断开，结账不会自动重试。';
            if (typeof console !== 'undefined' && console.warn) console.warn('[KShop checkout]', code);
            return '购买失败，请重试。';
        }
        if (scope === 'claim') {
            if (code === 'inventory_full') return '物品栏已满，无法领取！';
            if (code === 'destination_full') return '对应收集项已达持有上限，暂时无法领取！';
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
        var normalized = KShopProtocol.normalizeRequest(cmd, payload || {});
        if (!normalized) {
            if (typeof callback === 'function') callback({success:false,error:'invalid_payload',clientSynthetic:true});
            return null;
        }
        var authority = {
            catalog:JSON.parse(JSON.stringify(_catalog || [])),
            cart:JSON.parse(JSON.stringify(buildCartPayload() || [])),
            purchased:JSON.parse(JSON.stringify(_purchased || [])),
            purchasedToken:String(_purchasedToken || ''),
            balance:Number(_kpoints),
            preview:_protocolCheckoutPreview
                ? JSON.parse(JSON.stringify(_protocolCheckoutPreview)) : null
        };
        if (cmd === 'checkoutPreview' || cmd === 'bulkQuery'
                || cmd === 'checkout' || cmd === 'claim' || cmd === 'checkoutCommit') {
            _protocolCheckoutPreview = null;
        }
        return _mux.request('shop', cmd, normalized, function(response) {
            var sanitized = KShopProtocol.sanitizeResponse(cmd, normalized, response, authority);
            if (!sanitized) sanitized = {success:false,error:'invalid_response',clientSynthetic:true};
            if (cmd === 'checkoutPreview' && sanitized.success === true) {
                _protocolCheckoutPreview = JSON.parse(JSON.stringify(sanitized));
            }
            if (typeof callback === 'function') callback(sanitized);
        });
    }

    function requestInventory(cmd, payload, callback) {
        return _inventoryMux.request(cmd, payload || {}, {
            sendError:'disconnected'
        }, callback);
    }

    function isKShopOpen() {
        return Panels.getActive ? Panels.getActive() === 'kshop' : Panels.isOpen();
    }

    function applyBulkSnapshot(resp, options) {
        options = options || {};
        _catalog = resp.catalog || _catalog || [];
        var incomingCart = options.preserveCart ? _cart : (resp.cart || []);
        var sanitized = KShopCartController.sanitizeCart(incomingCart, findCatalogItem, isStackable);
        _cart = sanitized.cart;
        var cartAdjusted = !!(resp.cartAdjusted || sanitized.adjusted);
        if (cartAdjusted && !options.preserveCart) {
            toast('购物车中超过当前持有上限或已失效的数量已自动调整。');
        }
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
        return {cartAdjusted:cartAdjusted};
    }

    function applyWriteCatalog(catalog) {
        _catalog = Array.isArray(catalog) ? catalog : _catalog;
        var sanitized = KShopCartController.sanitizeCart(_cart, findCatalogItem, isStackable);
        _cart = sanitized.cart;
        _catalogPresenter.rebuildCategories();
        _catalogPresenter.render();
        _cartController.render();
        if (sanitized.adjusted) {
            toast('购物车中超过最新持有上限的数量已自动调整。');
            markCartDirty();
        }
        return sanitized.adjusted;
    }

    function refreshWriteControls(state) {
        _writeState = state;
        if (!_el) return;
        var blockEdits = !_shopReady || (state && !state.canEditCart);
        var inventoryBlocked = !_inventoryState.ready || !!_inventoryState.busyOwner || !!_inventoryState.refreshRequired;
        var blockWrites = !_shopReady || (state && !state.canStartWrite);
        var claimBlocked = !!blockWrites || inventoryBlocked;
        _el.classList.toggle('kshop-write-busy', !!blockWrites || !!(state && state.saveInFlight));
        var editButtons = _el.querySelectorAll('.kshop-add-btn,.kshop-cart-remove-btn');
        for (var i = 0; i < editButtons.length; i++) editButtons[i].disabled = !!blockEdits;
        if (_checkoutBtn) _checkoutBtn.disabled = _cart.length === 0 || !!blockWrites;
        if (_cartController.getSettlement()) _cartController.getSettlement().render();
        var claimButtons = _el.querySelectorAll('.kshop-claim-btn');
        for (var j = 0; j < claimButtons.length; j++) claimButtons[j].disabled = claimBlocked;
        _ownedPresenter.setAuthorityState(_inventoryState);
        if (_inventoryRetryButton) _inventoryRetryButton.style.display = _inventoryState.refreshRequired ? '' : 'none';
        if (_cartDropTarget) {
            _cartDropTarget.classList.toggle('disabled', !!blockEdits);
            _cartDropTarget.setAttribute('aria-disabled', blockEdits ? 'true' : 'false');
        }
        if (_dragController && blockEdits) _dragController.cancel();
        if (_workbenchShell) {
            if (_procurementNavigation.isReturning()) {
                _workbenchShell.setStatus('正在返回合成', 'busy');
            }
            else if (!_shopReady) _workbenchShell.setStatus(_loading ? '同步中' : '商城暂不可用', _loading ? 'busy' : 'warning');
            else if (_inventoryState.refreshRequired) _workbenchShell.setStatus('背包同步失败', 'warning');
            else if (_inventoryState.busyOwner) _workbenchShell.setStatus('处理中', 'busy');
            else if (state && state.reconcileBlocked) _workbenchShell.setStatus('同步失败', 'warning');
            else if (state && state.reconciling) _workbenchShell.setStatus('正在恢复', 'busy');
            else if (state && state.exclusive) _workbenchShell.setStatus('正在提交', 'busy');
            else if (state && (state.saveInFlight || state.dirty)) _workbenchShell.setStatus('正在保存', state.saveInFlight ? 'busy' : 'pending');
            else _workbenchShell.setStatus('已同步', 'ready');
        }
        if (state && state.reconcileBlocked) {
            showSaveFailedDialog('商城对账失败，写操作保持锁定', true);
        }
        _procurementNavigation.refreshControls();
    }

    // ══════════════════════════════════════════
    //  Panel registration
    // ══════════════════════════════════════════
    Panels.register('kshop', {
        create: createDOM,
        onOpen: onOpen,
        onRebind: onRebind,
        onClose: onClose,
        onRequestClose: function(reason) { requestClose(reason); },
        onForceClose: onForceClose
    });

    function createDOM() {
        if (typeof Workbench === 'undefined') throw new Error('Workbench runtime is required before KShop');
        if (typeof KShopViews === 'undefined') throw new Error('KShop view composition is required before KShop');
        _workbenchShell = new Workbench.DualPaneShell({
            profile: 'catalog-decision',
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
            onChange:function(mode) {
                if (mode === 'inventory') showInventoryMode(true);
                else showShopMode(true);
            }
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
        _layoutToggle = _densityController.createToggle(function(mode) { _layoutMode = mode; });
        _workbenchShell.addHeaderAction(_layoutToggle);

        _workbenchHelp = new WorkbenchComponents.HelpAction({shell:_workbenchShell});

        _procurementNavigation.createReturnAction(_workbenchShell);

        _closeButton = document.createElement('button');
        _closeButton.className = 'kshop-close-btn workbench-close-btn';
        _closeButton.type = 'button';
        _closeButton.textContent = '×';
        _closeButton.setAttribute('data-header-action', 'close');
        _closeButton.setAttribute('data-audio-cue', 'back');
        _closeButton.addEventListener('click', function() { requestClose('header'); });
        _workbenchShell.addHeaderAction(_closeButton);

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

    function showShopMode(restoreModeFocus) {
        if (!_workbenchShell) return;
        _el.setAttribute('data-workbench-skin', 'shop');
        _ownedPresenter.setMenuOpen(false);
        _workbenchShell.moveView('L', _catalogView);
        _workbenchShell.moveView('R', _orderView);
        updateModeContext('shop', restoreModeFocus);
    }

    function showInventoryMode(restoreModeFocus) {
        if (!_workbenchShell) return;
        _cartController.closeSettlement();
        _el.setAttribute('data-workbench-skin', 'inventory');
        _workbenchShell.moveView('L', _backpackView);
        _workbenchShell.moveView('R', _warehouseView);
        updateModeContext('inventory', restoreModeFocus);
        _ownedPresenter.render();
    }

    function applyModeActionProjection(inventory) {
        _modeChoiceGroup.update({value:inventory ? 'inventory' : 'shop', disabled:false});
        [_shopModeButton, _inventoryModeButton].forEach(function(button) {
            button.hidden = false;
            button.disabled = false;
            button.removeAttribute('aria-disabled');
            button.removeAttribute('title');
        });
        _closeButton.hidden = false;
        _closeButton.disabled = false;
        _closeButton.removeAttribute('aria-disabled');
        _closeButton.removeAttribute('title');
    }

    function updateModeContext(mode, restoreModeFocus) {
        var inventory = mode === 'inventory';
        _workbenchShell.setProfile(inventory ? 'transfer-pair' : 'catalog-decision');
        _el.setAttribute('data-kshop-mode', inventory ? 'inventory' : 'shop');
        applyModeActionProjection(inventory);
        _workbenchShell.setSlotLabel('L', inventory ? '背包' : '商品');
        _workbenchShell.setSlotLabel('R', inventory ? '战备箱' : '购物车');
        _workbenchShell.setTitle(inventory ? '物品管理' : 'K点商城', '');
        if (_closeButton) _closeButton.setAttribute(
            'aria-label', inventory ? '关闭物品管理' : '关闭商城');
        if (_workbenchHelp) _workbenchHelp.update(inventory ? {
            kind:'kshop-inventory-help',
            ariaLabel:'查看物品管理帮助',
            title:'物品管理帮助',
            message:'背包与战备箱\n• 先选择一侧物品，再选择另一侧目标格；也可以直接拖拽到目标位置。\n• 按住 Ctrl 单击物品可快速转移，系统会优先合并同名堆叠，再寻找空格。',
            detail:'浏览与返回\n• “完整 / 紧凑”只改变物品格密度，不改变库存内容或操作能力。\n• 切回商城不会提交购物车；关闭按钮会关闭整个商城与物品管理面板。',
            actions:[{id:'close', label:'知道了', primary:true, audioCue:'activate'}]
        } : {
            kind:'kshop-help',
            ariaLabel:'查看 K 点商城帮助',
            title:'K 点商城帮助',
            message:'选购与结算\n• 单击商品或右上角“+”每次加购 1 件；拖入购物车仍可作为可选操作。\n• 购物车只负责查看与移除整行。需要精确数量时，点击“核对并结账”进入结算页统一调整。',
            detail:'数量与交付\n• 结算页支持数字输入、− / + / +5、“可用”和滑条；大数量会使用对数滑条，输入值仍是实际件数。\n• “可用”表示当前可直接结算数量，最终价格、容量与上限以每次游戏核算结果为准。\n• 新购商品会直接进入背包；“历史待领取”只处理旧存档遗留商品。\n\n浏览与库存\n• “完整 / 紧凑”控制物品格密度；分类、套装和专柜可逐层筛选。\n• 顶部“战备箱”切换到库存整理，不会提交商城订单。',
            actions:[{id:'close', label:'知道了', primary:true, audioCue:'activate'}]
        });
        if (restoreModeFocus) {
            (inventory ? _inventoryModeButton : _shopModeButton).focus();
        }
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
    function resetSessionScrollPositions() {
        var roots = [];
        var catalogGrid = _catalogPresenter && _catalogPresenter.getGrid();
        var order = _cartController && _cartController.getComposition();
        if (catalogGrid) roots.push(catalogGrid);
        if (order && order.cartList) roots.push(order.cartList);
        if (order && order.claimList) roots.push(order.claimList);
        var ownedViews = _ownedPresenter ? _ownedPresenter.getViews() : [];
        for (var i = 0; i < ownedViews.length; i++) if (ownedViews[i].renderer) roots.push(ownedViews[i].renderer.root);
        for (var j = 0; j < roots.length; j++) { roots[j].scrollTop = 0; roots[j].scrollLeft = 0; }
    }

    function onOpen(el, initData) {
        initData = initData || {};
        _panelInstanceId = typeof initData.panelInstanceId === 'string'
            ? initData.panelInstanceId : '';
        if (!/^[A-Za-z0-9._~-]{1,128}$/.test(_panelInstanceId)) {
            _panelInstanceId = '';
            return false;
        }
        var savedLayoutMode = Workbench.ItemGrid.getLayoutMode('kshop', 'compact');
        if (_densityController) _densityController.setMode(savedLayoutMode);
        _layoutMode = _densityController ? _densityController.mode : savedLayoutMode;
        if (_layoutToggle && typeof _layoutToggle.setLayoutMode === 'function') {
            _layoutToggle.setLayoutMode(_layoutMode);
        }
        _procurementNavigation.configure(initData);
        if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = (typeof PanelScale !== 'undefined') ? PanelScale.attach(_shellEl, 1024, 576) : null;
        if (_tooltipScope) _tooltipScope.dispose();
        _tooltipScope = (typeof PanelTooltip !== 'undefined' && PanelTooltip.createScope)
            ? PanelTooltip.createScope('kshop', {profile:'dense-inspect'}) : null;
        _closing = false;
        _shopReady = false;
        _loading = true;
        _catalog = [];
        _cart = [];
        _purchased = [];
        _purchasedToken = '';
        _protocolCheckoutPreview = null;
        _catalogPresenter.reset();
        resetSessionScrollPositions();
        _tooltipPresenter.reset();
        _ownedTooltipSelectionSuppressed = false;
        _ownedPresenter.resetSession();
        dismissDialog();
        _cartController.closeSettlement();
        if (_interactionBroker) _interactionBroker.clearSelection();
        _catalogPresenter.rebuildCategories();
        _cartController.render();
        renderClaimed();
        if (!_mux.openSession({
                ownerPanel:'kshop',
                panelInstanceId:_panelInstanceId
            })) return false;
        if (!_inventoryMux.openSession({
                ownerPanel:'kshop',
                panelInstanceId:_panelInstanceId
            })) return false;
        _writeCoordinator.open();
        showShopMode(false);
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
                var applied = applyBulkSnapshot(resp);
                _writeCoordinator.acceptAuthoritativeCart();
                _procurementNavigation.applyTarget(true);
                // bulkQuery 返回的是清理后的影子，不代表 AS2 已把清理结果写回存档。
                if (applied.cartAdjusted) markCartDirty();
            } else {
                _shopReady = false;
                refreshWriteControls(_writeCoordinator.debugState());
                toast('商城加载失败：' + messageForError('save', resp.error || 'invalid_response'));
            }
        });
    }

    function onRebind(el, initData) {
        // Host same-name replacement is a new capability generation. Retire every
        // old request/write/inventory owner before admitting the replacement so a
        // late response cannot mutate the still-mounted DOM under the new owner.
        onClose();
        return onOpen(el, initData);
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
            if (resp.success) {
                _kpoints = resp.newBalance;
                if (_balanceEl) _balanceEl.textContent = _kpoints;
                _purchased = resp.purchased || [];
                _purchasedToken = String(resp.purchasedToken || _purchasedToken);
                _cart = resp.cart || [];
                _writeCoordinator.acceptAuthoritativeCart();
                _cartController.closeSettlement();
                applyWriteCatalog(resp.catalog);
                renderClaimed();
            }
            if (!_inventoryCoordinator.completeExternalWrite(inventoryWrite, needsInventoryRefresh, function(refreshResult) {
                if (!isKShopOpen()) return;
                _ownedPresenter.render();
                if (resp.success && refreshResult.success) {
                    toast('购买成功，商品已直接交付！');
                    var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
                    if (A && typeof A.cue === 'function') A.cue('success');
                } else if (resp.success) {
                    toast('购买已成功，但背包刷新失败；请点击“重试库存同步”。');
                    var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
                    if (A && typeof A.cue === 'function') A.cue('success');
                } else {
                    toast(messageForError('checkout', resp.error));
                    var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
                    if (A && typeof A.cue === 'function') A.cue(isUncertainResult(resp.error) ? 'unknown' : 'rejected');
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
                totalPending += Number(_purchased[p].quantity) || 0;
            }
            _purchasedGridView.chrome.setMeta(totalPending > 0 ? totalPending + ' 件' : '');
        }
        refreshWriteControls(_writeState || _writeCoordinator.debugState());
    }

    function renderClaimRow(purchasedItem, purchasedIndex) {
        var itemName = String(purchasedItem.item);
        var qty = Number(purchasedItem.quantity);
        var catItem = findCatalogByName(itemName);
        var displayName = String(purchasedItem.displayname);
        var iconName = String(purchasedItem.icon);
        var row = document.createElement('article');
        row.className = 'kshop-claim-row';
        row.setAttribute('data-pidx', purchasedIndex);
        if (catItem) row.setAttribute('data-idx', catItem.idx);
        row.innerHTML =
            '<span class="kshop-cart-thumb">' + iconHtml(iconName, 'kshop-row-icon') + '</span>' +
            '<span class="kshop-claim-copy"><b class="kshop-claim-name">' + escHtml(displayName) + '</b><small>待领取 × ' + qty + '</small></span>' +
            '<button class="kshop-claim-btn" data-pidx="' + purchasedIndex + '" data-audio-cue="activate">领取</button>';
        return row;
    }

    function bindClaimRow(row, purchasedItem, purchasedIndex) {
        var button = row.querySelector('.kshop-claim-btn');
        if (button) button.addEventListener('click', onClaim);
        var idx = Number(row.getAttribute('data-idx'));
        if (isNaN(idx)) return;
        var item = findCatalogItem(idx);
        Workbench.EntityTile.bindActivation(row, {
            itemName:item ? item.displayname : String(purchasedItem && purchasedItem.displayname || '待领取商品'),
            label:'查看商品详情；领取操作使用行内按钮',
            inspectable:true,
            actionable:true,
            onActivate:function() { _tooltipPresenter.showItemDetail(idx, row); }
        });
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
                    applyWriteCatalog(resp.catalog);
                    renderClaimed();
                }
                _ownedPresenter.render();
                if (resp.success && refreshResult.success) {
                    toast('领取成功，背包已刷新！');
                    var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
                    if (A && typeof A.cue === 'function') A.cue('success');
                } else if (resp.success) {
                    toast('领取已成功，但背包刷新失败；请点击“重试库存同步”。');
                    var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
                    if (A && typeof A.cue === 'function') A.cue('success');
                } else {
                    toast(messageForError('claim', resp.error));
                    var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
                    if (A && typeof A.cue === 'function') A.cue(isUncertainResult(resp.error) ? 'unknown' : 'rejected');
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
    function requestClose(reason) {
        if (_procurementNavigation.isReturning()) {
            toast('正在返回原合成配方，请稍候。');
            return false;
        }
        if (_cartController.getSettlement() && _cartController.getSettlement().isActive() && reason === 'escape') { // 契约 §5.5：Esc 只剥结算页返回商城；×/backdrop/toggle 由整面板关闭经 onClose 统一 teardown
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
        if (_tooltipScope) { _tooltipScope.dispose(); _tooltipScope = null; }
        _shopReady = false;
        _loading = false;
        _writeCoordinator.forceClose();
        _inventoryCoordinator.close();
        _inventoryMux.closeSession();
        _mux.closeSession();
        _closing = false;
        _panelInstanceId = '';
        _procurementNavigation.cleanup();
        _protocolCheckoutPreview = null;
    }

    function doClose() {
        var accepted = false;
        try {
            accepted = Bridge.send({type:'panel', cmd:'close', panel:'kshop',
                panelInstanceId:_panelInstanceId}) !== false;
        } catch (_) {
            accepted = false;
        }
        if (!accepted) {
            // The cart was already saved before doClose. Re-arm the local write lifecycle so
            // a failed owner-envelope transport remains genuinely retryable.
            _writeCoordinator.open();
            toast('启动器连接不可用，商城保持打开。');
            _closing = false;
            return false;
        }
        dismissDialog();
        _cartController.closeSettlement();
        hideTooltip();
        Panels.close();
        _closing = false;
        return true;
    }

    function hideTooltip() {
        _tooltipPresenter.hide();
    }

    function showSaveFailedDialog(msg, timeoutMode) {
        var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
        if (A && typeof A.cue === 'function') A.cue('open');
        var actions = [
            {
                id: 'retry', label: '重新对账', primary: true, audioCue: 'select',
                onSelect: function() { if (!_writeCoordinator.retryReconcile()) requestClose(); }
            }
        ];
        if (!timeoutMode) {
            actions.push({ id: 'cancel', label: '继续购物', audioCue: 'back', onSelect: function() { _closing = false; } });
        }
        actions.push({ id: 'force', label: '强制关闭', danger: true, audioCue: 'destructive', onSelect: doClose });
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
        _inventoryMux.closeSession();
        _mux.closeSession();
        dismissDialog();
        _cartController.closeSettlement();
        hideTooltip();
        if (_tooltipScope) { _tooltipScope.dispose(); _tooltipScope = null; }
        _panelInstanceId = '';
        _procurementNavigation.cleanup();
        _protocolCheckoutPreview = null;
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
                inventoryRequestMux:_inventoryMux.debugState(),
                write: _writeCoordinator.debugState(),
                inventory: _inventoryCoordinator.debugState(),
                drag: _dragController ? _dragController.debugState() : null,
                selectedCatalogIdx: _selectedCatalogIdx,
                shopReady: _shopReady,
                cartCount: _cart.length,
                purchasedCount: _purchased.length,
                panelInstanceId:_panelInstanceId,
                settling: cartDebug.settling,
                previewBusy: cartDebug.previewBusy,
                hasCheckoutPreview: cartDebug.hasCheckoutPreview,
                settlement: cartDebug.settlement
            };
        }
    };
})();
