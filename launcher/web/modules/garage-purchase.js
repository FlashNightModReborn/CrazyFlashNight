(function() {
    'use strict';
    var Runtime = window.GaragePurchaseRuntime;
    var shell, element, scale, mux, snapshot, instance, vehicleId, recoveryToken;
    var visuals = {
        bicycle:{image:'assets/garage-vehicles/bicycle.webp', role:'轻便 · 近途出行'},
        motorcycle:{image:'assets/garage-vehicles/motorcycle.webp', role:'灵活 · 中途出行'},
        offroad:{image:'assets/garage-vehicles/offroad.webp', role:'载货 · 跨区出行'}
    };
    var phase = 'closed', busy = false, generation = 0;
    function byId(id) { return element.querySelector('#garage-' + id); }
    function cue(name) { if (window.BootstrapAudio) window.BootstrapAudio.cue(name); }
    function status(text) { if (element) byId('status').textContent = text; }
    function create() { shell = document.createElement('div'); shell.className = 'panel-scale-shell appearance-service-shell garage-scale-shell'; return shell; }
    function onOpen(host, data) {
        generation++; instance = data.panelInstanceId; vehicleId = data.vehicleId;
        phase = 'loading'; busy = false; snapshot = null; recoveryToken = '';
        host.innerHTML = '<section class="appearance-service-panel garage-panel">'
            + '<header class="appearance-service-header"><div class="appearance-service-heading"><p class="appearance-service-kicker">基地车库</p><h1 id="garage-title">车辆选购</h1></div>'
            + '<span class="appearance-service-current">出行与后勤</span><button class="appearance-service-close" id="garage-close" aria-label="关闭">×</button></header>'
            + '<main class="garage-body"><figure class="garage-showcase"><p class="garage-eyebrow">实车预览</p>'
            + '<div class="garage-vehicle-stage"><img id="garage-image" alt="" hidden>'
            + '<p class="garage-image-placeholder" id="garage-image-placeholder">正在读取车辆…</p></div>'
            + '<figcaption><span id="garage-role">出行与后勤</span><span>基地现车</span></figcaption></figure>'
            + '<article class="garage-card"><p class="garage-eyebrow">购买后获得</p>'
            + '<h2 id="garage-name">读取车辆资料…</h2><ul class="garage-benefits" id="garage-description" aria-label="车辆权益"></ul>'
            + '<dl><div><dt>购买价格</dt><dd id="garage-cost">—</dd></div>'
            + '<div><dt>当前金币</dt><dd id="garage-balance">—</dd></div>'
            + '<div><dt>驾驶要求</dt><dd id="garage-driving">—</dd></div></dl>'
            + '<p class="garage-status" id="garage-status" role="status" aria-live="polite">正在读取车辆资料…</p></article></main>'
            + '<footer class="appearance-service-footer"><p>一次购买，长期使用。地图目的地仍需满足剧情与发现条件。</p><div class="appearance-service-actions">'
            + '<button class="appearance-service-button" id="garage-cancel">取消</button>'
            + '<button class="appearance-service-button primary" id="garage-confirm" disabled>读取中…</button></div></footer></section>';
        element = host;
        scale = window.PanelScale.attach(shell, 1024, 576);
        mux = new Runtime.RequestMux({send:function(message) { return Bridge.send(message); }, panelInstanceId:instance});
        byId('close').onclick = requestClose; byId('cancel').onclick = requestClose; byId('confirm').onclick = submit;
        readSnapshot();
    }
    function presentVehicle(state) {
        var visual = visuals[state.vehicleId], image = byId('image'), placeholder = byId('image-placeholder');
        byId('role').textContent = visual.role;
        if (image.dataset.vehicleId !== state.vehicleId) {
            image.dataset.vehicleId = state.vehicleId;
            image.alt = state.name + '外观'; image.hidden = true; placeholder.hidden = false;
            placeholder.textContent = '正在读取车辆图片…';
            image.onload = function() { image.hidden = false; placeholder.hidden = true; };
            image.onerror = function() { image.hidden = true; placeholder.hidden = false; placeholder.textContent = '车辆预览暂时不可用'; };
            image.src = visual.image;
        }
        var list = byId('description'); list.textContent = '';
        state.description.split(/\r?\n/).forEach(function(line) {
            line = line.trim(); if (!line) return;
            var row = document.createElement('li'), separator = line.indexOf('：');
            if (separator > 0 && separator < 16) {
                var label = document.createElement('span'); label.className = 'garage-benefit-label';
                label.textContent = line.slice(0, separator); row.appendChild(label);
                var text = document.createElement('span'); text.className = 'garage-benefit-text';
                text.textContent = line.slice(separator + 1); row.appendChild(text);
            } else { row.className = 'garage-benefit-plain'; row.textContent = line; }
            list.appendChild(row);
        });
    }
    function refresh() {
        if (!element) return;
        if (snapshot) {
            byId('name').textContent = snapshot.name;
            presentVehicle(snapshot);
            byId('cost').textContent = snapshot.cost.toLocaleString('zh-CN') + ' 金币';
            byId('balance').textContent = snapshot.balance.toLocaleString('zh-CN') + ' 金币';
            byId('driving').textContent = snapshot.requiredDrivingLevel ? '驾驶 Lv.' + snapshot.requiredDrivingLevel + ' · 当前 Lv.' + snapshot.drivingLevel : '无需驾驶技能';
            byId('balance').dataset.insufficient = String(snapshot.balance < snapshot.cost);
            byId('driving').dataset.insufficient = String(snapshot.drivingLevel < snapshot.requiredDrivingLevel);
        }
        byId('confirm').textContent = busy ? '处理中…' : phase === 'save_pending' ? '重试保存'
            : phase === 'unknown' ? '核对购买结果' : phase === 'applied' || phase === 'owned' ? '关闭'
            : phase === 'error' ? '重新读取' : snapshot ? '确认购买 · ' + snapshot.cost.toLocaleString('zh-CN') + ' 金币' : '读取中…';
        byId('confirm').disabled = busy || phase === 'loading' || phase === 'editing' && (!snapshot || !snapshot.canPurchase);
        byId('cancel').textContent = phase === 'editing' || phase === 'loading' ? '取消' : '关闭';
        byId('cancel').disabled = byId('close').disabled = busy;
    }
    function request(cmd, payload, callback) {
        if (busy || !mux) return;
        var opened = generation;
        busy = true; refresh();
        mux.request(cmd, payload, function(result) {
            if (opened !== generation || phase === 'closed') return;
            busy = false; callback(result); refresh();
        });
    }
    function readSnapshot() {
        phase = 'loading'; status('正在读取车辆资料…');
        request('snapshot', {v:1, vehicleId:vehicleId}, function(result) {
            if (result.requiresReconcile && result.token) {
                recoveryToken = result.token;
                request('query', {v:1, token:recoveryToken}, receive);
            } else receive(result);
        });
    }
    function receive(result) {
        var state = Runtime.normalizeState(result);
        if (state) {
            snapshot = state; recoveryToken = state.token; phase = state.phase;
            status(phase === 'save_pending' ? '已购买，保存尚未完成。重试保存会保留本次购买。'
                : phase === 'applied' ? '已购买并保存。车辆权益已解锁。'
                : phase === 'owned' ? '你已拥有这辆车。'
                : state.drivingLevel < state.requiredDrivingLevel ? '驾驶技能未达到购买要求。'
                : state.balance < state.cost ? '金币不足。' : '确认后购买并保存；取消不扣费。');
            if (phase === 'applied') cue('success');
            return;
        }
        if (result.requiresReconcile || result.error === 'client_timeout') {
            phase = 'unknown'; recoveryToken = result.token || recoveryToken;
            status('正在等待购买结果。请先核对本次操作。');
        } else {
            phase = 'error';
            var messages = {driving_required:'驾驶技能未达到购买要求。', insufficient_funds:'金币不足。',
                catalog_changed:'车辆资料已更新，请重新读取。', context_changed:'场景或存档已切换，请返回车库重新打开。',
                not_sent:'请求未能发送，请重试。', disconnected:'游戏连接暂时不可用。'};
            status(messages[result.error] || '车辆资料暂时不可用，请重新读取或返回车库。');
        }
    }
    function submit() {
        if (busy || phase === 'closed') return;
        if (phase === 'applied' || phase === 'owned') { requestClose(); return; }
        if (phase === 'unknown') {
            if (!recoveryToken) { readSnapshot(); return; }
            request('query', {v:1, token:recoveryToken}, receive); return;
        }
        if (phase === 'error') { readSnapshot(); return; }
        if (!snapshot || phase === 'editing' && !snapshot.canPurchase) return;
        cue('activate');
        request('commit', {v:1, token:snapshot.token, draft:{vehicleId:snapshot.vehicleId}}, receive);
    }
    function requestClose() {
        if (busy || phase === 'closed') return false;
        var sent = false;
        try { sent = Bridge.send({type:'panel', panel:'garage', cmd:'close', panelInstanceId:instance}) !== false; } catch (_) { }
        if (!sent) { status('关闭请求未能发送，请再试一次。'); return false; }
        cue('back'); Panels.close(); return true;
    }
    function cleanup() {
        generation++; phase = 'closed'; busy = false;
        if (element) { var image = byId('image'); image.onload = image.onerror = null; image.removeAttribute('src'); }
        if (mux) mux.destroy(); if (scale) scale.detach();
        mux = scale = snapshot = null; recoveryToken = ''; instance = ''; element = null;
        if (shell) shell.textContent = '';
    }
    Panels.register('garage', {create:create, onOpen:onOpen, onClose:cleanup, onRequestClose:requestClose, onForceClose:cleanup});
    window.GaragePurchasePanel = {debugState:function() { return {phase:phase, busy:busy, state:snapshot, instance:instance}; }};
})();
