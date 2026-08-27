/** 游戏设置：AS2 权威草稿提交 + Host 即时偏好 + Web 本机偏好聚合。 */
(function() {
    'use strict';
    var DESIGN_W = 1024, DESIGN_H = 576;
    var _config = window.__SETTINGS_CONFIG__ || {};
    var _shell, _root, _content, _status, _apply, _discard, _saveRetry;
    var _init, _instance = '', _snapshot, _draft, _scale;
    var _busy = false, _requiresReconcile = false;
    var _previewActive = false, _previewTimer = null, _closeTimer = null;
    var _capturing = -1, _activeTab = 'game', _confirmAction = '', _confirmTimer = null;
    var _flashPreview = null, _cameraPreviewImage = null, _entryCameraScale = null;
    var _cameraModal = null, _cameraReturnFocus = null;
    var _cameraScaleHud = null, _cameraModeHud = null;
    var _pendingInitialCameraPreview = false;
    var _cheatModal = null, _cheatHelpRequest = null, _cheatHelpText = null, _helpReturnFocus = null;
    var _damageLedgerModal = null, _damageLedgerReturnFocus = null;
    var _damageLedgerOffset = 0, _damageLedgerLoading = false;
    var _tooltipScope = null;
    var SECTION_CODES = {
        '游戏常用设置':'GAME CORE', '镜头缩放':'CAMERA LAB',
        '流程救援':'RECOVERY LINK', '声音试听':'AUDIO BUS', '画面与性能':'DISPLAY CORE',
        '35 项权威键位':'INPUT MAP', '移动与操作':'MOVEMENT', '攻击模式':'COMBAT MODE',
        '快捷物品':'QUICK ITEMS', '快捷技能':'SKILL CHANNEL', '战斗扩展':'COMBAT AUX',
        'Launcher 本机偏好':'LAUNCHER LOCAL', '打击伤害数字':'HIT NUMBER',
        '点歌器运行规则':'JUKEBOX RULES',
        'Web Panel 偏好':'WEB LOCAL'
    };

    var _mux = new SettingsRuntime.RequestMux({
        send:function(message) { return Bridge.send(message); },
        timeoutMs:_config.requestTimeoutMs,
        sessionNonce:_config.sessionNonce
    });

    Panels.register('settings', {
        create:createDOM,
        onOpen:onOpen,
        onRebind:onRebind,
        onClose:cleanup,
        onRequestClose:requestClose,
        onForceClose:cleanup
    });

    function node(tag, className, text) {
        var el = document.createElement(tag);
        if (className) el.className = className;
        if (text !== undefined) el.textContent = text;
        return el;
    }
    function button(text, className, action) {
        var el = node('button', className || 'settings-button', text);
        /* 终端按钮族结构由 css/terminal.css .term-btn 承载；本行只做类接入，不改变语义类名。 */
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
    function escapeHtml(value) {
        return String(value == null ? '' : value).replace(/[&<>"']/g, function(character) {
            return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[character];
        });
    }
    function annotate(target, text, placement) {
        if (!target || !text) return target;
        target.removeAttribute('title');
        target.setAttribute('data-settings-tooltip', String(text));
        if (_tooltipScope && _tooltipScope.bindAsync) {
            _tooltipScope.bindAsync(target, {
                key:function(event, node) { return 'settings:' + node.getAttribute('data-settings-tooltip'); },
                resolveItem:function(event, node) { return node.getAttribute('data-settings-tooltip') || ''; },
                renderBasic:function(value) {
                    return '<div class="settings-simple-tooltip">' + escapeHtml(value) + '</div>';
                },
                placement:placement || 'bottom'
            });
        }
        return target;
    }

    function onOpen(el, initData) {
        _init = initData || {};
        _instance = String(_init.panelInstanceId || '');
        _flashPreview = SettingsRuntime.normalizeFlashPreview(_init.flashPreview);
        _entryCameraScale = null;
        _snapshot = null;
        _draft = null;
        _busy = false;
        _requiresReconcile = false;
        _previewActive = false;
        _capturing = -1;
        _activeTab = 'game';
        _pendingInitialCameraPreview = _init.initialView === 'camera_preview';
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
        if (_previewTimer) clearTimeout(_previewTimer);
        _previewTimer = null;
        if (_closeTimer) clearTimeout(_closeTimer);
        _closeTimer = null;
        cancelConfirmation();
        closeCameraSimulator(false);
        closeCheatHelp();
        closeDamageLedger(false);
        if (_cheatHelpRequest) { try { _cheatHelpRequest.abort(); } catch (abortError) {} }
        _cheatHelpRequest = null;
        if (_scale) { _scale.detach(); _scale = null; }
        _snapshot = null;
        _draft = null;
        _capturing = -1;
        _busy = false;
        _requiresReconcile = false;
        _flashPreview = null;
        _entryCameraScale = null;
        _cameraPreviewImage = null;
        _cameraScaleHud = null;
        _cameraModeHud = null;
        if (_tooltipScope) { _tooltipScope.dispose(); _tooltipScope = null; }
    }

    function buildDOM() {
        clear(_shell);
        if (_tooltipScope) _tooltipScope.dispose();
        _tooltipScope = typeof PanelTooltip !== 'undefined' && PanelTooltip.createScope
            ? PanelTooltip.createScope('settings', {profile:'simple-tooltip'}) : null;
        _root = node('section', 'settings-terminal-shell settings-panel');
        _root.setAttribute('aria-labelledby', 'settings-title');
        var header = node('header', 'settings-terminal-header settings-header term-heading-rule');
        header.appendChild(node('span', 'settings-brand-seal term-brand-seal', 'CF7:ME'));
        var heading = node('div', 'settings-heading');
        heading.appendChild(node('span', 'settings-kicker term-kicker', 'θ-FLOOD / CONFIGURATION LINK'));
        var title = node('h1', 'settings-title', '游戏设置'); title.id = 'settings-title';
        heading.appendChild(title);
        header.appendChild(heading);

        var tabs = node('nav', 'settings-tabs');
        tabs.setAttribute('aria-label', '设置页面');
        [['game','游戏'],['keys','键位'],['local','本机与 Web']]
            .forEach(function(row) {
                var tab = button(row[1], 'settings-tab', function() { showTab(row[0]); });
                tab.setAttribute('data-tab', row[0]);
                tabs.appendChild(tab);
            });
        header.appendChild(tabs);
        _status = node('p', 'settings-status', '正在读取游戏权威状态…');
        _status.setAttribute('role', 'status');
        header.appendChild(_status);
        header.appendChild(annotate(
            button('×', 'settings-terminal-close settings-close', requestClose),
            '关闭设置；尚未应用的游戏改动会被放弃。',
            'left'));
        _root.appendChild(header);
        _content = node('main', 'settings-content');
        _root.appendChild(_content);

        var footer = node('footer', 'settings-footer');
        var actions = node('div', 'settings-footer-actions');
        _saveRetry = button('重试保存', 'settings-button warning', retrySave);
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
        var id = _mux.request('snapshot', {v:1}, {}, function(response) {
            _busy = false;
            if (response && response.requiresReconcile === true) {
                _requiresReconcile = true;
                setStatus('该权威快照早于未决写入终态，写入仍保持锁定；请重新读取。', 'warning');
                renderCurrentTab();
                refreshFooter();
                return;
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
            _requiresReconcile = false;
            _snapshot = model;
            _draft = SettingsRuntime.gameDraft(model);
            if (_entryCameraScale === null) {
                _entryCameraScale = Number(model.settings.basicZoomScale);
                if (!isFinite(_entryCameraScale) || _entryCameraScale < 0.5 || _entryCameraScale > 3)
                    _entryCameraScale = 1;
            }
            _previewActive = model.previewActive;
            var keyState = SettingsRuntime.validateKeyDraft(model.keys, model.allowedKeyCodes);
            if (!keyState.valid) {
                setStatus('检测到历史键位冲突或保留键；可逐项修复，全部有效后再应用。', 'warning');
            } else {
                setStatus(model.migrationPending
                    ? '已补齐旧存档缺失键位；应用后会立即持久化。'
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

    function reconcileUnknownWrite(message) {
        _requiresReconcile = true;
        cue('unknown');
        renderCurrentTab();
        requestSnapshot(message || '写入结果未知，正在重新读取游戏权威状态；不会自动重放。');
    }

    function showTab(tab) {
        _activeTab = tab;
        if (_content) _content.setAttribute('data-active-tab', tab);
        var buttons = _root ? _root.querySelectorAll('.settings-tab') : [];
        for (var i = 0; i < buttons.length; i++) {
            var active = buttons[i].getAttribute('data-tab') === tab;
            buttons[i].classList.toggle('active', active);
            buttons[i].setAttribute('aria-selected', active ? 'true' : 'false');
        }
        renderCurrentTab();
    }

    function renderCurrentTab() {
        if (!_content) return;
        if (_tooltipScope && _tooltipScope.releaseTree) _tooltipScope.releaseTree(_content);
        clear(_content);
        if (_requiresReconcile) {
            var reconcile = node('div', 'settings-empty');
            reconcile.appendChild(node('h2', '', '写入状态等待权威核对'));
            reconcile.appendChild(node('p', '', '上一次请求可能已经生效；在游戏状态重新读取成功前，所有设置写入均保持锁定。'));
            var retry = button('重新读取权威状态', 'settings-button primary', function() {
                requestSnapshot('正在重新核对游戏权威状态；不会自动重放写入。');
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
        if (_activeTab === 'game') renderGame();
        else if (_activeTab === 'keys') renderKeys();
        else renderLocal();
    }

    function section(title, note) {
        var el = node('section', 'settings-section term-card term-corner-tick');
        var heading = node('div', 'settings-section-heading term-heading-rule');
        var identity = node('div', 'settings-section-identity');
        identity.appendChild(node('span', 'settings-section-code', SECTION_CODES[title] || 'SYSTEM BLOCK'));
        identity.appendChild(node('h2', '', title));
        heading.appendChild(identity);
        if (note) {
            var hint = button('?', 'settings-hint-trigger', null);
            hint.setAttribute('aria-label', title + '说明');
            heading.appendChild(annotate(hint, note, 'left'));
        }
        el.appendChild(heading);
        return el;
    }
    function field(label, control, note) {
        var row = node('label', 'settings-field');
        var copy = node('span', 'settings-field-copy');
        copy.appendChild(node('b', '', label));
        row.appendChild(copy);
        row.appendChild(control);
        if (note) {
            var focusTarget = control && control.matches && control.matches('button,input,select')
                ? control : control && control.querySelector ? control.querySelector('button,input,select') : null;
            annotate(focusTarget || row, note, 'bottom');
        }
        return row;
    }
    function checkbox(key, label, note, afterChange) {
        var input = document.createElement('input');
        input.type = 'checkbox'; input.checked = _draft.settings[key] === true;
        input.addEventListener('change', function() {
            _draft.settings[key] = input.checked; changed();
            if (afterChange) afterChange();
        });
        return field(label, input, note);
    }
    function selectControl(key, values) {
        var select = document.createElement('select'); select.className = 'settings-select';
        values.forEach(function(row) {
            var option = node('option', '', row[1]); option.value = String(row[0]);
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

    function renderGame() {
        var common = section('游戏常用设置');
        common.classList.add('settings-game-common');
        common.appendChild(renderRescueControls());

        var audioControls = node('div', 'settings-audio-grid');
        audioControls.appendChild(volumeField('setGlobalVolume', '总音量'));
        audioControls.appendChild(volumeField('setBGMVolume', '音乐音量'));
        audioControls.appendChild(annotate(
            button('试听界面音效', 'settings-button audition settings-audition-tile', function() {
                previewAudio('sfx');
            }),
            '播放一次 Web 界面提示音，方便判断当前音量。'));
        common.appendChild(gameBand('声音试听', 'AUDIO BUS', audioControls));

        var fields = node('div', 'settings-grid three settings-common-display-grid');
        fields.appendChild(field('性能等级上限',
            selectControl('性能等级上限', [[0,'0 · 保守'],[1,'1 · 完整']]),
            '保守模式减少部分画面效果；完整模式启用全部现役效果。'));
        fields.appendChild(field('立绘类型', selectControl('立绘类型', [[1,'类型 1'],[2,'类型 2']])));
        fields.appendChild(checkbox('是否阴影', '角色阴影'));
        fields.appendChild(checkbox('是否视觉元素', '视觉元素'));
        fields.appendChild(checkbox('使用滤镜渲染', '滤镜渲染'));
        fields.appendChild(checkbox('开启昼夜系统', '昼夜循环'));
        fields.appendChild(checkbox('暂停昼夜系统', '暂停昼夜变化'));
        common.appendChild(gameBand('画面与性能', 'DISPLAY CORE', fields));
        var homeCheat = cheatCommandForm();
        common.appendChild(gameBand('作弊码', 'COMMAND LINK', homeCheat));
        _content.appendChild(common);

        var camera = section('镜头缩放', '使用进入设置时的原分辨率静态画面模拟基础倍率，不会持续捕获游戏。');
        camera.classList.add('settings-camera-entry');
        var entry = node('div', 'settings-camera-entry-row');
        var summary = node('div', 'settings-camera-entry-copy');
        summary.appendChild(node('strong', '', Number(_draft.settings.basicZoomScale).toFixed(1) + '× 基础倍率'));
        entry.appendChild(summary);
        entry.appendChild(annotate(
            button('打开镜头预览', 'settings-button primary settings-camera-open', function(event) {
                openCameraSimulator(event.currentTarget);
            }),
            '用进入设置时的原分辨率静态画面预览基础镜头倍率；不是实时游戏画面。'));
        camera.appendChild(entry);
        _content.appendChild(camera);
    }

    function renderRescueControls() {
        var controls=node('div','settings-rescue-grid');
        var revive=button('尝试复活', 'settings-button primary', function() {
            sendTool('try_revive',{v:1},true);
        });
        revive.disabled=_snapshot.forceControls.tryReviveAvailable!==true;
        controls.appendChild(rescueCard('尝试复活', revive,
            _snapshot.forceControls.resurrectionRestricted
                ? '重新打开现役复活流程；当前关卡仍会执行自己的复活限制。'
                : '重新打开关卡结束后的现役复活流程。'));
        var base=button('立即返回基地', 'settings-button danger', function() {
            sendTool('return_base',{v:1},true);
        });
        base.disabled=_snapshot.forceControls.returnBaseAvailable!==true;
        controls.appendChild(rescueCard('返回基地', base, '立即跳过当前流程并返回基地，不再额外确认。'));
        var rescue = gameBand('流程救援', 'RECOVERY LINK', controls);
        rescue.classList.add('settings-rescue-strip');
        return rescue;
    }

    function gameBand(title, code, body) {
        var band = node('section', 'settings-game-band');
        var label = node('header', 'settings-game-band-label');
        label.appendChild(node('span', '', code));
        label.appendChild(node('h3', '', title));
        band.appendChild(label);
        band.appendChild(body);
        return band;
    }

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
        viewport.appendChild(node('span', 'settings-camera-safe-frame'));
        card.appendChild(viewport);
        var caption = node('figcaption', '', '入口静态帧 · 非实时画面');
        card.appendChild(caption);
        return card;
    }

    function updateCameraPreview() {
        if (!_draft) return;
        var scale = Number(_draft.settings.basicZoomScale);
        var baseline = Number(_entryCameraScale);
        if (!isFinite(scale) || scale < 0.5 || scale > 3) scale = 1;
        if (!isFinite(baseline) || baseline < 0.5 || baseline > 3) baseline = 1;
        var relativeScale = scale / baseline;
        if (_cameraPreviewImage) {
            _cameraPreviewImage.style.transform = 'scale(' + relativeScale.toFixed(3) + ')';
            _cameraPreviewImage.setAttribute('data-preview-scale', scale.toFixed(1));
            _cameraPreviewImage.setAttribute('data-preview-relative-scale', relativeScale.toFixed(3));
        }
        if (_cameraScaleHud) _cameraScaleHud.textContent = scale.toFixed(1) + '×';
        if (_cameraModeHud) {
            _cameraModeHud.textContent = _draft.settings.cameraZoomToggle === true
                ? '动态镜头：开启'
                : '固定基础倍率';
            _cameraModeHud.setAttribute('data-dynamic', _draft.settings.cameraZoomToggle === true ? 'on' : 'off');
        }
    }

    function volumeField(key, label) {
        var wrap = node('div', 'settings-range-wrap');
        var range = document.createElement('input'); range.type = 'range';
        range.min = '0'; range.max = '100'; range.step = '1'; range.value = String(_draft.settings[key]);
        var output = node('output', '', range.value + '%');
        range.addEventListener('input', function() {
            _draft.settings[key] = Number(range.value); output.textContent = range.value + '%';
            changed(); schedulePreview();
        });
        wrap.appendChild(range); wrap.appendChild(output);
        return field(label, wrap);
    }
    function rangeControl(key, min, max, step, afterInput) {
        var wrap = node('div', 'settings-range-wrap');
        var range = document.createElement('input'); range.type = 'range';
        range.min = String(min); range.max = String(max); range.step = String(step);
        range.value = String(_draft.settings[key]);
        var output = node('output', '', Number(range.value).toFixed(1) + '×');
        range.addEventListener('input', function() {
            _draft.settings[key] = Number(range.value);
            output.textContent = Number(range.value).toFixed(1) + '×'; changed();
            if (afterInput) afterInput();
        });
        wrap.appendChild(range); wrap.appendChild(output); return wrap;
    }

    function renderKeys() {
        var top = section('35 项权威键位', '点击一个键位后按新键。重复键、Esc 与 F1–F12 会被拒绝，不自动交换。');
        top.classList.add('settings-key-summary');
        var actions = node('div', 'settings-inline-actions');
        actions.appendChild(annotate(
            button('恢复全部默认', 'settings-button secondary', resetKeys),
            '把全部 35 项恢复为默认键位；仍需点击“应用并保存”。'));
        top.appendChild(actions);
        _content.appendChild(top);
        var groups = [
            {name:'移动与操作', start:0, end:7, columns:2, side:'left'},
            {name:'攻击模式', start:7, end:12, columns:2, side:'left'},
            {name:'快捷物品', start:12, end:16, columns:2, side:'left'},
            {name:'快捷技能', start:16, end:28, columns:3, side:'right'},
            {name:'战斗扩展', start:28, end:35, columns:2, side:'right'}
        ];
        var board = node('div', 'settings-key-board');
        var left = node('div', 'settings-key-column');
        var right = node('div', 'settings-key-column');
        groups.forEach(function(group) {
            var block = section(group.name);
            block.classList.add('settings-key-section');
            block.setAttribute('data-key-columns', String(group.columns));
            var list = node('div', 'settings-key-grid');
            for (var i = group.start; i < group.end; i++) list.appendChild(keyRow(i));
            block.appendChild(list);
            (group.side === 'left' ? left : right).appendChild(block);
        });
        board.appendChild(left); board.appendChild(right); _content.appendChild(board);
    }
    function keyRow(index) {
        var row = _draft.keys[index];
        var el = node('div', 'settings-key-row');
        el.setAttribute('data-key-index', String(index));
        var validation = SettingsRuntime.validateKeyDraft(_draft.keys, _snapshot.allowedKeyCodes);
        var invalid = !validation.valid && validation.indexes.indexOf(index) >= 0;
        el.classList.toggle('invalid', invalid);
        if (invalid) el.setAttribute('aria-invalid', 'true');
        el.appendChild(node('span', 'settings-key-label', row.label || row.id));
        var capture = button(_capturing === index ? '等待…'
            : SettingsRuntime.keyLabel(row.keyCode, _snapshot.allowedKeyCodes), 'settings-key-button', function() {
                _capturing = index; cue('activate'); renderCurrentTab();
            });
        capture.setAttribute('aria-label', _capturing === index
            ? row.label + '：等待新按键，Esc 取消'
            : row.label + '：当前为 ' + SettingsRuntime.keyLabel(row.keyCode, _snapshot.allowedKeyCodes));
        annotate(capture, _capturing === index
            ? '按下新的物理键；Esc 只取消本次捕获。'
            : '点击后按下新键；重复键、Esc 与 F1–F12 不会被接受。');
        capture.classList.toggle('capturing', _capturing === index);
        el.appendChild(capture); return el;
    }
    function onCaptureKey(event) {
        var pressed = Number(event.keyCode || event.which);
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
            _capturing = -1; setStatus('已取消键位捕获。', 'ready'); renderCurrentTab(); return;
        }
        var result = SettingsRuntime.validateKeyCandidate(
            _draft.keys, _capturing, code, _snapshot.allowedKeyCodes);
        if (!result.valid) {
            setStatus(result.error === 'key_conflict'
                ? '键位冲突：该物理键已经被另一项使用。'
                : '该键被保留或不受 Flash 支持，请换一个键。', 'error');
            cue('illegal'); return;
        }
        var candidate = SettingsRuntime.copy(_draft.keys);
        candidate[_capturing].keyCode = code;
        _draft.keys = candidate; _capturing = -1; cue('success'); changed(); renderCurrentTab();
    }
    function resetKeys() {
        var byId = {};
        _snapshot.defaultKeys.forEach(function(row) { byId[row.id] = row.keyCode; });
        _draft.keys.forEach(function(row) { row.keyCode = byId[row.id]; });
        _capturing = -1; changed(); renderCurrentTab();
    }

    function renderLocal() {
        var host = section('Launcher 本机偏好', '每一项在修改后立即由 Host 落盘；失败会回滚到权威值。');
        var hgrid = node('div', 'settings-grid two');
        hgrid.appendChild(hostBoolean('introEnabled', '下次启动播放片头动画'));
        hgrid.appendChild(hostBoolean('sfxEnabled', 'Web 界面音效'));
        hgrid.appendChild(hostBoolean('ambientEnabled', 'Web 环境音'));
        hgrid.appendChild(hostSelect('mapDisplayPreference', '地图显示',
            [['auto','自动'],['off','关闭'],['compact','紧凑'],['expanded','展开']]));
        hgrid.appendChild(hostRange());
        host.appendChild(hgrid); _content.appendChild(host);

        var hitNumber = section('打击伤害数字',
            '本机全局偏好；世界表达与精确对账分离，不占用任何战斗键。');
        var hitGrid = node('div', 'settings-grid two');
        hitGrid.appendChild(hostSelect('hitNumberMode', '显示行为',
            [['off','彻底关闭'],['balanced','平衡 · 目标锚定摘要'],
             ['total','总伤 · 每目标连段累计'],['classic','经典 · Flash 逐段散开'],
             ['detail','逐发 · Burst 完整矩阵']]));
        hitGrid.appendChild(hostNumber(
            'hitNumberWorldRowLimit',
            '世界攻击行上限',
            '0 表示真正无限制；非零值同时限制全局攻击行，逐发模式每个目标只保留最新 6 行，不影响独立对账日志。'));
        hitNumber.appendChild(hitGrid);
        var ledgerActions = node('div', 'settings-inline-actions settings-hit-number-actions');
        ledgerActions.appendChild(annotate(
            button('打开伤害对账日志', 'settings-button secondary settings-damage-ledger-open', function(event) {
                openDamageLedger(event.currentTarget);
            }),
            '暂停查看本场景最近的精确逐段记录；最多保留 32768 段，溢出会明确标记。'));
        hitNumber.appendChild(ledgerActions); _content.appendChild(hitNumber);

        var jukebox = section('点歌器运行规则', 'Flash 规则跟随底部“应用并保存”；Web 点歌器主题与其他本机偏好列在下方。');
        var jgrid = node('div', 'settings-grid three');
        jgrid.appendChild(checkbox('jukeboxOverride', '允许点歌覆盖'));
        jgrid.appendChild(checkbox('jukeboxTrueRandom', '真随机'));
        jgrid.appendChild(field('播放模式', selectControl('jukeboxPlayMode',
            [['singleLoop','单曲循环'],['albumLoop','专辑循环'],['playOnce','播放一次']])));
        jukebox.appendChild(jgrid);
        _content.appendChild(jukebox);

        var local = section('Web Panel 偏好', '复用各面板现有存储键；通常在重新打开对应面板后完整生效。');
        var list = node('div', 'settings-local-list');
        SettingsPreferences.list().forEach(function(pref) {
            var select = document.createElement('select'); select.className = 'settings-select';
            pref.values.forEach(function(value) {
                var option = node('option', '', optionLabel(value)); option.value = value; select.appendChild(option);
            });
            select.value = pref.value;
            select.addEventListener('change', function() {
                if (SettingsPreferences.write(pref.key, select.value)) {
                    setStatus('已保存 Web 偏好：“' + pref.label + '”。', 'ready'); cue('success');
                } else { select.value = SettingsPreferences.read(pref.key); setStatus('本机存储不可用，偏好未保存。', 'error'); }
            });
            list.appendChild(field(pref.label, select));
        });
        local.appendChild(list); _content.appendChild(local);
    }
    function hostBoolean(key, label) {
        var input = document.createElement('input'); input.type = 'checkbox';
        input.checked = _snapshot.hostPrefs[key] === true;
        input.setAttribute('data-host-key', key);
        input.addEventListener('change', function() { setHostPreference(key, input.checked, input); });
        return field(label, input);
    }
    function hostSelect(key, label, values) {
        var select = document.createElement('select'); select.className = 'settings-select';
        select.setAttribute('data-host-key', key);
        values.forEach(function(row) { var option = node('option','',row[1]); option.value=row[0]; select.appendChild(option); });
        select.value = String(_snapshot.hostPrefs[key]);
        select.addEventListener('change', function() { setHostPreference(key, select.value, select); });
        return field(label, select);
    }
    function hostNumber(key, label, hint) {
        var input = document.createElement('input'); input.type = 'number';
        input.className = 'settings-select'; input.min = '0'; input.max = '1000'; input.step = '1';
        input.value = String(_snapshot.hostPrefs[key]); input.setAttribute('data-host-key', key);
        input.addEventListener('change', function() {
            if (input.value.trim() === '') {
                applyHostControlValue(input, key, _snapshot.hostPrefs[key]);
                return;
            }
            var value = Number(input.value);
            if (!Number.isInteger(value) || value < 0 || value > 1000) {
                applyHostControlValue(input, key, _snapshot.hostPrefs[key]);
                return;
            }
            setHostPreference(key, value, input);
        });
        return field(label, input, hint);
    }
    function hostRange() {
        var wrap = node('div', 'settings-range-wrap');
        var range = document.createElement('input'); range.type='range'; range.min='0.7'; range.max='1.9'; range.step='0.05';
        range.value=String(_snapshot.hostPrefs.uiFontScale); range.setAttribute('data-host-key','uiFontScale');
        var output=node('output','',Number(range.value).toFixed(2)+'×');
        range.addEventListener('input',function(){ output.textContent=Number(range.value).toFixed(2)+'×'; });
        range.addEventListener('change',function(){ setHostPreference('uiFontScale',Number(range.value),range); });
        wrap.appendChild(range); wrap.appendChild(output);
        return field('启动页字号倍率',wrap,'下次启动完整生效');
    }
    function setHostPreference(key, value, control) {
        if (_requiresReconcile) {
            applyHostControlValue(control, key, _snapshot.hostPrefs[key]);
            setStatus('写入结果尚未核对，本机偏好保持锁定。', 'warning');
            return;
        }
        var previous = _snapshot.hostPrefs[key];
        control.disabled = true;
        var id = _mux.request('host_set', {v:1,key:key,value:value}, {kind:'host.'+key}, function(response) {
            var hasAuthority = response && response.currentValue !== undefined;
            var authoritative = hasAuthority ? response.currentValue : previous;
            _snapshot.hostPrefs[key] = authoritative;
            applyHostControlValue(control, key, authoritative);
            if (response && response.requiresReconcile === true) {
                reconcileUnknownWrite('本机偏好结果未知，正在重新读取权威状态；不会自动重试。');
                return;
            }
            control.disabled = false;
            var ok = response && response.success === true && hasAuthority;
            setStatus(ok ? '本机偏好已保存。'
                : '本机偏好未保存：' + errorText(response && response.error || 'malformed_response'),
                ok ? 'ready' : 'error');
        });
        if (!id) {
            control.disabled=false;
            applyHostControlValue(control, key, previous);
            setStatus('本机偏好请求未发出。','error');
        }
    }
    function applyHostControlValue(control, key, value) {
        if (control.type === 'checkbox') control.checked = value === true;
        else control.value = String(value);
        var output = control.parentNode && control.parentNode.querySelector
            ? control.parentNode.querySelector('output') : null;
        if (output && key === 'uiFontScale') output.textContent = Number(value).toFixed(2) + '×';
    }

    function cheatCommandForm() {
        var form = node('div', 'settings-cheat-form settings-home-cheat');
        var input = document.createElement('input'); input.type='text'; input.maxLength=240;
        input.placeholder='输入作弊码，例如 status 或 #level:15';
        input.id='settings-home-cheat-input';
        form.appendChild(input);
        form.appendChild(annotate(
            button('执行命令', 'settings-button danger', function() {
                var command=input.value.trim(); if (!command) return;
                confirmThen('cheat:'+command, '再次点击确认执行命令', function() {
                    sendTool('cheat',{v:1,command:command,confirmed:true},false);
                });
            }),
            '第一次点击进入待确认状态，再次点击才会把命令交给游戏。'));
        form.appendChild(annotate(
            button('作弊码帮助', 'settings-button secondary settings-cheat-help-open', function(event) {
                openCheatHelp(event.currentTarget);
            }),
            _snapshot.challengeMode
                ? '挑战模式只展示如何切换模式；命令输入仍保持可用。'
                : '查看完整现役指令并一键复制；复制不会自动执行。'));
        return form;
    }
    function rescueCard(title, action, copy) {
        var card=node('article','settings-rescue-card'); card.appendChild(node('h3','',title));
        card.appendChild(annotate(action, copy)); return card;
    }

    function openCameraSimulator(trigger) {
        if (_cameraModal || !_draft) return;
        _cameraReturnFocus = trigger || null;
        var layer = node('div', 'settings-modal-layer settings-camera-modal-layer');
        layer.addEventListener('click', function(event) {
            if (event.target === layer) closeCameraSimulator(true);
        });
        var dialog = node('section', 'settings-camera-modal');
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
        dialog.setAttribute('aria-labelledby', 'settings-camera-title');
        dialog.addEventListener('keydown', trapCameraFocus);

        var header = node('header', 'settings-camera-modal-header');
        var identity = node('div', 'settings-camera-modal-identity');
        identity.appendChild(node('span', 'settings-modal-kicker', 'CAMERA PREVIEW'));
        var title = node('h2', '', '镜头缩放模拟'); title.id = 'settings-camera-title';
        identity.appendChild(title);
        header.appendChild(identity);
        var help = button('?', 'settings-hint-trigger settings-camera-help', null);
        help.setAttribute('aria-label', '镜头预览说明');
        header.appendChild(annotate(help,
            '1×对应进入设置时的完整静态画面。提高倍率会以中心放大并裁切；低于入口倍率时，外围网格表示本次截图没有记录的额外视野。动态镜头只能在游戏运行中变化，这里只预览基础倍率。',
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
        zoom.classList.add('settings-camera-control-field');
        controls.appendChild(zoom);
        var dynamic = checkbox('cameraZoomToggle', '动态镜头调节',
            '关闭时仍使用固定基础倍率；开启后游戏可围绕基础倍率动态变化。', updateCameraPreview);
        dynamic.classList.add('settings-camera-control-field');
        controls.appendChild(dynamic);
        _cameraModeHud = node('p', 'settings-camera-mode-hud');
        controls.appendChild(_cameraModeHud);
        var actions = node('div', 'settings-camera-control-actions');
        actions.appendChild(annotate(
            button('恢复 1.0×', 'settings-button secondary', function() {
                _draft.settings.basicZoomScale = 1;
                var range = _cameraModal && _cameraModal.querySelector('input[type="range"]');
                if (range) {
                    range.value = '1';
                    var output = range.parentNode.querySelector('output');
                    if (output) output.textContent = '1.0×';
                }
                changed(); updateCameraPreview();
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
        var returnFocus = _cameraReturnFocus;
        if (_tooltipScope && _tooltipScope.releaseTree) _tooltipScope.releaseTree(_cameraModal);
        if (_cameraModal.parentNode) _cameraModal.parentNode.removeChild(_cameraModal);
        _cameraModal = null;
        _cameraReturnFocus = null;
        _cameraPreviewImage = null;
        _cameraScaleHud = null;
        _cameraModeHud = null;
        _pendingInitialCameraPreview = false;
        if (restoreFocus && _activeTab === 'game' && _snapshot && _draft) {
            renderCurrentTab();
            var freshTrigger = _content && _content.querySelector('.settings-camera-open');
            if (freshTrigger) freshTrigger.focus();
        } else if (restoreFocus && returnFocus && document.documentElement.contains(returnFocus)) {
            returnFocus.focus();
        }
    }

    function trapCameraFocus(event) {
        if (event.key !== 'Tab' || !_cameraModal) return;
        var focusable = _cameraModal.querySelectorAll('button, input, select, [tabindex]:not([tabindex="-1"])');
        if (!focusable.length) return;
        var first = focusable[0], last = focusable[focusable.length - 1];
        if (event.shiftKey && document.activeElement === first) {
            event.preventDefault(); last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault(); first.focus();
        }
    }

    function openCheatHelp(trigger) {
        if (_cheatModal) return;
        _helpReturnFocus = trigger || null;
        var layer = node('div', 'settings-modal-layer');
        layer.addEventListener('click', function(event) {
            if (event.target === layer) closeCheatHelp();
        });
        var dialog = node('section', 'settings-cheat-modal');
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
        dialog.setAttribute('aria-labelledby', 'settings-cheat-help-title');
        dialog.addEventListener('keydown', trapCheatHelpFocus);
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
        var returnFocus = _helpReturnFocus;
        if (_tooltipScope && _tooltipScope.releaseTree) _tooltipScope.releaseTree(_cheatModal);
        if (_cheatModal.parentNode) _cheatModal.parentNode.removeChild(_cheatModal);
        _cheatModal = null;
        _helpReturnFocus = null;
        if (returnFocus && document.documentElement.contains(returnFocus)) returnFocus.focus();
    }

    function openDamageLedger(trigger) {
        if (_damageLedgerModal) return;
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
        dialog.addEventListener('keydown', trapDamageLedgerFocus);

        var header = node('header', 'settings-damage-ledger-header');
        var identity = node('div', 'settings-damage-ledger-identity');
        identity.appendChild(node('span', 'settings-modal-kicker', 'EXACT DAMAGE RECONCILIATION'));
        var title = node('h2', '', '伤害对账日志'); title.id = 'settings-damage-ledger-title';
        identity.appendChild(title); header.appendChild(identity);
        header.appendChild(annotate(
            button('×', 'settings-terminal-close settings-damage-ledger-close', function() {
                closeDamageLedger(true);
            }), '关闭日志并返回打击数字设置。', 'left'));
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
        layer.appendChild(dialog); _root.appendChild(layer);
        _damageLedgerModal = layer;
        cue('activate');
        var close = dialog.querySelector('.settings-damage-ledger-close');
        if (close) close.focus();
        requestDamageLedger();
    }

    function closeDamageLedger(restoreFocus) {
        if (!_damageLedgerModal) return;
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
            {v:1,offset:_damageLedgerOffset,limit:24},
            {kind:'hit-number-ledger',latestWins:true}, function(response) {
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
                chip.style.color = color; chip.style.borderColor = color;
                segments.appendChild(chip);
            });
            card.appendChild(segments); body.appendChild(card);
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
        var colors = ['#ffffff','#ff4b4b','#ffcc00','#a94b70','#8d5bdb','#ac99ff',
            '#28adff','#c13a3a','#bca52e','#ff8e8e','#ffe770'];
        var colorId = (packed >> 18) & 15;
        return colors[Math.min(colorId, colors.length - 1)];
    }

    function trapDamageLedgerFocus(event) {
        if (event.key !== 'Tab' || !_damageLedgerModal) return;
        var focusable = _damageLedgerModal.querySelectorAll('button, [href], input, [tabindex]:not([tabindex="-1"])');
        if (!focusable.length) return;
        var first = focusable[0], last = focusable[focusable.length - 1];
        if (event.shiftKey && document.activeElement === first) {
            event.preventDefault(); last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault(); first.focus();
        }
    }

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
        var markdown = SettingsRuntime.selectCheatHelpMarkdown(
            _cheatHelpText, _snapshot.challengeMode);
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
        input.style.position = 'fixed'; input.style.opacity = '0';
        document.body.appendChild(input); input.select();
        var copied = false;
        try { copied = document.execCommand('copy'); } catch (copyError) { copied = false; }
        document.body.removeChild(input);
        return copied;
    }

    function trapCheatHelpFocus(event) {
        if (event.key !== 'Tab' || !_cheatModal) return;
        var focusable = _cheatModal.querySelectorAll('button, [href], input, [tabindex]:not([tabindex="-1"])');
        if (!focusable.length) return;
        var first = focusable[0], last = focusable[focusable.length - 1];
        if (event.shiftKey && document.activeElement === first) {
            event.preventDefault(); last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault(); first.focus();
        }
    }
    function confirmThen(key, prompt, callback) {
        if (_confirmAction !== key) {
            cancelConfirmation(); _confirmAction=key; setStatus(prompt+'（5 秒内有效）','warning'); cue('activate');
            _confirmTimer=setTimeout(cancelConfirmation,5000); return;
        }
        cancelConfirmation(); callback();
    }
    function cancelConfirmation() {
        if (_confirmTimer) clearTimeout(_confirmTimer);
        _confirmTimer=null; _confirmAction='';
    }
    function sendTool(cmd,payload,closeOnSuccess) {
        if (_busy || _requiresReconcile) return; _busy=true; refreshFooter();
        _mux.request(cmd,payload,{},function(response){
            _busy=false; refreshFooter();
            if(response&&response.success===true){
                cue('success'); setStatus(response.message||'操作已由游戏端接受。','ready');
                if(response.cheatHelp)_snapshot.cheatHelp=SettingsRuntime.copy(response.cheatHelp);
                if(response.challengeMode!==undefined)_snapshot.challengeMode=response.challengeMode===true;
                if(_cheatModal&&_cheatHelpText!==null)renderCheatHelpDocument();
                if(closeOnSuccess||response.closePanel===true) closeExact(); else renderCurrentTab();
            }else if(response&&response.requiresReconcile===true){
                reconcileUnknownWrite('游戏端结果未知，正在重新读取权威状态；不会自动重复执行。');
                return;
            }else{ cue('rejected'); setStatus('操作未执行：'+errorText(response&&response.error),'error'); }
        });
    }

    function schedulePreview() {
        if (_previewTimer) clearTimeout(_previewTimer);
        _previewTimer=setTimeout(function(){previewAudio('none');},120);
    }
    function previewAudio(sample) {
        if (!_draft || _busy || _requiresReconcile) return;
        _mux.request('preview',{v:1,globalVolume:_draft.settings.setGlobalVolume,
            bgmVolume:_draft.settings.setBGMVolume,sample:sample},
            {kind:'preview',latestWins:true,singleFlight:false},function(response){
                if(response&&response.success===true){_previewActive=true;if(sample==='sfx')setStatus('已播放试听音效。','ready');}
                else setStatus('试听失败：'+errorText(response&&response.error),'error');
            });
    }
    function changed() { refreshFooter(); }
    function applyGameDraft() {
        if (!_snapshot || !_draft || _busy || _requiresReconcile) return;
        var validation=SettingsRuntime.validateKeyDraft(_draft.keys,_snapshot.allowedKeyCodes);
        if(!validation.valid){showTab('keys');setStatus(validation.error==='key_conflict'?'仍有键位冲突。':'键位包含保留或无效按键。','error');return;}
        _busy=true; refreshFooter(); setStatus('正在应用并同步保存…','loading');
        _mux.request('apply',SettingsRuntime.applyPayload(_snapshot,_draft),{},function(response){
            _busy=false;
            if(response&&response.applied===true){
                _snapshot.revision=Number(response.revision);
                _snapshot.settings=SettingsRuntime.copy(response.settings||_draft.settings);
                _snapshot.keys=SettingsRuntime.copy(response.keys||_draft.keys);
                _draft=SettingsRuntime.gameDraft(_snapshot); _previewActive=false;
                _snapshot.migrationPending=response.migrationPending===true;
                _saveRetry.hidden=response.durable===true;
                setStatus(response.durable===true?'设置已应用并持久化。':'设置已应用，但落盘失败；请重试保存。',
                    response.durable===true?'ready':'error'); cue(response.durable===true?'success':'unknown');
            }else if(response&&response.error==='stale_state'){
                setStatus('状态已在别处变化，正在重新同步。','warning'); requestSnapshot(); return;
            }else if(response&&(response.error==='apply_ambiguous'||response.requiresReconcile===true)){
                reconcileUnknownWrite('应用结果未知，正在重新读取游戏权威状态；不会自动重放写入。'); return;
            }else setStatus('设置未应用：'+errorText(response&&response.error),'error');
            renderCurrentTab(); refreshFooter();
        });
    }
    function discardGameDraft() {
        if(!_snapshot||_busy||_requiresReconcile)return;
        _busy=true; refreshFooter();
        _mux.request('cancel',{v:1},{},function(response){
            _busy=false;
            if(response&&response.success===true){_draft=SettingsRuntime.gameDraft(_snapshot);_previewActive=false;_capturing=-1;setStatus('已放弃未应用改动并恢复试听音量。','ready');}
            else if(response&&response.requiresReconcile===true){
                reconcileUnknownWrite('试听恢复结果未知，正在重新读取游戏权威状态；面板保持打开。'); return;
            }
            else setStatus('恢复试听音量失败：'+errorText(response&&response.error),'error');
            renderCurrentTab();refreshFooter();
        });
    }
    function retrySave() {
        if(_busy||_requiresReconcile)return; _busy=true;refreshFooter();
        _mux.request('save',{v:1},{},function(response){
            _busy=false;
            var ok=response&&response.success===true&&response.durable===true;
            if(ok)_snapshot.migrationPending=response.migrationPending===true;
            if(!ok&&response&&response.requiresReconcile===true){
                reconcileUnknownWrite('保存结果未知，正在重新读取游戏权威状态；不会自动重试。'); return;
            }
            _saveRetry.hidden=ok;setStatus(ok?'设置已成功持久化。':'保存仍失败，请稍后重试。',ok?'ready':'error');refreshFooter();
        });
    }
    function requestClose() {
        if(_busy){setStatus('当前操作尚未结束，请稍候。','warning');return false;}
        if(_requiresReconcile){closeExact();return true;}
        var dirty=_snapshot&&_draft&&(SettingsRuntime.hasGameChanges(_snapshot,_draft)
            || _snapshot.migrationPending===true);
        if(dirty&&!window.confirm('有未应用的游戏设置或键位改动。放弃并关闭吗？'))return false;
        if(dirty||_previewActive){
            _busy=true;refreshFooter();
            _mux.request('cancel',{v:1},{},function(response){
                _busy=false;
                if(response&&response.success===true){_previewActive=false;closeExact();}
                else if(response&&response.requiresReconcile===true){
                    reconcileUnknownWrite('关闭前试听恢复结果未知，正在重新读取权威状态；面板保持打开。');
                }
                else{setStatus('关闭前恢复试听失败：'+errorText(response&&response.error),'error');refreshFooter();}
            });
            return true;
        }
        closeExact(); return true;
    }
    function closeExact() {
        if(_closeTimer)return;
        var instance=_instance;
        var sent=Bridge.send({type:'panel',cmd:'close',panel:'settings',panelInstanceId:instance});
        if(sent!==true){_busy=false;setStatus('关闭请求未发出，面板仍保持打开。','error');refreshFooter();return;}
        _busy=true;setStatus('正在等待 Host 确认关闭…','loading');refreshFooter();
        _closeTimer=setTimeout(function(){
            _closeTimer=null;_busy=false;
            setStatus('Host 尚未确认关闭，可再次尝试。','warning');refreshFooter();
        },3000);
    }
    function refreshFooter() {
        if(!_apply)return;
        var changed=_snapshot&&_draft&&(SettingsRuntime.hasGameChanges(_snapshot,_draft)
            || _snapshot.migrationPending===true);
        _apply.disabled=_busy||_requiresReconcile||!changed;
        var manualChanged=_snapshot&&_draft&&SettingsRuntime.hasGameChanges(_snapshot,_draft);
        _discard.disabled=_busy||_requiresReconcile||(!manualChanged&&!_previewActive);
        _saveRetry.disabled=_busy||_requiresReconcile;
    }
    function setStatus(text,state) {
        if(!_status)return;_status.textContent=text;_status.setAttribute('data-state',state||'ready');
    }
    function optionLabel(value) {
        return {safe:'逐步确认',fast:'快捷确认',rich:'完整',brief:'缩略',green:'绿色',amber:'琥珀',
            full:'完整',compact:'紧凑','0':'开启','1':'静音'}[value]||value;
    }
    function errorText(error) {
        return {reconcile_required:'必须先重新读取游戏权威状态',disconnected:'游戏连接已断开',timeout:'等待游戏响应超时',client_timeout:'等待响应超时',
            not_sent:'请求未发出',delivery_unknown:'请求投递结果未知',invalid_payload:'请求格式无效',invalid_settings:'设置值无效',invalid_keys:'键位表无效',
            key_conflict:'键位冲突',reserved_key:'按键被保留',stale_state:'状态已变化',save_failed:'保存失败',
            save_unavailable:'当前不可保存',settings_unavailable:'设置尚未初始化',revive_unavailable:'当前没有可恢复的复活流程',
            actor_alive:'角色尚未死亡',resurrection_restricted:'本关禁止复活',no_revive_coin:'没有复活币',
            revive_asset_failed:'复活币扣除未被确认，请重试',revive_asset_ambiguous:'复活币状态不明确，请重新同步后核对',
            respawn_dispatch_failed:'游戏未确认复活，复活币已返还',respawn_dispatch_rollback_failed:'复活失败且退款未确认，请立即核对复活币存量',
            return_in_progress:'正在返回基地',return_base_unavailable:'返回基地入口不可用',
            settlement_prepare_failed:'关卡结算尚未准备完成，请稍后重试',return_base_failed:'返回基地失败，请稍后重试',
            unknown_command:'无法识别该作弊码',
            apply_ambiguous:'应用结果未知，需要重新同步',key_refresh_failed:'键位缓存刷新失败，请重试同步',
            hit_number_ledger_unavailable:'伤害对账日志暂不可用',
            malformed_response:'游戏响应格式异常'}[error]||String(error||'未知错误');
    }
})();
