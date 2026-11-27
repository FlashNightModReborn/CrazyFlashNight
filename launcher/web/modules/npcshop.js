/** NPC 金币商店 — 主页面选择待购/待售，二级页面执行权威原子结算。 */
var NpcShop = (function() {
    'use strict';
    var _shellEl, _shell, _catalogView, _catalogRenderer, _categoryToolbar, _categoryNavigator, _categoryTree;
    var _rightViews = {}, _ownedPanes = {}, _viewButtons = {}, _viewChoiceGroup, _activeRight = 'bag';
    var _state = null, _shopId = '', _busy = false;
    var _scaleHandle = null, _retryButton, _organizeHeaderBtn, _liveTradeBar = null, _helpButton, _helpAction, _category = {mode:'auto', path:[]}, _categoryInitialized = false;
    var _purchaseIntents = {}, _saleIntents = {}, _settlement = null, _settlementCheckpoint = '', _settlementPresenter = null;
    var _settlementDraftRev = -1, _shortcutDraft = null, _keepCartOnRefresh = false;
    var _previewBusy = false, _previewQueued = false, _previewRevision = 0, _previewEpoch = 0, _activePreview = 0;
    var _tooltipCache = {}, _tooltipScope = null;
    var _layoutMode = 'full', _densityController = null, _layoutToggle = null;
    var _spacePresenter = null, _spaceBusy = false, _spaceMutated = false, _spaceFromSettlement = false;
    var _helpPresenter = null, _bagFilterControl = null;
    var _keeper = null;
    var _config = (typeof window !== 'undefined' && window.__NPCSHOP_CONFIG__) || {};
    var _runtimeConfig = {};
    for (var _configKey in _config) {
        if (Object.prototype.hasOwnProperty.call(_config, _configKey)) {
            _runtimeConfig[_configKey] = _config[_configKey];
        }
    }
    var emitDiagnostic = NpcShopRuntime.createDiagnosticEmitter({
        local:_config.diagnostic,
        send:function(message) { return Bridge.send(message); }
    });
    _runtimeConfig.diagnostic = emitDiagnostic;
    var _ownerChannels = NpcShopRuntime.createOwnerChannels(
        function(message) { return Bridge.send(message); }, _runtimeConfig);
    var _mux = _ownerChannels.business, _inventoryMux = _ownerChannels.inventory;
    var _owner = _ownerChannels.owner;
    var _inventoryState = {opened:false, ready:false, busyOwner:null, refreshRequired:false};
    var _inventoryAdapter = NpcShopRuntime.createPhysicalInventoryAdapter({
        inventoryRuntime:InventoryRuntime, request:requestInventory, owner:_owner,
        onStateChange:function(state) {
            _inventoryState = state;
            renderOwnedViews();
            renderSpaceOrganizer();
            refreshControls();
        },
        onApplied:function(result) {
            var bag = result.success && result.surface && NpcShopSecondaryPages.fullBag(result.surface.snapshots);
            if (bag) rebindSaleIntentsFromViews({bag:bag});
            renderOwnedViews(); refreshControls();
        }
    });
    var _inventoryCoordinator = _inventoryAdapter.coordinator;
    var _materialNavigation = NpcShopMaterialNavigation.create({
        runtime:NpcShopRuntime, bridge:Bridge, panels:Panels, workbench:Workbench,
        itemFilter:ItemFilter, getOwner:function() { return _owner; }, getState:function() { return _state; },
        getCatalogRenderer:function() { return _catalogRenderer; }, isReturnBlocked:returnNavigationBlocked,
        refreshSnapshot:refreshSnapshot,
        refreshControls:refreshControls
    });
    Panels.register('npcshop', {
        create:createDOM,
        onOpen:onOpen,
        onRebind:function(el, initData) { cleanup(); return onOpen(el, initData); },
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
        disposeFilterNavigators();
        disposeSharedComponents();
        if (_shell) _shell.destroy();
        Workbench.clearElement(_shellEl);
        _rightViews = {}; _ownedPanes = {}; _viewButtons = {};
        _shell = new Workbench.DualPaneShell({profile:'catalog-decision', title:_shopId, status:'同步中', leftLabel:'商品', rightLabel:'背包'});
        var root = _shell.getRoot();
        root.classList.add('kshop-workbench', 'npcshop-panel');
        root.setAttribute('data-workbench-skin', 'npcshop');
        // 独立视觉（烹饪式路线）：frame 携带阵营主题变量，立绘底板压入商品目录槽；壳宽仍为 1024 设计画布
        _keeper = typeof NpcShopKeeper !== 'undefined' ? NpcShopKeeper.create({shopId:_shopId, shell:_shell}) : null;
        if (_keeper) _keeper.root.appendChild(root);
        _shellEl.appendChild(_keeper ? _keeper.root : root);
        _viewChoiceGroup = new WorkbenchComponents.ChoiceGroup({
            document:document,
            ariaLabel:'NPC 商店右栏视图',
            value:'bag',
            choices:[
                {value:'bag', label:'背包', className:'workbench-mode-btn npcshop-view-btn', dataAttribute:'data-view-id'},
                {value:'material', label:'材料', className:'workbench-mode-btn npcshop-view-btn', dataAttribute:'data-view-id'},
                {value:'intelligence', label:'情报', className:'workbench-mode-btn npcshop-view-btn', dataAttribute:'data-view-id'}
            ],
            onChange:switchRightView
        });
        _viewButtons.bag = _viewChoiceGroup.getButton('bag');
        _viewButtons.material = _viewChoiceGroup.getButton('material');
        _viewButtons.intelligence = _viewChoiceGroup.getButton('intelligence');
        _shell.addHeaderAction(_viewChoiceGroup.root);
        _organizeHeaderBtn = document.createElement('button');
        _organizeHeaderBtn.type = 'button';
        _organizeHeaderBtn.className = 'workbench-mode-btn npcshop-organize-btn';
        _organizeHeaderBtn.textContent = '整理背包';
        _organizeHeaderBtn.setAttribute('data-audio-cue', 'open');
        _organizeHeaderBtn.addEventListener('click', function() { openSpaceOrganizer(true); });
        _shell.addHeaderAction(_organizeHeaderBtn);
        if (_densityController) _densityController.destroy();
        _densityController = new Workbench.GridDensityController({panelId:'npcshop'});
        _layoutMode = _densityController.mode;
        _layoutToggle = _densityController.createToggle(function(mode) { _layoutMode = mode; });
        _shell.addHeaderAction(_layoutToggle);
        _helpAction = new WorkbenchComponents.HelpAction({shell:_shell, spec:{
            ariaLabel:'商店操作帮助', onOpen:openHelpPage
        }});
        _helpButton = _helpAction.button; _helpButton.classList.add('npcshop-help-btn');
        _materialNavigation.createReturnAction(_shell);
        _retryButton = document.createElement('button');
        _retryButton.type = 'button'; _retryButton.className = 'workbench-mode-btn warning npcshop-retry-btn'; _retryButton.textContent = '重新同步';
        _retryButton.addEventListener('click', refreshSnapshot); _shell.addHeaderAction(_retryButton);
        var close = document.createElement('button');
        close.type = 'button'; close.className = 'workbench-close-btn'; close.textContent = '×'; close.setAttribute('aria-label', '关闭 NPC 商店');
        close.setAttribute('data-audio-cue', 'back');
        close.addEventListener('click', function() { requestClose('button'); });
        _shell.addHeaderAction(close);
        _catalogView = createCatalogView();
        _rightViews.bag = createOwnedView({viewId:'bag', title:'背包', canSell:true, layoutMode:_layoutMode});
        _rightViews.material = createOwnedView({viewId:'material', title:'材料', canSell:true, layoutMode:_layoutMode});
        _rightViews.intelligence = createOwnedView({viewId:'intelligence', title:'情报', canSell:false, layoutMode:_layoutMode});
        _shell.setDefault('L', _catalogView); _shell.setDefault('R', _rightViews.bag);
        _shell.mountInitial(_catalogView, _rightViews.bag);
        _liveTradeBar = new NpcShopSecondaryPages.LiveTradeBar({
            document:document, host:root,
            onClear:clearAllIntents, onOpenSettlement:openSettlement, onDirectTrade:quickDirectTrade
        });
        switchRightView(_activeRight); refreshControls();
    }
    function createCatalogView() {
        var root = document.createElement('div'); root.className = 'workbench-view npcshop-catalog-view';
        var chrome = new Workbench.ViewChrome({title:'商品目录', meta:'同步中'});
        _categoryNavigator = new ItemFilter.FilterNavigator({
            className:'npcshop-category-tabs item-filter-navigator',
            ariaLabel:'商店商品分类',
            presentation:'drilldown',
            visualStyle:'catalog',
            breadcrumbHost:chrome.breadcrumbHost,
            onChange:function(path) {
                if (_materialNavigation.isReturning()) return;
                _materialNavigation.clearTarget(true);
                var mode = _categoryToolbar && _categoryToolbar.getAttribute('data-filter-mode');
                _category = {mode:mode || 'auto', path:path};
                decorateCategoryButtons(mode || 'auto');
                renderCatalog({preserveScroll:false});
            }
        });
        _categoryToolbar = _categoryNavigator.root;
        chrome.setToolbar(_categoryToolbar);
        _catalogRenderer = new Workbench.GridRenderer({
            className:'npcshop-catalog-grid', emptyText:'当前分组暂无商品',
            keyOf:function(item) { return item.catalogIndex; }, renderItem:renderCatalogCard, bindItem:bindCatalogCard
        });
        if (_densityController) _densityController.register(_catalogRenderer);
        root.appendChild(chrome.root);
        _materialNavigation.attachBanner(root);
        root.appendChild(_catalogRenderer.root);
        return {
            instanceKey:'npcshop:catalog', instancePolicy:'singletonByBinding', allowedSlots:['L'], viewKind:'catalog',
            root:root, chrome:chrome,
            mount:function(container) { container.appendChild(root); },
            unmount:function() { if (root.parentNode) root.parentNode.removeChild(root); },
            render:renderCatalog
        };
    }

    function ownedInteraction(viewId) {
        return NpcShopSecondaryPages.ownedInteraction({
            ready:!!_state && _inventoryState.ready, busyOwner:_inventoryState.busyOwner,
            refreshRequired:_inventoryState.refreshRequired, transactionBusy:_busy,
            reconcileRequired:_owner.needsReconcile, spaceBusy:_spaceBusy,
            returning:_materialNavigation.isReturning(), readOnly:viewId === 'intelligence'
        });
    }
    function createOwnedView(options) {
        options = options || {};
        var viewId = options.viewId;
        var result = NpcShopSecondaryPages.createOwnedView({
            document:document, inventoryUI:InventoryUI, workbench:Workbench, components:WorkbenchComponents,
            viewId:viewId, title:options.title, canSell:options.canSell, layoutMode:options.layoutMode,
            densityController:_densityController, getView:getView,
            getSaleIntents:function() { return _saleIntents; }, iconHtml:iconHtml,
            saleIdentity:saleIdentity, bindOwnedTooltip:bindOwnedTooltip,
            interaction:ownedInteraction, toast:toast, toggleSale:toggleSale,
            onRemoveSale:function(vid, slot) { removeIntentOnMain('sale', saleIdentity(vid, slot)); },
            onQuickBulkSale:quickBulkSale,
            onQuickTrade:function(vid, slot, dbl) { quickSingleTrade('sale', {viewId:vid, slot:slot}, dbl); }
        });
        _ownedPanes[viewId] = result.pane;
        if (viewId === 'bag') installBagToolbar(result.view);
        return result.view;
    }

    function installBagToolbar(view) {
        var toolbar = document.createElement('div'); toolbar.className = 'npcshop-bag-toolbar';
        _bagFilterControl = new InventoryUI.InventoryFilterControl({
            options:InventoryUI.categoryFilterOptions(),
            ariaLabel:'商店背包分类筛选',
            navigatorPresentation:'drilldown',
            onLegacyChange:changeBagFilterLegacy,
            onSpecChange:changeBagFilterSpec
        });
        toolbar.appendChild(_bagFilterControl.root);
        view.inventoryFilterControl = _bagFilterControl;
        if (view.ownedInventoryShell) view.ownedInventoryShell.setToolbar(toolbar, _bagFilterControl); else view.chrome.setToolbar(toolbar);
    }

    function changeBagFilterLegacy(filterKey) {
        if (_materialNavigation.isReturning()) return false;
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
        if (_materialNavigation.isReturning()) return false;
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

    function renderCatalogCard(item) {
        return NpcShopSecondaryPages.renderCatalogCard({
            workbench:Workbench, components:WorkbenchComponents, document:document,
            itemFilter:ItemFilter, iconHtml:iconHtml,
            getPurchaseIntents:function() { return _purchaseIntents; }
        }, item);
    }

    function syncCatalogIntentCard(item, targetNode) {
        NpcShopSecondaryPages.syncCatalogIntentCard({
            workbench:Workbench,
            getCatalogRenderer:function() { return _catalogRenderer; },
            getPurchaseIntents:function() { return _purchaseIntents; }
        }, item, targetNode);
    }

    function syncOwnedIntentCard(viewId, slot, targetNode) {
        NpcShopSecondaryPages.syncOwnedIntentCard({
            workbench:Workbench, getRightView:function(id) { return _rightViews[id]; },
            getOwnedPane:function(id) { return _ownedPanes[id]; },
            getSaleIntents:function() { return _saleIntents; }, saleIdentity:saleIdentity
        }, viewId, slot, targetNode);
    }

    function syncAllIntentCards() {
        NpcShopSecondaryPages.syncAllIntentCards({
            workbench:Workbench, getCatalogRenderer:function() { return _catalogRenderer; },
            getPurchaseIntents:function() { return _purchaseIntents; },
            getRightView:function(id) { return _rightViews[id]; }, rightViews:_rightViews,
            getOwnedPane:function(id) { return _ownedPanes[id]; },
            getSaleIntents:function() { return _saleIntents; }, saleIdentity:saleIdentity
        });
    }

    var _lastClickUndo = null, _draftRevision = 0, _driftNotice = '';
    function togglePurchase(item, event) {
        if (event && event.detail >= 2) return;
        if (_materialNavigation.isReturning() || _busy || _previewBusy || _owner.needsReconcile || !item || item.locked) return;
        var maximum = Number(item.maxQuantity);
        if (isFinite(maximum) && maximum <= 0) { toast((item.itemKind === 'intelligence' || item.majorType === '情报') ? '该情报已达持有上限。' : '该商品已达持有上限。', 'warning', {silent:true}); cue('illegal'); return; }
        var key = String(item.catalogIndex), cap = isFinite(maximum) && maximum >= 1 ? Math.floor(maximum) : 1;
        var prev = _purchaseIntents[key] ? Object.assign({}, _purchaseIntents[key]) : null;
        if (_purchaseIntents[key]) {
            if (_purchaseIntents[key].quantity >= cap) { toast('已达到单笔可购买上限 ' + cap + '。', 'warning', {silent:true}); cue('illegal'); return; }
            _purchaseIntents[key].quantity += 1;
        } else {
            _purchaseIntents[key] = {catalogIndex:Number(item.catalogIndex), quantity:1, maxQuantity:cap, item:item};
        }
        _draftRevision++;
        if (event && event.detail === 1) _lastClickUndo = {kind:'purchase', key:key, prev:prev, at:Date.now()};
        syncCatalogIntentCard(item); refreshControls(); cue('activate');
    }
    function removeIntentOnMain(kind, identity) {
        if (_materialNavigation.isReturning() || _busy || _previewBusy || _owner.needsReconcile) return;
        var map = kind === 'purchase' ? _purchaseIntents : _saleIntents;
        if (!map[identity]) return;
        delete map[identity]; _draftRevision++;
        syncAllIntentCards(); refreshControls(); cue('back');
    }
    function clearAllIntents() {
        if (_materialNavigation.isReturning() || _busy || _previewBusy || _owner.needsReconcile || !selectionCount()) return;
        _purchaseIntents = {}; _saleIntents = {}; _draftRevision++;
        syncAllIntentCards(); refreshControls(); cue('back');
    }
    function quickBulkSale(slot) {
        if (_materialNavigation.isReturning() || _busy || _previewBusy || _owner.needsReconcile || inventoryWriteUnavailable() || !slot || !slot.occupied) return;
        var identity = saleIdentity('bag', slot);
        var max = Math.max(1, Math.floor(Number(slot.item && slot.item.quantity) || 1));
        _saleIntents[identity] = {
            identity:identity, quantity:max, maxQuantity:max, scope:'same_name', item:slot.item || {},
            source:{containerId:'背包', slot:Number(slot.physicalSlot), expectedLease:String(slot.slotLease)}
        };
        _draftRevision++;
        showGuideOnce('bulk_sale', '同名全售会扫描整个背包，并自动保护强化、进阶和带插件的装备。');
        syncOwnedIntentCard('bag', slot); refreshControls(); cue('activate');
    }

    function saleIdentity(viewId, slot) {
        return viewId === 'bag' ? 'bag:' + Number(slot.physicalSlot) : 'material:' + String(slot.collectionKey);
    }

    function toggleSale(viewId, slot, event) {
        if (event && event.detail >= 2) return;
        if (_materialNavigation.isReturning() || _busy || _previewBusy || _owner.needsReconcile
                || !_inventoryState.ready || _inventoryState.busyOwner
                || _inventoryState.refreshRequired || !slot || !slot.occupied || viewId === 'intelligence') return;
        var identity = saleIdentity(viewId, slot), prev = _saleIntents[identity] ? Object.assign({}, _saleIntents[identity]) : null;
        if (_saleIntents[identity]) {
            delete _saleIntents[identity];
            if (_ownedPanes[viewId]) _ownedPanes[viewId].setSelected(slot, false);
        } else {
            var max = Math.max(1, Math.floor(Number(slot.item && slot.item.quantity) || 1));
            _saleIntents[identity] = {
                identity:identity, quantity:max, maxQuantity:max, scope:'slot', item:slot.item || {},
                source:viewId === 'bag'
                    ? {containerId:'背包', slot:Number(slot.physicalSlot), expectedLease:String(slot.slotLease)}
                    : {viewId:'material', key:String(slot.collectionKey), expectedLease:String(slot.slotLease)}
            };
            if (_ownedPanes[viewId]) _ownedPanes[viewId].setSelected(slot, true);
        }
        _draftRevision++;
        if (event && event.detail === 1) _lastClickUndo = {kind:'sale', key:identity, prev:prev, at:Date.now()};
        syncOwnedIntentCard(viewId, slot); refreshControls(); cue('activate');
    }

    function renderCategoryToolbar() {
        if (!_categoryNavigator) return;
        var sections = _state && _state.layout && Array.isArray(_state.layout.sections) ? _state.layout.sections : [];
        var catalog = _state && _state.catalog ? _state.catalog : [];
        var setTree = ItemFilter.buildSetTree(catalog);
        if (sections.length || setTree.children.length) {
            var automaticTree = ItemFilter.build(catalog, ItemFilter.catalogPath);
            var branches = [{id:'category', label:'类别', tree:automaticTree}];
            if (setTree.children.length) branches.push({id:'set', label:'套装', tree:setTree});
            if (sections.length) branches.push({id:'curated', label:'专柜', tree:ItemFilter.manualSections(sections, catalog.length)});
            _categoryTree = ItemFilter.branchTree(branches, catalog.length);
            var currentPath = _category && _category.mode === 'combined' ? (_category.path || []) : [];
            var valid = ItemFilter.validPath(_categoryTree, currentPath);
            if (!_categoryInitialized || !valid) {
                var configured = sections.length ? String((_state.layout && _state.layout.defaultSection) || '') : '';
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

    function decorateCategoryButtons(mode) { NpcShopSecondaryPages.decorateCategoryButtons(_categoryToolbar, _categoryTree, ItemFilter, mode); }
    function renderCatalog(renderOptions) {
        if (!_catalogRenderer) return;
        var catalog = _state && _state.catalog ? _state.catalog : [];
        var filtered = catalog.filter(matchesCategory); _catalogRenderer.render(filtered, renderOptions);
        if (_catalogView) _catalogView.chrome.setMeta(_state ? filtered.length + ' / ' + catalog.length + ' 件商品' : '同步中');
        _materialNavigation.applyPresentation();
        if (_keeper) _keeper.warmIcons(function() { if (_catalogRenderer && _state) { renderCatalog({forceItemRender:true}); renderOwnedViews(); refreshControls(); } });
    }
    function matchesCategory(item) { return NpcShopSecondaryPages.matchesCategory(_state, _category, ItemFilter, item); }

    function renderOwnedViews() {
        for (var key in _rightViews) {
            var view = _rightViews[key]; if (!view) continue;
            var data = getView(key); var occupied = data && data.slots ? data.slots.filter(function(slot) { return slot.occupied; }).length : 0;
            var total = data && data.filterItemCount != null ? Number(data.filterItemCount) : occupied;
            var meta = _state ? (occupied === total ? occupied : occupied + ' / ' + total) + ' 项' : '同步中';
            if (view.ownedInventoryPane) view.ownedInventoryPane.update(data, {meta:meta});
            else { view.render(); view.chrome.setMeta(meta); }
        }
    }
    function cartDraft() { return {purchases:_purchaseIntents, sales:_saleIntents}; }
    function settlementDraft() { return _shortcutDraft || cartDraft(); }
    function settlementRevision() { return _shortcutDraft ? _shortcutDraft.revision : _draftRevision; }
    function markSettlementEdited() {
        if (_shortcutDraft) _shortcutDraft.revision++;
        else _draftRevision++;
    }
    function selectionPayload(draft) { return NpcShopSecondaryPages.selectionPayload(_shopId, draft || cartDraft()); }
    function selectionCount(draft) { draft = draft || cartDraft(); return Object.keys(draft.purchases).length + Object.keys(draft.sales).length; }
    function inventoryWriteUnavailable() { return !_inventoryState.ready || !!_inventoryState.busyOwner || !!_inventoryState.refreshRequired; }
    function openSettlement() {
        if (_materialNavigation.isReturning() || !selectionCount() || _busy || _previewBusy
                || _owner.needsReconcile || inventoryWriteUnavailable()) return;
        if (!_settlementPresenter) createSettlementPage();
        resetPreviewCycle();
        _settlement = null; _settlementCheckpoint = ''; _driftNotice = ''; _settlementDraftRev = -1; _shortcutDraft = null; _settlementPresenter.reset();
        _settlementPresenter.open(); _shell.getRoot().classList.add('npcshop-settling');
        showGuideOnce('settlement', '这里仍是交易清单：调整完成并点击“确认交易”后，买卖才会一次生效。');
        requestTradePreview();
    }
    function closeSettlement() {
        if (_materialNavigation.isReturning()) return false;
        if (_busy) { toast('交易正在确认，请稍候。'); return false; }
        resetPreviewCycle();
        if (_settlementPresenter) _settlementPresenter.close('return');
        if (_shell) _shell.getRoot().classList.remove('npcshop-settling');
        _settlement = null; _settlementCheckpoint = ''; _driftNotice = ''; _settlementDraftRev = -1; _shortcutDraft = null; syncAllIntentCards(); refreshControls();
        return true;
    }
    function resetPreviewCycle() {
        _previewEpoch++; _activePreview = 0; _previewBusy = false; _previewQueued = false;
    }
    function createSettlementPage() {
        _settlementPresenter = new NpcShopSecondaryPages.SettlementPresenter({
            document:document,
            components:WorkbenchComponents,
            host:_shell.getRoot(),
            onBack:closeSettlement,
            onClose:requestPanelCloseFromSecondary,
            onOrganize:openSpaceOrganizer,
            onCommit:commitTrade,
            onSetQuantity:setIntentQuantity,
            onBulkSale:setBulkSale,
            onRemove:removeIntent,
            onHelp:openHelpPage,
            onPurchaseBounds:function(identity, bounds) {
                var intent = settlementDraft().purchases[identity];
                if (!intent) return;
                intent.purchaseLimit = bounds.purchaseLimit;
                intent.maxPurchasable = bounds.maxPurchasable;
            },
            onGuide:function(topic) {
                if (topic === 'inventory_full') showGuideOnce(topic,
                    '背包不足时可点“整理空间”；返回结算后，系统会重新核算数量与空位。');
            },
            tooltip:_tooltipScope || PanelTooltip, tooltipCache:_tooltipCache, renderTooltipBasic:buildTooltipBasic, renderTooltipRich:buildTooltipRich,
            requestTooltip:request, iconHtml:iconHtml, errorMessage:errorMessage
        });
    }
    function requestTradePreview() {
        if (_materialNavigation.isReturning() || _busy || _owner.needsReconcile
                || inventoryWriteUnavailable() || !_settlementPresenter
                || !_settlementPresenter.isActive()) return;
        var draft = settlementDraft();
        if (!selectionCount(draft)) { closeSettlement(); return; }
        if (_previewBusy) { _previewQueued = true; return; }
        _previewBusy = true; _previewQueued = false; _previewRevision++; _driftNotice = '';
        var revision = _previewRevision, epoch = _previewEpoch;
        var requestCheckpoint = JSON.stringify(draft);
        _activePreview = revision; renderSettlementLoading();
        var payload = selectionPayload(draft), previewDraftRev = settlementRevision();
        var issued = request('tradePreview', payload, function(response) {
            if (epoch !== _previewEpoch || revision !== _activePreview || !_settlementPresenter || !_settlementPresenter.isActive()) return;
            _activePreview = 0; _previewBusy = false;
            if (!response.success) {
                handlePreviewError(response);
                return;
            }
            if (previewDraftRev !== settlementRevision()) { requestTradePreview(); return; }
            _settlement = response; _settlementDraftRev = previewDraftRev; renderSettlement();
            _settlementCheckpoint = requestCheckpoint;
            if (_previewQueued) requestTradePreview();
        });
        if (!issued && epoch === _previewEpoch && revision === _activePreview) {
            _activePreview = 0; _previewBusy = false; renderSettlementFailure('disconnected', false);
        }
    }
    function renderSettlementLoading() {
        if (!_settlementPresenter) return;
        if (_settlement) renderSettlement();
        _settlementPresenter.renderLoading();
    }
    function renderSettlementFailure(errorCode, recovered) {
        if (_settlementPresenter) _settlementPresenter.renderFailure(errorCode, recovered);
    }
    function renderSettlement() {
        if (!_settlementPresenter || !_settlement) return;
        _settlementPresenter.render(_settlement, settlementDraft(), {
            busy:_busy, previewBusy:_previewBusy, spaceBusy:_spaceBusy, driftNotice:_driftNotice,
            draftStale:_settlementDraftRev !== settlementRevision()
        });
    }
    function restoreSettlementCheckpoint() {
        if (!_settlement || !_settlementCheckpoint) return false;
        var checkpoint = JSON.parse(_settlementCheckpoint);
        if (_shortcutDraft) { _shortcutDraft.purchases = checkpoint.purchases; _shortcutDraft.sales = checkpoint.sales; }
        else { _purchaseIntents = checkpoint.purchases; _saleIntents = checkpoint.sales; }
        _previewQueued = false;
        markSettlementEdited(); _settlementDraftRev = settlementRevision();
        syncAllIntentCards(); refreshControls(); return true;
    }
    function handlePreviewError(response, shortcut) {
        var error = String(response && response.error || 'invalid_response');
        if ((response && response.requiresReconcile) || error === 'reconcile_required') {
            _owner.enterNeedsReconcile(); refreshControls(); refreshSnapshot(shortcut === true); return;
        }
        if (['stale_state','shop_not_found','item_not_found','locked','invalid_price','invalid_quantity',
                'insufficient_quantity','nothing_to_sell','sell_forbidden'].indexOf(error) >= 0) {
            handleError(response); refreshSnapshot(shortcut === true); return;
        }
        handleError(response);
        var recovered = restoreSettlementCheckpoint();
        if (recovered) renderSettlement();
        else { _settlement = null; _settlementDraftRev = -1; }
        renderSettlementFailure(error, recovered);
    }
    function setIntentQuantity(kind, identity, quantity, reason) {
        var draft = settlementDraft();
        var line = (kind === 'purchase' ? draft.purchases : draft.sales)[identity];
        if (_materialNavigation.isReturning() || !line || _busy || _previewBusy
                || _owner.needsReconcile) return;
        var limit = kind === 'purchase' ? Number(line.purchaseLimit || line.maxQuantity) : line.maxQuantity;
        if (kind === 'purchase' && reason === 'maximum') {
            limit = Math.max(limit, Number(line.maxPurchasable || 0));
        }
        line.quantity = Math.max(1, Math.min(limit, Math.floor(Number(quantity) || 1))); markSettlementEdited();
        if (kind === 'purchase') syncCatalogIntentCard(line.item);
        else syncAllIntentCards();
        requestTradePreview();
    }
    function setBulkSale(identity, enabled) {
        var line = settlementDraft().sales[identity];
        if (_materialNavigation.isReturning() || !line || _busy || _previewBusy
                || _owner.needsReconcile || !line.source
                || line.source.containerId !== '背包') return;
        line.scope = enabled ? 'same_name' : 'slot'; markSettlementEdited();
        if (enabled) showGuideOnce('bulk_sale', '同名全售会扫描整个背包，并自动保护强化、进阶和带插件的装备。');
        syncAllIntentCards(); requestTradePreview();
    }
    function openHelpPage() {
        if (_materialNavigation.isReturning() || _busy || _inventoryState.busyOwner) return;
        if (!_helpPresenter) createHelpPage();
        _helpPresenter.open(_settlementPresenter && _settlementPresenter.isActive() ? '← 返回结算' : '← 返回商店');
        _shell.getRoot().classList.add('npcshop-helping');
        refreshControls();
    }

    function closeHelpPage() {
        if (_helpPresenter) _helpPresenter.close('return');
        if (_shell) _shell.getRoot().classList.remove('npcshop-helping');
        refreshControls();
        if (_helpButton && !(_settlementPresenter && _settlementPresenter.isActive())) _helpButton.focus();
    }

    function createHelpPage() {
        _helpPresenter = new NpcShopSecondaryPages.HelpPresenter({
            document:document, components:WorkbenchComponents, host:_shell.getRoot(),
            onBack:closeHelpPage, onClose:requestPanelCloseFromSecondary
        });
    }

    function showGuideOnce(topic, message) {
        var key = 'cf7.npcshop.guide.v1.' + topic;
        try {
            if (window.localStorage && window.localStorage.getItem(key) === '1') return false;
            if (window.localStorage) window.localStorage.setItem(key, '1');
        } catch (error) {}
        toast(message); return true;
    }

    function openSpaceOrganizer(fromHeader) {
        var fromSettlement = fromHeader !== true && !!(_settlementPresenter && _settlementPresenter.isActive());
        if (_materialNavigation.isReturning() || _busy || _previewBusy || _owner.needsReconcile) return;
        if (fromHeader !== true && (!_settlement || _settlement.blockingError !== 'inventory_full')) return;
        if (!_spacePresenter) createSpaceOrganizer();
        _spaceFromSettlement = fromSettlement;
        _spacePresenter.open(fromSettlement ? '← 返回结算' : '← 返回商店');
        if (fromSettlement && _settlementPresenter) _settlementPresenter.setOrganizing(true);
        _spaceBusy = true; _spaceMutated = false; refreshControls();
        if (_inventoryState.opened && _inventoryState.ready && !_inventoryState.refreshRequired) {
            _spaceBusy = false; renderSpaceOrganizer(); refreshControls();
        } else refreshInventory(function(result) {
            _spaceBusy = false; renderSpaceOrganizer(); refreshControls();
            if (!result.success) toast('库存同步失败，暂时无法整理空间。');
        });
    }

    function createSpaceOrganizer() {
        _spacePresenter = new NpcShopSecondaryPages.SpaceOrganizerPresenter({
            document:document, components:WorkbenchComponents, inventoryUI:InventoryUI, workbench:Workbench,
            densityController:_densityController, host:_shell.getRoot(),
            getWindow:function(c) { return _inventoryCoordinator.getWindow(c); },
            getRequest:function(c) { return _inventoryCoordinator.getRequest(c); },
            setWindow:function(c, o, l, cb) { return _inventoryCoordinator.setWindow(c, o, l, cb); },
            autoTransfer:function(source, target, done) { return _inventoryCoordinator.autoTransfer(source, target, done); },
            onBack:function() { closeSpaceOrganizer(); return false; }, onClose:requestPanelCloseFromSecondary,
            onPageResult:function(r) { if (!r.success) toast('战备箱翻页失败。'); },
            onTransferResult:function(r) {
                if (r && r.success) _spaceMutated = true; else toast(errorMessage(r && r.error));
                refreshControls();
            },
            tooltip:_tooltipScope || PanelTooltip, tooltipCache:_tooltipCache,
            renderTooltipBasic:buildTooltipBasic, renderTooltipRich:buildTooltipRich,
            requestTooltip:request, iconHtml:iconHtml, toast:toast
        });
    }

    function renderSpaceOrganizer() {
        if (_spacePresenter) _spacePresenter.render(Object.assign({}, _inventoryState, {spaceBusy:_spaceBusy}));
    }

    function closeSpaceOrganizer() {
        if (!_spacePresenter || !_spacePresenter.isActive() || _inventoryState.busyOwner) return;
        _spaceBusy = true; renderSettlementLoading(); renderSpaceOrganizer(); refreshControls();
        var inventoryCallId = requestInventory('snapshot', {
            v:1,
            requests:[{containerId:'背包', offset:0, limit:50, filterKey:'all'}]
        }, function(inventoryResponse) {
            var fullBag = inventoryResponse && inventoryResponse.success && NpcShopSecondaryPages.fullBag(inventoryResponse.snapshots);
            if (!fullBag) {
                _spaceBusy = false; renderSpaceOrganizer(); refreshControls();
                toast('完整背包同步失败，暂时无法返回结算。');
                return;
            }
            var snapshotIntent = _owner.captureSnapshot();
            request('snapshot', {shopId:_shopId}, function(response) {
                _spaceBusy = false;
                if (!_owner.isCurrentSnapshot(snapshotIntent)) { renderSpaceOrganizer(); refreshControls(); return; }
                if (!response.success) { handleWriteError(response); return; }
                rebindSaleIntentsFromViews({
                    bag:fullBag,
                    material:response.views && response.views.material
                });
                var returnToSettlement = _spaceFromSettlement && _settlementPresenter && _settlementPresenter.isActive();
                _spaceFromSettlement = false;
                _spacePresenter.close('return');
                if (_settlementPresenter) _settlementPresenter.setOrganizing(false);
                if (returnToSettlement) {
                    _settlement = null; _settlementCheckpoint = ''; _driftNotice = ''; _settlementPresenter.reset();
                    applyState(response);
                    requestTradePreview();
                    if (_spaceMutated) toast('库存已整理，交易数量与容量已重新核算。');
                } else {
                    applyState(response); syncAllIntentCards();
                    if (_spaceMutated) toast('背包与战备箱已整理。');
                }
            });
        });
        if (!inventoryCallId) {
            _spaceBusy = false; renderSpaceOrganizer(); refreshControls();
            toast('完整背包同步失败，暂时无法返回结算。');
        }
    }

    function rebindSaleIntentsFromViews(views) {
        var result = NpcShopSecondaryPages.rebindSaleIntents(_saleIntents, views, NpcShopRuntime.isPlainProjectedItem);
        _saleIntents = result.next;
        if (result.changed) _draftRevision++;
        var changed = result.changed;
        if (_shortcutDraft) {
            var active = NpcShopSecondaryPages.rebindSaleIntents(_shortcutDraft.sales, views, NpcShopRuntime.isPlainProjectedItem);
            _shortcutDraft.sales = active.next;
            changed = active.changed;
            if (changed) markSettlementEdited();
        }
        if (result.dropped) toast('有 ' + result.dropped + ' 项待售物品已变化，已从结算单移除。');
        if (changed && _settlementPresenter && _settlementPresenter.isActive()) {
            _settlementCheckpoint = '';
            if (!selectionCount(settlementDraft())) closeSettlement();
            else if (!_spaceBusy && !_spaceFromSettlement) requestTradePreview();
        }
    }

    function removeIntent(kind, identity) {
        if (_materialNavigation.isReturning() || _busy || _previewBusy || _owner.needsReconcile) return;
        var draft = settlementDraft();
        var map = kind === 'purchase' ? draft.purchases : draft.sales; delete map[identity]; markSettlementEdited();
        syncAllIntentCards(); cue('back');
        if (!selectionCount(draft)) closeSettlement(); else requestTradePreview();
    }

    function commitTrade() {
        if (_materialNavigation.isReturning() || _busy || _owner.needsReconcile
                || inventoryWriteUnavailable() || !_settlement
                || !_settlement.canCommit || _previewBusy || _settlementDraftRev !== settlementRevision()) return;
        var shortcut = !!_shortcutDraft;
        write('tradeCommit', {shopId:_shopId, expectedTradeToken:String(_settlement.tradeToken)}, function(response) {
            if (!response.success) { handleWriteError(response); cue('rejected'); return; }
            var trade = response.trade || {};
            if (!shortcut) { _purchaseIntents = {}; _saleIntents = {}; _draftRevision++; }
            _driftNotice = ''; _settlementDraftRev = -1; closeSettlement();
            applyState(response); refreshInventory();
            toast('交易完成：购买 $' + Number(trade.buyTotal || 0).toLocaleString() + '，出售 $' + Number(trade.sellTotal || 0).toLocaleString());
            cue('success');
        });
    }

    function executeDirectTrade(payload, clearIntents, shortcutIntent) {
        if (_materialNavigation.isReturning() || _busy || _previewBusy || _owner.needsReconcile || inventoryWriteUnavailable()) return;
        var epoch = _previewEpoch, draftRev = _draftRevision, expectedQuote = NpcShopSecondaryPages.captureDirectQuote(payload, _purchaseIntents, _saleIntents, shortcutIntent, _state);
        _previewBusy = true; refreshControls();
        request('tradePreview', payload, function(preview) {
            if (epoch !== _previewEpoch) return;
            _previewBusy = false; refreshControls();
            if (draftRev !== _draftRevision) return;
            if (!preview || !preview.success) { handlePreviewError(preview || {}, !!shortcutIntent); return; }
            var drift = NpcShopSecondaryPages.describeQuoteDrift(expectedQuote, preview);
            if (!preview.canCommit || drift || NpcShopSecondaryPages.requiresTradeReview(payload, preview, shortcutIntent, _saleIntents, NpcShopRuntime.isPlainProjectedItem)) {
                _shortcutDraft = null;
                if (shortcutIntent) {
                    _shortcutDraft = {purchases:{}, sales:{}, revision:0};
                    var lines = shortcutIntent.kind === 'purchase' ? _shortcutDraft.purchases : _shortcutDraft.sales;
                    lines[shortcutIntent.key] = shortcutIntent.intent;
                }
                _settlementCheckpoint = JSON.stringify(settlementDraft());
                if (!_settlementPresenter) createSettlementPage();
                _driftNotice = drift; _settlement = preview; _settlementDraftRev = settlementRevision();
                _settlementPresenter.open(); _shell.getRoot().classList.add('npcshop-settling');
                renderSettlement(); if (drift) toast(drift, 'warning'); return;
            }
            write('tradeCommit', {shopId:_shopId, expectedTradeToken:String(preview.tradeToken)}, function(response) {
                if (!response.success) { handleWriteError(response, !!shortcutIntent); cue('rejected'); return; }
                var trade = response.trade || {};
                if (clearIntents && draftRev === _draftRevision) { _purchaseIntents = {}; _saleIntents = {}; _draftRevision++; }
                applyState(response); refreshInventory();
                toast('交易完成：购买 $' + Number(trade.buyTotal || 0).toLocaleString() + '，出售 $' + Number(trade.sellTotal || 0).toLocaleString());
                cue('success');
            });
        });
    }
    function quickDirectTrade() { if (selectionCount()) executeDirectTrade(selectionPayload(), true); }
    function quickSingleTrade(kind, target, fromDblClick) {
        if (_materialNavigation.isReturning() || _busy || _previewBusy || _owner.needsReconcile || inventoryWriteUnavailable()) return;
        var key = kind === 'purchase' ? String(target && target.catalogIndex) : saleIdentity(target && target.viewId, target && target.slot);
        if (fromDblClick && _lastClickUndo && _lastClickUndo.kind === kind && _lastClickUndo.key === key && Date.now() - _lastClickUndo.at <= 600) {
            var undo = _lastClickUndo; _lastClickUndo = null;
            var map = kind === 'purchase' ? _purchaseIntents : _saleIntents;
            if (undo.prev) map[key] = undo.prev; else delete map[key];
            _draftRevision++; syncAllIntentCards(); refreshControls();
        }
        var payload = NpcShopSecondaryPages.buildSingleTradePayload(_shopId, kind, target);
        if (!payload) return;
        var sc = kind === 'purchase'
            ? {kind:'purchase', key:key, intent:{catalogIndex:Number(target.catalogIndex), quantity:1, maxQuantity:Math.max(1, Math.floor(Number(target.maxQuantity) || 1)), item:target}}
            : {kind:'sale', key:key, intent:{identity:key, quantity:1, maxQuantity:Math.max(1, Math.floor(Number(target.slot.item && target.slot.item.quantity) || 1)), scope:'slot', item:target.slot.item || {}, source:payload.sales[0].source}};
        executeDirectTrade(payload, false, sc);
    }

    function bindCatalogCard(node, item) {
        var tooltipBinder = _tooltipScope || PanelTooltip;
        tooltipBinder.bindAsyncHover(node, {
            cache: _tooltipCache,
            key: 'catalog:' + item.itemName,
            item: item,
            renderBasic: buildTooltipBasic,
            renderRich: buildTooltipRich,
            fetch: function(item, callback) {
                request('tooltip', {itemName: item.itemName}, callback);
            }
        });
        function blockReturnNavigationMutation(event) {
            _materialNavigation.consumeMutation(event);
        }
        node.addEventListener('click', blockReturnNavigationMutation, true);
        node.addEventListener('keydown', blockReturnNavigationMutation, true);
        NpcShopSecondaryPages.bindCatalogActivation({
            workbench:Workbench, node:node, item:item, toast:toast,
            selected:!!_purchaseIntents[String(item.catalogIndex)],
            onActivate:function(event) { togglePurchase(item, event); },
            onRemove:function(entry) { removeIntentOnMain('purchase', String(entry.catalogIndex)); },
            onQuickTrade:function(entry, dbl) { quickSingleTrade('purchase', entry, dbl); }
        });
    }
    function bindOwnedTooltip(node, viewId, slot) {
        var tooltipBinder = _tooltipScope || PanelTooltip;
        NpcShopSecondaryPages.bindOwnedTooltip({
            node:node, viewId:viewId, slot:slot, tooltip:tooltipBinder, cache:_tooltipCache,
            renderBasic:buildTooltipBasic, renderRich:buildTooltipRich, request:request
        });
    }
    function buildTooltipBasic(item) { return NpcShopSecondaryPages.tooltipBasic(item, escapeHtml, Workbench); }
    function buildTooltipRich(item, rich) { return NpcShopSecondaryPages.tooltipRich(item, rich, PanelTooltip, Workbench); }

    function switchRightView(viewId) {
        if (!_rightViews[viewId]) viewId = 'bag';
        // 视图/页签切换：仅真实切换时播音（初始化与重复点击当前页签静默）
        if (viewId !== _activeRight) cue('select');
        _activeRight = viewId;
        _shell.moveView('R', _rightViews[viewId]);
        var labels = {bag:'背包',material:'材料',intelligence:'情报'};
        _shell.setSlotLabel('R', labels[viewId] || '背包');
        if (_viewChoiceGroup) _viewChoiceGroup.update({value:viewId});
        else for (var key in _viewButtons) _viewButtons[key].classList.toggle('active', key === viewId);
    }

    function onOpen(el, initData) {
        initData = initData || {};
        var parsedInit = NpcShopRuntime.parseInitData(initData);
        if (!parsedInit) return false;
        _materialNavigation.configure(parsedInit, initData);
        disposeSharedComponents();
        if (_tooltipScope) _tooltipScope.dispose();
        _tooltipScope = typeof PanelTooltip !== 'undefined' && PanelTooltip.createScope
            ? PanelTooltip.createScope('npcshop', {profile:'dense-inspect'}) : null;
        _shopId = typeof initData.shopId === 'string' ? initData.shopId : '';
        _state = null; _busy = false; _purchaseIntents = {}; _saleIntents = {}; _settlement = null; _settlementCheckpoint = '';
        _spaceBusy = false; _spaceMutated = false; _spaceFromSettlement = false; _helpButton = null;
        resetPreviewCycle(); _previewRevision = 0; _category = {mode:'auto', path:[]}; _categoryInitialized = false;
        _activeRight = 'bag'; _tooltipCache = {};
        buildDOM(); if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = typeof PanelScale !== 'undefined' ? PanelScale.attach(_shellEl, 1024, 576) : null;
        if (!_inventoryAdapter.resetSession()) return false;
        if (!_owner.open(initData.panelInstanceId)) return false;
        refreshSnapshot();
    }

    function refreshSnapshot(keepCart) {
        if (keepCart === true || _shortcutDraft) _keepCartOnRefresh = true;
        if (_materialNavigation.isReturning() || !_shopId || _busy) return false;
        _materialNavigation.beginSnapshot();
        refreshInventory();
        _shell.setStatus('同步中', 'loading'); var snapshotIntent = _owner.captureSnapshot();
        return !!request('snapshot', {shopId:_shopId}, function(response, entry) {
            if (!_owner.isCurrentSnapshot(snapshotIntent)) {
                emitDiagnostic(NpcShopRuntime.createSnapshotDiagnostic(
                    'snapshot_stale', response, entry, _owner.panelInstanceId));
                return;
            }
            if (response.success) {
                _owner.acceptAuthorityState();
                if (!_keepCartOnRefresh) { _purchaseIntents = {}; _saleIntents = {}; }
                _keepCartOnRefresh = false;
                closeSettlement(); applyState(response);
                emitDiagnostic(NpcShopRuntime.createSnapshotDiagnostic(
                    'snapshot_adopted', response, entry, _owner.panelInstanceId));
            }
            else {
                emitDiagnostic(NpcShopRuntime.createSnapshotDiagnostic(
                    'snapshot_rejected', response, entry, _owner.panelInstanceId));
                _owner.enterNeedsReconcile();
                _materialNavigation.rejectSnapshot();
                handleError(response); refreshControls();
            }
        });
    }

    function applyState(response) {
        _state = response; _busy = false; _owner.acceptAuthorityState();
        if (response.views && response.views.material) rebindSaleIntentsFromViews({material:response.views.material});
        _materialNavigation.acceptSnapshot();
        var preferredCategory = _materialNavigation.prepareState(response);
        if (preferredCategory) {
            _category = preferredCategory;
            _categoryInitialized = true;
        }
        var title = response.layout && response.layout.title ? response.layout.title : _shopId;
        _shell.setTitle(title, (_keeper && _keeper.faction ? _keeper.faction + ' · ' : '') + 'NPC 物品商店'); _shell.setMetric('money', '金币', Number(response.balance || 0).toLocaleString());
        renderCategoryToolbar(); renderCatalog(); renderOwnedViews(); refreshControls();
    }

    function request(cmd, payload, callback) { payload = payload || {}; payload.v = 1; return _mux.request(cmd, payload, callback); }
    function requestInventory(cmd, payload, callback) { return _inventoryMux.request(cmd, payload || {}, callback); }
    function refreshInventory(callback) { return _inventoryAdapter.refresh(callback); }
    function write(cmd, payload, callback) {
        if (_materialNavigation.isReturning() || _busy || _owner.needsReconcile
                || inventoryWriteUnavailable()) {
            toast(_owner.needsReconcile || _inventoryState.refreshRequired || !_inventoryState.ready
                ? '请先重新同步商店状态。' : '正在处理上一项交易。', 'warning');
            return false; }
        _busy = true; refreshControls();
        return !!request(cmd, payload, function(response) { _busy = false; refreshControls(); callback(response); });
    }
    function handleWriteError(response, shortcut) {
        var error = response && response.error;
        if ((response && response.requiresReconcile) || error === 'timeout' || error === 'client_timeout'
                || error === 'reconcile_required' || error === 'malformed_response') {
            _owner.enterNeedsReconcile(); refreshControls(); refreshSnapshot(shortcut === true); return;
        }
        if (error === 'stale_state') { toast('物品状态已经变化，正在重新同步。', 'warning'); refreshSnapshot(shortcut === true); return; }
        handleError(response); if (_settlementPresenter && _settlementPresenter.isActive()) _settlementPresenter.renderFailure(error, false);
    }
    function handleError(response) { toast(NpcShopSecondaryPages.errorMessage(response && response.error), 'error'); }
    function refreshControls() {
        if (!_shell) return;
        var returning = _materialNavigation.isReturning();
        var needsInventoryRetry = !!_inventoryState.refreshRequired;
        if (returning) _shell.setStatus('正在返回材料档案', 'loading');
        else if (_owner.needsReconcile) _shell.setStatus('需要重新同步', 'error');
        else if (needsInventoryRetry) _shell.setStatus('库存需要重新同步', 'error');
        else if (_busy || _previewBusy || _spaceBusy || _inventoryState.busyOwner) _shell.setStatus('交易核算中', 'loading');
        else if (_state) _shell.setStatus('', 'idle'); else _shell.setStatus('同步中', 'loading');
        if (_retryButton) {
            _retryButton.style.display = _owner.needsReconcile || needsInventoryRetry ? '' : 'none';
            _retryButton.disabled = returning;
        }
        if (_organizeHeaderBtn) _organizeHeaderBtn.disabled = returning || !_state || _busy || _previewBusy || _spaceBusy || _owner.needsReconcile;
        var draftBlocked = returning || _busy || _previewBusy || _owner.needsReconcile;
        if (_liveTradeBar) _liveTradeBar.update({
            purchases:_purchaseIntents, sales:_saleIntents, buyRatePermille:_state && _state.buyRatePermille,
            disabled:draftBlocked || inventoryWriteUnavailable()
        });
        var rmBtns = _shell.getRoot().querySelectorAll('.npcshop-intent-remove');
        for (var rm = 0; rm < rmBtns.length; rm++) rmBtns[rm].disabled = draftBlocked;
        if (_helpButton) _helpButton.disabled = returning || _busy || !!_inventoryState.busyOwner;
        if (_bagFilterControl) _bagFilterControl.setDisabled(returning || _busy || _previewBusy || _owner.needsReconcile || !_inventoryState.ready
            || !!_inventoryState.busyOwner || !!_inventoryState.refreshRequired);
        if (_viewChoiceGroup) _viewChoiceGroup.update({disabled:returning || _busy});
        else for (var key in _viewButtons) _viewButtons[key].disabled = returning || _busy;
        for (var paneKey in _ownedPanes) _ownedPanes[paneKey].setInteraction(ownedInteraction(paneKey));
        if (_categoryNavigator) _categoryNavigator.setDisabled(returning);
        if (_layoutToggle) {
            var layoutButtons = _layoutToggle.querySelectorAll('button');
            for (var layoutIndex = 0; layoutIndex < layoutButtons.length; layoutIndex++) {
                layoutButtons[layoutIndex].disabled = returning;
            }
        }
        _materialNavigation.syncControls(_catalogRenderer && _catalogRenderer.root);
        if (_settlement) renderSettlement();
    }

    function returnNavigationBlocked() {
        return !_materialNavigation.hasTarget() || !_state
            || _busy || _previewBusy || _spaceBusy || !!_inventoryState.busyOwner
            || !_inventoryState.ready || !!_inventoryState.refreshRequired
            || _owner.needsReconcile
            || !!(_helpPresenter && _helpPresenter.isActive())
            || !!(_spacePresenter && _spacePresenter.isActive())
            || !!(_settlementPresenter && _settlementPresenter.isActive())
            || !!(_shell && _shell.hasModal && _shell.hasModal());
    }

    function cleanup() {
        _shortcutDraft = null; _keepCartOnRefresh = false;
        _materialNavigation.cleanup();
        if (_scaleHandle) { _scaleHandle.detach(); _scaleHandle = null; }
        _inventoryAdapter.close(); _owner.close(); if (_keeper) { _keeper.destroy(); _keeper = null; }
        if (_shell) _shell.closeModal();
        disposeSharedComponents();
        _busy = false; resetPreviewCycle(); _state = null;
        _purchaseIntents = {}; _saleIntents = {}; _draftRevision++; _driftNotice = ''; _settlement = null; _settlementCheckpoint = '';
        _helpButton = null;
        disposeFilterNavigators();
        if (_densityController) { _densityController.destroy(); _densityController = null; }
        _layoutToggle = null;
        if (_tooltipScope) { _tooltipScope.dispose(); _tooltipScope = null; }
    }
    function disposeFilterNavigators() {
        if (_categoryNavigator && typeof _categoryNavigator.destroy === 'function') _categoryNavigator.destroy();
        if (_bagFilterControl && typeof _bagFilterControl.destroy === 'function') _bagFilterControl.destroy();
        _categoryNavigator = null;
        _categoryToolbar = null;
        _bagFilterControl = null;
    }
    function disposeSharedComponents() {
        if (_liveTradeBar) _liveTradeBar.destroy();
        if (_helpAction) _helpAction.destroy();
        if (_spacePresenter) _spacePresenter.destroy();
        if (_helpPresenter) _helpPresenter.destroy();
        if (_settlementPresenter) _settlementPresenter.destroy();
        if (_viewChoiceGroup) _viewChoiceGroup.destroy();
        for (var key in _ownedPanes) _ownedPanes[key].destroy();
        _liveTradeBar = null; _helpAction = null; _spacePresenter = null; _helpPresenter = null; _settlementPresenter = null;
        _viewChoiceGroup = null; _ownedPanes = {};
    }
    function requestClose(reason) {
        reason = NpcShopRuntime.isCloseReason(reason) ? reason : 'button';
        if (_helpPresenter && _helpPresenter.isActive()) { closeHelpPage(); return true; }
        if (_spacePresenter && _spacePresenter.isActive()) {
            closeSpaceOrganizer(); return true;
        }
        if (_settlementPresenter && _settlementPresenter.isActive()) {
            closeSettlement(); return true;
        }
        if (_shell && _shell.hasModal()) { _shell.closeModal(reason); return true; }
        return commitPanelClose(reason);
    }
    // 面板级关闭的独立 commit 路径（契约 §5.5）：二级页 × 绕过层级检查直接关整个面板，
    // 不得复用 requestClose（会被 presenter/modal 检查拦截成只关二级页）。
    function commitPanelClose(reason) {
        if (_materialNavigation.isReturning()) {
            toast('正在返回材料档案，请稍候。', 'warning'); return false;
        }
        if (_busy) { toast('交易正在确认，请稍候。', 'warning'); return false; }
        var closeMessage = _owner.closeMessage(reason);
        if (!closeMessage || Bridge.send(closeMessage) === false) {
            toast('启动器连接不可用，NPC 商店保持打开。', 'error');
            return false;
        }
        return true;
    }
    function requestPanelCloseFromSecondary() {
        return commitPanelClose('button');
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
    function toast(message, severity, opts) { if (typeof Toast !== 'undefined') Toast.add(message, severity, opts); }
    // 语义音效命令式入口（契约 §8）：仅本地可拒绝 / 权威结果路径使用，静态元素走 data-audio-cue
    function cue(name) {
        var A = window.BootstrapAudio;
        if (A && typeof A.cue === 'function') A.cue(name);
    }
    function errorMessage(error) { return NpcShopSecondaryPages.errorMessage(error); }
    return {debugState:function() {
        var navigation = _materialNavigation.debugState();
        return {shopId:_shopId, activeRight:_activeRight, busy:_busy, needsReconcile:_owner.needsReconcile,
            reconcileEpoch:_owner.reconcileEpoch, panelInstanceId:_owner.panelInstanceId,
            purchaseCount:Object.keys(_purchaseIntents).length, saleCount:Object.keys(_saleIntents).length,
            settling:!!(_settlementPresenter && _settlementPresenter.isActive()), helping:!!(_helpPresenter && _helpPresenter.isActive()), organizingSpace:!!(_spacePresenter && _spacePresenter.isActive()),
            catalogNavigation:navigation.catalogNavigation,
            returnNavigation:navigation.returnNavigation,
            returnNavigationError:navigation.returnNavigationError,
            inventory:_inventoryCoordinator.debugState(),
            inventorySurface:_inventoryAdapter.getReceipt(),
            mux:_mux.debugState()};
    }};
})();
