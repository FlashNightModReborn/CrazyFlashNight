/* 医务室整形：本地草稿 + 现役装扮预览 + AS2 一次性付费与保存。 */
(function() {
    'use strict';
    var Controls = CharacterIdentityControls;
    var Runtime = PlasticSurgeryRuntime;
    var shell, element, mux, scale, renderer, manifest;
    var snapshot, draft, submitted, phase = 'closed', busy = false, composing = false, generation = 0, instance = '', errorText = '';
    var disposers = [], needsSnapshot = false, recoveryToken = '';
    var errors = {
        disconnected:'游戏连接已断开，请恢复连接后重试。', timeout:'提交结果尚未确认，请先核对上次结果。',
        client_timeout:'提交结果尚未确认，请先核对上次结果。', not_sent:'请求未能发送，请重试。',
        insufficient_funds:'K 点不足，整形需要 5 K 点。', stale_state:'角色资料已变化，请重新读取。',
        stale_token:'本次操作已失效，请重新读取角色资料。', context_changed:'角色或场景已变化，请关闭后重新打开整形。',
        refresh_failed:'外观刷新失败，本次未扣费，请稍后重试。', no_change:'请先修改姓名、性别或身高。',
        save_pending:'整形已生效，保存尚未成功。重试保存不会再次扣费。',
        actor_unavailable:'角色尚未准备好，请关闭后重新打开。', invalid_payload:'角色资料不完整，请重新读取。',
        malformed_response:'暂时无法确认操作结果，请核对上次结果。', reconcile_required:'请先核对上次提交结果。',
        save_unavailable:'保存功能暂时不可用，本次未扣费。', surgery_unavailable:'整形服务尚未准备好，请稍后重试。'
    };
    function byId(id) { return element.querySelector('#surgery-' + id); }
    function copy(value) { return JSON.parse(JSON.stringify(value)); }
    function setStatus(text) { if (element) byId('status').textContent = text; }
    function cue(name) { if (window.BootstrapAudio) window.BootstrapAudio.cue(name); }
    function setError(text) {
        errorText = text || '';
        if (element) { byId('error').textContent = errorText; byId('error').hidden = !errorText; }
    }
    // 换装反馈：性别/身高重绘后一道扫描光掠过预览舞台，遮住合成硬切；reduced-motion 由 CSS 关闭。
    function flashPreviewSwap() {
        var stage = element && element.querySelector('.appearance-service-preview-stage');
        if (!stage) return;
        stage.classList.remove('appearance-service-swap-flash');
        void stage.offsetWidth;
        stage.classList.add('appearance-service-swap-flash');
    }
    function same(a, b) { return a && b && a.characterName === b.characterName && a.gender === b.gender && a.height === b.height; }
    function create() { shell = document.createElement('div'); shell.className = 'panel-scale-shell surgery-scale-shell appearance-service-shell'; return shell; }
    function onOpen(host, data) {
        cleanup();
        instance = data && data.panelInstanceId || '';
        phase = 'loading'; busy = false;
        element = document.createElement('section'); element.className = 'surgery-panel appearance-service-panel'; element.setAttribute('aria-labelledby', 'surgery-title');
        element.innerHTML = '<header class="appearance-service-header"><div class="appearance-service-heading">'
            + '<span class="appearance-service-kicker">医务室 / 角色整形</span><h1 id="surgery-title">整形手术</h1>'
            + '<p class="appearance-service-current" id="surgery-current">正在读取角色资料…</p></div>'
            + '<div class="appearance-service-status surgery-balance">持有 <strong id="surgery-balance">—</strong> K 点</div>'
            + '<button type="button" class="appearance-service-close" aria-label="关闭整形手术" id="surgery-close">×</button></header>'
            + '<div class="appearance-service-body surgery-main"><aside class="appearance-service-preview-pane" aria-labelledby="surgery-preview-title">'
            + '<div class="appearance-service-section-title"><h2 id="surgery-preview-title">整形后外观</h2><span class="appearance-service-badge">本地预览</span></div>'
            + '<div class="appearance-service-preview-stage"><canvas class="appearance-service-preview-canvas" id="surgery-canvas" role="img" aria-label="整形后角色预览"></canvas>'
            + '<p class="appearance-service-preview-fallback" id="surgery-preview-fallback">正在准备角色预览…</p></div>'
            + '<div class="appearance-service-preview-facts surgery-preview-meta"><strong id="surgery-preview-identity">—</strong>'
            + '<span id="surgery-preview-note">保留当前装备和发型</span></div></aside>'
            + '<form class="appearance-service-pane" id="surgery-form" novalidate>'
            + '<div class="appearance-service-section-title"><h2 id="surgery-fields-title">调整角色资料</h2><span class="appearance-service-count">姓名 · 性别 · 身高</span></div>'
            + '<div class="surgery-fields">'
            + Controls.nameMarkup('surgery', false) + Controls.genderMarkup('surgery') + Controls.heightMarkup('surgery', false, 'surgery-fields-title')
            + '<div class="surgery-change"><span>本次修改</span><p id="surgery-summary">正在读取角色资料…</p></div></div></form></div>'
            + '<footer class="appearance-service-footer"><div class="appearance-service-messages surgery-feedback"><strong id="surgery-price">整形费用：5 K 点</strong>'
            + '<p class="appearance-service-error" id="surgery-error" role="alert" hidden></p>'
            + '<p class="appearance-service-hint" id="surgery-status" role="status" aria-live="polite">正在读取角色资料…</p></div>'
            + '<div class="appearance-service-actions"><button type="button" class="appearance-service-button" id="surgery-cancel">取消</button>'
            + '<button type="button" id="surgery-confirm" class="appearance-service-button primary surgery-confirm">确认整形</button></div></footer>';
        shell.appendChild(element);
        scale = PanelScale.attach(shell, 1024, 576);
        mux = new Runtime.RequestMux({send:function(message) { return Bridge.send(message); }, panelInstanceId:instance});
        byId('close').addEventListener('click', requestClose);
        byId('cancel').addEventListener('click', requestClose);
        byId('confirm').addEventListener('click', submit);
        byId('form').addEventListener('submit', function(event) { event.preventDefault(); if (!composing) submit(); });
        disposers.push(Controls.bindNameInput(byId('character-name'), {
            onComposition:function(value) { composing = value; },
            onChange:function(value) { if (editable()) { errorText = ''; draft.characterName = value; refresh(); } }, onEnter:submit
        }));
        disposers.push(Controls.bindGender(element.querySelectorAll('input[name="surgery-gender"]'), function(value) {
            if (editable()) { errorText = ''; draft.gender = value; refresh(); render(); flashPreviewSwap(); cue('select'); }
        }));
        disposers.push(Controls.bindHeight(byId('height'), function(value) {
            if (editable()) { errorText = ''; draft.height = value; refresh(); render(); flashPreviewSwap(); }
        }));
        // 滑条拖动每帧都触发 input，select 音效只在一次调整落定（change）时播。
        byId('height').addEventListener('change', function() { if (editable()) cue('select'); });
        var current = generation;
        DressupDollRenderer.loadManifest('assets/dressup/manifest.json').then(function(value) {
            if (current !== generation || phase === 'closed') return;
            manifest = value;
            renderer = CharacterAppearancePreview.create(byId('canvas'), {manifest:manifest, animate:false,
                ignoreCssTransforms:true, onRender:function(meta) {
                    if (current !== generation || !element) return;
                    var missing = meta && (meta.missing > 0 || (meta.missingItems && meta.missingItems.length));
                    byId('preview-fallback').hidden = !!(meta && meta.drawnImages > 0 && !meta.failedImages && !meta.pendingImages && !missing);
                    if (meta && (meta.failedImages || missing)) byId('preview-fallback').textContent = '部分外观素材暂未能显示，实际装备和发型会保留。';
                    byId('preview-note').textContent = meta && meta.hairHidden
                        ? '头盔遮住发型，原发型保留' : '保留当前装备和发型';
                }});
            render();
        }).catch(function() {
            if (current === generation && element) byId('preview-fallback').textContent = '预览暂时不可用，仍可修改角色资料。';
        });
        refresh(); readSnapshot();
    }
    function editable() { return !!draft && phase === 'editing' && !busy; }
    function refresh() {
        if (!element) return;
        element.setAttribute('data-state', busy ? 'busy' : phase === 'unknown' || phase === 'save_pending' ? 'reconcile' : phase === 'error' || errorText ? 'error' : 'ready');
        byId('error').textContent = errorText;
        byId('error').hidden = !errorText;
        var locked = !editable();
        element.querySelectorAll('#surgery-form input').forEach(function(input) { input.disabled = locked; });
        byId('close').disabled = busy; byId('cancel').disabled = busy;
        byId('cancel').textContent = phase === 'editing' || phase === 'loading' ? '取消' : '关闭';
        if (draft) {
            byId('character-name').value = draft.characterName;
            element.querySelectorAll('input[name="surgery-gender"]').forEach(function(input) { input.checked = input.value === draft.gender; });
            byId('height').value = String(draft.height);
            byId('height').setAttribute('aria-valuetext', draft.height + ' 厘米');
            byId('height-value').textContent = draft.height + ' 厘米';
            byId('canvas').style.setProperty('--identity-height-scale', String(Controls.previewScale(draft.height)));
            byId('canvas').setAttribute('aria-label', (draft.gender === 'female' ? '女性' : '男性') + '角色，身高' + draft.height + '厘米');
            byId('preview-identity').textContent = (draft.gender === 'female' ? '女性' : '男性') + ' · ' + draft.height + ' 厘米';
            var problems = Controls.validateProfile(draft);
            byId('error-characterName').textContent = problems.characterName || '';
            byId('character-name').setAttribute('aria-invalid', problems.characterName ? 'true' : 'false');
            var changes = [];
            if (snapshot) {
                if (draft.characterName !== snapshot.current.characterName) changes.push('姓名：' + snapshot.current.characterName + ' → ' + draft.characterName);
                if (draft.gender !== snapshot.current.gender) changes.push('性别：' + (draft.gender === 'female' ? '女性' : '男性'));
                if (draft.height !== snapshot.current.height) changes.push('身高：' + snapshot.current.height + ' → ' + draft.height + ' 厘米');
            }
            byId('summary').textContent = changes.length ? changes.join('；') : '尚未修改。确认后，角色外观会立即更新。';
            byId('balance').textContent = snapshot ? snapshot.balance.toLocaleString('zh-CN') : '—';
            if (snapshot) byId('current').textContent = '当前角色：' + snapshot.current.characterName;
        }
        var invalid = !draft || Object.keys(Controls.validateProfile(draft)).length > 0;
        byId('confirm').textContent = busy ? '正在处理…' : phase === 'applied' ? '关闭' : needsSnapshot ? '重新读取角色' : phase === 'unknown' ? '核对上次结果'
            : phase === 'save_pending' ? '重试保存' : '确认整形 · 5 K 点';
        byId('confirm').disabled = busy || phase === 'loading' || (!needsSnapshot && phase === 'editing'
            && (invalid || same(draft, snapshot && snapshot.current)));
    }
    function render() {
        if (!renderer || !draft || !snapshot) return;
        renderer.renderProfile(draft, snapshot.portrait.equipment,
            {'脸型':(draft.gender === 'female' ? '女' : '男') + '变装-基本脸型', '发型':snapshot.portrait.hair},
            {zoom:1, margin:12});
    }
    function request(cmd, payload, callback) {
        var current = generation;
        busy = true; errorText = ''; refresh();
        mux.request(cmd, payload, function(result) {
            if (current !== generation || phase === 'closed') return;
            busy = false; callback(result); refresh();
        });
    }
    function readSnapshot() {
        needsSnapshot = false;
        request('snapshot', {v:1}, function(result) {
            if (result && result.error === 'reconcile_required' && typeof result.token === 'string') {
                recoveryToken = result.token;
                request('query', {v:1, token:result.token}, function(recovered) { receive(recovered, false); });
            } else receive(result, false);
        });
    }
    function receive(result, fromWrite) {
        var state = Runtime.normalizeState(result);
        if (state) {
            snapshot = state;
            recoveryToken = state.token;
            phase = state.phase;
            draft = copy(state.draft);
            submitted = state.phase === 'save_pending' ? copy(state.draft) : submitted;
            render();
            setError(state.phase === 'save_pending' ? errors.save_pending : '');
            if (state.phase === 'applied') {
                setStatus('整形已生效并保存。');
                if (fromWrite) cue('success');
                if (typeof Toast !== 'undefined') Toast.add('整形已生效并保存。');
                requestClose(true);
            } else {
                if (fromWrite && state.phase === 'save_pending') cue('unknown');
                setStatus(state.phase === 'save_pending' ? '保存重试不会重复扣费。' : '编辑和取消不扣费；确认后立即生效。');
            }
            return;
        }
        var code = result && result.error || 'malformed_response';
        var unknown = !!(result && result.requiresReconcile || fromWrite && code === 'malformed_response');
        if (unknown) phase = 'unknown';
        else if (snapshot) phase = 'editing';
        else { phase = 'error'; needsSnapshot = true; }
        if (/^(stale_state|stale_token|context_changed|invalid_payload)$/.test(code)) needsSnapshot = true;
        setError(errors[code] || '暂时无法完成操作，请重试或重新打开整形。');
        setStatus(phase === 'unknown' ? '核对上次提交结果前不会重复扣费。'
            : needsSnapshot ? '请重新读取角色资料。' : '编辑和取消不扣费；确认后立即生效。');
        if (fromWrite) cue(unknown ? 'unknown' : code === 'not_sent' ? 'illegal' : 'rejected');
    }
    function submit() {
        if (busy || composing || phase === 'closed') return;
        if (phase === 'applied') { requestClose(); return; }
        if (needsSnapshot) { readSnapshot(); return; }
        if (phase === 'unknown') {
            if (!recoveryToken) { readSnapshot(); return; }
            request('query', {v:1, token:recoveryToken}, function(result) { receive(result, true); });
            return;
        }
        if (!snapshot || !draft) return;
        if (phase === 'editing') {
            draft.characterName = draft.characterName.trim();
            if (Object.keys(Controls.validateProfile(draft)).length || same(draft, snapshot.current)) { refresh(); return; }
            submitted = copy(draft);
        }
        if (!submitted) return;
        cue('activate');
        request('commit', {v:1, token:snapshot.token, draft:copy(submitted)}, function(result) { receive(result, true); });
    }
    // 取消/关闭（含 ESC/遮罩，首参为 reason 值）播 back；applied 成功路径显式传 true 保持静默（已播 success，一动作一声）。
    function requestClose(silent) {
        if (busy || phase === 'closed') return false;
        var accepted = false;
        try { accepted = Bridge.send({type:'panel', cmd:'close', panel:'surgery', panelInstanceId:instance}) !== false; }
        catch (error) { accepted = false; }
        if (!accepted) { setStatus('关闭请求未能发送，请再试一次。'); return false; }
        if (silent !== true) cue('back');
        Panels.close();
        return true;
    }
    function cleanup() {
        generation++; phase = 'closed'; busy = false; composing = false;
        disposers.forEach(function(dispose) { dispose(); }); disposers = [];
        if (mux) mux.destroy(); if (renderer) renderer.destroy(); if (scale) scale.detach();
        mux = renderer = scale = manifest = snapshot = draft = submitted = null;
        needsSnapshot = false; instance = ''; recoveryToken = ''; errorText = '';
        if (shell) shell.textContent = '';
        element = null;
    }
    Panels.register('surgery', {create:create, onOpen:onOpen, onClose:cleanup, onRequestClose:requestClose, onForceClose:cleanup});
    window.PlasticSurgeryPanel = {debugState:function() { return {phase:phase, busy:busy, draft:draft && copy(draft), token:snapshot && snapshot.token}; }};
})();
