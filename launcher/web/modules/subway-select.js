/* U7 地铁线路图：站点投影 + 目的地列表 + 进入确认。门槛与进关由 AS2 裁决。 */
(function() {
    'use strict';
    var Runtime = window.SubwaySelectRuntime;
    var shell, element, scale, mux, instance, snapshot, pendingEntry;
    var phase = 'closed', busy = false, generation = 0;
    var disposers = [];
    var errors = {
        locked:'该目的地尚未解锁。',
        not_enterable:'该条目只作展示，不能从这里进入。',
        unknown_entry:'目的地已失效，请重新打开线路图。',
        pending_stage_settlement:'请先处理上一关的奖励或结算。',
        enter_refused:'暂时无法进入该关卡。',
        stage_config_unavailable:'关卡资料尚未就绪，请稍后重试。',
        stage_config_failed:'关卡资料读取失败，请重新打开线路图。',
        disconnected:'游戏连接已断开，请恢复连接后再试。',
        not_sent:'请求未能发送，请再试一次。',
        timeout:'进入结果未确认，请观察游戏状态后再操作。',
        client_timeout:'进入结果未确认，请观察游戏状态后再操作。',
        malformed_response:'暂时无法确认进入结果，请观察游戏状态。',
        busy:'上一个进入请求仍在处理中。',
        panel_instance_expired:'面板已失效，请从隧道据点重新打开。'
    };
    function byId(id) { return element.querySelector('#subway-' + id); }
    function cue(name) { if (window.BootstrapAudio) window.BootstrapAudio.cue(name); }
    function status(text) { if (element) byId('status').textContent = text; }
    function listen(node, event, handler) {
        node.addEventListener(event, handler);
        disposers.push(function() { node.removeEventListener(event, handler); });
    }
    function create() { shell = document.createElement('div'); shell.className = 'panel-scale-shell appearance-service-shell stage-door-shell subway-scale-shell'; return shell; }
    function onOpen(host, data) {
        generation++; instance = data.panelInstanceId; snapshot = null; pendingEntry = null;
        phase = 'loading'; busy = false; disposers = [];
        host.innerHTML = '<section class="appearance-service-panel stage-door-panel subway-panel">'
            + '<header class="appearance-service-header"><div class="appearance-service-heading"><p class="appearance-service-kicker">隧道据点</p><h1>地铁线路图</h1></div>'
            + '<span class="appearance-service-current">站点与目的地</span><button class="appearance-service-close" id="subway-close" aria-label="关闭">×</button></header>'
            + '<main class="stage-door-body"><ol class="subway-stations" id="subway-stations" aria-label="线路站点"></ol>'
            + '<div class="stage-door-entries" id="subway-entries" role="list"></div></main>'
            + '<div class="stage-door-confirm" id="subway-confirm" hidden>'
            + '<p id="subway-confirm-text"></p><div class="stage-door-confirm-actions">'
            + '<button class="appearance-service-button" id="subway-confirm-cancel">取消</button>'
            + '<button class="appearance-service-button primary" id="subway-confirm-enter">进入</button></div></div>'
            + '<footer class="appearance-service-footer"><p class="stage-door-status" id="subway-status" role="status" aria-live="polite">正在读取线路…</p></footer></section>';
        element = host;
        scale = window.PanelScale.attach(shell, 1024, 576);
        mux = new Runtime.RequestMux({send:function(message) { return Bridge.send(message); }, panelInstanceId:instance});
        listen(byId('close'), 'click', requestClose);
        listen(byId('confirm-cancel'), 'click', cancelConfirm);
        listen(byId('confirm-enter'), 'click', confirmEnter);
        readSnapshot();
    }
    function stationSymbol(station) {
        var dot = document.createElement('li');
        dot.className = 'subway-station' + (station.locked ? ' locked' : '');
        var mark = document.createElement('span'); mark.className = 'subway-station-dot'; mark.setAttribute('aria-hidden', 'true');
        var name = document.createElement('span'); name.className = 'subway-station-name'; name.textContent = station.name;
        dot.appendChild(mark); dot.appendChild(name);
        if (station.locked) dot.setAttribute('aria-label', station.name + '（未解锁）');
        return dot;
    }
    function entryCard(entry) {
        var card = document.createElement('button');
        card.type = 'button';
        card.className = 'stage-door-entry' + (entry.highlighted ? ' highlighted' : '');
        card.setAttribute('role', 'listitem');
        var title = document.createElement('span'); title.className = 'stage-door-entry-name'; title.textContent = entry.name;
        card.appendChild(title);
        if (entry.description) {
            var description = document.createElement('span'); description.className = 'stage-door-entry-description';
            description.textContent = entry.description; card.appendChild(description);
        }
        if (entry.enterable) {
            var badge = document.createElement('span'); badge.className = 'stage-door-entry-difficulty';
            badge.textContent = entry.difficulty; card.appendChild(badge);
            listen(card, 'click', function() { armConfirm(entry); });
        } else {
            card.disabled = true;
            var note = document.createElement('span'); note.className = 'stage-door-entry-note';
            note.textContent = '仅记录'; card.appendChild(note);
        }
        return card;
    }
    function refresh() {
        if (!element || !snapshot) return;
        var stations = byId('stations'); stations.textContent = '';
        snapshot.stations.forEach(function(station) { stations.appendChild(stationSymbol(station)); });
        var list = byId('entries'); list.textContent = '';
        if (!snapshot.entries.length) {
            var empty = document.createElement('p'); empty.className = 'stage-door-empty';
            empty.textContent = '当前没有可用目的地。'; list.appendChild(empty);
        }
        snapshot.entries.forEach(function(entry) { list.appendChild(entryCard(entry)); });
        byId('confirm-enter').disabled = busy;
    }
    function armConfirm(entry) {
        if (busy || phase !== 'editing') return;
        pendingEntry = entry;
        byId('confirm-text').textContent = '前往 ' + entry.name + '（' + entry.difficulty + '）？';
        byId('confirm').hidden = false;
        byId('confirm-enter').focus();
    }
    function cancelConfirm() {
        pendingEntry = null;
        byId('confirm').hidden = true;
    }
    function readSnapshot() {
        phase = 'loading'; status('正在读取线路…');
        request('snapshot', {v:1}, function(result) {
            var state = Runtime.normalizeState(result);
            if (state) {
                snapshot = state; phase = 'editing';
                status('主线任务进度 ' + state.progress.main + ' · 彩蛋进度 ' + state.progress.egg);
                refresh();
                return;
            }
            phase = 'error';
            status(errors[result && result.error] || '线路资料暂时不可用，请重新打开。');
        });
    }
    function confirmEnter() {
        if (busy || !pendingEntry || phase !== 'editing') return;
        cue('activate');
        var entry = pendingEntry;
        status('正在进入 ' + entry.name + '…');
        request('enter', {v:1, entryId:entry.id}, function(result) {
            var outcome = Runtime.normalizeEnter(result);
            if (outcome && outcome.success) { requestClose(); return; }
            cancelConfirm();
            if (result && result.enterUnknown) {
                status('进入结果未确认，请观察游戏状态后再操作。');
            } else {
                status(errors[outcome && outcome.error || result && result.error] || '暂时无法进入该关卡。');
            }
        });
    }
    function request(cmd, payload, callback) {
        if (busy || !mux) return;
        var opened = generation;
        busy = true; if (element) byId('confirm-enter').disabled = true;
        mux.request(cmd, payload, function(result) {
            if (opened !== generation || phase === 'closed') return;
            busy = false; callback(result);
        });
    }
    function requestClose() {
        if (busy || phase === 'closed') return false;
        var sent = false;
        try { sent = Bridge.send({type:'panel', panel:'subway', cmd:'close', panelInstanceId:instance}) !== false; } catch (_) { }
        if (!sent) { status('关闭请求未能发送，请再试一次。'); return false; }
        cue('back'); Panels.close(); return true;
    }
    function cleanup() {
        generation++; phase = 'closed'; busy = false; snapshot = null; pendingEntry = null;
        disposers.forEach(function(dispose) { dispose(); }); disposers = [];
        if (mux) mux.destroy(); if (scale) scale.detach();
        mux = scale = null; instance = ''; element = null;
        if (shell) shell.textContent = '';
    }
    Panels.register('subway', {create:create, onOpen:onOpen, onClose:cleanup, onRequestClose:requestClose, onForceClose:cleanup});
    window.SubwaySelectPanel = {debugState:function() { return {phase:phase, busy:busy, state:snapshot, instance:instance}; }};
})();
