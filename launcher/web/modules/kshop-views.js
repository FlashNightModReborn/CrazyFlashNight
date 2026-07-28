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
            emptyText: '购物车为空；单击左侧商品即可加购，也可拖入这里'
        });
        cartGridView.renderer.root.id = 'kshop-cart-list';

        var dropTarget = document.createElement('button');
        dropTarget.type = 'button';
        dropTarget.className = 'kshop-cart-drop-target';
        dropTarget.setAttribute('data-audio-cue', 'select');
        dropTarget.innerHTML = '<span class="kshop-drop-glyph">＋</span>'
            + '<span class="kshop-drop-copy"><b>拖拽加购</b><small>可选操作</small></span>';
        dropTarget.setAttribute('aria-label', '可将商品拖入购物车；单击商品也可直接加购');
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
        this._components = options.components || (typeof WorkbenchComponents !== 'undefined'
            ? WorkbenchComponents : null);
        if (!this._components || typeof this._components.SecondaryPage !== 'function'
                || typeof this._components.QuantityControl !== 'function') {
            throw new Error('KShop SettlementPage requires shared workbench components');
        }
        this._errorMessage = '';
        this._preview = null;
        this._loading = false;
        this._lineRecords = {};
        this.root = document.createElement('section');
        this.root.className = 'kshop-settlement-page';
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
        this._commitHandler = options.onCommit;
        this._commit.addEventListener('click', this._commitHandler);
        this.secondary = new this._components.SecondaryPage({
            root:this.root,
            role:'dialog',
            ariaLabel:'K 点商城结算核对',
            removeOnDestroy:true
        });
        this.secondary.bindClose(this._back, options.onBack);
    }

    SettlementPage.prototype.mount = function(container) { return this.secondary.mount(container); };
    SettlementPage.prototype.isActive = function() { return this.secondary.isActive(); };
    SettlementPage.prototype.debugState = function() {
        return {active:this.isActive(),loading:this._loading,hasPreview:!!this._preview,
            previewCanCommit:!!(this._preview && this._preview.canCommit),commitDisabled:this._commit.disabled,
            stableLineCount:Object.keys(this._lineRecords).length};
    };
    SettlementPage.prototype.show = function() {
        this._errorMessage = '';
        this._preview = null;
        this._loading = true;
        this._list.scrollTop = 0;
        this._list.scrollLeft = 0;
        this._options.panelRoot.classList.add('kshop-settling');
        if (!this.secondary.open({initialFocus:this._back})) {
            this._options.panelRoot.classList.remove('kshop-settling');
            return false;
        }
        this.render();
        return true;
    };
    SettlementPage.prototype.hide = function(reason) {
        this._options.panelRoot.classList.remove('kshop-settling');
        this._errorMessage = '';
        this._preview = null;
        this._loading = false;
        var closed = this.secondary.close(reason || 'return');
        this._destroyQuantityControls();
        return closed;
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
        var nextRecords = {};
        var desiredRows = [];
        for (var i = 0; i < cart.length; i++) {
            var cartItem = cart[i];
            var item = options.findCatalogItem(cartItem.idx);
            var qty = Math.max(1, Number(cartItem.qty) || 1);
            quantity += qty;
            if (item) total += Number(item.price || 0) * qty;
            else invalid++;
            var identity = String(cartItem.idx);
            if (nextRecords[identity]) continue;
            var variant = !item ? 'missing' : options.isStackable(item) ? 'stackable' : 'fixed';
            var record = this._lineRecords[identity];
            if (record && record.variant !== variant) {
                this._destroyLineRecord(record);
                record = null;
            }
            if (!record) record = this._createLineRecord(cartItem, item, variant);
            this._updateLineRecord(record, cartItem, item, qty, previewByIndex[identity]);
            nextRecords[identity] = record;
            desiredRows.push(record.row);
        }
        for (var oldIdentity in this._lineRecords) {
            if (Object.prototype.hasOwnProperty.call(this._lineRecords, oldIdentity)
                    && !nextRecords[oldIdentity]) {
                this._destroyLineRecord(this._lineRecords[oldIdentity]);
            }
        }
        this._lineRecords = nextRecords;
        for (var rowIndex = 0; rowIndex < desiredRows.length; rowIndex++) {
            var currentRow = this._list.children[rowIndex] || null;
            if (currentRow !== desiredRows[rowIndex]) this._list.insertBefore(desiredRows[rowIndex], currentRow);
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
        if (!status && preview && preview.blockingError === 'destination_full') status = '对应收集项已达持有上限，请减少数量。';
        if (!status && preview) status = '权威核算完成，可直接交付到对应物品栏。';
        this._status.textContent = status;
        this._status.classList.toggle('error', !!this._errorMessage || !!invalid || !!(preview && preview.blockingError));
        this._commit.disabled = invalid > 0 || this._loading || !preview || !preview.canCommit || !options.canCheckout();
        this._list.scrollTop = previousScrollTop;
        this._list.scrollLeft = previousScrollLeft;
    };
    SettlementPage.prototype._createLineRecord = function(cartItem, item, variant) {
        var options = this._options;
        var identity = String(cartItem.idx);
        var record = {identity:identity, variant:variant};
        var row = document.createElement('article');
        row.className = 'kshop-settlement-line';
        row.setAttribute('data-idx', cartItem.idx);
        record.row = row;
        var icon = document.createElement('span');
        icon.className = 'kshop-settlement-icon';
        record.icon = icon;
        var copy = document.createElement('span');
        copy.className = 'kshop-settlement-copy';
        record.copy = copy;
        var name = document.createElement('button');
        name.type = 'button';
        name.className = 'kshop-settlement-inspect';
        name.addEventListener('click', function(event) {
            if (event.stopPropagation) event.stopPropagation();
            if (record.itemAvailable && options.onInspect) options.onInspect(Number(identity), row);
        });
        record.name = name;
        var price = document.createElement('small');
        record.price = price;
        var bound = document.createElement('em');
        record.bound = bound;
        copy.appendChild(name);
        copy.appendChild(price);
        copy.appendChild(bound);
        var stepper = document.createElement('span');
        stepper.className = 'kshop-settlement-stepper';
        record.stepper = stepper;
        if (variant === 'stackable') {
            record.control = new this._components.QuantityControl({
                document:document,
                className:'workbench-quantity-control kshop-settlement-quantity',
                min:1,
                max:1,
                value:1,
                showPlusFive:true,
                showMax:true,
                showRange:true,
                onChange:function(value) { options.setQuantity(Number(identity), value); }
            });
            stepper.appendChild(record.control.root);
        } else if (variant === 'fixed') {
            record.fixed = document.createElement('b');
            record.fixed.textContent = '1 件';
            stepper.appendChild(record.fixed);
        }
        record.remove = this._button('移除', function() {
            options.adjustQuantity(Number(identity), 0, true);
        });
        record.remove.classList.add('wide', 'remove');
        stepper.appendChild(record.remove);
        row.addEventListener('click', function(event) {
            if (event.target.closest && event.target.closest('button,.workbench-quantity-control')) return;
            if (record.itemAvailable && options.onInspect) options.onInspect(Number(identity), row);
        });
        row.appendChild(icon); row.appendChild(copy); row.appendChild(stepper);
        return record;
    };
    SettlementPage.prototype._updateLineRecord = function(record, cartItem, item, quantity, authorityLine) {
        var options = this._options;
        record.itemAvailable = !!item;
        record.row.setAttribute('data-idx', cartItem.idx);
        var iconKey = String(item ? item.icon : '');
        if (record.iconKey !== iconKey) {
            record.iconKey = iconKey;
            record.icon.innerHTML = options.iconHtml(iconKey, 'kshop-icon');
        }
        var displayName = item ? item.displayname : ('失效商品 #' + cartItem.idx);
        record.name.textContent = displayName;
        record.name.disabled = !item || !options.onInspect;
        record.name.setAttribute('aria-label', item ? '查看 ' + displayName + ' 详情' : displayName);
        var unitPrice = authorityLine ? Number(authorityLine.unitPrice || 0) : Number(item && item.price || 0);
        var lineTotal = authorityLine ? Number(authorityLine.total || 0) : unitPrice * quantity;
        record.price.textContent = item ? ('K ' + unitPrice.toLocaleString() + ' / 件 · 小计 '
            + lineTotal.toLocaleString()) : '目录中已不存在';
        if (authorityLine) {
            record.bound.hidden = false;
            record.bound.textContent = '当前可直接结算 ' + Number(authorityLine.maxPurchasable || 0)
                + ' · 容量上限 ' + Number(authorityLine.maxByCapacity || 0);
        } else {
            record.bound.hidden = true;
            record.bound.textContent = '';
        }
        var editable = options.canEditCart() && !this._loading;
        if (record.control) {
            var catalogMaximum = Math.floor(Number(item && item.maxQuantity));
            var previewMaximum = Math.floor(Number(authorityLine && authorityLine.maxQuantity));
            var authorityMaximum = isFinite(previewMaximum) && previewMaximum > 0
                ? previewMaximum : isFinite(catalogMaximum) && catalogMaximum > 0
                    ? catalogMaximum : quantity;
            authorityMaximum = Math.max(1, quantity, authorityMaximum);
            var effective = authorityLine
                ? Math.max(0, Math.floor(Number(authorityLine.maxPurchasable || 0)))
                : 0;
            record.control.root.setAttribute('aria-label', displayName + '购买数量');
            record.control.update({
                min:1,
                max:authorityMaximum,
                presetMax:effective,
                sliderMax:authorityMaximum,
                value:quantity,
                disabled:!editable,
                maxLabel:'可用',
                maxAriaLabel:'设为当前可直接结算上限'
            });
        }
        record.remove.disabled = !editable;
    };
    SettlementPage.prototype._destroyLineRecord = function(record) {
        if (!record) return;
        if (record.control) record.control.destroy();
        if (record.row.parentNode) record.row.parentNode.removeChild(record.row);
    };
    SettlementPage.prototype._destroyQuantityControls = function() {
        for (var identity in this._lineRecords) {
            if (Object.prototype.hasOwnProperty.call(this._lineRecords, identity)) {
                this._destroyLineRecord(this._lineRecords[identity]);
            }
        }
        this._lineRecords = {};
    };
    SettlementPage.prototype._button = function(label, handler) {
        var button = document.createElement('button');
        button.type = 'button'; button.textContent = label;
        button.addEventListener('click', handler);
        return button;
    };
    SettlementPage.prototype.destroy = function() {
        this._options.panelRoot.classList.remove('kshop-settling');
        this._destroyQuantityControls();
        this._commit.removeEventListener('click', this._commitHandler);
        return this.secondary.destroy();
    };

    return { createCatalog: createCatalog, createOrder: createOrder, SettlementPage: SettlementPage };
});
