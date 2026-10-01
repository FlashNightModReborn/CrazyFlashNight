/** 公社防具 — 陈旧工厂档案风格合成界面，独立于通用工作台。
 *  左页：会议纪要（"经蓉都公社各工作组研究决定…"），点选条目画红圈圈阅；
 *  右页：生产指标档案（红头标题 + 图标环绕简介 + 官话 + 物资调拨清单
 *  审计通过/未通过 + 此致敬礼 + 生产大队红圈印章），内容溢出滚动。
 *  物品简介直接用产物 description（跟随物品数据改动）。
 *  协议走 CraftingRuntime mux，snapshot/preview/commit 语义与烹饪一致。 */
var CommunePanel = (function() {
    'use strict';
    var _host = null;
    var _el = null, _statusEl = null, _minutesEl = null, _docEl = null,
        _veilEl = null, _closeButton = null, _moneyEl = null, _kpointsEl = null;
    var _snapshot = null, _recipes = [], _selectedIndex = -1,
        _selectedRecipe = null, _preview = null, _craftCount = 1;
    var _busy = false, _previewBusy = false, _generation = 0;
    var _commitFeedback = null;
    var NUMERALS = ['一','二','三','四','五','六','七','八','九','十',
        '十一','十二','十三','十四','十五','十六','十七','十八','十九','二十'];

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
        _el.className = 'comm-panel';

        var header = document.createElement('header');
        header.className = 'comm-header';
        var brand = document.createElement('div');
        brand.className = 'comm-brand';
        brand.innerHTML = '<span class="comm-kicker">蓉都公社生产大队</span><h1>公社防具</h1>';
        _statusEl = document.createElement('div');
        _statusEl.className = 'comm-status';
        _statusEl.textContent = '同步中';
        var metrics = document.createElement('div');
        metrics.className = 'comm-metrics';
        _moneyEl = document.createElement('span');
        _moneyEl.className = 'comm-metric';
        _kpointsEl = document.createElement('span');
        _kpointsEl.className = 'comm-metric kpoints';
        metrics.appendChild(_moneyEl); metrics.appendChild(_kpointsEl);
        _closeButton = document.createElement('button');
        _closeButton.type = 'button';
        _closeButton.className = 'comm-close';
        _closeButton.textContent = '×';
        _closeButton.setAttribute('aria-label', '关闭公社防具');
        _closeButton.setAttribute('data-audio-cue', 'back');
        _closeButton.addEventListener('click', function() {
            if (_host && _host.requestClose) _host.requestClose('header');
        });
        header.appendChild(brand); header.appendChild(_statusEl);
        header.appendChild(metrics); header.appendChild(_closeButton);

        var body = document.createElement('div');
        body.className = 'comm-body';
        _minutesEl = document.createElement('article');
        _minutesEl.className = 'comm-minutes';
        _docEl = document.createElement('article');
        _docEl.className = 'comm-doc';
        _veilEl = document.createElement('div');
        _veilEl.className = 'comm-veil';
        _docEl.appendChild(_veilEl);
        body.appendChild(_minutesEl); body.appendChild(_docEl);
        _el.appendChild(header); _el.appendChild(body);
        renderMinutes(); renderDoc();
    }

    function refresh() {
        if (_statusEl) {
            _statusEl.textContent = '同步中';
            _statusEl.setAttribute('data-state', 'loading');
        }
        var generation = _generation;
        var callId = _host.request('snapshot', {category:'公社防具'}, function(response) {
            if (generation !== _generation || !_el) return;
            if (!response || !response.success) {
                setStatus('读取失败', 'error');
                toast(errorMessage(response && response.error));
                renderDoc(); return;
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
            renderMinutes(); renderDoc();
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
        renderMinutes(); renderDoc(); requestPreview();
    }

    function deselect() {
        _selectedIndex = -1; _selectedRecipe = null;
        _preview = null; _commitFeedback = null;
        renderMinutes(); renderDoc();
    }

    function requestPreview() {
        if (!_selectedRecipe || _busy) return;
        _previewBusy = true; renderDoc();
        var generation = _generation;
        var recipeIndex = _selectedIndex, craftCount = _craftCount;
        _host.request('preview', {category:'公社防具', recipeIndex:recipeIndex,
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
        _host.request('commit', {category:'公社防具',
            expectedCraftToken:_preview.craftToken}, function(response) {
            if (generation !== _generation || !_el) return;
            _busy = false;
            if (response && response.success) {
                toast('已下线 ' + (response.crafted && response.crafted.displayName
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
        wrap.className = 'comm-iconwrap pending';
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

    // ── 左页：会议纪要 ──
    function renderMinutes() {
        if (!_minutesEl) return;
        _minutesEl.innerHTML = '';
        var head = document.createElement('div');
        head.className = 'comm-minutes-head';
        head.innerHTML = '<b>蓉都公社生产会议纪要</b>'
            + '<small>蓉公产〔七〕第 04 号</small>';
        _minutesEl.appendChild(head);
        var lead = document.createElement('p');
        lead.className = 'comm-minutes-lead';
        lead.textContent = '经蓉都公社各工作组研究决定，针对以下防御用具进行扩大生产：';
        _minutesEl.appendChild(lead);
        var list = document.createElement('div');
        list.className = 'comm-minutes-list';
        if (!_recipes.length && _snapshot) {
            var empty = document.createElement('div');
            empty.className = 'comm-empty';
            empty.textContent = '本会期暂无排产条目。';
            list.appendChild(empty);
        }
        for (var i = 0; i < _recipes.length; i++) {
            var recipe = _recipes[i];
            var item = document.createElement('button');
            item.type = 'button';
            item.className = 'comm-item ' + availabilityClass(recipe.availability)
                + (_selectedRecipe && _selectedRecipe.recipeIndex === recipe.recipeIndex
                    ? ' active' : '');
            item.setAttribute('data-audio-cue', 'activate');
            var num = document.createElement('span');
            num.className = 'comm-item-num';
            num.textContent = NUMERALS[i] || String(i + 1);
            var name = document.createElement('span');
            name.className = 'comm-item-name';
            name.textContent = recipe.output.displayName || recipe.title;
            var state = document.createElement('span');
            state.className = 'comm-item-state';
            state.textContent = availabilityLabel(recipe);
            // 圈阅红圈
            var circle = document.createElement('span');
            circle.className = 'comm-item-circle';
            circle.setAttribute('aria-hidden', 'true');
            item.appendChild(num); item.appendChild(name);
            item.appendChild(state); item.appendChild(circle);
            item.addEventListener('click', bindRecipe(recipe.recipeIndex));
            list.appendChild(item);
        }
        _minutesEl.appendChild(list);
        function bindRecipe(recipeIndex) {
            return function() { selectRecipe(recipeIndex); };
        }
    }

    // ── 右页：生产指标档案 ──
    function renderDoc() {
        if (!_docEl) return;
        _docEl.innerHTML = '';
        _docEl.appendChild(_veilEl);
        _veilEl.innerHTML = '';
        var pending = !!(_selectedRecipe && _previewBusy && !_preview);
        _veilEl.classList.toggle('on', pending);
        _el.classList.toggle('comm-pending', pending);
        if (pending) {
            var note = document.createElement('div');
            note.className = 'comm-veil-note';
            note.textContent = '正在核算指标…';
            _veilEl.appendChild(note);
        }

        var paper = document.createElement('div');
        paper.className = 'comm-paper';
        _docEl.appendChild(paper);

        if (!_selectedRecipe) {
            var idle = document.createElement('div');
            idle.className = 'comm-doc-idle';
            idle.innerHTML = '<p>—— 请在左侧纪要中圈选排产条目 ——</p>';
            paper.appendChild(idle);
            return;
        }
        renderDocBody(paper);
    }

    function renderDocBody(paper) {
        var recipe = _selectedRecipe;
        var index = _recipes.indexOf(recipe);

        var head = document.createElement('header');
        head.className = 'comm-doc-head';
        head.innerHTML = '<b>七年计划防御用具产线——'
            + escapeHtml(recipe.output.displayName || recipe.title)
            + '生产指标</b>'
            + '<small>蓉公产字〔七计〕第 ' + pad2(index + 1) + ' 号</small>';
        paper.appendChild(head);

        // 简介段：图标左浮，文字环绕（沿用物品 description，缺失时用兜底官话）
        var intro = document.createElement('div');
        intro.className = 'comm-doc-intro';
        var figure = document.createElement('span');
        figure.className = 'comm-doc-figure';
        mountIcon(figure, recipe.output.icon, 'comm-icon-lg');
        var cap = document.createElement('span');
        cap.className = 'comm-doc-figcap';
        cap.textContent = '图：' + recipe.output.displayName;
        figure.appendChild(cap);
        intro.appendChild(figure);
        var desc = document.createElement('p');
        desc.textContent = (typeof recipe.output.description === 'string'
            && recipe.output.description)
            ? recipe.output.description
            : '本品列入公社防御用具序列，由产线统一轧制、检验、入库。';
        intro.appendChild(desc);
        paper.appendChild(intro);

        var official = document.createElement('p');
        official.className = 'comm-doc-official';
        official.textContent = '为坚决落实公社扩大再生产指示精神，保障一线防御供给，'
            + '现就本品投产所需物资调拨指标通知如下。请各工作组按清单据实核发，'
            + '逐条审计、照章执行，不得挪用。';
        paper.appendChild(official);

        var listTitle = document.createElement('p');
        listTitle.className = 'comm-doc-list-title';
        listTitle.textContent = '物资调拨清单：';
        paper.appendChild(listTitle);
        var list = document.createElement('div');
        list.className = 'comm-doc-list';
        if (_preview) {
            renderDocMaterials(list, _preview);
        } else if (_previewBusy) {
            var loading = document.createElement('p');
            loading.className = 'comm-doc-note';
            loading.textContent = '指标核算中……';
            list.appendChild(loading);
        } else {
            var wait = document.createElement('p');
            wait.className = 'comm-doc-note';
            wait.textContent = recipe.canCraftOne
                ? '等待核算结果……' : availabilityLabel(recipe);
            list.appendChild(wait);
        }
        paper.appendChild(list);
        if (_commitFeedback) {
            var feedback = document.createElement('p');
            feedback.className = 'comm-doc-note warn';
            feedback.textContent = _commitFeedback;
            paper.appendChild(feedback);
        }

        var salute = document.createElement('div');
        salute.className = 'comm-doc-salute';
        salute.innerHTML = '<p>此致</p><p class="indent">敬礼！</p>';
        paper.appendChild(salute);

        var foot = document.createElement('div');
        foot.className = 'comm-doc-foot';
        var sign = document.createElement('div');
        sign.className = 'comm-doc-sign';
        sign.innerHTML = '<b>蓉都公社生产大队</b><small>七年计划执行办公室</small>';
        foot.appendChild(sign);
        foot.appendChild(buildSeal());
        var actions = document.createElement('div');
        actions.className = 'comm-doc-actions';
        if (recipe.batchEligible) {
            actions.appendChild(buildStepper());
        }
        var cost = document.createElement('div');
        cost.className = 'comm-cost';
        cost.textContent = costText(recipe);
        actions.appendChild(cost);
        var confirm = document.createElement('button');
        confirm.type = 'button';
        confirm.className = 'comm-confirm';
        confirm.textContent = _busy ? '投产中…' : '投产（确认合成）';
        var committable = !!_preview && _preview.canCommit && !_busy && !_previewBusy;
        confirm.disabled = !committable;
        if (!committable) confirm.setAttribute('aria-disabled', 'true');
        confirm.setAttribute('data-audio-cue', 'activate');
        confirm.addEventListener('click', commit);
        actions.appendChild(confirm);
        foot.appendChild(actions);
        paper.appendChild(foot);
    }

    // 红圈印章：圆环 + 环形文字 + 五角星
    function buildSeal() {
        var seal = document.createElement('div');
        seal.className = 'comm-seal';
        seal.setAttribute('aria-hidden', 'true');
        seal.innerHTML =
            '<svg viewBox="0 0 100 100" width="86" height="86">'
            + '<defs><path id="comm-seal-arc" '
            + 'd="M 50 50 m -33 0 a 33 33 0 1 1 66 0 a 33 33 0 1 1 -66 0"/></defs>'
            + '<circle cx="50" cy="50" r="45" fill="none" '
            + 'stroke="#b03430" stroke-width="2.5"/>'
            + '<text fill="#b03430" font-size="10.5" '
            + 'font-family="SimSun,serif" letter-spacing="1.5">'
            + '<textPath href="#comm-seal-arc" startOffset="2%">'
            + '蓉都公社生产大队·监制</textPath></text>'
            + '<text x="50" y="60" text-anchor="middle" fill="#b03430" '
            + 'font-size="24">★</text>'
            + '</svg>';
        return seal;
    }

    function buildStepper() {
        var stepper = document.createElement('div');
        stepper.className = 'comm-count';
        var minus = document.createElement('button');
        minus.type = 'button'; minus.textContent = '−';
        minus.setAttribute('aria-label', '减少一件');
        minus.disabled = _craftCount <= 1 || _busy || _previewBusy;
        minus.addEventListener('click', function() { setCraftCount(_craftCount - 1); });
        var input = document.createElement('input');
        input.className = 'comm-count-input';
        input.type = 'text'; input.inputMode = 'numeric';
        input.value = String(_craftCount);
        input.setAttribute('aria-label', '投产数量');
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
            line.className = 'comm-req infra ' + (row.met ? 'met' : 'unmet');
            var nameEl = document.createElement('span');
            nameEl.className = 'comm-req-name';
            nameEl.textContent = row.name + (row.appliance ? '·' + row.appliance : '');
            var mark = document.createElement('span');
            mark.className = 'comm-req-mark';
            mark.textContent = row.met ? '审计通过' : '审计未通过';
            line.appendChild(nameEl); line.appendChild(mark);
            list.appendChild(line);
        }
        var materials = preview.materials || [];
        for (var m = 0; m < materials.length; m++) {
            var material = materials[m];
            var node = document.createElement('div');
            node.className = 'comm-req ' + (material.enough ? 'met' : 'unmet');
            var iconNode = document.createElement('span');
            iconNode.className = 'comm-req-icon';
            mountIcon(iconNode, material.icon, 'comm-icon-sm');
            var nameNode = document.createElement('span');
            nameNode.className = 'comm-req-name';
            nameNode.textContent = material.displayName
                + (material.consumed ? '' : '（不消耗）')
                + ' ×' + material.required + '（现存 ' + material.owned + '）';
            var markNode = document.createElement('span');
            markNode.className = 'comm-req-mark';
            markNode.textContent = material.enough ? '审计通过' : '审计未通过';
            node.appendChild(iconNode); node.appendChild(nameNode);
            node.appendChild(markNode);
            list.appendChild(node);
        }
    }

    function availabilityLabel(recipe) {
        switch (recipe.availability) {
            case 'ready': return '具备投产条件';
            case 'infrastructure_locked': return '缺设备';
            case 'level_locked': return '等级不足';
            case 'material_missing': return '物资不足';
            case 'insufficient_money': return '经费不足';
            case 'insufficient_kpoint': return 'K点不足';
            case 'inventory_full': return '库房已满';
            default: return '暂缓排产';
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
        if (money > 0) parts.push('经费 ' + _host.formatNumber(money * _craftCount));
        if (kpoints > 0) parts.push('K点 ' + _host.formatNumber(kpoints * _craftCount));
        return parts.length ? '核算：' + parts.join('　') : '免收经费';
    }

    function pad2(value) { return value < 10 ? '0' + value : String(value); }

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
        var messages = {category_not_found:'未找到公社防具分类。', recipe_not_found:'配方已变化。',
            item_not_found:'未找到该物资或产物。', level_locked:'角色等级与逆向等级不足。',
            infrastructure_locked:'设备未就绪，需要先在基地建造。',
            material_missing:'所需物资不足。', insufficient_money:'金币不足。',
            insufficient_kpoint:'K 点不足。', inventory_full:'背包空间不足。',
            stale_state:'物品状态已变化，请重新核对。', batch_not_supported:'该产物只能逐件生产。',
            busy:'产线正在处理另一项生产。', reconcile_required:'上次提交结果需要重新核对。',
            stale_snapshot:'排产目录已更新，请重新同步。',
            malformed_response:'回包不完整。', timeout:'生产响应超时。',
            client_timeout:'生产响应超时。', disconnected:'连接已断开。'};
        return messages[error] || '生产操作失败，请重试。';
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
