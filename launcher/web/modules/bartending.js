/** 调酒吧台 — 赛博朋克酒保风格界面，独立于合成工作台。
 *  左列：酒单纸条（按配方 book 分组）；中间：酒品名录；
 *  右侧：吧台操作区——选中酒品后展示配方要求与调制控制台
 *  （摇法三选一 轻摇/猛摇/直接调制，加冰/陈化/卡莫特林开关），
 *  调制方式随 preview 请求提交，由 AS2 逐项比对裁决并冻结进计划。
 *  协议仍走 CraftingRuntime mux，snapshot/preview/commit 语义与其他品类一致。 */
var BartendingPanel = (function() {
    'use strict';
    var _host = null;
    var _el = null, _statusEl = null, _booksEl = null, _listEl = null, _stationEl = null,
        _closeButton = null, _moneyEl = null, _kpointsEl = null;
    var _snapshot = null, _books = [], _selectedBook = '', _selectedIndex = -1,
        _selectedRecipe = null,
        _preview = null, _craftCount = 1;
    var _technique = {shake:'none', ice:false, aged:false, karmotrine:false};
    var _busy = false, _previewBusy = false, _generation = 0;
    var _commitFeedback = null;

    function mount(shellEl, deps) {
        _host = deps;
        _generation++;
        _snapshot = null; _books = []; _selectedBook = '';
        _selectedIndex = -1; _selectedRecipe = null;
        _preview = null;
        _craftCount = 1; _busy = false; _previewBusy = false; _commitFeedback = null;
        _technique = {shake:'none', ice:false, aged:false, karmotrine:false};
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
        _el.className = 'bart-panel';

        var header = document.createElement('header');
        header.className = 'bart-header';
        var brand = document.createElement('div');
        brand.className = 'bart-brand';
        brand.innerHTML = '<span class="bart-kicker">堕落城酒吧</span><h1>调酒</h1>';
        _statusEl = document.createElement('div');
        _statusEl.className = 'bart-status';
        _statusEl.textContent = '同步中';
        var metrics = document.createElement('div');
        metrics.className = 'bart-metrics';
        _moneyEl = document.createElement('span');
        _moneyEl.className = 'bart-metric';
        _kpointsEl = document.createElement('span');
        _kpointsEl.className = 'bart-metric kpoints';
        metrics.appendChild(_moneyEl); metrics.appendChild(_kpointsEl);
        _closeButton = document.createElement('button');
        _closeButton.type = 'button';
        _closeButton.className = 'bart-close';
        _closeButton.textContent = '×';
        _closeButton.setAttribute('aria-label', '关闭调酒吧台');
        _closeButton.setAttribute('data-audio-cue', 'back');
        _closeButton.addEventListener('click', function() {
            if (_host && _host.requestClose) _host.requestClose('header');
        });
        header.appendChild(brand); header.appendChild(_statusEl);
        header.appendChild(metrics); header.appendChild(_closeButton);

        var body = document.createElement('div');
        body.className = 'bart-body';
        _booksEl = document.createElement('nav');
        _booksEl.className = 'bart-books';
        _booksEl.setAttribute('aria-label', '酒单');
        _listEl = document.createElement('div');
        _listEl.className = 'bart-list';
        _stationEl = document.createElement('section');
        _stationEl.className = 'bart-station';
        body.appendChild(_booksEl); body.appendChild(_listEl); body.appendChild(_stationEl);
        _el.appendChild(header); _el.appendChild(body);
        renderBooks(); renderList(); renderStation();
    }

    function refresh() {
        if (_statusEl) {
            _statusEl.textContent = '同步中';
            _statusEl.setAttribute('data-state', 'loading');
        }
        var generation = _generation;
        var callId = _host.request('snapshot', {category:'调酒'}, function(response) {
            if (generation !== _generation || !_el) return;
            if (!response || !response.success) {
                setStatus('读取失败', 'error');
                toast(errorMessage(response && response.error));
                renderStation(); return;
            }
            _snapshot = response;
            applyBalance(response.balance);
            setStatus(response.note || '就绪', 'ready');
            groupBooks(response.recipes || []);
            if (_selectedBook && !_books.some(function(book) { return book.name === _selectedBook; })) {
                _selectedBook = '';
                _selectedIndex = -1; _selectedRecipe = null; _preview = null;
            }
            if (_selectedRecipe) {
                var found = findRecipe(_selectedRecipe.recipeIndex);
                if (!found) {
                    _selectedRecipe = null; _selectedIndex = -1; _preview = null;
                }
                else _selectedRecipe = found;
            }
            renderBooks(); renderList(); renderStation();
            if (_selectedRecipe) requestPreview();
        });
        if (!callId) {
            setStatus('发送失败', 'error');
            toast('合成通道不可用，请关闭后重试。');
        }
    }

    function groupBooks(recipes) {
        var order = [], index = {};
        _books = [];
        for (var i = 0; i < recipes.length; i++) {
            var recipe = recipes[i];
            var name = String(recipe.book || '散页酒单');
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
        if (_selectedBook === name) {
            _selectedBook = '';
            _selectedIndex = -1; _selectedRecipe = null;
            _preview = null; _commitFeedback = null;
            renderBooks(); renderList(); renderStation();
            return;
        }
        _selectedBook = name;
        _selectedIndex = -1; _selectedRecipe = null;
        _preview = null; _commitFeedback = null;
        renderBooks(); renderList(); renderStation();
    }

    function selectRecipe(recipeIndex) {
        var recipe = findRecipe(recipeIndex);
        if (!recipe) return;
        _selectedIndex = Number(recipeIndex);
        _selectedRecipe = recipe;
        _craftCount = 1; _preview = null; _commitFeedback = null;
        // 控制台默认回放配方要求的调制方式；玩家仍可改动，
        // 不匹配时 AS2 以 technique_mismatch 阻断并提示。
        var declared = recipe.technique || null;
        _technique = declared
            ? {shake:declared.shake, ice:declared.ice === true,
                aged:declared.aged === true, karmotrine:false}
            : {shake:'none', ice:false, aged:false, karmotrine:false};
        renderList(); renderStation(); requestPreview();
    }

    function requestPreview() {
        if (!_selectedRecipe || _busy) return;
        _previewBusy = true; renderStation();
        var generation = _generation;
        var recipeIndex = _selectedIndex, craftCount = _craftCount;
        var payload = {category:'调酒', recipeIndex:recipeIndex, craftCount:craftCount};
        if (_selectedRecipe.technique) {
            payload.technique = {shake:_technique.shake, ice:_technique.ice === true,
                aged:_technique.aged === true,
                karmotrine:_selectedRecipe.technique.karmotrine === 'optional'
                    && _technique.karmotrine === true};
        }
        var sentTechnique = payload.technique ? JSON.stringify(payload.technique) : '';
        _host.request('preview', payload, function(response) {
            if (generation !== _generation || !_el) return;
            _previewBusy = false;
            if (_selectedIndex !== recipeIndex || _craftCount !== craftCount) return;
            var current = _selectedRecipe && _selectedRecipe.technique
                ? JSON.stringify({shake:_technique.shake, ice:_technique.ice === true,
                    aged:_technique.aged === true,
                    karmotrine:_selectedRecipe.technique.karmotrine === 'optional'
                        && _technique.karmotrine === true})
                : '';
            if (current !== sentTechnique) return;
            if (!response || !response.success) {
                _preview = null;
                _commitFeedback = errorMessage(response && response.error);
            } else {
                _preview = response; _commitFeedback = null;
            }
            renderStation();
        });
    }

    function commit() {
        if (_busy || _previewBusy || !_preview || !_preview.canCommit
                || !_preview.craftToken || !_selectedRecipe) return;
        _busy = true; _commitFeedback = null; renderStation();
        var generation = _generation;
        var craftedName = _selectedRecipe.title;
        _host.request('commit', {category:'调酒',
            expectedCraftToken:_preview.craftToken}, function(response) {
            if (generation !== _generation || !_el) return;
            _busy = false;
            if (response && response.success) {
                toast('已调制 ' + (response.crafted && response.crafted.displayName
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
            renderStation();
            requestPreview();
        });
    }

    function renderBooks() {
        if (!_booksEl) return;
        _booksEl.innerHTML = '';
        for (var i = 0; i < _books.length; i++) {
            var book = _books[i];
            var slip = document.createElement('button');
            slip.type = 'button';
            slip.className = 'bart-slip'
                + (book.name === _selectedBook ? ' active' : '');
            slip.setAttribute('data-audio-cue', 'activate');
            slip.setAttribute('aria-pressed', book.name === _selectedBook ? 'true' : 'false');
            var nameEl = document.createElement('span');
            nameEl.className = 'bart-slip-name';
            nameEl.textContent = book.name;
            var count = document.createElement('span');
            count.className = 'bart-slip-count';
            count.textContent = book.recipes.length + ' 款';
            slip.appendChild(nameEl); slip.appendChild(count);
            slip.addEventListener('click', bindBook(book.name));
            _booksEl.appendChild(slip);
        }
        function bindBook(name) {
            return function() { selectBook(name); };
        }
    }

    function availabilityLabel(recipe) {
        switch (recipe.availability) {
            case 'ready': return '可调';
            case 'infrastructure_locked': return '缺设备';
            case 'level_locked': return '等级不足';
            case 'material_missing': return '缺原料';
            case 'insufficient_money': return '金币不足';
            case 'insufficient_kpoint': return 'K点不足';
            case 'inventory_full': return '栏位不足';
            default: return '暂不可调';
        }
    }

    function availabilityClass(availability) {
        return availability === 'ready' ? 'is-ready' : 'is-blocked';
    }

    function renderList() {
        if (!_listEl) return;
        _listEl.innerHTML = '';
        var grid = document.createElement('div');
        grid.className = 'bart-drink-grid';
        if (!_selectedBook) {
            grid.classList.add('empty');
            _listEl.appendChild(grid);
            return;
        }
        var recipes = bookRecipes();
        if (!recipes.length) {
            var empty = document.createElement('div');
            empty.className = 'bart-empty';
            empty.textContent = _snapshot ? '这份酒单还没有可调的酒。' : '同步中…';
            grid.appendChild(empty);
        }
        for (var i = 0; i < recipes.length; i++) {
            var recipe = recipes[i];
            var card = document.createElement('button');
            card.type = 'button';
            card.className = 'bart-drink ' + availabilityClass(recipe.availability)
                + (_selectedRecipe && _selectedRecipe.recipeIndex === recipe.recipeIndex
                    ? ' active' : '');
            card.setAttribute('data-audio-cue', 'activate');
            var thumb = document.createElement('span');
            thumb.className = 'bart-drink-thumb';
            thumb.innerHTML = _host.iconHtml(recipe.output.icon, 'bart-icon');
            var name = document.createElement('span');
            name.className = 'bart-drink-name';
            name.textContent = recipe.title;
            var state = document.createElement('span');
            state.className = 'bart-drink-state';
            state.textContent = availabilityLabel(recipe);
            card.appendChild(thumb); card.appendChild(name); card.appendChild(state);
            card.addEventListener('click', bindDrink(recipe.recipeIndex));
            grid.appendChild(card);
        }
        _listEl.appendChild(grid);
        function bindDrink(recipeIndex) {
            return function() { selectRecipe(recipeIndex); };
        }
    }

    function shakeLabel(shake) {
        switch (shake) {
            case 'light': return '轻摇';
            case 'hard': return '猛摇';
            default: return '直接调制';
        }
    }

    function declaredTechniqueText(declared) {
        if (!declared) return '';
        var parts = [];
        if (declared.aged === true) parts.push('陈化');
        if (declared.ice === true) parts.push('加冰');
        parts.push(shakeLabel(declared.shake));
        return parts.join('·');
    }

    function techniqueMismatch() {
        var declared = _selectedRecipe && _selectedRecipe.technique;
        if (!declared) return false;
        if (_technique.shake !== declared.shake) return true;
        if (_technique.ice !== declared.ice) return true;
        if (_technique.aged !== declared.aged) return true;
        return false;
    }

    function renderStation() {
        if (!_stationEl) return;
        _stationEl.innerHTML = '';
        var recipe = _selectedRecipe;
        if (!recipe) {
            var idle = document.createElement('div');
            idle.className = 'bart-idle';
            idle.textContent = _selectedBook ? '点选一款酒开始调制。' : '先翻开一份酒单。';
            _stationEl.appendChild(idle);
            return;
        }
        var station = document.createElement('div');
        station.className = 'bart-card';

        var head = document.createElement('div');
        head.className = 'bart-card-head';
        var thumb = document.createElement('span');
        thumb.className = 'bart-drink-thumb lg';
        thumb.innerHTML = _host.iconHtml(recipe.output.icon, 'bart-icon');
        var titleBlock = document.createElement('div');
        titleBlock.className = 'bart-card-title';
        var title = document.createElement('b');
        title.textContent = recipe.title;
        var owned = document.createElement('small');
        owned.textContent = '现有 ' + recipe.owned.total + ' 份';
        titleBlock.appendChild(title); titleBlock.appendChild(owned);
        head.appendChild(thumb); head.appendChild(titleBlock);
        station.appendChild(head);

        var declared = recipe.technique || null;
        if (declared) {
            var spec = document.createElement('div');
            spec.className = 'bart-spec';
            spec.textContent = '配方要求：' + declaredTechniqueText(declared)
                + (declared.karmotrine === 'optional' ? '（卡莫特林可选）' : '');
            station.appendChild(spec);
        }

        renderConsole(station, recipe, declared);
        renderRequirementRows(station, recipe);

        var footer = document.createElement('div');
        footer.className = 'bart-card-footer';
        if (recipe.batchEligible) {
            var stepper = document.createElement('div');
            stepper.className = 'bart-count';
            var minus = document.createElement('button');
            minus.type = 'button'; minus.textContent = '−';
            minus.setAttribute('aria-label', '减少一杯');
            minus.disabled = _craftCount <= 1 || _busy || _previewBusy;
            minus.addEventListener('click', function() { setCraftCount(_craftCount - 1); });
            var input = document.createElement('input');
            input.className = 'bart-count-input';
            input.type = 'text'; input.inputMode = 'numeric';
            input.value = String(_craftCount);
            input.setAttribute('aria-label', '调制杯数');
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
            plus.setAttribute('aria-label', '增加一杯');
            plus.disabled = _craftCount >= maxCount() || _busy || _previewBusy;
            plus.addEventListener('click', function() { setCraftCount(_craftCount + 1); });
            stepper.appendChild(minus); stepper.appendChild(input); stepper.appendChild(plus);
            footer.appendChild(stepper);
        }
        var cost = document.createElement('div');
        cost.className = 'bart-cost';
        cost.textContent = costText(recipe);
        footer.appendChild(cost);
        var confirm = document.createElement('button');
        confirm.type = 'button';
        confirm.className = 'bart-confirm';
        confirm.textContent = _busy ? '调制中…' : '调制出品';
        var committable = !!_preview && _preview.canCommit && !_busy && !_previewBusy;
        confirm.disabled = !committable;
        if (!committable) confirm.setAttribute('aria-disabled', 'true');
        confirm.setAttribute('data-audio-cue', 'activate');
        confirm.addEventListener('click', commit);
        footer.appendChild(confirm);
        station.appendChild(footer);
        _stationEl.appendChild(station);
    }

    function renderConsole(station, recipe, declared) {
        if (!declared) return;
        var consoleEl = document.createElement('div');
        consoleEl.className = 'bart-console';

        var shakeRow = document.createElement('div');
        shakeRow.className = 'bart-technique';
        var shakes = ['light', 'hard', 'none'];
        for (var i = 0; i < shakes.length; i++) {
            var value = shakes[i];
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'bart-tech-btn'
                + (_technique.shake === value ? ' active' : '');
            button.textContent = shakeLabel(value);
            button.setAttribute('data-audio-cue', 'activate');
            button.disabled = _busy;
            button.addEventListener('click', bindShake(value));
            shakeRow.appendChild(button);
        }
        consoleEl.appendChild(shakeRow);

        var toggleRow = document.createElement('div');
        toggleRow.className = 'bart-technique toggles';
        toggleRow.appendChild(buildToggle('ice', '加冰'));
        toggleRow.appendChild(buildToggle('aged', '陈化'));
        if (declared.karmotrine === 'optional') {
            toggleRow.appendChild(buildToggle('karmotrine', '卡莫特林'));
        }
        consoleEl.appendChild(toggleRow);

        if (techniqueMismatch()) {
            var warn = document.createElement('div');
            warn.className = 'bart-tech-warn';
            warn.textContent = '调制方式与配方不符';
            consoleEl.appendChild(warn);
        }
        station.appendChild(consoleEl);

        function bindShake(value) {
            return function() {
                if (_busy || _technique.shake === value) return;
                _technique.shake = value;
                _commitFeedback = null;
                renderStation(); requestPreview();
            };
        }
        function buildToggle(field, label) {
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'bart-tech-btn toggle'
                + (_technique[field] === true ? ' active' : '');
            button.textContent = label;
            button.setAttribute('data-audio-cue', 'activate');
            button.setAttribute('aria-pressed', _technique[field] === true ? 'true' : 'false');
            button.disabled = _busy;
            button.addEventListener('click', function() {
                if (_busy) return;
                _technique[field] = _technique[field] !== true;
                _commitFeedback = null;
                renderStation(); requestPreview();
            });
            return button;
        }
    }

    function renderRequirementRows(station, recipe) {
        var body = document.createElement('div');
        body.className = 'bart-reqs';
        if (_preview) {
            var materials = _preview.materials || [];
            for (var m = 0; m < materials.length; m++) {
                var material = materials[m];
                var line = document.createElement('div');
                line.className = 'bart-req ' + (material.enough ? 'met' : 'unmet');
                var iconNode = document.createElement('span');
                iconNode.className = 'bart-req-icon';
                iconNode.innerHTML = _host.iconHtml(material.icon, 'bart-icon-sm');
                var nameNode = document.createElement('span');
                nameNode.className = 'bart-req-name';
                nameNode.textContent = material.displayName
                    + (material.consumed ? '' : '（不消耗）');
                var count = document.createElement('span');
                count.className = 'bart-req-value';
                count.textContent = material.owned + '/' + material.required;
                var mark = document.createElement('span');
                mark.className = 'bart-req-mark ' + (material.enough ? 'ok' : 'no');
                mark.textContent = material.enough ? '✓' : '✗';
                line.appendChild(iconNode); line.appendChild(nameNode);
                line.appendChild(count); line.appendChild(mark);
                body.appendChild(line);
            }
            if (_previewBusy) {
                var recalc = document.createElement('div');
                recalc.className = 'bart-note';
                recalc.textContent = '正在核算…';
                body.appendChild(recalc);
            }
        } else {
            var wait = document.createElement('div');
            wait.className = 'bart-note';
            wait.textContent = _previewBusy ? '正在核算…'
                : (recipe.canCraftOne ? '等待核算结果…' : availabilityLabel(recipe));
            body.appendChild(wait);
        }
        if (_commitFeedback) {
            var feedback = document.createElement('div');
            feedback.className = 'bart-note warn';
            feedback.textContent = _commitFeedback;
            body.appendChild(feedback);
        }
        station.appendChild(body);
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
        if (value === _craftCount) { renderStation(); return; }
        _craftCount = value;
        renderStation(); requestPreview();
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
        var messages = {category_not_found:'未找到调酒分类。', recipe_not_found:'酒单已变化。',
            item_not_found:'未找到该原料或酒品。', level_locked:'角色等级与逆向等级不足。',
            infrastructure_locked:'吧台设备未就绪。',
            material_missing:'所需原料不足。', insufficient_money:'金币不足。',
            insufficient_kpoint:'K 点不足。', inventory_full:'背包空间不足。',
            stale_state:'物品状态已变化，请重新核对。', batch_not_supported:'该酒品只能逐杯调制。',
            technique_mismatch:'调制方式与配方不符，请核对摇法与选项。',
            technique_not_supported:'该配方没有调制方式要求。',
            busy:'吧台正在处理另一份调制。', reconcile_required:'上次提交结果需要重新核对。',
            stale_snapshot:'酒单目录已更新，请重新同步。',
            malformed_response:'回包不完整。', timeout:'调酒响应超时。',
            client_timeout:'调酒响应超时。', disconnected:'连接已断开。'};
        return messages[error] || '调酒操作失败，请重试。';
    }

    function toast(message) { if (_host && _host.toast) _host.toast(message); }
    function cue(name) { if (_host && _host.cue) _host.cue(name); }

    return {
        mount:mount,
        unmount:unmount,
        refresh:refresh,
        isBusy:function() { return _busy || _previewBusy; },
        debugState:function() { return {
            book:_selectedBook, selectedIndex:_selectedIndex,
            craftCount:_craftCount, technique:{
                shake:_technique.shake, ice:_technique.ice,
                aged:_technique.aged, karmotrine:_technique.karmotrine
            },
            busy:_busy, previewBusy:_previewBusy,
            books:_books.map(function(book) { return book.name; })
        }; }
    };
})();
