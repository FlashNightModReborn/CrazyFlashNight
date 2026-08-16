/**
 * arena-shell.js — 竞技场面板 P4 工程拆分 · 壳：DualPaneShell 构造 / 模式 tabs / 视图互斥切换 / 生命周期与 Esc 逐层。
 *
 * 本文件由 modules/arena-panel.js 单文件 IIFE 机械拆分而来（纯移动：行为 / 协议 payload /
 * DOM id·class 契约 / QA 断言不变）。转换规则：原顶层 `var _x` 状态 → ArenaCore.state._x（本文件内
 * 以 `S._x` 访问）；跨模块函数/常量引用 → `模块全局.名字`。加载顺序由 panels-lazy-registry 的
 * arena 注册项与 arena/dev/harness.html script 区固定（与本文件守卫一致）。
 * 依赖守卫：arena/arena-core.js。
 */
(function() {
    'use strict';

    if (typeof window === 'undefined' || !window.ArenaCore) {
        throw new Error('arena/arena-shell.js 需要先加载 arena/arena-core.js（共享基座：状态容器 + 跨模块工具 + 共享常量）');
    }

    var S = ArenaCore.state; // 共享状态（原顶层 var _x）


    // 竞技场模式（顶部 tab 条，视觉对齐战队界面 .team-tab）。
    // 当前仅「标准模式」；后续不同玩法在此追加 { id, label }，并在 onModeClick 扩展点接入
    // 各模式自己的卡片集 / preview 逻辑。结构先就位，避免把模式硬编进单一卡片列表。
    var ARENA_MODES = [
        { id: 'standard', label: '标准模式' },
        { id: 'custom', label: '定制赛' },
        // 堕落模式（Phase 2）：势力主题固定挑战。每张卡 = 一个势力，对手全部从该势力 roster
        // 采样怪物 roster（复用 Phase1 的 roster 入场通路，AS2 零改动——合成 expr 只为过校验）。
        // 需 arena-meta-rosters.js 已载（rostersAvailable）才显示该 tab；
        // QA harness 未载 → buildModeTabs 跳过本项 → 仅标准模式，行为/卡数不变。
        { id: 'fallen', label: '堕落模式', requiresRosters: true },
        // 爬升模式（Phase 3）：势力主题无限爬升 + 奖池押注（拿钱/续战走战斗内压力板位置决策）。
        // 复用势力卡（与堕落同源），进场发 mode="escalation" + 该势力单位池；战斗循环全在 AS2 自管。
        { id: 'escalation', label: '爬升模式', requiresRosters: true }
    ];

    // ════════════════════════════════════════════════════════════════════════════
    // DOM 创建
    // ════════════════════════════════════════════════════════════════════════════
    function createDOM(container) {
        S._el = document.createElement('div');
        S._el.className = 'arena-panel';
        // P1c：skin 作用域锚点——css/workbench/arena.css 的色谱/角色 token 挂 [data-workbench-skin="arena"]
        S._el.setAttribute('data-workbench-skin', 'arena');
        // P2 结构：浏览面 = #arena-grid-view，内承 DualPaneShell（三挑战模式双栏）
        // 与 #arena-custom-overview（定制赛总览，壳 body 隐藏时覆盖 body 区，D2 总览独立）；
        // 结算页 / 定制赛编辑器保持整页互斥视图不变；旧 arena-header/modebar/detail 视图退役
        // （title/money/close/tabs 迁入壳 header，detail 被右栏 preview 吸收）。
        S._el.innerHTML =
            '<div class="arena-grid-view" id="arena-grid-view">' +
                '<div class="arena-custom-overview arena-xshell" id="arena-custom-overview" hidden>' +
                    '<div class="arena-grid arena-grid-custom" id="arena-custom-grid"></div>' +
                '</div>' +
            '</div>' +
            '<div class="arena-custom-result-view arena-xshell" id="arena-custom-result-view" hidden></div>' +
            '<div class="arena-custom-editor-view arena-xshell" id="arena-custom-editor-view" hidden>' + ArenaCustomEditor.buildCustomEditorViewHtml() + '</div>' +
            '<div class="arena-toast arena-xshell" id="arena-toast"></div>';

        S._gridViewEl = S._el.querySelector('#arena-grid-view');
        S._customOverviewEl = S._el.querySelector('#arena-custom-overview');
        S._customGridEl = S._el.querySelector('#arena-custom-grid');
        S._customResultViewEl = S._el.querySelector('#arena-custom-result-view');
        S._customEditorViewEl = S._el.querySelector('#arena-custom-editor-view');

        buildWorkbenchShell();
        buildCustomLayerScopes();

        S._customResultViewEl.addEventListener('click', ArenaResult.onCustomResultClick);
        S._customEditorViewEl.addEventListener('click', ArenaCustomEditor.onCustomWorkbenchClick);
        S._customEditorViewEl.addEventListener('change', ArenaCustomEditor.onCustomWorkbenchChange);
        S._customEditorViewEl.addEventListener('input', ArenaCustomEditor.onCustomEditorInput);
        S._customEditorViewEl.addEventListener('keydown', ArenaCustomEditor.onCustomSelectKeydown);
        var customUnitListEl = S._el.querySelector('#arena-custom-unit-list');
        if (customUnitListEl) customUnitListEl.addEventListener('scroll', ArenaCustomEditor.onCustomUnitBrowserScroll);

        ArenaChallengeBrowser.buildCards();

        if (typeof Icons !== 'undefined') Icons.load(function(){});

        // 沉浸全屏化 2026-06-12：固定 1024×576 画布(.arena-panel)包进共享 .panel-scale-shell，
        // 整体等比缩放铺满全 anchor（取代旧 fluid 居中子矩形卡片）。
        S._shellEl = document.createElement('div');
        S._shellEl.className = 'panel-scale-shell arena-scale-shell';
        S._shellEl.appendChild(S._el);
        return S._shellEl;
    }

    // ── P2 共享工作台壳（WB128：封闭 options 字面量 + profile 字符串字面量）──
    // header actions 顺序固定（team 同款）：模式 tabs → 密度切换 → 帮助 → 关闭。
    function buildWorkbenchShell() {
        S._shell = new Workbench.DualPaneShell({
            profile: 'catalog-decision',
            title: 'DEATH MATCH',
            subtitle: '角斗场 · 生死竞技',
            eyebrow: '竞技场',
            status: '待命',
            leftLabel: '挑战目录',
            rightLabel: '挑战决策',
            flowLabel: '竞技',
            // 官方 opt-out（WB129 合规）：pane 自带单行控件条承担标签职能，关闭壳级 L/R marker
            slotMarkers: false
        });
        var shellRoot = S._shell.getRoot();
        shellRoot.classList.add('arena-workbench');
        S._gridViewEl.insertBefore(shellRoot, S._customOverviewEl);
        S._shellBodyEl = shellRoot.querySelector('.workbench-body');

        S._modesNav = document.createElement('nav');
        S._modesNav.className = 'arena-modes';
        S._modesNav.id = 'arena-modes';
        S._modesNav.setAttribute('aria-label', '竞技场模式');
        refreshModeTabs();
        S._shell.addHeaderAction(S._modesNav);

        S._density = new Workbench.GridDensityController({ panelId: 'arena', compactClass: 'arena-grid-compact' });
        S._densityToggle = S._density.createToggle();
        S._densityToggle.setAttribute('aria-label', '挑战目录布局');
        var densityLabel = S._densityToggle.querySelector('.item-grid-mode-label');
        if (densityLabel) densityLabel.textContent = '密度';
        S._shell.addHeaderAction(S._densityToggle);

        S._helpAction = new WorkbenchComponents.HelpAction({ shell: S._shell, spec: helpSpec() });

        S._closeButton = document.createElement('button');
        S._closeButton.type = 'button';
        S._closeButton.className = 'workbench-close-btn';
        S._closeButton.textContent = '×';
        S._closeButton.setAttribute('aria-label', '关闭竞技场面板');
        S._closeButton.setAttribute('data-audio-cue', 'back');
        S._closeButton.addEventListener('click', onArenaRequestClose);
        S._shell.addHeaderAction(S._closeButton);

        ArenaChallengeBrowser.buildBrowseViews();
        S._shell.mountInitial(S._browseL, S._browseR);
        // 金钱迁入壳 header metrics；保留 id/class 锚点（QA 与 updateMoneyDisplay 沿用）
        S._moneyEl = S._shell.setMetric('money', '金钱', '--');
        S._moneyEl.className = 'arena-money-value';
        S._moneyEl.id = 'arena-money-value';
    }

    // ── P3 定制赛选择性收敛：焦点栈 + SecondaryPage 承载（共享合同见
    //    workbench-ui-system.md §5.3/§6：二级页把焦点移入、trap Tab、背景 inert、
    //    Esc 逐层、关闭归还 opener）──
    // 层级：总览（壳内，无 scope）→ 编辑器整页（_customEditorScope）→ 深层参数页
    // （SecondaryPage，自身 FocusScope 压栈为顶层）→ 结算页（_customResultScope）。
    // Esc 归宿主 panel_esc 通道（onArenaRequestClose 逐层消费）；DOM keydown Escape
    // 走 FocusScope（dev harness / 真实浏览器键盘），两者不重复触发（Host 把物理 Esc
    // 合并为 panel_esc，见 skills 同款约定）。
    function buildCustomLayerScopes() {
        var paramPageEl = S._el.querySelector('[data-custom-editor-page="params"]');
        if (paramPageEl && typeof WorkbenchComponents !== 'undefined'
                && WorkbenchComponents.SecondaryPage) {
            // 只换承载机制（inert / Esc 分层 / opener 归还），参数编辑的信息架构与字段不变。
            // 返回/应用/保存返回的点击仍归编辑器委派路由（onCustomWorkbenchClick），
            // 这里只接管 Esc 与焦点栈；onEscape 返回 false = 关闭动作由领域流驱动
            // （renderCustomEditor 的 syncCustomParamPageVisibility），不走组件自动关闭。
            S._customParamPage = new WorkbenchComponents.SecondaryPage({
                root: paramPageEl,
                className: 'arena-custom-param-secondary',
                role: 'dialog',
                ariaLabel: '定制赛单位参数编辑',
                host: S._customEditorViewEl,
                onEscape: function() { ArenaCustomEditor.leaveCustomParamEditorDiscardingDraft(); return false; }
            });
            S._customParamPage.mount(S._customEditorViewEl);
        }
        if (typeof WorkbenchFocus !== 'undefined' && WorkbenchFocus.FocusScope) {
            S._customEditorScope = new WorkbenchFocus.FocusScope({
                root: S._customEditorViewEl,
                // Esc 一次只消费最内层：自绘下拉菜单开着时先收菜单（既有
                // onCustomSelectKeydown 同款语义），菜单关闭才逐层退页
                onEscape: function() {
                    if (S._customSelectOpen) { ArenaCustomEditor.closeCustomSelectMenus(); return false; }
                    customEditorBack();
                    return false;
                }
            });
            S._customResultScope = new WorkbenchFocus.FocusScope({
                root: S._customResultViewEl,
                onEscape: function() { ArenaResult.onCustomResultBack(); return false; }
            });
        }
    }

    // 编辑器「返回配置」按钮的层级语义（Esc 与按钮同路径）：
    // 参数页 → 放弃草稿回阵容页；单方/战场页 → 回配置总览；配置总览 → 回总览入口卡。
    function customEditorBack() {
        if (S._customEditorPage === 'params') {
            ArenaCustomEditor.leaveCustomParamEditorDiscardingDraft();
            return;
        }
        if (S._customEditorPage === 'side' || S._customEditorPage === 'battle') {
            ArenaCustomEditor.showCustomEditorConfigPage();
            return;
        }
        showGridView();
    }

    function helpSpec() {
        return {
            kind: 'workbench-help',
            kicker: '竞技场',
            title: '角斗场帮助',
            ariaLabel: '角斗场帮助',
            message: '左侧目录点击卡片选中挑战，右栏持续预览阵容、等级带、押金与奖金；'
                + '「⚔ 开始挑战」是唯一确认入口，已选中卡片上按 Enter/Space 等价触发。'
                + '「↻ 换一批」只重抽选中挑战的对手（免费），新对手到达前该卡不可确认；'
                + '「↻ 全部重抽」重抽当前模式全部卡片并清空选择。'
                + '方向键在目录中上下移动选择。堕落/爬升按势力出卡，对手为本地采样的真实兵种阵容。',
            actions: [
                { id: 'close', label: '知道了', primary: true, audioCue: 'back' }
            ]
        };
    }

    // 元战队 roster 数据是否就绪（arena-meta-rosters.js 已载）。
    // 决定堕落模式 tab 是否显示 + 怪物采样是否可行。QA harness 未载 → 恒 false。
    function rostersAvailable() {
        return (typeof window !== 'undefined') && !!window.ArenaMetaRosters && !!window.ArenaMetaRosters.factions;
    }

    function modeAvailable(mode) {
        var id = (typeof mode === 'string') ? mode : mode.id;
        if (id === 'standard') return true;
        if (id === 'custom') return true;
        if (!rostersAvailable() || S._knownEnemyCount <= 0) return false;
        return ArenaChallengeBrowser.buildFallenCards().length > 0;
    }

    function bindModeTabs() {
        if (!S._modesNav) return;
        var modeTabs = S._modesNav.querySelectorAll('.arena-mode-tab');
        for (var mt = 0; mt < modeTabs.length; mt++) {
            modeTabs[mt].addEventListener('click', onModeClick);
        }
    }

    function refreshModeTabs() {
        if (!S._modesNav) return;
        S._modesNav.innerHTML = buildModeTabs();
        bindModeTabs();
    }

    // 模式 tab 条（对齐战队界面 tab）。requiresRosters 的模式仅在数据就绪时出现。
    function buildModeTabs() {
        var html = '';
        for (var i = 0; i < ARENA_MODES.length; i++) {
            var m = ARENA_MODES[i];
            if (!modeAvailable(m)) continue;
            var active = (m.id === S._activeMode) ? ' arena-mode-tab-active' : '';
            html += '<button class="arena-mode-tab' + active + '" type="button"' +
                    ' data-mode="' + ArenaCore.escapeAttr(m.id) + '" data-audio-cue="select">' +
                    ArenaCore.escapeHtml(m.label) + '</button>';
        }
        return html;
    }

    // 模式切换：重建该模式的卡片集 + 清空全部 per-card 状态（卡 index 含义随模式变，旧 cache 失效），
    // 重发 batch preview（snapshot 已到才发；未到则由 snapshot 回调按当前 _activeCards 补发）。
    function onModeClick(e) {
        if (S._busy) return;
        var btn = e.currentTarget;
        var mode = btn.getAttribute('data-mode');
        if (!mode || mode === S._activeMode) return;
        if (!modeAvailable(mode)) return;
        ArenaChallengeBrowser.rebuildForMode(mode);
        if (S._snapshot) ArenaPreviewAuthority.batchRequestPreview();
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 生命周期
    // ════════════════════════════════════════════════════════════════════════════
    function onOpen(el, initData) {
        if (S._scaleHandle) S._scaleHandle.detach();
        S._scaleHandle = (typeof PanelScale !== 'undefined') ? PanelScale.attach(S._shellEl, 1024, 576) : null;
        S._session++;
        S._pendingReq = {};
        S._busy = false;
        S._snapshot = null;
        S._selectedCardIdx = -1;
        S._previewOpponents = null;
        S._catalogScroll = {};   // 新 session = 新窗口：目录滚动显式归顶
        S._ttCache = {};
        // batch preview 缓存清空：每次 panel reopen = 新 session，旧 lineup 与当前 _root.可雇佣兵 pool 可能不一致
        ArenaChallengeBrowser.resetCardRuntimeState();
        if (S._shell) S._shell.setStatus('读取中', Workbench.WorkbenchState.LOADING);
        S._knownEnemies = {};
        S._knownEnemyCount = 0;
        S._customResult = ArenaResult.normalizeCustomResultInitData(initData);
        S._customResultReturnBaseRequired = !!S._customResult;
        S._customMatch = null;
        S._customEditor = null;
        S._customSelectedSide = 'blue';
        S._customEditorPage = 'config';
        S._customConfirmOpen = false;
        S._customUndo = null;
        S._customSelectOpen = null;
        S._customParamOpener = null;
        // 防御：上一会话若异常退出（未经 onClose），焦点栈/二级页显式归零
        if (S._customParamPage && S._customParamPage.isActive()) {
            try { S._customParamPage.close('panel-open', { restoreFocus: false }); } catch (e) {}
        }
        if (S._customEditorScope && S._customEditorScope.isActive()) {
            try { S._customEditorScope.deactivate('panel-open', { restoreFocus: false }); } catch (e) {}
        }
        if (S._customResultScope && S._customResultScope.isActive()) {
            try { S._customResultScope.deactivate('panel-open', { restoreFocus: false }); } catch (e) {}
        }
        if (S._customResult && S._customResult.matchCode) {
            S._customMatch = {
                code: String(S._customResult.matchCode),
                parsed: null,
                error: '',
                details: []
            };
            ArenaCustomEditor.parseCustomMatchCode();
        }
        S._customRun = S._customResult ? ArenaResult.buildCustomRunFromResult(S._customResult) : null;
        ArenaResult.clearCustomPoll();
        S._customSampleIndex = 0;
        // initData.difficulty 来自 stage-select 重定向；dev 模式 ARENA_TEST 直开时为 ""
        S._initDifficulty = (initData && initData.difficulty) ? String(initData.difficulty) : '';
        ArenaCore.hideToast();
        ArenaChallengeBrowser.updateMoneyDisplay(null);
        refreshModeTabs();
        // 普通打开复位到标准模式；定制赛结算回开则直达独立结算页。
        // 上次会话可能停在堕落模式；DOM 跨 open/close 复用，必须重建目标模式（否则残留旧卡）。
        ArenaChallengeBrowser.rebuildForMode(S._customResult ? 'custom' : 'standard');
        if (S._customResult) showCustomResultView();
        ArenaPreviewAuthority.requestSnapshot();
    }

    // requestClose 三种调用语义：
    //   - 无参 / 默认：用户主动取消（点 ✕、ESC、backdrop），PanelHostController 会 pop
    //     return stack reopen 上层 panel（典型场景：玩家从 stage-select 跳进 arena，
    //     按 ✕ 想回 stage-select）。
    //   - {dismissReturnStack:true}：业务流程已 commit，AS2 端已跳关到 wuxianguotu_1。
    //     必须清整个返回链，否则 PanelHostController 会 reopen stage-select 遮挡战场视野。
    //   - {returnBase:true}：定制赛结算页退出。此时 Flash 已在竞技场场景，
    //     关闭 Web panel 不能只回 AS2 视野，必须显式请求 AS2 返回基地。
    function requestClose(options) {
        if (S._busy) return;
        Panels.close();
        var msg = { type: 'panel', panel: 'arena', cmd: 'close' };
        if (options && options.dismissReturnStack) msg.dismissReturnStack = true;
        if (options && options.returnBase) msg.returnBase = true;
        Bridge.send(msg);
    }

    // P3 Esc 逐层（宿主 panel_esc 通道，一次只消费最内层）：
    // 壳 modal → 参数 SecondaryPage（= 放弃返回）→ 编辑器整页（= 返回配置/上一级）→
    // 结算页（返回基地）→ 确认条（= 取消确认）→ 普通关闭。
    function onArenaRequestClose() {
        if (S._shell && S._shell.hasModal && S._shell.hasModal()) {
            S._shell.closeModal('escape');
            return;
        }
        if (S._customParamPage && S._customParamPage.isActive()) {
            ArenaCustomEditor.leaveCustomParamEditorDiscardingDraft();
            return;
        }
        if (S._customEditorViewEl && !S._customEditorViewEl.hidden) {
            customEditorBack();
            return;
        }
        if (S._customResultViewEl && !S._customResultViewEl.hidden) {
            requestCustomResultReturnBase();
            return;
        }
        if (S._customResultReturnBaseRequired) {
            requestCustomResultReturnBase();
            return;
        }
        if (S._customConfirmOpen) {
            S._customConfirmOpen = false;
            ArenaCustomEditor.refreshCustomMatchCard();
            return;
        }
        requestClose();
    }

    function requestCustomResultReturnBase() {
        requestClose({ dismissReturnStack: true, returnBase: true });
    }

    function onClose() {
        if (ArenaChallengeBrowser.disposeTooltips) ArenaChallengeBrowser.disposeTooltips();
        if (S._scaleHandle) { S._scaleHandle.detach(); S._scaleHandle = null; }
        // P3：先退焦点栈/二级页（document 级 listener 随 deactivate 移除，幂等），再清状态
        if (S._customParamPage) {
            try { S._customParamPage.close('panel-close', { restoreFocus: false }); } catch (e) {}
        }
        if (S._customEditorScope) {
            try { S._customEditorScope.deactivate('panel-close', { restoreFocus: false }); } catch (e) {}
        }
        if (S._customResultScope) {
            try { S._customResultScope.deactivate('panel-close', { restoreFocus: false }); } catch (e) {}
        }
        S._customParamOpener = null;
        S._pendingReq = {};
        S._busy = false;
        S._snapshot = null;
        S._selectedCardIdx = -1;
        S._previewOpponents = null;
        S._catalogScroll = {};
        S._ttCache = {};
        S._previewCache = {};
        S._previewPending = {};
        S._previewGen = {};
        S._previewError = {};
        S._cardKind = {};
        S._monsterSquad = {};
        S._knownEnemies = {};
        S._knownEnemyCount = 0;
        S._customMatch = null;
        S._customRun = null;
        S._customResult = null;
        S._customEditor = null;
        S._customSelectedSide = 'blue';
        S._customEditorPage = 'config';
        S._customConfirmOpen = false;
        S._customUndo = null;
        S._customResultReturnBaseRequired = false;
        S._customSelectOpen = null;
        ArenaResult.clearCustomPoll();
        S._customSampleIndex = 0;
        S._initDifficulty = '';
        PanelTooltip.hide();
        ArenaCore.hideToast();
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 视图切换（P2：detail 整页视图退役，被右栏持续 preview 吸收；三视图互斥收缩为
    // 浏览面（壳）/ 结算页 / 定制赛编辑器三面。P3：编辑器与结算页各持一个
    // FocusScope 焦点栈层——进页移入焦点并 trap Tab、Esc 逐层（与「返回配置」同路径）、
    // 退出归还 opener；深层参数页由 SecondaryPage 承载，见 syncCustomParamPageVisibility）
    // ════════════════════════════════════════════════════════════════════════════
    function showGridView() {
        ArenaCustomEditor.closeCustomSelectMenus();
        // 先退焦点栈再显隐：编辑器 scope 的 deactivate 会级联关闭参数 SecondaryPage
        // （onAncestorDeactivate）。opener 归还走领域路径（总览卡已随 render 重建，
        // FocusScope 持有的 opener 节点已脱离 DOM），故此处 restoreFocus:false。
        var editorWasActive = !!(S._customEditorScope && S._customEditorScope.isActive());
        if (S._customEditorScope) S._customEditorScope.deactivate('view-grid', { restoreFocus: false });
        if (S._customResultScope) S._customResultScope.deactivate('view-grid');
        S._gridViewEl.hidden = false;
        S._customResultViewEl.hidden = true;
        S._customEditorViewEl.hidden = true;
        PanelTooltip.hide();
        if (editorWasActive) focusCustomEditorOpener();
    }

    // 编辑器层 opener 焦点归还：按离开时的页面语义在重渲后的总览卡上找回入口按钮
    // （单方/战场/参数页 → 「调整某方」；配置总览 → 「编辑配置」）。
    function focusCustomEditorOpener() {
        if (!S._el) return;
        var btn = null;
        if (S._customEditorPage !== 'config'
                && (S._customSelectedSide === 'blue' || S._customSelectedSide === 'red')) {
            btn = S._el.querySelector('.arena-card-custom [data-custom-action="edit"][data-custom-edit-side="' + S._customSelectedSide + '"]');
        }
        if (!btn) btn = S._el.querySelector('.arena-card-custom .arena-custom-edit');
        if (btn && typeof btn.focus === 'function') btn.focus({ preventScroll: true });
    }

    function showCustomResultView() {
        ArenaCustomEditor.closeCustomSelectMenus();
        if (S._customEditorScope) S._customEditorScope.deactivate('view-result');
        ArenaResult.renderCustomResultView();
        S._gridViewEl.hidden = true;
        S._customResultViewEl.hidden = false;
        S._customEditorViewEl.hidden = true;
        if (S._customResultScope) S._customResultScope.activate({ underlay: [] });
        PanelTooltip.hide();
    }

    function showCustomEditorView() {
        ArenaCustomEditor.ensureCustomMatchState();
        ArenaCustomEditor.parseCustomMatchCode();
        // 先显隐 + 激活编辑器焦点栈，再渲染：参数页的 SecondaryPage open 会把自身
        // FocusScope 压到栈顶（后激活者为顶层），顺序反了 Esc 分层就倒错
        S._gridViewEl.hidden = true;
        S._customResultViewEl.hidden = true;
        S._customEditorViewEl.hidden = false;
        if (S._customEditorScope) S._customEditorScope.activate({ underlay: [] });
        ArenaCustomEditor.refreshCustomMatchCard();
        ArenaCustomEditor.renderCustomEditor();
        ArenaCustomEditor.renderCustomUnitBrowser();
        PanelTooltip.hide();
    }

    function showCustomEditorForSide(side) {
        var editor = ArenaCustomEditor.ensureCustomEditorState();
        if (editor.mode === 'pve') side = 'red';
        if (side === 'blue' || side === 'red') {
            S._customSelectedSide = side;
            S._customEditorPage = 'side';
        } else {
            S._customEditorPage = 'config';
        }
        showCustomEditorView();
    }

    // 导出：仅被其它 arena 模块 / facade 引用的名字
    window.ArenaShell = {
        createDOM: createDOM,
        rostersAvailable: rostersAvailable,
        modeAvailable: modeAvailable,
        refreshModeTabs: refreshModeTabs,
        onOpen: onOpen,
        requestClose: requestClose,
        onArenaRequestClose: onArenaRequestClose,
        requestCustomResultReturnBase: requestCustomResultReturnBase,
        onClose: onClose,
        showGridView: showGridView,
        showCustomEditorForSide: showCustomEditorForSide
    };
})();
