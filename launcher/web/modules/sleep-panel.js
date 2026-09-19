/* 床边闹钟：SVG 表壳与独立指针，本地草稿在确认入睡时一次提交。 */
(function() {
    'use strict';
    var R = SleepRuntime, shell, root, scale, mux, instance = '', openerToken = '', recoveryToken = '';
    var state, draft = 360, phase = 'closed', busy = false, generation = 0, hand = 'minute', drag, closeTimer;
    var disposers = [], errorText = '', invalidTime = false, palette;
    var mood = null, moodTarget = 0, moodFrame = 0, moodAt = 0, moodDuration = 1800, motionPreference;
    var errors = {
        cycle_disabled:'昼夜循环已关闭。请先在游戏设置中开启，再选择醒来时间。',
        context_changed:'已经离开这张床，请关闭面板后重新打开。', stale_token:'这次休息已失效，请从床铺重新打开。',
        clock_unavailable:'游戏时钟暂时不可用，请重新打开面板。', sleep_unavailable:'睡眠服务尚未准备好。',
        disconnected:'游戏连接已断开，请恢复连接后再试。', not_sent:'请求未能发送，请再试一次。',
        timeout:'尚未确认入睡结果，请先核对上次结果。', client_timeout:'尚未确认入睡结果，请先核对上次结果。',
        malformed_response:'暂时无法确认入睡结果，请先核对。', reconcile_required:'请先核对上次入睡结果。',
        panel_instance_expired:'面板已失效，请从床铺重新打开。'
    };
    function el(id) { return root.querySelector('#sleep-' + id); }
    function listen(node, event, handler, options) {
        node.addEventListener(event, handler, options);
        disposers.push(function() { node.removeEventListener(event, handler, options); });
    }
    function watch() {
        var ticks = '', numbers = '', i;
        for (i = 0; i < 60; i++) ticks += '<path class="sleep-tick ' + (i % 5 ? '' : 'major') + '" d="M240 82v' + (i % 5 ? '6' : '13') + '" transform="rotate(' + i * 6 + ' 240 225)"/>';
        for (i = 1; i <= 12; i++) {
            var a = i * Math.PI / 6;
            numbers += '<text font-family="Georgia,serif" font-size="28" text-anchor="middle" dominant-baseline="middle" x="' + (240 + Math.sin(a) * 108) + '" y="' + (226 - Math.cos(a) * 108) + '">' + i + '</text>';
        }
        return '<svg id="sleep-dial" class="sleep-dial" viewBox="0 0 480 450" role="group" aria-label="拖动指针设置闹钟">'
            + '<defs><radialGradient id="sleep-metal"><stop offset="0" stop-color="#f8e4a8"/><stop offset=".76" stop-color="#b89959"/><stop offset=".89" stop-color="#f2d994"/><stop offset="1" stop-color="#65451e"/></radialGradient>'
            + '<radialGradient id="sleep-enamel" cx=".38" cy=".3" r=".75"><stop stop-color="#fff9e7"/><stop offset="1" stop-color="#d9ccaa"/></radialGradient>'
            + '<linearGradient id="sleep-leather"><stop stop-color="#291f19"/><stop offset=".45" stop-color="#68503b"/><stop offset="1" stop-color="#241b16"/></linearGradient>'
            + '<linearGradient id="sleep-hand-metal"><stop stop-color="#51402b"/><stop offset=".5" stop-color="#d8bd77"/><stop offset="1" stop-color="#342b22"/></linearGradient>'
            + '<clipPath id="sleep-moon-crop"><circle cx="240" cy="225" r="86"/></clipPath></defs>'
            + '<g class="sleep-strap"><path d="M184 0H296L301 450H179Z" fill="url(#sleep-leather)"/><path d="M192 0L187 450M288 0L293 450" fill="none" stroke="#977b53" stroke-dasharray="3 5"/>'
            + '<path d="M183 45H297M180 407H300" stroke="#b59a66" stroke-width="6"/><g fill="#211811"><circle cx="240" cy="418" r="4"/><circle cx="240" cy="438" r="4"/></g></g>'
            + '<rect x="406" y="208" width="27" height="35" rx="6" fill="url(#sleep-metal)"/><path d="M415 211v29m7-29v29" stroke="#72572c" stroke-width="2"/>'
            + '<circle cx="240" cy="229" r="170" fill="#000" opacity=".35"/><circle cx="240" cy="225" r="166" fill="url(#sleep-metal)"/>'
            + '<circle cx="240" cy="225" r="154" fill="#6b532e"/><circle cx="240" cy="225" r="149" fill="url(#sleep-enamel)"/>'
            + '<circle cx="240" cy="225" r="139" fill="none" stroke="#baa574" stroke-width=".6"/>'
            + '<g class="sleep-starwork"><circle cx="240" cy="225" r="77"/><path d="M240 148L307 263H173ZM240 302L173 187H307Z"/><circle cx="240" cy="225" r="68"/></g>'
            + '<image class="sleep-face-art sleep-sun" href="assets/sleep/day-face.svg" x="164" y="149" width="152" height="152"/>'
            + '<image class="sleep-face-art sleep-moon" href="assets/sleep/night-face.svg" x="151" y="136" width="178" height="178" clip-path="url(#sleep-moon-crop)"/>'
            + '<g class="sleep-dial-ticks">' + ticks + '</g><g class="sleep-dial-numbers">' + numbers + '</g>'
            + '<text x="240" y="313" class="sleep-face-small">沉 睡 · 唤 醒</text>'
            + '<g id="sleep-hour-hand" data-hand="hour" class="sleep-hand" role="slider" tabindex="0" aria-label="闹钟小时" aria-valuemin="0" aria-valuemax="23">'
            + '<path class="sleep-hand-hit" d="M240 145V248"/><path d="M240 139l-8 23 4 69 4 19 4-19 4-69z" fill="url(#sleep-hand-metal)" stroke="#453820" stroke-width="1.5"/>'
            + '<path d="M240 164v56" stroke="#e9d9a9" stroke-width="3"/></g>'
            + '<g id="sleep-minute-hand" data-hand="minute" class="sleep-hand" role="slider" tabindex="0" aria-label="闹钟分钟" aria-valuemin="0" aria-valuemax="59">'
            + '<path class="sleep-hand-hit" d="M240 107V251"/><path d="M240 101l-5 22 2 108 3 24 3-24 2-108z" fill="url(#sleep-hand-metal)" stroke="#453820" stroke-width="1.2"/>'
            + '<path d="M240 123v95" stroke="#f7ebc4" stroke-width="1.7"/></g>'
            + '<circle cx="240" cy="225" r="10" fill="url(#sleep-metal)" stroke="#624b26" stroke-width="1.5"/><circle cx="240" cy="225" r="3" fill="#3d3328"/>'
            + '<path d="M137 132a139 139 0 0 1 178-29" fill="none" stroke="#fff" stroke-opacity=".48" stroke-width="3" pointer-events="none"/>'
            + '</svg>';
    }
    function create() { shell = document.createElement('div'); shell.className = 'panel-scale-shell sleep-scale-shell'; return shell; }
    function readPalette() {
        var data = window.SleepArtPalette;
        if (!data || data.v !== 1 || !data.colors) return null;
        var valid = ['day-bg','night-bg','day-surface','night-surface','day-ink','night-ink','day-muted','night-muted','day-brass','night-brass',
            'day-line','night-line','twilight','twilight-bg','twilight-surface','twilight-enamel-upper','twilight-enamel-lower',
            'day-enamel-upper','day-enamel-lower','night-paper','night-rim','dial-ink','night-numeral','needle-dark','needle-light'].every(function(key) {
            var color = data.colors[key];
            return Array.isArray(color) && color.length === 3 && color.every(function(v) { return Number.isFinite(v) && v >= 0 && v <= 255; });
        });
        return valid ? data.colors : null;
    }
    function renderTimeMood(day) {
        if (!palette) return;
        var p = R.phaseAtDay(day), mix = R.mix;
        function shade(name) { return mix(palette['night-'+name],palette['day-'+name],p.day); }
        function set(name, rgb) { root.style.setProperty('--sleep-'+name, 'rgb(' + rgb.join(',') + ')'); }
        var bg = R.moodColor(palette['night-bg'],palette['twilight-bg'],palette['day-bg'],p.day);
        var surface = R.moodColor(palette['night-surface'],palette['twilight-surface'],palette['day-surface'],p.day);
        var upper = R.moodColor(palette['night-paper'],palette['twilight-enamel-upper'],palette['day-enamel-upper'],p.day);
        var lower = R.moodColor(palette['night-rim'],palette['twilight-enamel-lower'],palette['day-enamel-lower'],p.day);
        set('bg',bg); set('surface',surface); set('line',shade('line'));
        set('ink',R.readable([bg],palette['day-ink'],palette['night-ink']));
        set('control-ink',R.readable([surface],palette['day-ink'],palette['night-ink']));
        set('muted',R.readable([bg],palette['day-muted'],palette['night-muted']));
        var brass = R.readable([bg],palette['day-brass'],palette['night-brass']);
        set('brass',brass);
        // 入睡操作保持金底深字，不跟随正文的明暗极性翻转。
        set('primary-bg',palette['night-brass']); set('primary-ink',palette['needle-dark']);
        set('control-brass',R.readable([surface],palette['day-brass'],palette['night-brass']));
        set('enamel-upper',upper); set('enamel-lower',lower);
        var dialInk = R.readable([upper,lower],palette['dial-ink'],palette['night-numeral'],3);
        set('dial-color',dialInk);
        var needleInk = R.readable([upper,lower],palette['needle-dark'],palette['needle-light'],3);
        set('needle-color',needleInk); set('needle-glint',mix(needleInk,shade('brass'),.12));
        root.style.setProperty('--sleep-sun-opacity',p.sun);
        root.style.setProperty('--sleep-moon-opacity',p.moon);
        root.style.setProperty('--sleep-day-weight',p.day);
        root.style.setProperty('--sleep-night-weight',1-p.day);
    }
    function stopMood() { cancelAnimationFrame(moodFrame); moodFrame = 0; }
    function animateMood(now) {
        moodFrame = 0;
        if (!root || !palette) return;
        mood = R.followMood(mood, moodTarget, now - moodAt, moodDuration); moodAt = now;
        renderTimeMood(mood);
        if (mood !== moodTarget) moodFrame = requestAnimationFrame(animateMood);
    }
    function updateTimeMood() {
        if (!palette) return;
        var preview = drag ? R.dragPreview(drag.start, drag.hand, drag.delta) : draft;
        moodTarget = R.visualPhase(preview).day;
        if (mood === null || motionPreference.matches) {
            stopMood(); mood = moodTarget; renderTimeMood(mood); return;
        }
        if (!moodFrame && mood !== moodTarget) { moodAt = performance.now(); moodFrame = requestAnimationFrame(animateMood); }
    }
    function onOpen(host, data) {
        cleanup();
        instance = data && data.panelInstanceId || ''; openerToken = data && data.token || '';
        phase = 'loading';
        root = document.createElement('section'); root.className = 'sleep-panel'; root.setAttribute('aria-labelledby', 'sleep-title');
        root.innerHTML = '<header class="sleep-header"><div><h1 id="sleep-title">选择醒来的时刻</h1></div>'
            + '<div class="sleep-now">此刻 <strong id="sleep-current">—</strong><span>游戏已暂停</span></div>'
            + '<button id="sleep-close" class="sleep-close" type="button" aria-label="关闭睡眠面板">×</button></header>'
            + '<div class="sleep-body"><div class="sleep-watch-space">' + watch() + '<p class="sleep-watch-help">拖动指针 · 设定醒来的时刻</p></div>'
            + '<div class="sleep-controls"><p class="sleep-eyebrow">拨动指针，定好闹钟</p><label for="sleep-time" class="sleep-time-label">闹钟时间</label>'
            + '<div class="sleep-readout"><input id="sleep-time" type="text" inputmode="numeric" maxlength="5" value="06:00" aria-label="闹钟时间，24小时制，例如06:30" spellcheck="false" autocomplete="off"/>'
            + '<button id="sleep-halfday" type="button" aria-label="切换上午或下午">上午</button></div>'
            + '<div class="sleep-hand-choice" role="group" aria-label="选择要调整的指针"><button type="button" data-select-hand="hour">时针</button><button type="button" data-select-hand="minute" aria-pressed="true">分针</button>'
            + '<span>拖动吸附 5 分钟</span></div><div class="sleep-adjust" role="group" aria-label="微调闹钟时间"><button type="button" data-adjust="-60">−1 小时</button><button type="button" data-adjust="-1">−1 分钟</button><button type="button" data-adjust="1">+1 分钟</button><button type="button" data-adjust="60">+1 小时</button></div>'
            + '<div class="sleep-presets" role="group" aria-label="快速选择醒来时间"><button type="button" data-preset="360"><img class="sleep-preset-symbol" src="assets/sleep/day-face.svg" alt=""/><span>清晨<strong>06:00</strong></span></button>'
            + '<button type="button" data-preset="1140"><img class="sleep-preset-symbol" src="assets/sleep/night-face.svg" alt=""/><span>夜晚<strong>19:00</strong></span></button></div>'
            + '<p id="sleep-status" class="sleep-status" role="status">正在准备床铺…</p><p id="sleep-error" class="sleep-error" role="alert" hidden></p></div></div>'
            + '<footer class="sleep-footer"><p>设好闹钟，再安心入睡。<span>取消会放弃本次调整</span></p><button id="sleep-cancel" class="sleep-cancel" type="button">暂不休息</button>'
            + '<button id="sleep-confirm" class="sleep-confirm" type="button">设好闹钟，入睡</button></footer><div class="sleep-curtain" aria-hidden="true"></div>';
        shell.appendChild(root);
        scale = PanelScale.attach(shell, 1024, 576);
        palette = readPalette();
        motionPreference = window.matchMedia('(prefers-reduced-motion: reduce)');
        listen(motionPreference, 'change', updateTimeMood);
        var duration = getComputedStyle(root).getPropertyValue('--sleep-mood-duration').trim();
        var parsedDuration = parseFloat(duration) * (/ms$/.test(duration) ? 1 : 1000);
        moodDuration = Number.isFinite(parsedDuration) && parsedDuration > 0 ? parsedDuration : 1800;
        mux = new R.RequestMux({panelInstanceId:instance, send:function(message) { return Bridge.send(message); }});
        listen(el('close'), 'click', requestClose); listen(el('cancel'), 'click', requestClose); listen(el('confirm'), 'click', submit);
        listen(el('halfday'), 'click', function() { change(R.wrap(draft + 720)); });
        root.querySelectorAll('[data-adjust]').forEach(function(button) { listen(button, 'click', function() { change(draft + Number(button.dataset.adjust)); }); });
        root.querySelectorAll('[data-preset]').forEach(function(button) { listen(button, 'click', function() { change(Number(button.dataset.preset)); }); });
        root.querySelectorAll('[data-select-hand]').forEach(function(button) { listen(button, 'click', function() { hand = button.dataset.selectHand; refresh(); }); });
        listen(el('time'), 'change', applyText);
        listen(el('time'), 'keydown', function(event) { if (event.key === 'Enter') { event.preventDefault(); event.stopPropagation(); applyText(); el('confirm').focus(); } });
        listen(el('dial'), 'pointerdown', beginDrag); listen(el('dial'), 'pointermove', moveDrag);
        listen(el('dial'), 'pointerup', endDrag); listen(el('dial'), 'pointercancel', cancelDrag);
        listen(el('dial'), 'lostpointercapture', cancelDrag); listen(window, 'blur', cancelDrag);
        ['hour','minute'].forEach(function(name) {
            listen(el(name + '-hand'), 'keydown', function(event) {
                if (!editable()) return;
                var delta = event.key === 'ArrowUp' || event.key === 'ArrowRight' ? 1 : event.key === 'ArrowDown' || event.key === 'ArrowLeft' ? -1 : 0;
                if (delta) { event.preventDefault(); event.stopPropagation(); hand = name; change(draft + delta * (name === 'hour' ? 60 : (event.shiftKey ? 5 : 1))); }
            });
        });
        if (!palette) { phase = 'resource_error'; errorText = '界面资源暂未准备好，请关闭后重新打开。'; refresh(); return; }
        refresh(); readSnapshot();
    }
    function editable() { return phase === 'editing' && !busy && palette && state && state.canSleep; }
    function change(value) { if (!editable()) return; draft = R.wrap(value); invalidTime = false; errorText = ''; refresh(); }
    function applyText() {
        if (!editable()) return;
        var match = /^(\d{1,2}):(\d{2})$/.exec(el('time').value.trim());
        if (!match || Number(match[1]) > 23 || Number(match[2]) > 59) { invalidTime = true; errorText = '请输入 00:00 至 23:59，例如 06:30。'; refresh(); return; }
        change(Number(match[1]) * 60 + Number(match[2]));
    }
    function pointerAngle(event) {
        var matrix = el('dial').getScreenCTM();
        if (!matrix) return null;
        var point = new DOMPoint(event.clientX, event.clientY).matrixTransform(matrix.inverse());
        if (Math.hypot(point.x - 240, point.y - 225) < 20) return null;
        return (Math.atan2(point.x - 240, 225 - point.y) * 180 / Math.PI + 360) % 360;
    }
    function beginDrag(event) {
        if (!editable() || event.button !== 0 || drag) return;
        var target = event.target.closest('[data-hand]');
        // 在表盘任意位置按住即可拨动当前选中的指针，不要求精确点中细针。
        if (target) hand = target.dataset.hand;
        var angle = pointerAngle(event); if (angle === null) return;
        event.preventDefault();
        drag = {id:event.pointerId, start:draft, previous:angle, delta:0, hand:hand};
        el('dial').setPointerCapture(event.pointerId); root.classList.add('is-dragging'); refresh();
    }
    function moveDrag(event) {
        if (!drag || event.pointerId !== drag.id || !editable()) return;
        var angle = pointerAngle(event); if (angle === null) return;
        drag.delta += R.angleDelta(drag.previous, angle); drag.previous = angle;
        draft = R.dragMinutes(drag.start, drag.hand, drag.delta, event.shiftKey); invalidTime = false; errorText = ''; refresh();
    }
    function endDrag(event) {
        if (!drag || event.pointerId !== drag.id) return;
        moveDrag(event); var id = drag.id; drag = null; root.classList.remove('is-dragging');
        if (el('dial').hasPointerCapture(id)) el('dial').releasePointerCapture(id);
        updateTimeMood();
    }
    function cancelDrag() {
        if (!drag) return;
        var id = drag.id; draft = drag.start; drag = null;
        if (root) { root.classList.remove('is-dragging'); if (el('dial').hasPointerCapture(id)) el('dial').releasePointerCapture(id); refresh(); }
    }
    function refresh() {
        if (!root) return;
        var a = R.angles(draft), disabled = !editable();
        el('hour-hand').setAttribute('transform', 'rotate(' + a.hour + ' 240 225)');
        el('minute-hand').setAttribute('transform', 'rotate(' + a.minute + ' 240 225)');
        ['hour','minute'].forEach(function(name) {
            var node = el(name + '-hand'); node.classList.toggle('selected', hand === name);
            node.setAttribute('aria-valuenow', name === 'hour' ? Math.floor(draft / 60) : draft % 60);
            node.setAttribute('aria-valuetext', R.format(draft)); node.setAttribute('aria-disabled', String(disabled));
            node.setAttribute('tabindex', disabled ? '-1' : '0');
        });
        el('time').value = R.format(draft); el('halfday').textContent = draft < 720 ? '上午' : '下午';
        el('current').textContent = state ? R.format(state.currentMinutes) : '—';
        root.querySelectorAll('.sleep-controls button, .sleep-controls input').forEach(function(node) { node.disabled = disabled; });
        root.querySelectorAll('[data-select-hand]').forEach(function(node) { node.setAttribute('aria-pressed', String(node.dataset.selectHand === hand)); });
        root.querySelectorAll('[data-preset]').forEach(function(node) { node.setAttribute('aria-pressed', String(Number(node.dataset.preset) === draft)); });
        el('error').textContent = errorText; el('error').hidden = !errorText;
        el('status').hidden = !!errorText;
        el('status').textContent = phase === 'loading' ? '正在准备床铺…' : phase === 'unknown' ? '核对结果后才能再次入睡。'
            : phase === 'expired' ? errors.context_changed : phase === 'applied' ? '一觉醒来，已是 ' + R.format(draft) + '。'
            : state && !state.canSleep ? errors.cycle_disabled : '将于 ' + R.format(draft) + ' 醒来。' + (state && state.cyclePaused ? '昼夜时钟当前保持冻结。' : '');
        el('confirm').textContent = busy ? '正在处理…' : phase === 'unknown' ? '核对上次结果' : phase === 'applied' ? '醒来'
            : phase === 'error' ? '重新读取' : '设好闹钟，入睡';
        el('confirm').disabled = busy || phase === 'loading' || phase === 'expired' || phase === 'resource_error' || phase === 'editing' && (disabled || invalidTime);
        el('cancel').disabled = el('close').disabled = busy;
        updateTimeMood();
        root.setAttribute('aria-busy', String(busy));
    }
    function request(cmd, payload, callback) {
        var current = generation; busy = true; errorText = ''; refresh();
        mux.request(cmd, payload, function(result) { if (current !== generation || phase === 'closed') return; busy = false; callback(result); refresh(); });
    }
    function readSnapshot() {
        request('snapshot', {v:1, token:openerToken}, function(result) {
            if (result && result.requiresReconcile && result.recoveryToken) { recoveryToken = result.recoveryToken; phase = 'unknown'; receive(result, false); }
            else receive(result, false);
        });
    }
    function receive(result, fromWrite) {
        var incoming = R.normalizeState(result);
        if (incoming) {
            state = incoming; phase = incoming.phase; recoveryToken = incoming.token;
            draft = incoming.phase === 'editing' ? draft : incoming.targetMinutes;
            if (incoming.phase === 'expired' && incoming.token !== openerToken) { phase = 'loading'; readSnapshot(); return; }
            if (incoming.phase === 'editing' && incoming.token !== openerToken) { phase = 'loading'; readSnapshot(); return; }
            if (phase === 'applied') finish();
            return;
        }
        var code = result && result.error || 'malformed_response';
        if (result && result.recoveryToken) recoveryToken = result.recoveryToken;
        if (result && result.requiresReconcile || fromWrite && code === 'malformed_response') phase = 'unknown';
        else if (/^(stale_token|context_changed|panel_instance_expired)$/.test(code)) phase = 'expired';
        else phase = state ? 'editing' : 'error';
        errorText = errors[code] || '暂时无法完成休息，请稍后重试。';
    }
    function submit() {
        if (busy) return;
        cancelDrag();
        if (phase === 'applied') { requestClose(); return; }
        if (phase === 'unknown') { request('query', {v:1, token:recoveryToken || openerToken}, function(result) { receive(result, false); }); return; }
        if (phase === 'error') { readSnapshot(); return; }
        if (!editable() || invalidTime) return;
        recoveryToken = state.token;
        request('commit', {v:1, token:state.token, targetMinutes:draft}, function(result) { receive(result, true); });
    }
    function finish() {
        root.classList.add('is-asleep');
        var current = generation, reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        closeTimer = setTimeout(function() { if (current === generation && phase === 'applied') requestClose(); }, reduced ? 0 : 500);
    }
    function requestClose(reason) {
        if (busy || phase === 'closed') return false;
        if (reason === 'escape' && drag) { cancelDrag(); return false; }
        var accepted = false;
        try { accepted = Bridge.send({type:'panel', cmd:'close', panel:'sleep', panelInstanceId:instance}) !== false; } catch (_) {}
        if (!accepted) { root.classList.remove('is-asleep'); errorText = '关闭请求未能发送，请再试一次。'; refresh(); return false; }
        Panels.close(); return true;
    }
    function cleanup() {
        generation++; cancelDrag(); phase = 'closed'; busy = false;
        stopMood(); mood = null; motionPreference = null;
        clearTimeout(closeTimer); closeTimer = null;
        disposers.forEach(function(dispose) { dispose(); }); disposers = [];
        if (mux) mux.destroy(); if (scale) scale.detach();
        mux = scale = state = root = palette = null; instance = openerToken = recoveryToken = errorText = ''; draft = 360; hand = 'minute'; invalidTime = false;
        if (shell) shell.textContent = '';
    }
    Panels.register('sleep', {create:create, onOpen:onOpen, onRebind:onOpen, onClose:cleanup, onRequestClose:requestClose, onForceClose:cleanup});
    window.SleepPanel = {debugState:function() { return {phase:phase, busy:busy, draft:draft, hand:hand, dragging:!!drag, moodAnimating:!!moodFrame, token:state && state.token}; }};
})();
