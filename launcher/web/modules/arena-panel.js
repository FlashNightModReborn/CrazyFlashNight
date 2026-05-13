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
    var _headerEl;
    var _gridEl;
    var _moneyEl;
    var _cardEls = [];
    var _pendingReq = {};
    var _reqSeq = 0;
    var _session = 0;
    var _snapshot = null;
    var _busy = false;

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
            '<div class="arena-grid" id="arena-grid"></div>' +
            '<div class="arena-toast" id="arena-toast"></div>';

        _headerEl = _el.querySelector('.arena-header');
        _gridEl = _el.querySelector('#arena-grid');
        _moneyEl = _el.querySelector('#arena-money-value');

        _el.querySelector('.arena-close-btn').addEventListener('click', requestClose);

        buildCards();
        return _el;
    }

    function buildCards() {
        _gridEl.innerHTML = '';
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
                '<button class="arena-card-btn" type="button" data-index="' + i + '" data-audio-cue="confirm">开始挑战</button>';

            cardEl.querySelector('.arena-card-btn').addEventListener('click', onCardClick);
            _gridEl.appendChild(cardEl);
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
        hideToast();
        updateMoneyDisplay(null);
        updateCardStates();
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
        hideToast();
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

        if (_snapshot && _snapshot.money != null && _snapshot.money < card.deposit) {
            showToast('金钱不足！');
            return;
        }

        _busy = true;
        setCardBusy(idx, true);

        var reqId = 'arena_ent_' + (++_reqSeq) + '_' + _session;
        _pendingReq[reqId] = function(data) {
            _busy = false;
            setCardBusy(idx, false);
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
            cardIndex: idx,
            expr: card.expr,
            deposit: card.deposit,
            reward: card.reward
        });
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
    // Snapshot 与 UI 更新
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
            btn.textContent = '开始挑战';
        } else {
            cardEl.classList.add('arena-card-disabled');
            btn.disabled = true;
            btn.textContent = '金钱不足';
        }
    }

    function setCardBusy(index, busy) {
        var cardEl = _cardEls[index];
        if (!cardEl) return;
        var btn = cardEl.querySelector('.arena-card-btn');
        if (busy) {
            btn.disabled = true;
            btn.textContent = '请稍候...';
        } else {
            btn.disabled = false;
            btn.textContent = '开始挑战';
            updateCardStates();
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

    // ════════════════════════════════════════════════════════════════════════════
    // 调试接口（harness / QA 用）
    // ════════════════════════════════════════════════════════════════════════════
    function _debugGetState() {
        return {
            session: _session,
            busy: _busy,
            snapshot: _snapshot,
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
