(function(global) {
    'use strict';

    var _cfg;
    var _pane;
    var _session = 0;
    var _boardId = '';
    var _skin = 'first-defense';
    var _entries = [];
    var _selectedTaskId = null;
    var _detail = null;

    var SKINS = {
        'first-defense': {
            eyebrow: 'FIRST DEFENSE LINE',
            title: '第一防线前线调度板',
            subtitle: '公开登记 · 按单行动 · 按线接应'
        }
    };

    function install(config) {
        _cfg = config || {};
        _pane = _cfg.paneEl;
        if (_pane) _pane.addEventListener('click', onClick);
    }

    function open(initData) {
        _session++;
        _boardId = String(initData && initData.boardId || 'first_defense');
        _skin = String(initData && initData.skin || 'first-defense');
        _entries = [];
        _selectedTaskId = null;
        _detail = null;
        renderShell(true);

        var requestSession = _session;
        _cfg.send('dispatchBoardSnapshot', { boardId: _boardId }, function(data) {
            if (requestSession !== _session) return;
            if (!data || !data.success) {
                renderError('调度目录暂时无法读取');
                return;
            }
            _entries = data.entries || [];
            renderShell(false);
            if (_entries.length) selectTask(_entries[0].taskId);
        });
    }

    function close() {
        _session++;
        _entries = [];
        _selectedTaskId = null;
        _detail = null;
        if (_pane) _pane.innerHTML = '';
    }

    function renderShell(loading) {
        if (!_pane) return;
        var meta = SKINS[_skin] || SKINS['first-defense'];
        _pane.setAttribute('data-board-skin', _skin);
        _pane.innerHTML = '' +
            '<div class="dispatch-shell">' +
                '<header class="dispatch-header">' +
                    '<div class="dispatch-heading">' +
                        '<span class="dispatch-eyebrow">' + esc(meta.eyebrow) + '</span>' +
                        '<strong class="dispatch-title">' + esc(meta.title) + '</strong>' +
                        '<span class="dispatch-subtitle">' + esc(meta.subtitle) + '</span>' +
                    '</div>' +
                    '<div class="dispatch-header-status"><span class="dispatch-live-dot"></span>线路在线</div>' +
                    '<button class="dispatch-close" type="button" title="关闭" aria-label="关闭">✕</button>' +
                '</header>' +
                '<div class="dispatch-body">' +
                    '<aside class="dispatch-index">' +
                        '<div class="dispatch-index-head"><span>行动与战例</span><b>' + (loading ? '…' : _entries.length) + '</b></div>' +
                        '<div class="dispatch-entry-list">' + (loading ? loadingHtml() : entriesHtml()) + '</div>' +
                        '<div class="dispatch-protocol">目标、路线、接应和报酬全部公开登记。未上板的行动不计入防线调度。</div>' +
                    '</aside>' +
                    '<main class="dispatch-detail">' +
                        (loading ? '<div class="dispatch-detail-empty">正在同步前线记录…</div>' : emptyDetailHtml()) +
                    '</main>' +
                '</div>' +
            '</div>';
    }

    function loadingHtml() {
        return '<div class="dispatch-entry-loading"><i></i><i></i><i></i></div>';
    }

    function entriesHtml() {
        if (!_entries.length) return '<div class="dispatch-entry-empty">当前没有已经登记的行动</div>';
        var html = '';
        for (var i = 0; i < _entries.length; i++) {
            var entry = _entries[i] || {};
            var selected = String(entry.taskId) === String(_selectedTaskId);
            var stateClass = entry.replay ? ' is-replay' : (entry.active ? ' is-active' : ' is-available');
            html += '<button type="button" class="dispatch-entry' + stateClass + (selected ? ' selected' : '') + '" data-task-id="' + attr(entry.taskId) + '">' +
                '<span class="dispatch-entry-pin" aria-hidden="true"></span>' +
                '<span class="dispatch-entry-kind">' + esc(entry.replay ? '复盘案例' : (entry.active ? '执行中' : '待登记')) + '</span>' +
                '<strong>' + esc(entry.title || ('任务 ' + entry.taskId)) + '</strong>' +
                '<span class="dispatch-entry-route">' + esc(entry.stageName || '路线待确认') + '</span>' +
                '<span class="dispatch-entry-order">NO.' + padOrder(entry.order, i + 1) + '</span>' +
            '</button>';
        }
        return html;
    }

    function emptyDetailHtml() {
        if (!_entries.length) {
            return '<div class="dispatch-detail-empty"><strong>线路安静</strong><span>新的求援和行动记录会在登记后出现在这里。</span></div>';
        }
        return '<div class="dispatch-detail-empty">从左侧选择一项委托</div>';
    }

    function renderError(message) {
        if (!_pane) return;
        var detail = _pane.querySelector('.dispatch-detail');
        var list = _pane.querySelector('.dispatch-entry-list');
        if (list) list.innerHTML = '<div class="dispatch-entry-empty">目录读取失败</div>';
        if (detail) detail.innerHTML = '<div class="dispatch-detail-empty is-error">' + esc(message) + '</div>';
    }

    function selectTask(taskId) {
        if (taskId == null || isBusy()) return;
        _selectedTaskId = taskId;
        _detail = null;
        refreshEntrySelection();
        var detailPane = _pane && _pane.querySelector('.dispatch-detail');
        if (detailPane) detailPane.innerHTML = '<div class="dispatch-detail-empty">正在调取任务简报…</div>';

        var requestSession = _session;
        var requestTaskId = taskId;
        _cfg.send('dispatchBoardDetail', { boardId: _boardId, taskId: requestTaskId }, function(data) {
            if (requestSession !== _session || String(requestTaskId) !== String(_selectedTaskId)) return;
            if (!data || !data.success || !data.detail) {
                renderDetailError((data && data.error) || 'detail_failed');
                return;
            }
            _detail = data.detail;
            renderDetail();
            requestBriefing(requestTaskId, requestSession);
        });
    }

    function refreshEntrySelection() {
        var list = _pane && _pane.querySelector('.dispatch-entry-list');
        if (!list) return;
        list.innerHTML = entriesHtml();
    }

    function renderDetail() {
        var detailPane = _pane && _pane.querySelector('.dispatch-detail');
        if (!detailPane || !_detail) return;
        var status = _detail.replay ? '已结案，可复盘' : (_detail.active ? '已登记，可出击' : '等待前治安官登记');
        var difficulty = _detail.stageDifficulty || '';
        var infoHtml = global.MissionBriefView && global.MissionBriefView.render
            ? global.MissionBriefView.render({
                detail: _detail,
                difficulty: difficulty,
                statusLabel: status,
                limits: _detail.normalLimits || [],
                limitsHtml: _cfg.limitsHtml,
                rewardsHtml: _cfg.rewardsHtml,
                escHtml: _cfg.escHtml,
                dialogueHtml: _cfg.dialogueHtml,
                dialogueMode: _cfg.getDialogueMode(),
                dialogueButtonText: _cfg.dialogueModeButtonText(),
                rewardsTitle: _detail.replay ? '首次结案奖励' : '任务奖励'
            })
            : '<div class="dispatch-detail-empty">任务简报组件未加载</div>';
        var canEnter = _detail.canEnter === true;
        var buttonLabel = canEnter ? (_detail.replay ? '进入战例复盘' : '按登记路线出击') : (_detail.active || _detail.replay ? '关卡尚未就绪' : '先向前治安官登记');
        var actionNote = _detail.replay
            ? '复盘不会重复结算任务奖励；关卡内收益仍按关卡规则处理。'
            : (_detail.blockReason || '出击后由任务系统按登记难度验收。');
        detailPane.innerHTML = '<div class="dispatch-brief-scroll">' + infoHtml + '</div>' +
            '<footer class="dispatch-actions">' +
                '<div class="dispatch-action-note">' + esc(actionNote) + '</div>' +
                '<button class="dispatch-enter" type="button"' + (canEnter ? '' : ' disabled') + '>' + esc(buttonLabel) + '</button>' +
            '</footer>';
    }

    function renderDetailError(error) {
        var detailPane = _pane && _pane.querySelector('.dispatch-detail');
        if (detailPane) detailPane.innerHTML = '<div class="dispatch-detail-empty is-error">无法读取任务简报（' + esc(error) + '）</div>';
    }

    function requestBriefing(taskId, requestSession) {
        _cfg.send('dispatchBoardBriefing', { boardId: _boardId, taskId: taskId }, function(data) {
            if (requestSession !== _session || String(taskId) !== String(_selectedTaskId)) return;
            var dialogue = _pane && _pane.querySelector('.dgn-dialogue');
            if (!dialogue) return;
            if (!data || !data.success || !data.lines || !data.lines.length) {
                dialogue.innerHTML = '<div class="tlv-dia-empty">暂无任务简报</div>';
                return;
            }
            _cfg.renderDialogue(dialogue, data.lines, data.heroPortrait, { staged: true, autoScroll: false });
        });
    }

    function doEnter() {
        if (!_detail || _detail.canEnter !== true || isBusy()) return;
        var requestSession = _session;
        var requestTaskId = _selectedTaskId;
        _cfg.beginOp();
        _cfg.send('dispatchBoardEnter', { boardId: _boardId, taskId: requestTaskId }, function(data) {
            _cfg.endOp();
            if (requestSession !== _session) return;
            if (data && data.success && data.entered) {
                // 权威结果音：出击成功（随后关面板进图，不再播 back，一动作一声）
                if (window.BootstrapAudio) window.BootstrapAudio.cue('success');
                _cfg.closeForEnter();
                return;
            }
            var error = (data && data.error) || 'unknown';
            var message = {
                task_not_active: '任务尚未登记，先与前治安官确认',
                stage_not_found: '任务关卡数据尚未就绪',
                board_mismatch: '该任务不属于当前调度板',
                disconnected: '连接已断开'
            }[error] || ('出击失败（' + error + '）');
            _cfg.toast(message, 'error');
        });
    }

    function onClick(event) {
        var target = event.target;
        var closeButton = closest(target, '.dispatch-close');
        if (closeButton) { _cfg.requestClose(); return; }

        var entryButton = closest(target, '.dispatch-entry');
        if (entryButton && _pane.contains(entryButton)) {
            selectTask(entryButton.getAttribute('data-task-id'));
            return;
        }

        var modeButton = closest(target, '[data-dialogue-mode-toggle]');
        if (modeButton && _pane.contains(modeButton)) {
            _cfg.toggleDialogueMode();
            if (_detail) {
                renderDetail();
                requestBriefing(_selectedTaskId, _session);
            }
            return;
        }

        if (closest(target, '.dispatch-enter')) doEnter();
    }

    function isBusy() {
        return _cfg && _cfg.isBusy && _cfg.isBusy();
    }

    function closest(node, selector) {
        return node && node.closest ? node.closest(selector) : null;
    }

    function padOrder(value, fallback) {
        var number = Number(value);
        if (!isFinite(number) || number < 0) number = fallback;
        number = Math.floor(number);
        return number < 10 ? '0' + number : String(number);
    }

    function esc(value) {
        return _cfg && _cfg.escHtml ? _cfg.escHtml(value) : String(value == null ? '' : value);
    }

    function attr(value) {
        return _cfg && _cfg.escAttr ? _cfg.escAttr(value) : esc(value);
    }

    global.DispatchBoardView = {
        install: install,
        open: open,
        close: close,
        getState: function() {
            return {
                boardId: _boardId,
                skin: _skin,
                entryCount: _entries.length,
                selectedTaskId: _selectedTaskId,
                hasDetail: !!_detail
            };
        }
    };
})(window);
