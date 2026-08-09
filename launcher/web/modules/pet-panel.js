/**
 * PetTeamController — 伙伴 / 战宠 / 机械三 tab 统一的战队双栏工作台控制器（Phase B 重写）。
 *
 * 视图地图（设计 §3.1，profile = catalog-decision）：
 *  - roster（默认）：左栏名册网格（EntityTile 卡：体力 + 经验双 meter、排序 / 筛选、
 *    「＋ 领养」入口、世界内候选卡置顶），
 *    右栏决策面（详情 / 出战 · 休息 / 恢复体力 / 快捷进阶开关 / 「培养 →」）；
 *  - store（领养）：左栏分类 tabs + 可领养目录 + 骨架，右栏候选预览 + CommitBar（唯一主 CTA 确认领养）；
 *  - advance（培养）：SecondaryPage 覆盖 body（两栏：左栏 属性信息 / 战斗属性（窄栏紧凑排布，
 *    旧 SWF 缺 combat 字段仍整块隐藏），右栏 进阶方案独占纵向滚动列；出战 · 恢复 · 强化 · 删除在 header）。
 *
 * 协议零改动（AS2 为数据权威，JS 纯展示层）：panel='pets'；cmd 全集保持
 * snapshot / pet_lib / adopt_list / adopt / deploy / restore_stamina / level_up /
 * delete / advance / expand_slot，以及世界内招募通道 world_adopt；
 * callId 请求-响应、_pendingReq、_session 迟到回包守卫语义原样保留。
 */
(function() {
    'use strict';

    // ── 依赖 fail-fast：缺共享层直接报错，不做半初始化 ──
    if (typeof TeamShared === 'undefined'
            || typeof Workbench === 'undefined'
            || typeof WorkbenchComponents === 'undefined'
            || typeof PanelScale === 'undefined'
            || typeof EnemyPortraits === 'undefined') {
        throw new Error('pet-panel.js 需要先加载 team/team-shared.js、workbench 共享层、panel-scale.js 与 portrait-resolver.js');
    }

    var DESIGN_W = 1024;
    var DESIGN_H = 576;
    var RESTORE_COST = 1000;        // 恢复体力展示花费（权威扣费在 AS2）
    var CANDIDATE_SLOT = -2;        // 世界内招募候选的选中哨兵（真实 slotIndex ≥ 0，-1 为未选中）

    var ROSTER_META = {
        partner:    { noun: '伙伴', measure: '位' },
        pet:        { noun: '战宠', measure: '只' },
        mechanical: { noun: '机械', measure: '台' }
    };
    var SORT_OPTIONS = [
        { value: 'default',     label: '出战优先' },
        { value: 'level_desc',  label: '等级 ↓' },
        { value: 'level_asc',   label: '等级 ↑' },
        { value: 'stamina_asc', label: '体力 ↑' },
        { value: 'name',        label: '名称' }
    ];
    var FILTER_OPTIONS = [
        { value: 'all',         label: '全部' },
        { value: 'deployed',    label: '仅出战' },
        { value: 'resting',     label: '仅休息' },
        { value: 'low_stamina', label: '体力不足' }
    ];

    // ── 状态 ──
    var _el = null, _scaleEl = null, _scaleHandle = null;
    var _shell = null, _helpAction = null, _density = null, _densityToggle = null;
    var _tooltipScope = null;
    var _sortDropdown = null, _filterDropdown = null;
    var _closeButton = null;

    var _pets = [];
    var _snapshot = null;
    var _petLib = null;
    var _pendingReq = {};
    var _reqSeq = 0;
    var _session = 0;
    var _busy = false;
    var _rosterType = 'partner';
    var _hireCandidate = null;      // 世界内招募候选（NPC 处，置顶在 roster 顶部的卡；null=普通管理）
    var _sortMode = 'default';
    var _filterMode = 'all';
    var _firstSnapshot = true;
    var _loadError = '';

    var _view = 'roster';           // roster | store
    var _selectedSlot = -1;         // -1 未选中；CANDIDATE_SLOT 候选；否则 slotIndex
    var _storeCategoryIdx = 0;
    var _storeData = [];
    var _storeCategories = [];
    var _storeCache = {};           // 分类缓存：rosterType:catIdx → { adoptable, categories }
    var _adoptPetId = null;         // store 右栏选中候选
    var _commitError = null;        // 领养失败的可读原因（truthy 期间 renderStorePreview 保留 CommitBar error 投影）
    var _adoptListSeq = 0;          // adopt_list 请求序号：同 session 连切分类时只接受最新回包

    // DOM refs / 视图对象
    var _rosterLeftRoot = null, _rosterRightRoot = null;
    var _storeLeftRoot = null, _storeRightRoot = null;
    var _gridEl = null, _rosterScrollEl = null, _detailEl = null;
    var _storeTabsEl = null, _storeGridEl = null, _storeScrollEl = null, _storePreviewEl = null;
    var _rosterL = null, _rosterR = null, _storeL = null, _storeR = null;
    var _commitBar = null;
    var _advancePage = null, _advanceBodyEl = null, _advanceTitleEl = null, _advanceChipsEl = null;
    var _advanceLeftEl = null, _advanceRightEl = null;
    var _advanceSlot = -1;

    function meta() { return ROSTER_META[_rosterType] || ROSTER_META.pet; }

    // ═══════════════════════════════════════════════════════════
    // DOM 创建 / 生命周期
    // ═══════════════════════════════════════════════════════════
    function createDOM(container) {
        _el = document.createElement('div');
        _el.className = 'team-child team-pet-child';
        _scaleEl = document.createElement('div');
        _scaleEl.className = 'panel-scale-shell team-pet-scale-shell';
        _el.appendChild(_scaleEl);
        container.appendChild(_el);
        return _el;
    }

    function onOpen(el, initData) {
        initData = initData || {};
        _session++;
        _rosterType = initData.rosterType || _rosterType;
        _hireCandidate = initData.hireCandidate || null;
        _pendingReq = {};
        _busy = false;
        _snapshot = null;
        _pets = [];
        _selectedSlot = _hireCandidate ? CANDIDATE_SLOT : -1;
        _adoptPetId = null;
        _commitError = null;
        _storeCategoryIdx = 0;
        _storeData = [];
        _storeCategories = [];
        _storeCache = {};
        _firstSnapshot = true;
        _loadError = '';

        teardownView(false);
        _tooltipScope = (typeof PanelTooltip !== 'undefined' && PanelTooltip && PanelTooltip.createScope)
            ? PanelTooltip.createScope('team-pet') : null;
        buildShell(initData);
        buildRosterViews();
        _shell.mountInitial(_rosterL, _rosterR);
        if (_scaleHandle) { _scaleHandle.detach(); _scaleHandle = null; }
        _scaleHandle = PanelScale.attach(_scaleEl, DESIGN_W, DESIGN_H);
        _shell.setStatus('读取中', Workbench.WorkbenchState.LOADING);
        renderRosterGrid();
        renderDetail();
        requestSnapshot();
        if (!_petLib) requestPetLib();
    }

    function onClose() {
        _pendingReq = {};
        _busy = false;
        _snapshot = null;
        _pets = [];
        _selectedSlot = -1;
        teardownView(true);
    }

    function requestClose() {
        if (guardBusy()) return;
        if (window.TeamPanelHost && TeamPanelHost.requestClose) {
            TeamPanelHost.requestClose();
            return;
        }
        Panels.close();
        Bridge.send({ type: 'panel', panel: 'pets', cmd: 'close' });
    }

    // 视图 teardown：销毁壳 / 组件 / tooltip 域，清空 DOM 引用；幂等。
    function teardownView(detachScale) {
        if (_sortDropdown) { _sortDropdown.destroy(); _sortDropdown = null; }
        if (_filterDropdown) { _filterDropdown.destroy(); _filterDropdown = null; }
        if (_density) { _density.destroy(); _density = null; }
        _densityToggle = null;
        if (_advancePage) { _advancePage.destroy(); _advancePage = null; }
        _advanceBodyEl = null; _advanceTitleEl = null; _advanceChipsEl = null; _advanceSlot = -1;
        _advanceLeftEl = null; _advanceRightEl = null;
        if (_commitBar) { _commitBar.destroy(); _commitBar = null; }
        if (_helpAction) { _helpAction.destroy(); _helpAction = null; }
        if (_tooltipScope) { _tooltipScope.dispose(); _tooltipScope = null; }
        if (_shell) { _shell.destroy(); _shell = null; }
        _closeButton = null;
        _rosterL = null; _rosterR = null; _storeL = null; _storeR = null;
        _rosterLeftRoot = null; _rosterRightRoot = null;
        _storeLeftRoot = null; _storeRightRoot = null;
        _gridEl = null; _rosterScrollEl = null; _detailEl = null;
        _storeTabsEl = null; _storeGridEl = null; _storeScrollEl = null; _storePreviewEl = null;
        _view = 'roster';
        if (_scaleEl) Workbench.clearElement(_scaleEl);
        if (detachScale !== false && _scaleHandle) { _scaleHandle.detach(); _scaleHandle = null; }
    }

    // ═══════════════════════════════════════════════════════════
    // 壳与 header（tab 条 → 密度切换 → 帮助 → 关闭）
    // ═══════════════════════════════════════════════════════════
    function buildShell(initData) {
        var noun = meta().noun;
        _shell = new Workbench.DualPaneShell({
            profile: 'catalog-decision',
            title: noun + '管理',
            subtitle: '',
            status: '读取中',
            leftLabel: '名册',
            rightLabel: '决策',
            flowLabel: noun,
            eyebrow: '战队',
            // 官方 opt-out（WB129 合规）：pane 自带单行控件条承担标签职能，关闭壳级 L/R marker
            slotMarkers: false
        });
        var root = _shell.getRoot();
        root.classList.add('team-workbench');
        root.setAttribute('data-workbench-skin', 'team');
        root.setAttribute('data-team-roster', _rosterType);
        _scaleEl.appendChild(root);

        // header actions 顺序固定：tab 条（team 壳层传入，必须是第一个）→ 密度切换 → 帮助 → 关闭
        if (initData.tabNav) _shell.addHeaderAction(initData.tabNav);

        _density = new Workbench.GridDensityController({ panelId: 'team-pet', compactClass: 'team-grid-compact' });
        _densityToggle = _density.createToggle();
        _densityToggle.setAttribute('aria-label', noun + '卡片布局');
        var densityLabel = _densityToggle.querySelector('.item-grid-mode-label');
        if (densityLabel) densityLabel.textContent = '布局';
        _shell.addHeaderAction(_densityToggle);

        _helpAction = new WorkbenchComponents.HelpAction({ shell: _shell, spec: helpSpec() });

        _closeButton = button('×', 'workbench-close-btn', requestClose);
        _closeButton.setAttribute('aria-label', '关闭战队面板');
        _closeButton.setAttribute('data-audio-cue', 'cancel');
        _shell.addHeaderAction(_closeButton);
    }

    function helpSpec() {
        var noun = meta().noun;
        return {
            kind: 'workbench-help',
            kicker: '战队',
            title: noun + '管理帮助',
            ariaLabel: noun + '管理帮助',
            message: '名册支持排序（出战优先 / 等级 / 体力 / 名称）与筛选（全部 / 仅出战 / 仅休息 / 体力不足）。'
                + '点选卡片后，右栏可出战 · 休息、恢复体力、切换已解锁的快捷进阶（淬毒 / 发型等）；'
                + '「培养 →」进入进阶页做强化、方案进阶与删除。完整 / 紧凑布局同时作用于名册与领养目录。',
            detail: '「＋ 领养' + noun + '」打开领养目录：左侧按分类浏览，右侧确认价格与余额后提交唯一「确认领养」。'
                + '条件不满足（主线 / 等级 / 唯一 / 栏位 / 余额）会写明原因且不可提交。'
                + '世界内招募候选以「候选」卡置顶，契约金满足即可在右栏确认招募。'
        };
    }

    // ═══════════════════════════════════════════════════════════
    // 视图对象（壳 view host 协议）
    // ═══════════════════════════════════════════════════════════
    function simpleView(key, kind, slots, root, renderer) {
        return {
            instanceKey: key,
            instancePolicy: 'singletonByBinding',
            viewKind: kind,
            allowedSlots: slots,
            mount: function(container) { container.appendChild(root); },
            unmount: function() { if (root.parentNode) root.parentNode.removeChild(root); },
            render: renderer
        };
    }

    function buildRosterViews() {
        var noun = meta().noun;

        _rosterLeftRoot = document.createElement('div');
        _rosterLeftRoot.className = 'workbench-view team-pet-view';
        // Phase F 排版收紧 + Phase G1 壳级 marker opt-out：pane 内不再重复大标题，
        // chrome 收敛为单行控件条（排序 / 筛选 / 领养入口 / 扩容）
        var paneHeader = document.createElement('div');
        paneHeader.className = 'team-pane-header';
        var tools = document.createElement('div');
        tools.className = 'team-pane-tools';

        _sortDropdown = TeamShared.createDropdown({
            label: '排序',
            options: SORT_OPTIONS,
            activeValue: _sortMode,
            ariaLabel: noun + '名册排序',
            onSelect: function(value) { _sortMode = value; renderRosterGrid(); }
        });
        tools.appendChild(_sortDropdown.root);
        _filterDropdown = TeamShared.createDropdown({
            label: '筛选',
            options: FILTER_OPTIONS,
            activeValue: _filterMode,
            ariaLabel: noun + '名册筛选',
            onSelect: function(value) { _filterMode = value; renderRosterGrid(); }
        });
        tools.appendChild(_filterDropdown.root);

        var adoptEntry = button('＋ 领养' + noun, 'team-pane-btn team-goto-store', enterStore);
        adoptEntry.setAttribute('data-tone', 'primary');
        adoptEntry.setAttribute('aria-label', '打开领养' + noun + '目录');
        tools.appendChild(adoptEntry);
        var expandBtn = button('扩容', 'team-pane-btn team-expand-slot', function() { onExpandSlot(this); });
        expandBtn.setAttribute('data-tone', 'primary');
        expandBtn.title = '花费金币扩充一个' + noun + '栏位';
        expandBtn.setAttribute('aria-label', '扩充' + noun + '栏位');
        tools.appendChild(expandBtn);
        paneHeader.appendChild(tools);
        _rosterLeftRoot.appendChild(paneHeader);

        _rosterScrollEl = document.createElement('div');
        _rosterScrollEl.className = 'team-scroll team-pet-roster-scroll';
        _rosterScrollEl.setAttribute('data-scroll-region', '');
        _gridEl = document.createElement('div');
        _gridEl.className = 'team-entity-grid team-pet-grid';
        // 名册网格是单选列表容器：卡内嵌「出战/恢复」真按钮，APG 明确 listbox/option 不包容
        // 嵌套交互控件——投 role=list + 卡 role=listitem（选中态 aria-current，见 fixupCardA11y）；
        // 空位 tile 是无语义真 button
        _gridEl.setAttribute('role', 'list');
        _gridEl.setAttribute('aria-label', noun + '名册');
        _rosterScrollEl.appendChild(_gridEl);
        _rosterLeftRoot.appendChild(_rosterScrollEl);
        _density.register(_gridEl);

        _rosterRightRoot = document.createElement('div');
        _rosterRightRoot.className = 'workbench-view team-pet-view';
        _detailEl = document.createElement('div');
        _detailEl.className = 'team-scroll team-pet-detail';
        _detailEl.setAttribute('data-scroll-region', '');
        _rosterRightRoot.appendChild(_detailEl);

        _rosterL = simpleView('team-pet:roster', 'catalog', ['L'], _rosterLeftRoot, renderRosterGrid);
        _rosterR = simpleView('team-pet:decision', 'detail', ['R'], _rosterRightRoot, renderDetail);
    }

    function buildStoreViews() {
        var noun = meta().noun;

        _storeLeftRoot = document.createElement('div');
        _storeLeftRoot.className = 'workbench-view team-pet-view';
        // Phase F 排版收紧：store 页头并条——返回钮 + 分类 tabs 同一行 chrome（去掉大标题）
        var paneHeader = document.createElement('div');
        paneHeader.className = 'team-pane-header';
        var backBtn = button('‹ 返回名册', 'team-pane-btn team-back-roster', backToRoster);
        backBtn.setAttribute('aria-label', '返回' + noun + '名册');
        paneHeader.appendChild(backBtn);
        _storeTabsEl = document.createElement('div');
        _storeTabsEl.className = 'team-store-tabs';
        _storeTabsEl.setAttribute('role', 'group');
        _storeTabsEl.setAttribute('aria-label', '领养分类');
        paneHeader.appendChild(_storeTabsEl);
        _storeLeftRoot.appendChild(paneHeader);

        _storeScrollEl = document.createElement('div');
        _storeScrollEl.className = 'team-scroll team-store-scroll';
        _storeScrollEl.setAttribute('data-scroll-region', '');
        _storeGridEl = document.createElement('div');
        _storeGridEl.className = 'team-entity-grid team-store-grid';
        // 同名册网格（外审二轮 P2-4）：listbox→list，目录卡 role=listitem
        _storeGridEl.setAttribute('role', 'list');
        _storeGridEl.setAttribute('aria-label', '领养' + noun + '目录');
        _storeScrollEl.appendChild(_storeGridEl);
        _storeLeftRoot.appendChild(_storeScrollEl);
        // 领养目录与名册共享同一持久化密度状态。store 是懒创建视图，register
        // 会立即套用当前 mode，随后顶部完整/紧凑切换也会同步更新两个网格。
        _density.register(_storeGridEl);

        _storeRightRoot = document.createElement('div');
        _storeRightRoot.className = 'workbench-view team-pet-view team-store-decision';
        _storePreviewEl = document.createElement('div');
        _storePreviewEl.className = 'team-scroll team-store-preview';
        _storePreviewEl.setAttribute('data-scroll-region', '');
        _storeRightRoot.appendChild(_storePreviewEl);
        _commitBar = new WorkbenchComponents.CommitBar({
            label: '确认领养',
            status: '选择左侧目标后确认',
            disabled: true,
            onCommit: onCommitAdopt
        });
        _commitBar.primaryButton.setAttribute('data-tone', 'primary');
        _commitBar.mount(_storeRightRoot);

        _storeL = simpleView('team-pet:store-catalog', 'catalog', ['L'], _storeLeftRoot, renderStoreGrid);
        _storeR = simpleView('team-pet:store-commit', 'detail', ['R'], _storeRightRoot, renderStorePreview);
    }

    // ═══════════════════════════════════════════════════════════
    // 通信（协议零改动：panel='pets' + callId 请求-响应 + session 守卫）
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
                // snapshot 先到、pet_lib 后到时由本回调收尾渲染（与 snapshot 路径同一就绪序列）
                if (_snapshot) renderAfterDataReady();
            } else {
                _petLib = [];
                TeamShared.toast('宠物分类目录不可用，未知项已归入战宠');
                if (_snapshot) renderAfterDataReady();
            }
        });
    }

    function requestSnapshot() {
        var snapSession = _session;
        sendPanelMsg('snapshot', null, function(data) {
            if (snapSession !== _session) return;
            if (!data.success) {
                _loadError = '获取' + meta().noun + '数据失败：' + (data.error || '未知错误');
                if (_shell) _shell.setStatus('读取失败', Workbench.WorkbenchState.ERROR);
                TeamShared.toast(_loadError);
                renderRosterGrid();
                return;
            }
            _snapshot = data.snapshot;
            _pets = data.snapshot.pets || [];
            // 领养失败的对账回包：此刻数据才真的重新同步，给保留中的 CommitBar error 补后缀
            if (_commitError && _commitBar && _view === 'store') {
                _commitBar.update({ busy: false, state: 'error',
                    status: _commitError + ' · 数据已重新同步，请重新确认' });
            }
            if (!_petLib) { renderRosterGrid(); return; }   // 等 pet_lib 收尾（骨架保持）
            renderAfterDataReady();
        });
    }

    // snapshot + petLib 双数据就绪后的统一渲染序列（snapshot 回调与迟到的 pet_lib 回调共用）
    function renderAfterDataReady() {
        _firstSnapshot = false;
        _loadError = '';
        if (_selectedSlot !== CANDIDATE_SLOT) {
            var sel = findPetBySlot(_selectedSlot);
            if (!sel || rosterTypeForPet(sel.petId) !== _rosterType) {
                _selectedSlot = _hireCandidate ? CANDIDATE_SLOT : defaultSelectSlot();
            }
        }
        updateHeaderMetrics();
        if (_shell) _shell.setStatus('就绪', Workbench.WorkbenchState.READY);
        renderRosterGrid();
        renderDetail();
        renderAdvance();
        if (_view === 'store') { renderStoreGrid(); renderStorePreview(); }
    }

    function requestAdoptList(catIdx, cb) {
        var cacheKey = _rosterType + ':' + catIdx;
        var reqSession = _session;
        // 乱序回包守卫：连切分类时同 session 可能有多个请求在飞（缓存命中也自增序号），
        // 只接受最新一次写回 _storeData / _storeCategoryIdx，迟到回包直接丢弃
        var reqAdoptSeq = ++_adoptListSeq;
        if (_storeCache[cacheKey]) {  // 命中缓存：零延迟
            _storeData = _storeCache[cacheKey].adoptable;
            _storeCategories = _storeCache[cacheKey].categories || _storeCategories;
            if (cb) cb(true);
            return;
        }
        sendPanelMsg('adopt_list', { categoryIndex: catIdx, rosterType: _rosterType }, function(data) {
            if (reqSession !== _session) return;
            if (reqAdoptSeq !== _adoptListSeq) return;   // 已有更新的请求 / 缓存命中接管
            if (!data.success) {
                TeamShared.toast('获取领养列表失败：' + (data.error || '超时'));
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
    // roster 视图：名册网格
    // ═══════════════════════════════════════════════════════════
    function renderRosterGrid() {
        if (!_gridEl) return;
        var prevScroll = _rosterScrollEl ? _rosterScrollEl.scrollTop : 0;
        var focusSlot = null;
        if (typeof document !== 'undefined' && document.activeElement && _gridEl.contains(document.activeElement)) {
            var focusCard = document.activeElement.closest ? document.activeElement.closest('.team-pet-card') : null;
            if (focusCard) focusSlot = focusCard.getAttribute('data-slot');
        }
        Workbench.clearElement(_gridEl);

        if (_loadError) {
            _gridEl.appendChild(errorEmptyState(_loadError, function() {
                _loadError = '';
                _firstSnapshot = true;
                if (_shell) _shell.setStatus('读取中', Workbench.WorkbenchState.LOADING);
                renderRosterGrid();
                requestSnapshot();
            }));
        } else if (!_snapshot || !_petLib) {
            if (_firstSnapshot) appendSkeleton(_gridEl);
        } else {
            if (_hireCandidate) _gridEl.appendChild(buildCandidateCard(_hireCandidate));
            var order = visibleOrder();
            if (order.length === 0 && !_hireCandidate) {
                _gridEl.appendChild(rosterEmptyState());
            } else {
                for (var k = 0; k < order.length; k++) {
                    _gridEl.appendChild(buildPetCard(_pets[order[k]]));
                }
                appendSlotEmptyTiles();
            }
        }
        if (_rosterScrollEl) _rosterScrollEl.scrollTop = prevScroll;
        if (focusSlot != null) {
            var again = _gridEl.querySelector('.team-pet-card[data-slot="' + focusSlot + '"]');
            if (again) again.focus();
        }
    }

    function appendSkeleton(grid) {
        for (var i = 0; i < 8; i++) {
            var cell = document.createElement('div');
            cell.className = 'team-skel-card';
            grid.appendChild(cell);
        }
    }

    function rosterEmptyState() {
        var noun = meta().noun;
        if (_filterMode !== 'all') {
            return TeamShared.buildEmptyState({
                kind: 'filtered',
                statement: '没有符合当前筛选条件的' + noun,
                nextStep: '调整筛选条件或改回「全部」'
            });
        }
        // H2-5 人文向文案：statement 按 tab 名词变化，nextStep 指回领养入口
        return TeamShared.buildEmptyState({
            kind: 'empty',
            statement: noun + '名册空空如也',
            nextStep: '点「＋ 领养' + noun + '」，迎接第一' + meta().measure + '同行的' + noun
        });
    }

    // 空闲栏位卡（旧 pet-panel「领养空位」复原）：实体卡（含候选卡）之后按全局容量
    // maxSlots - 当前实体数 渲染剩余空位 tile，点击 → 领养目录（复用 enterStore）。
    // snapshot 无 maxSlots 字段时不渲染；筛选态不渲染（避免与筛选结果/筛选空态混淆）。
    function appendSlotEmptyTiles() {
        if (_filterMode !== 'all') return;
        var maxSlots = _snapshot && typeof _snapshot.maxSlots === 'number' ? _snapshot.maxSlots : 0;
        if (maxSlots <= 0) return;
        var entityCount = (_pets ? _pets.length : 0) + (_hireCandidate ? 1 : 0);
        var emptyCount = maxSlots - entityCount;
        for (var i = 0; i < emptyCount; i++) _gridEl.appendChild(buildSlotEmptyTile());
    }

    function buildSlotEmptyTile() {
        var noun = meta().noun;
        var tile = document.createElement('button');
        tile.type = 'button';
        tile.className = 'team-slot-empty';
        // 领养入口真 button：名册网格 listbox→list 后不再投 option，保留原生按钮无语义角色（入口永不被选中）
        tile.setAttribute('aria-label', '空栏位：前往领养' + noun);
        tile.title = '空栏位：前往领养' + noun;
        var plus = document.createElement('span');
        plus.className = 'team-slot-plus';
        plus.textContent = '＋';
        plus.setAttribute('aria-hidden', 'true');
        tile.appendChild(plus);
        var label = document.createElement('span');
        label.className = 'team-slot-label';
        label.textContent = noun + '空位';
        tile.appendChild(label);
        tile.addEventListener('click', enterStore);
        return tile;
    }

    function errorEmptyState(statement, onRetry) {
        var node = TeamShared.buildEmptyState({
            kind: 'error',
            statement: statement,
            nextStep: '检查连接后重试'
        });
        node.appendChild(button('重试', 'team-pane-btn team-empty-retry', onRetry));
        return node;
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

    function buildPetCard(pet) {
        var card = document.createElement('div');
        card.className = 'team-entity-card team-pet-card';
        card.setAttribute('data-slot', pet.slotIndex);

        card.appendChild(iconFrame('assets/pets/pet_' + pet.petId + '.png', portraitContext(pet)));
        card.appendChild(cardFrame());

        var body = document.createElement('div');
        body.className = 'team-entity-body';
        var name = document.createElement('div');
        name.className = 'team-entity-name';
        // Phase J 视觉对齐：等级 inline 回名称行（「名 + Lv」同排，对齐旧版卡片语言），
        // 图标右下数字角标退役；节点保留 append 供 compact 密度角标使用（见下方 levelBadge）
        // Phase K 打磨：名字文本包 .team-pet-name-text（flex 下可缩 + ellipsis 只裁名字），
        // Lv 固定不缩——长名不再把 Lv 一起裁掉
        var nameText = document.createElement('span');
        nameText.className = 'team-pet-name-text';
        nameText.textContent = pet.name;
        name.appendChild(nameText);
        var lvInline = document.createElement('span');
        lvInline.className = 'team-pet-lv';
        lvInline.textContent = 'Lv.' + pet.level;
        name.appendChild(lvInline);
        body.appendChild(name);
        // K-B-1：meta 文字行（Lv · 体力 x/y）退役——Phase J 起等级由名内 inline Lv 承担、
        // 体力/经验数值随下方卡内 meter 行（label + track + 数值）回卡。
        var maxSt = pet.maxStamina || 200;
        // H2-2：full 卡体力 + 经验双 meter（对齐旧版卡片与右栏决策面信息量；
        // 满级经验条投 max 紫；compact 密度整个 body 隐藏，不受影响）
        // Phase J 视觉对齐：卡内 meter 回升为「label（体力/经验）+ track + 右对齐数值」行
        // （旧版分段仪表带标签数值语言；经验百分比、满级投 MAX；
        //   Phase K 起体力数值精简为当前值整数，上限在右栏决策面 / tooltip 仍有）
        var meters = document.createElement('div');
        meters.className = 'team-entity-meters';
        // Phase K 打磨：卡内体力数值精简为当前值整数（对齐旧版卡语言；
        // 上限细节在右栏决策面与 tooltip 仍有），数值列定宽后两条 track 等长
        meters.appendChild(cardMeterRow('体力', staminaTone(pet.stamina), ratioOf(pet.stamina, maxSt),
            String(Math.round(pet.stamina))));
        if (isMaxLevel(pet)) {
            meters.appendChild(cardMeterRow('经验', 'max', 1, 'MAX'));
        } else {
            meters.appendChild(cardMeterRow('经验', 'xp', ratioOf(pet.xp, pet.xpNeeded),
                Math.round(ratioOf(pet.xp, pet.xpNeeded) * 100) + '%'));
        }
        body.appendChild(meters);
        card.appendChild(body);

        // I2：卡内直操动作行（full 密度投 bottom 动作行；compact 由 CSS 隐藏保持纯检视）
        card.appendChild(buildCardActions(pet));

        // I3：同族角标对——状态字牌左上（出战中 / 体力耗尽可共存），满级金角标右上，
        // 满级出战卡两徽标成对同线（同 inset 8px、同几何，仅角色色区分）
        var badges = statusBadge(pet);
        for (var bi = 0; bi < badges.length; bi++) card.appendChild(badges[bi]);
        var maxB = maxBadge(pet);
        if (maxB) card.appendChild(maxB);
        // G2 等级数字角标：full 密度 Phase J 起退役（等级由名内 inline Lv 承担），
        // 节点仅为 compact 密度右下角数字角标保留（SHARED compact 规则显影）
        //（H2-1 起 full/compact 满级同为金色系，compact 金数字角标与整卡金框同源）
        card.appendChild(levelBadge(pet.level));
        if (isMaxLevel(pet)) card.setAttribute('data-level-max', 'true');

        Workbench.EntityTile.bindActivation(card, {
            itemName: pet.name,
            label: cardLabel(pet),
            role: 'listitem',
            selected: pet.slotIndex === _selectedSlot,
            onActivate: function() { selectPet(pet.slotIndex); }
        });
        fixupCardA11y(card, pet.slotIndex === _selectedSlot);
        if (pet.slotIndex === _selectedSlot) card.setAttribute('data-state', 'selected');
        bindCardTip(card, function() { return cardTipText(pet); });
        return card;
    }

    // I2 卡内直操动作行（full 卡底部）：出战/休息 + 恢复体力（「恢复·1000金」花费文案），
    // 与右栏决策面同 handler / blocked 投影 / pending；嵌套按钮纪律见 bindCardActionNesting
    function buildCardActions(pet) {
        var row = document.createElement('div');
        row.className = 'team-entity-actions';
        var maxSt = pet.maxStamina || 200;

        var deployBtn = button(pet.deployed ? '休息' : '出战', 'team-action-btn team-card-act team-act-deploy', null);
        deployBtn.setAttribute('data-tone', 'deploy');
        deployBtn.setAttribute('aria-label', (pet.deployed ? '休息：' : '出战：') + pet.name);
        var deployReason = '';
        if (_snapshot && _snapshot.isCombatMap && !pet.deployed) deployReason = '战斗中无法调整出战阵容';
        else if (pet.stamina <= 0 && !pet.deployed) deployReason = '体力耗尽，无法出战';
        setActionBlocked(deployBtn, deployReason);
        deployBtn.addEventListener('click', function() {
            if (guardBlocked(this)) return;
            onToggleDeploy(pet.slotIndex, this);
        });
        row.appendChild(deployBtn);

        var restoreBtn = button('恢复·' + RESTORE_COST + '金', 'team-action-btn team-card-act team-act-restore', null);
        restoreBtn.setAttribute('data-tone', 'restore');
        restoreBtn.setAttribute('aria-label', '恢复：' + pet.name + '（' + RESTORE_COST + ' 金币）');
        var restoreReason = '';
        if (pet.stamina >= maxSt) restoreReason = '体力已满';
        else if (_snapshot && (_snapshot.gold || 0) < RESTORE_COST) restoreReason = '金币不足（需 ' + RESTORE_COST + '）';
        setActionBlocked(restoreBtn, restoreReason);
        if (!restoreReason) restoreBtn.title = '消耗 ' + RESTORE_COST + ' 金币恢复体力至满值';
        restoreBtn.addEventListener('click', function() {
            if (guardBlocked(this)) return;
            onRestoreStamina(pet.slotIndex, this);
        });
        row.appendChild(restoreBtn);

        bindCardActionNesting(row);
        return row;
    }

    // 嵌套按钮纪律（EntityTile 规范）：卡内按钮是真 button、自带 tab stop 与 aria-label；
    // 点击 / Enter / Space 在按钮上不得冒泡触发卡片选中（卡片本体选中行为不变）
    function bindCardActionNesting(row) {
        row.addEventListener('click', function(event) { event.stopPropagation(); });
        row.addEventListener('keydown', function(event) {
            if (event.key === 'Enter' || event.key === ' ') event.stopPropagation();
        });
    }

    // listitem 选中态修正（外审二轮 P2-4）：共享层 EntityTile.applySemantics / setSelected 照写
    // aria-selected（真 listbox 面板仍需要），但 role=listitem 不支持该属性——team 局部在
    // bindActivation / setSelected 调用点后改投 aria-current；选中态视觉不受影响（走 data-state）
    function fixupCardA11y(card, selected) {
        if (!card) return;
        card.removeAttribute('aria-selected');
        if (selected) card.setAttribute('aria-current', 'true');
        else card.removeAttribute('aria-current');
    }

    // 世界内招募候选卡（旧 Symbol 2035 宠物分支的 web 等价）：置顶在现役上方，
    // 只展示 图标/名字/等级/契约金 + 「候选」标识；门控在右栏决策面按实时 snapshot 复算。
    function buildCandidateCard(cand) {
        var card = document.createElement('div');
        card.className = 'team-entity-card team-pet-card team-pet-card-candidate';
        card.setAttribute('data-slot', String(CANDIDATE_SLOT));

        card.appendChild(iconFrame('assets/pets/pet_' + cand.petId + '.png', portraitContext(cand)));
        card.appendChild(cardFrame());

        var body = document.createElement('div');
        body.className = 'team-entity-body';
        var name = document.createElement('div');
        name.className = 'team-entity-name';
        // Phase K：与现役卡同名结构（.team-pet-name-text 独占，flex 名称行下保持 ellipsis）
        var nameText = document.createElement('span');
        nameText.className = 'team-pet-name-text';
        nameText.textContent = cand.name;
        name.appendChild(nameText);
        body.appendChild(name);
        var metaLine = document.createElement('div');
        metaLine.className = 'team-entity-meta';
        metaLine.textContent = 'Lv.' + cand.level + ' · 契约金 ' + TeamShared.fmtMoney(cand.goldPrice);
        body.appendChild(metaLine);
        card.appendChild(body);

        var badge = document.createElement('span');
        badge.className = 'team-entity-badge';
        badge.setAttribute('data-tone', 'info');
        badge.textContent = '候选';
        card.appendChild(badge);

        Workbench.EntityTile.bindActivation(card, {
            itemName: cand.name,
            label: '招募候选 ' + cand.name + '，Lv.' + cand.level,
            role: 'listitem',
            selected: _selectedSlot === CANDIDATE_SLOT,
            onActivate: function() { selectPet(CANDIDATE_SLOT); }
        });
        fixupCardA11y(card, _selectedSlot === CANDIDATE_SLOT);
        if (_selectedSlot === CANDIDATE_SLOT) card.setAttribute('data-state', 'selected');
        bindCardTip(card, function() {
            return '招募候选 ' + cand.name + ' · Lv.' + cand.level + ' · 契约金 ' + TeamShared.fmtMoney(cand.goldPrice);
        });
        return card;
    }

    function selectPet(slot) {
        if (guardBusy()) return;
        _selectedSlot = slot;
        var cards = _gridEl.querySelectorAll('.team-pet-card');
        for (var i = 0; i < cards.length; i++) {
            var sel = cards[i].getAttribute('data-slot') === String(slot);
            Workbench.EntityTile.setSelected(cards[i], sel);
            fixupCardA11y(cards[i], sel);
            if (sel) cards[i].setAttribute('data-state', 'selected');
            else cards[i].removeAttribute('data-state');
        }
        renderDetail();
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

    // 出战 / 恢复后按「筛选 + 排序」双重归属决定刷新粒度：
    // 位次未变 → refreshCard 原位更新（不跳动、不动滚动）；被剔除或位次变化 → 静默整排。
    function reflowCardAfterMutation(slotIndex) {
        var petIdx = findPetIndexBySlot(slotIndex);
        if (petIdx < 0) { renderRosterGrid(); return; }
        var order = visibleOrder();
        var newPos = -1;
        for (var k = 0; k < order.length; k++) { if (order[k] === petIdx) { newPos = k; break; } }
        if (newPos < 0) { renderRosterGrid(); return; }
        var oldCard = _gridEl.querySelector('.team-pet-card[data-slot="' + slotIndex + '"]');
        if (!oldCard) { renderRosterGrid(); return; }
        var cards = _gridEl.querySelectorAll('.team-pet-card[data-slot]');
        var oldPos = -1, realPos = -1;
        for (var j = 0; j < cards.length; j++) {
            if (cards[j].getAttribute('data-slot') === String(CANDIDATE_SLOT)) continue;
            realPos++;
            if (cards[j] === oldCard) { oldPos = realPos; break; }
        }
        if (oldPos === newPos) refreshCard(slotIndex);
        else renderRosterGrid();
    }

    // 局部刷新单张卡片（出战 / 恢复后，不整页重排）
    function refreshCard(slotIndex) {
        var idx = findPetIndexBySlot(slotIndex);
        if (idx < 0) return;
        var old = _gridEl.querySelector('.team-pet-card[data-slot="' + slotIndex + '"]');
        if (!old) return;
        // 换卡会销毁旧节点：先记下焦点落点（卡本体或卡内哪个动作），
        // 替换后恢复到新卡等价控件，避免焦点掉 body（对齐 renderRosterGrid 的焦点恢复）
        var focusSelector = null, focusOnCard = false;
        if (typeof document !== 'undefined' && document.activeElement && old.contains(document.activeElement)) {
            var active = document.activeElement;
            if (active === old) {
                focusOnCard = true;
            } else if (active.closest && active.closest('.team-act-deploy')) {
                focusSelector = '.team-act-deploy';
            } else if (active.closest && active.closest('.team-act-restore')) {
                focusSelector = '.team-act-restore';
            } else {
                focusOnCard = true;   // 卡内其他落点：退回卡本体
            }
        }
        var fresh = buildPetCard(_pets[idx]);
        // 原位替换前先释放旧卡上的 EntityTile / tooltip 绑定，避免域内 detached 绑定累积
        Workbench.releaseElementBindings(old);
        old.parentNode.replaceChild(fresh, old);
        if (focusSelector) {
            var focusBtn = fresh.querySelector(focusSelector);
            if (focusBtn) focusBtn.focus();
        } else if (focusOnCard) {
            fresh.focus();
        }
    }

    // ═══════════════════════════════════════════════════════════
    // roster 视图：右栏决策面
    // ═══════════════════════════════════════════════════════════
    function renderDetail() {
        if (!_detailEl) return;
        Workbench.clearElement(_detailEl);
        if (_selectedSlot === CANDIDATE_SLOT && _hireCandidate) { renderCandidateDetail(); return; }
        var noun = meta().noun;
        var pet = findPetBySlot(_selectedSlot);
        if (!pet || rosterTypeForPet(pet.petId) !== _rosterType) {
            _detailEl.appendChild(TeamShared.buildEmptyState({
                kind: 'empty',
                statement: '选择左侧一只' + noun + '查看详情',
                nextStep: _hireCandidate ? '或选择置顶「候选」卡确认招募' : '出战 · 恢复 · 培养都在这里完成'
            }));
            return;
        }

        _detailEl.appendChild(detailHead(pet.name, 'Lv.' + pet.level,
            'assets/pets/pet_' + pet.petId + '.png', statusChips(pet), portraitContext(pet)));

        var meters = document.createElement('div');
        meters.className = 'team-detail-meters';
        var maxSt = pet.maxStamina || 200;
        meters.appendChild(meterRow('体力', staminaTone(pet.stamina), ratioOf(pet.stamina, maxSt),
            pet.stamina + '/' + maxSt));
        var levelLimit = _snapshot ? (_snapshot.levelLimit || 100) : 100;
        if (pet.level >= levelLimit) {
            meters.appendChild(meterRow('经验', 'max', 1, 'MAX'));
        } else {
            meters.appendChild(meterRow('经验', 'xp', ratioOf(pet.xp, pet.xpNeeded),
                Math.round(ratioOf(pet.xp, pet.xpNeeded) * 100) + '%'));
        }
        _detailEl.appendChild(meters);

        var summary = combatSummary(pet);
        if (summary) _detailEl.appendChild(summary);

        // 动作行：出战 · 休息切换 / 恢复体力 / 培养
        var actions = document.createElement('div');
        actions.className = 'team-detail-action-row';

        var deployBtn = button(pet.deployed ? '休息' : '出战', 'team-action-btn team-act-deploy', null);
        deployBtn.setAttribute('data-tone', 'deploy');
        deployBtn.setAttribute('aria-label', (pet.deployed ? '休息 ' : '出战 ') + pet.name);
        var deployReason = '';
        if (_snapshot && _snapshot.isCombatMap && !pet.deployed) deployReason = '战斗中无法调整出战阵容';
        else if (pet.stamina <= 0 && !pet.deployed) deployReason = '体力耗尽，无法出战';
        setActionBlocked(deployBtn, deployReason);
        deployBtn.addEventListener('click', function() {
            if (guardBlocked(this)) return;
            onToggleDeploy(pet.slotIndex, this);
        });
        actions.appendChild(deployBtn);

        var restoreBtn = button('恢复 · ' + RESTORE_COST + '金', 'team-action-btn team-act-restore', null);
        restoreBtn.setAttribute('data-tone', 'restore');
        restoreBtn.setAttribute('aria-label', '恢复体力 ' + pet.name + '（' + RESTORE_COST + ' 金币）');
        var restoreReason = '';
        if (pet.stamina >= maxSt) restoreReason = '体力已满';
        else if (_snapshot && (_snapshot.gold || 0) < RESTORE_COST) restoreReason = '金币不足（需 ' + RESTORE_COST + '）';
        setActionBlocked(restoreBtn, restoreReason);
        if (!restoreReason) restoreBtn.title = '消耗 ' + RESTORE_COST + ' 金币恢复体力至满值';
        restoreBtn.addEventListener('click', function() {
            if (guardBlocked(this)) return;
            onRestoreStamina(pet.slotIndex, this);
        });
        actions.appendChild(restoreBtn);

        var advanceBtn = button('培养 →', 'team-action-btn team-act-advance', function() {
            openAdvance(pet.slotIndex);
        });
        advanceBtn.setAttribute('data-tone', 'primary');
        advanceBtn.setAttribute('aria-label', '培养 ' + pet.name);
        advanceBtn.title = '进阶养成 / 强化 / 删除 / 完整文案';
        actions.appendChild(advanceBtn);
        _detailEl.appendChild(actions);

        // 快捷进阶开关（已解锁、可反复开关 / 循环的方案：淬毒、发型…）
        var quickBox = document.createElement('div');
        quickBox.className = 'team-quick-toggles';
        renderQuickToggles(pet, quickBox);
        _detailEl.appendChild(quickBox);
    }

    function renderCandidateDetail() {
        var cand = _hireCandidate;
        var noun = meta().noun;
        var chips = [];
        var candChip = document.createElement('span');
        candChip.className = 'team-detail-chip';
        candChip.textContent = '招募候选';
        chips.push(candChip);
        _detailEl.appendChild(detailHead(cand.name, 'Lv.' + cand.level,
            'assets/pets/pet_' + cand.petId + '.png', chips, portraitContext(cand)));

        var price = document.createElement('div');
        price.className = 'team-cand-price';
        var gold = _snapshot ? (_snapshot.gold || 0) : 0;
        price.textContent = '契约金 ' + TeamShared.fmtMoney(cand.goldPrice)
            + ' · 余额 ' + TeamShared.fmtMoney(gold);
        _detailEl.appendChild(price);

        var block = '';
        var totalPets = _pets ? _pets.length : 0;
        // snapshot 未到达前按「加载中」禁用（对齐 adoptGate 的未就绪模式）：
        // 首开一瞬 gold 按 0 算会误挂「金币不足」，snapshot 到达后重渲自愈
        if (!_snapshot) block = '数据加载中…';
        else if (_snapshot.maxSlots > 0 && totalPets >= _snapshot.maxSlots) block = noun + '栏位已满，请先删除部分' + noun;
        else if (gold < cand.goldPrice) block = '金币不足';

        var actions = document.createElement('div');
        actions.className = 'team-detail-action-row';
        var recruitBtn = button('确认招募', 'team-action-btn team-act-recruit', null);
        recruitBtn.setAttribute('data-tone', 'primary');
        recruitBtn.setAttribute('aria-label', '确认招募 ' + cand.name);
        setActionBlocked(recruitBtn, block);
        recruitBtn.addEventListener('click', function() {
            if (guardBlocked(this)) return;
            onWorldAdopt(this);
        });
        actions.appendChild(recruitBtn);
        _detailEl.appendChild(actions);

        var note = document.createElement('div');
        note.className = 'team-cand-note';
        note.textContent = '招募成功后关闭面板返回场景；门控按实时数据复算。';
        _detailEl.appendChild(note);
    }

    // 选中宠的快捷进阶：仅渲染「已解锁的可反复开关 / 循环」方案；
    // 一次性进阶 / 强化 / 删除 / 完整文案均在「培养」页，不在此重复。
    function renderQuickToggles(pet, box) {
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
            pill.className = 'team-qadv team-qadv-' + tk + (tk === 'binary' && st.toggleOn ? ' team-qadv-on' : '');
            pill.setAttribute('aria-pressed', tk === 'binary' && st.toggleOn ? 'true' : 'false');
            if (tk === 'binary') {
                pill.title = st.toggleOn
                    ? ('点击关闭「' + nm + '」' + (perMap ? '（省每图 ' + TeamShared.fmtMoney(schemes[nm].gold) + ' 金）' : ''))
                    : ('点击开启「' + nm + '」' + (perMap ? '（开启后每图 ' + TeamShared.fmtMoney(schemes[nm].gold) + ' 金）' : ''));
                pill.setAttribute('aria-label', (st.toggleOn ? '关闭 ' : '开启 ') + nm);
                pill.innerHTML = '<span class="team-qadv-name">' + TeamShared.escapeHtml(nm)
                    + '</span><span class="team-qadv-switch"></span>';
            } else {
                pill.title = '点击切换「' + nm + '」';
                pill.setAttribute('aria-label', '切换 ' + nm + '（当前 ' + (st.toggleValue || '无') + '）');
                pill.innerHTML = '<span class="team-qadv-name">' + TeamShared.escapeHtml(nm)
                    + '</span><span class="team-qadv-value">' + TeamShared.escapeHtml(st.toggleValue || '') + '</span>';
            }
            (function(schemeName, slot) {
                pill.addEventListener('click', function() { onAdvance(schemeName, this, slot, '已更新'); });
            })(nm, pet.slotIndex);
            box.appendChild(pill);
            count++;
        }
        if (count === 0) {
            var hint = document.createElement('div');
            hint.className = 'team-qadv-empty';
            hint.textContent = '暂无可快捷切换的进阶 · 点「培养 →」查看养成方案';
            box.appendChild(hint);
        }
    }

    function updateHeaderMetrics() {
        if (!_shell) return;
        var noun = meta().noun;
        var subtitle = '读取中';
        if (_snapshot) {
            subtitle = '出战 ' + (_snapshot.currentDeployCount || 0) + '/' + (_snapshot.maxDeploy || 0)
                + ' · 栏位 ' + (_pets ? _pets.length : 0) + '/' + (_snapshot.maxSlots || 0);
        }
        _shell.setTitle(noun + '管理', subtitle);
        if (!_snapshot) return;
        _shell.setMetric('gold', '金币', TeamShared.fmtMoney(_snapshot.gold));
        _shell.setMetric('kpoint', 'K点', TeamShared.fmtMoney(_snapshot.kpoint));
    }

    // ═══════════════════════════════════════════════════════════
    // store 视图：领养目录 + CommitBar
    // ═══════════════════════════════════════════════════════════
    function enterStore() {
        if (guardBusy()) return;
        if (_view === 'store' || !_shell) return;
        if (!_storeL) buildStoreViews();
        _view = 'store';
        _adoptPetId = null;
        _commitError = null;   // 进商店即新 browse 会话，旧领养失败投影随之失效
        _shell.moveView('L', _storeL);
        _shell.moveView('R', _storeR);
        renderStoreContent();
    }

    function backToRoster() {
        if (guardBusy()) return;   // pointer-events 锁不挡键盘，busy 期 Enter 可触达本 handler
        if (_view !== 'store' || !_shell) return;
        _view = 'roster';
        _adoptPetId = null;
        _commitError = null;   // 出商店即新 browse 会话，旧领养失败投影随之失效
        _shell.moveView('L', _rosterL);
        _shell.moveView('R', _rosterR);
    }

    function renderStoreContent() {
        var cached = !!_storeCache[_rosterType + ':' + _storeCategoryIdx];
        if (!cached) {
            if (_storeTabsEl) Workbench.clearElement(_storeTabsEl);
            if (_storeGridEl) {
                Workbench.clearElement(_storeGridEl);
                appendSkeleton(_storeGridEl);
            }
            if (_shell) _shell.setStatus('读取中', Workbench.WorkbenchState.LOADING);
        }
        var storeSession = _session;
        requestAdoptList(_storeCategoryIdx, function(ok) {
            if (storeSession !== _session) return;
            if (!ok) {
                if (_shell) _shell.setStatus('读取失败', Workbench.WorkbenchState.ERROR);
                if (_storeGridEl) {
                    Workbench.clearElement(_storeGridEl);
                    _storeGridEl.appendChild(errorEmptyState('获取领养列表失败', function() {
                        renderStoreContent();
                    }));
                }
                return;
            }
            if (_shell) _shell.setStatus('就绪', Workbench.WorkbenchState.READY);
            renderStoreTabs();
            renderStoreGrid();
            renderStorePreview();
        });
    }

    function renderStoreTabs() {
        if (!_storeTabsEl) return;
        Workbench.clearElement(_storeTabsEl);
        var categories = _storeCategories || [];
        for (var c = 0; c < categories.length; c++) {
            var originalIndex = typeof categories[c].index === 'number' ? categories[c].index : c;
            var tab = document.createElement('button');
            tab.type = 'button';
            tab.className = 'team-store-tab' + (originalIndex === _storeCategoryIdx ? ' team-store-tab-active' : '');
            tab.textContent = categories[c].name;
            tab.setAttribute('data-index', originalIndex);
            tab.setAttribute('aria-pressed', originalIndex === _storeCategoryIdx ? 'true' : 'false');
            tab.setAttribute('aria-label', '领养分类 ' + categories[c].name);
            tab.addEventListener('click', function() {
                var ci = parseInt(this.getAttribute('data-index'), 10);
                if (ci === _storeCategoryIdx) return;
                if (guardBusy()) return;
                _storeCategoryIdx = ci;
                renderStoreContent();
            });
            _storeTabsEl.appendChild(tab);
        }
    }

    function renderStoreGrid() {
        if (!_storeGridEl || _view !== 'store') return;
        Workbench.clearElement(_storeGridEl);
        if (!_storeData || _storeData.length === 0) {
            // 请求在途（无数据且当前分类无缓存）投骨架而非空态：消除 enterStore 首进
            // attach 渲染闪一帧「暂无可领养」的假空态；真空分类回包后缓存已建，仍走空态
            if (!_storeCache[_rosterType + ':' + _storeCategoryIdx]) { appendSkeleton(_storeGridEl); return; }
            _storeGridEl.appendChild(TeamShared.buildEmptyState({
                kind: 'empty',
                statement: '该分类下暂无可领养' + meta().noun,
                nextStep: '切换其他分类看看'
            }));
            return;
        }
        for (var i = 0; i < _storeData.length; i++) {
            _storeGridEl.appendChild(buildStoreCard(_storeData[i]));
        }
    }

    function buildStoreCard(item) {
        var gate = adoptGate(item);
        var taskLocked = isMainlineLocked(item);

        var card = document.createElement('div');
        card.className = 'team-entity-card team-pet-card team-store-card';
        card.setAttribute('data-pet-id', item.petId);
        if (taskLocked) card.setAttribute('data-mainline-locked', 'true');
        var storeIcon = taskLocked ? 'assets/pets/pet_locked.png' : 'assets/pets/pet_' + item.petId + '.png';
        card.appendChild(iconFrame(storeIcon, portraitContext(item, { locked: taskLocked })));
        card.appendChild(cardFrame());

        var body = document.createElement('div');
        body.className = 'team-entity-body';
        var name = document.createElement('div');
        name.className = 'team-entity-name';
        // Phase K：与现役卡同名结构（.team-pet-name-text 独占，flex 名称行下保持 ellipsis）
        var nameText = document.createElement('span');
        nameText.className = 'team-pet-name-text';
        nameText.textContent = item.name;
        name.appendChild(nameText);
        body.appendChild(name);
        // 「唯一」是身份属性：独立于经济信息占一条属性轨，也不复用左上状态徽标。
        // 完整态保留该轨；紧凑态由 card body 一并隐藏，tooltip / aria / 右栏继续承接语义。
        if (item.unique) {
            var flags = document.createElement('div');
            flags.className = 'team-store-flags';
            var uniqueMark = document.createElement('span');
            uniqueMark.className = 'team-store-unique-chip';
            uniqueMark.textContent = '唯一';
            uniqueMark.setAttribute('aria-label', '唯一战宠');
            flags.appendChild(uniqueMark);
            body.appendChild(flags);
        }
        var metaLine = document.createElement('div');
        metaLine.className = 'team-entity-meta';
        var price = document.createElement('span');
        price.className = 'team-store-price';
        price.textContent = priceText(item);
        metaLine.appendChild(price);
        body.appendChild(metaLine);
        card.appendChild(body);

        Workbench.EntityTile.bindActivation(card, {
            itemName: item.name,
            label: item.name + '，' + priceText(item) + (item.unique ? '，唯一' : ''),
            role: 'listitem',
            selected: item.petId === _adoptPetId,
            actionable: true,   // 选候选是本地 browse（零写入）；门控由右栏 CommitBar 阻断
            reason: gate,
            onActivate: function() { selectStoreItem(item.petId); }
        });
        fixupCardA11y(card, item.petId === _adoptPetId);
        if (item.petId === _adoptPetId) card.setAttribute('data-state', 'selected');
        else if (gate) card.setAttribute('data-state', 'blocked');
        bindCardTip(card, function() {
            return item.name + ' · ' + priceText(item) + (item.unique ? ' · 唯一' : '')
                + (gate ? ' · ' + gate : ' · 可领养');
        });
        return card;
    }

    function selectStoreItem(petId) {
        if (guardBusy()) return;    // commit 飞行中禁止改选：重渲会冲掉 CommitBar busy 投影
        _commitError = null;        // 用户改选：旧领养失败 error 投影随之失效
        _adoptPetId = petId;
        var cards = _storeGridEl.querySelectorAll('.team-store-card');
        for (var i = 0; i < cards.length; i++) {
            var sel = cards[i].getAttribute('data-pet-id') === String(petId);
            Workbench.EntityTile.setSelected(cards[i], sel);
            fixupCardA11y(cards[i], sel);
            if (sel) {
                cards[i].setAttribute('data-state', 'selected');
            } else {
                var gate = cards[i].getAttribute('data-entity-reason');
                if (gate) cards[i].setAttribute('data-state', 'blocked');
                else cards[i].removeAttribute('data-state');
            }
        }
        renderStorePreview();
    }

    function renderStorePreview() {
        if (!_storePreviewEl || !_commitBar || _view !== 'store') return;
        if (_commitError) return;   // 领养失败 error 投影保留到用户改选 / 重新提交，不被常规重渲冲掉
        Workbench.clearElement(_storePreviewEl);
        var item = findStoreItem(_adoptPetId);
        if (!item) {
            _storePreviewEl.appendChild(TeamShared.buildEmptyState({
                kind: 'empty',
                statement: '选择左侧目标查看价格与确认领养',
                nextStep: '价格、余额与条件在提交前再次核对'
            }));
            if (!_busy) _commitBar.update({ status: '未选择目标', disabled: true, state: '', busy: false });
            return;
        }

        var chips = [];
        if (item.unique) {
            var chip = document.createElement('span');
            chip.className = 'team-detail-chip';
            chip.textContent = '唯一';
            chips.push(chip);
        }
        // 主线未解锁时，右侧必须与左卡使用同一视觉防剧透投影。locked context
        // 令 resolver 在占位图后立即返回，不请求 manifest 或现代透明头像。
        var taskLocked = isMainlineLocked(item);
        var previewIcon = taskLocked ? 'assets/pets/pet_locked.png' : 'assets/pets/pet_' + item.petId + '.png';
        var previewHead = detailHead(item.name, priceText(item), previewIcon, chips,
            portraitContext(item, { locked: taskLocked }));
        if (taskLocked) previewHead.setAttribute('data-mainline-locked', 'true');
        _storePreviewEl.appendChild(previewHead);

        var req = document.createElement('div');
        req.className = 'team-store-req';
        var reqs = [];
        if (item.unlockTask > 0) reqs.push('需主线 ' + item.unlockTask);
        if (item.unlockLevel > 0) reqs.push('需 Lv.' + item.unlockLevel);
        if (!reqs.length) reqs.push('无解锁条件');
        req.textContent = reqs.join(' · ');
        _storePreviewEl.appendChild(req);

        var gate = adoptGate(item);
        if (_busy) return;   // commit 飞行中：预览内容已重渲，CommitBar busy 投影保持不覆盖
        if (gate) {
            _commitBar.update({ status: gate, canCommit: false, state: 'blocked', busy: false });
        } else {
            // Phase K 打磨：ready 态改短文案——价格已在右栏 detailHead 副题、
            // 余额在 header metrics，CommitBar 不复述（长文本与 CTA/滚动区挤碰遮挡）
            _commitBar.update({ status: '可确认领养', canCommit: true, state: 'ready', busy: false });
        }
    }

    // CommitBar 唯一主 CTA：busy 到回包；成功 → 刷新 snapshot 并回名册；
    // 失败 → status error 保留到用户改选 / 重新提交 + 重拉 snapshot 对账，绝不自动重放。
    function onCommitAdopt() {
        if (guardBusy()) return;
        if (_adoptPetId == null) return;
        _commitError = null;   // 重新提交：旧失败 error 投影失效
        var item = findStoreItem(_adoptPetId);
        if (!item) return;
        var gate = adoptGate(item);
        if (gate) { TeamShared.toast(gate); renderStorePreview(); return; }
        beginOp(null);   // 与其他操作同锁：data-team-busy 投影同样覆盖领养 commit 飞行期
        _commitBar.update({ busy: true, status: '领养确认中', state: 'busy' });
        sendPanelMsg('adopt', { petId: _adoptPetId }, function(data) {
            endOp(null);
            if (data.success) {
                if (_snapshot) { _snapshot.gold = data.gold; _snapshot.kpoint = data.kpoint; }
                _storeCache = {};   // 领养改变拥有态 / 价格，失效缓存
                TeamShared.toast('领养成功！');
                _adoptPetId = null;
                if (_commitBar) _commitBar.update({ busy: false, status: '已领养', state: 'ready' });
                backToRoster();
                requestSnapshot();
            } else {
                var msg = '领养失败：' + (data.reason || data.error || '未知错误');
                _commitError = msg;   // error 投影保留到用户改选 / 重新提交
                TeamShared.toast(msg);
                // 先只呈现失败原因；「数据已重新同步」后缀由对账 snapshot 回包后再补，文案不抢跑
                if (_commitBar) _commitBar.update({ busy: false, state: 'error', status: msg });
                requestSnapshot();   // 对账重拉
            }
        });
    }

    // ═══════════════════════════════════════════════════════════
    // advance 培养页（SecondaryPage 覆盖 body）
    // ═══════════════════════════════════════════════════════════
    function openAdvance(slotIndex) {
        if (guardBusy()) return;
        var pet = findPetBySlot(slotIndex);
        if (!pet) return;
        _advanceSlot = slotIndex;
        if (!_advancePage) buildAdvancePage();
        renderAdvance();
        _advancePage.open({ initialFocus: _advanceRightEl });
    }

    function buildAdvancePage() {
        var rootEl = document.createElement('section');
        rootEl.className = 'team-advance';
        _advancePage = new WorkbenchComponents.SecondaryPage({
            root: rootEl,
            className: 'team-advance-page',
            ariaLabel: meta().noun + '培养',
            host: _shell.getRoot(),
            onClose: function() {
                renderRosterGrid();
                renderDetail();
            }
        });

        var header = document.createElement('div');
        header.className = 'team-advance-header';
        var back = button('‹ 返回', 'team-pane-btn team-advance-back', null);
        back.setAttribute('aria-label', '返回名册');
        _advancePage.bindBack(back);
        header.appendChild(back);
        _advanceTitleEl = document.createElement('div');
        _advanceTitleEl.className = 'team-advance-title';
        header.appendChild(_advanceTitleEl);
        _advanceChipsEl = document.createElement('div');
        _advanceChipsEl.className = 'team-detail-chip-row team-advance-chips';
        header.appendChild(_advanceChipsEl);
        var actions = document.createElement('div');
        actions.className = 'team-advance-actions';
        header.appendChild(actions);
        rootEl.appendChild(header);

        // H1 两栏：body 是 grid 容器（自身不滚动）；左右栏各自窄轨纵滚，右栏为进阶方案主滚动区
        _advanceBodyEl = document.createElement('div');
        _advanceBodyEl.className = 'team-advance-body team-pet-advance-body';
        _advanceLeftEl = document.createElement('div');
        _advanceLeftEl.className = 'team-scroll team-pet-advance-left';
        _advanceLeftEl.setAttribute('data-scroll-region', '');
        _advanceBodyEl.appendChild(_advanceLeftEl);
        _advanceRightEl = document.createElement('div');
        _advanceRightEl.className = 'team-scroll team-pet-advance-right';
        _advanceRightEl.setAttribute('data-scroll-region', '');
        _advanceRightEl.setAttribute('tabindex', '0');
        _advanceBodyEl.appendChild(_advanceRightEl);
        rootEl.appendChild(_advanceBodyEl);
    }

    function renderAdvance() {
        if (!_advancePage || !_advanceBodyEl) return;
        var pet = findPetBySlot(_advanceSlot);
        if (!pet) {
            if (_advancePage.isActive()) _advancePage.close('pet-gone');
            return;
        }
        var noun = meta().noun;
        _advanceTitleEl.textContent = pet.name + ' Lv.' + pet.level;

        Workbench.clearElement(_advanceChipsEl);
        var chips = statusChips(pet);
        for (var c = 0; c < chips.length; c++) _advanceChipsEl.appendChild(chips[c]);

        // 顶部动作：出战 · 休息 / 恢复体力 / 强化 / 删除
        var actions = _advancePage.root.querySelector('.team-advance-actions');
        Workbench.clearElement(actions);

        var deployBtn = button(pet.deployed ? '休息' : '出战', 'team-action-btn team-act-deploy', null);
        deployBtn.setAttribute('data-tone', 'deploy');
        deployBtn.setAttribute('aria-label', (pet.deployed ? '休息 ' : '出战 ') + pet.name);
        var deployReason = '';
        if (_snapshot && _snapshot.isCombatMap && !pet.deployed) deployReason = '战斗中无法调整出战阵容';
        else if (pet.stamina <= 0 && !pet.deployed) deployReason = '体力耗尽，无法出战';
        setActionBlocked(deployBtn, deployReason);
        deployBtn.addEventListener('click', function() {
            if (guardBlocked(this)) return;
            onToggleDeploy(pet.slotIndex, this);
        });
        actions.appendChild(deployBtn);

        var maxSt = pet.maxStamina || 200;
        var restoreBtn = button('恢复 · ' + RESTORE_COST + '金', 'team-action-btn team-act-restore', null);
        restoreBtn.setAttribute('data-tone', 'restore');
        restoreBtn.setAttribute('aria-label', '恢复体力 ' + pet.name + '（' + RESTORE_COST + ' 金币）');
        var restoreReason = '';
        if (pet.stamina >= maxSt) restoreReason = '体力已满';
        else if (_snapshot && (_snapshot.gold || 0) < RESTORE_COST) restoreReason = '金币不足（需 ' + RESTORE_COST + '）';
        setActionBlocked(restoreBtn, restoreReason);
        restoreBtn.addEventListener('click', function() {
            if (guardBlocked(this)) return;
            onRestoreStamina(pet.slotIndex, this);
        });
        actions.appendChild(restoreBtn);

        var levelLimit = _snapshot ? (_snapshot.levelLimit || 100) : 100;
        var levelupBtn = button('', 'team-action-btn team-act-levelup', null);
        levelupBtn.setAttribute('data-tone', 'primary');
        if (pet.level >= levelLimit) {
            levelupBtn.textContent = '已满级';
            setActionBlocked(levelupBtn, '已达等级上限');
        } else {
            var xpNeededForCost = pet.xpNeeded || 0;
            var stoneCost = pet.level * 2 + Math.floor(xpNeededForCost / 10000);
            if (stoneCost < 1) stoneCost = 1;
            levelupBtn.textContent = '强化 · 灵石×' + stoneCost;
            levelupBtn.title = '消耗战宠灵石：' + stoneCost + '  |  经验：' + (pet.xp || 0) + '/' + (xpNeededForCost || '--');
        }
        levelupBtn.setAttribute('aria-label', '强化 ' + pet.name);
        levelupBtn.addEventListener('click', function() {
            if (guardBlocked(this)) return;
            onLevelUp(this);
        });
        actions.appendChild(levelupBtn);

        var deleteBtn = button('删除', 'team-action-btn team-act-delete', function() {
            confirmDelete(pet);
        });
        deleteBtn.setAttribute('data-tone', 'danger');
        deleteBtn.setAttribute('aria-label', '删除 ' + pet.name);
        deleteBtn.title = '永久删除此' + noun;
        actions.appendChild(deleteBtn);

        // body 两栏：左栏 属性信息 / 战斗属性，右栏 进阶方案（独占纵向滚动区）
        Workbench.clearElement(_advanceLeftEl);
        Workbench.clearElement(_advanceRightEl);

        var statSection = advanceSection('属性信息');
        var statGrid = document.createElement('div');
        statGrid.className = 'team-stats-grid';
        statGrid.appendChild(meterRow('体力', staminaTone(pet.stamina), ratioOf(pet.stamina, maxSt),
            pet.stamina + '/' + maxSt));
        if (pet.level >= levelLimit) {
            statGrid.appendChild(meterRow('经验', 'max', 1, '已满级'));
        } else {
            var curXp = pet.xp || 0, needXp = pet.xpNeeded || 0;
            statGrid.appendChild(meterRow('经验', 'xp', ratioOf(curXp, needXp),
                curXp + '/' + (needXp || '--')));
        }
        statSection.appendChild(statGrid);
        if (pet.level < levelLimit && (pet.xpNeeded || 0) > 0) {
            var xpSub = document.createElement('div');
            xpSub.className = 'team-stat-sub';
            xpSub.textContent = '还需 ' + Math.max(0, (pet.xpNeeded || 0) - (pet.xp || 0)).toLocaleString() + ' 经验升级';
            statSection.appendChild(xpSub);
        } else if (pet.level >= levelLimit) {
            var maxSub = document.createElement('div');
            maxSub.className = 'team-stat-sub';
            maxSub.textContent = 'Lv.' + pet.level + ' 已达上限';
            statSection.appendChild(maxSub);
        }
        _advanceLeftEl.appendChild(statSection);

        // 战斗属性成长（AS2 snapshot.combat：敌人属性表插值；旧 SWF 缺字段时整块隐藏）
        var combatGrid = document.createElement('div');
        combatGrid.className = 'team-stats-grid';
        if (renderCombatStats(pet, levelLimit, combatGrid)) {
            var combatSection = advanceSection('战斗属性');
            combatSection.appendChild(combatGrid);
            var note = document.createElement('div');
            note.className = 'team-stat-sub';
            note.textContent = '已计入进阶方案加成；出战实体按当前难度与等级初始化，数值随难度档位变化。';
            combatSection.appendChild(note);
            _advanceLeftEl.appendChild(combatSection);
        }

        // J2：进阶方案区整体卡化——section 头带计数「进阶方案 · N」，容器撑满右栏高度；
        // 方案少时列表下一行补中性提示（纯文案零协议），0 方案给居中版空态（H2-5 同版式）
        var promoCount = countPromotions(pet);
        var promoSection = advanceSection('进阶方案 · ' + promoCount);
        promoSection.classList.add('team-promo-section');
        if (promoCount === 0) {
            promoSection.appendChild(TeamShared.buildEmptyState({
                kind: 'empty',
                statement: '该' + noun + '暂无进阶方案',
                nextStep: '更多进阶方案随等级与图鉴解锁'
            }));
        } else {
            var promoList = document.createElement('div');
            promoList.className = 'team-promos';
            renderPromotions(pet, promoList);
            promoSection.appendChild(promoList);
            if (promoCount < 3) {
                var promoMore = document.createElement('div');
                promoMore.className = 'team-promos-more';
                promoMore.textContent = '更多进阶方案随等级与图鉴解锁';
                promoSection.appendChild(promoMore);
            }
        }
        _advanceRightEl.appendChild(promoSection);
    }

    // 可解析进阶方案数（petDef.promotions 中 snapshot.schemes 命中的条数，与 renderPromotions 口径一致）
    function countPromotions(pet) {
        var petDef = getPetLibDef(pet.petId);
        if (!petDef || !petDef.promotions) return 0;
        var n = 0;
        for (var i = 0; i < petDef.promotions.length; i++) {
            if (_snapshot && _snapshot.schemes && _snapshot.schemes[petDef.promotions[i]]) n++;
        }
        return n;
    }

    // 战斗属性成长条（起点 Lv.1 → 当前 → 满级）：数据来自 AS2 snapshot.combat。
    // 返回是否有数据；无数据时调用方整块隐藏（旧 SWF 缺字段降级）。
    function renderCombatStats(pet, levelLimit, gridEl) {
        var combat = pet.combat;
        if (!combat || !combat.hp || typeof combat.hp !== 'object') return false;
        var maxLv = combat.maxLevel || levelLimit;
        var startLv = combat.startLevel || 1;
        var defs = [
            { label: '生命', d: combat.hp },
            { label: '攻击', d: combat.attack },
            { label: '防御', d: combat.defense },
            { label: '速度', d: combat.speed }
        ];
        for (var i = 0; i < defs.length; i++) {
            var d = defs[i].d || {};
            var span = (d.max || 0) - (d.start || 0);
            var pctv = span > 0 ? Math.max(0, Math.min(1, ((d.cur || 0) - (d.start || 0)) / span)) : 1;
            var cell = document.createElement('div');
            cell.className = 'team-stat';
            var head = document.createElement('div');
            head.className = 'team-stat-head';
            var lab = document.createElement('span');
            lab.className = 'team-stat-label';
            lab.textContent = defs[i].label;
            var val = document.createElement('span');
            val.className = 'team-stat-value';
            val.textContent = d.cur != null ? Number(d.cur).toLocaleString() : '--';
            head.appendChild(lab);
            head.appendChild(val);
            cell.appendChild(head);
            cell.appendChild(meterNode('', pctv));
            var ends = document.createElement('div');
            ends.className = 'team-stat-sub team-growth-ends';
            var start = document.createElement('span');
            start.textContent = 'Lv.' + startLv + ' · ' + Number(d.start != null ? d.start : 0).toLocaleString();
            var end = document.createElement('span');
            end.textContent = '满级 Lv.' + maxLv + ' · ' + Number(d.max != null ? d.max : 0).toLocaleString();
            ends.appendChild(start);
            ends.appendChild(end);
            cell.appendChild(ends);
            gridEl.appendChild(cell);
        }
        return true;
    }

    function renderPromotions(pet, listEl) {
        var noun = meta().noun;
        var petDef = getPetLibDef(pet.petId);
        if (!petDef || !petDef.promotions || petDef.promotions.length === 0) {
            var empty = document.createElement('div');
            empty.className = 'team-promo-empty';
            empty.textContent = '该' + noun + '暂无进阶方案';
            listEl.appendChild(empty);
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
            promoEl.className = 'team-promo';
            if (isMaxed) promoEl.classList.add('team-promo-maxed');
            else if (!levelOk) promoEl.classList.add('team-promo-locked');

            var statusText = '';
            var actionNode = null;

            if (isMaxed) {
                statusText = '已完成';
                actionNode = button('已完成', 'team-promo-btn', null);
                actionNode.disabled = true;
                actionNode.title = '已完成全部进阶';
            } else if (!levelOk) {
                statusText = (status && status.lockReason === 'prereq') ? '需先完成前置训练' : ('需 Lv.' + (scheme.unlockLevel || 0) + ' 解锁');
                actionNode = button('未解锁', 'team-promo-btn', null);
                actionNode.disabled = true;
                actionNode.title = statusText;
            } else if (freeToggle) {
                var tk = status ? status.toggleKind : null;
                var perMap = (scheme.type === '开关' && scheme.gold > 0);
                if (tk === 'binary') {
                    var on = !!status.toggleOn;
                    if (on) promoEl.classList.add('team-promo-on');
                    statusText = on
                        ? (perMap ? ('运行中 · 每图消耗 ' + TeamShared.fmtMoney(scheme.gold) + ' 金') : '已启用')
                        : (perMap ? ('已关闭 · 开启后每图 ' + TeamShared.fmtMoney(scheme.gold) + ' 金') : '已停用');
                    actionNode = button('', 'team-toggle' + (on ? ' team-toggle-on' : ''), null);
                    actionNode.setAttribute('aria-pressed', on ? 'true' : 'false');
                    actionNode.setAttribute('aria-label', (on ? '关闭 ' : '开启 ') + schemeName);
                    actionNode.title = '点击' + (on ? '关闭' : '开启');
                    actionNode.innerHTML = '<span class="team-toggle-track"></span><span class="team-toggle-label">'
                        + (on ? '运行中' : '已关闭') + '</span>';
                    bindPromoAction(actionNode, schemeName);
                } else if (tk === 'cycle') {
                    statusText = '点击切换';
                    var wrap = document.createElement('span');
                    wrap.className = 'team-promo-cycle';
                    var valueChip = document.createElement('span');
                    valueChip.className = 'team-promo-value-chip';
                    valueChip.textContent = status.toggleValue || '';
                    wrap.appendChild(valueChip);
                    var cycleBtn = button('切换', 'team-promo-btn', null);
                    cycleBtn.setAttribute('aria-label', '切换 ' + schemeName);
                    bindPromoAction(cycleBtn, schemeName);
                    wrap.appendChild(cycleBtn);
                    actionNode = wrap;
                } else {
                    statusText = '可切换';
                    actionNode = button(scheme.buttonText || '执行', 'team-promo-btn', null);
                    bindPromoAction(actionNode, schemeName);
                }
            } else if (!canAfford && scheme.gold > 0) {
                promoEl.classList.add('team-promo-locked');
                statusText = '金币不足';
                actionNode = button(TeamShared.fmtMoney(scheme.gold) + '金 ' + (scheme.buttonText || '执行'), 'team-promo-btn', null);
                setActionBlocked(actionNode, '金币不足（需 ' + TeamShared.fmtMoney(scheme.gold) + '）');
                actionNode.addEventListener('click', function() { guardBlocked(this); });
            } else {
                statusText = scheme.gold > 0 ? TeamShared.fmtMoney(scheme.gold) + ' 金币' : '免费';
                actionNode = button(scheme.buttonText || '执行', 'team-promo-btn', null);
                bindPromoAction(actionNode, schemeName);
            }

            var info = document.createElement('div');
            info.className = 'team-promo-info';
            var nameEl = document.createElement('div');
            nameEl.className = 'team-promo-name';
            nameEl.textContent = schemeName;
            var desc = document.createElement('div');
            desc.className = 'team-promo-desc';
            desc.textContent = (status && status.desc) || scheme.desc || '';
            var cost = document.createElement('div');
            cost.className = 'team-promo-cost';
            cost.textContent = statusText;
            info.appendChild(nameEl);
            info.appendChild(desc);
            info.appendChild(cost);
            promoEl.appendChild(info);
            var actionBox = document.createElement('div');
            actionBox.className = 'team-promo-action';
            if (actionNode) actionBox.appendChild(actionNode);
            promoEl.appendChild(actionBox);
            listEl.appendChild(promoEl);
        }
    }

    function bindPromoAction(node, schemeName) {
        node.addEventListener('click', function() { onAdvance(schemeName, this, _advanceSlot); });
    }

    // ═══════════════════════════════════════════════════════════
    // 操作处理（协议与现役逐条一致；按钮 pending + blocked 可读原因）
    // ═══════════════════════════════════════════════════════════
    function onToggleDeploy(slotIndex, btn) {
        if (guardBusy()) return;
        var pet = findPetBySlot(slotIndex);
        if (!pet) return;
        beginOp(btn);
        sendPanelMsg('deploy', { slotIndex: slotIndex }, function(data) {
            endOp(btn);
            if (data.success) {
                pet.deployed = data.deployed;
                if (_snapshot) _snapshot.currentDeployCount = data.currentDeployCount;
                updateHeaderMetrics();
                reflowCardAfterMutation(slotIndex);
                // 选中候选卡时右栏招募门控也随操作后数据重算（卡内直操不影响选中态）
                if (_selectedSlot === slotIndex || _selectedSlot === CANDIDATE_SLOT) renderDetail();
                renderAdvance();
                TeamShared.toast(pet.deployed ? '已出战' : '已休息');
            } else {
                TeamShared.toast('操作失败：' + (data.error || '未知错误'));
            }
        });
    }

    function onRestoreStamina(slotIndex, btn) {
        if (guardBusy()) return;
        var pet = findPetBySlot(slotIndex);
        if (!pet) return;
        if (pet.stamina >= (pet.maxStamina || 200)) return;
        beginOp(btn);
        sendPanelMsg('restore_stamina', { slotIndex: slotIndex }, function(data) {
            endOp(btn);
            if (data.success) {
                pet.stamina = data.stamina;
                if (_snapshot) _snapshot.gold = data.gold;
                updateHeaderMetrics();
                reflowCardAfterMutation(slotIndex);
                // 卡内直操扣金币后，选中候选卡时右栏招募门控的余额判断需重算
                if (_selectedSlot === slotIndex || _selectedSlot === CANDIDATE_SLOT) renderDetail();
                renderAdvance();
                TeamShared.toast('体力已恢复至 ' + data.stamina);
            } else {
                var msg = '恢复失败';
                if (data.error === 'insufficient_gold') msg = '金币不足，需要1000金币';
                else if (data.error === 'stamina_full') msg = '体力已满';
                else if (data.error) msg = data.error;
                TeamShared.toast(msg);
            }
        });
    }

    function onLevelUp(btn) {
        if (guardBusy()) return;
        var pet = findPetBySlot(_advanceSlot);
        if (!pet) return;
        beginOp(btn);
        sendPanelMsg('level_up', { slotIndex: pet.slotIndex }, function(data) {
            endOp(btn);
            if (data.success) {
                requestSnapshot();   // 等级变化牵动门槛，需重拉
                TeamShared.toast(meta().noun + '升级！战宠灵石 -' + data.stoneCost);
            } else {
                var msg = '升级失败';
                if (data.error === 'level_maxed') msg = '已达等级上限';
                else if (data.error === 'insufficient_stones') msg = '战宠灵石不足，需要' + (data.cost || '?') + '个';
                else if (data.error) msg = data.error;
                TeamShared.toast(msg);
            }
        });
    }

    function confirmDelete(pet) {
        if (guardBusy()) return;
        if (!_shell) return;
        var xpNeeded = pet.xpNeeded || 0;
        var refund = Math.floor(Math.sqrt(pet.level) * 0.8 * xpNeeded / 10000);
        if (isNaN(refund) || refund < 0) refund = 0;
        _shell.openModal({
            kind: 'confirm',
            kicker: meta().noun + '培养',
            title: '确认删除',
            message: '确认永久删除 ' + pet.name + '（Lv.' + pet.level + '）吗？此操作不可撤销。',
            detail: '返还战宠灵石：' + refund + ' 个',
            actions: [
                { id: 'cancel', label: '取消', audioCue: 'cancel' },
                { id: 'confirm', label: '确认删除', primary: true, danger: true, audioCue: 'confirm',
                    onSelect: function() { doDelete(pet.slotIndex); } }
            ]
        });
    }

    function doDelete(slotIndex) {
        if (guardBusy()) return;
        beginOp(null);
        sendPanelMsg('delete', { slotIndex: slotIndex }, function(data) {
            endOp(null);
            if (data.success) {
                var refundText = data.stoneRefund > 0 ? '，返还战宠灵石 ' + data.stoneRefund + ' 个' : '';
                if (_advancePage && _advancePage.isActive()) _advancePage.close('deleted');
                _selectedSlot = -1;
                TeamShared.toast('已删除' + meta().noun + refundText);
                requestSnapshot();
            } else {
                TeamShared.toast('删除失败：' + (data.error || '未知错误'));
            }
        });
    }

    // slotIndex 省略时取培养页当前宠；右栏快捷开关显式传选中 slot
    function onAdvance(schemeName, btn, slotIndex, okMsg) {
        if (guardBusy()) return;
        var slot = (slotIndex != null) ? slotIndex : _advanceSlot;
        var pet = findPetBySlot(slot);
        if (!pet) return;
        beginOp(btn);
        sendPanelMsg('advance', { slotIndex: pet.slotIndex, scheme: schemeName }, function(data) {
            endOp(btn);
            if (data.success) {
                if (_snapshot) { _snapshot.gold = data.gold; _snapshot.kpoint = data.kpoint; }
                updateHeaderMetrics();
                requestSnapshot();
                TeamShared.toast(okMsg || '进阶成功！');
            } else {
                TeamShared.toast('进阶失败：' + (data.reason || data.error || '未知错误'));
            }
        });
    }

    // 世界内招募（NPC 处，旧 Symbol 2035 宠物分支的 web 等价）：world_adopt 走 pets 通道，
    // AS2 用 _pendingHireNpc 读权威、扣费、写 宠物信息、加载宠物 + 删 NPC。回 hired:true → 关面板。
    function onWorldAdopt(btn) {
        if (guardBusy()) return;
        beginOp(btn);
        sendPanelMsg('world_adopt', {}, function(data) {
            endOp(btn);
            if (data && data.success && data.hired) {
                requestClose();   // 已加载宠物 + 删 NPC，关面板交还 Flash
                return;
            }
            var err = (data && data.error) || 'unknown';
            TeamShared.toast(({
                insufficient_gold: '金币不足',
                slots_full: '战宠栏位已满，请先删除部分战宠',
                npc_gone: 'NPC 已离开，招募取消',
                disconnected: '连接已断开'
            })[err] || ('招募失败：' + err));
        });
    }

    function onExpandSlot(btn) {
        if (guardBusy()) return;
        beginOp(btn);
        sendPanelMsg('expand_slot', null, function(data) {
            endOp(btn);
            if (data.success) {
                if (_snapshot) { _snapshot.gold = data.gold; _snapshot.maxSlots = data.maxSlots; }
                updateHeaderMetrics();
                renderRosterGrid();
                renderDetail();   // 扩容解除「栏位已满」blocked：右栏（含候选招募门控）同步重渲
                TeamShared.toast(meta().noun + '栏已扩充至 ' + data.maxSlots);
            } else {
                var msg = '扩充失败';
                if (data.error === 'max_slots_reached') msg = '已达最大格子数（' + (data.maxSlots || '') + '）';
                else if (data.error === 'insufficient_gold' || data.error === '金币不足') msg = '金币不足，无法开格子';
                else if (data.error) msg = '扩充失败：' + data.error;
                TeamShared.toast(msg);
            }
        });
    }

    // 操作锁 + 按钮 pending（TeamShared.setPending 投影）；
    // busy 期间壳根挂 data-team-busy（旧版 .pet-busy 指针锁的 workbench 等价，供皮肤层投影）
    function beginOp(btn) {
        _busy = true;
        if (btn) TeamShared.setPending(btn, true);
        if (_shell) {
            _shell.getRoot().setAttribute('data-team-busy', 'true');
            _shell.setStatus('处理中', Workbench.WorkbenchState.PENDING);
        }
    }
    function endOp(btn) {
        _busy = false;
        if (btn) TeamShared.setPending(btn, false);
        if (_shell) {
            _shell.getRoot().removeAttribute('data-team-busy');
            if (!_loadError) {
                _shell.setStatus(_snapshot ? '就绪' : '读取中',
                    _snapshot ? Workbench.WorkbenchState.READY : Workbench.WorkbenchState.LOADING);
            }
        }
    }

    // busy 守卫反馈（设计 §4：操作锁期间的用户动作不允许可点外观 + silent no-op）：
    // 所有用户动作处理器入口统一走本守卫给壳级可读状态；纯内部程序化路径仍直接判 _busy 静默返回
    function guardBusy() {
        if (!_busy) return false;
        if (_shell) _shell.setStatus('操作进行中，请稍候…', Workbench.WorkbenchState.PENDING);
        return true;
    }

    // ═══════════════════════════════════════════════════════════
    // 小构件（DOM 投影）
    // ═══════════════════════════════════════════════════════════
    function button(text, className, onClick) {
        var b = document.createElement('button');
        b.type = 'button';
        b.className = className;
        b.textContent = text;
        if (typeof onClick === 'function') b.addEventListener('click', onClick);
        return b;
    }

    function iconFrame(src, portraitOptions) {
        var icon = document.createElement('div');
        icon.className = 'team-entity-icon';
        var img = document.createElement('img');
        icon.appendChild(img);
        portraitOptions = portraitOptions || {};
        portraitOptions.legacyUrl = src;
        EnemyPortraits.mount(icon, img, portraitOptions);
        return icon;
    }

    // L 角标框挂载点（战术军械皮肤签名；纯装饰由 CSS 绘制，aria 隐藏、pointer-events:none）
    function cardFrame() {
        var frame = document.createElement('span');
        frame.className = 'team-card-frame';
        frame.setAttribute('aria-hidden', 'true');
        return frame;
    }

    function detailHead(name, sub, iconSrc, chips, portraitOptions) {
        var head = document.createElement('div');
        head.className = 'team-detail-head';
        var portrait = document.createElement('div');
        portrait.className = 'team-portrait';
        var img = document.createElement('img');
        portrait.appendChild(img);
        portraitOptions = portraitOptions || {};
        portraitOptions.legacyUrl = iconSrc;
        EnemyPortraits.mount(portrait, img, portraitOptions);
        head.appendChild(portrait);
        var main = document.createElement('div');
        main.className = 'team-detail-head-main';
        var titleRow = document.createElement('div');
        titleRow.className = 'team-detail-title-row';
        var title = document.createElement('span');
        title.className = 'team-detail-title';
        title.textContent = name;
        titleRow.appendChild(title);
        var subEl = document.createElement('span');
        subEl.className = 'team-detail-subtitle';
        subEl.textContent = sub;
        titleRow.appendChild(subEl);
        main.appendChild(titleRow);
        if (chips && chips.length) {
            var chipRow = document.createElement('div');
            chipRow.className = 'team-detail-chip-row';
            for (var i = 0; i < chips.length; i++) chipRow.appendChild(chips[i]);
            main.appendChild(chipRow);
        }
        head.appendChild(main);
        return head;
    }

    function statusChips(pet) {
        var chips = [];
        var state = document.createElement('span');
        state.className = 'team-detail-chip' + (pet.deployed ? ' team-chip-deployed' : '');
        state.textContent = pet.deployed ? '出战中' : '休息中';
        chips.push(state);
        if (pet.stamina <= 0) {
            var exhausted = document.createElement('span');
            exhausted.className = 'team-detail-chip team-chip-danger';
            exhausted.textContent = '体力耗尽';
            chips.push(exhausted);
        }
        return chips;
    }

    function meterNode(tone, ratioValue) {
        var m = document.createElement('div');
        m.className = 'team-meter';
        if (tone) m.setAttribute('data-tone', tone);
        var fill = document.createElement('div');
        fill.className = 'team-meter-fill';
        fill.style.setProperty('--team-meter-fill', String(ratioOf(ratioValue, 1)));
        m.appendChild(fill);
        return m;
    }

    function meterRow(label, tone, ratioValue, valueText) {
        var row = document.createElement('div');
        row.className = 'team-meter-row';
        var lab = document.createElement('span');
        lab.className = 'team-meter-label';
        lab.textContent = label;
        row.appendChild(lab);
        row.appendChild(meterNode(tone, ratioValue));
        var val = document.createElement('span');
        val.className = 'team-meter-val';
        val.textContent = valueText;
        row.appendChild(val);
        return row;
    }

    // Phase J 卡内 meter 行（pet full 卡；旧版分段仪表「标签 + 数值」语言回升）：
    // 与详情页 meterRow 同构——label（10px muted）+ track（卡内 8px）+ 右对齐数值
    // （chip 角色词类名走 9px 字号豁免，tabular-nums 等宽数字）；
    // 列轨由 .team-card-meter-row 自适应（卡宽比详情面窄，不用 34/1fr/64 固定轨）
    function cardMeterRow(label, tone, ratioValue, valueText) {
        var row = document.createElement('div');
        row.className = 'team-card-meter-row';
        var lab = document.createElement('span');
        lab.className = 'team-card-meter-label';
        lab.textContent = label;
        row.appendChild(lab);
        row.appendChild(meterNode(tone, ratioValue));
        var val = document.createElement('span');
        val.className = 'team-card-meter-chip';
        val.textContent = valueText;
        row.appendChild(val);
        return row;
    }

    function combatSummary(pet) {
        var combat = pet.combat;
        if (!combat || !combat.hp || typeof combat.hp !== 'object') return null;
        var defs = [
            { label: '生命', d: combat.hp },
            { label: '攻击', d: combat.attack },
            { label: '防御', d: combat.defense },
            { label: '速度', d: combat.speed }
        ];
        var grid = document.createElement('div');
        grid.className = 'team-combat-summary';
        for (var i = 0; i < defs.length; i++) {
            var cell = document.createElement('div');
            cell.className = 'team-combat-cell';
            var lab = document.createElement('span');
            lab.className = 'team-combat-label';
            lab.textContent = defs[i].label;
            var val = document.createElement('span');
            val.className = 'team-combat-value';
            var d = defs[i].d || {};
            val.textContent = d.cur != null ? Number(d.cur).toLocaleString() : '--';
            cell.appendChild(lab);
            cell.appendChild(val);
            grid.appendChild(cell);
        }
        return grid;
    }

    function advanceSection(title) {
        var sec = document.createElement('section');
        sec.className = 'team-advance-section';
        var h = document.createElement('h3');
        h.className = 'team-advance-section-title';
        h.textContent = title;
        sec.appendChild(h);
        return sec;
    }

    // blocked 投影：aria-disabled + 可读原因（title + 点击 toast），禁用 silent no-op
    function setActionBlocked(btn, reason) {
        if (reason) {
            btn.setAttribute('aria-disabled', 'true');
            btn.setAttribute('data-blocked-reason', reason);
            btn.title = reason;
        } else {
            btn.removeAttribute('aria-disabled');
            btn.removeAttribute('data-blocked-reason');
        }
    }
    function guardBlocked(btn) {
        var reason = btn.getAttribute('data-blocked-reason');
        if (reason) { TeamShared.toast(reason); return true; }
        return false;
    }

    function bindCardTip(node, textOf) {
        if (!_tooltipScope) return;
        _tooltipScope.bindAsync(node, {
            item: node,
            renderBasic: function() { return TeamShared.escapeHtml(textOf()); }
        });
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
    function findStoreItem(petId) {
        if (petId == null) return null;
        for (var i = 0; i < _storeData.length; i++) { if (_storeData[i].petId === petId) return _storeData[i]; }
        return null;
    }
    function hasPet(petId) {
        for (var i = 0; i < _pets.length; i++) { if (_pets[i].petId === petId) return true; }
        return false;
    }
    function getPetLibDef(petId) {
        if (!_petLib) return null;
        for (var i = 0; i < _petLib.length; i++) { if (_petLib[i].id === petId) return _petLib[i]; }
        return null;
    }
    function portraitContext(item, extra) {
        item = item || {};
        var def = getPetLibDef(item.petId);
        var context = {
            consumer: 'team',
            portraitRef: item.portraitRef || item.identifier || (def && (def.portraitRef || def.identifier)),
            identifier: item.identifier || (def && def.identifier),
            portraitVariant: item.portraitVariant || null,
            schemeStatus: item.schemeStatus || null
        };
        if (extra) {
            for (var key in extra) {
                if (extra.hasOwnProperty(key)) context[key] = extra[key];
            }
        }
        return context;
    }
    function rosterTypeForPet(petId) {
        var def = getPetLibDef(petId);
        return def && def.rosterType ? def.rosterType : 'pet';
    }

    function ratioOf(cur, max) {
        cur = Number(cur) || 0; max = Number(max) || 0;
        if (max <= 0) return 0;
        var p = cur / max;
        return p < 0 ? 0 : (p > 1 ? 1 : p);
    }
    function staminaTone(stamina) {
        if (stamina <= 0) return 'depleted';
        if (stamina <= 5) return 'low';
        return 'stamina';
    }
    function isMaxLevel(pet) {
        var levelLimit = _snapshot ? (_snapshot.levelLimit || 100) : 100;
        return pet.level >= levelLimit;
    }
    // I3 徽标拆分：状态字牌（左上：出战中 / 体力耗尽 danger，两字牌可共存不互斥）与
    // 满级金角标（右上 data-badge-kind=max）独立投影；满级出战卡两徽标成对同线不互挡。
    // 蓝底 MAX 字牌保持退役（H2-1），满级视觉仍与 compact 金框/金数字角标同源
    function statusBadge(pet) {
        var badges = [];
        if (pet.deployed) badges.push(buildStatusBadge('出战中', ''));
        if (pet.stamina <= 0) badges.push(buildStatusBadge('体力耗尽', 'danger'));
        return badges;
    }
    function buildStatusBadge(text, tone) {
        var badge = document.createElement('span');
        badge.className = 'team-entity-badge';
        if (tone) badge.setAttribute('data-tone', tone);
        badge.textContent = text;
        return badge;
    }
    function maxBadge(pet) {
        if (!isMaxLevel(pet)) return null;
        var badge = document.createElement('span');
        badge.className = 'team-entity-badge';
        badge.setAttribute('data-badge-kind', 'max');
        badge.textContent = 'MAX';
        return badge;
    }
    // G2 compact 等级角标（对齐物品格数量角标语言）：纯数字文本 + aria-label 完整「等级 N」
    function levelBadge(level) {
        var badge = document.createElement('span');
        badge.className = 'team-entity-lv-badge';
        badge.textContent = String(level);
        badge.setAttribute('aria-label', '等级 ' + level);
        return badge;
    }
    function cardLabel(pet) {
        return pet.name + '，Lv.' + pet.level
            + (pet.deployed ? '，出战中' : '')
            + (pet.stamina <= 0 ? '，体力耗尽' : '');
    }
    function cardTipText(pet) {
        var maxSt = pet.maxStamina || 200;
        var xpText = isMaxLevel(pet) ? 'MAX' : (Math.round(ratioOf(pet.xp, pet.xpNeeded) * 100) + '%');
        return pet.name + ' · Lv.' + pet.level
            + ' · 体力 ' + pet.stamina + '/' + maxSt
            + ' · 经验 ' + xpText
            + (pet.deployed ? ' · 出战中' : ' · 休息中')
            + (pet.stamina <= 0 ? ' · 体力耗尽' : '');
    }

    function effectivePrice(item) {
        if (_snapshot && _snapshot.priceOverrides && _snapshot.priceOverrides[item.petId] != null) {
            return _snapshot.priceOverrides[item.petId];
        }
        return item.price || 0;
    }
    function priceText(item) {
        var effPrice = effectivePrice(item);
        var text = '';
        if (effPrice > 0) text += TeamShared.fmtMoney(effPrice) + ' 金';
        if ((item.kprice || 0) > 0) { if (text) text += ' / '; text += TeamShared.fmtMoney(item.kprice) + ' K'; }
        if (!text) text = '免费';
        return text;
    }
    function isMainlineLocked(item) {
        return !!(item && item.unlockTask > 0 && _snapshot
            && item.unlockTask > (_snapshot.playerTask || 0));
    }
    // 领养门控（展示层复算；权威裁决仍在 AS2）：'' 可领养，否则可读原因
    function adoptGate(item) {
        var effPrice = effectivePrice(item);
        if (!_snapshot) return '数据未就绪';
        if (item.unlockTask > 0 && item.unlockTask > (_snapshot.playerTask || 0)) return '需主线 ' + item.unlockTask;
        if (item.unlockLevel > (_snapshot.playerLevel || 0)) return '需 Lv.' + item.unlockLevel;
        if (item.unique && hasPet(item.petId)) return '已拥有';
        if (_pets.length >= (_snapshot.maxSlots || 0)) return meta().noun + '栏已满';
        if (effPrice > 0 && (_snapshot.gold || 0) < effPrice) return '金币不足';
        if ((item.kprice || 0) > 0 && (_snapshot.kpoint || 0) < item.kprice) return 'K点不足';
        return '';
    }

    // ═══════════════════════════════════════════════════════════
    // 导出
    // ═══════════════════════════════════════════════════════════
    function resetToList() {
        if (_advancePage && _advancePage.isActive()) _advancePage.close('reset');
        backToRoster();
    }

    // 测试 / 调试用
    if (typeof window !== 'undefined') {
        window.PetPanel = {
            getState: function() {
                return {
                    view: _view,
                    rosterType: _rosterType,
                    pets: _pets.length,
                    selected: _selectedSlot,
                    busy: _busy,
                    sort: _sortMode,
                    filter: _filterMode
                };
            }
        };
    }
    window.PetTeamController = {
        create: createDOM,
        onOpen: onOpen,
        onClose: onClose,
        requestClose: requestClose,
        resetToList: resetToList,
        isBusy: function() { return _busy; }
    };
})();
