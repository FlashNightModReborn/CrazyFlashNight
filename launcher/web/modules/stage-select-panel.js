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
    var _currentFrameLabel = '';
    var _fixtureName = 'mixed';
    var _fixture = null;
    var _lastDifficultyClick = null;
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
                    '<button class="stage-select-close-btn" type="button" title="关闭" data-audio-cue="cancel">X</button>' +
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

        _el.querySelector('.stage-select-close-btn').addEventListener('click', requestClose);
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
        DESIGN_W = manifest.designSize && manifest.designSize.width || 1024;
        DESIGN_H = manifest.designSize && manifest.designSize.height || 576;
        _fixtureName = initData && initData.fixture || 'mixed';
        _currentFrameLabel = initData && initData.frameLabel || initData && initData.page || manifest.frameOrder[0];
        setFixture(_fixtureName);
        if (_fixtureSelectEl) _fixtureSelectEl.value = _fixtureName;
        _lastDifficultyClick = null;
        renderTabs();
        initLayoutWatcher();
        renderCurrentFrame();
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
        _tabsEl.innerHTML = '';
        manifest.frameOrder.forEach(function(label) {
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'stage-select-tab';
            button.setAttribute('data-frame-label', label);
            button.textContent = label;
            button.addEventListener('click', function() {
                setFrame(label, 'tab');
            });
            _tabsEl.appendChild(button);
        });
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
        var i;
        for (i = 0; i < tabs.length; i += 1) {
            tabs[i].classList.toggle('is-active', tabs[i].getAttribute('data-frame-label') === frame.frameLabel);
        }
        var region = _el.querySelector('#stage-select-region');
        if (region) region.textContent = frame.frameLabel;
        if (_summaryEl) {
            _summaryEl.innerHTML =
                '<div>frame: <b>' + escapeHtml(frame.frameLabel) + '</b></div>' +
                '<div>stage buttons: <b>' + (frame.stageButtons || []).length + '</b></div>' +
                '<div>nav buttons: <b>' + (frame.navButtons || []).length + '</b></div>' +
                '<div>background: <b>' + escapeHtml(frame.background && frame.background.mode || 'missing') + '</b></div>' +
                '<div>fixture: <b>' + escapeHtml(_fixtureName) + '</b></div>';
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
        (frame.stageButtons || []).forEach(function(button) {
            _buttonLayerEl.appendChild(createStageButton(button));
        });
    }

    function createStageButton(button) {
        var state = getStageState(button.stageName);
        var node = document.createElement('div');
        node.className = 'stage-select-stage-button';
        node.tabIndex = 0;
        node.setAttribute('role', 'button');
        node.setAttribute('data-stage-name', button.stageName);
        node.setAttribute('data-stage-id', button.id);
        node.style.left = button.x + 'px';
        node.style.top = button.y + 'px';
        if (button.y < 60) node.classList.add('is-edge-top');
        if (button.x < 40) node.classList.add('is-edge-left');
        if (button.x > 790) node.classList.add('is-edge-right');
        if (!state.unlocked) node.classList.add('is-locked');
        if (state.task) node.classList.add('is-task');
        node.innerHTML =
            '<span class="stage-select-hit-zone" aria-hidden="true"></span>' +
            renderStageMarkerSvg() +
            '<span class="stage-select-stage-name">' + escapeHtml(button.stageName || '未命名') + '</span>' +
            renderStageLockSvg() +
            '<span class="stage-select-task-pulse"></span>' +
            '<span class="stage-select-card">' +
                '<span class="stage-select-card-corner" aria-hidden="true"></span>' +
                '<span class="stage-select-card-name">' + escapeHtml(button.stageName || '未命名') + '</span>' +
                '<span class="stage-select-preview-wrap">' +
                    '<img class="stage-select-preview" src="' + escapeAttr(resolveAssetUrl(button.previewUrl)) + '" alt="' + escapeAttr(button.stageName) + ' 预览" data-preview-source="' + escapeAttr(button.previewSource || '') + '">' +
                '</span>' +
                '<span class="stage-select-card-detail">' + escapeHtml(button.detail || state.detail || '暂无资料') + '</span>' +
                '<span class="stage-select-difficulties">' + renderDifficulties(button, state) + '</span>' +
            '</span>';
        node.addEventListener('click', function() {
            logDev('select stage: ' + button.stageName + (state.unlocked ? '' : ' (locked fixture)'));
        });
        node.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                logDev('select stage: ' + button.stageName + (state.unlocked ? '' : ' (locked fixture)'));
            }
        });
        return node;
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
        var difficulties = _fixture && _fixture.challenge ? ['地狱'] : ['简单', '冒险', '修罗', '地狱'];
        return difficulties.map(function(name) {
            var active = state.task && state.highestDifficulty === name ? ' is-recommended' : '';
            return '<button type="button" class="stage-select-difficulty is-' + difficultyClass(name) + active + '" data-stage-name="' + escapeAttr(button.stageName) + '" data-difficulty="' + escapeAttr(name) + '">' + escapeHtml(name) + '</button>';
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
                    setFrame(nav.targetFrameLabel, 'nav');
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

    function handleDifficultyClick(e) {
        var target = e.target;
        if (!target || !target.classList || !target.classList.contains('stage-select-difficulty')) return;
        e.preventDefault();
        e.stopPropagation();
        _lastDifficultyClick = {
            stageName: target.getAttribute('data-stage-name') || '',
            difficulty: target.getAttribute('data-difficulty') || ''
        };
        logDev('difficulty fixture click: ' + _lastDifficultyClick.stageName + ' / ' + _lastDifficultyClick.difficulty);
        target.classList.add('is-pressed');
        setTimeout(function() {
            target.classList.remove('is-pressed');
        }, 180);
    }

    function getStageState(stageName) {
        var stages = _fixture && _fixture.stages || {};
        return stages[stageName] || {
            unlocked: true,
            task: false,
            highestDifficulty: '简单',
            detail: ''
        };
    }

    function requestClose() {
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
        teardownLayoutWatcher();
    }

    function syncStageLayout() {
        if (!_stageEl || !_el) return;
        var shell = _el.querySelector('.stage-select-stage-shell');
        if (!shell) return;
        var rect = shell.getBoundingClientRect();
        var scale = Math.min(rect.width / DESIGN_W, rect.height / DESIGN_H);
        scale = Math.max(0.45, Math.min(1.35, scale || 1));
        _stageEl.style.width = DESIGN_W + 'px';
        _stageEl.style.height = DESIGN_H + 'px';
        _stageEl.style.transform = 'translate(-50%, -50%) scale(' + scale + ')';
        _stageEl.style.setProperty('--stage-select-scale', scale);
    }

    function logDev(message) {
        if (_logEl) _logEl.textContent = message;
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

    return {
        _debugGetState: function() {
            return {
                isOpen: Panels.getActive && Panels.getActive() === 'stage-select',
                frameLabel: _currentFrameLabel,
                fixture: _fixtureName,
                challenge: !!(_fixture && _fixture.challenge),
                stageButtonCount: _buttonLayerEl ? _buttonLayerEl.querySelectorAll('.stage-select-stage-button').length : 0,
                navButtonCount: _navLayerEl ? _navLayerEl.querySelectorAll('.stage-select-nav-button').length : 0,
                layoutWatcherActive: !!(_layoutObserver || _resizeHandler),
                lastDifficultyClick: _lastDifficultyClick
            };
        },
        _debugSetFrame: setFrame,
        _debugSetFixture: function(name) {
            setFixture(name);
            if (_fixtureSelectEl) _fixtureSelectEl.value = _fixtureName;
            renderCurrentFrame();
        }
    };
})();
