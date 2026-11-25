/** 游戏设置：常用驾驶舱、画面与实时弹幕预览沙盒、36 键映射与统一偏好中心。 */
(function() {
    'use strict';
    var DESIGN_W = 1024, DESIGN_H = 576;
    var _config = window.__SETTINGS_CONFIG__ || {};
    var _shell, _root, _content, _status, _apply, _discard, _saveRetry;
    var _init, _instance = '', _snapshot, _draft, _scale;
    var _busy = false, _requiresReconcile = false;
    var _authority = null, _persistenceStatus, _reconcileButton, _dirtyBadge;
    var _readOnlyProtocol = false;
    var _performanceDraft = null, _performanceBusy = false;
    var _performanceMessage = '', _performanceMessageState = 'ready';
    var _hostReconcileDraft = null;
    var _previewActive = false, _previewTimer = null, _closeTimer = null;
    var _capturing = -1, _activeTab = 'common', _confirmAction = '', _confirmTimer = null;
    var _keyFilterQuery = '';
    var _flashPreview = null, _hitNumberPreview = null;
    var _cameraPreviewImage = null, _inlineCameraImage = null, _inlineCameraHud = null;
    var _inlineCameraSafeFrame = null, _inlineCameraHudBand = null;
    var _cameraSafeFrame = null, _cameraHudBand = null, _cameraParityNote = null, _cameraDynamicSamples = null;
    var _entryCameraScale = null, _entryCameraContext = null, _cameraDynamicSample = 1;
    var _cameraModal = null, _cameraReturnFocus = null;
    var _cameraScaleHud = null, _cameraModeHud = null;
    var _pendingInitialCameraPreview = false;
    var _cheatModal = null, _cheatHelpRequest = null, _cheatHelpText = null, _helpReturnFocus = null;
    var _damageLedgerModal = null, _damageLedgerReturnFocus = null;
    var _damageLedgerOffset = 0, _damageLedgerLoading = false;
    var _closeConfirmModal = null, _closeConfirmReturnFocus = null;
    var _tooltipScope = null;

    // 打击伤害数字实时预览沙盒状态（仅在视觉页签可见时步进，切页/关闭立即释放）
    var _hitPreviewState = {
        presetId: 'barrage',
        paused: false,
        useGameBg: false,
        timeMs: 0,
        lastTickAt: 0,
        activeRows: 0,
        omittedRows: 0,
        error: ''
    };
    var _hitPreviewTimer = null;
    var _hitPreviewAbort = null;
    var _hitPreviewInFlight = false;
    var _hitPreviewCanvas = null;
    var _hitPreviewTelemetry = null;
    var _hitPreviewStage = null;
    var _hitPreviewToken = 0;

    // Andy Law 立绘 manifest 会话内单次加载缓存
    var _portraitManifestPromise = null;
    var _portraitManifestCache = null;

    var TABS = [
        ['common', '常用'],
        ['visual', '画面与战斗'],
        ['keys', '键位'],
        ['prefs', '界面与音频']
    ];

    var HIT_MODES = [
        {value: 'balanced', short: '平衡', label: '平衡 · 语义分轨', desc: '默认推荐 · 语义分轨压缩，高密弹幕下保持清晰可读'},
        {value: 'total', short: '总伤', label: '总伤 · 累计连段', desc: '每目标累计总伤，连段持续跳字并高亮当前属性'},
        {value: 'classic', short: '经典', label: '经典 · 逐段散开', desc: '经典 Flash 逐段散开飘字，保留原味反馈节奏'},
        {value: 'detail', short: '逐发', label: '逐发 · 完整矩阵', desc: '完整展示每发 Burst 逐段明细，配目标短距指向符'},
        {value: 'off', short: '关闭', label: '关闭 · 隐藏飘字', desc: '彻底关闭战斗飘字（精确对账日志仍可在暂停时查看）'}
    ];

    var PERF_PRESETS = [
        {value: 'performance', title: '性能', sub: '优先帧率'},
        {value: 'balanced', title: '通用', sub: '均衡推荐'},
        {value: 'quality', title: '画质', sub: '优先清晰'}
    ];

    var HUD_MOTION_MODES = [
        {value: 'full', label: '完整', desc: '保留掉血残影、连击脉冲与低血呼吸'},
        {value: 'reduced', label: '精简', desc: '缩短过渡并关闭呼吸与脉冲闪光'},
        {value: 'static', label: '静态反馈', desc: '取消过渡动画，数值与血条瞬时更新'}
    ];

    var SECTION_CODES = {
        '流程救援': 'RECOVERY',
        '声音': 'AUDIO BUS',
        '性能预设': 'PERFORMANCE',
        '打击伤害数字': 'HIT NUMBER',
        '镜头缩放': 'CAMERA LAB',
        '打击伤害数字 · 实时弹幕预览': 'LIVE SANDBOX',
        '性能方案与画面增强': 'RENDER PIPELINE',
        '游戏内画面与立绘': 'WORLD & PORTRAIT',
        '战斗信息动效': 'HUD MOTION',
        '36 项权威键位': 'INPUT MAP',
        '移动与操作': 'MOVEMENT',
        '攻击模式': 'COMBAT MODE',
        '快捷物品': 'QUICK ITEMS',
        '快捷技能': 'SKILL CHANNEL',
        '战斗扩展': 'COMBAT AUX',
        '点歌器设置': 'JUKEBOX',
        '界面与音频偏好': 'LOCAL PREFS',
        '物品栏网格密度': 'ITEM DENSITY'
    };

    var _mux = new SettingsRuntime.RequestMux({
        send: function(message) { return Bridge.send(message); },
        timeoutMs: _config.requestTimeoutMs,
        sessionNonce: _config.sessionNonce
    });

    Panels.register('settings', {
        create: createDOM,
        onOpen: onOpen,
        onRebind: onRebind,
        onClose: cleanup,
        onRequestClose: requestClose,
        onForceClose: cleanup
    });

    function node(tag, className, text) {
        var el = document.createElement(tag);
        if (className) el.className = className;
        if (text !== undefined) el.textContent = text;
        return el;
    }
    function button(text, className, action) {
        var el = node('button', className || 'settings-button', text);
        if (/\bsettings-(?:button|key-button|copy-command)\b/.test(el.className)) el.classList.add('term-btn');
        el.type = 'button';
        if (action) el.addEventListener('click', action);
        return el;
    }
    function createDOM() {
        _shell = node('div', 'panel-scale-shell settings-scale-shell');
        return _shell;
    }
    function clear(el) { while (el && el.firstChild) el.removeChild(el.firstChild); }
    function cue(name) { if (window.BootstrapAudio) window.BootstrapAudio.cue(name); }
    function notifyToast(message, severity, silent) {
        if (typeof Toast !== 'undefined' && Toast && typeof Toast.add === 'function') {
            Toast.add(message, {severity: severity || 'info', silent: silent === true});
        }
    }
    function hideTooltips() {
        if (typeof PanelTooltip !== 'undefined' && PanelTooltip && typeof PanelTooltip.hide === 'function') {
            try { PanelTooltip.hide(); } catch (err) {}
        }
    }
    function dismissTooltipsHard() {
        hideTooltips();
        if (typeof Promise !== 'undefined') {
            Promise.resolve().then(hideTooltips);
        }
    }
    function prefersReducedMotion() {
        try {
            return !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
        } catch (err) {
            return false;
        }
    }
    function escapeHtml(value) {
        return String(value == null ? '' : value).replace(/[&<>"']/g, function(character) {
            return {'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[character];
        });
    }
    function annotate(target, text, placement) {
        if (!target || !text) return target;
        target.removeAttribute('title');
        target.setAttribute('data-settings-tooltip', String(text));
        if (_tooltipScope && _tooltipScope.bindAsync) {
            _tooltipScope.bindAsync(target, {
                key: function(event, el) { return 'settings:' + el.getAttribute('data-settings-tooltip'); },
                resolveItem: function(event, el) { return el.getAttribute('data-settings-tooltip') || ''; },
                renderBasic: function(value) {
                    return '<div class="settings-simple-tooltip">' + escapeHtml(value) + '</div>';
                },
                placement: placement || 'bottom'
            });
        }
        return target;
    }

    function onOpen(el, initData) {
        _init = initData || {};
        _instance = String(_init.panelInstanceId || '');
        _flashPreview = SettingsRuntime.normalizeFlashPreview(_init.flashPreview);
        _hitNumberPreview = SettingsRuntime.normalizeHitNumberPreview(_init.hitNumberPreview);
        _entryCameraScale = null;
        _entryCameraContext = null;
        _cameraDynamicSample = 1;
        _snapshot = null;
        _draft = null;
        _performanceDraft = null;
        _performanceBusy = false;
        _performanceMessage = '';
        _performanceMessageState = 'ready';
        _hostReconcileDraft = null;
        _busy = false;
        _requiresReconcile = false;
        _authority = null;
        _readOnlyProtocol = false;
        _previewActive = false;
        _capturing = -1;
        _activeTab = 'common';
        _keyFilterQuery = '';
        _pendingInitialCameraPreview = _init.initialView === 'camera_preview';
        _hitPreviewState = {
            presetId: (_hitNumberPreview && _hitNumberPreview.presets[1] && _hitNumberPreview.presets[1].id)
                || (_hitNumberPreview && _hitNumberPreview.presets[0] && _hitNumberPreview.presets[0].id)
                || 'barrage',
            paused: prefersReducedMotion(),
            useGameBg: false,
            timeMs: 0,
            lastTickAt: 0,
            activeRows: 0,
            omittedRows: 0,
            error: ''
        };
        cancelConfirmation();
        buildDOM();
        if (_scale) _scale.detach();
        _scale = typeof PanelScale !== 'undefined'
            ? PanelScale.attach(_shell, DESIGN_W, DESIGN_H) : null;
        window.addEventListener('keydown', onCaptureKey, true);
        if (!_mux.openSession(_instance)) {
            setStatus('面板实例无效，设置未加载。', 'error');
            return;
        }
        requestSnapshot();
    }

    function onRebind(el, initData) {
        cleanup();
        onOpen(el, initData);
        return true;
    }

    function cleanup() {
        _mux.closeSession();
        window.removeEventListener('keydown', onCaptureKey, true);
        stopHitPreviewLoop();
        hideTooltips();
        if (_previewTimer) clearTimeout(_previewTimer);
        _previewTimer = null;
        if (_closeTimer) clearTimeout(_closeTimer);
        _closeTimer = null;
        cancelConfirmation();
        closeCloseConfirm(false);
        closeCameraSimulator(false);
        closeCheatHelp();
        closeDamageLedger(false);
        if (_cheatHelpRequest) { try { _cheatHelpRequest.abort(); } catch (abortError) {} }
        _cheatHelpRequest = null;
        if (_scale) { _scale.detach(); _scale = null; }
        _snapshot = null;
        _draft = null;
        _performanceDraft = null;
        _performanceBusy = false;
        _hostReconcileDraft = null;
        _capturing = -1;
        _busy = false;
        _requiresReconcile = false;
        _flashPreview = null;
        _hitNumberPreview = null;
        _entryCameraScale = null;
        _entryCameraContext = null;
        _cameraDynamicSample = 1;
        _cameraPreviewImage = null;
        _inlineCameraImage = null;
        _inlineCameraHud = null;
        _inlineCameraSafeFrame = null;
        _inlineCameraHudBand = null;
        _cameraSafeFrame = null;
        _cameraHudBand = null;
        _cameraParityNote = null;
        _cameraDynamicSamples = null;
        _cameraScaleHud = null;
        _cameraModeHud = null;
        if (_tooltipScope) { _tooltipScope.dispose(); _tooltipScope = null; }
    }

    function buildDOM() {
        clear(_shell);
        hideTooltips();
        if (_tooltipScope) _tooltipScope.dispose();
        _tooltipScope = typeof PanelTooltip !== 'undefined' && PanelTooltip.createScope
            ? PanelTooltip.createScope('settings', {profile: 'simple-tooltip'}) : null;
        _root = node('section', 'settings-terminal-shell settings-panel');
        _root.setAttribute('aria-labelledby', 'settings-title');

        var header = node('header', 'settings-terminal-header settings-header term-heading-rule');
        header.appendChild(node('span', 'settings-brand-seal term-brand-seal', 'CF7:ME'));
        var heading = node('div', 'settings-heading');
        heading.appendChild(node('span', 'settings-kicker term-kicker', 'CONFIGURATION LINK'));
        var title = node('h1', 'settings-title', '游戏设置'); title.id = 'settings-title';
        heading.appendChild(title);
        header.appendChild(heading);

        var tabs = node('nav', 'settings-tabs');
        tabs.setAttribute('role', 'tablist');
        tabs.setAttribute('aria-label', '设置页面');
        TABS.forEach(function(row) {
            var tab = button(row[1], 'settings-tab', function() { showTab(row[0]); });
            tab.setAttribute('role', 'tab');
            tab.setAttribute('data-tab', row[0]);
            tabs.appendChild(tab);
        });
        header.appendChild(tabs);

        _status = node('p', 'settings-status', '正在读取游戏权威状态…');
        _status.setAttribute('role', 'status');
        header.appendChild(_status);
        header.appendChild(annotate(
            button('×', 'settings-terminal-close settings-close', requestClose),
            '关闭设置；若有尚未保存的存档改动，将先确认是否保存或放弃。',
            'left'));
        _root.appendChild(header);

        _content = node('main', 'settings-content');
        _content.addEventListener('scroll', hideTooltips, {passive: true});
        _root.appendChild(_content);

        var footer = node('footer', 'settings-footer');
        var footerMeta = node('div', 'settings-footer-meta');
        _dirtyBadge = node('span', 'settings-dirty-badge', '');
        _dirtyBadge.hidden = true;
        footerMeta.appendChild(_dirtyBadge);
        _persistenceStatus = node('div', 'settings-persistence-status', '正在读取保存确认…');
        _persistenceStatus.setAttribute('role', 'status');
        _persistenceStatus.setAttribute('aria-live', 'polite');
        footerMeta.appendChild(_persistenceStatus);
        footer.appendChild(footerMeta);

        var actions = node('div', 'settings-footer-actions');
        _reconcileButton = button('核对状态', 'settings-button secondary', requestReconcile);
        _reconcileButton.hidden = true;
        actions.appendChild(_reconcileButton);
        _saveRetry = button('只重试保存', 'settings-button warning', retrySave);
        _saveRetry.hidden = true;
        actions.appendChild(annotate(_saveRetry, '只重试上一次已经应用成功、但未能落盘的游戏设置。', 'top'));
        _discard = button('放弃游戏改动', 'settings-button secondary', discardGameDraft);
        actions.appendChild(annotate(_discard, '恢复打开设置时的游戏设置与音量，不影响已即时保存的本机偏好。', 'top'));
        _apply = button('应用并保存', 'settings-button primary', applyGameDraft);
        actions.appendChild(annotate(_apply, '应用当前游戏设置和键位，并写入玩家存档。', 'top'));
        footer.appendChild(actions);
        _root.appendChild(footer);
        _shell.appendChild(_root);
        showTab(_activeTab);
        refreshFooter();
    }

    function requestSnapshot(reconcileMessage) {
        _busy = true;
        refreshFooter();
        setStatus(reconcileMessage || '正在读取游戏权威状态…', 'loading');
        var id = _mux.request('snapshot', {v: 1}, {}, function(response) {
            _busy = false;
            adoptAuthority(response);
            if (response && response.v === 1 && response.writeAdmission === 'blocked_by_context') _readOnlyProtocol = true;
            if (response && response.requiresReconcile === true) {
                _requiresReconcile = true;
                setStatus('该权威快照早于未决写入终态，写入仍保持锁定；请重新读取。', 'warning');
            }
            var model = SettingsRuntime.normalizeSnapshot(response);
            if (!model) {
                setStatus(_requiresReconcile
                    ? '权威状态读取失败，写入仍保持锁定：' + errorText(response && response.error)
                    : '读取失败：' + errorText(response && response.error), 'error');
                renderCurrentTab();
                refreshFooter();
                return;
            }
            if (!_authority && response.requiresReconcile !== true) _requiresReconcile = false;
            _snapshot = model;
            var keepGameDraft = _hostReconcileDraft
                && _hostReconcileDraft.revision === model.revision
                && JSON.stringify(_hostReconcileDraft.settings) === JSON.stringify(model.settings)
                && JSON.stringify(_hostReconcileDraft.keys) === JSON.stringify(model.keys);
            _draft = keepGameDraft ? _hostReconcileDraft.draft : SettingsRuntime.gameDraft(model);
            var keepPerformanceDraft = _hostReconcileDraft && model.hostPrefs.performance
                && _hostReconcileDraft.performanceDraft
                && JSON.stringify(_hostReconcileDraft.performance) === JSON.stringify(model.hostPrefs.performance);
            _performanceDraft = keepPerformanceDraft ? _hostReconcileDraft.performanceDraft
                : model.hostPrefs.performance ? SettingsRuntime.copy(model.hostPrefs.performance.current) : null;
            _hostReconcileDraft = null;
            _performanceMessage = '';
            _performanceMessageState = 'ready';
            if (_entryCameraScale === null) {
                _entryCameraScale = Number(model.settings.basicZoomScale);
                if (!isFinite(_entryCameraScale) || _entryCameraScale < 0.5 || _entryCameraScale > 3)
                    _entryCameraScale = 1;
            }
            if (_entryCameraContext === null && model.cameraPreview) {
                _entryCameraContext = SettingsRuntime.copy(model.cameraPreview);
                if (_entryCameraContext.available && isFinite(_entryCameraContext.entryScale)) {
                    _entryCameraScale = _entryCameraContext.entryScale;
                }
            }
            _previewActive = model.previewActive;
            var keyState = SettingsRuntime.validateKeyDraft(model.keys, model.allowedKeyCodes);
            if (_requiresReconcile) {
                setStatus('上次操作等待核对，写入保持锁定。', 'warning');
            } else if (!keyState.valid) {
                setStatus('检测到历史键位冲突或保留键；可逐项修复，全部有效后再应用。', 'warning');
            } else {
                setStatus(model.migrationPending
                    ? (model.keyMigrationNotice || '已补齐旧存档缺失键位；应用后会立即持久化。')
                    : '已与游戏状态同步。', model.migrationPending ? 'warning' : 'ready');
            }
            renderCurrentTab();
            refreshFooter();
            if (_pendingInitialCameraPreview) {
                _pendingInitialCameraPreview = false;
                var cameraTrigger = _content && _content.querySelector('.settings-camera-open');
                if (cameraTrigger) openCameraSimulator(cameraTrigger);
            }
        });
        if (!id) {
            _busy = false;
            setStatus(_requiresReconcile
                ? '权威状态请求未发出，写入仍保持锁定。'
                : '设置会话尚未就绪。', 'error');
            renderCurrentTab();
            refreshFooter();
        }
    }

    function reconcileUnknownWrite(message, preserveDrafts) {
        if (preserveDrafts && !_hostReconcileDraft && _snapshot && _draft) {
            _hostReconcileDraft = {
                revision: _snapshot.revision,
                settings: SettingsRuntime.copy(_snapshot.settings),
                keys: SettingsRuntime.copy(_snapshot.keys),
                draft: SettingsRuntime.copy(_draft),
                performance: SettingsRuntime.copy(_snapshot.hostPrefs.performance),
                performanceDraft: SettingsRuntime.copy(_performanceDraft)
            };
        }
        _requiresReconcile = true;
        cue('unknown');
        renderCurrentTab();
        requestSnapshot(message || '写入结果未知，正在重新读取游戏权威状态；不会自动重放。');
    }
    function adoptAuthority(response) {
        _authority = SettingsRuntime.reduceAuthority(_authority, response);
        if (_authority) _requiresReconcile = _authority.requiresReconcile;
    }
    function requestReconcile() {
        if (_busy) return;
        _busy = true;
        refreshFooter();
        setStatus('正在核对上次操作与保存结果…', 'loading');
        _mux.request('reconcile', {v: 1}, {}, function(response) {
            _busy = false;
            adoptAuthority(response);
            if (response && response.success === true && !_requiresReconcile) {
                setStatus('上次操作已核对。', 'ready');
                requestSnapshot();
                return;
            }
            setStatus('现有证据尚不能结案；保存入口保持锁定。', 'warning');
            renderCurrentTab();
            refreshFooter();
        });
    }

    function showTab(tab, scrollTargetSelector) {
        hideTooltips();
        stopHitPreviewLoop();
        _activeTab = tab;
        if (_content) {
            _content.setAttribute('data-active-tab', tab);
            _content.scrollTop = 0;
        }
        var buttons = _root ? _root.querySelectorAll('.settings-tab') : [];
        for (var i = 0; i < buttons.length; i++) {
            var active = buttons[i].getAttribute('data-tab') === tab;
            buttons[i].classList.toggle('active', active);
            buttons[i].setAttribute('aria-selected', active ? 'true' : 'false');
        }
        renderCurrentTab();
        if (scrollTargetSelector && _content) {
            var target = _content.querySelector(scrollTargetSelector);
            if (target && typeof target.scrollIntoView === 'function') {
                target.scrollIntoView({block: 'start', behavior: 'auto'});
            }
        }
    }

    function renderCurrentTab() {
        if (!_content) return;
        stopHitPreviewLoop();
        hideTooltips();
        _inlineCameraImage = null;
        _inlineCameraHud = null;
        _inlineCameraSafeFrame = null;
        _inlineCameraHudBand = null;
        if (_tooltipScope && _tooltipScope.releaseTree) _tooltipScope.releaseTree(_content);
        clear(_content);
        if (_requiresReconcile) {
            var reconcile = node('div', 'settings-empty');
            reconcile.appendChild(node('h2', '', '写入状态等待权威核对'));
            reconcile.appendChild(node('p', '', '上一次请求可能已经生效；只有核对原操作与保存尝试后，才能解除写入锁。'));
            var retry = button('重新读取权威状态', 'settings-button primary', function() {
                if (_authority) requestReconcile();
                else requestSnapshot('正在重新核对游戏权威状态；不会自动重放写入。');
            });
            retry.disabled = _busy;
            reconcile.appendChild(retry);
            _content.appendChild(reconcile);
            return;
        }
        if (!_snapshot || !_draft) {
            var empty = node('div', 'settings-empty');
            empty.appendChild(node('h2', '', '设置暂不可用'));
            empty.appendChild(node('p', '', '请确认游戏已完成读档，然后重试同步。'));
            empty.appendChild(button('重新同步', 'settings-button primary', requestSnapshot));
            _content.appendChild(empty);
            return;
        }
        if (_activeTab === 'common') renderCommon();
        else if (_activeTab === 'visual') renderVisual();
        else if (_activeTab === 'keys') renderKeys();
        else renderPrefs();
    }

    // ── 通用构建原语 ──
    function section(title, note, opts) {
        opts = opts || {};
        var el = node('section', 'settings-section term-card term-corner-tick');
        var heading = node('div', 'settings-section-heading term-heading-rule');
        var identity = node('div', 'settings-section-identity');
        if (!opts.compact) {
            identity.appendChild(node('span', 'settings-section-code', SECTION_CODES[title] || 'SYSTEM BLOCK'));
        }
        var titleRow = node('div', 'settings-section-title-row');
        titleRow.appendChild(node('h2', '', title));
        if (opts.scope) {
            var scopeBadge = node('span', 'settings-scope-pill',
                opts.scope === 'save' ? '存档项' : '本机即时');
            scopeBadge.setAttribute('data-scope', opts.scope);
            titleRow.appendChild(scopeBadge);
        }
        identity.appendChild(titleRow);
        heading.appendChild(identity);

        var tools = node('div', 'settings-section-tools');
        if (opts.actions && opts.actions.length) {
            opts.actions.forEach(function(actionNode) { tools.appendChild(actionNode); });
        }
        if (note) {
            var hint = button('?', 'settings-hint-trigger', null);
            hint.setAttribute('aria-label', title + '说明');
            tools.appendChild(annotate(hint, note, 'left'));
        }
        if (tools.childNodes.length) heading.appendChild(tools);
        el.appendChild(heading);
        return el;
    }

    function field(label, control, note, desc) {
        var row = node('label', 'settings-field');
        var copy = node('span', 'settings-field-copy');
        copy.appendChild(node('b', '', label));
        if (desc) copy.appendChild(node('small', '', desc));
        row.appendChild(copy);
        row.appendChild(control);
        if (note) {
            var focusTarget = control && control.matches && control.matches('button,input,select')
                ? control : control && control.querySelector ? control.querySelector('button,input,select') : null;
            annotate(focusTarget || row, note, 'bottom');
        }
        return row;
    }

    function toggleSwitchInput(checked, onChange, hostKey) {
        var input = document.createElement('input');
        input.type = 'checkbox';
        input.className = 'settings-switch-input';
        input.checked = checked === true;
        if (hostKey) input.setAttribute('data-host-key', hostKey);
        input.addEventListener('change', function() { onChange(input.checked, input); });
        return input;
    }

    function checkbox(key, label, note, afterChange, desc) {
        var input = toggleSwitchInput(_draft.settings[key] === true, function(checked) {
            _draft.settings[key] = checked;
            changed();
            if (afterChange) afterChange();
        });
        return field(label, input, note, desc);
    }

    function selectControl(key, values) {
        var select = document.createElement('select');
        select.className = 'settings-select';
        values.forEach(function(row) {
            var option = node('option', '', row[1]);
            option.value = String(row[0]);
            select.appendChild(option);
        });
        select.value = String(_draft.settings[key]);
        select.addEventListener('change', function() {
            _draft.settings[key] = values.some(function(row) { return typeof row[0] === 'number'; })
                ? Number(select.value) : select.value;
            changed();
        });
        return select;
    }

    function segmentedGroup(options, currentValue, onSelect, extraClass, hostKey) {
        var group = node('div', 'settings-segmented ' + (extraClass || ''));
        group.setAttribute('role', 'radiogroup');
        if (hostKey) group.setAttribute('data-host-segment', hostKey);
        options.forEach(function(item) {
            var btn = node('button', 'settings-seg-btn');
            btn.type = 'button';
            btn.setAttribute('role', 'radio');
            btn.setAttribute('data-value', String(item.value));
            var isSelected = String(currentValue) === String(item.value);
            btn.classList.toggle('active', isSelected);
            btn.setAttribute('aria-checked', isSelected ? 'true' : 'false');
            btn.appendChild(node('span', 'settings-seg-title', item.label || item.title || item.short));
            if (item.sub) btn.appendChild(node('small', 'settings-seg-sub', item.sub));
            if (item.tooltip) annotate(btn, item.tooltip, 'bottom');
            btn.addEventListener('click', function() {
                if (btn.disabled) return;
                hideTooltips();
                onSelect(item.value, btn, group);
            });
            group.appendChild(btn);
        });
        return group;
    }

    function syncSegmentedGroup(group, value, disabled) {
        if (!group) return;
        var btns = group.querySelectorAll('.settings-seg-btn');
        for (var i = 0; i < btns.length; i++) {
            var active = btns[i].getAttribute('data-value') === String(value);
            btns[i].classList.toggle('active', active);
            btns[i].setAttribute('aria-checked', active ? 'true' : 'false');
            if (disabled !== undefined) btns[i].disabled = disabled;
        }
    }

    function hitModeMeta(mode) {
        for (var i = 0; i < HIT_MODES.length; i++) {
            if (HIT_MODES[i].value === mode) return HIT_MODES[i];
        }
        return HIT_MODES[0];
    }

    // ══════════════════════════════════════════════════════════════
    // 页签 1：常用驾驶舱（1024×576 一屏零滚动，6 项高频核心）
    // ══════════════════════════════════════════════════════════════
    function renderCommon() {
        var home = node('div', 'settings-home-layout settings-game-common');

        // 1. 顶部快捷救援带（尝试复活 / 立即返回基地 + 伤害对账日志入口）
        var rescueStrip = node('section', 'settings-rescue-strip term-card');
        var rescueLeft = node('div', 'settings-rescue-left');
        var rescueTag = node('div', 'settings-rescue-tag');
        rescueTag.appendChild(node('span', 'settings-section-code', 'RECOVERY LINK'));
        rescueTag.appendChild(node('strong', '', '流程救援'));
        rescueLeft.appendChild(rescueTag);

        var reviveBtn = button('尝试复活', 'settings-button primary', function() {
            sendTool('try_revive', {v: 1}, true);
        });
        reviveBtn.disabled = _snapshot.forceControls.tryReviveAvailable !== true;
        annotate(reviveBtn, _snapshot.forceControls.resurrectionRestricted
            ? '重新打开现役复活流程；当前关卡仍会执行自己的复活限制。'
            : '重新打开关卡结束后的现役复活流程。', 'bottom');
        rescueLeft.appendChild(reviveBtn);

        var baseBtn = button('立即返回基地', 'settings-button danger', function() {
            sendTool('return_base', {v: 1}, true);
        });
        baseBtn.disabled = _snapshot.forceControls.returnBaseAvailable !== true;
        annotate(baseBtn, '立即跳过当前流程并返回基地，不再额外确认。', 'bottom');
        rescueLeft.appendChild(baseBtn);
        rescueStrip.appendChild(rescueLeft);

        var rescueRight = node('div', 'settings-rescue-right');
        rescueRight.appendChild(annotate(
            button('打开伤害对账日志', 'settings-button secondary settings-damage-ledger-open', function(event) {
                openDamageLedger(event.currentTarget);
            }),
            '暂停查看本场景最近的精确逐段伤害记录（最多 32768 段），不占用任何战斗键。',
            'left'));
        rescueStrip.appendChild(rescueRight);
        home.appendChild(rescueStrip);

        // 2. 主体两栏驾驶舱（左：声音 / 性能预设 / 打击伤害数字；右：镜头缩放行内实时预览）
        var cockpit = node('div', 'settings-cockpit-grid');
        var leftCol = node('div', 'settings-cockpit-left');

        // 2a. 声音卡片
        var sfxInlineWrap = node('label', 'settings-inline-switch');
        sfxInlineWrap.appendChild(node('span', '', '界面音效'));
        sfxInlineWrap.appendChild(toggleSwitchInput(_snapshot.hostPrefs.sfxEnabled === true, function(val, input) {
            setHostPreference('sfxEnabled', val, input, 'Web 界面音效已' + (val ? '开启' : '关闭'));
        }, 'sfxEnabled'));
        annotate(sfxInlineWrap, '控制启动器与 Web 面板按钮提示音，立即保存于本机。', 'bottom');

        var auditionBtn = annotate(
            button('试听界面音效', 'settings-button secondary settings-audition-tile', function() {
                previewAudio('sfx');
            }),
            '按当前总音量与音乐音量草稿试听提示音。',
            'bottom');

        var audioCard = section('声音', '', {
            compact: true,
            scope: 'save',
            actions: [sfxInlineWrap, auditionBtn]
        });
        audioCard.classList.add('settings-cockpit-card');
        var audioControls = node('div', 'settings-audio-grid');
        audioControls.appendChild(volumeField('setGlobalVolume', '总音量'));
        audioControls.appendChild(volumeField('setBGMVolume', '音乐音量'));
        audioCard.appendChild(audioControls);
        leftCol.appendChild(audioCard);

        // 2b. 性能预设快切卡片
        var perfState = _snapshot.hostPrefs.performance;
        var perfActions = [];
        if (perfState && perfState.previous) {
            var quickUndoBtn = annotate(
                button('撤销', 'settings-link-btn settings-quick-perf-undo', function() {
                    quickApplyPerformanceUndo();
                }),
                '恢复上一次保存前的性能方案。',
                'bottom');
            quickUndoBtn.disabled = _busy || _requiresReconcile || _performanceBusy;
            perfActions.push(quickUndoBtn);
        }
        var perfDirtyDot = perfState && _performanceDraft
            && SettingsRuntime.hasPerformanceChanges(perfState, _performanceDraft);
        perfActions.push(button(perfDirtyDot ? '高阶画质(有草稿) →' : '高阶画质 →', 'settings-link-btn', function() {
            showTab('visual', '.settings-performance');
        }));
        var perfCard = section('性能预设', '', {compact: true, scope: 'local', actions: perfActions});
        perfCard.classList.add('settings-cockpit-card', 'settings-quick-perf');
        if (perfState) {
            var perfSeg = segmentedGroup(PERF_PRESETS, perfState.current.preset, function(nextPreset) {
                quickApplyPerformancePreset(nextPreset);
            }, 'settings-seg-three settings-perf-preset-seg');
            perfCard.appendChild(perfSeg);
            var perfSub = node('p', 'settings-card-footnote',
                '当前生效：' + performanceLabel(perfState.current));
            perfCard.appendChild(perfSub);
        } else {
            perfCard.appendChild(node('p', 'settings-card-footnote', '性能方案暂不可用，请重新打开设置。'));
        }
        leftCol.appendChild(perfCard);

        // 2c. 打击伤害数字快切卡片
        var hitJump = button('实时弹幕预览 →', 'settings-link-btn', function() {
            showTab('visual', '.settings-hit-sandbox');
        });
        var hitCard = section('打击伤害数字', '', {compact: true, scope: 'local', actions: [hitJump]});
        hitCard.classList.add('settings-cockpit-card', 'settings-quick-hit');
        var currentHitMode = _snapshot.hostPrefs.hitNumberMode || 'balanced';
        var hitDescLine = node('p', 'settings-card-footnote settings-hit-mode-desc', hitModeMeta(currentHitMode).desc);
        var hitSeg = segmentedGroup(
            HIT_MODES.map(function(m) { return {value: m.value, label: m.short, tooltip: m.desc}; }),
            currentHitMode,
            function(nextMode, btn, group) {
                hitDescLine.textContent = hitModeMeta(nextMode).desc;
                setHostPreference('hitNumberMode', nextMode, group, '打击伤害数字：' + hitModeMeta(nextMode).short);
            },
            'settings-seg-five',
            'hitNumberMode'
        );
        hitCard.appendChild(hitSeg);
        hitCard.appendChild(hitDescLine);
        leftCol.appendChild(hitCard);
        cockpit.appendChild(leftCol);

        // 2d. 右栏：镜头缩放卡片（行内缩略实时预览 + 直接可调滑杆与动态开关）
        var fullPreviewBtn = annotate(
            button('打开镜头预览', 'settings-button primary settings-camera-open', function(event) {
                openCameraSimulator(event.currentTarget);
            }),
            '展开全屏静态画面模拟精调基础镜头倍率。',
            'left');
        var cameraCard = section('镜头缩放', '', {compact: true, scope: 'save', actions: [fullPreviewBtn]});
        cameraCard.classList.add('settings-cockpit-card', 'settings-camera-entry');

        var inlineViewport = node('div', 'settings-camera-inline-viewport');
        if (_flashPreview) {
            _inlineCameraImage = document.createElement('img');
            _inlineCameraImage.src = _flashPreview.dataUrl;
            _inlineCameraImage.alt = '进入设置时捕获的游戏静态画面缩略预览';
            _inlineCameraImage.draggable = false;
            inlineViewport.appendChild(_inlineCameraImage);
        } else {
            _inlineCameraImage = null;
            inlineViewport.appendChild(node('p', 'settings-camera-unavailable', '本次入口未取得静态画面'));
        }
        _inlineCameraHud = node('output', 'settings-camera-inline-hud',
            Number(_draft.settings.basicZoomScale).toFixed(1) + '×');
        inlineViewport.appendChild(_inlineCameraHud);
        _inlineCameraSafeFrame = node('span', 'settings-camera-safe-frame');
        inlineViewport.appendChild(_inlineCameraSafeFrame);
        _inlineCameraHudBand = node('span', 'settings-camera-hud-band');
        inlineViewport.appendChild(_inlineCameraHudBand);
        cameraCard.appendChild(inlineViewport);

        var camControls = node('div', 'settings-camera-inline-controls');
        var zoomRow = node('div', 'settings-camera-zoom-row');
        var inlineZoomControl = rangeControl('basicZoomScale', 0.5, 3, 0.1, updateCameraPreview);
        zoomRow.appendChild(field('基础倍率', inlineZoomControl));
        var resetZoomBtn = annotate(
            button('1.0×', 'settings-button secondary settings-camera-reset-inline', function() {
                _draft.settings.basicZoomScale = 1;
                var range = inlineZoomControl.querySelector('input[type="range"]');
                var out = inlineZoomControl.querySelector('output');
                if (range) range.value = '1';
                if (out) out.textContent = '1.0×';
                changed();
                updateCameraPreview();
            }),
            '恢复基础镜头倍率为 1.0×。',
            'top');
        zoomRow.appendChild(resetZoomBtn);
        camControls.appendChild(zoomRow);
        camControls.appendChild(checkbox(
            'cameraZoomToggle',
            '动态镜头调节',
            '关闭时固定应用基础倍率；开启后战斗中可围绕基础倍率动态缩放。',
            updateCameraPreview));
        cameraCard.appendChild(camControls);
        cockpit.appendChild(cameraCard);

        home.appendChild(cockpit);

        // 3. 底部单行作弊码命令条
        var cheatBar = node('section', 'settings-home-cheat-bar term-card');
        var cheatTag = node('div', 'settings-cheat-bar-tag');
        cheatTag.appendChild(node('span', 'settings-section-code', 'COMMAND'));
        cheatTag.appendChild(node('strong', '', '作弊码'));
        cheatBar.appendChild(cheatTag);
        cheatBar.appendChild(cheatCommandForm());
        home.appendChild(cheatBar);

        _content.appendChild(home);
        updateCameraPreview();
    }

    // ══════════════════════════════════════════════════════════════
    // 页签 2：画面与战斗（实时弹幕沙盒 + 完整性能/画质 + Andy Law 双立绘 + HUD 动效）
    // ══════════════════════════════════════════════════════════════
    function renderVisual() {
        // 1. 打击伤害数字 · 实时弹幕预览沙盒
        renderHitNumberSandboxSection();

        // 2. 性能方案（完整草稿闭环）+ 画面增强（CAS / 动态模糊）
        renderPerformanceSection();

        // 3. 游戏内画面开关 + Andy Law 对话立绘双图实拍对比
        renderWorldAndPortraitSection();

        // 4. 战斗信息 HUD 动效强度 + 纯 CSS 迷你血条示意
        renderHudMotionSection();
    }

    function renderHitNumberSandboxSection() {
        var ledgerBtn = annotate(
            button('打开伤害对账日志', 'settings-button secondary settings-damage-ledger-open', function(event) {
                openDamageLedger(event.currentTarget);
            }),
            '暂停查看本场景最近的精确逐段记录；最多保留 32768 段，溢出会明确标记。',
            'left');
        var box = section('打击伤害数字 · 实时弹幕预览',
            '直接驱动 Host 生产伤害数字管线的隔离沙盒，实时对照 5 种模式、多种弹幕密度与世界行上限；不污染战斗对账日志，也不占用任何战斗键。',
            {scope: 'local', actions: [ledgerBtn]});
        box.classList.add('settings-hit-sandbox');

        var grid = node('div', 'settings-hit-sandbox-grid');
        var controls = node('div', 'settings-hit-sandbox-controls');

        // 显示模式 5 档
        var modeBlock = node('div', 'settings-control-group');
        modeBlock.appendChild(node('span', 'settings-control-label', '显示行为'));
        var currentMode = _snapshot.hostPrefs.hitNumberMode || 'balanced';
        var modeDesc = node('p', 'settings-control-desc', hitModeMeta(currentMode).desc);
        var modeSeg = segmentedGroup(
            HIT_MODES.map(function(m) { return {value: m.value, label: m.short, tooltip: m.desc}; }),
            currentMode,
            function(nextMode, btn, group) {
                modeDesc.textContent = hitModeMeta(nextMode).desc;
                setHostPreference('hitNumberMode', nextMode, group, '打击伤害数字：' + hitModeMeta(nextMode).short, function() {
                    restartHitPreviewImmediate();
                });
            },
            'settings-seg-five',
            'hitNumberMode'
        );
        modeBlock.appendChild(modeSeg);
        modeBlock.appendChild(modeDesc);
        controls.appendChild(modeBlock);

        // 弹幕预设选择
        var presets = (_hitNumberPreview && _hitNumberPreview.presets) || [
            {id: 'light', label: '常规连射', description: '单发与 4 段联弹混伤，含暴击/属性/护盾/吸血', durationMs: 3600, representativeTimeMs: 1450},
            {id: 'barrage', label: '高密弹幕', description: '持续 60 段/秒爆发流，直观对比聚合与行数上限', durationMs: 4000, representativeTimeMs: 1850},
            {id: 'crowd', label: '多目标混战', description: '近邻多目标交叉受击，对照目标归属与指向标记', durationMs: 3600, representativeTimeMs: 1700},
            {id: 'healing', label: '伤害与治疗', description: '持续治疗窗口、敌方回血与同屏伤害混流', durationMs: 4400, representativeTimeMs: 1800}
        ];
        if (!presets.some(function(p) { return p.id === _hitPreviewState.presetId; })) {
            _hitPreviewState.presetId = presets[0].id;
        }
        var currentPreset = presets.filter(function(p) { return p.id === _hitPreviewState.presetId; })[0] || presets[0];

        var presetBlock = node('div', 'settings-control-group');
        presetBlock.appendChild(node('span', 'settings-control-label', '弹幕预设场景'));
        var presetDesc = node('p', 'settings-control-desc', currentPreset.description);
        var presetSeg = segmentedGroup(
            presets.map(function(p) { return {value: p.id, label: p.label, tooltip: p.description}; }),
            _hitPreviewState.presetId,
            function(nextId, btn, group) {
                _hitPreviewState.presetId = nextId;
                _hitPreviewState.timeMs = _hitPreviewState.paused ? getPresetRepresentativeTime(nextId) : 0;
                var found = presets.filter(function(p) { return p.id === nextId; })[0];
                if (found) presetDesc.textContent = found.description;
                syncSegmentedGroup(group, nextId);
                restartHitPreviewImmediate();
            },
            'settings-seg-four'
        );
        presetBlock.appendChild(presetSeg);
        presetBlock.appendChild(presetDesc);
        controls.appendChild(presetBlock);

        // 世界攻击行上限（快捷芯片 + 精确数字框）
        var limitBlock = node('div', 'settings-control-group');
        var limitHeader = node('div', 'settings-limit-header');
        limitHeader.appendChild(node('span', 'settings-control-label', '世界攻击行上限'));
        var limitChips = node('div', 'settings-limit-chips');
        var currentLimit = Number(_snapshot.hostPrefs.hitNumberWorldRowLimit);
        var limitInput = document.createElement('input');
        limitInput.type = 'number';
        limitInput.className = 'settings-select settings-limit-input';
        limitInput.min = '0';
        limitInput.max = '1000';
        limitInput.step = '1';
        limitInput.value = String(currentLimit);
        limitInput.setAttribute('data-host-key', 'hitNumberWorldRowLimit');
        annotate(limitInput, '0 表示真正无限制；非零值同时限制全局攻击行，逐发模式每目标最多保留最新 6 行，不影响独立对账日志。', 'bottom');

        function syncLimitChips(val) {
            var nodes = limitChips.querySelectorAll('.settings-chip-btn');
            for (var i = 0; i < nodes.length; i++) {
                nodes[i].classList.toggle('active', Number(nodes[i].getAttribute('data-limit')) === Number(val));
            }
        }
        [[0, '不限'], [12, '12'], [24, '24'], [48, '48']].forEach(function(pair) {
            var chip = node('button', 'settings-chip-btn', pair[1]);
            chip.type = 'button';
            chip.setAttribute('data-limit', String(pair[0]));
            chip.classList.toggle('active', currentLimit === pair[0]);
            chip.addEventListener('click', function() {
                limitInput.value = String(pair[0]);
                syncLimitChips(pair[0]);
                setHostPreference('hitNumberWorldRowLimit', pair[0], limitInput,
                    pair[0] === 0 ? '世界攻击行上限：无限制' : '世界攻击行上限：' + pair[0],
                    function() { restartHitPreviewImmediate(); });
            });
            limitChips.appendChild(chip);
        });
        limitInput.addEventListener('change', function() {
            if (limitInput.value.trim() === '') {
                applyHostControlValue(limitInput, 'hitNumberWorldRowLimit', _snapshot.hostPrefs.hitNumberWorldRowLimit);
                syncLimitChips(_snapshot.hostPrefs.hitNumberWorldRowLimit);
                return;
            }
            var value = Number(limitInput.value);
            if (!Number.isInteger(value) || value < 0 || value > 1000) {
                applyHostControlValue(limitInput, 'hitNumberWorldRowLimit', _snapshot.hostPrefs.hitNumberWorldRowLimit);
                syncLimitChips(_snapshot.hostPrefs.hitNumberWorldRowLimit);
                return;
            }
            syncLimitChips(value);
            setHostPreference('hitNumberWorldRowLimit', value, limitInput,
                value === 0 ? '世界攻击行上限：无限制' : '世界攻击行上限：' + value,
                function() { restartHitPreviewImmediate(); });
        });
        limitHeader.appendChild(limitChips);
        limitHeader.appendChild(limitInput);
        limitBlock.appendChild(limitHeader);
        controls.appendChild(limitBlock);

        // 播放控制条
        var playbackRow = node('div', 'settings-hit-playback-row');
        var pauseBtn = button(_hitPreviewState.paused ? '播放预览' : '暂停', 'settings-button secondary', function() {
            _hitPreviewState.paused = !_hitPreviewState.paused;
            pauseBtn.textContent = _hitPreviewState.paused ? '播放预览' : '暂停';
            _hitPreviewState.lastTickAt = performance.now();
            if (!_hitPreviewState.paused) scheduleNextHitPreviewFrame(0);
        });
        playbackRow.appendChild(pauseBtn);
        playbackRow.appendChild(button('重播', 'settings-button secondary', function() {
            _hitPreviewState.timeMs = 0;
            _hitPreviewState.lastTickAt = performance.now();
            restartHitPreviewImmediate();
        }));
        if (_flashPreview) {
            var bgBtn = button(_hitPreviewState.useGameBg ? '底图：当前画面' : '底图：暗场网格',
                'settings-button secondary', function() {
                    _hitPreviewState.useGameBg = !_hitPreviewState.useGameBg;
                    bgBtn.textContent = _hitPreviewState.useGameBg ? '底图：当前画面' : '底图：暗场网格';
                    if (_hitPreviewStage) _hitPreviewStage.classList.toggle('use-game-bg', _hitPreviewState.useGameBg);
                });
            playbackRow.appendChild(bgBtn);
        }
        controls.appendChild(playbackRow);
        grid.appendChild(controls);

        // 右侧 16:9 实时预览舞台
        var stageWrap = node('div', 'settings-hit-stage-wrap');
        var stage = node('div', 'settings-hit-stage');
        if (_hitPreviewState.useGameBg && _flashPreview) stage.classList.add('use-game-bg');
        _hitPreviewStage = stage;

        if (_flashPreview) {
            var bgImg = document.createElement('img');
            bgImg.className = 'settings-hit-stage-bg';
            bgImg.src = _flashPreview.dataUrl;
            bgImg.alt = '';
            bgImg.draggable = false;
            stage.appendChild(bgImg);
        }

        var canLiveRender = !!(_hitNumberPreview || typeof _config.renderMockHitPreviewFrame === 'function');
        if (canLiveRender) {
            var canvas = document.createElement('canvas');
            canvas.className = 'settings-hit-preview-canvas';
            canvas.width = (_hitNumberPreview && _hitNumberPreview.width) || 512;
            canvas.height = (_hitNumberPreview && _hitNumberPreview.height) || 288;
            stage.appendChild(canvas);
            _hitPreviewCanvas = canvas;
        } else {
            _hitPreviewCanvas = null;
            var fallback = node('div', 'settings-hit-fallback');
            fallback.appendChild(node('strong', '', '实时沙盒未就绪'));
            fallback.appendChild(node('p', '', '当前运行宿主未开启实时伤害数字预览端点，已保留完整显示模式与世界行上限配置。'));
            stage.appendChild(fallback);
        }

        _hitPreviewTelemetry = node('div', 'settings-hit-telemetry',
            canLiveRender ? '正在连接 Host 生产沙盒…' : '降级模式 · 仅配置偏好');
        stage.appendChild(_hitPreviewTelemetry);
        stageWrap.appendChild(stage);
        grid.appendChild(stageWrap);

        box.appendChild(grid);
        _content.appendChild(box);

        if (canLiveRender) {
            startHitPreviewLoop();
        }
    }

    function getPresetMeta(id) {
        var list = (_hitNumberPreview && _hitNumberPreview.presets) || [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id) return list[i];
        }
        return {id: id || 'barrage', durationMs: 4000, representativeTimeMs: 1850};
    }

    function getPresetRepresentativeTime(id) {
        return getPresetMeta(id).representativeTimeMs;
    }

    function startHitPreviewLoop() {
        stopHitPreviewLoop(true);
        _hitPreviewToken++;
        if (_hitPreviewState.paused && _hitPreviewState.timeMs === 0) {
            _hitPreviewState.timeMs = getPresetRepresentativeTime(_hitPreviewState.presetId);
        }
        _hitPreviewState.lastTickAt = performance.now();
        requestHitPreviewFrame(_hitPreviewToken);
    }

    function restartHitPreviewImmediate() {
        if (!_hitPreviewCanvas || _activeTab !== 'visual') return;
        stopHitPreviewLoop(true);
        _hitPreviewToken++;
        _hitPreviewState.lastTickAt = performance.now();
        requestHitPreviewFrame(_hitPreviewToken);
    }

    function stopHitPreviewLoop(keepDomRefs) {
        _hitPreviewToken++;
        if (_hitPreviewTimer) clearTimeout(_hitPreviewTimer);
        _hitPreviewTimer = null;
        if (_hitPreviewAbort) {
            try { _hitPreviewAbort.abort(); } catch (err) {}
            _hitPreviewAbort = null;
        }
        _hitPreviewInFlight = false;
        if (!keepDomRefs) {
            _hitPreviewCanvas = null;
            _hitPreviewTelemetry = null;
            _hitPreviewStage = null;
        }
    }

    function scheduleNextHitPreviewFrame(delayMs) {
        if (_hitPreviewState.paused || !_hitPreviewCanvas || _activeTab !== 'visual') return;
        var token = _hitPreviewToken;
        if (_hitPreviewTimer) clearTimeout(_hitPreviewTimer);
        _hitPreviewTimer = setTimeout(function() {
            _hitPreviewTimer = null;
            if (token !== _hitPreviewToken || !_hitPreviewCanvas || _activeTab !== 'visual') return;
            var now = performance.now();
            var dt = Math.min(120, Math.max(16, now - (_hitPreviewState.lastTickAt || now)));
            _hitPreviewState.lastTickAt = now;
            var meta = getPresetMeta(_hitPreviewState.presetId);
            var duration = meta.durationMs || 4000;
            _hitPreviewState.timeMs = (_hitPreviewState.timeMs + Math.round(dt)) % duration;
            requestHitPreviewFrame(token);
        }, Math.max(16, delayMs || 42));
    }

    function updateHitPreviewTelemetry() {
        if (!_hitPreviewTelemetry || !_snapshot) return;
        var mode = _snapshot.hostPrefs.hitNumberMode || 'balanced';
        if (mode === 'off') {
            _hitPreviewTelemetry.textContent = '已关闭战斗飘字 · 战斗对账日志仍可用';
            return;
        }
        if (_hitPreviewState.error) {
            _hitPreviewTelemetry.textContent = '预览暂不可用：' + _hitPreviewState.error;
            return;
        }
        var label = hitModeMeta(mode).short;
        var limit = Number(_snapshot.hostPrefs.hitNumberWorldRowLimit);
        var limitText = limit === 0 ? '不限' : String(limit);
        _hitPreviewTelemetry.textContent = label + ' · 可见行 ' + _hitPreviewState.activeRows
            + (_hitPreviewState.omittedRows > 0 ? ' · 已裁剪 ' + _hitPreviewState.omittedRows : '')
            + ' · 上限 ' + limitText
            + (_hitPreviewState.paused ? ' · 已暂停' : '');
    }

    function requestHitPreviewFrame(token) {
        if (!_hitPreviewCanvas || !_snapshot || _hitPreviewInFlight || token !== _hitPreviewToken) return;
        var mode = _snapshot.hostPrefs.hitNumberMode || 'balanced';
        var limit = Number(_snapshot.hostPrefs.hitNumberWorldRowLimit);
        if (!Number.isInteger(limit) || limit < 0 || limit > 1000) limit = 24;
        var presetId = _hitPreviewState.presetId || 'barrage';
        var timeMs = Math.max(0, Math.floor(_hitPreviewState.timeMs || 0));

        // 独立浏览器 harness 钩子（无 WebView2 Host 时用于渲染模拟预览帧）
        if (typeof _config.renderMockHitPreviewFrame === 'function') {
            var mockResult = _config.renderMockHitPreviewFrame(_hitPreviewCanvas, {
                mode: mode, presetId: presetId, limit: limit, timeMs: timeMs
            });
            _hitPreviewState.activeRows = (mockResult && mockResult.rows) || 0;
            _hitPreviewState.omittedRows = (mockResult && mockResult.omitted) || 0;
            _hitPreviewState.error = '';
            updateHitPreviewTelemetry();
            if (!_hitPreviewState.paused) scheduleNextHitPreviewFrame(42);
            return;
        }

        if (!_hitNumberPreview || !_instance) return;
        var url = _hitNumberPreview.origin + '/frame?instance=' + encodeURIComponent(_instance)
            + '&preset=' + encodeURIComponent(presetId)
            + '&mode=' + encodeURIComponent(mode)
            + '&limit=' + encodeURIComponent(String(limit))
            + '&t=' + encodeURIComponent(String(timeMs))
            + '&w=' + encodeURIComponent(String(_hitPreviewCanvas.width))
            + '&h=' + encodeURIComponent(String(_hitPreviewCanvas.height))
            + '&targets=1';

        _hitPreviewInFlight = true;
        var controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
        _hitPreviewAbort = controller;
        var startedAt = performance.now();

        fetch(url, {cache: 'no-store', signal: controller ? controller.signal : undefined})
            .then(function(response) {
                if (!response.ok) throw new Error('HTTP ' + response.status);
                var rowsHeader = Number(response.headers.get('X-CF7-HitPreview-Rows') || 0);
                var omittedHeader = Number(response.headers.get('X-CF7-HitPreview-Omitted') || 0);
                return response.blob().then(function(blob) {
                    return {blob: blob, rows: rowsHeader, omitted: omittedHeader};
                });
            })
            .then(function(pack) {
                if (token !== _hitPreviewToken || !_hitPreviewCanvas) return;
                if (typeof createImageBitmap === 'function') {
                    return createImageBitmap(pack.blob).then(function(bitmap) {
                        if (token !== _hitPreviewToken || !_hitPreviewCanvas) {
                            try { bitmap.close(); } catch (err) {}
                            return;
                        }
                        var ctx = _hitPreviewCanvas.getContext('2d');
                        ctx.clearRect(0, 0, _hitPreviewCanvas.width, _hitPreviewCanvas.height);
                        ctx.drawImage(bitmap, 0, 0, _hitPreviewCanvas.width, _hitPreviewCanvas.height);
                        try { bitmap.close(); } catch (err) {}
                        _hitPreviewState.activeRows = pack.rows;
                        _hitPreviewState.omittedRows = pack.omitted;
                        _hitPreviewState.error = '';
                        updateHitPreviewTelemetry();
                    });
                }
            })
            .catch(function(err) {
                if (token !== _hitPreviewToken) return;
                if (err && err.name === 'AbortError') return;
                _hitPreviewState.error = '渲染中断';
                updateHitPreviewTelemetry();
            })
            .finally(function() {
                if (_hitPreviewAbort === controller) _hitPreviewAbort = null;
                _hitPreviewInFlight = false;
                if (token !== _hitPreviewToken || !_hitPreviewCanvas) return;
                var elapsed = performance.now() - startedAt;
                if (!_hitPreviewState.paused && !_hitPreviewState.error) {
                    scheduleNextHitPreviewFrame(Math.max(16, 42 - elapsed));
                }
            });
    }

    function renderPerformanceSection() {
        var group = section('性能方案与画面增强',
            '性能方案保存在这台电脑。修改下方高级项后点击“应用方案”；底部“应用并保存”只处理游戏存档设置与键位。',
            {scope: 'local'});
        group.classList.add('settings-performance');
        var state = _snapshot.hostPrefs.performance;
        if (!state || !_performanceDraft) {
            group.appendChild(node('p', 'settings-performance-message', '性能方案暂不可用，请重新打开设置。'));
        } else {
            var fields = node('div', 'settings-grid three settings-performance-fields');
            fields.appendChild(performanceSelect('preset', '推荐方案',
                [['balanced', '通用'], ['performance', '性能'], ['quality', '画质']],
                '通用兼顾流畅与清晰，性能优先减少绘制负担，画质优先保留清晰度。切换方案不会清除手动分辨率上限。'));
            fields.appendChild(performanceSelect('mode', '调节方式', [['auto', '自动'], ['fixed', '固定']],
                '自动按游戏运行速度调整。固定保持该方案允许的最高完整档位，绘制尺寸仍受手动上限、当前窗口与显示缩放限制。'));
            fields.appendChild(performanceSelect('maxRenderHeight', '绘制高度上限',
                SettingsRuntime.PERFORMANCE_HEIGHTS.map(function(value) {
                    return [value, value === 0 ? '方案默认上限' : '最高 ' + value + 'p'];
                }), '只限制游戏内部绘制高度，不改变窗口大小。实际绘制状态可查看顶部性能显示。'));
            group.appendChild(fields);

            var statusBar = node('div', 'settings-performance-bar');
            statusBar.appendChild(node('p', 'settings-performance-saved', '已保存：' + performanceLabel(state.current)));
            var actions = node('div', 'settings-inline-actions settings-performance-actions');
            actions.appendChild(annotate(button('恢复推荐值', 'settings-button secondary settings-performance-reset', function() {
                if (_busy || _requiresReconcile) return;
                _performanceDraft = SettingsRuntime.recommendedPerformanceConfig(_performanceDraft);
                _performanceMessage = '已恢复自动调节；所选方案和分辨率上限保留，应用后保存。';
                _performanceMessageState = 'ready';
                refreshPerformanceControls();
            }), '将当前方案的调节方式恢复为自动，保留所选方案和手动分辨率上限；尚未保存。', 'top'));
            actions.appendChild(annotate(button('撤销上次应用', 'settings-button secondary settings-performance-undo', function() {
                savePerformance(true);
            }), '恢复上一次保存前的整组性能方案，只影响本机性能设置。', 'top'));
            actions.appendChild(button('应用方案', 'settings-button primary settings-performance-apply', function() {
                savePerformance(false);
            }));
            statusBar.appendChild(actions);
            group.appendChild(statusBar);

            var message = node('p', 'settings-performance-message');
            message.setAttribute('role', 'status');
            group.appendChild(message);
        }

        if (_snapshot.hostPrefs.imageEnhancementAvailable) {
            var enhanceBlock = node('div', 'settings-subband');
            enhanceBlock.appendChild(node('h3', 'settings-subband-title', '后处理画面增强（修改即刻保存）'));
            var imageGrid = node('div', 'settings-grid two');
            imageGrid.appendChild(hostBoolean('casEnabled', '清晰度增强',
                '温和锐化世界画面，界面文字保持清晰不变'));
            imageGrid.appendChild(hostBoolean('motionFeedbackEnabled', '动态模糊',
                '加入短时运动残影，高速移动时可能略降辨识度'));
            enhanceBlock.appendChild(imageGrid);
            group.appendChild(enhanceBlock);
        }

        _content.appendChild(group);
        refreshPerformanceControls();
    }

    function renderWorldAndPortraitSection() {
        var box = section('游戏内画面与立绘',
            '以下设置归属角色存档，修改后点击右下角“应用并保存”生效并落盘。',
            {scope: 'save'});
        box.classList.add('settings-visual-game');

        var split = node('div', 'settings-world-portrait-grid');

        // 左：阴影 / 视觉元素 / 昼夜循环与从属开关
        var toggles = node('div', 'settings-world-toggles');
        toggles.appendChild(checkbox('是否阴影', '角色阴影', '', null, '关闭可在大量单位同屏时减轻 Flash 绘制压力'));
        toggles.appendChild(checkbox('是否视觉元素', '场景视觉元素', '', null, '控制场景装饰特效与部分非关键粒子'));

        var dayNightOn = _draft.settings['开启昼夜系统'] === true;
        toggles.appendChild(checkbox('开启昼夜系统', '昼夜循环', '', function() {
            renderCurrentTab();
        }, '开启场景日夜时间推进与环境色温变化'));

        var pauseRow = checkbox('暂停昼夜系统', '暂停昼夜变化', '', null,
            dayNightOn ? '冻结当前时段光影，不再随时间推移变化' : '需先开启上方的“昼夜循环”');
        pauseRow.classList.add('settings-field-subordinate');
        var pauseInput = pauseRow.querySelector('input[type="checkbox"]');
        if (pauseInput) pauseInput.disabled = !dayNightOn;
        pauseRow.classList.toggle('is-disabled', !dayNightOn);
        toggles.appendChild(pauseRow);
        split.appendChild(toggles);

        // 右：Andy Law 对话立绘风格双图实拍对比（直读已随包 dialogue-portraits）
        var portraitWrap = node('div', 'settings-portrait-picker');
        var portraitHead = node('div', 'settings-portrait-head');
        portraitHead.appendChild(node('strong', '', 'Andy Law 对话立绘风格'));
        portraitHead.appendChild(node('span', '', '仅影响剧情对话中 Andy Law 的立绘版本'));
        portraitWrap.appendChild(portraitHead);

        var cards = node('div', 'settings-portrait-cards');
        var currentType = Number(_draft.settings['立绘类型']) === 2 ? 2 : 1;
        [
            {value: 1, title: '风格 1 · 默认立绘', expr: '普通'},
            {value: 2, title: '风格 2 · 备选立绘', expr: '普通2'}
        ].forEach(function(item) {
            var card = node('button', 'settings-portrait-card');
            card.type = 'button';
            card.setAttribute('data-portrait-type', String(item.value));
            card.classList.toggle('active', currentType === item.value);
            card.setAttribute('aria-pressed', currentType === item.value ? 'true' : 'false');

            var frame = node('div', 'settings-portrait-frame');
            var canvas = document.createElement('canvas');
            canvas.width = 160;
            canvas.height = 128;
            canvas.className = 'settings-portrait-canvas';
            frame.appendChild(canvas);
            var fallbackText = node('span', 'settings-portrait-fallback', '类型 ' + item.value);
            frame.appendChild(fallbackText);
            card.appendChild(frame);
            card.appendChild(node('span', 'settings-portrait-label', item.title));

            card.addEventListener('click', function() {
                _draft.settings['立绘类型'] = item.value;
                changed();
                var siblings = cards.querySelectorAll('.settings-portrait-card');
                for (var i = 0; i < siblings.length; i++) {
                    var active = Number(siblings[i].getAttribute('data-portrait-type')) === item.value;
                    siblings[i].classList.toggle('active', active);
                    siblings[i].setAttribute('aria-pressed', active ? 'true' : 'false');
                }
                cue('activate');
            });
            cards.appendChild(card);
            hydrateAndyLawPortrait(canvas, fallbackText, item.expr);
        });
        portraitWrap.appendChild(cards);
        split.appendChild(portraitWrap);

        box.appendChild(split);
        _content.appendChild(box);
    }

    function dialoguePortraitBaseUrl() {
        if (_config.dialoguePortraitBaseUrl) return String(_config.dialoguePortraitBaseUrl);
        return 'assets/dialogue-portraits/';
    }

    function loadPortraitManifest() {
        if (_portraitManifestCache) return Promise.resolve(_portraitManifestCache);
        if (_portraitManifestPromise) return _portraitManifestPromise;
        _portraitManifestPromise = fetch(dialoguePortraitBaseUrl() + 'manifest.json', {cache: 'no-cache'})
            .then(function(resp) { return resp.ok ? resp.json() : null; })
            .then(function(data) { _portraitManifestCache = data; return data; })
            .catch(function() { return null; });
        return _portraitManifestPromise;
    }

    function hydrateAndyLawPortrait(canvas, fallbackEl, expressionKey) {
        loadPortraitManifest().then(function(manifest) {
            if (!manifest || !manifest.entries || !manifest.entries['Andy Law']
                || !document.documentElement.contains(canvas)) return;
            var expr = manifest.entries['Andy Law'].expressions
                && manifest.entries['Andy Law'].expressions[expressionKey];
            if (!expr || !expr.uri) return;
            var img = new Image();
            img.onload = function() {
                if (!document.documentElement.contains(canvas)) return;
                var ctx = canvas.getContext('2d');
                ctx.clearRect(0, 0, canvas.width, canvas.height);
                var b = expr.bounds || {x: 0, y: 0, width: img.naturalWidth, height: img.naturalHeight};
                // 聚焦角色上半身/胸像区，保证两种构图比例都能清晰对比人物风格
                var cropW = Math.min(b.width, Math.max(b.width * 0.88, b.height * 0.95));
                var cropH = Math.min(b.height, cropW * (canvas.height / canvas.width));
                var sx = Math.max(0, b.x + (b.width - cropW) * 0.5);
                var sy = Math.max(0, b.y + b.height * 0.02);
                ctx.drawImage(img, sx, sy, cropW, cropH, 0, 0, canvas.width, canvas.height);
                if (fallbackEl) {
                    fallbackEl.hidden = true;
                    if (fallbackEl.parentNode) fallbackEl.parentNode.removeChild(fallbackEl);
                }
            };
            img.src = dialoguePortraitBaseUrl() + expr.uri;
        });
    }

    function renderHudMotionSection() {
        var box = section('战斗信息动效',
            '只调整原生 HUD 界面反馈强度；生命、护盾、冷却和按键提示始终实时更新。',
            {scope: 'local'});
        box.classList.add('settings-hud-motion');

        var row = node('div', 'settings-hud-motion-grid');
        var current = _snapshot.hostPrefs.hudMotionMode || 'full';
        var demo = node('div', 'settings-hud-demo');
        demo.setAttribute('data-motion', current);
        demo.appendChild(node('span', 'settings-hud-demo-label', '血条受击反馈示意'));
        var bar = node('div', 'settings-hud-demo-bar');
        bar.appendChild(node('span', 'settings-hud-demo-trail'));
        bar.appendChild(node('span', 'settings-hud-demo-fill'));
        demo.appendChild(bar);
        var modeCopy = node('p', 'settings-control-desc',
            (HUD_MOTION_MODES.filter(function(m) { return m.value === current; })[0] || HUD_MOTION_MODES[0]).desc);

        var left = node('div', 'settings-hud-motion-left');
        left.appendChild(segmentedGroup(
            HUD_MOTION_MODES.map(function(m) { return {value: m.value, label: m.label, tooltip: m.desc}; }),
            current,
            function(nextVal, btn, group) {
                demo.setAttribute('data-motion', nextVal);
                var meta = HUD_MOTION_MODES.filter(function(m) { return m.value === nextVal; })[0];
                if (meta) modeCopy.textContent = meta.desc;
                setHostPreference('hudMotionMode', nextVal, group, '战斗信息动效：' + (meta ? meta.label : nextVal));
            },
            'settings-seg-three',
            'hudMotionMode'
        ));
        left.appendChild(modeCopy);
        row.appendChild(left);
        row.appendChild(demo);
        box.appendChild(row);
        _content.appendChild(box);
    }

    // ══════════════════════════════════════════════════════════════
    // 页签 3：36 项权威键位（保持 1024×576 零滚动 + 搜索高亮）
    // ══════════════════════════════════════════════════════════════
    function renderKeys() {
        var validation = SettingsRuntime.validateKeyDraft(_draft.keys, _snapshot.allowedKeyCodes);
        var searchInput = document.createElement('input');
        searchInput.type = 'search';
        searchInput.className = 'settings-key-search';
        searchInput.placeholder = '筛查键位（如 技能 / 药剂 / 奔跑）';
        searchInput.value = _keyFilterQuery;
        searchInput.setAttribute('aria-label', '筛查键位');

        var actions = [];
        if (!validation.valid) {
            actions.push(node('span', 'settings-key-conflict-pill',
                '异常 ' + validation.indexes.length + ' 项'));
        }
        actions.push(searchInput);
        actions.push(annotate(
            button('恢复全部默认', 'settings-button secondary', resetKeys),
            '把全部 36 项恢复为默认键位；药剂组切换恢复为 6，仍需点击“应用并保存”。',
            'left'));

        var top = section('36 项权威键位',
            '点击一个键位后按新键。重复键、Esc 与 F1–F12 会被拒绝，不自动交换。',
            {compact: true, scope: 'save', actions: actions});
        top.classList.add('settings-key-summary');
        _content.appendChild(top);

        var groups = [
            {name: '移动与操作', start: 0, end: 7, columns: 2, side: 'left'},
            {name: '攻击模式', start: 7, end: 12, columns: 2, side: 'left'},
            {name: '快捷物品', start: 12, end: 17, columns: 3, side: 'left'},
            {name: '快捷技能', start: 17, end: 29, columns: 3, side: 'right'},
            {name: '战斗扩展', start: 29, end: 36, columns: 2, side: 'right'}
        ];
        var board = node('div', 'settings-key-board');
        var left = node('div', 'settings-key-column');
        var right = node('div', 'settings-key-column');
        groups.forEach(function(group) {
            var block = section(group.name, '', {compact: true});
            block.classList.add('settings-key-section');
            block.setAttribute('data-key-columns', String(group.columns));
            var list = node('div', 'settings-key-grid');
            for (var i = group.start; i < group.end; i++) list.appendChild(keyRow(i, validation));
            block.appendChild(list);
            (group.side === 'left' ? left : right).appendChild(block);
        });
        board.appendChild(left);
        board.appendChild(right);
        _content.appendChild(board);

        function applyKeyFilter() {
            var q = _keyFilterQuery.trim().toLowerCase();
            var rows = board.querySelectorAll('.settings-key-row');
            for (var i = 0; i < rows.length; i++) {
                var text = (rows[i].getAttribute('data-search') || '').toLowerCase();
                var hit = !q || text.indexOf(q) >= 0;
                rows[i].classList.toggle('is-match', !!q && hit);
                rows[i].classList.toggle('is-dimmed', !!q && !hit);
            }
        }
        searchInput.addEventListener('input', function() {
            _keyFilterQuery = searchInput.value;
            applyKeyFilter();
        });
        applyKeyFilter();
    }

    function keyRow(index, validation) {
        var row = _draft.keys[index];
        var el = node('div', 'settings-key-row');
        el.setAttribute('data-key-index', String(index));
        var keyText = SettingsRuntime.keyLabel(row.keyCode, _snapshot.allowedKeyCodes);
        el.setAttribute('data-search', (row.label || row.id) + ' ' + keyText);
        var invalid = validation && !validation.valid && validation.indexes.indexOf(index) >= 0;
        el.classList.toggle('invalid', invalid);
        if (invalid) el.setAttribute('aria-invalid', 'true');
        el.appendChild(node('span', 'settings-key-label', row.label || row.id));
        var capture = button(_capturing === index ? '等待…' : keyText, 'settings-key-button', function() {
            _capturing = index;
            cue('activate');
            renderCurrentTab();
        });
        capture.setAttribute('aria-label', _capturing === index
            ? row.label + '：等待新按键，Esc 取消'
            : row.label + '：当前为 ' + keyText);
        annotate(capture, _capturing === index
            ? '按下新的物理键；Esc 只取消本次捕获。'
            : '点击后按下新键；重复键、Esc 与 F1–F12 不会被接受。');
        capture.classList.toggle('capturing', _capturing === index);
        el.appendChild(capture);
        return el;
    }

    function onCaptureKey(event) {
        var pressed = Number(event.keyCode || event.which);
        if (pressed === 27 && _closeConfirmModal) {
            event.preventDefault(); event.stopPropagation();
            closeCloseConfirm(true); return;
        }
        if (pressed === 27 && _damageLedgerModal) {
            event.preventDefault(); event.stopPropagation();
            closeDamageLedger(true); return;
        }
        if (pressed === 27 && _cameraModal) {
            event.preventDefault(); event.stopPropagation();
            closeCameraSimulator(true); return;
        }
        if (pressed === 27 && _cheatModal) {
            event.preventDefault(); event.stopPropagation();
            closeCheatHelp(); return;
        }
        if (_capturing < 0 || !_draft || _activeTab !== 'keys') return;
        event.preventDefault(); event.stopPropagation();
        var code = pressed;
        if (code === 27) {
            _capturing = -1;
            setStatus('已取消键位捕获。', 'ready');
            renderCurrentTab();
            return;
        }
        var result = SettingsRuntime.validateKeyCandidate(
            _draft.keys, _capturing, code, _snapshot.allowedKeyCodes);
        if (!result.valid) {
            setStatus(result.error === 'key_conflict'
                ? '键位冲突：该物理键已经被另一项使用。'
                : '该键被保留或不受 Flash 支持，请换一个键。', 'error');
            cue('illegal');
            return;
        }
        var candidate = SettingsRuntime.copy(_draft.keys);
        candidate[_capturing].keyCode = code;
        _draft.keys = candidate;
        _capturing = -1;
        cue('success');
        changed();
        renderCurrentTab();
    }

    function resetKeys() {
        var byId = {};
        _snapshot.defaultKeys.forEach(function(row) { byId[row.id] = row.keyCode; });
        _draft.keys.forEach(function(row) { row.keyCode = byId[row.id]; });
        _capturing = -1;
        changed();
        renderCurrentTab();
    }

    // ══════════════════════════════════════════════════════════════
    // 页签 4：界面与音频（点歌器合并 + 习惯偏好 + 批量物品网格密度）
    // ══════════════════════════════════════════════════════════════
    function renderPrefs() {
        // 1. 点歌器设置（Flash 运行规则 + Web 磷光主题合并为一卡！）
        var jukebox = section('点歌器设置',
            '播放规则随角色存档保存；磷光屏主题保存在本机，重新打开点歌器即生效。');
        jukebox.classList.add('settings-jukebox-unified');

        var jRuleLabel = node('div', 'settings-subband-head');
        jRuleLabel.appendChild(node('h3', 'settings-subband-title', '播放规则'));
        var savePill = node('span', 'settings-scope-pill', '存档项');
        savePill.setAttribute('data-scope', 'save');
        jRuleLabel.appendChild(savePill);
        jukebox.appendChild(jRuleLabel);

        var jgrid = node('div', 'settings-grid three');
        jgrid.appendChild(checkbox('jukeboxOverride', '允许点歌覆盖'));
        jgrid.appendChild(checkbox('jukeboxTrueRandom', '真随机'));
        jgrid.appendChild(field('播放模式', selectControl('jukeboxPlayMode',
            [['singleLoop', '单曲循环'], ['albumLoop', '专辑循环'], ['playOnce', '播放一次']])));
        jukebox.appendChild(jgrid);

        var jThemeHead = node('div', 'settings-subband-head settings-subband');
        jThemeHead.appendChild(node('h3', 'settings-subband-title', '点歌器磷光屏主题'));
        var localPill = node('span', 'settings-scope-pill', '本机即时');
        localPill.setAttribute('data-scope', 'local');
        jThemeHead.appendChild(localPill);
        jukebox.appendChild(jThemeHead);

        var currentTheme = SettingsPreferences.read('cf7-jukebox-theme');
        var themeCards = node('div', 'settings-jukebox-themes');
        [
            {value: 'green', title: '绿磷屏', sub: '经典示波器冷绿辉光'},
            {value: 'amber', title: '琥珀磷屏', sub: '工业终端暖琥珀辉光'}
        ].forEach(function(item) {
            var card = node('button', 'settings-theme-card');
            card.type = 'button';
            card.setAttribute('data-theme-value', item.value);
            card.classList.toggle('active', currentTheme === item.value);
            card.setAttribute('aria-pressed', currentTheme === item.value ? 'true' : 'false');
            var screen = node('span', 'settings-theme-crt');
            screen.innerHTML = '<svg viewBox="0 0 120 26" aria-hidden="true">'
                + '<path d="M2 13 L20 13 L28 5 L36 21 L44 7 L54 19 L64 4 L74 22 L84 10 L92 16 L100 13 L118 13" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
            card.appendChild(screen);
            var copy = node('span', 'settings-theme-copy');
            copy.appendChild(node('b', '', item.title));
            copy.appendChild(node('small', '', item.sub));
            card.appendChild(copy);
            card.addEventListener('click', function() {
                if (SettingsPreferences.write('cf7-jukebox-theme', item.value)) {
                    var siblings = themeCards.querySelectorAll('.settings-theme-card');
                    for (var i = 0; i < siblings.length; i++) {
                        var active = siblings[i].getAttribute('data-theme-value') === item.value;
                        siblings[i].classList.toggle('active', active);
                        siblings[i].setAttribute('aria-pressed', active ? 'true' : 'false');
                    }
                    setStatus('已保存点歌器主题：' + item.title + '。', 'ready');
                    notifyToast('点歌器主题：' + item.title, 'success', true);
                    cue('success');
                } else {
                    setStatus('本机存储不可用，偏好未保存。', 'error');
                }
            });
            themeCards.appendChild(card);
        });
        jukebox.appendChild(themeCards);
        _content.appendChild(jukebox);

        // 2. 界面与音频偏好（本机即时：Host + 非密度 Web 偏好统一收纳）
        var habits = section('界面与音频偏好',
            '每一项在修改后立即保存于本机；小地图显示也可在局内顶部刘海屏随时快捷切换。',
            {scope: 'local'});
        habits.classList.add('settings-prefs-habits');
        var hgrid = node('div', 'settings-grid two');
        hgrid.appendChild(hostBoolean('sfxEnabled', 'Web 界面音效', '控制按钮点击、切换与提示反馈音'));
        hgrid.appendChild(hostBoolean('ambientEnabled', 'Web 环境音', '控制启动器前门与界面底噪氛围音'));
        hgrid.appendChild(webPrefSegmented('cf7.gobang.audio.muted', '五子棋音轨',
            [{value: '0', label: '开启'}, {value: '1', label: '静音'}]));
        hgrid.appendChild(hostSegmented('mapDisplayPreference', '小地图默认显示',
            [{value: 'auto', label: '自动'}, {value: 'compact', label: '紧凑'},
             {value: 'expanded', label: '展开'}, {value: 'off', label: '关闭'}]));
        hgrid.appendChild(hostBoolean('tutorialsAutoOpen', '自动打开教程页面',
            '关闭后改为顶部轻通知提醒，仍可从帮助页查阅'));
        hgrid.appendChild(hostBoolean('reducedPresentation', '精简演出',
            '跳过漫画运镜与界面结构淡入，开箱配给直接同帧呈现'));
        hgrid.appendChild(hostBoolean('introEnabled', '下次启动播放片头动画', '控制下次冷启动时是否播放开场片头'));
        hgrid.appendChild(webPrefSegmented('cf7.dialogueMode', '任务对话呈现',
            [{value: 'rich', label: '完整'}, {value: 'brief', label: '缩略'}]));
        hgrid.appendChild(webPrefSegmented('cf7.skills.loadoutConfirmationMode', '技能装配确认',
            [{value: 'safe', label: '逐步确认'}, {value: 'fast', label: '快捷确认'}]));
        hgrid.appendChild(webPrefSegmented('cf7.equipmentTuning.modConfirmationMode', '配件调制确认',
            [{value: 'safe', label: '逐步确认'}, {value: 'fast', label: '快捷确认'}]));
        habits.appendChild(hgrid);
        _content.appendChild(habits);

        // 3. 物品栏网格密度（微缩对照样片 + 一键全部紧凑/完整 + 9 面板逐项切换）
        var allPrefs = SettingsPreferences.list();
        var densityPrefs = allPrefs.filter(function(p) { return p.group === '物品密度'; });

        var batchCompactBtn = button('全部设为紧凑', 'settings-button secondary', function() {
            applyBatchDensity(densityPrefs, 'compact');
        });
        var batchFullBtn = button('全部设为完整', 'settings-button secondary', function() {
            applyBatchDensity(densityPrefs, 'full');
        });

        var densitySec = section('物品栏网格密度',
            '控制各面板物品格默认按多列图标（紧凑）或带名称/价格信息卡（完整）展示；通常重新打开对应面板后生效。',
            {scope: 'local', actions: [batchCompactBtn, batchFullBtn]});
        densitySec.classList.add('settings-itemgrid-section');

        // 轻量纯 CSS 完整 vs 紧凑对照样片
        var specimen = node('div', 'settings-density-specimen');
        specimen.innerHTML = ''
            + '<div class="settings-density-sample">'
            + '  <span class="settings-density-tag">完整卡片</span>'
            + '  <div class="settings-density-mock full">'
            + '    <span class="mock-card"><i class="mock-ico"></i><span class="mock-lines"><b></b><em></em></span></span>'
            + '    <span class="mock-card"><i class="mock-ico"></i><span class="mock-lines"><b></b><em></em></span></span>'
            + '  </div>'
            + '</div>'
            + '<div class="settings-density-sample">'
            + '  <span class="settings-density-tag">紧凑图标格</span>'
            + '  <div class="settings-density-mock compact">'
            + '    <i class="mock-ico"></i><i class="mock-ico"></i><i class="mock-ico"></i><i class="mock-ico"></i><i class="mock-ico"></i><i class="mock-ico"></i>'
            + '  </div>'
            + '</div>';
        densitySec.appendChild(specimen);

        var dgrid = node('div', 'settings-grid three settings-density-grid');
        densityPrefs.forEach(function(pref) {
            dgrid.appendChild(webPrefSegmented(pref.key, pref.label,
                [{value: 'full', label: '完整'}, {value: 'compact', label: '紧凑'}]));
        });
        densitySec.appendChild(dgrid);
        _content.appendChild(densitySec);
    }

    function webPrefSegmented(key, label, options) {
        var current = SettingsPreferences.read(key);
        var seg = segmentedGroup(options, current, function(nextVal, btn, group) {
            if (SettingsPreferences.write(key, nextVal)) {
                syncSegmentedGroup(group, nextVal);
                setStatus('已保存偏好：“' + label + '”。', 'ready');
                notifyToast(label + '：' + optionLabel(nextVal), 'success', true);
                cue('success');
            } else {
                syncSegmentedGroup(group, SettingsPreferences.read(key));
                setStatus('本机存储不可用，偏好未保存。', 'error');
            }
        }, 'settings-seg-compact');
        seg.setAttribute('data-web-pref-key', key);
        return field(label, seg);
    }

    function applyBatchDensity(densityPrefs, mode) {
        var allOk = true;
        densityPrefs.forEach(function(pref) {
            if (!SettingsPreferences.write(pref.key, mode)) allOk = false;
        });
        if (allOk) {
            setStatus('已将全部 ' + densityPrefs.length + ' 个面板设为' + optionLabel(mode) + '密度。', 'ready');
            notifyToast('全部物品栏密度已设为：' + optionLabel(mode), 'success', true);
            cue('success');
            renderCurrentTab();
        } else {
            setStatus('本机存储不可用，批量密度未保存。', 'error');
        }
    }

    // ── 性能方案控制与快速提交 ──
    function performanceLabel(value) {
        if (!value) return '暂不可用';
        var preset = {balanced: '通用', performance: '性能', quality: '画质'}[value.preset];
        return preset + ' · ' + (value.mode === 'fixed' ? '固定' : '自动') + ' · '
            + (value.maxRenderHeight === 0 ? '方案默认上限' : '最高 ' + value.maxRenderHeight + 'p');
    }

    function quickApplyPerformancePreset(nextPreset) {
        var state = _snapshot && _snapshot.hostPrefs.performance;
        if (!state || _busy || _requiresReconcile || _performanceBusy) return;
        if (state.current.preset === nextPreset) return;
        var nextConfig = SettingsRuntime.normalizePerformanceConfig({
            preset: nextPreset,
            mode: state.current.mode,
            maxRenderHeight: state.current.maxRenderHeight
        });
        if (!nextConfig) return;
        _performanceDraft = SettingsRuntime.copy(nextConfig);
        savePerformance(false, true);
    }

    function quickApplyPerformanceUndo() {
        var state = _snapshot && _snapshot.hostPrefs.performance;
        if (!state || !state.previous || _busy || _requiresReconcile || _performanceBusy) return;
        savePerformance(true, true);
    }

    function performanceSelect(key, label, values, note) {
        var select = document.createElement('select');
        select.className = 'settings-select';
        select.setAttribute('data-performance-key', key);
        values.forEach(function(row) {
            var option = node('option', '', row[1]);
            option.value = String(row[0]);
            select.appendChild(option);
        });
        select.value = String(_performanceDraft[key]);
        select.addEventListener('change', function() {
            if (_busy || _requiresReconcile) {
                select.value = String(_performanceDraft[key]);
                return;
            }
            _performanceDraft[key] = key === 'maxRenderHeight' ? Number(select.value) : select.value;
            _performanceMessage = '';
            _performanceMessageState = 'ready';
            refreshPerformanceControls();
        });
        return field(label, select, note);
    }

    function refreshPerformanceControls() {
        var group = _content && _content.querySelector('.settings-performance');
        var state = _snapshot && _snapshot.hostPrefs.performance;
        if (!group || !state || !_performanceDraft) return;
        var locked = _busy || _requiresReconcile || _performanceBusy;
        var dirty = SettingsRuntime.hasPerformanceChanges(state, _performanceDraft);
        var controls = group.querySelectorAll('[data-performance-key]');
        for (var i = 0; i < controls.length; i++) {
            var control = controls[i];
            control.disabled = locked;
            control.value = String(_performanceDraft[control.getAttribute('data-performance-key')]);
        }
        var applyBtn = group.querySelector('.settings-performance-apply');
        var undoBtn = group.querySelector('.settings-performance-undo');
        var resetBtn = group.querySelector('.settings-performance-reset');
        var savedEl = group.querySelector('.settings-performance-saved');
        var message = group.querySelector('.settings-performance-message');
        if (applyBtn) applyBtn.disabled = locked || !dirty;
        if (undoBtn) undoBtn.disabled = locked || !state.previous;
        if (resetBtn) resetBtn.disabled = locked || _performanceDraft.mode === 'auto';
        if (savedEl) savedEl.textContent = '已保存：' + performanceLabel(state.current);
        if (message) {
            message.textContent = _performanceMessage || (dirty ? '性能方案有未应用的改动。'
                : _performanceDraft.mode === 'fixed'
                    ? '固定使用方案允许的最高档；实际绘制尺寸受分辨率上限、窗口与显示缩放限制。'
                    : '自动调节流畅度与清晰度，实际状态见顶部性能显示。');
            message.setAttribute('data-state', _performanceMessageState);
        }
    }

    function savePerformance(undo, fromQuickPreset) {
        var state = _snapshot && _snapshot.hostPrefs.performance;
        if (!state || !_performanceDraft || _busy || _requiresReconcile || _performanceBusy) return;
        if (undo ? !state.previous : !SettingsRuntime.hasPerformanceChanges(state, _performanceDraft)) return;
        var key = undo ? 'performanceUndo' : 'performance';
        var value = undo ? true : SettingsRuntime.normalizePerformanceConfig(_performanceDraft);
        if (!value) return;
        _busy = true;
        _performanceBusy = true;
        _performanceMessage = undo ? '正在恢复上次性能方案…' : '正在保存性能方案…';
        _performanceMessageState = 'loading';
        refreshFooter();
        var id = _mux.request('host_set', {v: 1, key: key, value: value}, {kind: 'host.performance'}, function(response) {
            _busy = false;
            _performanceBusy = false;
            var authoritative = response && SettingsRuntime.normalizePerformanceState(response.currentValue);
            if (response && (response.requiresReconcile === true
                || response.error === 'malformed_response'
                || (response.success === true && (!authoritative || response.key !== key)))) {
                reconcileUnknownWrite('性能方案结果未知，正在重新读取当前配置；不会自动重试。', true);
                return;
            }
            if (authoritative) _snapshot.hostPrefs.performance = authoritative;
            var ok = response && response.success === true && authoritative;
            if (ok) _performanceDraft = SettingsRuntime.copy(authoritative.current);
            else if (fromQuickPreset && authoritative) _performanceDraft = SettingsRuntime.copy(authoritative.current);
            _performanceMessage = ok
                ? (undo ? '已保存上次性能方案；关闭设置后按方案运行。' : '方案已保存；关闭设置后按方案运行。')
                : '性能方案未保存：' + errorText(response && response.error || 'malformed_response');
            _performanceMessageState = ok ? 'ready' : 'error';
            setStatus(ok ? '性能方案已保存。' : _performanceMessage, _performanceMessageState);
            if (ok) {
                cue('success');
                notifyToast(undo ? '已恢复上次性能方案' : '性能方案：' + performanceLabel(authoritative.current), 'success', true);
            } else {
                cue('rejected');
            }
            if (_activeTab === 'common') renderCurrentTab();
            refreshFooter();
        });
        if (!id) {
            _busy = false;
            _performanceBusy = false;
            _performanceMessage = '性能方案请求未发出，改动已保留。';
            _performanceMessageState = 'error';
            refreshFooter();
        }
    }

    // ── Host 本机偏好通用控件 ──
    function hostBoolean(key, label, desc) {
        var input = toggleSwitchInput(_snapshot.hostPrefs[key] === true, function(val, el) {
            setHostPreference(key, val, el, label + '已' + (val ? '开启' : '关闭'));
        }, key);
        return field(label, input, '', desc);
    }

    function hostSegmented(key, label, options) {
        var current = String(_snapshot.hostPrefs[key]);
        var seg = segmentedGroup(options, current, function(nextVal, btn, group) {
            var meta = options.filter(function(o) { return o.value === nextVal; })[0];
            setHostPreference(key, nextVal, group, label + '：' + (meta ? meta.label : nextVal));
        }, 'settings-seg-compact', key);
        return field(label, seg);
    }

    function setHostPreference(key, value, control, toastText, onSuccess) {
        if (_requiresReconcile) {
            applyHostControlValue(control, key, _snapshot.hostPrefs[key]);
            setStatus('写入结果尚未核对，本机偏好保持锁定。', 'warning');
            return;
        }
        var previous = _snapshot.hostPrefs[key];
        setHostControlDisabled(control, true);
        var id = _mux.request('host_set', {v: 1, key: key, value: value}, {kind: 'host.' + key}, function(response) {
            var hasAuthority = response && response.currentValue !== undefined;
            var authoritative = hasAuthority ? response.currentValue : previous;
            _snapshot.hostPrefs[key] = authoritative;
            applyHostControlValue(control, key, authoritative);
            if (response && (response.requiresReconcile === true
                || response.error === 'malformed_response'
                || (response.success === true && (!hasAuthority || response.key !== key)))) {
                reconcileUnknownWrite('本机偏好结果未知，正在重新读取权威状态；不会自动重试。', true);
                return;
            }
            setHostControlDisabled(control, false);
            var liveControls = _content ? _content.querySelectorAll('[data-host-key],[data-host-segment]') : [];
            for (var i = 0; i < liveControls.length; i++) {
                var targetKey = liveControls[i].getAttribute('data-host-key')
                    || liveControls[i].getAttribute('data-host-segment');
                if (targetKey === key) {
                    applyHostControlValue(liveControls[i], key, authoritative);
                    setHostControlDisabled(liveControls[i], false);
                }
            }
            var ok = response && response.success === true && hasAuthority;
            setStatus(ok ? '本机偏好已保存。'
                : '本机偏好未保存：' + errorText(response && response.error || 'malformed_response'),
                ok ? 'ready' : 'error');
            if (ok) {
                cue('success');
                if (toastText) notifyToast(toastText, 'success', true);
                if (onSuccess) onSuccess(authoritative);
            } else {
                cue('rejected');
            }
        });
        if (!id) {
            setHostControlDisabled(control, false);
            applyHostControlValue(control, key, previous);
            setStatus('本机偏好请求未发出。', 'error');
        }
    }

    function setHostControlDisabled(control, disabled) {
        if (!control) return;
        if (control.hasAttribute && control.hasAttribute('data-host-segment')) {
            syncSegmentedGroup(control, _snapshot && _snapshot.hostPrefs[control.getAttribute('data-host-segment')], disabled);
            return;
        }
        control.disabled = disabled;
    }

    function applyHostControlValue(control, key, value) {
        if (!control) return;
        if (control.hasAttribute && control.hasAttribute('data-host-segment')) {
            syncSegmentedGroup(control, value);
            return;
        }
        if (control.type === 'checkbox') control.checked = value === true;
        else control.value = String(value);
    }

    // ── 音量 / 倍率滑杆 / 作弊码 ──
    function volumeField(key, label) {
        var wrap = node('div', 'settings-range-wrap');
        var range = document.createElement('input');
        range.type = 'range';
        range.min = '0';
        range.max = '100';
        range.step = '1';
        range.value = String(_draft.settings[key]);
        var output = node('output', '', range.value + '%');
        range.addEventListener('input', function() {
            _draft.settings[key] = Number(range.value);
            output.textContent = range.value + '%';
            changed();
            schedulePreview();
        });
        wrap.appendChild(range);
        wrap.appendChild(output);
        return field(label, wrap);
    }

    function rangeControl(key, min, max, step, afterInput) {
        var wrap = node('div', 'settings-range-wrap');
        var range = document.createElement('input');
        range.type = 'range';
        range.min = String(min);
        range.max = String(max);
        range.step = String(step);
        range.value = String(_draft.settings[key]);
        var output = node('output', '', Number(range.value).toFixed(1) + '×');
        range.addEventListener('input', function() {
            _draft.settings[key] = Number(range.value);
            output.textContent = Number(range.value).toFixed(1) + '×';
            changed();
            if (afterInput) afterInput();
        });
        wrap.appendChild(range);
        wrap.appendChild(output);
        return wrap;
    }

    function cheatCommandForm() {
        var form = node('div', 'settings-cheat-form settings-home-cheat');
        var input = document.createElement('input');
        input.type = 'text';
        input.maxLength = 240;
        input.placeholder = '输入作弊码，例如 status 或 #level:15';
        input.id = 'settings-home-cheat-input';
        form.appendChild(input);

        var execBtn = button('执行命令', 'settings-button danger settings-cheat-exec', function() {
            var command = input.value.trim();
            if (!command) return;
            confirmThen('cheat:' + command, '再次点击确认执行命令', function() {
                execBtn.textContent = '执行命令';
                execBtn.classList.remove('is-arming');
                sendTool('cheat', {v: 1, command: command, confirmed: true}, false);
            }, function(armed) {
                execBtn.textContent = armed ? '再次点击确认' : '执行命令';
                execBtn.classList.toggle('is-arming', armed);
            });
        });
        annotate(execBtn, '第一次点击进入待确认状态，5 秒内再次点击才会把命令交给游戏。', 'top');
        form.appendChild(execBtn);

        input.addEventListener('keydown', function(event) {
            if (event.key === 'Enter') {
                event.preventDefault();
                execBtn.click();
            }
        });

        form.appendChild(annotate(
            button('作弊码帮助', 'settings-button secondary settings-cheat-help-open', function(event) {
                openCheatHelp(event.currentTarget);
            }),
            _snapshot.challengeMode
                ? '挑战模式只展示如何切换模式；命令输入仍保持可用。'
                : '查看完整现役指令并一键复制；复制不会自动执行。',
            'top'));
        return form;
    }

    // ── 镜头预览同步与全屏精调模态 ──
    function cameraPreviewStage() {
        var card = node('figure', 'settings-camera-preview settings-camera-simulator-stage');
        var viewport = node('div', 'settings-camera-viewport settings-camera-simulator-viewport');
        if (_flashPreview) {
            _cameraPreviewImage = document.createElement('img');
            _cameraPreviewImage.src = _flashPreview.dataUrl;
            _cameraPreviewImage.alt = '进入设置时捕获的游戏静态画面';
            _cameraPreviewImage.draggable = false;
            viewport.appendChild(_cameraPreviewImage);
        } else {
            _cameraPreviewImage = null;
            viewport.appendChild(node('p', 'settings-camera-unavailable', '本次入口未取得可用画面'));
        }
        _cameraScaleHud = node('output', 'settings-camera-hud-scale', '1.0×');
        viewport.appendChild(_cameraScaleHud);
        _cameraSafeFrame = node('span', 'settings-camera-safe-frame');
        viewport.appendChild(_cameraSafeFrame);
        _cameraHudBand = node('span', 'settings-camera-hud-band is-labeled', '底部状态栏安全区 (64px)');
        viewport.appendChild(_cameraHudBand);
        card.appendChild(viewport);
        _cameraParityNote = node('figcaption', '', '入口静态帧 · 非实时画面');
        card.appendChild(_cameraParityNote);
        return card;
    }

    function applyCameraTransformToImage(img, projection, scaleLabel) {
        if (!img || !projection) return;
        img.style.transform = 'translate('
            + projection.translateXPct.toFixed(3) + '%, '
            + projection.translateYPct.toFixed(3) + '%) scale('
            + projection.relativeScale.toFixed(4) + ')';
        img.setAttribute('data-preview-scale', scaleLabel);
        img.setAttribute('data-preview-effective-scale', projection.effectiveScale.toFixed(2));
        img.setAttribute('data-preview-relative-scale', projection.relativeScale.toFixed(4));
        img.setAttribute('data-preview-mode', projection.mode);
        img.setAttribute('data-preview-tx', projection.translateXPct.toFixed(3));
        img.setAttribute('data-preview-ty', projection.translateYPct.toFixed(3));
    }

    function applyCameraOverlayGuides(safeFrame, hudBand, projection) {
        var hudPct = projection && isFinite(projection.hudBandPct) ? projection.hudBandPct : (64 / 576) * 100;
        if (safeFrame) safeFrame.style.bottom = hudPct.toFixed(3) + '%';
        if (hudBand) hudBand.style.height = hudPct.toFixed(3) + '%';
    }

    function updateCameraPreview() {
        if (!_draft) return;
        var scale = Number(_draft.settings.basicZoomScale);
        if (!isFinite(scale) || scale < 0.5 || scale > 3) scale = 1;
        var dynamicOn = _draft.settings.cameraZoomToggle === true;
        if (!dynamicOn) _cameraDynamicSample = 1;

        var inlineProjection = SettingsRuntime.computeCameraPreviewTransform({
            camera: _entryCameraContext,
            basicZoomScale: scale,
            cameraZoomToggle: dynamicOn,
            dynamicMultiplier: 1,
            fallbackEntryScale: _entryCameraScale
        });
        var modalProjection = SettingsRuntime.computeCameraPreviewTransform({
            camera: _entryCameraContext,
            basicZoomScale: scale,
            cameraZoomToggle: dynamicOn,
            dynamicMultiplier: dynamicOn ? _cameraDynamicSample : 1,
            fallbackEntryScale: _entryCameraScale
        });

        applyCameraTransformToImage(_inlineCameraImage, inlineProjection, scale.toFixed(1));
        applyCameraOverlayGuides(_inlineCameraSafeFrame, _inlineCameraHudBand, inlineProjection);
        applyCameraTransformToImage(_cameraPreviewImage, modalProjection, scale.toFixed(1));
        applyCameraOverlayGuides(_cameraSafeFrame, _cameraHudBand, modalProjection);

        if (_inlineCameraHud) _inlineCameraHud.textContent = scale.toFixed(1) + '×';
        if (_cameraScaleHud) {
            _cameraScaleHud.textContent = (dynamicOn && _cameraDynamicSample > 1)
                ? modalProjection.effectiveScale.toFixed(1) + '×'
                : scale.toFixed(1) + '×';
        }
        if (_cameraDynamicSamples) {
            _cameraDynamicSamples.hidden = !dynamicOn;
            syncSegmentedGroup(_cameraDynamicSamples.querySelector('.settings-segmented'), _cameraDynamicSample, !dynamicOn);
        }
        if (_cameraModeHud) {
            _cameraModeHud.textContent = dynamicOn
                ? ('动态镜头：开启 · 战斗范围 ' + scale.toFixed(1) + '×–' + (scale * 2).toFixed(1) + '×')
                : '固定基础倍率';
            _cameraModeHud.setAttribute('data-dynamic', dynamicOn ? 'on' : 'off');
        }
        if (_cameraParityNote) {
            var parts = [];
            if (modalProjection.mode === 'as2_exact') {
                parts.push('AS2 镜头同源构图');
                if (Math.abs(modalProjection.entryScale - 1) > 0.01 && Math.abs(modalProjection.entryScale - scale) > 0.01) {
                    parts.push('入口实景 ' + modalProjection.entryScale.toFixed(2) + '×');
                }
                if (modalProjection.pinnedX || modalProjection.pinnedY) parts.push('小图贴齐左上角');
                else if (modalProjection.clampedX || modalProjection.clampedY) parts.push('已贴合场景边界');
            } else {
                parts.push('入口静态帧 · 当前场景未激活卷屏镜头（中心近似）');
            }
            _cameraParityNote.textContent = parts.join(' · ');
        }
    }

    function openCameraSimulator(trigger) {
        if (_cameraModal || !_draft) return;
        hideTooltips();
        _cameraReturnFocus = trigger || null;
        _cameraDynamicSample = 1;
        var layer = node('div', 'settings-modal-layer settings-camera-modal-layer');
        layer.addEventListener('click', function(event) {
            if (event.target === layer) closeCameraSimulator(true);
        });
        var dialog = node('section', 'settings-camera-modal');
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
        dialog.setAttribute('aria-labelledby', 'settings-camera-title');
        dialog.addEventListener('keydown', function(e) { trapModalFocus(e, _cameraModal); });

        var header = node('header', 'settings-camera-modal-header');
        var identity = node('div', 'settings-camera-modal-identity');
        identity.appendChild(node('span', 'settings-modal-kicker', 'CAMERA PREVIEW'));
        var title = node('h2', '', '镜头缩放模拟'); title.id = 'settings-camera-title';
        identity.appendChild(title);
        header.appendChild(identity);
        var help = button('?', 'settings-hint-trigger settings-camera-help', null);
        help.setAttribute('aria-label', '镜头预览说明');
        header.appendChild(annotate(help,
            '按游戏真实卷屏构图规则模拟：跟随角色坐标与朝向偏置、扣除底部 64px 状态栏并受地图边界钳制。当倍率缩至地图小于视口时，游戏会将画面贴齐左上角；外围网格表示入口快照未记录的视野区域。',
            'left'));
        header.appendChild(annotate(
            button('×', 'settings-terminal-close settings-camera-modal-close', function() {
                closeCameraSimulator(true);
            }),
            '返回设置并保留当前镜头草稿。',
            'left'));
        dialog.appendChild(header);

        var body = node('div', 'settings-camera-simulator-body');
        body.appendChild(cameraPreviewStage());
        var controls = node('aside', 'settings-camera-controls');
        var zoom = field('基础镜头倍率', rangeControl('basicZoomScale', 0.5, 3, 0.1, updateCameraPreview),
            '数值越大，画面越近；关闭动态镜头时仍会固定应用该倍率。');
        zoom.classList.add('settings-camera-control-field', 'is-stacked');
        controls.appendChild(zoom);
        var dynamic = checkbox('cameraZoomToggle', '动态镜头调节',
            '关闭时仍使用固定基础倍率；开启后游戏可围绕基础倍率动态变化。', updateCameraPreview);
        dynamic.classList.add('settings-camera-control-field');
        controls.appendChild(dynamic);
        _cameraModeHud = node('p', 'settings-camera-mode-hud');
        controls.appendChild(_cameraModeHud);

        _cameraDynamicSamples = node('div', 'settings-camera-dynamic-samples');
        _cameraDynamicSamples.appendChild(node('span', 'settings-control-label', '战斗动态倍率试看'));
        _cameraDynamicSamples.appendChild(segmentedGroup(
            [
                {value: 1, label: '基础 ×1.0', tooltip: '非战斗或敌人较多（>8）时的基础视野'},
                {value: 1.5, label: '交火 ×1.5', tooltip: '3–5 名敌人交火时的中距动态放大上限'},
                {value: 2, label: '近战 ×2.0', tooltip: '少于 3 名敌人近距战斗时的最大动态放大上限'}
            ],
            _cameraDynamicSample,
            function(nextMult) {
                _cameraDynamicSample = Number(nextMult) || 1;
                updateCameraPreview();
            },
            'settings-seg-three'
        ));
        controls.appendChild(_cameraDynamicSamples);

        var actions = node('div', 'settings-camera-control-actions');
        actions.appendChild(annotate(
            button('恢复 1.0×', 'settings-button secondary', function() {
                _draft.settings.basicZoomScale = 1;
                _cameraDynamicSample = 1;
                var range = _cameraModal && _cameraModal.querySelector('input[type="range"]');
                if (range) {
                    range.value = '1';
                    var output = range.parentNode.querySelector('output');
                    if (output) output.textContent = '1.0×';
                }
                changed();
                updateCameraPreview();
            }),
            '把基础倍率恢复为 1.0×。'));
        controls.appendChild(actions);
        body.appendChild(controls);
        dialog.appendChild(body);

        var footer = node('footer', 'settings-camera-modal-footer');
        footer.appendChild(annotate(
            button('返回设置', 'settings-button primary settings-camera-done', function() {
                closeCameraSimulator(true);
            }),
            '保留当前镜头草稿；回到设置后仍需点击“应用并保存”。',
            'top'));
        dialog.appendChild(footer);
        layer.appendChild(dialog);
        _root.appendChild(layer);
        _cameraModal = layer;
        updateCameraPreview();
        cue('activate');
        var first = dialog.querySelector('input[type="range"]');
        if (first) first.focus();
    }

    function closeCameraSimulator(restoreFocus) {
        if (!_cameraModal) return;
        hideTooltips();
        var returnFocus = _cameraReturnFocus;
        if (_tooltipScope && _tooltipScope.releaseTree) _tooltipScope.releaseTree(_cameraModal);
        if (_cameraModal.parentNode) _cameraModal.parentNode.removeChild(_cameraModal);
        _cameraModal = null;
        _cameraReturnFocus = null;
        _cameraPreviewImage = null;
        _cameraScaleHud = null;
        _cameraSafeFrame = null;
        _cameraHudBand = null;
        _cameraParityNote = null;
        _cameraDynamicSamples = null;
        _cameraModeHud = null;
        _cameraDynamicSample = 1;
        _pendingInitialCameraPreview = false;
        if (restoreFocus && _activeTab === 'common' && _snapshot && _draft) {
            renderCurrentTab();
            var freshTrigger = _content && _content.querySelector('.settings-camera-open');
            if (freshTrigger) freshTrigger.focus();
        } else if (restoreFocus && returnFocus && document.documentElement.contains(returnFocus)) {
            returnFocus.focus();
        }
    }

    // ── 作弊码帮助模态 ──
    function openCheatHelp(trigger) {
        if (_cheatModal) return;
        hideTooltips();
        _helpReturnFocus = trigger || null;
        var layer = node('div', 'settings-modal-layer');
        layer.addEventListener('click', function(event) {
            if (event.target === layer) closeCheatHelp();
        });
        var dialog = node('section', 'settings-cheat-modal');
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
        dialog.setAttribute('aria-labelledby', 'settings-cheat-help-title');
        dialog.addEventListener('keydown', function(e) { trapModalFocus(e, _cheatModal); });
        var header = node('header', 'settings-cheat-modal-header');
        var identity = node('div', 'settings-cheat-modal-identity');
        identity.appendChild(node('span', 'settings-modal-kicker', _snapshot.challengeMode
            ? 'CHALLENGE MODE / LIMITED HELP' : 'DEVELOPER COMMAND REFERENCE'));
        var title = node('h2', '', '作弊码帮助'); title.id = 'settings-cheat-help-title';
        identity.appendChild(title);
        header.appendChild(identity);
        header.appendChild(annotate(
            button('×', 'settings-terminal-close settings-cheat-modal-close', closeCheatHelp),
            '关闭帮助并返回作弊码输入。',
            'left'));
        dialog.appendChild(header);
        var content = node('div', 'settings-cheat-doc');
        content.setAttribute('data-role', 'cheat-help-content');
        content.appendChild(node('p', 'settings-help-loading', '正在加载作弊码文档…'));
        dialog.appendChild(content);
        dialog.appendChild(node('p', 'settings-cheat-modal-footnote',
            '复制只写入剪贴板；不会自动执行。命令仍通过游戏内部 Bridge 交给 Flash 权威后端。'));
        layer.appendChild(dialog);
        _root.appendChild(layer);
        _cheatModal = layer;
        cue('activate');
        var close = dialog.querySelector('.settings-cheat-modal-close');
        if (close) close.focus();
        if (_cheatHelpText !== null) {
            renderCheatHelpDocument();
            return;
        }
        loadCheatHelp();
    }

    function closeCheatHelp() {
        if (!_cheatModal) return;
        hideTooltips();
        var returnFocus = _helpReturnFocus;
        if (_tooltipScope && _tooltipScope.releaseTree) _tooltipScope.releaseTree(_cheatModal);
        if (_cheatModal.parentNode) _cheatModal.parentNode.removeChild(_cheatModal);
        _cheatModal = null;
        _helpReturnFocus = null;
        if (returnFocus && document.documentElement.contains(returnFocus)) returnFocus.focus();
    }

    // ── 伤害对账日志模态 ──
    function openDamageLedger(trigger) {
        if (_damageLedgerModal) return;
        hideTooltips();
        _damageLedgerReturnFocus = trigger || null;
        _damageLedgerOffset = 0;
        var layer = node('div', 'settings-modal-layer settings-damage-ledger-layer');
        layer.addEventListener('click', function(event) {
            if (event.target === layer) closeDamageLedger(true);
        });
        var dialog = node('section', 'settings-damage-ledger-modal');
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
        dialog.setAttribute('aria-labelledby', 'settings-damage-ledger-title');
        dialog.addEventListener('keydown', function(e) { trapModalFocus(e, _damageLedgerModal); });

        var header = node('header', 'settings-damage-ledger-header');
        var identity = node('div', 'settings-damage-ledger-identity');
        identity.appendChild(node('span', 'settings-modal-kicker', 'EXACT DAMAGE RECONCILIATION'));
        var title = node('h2', '', '伤害对账日志'); title.id = 'settings-damage-ledger-title';
        identity.appendChild(title);
        header.appendChild(identity);
        header.appendChild(annotate(
            button('×', 'settings-terminal-close settings-damage-ledger-close', function() {
                closeDamageLedger(true);
            }), '关闭日志并返回设置。', 'left'));
        dialog.appendChild(header);

        var summary = node('p', 'settings-damage-ledger-summary', '正在读取本场景记录…');
        summary.setAttribute('data-role', 'damage-ledger-summary');
        dialog.appendChild(summary);
        var body = node('div', 'settings-damage-ledger-body');
        body.setAttribute('data-role', 'damage-ledger-body');
        body.appendChild(node('p', 'settings-help-loading', '正在读取精确逐段记录…'));
        dialog.appendChild(body);

        var footer = node('footer', 'settings-damage-ledger-footer');
        footer.appendChild(button('较新一页', 'settings-button secondary', function() {
            if (_damageLedgerOffset <= 0) return;
            _damageLedgerOffset = Math.max(0, _damageLedgerOffset - 24);
            requestDamageLedger();
        }));
        footer.lastChild.setAttribute('data-role', 'damage-ledger-newer');
        footer.appendChild(button('刷新最新', 'settings-button secondary', function() {
            _damageLedgerOffset = 0; requestDamageLedger();
        }));
        footer.appendChild(button('较旧一页', 'settings-button secondary', function() {
            _damageLedgerOffset += 24; requestDamageLedger();
        }));
        footer.lastChild.setAttribute('data-role', 'damage-ledger-older');
        dialog.appendChild(footer);
        layer.appendChild(dialog);
        _root.appendChild(layer);
        _damageLedgerModal = layer;
        cue('activate');
        var close = dialog.querySelector('.settings-damage-ledger-close');
        if (close) close.focus();
        requestDamageLedger();
    }

    function closeDamageLedger(restoreFocus) {
        if (!_damageLedgerModal) return;
        hideTooltips();
        var returnFocus = _damageLedgerReturnFocus;
        if (_tooltipScope && _tooltipScope.releaseTree) _tooltipScope.releaseTree(_damageLedgerModal);
        if (_damageLedgerModal.parentNode) _damageLedgerModal.parentNode.removeChild(_damageLedgerModal);
        _damageLedgerModal = null;
        _damageLedgerReturnFocus = null;
        _damageLedgerLoading = false;
        if (restoreFocus !== false && returnFocus && document.documentElement.contains(returnFocus))
            returnFocus.focus();
    }

    function requestDamageLedger() {
        if (!_damageLedgerModal || _damageLedgerLoading) return;
        _damageLedgerLoading = true;
        var body = _damageLedgerModal.querySelector('[data-role="damage-ledger-body"]');
        if (body) { clear(body); body.appendChild(node('p', 'settings-help-loading', '正在读取精确逐段记录…')); }
        var id = _mux.request('hit_number_ledger',
            {v: 1, offset: _damageLedgerOffset, limit: 24},
            {kind: 'hit-number-ledger', latestWins: true}, function(response) {
                _damageLedgerLoading = false;
                if (!_damageLedgerModal) return;
                if (!response || response.success !== true || !response.ledger
                    || !Array.isArray(response.ledger.bursts)) {
                    renderDamageLedgerError(errorText(response && response.error || 'malformed_response'));
                    return;
                }
                _damageLedgerOffset = Number(response.ledger.offset) || 0;
                renderDamageLedger(response.ledger);
            });
        if (!id) {
            _damageLedgerLoading = false;
            renderDamageLedgerError('请求未发出');
        }
    }

    function renderDamageLedgerError(message) {
        if (!_damageLedgerModal) return;
        var body = _damageLedgerModal.querySelector('[data-role="damage-ledger-body"]');
        if (body) { clear(body); body.appendChild(node('p', 'settings-help-error', '读取失败：' + message)); }
    }

    function renderDamageLedger(ledger) {
        if (!_damageLedgerModal) return;
        var summary = _damageLedgerModal.querySelector('[data-role="damage-ledger-summary"]');
        var body = _damageLedgerModal.querySelector('[data-role="damage-ledger-body"]');
        var newer = _damageLedgerModal.querySelector('[data-role="damage-ledger-newer"]');
        var older = _damageLedgerModal.querySelector('[data-role="damage-ledger-older"]');
        if (newer) newer.disabled = ledger.hasNewer !== true;
        if (older) older.disabled = ledger.hasOlder !== true;
        if (summary) {
            var retained = Number(ledger.retainedSegments) || 0;
            var dropped = Number(ledger.droppedSegments) || 0;
            summary.textContent = '本场景保留 ' + retained + ' 段 · 共 ' + (Number(ledger.totalBursts) || 0)
                + ' 发攻击' + (dropped > 0 ? ' · 较早 ' + dropped + ' 段已越过内存上限' : ' · 尚未截断');
            summary.setAttribute('data-truncated', dropped > 0 ? 'true' : 'false');
        }
        if (!body) return;
        clear(body);
        if (!ledger.bursts.length) {
            body.appendChild(node('p', 'settings-empty', '本场景尚无可对账的伤害段。'));
            return;
        }
        ledger.bursts.forEach(function(burst) {
            var card = node('article', 'settings-damage-ledger-burst');
            var heading = node('header', 'settings-damage-ledger-burst-header');
            var target = String(burst.targetId || '未知目标');
            heading.appendChild(node('strong', '', target));
            heading.appendChild(node('span', '', 'Σ' + String(burst.totalDamage) + ' ×' + String(burst.hitCount)
                + ' · ' + String(burst.ageMs) + 'ms 前'));
            card.appendChild(heading);
            card.appendChild(node('code', 'settings-damage-ledger-burst-id', String(burst.burstId || '独立段')));
            var segments = node('div', 'settings-damage-ledger-segments');
            (burst.segments || []).forEach(function(segment) {
                var packed = Number(segment.packed) || 0;
                var chip = node('span', 'settings-damage-ledger-segment', ledgerSegmentText(segment, packed));
                var color = ledgerPackedColor(packed);
                chip.style.color = color;
                chip.style.borderColor = color;
                segments.appendChild(chip);
            });
            card.appendChild(segments);
            body.appendChild(card);
        });
    }

    function ledgerSegmentText(segment, packed) {
        var flags = packed & 511;
        var labels = [];
        if ((packed & 512) !== 0) labels.push('MISS');
        else labels.push(String(segment.damage));
        if ((flags & 8) !== 0 && segment.effectText) labels.push(String(segment.effectText));
        if ((flags & 16) !== 0) labels.push(String(segment.effectEmoji || '') + String(segment.effectText || '破'));
        if ((flags & 1) !== 0) labels.push('溃');
        if ((flags & 2) !== 0) labels.push('毒');
        if ((flags & 4) !== 0) labels.push('斩');
        if ((flags & 32) !== 0 && Number(segment.lifeSteal) > 0) labels.push('汲:' + Math.trunc(Number(segment.lifeSteal)));
        if ((flags & 256) !== 0 && Number(segment.shieldAbsorb) > 0) labels.push('盾:' + Math.trunc(Number(segment.shieldAbsorb)));
        return labels.join(' · ');
    }

    function ledgerPackedColor(packed) {
        var colors = ['#ffffff', '#ff4b4b', '#ffcc00', '#a94b70', '#8d5bdb', '#ac99ff',
            '#28adff', '#c13a3a', '#bca52e', '#ff8e8e', '#ffe770'];
        var colorId = (packed >> 18) & 15;
        return colors[Math.min(colorId, colors.length - 1)];
    }

    // ── 自定义面板内关闭确认弹层（彻底替代原生 window.confirm） ──
    function openCloseConfirm(dirtyGame, dirtyPerformance, dirtyCount) {
        if (_closeConfirmModal) return;
        dismissTooltipsHard();
        _closeConfirmReturnFocus = document.activeElement;
        var layer = node('div', 'settings-modal-layer settings-confirm-layer');
        layer.addEventListener('click', function(event) {
            if (event.target === layer) closeCloseConfirm(true);
        });
        var dialog = node('section', 'settings-confirm-modal');
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
        dialog.setAttribute('aria-labelledby', 'settings-close-confirm-title');
        dialog.addEventListener('keydown', function(e) { trapModalFocus(e, _closeConfirmModal); });

        var header = node('header', 'settings-confirm-header');
        header.appendChild(node('span', 'settings-modal-kicker', 'UNSAVED CHANGES'));
        var title = node('h2', '', '尚有未保存的设置改动');
        title.id = 'settings-close-confirm-title';
        header.appendChild(title);
        dialog.appendChild(header);

        var reasons = [];
        if (dirtyGame) {
            reasons.push(dirtyCount > 0
                ? '游戏存档设置与键位有 ' + dirtyCount + ' 项改动尚未保存。'
                : '旧存档键位补齐尚未保存落盘。');
        }
        if (dirtyPerformance) {
            reasons.push('高级性能方案草稿尚未点击“应用方案”。');
        }
        var body = node('div', 'settings-confirm-body');
        reasons.forEach(function(line) { body.appendChild(node('p', '', line)); });
        body.appendChild(node('p', 'settings-confirm-note', '已修改的本机即时偏好（如伤害数字、界面音效等）已自动保存，不受影响。'));
        dialog.appendChild(body);

        var footer = node('footer', 'settings-confirm-footer');
        var backBtn = button('返回继续编辑', 'settings-button secondary settings-confirm-cancel', function() {
            closeCloseConfirm(true);
        });
        footer.appendChild(backBtn);

        var discardCloseBtn = button('放弃并关闭', 'settings-button danger settings-confirm-discard', function() {
            closeCloseConfirm(false);
            proceedDiscardAndClose(dirtyGame);
        });
        footer.appendChild(discardCloseBtn);

        var persistence = SettingsRuntime.persistenceView(_authority);
        if (dirtyGame && !dirtyPerformance && !_readOnlyProtocol && persistence.canApply) {
            var saveCloseBtn = button('应用并保存后关闭', 'settings-button primary settings-confirm-save', function() {
                closeCloseConfirm(false);
                applyGameDraft(true);
            });
            footer.appendChild(saveCloseBtn);
        }
        dialog.appendChild(footer);
        layer.appendChild(dialog);
        _root.appendChild(layer);
        _closeConfirmModal = layer;
        cue('activate');
        backBtn.focus();
    }

    function closeCloseConfirm(restoreFocus) {
        if (!_closeConfirmModal) return;
        hideTooltips();
        var ret = _closeConfirmReturnFocus;
        if (_closeConfirmModal.parentNode) _closeConfirmModal.parentNode.removeChild(_closeConfirmModal);
        _closeConfirmModal = null;
        _closeConfirmReturnFocus = null;
        if (restoreFocus && ret && document.documentElement.contains(ret)) ret.focus();
    }

    function proceedDiscardAndClose(dirtyGame) {
        if (dirtyGame || _previewActive) {
            _busy = true;
            refreshFooter();
            _mux.request('cancel', {v: 1}, {}, function(response) {
                _busy = false;
                if (response && response.success === true) {
                    _previewActive = false;
                    closeExact();
                } else if (response && response.requiresReconcile === true) {
                    reconcileUnknownWrite('关闭前试听恢复结果未知，正在重新读取权威状态；面板保持打开。');
                } else {
                    setStatus('关闭前恢复试听失败：' + errorText(response && response.error), 'error');
                    refreshFooter();
                }
            });
            return;
        }
        closeExact();
    }

    function trapModalFocus(event, modalLayer) {
        if (event.key !== 'Tab' || !modalLayer) return;
        var focusable = modalLayer.querySelectorAll('button:not(:disabled), [href], input:not(:disabled), [tabindex]:not([tabindex="-1"])');
        if (!focusable.length) return;
        var first = focusable[0], last = focusable[focusable.length - 1];
        if (event.shiftKey && document.activeElement === first) {
            event.preventDefault(); last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault(); first.focus();
        }
    }

    // ── 作弊码帮助文档加载与复制 ──
    function loadCheatHelp() {
        if (_cheatHelpRequest) return;
        var request = new XMLHttpRequest();
        _cheatHelpRequest = request;
        request.open('GET', _config.cheatHelpUrl || 'help/cheat-codes.md', true);
        request.onreadystatechange = function() {
            if (request.readyState !== 4) return;
            _cheatHelpRequest = null;
            if (request.status === 200 || request.status === 0) {
                _cheatHelpText = request.responseText;
                renderCheatHelpDocument();
            } else {
                renderCheatHelpFallback('作弊码文档加载失败；以下为游戏端最小回退帮助。');
            }
        };
        request.send();
    }

    function renderCheatHelpDocument() {
        if (!_cheatModal || !_snapshot) return;
        var content = _cheatModal.querySelector('[data-role="cheat-help-content"]');
        if (!content) return;
        var markdown = SettingsRuntime.selectCheatHelpMarkdown(_cheatHelpText, _snapshot.challengeMode);
        if (!markdown) {
            renderCheatHelpFallback('挑战模式帮助边界缺失；已回退到游戏端模式命令。');
            return;
        }
        try {
            content.innerHTML = typeof marked !== 'undefined' && marked.parse
                ? marked.parse(markdown) : '<pre></pre>';
            if (typeof marked === 'undefined' || !marked.parse)
                content.querySelector('pre').textContent = markdown;
            decorateCheatCopyButtons(content);
        } catch (renderError) {
            renderCheatHelpFallback('作弊码文档渲染失败；以下为游戏端最小回退帮助。');
        }
    }

    function renderCheatHelpFallback(message) {
        if (!_cheatModal) return;
        var content = _cheatModal.querySelector('[data-role="cheat-help-content"]');
        if (!content) return;
        clear(content);
        content.appendChild(node('p', 'settings-help-error', message));
        var list = node('ul', 'settings-cheat-fallback-list');
        (_snapshot && _snapshot.cheatHelp || []).forEach(function(row) {
            var item = document.createElement('li');
            item.appendChild(node('code', '', row.command));
            item.appendChild(node('span', '', row.description));
            list.appendChild(item);
        });
        content.appendChild(list);
        decorateCheatCopyButtons(content);
    }

    function decorateCheatCopyButtons(content) {
        var rows = content.querySelectorAll('li, tr');
        for (var i = 0; i < rows.length; i++) {
            var code = rows[i].querySelector('code');
            if (!code || rows[i].querySelector('.settings-copy-command')) continue;
            var command = code.textContent.trim();
            if (!command) continue;
            var copy = button('复制', 'settings-copy-command', (function(value) {
                return function(event) { copyCommand(value, event.currentTarget); };
            })(command));
            copy.setAttribute('aria-label', '复制命令 ' + command);
            rows[i].appendChild(copy);
        }
    }

    function copyCommand(command, control) {
        function finish(ok) {
            if (!_cheatModal) return;
            control.textContent = ok ? '已复制' : '复制失败';
            setStatus(ok ? '已复制作弊码：' + command : '复制失败，请手动选择命令。', ok ? 'ready' : 'error');
            cue(ok ? 'success' : 'rejected');
            setTimeout(function() {
                if (document.documentElement.contains(control)) control.textContent = '复制';
            }, 1500);
        }
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(command).then(function() { finish(true); }, function() {
                finish(legacyCopy(command));
            });
            return;
        }
        finish(legacyCopy(command));
    }

    function legacyCopy(command) {
        var input = document.createElement('textarea');
        input.value = command;
        input.setAttribute('readonly', 'readonly');
        input.style.position = 'fixed';
        input.style.opacity = '0';
        document.body.appendChild(input);
        input.select();
        var copied = false;
        try { copied = document.execCommand('copy'); } catch (copyError) { copied = false; }
        document.body.removeChild(input);
        return copied;
    }

    // ── 二次点击确认 / 工具命令 / 权威保存与关闭 ──
    var _confirmResetHook = null;
    function confirmThen(key, prompt, callback, onArmedChange) {
        if (_confirmAction !== key) {
            cancelConfirmation();
            _confirmAction = key;
            _confirmResetHook = onArmedChange || null;
            if (onArmedChange) onArmedChange(true);
            setStatus(prompt + '（5 秒内有效）', 'warning');
            cue('activate');
            _confirmTimer = setTimeout(cancelConfirmation, 5000);
            return;
        }
        cancelConfirmation();
        callback();
    }
    function cancelConfirmation() {
        if (_confirmTimer) clearTimeout(_confirmTimer);
        _confirmTimer = null;
        _confirmAction = '';
        var hook = _confirmResetHook;
        _confirmResetHook = null;
        if (hook) { try { hook(false); } catch (err) {} }
    }

    function sendTool(cmd, payload, closeOnSuccess) {
        if (_busy || _requiresReconcile) return;
        _busy = true;
        refreshFooter();
        _mux.request(cmd, payload, {}, function(response) {
            _busy = false;
            refreshFooter();
            if (response && response.success === true) {
                cue('success');
                setStatus(response.message || '操作已由游戏端接受。', 'ready');
                if (response.cheatHelp) _snapshot.cheatHelp = SettingsRuntime.copy(response.cheatHelp);
                if (response.challengeMode !== undefined) _snapshot.challengeMode = response.challengeMode === true;
                if (_cheatModal && _cheatHelpText !== null) renderCheatHelpDocument();
                if (closeOnSuccess || response.closePanel === true) closeExact();
                else renderCurrentTab();
            } else if (response && response.requiresReconcile === true) {
                reconcileUnknownWrite('游戏端结果未知，正在重新读取权威状态；不会自动重复执行。');
                return;
            } else {
                cue('rejected');
                setStatus('操作未执行：' + errorText(response && response.error), 'error');
            }
        });
    }

    function schedulePreview() {
        if (_previewTimer) clearTimeout(_previewTimer);
        _previewTimer = setTimeout(function() { previewAudio('none'); }, 120);
    }

    function previewAudio(sample) {
        if (!_draft || _busy || _requiresReconcile || _readOnlyProtocol) return;
        _mux.request('preview', {
            v: 1,
            globalVolume: _draft.settings.setGlobalVolume,
            bgmVolume: _draft.settings.setBGMVolume,
            sample: sample
        }, {kind: 'preview', latestWins: true, singleFlight: false}, function(response) {
            if (response && response.success === true) {
                _previewActive = true;
                if (sample === 'sfx') setStatus('已播放试听音效。', 'ready');
            } else {
                setStatus('试听失败：' + errorText(response && response.error), 'error');
            }
        });
    }

    function changed() { refreshFooter(); }

    function applyGameDraft(closeOnDurableSuccess) {
        if (!_snapshot || !_draft || _busy || _requiresReconcile || _readOnlyProtocol
            || !SettingsRuntime.persistenceView(_authority).canApply) return;
        var validation = SettingsRuntime.validateKeyDraft(_draft.keys, _snapshot.allowedKeyCodes);
        if (!validation.valid) {
            showTab('keys');
            setStatus(validation.error === 'key_conflict' ? '仍有键位冲突。' : '键位包含保留或无效按键。', 'error');
            return;
        }
        _busy = true;
        refreshFooter();
        setStatus('正在应用并同步保存…', 'loading');
        _mux.request('apply', SettingsRuntime.applyPayload(_snapshot, _draft), {}, function(response) {
            _busy = false;
            adoptAuthority(response);
            var savedCleanly = false;
            if (response && response.applied === true && response.keySchemaVersion === 2) {
                _snapshot.revision = Number(response.revision);
                _snapshot.settings = SettingsRuntime.copy(response.settings || _draft.settings);
                _snapshot.keys = SettingsRuntime.copy(response.keys || _draft.keys);
                _draft = SettingsRuntime.gameDraft(_snapshot);
                _previewActive = false;
                _snapshot.migrationPending = response.migrationPending === true;
                _snapshot.keyMigrationNotice = String(response.keyMigrationNotice || '');
                _saveRetry.hidden = response.durable === true;
                savedCleanly = response.durable === true;
                setStatus(savedCleanly ? '设置已应用并持久化。' : '设置已应用，但落盘失败；请重试保存。',
                    savedCleanly ? 'ready' : 'error');
                if (savedCleanly) notifyToast('游戏设置已保存', 'success', true);
                cue(savedCleanly ? 'success' : 'unknown');
            } else if (response && response.applied === true) {
                setStatus('设置响应缺少 36 键协议确认，未采信回包。', 'error');
            } else if (response && response.error === 'stale_state') {
                setStatus('状态已在别处变化，正在重新同步。', 'warning');
                requestSnapshot();
                return;
            } else if (response && (response.error === 'apply_ambiguous' || response.requiresReconcile === true)) {
                reconcileUnknownWrite('应用结果未知，正在重新读取游戏权威状态；不会自动重放写入。');
                return;
            } else {
                setStatus('设置未应用：' + errorText(response && response.error), 'error');
            }
            if (closeOnDurableSuccess === true && savedCleanly) {
                closeExact();
                return;
            }
            renderCurrentTab();
            refreshFooter();
        });
    }

    function discardGameDraft() {
        if (!_snapshot || _busy) return;
        _busy = true;
        refreshFooter();
        _mux.request('cancel', {v: 1}, {}, function(response) {
            _busy = false;
            adoptAuthority(response);
            if (response && response.success === true) {
                _draft = SettingsRuntime.gameDraft(_snapshot);
                _previewActive = false;
                _capturing = -1;
                setStatus('已放弃未应用改动并恢复试听音量。', 'ready');
                notifyToast('已恢复打开设置时的游戏草稿', 'info', true);
            } else if (response && response.requiresReconcile === true) {
                reconcileUnknownWrite('试听恢复结果未知，正在重新读取游戏权威状态；面板保持打开。');
                return;
            } else {
                setStatus('恢复试听音量失败：' + errorText(response && response.error), 'error');
            }
            renderCurrentTab();
            refreshFooter();
        });
    }

    function retrySave() {
        if (_busy || _requiresReconcile || (_authority && !SettingsRuntime.persistenceView(_authority).canSave)) return;
        _busy = true;
        refreshFooter();
        _mux.request('save', {v: 1}, {}, function(response) {
            _busy = false;
            adoptAuthority(response);
            var ok = response && response.success === true && response.durable === true;
            if (ok) {
                _snapshot.migrationPending = response.migrationPending === true;
                if (!_snapshot.migrationPending) _snapshot.keyMigrationNotice = '';
                notifyToast('游戏设置已成功持久化', 'success', true);
            }
            if (!ok && response && response.requiresReconcile === true) {
                reconcileUnknownWrite('保存结果未知，正在重新读取游戏权威状态；不会自动重试。');
                return;
            }
            _saveRetry.hidden = ok;
            setStatus(ok ? '设置已成功持久化。' : '保存仍失败，请稍后重试。', ok ? 'ready' : 'error');
            refreshFooter();
        });
    }

    function requestClose() {
        if (_busy) {
            setStatus('当前操作尚未结束，请稍候。', 'warning');
            return false;
        }
        if (_closeConfirmModal) {
            closeCloseConfirm(true);
            return false;
        }
        if (_requiresReconcile) {
            closeExact();
            return true;
        }
        var dirty = _snapshot && _draft && (SettingsRuntime.hasGameChanges(_snapshot, _draft)
            || _snapshot.migrationPending === true);
        var performanceDirty = _snapshot
            && SettingsRuntime.hasPerformanceChanges(_snapshot.hostPrefs.performance, _performanceDraft);
        if (dirty || performanceDirty) {
            var count = SettingsRuntime.countGameChanges(_snapshot, _draft);
            openCloseConfirm(dirty, performanceDirty, count);
            return false;
        }
        proceedDiscardAndClose(false);
        return true;
    }

    function closeExact() {
        if (_closeTimer) return;
        stopHitPreviewLoop();
        hideTooltips();
        var instance = _instance;
        var sent = Bridge.send({type: 'panel', cmd: 'close', panel: 'settings', panelInstanceId: instance});
        if (sent !== true) {
            _busy = false;
            setStatus('关闭请求未发出，面板仍保持打开。', 'error');
            refreshFooter();
            return;
        }
        _busy = true;
        setStatus('正在等待 Host 确认关闭…', 'loading');
        refreshFooter();
        _closeTimer = setTimeout(function() {
            _closeTimer = null;
            _busy = false;
            setStatus('Host 尚未确认关闭，可再次尝试。', 'warning');
            refreshFooter();
        }, 3000);
    }

    function refreshFooter() {
        if (!_apply) return;
        var manualChanged = _snapshot && _draft && SettingsRuntime.hasGameChanges(_snapshot, _draft);
        var dirtyCount = manualChanged ? SettingsRuntime.countGameChanges(_snapshot, _draft) : 0;
        var changedFlag = _snapshot && _draft && (manualChanged || _snapshot.migrationPending === true);
        _apply.disabled = _busy || _requiresReconcile || !changedFlag;
        var persistence = SettingsRuntime.persistenceView(_authority);
        if (_authority) _apply.disabled = _apply.disabled || !persistence.canApply;
        if (_readOnlyProtocol) _apply.disabled = true;
        _discard.disabled = _busy || (!manualChanged && !_previewActive);
        _saveRetry.disabled = _busy || _requiresReconcile;
        if (_authority) {
            _saveRetry.hidden = !persistence.canSave;
            _saveRetry.disabled = _saveRetry.disabled || !persistence.canSave;
        }
        if (_dirtyBadge) {
            if (dirtyCount > 0) {
                _dirtyBadge.hidden = false;
                _dirtyBadge.textContent = dirtyCount + ' 项存档改动待保存';
            } else if (_snapshot && _snapshot.migrationPending === true) {
                _dirtyBadge.hidden = false;
                _dirtyBadge.textContent = '键位迁移待保存';
            } else {
                _dirtyBadge.hidden = true;
            }
        }
        if (_persistenceStatus && _snapshot) _persistenceStatus.textContent = persistence.text;
        if (_persistenceStatus && _readOnlyProtocol) _persistenceStatus.textContent = '当前版本仅支持查看设置，未提供保存确认。';
        if (_reconcileButton) {
            _reconcileButton.hidden = !persistence.canReconcile;
            _reconcileButton.disabled = _busy;
        }
        refreshPerformanceControls();
    }

    function setStatus(text, state) {
        if (!_status) return;
        _status.textContent = text;
        _status.setAttribute('data-state', state || 'ready');
    }

    function optionLabel(value) {
        return {
            safe: '逐步确认', fast: '快捷确认', rich: '完整', brief: '缩略',
            green: '绿磷屏', amber: '琥珀磷屏', full: '完整', compact: '紧凑',
            '0': '开启', '1': '静音'
        }[value] || value;
    }

    function errorText(error) {
        return {
            reconcile_required: '必须先重新读取游戏权威状态',
            disconnected: '游戏连接已断开',
            timeout: '等待游戏响应超时',
            client_timeout: '等待响应超时',
            not_sent: '请求未发出',
            delivery_unknown: '请求投递结果未知',
            invalid_payload: '请求格式无效',
            invalid_settings: '设置值无效',
            invalid_keys: '键位表无效',
            key_conflict: '键位冲突',
            reserved_key: '按键被保留',
            stale_state: '状态已变化',
            save_failed: '保存失败',
            bad_value: '设置值无效',
            performance_undo_unavailable: '没有可撤销的性能方案',
            save_unavailable: '当前不可保存',
            settings_unavailable: '设置尚未初始化',
            revive_unavailable: '当前没有可恢复的复活流程',
            actor_alive: '角色尚未死亡',
            resurrection_restricted: '本关禁止复活',
            no_revive_coin: '没有复活币',
            revive_asset_failed: '复活币扣除未被确认，请重试',
            revive_asset_ambiguous: '复活币状态不明确，请重新同步后核对',
            respawn_dispatch_failed: '游戏未确认复活，复活币已返还',
            respawn_dispatch_rollback_failed: '复活失败且退款未确认，请立即核对复活币存量',
            return_in_progress: '正在返回基地',
            return_base_unavailable: '返回基地入口不可用',
            settlement_prepare_failed: '关卡结算尚未准备完成，请稍后重试',
            return_base_failed: '返回基地失败，请稍后重试',
            unknown_command: '无法识别该作弊码',
            apply_ambiguous: '应用结果未知，需要重新同步',
            key_refresh_failed: '键位缓存刷新失败，请重试同步',
            hit_number_ledger_unavailable: '伤害对账日志暂不可用',
            malformed_response: '游戏响应格式异常'
        }[error] || String(error || '未知错误');
    }
})();
