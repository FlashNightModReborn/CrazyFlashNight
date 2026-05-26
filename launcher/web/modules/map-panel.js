var MapPanel = (function() {
    'use strict';

    // Stage 最大 scale · 单一真相源
    //   - map-panel.js syncStageLayout 的一级缩放上限
    //   - tools/tune-map-filter-fit.js STAGE_MAX_SCALE 必须同步 (离线 fit 算分才能对齐)
    //   - 调大需回查 composite PNG 源分辨率, 否则最终总放大 > 1.5x 会 pixelated
    var STAGE_MAX_SCALE = 1.3;

    var _el, _bodyEl, _stageEl, _stageShellEl, _railEl, _canvasEl, _ringCanvasEl, _fgCanvasEl, _canvasRenderer, _contentFitEl, _sceneVisualLayerEl, _avatarLayerEl, _hotspotLayer, _hitcaptureEl, _hotspotLabelLayer, _loadingEl, _errorEl, _errorTextEl;
    var _pageTabsEl, _pageSummaryEl;
    var _activePage = null;
    var _reqSeq = 0;
    var _pendingReq = {};
    var _enabledLookup = {};
    var _hotspotStateLookup = {};
    var _unlockFlags = {};
    var _pageFilterState = {};
    var _dynamicAvatarState = {};
    var _snapshotMarkers = [];
    var _snapshotTips = [];
    // v3 snapshot 新增字段缓存（v2 snapshot 时全部为空 = 不门控，等价默认可见）
    var _avatarVisibility = {};       // { avatarId: boolean }；缺 key = 默认可见
    var _snapshotTaskChains = {};     // 仅用于 dev/qa 调试，渲染路径不读
    var _snapshotInfrastructure = {}; // 同上
    // 任务红点聚合 lookup（applySnapshot 末尾、_enabledLookup 就绪后重建）
    // 剧透防护：只统计 enabled 的 hotspot，被门控锁住的区域永不点亮
    // - byHotspot[hotspotId] = true 时末端 dot 亮
    // - byFilter[pageId][filterId] = N 时该 filter 数字 badge 显 N
    // - byPage[pageId] = N 时该 page tab 数字 badge 显 N
    var _taskBadge = { byPage: {}, byFilter: {}, byHotspot: {} };
    var _snapshotVersion = 2;
    var _currentHotspotId = '';
    var _requestedInitialPageId = '';
    var _hoverHotspotId = '';
    var _busyLookup = {};
    var _stageSelectBusyHotspotId = '';
    var _stageSelectHotspotIndex = null;
    var _closing = false;
    var _session = 0;
    var _stageScale = 1;
    var _contentFitScale = 1;
    var _contentFitOffsetX = 0;
    var _contentFitOffsetY = 0;
    var _contentFitPadX = 0;
    var _contentFitPadY = 0;
    var _contentFitPresetId = '';
    var _contentFitPresetMeta = null;
    var _contentBounds = null;
    var _stageViewportWidth = 0;
    var _stageViewportHeight = 0;
    var _layoutRaf = 0;
    var _layoutSettleTimer = 0;
    var _layoutPendingReason = '';
    var _layoutObserver = null;
    var _resizingClassTimer = 0;
    var _windowResizeBound = false;
    var _visualViewportResizeBound = false;
    var _windowResizeHandler = null;
    var _visualViewportResizeHandler = null;
    var _debugTelemetryEnabled = false;
    var _snapshotAnnounced = false;     // 每次 onOpen 后首次 snapshot 成功播 ready, 避免刷新 spam
    var _canvasActive = false;          // 面板可见且应渲染时为 true; host 驱动关闭后置 false
    var _canvasSyncScheduled = false;   // 微任务合并: 同一同步批次多次 sync 只 setState 一次
    var _canvasRevision = 0;
    var _canvasRenderCache = {};

    function playCue(name) {
        var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
        if (!A) return;
        var fn = A['play' + name.charAt(0).toUpperCase() + name.slice(1)];
        if (typeof fn === 'function') fn();
    }

    Panels.register('map', {
        create: createDOM,
        onOpen: onOpen,
        // Esc / backdrop 来自 Panels 框架，不经过 DOM click，所以 overlay 的 click 代理不会触发
        // cancel cue — 这里显式补一次；DOM click 路径（close btn）由代理负责，避免双响。
        onRequestClose: function() { playCue('cancel'); requestClose(); },
        onClose: handleClose,
        onForceClose: onForceClose
    });

    function createDOM() {
        _el = document.createElement('div');
        _el.className = 'map-panel';
        _el.innerHTML =
            '<div class="map-panel-header">' +
                '<div class="map-page-tabs" id="map-page-tabs"></div>' +
                '<div class="map-page-summary" id="map-page-summary"></div>' +
                '<button class="map-panel-close-btn" type="button" title="关闭" data-audio-cue="cancel">X</button>' +
            '</div>' +
            '<div class="map-panel-body">' +
                '<div class="map-stage-shell" id="map-stage-shell">' +
                    '<div class="map-stage-frame" id="map-stage-frame">' +
                        // 三画布: bg=backdrop/异常层/场景/头像 (z=2);
                        // ring=任务环 (z=3, 低于 hotspot/标签 — 套住头像但不遮"前往选关"卡片);
                        // fg=反馈标记/提示/未开放提示 (z=6, 高于标签, 还原旧 feedback-layer 层序)
                        '<canvas class="map-stage-canvas map-stage-canvas--bg" id="map-stage-canvas" aria-hidden="true"></canvas>' +
                        '<canvas class="map-stage-canvas map-stage-canvas--ring" id="map-stage-canvas-ring" aria-hidden="true"></canvas>' +
                        '<div class="map-stage-content-fit" id="map-stage-content-fit">' +
                            // sceneVisual DOM 层 (Phase 1B) — 常态隐藏, current/hover/focus 显示;
                            // canvas drawScenes 非 hierarchy 整层短路, hierarchy 跳过 DOM 已显示的 visualId
                            '<div class="map-scene-visual-layer" id="map-scene-visual-layer" aria-hidden="true"></div>' +
                            // avatar DOM 层 (Phase 2) — 静态 + 动态头像 (替代 canvas drawAvatars)
                            '<div class="map-avatar-layer" id="map-avatar-layer" aria-hidden="true"></div>' +
                            '<div class="map-hotspot-layer" id="map-hotspot-layer"></div>' +
                            // hitcapture (z=4) 在 hotspot-layer (z=3) 与 label-layer (z=5) 之间
                            // 唯一接收鼠标的 hotspot 命中层; .map-hotspot button 改 pointer-events:none
                            '<div class="map-hotspot-hitcapture" id="map-hotspot-hitcapture"></div>' +
                            '<div class="map-hotspot-label-layer" id="map-hotspot-label-layer"></div>' +
                        '</div>' +
                        '<canvas class="map-stage-canvas map-stage-canvas--fg" id="map-stage-canvas-fg" aria-hidden="true"></canvas>' +
                        '<div class="map-stage-corner map-stage-corner--tl" aria-hidden="true"></div>' +
                        '<div class="map-stage-corner map-stage-corner--tr" aria-hidden="true"></div>' +
                        '<div class="map-stage-corner map-stage-corner--bl" aria-hidden="true"></div>' +
                        '<div class="map-stage-corner map-stage-corner--br" aria-hidden="true"></div>' +
                        '<div class="map-stage-loading" id="map-stage-loading">读取地图状态中...</div>' +
                        '<div class="map-stage-error" id="map-stage-error" style="display:none">' +
                            '<div class="map-stage-error-title">地图状态加载失败</div>' +
                            '<div class="map-stage-error-text" id="map-stage-error-text"></div>' +
                            '<div class="map-stage-error-actions">' +
                                '<button class="map-error-retry" type="button" data-audio-cue="select">重试</button>' +
                                '<button class="map-error-close" type="button" data-audio-cue="cancel">关闭</button>' +
                            '</div>' +
                        '</div>' +
                    '</div>' +
                '</div>' +
                '<div class="map-rail-shell" id="map-rail-shell"></div>' +
            '</div>';

        _bodyEl = _el.querySelector('.map-panel-body');
        _stageEl = _el.querySelector('#map-stage-frame');
        _canvasEl = _el.querySelector('#map-stage-canvas');
        _ringCanvasEl = _el.querySelector('#map-stage-canvas-ring');
        _fgCanvasEl = _el.querySelector('#map-stage-canvas-fg');
        _contentFitEl = _el.querySelector('#map-stage-content-fit');
        _sceneVisualLayerEl = _el.querySelector('#map-scene-visual-layer');
        _avatarLayerEl = _el.querySelector('#map-avatar-layer');
        _hotspotLayer = _el.querySelector('#map-hotspot-layer');
        _hitcaptureEl = _el.querySelector('#map-hotspot-hitcapture');
        _hotspotLabelLayer = _el.querySelector('#map-hotspot-label-layer');
        _stageShellEl = _el.querySelector('#map-stage-shell');
        _railEl = _el.querySelector('#map-rail-shell');
        _loadingEl = _el.querySelector('#map-stage-loading');
        _errorEl = _el.querySelector('#map-stage-error');
        _errorTextEl = _el.querySelector('#map-stage-error-text');
        _pageTabsEl = _el.querySelector('#map-page-tabs');
        _pageSummaryEl = _el.querySelector('#map-page-summary');
        _canvasRenderer = (typeof MapCanvasStageRenderer !== 'undefined')
            ? new MapCanvasStageRenderer(_canvasEl, { fgCanvas: _fgCanvasEl, ringCanvas: _ringCanvasEl, resolveAssetUrl: resolveAssetUrl })
            : null;

        if (typeof MapSceneVisualLayer !== 'undefined' && _sceneVisualLayerEl) {
            MapSceneVisualLayer.mount(_sceneVisualLayerEl, _stageEl, resolveAssetUrl);
        }

        if (typeof MapAvatarLayer !== 'undefined' && _avatarLayerEl) {
            MapAvatarLayer.mount(_avatarLayerEl);
        }

        if (typeof MapHotspotHitcapture !== 'undefined' && _hitcaptureEl) {
            MapHotspotHitcapture.mount(_hitcaptureEl, {
                getCurrentPageId: function() { return _activePage ? _activePage.id : ''; },
                getCurrentPage: function() { return _activePage; },
                getVisibleLookup: function() { return buildVisibleLookup(_activePage); },
                getEnabledLookup: function() { return _enabledLookup; },
                getBusyLookup: function() { return _busyLookup; },
                onHover: function(id, isHover) { setHotspotHover(id, isHover); },
                onClick: function(id) {
                    if (!_activePage) return;
                    var hotspot = findHotspotById(_activePage, id);
                    if (hotspot) requestNavigate(hotspot);
                }
            });
        }

        buildPageTabs();
        initLayoutWatcher();

        _el.querySelector('.map-panel-close-btn').addEventListener('click', function() { requestClose(); });
        _el.querySelector('.map-error-retry').addEventListener('click', function() { requestSnapshot('refresh'); });
        _el.querySelector('.map-error-close').addEventListener('click', function() { requestClose(); });

        _el.addEventListener('animationend', function(e) {
            if (e.target === _el && e.animationName === 'mapPanelBoot') {
                _el.classList.remove('is-entering');
                scheduleLayoutSync();
                scheduleSettledLayoutSync();
                return;
            }
            if (e.target === _stageEl && e.animationName === 'mapStageBoot') {
                scheduleLayoutSync();
                scheduleSettledLayoutSync();
            }
        });

        return _el;
    }

    function buildPageTabs() {
        var order = MapPanelData.getPageOrder();
        _pageTabsEl.innerHTML = '';

        for (var i = 0; i < order.length; i++) {
            var page = MapPanelData.getPage(order[i]);
            var btn = document.createElement('button');
            btn.className = 'map-page-tab';
            btn.type = 'button';
            btn.setAttribute('data-page-id', page.id);
            btn.setAttribute('data-audio-cue', 'select');
            // 任务红点 badge 静态挂在 tab 上，每次 applySnapshot/applyPage 由 syncPageTabBadges 刷文本/可见性
            btn.innerHTML = escHtml(page.tabLabel) +
                '<span class="map-page-tab-badge" aria-hidden="true" style="display:none"></span>';
            attachPageHandler(btn, page.id);
            _pageTabsEl.appendChild(btn);
        }
    }

    function attachPageHandler(btn, pageId) {
        btn.addEventListener('click', function() {
            applyPage(pageId);
        });
    }

    function onOpen(el, initData) {
        _closing = false;
        _session += 1;
        _pendingReq = {};
        _enabledLookup = {};
        _hotspotStateLookup = {};
        _unlockFlags = {};
        _pageFilterState = {};
        _dynamicAvatarState = {};
        _avatarVisibility = {};
        _snapshotTaskChains = {};
        _snapshotInfrastructure = {};
        _taskBadge = { byPage: {}, byFilter: {}, byHotspot: {} };
        _snapshotVersion = 2;
        _snapshotMarkers = [];
        _snapshotTips = [];
        _currentHotspotId = '';
        _hoverHotspotId = '';
        _busyLookup = {};
        _debugTelemetryEnabled = !!(initData && initData.dev);
        _snapshotAnnounced = false;
        _canvasActive = true;
        resetCanvasRenderCache();
        resetContentFit();
        if (_el) _el.classList.remove('is-compact');

        if (_el) {
            _el.classList.remove('is-entering');
            // 强制回流后加 class, 保证 CSS 动画重新播放
            void _el.offsetWidth;
            _el.classList.add('is-entering');
        }

        initLayoutWatcher();
        hideError();
        setLoading(true);
        var requestedPageId = (initData && (initData.page || initData.region)) || '';
        _requestedInitialPageId = requestedPageId;
        applyPage(requestedPageId || 'base');
        requestSnapshot('snapshot');
        scheduleSettledLayoutSync();
        playCue('modalOpen');
    }

    function onForceClose() {
        // teardownLayoutWatcher 已由 Panels.close() 经 onClose 钩子触发，此处只做状态复位。
        _closing = false;
        stopCanvasStage();
        _pendingReq = {};
        _enabledLookup = {};
        _hotspotStateLookup = {};
        _unlockFlags = {};
        _pageFilterState = {};
        _dynamicAvatarState = {};
        _avatarVisibility = {};
        _snapshotTaskChains = {};
        _snapshotInfrastructure = {};
        _taskBadge = { byPage: {}, byFilter: {}, byHotspot: {} };
        _snapshotVersion = 2;
        _snapshotMarkers = [];
        _snapshotTips = [];
        _currentHotspotId = '';
        _requestedInitialPageId = '';
        _hoverHotspotId = '';
        _busyLookup = {};
        _debugTelemetryEnabled = false;
        _stageScale = 1;
        resetCanvasRenderCache();
        resetContentFit();
        if (_el) _el.classList.remove('is-compact');
        hideError();
        setLoading(false);
    }

    function teardownLayoutWatcher() {
        if (_layoutObserver) {
            _layoutObserver.disconnect();
            _layoutObserver = null;
        }
        if (_windowResizeBound && typeof window !== 'undefined' && window.removeEventListener && _windowResizeHandler) {
            window.removeEventListener('resize', _windowResizeHandler);
        }
        _windowResizeBound = false;
        if (_visualViewportResizeBound && typeof window !== 'undefined' && window.visualViewport && window.visualViewport.removeEventListener && _visualViewportResizeHandler) {
            window.visualViewport.removeEventListener('resize', _visualViewportResizeHandler);
        }
        _visualViewportResizeBound = false;
        if (_layoutSettleTimer) {
            clearTimeout(_layoutSettleTimer);
            _layoutSettleTimer = 0;
        }
        if (_layoutRaf && typeof cancelAnimationFrame === 'function') {
            cancelAnimationFrame(_layoutRaf);
        }
        _layoutRaf = 0;
        if (_resizingClassTimer) {
            clearTimeout(_resizingClassTimer);
            _resizingClassTimer = 0;
        }
        if (_stageEl) _stageEl.classList.remove('is-resizing');
    }

    // 正常 onClose 钩子: 拆布局监听 + 停 canvas 渲染循环。
    function handleClose() {
        teardownLayoutWatcher();
        stopCanvasStage();
    }

    // 停 canvas 渲染。host 驱动关闭 (panel_cmd close / 切面板 / 选关交接) 也会经 onClose
    // 走到这里。隐藏画布 clientWidth 为 0, 但渲染器仍持上次 stage 尺寸快照, 不显式停
    // 就会在隐藏画布上一直转 RAF; stopped 标志同时挡延迟的图片 onload 回调重启循环。
    function stopCanvasStage() {
        _canvasActive = false;
        _canvasSyncScheduled = false;
        if (_canvasRenderer && _canvasRenderer.stop) _canvasRenderer.stop();
        // 释放所有 page 的 hitmap (每张 ~2.4MB ImageData), 下次 applyPage 重建.
        // hitcapture 自身的 listeners 留在 DOM 上, 由 Panels 框架保留 _el 复用; 状态归零靠
        // ensurePage 未就绪时 query 返回 null 兜底.
        if (typeof MapHittestEngine !== 'undefined' && typeof MapPanelData !== 'undefined') {
            var pageOrder = MapPanelData.getPageOrder ? MapPanelData.getPageOrder() : [];
            for (var i = 0; i < pageOrder.length; i += 1) {
                MapHittestEngine.discardPage(pageOrder[i]);
            }
        }
    }

    function applyPage(pageId) {
        _activePage = MapPanelData.getPage(pageId);
        _hoverHotspotId = '';
        ensurePageFilterState(_activePage);
        _stageEl.style.aspectRatio = _activePage.width + ' / ' + _activePage.height;
        // 像素级 hittest 构建 (lazy, fire-and-forget):
        // 必须传整页 sceneVisuals (engine 内部读 page.sceneVisuals), 与 filter 无关;
        // filter 过滤由 hitcapture 调用方在 query 后用 getVisibleLookup 套
        if (typeof MapHittestEngine !== 'undefined' && _activePage && _activePage.sceneVisuals && _activePage.sceneVisuals.length) {
            MapHittestEngine.ensurePage(_activePage, resolveAssetUrl);
        }
        // sceneVisual DOM 层重建 (整页全部 visuals, 与 filter 无关).
        // 必须在 renderStageBackdrop → syncCanvasStage 之前, 因为 buildCanvasRenderState
        // 会 syncState 拿 domVisibleVisualIds 喂 canvasSkipVisualIds
        if (typeof MapSceneVisualLayer !== 'undefined' && _activePage) {
            MapSceneVisualLayer.syncPage(_activePage);
        }
        // avatar DOM 层重建 (整页全部 slots, 与 filter 无关).
        // syncPage 内有 fingerprint 防重建闪烁; _dynamicAvatarState 变化时
        // dynamic slot 的 assetUrl 会变, fingerprint 不同, 触发重建.
        if (typeof MapAvatarLayer !== 'undefined' && _activePage) {
            MapAvatarLayer.syncPage(_activePage, buildAvatarLayerSlots(_activePage));
        }
        renderStageBackdrop();
        renderStageImage();
        renderSceneVisuals();
        renderAvatars();
        renderHotspots();
        renderFeedback();
        renderFilterButtons();
        updatePageTabs();
        updatePageSummary();
        scheduleLayoutSync();
        scheduleSettledLayoutSync();
    }

    function useAssembledVisuals(page) {
        return !!(page && page.renderMode === 'assembled' && page.sceneVisuals && page.sceneVisuals.length);
    }

    function renderStageBackdrop() {
        var activeViewMode = getActiveViewMode(_activePage);
        var activeFilter = _activePage ? getActiveFilter(_activePage) : null;
        var activeFilterId = activeFilter ? activeFilter.id : '';
        _stageEl.classList.toggle('is-assembled', useAssembledVisuals(_activePage));
        _stageEl.classList.toggle('is-layer-relation', activeViewMode === 'hierarchy');
        _stageEl.setAttribute('data-page-id', _activePage ? _activePage.id : '');
        _stageEl.setAttribute('data-active-filter', activeFilterId);
        syncCanvasStage();
    }

    function renderStageImage() {
        syncCanvasStage();
    }

    function updatePageTabs() {
        var btns = _pageTabsEl.querySelectorAll('.map-page-tab');
        for (var i = 0; i < btns.length; i++) {
            var btn = btns[i];
            var isActive = _activePage && btn.getAttribute('data-page-id') === _activePage.id;
            btn.classList.toggle('is-active', isActive);
        }
        syncPageTabBadges();
    }

    // 整页是否有任一 hotspot 解锁。base 永远 true（base hotspots 全部默认 enabled）。
    function pageHasAnyEnabled(pageId) {
        var page = MapPanelData.getPage(pageId);
        if (!page || !page.hotspots) return false;
        for (var i = 0; i < page.hotspots.length; i++) {
            if (_enabledLookup[page.hotspots[i].id]) return true;
        }
        return false;
    }

    // 整页全锁 → tab 隐藏（display:none）。在 _enabledLookup 重建后调用。
    function syncPageTabVisibility() {
        if (!_pageTabsEl) return;
        var btns = _pageTabsEl.querySelectorAll('.map-page-tab');
        for (var i = 0; i < btns.length; i++) {
            var pageId = btns[i].getAttribute('data-page-id');
            btns[i].style.display = pageHasAnyEnabled(pageId) ? '' : 'none';
        }
    }

    // 扫 _snapshotMarkers，按 hotspot/filter/page 三级聚合任务红点。
    // 剧透防护：只统计 _enabledLookup[hotspotId] === true 的 hotspot，
    // 被门控锁住的区域永不点亮红点（避免泄露"那里有任务等你"）。
    // 接受所有 marker.kind（保留兼容性），但实际只有 'taskNpc' 一种语义；
    // 'currentLocation' 类型也走 hotspotId 但不会点亮 badge — 我们只把"非当前位置"算作"有事要办"。
    function rebuildTaskBadgeLookup() {
        var byPage = {};
        var byFilter = {};
        var byHotspot = {};
        var i;
        var marker;
        var hotspotId;
        var pageId;
        var page;
        var filters;
        var filterId;
        var f;

        for (i = 0; i < _snapshotMarkers.length; i++) {
            marker = _snapshotMarkers[i];
            if (!marker) continue;
            // 仅"任务交付可达"算红点；其他 kind（含 currentLocation）忽略
            if (marker.kind !== 'taskNpc') continue;
            hotspotId = marker.hotspotId;
            if (!hotspotId || !_enabledLookup[hotspotId]) continue;     // 锁住 / 未登记的 hotspot 一律不计
            if (byHotspot[hotspotId]) continue;                          // 同 hotspot 多 NPC 折叠为 1

            byHotspot[hotspotId] = true;

            pageId = marker.pageId || (MapPanelData.findHotspotPageId ? MapPanelData.findHotspotPageId(hotspotId) : '');
            if (!pageId) continue;

            byPage[pageId] = (byPage[pageId] || 0) + 1;

            // hotspot → 它在该 page 哪些 filter 的 hotspotIds 里就给哪些 filter 计一次
            page = MapPanelData.getPage(pageId);
            filters = page && page.filters ? page.filters : [];
            for (f = 0; f < filters.length; f++) {
                filterId = filters[f].id;
                if (!filters[f].hotspotIds || filters[f].hotspotIds.indexOf(hotspotId) < 0) continue;
                if (!byFilter[pageId]) byFilter[pageId] = {};
                byFilter[pageId][filterId] = (byFilter[pageId][filterId] || 0) + 1;
            }
        }

        _taskBadge = { byPage: byPage, byFilter: byFilter, byHotspot: byHotspot };
    }

    // 数字 badge 渲染：1-9 显数字，>=10 显 "9+"（避免撑爆按钮）
    function formatBadgeCount(n) {
        if (!n || n <= 0) return '';
        if (n >= 10) return '9+';
        return String(n);
    }

    // 同步顶部 page tab 的红点文本与 has-quest class。
    // 由 buildPageTabs 创建静态 span，applySnapshot/applyPage 刷新内容。
    function syncPageTabBadges() {
        if (!_pageTabsEl) return;
        var btns = _pageTabsEl.querySelectorAll('.map-page-tab');
        for (var i = 0; i < btns.length; i++) {
            var pageId = btns[i].getAttribute('data-page-id');
            var n = (_taskBadge.byPage[pageId]) || 0;
            var txt = formatBadgeCount(n);
            var badge = btns[i].querySelector('.map-page-tab-badge');
            btns[i].classList.toggle('has-quest', n > 0);
            if (badge) {
                badge.textContent = txt;
                badge.style.display = txt ? '' : 'none';
            }
        }
    }

    // 返回首个 live page id；找不到则 fallback 到 page order 的第一个（base 兜底）
    function resolveFirstLivePageId() {
        var order = MapPanelData.getPageOrder();
        for (var i = 0; i < order.length; i++) {
            if (pageHasAnyEnabled(order[i])) return order[i];
        }
        return order[0] || '';
    }

    function updatePageSummary() {
        if (!_activePage) {
            _pageSummaryEl.textContent = '';
            return;
        }

        var hotspots = getVisibleHotspots(_activePage);
        var enabledCount = 0;
        for (var i = 0; i < hotspots.length; i++) {
            if (_enabledLookup[hotspots[i].id]) enabledCount++;
        }

        var activeFilter = getActiveFilter(_activePage);
        var prefix = activeFilter ? (activeFilter.label + ' · ') : '';
        _pageSummaryEl.textContent = hotspots.length
            ? (prefix + '可用 ' + enabledCount + ' / ' + hotspots.length)
            : (prefix + '无场景');
    }

    function renderSceneVisuals() {
        syncCanvasStage();
    }

    function getVisibleSceneVisuals(page) {
        if (!page) return [];
        var activeFilter = getActiveFilter(page);
        return MapPanelData.getVisibleSceneVisuals(page.id, activeFilter ? activeFilter.id : '');
    }

    function syncSceneNodeStates() {
        syncCanvasStage();
    }

    function requestSnapshot(cmd) {
        hideError();
        setLoading(true);

        var reqId = 'map-' + (++_reqSeq);
        var currentSession = _session;
        _pendingReq[reqId] = function(resp) {
            delete _pendingReq[reqId];
            if (currentSession !== _session || !Panels.isOpen() || Panels.getActive() !== 'map') return;

            if (!resp.success) {
                showError(resp.error || 'unknown_error');
                return;
            }

            setLoading(false);
            applySnapshot(resp.snapshot || {});
            if (!_snapshotAnnounced) {
                _snapshotAnnounced = true;
                playCue('ready');
            }
        };

        Bridge.send({
            type: 'panel',
            panel: 'map',
            cmd: cmd,
            callId: reqId
        });
    }

    function requestNavigate(hotspot) {
        if (!_activePage || _closing) return;

        if (!_enabledLookup[hotspot.id]) {
            // hotspot 按钮本身带 data-audio-cue='error'，overlay click 代理已播一次 cue，此处只补 toast
            pushLockedReason(hotspot.id);
            return;
        }

        if (_busyLookup[hotspot.id]) return;

        // hotspot 按钮本身带 data-audio-cue='transition'，overlay click 代理已播一次 cue
        var reqId = 'map-nav-' + (++_reqSeq);
        var currentSession = _session;
        _pendingReq[reqId] = function(resp) {
            delete _pendingReq[reqId];
            if (currentSession !== _session) return;

            if (!resp.success) {
                if (typeof Toast !== 'undefined') {
                    Toast.add('地图跳转失败: ' + (resp.error || 'unknown_error'));
                }
                setHotspotBusy(hotspot.id, false);
                return;
            }

            if (resp.closePanel) {
                finishClose(true);
                return;
            }

            setHotspotBusy(hotspot.id, false);
        };

        setHotspotBusy(hotspot.id, true);
        Bridge.send({
            type: 'panel',
            panel: 'map',
            cmd: 'navigate',
            callId: reqId,
            targetId: hotspot.id,
            targetType: 'scene'
        });
    }

    function requestOpenStageSelect(hotspot, event) {
        if (event) {
            event.preventDefault();
            event.stopPropagation();
        }
        if (!_activePage || _closing || !hotspot) return;

        var entry = resolveStageSelectEntryForHotspot(hotspot);
        if (!entry) {
            if (typeof Toast !== 'undefined' && Toast) Toast.add('该区域没有对应的选关入口。');
            return;
        }
        if (!_enabledLookup[hotspot.id]) {
            pushLockedReason(hotspot.id);
            return;
        }
        if (_stageSelectBusyHotspotId) return;

        if (typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') {
            if (typeof Toast !== 'undefined' && Toast) Toast.add('选关面板暂不可用。');
            return;
        }

        var reqId = 'map-stage-select-' + (++_reqSeq);
        var currentSession = _session;
        var returnFrameLabel = resolveStageSelectReturnFrameLabel();
        var timeoutHandle = setTimeout(function() {
            if (!_pendingReq[reqId]) return;
            delete _pendingReq[reqId];
            if (currentSession !== _session) return;
            if (_stageSelectBusyHotspotId === hotspot.id) {
                _stageSelectBusyHotspotId = '';
                syncHotspotStates();
            }
            if (typeof Toast !== 'undefined' && Toast) {
                Toast.add('打开选关超时, 请重试。');
            }
        }, 5000);
        _pendingReq[reqId] = function(resp) {
            clearTimeout(timeoutHandle);
            delete _pendingReq[reqId];
            if (currentSession !== _session) return;

            _stageSelectBusyHotspotId = '';
            syncHotspotStates();
            if (!resp.success) {
                if (typeof Toast !== 'undefined' && Toast) {
                    Toast.add('打开选关失败: ' + (resp.error || 'unknown_error'));
                }
            }
        };

        _stageSelectBusyHotspotId = hotspot.id;
        syncHotspotStates();
        Bridge.send({
            type: 'panel',
            panel: 'map',
            cmd: 'open_stage_select',
            callId: reqId,
            targetId: hotspot.id,
            targetSceneName: getHotspotSceneName(hotspot),
            frameLabel: entry.frameLabel,
            returnFrameLabel: returnFrameLabel,
            source: 'map_panel'
        });
    }

    function requestClose() {
        finishClose(true);
    }

    function finishClose(notifyHost) {
        if (_closing) return;
        _closing = true;
        _pendingReq = {};
        _enabledLookup = {};
        _hotspotStateLookup = {};
        _unlockFlags = {};
        _pageFilterState = {};
        _dynamicAvatarState = {};
        _avatarVisibility = {};
        _snapshotTaskChains = {};
        _snapshotInfrastructure = {};
        _taskBadge = { byPage: {}, byFilter: {}, byHotspot: {} };
        _snapshotVersion = 2;
        _snapshotMarkers = [];
        _snapshotTips = [];
        _currentHotspotId = '';
        _hoverHotspotId = '';
        _busyLookup = {};
        _stageSelectBusyHotspotId = '';
        resetCanvasRenderCache();
        // cancel cue 由调用方负责: DOM click 走 overlay click 代理, Esc/backdrop 走 onRequestClose
        // navigate 成功直闭(resp.closePanel)不播 cancel, transition cue 已足够表达
        resetContentFit();
        Panels.close();
        if (notifyHost) {
            Bridge.send({ type: 'panel', panel: 'map', cmd: 'close' });
        }
        _closing = false;
    }

    function applySnapshot(snapshot) {
        var enabledIds = snapshot.enabledHotspotIds || [];
        _unlockFlags = MapPanelData.normalizeUnlockFlags(snapshot.unlocks || {});
        _hotspotStateLookup = MapPanelData.buildHotspotStates(_unlockFlags);
        _enabledLookup = {};
        _dynamicAvatarState = snapshot.dynamicAvatarState || {};
        _snapshotMarkers = snapshot.markers || [];
        _snapshotTips = snapshot.tips || [];
        _currentHotspotId = snapshot.currentHotspotId || resolveCurrentHotspotId(_snapshotMarkers) || '';
        // v3 字段：v2 snapshot 没有这些 key，缺 = 默认可见（保留向后兼容）
        _snapshotVersion = Number(snapshot.version) || 2;
        _avatarVisibility = (_snapshotVersion >= 3 && snapshot.avatarVisibility) ? snapshot.avatarVisibility : {};
        _snapshotTaskChains = (_snapshotVersion >= 3 && snapshot.taskChains) ? snapshot.taskChains : {};
        _snapshotInfrastructure = (_snapshotVersion >= 3 && snapshot.infrastructure) ? snapshot.infrastructure : {};

        if (snapshot.hotspotStates) {
            mergeHotspotStates(snapshot.hotspotStates);
        }

        for (var i = 0; i < enabledIds.length; i++) {
            _enabledLookup[enabledIds[i]] = true;
        }

        if (snapshot.hotspotStates) {
            rebuildEnabledLookupFromStates();
        } else if (!enabledIds.length) {
            rebuildEnabledLookupFromStates(true);
        }

        // _enabledLookup 已就绪 → 同步 tab 可见性（整页全锁则 display:none）
        syncPageTabVisibility();
        // _enabledLookup 已就绪 → 重建任务红点 lookup（locked hotspot 自然被过滤掉，剧透防护）
        rebuildTaskBadgeLookup();
        syncPageTabBadges();

        var requestedPageId = _requestedInitialPageId;
        _requestedInitialPageId = '';
        var targetPageId = requestedPageId || snapshot.defaultPageId || resolvePageIdForHotspot(_currentHotspotId) || (_activePage ? _activePage.id : '');
        // 目标页若全锁 → 回落到首个 live page（避免打开后看到空页）
        if (targetPageId && !pageHasAnyEnabled(targetPageId)) {
            targetPageId = resolveFirstLivePageId();
        }
        if (targetPageId) {
            applyPage(targetPageId);
            return;
        }

        renderAvatars();
        renderHotspots();
        renderFeedback();
        renderFilterButtons();
        updatePageSummary();
        scheduleLayoutSync();
        scheduleSettledLayoutSync();
    }

    function renderHotspots() {
        if (!_activePage) return;

        var hotspots = getVisibleHotspots(_activePage);
        _hotspotLayer.innerHTML = '';

        for (var i = 0; i < hotspots.length; i++) {
            var hotspot = hotspots[i];
            var rect = hotspot.rect;
            var hotspotState = getHotspotState(hotspot.id);
            var enabled = !!hotspotState.enabled;
            // 锁定 hotspot 整体不渲染（剧透防护）。彻底不可见 + 不可点；
            // 解锁原因通过 group 级 filter 按钮自身在解锁前的隐藏来表达。
            if (!enabled) continue;
            var btn = document.createElement('button');

            btn.className = 'map-hotspot' + (_currentHotspotId === hotspot.id ? ' is-current' : '');
            btn.type = 'button';
            btn.setAttribute('data-hotspot-id', hotspot.id);
            btn.setAttribute('data-audio-cue', 'transition');
            btn.style.left = toPercent(rect.x, _activePage.width);
            btn.style.top = toPercent(rect.y, _activePage.height);
            btn.style.width = toPercent(rect.w, _activePage.width);
            btn.style.height = toPercent(rect.h, _activePage.height);
            btn.setAttribute('aria-disabled', 'false');
            btn.setAttribute('aria-label', hotspot.label);
            // Phase 2: .map-hotspot-sheen span 删除; 视觉装饰已迁 .map-scene-visual / .map-avatar.

            attachHotspotHandler(btn, hotspot);
            _hotspotLayer.appendChild(btn);
        }

        renderHotspotLabels();
        syncHotspotStates();
    }

    function attachHotspotHandler(btn, hotspot) {
        // 鼠标命中已迁移到 .map-hotspot-hitcapture (像素级 alpha 命中);
        // 按钮本身 pointer-events:none. 这里只保留键盘 a11y 路径:
        // - click: 键盘 focus + Enter 时浏览器仍派发 click 事件 (不依赖 pointer-events)
        // - focus/blur: Tab 键盘焦点 → 等价于 hover, 让 label 卡片浮起
        btn.addEventListener('click', function() {
            requestNavigate(hotspot);
        });
        btn.addEventListener('focus', function() {
            setHotspotHover(hotspot.id, true);
        });
        btn.addEventListener('blur', function() {
            setHotspotHover(hotspot.id, false);
        });
    }

    function renderFilterButtons() {
        if (!_activePage || !_railEl) return;

        var filters = getPageFilters(_activePage);
        var activeFilter = getActiveFilter(_activePage);
        _railEl.innerHTML = '';

        // rail 按 filter 原 buttonRect.y 升序排列 (数据契约里保存的垂直视觉顺序)
        var ordered = filters.slice().sort(function(a, b) {
            var ay = a.buttonRect ? a.buttonRect.y : 9999;
            var by = b.buttonRect ? b.buttonRect.y : 9999;
            return ay - by;
        });

        for (var i = 0; i < ordered.length; i++) {
            var filter = ordered[i];
            var enabledCount = countEnabledIds(filter.hotspotIds || []);
            var filterMeta = getFilterMeta(_activePage.id, filter.id);
            var isLocked = !!(filterMeta && !_unlockFlags[filterMeta.unlockGroup]);
            // 锁定的 group-mapped filter 整个按钮不渲染（剧透防护）；
            // meta filter（all/hierarchy）和无 group 关联的 filter 保留。
            if (isLocked) continue;
            var btn = document.createElement('button');
            btn.className = 'map-filter-hotspot';
            btn.type = 'button';
            btn.setAttribute('data-filter-id', filter.id);
            btn.setAttribute('data-audio-cue', isLocked ? 'error' : 'select');
            btn.setAttribute('aria-label', buildFilterTitle(filter, enabledCount, filterMeta, isLocked));
            btn.classList.toggle('is-active', !!activeFilter && activeFilter.id === filter.id);
            btn.classList.toggle('is-empty', enabledCount === 0);
            btn.classList.toggle('is-locked', isLocked);
            // 任务红点 badge：只在该 filter 有"已解锁且有可交付任务"hotspot 时显示
            var questCount = (_taskBadge.byFilter[_activePage.id] && _taskBadge.byFilter[_activePage.id][filter.id]) || 0;
            var questBadgeHtml = questCount > 0
                ? '<span class="map-filter-hotspot-badge" aria-hidden="true">' + formatBadgeCount(questCount) + '</span>'
                : '';
            btn.classList.toggle('has-quest', questCount > 0);
            btn.innerHTML =
                '<span class="map-filter-hotspot-chrome"></span>' +
                '<span class="map-filter-hotspot-label">' + escHtml(filter.label) + '</span>' +
                questBadgeHtml +
                '<span class="map-filter-hotspot-meta">' + enabledCount + '/' + ((filter.hotspotIds || []).length) + '</span>';
            attachFilterHandler(btn, filter.id);
            _railEl.appendChild(btn);

            // 手风琴: 仅展开当前 active + 非 meta(all/hierarchy) + 非 locked 的 filter 子场景列表
            if (activeFilter && activeFilter.id === filter.id && !isMetaFilterId(filter.id) && !isLocked) {
                var subList = buildSceneSubList(filter);
                if (subList) _railEl.appendChild(subList);
            }
        }
    }

    function isMetaFilterId(filterId) {
        return filterId === 'all' || filterId === 'hierarchy';
    }

    function findHotspotById(page, hotspotId) {
        if (!page || !page.hotspots) return null;
        for (var i = 0; i < page.hotspots.length; i++) {
            if (page.hotspots[i].id === hotspotId) return page.hotspots[i];
        }
        return null;
    }

    function findHotspotByIdAnyPage(hotspotId) {
        var pageId = hotspotId && MapPanelData.findHotspotPageId ? MapPanelData.findHotspotPageId(hotspotId) : '';
        return pageId ? MapPanelData.findHotspot(pageId, hotspotId) : null;
    }

    function getHotspotSceneName(hotspot) {
        if (!hotspot) return '';
        if (hotspot.target && hotspot.target.sceneName) return hotspot.target.sceneName;
        return hotspot.sceneName || '';
    }

    function getStageSelectHotspotIndex() {
        if (_stageSelectHotspotIndex) return _stageSelectHotspotIndex;
        var index = {};
        if (typeof StageSelectData === 'undefined' || !StageSelectData || typeof StageSelectData.getManifest !== 'function') {
            return index;
        }

        var manifest = StageSelectData.getManifest();
        (manifest.frames || []).forEach(function(frame) {
            if (frame.frameLabel) {
                index[frame.frameLabel] = {
                    frameLabel: frame.frameLabel,
                    source: 'frame'
                };
            }
            (frame.stageButtons || []).forEach(function(button) {
                if (button.entryKind !== 'map' || !button.rootFadeTransitionFrame) return;
                index[button.rootFadeTransitionFrame] = {
                    frameLabel: frame.frameLabel,
                    source: 'diplomacy',
                    stageName: button.stageName || '',
                    rootFadeTransitionFrame: button.rootFadeTransitionFrame
                };
            });
        });

        _stageSelectHotspotIndex = index;
        return index;
    }

    function resolveStageSelectEntryForHotspot(hotspot) {
        var sceneName = getHotspotSceneName(hotspot);
        if (!sceneName) return null;
        return getStageSelectHotspotIndex()[sceneName] || null;
    }

    function resolveStageSelectReturnFrameLabel() {
        var currentHotspot = findHotspotByIdAnyPage(_currentHotspotId);
        var sceneName = getHotspotSceneName(currentHotspot);
        return sceneName || '基地门口';
    }

    function buildSceneSubList(filter) {
        var ids = filter.hotspotIds || [];
        if (!ids.length) return null;
        var list = document.createElement('div');
        list.className = 'map-rail-scene-list';
        list.setAttribute('data-filter-id', filter.id);
        for (var i = 0; i < ids.length; i++) {
            var hotspotId = ids[i];
            var hotspot = findHotspotById(_activePage, hotspotId);
            if (!hotspot) continue;
            var state = getHotspotState(hotspotId);
            var enabled = !!_enabledLookup[hotspotId];
            var isCurrent = _currentHotspotId === hotspotId;
            var stageSelectEntry = resolveStageSelectEntryForHotspot(hotspot);
            var hasQuest = !!_taskBadge.byHotspot[hotspotId];
            var row = document.createElement('div');
            row.className = 'map-rail-scene-row';
            row.setAttribute('data-hotspot-id', hotspotId);
            var item = document.createElement('button');
            item.className = 'map-rail-scene-item';
            item.type = 'button';
            item.setAttribute('data-hotspot-id', hotspotId);
            item.setAttribute('data-audio-cue', enabled ? 'transition' : 'error');
            item.classList.toggle('is-current', isCurrent);
            item.classList.toggle('is-disabled', !enabled);
            if (!enabled && state.lockedReason) {
                item.setAttribute('data-locked-reason', state.lockedReason);
            }
            item.setAttribute('aria-disabled', enabled ? 'false' : 'true');
            item.setAttribute('aria-label', hotspot.label);
            // 末端任务红点：只在已解锁 + 有可交付任务时显示（剧透防护已在 rebuildTaskBadgeLookup 内做掉）
            item.classList.toggle('has-quest', hasQuest);
            var questDotHtml = hasQuest
                ? '<span class="map-rail-scene-quest" aria-hidden="true"></span>'
                : '';
            item.innerHTML =
                '<span class="map-rail-scene-dot" aria-hidden="true"></span>' +
                '<span class="map-rail-scene-label">' + escHtml(hotspot.label) + '</span>' +
                questDotHtml;
            attachSceneItemHandler(item, hotspot);
            row.appendChild(item);
            if (stageSelectEntry && enabled) {
                var stageBtn = document.createElement('button');
                stageBtn.className = 'map-rail-stage-select-btn' + (hasQuest ? ' is-task' : '');
                stageBtn.type = 'button';
                stageBtn.textContent = hasQuest ? '选关' : '选关';
                stageBtn.setAttribute('data-hotspot-id', hotspotId);
                stageBtn.setAttribute('data-stage-select-frame', stageSelectEntry.frameLabel);
                stageBtn.setAttribute('data-audio-cue', 'select');
                stageBtn.setAttribute('aria-label', (hasQuest ? '打开任务指向的' : '打开') + stageSelectEntry.frameLabel + '选关');
                attachStageSelectActionHandler(stageBtn, hotspot);
                row.appendChild(stageBtn);
            }
            list.appendChild(row);
        }
        return list;
    }

    function attachSceneItemHandler(item, hotspot) {
        item.addEventListener('click', function() {
            // 复用 requestNavigate: enabled 走 transition + 导航; disabled 推 toast 原因; busy 去重
            requestNavigate(hotspot);
        });
    }

    function attachStageSelectActionHandler(item, hotspot) {
        item.addEventListener('click', function(event) {
            // 卡片浮在 hotspot 上方; 显式停止传播, 防止 overlay click 代理误把动作识别成导航
            if (event && typeof event.stopPropagation === 'function') event.stopPropagation();
            requestOpenStageSelect(hotspot, event);
        });
    }

    function attachFilterHandler(btn, filterId) {
        btn.addEventListener('click', function() {
            if (!_activePage) return;
            var filterMeta = getFilterMeta(_activePage.id, filterId);
            var isLocked = !!(filterMeta && !_unlockFlags[filterMeta.unlockGroup]);
            if (isLocked) {
                // 锁定 filter 只显示原因, 不切换状态; cue 已由 overlay click 代理按 data-audio-cue='error' 播过
                if (filterMeta && filterMeta.lockedReason && typeof Toast !== 'undefined' && Toast && typeof Toast.add === 'function') {
                    Toast.add(filterMeta.lockedReason);
                }
                return;
            }
            setActiveFilter(filterId);
        });
    }

    function renderAvatars() {
        syncCanvasStage();
    }

    function resolveStaticAvatarRect(slot) {
        if (!slot || !slot.assetUrl) return null;
        if (typeof MapAvatarSourceData === 'undefined' || !MapAvatarSourceData || !MapAvatarSourceData.getByAssetUrl) return null;
        var sourceSlot = MapAvatarSourceData.getByAssetUrl(slot.assetUrl);
        if (!sourceSlot || !sourceSlot.size) return null;
        var hotspotId = sourceSlot.hotspotId || slot.hotspotId;
        if (!hotspotId) return null;
        var hotspot = MapPanelData.findHotspot(_activePage.id, hotspotId);
        if (!hotspot || !hotspot.rect) return null;
        return {
            x: hotspot.rect.x + sourceSlot.relX,
            y: hotspot.rect.y + sourceSlot.relY,
            w: sourceSlot.size.w,
            h: sourceSlot.size.h
        };
    }

    function renderFeedback() {
        syncCanvasStage();
    }

    function renderHotspotLabels() {
        if (!_activePage || !_hotspotLabelLayer) return;

        var hotspots = getVisibleHotspots(_activePage);
        _hotspotLabelLayer.innerHTML = '';
        for (var i = 0; i < hotspots.length; i++) {
            var hotspot = hotspots[i];
            var hotspotState = getHotspotState(hotspot.id);
            // 锁定 hotspot 不渲染标签（剧透防护：与 renderHotspots 口径一致，
            // 锁定区域彻底无 DOM，不靠 content-fit 裁剪来隐藏 — 否则未自适应缩放时
            // 锁定地点名会以 is-muted 0.28 透明度泄露出来）
            if (!hotspotState.enabled) continue;
            var rect = hotspot.rect;
            var stageSelectEntry = resolveStageSelectEntryForHotspot(hotspot);
            var hasQuest = !!_taskBadge.byHotspot[hotspot.id];
            var label = document.createElement('div');
            label.className = 'map-hotspot-overlay-label';
            label.setAttribute('data-hotspot-id', hotspot.id);
            label.style.left = toPercent(rect.x + 8, _activePage.width);
            label.style.top = toPercent((rect.y + rect.h) - 8, _activePage.height);
            // 卡片头: 地点名; hover/current 时整张卡片浮出, 操作行附在下方
            label.innerHTML =
                '<span class="map-hotspot-overlay-label-head">' +
                    '<span class="map-hotspot-overlay-label-text">' + escHtml(hotspot.label || hotspot.id) + '</span>' +
                '</span>';
            // 可选关: 加大尺寸的 "前往选关" 按钮独占一行, 避免与 hotspot 整块点击区争抢命中
            if (stageSelectEntry) {
                var actions = document.createElement('div');
                actions.className = 'map-hotspot-overlay-actions';
                var action = document.createElement('button');
                action.className = 'map-hotspot-stage-select-btn' + (hasQuest ? ' is-task' : '');
                action.type = 'button';
                action.textContent = hasQuest ? '选关' : '前往选关';
                action.setAttribute('data-hotspot-id', hotspot.id);
                action.setAttribute('data-stage-select-frame', stageSelectEntry.frameLabel);
                action.setAttribute('data-audio-cue', 'select');
                action.setAttribute('aria-label', (hasQuest ? '打开任务指向的' : '打开') + stageSelectEntry.frameLabel + '选关');
                attachStageSelectActionHandler(action, hotspot);
                actions.appendChild(action);
                label.appendChild(actions);
            }
            attachHotspotLabelHoverBridge(label, hotspot);
            _hotspotLabelLayer.appendChild(label);
        }

        syncHotspotLabelStates();
    }

    // 鼠标从 hotspot 移到浮层卡片时, hotspot 的 mouseleave 会先清掉 _hoverHotspotId,
    // 这里用 label 自身的 mouseenter 立即接管, 保证卡片不会瞬时坍缩。
    function attachHotspotLabelHoverBridge(label, hotspot) {
        label.addEventListener('mouseenter', function() {
            setHotspotHover(hotspot.id, true);
        });
        label.addEventListener('mouseleave', function() {
            setHotspotHover(hotspot.id, false);
        });
    }

    function shouldRenderFeedbackItem(item) {
        if (!item) return false;

        var pageId = item.pageId || resolvePageIdForHotspot(item.hotspotId);
        if (pageId && _activePage.id !== pageId) return false;

        var visibleLookup = buildVisibleLookup(_activePage);
        if (item.hotspotId && !visibleLookup[item.hotspotId]) return false;
        // 锁定 hotspot 不显示 feedback tip
        if (item.hotspotId && !_enabledLookup[item.hotspotId]) return false;

        return true;
    }

    function shouldRenderFlashHint(hint) {
        if (!hint) return false;
        if (hint.pageId && _activePage.id !== hint.pageId) return false;
        if (!hint.conditionId) return true;
        return MapPanelData.evaluateCondition(_unlockFlags, hint.conditionId) === !!hint.whenValue;
    }

    function resolveFeedbackAnchor(item) {
        if (!item) return null;

        if (item.point && item.point.x !== undefined && item.point.y !== undefined) {
            return item.point;
        }

        if (item.hotspotId) {
            var hotspot = MapPanelData.findHotspot(_activePage.id, item.hotspotId);
            if (hotspot && hotspot.rect) {
                return {
                    x: hotspot.rect.x + (hotspot.rect.w / 2),
                    y: hotspot.rect.y + (hotspot.rect.h / 2)
                };
            }
        }

        return null;
    }

    function normalizeNpcMarkerKey(value) {
        return String(value || '')
            .replace(/^task_npc_/, '')
            .replace(/\s+/g, '')
            .replace(/[·•]/g, '')
            .toLowerCase();
    }

    function getMarkerNpcKey(marker) {
        if (!marker) return '';
        if (marker.npcName) return normalizeNpcMarkerKey(marker.npcName);
        if (marker.id) return normalizeNpcMarkerKey(marker.id);
        if (marker.label) return normalizeNpcMarkerKey(marker.label);
        return '';
    }

    function getSlotNpcKeys(slot) {
        var keys = [];
        if (!slot) return keys;

        if (slot.label) keys.push(normalizeNpcMarkerKey(slot.label));
        if (slot.id) keys.push(normalizeNpcMarkerKey(slot.id));
        if (slot.assetUrl) keys.push(normalizeNpcMarkerKey(slot.assetUrl));
        if (slot.label === '杀马特') keys.push(normalizeNpcMarkerKey('∞天ㄙ★使的剪∞'));

        return keys;
    }

    function findAvatarAnchorForMarker(marker, visibleLookup) {
        var npcKey = getMarkerNpcKey(marker);
        if (!npcKey || !_activePage) return null;

        var staticAnchor = findAnchorInSlots(npcKey, _activePage.staticAvatars, visibleLookup, resolveStaticAvatarRect);
        if (staticAnchor) return staticAnchor;

        return findAnchorInSlots(npcKey, _activePage.dynamicAvatars, visibleLookup, resolveDynamicAvatarRect);
    }

    function findAnchorInSlots(npcKey, slots, visibleLookup, rectResolver) {
        if (!slots || !slots.length) return null;

        for (var i = 0; i < slots.length; i++) {
            var slot = slots[i];
            if (slot.hotspotId && visibleLookup && !visibleLookup[slot.hotspotId]) continue;
            // 锁定 hotspot 不提供锚点
            if (slot.hotspotId && !_enabledLookup[slot.hotspotId]) continue;
            // 与 renderStaticAvatars 保持口径一致：avatar 不可见时也不给 task marker 提供锚点（避免泄剧透）
            if (slot.id && _avatarVisibility.hasOwnProperty(slot.id) && _avatarVisibility[slot.id] === false) continue;

            var keys = getSlotNpcKeys(slot);
            for (var j = 0; j < keys.length; j++) {
                if (keys[j] && keys[j] === npcKey) {
                    var rect = rectResolver(slot);
                    if (!rect) return null;
                    return {
                        x: rect.x + (rect.w / 2),
                        y: rect.y + (rect.h / 2),
                        // 任务环套住头像用: 与 renderer drawAvatar 的 r = max(w,h)/2 同口径
                        radius: Math.max(rect.w, rect.h) / 2
                    };
                }
            }
        }

        return null;
    }

    function resolveDynamicAvatarRect(slot) {
        if (!slot || !slot.hotspotId) return null;
        var hotspot = MapPanelData.findHotspot(_activePage.id, slot.hotspotId);
        if (!hotspot || !hotspot.rect) return null;
        return {
            x: hotspot.rect.x + slot.relX,
            y: hotspot.rect.y + slot.relY,
            w: slot.w,
            h: slot.h
        };
    }

    function resolveFlashHintAnchor(hint) {
        if (!hint) return null;

        if (hint.filterId) {
            var filter = MapPanelData.findFilter(_activePage.id, hint.filterId);
            if (filter && filter.buttonRect) {
                return {
                    x: filter.buttonRect.x + (filter.buttonRect.w / 2),
                    y: filter.buttonRect.y + 10
                };
            }
        }

        return resolveFeedbackAnchor(hint);
    }

    function resolveCurrentHotspotId(markers) {
        for (var i = 0; i < markers.length; i++) {
            if (markers[i] && markers[i].kind === 'currentLocation' && markers[i].hotspotId) {
                return markers[i].hotspotId;
            }
        }
        return '';
    }

    function resolvePageIdForHotspot(hotspotId) {
        return hotspotId ? MapPanelData.findHotspotPageId(hotspotId) : '';
    }

    function resolveAssetUrl(assetUrl) {
        var value = String(assetUrl || '');
        var href = '';
        var marker = '/launcher/web/';
        var idx = -1;
        if (!value || /^(?:[a-z]+:|\/|#)/i.test(value)) return value;
        if (typeof document === 'undefined' || !document.location) return value;

        href = String(document.location.href || '');
        idx = href.indexOf(marker);
        if (idx < 0) return value;

        try {
            return new URL(value, href.slice(0, idx + marker.length)).href;
        } catch (err) {
            return value;
        }
    }

    function resolveDynamicAvatarUrl(slot) {
        if (!slot) return '';

        if (slot.kind === 'roommateGender') {
            var gender = String(_dynamicAvatarState.roommateGender || '').toLowerCase();
            if (gender === '女' || gender === 'female' || gender === 'girl' || gender === 'f') {
                return 'assets/map/roommate-female.png';
            }
            return 'assets/map/roommate-male.png';
        }

        return slot.assetUrl || '';
    }

    function mergeHotspotStates(hotspotStates) {
        var hotspotId;
        for (hotspotId in hotspotStates) {
            _hotspotStateLookup[hotspotId] = {
                enabled: hotspotStates[hotspotId].enabled !== undefined ? !!hotspotStates[hotspotId].enabled : !!_enabledLookup[hotspotId],
                unlockGroup: hotspotStates[hotspotId].unlockGroup || (_hotspotStateLookup[hotspotId] ? _hotspotStateLookup[hotspotId].unlockGroup : ''),
                lockedReason: hotspotStates[hotspotId].lockedReason || (_hotspotStateLookup[hotspotId] ? _hotspotStateLookup[hotspotId].lockedReason : '')
            };
        }
    }

    function rebuildEnabledLookupFromStates(fallbackEnabled) {
        var ids = MapPanelData.getAllHotspotIds();
        var i;
        _enabledLookup = {};

        for (i = 0; i < ids.length; i++) {
            var state = getHotspotState(ids[i], fallbackEnabled);
            _enabledLookup[ids[i]] = !!state.enabled;
        }
    }

    function getHotspotState(hotspotId, fallbackEnabled) {
        if (_hotspotStateLookup[hotspotId]) return _hotspotStateLookup[hotspotId];

        return {
            enabled: fallbackEnabled === undefined ? !!_enabledLookup[hotspotId] : !!fallbackEnabled,
            unlockGroup: '',
            lockedReason: ''
        };
    }

    function getFilterMeta(pageId, filterId) {
        var unlockGroup = MapPanelData.getFilterUnlockGroup(pageId, filterId);
        var meta = MapPanelData.getUnlockGroupMeta(unlockGroup);
        if (!meta) return null;

        return {
            unlockGroup: unlockGroup,
            lockedReason: meta.lockedReason
        };
    }

    function buildFilterTitle(filter, enabledCount, filterMeta, isLocked) {
        var title = filter.label + ' (' + enabledCount + '/' + (filter.hotspotIds || []).length + ')';
        if (isLocked && filterMeta && filterMeta.lockedReason) {
            title += ' - ' + filterMeta.lockedReason;
        }
        return title;
    }

    function pushLockedReason(hotspotId) {
        var hotspotState = getHotspotState(hotspotId);
        if (!hotspotState.lockedReason) return;
        if (typeof Toast !== 'undefined' && Toast && typeof Toast.add === 'function') {
            Toast.add(hotspotState.lockedReason);
        }
    }

    function setActiveFilter(filterId) {
        if (!_activePage) return;

        var filter = findFilter(_activePage, filterId);
        if (!filter) return;

        _pageFilterState[_activePage.id] = filter.id;
        renderStageBackdrop();
        renderAvatars();
        renderSceneVisuals();
        renderHotspots();
        renderFeedback();
        renderFilterButtons();
        updatePageSummary();
        scheduleLayoutSync();
    }

    function getVisibleHotspots(page) {
        if (!page) return [];
        var activeFilter = getActiveFilter(page);
        return MapPanelData.getVisibleHotspots(page.id, activeFilter ? activeFilter.id : '');
    }

    function buildVisibleLookup(page) {
        var hotspots = getVisibleHotspots(page);
        var lookup = {};
        for (var i = 0; i < hotspots.length; i++) {
            lookup[hotspots[i].id] = true;
        }
        return lookup;
    }

    function countEnabledIds(ids) {
        var count = 0;
        for (var i = 0; i < ids.length; i++) {
            if (_enabledLookup[ids[i]]) count++;
        }
        return count;
    }

    function getPageFilters(page) {
        return page && page.filters ? page.filters : [];
    }

    function ensurePageFilterState(page) {
        if (!page) return;

        var filters = getPageFilters(page);
        if (!filters.length) {
            delete _pageFilterState[page.id];
            return;
        }

        var currentId = _pageFilterState[page.id];
        if (findFilter(page, currentId)) return;

        var fallbackId = page.defaultFilterId;
        if (!findFilter(page, fallbackId)) {
            fallbackId = filters[0].id;
        }
        _pageFilterState[page.id] = fallbackId;
    }

    function getActiveFilter(page) {
        ensurePageFilterState(page);
        return findFilter(page, _pageFilterState[page.id]);
    }

    function findFilter(page, filterId) {
        if (!page || !filterId) return null;

        var filters = getPageFilters(page);
        for (var i = 0; i < filters.length; i++) {
            if (filters[i].id === filterId) {
                return filters[i];
            }
        }
        return null;
    }

    function getActiveViewMode(page) {
        var activeFilter = getActiveFilter(page);
        return MapPanelData.isLayerRelationFilter(page ? page.id : '', activeFilter ? activeFilter.id : '') ? 'hierarchy' : 'default';
    }

    function getFocusHotspotId(page) {
        var visibleLookup = buildVisibleLookup(page);
        if (_hoverHotspotId && visibleLookup[_hoverHotspotId]) {
            return _hoverHotspotId;
        }
        if (_currentHotspotId && visibleLookup[_currentHotspotId]) {
            return _currentHotspotId;
        }
        return '';
    }

    function setHotspotHover(id, isHover) {
        if (!id) return;
        if (isHover) {
            _hoverHotspotId = id;
        } else if (_hoverHotspotId === id) {
            _hoverHotspotId = '';
        }
        syncHotspotStates();
        syncAvatarStates();
        syncSceneNodeStates();
    }

    function syncHotspotStates() {
        if (!_hotspotLayer) return;

        var activeViewMode = getActiveViewMode(_activePage);
        var focusHotspotId = getFocusHotspotId(_activePage);
        var buttons = _hotspotLayer.querySelectorAll('.map-hotspot');
        for (var i = 0; i < buttons.length; i++) {
            var id = buttons[i].getAttribute('data-hotspot-id') || '';
            var hotspotState = getHotspotState(id);
            var isFocused = !!focusHotspotId && focusHotspotId === id;
            var isMuted = !!focusHotspotId && !isFocused;

            var isBusy = !!_busyLookup[id];
            buttons[i].classList.toggle('is-hover', _hoverHotspotId === id);
            buttons[i].classList.toggle('is-current', _currentHotspotId === id);
            buttons[i].classList.toggle('is-busy', isBusy);
            buttons[i].classList.toggle('is-muted', isMuted);
            buttons[i].classList.toggle('is-relation', activeViewMode === 'hierarchy');
            buttons[i].disabled = isBusy;
        }

        syncHotspotLabelStates();
        syncRailSceneItemStates();
    }

    function syncHotspotLabelStates() {
        if (!_hotspotLabelLayer) return;

        var activeViewMode = getActiveViewMode(_activePage);
        var focusHotspotId = getFocusHotspotId(_activePage);
        var labels = _hotspotLabelLayer.querySelectorAll('.map-hotspot-overlay-label');
        for (var i = 0; i < labels.length; i++) {
            var id = labels[i].getAttribute('data-hotspot-id') || '';
            var hotspotState = getHotspotState(id);
            var isFocused = !!focusHotspotId && focusHotspotId === id;
            var isMuted = !!focusHotspotId && !isFocused;
            var isBusy = !!_busyLookup[id];

            labels[i].classList.toggle('is-hover', _hoverHotspotId === id);
            labels[i].classList.toggle('is-current', _currentHotspotId === id);
            labels[i].classList.toggle('is-busy', isBusy);
            labels[i].classList.toggle('is-muted', isMuted);
            labels[i].classList.toggle('is-disabled', !hotspotState.enabled);
            labels[i].classList.toggle('is-relation', activeViewMode === 'hierarchy');
            var action = labels[i].querySelector('.map-hotspot-stage-select-btn');
            if (action) {
                var stageSelectBusy = _stageSelectBusyHotspotId === id;
                action.classList.toggle('is-busy', stageSelectBusy);
                action.disabled = stageSelectBusy || (!!_stageSelectBusyHotspotId && !stageSelectBusy);
                action.setAttribute('aria-busy', stageSelectBusy ? 'true' : 'false');
            }
        }
    }

    function syncRailSceneItemStates() {
        if (!_railEl) return;

        var items = _railEl.querySelectorAll('.map-rail-scene-item');
        for (var i = 0; i < items.length; i++) {
            var id = items[i].getAttribute('data-hotspot-id') || '';
            var isBusy = !!_busyLookup[id];
            items[i].classList.toggle('is-busy', isBusy);
            items[i].disabled = isBusy;
            items[i].setAttribute('aria-busy', isBusy ? 'true' : 'false');
        }

        var actions = _railEl.querySelectorAll('.map-rail-stage-select-btn');
        for (i = 0; i < actions.length; i++) {
            id = actions[i].getAttribute('data-hotspot-id') || '';
            var stageSelectBusy = _stageSelectBusyHotspotId === id;
            actions[i].classList.toggle('is-busy', stageSelectBusy);
            actions[i].disabled = stageSelectBusy || (!!_stageSelectBusyHotspotId && !stageSelectBusy);
            actions[i].setAttribute('aria-busy', stageSelectBusy ? 'true' : 'false');
        }
    }

    function syncAvatarStates() {
        syncCanvasStage();
    }

    function setHotspotBusy(id, isBusy) {
        if (isBusy) {
            _busyLookup[id] = true;
        } else {
            delete _busyLookup[id];
        }
        var hotspotBtn = _hotspotLayer ? _hotspotLayer.querySelector('[data-hotspot-id="' + id + '"]') : null;
        if (hotspotBtn) hotspotBtn.classList.toggle('is-busy', !!isBusy);

        syncHotspotStates();
        syncAvatarStates();
        syncSceneNodeStates();
    }

    function setLoading(isLoading) {
        _loadingEl.style.display = isLoading ? '' : 'none';
    }

    function clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }

    function roundLayoutValue(value) {
        return Math.round(value * 100) / 100;
    }

    function roundLayoutRect(rect) {
        if (!rect) return null;
        return {
            x: roundLayoutValue(rect.x),
            y: roundLayoutValue(rect.y),
            w: roundLayoutValue(rect.w),
            h: roundLayoutValue(rect.h)
        };
    }

    function bumpCanvasRevision() {
        _canvasRevision += 1;
        return _canvasRevision;
    }

    function isLowEffectsMode() {
        return !!(typeof document !== 'undefined'
            && document.documentElement
            && document.documentElement.classList
            && document.documentElement.classList.contains('perf-low-effects'));
    }

    // applyPage 一次切页会连环触发 renderStageBackdrop/renderSceneVisuals/renderAvatars/...
    // 各调一次 syncCanvasStage; 微任务合并成一次 setState, 避免整份 render state 重建六七遍。
    // revision 仍同步自增 — QA 的 isCanvasCurrent 靠它判断画面是否追上请求。
    function syncCanvasStage() {
        if (!_canvasActive || !_canvasRenderer || !_activePage) return;
        bumpCanvasRevision();
        if (_canvasSyncScheduled) return;
        _canvasSyncScheduled = true;
        scheduleMicrotask(flushCanvasStage);
    }

    function flushCanvasStage() {
        _canvasSyncScheduled = false;
        // 微任务兑现时面板可能已关 (host 驱动关闭) — 关了就别再 setState 重启循环。
        if (!_canvasActive || !_canvasRenderer || !_activePage) return;
        if (!_canvasRenderer.isAvailable || !_canvasRenderer.isAvailable()) {
            showError('canvas_unavailable');
            return;
        }
        _canvasRenderer.setState(buildCanvasRenderState());
    }

    function scheduleMicrotask(fn) {
        if (typeof Promise !== 'undefined') {
            Promise.resolve().then(fn);
        } else {
            setTimeout(fn, 0);
        }
    }

    function buildCanvasRenderState() {
        var activeFilter = getActiveFilter(_activePage);
        var pageId = _activePage ? _activePage.id : '';
        var filterId = activeFilter ? activeFilter.id : '';
        var viewMode = getActiveViewMode(_activePage);
        var visibleKey = pageId + '|' + filterId + '|' + lookupCacheKey(_enabledLookup);
        var avatarKey = visibleKey + '|' + objectCacheKey(_avatarVisibility);
        // dynamicAvatarKey 已与 avatarKey 合并到 taskRings 的 markerKey+avatarKey 组合签名中;
        // canvas 不再需要 dynamic avatar 数据 (DOM 接管), 单独的 dynamicAvatarKey 不必维护.
        var markerKey = visibleKey + '|' + markerCacheKey(_snapshotMarkers);
        var tipKey = visibleKey + '|' + markerCacheKey(_snapshotTips);

        // DOM scene layer 同步: 更新 visibility/.is-* 类, 返回当前 visible visualId 集合.
        // Plan C: canvas 全模式画 scene (稳态原色 / 有 focus 时其它 muted 0.42 / hierarchy 0.74);
        // DOM scene layer 负责 focus 那张的 lift+glow 高亮, canvas 通过 canvasSkipVisualIds 跳过避免双绘.
        var canvasSkipVisualIds = [];
        if (typeof MapSceneVisualLayer !== 'undefined') {
            var syncResult = MapSceneVisualLayer.syncState({
                viewMode: viewMode,
                activeFilterId: filterId,
                currentHotspotId: _currentHotspotId,
                hoverHotspotId: _hoverHotspotId,
                busyLookup: _busyLookup
            });
            canvasSkipVisualIds = (syncResult && syncResult.domVisibleVisualIds) || [];
        }

        // Phase 2: DOM avatar layer 同步. canvas drawAvatars 已删除调用, 此处只更新 DOM.
        if (typeof MapAvatarLayer !== 'undefined' && _activePage) {
            MapAvatarLayer.syncState({
                visibleLookup: buildVisibleLookup(_activePage),
                enabledLookup: _enabledLookup,
                avatarVisibility: _avatarVisibility,
                focusHotspotId: getFocusHotspotId(_activePage),
                currentHotspotId: _currentHotspotId,
                hoverHotspotId: _hoverHotspotId,
                busyLookup: _busyLookup
            });
        }

        return {
            revision: _canvasRevision,
            page: _activePage,
            // background 渲染模式的页面: 把底图 PNG 交给 canvas 作底层绘制 (assembled 页面恒为空)
            backgroundImageUrl: (_activePage && _activePage.backgroundUrl && !useAssembledVisuals(_activePage))
                ? resolveAssetUrl(_activePage.backgroundUrl)
                : '',
            activeFilterId: filterId,
            activeViewMode: viewMode,
            focusHotspotId: getFocusHotspotId(_activePage),
            currentHotspotId: _currentHotspotId,
            hoverHotspotId: _hoverHotspotId,
            busyLookup: cloneLookup(_busyLookup),
            enabledLookup: cloneLookup(_enabledLookup),
            canvasSkipVisualIds: canvasSkipVisualIds,
            stageScale: _stageScale,
            stageWidth: _stageEl ? _stageEl.clientWidth : 0,
            stageHeight: _stageEl ? _stageEl.clientHeight : 0,
            contentFitScale: _contentFitScale,
            contentFitOffsetX: _contentFitOffsetX,
            contentFitOffsetY: _contentFitOffsetY,
            lowEffects: isLowEffectsMode(),
            anomalyActive: !!(_activePage && _activePage.id === 'defense' && activeFilter && activeFilter.id === 'restricted'),
            sceneVisuals: getCanvasRenderSlice('sceneVisuals', visibleKey, function() {
                return buildCanvasSceneVisuals(_activePage);
            }),
            taskRings: getCanvasRenderSlice('taskRings', markerKey + '|' + avatarKey, function() {
                return buildCanvasTaskRings(_activePage);
            }),
            feedbackMarkers: getCanvasRenderSlice('feedbackMarkers', markerKey, function() {
                return buildCanvasFeedbackMarkers(_activePage);
            }),
            feedbackTips: getCanvasRenderSlice('feedbackTips', tipKey, function() {
                return buildCanvasFeedbackTips(_activePage);
            }),
            flashHints: getCanvasRenderSlice('flashHints', visibleKey, function() {
                return buildCanvasFlashHints(_activePage);
            })
        };
    }

    function cloneLookup(source) {
        var out = {};
        var key;
        source = source || {};
        for (key in source) {
            if (Object.prototype.hasOwnProperty.call(source, key)) {
                out[key] = source[key];
            }
        }
        return out;
    }

    function resetCanvasRenderCache() {
        _canvasRenderCache = {};
    }

    function getCanvasRenderSlice(name, key, builder) {
        var slot = _canvasRenderCache[name];
        if (slot && slot.key === key) return slot.value;
        slot = {
            key: key,
            value: builder()
        };
        _canvasRenderCache[name] = slot;
        return slot.value;
    }

    function lookupCacheKey(lookup) {
        var keys = [];
        var key;
        lookup = lookup || {};
        for (key in lookup) {
            if (Object.prototype.hasOwnProperty.call(lookup, key) && lookup[key]) keys.push(key);
        }
        keys.sort();
        return keys.join(',');
    }

    function objectCacheKey(source) {
        var keys = [];
        var out = [];
        var key;
        var i;
        source = source || {};
        for (key in source) {
            if (Object.prototype.hasOwnProperty.call(source, key)) keys.push(key);
        }
        keys.sort();
        for (i = 0; i < keys.length; i++) {
            out.push(keys[i] + '=' + String(source[keys[i]]));
        }
        return out.join(',');
    }

    function markerCacheKey(markers) {
        var out = [];
        var i;
        var item;
        markers = markers || [];
        for (i = 0; i < markers.length; i++) {
            item = markers[i] || {};
            out.push([
                item.id || '',
                item.kind || '',
                item.pageId || '',
                item.hotspotId || '',
                item.npcName || '',
                item.label || '',
                item.tone || '',
                item.point && item.point.x !== undefined ? item.point.x : '',
                item.point && item.point.y !== undefined ? item.point.y : ''
            ].join(':'));
        }
        return out.join(';');
    }

    function buildCanvasSceneVisuals(page) {
        var visuals = getVisibleSceneVisuals(page);
        var out = [];
        var i;
        var ids;
        var hasEnabledHotspot;
        var j;
        if (!page) return out;
        for (i = 0; i < visuals.length; i++) {
            ids = visuals[i].hotspotIds || [];
            hasEnabledHotspot = ids.length === 0;
            for (j = 0; j < ids.length; j++) {
                if (_enabledLookup[ids[j]]) {
                    hasEnabledHotspot = true;
                    break;
                }
            }
            if (!hasEnabledHotspot) continue;
            out.push({
                id: visuals[i].id,
                label: visuals[i].label || visuals[i].id,
                assetUrl: visuals[i].assetUrl,
                rect: cloneRect(visuals[i].rect),
                hotspotIds: (visuals[i].hotspotIds || []).slice()
            });
        }
        return out;
    }

    function avatarFallbackChar(label) {
        var s = label ? String(label).replace(/^\s+/, '') : '';
        return s ? s.charAt(0) : '?';
    }

    // Phase 2: 把 page.staticAvatars + page.dynamicAvatars 解析成统一 slot 列表喂 MapAvatarLayer.
    // 资源 URL / rect / fallback char 全部预解析. 与 filter / hover 无关, 仅页/动态 state 影响.
    function buildAvatarLayerSlots(page) {
        var out = [];
        var i;
        var slot;
        var rect;
        var url;
        if (!page) return out;
        var staticSlots = page.staticAvatars || [];
        for (i = 0; i < staticSlots.length; i += 1) {
            slot = staticSlots[i];
            if (!slot || !slot.assetUrl) continue;
            rect = resolveStaticAvatarRect(slot);
            if (!rect) continue;
            out.push({
                id: slot.id || '',
                kind: 'static',
                label: slot.label || '',
                hotspotId: slot.hotspotId || '',
                rect: cloneRect(rect),
                assetUrl: resolveAssetUrl(slot.assetUrl),
                fallbackChar: avatarFallbackChar(slot.label)
            });
        }
        var dynamicSlots = page.dynamicAvatars || [];
        for (i = 0; i < dynamicSlots.length; i += 1) {
            slot = dynamicSlots[i];
            if (!slot) continue;
            url = resolveDynamicAvatarUrl(slot);
            if (!url) continue;
            rect = resolveDynamicAvatarRect(slot);
            if (!rect) continue;
            out.push({
                id: slot.id || '',
                kind: 'dynamic',
                label: slot.label || '',
                hotspotId: slot.hotspotId || '',
                rect: cloneRect(rect),
                assetUrl: resolveAssetUrl(url),
                fallbackChar: avatarFallbackChar(slot.label)
            });
        }
        return out;
    }

    function buildCanvasStaticAvatars(page) {
        var visibleLookup = buildVisibleLookup(page);
        var slots = page && page.staticAvatars ? page.staticAvatars : [];
        var out = [];
        var i;
        var slot;
        var rect;
        for (i = 0; i < slots.length; i++) {
            slot = slots[i];
            if (slot.hotspotId && !visibleLookup[slot.hotspotId]) continue;
            if (slot.hotspotId && !_enabledLookup[slot.hotspotId]) continue;
            if (!slot.assetUrl) continue;
            if (slot.id && _avatarVisibility.hasOwnProperty(slot.id) && _avatarVisibility[slot.id] === false) continue;
            rect = resolveStaticAvatarRect(slot);
            if (!rect) continue;
            out.push({
                id: slot.id || '',
                label: slot.label || '',
                hotspotId: slot.hotspotId || '',
                assetUrl: resolveAssetUrl(slot.assetUrl),
                rect: cloneRect(rect)
            });
        }
        return out;
    }

    function buildCanvasDynamicAvatars(page) {
        var visibleLookup = buildVisibleLookup(page);
        var slots = page && page.dynamicAvatars ? page.dynamicAvatars : [];
        var out = [];
        var i;
        var slot;
        var assetUrl;
        var rect;
        for (i = 0; i < slots.length; i++) {
            slot = slots[i];
            if (slot.hotspotId && !visibleLookup[slot.hotspotId]) continue;
            if (slot.hotspotId && !_enabledLookup[slot.hotspotId]) continue;
            assetUrl = resolveDynamicAvatarUrl(slot);
            if (!assetUrl) continue;
            rect = resolveDynamicAvatarRect(slot);
            if (!rect) continue;
            out.push({
                id: slot.id || '',
                label: slot.label || '',
                hotspotId: slot.hotspotId || '',
                assetUrl: resolveAssetUrl(assetUrl),
                rect: cloneRect(rect)
            });
        }
        return out;
    }

    function buildCanvasTaskRings(page) {
        var visibleLookup = buildVisibleLookup(page);
        var out = [];
        var i;
        var marker;
        var avatarAnchor;
        var anchor;
        if (!page) return out;
        for (i = 0; i < _snapshotMarkers.length; i++) {
            marker = _snapshotMarkers[i];
            if (!marker || marker.kind !== 'taskNpc') continue;
            if (marker.pageId && marker.pageId !== page.id) continue;
            if (marker.hotspotId && !visibleLookup[marker.hotspotId]) continue;
            if (marker.hotspotId && !_enabledLookup[marker.hotspotId]) continue;
            avatarAnchor = findAvatarAnchorForMarker(marker, visibleLookup);
            anchor = avatarAnchor || resolveFeedbackAnchor(marker);
            if (!anchor) continue;
            out.push({
                id: marker.id || '',
                hotspotId: marker.hotspotId || '',
                point: clonePoint(anchor),
                // >0 = 命中头像, 任务环套住头像; 0 = 未命中, 回退固定小环
                avatarRadius: (avatarAnchor && avatarAnchor.radius) || 0
            });
        }
        return out;
    }

    function buildCanvasFeedbackMarkers(page) {
        var out = [];
        var i;
        var marker;
        var anchor;
        if (!page) return out;
        for (i = 0; i < _snapshotMarkers.length; i++) {
            marker = _snapshotMarkers[i];
            if (marker && marker.kind === 'taskNpc') continue;
            if (!shouldRenderFeedbackItem(marker)) continue;
            anchor = resolveFeedbackAnchor(marker);
            if (!anchor) continue;
            out.push({
                id: marker.id || '',
                kind: marker.kind || '',
                hotspotId: marker.hotspotId || '',
                point: clonePoint(anchor)
            });
        }
        return out;
    }

    function buildCanvasFeedbackTips(page) {
        var out = [];
        var i;
        var tip;
        var anchor;
        if (!page) return out;
        for (i = 0; i < _snapshotTips.length; i++) {
            tip = _snapshotTips[i];
            if (!shouldRenderFeedbackItem(tip)) continue;
            anchor = resolveFeedbackAnchor(tip);
            if (!anchor) continue;
            out.push({
                id: tip.id || '',
                label: tip.label || '提示',
                tone: tip.tone || '',
                hotspotId: tip.hotspotId || '',
                point: clonePoint(anchor)
            });
        }
        return out;
    }

    function buildCanvasFlashHints(page) {
        var hints = page ? MapPanelData.getPageFlashHints(page.id) : [];
        var out = [];
        var i;
        var hint;
        var anchor;
        for (i = 0; i < hints.length; i++) {
            hint = hints[i];
            if (!shouldRenderFlashHint(hint)) continue;
            anchor = resolveFlashHintAnchor(hint);
            if (!anchor) continue;
            out.push({
                id: hint.id || '',
                label: hint.label || '未开放',
                kind: hint.kind || '',
                tone: hint.tone || '',
                point: clonePoint(anchor)
            });
        }
        return out;
    }

    function cloneRect(rect) {
        if (!rect) return null;
        return {
            x: Number(rect.x) || 0,
            y: Number(rect.y) || 0,
            w: Number(rect.w) || 0,
            h: Number(rect.h) || 0
        };
    }

    function clonePoint(point) {
        if (!point) return null;
        return {
            x: Number(point.x) || 0,
            y: Number(point.y) || 0
        };
    }

    function resetContentFit() {
        _contentFitScale = 1;
        _contentFitOffsetX = 0;
        _contentFitOffsetY = 0;
        _contentFitPadX = 0;
        _contentFitPadY = 0;
        _contentFitPresetId = '';
        _contentFitPresetMeta = null;
        _contentBounds = null;
        _stageViewportWidth = 0;
        _stageViewportHeight = 0;
        if (_contentFitEl) {
            _contentFitEl.style.transform = 'translate3d(0px, 0px, 0) scale(1)';
        }
        syncCanvasStage();
    }

    function applyContentFit(scale, offsetX, offsetY, bounds, stageWidth, stageHeight, fitMeta) {
        _contentFitScale = scale;
        _contentFitOffsetX = offsetX;
        _contentFitOffsetY = offsetY;
        _contentFitPadX = fitMeta && isFinite(fitMeta.padX) ? roundLayoutValue(fitMeta.padX) : 0;
        _contentFitPadY = fitMeta && isFinite(fitMeta.padY) ? roundLayoutValue(fitMeta.padY) : 0;
        _contentFitPresetId = fitMeta && fitMeta.presetId ? String(fitMeta.presetId) : '';
        _contentFitPresetMeta = fitMeta ? {
            presetId: fitMeta.presetId || '',
            padXRate: roundLayoutValue(fitMeta.padXRate || 0),
            padYRate: roundLayoutValue(fitMeta.padYRate || 0),
            maxScale: roundLayoutValue(fitMeta.maxScale || 1),
            biasX: roundLayoutValue(fitMeta.biasX || 0),
            biasY: roundLayoutValue(fitMeta.biasY || 0)
        } : null;
        _contentBounds = roundLayoutRect(bounds);
        _stageViewportWidth = roundLayoutValue(stageWidth);
        _stageViewportHeight = roundLayoutValue(stageHeight);
        if (_contentFitEl) {
            _contentFitEl.style.transform =
                'translate3d(' + offsetX.toFixed(2) + 'px, ' + offsetY.toFixed(2) + 'px, 0) scale(' + scale.toFixed(4) + ')';
        }
        syncCanvasStage();
    }

    function measureContentBounds() {
        if (!_activePage) return null;

        var rects = [];
        var hotspots = getVisibleHotspots(_activePage);
        var scenes = buildCanvasSceneVisuals(_activePage);
        var staticAvatars = buildCanvasStaticAvatars(_activePage);
        var dynamicAvatars = buildCanvasDynamicAvatars(_activePage);
        var taskRings = buildCanvasTaskRings(_activePage);
        var markers = buildCanvasFeedbackMarkers(_activePage);
        var tips = buildCanvasFeedbackTips(_activePage);
        var i;

        for (i = 0; i < scenes.length; i++) rects.push(scenes[i].rect);
        for (i = 0; i < hotspots.length; i++) {
            // 仅计入实际会渲染的解锁 hotspot；锁定区域不渲染也不参与取景包围盒（剧透防护一致性）
            if (_enabledLookup[hotspots[i].id]) {
                rects.push(hotspots[i].rect);
            }
        }
        for (i = 0; i < staticAvatars.length; i++) rects.push(staticAvatars[i].rect);
        for (i = 0; i < dynamicAvatars.length; i++) rects.push(dynamicAvatars[i].rect);
        for (i = 0; i < taskRings.length; i++) rects.push(pointRect(taskRings[i].point, 28, 28));
        for (i = 0; i < markers.length; i++) rects.push(pointRect(markers[i].point, 44, 44));
        for (i = 0; i < tips.length; i++) rects.push(pointRect(tips[i].point, 132, 32));
        // flash hint（"尚未开放"提示）锚定在锁定区域，不计入取景包围盒 —
        // 还原旧 measureContentBounds 行为（旧版 querySelector 不含 .map-feedback-hint），
        // 否则散布全图的提示会撑大包围盒，使单一解锁区无法自适应放大。

        return scaleBoundsForLayout(unionRects(rects));
    }

    function scaleBoundsForLayout(bounds) {
        var scale = _stageScale || 1;
        if (!bounds) return null;
        return {
            x: bounds.x * scale,
            y: bounds.y * scale,
            w: bounds.w * scale,
            h: bounds.h * scale
        };
    }

    function pointRect(point, w, h) {
        if (!point) return null;
        return {
            x: point.x - w / 2,
            y: point.y - h / 2,
            w: w,
            h: h
        };
    }

    function unionRects(rects) {
        var minX = Infinity;
        var minY = Infinity;
        var maxX = -Infinity;
        var maxY = -Infinity;
        var i;
        var rect;
        for (i = 0; i < rects.length; i++) {
            rect = rects[i];
            if (!rect || rect.w <= 0 || rect.h <= 0) continue;
            minX = Math.min(minX, rect.x);
            minY = Math.min(minY, rect.y);
            maxX = Math.max(maxX, rect.x + rect.w);
            maxY = Math.max(maxY, rect.y + rect.h);
        }
        if (!isFinite(minX) || !isFinite(minY) || !isFinite(maxX) || !isFinite(maxY)) return null;
        return {
            x: minX,
            y: minY,
            w: Math.max(1, maxX - minX),
            h: Math.max(1, maxY - minY)
        };
    }

    function resolveContentFitPreset(pageId, filterId) {
        var preset = {
            id: (pageId || '') + ':' + (filterId || '*'),
            pageId: pageId || '',
            filterId: filterId || '',
            padXRate: 0.055,
            padXMin: 22,
            padXMax: 54,
            padYRate: 0.07,
            padYMin: 20,
            padYMax: 48,
            maxScale: 1.36,
            biasX: 0,
            biasY: 0
        };
        var source = (typeof MapFitPresets !== 'undefined' && MapFitPresets && typeof MapFitPresets.resolve === 'function')
            ? MapFitPresets.resolve(pageId || '', filterId || '')
            : null;
        var numericKeys = ['padXRate', 'padXMin', 'padXMax', 'padYRate', 'padYMin', 'padYMax', 'maxScale', 'biasX', 'biasY'];
        var i;

        if (source) {
            if (source.id) preset.id = String(source.id);
            for (i = 0; i < numericKeys.length; i++) {
                if (isFinite(source[numericKeys[i]])) {
                    preset[numericKeys[i]] = Number(source[numericKeys[i]]);
                }
            }
        }

        preset.padXRate = clamp(preset.padXRate, 0.02, 0.12);
        preset.padYRate = clamp(preset.padYRate, 0.02, 0.12);
        preset.padXMin = clamp(preset.padXMin, 0, 96);
        preset.padXMax = Math.max(preset.padXMin, preset.padXMax);
        preset.padYMin = clamp(preset.padYMin, 0, 96);
        preset.padYMax = Math.max(preset.padYMin, preset.padYMax);
        preset.maxScale = Math.max(1, preset.maxScale);
        preset.biasX = clamp(preset.biasX, -1, 1);
        preset.biasY = clamp(preset.biasY, -1, 1);

        return preset;
    }

    function syncContentFit() {
        if (!_contentFitEl || !_stageEl || !_activePage) return;

        _contentFitEl.style.transform = 'translate3d(0px, 0px, 0) scale(1)';

        var activeFilter = getActiveFilter(_activePage);
        var fitPreset = resolveContentFitPreset(_activePage.id, activeFilter ? activeFilter.id : '');
        var stageRect = _stageEl.getBoundingClientRect();
        var stageWidth = Math.max(0, _stageEl.clientWidth || stageRect.width);
        var stageHeight = Math.max(0, _stageEl.clientHeight || stageRect.height);
        var bounds = measureContentBounds();
        var padX;
        var padY;
        var fitScale;
        var targetWidth;
        var targetHeight;
        var offsetX;
        var offsetY;
        var slackX;
        var slackY;

        if (!stageWidth || !stageHeight) {
            resetContentFit();
            return;
        }

        if (!useAssembledVisuals(_activePage) || !bounds) {
            applyContentFit(1, 0, 0, bounds, stageWidth, stageHeight, {
                presetId: fitPreset.id,
                padX: 0,
                padY: 0,
                padXRate: fitPreset.padXRate,
                padYRate: fitPreset.padYRate,
                maxScale: fitPreset.maxScale,
                biasX: fitPreset.biasX,
                biasY: fitPreset.biasY
            });
            return;
        }

        padX = clamp(stageWidth * fitPreset.padXRate, fitPreset.padXMin, fitPreset.padXMax);
        padY = clamp(stageHeight * fitPreset.padYRate, fitPreset.padYMin, fitPreset.padYMax);
        fitScale = Math.max(
            1,
            Math.min(
                (stageWidth - (padX * 2)) / bounds.w,
                (stageHeight - (padY * 2)) / bounds.h,
                fitPreset.maxScale
            )
        );

        if (!isFinite(fitScale) || fitScale <= 0) {
            fitScale = 1;
        }

        targetWidth = bounds.w * fitScale;
        targetHeight = bounds.h * fitScale;
        offsetX = ((stageWidth - targetWidth) / 2) - (bounds.x * fitScale);
        offsetY = ((stageHeight - targetHeight) / 2) - (bounds.y * fitScale);
        slackX = Math.max(0, stageWidth - targetWidth - (padX * 2));
        slackY = Math.max(0, stageHeight - targetHeight - (padY * 2));
        offsetX += (slackX * 0.5) * fitPreset.biasX;
        offsetY += (slackY * 0.5) * fitPreset.biasY;

        applyContentFit(fitScale, offsetX, offsetY, bounds, stageWidth, stageHeight, {
            presetId: fitPreset.id,
            padX: padX,
            padY: padY,
            padXRate: fitPreset.padXRate,
            padYRate: fitPreset.padYRate,
            maxScale: fitPreset.maxScale,
            biasX: fitPreset.biasX,
            biasY: fitPreset.biasY
        });
    }

    function describeDomRect(rect) {
        if (!rect) return null;
        return {
            x: roundLayoutValue(rect.left),
            y: roundLayoutValue(rect.top),
            w: roundLayoutValue(rect.width),
            h: roundLayoutValue(rect.height)
        };
    }

    function emitLayoutDiagnostic(reason, extra) {
        if (!_debugTelemetryEnabled || !_activePage || !_stageEl || !_stageShellEl || typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') return;

        var activeFilter = getActiveFilter(_activePage);
        var visualViewport = (typeof window !== 'undefined' && window.visualViewport) ? window.visualViewport : null;
        var payload = {
            reason: reason || 'layout_sync',
            activePageId: _activePage.id,
            activeFilterId: activeFilter ? activeFilter.id : null,
            currentHotspotId: _currentHotspotId,
            stageScale: roundLayoutValue(_stageScale),
            contentFitScale: roundLayoutValue(_contentFitScale),
            contentFitOffsetX: roundLayoutValue(_contentFitOffsetX),
            contentFitOffsetY: roundLayoutValue(_contentFitOffsetY),
            contentFitPadX: _contentFitPadX,
            contentFitPadY: _contentFitPadY,
            activeFitPresetId: _contentFitPresetId,
            contentFitPreset: _contentFitPresetMeta,
            stageViewportWidth: _stageViewportWidth,
            stageViewportHeight: _stageViewportHeight,
            compactMode: !!(_el && _el.classList.contains('is-compact')),
            contentCoverageX: _contentBounds && _stageViewportWidth
                ? roundLayoutValue((_contentBounds.w * _contentFitScale) / _stageViewportWidth)
                : 0,
            contentCoverageY: _contentBounds && _stageViewportHeight
                ? roundLayoutValue((_contentBounds.h * _contentFitScale) / _stageViewportHeight)
                : 0,
            windowInnerWidth: (typeof window !== 'undefined' && window.innerWidth) ? window.innerWidth : 0,
            windowInnerHeight: (typeof window !== 'undefined' && window.innerHeight) ? window.innerHeight : 0,
            visualViewportWidth: visualViewport ? roundLayoutValue(visualViewport.width) : 0,
            visualViewportHeight: visualViewport ? roundLayoutValue(visualViewport.height) : 0,
            bodyClientWidth: _bodyEl ? _bodyEl.clientWidth : 0,
            bodyClientHeight: _bodyEl ? _bodyEl.clientHeight : 0,
            shellClientWidth: _stageShellEl ? _stageShellEl.clientWidth : 0,
            shellClientHeight: _stageShellEl ? _stageShellEl.clientHeight : 0,
            stageClientWidth: _stageEl ? _stageEl.clientWidth : 0,
            stageClientHeight: _stageEl ? _stageEl.clientHeight : 0,
            contentBounds: _contentBounds
        };

        if (extra) {
            var key;
            for (key in extra) {
                if (Object.prototype.hasOwnProperty.call(extra, key)) {
                    payload[key] = extra[key];
                }
            }
        }

        Bridge.send({
            type: 'debug',
            scope: 'map_layout',
            payload: payload
        });
    }

    function initLayoutWatcher() {
        if (_layoutObserver || !_el || !_bodyEl) return;

        if (typeof ResizeObserver !== 'undefined') {
            _layoutObserver = new ResizeObserver(function() {
                handleViewportLayoutChange('resize_observer');
            });
            _layoutObserver.observe(_el);
            _layoutObserver.observe(_bodyEl);
            if (_stageShellEl) _layoutObserver.observe(_stageShellEl);
            if (_railEl) _layoutObserver.observe(_railEl);
        }

        if (!_windowResizeBound && typeof window !== 'undefined' && window.addEventListener) {
            if (!_windowResizeHandler) {
                _windowResizeHandler = function() {
                    handleViewportLayoutChange('window_resize');
                };
            }
            _windowResizeBound = true;
            window.addEventListener('resize', _windowResizeHandler);
        }
        if (!_visualViewportResizeBound && typeof window !== 'undefined' && window.visualViewport && window.visualViewport.addEventListener) {
            if (!_visualViewportResizeHandler) {
                _visualViewportResizeHandler = function() {
                    handleViewportLayoutChange('visual_viewport_resize');
                };
            }
            _visualViewportResizeBound = true;
            window.visualViewport.addEventListener('resize', _visualViewportResizeHandler);
        }
    }

    function handleViewportLayoutChange(reason) {
        var layoutReason = (typeof reason === 'string' && reason) ? reason : 'external_resize';
        markStageInteracting();
        scheduleLayoutSync(layoutReason);
        scheduleSettledLayoutSync(layoutReason + ':settled');
    }

    // 滑动 / resize 期临时给 stage 打 is-resizing 类, CSS 借此关掉父级 filter graph 与 scene-node 装饰层。
    // 每次触发都 push 一次 140ms timer (略大于 settled sync 的 110ms), 停手后才清掉, 避免连续 resize 期间反复 add/remove。
    function markStageInteracting() {
        if (!_stageEl) return;
        _stageEl.classList.add('is-resizing');
        if (_resizingClassTimer) clearTimeout(_resizingClassTimer);
        _resizingClassTimer = setTimeout(function() {
            _resizingClassTimer = 0;
            if (_stageEl) _stageEl.classList.remove('is-resizing');
        }, 140);
    }

    function scheduleLayoutSync(reason) {
        if (!_activePage || !_bodyEl || !_stageEl) return;
        _layoutPendingReason = (typeof reason === 'string' && reason) ? reason : (_layoutPendingReason || 'layout_sync');
        if (_layoutRaf) return;

        _layoutRaf = (typeof requestAnimationFrame === 'function'
            ? requestAnimationFrame
            : function(cb) { return setTimeout(cb, 16); })(function() {
                var layoutReason = _layoutPendingReason || 'layout_sync';
                _layoutRaf = 0;
                _layoutPendingReason = '';
                syncStageLayout(layoutReason);
            });
    }

    function scheduleSettledLayoutSync(reason) {
        if (!_activePage || !_bodyEl || !_stageEl) return;
        if (_layoutSettleTimer) {
            clearTimeout(_layoutSettleTimer);
        }
        _layoutSettleTimer = setTimeout(function() {
            _layoutSettleTimer = 0;
            scheduleLayoutSync((typeof reason === 'string' && reason) ? reason : 'layout_settled');
        }, 110);
    }

    function syncStageLayout(reason) {
        if (!_activePage || !_bodyEl || !_stageEl || !_stageShellEl) return;

        // shell 是 body 内 stage 的直接父容器 (与 rail 平铺), shell 的 contentBox 才是 stage 可用空间;
        // 直接读 body 会把 rail 宽度也算进去, 导致 stage 超出 shell 再回头引发横向/纵向溢出。
        var shellRect = _stageShellEl.getBoundingClientRect();
        var bodyStyle = window.getComputedStyle ? window.getComputedStyle(_bodyEl) : null;
        var bodyPaddingTop = bodyStyle ? (parseFloat(bodyStyle.paddingTop) || 0) : 0;
        var bodyPaddingBottom = bodyStyle ? (parseFloat(bodyStyle.paddingBottom) || 0) : 0;
        var bodyAvailableHeight = Math.max(0, (_bodyEl.clientHeight || 0) - bodyPaddingTop - bodyPaddingBottom);
        var availableWidth = Math.max(320, Math.floor(_stageShellEl.clientWidth || shellRect.width));
        var availableHeight = Math.max(220, Math.floor(Math.max(_stageShellEl.clientHeight || 0, shellRect.height || 0, bodyAvailableHeight)));
        var widthScale = availableWidth / _activePage.width;
        var heightScale = availableHeight / _activePage.height;
        _stageScale = Math.min(widthScale, heightScale, STAGE_MAX_SCALE);
        if (!isFinite(_stageScale) || _stageScale <= 0) {
            _stageScale = 1;
        }

        _stageEl.style.width = Math.round(_activePage.width * _stageScale) + 'px';
        _stageEl.style.height = Math.round(_activePage.height * _stageScale) + 'px';
        syncContentFit();
        _el.classList.toggle('is-compact', _stageScale < 0.985);
        emitLayoutDiagnostic(reason || 'layout_sync', {
            availableWidth: availableWidth,
            availableHeight: availableHeight,
            bodyAvailableHeight: roundLayoutValue(bodyAvailableHeight),
            widthScale: roundLayoutValue(widthScale),
            heightScale: roundLayoutValue(heightScale),
            shellRect: describeDomRect(shellRect),
            stageRect: describeDomRect(_stageEl.getBoundingClientRect()),
            bodyRect: describeDomRect(_bodyEl.getBoundingClientRect())
        });
    }

    function showError(errorText) {
        setLoading(false);
        _errorTextEl.textContent = normalizeError(errorText);
        _errorEl.style.display = 'flex';
        playCue('error');
    }

    function hideError() {
        _errorEl.style.display = 'none';
        _errorTextEl.textContent = '';
    }

    function normalizeError(errorText) {
        switch (String(errorText || '')) {
            case 'timeout': return '启动器等待地图状态响应超时。';
            case 'disconnected': return '当前未连接到游戏运行时。';
            case 'invalid_target': return '目标区域无效或暂不可达。';
            case 'canvas_unavailable': return '当前 WebView2 不支持地图 Canvas 渲染。';
            default: return '地图桥接返回错误: ' + String(errorText || 'unknown_error');
        }
    }

    function toPercent(value, total) {
        return ((value / total) * 100).toFixed(3) + '%';
    }

    function escHtml(s) {
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
    }

    function getDebugState() {
        var hotspots = _activePage ? getVisibleHotspots(_activePage) : [];
        var activeFilter = _activePage ? getActiveFilter(_activePage) : null;
        var visibleHotspotIds = [];
        var enabledHotspotIds = [];
        var lockedHotspotIds = [];
        var stageSelectHotspotIds = [];
        var taskStageSelectHotspotIds = [];
        var i;

        for (i = 0; i < hotspots.length; i++) {
            visibleHotspotIds.push(hotspots[i].id);
            if (_enabledLookup[hotspots[i].id]) {
                enabledHotspotIds.push(hotspots[i].id);
            } else {
                lockedHotspotIds.push(hotspots[i].id);
            }
            if (resolveStageSelectEntryForHotspot(hotspots[i])) {
                stageSelectHotspotIds.push(hotspots[i].id);
                if (_taskBadge.byHotspot[hotspots[i].id]) {
                    taskStageSelectHotspotIds.push(hotspots[i].id);
                }
            }
        }

        var state = {
            isOpen: Panels.isOpen(),
            activePageId: _activePage ? _activePage.id : null,
            activeFilterId: activeFilter ? activeFilter.id : null,
            title: _activePage ? _activePage.title : '',
            summary: _pageSummaryEl ? _pageSummaryEl.textContent : '',
            loadingVisible: !!(_loadingEl && _loadingEl.style.display !== 'none'),
            errorVisible: !!(_errorEl && _errorEl.style.display !== 'none'),
            errorText: _errorTextEl ? _errorTextEl.textContent : '',
            visibleHotspotIds: visibleHotspotIds,
            enabledHotspotIds: enabledHotspotIds,
            lockedHotspotIds: lockedHotspotIds,
            stageSelectHotspotIds: stageSelectHotspotIds,
            taskStageSelectHotspotIds: taskStageSelectHotspotIds,
            stageSelectBusyHotspotId: _stageSelectBusyHotspotId,
            dynamicAvatarState: _dynamicAvatarState,
            unlockFlags: _unlockFlags,
            currentHotspotId: _currentHotspotId,
            focusHotspotId: getFocusHotspotId(_activePage),
            activeViewMode: getActiveViewMode(_activePage),
            renderMode: _activePage && _activePage.renderMode ? _activePage.renderMode : 'background',
            sceneVisualCount: _activePage ? buildCanvasSceneVisuals(_activePage).length : 0,
            canvasRequestedRevision: _canvasRevision,
            stageScale: _stageScale,
            contentFitScale: _contentFitScale,
            contentFitOffsetX: roundLayoutValue(_contentFitOffsetX),
            contentFitOffsetY: roundLayoutValue(_contentFitOffsetY),
            contentFitPadX: _contentFitPadX,
            contentFitPadY: _contentFitPadY,
            activeFitPresetId: _contentFitPresetId,
            contentFitPreset: _contentFitPresetMeta,
            contentBounds: _contentBounds,
            stageViewportWidth: _stageViewportWidth,
            stageViewportHeight: _stageViewportHeight,
            contentCoverageX: _contentBounds && _stageViewportWidth
                ? roundLayoutValue((_contentBounds.w * _contentFitScale) / _stageViewportWidth)
                : 0,
            contentCoverageY: _contentBounds && _stageViewportHeight
                ? roundLayoutValue((_contentBounds.h * _contentFitScale) / _stageViewportHeight)
                : 0,
            compactMode: !!(_el && _el.classList.contains('is-compact')),
            flashHintIds: _activePage ? MapPanelData.getPageFlashHints(_activePage.id).filter(function(item) {
                return shouldRenderFlashHint(item);
            }).map(function(item) { return item.id; }) : [],
            markerIds: (_snapshotMarkers || []).map(function(item) { return item.id; }),
            tipIds: (_snapshotTips || []).map(function(item) { return item.id; }),
            taskRings: _activePage ? buildCanvasTaskRings(_activePage) : [],
            taskBadge: _taskBadge
        };
        if (_canvasRenderer && _canvasRenderer.getDebugState) {
            var canvasDebug = _canvasRenderer.getDebugState();
            var key;
            for (key in canvasDebug) {
                if (Object.prototype.hasOwnProperty.call(canvasDebug, key)) {
                    state[key] = canvasDebug[key];
                }
            }
        } else {
            state.renderer = 'canvas';
            state.canvasReady = false;
            state.canvasPendingAssets = 0;
            state.canvasDrawCount = 0;
        }
        if (typeof MapSceneVisualLayer !== 'undefined' && MapSceneVisualLayer.debugState) {
            state.sceneVisualLayer = MapSceneVisualLayer.debugState();
        }
        if (typeof MapAvatarLayer !== 'undefined' && MapAvatarLayer.debugState) {
            state.avatarLayer = MapAvatarLayer.debugState();
        }
        return state;
    }

    Bridge.on('panel_resp', function(data) {
        if (!data || data.panel !== 'map') return;
        var cb = _pendingReq[data.callId];
        if (cb) cb(data);
    });

    return {
        _debugGetState: getDebugState,
        _debugApplySnapshot: applySnapshot,
        _debugSetFilter: setActiveFilter,
        _debugRequestSnapshot: requestSnapshot,
        _debugSyncLayout: syncStageLayout
    };
})();
