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
    // CSS 模板（从 harness.html 提取，适配面板容器）
    // ═══════════════════════════════════════════════════════════
    var CSS = '' +
        '.task-panel-container {' +
            'width: 100%;' +
            'height: 100%;' +
            'background-image: url(\'modules/tasks/dev/task_main_bg.png\');' +
            'background-size: 100% 100%;' +
            'font-family: system-ui, sans-serif;' +
            'display: flex;' +
            'flex-wrap: wrap;' +
        '}' +
        '.task-panel-top {' +
            'width: 100%;' +
            'height: 10%;' +
            'box-sizing: border-box;' +
            'padding: 4px;' +
            'display: flex;' +
            'align-items: center;' +
            'justify-content: flex-end;' +
        '}' +
        '.task-panel-close {' +
            'width: 36px;' +
            'height: 36px;' +
            'background: rgba(255,255,255,0.08);' +
            'border: 1px solid rgba(255,255,255,0.2);' +
            'border-radius: 4px;' +
            'color: #fff;' +
            'font-size: 20px;' +
            'cursor: pointer;' +
            'display: flex;' +
            'align-items: center;' +
            'justify-content: center;' +
            'margin-right: 8px;' +
            'user-select: none;' +
        '}' +
        '.task-panel-close:hover {' +
            'background: rgba(255,80,80,0.3);' +
            'border-color: rgba(255,80,80,0.5);' +
        '}' +
        '.task-panel-left {' +
            'width: 26%;' +
            'height: 90%;' +
            'box-sizing: border-box;' +
            'padding: 4px;' +
            'display: flex;' +
            'flex-direction: column;' +
            'overflow-y: auto;' +
        '}' +
        '.task-panel-left::-webkit-scrollbar { width: 4px; }' +
        '.task-panel-left::-webkit-scrollbar-track { background: rgba(0,240,255,0.03); }' +
        '.task-panel-left::-webkit-scrollbar-thumb { background: rgba(0,240,255,0.15); border-radius: 2px; }' +
        '.task-panel-left::-webkit-scrollbar-thumb:hover { background: rgba(0,240,255,0.3); }' +
        '.task-panel-right {' +
            'width: 74%;' +
            'height: 90%;' +
            'box-sizing: border-box;' +
            'padding: 4px;' +
            'display: flex;' +
            'flex-direction: column;' +
        '}' +
        '.task-icon {' +
            'background-image: url(\'modules/tasks/dev/task_icon_bg.png\');' +
            'background-color: transparent;' +
            'background-size: 100%;' +
            'position: relative;' +
            'overflow: hidden;' +
            'width: 220px;' +
            'height: 110px;' +
            'margin-bottom: 10px;' +
            'margin-left: 8px;' +
            'box-sizing: border-box;' +
            'padding: 5px;' +
            'display: flex;' +
            'flex-direction: row;' +
            'align-items: center;' +
            'gap: 2px;' +
            'color: #fff;' +
            'user-select: none;' +
            'border: none;' +
            'cursor: pointer;' +
            'flex-shrink: 0;' +
        '}' +
        '.task-icon.active {' +
            'outline: 2px solid rgba(0,240,255,0.6);' +
            'outline-offset: -2px;' +
        '}' +
        '.task-icon-left {' +
            'flex: 1;' +
            'min-width: 0;' +
            'display: flex;' +
            'flex-direction: column;' +
            'justify-content: center;' +
            'box-sizing: border-box;' +
            'padding-left: 6px;' +
            'text-align: left;' +
        '}' +
        '.task-icon-type {' +
            'font-size: 13px;' +
            'color: rgba(255,255,255,0.55);' +
            'line-height: 1.3;' +
        '}' +
        '.task-icon-name {' +
            'font-size: 16px;' +
            'color: #fff;' +
            'line-height: 1.4;' +
            'font-weight: 600;' +
            'white-space: nowrap;' +
            'overflow: hidden;' +
            'text-overflow: ellipsis;' +
        '}' +
        '.task-icon-avatar {' +
            'flex-shrink: 0;' +
            'width: 100px;' +
            'height: 100px;' +
            'background: rgba(255,255,255,0.06);' +
            'border: 1px solid rgba(255,255,255,0.15);' +
            'border-radius: 4px;' +
            'box-sizing: border-box;' +
            'overflow: hidden;' +
        '}' +
        '.task-icon-avatar img {' +
            'width: 100%;' +
            'height: 100%;' +
            'object-fit: cover;' +
            'display: block;' +
        '}' +
        '.task-icon::after {' +
            'content: \'\';' +
            'position: absolute;' +
            'top: -200%;' +
            'left: 0;' +
            'width: 100%;' +
            'height: 300%;' +
            'background: linear-gradient(' +
                'to bottom,' +
                'rgba(255, 255, 255, 0.2) 0%,' +
                'transparent 25%,' +
                'transparent 50%,' +
                'rgba(255, 255, 255, 0.3) 70%,' +
                'rgba(255, 255, 255, 0.3) 80%,' +
                'transparent 100%' +
            ');' +
            'opacity: 0;' +
            'animation: none;' +
        '}' +
        '.task-icon:hover::after {' +
            'animation: task-sweep-down 3.0s ease-out forwards;' +
        '}' +
        '@keyframes task-sweep-down {' +
            '0%   { top: -200%; opacity: 1; }' +
            '100% { top: 0%; opacity: 1; }' +
        '}' +
        '.task-title-box {' +
            'position: relative;' +
            'overflow: hidden;' +
            'box-sizing: border-box;' +
            'width: 720px;' +
            'height: 60px;' +
            'padding: 0 20px 0 20px;' +
            'text-align: left;' +
            'color: #fff;' +
            'font-size: 24px;' +
            'flex-shrink: 0;' +
        '}' +
        '.task-title-box::after {' +
            'content: \'\';' +
            'position: absolute;' +
            'top: 0;' +
            'left: 0;' +
            'right: 0;' +
            'bottom: 0;' +
            'background: #ccc;' +
            'transform-origin: left center;' +
            'animation: task-shrink-reveal 0.8s ease-out forwards;' +
        '}' +
        '@keyframes task-shrink-reveal {' +
            '0%   { transform: scaleX(1); }' +
            '50%  { transform: scaleX(0.005); }' +
            '100% { transform: scaleX(0.015); }' +
        '}' +
        '.task-desc-box {' +
            'position: relative;' +
            'box-sizing: border-box;' +
            'width: 720px;' +
            'height: 120px;' +
            'padding: 12px 30px 12px 30px;' +
            'margin: 20px 0;' +
            'text-align: left;' +
            'background: transparent;' +
            'color: #fff;' +
            'font-size: 24px;' +
            'overflow: hidden;' +
            'flex-shrink: 0;' +
        '}' +
        '.task-desc-box .corner-horizontal {' +
            'position: absolute;' +
            'width: 8px;' +
            'height: 8px;' +
            'background: #ccc;' +
            'animation: task-stretch-horizontal 0.5s ease-out forwards;' +
        '}' +
        '.task-desc-box .corner-vertical {' +
            'position: absolute;' +
            'width: 8px;' +
            'height: 8px;' +
            'background: #ccc;' +
            'animation: task-stretch-vertical 0.5s ease-out forwards;' +
        '}' +
        '.corner-horizontal.top-left    { top: 0; left: 0;   transform-origin: left top; }' +
        '.corner-horizontal.top-right   { top: 0; right: 0;  transform-origin: right top; animation-delay: 0.5s; }' +
        '.corner-horizontal.bottom-left { bottom: 0; left: 0; transform-origin: left bottom; animation-delay: 0.5s; }' +
        '.corner-horizontal.bottom-right{ bottom: 0; right: 0; transform-origin: right bottom; }' +
        '.corner-vertical.top-left    { top: 0; left: 0;   transform-origin: left top; animation-delay: 0.5s; }' +
        '.corner-vertical.top-right   { top: 0; right: 0;  transform-origin: right top; }' +
        '.corner-vertical.bottom-left { bottom: 0; left: 0; transform-origin: left bottom; }' +
        '.corner-vertical.bottom-right{ bottom: 0; right: 0; transform-origin: right bottom; animation-delay: 0.5s; }' +
        '@keyframes task-stretch-horizontal {' +
            'from { transform: scaleX(1); }' +
            'to   { transform: scaleX(3); }' +
        '}' +
        '@keyframes task-stretch-vertical {' +
            'from { transform: scaleY(1); }' +
            'to   { transform: scaleY(3); }' +
        '}' +
        '.task-requirement-area {' +
            'display: flex;' +
            'flex-wrap: wrap;' +
            'align-items: flex-start;' +
            'gap: 10px;' +
            'margin: 10px 0;' +
            'padding: 4px 0;' +
        '}' +
        '.task-requirement {' +
            'width: 175px;' +
            'height: 100px;' +
            'background: radial-gradient(circle, rgba(0, 0, 0, 0.2) 0 1px, transparent 1.2px) 0 0 / 7px 7px, linear-gradient(to bottom, #d8d8d8 30%, #999 70%);' +
            'border-radius: 8px;' +
            'display: flex;' +
            'align-items: center;' +
            'justify-content: center;' +
            'flex-shrink: 0;' +
            'margin-right: 20px;' +
        '}' +
        '.task-item-requirement {' +
            'width: 175px;' +
            'min-height: 100px;' +
            'background: radial-gradient(circle, rgba(0, 0, 0, 0.2) 0 1px, transparent 1.2px) 0 0 / 7px 7px, linear-gradient(to bottom, #d8d8d8 30%, #999 70%);' +
            'border-radius: 8px;' +
            'display: flex;' +
            'align-items: center;' +
            'justify-content: center;' +
            'flex-shrink: 0;' +
            'margin-right: 20px;' +
        '}' +
        '.task-npc {' +
            'width: 270px;' +
            'height: 100px;' +
            'background: radial-gradient(circle, rgba(0, 0, 0, 0.2) 0 1px, transparent 1.2px) 0 0 / 7px 7px, linear-gradient(to bottom, #ffb547 30%, #f60 70%);' +
            'border-radius: 8px;' +
            'display: flex;' +
            'flex-direction: row;' +
            'align-items: flex-start;' +
            'padding: 5px;' +
            'box-sizing: border-box;' +
            'flex-shrink: 0;' +
            'margin-right: 20px;' +
        '}' +
        '.task-requirement-inner {' +
            'width: 165px;' +
            'height: 90px;' +
            'overflow: hidden;' +
            'border-radius: 8px;' +
            'display: flex;' +
            'flex-direction: column;' +
            'align-items: flex-start;' +
            'padding-top: 4px;' +
        '}' +
        '.task-item-requirement-inner {' +
            'width: 165px;' +
            'min-height: 90px;' +
            'overflow: hidden;' +
            'border-radius: 8px;' +
            'display: flex;' +
            'flex-direction: column;' +
            'align-items: flex-start;' +
            'padding-top: 4px;' +
        '}' +
        '.task-npc-left {' +
            'width: 160px;' +
            'height: 90px;' +
            'overflow: hidden;' +
            'border-radius: 8px;' +
            'flex-shrink: 0;' +
            'display: flex;' +
            'flex-direction: column;' +
        '}' +
        '.task-npc-avatar {' +
            'flex-shrink: 0;' +
            'width: 90px;' +
            'height: 90px;' +
            'background: rgba(255,255,255,0.06);' +
            'border: none;' +
            'border-radius: 4px;' +
            'margin-left: 8px;' +
            'overflow: hidden;' +
        '}' +
        '.task-npc-avatar img {' +
            'width: 100%;' +
            'height: 100%;' +
            'object-fit: cover;' +
            'display: block;' +
        '}' +
        '.task-requirement-title {' +
            'width: 160px;' +
            'height: 40px;' +
            'margin-top: 3px;' +
            'margin-left: 2px;' +
            'background-size: 100%;' +
        '}' +
        '.task-requirement-title.stage {' +
            'background-image: url(\'modules/tasks/dev/requirement_stage.png\');' +
        '}' +
        '.task-requirement-title.submit {' +
            'background-image: url(\'modules/tasks/dev/requirement_submit.png\');' +
        '}' +
        '.task-requirement-title.contain {' +
            'background-image: url(\'modules/tasks/dev/requirement_contain.png\');' +
        '}' +
        '.task-requirement-stage-name {' +
            'width: 155px;' +
            'margin-top: 2px;' +
            'margin-left: 2px;' +
            'text-align: left;' +
            'color: #333;' +
            'font-size: 14px;' +
            'font-weight: 600;' +
            'white-space: nowrap;' +
            'overflow: hidden;' +
            'text-overflow: ellipsis;' +
        '}' +
        '.task-npc-title {' +
            'width: 160px;' +
            'height: 40px;' +
            'margin-top: 3px;' +
            'margin-left: 2px;' +
            'background-image: url(\'modules/tasks/dev/finish_npc.png\');' +
            'background-size: cover;' +
        '}' +
        '.task-npc-name {' +
            'overflow: hidden;' +
            'position: relative;' +
            'width: 160px;' +
            'height: 22px;' +
            'box-sizing: border-box;' +
            'padding: 0 20px 2px 20px;' +
            'text-align: left;' +
            'font-size: 18px;' +
        '}' +
        '.task-npc-name::after {' +
            'content: \'\';' +
            'position: absolute;' +
            'top: 0;' +
            'left: 0;' +
            'right: 0;' +
            'bottom: 0;' +
            'background: #000;' +
            'transform-origin: left center;' +
            'animation: task-npc-reveal 0.5s ease-out forwards;' +
        '}' +
        '@keyframes task-npc-reveal {' +
            '0%   { transform: scaleX(0.1); }' +
            '80%  { transform: scaleX(1); left: 0; }' +
            '100% { left: 100%; }' +
        '}' +
        '.scroll-track {' +
            'background-image: url(\'modules/tasks/dev/task_scroll.png\');' +
            'display: block;' +
            'animation: task-slowRoll 0.5s linear infinite;' +
            'width: 180px;' +
            'height: 5px;' +
            'flex-shrink: 0;' +
            'user-select: none;' +
            'pointer-events: none;' +
        '}' +
        '@keyframes task-slowRoll {' +
            '0%   { transform: translateX(-15px); }' +
            '100% { transform: translateX(0); }' +
        '}' +
        '.task-reward-box {' +
            'position: relative;' +
            'overflow: hidden;' +
            'box-sizing: border-box;' +
            'width: 120px;' +
            'height: 36px;' +
            'padding: 2px;' +
            'text-align: left;' +
            'color: #000;' +
            'font-size: 24px;' +
        '}' +
        '.task-reward-box::after {' +
            'content: \'\';' +
            'position: absolute;' +
            'top: 0;' +
            'left: 0;' +
            'right: 0;' +
            'bottom: 0;' +
            'background: radial-gradient(circle, rgba(0, 0, 0, 0.2) 0 1px, transparent 1.2px) 0 0 / 7px 7px, linear-gradient(to bottom, #d8d8d8 30%, #999 70%);' +
            'transform-origin: right center;' +
            'animation: task-reward-reveal 0.5s ease-out forwards;' +
        '}' +
        '.task-reward-box span {' +
            'position: relative;' +
            'z-index: 1;' +
        '}' +
        '@keyframes task-reward-reveal {' +
            '0%   { left: 90%; }' +
            '100%  { left: 0; }' +
        '}' +
        '.task-reward-section {' +
            'flex-shrink: 0;' +
            'padding: 4px 0;' +
            'display: flex;' +
            'flex-direction: row;' +
            'align-items: flex-start;' +
            'gap: 8px;' +
        '}' +
        '.task-reward-items {' +
            'display: flex;' +
            'gap: 4px;' +
            'flex-wrap: wrap;' +
        '}' +
        '.task-requirement-items {' +
            'display: flex;' +
            'gap: 4px;' +
            'flex-wrap: wrap;' +
            'margin-top: 4px;' +
        '}' +
        '.task-item {' +
            'position: relative;' +
            'width: 32px;' +
            'height: 32px;' +
            'background: rgba(0, 0, 0, 0.4) url(\'modules/tasks/dev/item_bg.png\') center/cover no-repeat;' +
            'border: 1px solid rgba(255, 255, 255, 0.12);' +
            'border-radius: 3px;' +
            'overflow: hidden;' +
            'flex-shrink: 0;' +
            'display: flex;' +
            'align-items: center;' +
            'justify-content: center;' +
        '}' +
        '.task-item-count {' +
            'position: absolute;' +
            'right: 1px;' +
            'bottom: 1px;' +
            'font-size: 10px;' +
            'color: #fff;' +
            'background: rgba(0, 0, 0, 0.7);' +
            'padding: 0 3px;' +
            'border-radius: 2px;' +
            'line-height: 1.4;' +
            'pointer-events: none;' +
        '}' +
        '.task-empty-hint {' +
            'color: rgba(255,255,255,0.4);' +
            'font-size: 18px;' +
            'text-align: center;' +
            'margin-top: 40px;' +
        '}';

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
            '<style>' + CSS + '</style>' +
            '<div class="task-panel-container">' +
                '<div class="task-panel-top">' +
                    '<button class="task-panel-close" title="关闭">✕</button>' +
                '</div>' +
                '<div class="task-panel-left" id="task-panel-left"></div>' +
                '<div class="task-panel-right" id="task-panel-right">' +
                    '<div class="task-empty-hint">请从左侧选择一个任务</div>' +
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
        if (typeof Icons !== 'undefined' && Icons && Icons.load) {
            Icons.load(function() { _iconsReady = true; });
        }
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
            if (!data.success) {
                _leftEl.innerHTML = '<div class="task-empty-hint">获取任务数据失败</div>';
                return;
            }
            if (snapSession !== _session) return;
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
            if (!data.success) {
                _rightEl.innerHTML = '<div class="task-empty-hint">加载任务详情失败: ' + (data.error || '未知错误') + '</div>';
                return;
            }
            if (snapSession !== _session) return;
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
                '<div class="task-icon-avatar"><img src="' + avatarUrl(task.npcName) + '" onerror="this.onerror=null;this.src=\'' + defaultAvatarUrl() + '\';" alt=""></div>';

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
        html += '<div class="task-title-box">' + escHtml(task.type || '') + '<br>' + escHtml(task.title || '') + '</div>';

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
            html += '</div></div>';
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
            html += '<div class="task-npc-name">' + escHtml(task.npcName) + '</div>';
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
            ? '<img src="' + url + '" style="width:28px;height:28px;object-fit:contain;display:block;" alt="">'
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
