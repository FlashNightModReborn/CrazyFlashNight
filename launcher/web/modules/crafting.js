/** 合成工作台 — 左侧配方目录，右侧 Flash 权威预览与一次性提交。 */
var CraftingPanel = (function() {
    'use strict';
    var _shellEl, _shell, _catalogView, _detailView, _catalogRenderer, _detailBody;
    var _category = '', _snapshot = null, _preview = null, _selectedIndex = -1, _craftCount = 1;
    var _busy = false, _previewBusy = false, _organizerBusy = false, _needsReconcile = false, _generation = 0;
    var _scaleHandle = null, _retryButton = null, _organizerButton = null, _commitButton = null, _craftableToggle = null, _tooltipCache = {};
    var _filterTree = null, _filterNavigator = null, _filterPath = [];
    var _craftableOnly = false;
    var _config = (typeof window !== 'undefined' && window.__CRAFTING_CONFIG__) || {};
    var _mux = new CraftingRuntime.RequestMux({
        send:function(message) { Bridge.send(message); },
        timeoutMs:_config.requestTimeoutMs,
        sessionNonce:_config.sessionNonce
    });

    Panels.register('crafting', {
        create:createDOM,
        onOpen:onOpen,
        onClose:cleanup,
        onRequestClose:requestClose,
        onForceClose:function() { cleanup(); toast('连接断开，合成工作台已关闭'); }
    });

    function createDOM() {
        _shellEl = document.createElement('div');
        _shellEl.className = 'panel-scale-shell crafting-scale-shell';
        return _shellEl;
    }

    function buildDOM() {
        disposeFilterNavigator();
        while (_shellEl.firstChild) _shellEl.removeChild(_shellEl.firstChild);
        if (_shell) _shell.destroy();
        _shell = new Workbench.DualPaneShell({title:_category || '合成工作台', subtitle:'权威预览',
            status:'同步中', leftLabel:'配方目录', rightLabel:'合成详情', flowLabel:'核算'});
        var root = _shell.getRoot();
        root.classList.add('kshop-workbench', 'crafting-panel');
        root.setAttribute('data-workbench-skin', 'crafting');
        _shellEl.appendChild(root);

        _retryButton = document.createElement('button');
        _retryButton.type = 'button'; _retryButton.className = 'workbench-mode-btn warning';
        _retryButton.textContent = '重新核对'; _retryButton.addEventListener('click', reconcile);
        _shell.addHeaderAction(_retryButton);
        _organizerButton = document.createElement('button');
        _organizerButton.type = 'button'; _organizerButton.className = 'workbench-mode-btn crafting-organizer-btn';
        _organizerButton.textContent = '背包 / 战备箱';
        _organizerButton.setAttribute('aria-label', '切换到背包—战备箱整理；返回后会重新核算当前配方');
        _organizerButton.addEventListener('click', openOrganizer);
        _shell.addHeaderAction(_organizerButton);
        var close = document.createElement('button');
        close.type = 'button'; close.className = 'workbench-close-btn'; close.textContent = '×';
        close.setAttribute('aria-label', '关闭合成工作台'); close.addEventListener('click', requestClose);
        _shell.addHeaderAction(close);

        _catalogView = createCatalogView();
        _detailView = createDetailView();
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
            className:'crafting-catalog-grid', emptyText:'该分类暂无可用配方',
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
        var root = document.createElement('div'); root.className = 'workbench-view crafting-detail-view';
        var chrome = new Workbench.ViewChrome({title:'合成详情', kicker:'权威核算', meta:'请选择配方'});
        _detailBody = document.createElement('div'); _detailBody.className = 'crafting-detail-body';
        root.appendChild(chrome.root); root.appendChild(_detailBody);
        return {instanceKey:'crafting:detail', instancePolicy:'singletonByBinding', allowedSlots:['R'],
            viewKind:'detail', root:root, chrome:chrome,
            mount:function(container) { container.appendChild(root); },
            unmount:function() { if (root.parentNode) root.parentNode.removeChild(root); },
            render:renderDetail};
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

    function renderCatalog() {
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
            _catalogRenderer.render(visible);
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
            _craftCount = 1; _preview = null;
            renderCatalog(); renderDetail();
            if (_selectedIndex >= 0) requestPreview(); else refreshControls();
            return;
        }
        renderCatalog();
    }

    function selectRecipe(recipeIndex) {
        if (_busy || recipeIndex < 0) return;
        _selectedIndex = recipeIndex; _craftCount = 1; _preview = null;
        if (_catalogRenderer) _catalogRenderer.setSelectedKey(String(recipeIndex));
        renderDetail(); requestPreview();
    }

    function requestPreview(callback) {
        if (_selectedIndex < 0 || !_category || _previewBusy) return false;
        _previewBusy = true; refreshControls(); renderDetail();
        var generation = _generation, requestedIndex = _selectedIndex, requestedCount = _craftCount;
        return !!request('preview', {category:_category, recipeIndex:requestedIndex, craftCount:requestedCount}, function(response) {
            if (generation !== _generation) return;
            _previewBusy = false;
            if (requestedIndex !== _selectedIndex || requestedCount !== _craftCount) {
                renderDetail(); refreshControls(); requestPreview(); return;
            }
            if (response.success) {
                _preview = response; _needsReconcile = false; applyBalance(response.balance);
            } else {
                _preview = null;
                if (isAmbiguous(response)) _needsReconcile = true;
                toast(errorMessage(response.error));
            }
            renderDetail(); refreshControls(); if (callback) callback(response);
        });
    }

    function renderDetail() {
        if (!_detailBody) return;
        while (_detailBody.firstChild) _detailBody.removeChild(_detailBody.firstChild);
        if (_selectedIndex < 0) { appendEmpty('从左侧选择一项配方'); return; }
        if (_previewBusy || !_preview) { appendEmpty(_previewBusy ? '正在向 Flash 核算材料与容量…' : '等待权威预览'); return; }
        var output = _preview.output || {};
        _detailView.chrome.setTitle(output.displayName || output.name || '合成详情', '权威核算');
        _detailView.chrome.setMeta(_snapshot && _snapshot.note ? _snapshot.note : '提交前会再次校验');

        var hero = document.createElement('section'); hero.className = 'crafting-output-card';
        var icon = document.createElement('span'); icon.className = 'crafting-output-icon';
        icon.innerHTML = iconHtml(output.icon || output.name, 'kshop-icon'); bindTooltip(icon, output);
        var copy = document.createElement('div'); copy.className = 'crafting-output-copy';
        var title = document.createElement('h2'); title.textContent = output.displayName || output.name || '产物';
        var value = document.createElement('p');
        value.textContent = output.itemKind === 'equipment'
            ? '装备强化 +' + Number(output.enhancementLevel || 1) + ' · 需求等级 ' + Number(output.requiredLevel || 0)
            : '产出数量 ×' + Number(output.quantity || output.value || 1);
        copy.appendChild(title); copy.appendChild(value); hero.appendChild(icon); hero.appendChild(copy);
        _detailBody.appendChild(hero);
        if (_preview.batchEligible) _detailBody.appendChild(renderQuantityControl());

        var list = document.createElement('section'); list.className = 'crafting-material-list';
        var heading = document.createElement('h3'); heading.textContent = '所需材料'; list.appendChild(heading);
        var rows = _preview.materials || [];
        if (!rows.length) {
            var noMaterial = document.createElement('div'); noMaterial.className = 'crafting-material-empty';
            noMaterial.textContent = '该配方不消耗材料'; list.appendChild(noMaterial);
        }
        rows.forEach(function(material) { list.appendChild(renderMaterialRow(material)); });
        _detailBody.appendChild(list);

        var summary = document.createElement('section'); summary.className = 'crafting-cost-summary';
        var cost = _preview.cost || {};
        summary.innerHTML = '<span>金币 <b>' + formatNumber(cost.money) + '</b></span>'
            + '<span>K 点 <b>' + formatNumber(cost.kpoints) + '</b></span>'
            + '<span class="crafting-capacity ' + (_preview.enoughSpace ? 'ok' : 'bad') + '">'
            + (_preview.enoughSpace ? '容量可用' : '背包空间不足') + '</span>';
        _detailBody.appendChild(summary);

        var status = document.createElement('div');
        status.className = 'crafting-commit-status ' + (_preview.canCommit ? 'ok' : 'bad');
        status.textContent = _preview.canCommit
            ? '条件满足，可安全提交 ' + Number(_preview.craftCount || 1) + ' 份'
            : errorMessage(_preview.blockingError);
        _detailBody.appendChild(status);
        _commitButton = document.createElement('button'); _commitButton.type = 'button';
        _commitButton.className = 'crafting-commit-btn'; _commitButton.textContent = _busy ? '提交中…' : '确认合成';
        _commitButton.setAttribute('aria-label', '确认合成 ' + Number(_preview.craftCount || 1) + ' 份');
        _commitButton.setAttribute('data-title', '确认合成');
        _commitButton.disabled = _busy || _needsReconcile || !_preview.canCommit || !_preview.craftToken;
        _commitButton.addEventListener('click', commitCraft); _detailBody.appendChild(_commitButton);
    }

    function renderQuantityControl() {
        var max = Math.max(0, Number(_preview.maxCraftCount) || 0);
        var control = document.createElement('section'); control.className = 'crafting-quantity-control';
        var label = document.createElement('span'); label.className = 'crafting-quantity-label'; label.textContent = '合成份数';
        var group = document.createElement('div'); group.className = 'crafting-quantity-stepper';
        var minus = quantityButton('−', '减少一份', function() { setCraftCount(_craftCount - 1); });
        var value = document.createElement('output'); value.className = 'crafting-quantity-value';
        value.value = String(_craftCount); value.textContent = String(_craftCount);
        var plus = quantityButton('+', '增加一份', function() { setCraftCount(_craftCount + 1); });
        var maximum = quantityButton('最大', '使用当前权威可合成上限', function() { if (max > 0) setCraftCount(max); });
        minus.setAttribute('data-title', '减少一份');
        plus.setAttribute('data-title', '增加一份');
        maximum.setAttribute('data-title', '合成上限 ' + max + ' 份');
        minus.disabled = _craftCount <= 1 || _busy || _previewBusy;
        plus.disabled = max <= 0 || _craftCount >= max || _busy || _previewBusy;
        maximum.disabled = max <= 0 || _craftCount === max || _busy || _previewBusy;
        group.appendChild(minus); group.appendChild(value); group.appendChild(plus); group.appendChild(maximum);
        var hint = document.createElement('small'); hint.textContent = max > 0 ? '当前最多 ' + max + ' 份' : '当前资源不足 1 份';
        control.appendChild(label); control.appendChild(group); control.appendChild(hint); return control;
    }

    function quantityButton(text, ariaLabel, handler) {
        var button = document.createElement('button'); button.type = 'button';
        button.className = 'crafting-quantity-btn'; button.textContent = text;
        button.setAttribute('aria-label', ariaLabel); button.addEventListener('click', handler); return button;
    }

    function setCraftCount(value) {
        if (_busy || _previewBusy || !_preview || !_preview.batchEligible) return false;
        var max = Math.max(0, Number(_preview.maxCraftCount) || 0);
        var next = Math.max(1, Math.min(99, Math.floor(Number(value) || 1)));
        if (max > 0) next = Math.min(next, max);
        if (next === _craftCount) return false;
        _craftCount = next; _preview = null; renderDetail(); requestPreview(); return true;
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
        if (_busy || _needsReconcile || !_preview || !_preview.canCommit || !_preview.craftToken) return;
        _busy = true; refreshControls(); renderDetail();
        var preferred = _selectedIndex, preferredCount = _craftCount;
        request('commit', {category:_category, expectedCraftToken:_preview.craftToken}, function(response) {
            _busy = false;
            if (response.success) {
                toast('已合成 ' + ((response.crafted && response.crafted.displayName) || '目标物品'));
                _preview = null; refreshSnapshot(preferred, preferredCount); return;
            }
            if (isAmbiguous(response)) {
                _needsReconcile = true; toast('提交结果不明确，正在向 Flash 对账。');
                requestPreview();
            } else {
                toast(errorMessage(response.error)); _preview = null; requestPreview();
            }
            renderDetail(); refreshControls();
        });
    }

    function refreshSnapshot(preferredIndex, preferredCount) {
        if (!_category) return false;
        _shell.setStatus('同步中', 'loading');
        var generation = _generation;
        return !!request('snapshot', {category:_category}, function(response) {
            if (generation !== _generation) return;
            if (!response.success) {
                _needsReconcile = true; toast(errorMessage(response.error)); refreshControls(); return;
            }
            _snapshot = response; applyBalance(response.balance); rebuildFilterTree(); renderCatalog();
            var recipes = response.recipes || [], visible = filteredRecipes(recipes);
            var next = Number(preferredIndex);
            if (isNaN(next) || next < 0 || !visible.some(function(recipe) { return Number(recipe.recipeIndex) === next; })) {
                next = visible.length ? Number(visible[0].recipeIndex) : -1;
            }
            _selectedIndex = next;
            _craftCount = Math.max(1, Math.min(99, Math.floor(Number(preferredCount) || 1)));
            _preview = null; renderCatalog(); renderDetail();
            if (next >= 0) requestPreview(); else refreshControls();
        });
    }

    function reconcile() {
        if (_selectedIndex >= 0) requestPreview(); else refreshSnapshot();
    }

    function openOrganizer() {
        if (_busy || _previewBusy || _organizerBusy || !_category) return false;
        _organizerBusy = true; refreshControls();
        var generation = _generation;
        return !!request('snapshot', {category:_category}, function(response) {
            if (generation !== _generation) return;
            _organizerBusy = false;
            if (!response.success) { toast(errorMessage(response.error)); refreshControls(); return; }
            _preview = null;
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

    function appendEmpty(text) {
        var empty = document.createElement('div'); empty.className = 'crafting-detail-empty';
        empty.textContent = text; _detailBody.appendChild(empty);
    }

    function refreshControls() {
        if (!_shell) return;
        if (_needsReconcile) _shell.setStatus('需要重新核对', 'error');
        else if (_organizerBusy) _shell.setStatus('正在打开战备箱', 'loading');
        else if (_busy || _previewBusy) _shell.setStatus('权威核算中', 'loading');
        else if (_snapshot) _shell.setStatus('Flash 权威状态', 'idle');
        else _shell.setStatus('同步中', 'loading');
        if (_retryButton) { _retryButton.style.display = _needsReconcile ? '' : 'none'; _retryButton.disabled = _previewBusy; }
        if (_organizerButton) _organizerButton.disabled = _busy || _previewBusy || _organizerBusy || _needsReconcile;
        if (_filterNavigator) _filterNavigator.setDisabled(_busy || _previewBusy || _organizerBusy);
        if (_craftableToggle) _craftableToggle.disabled = _busy || _previewBusy || _organizerBusy;
        if (_commitButton) _commitButton.disabled = _busy || _needsReconcile || !_preview || !_preview.canCommit || !_preview.craftToken;
    }

    function onOpen(el, initData) {
        _generation++;
        var nextCategory = initData && typeof initData.category === 'string' ? initData.category : '';
        if (nextCategory !== _category) { _filterPath = []; _craftableOnly = false; }
        _category = nextCategory;
        var preferredIndex = initData && Number(initData.preferredRecipeIndex);
        var preferredCount = initData && Number(initData.preferredCraftCount);
        _snapshot = null; _preview = null; _selectedIndex = -1; _busy = false; _previewBusy = false;
        _craftCount = 1; _organizerBusy = false; _needsReconcile = false; _tooltipCache = {}; buildDOM();
        if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = typeof PanelScale !== 'undefined' ? PanelScale.attach(_shellEl, 1024, 576) : null;
        _mux.openSession(); refreshSnapshot(preferredIndex, preferredCount);
    }

    function cleanup() {
        _generation++; _mux.closeSession();
        if (_scaleHandle) { _scaleHandle.detach(); _scaleHandle = null; }
        if (_shell) _shell.closeModal();
        _busy = false; _previewBusy = false; _organizerBusy = false; _snapshot = null; _preview = null;
        disposeFilterNavigator(); _craftableToggle = null;
        if (typeof PanelTooltip !== 'undefined') PanelTooltip.hide();
    }

    function disposeFilterNavigator() {
        if (_filterNavigator && typeof _filterNavigator.destroy === 'function') _filterNavigator.destroy();
        _filterNavigator = null;
    }

    function requestClose() {
        if (_busy || _organizerBusy) { toast('合成状态正在确认，请稍候。'); return; }
        Panels.close(); Bridge.send({type:'panel', cmd:'close', panel:'crafting'});
    }

    function request(cmd, payload, callback) { payload = payload || {}; payload.v = 1; return _mux.request(cmd, payload, callback); }

    function bindTooltip(node, item) {
        if (!node || !item || !item.name || typeof PanelTooltip === 'undefined') return;
        PanelTooltip.bindAsyncHover(node, {
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

    function isAmbiguous(response) {
        var error = response && response.error;
        return !!(response && response.requiresReconcile) || error === 'timeout' || error === 'client_timeout'
            || error === 'disconnected' || error === 'reconcile_required' || error === 'malformed_response';
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
        var messages = {category_not_found:'未找到该合成分类。', recipe_not_found:'配方已变化。', item_not_found:'配方包含未知物品。',
            level_locked:'角色等级与逆向等级不足。', material_missing:'所需材料不足。', insufficient_money:'金币不足。',
            insufficient_kpoint:'K 点不足。', inventory_full:'背包空间不足。', stale_state:'物品状态已变化，请重新核对。',
            batch_not_supported:'该配方包含装备产物或装备素材，只能逐份合成。',
            busy:'Flash 正在处理另一项合成。', reconcile_required:'上次提交结果需要重新核对。',
            malformed_response:'Flash 回包不完整。', timeout:'合成响应超时。', client_timeout:'合成响应超时。', disconnected:'连接已断开。'};
        return messages[error] || '合成操作失败，请重试。';
    }

    Bridge.on('panel_resp', function(data) { _mux.handleResponse(data); });
    return {debugState:function() { return {category:_category, selectedIndex:_selectedIndex, craftCount:_craftCount,
        filterPath:_filterPath.slice(), craftableOnly:_craftableOnly,
        craftableCount:_snapshot && _snapshot.recipes ? _snapshot.recipes.filter(function(recipe) { return recipe.canCraftOne === true; }).length : 0,
        busy:_busy, previewBusy:_previewBusy, organizerBusy:_organizerBusy,
        needsReconcile:_needsReconcile, mux:_mux.debugState()}; }};
})();
