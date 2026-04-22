var MapPanel = (function() {
    'use strict';

    // Stage 最大 scale · 单一真相源
    //   - map-panel.js syncStageLayout 的一级缩放上限
    //   - tools/tune-map-filter-fit.js STAGE_MAX_SCALE 必须同步 (离线 fit 算分才能对齐)
    //   - 调大需回查 composite PNG 源分辨率, 否则最终总放大 > 1.5x 会 pixelated
    var STAGE_MAX_SCALE = 1.3;

    var _el, _titleEl, _bodyEl, _stageEl, _stageShellEl, _railEl, _backdropEl, _filterOverlayEl, _anomalyEl, _contentFitEl, _imageEl, _sceneLayer, _hotspotLayer, _avatarLayer, _feedbackLayer, _overlayLayer, _loadingEl, _errorEl, _errorTextEl, _badgeEl;
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
    var _currentHotspotId = '';
    var _hoverHotspotId = '';
    var _busyLookup = {};
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
    var _windowResizeBound = false;
    var _visualViewportResizeBound = false;
    var _windowResizeHandler = null;
    var _visualViewportResizeHandler = null;
    var _debugTelemetryEnabled = false;
    var _snapshotAnnounced = false;     // 每次 onOpen 后首次 snapshot 成功播 ready, 避免刷新 spam

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
        onClose: teardownLayoutWatcher,
        onForceClose: onForceClose
    });

    function createDOM() {
        _el = document.createElement('div');
        _el.className = 'map-panel';
        _el.innerHTML =
            '<div class="map-panel-header">' +
                '<div class="map-panel-heading">' +
                    '<span class="map-panel-title">地图测试</span>' +
                    '<span class="map-panel-region" id="map-panel-region"></span>' +
                '</div>' +
                '<div class="map-page-tabs" id="map-page-tabs"></div>' +
                '<div class="map-page-summary" id="map-page-summary"></div>' +
                '<div class="map-panel-badge" id="map-panel-badge">DEV</div>' +
                '<button class="map-panel-close-btn" type="button" title="关闭" data-audio-cue="cancel">X</button>' +
            '</div>' +
            '<div class="map-panel-body">' +
                '<div class="map-stage-shell" id="map-stage-shell">' +
                    '<div class="map-stage-frame" id="map-stage-frame">' +
                        '<div class="map-stage-backdrop" id="map-stage-backdrop">' +
                            // filter-overlay 与 anomaly 嵌在 backdrop 内 —
                            // backdrop z-index:0 建立 stacking context, 子元素全部被封印在 z=0 层,
                            // 无法逃逸到 image(z:1) / scenes(z:2) 之上, 避免干扰半透明场景边缘
                            '<div class="map-stage-filter-overlay" id="map-stage-filter-overlay" aria-hidden="true"></div>' +
                            '<div class="map-stage-anomaly" id="map-stage-anomaly" aria-hidden="true">' +
                                '<div class="map-stage-anomaly-pulse"></div>' +
                            '</div>' +
                        '</div>' +
                        '<img class="map-stage-image" id="map-stage-image" alt="地图背景">' +
                        '<div class="map-stage-content-fit" id="map-stage-content-fit">' +
                        '<div class="map-scene-layer" id="map-scene-layer"></div>' +
                        '<div class="map-hotspot-layer" id="map-hotspot-layer"></div>' +
                        '<div class="map-dynamic-avatar-layer" id="map-dynamic-avatar-layer"></div>' +
                        '<div class="map-feedback-layer" id="map-feedback-layer"></div>' +
                        '</div>' +
                        '<div class="map-stage-overlay-layer" id="map-stage-overlay-layer"></div>' +
                        '<div class="map-stage-scanline" aria-hidden="true"></div>' +
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

        _titleEl = _el.querySelector('#map-panel-region');
        _bodyEl = _el.querySelector('.map-panel-body');
        _stageEl = _el.querySelector('#map-stage-frame');
        _backdropEl = _el.querySelector('#map-stage-backdrop');
        _filterOverlayEl = _el.querySelector('#map-stage-filter-overlay');
        _anomalyEl = _el.querySelector('#map-stage-anomaly');
        _contentFitEl = _el.querySelector('#map-stage-content-fit');
        _imageEl = _el.querySelector('#map-stage-image');
        _sceneLayer = _el.querySelector('#map-scene-layer');
        _hotspotLayer = _el.querySelector('#map-hotspot-layer');
        _avatarLayer = _el.querySelector('#map-dynamic-avatar-layer');
        _feedbackLayer = _el.querySelector('#map-feedback-layer');
        _overlayLayer = _el.querySelector('#map-stage-overlay-layer');
        _stageShellEl = _el.querySelector('#map-stage-shell');
        _railEl = _el.querySelector('#map-rail-shell');
        _loadingEl = _el.querySelector('#map-stage-loading');
        _errorEl = _el.querySelector('#map-stage-error');
        _errorTextEl = _el.querySelector('#map-stage-error-text');
        _badgeEl = _el.querySelector('#map-panel-badge');
        _pageTabsEl = _el.querySelector('#map-page-tabs');
        _pageSummaryEl = _el.querySelector('#map-page-summary');

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
            btn.textContent = page.tabLabel;
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
        _snapshotMarkers = [];
        _snapshotTips = [];
        _currentHotspotId = '';
        _hoverHotspotId = '';
        _busyLookup = {};
        _debugTelemetryEnabled = !!(initData && initData.dev);
        _snapshotAnnounced = false;
        resetContentFit();
        if (_el) _el.classList.remove('is-compact');

        _badgeEl.style.display = initData && initData.dev ? '' : 'none';

        if (_el) {
            _el.classList.remove('is-entering');
            // 强制回流后加 class, 保证 CSS 动画重新播放
            void _el.offsetWidth;
            _el.classList.add('is-entering');
        }

        initLayoutWatcher();
        hideError();
        setLoading(true);
        applyPage((initData && (initData.page || initData.region)) || 'base');
        requestSnapshot('snapshot');
        scheduleSettledLayoutSync();
        playCue('modalOpen');
    }

    function onForceClose() {
        // teardownLayoutWatcher 已由 Panels.close() 经 onClose 钩子触发，此处只做状态复位。
        _closing = false;
        _pendingReq = {};
        _enabledLookup = {};
        _hotspotStateLookup = {};
        _unlockFlags = {};
        _pageFilterState = {};
        _dynamicAvatarState = {};
        _snapshotMarkers = [];
        _snapshotTips = [];
        _currentHotspotId = '';
        _hoverHotspotId = '';
        _busyLookup = {};
        _debugTelemetryEnabled = false;
        _stageScale = 1;
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
    }

    function applyPage(pageId) {
        _activePage = MapPanelData.getPage(pageId);
        _hoverHotspotId = '';
        ensurePageFilterState(_activePage);
        _titleEl.textContent = _activePage.title;
        _stageEl.style.aspectRatio = _activePage.width + ' / ' + _activePage.height;
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
        var backdropTheme = _activePage && _activePage.backdropTheme ? _activePage.backdropTheme : 'default';
        var activeViewMode = getActiveViewMode(_activePage);
        var activeFilter = _activePage ? getActiveFilter(_activePage) : null;
        var activeFilterId = activeFilter ? activeFilter.id : '';
        _stageEl.classList.toggle('is-assembled', useAssembledVisuals(_activePage));
        _stageEl.classList.toggle('is-layer-relation', activeViewMode === 'hierarchy');
        _stageEl.setAttribute('data-page-id', _activePage ? _activePage.id : '');
        _stageEl.setAttribute('data-active-filter', activeFilterId);
        _backdropEl.className = 'map-stage-backdrop map-stage-backdrop--' + backdropTheme;
        if (_filterOverlayEl) {
            _filterOverlayEl.setAttribute('data-active-filter', activeFilterId);
            _filterOverlayEl.setAttribute('data-page-id', _activePage ? _activePage.id : '');
        }
        if (_anomalyEl) {
            // 禁区异常层: defense + restricted filter 时显示; 其它场景隐藏
            var isAnomaly = _activePage && _activePage.id === 'defense' && activeFilterId === 'restricted';
            _anomalyEl.classList.toggle('is-active', !!isAnomaly);
        }
    }

    function triggerFilterRetune() {
        if (!_stageEl) return;
        _stageEl.classList.remove('is-retuning');
        // force reflow 以重启动画
        void _stageEl.offsetWidth;
        _stageEl.classList.add('is-retuning');
    }

    function renderStageImage() {
        var hasBackground = !!(_activePage && _activePage.backgroundUrl);
        var hideImage = useAssembledVisuals(_activePage);

        _imageEl.classList.toggle('is-hidden', !hasBackground || hideImage);
        _imageEl.width = _activePage.width;
        _imageEl.height = _activePage.height;

        if (hasBackground) {
            _imageEl.src = resolveAssetUrl(_activePage.backgroundUrl);
            return;
        }

        _imageEl.removeAttribute('src');
    }

    function updatePageTabs() {
        var btns = _pageTabsEl.querySelectorAll('.map-page-tab');
        for (var i = 0; i < btns.length; i++) {
            var btn = btns[i];
            var isActive = _activePage && btn.getAttribute('data-page-id') === _activePage.id;
            btn.classList.toggle('is-active', isActive);
        }
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
        if (!_activePage || !_sceneLayer) return;

        var visuals = getVisibleSceneVisuals(_activePage);
        _sceneLayer.innerHTML = '';

        for (var i = 0; i < visuals.length; i++) {
            var visual = visuals[i];
            if (!visual || !visual.rect || !visual.assetUrl) continue;

            var rect = visual.rect;
            var assetUrl = resolveAssetUrl(visual.assetUrl);
            var node = document.createElement('div');
            node.className = 'map-scene-node';
            node.setAttribute('data-scene-node-id', visual.id);
            node.setAttribute('data-hotspot-ids', (visual.hotspotIds || []).join(' '));
            node.style.left = toPercent(rect.x, _activePage.width);
            node.style.top = toPercent(rect.y, _activePage.height);
            node.style.width = toPercent(rect.w, _activePage.width);
            node.style.height = toPercent(rect.h, _activePage.height);
            node.title = visual.label || visual.id;
            node.innerHTML =
                '<img class="map-scene-node-image" alt="" src="' + escAttr(assetUrl) + '">' +
                '<span class="map-scene-node-glow"></span>';
            _sceneLayer.appendChild(node);
        }

        syncSceneNodeStates();
    }

    function getVisibleSceneVisuals(page) {
        if (!page) return [];
        var activeFilter = getActiveFilter(page);
        return MapPanelData.getVisibleSceneVisuals(page.id, activeFilter ? activeFilter.id : '');
    }

    function syncSceneNodeStates() {
        if (!_sceneLayer) return;

        var nodes = _sceneLayer.querySelectorAll('.map-scene-node');
        var activeViewMode = getActiveViewMode(_activePage);
        var focusHotspotId = getFocusHotspotId(_activePage);
        for (var i = 0; i < nodes.length; i++) {
            var hotspotIds = getNodeHotspotIds(nodes[i]);
            var enabledCount = countEnabledIds(hotspotIds);
            var isCurrent = containsHotspotId(hotspotIds, _currentHotspotId);
            var isHover = containsHotspotId(hotspotIds, _hoverHotspotId);
            var isBusy = hasBusyHotspot(hotspotIds);
            var isLocked = hotspotIds.length ? enabledCount === 0 : false;
            var isFocused = containsHotspotId(hotspotIds, focusHotspotId);
            var isMuted = !!focusHotspotId && !isFocused;

            nodes[i].classList.toggle('is-disabled', isLocked);
            nodes[i].classList.toggle('is-current', isCurrent);
            nodes[i].classList.toggle('is-hover', isHover);
            nodes[i].classList.toggle('is-busy', isBusy);
            nodes[i].classList.toggle('is-muted', isMuted);
            nodes[i].classList.toggle('is-emphasis', !!focusHotspotId && isFocused);
            nodes[i].classList.toggle('is-relationship', activeViewMode === 'hierarchy');
        }
    }

    function getNodeHotspotIds(node) {
        var raw = node ? (node.getAttribute('data-hotspot-ids') || '') : '';
        return raw ? raw.split(/\s+/).filter(Boolean) : [];
    }

    function containsHotspotId(hotspotIds, hotspotId) {
        return !!(hotspotId && hotspotIds && hotspotIds.indexOf(hotspotId) >= 0);
    }

    function hasBusyHotspot(hotspotIds) {
        if (!hotspotIds || !hotspotIds.length) return false;
        for (var i = 0; i < hotspotIds.length; i++) {
            if (_busyLookup[hotspotIds[i]]) return true;
        }
        return false;
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
        _snapshotMarkers = [];
        _snapshotTips = [];
        _currentHotspotId = '';
        _hoverHotspotId = '';
        _busyLookup = {};
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

        var targetPageId = snapshot.defaultPageId || resolvePageIdForHotspot(_currentHotspotId) || (_activePage ? _activePage.id : '');
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
            var btn = document.createElement('button');

            btn.className = 'map-hotspot' + (enabled ? '' : ' is-disabled') + (_currentHotspotId === hotspot.id ? ' is-current' : '');
            btn.type = 'button';
            btn.setAttribute('data-hotspot-id', hotspot.id);
            btn.setAttribute('data-audio-cue', enabled ? 'transition' : 'error');
            btn.style.left = toPercent(rect.x, _activePage.width);
            btn.style.top = toPercent(rect.y, _activePage.height);
            btn.style.width = toPercent(rect.w, _activePage.width);
            btn.style.height = toPercent(rect.h, _activePage.height);
            btn.setAttribute('aria-disabled', enabled ? 'false' : 'true');
            if (!enabled && hotspotState.lockedReason) {
                btn.setAttribute('data-locked-reason', hotspotState.lockedReason);
                btn.title = hotspotState.lockedReason;
            } else {
                btn.title = hotspot.label;
            }
            btn.innerHTML =
                '<span class="map-hotspot-sheen"></span>' +
                '<span class="map-hotspot-label">' + escHtml(hotspot.label) + '</span>';

            attachHotspotHandler(btn, hotspot);
            _hotspotLayer.appendChild(btn);
        }

        syncHotspotStates();
    }

    function attachHotspotHandler(btn, hotspot) {
        btn.addEventListener('click', function() {
            requestNavigate(hotspot);
        });
        btn.addEventListener('mouseenter', function() {
            setHotspotHover(hotspot.id, true);
        });
        btn.addEventListener('mouseleave', function() {
            setHotspotHover(hotspot.id, false);
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
            var btn = document.createElement('button');
            btn.className = 'map-filter-hotspot';
            btn.type = 'button';
            btn.setAttribute('data-filter-id', filter.id);
            btn.setAttribute('data-audio-cue', isLocked ? 'error' : 'select');
            btn.setAttribute('title', buildFilterTitle(filter, enabledCount, filterMeta, isLocked));
            btn.setAttribute('aria-label', filter.label);
            btn.classList.toggle('is-active', !!activeFilter && activeFilter.id === filter.id);
            btn.classList.toggle('is-empty', enabledCount === 0);
            btn.classList.toggle('is-locked', isLocked);
            btn.innerHTML =
                '<span class="map-filter-hotspot-chrome"></span>' +
                '<span class="map-filter-hotspot-label">' + escHtml(filter.label) + '</span>' +
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
            var item = document.createElement('button');
            item.className = 'map-rail-scene-item';
            item.type = 'button';
            item.setAttribute('data-hotspot-id', hotspotId);
            item.setAttribute('data-audio-cue', enabled ? 'transition' : 'error');
            item.classList.toggle('is-current', isCurrent);
            item.classList.toggle('is-disabled', !enabled);
            if (!enabled && state.lockedReason) {
                item.setAttribute('data-locked-reason', state.lockedReason);
                item.setAttribute('title', state.lockedReason);
            } else {
                item.setAttribute('title', hotspot.label);
            }
            item.setAttribute('aria-disabled', enabled ? 'false' : 'true');
            item.innerHTML =
                '<span class="map-rail-scene-dot" aria-hidden="true"></span>' +
                '<span class="map-rail-scene-label">' + escHtml(hotspot.label) + '</span>';
            attachSceneItemHandler(item, hotspot);
            list.appendChild(item);
        }
        return list;
    }

    function attachSceneItemHandler(item, hotspot) {
        item.addEventListener('click', function() {
            // 复用 requestNavigate: enabled 走 transition + 导航; disabled 推 toast 原因; busy 去重
            requestNavigate(hotspot);
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
        if (!_activePage || !_avatarLayer) return;

        var visibleLookup = buildVisibleLookup(_activePage);
        _avatarLayer.innerHTML = '';

        renderAvatarTaskMarkers(visibleLookup);
        renderStaticAvatars(visibleLookup);
        renderDynamicAvatars(visibleLookup);
        syncAvatarStates();
    }

    function renderAvatarTaskMarkers(visibleLookup) {
        for (var i = 0; i < _snapshotMarkers.length; i++) {
            var marker = _snapshotMarkers[i];
            if (!marker || marker.kind !== 'taskNpc') continue;
            if (marker.pageId && marker.pageId !== _activePage.id) continue;
            if (marker.hotspotId && !visibleLookup[marker.hotspotId]) continue;

            var anchor = findAvatarAnchorForMarker(marker, visibleLookup) || resolveFeedbackAnchor(marker);
            if (!anchor) continue;

            var ring = document.createElement('div');
            ring.className = 'map-avatar-task-ring';
            ring.setAttribute('data-hotspot-id', marker.hotspotId || '');
            ring.style.left = toPercent(anchor.x, _activePage.width);
            ring.style.top = toPercent(anchor.y, _activePage.height);
            _avatarLayer.appendChild(ring);
        }
    }

    function renderStaticAvatars(visibleLookup) {
        var slots = _activePage.staticAvatars || [];

        for (var i = 0; i < slots.length; i++) {
            var slot = slots[i];
            if (slot.hotspotId && !visibleLookup[slot.hotspotId]) continue;
            if (!slot.assetUrl) continue;
            var rect = resolveStaticAvatarRect(slot);

            var avatar = document.createElement('div');
            avatar.className = 'map-avatar map-static-avatar';
            avatar.setAttribute('data-avatar-id', slot.id || '');
            avatar.setAttribute('data-hotspot-id', slot.hotspotId || '');
            avatar.title = slot.label || '';
            avatar.style.left = toPercent(rect.x, _activePage.width);
            avatar.style.top = toPercent(rect.y, _activePage.height);
            avatar.style.width = toPercent(rect.w, _activePage.width);
            avatar.style.height = toPercent(rect.h, _activePage.height);
            appendAvatarImage(avatar, slot.assetUrl, slot.label || '');
            _avatarLayer.appendChild(avatar);
        }
    }

    function resolveStaticAvatarRect(slot) {
        if (typeof MapAvatarSourceData !== 'undefined' && MapAvatarSourceData && MapAvatarSourceData.getByAssetUrl) {
            var sourceSlot = MapAvatarSourceData.getByAssetUrl(slot.assetUrl || '');
            if (sourceSlot && sourceSlot.rect) {
                return sourceSlot.rect;
            }
        }

        return {
            x: slot.x,
            y: slot.y,
            w: slot.w,
            h: slot.h
        };
    }

    function renderDynamicAvatars(visibleLookup) {
        var slots = _activePage.dynamicAvatars || [];

        for (var i = 0; i < slots.length; i++) {
            var slot = slots[i];
            if (slot.hotspotId && !visibleLookup[slot.hotspotId]) continue;

            var assetUrl = resolveDynamicAvatarUrl(slot);
            if (!assetUrl) continue;

            var avatar = document.createElement('div');
            avatar.className = 'map-avatar map-dynamic-avatar map-dynamic-avatar--' + slot.kind;
            avatar.setAttribute('data-hotspot-id', slot.hotspotId || '');
            avatar.style.left = toPercent(slot.x, _activePage.width);
            avatar.style.top = toPercent(slot.y, _activePage.height);
            avatar.style.width = toPercent(slot.w, _activePage.width);
            avatar.style.height = toPercent(slot.h, _activePage.height);
            appendAvatarImage(avatar, assetUrl, slot.id || '', 'map-dynamic-avatar-image');
            _avatarLayer.appendChild(avatar);
        }
    }

    function appendAvatarImage(container, assetUrl, fallbackLabel, extraClass) {
        var image = document.createElement('img');
        image.className = 'map-avatar-image';
        if (extraClass) {
            image.className += ' ' + extraClass;
        }
        image.alt = '';
        image.src = resolveAssetUrl(assetUrl);
        image.addEventListener('error', function onError() {
            image.removeEventListener('error', onError);
            container.classList.add('is-missing');
            if (image.parentNode === container) {
                container.removeChild(image);
            }
            if (container.querySelector('.map-avatar-fallback')) return;

            var fallback = document.createElement('span');
            fallback.className = 'map-avatar-fallback';
            fallback.textContent = buildAvatarFallbackLabel(fallbackLabel);
            container.appendChild(fallback);
        });
        container.appendChild(image);
    }

    function buildAvatarFallbackLabel(label) {
        if (!label) return '?';
        return String(label).trim().charAt(0) || '?';
    }

    function renderFeedback() {
        if (!_activePage) return;

        _feedbackLayer.innerHTML = '';
        if (_overlayLayer) _overlayLayer.innerHTML = '';

        renderFlashHints(MapPanelData.getPageFlashHints(_activePage.id));
        renderFeedbackMarkers(_snapshotMarkers);
        renderFeedbackTips(_snapshotTips);
    }

    function renderFlashHints(hints) {
        var target = _overlayLayer || _feedbackLayer;
        if (!target) return;

        for (var i = 0; i < hints.length; i++) {
            var hint = hints[i];
            if (!shouldRenderFlashHint(hint)) continue;

            var anchor = resolveFlashHintAnchor(hint);
            if (!anchor) continue;

            var el = document.createElement('div');
            el.className = 'map-feedback-hint' + (hint.kind ? ' map-feedback-hint--' + hint.kind : '');
            el.style.left = toPercent(anchor.x, _activePage.width);
            el.style.top = toPercent(anchor.y, _activePage.height);
            el.textContent = hint.label || '未开放';
            target.appendChild(el);
        }
    }

    function renderFeedbackMarkers(markers) {
        for (var i = 0; i < markers.length; i++) {
            var marker = markers[i];
            if (marker && marker.kind === 'taskNpc') continue;
            if (!shouldRenderFeedbackItem(marker)) continue;

            var anchor = resolveFeedbackAnchor(marker);
            if (!anchor) continue;

            var el = document.createElement('div');
            el.className = 'map-feedback-marker' + (marker.kind ? ' map-feedback-marker--' + marker.kind : '');
            el.style.left = toPercent(anchor.x, _activePage.width);
            el.style.top = toPercent(anchor.y, _activePage.height);
            // 标记只留点 + 雷达扫针，文字描述交给 tips 层，避免和 tip "当前位置" 叠字
            _feedbackLayer.appendChild(el);
        }
    }

    function renderFeedbackTips(tips) {
        for (var i = 0; i < tips.length; i++) {
            var tip = tips[i];
            if (!shouldRenderFeedbackItem(tip)) continue;

            var anchor = resolveFeedbackAnchor(tip);
            if (!anchor) continue;

            var el = document.createElement('div');
            el.className = 'map-feedback-tip' + (tip.tone ? ' is-' + tip.tone : '');
            el.style.left = toPercent(anchor.x, _activePage.width);
            el.style.top = toPercent(anchor.y, _activePage.height);
            el.textContent = tip.label || '提示';
            _feedbackLayer.appendChild(el);
        }
    }

    function shouldRenderFeedbackItem(item) {
        if (!item) return false;

        var pageId = item.pageId || resolvePageIdForHotspot(item.hotspotId);
        if (pageId && _activePage.id !== pageId) return false;

        var visibleLookup = buildVisibleLookup(_activePage);
        if (item.hotspotId && !visibleLookup[item.hotspotId]) return false;

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

            var keys = getSlotNpcKeys(slot);
            for (var j = 0; j < keys.length; j++) {
                if (keys[j] && keys[j] === npcKey) {
                    var rect = rectResolver(slot);
                    return {
                        x: rect.x + (rect.w / 2),
                        y: rect.y + (rect.h / 2)
                    };
                }
            }
        }

        return null;
    }

    function resolveDynamicAvatarRect(slot) {
        return { x: slot.x, y: slot.y, w: slot.w, h: slot.h };
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

        var previousFilterId = _pageFilterState[_activePage.id];
        _pageFilterState[_activePage.id] = filter.id;
        if (previousFilterId && previousFilterId !== filter.id) {
            // 「频段重调」过渡: 仅在真正切 filter 时触发, 首次/相同不重放
            triggerFilterRetune();
        }
        renderStageBackdrop();
        renderAvatars();
        renderSceneVisuals();
        renderHotspots();
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
            if (!hotspotState.enabled && hotspotState.lockedReason) {
                buttons[i].title = hotspotState.lockedReason;
            }
        }

        syncRailSceneItemStates();
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
    }

    function syncAvatarStates() {
        if (!_avatarLayer) return;

        var focusHotspotId = getFocusHotspotId(_activePage);
        var avatars = _avatarLayer.querySelectorAll('.map-avatar');
        for (var i = 0; i < avatars.length; i++) {
            var hotspotId = avatars[i].getAttribute('data-hotspot-id') || '';
            avatars[i].classList.toggle('is-current', !!hotspotId && hotspotId === _currentHotspotId);
            avatars[i].classList.toggle('is-focus', !!focusHotspotId && hotspotId === focusHotspotId);
            avatars[i].classList.toggle('is-muted', !!focusHotspotId && !!hotspotId && hotspotId !== focusHotspotId);
        }
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
    }

    function measureContentBounds(stageRect) {
        if (!_contentFitEl || !stageRect) return null;

        var nodes = _contentFitEl.querySelectorAll('.map-scene-node, .map-hotspot, .map-avatar, .map-avatar-task-ring, .map-feedback-marker, .map-feedback-tip');
        var minX = Infinity;
        var minY = Infinity;
        var maxX = -Infinity;
        var maxY = -Infinity;
        var i;

        for (i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            var style = (typeof window !== 'undefined' && window.getComputedStyle) ? window.getComputedStyle(node) : null;
            var rect;
            if (!node || !node.getBoundingClientRect) continue;
            if (style && (style.display === 'none' || style.visibility === 'hidden')) continue;

            rect = node.getBoundingClientRect();
            if (!rect || (rect.width <= 0 && rect.height <= 0)) continue;

            minX = Math.min(minX, rect.left - stageRect.left);
            minY = Math.min(minY, rect.top - stageRect.top);
            maxX = Math.max(maxX, rect.right - stageRect.left);
            maxY = Math.max(maxY, rect.bottom - stageRect.top);
        }

        if (!isFinite(minX) || !isFinite(minY) || !isFinite(maxX) || !isFinite(maxY)) {
            return null;
        }

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
        var bounds = measureContentBounds(stageRect);
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
        scheduleLayoutSync(layoutReason);
        scheduleSettledLayoutSync(layoutReason + ':settled');
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

    function escAttr(s) {
        return escHtml(s).replace(/"/g, '&quot;');
    }

    function getDebugState() {
        var hotspots = _activePage ? getVisibleHotspots(_activePage) : [];
        var activeFilter = _activePage ? getActiveFilter(_activePage) : null;
        var visibleHotspotIds = [];
        var enabledHotspotIds = [];
        var lockedHotspotIds = [];
        var i;

        for (i = 0; i < hotspots.length; i++) {
            visibleHotspotIds.push(hotspots[i].id);
            if (_enabledLookup[hotspots[i].id]) {
                enabledHotspotIds.push(hotspots[i].id);
            } else {
                lockedHotspotIds.push(hotspots[i].id);
            }
        }

        return {
            isOpen: Panels.isOpen(),
            activePageId: _activePage ? _activePage.id : null,
            activeFilterId: activeFilter ? activeFilter.id : null,
            title: _titleEl ? _titleEl.textContent : '',
            summary: _pageSummaryEl ? _pageSummaryEl.textContent : '',
            loadingVisible: !!(_loadingEl && _loadingEl.style.display !== 'none'),
            errorVisible: !!(_errorEl && _errorEl.style.display !== 'none'),
            errorText: _errorTextEl ? _errorTextEl.textContent : '',
            visibleHotspotIds: visibleHotspotIds,
            enabledHotspotIds: enabledHotspotIds,
            lockedHotspotIds: lockedHotspotIds,
            dynamicAvatarState: _dynamicAvatarState,
            unlockFlags: _unlockFlags,
            currentHotspotId: _currentHotspotId,
            focusHotspotId: getFocusHotspotId(_activePage),
            activeViewMode: getActiveViewMode(_activePage),
            renderMode: _activePage && _activePage.renderMode ? _activePage.renderMode : 'background',
            sceneVisualCount: _sceneLayer ? _sceneLayer.querySelectorAll('.map-scene-node').length : 0,
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
            tipIds: (_snapshotTips || []).map(function(item) { return item.id; })
        };
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
