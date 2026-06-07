(function() {
    'use strict';

    // ═══════════════════════════════════════════════════════════
    // 状态
    // ═══════════════════════════════════════════════════════════
    var _el;
    var _tasks = [];
    var _activeIndex = -1;
    var _pendingReq = {};
    var _reqSeq = 0;
    var _session = 0;
    var _busy = false;
    var _iconsReady = false;
    var _cssLink = null;
    var _resizeObserver = null;

    // 设计分辨率
    var DESIGN_W = 1024;
    var DESIGN_H = 576;

    // DOM refs (set in createDOM)
    var _leftEl, _rightEl, _closeBtn;

    // ═══════════════════════════════════════════════════════════
    // Panel 注册
    // ═══════════════════════════════════════════════════════════
    Panels.register('tasks', {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: requestClose,
        onClose: onClose
    });

    // ═══════════════════════════════════════════════════════════
    // CSS 由外部文件 css/task_panel.css 提供，createDOM 时注入 <link>
    // ═══════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════
    // DOM 创建
    // ═══════════════════════════════════════════════════════════
    function createDOM(container) {
        _el = document.createElement('div');
        _el.style.position = 'absolute';
        _el.style.top = '0';
        _el.style.left = '0';
        _el.style.width = '100%';
        _el.style.height = '100%';
        _el.style.margin = '0';
        _el.style.padding = '0';

        _el.innerHTML = '' +
            '<div class="task-panel-scale-shell">' +
                '<div class="task-panel-container">' +
                    '<div class="task-panel-top">' +
                        '<button class="task-panel-close" title="关闭">✕</button>' +
                    '</div>' +
                    '<div class="task-panel-left" id="task-panel-left"></div>' +
                    '<div class="task-panel-right" id="task-panel-right">' +
                        '<div class="task-empty-hint">请从左侧选择一个任务</div>' +
                    '</div>' +
                '</div>' +
            '</div>';

        _leftEl = _el.querySelector('#task-panel-left');
        _rightEl = _el.querySelector('#task-panel-right');
        _closeBtn = _el.querySelector('.task-panel-close');

        // 关闭按钮
        _closeBtn.addEventListener('click', function() {
            requestClose();
        });

        container.appendChild(_el);
        return _el;
    }

    // ═══════════════════════════════════════════════════════════
    // 生命周期
    // ═══════════════════════════════════════════════════════════
    function onOpen(el, initData) {
        _session++;
        _tasks = [];
        _activeIndex = -1;
        _pendingReq = {};
        _busy = false;
        _iconsReady = false;
        _leftEl.innerHTML = '';
        _rightEl.innerHTML = '<div class="task-empty-hint">加载中...</div>';

        // 注入 CSS（每次打开时确保已加载；onClose 会移除）
        if (!document.getElementById('task-panel-css')) {
            _cssLink = document.createElement('link');
            _cssLink.id = 'task-panel-css';
            _cssLink.rel = 'stylesheet';
            _cssLink.href = 'css/task_panel.css';
            document.head.appendChild(_cssLink);
        }

        if (typeof Icons !== 'undefined' && Icons && Icons.load) {
            Icons.load(function() { _iconsReady = true; });
        }
        updateFitScale();
        bindScaleWatcher();
        requestSnapshot();
    }

    function requestClose() {
        if (_busy) return;
        Panels.close();
        Bridge.send({ type: 'panel', panel: 'tasks', cmd: 'close' });
    }

    function onClose() {
        _pendingReq = {};
        _busy = false;
        _session++;
        unbindScaleWatcher();
        if (_cssLink && _cssLink.parentNode) {
            _cssLink.parentNode.removeChild(_cssLink);
            _cssLink = null;
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 缩放（设计分辨率 1024×576 → 窗口自适应）
    // ═══════════════════════════════════════════════════════════
    function scheduleScaleUpdate() {
        if (typeof requestAnimationFrame === 'function') {
            requestAnimationFrame(updateFitScale);
        } else {
            setTimeout(updateFitScale, 0);
        }
    }

    function updateFitScale() {
        if (!_el) return;
        var width = _el.clientWidth || _el.offsetWidth || 0;
        var height = _el.clientHeight || _el.offsetHeight || 0;
        if (!width || !height) return;
        var scale = Math.min(width / DESIGN_W, height / DESIGN_H);
        if (!isFinite(scale) || scale <= 0) scale = 1;
        _el.style.setProperty('--task-scale', scale.toFixed(4));
    }

    function bindScaleWatcher() {
        unbindScaleWatcher();
        window.addEventListener('resize', scheduleScaleUpdate);
        if (typeof ResizeObserver !== 'undefined' && _el) {
            _resizeObserver = new ResizeObserver(scheduleScaleUpdate);
            _resizeObserver.observe(_el);
            if (_el.parentElement) _resizeObserver.observe(_el.parentElement);
        }
    }

    function unbindScaleWatcher() {
        window.removeEventListener('resize', scheduleScaleUpdate);
        if (_resizeObserver) {
            _resizeObserver.disconnect();
            _resizeObserver = null;
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 通信
    // ═══════════════════════════════════════════════════════════
    Bridge.on('panel_resp', function(data) {
        if (!data || data.panel !== 'tasks') return;
        var handler = _pendingReq[data.callId];
        if (handler) {
            delete _pendingReq[data.callId];
            if (typeof handler === 'function') {
                handler(data);
            }
        }
    });

    function sendPanelMsg(cmd, extra, cb) {
        var callId = 'task_' + (++_reqSeq) + '_' + Date.now();
        if (cb) _pendingReq[callId] = cb;
        var msg = { type: 'panel', panel: 'tasks', cmd: cmd, callId: callId };
        if (extra) {
            for (var k in extra) {
                if (extra.hasOwnProperty(k)) msg[k] = extra[k];
            }
        }
        Bridge.send(msg);
        return callId;
    }

    // ═══════════════════════════════════════════════════════════
    // Snapshot — 拉取全部任务概要
    // ═══════════════════════════════════════════════════════════
    function requestSnapshot() {
        var snapSession = _session;
        sendPanelMsg('snapshot', null, function(data) {
            if (snapSession !== _session) return;
            if (!data.success) {
                _leftEl.innerHTML = '<div class="task-empty-hint">获取任务数据失败</div>';
                return;
            }
            _tasks = data.tasks || [];
            renderTaskList();
            if (_tasks.length > 0) {
                requestDetail(0);
            }
        });
    }

    // ═══════════════════════════════════════════════════════════
    // Detail — 加载单个任务详情
    // ═══════════════════════════════════════════════════════════
    function requestDetail(index) {
        var snapSession = _session;
        _activeIndex = index;
        highlightActiveIcon();
        _rightEl.innerHTML = '<div class="task-empty-hint">加载中...</div>';
        sendPanelMsg('detail', { index: index }, function(data) {
            if (snapSession !== _session) return;
            if (!data.success) {
                _rightEl.innerHTML = '<div class="task-empty-hint">加载任务详情失败: ' + (data.error || '未知错误') + '</div>';
                return;
            }
            renderTaskDetail(data.taskData);
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：左侧任务列表
    // ═══════════════════════════════════════════════════════════
    function renderTaskList() {
        _leftEl.innerHTML = '';
        if (_tasks.length === 0) {
            _leftEl.innerHTML = '<div class="task-empty-hint">暂无任务</div>';
            return;
        }

        for (var i = 0; i < _tasks.length; i++) {
            var task = _tasks[i];
            var btn = document.createElement('button');
            btn.className = 'task-icon';
            btn.dataset.index = i;
            btn.innerHTML = '' +
                '<div class="task-icon-left">' +
                    '<div class="task-icon-type">' + escHtml(task.type || '') + '</div>' +
                    '<div class="task-icon-name">' + escHtml(task.title || '') + '</div>' +
                '</div>' +
                '<div class="task-icon-avatar"><img src="' + avatarUrl(task.npcName) + '" onerror="this.onerror=null;this.src=\'' + defaultAvatarUrl() + '\';" alt=""></div>' +
                (task.satisfied ? '<img class="task-finished-overlay" src="/modules/tasks/assets/task_finished_icon.png" alt="">' : '');

            btn.addEventListener('click', (function(idx) {
                return function() { requestDetail(idx); };
            })(i));

            _leftEl.appendChild(btn);
        }
    }

    function highlightActiveIcon() {
        var buttons = _leftEl.querySelectorAll('.task-icon');
        for (var i = 0; i < buttons.length; i++) {
            var idx = parseInt(buttons[i].dataset.index, 10);
            if (idx === _activeIndex) {
                buttons[i].classList.add('active');
            } else {
                buttons[i].classList.remove('active');
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：右侧任务详情
    // ═══════════════════════════════════════════════════════════
    function renderTaskDetail(task) {
        if (!task) {
            _rightEl.innerHTML = '<div class="task-empty-hint">无任务数据</div>';
            return;
        }

        var html = '';

        // 任务标题
        html += '<div class="task-title-box">' +
            '<span class="task-title-line1">任务详情</span>' +
            '<span class="task-title-line2">' + escHtml(task.title || '') + '</span>' +
        '</div>';

        // 任务描述
        html += '<div class="task-desc-box">';
        html += escHtml(task.description || '');
        html += '<span class="corner-horizontal top-left"></span>';
        html += '<span class="corner-horizontal top-right"></span>';
        html += '<span class="corner-horizontal bottom-left"></span>';
        html += '<span class="corner-horizontal bottom-right"></span>';
        html += '<span class="corner-vertical top-left"></span>';
        html += '<span class="corner-vertical top-right"></span>';
        html += '<span class="corner-vertical bottom-left"></span>';
        html += '<span class="corner-vertical bottom-right"></span>';
        html += '</div>';

        // 任务需求区
        html += '<div class="task-requirement-area">';

        // 关卡需求
        if (task.stageReq) {
            html += '<div class="task-requirement">';
            html += '<div class="task-requirement-inner">';
            html += '<div class="scroll-track"></div>';
            html += '<div class="task-requirement-title stage"></div>';
            html += '<div class="task-requirement-stage-name">' + escHtml(task.stageReq.name || '') + '</div>';
            html += '</div>';
            if (task.stageReq.difficulty) {
                html += '<span class="task-difficulty-label difficulty-' + escHtml(task.stageReq.difficulty) + '">' + escHtml(task.stageReq.difficulty) + '</span>';
            }
            html += '</div>';
        }

        // 物品需求
        if (task.itemReqs && task.itemReqs.length > 0) {
            var kind = task.itemReqs[0].kind || 'submit';
            var titleClass = kind === 'contain' ? 'contain' : 'submit';
            html += '<div class="task-item-requirement">';
            html += '<div class="task-item-requirement-inner">';
            html += '<div class="scroll-track"></div>';
            html += '<div class="task-requirement-title ' + titleClass + '"></div>';
            html += '<div class="task-requirement-items">';
            for (var ir = 0; ir < task.itemReqs.length; ir++) {
                var item = task.itemReqs[ir];
                html += itemIconHtml(item.name, item.count);
            }
            html += '</div></div></div>';
        }

        // NPC
        if (task.npcName) {
            html += '<div class="task-npc">';
            html += '<div class="task-npc-left">';
            html += '<div class="scroll-track"></div>';
            html += '<div class="task-npc-title"></div>';
            html += '<div class="task-npc-name"><span>' + escHtml(task.npcName) + '</span></div>';
            html += '</div>';
            html += '<div class="task-npc-avatar"><img src="' + avatarUrl(task.npcName) + '" onerror="this.onerror=null;this.src=\'' + defaultAvatarUrl() + '\';" alt=""></div>';
            html += '</div>';
        }

        html += '</div>'; // .task-requirement-area

        // 任务奖励
        if (task.rewards && task.rewards.length > 0) {
            html += '<div class="task-reward-section">';
            html += '<div class="task-reward-box"><span>任务奖励</span></div>';
            html += '<div class="task-reward-items">';
            for (var r = 0; r < task.rewards.length; r++) {
                var reward = task.rewards[r];
                html += itemIconHtml(reward.name, reward.count);
            }
            html += '</div></div>';
        }

        _rightEl.innerHTML = html;
    }

    // ═══════════════════════════════════════════════════════════
    // 工具函数
    // ═══════════════════════════════════════════════════════════
    function escHtml(s) {
        if (!s) return '';
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    function resolveIconUrl(itemName) {
        if (!itemName) return null;
        if (typeof Icons !== 'undefined' && Icons && Icons.resolve) {
            return Icons.resolve(itemName);
        }
        return null;
    }

    function itemIconHtml(itemName, count) {
        var url = resolveIconUrl(itemName);
        var imgHtml = url
            ? '<img src="' + escHtml(url) + '" style="width:28px;height:28px;object-fit:contain;display:block;" alt="">'
            : '';
        return '<div class="task-item">' + imgHtml
            + '<span class="task-item-count">' + escHtml(String(count)) + '</span></div>';
    }

    var ASSETS_BASE = 'https://cfn-assets.local/portraits/profiles/';
    var DEFAULT_AVATAR = ASSETS_BASE + encodeURIComponent('无头像') + '.png';

    function avatarUrl(npcName) {
        var name = npcName || '';
        return ASSETS_BASE + encodeURIComponent(name) + '.png';
    }

    function defaultAvatarUrl() {
        return DEFAULT_AVATAR;
    }
})();
