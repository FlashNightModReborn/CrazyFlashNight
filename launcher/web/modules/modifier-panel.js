(function() {
    'use strict';

    var Runtime = window.ModifierRuntime;
    var shell, root, scale, mux, instance = '', token = '', generation = 0;
    var busy = false, writeBusy = false, phase = 'closed', activeTab = 'economy';
    var snapshot = null, unresolved = null, revision = 0;
    var selectedItem = null, selectedUnit = null;
    var itemQuery = '', itemPage = 1, itemTotal = 0, itemPageSize = 64, itemLoading = false;
    var unitQuery = '', unitPage = 1, unitTotal = 0, unitPageSize = 24, unitLoading = false;
    var closeAfterWrite = false, closing = false, opSequence = 0, armTimer = 0;

    function byId(id) { return root ? root.querySelector('#modifier-' + id) : null; }
    function text(id, value) { var node = byId(id); if (node) node.textContent = value; }
    function setStatus(value, tone) {
        var node = byId('message');
        if (node) { node.textContent = value || ''; node.setAttribute('data-tone', tone || 'neutral'); }
    }

    function create() {
        shell = document.createElement('div');
        shell.className = 'panel-scale-shell modifier-scale-shell';
        return shell;
    }

    function onOpen(host, data) {
        generation++;
        instance = data && typeof data.panelInstanceId === 'string' ? data.panelInstanceId : '';
        token = data && typeof data.token === 'string' ? data.token : '';
        busy = false; writeBusy = false; closing = false; phase = 'loading';
        snapshot = null; unresolved = null; revision = 0;
        selectedItem = null; selectedUnit = null;
        itemQuery = ''; itemPage = 1; itemTotal = 0; itemLoading = false;
        unitQuery = ''; unitPage = 1; unitTotal = 0; unitLoading = false;
        closeAfterWrite = false; opSequence = 0;

        host.innerHTML = '<section class="modifier-panel" data-panel="modifier">'
            + '<header class="modifier-header">'
            + '<div class="modifier-brand"><span class="modifier-kicker">DEVELOPER TOOLS / AS2 AUTHORITY</span>'
            + '<h1>修改器</h1></div>'
            + '<div class="modifier-header-state"><span id="modifier-mode">读取中…</span>'
            + '<span id="modifier-wallet">—</span></div>'
            + '<button type="button" class="modifier-close" id="modifier-close" aria-label="关闭修改器">×</button>'
            + '</header>'
            + '<nav class="modifier-tabs" role="tablist" aria-label="修改器页面">'
            + '<button type="button" class="modifier-tab" role="tab" data-tab="economy" aria-selected="true">经济</button>'
            + '<button type="button" class="modifier-tab" role="tab" data-tab="items" aria-selected="false">物品</button>'
            + '<button type="button" class="modifier-tab" role="tab" data-tab="level" aria-selected="false">关卡</button>'
            + '<button type="button" class="modifier-tab" role="tab" data-tab="units" aria-selected="false">阵营</button>'
            + '</nav>'
            + '<main class="modifier-body">'
            + '<section class="modifier-view" data-view="economy" role="tabpanel">'
            + '<div class="modifier-economy-grid">'
            + '<article class="modifier-card"><p class="modifier-eyebrow">货币</p><h2 id="modifier-money">—</h2><p>金币</p>'
            + '<button type="button" class="modifier-button primary" data-write data-economy="grantMoney">+100,000 金币</button></article>'
            + '<article class="modifier-card"><p class="modifier-eyebrow">点数</p><h2 id="modifier-kcoin">—</h2><p>K点</p>'
            + '<button type="button" class="modifier-button primary" data-write data-economy="grantKCoin">+100,000 K点</button></article>'
            + '<article class="modifier-card modifier-card-wide"><p class="modifier-eyebrow">场景</p><h2 id="modifier-scene">—</h2>'
            + '<p>开发跳转与关卡动作只在角色场景中执行。写操作会按 AS2 现有 dirty/保存语义落盘。</p>'
            + '<button type="button" class="modifier-button danger" data-level-action="test_space">前往测试空间</button></article>'
            + '</div></section>'
            + '<section class="modifier-view" data-view="items" role="tabpanel" hidden>'
            + '<div class="modifier-toolbar"><label class="modifier-search"><span>检索</span>'
            + '<input id="modifier-item-query" type="search" maxlength="64" autocomplete="off" placeholder="id / 名称 / 类型 / 用途"></label>'
            + '<button type="button" class="modifier-button" id="modifier-item-search">搜索</button>'
            + '<button type="button" class="modifier-button quiet" id="modifier-item-clear">清空</button>'
            + '<span class="modifier-page-state" id="modifier-item-page-state">—</span></div>'
            + '<div class="modifier-split">'
            + '<div class="modifier-grid-wrap"><div class="modifier-item-grid" id="modifier-item-grid"></div>'
            + '<div class="modifier-page-row"><button type="button" class="modifier-button" id="modifier-item-prev">上一页</button>'
            + '<button type="button" class="modifier-button" id="modifier-item-next">下一页</button></div></div>'
            + '<aside class="modifier-detail" id="modifier-item-detail"><p class="modifier-empty">选择一个物品查看生产选项。</p></aside>'
            + '</div></section>'
            + '<section class="modifier-view" data-view="level" role="tabpanel" hidden>'
            + '<div class="modifier-level-grid">'
            + '<article class="modifier-card"><p class="modifier-eyebrow">关卡控制</p><h2 id="modifier-stage-state">—</h2>'
            + '<p>当前关卡状态。完成/结束动作使用现役 AS2 关卡权威。</p>'
            + '<div class="modifier-action-row">'
            + '<button type="button" class="modifier-button" data-write data-level-action="unlock_stages">解锁关卡</button>'
            + '<button type="button" class="modifier-button" data-write data-level-action="kill_all">敌人全死</button>'
            + '<button type="button" class="modifier-button" data-write data-level-action="finish_wave">完成当前波次</button>'
            + '<button type="button" class="modifier-button" data-write data-level-action="finish_map">完成当前地图</button>'
            + '<button type="button" class="modifier-button danger" data-write data-level-action="finish_stage">结算关卡</button>'
            + '<button type="button" class="modifier-button danger" data-write data-level-action="test_space">测试空间</button>'
            + '</div></article>'
            + '<article class="modifier-card"><p class="modifier-eyebrow">任务</p><h2>主线任务</h2>'
            + '<p>输入主线 id 后取得对应任务；与旧修改器一致，会移除同一任务链的现有条目并写回主线进度。</p>'
            + '<div class="modifier-inline-form"><input id="modifier-task-id" type="number" min="1" max="999" step="1" value="1" aria-label="主线任务 id">'
            + '<button type="button" class="modifier-button primary" data-write id="modifier-grant-task">获得任务</button></div></article>'
            + '</div></section>'
            + '<section class="modifier-view" data-view="units" role="tabpanel" hidden>'
            + '<div class="modifier-toolbar"><label class="modifier-search"><span>检索</span>'
            + '<input id="modifier-unit-query" type="search" maxlength="64" autocomplete="off" placeholder="id / 单位名 / 兵种名 / key"></label>'
            + '<button type="button" class="modifier-button" id="modifier-unit-search">搜索</button>'
            + '<button type="button" class="modifier-button quiet" id="modifier-unit-clear">清空</button>'
            + '<span class="modifier-page-state" id="modifier-unit-page-state">—</span></div>'
            + '<div class="modifier-split">'
            + '<div class="modifier-grid-wrap"><div class="modifier-unit-grid" id="modifier-unit-grid"></div>'
            + '<div class="modifier-page-row"><button type="button" class="modifier-button" id="modifier-unit-prev">上一页</button>'
            + '<button type="button" class="modifier-button" id="modifier-unit-next">下一页</button></div></div>'
            + '<aside class="modifier-detail" id="modifier-unit-detail"><p class="modifier-empty">选择一个兵种查看生成选项。</p></aside>'
            + '</div></section>'
            + '</main>'
            + '<footer class="modifier-footer"><p id="modifier-message" role="status" aria-live="polite"></p>'
            + '<div class="modifier-reconcile" id="modifier-reconcile" hidden><span>上次操作结果未确认。</span>'
            + '<button type="button" class="modifier-button" id="modifier-reconcile-query">核对结果</button></div></footer>'
            + '</section>';

        root = host;
        scale = window.PanelScale.attach(shell, 1024, 576);
        mux = new Runtime.RequestMux({send:function(message) { return Bridge.send(message); }, panelInstanceId:instance});

        byId('close').onclick = requestClose;
        root.querySelectorAll('.modifier-tab').forEach(function(tab) {
            tab.addEventListener('click', function() { showTab(tab.getAttribute('data-tab')); });
        });
        root.querySelectorAll('[data-economy]').forEach(function(button) {
            button.addEventListener('click', function() { writeRequest(button.getAttribute('data-economy'), {}); });
        });
        root.querySelectorAll('[data-level-action]').forEach(function(button) {
            button.addEventListener('click', function() {
                var action = button.getAttribute('data-level-action');
                if (action === 'finish_stage' || action === 'test_space') arm(button, function() {
                    writeRequest('levelAction', {levelAction:action}, true);
                });
                else writeRequest('levelAction', {levelAction:action});
            });
        });
        byId('grant-task').onclick = function() {
            var value = Number(byId('task-id').value);
            if (!Runtime.int(value, 1, 999)) { setStatus('任务 id 必须是 1–999 的整数。', 'error'); return; }
            writeRequest('grantTask', {taskId:value});
        };
        byId('item-search').onclick = function() { searchItems(); };
        byId('item-clear').onclick = function() { byId('item-query').value = ''; searchItems(); };
        byId('item-query').addEventListener('keydown', function(event) {
            if (event.key === 'Enter') { event.preventDefault(); searchItems(); }
        });
        byId('item-prev').onclick = function() { if (itemPage > 1) { itemPage--; loadItems(); } };
        byId('item-next').onclick = function() {
            if (itemPage * itemPageSize < itemTotal) { itemPage++; loadItems(); }
        };
        byId('unit-search').onclick = function() { searchUnits(); };
        byId('unit-clear').onclick = function() { byId('unit-query').value = ''; searchUnits(); };
        byId('unit-query').addEventListener('keydown', function(event) {
            if (event.key === 'Enter') { event.preventDefault(); searchUnits(); }
        });
        byId('unit-prev').onclick = function() { if (unitPage > 1) { unitPage--; loadUnits(); } };
        byId('unit-next').onclick = function() {
            if (unitPage * unitPageSize < unitTotal) { unitPage++; loadUnits(); }
        };
        byId('reconcile-query').onclick = queryUnresolved;

        showTab(activeTab);
        loadSnapshot(true);
    }

    function showTab(tab) {
        activeTab = tab;
        root.querySelectorAll('.modifier-tab').forEach(function(button) {
            button.setAttribute('aria-selected', String(button.getAttribute('data-tab') === tab));
        });
        root.querySelectorAll('.modifier-view').forEach(function(view) {
            view.hidden = view.getAttribute('data-view') !== tab;
        });
        if (tab === 'items' && !itemTotal) loadItems();
        if (tab === 'units' && !unitTotal) loadUnits();
    }

    function loadSnapshot(initial, quiet) {
        if (!mux) return;
        if (initial) setStatus('正在读取修改器状态…');
        request('snapshot', {v:1, token:token}, function(result) {
            var state = Runtime.normalizeSnapshot(result, token);
            if (!state) {
                if (result && result.requiresReconcile && result.recoveryToken) {
                    setUnresolved(result.recoveryToken, result.recoveryOperationId, '快照');
                }
                if (initial) setStatus(messageFor(result && result.error) || '修改器状态暂时不可用。', 'error');
                return;
            }
            if (state.revision < revision) return;
            snapshot = state;
            revision = state.revision;
            if (result.requiresReconcile && result.recoveryToken) setUnresolved(result.recoveryToken, result.recoveryOperationId, '快照');
            else clearUnresolved();
            updateSnapshot();
            if (!quiet) setStatus(initial ? '修改器已就绪。' : '状态已刷新。', 'ok');
        });
    }

    function updateSnapshot() {
        if (!snapshot) return;
        var state = snapshot.state;
        text('money', state.money.toLocaleString('zh-CN'));
        text('kcoin', state.kcoin.toLocaleString('zh-CN'));
        text('scene', state.stageActive === 'none' ? '基地 / 非关卡' : '关卡：' + state.stageActive);
        text('stage-state', state.stageActive === 'none' ? '当前不在关卡中' : state.stageActive);
        text('mode', state.challengeMode ? '挑战模式' : (state.inWorld ? '角色场景' : '非角色场景'));
        text('wallet', state.money.toLocaleString('zh-CN') + ' 金币 · ' + state.kcoin.toLocaleString('zh-CN') + ' K点');
        var canWrite = !state.challengeMode && state.saveAvailable;
        root.querySelectorAll('[data-write]').forEach(function(button) {
            button.disabled = !canWrite || !!unresolved || writeBusy;
        });
        if (state.challengeMode) setStatus('挑战模式中修改器写操作不可用。', 'error');
        else if (!state.saveAvailable) setStatus('存档系统尚未就绪，写操作不可用。', 'error');
    }

    function setUnresolved(recoveryToken, recoveryOperationId, source) {
        if (!recoveryToken || !recoveryOperationId) {
            setStatus('检测到未确认操作，但缺少恢复身份，请关闭后重启游戏再试。', 'error');
            return;
        }
        unresolved = {token:recoveryToken, operationId:recoveryOperationId, source:source || ''};
        var banner = byId('reconcile');
        if (banner) banner.hidden = false;
        root.querySelectorAll('[data-write]').forEach(function(button) { button.disabled = true; });
        setStatus('上次操作结果未确认。请先核对，不能重放。', 'error');
    }

    function clearUnresolved() {
        unresolved = null;
        var banner = byId('reconcile');
        if (banner) banner.hidden = true;
        if (snapshot) updateSnapshot();
    }

    function queryUnresolved() {
        if (!unresolved || busy) return;
        busy = true; setStatus('正在核对上次操作…');
        request('query', {v:1, token:unresolved.token, operationId:unresolved.operationId}, function(result) {
            busy = false;
            var normalized = Runtime.normalizeWrite(result, 'query', unresolved.token, unresolved.operationId);
            if (!normalized) {
                if (result && result.requiresReconcile) setStatus('核对仍未拿到确定结果，请稍后再试。', 'error');
                else setStatus('核对回包无法验证，请稍后再试。', 'error');
                return;
            }
            if (normalized.success) {
                clearUnresolved();
                setStatus(normalized.message || '上次操作已确认完成。', 'ok');
                loadSnapshot(false, true);
            } else if (normalized.error === 'not_applied') {
                clearUnresolved();
                setStatus('上次操作未执行。', 'ok');
                loadSnapshot(false, true);
            } else if (normalized.requiresReconcile || normalized.error === 'apply_ambiguous') {
                setStatus('上次操作仍无法确认，请保留现场并重启游戏。', 'error');
            } else {
                clearUnresolved();
                setStatus(messageFor(normalized.error), 'error');
                loadSnapshot(false, true);
            }
        });
    }

    function writeRequest(cmd, extra, closeOnSuccess) {
        if (!mux) return;
        if (unresolved) { setStatus('请先核对上次操作结果。', 'error'); return; }
        if (writeBusy) { setStatus('上一项写操作仍在处理中。', 'warn'); return; }
        var operationId = makeOperationId();
        var payload = {v:1, token:token, operationId:operationId, expectedRevision:revision};
        for (var key in extra) if (Object.prototype.hasOwnProperty.call(extra, key)) payload[key] = extra[key];
        writeBusy = true; closeAfterWrite = closeOnSuccess === true;
        root.querySelectorAll('[data-write]').forEach(function(button) { button.disabled = true; });
        setStatus('正在请求 AS2 执行…', 'pending');
        var issued = request(cmd, payload, function(result) {
            writeBusy = false;
            var normalized = Runtime.normalizeWrite(result, cmd, token, operationId);
            if (!normalized) {
                if (result && result.requiresReconcile && result.recoveryToken && result.recoveryOperationId) {
                    setUnresolved(result.recoveryToken, result.recoveryOperationId, cmd);
                } else if (result && result.clientSynthetic) {
                    setUnresolved(token, operationId, cmd);
                } else {
                    setStatus(messageFor(result && result.error), 'error');
                }
                updateSnapshot();
                return;
            }
            if (normalized.revision >= revision) revision = normalized.revision;
            if (normalized.success) {
                if (normalized.money !== undefined && snapshot) snapshot.state.money = normalized.money;
                if (normalized.kcoin !== undefined && snapshot) snapshot.state.kcoin = normalized.kcoin;
                if (snapshot) updateSnapshot();
                setStatus(normalized.message || '操作已完成。', 'ok');
                if (normalized.closeAfter && closeAfterWrite) { requestClose(); return; }
                loadSnapshot(false, true);
            } else if (normalized.requiresReconcile || normalized.error === 'apply_ambiguous') {
                setUnresolved(token, operationId, cmd);
                setStatus('写操作结果未确认，已冻结后续写。', 'error');
            } else {
                setStatus(messageFor(normalized.error), 'error');
                if (snapshot) updateSnapshot();
                if (normalized.error === 'stale_revision' || normalized.error === 'context_changed') loadSnapshot(false, true);
            }
        });
        if (issued == null) { writeBusy = false; setStatus('上一项请求仍在处理中。', 'warn'); updateSnapshot(); }
    }

    function loadItems() {
        if (!mux || itemLoading) return;
        itemLoading = true;
        var requestedPage = itemPage;
        var requestedQuery = itemQuery;
        setStatus('正在读取物品目录…', 'pending');
        request('items', {v:1, token:token, query:requestedQuery, page:requestedPage}, function(result) {
            itemLoading = false;
            var normalized = Runtime.normalizeItems(result, token);
            if (!normalized) { setStatus(messageFor(result && result.error) || '物品目录暂时不可用。', 'error'); return; }
            if (normalized.revision >= revision) revision = normalized.revision;
            itemQuery = normalized.query; itemPage = normalized.page; itemTotal = normalized.total;
            itemPageSize = normalized.pageSize;
            selectedItem = null;
            renderItems(normalized.items);
            renderItemPageState();
            renderItemDetail();
            setStatus('物品目录已更新。', 'ok');
        });
    }

    function searchItems() {
        itemQuery = byId('item-query').value.trim().slice(0, 64);
        itemPage = 1;
        loadItems();
    }

    function renderItems(items) {
        var grid = byId('item-grid');
        if (!grid) return;
        grid.textContent = '';
        if (!items.length) {
            var empty = document.createElement('p');
            empty.className = 'modifier-empty modifier-grid-empty';
            empty.textContent = '没有匹配的物品。';
            grid.appendChild(empty);
            return;
        }
        items.forEach(function(item) {
            var card = document.createElement('button');
            card.type = 'button';
            card.className = 'modifier-item-card';
            card.setAttribute('data-name', item.name);
            if (selectedItem && selectedItem.name === item.name) card.classList.add('selected');
            var image = document.createElement('img');
            image.alt = '';
            var url = window.Icons ? (Icons.resolveStatic(item.icon) || Icons.resolve(item.icon)) : null;
            if (url) {
                image.src = url;
                image.onerror = function() { image.remove(); card.classList.add('no-icon'); };
            } else {
                card.classList.add('no-icon');
            }
            var label = document.createElement('span');
            label.textContent = item.displayName;
            card.appendChild(image);
            card.appendChild(label);
            card.onclick = function() { selectedItem = item; renderItems(items); renderItemDetail(); };
            grid.appendChild(card);
        });
    }

    function renderItemPageState() {
        var pages = itemTotal > 0 ? Math.ceil(itemTotal / Math.max(1, itemPageSize)) : 0;
        text('item-page-state', itemTotal + ' 项 · ' + (pages ? itemPage + '/' + pages : '0/0'));
        var prev = byId('item-prev'), next = byId('item-next');
        if (prev) prev.disabled = itemPage <= 1;
        if (next) next.disabled = itemPage * itemPageSize >= itemTotal;
    }

    function renderItemDetail() {
        var detail = byId('item-detail');
        if (!detail) return;
        if (!selectedItem) {
            detail.innerHTML = '<p class="modifier-empty">选择一个物品查看生产选项。</p>';
            return;
        }
        detail.innerHTML = '';
        var eyebrow = document.createElement('p'); eyebrow.className = 'modifier-eyebrow'; eyebrow.textContent = '物品生产';
        var title = document.createElement('h2'); title.textContent = selectedItem.displayName;
        var meta = document.createElement('p'); meta.className = 'modifier-meta';
        meta.textContent = '#' + selectedItem.id + ' · ' + (selectedItem.type || '未分类') + ' · ' + (selectedItem.use || '—');
        var form = document.createElement('div'); form.className = 'modifier-inline-form';
        var quantity = document.createElement('input');
        quantity.id = 'modifier-item-quantity'; quantity.type = 'number'; quantity.min = '1';
        quantity.max = '999999999'; quantity.step = '1'; quantity.value = '1'; quantity.setAttribute('aria-label', '生产数量');
        var minus = document.createElement('button'); minus.type = 'button'; minus.className = 'modifier-button quiet'; minus.textContent = '−';
        var plus = document.createElement('button'); plus.type = 'button'; plus.className = 'modifier-button quiet'; plus.textContent = '+';
        minus.onclick = function() { quantity.value = String(Math.max(1, Number(quantity.value || 1) - 1)); };
        plus.onclick = function() { quantity.value = String(Math.min(999999999, Number(quantity.value || 1) + 1)); };
        var produce = document.createElement('button'); produce.type = 'button'; produce.className = 'modifier-button primary'; produce.setAttribute('data-write', '');
        produce.textContent = '生产'; produce.disabled = !!unresolved || writeBusy || !snapshot || !snapshot.state.saveAvailable || snapshot.state.challengeMode;
        produce.onclick = function() {
            var count = Number(quantity.value);
            if (!Runtime.int(count, 1, 999999999)) { setStatus('生产数量必须是 1–999999999 的整数。', 'error'); return; }
            writeRequest('spawnItem', {itemName:selectedItem.name, quantity:count});
        };
        form.appendChild(minus); form.appendChild(quantity); form.appendChild(plus); form.appendChild(produce);
        var note = document.createElement('p'); note.className = 'modifier-note';
        note.textContent = '生产会在角色位置生成可拾取物；关闭面板后拾取。材料数量上限按 AS2 现有集合规则校验。';
        detail.appendChild(eyebrow); detail.appendChild(title); detail.appendChild(meta); detail.appendChild(form); detail.appendChild(note);
    }

    function loadUnits() {
        if (!mux || unitLoading) return;
        unitLoading = true;
        var requestedPage = unitPage;
        var requestedQuery = unitQuery;
        setStatus('正在读取兵种目录…', 'pending');
        request('units', {v:1, token:token, query:requestedQuery, page:requestedPage}, function(result) {
            unitLoading = false;
            var normalized = Runtime.normalizeUnits(result, token);
            if (!normalized) { setStatus(messageFor(result && result.error) || '兵种目录暂时不可用。', 'error'); return; }
            if (normalized.revision >= revision) revision = normalized.revision;
            unitQuery = normalized.query; unitPage = normalized.page; unitTotal = normalized.total;
            unitPageSize = normalized.pageSize;
            selectedUnit = null;
            renderUnits(normalized.units);
            renderUnitPageState();
            renderUnitDetail();
            setStatus('兵种目录已更新。', 'ok');
        });
    }

    function searchUnits() {
        unitQuery = byId('unit-query').value.trim().slice(0, 64);
        unitPage = 1;
        loadUnits();
    }

    function renderUnits(units) {
        var grid = byId('unit-grid');
        if (!grid) return;
        grid.textContent = '';
        if (!units.length) {
            var empty = document.createElement('p');
            empty.className = 'modifier-empty modifier-grid-empty';
            empty.textContent = '没有匹配的兵种。';
            grid.appendChild(empty);
            return;
        }
        units.forEach(function(unit) {
            var card = document.createElement('button');
            card.type = 'button';
            card.className = 'modifier-unit-card' + (unit.hostile ? ' hostile' : '');
            if (selectedUnit && selectedUnit.id === unit.id) card.classList.add('selected');
            var name = document.createElement('strong');
            name.textContent = unit.name || unit.spriteName;
            var sprite = document.createElement('span');
            sprite.textContent = unit.spriteName;
            var meta = document.createElement('small');
            meta.textContent = '#' + unit.id + ' · Lv.' + unit.level + ' · ' + (unit.hostile ? '敌' : '友');
            card.appendChild(name); card.appendChild(sprite); card.appendChild(meta);
            card.onclick = function() { selectedUnit = unit; renderUnits(units); renderUnitDetail(); };
            grid.appendChild(card);
        });
    }

    function renderUnitPageState() {
        var pages = unitTotal > 0 ? Math.ceil(unitTotal / Math.max(1, unitPageSize)) : 0;
        text('unit-page-state', unitTotal + ' 项 · ' + (pages ? unitPage + '/' + pages : '0/0'));
        var prev = byId('unit-prev'), next = byId('unit-next');
        if (prev) prev.disabled = unitPage <= 1;
        if (next) next.disabled = unitPage * unitPageSize >= unitTotal;
    }

    function renderUnitDetail() {
        var detail = byId('unit-detail');
        if (!detail) return;
        if (!selectedUnit) {
            detail.innerHTML = '<p class="modifier-empty">选择一个兵种查看生成选项。</p>';
            return;
        }
        detail.innerHTML = '';
        var eyebrow = document.createElement('p'); eyebrow.className = 'modifier-eyebrow'; eyebrow.textContent = '兵种生成';
        var title = document.createElement('h2'); title.textContent = selectedUnit.name || selectedUnit.spriteName;
        var meta = document.createElement('p'); meta.className = 'modifier-meta';
        meta.textContent = '#' + selectedUnit.id + ' · ' + selectedUnit.spriteName + (selectedUnit.key ? ' · ' + selectedUnit.key : '');
        var hostile = {value:selectedUnit.hostile};
        var hostileButton = document.createElement('button'); hostileButton.type = 'button'; hostileButton.className = 'modifier-button';
        function paintHostile() {
            hostileButton.textContent = hostile.value ? '敌我属性：敌人' : '敌我属性：友军';
            hostileButton.classList.toggle('danger', hostile.value);
        }
        paintHostile();
        hostileButton.onclick = function() { hostile.value = !hostile.value; paintHostile(); };

        var level = document.createElement('input');
        level.id = 'modifier-unit-level'; level.type = 'number'; level.min = '1'; level.max = '9999'; level.step = '1';
        level.value = String(Math.max(1, selectedUnit.level || 1)); level.setAttribute('aria-label', '生成等级');
        var count = document.createElement('input');
        count.id = 'modifier-unit-count'; count.type = 'number'; count.min = '1'; count.max = '100'; count.step = '1';
        count.value = '1'; count.setAttribute('aria-label', '生成数量');
        var levelRow = document.createElement('label'); levelRow.className = 'modifier-field'; levelRow.textContent = '等级'; levelRow.appendChild(level);
        var countRow = document.createElement('label'); countRow.className = 'modifier-field'; countRow.textContent = '数量'; countRow.appendChild(count);

        var spawnUnit = document.createElement('button'); spawnUnit.type = 'button'; spawnUnit.className = 'modifier-button primary';
        spawnUnit.setAttribute('data-write', ''); spawnUnit.textContent = '生成单位';
        spawnUnit.disabled = !!unresolved || writeBusy || !snapshot || !snapshot.state.saveAvailable || snapshot.state.challengeMode;
        spawnUnit.onclick = function() {
            var lv = Number(level.value), n = Number(count.value);
            if (!Runtime.int(lv, 1, 9999) || !Runtime.int(n, 1, 100)) { setStatus('等级需为 1–9999，数量需为 1–100。', 'error'); return; }
            writeRequest('spawnUnit', {unitId:selectedUnit.id, count:n, level:lv, hostile:hostile.value});
        };
        var spawnMerc = document.createElement('button'); spawnMerc.type = 'button'; spawnMerc.className = 'modifier-button';
        spawnMerc.setAttribute('data-write', ''); spawnMerc.textContent = '生成佣兵';
        spawnMerc.disabled = !!unresolved || writeBusy || !snapshot || !snapshot.state.saveAvailable || snapshot.state.challengeMode;
        spawnMerc.onclick = function() {
            var lv = Number(level.value);
            if (!Runtime.int(lv, 1, 9999)) { setStatus('等级需为 1–9999。', 'error'); return; }
            writeRequest('spawnMerc', {unitId:selectedUnit.id, level:lv, hostile:hostile.value});
        };
        var note = document.createElement('p'); note.className = 'modifier-note';
        note.textContent = '生成单位使用当前场景角色位置；生成佣兵会写入可雇佣兵池并需要保存。数量只作用于生成单位。';
        detail.appendChild(eyebrow); detail.appendChild(title); detail.appendChild(meta); detail.appendChild(hostileButton);
        detail.appendChild(levelRow); detail.appendChild(countRow);
        detail.appendChild(spawnUnit); detail.appendChild(spawnMerc); detail.appendChild(note);
    }

    function request(cmd, payload, callback) {
        if (!mux) return null;
        var scheduled = generation;
        var issued = mux.request(cmd, payload, function(result) {
            if (scheduled !== generation || phase === 'closed') return;
            callback(result || {});
        });
        return issued;
    }

    function makeOperationId() {
        opSequence++;
        return 'mod.' + Date.now().toString(36) + '.' + opSequence.toString(36) + '.'
            + Math.floor(Math.random() * 0x7fffffff).toString(36);
    }

    function arm(button, action) {
        if (button.getAttribute('data-armed') === '1') {
            button.setAttribute('data-armed', '0');
            button.textContent = button.getAttribute('data-label') || button.textContent;
            if (armTimer) { clearTimeout(armTimer); armTimer = 0; }
            action();
            return;
        }
        button.setAttribute('data-label', button.textContent);
        button.setAttribute('data-armed', '1');
        button.textContent = '再次点击确认';
        if (armTimer) clearTimeout(armTimer);
        armTimer = setTimeout(function() {
            armTimer = 0;
            button.setAttribute('data-armed', '0');
            if (button.getAttribute('data-label')) button.textContent = button.getAttribute('data-label');
        }, 3000);
    }

    function requestClose() {
        if (closing) return false;
        closing = true;
        var sent = false;
        try { sent = Bridge.send({type:'panel', panel:'modifier', cmd:'close', panelInstanceId:instance}) !== false; }
        catch (_) { sent = false; }
        if (!sent) { closing = false; setStatus('关闭请求未能发送，请再试一次。', 'error'); return false; }
        Panels.close();
        return true;
    }

    function cleanup() {
        generation++;
        phase = 'closed'; busy = false; writeBusy = false; closing = false;
        if (armTimer) { clearTimeout(armTimer); armTimer = 0; }
        if (mux) { mux.destroy(); mux = null; }
        if (scale) { scale.detach(); scale = null; }
        snapshot = null; unresolved = null; selectedItem = null; selectedUnit = null;
        instance = ''; token = ''; revision = 0;
        if (root) root.innerHTML = '';
        root = null; shell = null;
    }

    function messageFor(error) {
        var messages = {
            unsupported_domain:'修改器请求域无效。', unsupported_cmd:'修改器命令不受支持。',
            unsupported_version:'修改器协议版本不一致。', invalid_payload:'请求参数无效。',
            invalid_owner:'面板实例已失效，请关闭后重新打开。', disconnected:'游戏连接暂时不可用。',
            timeout:'AS2 未在时限内确认结果。', not_sent:'请求未能发送，请重试。',
            client_timeout:'AS2 未在时限内确认结果。', malformed_response:'回包无法验证，已冻结后续写。',
            reconcile_required:'请先核对上次操作结果。', apply_ambiguous:'操作结果未确认，请核对。',
            stale_token:'会话已失效，请关闭后重新打开。', stale_revision:'状态已变化，请刷新后重试。',
            context_changed:'场景或存档已切换，请重新打开修改器。',
            invalid_balance:'当前余额无法安全写入。', item_unavailable:'该物品不存在或不可生产。',
            quantity_overflow:'数量超过材料集合可安全写入的上限。', pickup_unavailable:'拾取物系统尚未就绪。',
            actor_unavailable:'当前角色不在场景中。', stage_unavailable:'当前没有可操作的关卡。',
            wave_unavailable:'当前没有可完成的波次。', task_unavailable:'任务数据或任务系统不可用。',
            unit_unavailable:'该兵种不可生成。', merc_pool_empty:'可雇佣兵池为空。',
            merc_pool_invalid:'可雇佣兵池条目结构异常。', spawn_unavailable:'单位生成函数尚未就绪。',
            spawn_failed:'单位生成失败。', navigation_unavailable:'场景转场尚未就绪。',
            not_allowed:'当前场景不允许该动作。', challenge_mode:'挑战模式中修改器写操作不可用。',
            save_unavailable:'存档系统尚未就绪。', not_applied:'上次操作未执行。'
        };
        return messages[error] || '操作未完成，请稍后重试。';
    }

    Panels.register('modifier', {
        create: create,
        onOpen: onOpen,
        onRebind: function(element, data) { cleanup(); onOpen(element, data); },
        onRequestClose: requestClose,
        onForceClose: cleanup,
        onClose: cleanup
    });
    window.ModifierPanel = {debugState:function() {
        return {phase:phase, busy:busy, writeBusy:writeBusy, revision:revision,
            unresolved:unresolved, selectedItem:selectedItem, selectedUnit:selectedUnit,
            itemPage:itemPage, unitPage:unitPage};
    }};
})();
