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
 *   旧 modules/jukebox.js 已于 2026-07-28 删除；本面板独立一份 listener，行为收敛于 panel 关闭时清理）。
 *
 * 美化轮 2026-07-28：CRT 开机动画 / 标题+曲名 marquee / 点曲 pending / active 滚动定位 / SVG 图标 /
 *   LED 状态灯 / 待机屏 / 专辑分组 sticky 头 / 下拉与弹窗过渡 / 专辑 chip / 首屏 stagger /
 *   磷光主题单选（绿磷屏|琥珀磷屏，localStorage 持久化）/ 进度条 scaleX / 列表 content-visibility。
 *
 * 交互补齐轮 2026-08-10（借双栏工作台横切契约，但不并入其视觉/治理体系——点歌机无物品写 authority）：
 *   键盘可达（曲目 Enter/Space 点曲 + 方向键导航，roving tabindex / 滑条与进度条方向键 + Home/End /
 *   设置项与控制台按钮 Enter/Space / 专辑下拉全键盘操作）/ Esc 逐层只退一级（帮助弹窗 → 专辑下拉 → 面板，
 *   统一收口于 closeLocally，生产环境 Esc 由 C# panel_esc 桥消息进入，web 侧不另设 DOM Esc 监听以免双通道重复消费）/
 *   帮助弹窗焦点圈定 + 关闭返还 / focus-visible 焦点环（features.css jukebox 段）/ 关键控件 role + ARIA。
 */
(function() {
    'use strict';

    if (typeof Panels === 'undefined') return;

    var _el, _shellEl;
    var _scaleHandle = null;   // 沉浸全屏化：PanelScale 句柄
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
    var currentCursor = 0;   // 最近一次音频包的播放进度（秒）：键盘 seek 的基准，音频回包持续校正
    var _ariaProgSec = -1;   // 进度条 aria-valuenow/max 秒级去抖
    var _ariaProgMax = -1;
    var oscPhase = 0;      // 示波器弦载波相位
    var _rafId = null;     // requestAnimationFrame 渲染循环句柄
    var displayHistL = new Float32Array(HISTORY); // 平滑插值显示缓冲
    var displayHistR = new Float32Array(HISTORY);

    var albums = {};       // 专辑名 → [{title,weight}]
    var allTracks = [];
    var currentAlbumFilter = '';

    var settingsState = {
        override: false,
        trueRandom: false,
        playMode: 'singleLoop',
        phosphor: 'green'
    };
    var sliders = {};
    var isPaused = false;
    var seekRect = null;

    // ── 美化轮（2026-07-28）：内联 SVG 图标 / 磷光主题 / 点曲 pending ──
    // currentColor 继承按钮文字色，消除 Unicode 符号（‖ ⏼ ?）的字体回退差异
    var ICON_PLAY  = '<svg viewBox="0 0 12 12" fill="currentColor" aria-hidden="true"><path d="M3 2 L10 6 L3 10 Z"/></svg>';
    var ICON_PAUSE = '<svg viewBox="0 0 12 12" fill="currentColor" aria-hidden="true"><rect x="2.5" y="2" width="2.6" height="8"/><rect x="6.9" y="2" width="2.6" height="8"/></svg>';
    var ICON_STOP  = '<svg viewBox="0 0 12 12" fill="currentColor" aria-hidden="true"><rect x="2.5" y="2.5" width="7" height="7"/></svg>';
    var ICON_HELP  = '<svg viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" aria-hidden="true"><path d="M4.2 4.4 C4.2 3 5.1 2.2 6 2.2 C7 2.2 7.8 3 7.8 4 C7.8 4.9 7.2 5.3 6.6 5.8 C6.1 6.2 6 6.5 6 7.1"/><circle cx="6" cy="9.3" r="0.9" fill="currentColor" stroke="none"/></svg>';
    var ICON_CLOSE = '<svg viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" aria-hidden="true"><path d="M3 3 L9 9 M9 3 L3 9"/></svg>';

    function setIcon(el, svg, name) {
        el.innerHTML = svg;
        el.setAttribute('data-icon', name);
    }

    // 磷光主题：CSS 侧走 --jb-accent 变量（applyTheme 内联覆盖），canvas 侧走本调色板
    var THEME_STORAGE_KEY = 'cf7-jukebox-theme';
    var PALETTES = {
        green: {
            accent: '#c8ff4c', accentRgb: '200,255,76', screenBg: '#070b06',
            trail: 'rgba(7, 11, 6, 0.5)',
            baseLine: 'rgba(200, 255, 76, 0.1)',
            lGlow: 'rgba(170, 255, 50, 0.3)',   lCore: 'rgba(230, 255, 180, 0.95)',
            rGlow: 'rgba(90,  255, 120, 0.25)', rCore: 'rgba(180, 255, 210, 0.90)',
            standbyLine: 'rgba(200, 255, 76, 0.30)', standbyText: 'rgba(200, 255, 76, 0.55)'
        },
        amber: {
            accent: '#ffb000', accentRgb: '255,176,0', screenBg: '#0b0803',
            trail: 'rgba(11, 8, 3, 0.5)',
            baseLine: 'rgba(255, 176, 0, 0.1)',
            lGlow: 'rgba(255, 176, 0, 0.3)',    lCore: 'rgba(255, 236, 190, 0.95)',
            rGlow: 'rgba(255, 132, 20, 0.25)',  rCore: 'rgba(255, 208, 150, 0.90)',
            standbyLine: 'rgba(255, 176, 0, 0.30)', standbyText: 'rgba(255, 176, 0, 0.55)'
        }
    };
    var palette = PALETTES.green;

    // 点曲 pending：点击立即反馈，UiData 'bgm' 确认后转 active，超时兜底清除
    var _pendingTitle = '';
    var _pendingTimer = null;

    // 时间文本写入去抖：音频数据 ~60ms 一推，秒级文本每秒才变一次，值不变不碰 DOM
    var _lastStartText = '';
    var _lastEndText = '';

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
    ///         三条入口（× 按钮 / ESC / backdrop click）共用，避免单边漏 Panels.close 让 _active 滞留。
    ///         ESC 先做分层消费（帮助弹窗 → 专辑下拉，每层只退一级），确认无浮层后才真正关面板。</summary>
    function closeLocally(reason) {
        if (reason === 'escape') {
            if (isHelpOpen()) { closeHelpModal(); return; }
            if (_refs.albumWrap && _refs.albumWrap.classList.contains('open')) {
                setAlbumDropdownOpen(false);
                return;
            }
        }
        try { Panels.close(); } catch (e) {}
        Bridge.send({type: 'panel', cmd: 'close', panel: 'jukebox'});
    }

    function createDOM() {
        _el = document.createElement('div');
        _el.className = 'jbp-panel';
        _el.innerHTML = [
            '<div class="jbp-header">',
                '<span class="jbp-title-static">&#9835; 点歌台</span>',
                '<span class="jbp-current-title" id="jbp-current-title"><span class="marquee-inner">未播放</span></span>',
                '<span class="jbp-album-chip" id="jbp-album-chip" style="display:none"></span>',
                '<div class="jbp-header-spacer"></div>',
                '<span class="jbp-led" id="jbp-led" title="播放状态"></span>',
                '<div class="jbp-pause-btn jb-ctrl-btn jbp-primary" id="jbp-pause-btn" data-icon="pause" title="暂停/继续" role="button" tabindex="0" aria-label="暂停/继续">' + ICON_PAUSE + '</div>',
                '<div class="jbp-stop-btn jb-ctrl-btn" id="jbp-stop-btn" data-icon="stop" title="停止(回到默认BGM)" role="button" tabindex="0" aria-label="停止(回到默认BGM)">' + ICON_STOP + '</div>',
                '<div class="jbp-help-btn jb-ctrl-btn" id="jbp-help-btn" data-icon="help" title="帮助" role="button" tabindex="0" aria-label="帮助">' + ICON_HELP + '</div>',
                '<button class="jbp-close-btn" id="jbp-close-btn" data-icon="close" type="button" title="关闭" aria-label="关闭">' + ICON_CLOSE + '</button>',
            '</div>',
            // 沉浸全屏化 2026-06-12：双栏控制台（左 Now-Playing：波形+进度+设置；右 曲库：专辑下拉+曲目列表）
            '<div class="jbp-body">',
                '<div class="jbp-now">',
                    '<div class="jbp-wave-bezel">',
                        '<canvas class="jbp-wave" id="jbp-wave" width="800" height="64"></canvas>',
                        '<span class="jbp-wave-corner jbp-wave-corner-tl"></span>',
                        '<span class="jbp-wave-corner jbp-wave-corner-tr"></span>',
                        '<span class="jbp-wave-corner jbp-wave-corner-bl"></span>',
                        '<span class="jbp-wave-corner jbp-wave-corner-br"></span>',
                    '</div>',
                    '<div class="jbp-progress-row">',
                        '<span class="jbp-prog-time" id="jbp-prog-time-start">00:00</span>',
                        '<div class="jbp-progress" id="jbp-progress" tabindex="0" role="slider" aria-label="播放进度" aria-valuemin="0" aria-valuemax="0" aria-valuenow="0"><div class="jbp-prog-fill" id="jbp-prog-fill"></div></div>',
                        '<span class="jbp-prog-time" id="jbp-prog-time-end">00:00</span>',
                    '</div>',
                    '<div class="jbp-settings" id="jbp-settings">',
                        '<div class="jb-setting-group-label">音量控制</div>',
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
                        '<div class="jb-setting-group-label">播放源设置</div>',
                        '<div class="jb-setting-row jb-setting-item" data-key="override" tabindex="0" role="checkbox" aria-checked="false">',
                            '<span class="jb-setting-dot"></span>',
                            '<span class="jb-setting-label">覆盖关卡BGM</span>',
                        '</div>',
                        '<div class="jb-setting-row jb-setting-item" data-key="trueRandom" tabindex="0" role="checkbox" aria-checked="false">',
                            '<span class="jb-setting-dot"></span>',
                            '<span class="jb-setting-label">真随机</span>',
                        '</div>',
                        '<div class="jb-setting-divider"></div>',
                        '<div class="jb-setting-group-label">播放模式</div>',
                        '<div class="jb-setting-row jb-setting-item jb-radio" data-key="playMode" data-value="singleLoop" tabindex="0" role="radio" aria-checked="true">',
                            '<span class="jb-setting-dot"></span>',
                            '<span class="jb-setting-label">单曲循环</span>',
                        '</div>',
                        '<div class="jb-setting-row jb-setting-item jb-radio" data-key="playMode" data-value="albumLoop" tabindex="0" role="radio" aria-checked="false">',
                            '<span class="jb-setting-dot"></span>',
                            '<span class="jb-setting-label">专辑循环</span>',
                        '</div>',
                        '<div class="jb-setting-row jb-setting-item jb-radio" data-key="playMode" data-value="playOnce" tabindex="0" role="radio" aria-checked="false">',
                            '<span class="jb-setting-dot"></span>',
                            '<span class="jb-setting-label">播完回默认</span>',
                        '</div>',
                        '<div class="jb-setting-divider"></div>',
                        '<div class="jb-setting-group-label">显示</div>',
                        '<div class="jb-setting-row jb-setting-item jb-radio" data-key="phosphor" data-value="green" tabindex="0" role="radio" aria-checked="true">',
                            '<span class="jb-setting-dot"></span>',
                            '<span class="jb-setting-label">绿磷屏</span>',
                        '</div>',
                        '<div class="jb-setting-row jb-setting-item jb-radio" data-key="phosphor" data-value="amber" tabindex="0" role="radio" aria-checked="false">',
                            '<span class="jb-setting-dot"></span>',
                            '<span class="jb-setting-label">琥珀磷屏</span>',
                        '</div>',
                    '</div>',
                '</div>',
                '<div class="jbp-library">',
                    '<div class="jbp-browser-row">',
                        '<div class="jbp-album-dropdown" id="jbp-album-dropdown">',
                            '<div class="jbp-album-trigger" id="jbp-album-trigger" tabindex="0" role="button" aria-haspopup="listbox" aria-expanded="false">',
                                '<span class="jbp-album-label" id="jbp-album-label">全部</span>',
                                '<span class="jb-dd-arrow">&#9662;</span>',
                            '</div>',
                            '<div class="jbp-album-options" id="jbp-album-options" role="listbox"></div>',
                        '</div>',
                    '</div>',
                    '<div class="jbp-track-list" id="jbp-track-list"></div>',
                '</div>',
            '</div>',
            '<div class="jbp-help-modal" id="jbp-help-modal" role="dialog" aria-modal="true" aria-label="点歌台帮助">',
                '<div class="jbp-help-content" id="jbp-help-content"></div>',
                '<button class="jbp-help-close" id="jbp-help-close" type="button">关闭</button>',
            '</div>'
        ].join('');

        _refs.title       = _el.querySelector('#jbp-current-title');
        _refs.albumChip   = _el.querySelector('#jbp-album-chip');
        _refs.led         = _el.querySelector('#jbp-led');
        _refs.canvas      = _el.querySelector('#jbp-wave');
        _refs.progFill    = _el.querySelector('#jbp-prog-fill');
        _refs.progBar     = _el.querySelector('#jbp-progress');
        _refs.progTimeStart = _el.querySelector('#jbp-prog-time-start');
        _refs.progTimeEnd   = _el.querySelector('#jbp-prog-time-end');
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

        _refs.closeBtn.addEventListener('click', function() { closeLocally('button'); });
        _refs.albumTrig.addEventListener('click', function(e) {
            e.stopPropagation();
            setAlbumDropdownOpen(!_refs.albumWrap.classList.contains('open'));
        });
        _refs.albumOpts.addEventListener('click', function(e) {
            var opt = e.target;
            while (opt && !opt.classList.contains('jbp-album-option')) opt = opt.parentElement;
            if (!opt) return;
            selectAlbumOption(opt);
        });
        _refs.pauseBtn.addEventListener('click', onPauseClick);
        _refs.stopBtn.addEventListener('click', onStopClick);
        _refs.helpBtn.addEventListener('click', onHelpClick);
        _refs.helpClose.addEventListener('click', closeHelpModal);
        _refs.progBar.addEventListener('mousedown', onSeekStart);
        _refs.settings.addEventListener('click', onSettingsClick);
        // 键盘可达性：面板级单一 keydown 委派（Enter/Space/方向键/Home/End/Tab 圈定）
        _el.addEventListener('keydown', onPanelKeydown);
        // 滑条
        initSlider('volGlobal', 'volGlobal', 50);
        initSlider('volBgm', 'volBgm', 80);
        // 点击外部关闭专辑下拉
        _onDocClick = function(e) {
            if (_refs.albumWrap && !_refs.albumWrap.contains(e.target)) {
                setAlbumDropdownOpen(false);
            }
        };
        // CRT 开机动画结束即摘除 class，下次 onOpen 可重新触发
        _el.addEventListener('animationend', function(e) {
            if (e.animationName === 'jbpBoot') _el.classList.remove('is-booting');
        });
        // 标题 marquee：元素随 panel 常驻，observer 建一次即可；尺寸就绪/变化时重测溢出
        if (typeof ResizeObserver !== 'undefined') {
            _titleMarqueeObserver = new ResizeObserver(function() {
                checkMarqueeOverflow(_refs.title);
            });
            _titleMarqueeObserver.observe(_refs.title);
        }
        // 磷光主题：纯视觉偏好，localStorage 本地持久化（不经 Flash 桥）
        applyTheme(loadTheme());
        // 沉浸全屏化：固定 1024×576 画布(.jbp-panel)包进共享 .panel-scale-shell，整体等比缩放铺满全 anchor
        _shellEl = document.createElement('div');
        _shellEl.className = 'panel-scale-shell jbp-scale-shell';
        _shellEl.appendChild(_el);
        return _shellEl;
    }

    var _onDocClick = null;
    var _titleMarqueeObserver = null;   // 标题 marquee 溢出重测（createDOM 建一次，元素常驻不析构）
    var _bridgeAudioH = null;
    var _bridgeCatalogH = null;
    var _bridgeCatalogUpdateH = null;
    var _bridgeHelpTextH = null;
    var _uiSubs = [];   // [{key, handler}] 用于 UiData.off
    var _helpLoaded = false;

    function onOpen() {
        _opened = true;
        // CRT 开机动画：class 重触发（元素常驻，每次 open 重放一次；perf-low-effects 全局禁用动画）
        _el.classList.remove('is-booting');
        void _el.offsetWidth;
        _el.classList.add('is-booting');
        if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = (typeof PanelScale !== 'undefined') ? PanelScale.attach(_shellEl, 1024, 576) : null;
        // 双栏布局后波形画布按实际布局尺寸重设 buffer（createDOM 时元件未入 DOM 取不到尺寸，且 CSS 高度由 64→132），避免拉伸/模糊
        if (_refs.canvas) {
            var _dpr = window.devicePixelRatio || 1;
            _refs.canvas.width = Math.round((_refs.canvas.clientWidth || 800) * _dpr);
            _refs.canvas.height = Math.round((_refs.canvas.clientHeight || 132) * _dpr);
        }
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
        // 启动独立高帧率渲染循环（数据仍按 60ms 推送，但波形以显示器刷新率绘制）
        startRenderLoop();
    }

    function subscribeUi(key, handler) {
        UiData.on(key, handler);
        _uiSubs.push({key: key, handler: handler});
    }

    function cleanup() {
        if (!_opened) return;
        _opened = false;
        if (_scaleHandle) { _scaleHandle.detach(); _scaleHandle = null; }
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
        if (_refs.helpContent) _refs.helpContent.innerHTML = '';
        _helpLoaded = false;
        // 清理瞬态状态：下次 onOpen 重新 seed UiData 当前值
        // （否则关闭期间 BGM 切空 / 进度推进 / 设置改动后，重开会先闪一帧旧数据）
        bgmTitle = '';
        currentDuration = 0;
        currentCursor = 0;
        playing = false;
        isPaused = false;
        _pendingTitle = '';
        clearTimeout(_pendingTimer);
        if (_refs.title) setupMarquee(_refs.title, '未播放', 18);
        if (_refs.albumChip) _refs.albumChip.style.display = 'none';
        setProgress(0);
        setTimeTexts('00:00', '00:00');
        // 进度条 ARIA 与 JS 状态同步复位：元素常驻，残留旧值会让重开首帧读到过期进度
        _ariaProgSec = -1;
        _ariaProgMax = -1;
        if (_refs.progBar) {
            _refs.progBar.setAttribute('aria-valuenow', '0');
            _refs.progBar.setAttribute('aria-valuemax', '0');
        }
        if (_refs.pauseBtn) {
            _refs.pauseBtn.classList.remove('paused');
            setIcon(_refs.pauseBtn, ICON_PAUSE, 'pause');
        }
        updateLed();
        if (_refs.ctx && _refs.canvas) {
            _refs.ctx.clearRect(0, 0, _refs.canvas.width, _refs.canvas.height);
        }
        stopRenderLoop();
        histIdx = 0;
        histLen = 0;
        for (var hi = 0; hi < HISTORY; hi++) {
            displayHistL[hi] = 0;
            displayHistR[hi] = 0;
        }
    }

    function setTitle(title) {
        bgmTitle = title || '';
        if (_refs.title) {
            setupMarquee(_refs.title, bgmTitle || '未播放', 18);
            _refs.title.title = bgmTitle;
        }
        if (!bgmTitle) setProgress(0);
        // bgm 回包到达：点曲 pending 收敛为 active
        _pendingTitle = '';
        clearTimeout(_pendingTimer);
        updateAlbumChip();
        refreshTrackStates();
    }

    // ── 标题/曲名 marquee：内容溢出裁剪窗口时横向滚动 ──
    function setupMarquee(el, text, speed) {
        if (!el) return;
        if (speed == null) speed = 25;
        el.innerHTML = '<span class="marquee-inner">' + escHtml(text) + '</span>';
        el.classList.remove('scrolling');
        el._marqueeSpeed = speed;
        applyMarqueeVars(el, measureMarqueeOverflow(el), speed);
    }

    // inner 在非 scrolling 态被 max-width:100% 裁剪：scrollWidth=完整内容宽，offsetWidth=可见宽。
    // 先摘掉 scrolling 再测，避免类相关度量在 ResizeObserver 回调里自激抖动。
    function measureMarqueeOverflow(el) {
        if (!el) return 0;
        var inner = el.querySelector('.marquee-inner');
        if (!inner) return 0;
        el.classList.remove('scrolling');
        return inner.scrollWidth - inner.offsetWidth;
    }

    function applyMarqueeVars(el, overflow, speed) {
        if (overflow > 2) {
            var dist = overflow + 8;   // 右侧留呼吸空间
            var dur = Math.max(4, dist / (speed || 25));
            el.style.setProperty('--marquee-dist', '-' + dist + 'px');
            el.style.setProperty('--marquee-dur', dur + 's');
            el.classList.add('scrolling');
        } else {
            el.style.removeProperty('--marquee-dist');
            el.style.removeProperty('--marquee-dur');
            el.classList.remove('scrolling');
        }
    }

    function checkMarqueeOverflow(el) {
        if (!el) return;
        applyMarqueeVars(el, measureMarqueeOverflow(el), el._marqueeSpeed);
    }

    // 当前曲目所属专辑 chip：header 一眼定位（与“全部”视图的分组头同名）
    function updateAlbumChip() {
        if (!_refs.albumChip) return;
        var album = '';
        for (var i = 0; i < allTracks.length; i++) {
            if (allTracks[i].title === bgmTitle) { album = allTracks[i].album || ''; break; }
        }
        if (album && bgmTitle) {
            _refs.albumChip.textContent = album;
            _refs.albumChip.style.display = '';
        } else {
            _refs.albumChip.style.display = 'none';
        }
    }

    function fmtTime(sec) {
        if (!sec || sec <= 0) return '00:00';
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
        currentCursor = cursor;
        // 进度条 slider ARIA：秒级去抖，值变化才写属性（音频数据 ~60ms 一推）
        if (_refs.progBar) {
            var secNow = Math.floor(cursor);
            if (secNow !== _ariaProgSec) {
                _ariaProgSec = secNow;
                _refs.progBar.setAttribute('aria-valuenow', String(secNow));
            }
            var durNow = Math.floor(duration);
            if (durNow !== _ariaProgMax) {
                _ariaProgMax = durNow;
                _refs.progBar.setAttribute('aria-valuemax', String(durNow));
            }
        }
        histL[histIdx] = peakL;
        histR[histIdx] = peakR;
        histIdx = (histIdx + 1) % HISTORY;
        if (histLen < HISTORY) histLen++;

        if (duration > 0 && bgmTitle) {
            setProgress(Math.min(cursor / duration, 1));
            setTimeTexts(fmtTime(cursor), fmtTime(duration));
        } else {
            setProgress(0);
            setTimeTexts('00:00', '00:00');
        }
        updateLed();
        // 注：渲染已迁移到独立的 30fps 循环，数据更新与绘制解耦
    }

    // 进度条 fill 用 scaleX（合成层）；width 写入会随 60ms 数据推送持续触发布局
    function setProgress(p) {
        if (_refs.progFill) _refs.progFill.style.transform = 'scaleX(' + p + ')';
    }

    // 时间文本写入去抖：值不变不碰 DOM（缓存初始 ''，面板重建后首帧必写一次）
    function setTimeTexts(start, end) {
        if (start !== _lastStartText) {
            _lastStartText = start;
            if (_refs.progTimeStart) _refs.progTimeStart.textContent = start;
        }
        if (end !== _lastEndText) {
            _lastEndText = end;
            if (_refs.progTimeEnd) _refs.progTimeEnd.textContent = end;
        }
    }

    // LED 状态灯：播放=主题色呼吸 / 暂停=琥珀 / 空闲=熄灭
    function updateLed() {
        if (!_refs.led) return;
        _refs.led.classList.toggle('is-live', playing && !isPaused);
        _refs.led.classList.toggle('is-paused', isPaused);
    }

    function startRenderLoop() {
        stopRenderLoop();
        // 锁 30fps：Intel UHD 核显友好，同时避免 120/240Hz 显示器上过度消耗
        function loop() {
            if (!_opened) return;
            _rafId = setTimeout(loop, 33);
            if (visualizersDisabled()) {
                if (_refs.ctx && _refs.canvas) {
                    _refs.ctx.clearRect(0, 0, _refs.canvas.width, _refs.canvas.height);
                }
                return;
            }
            render();
        }
        _rafId = setTimeout(loop, 0);
    }

    function stopRenderLoop() {
        if (_rafId) {
            clearTimeout(_rafId);
            _rafId = null;
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

        // 低性能/隐藏页签：直接清空，不做视觉器渲染
        if (visualizersDisabled()) {
            ctx.clearRect(0, 0, w, h);
            return;
        }

        // 1. 解决【残留过强】与【画面脏】：提高擦除透明度 (0.18 -> 0.5)
        // 让拖影变短、收尾干脆利落，只保留极短的 CRT 物理余晖，防止画面积灰
        ctx.globalCompositeOperation = 'source-over';
        ctx.fillStyle = palette.trail;
        ctx.fillRect(0, 0, w, h);

        // 待机屏按“没有当前 BGM”判定；停止后音频通道仍会持续推送零峰值，不能用 histLen 判断。
        if (!bgmTitle) { renderStandby(ctx, w, h, midY); return; }
        // 已有曲名但首个音频包尚未到达时保持空屏，避免把加载窗口误标成待机。
        if (histLen === 0) return;

        // 数据平滑插值：目标 hist 每 ~60ms 更新一次，显示缓冲每帧向目标逼近，
        // 使 60ms 的数据跳变在高帧率渲染下过渡顺滑，消除顿挫感
        var interpK = 0.22;
        for (var hi = 0; hi < histLen; hi++) {
            var hidx = (histIdx - histLen + hi + HISTORY) % HISTORY;
            displayHistL[hidx] += (histL[hidx] - displayHistL[hidx]) * interpK;
            displayHistR[hidx] += (histR[hidx] - displayHistR[hidx]) * interpK;
        }

        var barW = w / (HISTORY - 1);
        var maxH = midY - 6 * dpr;

        // 2. 基准推力：锁 30fps 后，每帧增量需比 60fps 时减半左右，
        //    保持波形缓慢流动而非狂躁抖动
        oscPhase += playing ? 1.4 : 0.04;

        // --- 中心辅助基准线 (放底层，保持极其克制的透明度) ---
        ctx.globalCompositeOperation = 'source-over';
        ctx.shadowBlur = 0; // 彻底封杀 shadowBlur
        ctx.beginPath();
        ctx.moveTo(0, midY);
        ctx.lineTo(w, midY);
        ctx.lineWidth = 1 * dpr;
        ctx.strokeStyle = palette.baseLine;
        ctx.stroke();

        // 开启光学叠加混合 (交叠处会自动过曝爆白)
        ctx.globalCompositeOperation = 'lighter';

        // 分别绘制左右声道（传入参数：历史数据, 是否倒置, 外层发光色, 核心高亮色, 相位差）
        // 刻意把左右声道的颜色拉开了一点点层级，交叉时色彩会极其通透
        drawOscillator(displayHistL, true,  palette.lGlow, palette.lCore, 0);
        drawOscillator(displayHistR, false, palette.rGlow, palette.rCore, Math.PI);

        function drawOscillator(hist, isLeft, colorGlow, colorCore, phaseOffset) {
            ctx.beginPath();
            for (var i = 0; i < histLen; i++) {
                var idx = (histIdx - histLen + i + HISTORY) % HISTORY;
                var envelope = hist[idx];
                
                // 动态拉伸包络：让小音量时电波也有活力，不会变成一根死线
                envelope = playing ? Math.pow(Math.max(0.015, envelope), 0.8) : 0;

                var x = i * barW;
                var nx = i / (histLen - 1); // X坐标归一化 (0.0 ~ 1.0)
                var distanceDamp = Math.sin(nx * Math.PI); // 强制两端向中心线收束

                // 3. 解决【果冻感】：弃用纯平滑三角函数相乘，引入“非线性锐化”与“高频毛刺”
                var time = oscPhase + phaseOffset;
                
                // A. 基础流波：维持整体身段的低频扭动
                var baseWave = Math.sin(nx * 20 - time * 0.8);
                // B. 锐化电涌 (核心魔法！)：使用 3次方，它能把平滑的波峰压扁，瞬间拔高成一根尖锐的刺！
                var spikeWave = Math.pow(Math.sin(nx * 45 + time * 1.5), 3);
                // C. 物理杂讯：模拟高压电击穿空气的微小随机颤流 (随音量放大)
                var noise = (Math.random() - 0.5) * 0.35 * envelope;

                // 加法合成：基波(40%) + 尖刺(60%) + 噪音
                var synthWave = (baseWave * 0.4) + (spikeWave * 0.6) + noise;
                
                var offsetY = synthWave * envelope * distanceDamp * maxH;
                var y = midY + offsetY * (isLeft ? -1 : 1);

                if (i === 0) ctx.moveTo(x, midY);
                else ctx.lineTo(x, y);
            }
            
            // 4. 解决【画面脏】：废弃 shadowBlur，改用次世代 2D 渲染法 Dual-Stroke (双轨描边)
            ctx.lineJoin = 'bevel'; // 将连线转角从 round(圆润) 改为 bevel(斜切)，增强机械锋利感

            // 图层 A：外层光晕 (较宽的线，低透明度，模拟物理散射)
            ctx.lineWidth = 3.5 * dpr;
            ctx.strokeStyle = colorGlow;
            ctx.stroke();

            // 图层 B：高温电子内核 (极细的线，高亮度，无阴影，赋予光效真正的骨架实体)
            // 直接复用上一条 path，无需 beginPath，性能极高且发光极其干净！
            ctx.lineWidth = 0.8 * dpr;
            ctx.strokeStyle = colorCore;
            ctx.stroke();
        }
    }

    // ── 待机屏：无 BGM 时的呼吸正弦 + STANDBY 字符（复用 render 的 30fps 循环）──
    // 擦除透明度 0.5 的余晖会让静止字符产生轻微 CRT 辉光拖尾，属于刻意效果
    function renderStandby(ctx, w, h, midY) {
        oscPhase += 0.06;
        ctx.globalCompositeOperation = 'source-over';
        ctx.lineJoin = 'bevel';
        ctx.lineWidth = 1 * dpr;
        ctx.strokeStyle = palette.standbyLine;
        ctx.beginPath();
        var breathe = 0.5 + 0.5 * Math.sin(oscPhase * 0.09);
        var amp = (2 + 3 * breathe) * dpr;
        for (var x = 0; x <= w; x += 4 * dpr) {
            var y = midY + Math.sin(x * 0.03 / dpr + oscPhase * 0.12) * amp;
            if (x === 0) ctx.moveTo(x, y);
            else ctx.lineTo(x, y);
        }
        ctx.stroke();
        // 字符缓慢明灭
        ctx.globalAlpha = 0.35 + 0.25 * Math.sin(oscPhase * 0.15);
        ctx.fillStyle = palette.standbyText;
        ctx.font = (10 * dpr) + 'px Consolas, "Courier New", monospace';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText('- STANDBY -', w / 2, midY - 12 * dpr);
        ctx.globalAlpha = 1;
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
        // 首次打开时 UiData 的 bgm seed 早于 catalog 回包；目录到达后补做专辑归属对账。
        updateAlbumChip();
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
        // 当前曲目可能随增量目录获得、失去或改变专辑归属。
        updateAlbumChip();
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
        _refs.albumOpts.appendChild(createAlbumOption('', '全部'));
        var names = [];
        for (var alb in albums) names.push(alb);
        names.sort();
        for (var i = 0; i < names.length; i++) {
            _refs.albumOpts.appendChild(
                createAlbumOption(names[i], names[i] + ' (' + albums[names[i]].length + ')'));
        }
        if (_refs.albumLabel) {
            _refs.albumLabel.textContent = currentAlbumFilter
                ? currentAlbumFilter + ' (' + (albums[currentAlbumFilter] || []).length + ')'
                : '全部';
        }
    }

    // 专辑选项统一构造：class + data-album + listbox 语义（tabindex=-1，键盘导航 focus() 驱动）
    function createAlbumOption(album, label) {
        var opt = document.createElement('div');
        var selected = album === currentAlbumFilter;
        opt.className = 'jbp-album-option' + (selected ? ' active' : '');
        opt.textContent = label;
        opt.setAttribute('data-album', album);
        opt.setAttribute('role', 'option');
        opt.setAttribute('tabindex', '-1');
        opt.setAttribute('aria-selected', selected ? 'true' : 'false');
        return opt;
    }

    // 刚脱离 visibility:hidden 的容器，focus() 会被 Blink 判为不可聚焦而静默失败；
    // 且 visibility 过渡延迟（~150ms）完结前持续不可聚焦。短轮询直到聚焦落地或浮层关闭。
    // 刚脱离 visibility:hidden 的容器，focus() 会被 Blink 判为不可聚焦而静默失败；
    // 且 visibility 过渡延迟（~150ms）完结前持续不可聚焦。短轮询直到聚焦落地或浮层关闭。
    // resolveEl 每次重取节点：catalog 增量/全量刷新会重建选项 DOM，旧节点 detach 不等于放弃。
    function focusWhenReady(resolveEl, isOpen) {
        var tries = 0;
        (function attempt() {
            if (!isOpen()) return;
            var el = resolveEl();
            if (el && document.contains(el)) {
                el.focus();
                if (document.activeElement === el) return;
            }
            if (++tries > 20) return;   // ~600ms 封顶：聚焦失败不影响功能本身
            setTimeout(attempt, 30);
        })();
    }

    function isAlbumDropdownOpen() {
        return !!(_refs.albumWrap && _refs.albumWrap.classList.contains('open'));
    }

    // 当前应聚焦的专辑选项：优先当前筛选（active），退化为首项
    function resolveAlbumFocusOption() {
        if (!_refs.albumOpts) return null;
        return _refs.albumOpts.querySelector('.jbp-album-option.active')
            || _refs.albumOpts.querySelector('.jbp-album-option');
    }

    // 专辑下拉开合唯一入口：同步 aria-expanded；键盘打开时焦点落入当前/首选项，关闭时从选项内返还 trigger
    function setAlbumDropdownOpen(open) {
        if (!_refs.albumWrap) return;
        var wasOpen = _refs.albumWrap.classList.contains('open');
        if (open === wasOpen) return;
        _refs.albumWrap.classList.toggle('open', open);
        if (_refs.albumTrig) _refs.albumTrig.setAttribute('aria-expanded', open ? 'true' : 'false');
        if (open) {
            if (document.activeElement === _refs.albumTrig) {
                focusWhenReady(resolveAlbumFocusOption, isAlbumDropdownOpen);
            }
        } else if (_refs.albumOpts && _refs.albumOpts.contains(document.activeElement)) {
            // trigger 始终可见，可同步聚焦
            if (_refs.albumTrig) _refs.albumTrig.focus();
        }
    }

    // 专辑选项激活统一入口：鼠标 click 与键盘 Enter/Space 汇聚同一 intent
    function selectAlbumOption(opt) {
        currentAlbumFilter = opt.getAttribute('data-album') || '';
        setAlbumDropdownOpen(false);
        renderAlbumSelect();
        renderTrackList(currentAlbumFilter);
    }

    // 首屏 stagger：每次重建列表只给前 12 项加入场动画，避免长列表视觉噪音
    var ENTER_STAGGER_MAX = 12;

    function renderTrackList(albumFilter) {
        if (!_refs.trackList) return;
        _refs.trackList.innerHTML = '';
        var enterCount = 0;
        if (albumFilter) {
            enterCount = appendTrackItems(albums[albumFilter] || [], enterCount);
        } else {
            // “全部”视图：按专辑分组，分组头 sticky 吸附（顺序与专辑下拉一致）
            var names = [];
            for (var alb in albums) names.push(alb);
            names.sort();
            for (var i = 0; i < names.length; i++) {
                if (!albums[names[i]].length) continue;
                var header = document.createElement('div');
                header.className = 'jbp-album-group';
                header.textContent = names[i];
                _refs.trackList.appendChild(header);
                enterCount = appendTrackItems(albums[names[i]], enterCount);
            }
        }
        refreshTrackStates();
        // roving tabindex 入口：Tab 进列表落在当前曲目（无则首项），其余项 -1 不独立占用 Tab 序
        var entry = _refs.trackList.querySelector('.jbp-track-item.active') || _refs.trackList.querySelector('.jbp-track-item');
        if (entry) setTrackEntry(entry);
        // active 项滚动定位：布局落定后执行，仅不在可视区时滚动并居中
        setTimeout(scrollActiveIntoView, 0);
    }

    // roving tabindex：仅入口项 tabindex=0；方向键导航迁移焦点后同步迁移入口
    function setTrackEntry(item) {
        if (!_refs.trackList) return;
        var items = _refs.trackList.querySelectorAll('.jbp-track-item');
        for (var i = 0; i < items.length; i++) {
            items[i].setAttribute('tabindex', items[i] === item ? '0' : '-1');
        }
    }

    function appendTrackItems(source, enterCount) {
        for (var i = 0; i < source.length; i++) {
            var div = document.createElement('div');
            div.className = 'jbp-track-item';
            div.innerHTML = '<span class="marquee-inner">' + escHtml(source[i].title) + '</span>';
            div.setAttribute('data-title', source[i].title);
            div.setAttribute('role', 'button');
            div.setAttribute('tabindex', '-1');   // roving：renderTrackList 收尾时把入口项提为 0
            div._marqueeSpeed = 25;
            if (enterCount < ENTER_STAGGER_MAX) {
                div.classList.add('jbp-enter');
                div.style.animationDelay = (enterCount * 20) + 'ms';
                enterCount++;
            }
            div.addEventListener('click', onTrackClick);
            div.addEventListener('mouseenter', onTrackHover);
            _refs.trackList.appendChild(div);
        }
        return enterCount;
    }

    // 曲名 marquee：首次 hover 时测量溢出；溢出项挂 .can-scroll，hover 期间滚动读全
    function onTrackHover(e) {
        var item = e.currentTarget;
        if (item._marqueeChecked) return;
        item._marqueeChecked = true;
        var overflow = measureMarqueeOverflow(item);
        if (overflow > 2) {
            var dist = overflow + 8;   // 右侧留呼吸空间
            item.style.setProperty('--marquee-dist', '-' + dist + 'px');
            item.style.setProperty('--marquee-dur', Math.max(4, dist / (item._marqueeSpeed || 25)) + 's');
            item.classList.add('can-scroll');
        }
    }

    function onTrackClick(e) {
        var el = e.target;
        while (el && !el.getAttribute('data-title')) el = el.parentElement;
        var title = el ? el.getAttribute('data-title') : null;
        if (title) playTrack(title);
    }

    // 点曲统一入口：鼠标 click 与键盘 Enter/Space 汇聚同一 intent
    function playTrack(title) {
        if (title !== bgmTitle) setPendingTrack(title);
        Bridge.send({type: 'jukebox', cmd: 'play', title: title});
    }

    // 点曲 pending：点击立即反馈，UiData 'bgm' 回包确认后转 active；3s 无回包兜底清除
    function setPendingTrack(title) {
        _pendingTitle = title || '';
        clearTimeout(_pendingTimer);
        if (_pendingTitle) {
            _pendingTimer = setTimeout(function() {
                _pendingTitle = '';
                refreshTrackStates();
            }, 3000);
        }
        refreshTrackStates();
    }

    function refreshTrackStates() {
        if (!_refs.trackList) return;
        var items = _refs.trackList.children;
        for (var i = 0; i < items.length; i++) {
            var t = items[i].getAttribute('data-title');
            if (!t) continue;   // 专辑分组头无 data-title
            items[i].classList.toggle('active', t === bgmTitle);
            items[i].classList.toggle('pending', t === _pendingTitle && t !== bgmTitle);
        }
    }

    // active 项滚动定位：仅不在可视区时滚动（不打扰正在浏览其他位置的用户）
    function scrollActiveIntoView() {
        if (!_refs.trackList) return;
        var active = _refs.trackList.querySelector('.jbp-track-item.active');
        if (!active) return;
        var listR = _refs.trackList.getBoundingClientRect();
        var itemR = active.getBoundingClientRect();
        if (itemR.top < listR.top || itemR.bottom > listR.bottom) {
            _refs.trackList.scrollTop += itemR.top - listR.top - (listR.height - itemR.height) / 2;
        }
    }

    function onPauseClick() {
        isPaused = !isPaused;
        _refs.pauseBtn.classList.toggle('paused', isPaused);
        setIcon(_refs.pauseBtn, isPaused ? ICON_PLAY : ICON_PAUSE, isPaused ? 'play' : 'pause');
        updateLed();
        Bridge.send({type: 'jukebox', cmd: isPaused ? 'pause' : 'resume'});
    }

    function onStopClick() {
        isPaused = false;
        if (_refs.pauseBtn) {
            _refs.pauseBtn.classList.remove('paused');
            setIcon(_refs.pauseBtn, ICON_PAUSE, 'pause');
        }
        updateLed();
        Bridge.send({type: 'jukebox', cmd: 'stop'});
    }

    function syncPauseState(isPlayingNow) {
        if (isPlayingNow && isPaused) {
            isPaused = false;
            if (_refs.pauseBtn) {
                _refs.pauseBtn.classList.remove('paused');
                setIcon(_refs.pauseBtn, ICON_PAUSE, 'pause');
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
        // 键盘可达：role=slider + ARIA 值三元组；键盘调量由 onPanelKeydown → keyOnSlider 驱动
        var labelEl = row.querySelector('.jb-slider-label');
        s.track.setAttribute('role', 'slider');
        s.track.setAttribute('tabindex', '0');
        s.track.setAttribute('aria-label', (labelEl ? labelEl.textContent : key) + '音量');
        s.track.setAttribute('aria-valuemin', '0');
        s.track.setAttribute('aria-valuemax', '100');
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

    // 键盘调量统一入口：与鼠标拖拽同一命令通道（±5 步进，Home/End 到两端）
    function commitSliderValue(s, val) {
        s.value = Math.max(0, Math.min(100, val));
        updateSliderUI(s);
        Bridge.send({type: 'jukebox', cmd: s.cmd, value: s.value});
    }

    function updateSliderUI(s) {
        var pct = s.value + '%';
        if (s.fill) s.fill.style.width = pct;
        if (s.thumb) s.thumb.style.left = pct;
        if (s.valEl) s.valEl.textContent = s.value;
        if (s.track) s.track.setAttribute('aria-valuenow', String(s.value));
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
        activateSettingItem(item);
    }

    // 设置项激活统一入口：鼠标 click 与键盘 Enter/Space 汇聚同一 intent
    function activateSettingItem(item) {
        var key = item.getAttribute('data-key');
        if (!key) return;
        if (item.classList.contains('jb-radio')) {
            var val = item.getAttribute('data-value');
            settingsState[key] = val;
            syncRadioUI(key, val);
            if (key === 'playMode') {
                Bridge.send({type: 'jukebox', cmd: 'playMode', value: val});
            } else if (key === 'phosphor') {
                // 纯视觉偏好：本地应用 + localStorage 持久化，不经 Flash 桥
                applyTheme(val);
                persistTheme();
            }
            return;
        }
        settingsState[key] = !settingsState[key];
        item.classList.toggle('active', settingsState[key]);
        item.setAttribute('aria-checked', settingsState[key] ? 'true' : 'false');
        if (key === 'override') {
            Bridge.send({type: 'jukebox', cmd: 'override', value: settingsState.override});
        } else if (key === 'trueRandom') {
            Bridge.send({type: 'jukebox', cmd: 'trueRandom', value: settingsState.trueRandom});
        }
    }

    function syncSettingUI(key, active) {
        if (!_refs.settings) return;
        var items = _refs.settings.querySelectorAll('.jb-setting-item[data-key="' + key + '"]');
        for (var i = 0; i < items.length; i++) {
            items[i].classList.toggle('active', active);
            items[i].setAttribute('aria-checked', active ? 'true' : 'false');
        }
    }

    function syncRadioUI(key, val) {
        if (!_refs.settings) return;
        var radios = _refs.settings.querySelectorAll('.jb-radio[data-key="' + key + '"]');
        for (var i = 0; i < radios.length; i++) {
            var on = radios[i].getAttribute('data-value') === val;
            radios[i].classList.toggle('active', on);
            radios[i].setAttribute('aria-checked', on ? 'true' : 'false');
        }
    }

    function syncPlayModeUI(mode) {
        settingsState.playMode = mode;
        syncRadioUI('playMode', mode);
    }

    // ── 磷光主题：绿磷屏 / 琥珀磷屏（互斥单选）。CSS 侧内联覆盖 --jb-accent 变量，canvas 侧切换 palette ──
    function loadTheme() {
        try {
            return localStorage.getItem(THEME_STORAGE_KEY) === 'amber' ? 'amber' : 'green';
        } catch (e) { return 'green'; }
    }

    function persistTheme() {
        try {
            localStorage.setItem(THEME_STORAGE_KEY, settingsState.phosphor);
        } catch (e) {}
    }

    function applyTheme(name) {
        var p = PALETTES[name] || PALETTES.green;
        palette = p;
        settingsState.phosphor = (p === PALETTES.amber) ? 'amber' : 'green';
        if (_el) {
            _el.style.setProperty('--jb-accent', p.accent);
            _el.style.setProperty('--jb-accent-rgb', p.accentRgb);
            _el.style.setProperty('--jb-screen-bg', p.screenBg);
        }
        syncRadioUI('phosphor', settingsState.phosphor);
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

    // ── 帮助弹窗：焦点圈定 + 关闭返还 ──
    function isHelpOpen() {
        return !!(_refs.helpModal && _refs.helpModal.classList.contains('visible'));
    }

    function openHelpModal() {
        if (!_helpLoaded) {
            _refs.helpContent.textContent = '加载中...';
            Bridge.send({type: 'jukebox', cmd: 'loadHelp'});
        }
        _refs.helpModal.classList.add('visible');
        focusWhenReady(function() { return _refs.helpClose; }, isHelpOpen);
    }

    function closeHelpModal() {
        if (!isHelpOpen()) return;
        _refs.helpModal.classList.remove('visible');
        // 焦点返还：仅当焦点仍留在弹窗内时拉回帮助按钮，不抢用户已移走的焦点
        if (_refs.helpBtn && _refs.helpModal.contains(document.activeElement)) {
            _refs.helpBtn.focus();
        }
    }

    function onHelpClick() {
        if (isHelpOpen()) closeHelpModal();
        else openHelpModal();
    }

    function onHelpText(data) {
        _helpLoaded = true;
        if (typeof marked !== 'undefined' && marked.parse) {
            _refs.helpContent.innerHTML = marked.parse(data.text || '');
        } else {
            _refs.helpContent.textContent = data.text || '';
        }
    }

    // ── 键盘可达性：面板级单一 keydown 委派 ──
    // Enter/Space/方向键/Home/End 在此分发。Esc 刻意不在 web 侧监听：生产环境 Esc 由 C# 捕获后
    // 发 panel_esc 桥消息，统一走 closeLocally 分层，避免 DOM keydown 与桥消息双通道重复消费。
    function onPanelKeydown(e) {
        if (e.key === 'Tab') {
            if (isHelpOpen()) trapHelpFocus(e);
            return;
        }
        var t = e.target;
        if (!t || t === _el || typeof t.closest !== 'function') return;
        var handled = false;
        var el;
        if ((el = t.closest('.jbp-track-item'))) handled = keyOnTrackItem(e, el);
        else if ((el = t.closest('.jb-slider-track'))) handled = keyOnSlider(e, el);
        else if (t.closest('.jbp-progress')) handled = keyOnSeek(e);
        else if ((el = t.closest('.jb-setting-item'))) handled = keyOnSetting(e, el);
        else if ((el = t.closest('.jbp-album-option'))) handled = keyOnAlbumOption(e, el);
        else if ((el = t.closest('.jbp-album-trigger'))) handled = keyOnAlbumTrigger(e, el);
        else if ((el = t.closest('.jb-ctrl-btn'))) handled = keyOnCtrlBtn(e, el);
        if (handled) {
            e.preventDefault();
            e.stopPropagation();
        }
    }

    // 帮助弹窗焦点圈定：Tab/Shift+Tab 只在弹窗可聚焦元素内循环，永不逃逸到背后面板
    function trapHelpFocus(e) {
        var modal = _refs.helpModal;
        if (!modal) return;
        var focusables = modal.querySelectorAll('button, a[href], [tabindex]:not([tabindex="-1"])');
        e.preventDefault();
        if (!focusables.length) return;
        var idx = -1;
        for (var i = 0; i < focusables.length; i++) {
            if (focusables[i] === document.activeElement) { idx = i; break; }
        }
        if (e.shiftKey) idx = (idx <= 0) ? focusables.length - 1 : idx - 1;
        else idx = (idx < 0 || idx >= focusables.length - 1) ? 0 : idx + 1;
        focusables[idx].focus();
    }

    function keyOnTrackItem(e, item) {
        if (e.key === 'Enter' || e.key === ' ') {
            var title = item.getAttribute('data-title');
            if (title) playTrack(title);
            return true;
        }
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'Home' || e.key === 'End') {
            var items = _refs.trackList ? _refs.trackList.querySelectorAll('.jbp-track-item') : [];
            var idx = -1;
            for (var i = 0; i < items.length; i++) if (items[i] === item) { idx = i; break; }
            if (idx < 0) return false;
            if (e.key === 'ArrowDown') idx = Math.min(items.length - 1, idx + 1);
            else if (e.key === 'ArrowUp') idx = Math.max(0, idx - 1);
            else if (e.key === 'Home') idx = 0;
            else idx = items.length - 1;
            items[idx].focus();
            setTrackEntry(items[idx]);
            return true;
        }
        return false;
    }

    function keyOnSlider(e, track) {
        var row = track.closest('.jb-slider-row');
        var key = row ? row.getAttribute('data-slider') : null;
        var s = key ? sliders[key] : null;
        if (!s) return false;
        if (e.key === 'ArrowRight' || e.key === 'ArrowUp') { commitSliderValue(s, s.value + 5); return true; }
        if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') { commitSliderValue(s, s.value - 5); return true; }
        if (e.key === 'Home') { commitSliderValue(s, 0); return true; }
        if (e.key === 'End') { commitSliderValue(s, 100); return true; }
        return false;
    }

    function keyOnSeek(e) {
        if (currentDuration <= 0) return false;
        var target = -1;
        if (e.key === 'ArrowRight') target = Math.min(currentDuration, currentCursor + 5);
        else if (e.key === 'ArrowLeft') target = Math.max(0, currentCursor - 5);
        else if (e.key === 'Home') target = 0;
        else if (e.key === 'End') target = currentDuration;
        else return false;
        currentCursor = target;   // 先行推进保证连续按键以新位置累加；音频回包会校正
        Bridge.send({type: 'jukebox', cmd: 'seek', sec: target});
        return true;
    }

    function keyOnSetting(e, item) {
        if (e.key !== 'Enter' && e.key !== ' ') return false;
        activateSettingItem(item);
        return true;
    }

    function keyOnAlbumTrigger(e) {
        if (e.key === 'Enter' || e.key === ' ' || e.key === 'ArrowDown') {
            setAlbumDropdownOpen(true);
            return true;
        }
        if (e.key === 'ArrowUp' && _refs.albumWrap && _refs.albumWrap.classList.contains('open')) {
            setAlbumDropdownOpen(false);
            return true;
        }
        return false;
    }

    function keyOnAlbumOption(e, opt) {
        if (e.key === 'Enter' || e.key === ' ') {
            selectAlbumOption(opt);
            return true;
        }
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'Home' || e.key === 'End') {
            var opts = _refs.albumOpts ? _refs.albumOpts.querySelectorAll('.jbp-album-option') : [];
            var idx = -1;
            for (var i = 0; i < opts.length; i++) if (opts[i] === opt) { idx = i; break; }
            if (idx < 0) return false;
            if (e.key === 'ArrowDown') idx = Math.min(opts.length - 1, idx + 1);
            else if (e.key === 'ArrowUp') idx = Math.max(0, idx - 1);
            else if (e.key === 'Home') idx = 0;
            else idx = opts.length - 1;
            opts[idx].focus();
            return true;
        }
        return false;
    }

    function keyOnCtrlBtn(e, btn) {
        if (e.key !== 'Enter' && e.key !== ' ') return false;
        if (btn === _refs.pauseBtn) onPauseClick();
        else if (btn === _refs.stopBtn) onStopClick();
        else if (btn === _refs.helpBtn) onHelpClick();
        else return false;
        return true;
    }
})();
