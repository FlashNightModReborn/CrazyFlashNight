/** 烹饪厨房 — 纸质感菜谱界面，独立于合成工作台。
 *  左列：纸条（红线白纸黑字，每张纸条 = 一本菜谱，按配方 book 字段分组）；
 *  中右：摊开的蓝色横线白纸书本。不选纸条时书页空白；
 *  选中纸条后左页钉一张厨具照片（黑底 + 白边 + 黑外框，按选中/首道
 *  菜品所需厨具加载 assets/cooking/<厨具名>.svg|png），右页摆出该菜谱
 *  的菜品小照片；点菜品弹出配方纸卡，材料与厨具条件满足打黑勾、
 *  不满足打红叉，附份数与确认烹饪。
 *  协议仍走 CraftingRuntime mux，snapshot/preview/commit 语义与其他品类一致。 */
var CookingPanel = (function() {
    'use strict';
    var _host = null;
    var _el = null, _statusEl = null, _booksEl = null, _stageEl = null,
        _stageCaptionEl = null, _rightEl = null, _popEl = null,
        _closeButton = null, _moneyEl = null, _kpointsEl = null;
    var _snapshot = null, _books = [], _selectedBook = '', _selectedIndex = -1,
        _selectedRecipe = null, _cardOpen = false,
        _preview = null, _craftCount = 1;
    var _busy = false, _previewBusy = false, _generation = 0;
    var _commitFeedback = null;

    function mount(shellEl, deps) {
        _host = deps;
        _generation++;
        _snapshot = null; _books = []; _selectedBook = '';
        _selectedIndex = -1; _selectedRecipe = null; _cardOpen = false;
        _preview = null;
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
        _cardOpen = false;
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
        _booksEl.className = 'cooking-slips';
        _booksEl.setAttribute('aria-label', '菜谱');

        var book = document.createElement('div');
        book.className = 'cooking-book';
        _stageEl = document.createElement('div');
        _stageEl.className = 'cooking-page left';
        var photo = document.createElement('div');
        photo.className = 'cooking-photo';
        var photoFrame = document.createElement('div');
        photoFrame.className = 'cooking-photo-frame';
        photo.appendChild(photoFrame);
        _stageCaptionEl = document.createElement('div');
        _stageCaptionEl.className = 'cooking-photo-caption';
        photo.appendChild(_stageCaptionEl);
        _stageEl.appendChild(photo);
        _rightEl = document.createElement('section');
        _rightEl.className = 'cooking-page right';
        book.appendChild(_stageEl); book.appendChild(_rightEl);
        _popEl = document.createElement('div');
        _popEl.className = 'cooking-pop-host';
        book.appendChild(_popEl);

        body.appendChild(_booksEl); body.appendChild(book);
        _el.appendChild(header); _el.appendChild(body);
        renderBooks(); renderStage(); renderRight();
    }

    function refresh() {
        if (_statusEl) {
            _statusEl.textContent = '同步中';
            _statusEl.setAttribute('data-state', 'loading');
        }
        var generation = _generation;
        var callId = _host.request('snapshot', {category:'烹饪'}, function(response) {
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
                _selectedIndex = -1; _selectedRecipe = null;
                _cardOpen = false; _preview = null;
            }
            if (_selectedRecipe) {
                var found = findRecipe(_selectedRecipe.recipeIndex);
                if (!found) {
                    _selectedRecipe = null; _selectedIndex = -1;
                    _cardOpen = false; _preview = null;
                }
                else _selectedRecipe = found;
            }
            renderBooks(); renderStage(); renderRight();
            if (_selectedRecipe && _cardOpen) requestPreview();
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
        if (_selectedBook === name) {
            // 再点当前纸条：收回纸条，书本翻回空白页。
            _selectedBook = '';
            _selectedIndex = -1; _selectedRecipe = null;
            _cardOpen = false;
            _preview = null; _commitFeedback = null;
            renderBooks(); renderStage(); renderRight();
            return;
        }
        _selectedBook = name;
        _selectedIndex = -1; _selectedRecipe = null; _cardOpen = false;
        _preview = null; _commitFeedback = null;
        renderBooks(); renderStage(); renderRight();
    }

    // 收卡只关配方纸：菜品保持选中、厨具照片留在左页。
    function closeRecipe() {
        if (!_cardOpen) return;
        _cardOpen = false; _commitFeedback = null;
        renderRight();
    }

    // 取消选中菜品（换纸条/再次点该菜时调用）：照片也撤下。
    function deselectRecipe() {
        _selectedIndex = -1; _selectedRecipe = null;
        _cardOpen = false; _preview = null; _commitFeedback = null;
        renderStage(); renderRight();
    }

    function selectRecipe(recipeIndex) {
        var recipe = findRecipe(recipeIndex);
        if (!recipe) return;
        if (_selectedRecipe && _selectedRecipe.recipeIndex === recipe.recipeIndex) {
            // 已选中该菜：卡关着就重新展开，卡开着就取消选中收起照片。
            if (!_cardOpen) {
                _cardOpen = true;
                renderRight();
                if (!_preview && !_previewBusy) requestPreview();
            } else {
                deselectRecipe();
            }
            return;
        }
        _selectedIndex = Number(recipeIndex);
        _selectedRecipe = recipe;
        _cardOpen = true;
        _craftCount = 1; _preview = null; _commitFeedback = null;
        renderStage(); renderRight(); requestPreview();
    }

    function requestPreview() {
        if (!_selectedRecipe || _busy) return;
        _previewBusy = true; renderRight();
        var generation = _generation;
        var recipeIndex = _selectedIndex, craftCount = _craftCount;
        _host.request('preview', {category:'烹饪', recipeIndex:recipeIndex,
            craftCount:craftCount}, function(response) {
            if (generation !== _generation || !_el) return;
            _previewBusy = false;
            if (_selectedIndex !== recipeIndex || _craftCount !== craftCount) return;
            if (!response || !response.success) {
                // 核算失败：收卡留选中（照片保留），toast 说明原因。
                _preview = null; _cardOpen = false;
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
            slip.className = 'cooking-slip'
                + (book.name === _selectedBook ? ' active' : '');
            slip.setAttribute('data-audio-cue', 'activate');
            slip.setAttribute('aria-pressed', book.name === _selectedBook ? 'true' : 'false');
            var nameEl = document.createElement('span');
            nameEl.className = 'cooking-slip-name';
            nameEl.textContent = book.name;
            var count = document.createElement('span');
            count.className = 'cooking-slip-count';
            count.textContent = book.recipes.length + ' 道';
            slip.appendChild(nameEl); slip.appendChild(count);
            slip.addEventListener('click', bindBook(book.name));
            _booksEl.appendChild(slip);
        }
        function bindBook(name) {
            return function() { selectBook(name); };
        }
    }

    function displayRecipe() {
        // 只在做菜详情（已点选菜品）时展示厨具照片，只抽纸条不贴照片。
        return _selectedRecipe;
    }

    function stageAppliance(recipe) {
        // 菜品的第一个基建条件决定厨具；无门槛的菜默认炒锅。
        var rows = recipe && recipe.infrastructure instanceof Array
            ? recipe.infrastructure : [];
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].appliance) return String(rows[i].appliance);
        }
        if (_preview && _preview.infrastructure instanceof Array
                && _selectedRecipe && recipe === _selectedRecipe) {
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
        var frame = _stageEl.querySelector('.cooking-photo-frame');
        if (!frame) return;
        var recipe = displayRecipe();
        var appliance = stageAppliance(recipe);
        frame.innerHTML = '';
        _stageEl.setAttribute('data-appliance', appliance);
        if (!appliance) {
            _stageCaptionEl.textContent = '';
            _stageEl.classList.add('blank');
            return;
        }
        _stageEl.classList.remove('blank');
        // 整张照片加载完才揭开：先压隐整个相框，svg/png 就位后一起淡入。
        var photo = _stageEl.querySelector('.cooking-photo');
        if (photo) photo.classList.add('loading');
        var reveal = function() {
            if (photo) photo.classList.remove('loading');
        };
        var img = document.createElement('img');
        img.className = 'cooking-photo-img';
        img.alt = appliance;
        img.draggable = false;
        // 资产接口：assets/cooking/<厨具名>.svg → 失败回落 .png → 再回落占位件
        img.addEventListener('load', reveal);
        img.addEventListener('error', function onError() {
            img.removeEventListener('error', onError);
            img.remove();
            var fallback = document.createElement('img');
            fallback.className = img.className;
            fallback.alt = appliance;
            fallback.draggable = false;
            fallback.addEventListener('load', reveal);
            fallback.addEventListener('error', function() {
                fallback.remove();
                mountCookwarePlaceholder(frame, appliance);
                reveal();
            });
            fallback.src = 'assets/cooking/' + encodeURIComponent(appliance) + '.png';
            frame.appendChild(fallback);
        });
        img.src = 'assets/cooking/' + encodeURIComponent(appliance) + '.svg';
        frame.appendChild(img);
        _stageCaptionEl.textContent = appliance;
    }

    function mountCookwarePlaceholder(frame, appliance) {
        var placeholder = document.createElement('div');
        placeholder.className = 'cooking-photo-placeholder';
        placeholder.innerHTML = '<i></i><b>' + escapeHtml(appliance) + '</b>';
        frame.appendChild(placeholder);
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
        if (!_rightEl || !_popEl) return;
        _rightEl.innerHTML = '';
        _popEl.innerHTML = '';
        renderDishList();
        if (_selectedRecipe && _cardOpen) {
            // 核算期只压幕布不弹卡；preview 到手才整体弹出，无中间态。
            if (_preview) renderRecipeCard();
            else if (_previewBusy) renderPreviewVeil();
            else renderRecipeCard();
        }
        _el.classList.toggle('cooking-pending',
            !!(_selectedRecipe && _cardOpen && _previewBusy && !_preview));
    }

    function renderDishList() {
        var recipes = bookRecipes();
        var grid = document.createElement('div');
        grid.className = 'cooking-dish-grid';
        if (!_selectedBook) {
            grid.classList.add('empty');
            _rightEl.appendChild(grid);
            return;
        }
        if (!recipes.length) {
            var empty = document.createElement('div');
            empty.className = 'cooking-empty';
            empty.textContent = _snapshot ? '这本菜谱还没有可做的菜。' : '同步中…';
            grid.appendChild(empty);
        }
        for (var i = 0; i < recipes.length; i++) {
            var recipe = recipes[i];
            var card = document.createElement('button');
            card.type = 'button';
            card.className = 'cooking-dish-photo ' + availabilityClass(recipe.availability)
                + (_selectedRecipe && _selectedRecipe.recipeIndex === recipe.recipeIndex
                    ? ' active' : '');
            card.setAttribute('data-audio-cue', 'activate');
            var thumb = document.createElement('span');
            thumb.className = 'cooking-dish-thumb';
            thumb.innerHTML = _host.iconHtml(recipe.output.icon, 'cooking-icon');
            var name = document.createElement('span');
            name.className = 'cooking-dish-name';
            name.textContent = recipe.title;
            var state = document.createElement('span');
            state.className = 'cooking-dish-state';
            state.textContent = availabilityLabel(recipe);
            card.appendChild(thumb); card.appendChild(name); card.appendChild(state);
            card.addEventListener('click', bindDish(recipe.recipeIndex));
            grid.appendChild(card);
        }
        _rightEl.appendChild(grid);
        function bindDish(recipeIndex) {
            return function() { selectRecipe(recipeIndex); };
        }
    }

    function availabilityClass(availability) {
        return availability === 'ready' ? 'is-ready' : 'is-blocked';
    }

    // 核算期的幕布：罩住书本挡住点击，不弹卡，不出现中间态内容。
    function renderPreviewVeil() {
        var veil = document.createElement('div');
        veil.className = 'cooking-recipe-pop veil';
        var note = document.createElement('div');
        note.className = 'cooking-veil-note';
        note.textContent = '正在核算…';
        veil.appendChild(note);
        _popEl.appendChild(veil);
    }

    function renderRecipeCard() {
        var recipe = _selectedRecipe;
        var pop = document.createElement('div');
        pop.className = 'cooking-recipe-pop';
        var card = document.createElement('div');
        card.className = 'cooking-recipe-card';
        card.setAttribute('role', 'dialog');
        card.setAttribute('aria-label', '配方：' + recipe.title);

        var close = document.createElement('button');
        close.type = 'button';
        close.className = 'cooking-pop-close';
        close.textContent = '×';
        close.setAttribute('aria-label', '收起配方');
        close.setAttribute('data-audio-cue', 'back');
        close.addEventListener('click', closeRecipe);
        card.appendChild(close);

        var head = document.createElement('div');
        head.className = 'cooking-recipe-head';
        var thumb = document.createElement('span');
        thumb.className = 'cooking-dish-thumb sm';
        thumb.innerHTML = _host.iconHtml(recipe.output.icon, 'cooking-icon');
        var titleBlock = document.createElement('div');
        titleBlock.className = 'cooking-recipe-title';
        var title = document.createElement('b');
        title.textContent = recipe.title;
        var owned = document.createElement('small');
        owned.textContent = '现有 ' + recipe.owned.total + ' 份';
        titleBlock.appendChild(title); titleBlock.appendChild(owned);
        head.appendChild(thumb); head.appendChild(titleBlock);
        card.appendChild(head);

        var body = document.createElement('div');
        body.className = 'cooking-recipe-body';
        if (_preview) {
            renderRequirements(body, _preview);
            if (_previewBusy) {
                var recalc = document.createElement('div');
                recalc.className = 'cooking-recipe-note';
                recalc.textContent = '正在核算…';
                body.appendChild(recalc);
            }
        } else {
            var wait = document.createElement('div');
            wait.className = 'cooking-recipe-note';
            wait.textContent = recipe.canCraftOne
                ? '等待核算结果…' : availabilityLabel(recipe);
            body.appendChild(wait);
        }
        if (_commitFeedback) {
            var feedback = document.createElement('div');
            feedback.className = 'cooking-recipe-note warn';
            feedback.textContent = _commitFeedback;
            body.appendChild(feedback);
        }
        card.appendChild(body);

        var footer = document.createElement('div');
        footer.className = 'cooking-recipe-footer';
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
        card.appendChild(footer);

        // 点纸卡外的书本区域收回配方。
        pop.addEventListener('click', function(event) {
            if (event.target === pop) closeRecipe();
        });
        pop.appendChild(card);
        _popEl.appendChild(pop);
    }

    function renderRequirements(body, preview) {
        var infra = preview.infrastructure instanceof Array ? preview.infrastructure : [];
        for (var i = 0; i < infra.length; i++) {
            var row = infra[i];
            var node = document.createElement('div');
            node.className = 'cooking-req infra ' + (row.met ? 'met' : 'unmet');
            var spacer = document.createElement('span');
            spacer.className = 'cooking-req-icon';
            var label = document.createElement('span');
            label.className = 'cooking-req-name';
            label.textContent = row.name + (row.appliance ? '·' + row.appliance : '');
            var mark = document.createElement('span');
            mark.className = 'cooking-req-mark ' + (row.met ? 'ok' : 'no');
            mark.textContent = row.met ? '✓' : '✗';
            node.appendChild(spacer); node.appendChild(label); node.appendChild(mark);
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
            count.textContent = material.owned + '/' + material.required;
            var mark2 = document.createElement('span');
            mark2.className = 'cooking-req-mark ' + (material.enough ? 'ok' : 'no');
            mark2.textContent = material.enough ? '✓' : '✗';
            line.appendChild(iconNode); line.appendChild(nameNode);
            line.appendChild(count); line.appendChild(mark2);
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
        // 重核期间保留旧 preview：卡不塌、控件禁用，回来就地刷新。
        renderRight(); requestPreview();
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
            infrastructure_locked:'厨具未就绪，需要先在基地建造对应烹饪设备。',
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
            book:_selectedBook, selectedIndex:_selectedIndex, cardOpen:_cardOpen,
            craftCount:_craftCount, busy:_busy, previewBusy:_previewBusy,
            books:_books.map(function(book) { return book.name; })
        }; }
    };
})();
