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

    // 竞技场模式（顶部 tab 条，视觉对齐战队界面 .team-tab）。
    // 当前仅「标准模式」；后续不同玩法在此追加 { id, label }，并在 onModeClick 扩展点接入
    // 各模式自己的卡片集 / preview 逻辑。结构先就位，避免把模式硬编进单一卡片列表。
    var ARENA_MODES = [
        { id: 'standard', label: '标准模式' },
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

    // ════════════════════════════════════════════════════════════════════════════
    // Panel 注册
    // ════════════════════════════════════════════════════════════════════════════
    Panels.register('arena', {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: requestClose,
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
        _moneyEl = _el.querySelector('#arena-money-value');
        _detailTitleEl = _el.querySelector('#arena-detail-title');
        _detailMetaEl = _el.querySelector('#arena-detail-meta');
        _detailOpponentsEl = _el.querySelector('#arena-opponents');
        _detailRollBtn = _el.querySelector('.arena-detail-roll');
        _detailConfirmBtn = _el.querySelector('.arena-detail-confirm');

        _el.querySelector('.arena-close-btn').addEventListener('click', requestClose);
        _el.querySelector('.arena-detail-back').addEventListener('click', backToGrid);
        _detailRollBtn.addEventListener('click', onRollAgain);
        _detailConfirmBtn.addEventListener('click', onConfirmChallenge);

        var modeTabs = _el.querySelectorAll('.arena-mode-tab');
        for (var mt = 0; mt < modeTabs.length; mt++) {
            modeTabs[mt].addEventListener('click', onModeClick);
        }

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

        for (var i = 0; i < _activeCards.length; i++) {
            var card = _activeCards[i];
            var diff = difficultyOf(card);
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

    // 元战队 roster 数据是否就绪（arena-meta-rosters.js 已载）。
    // 决定堕落模式 tab 是否显示 + 怪物采样是否可行。QA harness 未载 → 恒 false。
    function rostersAvailable() {
        return (typeof window !== 'undefined') && !!window.ArenaMetaRosters && !!window.ArenaMetaRosters.factions;
    }

    // 模式 tab 条（对齐战队界面 tab）。requiresRosters 的模式仅在数据就绪时出现。
    function buildModeTabs() {
        var html = '';
        for (var i = 0; i < ARENA_MODES.length; i++) {
            var m = ARENA_MODES[i];
            if (m.requiresRosters && !rostersAvailable()) continue;
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
        rebuildForMode(mode);
        if (_snapshot) batchRequestPreview();
    }

    // 按模式重建卡片集与 DOM，并复位 per-card 派生状态。不发请求（caller 决定何时 batch）。
    function rebuildForMode(mode) {
        _activeMode = mode;
        _activeCards = (mode === 'fallen') ? buildFallenCards()
                     : (mode === 'escalation') ? buildEscalationCards()
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
            var meta = factionMeta(name);
            if (meta.enabled === false) continue;     // 手作禁用的势力不出卡
            var lo = 99999, hi = 0;
            for (var u = 0; u < units.length; u++) {
                if (units[u].minLevel < lo) lo = units[u].minLevel;
                if (units[u].maxLevel > hi) hi = units[u].maxLevel;
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
                unitCount: units.length,
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
        var units = factions[faction].units || [];
        var pool = [];
        for (var i = 0; i < units.length; i++) {
            var u = units[i];
            pool.push({ type: u.type, minLevel: u.minLevel, maxLevel: u.maxLevel, weight: u.weight });
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
        // initData.difficulty 来自 stage-select 重定向；dev 模式 ARENA_TEST 直开时为 ""
        _initDifficulty = (initData && initData.difficulty) ? String(initData.difficulty) : '';
        hideToast();
        updateMoneyDisplay(null);
        // 每次打开复位到标准模式：重建标准卡 DOM（摘要回 loading）+ 清缓存 + tab active 态 + 显示 grid。
        // 上次会话可能停在堕落模式；DOM 跨 open/close 复用，必须重建回标准（否则残留堕落卡）。
        rebuildForMode('standard');
        requestSnapshot();
    }

    // requestClose 两种调用语义：
    //   - 无参 / 默认：用户主动取消（点 ✕、ESC、backdrop），PanelHostController 会 pop
    //     return stack reopen 上层 panel（典型场景：玩家从 stage-select 跳进 arena，
    //     按 ✕ 想回 stage-select）。
    //   - {dismissReturnStack:true}：业务流程已 commit，AS2 端已跳关到 wuxianguotu_1。
    //     必须清整个返回链，否则 PanelHostController 会 reopen stage-select 遮挡战场视野。
    function requestClose(options) {
        if (_busy) return;
        Panels.close();
        var msg = { type: 'panel', panel: 'arena', cmd: 'close' };
        if (options && options.dismissReturnStack) msg.dismissReturnStack = true;
        Bridge.send(msg);
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
        PanelTooltip.hide();
    }

    function showDetailView() {
        _gridViewEl.hidden = true;
        _detailViewEl.hidden = false;
    }

    function backToGrid() {
        if (_busy) return;
        _activeCardIdx = -1;
        _previewOpponents = null;
        showGridView();
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
                roster.push({ type: opponents[ri].type, level: opponents[ri].level });
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
            if (u.minLevel <= levelMax && u.maxLevel >= levelMin) pool.push(u);
        }
        return pool;
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
            opponents.push({ name: pick.name, level: lvl, type: pick.type, spritename: pick.spritename, isMonster: true });
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
                    var iconUrl = (typeof Icons !== 'undefined') ? Icons.resolve(iconKey) : null;
                    var iconHtml = iconUrl
                        ? '<img src="' + escapeAttr(iconUrl) + '" alt="" onerror="this.style.display=\'none\'">'
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
    // 对手技能渲染（复用 merc 技能图标范式：Icons.resolve 烘焙图 → 占位字回退 → 等级 + tooltip）
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
        var iconUrl = (name && typeof Icons !== 'undefined') ? Icons.resolve(name) : null;
        var cls = 'arena-skill-cell' + (iconUrl ? ' arena-skill-cell-baked' : '');
        var imgHtml = iconUrl ? '<img class="arena-skill-icon" src="' + escapeAttr(iconUrl) + '" alt="">' : '';
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
        var iconUrl = (iconKey && typeof Icons !== 'undefined') ? Icons.resolve(iconKey) : null;

        var cached = _ttCache[key];
        var html = cached
            ? buildRichTooltipHtml(cached, iconUrl)
            : buildBasicTooltipHtml(displayName, level, iconUrl);
        PanelTooltip.showAtMouse(html, e);
        if (!cached) requestEquipTooltip(raw, level, key, iconUrl);
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
    function buildBasicTooltipHtml(displayName, level, iconUrl) {
        var iconBlock = iconUrl
            ? '<div class="kshop-tt-icon"><img src="' + iconUrl + '"></div>'
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
    function buildRichTooltipHtml(data, iconUrl) {
        return PanelTooltip.buildItemRichHtml({
            iconUrl:   iconUrl,
            introHTML: data.introHTML,
            descHTML:  data.descHTML,
            rootClass: 'arena-tt-rich'
        });
    }

    function requestEquipTooltip(raw, level, key, iconUrl) {
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
                PanelTooltip.updateContent(buildRichTooltipHtml(_ttCache[key], iconUrl));
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
            pendingCount: Object.keys(_pendingReq).length,
            previewCacheCount: Object.keys(_previewCache).length,
            previewPendingCount: Object.keys(_previewPending).length,
            previewErrorCount: Object.keys(_previewError).length,
            cardKind: _cardKind
        };
    }

    // 暴露给 harness QA
    if (typeof window !== 'undefined') {
        window.ArenaPanel = {
            getState: _debugGetState,
            getCards: function() { return _activeCards.slice(); },
            // 测试/截图注入：设怪物混入概率（1=全怪物，0=全 merc）。需 window.ArenaMetaRosters 已载。
            setMixChance: function(p) { _mixChance = Number(p); },
            // 测试/截图：切到堕落模式（需 rosters 已载）。返回切后卡片数。
            switchMode: function(mode) { rebuildForMode(mode); if (_snapshot) batchRequestPreview(); return _activeCards.length; }
        };
    }
})();
