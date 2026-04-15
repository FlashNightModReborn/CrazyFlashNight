var LockboxPanel = (function() {
    'use strict';

    var _el;
    var _refs = {};
    var _state = null;
    var _loopId = 0;
    var _poolPromise = null;
    var _pointerReleaseBound = false;
    var _helpOpen = true;
    var _hudOpen = false;
    var _loadToken = 0;
    var _panelOpen = false;
    var _metaDirty = true;

    var DEFAULT_INIT = {
        mode: 'dev',
        profile: 'standard',
        source: 'runtime',
        familySeed: (Date.now() >>> 0),
        variantIndex: 0,
        hintMode: 'off',
        debug: true
    };

    Panels.register('lockbox', {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: function() { closePanel(); },
        onForceClose: cleanup
    });

    function createDOM() {
        _el = document.createElement('div');
        _el.className = 'lockbox-panel';
        _el.innerHTML = [
            '<div class="lockbox-header">',
                '<div>',
                    '<div class="lockbox-kicker">// WEBVIEW PROTOTYPE //</div>',
                    '<div class="lockbox-title">高安箱协议破解器</div>',
                '</div>',
                '<div class="lockbox-header-right">',
                    '<button class="lockbox-chrome-btn" type="button" data-action="toggle-help">规则</button>',
                    '<button class="lockbox-chrome-btn" type="button" data-action="toggle-hud">调试</button>',
                    '<button class="lockbox-chrome-btn" type="button" data-action="toggle-mute">♪ 开</button>',
                    '<div class="lockbox-phase-badge" id="lockbox-phase-badge">INIT</div>',
                    '<button class="lockbox-close-btn" type="button">×</button>',
                '</div>',
            '</div>',
            '<div class="lockbox-help-panel" id="lockbox-help-panel">',
                '<div class="lockbox-help-card">',
                    '<div class="lockbox-help-head">',
                        '<div>',
                            '<div class="lockbox-help-kicker">// RULE BRIEF //</div>',
                            '<div class="lockbox-help-title">玩法速览</div>',
                        '</div>',
                        '<button class="lockbox-chrome-btn" type="button" data-action="toggle-help">关闭</button>',
                    '</div>',
                    '<div class="lockbox-help-grid">',
                        '<div class="lockbox-help-item"><b>1.</b> 第一手只能从顶行开始，先找入口。</div>',
                        '<div class="lockbox-help-item"><b>2.</b> 第二手起必须在“同列 / 同行”之间交替跳点。</div>',
                        '<div class="lockbox-help-item"><b>3.</b> 每次合法点击都会写入 Buffer；A/B 同时命中就是主成功。</div>',
                        '<div class="lockbox-help-item"><b>4.</b> C 只算 bonus，主成功后可以再贪，不会反杀主成功。</div>',
                        '<div class="lockbox-help-item"><b>5.</b> 非法点不耗 Buffer，但会推高 Trace；70% 锁 bonus，100% 前没做出 A/B 就失败。</div>',
                        '<div class="lockbox-help-item emphasis">推荐测试流：先在观察阶段看 A/B 是否重叠，再点“开始注入”。</div>',
                    '</div>',
                    '<div class="lockbox-help-actions">',
                        '<button type="button" class="lockbox-btn lockbox-btn-primary" data-action="toggle-help">知道了，开始测试</button>',
                    '</div>',
                '</div>',
            '</div>',
            '<div class="lockbox-main">',
                '<div class="lockbox-grid-pane">',
                    '<div class="lockbox-stage-meta">',
                        '<div id="lockbox-axis-label">顶行入口待机</div>',
                        '<div id="lockbox-stage-hint">规划 A/B 重叠后再开始注入。</div>',
                    '</div>',
                    '<div class="lockbox-quickbar">',
                        '<div class="lockbox-profile-switch" id="lockbox-profile-switch">',
                            '<button type="button" class="lockbox-chip-btn" data-profile-switch="standard">标准</button>',
                            '<button type="button" class="lockbox-chip-btn" data-profile-switch="elite7">精英7</button>',
                            '<button type="button" class="lockbox-chip-btn" data-profile-switch="elite6">精英6</button>',
                        '</div>',
                        '<div class="lockbox-control-strip">',
                            '<button type="button" class="lockbox-btn lockbox-btn-small lockbox-toolbar-btn lockbox-btn-primary" data-action="start">开始</button>',
                            '<button type="button" class="lockbox-btn lockbox-btn-small lockbox-toolbar-btn lockbox-btn-accent" data-action="submit">提交</button>',
                            '<button type="button" class="lockbox-btn lockbox-btn-small lockbox-toolbar-btn" data-action="reroll">重生</button>',
                            '<button type="button" class="lockbox-btn lockbox-btn-small lockbox-toolbar-btn" data-action="export">导出</button>',
                            '<button type="button" class="lockbox-btn lockbox-btn-small lockbox-toolbar-btn" data-action="hint">指引:关</button>',
                        '</div>',
                        '<div class="lockbox-profile-note" id="lockbox-profile-note">当前档位：standard</div>',
                    '</div>',
                    '<div class="lockbox-guide-note" id="lockbox-guide-note">指引关闭。</div>',
                    '<div class="lockbox-grid-shell">',
                        '<div class="lockbox-trace-frame" id="lockbox-trace-frame"></div>',
                        '<div class="lockbox-trace-rail left">',
                            '<div class="lockbox-trace-rail-title">TRACE</div>',
                            '<div class="lockbox-trace-rail-track">',
                                '<div class="lockbox-trace-rail-fill" id="lockbox-trace-rail-fill"></div>',
                                '<div class="lockbox-trace-rail-mark lock">70</div>',
                                '<div class="lockbox-trace-rail-mark burn">100</div>',
                            '</div>',
                            '<div class="lockbox-trace-rail-meta" id="lockbox-trace-rail-left-meta"></div>',
                        '</div>',
                        '<div class="lockbox-grid-wrap">',
                            '<div class="lockbox-grid" id="lockbox-grid"></div>',
                        '</div>',
                        '<div class="lockbox-trace-rail right">',
                            '<div class="lockbox-trace-rail-title" id="lockbox-trace-rail-right-title">MODE C</div>',
                            '<div class="lockbox-trace-module-stack" id="lockbox-trace-module-stack"></div>',
                            '<div class="lockbox-rail-finisher" id="lockbox-rail-finisher">',
                                '<div class="lockbox-rail-finisher-label">HOLD</div>',
                                '<div class="lockbox-rail-finisher-track" id="lockbox-rail-finisher-track">',
                                    '<div class="lockbox-rail-finisher-zone good-low"></div>',
                                    '<div class="lockbox-rail-finisher-zone perfect"></div>',
                                    '<div class="lockbox-rail-finisher-zone good-high"></div>',
                                    '<div class="lockbox-rail-finisher-progress" id="lockbox-rail-finisher-progress"></div>',
                                '</div>',
                                '<div class="lockbox-rail-finisher-meta" id="lockbox-rail-finisher-meta">PRESS</div>',
                            '</div>',
                        '</div>',
                        '<div class="lockbox-trace-footer" id="lockbox-trace-footer"></div>',
                    '</div>',
                '</div>',
                '<div class="lockbox-side-pane">',
                    '<div class="lockbox-result-card" id="lockbox-result-card"></div>',
                    '<section class="lockbox-side-section">',
                        '<div class="lockbox-side-title">目标序列</div>',
                        '<div id="lockbox-sequences"></div>',
                    '</section>',
                    '<section class="lockbox-side-section">',
                        '<div class="lockbox-side-title">Buffer</div>',
                        '<div id="lockbox-buffer"></div>',
                    '</section>',
                    '<section class="lockbox-side-section">',
                        '<div class="lockbox-side-title">Trace</div>',
                        '<div class="lockbox-trace-bar"><div class="lockbox-trace-fill" id="lockbox-trace-fill"></div></div>',
                        '<div class="lockbox-trace-meta" id="lockbox-trace-meta"></div>',
                    '</section>',
                    '<section class="lockbox-side-section">',
                        '<div class="lockbox-side-title">运行状态</div>',
                        '<div class="lockbox-status" id="lockbox-status"></div>',
                    '</section>',
                '</div>',
            '</div>',
            '<div class="lockbox-hud">',
                '<div class="lockbox-hud-row">',
                    '<label>档位',
                        '<select id="lockbox-profile">',
                            '<option value="standard">standard</option>',
                            '<option value="elite7">elite7</option>',
                            '<option value="elite6">elite6</option>',
                        '</select>',
                    '</label>',
                    '<label>题源',
                        '<select id="lockbox-source">',
                            '<option value="runtime">runtime</option>',
                            '<option value="baked">baked</option>',
                        '</select>',
                    '</label>',
                    '<label>familySeed <input id="lockbox-family-seed" type="number" min="0" step="1"></label>',
                    '<label>variant <input id="lockbox-variant" type="number" min="0" step="1"></label>',
                    '<button type="button" class="lockbox-btn lockbox-btn-small" data-action="apply-hud">应用</button>',
                '</div>',
                '<div class="lockbox-hud-grid">',
                    '<div class="lockbox-hud-card">',
                        '<div class="lockbox-side-title">Solver 指标</div>',
                        '<div id="lockbox-metrics"></div>',
                    '</div>',
                    '<div class="lockbox-hud-card">',
                        '<div class="lockbox-side-title">运行指标</div>',
                        '<div id="lockbox-session-metrics"></div>',
                    '</div>',
                '</div>',
            '</div>'
        ].join('');

        bindDomRefs();
        bindEvents();
        return _el;
    }

    function bindDomRefs() {
        _refs.closeBtn = _el.querySelector('.lockbox-close-btn');
        _refs.helpToggle = _el.querySelector('[data-action="toggle-help"]');
        _refs.hudToggle = _el.querySelector('[data-action="toggle-hud"]');
        _refs.muteToggle = _el.querySelector('[data-action="toggle-mute"]');
        _refs.helpPanel = _el.querySelector('#lockbox-help-panel');
        _refs.grid = _el.querySelector('#lockbox-grid');
        _refs.phaseBadge = _el.querySelector('#lockbox-phase-badge');
        _refs.axisLabel = _el.querySelector('#lockbox-axis-label');
        _refs.stageHint = _el.querySelector('#lockbox-stage-hint');
        _refs.profileSwitch = _el.querySelector('#lockbox-profile-switch');
        _refs.profileNote = _el.querySelector('#lockbox-profile-note');
        _refs.guideNote = _el.querySelector('#lockbox-guide-note');
        _refs.hintBtn = _el.querySelector('[data-action="hint"]');
        _refs.traceFrame = _el.querySelector('#lockbox-trace-frame');
        _refs.traceRailFill = _el.querySelector('#lockbox-trace-rail-fill');
        _refs.traceRailLeftMeta = _el.querySelector('#lockbox-trace-rail-left-meta');
        _refs.traceRailRightTitle = _el.querySelector('#lockbox-trace-rail-right-title');
        _refs.traceModuleStack = _el.querySelector('#lockbox-trace-module-stack');
        _refs.railFinisher = _el.querySelector('#lockbox-rail-finisher');
        _refs.railFinisherTrack = _el.querySelector('#lockbox-rail-finisher-track');
        _refs.railFinisherProgress = _el.querySelector('#lockbox-rail-finisher-progress');
        _refs.railFinisherMeta = _el.querySelector('#lockbox-rail-finisher-meta');
        _refs.traceFooter = _el.querySelector('#lockbox-trace-footer');
        _refs.traceFill = _el.querySelector('#lockbox-trace-fill');
        _refs.traceMeta = _el.querySelector('#lockbox-trace-meta');
        _refs.sequences = _el.querySelector('#lockbox-sequences');
        _refs.buffer = _el.querySelector('#lockbox-buffer');
        _refs.status = _el.querySelector('#lockbox-status');
        _refs.resultCard = _el.querySelector('#lockbox-result-card');
        _refs.profile = _el.querySelector('#lockbox-profile');
        _refs.source = _el.querySelector('#lockbox-source');
        _refs.familySeed = _el.querySelector('#lockbox-family-seed');
        _refs.variant = _el.querySelector('#lockbox-variant');
        _refs.metrics = _el.querySelector('#lockbox-metrics');
        _refs.sessionMetrics = _el.querySelector('#lockbox-session-metrics');
        _refs.hud = _el.querySelector('.lockbox-hud');
    }

    function bindEvents() {
        _refs.closeBtn.addEventListener('click', closePanel);

        _el.addEventListener('click', function(event) {
            var btn = event.target.closest('[data-action], [data-profile-switch]');
            if (!btn) return;
            var action = btn.getAttribute('data-action');
            if (action === 'toggle-help') toggleHelp();
            else if (action === 'toggle-hud') toggleHud();
            else if (action === 'toggle-mute') toggleMute();
            else if (action === 'start') startInject();
            else if (action === 'submit') requestSubmit();
            else if (action === 'reroll') rerollPuzzle();
            else if (action === 'export') exportCurrentJson();
            else if (action === 'hint') toggleHintMode();
            else if (action === 'apply-hud') loadPuzzle(getHudRequest());

            var profileId = btn.getAttribute('data-profile-switch');
            if (profileId) switchProfile(profileId);
        });

        _refs.grid.addEventListener('pointerdown', function(event) {
            var cellEl = event.target.closest('.lockbox-cell');
            if (!cellEl) return;
            event.preventDefault();
            onCellPointerDown(Number(cellEl.getAttribute('data-r')), Number(cellEl.getAttribute('data-c')));
        });

        _refs.railFinisherTrack.addEventListener('pointerdown', function(event) {
            if (!_state || _state.phase !== 'FINISHER' || _state.finisher.holding) return;
            event.preventDefault();
            beginFinisherHold(event.pointerId);
        });

        _refs.railFinisherTrack.addEventListener('pointerup', function(event) {
            if (!_state || !_state.finisher.holding) return;
            event.preventDefault();
            finishFinisherHold(false);
        });

        if (!_pointerReleaseBound) {
            window.addEventListener('pointerup', function() {
                if (_state && _state.finisher && _state.finisher.holding) finishFinisherHold(false);
            });
            _pointerReleaseBound = true;
        }
    }

    function onOpen(el, initData) {
        var data = normalizeInitData(initData || DEFAULT_INIT);
        _panelOpen = true;
        _helpOpen = true;
        _hudOpen = false;
        _refs.profile.value = data.profile;
        _refs.source.value = data.source;
        _refs.familySeed.value = String(data.familySeed >>> 0);
        _refs.variant.value = String(data.variantIndex | 0);
        setProfileUi(data.profile, data.source);
        renderChromeToggles();
        if (typeof LockboxAudio !== 'undefined') LockboxAudio.resume();
        loadPuzzle(data);
        startLoop();
    }

    function cleanup() {
        _panelOpen = false;
        _loadToken++;
        stopLoop();
        _state = null;
        if (typeof LockboxAudio !== 'undefined') {
            LockboxAudio.stopAmbient();
            LockboxAudio.stopHeartbeat();
        }
    }

    function closePanel() {
        cleanup();
        Panels.close();
        Bridge.send({ type: 'panel', cmd: 'close', panel: 'lockbox' });
    }

    function toggleHelp() {
        _helpOpen = !_helpOpen;
        renderChromeToggles();
    }

    function toggleHud() {
        _hudOpen = !_hudOpen;
        renderChromeToggles();
    }

    function toggleMute() {
        if (typeof LockboxAudio === 'undefined') return;
        LockboxAudio.setMuted(!LockboxAudio.isMuted());
        renderChromeToggles();
    }

    function renderChromeToggles() {
        if (_refs.helpPanel) _refs.helpPanel.classList.toggle('visible', _helpOpen);
        if (_refs.hud) _refs.hud.classList.toggle('visible', _hudOpen);
        if (_refs.helpToggle) _refs.helpToggle.textContent = _helpOpen ? '收起规则' : '规则';
        if (_refs.hudToggle) _refs.hudToggle.textContent = _hudOpen ? '收起调试' : '调试';
        if (_refs.muteToggle) {
            var muted = (typeof LockboxAudio !== 'undefined') && LockboxAudio.isMuted();
            _refs.muteToggle.textContent = muted ? '♪ 关' : '♪ 开';
            _refs.muteToggle.classList.toggle('muted', muted);
        }
    }

    function normalizeInitData(initData) {
        var data = {};
        var key;
        for (key in DEFAULT_INIT) data[key] = DEFAULT_INIT[key];
        for (key in initData) data[key] = initData[key];
        data.familySeed = sanitizeUInt(data.familySeed, Date.now() >>> 0);
        data.variantIndex = sanitizeUInt(data.variantIndex, 0);
        if (!LockboxCore.PROFILE_DEFS[data.profile]) data.profile = 'standard';
        if (data.source !== 'runtime' && data.source !== 'baked') data.source = 'runtime';
        if (data.hintMode !== 'next' && data.hintMode !== 'path') data.hintMode = 'off';
        return data;
    }

    function sanitizeUInt(value, fallback) {
        var n = Number(value);
        if (isNaN(n) || !isFinite(n) || n < 0) return fallback >>> 0;
        return (Math.floor(n) >>> 0);
    }

    function getHudRequest() {
        return normalizeInitData({
            profile: _refs.profile.value,
            source: _refs.source.value,
            familySeed: sanitizeUInt(_refs.familySeed.value, Date.now() >>> 0),
            variantIndex: sanitizeUInt(_refs.variant.value, 0),
            hintMode: _state ? _state.hintMode : 'off',
            mode: 'dev',
            debug: true
        });
    }

    function rerollPuzzle() {
        var request = buildRerollRequest();
        _helpOpen = false;
        renderChromeToggles();
        loadPuzzle(request);
    }

    function toggleHintMode() {
        if (!_state) return;
        if (_state.hintMode === 'off') _state.hintMode = 'next';
        else if (_state.hintMode === 'next') _state.hintMode = 'path';
        else _state.hintMode = 'off';
        _state.request.hintMode = _state.hintMode;
        renderAll();
    }

    function switchProfile(profileId) {
        if (!LockboxCore.PROFILE_DEFS[profileId]) return;
        var request = _state ? normalizeInitData(_state.request) : getHudRequest();
        request.profile = profileId;
        request.source = _refs.source.value || request.source;
        request.familySeed = sanitizeUInt(_state ? _state.puzzle.familySeed : request.familySeed, Date.now() >>> 0);
        request.variantIndex = 0;
        request.mode = 'dev';
        request.debug = true;
        request.hintMode = _state ? _state.hintMode : 'off';

        _refs.profile.value = request.profile;
        _refs.source.value = request.source;
        _refs.familySeed.value = String(request.familySeed >>> 0);
        _refs.variant.value = '0';
        _helpOpen = false;
        renderChromeToggles();
        loadPuzzle(request);
    }

    function buildRerollRequest() {
        var current = _state ? normalizeInitData(_state.request) : getHudRequest();
        current.profile = _refs.profile.value || current.profile;
        current.source = _refs.source.value || current.source;
        current.familySeed = sanitizeUInt(_state ? _state.puzzle.familySeed : current.familySeed, Date.now() >>> 0);
        current.variantIndex = sanitizeUInt((_state ? _state.puzzle.variantIndex : current.variantIndex) + 1, 0);
        current.mode = 'dev';
        current.debug = true;
        current.hintMode = _state ? _state.hintMode : 'off';

        _refs.profile.value = current.profile;
        _refs.source.value = current.source;
        _refs.familySeed.value = String(current.familySeed >>> 0);
        _refs.variant.value = String(current.variantIndex | 0);
        return current;
    }

    function loadPuzzle(request) {
        var token = ++_loadToken;
        setProfileUi(request.profile, request.source);
        setBusyState('生成/加载题目中…');
        resolvePuzzle(request, token).then(function(packageData) {
            if (token !== _loadToken || !_panelOpen) return;
            beginRun(packageData, request);
        }).catch(function(error) {
            if (token !== _loadToken || !_panelOpen) return;
            setBusyState('题目生成失败: ' + (error && error.message ? error.message : String(error)));
        });
    }

    function resolvePuzzle(request, token) {
        if (request.source === 'baked') {
            return loadBakedPool().then(function(pool) {
                if (token !== _loadToken || !_panelOpen) return null;
                var picked = pickBakedVariant(pool, request);
                if (picked) {
                    request.familySeed = picked.familySeed >>> 0;
                    request.variantIndex = picked.variantIndex | 0;
                    _refs.familySeed.value = String(request.familySeed);
                    _refs.variant.value = String(request.variantIndex);
                    return {
                        config: LockboxCore.clone(picked.config),
                        puzzle: LockboxCore.clone(picked.puzzle),
                        report: LockboxCore.clone(picked.report)
                    };
                }
                return LockboxGenerator.generatePuzzle(request.profile, request.familySeed, request.variantIndex);
            });
        }

        return Promise.resolve(LockboxGenerator.generatePuzzle(request.profile, request.familySeed, request.variantIndex));
    }

    function loadBakedPool() {
        if (_poolPromise) return _poolPromise;
        _poolPromise = fetch('data/lockbox-variants.json')
            .then(function(resp) {
                if (!resp.ok) throw new Error('HTTP ' + resp.status);
                return resp.json();
            })
            .catch(function() {
                return { variantPool: [] };
            });
        return _poolPromise;
    }

    function pickBakedVariant(pool, request) {
        var list = (pool && pool.variantPool) ? pool.variantPool : [];
        var exact = null;
        var fallback = null;
        for (var i = 0; i < list.length; i++) {
            if (list[i].tier !== request.profile) continue;
            if (!fallback) fallback = list[i];
            if ((list[i].familySeed >>> 0) === (request.familySeed >>> 0) && (list[i].variantIndex | 0) === (request.variantIndex | 0)) {
                exact = list[i];
                break;
            }
        }
        return exact || fallback;
    }

    function beginRun(packageData, request) {
        if (!packageData) return;
        if (typeof LockboxAudio !== 'undefined') {
            LockboxAudio.stopHeartbeat();
            LockboxAudio.stopAmbient();
        }
        if (_el) _el.classList.remove('fx-perfect', 'fx-good', 'fx-miss', 'fx-fail', 'fx-shake');
        var now = performance.now();
        _state = {
            request: LockboxCore.clone(request),
            config: LockboxCore.clone(packageData.config),
            puzzle: LockboxCore.clone(packageData.puzzle),
            report: LockboxCore.clone(packageData.report),
            phase: 'OBSERVE',
            traceValue: 0,
            tracePenalty: 0,
            traceStartedAt: 0,
            traceFrozen: false,
            selectedCells: [],
            selectedMap: {},
            bufferTokens: [],
            illegalGraceLeft: packageData.config.illegalGrace,
            illegalTapCount: 0,
            mainSolved: false,
            bonusSolved: false,
            bonusLocked: false,
            hintMode: request.hintMode || 'off',
            finisher: {
                holding: false,
                startedAt: 0,
                currentMs: 0,
                pointerId: null,
                result: null
            },
            result: null,
            openedAt: now,
            observeStartedAt: now,
            injectStartedAt: 0,
            mainSolvedAt: 0,
            traceAtMainSolved: 0,
            resultAt: 0,
            lastStatus: packageData.puzzle.accepted === false
                ? '当前盘面未命中验收带，保留为最优回退盘。'
                : '观察矩阵并规划 A/B 的重叠主解。'
        };

        renderAll();
    }

    function setBusyState(text) {
        _state = null;
        _refs.phaseBadge.textContent = 'INIT';
        _refs.axisLabel.textContent = '等待题目';
        _refs.stageHint.textContent = text;
        _refs.grid.innerHTML = '<div class="lockbox-empty">' + escapeHtml(text) + '</div>';
        _refs.sequences.innerHTML = '';
        _refs.buffer.innerHTML = '';
        _refs.traceFill.style.width = '0%';
        _refs.traceMeta.textContent = '';
        if (_refs.traceRailFill) _refs.traceRailFill.style.height = '0%';
        if (_refs.traceRailLeftMeta) _refs.traceRailLeftMeta.innerHTML = '<div>0%</div><div>STANDBY</div>';
        if (_refs.traceRailRightTitle) _refs.traceRailRightTitle.textContent = 'MODE C';
        if (_refs.guideNote) _refs.guideNote.textContent = '指引关闭。';
        if (_refs.traceModuleStack) _refs.traceModuleStack.innerHTML = '';
        if (_refs.railFinisher) _refs.railFinisher.classList.remove('visible');
        if (_refs.railFinisherProgress) _refs.railFinisherProgress.style.height = '0%';
        if (_refs.railFinisherMeta) _refs.railFinisherMeta.textContent = 'PRESS';
        if (_refs.traceFooter) _refs.traceFooter.textContent = 'TRACE BUS / waiting for puzzle';
        _refs.status.innerHTML = '<div class="lockbox-status-line">' + escapeHtml(text) + '</div>';
        _refs.resultCard.className = 'lockbox-result-card';
        _refs.resultCard.innerHTML = '';
        _refs.metrics.innerHTML = '';
        _refs.sessionMetrics.innerHTML = '';
    }

    function startInject() {
        if (!_state || _state.phase !== 'OBSERVE') return;
        _state.phase = 'INJECTING';
        _state.traceStartedAt = performance.now();
        _state.injectStartedAt = _state.traceStartedAt;
        _state.traceTickLevel = 0;
        _state.traceCriticalFired = false;
        _state.lastStatus = 'Trace 已启动，执行注入路径。';
        if (typeof LockboxAudio !== 'undefined') {
            LockboxAudio.play('inject');
            LockboxAudio.startAmbient();
            LockboxAudio.setAmbientTension(0);
        }
        notifyHost('start', null);
        renderAll();
    }

    function requestSubmit() {
        if (!_state || _state.phase !== 'MAIN_READY' || !_state.mainSolved) return;
        enterFinisher();
    }

    function onCellPointerDown(r, c) {
        if (!_state) return;
        if (_state.phase === 'OBSERVE') {
            _state.lastStatus = '先点击“开始注入”，再进入执行段。';
            renderMetaOnly();
            return;
        }
        if (_state.phase !== 'INJECTING' && _state.phase !== 'MAIN_READY') return;

        var cell = { r: r, c: c };
        if (!isLegalCell(cell)) {
            onIllegalTap();
            return;
        }

        var token = _state.puzzle.matrix[r][c];
        _state.selectedCells.push(cell);
        _state.selectedMap[LockboxCore.cellKey(cell)] = true;
        _state.bufferTokens.push(token);
        if (typeof LockboxAudio !== 'undefined') LockboxAudio.play('tapLegal', { tokenId: token });

        var completion = LockboxCore.evaluateBuffer(_state.bufferTokens, _state.puzzle.seqA, _state.puzzle.seqB, _state.puzzle.seqC);
        var mainSolvedNow = completion.a && completion.b;
        var bonusGainedNow = completion.c && !_state.bonusLocked && !_state.bonusSolved;

        if (completion.c && !_state.bonusLocked) _state.bonusSolved = true;
        if (mainSolvedNow && !_state.mainSolved) {
            _state.mainSolved = true;
            _state.mainSolvedAt = performance.now();
            _state.traceAtMainSolved = _state.traceValue;
            _state.lastStatus = '主解 A/B 已完成，可立即提交或继续追 C。';
            _state.phase = 'MAIN_READY';
            if (typeof LockboxAudio !== 'undefined') LockboxAudio.play('mainSolved');
        } else if (bonusGainedNow) {
            _state.lastStatus = 'Bonus C 命中，可收尾或继续优化。';
            if (typeof LockboxAudio !== 'undefined') LockboxAudio.play('bonusSolved');
        } else if (_state.phase === 'MAIN_READY' && !_state.bonusSolved) {
            _state.lastStatus = '主解已保底，可继续贪 Bonus。';
        } else {
            _state.lastStatus = '缓冲区写入 1 个 token。';
        }

        if (_state.bufferTokens.length >= _state.config.bufferCap) {
            if (_state.mainSolved) {
                enterFinisher();
            } else {
                failRun('buffer');
                return;
            }
        }

        renderAll();
    }

    function isLegalCell(cell) {
        if (_state.selectedMap[LockboxCore.cellKey(cell)]) return false;
        if (!_state.selectedCells.length) return cell.r === 0;

        var prev = _state.selectedCells[_state.selectedCells.length - 1];
        var axis = LockboxCore.nextAxisAfterPickCount(_state.selectedCells.length);
        if (axis === 'COL') return cell.c === prev.c;
        return cell.r === prev.r;
    }

    function onIllegalTap() {
        _state.illegalTapCount++;
        if (_state.illegalGraceLeft > 0) {
            _state.illegalGraceLeft--;
            _state.lastStatus = '非法节点命中，但本档仍有 1 次宽限。';
            if (typeof LockboxAudio !== 'undefined') LockboxAudio.play('illegalGrace');
        } else {
            _state.tracePenalty += _state.config.tracePulse;
            _state.lastStatus = '非法节点触发 Trace 脉冲。';
            if (typeof LockboxAudio !== 'undefined') LockboxAudio.play('illegalPulse');
        }
        renderMetaOnly();
    }

    function enterFinisher() {
        if (!_state || _state.result) return;
        _state.phase = 'FINISHER';
        _state.traceFrozen = true;
        _state.lastStatus = 'Trace 已冻结，按住并在甜区释放。';
        if (typeof LockboxAudio !== 'undefined') LockboxAudio.play('finisherArm');
        renderAll();
    }

    function beginFinisherHold(pointerId) {
        _state.finisher.holding = true;
        _state.finisher.startedAt = performance.now();
        _state.finisher.currentMs = 0;
        _state.finisher.pointerId = pointerId;
        _refs.railFinisherTrack.setPointerCapture(pointerId);
        if (typeof LockboxAudio !== 'undefined') LockboxAudio.startHeartbeat();
        renderFinisher();
    }

    function finishFinisherHold(autoTimeout) {
        if (!_state || !_state.finisher.holding) return;
        if (_state.finisher.pointerId !== null) {
            try { _refs.railFinisherTrack.releasePointerCapture(_state.finisher.pointerId); } catch (e) {}
        }

        _state.finisher.holding = false;
        var heldMs = _state.finisher.currentMs;
        var delta = Math.abs(heldMs - 900);
        var result = 'miss';
        if (!autoTimeout && delta <= 120) result = 'perfect';
        else if (!autoTimeout && delta <= 300) result = 'good';
        finalizeRun('success', result);
    }

    function failRun(reason) {
        finalizeRun('fail', null, reason);
    }

    function finalizePartial() {
        finalizeRun('partial_success', null, 'trace');
    }

    function finalizeRun(outcome, finisherResult, reason) {
        if (!_state || _state.result) return;
        _state.traceFrozen = true;
        _state.finisher.holding = false;
        _state.finisher.result = finisherResult;

        var payload = {
            outcome: outcome,
            reason: reason || null,
            rating: computeRating(outcome, finisherResult),
            mainSolved: _state.mainSolved,
            bonusSolved: _state.bonusSolved,
            bonusLocked: _state.bonusLocked,
            finisherResult: finisherResult,
            traceValue: Number(_state.traceValue.toFixed(4)),
            picksUsed: _state.bufferTokens.length,
            illegalTapCount: _state.illegalTapCount
        };

        _state.result = payload;
        _state.resultAt = performance.now();
        _state.phase = (outcome === 'fail') ? 'FAIL' : 'RESULT';
        _state.lastStatus = buildResultCopy(payload);
        if (typeof LockboxAudio !== 'undefined') {
            LockboxAudio.stopHeartbeat();
            LockboxAudio.stopAmbient();
            if (outcome === 'fail') LockboxAudio.play('fail');
            else if (finisherResult === 'perfect') LockboxAudio.play('finishPerfect');
            else if (finisherResult === 'good') LockboxAudio.play('finishGood');
            else LockboxAudio.play('finishMiss');
        }
        triggerResultFx(outcome, finisherResult);
        notifyHost('result', payload);
        renderAll();
    }

    function triggerResultFx(outcome, finisherResult) {
        if (!_el) return;
        _el.classList.remove('fx-perfect', 'fx-good', 'fx-miss', 'fx-fail', 'fx-shake');
        void _el.offsetWidth;
        if (outcome === 'fail') {
            _el.classList.add('fx-fail', 'fx-shake');
        } else if (finisherResult === 'perfect') {
            _el.classList.add('fx-perfect');
        } else if (finisherResult === 'good') {
            _el.classList.add('fx-good');
        } else {
            _el.classList.add('fx-miss');
        }
        setTimeout(function() {
            if (_el) _el.classList.remove('fx-shake');
        }, 700);
    }

    function computeRating(outcome, finisherResult) {
        if (outcome === 'fail') return 'F';
        var score = 2;
        if (_state.bonusSolved) score += 1;
        if (outcome === 'partial_success') score -= 1;
        if (finisherResult === 'perfect') score += 2;
        else if (finisherResult === 'good') score += 1;
        if (score >= 5) return 'S';
        if (score >= 4) return 'A';
        if (score >= 3) return 'B';
        return 'C';
    }

    function buildResultCopy(payload) {
        if (payload.outcome === 'fail') return '主解未完成，箱体仍处于锁定状态。';
        if (payload.outcome === 'partial_success') return '主解保底成功，但 Trace 已烧毁剩余窗口。';
        if (payload.finisherResult === 'perfect') return '完美收尾，协议注入稳定落点。';
        if (payload.finisherResult === 'good') return '收尾良好，主成功已确认。';
        return '主解已确认，但收尾偏粗暴。';
    }

    function notifyHost(eventName, resultPayload) {
        if (!_state) return;
        Bridge.send({
            type: 'panel',
            cmd: 'lockbox_session',
            payload: {
                event: eventName,
                profile: _state.config.id,
                source: _state.request.source,
                familySeed: _state.puzzle.familySeed,
                variantIndex: _state.puzzle.variantIndex,
                result: resultPayload || null,
                metrics: collectSessionMetrics()
            }
        });
    }

    function exportCurrentJson() {
        if (!_state) return;
        var exported = LockboxCore.buildSessionExport(_state.config, _state.puzzle, _state.report, {
            request: _state.request,
            result: _state.result,
            metrics: collectSessionMetrics()
        });
        var text = JSON.stringify(exported, null, 2);
        var blob = new Blob([text], { type: 'application/json' });
        var url = URL.createObjectURL(blob);
        var a = document.createElement('a');
        a.href = url;
        a.download = 'lockbox-' + _state.config.id + '-' + _state.puzzle.familySeed + '-' + _state.puzzle.variantIndex + '.json';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        setTimeout(function() { URL.revokeObjectURL(url); }, 0);

        Bridge.send({
            type: 'panel',
            cmd: 'lockbox_session',
            payload: {
                event: 'export',
                profile: _state.config.id,
                source: _state.request.source,
                familySeed: _state.puzzle.familySeed,
                variantIndex: _state.puzzle.variantIndex,
                result: _state.result,
                metrics: collectSessionMetrics()
            }
        });
    }

    function collectSessionMetrics() {
        if (!_state) return {};
        var now = _state.resultAt || performance.now();
        var observeMs = _state.injectStartedAt ? (_state.injectStartedAt - _state.observeStartedAt) : (now - _state.observeStartedAt);
        var executeMs = _state.injectStartedAt ? (now - _state.injectStartedAt) : 0;
        return {
            observeMs: Math.round(observeMs),
            executeMs: Math.round(Math.max(0, executeMs)),
            illegalTapCount: _state.illegalTapCount,
            traceAtMainSolved: Number((_state.traceAtMainSolved || 0).toFixed(4)),
            traceValue: Number((_state.traceValue || 0).toFixed(4)),
            picksUsed: _state.bufferTokens.length,
            accepted: _state.puzzle.accepted !== false
        };
    }

    function startLoop() {
        stopLoop();
        function frame(now) {
            if (!_panelOpen) { _loopId = 0; return; }
            _loopId = requestAnimationFrame(frame);
            tick(now);
        }
        _loopId = requestAnimationFrame(frame);
    }

    function stopLoop() {
        if (_loopId) cancelAnimationFrame(_loopId);
        _loopId = 0;
    }

    function tick(now) {
        if (!_state) return;
        var changed = false;

        if ((_state.phase === 'INJECTING' || _state.phase === 'MAIN_READY') && !_state.traceFrozen && _state.traceStartedAt) {
            var nextTrace = LockboxCore.clamp(((now - _state.traceStartedAt) / _state.config.traceFullMs) + _state.tracePenalty, 0, 1);
            if (Math.abs(nextTrace - _state.traceValue) > 0.0025) changed = true;
            _state.traceValue = nextTrace;

            if (typeof LockboxAudio !== 'undefined') {
                LockboxAudio.setAmbientTension(_state.traceValue);
                var nextLevel = Math.min(9, Math.floor(_state.traceValue * 10));
                if (nextLevel > (_state.traceTickLevel || 0)) {
                    _state.traceTickLevel = nextLevel;
                    LockboxAudio.play('traceTick', { level: nextLevel });
                }
                if (!_state.traceCriticalFired && _state.traceValue >= 0.85) {
                    _state.traceCriticalFired = true;
                    LockboxAudio.play('traceCritical');
                }
            }

            if (!_state.bonusLocked && !_state.bonusSolved && _state.traceValue >= _state.config.bonusLockPct) {
                _state.bonusLocked = true;
                _state.lastStatus = 'Bonus 窗口已锁死，优先保住主解。';
                if (typeof LockboxAudio !== 'undefined') LockboxAudio.play('bonusLock');
                _metaDirty = true;
                changed = true;
            }

            if (_state.traceValue >= 1 && !_state.result) {
                if (_state.mainSolved) finalizePartial();
                else failRun('trace');
                return;
            }
        }

        if (_state.phase === 'FINISHER' && _state.finisher.holding) {
            _state.finisher.currentMs = now - _state.finisher.startedAt;
            var holdPct = LockboxCore.clamp(_state.finisher.currentMs / 900, 0, 1.3);
            if (typeof LockboxAudio !== 'undefined') LockboxAudio.tickHeartbeat(Math.min(1, holdPct));
            if (_state.finisher.currentMs >= 1200) {
                finishFinisherHold(true);
                return;
            }
            renderFinisher();
        }

        renderFrame();
        if (_metaDirty) {
            _metaDirty = false;
            if (changed) renderAll();
            else renderMetaOnly();
        } else if (changed) {
            renderAll();
        }
    }

    function renderFrame() {
        if (!_state) return;
        var tracePct = Math.round(_state.traceValue * 100);
        if (_refs.traceFill) _refs.traceFill.style.width = tracePct + '%';
        if (_refs.traceRailFill) _refs.traceRailFill.style.height = tracePct + '%';
        if (_refs.traceFrame) _refs.traceFrame.style.setProperty('--trace-intensity', String((_state.traceValue * 0.55).toFixed(3)));
    }

    function renderAll() {
        if (!_state) return;
        renderGrid();
        renderSequences();
        renderBuffer();
        renderResult();
        renderMetaOnly();
        renderMetrics();
        renderFinisher();
    }

    function renderGrid() {
        var matrix = _state.puzzle.matrix;
        var legalMap = getLegalMap();
        var hintInfo = getHintInfo();
        var html = [];
        var guideActive = !!hintInfo;
        _refs.grid.style.setProperty('--lockbox-size', _state.config.size);
        _refs.grid.style.setProperty('--lockbox-grid-max', (_state.config.size >= 5 ? 380 : 460) + 'px');
        _refs.grid.style.setProperty('--lockbox-grid-vh-max', 'calc(100vh - 214px)');
        _refs.grid.className = 'lockbox-grid' + (guideActive ? ' guide-active guide-' + _state.hintMode : '');

        for (var r = 0; r < _state.config.size; r++) {
            for (var c = 0; c < _state.config.size; c++) {
                var key = LockboxCore.cellKey({ r: r, c: c });
                var classes = ['lockbox-cell'];
                if (_state.selectedMap[key]) classes.push('selected');
                else if (legalMap[key] && (_state.phase === 'INJECTING' || _state.phase === 'MAIN_READY')) classes.push('legal');
                else if (!_state.selectedCells.length && r === 0 && (_state.phase === 'OBSERVE' || _state.phase === 'INJECTING')) classes.push('entry');
                if (hintInfo && hintInfo.hinted[key]) classes.push('hinted');
                if (hintInfo && hintInfo.nextKey === key) classes.push('hint-next');
                if (guideActive && !(hintInfo && hintInfo.hinted[key]) && !_state.selectedMap[key]) classes.push('guide-muted');
                if (_state.phase === 'RESULT' || _state.phase === 'FAIL') classes.push('disabled');
                var hintBadge = '';
                if (hintInfo && hintInfo.hinted[key]) {
                    hintBadge = '<span class="lockbox-hint-badge ' + (hintInfo.nextKey === key ? 'next' : 'path') + '">' +
                        escapeHtml(hintInfo.nextKey === key ? 'NEXT' : String(hintInfo.steps[key])) +
                        '</span>';
                }
                html.push(
                    '<button type="button" class="' + classes.join(' ') + '" data-r="' + r + '" data-c="' + c + '">' +
                    hintBadge +
                    '<span class="lockbox-token">' + LockboxCore.renderTokenSvg(matrix[r][c], { size: 58 }) + '</span>' +
                    '</button>'
                );
            }
        }

        _refs.grid.innerHTML = html.join('');
    }

    function renderSequences() {
        var seqs = [
            { id: 'A', tokens: _state.puzzle.seqA, done: LockboxCore.bufferContainsSequence(_state.bufferTokens, _state.puzzle.seqA), locked: false },
            { id: 'B', tokens: _state.puzzle.seqB, done: LockboxCore.bufferContainsSequence(_state.bufferTokens, _state.puzzle.seqB), locked: false },
            { id: 'C', tokens: _state.puzzle.seqC, done: _state.bonusSolved, locked: _state.bonusLocked && !_state.bonusSolved }
        ];
        var html = [];
        for (var i = 0; i < seqs.length; i++) {
            html.push(
                '<div class="lockbox-seq-row ' + (seqs[i].done ? 'done' : '') + ' ' + (seqs[i].locked ? 'locked' : '') + '">' +
                '<div class="lockbox-seq-label">' + seqs[i].id + '</div>' +
                '<div class="lockbox-seq-tokens">' + renderTokenStrip(seqs[i].tokens, 28) + '</div>' +
                '<div class="lockbox-seq-state">' + (seqs[i].locked ? 'LOCKED' : seqs[i].done ? 'SOLVED' : 'PENDING') + '</div>' +
                '</div>'
            );
        }
        _refs.sequences.innerHTML = html.join('');
    }

    function renderBuffer() {
        var html = [];
        for (var i = 0; i < _state.config.bufferCap; i++) {
            if (i < _state.bufferTokens.length) {
                html.push('<div class="lockbox-buffer-slot filled">' + LockboxCore.renderTokenSvg(_state.bufferTokens[i], { size: 30 }) + '</div>');
            } else {
                html.push('<div class="lockbox-buffer-slot empty">' + (i + 1) + '</div>');
            }
        }
        _refs.buffer.innerHTML = '<div class="lockbox-buffer-track">' + html.join('') + '</div>';
    }

    function renderResult() {
        if (!_state.result) {
            _refs.resultCard.className = 'lockbox-result-card';
            _refs.resultCard.innerHTML = '';
            return;
        }

        var payload = _state.result;
        _refs.resultCard.className = 'lockbox-result-card visible ' + payload.outcome;
        _refs.resultCard.innerHTML = [
            '<div class="lockbox-result-head">',
                '<div class="lockbox-result-title">' + escapeHtml(payload.outcome.toUpperCase()) + '</div>',
                '<div class="lockbox-result-rating">评级 ' + escapeHtml(payload.rating) + '</div>',
            '</div>',
            '<div class="lockbox-result-body">' + escapeHtml(buildResultCopy(payload)) + '</div>',
            '<div class="lockbox-result-tags">',
                '<span>主解 ' + (_state.mainSolved ? '完成' : '失败') + '</span>',
                '<span>Bonus ' + (_state.bonusSolved ? '保留' : _state.bonusLocked ? '锁死' : '未拿') + '</span>',
                '<span>收尾 ' + (payload.finisherResult || '无') + '</span>',
            '</div>'
        ].join('');
    }

    function renderMetaOnly() {
        if (!_state) return;
        if (_el) _el.setAttribute('data-phase', _state.phase);
        _refs.phaseBadge.textContent = _state.phase;
        _refs.axisLabel.textContent = buildAxisLabel();
        _refs.stageHint.textContent = _state.lastStatus;
        renderProfileSwitch();
        renderTraceShell();
        _refs.traceFill.style.width = Math.round(_state.traceValue * 100) + '%';
        _refs.traceMeta.textContent = Math.round(_state.traceValue * 100) + '% / 锁阈值 ' + Math.round(_state.config.bonusLockPct * 100) + '%' + (_state.traceFrozen ? ' / 已冻结' : '');
        _refs.status.innerHTML = renderStatusBlock();
        _refs.traceFrame.style.setProperty('--trace-intensity', String((_state.traceValue * 0.55).toFixed(3)));
        _refs.traceFrame.className = 'lockbox-trace-frame' + (_state.traceFrozen ? ' frozen' : '') + (_state.bonusLocked ? ' bonus-locked' : '');
        _el.querySelector('[data-action="start"]').disabled = _state.phase !== 'OBSERVE';
        _el.querySelector('[data-action="submit"]').disabled = !(_state.phase === 'MAIN_READY' && _state.mainSolved);
    }

    function renderTraceShell() {
        var tracePct = Math.round(_state.traceValue * 100);
        if (_refs.traceRailFill) _refs.traceRailFill.style.height = tracePct + '%';
        if (_refs.traceRailRightTitle) _refs.traceRailRightTitle.textContent = _state.phase === 'FINISHER' ? 'FINISH' : 'MODE C';
        if (_refs.traceRailLeftMeta) {
            _refs.traceRailLeftMeta.innerHTML = [
                '<div>' + tracePct + '%</div>',
                '<div>' + (_state.traceFrozen ? 'FROZEN' : _state.bonusLocked ? 'LOCKED' : 'LIVE') + '</div>'
            ].join('');
        }
        if (_refs.traceModuleStack) {
            _refs.traceModuleStack.innerHTML = _state.phase === 'FINISHER' ? '' : [
                renderTraceModule('LOCK', Math.round(_state.config.bonusLockPct * 100) + '%', _state.bonusLocked ? 'hot' : ''),
                renderTraceModule('GRACE', String(_state.illegalGraceLeft), _state.illegalGraceLeft > 0 ? 'safe' : ''),
                renderTraceModule('PULSE', String(_state.illegalTapCount), _state.illegalTapCount > 0 ? 'warn' : ''),
                renderTraceModule('STATE', _state.phase, _state.traceFrozen ? 'frozen' : '')
            ].join('');
        }
        if (_refs.traceFooter) {
            var hintInfo = getHintInfo();
            _refs.traceFooter.innerHTML = [
                '<span class="lockbox-trace-footer-label">TRACE BUS</span>',
                '<span class="lockbox-trace-footer-chip">mode C</span>',
                '<span class="lockbox-trace-footer-chip">trace ' + tracePct + '%</span>',
                '<span class="lockbox-trace-footer-chip">' + (_state.bonusLocked ? 'bonus locked' : 'bonus open') + '</span>',
                '<span class="lockbox-trace-footer-chip">' + (_state.traceFrozen ? 'frozen' : 'injecting') + '</span>',
                '<span class="lockbox-trace-footer-chip">guide ' + getHintModeLabel(_state.hintMode) + (hintInfo && hintInfo.reset ? ' / reset' : '') + '</span>'
            ].join('');
        }
    }

    function renderTraceModule(label, value, tone) {
        return '<div class="lockbox-trace-module ' + tone + '"><span>' + escapeHtml(label) + '</span><b>' + escapeHtml(value) + '</b></div>';
    }

    function renderProfileSwitch() {
        setProfileUi(_state.config.id, _state.request.source);
    }

    function setProfileUi(profileId, source) {
        if (_refs.profileNote) _refs.profileNote.textContent = '当前档位：' + profileId + ' / ' + source;
        if (_refs.hintBtn) _refs.hintBtn.textContent = '指引:' + getHintModeLabel(_state ? _state.hintMode : 'off');
        if (_refs.guideNote) _refs.guideNote.textContent = buildGuideCopy();
        if (!_refs.profileSwitch) return;
        var buttons = _refs.profileSwitch.querySelectorAll('[data-profile-switch]');
        for (var i = 0; i < buttons.length; i++) {
            var active = buttons[i].getAttribute('data-profile-switch') === profileId;
            buttons[i].classList.toggle('active', active);
        }
    }

    function getHintModeLabel(mode) {
        if (mode === 'next') return '下一';
        if (mode === 'path') return '全路';
        return '关';
    }

    function collectMinPaths() {
        var pool = [];
        if (_state && _state.report && _state.report.mainMinPaths && _state.report.mainMinPaths.length) {
            pool = _state.report.mainMinPaths;
        } else if (_state && _state.report && _state.report.canonicalMainPath) {
            pool = [_state.report.canonicalMainPath];
        } else if (_state && _state.puzzle && _state.puzzle.canonicalPath) {
            pool = [_state.puzzle.canonicalPath];
        }
        return pool;
    }

    function pathPrefixMatches(p, picks) {
        if (picks.length > p.length) return false;
        for (var i = 0; i < picks.length; i++) {
            if (picks[i].r !== p[i].r || picks[i].c !== p[i].c) return false;
        }
        return true;
    }

    function getHintInfo() {
        if (!_state || _state.hintMode === 'off') return null;
        if (_state.phase === 'FAIL' || _state.phase === 'RESULT') return null;

        var pool = collectMinPaths();
        if (!pool.length) return null;

        var picks = _state.selectedCells;
        var viable = [];
        for (var k = 0; k < pool.length; k++) {
            if (pathPrefixMatches(pool[k], picks)) viable.push(pool[k]);
        }

        var reset = false;
        var path = null;
        if (viable.length) {
            path = viable[0];
        } else {
            reset = true;
            path = pool[0];
        }

        var startIndex = reset ? 0 : picks.length;
        if (startIndex >= path.length) return null;

        var hinted = {};
        var steps = {};
        var nextKey = null;
        for (var i = startIndex; i < path.length; i++) {
            var key = LockboxCore.cellKey(path[i]);
            if (!nextKey) nextKey = key;
            hinted[key] = true;
            steps[key] = (i - startIndex + 1);
            if (_state.hintMode === 'next') break;
        }

        return {
            hinted: hinted,
            nextKey: nextKey,
            steps: steps,
            reset: reset,
            nextCell: path[startIndex],
            remaining: path.length - startIndex,
            viableCount: viable.length,
            totalPaths: pool.length
        };
    }

    function buildGuideCopy() {
        if (!_state) return '指引关闭。';
        var hintInfo = getHintInfo();
        if (_state.hintMode === 'off' || !hintInfo) return '指引关闭。';

        var nextCell = hintInfo.nextCell;
        var tokenId = nextCell ? _state.puzzle.matrix[nextCell.r][nextCell.c] : null;
        var tokenCode = (tokenId !== null && LockboxCore.TOKEN_SPECS[tokenId]) ? LockboxCore.TOKEN_SPECS[tokenId].code : '--';
        var prefix;
        if (hintInfo.reset) {
            prefix = '当前走法已脱离所有最短主解（' + hintInfo.totalPaths + ' 条），回退到首选路径；';
        } else if (hintInfo.viableCount < hintInfo.totalPaths) {
            prefix = '仍在 ' + hintInfo.viableCount + '/' + hintInfo.totalPaths + ' 条最短主解上；';
        } else {
            prefix = '';
        }

        if (_state.hintMode === 'next') {
            return prefix + '下一步：第 ' + (nextCell.r + 1) + ' 行 第 ' + (nextCell.c + 1) + ' 列 / ' + tokenCode;
        }

        return prefix + '全链路已编号，高亮共 ' + hintInfo.remaining + ' 步；NEXT 为当前推荐落点。';
    }

    function renderStatusBlock() {
        var lines = [
            'Profile: ' + _state.config.id + ' / ' + _state.request.source,
            'familySeed: ' + (_state.puzzle.familySeed >>> 0) + ' / variant: ' + (_state.puzzle.variantIndex | 0),
            'Picks: ' + _state.bufferTokens.length + '/' + _state.config.bufferCap + ' / Illegal: ' + _state.illegalTapCount,
            'Main: ' + (_state.mainSolved ? 'ready' : 'pending') + ' / Bonus: ' + (_state.bonusSolved ? 'solved' : _state.bonusLocked ? 'locked' : 'pending'),
            'Guide: ' + getHintModeLabel(_state.hintMode)
        ];
        if (_state.puzzle.accepted === false) lines.push('Solver fallback: 当前盘面未命中验收带');
        var html = [];
        for (var i = 0; i < lines.length; i++) html.push('<div class="lockbox-status-line">' + escapeHtml(lines[i]) + '</div>');
        return html.join('');
    }

    function renderMetrics() {
        var report = _state.report || {};
        _refs.metrics.innerHTML = renderKvList([
            ['mainMinLen', report.minMainLen],
            ['mainMinSolutions', report.mainSolutionCountMinLen],
            ['fullSolutions', report.fullSolutionCount],
            ['entryStarts', report.entryStartCount],
            ['bonusShare', pct(report.bonusShare)],
            ['deadChoiceRate', pct(report.deadChoiceRate)],
            ['difficulty', report.difficultyScore ? report.difficultyScore.toFixed(1) : '0.0']
        ]);

        var session = collectSessionMetrics();
        _refs.sessionMetrics.innerHTML = renderKvList([
            ['observeMs', session.observeMs],
            ['executeMs', session.executeMs],
            ['traceAtMain', pct(session.traceAtMainSolved)],
            ['traceNow', pct(session.traceValue)],
            ['picksUsed', session.picksUsed],
            ['accepted', session.accepted ? 'yes' : 'fallback']
        ]);
    }

    function renderFinisher() {
        if (!_state) return;
        if (_state.phase !== 'FINISHER') {
            _refs.railFinisher.classList.remove('visible');
            _refs.railFinisherProgress.style.height = '0%';
            _refs.railFinisherMeta.textContent = 'PRESS';
            return;
        }

        _refs.railFinisher.classList.add('visible');
        var pctValue = LockboxCore.clamp((_state.finisher.currentMs || 0) / 1200, 0, 1);
        _refs.railFinisherProgress.style.height = Math.round(pctValue * 100) + '%';
        _refs.railFinisherMeta.textContent = _state.finisher.holding
            ? ('释放 @ ' + Math.round(_state.finisher.currentMs) + 'ms')
            : '按住开始';
    }

    function buildAxisLabel() {
        if (!_state.selectedCells.length) return _state.phase === 'OBSERVE' ? '顶行入口待机' : '下一步：顶行起手';
        var axis = LockboxCore.nextAxisAfterPickCount(_state.selectedCells.length);
        return axis === 'COL' ? '下一步：同列选点' : '下一步：同行选点';
    }

    function getLegalMap() {
        var map = {};
        if (!_state || _state.phase === 'RESULT' || _state.phase === 'FAIL' || _state.phase === 'FINISHER') return map;
        var legal;
        if (!_state.selectedCells.length) {
            legal = LockboxCore.getLegalCells(_state.config.size, null, null);
        } else {
            legal = LockboxCore.getLegalCells(
                _state.config.size,
                _state.selectedCells[_state.selectedCells.length - 1],
                LockboxCore.nextAxisAfterPickCount(_state.selectedCells.length)
            );
        }
        for (var i = 0; i < legal.length; i++) {
            var key = LockboxCore.cellKey(legal[i]);
            if (!_state.selectedMap[key]) map[key] = true;
        }
        return map;
    }

    function renderTokenStrip(tokens, size) {
        var html = [];
        for (var i = 0; i < tokens.length; i++) {
            html.push('<span class="lockbox-mini-token">' + LockboxCore.renderTokenSvg(tokens[i], { size: size }) + '</span>');
        }
        return html.join('');
    }

    function renderKvList(rows) {
        var html = [];
        for (var i = 0; i < rows.length; i++) {
            html.push(
                '<div class="lockbox-kv-row"><span class="lockbox-kv-key">' + escapeHtml(String(rows[i][0])) +
                '</span><span class="lockbox-kv-value">' + escapeHtml(String(rows[i][1])) + '</span></div>'
            );
        }
        return html.join('');
    }

    function pct(value) {
        if (value === undefined || value === null || isNaN(value)) return '0%';
        return Math.round(value * 100) + '%';
    }

    function escapeHtml(text) {
        return String(text)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
    }

    return {};
})();
