(function() {
    'use strict';

    // ════════════════════════════════════════════════════════════════════════════
    // 配置数据（从 data/arena/arena_config.xml 提取）
    // ════════════════════════════════════════════════════════════════════════════
    var ARENA_CARDS = [
        { id: 'arena-1', index: 1, name: 'DEATH MATCH角斗场', opponentCount: 1, levelMin: 1,  levelMax: 5,  deposit: 500,    reward: 1000,   expr: '#0@1-5%1' },
        { id: 'arena-2', index: 2, name: 'DEATH MATCH角斗场', opponentCount: 2, levelMin: 5,  levelMax: 10, deposit: 5000,   reward: 10000,  expr: '#0@5-10%2' },
        { id: 'arena-3', index: 3, name: 'DEATH MATCH角斗场', opponentCount: 2, levelMin: 10, levelMax: 15, deposit: 10000,  reward: 20000,  expr: '#0@10-15%2' },
        { id: 'arena-4', index: 4, name: 'DEATH MATCH角斗场', opponentCount: 2, levelMin: 10, levelMax: 15, deposit: 20000,  reward: 40000,  expr: '#0@10-15%2' },
        { id: 'arena-5', index: 5, name: 'DEATH MATCH角斗场', opponentCount: 4, levelMin: 15, levelMax: 20, deposit: 30000,  reward: 60000,  expr: '#0@15-20%4' },
        { id: 'arena-6', index: 6, name: 'DEATH MATCH角斗场', opponentCount: 4, levelMin: 15, levelMax: 20, deposit: 30000,  reward: 60000,  expr: '#0@15-20%4' },
        { id: 'arena-7', index: 7, name: 'DEATH MATCH角斗场', opponentCount: 1, levelMin: 20, levelMax: 40, deposit: 12500,  reward: 25000,  expr: '#0@20-40%1' },
        { id: 'arena-8', index: 8, name: 'DEATH MATCH角斗场', opponentCount: 4, levelMin: 40, levelMax: 60, deposit: 100000, reward: 200000, expr: '#0@40-60%4' }
    ];

    var CUSTOM_MATCH_FALLBACK_CODE =
        'CF7ARENA:v1;mode=mvm;seed=90210;blue=u44@30x2,u48@30x1;red=u164@60x1,u11@30x1';
    var CUSTOM_PVE_FALLBACK_CODE =
        'CF7ARENA:v1;mode=pve;seed=3307;enemy=u44@30x1;player=current';
    var CUSTOM_BROWSER_BATCH_SIZE = 80;
    var CUSTOM_SAVED_ROSTERS_KEY = 'cf7.arena.custom.savedRosters.v1';
    var CUSTOM_SAVED_ROSTER_LIMIT = 24;
    var CUSTOM_MATCH_CARD = {
        id: 'custom-match-p1',
        index: 0,
        name: '定制死亡竞赛',
        isCustom: true,
        opponentCount: 0,
        levelMin: 1,
        levelMax: 60,
        deposit: 0,
        reward: 0,
        expr: ''
    };

    // 竞技场模式（顶部 tab 条，视觉对齐战队界面 .team-tab）。
    // 当前仅「标准模式」；后续不同玩法在此追加 { id, label }，并在 onModeClick 扩展点接入
    // 各模式自己的卡片集 / preview 逻辑。结构先就位，避免把模式硬编进单一卡片列表。
    var ARENA_MODES = [
        { id: 'standard', label: '标准模式' },
        { id: 'custom', label: '定制赛' },
        // 堕落模式（Phase 2）：势力主题固定挑战。每张卡 = 一个势力，对手全部从该势力 roster
        // 采样非人形怪（复用 Phase1 的 roster 入场通路，AS2 零改动——合成 expr 只为过校验）。
        // 需 arena-meta-rosters.js 已载（rostersAvailable）才显示该 tab；
        // QA harness 未载 → buildModeTabs 跳过本项 → 仅标准模式，行为/卡数不变。
        { id: 'fallen', label: '堕落模式', requiresRosters: true },
        // 爬升模式（Phase 3）：势力主题无限爬升 + 奖池押注（拿钱/续战走战斗内压力板位置决策）。
        // 复用势力卡（与堕落同源），进场发 mode="escalation" + 该势力单位池；战斗循环全在 AS2 自管。
        { id: 'escalation', label: '爬升模式', requiresRosters: true }
    ];

    // 堕落模式卡片派生参数（业务可调）。
    var FALLEN_MIN_UNITS = 4;     // 势力 roster 单位数门槛（剔单例 boss/误分类势力，如 联合大学/斯巴达）
    var FALLEN_BAND_WINDOW = 15;  // 精英窗口：取势力顶端 N 级为挑战带，避免 1-60 这种跨度让挑战失焦

    // ════════════════════════════════════════════════════════════════════════════
    // 状态
    // ════════════════════════════════════════════════════════════════════════════
    var _activeMode = 'standard';
    var _activeCards = ARENA_CARDS; // 当前模式的卡片集（标准=ARENA_CARDS；堕落=buildFallenCards()）；rebuildForMode 切换
    var _el, _shellEl;
    var _scaleHandle = null;   // 沉浸全屏化：PanelScale 句柄
    var _gridViewEl;
    var _detailViewEl;
    var _customResultViewEl;
    var _customEditorViewEl;
    var _moneyEl;
    var _detailTitleEl;
    var _detailMetaEl;
    var _detailOpponentsEl;
    var _detailRollBtn;
    var _detailConfirmBtn;
    var _cardEls = [];
    var _pendingReq = {};
    var _reqSeq = 0;
    var _session = 0;
    var _snapshot = null;
    var _busy = false;
    var _activeCardIdx = -1;     // 当前进入详情的卡片下标；-1 表示在 grid
    var _previewOpponents = null; // 当前显示的对手数据
    var _ttCache = {};            // (name|level) → {descHTML, introHTML, displayname}
    var _ttHoverKey = null;       // 当前 hover 的 cache key
    var _toastTimer = null;
    var _initDifficulty = '';     // initData.difficulty（来自 stage-select 重定向）→ enter 时回传 AS2
    // batch preview 缓存：panel open 时并发抽 8 卡，结果按 cardIdx 落 cache。
    // grid 摘要 + detail 视图共用同一份 cache。WYSIWYG: 用户在 grid 上看到的对手 = enter 时实际打到的人。
    // AS2 端有镜像缓存 _root._arenaLineupCache（同 cardIdx 索引），handleEnter 按 cardIndex 取出 commit。
    var _previewCache = {};       // cardIdx → opponents[]（成功时填入）
    var _previewPending = {};     // cardIdx → reqId（dedup：pending 中不重发）
    var _previewError = {};       // cardIdx → error string（失败 → 摘要显示"加载失败 ↻"）
    // ── 元战队（非人形怪）混入（M2 / 堕落模式雏形）──
    // 每卡每次抽取先决定种类（merc / monster）。monster 走 web 本地 roster 采样（无 AS2 preview 往返），
    // enter 时把采样小队作为 roster 下发 AS2（commitRoster 生成非人形怪）。
    // 数据源 window.ArenaMetaRosters（arena-meta-rosters.js，由 derive-arena-meta-teams.js 派生）；
    // 未载入（如 QA harness）时 sampleMonsterSquad 恒返回 null → 全卡 merc，旧行为不变。
    var _cardKind = {};       // cardIdx → 'merc' | 'monster'
    var _monsterSquad = {};   // cardIdx → { faction, opponents:[{name,level,type,spritename,isMonster:true}] }
    var _mixChance = 0.35;    // 单卡判为怪物小队的概率（setMixChance 可调，QA/截图注入用）
    var _knownEnemies = {};   // spritename → true；来自 AS2 snapshot 的 killStats.byType
    var _knownEnemyCount = 0;
    var _customMatch = null;  // 定制赛：赛程代码解析状态
    var _customRun = null;    // 定制赛 P2：后台 single-case 运行状态
    var _customResult = null; // 定制赛结算回开 initData 摘要
    var _customEditor = null; // 定制赛 P3a：可视化 roster 编辑状态
    var _customSelectedSide = 'blue';
    var _customEditorPage = 'config';
    var _customParamEditor = null;
    var _customSavedRosters = null;
    var _customConfirmOpen = false;
    var _customPollTimer = 0;
    var _customSampleIndex = 0;
    var _customUndo = null;
    var _customResultReturnBaseRequired = false;

    // ════════════════════════════════════════════════════════════════════════════
    // Panel 注册
    // ════════════════════════════════════════════════════════════════════════════
    Panels.register('arena', {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: onArenaRequestClose,
        onClose: onClose
    });

    // ════════════════════════════════════════════════════════════════════════════
    // DOM 创建
    // ════════════════════════════════════════════════════════════════════════════
    function createDOM(container) {
        _el = document.createElement('div');
        _el.className = 'arena-panel';
        _el.innerHTML =
            '<div class="arena-header">' +
                '<span class="arena-title-mark"></span>' +
                '<div class="arena-title-block">' +
                    '<h1 class="arena-title">DEATH MATCH</h1>' +
                    '<span class="arena-subtitle">角斗场 · 生死竞技</span>' +
                '</div>' +
                '<div class="arena-header-spacer"></div>' +
                '<div class="arena-money">' +
                    '<span class="arena-money-label">金钱</span>' +
                    '<span class="arena-money-value" id="arena-money-value">--</span>' +
                '</div>' +
                '<button class="arena-close-btn" type="button" title="关闭" aria-label="关闭" data-audio-cue="cancel">✕</button>' +
            '</div>' +
            '<div class="arena-grid-view" id="arena-grid-view">' +
                // 模式条：首个 = 标准模式；tab 语言对齐战队界面，后续可扩展不同竞技场模式
                '<div class="arena-toolbar arena-modebar">' +
                    '<div class="arena-modes" id="arena-modes">' + buildModeTabs() + '</div>' +
                '</div>' +
                '<div class="arena-grid" id="arena-grid"></div>' +
            '</div>' +
            '<div class="arena-custom-result-view" id="arena-custom-result-view" hidden></div>' +
            '<div class="arena-custom-editor-view" id="arena-custom-editor-view" hidden>' + buildCustomEditorViewHtml() + '</div>' +
            '<div class="arena-detail-view" id="arena-detail-view" hidden>' +
                '<div class="arena-detail-header">' +
                    '<button class="arena-detail-back" type="button" data-audio-cue="cancel">‹ 返回</button>' +
                    '<div class="arena-detail-title-block">' +
                        '<h2 class="arena-detail-title" id="arena-detail-title">--</h2>' +
                        '<div class="arena-detail-meta" id="arena-detail-meta"></div>' +
                    '</div>' +
                    '<button class="arena-detail-roll" type="button" data-audio-cue="confirm" title="重新抽取对手（免费）">↻ 换一批</button>' +
                '</div>' +
                '<div class="arena-opponents" id="arena-opponents"></div>' +
                '<div class="arena-detail-footer">' +
                    '<button class="arena-detail-confirm" type="button" data-audio-cue="confirm">⚔ 确认挑战</button>' +
                '</div>' +
            '</div>' +
            '<div class="arena-toast" id="arena-toast"></div>';

        _gridViewEl = _el.querySelector('#arena-grid-view');
        _detailViewEl = _el.querySelector('#arena-detail-view');
        _customResultViewEl = _el.querySelector('#arena-custom-result-view');
        _customEditorViewEl = _el.querySelector('#arena-custom-editor-view');
        _moneyEl = _el.querySelector('#arena-money-value');
        _detailTitleEl = _el.querySelector('#arena-detail-title');
        _detailMetaEl = _el.querySelector('#arena-detail-meta');
        _detailOpponentsEl = _el.querySelector('#arena-opponents');
        _detailRollBtn = _el.querySelector('.arena-detail-roll');
        _detailConfirmBtn = _el.querySelector('.arena-detail-confirm');

        _el.querySelector('.arena-close-btn').addEventListener('click', onArenaRequestClose);
        _el.querySelector('.arena-detail-back').addEventListener('click', backToGrid);
        _customResultViewEl.addEventListener('click', onCustomResultClick);
        _customEditorViewEl.addEventListener('click', onCustomWorkbenchClick);
        _customEditorViewEl.addEventListener('change', onCustomWorkbenchChange);
        _customEditorViewEl.addEventListener('input', onCustomEditorInput);
        var customUnitListEl = _el.querySelector('#arena-custom-unit-list');
        if (customUnitListEl) customUnitListEl.addEventListener('scroll', onCustomUnitBrowserScroll);
        _detailRollBtn.addEventListener('click', onRollAgain);
        _detailConfirmBtn.addEventListener('click', onConfirmChallenge);

        bindModeTabs();

        buildCards();

        if (typeof Icons !== 'undefined') Icons.load(function(){});

        // 沉浸全屏化 2026-06-12：固定 1024×576 画布(.arena-panel)包进共享 .panel-scale-shell，
        // 整体等比缩放铺满全 anchor（取代旧 fluid 居中子矩形卡片）。
        _shellEl = document.createElement('div');
        _shellEl.className = 'panel-scale-shell arena-scale-shell';
        _shellEl.appendChild(_el);
        return _shellEl;
    }

    function buildCards() {
        var gridEl = _el.querySelector('#arena-grid');
        gridEl.innerHTML = '';
        _cardEls = [];
        // 卡片多于单屏（>8，如堕落模式 18 张）→ 切顶部对齐的滚动布局；否则维持 8 卡铺满（标准模式不变）
        gridEl.classList.toggle('arena-grid-scroll', _activeCards.length > 8);
        gridEl.classList.toggle('arena-grid-custom', _activeMode === 'custom');

        for (var i = 0; i < _activeCards.length; i++) {
            var card = _activeCards[i];
            var diff = difficultyOf(card);
            if (card.isCustom) {
                var customCardEl = buildCustomMatchCard(i, card, diff);
                gridEl.appendChild(customCardEl);
                _cardEls.push(customCardEl);
                continue;
            }
            var isFallen = !!card.isFallen;
            var cardEl = document.createElement('div');
            // d{1..6} 类驱动 --d-color 难度热度（CSS .arena-card-d* → 顶部色条 + 难度标签色）。
            // 堕落卡恒非人形 → 建卡即上 arena-card-monster（紫罗兰），不等采样回调。
            cardEl.className = 'arena-card arena-card-d' + diff.tier + (isFallen ? ' arena-card-monster' : '');
            cardEl.dataset.index = i;
            // 标准卡 rank = 段位号；堕落卡 rank = 势力名（卡片身份）+ 阵容 cap 改「麾下阵容」
            var rankHtml = isFallen
                ? '<span class="arena-card-rank arena-card-rank-faction">' + escapeHtml(card.faction) + '</span>'
                : '<span class="arena-card-rank">段位 ' + card.index + '</span>';
            var oppCapText = isFallen ? '麾下阵容' : '对手阵容';
            cardEl.innerHTML =
                '<div class="arena-card-frame"></div>' +
                '<div class="arena-card-header">' +
                    rankHtml +
                    '<span class="arena-card-icon">⚔</span>' +
                    '<span class="arena-card-diff">' + diff.label + '</span>' +
                '</div>' +
                '<div class="arena-card-body">' +
                    '<div class="arena-card-stats">' +
                        '<div class="arena-stat">' +
                            '<span class="arena-stat-label">对手</span>' +
                            '<span class="arena-stat-value">×' + card.opponentCount + '</span>' +
                        '</div>' +
                        '<div class="arena-stat">' +
                            '<span class="arena-stat-label">等级</span>' +
                            '<span class="arena-stat-value">' + card.levelMin + '–' + card.levelMax + '</span>' +
                        '</div>' +
                    '</div>' +
                    // 奖金主视觉（金色大字）/ 押金次视觉，回应"押注挑战"的风险-回报心智模型
                    '<div class="arena-card-prize">' +
                        '<div class="arena-prize-main">' +
                            '<span class="arena-prize-label">奖金</span>' +
                            '<span class="arena-prize-value">' + formatMoney(card.reward) + '</span>' +
                        '</div>' +
                        '<div class="arena-prize-deposit">押金 ' + formatMoney(card.deposit) + '</div>' +
                    '</div>' +
                    // 对手摘要 row：snapshot 回包后 batchRequestPreview 触发 8 卡并发抽签，
                    // 单卡回包后 renderCardSummary(cardIdx) 写入下方 span。
                    '<div class="arena-card-opponents-row">' +
                        '<span class="arena-card-opponents-cap">' + oppCapText + '</span>' +
                        '<span class="arena-card-opponents arena-card-opponents-loading" id="arena-opp-summary-' + i + '">抽取中…</span>' +
                    '</div>' +
                '</div>' +
                // 主+次按钮：主 ⚔ 开始挑战（grid 直入战场，无需进 detail）；次 🔍 查看对手（进 detail 看装备 / 换一批）
                '<div class="arena-card-actions">' +
                    '<button class="arena-card-btn-enter" type="button" data-index="' + i + '" data-audio-cue="confirm">⚔ 开始挑战</button>' +
                    '<button class="arena-card-btn-detail" type="button" data-index="' + i + '" data-audio-cue="confirm" title="查看对手详情">🔍</button>' +
                '</div>';

            cardEl.querySelector('.arena-card-btn-enter').addEventListener('click', onDirectEnter);
            cardEl.querySelector('.arena-card-btn-detail').addEventListener('click', onCardClick);
            gridEl.appendChild(cardEl);
            _cardEls.push(cardEl);
        }
    }

    function buildCustomEditorViewHtml() {
        return '<div class="arena-custom-editor-header">' +
                '<button class="arena-custom-btn" type="button" data-custom-editor-action="back" data-audio-cue="cancel">返回配置</button>' +
                '<div class="arena-custom-editor-title-block">' +
                    '<div class="arena-custom-editor-kicker">定制赛阵容</div>' +
                    '<div class="arena-custom-editor-title">配置赛程与阵容</div>' +
                    '<div class="arena-custom-editor-meta">配置总览管理赛程与双方阵容，单方编辑页提供完整单位目录空间</div>' +
                '</div>' +
                    '<div class="arena-custom-editor-actions">' +
                        '<button class="arena-custom-btn" type="button" id="arena-custom-undo" data-custom-editor-action="undo" data-audio-cue="cancel" disabled>撤销</button>' +
                        '<button class="arena-card-btn-enter" type="button" data-custom-editor-action="done" data-audio-cue="confirm">完成</button>' +
                    '</div>' +
            '</div>' +
            '<div class="arena-custom-editor-page arena-custom-config-page" data-custom-editor-page="config">' +
                '<div class="arena-custom-config-panel">' +
                    '<div class="arena-custom-config-code">' +
                        '<div class="arena-custom-mode-switch" aria-label="定制赛模式">' +
                            '<button class="arena-custom-btn" type="button" data-custom-mode="mvm" data-audio-cue="confirm">怪物 vs 怪物</button>' +
                            '<button class="arena-custom-btn" type="button" data-custom-mode="pve" data-audio-cue="confirm">玩家 vs 怪物</button>' +
                        '</div>' +
                        '<label class="arena-custom-code-label" for="arena-custom-code-input">赛程代码（实时解析）</label>' +
                        '<textarea id="arena-custom-code-input" class="arena-custom-code-input" rows="2" spellcheck="false"></textarea>' +
                        '<div class="arena-custom-code-status" id="arena-custom-code-status"></div>' +
                    '</div>' +
                    '<div class="arena-custom-config-tools">' +
                        '<label class="arena-custom-code-label" for="arena-custom-preset-select">整局待标定组合</label>' +
                        '<select id="arena-custom-preset-select" class="arena-custom-preset-select" aria-label="待标定组合">' + buildCustomPresetOptions() + '</select>' +
                        '<div class="arena-custom-actions arena-custom-editor-code-actions">' +
                            '<button class="arena-custom-btn" type="button" data-custom-action="preset" data-audio-cue="confirm">载入整局</button>' +
                            '<button class="arena-custom-btn" type="button" data-custom-action="random" data-audio-cue="confirm">随机整局</button>' +
                        '</div>' +
                        '<div class="arena-custom-actions arena-custom-editor-code-actions" id="arena-custom-swap-actions">' +
                            '<button class="arena-custom-btn" type="button" data-custom-action="import" data-audio-cue="confirm">校验代码</button>' +
                            '<button class="arena-custom-btn" type="button" data-custom-action="copy" data-audio-cue="confirm">复制代码</button>' +
                            '<button class="arena-custom-btn" type="button" data-custom-action="swap-sides" data-audio-cue="confirm">交换红蓝</button>' +
                        '</div>' +
                    '</div>' +
                '</div>' +
                '<div class="arena-custom-side-configs">' +
                    '<div class="arena-custom-side-config-card arena-custom-side-config-blue" id="arena-custom-config-blue"></div>' +
                    '<div class="arena-custom-side-config-card arena-custom-side-config-red" id="arena-custom-config-red"></div>' +
                '</div>' +
            '</div>' +
            '<div class="arena-custom-editor-page arena-custom-side-page" data-custom-editor-page="side" hidden>' +
                '<div class="arena-custom-side-editor-head">' +
                    '<div class="arena-custom-side-editor-title-block">' +
                        '<div class="arena-custom-editor-kicker" id="arena-custom-side-editor-kicker">蓝方阵容</div>' +
                        '<div class="arena-custom-editor-title" id="arena-custom-side-editor-title">编辑蓝方</div>' +
                        '<div class="arena-custom-editor-meta" id="arena-custom-side-editor-meta">--</div>' +
                    '</div>' +
                    '<div class="arena-custom-side-editor-actions">' +
                        '<select class="arena-custom-preset-select" data-custom-saved-select="active" aria-label="已保存配置"></select>' +
                        '<button class="arena-custom-btn" type="button" data-custom-side-action="load" data-side="active" data-audio-cue="confirm">读取</button>' +
                        '<button class="arena-custom-btn" type="button" data-custom-side-action="save" data-side="active" data-audio-cue="confirm">保存</button>' +
                        '<button class="arena-custom-btn" type="button" data-custom-side-action="random" data-side="active" data-audio-cue="confirm">随机组合</button>' +
                        '<button class="arena-custom-btn" type="button" data-custom-side-action="clear" data-side="active" data-audio-cue="cancel">清空</button>' +
                    '</div>' +
                '</div>' +
                '<div class="arena-custom-side-workbench">' +
                    '<div class="arena-custom-roster-panel arena-custom-roster-active" id="arena-custom-active-roster-panel" data-side="blue">' +
                        '<div class="arena-custom-roster-head">' +
                            '<button class="arena-custom-roster-tab" type="button" data-custom-editor-action="to-config" data-audio-cue="cancel">返回总览</button>' +
                            '<span class="arena-custom-roster-head-count" id="arena-custom-active-roster-count">--</span>' +
                        '</div>' +
                        '<div class="arena-custom-roster-list" id="arena-custom-active-roster"></div>' +
                    '</div>' +
                    '<div class="arena-custom-browser">' +
                    '<div class="arena-custom-browser-toolbar">' +
                        '<div class="arena-custom-side-switch" aria-label="添加目标">' +
                            '<button type="button" data-custom-side="blue" data-audio-cue="confirm">加到蓝方</button>' +
                            '<button type="button" data-custom-side="red" data-audio-cue="confirm">加到红方</button>' +
                        '</div>' +
                        '<input id="arena-custom-unit-search" class="arena-custom-unit-search" type="search" placeholder="搜索 ID / 名称 / 素材" spellcheck="false">' +
                        '<span class="arena-custom-unit-count" id="arena-custom-unit-count">--</span>' +
                    '</div>' +
                    '<div class="arena-custom-unit-filters">' +
                        '<button type="button" data-custom-unit-filter="all" data-audio-cue="confirm">全部</button>' +
                        '<button type="button" data-custom-unit-filter="hostile" data-audio-cue="confirm">敌对</button>' +
                        '<button type="button" data-custom-unit-filter="nonhostile" data-audio-cue="confirm">非敌对</button>' +
                    '</div>' +
                    '<div class="arena-custom-unit-list" id="arena-custom-unit-list"></div>' +
                    '</div>' +
                '</div>' +
            '</div>' +
            '<div class="arena-custom-editor-page arena-custom-param-page" data-custom-editor-page="params" hidden>' +
                '<div class="arena-custom-param-editor-head">' +
                    '<div class="arena-custom-side-editor-title-block">' +
                        '<div class="arena-custom-editor-kicker" id="arena-custom-param-editor-kicker">单位参数</div>' +
                        '<div class="arena-custom-editor-title" id="arena-custom-param-editor-title">编辑参数</div>' +
                        '<div class="arena-custom-editor-meta" id="arena-custom-param-editor-meta">--</div>' +
                    '</div>' +
                    '<div class="arena-custom-param-editor-actions">' +
                        '<button class="arena-custom-btn" type="button" data-custom-param-action="back" data-audio-cue="cancel">返回阵容</button>' +
                        '<button class="arena-custom-btn" type="button" data-custom-param-action="apply" data-audio-cue="confirm">应用</button>' +
                        '<button class="arena-card-btn-enter" type="button" data-custom-param-action="save-back" data-audio-cue="confirm">保存返回</button>' +
                    '</div>' +
                '</div>' +
                '<div class="arena-custom-param-editor-body" id="arena-custom-param-editor-body"></div>' +
            '</div>';
    }

    function buildCustomMatchCard(index, card, diff) {
        var cardEl = document.createElement('div');
        cardEl.className = 'arena-card arena-card-custom arena-card-d' + diff.tier;
        cardEl.dataset.index = index;
        cardEl.innerHTML =
            '<div class="arena-card-frame"></div>' +
            '<div class="arena-card-header">' +
                '<span class="arena-card-rank">定制赛</span>' +
                '<span class="arena-card-icon">⚔</span>' +
                '<span class="arena-card-diff">P2</span>' +
            '</div>' +
            '<div class="arena-card-body arena-custom-body">' +
                '<div class="arena-custom-title-row">' +
                    '<div>' +
                        '<div class="arena-custom-title">定制死亡竞赛</div>' +
                        '<div class="arena-custom-subtitle">怪物 vs 怪物 · 后台单局 · 无掉落无经验</div>' +
                    '</div>' +
                    '<span class="arena-opp-monster-tag">无掉落 / 无经验</span>' +
                '</div>' +
                '<div class="arena-custom-layout">' +
                    '<div class="arena-custom-playbook">' +
                        '<div class="arena-custom-section-title">当前对阵</div>' +
                        '<div class="arena-custom-summary" id="arena-custom-summary"></div>' +
                        '<div class="arena-custom-rulebar">' +
                            '<span id="arena-custom-case">--</span>' +
                            '<span id="arena-custom-status">状态：未委托</span>' +
                        '</div>' +
                    '</div>' +
                '</div>' +
                '<div class="arena-custom-confirm" id="arena-custom-confirm" hidden></div>' +
            '</div>' +
            '<div class="arena-card-actions arena-custom-footer">' +
                '<div class="arena-custom-fee">' +
                    '<span class="arena-prize-label">估算场地费</span>' +
                    '<span class="arena-prize-value" id="arena-custom-fee">--</span>' +
                '</div>' +
                '<button class="arena-custom-btn arena-custom-abort" type="button" data-audio-cue="cancel">中止</button>' +
                '<button class="arena-custom-btn arena-custom-edit" type="button" data-custom-action="edit" data-audio-cue="confirm">编辑配置</button>' +
                '<button class="arena-card-btn-enter arena-custom-generate" type="button" data-audio-cue="confirm">检查并确认</button>' +
            '</div>';

        cardEl.addEventListener('click', onCustomWorkbenchClick);
        cardEl.querySelector('.arena-custom-generate').addEventListener('click', onCustomGenerate);
        cardEl.querySelector('.arena-custom-abort').addEventListener('click', onCustomAbort);
        return cardEl;
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
        if (!rostersAvailable() || _knownEnemyCount <= 0) return false;
        return buildFallenCards().length > 0;
    }

    function bindModeTabs() {
        if (!_el) return;
        var modeTabs = _el.querySelectorAll('.arena-mode-tab');
        for (var mt = 0; mt < modeTabs.length; mt++) {
            modeTabs[mt].addEventListener('click', onModeClick);
        }
    }

    function refreshModeTabs() {
        if (!_el) return;
        var modesEl = _el.querySelector('#arena-modes');
        if (!modesEl) return;
        modesEl.innerHTML = buildModeTabs();
        bindModeTabs();
    }

    // 模式 tab 条（对齐战队界面 tab）。requiresRosters 的模式仅在数据就绪时出现。
    function buildModeTabs() {
        var html = '';
        for (var i = 0; i < ARENA_MODES.length; i++) {
            var m = ARENA_MODES[i];
            if (!modeAvailable(m)) continue;
            var active = (m.id === _activeMode) ? ' arena-mode-tab-active' : '';
            html += '<button class="arena-mode-tab' + active + '" type="button"' +
                    ' data-mode="' + escapeAttr(m.id) + '" data-audio-cue="confirm">' +
                    escapeHtml(m.label) + '</button>';
        }
        return html;
    }

    // 模式切换：重建该模式的卡片集 + 清空全部 per-card 状态（卡 index 含义随模式变，旧 cache 失效），
    // 重发 batch preview（snapshot 已到才发；未到则由 snapshot 回调按当前 _activeCards 补发）。
    function onModeClick(e) {
        if (_busy) return;
        var btn = e.currentTarget;
        var mode = btn.getAttribute('data-mode');
        if (!mode || mode === _activeMode) return;
        if (!modeAvailable(mode)) return;
        rebuildForMode(mode);
        if (_snapshot) batchRequestPreview();
    }

    // 按模式重建卡片集与 DOM，并复位 per-card 派生状态。不发请求（caller 决定何时 batch）。
    function rebuildForMode(mode) {
        if (mode !== 'custom') clearCustomPoll();
        _activeMode = mode;
        _activeCards = (mode === 'fallen') ? buildFallenCards()
                     : (mode === 'escalation') ? buildEscalationCards()
                     : (mode === 'custom') ? [CUSTOM_MATCH_CARD]
                     : ARENA_CARDS;
        // 切模式让所有卡 index 重新映射 → 旧 preview/kind/squad 缓存全部作废，避免跨模式串卡
        _previewCache = {};
        _previewPending = {};
        _previewError = {};
        _cardKind = {};
        _monsterSquad = {};
        _activeCardIdx = -1;
        _previewOpponents = null;
        // tab active 态
        var tabs = _el ? _el.querySelectorAll('.arena-mode-tab') : [];
        for (var i = 0; i < tabs.length; i++) {
            tabs[i].classList.toggle('arena-mode-tab-active', tabs[i].getAttribute('data-mode') === mode);
        }
        buildCards();       // 重建 grid DOM（_activeCards 驱动）+ 重挂卡片按钮监听 + 摘要回 loading 态
        if (mode === 'custom') refreshCustomMatchCard();
        showGridView();
        updateCardStates();
    }

    // 堕落模式卡片派生：每个合格势力 → 一张「精英挑战」卡。
    // 等级带取势力顶端 FALLEN_BAND_WINDOW 级（精英窗口）；对手数随等级档 4~6；
    // 押金/奖金按 等级×人数 线性派生（业务可调）。合成 expr 仅为过 AS2 handleEnter 的非空校验，
    // roster 分支不消费它（生成走 _root.角斗场roster阵容）。
    function buildFallenCards() {
        var factions = rostersAvailable() ? window.ArenaMetaRosters.factions : null;
        if (!factions) return [];
        var cards = [];
        for (var name in factions) {
            var units = factions[name].units || [];
            if (units.length < FALLEN_MIN_UNITS) continue;
            var knownUnits = filterKnownUnits(units);
            if (knownUnits.length === 0) continue;
            var meta = factionMeta(name);
            if (meta.enabled === false) continue;     // 手作禁用的势力不出卡
            var lo = 99999, hi = 0;
            for (var u = 0; u < knownUnits.length; u++) {
                if (knownUnits[u].minLevel < lo) lo = knownUnits[u].minLevel;
                if (knownUnits[u].maxLevel > hi) hi = knownUnits[u].maxLevel;
            }
            if (hi <= 0) continue;
            var levelMin = Math.max(lo, hi - FALLEN_BAND_WINDOW);
            var levelMax = hi;
            // 对标等级（手标等效挑战等级，廉价怪通常远低于原始等级）：缺省回退 levelMax。
            // 奖金/押金按对标等级算（而非原始怪物等级）→ 避免「难度太低奖励太高」。
            var benchLevel = (meta.benchLevel != null) ? meta.benchLevel : levelMax;
            var count = clampInt(3 + Math.floor(levelMax / 25), 4, 6); // 45~60→4~5；100→6
            var reward = roundTo(benchLevel * count * 800, 1000);
            var deposit = roundTo(reward * 0.4, 1000);
            cards.push({
                id: 'fallen-' + name,
                faction: name,
                displayName: meta.displayName || name,
                isFallen: true,
                name: 'DEATH MATCH角斗场',
                opponentCount: count,
                levelMin: levelMin,
                levelMax: levelMax,
                benchLevel: benchLevel,
                scale: meta.scale || null,        // small|large|coalition（爬升波数档）
                unitCount: knownUnits.length,
                deposit: deposit,
                reward: reward,
                expr: '#0@' + levelMin + '-' + levelMax + '%' + count
            });
        }
        // 按挑战带升序 → grid 呈现难度递进
        cards.sort(function(a, b) { return (a.levelMin - b.levelMin) || (a.levelMax - b.levelMax); });
        return cards;
    }

    function clampInt(v, lo, hi) { v = Math.round(v); return v < lo ? lo : (v > hi ? hi : v); }
    function roundTo(v, step) { return Math.max(step, Math.round(v / step) * step); }

    // 手作势力卡元数据（launcher/web/modules/arena-factions.js → window.ArenaFactions），缺省回退派生值。
    // 字段：benchLevel(对标等级=等效挑战等级，廉价怪远低于原始等级) / scale(small|large|coalition→波数 5|10|15)
    //       / enabled(false=不出卡) / displayName(叙事名) / units(兵种白名单，预留)。策划逐势力填，未配置即全回退。
    function factionMeta(faction) {
        var F = (typeof window !== 'undefined' && window.ArenaFactions && window.ArenaFactions.factions)
            ? window.ArenaFactions.factions[faction] : null;
        return F || {};
    }
    // 势力规模档 → 爬升波数上限。缺省按 roster 单位数猜（小<6 / 大<12 / 联军≥12）。
    function wavesForScale(scale, unitCount) {
        if (scale === 'coalition') return 15;
        if (scale === 'large') return 10;
        if (scale === 'small') return 5;
        return unitCount >= 12 ? 15 : (unitCount >= 6 ? 10 : 5);
    }

    // 爬升模式卡片（Phase 3）：与堕落卡同源（每势力一张），但带 isEscalation 标记 + 自己的押注经济。
    // 卡面/预览复用堕落（isFallen=true → 紫罗兰 + 起始波小队采样预览）；差异在进场 payload：
    // opponentCount/levelMin/levelMax 作为「起始波」基准，AS2 据势力单位池逐波爬升；maxWaves 为波数上限。
    // 经济：波奖励基准 = 标准模式单场净收益@对标等级 = 对标等级×base对手数×500；AS2 按线性斜坡逐波发奖
    //       （均值=效率目标 1.75 → 打满≈1.75×标准同时长收益）；押注 deposit≈一场净收益，战死没收。
    function buildEscalationCards() {
        var base = buildFallenCards();
        var out = [];
        for (var i = 0; i < base.length; i++) {
            var c = base[i];
            var maxWaves = wavesForScale(c.scale, c.unitCount);
            var waveBase = roundTo(c.benchLevel * c.opponentCount * 500, 100); // 波奖励基准（= AS2 baseReward）
            var deposit = roundTo(waveBase, 1000);                              // 押注≈一场净收益
            out.push({
                id: 'esc-' + c.faction,
                faction: c.faction,
                displayName: c.displayName,
                isFallen: true,        // 复用堕落卡视觉 + 怪物预览
                isEscalation: true,    // 进场走爬升分叉
                name: c.name,
                opponentCount: c.opponentCount,
                levelMin: c.levelMin,
                levelMax: c.levelMax,
                benchLevel: c.benchLevel,
                maxWaves: maxWaves,
                deposit: deposit,
                reward: waveBase,      // = 波奖励基准
                expr: c.expr
            });
        }
        return out;
    }

    // 取某势力完整单位池（{type,minLevel,maxLevel,weight}）下发给 AS2 逐波采样。
    function factionPool(faction) {
        var factions = rostersAvailable() ? window.ArenaMetaRosters.factions : null;
        if (!factions || !factions[faction]) return [];
        var units = filterKnownUnits(factions[faction].units || []);
        var pool = [];
        for (var i = 0; i < units.length; i++) {
            var u = units[i];
            var entry = { type: u.type, minLevel: u.minLevel, maxLevel: u.maxLevel, weight: u.weight };
            var parameters = u.Parameters || u.parameters || u['参数'];
            if (customHasParameters(parameters)) entry.Parameters = cloneCustomParameters(parameters);
            pool.push(entry);
        }
        return pool;
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 生命周期
    // ════════════════════════════════════════════════════════════════════════════
    function onOpen(el, initData) {
        if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = (typeof PanelScale !== 'undefined') ? PanelScale.attach(_shellEl, 1024, 576) : null;
        _session++;
        _pendingReq = {};
        _busy = false;
        _snapshot = null;
        _activeCardIdx = -1;
        _previewOpponents = null;
        _ttCache = {};
        _ttHoverKey = null;
        // batch preview 缓存清空：每次 panel reopen = 新 session，旧 lineup 与当前 _root.可雇佣兵 pool 可能不一致
        _previewCache = {};
        _previewPending = {};
        _previewError = {};
        _cardKind = {};
        _monsterSquad = {};
        _knownEnemies = {};
        _knownEnemyCount = 0;
        _customResult = normalizeCustomResultInitData(initData);
        _customResultReturnBaseRequired = !!_customResult;
        _customMatch = null;
        _customEditor = null;
        _customSelectedSide = 'blue';
        _customEditorPage = 'config';
        _customConfirmOpen = false;
        _customUndo = null;
        if (_customResult && _customResult.matchCode) {
            _customMatch = {
                code: String(_customResult.matchCode),
                parsed: null,
                error: '',
                details: []
            };
            parseCustomMatchCode();
        }
        _customRun = _customResult ? buildCustomRunFromResult(_customResult) : null;
        clearCustomPoll();
        _customSampleIndex = 0;
        // initData.difficulty 来自 stage-select 重定向；dev 模式 ARENA_TEST 直开时为 ""
        _initDifficulty = (initData && initData.difficulty) ? String(initData.difficulty) : '';
        hideToast();
        updateMoneyDisplay(null);
        refreshModeTabs();
        // 普通打开复位到标准模式；定制赛结算回开则直达独立结算页。
        // 上次会话可能停在堕落模式；DOM 跨 open/close 复用，必须重建目标模式（否则残留旧卡）。
        rebuildForMode(_customResult ? 'custom' : 'standard');
        if (_customResult) showCustomResultView();
        requestSnapshot();
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
        if (_busy) return;
        Panels.close();
        var msg = { type: 'panel', panel: 'arena', cmd: 'close' };
        if (options && options.dismissReturnStack) msg.dismissReturnStack = true;
        if (options && options.returnBase) msg.returnBase = true;
        Bridge.send(msg);
    }

    function onArenaRequestClose() {
        if (_customResultViewEl && !_customResultViewEl.hidden) {
            requestCustomResultReturnBase();
            return;
        }
        if (_customResultReturnBaseRequired) {
            requestCustomResultReturnBase();
            return;
        }
        requestClose();
    }

    function requestCustomResultReturnBase() {
        requestClose({ dismissReturnStack: true, returnBase: true });
    }

    function onClose() {
        if (_scaleHandle) { _scaleHandle.detach(); _scaleHandle = null; }
        _pendingReq = {};
        _busy = false;
        _snapshot = null;
        _activeCardIdx = -1;
        _previewOpponents = null;
        _ttCache = {};
        _ttHoverKey = null;
        _previewCache = {};
        _previewPending = {};
        _previewError = {};
        _cardKind = {};
        _monsterSquad = {};
        _knownEnemies = {};
        _knownEnemyCount = 0;
        _customMatch = null;
        _customRun = null;
        _customResult = null;
        _customEditor = null;
        _customSelectedSide = 'blue';
        _customEditorPage = 'config';
        _customConfirmOpen = false;
        _customUndo = null;
        _customResultReturnBaseRequired = false;
        clearCustomPoll();
        _customSampleIndex = 0;
        _initDifficulty = '';
        PanelTooltip.hide();
        hideToast();
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 视图切换
    // ════════════════════════════════════════════════════════════════════════════
    function showGridView() {
        _gridViewEl.hidden = false;
        _detailViewEl.hidden = true;
        _customResultViewEl.hidden = true;
        _customEditorViewEl.hidden = true;
        PanelTooltip.hide();
    }

    function showDetailView() {
        _gridViewEl.hidden = true;
        _detailViewEl.hidden = false;
        _customResultViewEl.hidden = true;
        _customEditorViewEl.hidden = true;
    }

    function showCustomResultView() {
        renderCustomResultView();
        _gridViewEl.hidden = true;
        _detailViewEl.hidden = true;
        _customResultViewEl.hidden = false;
        _customEditorViewEl.hidden = true;
        PanelTooltip.hide();
    }

    function showCustomEditorView() {
        ensureCustomMatchState();
        parseCustomMatchCode();
        refreshCustomMatchCard();
        renderCustomEditor();
        renderCustomUnitBrowser();
        _gridViewEl.hidden = true;
        _detailViewEl.hidden = true;
        _customResultViewEl.hidden = true;
        _customEditorViewEl.hidden = false;
        PanelTooltip.hide();
    }

    function showCustomEditorForSide(side) {
        var editor = ensureCustomEditorState();
        if (editor.mode === 'pve') side = 'red';
        if (side === 'blue' || side === 'red') {
            _customSelectedSide = side;
            _customEditorPage = 'side';
        } else {
            _customEditorPage = 'config';
        }
        showCustomEditorView();
    }

    function backToGrid() {
        if (_busy) return;
        _activeCardIdx = -1;
        _previewOpponents = null;
        showGridView();
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 定制赛 P2：赛程代码导入 / 后台 single-case 运行 / 状态摘要
    // ════════════════════════════════════════════════════════════════════════════
    function ensureCustomMatchState() {
        if (_customMatch) return _customMatch;
        _customMatch = {
            code: getDefaultCustomMatchCode(),
            parsed: null,
            error: '',
            details: []
        };
        parseCustomMatchCode();
        return _customMatch;
    }

    function getCustomPresets() {
        if (typeof window !== 'undefined' && window.ArenaCustomPresets) {
            if (window.ArenaCustomPresets.length) return window.ArenaCustomPresets;
            if (window.ArenaCustomPresets.presets && window.ArenaCustomPresets.presets.length) {
                return window.ArenaCustomPresets.presets;
            }
        }
        return [
            { id: 'fallback-default', label: '默认样例', description: '', code: CUSTOM_MATCH_FALLBACK_CODE }
        ];
    }

    function getDefaultCustomMatchCode() {
        var presets = getCustomPresets();
        return (presets[0] && presets[0].code) || CUSTOM_MATCH_FALLBACK_CODE;
    }

    function buildCustomPresetOptions() {
        var presets = getCustomPresets();
        var html = '';
        for (var i = 0; i < presets.length; i++) {
            html += '<option value="' + escapeAttr(presets[i].id) + '">' + escapeHtml(presets[i].label) + '</option>';
        }
        return html;
    }

    function getCustomSavedRosters() {
        if (_customSavedRosters) return _customSavedRosters;
        _customSavedRosters = [];
        if (typeof window === 'undefined' || !window.localStorage) return _customSavedRosters;
        try {
            var raw = window.localStorage.getItem(CUSTOM_SAVED_ROSTERS_KEY);
            if (!raw) return _customSavedRosters;
            var parsed = JSON.parse(raw);
            var list = parsed && parsed.rosters ? parsed.rosters : (parsed && parsed.length ? parsed : []);
            for (var i = 0; i < list.length; i++) {
                if (!list[i] || !list[i].roster || !list[i].roster.length) continue;
                _customSavedRosters.push({
                    id: String(list[i].id || ('saved-' + i)),
                    label: String(list[i].label || ('已保存配置 ' + (i + 1))),
                    createdAt: String(list[i].createdAt || ''),
                    roster: cloneCustomRoster(list[i].roster)
                });
            }
        } catch (err) {
            _customSavedRosters = [];
        }
        return _customSavedRosters;
    }

    function saveCustomSavedRosters(list) {
        _customSavedRosters = list || [];
        if (typeof window === 'undefined' || !window.localStorage) {
            showToast('保存失败：浏览器本地存储不可用');
            return false;
        }
        try {
            window.localStorage.setItem(CUSTOM_SAVED_ROSTERS_KEY, JSON.stringify({
                schema: 'arena-custom-saved-rosters.v1',
                rosters: _customSavedRosters
            }));
            return true;
        } catch (err) {
            showToast('保存失败：浏览器本地存储不可用');
            return false;
        }
    }

    function buildCustomSavedRosterOptions() {
        var saved = getCustomSavedRosters();
        if (!saved.length) return '<option value="">暂无已保存配置</option>';
        var html = '';
        for (var i = 0; i < saved.length; i++) {
            html += '<option value="' + escapeAttr(saved[i].id) + '">' + escapeHtml(saved[i].label) + '</option>';
        }
        return html;
    }

    function findCustomSavedRosterById(id) {
        var saved = getCustomSavedRosters();
        for (var i = 0; i < saved.length; i++) {
            if (saved[i].id === id) return saved[i];
        }
        return saved[0] || null;
    }

    function collectCustomUnitCatalog() {
        var catalog = {};
        var unitCatalog = (typeof window !== 'undefined' && window.ArenaUnitCatalog)
            ? window.ArenaUnitCatalog.units : null;
        if (unitCatalog && unitCatalog.length) {
            for (var u = 0; u < unitCatalog.length; u++) {
                var unitId = Number(unitCatalog[u].id);
                if (!isNaN(unitId)) catalog[unitId] = unitCatalog[u];
            }
        }

        var rosters = (typeof window !== 'undefined' && window.ArenaMetaRosters)
            ? window.ArenaMetaRosters.factions : null;
        if (rosters) {
            for (var faction in rosters) {
                var units = (rosters[faction] && rosters[faction].units) || [];
                for (var i = 0; i < units.length; i++) {
                    var id = units[i].type ? Number(String(units[i].type).replace(/^兵种/, '')) : NaN;
                    if (!isNaN(id) && !catalog[id]) catalog[id] = units[i];
                }
            }
        }
        // P1 样例单位兜底：生产 lazy deps 会加载 ArenaMetaRosters；保留兜底只为独立调试页。
        catalog[11] = catalog[11] || { id: 11, name: '巨型僵尸', spritename: '敌人-boss大僵尸' };
        catalog[44] = catalog[44] || { id: 44, name: '左轮', spritename: '敌人-盗贼枪手' };
        catalog[45] = catalog[45] || { id: 45, name: '跳蚤', spritename: '敌人-盗贼侏儒' };
        catalog[48] = catalog[48] || { id: 48, name: '铁拳', spritename: '敌人-盗贼大叔' };
        catalog[164] = catalog[164] || { id: 164, name: '终结者T800', spritename: '敌人-终结者T800' };
        return catalog;
    }

    function getCustomUnitList() {
        var units = (typeof window !== 'undefined' && window.ArenaUnitCatalog && window.ArenaUnitCatalog.units)
            ? window.ArenaUnitCatalog.units : [];
        if (units.length) return units;
        var catalog = collectCustomUnitCatalog();
        var out = [];
        for (var id in catalog) {
            if (!Object.prototype.hasOwnProperty.call(catalog, id)) continue;
            var unit = catalog[id];
            out.push({
                id: Number(id),
                type: '兵种' + id,
                name: unit.name || ('兵种' + id),
                spritename: unit.spritename || '',
                level: unit.level || unit.minLevel || 1,
                height: unit.height || 0,
                slots: unit.slots || [],
                isHostile: unit.isHostile,
                faction: unit.faction || ''
            });
        }
        out.sort(function(a, b) { return a.id - b.id; });
        return out;
    }

    function getCustomUnitById(id) {
        id = Number(id);
        var catalog = collectCustomUnitCatalog();
        return catalog[id] || { id: id, type: '兵种' + id, name: '兵种' + id, spritename: '', level: 1, slots: [] };
    }

    function getCustomUnitParameterPresets(unitId) {
        var store = (typeof window !== 'undefined' && window.ArenaUnitParameterPresets)
            ? window.ArenaUnitParameterPresets : null;
        if (!store || !store.byUnit) return [];
        return store.byUnit[String(Number(unitId))] || [];
    }

    function findCustomUnitParameterPreset(presetId) {
        var store = (typeof window !== 'undefined' && window.ArenaUnitParameterPresets)
            ? window.ArenaUnitParameterPresets : null;
        if (!store || !store.byId || !presetId) return null;
        return store.byId[presetId] || null;
    }

    function buildCustomUnitChoices() {
        var units = getCustomUnitList();
        var out = [];
        for (var i = 0; i < units.length; i++) {
            out.push({ kind: 'base', unit: units[i], preset: null });
            var presets = getCustomUnitParameterPresets(units[i].id);
            for (var p = 0; p < presets.length; p++) {
                out.push({ kind: 'preset', unit: units[i], preset: presets[p] });
            }
        }
        return out;
    }

    function parseCustomMatchCode(options) {
        ensureCustomModule();
        if (!_customMatch) {
            _customMatch = { code: getDefaultCustomMatchCode(), parsed: null, error: '', details: [] };
        }
        options = options || {};
        try {
            _customMatch.parsed = ArenaCustomMatchCode.parseMatchCode(_customMatch.code, {
                unitCatalog: collectCustomUnitCatalog(),
                caseId: 'arena-custom-p3'
            });
            _customMatch.code = _customMatch.parsed.canonical;
            _customMatch.error = '';
            _customMatch.details = [];
            if (options.syncEditor !== false) syncCustomEditorFromParsed(_customMatch.parsed);
        } catch (err) {
            _customMatch.parsed = null;
            _customMatch.error = err && err.message ? err.message : String(err);
            _customMatch.details = err && err.details ? err.details : [];
        }
    }

    function ensureCustomModule() {
        if (typeof ArenaCustomMatchCode === 'undefined' || !ArenaCustomMatchCode.parseMatchCode) {
            throw new Error('ArenaCustomMatchCode 未加载');
        }
        if (typeof ArenaCustomParameters === 'undefined' || !ArenaCustomParameters.parseDraft) {
            throw new Error('ArenaCustomParameters 未加载');
        }
        if (typeof ArenaCustomUndo === 'undefined' || !ArenaCustomUndo.capture) {
            throw new Error('ArenaCustomUndo 未加载');
        }
        if (typeof ArenaCustomPolling === 'undefined' || !ArenaCustomPolling.schedule) {
            throw new Error('ArenaCustomPolling 未加载');
        }
        if (typeof ArenaCustomParamEditor === 'undefined' || !ArenaCustomParamEditor.createState) {
            throw new Error('ArenaCustomParamEditor 未加载');
        }
    }

    function syncCustomEditorFromParsed(parsed) {
        if (!parsed) return;
        var parsedMode = parsed.mode === 'pve' ? 'pve' : 'mvm';
        var previousEditor = _customEditor || {};
        _customEditor = {
            mode: parsedMode,
            seed: parsed.seed || 0,
            timeoutFrames: parsed.timeoutFrames || ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
            blue: parsedMode === 'pve' ? [] : cloneCustomRoster(parsed.blueRoster),
            red: parsedMode === 'pve' ? cloneCustomRoster(parsed.enemyRoster) : cloneCustomRoster(parsed.redRoster),
            query: previousEditor.query || '',
            filter: previousEditor.filter || 'all',
            expandedFactions: previousEditor.expandedFactions || {},
            unitVisibleRows: previousEditor.unitVisibleRows || CUSTOM_BROWSER_BATCH_SIZE,
            unitScrollableRows: previousEditor.unitScrollableRows || 0
        };
        if (parsedMode === 'pve') _customSelectedSide = 'red';
        _customConfirmOpen = false;
    }

    function ensureCustomEditorState() {
        ensureCustomMatchState();
        if (!_customEditor && _customMatch && _customMatch.parsed) syncCustomEditorFromParsed(_customMatch.parsed);
        if (!_customEditor) {
            _customEditor = {
                mode: 'mvm',
                seed: 0,
                timeoutFrames: ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
                blue: [],
                red: [],
                query: '',
                filter: 'all',
                expandedFactions: {},
                unitVisibleRows: CUSTOM_BROWSER_BATCH_SIZE,
                unitScrollableRows: 0
            };
        }
        return _customEditor;
    }

    function customUndoOptions() {
        return {
            defaultTimeoutFrames: ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
            browserBatchSize: CUSTOM_BROWSER_BATCH_SIZE
        };
    }

    function captureCustomUndo(label) {
        if (!_customEditor) ensureCustomEditorState();
        _customUndo = ArenaCustomUndo.capture(_customEditor, {
            label: label || '上一步',
            selectedSide: _customSelectedSide,
            editorPage: _customEditorPage
        }, customUndoOptions());
    }

    function restoreCustomUndo() {
        if (!_customUndo) {
            showToast('暂无可撤销操作');
            return;
        }
        var restored = ArenaCustomUndo.restore(_customUndo, customUndoOptions());
        _customUndo = null;
        _customEditor = restored.editor;
        _customSelectedSide = restored.selectedSide;
        _customEditorPage = restored.editorPage;
        _customParamEditor = null;
        syncCustomCodeFromEditor();
        renderCustomEditor();
        renderCustomUnitBrowser();
        showToast('已撤销：' + restored.label);
    }

    function renderCustomUndoState() {
        var btn = _el ? _el.querySelector('#arena-custom-undo') : null;
        ArenaCustomUndo.renderButton(btn, _customUndo, {
            disabled: _busy || customRunActive(),
            truncateText: truncateCustomText
        });
    }

    function cloneCustomRoster(roster) {
        var out = [];
        roster = roster || [];
        for (var i = 0; i < roster.length; i++) {
            var id = roster[i].id != null ? roster[i].id : ArenaCustomMatchCode.normalizeUnitId(roster[i].type);
            var entry = {
                id: Number(id),
                type: '兵种' + Number(id),
                level: Number(roster[i].level) || 1,
                count: Number(roster[i].count) || 1
            };
            var parameters = roster[i].parameters || roster[i].Parameters || roster[i]['参数'];
            if (customHasParameters(parameters)) entry.parameters = cloneCustomParameters(parameters);
            if (roster[i].presetId) entry.presetId = roster[i].presetId;
            if (roster[i].presetLabel) entry.presetLabel = roster[i].presetLabel;
            out.push(entry);
        }
        return out;
    }

    function cloneCustomParameters(value) {
        return ArenaCustomParameters.clone(value);
    }

    function customHasParameters(value) {
        return ArenaCustomParameters.has(value);
    }

    function customParameterText(value) {
        return ArenaCustomParameters.text(value);
    }

    function customParametersEqual(a, b) {
        return ArenaCustomParameters.equal(a, b);
    }

    function syncCustomCodeFromEditor(options) {
        options = options || {};
        ensureCustomModule();
        var editor = ensureCustomEditorState();
        if (editor.mode === 'pve') {
            _customSelectedSide = 'red';
            _customMatch.code = ArenaCustomMatchCode.serializeMatchCode({
                mode: 'pve',
                seed: editor.seed || 0,
                timeoutFrames: editor.timeoutFrames || ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
                enemyRoster: editor.red,
                player: 'current'
            });
        } else {
            _customMatch.code = ArenaCustomMatchCode.serializeMatchCode({
                mode: 'mvm',
                seed: editor.seed || 0,
                timeoutFrames: editor.timeoutFrames || ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
                blueRoster: editor.blue,
                redRoster: editor.red
            });
        }
        parseCustomMatchCode({ syncEditor: false });
        _customConfirmOpen = false;
        if (options.refresh !== false) refreshCustomMatchCard();
    }

    function refreshCustomMatchCard() {
        if (_activeMode !== 'custom') return;
        ensureCustomMatchState();
        ensureCustomEditorState();
        var input = _el ? _el.querySelector('#arena-custom-code-input') : null;
        if (input && document.activeElement !== input) input.value = _customMatch.code;

        var summaryEl = _el ? _el.querySelector('#arena-custom-summary') : null;
        var caseEl = _el ? _el.querySelector('#arena-custom-case') : null;
        var statusEl = _el ? _el.querySelector('#arena-custom-status') : null;
        var feeEl = _el ? _el.querySelector('#arena-custom-fee') : null;
        var btn = _el ? _el.querySelector('.arena-custom-generate') : null;
        var abortBtn = _el ? _el.querySelector('.arena-custom-abort') : null;
        var subtitleEl = _el ? _el.querySelector('.arena-custom-subtitle') : null;
        renderCustomEditor();
        renderCustomUnitBrowser();
        renderCustomConfirm();
        renderCustomCodeStatus();
        if (!summaryEl || !caseEl || !statusEl || !feeEl || !btn || !abortBtn) return;

        if (!_customMatch.parsed) {
            summaryEl.innerHTML = buildCustomErrorHtml(_customMatch);
            caseEl.textContent = '等待有效赛程代码';
            statusEl.innerHTML = buildCustomRunStatusHtml(false);
            feeEl.textContent = '--';
            btn.disabled = true;
            abortBtn.disabled = true;
            return;
        }

        var parsed = _customMatch.parsed;
        if (parsed.mode === 'pve') {
            var enemyCount = customRosterTotal(parsed.enemyRoster);
            if (subtitleEl) subtitleEl.textContent = '玩家 vs 怪物 · 标准竞技场 · 无掉落无经验';
            summaryEl.innerHTML =
                '<div class="arena-custom-side arena-custom-side-blue arena-custom-side-player">' +
                    '<div class="arena-custom-side-head">' +
                        '<span class="arena-custom-side-title">玩家</span>' +
                        '<span class="arena-custom-side-count">当前存档</span>' +
                    '</div>' +
                    '<span class="arena-custom-side-roster">使用当前角色、装备、技能和操作</span>' +
                '</div>' +
                '<div class="arena-custom-vs-mark">VS</div>' +
                '<div class="arena-custom-side arena-custom-side-red">' +
                    '<div class="arena-custom-side-head">' +
                        '<span class="arena-custom-side-title">怪物</span>' +
                        '<span class="arena-custom-side-count">' + enemyCount + ' 单位</span>' +
                    '</div>' +
                    '<span class="arena-custom-side-roster">' + escapeHtml(summarizeCustomRoster(parsed.enemyRoster)) + '</span>' +
                    '<button class="arena-custom-side-edit" type="button" data-custom-action="edit" data-custom-edit-side="red" data-audio-cue="confirm">调整怪物</button>' +
                '</div>';
            caseEl.textContent =
                'seed=' + parsed.seed +
                ' · player=current' +
                ' · 无掉落 / 无经验 / 标准竞技场';
        } else {
            var blueCount = customRosterTotal(parsed.blueRoster);
            var redCount = customRosterTotal(parsed.redRoster);
            if (subtitleEl) subtitleEl.textContent = '怪物 vs 怪物 · 后台单局 · 无掉落无经验';
            summaryEl.innerHTML =
                '<div class="arena-custom-side arena-custom-side-blue">' +
                    '<div class="arena-custom-side-head">' +
                        '<span class="arena-custom-side-title">蓝方</span>' +
                        '<span class="arena-custom-side-count">' + blueCount + ' 单位</span>' +
                    '</div>' +
                    '<span class="arena-custom-side-roster">' + escapeHtml(summarizeCustomRoster(parsed.blueRoster)) + '</span>' +
                    '<button class="arena-custom-side-edit" type="button" data-custom-action="edit" data-custom-edit-side="blue" data-audio-cue="confirm">调整蓝方</button>' +
                '</div>' +
                '<div class="arena-custom-vs-mark">VS</div>' +
                '<div class="arena-custom-side arena-custom-side-red">' +
                    '<div class="arena-custom-side-head">' +
                        '<span class="arena-custom-side-title">红方</span>' +
                        '<span class="arena-custom-side-count">' + redCount + ' 单位</span>' +
                    '</div>' +
                    '<span class="arena-custom-side-roster">' + escapeHtml(summarizeCustomRoster(parsed.redRoster)) + '</span>' +
                    '<button class="arena-custom-side-edit" type="button" data-custom-action="edit" data-custom-edit-side="red" data-audio-cue="confirm">调整红方</button>' +
                '</div>';
            caseEl.textContent =
                'seed=' + parsed.seed +
                ' · 上限 ' + parsed.calibrationCase.timeoutFrames + ' 帧' +
                ' · 无掉落 / 无经验 / 原死亡流程';
        }
        statusEl.innerHTML = buildCustomRunStatusHtml(parsed.mode === 'pve');
        feeEl.textContent = formatMoney(parsed.venueFeeEstimate);
        btn.textContent = _customConfirmOpen ? '确认页已打开' : '检查并确认';
        btn.disabled = _busy || (parsed.mode !== 'pve' && customRunActive());
        abortBtn.disabled = _busy || parsed.mode === 'pve' || !customRunActive();
    }

    function renderCustomEditor() {
        if (!_el) return;
        var editor = ensureCustomEditorState();
        if (editor.mode === 'pve') _customSelectedSide = 'red';
        var configPage = _el.querySelector('[data-custom-editor-page="config"]');
        var sidePage = _el.querySelector('[data-custom-editor-page="side"]');
        var paramPage = _el.querySelector('[data-custom-editor-page="params"]');
        if (configPage) configPage.hidden = _customEditorPage !== 'config';
        if (sidePage) sidePage.hidden = _customEditorPage !== 'side';
        if (paramPage) paramPage.hidden = _customEditorPage !== 'params';

        var modeBtns = _el.querySelectorAll('[data-custom-mode]');
        for (var mb = 0; mb < modeBtns.length; mb++) {
            var mode = modeBtns[mb].getAttribute('data-custom-mode');
            modeBtns[mb].classList.toggle('arena-custom-mode-active', mode === editor.mode);
        }
        renderCustomUndoState();

        var sideConfigs = _el.querySelector('.arena-custom-side-configs');
        if (sideConfigs) sideConfigs.classList.toggle('arena-custom-side-configs-pve', editor.mode === 'pve');
        var swapActions = _el.querySelector('#arena-custom-swap-actions');
        if (swapActions) swapActions.classList.toggle('arena-custom-pve-actions', editor.mode === 'pve');
        var swapBtn = _el.querySelector('[data-custom-action="swap-sides"]');
        if (swapBtn) swapBtn.hidden = editor.mode === 'pve';
        var presetLabel = _el.querySelector('label[for="arena-custom-preset-select"]');
        if (presetLabel) presetLabel.textContent = editor.mode === 'pve' ? '待标定怪物组合' : '整局待标定组合';

        var blueConfigEl = _el.querySelector('#arena-custom-config-blue');
        var redConfigEl = _el.querySelector('#arena-custom-config-red');
        if (blueConfigEl) {
            blueConfigEl.hidden = false;
            blueConfigEl.classList.toggle('arena-custom-side-config-player', editor.mode === 'pve');
            blueConfigEl.innerHTML = editor.mode === 'pve'
                ? buildCustomPlayerConfigCardHtml()
                : buildCustomSideConfigCardHtml('blue', editor.blue);
        }
        if (redConfigEl) redConfigEl.innerHTML = buildCustomSideConfigCardHtml('red', editor.red);

        var activeRoster = getCustomSideRoster(_customSelectedSide);
        var activeRosterEl = _el.querySelector('#arena-custom-active-roster');
        if (activeRosterEl) activeRosterEl.innerHTML = buildCustomRosterEditorHtml(_customSelectedSide, activeRoster);

        var activePanel = _el.querySelector('#arena-custom-active-roster-panel');
        if (activePanel) {
            activePanel.setAttribute('data-side', _customSelectedSide);
            activePanel.classList.toggle('arena-custom-roster-blue', _customSelectedSide === 'blue');
            activePanel.classList.toggle('arena-custom-roster-red', _customSelectedSide === 'red');
        }
        var titleEl = _el.querySelector('#arena-custom-side-editor-title');
        var kickerEl = _el.querySelector('#arena-custom-side-editor-kicker');
        var metaEl = _el.querySelector('#arena-custom-side-editor-meta');
        var countEl = _el.querySelector('#arena-custom-active-roster-count');
        var sideLabel = customSideLabel(_customSelectedSide);
        if (kickerEl) kickerEl.textContent = sideLabel + '阵容';
        if (titleEl) titleEl.textContent = '编辑' + sideLabel;
        if (metaEl) metaEl.textContent = customRosterTotal(activeRoster) + ' 单位 · ' + (activeRoster.length ? summarizeCustomRoster(activeRoster) : '空阵容');
        if (countEl) countEl.textContent = customRosterTotal(activeRoster) + ' 单位';

        var savedOptions = buildCustomSavedRosterOptions();
        var savedSelects = _el.querySelectorAll('[data-custom-saved-select]');
        for (var ss = 0; ss < savedSelects.length; ss++) {
            savedSelects[ss].innerHTML = savedOptions;
        }

        var panels = _el.querySelectorAll('.arena-custom-roster-panel');
        for (var i = 0; i < panels.length; i++) {
            panels[i].classList.toggle('arena-custom-roster-active', panels[i].getAttribute('data-side') === _customSelectedSide);
        }
        var sideBtns = _el.querySelectorAll('[data-custom-side]');
        for (var s = 0; s < sideBtns.length; s++) {
            var side = sideBtns[s].getAttribute('data-custom-side');
            if (editor.mode === 'pve' && side === 'blue') {
                sideBtns[s].hidden = true;
                continue;
            }
            sideBtns[s].hidden = false;
            if (editor.mode === 'pve' && side === 'red') sideBtns[s].textContent = '加到怪物';
            else sideBtns[s].textContent = side === 'red' ? '加到红方' : '加到蓝方';
            sideBtns[s].classList.toggle('arena-custom-side-target-active', side === _customSelectedSide);
        }
        renderCustomParamEditor();
    }

    function buildCustomSideConfigCardHtml(side, roster) {
        var sideLabel = customSideLabel(side);
        var total = customRosterTotal(roster);
        var empty = !roster || !roster.length;
        var rosterText = empty ? '尚未配置单位' : summarizeCustomRoster(roster);
        return '<div class="arena-custom-side-config-head">' +
                '<div>' +
                    '<div class="arena-custom-side-title">' + sideLabel + '</div>' +
                    '<div class="arena-custom-side-count">' + total + ' 单位</div>' +
                '</div>' +
                '<button class="arena-custom-btn" type="button" data-custom-side-action="edit" data-side="' + side + '" data-audio-cue="confirm">编辑阵容</button>' +
            '</div>' +
            '<div class="arena-custom-side-config-roster">' + escapeHtml(rosterText) + '</div>' +
            '<div class="arena-custom-side-config-load">' +
                '<select class="arena-custom-preset-select" data-custom-saved-select="' + side + '" aria-label="' + sideLabel + '已保存配置">' + buildCustomSavedRosterOptions() + '</select>' +
                '<button class="arena-custom-btn" type="button" data-custom-side-action="load" data-side="' + side + '" data-audio-cue="confirm">读取</button>' +
            '</div>' +
            '<div class="arena-custom-side-config-actions">' +
                '<button class="arena-custom-btn" type="button" data-custom-side-action="random" data-side="' + side + '" data-audio-cue="confirm">随机组合</button>' +
                '<button class="arena-custom-btn" type="button" data-custom-side-action="save" data-side="' + side + '" data-audio-cue="confirm">保存配置</button>' +
                '<button class="arena-custom-btn" type="button" data-custom-side-action="clear" data-side="' + side + '" data-audio-cue="cancel">清空</button>' +
            '</div>';
    }

    function buildCustomPlayerConfigCardHtml() {
        return '<div class="arena-custom-side-config-head">' +
                '<div>' +
                    '<div class="arena-custom-side-title">玩家</div>' +
                    '<div class="arena-custom-side-count">当前存档</div>' +
                '</div>' +
            '</div>' +
            '<div class="arena-custom-side-config-roster arena-custom-player-config-roster">' +
                '使用当前角色、装备、技能和操作' +
            '</div>';
    }

    function customSideLabel(side) {
        var editor = _customEditor || null;
        if (editor && editor.mode === 'pve') return side === 'red' ? '怪物' : '玩家';
        return side === 'red' ? '红方' : '蓝方';
    }

    function resolveCustomSide(side) {
        var editor = _customEditor || null;
        if (editor && editor.mode === 'pve') return 'red';
        if (side === 'active') return _customSelectedSide;
        return side === 'red' ? 'red' : 'blue';
    }

    function getCustomSideRoster(side) {
        var editor = ensureCustomEditorState();
        return resolveCustomSide(side) === 'red' ? editor.red : editor.blue;
    }

    function setCustomSideRoster(side, roster) {
        var editor = ensureCustomEditorState();
        if (resolveCustomSide(side) === 'red') editor.red = cloneCustomRoster(roster || []);
        else editor.blue = cloneCustomRoster(roster || []);
        syncCustomCodeFromEditor();
    }

    function showCustomEditorConfigPage() {
        _customEditorPage = 'config';
        _customParamEditor = null;
        renderCustomEditor();
        renderCustomUnitBrowser();
    }

    function showCustomSideEditorPage(side) {
        _customSelectedSide = resolveCustomSide(side);
        _customEditorPage = 'side';
        _customParamEditor = null;
        renderCustomEditor();
        renderCustomUnitBrowser();
    }

    function showCustomParamEditorPage(side, index) {
        side = resolveCustomSide(side);
        var entry = getCustomRosterEntry(side, index);
        if (!entry) return;
        _customSelectedSide = side;
        _customParamEditor = buildCustomParamEditorState(side, index, 'json', entry);
        _customEditorPage = 'params';
        renderCustomEditor();
    }

    function buildCustomParamEditorState(side, index, mode, entry) {
        return ArenaCustomParamEditor.createState(side, index, mode, entry);
    }

    function getCustomRosterEntry(side, index) {
        var editor = ensureCustomEditorState();
        var roster = resolveCustomSide(side) === 'red' ? editor.red : editor.blue;
        index = Number(index);
        if (index < 0 || index >= roster.length) return null;
        return roster[index];
    }

    function renderCustomParamEditor() {
        if (!_el) return;
        var bodyEl = _el.querySelector('#arena-custom-param-editor-body');
        if (!bodyEl) return;
        if (_customEditorPage !== 'params') return;

        var state = _customParamEditor;
        var entry = state ? getCustomRosterEntry(state.side, state.index) : null;
        ArenaCustomParamEditor.render({
            rootEl: _el,
            bodyEl: bodyEl,
            state: state,
            entry: entry,
            unit: entry ? getCustomUnitById(entry.id) : null,
            sideLabel: state ? customSideLabel(state.side) : '',
            summary: entry ? (summarizeCustomParameters(entry.parameters) || '默认参数') : '',
            titleEl: _el.querySelector('#arena-custom-param-editor-title'),
            kickerEl: _el.querySelector('#arena-custom-param-editor-kicker'),
            metaEl: _el.querySelector('#arena-custom-param-editor-meta'),
            escapeHtml: escapeHtml
        });
    }

    function customParamEditorDirty() {
        var entry = _customParamEditor ? getCustomRosterEntry(_customParamEditor.side, _customParamEditor.index) : null;
        return ArenaCustomParamEditor.dirty(_customParamEditor, entry);
    }

    function leaveCustomParamEditorDiscardingDraft() {
        var side = _customParamEditor ? _customParamEditor.side : _customSelectedSide;
        if (customParamEditorDirty()) showToast('已放弃未应用参数草稿');
        showCustomSideEditorPage(side);
    }

    function updateCustomParamDraft(text) {
        if (!_customParamEditor) return;
        ArenaCustomParamEditor.updateDraft(_customParamEditor, text);
        updateCustomParamInlineState();
    }

    function updateCustomParamInlineState() {
        if (!_el || _customEditorPage !== 'params') return;
        var entry = _customParamEditor ? getCustomRosterEntry(_customParamEditor.side, _customParamEditor.index) : null;
        ArenaCustomParamEditor.updateInline(_el, _customParamEditor, entry);
    }

    function setCustomParamEditorMode(mode) {
        if (!_customParamEditor) return;
        if (!ArenaCustomParamEditor.setMode(_customParamEditor, mode)) {
            renderCustomEditor();
            return;
        }
        renderCustomEditor();
    }

    function applyCustomParamDraft(returnToSide) {
        if (!_customParamEditor) return false;
        var mode = _customParamEditor.mode === 'xml' ? 'xml' : 'json';
        var parsed = ArenaCustomParamEditor.parseCurrent(_customParamEditor);
        if (!parsed.ok) {
            _customParamEditor.error = parsed.error;
            renderCustomEditor();
            return false;
        }
        var side = _customParamEditor.side;
        var index = _customParamEditor.index;
        if (!setCustomRosterParametersValue(side, index, parsed.value)) return false;
        var entry = getCustomRosterEntry(side, index);
        if (entry) {
            _customParamEditor = buildCustomParamEditorState(side, index, mode, entry);
        }
        showToast(customSideLabel(side) + '单位参数已应用');
        if (returnToSide) showCustomSideEditorPage(side);
        else renderCustomEditor();
        return true;
    }

    function clearCustomParamDraft() {
        if (!_customParamEditor) return;
        ArenaCustomParamEditor.clearDraft(_customParamEditor);
        renderCustomEditor();
    }

    function buildCustomRosterEditorHtml(side, roster) {
        if (!roster || !roster.length) {
            return '<div class="arena-custom-roster-empty">从右侧单位目录添加到' + customSideLabel(side) + '</div>';
        }
        var html = '';
        for (var i = 0; i < roster.length; i++) {
            var entry = roster[i];
            var unit = getCustomUnitById(entry.id);
            var paramSummary = entry.presetLabel || summarizeCustomParameters(entry.parameters);
            var paramLabel = paramSummary ? truncateCustomText(paramSummary, 22) : '默认参数';
            var paramClass = customHasParameters(entry.parameters) ? ' arena-custom-param-pill-active' : '';
            html += '<div class="arena-custom-roster-row">' +
                '<div class="arena-custom-unit-mark">u' + entry.id + '</div>' +
                '<div class="arena-custom-roster-info">' +
                    '<b>' + escapeHtml(unit.name || ('兵种' + entry.id)) + '</b>' +
                    '<span>兵种' + entry.id + ' · ' + escapeHtml(unit.spritename || '--') + (paramSummary ? ' · ' + escapeHtml(paramSummary) : '') + '</span>' +
                '</div>' +
                '<label>Lv.<input class="arena-custom-mini-input" type="number" min="1" max="999" value="' + entry.level + '" data-custom-roster-input="level" data-side="' + side + '" data-index="' + i + '"></label>' +
                '<div class="arena-custom-count-stepper">' +
                    '<button type="button" data-custom-adjust-count="-1" data-side="' + side + '" data-index="' + i + '" data-audio-cue="cancel">−</button>' +
                    '<input class="arena-custom-mini-input" type="number" min="1" max="20" value="' + entry.count + '" data-custom-roster-input="count" data-side="' + side + '" data-index="' + i + '">' +
                    '<button type="button" data-custom-adjust-count="1" data-side="' + side + '" data-index="' + i + '" data-audio-cue="confirm">+</button>' +
                '</div>' +
                '<button class="arena-custom-param-pill' + paramClass + '" type="button" data-custom-edit-params data-side="' + side + '" data-index="' + i + '" title="' + escapeAttr(paramSummary || '编辑单位参数') + '" data-audio-cue="confirm">' +
                    '<span>' + escapeHtml(paramLabel) + '</span>' +
                    '<b>参数</b>' +
                '</button>' +
                '<button class="arena-custom-icon-btn" type="button" title="移除" data-custom-remove data-side="' + side + '" data-index="' + i + '" data-audio-cue="cancel">×</button>' +
            '</div>';
        }
        return html;
    }

    function renderCustomUnitBrowser(options) {
        options = options || {};
        var listEl = _el ? _el.querySelector('#arena-custom-unit-list') : null;
        var countEl = _el ? _el.querySelector('#arena-custom-unit-count') : null;
        var searchEl = _el ? _el.querySelector('#arena-custom-unit-search') : null;
        if (!listEl || !countEl || !searchEl) return;
        var previousScrollTop = options.preserveScroll ? listEl.scrollTop : 0;
        var editor = ensureCustomEditorState();
        editor.expandedFactions = editor.expandedFactions || {};
        editor.unitVisibleRows = editor.unitVisibleRows || CUSTOM_BROWSER_BATCH_SIZE;
        if (document.activeElement !== searchEl) searchEl.value = editor.query || '';

        var query = normalizeSearchText(editor.query || '');
        var filter = editor.filter || 'all';
        var choices = buildCustomUnitChoices();
        var factionLookup = buildCustomFactionLookup();
        var groups = [];
        var groupMap = {};
        var matchCount = 0;
        for (var i = 0; i < choices.length; i++) {
            var choice = choices[i];
            var unit = choice.unit;
            if (filter === 'hostile' && unit.isHostile === false) continue;
            if (filter === 'nonhostile' && unit.isHostile !== false) continue;
            var faction = customUnitFaction(unit, factionLookup);
            if (query && normalizeSearchText(customUnitChoiceSearchText(choice, faction)).indexOf(query) < 0) continue;
            var key = faction || '未归类';
            if (!groupMap[key]) {
                groupMap[key] = { key: key, label: customFactionLabel(key), units: [] };
                groups.push(groupMap[key]);
            }
            groupMap[key].units.push({ choice: choice, faction: key });
            matchCount++;
        }
        groups.sort(sortCustomUnitGroups);

        countEl.textContent = matchCount + '/' + choices.length + ' 条目';
        var filterBtns = _el.querySelectorAll('[data-custom-unit-filter]');
        for (var f = 0; f < filterBtns.length; f++) {
            filterBtns[f].classList.toggle('arena-custom-unit-filter-active', filterBtns[f].getAttribute('data-custom-unit-filter') === filter);
        }
        if (!matchCount) {
            listEl.innerHTML = '<div class="arena-custom-unit-empty">没有匹配单位</div>';
            editor.unitScrollableRows = 0;
            return;
        }
        var html = '';
        var renderedRows = 0;
        var expandedRows = 0;
        var hiddenRows = 0;
        var forceExpanded = !!query;
        for (var g = 0; g < groups.length; g++) {
            var group = groups[g];
            var expanded = forceExpanded || editor.expandedFactions[group.key] === true;
            html += buildCustomUnitGroupHtml(group, expanded, forceExpanded);
            if (!expanded) continue;
            expandedRows += group.units.length;
            for (var m = 0; m < group.units.length; m++) {
                if (renderedRows >= editor.unitVisibleRows) {
                    hiddenRows += group.units.length - m;
                    break;
                }
                html += buildCustomUnitRowHtml(group.units[m].choice, group.units[m].faction);
                renderedRows++;
            }
        }
        if (hiddenRows > 0) {
            html += '<div class="arena-custom-unit-more">继续滚动加载剩余 ' + hiddenRows + ' 个单位</div>';
        }
        listEl.innerHTML = html;
        editor.unitScrollableRows = expandedRows;
        if (options.preserveScroll) listEl.scrollTop = previousScrollTop;
        else listEl.scrollTop = 0;
    }

    function buildCustomFactionLookup() {
        var lookup = {};
        var rosters = (typeof window !== 'undefined' && window.ArenaMetaRosters)
            ? window.ArenaMetaRosters.factions : null;
        if (!rosters) return lookup;
        for (var faction in rosters) {
            if (!Object.prototype.hasOwnProperty.call(rosters, faction)) continue;
            var units = (rosters[faction] && rosters[faction].units) || [];
            for (var i = 0; i < units.length; i++) {
                if (units[i].type) lookup[units[i].type] = faction;
            }
        }
        return lookup;
    }

    function customUnitFaction(unit, lookup) {
        if (unit && unit.faction) return unit.faction;
        var type = unit && unit.type ? unit.type : ('兵种' + (unit ? unit.id : ''));
        return (lookup && lookup[type]) || '未归类';
    }

    function customFactionLabel(faction) {
        if (!faction || faction === 'unknown' || faction === '未归类') return '未归类';
        return faction;
    }

    function sortCustomUnitGroups(a, b) {
        if (a.key === '未归类' && b.key !== '未归类') return 1;
        if (b.key === '未归类' && a.key !== '未归类') return -1;
        if (a.label === b.label) return 0;
        return a.label > b.label ? 1 : -1;
    }

    function buildCustomUnitGroupHtml(group, expanded, queryActive) {
        var cls = 'arena-custom-unit-group' +
            (expanded ? ' arena-custom-unit-group-expanded' : '') +
            (queryActive ? ' arena-custom-unit-group-search' : '');
        return '<button class="' + cls + '" type="button" data-custom-toggle-faction="' + escapeAttr(group.key) + '" data-custom-faction-count="' + group.units.length + '" data-audio-cue="confirm">' +
            '<span class="arena-custom-unit-group-arrow">' + (expanded ? '▾' : '▸') + '</span>' +
            '<span class="arena-custom-unit-group-name">' + escapeHtml(group.label) + '</span>' +
            '<span class="arena-custom-unit-group-count">' + group.units.length + '</span>' +
        '</button>';
    }

    function buildCustomUnitRowHtml(choice, faction) {
        var unit = choice.unit;
        var preset = choice.preset;
        var slots = summarizeCustomSlots(unit);
        var hostileLabel = unit.isHostile === false ? ' · 非敌对' : '';
        var factionLabel = faction && faction !== '未归类' ? ' · ' + faction : '';
        var presetLabel = preset ? (' · 预设 · ' + (preset.summary || summarizeCustomParameters(preset.parameters))) : '';
        var presetAttr = preset ? ' data-custom-preset-id="' + escapeAttr(preset.id) + '"' : '';
        var rowClass = 'arena-custom-unit-row' +
            (preset ? ' arena-custom-unit-row-preset' : '') +
            (unit.isHostile === false ? ' arena-custom-unit-row-nonhostile' : '');
        return '<button class="' + rowClass + '" type="button" data-custom-add-unit="' + unit.id + '"' + presetAttr + ' data-custom-faction="' + escapeAttr(faction || '') + '" data-audio-cue="confirm">' +
            '<span class="arena-custom-unit-mark">u' + unit.id + '</span>' +
            '<span class="arena-custom-unit-main">' +
                '<b>' + escapeHtml(unit.name || ('兵种' + unit.id)) + '</b>' +
                '<em>' + escapeHtml(unit.spritename || '--') + '</em>' +
            '</span>' +
            '<span class="arena-custom-unit-meta">Lv.' + (preset && preset.defaultLevel ? preset.defaultLevel : (unit.level || 1)) + factionLabel + hostileLabel + presetLabel + (slots ? ' · ' + escapeHtml(slots) : '') + '</span>' +
        '</button>';
    }

    function summarizeCustomSlots(unit) {
        var slots = unit && unit.slots ? unit.slots : [];
        if (!slots.length) return '';
        var parts = [];
        for (var i = 0; i < slots.length && i < 2; i++) {
            parts.push(slots[i].value);
        }
        return parts.join(' / ');
    }

    function customUnitSearchText(unit, faction) {
        return [
            unit.id,
            unit.type,
            unit.name,
            unit.spritename,
            faction || unit.faction || '',
            summarizeCustomSlots(unit)
        ].join(' ');
    }

    function customUnitChoiceSearchText(choice, faction) {
        var preset = choice && choice.preset;
        return [
            customUnitSearchText(choice.unit, faction),
            preset ? preset.id : '',
            preset ? preset.label : '',
            preset ? preset.summary : '',
            preset && preset.parameterKeys ? preset.parameterKeys.join(' ') : '',
            preset && preset.sourceStages ? preset.sourceStages.join(' ') : '',
            preset ? customParameterText(preset.parameters) : ''
        ].join(' ');
    }

    function normalizeSearchText(text) {
        return String(text || '').toLowerCase().replace(/\s+/g, '');
    }

    function renderCustomConfirm() {
        var confirmEl = _el ? _el.querySelector('#arena-custom-confirm') : null;
        if (!confirmEl) return;
        var cardEl = _el ? _el.querySelector('.arena-card-custom') : null;
        if (!_customConfirmOpen || !_customMatch || !_customMatch.parsed) {
            confirmEl.hidden = true;
            confirmEl.innerHTML = '';
            if (cardEl) cardEl.classList.remove('arena-card-custom-confirming');
            return;
        }
        var parsed = _customMatch.parsed;
        confirmEl.hidden = false;
        if (cardEl) cardEl.classList.add('arena-card-custom-confirming');
        if (parsed.mode === 'pve') {
            confirmEl.innerHTML =
                '<div class="arena-custom-confirm-head">' +
                    '<div>' +
                        '<div class="arena-custom-confirm-title">确认挑战</div>' +
                        '<div class="arena-custom-confirm-subtitle">启动后关闭 Web 面板，使用当前玩家进入标准竞技场</div>' +
                    '</div>' +
                    '<div class="arena-custom-confirm-fee">' + formatMoney(0) + '</div>' +
                '</div>' +
                '<div class="arena-custom-confirm-grid">' +
                    '<span>玩家</span><b>当前存档 / 当前装备 / 当前操作</b>' +
                    '<span>怪物</span><b>' + escapeHtml(summarizeCustomRoster(parsed.enemyRoster)) + '</b>' +
                    '<span>规则</span><b>无押金 / 无奖金 / 无掉落 / 无经验</b>' +
                    '<span>复现</span><b>仅复现怪物配置，不复现玩家状态</b>' +
                '</div>' +
                '<div class="arena-custom-confirm-actions">' +
                    '<button class="arena-custom-btn" type="button" data-custom-confirm-action="cancel" data-audio-cue="cancel">返回编辑</button>' +
                    '<button class="arena-card-btn-enter" type="button" data-custom-confirm-action="start" data-audio-cue="confirm">开始挑战</button>' +
                '</div>';
            return;
        }
        confirmEl.innerHTML =
            '<div class="arena-custom-confirm-head">' +
                '<div>' +
                    '<div class="arena-custom-confirm-title">确认委托</div>' +
                    '<div class="arena-custom-confirm-subtitle">启动后将关闭 Web 面板，战斗结束再回开结算页</div>' +
                '</div>' +
                '<div class="arena-custom-confirm-fee">' + formatMoney(parsed.venueFeeEstimate) + '</div>' +
            '</div>' +
            '<div class="arena-custom-confirm-grid">' +
                '<span>蓝方</span><b>' + escapeHtml(summarizeCustomRoster(parsed.blueRoster)) + '</b>' +
                '<span>红方</span><b>' + escapeHtml(summarizeCustomRoster(parsed.redRoster)) + '</b>' +
                '<span>战斗上限</span><b>' + parsed.calibrationCase.timeoutFrames + ' 帧</b>' +
                '<span>规则</span><b>无掉落 / 无经验 / 原死亡流程</b>' +
            '</div>' +
            '<div class="arena-custom-confirm-actions">' +
                '<button class="arena-custom-btn" type="button" data-custom-confirm-action="cancel" data-audio-cue="cancel">返回编辑</button>' +
                '<button class="arena-card-btn-enter" type="button" data-custom-confirm-action="start" data-audio-cue="confirm">确认委托</button>' +
            '</div>';
    }

    function buildCustomErrorHtml(state) {
        var text = state.error || '解析失败';
        if (state.details && state.details.length) {
            text += ': ' + state.details.map(function(d) {
                return (d.field ? d.field + ' ' : '') + d.message;
            }).join('; ');
        }
        return '<div class="arena-opponents-error">' + escapeHtml(text) + '</div>';
    }

    function summarizeCustomRoster(roster) {
        roster = roster || [];
        var parts = [];
        for (var i = 0; i < roster.length; i++) {
            var params = summarizeCustomParameters(roster[i].parameters);
            parts.push(roster[i].type + (params ? '{' + params + '}' : '') + ' Lv.' + roster[i].level + ' ×' + roster[i].count);
        }
        return parts.join(' / ');
    }

    function summarizeCustomParameters(parameters) {
        if (!customHasParameters(parameters)) return '';
        var parts = [];
        var keys = Object.keys(parameters).sort();
        for (var i = 0; i < keys.length && parts.length < 3; i++) {
            var key = keys[i];
            var value = parameters[key];
            if (value == null || typeof value === 'object') parts.push(key);
            else parts.push(key + '=' + String(value));
        }
        if (keys.length > parts.length) parts.push('+' + (keys.length - parts.length));
        return parts.join(' / ');
    }

    function truncateCustomText(text, maxLen) {
        text = String(text || '');
        maxLen = Number(maxLen) || 24;
        if (text.length <= maxLen) return text;
        return text.slice(0, Math.max(1, maxLen - 1)) + '…';
    }

    function customRosterTotal(roster) {
        var total = 0;
        roster = roster || [];
        for (var i = 0; i < roster.length; i++) total += Number(roster[i].count) || 0;
        return total;
    }

    function customRunActive() {
        return !!(_customRun && (
            _customRun.state === 'running' ||
            _customRun.state === 'queued' ||
            _customRun.state === 'abort_requested'
        ));
    }

    function customRunTerminal() {
        return !!(_customRun && (
            _customRun.state === 'completed' ||
            _customRun.state === 'failed' ||
            _customRun.state === 'aborted'
        ));
    }

    function customRunText() {
        if (!_customRun) return '状态：未委托';
        var text = '状态：' + (_customRun.state || 'unknown');
        if (_customRun.completedRuns != null && _customRun.totalRuns != null) {
            text += ' · ' + _customRun.completedRuns + '/' + _customRun.totalRuns;
        }
        if (_customRun.lastResult && customRunTerminal()) text += ' · ' + customResultSummaryText(_customRun.lastResult);
        if (_customRun.batchId) text += ' · ' + _customRun.batchId;
        if (_customRun.resultPath && customRunTerminal()) text += ' · ' + _customRun.resultPath;
        if (_customRun.lastError) text += ' · ' + _customRun.lastError;
        if (_customRun.error && !_customRun.success) text += ' · ' + _customRun.error;
        return text;
    }

    function buildCustomRunStatusHtml(isPve) {
        if (isPve) {
            return buildCustomStatusChip('状态', '可挑战', 'ok') +
                buildCustomStatusChip('路径', '标准竞技场', '');
        }
        if (!_customRun) return buildCustomStatusChip('状态', '未委托', '');
        var state = _customRun.state || 'unknown';
        var html = buildCustomStatusChip('状态', customRunStateLabel(state), customRunTerminal() ? 'done' : 'active');
        if (_customRun.completedRuns != null && _customRun.totalRuns != null) {
            html += buildCustomStatusChip('进度', _customRun.completedRuns + '/' + _customRun.totalRuns, '');
        }
        if (_customRun.lastResult && customRunTerminal()) {
            html += buildCustomStatusChip('结果', customResultSummaryText(_customRun.lastResult).replace(/^结果：/, ''), 'done');
        }
        if (_customRun.batchId) html += buildCustomStatusChip('批次', _customRun.batchId, 'mono');
        if (_customRun.resultPath && customRunTerminal()) html += buildCustomStatusChip('日志', _customRun.resultPath, 'mono');
        if (_customRun.lastError) html += buildCustomStatusChip('错误', _customRun.lastError, 'error');
        if (_customRun.error && !_customRun.success) html += buildCustomStatusChip('错误', _customRun.error, 'error');
        return html;
    }

    function customRunStateLabel(state) {
        if (state === 'queued') return '排队中';
        if (state === 'running') return '运行中';
        if (state === 'abort_requested') return '中止中';
        if (state === 'completed') return '已完成';
        if (state === 'failed') return '失败';
        if (state === 'aborted') return '已中止';
        if (state === 'idle') return '空闲';
        return state || '未知';
    }

    function buildCustomStatusChip(label, value, kind) {
        var cls = 'arena-custom-status-chip' + (kind ? ' arena-custom-status-chip-' + kind : '');
        return '<span class="' + cls + '"><em>' + escapeHtml(label) + '</em><b>' + escapeHtml(value == null ? '--' : value) + '</b></span>';
    }

    function renderCustomCodeStatus() {
        var el = _el ? _el.querySelector('#arena-custom-code-status') : null;
        if (!el || !_customMatch) return;
        if (_customMatch.parsed) {
            var parsed = _customMatch.parsed;
            var left = parsed.mode === 'pve'
                ? customRosterTotal(parsed.enemyRoster)
                : customRosterTotal(parsed.blueRoster);
            var right = parsed.mode === 'pve'
                ? 1
                : customRosterTotal(parsed.redRoster);
            el.className = 'arena-custom-code-status arena-custom-code-status-ok';
            el.textContent = '实时解析 OK · mode=' + parsed.mode + ' · seed=' + parsed.seed + ' · ' + left + ' vs ' + right;
        } else {
            el.className = 'arena-custom-code-status arena-custom-code-status-error';
            el.textContent = '实时解析失败 · ' + (_customMatch.error || '赛程代码无效');
        }
    }

    function customResultSummaryText(result) {
        if (!result) return '结果：未知';
        var winner = String(result.winner || 'none');
        var label = winner === 'blue' ? '蓝方胜'
            : winner === 'red' ? '红方胜'
            : winner === 'timeout' ? '超时'
            : winner === 'draw' ? '平局'
            : '无胜者';
        var status = result.status ? String(result.status) : '';
        var frames = result.frames != null ? String(result.frames) + '帧' : '';
        var parts = [label];
        if (status) parts.push(status);
        if (frames) parts.push(frames);
        return '结果：' + parts.join(' / ');
    }

    function renderCustomResultView() {
        if (!_customResultViewEl) return;
        ensureCustomMatchState();
        if (typeof ArenaCustomResultView === 'undefined' || !ArenaCustomResultView.render) {
            _customResultViewEl.innerHTML =
                '<div class="arena-custom-result-panel">' +
                    '<div class="arena-custom-result-error">结算视图模块未加载</div>' +
                '</div>';
            return;
        }
        ArenaCustomResultView.render(_customResultViewEl, {
            run: _customRun || {},
            customResult: _customResult,
            customMatch: _customMatch,
            escapeHtml: escapeHtml,
            summarizeCustomRoster: summarizeCustomRoster
        });
    }

    function onCustomResultClick(e) {
        var node = e.target;
        while (node && node !== _customResultViewEl) {
            if (node.getAttribute) {
                var action = node.getAttribute('data-custom-result-action');
                if (action === 'back') {
                    onCustomResultBack();
                    return;
                }
                if (action === 'copy') {
                    copyCustomMatchCode();
                    return;
                }
                if (action === 'reopen') {
                    reopenCustomResultPanel();
                    return;
                }
            }
            node = node.parentNode;
        }
    }

    function onCustomResultBack() {
        if (_busy) return;
        requestCustomResultReturnBase();
    }

    function reopenCustomResultPanel() {
        if (_busy) return;
        ensureCustomMatchState();
        if (_customMatch && _customMatch.parsed) _customMatch.code = _customMatch.parsed.canonical;
        _customRun = null;
        _customResult = null;
        // 再赛一场已回到编辑态，后续 ESC/× 是普通取消，不再请求 AS2 返回基地。
        _customResultReturnBaseRequired = false;
        _customConfirmOpen = false;
        _customEditorPage = 'config';
        _customParamEditor = null;
        _customUndo = null;
        clearCustomPoll();
        rebuildForMode('custom');
        showToast('已回到定制赛面板，可再次确认开赛');
    }

    function applyCustomRunStatus(data) {
        _customRun = {
            success: data.success !== false,
            state: data.state || 'unknown',
            note: data.note || '',
            batchId: data.batchId || (_customRun && _customRun.batchId) || '',
            manifestHash: data.manifestHash || '',
            manifestPath: data.manifestPath || '',
            frozenManifestPath: data.frozenManifestPath || '',
            resultPath: data.resultPath || '',
            totalRuns: data.totalRuns,
            completedRuns: data.completedRuns,
            currentCaseId: data.currentCaseId || '',
            currentRunId: data.currentRunId || '',
            lastError: data.lastError || data.message || '',
            error: data.error || '',
            lastResult: data.lastResult || (_customRun && _customRun.lastResult) || null,
            reopened: data.reopened || (_customRun && _customRun.reopened) || false
        };
        refreshCustomMatchCard();
    }

    function normalizeCustomResultInitData(initData) {
        if (!initData || initData.mode !== 'custom_result') return null;
        return {
            mode: 'custom_result',
            source: initData.source || 'arena_custom_match_result',
            matchCode: initData.matchCode || '',
            state: initData.state || 'completed',
            batchId: initData.batchId || '',
            resultPath: initData.resultPath || '',
            manifestPath: initData.manifestPath || '',
            frozenManifestPath: initData.frozenManifestPath || '',
            totalRuns: initData.totalRuns,
            completedRuns: initData.completedRuns,
            lastError: initData.lastError || '',
            lastResult: initData.lastResult || null
        };
    }

    function buildCustomRunFromResult(result) {
        return {
            success: result.state !== 'failed',
            state: result.state || 'completed',
            note: 'settled',
            batchId: result.batchId || '',
            manifestHash: '',
            manifestPath: result.manifestPath || '',
            frozenManifestPath: result.frozenManifestPath || '',
            resultPath: result.resultPath || '',
            totalRuns: result.totalRuns,
            completedRuns: result.completedRuns,
            currentCaseId: '',
            currentRunId: '',
            lastError: result.lastError || '',
            error: '',
            lastResult: result.lastResult || null,
            reopened: true
        };
    }

    function clearCustomPoll() {
        _customPollTimer = ArenaCustomPolling.clear(_customPollTimer);
    }

    function scheduleCustomStatusPoll() {
        _customPollTimer = ArenaCustomPolling.schedule(_customPollTimer, {
            active: _activeMode === 'custom' && customRunActive(),
            delayMs: 1000,
            callback: function() {
            _customPollTimer = 0;
            requestCustomStatus();
            }
        });
    }

    function requestCustomStatus() {
        if (_activeMode !== 'custom' || !_customRun) return;
        sendCustomRequest('custom_status', { batchId: _customRun.batchId || '' }, function(data) {
            applyCustomRunStatus(data);
            if (customRunActive()) scheduleCustomStatusPoll();
        });
    }

    function sendCustomRequest(cmd, payload, cb) {
        var reqId = 'arena_custom_' + (++_reqSeq) + '_' + _session;
        _pendingReq[reqId] = function(data) {
            if (typeof cb === 'function') cb(data || {});
        };
        payload = payload || {};
        payload.type = 'panel';
        payload.panel = 'arena';
        payload.cmd = cmd;
        payload.callId = reqId;
        Bridge.send(payload);
    }

    function onCustomCodeInput(e) {
        ensureCustomMatchState();
        var input = e.target || e.currentTarget;
        _customMatch.code = input.value;
        parseCustomMatchCode();
        refreshCustomMatchCard();
    }

    function handleCustomAction(action, node) {
        if (!action) return false;
        if (_busy || customRunActive()) return true;
        ensureCustomMatchState();
        if (action === 'random') {
            applyRandomCustomPreset();
        } else if (action === 'preset') {
            applySelectedCustomPreset();
        } else if (action === 'copy') {
            copyCustomMatchCode();
        } else if (action === 'swap-sides') {
            swapCustomSides();
        } else if (action === 'edit') {
            showCustomEditorForSide(node ? node.getAttribute('data-custom-edit-side') : '');
        } else {
            parseCustomMatchCode();
            refreshCustomMatchCard();
            showToast(_customMatch.parsed ? '赛程代码已导入' : '赛程代码无效');
        }
        return true;
    }

    function setCustomEditorMode(mode) {
        mode = mode === 'pve' ? 'pve' : 'mvm';
        var editor = ensureCustomEditorState();
        if (editor.mode === mode) return;
        captureCustomUndo('切换模式');
        editor.mode = mode;
        if (mode === 'pve') {
            _customSelectedSide = 'red';
            if (!editor.red.length) {
                var fallback = parseCustomCodeForEditor(CUSTOM_PVE_FALLBACK_CODE);
                if (fallback && fallback.enemyRoster) editor.red = cloneCustomRoster(fallback.enemyRoster);
            }
        } else if (!editor.blue.length) {
            var parsed = parseCustomCodeForEditor(CUSTOM_MATCH_FALLBACK_CODE);
            if (parsed) {
                editor.blue = cloneCustomRoster(parsed.blueRoster);
                if (!editor.red.length) editor.red = cloneCustomRoster(parsed.redRoster);
            }
        }
        syncCustomCodeFromEditor();
        showToast(mode === 'pve' ? '已切换为玩家 vs 怪物' : '已切换为怪物 vs 怪物');
    }

    function applyRandomCustomPreset() {
        var presets = getCustomPresets();
        captureCustomUndo('随机整局');
        if (!presets.length) {
            applyCustomMatchCode(getDefaultCustomMatchCode(), '已载入默认组合');
            return;
        }
        var nextIndex = Math.floor(Math.random() * presets.length);
        if (presets.length > 1 && nextIndex === _customSampleIndex) {
            nextIndex = (nextIndex + 1) % presets.length;
        }
        _customSampleIndex = nextIndex;
        var select = _el ? _el.querySelector('#arena-custom-preset-select') : null;
        if (select && presets[_customSampleIndex]) select.value = presets[_customSampleIndex].id;
        applyCustomPresetCodeForCurrentMode(presets[_customSampleIndex].code, '已随机抽取待标定组合');
    }

    function applySelectedCustomPreset() {
        var select = _el ? _el.querySelector('#arena-custom-preset-select') : null;
        var preset = findCustomPresetById(select ? select.value : '');
        captureCustomUndo('载入整局');
        applyCustomPresetCodeForCurrentMode((preset && preset.code) || getDefaultCustomMatchCode(), '已载入待标定组合');
    }

    function applyCustomPresetCodeForCurrentMode(code, toast) {
        var editor = ensureCustomEditorState();
        if (editor.mode !== 'pve') {
            applyCustomMatchCode(code, toast);
            return;
        }
        var parsed = parseCustomCodeForEditor(code);
        if (!parsed) {
            showToast('预设解析失败');
            return;
        }
        var roster = parsed.mode === 'pve'
            ? parsed.enemyRoster
            : ((parsed.redRoster && parsed.redRoster.length) ? parsed.redRoster : parsed.blueRoster);
        editor.red = cloneCustomRoster(roster || []);
        syncCustomCodeFromEditor();
        if (toast) showToast(toast);
    }

    function parseCustomCodeForEditor(code) {
        ensureCustomModule();
        try {
            return ArenaCustomMatchCode.parseMatchCode(code, {
                unitCatalog: collectCustomUnitCatalog(),
                caseId: 'arena-custom-p3'
            });
        } catch (err) {
            return null;
        }
    }

    function applyRandomCustomSidePreset(side) {
        side = resolveCustomSide(side);
        var presets = getCustomPresets();
        if (!presets.length) return;
        var preset = presets[Math.floor(Math.random() * presets.length)];
        var parsed = parseCustomPresetForRoster(preset);
        if (!parsed) {
            showToast('随机组合解析失败');
            return;
        }
        var roster = parsed.mode === 'pve'
            ? parsed.enemyRoster
            : ((parsed.redRoster && parsed.redRoster.length) ? parsed.redRoster : parsed.blueRoster);
        captureCustomUndo(customSideLabel(side) + '随机组合');
        setCustomSideRoster(side, roster || []);
        showToast(customSideLabel(side) + '已随机抽取待标定组合');
    }

    function parseCustomPresetForRoster(preset) {
        if (!preset || !preset.code) return null;
        return parseCustomCodeForEditor(preset.code);
    }

    function saveCustomSideConfig(side) {
        side = resolveCustomSide(side);
        var roster = cloneCustomRoster(getCustomSideRoster(side));
        if (!roster.length) {
            showToast(customSideLabel(side) + '为空，未保存');
            return;
        }
        var summary = summarizeCustomRoster(roster);
        var label = customSideLabel(side) + ' · ' + customRosterTotal(roster) + '体 · ' + truncateCustomText(summary, 26);
        var saved = getCustomSavedRosters().slice();
        saved.unshift({
            id: 'saved-' + Date.now() + '-' + Math.floor(Math.random() * 10000),
            label: label,
            createdAt: new Date().toISOString(),
            roster: roster
        });
        if (saved.length > CUSTOM_SAVED_ROSTER_LIMIT) saved.length = CUSTOM_SAVED_ROSTER_LIMIT;
        if (!saveCustomSavedRosters(saved)) return;
        renderCustomEditor();
        showToast(customSideLabel(side) + '配置已保存');
    }

    function loadCustomSideConfig(side) {
        side = resolveCustomSide(side);
        var selectorKey = side;
        var activeSelect = _el ? _el.querySelector('[data-custom-saved-select="active"]') : null;
        if (_customEditorPage === 'side' && activeSelect) selectorKey = 'active';
        var select = _el ? _el.querySelector('[data-custom-saved-select="' + selectorKey + '"]') : null;
        var saved = findCustomSavedRosterById(select ? select.value : '');
        if (!saved) {
            showToast('暂无可读取配置');
            return;
        }
        captureCustomUndo(customSideLabel(side) + '读取配置');
        setCustomSideRoster(side, saved.roster);
        showToast(customSideLabel(side) + '已读取配置');
    }

    function swapCustomSides() {
        var editor = ensureCustomEditorState();
        captureCustomUndo('交换红蓝');
        var nextBlue = cloneCustomRoster(editor.red);
        var nextRed = cloneCustomRoster(editor.blue);
        editor.blue = nextBlue;
        editor.red = nextRed;
        _customSelectedSide = _customSelectedSide === 'red' ? 'blue' : 'red';
        syncCustomCodeFromEditor();
        showToast('红蓝配置已交换');
    }

    function handleCustomSideAction(action, side) {
        if (!action) return false;
        if (_busy || customRunActive()) return true;
        if ((_customEditor && _customEditor.mode === 'pve') && side === 'blue') {
            showToast('玩家使用当前存档，无需配置');
            return true;
        }
        side = resolveCustomSide(side);
        if (action === 'edit') {
            showCustomSideEditorPage(side);
        } else if (action === 'random') {
            applyRandomCustomSidePreset(side);
        } else if (action === 'save') {
            saveCustomSideConfig(side);
        } else if (action === 'load') {
            loadCustomSideConfig(side);
        } else if (action === 'clear') {
            clearCustomRosterSide(side);
        } else {
            return false;
        }
        return true;
    }

    function findCustomPresetById(id) {
        var presets = getCustomPresets();
        for (var i = 0; i < presets.length; i++) {
            if (presets[i].id === id) return presets[i];
        }
        return presets[0] || null;
    }

    function applyCustomMatchCode(code, toast) {
        ensureCustomMatchState();
        _customMatch.code = code || getDefaultCustomMatchCode();
        parseCustomMatchCode();
        refreshCustomMatchCard();
        if (toast) showToast(toast);
    }

    function onCustomUnitSearchInput(e) {
        var editor = ensureCustomEditorState();
        var input = e.target || e.currentTarget;
        editor.query = input.value || '';
        resetCustomUnitBrowserWindow(editor);
        renderCustomUnitBrowser();
    }

    function resetCustomUnitBrowserWindow(editor) {
        editor = editor || ensureCustomEditorState();
        editor.unitVisibleRows = CUSTOM_BROWSER_BATCH_SIZE;
    }

    function onCustomUnitBrowserScroll(e) {
        var listEl = e.currentTarget || e.target;
        if (!listEl) return;
        if (listEl.scrollTop + listEl.clientHeight < listEl.scrollHeight - 48) return;
        var editor = ensureCustomEditorState();
        var visibleRows = editor.unitVisibleRows || CUSTOM_BROWSER_BATCH_SIZE;
        var totalRows = editor.unitScrollableRows || 0;
        if (visibleRows >= totalRows) return;
        editor.unitVisibleRows = Math.min(totalRows, visibleRows + CUSTOM_BROWSER_BATCH_SIZE);
        renderCustomUnitBrowser({ preserveScroll: true });
    }

    function toggleCustomUnitFaction(factionKey) {
        var editor = ensureCustomEditorState();
        editor.expandedFactions = editor.expandedFactions || {};
        if (editor.expandedFactions[factionKey]) delete editor.expandedFactions[factionKey];
        else editor.expandedFactions[factionKey] = true;
        resetCustomUnitBrowserWindow(editor);
        renderCustomUnitBrowser();
    }

    function onCustomEditorInput(e) {
        var input = e.target;
        if (!input) return;
        if (input.id === 'arena-custom-code-input') {
            onCustomCodeInput(e);
            return;
        }
        if (input.hasAttribute && input.hasAttribute('data-custom-param-editor-input')) {
            updateCustomParamDraft(input.value);
            return;
        }
        if (input.id !== 'arena-custom-unit-search') return;
        onCustomUnitSearchInput(e);
    }

    function onCustomSideSelect(e) {
        var side = e.currentTarget.getAttribute('data-custom-side');
        if (side === 'blue' || side === 'red') {
            if ((_customEditor && _customEditor.mode === 'pve') && side === 'blue') {
                _customSelectedSide = 'red';
                renderCustomEditor();
                return;
            }
            _customSelectedSide = side;
            renderCustomEditor();
        }
    }

    function onCustomWorkbenchClick(e) {
        var node = e.target;
        while (node && node !== e.currentTarget) {
            if (node.getAttribute) {
                var editorAction = node.getAttribute('data-custom-editor-action');
                if (editorAction === 'back' || editorAction === 'done') {
                    if (editorAction === 'back' && _customEditorPage === 'params') {
                        leaveCustomParamEditorDiscardingDraft();
                        return;
                    }
                    if (editorAction === 'back' && _customEditorPage === 'side') {
                        showCustomEditorConfigPage();
                        return;
                    }
                    showGridView();
                    return;
                }
                if (editorAction === 'undo') {
                    restoreCustomUndo();
                    return;
                }
                if (editorAction === 'to-config') {
                    showCustomEditorConfigPage();
                    return;
                }
                if (editorAction === 'copy') {
                    copyCustomMatchCode();
                    return;
                }
                var customMode = node.getAttribute('data-custom-mode');
                if (customMode === 'mvm' || customMode === 'pve') {
                    setCustomEditorMode(customMode);
                    return;
                }
                var customAction = node.getAttribute('data-custom-action');
                if (handleCustomAction(customAction, node)) {
                    return;
                }
                var sideAction = node.getAttribute('data-custom-side-action');
                if (handleCustomSideAction(sideAction, node.getAttribute('data-side'))) {
                    return;
                }
                var side = node.getAttribute('data-custom-side');
                if (side === 'blue' || side === 'red') {
                    if ((_customEditor && _customEditor.mode === 'pve') && side === 'blue') {
                        _customSelectedSide = 'red';
                        renderCustomEditor();
                        return;
                    }
                    _customSelectedSide = side;
                    renderCustomEditor();
                    return;
                }
                var paramMode = node.getAttribute('data-custom-param-mode');
                if (paramMode === 'json' || paramMode === 'xml') {
                    setCustomParamEditorMode(paramMode);
                    return;
                }
                var paramAction = node.getAttribute('data-custom-param-action');
                if (paramAction === 'back') {
                    leaveCustomParamEditorDiscardingDraft();
                    return;
                }
                if (paramAction === 'apply') {
                    applyCustomParamDraft(false);
                    return;
                }
                if (paramAction === 'save-back') {
                    applyCustomParamDraft(true);
                    return;
                }
                if (paramAction === 'clear') {
                    clearCustomParamDraft();
                    return;
                }
                var filter = node.getAttribute('data-custom-unit-filter');
                if (filter === 'all' || filter === 'hostile' || filter === 'nonhostile') {
                    var editor = ensureCustomEditorState();
                    editor.filter = filter;
                    resetCustomUnitBrowserWindow(editor);
                    renderCustomUnitBrowser();
                    return;
                }
                var factionKey = node.getAttribute('data-custom-toggle-faction');
                if (factionKey) {
                    toggleCustomUnitFaction(factionKey);
                    return;
                }
                var clearSide = node.getAttribute('data-custom-clear-side');
                if (clearSide === 'blue' || clearSide === 'red') {
                    clearCustomRosterSide(clearSide);
                    return;
                }
                var adjustCount = node.getAttribute('data-custom-adjust-count');
                if (adjustCount) {
                    adjustCustomRosterCount(node.getAttribute('data-side'), Number(node.getAttribute('data-index')), Number(adjustCount));
                    return;
                }
                var addId = node.getAttribute('data-custom-add-unit');
                if (addId) {
                    addCustomUnitToSide(Number(addId), _customSelectedSide, node.getAttribute('data-custom-preset-id'));
                    return;
                }
                if (node.hasAttribute('data-custom-edit-params')) {
                    showCustomParamEditorPage(node.getAttribute('data-side'), Number(node.getAttribute('data-index')));
                    return;
                }
                if (node.hasAttribute('data-custom-remove')) {
                    removeCustomRosterEntry(node.getAttribute('data-side'), Number(node.getAttribute('data-index')));
                    return;
                }
                var confirmAction = node.getAttribute('data-custom-confirm-action');
                if (confirmAction === 'cancel') {
                    _customConfirmOpen = false;
                    refreshCustomMatchCard();
                    return;
                }
                if (confirmAction === 'start') {
                    startCustomMatch();
                    return;
                }
            }
            node = node.parentNode;
        }
    }

    function onCustomWorkbenchChange(e) {
        var input = e.target;
        if (!input || !input.getAttribute) return;
        var field = input.getAttribute('data-custom-roster-input');
        if (field !== 'level' && field !== 'count') return;
        updateCustomRosterEntry(input.getAttribute('data-side'), Number(input.getAttribute('data-index')), field, Number(input.value));
    }

    function addCustomUnitToSide(unitId, side, presetId) {
        var editor = ensureCustomEditorState();
        var roster = side === 'red' ? editor.red : editor.blue;
        var unit = getCustomUnitById(unitId);
        var preset = findCustomUnitParameterPreset(presetId);
        var parameters = preset && customHasParameters(preset.parameters) ? cloneCustomParameters(preset.parameters) : null;
        var level = preset && Number(preset.defaultLevel) > 0
            ? Number(preset.defaultLevel)
            : (Number(unit.level) > 0 ? Number(unit.level) : 1);
        for (var i = 0; i < roster.length; i++) {
            if (roster[i].id === unitId && roster[i].level === level && customParametersEqual(roster[i].parameters, parameters)) {
                captureCustomUndo(customSideLabel(side) + '添加单位');
                roster[i].count++;
                syncCustomCodeFromEditor();
                return;
            }
        }
        captureCustomUndo(customSideLabel(side) + '添加单位');
        var entry = { id: unitId, type: '兵种' + unitId, level: level, count: 1 };
        if (parameters) {
            entry.parameters = parameters;
            entry.presetId = preset.id;
            entry.presetLabel = preset.summary || summarizeCustomParameters(parameters);
        }
        roster.push(entry);
        syncCustomCodeFromEditor();
    }

    function removeCustomRosterEntry(side, index) {
        var editor = ensureCustomEditorState();
        var roster = side === 'red' ? editor.red : editor.blue;
        if (index >= 0 && index < roster.length) {
            captureCustomUndo(customSideLabel(side) + '移除单位');
            roster.splice(index, 1);
            syncCustomCodeFromEditor();
        }
    }

    function clearCustomRosterSide(side) {
        var editor = ensureCustomEditorState();
        var roster = side === 'red' ? editor.red : editor.blue;
        if (!roster || !roster.length) return;
        captureCustomUndo(customSideLabel(side) + '清空阵容');
        if (side === 'red') editor.red = [];
        else editor.blue = [];
        syncCustomCodeFromEditor();
    }

    function adjustCustomRosterCount(side, index, delta) {
        var editor = ensureCustomEditorState();
        var roster = side === 'red' ? editor.red : editor.blue;
        if (index < 0 || index >= roster.length) return;
        var next = (Number(roster[index].count) || 1) + delta;
        if (next < 1) next = 1;
        if (next > 20) next = 20;
        if (next === roster[index].count) return;
        captureCustomUndo(customSideLabel(side) + '调整数量');
        roster[index].count = next;
        syncCustomCodeFromEditor();
    }

    function updateCustomRosterEntry(side, index, field, value) {
        var editor = ensureCustomEditorState();
        var roster = side === 'red' ? editor.red : editor.blue;
        if (index < 0 || index >= roster.length) return;
        if (isNaN(value) || value < 1) value = 1;
        value = Math.floor(value);
        if (field === 'count' && value > 20) value = 20;
        if (roster[index][field] === value) return;
        captureCustomUndo(customSideLabel(side) + (field === 'level' ? '调整等级' : '调整数量'));
        roster[index][field] = value;
        // 数字输入 change 后也要刷新隐藏入口卡，否则点“完成”回 grid 会看到旧摘要。
        syncCustomCodeFromEditor();
    }

    function setCustomRosterParametersValue(side, index, value) {
        var editor = ensureCustomEditorState();
        var roster = resolveCustomSide(side) === 'red' ? editor.red : editor.blue;
        if (index < 0 || index >= roster.length) return false;
        if (customParametersEqual(roster[index].parameters, value)) return true;
        captureCustomUndo(customSideLabel(side) + '应用参数');
        if (customHasParameters(value)) {
            roster[index].parameters = cloneCustomParameters(value);
            delete roster[index].presetId;
            roster[index].presetLabel = summarizeCustomParameters(roster[index].parameters);
        } else {
            delete roster[index].parameters;
            delete roster[index].presetId;
            delete roster[index].presetLabel;
        }
        syncCustomCodeFromEditor();
        return true;
    }

    function copyCustomMatchCode() {
        ensureCustomMatchState();
        if (_customMatch.parsed) _customMatch.code = _customMatch.parsed.canonical;
        var text = _customMatch.code || '';
        var done = function() { showToast('赛程代码已复制'); };
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(done, function() { showToast('复制失败，请手动复制'); });
        } else {
            showToast('当前环境不支持自动复制');
        }
        var input = _el ? _el.querySelector('#arena-custom-code-input') : null;
        if (input) input.value = text;
    }

    function onCustomGenerate() {
        if (_busy || customRunActive()) return;
        ensureCustomMatchState();
        parseCustomMatchCode();
        refreshCustomMatchCard();
        if (!_customMatch.parsed) {
            showToast('赛程代码无效');
            return;
        }
        _customConfirmOpen = true;
        refreshCustomMatchCard();
    }

    function startCustomMatch() {
        if (_busy || customRunActive()) return;
        ensureCustomMatchState();
        parseCustomMatchCode();
        refreshCustomMatchCard();
        if (!_customMatch.parsed) {
            showToast('赛程代码无效');
            return;
        }
        if (_customMatch.parsed.mode === 'pve') {
            startCustomPveMatch(_customMatch.parsed);
            return;
        }
        _busy = true;
        refreshCustomMatchCard();
        sendCustomRequest('custom_start', {
            matchCode: _customMatch.parsed.canonical,
            calibrationCase: _customMatch.parsed.calibrationCase,
            venueFeeEstimate: _customMatch.parsed.venueFeeEstimate
        }, function(data) {
            _busy = false;
            applyCustomRunStatus(data);
            if (data.success === false) {
                showToast(data.message || data.error || '委托启动失败');
                return;
            }
            showToast('定制赛委托已开始');
            if (data.closePanel) {
                requestClose({ dismissReturnStack: true });
                return;
            }
            scheduleCustomStatusPoll();
        });
    }

    function startCustomPveMatch(parsed) {
        var payload = parsed && parsed.enterPayload;
        if (!payload || !payload.roster || !payload.roster.length) {
            showToast('怪物配置为空');
            return;
        }
        _busy = true;
        refreshCustomMatchCard();

        var reqId = 'arena_custom_pve_' + (++_reqSeq) + '_' + _session;
        _pendingReq[reqId] = function(data) {
            _busy = false;
            refreshCustomMatchCard();
            if (!data.success) {
                showToast(data.error || '挑战发起失败');
                return;
            }
            showToast('玩家对怪物挑战已开始');
            if (data.closePanel) requestClose({ dismissReturnStack: true });
        };

        var msg = {};
        for (var key in payload) {
            if (Object.prototype.hasOwnProperty.call(payload, key)) msg[key] = payload[key];
        }
        msg.type = 'panel';
        msg.panel = 'arena';
        msg.cmd = 'enter';
        msg.callId = reqId;
        msg.difficulty = _initDifficulty || msg.difficulty || '';
        msg.matchCode = parsed.canonical;
        Bridge.send(msg);
    }

    function onCustomAbort() {
        if (_busy || !customRunActive()) return;
        _busy = true;
        refreshCustomMatchCard();
        sendCustomRequest('custom_abort', {
            batchId: _customRun.batchId || ''
        }, function(data) {
            _busy = false;
            applyCustomRunStatus(data);
            showToast(data.success === false ? (data.message || data.error || '中止失败') : '已请求中止');
            if (customRunActive()) scheduleCustomStatusPoll();
        });
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 交互
    // ════════════════════════════════════════════════════════════════════════════
    function onCardClick(e) {
        e.stopPropagation();
        if (_busy) return;

        // currentTarget = 绑事件的 button 自身；target 在 button 内含子元素时可能是 textNode
        var btn = e.currentTarget || e.target;
        var idx = parseInt(btn.dataset.index, 10);
        var card = _activeCards[idx];
        if (!card) return;

        _activeCardIdx = idx;

        _detailTitleEl.textContent = card.isEscalation
            ? (card.faction + ' · 爬升挑战（无限波 · 奖池押注）')
            : card.isFallen
                ? (card.faction + ' · ' + difficultyOf(card).label + ' 挑战')
                : ('DEATH MATCH · 段位 ' + card.index + ' · ' + difficultyOf(card).label);
        _detailMetaEl.innerHTML =
            '<span class="arena-meta-chip">对手 ×' + card.opponentCount + '</span>' +
            '<span class="arena-meta-chip">等级 ' + card.levelMin + '—' + card.levelMax + '</span>' +
            '<span class="arena-meta-chip arena-meta-deposit">押金 ' + formatMoney(card.deposit) + '</span>' +
            '<span class="arena-meta-chip arena-meta-reward">奖金 ' + formatMoney(card.reward) + '</span>';
        showDetailView();

        // cache 命中（batch preview 已抽过且成功）→ 直接渲，不发请求。WYSIWYG: detail 看到的 = grid 摘要里那批人
        if (_previewCache[idx]) {
            _previewOpponents = _previewCache[idx];
            renderOpponents(_previewCache[idx]);
            setDetailButtonsBusy(false);
            return;
        }

        // cache miss：① batch preview 仍 pending（dedup 命中等同一回包 fan out）② 失败后从 grid 进 detail 重试
        _previewOpponents = null;
        _detailOpponentsEl.innerHTML = '<div class="arena-opponents-loading">正在抽取对手…</div>';
        setDetailButtonsBusy(true);
        requestPreviewForCard(idx); // dedup 内部处理：pending 中则不重发，等回包 fan out 到 detail view
    }

    function onRollAgain() {
        if (_busy || _activeCardIdx < 0) return;
        var card = _activeCards[_activeCardIdx];
        if (!card) return;
        _detailOpponentsEl.innerHTML = '<div class="arena-opponents-loading">正在重新抽取…</div>';
        setDetailButtonsBusy(true);
        // 强制重抽：清 dedup token + cache + error + 种类决定（换一批可翻 merc↔monster），
        // 让 requestPreviewForCard 走完整新链路（含重新决定种类）。
        delete _previewPending[_activeCardIdx];
        delete _previewCache[_activeCardIdx];
        delete _previewError[_activeCardIdx];
        delete _cardKind[_activeCardIdx];
        delete _monsterSquad[_activeCardIdx];
        requestPreviewForCard(_activeCardIdx);
    }

    // grid 直入入口（"⚔ 开始挑战" 按钮）。从 _previewCache[cardIdx] 取 lineup 走入场链。
    // updateCardStates 在 cache 缺失时已 disable enter 按钮，这里 opponents 兜底校验只是双保险。
    function onDirectEnter(e) {
        e.stopPropagation();
        if (_busy) return;
        var btn = e.currentTarget || e.target;
        var cardIdx = parseInt(btn.dataset.index, 10);
        var card = _activeCards[cardIdx];
        if (!card) return;
        var opponents = _previewCache[cardIdx];
        if (!opponents) {
            showToast('对手数据未就绪');
            return;
        }
        enterChallenge(cardIdx, card, opponents);
    }

    function onConfirmChallenge() {
        if (_activeCardIdx < 0) return;
        enterChallenge(_activeCardIdx, _activeCards[_activeCardIdx], _previewOpponents);
    }

    // 入场链公共函数：detail "⚔ 确认挑战" 与 grid "⚔ 开始挑战" 共用。
    // 接口约定：opponents 由 caller 传入（detail = _previewOpponents；grid = _previewCache[idx]），
    // 本函数不关心来源。busy UI 反馈分两路：detail 走 setDetailButtonsBusy，grid 走 updateCardStates。
    function enterChallenge(cardIdx, card, opponents) {
        if (_busy || cardIdx < 0 || !card || !opponents || opponents.length === 0) return;
        if (_snapshot && _snapshot.money != null && _snapshot.money < card.deposit) {
            showToast('金钱不足！');
            return;
        }

        _busy = true;
        if (_activeCardIdx >= 0) {
            setDetailButtonsBusy(true);
        } else {
            updateCardStates(); // grid 直入：刷新所有 enter 按钮 → _busy 让全部 disable
        }

        var reqId = 'arena_ent_' + (++_reqSeq) + '_' + _session;
        _pendingReq[reqId] = function(data) {
            _busy = false;
            if (_activeCardIdx >= 0) {
                setDetailButtonsBusy(false);
            } else {
                updateCardStates();
            }
            if (!data.success) {
                showToast(data.error || '挑战发起失败');
                return;
            }
            // closePanel:true → 必须走 requestClose 而不是裸 Panels.close()，
            // 因为后者只关 web 端 UI，不通知 C# 收 PanelHost；不收的话 WebOverlay
            // 还停在 opaque/panelRect 模式遮盖 Flash → AS2 已转场但视觉黑屏。
            // dismissReturnStack=true：AS2 已跳关到 wuxianguotu_1，必须清整个返回链；
            // 否则 PanelHostController 会 pop 出 stage-select 重新打开遮挡战场视野。
            if (data.closePanel) requestClose({ dismissReturnStack: true });
        };

        var msg = {
            type: 'panel',
            panel: 'arena',
            cmd: 'enter',
            callId: reqId,
            cardIndex: cardIdx,
            expr: card.expr,
            deposit: card.deposit,
            reward: card.reward,
            // 来自 stage-select 重定向时是 "冒险"/"修罗" 等；dev 直开时是 ""。
            // AS2 ArenaPanelService 在非空时设 _root.当前关卡难度，让任务系统能匹配。
            difficulty: _initDifficulty
        };
        // 爬升模式：下发该势力完整单位池 + 起始波基准，AS2 逐波采样爬升（不发 roster 快照）。
        if (card.isEscalation) {
            msg.mode = 'escalation';
            msg.faction = card.faction;
            msg.baseCount = card.opponentCount;
            msg.baseLevelMin = card.levelMin;
            msg.baseLevelMax = card.levelMax;
            msg.maxWaves = card.maxWaves;        // 波数上限（小5/大10/联军15）
            msg.pool = factionPool(card.faction);
        }
        // 怪物卡（堕落/标准混入）：把本地采样的非人形小队作为 roster 下发 → AS2 走 commitRoster 生成非人形怪。
        // WYSIWYG：下发的就是 grid/detail 预览里那批怪（type+level 一一对应）。
        else if (_cardKind[cardIdx] === 'monster' && opponents[0] && opponents[0].isMonster) {
            var roster = [];
            for (var ri = 0; ri < opponents.length; ri++) {
                var rosterEntry = { type: opponents[ri].type, level: opponents[ri].level };
                if (customHasParameters(opponents[ri].parameters)) rosterEntry.parameters = cloneCustomParameters(opponents[ri].parameters);
                roster.push(rosterEntry);
            }
            msg.roster = roster;
        }
        Bridge.send(msg);
    }

    function setDetailButtonsBusy(busy) {
        _detailRollBtn.disabled = busy || _activeCardIdx < 0;
        _detailConfirmBtn.disabled = busy || !_previewOpponents || _previewOpponents.length === 0;
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 消息处理
    // ════════════════════════════════════════════════════════════════════════════
    Bridge.on('panel_resp', function(data) {
        if (!data || data.panel !== 'arena') return;
        var cb = _pendingReq[data.callId];
        if (cb) {
            delete _pendingReq[data.callId];
            cb(data);
        }
    });

    // ════════════════════════════════════════════════════════════════════════════
    // Snapshot
    // ════════════════════════════════════════════════════════════════════════════
    function requestSnapshot() {
        var reqId = 'arena_snap_' + (++_reqSeq) + '_' + _session;
        var snapSession = _session; // 闭包捕获，跨 panel reopen 不要触发旧 session 的 batch
        _pendingReq[reqId] = function(data) {
            if (data.success && data.snapshot) {
                _snapshot = data.snapshot;
                setKnownEnemies(_snapshot.knownEnemies);
                if (!modeAvailable(_activeMode)) {
                    rebuildForMode('standard');
                }
                refreshModeTabs();
                updateMoneyDisplay(_snapshot.money);
                updateCardStates();
                // snapshot 成功才发 batch preview：① 提早发会让 preview 回包后 updateCardStates 拿不到 money
                //   导致 enter 按钮在 money 未到时一闪亮一下；② snapshot 失败时 panel 实际不可用，preview 也无意义
                if (snapSession === _session) {
                    batchRequestPreview();
                }
            }
        };
        Bridge.send({
            type: 'panel',
            panel: 'arena',
            cmd: 'snapshot',
            callId: reqId
        });
    }

    // ════════════════════════════════════════════════════════════════════════════
    // Batch Preview（panel open 时并发抽 8 卡）
    // ════════════════════════════════════════════════════════════════════════════
    function batchRequestPreview() {
        if (_activeMode === 'custom') {
            refreshCustomMatchCard();
            return;
        }
        for (var i = 0; i < _activeCards.length; i++) {
            requestPreviewForCard(i);
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    // Preview（按 cardIdx 抽签 + 缓存）
    //
    // 两条触发路径：
    //   1. snapshot 成功 → batchRequestPreview() → 8 卡并发首抽
    //   2. detail "↻ 换一批" → onRollAgain → 强制重抽（清 cache/pending）
    //   3. cache miss（detail 进入时 batch 仍 pending 或失败重试）→ onCardClick / onSummaryRetry
    //
    // dedup：_previewPending[cardIdx] 已存在则 return，避免一卡多飞造成 reqId 失效。
    // 双 view 同步：回包写 _previewCache → renderCardSummary 同步 grid 摘要；若用户当前 detail
    //   看的就是该卡（_activeCardIdx === cardIdx），还会同步 detail 视图。
    // 跨 session 防护：reqId 含 _session，且回包时双重校验 _previewPending[cardIdx] === reqId
    //   防 onRollAgain 后被新 reqId 覆盖时旧回包污染。
    // ════════════════════════════════════════════════════════════════════════════
    function requestPreviewForCard(cardIdx) {
        if (_previewPending[cardIdx] !== undefined) return; // dedup（仅 merc 异步路径用）
        var card = _activeCards[cardIdx];
        if (!card) return;

        // 决定本卡种类（首抽 / 换一批后未决定时）。
        //   - 堕落卡：恒怪物，且锁定从本卡势力采样（非随机势力）；采样失败 → 报错，绝不退回 merc 路径
        //     （否则合成 expr 会被 AS2 当真去抽人形佣兵，串成人形对手）。
        //   - 标准卡：按 _mixChance 概率尝试混入随机势力怪物，未命中 → merc（AS2 往返抽佣兵）。
        if (_cardKind[cardIdx] === undefined) {
            if (card.isFallen) {
                var fsq = sampleFactionSquad(card.faction, card.levelMin, card.levelMax, card.opponentCount);
                if (fsq) { _cardKind[cardIdx] = 'monster'; _monsterSquad[cardIdx] = fsq; }
                else {
                    _previewError[cardIdx] = '该势力暂无可用单位';
                    renderCardSummary(cardIdx);
                    updateCardStates();
                    if (_activeCardIdx === cardIdx) {
                        _detailOpponentsEl.innerHTML = '<div class="arena-opponents-error">该势力暂无可用单位</div>';
                        setDetailButtonsBusy(false);
                        _detailConfirmBtn.disabled = true;
                    }
                    return;
                }
            } else {
                var decided = decideMonsterSquad(card);
                if (decided) { _cardKind[cardIdx] = 'monster'; _monsterSquad[cardIdx] = decided; }
                else { _cardKind[cardIdx] = 'merc'; }
            }
        }
        if (_cardKind[cardIdx] === 'monster') {
            applyMonsterPreview(cardIdx); // web 本地采样渲染，无 AS2 preview 往返
            return;
        }

        var reqId = 'arena_prev_' + (++_reqSeq) + '_' + _session;
        _previewPending[cardIdx] = reqId;
        delete _previewError[cardIdx]; // 清旧错误，让摘要进 loading 态

        // 摘要 UI 进 loading 态（覆盖上次失败 / 上次结果）
        var sumEl = document.getElementById('arena-opp-summary-' + cardIdx);
        if (sumEl) {
            sumEl.className = 'arena-card-opponents arena-card-opponents-loading';
            sumEl.textContent = '抽取中…';
            sumEl.onclick = null;
        }

        _pendingReq[reqId] = function(data) {
            // 跨 session 回包丢弃（panel 已 reopen，这条是上个 session 的）
            if (_previewPending[cardIdx] !== reqId) return;
            delete _previewPending[cardIdx];

            if (!data.success || !data.opponents) {
                _previewError[cardIdx] = data.error || '抽取失败';
                renderCardSummary(cardIdx);
                updateCardStates(); // 失败 → enter 按钮 disabled（hasPreview 为 false）
                if (_activeCardIdx === cardIdx) {
                    _detailOpponentsEl.innerHTML = '<div class="arena-opponents-error">' + escapeHtml(_previewError[cardIdx]) + '</div>';
                    setDetailButtonsBusy(false);
                    _detailConfirmBtn.disabled = true;
                }
                return;
            }

            _previewCache[cardIdx] = data.opponents;
            renderCardSummary(cardIdx);
            updateCardStates(); // 刷新 enter 按钮 enabled

            if (_activeCardIdx === cardIdx) {
                _previewOpponents = data.opponents;
                renderOpponents(data.opponents);
                setDetailButtonsBusy(false);
            }
        };

        Bridge.send({
            type: 'panel',
            panel: 'arena',
            cmd: 'preview',
            callId: reqId,
            cardIndex: cardIdx,
            expr: card.expr
        });
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 元战队（非人形怪）采样 — M2：web 本地从 window.ArenaMetaRosters 抽，无 AS2 往返
    // ════════════════════════════════════════════════════════════════════════════
    // 按概率 + 数据可用性决定本卡是否为怪物小队；返回 {faction, opponents} 或 null（=走 merc）。
    function decideMonsterSquad(card) {
        var rosters = (typeof window !== 'undefined' && window.ArenaMetaRosters)
            ? window.ArenaMetaRosters.factions : null;
        if (!rosters) return null;                       // 无数据（如 QA harness 未载）→ 恒 merc
        if (_knownEnemyCount <= 0) return null;           // 未击杀过对应 spritename → 不混入怪物，避免剧透
        if (Math.random() >= _mixChance) return null;    // 概率未命中 → merc
        return sampleMonsterSquad(rosters, card.levelMin, card.levelMax, card.opponentCount);
    }

    // 从与 [levelMin,levelMax] 重叠的某个势力 roster，按 weight 加权采样 count 个单位（可重复）。
    // 每个单位等级钳进卡片等级带。无重叠势力 → null（该等级带无怪可混，保持 merc）。
    function sampleMonsterSquad(rosters, levelMin, levelMax, count) {
        var eligible = [];
        for (var f in rosters) {
            var pool = poolForBand(rosters[f].units, levelMin, levelMax);
            if (pool.length) eligible.push({ faction: f, pool: pool });
        }
        if (eligible.length === 0) return null;
        var chosen = eligible[Math.floor(Math.random() * eligible.length)];
        return { faction: chosen.faction, opponents: weightedSample(chosen.pool, levelMin, levelMax, count) };
    }

    // 堕落模式（Phase 2）：从指定势力采样（非随机势力）。faction 缺失 / 无等级带重叠单位 → null。
    function sampleFactionSquad(factionName, levelMin, levelMax, count) {
        var factions = rostersAvailable() ? window.ArenaMetaRosters.factions : null;
        if (!factions || !factions[factionName]) return null;
        var pool = poolForBand(factions[factionName].units, levelMin, levelMax);
        if (!pool.length) return null;
        return { faction: factionName, opponents: weightedSample(pool, levelMin, levelMax, count) };
    }

    // 取势力单位中与 [levelMin,levelMax] 等级带重叠的子池。
    function poolForBand(units, levelMin, levelMax) {
        units = units || [];
        var pool = [];
        for (var i = 0; i < units.length; i++) {
            var u = units[i];
            if (!isKnownEnemyUnit(u)) continue;
            if (u.minLevel <= levelMax && u.maxLevel >= levelMin) pool.push(u);
        }
        return pool;
    }

    function setKnownEnemies(list) {
        _knownEnemies = {};
        _knownEnemyCount = 0;
        list = list || [];
        for (var i = 0; i < list.length; i++) {
            var key = String(list[i] || '');
            if (!key || _knownEnemies[key]) continue;
            _knownEnemies[key] = true;
            _knownEnemyCount++;
        }
    }

    function isKnownEnemyUnit(unit) {
        if (!unit || !unit.spritename) return false;
        return _knownEnemies[String(unit.spritename)] === true;
    }

    function filterKnownUnits(units) {
        units = units || [];
        var out = [];
        for (var i = 0; i < units.length; i++) {
            if (isKnownEnemyUnit(units[i])) out.push(units[i]);
        }
        return out;
    }

    // 从单位池按 weight 加权采样 count 个（可重复），每个单位等级钳进 [levelMin,levelMax]。
    function weightedSample(pool, levelMin, levelMax, count) {
        var totalW = 0;
        for (var k = 0; k < pool.length; k++) totalW += (pool[k].weight || 1);
        var opponents = [];
        for (var n = 0; n < count; n++) {
            var r = Math.random() * totalW, acc = 0, pick = pool[0];
            for (var j = 0; j < pool.length; j++) {
                acc += (pool[j].weight || 1);
                if (r <= acc) { pick = pool[j]; break; }
            }
            var lo = Math.max(pick.minLevel, levelMin), hi = Math.min(pick.maxLevel, levelMax);
            if (hi < lo) hi = lo;
            var lvl = lo + Math.floor(Math.random() * (hi - lo + 1));
            var opponent = { name: pick.name, level: lvl, type: pick.type, spritename: pick.spritename, isMonster: true };
            var parameters = pick.Parameters || pick.parameters || pick['参数'];
            if (customHasParameters(parameters)) opponent.parameters = cloneCustomParameters(parameters);
            opponents.push(opponent);
        }
        return opponents;
    }

    // 怪物卡：本地采样结果直接写 cache + 渲染（不发 AS2，无 pending）。
    function applyMonsterPreview(cardIdx) {
        var squad = _monsterSquad[cardIdx];
        if (!squad) return;
        delete _previewError[cardIdx];
        delete _previewPending[cardIdx];
        _previewCache[cardIdx] = squad.opponents;
        markCardMonster(cardIdx, squad.faction);
        renderCardSummary(cardIdx);
        updateCardStates();
        if (_activeCardIdx === cardIdx) {
            _previewOpponents = squad.opponents;
            renderOpponents(squad.opponents);
            setDetailButtonsBusy(false);
        }
    }

    // 怪物卡视觉标记：加类 + 把「对手阵容」cap 换成势力名（faction=null 还原为 merc 态）。
    function markCardMonster(cardIdx, faction) {
        var cardEl = _cardEls[cardIdx];
        if (!cardEl) return;
        var card = _activeCards[cardIdx];
        var isFallen = !!(card && card.isFallen);
        // 堕落卡建卡即恒紫罗兰；标准卡按本次采样结果开关
        cardEl.classList.toggle('arena-card-monster', !!faction || isFallen);
        if (isFallen) return; // 堕落卡的势力名（rank）+「麾下阵容」cap 已在 buildCards 定好，采样回调不覆盖
        var capEl = cardEl.querySelector('.arena-card-opponents-cap');
        if (capEl) capEl.textContent = faction ? ('⚠ ' + faction) : '对手阵容';
    }

    // 渲染单卡 grid 摘要 row：≤2 名全显，>2 名头 2 + "+N"。
    // 失败态显示 "⚠ ... ↻" 可点击重试。loading 态由 requestPreviewForCard 入口统一写。
    function renderCardSummary(cardIdx) {
        var sumEl = document.getElementById('arena-opp-summary-' + cardIdx);
        if (!sumEl) return;

        if (_previewError[cardIdx]) {
            sumEl.className = 'arena-card-opponents arena-card-opponents-error';
            sumEl.textContent = '⚠ ' + _previewError[cardIdx] + ' ↻';
            sumEl.setAttribute('data-retry-idx', cardIdx);
            sumEl.onclick = onSummaryRetry; // onclick 自动 dedup 重复绑定
            return;
        }

        var opps = _previewCache[cardIdx];
        if (!opps || opps.length === 0) {
            sumEl.className = 'arena-card-opponents arena-card-opponents-loading';
            sumEl.textContent = '抽取中…';
            sumEl.onclick = null;
            return;
        }

        sumEl.className = 'arena-card-opponents';
        sumEl.onclick = null;
        var MAX = 2;
        var parts = [];
        for (var i = 0; i < Math.min(MAX, opps.length); i++) {
            parts.push(opps[i].name + ' Lv' + opps[i].level);
        }
        var text = parts.join(' / ');
        if (opps.length > MAX) {
            text += ' +' + (opps.length - MAX);
        }
        sumEl.textContent = text;
    }

    function onSummaryRetry(e) {
        e.stopPropagation();
        var idx = parseInt(e.currentTarget.getAttribute('data-retry-idx'), 10);
        if (isNaN(idx)) return;
        delete _previewPending[idx]; // 强制重发：清 dedup token 让 requestPreviewForCard 重新发
        delete _cardKind[idx];       // 重抽可重新决定种类（失败的 merc 卡可翻成稳成功的 monster 卡）
        delete _monsterSquad[idx];
        requestPreviewForCard(idx);
    }

    // 非人形怪小队（M2）：无装备/技能，渲简版行（头像 + 名/级 + 非人形标 + 家族注）。
    function renderMonsterOpponents(opponents) {
        var html = '';
        for (var i = 0; i < opponents.length; i++) {
            var opp = opponents[i];
            html += '<div class="arena-opp-row arena-opp-row-monster">';
            html += '<div class="arena-opp-portrait arena-opp-portrait-fallback arena-opp-portrait-monster"></div>';
            html += '<div class="arena-opp-main">';
            html += '<div class="arena-opp-topline">';
            html += '<span class="arena-opp-name">' + escapeHtml(opp.name) + '</span>';
            html += '<span class="arena-opp-level">LV. ' + opp.level + '</span>';
            html += '<span class="arena-opp-monster-tag">非人形</span>';
            html += '</div>';
            html += '<div class="arena-opp-monster-note">' + escapeHtml(String(opp.spritename || '').replace(/^敌人-/, '')) + '</div>';
            html += '</div></div>';
        }
        _detailOpponentsEl.innerHTML = html;
    }

    function renderOpponents(opponents) {
        // 非人形怪小队：走简版渲染（无装备/技能 hover）
        if (opponents && opponents.length && opponents[0] && opponents[0].isMonster) {
            renderMonsterOpponents(opponents);
            return;
        }
        var SLOT_LABELS = {
            6: '头盔', 7: '护身', 8: '护甲', 9: '护腿', 10: '靴子',
            11: '披风', 12: '主武器', 13: '副武器', 14: '副武器2',
            15: '近战', 16: '手雷'
        };
        var html = '';
        for (var i = 0; i < opponents.length; i++) {
            var opp = opponents[i];
            html += '<div class="arena-opp-row">';
            // 对手暂无头像素材 → 剪影占位（与佣兵卡同源），让对手行有"人"的视觉锚点
            html += '<div class="arena-opp-portrait arena-opp-portrait-fallback"></div>';
            html += '<div class="arena-opp-main">';
            html += '<div class="arena-opp-topline">';
            html += '<span class="arena-opp-name">' + escapeHtml(opp.name) + '</span>';
            html += '<span class="arena-opp-level">LV. ' + opp.level + '</span>';
            html += '</div>';
            html += '<div class="arena-opp-equips">';
            // 11 槽固定渲染：有装备显示图标，空槽显示占位
            var equipBySlot = {};
            for (var k = 0; k < opp.equips.length; k++) {
                equipBySlot[opp.equips[k].slot] = opp.equips[k];
            }
            for (var slot = 6; slot <= 16; slot++) {
                var eq = equipBySlot[slot];
                if (eq) {
                    // 注意：raw 是完整编码字符串（含 ##tier #mods），用作 tooltip 查询和 cache key
                    //       icon 是图标资产 key（多装备可共用一张图），displayname 才是用户可见名
                    var raw = eq.raw || eq.name;
                    var iconKey = eq.icon || eq.name;
                    var displayName = eq.displayname || eq.name;
                    var iconHtml = (typeof Icons !== 'undefined' && Icons.html)
                        ? Icons.html(iconKey, '', ' onerror="this.style.display=\'none\'"')
                        : '';
                    iconHtml = iconHtml
                        ? iconHtml
                        : '<span class="arena-equip-fallback">' + escapeHtml(displayName.charAt(0)) + '</span>';
                    // 不设 title 属性：避免浏览器原生 tooltip 与 PanelTooltip 富文本重叠显示
                    html += '<div class="arena-equip-cell"' +
                            ' data-eq-raw="' + escapeAttr(raw) + '"' +
                            ' data-eq-displayname="' + escapeAttr(displayName) + '"' +
                            ' data-eq-icon="' + escapeAttr(iconKey) + '"' +
                            ' data-eq-level="' + eq.level + '">' +
                            iconHtml +
                            '<span class="arena-equip-level">' + eq.level + '</span>' +
                        '</div>';
                } else {
                    // 空槽位保留 title — 没有富文本 tooltip 可覆盖，原生提示就是 fallback
                    html += '<div class="arena-equip-cell arena-equip-empty" title="' + escapeAttr(SLOT_LABELS[slot] || '') + '"></div>';
                }
            }
            html += '</div>'; // equips
            // 技能行：复用战队-佣兵界面技能成果（烘焙图标 + 占位字 + 等级 + hover tooltip）
            html += buildOppSkillsHtml(opp.skills);
            html += '</div>'; // arena-opp-main
            html += '</div>'; // arena-opp-row
        }
        _detailOpponentsEl.innerHTML = html;

        // 装备 hover → tooltip
        var cells = _detailOpponentsEl.querySelectorAll('.arena-equip-cell[data-eq-raw]');
        for (var c = 0; c < cells.length; c++) {
            cells[c].addEventListener('mouseenter', onEquipHover);
            cells[c].addEventListener('mouseleave', onEquipLeave);
            cells[c].addEventListener('mousemove', onEquipMove);
        }
        // 技能 hover → tooltip + 烘焙图加载失败回退占位字
        var skillCells = _detailOpponentsEl.querySelectorAll('.arena-skill-cell[data-skill-name]');
        for (var sc = 0; sc < skillCells.length; sc++) {
            skillCells[sc].addEventListener('mouseenter', onSkillHover);
            skillCells[sc].addEventListener('mouseleave', onSkillLeave);
            skillCells[sc].addEventListener('mousemove', onEquipMove);
        }
        var skillImgs = _detailOpponentsEl.querySelectorAll('.arena-skill-cell-baked .arena-skill-icon');
        for (var si = 0; si < skillImgs.length; si++) {
            skillImgs[si].addEventListener('error', onSkillImgError);
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 对手技能渲染（复用 merc 技能图标范式：Icons.html 烘焙图 → 占位字回退 → 等级 + tooltip）
    // 优雅降级：opp.skills == null（AS2 未回传 / 未重编译）→ 整段省略；空数组 → "无技能"。
    // tooltip 数据走 data-* 属性（避免 HTML 入属性的转义陷阱），hover 时现拼富文本。
    // ════════════════════════════════════════════════════════════════════════════
    function buildOppSkillsHtml(skills) {
        if (skills == null) return '';
        var inner;
        if (!skills.length) {
            inner = '<span class="arena-opp-skills-empty">无技能</span>';
        } else {
            inner = '';
            for (var i = 0; i < skills.length; i++) inner += buildSkillCellHtml(skills[i]);
        }
        return '<div class="arena-opp-skills">' +
                '<span class="arena-opp-skills-cap">技能</span>' +
                '<div class="arena-opp-skills-flow">' + inner + '</div>' +
            '</div>';
    }

    function buildSkillCellHtml(sk) {
        var name = String(sk.name || '');
        var level = sk.level || 1;
        var imgHtml = (name && typeof Icons !== 'undefined' && Icons.html)
            ? Icons.html(name, 'arena-skill-icon')
            : '';
        var cls = 'arena-skill-cell' + (imgHtml ? ' arena-skill-cell-baked' : '');
        return '<div class="' + cls + '"' +
                ' data-skill-name="' + escapeAttr(name) + '"' +
                ' data-skill-level="' + level + '"' +
                ' data-skill-type="' + escapeAttr(String(sk.type || '')) + '"' +
                ' data-skill-trait="' + escapeAttr(String(sk.trait || '')) + '"' +
                ' data-skill-cd="' + (sk.cooldown || 0) + '"' +
                ' data-skill-cost="' + (sk.cost || 0) + '">' +
                '<span class="arena-skill-glyph">' + escapeHtml(String(sk.type || '技').charAt(0)) + '</span>' +
                imgHtml +
                '<span class="arena-skill-level">' + level + '</span>' +
            '</div>';
    }

    function onSkillHover(e) {
        var c = e.currentTarget;
        var type = c.getAttribute('data-skill-type') || '';
        var trait = c.getAttribute('data-skill-trait') || '';
        var html = '<div class="kshop-tt-rich"><div class="kshop-tt-desc">' +
                '<div class="kshop-tt-header"><b>' + escapeHtml(c.getAttribute('data-skill-name') || '') + '</b>' +
                    ' <span class="kshop-tt-dim">Lv.' + (c.getAttribute('data-skill-level') || '1') + '</span></div>' +
                '<div class="kshop-tt-dim">' + escapeHtml(type + (trait ? ' · ' + trait : '')) + '</div>' +
                '<div class="kshop-tt-dim">冷却 ' + (c.getAttribute('data-skill-cd') || '0') + 's · 消耗 ' + (c.getAttribute('data-skill-cost') || '0') + ' MP</div>' +
            '</div></div>';
        PanelTooltip.showAtMouse(html, e);
    }

    function onSkillLeave() {
        PanelTooltip.hide();
    }

    // 烘焙图加载失败：移除 img + 去 baked 类（露出占位字 + 还原虚线样式），与 merc 一致
    function onSkillImgError(e) {
        var img = e.currentTarget;
        var cell = img.parentNode;
        if (cell) cell.classList.remove('arena-skill-cell-baked');
        if (img.parentNode) img.parentNode.removeChild(img);
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 装备 Tooltip — kshop 范式：immediate basic html + async rich fetch + cache
    // ════════════════════════════════════════════════════════════════════════════
    function onEquipHover(e) {
        var cell = e.currentTarget;
        var raw = cell.getAttribute('data-eq-raw');
        var displayName = cell.getAttribute('data-eq-displayname') || raw;
        var iconKey = cell.getAttribute('data-eq-icon') || '';
        var level = Number(cell.getAttribute('data-eq-level'));
        if (!raw) return;
        var key = raw + '|' + level;
        _ttHoverKey = key;

        var cached = _ttCache[key];
        var html = cached
            ? buildRichTooltipHtml(cached, iconKey)
            : buildBasicTooltipHtml(displayName, level, iconKey);
        PanelTooltip.showAtMouse(html, e);
        if (!cached) requestEquipTooltip(raw, level, key, iconKey);
    }

    function onEquipLeave() {
        _ttHoverKey = null;
        PanelTooltip.hide();
    }

    function onEquipMove(e) {
        PanelTooltip.followMouse(e);
    }

    // 基础态（loading）：仅 hover 即时显示，等 Flash 富文本回包后被 buildRichTooltipHtml 覆盖
    // 用 kshop-tt-* 类，与商城 / 情报 panel 视觉一致
    function buildBasicTooltipHtml(displayName, level, iconKey) {
        var iconHtml = PanelTooltip.dynamicIconHtml(iconKey);
        var iconBlock = iconHtml
            ? '<div class="kshop-tt-icon">' + iconHtml + '</div>'
            : '';
        return '<div class="kshop-tt-rich arena-tt-basic">' +
                iconBlock +
                '<div class="kshop-tt-desc">' +
                    '<div class="kshop-tt-header"><b>' + escapeHtml(displayName) + '</b>' +
                        ' <span class="kshop-tt-dim">Lv.' + level + '</span></div>' +
                    '<div class="kshop-tt-loading">加载中…</div>' +
                '</div>' +
            '</div>';
    }

    // 富文本态：TooltipComposer 的 introHTML/descHTML 已含 displayname header，不再外加。
    // arena 显示的是玩家身上的装备（武器/护甲/技能/药剂），AS2 端全部走 applyIntroLayout 的
    // wide 分支（BASE_NUM=200），所以不传 layoutType（buildItemRichHtml 默认 wide）。
    function buildRichTooltipHtml(data, iconKey) {
        return PanelTooltip.buildItemRichHtml({
            iconHtml:  PanelTooltip.dynamicIconHtml(iconKey),
            iconUrl:   PanelTooltip.staticIconUrl(iconKey),
            introHTML: data.introHTML,
            descHTML:  data.descHTML,
            rootClass: 'arena-tt-rich'
        });
    }

    function requestEquipTooltip(raw, level, key, iconKey) {
        var reqId = 'arena_tt_' + (++_reqSeq) + '_' + _session;
        _pendingReq[reqId] = function(resp) {
            if (!resp.success) return;
            _ttCache[key] = {
                descHTML: resp.descHTML || '',
                introHTML: resp.introHTML || '',
                displayname: resp.displayname || '',
                itemName: resp.itemName || raw
            };
            // 仍 hover 在同一 cell 才更新
            if (_ttHoverKey === key && PanelTooltip.isVisible() && Panels.isOpen()) {
                PanelTooltip.updateContent(buildRichTooltipHtml(_ttCache[key], iconKey));
            }
        };
        Bridge.send({
            type: 'panel',
            panel: 'arena',
            cmd: 'equip_tooltip',
            callId: reqId,
            raw: raw,
            level: level
        });
    }

    // ════════════════════════════════════════════════════════════════════════════
    // UI 更新
    // ════════════════════════════════════════════════════════════════════════════
    function updateMoneyDisplay(money) {
        if (money == null) {
            _moneyEl.textContent = '--';
            return;
        }
        _moneyEl.textContent = formatMoney(money);
    }

    // 卡片状态机：一张卡有 enter 按钮 + detail 按钮 + 整卡视觉灰类，三者 disable 条件不同
    //   - enter 按钮：busy / 钱不够 / preview 未到 任一即 disable
    //   - detail 按钮：仅 busy 时 disable（钱不够也允许查看对手装备）
    //   - 整卡灰类：仅按 money 判断（视觉降权，不直接干预按钮）
    function updateCardStates() {
        var money = (_snapshot && _snapshot.money != null) ? _snapshot.money : null;
        for (var i = 0; i < _activeCards.length; i++) {
            if (_activeCards[i].isCustom) {
                refreshCustomMatchCard();
                continue;
            }
            var deposit = _activeCards[i].deposit;
            var moneyOk = (money == null) || (money >= deposit); // snapshot 未到先全亮
            var hasPreview = !!_previewCache[i];
            setCardEnterEnabled(i, !_busy && moneyOk && hasPreview);
            setCardDetailEnabled(i, !_busy);
            setCardVisualDisabled(i, money != null && money < deposit);
        }
    }

    function setCardEnterEnabled(index, enabled) {
        var cardEl = _cardEls[index];
        if (!cardEl) return;
        var btn = cardEl.querySelector('.arena-card-btn-enter');
        if (!btn) return;
        btn.disabled = !enabled;
    }

    function setCardDetailEnabled(index, enabled) {
        var cardEl = _cardEls[index];
        if (!cardEl) return;
        var btn = cardEl.querySelector('.arena-card-btn-detail');
        if (!btn) return;
        btn.disabled = !enabled;
    }

    function setCardVisualDisabled(index, disabled) {
        var cardEl = _cardEls[index];
        if (!cardEl) return;
        cardEl.classList.toggle('arena-card-disabled', disabled);
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 工具
    // ════════════════════════════════════════════════════════════════════════════
    function showToast(text) {
        var toastEl = _el.querySelector('#arena-toast');
        if (!toastEl) return;
        toastEl.textContent = text;
        toastEl.style.display = 'block';
        toastEl.classList.add('arena-toast-visible');
        clearTimeout(_toastTimer);
        _toastTimer = setTimeout(hideToast, 3000);
    }

    function hideToast() {
        var toastEl = _el.querySelector('#arena-toast');
        if (!toastEl) return;
        toastEl.classList.remove('arena-toast-visible');
        toastEl.style.display = 'none';
    }

    function formatMoney(n) {
        if (typeof n !== 'number') return String(n);
        return n.toLocaleString('zh-CN');
    }

    // 难度档位：按对手最高等级映射「热度」tier（1 安全 → 6 致命）+ 中文段位名。
    // tier 驱动卡片 .arena-card-d{tier} 类（CSS 决定 --d-color 顶部色条/标签色）。
    // 8 张卡的 levelMax: 5/10/15/15/20/20/40/60 → 新兵/老兵/精锐×2/王牌×2/传奇/神话。
    function difficultyOf(card) {
        var lm = card.levelMax;
        if (lm <= 5)  return { tier: 1, label: '新兵' };
        if (lm <= 10) return { tier: 2, label: '老兵' };
        if (lm <= 15) return { tier: 3, label: '精锐' };
        if (lm <= 20) return { tier: 4, label: '王牌' };
        if (lm <= 40) return { tier: 5, label: '传奇' };
        return { tier: 6, label: '神话' };
    }

    function escapeHtml(text) {
        var div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    function escapeAttr(text) {
        return String(text).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 调试接口（harness / QA 用）
    // ════════════════════════════════════════════════════════════════════════════
    function _debugGetState() {
        return {
            session: _session,
            busy: _busy,
            snapshot: _snapshot,
            activeCardIdx: _activeCardIdx,
            previewOpponents: _previewOpponents,
            activeMode: _activeMode,
            knownEnemyCount: _knownEnemyCount,
            pendingCount: Object.keys(_pendingReq).length,
            previewCacheCount: Object.keys(_previewCache).length,
            previewPendingCount: Object.keys(_previewPending).length,
            previewErrorCount: Object.keys(_previewError).length,
            cardKind: _cardKind,
            monsterSquad: _monsterSquad,
            customMatch: _customMatch,
            customEditor: _customEditor,
            customSelectedSide: _customSelectedSide,
            customEditorPage: _customEditorPage,
            customParamEditor: _customParamEditor,
            customSavedRosters: getCustomSavedRosters().slice(),
            customConfirmOpen: _customConfirmOpen,
            customRun: _customRun,
            customResult: _customResult
        };
    }

    // 暴露给 harness QA
    if (typeof window !== 'undefined') {
        window.ArenaPanel = {
            getState: _debugGetState,
            getCards: function() { return _activeCards.slice(); },
            // 测试/截图注入：设怪物混入概率（1=全怪物，0=全 merc）。需 window.ArenaMetaRosters 已载。
            setMixChance: function(p) { _mixChance = Number(p); },
            // 测试注入：模拟 AS2 snapshot 的 killStats.byType spritename 列表。
            setKnownEnemies: function(list) {
                setKnownEnemies(list);
                refreshModeTabs();
            },
            // 测试/截图：切到堕落模式（需 rosters 已载）。返回切后卡片数。
            switchMode: function(mode) {
                if (!modeAvailable(mode)) return 0;
                rebuildForMode(mode);
                if (_snapshot) batchRequestPreview();
                return _activeCards.length;
            }
        };
    }
})();
