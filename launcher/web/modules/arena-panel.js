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

    // ════════════════════════════════════════════════════════════════════════════
    // 状态
    // ════════════════════════════════════════════════════════════════════════════
    var _el;
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
                '<h1 class="arena-title">DEATH MATCH角斗场</h1>' +
                '<div class="arena-money">' +
                    '<span class="arena-money-label">当前金钱:</span>' +
                    '<span class="arena-money-value" id="arena-money-value">--</span>' +
                '</div>' +
                '<button class="arena-close-btn" type="button" title="关闭" aria-label="关闭" data-audio-cue="cancel">✕</button>' +
            '</div>' +
            '<div class="arena-grid-view" id="arena-grid-view">' +
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

        buildCards();

        if (typeof Icons !== 'undefined') Icons.load(function(){});

        return _el;
    }

    function buildCards() {
        var gridEl = _el.querySelector('#arena-grid');
        gridEl.innerHTML = '';
        _cardEls = [];

        for (var i = 0; i < ARENA_CARDS.length; i++) {
            var card = ARENA_CARDS[i];
            var cardEl = document.createElement('div');
            cardEl.className = 'arena-card';
            cardEl.dataset.index = i;
            cardEl.innerHTML =
                '<div class="arena-card-header">' +
                    '<span class="arena-card-icon">⚠</span>' +
                    '<span class="arena-card-name">' + escapeHtml(card.name) + '</span>' +
                '</div>' +
                '<div class="arena-card-body">' +
                    '<div class="arena-card-row">' +
                        '<span class="arena-card-label">挑战对手数量:</span>' +
                        '<span class="arena-card-value">' + card.opponentCount + '</span>' +
                    '</div>' +
                    '<div class="arena-card-row">' +
                        '<span class="arena-card-label">对手等级:</span>' +
                        '<span class="arena-card-value">' + card.levelMin + '—' + card.levelMax + '</span>' +
                    '</div>' +
                    '<div class="arena-card-row arena-card-deposit">' +
                        '<span class="arena-card-label">押金:</span>' +
                        '<span class="arena-card-value">' + formatMoney(card.deposit) + '</span>' +
                    '</div>' +
                    '<div class="arena-card-row arena-card-reward">' +
                        '<span class="arena-card-label">奖金:</span>' +
                        '<span class="arena-card-value">' + formatMoney(card.reward) + '</span>' +
                    '</div>' +
                    // 对手摘要 row：snapshot 回包后 batchRequestPreview 触发 8 卡并发抽签，
                    // 单卡回包后 renderCardSummary(cardIdx) 写入下方 span。
                    '<div class="arena-card-row arena-card-opponents-row">' +
                        '<span class="arena-card-label">对手:</span>' +
                        '<span class="arena-card-opponents arena-card-opponents-loading" id="arena-opp-summary-' + i + '">抽取中…</span>' +
                    '</div>' +
                '</div>' +
                // 主+次按钮：主 ⚔ 开始挑战（grid 直入战场，无需进 detail）；次 🔍 查看对手（进 detail 看装备 / 换一批）
                '<div class="arena-card-actions">' +
                    '<button class="arena-card-btn arena-card-btn-enter" type="button" data-index="' + i + '" data-audio-cue="confirm">⚔ 开始挑战</button>' +
                    '<button class="arena-card-btn-detail" type="button" data-index="' + i + '" data-audio-cue="confirm" title="查看对手详情">🔍</button>' +
                '</div>';

            cardEl.querySelector('.arena-card-btn-enter').addEventListener('click', onDirectEnter);
            cardEl.querySelector('.arena-card-btn-detail').addEventListener('click', onCardClick);
            gridEl.appendChild(cardEl);
            _cardEls.push(cardEl);
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 生命周期
    // ════════════════════════════════════════════════════════════════════════════
    function onOpen(el, initData) {
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
        // 重置所有 grid 摘要回 loading 态（避免 reopen 时残留上次 cache 的文本）
        for (var k = 0; k < ARENA_CARDS.length; k++) {
            var sumEl = document.getElementById('arena-opp-summary-' + k);
            if (sumEl) {
                sumEl.className = 'arena-card-opponents arena-card-opponents-loading';
                sumEl.textContent = '抽取中…';
            }
        }
        // initData.difficulty 来自 stage-select 重定向；dev 模式 ARENA_TEST 直开时为 ""
        _initDifficulty = (initData && initData.difficulty) ? String(initData.difficulty) : '';
        hideToast();
        updateMoneyDisplay(null);
        updateCardStates();
        showGridView();
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
        var card = ARENA_CARDS[idx];
        if (!card) return;

        _activeCardIdx = idx;

        _detailTitleEl.textContent = card.name + ' · 卡片 ' + card.index;
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
        var card = ARENA_CARDS[_activeCardIdx];
        if (!card) return;
        _detailOpponentsEl.innerHTML = '<div class="arena-opponents-loading">正在重新抽取…</div>';
        setDetailButtonsBusy(true);
        // 强制重抽：清 dedup token + cache + error，让 requestPreviewForCard 走完整新链路。
        // 回包后会自动 _previewCache[idx] = 新 lineup → renderCardSummary 同步 grid 摘要（覆盖旧）
        delete _previewPending[_activeCardIdx];
        delete _previewCache[_activeCardIdx];
        delete _previewError[_activeCardIdx];
        requestPreviewForCard(_activeCardIdx);
    }

    // grid 直入入口（"⚔ 开始挑战" 按钮）。从 _previewCache[cardIdx] 取 lineup 走入场链。
    // updateCardStates 在 cache 缺失时已 disable enter 按钮，这里 opponents 兜底校验只是双保险。
    function onDirectEnter(e) {
        e.stopPropagation();
        if (_busy) return;
        var btn = e.currentTarget || e.target;
        var cardIdx = parseInt(btn.dataset.index, 10);
        var card = ARENA_CARDS[cardIdx];
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
        enterChallenge(_activeCardIdx, ARENA_CARDS[_activeCardIdx], _previewOpponents);
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

        Bridge.send({
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
        });
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
        for (var i = 0; i < ARENA_CARDS.length; i++) {
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
        if (_previewPending[cardIdx] !== undefined) return; // dedup
        var card = ARENA_CARDS[cardIdx];
        if (!card) return;

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
        requestPreviewForCard(idx);
    }

    function renderOpponents(opponents) {
        var SLOT_LABELS = {
            6: '头盔', 7: '护身', 8: '护甲', 9: '护腿', 10: '靴子',
            11: '披风', 12: '主武器', 13: '副武器', 14: '副武器2',
            15: '近战', 16: '手雷'
        };
        var html = '';
        for (var i = 0; i < opponents.length; i++) {
            var opp = opponents[i];
            html += '<div class="arena-opp-row">';
            html += '<div class="arena-opp-info">';
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
            html += '</div>';
            html += '</div>';
        }
        _detailOpponentsEl.innerHTML = html;

        // 装备 hover → tooltip
        var cells = _detailOpponentsEl.querySelectorAll('.arena-equip-cell[data-eq-raw]');
        for (var c = 0; c < cells.length; c++) {
            cells[c].addEventListener('mouseenter', onEquipHover);
            cells[c].addEventListener('mouseleave', onEquipLeave);
            cells[c].addEventListener('mousemove', onEquipMove);
        }
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

    // 富文本态：TooltipComposer 的 introHTML/descHTML 已含 displayname header，不再外加
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
        for (var i = 0; i < ARENA_CARDS.length; i++) {
            var deposit = ARENA_CARDS[i].deposit;
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
            previewErrorCount: Object.keys(_previewError).length
        };
    }

    // 暴露给 harness QA
    if (typeof window !== 'undefined') {
        window.ArenaPanel = {
            getState: _debugGetState,
            getCards: function() { return ARENA_CARDS.slice(); }
        };
    }
})();
