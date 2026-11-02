(function() {
    'use strict';

    var Runtime = window.ModifierRuntime;
    var shell, root, scale, mux, instance = '', token = '', generation = 0;
    var busy = false, writeBusy = false, activeTab = 'economy', phase = 'closed';
    var snapshot = null, unresolved = null, revision = 0;
    var selectedItem = null, selectedUnit = null;
    var itemQuery = '', itemPage = 1, itemTotal = 0, itemPageSize = 64, itemLoading = false;
    var unitQuery = '', unitPage = 1, unitTotal = 0, unitPageSize = 8, unitLoading = false;
    var closeAfterWrite = false, opSequence = 0, armTimer = 0, readySent = false, tabAudio = null, itemTip = null, unitFrames = {};
    var unitFrameCache = {}, unitFrameLoading = {}, tooltipCache = {}, tooltipLoading = {}, lastTipEvent = null, lastTipName = '';

    function byId(id) { return root ? root.querySelector('#mw-' + id) : null; }
    function playTabSound() {
        try {
            if (!tabAudio) { tabAudio = new Audio('assets/modifier/tab-click.wav?v=20261102b'); tabAudio.preload = 'auto'; tabAudio.volume = 0.9; }
            tabAudio.currentTime = 0;
            var played = tabAudio.play();
            if (played && played.catch) played.catch(function() {});
        } catch (error) { }
    }
    function text(id, value) { var node = byId(id); if (node) node.textContent = value; }
    function setStatus(value, tone) {
        var node = byId('message');
        if (node) { node.textContent = value || ''; node.setAttribute('data-tone', tone || 'neutral'); }
    }

    function skeleton() {
        return '<section class="mw-window" data-tab="economy" role="dialog" aria-label="修改器">'
            + '<nav class="mw-tabs" role="tablist" aria-label="修改器页面">'
            + '<button type="button" class="mw-tab" role="tab" data-tab="economy" aria-selected="true"><span class="mw-sr">经济</span></button>'
            + '<button type="button" class="mw-tab" role="tab" data-tab="items" aria-selected="false"><span class="mw-sr">物品</span></button>'
            + '<button type="button" class="mw-tab" role="tab" data-tab="level" aria-selected="false"><span class="mw-sr">关卡</span></button>'
            + '<button type="button" class="mw-tab" role="tab" data-tab="units" aria-selected="false"><span class="mw-sr">兵种</span></button>'
            + '</nav>'
            + '<button type="button" class="mw-close" id="mw-close" aria-label="关闭修改器"></button>'
            + '<section class="mw-view" data-view="economy" role="tabpanel">'
            + '<button type="button" class="mw-hit mw-eco-money" data-write data-economy="grantMoney" aria-label="+10万金币"></button>'
            + '<button type="button" class="mw-hit mw-eco-kcoin" data-write data-economy="grantKCoin" aria-label="+10万K点"></button>'
            + '<button type="button" class="mw-hit mw-eco-map" data-write data-level-action="test_space" aria-label="测试用地图"></button>'
            + '<span class="mw-aux" aria-hidden="true"><span id="mw-money"></span><span id="mw-kcoin"></span></span>'
            + '</section>'
            + '<section class="mw-view" data-view="items" role="tabpanel" hidden>'
            + '<button type="button" class="mw-hit mw-item-first" id="mw-item-first" aria-label="第一页"></button>'
            + '<button type="button" class="mw-hit mw-item-prev" id="mw-item-prev" aria-label="上一页"></button>'
            + '<button type="button" class="mw-hit mw-item-next" id="mw-item-next" aria-label="下一页"></button>'
            + '<button type="button" class="mw-hit mw-item-last" id="mw-item-last" aria-label="最后一页"></button>'
            + '<div class="mw-item-grid" id="mw-item-grid"></div>'
            + '<div class="mw-item-tip" id="mw-item-tip" hidden></div>'
            + '<input class="mw-input mw-item-query" id="mw-item-query" type="search" maxlength="64" autocomplete="off">'
            + '<input class="mw-input mw-item-quantity" id="mw-item-quantity" type="number" min="1" max="999999999" step="1" value="1">'
            + '<button type="button" class="mw-hit mw-item-minus" id="mw-item-minus" aria-label="减少数量"></button>'
            + '<button type="button" class="mw-hit mw-item-plus" id="mw-item-plus" aria-label="增加数量"></button>'
            + '<button type="button" class="mw-hit mw-item-produce" id="mw-item-produce" data-write data-requires="item" aria-label="生产"></button>'
            + '<button type="button" class="mw-hit mw-item-search" id="mw-item-search" aria-label="搜索"></button>'
            + '<span class="mw-page-state mw-item-page-state" id="mw-item-page-state"></span>'
            + '</section>'
            + '<section class="mw-view" data-view="level" role="tabpanel" hidden>'
            + '<button type="button" class="mw-hit mw-lv-kill" data-write data-level-action="kill_all" aria-label="敌人全死"></button>'
            + '<button type="button" class="mw-hit mw-lv-wave" data-write data-level-action="finish_wave" aria-label="直接跳波"></button>'
            + '<button type="button" class="mw-hit mw-lv-map" data-write data-level-action="finish_map" aria-label="直接过图"></button>'
            + '<button type="button" class="mw-hit mw-lv-stage" data-write data-level-action="finish_stage" aria-label="直接过关"></button>'
            + '<input class="mw-input mw-task-input" id="mw-task-id" type="number" min="1" max="999" step="1" value="1">'
            + '<button type="button" class="mw-hit mw-lv-task" data-write id="mw-grant-task" aria-label="获得对应ID任务"></button>'
            + '<button type="button" class="mw-hit mw-lv-unlock" data-write data-level-action="unlock_stages" aria-label="解锁关卡"></button>'
            + '</section>'
            + '<section class="mw-view" data-view="units" role="tabpanel" hidden>'
            + '<input id="mw-unit-query" type="hidden" value="">'
            + '<button type="button" class="mw-hit mw-unit-first" id="mw-unit-first" aria-label="第一页"></button>'
            + '<button type="button" class="mw-hit mw-unit-prev" id="mw-unit-prev" aria-label="上一页"></button>'
            + '<button type="button" class="mw-hit mw-unit-next" id="mw-unit-next" aria-label="下一页"></button>'
            + '<button type="button" class="mw-hit mw-unit-last" id="mw-unit-last" aria-label="最后一页"></button>'
            + '<div class="mw-unit-grid" id="mw-unit-grid"></div>'
            + '<span class="mw-page-state mw-unit-page-state" id="mw-unit-page-state"></span>'
            + '<div class="mw-unit-frame" aria-hidden="true"></div>'
            + '<div class="mw-unit-preview" id="mw-unit-preview"></div>'
            + '<input class="mw-input mw-unit-level" id="mw-unit-level" type="number" min="1" max="9999" step="1" value="1">'
            + '<input class="mw-input mw-unit-count" id="mw-unit-count" type="number" min="1" max="100" step="1" value="1">'
            + '<button type="button" class="mw-hit mw-unit-level-minus" id="mw-unit-level-minus" aria-label="降低等级"></button>'
            + '<button type="button" class="mw-hit mw-unit-level-plus" id="mw-unit-level-plus" aria-label="提高等级"></button>'
            + '<button type="button" class="mw-hit mw-unit-count-minus" id="mw-unit-count-minus" aria-label="减少数量"></button>'
            + '<button type="button" class="mw-hit mw-unit-count-plus" id="mw-unit-count-plus" aria-label="增加数量"></button>'
            + '<input class="mw-unit-hostile" id="mw-unit-hostile" type="checkbox">'
            + '<button type="button" class="mw-hit mw-unit-spawn" id="mw-unit-spawn" data-write data-requires="unit" aria-label="加载兵种"></button>'
            + '<button type="button" class="mw-hit mw-unit-merc" id="mw-unit-merc" data-write data-requires="unit" aria-label="添加佣兵"></button>'
            + '</section>'
            + '<footer class="mw-status"><p id="mw-message" role="status" aria-live="polite"></p>'
            + '<div class="mw-reconcile" id="mw-reconcile" hidden><button type="button" class="mw-reconcile-query" id="mw-reconcile-query">核对</button></div></footer>'
            + '</section>';
    }

    function loadUnitFrames() {
        if (typeof fetch !== 'function') return;
        fetch('assets/modifier/units/manifest.json?v=20261102b', {cache:'no-cache'})
            .then(function(response) { return response.ok ? response.json() : null; })
            .then(function(data) { if (data && data.units) unitFrames = data.units; })
            .catch(function() {});
    }

    function init() {
        shell = document.getElementById('modifier-window-shell');
        if (!shell) return;
        shell.innerHTML = skeleton();
        root = shell;
        itemTip = byId('item-tip');
        scale = window.PanelScale.attach(shell, 843, 400);
        bind();
        loadUnitFrames();
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
            tab.addEventListener('click', function() { if (tab.getAttribute('data-tab') !== activeTab) playTabSound(); showTab(tab.getAttribute('data-tab')); });
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
        byId('item-query').addEventListener('keydown', function(event) {
            if (event.key === 'Enter') { event.preventDefault(); searchItems(); }
        });
        byId('item-first').onclick = function() { if (itemPage !== 1) { itemPage = 1; loadItems(); } };
        byId('item-prev').onclick = function() { if (itemPage > 1) { itemPage--; loadItems(); } };
        byId('item-next').onclick = function() { if (itemPage * itemPageSize < itemTotal) { itemPage++; loadItems(); } };
        byId('item-last').onclick = function() {
            var last = itemTotal > 0 ? Math.ceil(itemTotal / Math.max(1, itemPageSize)) : 1;
            if (itemPage !== last) { itemPage = last; loadItems(); }
        };
        byId('item-minus').onclick = function() {
            var input = byId('item-quantity');
            input.value = String(Math.max(1, Number(input.value || 1) - 1));
        };
        byId('item-plus').onclick = function() {
            var input = byId('item-quantity');
            input.value = String(Math.min(999999999, Number(input.value || 1) + 1));
        };
        byId('item-produce').onclick = function() {
            if (!selectedItem) { setStatus('请先选择物品。', 'warn'); return; }
            var count = Number(byId('item-quantity').value);
            if (!Runtime.int(count, 1, 999999999)) { setStatus('数量需为 1–999999999。', 'error'); return; }
            writeRequest('spawnItem', {itemName:selectedItem.name, quantity:count});
        };
        byId('unit-first').onclick = function() { if (unitPage !== 1) { unitPage = 1; loadUnits(); } };
        byId('unit-prev').onclick = function() { if (unitPage > 1) { unitPage--; loadUnits(); } };
        byId('unit-next').onclick = function() { if (unitPage * unitPageSize < unitTotal) { unitPage++; loadUnits(); } };
        byId('unit-last').onclick = function() {
            var last = unitTotal > 0 ? Math.ceil(unitTotal / Math.max(1, unitPageSize)) : 1;
            if (unitPage !== last) { unitPage = last; loadUnits(); }
        };
        byId('unit-level-minus').onclick = function() {
            var input = byId('unit-level');
            input.value = String(Math.max(1, Number(input.value || 1) - 1));
        };
        byId('unit-level-plus').onclick = function() {
            var input = byId('unit-level');
            input.value = String(Math.min(9999, Number(input.value || 1) + 1));
        };
        byId('unit-count-minus').onclick = function() {
            var input = byId('unit-count');
            input.value = String(Math.max(1, Number(input.value || 1) - 1));
        };
        byId('unit-count-plus').onclick = function() {
            var input = byId('unit-count');
            input.value = String(Math.min(100, Number(input.value || 1) + 1));
        };
        byId('unit-spawn').onclick = function() {
            if (!selectedUnit) { setStatus('请先选择兵种。', 'warn'); return; }
            var lv = Number(byId('unit-level').value), count = Number(byId('unit-count').value);
            if (!Runtime.int(lv, 1, 9999) || !Runtime.int(count, 1, 100)) { setStatus('等级 1–9999，数量 1–100。', 'error'); return; }
            writeRequest('spawnUnit', {unitId:selectedUnit.id, count:count, level:lv, hostile:byId('unit-hostile').checked});
        };
        byId('unit-merc').onclick = function() {
            if (!selectedUnit) { setStatus('请先选择兵种。', 'warn'); return; }
            var lv = Number(byId('unit-level').value);
            if (!Runtime.int(lv, 1, 9999)) { setStatus('等级 1–9999。', 'error'); return; }
            writeRequest('spawnMerc', {unitId:selectedUnit.id, level:lv, hostile:byId('unit-hostile').checked});
        };
        byId('reconcile-query').onclick = queryUnresolved;
    }

    function showTab(tab, load) {
        activeTab = tab;
        var win = root.querySelector('.mw-window');
        if (win) win.setAttribute('data-tab', tab);
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
            if (initial) setStatus('', 'neutral');
            else setStatus('状态已刷新。', 'ok');
        });
    }

    function updateSnapshot() {
        if (!snapshot) return;
        var state = snapshot.state;
        text('money', state.money.toLocaleString('zh-CN'));
        text('kcoin', state.kcoin.toLocaleString('zh-CN'));
        var canWrite = !state.challengeMode && state.saveAvailable;
        root.querySelectorAll('[data-write]').forEach(function(button) {
            var requires = button.getAttribute('data-requires');
            var missing = (requires === 'item' && !selectedItem) || (requires === 'unit' && !selectedUnit);
            button.disabled = !canWrite || missing || !!unresolved || writeBusy;
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
            var url = (window.Icons && Icons.resolveStatic) ? Icons.resolveStatic(item.icon) : null;
            if (url) {
                var image = document.createElement('img');
                image.alt = ''; image.src = url;
                image.onerror = function() { image.remove(); card.classList.add('no-icon'); };
                card.appendChild(image);
            } else {
                card.classList.add('no-icon');
            }
            var count = document.createElement('span');
            count.className = 'mw-item-count';
            count.textContent = '1';
            card.appendChild(count);
            card.onclick = function() { selectedItem = item; renderItems(items); renderItemDetail(); };
            card.addEventListener('mouseenter', function(event) { showItemTip(item, card, event); });
            card.addEventListener('mouseleave', hideItemTip);
            grid.appendChild(card);
        });
    }

    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    function showRichItemTip(item, data, event) {
        if (!window.PanelTooltip) return false;
        var html = PanelTooltip.buildItemRichHtml({
            iconHtml: PanelTooltip.dynamicIconHtml(item.icon),
            introHTML: data.introHTML || '',
            descHTML: data.descHTML || '',
            document: data.document || null,
            rootClass: 'inventory-owned-tt-context',
            layoutType: PanelTooltip.inferLayoutType(item.type || item.use || '物品')
        });
        PanelTooltip.showAtMouse(html, event, 'modifier', {profile:'simple-tooltip', placement:'right'});
        return true;
    }

    function requestItemTooltip(item) {
        if (!mux || tooltipLoading[item.name]) return;
        tooltipLoading[item.name] = true;
        request('itemTooltip', {v:1, token:token, itemName:item.name}, function(result) {
            tooltipLoading[item.name] = false;
            var data = Runtime.normalizeItemTooltip(result, token);
            if (!data) return;
            tooltipCache[item.name] = data;
            if (lastTipName === item.name && lastTipEvent && window.PanelTooltip)
                showRichItemTip(item, data, lastTipEvent);
        });
    }

    function showItemTip(item, card, event) {
        lastTipName = item.name;
        lastTipEvent = event ? {clientX:event.clientX, clientY:event.clientY} : null;
        if (window.PanelTooltip && document.getElementById('panel-tooltip')) {
            if (tooltipCache[item.name]) {
                showRichItemTip(item, tooltipCache[item.name], event);
            } else {
                var iconHtml = PanelTooltip.dynamicIconHtml(item.icon);
                var name = escapeHtml(item.displayName || item.name);
                var meta = escapeHtml('#' + item.id + ' · ' + (item.type || '—') + ' · ' + (item.use || '—'));
                var html = PanelTooltip.buildItemRichHtml({
                    iconHtml: iconHtml,
                    introWebHTML: '<b>' + name + '</b>',
                    descHTML: '<span>' + meta + '</span>',
                    splitMode: 'merge'
                });
                PanelTooltip.showAtMouse(html, event, 'modifier', {profile:'simple-tooltip', placement:'right'});
                requestItemTooltip(item);
            }
            return;
        }
        if (!itemTip) return;
        itemTip.textContent = '';
        var title = document.createElement('strong');
        title.textContent = item.displayName || item.name;
        var metaNode = document.createElement('span');
        metaNode.textContent = '#' + item.id + ' · ' + (item.type || '—') + ' · ' + (item.use || '—');
        itemTip.appendChild(title); itemTip.appendChild(metaNode);
        var grid = byId('item-grid');
        var left = (grid ? grid.offsetLeft : 0) + card.offsetLeft + 28;
        var top = (grid ? grid.offsetTop : 0) + card.offsetTop + 2;
        if (left > 660) left = Math.max(4, left - 180);
        itemTip.style.left = left + 'px';
        itemTip.style.top = top + 'px';
        itemTip.hidden = false;
    }

    function hideItemTip() {
        if (window.PanelTooltip) PanelTooltip.hide('modifier');
        if (itemTip) itemTip.hidden = true;
    }

    function renderItemPageState() {
        var pages = itemTotal > 0 ? Math.ceil(itemTotal / Math.max(1, itemPageSize)) : 0;
        text('item-page-state', itemTotal + ' · ' + (pages ? itemPage + '/' + pages : '0/0'));
        var prev = byId('item-prev'), next = byId('item-next');
        var first = byId('item-first'), last = byId('item-last');
        if (prev) prev.disabled = itemPage <= 1;
        if (first) first.disabled = itemPage <= 1;
        if (next) next.disabled = itemPage * itemPageSize >= itemTotal;
        if (last) last.disabled = itemPage * itemPageSize >= itemTotal;
    }

    function renderItemDetail() {
        var slots = [byId('item-slot-0'), byId('item-slot-1')];
        slots.forEach(function(slot) { if (slot) slot.textContent = ''; });
        var produce = byId('item-produce');
        if (!selectedItem) { if (produce) produce.disabled = true; return; }
        var query = byId('item-query');
        if (query) query.value = selectedItem.name;
        var iconUrl = (window.Icons && Icons.resolveStatic) ? Icons.resolveStatic(selectedItem.icon) : null;
        if (iconUrl && slots[0]) {
            var icon = document.createElement('img'); icon.alt = ''; icon.src = iconUrl; slots[0].appendChild(icon);
        }
        var quantity = byId('item-quantity');
        if (quantity && !quantity.value) quantity.value = '1';
        if (produce) {
            produce.disabled = !!unresolved || writeBusy || !snapshot
                || !snapshot.state.saveAvailable || snapshot.state.challengeMode;
        }
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
        var first = byId('unit-first'), last = byId('unit-last');
        if (prev) prev.disabled = unitPage <= 1;
        if (first) first.disabled = unitPage <= 1;
        if (next) next.disabled = unitPage * unitPageSize >= unitTotal;
        if (last) last.disabled = unitPage * unitPageSize >= unitTotal;
    }

    function applyUnitFrame(dataUrl) {
        var preview = byId('unit-preview');
        if (!preview) return;
        preview.textContent = '';
        var img = document.createElement('img');
        img.alt = '';
        img.src = dataUrl;
        preview.appendChild(img);
    }

    function loadUnitFrame(spriteName) {
        if (!mux || !spriteName) return;
        if (unitFrameCache[spriteName]) { applyUnitFrame(unitFrameCache[spriteName]); return; }
        if (unitFrameLoading[spriteName]) return;
        unitFrameLoading[spriteName] = true;
        request('unitFrame', {v:1, token:token, spriteName:spriteName}, function(result) {
            unitFrameLoading[spriteName] = false;
            var frame = Runtime.normalizeUnitFrame(result, token);
            if (!frame) return;
            try {
                var raw = atob(frame.pixels);
                var bytes = new Uint8ClampedArray(raw.length);
                for (var i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
                var canvas = document.createElement('canvas');
                canvas.width = frame.width; canvas.height = frame.height;
                var context = canvas.getContext('2d');
                var image = context.createImageData(frame.width, frame.height);
                image.data.set(bytes);
                context.putImageData(image, 0, 0);
                var dataUrl = canvas.toDataURL('image/png');
                unitFrameCache[spriteName] = dataUrl;
                if (selectedUnit && selectedUnit.spriteName === spriteName) applyUnitFrame(dataUrl);
            } catch (error) { }
        });
    }
    function renderUnitDetail() {
        var spawn = byId('unit-spawn');
        var merc = byId('unit-merc');
        if (!selectedUnit) {
            if (spawn) spawn.disabled = true;
            if (merc) merc.disabled = true;
            return;
        }
        var level = byId('unit-level');
        var count = byId('unit-count');
        var hostile = byId('unit-hostile');
        if (level) level.value = String(Math.max(1, selectedUnit.level || 1));
        if (count) count.value = '1';
        if (hostile) hostile.checked = !!selectedUnit.hostile;
        var preview = byId('unit-preview');
        if (preview) {
            if (unitFrameCache[selectedUnit.spriteName]) {
                applyUnitFrame(unitFrameCache[selectedUnit.spriteName]);
            } else {
                preview.textContent = '';
                var img = document.createElement('img'); img.alt = '' ;
                preview.appendChild(img);
                var frame = unitFrames[selectedUnit.spriteName];
                if (frame) img.src = 'assets/modifier/units/' + frame;
                else if (window.EnemyPortraits) EnemyPortraits.mount(preview, img, {identifier:selectedUnit.spriteName, portraitRef:selectedUnit.spriteName, consumer:'modifier'});
                loadUnitFrame(selectedUnit.spriteName);
            }
        }
        var disabled = !!unresolved || writeBusy || !snapshot
            || !snapshot.state.saveAvailable || snapshot.state.challengeMode;
        if (spawn) spawn.disabled = disabled;
        if (merc) merc.disabled = disabled;
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
