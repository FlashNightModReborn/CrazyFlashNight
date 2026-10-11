/** A兵团·武器库 — 黑白灰工业机能风合成界面，覆盖武器合成/饰品合成/进阶防具/基础防具
 *  四个类目（由 crafting.js 按 initData.category 挂载并传入 deps.category）。
 *  左栏：军械目录条目（平行四边形机能饰带 + 状态色带）；
 *  右栏：蓝图卡——底层蓝图网格 + 产物图标白线剪影作概念图，前景同图标全彩展示，
 *  下接调拨清单与投产按钮。物品简介直接用产物 description。
 *  协议走 CraftingRuntime mux，snapshot/preview/commit 语义与烹饪/公社一致。 */
var ArmoryPanel = (function() {
    'use strict';
    var _host = null;
    var _category = '';
    var _el = null, _statusEl = null, _listEl = null, _docEl = null,
        _veilEl = null, _closeButton = null, _moneyEl = null, _kpointsEl = null,
        _brandTitleEl = null;
    var _snapshot = null, _recipes = [], _selectedIndex = -1,
        _selectedRecipe = null, _preview = null, _craftCount = 1;
    var _busy = false, _previewBusy = false, _generation = 0;
    var _commitFeedback = null;

    var CATEGORY_NAMES = {
        '武器合成': '武器合成',
        '饰品合成': '饰品合成',
        '进阶防具': '进阶防具',
        '基础防具': '基础防具'
    };

    function mount(shellEl, deps) {
        _host = deps;
        _category = _host && _host.category ? _host.category : '武器合成';
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
        _el.className = 'arm-panel';
        _el.setAttribute('data-armory-category', _category);

        // 白线蓝图走 assets/armory-blueprints/*.svg（ffdec 提取的源素材线稿）；
        // 无素材/饰品类不出线稿，保留网格底 + 全彩图标。

        var header = document.createElement('header');
        header.className = 'arm-header';
        header.innerHTML =
            '<span class="arm-slashes" aria-hidden="true"></span>'
            // A兵团标志：直接引用 assets/logos/a-legion-emblem.svg 的官方徽标
            // 矢量路径（两枚错位开口三角构成 A 剪影），填当前主题色。
            + '<span class="arm-mark" aria-hidden="true"><svg viewBox="63 -3 168 146" width="34" height="34">'
            + '<path d="M227.75 140.05L65.95 139.70L134.25 23.10L177.95 98.45L157.95 98.45L134.90 55.95L96.60 123.95L218.75 124.25Z '
            + 'M147.85 0L148.00 0.10L215.30 118.20L108.45 117.30L117.85 101.75L188.30 102.40L138.40 16.10L147.80 0Z" '
            + 'fill="rgba(216,220,226,.92)"/>'
            + '</svg></span>';
        var brand = document.createElement('div');
        brand.className = 'arm-brand';
        _brandTitleEl = document.createElement('h1');
        _brandTitleEl.textContent = CATEGORY_NAMES[_category] || _category;
        brand.innerHTML = '<span class="arm-kicker">A兵团 · 武器库</span>';
        brand.appendChild(_brandTitleEl);
        _statusEl = document.createElement('div');
        _statusEl.className = 'arm-status';
        _statusEl.textContent = '同步中';
        var metrics = document.createElement('div');
        metrics.className = 'arm-metrics';
        _moneyEl = document.createElement('span');
        _moneyEl.className = 'arm-metric';
        _kpointsEl = document.createElement('span');
        _kpointsEl.className = 'arm-metric kpoints';
        metrics.appendChild(_moneyEl); metrics.appendChild(_kpointsEl);
        _closeButton = document.createElement('button');
        _closeButton.type = 'button';
        _closeButton.className = 'arm-close';
        _closeButton.textContent = '×';
        _closeButton.setAttribute('aria-label', '关闭武器库');
        _closeButton.setAttribute('data-audio-cue', 'back');
        _closeButton.addEventListener('click', function() {
            if (_host && _host.requestClose) _host.requestClose('header');
        });
        header.appendChild(brand); header.appendChild(_statusEl);
        header.appendChild(metrics); header.appendChild(_closeButton);

        var body = document.createElement('div');
        body.className = 'arm-body';
        _listEl = document.createElement('aside');
        _listEl.className = 'arm-list';
        _docEl = document.createElement('article');
        _docEl.className = 'arm-doc';
        _veilEl = document.createElement('div');
        _veilEl.className = 'arm-veil';
        _docEl.appendChild(_veilEl);
        body.appendChild(_listEl); body.appendChild(_docEl);
        _el.appendChild(header); _el.appendChild(body);
        renderList(); renderDoc();
    }

    function refresh() {
        if (_statusEl) {
            _statusEl.textContent = '同步中';
            _statusEl.setAttribute('data-state', 'loading');
        }
        var generation = _generation;
        var callId = _host.request('snapshot', {category:_category}, function(response) {
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
            renderList(); renderDoc();
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
        renderList(); renderDoc(); requestPreview();
    }

    function deselect() {
        _selectedIndex = -1; _selectedRecipe = null;
        _preview = null; _commitFeedback = null;
        renderList(); renderDoc();
    }

    function requestPreview() {
        if (!_selectedRecipe || _busy) return;
        _previewBusy = true; renderDoc();
        var generation = _generation;
        var recipeIndex = _selectedIndex, craftCount = _craftCount;
        _host.request('preview', {category:_category, recipeIndex:recipeIndex,
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
        _host.request('commit', {category:_category,
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
        wrap.className = 'arm-iconwrap pending';
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

    // 蓝图线稿：ffdec 从源 SWF 导出的元件 SVG 去填充留白描边（tools/bake-armory-blueprints.js）。
    // 文件名即图标名（UTF-8 直存，URL 侧 encodeURIComponent）；无素材时回退到图标滤镜线稿。
    var BP_ROOT = (typeof window !== 'undefined' && window.CF7_ARMORY_BP_ROOT)
        ? String(window.CF7_ARMORY_BP_ROOT)
        : 'assets/armory-blueprints/';
    if (BP_ROOT.charAt(BP_ROOT.length - 1) !== '/') BP_ROOT += '/';

    function mountBlueprint(hostEl, iconName) {
        if (!iconName) return;
        var img = document.createElement('img');
        img.className = 'arm-bp-art';
        img.alt = '';
        img.draggable = false;
        // 无蓝图素材：不出滤镜线稿（噪点版），只留网格底
        img.addEventListener('error', function() {
            if (img.parentNode) img.parentNode.removeChild(img);
        });
        img.src = BP_ROOT + encodeURIComponent(iconName) + '.svg';
        hostEl.appendChild(img);
    }

    // ── 左栏：军械目录（三列网格，图标在上名称在下）──
    function renderList() {
        if (!_listEl) return;
        _listEl.innerHTML = '';
        var head = document.createElement('div');
        head.className = 'arm-list-head';
        head.innerHTML = '<b>军械目录</b><small>ARMORY CATALOGUE // ' + pad2(_recipes.length) + ' 条目</small>';
        _listEl.appendChild(head);
        var list = document.createElement('div');
        list.className = 'arm-items';
        if (!_recipes.length && _snapshot) {
            var empty = document.createElement('div');
            empty.className = 'arm-empty';
            empty.textContent = '暂无可排产条目。';
            list.appendChild(empty);
        }
        for (var i = 0; i < _recipes.length; i++) {
            var recipe = _recipes[i];
            var item = document.createElement('button');
            item.type = 'button';
            item.className = 'arm-item ' + availabilityClass(recipe.availability)
                + (_selectedRecipe && _selectedRecipe.recipeIndex === recipe.recipeIndex
                    ? ' active' : '');
            item.setAttribute('data-audio-cue', 'activate');
            item.innerHTML = '<span class="arm-item-strip" aria-hidden="true"></span>';
            var idx = document.createElement('span');
            idx.className = 'arm-item-idx';
            idx.textContent = pad2(i + 1);
            var iconNode = document.createElement('span');
            iconNode.className = 'arm-item-icon';
            mountIcon(iconNode, recipe.output && recipe.output.icon, 'arm-icon-xs');
            var name = document.createElement('span');
            name.className = 'arm-item-name';
            name.textContent = recipe.output.displayName || recipe.title;
            var state = document.createElement('span');
            state.className = 'arm-item-state';
            state.textContent = availabilityLabel(recipe);
            item.appendChild(idx); item.appendChild(iconNode);
            item.appendChild(name); item.appendChild(state);
            item.addEventListener('click', bindRecipe(recipe.recipeIndex));
            list.appendChild(item);
        }
        _listEl.appendChild(list);
        function bindRecipe(recipeIndex) {
            return function() { selectRecipe(recipeIndex); };
        }
    }

    // ── 右栏：蓝图卡 ──
    function renderDoc() {
        if (!_docEl) return;
        _docEl.innerHTML = '';
        _docEl.appendChild(_veilEl);
        _veilEl.innerHTML = '';
        var pending = !!(_selectedRecipe && _previewBusy && !_preview);
        _veilEl.classList.toggle('on', pending);
        _el.classList.toggle('arm-pending', pending);
        if (pending) {
            var note = document.createElement('div');
            note.className = 'arm-veil-note';
            note.textContent = '正在核算蓝图…';
            _veilEl.appendChild(note);
        }

        var paper = document.createElement('div');
        paper.className = 'arm-paper';
        _docEl.appendChild(paper);

        if (!_selectedRecipe) {
            var idle = document.createElement('div');
            idle.className = 'arm-doc-idle';
            idle.innerHTML = '<span class="arm-idle-glyph" aria-hidden="true"></span>'
                + '<p>// 在左侧目录中选择排产条目 //</p>';
            paper.appendChild(idle);
            return;
        }
        renderDocBody(paper);
    }

    function renderDocBody(paper) {
        var recipe = _selectedRecipe;

        // 蓝图区：底图网格 + 白线剪影 + 全彩前景图标
        var bp = document.createElement('div');
        bp.className = 'arm-blueprint';
        // 饰品类（项链等颈部装备）按设计不出蓝图，只留网格底 + 全彩图标
        if (_category !== '饰品合成') {
            var ghost = document.createElement('span');
            ghost.className = 'arm-bp-ghost';
            ghost.setAttribute('aria-hidden', 'true');
            mountBlueprint(ghost, recipe.output.icon);
            bp.appendChild(ghost);
        }
        var fg = document.createElement('span');
        fg.className = 'arm-bp-fg';
        mountIcon(fg, recipe.output.icon, 'arm-icon-fg');
        bp.appendChild(fg);
        var bpTag = document.createElement('span');
        bpTag.className = 'arm-bp-tag';
        bpTag.textContent = 'BP-' + pad2(recipe.recipeIndex + 1);
        bp.appendChild(bpTag);
        paper.appendChild(bp);

        var head = document.createElement('header');
        head.className = 'arm-doc-head';
        head.innerHTML = '<b>' + escapeHtml(recipe.output.displayName || recipe.title) + '</b>'
            + '<small>' + escapeHtml(CATEGORY_NAMES[_category] || _category) + ' 产线 · 指标单</small>';
        paper.appendChild(head);

        var desc = document.createElement('p');
        desc.className = 'arm-doc-desc';
        desc.textContent = (typeof recipe.output.description === 'string'
            && recipe.output.description)
            ? recipe.output.description
            : '本品列入 A兵团武器库产线序列，按标准工艺单排产、检验、入库。';
        paper.appendChild(desc);

        var listTitle = document.createElement('p');
        listTitle.className = 'arm-doc-list-title';
        listTitle.textContent = '// 物资调拨清单';
        paper.appendChild(listTitle);
        var list = document.createElement('div');
        list.className = 'arm-doc-list';
        if (_preview) {
            renderDocMaterials(list, _preview);
        } else if (_previewBusy) {
            var loading = document.createElement('p');
            loading.className = 'arm-doc-note';
            loading.textContent = '指标核算中……';
            list.appendChild(loading);
        } else {
            var wait = document.createElement('p');
            wait.className = 'arm-doc-note';
            wait.textContent = recipe.canCraftOne
                ? '等待核算结果……' : availabilityLabel(recipe);
            list.appendChild(wait);
        }
        paper.appendChild(list);
        if (_commitFeedback) {
            var feedback = document.createElement('p');
            feedback.className = 'arm-doc-note warn';
            feedback.textContent = _commitFeedback;
            paper.appendChild(feedback);
        }

        var foot = document.createElement('div');
        foot.className = 'arm-doc-foot';
        var sign = document.createElement('div');
        sign.className = 'arm-doc-sign';
        sign.innerHTML = '<b>A兵团武器库</b><small>ARMS DIVISION · FAB LINE</small>';
        foot.appendChild(sign);
        var actions = document.createElement('div');
        actions.className = 'arm-doc-actions';
        if (recipe.batchEligible) {
            actions.appendChild(buildStepper());
        }
        var cost = document.createElement('div');
        cost.className = 'arm-cost';
        cost.textContent = costText(recipe);
        actions.appendChild(cost);
        var confirm = document.createElement('button');
        confirm.type = 'button';
        confirm.className = 'arm-confirm';
        confirm.textContent = _busy ? '投产中…' : '投产';
        var committable = !!_preview && _preview.canCommit && !_busy && !_previewBusy;
        confirm.disabled = !committable;
        if (!committable) confirm.setAttribute('aria-disabled', 'true');
        confirm.setAttribute('data-audio-cue', 'activate');
        confirm.addEventListener('click', commit);
        actions.appendChild(confirm);
        foot.appendChild(actions);
        paper.appendChild(foot);
    }

    function buildStepper() {
        var stepper = document.createElement('div');
        stepper.className = 'arm-count';
        var minus = document.createElement('button');
        minus.type = 'button'; minus.textContent = '−';
        minus.setAttribute('aria-label', '减少一件');
        minus.disabled = _craftCount <= 1 || _busy || _previewBusy;
        minus.addEventListener('click', function() { setCraftCount(_craftCount - 1); });
        var input = document.createElement('input');
        input.className = 'arm-count-input';
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
            line.className = 'arm-req infra ' + (row.met ? 'met' : 'unmet');
            var nameEl = document.createElement('span');
            nameEl.className = 'arm-req-name';
            nameEl.textContent = row.name + (row.appliance ? '·' + row.appliance : '');
            var mark = document.createElement('span');
            mark.className = 'arm-req-mark';
            mark.textContent = row.met ? '满足' : '不足';
            line.appendChild(nameEl); line.appendChild(mark);
            list.appendChild(line);
        }
        var materials = preview.materials || [];
        for (var m = 0; m < materials.length; m++) {
            var material = materials[m];
            var node = document.createElement('div');
            node.className = 'arm-req ' + (material.enough ? 'met' : 'unmet');
            var iconNode = document.createElement('span');
            iconNode.className = 'arm-req-icon';
            mountIcon(iconNode, material.icon, 'arm-icon-sm');
            var nameNode = document.createElement('span');
            nameNode.className = 'arm-req-name';
            nameNode.textContent = material.displayName
                + (material.consumed ? '' : '（不消耗）')
                + ' ×' + material.required + '（现存 ' + material.owned + '）';
            var markNode = document.createElement('span');
            markNode.className = 'arm-req-mark';
            markNode.textContent = material.enough ? '满足' : '不足';
            node.appendChild(iconNode); node.appendChild(nameNode);
            node.appendChild(markNode);
            list.appendChild(node);
        }
    }

    function availabilityLabel(recipe) {
        switch (recipe.availability) {
            case 'ready': return '可投产';
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
        var messages = {category_not_found:'未找到该类目的合成清单。', recipe_not_found:'配方已变化。',
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
            category:_category,
            selectedIndex:_selectedIndex,
            craftCount:_craftCount, busy:_busy, previewBusy:_previewBusy,
            recipes:_recipes.length
        }; }
    };
})();
