/**
 * arena-core.js — 竞技场面板 P4 工程拆分 · 共享基座：状态容器 + 跨模块工具 + 共享常量。
 *
 * 本文件由 modules/arena-panel.js 单文件 IIFE 机械拆分而来（纯移动：行为 / 协议 payload /
 * DOM id·class 契约 / QA 断言不变）。转换规则：原顶层 `var _x` 状态 → ArenaCore.state._x（本文件内
 * 以 `S._x` 访问）；跨模块函数/常量引用 → `模块全局.名字`。加载顺序由 panels-lazy-registry 的
 * arena 注册项与 arena/dev/harness.html script 区固定（与本文件守卫一致）。
 * 依赖守卫：workbench 共享层（lifecycle/focus/primitives/profile/workbench.js/components）必须在自身之前加载——沿用 P2 fail-fast 语义与报错文案（lazy closure 测试锚定）。
 */
(function() {
    'use strict';

    if (typeof Workbench === 'undefined' || typeof WorkbenchComponents === 'undefined') {
        throw new Error('arena/arena-core.js 需要先加载 workbench-lifecycle/focus/primitives/profile/workbench.js/components 共享层');
    }

    // ── 状态容器（原 arena-panel.js 顶层 `var _x` 全量平移，初始化值逐字保留）──
    var state = {};

    // ════════════════════════════════════════════════════════════════════════════
    // 状态
    // ════════════════════════════════════════════════════════════════════════════
    state._activeMode = 'standard';
    state._activeCards = []; // 当前模式的卡片集（标准=会话生成；堕落/爬升=派生；定制=入口卡）
    state._el = undefined;
    state._shellEl = undefined;
    state._scaleHandle = null;   // 沉浸全屏化：PanelScale 句柄
    state._gridViewEl = undefined;
    state._customOverviewEl = undefined;     // 定制赛总览覆盖层（壳 body 隐藏时承载入口卡，D2 总览独立）
    state._customGridEl = undefined;
    state._customResultViewEl = undefined;
    state._customEditorViewEl = undefined;
    state._moneyEl = undefined;
    // ── P2 共享工作台壳 ──
    state._shell = null;         // Workbench.DualPaneShell（catalog-decision）
    state._shellBodyEl = null;   // 壳 body（定制赛模式整体隐藏 → 总览覆盖，core.css 壳级 [hidden] 规则）
    state._modesNav = null;      // 模式 tabs（壳 header 第一个 action，team 同款注入）
    state._density = null;       // GridDensityController（目录完整/紧凑，localStorage 持久）
    state._densityToggle = null;
    state._helpAction = null;
    state._closeButton = null;
    state._browseL = null;       // 左栏视图：挑战目录
    state._browseR = null;       // 右栏视图：选中挑战 preview + 唯一确认区
    state._catalogRoot = null;
    state._catalogGridEl = null; // #arena-grid：左栏卡目录（可滚，role=listbox）
    state._decisionRoot = null;
    state._rollOneBtn = null;    // 左栏控件条「↻ 换一批」（单卡重抽，作用选中卡）
    state._rerollAllBtn = null;  // 左栏控件条「↻ 全部重抽」
    state._commitBar = null;     // WorkbenchComponents.CommitBar：决策面唯一主 CTA「⚔ 开始挑战」
    state._detailTitleEl = undefined;
    state._detailMetaEl = undefined;
    state._detailOpponentsEl = undefined;
    state._cardEls = [];
    state._pendingReq = {};
    state._reqSeq = 0;
    state._session = 0;
    state._snapshot = null;
    state._busy = false;
    state._selectedCardIdx = -1; // 当前选中的卡片下标（P2 选中语义）；-1 表示未选
    state._previewOpponents = null; // 当前选中卡右栏显示的对手数据
    state._catalogScroll = {};      // 模式内滚动记忆：mode → scrollTop（切回恢复；新 session 归顶）
    state._ttCache = {};            // (name|level) → {descHTML, introHTML, displayname}
    state._toastTimer = null;
    state._initDifficulty = '';     // initData.difficulty（来自 stage-select 重定向）→ enter 时回传 AS2
    // batch preview 缓存：panel open 时并发抽当前卡片集，结果按 cardIdx 落 cache。
    // grid 摘要 + 右栏 preview 共用同一份 cache。WYSIWYG: 用户在目录上看到的对手 = enter 时实际打到的人。
    // AS2 端有镜像缓存 _root._arenaLineupCache（同 cardIdx 索引），handleEnter 按 cardIndex 取出 commit。
    state._previewCache = {};       // cardIdx → opponents[]（成功时填入）
    // P2（P0 裁决 3）：pending 记录从裸 reqId 升级为隔离三元组 {reqId, mode, cardKey, gen}——
    // 模式 + 稳定卡 ID + session/generation 任一漂移，迟到回包即丢弃（见 requestPreviewForCard）。
    state._previewPending = {};     // cardIdx → {reqId, mode, cardKey, gen}（dedup：pending 中不重发）
    state._previewGen = {};         // cardIdx → 单调递增 generation（每次强制重抽 +1）
    state._previewError = {};       // cardIdx → error string（失败 → 摘要显示"加载失败 ↻"）
    // ── 元战队 / 混编 roster 混入（M2 / 堕落模式雏形）──
    // 每卡每次抽取先决定种类（merc / monster / mixed）。roster 类走 web 本地采样（无 AS2 preview 往返），
    // enter 时把采样小队作为 roster 下发 AS2（commitRoster 生成兵种阵容）。
    // 数据源 window.ArenaMetaRosters（arena-meta-rosters.js，由 derive-arena-meta-teams.js 派生）；
    // factions 用于按势力拆兵种单体兜底采样，teams 用于怪物组 / 混编优先复用真实关卡组合。
    // 未载入（如 QA harness）时 sampleMonsterSquad 恒返回 null → 全卡 merc，旧行为不变。
    state._cardKind = {};       // cardIdx → 'merc' | 'monster' | 'mixed'
    state._monsterSquad = {};   // cardIdx → { faction, opponents:[{name,level,type,spritename,isMonster:true}] }
    state._knownEnemies = {};   // spritename → true；来自 AS2 snapshot 的 killStats.byType
    state._knownEnemyCount = 0;
    state._customMatch = null;  // 定制赛：赛程代码解析状态
    state._customRun = null;    // 定制赛 P2：后台 single-case 运行状态
    state._customResult = null; // 定制赛结算回开 initData 摘要
    state._customEditor = null; // 定制赛 P3a：可视化 roster 编辑状态
    state._customSelectedSide = 'blue';
    state._customEditorPage = 'config';
    state._customParamEditor = null;
    state._customSavedRosters = null;
    state._customConfirmOpen = false;
    state._customPollTimer = 0;
    state._customSampleIndex = 0;
    state._customUndo = null;
    state._customResultReturnBaseRequired = false;
    state._customSelectOpen = null;
    // ── P3 定制赛选择性收敛：共享承载机制 ──
    state._customParamPage = null;    // WorkbenchComponents.SecondaryPage：深层参数页（inert/Esc 分层/opener 归还）
    state._customEditorScope = null;  // WorkbenchFocus.FocusScope：编辑器整页视图焦点栈层
    state._customResultScope = null;  // WorkbenchFocus.FocusScope：结算页整页视图焦点栈层
    state._customParamOpener = null;  // 打开参数页的阵容行「参数」按钮（关闭后焦点归还目标）
    state._customConfirmBar = null;   // WorkbenchComponents.CommitBar：定制赛确认条主 CTA 状态投影

    var ARENA_DIFFICULTY_LABELS = [
        { maxLevel: 5,   tier: 1, label: '菜鸟' },
        { maxLevel: 10,  tier: 2, label: '拾荒者' },
        { maxLevel: 15,  tier: 3, label: '见习队员' },
        { maxLevel: 20,  tier: 4, label: '骨干老兵' },
        { maxLevel: 30,  tier: 5, label: '精英队长' },
        { maxLevel: 35,  tier: 5, label: '战线王牌' },
        { maxLevel: 40,  tier: 6, label: '兵团利刃' },
        { maxLevel: 50,  tier: 6, label: '佣兵传奇' },
        { maxLevel: 60,  tier: 6, label: '禁区噩梦' },
        { maxLevel: 100, tier: 6, label: '审判日行刑官' }
    ];

    function randomInt(lo, hi) {
        lo = Math.round(lo);
        hi = Math.round(hi);
        if (hi < lo) hi = lo;
        return lo + Math.floor(Math.random() * (hi - lo + 1));
    }

    function clampInt(v, lo, hi) { v = Math.round(v); return v < lo ? lo : (v > hi ? hi : v); }
    function roundTo(v, step) { return Math.max(step, Math.round(v / step) * step); }

    function normalizeSearchText(text) {
        return String(text || '').toLowerCase().replace(/\s+/g, '');
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 工具
    // ════════════════════════════════════════════════════════════════════════════
    function showToast(text) {
        var toastEl = state._el.querySelector('#arena-toast');
        if (!toastEl) return;
        toastEl.textContent = text;
        toastEl.style.display = 'block';
        toastEl.classList.add('arena-toast-visible');
        clearTimeout(state._toastTimer);
        state._toastTimer = setTimeout(hideToast, 3000);
    }

    function hideToast() {
        var toastEl = state._el.querySelector('#arena-toast');
        if (!toastEl) return;
        toastEl.classList.remove('arena-toast-visible');
        toastEl.style.display = 'none';
    }

    function formatMoney(n) {
        if (typeof n !== 'number') return String(n);
        return n.toLocaleString('zh-CN');
    }

    // 难度档位：按对手最高等级映射「热度」tier（1 安全 → 6 致命）+ 竞技场专属称号风格标签。
    // 标签借用主角称号的语感，但不直接读取 hero_titles.xml，避免玩家履历称号和挑战风险耦合。
    function difficultyOf(card) {
        var lm = card.levelMax;
        for (var i = 0; i < ARENA_DIFFICULTY_LABELS.length; i++) {
            if (lm <= ARENA_DIFFICULTY_LABELS[i].maxLevel) {
                return { tier: ARENA_DIFFICULTY_LABELS[i].tier, label: ARENA_DIFFICULTY_LABELS[i].label };
            }
        }
        return { tier: 6, label: ARENA_DIFFICULTY_LABELS[ARENA_DIFFICULTY_LABELS.length - 1].label };
    }

    function escapeHtml(text) {
        var div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    function escapeAttr(text) {
        return String(text).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
    }

    // 导出：状态容器 + 被其它 arena 模块引用的工具/常量
    if (typeof window === 'undefined') throw new Error('arena/arena-core.js 需要浏览器 window 环境');
    window.ArenaCore = {
        state: state,
        randomInt: randomInt,
        clampInt: clampInt,
        roundTo: roundTo,
        normalizeSearchText: normalizeSearchText,
        showToast: showToast,
        hideToast: hideToast,
        formatMoney: formatMoney,
        difficultyOf: difficultyOf,
        escapeHtml: escapeHtml,
        escapeAttr: escapeAttr
    };
})();
