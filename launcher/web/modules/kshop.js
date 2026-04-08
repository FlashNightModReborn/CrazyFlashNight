/**
 * KShop — K点商城面板
 *
 * 数据流: SHOP 按钮 → C# shopPanelOpen → panel_cmd open → KShop.onOpen
 *         → bulkQuery → Flash 回包 → 渲染商品列表
 * 关闭:   ESC/遮罩/关闭按钮 → requestClose → saveCart → close → shopPanelClose
 *
 * 旧系统行为保留:
 *   - 等级限制: item.level <= playerLevel + reverseLevel 才可购买
 *   - 购买分流: 消耗品/收集品 → 数量+/-, 其他(装备) → 单次加购(qty固定1)
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
    var _iconsLoaded = false;
    var _loading = false;

    // DOM refs
    var _el, _catBar, _grid, _cartList, _cartTotal, _balanceEl, _tooltip;
    var _checkoutBtn, _claimList, _loadingEl;

    var _kHandler = function(v) { _kpoints = Number(v); if (_balanceEl) _balanceEl.textContent = _kpoints; };

    // ── Helpers ──
    function isStackable(item) {
        return item.majorType === '\u6d88\u8017\u54c1' || item.majorType === '\u6536\u96c6\u54c1';
    }
    function isLocked(item) {
        return Number(item.level) > _playerLevel + _reverseLevel;
    }
    function findCatalogItem(idx) {
        for (var i = 0; i < _catalog.length; i++) {
            if (_catalog[i].idx === idx) return _catalog[i];
        }
        return null;
    }
    function escHtml(s) {
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }
    function iconHtml(itemName, cls) {
        var url = (typeof Icons !== 'undefined') ? Icons.resolve(itemName) : null;
        return url
            ? '<img class="' + (cls||'kshop-icon') + '" src="' + url + '" onerror="this.style.display=\'none\'">'
            : '<div class="' + (cls||'kshop-icon') + ' kshop-icon-placeholder"></div>';
    }
    function toast(msg) { if (typeof Toast !== 'undefined') Toast.add(msg); }

    // ══════════════════════════════════════════
    //  Panel registration
    // ══════════════════════════════════════════
    Panels.register('kshop', {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: function() { requestClose(); }
    });

    function createDOM() {
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
                '<div class="kshop-grid-wrap">' +
                    '<div class="kshop-loading" id="kshop-loading">LOADING...</div>' +
                    '<div class="kshop-grid" id="kshop-grid"></div>' +
                '</div>' +
                '<div class="kshop-sidebar">' +
                    '<div class="kshop-cart-header">// CART</div>' +
                    '<div class="kshop-cart-list" id="kshop-cart-list"></div>' +
                    '<div class="kshop-cart-footer">' +
                        '<span>TOTAL: <b id="kshop-cart-total">0</b></span>' +
                        '<button class="kshop-checkout-btn" id="kshop-checkout">CHECKOUT</button>' +
                    '</div>' +
                    '<div class="kshop-claim-header">// PURCHASED</div>' +
                    '<div class="kshop-claim-list" id="kshop-claim-list"></div>' +
                '</div>' +
            '</div>' +
            '<div class="kshop-dialog" id="kshop-dialog" style="display:none"></div>';

        _balanceEl = _el.querySelector('#kshop-kpoints');
        _catBar = _el.querySelector('#kshop-cat-bar');
        _grid = _el.querySelector('#kshop-grid');
        _loadingEl = _el.querySelector('#kshop-loading');
        _cartList = _el.querySelector('#kshop-cart-list');
        _cartTotal = _el.querySelector('#kshop-cart-total');
        _checkoutBtn = _el.querySelector('#kshop-checkout');
        _claimList = _el.querySelector('#kshop-claim-list');
        _tooltip = document.getElementById('panel-tooltip');

        _el.querySelector('.kshop-close-btn').addEventListener('click', function() { requestClose(); });
        _checkoutBtn.addEventListener('click', checkout);

        return _el;
    }

    // ══════════════════════════════════════════
    //  Open / Data load
    // ══════════════════════════════════════════
    function onOpen(el) {
        _closing = false;
        _checkingOut = false;
        _loading = true;
        UiData.on('k', _kHandler);
        if (_loadingEl) _loadingEl.style.display = '';
        if (_grid) _grid.style.opacity = '0.3';

        var reqId = 'bq' + (++_reqSeq);
        _pendingReq[reqId] = function(resp) {
            if (!Panels.isOpen()) return;
            delete _pendingReq[reqId];
            _loading = false;
            if (_loadingEl) _loadingEl.style.display = 'none';
            if (_grid) _grid.style.opacity = '';
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

    // ══════════════════════════════════════════
    //  Categories
    // ══════════════════════════════════════════
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
        var cat = e.target.getAttribute('data-cat');
        if (cat === _activeCategory) return;
        _activeCategory = cat;
        renderCatBar();
        _grid.scrollTop = 0; // 切类回顶
        renderGrid();
    }

    // ══════════════════════════════════════════
    //  Grid — 等级锁定 + 购买分流
    // ══════════════════════════════════════════
    function renderGrid() {
        _grid.innerHTML = '';
        for (var i = 0; i < _catalog.length; i++) {
            var item = _catalog[i];
            if (item.type !== _activeCategory) continue;

            var locked = isLocked(item);
            var nosale = item.type === '\u975e\u5356\u54c1';
            var stackable = isStackable(item);

            var card = document.createElement('div');
            card.className = 'kshop-card';
            if (nosale) card.classList.add('kshop-card-nosale');
            if (locked) card.classList.add('kshop-card-locked');

            var iconEl = iconHtml(item.item);

            // 购买控件：锁定/非卖品不显示，装备用单次加购，消耗品/收集品用+
            var actionHtml = '';
            if (!nosale && !locked) {
                if (stackable) {
                    actionHtml = '<button class="kshop-add-btn" data-idx="' + item.idx + '" title="\u52a0\u5165\u8d2d\u7269\u8f66">+</button>';
                } else {
                    actionHtml = '<button class="kshop-add-btn kshop-add-single" data-idx="' + item.idx + '" title="\u52a0\u5165\u8d2d\u7269\u8f66">\u2713</button>';
                }
            }

            // 锁定标志
            var lockHtml = locked
                ? '<div class="kshop-lock" title="Lv.' + item.level + ' \u89e3\u9501">\u26bf Lv.' + item.level + '</div>'
                : '';

            card.innerHTML = iconEl +
                '<div class="kshop-card-name">' + escHtml(item.displayname) + '</div>' +
                '<div class="kshop-card-price">K ' + item.price + '</div>' +
                lockHtml + actionHtml;

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

    // ══════════════════════════════════════════
    //  Tooltip — Flash bridge + 缓存
    //  hover 即时显示基础信息，异步拉取 Flash TooltipComposer 的富文本
    // ══════════════════════════════════════════
    var _tooltipCache = {};  // idx → {descHTML, introHTML}
    var _tooltipHovering = -1; // 当前 hover 的 idx，离开时置 -1

    function onCardHover(e) {
        var idx = Number(e.currentTarget.getAttribute('data-idx'));
        var item = findCatalogItem(idx);
        if (!item || !_tooltip) return;
        _tooltipHovering = idx;

        // 有缓存则直接渲染富文本
        if (_tooltipCache[idx]) {
            renderRichTooltip(item, _tooltipCache[idx]);
        } else {
            // 先显示基础占位
            renderBasicTooltip(item);
            // 异步请求 Flash 富文本
            requestFlashTooltip(idx);
        }
        _tooltip.style.display = 'block';
    }

    function onCardLeave() {
        _tooltipHovering = -1;
        if (_tooltip) _tooltip.style.display = 'none';
    }

    function onCardMove(e) {
        if (!_tooltip) return;
        // 确保 tooltip 不超出视口
        var x = e.clientX + 14, y = e.clientY + 14;
        var tw = _tooltip.offsetWidth, th = _tooltip.offsetHeight;
        var vw = window.innerWidth, vh = window.innerHeight;
        if (x + tw > vw - 8) x = e.clientX - tw - 8;
        if (y + th > vh - 8) y = vh - th - 8;
        _tooltip.style.left = x + 'px';
        _tooltip.style.top = y + 'px';
    }

    function renderBasicTooltip(item) {
        var locked = isLocked(item);
        _tooltip.innerHTML =
            '<div class="kshop-tt-header"><b>' + escHtml(item.displayname) + '</b></div>' +
            '<div class="kshop-tt-divider"></div>' +
            '<span class="kshop-tt-dim">TYPE</span> ' + escHtml(item.majorType) + ' / ' + escHtml(item.subType) + '<br>' +
            '<span class="kshop-tt-dim">LVL</span> ' + item.level +
            (locked ? ' <span class="kshop-tt-locked">\u26bf LOCKED</span>' : '') + '<br>' +
            '<span class="kshop-tt-price">K ' + item.price + '</span>' +
            '<div class="kshop-tt-loading">LOADING...</div>';
    }

    function renderRichTooltip(item, data) {
        var locked = isLocked(item);
        var introHtml = data.introHTML ? convertAS2Html(data.introHTML) : '';
        var descHtml = data.descHTML ? convertAS2Html(data.descHTML) : '';

        var lockBanner = locked
            ? '<div class="kshop-tt-lock-banner">\u26bf LOCKED \u2014 Lv.' + item.level + '</div>'
            : '';

        // 物品图标（与原 Flash 注释框的 物品图标定位 层对应）
        var iconUrl = (typeof Icons !== 'undefined') ? Icons.resolve(item.item) : null;
        var iconBlock = iconUrl
            ? '<div class="kshop-tt-icon"><img src="' + iconUrl + '" onerror="this.parentNode.style.display=\'none\'"></div>'
            : '';

        _tooltip.innerHTML =
            '<div class="kshop-tt-rich">' +
                iconBlock +
                (introHtml ? '<div class="kshop-tt-intro">' + introHtml + '</div>' : '') +
                (descHtml ? '<div class="kshop-tt-desc">' + descHtml + '</div>' : '') +
            '</div>' +
            lockBanner;
    }

    function requestFlashTooltip(idx) {
        var reqId = 'tt' + (++_reqSeq);
        _pendingReq[reqId] = function(resp) {
            delete _pendingReq[reqId];
            if (resp.success) {
                _tooltipCache[idx] = { descHTML: resp.descHTML || '', introHTML: resp.introHTML || '' };
                // 如果用户还在 hover 同一个物品，刷新 tooltip
                if (_tooltipHovering === idx && _tooltip) {
                    var item = findCatalogItem(idx);
                    if (item) {
                        renderRichTooltip(item, _tooltipCache[idx]);
                    }
                }
            }
        };
        Bridge.send({type:'panel', cmd:'tooltip', callId: reqId, idx: idx});
    }

    // AS2 TextField HTML → 浏览器 HTML
    // <FONT COLOR='#FFCC00'>text</FONT> → <span style="color:#FFCC00">text</span>
    // <B>text</B> → <b>text</b> (已兼容)
    // <BR> → <br>
    function convertAS2Html(s) {
        if (!s) return '';
        return s
            .replace(/<FONT\s+COLOR\s*=\s*'([^']+)'\s*>/gi, '<span style="color:$1">')
            .replace(/<\/FONT>/gi, '</span>')
            .replace(/<BR\s*\/?>/gi, '<br>')
            .replace(/<B>/gi, '<b>').replace(/<\/B>/gi, '</b>')
            .replace(/<I>/gi, '<i>').replace(/<\/I>/gi, '</i>');
    }

    // ══════════════════════════════════════════
    //  Cart — 购买分流：装备qty固定1，消耗品/收集品可叠加
    // ══════════════════════════════════════════
    function onAddToCart(e) {
        e.stopPropagation();
        var idx = Number(e.target.getAttribute('data-idx'));
        var item = findCatalogItem(idx);
        if (!item) return;

        // 二次等级校验（防 DOM 篡改）
        if (isLocked(item)) {
            toast('\u7b49\u7ea7\u4e0d\u8db3\uff0c\u65e0\u6cd5\u8d2d\u4e70\uff01');
            return;
        }

        var stackable = isStackable(item);

        for (var i = 0; i < _cart.length; i++) {
            if (_cart[i].idx === idx) {
                if (stackable) {
                    _cart[i].qty++;
                } else {
                    toast('\u8be5\u88c5\u5907\u5df2\u5728\u8d2d\u7269\u8f66\u4e2d');
                    return;
                }
                renderCart();
                return;
            }
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
            var stackable = isStackable(item);

            var row = document.createElement('div');
            row.className = 'kshop-cart-row';
            row.setAttribute('data-idx', c.idx);

            // 图标 + 名称 + 数量控件
            var qtyHtml;
            if (stackable) {
                qtyHtml =
                    '<span class="kshop-cart-qty">' +
                        '<button class="kshop-qty-btn" data-idx="' + c.idx + '" data-delta="-1">\u2212</button>' +
                        ' ' + c.qty + ' ' +
                        '<button class="kshop-qty-btn" data-idx="' + c.idx + '" data-delta="1">+</button>' +
                    '</span>';
            } else {
                qtyHtml =
                    '<span class="kshop-cart-qty">\u00d71</span>' +
                    '<button class="kshop-qty-btn kshop-remove-btn" data-idx="' + c.idx + '" data-delta="-1" title="\u79fb\u9664">\u2715</button>';
            }

            row.innerHTML =
                '<span class="kshop-cart-thumb">' + iconHtml(item.item, 'kshop-row-icon') + '</span>' +
                '<span class="kshop-cart-name">' + escHtml(item.displayname) + '</span>' +
                qtyHtml +
                '<span class="kshop-cart-sub">K ' + subtotal + '</span>';

            // 点击行弹详情
            row.addEventListener('click', onCartRowClick);
            var btns = row.querySelectorAll('.kshop-qty-btn');
            for (var b = 0; b < btns.length; b++) btns[b].addEventListener('click', onQtyChange);
            _cartList.appendChild(row);
        }
        _cartTotal.textContent = total;
        _checkoutBtn.disabled = _cart.length === 0;
    }

    function onCartRowClick(e) {
        if (e.target.classList.contains('kshop-qty-btn')) return;
        var idx = Number(e.currentTarget.getAttribute('data-idx'));
        showItemDetail(idx);
    }

    function onQtyChange(e) {
        e.stopPropagation();
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

    // ══════════════════════════════════════════
    //  Item detail (tooltip-style, triggered by row click)
    // ══════════════════════════════════════════
    function showItemDetail(idx) {
        var item = findCatalogItem(idx);
        if (!item || !_tooltip) return;

        // 用缓存的富文本（如果有的话）
        if (_tooltipCache[idx]) {
            renderRichTooltip(item, _tooltipCache[idx]);
        } else {
            renderBasicTooltip(item);
            requestFlashTooltip(idx);
        }
        // 固定在屏幕中央偏右
        _tooltip.style.display = 'block';
        _tooltip.style.left = '60%';
        _tooltip.style.top = '30%';
        _tooltipHovering = idx;
        // 5s 后自动关闭
        var closeIdx = idx;
        setTimeout(function() {
            if (_tooltipHovering === closeIdx) {
                _tooltipHovering = -1;
                _tooltip.style.display = 'none';
            }
        }, 5000);
    }

    // ══════════════════════════════════════════
    //  Checkout
    // ══════════════════════════════════════════
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
                toast('\u8d2d\u4e70\u6210\u529f\uff01');
            } else if (resp.error === 'insufficient_kpoints') {
                toast('K\u70b9\u4e0d\u8db3');
            } else {
                toast('\u8d2d\u4e70\u5931\u8d25: ' + (resp.error || 'unknown'));
            }
        };
        Bridge.send({type:'panel', cmd:'checkout', callId: reqId, cart: payload});
    }

    // ══════════════════════════════════════════
    //  Claimed items — 带图标
    // ══════════════════════════════════════════
    function renderClaimed() {
        _claimList.innerHTML = '';
        for (var i = 0; i < _purchased.length; i++) {
            var p = _purchased[i];
            var itemName = String(p[1]);
            var qty = p[p.length - 1];
            var row = document.createElement('div');
            row.className = 'kshop-claim-row';
            row.setAttribute('data-pidx', i);
            row.innerHTML =
                '<span class="kshop-cart-thumb">' + iconHtml(itemName, 'kshop-row-icon') + '</span>' +
                '<span class="kshop-claim-name">' + escHtml(itemName) + ' \u00d7' + qty + '</span>' +
                '<button class="kshop-claim-btn" data-pidx="' + i + '">CLAIM</button>';
            row.querySelector('.kshop-claim-btn').addEventListener('click', onClaim);
            _claimList.appendChild(row);
        }
    }

    function onClaim(e) {
        e.stopPropagation();
        var pidx = Number(e.target.getAttribute('data-pidx'));
        e.target.disabled = true;
        var reqId = 'cl' + (++_reqSeq);
        _pendingReq[reqId] = function(resp) {
            if (!Panels.isOpen()) return;
            delete _pendingReq[reqId];
            if (resp.success) {
                _purchased = resp.purchased || [];
                renderClaimed();
                toast('\u9886\u53d6\u6210\u529f\uff01');
            } else {
                toast('\u9886\u53d6\u5931\u8d25: ' + (resp.error || 'unknown'));
                e.target.disabled = false;
            }
        };
        Bridge.send({type:'panel', cmd:'claim', callId: reqId, purchasedIdx: pidx});
    }

    // ══════════════════════════════════════════
    //  Close — saveCart 失败对话框
    // ══════════════════════════════════════════
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
        dismissDialog();
        Panels.close();
        Bridge.send({type:'panel', cmd:'close'});
        UiData.off('k', _kHandler);
        _closing = false;
    }

    function showSaveFailedDialog(msg, timeoutMode) {
        var dlg = _el.querySelector('#kshop-dialog');
        if (!dlg) return;
        var btns = '<button class="kshop-dlg-btn" data-action="retry">RETRY</button>';
        if (!timeoutMode) btns += '<button class="kshop-dlg-btn" data-action="cancel">\u7ee7\u7eed\u8d2d\u7269</button>';
        btns += '<button class="kshop-dlg-btn kshop-dlg-danger" data-action="force">\u5f3a\u5236\u5173\u95ed</button>';

        dlg.innerHTML =
            '<div class="kshop-dlg-inner">' +
                '<div class="kshop-dlg-title">\u26a0 ' + escHtml(msg) + '</div>' +
                '<div class="kshop-dlg-hint">' +
                    (timeoutMode ? '\u8d2d\u7269\u8f66\u72b6\u6001\u672a\u77e5\uff0c\u5f3a\u5236\u5173\u95ed\u53ef\u80fd\u4e22\u5931\u8d2d\u7269\u8f66' : '\u53ef\u91cd\u8bd5\u6216\u7ee7\u7eed\u8d2d\u7269') +
                '</div>' +
                '<div class="kshop-dlg-btns">' + btns + '</div>' +
            '</div>';
        dlg.style.display = '';
        dlg.addEventListener('click', onDialogClick);
    }

    function onDialogClick(e) {
        var action = e.target.getAttribute('data-action');
        if (!action) return;
        if (action === 'retry') {
            dismissDialog();
            requestClose();
        } else if (action === 'cancel') {
            dismissDialog();
        } else if (action === 'force') {
            doClose();
        }
    }

    function dismissDialog() {
        var dlg = _el ? _el.querySelector('#kshop-dialog') : null;
        if (dlg) { dlg.style.display = 'none'; dlg.innerHTML = ''; }
    }

    function onForceClose() {
        _pendingReq = {};
        _closing = false;
        _checkingOut = false;
        dismissDialog();
        UiData.off('k', _kHandler);
        toast('\u8fde\u63a5\u65ad\u5f00\uff0c\u5546\u57ce\u5df2\u5173\u95ed');
    }

    return { requestClose: requestClose, onForceClose: onForceClose };
})();
