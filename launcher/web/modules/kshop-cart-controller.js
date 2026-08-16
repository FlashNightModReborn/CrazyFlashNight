/**
 * KShop cart and settlement controller.
 *
 * The controller owns interaction/presentation state only. Cart authority is
 * read and replaced through ports supplied by kshop.js; transport and writes
 * remain outside this module.
 */
(function(root, factory) {
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.KShopCartController = api;
})(typeof window !== 'undefined' ? window : this, function() {
    'use strict';

    function copyCart(cart) {
        var result = [];
        cart = cart || [];
        for (var i = 0; i < cart.length; i++) {
            result.push({idx:Number(cart[i].idx), qty:Math.max(1, Math.floor(Number(cart[i].qty) || 1))});
        }
        return result;
    }

    function quantityLimit(item, stackable) {
        if (!stackable) return 1;
        var authority = Number(item && item.maxQuantity);
        // 老版 Flash 未下发 maxQuantity 时保留旧 999 护栏；新版由权威目录显式给出。
        if (!isFinite(authority) || authority < 0) return 999;
        return Math.min(999999, Math.floor(authority));
    }

    function sanitizeCart(cart, findCatalogItem, isStackable) {
        var next = [], adjusted = false, seen = {};
        cart = cart || [];
        for (var i = 0; i < cart.length; i++) {
            var idx = Number(cart[i].idx);
            var item = findCatalogItem(idx);
            if (!item || seen[idx]) { adjusted = true; continue; }
            var maximum = quantityLimit(item, isStackable(item));
            var raw = Number(cart[i].qty);
            if (!isFinite(raw) || raw <= 0 || maximum <= 0) { adjusted = true; continue; }
            var qty = Math.min(maximum, Math.floor(raw));
            if (qty !== raw) adjusted = true;
            seen[idx] = true;
            next.push({idx:idx, qty:qty});
        }
        return {cart:next, adjusted:adjusted};
    }

    function buildPayload(cart) { return copyCart(cart); }

    function quantity(cart) {
        var value = 0;
        cart = cart || [];
        for (var i = 0; i < cart.length; i++) value += Number(cart[i].qty) || 0;
        return value;
    }

    function total(cart, findCatalogItem) {
        var value = 0;
        cart = cart || [];
        for (var i = 0; i < cart.length; i++) {
            var item = findCatalogItem(cart[i].idx);
            if (item) value += Number(item.price) * (Number(cart[i].qty) || 0);
        }
        return value;
    }

    function addItem(cart, idx, qty, stackable, maximum) {
        var next = copyCart(cart);
        idx = Number(idx);
        qty = Math.max(1, Math.floor(Number(qty) || 1));
        maximum = stackable ? Math.max(0, Math.floor(Number(maximum))) : 1;
        if (!isFinite(maximum)) maximum = stackable ? 999 : 1;
        if (maximum <= 0) return {changed:false, error:'sold_out', cart:next};
        for (var i = 0; i < next.length; i++) {
            if (next[i].idx !== idx) continue;
            if (!stackable) return {changed:false, error:'duplicate_single', cart:next};
            var requested = next[i].qty + qty;
            var combined = Math.min(maximum, requested);
            if (combined === next[i].qty) return {changed:false, error:'limit_reached', cart:next};
            next[i].qty = combined;
            return {changed:true, error:combined < requested ? 'limit_reached' : '', cart:next};
        }
        var inserted = stackable ? Math.min(maximum, qty) : 1;
        next.push({idx:idx, qty:inserted});
        return {changed:true, error:inserted < qty ? 'limit_reached' : '', cart:next};
    }

    function adjustItem(cart, idx, delta, removeAll, maximum) {
        var next = copyCart(cart);
        idx = Number(idx);
        for (var i = 0; i < next.length; i++) {
            if (next[i].idx !== idx) continue;
            if (removeAll) next.splice(i, 1);
            else {
                next[i].qty += Number(delta) || 0;
                if (next[i].qty <= 0) next.splice(i, 1);
                else if (isFinite(Number(maximum)) && next[i].qty > Number(maximum)) {
                    if (Number(maximum) <= 0) {
                        next.splice(i, 1);
                        return {changed:true, error:'sold_out', cart:next};
                    }
                    next[i].qty = Math.floor(Number(maximum));
                    return {changed:true, error:'limit_reached', cart:next};
                }
            }
            return {changed:true, cart:next};
        }
        return {changed:false, cart:next};
    }

    function setItemQuantity(cart, idx, value, maximum) {
        var next = copyCart(cart);
        idx = Number(idx);
        var target = Math.max(1, Math.floor(Number(value) || 1));
        if (isFinite(Number(maximum))) target = Math.min(target, Math.max(0, Math.floor(Number(maximum))));
        for (var i = 0; i < next.length; i++) {
            if (next[i].idx !== idx) continue;
            if (target <= 0) {
                next.splice(i, 1);
                return {changed:true, error:'sold_out', cart:next};
            }
            if (next[i].qty === target) return {changed:false, cart:next};
            next[i].qty = target;
            return {changed:true, cart:next};
        }
        return {changed:false, cart:next};
    }

    function validPreview(resp) {
        return !!resp && resp.success === true && resp.v === 1
            && typeof resp.checkoutToken === 'string' && resp.checkoutToken.length > 0
            && Array.isArray(resp.purchaseLines) && typeof resp.canCommit === 'boolean'
            && isFinite(Number(resp.total)) && isFinite(Number(resp.balance))
            && isFinite(Number(resp.projectedBalance)) && typeof resp.blockingError === 'string';
    }

    function CartController(options) {
        options = options || {};
        this._state = options.state || {};
        this._intent = options.intent || {};
        this._composition = null;
        this._settlement = null;
        this._preview = null;
        this._previewBusy = false;
        this._previewQueued = false;
        this._previewRevision = 0;
    }

    CartController.prototype._cart = function() {
        return this._state.getCart ? this._state.getCart() || [] : [];
    };

    CartController.prototype.buildPayload = function() { return buildPayload(this._cart()); };
    CartController.prototype.quantity = function() { return quantity(this._cart()); };
    CartController.prototype.getComposition = function() { return this._composition; };
    CartController.prototype.getSettlement = function() { return this._settlement; };

    CartController.prototype.createOrderView = function(options) {
        options = options || {};
        var self = this;
        this._composition = KShopViews.createOrder({
            getItems:function() { return self._cart(); },
            getCart:function() { return self._cart(); },
            getPurchased:options.getPurchased,
            renderCartItem:function(item) { return self.renderRow(item); },
            bindCartItem:function(row) { self.bindRow(row); },
            renderPurchasedItem:options.renderPurchasedItem,
            bindPurchasedItem:options.bindPurchasedItem,
            probeAccept:function(offer) { return self.probeAccept(offer); },
            onCartSinkClick:function() { self.onCartSinkClick(); },
            onCheckout:function() { self.openSettlement(); },
            render:function() { self.render(); if (options.renderPurchased) options.renderPurchased(); }
        });
        return this._composition.view;
    };

    CartController.prototype.mountSettlement = function(panelRoot) {
        var self = this;
        this._settlement = new KShopViews.SettlementPage({
            panelRoot:panelRoot,
            getCart:function() { return self._cart(); },
            getBalance:function() { return self._state.getBalance ? self._state.getBalance() : 0; },
            findCatalogItem:function(idx) { return self._state.findCatalogItem(idx); },
            isStackable:function(item) { return self._state.isStackable(item); },
            iconHtml:function(name, cls) { return self._intent.iconHtml(name, cls); },
            canEditCart:function() { return self._state.canEdit(); },
            canCheckout:function() { return self._state.canStartWrite(); },
            adjustQuantity:function(idx, delta, removeAll) { self.adjust(idx, delta, removeAll); },
            setQuantity:function(idx, value) { self.setQuantity(idx, value); },
            onInspect:function(idx, anchor) { if (self._intent.inspect) self._intent.inspect(idx, anchor); },
            onBack:function() { self.closeSettlement(); },
            onHelp:function(event) {
                if (self._intent.openHelp) self._intent.openHelp(event && event.currentTarget);
            },
            onClose:function() {
                self.closeSettlement();
                if (self._intent.requestPanelClose) self._intent.requestPanelClose();
            },
            onCommit:function() { self.checkout(); }
        });
        this._settlement.mount(panelRoot);
        return this._settlement;
    };

    CartController.prototype.probeAccept = function(offer) {
        if (!this._state.canEdit()) return {accepted:false, reason:'write_locked'};
        if (!offer || offer.subjectKind !== 'catalogEntry') return {accepted:false, reason:'unsupported_subject'};
        var operations = offer.offeredOperations || [];
        var accepted = false;
        for (var i = 0; i < operations.length; i++) if (operations[i] === 'shop.addCartIntent') accepted = true;
        if (!accepted) return {accepted:false, reason:'unsupported_operation'};
        return {accepted:true, operationId:'shop.addCartIntent', targetRef:{binding:'shop:cart'}, hint:'append'};
    };

    CartController.prototype.onCartSinkClick = function() {
        var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
        if (!this._state.canEdit()) {
            this._intent.toast('商城正在处理写入，请稍后再加购。');
            if (A && typeof A.cue === 'function') A.cue('illegal');
            return;
        }
        var result = this._intent.activateSelected();
        if (!result.accepted && result.reason === 'nothing_selected') {
            this._intent.toast('请先从左栏选择商品。');
            if (A && typeof A.cue === 'function') A.cue('illegal');
        }
    };

    CartController.prototype.setDropSelection = function(item) {
        if (!this._composition) return;
        this._composition.dropTarget.classList.toggle('has-selection', !!item);
        this._composition.dropLabel.textContent = item ? item.displayname + ' · 可拖入' : '可选操作';
    };

    CartController.prototype.addCatalogIntent = function(idx, qty) {
        if (!this._state.canEdit()) return false;
        var item = this._state.findCatalogItem(idx);
        if (!item || this._state.isLocked(item) || item.type === '非卖品') return false;
        var stackable = this._state.isStackable(item);
        var maximum = quantityLimit(item, stackable);
        var result = addItem(this._cart(), idx, qty, stackable, maximum);
        if (!result.changed) {
            if (result.error === 'duplicate_single') this._intent.toast('该装备已在购物车中');
            else if (result.error === 'sold_out') this._intent.toast('该商品当前已达持有上限。');
            else if (result.error === 'limit_reached') this._intent.toast('已达到当前可购买上限 ' + maximum + '。');
            var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
            if (A && typeof A.cue === 'function') A.cue('illegal');
            return false;
        }
        this._commitCart(result.cart);
        if (result.error === 'limit_reached') this._intent.toast('数量已调整为当前可购买上限 ' + maximum + '。');
        var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
        if (A && typeof A.cue === 'function') A.cue('activate');
        return true;
    };

    CartController.prototype.onAddFromButton = function(event) {
        event.stopPropagation();
        if (!this._state.canEdit()) {
            this._intent.toast('商城正在处理写入，请稍后再编辑购物车。');
            var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
            if (A && typeof A.cue === 'function') A.cue('illegal');
            return;
        }
        var idx = Number(event.target.getAttribute('data-idx'));
        var item = this._state.findCatalogItem(idx);
        if (!item) return;
        if (this._state.isLocked(item)) {
            this._intent.toast('等级不足，无法购买！');
            var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
            if (A && typeof A.cue === 'function') A.cue('illegal');
            return;
        }
        this.addCatalogIntent(idx, 1);
    };

    CartController.prototype._commitCart = function(next) {
        this._intent.replaceCart(next);
        this.render();
        this._intent.markDirty();
        if (this._settlement && this._settlement.isActive()) this.requestPreview();
    };

    CartController.prototype.adjust = function(idx, delta, removeAll) {
        if (!this._state.canEdit()) return false;
        var item = this._state.findCatalogItem(idx);
        var maximum = quantityLimit(item, item && this._state.isStackable(item));
        var result = adjustItem(this._cart(), idx, delta, removeAll, maximum);
        if (result.changed) this._commitCart(result.cart);
        if (result.error === 'limit_reached') this._intent.toast('已达到当前可购买上限 ' + maximum + '。');
        else if (result.error === 'sold_out') this._intent.toast('该商品已达持有上限，已从购物车移除。');
        return result.changed;
    };

    CartController.prototype.setQuantity = function(idx, value) {
        if (!this._state.canEdit()) return false;
        var item = this._state.findCatalogItem(idx);
        var maximum = quantityLimit(item, item && this._state.isStackable(item));
        var result = setItemQuantity(this._cart(), idx, value, maximum);
        if (result.changed) this._commitCart(result.cart);
        return result.changed;
    };

    CartController.prototype.render = function() {
        if (this._composition) {
            this._composition.cartGridView.renderer.render(this._cart());
            this._composition.cartGridView.chrome.setMeta(this._cart().length + ' 种 / ' + this.quantity() + ' 件');
            this._composition.dropTarget.classList.toggle('has-items', this._cart().length > 0);
            this._composition.cartTotal.textContent = total(this._cart(), this._state.findCatalogItem);
        }
        if (this._settlement) this._settlement.render();
        if (this._intent.refreshControls) this._intent.refreshControls();
    };

    CartController.prototype.renderRow = function(cartItem) {
        var item = this._state.findCatalogItem(cartItem.idx);
        var row = document.createElement('article');
        row.className = 'kshop-cart-row';
        row.setAttribute('data-idx', cartItem.idx);
        if (!item) {
            row.classList.add('kshop-cart-row-invalid');
            row.textContent = '目录已变化 · 商品 #' + cartItem.idx;
            return row;
        }
        var subtotal = Number(item.price) * cartItem.qty;
        row.innerHTML = '<span class="kshop-cart-thumb">' + this._intent.iconHtml(item.icon, 'kshop-row-icon') + '</span>'
            + '<span class="kshop-cart-copy"><b class="kshop-cart-name">' + this._intent.escapeHtml(item.displayname) + '</b><small>K ' + item.price + ' / 件</small></span>'
            + '<span class="kshop-cart-qty"><b>×' + cartItem.qty + '</b></span>'
            + '<span class="kshop-cart-sub">' + subtotal + '</span>'
            + '<button class="kshop-cart-remove-btn" type="button" data-audio-cue="back">×</button>';
        return row;
    };

    CartController.prototype.bindRow = function(row) {
        var self = this;
        var item = this._state.findCatalogItem(Number(row.getAttribute('data-idx')));
        if (item) Workbench.EntityTile.bindActivation(row, {
            itemName:item.displayname,
            label:'查看商品详情；移除操作使用行内按钮',
            inspectable:true,
            actionable:true,
            onActivate:function() {
                if (self._intent.inspect) self._intent.inspect(Number(row.getAttribute('data-idx')), row);
            }
        });
        var remove = row.querySelector('.kshop-cart-remove-btn');
        if (remove) {
            remove.setAttribute('aria-label', '从购物车移除'
                + (item ? '“' + item.displayname + '”' : '该商品'));
            remove.addEventListener('click', function(event) {
                event.stopPropagation();
                self.adjust(Number(row.getAttribute('data-idx')), 0, true);
            });
        }
    };

    CartController.prototype.openSettlement = function() {
        if (!this._settlement || !this._cart().length || !this._state.canStartWrite()) return;
        var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
        if (A && typeof A.cue === 'function') A.cue('open');
        this._settlement.show();
        this.requestPreview();
    };

    CartController.prototype.closeSettlement = function() {
        this._previewRevision++;
        this._previewBusy = false;
        this._previewQueued = false;
        this._preview = null;
        if (this._settlement) this._settlement.hide();
    };

    CartController.prototype.requestPreview = function() {
        if (!this._settlement || !this._settlement.isActive()) return;
        if (!this._cart().length) { this.closeSettlement(); return; }
        if (this._previewBusy) { this._previewQueued = true; return; }
        var self = this;
        this._previewBusy = true;
        this._previewQueued = false;
        this._preview = null;
        var revision = ++this._previewRevision;
        this._settlement.setLoading();
        this._intent.requestShop('checkoutPreview', {v:1, cart:this.buildPayload()}, function(resp) {
            if (revision !== self._previewRevision || !self._settlement.isActive()) return;
            self._previewBusy = false;
            if (validPreview(resp)) {
                self._preview = resp;
                self._settlement.setPreview(resp);
            } else {
                self._settlement.setError(self._intent.errorMessage('checkout', resp && resp.error));
            }
            if (self._previewQueued) self.requestPreview();
        });
    };

    CartController.prototype.checkout = function() {
        if (!this._cart().length || !this._state.canStartWrite() || !this._preview || !this._preview.canCommit) return;
        var token = this._preview.checkoutToken;
        this._preview = null;
        this._settlement.setLoading();
        this._intent.commitCheckout(token);
    };

    CartController.prototype.debugState = function() {
        return {
            settling:!!(this._settlement && this._settlement.isActive()),
            previewBusy:this._previewBusy,
            hasCheckoutPreview:!!this._preview,
            settlement:this._settlement ? this._settlement.debugState() : null
        };
    };

    CartController.prototype.destroy = function() {
        this.closeSettlement();
        if (this._settlement && typeof this._settlement.destroy === 'function') {
            this._settlement.destroy();
            this._settlement = null;
        }
    };

    return {
        CartController:CartController,
        copyCart:copyCart,
        quantityLimit:quantityLimit,
        sanitizeCart:sanitizeCart,
        buildPayload:buildPayload,
        quantity:quantity,
        total:total,
        addItem:addItem,
        adjustItem:adjustItem,
        setItemQuantity:setItemQuantity,
        validPreview:validPreview
    };
});
