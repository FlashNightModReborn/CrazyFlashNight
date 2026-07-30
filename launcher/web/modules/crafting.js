/** 合成工作台 — 左侧配方目录，右侧 Flash 权威预览与一次性提交。 */
var CraftingPanel = (function() {
    'use strict';
    var _shellEl, _shell, _catalogView, _detailView, _catalogRenderer, _detailPresenter;
    var _mode = 'recipes', _materials = null, _materialRequestSeq = 0;
    var _category = '', _snapshot = null, _preview = null, _previewCheckpoint = null, _selectedIndex = -1, _craftCount = 1;
    var _busy = false, _previewBusy = false, _organizerBusy = false, _needsReconcile = false, _needsRefresh = false, _generation = 0;
    var _previewFlight = null, _previewQueued = null, _checkpointRetryIntent = null;
    var _scaleHandle = null, _retryButton = null, _organizerButton = null, _craftableToggle = null, _tooltipCache = {};
    var _inspector = null, _tooltipScope = null;
    var _filterTree = null, _filterNavigator = null, _filterPath = [];
    var _craftableOnly = false;
    var _densityController = null, _helpAction = null;
    var _returnCharacterBuildButton = null, _returnNavigationTimer = null;
    var _panelInstanceId = '', _canReturnCharacterBuild = false;
    var _config = (typeof window !== 'undefined' && window.__CRAFTING_CONFIG__) || {};
    var _mux = new CraftingRuntime.RequestMux({
        send:function(message) { return Bridge.send(message); },
        timeoutMs:_config.requestTimeoutMs,
        sessionNonce:_config.sessionNonce
    });

    Panels.register('crafting', {
        create:createDOM,
        onOpen:onOpen,
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
        if (_mode === 'materials') {
            _densityController = new Workbench.GridDensityController({
                panelId:'crafting-materials',
                defaultMode:'compact'
            });
            root.setAttribute('data-layout-mode', _densityController.mode);
            _shell.addHeaderAction(_densityController.createToggle(function(mode) {
                root.setAttribute('data-layout-mode', mode);
            }));
        }
        _returnCharacterBuildButton = null;
        if (_canReturnCharacterBuild) {
            _returnCharacterBuildButton = document.createElement('button');
            _returnCharacterBuildButton.type = 'button';
            _returnCharacterBuildButton.className =
                'workbench-mode-btn crafting-return-character-btn';
            _returnCharacterBuildButton.textContent = '← 返回装备';
            _returnCharacterBuildButton.setAttribute(
                'aria-label', '返回角色构筑装备并重新读取当前装备');
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
            message:'浏览与筛选\n• 搜索框可按材料名称过滤；“已持有”和“有用途”只改变本地视图。\n• 紧凑模式以图标为主，适合快速扫视；完整模式同时显示持有量、来源数和用途数。',
            detail:'查看来源与用途\n• 选择左侧材料后，右侧会列出掉落敌人、关卡、任务或商店来源。\n• “会用在哪里”列出引用该材料的合成项目及每份需求。\n• 方向键在当前网格移动，Home / End 可直达首尾；Enter 打开当前材料。',
            actions:[{id:'close', label:'知道了', primary:true, audioCue:'confirm'}]
        } : {
            kind:'crafting-help',
            ariaLabel:'查看合成工作台帮助',
            title:'合成工作台帮助',
            message:'选择配方后，右侧会显示权威材料、费用、容量与产物预览。批量配方可用 − / +、+5、“最大”、数字输入或滑杆选择 1–99 份；核算期间仍可继续调整，提交会等最新份数核算完成。',
            detail:'数字输入按 Enter 确认、按 Esc 撤回未确认文字。滑杆可用方向键逐份调整，Shift + 方向键每次 5 份，Page Up / Page Down 跨数量级，Home / End 到两端。“只看可合成”只筛选当前目录；“背包 / 战备箱”返回后会重新核算原配方。',
            actions:[{id:'close', label:'知道了', primary:true, audioCue:'confirm'}]
        }});
        var close = document.createElement('button');
        close.type = 'button'; close.className = 'workbench-close-btn'; close.textContent = '×';
        close.setAttribute('aria-label', _mode === 'materials' ? '关闭材料档案' : '关闭合成工作台');
        close.addEventListener('click', function() { requestClose('header'); });
        _shell.addHeaderAction(close);

        if (_mode === 'materials') {
            _catalogRenderer = null;
            _craftableToggle = null;
            _materials = CraftingMaterials.create({
                iconHtml:iconHtml,
                bindTooltip:bindTooltip,
                onSelect:requestMaterialDetail,
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
            renderMaterialRow:renderMaterialRow,
            onInspect:openInspector,
            onQuantityChange:setCraftCount,
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
        icon.innerHTML = iconHtml(output.icon || output.name, 'kshop-icon');
        var copy = document.createElement('span'); copy.className = 'crafting-card-copy';
        var name = document.createElement('b'); name.textContent = output.displayName || output.name || recipe.title;
        var title = document.createElement('span'); title.textContent = recipe.title || '';
        var meta = document.createElement('small');
        var cost = recipe.baseCost || {};
        meta.textContent = '材料 ' + Number(recipe.materialCount || 0) + ' · ' + costText(cost);
        copy.appendChild(name); copy.appendChild(title); copy.appendChild(meta);
        var availability = document.createElement('span');
        availability.className = 'crafting-card-availability ' + (ready ? 'ready' : 'blocked');
        availability.textContent = ready ? '可合成' : availabilityText(recipe.availability);
        availability.setAttribute('aria-label', ready ? '当前资源可合成 1 份' : errorMessage(recipe.availability));
        node.appendChild(icon); node.appendChild(copy); node.appendChild(availability); return node;
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
        if (_busy || _previewBusy || _organizerBusy) return;
        _filterPath = path.slice();
        applyCatalogFilter();
    }

    function toggleCraftableOnly() {
        if (_busy || _previewBusy || _organizerBusy) return;
        _craftableOnly = !_craftableOnly;
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
        if (_busy || recipeIndex < 0) return;
        _selectedIndex = recipeIndex; _craftCount = 1; _preview = null; clearPreviewCheckpoint();
        if (_catalogRenderer) _catalogRenderer.setSelectedKey(String(recipeIndex));
        renderDetail({preserveScroll:false}); requestPreview();
    }

    function requestPreview() {
        if (_selectedIndex < 0 || !_category) return false;
        var intent = {
            generation:_generation,
            category:_category,
            recipeIndex:_selectedIndex,
            craftCount:_craftCount,
            revision:authorityRevision(_snapshot)
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
            _needsReconcile = true;
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
        var canCommit = !_busy && !_previewBusy && !_organizerBusy && !_needsReconcile && !_needsRefresh
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
            title:(output && (output.displayName || output.name))
                || recipeOutput.displayName || recipeOutput.name || '合成详情',
            kicker:'权威核算',
            meta:_snapshot && _snapshot.note ? _snapshot.note : '提交前会再次校验',
            emptyText:_previewBusy ? '正在向 Flash 核算材料与容量…' : '等待权威预览',
            previewState:previewState,
            pending:_previewBusy,
            output:output || null,
            outputSummary:output ? (output.itemKind === 'equipment'
                ? '装备强化 +' + Number(output.enhancementLevel || 1)
                    + ' · 需求等级 ' + Number(output.requiredLevel || 0)
                : '产出数量 ×' + Number(output.quantity || output.value || 1)) : '',
            materials:preview && preview.materials || [],
            moneyText:formatNumber(cost.money),
            kpointsText:formatNumber(cost.kpoints),
            enoughSpace:!!(preview && preview.enoughSpace),
            batchEligible:!!(recipe && recipe.batchEligible === true),
            craftCount:_craftCount,
            presetMax:preview ? Number(preview.maxCraftCount) || 0 : 0,
            quantityDisabled:_busy || _organizerBusy || _needsReconcile || _needsRefresh,
            canCommit:canCommit,
            commitBusy:_busy || _previewBusy,
            commitLabel:_busy ? '提交中…' : '确认合成',
            commitStatus:commitStatus,
            commitState:commitState,
            commitAriaLabel:'确认合成 ' + _craftCount + ' 份',
            commitTitle:'确认合成'
        });
    }

    function openInspector(output) {
        if (!_shell || typeof CraftingInspector === 'undefined' || !CraftingInspector.open) return false;
        if (typeof PanelTooltip !== 'undefined') PanelTooltip.hide();
        _inspector = CraftingInspector.open({
            shell: _shell,
            output: output,
            gender: _snapshot && _snapshot.gender,
            manifestUrl: _config.inspectorManifestUrl,
            onClose: function() { _inspector = null; }
        });
        return !!_inspector;
    }

    function setCraftCount(value) {
        var recipe = findRecipe(_selectedIndex);
        if (_busy || _organizerBusy || _needsReconcile || _needsRefresh
                || !recipe || recipe.batchEligible !== true) return false;
        var next = Math.max(1, Math.min(99, Math.floor(Number(value) || 1)));
        if (next === _craftCount) return false;
        _craftCount = next;
        requestPreview();
        return true;
    }

    function samePreviewIntent(left, right) {
        return !!left && !!right
            && left.generation === right.generation
            && left.category === right.category
            && left.recipeIndex === right.recipeIndex
            && left.craftCount === right.craftCount
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
        if (_busy) return '正在提交，请稍候';
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

    function renderMaterialRow(material) {
        var row = document.createElement('div'); row.className = 'crafting-material-row ' + (material.enough ? 'ok' : 'bad');
        var icon = document.createElement('span'); icon.className = 'crafting-material-icon';
        icon.innerHTML = iconHtml(material.icon || material.name, 'kshop-icon');
        var copy = document.createElement('span'); copy.className = 'crafting-material-copy';
        var name = document.createElement('b'); name.textContent = material.displayName || material.name;
        var note = document.createElement('small');
        if (material.itemKind === 'equipment' && !material.isQuantity) {
            note.textContent = '最高 +' + Number(material.maxEnhancement || 0) + ' / 需要 +' + Number(material.required || 1);
        } else {
            note.textContent = formatNumber(material.owned) + ' / ' + formatNumber(material.required)
                + (material.consumed === false ? ' · 图纸保留' : '');
        }
        copy.appendChild(name); copy.appendChild(note);
        var mark = document.createElement('span'); mark.className = 'crafting-material-mark';
        mark.textContent = material.enough ? '✓' : '不足';
        row.appendChild(icon); row.appendChild(copy); row.appendChild(mark); bindTooltip(row, material); return row;
    }

    function commitCraft() {
        if (_busy || _previewBusy || _needsReconcile || _needsRefresh || !previewMatchesCurrent()
                || !_preview.canCommit || !_preview.craftToken) return;
        _busy = true; refreshControls(); renderDetail();
        var preferred = _selectedIndex, preferredCount = _craftCount;
        var issuing = true;
        var callId = request('commit', {category:_category, expectedCraftToken:_preview.craftToken}, function(response) {
            var dispatched = !issuing;
            _busy = false;
            if (response.success) {
                toast('已合成 ' + ((response.crafted && response.crafted.displayName) || '目标物品'));
                _preview = null; clearPreviewCheckpoint(); refreshSnapshot(preferred, preferredCount); return;
            }
            if (isWriteAmbiguous(response, dispatched)) {
                _needsReconcile = true; toast('提交结果不明确，正在向 Flash 对账。');
                requestPreview();
            } else if (requiresAuthorityRefresh(response)) {
                toast(errorMessage(response.error)); _preview = null; clearPreviewCheckpoint();
                _needsRefresh = true; refreshSnapshot(preferred, preferredCount); return;
            } else {
                toast(errorMessage(response.error));
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
                    _preview = null; clearPreviewCheckpoint(); _needsReconcile = true; _needsRefresh = false;
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
        _shell.setStatus('同步中', 'loading');
        if (_retryButton) _retryButton.disabled = true;
        _previewBusy = true;
        var generation = _generation;
        return !!request('materials', {}, function(response) {
            if (generation !== _generation || _mode !== 'materials') return;
            _previewBusy = false;
            if (!response.success) {
                _needsRefresh = true;
                if (_materials) _materials.setError(errorMessage(response.error));
                toast(errorMessage(response.error));
                refreshControls();
                return;
            }
            _snapshot = response;
            _needsRefresh = false;
            if (_materials) _materials.setSnapshot(response, preferredName);
            refreshControls();
        });
    }

    function requestMaterialDetail(itemName) {
        if (_mode !== 'materials' || !itemName) return false;
        var generation = _generation;
        var requestSeq = ++_materialRequestSeq;
        _previewBusy = true;
        refreshControls();
        return !!request('materialDetail', {itemName:String(itemName)}, function(response) {
            if (generation !== _generation || requestSeq !== _materialRequestSeq
                    || _mode !== 'materials') return;
            _previewBusy = false;
            if (!response.success) {
                if (_materials) _materials.setError(errorMessage(response.error));
                toast(errorMessage(response.error));
            } else if (_materials) {
                _materials.setDetail(response);
            }
            refreshControls();
        });
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
        if (_busy || _previewBusy || _organizerBusy || _needsReconcile || _needsRefresh || !_category) return false;
        _organizerBusy = true; renderDetail(); refreshControls();
        var generation = _generation;
        return !!request('snapshot', {category:_category}, function(response) {
            if (generation !== _generation) return;
            _organizerBusy = false;
            if (!response.success) {
                if (requiresReconcile(response)) {
                    _preview = null; clearPreviewCheckpoint(); _needsReconcile = true;
                }
                toast(errorMessage(response.error)); renderDetail(); refreshControls(); return;
            }
            _preview = null; clearPreviewCheckpoint();
            Panels.open('workbench', {profile:'battlebox', returnTo:{panel:'crafting', initData:{
                category:_category, preferredRecipeIndex:_selectedIndex, preferredCraftCount:_craftCount
            }}});
        });
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

    function refreshControls() {
        if (!_shell) return;
        if (_mode === 'materials') {
            if (_needsRefresh) _shell.setStatus('需要重新同步', 'error');
            else if (_previewBusy) _shell.setStatus('正在读取材料档案', 'loading');
            else if (_snapshot) _shell.setStatus('材料索引已同步', 'idle');
            else _shell.setStatus('同步中', 'loading');
            if (_retryButton) {
                _retryButton.textContent = '重新同步';
                _retryButton.style.display = _needsRefresh ? '' : 'none';
                _retryButton.disabled = _previewBusy;
            }
            return;
        }
        if (_needsReconcile) _shell.setStatus('需要重新核对', 'error');
        else if (_needsRefresh) _shell.setStatus('需要重新同步', 'error');
        else if (_organizerBusy) _shell.setStatus('正在打开战备箱', 'loading');
        else if (_busy || _previewBusy) _shell.setStatus('权威核算中', 'loading');
        else if (_snapshot) _shell.setStatus('Flash 权威状态', 'idle');
        else _shell.setStatus('同步中', 'loading');
        if (_retryButton) {
            _retryButton.textContent = _needsReconcile ? '重新核对' : '重新同步';
            _retryButton.style.display = _needsReconcile || _needsRefresh ? '' : 'none';
            _retryButton.disabled = _previewBusy;
        }
        if (_organizerButton) _organizerButton.disabled = _busy || _previewBusy || _organizerBusy || _needsReconcile || _needsRefresh;
        if (_filterNavigator) _filterNavigator.setDisabled(_busy || _previewBusy || _organizerBusy || _needsReconcile || _needsRefresh);
        if (_craftableToggle) _craftableToggle.disabled = _busy || _previewBusy || _organizerBusy || _needsReconcile || _needsRefresh;
    }

    function onOpen(el, initData) {
        _generation++;
        _materialRequestSeq++;
        if (_tooltipScope) _tooltipScope.dispose();
        _tooltipScope = typeof PanelTooltip !== 'undefined' && PanelTooltip.createScope
            ? PanelTooltip.createScope('crafting') : null;
        initData = initData || {};
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
        _snapshot = null; _preview = null; clearPreviewCheckpoint(); _selectedIndex = -1; _busy = false; _previewBusy = false;
        _previewFlight = null; _previewQueued = null;
        _craftCount = 1; _organizerBusy = false; _needsReconcile = false; _needsRefresh = false; _tooltipCache = {}; buildDOM();
        if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = typeof PanelScale !== 'undefined' ? PanelScale.attach(_shellEl, 1024, 576) : null;
        _mux.openSession();
        if (_mode === 'materials') refreshMaterialsSnapshot();
        else refreshSnapshot(preferredIndex, preferredCount);
    }

    function cleanup() {
        _generation++; _materialRequestSeq++; _mux.closeSession();
        if (_returnNavigationTimer !== null) {
            clearTimeout(_returnNavigationTimer);
            _returnNavigationTimer = null;
        }
        _previewFlight = null; _previewQueued = null;
        if (_scaleHandle) { _scaleHandle.detach(); _scaleHandle = null; }
        if (_shell) _shell.closeModal();
        _inspector = null;
        _busy = false; _previewBusy = false; _organizerBusy = false; _snapshot = null; _preview = null;
        clearPreviewCheckpoint(); _needsReconcile = false; _needsRefresh = false;
        disposeFilterNavigator(); _craftableToggle = null;
        if (_materials) { _materials.destroy(); _materials = null; }
        if (_densityController) { _densityController.destroy(); _densityController = null; }
        if (_helpAction) { _helpAction.destroy(); _helpAction = null; }
        if (_detailPresenter) { _detailPresenter.destroy(); _detailPresenter = null; }
        if (_tooltipScope) { _tooltipScope.dispose(); _tooltipScope = null; }
        _returnCharacterBuildButton = null;
        _panelInstanceId = '';
        _canReturnCharacterBuild = false;
    }

    function disposeFilterNavigator() {
        if (_filterNavigator && typeof _filterNavigator.destroy === 'function') _filterNavigator.destroy();
        _filterNavigator = null;
    }

    function requestClose(reason) {
        if (_shell && _shell.hasModal()) {
            return _shell.closeModal(typeof reason === 'string' ? reason : 'close');
        }
        if (_busy || _organizerBusy) { toast('工作台状态正在确认，请稍候。'); return; }
        if (Bridge.send({type:'panel', cmd:'close', panel:'crafting'}) === false) {
            toast('启动器连接不可用，工作台保持打开。');
            return false;
        }
        Panels.close();
        return true;
    }

    function requestCharacterBuild() {
        if (!_canReturnCharacterBuild || !_panelInstanceId
                || !_returnCharacterBuildButton) return false;
        if (_busy || _previewBusy || _organizerBusy || _needsReconcile || _needsRefresh) {
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

    function request(cmd, payload, callback) { payload = payload || {}; payload.v = 1; return _mux.request(cmd, payload, callback); }

    function bindTooltip(node, item) {
        if (!node || !item || !item.name || typeof PanelTooltip === 'undefined') return;
        var tooltipBinder = _tooltipScope || PanelTooltip;
        tooltipBinder.bindAsyncHover(node, {
            cache:_tooltipCache, key:'craft:' + item.name, item:item,
            renderBasic:function(value) {
                return '<div class="kshop-tt-header"><b>' + escapeHtml(value.displayName || value.name) + '</b></div>'
                    + '<div class="kshop-tt-loading">加载中…</div>';
            },
            renderRich:function(value, rich) {
                return PanelTooltip.buildItemRichHtml({
                    iconHtml:PanelTooltip.dynamicIconHtml(value.icon || value.name),
                    iconUrl:PanelTooltip.staticIconUrl(value.icon || value.name),
                    introHTML:rich.introHTML || '', descHTML:rich.descHTML || '',
                    rootClass:'crafting-tooltip', layoutType:PanelTooltip.inferLayoutType(value.majorType || value.use)
                });
            },
            fetch:function(_, callback) { request('tooltip', {itemName:String(item.name)}, callback); }
        });
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
        var html = typeof Icons !== 'undefined' && Icons.html
            ? Icons.html(iconName, cls || 'kshop-icon', ' onerror="this.style.display=\'none\'"') : '';
        return html || '<span class="kshop-icon-placeholder"></span>';
    }
    function formatNumber(value) { var number = Number(value || 0); return isNaN(number) ? '0' : number.toLocaleString(); }
    function escapeHtml(value) { return String(value == null ? '' : value).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
    function toast(message) { if (typeof Toast !== 'undefined') Toast.add(message); }
    function errorMessage(error) {
        var messages = {category_not_found:'未找到该合成分类。', recipe_not_found:'配方已变化。', item_not_found:'未找到该材料或配方物品。',
            level_locked:'角色等级与逆向等级不足。', material_missing:'所需材料不足。', insufficient_money:'金币不足。',
            insufficient_kpoint:'K 点不足。', inventory_full:'背包空间不足。', stale_state:'物品状态已变化，请重新核对。',
            batch_not_supported:'该配方包含装备产物或装备素材，只能逐份合成。',
            busy:'Flash 正在处理另一项合成。', reconcile_required:'上次提交结果需要重新核对。',
            malformed_response:'Flash 回包不完整。', timeout:'合成响应超时。', client_timeout:'合成响应超时。', disconnected:'连接已断开。'};
        return messages[error] || (_mode === 'materials' ? '材料档案读取失败，请重试。' : '合成操作失败，请重试。');
    }

    return {debugState:function() { return {mode:_mode, category:_category, selectedIndex:_selectedIndex, craftCount:_craftCount,
        filterPath:_filterPath.slice(), craftableOnly:_craftableOnly,
        craftableCount:_snapshot && _snapshot.recipes ? _snapshot.recipes.filter(function(recipe) { return recipe.canCraftOne === true; }).length : 0,
        busy:_busy, previewBusy:_previewBusy, organizerBusy:_organizerBusy,
        needsReconcile:_needsReconcile, needsRefresh:_needsRefresh,
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
        canReturnCharacterBuild:_canReturnCharacterBuild,
        panelInstanceId:_panelInstanceId,
        mux:_mux.debugState()}; }};
})();
