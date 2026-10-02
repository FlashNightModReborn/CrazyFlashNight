/** 化学生产 — 蓝图风格合成界面，独立于通用工作台。
 *  铺底深蓝 + 白色虚线方格（蓝图底纹）。左区两列合成目录；
 *  选中后右区蓝图展开：所需材料按次序竖排在目录右侧，先横后斜的
 *  亮白线汇聚到右侧大图标的合成结果（与目录同款图标放大）；
 *  右下角放确认合成。所有图标在 img load 完成前不显示。
 *  协议走 CraftingRuntime mux，snapshot/preview/commit 语义与烹饪一致。 */
var ChemistryPanel = (function() {
    'use strict';
    var _host = null;
    var _el = null, _statusEl = null, _listEl = null, _blueprintEl = null,
        _wiresEl = null, _matsEl = null, _resultEl = null, _footEl = null,
        _veilEl = null, _closeButton = null, _moneyEl = null, _kpointsEl = null;
    var _snapshot = null, _recipes = [], _selectedIndex = -1,
        _selectedRecipe = null, _preview = null, _craftCount = 1;
    var _busy = false, _previewBusy = false, _generation = 0;
    var _commitFeedback = null;

    function mount(shellEl, deps) {
        _host = deps;
        _generation++;
        _snapshot = null; _recipes = []; _selectedIndex = -1;
        _selectedRecipe = null; _preview = null;
        _craftCount = 1; _busy = false; _previewBusy = false; _commitFeedback = null;
        buildDOM();
        if (shellEl) shellEl.appendChild(_el);
        refresh();
    }

    function unmount() {
        _generation++;
        if (_el && _el.parentNode) _el.parentNode.removeChild(_el);
        _el = null; _host = null; _snapshot = null; _preview = null;
        _selectedIndex = -1; _selectedRecipe = null;
        _busy = false; _previewBusy = false;
    }

    function buildDOM() {
        _el = document.createElement('div');
        _el.className = 'chem-panel';

        var header = document.createElement('header');
        header.className = 'chem-header';
        var brand = document.createElement('div');
        brand.className = 'chem-brand';
        brand.innerHTML = '<span class="chem-kicker">基地工坊</span><h1>化学生产</h1>';
        _statusEl = document.createElement('div');
        _statusEl.className = 'chem-status';
        _statusEl.textContent = '同步中';
        var metrics = document.createElement('div');
        metrics.className = 'chem-metrics';
        _moneyEl = document.createElement('span');
        _moneyEl.className = 'chem-metric';
        _kpointsEl = document.createElement('span');
        _kpointsEl.className = 'chem-metric kpoints';
        metrics.appendChild(_moneyEl); metrics.appendChild(_kpointsEl);
        _closeButton = document.createElement('button');
        _closeButton.type = 'button';
        _closeButton.className = 'chem-close';
        _closeButton.textContent = '×';
        _closeButton.setAttribute('aria-label', '关闭化学生产');
        _closeButton.setAttribute('data-audio-cue', 'back');
        _closeButton.addEventListener('click', function() {
            if (_host && _host.requestClose) _host.requestClose('header');
        });
        header.appendChild(brand); header.appendChild(_statusEl);
        header.appendChild(metrics); header.appendChild(_closeButton);

        var body = document.createElement('div');
        body.className = 'chem-body';
        _listEl = document.createElement('div');
        _listEl.className = 'chem-list';
        _listEl.setAttribute('aria-label', '合成目录');

        _blueprintEl = document.createElement('div');
        _blueprintEl.className = 'chem-blueprint';
        _wiresEl = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        _wiresEl.setAttribute('class', 'chem-wires');
        _wiresEl.setAttribute('aria-hidden', 'true');
        _matsEl = document.createElement('div');
        _matsEl.className = 'chem-materials';
        _resultEl = document.createElement('div');
        _resultEl.className = 'chem-result';
        _footEl = document.createElement('div');
        _footEl.className = 'chem-foot';
        _veilEl = document.createElement('div');
        _veilEl.className = 'chem-veil';
        _blueprintEl.appendChild(_wiresEl); _blueprintEl.appendChild(_matsEl);
        _blueprintEl.appendChild(_resultEl); _blueprintEl.appendChild(_footEl);
        _blueprintEl.appendChild(_veilEl);

        body.appendChild(_listEl); body.appendChild(_blueprintEl);
        _el.appendChild(header); _el.appendChild(body);
        renderList(); renderBlueprint();
    }

    function refresh() {
        if (_statusEl) {
            _statusEl.textContent = '同步中';
            _statusEl.setAttribute('data-state', 'loading');
        }
        var generation = _generation;
        var callId = _host.request('snapshot', {category:'化学生产'}, function(response) {
            if (generation !== _generation || !_el) return;
            if (!response || !response.success) {
                setStatus('读取失败', 'error');
                toast(errorMessage(response && response.error));
                renderBlueprint(); return;
            }
            _snapshot = response;
            applyBalance(response.balance);
            setStatus(response.note || '就绪', 'ready');
            _recipes = response.recipes || [];
            if (_selectedRecipe) {
                var found = findRecipe(_selectedRecipe.recipeIndex);
                if (!found) {
                    _selectedRecipe = null; _selectedIndex = -1; _preview = null;
                } else _selectedRecipe = found;
            }
            renderList(); renderBlueprint();
            if (_selectedRecipe) requestPreview();
        });
        if (!callId) {
            setStatus('发送失败', 'error');
            toast('合成通道不可用，请关闭后重试。');
        }
    }

    function findRecipe(recipeIndex) {
        for (var i = 0; i < _recipes.length; i++) {
            if (Number(_recipes[i].recipeIndex) === Number(recipeIndex)) {
                return _recipes[i];
            }
        }
        return null;
    }

    function selectRecipe(recipeIndex) {
        var recipe = findRecipe(recipeIndex);
        if (!recipe) return;
        if (_selectedRecipe && _selectedRecipe.recipeIndex === recipe.recipeIndex) {
            deselect(); return;
        }
        _selectedIndex = Number(recipeIndex);
        _selectedRecipe = recipe;
        _craftCount = 1; _preview = null; _commitFeedback = null;
        renderList(); renderBlueprint(); requestPreview();
    }

    function deselect() {
        _selectedIndex = -1; _selectedRecipe = null;
        _preview = null; _commitFeedback = null;
        renderList(); renderBlueprint();
    }

    function requestPreview() {
        if (!_selectedRecipe || _busy) return;
        _previewBusy = true; renderBlueprint();
        var generation = _generation;
        var recipeIndex = _selectedIndex, craftCount = _craftCount;
        _host.request('preview', {category:'化学生产', recipeIndex:recipeIndex,
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
            renderBlueprint();
        });
    }

    function commit() {
        if (_busy || _previewBusy || !_preview || !_preview.canCommit
                || !_preview.craftToken || !_selectedRecipe) return;
        _busy = true; _commitFeedback = null; renderBlueprint();
        var generation = _generation;
        var craftedName = _selectedRecipe.title;
        _host.request('commit', {category:'化学生产',
            expectedCraftToken:_preview.craftToken}, function(response) {
            if (generation !== _generation || !_el) return;
            _busy = false;
            if (response && response.success) {
                toast('已合成 ' + (response.crafted && response.crafted.displayName
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
            renderBlueprint();
            requestPreview();
        });
    }

    // ── 图标：img load 完成前隐藏，失败退占位框 ──
    function mountIcon(hostEl, iconName, cls) {
        var wrap = document.createElement('span');
        wrap.className = 'chem-iconwrap pending';
        wrap.innerHTML = _host.iconHtml(iconName, cls);
        var imgs = wrap.querySelectorAll('img');
        if (!imgs.length) {
            // 无图占位：直接亮出虚线占位框
            wrap.classList.remove('pending');
            wrap.classList.add('empty');
        }
        var pending = imgs.length, revealed = false;
        function done() {
            if (revealed) return;
            revealed = true;
            wrap.classList.remove('pending');
            wrap.classList.add('loaded');
        }
        for (var i = 0; i < imgs.length; i++) {
            var img = imgs[i];
            if (img.complete && img.naturalWidth > 0) {
                if (--pending === 0) done();
            } else {
                img.addEventListener('load', function() {
                    if (--pending === 0) done();
                });
                img.addEventListener('error', function() {
                    if (--pending === 0) done();
                });
            }
        }
        if (imgs.length && pending === 0) done();
        hostEl.appendChild(wrap);
        return wrap;
    }

    // ── 左：两列合成目录 ──
    function renderList() {
        if (!_listEl) return;
        _listEl.innerHTML = '';
        if (!_recipes.length && _snapshot) {
            var empty = document.createElement('div');
            empty.className = 'chem-empty';
            empty.textContent = '这个分类还没有可合成的配方。';
            _listEl.appendChild(empty);
        }
        for (var i = 0; i < _recipes.length; i++) {
            var recipe = _recipes[i];
            var cell = document.createElement('button');
            cell.type = 'button';
            cell.className = 'chem-cell ' + availabilityClass(recipe.availability)
                + (_selectedRecipe && _selectedRecipe.recipeIndex === recipe.recipeIndex
                    ? ' active' : '');
            cell.setAttribute('data-audio-cue', 'activate');
            var icon = document.createElement('span');
            icon.className = 'chem-cell-icon';
            mountIcon(icon, recipe.output.icon, 'chem-icon');
            var name = document.createElement('span');
            name.className = 'chem-cell-name';
            name.textContent = recipe.title;
            var state = document.createElement('span');
            state.className = 'chem-cell-state';
            state.textContent = availabilityLabel(recipe);
            cell.appendChild(icon); cell.appendChild(name); cell.appendChild(state);
            cell.addEventListener('click', bindRecipe(recipe.recipeIndex));
            _listEl.appendChild(cell);
        }
        function bindRecipe(recipeIndex) {
            return function() { selectRecipe(recipeIndex); };
        }
    }

    // ── 右：蓝图（材料列 + 汇聚线 + 结果大图 + 确认） ──
    function renderBlueprint() {
        if (!_blueprintEl) return;
        _matsEl.innerHTML = ''; _resultEl.innerHTML = '';
        _footEl.innerHTML = ''; _veilEl.innerHTML = '';
        _wiresEl.innerHTML = '';
        _veilEl.classList.toggle('on', !!(_selectedRecipe && _previewBusy && !_preview));
        _el.classList.toggle('chem-pending', !!(_selectedRecipe && _previewBusy && !_preview));

        if (!_selectedRecipe) return;

        if (_preview) {
            renderResult();
            renderMaterials(_preview);
            layoutArc();
            renderFoot();
            // 结果图标有入场缩放，等动画落地再量连线端点。
            var generation = _generation;
            setTimeout(function() {
                if (generation === _generation && _el) drawWires();
            }, 320);
        } else if (_previewBusy) {
            var note = document.createElement('div');
            note.className = 'chem-veil-note';
            note.textContent = '正在核算…';
            _veilEl.appendChild(note);
        } else {
            var idle = document.createElement('div');
            idle.className = 'chem-blueprint-note';
            idle.textContent = _selectedRecipe.canCraftOne
                ? '等待核算结果…' : availabilityLabel(_selectedRecipe);
            _matsEl.appendChild(idle);
        }
        if (_commitFeedback && !_previewBusy) {
            var feedback = document.createElement('div');
            feedback.className = 'chem-blueprint-note warn';
            feedback.textContent = _commitFeedback;
            _matsEl.appendChild(feedback);
        }
    }

    function renderMaterials(preview) {
        var materials = preview.materials || [];
        // 分组：药剂/成品(storageKind drug|bag) 与 材料(material_collection) 分弧段，
        // 情报类并入材料组。
        var sorted = materials.slice().sort(function(a, b) {
            return matGroup(a) - matGroup(b);
        });
        for (var m = 0; m < sorted.length; m++) {
            var material = sorted[m];
            var node = document.createElement('div');
            node.className = 'chem-mat ' + (material.enough ? 'met' : 'unmet');
            node.setAttribute('data-group', String(matGroup(material)));
            node.setAttribute('data-arc', '1');
            var iconNode = document.createElement('span');
            iconNode.className = 'chem-mat-icon';
            mountIcon(iconNode, material.icon, 'chem-icon-sm');
            var nameNode = document.createElement('span');
            nameNode.className = 'chem-mat-name';
            nameNode.textContent = material.displayName
                + (material.consumed ? '' : '（不消耗）');
            var count = document.createElement('span');
            count.className = 'chem-mat-count';
            count.textContent = material.owned + '/' + material.required;
            var markNode = document.createElement('span');
            markNode.className = 'chem-mat-mark ' + (material.enough ? 'ok' : 'no');
            markNode.textContent = material.enough ? '✓' : '✗';
            node.appendChild(iconNode); node.appendChild(nameNode);
            node.appendChild(count); node.appendChild(markNode);
            _matsEl.appendChild(node);
        }
        // 基建条件排在弧的最下段（group 2）。
        var infra = preview.infrastructure instanceof Array ? preview.infrastructure : [];
        for (var i = 0; i < infra.length; i++) {
            var row = infra[i];
            var line = document.createElement('div');
            line.className = 'chem-mat infra ' + (row.met ? 'met' : 'unmet');
            line.setAttribute('data-group', '2');
            line.setAttribute('data-arc', '1');
            var nameEl = document.createElement('span');
            nameEl.className = 'chem-mat-name';
            nameEl.textContent = row.name + (row.appliance ? '·' + row.appliance : '');
            var mark = document.createElement('span');
            mark.className = 'chem-mat-mark ' + (row.met ? 'ok' : 'no');
            mark.textContent = row.met ? '✓' : '✗';
            line.appendChild(nameEl); line.appendChild(mark);
            _matsEl.appendChild(line);
        }
    }

    // 0=药剂/成品，1=材料（含情报类并入）。storageKind 由 preview 权威投影。
    function matGroup(material) {
        var kind = material && material.storageKind;
        return (kind === 'drug' || kind === 'bag') ? 0 : 1;
    }

    // 环绕布局：材料行右缘落在以结果图标为圆心的弧上，组间留角距。
    function layoutArc() {
        var rows = _matsEl.querySelectorAll('.chem-mat[data-arc]');
        var figure = _resultEl.querySelector('.chem-result-figure');
        if (!rows.length || !figure) return;
        var base = _blueprintEl.getBoundingClientRect();
        var scale = _blueprintEl.offsetWidth
            ? base.width / _blueprintEl.offsetWidth : 1;
        if (!isFinite(scale) || scale <= 0) scale = 1;
        var target = figure.getBoundingClientRect();
        var cx = (target.left + target.width / 2 - base.left) / scale;
        var cy = (target.top + target.height / 2 - base.top) / scale;
        // 半径受限于左边距与材料行宽（行向左展开）
        var rowW = rows[0].offsetWidth || 190;
        var R = Math.max(150, Math.min(300, cx - rowW - 40));
        var step = 24, groupGap = 16;
        var n = rows.length, groups = 0, lastGroup = null;
        for (var g = 0; g < n; g++) {
            var grp = rows[g].getAttribute('data-group');
            if (grp !== lastGroup) { if (lastGroup !== null) groups++; lastGroup = grp; }
        }
        var total = (n - 1) * step + groups * groupGap;
        var maxArc = 120;
        if (total > maxArc) {
            // 行太多时压缩角距，保持不过顶/底
            var shrink = (maxArc - groups * groupGap) / Math.max(1, (n - 1));
            step = Math.max(10, shrink);
            total = (n - 1) * step + groups * groupGap;
        }
        var theta = total / 2; // 首行在最上（θ>0 向上）
        lastGroup = null;
        for (var i = 0; i < n; i++) {
            var row = rows[i];
            var grp2 = row.getAttribute('data-group');
            if (lastGroup !== null && grp2 !== lastGroup) theta -= groupGap;
            lastGroup = grp2;
            var rad = theta * Math.PI / 180;
            var rightX = cx - R * Math.cos(rad);
            var midY = cy - R * Math.sin(rad);
            row.style.left = (rightX - rowW) + 'px';
            row.style.top = (midY - row.offsetHeight / 2) + 'px';
            theta -= step;
        }
    }

    function renderResult() {
        var recipe = _selectedRecipe;
        var figure = document.createElement('div');
        figure.className = 'chem-result-figure';
        mountIcon(figure, recipe.output.icon, 'chem-icon-lg');
        _resultEl.appendChild(figure);
        var name = document.createElement('div');
        name.className = 'chem-result-name';
        name.textContent = recipe.title;
        _resultEl.appendChild(name);
        var owned = document.createElement('div');
        owned.className = 'chem-result-owned';
        owned.textContent = '现有 ' + recipe.owned.total + ' 份';
        _resultEl.appendChild(owned);
    }

    function renderFoot() {
        var recipe = _selectedRecipe;
        if (recipe.batchEligible) {
            var stepper = document.createElement('div');
            stepper.className = 'chem-count';
            var minus = document.createElement('button');
            minus.type = 'button'; minus.textContent = '−';
            minus.setAttribute('aria-label', '减少一份');
            minus.disabled = _craftCount <= 1 || _busy || _previewBusy;
            minus.addEventListener('click', function() { setCraftCount(_craftCount - 1); });
            var input = document.createElement('input');
            input.className = 'chem-count-input';
            input.type = 'text'; input.inputMode = 'numeric';
            input.value = String(_craftCount);
            input.setAttribute('aria-label', '合成份数');
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
            _footEl.appendChild(stepper);
        }
        var cost = document.createElement('div');
        cost.className = 'chem-cost';
        cost.textContent = costText(recipe);
        _footEl.appendChild(cost);
        var confirm = document.createElement('button');
        confirm.type = 'button';
        confirm.className = 'chem-confirm';
        confirm.textContent = _busy ? '合成中…' : '确认合成';
        var committable = !!_preview && _preview.canCommit && !_busy && !_previewBusy;
        confirm.disabled = !committable;
        if (!committable) confirm.setAttribute('aria-disabled', 'true');
        confirm.setAttribute('data-audio-cue', 'activate');
        confirm.addEventListener('click', commit);
        _footEl.appendChild(confirm);
    }

    // 汇聚线：材料行右缘 → 水平 → 斜向 → 结果图标左缘中点
    function drawWires() {
        var rows = _matsEl.querySelectorAll('.chem-mat[data-arc]');
        var figure = _resultEl.querySelector('.chem-result-figure');
        if (!rows.length || !figure) return;
        var base = _blueprintEl.getBoundingClientRect();
        // PanelScale 会把 rect 放大成屏幕像素；viewBox 是布局像素，必须归一化。
        var scale = _blueprintEl.offsetWidth
            ? base.width / _blueprintEl.offsetWidth : 1;
        if (!isFinite(scale) || scale <= 0) scale = 1;
        function lx(px) { return (px - base.left) / scale; }
        function ly(py) { return (py - base.top) / scale; }
        var target = figure.getBoundingClientRect();
        var tx = lx(target.left) - 6;
        var ty = ly(target.top + target.height / 2);
        var w = _blueprintEl.clientWidth, h = _blueprintEl.clientHeight;
        _wiresEl.setAttribute('viewBox', '0 0 ' + w + ' ' + h);
        _wiresEl.setAttribute('width', w); _wiresEl.setAttribute('height', h);
        var ns = 'http://www.w3.org/2000/svg';
        for (var i = 0; i < rows.length; i++) {
            var rect = rows[i].getBoundingClientRect();
            var sx = lx(rect.right);
            var sy = ly(rect.top + rect.height / 2);
            var elbowX = sx + 26;
            var path = document.createElementNS(ns, 'path');
            path.setAttribute('d',
                'M ' + sx + ' ' + sy + ' H ' + elbowX + ' L ' + tx + ' ' + ty);
            path.setAttribute('class', 'chem-wire'
                + (rows[i].classList.contains('unmet') ? ' dim' : ''));
            _wiresEl.appendChild(path);
        }
    }

    function availabilityLabel(recipe) {
        switch (recipe.availability) {
            case 'ready': return '可合成';
            case 'infrastructure_locked': return '缺设备';
            case 'level_locked': return '等级不足';
            case 'material_missing': return '缺材料';
            case 'insufficient_money': return '金币不足';
            case 'insufficient_kpoint': return 'K点不足';
            case 'inventory_full': return '栏位不足';
            default: return '暂不可合成';
        }
    }

    function availabilityClass(availability) {
        return availability === 'ready' ? 'is-ready' : 'is-blocked';
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
        if (value === _craftCount) { renderBlueprint(); return; }
        _craftCount = value;
        renderBlueprint(); requestPreview();
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
        var messages = {category_not_found:'未找到化学生产分类。', recipe_not_found:'配方已变化。',
            item_not_found:'未找到该材料或产物。', level_locked:'角色等级与逆向等级不足。',
            infrastructure_locked:'设备未就绪，需要先在基地建造。',
            material_missing:'所需材料不足。', insufficient_money:'金币不足。',
            insufficient_kpoint:'K 点不足。', inventory_full:'背包空间不足。',
            stale_state:'物品状态已变化，请重新核对。', batch_not_supported:'该产物只能逐份合成。',
            busy:'工坊正在处理另一项合成。', reconcile_required:'上次提交结果需要重新核对。',
            stale_snapshot:'配方目录已更新，请重新同步。',
            malformed_response:'回包不完整。', timeout:'合成响应超时。',
            client_timeout:'合成响应超时。', disconnected:'连接已断开。'};
        return messages[error] || '合成操作失败，请重试。';
    }

    function toast(message) { if (_host && _host.toast) _host.toast(message); }
    function cue(name) { if (_host && _host.cue) _host.cue(name); }

    return {
        mount:mount,
        unmount:unmount,
        refresh:refresh,
        isBusy:function() { return _busy || _previewBusy; },
        debugState:function() { return {
            selectedIndex:_selectedIndex,
            craftCount:_craftCount, busy:_busy, previewBusy:_previewBusy,
            recipes:_recipes.length
        }; }
    };
})();
