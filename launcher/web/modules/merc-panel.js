/**
 * MercTeamController — 佣兵 tab 的双栏工作台控制器（Phase C 重写，结构对齐 pet-panel.js）。
 *
 * 视图地图（设计 §3.2，profile = catalog-decision）：
 *  - roster（默认）：左栏名册（K-A 起单栏宽行卡 buildMercRowCard：小纸娃娃头像 +
 *    名称/元信息 + 装备带 11 槽 + 右侧直操——Phase J 起技能带下卡，对齐旧版
 *    「技能不上卡」，技能详情由右栏 / 培养页承担；世界内雇佣候选置顶带「候选」
 *    标识；名册网格挂 GridDensityController panelId='team-merc'，compact 收成
 *    [小头像 + 名称/等级 + 迷你装备行] 宽行），右栏决策面（中号纸娃娃、名称/等级/状态、
 *    关键属性摘要、出战 · 休息（阵亡→复活 · 复活币×1）、「培养 →」）；
 *  - hire（雇佣市场）：左栏等级定位 chips + 无缝下滑佣兵池（触底加载、哨兵行、按等级升序；
 *    网格挂同一 GridDensityController；卡与名册同 buildMercRowCard 骨架，右侧区改价格牌），
 *    右栏候选预览对齐培养页
 *    信息量（纸娃娃 / 性格特质六维 / 战斗技能全量 / 装备格只读 / 价格）+ CommitBar 唯一主 CTA「确认雇佣」；
 *  - detail（培养）：SecondaryPage 覆盖 body（两栏：左栏纸娃娃整列 + 内嵌 inspection 相机
 *    （K-B-2 起控件横排置顶于造型预览 section 内顶缘，视口全宽展示；
 *    滚轮 / 拖拽 / 键盘缩放平移，transform 只作用 exact Canvas，退出培养页即停用清零），
 *    右栏纵向滚动列依次 性格特质 → 战斗技能 → 装备调配只读 11 槽；出战/复活、解雇在 header）。
 *
 * 协议零改动（AS2 为数据权威，JS 纯展示层）：panel='mercs'；cmd 全集保持
 * snapshot / hire_list / hire / deploy / dismiss / revive / equip_tooltip，
 * 以及世界内雇佣通道 world_hire（消息与错误码映射照原样）；
 * callId 请求-响应、_pendingReq、_session 迟到回包守卫语义原样保留。
 */
(function() {
    'use strict';

    // ── 依赖 fail-fast：缺共享层直接报错，不做半初始化 ──
    // MercPortraits 内部仍对 DressupDollRenderer / AssetTimeline 缺失做 fail-soft；这里只守共享入口。
    if (typeof TeamShared === 'undefined'
            || typeof Workbench === 'undefined'
            || typeof WorkbenchComponents === 'undefined'
            || typeof PanelScale === 'undefined'
            || typeof MercData === 'undefined'
            || typeof MercPortraits === 'undefined') {
        throw new Error('merc-panel.js 需要先加载 team/team-shared.js、workbench 共享层、panel-scale.js、merc-data.js 与 merc-portrait-renderer.js');
    }

    var DESIGN_W = 1024;
    var DESIGN_H = 576;
    var CANDIDATE_SLOT = -2;        // 世界内雇佣候选的选中哨兵（真实 slotIndex ≥ 0，-1 为未选中）
    var LEVEL_JUMPS = [20, 40, 60, 80];
    var HIRE_SCROLL_TRIGGER = 220;  // 距底部多少 px 触发无缝加载（与现役一致）

    // 培养页 live canvas 复用共享 MercPortraits 状态构建；卡片/右栏快照也统一走该模块。
    var DRESSUP_BODY_FIT_FIELDS = MercPortraits.BODY_FIT_FIELDS;
    var DRESSUP_BATTLE_STATE = MercPortraits.BATTLE_STATE;

    // ── 状态 ──
    var _el = null, _scaleEl = null, _scaleHandle = null;
    var _shell = null, _helpAction = null, _density = null, _densityToggle = null;
    var _tooltipScope = null;
    var _closeButton = null;

    var _snapshot = null;
    var _hiredMercs = [];
    var _pendingReq = {};
    var _reqSeq = 0;
    var _session = 0;
    var _busy = false;
    var _hireCandidate = null;      // 世界内雇佣候选（NPC 处，置顶在 roster 顶部的卡；null=普通管理）
    var _firstSnapshot = true;
    var _loadError = '';

    var _view = 'roster';           // roster | hire
    var _selectedSlot = -1;         // -1 未选中；CANDIDATE_SLOT 候选；否则 slotIndex
    var _ttCache = {};              // (raw|level) → {descHTML, introHTML, displayname, itemName}（协议缓存原样）

    // 雇佣市场（无缝下滑分页）
    var _hirePage = 1;
    var _hireTotalPages = 1;
    var _hireTotalCount = 0;
    var _hireMinLevel = 0;          // 等级快速定位：0=全部，>0 时首次请求带 minLevel 让 AS2 跳页
    var _hireMaxLevel = 0;          // 可见池最高等级（回包下发，用于禁用超出范围的定位钮）
    var _hireData = [];
    var _hireLoaded = false;        // 首包已返回（区分「加载中」与「真空池」）
    var _hireError = '';
    var _selectedPoolIdx = -1;

    // DOM refs / 视图对象
    var _rosterLeftRoot = null, _rosterRightRoot = null;
    var _hireLeftRoot = null, _hireRightRoot = null;
    var _gridEl = null, _rosterScrollEl = null, _detailEl = null;
    var _hireChipsEl = null, _hireGridEl = null, _hireScrollEl = null, _hireSentinelEl = null, _hirePreviewEl = null;
    var _rosterL = null, _rosterR = null, _hireL = null, _hireR = null;
    var _commitBar = null;
    var _detailPage = null, _detailBodyEl = null, _detailTitleEl = null, _detailChipsEl = null;
    var _detailActionsEl = null, _detailDressupHost = null;
    var _detailRightEl = null, _detailDollViewport = null, _detailDollControls = null;
    var _detailCamera = null;       // 内嵌 inspection 瞬态相机（随 detail canvas 建销）
    var _detailSlot = -1;

    // 培养页保留单个 live renderer；卡片/右栏快照由共享 MercPortraits 缓存与销毁。
    var _dressupManifest = null;
    var _dressupDetailRenderer = null;
    var _dressupDetailCanvas = null;

    // ═══════════════════════════════════════════════════════════
    // DOM 创建 / 生命周期
    // ═══════════════════════════════════════════════════════════
    function createDOM(container) {
        _el = document.createElement('div');
        _el.className = 'team-child team-merc-child';
        _scaleEl = document.createElement('div');
        _scaleEl.className = 'panel-scale-shell team-merc-scale-shell';
        _el.appendChild(_scaleEl);
        container.appendChild(_el);
        return _el;
    }

    function onOpen(el, initData) {
        initData = initData || {};
        _session++;
        _hireCandidate = initData.hireCandidate || null;
        _pendingReq = {};
        _busy = false;
        _snapshot = null;
        _hiredMercs = [];
        _hirePage = 1;
        _hireTotalPages = 1;
        _hireTotalCount = 0;
        _hireMinLevel = 0;
        _hireMaxLevel = 0;
        _hireData = [];
        _hireLoaded = false;
        _hireError = '';
        _selectedSlot = _hireCandidate ? CANDIDATE_SLOT : -1;
        _selectedPoolIdx = -1;
        _detailSlot = -1;
        _ttCache = {};
        _firstSnapshot = true;
        _loadError = '';

        teardownView(false);
        _tooltipScope = (typeof PanelTooltip !== 'undefined' && PanelTooltip && PanelTooltip.createScope)
            ? PanelTooltip.createScope('team-merc', {profile:'simple-tooltip'}) : null;
        buildShell(initData);
        buildRosterViews();
        _shell.mountInitial(_rosterL, _rosterR);
        if (_scaleHandle) { _scaleHandle.detach(); _scaleHandle = null; }
        _scaleHandle = PanelScale.attach(_scaleEl, DESIGN_W, DESIGN_H);
        _shell.setStatus('读取中', Workbench.WorkbenchState.LOADING);
        renderRosterGrid();
        renderDetail();
        requestSnapshot();
        // 预加载图标 manifest（首次打开且未加载时发起 fetch，与其他面板共享缓存）
        if (typeof Icons !== 'undefined') Icons.load(function(){});
    }

    function onClose() {
        _session++;
        _pendingReq = {};
        _busy = false;
        _snapshot = null;
        _hiredMercs = [];
        _hireData = [];
        _ttCache = {};
        // MercPortraits 的着装快照缓存跨面板会话复用；节点 token 会阻断迟到渲染。
        _selectedSlot = -1;
        _selectedPoolIdx = -1;
        _detailSlot = -1;
        teardownView(true);
        if (typeof PanelTooltip !== 'undefined' && PanelTooltip && PanelTooltip.hide) PanelTooltip.hide();
    }

    function requestClose() {
        // pending 操作期间阻止关闭，防止状态泄漏（对齐 pet 模式）；用户动作守卫给可读反馈
        if (_busy) { notifyBusy(); return; }
        if (window.TeamPanelHost && TeamPanelHost.requestClose) {
            TeamPanelHost.requestClose();
            return;
        }
        Panels.close();     // 先触发 onClose 清理 JS 状态（tooltip/缓存/pendingReq），再通知 C#
        Bridge.send({ type: 'panel', panel: 'mercs', cmd: 'close' });
    }

    // 视图 teardown：销毁壳 / 组件 / tooltip 域 / 纸娃娃 live canvas，清空 DOM 引用；幂等。
    function teardownView(detachScale) {
        destroyDetailDressup();
        if (_density) { _density.destroy(); _density = null; }
        _densityToggle = null;
        if (_detailPage) { _detailPage.destroy(); _detailPage = null; }
        _detailBodyEl = null; _detailTitleEl = null; _detailChipsEl = null;
        _detailActionsEl = null; _detailDressupHost = null;
        _detailRightEl = null; _detailDollViewport = null; _detailDollControls = null;
        if (_commitBar) { _commitBar.destroy(); _commitBar = null; }
        if (_helpAction) { _helpAction.destroy(); _helpAction = null; }
        if (_tooltipScope) { _tooltipScope.dispose(); _tooltipScope = null; }
        if (_shell) { _shell.destroy(); _shell = null; }
        _closeButton = null;
        _rosterL = null; _rosterR = null; _hireL = null; _hireR = null;
        _rosterLeftRoot = null; _rosterRightRoot = null;
        _hireLeftRoot = null; _hireRightRoot = null;
        _gridEl = null; _rosterScrollEl = null; _detailEl = null;
        _hireChipsEl = null; _hireGridEl = null; _hireScrollEl = null;
        _hireSentinelEl = null; _hirePreviewEl = null;
        _view = 'roster';
        if (_scaleEl) Workbench.clearElement(_scaleEl);
        if (detachScale !== false && _scaleHandle) { _scaleHandle.detach(); _scaleHandle = null; }
    }

    // ═══════════════════════════════════════════════════════════
    // 壳与 header（tab 条 → 密度切换 → 帮助 → 关闭）
    // ═══════════════════════════════════════════════════════════
    function buildShell(initData) {
        _shell = new Workbench.DualPaneShell({
            profile: 'catalog-decision',
            title: '佣兵管理',
            subtitle: '',
            status: '读取中',
            leftLabel: '名册',
            rightLabel: '决策',
            flowLabel: '佣兵',
            eyebrow: '战队',
            // 官方 opt-out（WB129 合规）：pane 自带单行控件条承担标签职能，关闭壳级 L/R marker
            slotMarkers: false
        });
        var root = _shell.getRoot();
        root.classList.add('team-workbench');
        root.setAttribute('data-workbench-skin', 'team');
        root.setAttribute('data-team-roster', 'mercenary');
        _scaleEl.appendChild(root);

        // header actions 顺序固定：tab 条（team 壳层传入，必须是第一个）→ 密度切换 → 帮助 → 关闭
        if (initData.tabNav) _shell.addHeaderAction(initData.tabNav);

        _density = new Workbench.GridDensityController({ panelId: 'team-merc', compactClass: 'team-grid-compact' });
        _densityToggle = _density.createToggle();
        _densityToggle.setAttribute('aria-label', '佣兵名册布局');
        var densityLabel = _densityToggle.querySelector('.item-grid-mode-label');
        if (densityLabel) densityLabel.textContent = '名册';
        _shell.addHeaderAction(_densityToggle);

        _helpAction = new WorkbenchComponents.HelpAction({ shell: _shell, spec: helpSpec() });

        _closeButton = button('×', 'workbench-close-btn', requestClose);
        _closeButton.setAttribute('aria-label', '关闭战队面板');
        _closeButton.setAttribute('data-audio-cue', 'cancel');
        _shell.addHeaderAction(_closeButton);
    }

    function helpSpec() {
        return {
            kind: 'workbench-help',
            kicker: '战队',
            title: '佣兵管理帮助',
            ariaLabel: '佣兵管理帮助',
            message: '名册点选佣兵卡后，右栏可出战 · 休息（阵亡佣兵改为复活，消耗 1 枚复活币，余额不足会写明原因）、'
                + '查看性格特质 / 战斗技能 / 装备概要；「培养 →」进入培养页查看造型预览、六维特质、完整技能与'
                + '装备调配（更换功能筹备中），解雇也在培养页。',
            detail: '「＋ 雇佣佣兵」打开雇佣市场：左侧按等级定位（全部 / Lv.20+ / 40+ / 60+ / 80+）并无缝下滑浏览，'
                + '右侧确认价格与余额后提交唯一「确认雇佣」。佣兵栏已满 / 金币不足 / K点不足会写明原因且不可提交；'
                + '世界内雇佣候选以「候选」卡置顶，契约金满足即可在右栏确认。'
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
        _rosterLeftRoot = document.createElement('div');
        _rosterLeftRoot.className = 'workbench-view team-merc-view';
        // Phase F 排版收紧 + Phase G1 壳级 marker opt-out：pane 内不再重复大标题，
        // chrome 收敛为单行控件条（雇佣入口）
        var paneHeader = document.createElement('div');
        paneHeader.className = 'team-pane-header';
        var tools = document.createElement('div');
        tools.className = 'team-pane-tools';
        var hireEntry = button('＋ 雇佣佣兵', 'team-pane-btn team-goto-hire', enterHire);
        hireEntry.setAttribute('data-tone', 'primary');
        hireEntry.setAttribute('aria-label', '打开雇佣市场');
        hireEntry.setAttribute('data-audio-cue', 'confirm');
        tools.appendChild(hireEntry);
        paneHeader.appendChild(tools);
        _rosterLeftRoot.appendChild(paneHeader);

        _rosterScrollEl = document.createElement('div');
        _rosterScrollEl.className = 'team-scroll team-merc-roster-scroll';
        _rosterScrollEl.setAttribute('data-scroll-region', '');
        _gridEl = document.createElement('div');
        _gridEl.className = 'team-entity-grid team-merc-grid';
        // 卡内嵌直操真按钮，APG 明确 listbox/option 不包容嵌套交互控件——
        // 容器投 role=list，EntityTile 卡为 role=listitem（选中态 aria-current，见 fixupCardA11y）
        _gridEl.setAttribute('role', 'list');
        _gridEl.setAttribute('aria-label', '佣兵名册');
        _rosterScrollEl.appendChild(_gridEl);
        _rosterLeftRoot.appendChild(_rosterScrollEl);
        _density.register(_gridEl);

        _rosterRightRoot = document.createElement('div');
        _rosterRightRoot.className = 'workbench-view team-merc-view';
        _detailEl = document.createElement('div');
        _detailEl.className = 'team-scroll team-merc-detail';
        _detailEl.setAttribute('data-scroll-region', '');
        _rosterRightRoot.appendChild(_detailEl);

        _rosterL = simpleView('team-merc:roster', 'catalog', ['L'], _rosterLeftRoot, renderRosterGrid);
        _rosterR = simpleView('team-merc:decision', 'detail', ['R'], _rosterRightRoot, renderDetail);
    }

    function buildHireViews() {
        _hireLeftRoot = document.createElement('div');
        _hireLeftRoot.className = 'workbench-view team-merc-view';
        // Phase F 排版收紧：hire 页头并条——返回钮 + 等级 chips + 升序说明同一行 chrome（去掉大标题）
        var paneHeader = document.createElement('div');
        paneHeader.className = 'team-pane-header';
        var backBtn = button('‹ 返回名册', 'team-pane-btn team-back-roster', backToRoster);
        backBtn.setAttribute('aria-label', '返回佣兵名册');
        backBtn.setAttribute('data-audio-cue', 'cancel');
        paneHeader.appendChild(backBtn);

        // 等级快速定位：池按等级升序，chip 跳到对应区间起点（保持无缝下滑）
        _hireChipsEl = document.createElement('div');
        _hireChipsEl.className = 'team-merc-hire-chips';
        _hireChipsEl.setAttribute('role', 'group');
        _hireChipsEl.setAttribute('aria-label', '等级定位');
        appendLevelChip(_hireChipsEl, 0, '全部');
        for (var i = 0; i < LEVEL_JUMPS.length; i++) {
            appendLevelChip(_hireChipsEl, LEVEL_JUMPS[i], 'Lv.' + LEVEL_JUMPS[i] + '+');
        }
        var sortNote = document.createElement('span');
        sortNote.className = 'team-merc-hire-note';
        sortNote.textContent = '按等级升序';
        _hireChipsEl.appendChild(sortNote);
        paneHeader.appendChild(_hireChipsEl);
        _hireLeftRoot.appendChild(paneHeader);

        _hireScrollEl = document.createElement('div');
        _hireScrollEl.className = 'team-scroll team-merc-hire-scroll';
        _hireScrollEl.setAttribute('data-scroll-region', '');
        _hireGridEl = document.createElement('div');
        _hireGridEl.className = 'team-entity-grid team-merc-hire-grid';
        // 同名册网格（外审二轮 P2-4）：listbox→list，EntityTile 卡为 role=listitem
        _hireGridEl.setAttribute('role', 'list');
        _hireGridEl.setAttribute('aria-label', '可雇佣佣兵列表');
        _hireScrollEl.appendChild(_hireGridEl);
        // H2-4：hire 与 roster 共享同一密度状态（同 panelId='team-merc'），
        // compact 时 hire 卡收为紧凑行（头像小 + 名称/等级/价格一行），full 保持现状
        _density.register(_hireGridEl);
        // 无缝下滑：滚动触底自动加载下一页（哨兵行提示进度），无分页按钮
        _hireSentinelEl = document.createElement('div');
        _hireSentinelEl.className = 'team-merc-hire-more';
        _hireSentinelEl.hidden = true;
        _hireScrollEl.appendChild(_hireSentinelEl);
        _hireScrollEl.addEventListener('scroll', onHireScroll);
        _hireLeftRoot.appendChild(_hireScrollEl);

        _hireRightRoot = document.createElement('div');
        _hireRightRoot.className = 'workbench-view team-merc-view team-merc-hire-decision';
        _hirePreviewEl = document.createElement('div');
        _hirePreviewEl.className = 'team-scroll team-merc-hire-preview';
        _hirePreviewEl.setAttribute('data-scroll-region', '');
        _hireRightRoot.appendChild(_hirePreviewEl);
        _commitBar = new WorkbenchComponents.CommitBar({
            label: '确认雇佣',
            status: '选择左侧目标后确认',
            disabled: true,
            onCommit: onCommitHire
        });
        _commitBar.primaryButton.setAttribute('data-tone', 'primary');
        _commitBar.mount(_hireRightRoot);

        _hireL = simpleView('team-merc:hire-catalog', 'catalog', ['L'], _hireLeftRoot, renderHireGrid);
        _hireR = simpleView('team-merc:hire-commit', 'detail', ['R'], _hireRightRoot, renderHirePreview);
        updateLevelChips();
    }

    function appendLevelChip(host, min, label) {
        var chip = button(label, 'team-merc-lvl-chip', null);
        chip.setAttribute('data-min', String(min));
        chip.setAttribute('aria-pressed', min === _hireMinLevel ? 'true' : 'false');
        chip.setAttribute('aria-label', '等级定位 ' + label);
        chip.addEventListener('click', function() { onLevelChip(this); });
        host.appendChild(chip);
    }

    // ═══════════════════════════════════════════════════════════
    // 通信（协议零改动：panel='mercs' + callId 请求-响应 + session 守卫）
    // ═══════════════════════════════════════════════════════════
    Bridge.on('panel_resp', function(data) {
        if (!data || data.panel !== 'mercs') return;
        var handler = _pendingReq[data.callId];
        if (handler) {
            delete _pendingReq[data.callId];
            if (typeof handler === 'function') handler(data);
        }
    });

    function sendPanelMsg(cmd, extra, cb) {
        var callId = 'merc_' + (++_reqSeq) + '_' + Date.now();
        if (cb) _pendingReq[callId] = cb;
        var msg = { type: 'panel', panel: 'mercs', cmd: cmd, callId: callId };
        if (extra) {
            Object.keys(extra).forEach(function(k) { msg[k] = extra[k]; });
        }
        Bridge.send(msg);
        return callId;
    }

    function requestSnapshot() {
        var snapSession = _session;
        sendPanelMsg('snapshot', null, function(data) {
            if (snapSession !== _session) return;
            if (!data.success) {
                _loadError = '获取佣兵数据失败：' + (data.error || '未知错误');
                if (_shell) _shell.setStatus('读取失败', Workbench.WorkbenchState.ERROR);
                TeamShared.toast(_loadError);
                renderRosterGrid();
                return;
            }
            _snapshot = data.snapshot;
            _hiredMercs = _snapshot.hiredMercs || [];
            _firstSnapshot = false;
            _loadError = '';
            // 默认选中：保留旧选中（若仍在），否则候选优先、再次首个佣兵
            if (_selectedSlot !== CANDIDATE_SLOT && !findMercBySlot(_selectedSlot)) {
                _selectedSlot = _hireCandidate ? CANDIDATE_SLOT : defaultSelectSlot();
            }
            updateHeaderMetrics();
            if (_shell) _shell.setStatus('就绪', Workbench.WorkbenchState.READY);
            renderRosterGrid();
            renderDetail();
            renderDetailPage();
            // 雇佣失败对账重拉后，hire 右栏余额 / 门控显示值同步刷新
            if (_view === 'hire') renderHirePreview();
        });
    }

    // ═══════════════════════════════════════════════════════════
    // roster 视图：名册网格（EntityTile 卡 + 世界内候选置顶）
    // ═══════════════════════════════════════════════════════════
    function renderRosterGrid() {
        if (!_gridEl) return;
        var prevScroll = _rosterScrollEl ? _rosterScrollEl.scrollTop : 0;
        var focusSlot = null;
        if (typeof document !== 'undefined' && document.activeElement && _gridEl.contains(document.activeElement)) {
            var focusCard = document.activeElement.closest ? document.activeElement.closest('.team-merc-card') : null;
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
        } else if (!_snapshot) {
            if (_firstSnapshot) appendSkeleton(_gridEl);
        } else {
            if (_hireCandidate) _gridEl.appendChild(buildCandidateCard(_hireCandidate));
            if (_hiredMercs.length === 0) {
                if (!_hireCandidate) _gridEl.appendChild(rosterEmptyState());
            } else {
                for (var i = 0; i < _hiredMercs.length; i++) {
                    _gridEl.appendChild(buildMercCard(_hiredMercs[i]));
                }
            }
        }
        if (_rosterScrollEl) _rosterScrollEl.scrollTop = prevScroll;
        if (focusSlot != null) {
            var again = _gridEl.querySelector('.team-merc-card[data-slot="' + focusSlot + '"]');
            if (again) again.focus();
        }
    }

    function appendSkeleton(grid) {
        // K-A 单栏宽行：5 条骨架对应一屏容量（原 8 条是 4 列网格时代）
        for (var i = 0; i < 5; i++) {
            var cell = document.createElement('div');
            cell.className = 'team-skel-card';
            // 骨架是纯加载装饰：aria-hidden 移出 list 语义树
            cell.setAttribute('aria-hidden', 'true');
            grid.appendChild(cell);
        }
    }

    function rosterEmptyState() {
        // H2-5 人文向文案：statement 变化 + nextStep 指回雇佣入口（居中版式由 team.css 承担）
        var node = TeamShared.buildEmptyState({
            kind: 'empty',
            statement: '佣兵名册空空如也',
            nextStep: '点「＋ 雇佣佣兵」，迎接第一位同行的佣兵'
        });
        // list 容器内空态为纯展示：默认语义即可，不再投 role=option
        return node;
    }

    function errorEmptyState(statement, onRetry) {
        var node = TeamShared.buildEmptyState({
            kind: 'error',
            statement: statement,
            nextStep: '检查连接后重试'
        });
        // 同上：不投 role=option（重试钮自身是真 button，不借容器语义）
        node.appendChild(button('重试', 'team-pane-btn team-empty-retry', onRetry));
        return node;
    }

    // ═══════════════════════════════════════════════════════════
    // K-A 统一宽行卡（名册 / 雇佣 / 世界内候选同骨架，单栏一排一个）：
    //   [头像][信息块 名称+元信息][图标带块 装备带（Phase J 技能带下卡）][右侧区]
    // 右侧区按 mode 分野：roster = 卡内直操（出战/休息·复活 + 解雇）；
    // hire / candidate = 价格牌（选中进右栏预览，无按钮——购买走 CommitBar，
    // 候选走右栏确认雇佣）。full / compact 双态 DOM 一并投影（图标带 + 迷你
    // 装备行），显隐由 team.css 随 .team-grid-compact 切换；EntityTile 语义、
    // 嵌套按钮纪律、徽标角标对几何与原卡一致。
    // ═══════════════════════════════════════════════════════════
    function buildMercRowCard(merc, opts) {
        opts = opts || {};
        var mode = opts.mode || 'roster';   // roster | hire | candidate
        var gate = opts.gate || '';
        var card = document.createElement('div');
        card.className = 'team-entity-card team-merc-card team-merc-rowcard'
            + (mode === 'hire' ? ' team-merc-hire-card' : '')
            + (mode === 'candidate' ? ' team-merc-card-candidate' : '')
            + (mode === 'roster' && merc.dead ? ' team-merc-card-dead' : '');
        if (mode === 'hire') card.setAttribute('data-pool-idx', merc.poolIndex);
        else card.setAttribute('data-slot', mode === 'candidate' ? String(CANDIDATE_SLOT) : merc.slotIndex);

        var icon = document.createElement('div');
        icon.className = 'team-entity-icon team-merc-icon';
        icon.appendChild(createPortrait(merc, 'card'));
        card.appendChild(icon);
        card.appendChild(cardFrame());

        // 信息块：名称 + 元信息行（等级 / 性别·身高；价格不进 meta，由右侧价格牌承担）。
        // K-A 满级：MAX 金 chip 投 meta 行首顶替等级数字（宽行右上被按钮列占据，
        // 角标无落点；compact 由 SHARED 规则藏 chip、等级数字回显 + 金框/金角标承担）
        var body = document.createElement('div');
        body.className = 'team-entity-body';
        var name = document.createElement('div');
        name.className = 'team-entity-name';
        name.textContent = merc.name;
        body.appendChild(name);
        var metaLine = document.createElement('div');
        metaLine.className = 'team-entity-meta';
        if (mode === 'roster') {
            var maxChip = maxBadge(merc);
            if (maxChip) metaLine.appendChild(maxChip);
            var lvNum = document.createElement('span');
            lvNum.className = 'team-merc-lv-num';
            lvNum.textContent = 'Lv.' + merc.level;
            metaLine.appendChild(lvNum);
            metaLine.appendChild(document.createTextNode(' · ' + (merc.gender || '')
                + (merc.height ? ' · ' + merc.height + 'cm' : '')));
        } else {
            metaLine.textContent = 'Lv.' + merc.level + ' · ' + (merc.gender || '')
                + (merc.height ? ' · ' + merc.height + 'cm' : '');
        }
        body.appendChild(metaLine);
        card.appendChild(body);

        // 图标带块：装备带 11 槽（compact 由 CSS 整隐）。
        // Phase J 视觉对齐：技能带下卡——对齐旧版「技能不上卡」降噪（技能详情由右栏
        // 决策面技能流 / 培养页承担，见 buildSkillBlock），宽行只留装备带
        var bands = document.createElement('div');
        bands.className = 'team-merc-row-bands';
        bands.appendChild(buildEquipBand(merc));
        card.appendChild(bands);
        // K-A compact 迷你装备行：与 full 带同构件（buildEquipCell = 烘焙图标/占位
        // + 强化等级角标 + scope rich tooltip），仅装备、CSS 收 15px；技能不进 compact
        card.appendChild(buildMiniEquipStrip(merc));

        // 右侧区：roster 直操按钮列 / hire·candidate 价格牌
        if (mode === 'roster') card.appendChild(buildCardActions(merc));
        else card.appendChild(buildRowPriceTag(merc, mode));

        // 徽标区：状态字牌左上（roster）；候选字牌左上（candidate）；
        // MAX 金 chip 已在 meta 行（见上）；compact 等级数字角标 roster 保留
        //（hire/candidate 等级由 meta 行承担）
        if (mode === 'candidate') {
            var candBadge = document.createElement('span');
            candBadge.className = 'team-entity-badge';
            candBadge.setAttribute('data-tone', 'info');
            candBadge.textContent = '候选';
            card.appendChild(candBadge);
        } else if (mode === 'roster') {
            var badge = statusBadge(merc);
            if (badge) card.appendChild(badge);
            card.appendChild(levelBadge(merc.level));
            if (isMaxLevel(merc)) card.setAttribute('data-level-max', 'true');
        }

        // EntityTile 激活语义 + 卡级 tip（与格级 tip 共存由 PanelTooltip 嵌套守卫保证）
        if (mode === 'roster') {
            Workbench.EntityTile.bindActivation(card, {
                itemName: merc.name,
                label: cardLabel(merc),
                role: 'listitem',
                selected: merc.slotIndex === _selectedSlot,
                onActivate: function() { selectMerc(merc.slotIndex); }
            });
            fixupCardA11y(card, merc.slotIndex === _selectedSlot);
            if (merc.slotIndex === _selectedSlot) card.setAttribute('data-state', 'selected');
            bindCardTip(card, function() { return cardTipText(merc); });
        } else if (mode === 'hire') {
            Workbench.EntityTile.bindActivation(card, {
                itemName: merc.name,
                label: merc.name + '，' + priceText(merc),
                role: 'listitem',
                selected: merc.poolIndex === _selectedPoolIdx,
                actionable: true,   // 选候选是本地 browse（零写入）；门控由右栏 CommitBar 阻断
                reason: gate,
                onActivate: function() { selectHire(merc.poolIndex); }
            });
            fixupCardA11y(card, merc.poolIndex === _selectedPoolIdx);
            if (merc.poolIndex === _selectedPoolIdx) card.setAttribute('data-state', 'selected');
            else if (gate) card.setAttribute('data-state', 'blocked');
            bindCardTip(card, function() {
                return merc.name + ' · ' + priceText(merc) + (gate ? ' · ' + gate : ' · 可雇佣');
            });
        } else {
            Workbench.EntityTile.bindActivation(card, {
                itemName: merc.name,
                label: '雇佣候选 ' + merc.name + '，Lv.' + merc.level,
                role: 'listitem',
                selected: _selectedSlot === CANDIDATE_SLOT,
                onActivate: function() { selectMerc(CANDIDATE_SLOT); }
            });
            fixupCardA11y(card, _selectedSlot === CANDIDATE_SLOT);
            if (_selectedSlot === CANDIDATE_SLOT) card.setAttribute('data-state', 'selected');
            bindCardTip(card, function() {
                return '雇佣候选 ' + merc.name + ' · Lv.' + merc.level + ' · 契约金 ' + TeamShared.fmtMoney(merc.goldPrice);
            });
        }
        return card;
    }

    function buildMercCard(merc) { return buildMercRowCard(merc, { mode: 'roster' }); }

    // 雇佣卡：与名册卡同骨架同组件；blocked 候选仍可预览（browse 零写入），
    // 门控原因由右栏 CommitBar 投影
    function buildHireCard(merc) { return buildMercRowCard(merc, { mode: 'hire', gate: hireGate(merc) }); }

    // 世界内雇佣候选卡（旧 Symbol 2035 的 web 等价）：置顶在现役上方 + 「候选」标识；
    // 门控在右栏决策面按实时 snapshot 复算
    function buildCandidateCard(cand) { return buildMercRowCard(cand, { mode: 'candidate' }); }

    // hire / candidate 右侧价格牌（roster 右侧是直操按钮列，见 buildCardActions）：
    // 金币 / K点分币种植行（nowrap），避免「200 K」被折行拆散
    function buildRowPriceTag(merc, mode) {
        var tag = document.createElement('div');
        tag.className = 'team-merc-row-price';
        var label = document.createElement('span');
        label.className = 'team-merc-row-price-label';
        label.textContent = mode === 'candidate' ? '契约金' : '价格';
        tag.appendChild(label);
        var parts = [];
        if ((merc.goldPrice || 0) > 0) parts.push(TeamShared.fmtMoney(merc.goldPrice) + ' 金');
        if ((merc.kPrice || 0) > 0) parts.push(TeamShared.fmtMoney(merc.kPrice) + ' K');
        if (!parts.length) parts.push('免费');
        for (var i = 0; i < parts.length; i++) {
            var val = document.createElement('span');
            val.className = 'team-merc-row-price-val';
            val.textContent = parts[i];
            tag.appendChild(val);
        }
        return tag;
    }

    // 宽行卡装备带：11 槽固定图标带（复用 buildEquipCell 烘焙图标/占位回退/
    // 强化等级小角标/scope tooltip；空槽 = 虚线空格 + title 槽位名）。
    // 行内尺寸由 team.css 卡作用域收成 20px（detail / hire 预览 32px 规格不动）。
    // Phase J：同卡技能带（buildSkillBand）已随「技能不上卡」下卡删除——技能详情
    // 由右栏决策面技能流（buildSkillBlock）/ 培养页承担。
    function buildEquipBand(merc) {
        var band = document.createElement('div');
        band.className = 'team-entity-iconband team-merc-card-equips';
        var equipBySlot = {};
        if (merc.equips) {
            for (var e = 0; e < merc.equips.length; e++) equipBySlot[merc.equips[e].slot] = merc.equips[e];
        }
        var SLOTS = MercData.SLOTS, SLOT_NAMES = MercData.SLOT_NAMES;
        for (var i = 0; i < SLOTS.length; i++) {
            var slot = SLOTS[i];
            var eq = equipBySlot[slot];
            if (eq) {
                band.appendChild(buildEquipCell(eq));
            } else {
                var emptyCell = document.createElement('div');
                emptyCell.className = 'merc-equip-cell merc-equip-empty';
                emptyCell.title = SLOT_NAMES[slot] || '';
                band.appendChild(emptyCell);
            }
        }
        return band;
    }

    // K-A compact 迷你装备行：与 full 装备带同构件（buildEquipCell = 烘焙图标/占位
    // 回退 + 强化等级角标 + scope rich tooltip；空槽虚线 + title 槽位名），11 槽
    // 压一行、CSS 收 15px；技能不进 compact。full 密度整行由 CSS 隐藏。
    function buildMiniEquipStrip(merc) {
        var strip = document.createElement('div');
        strip.className = 'team-entity-ministrip team-merc-card-miniequips';
        var equipBySlot = {};
        if (merc.equips) {
            for (var e = 0; e < merc.equips.length; e++) equipBySlot[merc.equips[e].slot] = merc.equips[e];
        }
        var SLOTS = MercData.SLOTS, SLOT_NAMES = MercData.SLOT_NAMES;
        for (var i = 0; i < SLOTS.length; i++) {
            var slot = SLOTS[i];
            var eq = equipBySlot[slot];
            if (eq) {
                strip.appendChild(buildEquipCell(eq));
            } else {
                var emptyCell = document.createElement('div');
                emptyCell.className = 'merc-equip-cell merc-equip-empty';
                emptyCell.title = SLOT_NAMES[slot] || '';
                strip.appendChild(emptyCell);
            }
        }
        return strip;
    }

    // I2 卡内直操动作行（full 卡底部）：出战/休息（阵亡 → 复活 · 复活币×1）+ 解雇，
    // 与右栏决策面同 handler / blocked 投影 / pending；嵌套按钮纪律见 bindCardActionNesting
    function buildCardActions(merc) {
        var row = document.createElement('div');
        row.className = 'team-entity-actions';
        if (merc.dead) {
            var coins = _snapshot ? (_snapshot.reviveCoins || 0) : 0;
            var reviveBtn = button('复活', 'team-action-btn team-card-act team-merc-act-revive', null);
            reviveBtn.setAttribute('data-tone', 'restore');
            reviveBtn.setAttribute('aria-label', '复活：' + merc.name + '（消耗 1 枚复活币）');
            setActionBlocked(reviveBtn, coins <= 0 ? '复活币不足（商城/战利品可获得）' : '');
            if (coins > 0) reviveBtn.title = '消耗 1 枚复活币（持有 ' + coins + '）';
            reviveBtn.addEventListener('click', function() {
                if (guardBlocked(this)) return;
                onRevive(merc.slotIndex, this);
            });
            row.appendChild(reviveBtn);
        } else {
            var deployBtn = button(merc.deployed ? '休息' : '出战', 'team-action-btn team-card-act team-merc-act-deploy', null);
            deployBtn.setAttribute('data-tone', 'deploy');
            deployBtn.setAttribute('aria-label', (merc.deployed ? '休息：' : '出战：') + merc.name);
            deployBtn.addEventListener('click', function() {
                if (guardBlocked(this)) return;
                onDeploy(merc.slotIndex, this);
            });
            row.appendChild(deployBtn);
        }
        var dismissBtn = button('解雇', 'team-action-btn team-card-act team-act-delete team-merc-act-dismiss', null);
        dismissBtn.setAttribute('data-tone', 'danger');
        dismissBtn.setAttribute('aria-label', '解雇：' + merc.name);
        dismissBtn.title = '解雇后将回到雇佣市场';
        dismissBtn.addEventListener('click', function() {
            confirmDismiss(merc);
        });
        row.appendChild(dismissBtn);
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

    function selectMerc(slot) {
        if (_busy) { notifyBusy(); return; }
        _selectedSlot = slot;
        var cards = _gridEl.querySelectorAll('.team-merc-card');
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
        // 优先出战中的首个，否则列表首个（与现役「默认选中首位」语义接近）
        var i;
        for (i = 0; i < _hiredMercs.length; i++) {
            if (_hiredMercs[i].deployed && !_hiredMercs[i].dead) return _hiredMercs[i].slotIndex;
        }
        return _hiredMercs.length ? _hiredMercs[0].slotIndex : -1;
    }

    // 局部刷新单张卡片（出战 / 复活后，不整页重排）
    function refreshCard(slotIndex) {
        var merc = findMercBySlot(slotIndex);
        if (!merc || !_gridEl) return;
        var old = _gridEl.querySelector('.team-merc-card[data-slot="' + slotIndex + '"]');
        if (!old) { renderRosterGrid(); return; }
        var fresh = buildMercCard(merc);
        // 原位替换前先释放旧卡上的 EntityTile / tooltip 绑定，避免域内 detached 绑定累积
        Workbench.releaseElementBindings(old);
        old.parentNode.replaceChild(fresh, old);
    }

    // ═══════════════════════════════════════════════════════════
    // roster 视图：右栏决策面
    // ═══════════════════════════════════════════════════════════
    function renderDetail() {
        if (!_detailEl) return;
        Workbench.clearElement(_detailEl);
        if (_selectedSlot === CANDIDATE_SLOT && _hireCandidate) { renderCandidateDetail(); return; }
        var merc = findMercBySlot(_selectedSlot);
        if (!merc) {
            _detailEl.appendChild(TeamShared.buildEmptyState({
                kind: 'empty',
                statement: '选择左侧一名佣兵查看详情',
                nextStep: _hireCandidate ? '或选择置顶「候选」卡确认雇佣' : '出战 · 复活 · 培养都在这里完成'
            }));
            return;
        }

        _detailEl.appendChild(detailHead(merc.name,
            'Lv.' + merc.level + ' · ' + (merc.gender || '') + (merc.height ? ' · ' + merc.height + 'cm' : ''),
            statusChips(merc), merc));
        _detailEl.appendChild(buildSummary(merc));
        _detailEl.appendChild(buildRosterActions(merc));
        _detailEl.appendChild(buildSkillBlock(merc));
    }

    function renderCandidateDetail() {
        var cand = _hireCandidate;
        var chips = [];
        var candChip = document.createElement('span');
        candChip.className = 'team-detail-chip';
        candChip.textContent = '雇佣候选';
        chips.push(candChip);
        if (cand.levelGap) {
            var gapChip = document.createElement('span');
            gapChip.className = 'team-detail-chip team-chip-danger';
            gapChip.textContent = '等级过高';
            chips.push(gapChip);
        }
        _detailEl.appendChild(detailHead(cand.name, 'Lv.' + cand.level, chips, cand));

        var price = document.createElement('div');
        price.className = 'team-cand-price';
        // 余额写法对齐 hire 预览 CommitBar status：K点价 > 0 时补 K点余额
        price.textContent = '契约金 ' + TeamShared.fmtMoney(cand.goldPrice)
            + ((cand.kPrice || 0) > 0 ? ' / ' + TeamShared.fmtMoney(cand.kPrice) + ' K' : '')
            + ' · 余额 金币 ' + TeamShared.fmtMoney(_snapshot ? _snapshot.gold : 0)
            + ((cand.kPrice || 0) > 0 ? ' · K点 ' + TeamShared.fmtMoney(_snapshot ? _snapshot.kpoint : 0) : '');
        _detailEl.appendChild(price);

        var gate = candidateGate(cand);
        var actions = document.createElement('div');
        actions.className = 'team-detail-action-row';
        var recruitBtn = button('确认雇佣', 'team-action-btn team-merc-act-recruit', null);
        recruitBtn.setAttribute('data-tone', 'primary');
        recruitBtn.setAttribute('aria-label', '确认雇佣 ' + cand.name);
        setActionBlocked(recruitBtn, gate);
        recruitBtn.addEventListener('click', function() {
            if (guardBlocked(this)) return;
            onWorldHire(this);
        });
        actions.appendChild(recruitBtn);
        _detailEl.appendChild(actions);

        var note = document.createElement('div');
        note.className = 'team-cand-note';
        note.textContent = '雇佣成功后关闭面板返回场景；门控按实时数据复算。';
        _detailEl.appendChild(note);
    }

    // 详情头部：中号纸娃娃 + 名称/副题 + 状态 chips（roster 右栏 / 候选 / hire 预览共用）
    function detailHead(name, sub, chips, merc) {
        var head = document.createElement('div');
        head.className = 'team-detail-head';
        var portraitHost = document.createElement('div');
        portraitHost.className = 'team-portrait team-merc-portrait-mid';
        head.appendChild(portraitHost);
        updatePortraitHost(portraitHost, merc, 'decision');
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

    // 关键属性摘要（对齐现役 selbar 信息量：性格特质要点 / 技能数 / 装备概要）
    function buildSummary(merc) {
        var box = document.createElement('div');
        box.className = 'team-merc-summary';
        var top = topTrait(merc);
        box.appendChild(summaryRow('主导特质',
            top ? (top.name + ' ' + Math.round(top.value * 100)) : (merc.personality ? '暂无特质' : '情报暂不可用')));
        var skills = merc.skills;
        box.appendChild(summaryRow('战斗技能',
            skills ? (skills.length + ' 个') : '情报暂不可用'));
        box.appendChild(summaryRow('装备',
            (merc.equips ? merc.equips.length : 0) + '/' + MercData.SLOTS.length + ' 槽'));
        return box;
    }

    function summaryRow(label, value) {
        var row = document.createElement('div');
        row.className = 'team-merc-summary-row';
        var lab = document.createElement('span');
        lab.className = 'team-merc-summary-label';
        lab.textContent = label;
        var val = document.createElement('span');
        val.className = 'team-merc-summary-val';
        val.textContent = value;
        row.appendChild(lab);
        row.appendChild(val);
        return row;
    }

    // 动作行：出战 · 休息切换（阵亡 → 复活 · 复活币×1）+「培养 →」；解雇只在培养页
    function buildRosterActions(merc) {
        var actions = document.createElement('div');
        actions.className = 'team-detail-action-row';
        if (merc.dead) {
            var coins = _snapshot ? (_snapshot.reviveCoins || 0) : 0;
            var reviveBtn = button('复活 · 复活币×1', 'team-action-btn team-merc-act-revive', null);
            reviveBtn.setAttribute('data-tone', 'restore');
            reviveBtn.setAttribute('aria-label', '复活 ' + merc.name + '（消耗 1 枚复活币）');
            setActionBlocked(reviveBtn, coins <= 0 ? '复活币不足（商城/战利品可获得）' : '');
            if (coins > 0) reviveBtn.title = '消耗 1 枚复活币（持有 ' + coins + '）';
            reviveBtn.addEventListener('click', function() {
                if (guardBlocked(this)) return;
                onRevive(merc.slotIndex, this);
            });
            actions.appendChild(reviveBtn);
        } else {
            var deployBtn = button(merc.deployed ? '休息' : '出战', 'team-action-btn team-merc-act-deploy', null);
            deployBtn.setAttribute('data-tone', 'deploy');
            deployBtn.setAttribute('aria-label', (merc.deployed ? '休息 ' : '出战 ') + merc.name);
            deployBtn.addEventListener('click', function() {
                if (guardBlocked(this)) return;
                onDeploy(merc.slotIndex, this);
            });
            actions.appendChild(deployBtn);
        }
        var trainBtn = button('培养 →', 'team-action-btn team-merc-act-train', function() {
            openDetail(merc.slotIndex);
        });
        trainBtn.setAttribute('data-tone', 'primary');
        trainBtn.setAttribute('data-audio-cue', 'confirm');
        trainBtn.setAttribute('aria-label', '培养 ' + merc.name);
        trainBtn.title = '造型预览 / 性格特质 / 技能详情 / 装备调配';
        actions.appendChild(trainBtn);
        return actions;
    }

    // 战斗技能图标流（全量，区域内换行；技能不上卡——数量不可控）
    function buildSkillBlock(merc) {
        var wrap = document.createElement('div');
        var label = document.createElement('div');
        label.className = 'team-merc-skill-label';
        label.textContent = '战斗技能';
        wrap.appendChild(label);
        var flow = document.createElement('div');
        flow.className = 'team-merc-skill-flow';
        var skills = merc.skills;
        if (skills && skills.length) {
            for (var i = 0; i < skills.length; i++) flow.appendChild(buildSkillCell(skills[i]));
        } else {
            var empty = document.createElement('span');
            empty.className = 'team-merc-skill-empty';
            empty.textContent = skills ? '暂无技能' : '技能情报暂不可用';
            flow.appendChild(empty);
        }
        wrap.appendChild(flow);
        return wrap;
    }

    function statusChips(merc) {
        var chips = [];
        var state = document.createElement('span');
        if (merc.dead) {
            state.className = 'team-detail-chip team-chip-danger';
            state.textContent = '阵亡';
        } else {
            state.className = 'team-detail-chip' + (merc.deployed ? ' team-chip-deployed' : '');
            state.textContent = merc.deployed ? '出战中' : '休息中';
        }
        chips.push(state);
        return chips;
    }

    function updateHeaderMetrics() {
        if (!_shell) return;
        var subtitle = '读取中';
        if (_snapshot) {
            var deployed = 0;
            for (var i = 0; i < _hiredMercs.length; i++) { if (_hiredMercs[i].deployed) deployed++; }
            subtitle = '出战 ' + deployed + ' · 佣兵栏 ' + _hiredMercs.length + '/' + (_snapshot.maxSlots || 0);
        }
        _shell.setTitle('佣兵管理', subtitle);
        if (!_snapshot) return;
        _shell.setMetric('gold', '金币', TeamShared.fmtMoney(_snapshot.gold));
        _shell.setMetric('kpoint', 'K点', TeamShared.fmtMoney(_snapshot.kpoint));
        _shell.setMetric('revive', '复活币', String(_snapshot.reviveCoins || 0));
    }

    // ═══════════════════════════════════════════════════════════
    // hire 视图：雇佣市场（L/R 原位切换，对齐 pet store）
    // ═══════════════════════════════════════════════════════════
    function enterHire() {
        if (_busy) { notifyBusy(); return; }
        if (_view === 'hire' || !_shell) return;
        if (!_hireL) buildHireViews();
        _view = 'hire';
        _hireMinLevel = 0;
        updateLevelChips();
        _shell.moveView('L', _hireL);
        _shell.moveView('R', _hireR);
        resetHireList();
    }

    function backToRoster() {
        if (_busy) { notifyBusy(); return; }   // 旧版 navigateTo 的 busy 守卫（重写时丢失）
        if (_view !== 'hire' || !_shell) return;
        _view = 'roster';
        _selectedPoolIdx = -1;
        _shell.moveView('L', _rosterL);
        _shell.moveView('R', _rosterR);
    }

    function onLevelChip(chip) {
        if (_busy) { notifyBusy(); return; }
        if (_view !== 'hire') return;
        var min = Number(chip.getAttribute('data-min')) || 0;
        if (min === _hireMinLevel) return;
        _hireMinLevel = min;
        updateLevelChips();
        resetHireList();
    }

    // 等级定位 chip：激活态 + 超出池内最高等级的钮禁用
    function updateLevelChips() {
        if (!_hireChipsEl) return;
        var chips = _hireChipsEl.querySelectorAll('.team-merc-lvl-chip');
        for (var i = 0; i < chips.length; i++) {
            var min = Number(chips[i].getAttribute('data-min')) || 0;
            var active = min === _hireMinLevel;
            chips[i].classList.toggle('team-merc-lvl-chip-active', active);
            chips[i].setAttribute('aria-pressed', active ? 'true' : 'false');
            chips[i].disabled = (min > 0 && _hireMaxLevel > 0 && min > _hireMaxLevel);
            if (chips[i].disabled) chips[i].title = '佣兵池内暂无 Lv.' + min + ' 以上的佣兵';
            else chips[i].removeAttribute('title');
        }
    }

    // ── 雇佣列表：无缝下滑加载（滚动触底拉下一页并追加，替代分页按钮）──
    function resetHireList() {
        _hirePage = 1;
        _hireTotalPages = 1;
        _hireTotalCount = 0;
        _hireData = [];
        _hireLoaded = false;
        _hireError = '';
        _selectedPoolIdx = -1;
        if (_hireGridEl) Workbench.clearElement(_hireGridEl);
        if (_hireScrollEl) _hireScrollEl.scrollTop = 0;
        renderHirePreview();
        requestHireList(true);
    }

    function requestHireList(reset) {
        if (_busy) return;
        _busy = true;
        setHireSentinel('loading');
        if (_shell) _shell.setStatus('读取中', Workbench.WorkbenchState.LOADING);

        // minLevel 仅随 reset 请求发送（AS2 据此跳页覆盖页码）；
        // 后续触底翻页按返回页码顺延，再带 minLevel 会被反复拽回跳转页
        var req = { page: _hirePage };
        if (reset && _hireMinLevel > 0) req.minLevel = _hireMinLevel;

        sendPanelMsg('hire_list', req, function(data) {
            _busy = false;
            if (!data.success) {
                // 翻页请求失败要回退触底时的页码自增，否则下次触底再 ++ 会静默跳过一页
                if (!reset && _hirePage > 1) _hirePage--;
                setHireSentinel('idle');
                if (reset) {
                    _hireError = '获取雇佣市场失败：' + (data.error || '未知错误');
                    _hireLoaded = true;
                    renderHireGrid();
                    if (_shell) _shell.setStatus('读取失败', Workbench.WorkbenchState.ERROR);
                } else if (_shell) {
                    _shell.setStatus('就绪', Workbench.WorkbenchState.READY);
                }
                TeamShared.toast('加载失败：' + (data.error || '未知错误'));
                return;
            }
            var hl = data.hireList;
            _hirePage = hl.page;
            _hireTotalPages = hl.totalPages;
            _hireTotalCount = hl.totalCount || 0;
            if (typeof hl.maxLevel === 'number') _hireMaxLevel = hl.maxLevel;
            _hireLoaded = true;
            updateLevelChips();
            var items = hl.hireable || [];
            if (reset) {
                _hireData = items;
                renderHireGrid();
                anchorToMinLevel();
            } else {
                appendHireCards(items);
            }
            setHireSentinel('idle');
            maybeAutoFill();
            if (_shell) _shell.setStatus('就绪', Workbench.WorkbenchState.READY);
        });
    }

    // 跳页是页粒度（AS2 只定位到所在页），页内精确定位：滚动到首个达标卡片
    function anchorToMinLevel() {
        if (_hireMinLevel <= 0) return;
        if (!_hireScrollEl || !_hireGridEl) return;
        for (var i = 0; i < _hireData.length; i++) {
            if ((_hireData[i].level || 0) >= _hireMinLevel) {
                var card = _hireGridEl.children[i];
                if (card) _hireScrollEl.scrollTop = Math.max(0, card.offsetTop - _hireScrollEl.offsetTop - 8);
                return;
            }
        }
    }

    // 经典无限滚动陷阱守卫：首屏没被内容撑满（无法产生滚动）且仍有后续页时自动续载
    function maybeAutoFill() {
        if (_busy || _view !== 'hire') return;
        if (_hirePage >= _hireTotalPages) return;
        if (_hireScrollEl && _hireScrollEl.scrollHeight <= _hireScrollEl.clientHeight + 4) {
            _hirePage++;
            requestHireList(false);
        }
    }

    function onHireScroll() {
        if (_busy || _view !== 'hire') return;
        if (_hirePage >= _hireTotalPages) return;
        if (!_hireScrollEl) return;
        if (_hireScrollEl.scrollTop + _hireScrollEl.clientHeight >= _hireScrollEl.scrollHeight - HIRE_SCROLL_TRIGGER) {
            _hirePage++;
            requestHireList(false);
        }
    }

    // 触底哨兵：加载中 / 还有更多 / 已全部加载
    function setHireSentinel(state) {
        var el = _hireSentinelEl;
        if (!el) return;
        if (_hireData.length === 0 && state !== 'loading') { el.hidden = true; return; }
        el.hidden = false;
        el.classList.toggle('team-merc-hire-more-loading', state === 'loading');
        if (state === 'loading') {
            el.textContent = '加载中...';
        } else if (_hirePage < _hireTotalPages) {
            el.textContent = '↓ 下滑加载更多（已加载 ' + _hireData.length + ' 名）';
        } else {
            el.textContent = '已全部加载（' + _hireData.length + ' 名）';
        }
    }

    function renderHireGrid() {
        if (!_hireGridEl || _view !== 'hire') return;
        Workbench.clearElement(_hireGridEl);
        if (_hireError) {
            _hireGridEl.appendChild(errorEmptyState(_hireError, function() {
                _hireError = '';
                resetHireList();
            }));
            return;
        }
        if (_hireData.length === 0) {
            // 首包在途保持空网格 + 哨兵「加载中」；只有首包真返回空池才显示空态
            if (_hireLoaded && !_busy) {
                var emptyState = TeamShared.buildEmptyState({
                    kind: 'empty',
                    statement: '暂时没有可雇佣的佣兵',
                    nextStep: '稍后再来看看'
                });
                // 同名册：list 容器内空态为纯展示，不再投 role=option
                _hireGridEl.appendChild(emptyState);
            }
            renderHirePreview();
            return;
        }
        for (var i = 0; i < _hireData.length; i++) {
            _hireGridEl.appendChild(buildHireCard(_hireData[i]));
        }
        if (!findHireByPoolIdx(_selectedPoolIdx)) _selectedPoolIdx = _hireData[0].poolIndex;
        applyHireSelection();
        renderHirePreview();
    }

    function appendHireCards(items) {
        if (!_hireGridEl || !items.length) return;
        // 追加只发生在已有分页之后；若网格被空态/错误态占据（极端分页返回），先清场
        if (_hireGridEl.querySelector('.workbench-empty-state')) Workbench.clearElement(_hireGridEl);
        for (var i = 0; i < items.length; i++) {
            _hireData.push(items[i]);
            _hireGridEl.appendChild(buildHireCard(items[i]));
        }
        if (!findHireByPoolIdx(_selectedPoolIdx)) {
            _selectedPoolIdx = _hireData[0].poolIndex;
            applyHireSelection();
            renderHirePreview();
        }
    }

    function selectHire(poolIndex) {
        if (_busy) { notifyBusy(); return; }
        _selectedPoolIdx = poolIndex;
        applyHireSelection();
        renderHirePreview();
    }

    function applyHireSelection() {
        if (!_hireGridEl) return;
        var cards = _hireGridEl.querySelectorAll('.team-merc-hire-card');
        for (var i = 0; i < cards.length; i++) {
            var sel = cards[i].getAttribute('data-pool-idx') === String(_selectedPoolIdx);
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
    }

    function renderHirePreview() {
        if (!_hirePreviewEl || !_commitBar || _view !== 'hire') return;
        Workbench.clearElement(_hirePreviewEl);
        var item = findHireByPoolIdx(_selectedPoolIdx);
        if (!item) {
            _hirePreviewEl.appendChild(TeamShared.buildEmptyState({
                kind: 'empty',
                statement: '选择左侧目标查看价格与确认雇佣',
                nextStep: '价格、余额与条件在提交前再次核对'
            }));
            _commitBar.update({ status: '未选择目标', disabled: true, state: '', busy: false });
            return;
        }

        var chips = [];
        var lvChip = document.createElement('span');
        lvChip.className = 'team-detail-chip';
        lvChip.textContent = 'Lv.' + item.level;
        chips.push(lvChip);
        _hirePreviewEl.appendChild(detailHead(item.name,
            (item.gender || '') + (item.height ? ' · ' + item.height + 'cm' : ''), chips, item));

        var price = document.createElement('div');
        price.className = 'team-merc-hire-price';
        price.textContent = '价格 ' + priceText(item);
        _hirePreviewEl.appendChild(price);

        // H2-4：右栏信息量对齐培养页（数据 hire_list payload 全有），
        // 三节渲染直接复用培养页 section 渲染器（特质六维 / 技能行 / 装备格只读），
        // 内容超出走 .team-scroll 纵向滚动，CommitBar 固定底部不动
        var traitSection = detailSection('性格特质');
        var traitsGrid = document.createElement('div');
        traitsGrid.className = 'team-merc-traits-grid';
        renderTraits(item, traitsGrid);
        traitSection.appendChild(traitsGrid);
        _hirePreviewEl.appendChild(traitSection);

        var skillSection = detailSection('战斗技能');
        var skillRows = document.createElement('div');
        skillRows.className = 'team-merc-skill-rows';
        renderSkillRows(item, skillRows);
        skillSection.appendChild(skillRows);
        _hirePreviewEl.appendChild(skillSection);

        var equipSection = detailSection('装备');
        var equipGrid = document.createElement('div');
        equipGrid.className = 'team-merc-equip-manage-grid';
        renderEquipManage(item, equipGrid, true);
        equipSection.appendChild(equipGrid);
        _hirePreviewEl.appendChild(equipSection);

        var gate = hireGate(item);
        if (gate) {
            _commitBar.update({ status: gate, canCommit: false, state: 'blocked', busy: false });
        } else {
            // Phase K 打磨：ready 态改短文案——价格已在右栏预览 .team-merc-hire-price 行、
            // 余额在 header metrics，CommitBar 不复述（长文本与 CTA/滚动区挤碰遮挡）
            _commitBar.update({ status: '可确认雇佣', canCommit: true, state: 'ready', busy: false });
        }
    }

    // CommitBar 唯一主 CTA：busy 到回包；成功 → 刷新 snapshot 并回名册；
    // 失败 / 超时 → status error + 重拉对账，绝不自动重放。
    // 带 mercId 让 AS2 做身份校验：列表刷新前的快速连点会携带已位移的
    // stale poolIndex（hire splice / 解雇回池重排），只靠索引会雇错人。
    function onCommitHire() {
        if (_busy) { notifyBusy(); return; }
        if (_selectedPoolIdx < 0) return;
        var item = findHireByPoolIdx(_selectedPoolIdx);
        if (!item) return;
        var gate = hireGate(item);
        if (gate) { TeamShared.toast(gate); renderHirePreview(); return; }
        _busy = true;
        if (_shell) _shell.setStatus('处理中', Workbench.WorkbenchState.PENDING);
        _commitBar.update({ busy: true, status: '雇佣确认中', state: 'busy' });
        sendPanelMsg('hire', { poolIndex: item.poolIndex, mercId: item.id || '' }, function(data) {
            _busy = false;
            if (data.success) {
                if (_snapshot) {
                    _snapshot.gold = data.goldRemaining;
                    _snapshot.kpoint = data.kpointRemaining;
                }
                // 雇佣会 splice 佣兵池导致后续 poolIndex 整体位移，已加载分页全部失效；
                // 成功流程回名册 + 重拉 snapshot，下次进市场由 resetHireList 从第一页重拉
                TeamShared.toast('成功雇佣 ' + data.mercName + '！');
                _selectedPoolIdx = -1;
                if (_commitBar) _commitBar.update({ busy: false, status: '已雇佣', state: 'ready' });
                backToRoster();
                requestSnapshot();
                if (_shell) _shell.setStatus('就绪', Workbench.WorkbenchState.READY);
            } else if (data.error === 'pool_changed') {
                TeamShared.toast('佣兵列表已变化，已为你刷新');
                if (_commitBar) _commitBar.update({ busy: false, state: 'error', status: '佣兵列表已变化 · 数据已重新同步' });
                resetHireList();
            } else {
                var msg = '雇佣失败：' + (data.error || '未知错误');
                TeamShared.toast(msg);
                if (_commitBar) _commitBar.update({ busy: false, state: 'error', status: msg + ' · 数据已重新同步，请重新确认' });
                requestSnapshot();   // 对账重拉
                if (_shell) _shell.setStatus('就绪', Workbench.WorkbenchState.READY);
            }
        });
    }

    // ═══════════════════════════════════════════════════════════
    // detail 培养页（SecondaryPage 覆盖 body）
    // ═══════════════════════════════════════════════════════════
    function openDetail(slotIndex) {
        if (_busy) { notifyBusy(); return; }
        var merc = findMercBySlot(slotIndex);
        if (!merc) return;
        _detailSlot = slotIndex;
        if (!_detailPage) buildDetailPage();
        // 先 open 后 render：renderDetailPage 对未激活页早退（不重建 DOM / 不发 manifest promise）
        _detailPage.open({ initialFocus: _detailRightEl });
        renderDetailPage();
    }

    function buildDetailPage() {
        var rootEl = document.createElement('section');
        rootEl.className = 'team-advance team-merc-detail-page-root';
        _detailPage = new WorkbenchComponents.SecondaryPage({
            root: rootEl,
            className: 'team-merc-detail-page',
            ariaLabel: '佣兵培养',
            host: _shell.getRoot(),
            onClose: function() {
                destroyDetailDressup();
                renderRosterGrid();
                renderDetail();
            }
        });

        var header = document.createElement('div');
        header.className = 'team-advance-header';
        var back = button('‹ 返回', 'team-pane-btn team-merc-detail-back', null);
        back.setAttribute('aria-label', '返回名册');
        back.setAttribute('data-audio-cue', 'cancel');
        _detailPage.bindBack(back);
        header.appendChild(back);
        _detailTitleEl = document.createElement('div');
        _detailTitleEl.className = 'team-advance-title';
        header.appendChild(_detailTitleEl);
        _detailChipsEl = document.createElement('div');
        _detailChipsEl.className = 'team-detail-chip-row team-advance-chips';
        header.appendChild(_detailChipsEl);
        _detailActionsEl = document.createElement('div');
        _detailActionsEl.className = 'team-advance-actions';
        header.appendChild(_detailActionsEl);
        rootEl.appendChild(header);

        // H1 两栏：body 是 grid 容器（自身不滚动）；左栏 doll 整列，右栏唯一纵向滚动列
        _detailBodyEl = document.createElement('div');
        _detailBodyEl.className = 'team-advance-body team-merc-detail-body';

        var leftCol = document.createElement('div');
        leftCol.className = 'team-merc-detail-left';
        var dollSection = detailSection('造型预览');
        dollSection.classList.add('team-merc-doll-section');
        _detailDollViewport = document.createElement('div');
        _detailDollViewport.className = 'team-merc-doll-viewport';
        _detailDollViewport.setAttribute('tabindex', '0');
        _detailDollViewport.setAttribute('role', 'region');
        _detailDollViewport.setAttribute('aria-label', '佣兵造型预览，可拖拽或使用方向键移动');
        // K-B-2：相机控件从视口右缘竖轨移到造型预览 section 内部顶部（培养页 header
        // 不挪用），视口宽度全量还给 doll 展示；横排一行（缩放/读数/全貌 + 四向平移），
        // controlsHost 仅换挂载点，相机三路清零合同不变；footer 只留操作提示。
        // Phase K 打磨：h3 标题与控件并入同一标题行（标题左 / 控件右，垂直居中），
        // 省掉控件独占的一行高度；detailSection 是通用函数不动，仅在此把 h3 移入 titlerow
        var dollTitleRow = document.createElement('div');
        dollTitleRow.className = 'team-merc-doll-titlerow';
        dollTitleRow.appendChild(dollSection.querySelector('.team-advance-section-title'));
        _detailDollControls = document.createElement('div');
        _detailDollControls.className = 'team-merc-doll-controls';
        dollTitleRow.appendChild(_detailDollControls);
        dollSection.appendChild(dollTitleRow);
        var dollMain = document.createElement('div');
        dollMain.className = 'team-merc-doll-main';
        dollMain.appendChild(_detailDollViewport);
        dollSection.appendChild(dollMain);
        var dollFooter = document.createElement('div');
        dollFooter.className = 'team-merc-doll-footer';
        var dollHint = document.createElement('div');
        dollHint.className = 'team-merc-doll-hint';
        dollHint.textContent = '拖拽移动 · 滚轮缩放 · 方向键平移 · Home 复位';
        dollFooter.appendChild(dollHint);
        dollSection.appendChild(dollFooter);
        leftCol.appendChild(dollSection);
        _detailBodyEl.appendChild(leftCol);

        _detailRightEl = document.createElement('div');
        _detailRightEl.className = 'team-scroll team-merc-detail-right';
        _detailRightEl.setAttribute('data-scroll-region', '');
        _detailRightEl.setAttribute('tabindex', '0');
        _detailBodyEl.appendChild(_detailRightEl);
        rootEl.appendChild(_detailBodyEl);
    }

    function renderDetailPage() {
        if (!_detailPage || !_detailBodyEl) return;
        // 未激活早退：培养页关闭时不重建 DOM / 不发 manifest promise（onDeploy / onRevive /
        // requestSnapshot 的例行刷新在页面关闭时是纯浪费）；「佣兵消失 → 关页」只需在激活时
        // 判断，并入下方分支后语义不变
        if (!_detailPage.isActive()) return;
        var merc = findMercBySlot(_detailSlot);
        if (!merc) {
            // 佣兵不存在（被解雇/数据刷新）→ 关闭培养页回名册
            _detailPage.close('merc-gone');
            return;
        }
        _detailTitleEl.textContent = merc.name + ' Lv.' + merc.level;

        Workbench.clearElement(_detailChipsEl);
        var chips = statusChips(merc);
        var genderChip = document.createElement('span');
        genderChip.className = 'team-detail-chip';
        genderChip.textContent = (merc.gender || '') + (merc.height ? ' · ' + merc.height + 'cm' : '');
        chips.push(genderChip);
        for (var c = 0; c < chips.length; c++) _detailChipsEl.appendChild(chips[c]);

        // 顶部动作：出战 · 休息（阵亡 → 复活 · 复活币×1）+ 解雇（唯一入口）
        Workbench.clearElement(_detailActionsEl);
        if (merc.dead) {
            var coins = _snapshot ? (_snapshot.reviveCoins || 0) : 0;
            var reviveBtn = button('复活 · 复活币×1', 'team-action-btn team-merc-act-revive', null);
            reviveBtn.setAttribute('data-tone', 'restore');
            reviveBtn.setAttribute('data-audio-cue', 'confirm');
            reviveBtn.setAttribute('aria-label', '复活 ' + merc.name + '（消耗 1 枚复活币）');
            setActionBlocked(reviveBtn, coins <= 0 ? '复活币不足（商城/战利品可获得）' : '');
            if (coins > 0) reviveBtn.title = '消耗 1 枚复活币（持有 ' + coins + '）';
            reviveBtn.addEventListener('click', function() {
                if (guardBlocked(this)) return;
                onRevive(merc.slotIndex, this);
            });
            _detailActionsEl.appendChild(reviveBtn);
        } else {
            var deployBtn = button(merc.deployed ? '休息' : '出战', 'team-action-btn team-merc-act-deploy', null);
            deployBtn.setAttribute('data-tone', 'deploy');
            deployBtn.setAttribute('data-audio-cue', 'confirm');
            deployBtn.setAttribute('aria-label', (merc.deployed ? '休息 ' : '出战 ') + merc.name);
            deployBtn.addEventListener('click', function() {
                if (guardBlocked(this)) return;
                onDeploy(merc.slotIndex, this);
            });
            _detailActionsEl.appendChild(deployBtn);
        }
        var dismissBtn = button('解雇', 'team-action-btn team-act-delete team-merc-act-dismiss', function() {
            confirmDismiss(merc);
        });
        dismissBtn.setAttribute('data-tone', 'danger');
        dismissBtn.setAttribute('aria-label', '解雇 ' + merc.name);
        dismissBtn.title = '解雇后将回到雇佣市场';
        _detailActionsEl.appendChild(dismissBtn);

        // body：左栏 doll host 重建（相机随 canvas 挂接）；右栏滚动列依次 特质 → 技能 → 装备（只读）
        destroyDetailDressup();   // 先毁旧相机 / 渲染器再清 viewport，监听器不残留
        Workbench.clearElement(_detailDollViewport);
        _detailDressupHost = document.createElement('div');
        _detailDressupHost.className = 'team-merc-dressup-host';
        _detailDollViewport.appendChild(_detailDressupHost);

        Workbench.clearElement(_detailRightEl);
        var traitSection = detailSection('性格特质');
        var traitsGrid = document.createElement('div');
        traitsGrid.className = 'team-merc-traits-grid';
        renderTraits(merc, traitsGrid);
        traitSection.appendChild(traitsGrid);
        _detailRightEl.appendChild(traitSection);

        var skillSection = detailSection('战斗技能');
        var skillRows = document.createElement('div');
        skillRows.className = 'team-merc-skill-rows';
        renderSkillRows(merc, skillRows);
        skillSection.appendChild(skillRows);
        _detailRightEl.appendChild(skillSection);

        var equipSection = detailSection('装备调配');
        var hint = document.createElement('div');
        hint.className = 'team-merc-section-hint';
        hint.textContent = '装备更换功能筹备中——当前仅展示，后续将在此调整佣兵装备。';
        equipSection.appendChild(hint);
        var manageGrid = document.createElement('div');
        manageGrid.className = 'team-merc-equip-manage-grid';
        renderEquipManage(merc, manageGrid);
        equipSection.appendChild(manageGrid);
        _detailRightEl.appendChild(equipSection);

        renderDetailDressup(merc);
    }

    function detailSection(title) {
        var sec = document.createElement('section');
        sec.className = 'team-advance-section';
        var h = document.createElement('h3');
        h.className = 'team-advance-section-title';
        h.textContent = title;
        sec.appendChild(h);
        return sec;
    }

    // 性格特质六维条（最高维度标「主导」）
    function renderTraits(merc, gridEl) {
        var traits = merc.personality;
        if (traits && traits.length) {
            var topVal = -1;
            var t;
            for (t = 0; t < traits.length; t++) {
                if (traits[t].value > topVal) topVal = traits[t].value;
            }
            for (t = 0; t < traits.length; t++) {
                var tr = traits[t];
                var isTop = tr.value >= topVal - 0.0001;
                var row = document.createElement('div');
                row.className = 'team-merc-trait' + (isTop ? ' team-merc-trait-top' : '');
                var nameEl = document.createElement('span');
                nameEl.className = 'team-merc-trait-name';
                nameEl.textContent = tr.name;
                row.appendChild(nameEl);
                row.appendChild(meterNode(isTop ? 'top' : '', tr.value));
                var val = document.createElement('span');
                val.className = 'team-merc-trait-val';
                val.textContent = String(Math.round(tr.value * 100));
                row.appendChild(val);
                if (isTop) {
                    var tag = document.createElement('span');
                    tag.className = 'team-merc-trait-tag';
                    tag.textContent = '主导';
                    row.appendChild(tag);
                }
                gridEl.appendChild(row);
            }
        } else {
            var emptyRow = document.createElement('div');
            emptyRow.className = 'team-merc-empty-row';
            emptyRow.textContent = '性格情报暂不可用';
            gridEl.appendChild(emptyRow);
        }
    }

    // 战斗技能行（完整列表；skillTipHtml + hover/focus tooltip 协议保留）
    function renderSkillRows(merc, rowsEl) {
        var skills = merc.skills;
        if (skills && skills.length) {
            for (var s = 0; s < skills.length; s++) {
                var sk = skills[s];
                var srow = document.createElement('div');
                srow.className = 'team-merc-skill-row';
                srow.appendChild(buildSkillCell(sk));
                var info = document.createElement('div');
                info.className = 'team-merc-skill-row-info';
                var nm = document.createElement('div');
                nm.className = 'team-merc-skill-row-name';
                nm.textContent = sk.name;
                var lv = document.createElement('span');
                lv.className = 'team-merc-skill-row-lv';
                lv.textContent = 'Lv.' + (sk.level || 1);
                nm.appendChild(lv);
                var desc = document.createElement('div');
                desc.className = 'team-merc-skill-row-desc';
                desc.textContent = (sk.type || '') + ' · ' + (sk.trait || '');
                info.appendChild(nm);
                info.appendChild(desc);
                srow.appendChild(info);
                var stats = document.createElement('div');
                stats.className = 'team-merc-skill-row-stats';
                stats.innerHTML = '冷却 ' + (sk.cooldown || 0) + 's<br>消耗 ' + (sk.cost || 0) + ' MP';
                srow.appendChild(stats);
                rowsEl.appendChild(srow);
            }
        } else {
            var emptyRow = document.createElement('div');
            emptyRow.className = 'team-merc-empty-row';
            emptyRow.textContent = skills ? '该佣兵尚未习得技能' : '技能情报暂不可用';
            rowsEl.appendChild(emptyRow);
        }
    }

    // 装备调配（只读 11 槽；「更换」禁用占位，为后续装备更换功能预留）。
    // readonly=true 时连占位钮也不渲染（H2-4 hire 右栏纯展示装备格：图标 + 名称 + 等级）。
    function renderEquipManage(merc, gridEl, readonly) {
        var SLOTS = MercData.SLOTS;
        var SLOT_NAMES = MercData.SLOT_NAMES;
        var equipBySlot = {};
        if (merc.equips) {
            for (var e = 0; e < merc.equips.length; e++) equipBySlot[merc.equips[e].slot] = merc.equips[e];
        }
        for (var i = 0; i < SLOTS.length; i++) {
            var slot = SLOTS[i];
            var eq = equipBySlot[slot];
            var cellWrap = document.createElement('div');
            cellWrap.className = 'team-merc-equip-slot';
            if (eq) {
                cellWrap.appendChild(buildEquipCell(eq));
            } else {
                var emptyCell = document.createElement('div');
                emptyCell.className = 'merc-equip-cell merc-equip-empty';
                emptyCell.title = SLOT_NAMES[slot] || '';
                cellWrap.appendChild(emptyCell);
            }
            var info = document.createElement('div');
            info.className = 'team-merc-equip-slot-info';
            var label = document.createElement('span');
            label.className = 'team-merc-equip-slot-label';
            label.textContent = SLOT_NAMES[slot] || '';
            var nameEl = document.createElement('span');
            nameEl.className = 'team-merc-equip-slot-name' + (eq ? '' : ' team-merc-equip-slot-vacant');
            nameEl.textContent = eq ? ((eq.displayname || eq.name) + ' +' + eq.level) : '空';
            info.appendChild(label);
            info.appendChild(nameEl);
            cellWrap.appendChild(info);
            if (!readonly) {
                var swap = button('更换', 'team-pane-btn merc-equip-swap-btn', null);
                swap.disabled = true;
                swap.title = '装备更换功能筹备中';
                cellWrap.appendChild(swap);
            }
            gridEl.appendChild(cellWrap);
        }
    }

    // 解雇：共享 modal（danger 主按钮），替代自绘 confirm overlay
    function confirmDismiss(merc) {
        if (_busy) { notifyBusy(); return; }
        if (!_shell) return;
        _shell.openModal({
            kind: 'confirm',
            // 名册卡直操解雇也触发此 modal，kicker 用中性的「佣兵管理」（不只培养页入口）
            kicker: '佣兵管理',
            title: '确认解雇',
            message: '确定要解雇 ' + merc.name + '（Lv.' + merc.level + '）吗？',
            detail: '解雇后将回到雇佣市场。',
            actions: [
                { id: 'cancel', label: '取消', audioCue: 'cancel' },
                { id: 'confirm', label: '确认解雇', primary: true, danger: true, audioCue: 'confirm',
                    onSelect: function() { doDismiss(merc.slotIndex); } }
            ]
        });
    }

    function doDismiss(slotIndex) {
        if (_busy) { notifyBusy(); return; }
        beginOp(null);
        sendPanelMsg('dismiss', { mercIndex: slotIndex }, function(data) {
            endOp(null);
            if (data.success) {
                if (_detailPage && _detailPage.isActive()) _detailPage.close('dismissed');
                _selectedSlot = -1;
                TeamShared.toast('已解雇 ' + data.mercName);
                requestSnapshot();
            } else {
                TeamShared.toast('解雇失败：' + (data.error || '未知错误'));
            }
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 操作处理（协议与现役逐条一致；按钮 pending + blocked 可读原因）
    // ═══════════════════════════════════════════════════════════
    function onDeploy(slotIndex, btn) {
        if (_busy) { notifyBusy(); return; }
        var merc = findMercBySlot(slotIndex);
        if (!merc) return;
        beginOp(btn);
        sendPanelMsg('deploy', { mercIndex: slotIndex }, function(data) {
            endOp(btn);
            if (data.success) {
                merc.deployed = data.deployed;
                updateHeaderMetrics();
                refreshCard(slotIndex);
                if (_selectedSlot === slotIndex) renderDetail();
                renderDetailPage();
                TeamShared.toast(merc.deployed ? '已出战' : '已休息');
            } else {
                TeamShared.toast('操作失败：' + (data.error || '未知错误'));
            }
        });
    }

    // 阵亡佣兵复活：消耗 1 枚复活币；no_revive_coin 映射「复活币不足」（与现役一致）
    function onRevive(slotIndex, btn) {
        if (_busy) { notifyBusy(); return; }
        var merc = findMercBySlot(slotIndex);
        if (!merc) return;
        beginOp(btn);
        sendPanelMsg('revive', { mercIndex: slotIndex }, function(data) {
            endOp(btn);
            if (typeof data.reviveCoins === 'number' && _snapshot) _snapshot.reviveCoins = data.reviveCoins;
            if (!data.success) {
                TeamShared.toast('复活失败：' + (data.error === 'no_revive_coin' ? '复活币不足' : (data.error || '未知错误')));
                updateHeaderMetrics();
                if (_selectedSlot === slotIndex) renderDetail();
                renderDetailPage();
                return;
            }
            merc.dead = false;
            merc.deployed = false;
            updateHeaderMetrics();
            refreshCard(slotIndex);
            if (_selectedSlot === slotIndex) renderDetail();
            renderDetailPage();
            TeamShared.toast('已复活 ' + data.mercName + '（剩余复活币 ' + (_snapshot ? (_snapshot.reviveCoins || 0) : 0) + '）');
        });
    }

    // 世界内雇佣（NPC 处确认）：旧 Symbol 2035 的 web 等价。world_hire 走 mercs 通道，
    // AS2 用 _pendingHireNpc 读权威、扣费、写入、spawn 于 NPC 位 + 删 NPC。回 hired:true → 关面板。
    function onWorldHire(btn) {
        if (_busy) { notifyBusy(); return; }
        beginOp(btn);
        sendPanelMsg('world_hire', {}, function(data) {
            endOp(btn);
            if (data && data.success && data.hired) {
                requestClose();   // 已 spawn + 删 NPC，关面板交还 Flash
                return;
            }
            var err = (data && data.error) || 'unknown';
            TeamShared.toast(({
                insufficient_gold: '金币不足',
                slots_full: '佣兵已满，请先解雇腾位',
                level_gap: '低等级时无法雇佣等级过高的佣兵',
                npc_gone: 'NPC 已离开，雇佣取消',
                disconnected: '连接已断开'
            })[err] || ('雇佣失败：' + err));
        });
    }

    // 操作锁 + 按钮 pending（TeamShared.setPending 投影）；
    // data-team-busy 投影到壳根（指针锁样式由 team.css 消费，对齐旧版 .pet-busy 语义）
    function beginOp(btn) {
        _busy = true;
        if (_shell) _shell.getRoot().setAttribute('data-team-busy', 'true');
        if (btn) TeamShared.setPending(btn, true);
        if (_shell) _shell.setStatus('处理中', Workbench.WorkbenchState.PENDING);
    }
    function endOp(btn) {
        _busy = false;
        // onClose / teardown 后 shell 可能已销毁（_shell 置空），必须判空
        if (_shell) _shell.getRoot().removeAttribute('data-team-busy');
        if (btn) TeamShared.setPending(btn, false);
        if (_shell && !_loadError) {
            _shell.setStatus(_snapshot ? '就绪' : '读取中',
                _snapshot ? Workbench.WorkbenchState.READY : Workbench.WorkbenchState.LOADING);
        }
    }

    // busy 守卫的可读反馈（设计 §4：blocked 给可读原因，不允许可点外观 + silent no-op）。
    // 仅用户动作处理器调用；纯内部程序化路径（requestHireList / maybeAutoFill / onHireScroll）保持静默
    function notifyBusy() {
        if (_shell) _shell.setStatus('操作进行中，请稍候…', Workbench.WorkbenchState.PENDING);
    }

    // ═══════════════════════════════════════════════════════════
    // 装备 Tooltip — 协议原样（equip_tooltip 消息格式 + _ttCache + hover 语义：
    // 先出基本信息、异步 rich 回包后原位升级），生命周期改由 PanelTooltip scope 托管
    // ═══════════════════════════════════════════════════════════
    function bindEquipTip(cell, eq) {
        if (!_tooltipScope) return;
        var raw = eq.raw || eq.name;
        if (!raw) return;
        var item = {
            raw: raw,
            level: Number(eq.level) || 0,
            iconKey: eq.icon || eq.name,
            displayname: eq.displayname || eq.name
        };
        _tooltipScope.bindAsync(cell, {
            profile:'dense-inspect',
            key: item.raw + '|' + item.level,
            item: item,
            cache: _ttCache,
            renderBasic: function(it) { return buildBasicTooltipHtml(it.displayname, it.level, it.iconKey); },
            renderRich: function(it, data) { return buildRichTooltipHtml(data, it.iconKey); },
            fetch: function(it, callback) { requestEquipTooltip(it, callback); }
        });
    }

    function buildBasicTooltipHtml(displayName, level, iconKey) {
        var iconHtml = PanelTooltip.dynamicIconHtml(iconKey);
        var iconBlock = iconHtml
            ? '<div class="kshop-tt-icon">' + iconHtml + '</div>'
            : '';
        return '<div class="kshop-tt-rich merc-tt-basic">' +
                iconBlock +
                '<div class="kshop-tt-desc">' +
                    '<div class="kshop-tt-header"><b>' + TeamShared.escapeHtml(displayName) + '</b>' +
                        ' <span class="kshop-tt-dim">Lv.' + level + '</span></div>' +
                    '<div class="kshop-tt-loading">加载中...</div>' +
                '</div>' +
            '</div>';
    }

    function buildRichTooltipHtml(data, iconKey) {
        return PanelTooltip.buildItemRichHtml({
            iconHtml:  PanelTooltip.dynamicIconHtml(iconKey),
            iconUrl:   PanelTooltip.staticIconUrl(iconKey),
            introHTML: data.introHTML,
            descHTML:  data.descHTML,
            rootClass: 'merc-tt-rich'
        });
    }

    // 消息格式与现役逐字一致；失败不落缓存、不自动重试（hover 语义原样）
    function requestEquipTooltip(item, callback) {
        var reqId = 'merc_tt_' + (++_reqSeq) + '_' + _session;
        _pendingReq[reqId] = function(resp) {
            if (!resp || !resp.success) return;
            callback({
                success: true,
                descHTML: resp.descHTML || '',
                introHTML: resp.introHTML || '',
                displayname: resp.displayname || '',
                itemName: resp.itemName || item.raw
            });
        };
        Bridge.send({
            type: 'panel',
            panel: 'mercs',
            cmd: 'equip_tooltip',
            callId: reqId,
            raw: item.raw,
            level: item.level
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 纸娃娃预览：卡片/右栏使用共享缓存图，培养页使用单个 live canvas。
    // manifest、性别/外观归一与状态构建统一由 MercPortraits 负责。
    // ═══════════════════════════════════════════════════════════
    function ensureDressupManifest() {
        if (_dressupManifest) return Promise.resolve(_dressupManifest);
        return MercPortraits.loadManifest().then(function(manifest) {
            _dressupManifest = manifest;
            return manifest;
        });
    }

    function buildMercDressupState(merc, fitFields, zoom, margin, drawFields, rig, stateLabel, vAlign) {
        if (!_dressupManifest) return null;
        return MercPortraits.buildState(merc, {
            manifest: _dressupManifest,
            fitFields: fitFields,
            drawFields: drawFields,
            rig: rig,
            stateLabel: stateLabel,
            zoom: zoom,
            margin: margin,
            vAlign: vAlign
        });
    }

    function updatePortraitHost(host, merc, variant) {
        if (!host) return;
        MercPortraits.updateHost(host, merc, {
            variant: variant || 'card',
            selector: '.merc-card-portrait',
            className: 'merc-card-portrait merc-dressup-portrait'
                + (variant === 'decision' ? ' merc-decision-portrait' : ''),
            alt: '佣兵造型'
        });
    }

    function destroyDetailDressup() {
        // 相机先毁：deactivate 内部移除 transform / 输入监听 / 控制条，退出培养页即清零
        if (_detailCamera) {
            _detailCamera.destroy();
            _detailCamera = null;
        }
        if (_dressupDetailRenderer) {
            _dressupDetailRenderer.destroy();
            _dressupDetailRenderer = null;
        }
        _dressupDetailCanvas = null;
    }

    // 培养页全身预览：战斗 rig 空手站立（修正 dialogue man pose 的武器错位），全身居中
    function renderDetailDressup(merc) {
        var host = _detailDressupHost;
        if (!host) return;
        destroyDetailDressup();
        host.classList.add('team-merc-dressup-loading');
        host.textContent = '加载造型...';
        var token = String(Date.now()) + Math.random();
        host._dressupToken = token;
        ensureDressupManifest().then(function() {
            if (host._dressupToken !== token || !_detailPage || !_detailPage.isActive()) return;
            host.textContent = '';
            host.classList.remove('team-merc-dressup-loading');
            var canvas = document.createElement('canvas');
            canvas.className = 'team-merc-dressup-canvas merc-detail-dressup-canvas';
            host.appendChild(canvas);
            _dressupDetailCanvas = canvas;
            // H1：内嵌共享瞬态相机（参照 character-build-doll-preview 的消费方式，但不迁页——
            // 相机直接挂在培养页左栏 doll 区；transform 只作用 exact canvas）。
            // 模块缺失时优雅降级为静态预览（与纸娃娃链同策略，不进 fail-fast 清单）。
            // K-B-2：相机先于渲染器创建——控件条入主后布局即终态，渲染器首帧量到的
            // 才是扣掉顶部控件条的真实视口高（后创建会按空控件条的虚高锁定画布固有尺寸）
            if (typeof WorkbenchInspectionViewport !== 'undefined' && WorkbenchInspectionViewport
                    && _detailDollViewport && _detailDollControls) {
                _detailCamera = WorkbenchInspectionViewport.create({
                    document: document,
                    viewport: _detailDollViewport,
                    target: canvas,
                    controlsHost: _detailDollControls,
                    ariaLabel: '佣兵造型预览，可拖拽或使用方向键移动',
                    defaultZoom: 1,
                    fitZoom: 1,
                    minZoom: 1,
                    maxZoom: 3,
                    zoomStep: 0.2,
                    panStep: 34,
                    fitLabel: '全貌',
                    active: true
                });
            }
            _dressupDetailRenderer = DressupDollRenderer.create(canvas, {
                manifest: _dressupManifest,
                width: 360,
                height: 380,
                fps: 24
            });
            var state = buildMercDressupState(merc, DRESSUP_BODY_FIT_FIELDS, 0.92, 16, null, 'battle', DRESSUP_BATTLE_STATE);
            if (state) _dressupDetailRenderer.render(state);
        }).catch(function() {
            if (host._dressupToken !== token) return;
            host.classList.remove('team-merc-dressup-loading');
            host.textContent = '造型素材暂不可用';
        });
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

    // L 角标框挂载点（战术军械皮肤签名；纯装饰由 CSS 绘制，aria 隐藏、pointer-events:none）
    function cardFrame() {
        var frame = document.createElement('span');
        frame.className = 'team-card-frame';
        frame.setAttribute('aria-hidden', 'true');
        return frame;
    }

    function createPortrait(merc, variant) {
        return MercPortraits.create(merc, {
            variant: variant || 'card',
            className: 'merc-card-portrait merc-dressup-portrait'
                + (variant === 'decision' ? ' merc-decision-portrait' : ''),
            alt: '佣兵造型'
        });
    }

    // 装备图标格 — 11 槽固定渲染 (slot 6-16)，培养页装备调配行内使用
    function buildEquipCell(eq) {
        var raw = eq.raw || eq.name;
        var iconKey = eq.icon || eq.name;
        var displayName = eq.displayname || eq.name;
        var iconHtml = (typeof Icons !== 'undefined' && Icons.html)
            ? Icons.html(iconKey, '', ' onerror="this.style.display=\'none\'"')
            : '';
        iconHtml = iconHtml
            ? iconHtml
            : '<span class="merc-equip-fallback">' + TeamShared.escapeHtml(String(displayName).charAt(0)) + '</span>';
        var cell = document.createElement('div');
        cell.className = 'merc-equip-cell';
        cell.innerHTML = iconHtml + '<span class="merc-equip-badge">' + (eq.level || 0) + '</span>';
        bindEquipTip(cell, eq);
        return cell;
    }

    // 技能图标：manifest 以裸技能名为键（IconBaker 烘焙时剥掉「图标-」linkage 前缀，
    // 与物品图标共用命名空间）。命中 → 烘焙图盖在占位字上（实线样式）；
    // 未命中 / 图片加载失败 → 回退类型首字占位（虚线样式），规格与装备图标一致 32px。
    function buildSkillCell(sk) {
        var cell = document.createElement('div');
        cell.className = 'merc-skill-cell';
        var iconHtml = (typeof Icons !== 'undefined' && Icons.html)
            ? Icons.html(sk.name, 'merc-skill-icon')
            : '';
        cell.innerHTML =
            '<span class="merc-skill-glyph">' + TeamShared.escapeHtml(String(sk.type || '技').charAt(0)) + '</span>' +
            iconHtml +
            '<span class="merc-skill-badge">' + (sk.level || 1) + '</span>';
        if (iconHtml) {
            cell.classList.add('merc-skill-cell-baked');
            var img = cell.querySelector('.merc-skill-icon');
            img.addEventListener('error', function() {
                img.parentNode.removeChild(img);
                cell.classList.remove('merc-skill-cell-baked'); // 露出占位字 + 还原虚线样式
            });
        }
        bindSkillTip(cell, sk);
        return cell;
    }

    function skillTipHtml(sk) {
        return '<b>' + TeamShared.escapeHtml(sk.name) + '</b> <span class="kshop-tt-dim">Lv.' + (sk.level || 1) + '</span><br>' +
            TeamShared.escapeHtml((sk.type || '') + ' · ' + (sk.trait || '')) + '<br>' +
            '<span class="kshop-tt-dim">冷却 ' + (sk.cooldown || 0) + 's · 消耗 ' + (sk.cost || 0) + ' MP</span>';
    }

    function bindSkillTip(cell, sk) {
        if (!_tooltipScope) return;
        _tooltipScope.bindAsync(cell, {
            item: sk,
            renderBasic: function() { return skillTipHtml(sk); }
        });
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
    function findMercBySlot(slotIndex) {
        if (slotIndex < 0) return null;
        for (var i = 0; i < _hiredMercs.length; i++) {
            if (_hiredMercs[i].slotIndex === slotIndex) return _hiredMercs[i];
        }
        return null;
    }
    function findHireByPoolIdx(poolIndex) {
        if (poolIndex < 0) return null;
        for (var i = 0; i < _hireData.length; i++) {
            if (_hireData[i].poolIndex === poolIndex) return _hireData[i];
        }
        return null;
    }
    function topTrait(merc) {
        var traits = merc && merc.personality;
        if (!traits || !traits.length) return null;
        var top = traits[0];
        for (var i = 1; i < traits.length; i++) {
            if (traits[i].value > top.value) top = traits[i];
        }
        return top;
    }
    function ratioOf(cur, max) {
        cur = Number(cur) || 0; max = Number(max) || 0;
        if (max <= 0) return 0;
        var p = cur / max;
        return p < 0 ? 0 : (p > 1 ? 1 : p);
    }

    // I3 徽标拆分：状态字牌（左上：阵亡 danger / 出战中 energetic）与满级金角标
    // （右上 data-badge-kind=max）独立投影；满级出战卡两徽标成对同线不互挡
    function statusBadge(merc) {
        var text = '', tone = '';
        if (merc.dead) { text = '阵亡'; tone = 'danger'; }
        else if (merc.deployed) { text = '出战中'; }
        if (!text) return null;
        var badge = document.createElement('span');
        badge.className = 'team-entity-badge';
        if (tone) badge.setAttribute('data-tone', tone);
        badge.textContent = text;
        return badge;
    }
    function maxBadge(merc) {
        if (!isMaxLevel(merc)) return null;
        var badge = document.createElement('span');
        badge.className = 'team-entity-badge';
        badge.setAttribute('data-badge-kind', 'max');
        badge.textContent = 'MAX';
        return badge;
    }
    // G2：满级判定与 compact 等级角标（对齐 pet 名册：snapshot.levelLimit 缺省 100）
    function isMaxLevel(merc) {
        var levelLimit = _snapshot && _snapshot.levelLimit ? _snapshot.levelLimit : 100;
        return merc.level >= levelLimit;
    }
    function levelBadge(level) {
        var badge = document.createElement('span');
        badge.className = 'team-entity-lv-badge';
        badge.textContent = String(level);
        badge.setAttribute('aria-label', '等级 ' + level);
        return badge;
    }
    function cardLabel(merc) {
        return merc.name + '，Lv.' + merc.level
            + (merc.dead ? '，阵亡' : (merc.deployed ? '，出战中' : ''));
    }
    function cardTipText(merc) {
        var text = merc.name + ' · Lv.' + merc.level + ' · ' + (merc.gender || '')
            + (merc.dead ? ' · 阵亡' : (merc.deployed ? ' · 出战中' : ' · 休息中'));
        if (merc.skills) text += ' · 技能 ' + merc.skills.length;
        text += ' · 装备 ' + (merc.equips ? merc.equips.length : 0) + '/' + MercData.SLOTS.length;
        return text;
    }

    // 价格文本（雇佣市场 / 候选共用）：金币主价 + K点辅价
    function priceText(merc) {
        var text = '';
        if ((merc.goldPrice || 0) > 0) text += TeamShared.fmtMoney(merc.goldPrice) + ' 金';
        if ((merc.kPrice || 0) > 0) { if (text) text += ' / '; text += TeamShared.fmtMoney(merc.kPrice) + ' K'; }
        if (!text) text = '免费';
        return text;
    }

    // 雇佣门控（展示层复算；权威裁决仍在 AS2）：'' 可雇佣，否则可读原因
    function hireGate(item) {
        if (!_snapshot) return '数据未就绪';
        if (_snapshot.maxSlots > 0 && _hiredMercs.length >= _snapshot.maxSlots) return '佣兵栏已满，请先解雇腾位';
        if ((item.goldPrice || 0) > 0 && (_snapshot.gold || 0) < item.goldPrice) return '金币不足';
        if ((item.kPrice || 0) > 0 && (_snapshot.kpoint || 0) < item.kPrice) return 'K点不足';
        return '';
    }

    // 世界内候选门控：比池雇佣多一条 levelGap（低等级限高级）
    function candidateGate(cand) {
        if (!_snapshot) return '数据未就绪';
        if (_snapshot.maxSlots > 0 && _hiredMercs.length >= _snapshot.maxSlots) return '佣兵栏已满，请先解雇腾位';
        if (cand.levelGap) return '等级过高';
        if ((cand.goldPrice || 0) > 0 && (_snapshot.gold || 0) < cand.goldPrice) return '金币不足';
        if ((cand.kPrice || 0) > 0 && (_snapshot.kpoint || 0) < cand.kPrice) return 'K点不足';
        return '';
    }

    // ═══════════════════════════════════════════════════════════
    // 导出
    // ═══════════════════════════════════════════════════════════
    function resetToList() {
        if (_detailPage && _detailPage.isActive()) _detailPage.close('reset');
        backToRoster();
        // 旧版 navigateTo('list') 会重拉 snapshot：保留 team-panel 重复点当前 tab 的手动刷新名册通道
        requestSnapshot();
    }

    window.MercTeamController = {
        create: createDOM,
        onOpen: onOpen,
        onClose: onClose,
        requestClose: requestClose,
        resetToList: resetToList,
        isBusy: function() { return _busy; }
    };
})();
