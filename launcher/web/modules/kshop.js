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
    var _el, _catBar, _grid, _cartList, _cartTotal, _balanceEl;
    var _checkoutBtn, _claimList, _loadingEl;

    var _kHandler = function(v) { _kpoints = Number(v); if (_balanceEl) _balanceEl.textContent = _kpoints; };

    // ── Helpers ──
    function isStackable(item) {
        return item.majorType === '消耗品' || item.majorType === '收集品';
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
    function iconHtml(iconName, cls) {
        var url = (typeof Icons !== 'undefined') ? Icons.resolve(iconName) : null;
        return url
            ? '<img class="' + (cls||'kshop-icon') + '" src="' + url + '" onerror="this.style.display=\'none\'">'
            : '<div class="' + (cls||'kshop-icon') + ' kshop-icon-placeholder"></div>';
    }
    function toast(msg) { if (typeof Toast !== 'undefined') Toast.add(msg); }

    // 长按加速：按住按钮自动重复触发，间隔逐步缩短
    // 初始 400ms → 加速到最快 50ms（每次 ×0.85）
    // 返回 stop 函数，供外部在 DOM 重建前主动停止
    var _activeHoldTimers = []; // 所有活跃的 holdRepeat stop 句柄
    function holdRepeat(el, callback) {
        var timer = null, interval = 400;
        function fire() {
            callback();
            interval = Math.max(50, interval * 0.85);
            timer = setTimeout(fire, interval);
        }
        function start(e) {
            e.preventDefault();
            interval = 400;
            callback();
            timer = setTimeout(fire, interval);
            // 全局 mouseup 兜底：即使按钮被销毁也能停止
            document.addEventListener('mouseup', stop);
        }
        function stop() {
            if (timer) { clearTimeout(timer); timer = null; }
            interval = 400;
            document.removeEventListener('mouseup', stop);
        }
        el.addEventListener('mousedown', start);
        el.addEventListener('mouseup', stop);
        el.addEventListener('mouseleave', stop);
        el.addEventListener('click', function(e) { e.stopPropagation(); });
        _activeHoldTimers.push(stop);
    }
    // 在 DOM 重建前调用，强制停止所有活跃的长按 timer
    function killAllHoldTimers() {
        for (var i = 0; i < _activeHoldTimers.length; i++) _activeHoldTimers[i]();
        _activeHoldTimers = [];
    }

    // ══════════════════════════════════════════
    //  Panel registration
    // ══════════════════════════════════════════
    Panels.register('kshop', {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: function() { requestClose(); },
        onForceClose: onForceClose
    });

    function createDOM() {
        _el = document.createElement('div');
        _el.className = 'kshop-panel';
        _el.innerHTML =
            '<div class="kshop-header">' +
                '<span class="kshop-title">K点商城</span>' +
                '<span class="kshop-balance">K点: <b id="kshop-kpoints">0</b></span>' +
                '<button class="kshop-close-btn">×</button>' +
            '</div>' +
            '<div class="kshop-categories" id="kshop-cat-bar"></div>' +
            '<div class="kshop-body">' +
                '<div class="kshop-grid-wrap">' +
                    '<div class="kshop-loading" id="kshop-loading">加载中…</div>' +
                    '<div class="kshop-grid" id="kshop-grid"></div>' +
                '</div>' +
                '<div class="kshop-sidebar">' +
                    '<div class="kshop-cart-header">// 购物车</div>' +
                    '<div class="kshop-cart-list" id="kshop-cart-list"></div>' +
                    '<div class="kshop-cart-footer">' +
                        '<span>合计: <b id="kshop-cart-total">0</b></span>' +
                        '<button class="kshop-checkout-btn" id="kshop-checkout">结账</button>' +
                    '</div>' +
                    '<div class="kshop-claim-header">// 已购买</div>' +
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
            delete _pendingReq[reqId];
            if (!Panels.isOpen()) return;
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
            var nosale = item.type === '非卖品';
            var stackable = isStackable(item);

            var card = document.createElement('div');
            card.className = 'kshop-card';
            if (nosale) card.classList.add('kshop-card-nosale');
            if (locked) card.classList.add('kshop-card-locked');

            var iconEl = iconHtml(item.icon);

            // 购买控件：锁定/非卖品不显示，装备用单次加购，消耗品/收集品用+
            var actionHtml = '';
            if (!nosale && !locked) {
                if (stackable) {
                    actionHtml = '<button class="kshop-add-btn" data-idx="' + item.idx + '" title="加入购物车">+</button>';
                } else {
                    actionHtml = '<button class="kshop-add-btn kshop-add-single" data-idx="' + item.idx + '" title="加入购物车">✓</button>';
                }
            }

            // 锁定标志
            var lockHtml = locked
                ? '<div class="kshop-lock" title="Lv.' + item.level + ' 解锁">⚿ Lv.' + item.level + '</div>'
                : '';

            card.innerHTML = iconEl +
                '<div class="kshop-card-info">' +
                    '<div class="kshop-card-name">' + escHtml(item.displayname) + '</div>' +
                    '<div class="kshop-card-price">K ' + item.price + '</div>' +
                    lockHtml +
                '</div>' +
                actionHtml;

            card.addEventListener('mouseenter', onCardHover);
            card.addEventListener('mouseleave', onCardLeave);
            card.addEventListener('mousemove', onCardMove);
            card.setAttribute('data-idx', item.idx);

            var addBtn = card.querySelector('.kshop-add-btn');
            if (addBtn) addBtn.addEventListener('click', onAddToCart);
            _grid.appendChild(card);
        }
        if (!_iconsLoaded) {
            Icons.load(function() { _iconsLoaded = true; renderGrid(); renderCart(); renderClaimed(); });
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
        if (!item) return;
        _tooltipHovering = idx;

        var html = _tooltipCache[idx]
            ? buildRichHtml(item, _tooltipCache[idx])
            : buildBasicHtml(item);
        PanelTooltip.showAtMouse(html, e);
        if (!_tooltipCache[idx]) requestFlashTooltip(idx);
    }

    function onCardLeave() {
        _tooltipHovering = -1;
        PanelTooltip.hide();
    }

    function onCardMove(e) {
        PanelTooltip.followMouse(e);
    }

    function buildBasicHtml(item) {
        var locked = isLocked(item);
        return '<div class="kshop-tt-header"><b>' + escHtml(item.displayname) + '</b></div>' +
            '<div class="kshop-tt-divider"></div>' +
            '<span class="kshop-tt-dim">类型</span> ' + escHtml(item.majorType) + ' / ' + escHtml(item.subType) + '<br>' +
            '<span class="kshop-tt-dim">等级</span> ' + item.level +
            (locked ? ' <span class="kshop-tt-locked">⚿ 锁定</span>' : '') + '<br>' +
            '<span class="kshop-tt-price">K ' + item.price + '</span>' +
            '<div class="kshop-tt-loading">加载中…</div>';
    }

    function buildRichHtml(item, data) {
        var locked = isLocked(item);
        var introHtml = data.introHTML ? PanelTooltip.convertAS2Html(data.introHTML) : '';
        var descHtml = data.descHTML ? PanelTooltip.convertAS2Html(data.descHTML) : '';

        var lockBanner = locked
            ? '<div class="kshop-tt-lock-banner">⚿ 锁定 — 需要 Lv.' + item.level + '</div>'
            : '';

        var iconUrl = (typeof Icons !== 'undefined') ? Icons.resolve(item.icon) : null;
        var iconBlock = iconUrl
            ? '<div class="kshop-tt-icon"><img src="' + iconUrl + '" onerror="this.parentNode.style.display=\'none\'"></div>'
            : '';

        return '<div class="kshop-tt-rich">' +
                iconBlock +
                (introHtml ? '<div class="kshop-tt-intro">' + introHtml + '</div>' : '') +
                (descHtml ? '<div class="kshop-tt-desc">' + descHtml + '</div>' : '') +
            '</div>' +
            lockBanner;
    }

    function requestFlashTooltip(idx) {
        var reqId = 'tt' + (++_reqSeq);
        _pendingReq[reqId] = function(resp) {
            delete _pendingReq[reqId]; // 先清理，无论面板是否已关
            if (!Panels.isOpen()) return;
            if (resp.success) {
                _tooltipCache[idx] = { descHTML: resp.descHTML || '', introHTML: resp.introHTML || '' };
                if (_tooltipHovering === idx && PanelTooltip.isVisible() && Panels.isOpen()) {
                    var item = findCatalogItem(idx);
                    if (item) PanelTooltip.updateContent(buildRichHtml(item, _tooltipCache[idx]));
                }
            }
        };
        Bridge.send({type:'panel', cmd:'tooltip', callId: reqId, idx: idx});
    }

    // ══════════════════════════════════════════
    //  Cart — 购买分流：装备qty固定1，消耗品/收集品可叠加
    // ══════════════════════════════════════════
    function onAddToCart(e) {
        e.stopPropagation();
        var idx = Number(e.target.getAttribute('data-idx'));
        var item = findCatalogItem(idx);
        if (!item) return;

        if (isLocked(item)) {
            toast('等级不足，无法购买！');
            return;
        }

        var stackable = isStackable(item);

        if (!stackable) {
            // 装备：直接加1，重复提示
            for (var i = 0; i < _cart.length; i++) {
                if (_cart[i].idx === idx) {
                    toast('该装备已在购物车中');
                    return;
                }
            }
            _cart.push({idx: idx, qty: 1});
            renderCart();
        } else {
            // 消耗品/收集品：弹出数量输入
            showQtyInput(e.target, idx);
        }
    }

    // 消耗品批量数量输入弹窗
    var _qtyPopup = null;
    function showQtyInput(anchor, idx) {
        dismissQtyInput();
        var item = findCatalogItem(idx);
        if (!item) return;

        _qtyPopup = document.createElement('div');
        _qtyPopup.className = 'kshop-qty-popup';
        _qtyPopup.innerHTML =
            '<div class="kshop-qty-popup-title">' + escHtml(item.displayname) + '</div>' +
            '<div class="kshop-qty-popup-row">' +
                '<button class="kshop-qty-pop-btn" data-v="-10">−−</button>' +
                '<button class="kshop-qty-pop-btn" data-v="-1">−</button>' +
                '<input class="kshop-qty-input" type="number" value="1" min="1" max="999">' +
                '<button class="kshop-qty-pop-btn" data-v="1">+</button>' +
                '<button class="kshop-qty-pop-btn" data-v="10">++</button>' +
            '</div>' +
            '<div class="kshop-qty-popup-foot">' +
                '<span class="kshop-qty-subtotal">K ' + item.price + '</span>' +
                '<button class="kshop-qty-confirm">加购</button>' +
            '</div>';

        // 定位到按钮附近
        var rect = anchor.getBoundingClientRect();
        _qtyPopup.style.left = (rect.right + 4) + 'px';
        _qtyPopup.style.top = rect.top + 'px';
        document.body.appendChild(_qtyPopup);

        var input = _qtyPopup.querySelector('.kshop-qty-input');
        var subtotalEl = _qtyPopup.querySelector('.kshop-qty-subtotal');
        var price = Number(item.price);

        function updateSubtotal() {
            var v = Math.max(1, Math.floor(Number(input.value) || 1));
            input.value = v;
            subtotalEl.textContent = 'K ' + (v * price);
        }

        // +/- 按钮：长按加速
        var btns = _qtyPopup.querySelectorAll('.kshop-qty-pop-btn');
        for (var b = 0; b < btns.length; b++) {
            (function(btn) {
                var delta = Number(btn.getAttribute('data-v'));
                holdRepeat(btn, function() {
                    input.value = Math.max(1, (Number(input.value) || 1) + delta);
                    updateSubtotal();
                });
            })(btns[b]);
        }
        input.addEventListener('input', updateSubtotal);
        input.addEventListener('keydown', function(ev) {
            if (ev.key === 'Enter') confirmAdd();
        });

        // 确认按钮
        _qtyPopup.querySelector('.kshop-qty-confirm').addEventListener('click', confirmAdd);

        function confirmAdd() {
            var qty = Math.max(1, Math.floor(Number(input.value) || 1));
            addToCartDirect(idx, qty);
            dismissQtyInput();
        }

        // 点外部关闭
        setTimeout(function() {
            document.addEventListener('click', onQtyOutsideClick);
        }, 0);
        input.focus();
        input.select();
    }

    function onQtyOutsideClick(e) {
        if (_qtyPopup && !_qtyPopup.contains(e.target)) {
            dismissQtyInput();
        }
    }

    function dismissQtyInput() {
        killAllHoldTimers();
        document.removeEventListener('click', onQtyOutsideClick);
        if (_qtyPopup && _qtyPopup.parentNode) {
            _qtyPopup.parentNode.removeChild(_qtyPopup);
        }
        _qtyPopup = null;
    }

    function addToCartDirect(idx, qty) {
        for (var i = 0; i < _cart.length; i++) {
            if (_cart[i].idx === idx) {
                _cart[i].qty += qty;
                renderCart();
                return;
            }
        }
        _cart.push({idx: idx, qty: qty});
        renderCart();
    }

    function renderCart() {
        killAllHoldTimers();
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
                        '<button class="kshop-qty-btn" data-idx="' + c.idx + '" data-delta="-1">−</button>' +
                        ' ' + c.qty + ' ' +
                        '<button class="kshop-qty-btn" data-idx="' + c.idx + '" data-delta="1">+</button>' +
                    '</span>';
            } else {
                qtyHtml =
                    '<span class="kshop-cart-qty">×1</span>' +
                    '<button class="kshop-qty-btn kshop-remove-btn" data-idx="' + c.idx + '" data-delta="-1" title="移除">✕</button>';
            }

            row.innerHTML =
                '<span class="kshop-cart-thumb">' + iconHtml(item.icon, 'kshop-row-icon') + '</span>' +
                '<span class="kshop-cart-name">' + escHtml(item.displayname) + '</span>' +
                qtyHtml +
                '<span class="kshop-cart-sub">K ' + subtotal + '</span>';

            // 点击行弹详情
            row.addEventListener('click', onCartRowClick);
            // 数量按钮：长按加速
            var btns = row.querySelectorAll('.kshop-qty-btn');
            for (var b = 0; b < btns.length; b++) {
                (function(btn) {
                    var cidx = Number(btn.getAttribute('data-idx'));
                    var delta = Number(btn.getAttribute('data-delta'));
                    holdRepeat(btn, function() {
                        for (var j = 0; j < _cart.length; j++) {
                            if (_cart[j].idx === cidx) {
                                _cart[j].qty += delta;
                                if (_cart[j].qty <= 0) { _cart.splice(j, 1); }
                                renderCart();
                                return;
                            }
                        }
                    });
                })(btns[b]);
            }
            _cartList.appendChild(row);
        }
        _cartTotal.textContent = total;
        _checkoutBtn.disabled = _cart.length === 0;
    }

    function onCartRowClick(e) {
        if (e.target.classList.contains('kshop-qty-btn')) return;
        var idx = Number(e.currentTarget.getAttribute('data-idx'));
        showItemDetail(idx, e.currentTarget);
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
    //  使用 PanelTooltip.showAnchored，生命周期由通用模块管理
    // ══════════════════════════════════════════
    function showItemDetail(idx, anchorEl) {
        var item = findCatalogItem(idx);
        if (!item) return;

        _tooltipHovering = idx;
        var html = _tooltipCache[idx]
            ? buildRichHtml(item, _tooltipCache[idx])
            : buildBasicHtml(item);
        PanelTooltip.showAnchored(html, anchorEl);
        if (!_tooltipCache[idx]) requestFlashTooltip(idx);
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
            delete _pendingReq[reqId];
            if (!Panels.isOpen()) return;
            _checkingOut = false;
            if (resp.success) {
                _kpoints = resp.newBalance;
                if (_balanceEl) _balanceEl.textContent = _kpoints;
                _purchased = resp.purchased || [];
                _cart = [];
                renderCart();
                renderClaimed();
                toast('购买成功！');
            } else if (resp.error === 'insufficient_kpoints') {
                toast('K点不足');
            } else {
                toast('购买失败: ' + (resp.error || 'unknown'));
            }
        };
        Bridge.send({type:'panel', cmd:'checkout', callId: reqId, cart: payload});
    }

    // ══════════════════════════════════════════
    //  Claimed items — 带图标
    // ══════════════════════════════════════════
    // 通过 itemName 反查 catalog 条目（用于已购列表取 displayname/icon）
    function findCatalogByName(name) {
        for (var i = 0; i < _catalog.length; i++) {
            if (_catalog[i].item === name) return _catalog[i];
        }
        return null;
    }

    function renderClaimed() {
        _claimList.innerHTML = '';
        for (var i = 0; i < _purchased.length; i++) {
            var p = _purchased[i];
            var itemName = String(p[1]);
            var qty = p[p.length - 1];
            var catItem = findCatalogByName(itemName);
            var displayName = catItem ? catItem.displayname : itemName;
            var iconName = catItem ? catItem.icon : itemName;

            var row = document.createElement('div');
            row.className = 'kshop-claim-row';
            row.setAttribute('data-pidx', i);
            if (catItem) row.setAttribute('data-idx', catItem.idx);
            row.innerHTML =
                '<span class="kshop-cart-thumb">' + iconHtml(iconName, 'kshop-row-icon') + '</span>' +
                '<span class="kshop-claim-name">' + escHtml(displayName) + ' ×' + qty + '</span>' +
                '<button class="kshop-claim-btn" data-pidx="' + i + '">领取</button>';
            row.querySelector('.kshop-claim-btn').addEventListener('click', onClaim);
            if (catItem) row.addEventListener('click', onClaimRowClick);
            _claimList.appendChild(row);
        }
    }

    function onClaimRowClick(e) {
        if (e.target.classList.contains('kshop-claim-btn')) return;
        var idx = Number(e.currentTarget.getAttribute('data-idx'));
        if (!isNaN(idx)) showItemDetail(idx, e.currentTarget);
    }

    function onClaim(e) {
        e.stopPropagation();
        var pidx = Number(e.target.getAttribute('data-pidx'));
        e.target.disabled = true;
        var reqId = 'cl' + (++_reqSeq);
        _pendingReq[reqId] = function(resp) {
            delete _pendingReq[reqId];
            if (!Panels.isOpen()) return;
            if (resp.success) {
                _purchased = resp.purchased || [];
                renderClaimed();
                toast('领取成功！');
            } else {
                toast('领取失败: ' + (resp.error || 'unknown'));
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
            delete _pendingReq[reqId];
            if (!Panels.isOpen()) return;
            if (resp.success) {
                doClose();
            } else if (resp.error === 'timeout') {
                _closing = false;
                showSaveFailedDialog('保存超时，状态未知', true);
            } else {
                _closing = false;
                showSaveFailedDialog(resp.error || '保存失败', false);
            }
        };
        Bridge.send({type:'panel', cmd:'saveCart', callId: reqId, cart: cartPayload});
    }

    function doClose() {
        _pendingReq = {};
        dismissDialog();
        dismissQtyInput();
        hideTooltip();
        Panels.close();
        Bridge.send({type:'panel', cmd:'close', panel:'kshop'});
        UiData.off('k', _kHandler);
        _closing = false;
    }

    function hideTooltip() {
        _tooltipHovering = -1;
        PanelTooltip.hide();
    }

    function showSaveFailedDialog(msg, timeoutMode) {
        var dlg = _el.querySelector('#kshop-dialog');
        if (!dlg) return;
        var btns = '<button class="kshop-dlg-btn" data-action="retry">重试</button>';
        if (!timeoutMode) btns += '<button class="kshop-dlg-btn" data-action="cancel">继续购物</button>';
        btns += '<button class="kshop-dlg-btn kshop-dlg-danger" data-action="force">强制关闭</button>';

        dlg.innerHTML =
            '<div class="kshop-dlg-inner">' +
                '<div class="kshop-dlg-title">⚠ ' + escHtml(msg) + '</div>' +
                '<div class="kshop-dlg-hint">' +
                    (timeoutMode ? '购物车状态未知，强制关闭可能丢失购物车' : '可重试或继续购物') +
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
        dismissQtyInput();
        hideTooltip();
        UiData.off('k', _kHandler);
        toast('连接断开，商城已关闭');
    }

    return {};
})();
