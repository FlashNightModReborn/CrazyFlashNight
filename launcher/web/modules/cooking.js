/** 烹饪厨房 — 独立于合成工作台的专属界面。
 *  左列：可抽出的菜谱条（按配方 book 字段分组）；中列：厨具舞台
 *  （按选中菜品所需厨具加载 assets/cooking/<厨具名>.svg|png，缺失回落占位件）；
 *  右列：该菜谱的菜品列表 → 选中后切换为配方详情（材料逐条核对 +
 *  基建条件 + 份数 + 确认烹饪）。协议仍走 CraftingRuntime mux，
 *  snapshot/preview/commit 语义与其他品类一致。 */
var CookingPanel = (function() {
    'use strict';
    var _host = null;
    var _el = null, _statusEl = null, _booksEl = null, _stageEl = null,
        _stageCaptionEl = null, _rightEl = null, _closeButton = null,
        _moneyEl = null, _kpointsEl = null;
    var _snapshot = null, _books = [], _selectedBook = '', _selectedIndex = -1,
        _selectedRecipe = null, _preview = null, _craftCount = 1;
    var _busy = false, _previewBusy = false, _generation = 0;
    var _commitFeedback = null;

    function mount(shellEl, deps) {
        _host = deps;
        _generation++;
        _snapshot = null; _books = []; _selectedBook = '';
        _selectedIndex = -1; _selectedRecipe = null; _preview = null;
        _craftCount = 1; _busy = false; _previewBusy = false; _commitFeedback = null;
        buildDOM();
        if (shellEl) shellEl.appendChild(_el);
        refresh();
    }

    function unmount() {
        _generation++;
        if (_el && _el.parentNode) _el.parentNode.removeChild(_el);
        _el = null; _host = null; _snapshot = null; _preview = null;
        _selectedBook = ''; _selectedIndex = -1; _selectedRecipe = null;
        _busy = false; _previewBusy = false;
    }

    function buildDOM() {
        _el = document.createElement('div');
        _el.className = 'cooking-panel';

        var header = document.createElement('header');
        header.className = 'cooking-header';
        var brand = document.createElement('div');
        brand.className = 'cooking-brand';
        brand.innerHTML = '<span class="cooking-kicker">基地厨房</span><h1>烹饪</h1>';
        _statusEl = document.createElement('div');
        _statusEl.className = 'cooking-status';
        _statusEl.textContent = '同步中';
        var metrics = document.createElement('div');
        metrics.className = 'cooking-metrics';
        _moneyEl = document.createElement('span');
        _moneyEl.className = 'cooking-metric';
        _kpointsEl = document.createElement('span');
        _kpointsEl.className = 'cooking-metric kpoints';
        metrics.appendChild(_moneyEl); metrics.appendChild(_kpointsEl);
        _closeButton = document.createElement('button');
        _closeButton.type = 'button';
        _closeButton.className = 'cooking-close';
        _closeButton.textContent = '×';
        _closeButton.setAttribute('aria-label', '关闭烹饪厨房');
        _closeButton.setAttribute('data-audio-cue', 'back');
        _closeButton.addEventListener('click', function() {
            if (_host && _host.requestClose) _host.requestClose('header');
        });
        header.appendChild(brand); header.appendChild(_statusEl);
        header.appendChild(metrics); header.appendChild(_closeButton);

        var body = document.createElement('div');
        body.className = 'cooking-body';
        _booksEl = document.createElement('nav');
        _booksEl.className = 'cooking-books';
        _booksEl.setAttribute('aria-label', '菜谱');
        _stageEl = document.createElement('div');
        _stageEl.className = 'cooking-stage';
        var stageFigure = document.createElement('div');
        stageFigure.className = 'cooking-cookware';
        _stageEl.appendChild(stageFigure);
        _stageCaptionEl = document.createElement('div');
        _stageCaptionEl.className = 'cooking-cookware-label';
        _stageEl.appendChild(_stageCaptionEl);
        var stageHint = document.createElement('div');
        stageHint.className = 'cooking-stage-hint';
        stageHint.textContent = '从左侧抽出菜谱，挑选要做的菜';
        _stageEl.appendChild(stageHint);
        _rightEl = document.createElement('section');
        _rightEl.className = 'cooking-right';
        _rightEl.setAttribute('data-cooking-right', 'list');
        body.appendChild(_booksEl); body.appendChild(_stageEl); body.appendChild(_rightEl);

        _el.appendChild(header); _el.appendChild(body);
        renderBooks(); renderStage(); renderRight();
    }

    function refresh() {
        if (_statusEl) {
            _statusEl.textContent = '同步中';
            _statusEl.setAttribute('data-state', 'loading');
        }
        var generation = _generation;
        _host.request('snapshot', {category:'烹饪'}, function(response) {
            if (generation !== _generation || !_el) return;
            if (!response || !response.success) {
                setStatus('读取失败', 'error');
                toast(errorMessage(response && response.error));
                renderRight(); return;
            }
            _snapshot = response;
            applyBalance(response.balance);
            setStatus(response.note || '就绪', 'ready');
            groupBooks(response.recipes || []);
            if (_selectedBook && !_books.some(function(book) { return book.name === _selectedBook; })) {
                _selectedBook = '';
            }
            if (!_selectedBook && _books.length) _selectedBook = _books[0].name;
            if (_selectedRecipe) {
                var found = findRecipe(_selectedRecipe.recipeIndex);
                if (!found) { _selectedRecipe = null; _selectedIndex = -1; _preview = null; }
                else _selectedRecipe = found;
            }
            renderBooks(); renderStage(); renderRight();
            if (_selectedRecipe) requestPreview();
        });
    }

    function groupBooks(recipes) {
        var order = [], index = {};
        _books = [];
        for (var i = 0; i < recipes.length; i++) {
            var recipe = recipes[i];
            var name = String(recipe.book || '散页菜谱');
            if (index[name] == null) {
                index[name] = _books.length;
                order.push(name);
                _books.push({name:name, recipes:[]});
            }
            _books[index[name]].recipes.push(recipe);
        }
    }

    function findRecipe(recipeIndex) {
        if (!_snapshot || !_snapshot.recipes) return null;
        for (var i = 0; i < _snapshot.recipes.length; i++) {
            if (Number(_snapshot.recipes[i].recipeIndex) === Number(recipeIndex)) {
                return _snapshot.recipes[i];
            }
        }
        return null;
    }

    function bookRecipes() {
        for (var i = 0; i < _books.length; i++) {
            if (_books[i].name === _selectedBook) return _books[i].recipes;
        }
        return [];
    }

    function selectBook(name) {
        if (_selectedBook === name) return;
        _selectedBook = name;
        _selectedIndex = -1; _selectedRecipe = null; _preview = null; _commitFeedback = null;
        renderBooks(); renderStage(); renderRight();
    }

    function selectRecipe(recipeIndex) {
        var recipe = findRecipe(recipeIndex);
        if (!recipe) return;
        _selectedIndex = Number(recipeIndex);
        _selectedRecipe = recipe;
        _craftCount = 1; _preview = null; _commitFeedback = null;
        renderStage(); renderRight(); requestPreview();
    }

    function requestPreview() {
        if (!_selectedRecipe || _busy) return;
        _previewBusy = true; _preview = null; renderRight();
        var generation = _generation;
        var recipeIndex = _selectedIndex, craftCount = _craftCount;
        _host.request('preview', {category:'烹饪', recipeIndex:recipeIndex,
            craftCount:craftCount}, function(response) {
            if (generation !== _generation || !_el) return;
            _previewBusy = false;
            if (_selectedIndex !== recipeIndex || _craftCount !== craftCount) return;
            if (!response || !response.success) {
                _preview = null;
                toast(errorMessage(response && response.error));
            } else {
                _preview = response;
            }
            renderRight();
        });
    }

    function commit() {
        if (_busy || _previewBusy || !_preview || !_preview.canCommit
                || !_preview.craftToken || !_selectedRecipe) return;
        _busy = true; _commitFeedback = null; renderRight();
        var generation = _generation;
        var craftedName = _selectedRecipe.title;
        _host.request('commit', {category:'烹饪',
            expectedCraftToken:_preview.craftToken}, function(response) {
            if (generation !== _generation || !_el) return;
            _busy = false;
            if (response && response.success) {
                toast('已烹饪 ' + (response.crafted && response.crafted.displayName
                    ? response.crafted.displayName : craftedName));
                cue('success');
                _commitFeedback = null;
                _preview = null;
                refresh(); return;
            }
            cue('rejected');
            toast(errorMessage(response && response.error));
            _commitFeedback = errorMessage(response && response.error);
            _preview = null;
            renderRight();
        });
    }

    function renderBooks() {
        if (!_booksEl) return;
        _booksEl.innerHTML = '';
        for (var i = 0; i < _books.length; i++) {
            var book = _books[i];
            var strip = document.createElement('button');
            strip.type = 'button';
            strip.className = 'cooking-book-strip'
                + (book.name === _selectedBook ? ' active' : '');
            strip.setAttribute('data-audio-cue', 'activate');
            strip.setAttribute('aria-pressed', book.name === _selectedBook ? 'true' : 'false');
            var name = document.createElement('span');
            name.className = 'cooking-book-name';
            name.textContent = book.name;
            var count = document.createElement('span');
            count.className = 'cooking-book-count';
            count.textContent = book.recipes.length + ' 道';
            strip.appendChild(name); strip.appendChild(count);
            strip.addEventListener('click', bindBook(name));
            _booksEl.appendChild(strip);
        }
        function bindBook(name) {
            return function() { selectBook(name); };
        }
    }

    function stageAppliance() {
        // 选中菜品的第一条基建条件决定厨具展示；无门槛的菜默认炒锅。
        var recipe = _selectedRecipe;
        var rows = recipe && recipe.infrastructure instanceof Array
            ? recipe.infrastructure : [];
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].appliance) return String(rows[i].appliance);
        }
        if (_preview && _preview.infrastructure instanceof Array) {
            for (var j = 0; j < _preview.infrastructure.length; j++) {
                if (_preview.infrastructure[j].appliance) {
                    return String(_preview.infrastructure[j].appliance);
                }
            }
        }
        return recipe ? '炒锅' : '';
    }

    function renderStage() {
        if (!_stageEl) return;
        var figure = _stageEl.querySelector('.cooking-cookware');
        if (!figure) return;
        var appliance = stageAppliance();
        figure.innerHTML = '';
        if (!appliance) {
            _stageCaptionEl.textContent = '';
            figure.setAttribute('data-appliance', '');
            var idle = document.createElement('div');
            idle.className = 'cooking-cookware-idle';
            idle.textContent = '灶上无火';
            figure.appendChild(idle);
            return;
        }
        figure.setAttribute('data-appliance', appliance);
        var img = document.createElement('img');
        img.className = 'cooking-cookware-img';
        img.alt = appliance;
        img.draggable = false;
        // 资产接口：assets/cooking/<厨具名>.svg → 失败回落 .png → 再回落占位件
        img.src = 'assets/cooking/' + encodeURIComponent(appliance) + '.svg';
        img.addEventListener('error', function onError() {
            img.removeEventListener('error', onError);
            img.remove();
            var fallback = document.createElement('img');
            fallback.className = img.className;
            fallback.alt = appliance;
            fallback.draggable = false;
            fallback.src = 'assets/cooking/' + encodeURIComponent(appliance) + '.png';
            fallback.addEventListener('error', function() {
                fallback.remove();
                mountCookwarePlaceholder(figure, appliance);
            });
            figure.appendChild(fallback);
        });
        figure.appendChild(img);
        _stageCaptionEl.textContent = appliance;
    }

    function mountCookwarePlaceholder(figure, appliance) {
        var placeholder = document.createElement('div');
        placeholder.className = 'cooking-cookware-placeholder';
        placeholder.innerHTML = '<i></i><b>' + escapeHtml(appliance) + '</b>';
        figure.appendChild(placeholder);
    }

    function availabilityLabel(recipe) {
        switch (recipe.availability) {
            case 'ready': return '可做';
            case 'infrastructure_locked': return '缺厨具';
            case 'level_locked': return '等级不足';
            case 'material_missing': return '缺材料';
            case 'insufficient_money': return '金币不足';
            case 'insufficient_kpoint': return 'K点不足';
            case 'inventory_full': return '栏位不足';
            default: return '暂不可做';
        }
    }

    function renderRight() {
        if (!_rightEl) return;
        _rightEl.innerHTML = '';
        if (_selectedRecipe) renderDishDetail();
        else renderDishList();
    }

    function renderDishList() {
        _rightEl.setAttribute('data-cooking-right', 'list');
        var recipes = bookRecipes();
        var list = document.createElement('div');
        list.className = 'cooking-dish-list';
        if (!recipes.length) {
            var empty = document.createElement('div');
            empty.className = 'cooking-empty';
            empty.textContent = _snapshot ? '这本菜谱还没有可做的菜。' : '同步中…';
            list.appendChild(empty);
        }
        for (var i = 0; i < recipes.length; i++) {
            var recipe = recipes[i];
            var row = document.createElement('button');
            row.type = 'button';
            row.className = 'cooking-dish-row ' + availabilityClass(recipe.availability);
            row.setAttribute('data-audio-cue', 'activate');
            var icon = document.createElement('span');
            icon.className = 'cooking-dish-icon';
            icon.innerHTML = _host.iconHtml(recipe.output.icon, 'cooking-icon');
            var name = document.createElement('span');
            name.className = 'cooking-dish-name';
            name.textContent = recipe.title;
            var state = document.createElement('span');
            state.className = 'cooking-dish-state';
            state.textContent = availabilityLabel(recipe);
            row.appendChild(icon); row.appendChild(name); row.appendChild(state);
            row.addEventListener('click', bindDish(recipe.recipeIndex));
            list.appendChild(row);
        }
        _rightEl.appendChild(list);
        function bindDish(recipeIndex) {
            return function() { selectRecipe(recipeIndex); };
        }
    }

    function availabilityClass(availability) {
        return availability === 'ready' ? 'is-ready' : 'is-blocked';
    }

    function renderDishDetail() {
        _rightEl.setAttribute('data-cooking-right', 'detail');
        var recipe = _selectedRecipe;
        var detail = document.createElement('div');
        detail.className = 'cooking-detail';

        var head = document.createElement('div');
        head.className = 'cooking-detail-head';
        var icon = document.createElement('span');
        icon.className = 'cooking-detail-icon';
        icon.innerHTML = _host.iconHtml(recipe.output.icon, 'cooking-icon-lg');
        var titleBlock = document.createElement('div');
        titleBlock.className = 'cooking-detail-title';
        var title = document.createElement('b');
        title.textContent = recipe.title;
        var owned = document.createElement('small');
        owned.textContent = '现有 ' + recipe.owned.total + ' 份';
        titleBlock.appendChild(title); titleBlock.appendChild(owned);
        head.appendChild(icon); head.appendChild(titleBlock);
        detail.appendChild(head);

        var body = document.createElement('div');
        body.className = 'cooking-detail-body';
        if (_previewBusy) {
            var loading = document.createElement('div');
            loading.className = 'cooking-detail-note';
            loading.textContent = '正在核算材料…';
            body.appendChild(loading);
        } else if (_preview) {
            renderRequirements(body, _preview);
        } else {
            var wait = document.createElement('div');
            wait.className = 'cooking-detail-note';
            wait.textContent = recipe.canCraftOne
                ? '等待核算结果…' : availabilityLabel(recipe);
            body.appendChild(wait);
        }
        if (_commitFeedback) {
            var feedback = document.createElement('div');
            feedback.className = 'cooking-detail-note warn';
            feedback.textContent = _commitFeedback;
            body.appendChild(feedback);
        }
        detail.appendChild(body);

        var footer = document.createElement('div');
        footer.className = 'cooking-detail-footer';
        if (recipe.batchEligible) {
            var stepper = document.createElement('div');
            stepper.className = 'cooking-count';
            var minus = document.createElement('button');
            minus.type = 'button'; minus.textContent = '−';
            minus.setAttribute('aria-label', '减少一份');
            minus.disabled = _craftCount <= 1 || _busy || _previewBusy;
            minus.addEventListener('click', function() { setCraftCount(_craftCount - 1); });
            var input = document.createElement('input');
            input.className = 'cooking-count-input';
            input.type = 'text'; input.inputMode = 'numeric';
            input.value = String(_craftCount);
            input.setAttribute('aria-label', '烹饪份数');
            input.addEventListener('change', function() {
                setCraftCount(Number(input.value));
            });
            input.addEventListener('keydown', function(event) {
                if (event.key === 'Enter') { input.blur(); }
                else if (event.key === 'Escape') {
                    input.value = String(_craftCount); input.blur();
                }
            });
            var plus = document.createElement('button');
            plus.type = 'button'; plus.textContent = '+';
            plus.setAttribute('aria-label', '增加一份');
            plus.disabled = _craftCount >= maxCount() || _busy || _previewBusy;
            plus.addEventListener('click', function() { setCraftCount(_craftCount + 1); });
            stepper.appendChild(minus); stepper.appendChild(input); stepper.appendChild(plus);
            footer.appendChild(stepper);
        }
        var cost = document.createElement('div');
        cost.className = 'cooking-cost';
        cost.textContent = costText(recipe);
        footer.appendChild(cost);
        var confirm = document.createElement('button');
        confirm.type = 'button';
        confirm.className = 'cooking-confirm';
        confirm.textContent = _busy ? '烹饪中…' : '确认烹饪';
        var committable = !!_preview && _preview.canCommit && !_busy && !_previewBusy;
        confirm.disabled = !committable;
        if (!committable) confirm.setAttribute('aria-disabled', 'true');
        confirm.setAttribute('data-audio-cue', 'activate');
        confirm.addEventListener('click', commit);
        footer.appendChild(confirm);
        detail.appendChild(footer);
        _rightEl.appendChild(detail);
    }

    function renderRequirements(body, preview) {
        var infra = preview.infrastructure instanceof Array ? preview.infrastructure : [];
        for (var i = 0; i < infra.length; i++) {
            var row = infra[i];
            var node = document.createElement('div');
            node.className = 'cooking-req infra ' + (row.met ? 'met' : 'unmet');
            var label = document.createElement('span');
            label.className = 'cooking-req-name';
            label.textContent = row.name + (row.appliance ? '·' + row.appliance : '');
            var value = document.createElement('span');
            value.className = 'cooking-req-value';
            value.textContent = 'Lv.' + row.current + ' / Lv.' + row.required;
            node.appendChild(label); node.appendChild(value);
            body.appendChild(node);
        }
        var materials = preview.materials || [];
        for (var m = 0; m < materials.length; m++) {
            var material = materials[m];
            var line = document.createElement('div');
            line.className = 'cooking-req ' + (material.enough ? 'met' : 'unmet');
            var iconNode = document.createElement('span');
            iconNode.className = 'cooking-req-icon';
            iconNode.innerHTML = _host.iconHtml(material.icon, 'cooking-icon-sm');
            var nameNode = document.createElement('span');
            nameNode.className = 'cooking-req-name';
            nameNode.textContent = material.displayName
                + (material.consumed ? '' : '（不消耗）');
            var count = document.createElement('span');
            count.className = 'cooking-req-value';
            count.textContent = material.owned + ' / ' + material.required;
            line.appendChild(iconNode); line.appendChild(nameNode); line.appendChild(count);
            body.appendChild(line);
        }
    }

    function maxCount() {
        if (_preview && Number.isInteger(_preview.maxCraftCount)
                && _preview.maxCraftCount > 0) return _preview.maxCraftCount;
        return 99;
    }

    function setCraftCount(next) {
        var value = Math.floor(Number(next));
        if (isNaN(value)) value = 1;
        value = Math.max(1, Math.min(99, value));
        if (value === _craftCount) { renderRight(); return; }
        _craftCount = value;
        _preview = null; renderRight(); requestPreview();
    }

    function costText(recipe) {
        var money = Number(recipe.baseCost && recipe.baseCost.money || 0);
        var kpoints = Number(recipe.baseCost && recipe.baseCost.kpoints || 0);
        var parts = [];
        if (money > 0) parts.push('金币 ' + _host.formatNumber(money * _craftCount));
        if (kpoints > 0) parts.push('K点 ' + _host.formatNumber(kpoints * _craftCount));
        return parts.length ? '费用：' + parts.join('　') : '免加工费';
    }

    function applyBalance(balance) {
        if (!balance) return;
        _moneyEl.textContent = '金币 ' + _host.formatNumber(balance.money);
        _kpointsEl.textContent = 'K点 ' + _host.formatNumber(balance.kpoints);
    }

    function setStatus(text, state) {
        _statusEl.textContent = text;
        _statusEl.setAttribute('data-state', state);
    }

    function errorMessage(error) {
        var messages = {category_not_found:'未找到烹饪分类。', recipe_not_found:'菜谱已变化。',
            item_not_found:'未找到该材料或菜品。', level_locked:'角色等级与逆向等级不足。',
            infrastructure_locked:'厨具等级不足，需要先在基地建造对应烹饪设备。',
            material_missing:'所需材料不足。', insufficient_money:'金币不足。',
            insufficient_kpoint:'K 点不足。', inventory_full:'背包空间不足。',
            stale_state:'物品状态已变化，请重新核对。', batch_not_supported:'该菜品只能逐份烹饪。',
            busy:'厨房正在处理另一项烹饪。', reconcile_required:'上次提交结果需要重新核对。',
            stale_snapshot:'菜谱目录已更新，请重新同步。',
            malformed_response:'回包不完整。', timeout:'烹饪响应超时。',
            client_timeout:'烹饪响应超时。', disconnected:'连接已断开。'};
        return messages[error] || '烹饪操作失败，请重试。';
    }

    function toast(message) { if (_host && _host.toast) _host.toast(message); }
    function cue(name) { if (_host && _host.cue) _host.cue(name); }
    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }

    return {
        mount:mount,
        unmount:unmount,
        refresh:refresh,
        isBusy:function() { return _busy || _previewBusy; },
        debugState:function() { return {
            book:_selectedBook, selectedIndex:_selectedIndex,
            craftCount:_craftCount, busy:_busy, previewBusy:_previewBusy,
            books:_books.map(function(book) { return book.name; })
        }; }
    };
})();
