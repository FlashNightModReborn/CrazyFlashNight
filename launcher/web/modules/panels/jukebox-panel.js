/**
 * jukebox-panel.js — Phase 5：Jukebox 展开升格为 PanelManager 注册 panel
 *
 * 职责：折叠态（标题栏 + mini wave + pause/expand）已由 C# JukeboxTitlebarWidget 接管；
 * 本面板只负责展开态——大波形 + 进度条 + 专辑/曲目浏览器 + 设置（音量/覆盖/真随机/播放模式）+ 帮助。
 *
 * 入口：C# JukeboxTitlebarWidget expand 按钮 → router JUKEBOX_EXPAND → PanelHostController.OpenPanel("jukebox")
 *      → PostToWeb panel_cmd open → panels.js 调本 panel 的 onOpen。
 *
 * DOM 用 jbp- 前缀新 id，与 overlay.html 旧 #jukebox-panel DOM 完全隔离（旧 DOM 已被 CSS 整体隐藏，
 *   但 jukebox.js 仍 binding，本面板独立一份 listener，行为收敛于 panel 关闭时清理）。
 */
(function() {
    'use strict';

    if (typeof Panels === 'undefined') return;

    var _el;
    var _refs = {};
    var _opened = false;

    // 状态（panel 开期间存活；onClose 复位）
    var dpr = window.devicePixelRatio || 1;
    var HISTORY = 100;
    var histL = new Float32Array(HISTORY);
    var histR = new Float32Array(HISTORY);
    var histIdx = 0;
    var histLen = 0;
    var playing = false;
    var bgmTitle = '';
    var currentDuration = 0;
    var lastWaveRenderAt = 0;
    var WAVE_RENDER_MS = 50;

    var albums = {};       // 专辑名 → [{title,weight}]
    var allTracks = [];
    var currentAlbumFilter = '';

    var settingsState = {
        override: false,
        trueRandom: false,
        playMode: 'singleLoop'
    };
    var sliders = {};
    var isPaused = false;
    var seekRect = null;

    // 注册时机：panels.js 已加载（overlay.html 把本文件放在 panels.js 之后）
    Panels.register('jukebox', {
        create: createDOM,
        onOpen: onOpen,
        // ESC / backdrop 走此入口；必须先 Panels.close() 让 panels.js _active 复位为 null，
        // 否则 C# SuspendAfterPanel 不会回发 panel_cmd close（PanelHostController 走 SW_HIDE 不是 force_close 通知 web），
        // _active 滞留 'jukebox' 导致下次 open() 早 return（panels.js: if (_active === id) return）。
        onRequestClose: closeLocally,
        onClose: cleanup,
        onForceClose: cleanup
    });

    /// <summary>本地立即隐藏 panel + 通知 C# 走 backdrop/HUD-resume 序列。
    ///         三条入口（× 按钮 / ESC / backdrop click）共用，避免单边漏 Panels.close 让 _active 滞留。</summary>
    function closeLocally() {
        try { Panels.close(); } catch (e) {}
        Bridge.send({type: 'panel', cmd: 'close', panel: 'jukebox'});
    }

    function createDOM() {
        _el = document.createElement('div');
        _el.className = 'jbp-panel';
        _el.innerHTML = [
            '<div class="jbp-header">',
                '<span class="jbp-title-static">&#9835; 点歌台</span>',
                '<span class="jbp-current-title" id="jbp-current-title">未播放</span>',
                '<span class="jbp-time" id="jbp-time"></span>',
                '<div class="jbp-header-spacer"></div>',
                '<div class="jbp-pause-btn jb-ctrl-btn" id="jbp-pause-btn" title="暂停/继续">&#8214;</div>',
                '<div class="jbp-stop-btn jb-ctrl-btn" id="jbp-stop-btn" title="停止(回到默认BGM)">&#9724;</div>',
                '<div class="jbp-help-btn jb-ctrl-btn" id="jbp-help-btn" title="帮助">?</div>',
                '<button class="jbp-close-btn" id="jbp-close-btn" type="button">×</button>',
            '</div>',
            '<div class="jbp-body">',
                '<canvas class="jbp-wave" id="jbp-wave" width="800" height="64"></canvas>',
                '<div class="jbp-progress" id="jbp-progress"><div class="jbp-prog-fill" id="jbp-prog-fill"></div></div>',
                '<div class="jbp-browser-row">',
                    '<div class="jbp-album-dropdown" id="jbp-album-dropdown">',
                        '<div class="jbp-album-trigger" id="jbp-album-trigger">',
                            '<span class="jbp-album-label" id="jbp-album-label">全部</span>',
                            '<span class="jb-dd-arrow">&#9662;</span>',
                        '</div>',
                        '<div class="jbp-album-options" id="jbp-album-options"></div>',
                    '</div>',
                '</div>',
                '<div class="jbp-track-list" id="jbp-track-list"></div>',
                '<div class="jbp-settings" id="jbp-settings">',
                    '<div class="jb-setting-group-label">音量</div>',
                    '<div class="jb-slider-row" data-slider="volGlobal">',
                        '<span class="jb-slider-label">全局</span>',
                        '<div class="jb-slider-track"><div class="jb-slider-fill"></div><div class="jb-slider-thumb"></div></div>',
                        '<span class="jb-slider-value">50</span>',
                    '</div>',
                    '<div class="jb-slider-row" data-slider="volBgm">',
                        '<span class="jb-slider-label">音乐</span>',
                        '<div class="jb-slider-track"><div class="jb-slider-fill"></div><div class="jb-slider-thumb"></div></div>',
                        '<span class="jb-slider-value">80</span>',
                    '</div>',
                    '<div class="jb-setting-divider"></div>',
                    '<div class="jb-setting-row jb-setting-item" data-key="override">',
                        '<span class="jb-setting-dot"></span>',
                        '<span class="jb-setting-label">覆盖关卡BGM</span>',
                    '</div>',
                    '<div class="jb-setting-row jb-setting-item" data-key="trueRandom">',
                        '<span class="jb-setting-dot"></span>',
                        '<span class="jb-setting-label">真随机</span>',
                    '</div>',
                    '<div class="jb-setting-divider"></div>',
                    '<div class="jb-setting-group-label">播放模式</div>',
                    '<div class="jb-setting-row jb-setting-item jb-radio" data-key="playMode" data-value="singleLoop">',
                        '<span class="jb-setting-dot"></span>',
                        '<span class="jb-setting-label">单曲循环</span>',
                    '</div>',
                    '<div class="jb-setting-row jb-setting-item jb-radio" data-key="playMode" data-value="albumLoop">',
                        '<span class="jb-setting-dot"></span>',
                        '<span class="jb-setting-label">专辑循环</span>',
                    '</div>',
                    '<div class="jb-setting-row jb-setting-item jb-radio" data-key="playMode" data-value="playOnce">',
                        '<span class="jb-setting-dot"></span>',
                        '<span class="jb-setting-label">播完回默认</span>',
                    '</div>',
                '</div>',
            '</div>',
            '<div class="jbp-help-modal" id="jbp-help-modal">',
                '<div class="jbp-help-content" id="jbp-help-content"></div>',
                '<button class="jbp-help-close" id="jbp-help-close" type="button">关闭</button>',
            '</div>'
        ].join('');

        _refs.title       = _el.querySelector('#jbp-current-title');
        _refs.time        = _el.querySelector('#jbp-time');
        _refs.canvas      = _el.querySelector('#jbp-wave');
        _refs.progFill    = _el.querySelector('#jbp-prog-fill');
        _refs.progBar     = _el.querySelector('#jbp-progress');
        _refs.albumWrap   = _el.querySelector('#jbp-album-dropdown');
        _refs.albumTrig   = _el.querySelector('#jbp-album-trigger');
        _refs.albumLabel  = _el.querySelector('#jbp-album-label');
        _refs.albumOpts   = _el.querySelector('#jbp-album-options');
        _refs.trackList   = _el.querySelector('#jbp-track-list');
        _refs.pauseBtn    = _el.querySelector('#jbp-pause-btn');
        _refs.stopBtn     = _el.querySelector('#jbp-stop-btn');
        _refs.helpBtn     = _el.querySelector('#jbp-help-btn');
        _refs.helpModal   = _el.querySelector('#jbp-help-modal');
        _refs.helpContent = _el.querySelector('#jbp-help-content');
        _refs.helpClose   = _el.querySelector('#jbp-help-close');
        _refs.closeBtn    = _el.querySelector('#jbp-close-btn');
        _refs.settings    = _el.querySelector('#jbp-settings');

        _refs.canvas.width = _refs.canvas.clientWidth ? _refs.canvas.clientWidth * dpr : 800 * dpr;
        _refs.canvas.height = 64 * dpr;
        _refs.ctx = _refs.canvas.getContext('2d');

        _refs.closeBtn.addEventListener('click', closeLocally);
        _refs.albumTrig.addEventListener('click', function(e) {
            e.stopPropagation();
            _refs.albumWrap.classList.toggle('open');
        });
        _refs.albumOpts.addEventListener('click', function(e) {
            var opt = e.target;
            while (opt && !opt.classList.contains('jbp-album-option')) opt = opt.parentElement;
            if (!opt) return;
            currentAlbumFilter = opt.getAttribute('data-album') || '';
            _refs.albumWrap.classList.remove('open');
            renderAlbumSelect();
            renderTrackList(currentAlbumFilter);
        });
        _refs.pauseBtn.addEventListener('click', onPauseClick);
        _refs.stopBtn.addEventListener('click', onStopClick);
        _refs.helpBtn.addEventListener('click', onHelpClick);
        _refs.helpClose.addEventListener('click', function() {
            _refs.helpModal.classList.remove('visible');
        });
        _refs.progBar.addEventListener('mousedown', onSeekStart);
        _refs.settings.addEventListener('click', onSettingsClick);
        // 滑条
        initSlider('volGlobal', 'volGlobal', 50);
        initSlider('volBgm', 'volBgm', 80);
        // 点击外部关闭专辑下拉
        _onDocClick = function(e) {
            if (_refs.albumWrap && !_refs.albumWrap.contains(e.target)) {
                _refs.albumWrap.classList.remove('open');
            }
        };
        return _el;
    }

    var _onDocClick = null;
    var _bridgeAudioH = null;
    var _bridgeCatalogH = null;
    var _bridgeCatalogUpdateH = null;
    var _bridgeHelpTextH = null;
    var _uiSubs = [];   // [{key, handler}] 用于 UiData.off
    var _helpLoaded = false;

    function onOpen() {
        _opened = true;
        if (_onDocClick) document.addEventListener('click', _onDocClick);

        _bridgeAudioH = onAudioData;
        _bridgeCatalogH = onCatalog;
        _bridgeCatalogUpdateH = onCatalogUpdate;
        _bridgeHelpTextH = onHelpText;
        Bridge.on('audio', _bridgeAudioH);
        Bridge.on('catalog', _bridgeCatalogH);
        Bridge.on('catalogUpdate', _bridgeCatalogUpdateH);
        Bridge.on('helpText', _bridgeHelpTextH);

        if (typeof UiData !== 'undefined') {
            // 先 seed 当前已知 bgm 标题（panel 晚于启动期打开 → UiData.on() 不会重放历史值）
            if (UiData.get) {
                var seedBgm = UiData.get('bgm');
                if (typeof seedBgm === 'string' && seedBgm.length > 0) setTitle(seedBgm);
                var seedJbo = UiData.get('jbo');
                if (typeof seedJbo !== 'undefined') {
                    settingsState.override = (seedJbo === '1');
                    syncSettingUI('override', settingsState.override);
                }
                var seedJbr = UiData.get('jbr');
                if (typeof seedJbr !== 'undefined') {
                    settingsState.trueRandom = (seedJbr === '1');
                    syncSettingUI('trueRandom', settingsState.trueRandom);
                }
                var seedJbm = UiData.get('jbm');
                if (typeof seedJbm === 'string' && seedJbm.length > 0) syncPlayModeUI(seedJbm);
                var seedVg = UiData.get('vg');
                if (typeof seedVg === 'string') {
                    var vgNum = parseInt(seedVg, 10);
                    if (!isNaN(vgNum)) setSliderValue('volGlobal', vgNum);
                }
                var seedVb = UiData.get('vb');
                if (typeof seedVb === 'string') {
                    var vbNum = parseInt(seedVb, 10);
                    if (!isNaN(vbNum)) setSliderValue('volBgm', vbNum);
                }
            }
            subscribeUi('bgm', function(val) { setTitle(val); });
            subscribeUi('jbo', function(val) {
                settingsState.override = (val === '1'); syncSettingUI('override', settingsState.override);
            });
            subscribeUi('jbr', function(val) {
                settingsState.trueRandom = (val === '1'); syncSettingUI('trueRandom', settingsState.trueRandom);
            });
            subscribeUi('jbm', function(val) { syncPlayModeUI(val); });
            subscribeUi('vg', function(val) {
                var v = parseInt(val, 10); if (!isNaN(v)) setSliderValue('volGlobal', v);
            });
            subscribeUi('vb', function(val) {
                var v = parseInt(val, 10); if (!isNaN(v)) setSliderValue('volBgm', v);
            });
        }
        // 请求最新 catalog（C# 在初始化时主动 push 一次；保险二次请求）
        Bridge.send({type: 'jukebox', cmd: 'requestCatalog'});
    }

    function subscribeUi(key, handler) {
        UiData.on(key, handler);
        _uiSubs.push({key: key, handler: handler});
    }

    function cleanup() {
        if (!_opened) return;
        _opened = false;
        if (_onDocClick) document.removeEventListener('click', _onDocClick);
        if (_bridgeAudioH) Bridge.off('audio', _bridgeAudioH);
        if (_bridgeCatalogH) Bridge.off('catalog', _bridgeCatalogH);
        if (_bridgeCatalogUpdateH) Bridge.off('catalogUpdate', _bridgeCatalogUpdateH);
        if (_bridgeHelpTextH) Bridge.off('helpText', _bridgeHelpTextH);
        _bridgeAudioH = _bridgeCatalogH = _bridgeCatalogUpdateH = _bridgeHelpTextH = null;
        if (typeof UiData !== 'undefined' && UiData.off) {
            for (var i = 0; i < _uiSubs.length; i++) {
                UiData.off(_uiSubs[i].key, _uiSubs[i].handler);
            }
        }
        _uiSubs = [];
        if (seekRect) {
            document.removeEventListener('mousemove', onSeekMove);
            document.removeEventListener('mouseup', onSeekEnd);
            seekRect = null;
        }
        if (_refs.helpModal) _refs.helpModal.classList.remove('visible');
        // 清理瞬态状态：下次 onOpen 重新 seed UiData 当前值
        // （否则关闭期间 BGM 切空 / 进度推进 / 设置改动后，重开会先闪一帧旧数据）
        bgmTitle = '';
        currentDuration = 0;
        playing = false;
        isPaused = false;
        histIdx = 0;
        histLen = 0;
        if (_refs.title) _refs.title.textContent = '未播放';
        if (_refs.time) _refs.time.textContent = '';
        if (_refs.progFill) _refs.progFill.style.width = '0%';
        if (_refs.pauseBtn) {
            _refs.pauseBtn.classList.remove('paused');
            _refs.pauseBtn.textContent = '‖';
        }
        if (_refs.ctx && _refs.canvas) {
            _refs.ctx.clearRect(0, 0, _refs.canvas.width, _refs.canvas.height);
        }
    }

    function setTitle(title) {
        bgmTitle = title || '';
        if (_refs.title) _refs.title.textContent = bgmTitle || '未播放';
        if (!bgmTitle && _refs.time) _refs.time.textContent = '';
        if (!bgmTitle && _refs.progFill) _refs.progFill.style.width = '0%';
        updateActiveTrack();
    }

    function fmtTime(sec) {
        if (!sec || sec <= 0) return '--:--';
        var m = Math.floor(sec / 60);
        var s = Math.floor(sec % 60);
        return (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s;
    }

    function onAudioData(data) {
        var peakL = data.l || 0;
        var peakR = data.r || 0;
        var wasPlaying = playing;
        playing = data.p === 1;
        if (playing && !wasPlaying) syncPauseState(true);
        var cursor = data.c || 0;
        var duration = data.d || 0;
        currentDuration = duration;
        histL[histIdx] = peakL;
        histR[histIdx] = peakR;
        histIdx = (histIdx + 1) % HISTORY;
        if (histLen < HISTORY) histLen++;

        if (duration > 0 && bgmTitle) {
            var pct = Math.min(cursor / duration, 1) * 100;
            if (_refs.progFill) _refs.progFill.style.width = pct + '%';
            if (_refs.time) _refs.time.textContent = fmtTime(cursor) + '/' + fmtTime(duration);
        } else {
            if (_refs.progFill) _refs.progFill.style.width = '0%';
            if (_refs.time) _refs.time.textContent = '';
        }
        var now = performance.now ? performance.now() : Date.now();
        if (!visualizersDisabled() && now - lastWaveRenderAt >= WAVE_RENDER_MS) {
            lastWaveRenderAt = now;
            render();
        }
    }

    function visualizersDisabled() {
        var root = document.documentElement;
        return document.hidden || root.classList.contains('perf-low-effects') || root.classList.contains('perf-no-visualizers');
    }

    function render() {
        if (!_refs.ctx) return;
        var w = _refs.canvas.width;
        var h = _refs.canvas.height;
        var midY = h / 2;
        var ctx = _refs.ctx;
        ctx.clearRect(0, 0, w, h);
        if (histLen === 0) return;
        var barW = w / HISTORY;
        var maxH = midY - 1 * dpr;
        for (var i = 0; i < histLen; i++) {
            var idx = (histIdx - histLen + i + HISTORY) % HISTORY;
            var lv = histL[idx];
            var rv = histR[idx];
            var x = i * barW;
            var age = (histLen - 1 - i) / Math.max(histLen - 1, 1);
            var alpha = playing ? (0.3 + 0.7 * (1 - age)) : 0.15;
            var hL = Math.max(1 * dpr, lv * maxH);
            ctx.fillStyle = 'rgba(102,204,255,' + alpha + ')';
            ctx.fillRect(x, midY - hL, Math.max(barW - 0.5, 1), hL);
            var hR = Math.max(1 * dpr, rv * maxH);
            ctx.fillStyle = 'rgba(150,220,255,' + (alpha * 0.8) + ')';
            ctx.fillRect(x, midY, Math.max(barW - 0.5, 1), hR);
        }
        ctx.fillStyle = 'rgba(255,255,255,0.15)';
        ctx.fillRect(0, midY - 0.5 * dpr, w, 1 * dpr);
    }

    function onCatalog(data) {
        albums = {}; allTracks = [];
        var tracks = data.tracks || [];
        for (var i = 0; i < tracks.length; i++) {
            var t = tracks[i];
            if (!albums[t.album]) albums[t.album] = [];
            albums[t.album].push(t);
            allTracks.push(t);
        }
        renderAlbumSelect();
        renderTrackList(currentAlbumFilter);
    }

    function onCatalogUpdate(data) {
        var added = data.added || [];
        var removed = data.removed || [];
        for (var r = 0; r < removed.length; r++) removeTrackByTitle(removed[r]);
        for (var a = 0; a < added.length; a++) {
            var t = added[a];
            if (!albums[t.album]) albums[t.album] = [];
            albums[t.album].push(t);
            allTracks.push(t);
        }
        renderAlbumSelect();
        renderTrackList(currentAlbumFilter);
    }

    function removeTrackByTitle(title) {
        for (var alb in albums) {
            var arr = albums[alb];
            for (var i = arr.length - 1; i >= 0; i--) {
                if (arr[i].title === title) arr.splice(i, 1);
            }
            if (arr.length === 0) delete albums[alb];
        }
        for (var j = allTracks.length - 1; j >= 0; j--) {
            if (allTracks[j].title === title) allTracks.splice(j, 1);
        }
    }

    function escHtml(s) {
        return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }

    function renderAlbumSelect() {
        if (!_refs.albumOpts) return;
        _refs.albumOpts.innerHTML = '';
        var allOpt = document.createElement('div');
        allOpt.className = 'jbp-album-option' + (currentAlbumFilter === '' ? ' active' : '');
        allOpt.textContent = '全部';
        allOpt.setAttribute('data-album', '');
        _refs.albumOpts.appendChild(allOpt);
        var names = [];
        for (var alb in albums) names.push(alb);
        names.sort();
        for (var i = 0; i < names.length; i++) {
            var opt = document.createElement('div');
            opt.className = 'jbp-album-option' + (names[i] === currentAlbumFilter ? ' active' : '');
            opt.textContent = names[i] + ' (' + albums[names[i]].length + ')';
            opt.setAttribute('data-album', names[i]);
            _refs.albumOpts.appendChild(opt);
        }
        if (_refs.albumLabel) {
            _refs.albumLabel.textContent = currentAlbumFilter
                ? currentAlbumFilter + ' (' + (albums[currentAlbumFilter] || []).length + ')'
                : '全部';
        }
    }

    function renderTrackList(albumFilter) {
        if (!_refs.trackList) return;
        _refs.trackList.innerHTML = '';
        var source = albumFilter ? (albums[albumFilter] || []) : allTracks;
        for (var i = 0; i < source.length; i++) {
            var div = document.createElement('div');
            div.className = 'jbp-track-item';
            div.textContent = source[i].title;
            div.setAttribute('data-title', source[i].title);
            if (source[i].title === bgmTitle) div.classList.add('active');
            div.addEventListener('click', onTrackClick);
            _refs.trackList.appendChild(div);
        }
    }

    function onTrackClick(e) {
        var el = e.target;
        while (el && !el.getAttribute('data-title')) el = el.parentElement;
        var title = el ? el.getAttribute('data-title') : null;
        if (title) Bridge.send({type: 'jukebox', cmd: 'play', title: title});
    }

    function updateActiveTrack() {
        if (!_refs.trackList) return;
        var items = _refs.trackList.children;
        for (var i = 0; i < items.length; i++) {
            var t = items[i].getAttribute('data-title');
            if (t === bgmTitle) items[i].classList.add('active');
            else items[i].classList.remove('active');
        }
    }

    function onPauseClick() {
        isPaused = !isPaused;
        _refs.pauseBtn.classList.toggle('paused', isPaused);
        _refs.pauseBtn.textContent = isPaused ? '▶' : '‖';
        Bridge.send({type: 'jukebox', cmd: isPaused ? 'pause' : 'resume'});
    }

    function onStopClick() {
        isPaused = false;
        if (_refs.pauseBtn) {
            _refs.pauseBtn.classList.remove('paused');
            _refs.pauseBtn.textContent = '‖';
        }
        Bridge.send({type: 'jukebox', cmd: 'stop'});
    }

    function syncPauseState(isPlayingNow) {
        if (isPlayingNow && isPaused) {
            isPaused = false;
            if (_refs.pauseBtn) {
                _refs.pauseBtn.classList.remove('paused');
                _refs.pauseBtn.textContent = '‖';
            }
        }
    }

    // ── 音量滑条 ──
    function initSlider(key, cmd, defaultVal) {
        var row = _el.querySelector('.jb-slider-row[data-slider="' + key + '"]');
        if (!row) return;
        var s = {
            track: row.querySelector('.jb-slider-track'),
            fill:  row.querySelector('.jb-slider-fill'),
            thumb: row.querySelector('.jb-slider-thumb'),
            valEl: row.querySelector('.jb-slider-value'),
            value: defaultVal,
            cmd: cmd
        };
        sliders[key] = s;
        updateSliderUI(s);
        s.track.addEventListener('mousedown', function(e) {
            applySliderFromEvent(s, e);
            var onMove = function(ev) { applySliderFromEvent(s, ev); };
            var onUp = function() {
                document.removeEventListener('mousemove', onMove);
                document.removeEventListener('mouseup', onUp);
            };
            document.addEventListener('mousemove', onMove);
            document.addEventListener('mouseup', onUp);
        });
    }

    function applySliderFromEvent(s, e) {
        var rect = s.track.getBoundingClientRect();
        var pct = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
        s.value = Math.round(pct * 100);
        updateSliderUI(s);
        Bridge.send({type: 'jukebox', cmd: s.cmd, value: s.value});
    }

    function updateSliderUI(s) {
        var pct = s.value + '%';
        if (s.fill) s.fill.style.width = pct;
        if (s.thumb) s.thumb.style.left = pct;
        if (s.valEl) s.valEl.textContent = s.value;
    }

    function setSliderValue(key, val) {
        var s = sliders[key];
        if (!s) return;
        s.value = Math.max(0, Math.min(100, val));
        updateSliderUI(s);
    }

    // ── 设置点击 ──
    function onSettingsClick(e) {
        var item = e.target;
        while (item && !item.classList.contains('jb-setting-item')) item = item.parentElement;
        if (!item) return;
        var key = item.getAttribute('data-key');
        if (!key) return;
        if (item.classList.contains('jb-radio')) {
            var val = item.getAttribute('data-value');
            settingsState[key] = val;
            var siblings = _refs.settings.querySelectorAll('.jb-radio[data-key="' + key + '"]');
            for (var i = 0; i < siblings.length; i++) {
                siblings[i].classList.toggle('active', siblings[i].getAttribute('data-value') === val);
            }
            Bridge.send({type: 'jukebox', cmd: 'playMode', value: val});
            return;
        }
        settingsState[key] = !settingsState[key];
        item.classList.toggle('active', settingsState[key]);
        if (key === 'override') {
            Bridge.send({type: 'jukebox', cmd: 'override', value: settingsState.override});
        } else if (key === 'trueRandom') {
            Bridge.send({type: 'jukebox', cmd: 'trueRandom', value: settingsState.trueRandom});
        }
    }

    function syncSettingUI(key, active) {
        if (!_refs.settings) return;
        var items = _refs.settings.querySelectorAll('.jb-setting-item[data-key="' + key + '"]');
        for (var i = 0; i < items.length; i++) items[i].classList.toggle('active', active);
    }

    function syncPlayModeUI(mode) {
        if (!_refs.settings) return;
        settingsState.playMode = mode;
        var radios = _refs.settings.querySelectorAll('.jb-radio[data-key="playMode"]');
        for (var i = 0; i < radios.length; i++) {
            radios[i].classList.toggle('active', radios[i].getAttribute('data-value') === mode);
        }
    }

    // ── 进度条 seek ──
    function onSeekStart(e) {
        if (currentDuration <= 0) return;
        seekRect = _refs.progBar.getBoundingClientRect();
        sendSeek(e);
        document.addEventListener('mousemove', onSeekMove);
        document.addEventListener('mouseup', onSeekEnd);
    }
    function onSeekMove(e) { sendSeek(e); }
    function onSeekEnd() {
        seekRect = null;
        document.removeEventListener('mousemove', onSeekMove);
        document.removeEventListener('mouseup', onSeekEnd);
    }
    function sendSeek(e) {
        if (!seekRect || seekRect.width <= 0) return;
        var pct = Math.max(0, Math.min(1, (e.clientX - seekRect.left) / seekRect.width));
        Bridge.send({type: 'jukebox', cmd: 'seek', sec: pct * currentDuration});
    }

    // ── 帮助 markdown ──
    function onHelpClick() {
        if (!_helpLoaded) {
            _refs.helpContent.textContent = '加载中...';
            Bridge.send({type: 'jukebox', cmd: 'loadHelp'});
        }
        _refs.helpModal.classList.toggle('visible');
    }

    function onHelpText(data) {
        _helpLoaded = true;
        if (typeof marked !== 'undefined' && marked.parse) {
            _refs.helpContent.innerHTML = marked.parse(data.text || '');
        } else {
            _refs.helpContent.textContent = data.text || '';
        }
    }
})();
