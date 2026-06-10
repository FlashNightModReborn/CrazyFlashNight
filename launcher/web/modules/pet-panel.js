(function() {
    'use strict';

    // ═══════════════════════════════════════════════════════════
    // 战宠面板 — 军事战术风 · 固定画布 1024×576
    //
    // 视觉基线对齐任务面板：固定设计分辨率 + 整体 transform 缩放
    // （updateFitScale / bindScaleWatcher 照搬 task-panel）。
    // 体验层：按钮 pending 态 / Toast 三色队列 / 进度条入场动画 /
    // 卡片局部更新（出战不整页重排）/ 商店分类缓存 / 页面淡入切换 /
    // 排序·筛选 / 底部「当前选择」常驻栏 / 资源数字脉冲。
    //
    // 数据权威与通信协议保持不变：snapshot / pet_lib / adopt_list /
    // adopt / deploy / restore_stamina / level_up / delete / advance /
    // expand_slot 全走 AS2 回包，JS 仅展示层。
    // ═══════════════════════════════════════════════════════════

    var DESIGN_W = 1024;
    var DESIGN_H = 576;

    // ── 状态 ──
    var _el;
    var _pets = [];
    var _snapshot = null;
    var _currentPage = 'list';
    var _activePetIdx = -1;     // 进阶页目标（_pets 下标）
    var _selectedSlot = -1;     // 列表页底部选中栏的 slotIndex
    var _storeCategoryIdx = 0;
    var _storeData = [];
    var _storeCategories = [];
    var _storeCache = {};       // 分类缓存：rosterType:catIdx → { adoptable, categories }
    var _petLib = null;
    var _pendingReq = {};
    var _reqSeq = 0;
    var _session = 0;
    var _busy = false;
    var _sortMode = 'default';
    var _filterMode = 'all';
    var _firstSnapshot = true;
    var _prevGold = null, _prevKpoint = null;
    var _cssLink = null;
    var _resizeObserver = null;
    var _toasts = [];           // 活跃 toast DOM 列表
    var _docClickBound = null;
    var _tipEl = null;          // 当前悬浮 data-tip 元素（PanelTooltip）
    var _rosterType = 'partner';

    // ── DOM refs ──
    var _pageList, _pageStore, _pageAdvance;
    var _gridEl, _gridWrap, _listEmptyEl, _selbarEl, _toastStack;

    // ═══════════════════════════════════════════════════════════
    // Panel 注册
    // ═══════════════════════════════════════════════════════════
    // ═══════════════════════════════════════════════════════════
    // DOM 创建
    // ═══════════════════════════════════════════════════════════
    function createDOM(container) {
        _el = document.createElement('div');
        _el.style.position = 'absolute';
        _el.style.inset = '0';
        _el.style.margin = '0';
        _el.style.padding = '0';
        _el.className = 'team-child team-pet-child';

        _el.innerHTML =
            '<div class="pet-scale-shell">' +
            '<div class="pet-panel">' +

                // ── 页面 1：列表 ──
                '<div class="pet-page" id="pet-page-list">' +
                    '<div class="pet-page-header">' +
                        '<span class="pet-title-mark"></span>' +
                        '<h1 class="pet-page-title">战宠管理</h1>' +
                        '<div class="pet-header-spacer"></div>' +
                        resourcesHtml() +
                        '<button class="pet-close-btn" type="button" data-tip="关闭" aria-label="关闭" data-audio-cue="cancel">✕</button>' +
                    '</div>' +
                    '<div class="pet-toolbar">' +
                        '<span class="pet-status-item">出战 <strong id="pet-deploy-count">0/0</strong></span>' +
                        '<span class="pet-status-item">宠物栏 <strong id="pet-slot-count">0/0</strong></span>' +
                        '<div class="pet-toolbar-spacer"></div>' +
                        sortDropdownHtml() +
                        filterDropdownHtml() +
                        '<button class="pet-btn-primary" type="button" id="pet-expand-btn" data-audio-cue="confirm" data-tip="花费金币扩充一个宠物栏位">＋ 开格子</button>' +
                    '</div>' +
                    '<div class="pet-grid-wrap" id="pet-grid-wrap">' +
                        '<div class="pet-grid" id="pet-grid"></div>' +
                        '<div class="pet-list-empty" id="pet-list-empty" hidden>' +
                            '<span class="pet-empty-mark"></span>' +
                            '<span class="pet-empty-text">暂无战宠 · 点击右上「领养宠物」</span>' +
                        '</div>' +
                    '</div>' +
                    selbarHtml() +
                '</div>' +

                // ── 页面 2：领养商店 ──
                '<div class="pet-page" id="pet-page-store" hidden>' +
                    '<div class="pet-page-header">' +
                        '<button class="pet-page-back" type="button" data-audio-cue="cancel">‹ 返回</button>' +
                        '<span class="pet-title-mark"></span>' +
                        '<h2 class="pet-page-title pet-page-title-sub">领养宠物</h2>' +
                        '<div class="pet-header-spacer"></div>' +
                        resourcesHtml() +
                    '</div>' +
                    '<div class="pet-page-body">' +
                        '<div class="pet-store-tabs" id="pet-store-tabs"></div>' +
                        '<div class="pet-store-grid" id="pet-store-grid"></div>' +
                        '<div class="pet-store-empty" id="pet-store-empty" hidden>该分类下暂无可领养宠物</div>' +
                        '<div class="pet-store-loading" id="pet-store-loading" hidden>加载中</div>' +
                    '</div>' +
                '</div>' +

                // ── 页面 3：进阶 ──
                '<div class="pet-page" id="pet-page-advance" hidden>' +
                    '<div class="pet-page-header">' +
                        '<button class="pet-page-back" type="button" data-audio-cue="cancel">‹ 返回</button>' +
                        '<img class="pet-advance-avatar" id="pet-advance-avatar" src="assets/pets/pet_locked.png" alt="">' +
                        '<div class="pet-title-block">' +
                            '<h2 class="pet-page-title pet-page-title-sub" id="pet-advance-title">--</h2>' +
                            '<div class="pet-advance-meta" id="pet-advance-meta"></div>' +
                        '</div>' +
                        '<div class="pet-header-spacer"></div>' +
                        '<div class="pet-header-actions">' +
                            '<button class="pet-hdr-btn pet-hdr-deploy" type="button" id="pet-deploy-btn" data-audio-cue="confirm">出战</button>' +
                            '<button class="pet-hdr-btn pet-hdr-restore" type="button" id="pet-restore-btn">恢复体力</button>' +
                            '<button class="pet-hdr-btn pet-hdr-levelup" type="button" id="pet-levelup-btn">强化</button>' +
                            '<button class="pet-hdr-btn pet-hdr-delete" type="button" id="pet-delete-btn" data-tip="永久删除此宠物">删除</button>' +
                        '</div>' +
                    '</div>' +
                    '<div class="pet-page-body">' +
                        '<div class="pet-section">' +
                            '<h3 class="pet-section-title">属性信息</h3>' +
                            '<div class="pet-stats-grid">' +
                                '<div class="pet-stat">' +
                                    '<div class="pet-stat-head"><span class="pet-stat-label">体力</span><span class="pet-stat-value" id="pet-stat-stamina">--</span></div>' +
                                    '<div id="pet-stat-stamina-bar"></div>' +
                                '</div>' +
                                '<div class="pet-stat">' +
                                    '<div class="pet-stat-head"><span class="pet-stat-label">经验</span><span class="pet-stat-value" id="pet-stat-xp">--</span></div>' +
                                    '<div id="pet-stat-xp-bar"></div>' +
                                    '<div class="pet-stat-sub" id="pet-stat-xp-sub"></div>' +
                                '</div>' +
                            '</div>' +
                        '</div>' +
                        '<div class="pet-section">' +
                            '<h3 class="pet-section-title">进阶方案</h3>' +
                            '<div class="pet-promos" id="pet-promotions-list"></div>' +
                        '</div>' +
                    '</div>' +
                '</div>' +

                // ── Toast 队列容器 ──
                '<div class="pet-toast-stack" id="pet-toast-stack"></div>' +

                // ── 删除确认弹窗 ──
                '<div class="pet-confirm-overlay" id="pet-confirm-overlay" hidden>' +
                    '<div class="pet-confirm-dialog">' +
                        '<div class="pet-confirm-icon"></div>' +
                        '<div class="pet-confirm-title">确认删除</div>' +
                        '<div class="pet-confirm-body" id="pet-confirm-body"></div>' +
                        '<div class="pet-confirm-refund" id="pet-confirm-refund"></div>' +
                        '<div class="pet-confirm-footer">' +
                            '<button class="pet-confirm-btn pet-confirm-btn-yes" type="button" id="pet-confirm-yes">确认删除</button>' +
                            '<button class="pet-confirm-btn pet-confirm-btn-no" type="button" id="pet-confirm-no">取消</button>' +
                        '</div>' +
                    '</div>' +
                '</div>' +

            '</div>' + // .pet-panel
            '</div>';  // .pet-scale-shell

        // 缓存引用
        _pageList    = _el.querySelector('#pet-page-list');
        _pageStore   = _el.querySelector('#pet-page-store');
        _pageAdvance = _el.querySelector('#pet-page-advance');
        _gridEl      = _el.querySelector('#pet-grid');
        _gridWrap    = _el.querySelector('#pet-grid-wrap');
        _listEmptyEl = _el.querySelector('#pet-list-empty');
        _selbarEl    = _el.querySelector('#pet-selbar');
        _toastStack  = _el.querySelector('#pet-toast-stack');

        bindStaticEvents();

        container.appendChild(_el);
        return _el;
    }

    function resourcesHtml() {
        return '<div class="pet-resources">' +
            '<span class="pet-resource pet-resource-gold"><span class="pet-resource-label">金币</span><span class="pet-res-val">--</span></span>' +
            '<span class="pet-resource pet-resource-kpoint"><span class="pet-resource-label">K点</span><span class="pet-res-val">--</span></span>' +
        '</div>';
    }

    function sortDropdownHtml() {
        return '<div class="pet-dropdown" id="pet-sort-dd" data-kind="sort">' +
            '<button class="pet-dropdown-btn" type="button"><span class="pet-dd-text">排序 · 出战优先</span><span class="pet-caret">▼</span></button>' +
            '<div class="pet-dropdown-menu">' +
                ddOpt('sort', 'default', '出战优先', true) +
                ddOpt('sort', 'level_desc', '等级 ↓', false) +
                ddOpt('sort', 'level_asc', '等级 ↑', false) +
                ddOpt('sort', 'stamina_asc', '体力 ↑', false) +
                ddOpt('sort', 'name', '名称', false) +
            '</div>' +
        '</div>';
    }

    function filterDropdownHtml() {
        return '<div class="pet-dropdown" id="pet-filter-dd" data-kind="filter">' +
            '<button class="pet-dropdown-btn" type="button"><span class="pet-dd-text">筛选 · 全部</span><span class="pet-caret">▼</span></button>' +
            '<div class="pet-dropdown-menu">' +
                ddOpt('filter', 'all', '全部', true) +
                ddOpt('filter', 'deployed', '仅出战', false) +
                ddOpt('filter', 'resting', '仅休息', false) +
                ddOpt('filter', 'low_stamina', '体力不足', false) +
            '</div>' +
        '</div>';
    }

    function ddOpt(kind, value, label, active) {
        return '<div class="pet-dropdown-opt' + (active ? ' pet-opt-active' : '') + '" data-kind="' + kind + '" data-value="' + value + '">' + escapeHtml(label) + '</div>';
    }

    function selbarHtml() {
        // 差异化：卡片管「出战就绪」（出战/休息/恢复），选中栏管「快捷进阶开关」（淬毒/发型…），
        // 培养页管「深度养成 + 完整文案」（强化/一次性进阶/删除）。故选中栏不再重复出战/恢复。
        return '<div class="pet-selbar pet-selbar-empty" id="pet-selbar">' +
            '<span class="pet-selbar-hint">▾ 选择一只战宠查看快捷进阶</span>' +
            '<img class="pet-selbar-avatar" id="pet-sel-avatar" src="assets/pets/pet_locked.png" alt="">' +
            '<div class="pet-selbar-main">' +
                '<div class="pet-selbar-titlerow">' +
                    '<span class="pet-selbar-name" id="pet-sel-name"></span>' +
                    '<span class="pet-selbar-lv" id="pet-sel-lv"></span>' +
                    '<span id="pet-sel-chips" class="pet-advance-meta"></span>' +
                '</div>' +
                '<div class="pet-selbar-meters" id="pet-sel-meters"></div>' +
            '</div>' +
            '<div class="pet-selbar-quick" id="pet-sel-quick"></div>' +
            '<div class="pet-selbar-actions">' +
                '<button class="pet-act-btn pet-act-detail" type="button" id="pet-sel-detail" data-audio-cue="confirm" data-tip="进阶养成 / 强化 / 删除 / 完整文案"><span class="pet-act-ico">⚙</span><span>培养</span></button>' +
            '</div>' +
        '</div>';
    }

    // ═══════════════════════════════════════════════════════════
    // 静态事件绑定（一次性）
    // ═══════════════════════════════════════════════════════════
    function bindStaticEvents() {
        // 关闭
        var closeBtns = _el.querySelectorAll('.pet-close-btn');
        for (var c = 0; c < closeBtns.length; c++) closeBtns[c].addEventListener('click', requestClose);

        // 返回（商店/进阶共享）
        var backBtns = _el.querySelectorAll('.pet-page-back');
        for (var b = 0; b < backBtns.length; b++) {
            backBtns[b].addEventListener('click', function() { navigateTo('list'); });
        }

        // 开格子（原「领养宠物」位置，与空位卡片调换：扩容入口在工具栏，领养入口在空位卡片）
        _el.querySelector('#pet-expand-btn').addEventListener('click', function(e) { onExpandSlot(e.currentTarget); });

        // 进阶页 header 按钮
        _el.querySelector('#pet-deploy-btn').addEventListener('click', function(e) { onToggleDeploy(e.currentTarget); });
        _el.querySelector('#pet-restore-btn').addEventListener('click', function(e) {
            if (_activePetIdx >= 0 && _pets[_activePetIdx]) onRestoreStamina(_pets[_activePetIdx].slotIndex, e.currentTarget);
        });
        _el.querySelector('#pet-levelup-btn').addEventListener('click', function(e) { onLevelUp(e.currentTarget); });
        _el.querySelector('#pet-delete-btn').addEventListener('click', onDeleteClick);

        // 底部选中栏：仅保留「培养」入口（出战/休息/恢复 已在卡片，不重复；快捷进阶在 #pet-sel-quick 动态绑定）
        _el.querySelector('#pet-sel-detail').addEventListener('click', function() {
            var idx = findPetIndexBySlot(_selectedSlot);
            if (idx >= 0) navigateTo('advance', { petIdx: idx });
        });

        // 删除确认弹窗
        var confirmOverlay = _el.querySelector('#pet-confirm-overlay');
        _el.querySelector('#pet-confirm-yes').addEventListener('click', function(e) { onDeleteConfirm(e.currentTarget); });
        _el.querySelector('#pet-confirm-no').addEventListener('click', function() { confirmOverlay.hidden = true; });
        confirmOverlay.addEventListener('click', function(e) { if (e.target === confirmOverlay) confirmOverlay.hidden = true; });

        // 排序/筛选下拉
        var dds = _el.querySelectorAll('.pet-dropdown');
        for (var d = 0; d < dds.length; d++) {
            var dd = dds[d];
            dd.querySelector('.pet-dropdown-btn').addEventListener('click', (function(node) {
                return function(ev) { ev.stopPropagation(); toggleDropdown(node); };
            })(dd));
            var opts = dd.querySelectorAll('.pet-dropdown-opt');
            for (var o = 0; o < opts.length; o++) {
                opts[o].addEventListener('click', function(ev) {
                    ev.stopPropagation();
                    onSelectDropdown(this.dataset.kind, this.dataset.value, this.textContent);
                });
            }
        }

        // 面板内点击关闭下拉
        _docClickBound = function() { closeAllDropdowns(); };
        _el.addEventListener('click', _docClickBound);

        // 悬浮信息提示：统一走 PanelTooltip（与 K商城/情报/竞技场一致的描边深色注释框），
        // 取代散落的原生 title。委托到 _el：元素带 data-tip 即显示。
        // 注意：禁用按钮（disabled）浏览器不派发鼠标事件 → 委托收不到，故禁用态原因仍保留原生 title 兜底。
        if (typeof PanelTooltip !== 'undefined') {
            _el.addEventListener('mouseover', onTipOver);
            _el.addEventListener('mousemove', onTipMove);
            _el.addEventListener('mouseout', onTipOut);
        }

        // 软禁用按钮（.pet-off）点击拦截：捕获相位先于所有冒泡 action 处理器触发，
        // stopPropagation 一处切断，无需逐个 handler 加 guard。
        _el.addEventListener('click', function(e) {
            var off = (e.target && e.target.closest) ? e.target.closest('.pet-off') : null;
            if (off) { e.stopPropagation(); e.preventDefault(); }
        }, true);
    }

    // ═══════════════════════════════════════════════════════════
    // 悬浮提示（PanelTooltip 委托）
    // ═══════════════════════════════════════════════════════════
    function onTipOver(e) {
        var t = (e.target && e.target.closest) ? e.target.closest('[data-tip]') : null;
        if (!t || t === _tipEl) return;
        _tipEl = t;
        PanelTooltip.showAtMouse(escapeHtml(t.getAttribute('data-tip')), e);
    }
    function onTipMove(e) {
        if (_tipEl) PanelTooltip.followMouse(e);
    }
    function onTipOut(e) {
        if (!_tipEl) return;
        var to = e.relatedTarget;
        if (to && _tipEl.contains(to)) return; // 仍在同一 tip 元素内部移动
        PanelTooltip.hide();
        _tipEl = null;
    }
    // 重渲染/切页/关闭时，悬浮元素可能被移除而 mouseout 不触发 → 主动收起，避免注释框残留
    function hideTip() {
        if (typeof PanelTooltip === 'undefined') return;
        if (_tipEl) { PanelTooltip.hide(); _tipEl = null; }
    }
    // 软禁用：保留可 hover 的真实元素（原生 disabled 不派发鼠标事件 → 收不到 data-tip）。
    // 用 .pet-off 类 + aria-disabled 表达禁用态（CSS 复刻 :disabled 观感）；data-tip 始终生效，
    // 启用/禁用态都走统一的 PanelTooltip 描边框。点击由 bindStaticEvents 的捕获相位统一拦截。
    function softDisable(btn, off, tip) {
        if (!btn) return;
        btn.disabled = false;                       // 不再使用原生 disabled
        btn.classList.toggle('pet-off', !!off);
        if (off) {
            btn.setAttribute('aria-disabled', 'true');
            // 软禁用同时静音：overlay-audio-bindings 的 cue 代理在 document 捕获阶段先于面板
            // 拦截器执行，且只认原生 disabled、不认 .pet-off → 禁用按钮仍会响 confirm/hover。
            // 故摘除 data-audio-cue（暂存到 -off），启用时再还原，不污染原本无 cue 的按钮。
            if (btn.hasAttribute('data-audio-cue')) {
                btn.setAttribute('data-audio-cue-off', btn.getAttribute('data-audio-cue'));
                btn.removeAttribute('data-audio-cue');
            }
        } else {
            btn.removeAttribute('aria-disabled');
            if (btn.hasAttribute('data-audio-cue-off')) {
                btn.setAttribute('data-audio-cue', btn.getAttribute('data-audio-cue-off'));
                btn.removeAttribute('data-audio-cue-off');
            }
        }
        if (tip) btn.setAttribute('data-tip', tip);
        else btn.removeAttribute('data-tip');
    }

    // ═══════════════════════════════════════════════════════════
    // 下拉
    // ═══════════════════════════════════════════════════════════
    function toggleDropdown(node) {
        var open = node.classList.contains('pet-open');
        closeAllDropdowns();
        if (!open) node.classList.add('pet-open');
    }
    function closeAllDropdowns() {
        var dds = _el.querySelectorAll('.pet-dropdown.pet-open');
        for (var i = 0; i < dds.length; i++) dds[i].classList.remove('pet-open');
    }
    function onSelectDropdown(kind, value, label) {
        if (kind === 'sort') _sortMode = value;
        else if (kind === 'filter') _filterMode = value;
        var ddId = kind === 'sort' ? '#pet-sort-dd' : '#pet-filter-dd';
        var dd = _el.querySelector(ddId);
        dd.querySelector('.pet-dd-text').textContent = (kind === 'sort' ? '排序 · ' : '筛选 · ') + stripArrows(label);
        var opts = dd.querySelectorAll('.pet-dropdown-opt');
        for (var i = 0; i < opts.length; i++) opts[i].classList.toggle('pet-opt-active', opts[i].dataset.value === value);
        closeAllDropdowns();
        renderPetGrid();
    }
    function stripArrows(s) { return String(s).replace(/[↑↓]/g, '').trim(); }

    // ═══════════════════════════════════════════════════════════
    // 生命周期
    // ═══════════════════════════════════════════════════════════
    function onOpen(el, initData) {
        _session++;
        _pendingReq = {};
        _busy = false;
        _snapshot = null;
        _pets = [];
        _activePetIdx = -1;
        _selectedSlot = -1;
        _storeCategoryIdx = 0;
        _storeData = [];
        _storeCache = {};
        _firstSnapshot = true;
        _prevGold = null; _prevKpoint = null;
        clearToasts();
        _rosterType = initData && initData.rosterType ? initData.rosterType : _rosterType;

        // 注入 CSS（task-panel 范式：onOpen 确保加载，onClose 移除）
        if (!document.getElementById('pet-panel-css')) {
            _cssLink = document.createElement('link');
            _cssLink.id = 'pet-panel-css';
            _cssLink.rel = 'stylesheet';
            _cssLink.href = 'css/pet_panel.css';
            document.head.appendChild(_cssLink);
        }

        navigateTo('list', null, true);
        showSkeleton();
        updateFitScale();
        bindScaleWatcher();
        requestSnapshot();
        if (!_petLib) requestPetLib();
    }

    function requestClose() {
        if (_busy) return;
        if (window.TeamPanelHost && TeamPanelHost.requestClose) {
            TeamPanelHost.requestClose();
            return;
        }
        Panels.close();
        Bridge.send({ type: 'panel', panel: 'pets', cmd: 'close' });
    }

    function onClose() {
        _pendingReq = {};
        _busy = false;
        _snapshot = null;
        _activePetIdx = -1;
        _selectedSlot = -1;
        clearToasts();
        hideTip();
        unbindScaleWatcher();
        if (_cssLink && _cssLink.parentNode) {
            _cssLink.parentNode.removeChild(_cssLink);
            _cssLink = null;
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 缩放（设计 1024×576 → 窗口自适应；照搬 task-panel）
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
        _el.style.setProperty('--pet-scale', scale.toFixed(4));
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
    // 页面导航（淡入/滑入切换）
    // ═══════════════════════════════════════════════════════════
    function navigateTo(page, params, immediate) {
        if (page === _currentPage && !params && !immediate) return;
        var back = (page === 'list' && _currentPage !== 'list');
        _currentPage = page;
        closeAllDropdowns();
        hideTip();

        _pageList.hidden    = (page !== 'list');
        _pageStore.hidden   = (page !== 'store');
        _pageAdvance.hidden = (page !== 'advance');

        var active = page === 'list' ? _pageList : page === 'store' ? _pageStore : _pageAdvance;
        if (!immediate && active) playPageEnter(active, back);

        switch (page) {
            case 'list':
                updateResourceDisplay(false);
                updateStatusBar();
                renderPetGrid();
                renderSelbar();
                break;
            case 'store':
                renderStoreContent();
                break;
            case 'advance':
                if (params && typeof params.petIdx === 'number') _activePetIdx = params.petIdx;
                renderAdvancePage();
                break;
        }
    }

    function playPageEnter(node, back) {
        node.classList.add(back ? 'pet-page-enter-back' : 'pet-page-enter');
        // 强制 reflow 后移除 → 触发过渡
        void node.offsetWidth;
        requestAnimationFrame(function() {
            node.classList.remove('pet-page-enter');
            node.classList.remove('pet-page-enter-back');
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 通信
    // ═══════════════════════════════════════════════════════════
    Bridge.on('panel_resp', function(data) {
        if (!data || data.panel !== 'pets') return;
        var handler = _pendingReq[data.callId];
        if (handler) {
            delete _pendingReq[data.callId];
            if (typeof handler === 'function') handler(data);
        }
    });

    function sendPanelMsg(cmd, extra, cb) {
        var callId = 'pet_' + (++_reqSeq) + '_' + Date.now();
        if (cb) _pendingReq[callId] = cb;
        var msg = { type: 'panel', panel: 'pets', cmd: cmd, callId: callId };
        if (extra) { for (var k in extra) { if (extra.hasOwnProperty(k)) msg[k] = extra[k]; } }
        Bridge.send(msg);
        return callId;
    }

    function requestPetLib() {
        sendPanelMsg('pet_lib', null, function(data) {
            if (data && data.success && data.petLib) {
                _petLib = data.petLib;
                if (_snapshot) {
                    renderPetGrid(false);
                    renderSelbar(false);
                }
                if (_currentPage === 'advance') renderAdvancePage();
            } else {
                _petLib = [];
                showToast('宠物分类目录不可用，未知项已归入战宠', 'warning');
                if (_snapshot) renderPetGrid(false);
            }
        });
    }

    function requestSnapshot() {
        var snapSession = _session;
        sendPanelMsg('snapshot', null, function(data) {
            if (snapSession !== _session) return;
            if (!data.success) {
                hideSkeleton();
                showToast('获取战宠数据失败：' + (data.error || '未知错误'), 'error');
                return;
            }
            _snapshot = data.snapshot;
            _pets = data.snapshot.pets || [];
            var wasFirst = _firstSnapshot;   // 仅首帧 snapshot 播放卡片入场；后续刷新（升级/进阶/删除/领养/开格子）静默
            _firstSnapshot = false;
            if (!_petLib) {
                showSkeleton();
                return;
            }
            hideSkeleton();
            // 默认选中：保留旧选中（若仍在），否则选首个
            if (findPetBySlot(_selectedSlot) == null) {
                _selectedSlot = _pets.length > 0 ? defaultSelectSlot() : -1;
            }
            updateResourceDisplay(false);
            updateStatusBar();
            renderPetGrid(wasFirst);
            renderSelbar(wasFirst);
            if (_currentPage === 'advance') renderAdvancePage(wasFirst);
        });
    }

    function requestAdoptList(catIdx, cb) {
        var cacheKey = _rosterType + ':' + catIdx;
        if (_storeCache[cacheKey]) {  // 命中缓存：零延迟
            _storeData = _storeCache[cacheKey].adoptable;
            _storeCategories = _storeCache[cacheKey].categories || _storeCategories;
            if (cb) cb(true);
            return;
        }
        sendPanelMsg('adopt_list', { categoryIndex: catIdx, rosterType: _rosterType }, function(data) {
            if (!data.success) {
                showToast('获取领养列表失败：' + (data.error || '超时'), 'error');
                if (cb) cb(false);
                return;
            }
            _storeData = data.adoptable || [];
            if (data.categories) _storeCategories = data.categories;
            if (typeof data.selectedCategoryIndex === 'number') _storeCategoryIdx = data.selectedCategoryIndex;
            cacheKey = _rosterType + ':' + _storeCategoryIdx;
            _storeCache[cacheKey] = { adoptable: _storeData, categories: _storeCategories };
            if (cb) cb(true);
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 列表页渲染
    // ═══════════════════════════════════════════════════════════
    function showSkeleton() {
        if (!_firstSnapshot) return;
        _listEmptyEl.hidden = true;
        var html = '<div class="pet-skeleton-grid">';
        for (var i = 0; i < 8; i++) html += '<div class="pet-skel-card"></div>';
        html += '</div>';
        _gridEl.innerHTML = html;
    }
    function hideSkeleton() {
        var skel = _gridEl.querySelector('.pet-skeleton-grid');
        if (skel) skel.remove();
    }

    function visibleOrder() {
        if (!_pets) _pets = [];
        var order = [];
        for (var oi = 0; oi < _pets.length; oi++) {
            var p = _pets[oi];
            if (rosterTypeForPet(p.petId) !== _rosterType) continue;
            if (_filterMode === 'deployed' && !p.deployed) continue;
            if (_filterMode === 'resting' && p.deployed) continue;
            if (_filterMode === 'low_stamina' && p.stamina > 5) continue;
            order.push(oi);
        }
        order.sort(function(a, b) {
            var pa = _pets[a], pb = _pets[b];
            switch (_sortMode) {
                case 'level_desc': return (pb.level || 0) - (pa.level || 0);
                case 'level_asc':  return (pa.level || 0) - (pb.level || 0);
                case 'stamina_asc': return (pa.stamina || 0) - (pb.stamina || 0);
                case 'name': return String(pa.name).localeCompare(String(pb.name), 'zh');
                default: // 出战优先 → 等级降序
                    if (!!pa.deployed !== !!pb.deployed) return pa.deployed ? -1 : 1;
                    return (pb.level || 0) - (pa.level || 0);
            }
        });
        return order;
    }

    // animate: 入场逐个 stagger（首屏 snapshot / 切页 / 排序筛选时为 true）；
    // 局部更新（出战/恢复/进阶后重拉 snapshot）传 false，避免整列卡片重播入场动画 + 跳动。
    function renderPetGrid(animate) {
        if (animate === undefined) animate = true;
        hideTip();
        _gridEl.innerHTML = '';
        var order = visibleOrder();
        var totalPets = _pets ? _pets.length : 0;

        // 空位数 = 容量 - 已拥有（仅「全部」筛选下展示，避免与状态筛选混淆）
        var emptyCount = (_snapshot && _filterMode === 'all') ? Math.max(0, (_snapshot.maxSlots || 0) - totalPets) : 0;
        // 空态以「当前可见数」为准：筛选后无匹配也要给反馈，而非按未筛选的总数判断
        var showEmpty = (order.length === 0 && emptyCount === 0);
        _listEmptyEl.hidden = !showEmpty;
        if (showEmpty) {
            var txtEl = _listEmptyEl.querySelector('.pet-empty-text');
            // 非「全部」筛选下 emptyCount 恒为 0：此时空态成因是筛选，而非缺栏位——
            // 即便已开 16 个空栏位也不能引导去「开格子」（会诱导玩家白花金币）。
            // 「开格子」引导仅在「全部」筛选且确实无栏位/无宠（maxSlots===0）时出现。
            if (txtEl) txtEl.textContent = (_filterMode === 'all')
                ? '暂无战宠 · 点击「＋ 开格子」开启栏位后即可领养'
                : '没有符合当前筛选条件的战宠';
        }

        for (var k = 0; k < order.length; k++) {
            var i = order[k];
            var card = renderPetCard(_pets[i], i);
            if (animate) card.style.animationDelay = Math.min(k * 0.03, 0.3) + 's';
            else card.classList.add('pet-noanim'); // 静默：卡片不重播入场，内部体力/经验条不重播 grow
            _gridEl.appendChild(card);
        }

        // 全量空位卡片：直观呈现剩余栏位，点击任一空位即进入领养（服务端自动填入下一个空槽）
        for (var e = 0; e < emptyCount; e++) {
            var slot = document.createElement('div');
            slot.className = 'pet-slot-empty';
            if (animate) slot.style.animationDelay = Math.min((order.length + e) * 0.03, 0.36) + 's';
            else slot.classList.add('pet-noanim');
            slot.innerHTML = '<span class="pet-slot-plus">＋</span><span class="pet-slot-label">领养空位</span>';
            slot.addEventListener('click', function() { if (!_busy) navigateTo('store'); });
            _gridEl.appendChild(slot);
        }
    }

    // 出战/恢复后按「筛选 + 排序」双重归属决定刷新粒度：
    //   · 仍在列表且位次未变 → refreshCard 局部刷（不跳动）；
    //   · 被筛选剔除 或 排序位次变化（默认「出战优先」/「体力升序」下出战、恢复都会改变位次）
    //     → renderPetGrid(false) 静默整排，让卡片落到正确位置。
    // 仅查筛选不够：父提交的 petMatchesFilter 漏了排序，卡片会停在旧位置（外部审阅 P2）。
    function reflowCardAfterMutation(slotIndex) {
        var petIdx = findPetIndexBySlot(slotIndex);
        if (petIdx < 0) { renderPetGrid(false); return; }
        var order = visibleOrder();                 // 新状态下的筛选 + 排序结果
        var newPos = -1;
        for (var k = 0; k < order.length; k++) { if (order[k] === petIdx) { newPos = k; break; } }
        if (newPos < 0) { renderPetGrid(false); return; }   // 被当前筛选剔除
        var oldCard = _gridEl.querySelector('.pet-card[data-slot="' + slotIndex + '"]');
        if (!oldCard) { renderPetGrid(false); return; }
        var cards = _gridEl.querySelectorAll('.pet-card');  // 仅宠物卡，空位卡 .pet-slot-empty 不计
        var oldPos = -1;
        for (var j = 0; j < cards.length; j++) { if (cards[j] === oldCard) { oldPos = j; break; } }
        if (oldPos === newPos) refreshCard(slotIndex);      // 位次未变 → 局部刷
        else renderPetGrid(false);                          // 位次变 → 整排重排
    }

    function renderPetCard(pet, petIndex) {
        var card = document.createElement('div');
        card.className = 'pet-card' + (pet.deployed ? ' pet-card-deployed' : '') + (pet.slotIndex === _selectedSlot ? ' pet-card-selected' : '');
        card.dataset.index = petIndex;
        card.dataset.slot = pet.slotIndex;

        var maxSt = pet.maxStamina || 200;
        var staminaFull = pet.stamina >= maxSt;
        var levelLimit = _snapshot ? (_snapshot.levelLimit || 100) : 100;
        var maxLevel = pet.level >= levelLimit;

        var isCombatMap = _snapshot && _snapshot.isCombatMap;
        var deployDisabled = false;
        if (isCombatMap && !pet.deployed) deployDisabled = true;
        else if (pet.stamina <= 0 && !pet.deployed) deployDisabled = true;

        var deployTitle = '';
        if (deployDisabled && !pet.deployed) deployTitle = isCombatMap ? '战斗中无法调整出战阵容' : (pet.stamina <= 0 ? '体力耗尽，无法出战' : '');

        var badges = '';
        if (pet.deployed) badges += '<span class="pet-badge pet-badge-deployed">出战中</span>';
        if (maxLevel) badges += '<span class="pet-badge pet-badge-max">MAX</span>';
        if (pet.stamina <= 0) badges += '<span class="pet-badge pet-badge-exhausted">体力耗尽</span>';

        var xpMeter = maxLevel
            ? meterHtml('经验', buildBar(100, 'pet-bar-xp', 'pet-bar-max'), 'MAX', '')
            : meterHtml('经验', buildBar(pct(pet.xp, pet.xpNeeded), 'pet-bar-xp', ''), Math.round(pct(pet.xp, pet.xpNeeded)) + '%', '');
        var staminaMeter = meterHtml('体力', buildBar(pct(pet.stamina, maxSt), 'pet-bar-stamina', staminaBarMod(pet.stamina)), String(pet.stamina), staminaValClass(pet.stamina));

        card.innerHTML =
            '<span class="pet-card-frame"></span>' + // 4 角 L 框（拟物语汇对齐任务面板）
            '<div class="pet-card-top">' +
                '<img class="pet-card-icon" src="assets/pets/pet_' + pet.petId + '.png" onerror="this.onerror=null;this.src=\'assets/pets/pet_locked.png\'" alt="">' +
                '<div class="pet-card-headinfo">' +
                    '<div class="pet-card-nameline">' +
                        '<span class="pet-card-name">' + escapeHtml(pet.name) + '</span>' +
                        '<span class="pet-card-lv">Lv.' + pet.level + '</span>' +
                    '</div>' +
                    '<div class="pet-card-badges">' + badges + '</div>' +
                '</div>' +
            '</div>' +
            '<div class="pet-card-meters">' + staminaMeter + xpMeter + '</div>' +
            '<div class="pet-card-actions">' +
                '<button class="pet-mini-btn ' + (pet.deployed ? 'pet-mini-btn-rest' : 'pet-mini-btn-deploy') + (deployDisabled ? ' pet-off' : '') + '" type="button" data-act="deploy" data-slot="' + pet.slotIndex + '"' +
                    (deployDisabled ? ' aria-disabled="true"' : '') + (deployTitle ? ' data-tip="' + escapeHtml(deployTitle) + '"' : '') + '>' + (pet.deployed ? '休息' : '出战') + '</button>' +
                '<button class="pet-mini-btn pet-mini-btn-restore" type="button" data-act="restore" data-slot="' + pet.slotIndex + '"' + (staminaFull ? ' disabled' : '') + '>' + (staminaFull ? '体力满' : '恢复') + '</button>' +
            '</div>';

        // 卡片点击 → 选中（高亮 + 底部栏）
        card.addEventListener('click', function() {
            if (_busy) return;
            selectPet(parseInt(this.dataset.slot, 10));
        });
        // 出战/休息
        var deployBtn = card.querySelector('[data-act="deploy"]');
        deployBtn.addEventListener('click', function(e) {
            e.stopPropagation();
            if (this.disabled) return;
            onDeployFromList(parseInt(this.dataset.slot, 10), this);
        });
        // 恢复
        var restoreBtn = card.querySelector('[data-act="restore"]');
        restoreBtn.addEventListener('click', function(e) {
            e.stopPropagation();
            if (this.disabled) return;
            onRestoreStamina(parseInt(this.dataset.slot, 10), this);
        });
        return card;
    }

    function meterHtml(label, bar, val, valClass) {
        return '<div class="pet-meter"><span class="pet-meter-label">' + label + '</span>' + bar +
            '<span class="pet-meter-val ' + (valClass || '') + '">' + val + '</span></div>';
    }

    // 选中战宠（仅列表页）
    function selectPet(slotIndex) {
        _selectedSlot = slotIndex;
        var cards = _gridEl.querySelectorAll('.pet-card');
        for (var i = 0; i < cards.length; i++) {
            cards[i].classList.toggle('pet-card-selected', parseInt(cards[i].dataset.slot, 10) === slotIndex);
        }
        renderSelbar();
    }

    function defaultSelectSlot() {
        // 优先出战中的首个，否则等级最高
        var best = null;
        for (var i = 0; i < _pets.length; i++) {
            var p = _pets[i];
            if (rosterTypeForPet(p.petId) !== _rosterType) continue;
            if (best === null) { best = p; continue; }
            if (!!p.deployed !== !!best.deployed) { if (p.deployed) best = p; continue; }
            if ((p.level || 0) > (best.level || 0)) best = p;
        }
        return best ? best.slotIndex : -1;
    }

    // 局部刷新单张卡片（出战/恢复后，不整页重排）
    function refreshCard(slotIndex) {
        var idx = findPetIndexBySlot(slotIndex);
        if (idx < 0) return;
        var old = _gridEl.querySelector('.pet-card[data-slot="' + slotIndex + '"]');
        if (!old) return;
        var fresh = renderPetCard(_pets[idx], idx);
        fresh.classList.add('pet-noanim'); // 局部替换不重播入场（卡片 + 内部进度条）
        old.parentNode.replaceChild(fresh, old);
    }

    // ═══════════════════════════════════════════════════════════
    // 底部「当前选择」栏
    // ═══════════════════════════════════════════════════════════
    // animate 省略=true（选中/切页时进度条 grow 反馈）；静默刷新（snapshot/出战/恢复/进阶）传 false
    function renderSelbar(animate) {
        hideTip();
        var pet = findPetBySlot(_selectedSlot);
        if (!pet || rosterTypeForPet(pet.petId) !== _rosterType) {
            _selbarEl.classList.add('pet-selbar-empty');
            return;
        }
        _selbarEl.classList.remove('pet-selbar-empty');
        _selbarEl.classList.toggle('pet-noanim', animate === false);

        var avatar = _el.querySelector('#pet-sel-avatar');
        avatar.src = 'assets/pets/pet_' + pet.petId + '.png';
        avatar.onerror = function() { this.onerror = null; this.src = 'assets/pets/pet_locked.png'; };

        _el.querySelector('#pet-sel-name').textContent = pet.name;
        _el.querySelector('#pet-sel-lv').textContent = 'Lv.' + pet.level;

        var chips = '';
        chips += pet.deployed ? '<span class="pet-meta-chip pet-meta-deployed">出战中</span>' : '<span class="pet-meta-chip pet-meta-resting">休息中</span>';
        if (pet.stamina <= 0) chips += '<span class="pet-meta-chip pet-meta-exhausted">体力耗尽</span>';
        _el.querySelector('#pet-sel-chips').innerHTML = chips;

        var maxSt = pet.maxStamina || 200;
        var levelLimit = _snapshot ? (_snapshot.levelLimit || 100) : 100;
        var maxLevel = pet.level >= levelLimit;
        var xpBar = maxLevel
            ? meterHtml('经验', buildBar(100, 'pet-bar-xp', 'pet-bar-max'), 'MAX', '')
            : meterHtml('经验', buildBar(pct(pet.xp, pet.xpNeeded), 'pet-bar-xp', ''), Math.round(pct(pet.xp, pet.xpNeeded)) + '%', '');
        _el.querySelector('#pet-sel-meters').innerHTML =
            meterHtml('体力', buildBar(pct(pet.stamina, maxSt), 'pet-bar-stamina', staminaBarMod(pet.stamina)), pet.stamina + '/' + maxSt, staminaValClass(pet.stamina)) +
            xpBar;

        renderSelbarQuick(pet);
    }

    // 选中栏快捷进阶：仅渲染「已解锁的可反复开关/循环」方案（淬毒、发型…），
    // 一次性进阶 / 强化 / 删除 / 完整文案均在「培养」页，不在此重复。
    function renderSelbarQuick(pet) {
        var box = _el.querySelector('#pet-sel-quick');
        box.innerHTML = '';
        var ss = pet.schemeStatus || {};
        var schemes = _snapshot ? _snapshot.schemes : null;
        var count = 0;
        for (var nm in ss) {
            if (!ss.hasOwnProperty(nm)) continue;
            var st = ss[nm];
            if (!st || !st.repeatable || !st.purchased) continue;
            var tk = st.toggleKind;
            if (tk !== 'binary' && tk !== 'cycle') continue;

            var perMap = schemes && schemes[nm] && schemes[nm].type === '开关' && schemes[nm].gold > 0;
            var pill = document.createElement('button');
            pill.type = 'button';
            pill.className = 'pet-qadv pet-qadv-' + tk + (tk === 'binary' && st.toggleOn ? ' on' : '');
            pill.dataset.scheme = nm;
            if (tk === 'binary') {
                pill.dataset.tip = st.toggleOn
                    ? ('点击关闭「' + nm + '」' + (perMap ? '（省每图 ' + formatMoney(schemes[nm].gold) + ' 金）' : ''))
                    : ('点击开启「' + nm + '」' + (perMap ? '（开启后每图 ' + formatMoney(schemes[nm].gold) + ' 金）' : ''));
                pill.innerHTML = '<span class="pet-qadv-name">' + escapeHtml(nm) + '</span><span class="qsw"></span>';
            } else {
                pill.dataset.tip = '点击切换「' + nm + '」';
                pill.innerHTML = '<span class="pet-qadv-name">' + escapeHtml(nm) + '</span><span class="pet-promo-value-chip">' + escapeHtml(st.toggleValue || '') + '</span>';
            }
            var petSlot = pet.slotIndex;
            pill.addEventListener('click', function(e) {
                e.stopPropagation();
                onAdvance(this.dataset.scheme, this, '已更新', petSlot);
            });
            box.appendChild(pill);
            count++;
        }
        if (count === 0) {
            box.innerHTML = '<span class="pet-qadv-empty">该宠暂无可快捷切换的进阶 · 点「培养」养成</span>';
        }
    }

    function updateResourceDisplay(animate) {
        if (!_snapshot) return;
        setResource('gold', _snapshot.gold, _prevGold, animate);
        setResource('kpoint', _snapshot.kpoint, _prevKpoint, animate);
        _prevGold = _snapshot.gold;
        _prevKpoint = _snapshot.kpoint;
    }
    function setResource(kind, value, prev, animate) {
        var nodes = _el.querySelectorAll('.pet-resource-' + kind);
        var text = formatMoney(value);
        for (var i = 0; i < nodes.length; i++) {
            var valEl = nodes[i].querySelector('.pet-res-val');
            if (valEl) valEl.textContent = text;
            if (animate && prev != null && value !== prev) {
                var node = nodes[i];
                node.classList.remove('pet-resource-bump');
                void node.offsetWidth;
                node.classList.add('pet-resource-bump');
            }
        }
    }

    function updateStatusBar() {
        if (!_snapshot) return;
        var dc = _el.querySelector('#pet-deploy-count');
        var sc = _el.querySelector('#pet-slot-count');
        if (dc) dc.textContent = (_snapshot.currentDeployCount || 0) + '/' + (_snapshot.maxDeploy || 0);
        if (sc) sc.textContent = (_pets.length || 0) + '/' + (_snapshot.maxSlots || 0);
    }

    // ═══════════════════════════════════════════════════════════
    // 进阶页渲染
    // ═══════════════════════════════════════════════════════════
    // animate 省略=true（导航进入时 stat 条与进阶行入场）；静默刷新（snapshot/出战/恢复/进阶）传 false
    function renderAdvancePage(animate) {
        var pet = _pets[_activePetIdx];
        if (!pet) return;
        hideTip();
        _pageAdvance.classList.toggle('pet-noanim', animate === false);

        _el.querySelector('#pet-advance-title').textContent = pet.name + ' Lv.' + pet.level;
        var avatarEl = _el.querySelector('#pet-advance-avatar');
        avatarEl.src = 'assets/pets/pet_' + pet.petId + '.png';
        avatarEl.onerror = function() { this.onerror = null; this.src = 'assets/pets/pet_locked.png'; };

        var metaHtml = pet.deployed
            ? '<span class="pet-meta-chip pet-meta-deployed">出战中</span>'
            : '<span class="pet-meta-chip pet-meta-resting">休息中</span>';
        if (pet.stamina <= 0) metaHtml += '<span class="pet-meta-chip pet-meta-exhausted">体力耗尽</span>';
        _el.querySelector('#pet-advance-meta').innerHTML = metaHtml;

        var maxStamina = pet.maxStamina || 200;
        _el.querySelector('#pet-stat-stamina').textContent = pet.stamina + '/' + maxStamina;
        _el.querySelector('#pet-stat-stamina-bar').innerHTML = buildBar(pct(pet.stamina, maxStamina), 'pet-bar-stamina', staminaBarMod(pet.stamina));

        var levelLimit = _snapshot ? (_snapshot.levelLimit || 100) : 100;
        var isMaxLevel = pet.level >= levelLimit;
        var xpEl = _el.querySelector('#pet-stat-xp');
        var xpBarEl = _el.querySelector('#pet-stat-xp-bar');
        var xpSubEl = _el.querySelector('#pet-stat-xp-sub');
        if (isMaxLevel) {
            xpEl.textContent = '已满级';
            xpBarEl.innerHTML = buildBar(100, 'pet-bar-xp', 'pet-bar-max');
            xpSubEl.textContent = 'Lv.' + pet.level + ' 已达上限';
        } else {
            var curXp = pet.xp || 0, needXp = pet.xpNeeded || 0;
            xpEl.textContent = curXp + '/' + (needXp || '--');
            xpBarEl.innerHTML = buildBar(pct(curXp, needXp), 'pet-bar-xp', '');
            xpSubEl.textContent = needXp > 0 ? ('还需 ' + Math.max(0, needXp - curXp).toLocaleString() + ' 经验升级') : '';
        }

        // 出战按钮
        var deployBtn = _el.querySelector('#pet-deploy-btn');
        deployBtn.textContent = pet.deployed ? '休息' : '出战';
        deployBtn.classList.toggle('pet-hdr-rest', !!pet.deployed);
        if (_snapshot && _snapshot.isCombatMap && !pet.deployed) softDisable(deployBtn, true, '战斗中无法出战');
        else if (pet.stamina <= 0 && !pet.deployed) softDisable(deployBtn, true, '体力不足');
        else softDisable(deployBtn, false, '');

        // 恢复体力
        var restoreBtn = _el.querySelector('#pet-restore-btn');
        if (pet.stamina >= maxStamina) { restoreBtn.textContent = '体力已满'; softDisable(restoreBtn, true, '体力已满'); }
        else if (_snapshot && _snapshot.gold < 1000) { restoreBtn.textContent = '恢复 · 1000金'; softDisable(restoreBtn, true, '金币不足（需1000）'); }
        else { restoreBtn.textContent = '恢复 · 1000金'; softDisable(restoreBtn, false, '消耗1000金币恢复体力至满值'); }

        // 强化
        var levelupBtn = _el.querySelector('#pet-levelup-btn');
        if (pet.level >= levelLimit) { levelupBtn.textContent = '已满级'; softDisable(levelupBtn, true, '已达等级上限'); }
        else {
            var xpNeededForCost = pet.xpNeeded || 0;
            var stoneCost = pet.level * 2 + Math.floor(xpNeededForCost / 10000);
            if (stoneCost < 1) stoneCost = 1;
            levelupBtn.textContent = '强化 · 灵石×' + stoneCost;
            softDisable(levelupBtn, false, '消耗战宠灵石:' + stoneCost + '  |  经验:' + (pet.xp || 0) + '/' + (xpNeededForCost || '--'));
        }

        var deleteBtn = _el.querySelector('#pet-delete-btn');
        deleteBtn.disabled = false;
        deleteBtn.textContent = '删除';

        renderPromotions(pet);
    }

    function getPetLibDef(petId) {
        if (!_petLib) return null;
        for (var i = 0; i < _petLib.length; i++) { if (_petLib[i].id === petId) return _petLib[i]; }
        return null;
    }

    function renderPromotions(pet) {
        var listEl = _el.querySelector('#pet-promotions-list');
        listEl.innerHTML = '';

        var petDef = getPetLibDef(pet.petId);
        if (!petDef || !petDef.promotions || petDef.promotions.length === 0) {
            listEl.innerHTML = '<div class="pet-promo-empty">该宠物暂无进阶方案</div>';
            return;
        }

        for (var i = 0; i < petDef.promotions.length; i++) {
            var schemeName = petDef.promotions[i];
            var scheme = (_snapshot && _snapshot.schemes) ? _snapshot.schemes[schemeName] : null;
            if (!scheme) continue;

            var status = (pet.schemeStatus && pet.schemeStatus[schemeName]) ? pet.schemeStatus[schemeName] : null;
            var isMaxed = status ? !!status.completed : false;
            var levelOk = status ? !status.locked : (pet.level >= (scheme.unlockLevel || 0));
            var repeatable = status ? !!status.repeatable : false;
            var purchased = status ? !!status.purchased : false;
            var freeToggle = repeatable && purchased;
            var canAfford = freeToggle || (_snapshot && _snapshot.gold >= (scheme.gold || 0)) || (scheme.gold || 0) === 0;

            var promoEl = document.createElement('div');
            promoEl.className = 'pet-promo';
            if (isMaxed) promoEl.classList.add('pet-promo-maxed');
            else if (!levelOk) promoEl.classList.add('pet-promo-locked');

            var statusText = '', actionBtn = '';

            if (isMaxed) {
                statusText = '已完成';
                actionBtn = '<button class="pet-promo-btn" disabled>已完成</button>';
            } else if (!levelOk) {
                statusText = (status && status.lockReason === 'prereq') ? '需先完成前置训练' : ('需Lv.' + (scheme.unlockLevel || 0) + '解锁');
                actionBtn = '<button class="pet-promo-btn" disabled>未解锁</button>';
            } else if (freeToggle) {
                var tk = status ? status.toggleKind : null;
                var perMap = (scheme.type === '开关' && scheme.gold > 0);
                if (tk === 'binary') {
                    var on = !!status.toggleOn;
                    if (on) promoEl.classList.add('pet-promo-on');
                    statusText = on
                        ? (perMap ? ('运行中 · 每图消耗 ' + formatMoney(scheme.gold) + '金') : '已启用')
                        : (perMap ? ('已关闭 · 开启后每图 ' + formatMoney(scheme.gold) + '金') : '已停用');
                    actionBtn =
                        '<button class="pet-toggle ' + (on ? 'pet-toggle-on' : 'pet-toggle-off') + '" data-scheme="' + escapeHtml(schemeName) + '" data-tip="点击' + (on ? '关闭' : '开启') + '">' +
                            '<span class="pet-toggle-track"></span>' +
                            '<span class="pet-toggle-label">' + (on ? '运行中' : '已关闭') + '</span>' +
                        '</button>';
                } else if (tk === 'cycle') {
                    statusText = '点击切换';
                    actionBtn = '<span class="pet-promo-value-chip">' + escapeHtml(status.toggleValue || '') + '</span>' +
                        '<button class="pet-promo-btn" data-scheme="' + escapeHtml(schemeName) + '">切换</button>';
                } else {
                    statusText = '可切换';
                    actionBtn = '<button class="pet-promo-btn" data-scheme="' + escapeHtml(schemeName) + '">' + escapeHtml(scheme.buttonText || '执行') + '</button>';
                }
            } else if (!canAfford && scheme.gold > 0) {
                promoEl.classList.add('pet-promo-locked');
                statusText = '金币不足';
                actionBtn = '<button class="pet-promo-btn" data-scheme="' + escapeHtml(schemeName) + '">' + formatMoney(scheme.gold) + '金 ' + escapeHtml(scheme.buttonText || '执行') + '</button>';
            } else {
                statusText = scheme.gold > 0 ? formatMoney(scheme.gold) + '金币' : '免费';
                actionBtn = '<button class="pet-promo-btn" data-scheme="' + escapeHtml(schemeName) + '">' + escapeHtml(scheme.buttonText || '执行') + '</button>';
            }

            promoEl.innerHTML =
                '<div class="pet-promo-info">' +
                    '<div class="pet-promo-name">' + escapeHtml(schemeName) + '</div>' +
                    '<div class="pet-promo-desc">' + escapeHtml((status && status.desc) || scheme.desc || '') + '</div>' +
                    '<div class="pet-promo-cost">' + statusText + '</div>' +
                '</div>' +
                '<div class="pet-promo-action">' + actionBtn + '</div>';

            var actEls = promoEl.querySelectorAll('.pet-promo-action [data-scheme]');
            for (var a = 0; a < actEls.length; a++) {
                actEls[a].addEventListener('click', function(e) {
                    e.stopPropagation();
                    onAdvance(this.dataset.scheme, this);
                });
            }
            listEl.appendChild(promoEl);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 商店页渲染
    // ═══════════════════════════════════════════════════════════
    function renderStoreContent() {
        var loadingEl = _el.querySelector('#pet-store-loading');
        var gridEl = _el.querySelector('#pet-store-grid');
        var emptyEl = _el.querySelector('#pet-store-empty');
        // 命中缓存时不闪 loading
        var cached = !!_storeCache[_rosterType + ':' + _storeCategoryIdx];
        loadingEl.hidden = cached;
        gridEl.hidden = !cached;
        emptyEl.hidden = true;
        if (!cached) _el.querySelector('#pet-store-tabs').innerHTML = '';

        requestAdoptList(_storeCategoryIdx, function(ok) {
            loadingEl.hidden = true;
            if (ok) { renderStoreCategories(); renderStoreGrid(); }
        });
    }

    function renderStoreCategories() {
        var tabsEl = _el.querySelector('#pet-store-tabs');
        tabsEl.innerHTML = '';
        var categories = _storeCategories || [];
        for (var c = 0; c < categories.length; c++) {
            var tab = document.createElement('button');
            var originalIndex = typeof categories[c].index === 'number' ? categories[c].index : c;
            tab.className = 'pet-store-tab' + (originalIndex === _storeCategoryIdx ? ' pet-store-tab-active' : '');
            tab.textContent = categories[c].name;
            tab.dataset.index = originalIndex;
            tab.addEventListener('click', function() {
                var ci = parseInt(this.dataset.index, 10);
                if (ci === _storeCategoryIdx) return;
                _storeCategoryIdx = ci;
                renderStoreContent();
            });
            tabsEl.appendChild(tab);
        }
    }

    function renderStoreGrid() {
        var gridEl = _el.querySelector('#pet-store-grid');
        var emptyEl = _el.querySelector('#pet-store-empty');
        gridEl.innerHTML = '';
        if (!_storeData || _storeData.length === 0) {
            emptyEl.hidden = false; gridEl.hidden = true; return;
        }
        emptyEl.hidden = true; gridEl.hidden = false;

        for (var i = 0; i < _storeData.length; i++) {
            var pet = _storeData[i];
            var effPrice = pet.price;
            if (_snapshot && _snapshot.priceOverrides && _snapshot.priceOverrides[pet.petId] != null) effPrice = _snapshot.priceOverrides[pet.petId];

            var priceText = '';
            if (effPrice > 0) priceText += formatMoney(effPrice) + '金';
            if (pet.kprice > 0) { if (priceText) priceText += ' / '; priceText += formatMoney(pet.kprice) + 'K'; }
            if (!priceText) priceText = '免费';

            var canAdopt = true, btnText = priceText, taskLocked = false;
            if (!_snapshot) canAdopt = false;
            else if (pet.unlockTask > 0 && pet.unlockTask > (_snapshot.playerTask || 0)) { canAdopt = false; taskLocked = true; btnText = '需主线 ' + pet.unlockTask; }
            else if (pet.unlockLevel > _snapshot.playerLevel) { canAdopt = false; btnText = '需Lv.' + pet.unlockLevel; }
            else if (pet.unique && hasPet(pet.petId)) { canAdopt = false; btnText = '已拥有'; }
            else if (_pets.length >= _snapshot.maxSlots) { canAdopt = false; btnText = '宠物栏已满'; }
            else if (effPrice > 0 && _snapshot.gold < effPrice) canAdopt = false;
            else if (pet.kprice > 0 && _snapshot.kpoint < pet.kprice) canAdopt = false;

            var card = document.createElement('div');
            card.className = 'pet-store-card';
            card.style.animationDelay = Math.min(i * 0.025, 0.3) + 's';
            card.innerHTML =
                '<div class="pet-store-name-row">' +
                    '<span class="pet-store-name">' + escapeHtml(pet.name) + '</span>' +
                    (pet.unique ? '<span class="pet-store-unique">唯一</span>' : '') +
                '</div>' +
                (taskLocked
                    ? '<img class="pet-store-icon" src="assets/pets/pet_locked.png" alt="">'
                    : '<img class="pet-store-icon" src="assets/pets/pet_' + pet.petId + '.png" onerror="this.onerror=null;this.src=\'assets/pets/pet_locked.png\'" alt="">') +
                '<button class="pet-store-adopt-btn" type="button" data-pet-id="' + pet.petId + '"' + (canAdopt ? '' : ' disabled') + '>' + escapeHtml(btnText) + '</button>';

            if (canAdopt) {
                card.querySelector('.pet-store-adopt-btn').addEventListener('click', function(e) {
                    e.stopPropagation();
                    onAdopt(parseInt(this.dataset.petId, 10), this);
                });
            }
            gridEl.appendChild(card);
        }
    }

    function rosterTypeForPet(petId) {
        var def = getPetLibDef(petId);
        return def && def.rosterType ? def.rosterType : 'pet';
    }

    function setRosterType(rosterType) {
        _rosterType = rosterType || 'pet';
        _storeCategoryIdx = -1;
        _storeData = [];
        navigateTo('list', null, true);
        if (_snapshot && _petLib) {
            renderPetGrid(false);
            renderSelbar(false);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 操作处理（含按钮 pending）
    // ═══════════════════════════════════════════════════════════
    function onToggleDeploy(btn) {
        if (_busy || _activePetIdx < 0) return;
        var pet = _pets[_activePetIdx];
        if (!pet) return;
        beginOp(btn);
        sendPanelMsg('deploy', { slotIndex: pet.slotIndex }, function(data) {
            endOp(btn);
            if (data.success) {
                pet.deployed = data.deployed;
                if (_snapshot) _snapshot.currentDeployCount = data.currentDeployCount;
                updateStatusBar();
                refreshCard(pet.slotIndex);
                if (_selectedSlot === pet.slotIndex) renderSelbar(false);
                renderAdvancePage(false);
                showToast(pet.deployed ? '已出战' : '已休息', 'success');
            } else {
                showToast('操作失败：' + (data.error || '未知错误'), 'error');
            }
        });
    }

    function onDeployFromList(slotIndex, btn) {
        if (_busy) return;
        var pet = findPetBySlot(slotIndex);
        if (!pet) return;
        beginOp(btn);
        sendPanelMsg('deploy', { slotIndex: slotIndex }, function(data) {
            endOp(btn);
            if (data.success) {
                pet.deployed = data.deployed;
                if (_snapshot) _snapshot.currentDeployCount = data.currentDeployCount;
                updateStatusBar();
                // 出战态变化可能改变筛选归属或排序位次：原位则局部刷（不跳动），否则静默整排
                reflowCardAfterMutation(slotIndex);
                if (_selectedSlot === slotIndex) renderSelbar(false);
                showToast(pet.deployed ? '已出战' : '已休息', 'success');
            } else {
                showToast('操作失败：' + (data.error || '未知错误'), 'error');
            }
        });
    }

    function onRestoreStamina(slotIndex, btn) {
        if (_busy) return;
        var pet = findPetBySlot(slotIndex);
        if (!pet) return;
        if (pet.stamina >= (pet.maxStamina || 200)) return;
        beginOp(btn);
        sendPanelMsg('restore_stamina', { slotIndex: slotIndex }, function(data) {
            endOp(btn);
            if (data.success) {
                pet.stamina = data.stamina;
                if (_snapshot) _snapshot.gold = data.gold;
                updateResourceDisplay(true);
                // 恢复体力可能改变「体力不足」筛选 / 「体力↑」排序位次：同上策略
                reflowCardAfterMutation(slotIndex);
                if (_selectedSlot === slotIndex) renderSelbar(false);
                if (_currentPage === 'advance') renderAdvancePage(false);
                showToast('体力已恢复至 ' + data.stamina, 'success');
            } else {
                var msg = '恢复失败';
                if (data.error === 'insufficient_gold') msg = '金币不足，需要1000金币';
                else if (data.error === 'stamina_full') msg = '体力已满';
                else if (data.error) msg = data.error;
                showToast(msg, 'warn');
            }
        });
    }

    function onLevelUp(btn) {
        if (_busy || _activePetIdx < 0) return;
        var pet = _pets[_activePetIdx];
        if (!pet) return;
        beginOp(btn);
        sendPanelMsg('level_up', { slotIndex: pet.slotIndex }, function(data) {
            endOp(btn);
            if (data.success) {
                requestSnapshot();   // 等级变化牵动门槛，需重拉
                showToast('战宠升级！战宠灵石 -' + data.stoneCost, 'success');
            } else {
                var msg = '升级失败';
                if (data.error === 'level_maxed') msg = '已达等级上限';
                else if (data.error === 'insufficient_stones') msg = '战宠灵石不足，需要' + (data.cost || '?') + '个';
                else if (data.error) msg = data.error;
                showToast(msg, 'warn');
            }
        });
    }

    function onDeleteClick() {
        if (_busy || _activePetIdx < 0) return;
        var pet = _pets[_activePetIdx];
        if (!pet) return;
        var xpNeeded = pet.xpNeeded || 0;
        var refund = Math.floor(Math.sqrt(pet.level) * 0.8 * xpNeeded / 10000);
        if (isNaN(refund) || refund < 0) refund = 0;
        _el.querySelector('#pet-confirm-body').innerHTML =
            '确认永久删除 <strong>' + escapeHtml(pet.name) + ' (Lv.' + pet.level + ')</strong> 吗？此操作不可撤销。';
        _el.querySelector('#pet-confirm-refund').textContent = '返还战宠灵石：' + refund + ' 个';
        _el.querySelector('#pet-confirm-overlay').hidden = false;
    }

    function onDeleteConfirm(btn) {
        if (_busy || _activePetIdx < 0) { _el.querySelector('#pet-confirm-overlay').hidden = true; return; }
        var pet = _pets[_activePetIdx];
        if (!pet) { _el.querySelector('#pet-confirm-overlay').hidden = true; return; }
        beginOp(btn);
        sendPanelMsg('delete', { slotIndex: pet.slotIndex }, function(data) {
            endOp(btn);
            _el.querySelector('#pet-confirm-overlay').hidden = true;
            if (data.success) {
                var refundText = data.stoneRefund > 0 ? '，返还战宠灵石 ' + data.stoneRefund + ' 个' : '';
                _selectedSlot = -1;
                showToast('已删除战宠' + refundText, 'success');
                requestSnapshot();
                navigateTo('list');
            } else {
                showToast('删除失败：' + (data.error || '未知错误'), 'error');
            }
        });
    }

    // slotIndex 省略时取培养页当前宠（_activePetIdx）；选中栏快捷开关显式传 _selectedSlot
    function onAdvance(schemeName, btn, okMsg, slotIndex) {
        if (_busy) return;
        var slot = (slotIndex != null) ? slotIndex : (_activePetIdx >= 0 && _pets[_activePetIdx] ? _pets[_activePetIdx].slotIndex : -1);
        var pet = findPetBySlot(slot);
        if (!pet) return;
        beginOp(btn);
        sendPanelMsg('advance', { slotIndex: pet.slotIndex, scheme: schemeName }, function(data) {
            endOp(btn);
            if (data.success) {
                if (_snapshot) { _snapshot.gold = data.gold; _snapshot.kpoint = data.kpoint; }
                updateResourceDisplay(true);
                requestSnapshot();
                showToast(okMsg || '进阶成功！', 'success');
            } else {
                showToast('进阶失败：' + (data.reason || data.error || '未知错误'), 'warn');
            }
        });
    }

    function onAdopt(petId, btn) {
        if (_busy) return;
        beginOp(btn);
        sendPanelMsg('adopt', { petId: petId }, function(data) {
            endOp(btn);
            if (data.success) {
                if (_snapshot) { _snapshot.gold = data.gold; _snapshot.kpoint = data.kpoint; }
                _storeCache = {};   // 领养改变拥有态/价格，失效缓存
                updateResourceDisplay(true);
                requestSnapshot();
                showToast('领养成功！', 'success');
                navigateTo('list');
            } else {
                showToast('领养失败：' + (data.reason || data.error || '未知错误'), 'warn');
            }
        });
    }

    function onExpandSlot(btn) {
        if (_busy) return;
        beginOp(btn);
        sendPanelMsg('expand_slot', null, function(data) {
            endOp(btn);
            if (data.success) {
                if (_snapshot) { _snapshot.gold = data.gold; _snapshot.maxSlots = data.maxSlots; }
                updateResourceDisplay(true);
                updateStatusBar();
                renderPetGrid();
                showToast('宠物栏已扩充至 ' + data.maxSlots, 'success');
            } else {
                var msg = '扩充失败';
                if (data.error === 'max_slots_reached') msg = '已达最大格子数（' + (data.maxSlots || '') + '）';
                else if (data.error === 'insufficient_gold' || data.error === '金币不足') msg = '金币不足，无法开格子';
                else if (data.error) msg = '扩充失败：' + data.error;
                showToast(msg, 'warn');
            }
        });
    }

    // 操作锁 + 按钮 pending
    function beginOp(btn) {
        _busy = true;
        if (_el) _el.querySelector('.pet-panel').classList.add('pet-busy');
        if (btn) btn.classList.add('pet-btn-pending');
    }
    function endOp(btn) {
        _busy = false;
        if (_el) _el.querySelector('.pet-panel').classList.remove('pet-busy');
        if (btn) btn.classList.remove('pet-btn-pending');
    }

    // ═══════════════════════════════════════════════════════════
    // Toast 队列（三色，最多 3 条）
    // ═══════════════════════════════════════════════════════════
    function showToast(msg, type) {
        if (!_toastStack) return;
        var t = document.createElement('div');
        t.className = 'pet-toast' + (type ? ' pet-toast-' + type : '');
        t.textContent = msg;
        _toastStack.appendChild(t);
        _toasts.push(t);
        while (_toasts.length > 3) {
            var old = _toasts.shift();
            if (old && old.parentNode) old.parentNode.removeChild(old);
        }
        var self = t;
        setTimeout(function() { dismissToast(self); }, 2600);
    }
    function dismissToast(t) {
        if (!t || !t.parentNode) return;
        t.classList.add('pet-toast-out');
        setTimeout(function() {
            if (t.parentNode) t.parentNode.removeChild(t);
            var idx = _toasts.indexOf(t);
            if (idx >= 0) _toasts.splice(idx, 1);
        }, 250);
    }
    function clearToasts() {
        if (_toastStack) _toastStack.innerHTML = '';
        _toasts = [];
    }

    // ═══════════════════════════════════════════════════════════
    // 工具
    // ═══════════════════════════════════════════════════════════
    function findPetBySlot(slot) {
        if (slot < 0) return null;
        for (var i = 0; i < _pets.length; i++) { if (_pets[i].slotIndex === slot) return _pets[i]; }
        return null;
    }
    function findPetIndexBySlot(slot) {
        if (slot < 0) return -1;
        for (var i = 0; i < _pets.length; i++) { if (_pets[i].slotIndex === slot) return i; }
        return -1;
    }
    function hasPet(petId) {
        for (var i = 0; i < _pets.length; i++) { if (_pets[i].petId === petId) return true; }
        return false;
    }

    function formatMoney(n) {
        if (n == null || isNaN(n)) return '--';
        n = Number(n);
        if (n >= 100000000) return (n / 100000000).toFixed(2) + '亿';
        if (n >= 10000) return (n / 10000).toFixed(1) + '万';
        return n.toLocaleString ? n.toLocaleString() : String(n);
    }
    function pct(cur, max) {
        cur = Number(cur) || 0; max = Number(max) || 0;
        if (max <= 0) return 0;
        var p = (cur / max) * 100;
        return p < 0 ? 0 : (p > 100 ? 100 : p);
    }
    function buildBar(percent, baseClass, modifier) {
        var cls = 'pet-bar ' + baseClass + (modifier ? ' ' + modifier : '');
        return '<div class="' + cls + '"><div class="pet-bar-fill" style="--w:' + percent.toFixed(1) + '%"></div></div>';
    }
    function staminaBarMod(stamina) {
        if (stamina <= 0) return 'pet-bar-depleted';
        if (stamina <= 5) return 'pet-bar-low';
        return '';
    }
    function staminaValClass(stamina) {
        if (stamina <= 0) return 'pet-stamina-depleted';
        if (stamina <= 5) return 'pet-stamina-low';
        return '';
    }
    function escapeHtml(s) {
        if (s == null) return '';
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    // 测试/调试用
    if (typeof window !== 'undefined') {
        window.PetPanel = {
            getState: function() {
                return { page: _currentPage, pets: _pets.length, selected: _selectedSlot, busy: _busy, sort: _sortMode, filter: _filterMode };
            }
        };
    }
    window.PetTeamController = {
        create: createDOM,
        onOpen: onOpen,
        onClose: onClose,
        requestClose: requestClose,
        resetToList: function() { navigateTo('list', null, true); },
        setRosterType: setRosterType,
        isBusy: function() { return _busy; }
    };
})();
