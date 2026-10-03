(function() {
    'use strict';
    var R = window.BookshelfRuntime;
    var shell, host, scale, mux, token, instance, state, recovery, slotSignature;
    var selected = 'dust', page = 1, busy = false, generation = 0, autoReturnAttempted = false, readFailed = false;
    function el(id) { return host.querySelector('#bookshelf-' + id); }
    function create() { shell = document.createElement('div'); shell.className = 'panel-scale-shell bookshelf-shell'; return shell; }
    function onOpen(element, data) {
        host = element; token = data.token; instance = data.panelInstanceId;
        state = null; recovery = ''; slotSignature = ''; busy = false; autoReturnAttempted = false; readFailed = false; generation++;
        host.innerHTML = '<section class="bookshelf-panel"><header><div><span class="bookshelf-eyebrow">基地藏书室</span>'
            + '<h1>每一本书，另一段人生</h1></div><button id="bookshelf-close" aria-label="关闭书架">×</button></header>'
            + '<div class="bookshelf-body"><nav aria-label="书架目录"><h2>藏书</h2><div id="bookshelf-books"></div>'
            + '<h2>角色档案</h2><div id="bookshelf-slots"></div><p id="bookshelf-role" class="bookshelf-muted"></p></nav>'
            + '<main><div id="bookshelf-reader"><img id="bookshelf-page" alt="原版书页"><div class="bookshelf-paging">'
            + '<button id="bookshelf-prev">上一页</button><span id="bookshelf-page-number"></span><button id="bookshelf-next">下一页</button></div></div>'
            + '<article id="bookshelf-detail" hidden></article></main></div>'
            + '<footer><p id="bookshelf-status" role="status" aria-live="polite">正在读取书架…</p><button id="bookshelf-recover" hidden>核对结果</button></footer></section>';
        R.books.forEach(function(book) {
            var b = document.createElement('button'); b.className = 'bookshelf-entry'; b.dataset.book = book.id;
            var title = document.createElement('strong'), subtitle = document.createElement('small');
            title.textContent = book.title; subtitle.textContent = book.subtitle; b.append(title, subtitle);
            b.onclick = function() { selected = book.id; page = 1; render(); }; el('books').appendChild(b);
        });
        el('close').onclick = close; el('prev').onclick = function() { page--; render(); };
        el('next').onclick = function() { page++; render(); };
        el('recover').onclick = function() { if (recovery) reconcile(); else read(); };
        el('page').onerror = function() { status('书页未能载入，请重新打开书架。'); };
        scale = PanelScale.attach(shell, 1024, 576);
        mux = new R.RequestMux({panelInstanceId:instance, send:function(message) { return Bridge.send(message); }});
        render(); read();
    }
    function status(text) { if (host) el('status').textContent = text; }
    function request(cmd, payload) {
        if (!mux || busy) return;
        busy = true; var g = generation; render();
        mux.request(cmd, payload, function(result) { if (g !== generation) return; busy = false; receive(cmd, result); });
    }
    function read() { request('snapshot', {v:1, token:token}); }
    function reconcile() { if (recovery) request('query', {v:1, token:recovery}); }
    function commit(kind, target) { request('commit', {v:1, token:token, kind:kind, target:target}); }
    function receive(cmd, result) {
        if (cmd === 'snapshot') readFailed = !result.success;
        if (result.nextToken && /^(bookshelf\.)[A-Za-z0-9._~-]+$/.test(result.nextToken)
                && (result.phase === 'applied' || result.phase === 'expired') && !result.requiresReconcile) {
            token = result.nextToken; recovery = ''; read(); return;
        }
        if (result.requiresReconcile) recovery = result.recoveryToken || recovery || token;
        else if (cmd === 'query' && (result.phase === 'applied' || result.phase === 'expired')) recovery = '';
        if (cmd === 'query' && !recovery && result.phase) { read(); return; }
        if (result.outcomePending) recovery = token;
        else if (cmd === 'query' && result.phase === 'editing' && !result.requiresReconcile) recovery = '';
        if (result.phase) {
            if (!state && (result.inRun || result.pendingRun)) selected = 'repair-campus';
            state = result;
        }
        if (result.phase === 'switching') { status('正在翻开另一段人生…'); close(true); return; }
        if (result.requiresReconcile && cmd === 'snapshot') { reconcile(); return; }
        if (result.phase === 'save_pending') status('正在确认保存结果。核对完成前，请保留当前角色。');
        else if (result.phase === 'applied') { status('已完成。'); recovery = ''; }
        else if (result.success) status(result.inRun ? '书中装备和成长只属于本次旅程。' : result.lastReward > 0 ? '上次旅程获得 ' + result.lastReward + ' SP。' : '翻阅藏书，或走进另一段人生。');
        else {
            var messages = {busy:'仍有操作尚未完成，请稍后重试。', locked:'请先完成地铁站主线，或处理上一次旅程。',
                slot_corrupt:'这个档案需要在启动入口修复。', slot_needs_migration:'请先从启动入口读取一次这个旧档案。',
                slot_repairable:'这个档案需要在启动入口确认修复。', invalid_target:'档案状态已变化，请重新打开书架。',
                client_timeout:'暂未收到结果，请核对原操作。', not_sent:'请求未能发送，请稍后重试。', timeout:'暂未收到结果，请核对原操作。', disconnected:'游戏连接暂时不可用。', save_unavailable:'档案暂时不可读取。'};
            status(messages[result.error] || '操作未完成，请重新读取或核对结果。');
        }
        render();
        if (cmd === 'snapshot' && result.success && result.phase === 'editing'
                && result.exitRequired && result.inRun && result.canSwitch && !recovery && !autoReturnAttempted) {
            autoReturnAttempted = true;
            status('正在结束旅程，恢复原角色…');
            commit('return', result.originSlot);
        }
    }
    function render() {
        if (!host) return;
        el('close').disabled = busy || !!(state && state.exitRequired && state.inRun);
        var book = R.books.find(function(b) { return b.id === selected; });
        host.querySelectorAll('[data-book]').forEach(function(b) { b.setAttribute('aria-current', String(b.dataset.book === selected)); });
        var reading = book && book.pages > 0;
        el('reader').hidden = !reading; el('detail').hidden = reading;
        if (reading) {
            page = Math.max(1, Math.min(book.pages, page));
            el('page').src = R.pageUrl(book.id, page); el('page').alt = book.title + '，第 ' + page + ' 页';
            el('page-number').textContent = page + ' / ' + book.pages;
            el('prev').disabled = page <= 1; el('next').disabled = page >= book.pages;
        } else {
            var detail = el('detail');
            if (detail.dataset.view !== selected) {
                detail.textContent = ''; detail.dataset.view = selected;
                detail.append(document.createElement('h2'), document.createElement('p'), document.createElement('button'));
            }
            var heading = detail.children[0], text = detail.children[1], action = detail.children[2];
            action.className = 'bookshelf-primary';
            if (selected.indexOf('slot:') === 0) {
                var slot = selected.slice(5), entry = state && (state.slots || []).find(function(s) { return s.slot === slot; });
                heading.textContent = entry ? entry.name : '角色档案';
                text.textContent = '保存当前角色，经过场切换至这个档案。两位角色的装备、技能与任务进度各自保留。';
                action.textContent = state && state.activeSlot === slot ? '当前角色' : '切换角色';
                action.disabled = !state || state.activeSlot === slot || !state.canSwitch || state.inRun || !!state.pendingRun;
                action.onclick = function() { commit('switch', slot); };
            } else {
                heading.textContent = '修理大学';
                text.textContent = '从 1 级 Andy Law 开始，走过七张地图：从路边混混，到剑道社，最后挑战体育老师。拾取装备与战场补给，向迷之盔甲君学习技能，尝试自己的构筑。\n\n本次旅程不支持中途续玩。成功后带回 SP；失败时结束本次成长，原角色不受损失。';
                if (state && state.inRun) {
                    action.textContent = '结束旅程，返回原角色'; action.onclick = function() { commit('return', state.originSlot); };
                } else if (state && state.pendingRun) {
                    action.textContent = '核对上次旅程'; action.onclick = function() { commit('settle', state.pendingRun); };
                } else {
                    action.textContent = state && state.unlocked ? '进入书中' : '完成地铁站主线后开放';
                    action.onclick = function() { commit('play', 'repair-campus'); };
                }
                action.disabled = !state || !state.canSwitch || (!state.inRun && !state.pendingRun && !state.unlocked);
            }
            action.disabled = action.disabled || busy || !!recovery || readFailed;
        }
        el('recover').textContent = recovery ? '核对结果' : '重新读取';
        el('recover').hidden = !recovery && !readFailed && !!state; el('recover').disabled = busy;
        el('role').textContent = state ? '当前：' + state.role : '';
        var slots = el('slots'), entries = state && state.slots || [];
        var signature = JSON.stringify(entries);
        if (signature !== slotSignature) {
            var focused = document.activeElement && document.activeElement.dataset.slot;
            var scroll = slots.parentElement.scrollTop;
            slots.textContent = ''; slotSignature = signature;
            entries.forEach(function(slot) {
                var b = document.createElement('button'); b.className = 'bookshelf-slot'; b.dataset.slot = slot.slot;
                b.onclick = function() { selected = 'slot:' + slot.slot; render(); }; slots.appendChild(b);
                if (focused === slot.slot) b.focus({preventScroll:true});
            });
            slots.parentElement.scrollTop = scroll;
        }
        Array.from(slots.children).forEach(function(b, i) {
            b.textContent = (entries[i].slot === state.activeSlot ? '● ' : '') + entries[i].name;
            b.setAttribute('aria-current', String(selected === 'slot:' + entries[i].slot));
        });
    }
    function close(transitionAccepted) {
        if (!host || busy || (transitionAccepted !== true && state && state.exitRequired && state.inRun)) return false;
        if (Bridge.send({type:'panel', panel:'bookshelf', cmd:'close', panelInstanceId:instance}) === false) return false;
        Panels.close(); return true;
    }
    function cleanup() {
        generation++; if (mux) mux.destroy(); if (scale) scale.detach();
        if (host) el('page').onerror = null;
        host = mux = scale = state = null; recovery = ''; slotSignature = ''; busy = false;
        if (shell) shell.textContent = '';
    }
    Panels.register('bookshelf', {create:create, onOpen:onOpen, onRebind:function(element,data) { cleanup(); onOpen(element,data); }, onClose:cleanup, onRequestClose:close, onForceClose:cleanup});
})();
