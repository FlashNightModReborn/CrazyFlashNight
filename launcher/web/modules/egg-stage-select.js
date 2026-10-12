/* U7 彩蛋地图选关：三目的地 × 固定难度，彩蛋进度门投影由 AS2 裁决。 */
(function() {
    'use strict';
    var Runtime = window.EggStageSelectRuntime;
    var shell, element, scale, mux, instance, snapshot, pendingDestination;
    var phase = 'closed', busy = false, generation = 0;
    var disposers = [];
    var errors = {
        locked:'该目的地尚未解锁。',
        unknown_destination:'目的地已失效，请重新打开选关界面。',
        pending_stage_settlement:'请先处理上一关的奖励或结算。',
        enter_refused:'暂时无法进入该关卡。',
        stage_config_unavailable:'关卡资料尚未就绪，请稍后重试。',
        stage_config_failed:'关卡资料读取失败，请重新打开选关界面。',
        disconnected:'游戏连接已断开，请恢复连接后再试。',
        not_sent:'请求未能发送，请再试一次。',
        timeout:'进入结果未确认，请观察游戏状态后再操作。',
        client_timeout:'进入结果未确认，请观察游戏状态后再操作。',
        malformed_response:'暂时无法确认进入结果，请观察游戏状态。',
        busy:'上一个进入请求仍在处理中。',
        panel_instance_expired:'面板已失效，请从彩蛋地图的电脑重新打开。'
    };
    function byId(id) { return element.querySelector('#egg-' + id); }
    function cue(name) { if (window.BootstrapAudio) window.BootstrapAudio.cue(name); }
    function status(text) { if (element) byId('status').textContent = text; }
    function listen(node, event, handler) {
        node.addEventListener(event, handler);
        disposers.push(function() { node.removeEventListener(event, handler); });
    }
    function create() { shell = document.createElement('div'); shell.className = 'panel-scale-shell appearance-service-shell stage-door-shell egg-scale-shell'; return shell; }
    function onOpen(host, data) {
        generation++; instance = data.panelInstanceId; snapshot = null; pendingDestination = null;
        phase = 'loading'; busy = false; disposers = [];
        host.innerHTML = '<section class="appearance-service-panel stage-door-panel egg-panel">'
            + '<header class="appearance-service-header"><div class="appearance-service-heading"><p class="appearance-service-kicker">彩蛋地图</p><h1>关卡选择</h1></div>'
            + '<span class="appearance-service-current">隐藏区域</span><button class="appearance-service-close" id="egg-close" aria-label="关闭">×</button></header>'
            + '<main class="stage-door-body"><div class="stage-door-entries egg-entries" id="egg-entries" role="list"></div></main>'
            + '<div class="stage-door-confirm" id="egg-confirm" hidden>'
            + '<p id="egg-confirm-text"></p><div class="stage-door-confirm-actions">'
            + '<button class="appearance-service-button" id="egg-confirm-cancel">取消</button>'
            + '<button class="appearance-service-button primary" id="egg-confirm-enter">进入</button></div></div>'
            + '<footer class="appearance-service-footer"><p class="stage-door-status" id="egg-status" role="status" aria-live="polite">正在读取关卡…</p></footer></section>';
        element = host;
        scale = window.PanelScale.attach(shell, 1024, 576);
        mux = new Runtime.RequestMux({send:function(message) { return Bridge.send(message); }, panelInstanceId:instance});
        listen(byId('close'), 'click', requestClose);
        listen(byId('confirm-cancel'), 'click', cancelConfirm);
        listen(byId('confirm-enter'), 'click', confirmEnter);
        readSnapshot();
    }
    function destinationCard(destination) {
        var card = document.createElement('button');
        card.type = 'button';
        card.className = 'stage-door-entry egg-entry' + (destination.unlocked ? '' : ' locked');
        card.setAttribute('role', 'listitem');
        var title = document.createElement('span'); title.className = 'stage-door-entry-name'; title.textContent = destination.name;
        card.appendChild(title);
        var badge = document.createElement('span'); badge.className = 'stage-door-entry-difficulty';
        badge.textContent = destination.difficulty; card.appendChild(badge);
        if (destination.unlocked) {
            listen(card, 'click', function() { armConfirm(destination); });
        } else {
            card.disabled = true;
            var note = document.createElement('span'); note.className = 'stage-door-entry-note';
            note.textContent = destination.lockReason ? '尚未解锁：' + destination.lockReason : '尚未解锁';
            card.appendChild(note);
        }
        return card;
    }
    function refresh() {
        if (!element || !snapshot) return;
        var list = byId('entries'); list.textContent = '';
        snapshot.destinations.forEach(function(destination) { list.appendChild(destinationCard(destination)); });
        byId('confirm-enter').disabled = busy;
    }
    function armConfirm(destination) {
        if (busy || phase !== 'editing') return;
        pendingDestination = destination;
        byId('confirm-text').textContent = '进入 ' + destination.name + '（' + destination.difficulty + '）？';
        byId('confirm').hidden = false;
        byId('confirm-enter').focus();
    }
    function cancelConfirm() {
        pendingDestination = null;
        byId('confirm').hidden = true;
    }
    function readSnapshot() {
        phase = 'loading'; status('正在读取关卡…');
        request('snapshot', {v:1}, function(result) {
            var state = Runtime.normalizeState(result);
            if (state) {
                snapshot = state; phase = 'editing';
                status('彩蛋进度 ' + state.progress.egg + ' · 主线任务进度 ' + state.progress.main);
                refresh();
                return;
            }
            phase = 'error';
            status(errors[result && result.error] || '关卡资料暂时不可用，请重新打开。');
        });
    }
    function confirmEnter() {
        if (busy || !pendingDestination || phase !== 'editing') return;
        cue('activate');
        var destination = pendingDestination;
        status('正在进入 ' + destination.name + '…');
        request('enter', {v:1, destinationId:destination.id}, function(result) {
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
        try { sent = Bridge.send({type:'panel', panel:'egg-stage-select', cmd:'close', panelInstanceId:instance}) !== false; } catch (_) { }
        if (!sent) { status('关闭请求未能发送，请再试一次。'); return false; }
        cue('back'); Panels.close(); return true;
    }
    function cleanup() {
        generation++; phase = 'closed'; busy = false; snapshot = null; pendingDestination = null;
        disposers.forEach(function(dispose) { dispose(); }); disposers = [];
        if (mux) mux.destroy(); if (scale) scale.detach();
        mux = scale = null; instance = ''; element = null;
        if (shell) shell.textContent = '';
    }
    Panels.register('egg-stage-select', {create:create, onOpen:onOpen, onClose:cleanup, onRequestClose:requestClose, onForceClose:cleanup});
    window.EggStageSelectPanel = {debugState:function() { return {phase:phase, busy:busy, state:snapshot, instance:instance}; }};
})();
