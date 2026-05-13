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
                '</div>' +
                '<button class="arena-card-btn" type="button" data-index="' + i + '" data-audio-cue="confirm">查看对手 →</button>';

            cardEl.querySelector('.arena-card-btn').addEventListener('click', onCardClick);
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
        hideToast();
        updateMoneyDisplay(null);
        updateCardStates();
        showGridView();
        requestSnapshot();
    }

    function requestClose() {
        if (_busy) return;
        Panels.close();
        Bridge.send({ type: 'panel', panel: 'arena', cmd: 'close' });
    }

    function onClose() {
        _pendingReq = {};
        _busy = false;
        _snapshot = null;
        _activeCardIdx = -1;
        _previewOpponents = null;
        _ttCache = {};
        _ttHoverKey = null;
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

        var idx = parseInt(e.target.dataset.index, 10);
        var card = ARENA_CARDS[idx];
        if (!card) return;

        _activeCardIdx = idx;
        _previewOpponents = null;

        // 切到详情视图：先显示骨架，preview 回包再渲染对手
        _detailTitleEl.textContent = card.name + ' · 卡片 ' + card.index;
        _detailMetaEl.innerHTML =
            '<span class="arena-meta-chip">对手 ×' + card.opponentCount + '</span>' +
            '<span class="arena-meta-chip">等级 ' + card.levelMin + '—' + card.levelMax + '</span>' +
            '<span class="arena-meta-chip arena-meta-deposit">押金 ' + formatMoney(card.deposit) + '</span>' +
            '<span class="arena-meta-chip arena-meta-reward">奖金 ' + formatMoney(card.reward) + '</span>';
        _detailOpponentsEl.innerHTML = '<div class="arena-opponents-loading">正在抽取对手…</div>';
        setDetailButtonsBusy(true);
        showDetailView();
        requestPreview(card);
    }

    function onRollAgain() {
        if (_busy || _activeCardIdx < 0) return;
        var card = ARENA_CARDS[_activeCardIdx];
        if (!card) return;
        _detailOpponentsEl.innerHTML = '<div class="arena-opponents-loading">正在重新抽取…</div>';
        setDetailButtonsBusy(true);
        requestPreview(card);
    }

    function onConfirmChallenge() {
        if (_busy || _activeCardIdx < 0 || !_previewOpponents) return;
        var card = ARENA_CARDS[_activeCardIdx];
        if (!card) return;

        if (_snapshot && _snapshot.money != null && _snapshot.money < card.deposit) {
            showToast('金钱不足！');
            return;
        }

        _busy = true;
        setDetailButtonsBusy(true);

        var reqId = 'arena_ent_' + (++_reqSeq) + '_' + _session;
        _pendingReq[reqId] = function(data) {
            _busy = false;
            setDetailButtonsBusy(false);
            if (!data.success) {
                showToast(data.error || '挑战发起失败');
                return;
            }
            // closePanel:true → 必须走 requestClose 而不是裸 Panels.close()，
            // 因为后者只关 web 端 UI，不通知 C# 收 PanelHost；不收的话 WebOverlay
            // 还停在 opaque/panelRect 模式遮盖 Flash → AS2 已转场但视觉黑屏。
            if (data.closePanel) requestClose();
        };

        Bridge.send({
            type: 'panel',
            panel: 'arena',
            cmd: 'enter',
            callId: reqId,
            cardIndex: _activeCardIdx,
            expr: card.expr,
            deposit: card.deposit,
            reward: card.reward
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
        _pendingReq[reqId] = function(data) {
            if (data.success && data.snapshot) {
                _snapshot = data.snapshot;
                updateMoneyDisplay(_snapshot.money);
                updateCardStates();
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
    // Preview
    // ════════════════════════════════════════════════════════════════════════════
    function requestPreview(card) {
        var reqId = 'arena_prev_' + (++_reqSeq) + '_' + _session;
        var pendingCardIdx = _activeCardIdx; // 闭包捕获，防止抽取返回时已切回 grid
        _pendingReq[reqId] = function(data) {
            // 若用户已经返回 grid 或切到其他卡片，丢弃这个回包
            if (_activeCardIdx !== pendingCardIdx) return;

            if (!data.success || !data.opponents) {
                _detailOpponentsEl.innerHTML = '<div class="arena-opponents-error">' + escapeHtml(data.error || '抽取失败') + '</div>';
                setDetailButtonsBusy(false);
                _detailConfirmBtn.disabled = true;
                return;
            }
            _previewOpponents = data.opponents;
            renderOpponents(data.opponents);
            setDetailButtonsBusy(false);
        };
        Bridge.send({
            type: 'panel',
            panel: 'arena',
            cmd: 'preview',
            callId: reqId,
            expr: card.expr
        });
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

    function updateCardStates() {
        if (!_snapshot || _snapshot.money == null) {
            for (var i = 0; i < _cardEls.length; i++) {
                setCardEnabled(i, true);
            }
            return;
        }
        var money = _snapshot.money;
        for (var j = 0; j < ARENA_CARDS.length; j++) {
            setCardEnabled(j, money >= ARENA_CARDS[j].deposit);
        }
    }

    function setCardEnabled(index, enabled) {
        var cardEl = _cardEls[index];
        if (!cardEl) return;
        var btn = cardEl.querySelector('.arena-card-btn');
        if (enabled) {
            cardEl.classList.remove('arena-card-disabled');
            btn.disabled = false;
            btn.textContent = '查看对手 →';
        } else {
            cardEl.classList.add('arena-card-disabled');
            btn.disabled = true;
            btn.textContent = '金钱不足';
        }
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

    var _toastTimer = null;

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
            pendingCount: Object.keys(_pendingReq).length
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
