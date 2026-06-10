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
    //   detail 额外回 finishRemote:Boolean（可否面板远程交付）、finishNavigable:Boolean（可否一键前往NPC）
    //   finishTask(taskId) → { success, tasks:[...], error? }   写操作·交付（taskId 主键解析）
    //   deleteTask(taskId) → { success, tasks:[...], error? }   写操作·放弃（主线拒绝）
    //   navigateFinish(taskId) → { success, closePanel, error? } 前往交付（复用地图跳转，成功后关面板）
    //     · 写操作一律传 taskId（稳定主键），不传 index——AS2 splice 后 index 会偏移
    //     · 回包附带刷新后的 tasks 概要，前端走 applyWriteSnapshot 原子重渲
    //     · 远程交付门控：仅 finishRemote 任务可面板直接交付；否则按钮显示「前往NPC交付」，
    //       AS2 对非远程任务回 requires_npc（服务端硬门控）
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

    // ── 事件日志/任务树（WS6）──
    //   静态目录 = build 派生 task-catalog.json（web 直读，零 AS2 传输）；
    //   动态进度 = taskTreeState 小叠加；对话回放 = replayDialogue 命令回传 AS2 SetDialogue。
    var _catalog = null;            // task-catalog.json（不可变，模块级缓存，只 fetch 一次）
    var _catalogState = 'idle';     // idle | loading | ready | error
    var _catalogWaiters = [];       // 加载中等待回调
    var _treeState = null;          // { chainsProgress, finished:{id:1}, active:{id:1} }
    var _logSelectedId = null;      // log tab 当前选中任务 id（String）
    // 图表视图（BALDR SKY 风任务树）
    var _logView = 'list';          // list | chart（事件日志内的子视图）
    var _chartZoom = 1;             // 1 | 0.5 | 0.25
    var _chartMode = 'detail';      // detail | chapter
    var _chartLayout = null;        // 计算后的布局缓存
    var _chartDrag = null;          // 左键拖拽平移：{x,y,sl,st}（按下时快照）
    var _chartDragMoved = false;    // 本次按下是否已成拖拽（用于抑制拖拽末尾的误点选）

    // 设计分辨率
    var DESIGN_W = 1024;
    var DESIGN_H = 576;
    var TOOLTIP_TIMEOUT_MS = 8000;
    var TOOLTIP_RETRY_MS = 8000;

    // 产品级分类归并（链名 chain[0] → 五类）。口径：用户 2026-06-08 拍板。
    var CATEGORY_MAP = {
        '主线': '主线',
        '支线': '支线', '大学': '支线', '后勤': '支线', '将军': '支线', '引导': '支线', '废城': '支线',
        '委托': '副本', '挑战': '副本', '异形': '副本',
        '情报': '情报',
        '彩蛋': '其他', '预览': '其他'
    };
    var CATEGORIES = ['all', '主线', '支线', '副本', '情报', '其他'];
    var CATEGORY_LABEL = { all: '全部', '主线': '主线', '支线': '支线', '副本': '副本', '情报': '情报', '其他': '其他' };
    var CATEGORY_ORDER = { '主线': 0, '支线': 1, '副本': 2, '情报': 3, '其他': 4 };

    // DOM refs
    var _leftEl, _rightEl, _closeBtn, _chipsEl, _countEl, _sortEl, _viewBtn, _containerEl;
    var _treeEl, _logDetailEl;   // 事件日志/任务树（WS6）DOM refs
    var _logviewEl, _chartViewportEl, _chartCanvasEl, _chartCtrlsEl;   // 图表视图 DOM refs
    var _achViewEl;              // 成就 tab 容器（实现在 achievement-tab.js，lazy deps 先加载）

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
                            '<button class="task-tab" data-tab="ach" type="button">' +
                                '<span class="task-tab-emblem ach"></span><span class="task-tab-label">成就</span>' +
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
                    '<div class="task-panel-logview" id="task-panel-logview" data-logview="list">' +
                        '<div class="tlv-left">' +
                            '<div class="tlv-logbar">' +
                                '<div class="tlv-seg">' +
                                    '<button class="tlv-seg-btn active" data-logview="list" type="button">列表</button>' +
                                    '<button class="tlv-seg-btn" data-logview="chart" type="button">图表</button>' +
                                '</div>' +
                                '<div class="tlv-chart-ctrls" id="tlv-chart-ctrls" hidden>' +
                                    '<div class="tlv-seg">' +
                                        '<button class="tlv-seg-btn active" data-chartmode="detail" type="button">详细</button>' +
                                        '<button class="tlv-seg-btn" data-chartmode="chapter" type="button">章节</button>' +
                                    '</div>' +
                                    '<div class="tlv-seg">' +
                                        '<button class="tlv-seg-btn active" data-zoom="1" type="button">100%</button>' +
                                        '<button class="tlv-seg-btn" data-zoom="0.5" type="button">50%</button>' +
                                        '<button class="tlv-seg-btn" data-zoom="0.25" type="button">25%</button>' +
                                    '</div>' +
                                '</div>' +
                            '</div>' +
                            '<div class="tlv-tree" id="tlv-tree" tabindex="0"></div>' +
                            '<div class="tlv-chart-viewport" id="tlv-chart-viewport" hidden>' +
                                '<div class="tlv-chart-canvas" id="tlv-chart-canvas"></div>' +
                            '</div>' +
                        '</div>' +
                        '<div class="tlv-detail" id="tlv-detail"></div>' +
                    '</div>' +
                    '<div class="task-panel-achview" id="task-panel-achview"></div>' +
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
        _treeEl = _el.querySelector('#tlv-tree');
        _logDetailEl = _el.querySelector('#tlv-detail');
        _logviewEl = _el.querySelector('#task-panel-logview');
        _chartViewportEl = _el.querySelector('#tlv-chart-viewport');
        _chartCanvasEl = _el.querySelector('#tlv-chart-canvas');
        _chartCtrlsEl = _el.querySelector('#tlv-chart-ctrls');
        _achViewEl = _el.querySelector('#task-panel-achview');

        // 成就 tab 装配（achievement-tab.js 经 lazy deps 先加载；缺失时优雅降级为空 tab）。
        // claim 在途复用本面板 beginOp/endOp 的 _busy 锁——切 tab/关面板/二次点击三处口径统一。
        if (typeof TaskAchievementTab !== 'undefined') {
            TaskAchievementTab.install({
                paneEl: _achViewEl,
                send: sendPanelMsg,
                toast: toast,
                escHtml: escHtml,
                escAttr: escAttr,
                itemIconHtml: itemIconHtml,
                beginOp: beginOp,
                endOp: endOp,
                isBusy: function() { return _busy; },
                session: function() { return _session; }
            });
        }

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

        // 事件日志/任务树（WS6）：节点点击 + 详情区重播按钮（事件委托）
        _treeEl.addEventListener('click', onTreeClick);
        _logDetailEl.addEventListener('click', onLogDetailClick);

        // 图表视图：工具栏（列表/图表切换、章节/详细、缩放）+ 六边形节点点击（事件委托）
        _el.querySelector('.tlv-logbar').addEventListener('click', onLogbarClick);
        _chartCanvasEl.addEventListener('click', onChartClick);
        // 左键拖拽平移（取代滚动条）：在视口上按下，move/up 走 document（处理拖出视口）
        _chartViewportEl.addEventListener('mousedown', onChartMouseDown);
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
        _treeState = null;          // 进度叠加每次开面板重取（存档态可变）；_catalog 不重置（不可变）
        if (typeof TaskAchievementTab !== 'undefined') TaskAchievementTab.reset(); // 成就动态状态同口径重置（catalog 缓存保留）
        _logSelectedId = null;
        _logView = 'list';
        _chartZoom = 1;
        _chartMode = 'detail';
        _chartLayout = null;
        _chartDrag = null; _chartDragMoved = false;
        if (_chartCanvasEl) _chartCanvasEl.style.zoom = 1;   // 清洁重置：防上次 25% 残留到下次开面板
        if (_logviewEl) _logviewEl.setAttribute('data-logview', 'list');
        if (_chartCtrlsEl) _chartCtrlsEl.hidden = true;
        if (_treeEl) _treeEl.hidden = false;
        if (_chartViewportEl) _chartViewportEl.hidden = true;
        resetChartToolbarButtons();   // 重置 列表/详细/100% 分段高亮（DOM 复用→防上次 .active 残留，修「按钮停在图表」）
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
        endChartDrag();   // 清掉拖拽平移可能残留的 document 监听
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
        if (tab === 'log') enterLogTab();
        if (tab === 'ach' && typeof TaskAchievementTab !== 'undefined') TaskAchievementTab.enter();
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
        if (cached) { renderTaskDetail(cached, task); maybeRefreshNavigable(index, task, cached); return; }

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

    // 交付/前往按钮三态（满足+远程→交付任务｜满足+可前往→前往交付｜满足+不可前往→前往NPC禁用｜未满足→禁用）。
    // 抽出供 renderTaskDetail 渲染与 patchDeliverButton 就地修补共用（DRY）。
    // label/titleText 返回原始文本（含未转义 npcName）：渲染处用 escHtml/escAttr，patch 处用 textContent/.title，均安全。
    function computeDeliverState(detail, summary) {
        var satisfied = !!(summary && summary.satisfied);
        var npc = (detail && detail.npcName) || 'NPC';
        if (!satisfied) return { enabled: false, label: '尚未满足交付条件', act: '', titleText: '' };
        if (detail.finishRemote === true) return { enabled: true, label: '交付任务', act: 'deliver', titleText: '' };
        if (detail.finishNavigable === true) return { enabled: true, label: '前往交付', act: 'navigate', titleText: '前往「' + npc + '」所在地图交付' };
        return { enabled: false, label: '前往「' + npc + '」交付', act: '', titleText: '需前往交付NPC处提交（该区域暂不可一键前往）' };
    }

    // 就地修补交付按钮（不重渲详情，避免入场动效重放）
    function patchDeliverButton(detail, summary) {
        if (!_rightEl) return;
        var btn = _rightEl.querySelector('.task-act-deliver');
        if (!btn) return;
        var ds = computeDeliverState(detail, summary);
        btn.disabled = !ds.enabled;
        btn.setAttribute('data-act', ds.act);
        btn.textContent = ds.label;
        if (ds.titleText) btn.title = ds.titleText; else btn.removeAttribute('title');
    }

    // finishNavigable 是 AS2 动态计算（注册表就绪 + 地图解锁 + 当前是否战斗地图），不应被详情缓存永久固化。
    // 仅当当前显示为「满足 + 非远程 + 不可前往」（可能因注册表迟到/区域刚解锁而陈旧禁用）时，后台复查一次并就地修补；
    // 已可前往(true)不复查——陈旧 true 由 navigateFinish 服务端 not_navigable 兜底，避免每次选择都打 AS2。
    function maybeRefreshNavigable(index, summary, cached) {
        if (!summary || !summary.satisfied) return;
        if (!cached || cached.finishRemote === true || cached.finishNavigable === true) return;
        var reqSession = _session;
        sendPanelMsg('detail', { index: index }, function(data) {
            if (reqSession !== _session || _activeIndex !== index) return;
            if (!data || !data.success || !data.taskData) return;
            var nav = (data.taskData.finishNavigable === true);
            if (nav === cached.finishNavigable) return;
            cached.finishNavigable = nav;
            patchDeliverButton(cached, summary);
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
        if (t.classList.contains('task-act-deliver')) {
            if (t.getAttribute('data-act') === 'navigate') onNavigateFinish(t);
            else onDeliver(t);
        } else if (t.classList.contains('task-act-abandon')) {
            openAbandonConfirm();
        }
    }

    function onDeliver(btn) {
        if (_busy || _activeIndex < 0) return;
        var task = _tasks[_activeIndex];
        if (!task || !task.satisfied) return;     // 客户端预门控；AS2 端 taskCompleteCheck 二次硬门控
        // 远程交付门控（防御）：非远程任务即便绕过禁用态也不发请求；AS2 端 requires_npc 兜底
        var det = _detailCache[task.taskId];
        if (!det || det.finishRemote !== true) { toast('该任务需前往交付NPC处提交'); return; }
        var taskId = task.taskId;
        beginOp(btn);
        var reqSession = _session;
        sendPanelMsg('finishTask', { taskId: taskId }, function(data) {
            endOp(btn);
            if (reqSession !== _session) return;
            if (data && data.success) {
                // 远程交付成功后必须关面板：AS2 FinishTask 会 SetDialogue(完成对话) + 弹奖励提示界面 +
                // 可能自动接取链中下一任务再弹接取对话，这些原版 UI 都在游戏层，会被独占 web 覆盖层挡住
                // （玩家看不到也无法消解奖励弹窗）。关面板把它们露出来（closePanel 语义同前往交付 / 地图 navigate）。
                hideTip();
                Panels.close();
                Bridge.send({ type: 'panel', panel: 'tasks', cmd: 'close' });
            } else {
                toast(writeErrorMsg('交付失败', data));
                // 失败也消费刷新后的 tasks：任务未 splice 时 applyWriteSnapshot 按 taskId 原位保留选中，
                // 顺带把过期的 satisfied/可交付徽章/计数纠正回服务端真值（如交物型任务物品已被消耗）
                if (data && data.tasks) applyWriteSnapshot(data);
            }
        });
    }

    // 前往交付：复用地图跳转把玩家送到 finish_npc 地图位置；成功后关面板（场景在游戏内淡出跳转）
    function onNavigateFinish(btn) {
        if (_busy || _activeIndex < 0) return;
        var task = _tasks[_activeIndex];
        if (!task) return;
        var det = _detailCache[task.taskId];
        if (!det || det.finishNavigable !== true) { toast('该区域暂不可一键前往'); return; }
        beginOp(btn);
        var reqSession = _session;
        sendPanelMsg('navigateFinish', { taskId: task.taskId }, function(data) {
            endOp(btn);
            if (reqSession !== _session) return;
            if (data && data.success) {
                // 跳转已在游戏内发起（closePanel 语义同地图面板 navigate）→ 关闭任务面板
                hideTip();
                Panels.close();
                Bridge.send({ type: 'panel', panel: 'tasks', cmd: 'close' });
            } else {
                var msg = '无法前往交付NPC';
                if (data && data.error === 'not_navigable') msg = '该区域尚未解锁，无法一键前往';
                else if (data && data.error === 'npc_not_on_map') msg = '该任务NPC不在可跳转地图上';
                toast(msg);
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
        // 删除请求在途时（_busy）禁止关闭弹窗：否则用户点「确认放弃」后立刻点「取消」/遮罩，
        // 弹窗虽关但删除仍会在回包后执行，造成"以为取消了却被删"。请求结束后由回调统一关闭。
        if (_busy) return;
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
            case 'requires_npc':      return '该任务需前往交付NPC处提交';
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

        // 操作区（交付 / 前往 / 放弃）。配色纪律：功能按钮黑白灰，主次靠「填充 vs 描边」分层，不用橙。
        // 主操作按 finishRemote / finishNavigable 三态切换（data-act 决定点击行为）：
        //   满足+远程        → 「交付任务」直接远程交付（deliver）
        //   满足+非远程+可前往 → 「前往交付」一键跳转到 NPC 地图（navigate，复用地图跳转）
        //   满足+非远程+不可前往 → 「前往「NPC」交付」禁用（区域未解锁/战斗地图，需手动前往）
        //   未满足            → 「尚未满足交付条件」禁用
        var isMain = (summary && summary.type === '主线') || task.type === '主线';
        var ds = computeDeliverState(task, summary);
        html += '<div class="task-detail-actions">';
        html += '<button class="task-act-btn task-act-deliver" type="button" data-act="' + ds.act + '"' +
            (ds.enabled ? '' : ' disabled') +
            (ds.titleText ? ' title="' + escAttr(ds.titleText) + '"' : '') + '>' + escHtml(ds.label) + '</button>';
        html += '<button class="task-act-btn task-act-abandon" type="button"' +
            (isMain ? ' disabled title="主线任务无法放弃"' : '') + '>放弃任务</button>';
        html += '</div>';

        _rightEl.innerHTML = html;
    }

    // ═══════════════════════════════════════════════════════════
    // 事件日志 / 任务树（WS6）
    //   静态目录 task-catalog.json（build 派生，web 直读，零 AS2 传输）+ taskTreeState 进度小叠加
    //   → 渲染各链已完成/进行中节点；点节点看明细（明细来自 catalog）；「重播对话」命令回传 AS2
    //   由 _root.SetDialogue 在原版对话框播（成功关面板让对话框可见）。
    // ═══════════════════════════════════════════════════════════
    function enterLogTab() {
        var session = _session;
        _treeEl.innerHTML = '<div class="tlv-loading">加载任务树…</div>';
        if (!_logSelectedId) _logDetailEl.innerHTML = '<div class="task-empty-hint">从左侧任务树选择一个任务查看详情</div>';
        loadCatalog(function(cat) {
            if (session !== _session || _tab !== 'log') return;
            if (!cat) { _treeEl.innerHTML = '<div class="tlv-loading tlv-error">任务目录加载失败</div>'; return; }
            requestTreeState(function(state) {
                if (session !== _session || _tab !== 'log') return;
                if (!state) {
                    // 区分「桥/超时失败」与「真没记录」：失败给可重试错误态，别误导成"无任务记录"。
                    _treeState = null;
                    var errMsg = '<div class="tlv-loading tlv-error">任务进度加载失败（请重开面板重试）</div>';
                    _treeEl.innerHTML = errMsg;
                    if (_chartCanvasEl) _chartCanvasEl.innerHTML = errMsg;
                    return;
                }
                _treeState = state;
                renderActiveLogView();
            });
        });
    }

    // 加载 build 派生的静态任务目录（不可变，只 fetch 一次，模块级缓存）。
    // 测试钩子：harness 可预置 window.__TASK_CATALOG 跳过 fetch。
    function loadCatalog(cb) {
        if (_catalogState === 'ready') { cb(_catalog); return; }
        if (typeof window !== 'undefined' && window.__TASK_CATALOG) {
            _catalog = window.__TASK_CATALOG; _catalogState = 'ready'; cb(_catalog); return;
        }
        _catalogWaiters.push(cb);
        if (_catalogState === 'loading') return;
        _catalogState = 'loading';
        var flush = function(ok) {
            var ws = _catalogWaiters; _catalogWaiters = [];
            for (var i = 0; i < ws.length; i++) ws[i](ok ? _catalog : null);
        };
        try {
            fetch('modules/tasks/task-catalog.json').then(function(r) {
                if (!r.ok) throw new Error('http ' + r.status);
                return r.json();
            }).then(function(json) {
                _catalog = json; _catalogState = 'ready'; flush(true);
            })['catch'](function() {
                _catalogState = 'error'; flush(false);
            });
        } catch (e) {
            _catalogState = 'error'; flush(false);
        }
    }

    // 进度小叠加（只读存档态）：链进度 + 已完成 id 集 + 进行中 id 集。
    function requestTreeState(cb) {
        var session = _session;
        sendPanelMsg('treeState', null, function(data) {
            if (session !== _session) return;
            if (!data || !data.success) { cb(null); return; }
            cb({
                chainsProgress: data.chainsProgress || {},
                finished: toIdSet(data.finished),
                active: toIdSet(data.active)
            });
        });
    }
    function toIdSet(arr) {
        var set = Object.create(null);
        if (arr && arr.length) for (var i = 0; i < arr.length; i++) set[String(arr[i])] = 1;
        return set;
    }

    // 渲染任务树：每个有进展的链一段，节点按序号；状态 = 进行中 / 已完成。
    function renderTree() {
        if (!_catalog || !_treeState) return;
        var fin = _treeState.finished, act = _treeState.active;
        var html = '';
        var anyChain = false;

        // 有序号链（含主线），主线置顶，其余按五类序
        var names = Object.keys(_catalog.chains || {});
        names.sort(function(a, b) {
            if (a === '主线') return -1; if (b === '主线') return 1;
            return ((CATEGORY_ORDER[CATEGORY_MAP[a]] != null ? CATEGORY_ORDER[CATEGORY_MAP[a]] : 9)
                  - (CATEGORY_ORDER[CATEGORY_MAP[b]] != null ? CATEGORY_ORDER[CATEGORY_MAP[b]] : 9));
        });
        for (var n = 0; n < names.length; n++) {
            var nodes = collectChainNodes(_catalog.chains[names[n]], fin, act);
            if (!nodes.length) continue;
            anyChain = true;
            html += renderChainSection(names[n], nodes);
        }
        // 无序号链（委托等）：事件日志比原版树更包容，已完成/进行中也展示
        var uns = _catalog.chainsUnsequenced || {};
        var unames = Object.keys(uns);
        for (var u = 0; u < unames.length; u++) {
            var unodes = collectChainNodes(uns[unames[u]], fin, act);
            if (!unodes.length) continue;
            anyChain = true;
            html += renderChainSection(unames[u], unodes);
        }

        _treeEl.innerHTML = anyChain ? html : '<div class="tlv-loading">暂无已完成或进行中的任务记录</div>';
    }

    function collectChainNodes(ids, fin, act) {
        var nodes = [];
        if (!ids) return nodes;
        for (var i = 0; i < ids.length; i++) {
            var idk = String(ids[i]);
            if (act[idk]) nodes.push({ id: idk, state: 'active' });
            else if (fin[idk]) nodes.push({ id: idk, state: 'done' });
        }
        return nodes;
    }

    function renderChainSection(name, nodes) {
        var cat = CATEGORY_MAP[name] || '其他';
        var html = '<div class="tlv-chain" data-cat="' + escAttr(cat) + '">';
        html += '<div class="tlv-chain-head"><span class="tlv-chain-dot"></span>' + escHtml(name) +
            '<span class="tlv-chain-count">' + nodes.length + '</span></div>';
        html += '<div class="tlv-nodes">';
        for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            var t = _catalog.tasks[node.id];
            var title = (t && t.title) ? t.title : ('任务 ' + node.id);
            var sel = (node.id === _logSelectedId) ? ' selected' : '';
            html += '<button type="button" class="tlv-node ' + node.state + sel + '" data-task-id="' + escAttr(node.id) + '">' +
                '<span class="tlv-node-state"></span>' +
                '<span class="tlv-node-title">' + escHtml(title) + '</span>' +
            '</button>';
        }
        html += '</div></div>';
        return html;
    }

    function onTreeClick(e) {
        var t = e.target;
        while (t && t !== _treeEl && !(t.classList && t.classList.contains('tlv-node'))) t = t.parentNode;
        if (!t || t === _treeEl || !t.classList || !t.classList.contains('tlv-node')) return;
        var id = t.getAttribute('data-task-id');
        if (id) selectLogNode(id);
    }

    function selectLogNode(id) {
        _logSelectedId = String(id);
        var nodes = _treeEl.querySelectorAll('.tlv-node');
        for (var i = 0; i < nodes.length; i++) {
            nodes[i].classList.toggle('selected', nodes[i].getAttribute('data-task-id') === _logSelectedId);
        }
        // 图表视图：同步高亮选中六边形并滚动入视
        if (_chartCanvasEl) {
            var hexes = _chartCanvasEl.querySelectorAll('.tlv-hex'), selHex = null;
            for (var h = 0; h < hexes.length; h++) {
                var on = (hexes[h].getAttribute('data-task-id') === _logSelectedId);
                hexes[h].classList.toggle('selected', on);
                if (on) selHex = hexes[h];
            }
            if (selHex && _logView === 'chart' && selHex.scrollIntoView) {
                try { selHex.scrollIntoView({ block: 'center', inline: 'center' }); } catch (e) { selHex.scrollIntoView(); }
            }
        }
        renderLogDetail(_logSelectedId);
    }

    // 日志明细：复用 mine 详情的需求/奖励 HTML 结构（read-only，无交付/放弃），加对话回放按钮。
    function renderLogDetail(id) {
        var t = _catalog && _catalog.tasks[id];
        if (!t) { _logDetailEl.innerHTML = '<div class="task-empty-hint">无任务数据</div>'; return; }
        // 二态：进行中 / 已完成（未接取=locked 不进此面板）。
        var st = (_treeState && _treeState.active[id]) ? 'active' : ((_treeState && _treeState.finished[id]) ? 'done' : 'locked');
        // 防剧透：未接取(locked)任务绝不泄露标题/描述/需求/奖励/对话——只给占位。图表已只含已接取节点，
        // 此为纵深防御（即便经 QA 钩子/异常态选中 locked id 也不漏内容）。
        if (st === 'locked') {
            _logDetailEl.innerHTML = '<div class="task-detail-head"><div class="task-title-box">' +
                '<span class="task-title-line1">未接取</span>' +
                '<span class="task-title-line2">完成前置任务后解锁</span></div>' +
                '<div class="tlv-detail-badge locked">未接取</div></div>';
            return;
        }
        var html = '';
        html += '<div class="task-detail-head"><div class="task-title-box">' +
            '<span class="task-title-line1">' + escHtml(t.type || '任务') + '</span>' +
            '<span class="task-title-line2">' + escHtml(t.title || '') + '</span></div>';
        var stLabel = (st === 'active') ? '进行中' : '已完成';
        html += '<div class="tlv-detail-badge ' + st + '">' + stLabel + '</div></div>';

        html += '<div class="task-desc-box">' + escHtml(t.description || '') +
            '<span class="corner-horizontal top-left"></span><span class="corner-horizontal top-right"></span>' +
            '<span class="corner-horizontal bottom-left"></span><span class="corner-horizontal bottom-right"></span>' +
            '<span class="corner-vertical top-left"></span><span class="corner-vertical top-right"></span>' +
            '<span class="corner-vertical bottom-left"></span><span class="corner-vertical bottom-right"></span></div>';

        html += '<div class="task-requirement-area">';
        var reqI = 0;
        if (t.stageReq) {
            html += '<div class="task-requirement" data-i="' + reqI + '"><div class="task-requirement-inner">' +
                '<div class="scroll-track"></div><div class="task-requirement-title stage"></div>' +
                '<div class="task-requirement-stage-name">' + escHtml(t.stageReq.name || '') + '</div></div>';
            if (t.stageReq.difficulty) html += '<span class="task-difficulty-label difficulty-' + escAttr(t.stageReq.difficulty) + '">' + escHtml(t.stageReq.difficulty) + '</span>';
            html += '</div>'; reqI++;
        }
        if (t.itemReqs && t.itemReqs.length) {
            var titleClass = (t.itemReqs[0].kind === 'contain') ? 'contain' : 'submit';
            html += '<div class="task-item-requirement" data-i="' + reqI + '"><div class="task-item-requirement-inner">' +
                '<div class="scroll-track"></div><div class="task-requirement-title ' + titleClass + '"></div><div class="task-requirement-items">';
            for (var ir = 0; ir < t.itemReqs.length; ir++) html += itemIconHtml(t.itemReqs[ir].name, t.itemReqs[ir].count, ir);
            html += '</div></div></div>'; reqI++;
        }
        if (t.npcName) {
            html += '<div class="task-npc" data-i="' + reqI + '"><div class="task-npc-left"><div class="scroll-track"></div>' +
                '<div class="task-npc-title"></div><div class="task-npc-name"><span>' + escHtml(t.npcName) + '</span></div></div>' +
                '<div class="task-npc-avatar"><img src="' + avatarUrl(t.npcName) + '" onerror="this.onerror=null;this.src=\'' + defaultAvatarUrl() + '\';" alt=""></div></div>';
            reqI++;
        }
        html += '</div>';

        if (t.rewards && t.rewards.length) {
            html += '<div class="task-reward-section"><div class="task-reward-box"><span>任务奖励</span></div><div class="task-reward-items">';
            for (var r = 0; r < t.rewards.length; r++) html += itemIconHtml(t.rewards[r].name, t.rewards[r].count, r);
            html += '</div></div>';
        }

        // 剧情对话回放（轻量内联文本）：仅显示玩家【已经历过】的对话，避免回放未到达的剧情=剧透/语义不通。
        //   接取对话：已接取(进行中 active 或 已完成 done) 才显示；
        //   完成对话：仅已完成(done) 才显示（未完成时不该出现「完成对话」——修真机发现的困惑）。
        // 对话文本仍留 AS2，点击才按需回传渲染到下方 .tlv-dialogue，不关面板，体验连续。
        var accepted = (st === 'active' || st === 'done');
        var showGet = t.hasGetConv && accepted;
        var showFinish = t.hasFinishConv && (st === 'done');
        if (showGet || showFinish) {
            html += '<div class="tlv-replay-actions">';
            if (showGet) html += '<button type="button" class="tlv-replay-btn" data-which="get" data-task-id="' + escAttr(id) + '">接取对话</button>';
            if (showFinish) html += '<button type="button" class="tlv-replay-btn" data-which="finish" data-task-id="' + escAttr(id) + '">完成对话</button>';
            html += '</div>';
            html += '<div class="tlv-dialogue"></div>';
        }

        _logDetailEl.innerHTML = html;
    }

    function onLogDetailClick(e) {
        var t = e.target;
        while (t && t !== _logDetailEl && !(t.classList && t.classList.contains('tlv-replay-btn'))) t = t.parentNode;
        if (!t || t === _logDetailEl || !t.classList || !t.classList.contains('tlv-replay-btn')) return;
        if (t.disabled || t.classList.contains('task-btn-pending')) return;
        onReplayDialogue(t.getAttribute('data-task-id'), t.getAttribute('data-which'), t);
    }

    // 重播对话（轻量内联文本）：按需回传单任务对话行，渲染到详情下方 .tlv-dialogue，不关面板。
    function onReplayDialogue(taskId, which, btn) {
        if (!taskId) return;
        var allBtns = _logDetailEl.querySelectorAll('.tlv-replay-btn');
        for (var i = 0; i < allBtns.length; i++) allBtns[i].classList.remove('active');
        if (btn) { btn.classList.add('active'); btn.classList.add('task-btn-pending'); }
        var dia = _logDetailEl.querySelector('.tlv-dialogue');
        if (dia) dia.innerHTML = '<div class="tlv-dia-empty">加载对话…</div>';
        var reqSession = _session;
        var reqSelected = _logSelectedId;
        sendPanelMsg('replayDialogue', { taskId: idForRequest(taskId), which: which || 'get' }, function(data) {
            if (btn) btn.classList.remove('task-btn-pending');
            if (reqSession !== _session || _logSelectedId !== reqSelected) return; // 已切走/换节点
            var dia2 = _logDetailEl.querySelector('.tlv-dialogue');
            if (!dia2) return;
            if (!data || !data.success || !data.lines || !data.lines.length) {
                dia2.innerHTML = '<div class="tlv-dia-empty">' + ((data && data.error === 'no_dialogue') ? '该任务无此对话' : '无法加载对话') + '</div>';
                return;
            }
            dia2.innerHTML = renderDialogueLines(data.lines);
        });
    }
    // 对话文本含 AS2 htmlText 标记（如 $PC_TITLE→HeroUtil.getHeroTitle() 回的 <FONT COLOR=...>动态称号</FONT>）。
    // 复用全项目统一的 PanelTooltip.convertAS2Html：FONT(color/size/face)→span style、B/I/U、BR、P align，
    // 且带颜色/字号/face 白名单校验（安全）。PanelTooltip 缺失时退回 escHtml（不渲染但不破坏）。
    function dialogueHtml(s) {
        if (typeof PanelTooltip !== 'undefined' && PanelTooltip && PanelTooltip.convertAS2Html) return PanelTooltip.convertAS2Html(s);
        return escHtml(s);
    }
    function renderDialogueLines(lines) {
        var html = '';
        for (var i = 0; i < lines.length; i++) {
            var ln = lines[i] || {};
            html += '<div class="tlv-dia-line">';
            if (ln.speaker) {
                html += '<div class="tlv-dia-head"><span class="tlv-dia-speaker">' + dialogueHtml(ln.speaker) + '</span>';
                if (ln.sub) html += '<span class="tlv-dia-sub">' + dialogueHtml(ln.sub) + '</span>';
                html += '</div>';
            }
            html += '<div class="tlv-dia-text">' + dialogueHtml(ln.text || '') + '</div>';
            html += '</div>';
        }
        return html;
    }
    // catalog 用 String id 键；AS2 tasks 用数字 id。回传时尽量还原数字（与 AS2 一致）。
    function idForRequest(id) {
        var n = Number(id);
        return (!isNaN(n) && String(n) === String(id)) ? n : id;
    }

    // 渲染当前 log 子视图（列表 / 图表），由 enterLogTab 与切换共用
    function renderActiveLogView() {
        if (_logView === 'chart') renderChart();
        else renderTree();
    }

    // ═══════════════════════════════════════════════════════════
    // 图表视图（BALDR SKY 风任务树）
    //   数据已证实是「主干+分支」结构（237/238 单前置、跨链边多为 主线里程碑→侧链入口），
    //   故用「拓扑深度分行 + 按链分列 + 前置连线」即可，无需重型 DAG 布局算法。
    //   委托等无序号链不在图中（无前置顺序，列表视图展示）。点节点复用列表的明细+内联对话。
    // ═══════════════════════════════════════════════════════════
    var CHART_COL_W = 112, CHART_ROW_H = 64;

    // ── 任务线配色配置（写手可改）────────────────────────────────────────────
    //   三个杠杆：rim=边框/外环色(链身份主区分)、num=数字色、face=节点面色(可选,覆盖"状态面")。
    //   默认：rim+num 区分链，face 仍由状态(已完成银/进行中白/未接取暗)驱动以保可读性。
    //   阵营链(黑铁会/铁枪会)按制作组要求=黑底白字：设 face(黑)+num(白)，状态靠辉光/暗淡体现。
    //   未列出的链回落 _default。颜色取低饱和，避免抢"焦点橙(仅提交NPC)"与状态对比。
    var CHART_CHAIN_STYLE = {
        '主线': { rim: '#dcdcdc', num: '#1a1a1a' },
        '支线': { rim: '#6fa8c7', num: '#1a1a1a' },
        '大学': { rim: '#8fb87a', num: '#1a1a1a' },
        '后勤': { rim: '#c7a86f', num: '#1a1a1a' },
        '将军': { rim: '#b8788f', num: '#1a1a1a' },
        '引导': { rim: '#9a9a9a', num: '#1a1a1a' },
        '挑战': { rim: '#c77a6f', num: '#1a1a1a' },
        '预览': { rim: '#8f8fb8', num: '#1a1a1a' },
        '异形': { rim: '#7ac7b8', num: '#1a1a1a' },
        '彩蛋': { rim: '#c79f6f', num: '#1a1a1a' },
        '废城': { rim: '#a08f7a', num: '#1a1a1a' },
        '情报': { rim: '#7a9fc7', num: '#1a1a1a' },
        // 阵营链模板（数据尚无此链，预留；底黑数字白）：
        '黑铁会': { rim: '#5a5a5a', face: '#111111', num: '#ffffff' },
        '铁枪会': { rim: '#666666', face: '#141414', num: '#ffffff' },
        '_default': { rim: '#888888', num: '#1a1a1a' }
    };
    function chainStyleOf(name) { return CHART_CHAIN_STYLE[name] || CHART_CHAIN_STYLE._default; }

    function computeChartLayout(mode) {
        if (!_catalog) return null;
        var tasks = _catalog.tasks;
        var seqChains = _catalog.chains || {};
        var chainNames = Object.keys(seqChains);
        // 防剧透：图表只纳入玩家【已接取(active)/已完成(done)】的节点（与列表视图同口径）。未接取任务
        // 既不进图、也不暴露其标题/分支结构。fin/act 来自只读存档态叠加 _treeState（缺省空集→空图）。
        var fin = (_treeState && _treeState.finished) ? _treeState.finished : Object.create(null);
        var act = (_treeState && _treeState.active) ? _treeState.active : Object.create(null);
        // inChart: id → chainName（仅 sequenced 链中已接取/已完成的节点）
        var inChart = Object.create(null);
        for (var ci = 0; ci < chainNames.length; ci++) {
            var arr = seqChains[chainNames[ci]];
            for (var k = 0; k < arr.length; k++) {
                var idk0 = String(arr[k]);
                if (act[idk0] || fin[idk0]) inChart[idk0] = chainNames[ci];
            }
        }
        // 列分配：主线居中(0)，其余交替左右
        var colOf = Object.create(null);
        colOf['主线'] = 0;
        var others = chainNames.filter(function (n) { return n !== '主线'; });
        for (var oi = 0; oi < others.length; oi++) {
            colOf[others[oi]] = ((oi % 2 === 0) ? 1 : -1) * (Math.floor(oi / 2) + 1);
        }
        // 拓扑深度（最长前置链，仅图内边）
        var depthMemo = Object.create(null);
        var depthVisiting = Object.create(null);
        function depth(id) {
            if (depthMemo[id] != null) return depthMemo[id];
            if (depthVisiting[id]) return 0; // 环检测：访问中重入→记 0（任务数据应无环，仅自卫；只缓存最终值不占位污染）
            depthVisiting[id] = 1;
            var t = tasks[id], d = 0;
            if (t && t.req) for (var r = 0; r < t.req.length; r++) {
                var rk = String(t.req[r]);
                if (inChart[rk] != null) d = Math.max(d, 1 + depth(rk));
            }
            depthVisiting[id] = 0;
            depthMemo[id] = d; return d;
        }
        var allIds = Object.keys(inChart);

        // chapter 模式过滤集合：链头/链尾 + 分支点(跨链出边) + 合并点(入度≥2) + 进行中
        var keep = null;
        if (mode === 'chapter') {
            keep = Object.create(null);
            var indeg = Object.create(null), branch = Object.create(null);
            for (var a = 0; a < allIds.length; a++) {
                var t2 = tasks[allIds[a]];
                if (t2 && t2.req) for (var rr = 0; rr < t2.req.length; rr++) {
                    var rk2 = String(t2.req[rr]);
                    if (inChart[rk2] == null) continue;
                    indeg[allIds[a]] = (indeg[allIds[a]] || 0) + 1;
                    if (inChart[rk2] !== inChart[allIds[a]]) branch[rk2] = 1; // 跨链出边 = 分支点
                }
            }
            for (var cn = 0; cn < chainNames.length; cn++) {
                var carr = seqChains[chainNames[cn]];
                // 链头/链尾取【已接取(在图内)】节点的首尾——跳过未接取节点（防剧透过滤后链可能首尾内缩）。
                var visible = [];
                for (var vi = 0; vi < carr.length; vi++) { var vk = String(carr[vi]); if (inChart[vk] != null) visible.push(vk); }
                if (visible.length) { keep[visible[0]] = 1; keep[visible[visible.length - 1]] = 1; }
            }
            for (var b = 0; b < allIds.length; b++) {
                var id2 = allIds[b];
                if (branch[id2] || (indeg[id2] || 0) >= 2 || act[id2]) keep[id2] = 1;
            }
        }

        // 节点
        var nodes = [], minCol = 0, maxCol = 0;
        for (var ii = 0; ii < allIds.length; ii++) {
            var id = allIds[ii];
            if (keep && !keep[id]) continue;
            var col = colOf[inChart[id]] || 0;
            minCol = Math.min(minCol, col); maxCol = Math.max(maxCol, col);
            var st = act[id] ? 'active' : (fin[id] ? 'done' : 'locked');
            nodes.push({ id: id, chain: inChart[id], col: col, depth: depth(id), state: st });
        }
        // y：detail 用原始 depth；chapter 用 kept 子集紧凑 rank
        if (mode === 'chapter') {
            nodes.sort(function (x, y) { return x.depth - y.depth; });
            var rank = -1, lastDepth = -999;
            for (var n = 0; n < nodes.length; n++) {
                if (nodes[n].depth !== lastDepth) { lastDepth = nodes[n].depth; rank++; }
                nodes[n].row = rank;
            }
        } else {
            for (var n2 = 0; n2 < nodes.length; n2++) nodes[n2].row = nodes[n2].depth;
        }
        // 坐标
        var maxRow = 0;
        for (var p = 0; p < nodes.length; p++) {
            nodes[p].x = (nodes[p].col - minCol) * CHART_COL_W + CHART_COL_W / 2;
            nodes[p].y = nodes[p].row * CHART_ROW_H + CHART_ROW_H / 2;
            maxRow = Math.max(maxRow, nodes[p].row);
        }
        var nodeSet = Object.create(null);
        for (var q = 0; q < nodes.length; q++) nodeSet[nodes[q].id] = nodes[q];

        // 边
        var edges = [];
        if (mode === 'chapter') {
            // 最近 kept 祖先（折叠线性段）
            for (var e = 0; e < nodes.length; e++) {
                var nid = nodes[e].id, seen = Object.create(null);
                var stack = (tasks[nid] && tasks[nid].req) ? tasks[nid].req.map(String) : [];
                while (stack.length) {
                    var anc = stack.shift();
                    if (seen[anc] || inChart[anc] == null) continue;
                    seen[anc] = 1;
                    if (nodeSet[anc]) edges.push({ from: anc, to: nid, cross: inChart[anc] !== nodes[e].chain });
                    else { var at = tasks[anc]; if (at && at.req) stack = stack.concat(at.req.map(String)); }
                }
            }
        } else {
            for (var e2 = 0; e2 < nodes.length; e2++) {
                var n3 = nodes[e2], t3 = tasks[n3.id];
                if (t3 && t3.req) for (var r3 = 0; r3 < t3.req.length; r3++) {
                    var rk3 = String(t3.req[r3]);
                    if (nodeSet[rk3]) edges.push({ from: rk3, to: n3.id, cross: inChart[rk3] !== n3.chain });
                }
            }
        }
        return {
            nodes: nodes, edges: edges, nodeSet: nodeSet,
            width: (maxCol - minCol + 1) * CHART_COL_W,
            height: (maxRow + 1) * CHART_ROW_H
        };
    }

    function edgePath(a, b) {
        var x1 = a.x, y1 = a.y, x2 = b.x, y2 = b.y, my = (y1 + y2) / 2;
        return 'M' + x1 + ',' + y1 + ' C' + x1 + ',' + my + ' ' + x2 + ',' + my + ' ' + x2 + ',' + y2;
    }
    function chartNodeLabel(t) {
        if (t && t.chain && t.chain[1] != null) return String(t.chain[1]); // 链内序号
        return (t && t.title) ? t.title.charAt(0) : '?';
    }

    function renderChart() {
        if (!_chartCanvasEl) return;
        if (!_catalog) { _chartCanvasEl.innerHTML = '<div class="tlv-loading">任务目录加载中…</div>'; return; }
        var layout = computeChartLayout(_chartMode);
        _chartLayout = layout;
        if (!layout || !layout.nodes.length) {
            _chartCanvasEl.innerHTML = '<div class="tlv-loading">暂无可展示的任务链</div>';
            return;
        }
        var W = layout.width, H = layout.height;
        var svg = '<svg class="tlv-chart-edges" width="' + W + '" height="' + H + '" viewBox="0 0 ' + W + ' ' + H + '">';
        for (var i = 0; i < layout.edges.length; i++) {
            var ed = layout.edges[i], a = layout.nodeSet[ed.from], b = layout.nodeSet[ed.to];
            if (!a || !b) continue;
            svg += '<path class="tlv-edge' + (ed.cross ? ' cross' : '') + '" d="' + edgePath(a, b) + '"/>';
        }
        svg += '</svg>';
        var html = '';
        for (var j = 0; j < layout.nodes.length; j++) {
            var n = layout.nodes[j], t = _catalog.tasks[n.id];
            var sel = (n.id === _logSelectedId) ? ' selected' : '';
            var cs = chainStyleOf(n.chain);
            // 链配色经自定义属性下发：--hex-rim(外环) / --hex-num(数字)；face 仅链覆盖时设(否则由状态类驱动)
            var style = 'left:' + n.x + 'px;top:' + n.y + 'px;--hex-rim:' + cs.rim + ';--hex-num:' + (cs.num || '#1a1a1a') + ';';
            if (cs.face) style += '--hex-face:' + cs.face + ';';
            html += '<button type="button" class="tlv-hex ' + n.state + sel + '" data-task-id="' + escAttr(n.id) +
                '" data-cat="' + escAttr(CATEGORY_MAP[n.chain] || '其他') + '" style="' + style + '"' +
                ' title="' + escAttr(t ? (t.title || '') : '') + '"><span class="tlv-hex-label">' + escHtml(chartNodeLabel(t)) + '</span></button>';
        }
        _chartCanvasEl.style.width = W + 'px';
        _chartCanvasEl.style.height = H + 'px';
        _chartCanvasEl.innerHTML = svg + html;
        applyChartZoom();
    }

    // WebView2 = Chromium，用 CSS zoom（reflow 滚动区域，比 transform scale 省去手动算尺寸）
    function applyChartZoom() {
        if (_chartCanvasEl) _chartCanvasEl.style.zoom = _chartZoom;
    }

    function onChartClick(e) {
        if (_chartDragMoved) { _chartDragMoved = false; return; } // 刚发生拖拽平移 → 抑制本次点击，不误选节点
        var t = e.target;
        while (t && t !== _chartCanvasEl && !(t.classList && t.classList.contains('tlv-hex'))) t = t.parentNode;
        if (!t || t === _chartCanvasEl || !t.classList || !t.classList.contains('tlv-hex')) return;
        var id = t.getAttribute('data-task-id');
        if (id) selectLogNode(id);
    }

    // ── 左键拖拽平移（取代滚动条，二维画布更直观；保留滚轮，隐藏滚动条）──
    // 「点击 vs 拖拽」判定：移动超阈值才算拖拽并平移 + 抑制随后的 click（防误选节点）。
    var CHART_DRAG_THRESHOLD = 4;
    function onChartMouseDown(e) {
        if (e.button !== 0 || !_chartViewportEl) return;          // 仅左键
        _chartDrag = { x: e.clientX, y: e.clientY, sl: _chartViewportEl.scrollLeft, st: _chartViewportEl.scrollTop };
        _chartDragMoved = false;
        _chartViewportEl.classList.add('grabbing');
        document.addEventListener('mousemove', onChartMouseMove);
        document.addEventListener('mouseup', onChartMouseUp);
    }
    function onChartMouseMove(e) {
        if (!_chartDrag) return;
        var dx = e.clientX - _chartDrag.x, dy = e.clientY - _chartDrag.y;
        if (!_chartDragMoved && (Math.abs(dx) > CHART_DRAG_THRESHOLD || Math.abs(dy) > CHART_DRAG_THRESHOLD)) _chartDragMoved = true;
        if (_chartDragMoved) {
            _chartViewportEl.scrollLeft = _chartDrag.sl - dx;
            _chartViewportEl.scrollTop = _chartDrag.st - dy;
            if (e.preventDefault) e.preventDefault();
        }
    }
    function onChartMouseUp() {
        _chartDrag = null;
        if (_chartViewportEl) _chartViewportEl.classList.remove('grabbing');
        document.removeEventListener('mousemove', onChartMouseMove);
        document.removeEventListener('mouseup', onChartMouseUp);
        // 注：_chartDragMoved 不在此清，留给随后的 onChartClick 读取并自清（拖拽末尾的 click 紧跟 mouseup）
    }
    function endChartDrag() { // 生命周期清理（onClose）：确保不残留 document 监听
        _chartDrag = null; _chartDragMoved = false;
        if (_chartViewportEl) _chartViewportEl.classList.remove('grabbing');
        document.removeEventListener('mousemove', onChartMouseMove);
        document.removeEventListener('mouseup', onChartMouseUp);
    }

    function onLogbarClick(e) {
        var t = e.target;
        while (t && !(t.classList && t.classList.contains('tlv-seg-btn'))) t = t.parentNode;
        if (!t || !t.classList || !t.classList.contains('tlv-seg-btn')) return;
        if (t.getAttribute('data-logview')) { setLogView(t.getAttribute('data-logview')); return; }
        if (t.getAttribute('data-chartmode')) {
            _chartMode = t.getAttribute('data-chartmode');
            setSegActive(t);
            renderChart();
            return;
        }
        if (t.getAttribute('data-zoom')) {
            _chartZoom = Number(t.getAttribute('data-zoom')) || 1;
            setSegActive(t);
            applyChartZoom();
            return;
        }
    }
    function setSegActive(btn) {
        var seg = btn.parentNode;
        if (!seg) return;
        var btns = seg.querySelectorAll('.tlv-seg-btn');
        for (var i = 0; i < btns.length; i++) btns[i].classList.toggle('active', btns[i] === btn);
    }
    // 重置工具栏三组分段按钮到默认高亮（列表/详细/100%）——onOpen 调，防 DOM 复用残留上次 .active
    function resetChartToolbarButtons() {
        if (!_el) return;
        var defaults = [['data-logview', 'list'], ['data-chartmode', 'detail'], ['data-zoom', '1']];
        for (var d = 0; d < defaults.length; d++) {
            var attr = defaults[d][0], val = defaults[d][1];
            var btns = _el.querySelectorAll('.tlv-logbar .tlv-seg-btn[' + attr + ']');
            for (var i = 0; i < btns.length; i++) btns[i].classList.toggle('active', btns[i].getAttribute(attr) === val);
        }
    }
    function setLogView(view) {
        if (view !== 'list' && view !== 'chart') return;
        _logView = view;
        _logviewEl.setAttribute('data-logview', view);
        // 工具栏分段高亮
        var segBtns = _el.querySelectorAll('.tlv-logbar .tlv-seg-btn[data-logview]');
        for (var i = 0; i < segBtns.length; i++) segBtns[i].classList.toggle('active', segBtns[i].getAttribute('data-logview') === view);
        _chartCtrlsEl.hidden = (view !== 'chart');
        _treeEl.hidden = (view === 'chart');
        _chartViewportEl.hidden = (view !== 'chart');
        renderActiveLogView();
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
            _abandonPendingId: function() { return _pendingAbandonId; },
            // 绕过按钮直发面板命令（QA 验证服务端门控，如对非远程任务发 finishTask 应回 requires_npc）
            _debugSend: function(cmd, extra, cb) { return sendPanelMsg(cmd, extra, cb); },
            // 事件日志/任务树（WS6）QA 钩子
            _logState: function() {
                return {
                    catalogState: _catalogState,
                    selectedId: _logSelectedId,
                    chainCount: _treeEl ? _treeEl.querySelectorAll('.tlv-chain').length : 0,
                    nodeCount: _treeEl ? _treeEl.querySelectorAll('.tlv-node').length : 0,
                    replayBtnCount: _logDetailEl ? _logDetailEl.querySelectorAll('.tlv-replay-btn').length : 0
                };
            },
            _selectLogNode: function(id) { selectLogNode(id); },
            // 图表视图（BALDR SKY 风）QA 钩子
            _setLogView: function(v) { setLogView(v); },
            _chartState: function() {
                return {
                    logView: _logView, zoom: _chartZoom, mode: _chartMode,
                    hexCount: _chartCanvasEl ? _chartCanvasEl.querySelectorAll('.tlv-hex').length : 0,
                    edgeCount: _chartCanvasEl ? _chartCanvasEl.querySelectorAll('.tlv-edge').length : 0,
                    selectedHex: _chartCanvasEl ? !!_chartCanvasEl.querySelector('.tlv-hex.selected') : false
                };
            },
            _setChartMode: function(m) { _chartMode = m; renderChart(); },
            _setChartZoom: function(z) { _chartZoom = z; applyChartZoom(); },
            _chainStyle: CHART_CHAIN_STYLE,   // 写手可读改的任务线配色配置
            _hexRim: function(id) { var h = _chartCanvasEl && _chartCanvasEl.querySelector('.tlv-hex[data-task-id="' + id + '"]'); return h ? h.style.getPropertyValue('--hex-rim').trim() : ''; }
        };
    }
})();
