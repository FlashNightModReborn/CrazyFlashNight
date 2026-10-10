/** 铁枪会 — 远程商业点「工契订单」界面，独立于通用工作台。
 *  世界观：铁枪会是 DLS 工业中游加工商，以自治区时代「旧世遗线」接入
 *  铁枪图腾（远程商业点）接单。行会制组织，科技精密、做派古板——
 *  界面即一份图腾节点下发的「加工工契」文书：暗钢底 + 铜金描边 + 朱印。
 *  左页：订单簿（工契条目，行会编号）；
 *  右页：工契正文（品目图鉴 + 工位/用料核验 + 工酬核算 + 落印执行 + 铁枪印）。
 *  物品简介直接用产物 description（跟随物品数据改动）。
 *  协议走 CraftingRuntime mux，snapshot/preview/commit 语义与烹饪/公社一致。 */
var IronspearPanel = (function() {
    'use strict';
    var _host = null;
    var _el = null, _statusEl = null, _bookEl = null, _docEl = null,
        _veilEl = null, _closeButton = null, _moneyEl = null, _kpointsEl = null;
    var _snapshot = null, _recipes = [], _selectedIndex = -1,
        _selectedRecipe = null, _preview = null, _craftCount = 1;
    var _busy = false, _previewBusy = false, _generation = 0;
    var _commitFeedback = null;
    // 图腾资产根：正式壳从 launcher/web 相对解析；dev harness 深两级需覆写。
    var TOTEM_SRC = (window.CF7_IRONSPEAR_ASSET_ROOT || 'assets/ironspear/') + 'totem.svg';

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
        _el.className = 'isp-panel';

        var header = document.createElement('header');
        header.className = 'isp-header';
        var totem = document.createElement('img');
        totem.className = 'isp-totem';
        totem.src = TOTEM_SRC;
        totem.alt = '铁枪图腾';
        var brand = document.createElement('div');
        brand.className = 'isp-brand';
        brand.innerHTML = '<span class="isp-kicker">铁枪会 · 远程商业点</span>'
            + '<h1>加工订单</h1>'
            + '<span class="isp-sub">图腾节点 · 第一防线 · 旧世遗线接入</span>';
        _statusEl = document.createElement('div');
        _statusEl.className = 'isp-status';
        _statusEl.textContent = '图腾接入中';
        var metrics = document.createElement('div');
        metrics.className = 'isp-metrics';
        _moneyEl = document.createElement('span');
        _moneyEl.className = 'isp-metric';
        _kpointsEl = document.createElement('span');
        _kpointsEl.className = 'isp-metric kpoints';
        metrics.appendChild(_moneyEl); metrics.appendChild(_kpointsEl);
        _closeButton = document.createElement('button');
        _closeButton.type = 'button';
        _closeButton.className = 'isp-close';
        _closeButton.textContent = '×';
        _closeButton.setAttribute('aria-label', '关闭铁枪会订单');
        _closeButton.setAttribute('data-audio-cue', 'back');
        _closeButton.addEventListener('click', function() {
            if (_host && _host.requestClose) _host.requestClose('header');
        });
        header.appendChild(totem); header.appendChild(brand);
        header.appendChild(_statusEl); header.appendChild(metrics);
        header.appendChild(_closeButton);

        var body = document.createElement('div');
        body.className = 'isp-body';
        _bookEl = document.createElement('article');
        _bookEl.className = 'isp-book';
        _docEl = document.createElement('article');
        _docEl.className = 'isp-doc';
        _veilEl = document.createElement('div');
        _veilEl.className = 'isp-veil';
        _docEl.appendChild(_veilEl);
        body.appendChild(_bookEl); body.appendChild(_docEl);
        _el.appendChild(header); _el.appendChild(body);
        renderBook(); renderDoc();
    }

    function refresh() {
        if (_statusEl) {
            _statusEl.textContent = '图腾接入中';
            _statusEl.setAttribute('data-state', 'loading');
        }
        var generation = _generation;
        var callId = _host.request('snapshot', {category:'铁枪会'}, function(response) {
            if (generation !== _generation || !_el) return;
            if (!response || !response.success) {
                setStatus('接入失败', 'error');
                toast(errorMessage(response && response.error));
                renderDoc(); return;
            }
            _snapshot = response;
            applyBalance(response.balance);
            setStatus('图腾在线', 'ready');
            _recipes = response.recipes || [];
            if (_selectedRecipe) {
                var found = findRecipe(_selectedRecipe.recipeIndex);
                if (!found) {
                    _selectedRecipe = null; _selectedIndex = -1; _preview = null;
                } else _selectedRecipe = found;
            }
            renderBook(); renderDoc();
            if (_selectedRecipe) requestPreview();
        });
        if (!callId) {
            setStatus('接入失败', 'error');
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
        renderBook(); renderDoc(); requestPreview();
    }

    function deselect() {
        _selectedIndex = -1; _selectedRecipe = null;
        _preview = null; _commitFeedback = null;
        renderBook(); renderDoc();
    }

    function requestPreview() {
        if (!_selectedRecipe || _busy) return;
        _previewBusy = true; renderDoc();
        var generation = _generation;
        var recipeIndex = _selectedIndex, craftCount = _craftCount;
        _host.request('preview', {category:'铁枪会', recipeIndex:recipeIndex,
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
            renderDoc();
        });
    }

    function commit() {
        if (_busy || _previewBusy || !_preview || !_preview.canCommit
                || !_preview.craftToken || !_selectedRecipe) return;
        _busy = true; _commitFeedback = null; renderDoc();
        var generation = _generation;
        var craftedName = _selectedRecipe.title;
        _host.request('commit', {category:'铁枪会',
            expectedCraftToken:_preview.craftToken}, function(response) {
            if (generation !== _generation || !_el) return;
            _busy = false;
            if (response && response.success) {
                toast('已交付 ' + (response.crafted && response.crafted.displayName
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
            renderDoc();
            requestPreview();
        });
    }

    function mountIcon(hostEl, iconName, cls) {
        var wrap = document.createElement('span');
        wrap.className = 'isp-iconwrap pending';
        wrap.innerHTML = _host.iconHtml(iconName, cls);
        var imgs = wrap.querySelectorAll('img');
        if (!imgs.length) {
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

    // ── 左页：订单簿 ──
    function renderBook() {
        if (!_bookEl) return;
        _bookEl.innerHTML = '';
        var head = document.createElement('div');
        head.className = 'isp-book-head';
        head.innerHTML = '<b>订单簿</b><small>图腾节点下发·工契目录</small>';
        _bookEl.appendChild(head);
        var lead = document.createElement('p');
        lead.className = 'isp-book-lead';
        lead.textContent = '本会可承接以下加工订单，选材列契，逐项核验；'
            + '用料未齐者缓议，不议折扣。';
        _bookEl.appendChild(lead);
        var list = document.createElement('div');
        list.className = 'isp-book-list';
        if (!_recipes.length && _snapshot) {
            var empty = document.createElement('div');
            empty.className = 'isp-empty';
            empty.textContent = '节点暂无可下发订单。';
            list.appendChild(empty);
        }
        for (var i = 0; i < _recipes.length; i++) {
            var recipe = _recipes[i];
            var item = document.createElement('button');
            item.type = 'button';
            item.className = 'isp-item ' + availabilityClass(recipe.availability)
                + (_selectedRecipe && _selectedRecipe.recipeIndex === recipe.recipeIndex
                    ? ' active' : '');
            item.setAttribute('data-audio-cue', 'activate');
            var num = document.createElement('span');
            num.className = 'isp-item-num';
            num.textContent = orderNo(recipe, i);
            var icon = document.createElement('span');
            icon.className = 'isp-item-icon';
            mountIcon(icon, recipe.output.icon, 'isp-icon-xs');
            var name = document.createElement('span');
            name.className = 'isp-item-name';
            name.textContent = recipe.output.displayName || recipe.title;
            var state = document.createElement('span');
            state.className = 'isp-item-state';
            state.textContent = availabilityLabel(recipe);
            item.appendChild(num); item.appendChild(icon);
            item.appendChild(name); item.appendChild(state);
            item.addEventListener('click', bindRecipe(recipe.recipeIndex));
            list.appendChild(item);
        }
        _bookEl.appendChild(list);
        function bindRecipe(recipeIndex) {
            return function() { selectRecipe(recipeIndex); };
        }
    }

    // 行会编号：沿用 recipeId 尾号（工契第 N 号）
    function orderNo(recipe, i) {
        var m = /(\d+)\s*$/.exec(String(recipe.recipeId || ''));
        if (m) return m[1].padStart(3, '0');
        return String(i + 1).padStart(3, '0');
    }

    // ── 右页：加工工契 ──
    function renderDoc() {
        if (!_docEl) return;
        _docEl.innerHTML = '';
        _docEl.appendChild(_veilEl);
        _veilEl.innerHTML = '';
        var pending = !!(_selectedRecipe && _previewBusy && !_preview);
        _veilEl.classList.toggle('on', pending);
        _el.classList.toggle('isp-pending', pending);
        if (pending) {
            var note = document.createElement('div');
            note.className = 'isp-veil-note';
            note.textContent = '正在核价…';
            _veilEl.appendChild(note);
        }

        var paper = document.createElement('div');
        paper.className = 'isp-paper';
        _docEl.appendChild(paper);

        if (!_selectedRecipe) {
            var idle = document.createElement('div');
            idle.className = 'isp-doc-idle';
            idle.innerHTML = '<img class="isp-doc-watermark" src="' + TOTEM_SRC
                + '" alt=""><p>—— 请在订单簿中择契 ——</p>';
            paper.appendChild(idle);
            return;
        }
        renderDocBody(paper);
    }

    function renderDocBody(paper) {
        var recipe = _selectedRecipe;
        var index = _recipes.indexOf(recipe);

        var mark = document.createElement('img');
        mark.className = 'isp-doc-watermark in-doc';
        mark.src = TOTEM_SRC;
        mark.alt = '';
        paper.appendChild(mark);

        var head = document.createElement('header');
        head.className = 'isp-doc-head';
        head.innerHTML = '<b>铁枪会加工工契</b>'
            + '<small>契字第 ' + orderNo(recipe, index) + ' 号 · '
            + escapeHtml(recipe.output.displayName || recipe.title) + '</small>';
        paper.appendChild(head);

        var intro = document.createElement('div');
        intro.className = 'isp-doc-intro';
        var figure = document.createElement('span');
        figure.className = 'isp-doc-figure';
        mountIcon(figure, recipe.output.icon, 'isp-icon-lg');
        var cap = document.createElement('span');
        cap.className = 'isp-doc-figcap';
        cap.textContent = '图鉴：' + recipe.output.displayName;
        figure.appendChild(cap);
        intro.appendChild(figure);
        var desc = document.createElement('p');
        desc.textContent = (typeof recipe.output.description === 'string'
            && recipe.output.description)
            ? recipe.output.description
            : '本品列入铁枪会加工序列，由图腾节点远程核验、委托工位精密承接。';
        intro.appendChild(desc);
        paper.appendChild(intro);

        var listTitle = document.createElement('p');
        listTitle.className = 'isp-doc-list-title';
        listTitle.textContent = '核验项：';
        paper.appendChild(listTitle);
        var list = document.createElement('div');
        list.className = 'isp-doc-list';
        if (_preview) {
            renderDocMaterials(list, _preview);
        } else if (_previewBusy) {
            var loading = document.createElement('p');
            loading.className = 'isp-doc-note';
            loading.textContent = '工酬核价中……';
            list.appendChild(loading);
        } else {
            var wait = document.createElement('p');
            wait.className = 'isp-doc-note';
            wait.textContent = recipe.canCraftOne
                ? '等待核验……' : availabilityLabel(recipe);
            list.appendChild(wait);
        }
        paper.appendChild(list);
        if (_commitFeedback) {
            var feedback = document.createElement('p');
            feedback.className = 'isp-doc-note warn';
            feedback.textContent = _commitFeedback;
            paper.appendChild(feedback);
        }

        var foot = document.createElement('div');
        foot.className = 'isp-doc-foot';
        var sign = document.createElement('div');
        sign.className = 'isp-doc-sign';
        sign.innerHTML = '<b>铁枪会·远程商业点</b><small>旧世遗线·图腾节点核讫</small>';
        foot.appendChild(sign);
        var actions = document.createElement('div');
        actions.className = 'isp-doc-actions';
        if (recipe.batchEligible) {
            actions.appendChild(buildStepper());
        }
        var cost = document.createElement('div');
        cost.className = 'isp-cost';
        cost.textContent = costText(recipe);
        actions.appendChild(cost);
        foot.appendChild(actions);
        // 落印位：契约右下落款处，按钮即"盖印"语义
        var confirm = document.createElement('button');
        confirm.type = 'button';
        confirm.className = 'isp-confirm';
        confirm.textContent = _busy ? '交付中…' : '落印执行';
        var committable = !!_preview && _preview.canCommit && !_busy && !_previewBusy;
        confirm.disabled = !committable;
        if (!committable) confirm.setAttribute('aria-disabled', 'true');
        confirm.setAttribute('data-audio-cue', 'activate');
        confirm.addEventListener('click', commit);
        foot.appendChild(confirm);
        paper.appendChild(foot);
        // 点击=盖章：commit 在途时落朱砂「落印执行」印
        if (_busy) {
            var stamp = document.createElement('div');
            stamp.className = 'isp-stamp';
            stamp.setAttribute('aria-hidden', 'true');
            stamp.textContent = '落印执行';
            paper.appendChild(stamp);
        }
    }

    function buildStepper() {
        var stepper = document.createElement('div');
        stepper.className = 'isp-count';
        var minus = document.createElement('button');
        minus.type = 'button'; minus.textContent = '−';
        minus.setAttribute('aria-label', '减少一件');
        minus.disabled = _craftCount <= 1 || _busy || _previewBusy;
        minus.addEventListener('click', function() { setCraftCount(_craftCount - 1); });
        var input = document.createElement('input');
        input.className = 'isp-count-input';
        input.type = 'text'; input.inputMode = 'numeric';
        input.value = String(_craftCount);
        input.setAttribute('aria-label', '交付数量');
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
        plus.setAttribute('aria-label', '增加一件');
        plus.disabled = _craftCount >= maxCount() || _busy || _previewBusy;
        plus.addEventListener('click', function() { setCraftCount(_craftCount + 1); });
        stepper.appendChild(minus); stepper.appendChild(input); stepper.appendChild(plus);
        return stepper;
    }

    function renderDocMaterials(list, preview) {
        var infra = preview.infrastructure instanceof Array ? preview.infrastructure : [];
        for (var i = 0; i < infra.length; i++) {
            var row = infra[i];
            var line = document.createElement('div');
            line.className = 'isp-req infra ' + (row.met ? 'met' : 'unmet');
            var nameEl = document.createElement('span');
            nameEl.className = 'isp-req-name';
            nameEl.textContent = '工位·' + row.name + (row.appliance ? '·' + row.appliance : '');
            var mark = document.createElement('span');
            mark.className = 'isp-req-mark';
            mark.textContent = row.met ? '核验通过' : '核验未过';
            line.appendChild(nameEl); line.appendChild(mark);
            list.appendChild(line);
        }
        var materials = preview.materials || [];
        for (var m = 0; m < materials.length; m++) {
            var material = materials[m];
            var node = document.createElement('div');
            node.className = 'isp-req ' + (material.enough ? 'met' : 'unmet');
            var iconNode = document.createElement('span');
            iconNode.className = 'isp-req-icon';
            mountIcon(iconNode, material.icon, 'isp-icon-sm');
            var nameNode = document.createElement('span');
            nameNode.className = 'isp-req-name';
            nameNode.textContent = material.displayName
                + (material.consumed ? '' : '（样）')
                + ' ×' + material.required + '（存 ' + material.owned + '）';
            var markNode = document.createElement('span');
            markNode.className = 'isp-req-mark';
            markNode.textContent = material.enough ? '核验通过' : '核验未过';
            node.appendChild(iconNode); node.appendChild(nameNode);
            node.appendChild(markNode);
            list.appendChild(node);
        }
    }

    function availabilityLabel(recipe) {
        switch (recipe.availability) {
            case 'ready': return '可承接';
            case 'infrastructure_locked': return '工位未备';
            case 'level_locked': return '资历未至';
            case 'material_missing': return '用料未齐';
            case 'insufficient_money': return '工酬不足';
            case 'insufficient_kpoint': return 'K点不足';
            case 'inventory_full': return '库房已满';
            default: return '缓议';
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
        if (value === _craftCount) { renderDoc(); return; }
        _craftCount = value;
        renderDoc(); requestPreview();
    }

    function costText(recipe) {
        var money = Number(recipe.baseCost && recipe.baseCost.money || 0);
        var kpoints = Number(recipe.baseCost && recipe.baseCost.kpoints || 0);
        var parts = [];
        if (money > 0) parts.push('工酬 ' + _host.formatNumber(money * _craftCount));
        if (kpoints > 0) parts.push('K点 ' + _host.formatNumber(kpoints * _craftCount));
        return parts.length ? '核价：' + parts.join('　') : '免收工酬';
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
        var messages = {category_not_found:'未找到铁枪会订单分类。', recipe_not_found:'工契已变化。',
            item_not_found:'未找到该用料或成品。', level_locked:'资历与逆向等级不足。',
            infrastructure_locked:'工位未就绪，请先在基地建造。',
            material_missing:'用料不足。', insufficient_money:'金币不足。',
            insufficient_kpoint:'K 点不足。', inventory_full:'背包空间不足。',
            stale_state:'物品状态已变化，请重新核验。', batch_not_supported:'该品目只能逐件交付。',
            busy:'工位正在处理另一项订单。', reconcile_required:'上次交付结果需要重新核对。',
            stale_snapshot:'订单簿已更新，请重新接入。',
            malformed_response:'回包不完整。', timeout:'节点响应超时。',
            client_timeout:'节点响应超时。', disconnected:'连接已断开。'};
        return messages[error] || '订单执行失败，请重试。';
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
            selectedIndex:_selectedIndex,
            craftCount:_craftCount, busy:_busy, previewBusy:_previewBusy,
            recipes:_recipes.length
        }; }
    };
})();
