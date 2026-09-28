/* 床边闹钟：天穹盘与分段步进器，本地草稿在确认入睡时一次提交。 */
(function() {
    'use strict';
    var R = SleepRuntime, shell, root, scale, mux, instance = '', openerToken = '', recoveryToken = '';
    var state, draft = 360, phase = 'closed', busy = false, generation = 0, drag, closeTimer;
    var disposers = [], errorText = '', invalidTime = false, palette;
    var mood = null, moodTarget = 0, moodFrame = 0, moodAt = 0, moodDuration = 1800, motionPreference;
    var seeded = false, skyDeg = -90, chipSignature = '', lastUsed = null, segBuffer = {hour:'', minute:''}, journeyFrom = null;
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
    // 24 小时天穹环的极坐标：正午在顶、子夜在底、清晨在左、黄昏在右。
    function polar(minutes, radius) {
        var a = (minutes - 720) * .25 * Math.PI / 180;
        return [240 + radius * Math.sin(a), 225 - radius * Math.cos(a)];
    }
    function ringWedge(from, to, inner, outer) {
        var a = polar(from, outer), b = polar(to, outer), c = polar(to, inner), d = polar(from, inner);
        return 'M' + a[0].toFixed(2) + ' ' + a[1].toFixed(2) + 'A' + outer + ' ' + outer + ' 0 0 1 ' + b[0].toFixed(2) + ' ' + b[1].toFixed(2)
            + 'L' + c[0].toFixed(2) + ' ' + c[1].toFixed(2) + 'A' + inner + ' ' + inner + ' 0 0 0 ' + d[0].toFixed(2) + ' ' + d[1].toFixed(2) + 'Z';
    }
    function jitter(seed) { var x = Math.sin(seed * 12.9898) * 43758.5453; return x - Math.floor(x); }
    function watch() {
        var ticks = '', numbers = '', i;
        for (i = 0; i < 60; i++) ticks += '<path class="sleep-tick ' + (i % 5 ? '' : 'major') + '" d="M240 82v' + (i % 5 ? '6' : '13') + '" transform="rotate(' + i * 6 + ' 240 225)"/>';
        for (i = 1; i <= 12; i++) {
            var a = i * Math.PI / 6;
            numbers += '<text font-family="Georgia,serif" font-size="28" text-anchor="middle" dominant-baseline="middle" x="' + (240 + Math.sin(a) * 108) + '" y="' + (226 - Math.cos(a) * 108) + '">' + i + '</text>';
        }
        var discStars = '';
        for (i = 0; i < 26; i++) {
            var sa = Math.PI * (1 + jitter(i + 7)), sr = 12 + jitter(i + 31) * 66;
            discStars += '<circle cx="' + (240 + sr * Math.sin(sa)).toFixed(1) + '" cy="' + (225 + sr * Math.cos(sa)).toFixed(1) + '" r="' + (.8 + jitter(i + 53) * .9).toFixed(2) + '"/>';
        }
        return '<svg id="sleep-dial" class="sleep-dial" viewBox="0 0 480 450" role="img" aria-label="天穹钟面，拖动可设定醒来时刻">'
            + '<defs><radialGradient id="sleep-metal"><stop offset="0" stop-color="#f8e4a8"/><stop offset=".76" stop-color="#b89959"/><stop offset=".89" stop-color="#f2d994"/><stop offset="1" stop-color="#65451e"/></radialGradient>'
            + '<radialGradient id="sleep-enamel" cx=".38" cy=".3" r=".75"><stop stop-color="#fff9e7"/><stop offset="1" stop-color="#d9ccaa"/></radialGradient>'
            + '<linearGradient id="sleep-leather"><stop stop-color="#291f19"/><stop offset=".45" stop-color="#68503b"/><stop offset="1" stop-color="#241b16"/></linearGradient>'
            + '<linearGradient id="sleep-hand-metal"><stop stop-color="#51402b"/><stop offset=".5" stop-color="#d8bd77"/><stop offset="1" stop-color="#342b22"/></linearGradient>'
            + '<clipPath id="sleep-sky-window"><path d="M156 225A84 84 0 0 1 324 225Z"/></clipPath></defs>'
            + '<g class="sleep-strap"><path d="M184 0H296L301 450H179Z" fill="url(#sleep-leather)"/><path d="M192 0L187 450M288 0L293 450" fill="none" stroke="#977b53" stroke-dasharray="3 5"/>'
            + '<path d="M183 45H297M180 407H300" stroke="#b59a66" stroke-width="6"/><g fill="#211811"><circle cx="240" cy="418" r="4"/><circle cx="240" cy="438" r="4"/></g></g>'
            + '<rect x="406" y="208" width="27" height="35" rx="6" fill="url(#sleep-metal)"/><path d="M415 211v29m7-29v29" stroke="#72572c" stroke-width="2"/>'
            + '<circle cx="240" cy="229" r="170" fill="#000" opacity=".35"/><circle cx="240" cy="225" r="166" fill="url(#sleep-metal)"/>'
            + '<g id="sleep-skyring" class="sleep-skyring"></g>'
            + '<path id="sleep-arc-bed" class="sleep-arc-bed" fill="none" hidden/><path id="sleep-arc" class="sleep-arc" fill="none" hidden/><circle id="sleep-now-dot" class="sleep-now-dot" r="4.5" hidden/>'
            + '<circle cx="240" cy="225" r="163.5" fill="none" stroke="#3a2c17" stroke-width="1"/><circle cx="240" cy="225" r="149.5" fill="none" stroke="#3a2c17" stroke-width="1"/>'
            + '<circle cx="240" cy="225" r="149" fill="url(#sleep-enamel)"/>'
            + '<circle cx="240" cy="225" r="139" fill="none" stroke="#baa574" stroke-width=".6"/>'
            + '<g clip-path="url(#sleep-sky-window)"><rect x="150" y="135" width="180" height="90" class="sleep-sky-day"/>'
            + '<g id="sleep-sky-disc" class="sleep-sky-disc"><circle cx="240" cy="225" r="84" class="sleep-sky-disc-day"/>'
            + '<path d="M156 225A84 84 0 0 0 324 225Z" class="sleep-sky-disc-night"/><g class="sleep-disc-stars">' + discStars + '</g>'
            + '<image class="sleep-face-art" href="assets/sleep/day-face.svg" x="208" y="147" width="64" height="64"/>'
            + '<image class="sleep-face-art" href="assets/sleep/night-face.svg" x="204" y="235" width="72" height="72"/></g></g>'
            + '<path d="M156 225H324" stroke="#baa574" stroke-width=".8"/>'
            + '<g class="sleep-dial-ticks">' + ticks + '</g><g class="sleep-dial-numbers">' + numbers + '</g>'
            + '<text x="240" y="313" class="sleep-face-small">沉 睡 · 唤 醒</text>'
            + '<g id="sleep-hour-hand" class="sleep-hand">'
            + '<path d="M240 139l-8 23 4 69 4 19 4-19 4-69z" fill="url(#sleep-hand-metal)" stroke="#453820" stroke-width="1.5"/>'
            + '<path d="M240 164v56" stroke="#e9d9a9" stroke-width="3"/></g>'
            + '<g id="sleep-minute-hand" class="sleep-hand">'
            + '<path d="M240 101l-5 22 2 108 3 24 3-24 2-108z" fill="url(#sleep-hand-metal)" stroke="#453820" stroke-width="1.2"/>'
            + '<path d="M240 123v95" stroke="#f7ebc4" stroke-width="1.7"/></g>'
            + '<circle cx="240" cy="225" r="10" fill="url(#sleep-metal)" stroke="#624b26" stroke-width="1.5"/><circle cx="240" cy="225" r="3" fill="#3d3328"/>'
            + '<path d="M137 132a139 139 0 0 1 178-29" fill="none" stroke="#fff" stroke-opacity=".48" stroke-width="3" pointer-events="none"/>'
            + '</svg>';
    }
    // 天穹环是钟表地理，不随草稿变化；载入配色后一次绘制，夜晚段落撒星。
    function paintSkyRing() {
        if (!palette) return;
        var ring = el('skyring'), segments = '', stars = '', i;
        for (i = 0; i < 48; i++) {
            var m = i * 30 + 15, day = R.visualPhase(m).day;
            var color = R.moodColor(palette['night-bg'], palette['twilight-bg'], palette['day-bg'], day);
            segments += '<path d="' + ringWedge(m - 15, m + 15, 150, 162) + '" fill="rgb(' + color.join(',') + ')"/>';
            if (day < .3) {
                var sr = 151.5 + jitter(i * 3 + 1) * 9, sm = m + (jitter(i * 3 + 2) - .5) * 24;
                var point = polar(sm, sr);
                stars += '<circle cx="' + point[0].toFixed(1) + '" cy="' + point[1].toFixed(1) + '" r="' + (.9 + jitter(i * 3 + 3) * .8).toFixed(2) + '" fill="rgb(' + palette['needle-light'].join(',') + ')" opacity=".85"/>';
            }
        }
        ring.innerHTML = segments + stars;
    }
    function paintArc() {
        var arc = el('arc'), bed = el('arc-bed'), dot = el('now-dot');
        function show(node, yes) { if (yes) node.removeAttribute('hidden'); else node.setAttribute('hidden', ''); }
        if (!state || !R.minute(state.currentMinutes)) { show(arc, false); show(bed, false); show(dot, false); return; }
        var duration = R.sleepDuration(state.currentMinutes, draft);
        var at = polar(state.currentMinutes, 156);
        dot.setAttribute('cx', at[0].toFixed(2)); dot.setAttribute('cy', at[1].toFixed(2)); show(dot, true);
        if (!duration) { show(arc, false); show(bed, false); return; }
        var from = polar(state.currentMinutes, 156), to = polar(draft, 156);
        var d = 'M' + from[0].toFixed(2) + ' ' + from[1].toFixed(2) + 'A156 156 0 ' + (duration > 720 ? 1 : 0) + ' 1 ' + to[0].toFixed(2) + ' ' + to[1].toFixed(2);
        arc.setAttribute('d', d); bed.setAttribute('d', d);
        show(arc, true); show(bed, true);
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
        root.style.setProperty('--sleep-day-weight',p.day);
        root.style.setProperty('--sleep-night-weight',1-p.day);
    }
    function stopMood() { cancelAnimationFrame(moodFrame); moodFrame = 0; }
    function animateMood() {
        moodFrame = 0;
        if (!root || !palette) return;
        var now = performance.now();
        mood = R.followMood(mood, moodTarget, now - moodAt, moodDuration); moodAt = now;
        renderTimeMood(mood);
        if (mood !== moodTarget) moodFrame = requestAnimationFrame(animateMood);
    }
    function updateTimeMood() {
        if (!palette) return;
        var preview = drag ? R.dragPreview(drag.start, 'minute', drag.delta) : draft;
        moodTarget = R.visualPhase(preview).day;
        if (mood === null || motionPreference.matches) {
            stopMood(); mood = moodTarget; renderTimeMood(mood); return;
        }
        if (!moodFrame && mood !== moodTarget) { moodAt = performance.now(); moodFrame = requestAnimationFrame(animateMood); }
    }
    // 天穹盘角度只增不闪跳：绝对设定沿时间前进方向旋转，微调与拖动走最短续接。
    function advanceSky(spin, from, to) {
        if (typeof spin === 'number') { skyDeg += spin; return; }
        var delta = to - from;
        if (spin === 'forward') delta = R.wrap(delta);
        else delta = R.wrap(delta + 720) - 720;
        skyDeg += delta * .25;
    }
    function onOpen(host, data) {
        cleanup();
        instance = data && data.panelInstanceId || ''; openerToken = data && data.token || '';
        phase = 'loading';
        root = document.createElement('section'); root.className = 'sleep-panel'; root.setAttribute('aria-labelledby', 'sleep-title');
        root.innerHTML = '<header class="sleep-header"><div><h1 id="sleep-title">选择醒来的时刻</h1></div>'
            + '<div class="sleep-now">此刻 <strong id="sleep-current">—</strong><span>游戏已暂停</span></div>'
            + '<button id="sleep-close" class="sleep-close" type="button" aria-label="关闭睡眠面板">×</button></header>'
            + '<div class="sleep-body"><div class="sleep-watch-space">' + watch()
            + '<img class="sleep-hg sleep-hg-day" src="assets/sleep/hourglass-day.svg" alt="" aria-hidden="true"/><img class="sleep-hg sleep-hg-night" src="assets/sleep/hourglass-night.svg" alt="" aria-hidden="true"/>'
            + '<p class="sleep-watch-help">转动天穹 · 滚轮与方向键微调 · 可直接输入</p></div>'
            + '<div class="sleep-controls"><p class="sleep-eyebrow">定好闹钟，睡到天亮</p>'
            + '<div class="sleep-stepper" role="group" aria-label="闹钟时间">'
            + '<div class="sleep-seg-col"><button type="button" class="sleep-step" data-step="60" aria-label="小时加一">▲</button>'
            + '<span id="sleep-seg-hour" class="sleep-seg" role="spinbutton" tabindex="0" aria-label="闹钟小时" aria-valuemin="0" aria-valuemax="23">06</span>'
            + '<button type="button" class="sleep-step" data-step="-60" aria-label="小时减一">▼</button></div>'
            + '<span class="sleep-seg-colon">:</span>'
            + '<div class="sleep-seg-col"><button type="button" class="sleep-step" data-step="5" aria-label="分钟加五">▲</button>'
            + '<span id="sleep-seg-minute" class="sleep-seg" role="spinbutton" tabindex="0" aria-label="闹钟分钟" aria-valuemin="0" aria-valuemax="59">00</span>'
            + '<button type="button" class="sleep-step" data-step="-5" aria-label="分钟减五">▼</button></div>'
            + '<button id="sleep-halfday" type="button" aria-label="昼夜对调十二小时">±12h</button></div>'
            + '<div id="sleep-chips" class="sleep-chips" role="group" aria-label="快速选择醒来时间"></div>'
            + '<div class="sleep-adjust" role="group" aria-label="微调闹钟时间"><button type="button" data-adjust="-60">−1 小时</button><button type="button" data-adjust="-5">−5 分</button><button type="button" data-adjust="5">+5 分</button><button type="button" data-adjust="60">+1 小时</button></div>'
            + '<div class="sleep-typein"><label for="sleep-time">直接输入</label><input id="sleep-time" type="text" inputmode="numeric" maxlength="8" placeholder="1830 · 6:30 · +8h" aria-label="直接输入闹钟时间，支持 1830、6:30 或 +8h" spellcheck="false" autocomplete="off"/><span id="sleep-time-hint" class="sleep-time-hint"></span></div>'
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
        listen(el('halfday'), 'click', function() { change(draft + 720, 180); });
        root.querySelectorAll('[data-adjust]').forEach(function(button) { listen(button, 'click', function() { change(draft + Number(button.dataset.adjust), Number(button.dataset.adjust) * .25); }); });
        root.querySelectorAll('[data-step]').forEach(function(button) {
            listen(button, 'click', function(event) {
                var delta = Number(button.dataset.step);
                if (Math.abs(delta) === 5 && event.shiftKey) delta = delta > 0 ? 1 : -1;
                change(draft + delta, delta * .25);
            });
        });
        listen(el('chips'), 'click', function(event) {
            var button = event.target.closest('[data-preset]');
            if (button && !button.disabled) change(Number(button.dataset.preset), 'forward');
        });
        listen(el('time'), 'input', previewText);
        listen(el('time'), 'change', applyText);
        listen(el('time'), 'keydown', function(event) {
            if (event.key === 'Enter') { event.preventDefault(); event.stopPropagation(); if (applyText()) el('confirm').focus(); }
        });
        ['hour', 'minute'].forEach(function(name) {
            var seg = el('seg-' + name);
            listen(seg, 'click', function() { if (editable()) seg.focus(); });
            listen(seg, 'focus', function() { segBuffer[name] = ''; });
            listen(seg, 'wheel', function(event) {
                if (!editable()) return;
                event.preventDefault();
                var down = event.deltaY > 0 ? -1 : 1;
                var delta = name === 'hour' ? down * 60 : down * (event.shiftKey ? 1 : 5);
                change(draft + delta, delta * .25);
            }, {passive:false});
            listen(seg, 'keydown', function(event) {
                if (!editable()) return;
                var key = event.key;
                if (/^[0-9]$/.test(key)) { event.preventDefault(); event.stopPropagation(); typeDigit(name, key); return; }
                if (key === 'ArrowLeft' || key === 'ArrowRight') {
                    event.preventDefault(); event.stopPropagation();
                    el('seg-' + (name === 'hour' ? 'minute' : 'hour')).focus(); return;
                }
                var delta = key === 'ArrowUp' ? 1 : key === 'ArrowDown' ? -1 : 0;
                if (delta) {
                    event.preventDefault(); event.stopPropagation();
                    delta *= name === 'hour' ? 60 : (event.shiftKey ? 1 : 5);
                    change(draft + delta, delta * .25);
                }
            });
        });
        listen(el('dial'), 'pointerdown', beginDrag); listen(el('dial'), 'pointermove', moveDrag);
        listen(el('dial'), 'pointerup', endDrag); listen(el('dial'), 'pointercancel', cancelDrag);
        listen(el('dial'), 'lostpointercapture', cancelDrag); listen(window, 'blur', cancelDrag);
        listen(root, 'keydown', function(event) {
            if (event.key === 'Enter' && event.target.tagName !== 'BUTTON' && event.target.tagName !== 'INPUT' && editable() && !invalidTime) {
                event.preventDefault(); submit();
            }
        });
        if (!palette) { phase = 'resource_error'; errorText = '界面资源暂未准备好，请关闭后重新打开。'; refresh(); return; }
        paintSkyRing();
        skyDeg = (draft - 720) * .25;
        refresh();
        requestAnimationFrame(function() { requestAnimationFrame(function() { if (root) root.classList.add('sky-ready'); }); });
        readSnapshot();
    }
    function editable() { return phase === 'editing' && !busy && palette && state && state.canSleep; }
    // spin：数字=天穹精确转角，'forward'=沿入睡方向，'nearest'=最短续接（微调与键入）。
    function change(value, spin) {
        if (!editable()) return;
        var from = draft; draft = R.wrap(value); invalidTime = false; errorText = '';
        advanceSky(spin == null ? 'nearest' : spin, from, draft);
        refresh();
    }
    function typeDigit(name, digit) {
        var buffer = segBuffer[name] + digit, value = Number(buffer);
        if (name === 'hour') {
            if (buffer.length === 1 && value > 2) { segBuffer.hour = ''; setSegment('hour', value); el('seg-minute').focus(); return; }
            if (buffer.length >= 2) { segBuffer.hour = ''; if (value > 23) { flashSegment('hour'); return; } setSegment('hour', value); el('seg-minute').focus(); return; }
            segBuffer.hour = buffer; return;
        }
        if (buffer.length === 1 && value > 5) { segBuffer.minute = ''; setSegment('minute', value); return; }
        if (buffer.length >= 2) { segBuffer.minute = ''; if (value > 59) { flashSegment('minute'); return; } setSegment('minute', value); return; }
        segBuffer.minute = buffer;
    }
    function setSegment(name, value) {
        change(name === 'hour' ? value * 60 + draft % 60 : Math.floor(draft / 60) * 60 + value, 'nearest');
    }
    function flashSegment(name) {
        var seg = el('seg-' + name);
        seg.classList.add('is-invalid');
        setTimeout(function() { if (root) seg.classList.remove('is-invalid'); }, 320);
    }
    function previewText() {
        var hint = el('time-hint'), value = el('time').value;
        if (!value.trim()) { hint.textContent = ''; return; }
        var parsed = R.parseTimeText(value, state ? state.currentMinutes : 0);
        hint.textContent = parsed === null ? '无法识别' : '将设为 ' + R.format(parsed);
    }
    function applyText() {
        if (!editable()) return false;
        var value = el('time').value, hint = el('time-hint');
        if (!value.trim()) { hint.textContent = ''; return false; }
        var parsed = R.parseTimeText(value, state ? state.currentMinutes : 0);
        if (parsed === null) { invalidTime = true; errorText = '可输入 1830、6:30 或 +8h 这类时间。'; refresh(); return false; }
        hint.textContent = '';
        change(parsed, 'forward');
        return true;
    }
    function pointerAngle(event) {
        var matrix = el('dial').getScreenCTM();
        if (!matrix) return null;
        var point = new DOMPoint(event.clientX, event.clientY).matrixTransform(matrix.inverse());
        if (Math.hypot(point.x - 240, point.y - 225) < 20) return null;
        return (Math.atan2(point.x - 240, 225 - point.y) * 180 / Math.PI + 360) % 360;
    }
    // 整盘即 scrubber：按住天穹任意位置拨动时间，不分时针分针。
    function beginDrag(event) {
        if (!editable() || event.button !== 0 || drag) return;
        var angle = pointerAngle(event); if (angle === null) return;
        event.preventDefault();
        drag = {id:event.pointerId, start:draft, previous:angle, delta:0};
        el('dial').setPointerCapture(event.pointerId); root.classList.add('is-dragging'); refresh();
    }
    function moveDrag(event) {
        if (!drag || event.pointerId !== drag.id || !editable()) return;
        var angle = pointerAngle(event); if (angle === null) return;
        drag.delta += R.angleDelta(drag.previous, angle); drag.previous = angle;
        var from = draft;
        draft = R.dragMinutes(drag.start, 'minute', drag.delta, event.shiftKey); invalidTime = false; errorText = '';
        advanceSky('nearest', from, draft);
        refresh();
    }
    function endDrag(event) {
        if (!drag || event.pointerId !== drag.id) return;
        moveDrag(event); var id = drag.id; drag = null; root.classList.remove('is-dragging');
        if (el('dial').hasPointerCapture(id)) el('dial').releasePointerCapture(id);
        updateTimeMood();
    }
    function cancelDrag() {
        if (!drag) return;
        var id = drag.id, from = draft; draft = drag.start; drag = null;
        if (root) {
            root.classList.remove('is-dragging');
            if (el('dial').hasPointerCapture(id)) el('dial').releasePointerCapture(id);
            advanceSky('nearest', from, draft); refresh();
        }
    }
    function renderChips() {
        if (!state) return;
        var chips = R.computeChips(state.currentMinutes, lastUsed);
        var signature = chips.map(function(chip) { return chip.id + chip.minutes; }).join('|');
        if (signature === chipSignature) return;
        chipSignature = signature;
        el('chips').innerHTML = chips.map(function(chip) {
            var icon = chip.id === 'dawn' ? '<img class="sleep-chip-symbol" src="assets/sleep/day-face.svg" alt=""/>'
                : chip.id === 'dusk' ? '<img class="sleep-chip-symbol" src="assets/sleep/night-face.svg" alt=""/>'
                : chip.id === 'plus8' ? '<img class="sleep-chip-symbol" src="assets/sleep/hourglass-day.svg" alt=""/>'
                : '<svg class="sleep-chip-symbol" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5a7.5 7.5 0 1 1-7.2 5.3M4.6 4.5v5h5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
            return '<button type="button" data-preset="' + chip.minutes + '" data-chip="' + chip.id + '">' + icon
                + '<span>' + chip.label + '<strong>' + chip.time + '</strong></span></button>';
        }).join('');
    }
    function refresh() {
        if (!root) return;
        var a = R.angles(draft), disabled = !editable(), journey = root.classList.contains('is-journey');
        if (!journey) {
            el('hour-hand').style.transform = 'rotate(' + a.hour + 'deg)';
            el('minute-hand').style.transform = 'rotate(' + a.minute + 'deg)';
            el('sky-disc').style.transform = 'rotate(' + skyDeg + 'deg)';
        }
        renderChips(); paintArc();
        el('seg-hour').textContent = String(Math.floor(draft / 60)).padStart(2, '0');
        el('seg-minute').textContent = String(draft % 60).padStart(2, '0');
        el('seg-hour').setAttribute('aria-valuenow', Math.floor(draft / 60));
        el('seg-minute').setAttribute('aria-valuenow', draft % 60);
        el('seg-hour').setAttribute('aria-valuetext', R.format(draft)); el('seg-minute').setAttribute('aria-valuetext', R.format(draft));
        ['hour', 'minute'].forEach(function(name) {
            el('seg-' + name).setAttribute('aria-disabled', String(disabled));
            el('seg-' + name).setAttribute('tabindex', disabled ? '-1' : '0');
        });
        if (document.activeElement !== el('time')) el('time').value = R.format(draft);
        el('current').textContent = state ? R.format(state.currentMinutes) : '—';
        root.querySelectorAll('.sleep-controls button, .sleep-controls input').forEach(function(node) { node.disabled = disabled; });
        root.querySelectorAll('[data-preset]').forEach(function(node) { node.setAttribute('aria-pressed', String(Number(node.dataset.preset) === draft)); });
        el('error').textContent = errorText; el('error').hidden = !errorText;
        el('status').hidden = !!errorText;
        el('status').textContent = phase === 'loading' ? '正在准备床铺…' : phase === 'unknown' ? '核对结果后才能再次入睡。'
            : phase === 'expired' ? errors.context_changed : phase === 'applied' ? '一觉醒来，已是 ' + R.format(draft) + '。'
            : state && !state.canSleep ? errors.cycle_disabled : '将于 ' + R.format(draft) + ' 醒来 · 共睡 ' + R.formatDuration(R.sleepDuration(state.currentMinutes, draft)) + '。' + (state && state.cyclePaused ? '昼夜时钟当前保持冻结。' : '');
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
            if (incoming.phase === 'editing' && !seeded) {
                seeded = true;
                draft = R.defaultDraft(incoming.currentMinutes, lastUsed);
                skyDeg = (draft - 720) * .25;
                if (palette) { mood = moodTarget = R.visualPhase(draft).day; renderTimeMood(mood); }
            } else draft = incoming.phase === 'editing' ? draft : incoming.targetMinutes;
            if (incoming.phase === 'applied') lastUsed = incoming.targetMinutes;
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
        recoveryToken = state.token; journeyFrom = state.currentMinutes;
        request('commit', {v:1, token:state.token, targetMinutes:draft}, function(result) { receive(result, true); });
    }
    // 入睡即时间流逝：天穹与指针先落回入睡前刻，再沿入睡方向快进到目标；沙漏立柱浮现。
    function finish() {
        var current = generation, reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        var journey = !reduced && R.minute(journeyFrom) ? R.wrap(draft - journeyFrom) : 0;
        if (journey > 0) {
            var hourHand = el('hour-hand'), minuteHand = el('minute-hand'), disc = el('sky-disc');
            var hourFrom = (journeyFrom % 720) / 2, minuteFrom = (journeyFrom % 60) * 6;
            skyDeg -= journey * .25;
            hourHand.style.transform = 'rotate(' + hourFrom + 'deg)';
            minuteHand.style.transform = 'rotate(' + minuteFrom + 'deg)';
            disc.style.transform = 'rotate(' + skyDeg + 'deg)';
            void root.offsetWidth;
            root.classList.add('is-journey');
            skyDeg += journey * .25;
            disc.style.transform = 'rotate(' + skyDeg + 'deg)';
            hourHand.style.transform = 'rotate(' + (hourFrom + journey * .5) + 'deg)';
            minuteHand.style.transform = 'rotate(' + (minuteFrom + journey * 6) + 'deg)';
        }
        root.classList.add('is-asleep');
        closeTimer = setTimeout(function() { if (current === generation && phase === 'applied') requestClose(); },
            reduced ? 0 : journey > 0 ? Math.round(moodDuration * .7 + 900) : 500);
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
        mux = scale = state = root = palette = null; instance = openerToken = recoveryToken = errorText = ''; draft = 360; invalidTime = false;
        seeded = false; chipSignature = ''; segBuffer = {hour:'', minute:''}; journeyFrom = null;
        if (shell) shell.textContent = '';
    }
    Panels.register('sleep', {create:create, onOpen:onOpen, onRebind:onOpen, onClose:cleanup, onRequestClose:requestClose, onForceClose:cleanup});
    window.SleepPanel = {debugState:function() { return {phase:phase, busy:busy, draft:draft, dragging:!!drag, moodAnimating:!!moodFrame,
        sky:Math.round(skyDeg * 100) / 100, seeded:seeded, token:state && state.token}; }};
})();
