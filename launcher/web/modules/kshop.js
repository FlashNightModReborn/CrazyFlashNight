/**
 * KShop — K点商城面板
 *
 * 数据流: SHOP 按钮 → C# shopPanelOpen → panel_cmd open → KShop.onOpen
 *         → bulkQuery → Flash 回包 → 渲染商品列表
 * 关闭:   ESC/遮罩/关闭按钮 → requestClose → saveCart → close → shopPanelClose
 */
var KShop = (function() {
    'use strict';

    var _catalog = [];
    var _cart = [];           // [{idx, qty}, ...]
    var _purchased = [];
    var _kpoints = 0;
    var _playerLevel = 0;
    var _reverseLevel = 0;
    var _reqSeq = 0;
    var _pendingReq = {};
    var _closing = false;
    var _checkingOut = false;
    var _activeCategory = null;
    var _categories = [];

    // DOM refs (created once)
    var _el, _catBar, _grid, _cartPanel, _cartList, _cartTotal, _balanceEl, _tooltip;
    var _checkoutBtn, _claimList;

    var _iconsLoaded = false;
    var _kHandler = function(v) { _kpoints = Number(v); if (_balanceEl) _balanceEl.textContent = _kpoints; };

    // ── Panel registration ──
    console.log('[KShop] Registering panel');
    Panels.register('kshop', {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: function() { requestClose(); }
    });

    function createDOM(container) {
        _el = document.createElement('div');
        _el.className = 'kshop-panel';
        _el.innerHTML =
            '<div class="kshop-header">' +
                '<span class="kshop-title">K\u70b9\u5546\u57ce</span>' +
                '<span class="kshop-balance">K\u70b9: <b id="kshop-kpoints">0</b></span>' +
                '<button class="kshop-close-btn">\u00d7</button>' +
            '</div>' +
            '<div class="kshop-categories" id="kshop-cat-bar"></div>' +
            '<div class="kshop-body">' +
                '<div class="kshop-grid" id="kshop-grid"></div>' +
                '<div class="kshop-sidebar">' +
                    '<div class="kshop-cart-header">\u8d2d\u7269\u8f66</div>' +
                    '<div class="kshop-cart-list" id="kshop-cart-list"></div>' +
                    '<div class="kshop-cart-footer">' +
                        '<span>\u5408\u8ba1: <b id="kshop-cart-total">0</b></span>' +
                        '<button class="kshop-checkout-btn" id="kshop-checkout">\u7ed3\u8d26</button>' +
                    '</div>' +
                    '<div class="kshop-claim-header">\u5df2\u8d2d\u4e70</div>' +
                    '<div class="kshop-claim-list" id="kshop-claim-list"></div>' +
                '</div>' +
            '</div>';

        _balanceEl = _el.querySelector('#kshop-kpoints');
        _catBar = _el.querySelector('#kshop-cat-bar');
        _grid = _el.querySelector('#kshop-grid');
        _cartList = _el.querySelector('#kshop-cart-list');
        _cartTotal = _el.querySelector('#kshop-cart-total');
        _checkoutBtn = _el.querySelector('#kshop-checkout');
        _claimList = _el.querySelector('#kshop-claim-list');
        _tooltip = document.getElementById('panel-tooltip');

        _el.querySelector('.kshop-close-btn').addEventListener('click', function() { requestClose(); });
        _checkoutBtn.addEventListener('click', checkout);

        return _el;
    }

    function onOpen(el, initData) {
        console.log('[KShop] onOpen called');
        _closing = false;
        _checkingOut = false;
        UiData.on('k', _kHandler);

        // Request catalog from Flash
        var reqId = 'bq' + (++_reqSeq);
        console.log('[KShop] sending bulkQuery, callId=' + reqId);
        _pendingReq[reqId] = function(resp) {
            if (!Panels.isOpen()) return;
            delete _pendingReq[reqId];
            if (resp.success) {
                _catalog = resp.catalog || [];
                _cart = resp.cart || [];
                _purchased = resp.purchased || [];
                _kpoints = resp.kpoints || 0;
                _playerLevel = resp.playerLevel || 0;
                _reverseLevel = resp.reverseLevel || 0;
                if (_balanceEl) _balanceEl.textContent = _kpoints;
                buildCategories();
                renderGrid();
                renderCart();
                renderClaimed();
            }
        };
        Bridge.send({type:'panel', cmd:'bulkQuery', callId: reqId});
    }

    // ── Bridge response listener ──
    Bridge.on('panel_resp', function(data) {
        var cb = _pendingReq[data.callId];
        if (cb) cb(data);
    });

    // ── Categories ──
    function buildCategories() {
        var seen = {};
        _categories = [];
        for (var i = 0; i < _catalog.length; i++) {
            var t = _catalog[i].type;
            if (!seen[t]) { seen[t] = true; _categories.push(t); }
        }
        _activeCategory = _categories[0] || null;
        renderCatBar();
    }

    function renderCatBar() {
        _catBar.innerHTML = '';
        for (var i = 0; i < _categories.length; i++) {
            var btn = document.createElement('button');
            btn.className = 'kshop-cat-btn' + (_categories[i] === _activeCategory ? ' active' : '');
            btn.textContent = _categories[i];
            btn.setAttribute('data-cat', _categories[i]);
            btn.addEventListener('click', onCatClick);
            _catBar.appendChild(btn);
        }
    }

    function onCatClick(e) {
        _activeCategory = e.target.getAttribute('data-cat');
        renderCatBar();
        renderGrid();
    }

    // ── Grid ──
    function renderGrid() {
        _grid.innerHTML = '';
        for (var i = 0; i < _catalog.length; i++) {
            var item = _catalog[i];
            if (item.type !== _activeCategory) continue;
            var card = document.createElement('div');
            card.className = 'kshop-card';
            if (item.type === '\u975e\u5356\u54c1') card.classList.add('kshop-card-nosale');

            var iconUrl = (typeof Icons !== 'undefined') ? Icons.resolve(item.item) : null;
            var imgHtml = iconUrl
                ? '<img class="kshop-icon" src="' + iconUrl + '" onerror="this.style.display=\'none\'">'
                : '<div class="kshop-icon kshop-icon-placeholder"></div>';

            card.innerHTML = imgHtml +
                '<div class="kshop-card-name">' + escHtml(item.displayname) + '</div>' +
                '<div class="kshop-card-price">K ' + item.price + '</div>' +
                (item.type !== '\u975e\u5356\u54c1'
                    ? '<button class="kshop-add-btn" data-idx="' + item.idx + '">+</button>'
                    : '');

            card.addEventListener('mouseenter', onCardHover);
            card.addEventListener('mouseleave', onCardLeave);
            card.addEventListener('mousemove', onCardMove);
            card.setAttribute('data-idx', item.idx);

            var addBtn = card.querySelector('.kshop-add-btn');
            if (addBtn) addBtn.addEventListener('click', onAddToCart);
            _grid.appendChild(card);
        }
        if (!_iconsLoaded) {
            Icons.load(function() { _iconsLoaded = true; renderGrid(); });
        }
    }

    // ── Tooltip ──
    function onCardHover(e) {
        var idx = Number(e.currentTarget.getAttribute('data-idx'));
        var item = findCatalogItem(idx);
        if (!item || !_tooltip) return;
        _tooltip.innerHTML =
            '<b>' + escHtml(item.displayname) + '</b>' +
            '<div style="margin:4px 0;border-top:1px solid rgba(0,240,255,0.15)"></div>' +
            '<span style="color:#607088">TYPE</span> ' + item.majorType + ' / ' + item.subType + '<br>' +
            '<span style="color:#607088">LVL</span> ' + item.level + '<br>' +
            '<span style="color:#fcee09">K ' + item.price + '</span>';
        _tooltip.style.display = 'block';
    }
    function onCardLeave() { if (_tooltip) _tooltip.style.display = 'none'; }
    function onCardMove(e) {
        if (!_tooltip) return;
        _tooltip.style.left = (e.clientX + 12) + 'px';
        _tooltip.style.top = (e.clientY + 12) + 'px';
    }

    // ── Cart ──
    function onAddToCart(e) {
        e.stopPropagation();
        var idx = Number(e.target.getAttribute('data-idx'));
        for (var i = 0; i < _cart.length; i++) {
            if (_cart[i].idx === idx) { _cart[i].qty++; renderCart(); return; }
        }
        _cart.push({idx: idx, qty: 1});
        renderCart();
    }

    function renderCart() {
        _cartList.innerHTML = '';
        var total = 0;
        for (var i = 0; i < _cart.length; i++) {
            var c = _cart[i];
            var item = findCatalogItem(c.idx);
            if (!item) continue;
            var subtotal = Number(item.price) * c.qty;
            total += subtotal;
            var row = document.createElement('div');
            row.className = 'kshop-cart-row';
            row.innerHTML =
                '<span class="kshop-cart-name">' + escHtml(item.displayname) + '</span>' +
                '<span class="kshop-cart-qty">' +
                    '<button class="kshop-qty-btn" data-idx="' + c.idx + '" data-delta="-1">\u2212</button>' +
                    ' ' + c.qty + ' ' +
                    '<button class="kshop-qty-btn" data-idx="' + c.idx + '" data-delta="1">+</button>' +
                '</span>' +
                '<span class="kshop-cart-sub">K ' + subtotal + '</span>';
            var btns = row.querySelectorAll('.kshop-qty-btn');
            for (var b = 0; b < btns.length; b++) btns[b].addEventListener('click', onQtyChange);
            _cartList.appendChild(row);
        }
        _cartTotal.textContent = total;
        _checkoutBtn.disabled = _cart.length === 0;
    }

    function onQtyChange(e) {
        var idx = Number(e.target.getAttribute('data-idx'));
        var delta = Number(e.target.getAttribute('data-delta'));
        for (var i = 0; i < _cart.length; i++) {
            if (_cart[i].idx === idx) {
                _cart[i].qty += delta;
                if (_cart[i].qty <= 0) _cart.splice(i, 1);
                renderCart();
                return;
            }
        }
    }

    // ── Checkout ──
    function checkout() {
        if (_checkingOut || _cart.length === 0) return;
        _checkingOut = true;
        var reqId = 'co' + (++_reqSeq);
        var payload = [];
        for (var i = 0; i < _cart.length; i++) payload.push({idx: _cart[i].idx, qty: _cart[i].qty});
        _pendingReq[reqId] = function(resp) {
            if (!Panels.isOpen()) return;
            delete _pendingReq[reqId];
            _checkingOut = false;
            if (resp.success) {
                _kpoints = resp.newBalance;
                if (_balanceEl) _balanceEl.textContent = _kpoints;
                _purchased = resp.purchased || [];
                _cart = [];
                renderCart();
                renderClaimed();
                if (typeof Toast !== 'undefined') Toast.add('\u8d2d\u4e70\u6210\u529f\uff01');
            } else if (resp.error === 'insufficient_kpoints') {
                if (typeof Toast !== 'undefined') Toast.add('K\u70b9\u4e0d\u8db3');
            } else {
                if (typeof Toast !== 'undefined') Toast.add('\u8d2d\u4e70\u5931\u8d25: ' + (resp.error || 'unknown'));
            }
        };
        Bridge.send({type:'panel', cmd:'checkout', callId: reqId, cart: payload});
    }

    // ── Claim ──
    function renderClaimed() {
        _claimList.innerHTML = '';
        for (var i = 0; i < _purchased.length; i++) {
            var p = _purchased[i];
            var row = document.createElement('div');
            row.className = 'kshop-claim-row';
            row.innerHTML =
                '<span class="kshop-claim-name">' + escHtml(String(p[1])) + ' x' + p[p.length - 1] + '</span>' +
                '<button class="kshop-claim-btn" data-pidx="' + i + '">\u9886\u53d6</button>';
            row.querySelector('.kshop-claim-btn').addEventListener('click', onClaim);
            _claimList.appendChild(row);
        }
    }

    function onClaim(e) {
        var pidx = Number(e.target.getAttribute('data-pidx'));
        e.target.disabled = true;
        var reqId = 'cl' + (++_reqSeq);
        _pendingReq[reqId] = function(resp) {
            if (!Panels.isOpen()) return;
            delete _pendingReq[reqId];
            if (resp.success) {
                _purchased = resp.purchased || [];
                renderClaimed();
                if (typeof Toast !== 'undefined') Toast.add('\u9886\u53d6\u6210\u529f\uff01');
            } else {
                if (typeof Toast !== 'undefined') Toast.add('\u9886\u53d6\u5931\u8d25: ' + (resp.error || 'unknown'));
                e.target.disabled = false;
            }
        };
        Bridge.send({type:'panel', cmd:'claim', callId: reqId, purchasedIdx: pidx});
    }

    // ── Close ──
    function requestClose() {
        if (_closing) return;
        _closing = true;
        var cartPayload = [];
        for (var i = 0; i < _cart.length; i++) cartPayload.push({idx: _cart[i].idx, qty: _cart[i].qty});
        var reqId = 'wclose' + (++_reqSeq);
        _pendingReq[reqId] = function(resp) {
            if (!Panels.isOpen()) return;
            delete _pendingReq[reqId];
            if (resp.success) {
                doClose();
            } else if (resp.error === 'timeout') {
                _closing = false;
                showSaveFailedDialog('\u4fdd\u5b58\u8d85\u65f6\uff0c\u72b6\u6001\u672a\u77e5', true);
            } else {
                _closing = false;
                showSaveFailedDialog(resp.error || '\u4fdd\u5b58\u5931\u8d25', false);
            }
        };
        Bridge.send({type:'panel', cmd:'saveCart', callId: reqId, cart: cartPayload});
    }

    function doClose() {
        Panels.close();
        Bridge.send({type:'panel', cmd:'close'});
        UiData.off('k', _kHandler);
        _closing = false;
    }

    function showSaveFailedDialog(msg, timeoutMode) {
        // Simple confirm dialog
        var actions = timeoutMode
            ? '\u91cd\u8bd5 / \u5f3a\u5236\u5173\u95ed(\u4e22\u5f03\u8d2d\u7269\u8f66)'
            : '\u91cd\u8bd5 / \u653e\u5f03\u5173\u95ed / \u5f3a\u5236\u5173\u95ed(\u4e22\u5f03\u8d2d\u7269\u8f66)';
        if (typeof Toast !== 'undefined') Toast.add(msg + ' - ' + actions);
        // For now, auto-retry after brief delay
        setTimeout(function() { requestClose(); }, 2000);
    }

    function onForceClose() {
        _pendingReq = {};
        _closing = false;
        _checkingOut = false;
        UiData.off('k', _kHandler);
        if (typeof Toast !== 'undefined') Toast.add('\u8fde\u63a5\u65ad\u5f00\uff0c\u5546\u57ce\u5df2\u5173\u95ed');
    }

    // ── Helpers ──
    function findCatalogItem(idx) {
        for (var i = 0; i < _catalog.length; i++) {
            if (_catalog[i].idx === idx) return _catalog[i];
        }
        return null;
    }

    function escHtml(s) {
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }

    return { requestClose: requestClose, onForceClose: onForceClose };
})();
