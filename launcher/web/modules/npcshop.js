/** NPC 金币商店 — 主页面选择待购/待售，二级页面执行权威原子结算。 */
var NpcShop = (function() {
    'use strict';

    var _shellEl, _shell, _catalogView, _catalogRenderer, _categoryToolbar, _categoryNavigator, _categoryTree;
    var _rightViews = {}, _viewButtons = {}, _activeRight = 'bag', _activeCollection = 'material';
    var _state = null, _shopId = '', _busy = false, _needsReconcile = false, _generation = 0;
    var _scaleHandle = null, _retryButton, _checkoutButton, _helpButton, _category = {mode:'auto', path:[]}, _categoryInitialized = false;
    var _purchaseIntents = {}, _saleIntents = {}, _settlement = null, _settlementPage = null;
    var _previewBusy = false, _previewQueued = false, _previewRevision = 0;
    var _tooltipCache = {};
    var _layoutMode = 'full', _densityController = null;
    var _spacePage = null, _spaceGrids = {}, _spacePager = null, _spaceBusy = false, _spaceMutated = false;
    var _helpPage = null, _bagFilterControl = null;
    var _config = (typeof window !== 'undefined' && window.__NPCSHOP_CONFIG__) || {};
    var _mux = new NpcShopRuntime.RequestMux({
        send:function(message) { Bridge.send(message); },
        timeoutMs:_config.requestTimeoutMs,
        sessionNonce:_config.sessionNonce
    });
    var _inventoryMux = new NpcShopRuntime.RequestMux({
        send:function(message) { Bridge.send(message); },
        timeoutMs:_config.requestTimeoutMs,
        sessionNonce:_config.sessionNonce,
        domain:'inventory', panel:'npcshop', callPrefix:'npc-inv'
    });
    var _inventoryState = {opened:false, ready:false, busyOwner:null, refreshRequired:false};
    var _inventoryCoordinator = new InventoryRuntime.InventoryCoordinator({
        request:requestInventory,
        requests:[
            {containerId:'背包', offset:0, limit:50, filterKey:'all'},
            {containerId:'战备箱', offset:0, limit:40, filterKey:'all'}
        ],
        onStateChange:function(state) {
            _inventoryState = state;
            renderOwnedViews();
            renderSpaceOrganizer();
            refreshControls();
        }
    });

    Panels.register('npcshop', {
        create:createDOM,
        onOpen:onOpen,
        onClose:cleanup,
        onRequestClose:requestClose,
        onForceClose:function() { cleanup(); toast('连接断开，NPC 商店已关闭'); }
    });

    function createDOM() {
        _shellEl = document.createElement('div');
        _shellEl.className = 'panel-scale-shell npcshop-scale-shell';
        return _shellEl;
    }

    function buildDOM() {
        while (_shellEl.firstChild) _shellEl.removeChild(_shellEl.firstChild);
        if (_shell) _shell.destroy();
        _rightViews = {}; _viewButtons = {};
        _shell = new Workbench.DualPaneShell({title:_shopId, status:'同步中', leftLabel:'商品', rightLabel:'背包'});
        var root = _shell.getRoot();
        root.classList.add('kshop-workbench', 'npcshop-panel');
        root.setAttribute('data-workbench-skin', 'npcshop');
        _shellEl.appendChild(root);

        [['bag','背包'], ['collection','收集品']].forEach(function(pair) {
            var button = document.createElement('button');
            button.type = 'button'; button.className = 'workbench-mode-btn npcshop-view-btn'; button.textContent = pair[1];
            button.setAttribute('data-view-id', pair[0]);
            button.addEventListener('click', function() { switchRightGroup(pair[0]); });
            _viewButtons[pair[0]] = button; _shell.addHeaderAction(button);
        });

        if (_densityController) _densityController.destroy();
        _densityController = new Workbench.GridDensityController({panelId:'npcshop'});
        _layoutMode = _densityController.mode;
        var layoutToggle = _densityController.createToggle(function(mode) { _layoutMode = mode; });
        _shell.addHeaderAction(layoutToggle);

        _helpButton = document.createElement('button');
        _helpButton.type = 'button'; _helpButton.className = 'workbench-mode-btn npcshop-help-btn'; _helpButton.textContent = '？';
        _helpButton.setAttribute('aria-label', '商店操作帮助');
        _helpButton.addEventListener('click', openHelpPage); _shell.addHeaderAction(_helpButton);

        _checkoutButton = document.createElement('button');
        _checkoutButton.type = 'button'; _checkoutButton.className = 'workbench-mode-btn npcshop-checkout-btn';
        _checkoutButton.addEventListener('click', openSettlement);
        _shell.addHeaderAction(_checkoutButton);

        _retryButton = document.createElement('button');
        _retryButton.type = 'button'; _retryButton.className = 'workbench-mode-btn warning'; _retryButton.textContent = '重新同步';
        _retryButton.addEventListener('click', refreshSnapshot); _shell.addHeaderAction(_retryButton);

        var close = document.createElement('button');
        close.type = 'button'; close.className = 'workbench-close-btn'; close.textContent = '×'; close.setAttribute('aria-label', '关闭 NPC 商店');
        close.addEventListener('click', requestClose); _shell.addHeaderAction(close);

        _catalogView = createCatalogView();
        _rightViews.bag = createOwnedView({viewId:'bag', title:'背包', canSell:true, layoutMode:_layoutMode});
        _rightViews.material = createOwnedView({viewId:'material', title:'材料', canSell:true, layoutMode:_layoutMode});
        _rightViews.intelligence = createOwnedView({viewId:'intelligence', title:'情报', canSell:false, layoutMode:_layoutMode});
        _shell.setDefault('L', _catalogView); _shell.setDefault('R', _rightViews.bag);
        _shell.mountInitial(_catalogView, _rightViews.bag);

        switchRightView(_activeRight); refreshControls();
    }

    function createCatalogView() {
        var root = document.createElement('div'); root.className = 'workbench-view npcshop-catalog-view';
        var chrome = new Workbench.ViewChrome({title:'商品目录', meta:'同步中'});
        _categoryNavigator = new ItemFilter.FilterNavigator({
            className:'npcshop-category-tabs item-filter-navigator',
            ariaLabel:'商店商品分类',
            presentation:'drilldown',
            onChange:function(path) {
                var mode = _categoryToolbar && _categoryToolbar.getAttribute('data-filter-mode');
                _category = {mode:mode || 'auto', path:path};
                decorateCategoryButtons(mode || 'auto');
                if (_catalogRenderer && _catalogRenderer.root) _catalogRenderer.root.scrollTop = 0;
                renderCatalog();
            }
        });
        _categoryToolbar = _categoryNavigator.root;
        chrome.setToolbar(_categoryToolbar);
        _catalogRenderer = new Workbench.GridRenderer({
            className:'npcshop-catalog-grid', emptyText:'当前分组暂无商品',
            keyOf:function(item) { return item.catalogIndex; }, renderItem:renderCatalogCard, bindItem:bindCatalogCard
        });
        if (_densityController) _densityController.register(_catalogRenderer);
        root.appendChild(chrome.root); root.appendChild(_catalogRenderer.root);
        return {
            instanceKey:'npcshop:catalog', instancePolicy:'singletonByBinding', allowedSlots:['L'], viewKind:'catalog',
            root:root, chrome:chrome,
            mount:function(container) { container.appendChild(root); },
            unmount:function() { if (root.parentNode) root.parentNode.removeChild(root); },
            render:renderCatalog
        };
    }

    function createOwnedView(options) {
        options = options || {};
        var viewId = options.viewId;
        var title = options.title;
        var canSell = options.canSell;
        var ownedShell = new InventoryUI.OwnedInventoryViewShell({
            containerId:viewId,
            instanceKey:'npcshop:' + viewId,
            itemModel:'owned',
            getItems:function() { var view = getView(viewId); return view && view.slots ? view.slots : []; },
            keyOf:function(slot) { return viewId === 'bag' ? slot.physicalSlot : slot.collectionKey; },
            renderItem:function(slot) {
                var node = InventoryUI.renderOwnedSlot(viewId === 'bag' ? '背包' : title, slot, {iconHtml:iconHtml, allowDiscard:false});
                if (!slot.occupied) return node;
                node.classList.add('npcshop-owned-card');
                if (canSell) {
                    var identity = saleIdentity(viewId, slot);
                    var selected = !!_saleIntents[identity];
                    node.classList.toggle('selected', selected);
                    node.classList.toggle('item-card-selected', selected);
                    node.setAttribute('aria-pressed', selected ? 'true' : 'false');
                    var marker = document.createElement('span');
                    marker.className = 'item-card-auxiliary item-card-selection-marker npcshop-selection-marker';
                    marker.textContent = selected ? '待售 ×' + _saleIntents[identity].quantity : '点击加入待售';
                    node.appendChild(marker);
                    node.addEventListener('click', function(event) {
                        if (event.button && event.button !== 0) return;
                        toggleSale(viewId, slot);
                    });
                } else {
                    node.classList.add('read-only');
                }
                return node;
            },
            bindItem:function(node, slot) { bindOwnedTooltip(node, viewId, slot); },
            title:title,
            meta:'同步中',
            emptyText:'暂无' + title,
            className:'npcshop-owned-view npcshop-' + viewId + '-view',
            gridClassName:'npcshop-owned-grid',
            allowedSlots:['R'],
            layoutMode: options.layoutMode || 'full',
            densityController: _densityController
        });
        ownedShell.view.viewId = viewId;
        if (viewId === 'bag') installBagToolbar(ownedShell.view); else installCollectionToolbar(ownedShell.view);
        return ownedShell.view;
    }

    function installBagToolbar(view) {
        var toolbar = document.createElement('div'); toolbar.className = 'npcshop-bag-toolbar';
        var hint = document.createElement('span'); hint.className = 'npcshop-selection-hint';
        hint.textContent = '点击加入待售，不会立即出售；数量在结算页调整';
        view.chrome.title.appendChild(hint);
        _bagFilterControl = new InventoryUI.InventoryFilterControl({
            options:InventoryUI.categoryFilterOptions(),
            ariaLabel:'商店背包分类筛选',
            navigatorPresentation:'drilldown',
            onLegacyChange:changeBagFilterLegacy,
            onSpecChange:changeBagFilterSpec
        });
        toolbar.appendChild(_bagFilterControl.root);
        view.inventoryFilterControl = _bagFilterControl;
        if (view.ownedInventoryShell) view.ownedInventoryShell.setToolbar(toolbar); else view.chrome.setToolbar(toolbar);
    }

    function changeBagFilterLegacy(filterKey) {
        var snapshot = _inventoryCoordinator.getWindow('背包');
        if (!_inventoryCoordinator.setFilter('背包', filterKey, function(result) {
            if (!result || !result.success) {
                if (_bagFilterControl) _bagFilterControl.rejectPending(snapshot);
                toast('背包分类筛选失败。');
            }
            renderOwnedViews(); refreshControls();
        })) {
            if (_bagFilterControl) _bagFilterControl.setSnapshot(snapshot);
        }
    }

    function changeBagFilterSpec(filterSpec) {
        var snapshot = _inventoryCoordinator.getWindow('背包');
        if (!_inventoryCoordinator.setFilterSpec('背包', filterSpec, function(result) {
            if (!result || !result.success) {
                if (_bagFilterControl) _bagFilterControl.rejectPending(snapshot);
                toast('背包分类筛选失败。');
            }
            renderOwnedViews(); refreshControls();
        })) {
            if (_bagFilterControl) _bagFilterControl.setSnapshot(snapshot);
        }
    }

    function installCollectionToolbar(view) {
        var toolbar = document.createElement('div'); toolbar.className = 'npcshop-collection-tabs';
        [['material','材料'], ['intelligence','情报']].forEach(function(pair) {
            var button = document.createElement('button'); button.type = 'button'; button.className = 'workbench-mode-btn npcshop-collection-btn';
            button.textContent = pair[1]; button.setAttribute('data-collection-view', pair[0]);
            button.addEventListener('click', function() { switchRightView(pair[0]); }); toolbar.appendChild(button);
        });
        if (view.ownedInventoryShell) view.ownedInventoryShell.setToolbar(toolbar); else view.chrome.setToolbar(toolbar);
    }

    function renderCatalogCard(item) {
        var selected = !!_purchaseIntents[String(item.catalogIndex)];
        var markerText = item.locked ? '未解锁' : (selected ? '待购 ×' + _purchaseIntents[String(item.catalogIndex)].quantity : '点击加入待购');
        var lockTitle = item.requiredInfo ? '需要情报：' + item.requiredInfo : '尚未解锁';
        return Workbench.ItemCard.renderCatalog({
            skin: 'npcshop',
            item: item,
            id: item.catalogIndex,
            iconHtml: iconHtml(item.icon || item.itemName, 'kshop-icon'),
            name: item.displayName || item.itemName,
            meta: ItemFilter.catalogPath(item).map(function(part) { return part.label; }).join(' · '),
            priceText: '$ ' + Number(item.unitPrice || 0).toLocaleString(),
            locked: item.locked,
            lockTitle: lockTitle,
            selected: selected,
            markerText: markerText
        });
    }

    function togglePurchase(item) {
        if (_busy || _needsReconcile || !item || item.locked) return;
        var key = String(item.catalogIndex);
        if (_purchaseIntents[key]) delete _purchaseIntents[key];
        else _purchaseIntents[key] = {catalogIndex:Number(item.catalogIndex), quantity:1, maxQuantity:Number(item.maxQuantity) || 1, item:item};
        renderCatalog(); refreshControls();
    }

    function saleIdentity(viewId, slot) {
        return viewId === 'bag' ? 'bag:' + Number(slot.physicalSlot) : 'material:' + String(slot.collectionKey);
    }

    function toggleSale(viewId, slot) {
        if (_busy || _needsReconcile || !slot || !slot.occupied || viewId === 'intelligence') return;
        var identity = saleIdentity(viewId, slot);
        if (_saleIntents[identity]) delete _saleIntents[identity];
        else {
            var max = Math.max(1, Math.floor(Number(slot.item && slot.item.quantity) || 1));
            _saleIntents[identity] = {
                identity:identity, quantity:max, maxQuantity:max, scope:'slot', item:slot.item || {},
                source:viewId === 'bag'
                    ? {containerId:'背包', slot:Number(slot.physicalSlot), expectedLease:String(slot.slotLease)}
                    : {viewId:'material', key:String(slot.collectionKey), expectedLease:String(slot.slotLease)}
            };
        }
        renderOwnedViews(); refreshControls();
    }

    function renderCategoryToolbar() {
        if (!_categoryNavigator) return;
        var sections = _state && _state.layout && Array.isArray(_state.layout.sections) ? _state.layout.sections : [];
        var catalog = _state && _state.catalog ? _state.catalog : [];
        if (sections.length) {
            var automaticTree = ItemFilter.build(catalog, function(item) { return ItemFilter.catalogPath(item); });
            var curatedTree = ItemFilter.manualSections(sections, catalog.length);
            _categoryTree = ItemFilter.branchTree([
                {id:'category', label:'类别', tree:automaticTree},
                {id:'curated', label:'专柜', tree:curatedTree}
            ], catalog.length);
            var currentPath = _category && _category.mode === 'combined' ? (_category.path || []) : [];
            var valid = ItemFilter.validPath(_categoryTree, currentPath);
            if (!_categoryInitialized || !valid) {
                var configured = String((_state.layout && _state.layout.defaultSection) || '');
                var hasConfigured = sections.some(function(section) { return String(section.id) === configured; });
                _category = {mode:'combined', path:hasConfigured ? ['curated', configured] : []};
            } else {
                _category = {mode:'combined', path:valid};
            }
            _categoryToolbar.setAttribute('data-filter-mode', 'combined');
            _categoryNavigator.setModel(_categoryTree, _category.path);
            decorateCategoryButtons('combined');
        } else {
            if (!_categoryInitialized || !_category || _category.mode !== 'auto') _category = {mode:'auto', path:[]};
            _categoryTree = ItemFilter.build(catalog, function(item) { return ItemFilter.catalogPath(item); });
            _category.path = ItemFilter.validPath(_categoryTree, _category.path || []);
            _categoryToolbar.setAttribute('data-filter-mode', 'auto');
            _categoryNavigator.setModel(_categoryTree, _category.path);
            decorateCategoryButtons('auto');
        }
        _categoryInitialized = true;
    }

    function decorateCategoryButtons(mode) {
        var buttons = _categoryToolbar.querySelectorAll('[data-filter-path]');
        for (var i = 0; i < buttons.length; i++) {
            var path = String(buttons[i].getAttribute('data-filter-path') || '').split('/').filter(Boolean);
            var labels = [], node = _categoryTree;
            for (var depth = 0; depth < path.length; depth++) {
                node = ItemFilter.nodeAt(node, [path[depth]]);
                if (!node) break;
                labels.push(node.label);
            }
            var legacyPath = mode === 'auto' ? labels : path;
            buttons[i].setAttribute('data-category', mode + ':' + (legacyPath.length ? legacyPath.join(':') : 'all'));
        }
    }

    function renderCatalog() {
        if (!_catalogRenderer) return;
        var catalog = _state && _state.catalog ? _state.catalog : [];
        var filtered = catalog.filter(matchesCategory); _catalogRenderer.render(filtered);
        if (_catalogView) _catalogView.chrome.setMeta(_state ? filtered.length + ' / ' + catalog.length + ' 件商品' : '同步中');
    }

    function matchesCategory(item) {
        var sections = _state && _state.layout && Array.isArray(_state.layout.sections) ? _state.layout.sections : [];
        if (sections.length) {
            var browsePath = _category && _category.mode === 'combined' ? (_category.path || []) : [];
            if (!browsePath.length || browsePath.length === 1) return true;
            if (browsePath[0] === 'category') {
                return ItemFilter.matchesPath(item, browsePath.slice(1), function(entry) { return ItemFilter.catalogPath(entry); });
            }
            if (browsePath[0] === 'curated') {
                for (var i = 0; i < sections.length; i++) {
                    if (String(sections[i].id) === String(browsePath[1])) {
                        return (sections[i].entries || []).indexOf(Number(item.catalogIndex)) >= 0;
                    }
                }
            }
            return false;
        }
        var selected = _category && _category.mode === 'auto' ? (_category.path || []) : [];
        return ItemFilter.matchesPath(item, selected, function(entry) { return ItemFilter.catalogPath(entry); });
    }

    function renderOwnedViews() {
        for (var key in _rightViews) {
            var view = _rightViews[key]; if (!view) continue; view.render();
            var data = getView(key); var occupied = data && data.slots ? data.slots.filter(function(slot) { return slot.occupied; }).length : 0;
            if (key === 'bag' && view.inventoryFilterControl) view.inventoryFilterControl.setSnapshot(data);
            var total = data && data.filterItemCount != null ? Number(data.filterItemCount) : occupied;
            view.chrome.setMeta(_state ? (occupied === total ? occupied : occupied + ' / ' + total) + ' 项' : '同步中');
        }
    }

    function selectionPayload() {
        var purchases = [], sales = [];
        Object.keys(_purchaseIntents).sort(function(a,b) { return Number(a)-Number(b); }).forEach(function(key) {
            var line = _purchaseIntents[key]; purchases.push({catalogIndex:line.catalogIndex, quantity:line.quantity});
        });
        Object.keys(_saleIntents).sort().forEach(function(key) {
            var line = _saleIntents[key];
            if (line.scope === 'same_name') sales.push({source:line.source, scope:'same_name', policy:'plain_only'});
            else sales.push({source:line.source, quantity:line.quantity, scope:'slot'});
        });
        return {shopId:_shopId, purchases:purchases, sales:sales};
    }

    function selectionCount() { return Object.keys(_purchaseIntents).length + Object.keys(_saleIntents).length; }

    function openSettlement() {
        if (!selectionCount() || _busy || _needsReconcile) return;
        if (!_settlementPage) createSettlementPage();
        _settlementPage.classList.add('active'); _shell.getRoot().classList.add('npcshop-settling');
        showGuideOnce('settlement', '这里仍是交易清单：调整完成并点击“确认交易”后，买卖才会一次生效。');
        _settlement = null; requestTradePreview();
    }

    function closeSettlement() {
        if (_settlementPage) _settlementPage.classList.remove('active');
        if (_shell) _shell.getRoot().classList.remove('npcshop-settling');
        _settlement = null; _previewQueued = false; renderCatalog(); renderOwnedViews(); refreshControls();
    }

    function createSettlementPage() {
        _settlementPage = document.createElement('section');
        _settlementPage.className = 'workbench-secondary-page npcshop-settlement-page';
        _settlementPage.innerHTML = '<header class="npcshop-settlement-header"><button type="button" data-trade-back>← 返回选购</button>'
            + '<div><h2>交易结算</h2><p data-trade-context>价格与容量由游戏实时核算；确认后整单一次生效。</p></div></header>'
            + '<div class="npcshop-settlement-columns"><section><h3>待购</h3><div class="npcshop-settlement-list" data-purchase-lines></div></section>'
            + '<section><h3>待售</h3><div class="npcshop-settlement-list" data-sale-lines></div></section></div>'
            + '<footer class="npcshop-settlement-summary"><div data-trade-economy></div><span data-trade-error></span>'
            + '<button type="button" data-space-organize hidden>整理空间</button>'
            + '<button type="button" data-trade-commit>确认交易</button></footer>';
        _settlementPage.querySelector('[data-trade-back]').addEventListener('click', closeSettlement);
        _settlementPage.querySelector('[data-space-organize]').addEventListener('click', openSpaceOrganizer);
        _settlementPage.querySelector('[data-trade-commit]').addEventListener('click', commitTrade);
        _shell.getRoot().appendChild(_settlementPage);
    }

    function requestTradePreview() {
        if (!_settlementPage || !_settlementPage.classList.contains('active')) return;
        if (!selectionCount()) { closeSettlement(); return; }
        if (_previewBusy) { _previewQueued = true; return; }
        _previewBusy = true; _previewQueued = false; _previewRevision++;
        var revision = _previewRevision; renderSettlementLoading();
        var payload = selectionPayload();
        var issued = request('tradePreview', payload, function(response) {
            _previewBusy = false;
            if (revision !== _previewRevision || !_settlementPage || !_settlementPage.classList.contains('active')) return;
            if (!response.success) {
                if (response.error === 'stale_state' || response.error === 'reconcile_required'
                        || response.error === 'timeout' || response.error === 'client_timeout' || response.error === 'disconnected') {
                    handleWriteError(response);
                } else {
                    handleError(response); renderSettlementFailure(response.error);
                }
                return;
            }
            _settlement = response; renderSettlement();
            if (_previewQueued) requestTradePreview();
        });
        if (!issued) { _previewBusy = false; renderSettlementLoading(); }
    }

    function renderSettlementLoading() {
        if (!_settlementPage) return;
        var commit = _settlementPage.querySelector('[data-trade-commit]'); commit.disabled = true; commit.textContent = '核算中…';
    }

    function renderSettlementFailure(errorCode) {
        if (!_settlementPage) return;
        var error = _settlementPage.querySelector('[data-trade-error]');
        error.textContent = errorMessage(errorCode); error.classList.add('error');
        var commit = _settlementPage.querySelector('[data-trade-commit]'); commit.disabled = true; commit.textContent = '无法结算';
    }

    function renderSettlement() {
        if (!_settlementPage || !_settlement) return;
        renderSettlementLines('purchase', _settlement.purchaseLines || []);
        renderSettlementLines('sale', _settlement.saleLines || []);
        var economy = _settlementPage.querySelector('[data-trade-economy]');
        economy.innerHTML = '<b>购买 -$' + Number(_settlement.buyTotal || 0).toLocaleString() + '</b>'
            + '<b>出售 +$' + Number(_settlement.sellTotal || 0).toLocaleString() + '</b>'
            + '<strong>结余 $' + Number(_settlement.projectedBalance || 0).toLocaleString() + '</strong>'
            + '<small>需 ' + Number(_settlement.requiredSlots || 0) + ' 格 / 可用 ' + Number(_settlement.availableSlots || 0) + ' 格</small>';
        var error = _settlementPage.querySelector('[data-trade-error]');
        error.textContent = _settlement.blockingError ? errorMessage(_settlement.blockingError) : '整单可提交';
        error.classList.toggle('error', !!_settlement.blockingError);
        var organize = _settlementPage.querySelector('[data-space-organize]');
        organize.hidden = _settlement.blockingError !== 'inventory_full';
        organize.disabled = _busy || _previewBusy || _spaceBusy;
        var context = _settlementPage.querySelector('[data-trade-context]');
        if (_settlement.blockingError === 'inventory_full') {
            context.textContent = '背包空间不足：可先整理背包与战备箱，返回后订单会自动重新核算。';
            showGuideOnce('inventory_full', '背包不足时可点“整理空间”；返回结算后，系统会重新核算数量与空位。');
        } else if ((_settlement.saleLines || []).some(function(line) { return line.scope === 'same_name'; })) {
            context.textContent = '同名全售只出售普通实例，强化、进阶和带插件装备会自动保护。';
        } else {
            context.textContent = '待购和待售都只是清单；点击“确认交易”后整单才会一次生效。';
        }
        var commit = _settlementPage.querySelector('[data-trade-commit]');
        commit.disabled = _busy || _previewBusy || !_settlement.canCommit; commit.textContent = '确认交易';
    }

    function renderSettlementLines(kind, lines) {
        var list = _settlementPage.querySelector(kind === 'purchase' ? '[data-purchase-lines]' : '[data-sale-lines]');
        while (list.firstChild) list.removeChild(list.firstChild);
        if (!lines.length) { var empty = document.createElement('p'); empty.className = 'npcshop-settlement-empty'; empty.textContent = '无'; list.appendChild(empty); return; }
        lines.forEach(function(line) {
            var identity = kind === 'purchase' ? String(line.catalogIndex) : String(line.sourceIdentity);
            var intent = kind === 'purchase' ? _purchaseIntents[identity] : _saleIntents[identity]; if (!intent) return;
            if (kind === 'purchase') {
                intent.purchaseLimit = Number(line.purchaseLimit || intent.maxQuantity || 1);
                intent.maxPurchasable = Math.max(0, Number(line.maxPurchasable || 0));
            }
            var row = document.createElement('article'); row.className = 'npcshop-settlement-line';
            var icon = document.createElement('span'); icon.className = 'npcshop-card-icon'; icon.innerHTML = iconHtml(line.icon || line.itemName, 'kshop-icon');
            var copy = document.createElement('span'); copy.className = 'npcshop-settlement-copy';
            var name = document.createElement('b'); name.textContent = line.displayName || line.itemName;
            var total = document.createElement('small'); total.textContent = (kind === 'purchase' ? '-$' : '+$') + Number(line.total || 0).toLocaleString();
            copy.appendChild(name); copy.appendChild(total);
            if (kind === 'purchase') {
                var bound = document.createElement('em');
                bound.textContent = '当前最多可购 ' + intent.maxPurchasable + ' / 单笔上限 ' + intent.purchaseLimit;
                copy.appendChild(bound);
            } else if (line.scope === 'same_name') {
                var bulk = document.createElement('em');
                bulk.textContent = '同名匹配 ' + Number(line.matchedCount || 0) + ' 格，售出 ' + Number(line.eligibleCount || 0)
                    + ' 格，保护 ' + Number(line.protectedCount || 0) + ' 格';
                copy.appendChild(bulk);
            }
            var stepper = document.createElement('span'); stepper.className = 'npcshop-stepper';
            var remove = stepButton('×', function() { removeIntent(kind, identity); }); remove.classList.add('remove');
            if (kind === 'purchase') {
                var minus = stepButton('−', function() { adjustIntent(kind, identity, -1); });
                var quantity = document.createElement('b'); quantity.textContent = String(intent.quantity);
                var plus = stepButton('+', function() { adjustIntent(kind, identity, 1); });
                var plusFive = stepButton('+5', function() { adjustIntent(kind, identity, 5); }); plusFive.classList.add('wide');
                var max = stepButton('最大', function() { setPurchaseMax(identity); }); max.classList.add('wide');
                minus.disabled = intent.quantity <= 1;
                plus.disabled = intent.quantity >= intent.purchaseLimit;
                plusFive.disabled = intent.quantity >= intent.purchaseLimit;
                max.disabled = intent.maxPurchasable < 1 || intent.quantity === intent.maxPurchasable;
                stepper.appendChild(minus); stepper.appendChild(quantity); stepper.appendChild(plus);
                stepper.appendChild(plusFive); stepper.appendChild(max); stepper.appendChild(remove);
            } else if (line.scope === 'same_name') {
                var single = stepButton('只售此格', function() { setBulkSale(identity, false); }); single.classList.add('wide');
                stepper.appendChild(single); stepper.appendChild(remove);
            } else {
                var saleMinus = stepButton('−', function() { adjustIntent(kind, identity, -1); });
                var saleQuantity = document.createElement('b'); saleQuantity.textContent = String(intent.quantity);
                var salePlus = stepButton('+', function() { adjustIntent(kind, identity, 1); });
                saleMinus.disabled = intent.quantity <= 1; salePlus.disabled = intent.quantity >= intent.maxQuantity;
                stepper.appendChild(saleMinus); stepper.appendChild(saleQuantity); stepper.appendChild(salePlus);
                if (line.itemKind === 'equipment') {
                    var all = stepButton('同名全售', function() { setBulkSale(identity, true); }); all.classList.add('wide');
                    stepper.appendChild(all);
                }
                stepper.appendChild(remove);
            }
            row.appendChild(icon); row.appendChild(copy); row.appendChild(stepper); list.appendChild(row);
        });
    }

    function stepButton(label, handler) { var button = document.createElement('button'); button.type = 'button'; button.textContent = label; button.addEventListener('click', handler); return button; }

    function adjustIntent(kind, identity, delta) {
        var map = kind === 'purchase' ? _purchaseIntents : _saleIntents; var line = map[identity]; if (!line || _previewBusy) return;
        var limit = kind === 'purchase' ? Number(line.purchaseLimit || line.maxQuantity) : line.maxQuantity;
        line.quantity = Math.max(1, Math.min(limit, line.quantity + delta)); requestTradePreview();
    }

    function setPurchaseMax(identity) {
        var line = _purchaseIntents[identity];
        if (!line || _previewBusy || Number(line.maxPurchasable) < 1) return;
        line.quantity = Number(line.maxPurchasable); requestTradePreview();
    }

    function setBulkSale(identity, enabled) {
        var line = _saleIntents[identity];
        if (!line || _previewBusy || !line.source || line.source.containerId !== '背包') return;
        line.scope = enabled ? 'same_name' : 'slot';
        if (enabled) showGuideOnce('bulk_sale', '同名全售会扫描整个背包，并自动保护强化、进阶和带插件的装备。');
        requestTradePreview();
    }

    function openHelpPage() {
        if (_busy || _inventoryState.busyOwner) return;
        if (!_helpPage) createHelpPage();
        var back = _helpPage.querySelector('[data-help-back]');
        back.textContent = _settlementPage && _settlementPage.classList.contains('active') ? '← 返回结算' : '← 返回商店';
        _helpPage.classList.add('active');
        _shell.getRoot().classList.add('npcshop-helping');
        refreshControls();
        back.focus();
    }

    function closeHelpPage() {
        if (_helpPage) _helpPage.classList.remove('active');
        if (_shell) _shell.getRoot().classList.remove('npcshop-helping');
        refreshControls();
        if (_helpButton) _helpButton.focus();
    }

    function createHelpPage() {
        _helpPage = document.createElement('section');
        _helpPage.className = 'workbench-secondary-page npcshop-help-page';
        _helpPage.setAttribute('role', 'dialog');
        _helpPage.setAttribute('aria-label', 'NPC 商店操作帮助');
        _helpPage.innerHTML = '<header class="npcshop-help-header"><button type="button" data-help-back>← 返回商店</button>'
            + '<div><h2>商店操作帮助</h2><p>所有选择都可以在确认交易前调整或取消。</p></div></header>'
            + '<div class="npcshop-help-grid">'
            + helpCard('01','选择商品','左侧点击商品加入待购；右侧点击背包或材料加入待售。','此时不会扣钱，也不会移除物品。','待购','待售')
            + helpCard('02','调整并结算','在结算页用 −、+、+5 或“最大”调整数量，再确认整张订单。','“最多可购”由金币、背包容量和商店限制共同决定。','调整数量','确认交易')
            + helpCard('03','同名全售','装备待售行可切换为“同名全售”，快速清理重复装备。','只出售普通实例；强化、进阶和带插件装备自动保护。','同名匹配','保护特殊装备')
            + helpCard('04','整理空间','背包不足时进入背包—战备箱整理页，点击物品即可快速转移。','返回后订单自动重算；商品不会直接购买到战备箱。','整理空间','返回重算')
            + '</div><footer class="npcshop-help-rules"><b>记住三件事</b><span>选择 ≠ 交易</span><span>最大数量会动态变化</span><span>移动后的待售项可能被安全移除</span>'
            + '<small>关键提示只自动出现一次；本页可随时从标题栏“？”重新打开。</small></footer>';
        _helpPage.querySelector('[data-help-back]').addEventListener('click', closeHelpPage);
        _shell.getRoot().appendChild(_helpPage);
    }

    function helpCard(index, title, body, detail, chipA, chipB) {
        return '<article class="npcshop-help-card"><span class="npcshop-help-index">' + index + '</span><div><h3>' + title + '</h3><p>' + body
            + '</p><small>' + detail + '</small><div class="npcshop-help-flow"><i>' + chipA + '</i><b>→</b><i>' + chipB + '</i></div></div></article>';
    }

    function showGuideOnce(topic, message) {
        var key = 'cf7.npcshop.guide.v1.' + topic;
        try {
            if (window.localStorage && window.localStorage.getItem(key) === '1') return false;
            if (window.localStorage) window.localStorage.setItem(key, '1');
        } catch (error) {}
        toast(message); return true;
    }

    function openSpaceOrganizer() {
        if (!_settlement || _settlement.blockingError !== 'inventory_full' || _busy || _previewBusy) return;
        if (!_spacePage) createSpaceOrganizer();
        _spacePage.classList.add('active');
        _settlementPage.classList.add('organizing-space');
        _spaceBusy = true; _spaceMutated = false; refreshControls();
        if (_inventoryState.opened && _inventoryState.ready && !_inventoryState.refreshRequired) {
            _spaceBusy = false; renderSpaceOrganizer(); refreshControls();
        } else refreshInventory(function(result) {
            _spaceBusy = false; renderSpaceOrganizer(); refreshControls();
            if (!result.success) toast('库存同步失败，暂时无法整理空间。');
        });
    }

    function createSpaceOrganizer() {
        _spacePage = document.createElement('section');
        _spacePage.className = 'npcshop-space-page';
        _spacePage.innerHTML = '<header class="npcshop-space-header"><button type="button" data-space-back>← 返回结算</button>'
            + '<div><h2>整理购买空间</h2><p>点击物品即可在背包与战备箱之间快速转移；返回后交易会重新核算。</p></div>'
            + '<span data-space-status>同步中</span></header>'
            + '<div class="npcshop-space-columns"><section><h3>背包 <small data-space-meta="背包"></small></h3><div class="npcshop-space-grid" data-space-grid="背包"></div></section>'
            + '<section><h3>战备箱 <span data-space-pager></span><small data-space-meta="战备箱"></small></h3><div class="npcshop-space-grid battlebox" data-space-grid="战备箱"></div></section></div>';
        _spacePage.querySelector('[data-space-back]').addEventListener('click', closeSpaceOrganizer);
        _spaceGrids = {
            '背包':_spacePage.querySelector('[data-space-grid="背包"]'),
            '战备箱':_spacePage.querySelector('[data-space-grid="战备箱"]')
        };
        if (_densityController) {
            _densityController.register(_spaceGrids['背包']);
            _densityController.register(_spaceGrids['战备箱']);
        }
        _spacePager = new InventoryUI.InventoryWindowPager({
            containerId:'战备箱', containerLabel:'战备箱', columns:5,
            defaultOffset:0, defaultLimit:40, defaultCapacity:0,
            getSnapshot:function() { return _inventoryCoordinator.getWindow('战备箱'); },
            getRequest:function() { return _inventoryCoordinator.getRequest('战备箱'); },
            shortcutEnabled:function() { return !!(_spacePage && _spacePage.classList.contains('active')); },
            onRequest:function(offset, limit, callback) { return _inventoryCoordinator.setWindow('战备箱', offset, limit, callback); },
            onResult:function(result) { renderSpaceOrganizer(); if (!result.success) toast('战备箱翻页失败。'); }
        });
        _spacePage.querySelector('[data-space-pager]').appendChild(_spacePager.root);
        _spacePager.attach();
        _settlementPage.appendChild(_spacePage);
    }

    function renderSpaceOrganizer() {
        if (!_spacePage || !_spacePage.classList.contains('active')) return;
        renderSpaceGrid('背包'); renderSpaceGrid('战备箱');
        if (_spacePager) { _spacePager.setDisabled(!_inventoryState.ready || !!_inventoryState.busyOwner); _spacePager.refresh(); }
        var status = _spacePage.querySelector('[data-space-status]');
        status.textContent = _inventoryState.refreshRequired ? '同步失败' : _inventoryState.busyOwner ? '转移中…' : _inventoryState.ready ? '点击快速转移' : '同步中…';
    }

    function renderSpaceGrid(containerId) {
        var grid = _spaceGrids[containerId]; if (!grid) return;
        while (grid.firstChild) grid.removeChild(grid.firstChild);
        var snapshot = _inventoryCoordinator.getWindow(containerId);
        var slots = snapshot && snapshot.slots ? snapshot.slots : [];
        for (var i = 0; i < slots.length; i++) {
            var slot = slots[i];
            var node = InventoryUI.renderOwnedSlot(containerId, slot, {iconHtml:iconHtml, allowDiscard:false});
            if (slot.occupied) {
                node.classList.add('npcshop-space-transferable');
                node.title = containerId === '背包' ? '移入战备箱' : '移入背包';
                (function(sourceContainer, sourceSlot) {
                    node.addEventListener('click', function() { transferSpaceItem(sourceContainer, sourceSlot); });
                })(containerId, slot);
            }
            grid.appendChild(node);
        }
        var meta = _spacePage.querySelector('[data-space-meta="' + containerId + '"]');
        if (!snapshot) meta.textContent = '同步中';
        else if (containerId === '战备箱' && Number(snapshot.accessibleCapacity) <= 0) meta.textContent = '未解锁';
        else meta.textContent = slots.filter(function(slot) { return slot.occupied; }).length + ' 项';
    }

    function transferSpaceItem(containerId, slot) {
        if (!_inventoryState.ready || _inventoryState.busyOwner || !slot || !slot.occupied) return;
        var source = {
            containerId:containerId,
            slot:Number(slot.physicalSlot),
            expectedLease:String(slot.slotLease),
            occupied:true,
            item:slot.item || null
        };
        var target = containerId === '背包' ? '战备箱' : '背包';
        if (!_inventoryCoordinator.autoTransfer(source, target, function(result) {
            if (result && result.success) {
                _spaceMutated = true;
                rebindSaleIntentsFromViews({bag:_inventoryCoordinator.getWindow('背包')});
            } else toast(errorMessage(result && result.error));
            renderSpaceOrganizer(); refreshControls();
        })) toast('库存正在处理另一项操作。');
        renderSpaceOrganizer(); refreshControls();
    }

    function closeSpaceOrganizer() {
        if (!_spacePage || !_spacePage.classList.contains('active') || _inventoryState.busyOwner) return;
        _spacePage.classList.remove('active');
        _settlementPage.classList.remove('organizing-space');
        _spaceBusy = true; renderSettlementLoading(); refreshControls();
        request('snapshot', {shopId:_shopId}, function(response) {
            _spaceBusy = false;
            if (!response.success) { handleWriteError(response); return; }
            rebindSaleIntentsFromViews(response.views || {});
            applyState(response);
            requestTradePreview();
            if (_spaceMutated) toast('库存已整理，交易数量与容量已重新核算。');
        });
    }

    function rebindSaleIntentsFromViews(views) {
        var bag = views && views.bag;
        var material = views && views.material;
        var next = {}, dropped = 0;
        Object.keys(_saleIntents).forEach(function(oldIdentity) {
            var intent = _saleIntents[oldIdentity], slot = null, identity = oldIdentity;
            if (intent.source && intent.source.containerId === '背包') {
                var slots = bag && bag.slots ? bag.slots : [];
                for (var i = 0; i < slots.length; i++) {
                    if (!slots[i].occupied || String(slots[i].item && slots[i].item.name) !== String(intent.item && intent.item.name)) continue;
                    if ((intent.scope === 'same_name' && isPlainProjectedItem(slots[i].item))
                            || (intent.scope !== 'same_name' && Number(slots[i].physicalSlot) === Number(intent.source.slot))) {
                        slot = slots[i]; break;
                    }
                }
                if (slot) {
                    identity = 'bag:' + Number(slot.physicalSlot);
                    intent.identity = identity;
                    intent.source = {containerId:'背包', slot:Number(slot.physicalSlot), expectedLease:String(slot.slotLease)};
                }
            } else if (!material) {
                slot = {slotLease:intent.source && intent.source.expectedLease};
            } else {
                var materialSlots = material && material.slots ? material.slots : [];
                for (var j = 0; j < materialSlots.length; j++) {
                    if (String(materialSlots[j].collectionKey) === String(intent.source && intent.source.key)) { slot = materialSlots[j]; break; }
                }
                if (slot) intent.source.expectedLease = String(slot.slotLease);
            }
            if (slot && !next[identity]) next[identity] = intent; else dropped++;
        });
        _saleIntents = next;
        if (dropped) toast('有 ' + dropped + ' 项待售物品已移动，已从结算单移除。');
    }

    function isPlainProjectedItem(item) {
        if (!item || item.itemKind !== 'equipment') return true;
        return Number(item.enhancementLevel || 1) <= 1
            && !item.tierSlotUsed && Number(item.modSlotUsed || 0) <= 0;
    }

    function removeIntent(kind, identity) {
        if (_previewBusy) return;
        var map = kind === 'purchase' ? _purchaseIntents : _saleIntents; delete map[identity];
        if (!selectionCount()) closeSettlement(); else requestTradePreview();
    }

    function commitTrade() {
        if (!_settlement || !_settlement.canCommit || _previewBusy) return;
        write('tradeCommit', {shopId:_shopId, expectedTradeToken:String(_settlement.tradeToken)}, function(response) {
            if (!response.success) { handleWriteError(response); return; }
            var trade = response.trade || {}; _purchaseIntents = {}; _saleIntents = {}; closeSettlement();
            applyState(response); refreshInventory();
            toast('交易完成：购买 $' + Number(trade.buyTotal || 0).toLocaleString() + '，出售 $' + Number(trade.sellTotal || 0).toLocaleString());
        });
    }

    function bindCatalogCard(node, item) {
        PanelTooltip.bindAsyncHover(node, {
            cache: _tooltipCache,
            key: 'catalog:' + item.itemName,
            item: item,
            renderBasic: buildTooltipBasic,
            renderRich: buildTooltipRich,
            fetch: function(item, callback) {
                request('tooltip', {itemName: item.itemName}, callback);
            }
        });
        if (!item.locked) {
            node.addEventListener('click', function(event) {
                if (event.button && event.button !== 0) return;
                togglePurchase(item);
            });
        }
    }
    function bindOwnedTooltip(node, viewId, slot) {
        if (!slot || !slot.occupied) return;
        var key = viewId + ':' + String(slot.slotLease || slot.collectionKey);
        var item = slot.item || {};
        var payload = viewId === 'bag'
            ? {source:{containerId:'背包', slot:Number(slot.physicalSlot), expectedLease:String(slot.slotLease)}}
            : {itemName:String(item.name || '')};
        PanelTooltip.bindAsyncHover(node, {
            cache: _tooltipCache,
            key: key,
            item: item,
            renderBasic: buildTooltipBasic,
            renderRich: buildTooltipRich,
            fetch: function(_, callback) {
                request('tooltip', payload, callback);
            }
        });
    }
    function buildTooltipBasic(item) {
        return '<div class="kshop-tt-header"><b>' + escapeHtml(item.displayName || item.itemName || item.name || '物品') + '</b></div><div class="kshop-tt-loading">加载中…</div>';
    }
    function buildTooltipRich(item, rich) {
        return PanelTooltip.buildItemRichHtml({
            iconHtml:PanelTooltip.dynamicIconHtml(item.icon || item.name || item.itemName), iconUrl:PanelTooltip.staticIconUrl(item.icon || item.name || item.itemName),
            introHTML:rich.introHTML || '', descHTML:rich.descHTML || '', rootClass:'npcshop-tooltip', layoutType:PanelTooltip.inferLayoutType(item.majorType || item.use)
        });
    }

    function switchRightGroup(groupId) { switchRightView(groupId === 'collection' ? _activeCollection : 'bag'); }
    function switchRightView(viewId) {
        if (!_rightViews[viewId]) viewId = 'bag'; _activeRight = viewId;
        if (viewId === 'material' || viewId === 'intelligence') _activeCollection = viewId;
        _shell.moveView('R', _rightViews[viewId]);
        var labels = {bag:'背包',material:'材料',intelligence:'情报'}; var groupId = viewId === 'bag' ? 'bag' : 'collection';
        _shell.setSlotLabel('R', groupId === 'bag' ? '背包' : '收集品 · ' + labels[viewId]);
        for (var key in _viewButtons) _viewButtons[key].classList.toggle('active', key === groupId);
        var buttons = _shell.getRoot().querySelectorAll('[data-collection-view]');
        for (var i = 0; i < buttons.length; i++) buttons[i].classList.toggle('active', buttons[i].getAttribute('data-collection-view') === _activeCollection);
    }

    function onOpen(el, initData) {
        _generation++; _shopId = initData && typeof initData.shopId === 'string' ? initData.shopId : '';
        _state = null; _busy = false; _needsReconcile = false; _purchaseIntents = {}; _saleIntents = {}; _settlement = null; _settlementPage = null;
        _spacePage = null; _spaceGrids = {}; _spacePager = null; _spaceBusy = false; _spaceMutated = false;
        _helpPage = null; _helpButton = null; _bagFilterControl = null;
        _previewBusy = false; _previewQueued = false; _previewRevision = 0; _category = {mode:'auto', path:[]}; _categoryInitialized = false;
        _activeRight = 'bag'; _activeCollection = 'material'; _tooltipCache = {};
        buildDOM(); if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = typeof PanelScale !== 'undefined' ? PanelScale.attach(_shellEl, 1024, 576) : null;
        _mux.openSession(); _inventoryMux.openSession();
        _inventoryCoordinator.resetWindow('背包', 0, 50, 'all');
        _inventoryCoordinator.resetWindow('战备箱', 0, 40, 'all');
        refreshSnapshot();
    }

    function refreshSnapshot() {
        if (!_shopId || _busy) return false;
        refreshInventory();
        _shell.setStatus('同步中', 'loading'); var generation = _generation;
        return !!request('snapshot', {shopId:_shopId}, function(response) {
            if (generation !== _generation) return;
            if (response.success) { _needsReconcile = false; _purchaseIntents = {}; _saleIntents = {}; closeSettlement(); applyState(response); }
            else { _needsReconcile = true; handleError(response); refreshControls(); }
        });
    }

    function applyState(response) {
        _state = response; _busy = false; _needsReconcile = false;
        var title = response.layout && response.layout.title ? response.layout.title : _shopId;
        _shell.setTitle(title, 'NPC 物品商店'); _shell.setMetric('money', '金币', Number(response.balance || 0).toLocaleString());
        renderCategoryToolbar(); renderCatalog(); renderOwnedViews(); refreshControls();
    }

    function request(cmd, payload, callback) { payload = payload || {}; payload.v = 1; return _mux.request(cmd, payload, callback); }
    function requestInventory(cmd, payload, callback) { return _inventoryMux.request(cmd, payload || {}, callback); }
    function refreshInventory(callback) {
        _inventoryCoordinator.open(function(result) {
            if (result && result.success) rebindSaleIntentsFromViews({bag:_inventoryCoordinator.getWindow('背包')});
            renderOwnedViews(); refreshControls();
            if (callback) callback(result || {success:false});
        });
    }
    function write(cmd, payload, callback) {
        if (_busy || _needsReconcile) { toast(_needsReconcile ? '请先重新同步商店状态。' : '正在处理上一项交易。'); return false; }
        _busy = true; refreshControls();
        return !!request(cmd, payload, function(response) { _busy = false; refreshControls(); callback(response); });
    }
    function handleWriteError(response) {
        var error = response && response.error;
        if ((response && response.requiresReconcile) || error === 'timeout' || error === 'client_timeout'
                || error === 'disconnected' || error === 'reconcile_required' || error === 'malformed_response') {
            _needsReconcile = true; refreshControls(); refreshSnapshot(); return;
        }
        if (error === 'stale_state') { toast('物品状态已经变化，正在重新同步。'); refreshSnapshot(); return; }
        handleError(response); if (_settlementPage && _settlementPage.classList.contains('active')) requestTradePreview();
    }
    function handleError(response) { toast(errorMessage(response && response.error)); }
    function refreshControls() {
        if (!_shell) return;
        if (_needsReconcile) _shell.setStatus('需要重新同步', 'error'); else if (_busy || _previewBusy || _spaceBusy || _inventoryState.busyOwner) _shell.setStatus('交易核算中', 'loading');
        else if (_state) _shell.setStatus('', 'idle'); else _shell.setStatus('同步中', 'loading');
        if (_retryButton) _retryButton.style.display = _needsReconcile ? '' : 'none';
        var count = selectionCount();
        if (_checkoutButton) { _checkoutButton.textContent = count ? '结算 (' + count + ')' : '结算'; _checkoutButton.disabled = !count || _busy || _needsReconcile; }
        if (_helpButton) _helpButton.disabled = _busy || !!_inventoryState.busyOwner;
        if (_bagFilterControl) _bagFilterControl.setDisabled(_busy || !_inventoryState.ready || !!_inventoryState.busyOwner);
        for (var key in _viewButtons) _viewButtons[key].disabled = _busy;
        var buttons = _shell.getRoot().querySelectorAll('[data-collection-view]'); for (var i = 0; i < buttons.length; i++) buttons[i].disabled = _busy;
        if (_settlement) renderSettlement();
    }

    function cleanup() {
        _generation++; if (_scaleHandle) { _scaleHandle.detach(); _scaleHandle = null; }
        if (_spacePager) { _spacePager.detach(); _spacePager = null; }
        _inventoryCoordinator.close(); _inventoryMux.closeSession();
        if (_shell) _shell.closeModal(); _mux.closeSession();
        _busy = false; _previewBusy = false; _state = null; _purchaseIntents = {}; _saleIntents = {}; _settlement = null; _settlementPage = null;
        _helpPage = null; _helpButton = null; _bagFilterControl = null;
        if (_densityController) { _densityController.destroy(); _densityController = null; }
        if (typeof PanelTooltip !== 'undefined') PanelTooltip.hide();
    }
    function requestClose() {
        if (_helpPage && _helpPage.classList.contains('active')) { closeHelpPage(); return; }
        if (_spacePage && _spacePage.classList.contains('active')) { closeSpaceOrganizer(); return; }
        if (_settlementPage && _settlementPage.classList.contains('active')) { closeSettlement(); return; }
        if (_shell && _shell.hasModal()) { _shell.closeModal(); return; }
        if (_busy) { toast('交易正在确认，请稍候。'); return; }
        Panels.close(); Bridge.send({type:'panel', cmd:'close', panel:'npcshop'});
    }

    function getView(viewId) {
        if (viewId === 'bag') {
            var authoritative = _inventoryCoordinator.getWindow('背包');
            if (authoritative) return authoritative;
        }
        return _state && _state.views ? _state.views[viewId] : null;
    }
    function iconHtml(iconName, cls) {
        var html = typeof Icons !== 'undefined' && Icons.html ? Icons.html(iconName, cls || 'kshop-icon', ' onerror="this.style.display=\'none\'"') : '';
        return html || '<span class="kshop-icon-placeholder"></span>';
    }
    function escapeHtml(value) { return String(value == null ? '' : value).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
    function toast(message) { if (typeof Toast !== 'undefined') Toast.add(message); }
    function errorMessage(error) {
        var messages = {
            shop_not_found:'未找到该 NPC 的商店。', locked:'尚未获得所需情报。', insufficient_money:'金币不足。', inventory_full:'背包空间不足。',
            stale_state:'物品状态已经变化。', sell_forbidden:'该容器不允许出售。', insufficient_quantity:'物品数量不足。', duplicate_line:'交易清单包含重复物品。',
            invalid_quantity:'购买或出售数量无效。', nothing_to_sell:'没有可批量出售的普通实例。', target_full:'目标容器已满。', slot_locked:'该战备箱槽位尚未解锁。',
            busy:'商店正在处理另一项交易。', reconcile_required:'交易结果需要重新同步。', malformed_response:'交易回包不完整，正在重新同步。',
            timeout:'商店响应超时。', client_timeout:'商店响应超时。', disconnected:'连接已断开。'
        };
        return messages[error] || '操作失败，请重试。';
    }

    Bridge.on('panel_resp', function(data) { _mux.handleResponse(data); _inventoryMux.handleResponse(data); });

    return {debugState:function() {
        return {shopId:_shopId, activeRight:_activeRight, busy:_busy, needsReconcile:_needsReconcile,
            purchaseCount:Object.keys(_purchaseIntents).length, saleCount:Object.keys(_saleIntents).length,
            settling:!!(_settlementPage && _settlementPage.classList.contains('active')),
            helping:!!(_helpPage && _helpPage.classList.contains('active')),
            organizingSpace:!!(_spacePage && _spacePage.classList.contains('active')),
            inventory:_inventoryCoordinator.debugState(), mux:_mux.debugState()};
    }};
})();
