var StageSelectPanel = (function() {
    'use strict';

    var DESIGN_W = 1024;
    var DESIGN_H = 576;
    var _el;
    var _stageEl;
    var _backgroundEl;
    var _buttonLayerEl;
    var _navLayerEl;
    var _tabsEl;
    var _summaryEl;
    var _badgeEl;
    var _logEl;
    var _fixtureSelectEl;
    var _frameToggleEl;
    var _frameToggleLabelEl;
    var _frameToggleCounterEl;
    var _currentFrameLabel = '';
    var _returnFrameLabel = '';
    var _fixtureName = 'mixed';
    var _fixture = null;
    var _lastDifficultyClick = null;
    var _runtimeSnapshot = null;
    var _pendingReq = {};
    var _reqSeq = 0;
    var _session = 0;
    var _mode = 'dev';
    var _busyStageName = '';
    var _lastError = '';
    var _frameMenuOpen = false;
    var _layoutObserver = null;
    var _resizeHandler = null;

    Panels.register('stage-select', {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: requestClose,
        onClose: onClose
    });

    function createDOM() {
        _el = document.createElement('div');
        _el.className = 'stage-select-panel';
        _el.innerHTML =
            '<div class="stage-select-header">' +
                '<div class="stage-select-heading">' +
                    '<span class="stage-select-title">选关测试</span>' +
                    '<button class="stage-select-frame-toggle" id="stage-select-frame-toggle" type="button" aria-expanded="false" aria-haspopup="listbox" title="切换区域" data-audio-cue="confirm">' +
                        '<span class="stage-select-frame-toggle-label" id="stage-select-frame-toggle-label"></span>' +
                        '<span class="stage-select-frame-toggle-counter" id="stage-select-frame-toggle-counter" aria-hidden="true"></span>' +
                        '<span class="stage-select-frame-toggle-icon" aria-hidden="true">▾</span>' +
                    '</button>' +
                    '<span class="stage-select-region" id="stage-select-region"></span>' +
                '</div>' +
                '<div class="stage-select-tabs" id="stage-select-tabs"></div>' +
                '<div class="stage-select-tools">' +
                    '<label class="stage-select-fixture-label">fixture</label>' +
                    '<select id="stage-select-fixture">' +
                        '<option value="mixed">mixed</option>' +
                        '<option value="allUnlocked">allUnlocked</option>' +
                        '<option value="challenge">challenge</option>' +
                    '</select>' +
                    '<span class="stage-select-badge" id="stage-select-badge">DEV</span>' +
                    '<button class="stage-select-close-btn" type="button" title="关闭" aria-label="关闭" data-audio-cue="cancel">✕</button>' +
                '</div>' +
            '</div>' +
            '<div class="stage-select-body">' +
                '<div class="stage-select-stage-shell" id="stage-select-stage-shell">' +
                    '<div class="stage-select-stage" id="stage-select-stage">' +
                        '<img class="stage-select-bg" id="stage-select-bg" alt="选关背景">' +
                        '<div class="stage-select-nav-layer" id="stage-select-nav-layer"></div>' +
                        '<div class="stage-select-button-layer" id="stage-select-button-layer"></div>' +
                    '</div>' +
                '</div>' +
                '<div class="stage-select-side">' +
                    '<div class="stage-select-side-title">静态复刻</div>' +
                    '<div class="stage-select-summary" id="stage-select-summary"></div>' +
                    '<div class="stage-select-dev-log" id="stage-select-dev-log">等待交互</div>' +
                '</div>' +
            '</div>';

        _stageEl = _el.querySelector('#stage-select-stage');
        _backgroundEl = _el.querySelector('#stage-select-bg');
        _buttonLayerEl = _el.querySelector('#stage-select-button-layer');
        _navLayerEl = _el.querySelector('#stage-select-nav-layer');
        _tabsEl = _el.querySelector('#stage-select-tabs');
        _summaryEl = _el.querySelector('#stage-select-summary');
        _badgeEl = _el.querySelector('#stage-select-badge');
        _logEl = _el.querySelector('#stage-select-dev-log');
        _fixtureSelectEl = _el.querySelector('#stage-select-fixture');
        _frameToggleEl = _el.querySelector('#stage-select-frame-toggle');
        _frameToggleLabelEl = _el.querySelector('#stage-select-frame-toggle-label');
        _frameToggleCounterEl = _el.querySelector('#stage-select-frame-toggle-counter');

        _el.querySelector('.stage-select-close-btn').addEventListener('click', requestClose);
        _frameToggleEl.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            var willOpen = !_frameMenuOpen;
            setFrameMenuOpen(willOpen);
            if (willOpen) focusActiveFrameTab();
        });
        _frameToggleEl.addEventListener('keydown', handleFrameToggleKey);
        _tabsEl.addEventListener('click', function(e) {
            e.stopPropagation();
        });
        _tabsEl.addEventListener('keydown', handleFrameMenuKey);
        _el.addEventListener('click', function(e) {
            if (!_frameMenuOpen || !isRuntimeMode()) return;
            if (isWithin(e.target, _frameToggleEl) || isWithin(e.target, _tabsEl)) return;
            setFrameMenuOpen(false);
        });
        _el.addEventListener('keydown', function(e) {
            if (e.key === 'Escape' && _frameMenuOpen && isRuntimeMode()) {
                e.preventDefault();
                setFrameMenuOpen(false);
                if (_frameToggleEl) _frameToggleEl.focus();
            }
        });
        _fixtureSelectEl.addEventListener('change', function() {
            setFixture(_fixtureSelectEl.value);
            renderCurrentFrame();
        });
        _buttonLayerEl.addEventListener('click', handleDifficultyClick);

        initLayoutWatcher();
        renderTabs();
        return _el;
    }

    function onOpen(root, initData) {
        var manifest = StageSelectData.getManifest();
        _session += 1;
        _pendingReq = {};
        _runtimeSnapshot = null;
        _busyStageName = '';
        _lastError = '';
        _mode = initData && initData.mode || 'dev';
        DESIGN_W = manifest.designSize && manifest.designSize.width || 1024;
        DESIGN_H = manifest.designSize && manifest.designSize.height || 576;
        _fixtureName = initData && initData.fixture || 'mixed';
        _currentFrameLabel = initData && initData.frameLabel || initData && initData.page || manifest.frameOrder[0];
        _returnFrameLabel = initData && initData.returnFrameLabel || _currentFrameLabel;
        setFixture(_fixtureName);
        if (_fixtureSelectEl) _fixtureSelectEl.value = _fixtureName;
        if (_el) _el.classList.toggle('is-runtime', isRuntimeMode());
        setFrameMenuOpen(false);
        _lastDifficultyClick = null;
        renderTabs();
        initLayoutWatcher();
        renderCurrentFrame();
        requestSnapshot();
        syncStageLayout();
        root.classList.remove('is-entered');
        setTimeout(function() { if (root) root.classList.add('is-entered'); }, 20);
    }

    function setFixture(name) {
        _fixtureName = name || 'mixed';
        _fixture = StageSelectData.getFixture(_fixtureName);
        if (_badgeEl) _badgeEl.textContent = _fixture && _fixture.challenge ? 'CHALLENGE' : 'DEV';
    }

    function renderTabs() {
        if (!_tabsEl || !window.StageSelectData) return;
        var manifest = StageSelectData.getManifest();
        _tabsEl.setAttribute('role', 'listbox');
        _tabsEl.innerHTML = '';
        manifest.frameOrder.forEach(function(label, index) {
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'stage-select-tab';
            button.setAttribute('data-frame-label', label);
            button.setAttribute('data-frame-index', String(index));
            button.setAttribute('role', 'option');
            button.tabIndex = -1;
            button.textContent = label;
            button.addEventListener('click', function() {
                selectFrameTab(label);
            });
            _tabsEl.appendChild(button);
        });
    }

    function selectFrameTab(label) {
        var sourceFrameLabel = _currentFrameLabel;
        setFrame(label, 'tab');
        if (isRuntimeMode() && label !== sourceFrameLabel) {
            requestJumpFrame(label, { id: 'tab:' + label }, sourceFrameLabel);
        }
        setFrameMenuOpen(false);
        if (_frameToggleEl) _frameToggleEl.focus();
    }

    function focusActiveFrameTab() {
        if (!_tabsEl) return;
        var active = _tabsEl.querySelector('.stage-select-tab.is-active');
        if (!active) active = _tabsEl.querySelector('.stage-select-tab');
        if (active) active.focus();
    }

    function handleFrameToggleKey(e) {
        if (!isRuntimeMode()) return;
        if (e.key === 'ArrowDown' || e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            if (!_frameMenuOpen) setFrameMenuOpen(true);
            focusActiveFrameTab();
        } else if (e.key === 'Escape' && _frameMenuOpen) {
            e.preventDefault();
            setFrameMenuOpen(false);
        }
    }

    function handleFrameMenuKey(e) {
        if (!_frameMenuOpen || !_tabsEl) return;
        var nodes = _tabsEl.querySelectorAll('.stage-select-tab');
        if (!nodes.length) return;
        var current = document.activeElement;
        var idx = -1;
        for (var i = 0; i < nodes.length; i += 1) {
            if (nodes[i] === current) { idx = i; break; }
        }
        var next = idx;
        switch (e.key) {
            case 'ArrowRight':
            case 'ArrowDown':
                next = idx < 0 ? 0 : (idx + 1) % nodes.length;
                break;
            case 'ArrowLeft':
            case 'ArrowUp':
                next = idx < 0 ? 0 : (idx - 1 + nodes.length) % nodes.length;
                break;
            case 'Home':
                next = 0;
                break;
            case 'End':
                next = nodes.length - 1;
                break;
            case 'Enter':
            case ' ':
                if (idx >= 0) {
                    e.preventDefault();
                    selectFrameTab(nodes[idx].getAttribute('data-frame-label'));
                }
                return;
            case 'Escape':
                e.preventDefault();
                setFrameMenuOpen(false);
                if (_frameToggleEl) _frameToggleEl.focus();
                return;
            default:
                return;
        }
        e.preventDefault();
        nodes[next].focus();
    }

    function setFrame(label, source) {
        if (!StageSelectData.getFrame(label)) return;
        _currentFrameLabel = label;
        logDev((source || 'route') + ': ' + label);
        renderCurrentFrame();
    }

    function renderCurrentFrame() {
        var frame = StageSelectData.getFrame(_currentFrameLabel);
        if (!frame) return;
        _currentFrameLabel = frame.frameLabel;
        renderHeader(frame);
        renderBackground(frame);
        renderStageButtons(frame);
        renderNavButtons(frame);
        syncStageLayout();
    }

    function renderHeader(frame) {
        var tabs = _tabsEl ? _tabsEl.querySelectorAll('.stage-select-tab') : [];
        var activeIndex = -1;
        for (var i = 0; i < tabs.length; i += 1) {
            var isActive = tabs[i].getAttribute('data-frame-label') === frame.frameLabel;
            tabs[i].classList.toggle('is-active', isActive);
            tabs[i].setAttribute('aria-selected', isActive ? 'true' : 'false');
            if (isActive) activeIndex = i;
        }
        var region = _el.querySelector('#stage-select-region');
        if (region) region.textContent = frame.frameLabel;
        if (_frameToggleLabelEl) _frameToggleLabelEl.textContent = frame.frameLabel;
        if (_frameToggleCounterEl) {
            _frameToggleCounterEl.textContent = tabs.length
                ? (activeIndex >= 0 ? (activeIndex + 1) : 1) + '/' + tabs.length
                : '';
        }
        if (_summaryEl) {
            _summaryEl.innerHTML =
                '<div>frame: <b>' + escapeHtml(frame.frameLabel) + '</b></div>' +
                '<div>decorations: <b>' + (frame.decorations || []).length + '</b></div>' +
                '<div>stage buttons: <b>' + (frame.stageButtons || []).length + '</b></div>' +
                '<div>nav buttons: <b>' + (frame.navButtons || []).length + '</b></div>' +
                '<div>background: <b>' + escapeHtml(frame.background && frame.background.mode || 'missing') + '</b></div>' +
                '<div>fixture: <b>' + escapeHtml(_fixtureName) + '</b></div>' +
                '<div>runtime: <b>' + (_runtimeSnapshot ? 'live' : 'fixture') + '</b></div>' +
                (_lastError ? '<div class="stage-select-error-line">error: <b>' + escapeHtml(_lastError) + '</b></div>' : '');
        }
    }

    function renderBackground(frame) {
        var bg = frame.background || {};
        if (_backgroundEl) {
            _backgroundEl.src = resolveAssetUrl(bg.assetUrl || '');
            _backgroundEl.alt = frame.frameLabel + ' 背景';
            _backgroundEl.setAttribute('data-mode', bg.mode || 'missing');
            applyBackgroundRect(bg.rect);
        }
    }

    function applyBackgroundRect(rect) {
        var r = rect || { x: 0, y: 0, w: DESIGN_W, h: DESIGN_H };
        _backgroundEl.style.left = (Number(r.x) || 0) + 'px';
        _backgroundEl.style.top = (Number(r.y) || 0) + 'px';
        _backgroundEl.style.width = (Number(r.w) || DESIGN_W) + 'px';
        _backgroundEl.style.height = (Number(r.h) || DESIGN_H) + 'px';
    }

    function renderStageButtons(frame) {
        _buttonLayerEl.innerHTML = '';
        (frame.decorations || []).forEach(function(item) {
            _buttonLayerEl.appendChild(createDecoration(item));
        });
        (frame.stageButtons || []).forEach(function(button) {
            _buttonLayerEl.appendChild(createStageButton(button));
        });
    }

    function createDecoration(item) {
        var node = document.createElement('span');
        node.className = 'stage-select-decoration';
        node.classList.add('is-' + (item.kind || 'decor'));
        node.classList.add('is-' + (item.variant || 'default'));
        node.setAttribute('data-decoration-id', item.id || '');
        node.setAttribute('data-decoration-kind', item.kind || '');
        node.style.left = (Number(item.x) || 0) + 'px';
        node.style.top = (Number(item.y) || 0) + 'px';
        node.style.width = (Number(item.width) || 0) + 'px';
        node.style.height = (Number(item.height) || 0) + 'px';
        node.innerHTML = '<img class="stage-select-decoration-img" src="' + escapeAttr(resolveAssetUrl(item.assetUrl || '')) + '" alt="" draggable="false">';
        return node;
    }

    function createStageButton(button) {
        var state = getStageState(button.stageName);
        var detail = buildStageDetail(button, state);
        var sizing = computeCardSizing(button, detail);
        var direct = isDirectEntry(button);
        var directSizing = direct ? computeDirectSizing(button) : null;
        var mapLayout = direct && button.entryKind === 'map' && button.directLayout ? buildMapDirectLayout(button.directLayout) : null;
        var displayName = getStageDisplayName(button);
        var node = document.createElement('div');
        node.className = 'stage-select-stage-button';
        if (direct) {
            node.classList.add('is-direct-entry');
            node.classList.add('is-' + (button.entryKind || 'direct') + '-entry');
            node.style.setProperty('--stage-direct-width', directSizing.width + 'px');
            node.style.setProperty('--stage-direct-height', directSizing.height + 'px');
            if (mapLayout) {
                applyMapDirectLayoutVars(node, mapLayout);
            }
        }
        node.tabIndex = 0;
        node.setAttribute('role', 'button');
        node.setAttribute('data-stage-name', button.stageName);
        node.setAttribute('data-stage-id', button.id);
        node.setAttribute('data-entry-kind', button.entryKind || 'difficulty');
        node.setAttribute('data-card-name-lines', String(sizing.nameLines));
        if (mapLayout) {
            node.style.left = (button.x + mapLayout.bounds.x) + 'px';
            node.style.top = (button.y + mapLayout.bounds.y) + 'px';
            node.style.width = mapLayout.bounds.width + 'px';
            node.style.minHeight = mapLayout.bounds.height + 'px';
        } else {
            node.style.left = button.x + 'px';
            node.style.top = button.y + 'px';
        }
        node.style.setProperty('--stage-card-width', sizing.width + 'px');
        node.style.setProperty('--stage-card-height', sizing.cardHeight + 'px');
        if (button.y < 60) node.classList.add('is-edge-top');
        if (button.x < 40) node.classList.add('is-edge-left');
        if (button.x > 790) node.classList.add('is-edge-right');
        if (!state.unlocked) node.classList.add('is-locked');
        if (state.task) node.classList.add('is-task');
        if (_busyStageName && _busyStageName === button.stageName) node.classList.add('is-busy');
        var cardHtml = direct ? '' :
            '<span class="stage-select-card">' +
                '<span class="stage-select-card-corner" aria-hidden="true"></span>' +
                '<span class="stage-select-card-name">' + escapeHtml(displayName) + '</span>' +
                '<span class="stage-select-preview-wrap">' +
                    '<img class="stage-select-preview" src="' + escapeAttr(resolveAssetUrl(button.previewUrl)) + '" alt="' + escapeAttr(displayName) + ' 预览" data-preview-source="' + escapeAttr(button.previewSource || '') + '">' +
                '</span>' +
                '<span class="stage-select-card-detail">' + detail.html + '</span>' +
                '<span class="stage-select-difficulties">' + renderDifficulties(button, state) + '</span>' +
            '</span>';
        node.innerHTML =
            '<span class="stage-select-hit-zone" aria-hidden="true"></span>' +
            renderStageMarkerSvg() +
            '<span class="stage-select-stage-name">' + escapeHtml(displayName) + '</span>' +
            renderStageLockSvg() +
            '<span class="stage-select-task-pulse"></span>' +
            cardHtml;
        node.addEventListener('click', function(e) {
            if (e.target && e.target.classList && e.target.classList.contains('stage-select-difficulty')) return;
            if (direct) {
                if (e.target && e.target.closest && e.target.closest('.stage-select-card')) return;
                requestStageActivation(button, '', null);
                return;
            }
            logDev('select stage: ' + button.stageName + (state.unlocked ? '' : ' (locked fixture)'));
        });
        node.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                if (direct) {
                    requestStageActivation(button, '', null);
                    return;
                }
                logDev('select stage: ' + button.stageName + (state.unlocked ? '' : ' (locked fixture)'));
            }
        });
        return node;
    }

    function isDirectEntry(button) {
        return button && button.entryKind && button.entryKind !== 'difficulty';
    }

    function buildMapDirectLayout(layout) {
        var marker = layout && layout.marker || {};
        var text = layout && layout.text || {};
        var markerX = finiteNumber(marker.x, 0);
        var markerY = finiteNumber(marker.y, 120);
        var textX = finiteNumber(text.x, -68.5);
        var textY = finiteNumber(text.y, 135.7);
        var textW = finiteNumber(text.width, 137);
        var textH = finiteNumber(text.height, 34.3);
        var minX = Math.min(markerX - 22, textX);
        var minY = Math.min(markerY - 22, textY);
        var maxX = Math.max(markerX + 22, textX + textW);
        var maxY = Math.max(markerY + 22, textY + textH);
        return {
            marker: { x: markerX - minX, y: markerY - minY },
            text: { x: textX - minX, y: textY - minY, width: textW, height: textH },
            bounds: {
                x: minX,
                y: minY,
                width: Math.max(1, maxX - minX),
                height: Math.max(1, maxY - minY)
            }
        };
    }

    function applyMapDirectLayoutVars(node, layout) {
        var marker = layout && layout.marker || {};
        var text = layout && layout.text || {};
        node.style.setProperty('--stage-map-marker-x', numericCss(marker.x, 0));
        node.style.setProperty('--stage-map-marker-y', numericCss(marker.y, 120));
        node.style.setProperty('--stage-map-text-x', numericCss(text.x, -68.5));
        node.style.setProperty('--stage-map-text-y', numericCss(text.y, 135.7));
        node.style.setProperty('--stage-map-text-width', numericCss(text.width, 137));
        node.style.setProperty('--stage-map-text-height', numericCss(text.height, 34.3));
    }

    function finiteNumber(value, fallback) {
        var n = Number(value);
        return isFinite(n) ? n : fallback;
    }

    function numericCss(value, fallback) {
        return finiteNumber(value, fallback) + 'px';
    }

    function getStageDisplayName(button) {
        var directText = button && button.directLayout && button.directLayout.text && button.directLayout.text.label || '';
        if ((button && button.entryKind) === 'map' && directText) return directText;
        var name = button && button.stageName || '';
        if ((button && button.entryKind) === 'map' && name.indexOf('外交-') === 0) {
            return name.substr(3);
        }
        return name || '未命名';
    }

    function renderStageMarkerSvg() {
        return '<span class="stage-select-marker" aria-hidden="true">' +
            '<svg class="stage-select-marker-svg" viewBox="-293 -293 586 586" focusable="false">' +
                '<path class="stage-select-marker-fill" fill-rule="evenodd" d="' +
                    'M118 -118 Q167 -69 167 1 Q167 70 118 119 Q69 168 0 168 Q-69 168 -118 119 Q-167 70 -167 1 Q-167 -69 -118 -118 Q-69 -167 0 -166 Q69 -167 118 -118 Z ' +
                    'M168 -167 Q237 -98 237 1 Q237 99 168 168 Q99 238 1 238 Q-98 238 -167 168 Q-237 99 -236 1 Q-237 -98 -167 -167 Q-98 -237 1 -236 Q99 -237 168 -167 Z ' +
                    'M207 -207 Q292 -121 293 1 Q293 122 207 207 Q121 293 0 293 Q-121 293 -207 207 Q-293 122 -292 1 Q-293 -121 -207 -207 Q-121 -292 0 -292 Q121 -292 207 -207 Z' +
                '"/>' +
            '</svg>' +
        '</span>';
    }

    function renderStageLockSvg() {
        return '<span class="stage-select-lock" aria-hidden="true">' +
            '<svg class="stage-select-lock-svg" viewBox="-180 -270 360 540" focusable="false">' +
                '<path class="stage-select-lock-body" fill-rule="evenodd" d="' +
                    'M93 -228 Q131 -190 131 -136 L131 -32 L132 -32 Q178 -32 178 13 L178 222 Q178 267 132 267 L-133 267 Q-178 267 -178 222 L-178 13 Q-178 -32 -133 -32 L-132 -32 L-132 -136 Q-132 -190 -93 -228 Q-55 -267 0 -267 Q54 -267 93 -228 Z ' +
                    'M67 -203 Q95 -175 95 -136 L95 -32 L-96 -32 L-96 -136 Q-96 -175 -68 -203 Q-40 -231 0 -231 Q39 -231 67 -203 Z' +
                '"/>' +
                '<path class="stage-select-lock-hole" d="' +
                    'M13 166 L-14 166 L-14 109 L-30 99 Q-43 86 -43 69 Q-43 51 -30 39 Q-18 26 0 26 Q17 26 30 39 Q42 51 42 69 Q42 86 30 99 L13 109 L13 166 Z' +
                '"/>' +
            '</svg>' +
        '</span>';
    }

    function renderDifficulties(button, state) {
        var difficulties = isChallengeMode() ? ['地狱'] : ['简单', '冒险', '修罗', '地狱'];
        return difficulties.map(function(name) {
            var active = state.task && state.highestDifficulty === name ? ' is-recommended' : '';
            return '<button type="button" class="stage-select-difficulty is-' + difficultyClass(name) + active + '" data-stage-name="' + escapeAttr(button.stageName) + '" data-entry-kind="' + escapeAttr(button.entryKind || 'difficulty') + '" data-difficulty="' + escapeAttr(name) + '">' + escapeHtml(name) + '</button>';
        }).join('');
    }

    function difficultyClass(name) {
        if (name === '简单') return 'easy';
        if (name === '冒险') return 'adventure';
        if (name === '修罗') return 'shura';
        if (name === '地狱') return 'hell';
        return 'unknown';
    }

    function renderNavButtons(frame) {
        _navLayerEl.innerHTML = '';
        (frame.navButtons || []).forEach(function(nav) {
            var visualKind = getNavVisualKind(nav);
            var node = document.createElement('button');
            node.type = 'button';
            node.className = 'stage-select-nav-button is-' + visualKind;
            node.style.left = nav.x + 'px';
            node.style.top = nav.y + 'px';
            node.setAttribute('data-nav-id', nav.id);
            node.setAttribute('data-action-kind', nav.actionKind || '');
            node.setAttribute('data-library-item', nav.libraryItemName || '');
            node.textContent = getNavDisplayLabel(nav, visualKind);
            node.addEventListener('click', function(e) {
                e.stopPropagation();
                if (nav.actionKind === 'localFrame' && nav.targetFrameLabel) {
                    var sourceFrameLabel = _currentFrameLabel;
                    setFrame(nav.targetFrameLabel, 'nav');
                    if (isRuntimeMode()) requestJumpFrame(nav.targetFrameLabel, nav, sourceFrameLabel);
                } else if (isRuntimeMode() && (nav.actionKind === 'flashJumpCurrent' || nav.actionKind === 'flashJumpFrameValue')) {
                    requestReturnFrame(resolveReturnFrameLabel(nav), nav);
                } else {
                    logDev('nav static only: ' + (nav.targetFrameLabel || nav.actionKind));
                }
            });
            _navLayerEl.appendChild(node);
        });
    }

    function getNavVisualKind(nav) {
        var item = nav && nav.libraryItemName || '';
        if (item === '选关界面UI/Symbol 3308') return 'entry-yellow';
        if (item === '试炼场深处按钮') return 'entry-red';
        if (item === 'sprite/Symbol 1025') return 'return';
        if (item === 'sprite/返回车库按钮') return 'return-garage';
        if (item === 'sprite/通用按钮') return 'generic';
        if (item.indexOf('选关界面UI/Symbol ') === 0) return 'scene-entry';
        return 'generic';
    }

    function getNavDisplayLabel(nav, visualKind) {
        var target = nav && nav.targetFrameLabel || '';
        if (visualKind === 'entry-yellow' || visualKind === 'entry-red') return '进入' + target;
        if (visualKind === 'return') return '返回';
        if (visualKind === 'return-garage') return '回A兵团车库';
        return target || nav.label || '返回';
    }

    function resolveReturnFrameLabel(nav) {
        if (nav && nav.actionKind === 'flashJumpFrameValue' && nav.targetFrameLabel) {
            return nav.targetFrameLabel;
        }
        return _returnFrameLabel || _currentFrameLabel || '';
    }

    function handleDifficultyClick(e) {
        var target = e.target;
        if (!target || !target.classList || !target.classList.contains('stage-select-difficulty')) return;
        e.preventDefault();
        e.stopPropagation();
        var stageName = target.getAttribute('data-stage-name') || '';
        var difficulty = target.getAttribute('data-difficulty') || '';
        var entryKind = target.getAttribute('data-entry-kind') || 'difficulty';
        var button = findStageButton(stageName, entryKind);
        if (button) {
            requestStageActivation(button, difficulty, target);
            return;
        }
        requestStageActivation({ stageName: stageName, entryKind: entryKind }, difficulty, target);
    }

    function requestStageActivation(button, difficulty, pressedTarget) {
        var stageName = button && button.stageName || '';
        var entryKind = button && button.entryKind || 'difficulty';
        var state = getStageState(stageName);
        if (!stageName) {
            showError('invalid_stage');
            return;
        }
        if (!state.unlocked) {
            _lastDifficultyClick = {
                stageName: stageName,
                difficulty: difficulty,
                entryKind: entryKind,
                blocked: 'locked'
            };
            showError('locked');
            logDev((entryKind === 'difficulty' ? 'difficulty' : entryKind) + ' blocked: ' + stageName + ' / locked');
            return;
        }
        if (_busyStageName) {
            logDev('difficulty busy: ' + _busyStageName);
            return;
        }
        _lastDifficultyClick = {
            stageName: stageName,
            difficulty: difficulty,
            entryKind: entryKind
        };
        logDev((entryKind === 'difficulty' ? 'difficulty' : entryKind) + ' enter request: ' + stageName + (difficulty ? ' / ' + difficulty : ''));
        if (pressedTarget && pressedTarget.classList && pressedTarget.classList.contains('stage-select-difficulty')) {
            pressedTarget.classList.add('is-pressed');
            setTimeout(function() {
                pressedTarget.classList.remove('is-pressed');
            }, 180);
        }
        requestEnter(stageName, difficulty, entryKind);
    }

    function findStageButton(stageName, entryKind) {
        var frame = StageSelectData.getFrame(_currentFrameLabel);
        var buttons = frame && frame.stageButtons || [];
        for (var i = 0; i < buttons.length; i += 1) {
            if (buttons[i].stageName === stageName && (buttons[i].entryKind || 'difficulty') === entryKind) return buttons[i];
        }
        return null;
    }

    function getStageState(stageName) {
        var stages = _fixture && _fixture.stages || {};
        var base = stages[stageName] || {};
        var state = {
            unlocked: typeof base.unlocked === 'undefined' ? true : !!base.unlocked,
            task: !!base.task,
            highestDifficulty: base.highestDifficulty || '简单',
            detail: base.detail || '',
            materialDetail: base.materialDetail || '',
            limitDetail: base.limitDetail || '',
            stageType: base.stageType || ''
        };
        var live = _runtimeSnapshot && _runtimeSnapshot.stageDetails && _runtimeSnapshot.stageDetails[stageName] || null;
        if (live) {
            if (typeof live.task !== 'undefined') state.task = !!live.task;
            state.highestDifficulty = live.highestDifficulty || state.highestDifficulty;
            state.detail = typeof live.detail === 'string' ? live.detail : state.detail;
            state.materialDetail = typeof live.materialDetail === 'string' ? live.materialDetail : state.materialDetail;
            state.limitDetail = typeof live.limitDetail === 'string' ? live.limitDetail : state.limitDetail;
            state.stageType = live.stageType || state.stageType;
        }
        if (_runtimeSnapshot && _runtimeSnapshot.unlockedStages && Object.prototype.hasOwnProperty.call(_runtimeSnapshot.unlockedStages, stageName)) {
            state.unlocked = !!_runtimeSnapshot.unlockedStages[stageName];
        }
        return state;
    }

    function buildStageDetail(button, state) {
        var parts = [];
        var detail = flashHtmlToText(state.detail || button.detail || '');
        var limit = flashHtmlToText(state.limitDetail || '');
        var material = flashHtmlToText(state.materialDetail || '');
        if (detail) parts.push(detail);
        if (limit) parts.push(limit);
        if (!parts.length && material) parts.push(material);
        if (!parts.length) parts.push('暂无资料');
        var text = parts.join('\n');
        return {
            html: escapeHtml(text).replace(/\r?\n/g, '<br>'),
            rawText: text
        };
    }

    function cleanStageText(text) {
        return String(text || '')
            .replace(/\r\n/g, '\n')
            .replace(/[ \t]+\n/g, '\n')
            .replace(/\n{3,}/g, '\n\n')
            .replace(/^[\s\u3000]+|[\s\u3000]+$/g, '');
    }

    function flashHtmlToText(text) {
        var value = String(text || '');
        if (!value) return '';
        value = decodeHtmlEntities(value);
        value = value.replace(/<br\s*\/?>/gi, '\n').replace(/<\/p>/gi, '\n');
        if (typeof document !== 'undefined' && document.createElement) {
            var div = document.createElement('div');
            div.innerHTML = value;
            return cleanStageText(div.textContent || div.innerText || '');
        }
        return cleanStageText(value.replace(/<[^>]+>/g, ''));
    }

    function decodeHtmlEntities(text) {
        var value = String(text || '');
        if (typeof document === 'undefined' || !document.createElement) {
            return value
                .replace(/&amp;/g, '&')
                .replace(/&lt;/g, '<')
                .replace(/&gt;/g, '>')
                .replace(/&quot;/g, '"')
                .replace(/&#39;/g, "'");
        }
        var textarea = document.createElement('textarea');
        for (var i = 0; i < 2; i++) {
            textarea.innerHTML = value;
            var decoded = textarea.value;
            if (decoded === value) break;
            value = decoded;
        }
        return value;
    }

    function weighChars(s) {
        var w = 0;
        for (var i = 0; i < s.length; i += 1) {
            w += s.charCodeAt(i) < 128 ? 0.58 : 1;
        }
        return w;
    }

    // Off-DOM measurer: replicate .stage-select-card-detail typography exactly.
    // Reused across measurements to avoid layout-tree churn.
    var _detailMeasurer = null;
    function getDetailMeasurer() {
        if (_detailMeasurer || typeof document === 'undefined' || !document.body) return _detailMeasurer;
        _detailMeasurer = document.createElement('div');
        _detailMeasurer.setAttribute('aria-hidden', 'true');
        _detailMeasurer.style.cssText = [
            'position:absolute',
            'visibility:hidden',
            'pointer-events:none',
            'left:-9999px',
            'top:0',
            'box-sizing:content-box',
            'font-family:"Microsoft YaHei","Microsoft JhengHei",Arial,sans-serif',
            'font-size:14px',
            'white-space:normal',
            'word-break:break-all',
            'overflow-wrap:anywhere',
            'padding:0',
            'margin:0',
            'border:0'
        ].join(';');
        document.body.appendChild(_detailMeasurer);
        return _detailMeasurer;
    }

    // Measure exact rendered height of the detail HTML at a given inner width + line-height.
    // Returns -1 if measurement is unavailable (test/SSR contexts).
    function measureDetailHeight(html, innerWidth, lineHeight) {
        var m = getDetailMeasurer();
        if (!m) return -1;
        m.style.width = innerWidth + 'px';
        m.style.lineHeight = lineHeight + 'px';
        m.innerHTML = html || '';
        return m.scrollHeight;
    }

    // Heuristic fallback when DOM measurement isn't available.
    function estimateStageCardHeight(text, charsPerLine, lineHeight, baseline, minH, maxH) {
        var lines = cleanStageText(text).split('\n');
        var estLines = 0;
        lines.forEach(function(line) {
            estLines += Math.max(1, Math.ceil(weighChars(line) / charsPerLine));
        });
        return Math.max(minH, Math.min(maxH, baseline + estLines * lineHeight));
    }

    // Adaptive card sizing: keep 167px (original look) when content fits;
    // bump to 195 / 220 only when title or description would overflow.
    // Card height comes from a real off-DOM render measurement so wrapping,
    // CJK glyph metrics and word-break behavior are pixel-accurate.
    function computeCardSizing(button, detail) {
        var nameWeight = weighChars(button.stageName || '');
        var textWeight = weighChars(cleanStageText(detail.rawText || '').replace(/\n/g, ' '));

        if (!isRuntimeMode()) {
            // Dev mode: original geometry, fall back to estimation since the
            // dev card uses the legacy 167-wide layout.
            return {
                width: 167,
                nameLines: 1,
                cardHeight: estimateStageCardHeight(detail.rawText || '', 10.8, 20, 124, 232, 430)
            };
        }

        var width;
        var nameLines;
        if (nameWeight <= 9.4)         { width = 167; nameLines = 1; }
        else if (nameWeight <= 12.2)   { width = 195; nameLines = 1; }
        else if (nameWeight <= 14.0)   { width = 220; nameLines = 1; }
        else                           { width = 220; nameLines = 2; }

        // Description-driven bump: wider card → fewer wrap lines.
        if (textWeight > 130 && width < 220) width = 220;
        else if (textWeight > 90 && width < 195) width = 195;

        // Inner widths must match CSS: detail width = card width - 17px
        var innerWidth = width - 17;
        // Line height matches CSS rules (runtime detail = 19px; non-runtime = 20px)
        var lineHeight = 19;
        var baseline = (nameLines === 2) ? 167 : 124;
        var minH = (nameLines === 2) ? 240 : 232;
        // Generous cap: ~17 lines of 19px detail in 220-wide card.
        var maxH = 480;

        var detailH = measureDetailHeight(detail.html, innerWidth, lineHeight);
        var cardHeight;
        if (detailH >= 0) {
            cardHeight = Math.max(minH, Math.min(maxH, baseline + detailH));
        } else {
            // Headless / SSR fallback path
            var charsPerLine = (width === 220) ? 14.6 : (width === 195) ? 12.6 : 10.8;
            cardHeight = estimateStageCardHeight(detail.rawText || '', charsPerLine, lineHeight, baseline, minH, maxH);
        }
        return { width: width, nameLines: nameLines, cardHeight: cardHeight };
    }

    function computeDirectSizing(button) {
        var nameWeight = weighChars(button && button.stageName || '');
        var width = Math.max(92, Math.min(168, Math.ceil(nameWeight * 13) + 28));
        var height = nameWeight > 9.8 ? 34 : 26;
        if (button && button.entryKind === 'task') {
            width = 91;
            height = 21;
        }
        return { width: width, height: height };
    }

    function isChallengeMode() {
        if (_runtimeSnapshot && typeof _runtimeSnapshot.isChallengeMode !== 'undefined') return !!_runtimeSnapshot.isChallengeMode;
        return !!(_fixture && _fixture.challenge);
    }

    function isRuntimeMode() {
        return _mode === 'runtime';
    }

    function setFrameMenuOpen(open) {
        _frameMenuOpen = !!open && isRuntimeMode();
        if (_el) _el.classList.toggle('is-frame-menu-open', _frameMenuOpen);
        if (_frameToggleEl) _frameToggleEl.setAttribute('aria-expanded', _frameMenuOpen ? 'true' : 'false');
        if (_frameMenuOpen) clearError();
    }

    function isWithin(target, parent) {
        if (!target || !parent) return false;
        var node = target;
        while (node) {
            if (node === parent) return true;
            node = node.parentNode;
        }
        return false;
    }

    function requestSnapshot() {
        if (typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') {
            logDev('snapshot skipped: bridge unavailable');
            return;
        }
        var reqId = 'stage-select-snapshot-' + (++_reqSeq);
        var currentSession = _session;
        _pendingReq[reqId] = function(resp) {
            delete _pendingReq[reqId];
            if (currentSession !== _session || !Panels.isOpen() || Panels.getActive() !== 'stage-select') return;
            if (!resp.success) {
                showError(resp.error || 'snapshot_failed');
                return;
            }
            clearError();
            applyRuntimeSnapshot(resp.snapshot || {});
        };
        Bridge.send({
            type: 'panel',
            panel: 'stage-select',
            cmd: 'snapshot',
            callId: reqId,
            frameLabel: _currentFrameLabel,
            returnFrameLabel: _returnFrameLabel,
            stageNames: getManifestStageNames()
        });
    }

    function requestJumpFrame(frameLabel, nav, sourceFrameLabel) {
        if (!frameLabel) return;
        if (typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') {
            showError('bridge_unavailable');
            return;
        }
        var reqId = 'stage-select-jump-' + (++_reqSeq);
        var currentSession = _session;
        _pendingReq[reqId] = function(resp) {
            delete _pendingReq[reqId];
            if (currentSession !== _session || !Panels.isOpen() || Panels.getActive() !== 'stage-select') return;
            if (!resp.success) {
                showError(resp.error || 'jump_frame_failed');
                return;
            }
            clearError();
            logDev('jump frame synced: ' + frameLabel);
        };
        Bridge.send({
            type: 'panel',
            panel: 'stage-select',
            cmd: 'jump_frame',
            callId: reqId,
            frameLabel: frameLabel,
            sourceFrameLabel: sourceFrameLabel || '',
            navId: nav && nav.id || ''
        });
    }

    function requestEnter(stageName, difficulty, entryKind) {
        if (typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') {
            showError('bridge_unavailable');
            return;
        }
        var reqId = 'stage-select-enter-' + (++_reqSeq);
        var currentSession = _session;
        _busyStageName = stageName;
        _lastError = '';
        renderCurrentFrame();
        _pendingReq[reqId] = function(resp) {
            delete _pendingReq[reqId];
            if (currentSession !== _session) return;
            _busyStageName = '';
            if (!resp.success) {
                showError(resp.error || 'enter_failed');
                renderCurrentFrame();
                return;
            }
            logDev('enter accepted: ' + stageName + ' / ' + difficulty);
            if (resp.closePanel) {
                requestClose();
                return;
            }
            renderCurrentFrame();
        };
        Bridge.send({
            type: 'panel',
            panel: 'stage-select',
            cmd: 'enter',
            callId: reqId,
            stageName: stageName,
            difficulty: difficulty,
            entryKind: entryKind || 'difficulty'
        });
    }

    function requestReturnFrame(frameLabel, nav) {
        var targetFrameLabel = frameLabel || _returnFrameLabel || _currentFrameLabel;
        if (!targetFrameLabel) {
            showError('invalid_return_frame');
            return;
        }
        if (typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') {
            showError('bridge_unavailable');
            return;
        }
        var reqId = 'stage-select-return-' + (++_reqSeq);
        var currentSession = _session;
        _pendingReq[reqId] = function(resp) {
            delete _pendingReq[reqId];
            if (currentSession !== _session) return;
            if (!resp.success) {
                showError(resp.error || 'return_frame_failed');
                return;
            }
            clearError();
            logDev('return frame synced: ' + (resp.returnFrameLabel || targetFrameLabel));
            if (resp.closePanel) {
                requestClose();
            }
        };
        Bridge.send({
            type: 'panel',
            panel: 'stage-select',
            cmd: 'return_frame',
            callId: reqId,
            frameLabel: targetFrameLabel,
            returnFrameLabel: targetFrameLabel,
            navId: nav && nav.id || ''
        });
    }

    function applyRuntimeSnapshot(snapshot) {
        _runtimeSnapshot = snapshot || {};
        _lastError = '';
        if (_runtimeSnapshot.currentFrameLabel && StageSelectData.getFrame(_runtimeSnapshot.currentFrameLabel)) {
            _currentFrameLabel = _runtimeSnapshot.currentFrameLabel;
        }
        if (_runtimeSnapshot.returnFrameLabel) {
            _returnFrameLabel = _runtimeSnapshot.returnFrameLabel;
        }
        renderCurrentFrame();
        logDev('snapshot live: ' + countUnlocked(_runtimeSnapshot.unlockedStages) + ' unlocked');
    }

    function getManifestStageNames() {
        var manifest = StageSelectData.getManifest();
        var lookup = {};
        var names = [];
        (manifest.frames || []).forEach(function(frame) {
            (frame.stageButtons || []).forEach(function(button) {
                var name = button.stageName || '';
                if (!name || lookup[name]) return;
                lookup[name] = true;
                names.push(name);
            });
        });
        return names;
    }

    function countUnlocked(unlockedStages) {
        var count = 0;
        var key;
        for (key in (unlockedStages || {})) {
            if (unlockedStages[key]) count += 1;
        }
        return count;
    }

    function showError(error) {
        _lastError = error || 'unknown_error';
        if (_logEl) {
            _logEl.classList.add('is-error');
            _logEl.textContent = _lastError;
        }
    }

    function clearError() {
        if (!_lastError && (!_logEl || !_logEl.classList.contains('is-error'))) return;
        _lastError = '';
        if (_logEl) {
            _logEl.classList.remove('is-error');
            if (isRuntimeMode()) _logEl.textContent = '';
        }
    }

    function requestClose() {
        _pendingReq = {};
        Panels.close();
        if (typeof Bridge !== 'undefined' && Bridge && Bridge.send) {
            Bridge.send({ type: 'panel', panel: 'stage-select', cmd: 'close' });
        }
    }

    function initLayoutWatcher() {
        if (_resizeHandler) return;
        _resizeHandler = function() { syncStageLayout(); };
        window.addEventListener('resize', _resizeHandler);
        if (window.ResizeObserver) {
            _layoutObserver = new ResizeObserver(syncStageLayout);
            var shell = _el && _el.querySelector('.stage-select-stage-shell');
            if (shell) _layoutObserver.observe(shell);
        }
    }

    function teardownLayoutWatcher() {
        if (_layoutObserver) {
            _layoutObserver.disconnect();
            _layoutObserver = null;
        }
        if (_resizeHandler) {
            window.removeEventListener('resize', _resizeHandler);
            _resizeHandler = null;
        }
    }

    function onClose() {
        setFrameMenuOpen(false);
        teardownLayoutWatcher();
    }

    function syncStageLayout() {
        if (!_stageEl || !_el) return;
        var shell = _el.querySelector('.stage-select-stage-shell');
        if (!shell) return;
        var rect = shell.getBoundingClientRect();
        var scale = Math.min(rect.width / DESIGN_W, rect.height / DESIGN_H);
        var maxScale = isRuntimeMode() ? 1.65 : 1.35;
        scale = Math.max(0.45, Math.min(maxScale, scale || 1));
        _stageEl.style.width = DESIGN_W + 'px';
        _stageEl.style.height = DESIGN_H + 'px';
        _stageEl.style.transform = 'translate(-50%, -50%) scale(' + scale + ')';
        _stageEl.style.setProperty('--stage-select-scale', scale);
    }

    function logDev(message) {
        if (_logEl && !isRuntimeMode()) {
            _logEl.classList.remove('is-error');
            _logEl.textContent = message;
        }
        if (window.console && console.log) console.log('[stage-select] ' + message);
    }

    function resolveAssetUrl(url) {
        var value = String(url || '');
        if (!value) return value;
        if (/^(?:https?:|file:|data:|\/)/i.test(value)) return value;
        if (value.indexOf('assets/') === 0 && window.location && window.location.pathname.indexOf('/modules/stage-select/dev/') >= 0) {
            return '../../../' + value;
        }
        return value;
    }

    function escapeHtml(text) {
        return String(text || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function escapeAttr(text) {
        return escapeHtml(text).replace(/'/g, '&#39;');
    }

    Bridge.on('panel_resp', function(data) {
        if (!data || data.panel !== 'stage-select') return;
        var cb = _pendingReq[data.callId];
        if (cb) cb(data);
    });

    return {
        _debugGetState: function() {
            return {
                isOpen: Panels.getActive && Panels.getActive() === 'stage-select',
                frameLabel: _currentFrameLabel,
                fixture: _fixtureName,
                mode: _mode,
                returnFrameLabel: _returnFrameLabel,
                frameMenuOpen: _frameMenuOpen,
                challenge: isChallengeMode(),
                stageButtonCount: _buttonLayerEl ? _buttonLayerEl.querySelectorAll('.stage-select-stage-button').length : 0,
                navButtonCount: _navLayerEl ? _navLayerEl.querySelectorAll('.stage-select-nav-button').length : 0,
                layoutWatcherActive: !!(_layoutObserver || _resizeHandler),
                runtimeSnapshot: _runtimeSnapshot,
                pendingCount: Object.keys(_pendingReq).length,
                busyStageName: _busyStageName,
                lastError: _lastError,
                lastDifficultyClick: _lastDifficultyClick
            };
        },
        _debugSetFrame: setFrame,
        _debugApplySnapshot: applyRuntimeSnapshot,
        _debugRequestSnapshot: requestSnapshot,
        _debugSetFixture: function(name) {
            setFixture(name);
            if (_fixtureSelectEl) _fixtureSelectEl.value = _fixtureName;
            renderCurrentFrame();
        }
    };
})();
