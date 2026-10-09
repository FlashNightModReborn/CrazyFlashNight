/** 调酒吧台 — 赛博朋克酒保风格界面（VA-11 式自由调配），独立于合成工作台。
 *  左列：酒品名录——按口味/类型/瓶装饮料筛选浏览，卡片载配方规格，
 *        顶部「当前调配」栏实时显示玩家投放组合命中的酒品；
 *  右列：吧台操作区——五种原料槽（固定顺序、含剩余数目与投放计数）、
 *        加冰/陈化开关、中央摇壶（未摇制→轻摇→猛摇→轻摇…）与「重做」「完成」。
 *  配方结构来自 build 派生 bartending-spec.json（web 直读）；
 *  命中后仍走 CraftingRuntime preview/commit，调制方式与材料裁决
 *  由 AS2 逐项比对并冻结进计划——本地匹配只负责呈现与门控按钮。 */
var BartendingPanel = (function() {
    'use strict';
    var _host = null;
    var _el = null, _statusEl = null, _listEl = null, _stationEl = null,
        _closeButton = null, _moneyEl = null, _kpointsEl = null,
        _tabsEl = null, _chipsEl = null, _resultEl = null;
    var _snapshot = null, _spec = null, _specFailed = false,
        _materials = null, _materialsBusy = false;
    var _filter = {tab:'all', value:''};
    var _mix = null;
    var _matched = null, _preview = null;
    var _busy = false, _previewBusy = false, _generation = 0;
    var _commitFeedback = null;
    var SLOT_MAX = 9;

    function mount(shellEl, deps) {
        _host = deps;
        _generation++;
        _snapshot = null; _spec = null; _specFailed = false;
        _materials = null; _materialsBusy = false;
        _filter = {tab:'all', value:''};
        _matched = null; _preview = null;
        _busy = false; _previewBusy = false; _commitFeedback = null;
        resetMix();
        buildDOM();
        if (shellEl) shellEl.appendChild(_el);
        loadSpec();
        refresh();
    }

    function unmount() {
        _generation++;
        if (_el && _el.parentNode) _el.parentNode.removeChild(_el);
        _el = null; _host = null; _snapshot = null; _spec = null; _preview = null;
        _materials = null; _matched = null; _mix = null;
        _busy = false; _previewBusy = false; _materialsBusy = false;
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

        var browser = document.createElement('div');
        browser.className = 'bart-browser';
        _tabsEl = document.createElement('nav');
        _tabsEl.className = 'bart-tabs';
        _tabsEl.setAttribute('aria-label', '名录筛选');
        _chipsEl = document.createElement('div');
        _chipsEl.className = 'bart-chips';
        _resultEl = document.createElement('div');
        _resultEl.className = 'bart-result';
        _listEl = document.createElement('div');
        _listEl.className = 'bart-list';
        browser.appendChild(_tabsEl); browser.appendChild(_chipsEl);
        browser.appendChild(_resultEl); browser.appendChild(_listEl);

        _stationEl = document.createElement('section');
        _stationEl.className = 'bart-station';

        body.appendChild(browser); body.appendChild(_stationEl);
        _el.appendChild(header); _el.appendChild(body);
        renderAll();
    }

    function renderAll() {
        renderTabs(); renderChips(); renderResult(); renderList(); renderStation();
    }

    /* ── 数据装载 ── */

    function slotNames() {
        return _spec && _spec.ingredientSlots ? _spec.ingredientSlots : [];
    }

    function resetMix() {
        _mix = {counts:{}, ice:false, aged:false, shake:'none'};
        var names = slotNames();
        for (var i = 0; i < names.length; i++) _mix.counts[names[i]] = 0;
    }

    function loadSpec() {
        var generation = _generation;
        fetch('modules/bartending-spec.json').then(function(response) {
            if (!response.ok) throw new Error('spec http ' + response.status);
            return response.json();
        }).then(function(spec) {
            if (generation !== _generation || !_el) return;
            if (!spec || spec.version !== 1 || !Array.isArray(spec.recipes)
                    || !Array.isArray(spec.ingredientSlots)) {
                _specFailed = true;
            } else {
                _spec = spec;
                if (!_mix) resetMix();
            }
            renderAll();
            rematch();
        }).catch(function() {
            if (generation !== _generation || !_el) return;
            _specFailed = true;
            renderAll();
        });
    }

    function refresh() {
        if (_statusEl) {
            _statusEl.textContent = '同步中';
            _statusEl.setAttribute('data-state', 'loading');
        }
        loadMaterials();
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
            renderAll();
            rematch();
        });
        if (!callId) {
            setStatus('发送失败', 'error');
            toast('合成通道不可用，请关闭后重试。');
        }
    }

    function loadMaterials() {
        if (_materialsBusy) return;
        _materialsBusy = true;
        var generation = _generation;
        _host.request('materials', {v:1}, function(response) {
            if (generation !== _generation || !_el) return;
            _materialsBusy = false;
            if (response && response.success && Array.isArray(response.materials)) {
                var index = {};
                for (var i = 0; i < response.materials.length; i++) {
                    var row = response.materials[i];
                    index[row.name] = row;
                }
                _materials = index;
            }
            renderStation();
        });
    }

    /* ── 配方匹配（本地投影，裁决仍以 AS2 preview 为准）── */

    function specByIndex(recipeIndex) {
        if (!_spec) return null;
        for (var i = 0; i < _spec.recipes.length; i++) {
            if (Number(_spec.recipes[i].recipeIndex) === Number(recipeIndex)) {
                return _spec.recipes[i];
            }
        }
        return null;
    }

    function snapshotByIndex(recipeIndex) {
        if (!_snapshot || !_snapshot.recipes) return null;
        for (var i = 0; i < _snapshot.recipes.length; i++) {
            if (Number(_snapshot.recipes[i].recipeIndex) === Number(recipeIndex)) {
                return _snapshot.recipes[i];
            }
        }
        return null;
    }

    function mixHasAnyPour() {
        var names = slotNames();
        for (var i = 0; i < names.length; i++) {
            if ((_mix.counts[names[i]] || 0) > 0) return true;
        }
        return false;
    }

    /** 返回 {recipe, technique} 或 null；technique.karmotrine 为实际可选投放。 */
    function matchMix() {
        if (!_spec) return null;
        var slots = slotNames();
        var karmotrineName = '卡莫特林';
        for (var r = 0; r < _spec.recipes.length; r++) {
            var recipe = _spec.recipes[r];
            var need = recipe.ingredients || {};
            var ok = true;
            for (var i = 0; i < slots.length; i++) {
                var name = slots[i];
                if (name === karmotrineName) continue;
                if ((_mix.counts[name] || 0) !== (need[name] || 0)) { ok = false; break; }
            }
            if (!ok) continue;
            var declared = recipe.technique || null;
            if (declared) {
                if (_mix.shake !== declared.shake) continue;
                if (_mix.ice !== declared.ice) continue;
                if (_mix.aged !== declared.aged) continue;
            }
            var authoredK = need[karmotrineName] || 0;
            var kCount = _mix.counts[karmotrineName] || 0;
            var kind = declared ? declared.karmotrine : 'none';
            var sendKarmotrine = false;
            if (kind === 'required') {
                if (kCount !== authoredK) continue;
            } else if (kind === 'optional') {
                if (authoredK !== 0 || kCount > 1) continue;
                sendKarmotrine = kCount === 1;
            } else {
                if (kCount !== 0 || authoredK !== 0) continue;
            }
            return {recipe:recipe,
                technique:declared ? {
                    shake:declared.shake, ice:declared.ice,
                    aged:declared.aged, karmotrine:sendKarmotrine
                } : null};
        }
        return null;
    }

    function rematch() {
        _matched = matchMix();
        _preview = null;
        renderResult(); renderList(); renderStation();
        if (_matched) requestPreview();
    }

    /* ── 请求：preview / commit ── */

    function requestPreview() {
        if (!_matched || _busy) return;
        _previewBusy = true; renderStation();
        var generation = _generation;
        var recipeIndex = _matched.recipe.recipeIndex;
        var techniqueSig = _matched.technique ? JSON.stringify(_matched.technique) : '';
        var payload = {category:'调酒', recipeIndex:recipeIndex, craftCount:1};
        if (_matched.technique) payload.technique = _matched.technique;
        _host.request('preview', payload, function(response) {
            if (generation !== _generation || !_el) return;
            _previewBusy = false;
            if (!_matched || Number(_matched.recipe.recipeIndex) !== Number(recipeIndex)) return;
            var current = _matched.technique ? JSON.stringify(_matched.technique) : '';
            if (current !== techniqueSig) return;
            if (!response || !response.success) {
                _preview = null;
                _commitFeedback = errorMessage(response && response.error);
            } else {
                _preview = response; _commitFeedback = null;
            }
            renderResult(); renderStation();
        });
    }

    function commit() {
        if (_busy || _previewBusy || !_matched || !_preview
                || !_preview.canCommit || !_preview.craftToken) return;
        _busy = true; _commitFeedback = null; renderStation();
        var generation = _generation;
        var craftedName = _matched.recipe.title;
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
                resetMix(); _matched = null;
                refresh(); return;
            }
            cue('rejected');
            toast(errorMessage(response && response.error));
            _commitFeedback = errorMessage(response && response.error);
            _preview = null;
            renderResult(); renderStation();
            if (_matched) requestPreview();
        });
    }

    /* ── 交互 ── */

    function setCount(name, next) {
        var value = Math.floor(Number(next));
        if (isNaN(value) || value < 0) value = 0;
        if (value > SLOT_MAX) value = SLOT_MAX;
        if (_mix.counts[name] === value) { renderStation(); return; }
        _mix.counts[name] = value;
        _commitFeedback = null;
        rematch();
    }

    function setShake() {
        if (_busy) return;
        _mix.shake = _mix.shake === 'light' ? 'hard' : 'light';
        _commitFeedback = null;
        rematch();
    }

    function toggleOption(field) {
        if (_busy) return;
        _mix[field] = _mix[field] !== true;
        _commitFeedback = null;
        rematch();
    }

    function resetAll() {
        if (_busy) return;
        resetMix();
        _matched = null; _preview = null; _commitFeedback = null;
        renderResult(); renderList(); renderStation();
    }

    function loadRecipe(recipeIndex) {
        var recipe = specByIndex(recipeIndex);
        if (!recipe || _busy) return;
        resetMix();
        var need = recipe.ingredients || {};
        for (var name in need) {
            if (Object.prototype.hasOwnProperty.call(need, name)) {
                _mix.counts[name] = need[name];
            }
        }
        if (recipe.technique) {
            _mix.shake = recipe.technique.shake;
            _mix.ice = recipe.technique.ice === true;
            _mix.aged = recipe.technique.aged === true;
        }
        _commitFeedback = null;
        rematch();
    }

    /* ── 渲染：左侧名录 ── */

    var TABS = [
        {id:'all', label:'全部'},
        {id:'flavor', label:'按口味'},
        {id:'style', label:'按类型'},
        {id:'bottled', label:'瓶装饮料'}
    ];

    function renderTabs() {
        if (!_tabsEl) return;
        _tabsEl.innerHTML = '';
        for (var i = 0; i < TABS.length; i++) {
            var tab = TABS[i];
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'bart-tab' + (_filter.tab === tab.id ? ' active' : '');
            button.textContent = tab.label;
            button.setAttribute('data-audio-cue', 'activate');
            button.setAttribute('aria-pressed', _filter.tab === tab.id ? 'true' : 'false');
            button.addEventListener('click', bindTab(tab.id));
            _tabsEl.appendChild(button);
        }
        function bindTab(id) {
            return function() {
                _filter.tab = id;
                _filter.value = '';
                renderTabs(); renderChips(); renderList();
            };
        }
    }

    function renderChips() {
        if (!_chipsEl) return;
        _chipsEl.innerHTML = '';
        var options = _filter.tab === 'flavor' ? (_spec ? _spec.flavors : [])
            : _filter.tab === 'style' ? (_spec ? _spec.styles : []) : null;
        if (!options) { _chipsEl.classList.add('hidden'); return; }
        _chipsEl.classList.remove('hidden');
        for (var i = 0; i < options.length; i++) {
            var value = options[i];
            var chip = document.createElement('button');
            chip.type = 'button';
            chip.className = 'bart-chip' + (_filter.value === value ? ' active' : '');
            chip.textContent = value;
            chip.setAttribute('data-audio-cue', 'activate');
            chip.addEventListener('click', bindChip(value));
            _chipsEl.appendChild(chip);
        }
        function bindChip(value) {
            return function() {
                _filter.value = _filter.value === value ? '' : value;
                renderChips(); renderList();
            };
        }
    }

    function filteredRecipes() {
        if (!_spec) return [];
        var out = [];
        for (var i = 0; i < _spec.recipes.length; i++) {
            var recipe = _spec.recipes[i];
            if (_filter.tab === 'flavor' && _filter.value && recipe.flavor !== _filter.value) continue;
            if (_filter.tab === 'style' && _filter.value && recipe.style !== _filter.value) continue;
            if (_filter.tab === 'bottled' && recipe.bottled !== true) continue;
            out.push(recipe);
        }
        return out;
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

    function shakeLabel(shake) {
        switch (shake) {
            case 'light': return '轻摇';
            case 'hard': return '猛摇';
            default: return '不摇';
        }
    }

    function specLine(recipe) {
        var parts = [];
        var slots = slotNames();
        for (var i = 0; i < slots.length; i++) {
            var count = recipe.ingredients && recipe.ingredients[slots[i]];
            if (count > 0) parts.push(slots[i] + '×' + count);
        }
        if (recipe.technique) {
            if (recipe.technique.aged) parts.push('陈化');
            if (recipe.technique.ice) parts.push('加冰');
            parts.push(shakeLabel(recipe.technique.shake));
            if (recipe.technique.karmotrine === 'optional') parts.push('卡莫特林可选');
        }
        for (var e = 0; e < (recipe.extras || []).length; e++) {
            parts.push('需「' + recipe.extras[e].name + '」');
        }
        return parts.join(' · ');
    }

    function renderResult() {
        if (!_resultEl) return;
        _resultEl.innerHTML = '';
        var head = document.createElement('div');
        head.className = 'bart-result-head';
        head.textContent = '当前调配';
        var body = document.createElement('div');
        body.className = 'bart-result-body';
        if (_matched) {
            var snap = snapshotByIndex(_matched.recipe.recipeIndex);
            var thumb = document.createElement('span');
            thumb.className = 'bart-drink-thumb';
            if (snap) thumb.innerHTML = _host.iconHtml(snap.output.icon, 'bart-icon');
            var info = document.createElement('div');
            info.className = 'bart-result-info';
            var name = document.createElement('b');
            name.textContent = _matched.recipe.title;
            var state = document.createElement('small');
            state.textContent = _previewBusy ? '核算中…'
                : _preview && _preview.canCommit ? '配方成立，可出杯'
                : _preview ? errorMessage(_preview.blockingError)
                : _commitFeedback || '核算中…';
            info.appendChild(name); info.appendChild(state);
            body.appendChild(thumb); body.appendChild(info);
            _resultEl.classList.add('matched');
        } else {
            var hint = document.createElement('div');
            hint.className = 'bart-result-hint';
            hint.textContent = !_spec ? (_specFailed ? '酒单规格缺失，无法调配。' : '载入酒单中…')
                : mixHasAnyPour() ? '该组合不出任何酒——调整原料或手法。'
                : '按配方投放原料，或直接点选左侧酒品。';
            body.appendChild(hint);
            _resultEl.classList.remove('matched');
        }
        _resultEl.appendChild(head); _resultEl.appendChild(body);
    }

    function renderList() {
        if (!_listEl) return;
        _listEl.innerHTML = '';
        var grid = document.createElement('div');
        grid.className = 'bart-drink-grid';
        var recipes = filteredRecipes();
        if (!_spec) {
            var empty = document.createElement('div');
            empty.className = 'bart-empty';
            empty.textContent = _specFailed ? '酒单规格缺失。' : '载入中…';
            grid.appendChild(empty);
        } else if (!recipes.length) {
            var none = document.createElement('div');
            none.className = 'bart-empty';
            none.textContent = '该分类下没有酒品。';
            grid.appendChild(none);
        }
        for (var i = 0; i < recipes.length; i++) {
            var recipe = recipes[i];
            var snap = snapshotByIndex(recipe.recipeIndex);
            var card = document.createElement('button');
            card.type = 'button';
            var classes = 'bart-drink'
                + (snap && snap.availability === 'ready' ? ' is-ready' : ' is-blocked')
                + (_matched && _matched.recipe.recipeIndex === recipe.recipeIndex
                    ? ' matched' : '');
            card.className = classes;
            card.setAttribute('data-audio-cue', 'activate');
            var thumb = document.createElement('span');
            thumb.className = 'bart-drink-thumb';
            if (snap) thumb.innerHTML = _host.iconHtml(snap.output.icon, 'bart-icon');
            var name = document.createElement('span');
            name.className = 'bart-drink-name';
            name.textContent = recipe.title;
            var spec = document.createElement('span');
            spec.className = 'bart-drink-spec';
            spec.textContent = specLine(recipe);
            var state = document.createElement('span');
            state.className = 'bart-drink-state';
            state.textContent = snap ? availabilityLabel(snap) : '同步中';
            card.appendChild(thumb); card.appendChild(name);
            card.appendChild(spec); card.appendChild(state);
            card.addEventListener('click', bindDrink(recipe.recipeIndex));
            grid.appendChild(card);
        }
        _listEl.appendChild(grid);
        function bindDrink(recipeIndex) {
            return function() { loadRecipe(recipeIndex); };
        }
    }

    /* ── 渲染：右侧吧台 ── */

    function materialMeta(name) {
        return _materials && _materials[name] ? _materials[name] : null;
    }

    function renderStation() {
        if (!_stationEl) return;
        _stationEl.innerHTML = '';
        var board = document.createElement('div');
        board.className = 'bart-board';

        var slotsRow = document.createElement('div');
        slotsRow.className = 'bart-slots';
        var slots = slotNames();
        for (var i = 0; i < slots.length; i++) {
            slotsRow.appendChild(renderSlot(slots[i]));
        }
        board.appendChild(slotsRow);

        var console_ = document.createElement('div');
        console_.className = 'bart-console';

        var options = document.createElement('div');
        options.className = 'bart-options';
        options.appendChild(optionButton('ice', '加冰'));
        options.appendChild(optionButton('aged', '陈化'));
        console_.appendChild(options);

        var shaker = document.createElement('button');
        shaker.type = 'button';
        shaker.className = 'bart-shaker state-' + _mix.shake;
        shaker.disabled = _busy;
        shaker.setAttribute('data-audio-cue', 'activate');
        var shakeState = document.createElement('span');
        shakeState.className = 'bart-shaker-state';
        shakeState.textContent = _mix.shake === 'none' ? '未摇制'
            : _mix.shake === 'light' ? '轻摇' : '猛摇';
        var shakeHint = document.createElement('span');
        shakeHint.className = 'bart-shaker-hint';
        shakeHint.textContent = '点击切换';
        shaker.appendChild(shakeState); shaker.appendChild(shakeHint);
        shaker.addEventListener('click', setShake);
        console_.appendChild(shaker);

        var redo = document.createElement('button');
        redo.type = 'button';
        redo.className = 'bart-tech-btn redo';
        redo.textContent = '重做';
        redo.disabled = _busy;
        redo.setAttribute('data-audio-cue', 'activate');
        redo.addEventListener('click', resetAll);
        console_.appendChild(redo);

        board.appendChild(console_);

        var footer = document.createElement('div');
        footer.className = 'bart-card-footer';
        var note = document.createElement('div');
        note.className = 'bart-foot-note';
        note.textContent = footerNote();
        footer.appendChild(note);
        var confirm = document.createElement('button');
        confirm.type = 'button';
        confirm.className = 'bart-confirm';
        confirm.textContent = _busy ? '调制中…' : '完成';
        var committable = !!_preview && _preview.canCommit && !_busy && !_previewBusy;
        confirm.disabled = !committable;
        if (!committable) confirm.setAttribute('aria-disabled', 'true');
        confirm.setAttribute('data-audio-cue', 'activate');
        confirm.addEventListener('click', commit);
        footer.appendChild(confirm);
        board.appendChild(footer);

        _stationEl.appendChild(board);
    }

    function footerNote() {
        if (!_spec) return _specFailed ? '酒单规格缺失。' : '载入中…';
        if (!_matched) return mixHasAnyPour()
            ? '配方不成立——原料与手法须与某款酒完全一致。' : '投放原料开始调配。';
        if (_previewBusy) return '正在核算…';
        if (_commitFeedback) return _commitFeedback;
        if (_preview && _preview.canCommit) return '将出品「' + _matched.recipe.title + '」。';
        if (_preview) return errorMessage(_preview.blockingError);
        return '正在核算…';
    }

    function renderSlot(name) {
        var meta = materialMeta(name);
        var count = _mix.counts[name] || 0;
        var owned = meta ? Number(meta.owned) : null;
        var slot = document.createElement('div');
        slot.className = 'bart-slot' + (count > 0 ? ' filled' : '')
            + (owned !== null && count > owned ? ' over' : '');

        var icon = document.createElement('span');
        icon.className = 'bart-slot-icon';
        if (meta && meta.icon) icon.innerHTML = _host.iconHtml(meta.icon, 'bart-icon-sm');
        var label = document.createElement('span');
        label.className = 'bart-slot-name';
        label.textContent = name;
        var stock = document.createElement('span');
        stock.className = 'bart-slot-stock';
        stock.textContent = owned === null ? '…' : '剩余 ' + owned;
        slot.appendChild(icon); slot.appendChild(label); slot.appendChild(stock);

        var stepper = document.createElement('div');
        stepper.className = 'bart-slot-count';
        var minus = document.createElement('button');
        minus.type = 'button'; minus.textContent = '−';
        minus.setAttribute('aria-label', '减少一份' + name);
        minus.disabled = _busy || count <= 0;
        minus.addEventListener('click', function() { setCount(name, count - 1); });
        var value = document.createElement('span');
        value.className = 'bart-slot-value';
        value.textContent = String(count);
        var plus = document.createElement('button');
        plus.type = 'button'; plus.textContent = '+';
        plus.setAttribute('aria-label', '增加一份' + name);
        plus.disabled = _busy || count >= SLOT_MAX;
        plus.addEventListener('click', function() { setCount(name, count + 1); });
        stepper.appendChild(minus); stepper.appendChild(value); stepper.appendChild(plus);
        slot.appendChild(stepper);
        return slot;
    }

    function optionButton(field, label) {
        var button = document.createElement('button');
        button.type = 'button';
        button.className = 'bart-tech-btn toggle'
            + (_mix[field] === true ? ' active' : '');
        button.textContent = label;
        button.setAttribute('data-audio-cue', 'activate');
        button.setAttribute('aria-pressed', _mix[field] === true ? 'true' : 'false');
        button.disabled = _busy;
        button.addEventListener('click', function() { toggleOption(field); });
        return button;
    }

    /* ── 杂项 ── */

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
            filter:{tab:_filter.tab, value:_filter.value},
            mix:_mix ? {counts:_mix.counts, ice:_mix.ice, aged:_mix.aged,
                shake:_mix.shake} : null,
            matched:_matched ? _matched.recipe.recipeIndex : null,
            specLoaded:!!_spec, specFailed:_specFailed,
            materialsLoaded:!!_materials,
            busy:_busy, previewBusy:_previewBusy
        }; }
    };
})();
