(function() {
    'use strict';

    var Runtime = window.ModifierRuntime;
    var shell, root, scale, mux, instance = '', token = '', generation = 0;
    var busy = false, writeBusy = false, activeTab = 'economy', phase = 'closed';
    var snapshot = null, unresolved = null, revision = 0;
    var selectedItem = null, selectedUnit = null;
    var itemQuery = '', itemPage = 1, itemTotal = 0, itemPageSize = 64, itemLoading = false;
    var unitQuery = '', unitPage = 1, unitTotal = 0, unitPageSize = 8, unitLoading = false;
    var closeAfterWrite = false, opSequence = 0, armTimer = 0, readySent = false;

    function byId(id) { return root ? root.querySelector('#mw-' + id) : null; }
    function text(id, value) { var node = byId(id); if (node) node.textContent = value; }
    function setStatus(value, tone) {
        var node = byId('message');
        if (node) { node.textContent = value || ''; node.setAttribute('data-tone', tone || 'neutral'); }
    }

    function skeleton() {
        return '<section class="mw-window" role="dialog" aria-label="修改器">'
            + '<header class="mw-titlebar">'
            + '<span class="mw-grip" aria-hidden="true"></span><span class="mw-title">修改器</span>'
            + '<nav class="mw-tabs" role="tablist" aria-label="修改器页面">'
            + '<button type="button" class="mw-tab" role="tab" data-tab="economy" aria-selected="true">经济</button>'
            + '<button type="button" class="mw-tab" role="tab" data-tab="items" aria-selected="false">物品</button>'
            + '<button type="button" class="mw-tab" role="tab" data-tab="level" aria-selected="false">关卡</button>'
            + '<button type="button" class="mw-tab" role="tab" data-tab="units" aria-selected="false">阵营</button>'
            + '</nav>'
            + '<button type="button" class="mw-close" id="mw-close" aria-label="关闭修改器">×</button>'
            + '</header>'
            + '<main class="mw-body">'
            + '<section class="mw-view" data-view="economy" role="tabpanel">'
            + '<div class="mw-economy">'
            + '<div class="mw-row"><span class="mw-label">金币</span><strong id="mw-money">—</strong>'
            + '<button type="button" class="mw-button" data-write data-economy="grantMoney">+100000</button></div>'
            + '<div class="mw-row"><span class="mw-label">虚拟币</span><strong id="mw-kcoin">—</strong>'
            + '<button type="button" class="mw-button" data-write data-economy="grantKCoin">+100000</button></div>'
            + '<p class="mw-hint">写操作沿用 AS2 现有 dirty/保存语义。</p>'
            + '<button type="button" class="mw-button danger" data-write data-level-action="test_space">前往测试空间</button>'
            + '</div></section>'
            + '<section class="mw-view" data-view="items" role="tabpanel" hidden>'
            + '<div class="mw-toolbar"><input id="mw-item-query" type="search" maxlength="64" autocomplete="off" placeholder="id / 名称 / 类型 / 用途">'
            + '<button type="button" class="mw-button" id="mw-item-search">搜索</button>'
            + '<button type="button" class="mw-button quiet" id="mw-item-clear">清空</button>'
            + '<span class="mw-page-state" id="mw-item-page-state">—</span></div>'
            + '<div class="mw-split"><div class="mw-grid-wrap"><div class="mw-item-grid" id="mw-item-grid"></div>'
            + '<div class="mw-page-row"><button type="button" class="mw-button" id="mw-item-prev">上一页</button>'
            + '<button type="button" class="mw-button" id="mw-item-next">下一页</button></div></div>'
            + '<aside class="mw-detail" id="mw-item-detail"><p class="mw-empty">选择物品</p></aside></div></section>'
            + '<section class="mw-view" data-view="level" role="tabpanel" hidden>'
            + '<div class="mw-level"><div class="mw-button-grid">'
            + '<button type="button" class="mw-button" data-write data-level-action="unlock_stages">解锁关卡</button>'
            + '<button type="button" class="mw-button" data-write data-level-action="kill_all">敌人全死</button>'
            + '<button type="button" class="mw-button" data-write data-level-action="finish_wave">完成当前波次</button>'
            + '<button type="button" class="mw-button" data-write data-level-action="finish_map">完成当前地图</button>'
            + '<button type="button" class="mw-button danger" data-write data-level-action="finish_stage">结算关卡</button>'
            + '<button type="button" class="mw-button danger" data-write data-level-action="test_space">测试空间</button>'
            + '</div><div class="mw-task"><label for="mw-task-id">主线任务</label>'
            + '<input id="mw-task-id" type="number" min="1" max="999" step="1" value="1">'
            + '<button type="button" class="mw-button primary" data-write id="mw-grant-task">获得任务</button></div></div></section>'
            + '<section class="mw-view" data-view="units" role="tabpanel" hidden>'
            + '<div class="mw-toolbar"><input id="mw-unit-query" type="search" maxlength="64" autocomplete="off" placeholder="id / 单位名 / 兵种名 / key">'
            + '<button type="button" class="mw-button" id="mw-unit-search">搜索</button>'
            + '<button type="button" class="mw-button quiet" id="mw-unit-clear">清空</button>'
            + '<span class="mw-page-state" id="mw-unit-page-state">—</span></div>'
            + '<div class="mw-split"><div class="mw-grid-wrap"><div class="mw-unit-grid" id="mw-unit-grid"></div>'
            + '<div class="mw-page-row"><button type="button" class="mw-button" id="mw-unit-prev">上一页</button>'
            + '<button type="button" class="mw-button" id="mw-unit-next">下一页</button></div></div>'
            + '<aside class="mw-detail" id="mw-unit-detail"><p class="mw-empty">选择兵种</p></aside></div></section>'
            + '</main>'
            + '<footer class="mw-footer"><p id="mw-message" role="status" aria-live="polite"></p>'
            + '<div class="mw-reconcile" id="mw-reconcile" hidden><span>结果未确认</span>'
            + '<button type="button" class="mw-button" id="mw-reconcile-query">核对</button></div></footer>'
            + '</section>';
    }

    function init() {
        shell = document.getElementById('modifier-window-shell');
        if (!shell) return;
        shell.innerHTML = skeleton();
        root = shell;
        scale = window.PanelScale.attach(shell, 550, 400);
        bind();
        if (window.Icons) Icons.load(function() { if (itemTotal) loadItems(); });
        shell.style.display = 'none';
        Bridge.on('panel_cmd', onPanelCommand);
        if (document.readyState === 'complete') sendReady();
        else window.addEventListener('load', sendReady);
    }

    function sendReady() {
        if (readySent) return;
        readySent = true;
        Bridge.send({type:'composition_modifier_ready'});
    }

    function onPanelCommand(data) {
        if (!data || data.panel !== 'modifier') return;
        if (data.cmd === 'open' && data.initData
            && typeof data.initData.panelInstanceId === 'string'
            && typeof data.initData.token === 'string') {
            openWindow(data.initData);
            return;
        }
        if (data.cmd === 'close' || data.cmd === 'force_close') cleanup();
    }

    function openWindow(data) {
        generation++;
        instance = data.panelInstanceId;
        token = data.token;
        busy = false; writeBusy = false; phase = 'loading';
        snapshot = null; unresolved = null; revision = 0;
        selectedItem = null; selectedUnit = null;
        itemQuery = ''; itemPage = 1; itemTotal = 0; itemLoading = false;
        unitQuery = ''; unitPage = 1; unitTotal = 0; unitLoading = false;
        closeAfterWrite = false; opSequence = 0; activeTab = 'economy';
        shell.style.display = '';
        if (mux) { mux.destroy(); mux = null; }
        mux = new Runtime.RequestMux({send:function(message) { return Bridge.send(message); }, panelInstanceId:instance});
        showTab(activeTab, false);
        loadSnapshot(true);
    }

    function cleanup() {
        generation++;
        phase = 'closed'; busy = false; writeBusy = false;
        if (armTimer) { clearTimeout(armTimer); armTimer = 0; }
        if (mux) { mux.destroy(); mux = null; }
        snapshot = null; unresolved = null; selectedItem = null; selectedUnit = null;
        instance = ''; token = ''; revision = 0;
        if (shell) shell.style.display = 'none';
    }

    function bind() {
        byId('close').onclick = requestClose;
        root.querySelectorAll('.mw-tab').forEach(function(tab) {
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
        byId('item-search').onclick = searchItems;
        byId('item-clear').onclick = function() { byId('item-query').value = ''; searchItems(); };
        byId('item-query').addEventListener('keydown', function(event) {
            if (event.key === 'Enter') { event.preventDefault(); searchItems(); }
        });
        byId('item-prev').onclick = function() { if (itemPage > 1) { itemPage--; loadItems(); } };
        byId('item-next').onclick = function() { if (itemPage * itemPageSize < itemTotal) { itemPage++; loadItems(); } };
        byId('unit-search').onclick = searchUnits;
        byId('unit-clear').onclick = function() { byId('unit-query').value = ''; searchUnits(); };
        byId('unit-query').addEventListener('keydown', function(event) {
            if (event.key === 'Enter') { event.preventDefault(); searchUnits(); }
        });
        byId('unit-prev').onclick = function() { if (unitPage > 1) { unitPage--; loadUnits(); } };
        byId('unit-next').onclick = function() { if (unitPage * unitPageSize < unitTotal) { unitPage++; loadUnits(); } };
        byId('reconcile-query').onclick = queryUnresolved;
    }

    function showTab(tab, load) {
        activeTab = tab;
        root.querySelectorAll('.mw-tab').forEach(function(button) {
            button.setAttribute('aria-selected', String(button.getAttribute('data-tab') === tab));
        });
        root.querySelectorAll('.mw-view').forEach(function(view) {
            view.hidden = view.getAttribute('data-view') !== tab;
        });
        if (load === false) return;
        if (tab === 'items' && !itemTotal) loadItems();
        if (tab === 'units' && !unitTotal) loadUnits();
    }

    function loadSnapshot(initial) {
        if (!mux) return;
        if (initial) setStatus('正在读取…', 'pending');
        request('snapshot', {v:1, token:token}, function(result) {
            var state = Runtime.normalizeSnapshot(result, token);
            if (!state) {
                if (result && result.requiresReconcile && result.recoveryToken)
                    setUnresolved(result.recoveryToken, result.recoveryOperationId);
                if (initial) setStatus(messageFor(result && result.error) || '状态不可用。', 'error');
                return;
            }
            if (state.revision < revision) return;
            snapshot = state;
            revision = state.revision;
            if (result.requiresReconcile && result.recoveryToken) setUnresolved(result.recoveryToken, result.recoveryOperationId);
            else clearUnresolved();
            updateSnapshot();
            if (!initial) setStatus('状态已刷新。', 'ok');
        });
    }

    function updateSnapshot() {
        if (!snapshot) return;
        var state = snapshot.state;
        text('money', state.money.toLocaleString('zh-CN'));
        text('kcoin', state.kcoin.toLocaleString('zh-CN'));
        var canWrite = !state.challengeMode && state.saveAvailable;
        root.querySelectorAll('[data-write]').forEach(function(button) {
            button.disabled = !canWrite || !!unresolved || writeBusy;
        });
        if (state.challengeMode) setStatus('挑战模式中写操作不可用。', 'error');
        else if (!state.saveAvailable) setStatus('存档系统尚未就绪。', 'error');
    }

    function setUnresolved(recoveryToken, recoveryOperationId) {
        if (!recoveryToken || !recoveryOperationId) {
            setStatus('缺少恢复身份，请重启游戏。', 'error');
            return;
        }
        unresolved = {token:recoveryToken, operationId:recoveryOperationId};
        var banner = byId('reconcile');
        if (banner) banner.hidden = false;
        root.querySelectorAll('[data-write]').forEach(function(button) { button.disabled = true; });
        setStatus('上次操作结果未确认，请先核对。', 'error');
    }

    function clearUnresolved() {
        unresolved = null;
        var banner = byId('reconcile');
        if (banner) banner.hidden = true;
        if (snapshot) updateSnapshot();
    }

    function queryUnresolved() {
        if (!unresolved || busy) return;
        busy = true; setStatus('正在核对…', 'pending');
        request('query', {v:1, token:unresolved.token, operationId:unresolved.operationId}, function(result) {
            busy = false;
            var normalized = Runtime.normalizeWrite(result, 'query', unresolved.token, unresolved.operationId);
            if (!normalized) { setStatus('核对未拿到确定结果。', 'error'); return; }
            if (normalized.success || normalized.error === 'not_applied') {
                clearUnresolved();
                setStatus(normalized.success ? (normalized.message || '已确认完成。') : '上次操作未执行。', 'ok');
                loadSnapshot(false);
            } else if (normalized.requiresReconcile || normalized.error === 'apply_ambiguous') {
                setStatus('仍无法确认，请保留现场并重启。', 'error');
            } else {
                clearUnresolved();
                setStatus(messageFor(normalized.error), 'error');
                loadSnapshot(false);
            }
        });
    }

    function writeRequest(cmd, extra, closeOnSuccess) {
        if (!mux) return;
        if (unresolved) { setStatus('请先核对上次操作。', 'error'); return; }
        if (writeBusy) { setStatus('上一项写操作仍在处理中。', 'warn'); return; }
        var operationId = makeOperationId();
        var payload = {v:1, token:token, operationId:operationId, expectedRevision:revision};
        for (var key in extra) if (Object.prototype.hasOwnProperty.call(extra, key)) payload[key] = extra[key];
        writeBusy = true; closeAfterWrite = closeOnSuccess === true;
        root.querySelectorAll('[data-write]').forEach(function(button) { button.disabled = true; });
        setStatus('正在请求 AS2…', 'pending');
        var issued = request(cmd, payload, function(result) {
            writeBusy = false;
            var normalized = Runtime.normalizeWrite(result, cmd, token, operationId);
            if (!normalized) {
                if (result && result.requiresReconcile && result.recoveryToken && result.recoveryOperationId)
                    setUnresolved(result.recoveryToken, result.recoveryOperationId);
                else if (result && result.clientSynthetic) setUnresolved(token, operationId);
                else setStatus(messageFor(result && result.error), 'error');
                updateSnapshot();
                return;
            }
            if (normalized.revision >= revision) revision = normalized.revision;
            if (normalized.success) {
                if (normalized.money !== undefined && snapshot) snapshot.state.money = normalized.money;
                if (normalized.kcoin !== undefined && snapshot) snapshot.state.kcoin = normalized.kcoin;
                if (snapshot) updateSnapshot();
                setStatus(normalized.message || '已完成。', 'ok');
                if (normalized.closeAfter && closeAfterWrite) { requestClose(); return; }
                loadSnapshot(false);
            } else if (normalized.requiresReconcile || normalized.error === 'apply_ambiguous') {
                setUnresolved(token, operationId);
                setStatus('写操作结果未确认，已冻结后续写。', 'error');
            } else {
                setStatus(messageFor(normalized.error), 'error');
                if (snapshot) updateSnapshot();
                if (normalized.error === 'stale_revision' || normalized.error === 'context_changed') loadSnapshot(false);
            }
        });
        if (issued == null) { writeBusy = false; setStatus('上一项请求仍在处理中。', 'warn'); updateSnapshot(); }
    }

    function loadItems() {
        if (!mux || itemLoading) return;
        itemLoading = true;
        var page = itemPage, query = itemQuery;
        setStatus('正在读取物品目录…', 'pending');
        request('items', {v:1, token:token, query:query, page:page}, function(result) {
            itemLoading = false;
            var normalized = Runtime.normalizeItems(result, token);
            if (!normalized) { setStatus(messageFor(result && result.error) || '物品目录不可用。', 'error'); return; }
            if (normalized.revision >= revision) revision = normalized.revision;
            itemQuery = normalized.query; itemPage = normalized.page; itemTotal = normalized.total;
            itemPageSize = normalized.pageSize; selectedItem = null;
            renderItems(normalized.items); renderItemPageState(); renderItemDetail();
            setStatus('物品目录已更新。', 'ok');
        });
    }

    function searchItems() {
        itemQuery = byId('item-query').value.trim().slice(0, 64);
        itemPage = 1; loadItems();
    }

    function renderItems(items) {
        var grid = byId('item-grid');
        if (!grid) return;
        grid.textContent = '';
        if (!items.length) {
            var empty = document.createElement('p');
            empty.className = 'mw-empty';
            empty.textContent = '没有匹配物品。';
            grid.appendChild(empty);
            return;
        }
        items.forEach(function(item) {
            var card = document.createElement('button');
            card.type = 'button';
            card.className = 'mw-item-card';
            card.setAttribute('aria-label', item.displayName);
            card.setAttribute('data-name', item.name);
            if (selectedItem && selectedItem.name === item.name) card.classList.add('selected');
            var url = window.Icons ? (Icons.resolveStatic(item.icon) || Icons.resolve(item.icon)) : null;
            if (url) {
                var image = document.createElement('img');
                image.alt = ''; image.src = url;
                image.onerror = function() { image.remove(); card.classList.add('no-icon'); };
                card.appendChild(image);
            } else {
                card.classList.add('no-icon');
            }
            card.onclick = function() { selectedItem = item; renderItems(items); renderItemDetail(); };
            grid.appendChild(card);
        });
    }

    function renderItemPageState() {
        var pages = itemTotal > 0 ? Math.ceil(itemTotal / Math.max(1, itemPageSize)) : 0;
        text('item-page-state', itemTotal + ' · ' + (pages ? itemPage + '/' + pages : '0/0'));
        var prev = byId('item-prev'), next = byId('item-next');
        if (prev) prev.disabled = itemPage <= 1;
        if (next) next.disabled = itemPage * itemPageSize >= itemTotal;
    }

    function renderItemDetail() {
        var detail = byId('item-detail');
        if (!detail) return;
        if (!selectedItem) { detail.innerHTML = '<p class="mw-empty">选择物品</p>'; return; }
        detail.innerHTML = '';
        var title = document.createElement('h2'); title.textContent = selectedItem.displayName;
        var meta = document.createElement('p'); meta.className = 'mw-meta';
        meta.textContent = '#' + selectedItem.id + ' · ' + (selectedItem.type || '—') + ' · ' + (selectedItem.use || '—');
        var row = document.createElement('div'); row.className = 'mw-inline';
        var quantity = document.createElement('input');
        quantity.id = 'mw-item-quantity'; quantity.type = 'number'; quantity.min = '1';
        quantity.max = '999999999'; quantity.step = '1'; quantity.value = '1';
        var minus = document.createElement('button'); minus.type = 'button'; minus.className = 'mw-button quiet'; minus.textContent = '−';
        var plus = document.createElement('button'); plus.type = 'button'; plus.className = 'mw-button quiet'; plus.textContent = '+';
        minus.onclick = function() { quantity.value = String(Math.max(1, Number(quantity.value || 1) - 1)); };
        plus.onclick = function() { quantity.value = String(Math.min(999999999, Number(quantity.value || 1) + 1)); };
        var produce = document.createElement('button'); produce.type = 'button'; produce.className = 'mw-button primary';
        produce.setAttribute('data-write', ''); produce.textContent = '生产';
        produce.disabled = !!unresolved || writeBusy || !snapshot || !snapshot.state.saveAvailable || snapshot.state.challengeMode;
        produce.onclick = function() {
            var count = Number(quantity.value);
            if (!Runtime.int(count, 1, 999999999)) { setStatus('数量需为 1–999999999。', 'error'); return; }
            writeRequest('spawnItem', {itemName:selectedItem.name, quantity:count});
        };
        row.appendChild(minus); row.appendChild(quantity); row.appendChild(plus); row.appendChild(produce);
        var note = document.createElement('p'); note.className = 'mw-note';
        note.textContent = '在角色位置生成可拾取物；关闭后拾取。';
        detail.appendChild(title); detail.appendChild(meta); detail.appendChild(row); detail.appendChild(note);
    }

    function loadUnits() {
        if (!mux || unitLoading) return;
        unitLoading = true;
        var page = unitPage, query = unitQuery;
        setStatus('正在读取兵种目录…', 'pending');
        request('units', {v:1, token:token, query:query, page:page}, function(result) {
            unitLoading = false;
            var normalized = Runtime.normalizeUnits(result, token);
            if (!normalized) { setStatus(messageFor(result && result.error) || '兵种目录不可用。', 'error'); return; }
            if (normalized.revision >= revision) revision = normalized.revision;
            unitQuery = normalized.query; unitPage = normalized.page; unitTotal = normalized.total;
            unitPageSize = normalized.pageSize; selectedUnit = null;
            renderUnits(normalized.units); renderUnitPageState(); renderUnitDetail();
            setStatus('兵种目录已更新。', 'ok');
        });
    }

    function searchUnits() {
        unitQuery = byId('unit-query').value.trim().slice(0, 64);
        unitPage = 1; loadUnits();
    }

    function renderUnits(units) {
        var grid = byId('unit-grid');
        if (!grid) return;
        grid.textContent = '';
        if (!units.length) {
            var empty = document.createElement('p'); empty.className = 'mw-empty'; empty.textContent = '没有匹配兵种。';
            grid.appendChild(empty); return;
        }
        units.forEach(function(unit) {
            var card = document.createElement('button'); card.type = 'button';
            card.className = 'mw-unit-row' + (unit.hostile ? ' hostile' : '');
            if (selectedUnit && selectedUnit.id === unit.id) card.classList.add('selected');
            var name = document.createElement('strong'); name.textContent = unit.name || unit.spriteName;
            var meta = document.createElement('span'); meta.textContent = unit.spriteName + ' · ' + unit.level + ' · ' + (unit.hostile ? '敌' : '友');
            card.appendChild(name); card.appendChild(meta);
            card.onclick = function() { selectedUnit = unit; renderUnits(units); renderUnitDetail(); };
            grid.appendChild(card);
        });
    }

    function renderUnitPageState() {
        var pages = unitTotal > 0 ? Math.ceil(unitTotal / Math.max(1, unitPageSize)) : 0;
        text('unit-page-state', unitTotal + ' · ' + (pages ? unitPage + '/' + pages : '0/0'));
        var prev = byId('unit-prev'), next = byId('unit-next');
        if (prev) prev.disabled = unitPage <= 1;
        if (next) next.disabled = unitPage * unitPageSize >= unitTotal;
    }

    function renderUnitDetail() {
        var detail = byId('unit-detail');
        if (!detail) return;
        if (!selectedUnit) { detail.innerHTML = '<p class="mw-empty">选择兵种</p>'; return; }
        detail.innerHTML = '';
        var title = document.createElement('h2'); title.textContent = selectedUnit.name || selectedUnit.spriteName;
        var meta = document.createElement('p'); meta.className = 'mw-meta';
        meta.textContent = '#' + selectedUnit.id + ' · ' + selectedUnit.spriteName;
        var hostile = {value:selectedUnit.hostile};
        var hostileButton = document.createElement('button'); hostileButton.type = 'button'; hostileButton.className = 'mw-button';
        function paint() { hostileButton.textContent = hostile.value ? '敌我：敌人' : '敌我：友军'; hostileButton.classList.toggle('danger', hostile.value); }
        paint(); hostileButton.onclick = function() { hostile.value = !hostile.value; paint(); };
        var level = document.createElement('input'); level.id = 'mw-unit-level'; level.type = 'number'; level.min = '1'; level.max = '9999'; level.step = '1';
        level.value = String(Math.max(1, selectedUnit.level || 1));
        var count = document.createElement('input'); count.id = 'mw-unit-count'; count.type = 'number'; count.min = '1'; count.max = '100'; count.step = '1'; count.value = '1';
        var levelRow = document.createElement('label'); levelRow.className = 'mw-field'; levelRow.textContent = '等级'; levelRow.appendChild(level);
        var countRow = document.createElement('label'); countRow.className = 'mw-field'; countRow.textContent = '数量'; countRow.appendChild(count);
        var spawn = document.createElement('button'); spawn.type = 'button'; spawn.className = 'mw-button primary'; spawn.setAttribute('data-write', ''); spawn.textContent = '生成单位';
        spawn.disabled = !!unresolved || writeBusy || !snapshot || !snapshot.state.saveAvailable || snapshot.state.challengeMode;
        spawn.onclick = function() {
            var lv = Number(level.value), n = Number(count.value);
            if (!Runtime.int(lv, 1, 9999) || !Runtime.int(n, 1, 100)) { setStatus('等级 1–9999，数量 1–100。', 'error'); return; }
            writeRequest('spawnUnit', {unitId:selectedUnit.id, count:n, level:lv, hostile:hostile.value});
        };
        var merc = document.createElement('button'); merc.type = 'button'; merc.className = 'mw-button'; merc.setAttribute('data-write', ''); merc.textContent = '生成佣兵';
        merc.disabled = spawn.disabled;
        merc.onclick = function() {
            var lv = Number(level.value);
            if (!Runtime.int(lv, 1, 9999)) { setStatus('等级 1–9999。', 'error'); return; }
            writeRequest('spawnMerc', {unitId:selectedUnit.id, level:lv, hostile:hostile.value});
        };
        var note = document.createElement('p'); note.className = 'mw-note'; note.textContent = '数量只作用于生成单位；佣兵会写入雇佣池。';
        detail.appendChild(title); detail.appendChild(meta); detail.appendChild(hostileButton);
        detail.appendChild(levelRow); detail.appendChild(countRow); detail.appendChild(spawn); detail.appendChild(merc); detail.appendChild(note);
    }

    function request(cmd, payload, callback) {
        if (!mux) return null;
        var scheduled = generation;
        return mux.request(cmd, payload, function(result) {
            if (scheduled !== generation || phase === 'closed') return;
            callback(result || {});
        });
    }

    function makeOperationId() {
        opSequence++;
        return 'mod.' + Date.now().toString(36) + '.' + opSequence.toString(36) + '.' + Math.floor(Math.random() * 0x7fffffff).toString(36);
    }

    function arm(button, action) {
        if (button.getAttribute('data-armed') === '1') {
            button.setAttribute('data-armed', '0');
            button.textContent = button.getAttribute('data-label') || button.textContent;
            if (armTimer) { clearTimeout(armTimer); armTimer = 0; }
            action(); return;
        }
        button.setAttribute('data-label', button.textContent);
        button.setAttribute('data-armed', '1');
        button.textContent = '再次点击确认';
        if (armTimer) clearTimeout(armTimer);
        armTimer = setTimeout(function() {
            armTimer = 0; button.setAttribute('data-armed', '0');
            if (button.getAttribute('data-label')) button.textContent = button.getAttribute('data-label');
        }, 3000);
    }

    function requestClose() {
        if (!instance) { cleanup(); return false; }
        var sent = false;
        try { sent = Bridge.send({type:'panel', panel:'modifier', cmd:'close', panelInstanceId:instance}) !== false; }
        catch (_) { sent = false; }
        if (!sent) { setStatus('关闭请求未能发送。', 'error'); return false; }
        cleanup();
        return true;
    }

    function messageFor(error) {
        var messages = {
            unsupported_domain:'请求域无效。', unsupported_cmd:'命令不受支持。', unsupported_version:'协议版本不一致。',
            invalid_payload:'参数无效。', invalid_owner:'面板实例已失效。', disconnected:'游戏连接不可用。',
            timeout:'AS2 未在时限内确认。', not_sent:'请求未能发送。', client_timeout:'AS2 未在时限内确认。',
            malformed_response:'回包无法验证。', reconcile_required:'请先核对上次操作。', apply_ambiguous:'结果未确认。',
            stale_token:'会话已失效。', stale_revision:'状态已变化，请刷新。', context_changed:'场景或存档已切换。',
            invalid_balance:'余额无法安全写入。', item_unavailable:'物品不可生产。', quantity_overflow:'数量超过上限。',
            pickup_unavailable:'拾取物系统未就绪。', actor_unavailable:'角色不在场景。', stage_unavailable:'没有可操作关卡。',
            wave_unavailable:'没有可完成波次。', task_unavailable:'任务系统不可用。', unit_unavailable:'兵种不可生成。',
            merc_pool_empty:'雇佣池为空。', merc_pool_invalid:'雇佣池结构异常。', spawn_unavailable:'生成函数未就绪。',
            spawn_failed:'生成失败。', navigation_unavailable:'场景转场未就绪。', not_allowed:'当前场景不允许。',
            challenge_mode:'挑战模式不可写。', save_unavailable:'存档系统未就绪。', not_applied:'上次操作未执行。'
        };
        return messages[error] || '操作未完成。';
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
    else init();
})();
