(function() {
    'use strict';

    // ════════════════════════════════════════════════════════════════════════════
    // 标准模式档位。每次 panel open / 全部重抽会按 countMin-countMax
    // 结算本 session 的固定人数、经济与 expr；preview / enter 全程复用这份卡片。
    // ════════════════════════════════════════════════════════════════════════════
    var STANDARD_OPPONENT_CAP = 4; // Flash 战斗承压上限：标准 / 隐藏警报卡的佣兵等效人数均不超过 4
    var STANDARD_ROLE_COUNTS = { merc: 7, monster: 2, mixed: 1 }; // 公开 10 卡固定配比，位置每 session 随机
    var STANDARD_TIERS = [
        { levelMin: 1,  levelMax: 5,   countMin: 1, countMax: 1 },
        { levelMin: 5,  levelMax: 10,  countMin: 1, countMax: 2 },
        { levelMin: 10, levelMax: 15,  countMin: 2, countMax: 3 },
        { levelMin: 15, levelMax: 20,  countMin: 2, countMax: 4 },
        { levelMin: 20, levelMax: 30,  countMin: 3, countMax: 4 },
        { levelMin: 30, levelMax: 35,  countMin: 3, countMax: 4 },
        { levelMin: 35, levelMax: 40,  countMin: 4, countMax: 4 },
        { levelMin: 40, levelMax: 50,  countMin: 4, countMax: 4 },
        { levelMin: 50, levelMax: 60,  countMin: 4, countMax: 4 },
        { levelMin: 60, levelMax: 100, countMin: 4, countMax: 4 }
    ];
    var STANDARD_HIDDEN_CHALLENGES = [
        { offset: 1, multiplier: 1.5, label: '死线警报 I', countMin: 1, countMax: 3, requiresMixedRoster: true },
        { offset: 2, multiplier: 2.0, label: '死线警报 II', countMin: 4, countMax: 4, requiresMixedRoster: true }
    ];
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

    var CUSTOM_MATCH_FALLBACK_CODE =
        'CF7ARENA:v1;mode=mvm;seed=90210;blue=u44@30x2,u48@30x1;red=u164@60x1,u11@30x1';
    var CUSTOM_PVE_FALLBACK_CODE =
        'CF7ARENA:v1;mode=pve;seed=3307;enemy=u44@30x1;player=current';
    var CUSTOM_BROWSER_BATCH_SIZE = 80;
    var CUSTOM_SAVED_ROSTERS_KEY = 'cf7.arena.custom.savedRosters.v1';
    var CUSTOM_SAVED_ROSTER_LIMIT = 24;
    var CUSTOM_TIMEOUT_FPS = 30;
    var CUSTOM_SPAWN_DISTANCE_PRESETS = [
        { label: '近', value: 520 },
        { label: '标准', value: 650 },
        { label: '远', value: 820 }
    ];
    var CUSTOM_TIMEOUT_PRESETS = [
        { label: '60秒', value: 1800 },
        { label: '120秒', value: 3600 },
        { label: '180秒', value: 5400 },
        { label: '300秒', value: 9000 }
    ];
    var CUSTOM_FORMATION_OPTIONS = [
        { id: 'line', label: '横列' },
        { id: 'column', label: '纵队' },
        { id: 'wedge', label: '楔形' },
        { id: 'shield', label: '前盾后排' },
        { id: 'grid', label: '网格散点' }
    ];
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
        // 采样怪物 roster（复用 Phase1 的 roster 入场通路，AS2 零改动——合成 expr 只为过校验）。
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
    var HIDDEN_MIXED_TEAM_MAX_UNITS = 12; // 单个怪物组展开上限；AS2 运行态按 12 活体上限分批补刷。

    // ════════════════════════════════════════════════════════════════════════════
    // 状态
    // ════════════════════════════════════════════════════════════════════════════
    var _activeMode = 'standard';
    var _activeCards = []; // 当前模式的卡片集（标准=会话生成；堕落/爬升=派生；定制=入口卡）
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
    // batch preview 缓存：panel open 时并发抽当前卡片集，结果按 cardIdx 落 cache。
    // grid 摘要 + detail 视图共用同一份 cache。WYSIWYG: 用户在 grid 上看到的对手 = enter 时实际打到的人。
    // AS2 端有镜像缓存 _root._arenaLineupCache（同 cardIdx 索引），handleEnter 按 cardIndex 取出 commit。
    var _previewCache = {};       // cardIdx → opponents[]（成功时填入）
    var _previewPending = {};     // cardIdx → reqId（dedup：pending 中不重发）
    var _previewError = {};       // cardIdx → error string（失败 → 摘要显示"加载失败 ↻"）
    // ── 元战队 / 混编 roster 混入（M2 / 堕落模式雏形）──
    // 每卡每次抽取先决定种类（merc / monster / mixed）。roster 类走 web 本地采样（无 AS2 preview 往返），
    // enter 时把采样小队作为 roster 下发 AS2（commitRoster 生成兵种阵容）。
    // 数据源 window.ArenaMetaRosters（arena-meta-rosters.js，由 derive-arena-meta-teams.js 派生）；
    // factions 用于按势力拆兵种单体兜底采样，teams 用于怪物组 / 混编优先复用真实关卡组合。
    // 未载入（如 QA harness）时 sampleMonsterSquad 恒返回 null → 全卡 merc，旧行为不变。
    var _cardKind = {};       // cardIdx → 'merc' | 'monster' | 'mixed'
    var _monsterSquad = {};   // cardIdx → { faction, opponents:[{name,level,type,spritename,isMonster:true}] }
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
    var _customSelectOpen = null;

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
                    '<button class="arena-reroll-all" type="button" id="arena-reroll-all" title="重新抽取全部标准卡人数与对手" data-audio-cue="confirm">↻ 全部重抽</button>' +
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
        _el.querySelector('#arena-reroll-all').addEventListener('click', onRerollAll);
        _el.querySelector('.arena-detail-back').addEventListener('click', backToGrid);
        _customResultViewEl.addEventListener('click', onCustomResultClick);
        _customEditorViewEl.addEventListener('click', onCustomWorkbenchClick);
        _customEditorViewEl.addEventListener('change', onCustomWorkbenchChange);
        _customEditorViewEl.addEventListener('input', onCustomEditorInput);
        _customEditorViewEl.addEventListener('keydown', onCustomSelectKeydown);
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
        // 卡片多于单屏（>8）→ 切顶部对齐的滚动布局；否则铺满单屏。
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
            var isHidden = !!card.isHiddenChallenge;
            var cardEl = document.createElement('div');
            // d{1..6} 类驱动 --d-color 难度热度（CSS .arena-card-d* → 顶部色条 + 难度标签色）。
            // 堕落卡恒 roster 怪物队 → 建卡即上 arena-card-monster（紫罗兰），不等采样回调。
            cardEl.className = 'arena-card arena-card-d' + diff.tier +
                (isFallen ? ' arena-card-monster' : '') +
                (isHidden ? ' arena-card-hidden' : '');
            cardEl.dataset.index = i;
            // 标准卡 rank = 段位号；堕落卡 rank = 势力名（卡片身份）+ 阵容 cap 改「麾下阵容」
            var rankHtml = isFallen
                ? '<span class="arena-card-rank arena-card-rank-faction">' + escapeHtml(card.faction) + '</span>'
                : '<span class="arena-card-rank">' + escapeHtml(isHidden ? card.hiddenLabel : ('段位 ' + card.index)) + '</span>';
            var oppCapText = isHidden ? '配置保密' : (isFallen ? '麾下阵容' : '对手阵容');
            var diffText = isHidden ? card.hiddenLabel : diff.label;
            var opponentText = isHidden ? '？？' : ('×' + card.opponentCount);
            var levelText = isHidden ? '？？' : (card.levelMin + '–' + card.levelMax);
            var detailDisabledAttr = isHidden ? ' disabled aria-disabled="true"' : '';
            var detailTitle = isHidden ? '隐藏警报不显示配置' : '查看对手详情';
            var extraMeta = isHidden
                ? '<span class="arena-prize-mult">收益 ×' + card.economyMultiplier + '</span>'
                : '';
            cardEl.innerHTML =
                '<div class="arena-card-frame"></div>' +
                '<div class="arena-card-header">' +
                    rankHtml +
                    '<span class="arena-card-icon">⚔</span>' +
                    '<span class="arena-card-diff">' + diffText + '</span>' +
                '</div>' +
                '<div class="arena-card-body">' +
                    '<div class="arena-card-stats">' +
                        '<div class="arena-stat">' +
                            '<span class="arena-stat-label">对手</span>' +
                            '<span class="arena-stat-value">' + opponentText + '</span>' +
                        '</div>' +
                        '<div class="arena-stat">' +
                            '<span class="arena-stat-label">等级</span>' +
                            '<span class="arena-stat-value">' + levelText + '</span>' +
                        '</div>' +
                    '</div>' +
                    // 奖金主视觉（金色大字）/ 押金次视觉，回应"押注挑战"的风险-回报心智模型
                    '<div class="arena-card-prize">' +
                        '<div class="arena-prize-main">' +
                            '<span class="arena-prize-label">奖金</span>' +
                            '<span class="arena-prize-value">' + formatMoney(card.reward) + '</span>' +
                            extraMeta +
                        '</div>' +
                        '<div class="arena-prize-deposit">押金 ' + formatMoney(card.deposit) + '</div>' +
                    '</div>' +
                    // 对手摘要 row：snapshot 回包后 batchRequestPreview 触发全卡并发抽签，
                    // 单卡回包后 renderCardSummary(cardIdx) 写入下方 span。
                    '<div class="arena-card-opponents-row">' +
                        '<span class="arena-card-opponents-cap">' + oppCapText + '</span>' +
                        '<span class="arena-card-opponents arena-card-opponents-loading" id="arena-opp-summary-' + i + '">抽取中…</span>' +
                    '</div>' +
                '</div>' +
                // 主+次按钮：主 ⚔ 开始挑战（grid 直入战场，无需进 detail）；次 🔍 查看对手（进 detail 看装备 / 换一批）
                '<div class="arena-card-actions">' +
                    '<button class="arena-card-btn-enter" type="button" data-index="' + i + '" data-audio-cue="confirm">⚔ 开始挑战</button>' +
                    '<button class="arena-card-btn-detail" type="button" data-index="' + i + '" data-audio-cue="confirm" title="' + detailTitle + '"' + detailDisabledAttr + '>🔍</button>' +
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
                '<div class="arena-custom-battle-summary" id="arena-custom-battle-summary">' +
                    '<div class="arena-custom-battle-summary-head">' +
                        '<div class="arena-custom-section-title">战场参数</div>' +
                        '<button class="arena-custom-btn" type="button" id="arena-custom-battle-edit" data-custom-editor-action="to-battle" data-audio-cue="confirm">编辑战场</button>' +
                    '</div>' +
                    '<div class="arena-custom-battle-summary-grid">' +
                        '<span><em>开局距离</em><b id="arena-custom-battle-summary-distance">--</b></span>' +
                        '<span><em>战斗时长</em><b id="arena-custom-battle-summary-timeout">--</b></span>' +
                        '<span><em>阵型</em><b id="arena-custom-battle-summary-formation">--</b></span>' +
                        '<span><em>间距</em><b id="arena-custom-battle-summary-spacing">--</b></span>' +
                    '</div>' +
                '</div>' +
                '<div class="arena-custom-side-configs">' +
                    '<div class="arena-custom-side-config-card arena-custom-side-config-blue" id="arena-custom-config-blue"></div>' +
                    '<div class="arena-custom-side-config-card arena-custom-side-config-red" id="arena-custom-config-red"></div>' +
                '</div>' +
            '</div>' +
            '<div class="arena-custom-editor-page arena-custom-battle-page" data-custom-editor-page="battle" hidden>' +
                '<div class="arena-custom-battle-editor-head">' +
                    '<div class="arena-custom-side-editor-title-block">' +
                        '<div class="arena-custom-editor-kicker">战场参数</div>' +
                        '<div class="arena-custom-editor-title">调整开局与阵型</div>' +
                        '<div class="arena-custom-editor-meta" id="arena-custom-battle-editor-meta">--</div>' +
                    '</div>' +
                    '<div class="arena-custom-battle-editor-actions">' +
                        '<button class="arena-custom-btn" type="button" data-custom-editor-action="to-config" data-audio-cue="cancel">返回总览</button>' +
                        '<button class="arena-card-btn-enter" type="button" data-custom-editor-action="done" data-audio-cue="confirm">完成</button>' +
                    '</div>' +
                '</div>' +
                '<div class="arena-custom-battle-params arena-custom-battle-params-editor" id="arena-custom-battle-params">' +
                    '<div class="arena-custom-battle-param-grid">' +
                        '<div class="arena-custom-battle-param-card" data-custom-battle-card="spawnDistance">' +
                            '<div class="arena-custom-battle-param-head"><span>开局距离</span><b id="arena-custom-spawn-distance-value">--</b></div>' +
                            '<div class="arena-custom-preset-row" id="arena-custom-spawn-distance-presets"></div>' +
                            '<input class="arena-custom-range" type="range" id="arena-custom-spawn-distance" data-custom-battle-field="spawnDistance">' +
                        '</div>' +
                        '<div class="arena-custom-battle-param-card" data-custom-battle-card="timeoutFrames">' +
                            '<div class="arena-custom-battle-param-head"><span>战斗时长</span><b id="arena-custom-timeout-value">--</b></div>' +
                            '<div class="arena-custom-preset-row" id="arena-custom-timeout-presets"></div>' +
                            '<input class="arena-custom-range" type="range" id="arena-custom-timeout" data-custom-battle-field="timeoutSeconds">' +
                        '</div>' +
                        '<div class="arena-custom-battle-param-card arena-custom-battle-param-card-wide">' +
                            '<div class="arena-custom-battle-param-head"><span>阵型</span><b id="arena-custom-formation-summary">--</b></div>' +
                            '<div class="arena-custom-formation-editors">' +
                                '<div class="arena-custom-formation-side" data-custom-formation-panel="blue">' +
                                    '<div class="arena-custom-formation-side-title" id="arena-custom-blue-formation-title">蓝方</div>' +
                                    '<div class="arena-custom-formation-options" id="arena-custom-blue-formation-options"></div>' +
                                    '<div class="arena-custom-formation-legend" id="arena-custom-blue-formation-legend"></div>' +
                                '</div>' +
                                '<div class="arena-custom-formation-side" data-custom-formation-panel="red">' +
                                    '<div class="arena-custom-formation-side-title" id="arena-custom-red-formation-title">红方</div>' +
                                    '<div class="arena-custom-formation-options" id="arena-custom-red-formation-options"></div>' +
                                    '<div class="arena-custom-formation-legend" id="arena-custom-red-formation-legend"></div>' +
                                '</div>' +
                            '</div>' +
                            '<div class="arena-custom-spacing-row">' +
                                '<span>间距</span>' +
                                '<input class="arena-custom-range" type="range" id="arena-custom-formation-spacing" data-custom-battle-field="formationSpacing">' +
                                '<b id="arena-custom-formation-spacing-value">--</b>' +
                            '</div>' +
                        '</div>' +
                    '</div>' +
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

    function resetCardRuntimeState() {
        _previewCache = {};
        _previewPending = {};
        _previewError = {};
        _cardKind = {};
        _monsterSquad = {};
        _activeCardIdx = -1;
        _previewOpponents = null;
    }

    function buildStandardSessionCards() {
        var cards = [];
        for (var i = 0; i < STANDARD_TIERS.length; i++) {
            cards.push(buildStandardCard(STANDARD_TIERS[i], i + 1, null));
        }
        assignStandardPublicRoles(cards);

        var playerTier = findPlayerTierIndex(getSnapshotPlayerLevel());
        var lastTierIndex = STANDARD_TIERS.length - 1;
        for (var h = 0; h < STANDARD_HIDDEN_CHALLENGES.length; h++) {
            var meta = STANDARD_HIDDEN_CHALLENGES[h];
            var targetIndex = Math.min(playerTier + meta.offset, lastTierIndex);
            cards.push(buildStandardCard(STANDARD_TIERS[targetIndex], cards.length + 1, meta));
        }
        return cards;
    }

    function assignStandardPublicRoles(cards) {
        var publicIdx = [];
        for (var i = 0; i < STANDARD_TIERS.length && i < cards.length; i++) {
            cards[i].standardRole = 'merc';
            publicIdx.push(i);
        }
        if (!publicIdx.length) return;

        var mixedCandidates = [];
        for (var m = 0; m < publicIdx.length; m++) {
            var card = cards[publicIdx[m]];
            if (hasMixedTeamForBand(card.levelMin, card.levelMax)) mixedCandidates.push(publicIdx[m]);
        }
        if (!mixedCandidates.length) mixedCandidates = publicIdx.slice(1);
        if (!mixedCandidates.length) mixedCandidates = publicIdx.slice();

        var used = {};
        var mixedIdx = pickRandomIndex(mixedCandidates, used);
        if (mixedIdx >= 0) {
            cards[mixedIdx].standardRole = 'mixed';
            used[mixedIdx] = true;
        }

        var monsterCandidates = [];
        for (var r = 0; r < publicIdx.length; r++) {
            var monsterCard = cards[publicIdx[r]];
            if (hasMonsterTeamForBand(monsterCard.levelMin, monsterCard.levelMax)) monsterCandidates.push(publicIdx[r]);
        }
        if (!monsterCandidates.length) monsterCandidates = publicIdx.slice();

        for (var n = 0; n < STANDARD_ROLE_COUNTS.monster; n++) {
            var monsterIdx = pickRandomIndex(monsterCandidates, used);
            if (monsterIdx < 0) break;
            cards[monsterIdx].standardRole = 'monster';
            used[monsterIdx] = true;
        }
    }

    function pickRandomIndex(candidates, used) {
        var pool = [];
        for (var i = 0; i < candidates.length; i++) {
            if (!used[candidates[i]]) pool.push(candidates[i]);
        }
        if (!pool.length) return -1;
        return pool[Math.floor(Math.random() * pool.length)];
    }

    function hasMixedTeamForBand(levelMin, levelMax) {
        var teams = (typeof window !== 'undefined' && window.ArenaMetaRosters && window.ArenaMetaRosters.teams)
            ? window.ArenaMetaRosters.teams : null;
        if (!teams || !teams.length) return false;
        for (var i = 0; i < teams.length; i++) {
            var team = teams[i];
            if (!team || team.levelMax < levelMin || team.levelMin > levelMax) continue;
            if (teamHasHumanoidAndNonHuman(team)) return true;
        }
        return false;
    }

    function hasMonsterTeamForBand(levelMin, levelMax) {
        var teams = (typeof window !== 'undefined' && window.ArenaMetaRosters && window.ArenaMetaRosters.teams)
            ? window.ArenaMetaRosters.teams : null;
        if (!teams || !teams.length) return false;
        for (var i = 0; i < teams.length; i++) {
            var team = teams[i];
            if (!team || team.unitCount < 2 || team.unitCount > HIDDEN_MIXED_TEAM_MAX_UNITS) continue;
            if (team.levelMax < levelMin || team.levelMin > levelMax) continue;
            if (teamHasOnlyNonHuman(team)) return true;
        }
        return false;
    }

    function buildStandardCard(tier, index, hiddenMeta) {
        var rawCountMin = hiddenMeta && hiddenMeta.countMin != null ? hiddenMeta.countMin : tier.countMin;
        var rawCountMax = hiddenMeta && hiddenMeta.countMax != null ? hiddenMeta.countMax : tier.countMax;
        var countMin = Math.min(rawCountMin, STANDARD_OPPONENT_CAP);
        var countMax = Math.min(rawCountMax, STANDARD_OPPONENT_CAP);
        var count = randomInt(countMin, countMax);
        if (hiddenMeta && hiddenMeta.requiresMixedRoster && count < 2 && countMax >= 2) count = 2;
        var multiplier = hiddenMeta ? hiddenMeta.multiplier : 1;
        var reward = roundTo(standardReward(tier, count) * multiplier, 1000);
        var deposit = Math.max(500, roundTo(reward / 2, 500));
        return {
            id: hiddenMeta ? ('arena-hidden-' + hiddenMeta.offset) : ('arena-' + index),
            index: index,
            name: 'DEATH MATCH角斗场',
            opponentCount: count,
            countMin: countMin,
            countMax: countMax,
            levelMin: tier.levelMin,
            levelMax: tier.levelMax,
            deposit: deposit,
            reward: reward,
            economyMultiplier: multiplier,
            hiddenLabel: hiddenMeta ? hiddenMeta.label : '',
            isHiddenChallenge: !!hiddenMeta,
            requiresMixedRoster: !!(hiddenMeta && hiddenMeta.requiresMixedRoster),
            expr: '#0@' + tier.levelMin + '-' + tier.levelMax + '%' + count
        };
    }

    function standardReward(tier, count) {
        var levelBase = Math.max(1, Number(tier.levelMin) || 1);
        var perLevel = levelBase >= 40 ? 1250 : 1000;
        return roundTo(count * levelBase * perLevel, 1000);
    }

    function randomInt(lo, hi) {
        lo = Math.round(lo);
        hi = Math.round(hi);
        if (hi < lo) hi = lo;
        return lo + Math.floor(Math.random() * (hi - lo + 1));
    }

    function getSnapshotPlayerLevel() {
        var level = _snapshot ? Number(_snapshot.playerLevel) : NaN;
        return (!isNaN(level) && level > 0) ? level : 1;
    }

    function findPlayerTierIndex(level) {
        level = Math.max(1, Math.floor(Number(level) || 1));
        for (var i = 0; i < STANDARD_TIERS.length; i++) {
            var tier = STANDARD_TIERS[i];
            var isLast = i === STANDARD_TIERS.length - 1;
            if (level >= tier.levelMin && (level < tier.levelMax || isLast)) return i;
        }
        return STANDARD_TIERS.length - 1;
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
                     : buildStandardSessionCards();
        // 切模式让所有卡 index 重新映射 → 旧 preview/kind/squad 缓存全部作废，避免跨模式串卡
        resetCardRuntimeState();
        // tab active 态
        var tabs = _el ? _el.querySelectorAll('.arena-mode-tab') : [];
        for (var i = 0; i < tabs.length; i++) {
            tabs[i].classList.toggle('arena-mode-tab-active', tabs[i].getAttribute('data-mode') === mode);
        }
        updateRerollAllButton();
        buildCards();       // 重建 grid DOM（_activeCards 驱动）+ 重挂卡片按钮监听 + 摘要回 loading 态
        if (mode === 'custom') refreshCustomMatchCard();
        showGridView();
        updateCardStates();
    }

    function updateRerollAllButton() {
        if (!_el) return;
        var btn = _el.querySelector('#arena-reroll-all');
        if (!btn) return;
        var hidden = _activeMode === 'custom';
        btn.hidden = hidden;
        btn.disabled = hidden || _busy;
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
        resetCardRuntimeState();
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
        _customSelectOpen = null;
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
        _customSelectOpen = null;
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
        closeCustomSelectMenus();
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
        closeCustomSelectMenus();
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
            spawnDistance: parsed.spawnDistance || ArenaCustomMatchCode.DEFAULT_SPAWN_DISTANCE,
            blueFormation: parsed.blueFormation || ArenaCustomMatchCode.DEFAULT_FORMATION,
            redFormation: parsed.redFormation || ArenaCustomMatchCode.DEFAULT_FORMATION,
            formationSpacing: parsed.formationSpacing || ArenaCustomMatchCode.DEFAULT_FORMATION_SPACING,
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
                spawnDistance: ArenaCustomMatchCode.DEFAULT_SPAWN_DISTANCE,
                blueFormation: ArenaCustomMatchCode.DEFAULT_FORMATION,
                redFormation: ArenaCustomMatchCode.DEFAULT_FORMATION,
                formationSpacing: ArenaCustomMatchCode.DEFAULT_FORMATION_SPACING,
                blue: [],
                red: [],
                query: '',
                filter: 'all',
                expandedFactions: {},
                unitVisibleRows: CUSTOM_BROWSER_BATCH_SIZE,
                unitScrollableRows: 0
            };
        }
        sanitizeCustomBattleParams(_customEditor);
        return _customEditor;
    }

    function customUndoOptions() {
        return {
            defaultTimeoutFrames: ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
            defaultSpawnDistance: ArenaCustomMatchCode.DEFAULT_SPAWN_DISTANCE,
            defaultFormation: ArenaCustomMatchCode.DEFAULT_FORMATION,
            defaultFormationSpacing: ArenaCustomMatchCode.DEFAULT_FORMATION_SPACING,
            browserBatchSize: CUSTOM_BROWSER_BATCH_SIZE
        };
    }

    function sanitizeCustomBattleParams(editor) {
        if (!editor) return;
        editor.timeoutFrames = clampInt(
            Number(editor.timeoutFrames) || ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
            30 * CUSTOM_TIMEOUT_FPS,
            600 * CUSTOM_TIMEOUT_FPS
        );
        editor.spawnDistance = clampInt(
            Number(editor.spawnDistance) || ArenaCustomMatchCode.DEFAULT_SPAWN_DISTANCE,
            ArenaCustomMatchCode.MIN_SPAWN_DISTANCE,
            ArenaCustomMatchCode.MAX_SPAWN_DISTANCE
        );
        editor.formationSpacing = clampInt(
            Number(editor.formationSpacing) || ArenaCustomMatchCode.DEFAULT_FORMATION_SPACING,
            ArenaCustomMatchCode.MIN_FORMATION_SPACING,
            ArenaCustomMatchCode.MAX_FORMATION_SPACING
        );
        editor.blueFormation = normalizeCustomFormation(editor.blueFormation);
        editor.redFormation = normalizeCustomFormation(editor.redFormation);
    }

    function normalizeCustomFormation(value) {
        var id = String(value || ArenaCustomMatchCode.DEFAULT_FORMATION || 'line').toLowerCase();
        var formations = ArenaCustomMatchCode.FORMATIONS || {};
        return formations[id] ? id : (ArenaCustomMatchCode.DEFAULT_FORMATION || 'line');
    }

    function customFormationLabel(id) {
        if (ArenaCustomMatchCode && ArenaCustomMatchCode.formationLabel) {
            return ArenaCustomMatchCode.formationLabel(id);
        }
        for (var i = 0; i < CUSTOM_FORMATION_OPTIONS.length; i++) {
            if (CUSTOM_FORMATION_OPTIONS[i].id === id) return CUSTOM_FORMATION_OPTIONS[i].label;
        }
        return id || '--';
    }

    function customTimeoutSeconds(editor) {
        editor = editor || ensureCustomEditorState();
        return clampInt(Math.round((Number(editor.timeoutFrames) || ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES) / CUSTOM_TIMEOUT_FPS), 30, 600);
    }

    function formatCustomBattleParams(parsed) {
        if (!parsed) return '--';
        return '距离 ' + parsed.spawnDistance +
            ' · 时长 ' + Math.round(parsed.timeoutFrames / CUSTOM_TIMEOUT_FPS) + '秒' +
            ' · ' + formatCustomFormationPair(parsed);
    }

    function formatCustomFormationPair(source) {
        var isPve = source && source.mode === 'pve';
        return (isPve ? '玩家 ' : '蓝 ') + customFormationLabel(source ? source.blueFormation : null) +
            ' / ' + (isPve ? '怪物 ' : '红 ') + customFormationLabel(source ? source.redFormation : null);
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

    function renderCustomBattleParams() {
        if (!_el) return;
        var editor = ensureCustomEditorState();
        sanitizeCustomBattleParams(editor);

        var summaryDistance = _el.querySelector('#arena-custom-battle-summary-distance');
        var summaryTimeout = _el.querySelector('#arena-custom-battle-summary-timeout');
        var summaryFormation = _el.querySelector('#arena-custom-battle-summary-formation');
        var summarySpacing = _el.querySelector('#arena-custom-battle-summary-spacing');
        var editorMeta = _el.querySelector('#arena-custom-battle-editor-meta');
        if (summaryDistance) summaryDistance.textContent = editor.spawnDistance + ' px';
        if (summaryTimeout) summaryTimeout.textContent = customTimeoutSeconds(editor) + ' 秒';
        if (summaryFormation) summaryFormation.textContent = formatCustomFormationPair(editor);
        if (summarySpacing) summarySpacing.textContent = editor.formationSpacing + ' px';
        if (editorMeta) editorMeta.textContent = formatCustomBattleParams(editor);

        var distance = _el.querySelector('#arena-custom-spawn-distance');
        var distanceValue = _el.querySelector('#arena-custom-spawn-distance-value');
        if (distance) {
            distance.min = ArenaCustomMatchCode.MIN_SPAWN_DISTANCE;
            distance.max = ArenaCustomMatchCode.MAX_SPAWN_DISTANCE;
            distance.step = 10;
            distance.value = editor.spawnDistance;
        }
        if (distanceValue) distanceValue.textContent = editor.spawnDistance + ' px';
        renderCustomPresetButtons('#arena-custom-spawn-distance-presets', 'spawnDistance', CUSTOM_SPAWN_DISTANCE_PRESETS, editor.spawnDistance);

        var timeoutSeconds = customTimeoutSeconds(editor);
        var timeout = _el.querySelector('#arena-custom-timeout');
        var timeoutValue = _el.querySelector('#arena-custom-timeout-value');
        if (timeout) {
            timeout.min = 30;
            timeout.max = 600;
            timeout.step = 10;
            timeout.value = timeoutSeconds;
        }
        if (timeoutValue) timeoutValue.textContent = timeoutSeconds + ' 秒';
        renderCustomPresetButtons('#arena-custom-timeout-presets', 'timeoutFrames', CUSTOM_TIMEOUT_PRESETS, editor.timeoutFrames);

        renderCustomFormationButtons('blue', editor.blueFormation);
        renderCustomFormationButtons('red', editor.redFormation);
        renderCustomFormationLegend('blue', editor.blueFormation);
        renderCustomFormationLegend('red', editor.redFormation);

        var blueTitle = _el.querySelector('#arena-custom-blue-formation-title');
        var redTitle = _el.querySelector('#arena-custom-red-formation-title');
        if (blueTitle) blueTitle.textContent = editor.mode === 'pve' ? '玩家' : '蓝方';
        if (redTitle) redTitle.textContent = editor.mode === 'pve' ? '怪物' : '红方';
        var summary = _el.querySelector('#arena-custom-formation-summary');
        if (summary) summary.textContent = customFormationLabel(editor.blueFormation) + ' / ' + customFormationLabel(editor.redFormation);

        var spacing = _el.querySelector('#arena-custom-formation-spacing');
        var spacingValue = _el.querySelector('#arena-custom-formation-spacing-value');
        if (spacing) {
            spacing.min = ArenaCustomMatchCode.MIN_FORMATION_SPACING;
            spacing.max = ArenaCustomMatchCode.MAX_FORMATION_SPACING;
            spacing.step = 2;
            spacing.value = editor.formationSpacing;
        }
        if (spacingValue) spacingValue.textContent = editor.formationSpacing + ' px';
    }

    function renderCustomPresetButtons(selector, field, presets, currentValue) {
        var el = _el ? _el.querySelector(selector) : null;
        if (!el) return;
        var html = '';
        for (var i = 0; i < presets.length; i++) {
            var active = Number(presets[i].value) === Number(currentValue);
            html += '<button class="arena-custom-preset-chip' + (active ? ' arena-custom-preset-chip-active' : '') + '" type="button" data-custom-battle-preset="' + field + '" data-custom-battle-value="' + presets[i].value + '" data-audio-cue="confirm">' + escapeHtml(presets[i].label) + '</button>';
        }
        el.innerHTML = html;
    }

    function renderCustomFormationButtons(side, current) {
        var el = _el ? _el.querySelector('#arena-custom-' + side + '-formation-options') : null;
        if (!el) return;
        var html = '';
        for (var i = 0; i < CUSTOM_FORMATION_OPTIONS.length; i++) {
            var option = CUSTOM_FORMATION_OPTIONS[i];
            html += '<button class="arena-custom-formation-option' + (option.id === current ? ' arena-custom-formation-option-active' : '') + '" type="button" data-custom-formation-side="' + side + '" data-custom-formation-value="' + option.id + '" data-audio-cue="confirm">' + escapeHtml(option.label) + '</button>';
        }
        el.innerHTML = html;
    }

    function renderCustomFormationLegend(side, formation) {
        var el = _el ? _el.querySelector('#arena-custom-' + side + '-formation-legend') : null;
        if (!el) return;
        var positions = buildCustomFormationPreview(formation, 9, side);
        var html = '';
        for (var i = 0; i < positions.length; i++) {
            html += '<i style="left:' + positions[i].x + '%;top:' + positions[i].y + '%">' + (i + 1) + '</i>';
        }
        el.innerHTML = html;
    }

    function buildCustomFormationPreview(formation, count, side) {
        var out = [];
        var i, row, col, lane, laneCount, depth;
        formation = normalizeCustomFormation(formation);
        for (i = 0; i < count; i++) {
            if (formation === 'column') {
                out.push({ x: 26, y: previewFormationY(i, count) });
            } else if (formation === 'wedge') {
                row = Math.floor((Math.sqrt(8 * i + 1) - 1) / 2);
                col = i - (row * (row + 1) / 2);
                laneCount = Math.min(row + 1, Math.max(1, count - (row * (row + 1) / 2)));
                out.push({ x: 26 + row * 14, y: previewFormationY(col, laneCount) });
            } else if (formation === 'shield') {
                laneCount = Math.min(5, count);
                if (i < laneCount) {
                    out.push({ x: 26, y: previewFormationY(i, laneCount) });
                } else {
                    row = Math.floor((i - laneCount) / 2) + 1;
                    col = (i - laneCount) % 2;
                    out.push({ x: 26 + row * 20, y: previewFormationY(col, Math.min(2, count - laneCount - (row - 1) * 2)) });
                }
            } else if (formation === 'grid') {
                laneCount = Math.min(3, Math.ceil(Math.sqrt(count)));
                depth = Math.floor(i / laneCount);
                lane = i % laneCount;
                out.push({ x: 26 + depth * 16, y: previewFormationY(lane, Math.min(laneCount, count - depth * laneCount)) });
            } else {
                out.push({ x: 26 + i * 6, y: 50 });
            }
        }
        if (side === 'blue') {
            for (i = 0; i < out.length; i++) {
                out[i].x = 100 - out[i].x;
            }
        }
        return out;
    }

    function previewFormationY(lane, laneCount) {
        if (laneCount <= 1) return 50;
        return 14 + (72 * lane / (laneCount - 1));
    }

    function enhanceCustomSelects() {
        if (!_customEditorViewEl) return;
        var selects = _customEditorViewEl.querySelectorAll('select.arena-custom-preset-select');
        for (var i = 0; i < selects.length; i++) {
            var select = selects[i];
            var shell = findCustomSelectShell(select);
            if (!shell) {
                shell = document.createElement('div');
                shell.className = 'arena-custom-select-shell';
                select.parentNode.insertBefore(shell, select);
                shell.appendChild(select);
            }
            select.classList.add('arena-custom-native-select');
            select.setAttribute('tabindex', '-1');

            var trigger = shell.querySelector('.arena-custom-select-trigger');
            if (!trigger) {
                trigger = document.createElement('button');
                trigger.type = 'button';
                trigger.className = 'arena-custom-select-trigger';
                trigger.setAttribute('data-custom-select-trigger', '1');
                trigger.setAttribute('aria-haspopup', 'listbox');
                shell.insertBefore(trigger, select);
            }

            var menu = shell.querySelector('.arena-custom-select-menu');
            if (!menu) {
                menu = document.createElement('div');
                menu.className = 'arena-custom-select-menu';
                menu.setAttribute('data-custom-select-menu', '1');
                menu.setAttribute('role', 'listbox');
                menu.hidden = true;
                shell.appendChild(menu);
            }
            syncCustomSelect(select);
        }
    }

    function findCustomSelectShell(node) {
        while (node && node !== _customEditorViewEl) {
            if (node.classList && node.classList.contains('arena-custom-select-shell')) return node;
            node = node.parentNode;
        }
        return null;
    }

    function syncCustomSelect(select) {
        var shell = findCustomSelectShell(select);
        if (!shell) return;
        var trigger = shell.querySelector('.arena-custom-select-trigger');
        var menu = shell.querySelector('.arena-custom-select-menu');
        var option = select.options[select.selectedIndex] || select.options[0];
        var label = option ? option.text : '';
        if (trigger) {
            trigger.textContent = label;
            trigger.title = label;
            trigger.disabled = !!select.disabled;
            trigger.setAttribute('aria-expanded', shell.classList.contains('arena-custom-select-open') ? 'true' : 'false');
        }
        if (menu && !menu.hidden) renderCustomSelectMenu(select, menu);
    }

    function renderCustomSelectMenu(select, menu) {
        var value = select.value;
        var html = '';
        for (var i = 0; i < select.options.length; i++) {
            var option = select.options[i];
            var active = option.value === value;
            html += '<button class="arena-custom-select-option' + (active ? ' arena-custom-select-option-active' : '') + '" type="button" role="option" aria-selected="' + (active ? 'true' : 'false') + '" data-custom-select-value="' + escapeAttr(option.value) + '">' + escapeHtml(option.text) + '</button>';
        }
        menu.innerHTML = html;
    }

    function closeCustomSelectMenus(exceptShell) {
        if (!_customEditorViewEl) return;
        var shells = _customEditorViewEl.querySelectorAll('.arena-custom-select-shell');
        for (var i = 0; i < shells.length; i++) {
            if (exceptShell && shells[i] === exceptShell) continue;
            shells[i].classList.remove('arena-custom-select-open');
            var menu = shells[i].querySelector('.arena-custom-select-menu');
            var trigger = shells[i].querySelector('.arena-custom-select-trigger');
            if (menu) menu.hidden = true;
            if (trigger) trigger.setAttribute('aria-expanded', 'false');
        }
        _customSelectOpen = exceptShell || null;
    }

    function openCustomSelect(select) {
        var shell = findCustomSelectShell(select);
        if (!shell) return;
        var menu = shell.querySelector('.arena-custom-select-menu');
        var trigger = shell.querySelector('.arena-custom-select-trigger');
        closeCustomSelectMenus(shell);
        renderCustomSelectMenu(select, menu);
        shell.classList.add('arena-custom-select-open');
        if (menu) menu.hidden = false;
        if (trigger) trigger.setAttribute('aria-expanded', 'true');
        _customSelectOpen = shell;
        var active = menu ? menu.querySelector('.arena-custom-select-option-active') : null;
        if (active && active.scrollIntoView) active.scrollIntoView({ block: 'nearest' });
    }

    function handleCustomSelectClick(e) {
        var node = e.target;
        var shellAtTarget = findCustomSelectShell(node);
        while (node && node !== _customEditorViewEl) {
            if (node.getAttribute) {
                if (node.getAttribute('data-custom-select-trigger')) {
                    var triggerShell = findCustomSelectShell(node);
                    var triggerSelect = triggerShell ? triggerShell.querySelector('select.arena-custom-preset-select') : null;
                    if (triggerSelect) {
                        if (triggerShell.classList.contains('arena-custom-select-open')) closeCustomSelectMenus();
                        else openCustomSelect(triggerSelect);
                        e.preventDefault();
                        return true;
                    }
                }
                if (node.getAttribute('data-custom-select-value') != null) {
                    var optionShell = findCustomSelectShell(node);
                    var optionSelect = optionShell ? optionShell.querySelector('select.arena-custom-preset-select') : null;
                    if (optionSelect) {
                        optionSelect.value = node.getAttribute('data-custom-select-value');
                        syncCustomSelect(optionSelect);
                        closeCustomSelectMenus();
                        optionSelect.dispatchEvent(new Event('change', { bubbles: true }));
                        e.preventDefault();
                        return true;
                    }
                }
            }
            node = node.parentNode;
        }
        if (!shellAtTarget) closeCustomSelectMenus();
        return false;
    }

    function onCustomSelectKeydown(e) {
        var shell = findCustomSelectShell(e.target);
        if (!shell) return;
        var select = shell.querySelector('select.arena-custom-preset-select');
        if (!select) return;
        var key = e.key || e.keyCode;
        if (key === 'Escape' || key === 27) {
            closeCustomSelectMenus();
            e.preventDefault();
            return;
        }
        if (key === 'Enter' || key === ' ' || key === 'ArrowDown' || key === 13 || key === 32 || key === 40) {
            if (!shell.classList.contains('arena-custom-select-open')) {
                openCustomSelect(select);
                e.preventDefault();
                return;
            }
        }
        if (shell.classList.contains('arena-custom-select-open') && (key === 'ArrowDown' || key === 'ArrowUp' || key === 40 || key === 38)) {
            var delta = (key === 'ArrowUp' || key === 38) ? -1 : 1;
            var next = Math.max(0, Math.min(select.options.length - 1, select.selectedIndex + delta));
            if (next !== select.selectedIndex) {
                select.selectedIndex = next;
                syncCustomSelect(select);
                select.dispatchEvent(new Event('change', { bubbles: true }));
            }
            e.preventDefault();
        }
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
        sanitizeCustomBattleParams(editor);
        if (editor.mode === 'pve') {
            _customSelectedSide = 'red';
            _customMatch.code = ArenaCustomMatchCode.serializeMatchCode({
                mode: 'pve',
                seed: editor.seed || 0,
                timeoutFrames: editor.timeoutFrames || ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
                spawnDistance: editor.spawnDistance || ArenaCustomMatchCode.DEFAULT_SPAWN_DISTANCE,
                blueFormation: editor.blueFormation || ArenaCustomMatchCode.DEFAULT_FORMATION,
                redFormation: editor.redFormation || ArenaCustomMatchCode.DEFAULT_FORMATION,
                formationSpacing: editor.formationSpacing || ArenaCustomMatchCode.DEFAULT_FORMATION_SPACING,
                enemyRoster: editor.red,
                player: 'current'
            });
        } else {
            _customMatch.code = ArenaCustomMatchCode.serializeMatchCode({
                mode: 'mvm',
                seed: editor.seed || 0,
                timeoutFrames: editor.timeoutFrames || ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
                spawnDistance: editor.spawnDistance || ArenaCustomMatchCode.DEFAULT_SPAWN_DISTANCE,
                blueFormation: editor.blueFormation || ArenaCustomMatchCode.DEFAULT_FORMATION,
                redFormation: editor.redFormation || ArenaCustomMatchCode.DEFAULT_FORMATION,
                formationSpacing: editor.formationSpacing || ArenaCustomMatchCode.DEFAULT_FORMATION_SPACING,
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
                ' · ' + formatCustomBattleParams(parsed) +
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
                ' · ' + formatCustomBattleParams(parsed) +
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
        var battlePage = _el.querySelector('[data-custom-editor-page="battle"]');
        var sidePage = _el.querySelector('[data-custom-editor-page="side"]');
        var paramPage = _el.querySelector('[data-custom-editor-page="params"]');
        if (configPage) configPage.hidden = _customEditorPage !== 'config';
        if (battlePage) battlePage.hidden = _customEditorPage !== 'battle';
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
        renderCustomBattleParams();

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
        enhanceCustomSelects();
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

    function showCustomBattleEditorPage() {
        _customEditorPage = 'battle';
        _customParamEditor = null;
        renderCustomEditor();
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
                    '<span>战场参数</span><b>' + escapeHtml(formatCustomBattleParams(parsed)) + '</b>' +
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
                '<span>战场参数</span><b>' + escapeHtml(formatCustomBattleParams(parsed)) + '</b>' +
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
            el.textContent = '实时解析 OK · mode=' + parsed.mode + ' · seed=' + parsed.seed + ' · ' + left + ' vs ' + right + ' · ' + formatCustomBattleParams(parsed);
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
        if (select && presets[_customSampleIndex]) {
            select.value = presets[_customSampleIndex].id;
            syncCustomSelect(select);
        }
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
        if (input.hasAttribute && input.hasAttribute('data-custom-battle-field')) {
            applyCustomBattleInput(input, false);
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
        if (handleCustomSelectClick(e)) return;
        var node = e.target;
        while (node && node !== e.currentTarget) {
            if (node.getAttribute) {
                var editorAction = node.getAttribute('data-custom-editor-action');
                if (editorAction === 'back' || editorAction === 'done') {
                    if (editorAction === 'back' && _customEditorPage === 'params') {
                        leaveCustomParamEditorDiscardingDraft();
                        return;
                    }
                    if (editorAction === 'back' && (_customEditorPage === 'side' || _customEditorPage === 'battle')) {
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
                if (editorAction === 'to-battle') {
                    showCustomBattleEditorPage();
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
                var battlePreset = node.getAttribute('data-custom-battle-preset');
                if (battlePreset) {
                    setCustomBattleValue(battlePreset, Number(node.getAttribute('data-custom-battle-value')), true);
                    return;
                }
                var formationSide = node.getAttribute('data-custom-formation-side');
                if (formationSide === 'blue' || formationSide === 'red') {
                    setCustomFormationValue(formationSide, node.getAttribute('data-custom-formation-value'));
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
        if (input.hasAttribute('data-custom-battle-field')) {
            applyCustomBattleInput(input, true);
            return;
        }
        var field = input.getAttribute('data-custom-roster-input');
        if (field !== 'level' && field !== 'count') return;
        updateCustomRosterEntry(input.getAttribute('data-side'), Number(input.getAttribute('data-index')), field, Number(input.value));
    }

    function applyCustomBattleInput(input, captureUndo) {
        var field = input.getAttribute('data-custom-battle-field');
        var value = Number(input.value);
        if (field === 'timeoutSeconds') value = value * CUSTOM_TIMEOUT_FPS;
        setCustomBattleValue(field === 'timeoutSeconds' ? 'timeoutFrames' : field, value, captureUndo);
    }

    function setCustomBattleValue(field, value, captureUndo) {
        var editor = ensureCustomEditorState();
        sanitizeCustomBattleParams(editor);
        var next = Number(value);
        if (field === 'timeoutFrames') next = clampInt(next, 30 * CUSTOM_TIMEOUT_FPS, 600 * CUSTOM_TIMEOUT_FPS);
        else if (field === 'spawnDistance') next = clampInt(next, ArenaCustomMatchCode.MIN_SPAWN_DISTANCE, ArenaCustomMatchCode.MAX_SPAWN_DISTANCE);
        else if (field === 'formationSpacing') next = clampInt(next, ArenaCustomMatchCode.MIN_FORMATION_SPACING, ArenaCustomMatchCode.MAX_FORMATION_SPACING);
        else return;
        if (editor[field] === next) {
            renderCustomBattleParams();
            return;
        }
        if (captureUndo) captureCustomUndo('调整战场参数');
        editor[field] = next;
        syncCustomCodeFromEditor();
        renderCustomBattleParams();
    }

    function setCustomFormationValue(side, value) {
        var editor = ensureCustomEditorState();
        var field = side === 'red' ? 'redFormation' : 'blueFormation';
        var next = normalizeCustomFormation(value);
        if (editor[field] === next) return;
        captureCustomUndo('调整阵型');
        editor[field] = next;
        syncCustomCodeFromEditor();
        renderCustomBattleParams();
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
        if (card.isHiddenChallenge) {
            showToast('隐藏警报不公开配置');
            return;
        }

        _activeCardIdx = idx;

        _detailTitleEl.textContent = card.isEscalation
            ? (card.faction + ' · 爬升挑战（无限波 · 奖池押注）')
            : card.isFallen
                ? (card.faction + ' · ' + difficultyOf(card).label + ' 挑战')
                : ('DEATH MATCH · 段位 ' + card.index + ' · ' + difficultyOf(card).label);
        renderDetailMeta(card, _previewCache[idx] || null);
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

    function onRerollAll() {
        if (_busy || _activeMode === 'custom') return;
        if (_activeMode === 'standard') {
            rebuildForMode('standard');
        } else {
            resetCardRuntimeState();
            buildCards();
            showGridView();
            updateCardStates();
        }
        if (_snapshot) batchRequestPreview();
        showToast(_activeMode === 'standard' ? '已重新抽取全部挑战' : '已重新抽取全部对手');
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
        // roster 卡（堕落/标准混入/隐藏混编）：把本地采样的小队作为 roster 下发 → AS2 走 commitRoster 生成混合阵容。
        // WYSIWYG：下发的就是 grid/detail 预览里那批怪（兵种 type 或 mercId + level 一一对应）。
        else if ((_cardKind[cardIdx] === 'monster' || _cardKind[cardIdx] === 'mixed')) {
            var roster = [];
            for (var ri = 0; ri < opponents.length; ri++) {
                var rosterEntry = null;
                if (opponents[ri].mercId != null) {
                    rosterEntry = { kind: 'merc', mercId: opponents[ri].mercId, level: opponents[ri].level };
                } else if (opponents[ri].type) {
                    rosterEntry = { type: opponents[ri].type, level: opponents[ri].level };
                }
                if (!rosterEntry) continue;
                if (customHasParameters(opponents[ri].parameters)) rosterEntry.parameters = cloneCustomParameters(opponents[ri].parameters);
                roster.push(rosterEntry);
            }
            if (roster.length) msg.roster = roster;
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
                if (_activeMode === 'standard') {
                    rebuildForMode('standard');
                } else if (!modeAvailable(_activeMode)) {
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
    // Batch Preview（panel open 时并发抽当前卡片集）
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
    //   1. snapshot 成功 → batchRequestPreview() → 当前卡片集并发首抽
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
        //   - 标准卡：按 session 固定角色计划执行（7 merc / 2 monster / 1 mixed，位置随机）。
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
            } else if (card.isHiddenChallenge) {
                var mixed = sampleHiddenMixedSquad(card);
                if (mixed) { _cardKind[cardIdx] = 'mixed'; _monsterSquad[cardIdx] = mixed; }
                else {
                    _previewError[cardIdx] = '混编情报不足';
                    renderCardSummary(cardIdx);
                    updateCardStates();
                    return;
                }
            } else {
                var decided = decideStandardRosterSquad(card);
                if (decided) { _cardKind[cardIdx] = decided.kind || 'monster'; _monsterSquad[cardIdx] = decided; }
                else { _cardKind[cardIdx] = 'merc'; }
            }
        }
        if (_cardKind[cardIdx] === 'monster' || _cardKind[cardIdx] === 'mixed') {
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
    // 元战队 / 混编采样 — M2：web 本地从 window.ArenaMetaRosters 抽，无 AS2 往返
    // ════════════════════════════════════════════════════════════════════════════
    // 按标准卡角色计划决定本卡是否为 mixed / 怪物小队；返回 {kind,faction,opponents} 或 null（=走 merc）。
    function decideStandardRosterSquad(card) {
        var rosters = (typeof window !== 'undefined' && window.ArenaMetaRosters)
            ? window.ArenaMetaRosters.factions : null;
        if (!rosters) return null;                       // 无数据（如 QA harness 未载）→ 恒 merc
        if (_knownEnemyCount <= 0) return null;           // 未击杀过对应 spritename → 不混入怪物，避免剧透

        if (card.standardRole === 'mixed') {
            var mixed = sampleMixedSquad(card);
            if (mixed) return mixed;
            return null;
        }
        if (card.standardRole === 'monster') {
            var monster = sampleMonsterTeamSquad(card);
            if (!monster) monster = sampleMonsterSquad(rosters, card.levelMin, card.levelMax, card.opponentCount);
            if (monster) monster.kind = 'monster';
            return monster;
        }
        return null;
    }

    // 隐藏警报卡：优先走已知的真实关卡组合；没有可用组合时才回退到已知兵种池临时混编。
    function sampleHiddenMixedSquad(card) {
        return sampleMixedSquad(card);
    }

    function sampleMixedSquad(card) {
        var mercSquad = sampleMercenaryMixedSquad(card);
        if (mercSquad) return mercSquad;
        var teamSquad = sampleMixedMetaTeamSquad(card); // 无可用佣兵时才允许剧情/关卡人形模板兜底
        if (teamSquad) return teamSquad;
        return sampleSyntheticMixedSquad(card);
    }

    function sampleMercenaryMixedSquad(card) {
        var rosters = rostersAvailable() ? window.ArenaMetaRosters.factions : null;
        if (!rosters || _knownEnemyCount <= 0) return null;
        var mercPool = mercenaryPoolForBand(card.levelMin, card.levelMax);
        var pools = splitRosterPools(rosters, card.levelMin, card.levelMax);
        if (!mercPool.length || !pools.nonHuman.length) return null;

        var counts = mixedRosterCounts(card);
        var opponents = weightedMercenarySample(mercPool, counts.humanoid);
        var monsters = sampleNonHumanTeamOpponents(card, counts.monster, HIDDEN_MIXED_TEAM_MAX_UNITS);
        var monsterSource = 'meta-team';
        if (!monsters || !monsters.length) {
            monsters = weightedSample(pools.nonHuman, card.levelMin, card.levelMax, counts.monster);
            monsterSource = 'unit-pool';
        }
        for (var i = 0; i < monsters.length; i++) {
            opponents.push(monsters[i]);
        }
        shuffleInPlace(opponents);
        return { kind: 'mixed', faction: '混编', source: 'mercenary', monsterSource: monsterSource, equivalentCount: card.opponentCount, opponents: opponents };
    }

    function sampleMixedMetaTeamSquad(card) {
        var teams = (typeof window !== 'undefined' && window.ArenaMetaRosters && window.ArenaMetaRosters.teams)
            ? window.ArenaMetaRosters.teams : null;
        if (!teams || !teams.length || _knownEnemyCount <= 0) return null;

        var candidates = [];
        for (var i = 0; i < teams.length; i++) {
            var team = teams[i];
            if (!team || team.unitCount < 2 || team.unitCount > HIDDEN_MIXED_TEAM_MAX_UNITS) continue;
            if (team.levelMax < card.levelMin || team.levelMin > card.levelMax) continue;
            if (!isKnownTeam(team)) continue;
            if (!teamHasHumanoidAndNonHuman(team)) continue;
            candidates.push({ team: team, weight: hiddenTeamWeight(team, card) });
        }
        if (!candidates.length) return null;

        var chosen = weightedTeamPick(candidates);
        var opponents = expandTeamOpponents(chosen);
        if (opponents.length < 2) return null;
        return {
            kind: 'mixed',
            faction: '混编',
            source: 'meta-team',
            teamId: chosen.id || '',
            sourceName: chosen.sourceName || chosen.sourceStage || '',
            equivalentCount: card.opponentCount,
            opponents: opponents
        };
    }

    function sampleSyntheticMixedSquad(card) {
        var rosters = rostersAvailable() ? window.ArenaMetaRosters.factions : null;
        if (!rosters || _knownEnemyCount <= 0) return null;
        var humanoidPool = humanoidTemplatePoolForBand(card.levelMin, card.levelMax);
        var pools = splitRosterPools(rosters, card.levelMin, card.levelMax);
        if (!humanoidPool.length || !pools.nonHuman.length) return null;

        var counts = mixedRosterCounts(card);
        var opponents = weightedSample(humanoidPool, card.levelMin, card.levelMax, counts.humanoid);
        var monsters = sampleNonHumanTeamOpponents(card, counts.monster, HIDDEN_MIXED_TEAM_MAX_UNITS);
        var monsterSource = 'meta-team';
        if (!monsters || !monsters.length) {
            monsters = weightedSample(pools.nonHuman, card.levelMin, card.levelMax, counts.monster);
            monsterSource = 'unit-pool';
        }
        for (var i = 0; i < monsters.length; i++) {
            opponents.push(monsters[i]);
        }
        shuffleInPlace(opponents);
        return { kind: 'mixed', faction: '混编', source: 'synthetic', monsterSource: monsterSource, equivalentCount: card.opponentCount, opponents: opponents };
    }

    function sampleMonsterTeamSquad(card) {
        var groupTarget = Math.max(1, Math.min(STANDARD_OPPONENT_CAP,
            Math.round(Number(card.opponentCount) || 1)));
        var teams = pickKnownNonHumanTeams(card.levelMin, card.levelMax, groupTarget, HIDDEN_MIXED_TEAM_MAX_UNITS);
        if (!teams || !teams.length) return null;

        var opponents = [];
        var teamIds = [];
        var factionMap = {};
        for (var i = 0; i < teams.length; i++) {
            var team = teams[i];
            var groupOpponents = expandTeamOpponents(team, HIDDEN_MIXED_TEAM_MAX_UNITS, i + 1);
            if (!groupOpponents || groupOpponents.length < 2) continue;
            teamIds.push(team.id || '');
            if (team.faction) factionMap[team.faction] = true;
            for (var j = 0; j < groupOpponents.length; j++) {
                opponents.push(groupOpponents[j]);
            }
        }
        if (!opponents.length) return null;
        return {
            kind: 'monster',
            faction: summarizeMonsterFactions(factionMap),
            source: 'meta-team',
            teamId: teamIds.join('|'),
            sourceName: teams.length > 1 ? '多组怪物队' : (teams[0].sourceName || teams[0].sourceStage || ''),
            equivalentCount: teams.length,
            opponents: opponents
        };
    }

    function sampleNonHumanTeamOpponents(card, equivalentCount, maxUnits) {
        var groupTarget = Math.max(1, Math.min(STANDARD_OPPONENT_CAP,
            Math.round(Number(equivalentCount) || 1)));
        var teams = pickKnownNonHumanTeams(card.levelMin, card.levelMax, groupTarget, maxUnits);
        if (!teams || !teams.length) return null;

        var opponents = [];
        var groups = 0;
        for (var i = 0; i < teams.length; i++) {
            var groupOpponents = expandTeamOpponents(teams[i], maxUnits, i + 1);
            if (!groupOpponents || groupOpponents.length < 2) continue;
            groups++;
            for (var j = 0; j < groupOpponents.length; j++) {
                opponents.push(groupOpponents[j]);
            }
        }
        return groups >= groupTarget ? opponents : null;
    }

    function pickKnownNonHumanTeam(levelMin, levelMax, equivalentCount, maxUnits) {
        var teams = pickKnownNonHumanTeams(levelMin, levelMax, 1, maxUnits, equivalentCount);
        return teams && teams.length ? teams[0] : null;
    }

    function pickKnownNonHumanTeams(levelMin, levelMax, groupCount, maxUnits, equivalentCount) {
        var candidates = collectKnownNonHumanTeamCandidates(levelMin, levelMax, equivalentCount || 1, maxUnits);
        if (!candidates.length) return null;
        groupCount = Math.max(1, Math.min(STANDARD_OPPONENT_CAP, Math.round(Number(groupCount) || 1)));
        var picked = [];
        var used = {};
        for (var i = 0; i < groupCount; i++) {
            var team = weightedTeamPick(candidates, used);
            if (!team) break;
            picked.push(team);
            used[teamPickKey(team)] = true;
        }
        return picked;
    }

    function collectKnownNonHumanTeamCandidates(levelMin, levelMax, equivalentCount, maxUnits) {
        var teams = (typeof window !== 'undefined' && window.ArenaMetaRosters && window.ArenaMetaRosters.teams)
            ? window.ArenaMetaRosters.teams : null;
        if (!teams || !teams.length || _knownEnemyCount <= 0) return [];
        maxUnits = Math.max(2, Math.min(HIDDEN_MIXED_TEAM_MAX_UNITS, Math.round(Number(maxUnits) || HIDDEN_MIXED_TEAM_MAX_UNITS)));

        var candidates = [];
        for (var i = 0; i < teams.length; i++) {
            var team = teams[i];
            if (!team || team.unitCount < 2 || team.unitCount > maxUnits) continue;
            if (team.levelMax < levelMin || team.levelMin > levelMax) continue;
            if (!teamHasOnlyNonHuman(team)) continue;
            if (!isKnownTeam(team)) continue;
            candidates.push({
                team: team,
                weight: monsterTeamWeight(team, levelMin, levelMax, equivalentCount)
            });
        }
        return candidates;
    }

    function summarizeMonsterFactions(factionMap) {
        var count = 0;
        var last = '';
        for (var key in factionMap) {
            if (!factionMap.hasOwnProperty(key)) continue;
            count++;
            last = key;
        }
        if (count === 1) return last || '怪物组';
        if (count > 1) return '混合怪物组';
        return '怪物组';
    }

    function teamPickKey(team) {
        if (!team) return '';
        return String(team.id || ((team.sourceStage || '') + '#' + (team.sourceName || '') + '#' + (team.levelMin || '') + '-' + (team.levelMax || '')));
    }

    function mixedRosterCounts(card) {
        var total = Math.max(2, Math.min(STANDARD_OPPONENT_CAP, Math.round(Number(card.opponentCount) || 2)));
        if (card && (card.isHiddenChallenge || card.requiresMixedRoster)) {
            var hiddenHumanoid = Math.max(1, Math.ceil(total / 2));
            return { humanoid: hiddenHumanoid, monster: Math.max(1, total - hiddenHumanoid) };
        }
        return { humanoid: 1, monster: Math.max(1, total - 1) };
    }

    function mercenaryPoolForBand(levelMin, levelMax) {
        var mercs = (typeof window !== 'undefined' && window.ArenaMetaRosters && window.ArenaMetaRosters.mercenaries)
            ? window.ArenaMetaRosters.mercenaries : null;
        if (!mercs || !mercs.length) return [];
        var pool = [];
        for (var i = 0; i < mercs.length; i++) {
            var merc = mercs[i];
            var lvl = Number(merc.level) || 1;
            if (lvl < levelMin || lvl > levelMax) continue;
            pool.push(merc);
        }
        return pool;
    }

    function weightedMercenarySample(pool, count) {
        var totalW = 0;
        for (var k = 0; k < pool.length; k++) totalW += (pool[k].weight || 1);
        var opponents = [];
        var used = {};
        for (var n = 0; n < count && n < pool.length; n++) {
            var pick = null;
            for (var guard = 0; guard < 20 && !pick; guard++) {
                var r = Math.random() * totalW, acc = 0;
                for (var j = 0; j < pool.length; j++) {
                    acc += (pool[j].weight || 1);
                    if (r <= acc) { pick = pool[j]; break; }
                }
                if (pick && used[pick.id]) pick = null;
            }
            if (!pick) {
                for (var f = 0; f < pool.length; f++) {
                    if (!used[pool[f].id]) { pick = pool[f]; break; }
                }
            }
            if (!pick) break;
            used[pick.id] = true;
            opponents.push({
                name: pick.name,
                level: Number(pick.level) || 1,
                mercId: pick.id,
                spritename: '主角-男',
                gender: pick.gender || '',
                isMonster: true,
                humanoid: true,
                rosterKind: 'humanoid',
                source: 'mercenary'
            });
        }
        return opponents;
    }

    function humanoidTemplatePoolForBand(levelMin, levelMax) {
        var teams = (typeof window !== 'undefined' && window.ArenaMetaRosters && window.ArenaMetaRosters.teams)
            ? window.ArenaMetaRosters.teams : null;
        if (!teams || !teams.length) return [];
        var pool = [];
        for (var i = 0; i < teams.length; i++) {
            var team = teams[i];
            if (!team || team.levelMax < levelMin || team.levelMin > levelMax) continue;
            var members = team.members || [];
            for (var m = 0; m < members.length; m++) {
                var member = members[m];
                if (!isHumanoidTemplateUnit(member)) continue;
                var unit = {
                    type: member.type,
                    name: member.name,
                    spritename: member.spritename,
                    gender: member.gender || '',
                    minLevel: Number(member.level) || levelMin,
                    maxLevel: Number(member.level) || levelMax,
                    weight: Math.max(1, Number(member.count) || 1),
                    humanoid: true
                };
                var parameters = member.Parameters || member.parameters || member['参数'];
                if (customHasParameters(parameters)) unit.parameters = cloneCustomParameters(parameters);
                pool.push(unit);
            }
        }
        return pool;
    }

    function isKnownTeam(team) {
        var members = (team && team.members) || [];
        if (!members.length) return false;
        for (var i = 0; i < members.length; i++) {
            if (!isKnownEnemyUnit(members[i])) return false;
        }
        return true;
    }

    function teamHasHumanoidAndNonHuman(team) {
        var members = (team && team.members) || [];
        var humanoid = false, nonHuman = false;
        for (var i = 0; i < members.length; i++) {
            var kind = rosterKindForUnit(members[i]);
            if (kind === 'humanoid') humanoid = true;
            else if (kind === 'nonhuman') nonHuman = true;
        }
        return humanoid && nonHuman;
    }

    function teamHasOnlyNonHuman(team) {
        var members = (team && team.members) || [];
        if (!members.length) return false;
        for (var i = 0; i < members.length; i++) {
            if (rosterKindForUnit(members[i]) !== 'nonhuman') return false;
        }
        return true;
    }

    function hiddenTeamWeight(team, card) {
        var targetPower = Math.max(1, card.opponentCount) * ((card.levelMin + card.levelMax) / 2);
        var power = Number(team.powerRating);
        if (isNaN(power) || power <= 0) power = estimateTeamPower(team);
        var closeness = targetPower / (targetPower + Math.abs(power - targetPower));
        var groupBonus = team.unitCount > card.opponentCount ? 1.2 : 1;
        return Math.max(0.05, closeness) * groupBonus;
    }

    function monsterTeamWeight(team, levelMin, levelMax, equivalentCount) {
        var levelBase = (levelMin + levelMax) / 2;
        var targetPower = Math.max(1, Number(equivalentCount) || 1) * levelBase;
        var power = Number(team.powerRating);
        if (isNaN(power) || power <= 0) power = estimateTeamPower(team);
        var closeness = targetPower / (targetPower + Math.abs(power - targetPower));
        var sizeBonus = team.unitCount > Math.max(1, equivalentCount) ? 1.15 : 1;
        var factionBonus = team.faction && team.faction !== 'unknown' ? 1.05 : 1;
        return Math.max(0.05, closeness) * sizeBonus * factionBonus;
    }

    function estimateTeamPower(team) {
        var members = (team && team.members) || [];
        var sum = 0;
        for (var i = 0; i < members.length; i++) {
            sum += (Number(members[i].level) || 1) * Math.max(1, Number(members[i].count) || 1);
        }
        return sum || 1;
    }

    function weightedTeamPick(candidates, used) {
        var pool = [];
        for (var p = 0; p < candidates.length; p++) {
            var key = teamPickKey(candidates[p].team);
            if (!used || !used[key]) pool.push(candidates[p]);
        }
        if (!pool.length) pool = candidates;

        var total = 0;
        for (var i = 0; i < pool.length; i++) total += pool[i].weight || 1;
        var r = Math.random() * total, acc = 0;
        for (var j = 0; j < pool.length; j++) {
            acc += pool[j].weight || 1;
            if (r <= acc) return pool[j].team;
        }
        return pool[0].team;
    }

    function expandTeamOpponents(team, maxUnits, groupInstance) {
        var limit = Math.max(1, Math.min(HIDDEN_MIXED_TEAM_MAX_UNITS,
            Math.round(Number(maxUnits) || HIDDEN_MIXED_TEAM_MAX_UNITS)));
        var out = [];
        var members = (team && team.members) || [];
        var baseGroupId = String((team && team.id) || ((team && team.sourceStage) ? (team.sourceStage + '#' + team.sourceName) : '') || 'monster-team');
        var groupId = groupInstance != null ? (baseGroupId + '@' + groupInstance) : baseGroupId;
        var groupName = String((team && (team.sourceName || team.sourceStage || team.faction)) || '关卡怪物组');
        var groupTotal = Math.min(limit, Math.max(1, Number(team && team.unitCount) || limit));
        for (var i = 0; i < members.length; i++) {
            var member = members[i];
            var count = Math.max(1, Math.round(Number(member.count) || 1));
            for (var n = 0; n < count && out.length < limit; n++) {
                var opponent = {
                    name: member.name,
                    level: Number(member.level) || 1,
                    type: member.type,
                    spritename: member.spritename,
                    gender: member.gender || '',
                    isMonster: true,
                    rosterKind: rosterKindForUnit(member),
                    sourceGroupId: groupId,
                    sourceGroupName: groupName,
                    sourceGroupMemberIndex: out.length + 1,
                    sourceGroupMemberTotal: groupTotal
                };
                var parameters = member.Parameters || member.parameters || member['参数'];
                if (customHasParameters(parameters)) opponent.parameters = cloneCustomParameters(parameters);
                out.push(opponent);
            }
        }
        shuffleInPlace(out);
        return out;
    }

    function splitRosterPools(rosters, levelMin, levelMax) {
        var all = [], humanoid = [], nonHuman = [];
        for (var f in rosters) {
            var pool = poolForBand(rosters[f].units, levelMin, levelMax);
            for (var i = 0; i < pool.length; i++) {
                var unit = pool[i];
                all.push(unit);
                if (rosterKindForUnit(unit) === 'humanoid') humanoid.push(unit);
                else if (rosterKindForUnit(unit) === 'nonhuman') nonHuman.push(unit);
            }
        }
        return { all: all, humanoid: humanoid, nonHuman: nonHuman };
    }

    function rosterKindForUnit(unit) {
        if (isHumanoidTemplateUnit(unit)) return 'humanoid';
        return 'nonhuman';
    }

    function isHumanoidRosterUnit(unit) {
        return rosterKindForUnit(unit) === 'humanoid';
    }

    function isHumanoidTemplateUnit(unit) {
        if (!unit) return false;
        if (unit.humanoid === true) return true;
        return /主角/.test(String(unit.spritename || ''));
    }

    function shuffleInPlace(list) {
        for (var i = list.length - 1; i > 0; i--) {
            var j = Math.floor(Math.random() * (i + 1));
            var t = list[i];
            list[i] = list[j];
            list[j] = t;
        }
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
        if (isHumanoidTemplateUnit(unit)) return true; // 佣兵模板由竞技场混编放行；普通怪物仍要求已击杀
        return _knownEnemies[String(unit.spritename)] === true;
    }

    function rosterDisplaySpritename(unit) {
        var sprite = String(unit && unit.spritename || '');
        if (isHumanoidTemplateUnit(unit) && (sprite === '主角-男' || sprite === '主角-女')) {
            var gender = String(unit && unit.gender || '').trim();
            if (gender === '女') return '主角-女';
            if (gender === '男') return '主角-男';
        }
        return sprite.replace(/^敌人-/, '');
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
            var opponent = {
                name: pick.name,
                level: lvl,
                type: pick.type,
                spritename: pick.spritename,
                gender: pick.gender || '',
                isMonster: true,
                rosterKind: isHumanoidRosterUnit(pick) ? 'humanoid' : 'nonhuman'
            };
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
        if (card && card.isHiddenChallenge) return; // 隐藏卡不公开混编来源，保留「配置保密」
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
        var card = _activeCards[cardIdx];
        if (card && card.isHiddenChallenge) {
            sumEl.textContent = '配置保密 · 已抽取';
            return;
        }
        if (isRosterOpponents(opps)) {
            var stats = rosterStats(opps, card);
            var rosterParts = [];
            if (stats.groups > 0) rosterParts.push('怪物组×' + stats.groups);
            rosterParts.push('实体×' + stats.actual);
            if (opps[0] && opps[0].name) {
                rosterParts.push(opps[0].name + ' Lv' + opps[0].level + (stats.actual > 1 ? ' +' + (stats.actual - 1) : ''));
            }
            sumEl.textContent = rosterParts.join(' · ');
            return;
        }
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

    function isRosterOpponents(opponents) {
        return !!(opponents && opponents.length && opponents[0] && opponents[0].isMonster);
    }

    function rosterStats(opponents, card) {
        var stats = {
            equivalent: 0,
            actual: opponents ? opponents.length : 0,
            humanoid: 0,
            nonhuman: 0,
            groups: 0
        };
        var seenGroups = {};
        opponents = opponents || [];
        for (var i = 0; i < opponents.length; i++) {
            if (opponents[i].rosterKind === 'humanoid') {
                stats.humanoid++;
                stats.equivalent++;
                continue;
            } else if (opponents[i].rosterKind === 'nonhuman') {
                stats.nonhuman++;
            }
            var gid = opponents[i].sourceGroupId;
            if (gid && !seenGroups[gid]) {
                seenGroups[gid] = true;
                stats.groups++;
                stats.equivalent++;
            } else if (!gid) {
                stats.equivalent++;
            }
        }
        return stats;
    }

    function renderDetailMeta(card, opponents) {
        if (!_detailMetaEl || !card) return;
        var html = '';
        if (isRosterOpponents(opponents)) {
            var stats = rosterStats(opponents, card);
            html += '<span class="arena-meta-chip arena-meta-equivalent">等效 ×' + stats.equivalent + '</span>';
            html += '<span class="arena-meta-chip arena-meta-actual">实体 ×' + stats.actual + '</span>';
            if (stats.groups > 0) {
                html += '<span class="arena-meta-chip arena-meta-group">怪物组 ×' + stats.groups + '</span>';
            }
        } else {
            html += '<span class="arena-meta-chip">对手 ×' + card.opponentCount + '</span>';
        }
        html += '<span class="arena-meta-chip">等级 ' + card.levelMin + '—' + card.levelMax + '</span>' +
            '<span class="arena-meta-chip arena-meta-deposit">押金 ' + formatMoney(card.deposit) + '</span>' +
            '<span class="arena-meta-chip arena-meta-reward">奖金 ' + formatMoney(card.reward) + '</span>';
        _detailMetaEl.innerHTML = html;
    }

    // roster 小队（M2）：无装备/技能，渲简版行（头像 + 名/级 + roster 标 + 家族注）。
    function renderMonsterOpponents(opponents) {
        var card = (_activeCardIdx >= 0) ? _activeCards[_activeCardIdx] : null;
        renderDetailMeta(card, opponents);
        var stats = rosterStats(opponents, card);
        var html = '<div class="arena-opp-roster-brief">';
        html += '<span>等效 ×' + stats.equivalent + '</span>';
        html += '<span>实战实体 ×' + stats.actual + '</span>';
        if (stats.groups > 0) html += '<span>怪物组 ×' + stats.groups + '</span>';
        if (stats.humanoid > 0) html += '<span>佣兵 ×' + stats.humanoid + '</span>';
        html += '</div>';
        for (var i = 0; i < opponents.length; i++) {
            var opp = opponents[i];
            var tagText = opp.rosterKind === 'humanoid'
                ? '佣兵'
                : (opp.sourceGroupId
                    ? ('怪物组 ' + (opp.sourceGroupMemberIndex || 1) + '/' + (opp.sourceGroupMemberTotal || stats.nonhuman || 1))
                    : '怪物');
            var noteText = rosterDisplaySpritename(opp);
            if (opp.sourceGroupName && opp.rosterKind !== 'humanoid') noteText += ' · ' + opp.sourceGroupName;
            html += '<div class="arena-opp-row arena-opp-row-monster">';
            html += '<div class="arena-opp-portrait arena-opp-portrait-fallback arena-opp-portrait-monster"></div>';
            html += '<div class="arena-opp-main">';
            html += '<div class="arena-opp-topline">';
            html += '<span class="arena-opp-name">' + escapeHtml(opp.name) + '</span>';
            html += '<span class="arena-opp-level">LV. ' + opp.level + '</span>';
            html += '<span class="arena-opp-monster-tag">' + escapeHtml(tagText) + '</span>';
            html += '</div>';
            html += '<div class="arena-opp-monster-note">' + escapeHtml(noteText) + '</div>';
            html += '</div></div>';
        }
        _detailOpponentsEl.innerHTML = html;
    }

    function renderOpponents(opponents) {
        var card = (_activeCardIdx >= 0) ? _activeCards[_activeCardIdx] : null;
        renderDetailMeta(card, opponents);
        // roster 小队：走简版渲染（无装备/技能 hover）
        if (isRosterOpponents(opponents)) {
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
        updateRerollAllButton();
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
            setCardDetailEnabled(i, !_busy && !_activeCards[i].isHiddenChallenge);
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
