/** 合成工作台 — 左侧配方目录，右侧 Flash 权威预览与一次性提交。 */
var CraftingPanel = (function() {
    'use strict';
    var _shellEl, _shell, _catalogView, _detailView, _catalogRenderer, _detailPresenter;
    var _mode = 'recipes', _materials = null, _materialRequestSeq = 0;
    var _materialSnapshotIntentGeneration = 0, _materialSessionVersion = 0,
        _materialSnapshotId = '';
    var _category = '', _snapshot = null, _preview = null, _previewCheckpoint = null, _selectedIndex = -1, _craftCount = 1;
    var _busy = false, _previewBusy = false, _planBusy = false,
        _organizerBusy = false, _organizerMounted = false;
    var _planFocusRecipeId = '', _planFocusAction = '', _planFeedback = null;
    var _needsReconcile = false, _needsRefresh = false, _reconcileEpoch = 0, _generation = 0;
    var _previewFlight = null, _previewQueued = null, _checkpointRetryIntent = null;
    var _scaleHandle = null, _retryButton = null, _organizerButton = null, _craftableToggle = null, _tooltipCache = {};
    var _inspector = null, _tooltipScope = null;
    var _filterTree = null, _filterNavigator = null, _filterPath = [];
    var _craftableOnly = false;
    var _densityController = null, _helpAction = null, _densityToggle = null;
    var _returnCharacterBuildButton = null, _returnNavigationTimer = null;
    var _returnMaterialsButton = null, _materialRecipeReturn = null;
    var _panelInstanceId = '', _canReturnCharacterBuild = false;
    var _recipeSnapshotGeneration = 0, _recipeSnapshotCallId = '',
        _recipeSnapshotIntent = null;
    var _materialShopNavigation = null, _materialShopNavigationTimer = null,
        _materialShopNavigationGeneration = 0, _materialShopNavigationSequence = 0;
    var _procurementNavigation = null, _procurementNavigationTimer = null,
        _procurementNavigationGeneration = 0, _procurementNavigationSequence = 0;
    var _nestedRecipeNavigation = null, _nestedRecipeNavigationGeneration = 0;
    var _config = (typeof window !== 'undefined' && window.__CRAFTING_CONFIG__) || {};
    var ORGANIZER_DEPS = [
        'modules/inventory-runtime.js',
        'modules/inventory-ui.js',
        'modules/inventory-workbench-config.js',
        'modules/inventory-workbench-quick-transfer.js',
        'modules/inventory-workbench-owned-view.js',
        'modules/inventory-storage-workbench.js',
        'modules/crafting-inventory-organizer.js'
    ];
    var _mux = new CraftingRuntime.RequestMux({
        send:function(message) { return Bridge.send(message); },
        timeoutMs:_config.requestTimeoutMs,
        sessionNonce:_config.sessionNonce
    });
    Bridge.on('panel_resp', handleMaterialShopNavigationFailure);
    Bridge.on('panel_resp', handleProcurementShopNavigationFailure);

    Panels.register('crafting', {
        create:createDOM,
        onOpen:onOpen,
        onRebind:onRebind,
        onClose:cleanup,
        onRequestClose:requestClose,
        onForceClose:function() { cleanup(); toast('连接断开，工作台已关闭'); }
    });

    function createDOM() {
        _shellEl = document.createElement('div');
        _shellEl.className = 'panel-scale-shell crafting-scale-shell';
        return _shellEl;
    }

    function buildDOM() {
        disposeFilterNavigator();
        if (_materials) { _materials.destroy(); _materials = null; }
        if (_densityController) { _densityController.destroy(); _densityController = null; }
        if (_helpAction) { _helpAction.destroy(); _helpAction = null; }
        if (_detailPresenter) { _detailPresenter.destroy(); _detailPresenter = null; }
        if (_shell) _shell.destroy();
        Workbench.clearElement(_shellEl);
        _shell = new Workbench.DualPaneShell({
            profile:_mode === 'materials' ? 'archive-reference' : 'catalog-decision',
            title:_mode === 'materials' ? '材料档案' : (_category || '合成工作台'),
            subtitle:_mode === 'materials' ? '来源与用途' : '权威预览',
            status:'同步中',
            leftLabel:_mode === 'materials' ? '材料目录' : '配方目录',
            rightLabel:_mode === 'materials' ? '来源与用途' : '合成详情',
            flowLabel:_mode === 'materials' ? '检索' : '核算'
        });
        var root = _shell.getRoot();
        root.classList.add('kshop-workbench', 'crafting-panel');
        root.setAttribute('data-workbench-skin', 'crafting');
        root.setAttribute('data-crafting-view', _mode);
        _shellEl.appendChild(root);
        if (_mode === 'materials') setMaterialsMetric('loading');

        _retryButton = document.createElement('button');
        _retryButton.type = 'button'; _retryButton.className = 'workbench-mode-btn warning';
        _retryButton.textContent = '重新核对'; _retryButton.addEventListener('click', reconcile);
        _shell.addHeaderAction(_retryButton);
        _organizerButton = null;
        if (_mode !== 'materials') {
            _organizerButton = document.createElement('button');
            _organizerButton.type = 'button'; _organizerButton.className = 'workbench-mode-btn crafting-organizer-btn';
            _organizerButton.textContent = '背包 / 战备箱';
            _organizerButton.setAttribute('aria-label', '切换到背包—战备箱整理；返回后会重新核算当前配方');
            _organizerButton.addEventListener('click', openOrganizer);
            _shell.addHeaderAction(_organizerButton);
        }
        _returnMaterialsButton = null;
        if (_mode === 'recipes' && _materialRecipeReturn) {
            _returnMaterialsButton = document.createElement('button');
            _returnMaterialsButton.type = 'button';
            _returnMaterialsButton.className =
                'workbench-mode-btn crafting-return-materials-btn';
            _returnMaterialsButton.textContent = '← 返回材料';
            _returnMaterialsButton.setAttribute(
                'aria-label', '返回材料档案并重新选中来源材料');
            _returnMaterialsButton.setAttribute('data-audio-cue', 'back');
            _returnMaterialsButton.addEventListener('click', returnToMaterials);
            _shell.addHeaderAction(_returnMaterialsButton);
        }
        _densityToggle = null;
        _densityController = new Workbench.GridDensityController({
            panelId:_mode === 'materials' ? 'crafting-materials' : 'crafting-recipes',
            defaultMode:_mode === 'materials' ? 'compact' : 'full'
        });
        root.setAttribute('data-layout-mode', _densityController.mode);
        _densityToggle = _densityController.createToggle(function(mode) {
            root.setAttribute('data-layout-mode', mode);
        });
        _shell.addHeaderAction(_densityToggle);
        _returnCharacterBuildButton = null;
        if (_canReturnCharacterBuild) {
            _returnCharacterBuildButton = document.createElement('button');
            _returnCharacterBuildButton.type = 'button';
            _returnCharacterBuildButton.className =
                'workbench-mode-btn crafting-return-character-btn';
            _returnCharacterBuildButton.textContent = '← 返回装备';
            _returnCharacterBuildButton.setAttribute(
                'aria-label', '返回角色构筑装备并重新读取当前装备');
            _returnCharacterBuildButton.setAttribute('data-audio-cue', 'back');
            _returnCharacterBuildButton.addEventListener(
                'click', requestCharacterBuild);
            _shell.addHeaderAction(_returnCharacterBuildButton);
        }
        _helpAction = new WorkbenchComponents.HelpAction({
            shell:_shell,
            spec:_mode === 'materials' ? {
            kind:'crafting-materials-help',
            ariaLabel:'查看材料档案帮助',
            title:'材料档案帮助',
            message:'浏览与筛选\n• 完整档案可沿“类型”或“用途”树逐层浏览；一种材料可能出现在多条路径，但结果只显示一张卡。\n• 搜索框、“已持有”和“有用途”会与当前树路径组合筛选；排序可切换档案顺序、持有数、名称或用途数，新开档案恢复档案顺序。\n• “持有种类”统计整个可信目录，不随搜索、筛选或排序变化；旧版兼容视图会持续提示并停用分类树与排序。\n• 紧凑模式以图标为主，完整模式同时显示类型、持有量、来源数和用途数。',
            detail:'查看来源与用途\n• 右侧把 authored“档案摘要”和随存档变化的“已发现来源”分开显示；尚未发现不等于没有来源。\n• 选择左侧材料后，结构化来源按档案顺序列出掉落敌人、关卡、任务或商店；同一敌人或关卡的每条掉落配置都会单独显示。\n• 敌人显示名义概率，关卡显示默认分支基准概率，两者都不是本次实际概率。\n• “会用在哪里”列出引用该材料的合成项目及每份需求。方向键在网格移动；Esc 会先关闭排序菜单、清空已聚焦的搜索，再在分类树内返回一级。',
            actions:[{id:'close', label:'知道了', primary:true, audioCue:'back'}]
        } : {
            kind:'crafting-help',
            ariaLabel:'查看合成工作台帮助',
            title:'合成工作台帮助',
            message:'选择配方后，右侧会显示权威材料、费用、容量与产物预览。批量配方可用 − / +、“最大”、数字输入或滑杆选择 1–99 份；99 是单次原子提交的协议保护上限，不是物品持有上限。核算期间仍可继续调整，提交会等最新份数核算完成。',
            detail:'完整模式显示当前总持有量与位置明细；紧凑模式固定每行 10 个图标，适合同屏浏览成套配方。待合成标记两侧的 − / + 可设置 0–99 件，金币商店与 K 点商城会按标记数量高亮仍需购买的材料；进行中任务的提交/持有物资也会纳入高亮。缺失材料旁的扳手可前往它的合成配方：同分类直接定位，跨分类会先读取并核对目标配方。\n数字输入按 Enter 确认、按 Esc 撤回未确认文字。滑杆可用方向键逐份调整，Shift + 方向键每次 5 份，Page Up / Page Down 跨数量级，Home / End 到两端。“只看可合成”只筛选当前目录；“背包 / 战备箱”返回后会重新核算原配方。',
            actions:[{id:'close', label:'知道了', primary:true, audioCue:'back'}]
        }});
        var close = document.createElement('button');
        close.type = 'button'; close.className = 'workbench-close-btn'; close.textContent = '×';
        close.setAttribute('aria-label', _mode === 'materials' ? '关闭材料档案' : '关闭合成工作台');
        close.setAttribute('data-audio-cue', 'back');
        close.addEventListener('click', function() { requestClose('header'); });
        _shell.addHeaderAction(close);

        if (_mode === 'materials') {
            _catalogRenderer = null;
            _craftableToggle = null;
            _materials = CraftingMaterials.create({
                iconHtml:iconHtml,
                staticIconUrl:staticIconUrl,
                bindTooltip:bindTooltip,
                onSelect:requestMaterialDetail,
                onSelectionChange:function() { invalidateMaterialUseIntent(true); },
                onOpenRecipe:function(use, opener) {
                    return requestMaterialUseSnapshot('recipe', use, opener);
                },
                onInspectUse:function(use, opener) {
                    return requestMaterialUseSnapshot('inspect', use, opener);
                },
                onOpenShop:function(source, opener) {
                    return requestMaterialShopNavigation(source, opener);
                },
                onRetry:function() { refreshMaterialsSnapshot(); },
                densityController:_densityController
            });
            _catalogView = _materials.catalogView;
            _detailView = _materials.detailView;
        } else {
            _catalogView = createCatalogView();
            _detailView = createDetailView();
        }
        _shell.setDefault('L', _catalogView); _shell.setDefault('R', _detailView);
        _shell.mountInitial(_catalogView, _detailView);
        refreshControls();
    }

    function createCatalogView() {
        var root = document.createElement('div'); root.className = 'workbench-view crafting-catalog-view';
        var chrome = new Workbench.ViewChrome({title:'配方目录', kicker:_category, meta:'同步中'});
        _filterNavigator = new ItemFilter.FilterNavigator({
            tree:ItemFilter.build([]), path:[], presentation:'drilldown', allLabel:'全部配方',
            ariaLabel:'合成产物分类', visualStyle:'catalog', breadcrumbHost:chrome.breadcrumbHost,
            onChange:onFilterChange
        });
        var toolbar = document.createElement('div'); toolbar.className = 'crafting-catalog-toolbar';
        _craftableToggle = document.createElement('button');
        _craftableToggle.type = 'button';
        _craftableToggle.className = 'item-filter-option item-filter-control crafting-craftable-toggle';
        _craftableToggle.setAttribute('aria-pressed', 'false');
        _craftableToggle.innerHTML = '<span>只看可合成</span><small>0</small>';
        _craftableToggle.addEventListener('click', toggleCraftableOnly);
        toolbar.appendChild(_filterNavigator.root); toolbar.appendChild(_craftableToggle);
        chrome.setToolbar(toolbar);
        _catalogRenderer = new Workbench.GridRenderer({
            className:'crafting-catalog-grid', emptyText:'当前筛选无可用配方；返回上级分类或关闭“只看可合成”',
            keyOf:function(item) { return item.recipeIndex; },
            renderItem:renderRecipeCard,
            bindItem:bindRecipeCard
        });
        if (_densityController) _densityController.register(_catalogRenderer);
        root.appendChild(chrome.root); root.appendChild(_catalogRenderer.root);
        return {instanceKey:'crafting:catalog', instancePolicy:'singletonByBinding', allowedSlots:['L'],
            viewKind:'catalog', root:root, chrome:chrome,
            mount:function(container) { container.appendChild(root); },
            unmount:function() { if (root.parentNode) root.parentNode.removeChild(root); },
            render:renderCatalog};
    }

    function createDetailView() {
        _detailPresenter = new CraftingDetailPresenter.Presenter({
            document:document,
            iconHtml:iconHtml,
            bindTooltip:bindTooltip,
            releaseTooltips:releaseTooltipTree,
            renderMaterialRow:renderMaterialRow,
            onInspect:openInspector,
            onQuantityChange:setCraftCount,
            onPlanToggle:toggleSelectedPlan,
            onPlanAdjust:adjustSelectedPlan,
            onCommit:commitCraft,
            onRender:renderDetail
        });
        return _detailPresenter.getView();
    }

    function renderRecipeCard(recipe) {
        var ready = recipe.canCraftOne === true;
        var node = document.createElement('button'); node.type = 'button';
        node.className = 'crafting-recipe-card ' + (ready ? 'craftable' : 'blocked');
        node.setAttribute('data-availability', recipe.availability || 'material_missing');
        var output = recipe.output || {};
        var icon = document.createElement('span'); icon.className = 'crafting-card-icon';
        icon.innerHTML = iconHtml(output.icon, 'kshop-icon');
        var copy = document.createElement('span'); copy.className = 'crafting-card-copy';
        var name = document.createElement('b'); name.textContent = output.displayName || '未命名产物';
        var title = document.createElement('span'); title.textContent = recipe.title || '';
        var meta = document.createElement('small');
        var cost = recipe.baseCost || {};
        meta.textContent = '材料 ' + Number(recipe.materialCount || 0) + ' · ' + costText(cost);
        copy.appendChild(name); copy.appendChild(title); copy.appendChild(meta);
        var availability = document.createElement('span');
        availability.className = 'crafting-card-availability ' + (ready ? 'ready' : 'blocked');
        availability.textContent = ready ? '可合成' : availabilityText(recipe.availability);
        availability.setAttribute('aria-label', ready ? '当前资源可合成 1 份' : errorMessage(recipe.availability));
        var owned = document.createElement('span');
        owned.className = 'crafting-card-owned';
        owned.textContent = formatNumber(recipe.owned && recipe.owned.total);
        owned.setAttribute('data-owned', String(Number(recipe.owned && recipe.owned.total || 0)));
        owned.setAttribute('aria-label', ownedSummaryText(recipe.owned));
        var planned = document.createElement('span');
        planned.className = 'crafting-card-planned';
        planned.hidden = !(Number(recipe.plannedCrafts) > 0);
        planned.textContent = '标 ' + Number(recipe.plannedCrafts || 0);
        node.setAttribute('aria-label', String(output.displayName || '未命名产物')
            + '，当前持有 ' + Number(recipe.owned && recipe.owned.total || 0)
            + (Number(recipe.plannedCrafts) > 0
                ? '，已标记 ' + Number(recipe.plannedCrafts) + ' 份' : '')
            + '，' + (ready ? '可合成' : availabilityText(recipe.availability)));
        node.appendChild(icon); node.appendChild(copy); node.appendChild(owned);
        node.appendChild(planned); node.appendChild(availability); return node;
    }

    function bindRecipeCard(node, recipe) {
        node.addEventListener('click', function() { selectRecipe(Number(recipe.recipeIndex)); });
        bindTooltip(node, recipe.output || {});
    }

    function renderCatalog(renderOptions) {
        var recipes = _snapshot && _snapshot.recipes ? _snapshot.recipes : [];
        var visible = filteredRecipes(recipes);
        var craftableCount = recipes.filter(function(recipe) { return recipe.canCraftOne === true; }).length;
        if (_catalogView) _catalogView.chrome.setMeta(recipes.length
            ? '可合成 ' + craftableCount + ' / ' + recipes.length + ' · 显示 ' + visible.length
            : '同步中');
        if (_craftableToggle) {
            _craftableToggle.classList.toggle('active', _craftableOnly);
            _craftableToggle.setAttribute('aria-pressed', _craftableOnly ? 'true' : 'false');
            var count = _craftableToggle.querySelector('small'); if (count) count.textContent = String(craftableCount);
        }
        if (_catalogRenderer) {
            _catalogRenderer.setSelectedKey(_selectedIndex >= 0 ? String(_selectedIndex) : null);
            _catalogRenderer.render(visible, renderOptions);
        }
    }

    function rebuildFilterTree() {
        var recipes = _snapshot && _snapshot.recipes ? _snapshot.recipes : [];
        var categoryTree = ItemFilter.build(recipes, function(recipe) { return ItemFilter.catalogPath(recipe.output || {}); });
        var setTree = ItemFilter.buildSetTree(recipes.map(function(recipe) { return recipe.output || {}; }));
        _filterTree = setTree.children.length ? ItemFilter.branchTree([
            {id:'category', label:'类别', tree:categoryTree},
            {id:'set', label:'套装', tree:setTree}
        ], recipes.length) : categoryTree;
        _filterPath = ItemFilter.validPath(_filterTree, _filterPath);
        if (_filterNavigator) _filterNavigator.setModel(_filterTree, _filterPath);
    }

    function filteredRecipes(recipes) {
        return recipes.filter(function(recipe) {
            var path = _filterPath || [], item = recipe.output || {}, matches = true;
            if (path[0] === 'category') matches = ItemFilter.matchesPath(item, path.slice(1), ItemFilter.catalogPath);
            else if (path[0] === 'set') matches = path.length === 1
                ? ItemFilter.setPath(item).length > 0
                : ItemFilter.matchesPath(item, path.slice(1), ItemFilter.setPath);
            else if (path.length) matches = ItemFilter.matchesPath(item, path, ItemFilter.catalogPath);
            return matches
                && (!_craftableOnly || recipe.canCraftOne === true);
        });
    }

    function onFilterChange(path) {
        if (_busy || _previewBusy || _planBusy || _organizerBusy
                || _procurementNavigation || _nestedRecipeNavigation) return;
        _filterPath = path.slice();
        cue('select');
        applyCatalogFilter();
    }

    function toggleCraftableOnly() {
        if (_busy || _previewBusy || _planBusy || _organizerBusy
                || _procurementNavigation || _nestedRecipeNavigation) return;
        _craftableOnly = !_craftableOnly;
        cue('toggle');
        applyCatalogFilter();
    }

    function applyCatalogFilter() {
        var visible = filteredRecipes(_snapshot && _snapshot.recipes ? _snapshot.recipes : []);
        if (!visible.some(function(recipe) { return Number(recipe.recipeIndex) === _selectedIndex; })) {
            _selectedIndex = visible.length ? Number(visible[0].recipeIndex) : -1;
            _craftCount = 1; _preview = null; clearPreviewCheckpoint();
            renderCatalog({preserveScroll:false}); renderDetail({preserveScroll:false});
            if (_selectedIndex >= 0) requestPreview(); else refreshControls();
            return;
        }
        renderCatalog({preserveScroll:false});
    }

    function selectRecipe(recipeIndex) {
        if (_busy || _planBusy || _procurementNavigation || _nestedRecipeNavigation
                || recipeIndex < 0) return;
        _selectedIndex = recipeIndex; _craftCount = 1; _preview = null; clearPreviewCheckpoint();
        if (_catalogRenderer) _catalogRenderer.setSelectedKey(String(recipeIndex));
        cue('select');
        renderDetail({preserveScroll:false}); requestPreview();
    }

    function requestPreview() {
        if (_selectedIndex < 0 || !_category) return false;
        var intent = {
            generation:_generation,
            category:_category,
            recipeIndex:_selectedIndex,
            craftCount:_craftCount,
            revision:authorityRevision(_snapshot),
            reconcileEpoch:_reconcileEpoch,
            isReconcileProbe:_needsReconcile
        };
        if (_previewFlight && samePreviewIntent(_previewFlight, intent)) {
            // The latest desired value returned to the in-flight intent, so a
            // superseded queued value must not run afterward and invalidate it.
            _previewQueued = null;
            return true;
        }
        if (_previewQueued && samePreviewIntent(_previewQueued, intent)) return true;
        _previewQueued = intent;
        _previewBusy = true;
        renderDetail();
        refreshControls();
        dispatchPreviewIntent();
        return true;
    }

    function dispatchPreviewIntent() {
        if (_previewFlight || !_previewQueued) return false;
        var intent = _previewQueued;
        _previewQueued = null;
        _previewFlight = intent;
        request('preview', {
            category:intent.category,
            recipeIndex:intent.recipeIndex,
            craftCount:intent.craftCount
        }, function(response) {
            completePreviewIntent(intent, response);
        });
        return true;
    }

    function completePreviewIntent(intent, response) {
        if (_previewFlight !== intent) return;
        _previewFlight = null;
        var isCurrent = intent.generation === _generation
            && intent.category === _category
            && intent.recipeIndex === _selectedIndex
            && intent.craftCount === _craftCount
            && intent.reconcileEpoch === _reconcileEpoch
            && (!_needsReconcile || intent.isReconcileProbe)
            && sameIntentRevision(intent.revision, authorityRevision(_snapshot));
        var exactResponse = !response.success || responseMatchesPreviewIntent(response, intent);

        // Superseded read replies are deliberately silent: they cannot change
        // the checkpoint, controls, focus, scroll, balance or player messaging.
        if (!isCurrent || !exactResponse) {
            if (_previewQueued) {
                dispatchPreviewIntent();
            } else {
                _previewBusy = false;
                renderDetail();
                refreshControls();
            }
            return;
        }

        _previewBusy = !!_previewQueued;
        var retryRestoredPreview = false;
        if (response.success) {
            _preview = response;
            rememberPreview(response, intent.recipeIndex, intent.craftCount);
            _needsReconcile = false;
            _needsRefresh = false;
            applyBalance(response.balance);
        } else if (requiresReconcile(response)) {
            _preview = null;
            clearPreviewCheckpoint();
            enterNeedsReconcile();
            toast(errorMessage(response.error));
        } else if (requiresAuthorityRefresh(response)) {
            _preview = null;
            clearPreviewCheckpoint();
            _needsRefresh = true;
            toast(errorMessage(response.error));
        } else {
            if (!_needsReconcile && !restorePreviewCheckpoint(intent.recipeIndex)) {
                _preview = null;
            } else if (_preview && !previewMatchesCurrent()
                    && !samePreviewIntent(_checkpointRetryIntent, intent)) {
                _checkpointRetryIntent = Object.assign({}, intent);
                retryRestoredPreview = true;
            }
            toast(errorMessage(response.error));
        }
        renderDetail();
        refreshControls();
        if (retryRestoredPreview) {
            requestPreview();
        } else if (_previewQueued && !_needsReconcile && !_needsRefresh) {
            _previewBusy = true;
            dispatchPreviewIntent();
        } else if (isCurrent && exactResponse && !response.success
                && requiresAuthorityRefresh(response)) {
            refreshSnapshot(intent.recipeIndex, intent.craftCount);
        }
    }

    function renderDetail(renderOptions) {
        if (!_detailPresenter) return;
        renderOptions = renderOptions || {};
        var recipe = findRecipe(_selectedIndex);
        var selected = !!recipe && _selectedIndex >= 0;
        var preview = _preview;
        var output = preview && preview.output;
        var previewCurrent = previewMatchesCurrent();
        var cost = preview && preview.cost || {};
        var canCommit = !_busy && !_previewBusy && !_planBusy && !_organizerBusy
            && !_procurementNavigation && !_nestedRecipeNavigation
            && !_needsReconcile && !_needsRefresh
            && previewCurrent && preview.canCommit === true && !!preview.craftToken;
        var commitStatus = detailCommitStatus(selected, preview, previewCurrent);
        var commitState = canCommit ? 'ready'
            : _needsReconcile || _needsRefresh || preview && preview.blockingError ? 'error'
                : _previewBusy || _busy ? 'busy' : 'blocked';
        var previewState = _needsReconcile || _needsRefresh ? 'error'
            : _previewBusy ? 'updating'
                : previewCurrent ? 'ready' : preview ? 'stale' : selected ? 'waiting' : 'empty';
        var recipeOutput = recipe && recipe.output || {};

        _detailPresenter.render({
            preserveScroll:renderOptions.preserveScroll !== false,
            selected:selected,
            title:(output && output.displayName) || recipeOutput.displayName || '合成详情',
            kicker:'权威核算',
            meta:detailMetaText(_snapshot),
            emptyText:_previewBusy ? '正在向 Flash 核算材料与容量…' : '等待权威预览',
            previewState:previewState,
            pending:_previewBusy,
            output:output || null,
            outputMeta:output ? outputMetaSegments(output, recipe && recipe.owned) : [],
            recipeId:recipe && recipe.recipeId || '',
            plannedCrafts:Number(recipe && recipe.plannedCrafts) || 0,
            planLabel:_planBusy ? '同步中…'
                : '待合成 ×' + Number(recipe && recipe.plannedCrafts || 0),
            planPressed:Number(recipe && recipe.plannedCrafts) > 0,
            planDisabled:_planBusy || _busy || _previewBusy || _organizerBusy
                || !!_procurementNavigation || !!_nestedRecipeNavigation
                || _needsReconcile || _needsRefresh,
            planAriaLabel:Number(recipe && recipe.plannedCrafts) > 0
                ? '取消标记 ' + String(recipeOutput.displayName || '当前配方')
                : '标记待合成 ' + String(recipeOutput.displayName || '当前配方'),
            planDecrementAriaLabel:'减少一件待合成标记；当前 '
                + Number(recipe && recipe.plannedCrafts || 0) + ' 件',
            planIncrementAriaLabel:'增加一件待合成标记；当前 '
                + Number(recipe && recipe.plannedCrafts || 0) + ' 件',
            planStatus:_planFeedback && recipe
                    && _planFeedback.recipeId === String(recipe.recipeId || '')
                ? _planFeedback.text : '',
            planStatusKind:_planFeedback && recipe
                    && _planFeedback.recipeId === String(recipe.recipeId || '')
                ? _planFeedback.kind : 'idle',
            materials:preview && preview.materials || [],
            moneyText:formatNumber(cost.money),
            kpointsText:formatNumber(cost.kpoints),
            enoughSpace:!!(preview && preview.enoughSpace),
            batchEligible:!!(recipe && recipe.batchEligible === true),
            craftCount:_craftCount,
            presetMax:preview ? Number(preview.maxCraftCount) || 0 : 0,
            quantityDisabled:_busy || _planBusy || _organizerBusy || !!_procurementNavigation
                || !!_nestedRecipeNavigation
                || _needsReconcile || _needsRefresh,
            canCommit:canCommit,
            commitBusy:_busy || _previewBusy || _planBusy || !!_procurementNavigation
                || !!_nestedRecipeNavigation,
            commitLabel:_busy ? '提交中…' : '确认合成',
            commitStatus:commitStatus,
            commitState:commitState,
            commitAriaLabel:'确认合成 ' + _craftCount + ' 份',
            commitTitle:'确认合成'
        });
        restorePlanButtonFocus(recipe);
    }

    function restorePlanButtonFocus(recipe) {
        if (!_planFocusRecipeId || _planBusy || !recipe
                || String(recipe.recipeId || '') !== _planFocusRecipeId) {
            if (recipe && String(recipe.recipeId || '') !== _planFocusRecipeId) {
                _planFocusRecipeId = '';
                _planFocusAction = '';
            }
            return;
        }
        var action = _planFocusAction === 'decrement' || _planFocusAction === 'increment'
            ? _planFocusAction : 'toggle';
        var button = _detailView && _detailView.root
            ? _detailView.root.querySelector('[data-plan-action="' + action + '"]') : null;
        if (button && button.disabled && action !== 'toggle') {
            button = _detailView.root.querySelector('[data-plan-action="toggle"]');
        }
        if (!button || button.disabled || typeof button.focus !== 'function') return;
        try { button.focus({preventScroll:true}); } catch (error) { button.focus(); }
        _planFocusRecipeId = '';
        _planFocusAction = '';
    }

    function openInspector(output, gender, returnFocusTarget) {
        if (!_shell || typeof CraftingInspector === 'undefined' || !CraftingInspector.open) return false;
        if (typeof PanelTooltip !== 'undefined') PanelTooltip.hide();
        _inspector = CraftingInspector.open({
            shell: _shell,
            output: output,
            gender: typeof gender === 'string' ? gender : _snapshot && _snapshot.gender,
            manifestUrl: _config.inspectorManifestUrl,
            onClose: function() {
                _inspector = null;
                if (returnFocusTarget && returnFocusTarget.isConnected !== false
                        && document.documentElement.contains(returnFocusTarget)
                        && typeof returnFocusTarget.focus === 'function') {
                    returnFocusTarget.focus();
                }
            }
        });
        return !!_inspector;
    }

    function toggleSelectedPlan(event) {
        var recipe = findRecipe(_selectedIndex);
        var current = Number(recipe && recipe.plannedCrafts || 0);
        return setSelectedPlan(current > 0 ? 0 : 1, event);
    }

    function adjustSelectedPlan(delta, event) {
        var recipe = findRecipe(_selectedIndex);
        var current = Number(recipe && recipe.plannedCrafts || 0);
        return setSelectedPlan(current + Number(delta || 0), event);
    }

    function setSelectedPlan(next, event) {
        var recipe = findRecipe(_selectedIndex);
        var procurement = _snapshot && _snapshot.procurement;
        if (_mode !== 'recipes' || !recipe || !recipe.recipeId || !procurement
                || _planBusy || _busy || _previewBusy || _organizerBusy
                || _procurementNavigation || _nestedRecipeNavigation
                || _needsReconcile || _needsRefresh) return false;
        next = Math.max(0, Math.min(99, Math.floor(Number(next) || 0)));
        if (next === Number(recipe.plannedCrafts || 0)) return false;
        var expectedRevision = Number(procurement.revision);
        if (!Number.isInteger(expectedRevision) || expectedRevision < 0) return false;
        _planFocusRecipeId = event && event.currentTarget === document.activeElement
            ? String(recipe.recipeId) : '';
        _planFocusAction = _planFocusRecipeId && event.currentTarget
            ? String(event.currentTarget.getAttribute('data-plan-action') || 'toggle') : '';
        _planFeedback = {recipeId:String(recipe.recipeId), kind:'pending',
            text:'保存中…'};
        _planBusy = true;
        renderDetail();
        refreshControls();
        var preferred = _selectedIndex, preferredCount = _craftCount;
        var issuing = true;
        var callId = request('setPlan', {
            recipeId:String(recipe.recipeId),
            plannedCrafts:next,
            expectedRevision:expectedRevision
        }, function(response) {
            var dispatched = !issuing;
            _planBusy = false;
            if (response.success) {
                if (_snapshot && _snapshot.procurement) {
                    _snapshot.procurement.revision = Number(response.revision);
                }
                var currentRecipe = findRecipe(preferred);
                if (currentRecipe && currentRecipe.recipeId === response.recipeId) {
                    currentRecipe.plannedCrafts = Number(response.plannedCrafts);
                }
                var savedCount = Number(response.plannedCrafts) || 0;
                _planFeedback = {recipeId:String(response.recipeId), kind:'success',
                    text:savedCount > 0
                        ? '已保存，商城按此数量高亮。'
                        : '已取消标记。'};
                toast(savedCount > 0 ? '待合成数量已设为 ' + savedCount + '；相关商店材料将高亮。'
                    : '已取消待合成标记。');
                renderCatalog({preserveScroll:true, forceItemRender:true});
                renderDetail();
                refreshControls();
                return;
            }
            if (isWriteAmbiguous(response, dispatched)
                    || requiresAuthorityRefresh(response)) {
                _needsRefresh = true;
                _planFeedback = {recipeId:String(recipe.recipeId), kind:'pending',
                    text:'正在核对标记结果…'};
                toast(isWriteAmbiguous(response, dispatched)
                    ? '标记结果不明确，正在向 Flash 对账。'
                    : errorMessage(response.error));
                refreshSnapshot(preferred, preferredCount);
                return;
            }
            _planFeedback = {recipeId:String(recipe.recipeId), kind:'error',
                text:'标记未保存：' + errorMessage(response.error)};
            toast(errorMessage(response.error));
            renderDetail();
            refreshControls();
        });
        issuing = false;
        if (!callId) {
            _planBusy = false;
            _planFeedback = {recipeId:String(recipe.recipeId), kind:'error',
                text:'标记未保存：启动器连接不可用。'};
            renderDetail();
            refreshControls();
            return false;
        }
        return true;
    }

    function setCraftCount(value) {
        var recipe = findRecipe(_selectedIndex);
        if (_busy || _planBusy || _organizerBusy || _procurementNavigation
                || _nestedRecipeNavigation
                || _needsReconcile || _needsRefresh
                || !recipe || recipe.batchEligible !== true) return false;
        var next = Math.max(1, Math.min(99, Math.floor(Number(value) || 1)));
        if (next === _craftCount) return false;
        _craftCount = next;
        requestPreview();
        return true;
    }

    function ownedSummaryText(owned) {
        owned = owned || {};
        var parts = [];
        function add(label, value) {
            value = Number(value || 0);
            if (value > 0) parts.push(label + ' ' + formatNumber(value));
        }
        add('背包', owned.bag);
        add('快捷栏', owned.drug);
        add('已装备', owned.equipped);
        add('战备箱', owned.battleBox);
        add('材料栏', owned.material);
        add('情报栏', owned.information);
        return '当前总持有 ' + formatNumber(owned.total)
            + (parts.length ? '（' + parts.join(' · ') + '）' : '');
    }

    function ownedInlineText(owned) {
        owned = owned || {};
        var parts = [];
        function add(label, value) {
            value = Number(value || 0);
            if (value > 0) parts.push(label + ' ' + formatNumber(value));
        }
        add('背包', owned.bag);
        add('快捷栏', owned.drug);
        add('已装备', owned.equipped);
        add('战备箱', owned.battleBox);
        add('材料栏', owned.material);
        add('情报栏', owned.information);
        return '持有 ' + formatNumber(owned.total)
            + (parts.length ? '（' + parts.join(' · ') + '）' : '');
    }

    function outputMetaSegments(output, owned) {
        output = output || {};
        var equipment = output.itemKind === 'equipment';
        var segments = [];
        if (equipment) {
            segments.push({kind:'level', text:'需求等级 ' + Number(output.requiredLevel || 0)});
        } else {
            segments.push({kind:'quantity',
                text:'产出 ×' + Number(output.quantity || output.value || 1)});
        }
        segments.push({kind:'owned', text:ownedInlineText(owned)});
        var enhancement = Number(output.enhancementLevel || 1);
        if (equipment && enhancement > 1) {
            segments.push({kind:'enhancement', text:'强化 +' + enhancement});
        }
        return segments;
    }

    function detailMetaText(snapshot) {
        var note = snapshot && snapshot.note ? String(snapshot.note) : '';
        return note === '改装后的装备默认强化等级为 1'
            ? '提交前会再次校验材料与费用'
            : note || '提交前会再次校验材料与费用';
    }

    function samePreviewIntent(left, right) {
        return !!left && !!right
            && left.generation === right.generation
            && left.category === right.category
            && left.recipeIndex === right.recipeIndex
            && left.craftCount === right.craftCount
            && left.reconcileEpoch === right.reconcileEpoch
            && left.isReconcileProbe === right.isReconcileProbe
            && sameIntentRevision(left.revision, right.revision);
    }

    function authorityRevision(value) {
        if (!value || typeof value !== 'object') return null;
        var keys = ['revision', 'stateRevision', 'snapshotRevision'];
        for (var i = 0; i < keys.length; i++) {
            if (!Object.prototype.hasOwnProperty.call(value, keys[i])) continue;
            var revision = Number(value[keys[i]]);
            if (isFinite(revision)) return revision;
        }
        return null;
    }

    function sameIntentRevision(left, right) {
        if (left == null || right == null) return left == null && right == null;
        return Number(left) === Number(right);
    }

    function matchesExpectedRevision(expected, actual) {
        return expected == null || actual != null && Number(expected) === Number(actual);
    }

    function responseMatchesPreviewIntent(response, intent) {
        return !!response
            && String(response.category || '') === intent.category
            && Number(response.recipeIndex) === intent.recipeIndex
            && Number(response.craftCount) === intent.craftCount
            && matchesExpectedRevision(intent.revision, authorityRevision(response));
    }

    function previewMatchesCurrent() {
        if (!_preview) return false;
        return responseMatchesPreviewIntent(_preview, {
            category:_category,
            recipeIndex:_selectedIndex,
            craftCount:_craftCount,
            revision:authorityRevision(_snapshot)
        });
    }

    function detailCommitStatus(selected, preview, previewCurrent) {
        if (!selected) return '请先选择配方';
        if (_needsReconcile) return '状态需要重新核对，暂不可提交';
        if (_needsRefresh) return '配方状态已变化，正在重新同步';
        if (_nestedRecipeNavigation) return '正在定位嵌套合成配方';
        if (_busy) return '正在提交，请稍候';
        if (_planBusy) return '正在同步待合成标记';
        if (_previewBusy) return '正在核算 ' + _craftCount + ' 份；仍可调整数量';
        if (!preview) return '等待权威预览';
        if (!previewCurrent) {
            return '上次核算为 ' + Number(preview.craftCount || 1)
                + ' 份；当前 ' + _craftCount + ' 份尚未核算';
        }
        return preview.canCommit
            ? '条件满足，可安全提交 ' + _craftCount + ' 份'
            : errorMessage(preview.blockingError);
    }

    function appendMaterialMetric(note, current, required, valueClass) {
        var currentNode = document.createElement('span');
        currentNode.className = valueClass + ' is-current';
        currentNode.textContent = current;
        var separator = document.createElement('span');
        separator.className = 'crafting-material-status-separator';
        separator.textContent = '/';
        var requiredNode = document.createElement('span');
        requiredNode.className = valueClass + ' is-required';
        requiredNode.textContent = required;
        note.appendChild(currentNode);
        note.appendChild(separator);
        note.appendChild(requiredNode);
    }

    function renderMaterialStatus(note, material, procurement) {
        var owned = Math.max(0, Number(material.owned) || 0);
        var required = Math.max(0, Number(material.required) || 0);
        if (material.itemKind !== 'equipment' || material.isQuantity) {
            note.className = 'crafting-material-status is-quantity';
            appendMaterialMetric(note, formatNumber(owned), formatNumber(required),
                'crafting-material-quantity-value');
            if (material.consumed === false) {
                var retained = document.createElement('span');
                retained.className = 'crafting-material-retained';
                retained.textContent = ' · 保留';
                note.appendChild(retained);
            }
            note.setAttribute('data-material-status', material.enough ? 'ready' : 'quantity-shortage');
            var quantityText = '数量：持有 ' + formatNumber(owned)
                + '，需要 ' + formatNumber(required);
            if (material.consumed === false) quantityText += '；该材料不消耗';
            note.setAttribute('aria-label', quantityText);
            return quantityText;
        }

        var totalOwned = procurement ? Math.max(0, Number(procurement.totalOwned) || 0) : owned;
        var requiredEnhancement = procurement
            ? Math.max(0, Number(procurement.requiredEnhancement) || 0) : required;
        if (!requiredEnhancement) requiredEnhancement = Math.max(1, required || 1);
        var totalMaxEnhancement = procurement
            ? Math.max(0, Number(procurement.totalMaxEnhancement) || 0)
            : Math.max(0, Number(material.maxEnhancement) || 0);
        var needsEnhancement = procurement
            ? procurement.needsEnhancement === true
            : totalMaxEnhancement < requiredEnhancement;
        var needsRelocation = procurement && Number(procurement.relocateMissing || 0) > 0;

        note.className = 'crafting-material-status is-equipment';
        if (totalOwned <= 0) {
            note.classList.add('is-missing');
            note.textContent = '缺少装备';
            note.setAttribute('data-material-status', 'equipment-missing');
            note.setAttribute('aria-label', '未持有所需装备');
            return '未持有所需装备';
        }
        if (needsEnhancement || totalMaxEnhancement < requiredEnhancement) {
            note.classList.add('is-enhancement');
            appendMaterialMetric(note, '+' + totalMaxEnhancement, '+' + requiredEnhancement,
                'crafting-material-enhancement-value');
            note.setAttribute('data-material-status', 'enhancement-shortage');
            var enhancementText = '强化度：当前最高 +' + totalMaxEnhancement
                + '，要求 +' + requiredEnhancement;
            note.setAttribute('aria-label', enhancementText);
            return enhancementText;
        }
        if (needsRelocation || !material.enough) {
            note.classList.add('is-relocate');
            var relocation = typeof WorkbenchComponents !== 'undefined'
                && WorkbenchComponents.ProcurementHighlight
                && typeof WorkbenchComponents.ProcurementHighlight.relocation === 'function'
                ? WorkbenchComponents.ProcurementHighlight.relocation(procurement) : null;
            note.textContent = relocation ? relocation.shortText : '合成前需要移回背包';
            note.setAttribute('data-material-status', 'equipment-relocate');
            note.setAttribute('data-relocation-source', relocation
                ? relocation.source : 'unknown');
            var relocationText = relocation ? relocation.detail
                : '这里只是合成前指引，不会自动移动装备；请将所需装备移回背包后再合成';
            note.setAttribute('aria-label', relocationText);
            return relocationText;
        }
        note.classList.add('is-ready');
        note.textContent = '装备满足';
        note.setAttribute('data-material-status', 'ready');
        note.setAttribute('aria-label', '已持有符合强化要求的装备');
        return '已持有符合强化要求的装备';
    }

    function buildAnnotationTooltipHtml(value) {
        return '<div class="crafting-simple-tooltip">'
            + escapeHtml(String(value || '')).replace(/\r?\n/g, '<br>') + '</div>';
    }

    function bindAnnotationTooltip(node, value, key, placement) {
        if (!node || !value || typeof PanelTooltip === 'undefined') return;
        var tooltipBinder = _tooltipScope || PanelTooltip;
        if (!tooltipBinder || typeof tooltipBinder.bindAsync !== 'function') return;
        node.removeAttribute('title');
        node.setAttribute('data-crafting-tooltip', String(value));
        tooltipBinder.bindAsync(node, {
            profile:'simple-tooltip',
            key:'crafting-annotation:' + String(key || value),
            item:String(value),
            renderBasic:buildAnnotationTooltipHtml,
            placement:placement || 'left'
        });
    }

    function renderMaterialRow(material) {
        var row = document.createElement('div'); row.className = 'crafting-material-row ' + (material.enough ? 'ok' : 'bad');
        row.setAttribute('data-material-name', String(material.name || ''));
        var iconSource = document.createElement('span');
        iconSource.innerHTML = iconHtml(material.icon, 'kshop-icon');
        var icon = iconSource.firstElementChild;
        if (!icon) {
            icon = document.createElement('span');
            icon.className = 'kshop-icon-placeholder';
        }
        icon.classList.add('crafting-material-icon');
        var copy = document.createElement('span'); copy.className = 'crafting-material-copy';
        var name = document.createElement('b'); name.textContent = material.displayName || '未命名材料';
        var note = document.createElement('small');
        var procurement = material.procurement || null;
        var noteTooltipText = renderMaterialStatus(note, material, procurement);
        copy.appendChild(name); copy.appendChild(note);
        var sourceActions = null;
        if (!material.enough && Array.isArray(material.craftingSources)
                && material.craftingSources.length) {
            sourceActions = document.createElement('span');
            sourceActions.className = 'crafting-material-source-actions';
            material.craftingSources.forEach(function(source) {
                if (!source) return;
                var craftingButton = document.createElement('button');
                craftingButton.type = 'button';
                craftingButton.className = 'workbench-mode-btn crafting-material-shop-btn '
                    + 'crafting-material-crafting-btn';
                craftingButton.setAttribute('data-procurement-source', 'crafting');
                craftingButton.setAttribute('data-crafting-category', String(source.category || ''));
                craftingButton.setAttribute('data-crafting-recipe-index', String(source.recipeIndex));
                craftingButton.setAttribute('data-crafting-recipe-id', String(source.recipeId || ''));
                craftingButton.textContent = '🔧︎';
                var pending = nestedRecipeTargetMatches(_nestedRecipeNavigation, material, source);
                var canNavigate = canRequestNestedRecipe(material, source);
                craftingButton.disabled = !canNavigate;
                if (pending) craftingButton.setAttribute('aria-busy', 'true');
                var targetLabel = String(source.category || '') + ' · '
                    + String(source.title || material.displayName || material.name || '目标配方');
                craftingButton.setAttribute('aria-label', pending
                    ? '正在定位合成配方：' + targetLabel
                    : '前往合成：' + String(material.displayName || material.name)
                        + '，' + targetLabel);
                craftingButton.addEventListener('click', function() {
                    requestNestedRecipeNavigation(material, source, craftingButton);
                });
                bindAnnotationTooltip(craftingButton,
                    (pending ? '正在定位 · ' : '前往合成 · ') + targetLabel,
                    'crafting-source:' + String(source.recipeId || '')
                        + ':' + String(source.recipeIndex));
                sourceActions.appendChild(craftingButton);
            });
            if (!sourceActions.childNodes.length) sourceActions = null;
        }
        var procurementSummary = typeof WorkbenchComponents !== 'undefined'
            && WorkbenchComponents.ProcurementHighlight
            ? WorkbenchComponents.ProcurementHighlight.summary(procurement) : null;
        if (procurementSummary) {
            row.classList.add(procurementSummary.kind === 'obtain'
                ? 'procurement-needed' : 'procurement-relocate');
            note.classList.add('crafting-material-procurement-note');
            var fullProcurementText = procurementSummary.shortText
                + (procurementSummary.detail ? '\n' + procurementSummary.detail : '');
            if (procurementSummary.kind === 'relocate'
                    && note.getAttribute('data-material-status') === 'equipment-relocate') {
                noteTooltipText = procurementSummary.detail;
            } else noteTooltipText += '\n' + fullProcurementText;
            if (procurementSummary.kind === 'obtain') {
                if (!sourceActions) {
                    sourceActions = document.createElement('span');
                    sourceActions.className = 'crafting-material-source-actions';
                }
                (procurement.sources || []).forEach(function(source) {
                    if (!source) return;
                    if (source.kind === 'npcshop') {
                        var shopButton = document.createElement('button');
                        shopButton.type = 'button';
                        shopButton.className = 'workbench-mode-btn crafting-material-shop-btn';
                        shopButton.setAttribute('data-procurement-source', 'npcshop');
                        var canNavigate = canRequestRecipeShopNavigation(material, source);
                        var directNavigation = hasDirectRecipeShopNavigation();
                        var destination = String(source.label || source.shopId || '金币商店');
                        var shopStateText = canNavigate ? '前往购买'
                            : directNavigation ? '核算中…' : '需摩托车';
                        shopButton.setAttribute('data-shop-label', destination);
                        shopButton.setAttribute('data-shop-state', canNavigate ? 'ready'
                            : directNavigation ? 'pending' : 'locked');
                        shopButton.textContent = destination.charAt(0).toUpperCase();
                        var shopImage = document.createElement('img');
                        shopImage.alt = '';
                        shopImage.setAttribute('aria-hidden', 'true');
                        shopButton.appendChild(shopImage);
                        shopButton.disabled = !canNavigate;
                        shopButton.setAttribute('aria-label', canNavigate
                            ? '前往 ' + destination
                                + ' 购买 ' + String(material.displayName || material.name)
                            : directNavigation
                                ? destination + ' 商店来源正在核算，请稍候'
                                : '需要摩托车或越野车基建，才能直接前往 '
                                    + destination + ' 购买 '
                                    + String(material.displayName || material.name));
                        shopButton.addEventListener('click', function() {
                            requestRecipeShopNavigation(material, source, shopButton);
                        });
                        bindAnnotationTooltip(shopButton, destination + ' · ' + shopStateText,
                            'shop:' + String(source.shopId || destination));
                        if (typeof ShopPortraits !== 'undefined' && ShopPortraits
                                && typeof ShopPortraits.mount === 'function') {
                            try {
                                var portraitMount = ShopPortraits.mount(
                                    shopButton, shopImage, source.shopId);
                                if (portraitMount && typeof portraitMount.catch === 'function') {
                                    portraitMount.catch(function() {});
                                }
                            } catch (ignore) {}
                        }
                        sourceActions.appendChild(shopButton);
                    } else if (source.kind === 'kshop') {
                        var kshopButton = document.createElement('button');
                        kshopButton.type = 'button';
                        kshopButton.className = 'workbench-mode-btn crafting-material-shop-btn';
                        kshopButton.setAttribute('data-procurement-source', 'kshop');
                        var canOpenKShop = canRequestRecipeShopNavigation(material, source);
                        var directKShopNavigation = hasDirectRecipeShopNavigation();
                        var kshopStateText = canOpenKShop ? '前往购买'
                            : directKShopNavigation ? '核算中…' : '需摩托车';
                        kshopButton.setAttribute('data-shop-label', 'K 点商城');
                        kshopButton.setAttribute('data-shop-state', canOpenKShop ? 'ready'
                            : directKShopNavigation ? 'pending' : 'locked');
                        kshopButton.classList.add('crafting-material-kshop-btn');
                        kshopButton.textContent = 'K';
                        kshopButton.disabled = !canOpenKShop;
                        kshopButton.setAttribute('aria-label', canOpenKShop
                            ? '前往 K 点商城购买 '
                                + String(material.displayName || material.name)
                            : directKShopNavigation
                                ? 'K 点商城来源正在核算，请稍候'
                                : '需要摩托车或越野车基建，才能直接前往 K 点商城');
                        kshopButton.addEventListener('click', function() {
                            requestRecipeShopNavigation(material, source, kshopButton);
                        });
                        bindAnnotationTooltip(kshopButton, 'K 点商城 · ' + kshopStateText,
                            'shop:kshop');
                        sourceActions.appendChild(kshopButton);
                    }
                });
                if (!sourceActions.childNodes.length) sourceActions = null;
            }
        }
        row.appendChild(icon); row.appendChild(copy);
        if (sourceActions) row.appendChild(sourceActions);
        if (material.enough) {
            var mark = document.createElement('span');
            mark.className = 'crafting-material-mark';
            mark.textContent = '✓';
            row.appendChild(mark);
        }
        bindAnnotationTooltip(note, noteTooltipText, 'material:' + String(material.name || ''));
        bindTooltip(row, material); return row;
    }

    function commitCraft() {
        if (_busy || _planBusy || _previewBusy || _procurementNavigation
                || _nestedRecipeNavigation
                || _needsReconcile || _needsRefresh || !previewMatchesCurrent()
                || !_preview.canCommit || !_preview.craftToken || !_preview.acceptedPlan) return;
        _busy = true; refreshControls(); renderDetail();
        var preferred = _selectedIndex, preferredCount = _craftCount;
        var expectedAcceptedPlan = _preview.acceptedPlan;
        var issuing = true;
        var callId = request('commit', {category:_category, expectedCraftToken:_preview.craftToken}, function(response) {
            var dispatched = !issuing;
            _busy = false;
            // 权威结果音在响应回调播放，附带的 toast 保持静默（契约 §5.3/§6）
            if (response.success) {
                if (!sameJson(response.acceptedPlan, expectedAcceptedPlan)) {
                    enterNeedsReconcile();
                    toast('提交回包与权威预览不一致，正在向 Flash 对账。');
                    cue('unknown');
                    requestPreview(); return;
                }
                toast('已合成 ' + response.crafted.displayName);
                cue('success');
                _preview = null; clearPreviewCheckpoint(); refreshSnapshot(preferred, preferredCount); return;
            }
            if (isWriteAmbiguous(response, dispatched)) {
                enterNeedsReconcile(); toast('提交结果不明确，正在向 Flash 对账。');
                cue('unknown');
                requestPreview();
            } else if (requiresAuthorityRefresh(response)) {
                toast(errorMessage(response.error)); cue('rejected'); _preview = null; clearPreviewCheckpoint();
                _needsRefresh = true; refreshSnapshot(preferred, preferredCount); return;
            } else {
                toast(errorMessage(response.error)); cue('rejected');
            }
            renderDetail(); refreshControls();
        });
        issuing = false;
        if (!callId) { _busy = false; renderDetail(); refreshControls(); }
    }

    function refreshSnapshot(preferredIndex, preferredCount) {
        if (!_category) return false;
        _shell.setStatus('同步中', 'loading');
        if (_retryButton) _retryButton.disabled = true;
        var generation = _generation, previousIndex = _selectedIndex;
        return !!request('snapshot', {category:_category}, function(response) {
            if (generation !== _generation) return;
            if (!response.success) {
                if (requiresReconcile(response)) {
                    _preview = null; clearPreviewCheckpoint(); enterNeedsReconcile(); _needsRefresh = false;
                } else if (!_needsReconcile) _needsRefresh = true;
                toast(errorMessage(response.error)); renderDetail(); refreshControls(); return;
            }
            _snapshot = response; _needsRefresh = false; applyBalance(response.balance); rebuildFilterTree();
            var recipes = response.recipes || [], visible = filteredRecipes(recipes);
            var next = Number(preferredIndex);
            if (isNaN(next) || next < 0 || !visible.some(function(recipe) { return Number(recipe.recipeIndex) === next; })) {
                next = visible.length ? Number(visible[0].recipeIndex) : -1;
            }
            var selectionChanged = next !== previousIndex;
            _selectedIndex = next;
            var selectedRecipe = findRecipe(next);
            _craftCount = selectedRecipe && selectedRecipe.batchEligible === true
                ? Math.max(1, Math.min(99, Math.floor(Number(preferredCount) || 1))) : 1;
            _preview = null; clearPreviewCheckpoint();
            renderCatalog({preserveScroll:!selectionChanged});
            renderDetail({preserveScroll:!selectionChanged});
            if (next >= 0) requestPreview(); else refreshControls();
        });
    }

    function refreshMaterialsSnapshot(preferredName) {
        if (_materialShopNavigation) return false;
        invalidateMaterialUseIntent(true);
        _shell.setStatus('同步中', 'loading');
        setMaterialsMetric('loading');
        if (_materials && typeof _materials.setCatalogLoading === 'function') {
            _materials.setCatalogLoading();
        }
        if (_retryButton) _retryButton.disabled = true;
        _previewBusy = true;
        var generation = _generation;
        var snapshotIntent = ++_materialSnapshotIntentGeneration;
        ++_materialRequestSeq;
        var requestedVersion = _materialSessionVersion || 2;
        return !!request('materials', {v:requestedVersion}, function(response) {
            if (generation !== _generation || snapshotIntent !== _materialSnapshotIntentGeneration
                    || _mode !== 'materials') return;
            _previewBusy = false;
            if (!response.success) {
                _needsRefresh = true;
                setMaterialsMetric('error');
                if (_materials) _materials.setCatalogError(errorMessage(response.error));
                toast(errorMessage(response.error));
                refreshControls();
                return;
            }
            var responseVersion = Number(response.v);
            if ((responseVersion !== 1 && responseVersion !== 2)
                    || _materialSessionVersion && responseVersion !== _materialSessionVersion) {
                _needsRefresh = true;
                setMaterialsMetric('error');
                if (_materials) _materials.setCatalogError('材料协议版本发生变化，请关闭后重试。');
                toast('材料协议版本发生变化，请关闭后重试。');
                refreshControls();
                return;
            }
            if (!_materialSessionVersion) _materialSessionVersion = responseVersion;
            _materialSnapshotId = responseVersion === 2 ? String(response.snapshotId || '') : '';
            _snapshot = response;
            _needsRefresh = false;
            if (_materials) _materials.setSnapshot(response, preferredName);
            setMaterialsMetric('ready', response.materials);
            refreshControls();
        });
    }

    function requestMaterialDetail(itemName) {
        if (_materialShopNavigation || _mode !== 'materials'
                || !itemName || !_materialSessionVersion) return false;
        invalidateMaterialUseIntent(true);
        var generation = _generation;
        var snapshotIntent = _materialSnapshotIntentGeneration;
        var snapshotId = _materialSnapshotId;
        var requestSeq = ++_materialRequestSeq;
        _previewBusy = true;
        refreshControls();
        var payload = {v:_materialSessionVersion, itemName:String(itemName)};
        if (_materialSessionVersion === 2) payload.snapshotId = snapshotId;
        return !!request('materialDetail', payload, function(response) {
            if (generation !== _generation || requestSeq !== _materialRequestSeq
                    || snapshotIntent !== _materialSnapshotIntentGeneration
                    || snapshotId !== _materialSnapshotId || _mode !== 'materials') return;
            _previewBusy = false;
            if (!_materials || _materials.getSelectedName() !== String(itemName)) {
                refreshControls();
                return;
            }
            if (!response.success) {
                var requiresCatalogRefresh = response.error === 'stale_snapshot';
                if (requiresCatalogRefresh) _needsRefresh = true;
                if (_materials) _materials.setDetailError(
                    errorMessage(response.error), !requiresCatalogRefresh);
                toast(errorMessage(response.error));
            } else if (_materials) {
                if (!_materials.setDetail(response)) {
                    _needsRefresh = true;
                    _materials.setDetailError('材料详情与目录快照不一致，请重新同步。', false);
                    toast('材料详情与目录快照不一致，请重新同步。');
                }
            }
            refreshControls();
        });
    }

    function materialUseTuple(use) {
        return {
            category:String(use && use.category || ''),
            recipeIndex:Number(use && use.recipeIndex),
            productName:String(use && use.productName || ''),
            displayName:String(use && use.displayName || ''),
            itemKind:String(use && use.itemKind || ''),
            recipeOrigin:use && use.recipeOrigin === 'craft_source' ? 'craft_source' : 'use',
            sourceKey:use && use.recipeOrigin === 'craft_source' ? String(use.sourceKey || '') : ''
        };
    }

    function materialUseTargetIsCurrent(kind, tuple) {
        if (!_materials || !tuple) return false;
        if (kind === 'inspect') {
            return _materials.isCurrentUse(tuple.category, tuple.recipeIndex, tuple.productName);
        }
        return typeof _materials.isCurrentRecipeTarget === 'function'
            && _materials.isCurrentRecipeTarget(tuple.category, tuple.recipeIndex,
                tuple.productName, tuple.recipeOrigin, tuple.sourceKey);
    }

    function invalidateMaterialUseIntent(clearViewState) {
        _recipeSnapshotGeneration++;
        if (_recipeSnapshotCallId && _mux && typeof _mux.cancel === 'function') {
            _mux.cancel(_recipeSnapshotCallId);
        }
        _recipeSnapshotCallId = '';
        _recipeSnapshotIntent = null;
        if (clearViewState !== false && _materials
                && typeof _materials.clearUseAction === 'function') {
            _materials.clearUseAction();
        }
        refreshControls();
    }

    function requestMaterialUseSnapshot(kind, use, opener) {
        kind = kind === 'inspect' ? 'inspect' : 'recipe';
        var tuple = materialUseTuple(use);
        if (_materialShopNavigation || _mode !== 'materials'
                || _materialSessionVersion !== 2 || !_materials
                || !_panelInstanceId || !tuple.category || tuple.recipeIndex < 0
                || Math.floor(tuple.recipeIndex) !== tuple.recipeIndex || !tuple.productName
                || kind === 'inspect' && tuple.itemKind !== 'equipment'
                || kind === 'recipe' && (!_materials.canOpenCrafting
                    || !_materials.canOpenCrafting())
                || !materialUseTargetIsCurrent(kind, tuple)) {
            return false;
        }
        invalidateMaterialUseIntent(true);
        var intent = {
            generation:++_recipeSnapshotGeneration,
            lifecycleGeneration:_generation,
            panelInstanceId:_panelInstanceId,
            materialSnapshotId:_materialSnapshotId,
            materialSnapshotIntentGeneration:_materialSnapshotIntentGeneration,
            selectedName:_materials.getSelectedName(),
            kind:kind,
            use:tuple,
            opener:opener,
            callId:''
        };
        _recipeSnapshotIntent = intent;
        if (!_materials.setUseActionPending(tuple, kind)) {
            _recipeSnapshotIntent = null;
            return false;
        }
        refreshControls();
        var snapshotPayload = {category:tuple.category};
        if (kind === 'recipe') snapshotPayload.materialSnapshotId = intent.materialSnapshotId;
        var callId = request('snapshot', snapshotPayload, function(response, entry) {
            completeMaterialUseSnapshot(intent, response, entry && entry.callId);
        });
        if (_recipeSnapshotIntent === intent) {
            intent.callId = String(callId || '');
            _recipeSnapshotCallId = intent.callId;
            if (!callId) {
                failMaterialUseIntent(intent, '最新配方请求未发送；请重试。');
            }
        }
        return !!callId;
    }

    function materialShopNavigationError(error) {
        var messages = {
            invalid_payload:'商店入口数据无效；请重新同步材料档案。',
            stale_source:'材料来源已经变化；请重新同步后再试。',
            navigation_unavailable:'商店导航暂不可用；请重试。',
            access_denied:'需要自行车、摩托车或越野车，才能从材料档案前往商店。',
            source_not_settled:'材料档案仍在同步；请稍后重试。',
            admission_failed:'商店暂时无法打开；请重试。',
            timeout:'打开商店超时；请重试。',
            busy:'另一项面板导航正在进行；请稍后重试。'
        };
        return messages[String(error || '')] || '暂时无法前往商店；请重试。';
    }

    function procurementNavigationError(error) {
        if (String(error || '') === 'access_denied') {
            return '需要摩托车或越野车基建，才能从配方直接前往商店。';
        }
        return materialShopNavigationError(error);
    }

    function requestMaterialShopNavigation(source, opener) {
        source = source || {};
        var selectedName = _materials && _materials.getSelectedName
            ? _materials.getSelectedName() : '';
        var restoreOpenerFocus = document.activeElement === opener;
        if (_materialShopNavigation || _mode !== 'materials'
                || _materialSessionVersion !== 2 || !_materials || !_panelInstanceId
                || _previewBusy || _busy || _organizerBusy || _needsRefresh
                || !_materials.canOpenShop || !_materials.canOpenShop()
                || _recipeSnapshotIntent || source.kind !== 'shop'
                || source.shopAccessMode !== 'full'
                || source.shopAccessReason !== 'indexed_live_match'
                || String(source.itemName || '') !== String(selectedName || '')
                || !_materialSnapshotId || !source.sourceKey
                || !_materials.isShopNavigationTrigger(opener, source.sourceKey)
                || !_materials.setShopNavigationPending(source.sourceKey)) return false;
        var callId = 'craft-material-shop-' + (++_materialShopNavigationSequence);
        var message = CraftingRuntime.createMaterialShopNavigationMessage({
            callId:callId,
            panelInstanceId:_panelInstanceId,
            materialSnapshotId:_materialSnapshotId,
            materialName:selectedName,
            shopId:source.shopId,
            catalogIndex:source.catalogIndex
        });
        if (!message) {
            _materials.setShopNavigationError(source.sourceKey,
                materialShopNavigationError('invalid_payload'));
            refreshControls();
            return false;
        }
        var intent = {
            generation:++_materialShopNavigationGeneration,
            lifecycleGeneration:_generation,
            panelInstanceId:_panelInstanceId,
            materialSnapshotId:_materialSnapshotId,
            materialName:selectedName,
            sourceKey:String(source.sourceKey),
            shopId:String(source.shopId),
            catalogIndex:Number(source.catalogIndex),
            callId:callId,
            opener:opener,
            restoreOpenerFocus:restoreOpenerFocus,
            startedAt:Date.now()
        };
        _materialShopNavigation = intent;
        refreshControls();
        var sent = false;
        try { sent = Bridge.send(message) !== false; }
        catch (_) { sent = false; }
        if (!sent) {
            failMaterialShopNavigation(intent, 'navigation_unavailable');
            return false;
        }
        if (_materialShopNavigation === intent) {
            var elapsed = Math.max(0, Date.now() - intent.startedAt);
            _materialShopNavigationTimer = setTimeout(function() {
                if (_materialShopNavigation === intent) {
                    failMaterialShopNavigation(intent, 'timeout');
                }
            }, Math.max(0, CraftingRuntime.NAVIGATION_WATCHDOG_MS - elapsed));
        }
        return true;
    }

    function materialShopNavigationIsCurrent(intent) {
        return !!intent && _materialShopNavigation === intent
            && intent.generation === _materialShopNavigationGeneration
            && intent.lifecycleGeneration === _generation
            && intent.panelInstanceId === _panelInstanceId
            && intent.materialSnapshotId === _materialSnapshotId
            && _mode === 'materials'
            && _materials && _materials.getSelectedName() === intent.materialName
            && (!Panels.getActive || Panels.getActive() === 'crafting');
    }

    function handleMaterialShopNavigationFailure(data) {
        var intent = _materialShopNavigation;
        if (!materialShopNavigationIsCurrent(intent)
                || !CraftingRuntime.validateMaterialShopNavigationFailure(data, {
                    callId:intent.callId,
                    panelInstanceId:intent.panelInstanceId
                })) return false;
        return failMaterialShopNavigation(intent, data.error);
    }

    function failMaterialShopNavigation(intent, error) {
        if (!materialShopNavigationIsCurrent(intent)) return false;
        var activeBeforeFailure = document.activeElement;
        if (_materialShopNavigationTimer !== null) {
            clearTimeout(_materialShopNavigationTimer);
            _materialShopNavigationTimer = null;
        }
        _materialShopNavigation = null;
        if (_materials) _materials.setShopNavigationError(
            intent.sourceKey, materialShopNavigationError(error));
        refreshControls();
        if (intent.restoreOpenerFocus && intent.opener && intent.opener.isConnected
                && _materials && _materials.isShopNavigationTrigger(
                    intent.opener, intent.sourceKey)
                && (activeBeforeFailure === intent.opener
                    || activeBeforeFailure === document.body
                    || activeBeforeFailure === document.documentElement)) {
            try { intent.opener.focus({preventScroll:true}); }
            catch (_) { intent.opener.focus(); }
        }
        return false;
    }

    function retireMaterialShopNavigation(clearViewState) {
        _materialShopNavigationGeneration++;
        if (_materialShopNavigationTimer !== null) {
            clearTimeout(_materialShopNavigationTimer);
            _materialShopNavigationTimer = null;
        }
        _materialShopNavigation = null;
        if (clearViewState !== false && _materials
                && typeof _materials.clearShopNavigation === 'function') {
            _materials.clearShopNavigation();
        }
    }

    function canRequestRecipeShopNavigation(material, source) {
        var recipe = findRecipe(_selectedIndex);
        var demand = material && material.procurement;
        var direct = hasDirectRecipeShopNavigation();
        if (_mode !== 'recipes' || _procurementNavigation || _nestedRecipeNavigation
                || _materialShopNavigation
                || !recipe || !recipe.recipeId || !material || !demand || !direct
                || _busy || _previewBusy || _planBusy || _organizerBusy
                || _needsReconcile || _needsRefresh || !_panelInstanceId
                || !source || (source.kind !== 'npcshop' && source.kind !== 'kshop')
                || Number(demand.obtainMissing) <= 0
                || !Array.isArray(demand.sources)
                || !demand.sources.some(function(candidate) {
                    if (!candidate || candidate.kind !== source.kind
                            || Number(candidate.catalogIndex)
                                !== Number(source.catalogIndex)) return false;
                    return source.kind === 'npcshop'
                        ? candidate.shopId === source.shopId
                        : candidate.entryId === source.entryId
                            && String(candidate.category || '')
                                === String(source.category || '');
                })) return false;
        if (source.kind === 'kshop'
                && (typeof source.entryId !== 'string' || !source.entryId)) return false;
        return true;
    }

    function hasDirectRecipeShopNavigation() {
        return !!(_snapshot && _snapshot.procurement
            && _snapshot.procurement.directShopNavigation === true);
    }

    function requestRecipeShopNavigation(material, source, opener) {
        var recipe = findRecipe(_selectedIndex);
        if (!canRequestRecipeShopNavigation(material, source)) {
            toast('商店来源仍在核算，请稍候再试。');
            renderDetail();
            refreshControls();
            return false;
        }
        var intent = {
            generation:++_procurementNavigationGeneration,
            lifecycleGeneration:_generation,
            panelInstanceId:_panelInstanceId,
            category:_category,
            recipeIndex:Number(recipe.recipeIndex),
            recipeId:String(recipe.recipeId),
            materialName:String(material.name || ''),
            shopKind:String(source.kind),
            shopId:String(source.shopId || ''),
            entryId:String(source.entryId || ''),
            kshopCategory:String(source.category || ''),
            catalogIndex:Number(source.catalogIndex),
            opener:opener,
            stage:'navigation',
            requestCallId:'',
            navigationCallId:'craft-procurement-shop-'
                + (++_procurementNavigationSequence)
        };
        if (!intent.materialName || intent.catalogIndex < 0
                || intent.shopKind === 'npcshop' && !intent.shopId
                || intent.shopKind === 'kshop' && !intent.entryId) return false;
        var messageFactory = intent.shopKind === 'kshop'
            ? CraftingRuntime.createProcurementKShopNavigationMessage
            : CraftingRuntime.createProcurementShopNavigationMessage;
        var message = messageFactory({
            callId:intent.navigationCallId,
            panelInstanceId:intent.panelInstanceId,
            materialName:intent.materialName,
            shopId:intent.shopId,
            catalogIndex:intent.catalogIndex,
            entryId:intent.entryId,
            kshopCategory:intent.kshopCategory,
            recipeId:intent.recipeId,
            category:intent.category,
            recipeIndex:intent.recipeIndex
        });
        if (!message) return false;
        _procurementNavigation = intent;
        renderDetail();
        refreshControls();
        var sent = false;
        try { sent = Bridge.send(message) !== false; }
        catch (_) { sent = false; }
        if (!sent) return failProcurementNavigation(intent, 'navigation_unavailable');
        _procurementNavigationTimer = setTimeout(function() {
            if (procurementNavigationIsCurrent(intent)) {
                failProcurementNavigation(intent, 'timeout');
            }
        }, CraftingRuntime.NAVIGATION_WATCHDOG_MS);
        return true;
    }

    function procurementNavigationIsCurrent(intent) {
        var recipe = findRecipe(_selectedIndex);
        return !!intent && _procurementNavigation === intent
            && intent.generation === _procurementNavigationGeneration
            && intent.lifecycleGeneration === _generation
            && intent.panelInstanceId === _panelInstanceId
            && _mode === 'recipes' && _category === intent.category
            && _selectedIndex === intent.recipeIndex
            && recipe && recipe.recipeId === intent.recipeId
            && (!Panels.getActive || Panels.getActive() === 'crafting');
    }

    function handleProcurementShopNavigationFailure(data) {
        var intent = _procurementNavigation;
        var validateFailure = intent && intent.shopKind === 'kshop'
            ? CraftingRuntime.validateProcurementKShopNavigationFailure
            : CraftingRuntime.validateProcurementShopNavigationFailure;
        if (!procurementNavigationIsCurrent(intent) || intent.stage !== 'navigation'
                || !validateFailure(data, {
                    callId:intent.navigationCallId,
                    panelInstanceId:intent.panelInstanceId
                })) return false;
        return failProcurementNavigation(intent, data.error);
    }

    function failProcurementNavigation(intent, error) {
        if (!procurementNavigationIsCurrent(intent)) return false;
        if (intent.requestCallId && _mux && typeof _mux.cancel === 'function') {
            _mux.cancel(intent.requestCallId);
        }
        if (_procurementNavigationTimer !== null) {
            clearTimeout(_procurementNavigationTimer);
            _procurementNavigationTimer = null;
        }
        _procurementNavigation = null;
        toast(procurementNavigationError(error));
        renderDetail();
        refreshControls();
        return false;
    }

    function retireProcurementNavigation() {
        _procurementNavigationGeneration++;
        var intent = _procurementNavigation;
        if (intent && intent.requestCallId && _mux && typeof _mux.cancel === 'function') {
            _mux.cancel(intent.requestCallId);
        }
        if (_procurementNavigationTimer !== null) {
            clearTimeout(_procurementNavigationTimer);
            _procurementNavigationTimer = null;
        }
        _procurementNavigation = null;
    }

    function nestedRecipeTargetMatches(intent, material, source) {
        return !!intent && !!material && !!source
            && intent.materialName === String(material.name || '')
            && intent.targetCategory === String(source.category || '')
            && intent.targetRecipeIndex === Number(source.recipeIndex)
            && intent.targetRecipeId === String(source.recipeId || '');
    }

    function previewContainsNestedSource(materialName, source) {
        if (!_preview || !previewMatchesCurrent() || !Array.isArray(_preview.materials)) return false;
        return _preview.materials.some(function(material) {
            return material && material.enough !== true
                && String(material.name || '') === String(materialName || '')
                && Array.isArray(material.craftingSources)
                && material.craftingSources.some(function(candidate) {
                    return candidate
                        && String(candidate.category || '') === String(source.category || '')
                        && Number(candidate.recipeIndex) === Number(source.recipeIndex)
                        && String(candidate.recipeId || '') === String(source.recipeId || '')
                        && String(candidate.title || '') === String(source.title || '');
                });
        });
    }

    function canRequestNestedRecipe(material, source) {
        var recipe = findRecipe(_selectedIndex);
        return _mode === 'recipes' && !!recipe && !!recipe.recipeId
            && !!material && material.enough !== true && !!source
            && !_nestedRecipeNavigation && !_procurementNavigation && !_materialShopNavigation
            && !_busy && !_previewBusy && !_planBusy && !_organizerBusy
            && !_needsReconcile && !_needsRefresh && !!_panelInstanceId
            && previewContainsNestedSource(material.name, source);
    }

    function requestNestedRecipeNavigation(material, source, opener) {
        if (!canRequestNestedRecipe(material, source)) {
            toast('合成来源仍在核算，请稍候再试。');
            return false;
        }
        var currentRecipe = findRecipe(_selectedIndex);
        var intent = {
            generation:++_nestedRecipeNavigationGeneration,
            lifecycleGeneration:_generation,
            panelInstanceId:_panelInstanceId,
            sourceCategory:_category,
            sourceRecipeIndex:_selectedIndex,
            sourceRecipeId:String(currentRecipe.recipeId || ''),
            materialName:String(material.name || ''),
            targetCategory:String(source.category || ''),
            targetRecipeIndex:Number(source.recipeIndex),
            targetRecipeId:String(source.recipeId || ''),
            targetTitle:String(source.title || ''),
            opener:opener,
            callId:''
        };
        if (intent.targetCategory === _category) {
            return completeSameCategoryNestedRecipe(intent);
        }
        _nestedRecipeNavigation = intent;
        renderDetail();
        refreshControls();
        var callId = request('snapshot', {category:intent.targetCategory}, function(response) {
            completeNestedRecipeSnapshot(intent, response);
        });
        intent.callId = callId || '';
        if (!callId) return failNestedRecipeNavigation(intent,
            '启动器连接不可用，暂时无法读取目标配方。');
        return true;
    }

    function nestedRecipeNavigationIsCurrent(intent) {
        var recipe = findRecipe(_selectedIndex);
        return !!intent && _nestedRecipeNavigation === intent
            && intent.generation === _nestedRecipeNavigationGeneration
            && intent.lifecycleGeneration === _generation
            && intent.panelInstanceId === _panelInstanceId
            && _mode === 'recipes' && _category === intent.sourceCategory
            && _selectedIndex === intent.sourceRecipeIndex
            && recipe && String(recipe.recipeId || '') === intent.sourceRecipeId
            && previewContainsNestedSource(intent.materialName, {
                category:intent.targetCategory,
                recipeIndex:intent.targetRecipeIndex,
                recipeId:intent.targetRecipeId,
                title:intent.targetTitle
            })
            && (!Panels.getActive || Panels.getActive() === 'crafting');
    }

    function exactNestedRecipe(response, intent) {
        if (!response || response.success !== true || Number(response.v) !== 1
                || String(response.category || '') !== intent.targetCategory
                || !Array.isArray(response.recipes)) return null;
        var matches = response.recipes.filter(function(recipe) {
            return recipe && Number(recipe.recipeIndex) === intent.targetRecipeIndex
                && String(recipe.recipeId || '') === intent.targetRecipeId
                && recipe.output
                && String(recipe.output.name || '') === intent.materialName;
        });
        return matches.length === 1 ? matches[0] : null;
    }

    function completeSameCategoryNestedRecipe(intent) {
        if (!previewContainsNestedSource(intent.materialName, {
                category:intent.targetCategory,
                recipeIndex:intent.targetRecipeIndex,
                recipeId:intent.targetRecipeId,
                title:intent.targetTitle
            })) return false;
        var target = exactNestedRecipe(_snapshot, intent);
        if (!target) {
            toast('配方已变化，未执行定位；请重新核对。');
            return false;
        }
        _filterPath = [];
        _craftableOnly = false;
        _selectedIndex = intent.targetRecipeIndex;
        _craftCount = 1;
        _preview = null;
        _planFeedback = null;
        clearPreviewCheckpoint();
        rebuildFilterTree();
        renderCatalog({preserveScroll:false});
        renderDetail({preserveScroll:false});
        cue('select');
        if (!focusExactRecipeCard(intent.targetRecipeIndex)) {
            _needsRefresh = true;
            refreshControls();
            return false;
        }
        requestPreview();
        return true;
    }

    function completeNestedRecipeSnapshot(intent, response) {
        if (!nestedRecipeNavigationIsCurrent(intent)) return false;
        if (!response || response.success !== true) {
            return failNestedRecipeNavigation(intent, '目标配方读取失败：'
                + errorMessage(response && response.error));
        }
        if (!exactNestedRecipe(response, intent)) {
            return failNestedRecipeNavigation(intent,
                '配方已变化，未执行跳转；请重新核对。');
        }
        _nestedRecipeNavigationGeneration++;
        _nestedRecipeNavigation = null;
        _category = intent.targetCategory;
        _snapshot = response;
        _selectedIndex = intent.targetRecipeIndex;
        _craftCount = 1;
        _preview = null;
        _previewFlight = null;
        _previewQueued = null;
        clearPreviewCheckpoint();
        _busy = false;
        _previewBusy = false;
        _planBusy = false;
        _organizerBusy = false;
        _organizerMounted = false;
        _needsReconcile = false;
        _needsRefresh = false;
        _reconcileEpoch = 0;
        _filterPath = [];
        _craftableOnly = false;
        _planFocusRecipeId = '';
        _planFocusAction = '';
        _planFeedback = null;
        _tooltipCache = {};
        buildDOM();
        rebuildFilterTree();
        applyBalance(response.balance);
        renderCatalog({preserveScroll:false});
        renderDetail({preserveScroll:false});
        cue('select');
        if (!focusExactRecipeCard(intent.targetRecipeIndex)) {
            _needsRefresh = true;
            refreshControls();
            return false;
        }
        requestPreview();
        return true;
    }

    function failNestedRecipeNavigation(intent, message) {
        if (!nestedRecipeNavigationIsCurrent(intent)) return false;
        _nestedRecipeNavigationGeneration++;
        _nestedRecipeNavigation = null;
        toast(message || '目标配方定位失败，请重试。');
        renderDetail();
        refreshControls();
        if (intent.opener && intent.opener.isConnected
                && typeof intent.opener.focus === 'function') {
            try { intent.opener.focus({preventScroll:true}); }
            catch (_) { intent.opener.focus(); }
        }
        return false;
    }

    function retireNestedRecipeNavigation() {
        _nestedRecipeNavigationGeneration++;
        var intent = _nestedRecipeNavigation;
        if (intent && intent.callId && _mux && typeof _mux.cancel === 'function') {
            _mux.cancel(intent.callId);
        }
        _nestedRecipeNavigation = null;
    }

    function materialUseIntentIsCurrent(intent, responseCallId) {
        if (!intent || _recipeSnapshotIntent !== intent
                || intent.generation !== _recipeSnapshotGeneration
                || intent.lifecycleGeneration !== _generation
                || intent.panelInstanceId !== _panelInstanceId
                || intent.materialSnapshotId !== _materialSnapshotId
                || intent.materialSnapshotIntentGeneration !== _materialSnapshotIntentGeneration
                || _mode !== 'materials' || _materialSessionVersion !== 2 || !_materials
                || _materials.getSelectedName() !== intent.selectedName
                || !materialUseTargetIsCurrent(intent.kind, intent.use)
                || !_materials.isUseActionTrigger(intent.opener, intent.use, intent.kind)) return false;
        if (intent.callId && responseCallId && intent.callId !== responseCallId) return false;
        return !Panels.getActive || Panels.getActive() === 'crafting';
    }

    function exactRecipeFromSnapshot(response, intent) {
        if (!response || response.success !== true || Number(response.v) !== 1
                || String(response.category || '') !== intent.use.category
                || !Array.isArray(response.recipes)) return null;
        var matches = response.recipes.filter(function(recipe) {
            return recipe && Number(recipe.recipeIndex) === intent.use.recipeIndex;
        });
        if (matches.length !== 1 || !matches[0].output
                || String(matches[0].output.name || '') !== intent.use.productName) return null;
        return matches[0];
    }

    function completeMaterialUseSnapshot(intent, response, responseCallId) {
        if (!materialUseIntentIsCurrent(intent, responseCallId)) return;
        if (!intent.callId && responseCallId) intent.callId = responseCallId;
        _recipeSnapshotCallId = '';
        if (!response || response.success !== true) {
            if (response && response.error === 'access_denied') {
                failMaterialUseIntent(intent,
                    '需要摩托车或越野车，才能从材料档案前往合成。');
                return;
            }
            if (response && response.error === 'stale_snapshot') {
                failMaterialUseIntent(intent, '材料档案已变化；请返回材料后重试。');
                return;
            }
            failMaterialUseIntent(intent, '最新配方读取失败：'
                + errorMessage(response && response.error) + ' 请重试。');
            return;
        }
        var recipe = exactRecipeFromSnapshot(response, intent);
        if (!recipe) {
            failMaterialUseIntent(intent, '配方已变化，未执行跳转；请重试。');
            return;
        }
        if (intent.kind === 'inspect') {
            completeMaterialUseInspector(intent, response, recipe);
            return;
        }
        if (_shell && _shell.hasModal && _shell.hasModal()) {
            failMaterialUseIntent(intent, '请先关闭当前弹窗，再前往合成。');
            return;
        }
        commitMaterialRecipeRoute(intent, response);
    }

    function failMaterialUseIntent(intent, message) {
        if (!intent || _recipeSnapshotIntent !== intent) return false;
        _recipeSnapshotGeneration++;
        _recipeSnapshotCallId = '';
        _recipeSnapshotIntent = null;
        if (_materials && _mode === 'materials') {
            _materials.setUseActionError(intent.use, intent.kind, message);
        }
        refreshControls();
        return false;
    }

    function completeMaterialUseInspector(intent, response, recipe) {
        if (intent.use.itemKind !== 'equipment' || recipe.output.itemKind !== 'equipment'
                || !_materials.isUseActionTrigger(intent.opener, intent.use, 'inspect')) {
            failMaterialUseIntent(intent, '装备入口已变化，未打开检视；请重试。');
            return false;
        }
        if (_shell && _shell.hasModal && _shell.hasModal()) {
            failMaterialUseIntent(intent, '请先关闭当前弹窗，再查看装备。');
            return false;
        }
        if (typeof intent.opener.focus === 'function') intent.opener.focus();
        var opened = false;
        try { opened = openInspector(recipe.output, response.gender, intent.opener); }
        catch (_) { opened = false; }
        if (!opened) {
            failMaterialUseIntent(intent, '装备检视暂不可用；请重试。');
            return false;
        }
        _recipeSnapshotGeneration++;
        _recipeSnapshotCallId = '';
        _recipeSnapshotIntent = null;
        _materials.completeUseAction(intent.use, 'inspect');
        refreshControls();
        return true;
    }

    function commitMaterialRecipeRoute(intent, response) {
        // This is a same-owner view transition. Deliberately preserve the
        // existing panelInstanceId and CharacterBuild return capability.
        _materialRecipeReturn = {
            materialName:String(intent.selectedName || '')
        };
        _recipeSnapshotGeneration++;
        _recipeSnapshotCallId = '';
        _recipeSnapshotIntent = null;
        _materialRequestSeq++;
        _materialSnapshotIntentGeneration++;
        _materialSessionVersion = 0;
        _materialSnapshotId = '';
        _mode = 'recipes';
        _category = intent.use.category;
        _snapshot = response;
        _selectedIndex = intent.use.recipeIndex;
        _craftCount = 1;
        _preview = null;
        _previewFlight = null;
        _previewQueued = null;
        clearPreviewCheckpoint();
        _busy = false;
        _previewBusy = false;
        _planBusy = false;
        _organizerBusy = false;
        _organizerMounted = false;
        _needsReconcile = false;
        _needsRefresh = false;
        _reconcileEpoch = 0;
        _filterPath = [];
        _craftableOnly = false;
        _tooltipCache = {};
        buildDOM();
        rebuildFilterTree();
        applyBalance(response.balance);
        renderCatalog({preserveScroll:false});
        renderDetail({preserveScroll:false});
        if (!focusExactRecipeCard(intent.use.recipeIndex)) {
            _needsRefresh = true;
            refreshControls();
            return false;
        }
        requestPreview();
        return true;
    }

    function returnToMaterials() {
        if (_mode !== 'recipes' || !_materialRecipeReturn
                || !_materialRecipeReturn.materialName) return false;
        if (_busy || _previewBusy || _planBusy || _organizerBusy || _organizerMounted
                || _procurementNavigation || _nestedRecipeNavigation
                || _needsReconcile || _needsRefresh) {
            toast('合成状态正在确认，请稍候返回材料。');
            return false;
        }
        var preferredName = _materialRecipeReturn.materialName;
        _materialRecipeReturn = null;
        _generation++;
        _recipeSnapshotGeneration++;
        _recipeSnapshotCallId = '';
        _recipeSnapshotIntent = null;
        _materialRequestSeq++;
        _materialSnapshotIntentGeneration++;
        _materialSessionVersion = 0;
        _materialSnapshotId = '';
        _mode = 'materials';
        _category = '';
        _snapshot = null;
        _preview = null;
        _selectedIndex = -1;
        _craftCount = 1;
        _previewFlight = null;
        _previewQueued = null;
        clearPreviewCheckpoint();
        _busy = false;
        _previewBusy = false;
        _planBusy = false;
        _organizerBusy = false;
        _organizerMounted = false;
        _needsReconcile = false;
        _needsRefresh = false;
        _reconcileEpoch = 0;
        _filterPath = [];
        _craftableOnly = false;
        _tooltipCache = {};
        buildDOM();
        refreshMaterialsSnapshot(preferredName);
        return true;
    }

    function focusExactRecipeCard(recipeIndex) {
        if (!_catalogRenderer || !_catalogRenderer.root) return false;
        var cards = _catalogRenderer.root.querySelectorAll('[data-workbench-key]');
        var target = null;
        for (var index = 0; index < cards.length; index++) {
            if (Number(cards[index].getAttribute('data-workbench-key')) === Number(recipeIndex)) {
                target = cards[index];
                break;
            }
        }
        if (!target) return false;
        if (typeof target.scrollIntoView === 'function') {
            target.scrollIntoView({block:'nearest', inline:'nearest'});
        }
        if (typeof target.focus === 'function') target.focus();
        return document.activeElement === target;
    }

    function reconcile() {
        if (_mode === 'materials') {
            refreshMaterialsSnapshot(_materials && _materials.getSelectedName());
            return;
        }
        if (_needsRefresh) refreshSnapshot(_selectedIndex, _craftCount);
        else if (_selectedIndex >= 0) requestPreview();
        else refreshSnapshot();
    }

    function openOrganizer() {
        if (_busy || _previewBusy || _planBusy || _procurementNavigation
                || _nestedRecipeNavigation || _organizerBusy
                || _needsReconcile || _needsRefresh || !_category) return false;
        _organizerBusy = true; renderDetail(); refreshControls();
        var generation = _generation;
        return !!request('snapshot', {category:_category}, function(response) {
            if (generation !== _generation) return;
            if (!response.success) {
                _organizerBusy = false;
                if (requiresReconcile(response)) {
                    _preview = null; clearPreviewCheckpoint(); enterNeedsReconcile();
                }
                toast(errorMessage(response.error)); renderDetail(); refreshControls(); return;
            }
            _preview = null; clearPreviewCheckpoint();
            loadOrganizer(generation);
        });
    }

    function loadOrganizer(generation) {
        var pending = null;
        try {
            pending = typeof LazyLoader !== 'undefined' && LazyLoader
                && typeof LazyLoader.load === 'function'
                ? LazyLoader.load(ORGANIZER_DEPS) : null;
        } catch (error) {
            failOrganizerMount(error, generation);
            return false;
        }
        if (!pending || typeof pending.then !== 'function') {
            failOrganizerMount(new Error('organizer dependency load returned a non-thenable'), generation);
            return false;
        }
        pending.then(function() {
            if (generation !== _generation || !Panels.getActive
                    || Panels.getActive() !== 'crafting') return;
            suspendForOrganizer();
            var mounted = typeof CraftingInventoryOrganizer !== 'undefined'
                && CraftingInventoryOrganizer.mount(_shellEl, {
                    kind:'crafting-organizer',
                    panel:'crafting',
                    panelInstanceId:_panelInstanceId,
                    onReturn:restoreFromOrganizer
                });
            if (!mounted) {
                failOrganizerMount(new Error('organizer mount was rejected'), generation);
                return;
            }
            _organizerMounted = true;
            _organizerBusy = false;
        }).catch(function(error) {
            failOrganizerMount(error, generation);
        });
        return true;
    }

    function suspendForOrganizer() {
        disposeFilterNavigator();
        if (_helpAction) { _helpAction.destroy(); _helpAction = null; }
        if (_detailPresenter) { _detailPresenter.destroy(); _detailPresenter = null; }
        if (_tooltipScope) { _tooltipScope.dispose(); _tooltipScope = null; }
        if (_shell) { _shell.destroy(); _shell = null; }
        Workbench.clearElement(_shellEl);
    }

    function restoreFromOrganizer() {
        if (!_organizerMounted && !_organizerBusy) return false;
        _organizerMounted = false;
        _organizerBusy = false;
        _preview = null;
        clearPreviewCheckpoint();
        _tooltipScope = typeof PanelTooltip !== 'undefined' && PanelTooltip.createScope
            ? PanelTooltip.createScope('crafting', {profile:'dense-inspect'}) : null;
        buildDOM();
        refreshSnapshot(_selectedIndex, _craftCount);
        return true;
    }

    function recoverOrganizerMountFailure() {
        if (!Panels.getActive || Panels.getActive() !== 'crafting') return false;
        if (!_shell) {
            _tooltipScope = typeof PanelTooltip !== 'undefined' && PanelTooltip.createScope
                ? PanelTooltip.createScope('crafting', {profile:'dense-inspect'}) : null;
            buildDOM();
            refreshSnapshot(_selectedIndex, _craftCount);
        } else {
            renderDetail();
            refreshControls();
        }
        return true;
    }

    function failOrganizerMount(error, generation) {
        if (generation !== _generation) return;
        _organizerBusy = false;
        _organizerMounted = false;
        if (typeof console !== 'undefined' && console.error) {
            console.error('[CraftingPanel] organizer mount failed:', error);
        }
        var closeAccepted = false;
        try {
            closeAccepted = Bridge.send({type:'panel', cmd:'close', panel:'crafting',
                panelInstanceId:_panelInstanceId}) !== false;
        } catch (_) {
            closeAccepted = false;
        }
        if (!closeAccepted) {
            recoverOrganizerMountFailure();
            toast('背包整理资源加载失败；启动器连接不可用，合成工作台保持打开，可重试。');
            return false;
        }
        toast('背包整理资源加载失败，合成工作台已安全关闭。');
        Panels.close();
        return true;
    }

    function findRecipe(index) {
        var recipes = _snapshot && _snapshot.recipes ? _snapshot.recipes : [];
        for (var i = 0; i < recipes.length; i++) if (Number(recipes[i].recipeIndex) === Number(index)) return recipes[i];
        return null;
    }

    function applyBalance(balance) {
        balance = balance || {};
        _shell.setMetric('money', '金币', formatNumber(balance.money));
        _shell.setMetric('kpoints', 'K 点', formatNumber(balance.kpoints));
    }

    function setMaterialsMetric(kind, materials) {
        if (!_shell || _mode !== 'materials') return;
        var value = '— / —', ariaLabel = kind === 'loading'
            ? '持有种类，正在同步' : '持有种类，暂不可用';
        if (kind === 'ready') {
            var seen = Object.create(null), ownedKinds = 0;
            (materials || []).forEach(function(material) {
                var name = material && String(material.name || '');
                if (!name || seen[name]) return;
                seen[name] = true;
                if (Number(material.owned || 0) > 0) ownedKinds++;
            });
            var total = Object.keys(seen).length;
            value = ownedKinds + ' / ' + total;
            ariaLabel = '持有种类，' + ownedKinds + ' / ' + total;
        }
        var valueNode = _shell.setMetric('ownedKinds', '持有种类', value);
        var metric = valueNode && valueNode.parentNode;
        if (metric) {
            metric.setAttribute('aria-label', ariaLabel);
            metric.setAttribute('data-metric-state', kind === 'ready' ? 'ready'
                : kind === 'loading' ? 'loading' : 'error');
        }
    }

    function refreshControls() {
        if (!_shell) return;
        if (_mode === 'materials') {
            if (_materialShopNavigation) _shell.setStatus('正在打开 NPC 商店', 'loading');
            else if (_needsRefresh) _shell.setStatus('需要重新同步', 'error');
            else if (_previewBusy) _shell.setStatus('正在读取材料档案', 'loading');
            else if (_snapshot) _shell.setStatus('材料索引已同步', 'idle');
            else _shell.setStatus('同步中', 'loading');
            if (_retryButton) {
                _retryButton.textContent = '重新同步';
                _retryButton.style.display = _needsRefresh ? '' : 'none';
                _retryButton.disabled = _previewBusy || !!_materialShopNavigation;
            }
            if (_returnCharacterBuildButton && _returnNavigationTimer === null) {
                _returnCharacterBuildButton.disabled = !!_recipeSnapshotIntent
                    || !!_materialShopNavigation;
            }
            if (_helpAction && _helpAction.button) {
                _helpAction.button.disabled = !!_materialShopNavigation;
            }
            if (_densityToggle) {
                var densityButtons = _densityToggle.querySelectorAll('button');
                for (var densityIndex = 0; densityIndex < densityButtons.length; densityIndex++) {
                    densityButtons[densityIndex].disabled = !!_materialShopNavigation;
                }
            }
            return;
        }
        if (_needsReconcile) _shell.setStatus('需要重新核对', 'error');
        else if (_needsRefresh) _shell.setStatus('需要重新同步', 'error');
        else if (_nestedRecipeNavigation) _shell.setStatus('正在定位合成配方', 'loading');
        else if (_procurementNavigation) _shell.setStatus('正在前往商店', 'loading');
        else if (_organizerBusy) _shell.setStatus('正在打开战备箱', 'loading');
        else if (_planBusy) _shell.setStatus('正在同步标记', 'loading');
        else if (_busy || _previewBusy) _shell.setStatus('权威核算中', 'loading');
        else if (_snapshot) _shell.setStatus('Flash 权威状态', 'idle');
        else _shell.setStatus('同步中', 'loading');
        if (_retryButton) {
            _retryButton.textContent = _needsReconcile ? '重新核对' : '重新同步';
            _retryButton.style.display = _needsReconcile || _needsRefresh ? '' : 'none';
            _retryButton.disabled = _previewBusy || !!_procurementNavigation
                || !!_nestedRecipeNavigation;
        }
        if (_organizerButton) _organizerButton.disabled = _busy || _previewBusy || _planBusy
            || _organizerBusy || !!_procurementNavigation || !!_nestedRecipeNavigation
            || _needsReconcile || _needsRefresh;
        if (_returnMaterialsButton) {
            _returnMaterialsButton.disabled = _busy || _previewBusy || _planBusy
                || _organizerBusy || _organizerMounted
                || !!_procurementNavigation || !!_nestedRecipeNavigation
                || _needsReconcile || _needsRefresh;
        }
        if (_returnCharacterBuildButton && _returnNavigationTimer === null) {
            _returnCharacterBuildButton.disabled = _busy || _previewBusy || _planBusy
                || _organizerBusy || !!_procurementNavigation || !!_nestedRecipeNavigation
                || _needsReconcile || _needsRefresh;
        }
        if (_filterNavigator) _filterNavigator.setDisabled(_busy || _previewBusy || _planBusy
            || _organizerBusy || !!_procurementNavigation || !!_nestedRecipeNavigation
            || _needsReconcile || _needsRefresh);
        if (_craftableToggle) _craftableToggle.disabled = _busy || _previewBusy || _planBusy
            || _organizerBusy || !!_procurementNavigation || !!_nestedRecipeNavigation
            || _needsReconcile || _needsRefresh;
        if (_helpAction && _helpAction.button) {
            _helpAction.button.disabled = !!_procurementNavigation || !!_nestedRecipeNavigation;
        }
        if (_densityToggle) {
            var recipeDensityButtons = _densityToggle.querySelectorAll('button');
            for (var recipeDensityIndex = 0;
                    recipeDensityIndex < recipeDensityButtons.length;
                    recipeDensityIndex++) {
                recipeDensityButtons[recipeDensityIndex].disabled = _busy || _planBusy
                    || _organizerBusy || !!_procurementNavigation
                    || !!_nestedRecipeNavigation;
            }
        }
    }

    function onOpen(el, initData) {
        _generation++;
        retireMaterialShopNavigation(false);
        retireProcurementNavigation();
        retireNestedRecipeNavigation();
        _recipeSnapshotGeneration++;
        _recipeSnapshotCallId = '';
        _recipeSnapshotIntent = null;
        _materialRequestSeq++;
        _materialSnapshotIntentGeneration++;
        _materialSessionVersion = 0;
        _materialSnapshotId = '';
        if (_tooltipScope) _tooltipScope.dispose();
        _tooltipScope = typeof PanelTooltip !== 'undefined' && PanelTooltip.createScope
            ? PanelTooltip.createScope('crafting', {profile:'dense-inspect'}) : null;
        initData = initData || {};
        _materialRecipeReturn = null;
        _mode = initData.view === 'materials' ? 'materials' : 'recipes';
        _panelInstanceId = typeof initData.panelInstanceId === 'string'
            ? initData.panelInstanceId : '';
        _canReturnCharacterBuild = _mode === 'materials'
            && initData.canReturnCharacterBuild === true
            && initData.navigationOrigin === 'character_build'
            && !!_panelInstanceId;
        var nextCategory = _mode === 'materials'
            ? '' : (typeof initData.category === 'string' ? initData.category : '');
        if (nextCategory !== _category) { _filterPath = []; _craftableOnly = false; }
        _category = nextCategory;
        var preferredIndex = initData && Number(initData.preferredRecipeIndex);
        var preferredCount = initData && Number(initData.preferredCraftCount);
        _snapshot = null; _preview = null; clearPreviewCheckpoint(); _selectedIndex = -1;
        _busy = false; _previewBusy = false; _planBusy = false;
        _planFocusRecipeId = ''; _planFocusAction = ''; _planFeedback = null;
        _previewFlight = null; _previewQueued = null;
        _craftCount = 1; _organizerBusy = false; _organizerMounted = false;
        _needsReconcile = false; _needsRefresh = false; _reconcileEpoch = 0; _tooltipCache = {}; buildDOM();
        if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = typeof PanelScale !== 'undefined' ? PanelScale.attach(_shellEl, 1024, 576) : null;
        if (!_mux.openSession({
                ownerPanel:'crafting',
                panelInstanceId:_panelInstanceId
            })) return false;
        if (_mode === 'materials') refreshMaterialsSnapshot();
        else refreshSnapshot(preferredIndex, preferredCount);
    }

    function onRebind(el, initData) {
        // Same-name opens replace the Host capability. Invalidate lazy work,
        // previews, organizer ownership and response callbacks before admitting
        // the replacement category/material view on the existing panel host.
        cleanup();
        return onOpen(el, initData);
    }

    function cleanup() {
        _generation++; _materialRequestSeq++; _materialSnapshotIntentGeneration++;
        retireMaterialShopNavigation(false);
        retireProcurementNavigation();
        retireNestedRecipeNavigation();
        invalidateMaterialUseIntent(true);
        _materialSessionVersion = 0; _materialSnapshotId = ''; _mux.closeSession();
        if (_returnNavigationTimer !== null) {
            clearTimeout(_returnNavigationTimer);
            _returnNavigationTimer = null;
        }
        _previewFlight = null; _previewQueued = null;
        if (_organizerMounted && typeof CraftingInventoryOrganizer !== 'undefined') {
            CraftingInventoryOrganizer.teardown();
        }
        if (_scaleHandle) { _scaleHandle.detach(); _scaleHandle = null; }
        if (_shell) _shell.closeModal();
        _inspector = null;
        _busy = false; _previewBusy = false; _planBusy = false; _organizerBusy = false;
        _planFocusRecipeId = ''; _planFocusAction = ''; _planFeedback = null;
        _organizerMounted = false; _snapshot = null; _preview = null;
        clearPreviewCheckpoint(); _needsReconcile = false; _needsRefresh = false; _reconcileEpoch = 0;
        disposeFilterNavigator(); _craftableToggle = null;
        if (_materials) { _materials.destroy(); _materials = null; }
        if (_densityController) { _densityController.destroy(); _densityController = null; }
        if (_helpAction) { _helpAction.destroy(); _helpAction = null; }
        if (_detailPresenter) { _detailPresenter.destroy(); _detailPresenter = null; }
        if (_tooltipScope) { _tooltipScope.dispose(); _tooltipScope = null; }
        _returnCharacterBuildButton = null;
        _returnMaterialsButton = null;
        _materialRecipeReturn = null;
        _densityToggle = null;
        _panelInstanceId = '';
        _canReturnCharacterBuild = false;
    }

    function disposeFilterNavigator() {
        if (_filterNavigator && typeof _filterNavigator.destroy === 'function') _filterNavigator.destroy();
        _filterNavigator = null;
    }

    function requestClose(reason) {
        if (_organizerMounted && typeof CraftingInventoryOrganizer !== 'undefined') {
            return CraftingInventoryOrganizer.requestClose(reason);
        }
        if (_shell && _shell.hasModal()) {
            return _shell.closeModal(typeof reason === 'string' ? reason : 'close');
        }
        if (reason === 'escape' && _mode === 'materials' && _materials
                && typeof _materials.consumeEscape === 'function'
                && _materials.consumeEscape(document.activeElement)) return true;
        if (_busy || _planBusy || _organizerBusy || _procurementNavigation
                || _nestedRecipeNavigation) {
            toast('工作台状态正在确认，请稍候。'); return;
        }
        if (Bridge.send({type:'panel', cmd:'close', panel:'crafting',
                panelInstanceId:_panelInstanceId}) === false) {
            toast('启动器连接不可用，工作台保持打开。');
            return false;
        }
        // Bridge acceptance only means the close intent reached Host.  Host still owns
        // exact-instance admission and commit, and will retire this owner with panel_cmd close.
        // Keeping the source mounted here preserves retry/focus when admission loses a race.
        return true;
    }

    function requestCharacterBuild() {
        if (!_canReturnCharacterBuild || !_panelInstanceId
                || !_returnCharacterBuildButton) return false;
        if (_busy || _previewBusy || _planBusy || _organizerBusy || _needsReconcile || _needsRefresh
                || _recipeSnapshotIntent || _materialShopNavigation || _procurementNavigation
                || _nestedRecipeNavigation) {
            toast('材料档案正在确认状态，请稍候。');
            return false;
        }
        _returnCharacterBuildButton.disabled = true;
        _returnCharacterBuildButton.textContent = '返回中…';
        if (Bridge.send({
                type:'panel',
                panel:'crafting',
                cmd:'close',
                panelInstanceId:_panelInstanceId,
                reason:'navigate_character_build'
            }) === false) {
            _returnCharacterBuildButton.disabled = false;
            _returnCharacterBuildButton.textContent = '← 返回装备';
            toast('启动器连接不可用，暂时无法返回装备。');
            return false;
        }
        _returnNavigationTimer = setTimeout(function() {
            _returnNavigationTimer = null;
            if (!_returnCharacterBuildButton) return;
            _returnCharacterBuildButton.disabled = false;
            _returnCharacterBuildButton.textContent = '← 返回装备';
            toast('返回装备未完成，请重试。');
        }, 4000);
        return true;
    }

    function request(cmd, payload, callback) {
        payload = payload || {};
        if (!Object.prototype.hasOwnProperty.call(payload, 'v')) payload.v = 1;
        return _mux.request(cmd, payload, callback);
    }

    function bindTooltip(node, item) {
        if (!node || !item || !item.name || typeof PanelTooltip === 'undefined') return;
        var tooltipBinder = _tooltipScope || PanelTooltip;
        tooltipBinder.bindAsyncHover(node, {
            cache:_tooltipCache, key:'craft:' + item.name, item:item,
            renderBasic:function(value) {
                return '<div class="kshop-tt-header"><b>' + escapeHtml(value.displayName || '未命名物品') + '</b></div>'
                    + '<div class="kshop-tt-loading">加载中…</div>';
            },
            renderRich:function(value, rich) {
                return PanelTooltip.buildItemRichHtml({
                    iconHtml:PanelTooltip.dynamicIconHtml(value.icon),
                    iconUrl:PanelTooltip.staticIconUrl(value.icon),
                    introHTML:rich.introHTML || '', descHTML:rich.descHTML || '',
                    rootClass:'crafting-tooltip', layoutType:PanelTooltip.inferLayoutType(value.majorType || value.use)
                });
            },
            fetch:function(_, callback) { request('tooltip', {itemName:String(item.name)}, callback); }
        });
    }

    function releaseTooltipTree(root) {
        if (!root) return 0;
        if (_tooltipScope && typeof _tooltipScope.releaseTree === 'function') {
            return _tooltipScope.releaseTree(root);
        }
        if (typeof PanelTooltip !== 'undefined' && PanelTooltip
                && typeof PanelTooltip.releaseTree === 'function') {
            return PanelTooltip.releaseTree(root);
        }
        return 0;
    }

    function rememberPreview(response, recipeIndex, craftCount) {
        _previewCheckpoint = {category:_category, recipeIndex:Number(recipeIndex), craftCount:Number(craftCount), preview:response};
        _checkpointRetryIntent = null;
    }

    function restorePreviewCheckpoint(recipeIndex) {
        var checkpoint = _previewCheckpoint;
        if (!checkpoint || checkpoint.category !== _category || checkpoint.recipeIndex !== Number(recipeIndex)) return false;
        _preview = checkpoint.preview; applyBalance(_preview.balance); return true;
    }

    function clearPreviewCheckpoint() {
        _previewCheckpoint = null;
        _checkpointRetryIntent = null;
    }

    function requiresReconcile(response) {
        return !!(response && response.requiresReconcile) || (response && response.error) === 'reconcile_required';
    }

    function sameJson(left, right) {
        if (left === right) return true;
        if (Array.isArray(left) || Array.isArray(right)) {
            return Array.isArray(left) && Array.isArray(right)
                && left.length === right.length && left.every(function(value, index) {
                    return sameJson(value, right[index]);
                });
        }
        if (!left || !right || typeof left !== 'object' || typeof right !== 'object') return false;
        var leftKeys = Object.keys(left).sort(), rightKeys = Object.keys(right).sort();
        return leftKeys.length === rightKeys.length && leftKeys.every(function(key, index) {
            return key === rightKeys[index] && sameJson(left[key], right[key]);
        });
    }

    function enterNeedsReconcile() {
        if (!_needsReconcile) _reconcileEpoch++;
        _needsReconcile = true;
    }

    function isTransportUncertain(response) {
        var error = response && response.error;
        return error === 'timeout' || error === 'client_timeout' || error === 'disconnected'
            || error === 'malformed_response' || error === 'invalid_response';
    }

    function isWriteAmbiguous(response, dispatched) {
        return requiresReconcile(response) || (dispatched && isTransportUncertain(response));
    }

    function requiresAuthorityRefresh(response) {
        var error = response && response.error;
        return error === 'category_not_found' || error === 'recipe_not_found' || error === 'item_not_found'
            || error === 'stale_state' || error === 'material_missing' || error === 'insufficient_money'
            || error === 'insufficient_kpoint' || error === 'inventory_full' || error === 'level_locked'
            || error === 'batch_not_supported';
    }

    function costText(cost) {
        var parts = [];
        if (Number(cost.money || 0)) parts.push(formatNumber(cost.money) + ' 金币');
        if (Number(cost.kpoints || 0)) parts.push(formatNumber(cost.kpoints) + ' K 点');
        return parts.length ? parts.join(' / ') : '无货币消耗';
    }
    function availabilityText(code) {
        var labels = {ready:'可合成', level_locked:'等级不足', material_missing:'材料不足',
            insufficient_money:'金币不足', insufficient_kpoint:'K点不足', inventory_full:'空间不足'};
        return labels[code] || '暂不可合成';
    }
    function iconHtml(iconName, cls) {
        if (typeof iconName !== 'string' || !iconName) {
            return '<span class="kshop-icon-placeholder"></span>';
        }
        var html = typeof Icons !== 'undefined' && Icons.html
            ? Icons.html(iconName, cls || 'kshop-icon', ' onerror="this.style.display=\'none\'"') : '';
        return html || '<span class="kshop-icon-placeholder"></span>';
    }
    function staticIconUrl(iconName) {
        return typeof iconName === 'string' && iconName
            && typeof Icons !== 'undefined' && Icons.resolveStatic
            ? (Icons.resolveStatic(iconName) || '') : '';
    }
    function formatNumber(value) { var number = Number(value || 0); return isNaN(number) ? '0' : number.toLocaleString(); }
    function escapeHtml(value) { return String(value == null ? '' : value).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
    function toast(message) { if (typeof Toast !== 'undefined') Toast.add(message); }
    // 语义音效命令式入口（契约 §8）：仅本地校验 / 权威结果路径使用，静态元素走 data-audio-cue
    function cue(name) {
        var A = window.BootstrapAudio;
        if (A && typeof A.cue === 'function') A.cue(name);
    }
    function errorMessage(error) {
        var messages = {category_not_found:'未找到该合成分类。', recipe_not_found:'配方已变化。', item_not_found:'未找到该材料或配方物品。',
            level_locked:'角色等级与逆向等级不足。', material_missing:'所需材料不足。', insufficient_money:'金币不足。',
            insufficient_kpoint:'K 点不足。', inventory_full:'背包空间不足。', stale_state:'物品状态已变化，请重新核对。',
            batch_not_supported:'该配方包含装备产物或装备素材，只能逐份合成。',
            busy:'Flash 正在处理另一项合成。', reconcile_required:'上次提交结果需要重新核对。',
            stale_snapshot:'材料目录已更新，请重新同步。',
            malformed_response:'Flash 回包不完整。', timeout:'合成响应超时。', client_timeout:'合成响应超时。', disconnected:'连接已断开。'};
        return messages[error] || (_mode === 'materials' ? '材料档案读取失败，请重试。' : '合成操作失败，请重试。');
    }

    return {debugState:function() { return {mode:_mode, category:_category, selectedIndex:_selectedIndex, craftCount:_craftCount,
        filterPath:_filterPath.slice(), craftableOnly:_craftableOnly,
        craftableCount:_snapshot && _snapshot.recipes ? _snapshot.recipes.filter(function(recipe) { return recipe.canCraftOne === true; }).length : 0,
        busy:_busy, previewBusy:_previewBusy, planBusy:_planBusy,
        organizerBusy:_organizerBusy,
        organizerMounted:_organizerMounted,
        needsReconcile:_needsReconcile, needsRefresh:_needsRefresh, reconcileEpoch:_reconcileEpoch,
        previewFlight:_previewFlight ? {recipeIndex:_previewFlight.recipeIndex, craftCount:_previewFlight.craftCount} : null,
        previewQueued:_previewQueued ? {recipeIndex:_previewQueued.recipeIndex, craftCount:_previewQueued.craftCount} : null,
        checkpointRetry:_checkpointRetryIntent ? {
            recipeIndex:_checkpointRetryIntent.recipeIndex,
            craftCount:_checkpointRetryIntent.craftCount
        } : null,
        previewCheckpoint:_previewCheckpoint ? {category:_previewCheckpoint.category,
            recipeIndex:_previewCheckpoint.recipeIndex, craftCount:_previewCheckpoint.craftCount} : null,
        gender:_snapshot && _snapshot.gender,
        inspector:_inspector && _inspector.debugState ? _inspector.debugState() : null,
        materials:_materials && _materials.debugState ? _materials.debugState() : null,
        detail:_detailPresenter && _detailPresenter.debugState ? _detailPresenter.debugState() : null,
        materialSessionVersion:_materialSessionVersion,
        materialSnapshotId:_materialSnapshotId,
        materialSnapshotIntentGeneration:_materialSnapshotIntentGeneration,
        recipeSnapshot:_recipeSnapshotIntent ? {
            generation:_recipeSnapshotIntent.generation,
            callId:_recipeSnapshotIntent.callId,
            kind:_recipeSnapshotIntent.kind,
            category:_recipeSnapshotIntent.use.category,
            recipeIndex:_recipeSnapshotIntent.use.recipeIndex,
            productName:_recipeSnapshotIntent.use.productName,
            recipeOrigin:_recipeSnapshotIntent.use.recipeOrigin,
            sourceKey:_recipeSnapshotIntent.use.sourceKey,
            selectedName:_recipeSnapshotIntent.selectedName
        } : null,
        materialShopNavigation:_materialShopNavigation ? {
            generation:_materialShopNavigation.generation,
            callId:_materialShopNavigation.callId,
            materialSnapshotId:_materialShopNavigation.materialSnapshotId,
            materialName:_materialShopNavigation.materialName,
            shopId:_materialShopNavigation.shopId,
            catalogIndex:_materialShopNavigation.catalogIndex,
            sourceKey:_materialShopNavigation.sourceKey
        } : null,
        procurementNavigation:_procurementNavigation ? {
            generation:_procurementNavigation.generation,
            stage:_procurementNavigation.stage,
            recipeId:_procurementNavigation.recipeId,
            materialName:_procurementNavigation.materialName,
            shopId:_procurementNavigation.shopId,
            catalogIndex:_procurementNavigation.catalogIndex,
            entryId:_procurementNavigation.entryId,
            kshopCategory:_procurementNavigation.kshopCategory,
            navigationCallId:_procurementNavigation.navigationCallId
        } : null,
        nestedRecipeNavigation:_nestedRecipeNavigation ? {
            generation:_nestedRecipeNavigation.generation,
            sourceCategory:_nestedRecipeNavigation.sourceCategory,
            sourceRecipeIndex:_nestedRecipeNavigation.sourceRecipeIndex,
            sourceRecipeId:_nestedRecipeNavigation.sourceRecipeId,
            materialName:_nestedRecipeNavigation.materialName,
            targetCategory:_nestedRecipeNavigation.targetCategory,
            targetRecipeIndex:_nestedRecipeNavigation.targetRecipeIndex,
            targetRecipeId:_nestedRecipeNavigation.targetRecipeId,
            callId:_nestedRecipeNavigation.callId
        } : null,
        materialRecipeReturn:_materialRecipeReturn ? {
            materialName:_materialRecipeReturn.materialName
        } : null,
        canReturnCharacterBuild:_canReturnCharacterBuild,
        panelInstanceId:_panelInstanceId,
        mux:_mux.debugState()}; }};
})();
