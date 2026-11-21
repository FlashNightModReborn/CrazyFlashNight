/* U7 彩蛋地图选关：原 FLA 美术与时间轴，C# 裁决准入，AS2 执行进关。 */
(function() {
    'use strict';
    var Runtime = window.EggStageSelectRuntime;
    var shell, element, scale, mux, instance, snapshot, pendingDestination, layout;
    var phase = 'closed', busy = false, generation = 0, closeTimer = 0, confirmTimer = 0;
    var disposers = [];
    var audio = {};
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
    function motionMs(value) {
        return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 0 : value;
    }
    function listen(node, event, handler) {
        node.addEventListener(event, handler);
        disposers.push(function() { node.removeEventListener(event, handler); });
    }
    function playSound(name) {
        try {
            if (!audio[name]) {
                audio[name] = new Audio('assets/egg-stage-select/' + name + '.wav');
                audio[name].preload = 'auto';
            }
            audio[name].currentTime = 0;
            var played = audio[name].play();
            if (played && played.catch) played.catch(function() {});
        } catch (_) {}
    }
    function stopSounds() {
        Object.keys(audio).forEach(function(name) {
            try { audio[name].pause(); audio[name].currentTime = 0; } catch (_) {}
        });
        audio = {};
    }
    function create() {
        shell = document.createElement('div');
        shell.className = 'panel-scale-shell appearance-service-shell stage-door-shell egg-scale-shell';
        return shell;
    }
    function onOpen(host, data) {
        generation++; instance = data.panelInstanceId; snapshot = null; pendingDestination = null; layout = null;
        phase = 'loading'; busy = false; disposers = []; closeTimer = confirmTimer = 0; audio = {};
        host.classList.remove('egg-exiting');
        host.innerHTML = '<section class="appearance-service-panel stage-door-panel egg-panel egg-entering">'
            + '<img class="egg-base" src="assets/egg-stage-select/panel-base.svg" alt="">'
            + '<div class="egg-entries" id="egg-entries" role="list"></div>'
            + '<div class="egg-texts" id="egg-texts"></div>'
            + '<button class="egg-close" id="egg-close" aria-label="关闭"><img src="assets/egg-stage-select/close.svg" alt=""></button>'
            + '<div class="egg-lock-notice" id="egg-lock-notice" hidden>尚未解锁</div>'
            + '<div class="egg-confirm" id="egg-confirm" hidden role="dialog" aria-modal="true" aria-labelledby="egg-confirm-text">'
            + '<img class="egg-dialog-art" src="assets/egg-stage-select/confirm-dialog.svg" alt="">'
            + '<p id="egg-confirm-text">确认选择该关卡吗？</p>'
            + '<button class="egg-dialog-button confirm" id="egg-confirm-enter">确认</button>'
            + '<button class="egg-dialog-button cancel" id="egg-confirm-cancel">取消</button></div>'
            + '<div class="egg-status" id="egg-status" role="status" aria-live="polite">正在读取关卡…</div></section>';
        element = host;
        scale = window.PanelScale.attach(shell, 540, 370);
        mux = new Runtime.RequestMux({send:function(message) { return Bridge.send(message); }, panelInstanceId:instance});
        listen(byId('close'), 'click', requestClose);
        listen(byId('confirm-cancel'), 'click', cancelConfirm);
        listen(byId('confirm-enter'), 'click', confirmEnter);
        loadLayout();
        readSnapshot();
        playSound('panel-enter');
    }
    function loadLayout() {
        var opened = generation;
        fetch('assets/egg-stage-select/layout.json', {cache:'no-cache'}).then(function(response) {
            if (!response.ok) throw new Error('layout_http_' + response.status);
            return response.json();
        }).then(function(data) {
            if (opened !== generation || phase === 'closed') return;
            if (!data || data.version !== 1 || !data.stage || !data.previews || !data.intro || !data.exit || !data.confirm) {
                throw new Error('invalid_layout');
            }
            layout = data;
            renderLayout();
            refresh();
        }).catch(function() {
            if (opened !== generation || phase === 'closed') return;
            phase = 'error';
            status('原关卡界面资源读取失败，请重新打开。');
        });
    }
    function textNode(text) { return document.createTextNode(text == null ? '' : String(text)); }
    function renderLayout() {
        var texts = byId('texts');
        layout.texts.forEach(function(record, index) {
            var block = document.createElement('div');
            block.className = 'egg-text' + (index === layout.texts.length - 1 ? ' instruction' : ' destination');
            block.style.left = record.x + 'px'; block.style.top = record.y + 'px';
            var lines = record.runs.filter(function(text) { return text && text !== '\r' && text.trim(); });
            lines.forEach(function(text, lineIndex) {
                var line = document.createElement('span');
                line.className = lineIndex === 0 && index < 3 ? 'egg-destination-name' : 'egg-destination-description';
                line.appendChild(textNode(text)); block.appendChild(line);
            });
            texts.appendChild(block);
        });
    }
    function destinationCard(destination) {
        var record = layout.previews[destination.id];
        var card = document.createElement('button');
        card.type = 'button';
        card.className = 'egg-entry' + (destination.unlocked ? '' : ' locked')
            + (pendingDestination && pendingDestination.id === destination.id ? ' selected' : '');
        card.style.left = record.x + 'px'; card.style.top = record.y + 'px';
        card.style.width = record.width + 'px'; card.style.height = record.height + 'px';
        card.setAttribute('role', 'listitem');
        card.setAttribute('data-destination', destination.id);
        card.setAttribute('aria-label', destination.name + '，' + destination.difficulty
            + (destination.unlocked ? '' : '，尚未解锁：' + destination.lockReason));
        card.setAttribute('aria-disabled', destination.unlocked ? 'false' : 'true');
        var image = document.createElement('img');
        image.src = 'assets/egg-stage-select/' + record.file; image.alt = destination.name;
        card.appendChild(image);
        listen(card, 'click', function() {
            if (destination.unlocked) armConfirm(destination);
            else status('尚未解锁：' + (destination.lockReason || '请继续推进彩蛋任务。'));
        });
        function showHint() {
            if (!destination.hintLocked && destination.unlocked) return;
            byId('lock-notice').hidden = false;
        }
        function hideHint() { byId('lock-notice').hidden = true; }
        listen(card, 'mouseenter', showHint); listen(card, 'focus', showHint);
        listen(card, 'mouseleave', hideHint); listen(card, 'blur', hideHint);
        return card;
    }
    function refresh() {
        if (!element || !snapshot || !layout) return;
        var list = byId('entries'); list.textContent = '';
        snapshot.destinations.forEach(function(destination) { list.appendChild(destinationCard(destination)); });
        byId('confirm-enter').disabled = busy;
    }
    function refreshSelection() {
        var cards = byId('entries').querySelectorAll('.egg-entry');
        for (var i = 0; i < cards.length; i++) {
            cards[i].classList.toggle('selected', !!pendingDestination && cards[i].getAttribute('data-destination') === pendingDestination.id);
        }
    }
    function armConfirm(destination) {
        if (busy || phase !== 'editing') return;
        clearTimeout(confirmTimer); confirmTimer = 0;
        pendingDestination = destination;
        byId('confirm').classList.remove('closing');
        byId('confirm').hidden = false;
        refreshSelection();
        playSound('confirm-open');
        byId('confirm-enter').focus();
    }
    function cancelConfirm() {
        pendingDestination = null;
        refreshSelection();
        if (byId('confirm').hidden) return;
        playSound('confirm-cancel');
        byId('confirm').classList.add('closing');
        var opened = generation;
        clearTimeout(confirmTimer);
        confirmTimer = setTimeout(function() {
            if (opened !== generation || phase === 'closed') return;
            byId('confirm').hidden = true;
            byId('confirm').classList.remove('closing');
        }, motionMs(layout ? layout.confirm.durationMs : 583));
    }
    function readSnapshot() {
        phase = 'loading'; status('正在读取关卡…');
        request('snapshot', {v:1}, function(result) {
            var state = Runtime.normalizeState(result);
            if (state) {
                snapshot = state; phase = 'editing';
                status('');
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
    function finishClose() {
        var sent = false;
        try { sent = Bridge.send({type:'panel', panel:'egg-stage-select', cmd:'close', panelInstanceId:instance}) !== false; } catch (_) {}
        if (!sent) {
            phase = 'editing'; shell.classList.remove('egg-exiting');
            status('关闭请求未能发送，请再试一次。');
            return;
        }
        cue('back'); Panels.close();
    }
    function requestClose() {
        if (busy || phase === 'closed' || phase === 'closing') return false;
        phase = 'closing';
        clearTimeout(confirmTimer); confirmTimer = 0;
        shell.classList.remove('egg-entering'); shell.classList.add('egg-exiting');
        var opened = generation;
        closeTimer = setTimeout(function() {
            if (opened === generation && phase === 'closing') finishClose();
        }, motionMs(layout ? layout.exit.durationMs : 0));
        return true;
    }
    function cleanup() {
        generation++; phase = 'closed'; busy = false; snapshot = null; pendingDestination = null; layout = null;
        clearTimeout(closeTimer); clearTimeout(confirmTimer); closeTimer = confirmTimer = 0;
        disposers.forEach(function(dispose) { dispose(); }); disposers = [];
        stopSounds();
        if (mux) mux.destroy(); if (scale) scale.detach();
        mux = scale = null; instance = ''; element = null;
        if (shell) shell.textContent = '';
    }
    Panels.register('egg-stage-select', {create:create, onOpen:onOpen, onClose:cleanup, onRequestClose:requestClose, onForceClose:cleanup});
    window.EggStageSelectPanel = {debugState:function() { return {phase:phase, busy:busy, state:snapshot, instance:instance,
        pendingDestination:pendingDestination && pendingDestination.id, layout:layout}; }};
})();
