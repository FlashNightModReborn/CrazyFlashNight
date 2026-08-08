/**
 * arena-challenge-browser.js — 竞技场面板 P4 工程拆分 · 挑战浏览器：三模式卡片目录 / 选中与决策栏 / 重抽 / enter / 对手渲染 / tooltip。
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
        throw new Error('arena/arena-challenge-browser.js 需要先加载 arena/arena-core.js（共享基座：状态容器 + 跨模块工具 + 共享常量）');
    }

    var S = ArenaCore.state; // 共享状态（原顶层 var _x）


    // ════════════════════════════════════════════════════════════════════════════
    // P5：标准/隐藏/势力卡都来自 C# snapshot.arenaAuthority。
    // Web 只分配展示用 roster 角色并提交 cardId；不再拥有经济公式或 XML 镜像常量。
    // ════════════════════════════════════════════════════════════════════════════
    var STANDARD_OPPONENT_CAP = 4; // Flash 战斗承压上限：标准 / 隐藏警报卡的佣兵等效人数均不超过 4
    var STANDARD_ROLE_COUNTS = { merc: 7, monster: 2, mixed: 1 }; // 公开 10 卡固定配比，位置每 session 随机
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

    var HIDDEN_MIXED_TEAM_MAX_UNITS = 12; // 单个怪物组展开上限；AS2 运行态按 12 活体上限分批补刷。

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

    // 左右栏视图：左 = 模式内卡目录（控件条 + 可滚网格）；右 = 选中挑战 preview + CommitBar。
    function buildBrowseViews() {
        S._catalogRoot = document.createElement('div');
        S._catalogRoot.className = 'workbench-view arena-catalog';
        var controls = document.createElement('div');
        controls.className = 'arena-catalog-controls';
        S._rollOneBtn = document.createElement('button');
        S._rollOneBtn.type = 'button';
        S._rollOneBtn.id = 'arena-roll-one';
        S._rollOneBtn.className = 'arena-detail-roll';
        S._rollOneBtn.textContent = '↻ 换一批';
        S._rollOneBtn.title = '重新抽取选中挑战的对手（免费）';
        S._rollOneBtn.setAttribute('data-audio-cue', 'confirm');
        S._rollOneBtn.disabled = true;
        S._rollOneBtn.addEventListener('click', onRollAgain);
        controls.appendChild(S._rollOneBtn);
        S._rerollAllBtn = document.createElement('button');
        S._rerollAllBtn.type = 'button';
        S._rerollAllBtn.id = 'arena-reroll-all';
        S._rerollAllBtn.className = 'arena-reroll-all';
        S._rerollAllBtn.textContent = '↻ 全部重抽';
        S._rerollAllBtn.title = '重新抽取当前模式全部卡片与对手';
        S._rerollAllBtn.setAttribute('data-audio-cue', 'confirm');
        S._rerollAllBtn.addEventListener('click', onRerollAll);
        controls.appendChild(S._rerollAllBtn);
        S._catalogRoot.appendChild(controls);

        S._catalogGridEl = document.createElement('div');
        S._catalogGridEl.className = 'arena-grid';
        S._catalogGridEl.id = 'arena-grid';
        S._catalogGridEl.setAttribute('role', 'listbox');
        S._catalogGridEl.setAttribute('aria-label', '挑战目录');
        S._catalogGridEl.addEventListener('keydown', onGridKeydown);
        S._catalogRoot.appendChild(S._catalogGridEl);
        S._density.register(S._catalogGridEl);

        S._decisionRoot = document.createElement('div');
        S._decisionRoot.className = 'workbench-view arena-decision';
        var head = document.createElement('div');
        head.className = 'arena-decision-head';
        head.innerHTML =
            '<div class="arena-detail-title-block">' +
                '<h2 class="arena-detail-title" id="arena-detail-title">--</h2>' +
                '<div class="arena-detail-meta" id="arena-detail-meta"></div>' +
            '</div>';
        S._decisionRoot.appendChild(head);
        S._detailTitleEl = head.querySelector('#arena-detail-title');
        S._detailMetaEl = head.querySelector('#arena-detail-meta');
        S._detailOpponentsEl = document.createElement('div');
        S._detailOpponentsEl.className = 'arena-opponents';
        S._detailOpponentsEl.id = 'arena-opponents';
        // 可聚焦纵向滚动区：右栏 preview 内容超出时键盘可达（壳级 data-scroll-region focus 环）
        S._detailOpponentsEl.setAttribute('data-scroll-region', '');
        S._detailOpponentsEl.setAttribute('tabindex', '0');
        S._decisionRoot.appendChild(S._detailOpponentsEl);
        S._commitBar = new WorkbenchComponents.CommitBar({
            label: '⚔ 开始挑战',
            status: '选择左侧挑战后确认',
            disabled: true,
            onCommit: commitSelectedChallenge
        });
        // 复用原 detail 确认键的战术橙 CTA 视觉（arena.css 同各类名规则）
        S._commitBar.primaryButton.classList.add('arena-detail-confirm');
        S._commitBar.primaryButton.setAttribute('data-audio-cue', 'confirm');
        S._commitBar.mount(S._decisionRoot);

        S._browseL = simpleView('arena:catalog', 'catalog', ['L'], S._catalogRoot, function() {});
        S._browseR = simpleView('arena:decision', 'detail', ['R'], S._decisionRoot, function() {});
        renderDecisionEmpty();
    }

    function buildCards() {
        var gridEl = S._catalogGridEl;
        gridEl.innerHTML = '';
        S._cardEls = [];
        // 卡片多于单屏（>8）→ 切顶部对齐的滚动布局；否则铺满单屏。
        gridEl.classList.toggle('arena-grid-scroll', S._activeCards.length > 8);
        if (S._customGridEl) S._customGridEl.innerHTML = '';

        for (var i = 0; i < S._activeCards.length; i++) {
            var card = S._activeCards[i];
            var diff = ArenaCore.difficultyOf(card);
            if (card.isCustom) {
                var customCardEl = buildCustomMatchCard(i, card, diff);
                if (S._customGridEl) S._customGridEl.appendChild(customCardEl);
                S._cardEls.push(customCardEl);
                continue;
            }
            var isFallen = !!card.isFallen;
            var isHidden = !!card.isHiddenChallenge;
            var cardEl = document.createElement('div');
            // d{1..6} 类驱动 --d-color 难度热度（CSS .arena-card-d* → 顶部色条 + 难度标签色）。
            // 堕落卡恒 roster 怪物队 → 建卡即上 arena-card-monster（紫罗兰），不等采样回调。
            cardEl.className = 'arena-card arena-card-d' + diff.tier +
                (isFallen ? ' arena-card-monster' : '') +
                (isHidden ? ' arena-card-hidden' : '') +
                (i === S._selectedCardIdx ? ' arena-card-selected' : '');
            cardEl.dataset.index = i;
            // P2（P0 裁决 2）：卡片 = 纯选中语义。click 选中、方向键移动选择、
            // 已选中卡 Enter/Space 触发与右栏 CommitBar 同一 commit handler；卡面不再承载按钮。
            cardEl.setAttribute('tabindex', '0');
            cardEl.setAttribute('role', 'option');
            cardEl.setAttribute('aria-selected', i === S._selectedCardIdx ? 'true' : 'false');
            // 标准卡 rank = 段位号；堕落卡 rank = 势力名（卡片身份）+ 阵容 cap 改「麾下阵容」
            var rankText = isFallen ? card.faction : (isHidden ? card.hiddenLabel : ('段位 ' + card.index));
            var rankHtml = isFallen
                ? '<span class="arena-card-rank arena-card-rank-faction">' + ArenaCore.escapeHtml(card.faction) + '</span>'
                : '<span class="arena-card-rank">' + ArenaCore.escapeHtml(isHidden ? card.hiddenLabel : ('段位 ' + card.index)) + '</span>';
            var oppCapText = isHidden ? '配置保密' : (isFallen ? '麾下阵容' : '对手阵容');
            var diffText = isHidden ? card.hiddenLabel : diff.label;
            var opponentText = isHidden ? '？？' : ('×' + card.opponentCount);
            var levelText = isHidden ? '？？' : (card.levelMin + '–' + card.levelMax);
            var extraMeta = isHidden
                ? '<span class="arena-prize-mult">收益 ×' + card.economyMultiplier + '</span>'
                : '';
            cardEl.setAttribute('aria-label', rankText + '，' + diffText
                + '，押金 ' + ArenaCore.formatMoney(card.deposit) + '，奖金 ' + ArenaCore.formatMoney(card.reward)
                + '，回车选中并预览');
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
                            '<span class="arena-prize-value">' + ArenaCore.formatMoney(card.reward) + '</span>' +
                            extraMeta +
                        '</div>' +
                        '<div class="arena-prize-deposit">押金 ' + ArenaCore.formatMoney(card.deposit) + '</div>' +
                    '</div>' +
                    // 对手摘要 row：snapshot 回包后 batchRequestPreview 触发全卡并发抽签，
                    // 单卡回包后 renderCardSummary(cardIdx) 写入下方 span。
                    '<div class="arena-card-opponents-row">' +
                        '<span class="arena-card-opponents-cap">' + oppCapText + '</span>' +
                        '<span class="arena-card-opponents arena-card-opponents-loading" id="arena-opp-summary-' + i + '">抽取中…</span>' +
                    '</div>' +
                '</div>';

            cardEl.addEventListener('click', onCardSelect);
            gridEl.appendChild(cardEl);
            S._cardEls.push(cardEl);
        }
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
                // P3：确认条 = 摘要体（随 render 重建）+ 持久动作脚（共享 CommitBar 承载主 CTA
                // 状态投影：busy/disabled/error；start 点击归 CommitBar.onCommit 单一持有）
                '<div class="arena-custom-confirm" id="arena-custom-confirm" hidden>' +
                    '<div class="arena-custom-confirm-body" id="arena-custom-confirm-body"></div>' +
                    '<div class="arena-custom-confirm-actions" id="arena-custom-confirm-actions"></div>' +
                '</div>' +
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

        // 卡片随 buildCards 重建：先销毁上一张卡的 CommitBar（listener 生命周期对齐卡片）
        if (S._customConfirmBar) { S._customConfirmBar.destroy(); S._customConfirmBar = null; }
        var confirmActionsEl = cardEl.querySelector('#arena-custom-confirm-actions');
        if (confirmActionsEl && typeof WorkbenchComponents !== 'undefined' && WorkbenchComponents.CommitBar) {
            var confirmCancelBtn = document.createElement('button');
            confirmCancelBtn.className = 'arena-custom-btn';
            confirmCancelBtn.type = 'button';
            confirmCancelBtn.textContent = '返回编辑';
            confirmCancelBtn.setAttribute('data-custom-confirm-action', 'cancel');
            confirmCancelBtn.setAttribute('data-audio-cue', 'cancel');
            confirmActionsEl.appendChild(confirmCancelBtn);
            S._customConfirmBar = new WorkbenchComponents.CommitBar({
                label: '确认委托',
                status: '',
                disabled: true,
                onCommit: function() { ArenaCustomEditor.startCustomMatch(); }
            });
            // 战术橙实心 CTA 视觉沿用 .arena-card-btn-enter 配方（与右栏决策 CommitBar 同款消费）
            S._customConfirmBar.primaryButton.classList.add('arena-card-btn-enter');
            S._customConfirmBar.primaryButton.setAttribute('data-custom-confirm-action', 'start');
            S._customConfirmBar.primaryButton.setAttribute('data-audio-cue', 'confirm');
            S._customConfirmBar.mount(confirmActionsEl);
        }

        cardEl.addEventListener('click', ArenaCustomEditor.onCustomWorkbenchClick);
        cardEl.querySelector('.arena-custom-generate').addEventListener('click', ArenaCustomEditor.onCustomGenerate);
        cardEl.querySelector('.arena-custom-abort').addEventListener('click', ArenaCustomEditor.onCustomAbort);
        return cardEl;
    }

    function resetCardRuntimeState() {
        S._previewCache = {};
        S._previewPending = {};
        S._previewGen = {};
        S._previewError = {};
        S._cardKind = {};
        S._monsterSquad = {};
        S._selectedCardIdx = -1;
        S._previewOpponents = null;
        // 选择随卡片集重建失效（P0 裁决 3：全部重抽/模式重建 → 整个决策面失效）
        renderDecisionEmpty();
    }

    function buildStandardSessionCards() {
        var cards = authorityCardsForModes({ standard: true, hidden: true });
        assignStandardPublicRoles(cards);
        return cards;
    }

    function assignStandardPublicRoles(cards) {
        var publicIdx = [];
        for (var i = 0; i < cards.length; i++) {
            if (cards[i].mode !== 'standard') continue;
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
            if (ArenaPreviewAuthority.teamHasHumanoidAndNonHuman(team)) return true;
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
            if (ArenaPreviewAuthority.teamHasOnlyNonHuman(team)) return true;
        }
        return false;
    }

    function authorityCardsForModes(modes) {
        var authority = S._snapshot && S._snapshot.arenaAuthority;
        var source = authority && authority.schemaVersion === 1 && Array.isArray(authority.cards)
            ? authority.cards : [];
        var cards = [];
        for (var i = 0; i < source.length; i++) {
            var raw = source[i];
            if (!raw || !modes[raw.mode] || typeof raw.id !== 'string') continue;
            // 角色/选中态会在 Web session 内附着，必须与 Host snapshot 脱离，禁止反向改写权威快照。
            var card = {};
            for (var key in raw) {
                if (Object.prototype.hasOwnProperty.call(raw, key)) card[key] = raw[key];
            }
            cards.push(card);
        }
        return cards;
    }

    // 按模式重建卡片集与 DOM，并复位 per-card 派生状态。不发请求（caller 决定何时 batch）。
    function rebuildForMode(mode) {
        if (mode !== 'custom') ArenaResult.clearCustomPoll();
        // 模式内滚动记忆：切走前存旧模式目录滚动位置，切回后恢复（卡片重建会重置 scrollTop）；
        // 全部重抽 / 新 session 已先把记忆归 0（新窗口显式归顶）。
        if (S._catalogGridEl && S._activeMode !== mode) S._catalogScroll[S._activeMode] = S._catalogGridEl.scrollTop;
        S._activeMode = mode;
        S._activeCards = (mode === 'fallen') ? buildFallenCards()
                     : (mode === 'escalation') ? buildEscalationCards()
                     : (mode === 'custom') ? [CUSTOM_MATCH_CARD]
                     : buildStandardSessionCards();
        // 切模式让所有卡 index 重新映射 → 旧 preview/kind/squad 缓存全部作废，避免跨模式串卡
        resetCardRuntimeState();
        // tab active 态
        var tabs = S._modesNav ? S._modesNav.querySelectorAll('.arena-mode-tab') : [];
        for (var i = 0; i < tabs.length; i++) {
            tabs[i].classList.toggle('arena-mode-tab-active', tabs[i].getAttribute('data-mode') === mode);
        }
        updateRerollAllButton();
        buildCards();       // 重建 grid DOM（_activeCards 驱动）+ 重挂卡片选中监听 + 摘要回 loading 态
        if (S._catalogGridEl) S._catalogGridEl.scrollTop = S._catalogScroll[mode] || 0;
        // 定制赛总览保持独立（D2）：壳 body 隐藏、总览覆盖 body 区，壳 header（tabs）保持可达；
        // 三挑战模式恢复双栏浏览面。
        var isCustom = (mode === 'custom');
        if (S._shellBodyEl) S._shellBodyEl.hidden = isCustom;
        if (S._customOverviewEl) S._customOverviewEl.hidden = !isCustom;
        if (isCustom) ArenaCustomEditor.refreshCustomMatchCard();
        ArenaShell.showGridView();
        updateCardStates();
    }

    function updateRerollAllButton() {
        if (!S._rerollAllBtn) return;
        var hidden = S._activeMode === 'custom';
        S._rerollAllBtn.hidden = hidden;
        S._rerollAllBtn.disabled = hidden || S._busy;
    }

    // 堕落/爬升卡也只投影 Host 权威快照；本地 roster 数据仅用于 WYSIWYG 采样与展示。
    function buildFallenCards() {
        var cards = authorityCardsForModes({ fallen: true });
        cards.sort(function(a, b) { return (a.levelMin - b.levelMin) || (a.levelMax - b.levelMax); });
        return cards;
    }

    function buildEscalationCards() {
        var cards = authorityCardsForModes({ escalation: true });
        cards.sort(function(a, b) { return (a.levelMin - b.levelMin) || (a.levelMax - b.levelMax); });
        return cards;
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 交互（P2：卡片 = 选中语义；commit 只从右栏确认区发起，选中卡 Enter/Space 为同一
    // handler 的快捷键别名——P0 裁决 2）
    // ════════════════════════════════════════════════════════════════════════════
    function onCardSelect(e) {
        // 摘要 ↻ 重试等嵌套控件已 stopPropagation；卡面点击 = 纯选中（本地意图，零写入）
        var idx = parseInt(e.currentTarget.getAttribute('data-index'), 10);
        selectCard(idx);
    }

    function selectCard(idx) {
        if (S._busy) return;
        var card = S._activeCards[idx];
        if (!card || card.isCustom) return;
        if (S._selectedCardIdx === idx) return;  // 重复选中：右栏已是该卡 preview，幂等
        S._selectedCardIdx = idx;
        updateCardSelection();
        renderDecisionForCard(idx);
    }

    // 选中态投影：class + aria-selected 双写（selected 边框走 --wb-role-selected，不覆盖 focus 环）
    function updateCardSelection() {
        for (var i = 0; i < S._cardEls.length; i++) {
            var cardEl = S._cardEls[i];
            if (!cardEl || !cardEl.classList || !cardEl.classList.contains('arena-card')) continue;
            var selected = (i === S._selectedCardIdx);
            cardEl.classList.toggle('arena-card-selected', selected);
            cardEl.setAttribute('aria-selected', selected ? 'true' : 'false');
        }
    }

    // 右栏决策面空态（{kind, statement, nextStep} 语义）：未选卡 / 选择失效后的归宿
    function renderDecisionEmpty() {
        S._previewOpponents = null;
        if (S._detailTitleEl) S._detailTitleEl.textContent = '选择挑战';
        if (S._detailMetaEl) S._detailMetaEl.innerHTML = '';
        if (S._detailOpponentsEl) {
            S._detailOpponentsEl.innerHTML =
                '<div class="arena-decision-empty">' +
                    '<div class="arena-decision-empty-statement">从左侧目录选择一场挑战</div>' +
                    '<div class="arena-decision-empty-next">阵容、风险、押金与奖励在确认前于此核对</div>' +
                '</div>';
        }
        updateCommitBar();
    }

    // 右栏持续 preview：复用旧 detail 视图的信息内容（标题 / meta 芯片 / 对手行）。
    // cache 命中直接渲（WYSIWYG：目录摘要里那批人）；miss 则 loading + 经 dedup 等同一回包 fan out。
    function renderDecisionForCard(idx) {
        var card = S._activeCards[idx];
        if (!card) return;

        S._detailTitleEl.textContent = card.isEscalation
            ? (card.faction + ' · 爬升挑战（无限波 · 奖池押注）')
            : card.isFallen
                ? (card.faction + ' · ' + ArenaCore.difficultyOf(card).label + ' 挑战')
                : card.isHiddenChallenge
                    ? ('DEATH MATCH · ' + card.hiddenLabel)
                    : ('DEATH MATCH · 段位 ' + card.index + ' · ' + ArenaCore.difficultyOf(card).label);

        // 隐藏警报卡：配置保密（现状钉版——旧 detail 按钮禁用 = 不可查看阵容）；
        // 经济面公开，commit 可用性照旧由本地混编 cache 决定。
        if (card.isHiddenChallenge) {
            renderDetailMeta(card, null);
            S._previewOpponents = null;
            S._detailOpponentsEl.innerHTML =
                '<div class="arena-opponents-loading">隐藏警报配置保密；对手已抽取，确认后直接迎战</div>';
            updateCommitBar();
            return;
        }

        renderDetailMeta(card, S._previewCache[idx] || null);
        if (S._previewCache[idx]) {
            S._previewOpponents = S._previewCache[idx];
            renderOpponents(S._previewCache[idx]);
            updateCommitBar();
            return;
        }

        S._previewOpponents = null;
        if (S._previewError[idx]) {
            // 失败态只投影原因、不自动重发：选中是高频浏览动作，自动重试会让失败态一闪而过；
            // 显式重试走目录摘要 ↻ 或左栏「换一批」（行为合同见 grid-single-fail-retry 用例）
            S._detailOpponentsEl.innerHTML = '<div class="arena-opponents-error">' + ArenaCore.escapeHtml(S._previewError[idx]) + '</div>';
            updateCommitBar();
            return;
        }
        S._detailOpponentsEl.innerHTML = '<div class="arena-opponents-loading">正在抽取对手…</div>';
        updateCommitBar();
        ArenaPreviewAuthority.requestPreviewForCard(idx); // dedup 内部处理：pending 中则不重发，等回包 fan out 到右栏
    }

    // 决策面唯一主 CTA 的可用性投影（§5.3：提交状态与阻断原因位于非滚动 decision footer）。
    // busy / 未选 / preview 未到 / 抽取失败 / 金钱不足逐档给出可读原因；enter 飞行中 busy。
    function updateCommitBar() {
        if (!S._commitBar) return;
        var idx = S._selectedCardIdx;
        var card = (idx >= 0) ? S._activeCards[idx] : null;
        if (S._rollOneBtn) {
            // 换一批 = 单卡重抽选中卡；隐藏卡无阵容可展示、堕落/爬升与标准卡均可重抽（旧 detail 同款能力面）
            S._rollOneBtn.disabled = S._busy || !card || card.isCustom || !!card.isHiddenChallenge;
        }
        if (S._busy) {
            S._commitBar.update({ busy: true, status: '挑战发起中…', state: 'busy' });
            return;
        }
        if (!card || card.isCustom) {
            S._commitBar.update({ status: '选择左侧挑战后确认', canCommit: false, state: '', busy: false });
            return;
        }
        if (S._previewError[idx]) {
            S._commitBar.update({ status: '对手抽取失败：' + S._previewError[idx], canCommit: false, state: 'error', busy: false });
            return;
        }
        var opponents = S._previewCache[idx];
        if (!opponents || opponents.length === 0) {
            // 含「单卡重抽后新 preview 未到达」档（裁决 3：该期间该卡 commit 禁用）
            S._commitBar.update({ status: '正在抽取对手…', canCommit: false, state: '', busy: false });
            return;
        }
        var money = (S._snapshot && S._snapshot.money != null) ? S._snapshot.money : null;
        if (money != null && money < card.deposit) {
            S._commitBar.update({ status: '金钱不足（押金 ' + ArenaCore.formatMoney(card.deposit) + '）', canCommit: false, state: 'blocked', busy: false });
            return;
        }
        S._commitBar.update({
            status: '押金 ' + ArenaCore.formatMoney(card.deposit) + ' · 奖金 ' + ArenaCore.formatMoney(card.reward),
            canCommit: true, state: 'ready', busy: false
        });
    }

    // 目录键盘语义（最小列表语义，§5 不做 roving 网格导航）：
    // 方向键上下/左右 = 线性移动选择（焦点跟随）；Enter/Space：未选中卡 = 选中（固定预览），
    // 已选中卡 = 与右栏 CommitBar 同一个 commit handler（keyboard-commit，P0 裁决 2）。
    function onGridKeydown(e) {
        if (S._busy) return;
        var cardEl = (e.target && e.target.closest) ? e.target.closest('.arena-card') : null;
        if (!cardEl || !S._catalogGridEl.contains(cardEl)) return;
        var idx = parseInt(cardEl.getAttribute('data-index'), 10);
        var card = S._activeCards[idx];
        if (!card || card.isCustom) return;
        if (e.key === 'Enter' || e.key === ' ' || e.key === 'Spacebar') {
            e.preventDefault();
            if (idx !== S._selectedCardIdx) selectCard(idx);
            else commitSelectedChallenge();
            return;
        }
        var next = -1;
        if (e.key === 'ArrowDown' || e.key === 'ArrowRight') next = idx + 1;
        else if (e.key === 'ArrowUp' || e.key === 'ArrowLeft') next = idx - 1;
        else if (e.key === 'Home') next = 0;
        else if (e.key === 'End') next = S._activeCards.length - 1;
        if (next < 0) return;
        e.preventDefault();
        next = Math.max(0, Math.min(S._activeCards.length - 1, next));
        if (next === idx || S._activeCards[next].isCustom) return;
        selectCard(next);
        var nextEl = S._cardEls[next];
        if (nextEl && nextEl.focus) nextEl.focus();
    }

    // P0 裁决 2：右栏 CommitBar 主 CTA 与选中卡 Enter/Space 共用的同一 commit handler。
    // 可用性门（busy/选中/preview/金钱）已由 updateCommitBar 投影，这里同序复核（键盘路径直达）。
    function commitSelectedChallenge() {
        if (S._busy) return;
        var idx = S._selectedCardIdx;
        if (idx < 0) return;
        var card = S._activeCards[idx];
        if (!card || card.isCustom) return;
        var opponents = S._previewCache[idx];
        if (!opponents || opponents.length === 0) return; // preview 未到/失败：右栏已禁用并给原因
        enterChallenge(idx, card, opponents);
    }

    function onRollAgain() {
        if (S._busy || S._selectedCardIdx < 0) return;
        var idx = S._selectedCardIdx;
        var card = S._activeCards[idx];
        if (!card || card.isCustom || card.isHiddenChallenge) return;
        // 单卡重抽（P0 裁决 3）：保留卡位与选中；清 cache 即断该卡 commit 可用性，
        // 新 preview 到达前 CommitBar 停「正在抽取对手…」；迟到回包由三元组隔离丢弃。
        delete S._previewPending[idx];
        delete S._previewCache[idx];
        delete S._previewError[idx];
        delete S._cardKind[idx];
        delete S._monsterSquad[idx];
        S._previewGen[idx] = (S._previewGen[idx] || 0) + 1;
        S._previewOpponents = null;
        S._detailOpponentsEl.innerHTML = '<div class="arena-opponents-loading">正在重新抽取…</div>';
        updateCommitBar();
        ArenaPreviewAuthority.requestPreviewForCard(idx);
    }

    function onRerollAll() {
        if (S._busy || S._activeMode === 'custom') return;
        // 全部重抽（P0 裁决 3）：整个决策面失效——resetCardRuntimeState 清空 selection 与
        // commit 可用性（右栏归空态）；新一批构成新窗口，目录滚动显式归顶。
        S._catalogScroll[S._activeMode] = 0;
        if (S._activeMode === 'standard') {
            resetCardRuntimeState();
            S._activeCards = [];
            buildCards();
            ArenaPreviewAuthority.requestSnapshot();
            ArenaCore.showToast('正在获取新的权威挑战批次');
            return;
        } else {
            resetCardRuntimeState();
            buildCards();
            ArenaShell.showGridView();
            updateCardStates();
        }
        if (S._snapshot) ArenaPreviewAuthority.batchRequestPreview();
        ArenaCore.showToast(S._activeMode === 'standard' ? '已重新抽取全部挑战' : '已重新抽取全部对手');
    }

    // 稳定卡 ID（三元组之一）：堕落/爬升卡带业务 id（fallen-势力 / esc-势力），
    // 隐藏卡用 hiddenLabel，标准公开卡用段位号。卡 index 跨重建会重映射，卡 ID 不随位置漂移。
    function stableCardKey(card) {
        if (!card) return '';
        if (card.isHiddenChallenge) return 'hidden:' + (card.hiddenLabel || card.index);
        if (card.id) return String(card.id);
        return 'std:' + card.index;
    }

    // 入场链公共函数：右栏 CommitBar / 选中卡 Enter/Space 经 commitSelectedChallenge 汇入。
    // 接口约定：opponents 由 caller 传入（= _previewCache[idx]），本函数不关心来源。
    // busy UI 反馈统一走 updateCardStates → updateCommitBar（busy 投影 + 目录控件禁用）。
    function enterChallenge(cardIdx, card, opponents) {
        if (S._busy || cardIdx < 0 || !card || !opponents || opponents.length === 0) return;
        if (S._snapshot && S._snapshot.money != null && S._snapshot.money < card.deposit) {
            ArenaCore.showToast('金钱不足！');
            return;
        }

        S._busy = true;
        updateCardStates(); // _busy → CommitBar busy 投影 + 重抽控件禁用
        if (S._shell) S._shell.setStatus('挑战发起中', Workbench.WorkbenchState.PENDING);

        var reqId = 'arena_ent_' + (++S._reqSeq) + '_' + S._session;
        S._pendingReq[reqId] = function(data) {
            S._busy = false;
            updateCardStates();
            if (S._shell) S._shell.setStatus('待命', Workbench.WorkbenchState.IDLE);
            if (!data.success) {
                ArenaCore.showToast(data.error || '挑战发起失败');
                return;
            }
            // closePanel:true → 必须走 requestClose 而不是裸 Panels.close()，
            // 因为后者只关 web 端 UI，不通知 C# 收 PanelHost；不收的话 WebOverlay
            // 还停在 opaque/panelRect 模式遮盖 Flash → AS2 已转场但视觉黑屏。
            // dismissReturnStack=true：AS2 已跳关到 wuxianguotu_1，必须清整个返回链；
            // 否则 PanelHostController 会 pop 出 stage-select 重新打开遮挡战场视野。
            if (data.closePanel) ArenaShell.requestClose({ dismissReturnStack: true });
        };

        var msg = {
            type: 'panel',
            panel: 'arena',
            cmd: 'enter',
            callId: reqId,
            cardId: card.id,
            cardIndex: cardIdx,
            // 来自 stage-select 重定向时是 "冒险"/"修罗" 等；dev 直开时是 ""。
            // AS2 ArenaPanelService 在非空时设 _root.当前关卡难度，让任务系统能匹配。
            difficulty: S._initDifficulty
        };
        // 爬升池、波数和经济均由 C# 按 cardId 注入；Web 不下发任何权威参数。
        if (card.isEscalation) {
            // 无额外字段。
        }
        // roster 卡（堕落/标准混入/隐藏混编）：把本地采样的小队作为 roster 下发 → AS2 走 commitRoster 生成混合阵容。
        // WYSIWYG：下发的就是 grid/detail 预览里那批怪（兵种 type 或 mercId + level 一一对应）。
        else if ((S._cardKind[cardIdx] === 'monster' || S._cardKind[cardIdx] === 'mixed')) {
            var roster = [];
            for (var ri = 0; ri < opponents.length; ri++) {
                var rosterEntry = null;
                if (opponents[ri].mercId != null) {
                    rosterEntry = { kind: 'merc', mercId: opponents[ri].mercId, level: opponents[ri].level };
                } else if (opponents[ri].type) {
                    rosterEntry = { type: opponents[ri].type, level: opponents[ri].level };
                }
                if (!rosterEntry) continue;
                if (ArenaCustomEditor.customHasParameters(opponents[ri].parameters)) rosterEntry.parameters = ArenaCustomEditor.cloneCustomParameters(opponents[ri].parameters);
                roster.push(rosterEntry);
            }
            if (roster.length) msg.roster = roster;
        }
        Bridge.send(msg);
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 消息处理
    // ════════════════════════════════════════════════════════════════════════════
    Bridge.on('panel_resp', function(data) {
        if (!data || data.panel !== 'arena') return;
        var cb = S._pendingReq[data.callId];
        if (cb) {
            delete S._pendingReq[data.callId];
            cb(data);
        }
    });

    // 渲染单卡 grid 摘要 row：≤2 名全显，>2 名头 2 + "+N"。
    // 失败态显示 "⚠ ... ↻" 可点击重试。loading 态由 requestPreviewForCard 入口统一写。
    function renderCardSummary(cardIdx) {
        var sumEl = document.getElementById('arena-opp-summary-' + cardIdx);
        if (!sumEl) return;

        if (S._previewError[cardIdx]) {
            sumEl.className = 'arena-card-opponents arena-card-opponents-error';
            sumEl.textContent = '⚠ ' + S._previewError[cardIdx] + ' ↻';
            sumEl.setAttribute('data-retry-idx', cardIdx);
            sumEl.onclick = onSummaryRetry; // onclick 自动 dedup 重复绑定
            return;
        }

        var opps = S._previewCache[cardIdx];
        if (!opps || opps.length === 0) {
            sumEl.className = 'arena-card-opponents arena-card-opponents-loading';
            sumEl.textContent = '抽取中…';
            sumEl.onclick = null;
            return;
        }

        sumEl.className = 'arena-card-opponents';
        sumEl.onclick = null;
        var card = S._activeCards[cardIdx];
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
        delete S._previewPending[idx]; // 强制重发：清 dedup token 让 requestPreviewForCard 重新发
        delete S._cardKind[idx];       // 重抽可重新决定种类（失败的 merc 卡可翻成稳成功的 monster 卡）
        delete S._monsterSquad[idx];
        S._previewGen[idx] = (S._previewGen[idx] || 0) + 1; // 三元组 generation 递增，旧回包隔离
        if (S._selectedCardIdx === idx) {
            S._detailOpponentsEl.innerHTML = '<div class="arena-opponents-loading">正在抽取对手…</div>';
            updateCommitBar();
        }
        ArenaPreviewAuthority.requestPreviewForCard(idx);
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
        if (!S._detailMetaEl || !card) return;
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
            '<span class="arena-meta-chip arena-meta-deposit">押金 ' + ArenaCore.formatMoney(card.deposit) + '</span>' +
            '<span class="arena-meta-chip arena-meta-reward">奖金 ' + ArenaCore.formatMoney(card.reward) + '</span>';
        S._detailMetaEl.innerHTML = html;
    }

    // roster 小队（M2）：无装备/技能，渲简版行（头像 + 名/级 + roster 标 + 家族注）。
    function renderMonsterOpponents(opponents) {
        var card = (S._selectedCardIdx >= 0) ? S._activeCards[S._selectedCardIdx] : null;
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
            var noteText = ArenaPreviewAuthority.rosterDisplaySpritename(opp);
            if (opp.sourceGroupName && opp.rosterKind !== 'humanoid') noteText += ' · ' + opp.sourceGroupName;
            html += '<div class="arena-opp-row arena-opp-row-monster">';
            html += '<div class="arena-opp-portrait arena-opp-portrait-fallback arena-opp-portrait-monster"></div>';
            html += '<div class="arena-opp-main">';
            html += '<div class="arena-opp-topline">';
            html += '<span class="arena-opp-name">' + ArenaCore.escapeHtml(opp.name) + '</span>';
            html += '<span class="arena-opp-level">LV. ' + opp.level + '</span>';
            html += '<span class="arena-opp-monster-tag">' + ArenaCore.escapeHtml(tagText) + '</span>';
            html += '</div>';
            html += '<div class="arena-opp-monster-note">' + ArenaCore.escapeHtml(noteText) + '</div>';
            html += '</div></div>';
        }
        S._detailOpponentsEl.innerHTML = html;
    }

    function renderOpponents(opponents) {
        var card = (S._selectedCardIdx >= 0) ? S._activeCards[S._selectedCardIdx] : null;
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
            html += '<span class="arena-opp-name">' + ArenaCore.escapeHtml(opp.name) + '</span>';
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
                        : '<span class="arena-equip-fallback">' + ArenaCore.escapeHtml(displayName.charAt(0)) + '</span>';
                    // 不设 title 属性：避免浏览器原生 tooltip 与 PanelTooltip 富文本重叠显示
                    html += '<div class="arena-equip-cell"' +
                            ' data-eq-raw="' + ArenaCore.escapeAttr(raw) + '"' +
                            ' data-eq-displayname="' + ArenaCore.escapeAttr(displayName) + '"' +
                            ' data-eq-icon="' + ArenaCore.escapeAttr(iconKey) + '"' +
                            ' data-eq-level="' + eq.level + '">' +
                            iconHtml +
                            '<span class="arena-equip-level">' + eq.level + '</span>' +
                        '</div>';
                } else {
                    // 空槽位保留 title — 没有富文本 tooltip 可覆盖，原生提示就是 fallback
                    html += '<div class="arena-equip-cell arena-equip-empty" title="' + ArenaCore.escapeAttr(SLOT_LABELS[slot] || '') + '"></div>';
                }
            }
            html += '</div>'; // equips
            // 技能行：复用战队-佣兵界面技能成果（烘焙图标 + 占位字 + 等级 + hover tooltip）
            html += buildOppSkillsHtml(opp.skills);
            html += '</div>'; // arena-opp-main
            html += '</div>'; // arena-opp-row
        }
        S._detailOpponentsEl.innerHTML = html;

        // 装备 hover → tooltip
        var cells = S._detailOpponentsEl.querySelectorAll('.arena-equip-cell[data-eq-raw]');
        for (var c = 0; c < cells.length; c++) {
            cells[c].addEventListener('mouseenter', onEquipHover);
            cells[c].addEventListener('mouseleave', onEquipLeave);
            cells[c].addEventListener('mousemove', onEquipMove);
        }
        // 技能 hover → tooltip + 烘焙图加载失败回退占位字
        var skillCells = S._detailOpponentsEl.querySelectorAll('.arena-skill-cell[data-skill-name]');
        for (var sc = 0; sc < skillCells.length; sc++) {
            skillCells[sc].addEventListener('mouseenter', onSkillHover);
            skillCells[sc].addEventListener('mouseleave', onSkillLeave);
            skillCells[sc].addEventListener('mousemove', onEquipMove);
        }
        var skillImgs = S._detailOpponentsEl.querySelectorAll('.arena-skill-cell-baked .arena-skill-icon');
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
                ' data-skill-name="' + ArenaCore.escapeAttr(name) + '"' +
                ' data-skill-level="' + level + '"' +
                ' data-skill-type="' + ArenaCore.escapeAttr(String(sk.type || '')) + '"' +
                ' data-skill-trait="' + ArenaCore.escapeAttr(String(sk.trait || '')) + '"' +
                ' data-skill-cd="' + (sk.cooldown || 0) + '"' +
                ' data-skill-cost="' + (sk.cost || 0) + '">' +
                '<span class="arena-skill-glyph">' + ArenaCore.escapeHtml(String(sk.type || '技').charAt(0)) + '</span>' +
                imgHtml +
                '<span class="arena-skill-level">' + level + '</span>' +
            '</div>';
    }

    function onSkillHover(e) {
        var c = e.currentTarget;
        var type = c.getAttribute('data-skill-type') || '';
        var trait = c.getAttribute('data-skill-trait') || '';
        var html = '<div class="kshop-tt-rich"><div class="kshop-tt-desc">' +
                '<div class="kshop-tt-header"><b>' + ArenaCore.escapeHtml(c.getAttribute('data-skill-name') || '') + '</b>' +
                    ' <span class="kshop-tt-dim">Lv.' + (c.getAttribute('data-skill-level') || '1') + '</span></div>' +
                '<div class="kshop-tt-dim">' + ArenaCore.escapeHtml(type + (trait ? ' · ' + trait : '')) + '</div>' +
                '<div class="kshop-tt-dim">冷却 ' + (c.getAttribute('data-skill-cd') || '0') + 's · 消耗 ' + (c.getAttribute('data-skill-cost') || '0') + ' MP</div>' +
            '</div></div>';
        PanelTooltip.showAtMouse(html, e);
    }

    function onSkillLeave() {
        PanelTooltip.hideHover();
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
        S._ttHoverKey = key;

        var cached = S._ttCache[key];
        var html = cached
            ? buildRichTooltipHtml(cached, iconKey)
            : buildBasicTooltipHtml(displayName, level, iconKey);
        PanelTooltip.showAtMouse(html, e);
        if (!cached) requestEquipTooltip(raw, level, key, iconKey);
    }

    function onEquipLeave() {
        S._ttHoverKey = null;
        PanelTooltip.hideHover();
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
                    '<div class="kshop-tt-header"><b>' + ArenaCore.escapeHtml(displayName) + '</b>' +
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
        var reqId = 'arena_tt_' + (++S._reqSeq) + '_' + S._session;
        S._pendingReq[reqId] = function(resp) {
            if (!resp.success) return;
            S._ttCache[key] = {
                descHTML: resp.descHTML || '',
                introHTML: resp.introHTML || '',
                displayname: resp.displayname || '',
                itemName: resp.itemName || raw
            };
            // 仍 hover 在同一 cell 才更新
            if (S._ttHoverKey === key && PanelTooltip.isVisible() && Panels.isOpen()) {
                PanelTooltip.updateContent(buildRichTooltipHtml(S._ttCache[key], iconKey));
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
            S._moneyEl.textContent = '--';
            return;
        }
        S._moneyEl.textContent = ArenaCore.formatMoney(money);
    }

    // 卡片状态机（P2）：卡面不再承载按钮，逐卡状态只剩两个投影
    //   - 整卡灰类 arena-card-disabled：仅按 money 判断（视觉降权，不阻断选中/查看——
    //     钱不够也允许选中看阵容，commit 阻断原因由右栏 CommitBar 投影）
    //   - 选中态 arena-card-selected + aria-selected（updateCardSelection）
    // commit 可用性统一归 updateCommitBar（busy / 选中 / preview / 金钱逐档判定）。
    function updateCardStates() {
        updateRerollAllButton();
        var money = (S._snapshot && S._snapshot.money != null) ? S._snapshot.money : null;
        for (var i = 0; i < S._activeCards.length; i++) {
            if (S._activeCards[i].isCustom) {
                ArenaCustomEditor.refreshCustomMatchCard();
                continue;
            }
            var deposit = S._activeCards[i].deposit;
            setCardVisualDisabled(i, money != null && money < deposit);
        }
        updateCardSelection();
        updateCommitBar();
    }

    function setCardVisualDisabled(index, disabled) {
        var cardEl = S._cardEls[index];
        if (!cardEl) return;
        cardEl.classList.toggle('arena-card-disabled', disabled);
    }

    // 导出：仅被其它 arena 模块 / facade 引用的名字
    window.ArenaChallengeBrowser = {
        STANDARD_OPPONENT_CAP: STANDARD_OPPONENT_CAP,
        HIDDEN_MIXED_TEAM_MAX_UNITS: HIDDEN_MIXED_TEAM_MAX_UNITS,
        buildBrowseViews: buildBrowseViews,
        buildCards: buildCards,
        resetCardRuntimeState: resetCardRuntimeState,
        rebuildForMode: rebuildForMode,
        buildFallenCards: buildFallenCards,
        stableCardKey: stableCardKey,
        renderCardSummary: renderCardSummary,
        renderDetailMeta: renderDetailMeta,
        renderOpponents: renderOpponents,
        updateMoneyDisplay: updateMoneyDisplay,
        updateCardStates: updateCardStates
    };
})();
