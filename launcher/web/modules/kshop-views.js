/**
 * KShop view composition.
 *
 * This module owns DOM/view construction only. K-point authority, cart persistence,
 * checkout reconciliation and claim writes remain in kshop-runtime.js / kshop.js.
 */
(function(root, factory) {
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.KShopViews = api;
})(typeof window !== 'undefined' ? window : this, function() {
    'use strict';

    function createCatalog(options) {
        var root = document.createElement('div');
        root.className = 'workbench-view kshop-catalog-view';
        root.setAttribute('data-view-binding', 'shop:catalog');

        var chrome = new Workbench.ViewChrome({ kicker: '', title: '商品', meta: '同步中' });
        var categoryBar = document.createElement('div');
        categoryBar.className = 'kshop-categories';
        categoryBar.id = 'kshop-cat-bar';
        chrome.setToolbar(categoryBar);

        var gridWrap = document.createElement('div');
        gridWrap.className = 'kshop-grid-wrap workbench-grid-wrap';
        var loading = document.createElement('div');
        loading.className = 'kshop-loading';
        loading.id = 'kshop-loading';
        loading.textContent = '正在加载商品…';
        var renderer = new Workbench.GridRenderer({
            className: 'kshop-grid workbench-catalog-grid',
            emptyText: '当前筛选无商品；返回上级分类或切换专柜',
            keyOf: function(item) { return item.idx; },
            renderItem: options.renderItem,
            bindItem: options.bindItem
        });
        renderer.root.id = 'kshop-grid';
        gridWrap.appendChild(loading);
        gridWrap.appendChild(renderer.root);
        root.appendChild(chrome.root);
        root.appendChild(gridWrap);

        var view = {
            instanceKey: 'shop:catalog',
            instancePolicy: 'singletonByBinding',
            allowedSlots: ['L'],
            viewKind: 'catalog',
            mount: function(container) { container.appendChild(root); },
            unmount: function() { if (root.parentNode) root.parentNode.removeChild(root); },
            render: options.render,
            exportOffer: options.exportOffer,
            getRoot: function() { return root; }
        };
        return { view: view, root: root, chrome: chrome, categoryBar: categoryBar,
            grid: renderer.root, loading: loading, renderer: renderer };
    }

    function createOrder(options) {
        var root = document.createElement('div');
        root.className = 'workbench-view kshop-order-view';
        root.setAttribute('data-view-binding', 'shop:cart');

        var cartAdapter = new Workbench.ContainerViewAdapter({
            instanceKey: 'shop:cart-items',
            itemModel: 'intent',
            getItems: options.getCart,
            keyOf: function(item) { return item.idx; },
            renderItem: options.renderCartItem,
            bindItem: options.bindCartItem,
            probeAccept: options.probeAccept
        });
        var cartGridView = new Workbench.GridContainerView({
            adapter: cartAdapter,
            title: '购物车',
            kicker: '',
            meta: '0 种 / 0 件',
            className: 'kshop-cart-section',
            gridClassName: 'kshop-cart-list',
            emptyText: '购物车为空；从左侧选择商品，双击也可加购'
        });
        cartGridView.renderer.root.id = 'kshop-cart-list';

        var dropTarget = document.createElement('button');
        dropTarget.type = 'button';
        dropTarget.className = 'kshop-cart-drop-target';
        dropTarget.setAttribute('data-audio-cue', 'select');
        dropTarget.innerHTML = '<span class="kshop-drop-glyph">＋</span>'
            + '<span class="kshop-drop-copy"><b>添加商品</b><small>选择或拖入</small></span>';
        dropTarget.setAttribute('aria-label', '选择商品后点击，或将商品拖入购物车');
        dropTarget.addEventListener('click', options.onCartSinkClick);
        cartGridView.root.insertBefore(dropTarget, cartGridView.renderer.root);

        var footer = document.createElement('div');
        footer.className = 'kshop-cart-footer workbench-commit-bar';
        footer.innerHTML = '<span class="workbench-commit-summary">预计结算 <b id="kshop-cart-total">0</b> K</span>'
            + '<button class="kshop-checkout-btn" id="kshop-checkout" data-audio-cue="confirm">核对并结账</button>';
        var cartTotal = footer.querySelector('#kshop-cart-total');
        var checkoutButton = footer.querySelector('#kshop-checkout');
        checkoutButton.addEventListener('click', options.onCheckout);
        cartGridView.root.appendChild(footer);

        var purchasedAdapter = new Workbench.ContainerViewAdapter({
            instanceKey: 'shop:purchased-items',
            itemModel: 'owned-pending',
            getItems: options.getPurchased,
            keyOf: function(item, index) { return index + ':' + String(item && item[1]); },
            renderItem: options.renderPurchasedItem,
            bindItem: options.bindPurchasedItem
        });
        var purchasedGridView = new Workbench.GridContainerView({
            adapter: purchasedAdapter,
            title: '历史待领取',
            kicker: '',
            meta: '',
            className: 'kshop-purchased-section',
            gridClassName: 'kshop-claim-list',
            emptyText: '没有待领取商品；新购买会直接送入背包'
        });
        purchasedGridView.renderer.root.id = 'kshop-claim-list';

        cartGridView.mount(root);
        purchasedGridView.mount(root);
        var view = {
            instanceKey: 'shop:cart',
            instancePolicy: 'singletonByBinding',
            allowedSlots: ['L', 'R'],
            viewKind: 'intent-composite',
            mount: function(container) { container.appendChild(root); },
            unmount: function() { if (root.parentNode) root.parentNode.removeChild(root); },
            render: options.render,
            probeAccept: options.probeAccept,
            getRoot: function() { return root; }
        };
        return {
            view: view,
            root: root,
            cartGridView: cartGridView,
            purchasedGridView: purchasedGridView,
            cartList: cartGridView.renderer.root,
            claimList: purchasedGridView.renderer.root,
            dropTarget: dropTarget,
            dropLabel: dropTarget.querySelector('small'),
            cartTotal: cartTotal,
            checkoutButton: checkoutButton
        };
    }

    function SettlementPage(options) {
        this._options = options;
        this._errorMessage = '';
        this._preview = null;
        this._loading = false;
        this.root = document.createElement('section');
        this.root.className = 'workbench-secondary-page kshop-settlement-page';
        this.root.setAttribute('role', 'dialog');
        this.root.setAttribute('aria-label', 'K 点商城结算核对');
        this.root.innerHTML = '<header class="kshop-settlement-header">'
            + '<button type="button" data-kshop-settlement-back data-audio-cue="cancel">← 返回商城</button>'
            + '<div><h2>结算核对</h2><p>价格、余额与交付容量由游戏实时核算；确认后整单扣款并直接交付。</p></div>'
            + '</header><div class="kshop-settlement-body">'
            + '<section><h3 data-kshop-settlement-count>购物车</h3><div class="kshop-settlement-list"></div></section>'
            + '<aside class="kshop-settlement-ledger"><h3>结算摘要</h3><div data-kshop-settlement-ledger></div>'
            + '<p class="kshop-settlement-authority">容量不足时整单不扣 K 点。历史存档的待领取商品仍可在商城主页面继续领取。</p></aside>'
            + '</div><footer class="kshop-settlement-summary"><span data-kshop-settlement-status></span>'
            + '<button type="button" data-kshop-settlement-commit data-audio-cue="confirm">确认结账</button></footer>';
        this._list = this.root.querySelector('.kshop-settlement-list');
        this._count = this.root.querySelector('[data-kshop-settlement-count]');
        this._ledger = this.root.querySelector('[data-kshop-settlement-ledger]');
        this._status = this.root.querySelector('[data-kshop-settlement-status]');
        this._commit = this.root.querySelector('[data-kshop-settlement-commit]');
        this._back = this.root.querySelector('[data-kshop-settlement-back]');
        this._back.addEventListener('click', options.onBack);
        this._commit.addEventListener('click', options.onCommit);
    }

    SettlementPage.prototype.mount = function(container) { container.appendChild(this.root); };
    SettlementPage.prototype.isActive = function() { return this.root.classList.contains('active'); };
    SettlementPage.prototype.debugState = function() {
        return {active:this.isActive(),loading:this._loading,hasPreview:!!this._preview,
            previewCanCommit:!!(this._preview && this._preview.canCommit),commitDisabled:this._commit.disabled};
    };
    SettlementPage.prototype.show = function() {
        this._errorMessage = '';
        this._preview = null;
        this._loading = true;
        this._list.scrollTop = 0;
        this._list.scrollLeft = 0;
        this.root.classList.add('active');
        this._options.panelRoot.classList.add('kshop-settling');
        this.render();
        this._back.focus();
    };
    SettlementPage.prototype.hide = function() {
        this.root.classList.remove('active');
        this._options.panelRoot.classList.remove('kshop-settling');
        this._errorMessage = '';
        this._preview = null;
        this._loading = false;
    };
    SettlementPage.prototype.setLoading = function() {
        this._preview = null;
        this._loading = true;
        this._errorMessage = '';
        this.render();
    };
    SettlementPage.prototype.setPreview = function(preview) {
        this._preview = preview || null;
        this._loading = false;
        this._errorMessage = '';
        this.render();
    };
    SettlementPage.prototype.setError = function(message) {
        this._loading = false;
        this._preview = null;
        this._errorMessage = String(message || '');
        this.render();
    };
    SettlementPage.prototype.render = function() {
        if (!this.isActive()) return;
        var options = this._options;
        var cart = options.getCart();
        if (!cart.length) { this.hide(); return; }
        var previousScrollTop = this._list.scrollTop;
        var previousScrollLeft = this._list.scrollLeft;
        while (this._list.firstChild) this._list.removeChild(this._list.firstChild);
        var preview = this._preview;
        var previewByIndex = {};
        if (preview && preview.purchaseLines) {
            for (var previewIndex = 0; previewIndex < preview.purchaseLines.length; previewIndex++) {
                previewByIndex[String(preview.purchaseLines[previewIndex].catalogIndex)] = preview.purchaseLines[previewIndex];
            }
        }
        var total = 0;
        var quantity = 0;
        var invalid = 0;
        for (var i = 0; i < cart.length; i++) {
            var cartItem = cart[i];
            var item = options.findCatalogItem(cartItem.idx);
            var qty = Math.max(1, Number(cartItem.qty) || 1);
            quantity += qty;
            if (item) total += Number(item.price || 0) * qty;
            else invalid++;
            this._list.appendChild(this._renderLine(cartItem, item, qty, previewByIndex[String(cartItem.idx)]));
        }
        this._count.textContent = '购物车 · ' + cart.length + ' 种 / ' + quantity + ' 件';
        var balance = preview ? Number(preview.balance || 0) : Number(options.getBalance() || 0);
        if (preview) total = Number(preview.total || 0);
        var projected = preview ? Number(preview.projectedBalance || 0) : balance - total;
        this._ledger.innerHTML = '<div><span>当前 K 点</span><strong>' + balance.toLocaleString() + '</strong></div>'
            + '<div><span>预计支付</span><strong>− ' + total.toLocaleString() + '</strong></div>'
            + '<div class="kshop-settlement-balance' + (projected < 0 ? ' negative' : '') + '"><span>预计结余</span><strong>' + projected.toLocaleString() + '</strong></div>';
        var status = this._errorMessage;
        if (!status && this._loading) status = '游戏正在核算价格、余额与背包容量…';
        if (!status && invalid) status = '目录已变化，请移除失效商品后再结账。';
        if (!status && preview && preview.blockingError === 'insufficient_kpoints') status = 'K 点不足，整单不会扣款。';
        if (!status && preview && preview.blockingError === 'inventory_full') status = '背包容量不足，请先到“战备箱”整理空间。';
        if (!status && preview) status = '权威核算完成，可直接交付到对应物品栏。';
        this._status.textContent = status;
        this._status.classList.toggle('error', !!this._errorMessage || !!invalid || !!(preview && preview.blockingError));
        this._commit.disabled = invalid > 0 || this._loading || !preview || !preview.canCommit || !options.canCheckout();
        this._list.scrollTop = previousScrollTop;
        this._list.scrollLeft = previousScrollLeft;
    };
    SettlementPage.prototype._renderLine = function(cartItem, item, quantity, authorityLine) {
        var options = this._options;
        var row = document.createElement('article');
        row.className = 'kshop-settlement-line';
        row.setAttribute('data-idx', cartItem.idx);
        var icon = document.createElement('span');
        icon.className = 'kshop-settlement-icon';
        icon.innerHTML = options.iconHtml(item ? item.icon : '', 'kshop-icon');
        var copy = document.createElement('span');
        copy.className = 'kshop-settlement-copy';
        var name = document.createElement('b');
        name.textContent = item ? item.displayname : ('失效商品 #' + cartItem.idx);
        var price = document.createElement('small');
        var unitPrice = authorityLine ? Number(authorityLine.unitPrice || 0) : Number(item && item.price || 0);
        var lineTotal = authorityLine ? Number(authorityLine.total || 0) : unitPrice * quantity;
        price.textContent = item ? ('K ' + unitPrice.toLocaleString() + ' / 件 · 小计 '
            + lineTotal.toLocaleString()) : '目录中已不存在';
        copy.appendChild(name);
        copy.appendChild(price);
        if (authorityLine) {
            var bound = document.createElement('em');
            bound.textContent = '当前最多可购 ' + Number(authorityLine.maxPurchasable || 0)
                + ' · 容量上限 ' + Number(authorityLine.maxByCapacity || 0);
            copy.appendChild(bound);
        }
        var stepper = document.createElement('span');
        stepper.className = 'kshop-settlement-stepper';
        if (item && options.isStackable(item)) {
            stepper.appendChild(this._button('−', function() { options.adjustQuantity(cartItem.idx, -1, false); }));
            var amount = document.createElement('b'); amount.textContent = String(quantity); stepper.appendChild(amount);
            stepper.appendChild(this._button('+', function() { options.adjustQuantity(cartItem.idx, 1, false); }));
            var plusFive = this._button('+5', function() { options.adjustQuantity(cartItem.idx, 5, false); });
            plusFive.classList.add('wide'); stepper.appendChild(plusFive);
            if (authorityLine && Number(authorityLine.maxPurchasable) > 0) {
                var maximum = this._button('最大', function() {
                    options.setQuantity(cartItem.idx, Number(authorityLine.maxPurchasable));
                });
                maximum.classList.add('wide'); stepper.appendChild(maximum);
            }
        } else if (item) {
            var fixed = document.createElement('b'); fixed.textContent = '1 件'; stepper.appendChild(fixed);
        }
        var remove = this._button('移除', function() { options.adjustQuantity(cartItem.idx, 0, true); });
        remove.classList.add('wide', 'remove'); stepper.appendChild(remove);
        var editable = options.canEditCart() && !this._loading;
        var buttons = stepper.querySelectorAll('button');
        for (var i = 0; i < buttons.length; i++) buttons[i].disabled = !editable;
        if (item && options.onInspect) row.addEventListener('click', function(event) {
            if (event.target.closest && event.target.closest('button')) return;
            options.onInspect(cartItem.idx, row);
        });
        row.appendChild(icon); row.appendChild(copy); row.appendChild(stepper);
        return row;
    };
    SettlementPage.prototype._button = function(label, handler) {
        var button = document.createElement('button');
        button.type = 'button'; button.textContent = label;
        button.addEventListener('click', handler);
        return button;
    };

    return { createCatalog: createCatalog, createOrder: createOrder, SettlementPage: SettlementPage };
});
