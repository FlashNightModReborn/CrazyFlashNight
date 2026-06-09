(function() {
    'use strict';

    // ═══════════════════════════════════════════════════════════
    // 任务面板 — 现代化升级版 (2026-06-08)
    //   · 五类筛选（主线/支线/副本/情报/其他）+ 卡片/列表双视图 + 排序 + 计数
    //   · 富物品 tooltip（hover 委托 + 缓存退避，后端 tasksTooltip 未就绪时优雅降级）
    //   · 入场/完成态动效（详见 css/task_panel.css）
    //   · detail 缓存 + 骨架屏 + 双 tab 头（事件日志占位）
    // 数据契约（AS2 TaskPanelService 透传，只读）：
    //   snapshot → { success, tasks:[{taskId,title,type,npcName,satisfied}] }
    //   detail(index) → { success, taskData:{taskId,type,title,description,
    //                     stageReq{name,difficulty}|null, itemReqs[{name,count,kind}],
    //                     npcName, rewards[{name,count}]} }
    //   tooltip(itemName) → { success, introHTML, descHTML, type, displayname }  (新增)
    //   finishTask(taskId) → { success, tasks:[...], error? }   写操作·交付（taskId 主键解析）
    //   deleteTask(taskId) → { success, tasks:[...], error? }   写操作·放弃（主线拒绝）
    //     · 写操作一律传 taskId（稳定主键），不传 index——AS2 splice 后 index 会偏移
    //     · 回包附带刷新后的 tasks 概要，前端走 applyWriteSnapshot 原子重渲
    // ═══════════════════════════════════════════════════════════

    // ── 状态 ──
    var _el;
    var _tasks = [];            // 权威 snapshot 数组（index 对齐 AS2 tasks_to_do）
    var _activeIndex = -1;      // 当前选中的「原始」index（非过滤视图位序）
    var _filterMode = 'all';    // all | 主线 | 支线 | 副本 | 情报 | 其他
    var _sortMode = 'default';  // default | deliverable | type
    var _viewMode = 'card';     // card | list
    var _tab = 'mine';          // mine | log
    var _pendingReq = {};
    var _reqSeq = 0;
    var _session = 0;
    var _busy = false;
    var _iconsReady = false;
    var _cssLink = null;
    var _resizeObserver = null;
    var _detailCache = Object.create(null);      // taskId → taskData
    var _tooltipCache = Object.create(null);     // itemName → {introHTML,descHTML,type} | {loading:true} | {failed:true,at}（null 原型，防 __proto__ 污染）
    var _hoverItemKey = null;
    var _pendingAbandonId = null;                // 放弃确认弹窗待删 taskId

    // 设计分辨率
    var DESIGN_W = 1024;
    var DESIGN_H = 576;
    var TOOLTIP_TIMEOUT_MS = 8000;
    var TOOLTIP_RETRY_MS = 8000;

    // 产品级分类归并（链名 chain[0] → 五类）。口径：用户 2026-06-08 拍板。
    var CATEGORY_MAP = {
        '主线': '主线',
        '支线': '支线', '大学': '支线', '后勤': '支线', '将军': '支线', '引导': '支线',
        '委托': '副本', '挑战': '副本', '异形': '副本',
        '情报': '情报',
        '彩蛋': '其他', '预览': '其他'
    };
    var CATEGORIES = ['all', '主线', '支线', '副本', '情报', '其他'];
    var CATEGORY_LABEL = { all: '全部', '主线': '主线', '支线': '支线', '副本': '副本', '情报': '情报', '其他': '其他' };
    var CATEGORY_ORDER = { '主线': 0, '支线': 1, '副本': 2, '情报': 3, '其他': 4 };

    // DOM refs
    var _leftEl, _rightEl, _closeBtn, _chipsEl, _countEl, _sortEl, _viewBtn, _containerEl;

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
    // DOM 创建
    // ═══════════════════════════════════════════════════════════
    function createDOM(container) {
        _el = document.createElement('div');
        _el.style.cssText = 'position:absolute;top:0;left:0;width:100%;height:100%;margin:0;padding:0;';

        _el.innerHTML = '' +
            '<div class="task-panel-scale-shell">' +
                '<div class="task-panel-container" data-tab="mine">' +
                    '<div class="task-panel-header">' +
                        '<div class="task-panel-tabs">' +
                            '<button class="task-tab active" data-tab="mine" type="button">' +
                                '<span class="task-tab-emblem"></span><span class="task-tab-label">我的任务</span>' +
                            '</button>' +
                            '<button class="task-tab" data-tab="log" type="button">' +
                                '<span class="task-tab-emblem log"></span><span class="task-tab-label">事件日志</span>' +
                            '</button>' +
                        '</div>' +
                        '<button class="task-panel-close" title="关闭" type="button"><span class="task-close-x">✕</span></button>' +
                    '</div>' +
                    '<div class="task-panel-toolbar">' +
                        '<div class="task-filter-chips" id="task-filter-chips"></div>' +
                        '<div class="task-toolbar-right">' +
                            '<span class="task-count" id="task-count"></span>' +
                            '<div class="task-dropdown" id="task-sort">' +
                                '<button class="task-dd-btn" type="button"><span class="task-dd-text">默认排序</span><span class="task-dd-caret">▾</span></button>' +
                                '<div class="task-dd-menu">' +
                                    '<button class="task-dd-opt active" data-sort="default" type="button">默认排序</button>' +
                                    '<button class="task-dd-opt" data-sort="deliverable" type="button">可交付优先</button>' +
                                    '<button class="task-dd-opt" data-sort="type" type="button">按类型</button>' +
                                '</div>' +
                            '</div>' +
                            '<button class="task-view-toggle" id="task-view-toggle" type="button" title="切换视图（卡片/列表）">▤</button>' +
                        '</div>' +
                    '</div>' +
                    '<div class="task-panel-body">' +
                        '<div class="task-panel-left view-card" id="task-panel-left"></div>' +
                        '<div class="task-panel-right" id="task-panel-right">' +
                            '<div class="task-empty-hint">请从左侧选择一个任务</div>' +
                        '</div>' +
                    '</div>' +
                    '<div class="task-panel-logview" id="task-panel-logview">' +
                        '<div class="tlv-icon"></div>' +
                        '<div class="tlv-title">事件日志 · 任务树</div>' +
                        '<div class="tlv-sub">链式任务树与剧情对话回放正在开发中，敬请期待。</div>' +
                    '</div>' +
                    '<div class="task-confirm-overlay" id="task-confirm-overlay" hidden>' +
                        '<div class="task-confirm-dialog">' +
                            '<div class="task-confirm-title">放弃任务</div>' +
                            '<div class="task-confirm-body" id="task-confirm-body"></div>' +
                            '<div class="task-confirm-footer">' +
                                '<button class="task-confirm-btn task-confirm-no" id="task-confirm-no" type="button">取消</button>' +
                                '<button class="task-confirm-btn task-confirm-yes" id="task-confirm-yes" type="button">确认放弃</button>' +
                            '</div>' +
                        '</div>' +
                    '</div>' +
                '</div>' +
            '</div>';

        _containerEl = _el.querySelector('.task-panel-container');
        _leftEl = _el.querySelector('#task-panel-left');
        _rightEl = _el.querySelector('#task-panel-right');
        _closeBtn = _el.querySelector('.task-panel-close');
        _chipsEl = _el.querySelector('#task-filter-chips');
        _countEl = _el.querySelector('#task-count');
        _sortEl = _el.querySelector('#task-sort');
        _viewBtn = _el.querySelector('#task-view-toggle');

        bindStaticEvents();
        container.appendChild(_el);
        return _el;
    }

    function bindStaticEvents() {
        _closeBtn.addEventListener('click', requestClose);

        // tab 切换
        var tabs = _el.querySelectorAll('.task-tab');
        for (var i = 0; i < tabs.length; i++) {
            tabs[i].addEventListener('click', (function(tab) {
                return function() { switchTab(tab); };
            })(tabs[i].dataset.tab));
        }

        // 排序下拉
        _sortEl.querySelector('.task-dd-btn').addEventListener('click', function(e) {
            e.stopPropagation();
            _sortEl.classList.toggle('open');
        });
        var opts = _sortEl.querySelectorAll('.task-dd-opt');
        for (var j = 0; j < opts.length; j++) {
            opts[j].addEventListener('click', (function(mode, label) {
                return function() { onSelectSort(mode, label); };
            })(opts[j].dataset.sort, opts[j].textContent));
        }
        // 注：document 级 closeSortMenu 监听随面板开关增删（见 onOpen/onClose），
        // 不在此处常驻，避免关闭后仍响应全局点击。

        // 视图切换
        _viewBtn.addEventListener('click', toggleView);

        // 物品 tooltip 委托（hover）
        _el.addEventListener('mouseover', onTipOver);
        _el.addEventListener('mousemove', onTipMove);
        _el.addEventListener('mouseout', onTipOut);

        // 键盘导航（上下键在左列表切换）
        _leftEl.addEventListener('keydown', onListKeydown);

        // 详情区操作按钮（交付/放弃）——事件委托，按钮随详情每次重渲
        _rightEl.addEventListener('click', onDetailAction);

        // 放弃确认弹窗
        var confirmOverlay = _el.querySelector('#task-confirm-overlay');
        _el.querySelector('#task-confirm-yes').addEventListener('click', function(e) { onAbandonConfirm(e.currentTarget); });
        _el.querySelector('#task-confirm-no').addEventListener('click', closeAbandonConfirm);
        confirmOverlay.addEventListener('click', function(e) { if (e.target === confirmOverlay) closeAbandonConfirm(); });
    }

    // ═══════════════════════════════════════════════════════════
    // 生命周期
    // ═══════════════════════════════════════════════════════════
    function onOpen(el, initData) {
        _session++;
        _tasks = [];
        _activeIndex = -1;
        _filterMode = 'all';
        _sortMode = 'default';
        _tab = 'mine';
        _pendingReq = {};
        _detailCache = Object.create(null);
        _tooltipCache = Object.create(null);
        _hoverItemKey = null;
        _busy = false;
        _iconsReady = false;
        closeAbandonConfirm();
        if (_containerEl) _containerEl.classList.remove('task-busy');
        if (_containerEl) _containerEl.setAttribute('data-tab', 'mine');
        setActiveTabButton('mine');
        resetToolbarControls();
        _rightEl.innerHTML = '<div class="task-empty-hint">请从左侧选择一个任务</div>';
        renderSkeletonList();

        // 注入 CSS（每次打开确保已加载；onClose 移除）
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
        document.addEventListener('click', closeSortMenu); // 仅面板打开期间生效；addEventListener 对同一引用幂等
        requestSnapshot();
    }

    function requestClose() {
        if (_busy) return;
        // 放弃确认弹窗打开时，ESC/全局遮罩关闭应先消解弹窗（modal 栈语义），不直接拆整个面板
        if (_pendingAbandonId != null) { closeAbandonConfirm(); return; }
        hideTip();
        Panels.close();
        Bridge.send({ type: 'panel', panel: 'tasks', cmd: 'close' });
    }

    function onClose() {
        _pendingReq = {};
        _busy = false;
        _session++;
        hideTip();
        closeAbandonConfirm();
        if (_containerEl) _containerEl.classList.remove('task-busy');
        unbindScaleWatcher();
        document.removeEventListener('click', closeSortMenu);
        if (_cssLink && _cssLink.parentNode) {
            _cssLink.parentNode.removeChild(_cssLink);
            _cssLink = null;
        }
    }

    function switchTab(tab) {
        if (tab === _tab) return;
        if (_busy) return; // 写操作进行中不切 tab
        _tab = tab;
        hideTip();
        closeSortMenu();
        closeAbandonConfirm();
        if (_containerEl) _containerEl.setAttribute('data-tab', tab);
        setActiveTabButton(tab);
    }
    function setActiveTabButton(tab) {
        var tabs = _el.querySelectorAll('.task-tab');
        for (var i = 0; i < tabs.length; i++) {
            tabs[i].classList.toggle('active', tabs[i].dataset.tab === tab);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 缩放（设计分辨率 1024×576 → 窗口自适应）
    // ═══════════════════════════════════════════════════════════
    function scheduleScaleUpdate() {
        if (typeof requestAnimationFrame === 'function') requestAnimationFrame(updateFitScale);
        else setTimeout(updateFitScale, 0);
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
        if (_resizeObserver) { _resizeObserver.disconnect(); _resizeObserver = null; }
    }

    // ═══════════════════════════════════════════════════════════
    // 通信
    // ═══════════════════════════════════════════════════════════
    Bridge.on('panel_resp', function(data) {
        if (!data || data.panel !== 'tasks') return;
        var handler = _pendingReq[data.callId];
        if (handler) {
            delete _pendingReq[data.callId];
            if (typeof handler === 'function') handler(data);
        }
    });

    function sendPanelMsg(cmd, extra, cb) {
        var callId = 'task_' + (++_reqSeq) + '_' + Date.now();
        if (cb) _pendingReq[callId] = cb;
        var msg = { type: 'panel', panel: 'tasks', cmd: cmd, callId: callId };
        if (extra) { for (var k in extra) if (extra.hasOwnProperty(k)) msg[k] = extra[k]; }
        Bridge.send(msg);
        return callId;
    }

    // ── Snapshot ──
    function requestSnapshot() {
        var snapSession = _session;
        sendPanelMsg('snapshot', null, function(data) {
            if (snapSession !== _session) return;
            if (!data.success) {
                _leftEl.innerHTML = '<div class="task-empty-hint">获取任务数据失败</div>';
                toast('获取任务数据失败');
                return;
            }
            _tasks = data.tasks || [];
            renderChips();
            renderCount();
            renderTaskList();
            var first = firstVisibleOriginalIndex();
            if (first >= 0) requestDetail(first);
            else _rightEl.innerHTML = '<div class="task-empty-hint">请从左侧选择一个任务</div>';
        });
    }

    // ── Detail（带 taskId 缓存）──
    function requestDetail(index) {
        var task = _tasks[index];
        if (!task) return;
        _activeIndex = index;
        highlightActiveIcon();

        var cached = _detailCache[task.taskId];
        if (cached) { renderTaskDetail(cached, task); return; }

        renderSkeletonDetail();
        var snapSession = _session;
        sendPanelMsg('detail', { index: index }, function(data) {
            if (snapSession !== _session) return;
            if (_activeIndex !== index) return; // 已切走
            if (!data.success) {
                _rightEl.innerHTML = '<div class="task-empty-hint">加载任务详情失败: ' + escHtml(data.error || '未知错误') + '</div>';
                toast('加载任务详情失败');
                return;
            }
            if (data.taskData) _detailCache[task.taskId] = data.taskData;
            renderTaskDetail(data.taskData, task);
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 写操作：交付 / 放弃
    //   · 一律按 taskId 发请求（AS2 splice 后 index 偏移，taskId 才是稳定主键）
    //   · 回包含刷新后的 tasks，走 applyWriteSnapshot 原子重渲（按 taskId 尽量保留选中）
    // ═══════════════════════════════════════════════════════════
    function onDetailAction(e) {
        var t = e.target;
        while (t && t !== _rightEl && !(t.classList && t.classList.contains('task-act-btn'))) t = t.parentNode;
        if (!t || t === _rightEl || !t.classList || !t.classList.contains('task-act-btn')) return;
        if (t.disabled || t.classList.contains('task-btn-pending')) return;
        if (t.classList.contains('task-act-deliver')) onDeliver(t);
        else if (t.classList.contains('task-act-abandon')) openAbandonConfirm();
    }

    function onDeliver(btn) {
        if (_busy || _activeIndex < 0) return;
        var task = _tasks[_activeIndex];
        if (!task || !task.satisfied) return;     // 客户端预门控；AS2 端 taskCompleteCheck 二次硬门控
        var taskId = task.taskId;
        beginOp(btn);
        var reqSession = _session;
        sendPanelMsg('finishTask', { taskId: taskId }, function(data) {
            endOp(btn);
            if (reqSession !== _session) return;
            if (data && data.success) {
                toast('任务已交付');
                applyWriteSnapshot(data);
            } else {
                toast(writeErrorMsg('交付失败', data));
                // 失败也消费刷新后的 tasks：任务未 splice 时 applyWriteSnapshot 按 taskId 原位保留选中，
                // 顺带把过期的 satisfied/可交付徽章/计数纠正回服务端真值（如交物型任务物品已被消耗）
                if (data && data.tasks) applyWriteSnapshot(data);
            }
        });
    }

    function openAbandonConfirm() {
        if (_busy || _activeIndex < 0) return;
        var task = _tasks[_activeIndex];
        if (!task) return;
        if (task.type === '主线') { toast('主线任务无法放弃'); return; }
        _pendingAbandonId = task.taskId;
        var body = _el.querySelector('#task-confirm-body');
        if (body) body.innerHTML = '确认放弃 <strong>' + escHtml(task.title || '') + '</strong> 吗？该任务将从列表移除，已收集/通关进度会清空，需重新接取。';
        var overlay = _el.querySelector('#task-confirm-overlay');
        if (overlay) overlay.hidden = false;
    }

    function closeAbandonConfirm() {
        _pendingAbandonId = null;
        var overlay = _el && _el.querySelector('#task-confirm-overlay');
        if (overlay) overlay.hidden = true;
    }

    function onAbandonConfirm(btn) {
        if (_busy || _pendingAbandonId == null) { closeAbandonConfirm(); return; }
        var taskId = _pendingAbandonId;
        beginOp(btn);
        var reqSession = _session;
        sendPanelMsg('deleteTask', { taskId: taskId }, function(data) {
            endOp(btn);
            closeAbandonConfirm();
            if (reqSession !== _session) return;
            if (data && data.success) {
                toast('已放弃任务');
                applyWriteSnapshot(data);
            } else {
                toast(writeErrorMsg('放弃失败', data));
                if (data && data.tasks) applyWriteSnapshot(data); // 放弃失败多为状态漂移，重同步保险
            }
        });
    }

    function writeErrorMsg(prefix, data) {
        if (!data) return prefix;
        switch (data.error) {
            case 'not_satisfied':     return '尚未满足交付条件';
            case 'inventory_full':    return '背包已满，无法交付，请清理背包后重试';
            case 'cannot_delete_main':return '主线任务无法放弃';
            case 'task_not_found':    return '任务已不存在，已刷新列表';
            case 'disconnected':      return '游戏连接已断开';
            case 'timeout':           return prefix + '：操作超时';
            default:                  return data.error ? (prefix + '：' + data.error) : prefix;
        }
    }

    // 写操作回包后用刷新 tasks 原子重渲；按 taskId 尽量保留原选中，不存在则选首个可见
    function applyWriteSnapshot(data) {
        if (!data || !data.tasks) return;
        var prevId = (_activeIndex >= 0 && _tasks[_activeIndex]) ? _tasks[_activeIndex].taskId : null;
        _tasks = data.tasks;
        renderChips();
        renderCount();
        renderTaskList();
        var newIdx = -1;
        if (prevId != null) {
            for (var i = 0; i < _tasks.length; i++) {
                if (String(_tasks[i].taskId) === String(prevId)) { newIdx = i; break; }
            }
        }
        _activeIndex = -1;
        if (newIdx >= 0) {
            requestDetail(newIdx);
        } else {
            var first = firstVisibleOriginalIndex();
            if (first >= 0) requestDetail(first);
            else _rightEl.innerHTML = '<div class="task-empty-hint">' + (_tasks.length ? '请从左侧选择一个任务' : '暂无任务') + '</div>';
        }
    }

    // 操作锁 + 按钮 pending（_busy 拦截 requestClose / switchTab / 并发写）
    function beginOp(btn) {
        _busy = true;
        if (_containerEl) _containerEl.classList.add('task-busy');
        if (btn) btn.classList.add('task-btn-pending');
    }
    function endOp(btn) {
        _busy = false;
        if (_containerEl) _containerEl.classList.remove('task-busy');
        if (btn) btn.classList.remove('task-btn-pending');
    }

    // ═══════════════════════════════════════════════════════════
    // 过滤 + 排序
    // ═══════════════════════════════════════════════════════════
    function categoryOf(task) {
        return CATEGORY_MAP[task && task.type] || '其他';
    }

    // 返回 [{task, idx}]（idx = _tasks 原始下标）
    function visibleTasks() {
        var view = [];
        for (var i = 0; i < _tasks.length; i++) {
            var t = _tasks[i];
            if (_filterMode !== 'all' && categoryOf(t) !== _filterMode) continue;
            view.push({ task: t, idx: i });
        }
        if (_sortMode === 'deliverable') {
            view.sort(function(a, b) {
                var sa = a.task.satisfied ? 0 : 1, sb = b.task.satisfied ? 0 : 1;
                if (sa !== sb) return sa - sb;
                return a.idx - b.idx;
            });
        } else if (_sortMode === 'type') {
            view.sort(function(a, b) {
                var ca = CATEGORY_ORDER[categoryOf(a.task)], cb = CATEGORY_ORDER[categoryOf(b.task)];
                if (ca !== cb) return ca - cb;
                return a.idx - b.idx;
            });
        }
        return view;
    }

    function firstVisibleOriginalIndex() {
        var v = visibleTasks();
        return v.length ? v[0].idx : -1;
    }

    function categoryCounts() {
        var counts = { all: _tasks.length, '主线': 0, '支线': 0, '副本': 0, '情报': 0, '其他': 0 };
        for (var i = 0; i < _tasks.length; i++) counts[categoryOf(_tasks[i])]++;
        return counts;
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：筛选 chips / 计数 / 排序 / 视图
    // ═══════════════════════════════════════════════════════════
    function renderChips() {
        var counts = categoryCounts();
        var html = '';
        for (var i = 0; i < CATEGORIES.length; i++) {
            var key = CATEGORIES[i];
            var n = counts[key];
            // 空分类（all 除外）不展示，减少噪声
            if (key !== 'all' && n === 0) continue;
            var active = key === _filterMode ? ' active' : '';
            html += '<button class="task-chip' + active + '" data-cat="' + key + '" type="button" style="animation-delay:' + (i * 0.04).toFixed(2) + 's">' +
                escHtml(CATEGORY_LABEL[key]) +
                '<span class="task-chip-count">' + n + '</span></button>';
        }
        _chipsEl.innerHTML = html;
        var chips = _chipsEl.querySelectorAll('.task-chip');
        for (var c = 0; c < chips.length; c++) {
            chips[c].addEventListener('click', (function(cat) {
                return function() { onSelectFilter(cat); };
            })(chips[c].dataset.cat));
        }
    }

    function onSelectFilter(cat) {
        if (cat === _filterMode) return;
        _filterMode = cat;
        var chips = _chipsEl.querySelectorAll('.task-chip');
        for (var i = 0; i < chips.length; i++) chips[i].classList.toggle('active', chips[i].dataset.cat === cat);
        renderTaskList();
        // 当前选中任务若被过滤掉，自动切到首个可见任务；无可见任务则清空右侧详情避免残留
        if (_activeIndex < 0 || categoryNotVisible(_activeIndex)) {
            var first = firstVisibleOriginalIndex();
            if (first >= 0) {
                requestDetail(first);
            } else {
                _activeIndex = -1;
                _rightEl.innerHTML = '<div class="task-empty-hint">该分类暂无任务</div>';
            }
        }
    }
    function categoryNotVisible(idx) {
        var t = _tasks[idx];
        if (!t) return true;
        return _filterMode !== 'all' && categoryOf(t) !== _filterMode;
    }

    function onSelectSort(mode, label) {
        _sortMode = mode;
        var opts = _sortEl.querySelectorAll('.task-dd-opt');
        for (var i = 0; i < opts.length; i++) opts[i].classList.toggle('active', opts[i].dataset.sort === mode);
        _sortEl.querySelector('.task-dd-text').textContent = label;
        closeSortMenu();
        renderTaskList();
    }
    function closeSortMenu() { if (_sortEl) _sortEl.classList.remove('open'); }

    // 重开面板时把工具栏 DOM 同步到 onOpen 里被重置的 _sortMode='default'，
    // 否则下拉文字/选中项会停留在上一次（如「可交付优先」）与实际状态不符。
    function resetToolbarControls() {
        if (!_sortEl) return;
        var ddText = _sortEl.querySelector('.task-dd-text');
        if (ddText) ddText.textContent = '默认排序';
        var opts = _sortEl.querySelectorAll('.task-dd-opt');
        for (var i = 0; i < opts.length; i++) opts[i].classList.toggle('active', opts[i].dataset.sort === 'default');
        _sortEl.classList.remove('open');
    }

    function toggleView() {
        _viewMode = _viewMode === 'card' ? 'list' : 'card';
        _leftEl.classList.toggle('view-card', _viewMode === 'card');
        _leftEl.classList.toggle('view-list', _viewMode === 'list');
        _viewBtn.textContent = _viewMode === 'card' ? '▤' : '▦';
        _viewBtn.title = _viewMode === 'card' ? '切换到列表视图' : '切换到卡片视图';
        renderTaskList();
    }

    function renderCount() {
        var total = _tasks.length;
        var deliverable = 0;
        for (var i = 0; i < _tasks.length; i++) if (_tasks[i].satisfied) deliverable++;
        _countEl.innerHTML = '共 <b>' + total + '</b> 个 · 可交付 <b>' + deliverable + '</b> 个';
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：左侧任务列表（过滤 + 排序 + 卡片/列表视图）
    // ═══════════════════════════════════════════════════════════
    function renderTaskList() {
        var view = visibleTasks();
        _leftEl.innerHTML = '';
        if (view.length === 0) {
            _leftEl.innerHTML = '<div class="task-empty-hint">' +
                (_tasks.length === 0 ? '暂无任务' : '该分类暂无任务') + '</div>';
            return;
        }
        for (var i = 0; i < view.length; i++) {
            var task = view[i].task;
            var idx = view[i].idx;
            var cat = categoryOf(task);
            var btn = document.createElement('button');
            btn.className = 'task-icon';
            btn.type = 'button';
            btn.dataset.index = idx;
            btn.dataset.satisfied = task.satisfied ? '1' : '0';
            btn.style.animationDelay = Math.min(i * 0.06, 0.42).toFixed(2) + 's';
            btn.innerHTML = '' +
                '<span class="task-icon-cat" data-cat="' + escAttr(cat) + '">' + escHtml(cat) + '</span>' +
                '<div class="task-icon-left">' +
                    '<div class="task-icon-type">' + escHtml(task.type || '') + '</div>' +
                    '<div class="task-icon-name">' + escHtml(task.title || '') + '</div>' +
                '</div>' +
                '<div class="task-icon-avatar"><img src="' + avatarUrl(task.npcName) + '" onerror="this.onerror=null;this.src=\'' + defaultAvatarUrl() + '\';" alt=""></div>' +
                '<span class="task-icon-flag" aria-hidden="true"></span>' +
                (task.satisfied ? '<img class="task-finished-overlay" src="/modules/tasks/assets/task_finished_icon.png" alt="已完成">' : '');
            btn.addEventListener('click', (function(originalIdx) {
                return function() { requestDetail(originalIdx); };
            })(idx));
            _leftEl.appendChild(btn);
        }
        highlightActiveIcon();
    }

    function highlightActiveIcon() {
        var buttons = _leftEl.querySelectorAll('.task-icon');
        for (var i = 0; i < buttons.length; i++) {
            var idx = parseInt(buttons[i].dataset.index, 10);
            buttons[i].classList.toggle('active', idx === _activeIndex);
        }
    }

    function onListKeydown(e) {
        if (_busy) return; // 写操作在途锁交互（pointer-events 不拦键盘，需显式守卫，与 switchTab 同口径）
        if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
        var buttons = _leftEl.querySelectorAll('.task-icon');
        if (!buttons.length) return;
        var cur = -1;
        for (var i = 0; i < buttons.length; i++) {
            if (parseInt(buttons[i].dataset.index, 10) === _activeIndex) { cur = i; break; }
        }
        var next = e.key === 'ArrowDown' ? cur + 1 : cur - 1;
        if (next < 0) next = 0;
        if (next >= buttons.length) next = buttons.length - 1;
        e.preventDefault();
        buttons[next].focus();
        requestDetail(parseInt(buttons[next].dataset.index, 10));
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：右侧任务详情
    // ═══════════════════════════════════════════════════════════
    function renderTaskDetail(task, summary) {
        if (!task) {
            _rightEl.innerHTML = '<div class="task-empty-hint">无任务数据</div>';
            return;
        }
        var satisfied = summary && summary.satisfied;
        var html = '';

        // 标题 + 可交付徽章
        html += '<div class="task-detail-head">';
        html += '<div class="task-title-box">' +
            '<span class="task-title-line1">任务详情</span>' +
            '<span class="task-title-line2">' + escHtml(task.title || '') + '</span>' +
        '</div>';
        if (satisfied) {
            html += '<div class="task-deliverable" title="该任务已满足交付条件">' +
                '<div class="task-stamp">' +
                    '<span class="task-stamp-ring"></span>' +
                    '<svg class="task-stamp-check" viewBox="0 0 24 24"><path d="M5 13 L10 18 L19 6"/></svg>' +
                '</div>' +
                '<span class="task-deliverable-label">可交付</span>' +
            '</div>';
        }
        html += '</div>';

        // 描述（角标伸缩）
        html += '<div class="task-desc-box">';
        html += escHtml(task.description || '');
        html += '<span class="corner-horizontal top-left"></span><span class="corner-horizontal top-right"></span>';
        html += '<span class="corner-horizontal bottom-left"></span><span class="corner-horizontal bottom-right"></span>';
        html += '<span class="corner-vertical top-left"></span><span class="corner-vertical top-right"></span>';
        html += '<span class="corner-vertical bottom-left"></span><span class="corner-vertical bottom-right"></span>';
        html += '</div>';

        // 需求区
        html += '<div class="task-requirement-area">';
        var reqI = 0;

        if (task.stageReq) {
            html += '<div class="task-requirement" data-i="' + reqI + '">';
            html += '<div class="task-requirement-inner">';
            html += '<div class="scroll-track"></div>';
            html += '<div class="task-requirement-title stage"></div>';
            html += '<div class="task-requirement-stage-name">' + escHtml(task.stageReq.name || '') + '</div>';
            html += '</div>';
            if (task.stageReq.difficulty) {
                html += '<span class="task-difficulty-label difficulty-' + escAttr(task.stageReq.difficulty) + '">' + escHtml(task.stageReq.difficulty) + '</span>';
            }
            html += '</div>';
            reqI++;
        }

        if (task.itemReqs && task.itemReqs.length > 0) {
            var kind = task.itemReqs[0].kind || 'submit';
            var titleClass = kind === 'contain' ? 'contain' : 'submit';
            html += '<div class="task-item-requirement" data-i="' + reqI + '">';
            html += '<div class="task-item-requirement-inner">';
            html += '<div class="scroll-track"></div>';
            html += '<div class="task-requirement-title ' + titleClass + '"></div>';
            html += '<div class="task-requirement-items">';
            for (var ir = 0; ir < task.itemReqs.length; ir++) {
                html += itemIconHtml(task.itemReqs[ir].name, task.itemReqs[ir].count, ir);
            }
            html += '</div></div></div>';
            reqI++;
        }

        if (task.npcName) {
            html += '<div class="task-npc" data-i="' + reqI + '">';
            html += '<div class="task-npc-left">';
            html += '<div class="scroll-track"></div>';
            html += '<div class="task-npc-title"></div>';
            html += '<div class="task-npc-name"><span>' + escHtml(task.npcName) + '</span></div>';
            html += '</div>';
            html += '<div class="task-npc-avatar"><img src="' + avatarUrl(task.npcName) + '" onerror="this.onerror=null;this.src=\'' + defaultAvatarUrl() + '\';" alt=""></div>';
            html += '</div>';
            reqI++;
        }

        html += '</div>'; // .task-requirement-area

        // 奖励
        if (task.rewards && task.rewards.length > 0) {
            html += '<div class="task-reward-section">';
            html += '<div class="task-reward-box"><span>任务奖励</span></div>';
            html += '<div class="task-reward-items">';
            for (var r = 0; r < task.rewards.length; r++) {
                html += itemIconHtml(task.rewards[r].name, task.rewards[r].count, r);
            }
            html += '</div></div>';
        }

        // 操作区（交付 / 放弃）。配色纪律：功能按钮黑白灰，主次靠「填充 vs 描边」分层，不用橙。
        // 主线任务不可放弃（AS2 DeleteTask 亦拒绝，此处仅前置禁用作即时反馈）。
        var isMain = (summary && summary.type === '主线') || task.type === '主线';
        html += '<div class="task-detail-actions">';
        html += '<button class="task-act-btn task-act-deliver" type="button"' +
            (satisfied ? '' : ' disabled') + '>' +
            (satisfied ? '交付任务' : '尚未满足交付条件') + '</button>';
        html += '<button class="task-act-btn task-act-abandon" type="button"' +
            (isMain ? ' disabled title="主线任务无法放弃"' : '') + '>放弃任务</button>';
        html += '</div>';

        _rightEl.innerHTML = html;
    }

    // ── 骨架屏 ──
    function renderSkeletonList() {
        var html = '';
        for (var i = 0; i < 4; i++) html += '<div class="task-skel task-skel-card"></div>';
        _leftEl.className = 'task-panel-left ' + (_viewMode === 'card' ? 'view-card' : 'view-list');
        _leftEl.innerHTML = html;
    }
    function renderSkeletonDetail() {
        _rightEl.innerHTML = '' +
            '<div class="task-skel task-skel-line w40" style="margin-top:18px"></div>' +
            '<div class="task-skel task-skel-line w70"></div>' +
            '<div class="task-skel task-skel-block"></div>' +
            '<div class="task-skel task-skel-line w40"></div>';
    }

    // ═══════════════════════════════════════════════════════════
    // 物品 tooltip（hover 委托 + 缓存退避，后端 tasksTooltip 未就绪时优雅降级）
    // ═══════════════════════════════════════════════════════════
    function onTipOver(e) {
        var cell = closestItem(e.target);
        if (!cell) return;
        var name = cell.getAttribute('data-item-name');
        if (!name) return;
        _hoverItemKey = name;
        if (typeof PanelTooltip === 'undefined' || !PanelTooltip) return;

        var cached = _tooltipCache[name];
        if (cached && cached.introHTML !== undefined) {
            PanelTooltip.showAtMouse(buildRichTip(name, cached), e);
            return;
        }
        // 先显示基础信息
        PanelTooltip.showAtMouse(buildBasicTip(name), e);
        if (cached && cached.loading) return;
        if (cached && cached.failed && (Date.now() - cached.at) < TOOLTIP_RETRY_MS) {
            PanelTooltip.showAtMouse(buildUnavailableTip(name), e);
            return;
        }
        requestTooltip(name);
    }
    function onTipMove(e) {
        if (!_hoverItemKey || typeof PanelTooltip === 'undefined') return;
        if (!closestItem(e.target)) return;
        PanelTooltip.followMouse(e);
    }
    function onTipOut(e) {
        var cell = closestItem(e.target);
        if (!cell) return;
        // 移到子元素内不算离开
        if (e.relatedTarget && cell.contains(e.relatedTarget)) return;
        _hoverItemKey = null;
        hideTip();
    }
    function closestItem(node) {
        while (node && node !== _el) {
            if (node.classList && node.classList.contains('task-item') && node.getAttribute('data-item-name')) return node;
            node = node.parentNode;
        }
        return null;
    }
    function hideTip() {
        if (typeof PanelTooltip !== 'undefined' && PanelTooltip && PanelTooltip.hide) PanelTooltip.hide();
    }

    function requestTooltip(name) {
        _tooltipCache[name] = { loading: true };
        var reqSession = _session;
        var callId = sendPanelMsg('tooltip', { itemName: name }, function(data) {
            if (reqSession !== _session) return;
            clearTimeout(timer);
            if (data && data.success && (data.introHTML !== undefined || data.descHTML !== undefined)) {
                // 注：物品类型用 itemType（不能用 type——会与 panel_resp 信封的 type 字段冲突）
                _tooltipCache[name] = { introHTML: data.introHTML || '', descHTML: data.descHTML || '', type: data.itemType || '' };
                if (_hoverItemKey === name && PanelTooltip.isVisible()) PanelTooltip.updateContent(buildRichTip(name, _tooltipCache[name]));
            } else {
                _tooltipCache[name] = { failed: true, at: Date.now() };
                if (_hoverItemKey === name && PanelTooltip.isVisible()) PanelTooltip.updateContent(buildUnavailableTip(name));
            }
        });
        // 兜底超时（后端 tooltip cmd 未接线时 callId 不会回，避免永久 loading）
        var timer = setTimeout(function() {
            if (_pendingReq[callId]) {
                delete _pendingReq[callId];
                _tooltipCache[name] = { failed: true, at: Date.now() };
                if (reqSession === _session && _hoverItemKey === name && PanelTooltip.isVisible()) {
                    PanelTooltip.updateContent(buildUnavailableTip(name));
                }
            }
        }, TOOLTIP_TIMEOUT_MS);
    }

    function buildBasicTip(name) {
        return PanelTooltip.buildItemRichHtml({
            iconUrl: resolveIconUrl(name),
            iconPlaceholder: '<span style="opacity:.5">?</span>',
            introHTML: '<b>' + plainText(name) + '</b><br><font size=\'12\' color=\'#999999\'>载入注释…</font>',
            descHTML: '',
            layoutType: 'narrow',
            rootClass: 'task-tt-rich'
        });
    }
    function buildRichTip(name, resp) {
        return PanelTooltip.buildItemRichHtml({
            iconUrl: resolveIconUrl(name),
            iconPlaceholder: '<span style="opacity:.5">?</span>',
            introHTML: resp.introHTML || ('<b>' + plainText(name) + '</b>'),
            descHTML: resp.descHTML || '',
            layoutType: PanelTooltip.inferLayoutType(resp.type),
            rootClass: 'task-tt-rich'
        });
    }
    function buildUnavailableTip(name) {
        return PanelTooltip.buildItemRichHtml({
            iconUrl: resolveIconUrl(name),
            iconPlaceholder: '<span style="opacity:.5">?</span>',
            introHTML: '<b>' + plainText(name) + '</b><br><font size=\'12\' color=\'#bb7766\'>注释暂不可用</font>',
            descHTML: '',
            layoutType: 'narrow',
            rootClass: 'task-tt-rich'
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 工具函数
    // ═══════════════════════════════════════════════════════════
    function escHtml(s) {
        if (s === null || s === undefined) return '';
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
    function escAttr(s) { return escHtml(s); }
    function plainText(s) {
        // 用于嵌进 AS2 font 标签的安全文本（剥 < > & 标签字符）
        if (s === null || s === undefined) return '';
        return String(s).replace(/[<>]/g, '');
    }

    function resolveIconUrl(itemName) {
        if (!itemName) return null;
        if (typeof Icons !== 'undefined' && Icons && Icons.resolve) return Icons.resolve(itemName);
        return null;
    }

    function itemIconHtml(itemName, count, i) {
        var url = resolveIconUrl(itemName);
        var imgHtml = url ? '<img src="' + escAttr(url) + '" alt="">' : '';
        var delayAttr = (i !== undefined) ? ' data-i="' + i + '"' : '';
        var nameAttr = itemName ? ' data-item-name="' + escAttr(itemName) + '"' : '';
        return '<div class="task-item"' + delayAttr + nameAttr + '>' + imgHtml +
            '<span class="task-item-count">' + escHtml(String(count)) + '</span></div>';
    }

    function toast(msg) {
        try { if (typeof Toast !== 'undefined' && Toast && Toast.add) Toast.add(escHtml(msg)); } catch (e) {}
    }

    var ASSETS_BASE = 'https://cfn-assets.local/portraits/profiles/';
    var DEFAULT_AVATAR = ASSETS_BASE + encodeURIComponent('无头像') + '.png';
    function avatarUrl(npcName) { return ASSETS_BASE + encodeURIComponent(npcName || '') + '.png'; }
    function defaultAvatarUrl() { return DEFAULT_AVATAR; }

    // ── 测试钩子（harness ?qa= 用，生产无副作用）──
    if (typeof window !== 'undefined') {
        window.TaskPanel = {
            getState: function() {
                return {
                    tab: _tab, filterMode: _filterMode, sortMode: _sortMode, viewMode: _viewMode,
                    activeIndex: _activeIndex, taskCount: _tasks.length,
                    visibleCount: visibleTasks().length,
                    categoryCounts: categoryCounts()
                };
            },
            // 暴露纯函数供单元断言
            _categoryOf: categoryOf,
            _categoryMap: CATEGORY_MAP,
            // 写操作 QA 钩子（harness 也可直接点真实 DOM 按钮；这些便于断言/编排）
            _isBusy: function() { return _busy; },
            _abandonPendingId: function() { return _pendingAbandonId; }
        };
    }
})();
