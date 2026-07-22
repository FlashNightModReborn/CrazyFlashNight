/**
 * KShop catalog presentation.
 *
 * Owns taxonomy navigation, filtering and catalog card binding. Authority stays
 * in kshop.js and is exposed here through read-only state and explicit intents.
 */
(function(root, factory) {
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.KShopCatalogPresenter = api;
})(typeof window !== 'undefined' ? window : this, function() {
    'use strict';

    function isStackable(item) {
        return !!item && (item.majorType === '消耗品' || item.majorType === '收集品');
    }

    function isLocked(item, playerLevel, reverseLevel) {
        return !!item && Number(item.level) > Number(playerLevel || 0) + Number(reverseLevel || 0);
    }

    function isAtLimit(item) {
        return !!item && isFinite(Number(item.maxQuantity)) && Number(item.maxQuantity) <= 0;
    }

    function findCatalogItem(catalog, idx) {
        catalog = catalog || [];
        for (var i = 0; i < catalog.length; i++) {
            if (Number(catalog[i].idx) === Number(idx)) return catalog[i];
        }
        return null;
    }

    function matchesCategory(item, path, itemFilter) {
        path = path || [];
        if (!path.length) return true;
        if (path.length === 1) {
            return path[0] === 'set' ? itemFilter.setPath(item).length > 0 : true;
        }
        if (path[0] === 'category') {
            return itemFilter.matchesPath(item, path.slice(1), function(entry) {
                return itemFilter.catalogPath(entry);
            });
        }
        if (path[0] === 'set') return itemFilter.matchesPath(item, path.slice(1), itemFilter.setPath);
        if (path[0] === 'curated') return String(item && item.type || '未分组') === String(path[1]);
        return false;
    }

    function buildCategoryTree(catalog, itemFilter) {
        catalog = catalog || [];
        var automaticTree = itemFilter.build(catalog, function(item) {
            return itemFilter.catalogPath(item);
        });
        var curatedTree = itemFilter.build(catalog, function(item) {
            var group = String(item && item.type || '未分组');
            return [{id:group, label:group}];
        });
        var setTree = itemFilter.buildSetTree(catalog);
        var branches = [{id:'category', label:'类别', tree:automaticTree}];
        if (setTree.children.length) branches.push({id:'set', label:'套装', tree:setTree});
        branches.push({id:'curated', label:'专柜', tree:curatedTree});
        return itemFilter.branchTree(branches, catalog.length);
    }

    function CatalogPresenter(options) {
        options = options || {};
        this._state = options.state || {};
        this._intent = options.intent || {};
        this._path = [];
        this._tree = null;
        this._navigator = null;
        this._composition = null;
        this._iconsLoaded = false;
    }

    CatalogPresenter.prototype._catalog = function() {
        return this._state.getCatalog ? this._state.getCatalog() || [] : [];
    };

    CatalogPresenter.prototype.find = function(idx) {
        return findCatalogItem(this._catalog(), idx);
    };

    CatalogPresenter.prototype.isLocked = function(item) {
        return isLocked(item,
            this._state.getPlayerLevel ? this._state.getPlayerLevel() : 0,
            this._state.getReverseLevel ? this._state.getReverseLevel() : 0);
    };

    CatalogPresenter.prototype.createView = function(densityController) {
        var self = this;
        var composition = KShopViews.createCatalog({
            renderItem: function(item) { return self.renderCard(item); },
            bindItem: function(card) { self.bindCard(card); },
            render: function() { self.render(); },
            exportOffer: function(item) {
                if (!item || self.isLocked(item) || item.type === '非卖品' || isAtLimit(item)) return null;
                return {
                    subjectKind: 'catalogEntry',
                    sourceRef: {catalogIdx:item.idx},
                    offeredOperations: ['shop.addCartIntent']
                };
            }
        });
        this._composition = composition;
        this._navigator = new ItemFilter.FilterNavigator({
            className:'kshop-category-navigator item-filter-navigator',
            ariaLabel:'商城商品分类',
            presentation:'drilldown',
            visualStyle:'catalog',
            breadcrumbHost:composition.chrome.breadcrumbHost,
            onChange:function(path) {
                self._path = path;
                if (self._intent.clearSelection) self._intent.clearSelection();
                self.render({preserveScroll:false});
                self._decorateButtons();
            }
        });
        while (composition.categoryBar.firstChild) {
            composition.categoryBar.removeChild(composition.categoryBar.firstChild);
        }
        composition.categoryBar.appendChild(this._navigator.root);
        if (densityController) densityController.register(composition.renderer);
        return composition.view;
    };

    CatalogPresenter.prototype.getComposition = function() { return this._composition; };
    CatalogPresenter.prototype.getView = function() { return this._composition && this._composition.view; };
    CatalogPresenter.prototype.getGrid = function() { return this._composition && this._composition.grid; };
    CatalogPresenter.prototype.getRenderer = function() { return this._composition && this._composition.renderer; };
    CatalogPresenter.prototype.getLoading = function() { return this._composition && this._composition.loading; };

    CatalogPresenter.prototype.reset = function() {
        this._path = [];
        if (this._intent.clearSelection) this._intent.clearSelection();
    };

    CatalogPresenter.prototype.rebuildCategories = function() {
        this._tree = buildCategoryTree(this._catalog(), ItemFilter);
        this._path = ItemFilter.validPath(this._tree, this._path);
        if (this._navigator) this._navigator.setModel(this._tree, this._path);
        this._decorateButtons();
    };

    CatalogPresenter.prototype._decorateButtons = function() {
        if (!this._navigator) return;
        var buttons = this._navigator.root.querySelectorAll('[data-filter-path]');
        for (var i = 0; i < buttons.length; i++) {
            var label = buttons[i].querySelector('span');
            buttons[i].setAttribute('data-cat', label ? label.textContent.replace(/^全部/, '') || '全部' : '全部');
            buttons[i].setAttribute('data-audio-cue', 'select');
        }
    };

    CatalogPresenter.prototype.render = function(renderOptions) {
        if (!this._composition) return;
        if (typeof PanelTooltip !== 'undefined' && PanelTooltip.hide) PanelTooltip.hide();
        var catalog = this._catalog();
        var visible = [];
        for (var i = 0; i < catalog.length; i++) {
            if (matchesCategory(catalog[i], this._path, ItemFilter)) visible.push(catalog[i]);
        }
        this._composition.renderer.render(visible, renderOptions);
        this.setSelected(this._state.getSelectedIdx ? this._state.getSelectedIdx() : null);
        this._composition.chrome.setMeta(visible.length + ' 件');
        if (!this._iconsLoaded && typeof Icons !== 'undefined') {
            var self = this;
            Icons.load(function() {
                self._iconsLoaded = true;
                self.render({forceItemRender:true});
                if (self._intent.iconsReady) self._intent.iconsReady();
            });
        }
        if (this._intent.renderComplete) this._intent.renderComplete();
    };

    CatalogPresenter.prototype.setSelected = function(idx) {
        if (this._composition) this._composition.renderer.setSelectedKey(idx);
    };

    CatalogPresenter.prototype.renderCard = function(item) {
        var locked = this.isLocked(item);
        var nosale = item.type === '非卖品';
        var atLimit = isAtLimit(item);
        var stackable = isStackable(item);
        var actionHtml = '';
        if (!nosale && !locked && !atLimit) {
            actionHtml = '<button class="kshop-add-btn' + (stackable ? '' : ' kshop-add-single')
                + '" data-idx="' + item.idx + '" data-audio-cue="select" aria-label="加入购物车">'
                + (stackable ? '+' : '加入') + '</button>';
        }
        return Workbench.ItemCard.renderCatalog({
            skin:'kshop', item:item, id:item.idx,
            iconHtml:this._intent.iconHtml ? this._intent.iconHtml(item.icon) : '',
            name:item.displayname, meta:item.subType || item.majorType || item.type,
            price:item.price, priceLabel:'K', locked:locked || atLimit,
            lockReason:atLimit ? '已达持有上限' : ('Lv.' + item.level + ' 解锁'), nosale:nosale,
            ariaLabel:item.displayname + '，K ' + item.price, extraHtml:actionHtml
        });
    };

    CatalogPresenter.prototype.bindCard = function(card) {
        var self = this;
        var idx = Number(card.getAttribute('data-idx'));
        var item = this.find(idx);
        if (item && this._intent.bindTooltip) this._intent.bindTooltip(card, item);
        Workbench.EntityTile.bindActivation(card, {
            itemName:item ? item.displayname : '',
            label:card.getAttribute('aria-label') || '',
            selected:this._state.getSelectedIdx && this._state.getSelectedIdx() === idx,
            disabled:!item || this.isLocked(item) || item.type === '非卖品' || isAtLimit(item),
            onActivate:function(event) { self._activateCard(event); }
        });
        card.addEventListener('dblclick', function(event) { self._doubleClickCard(event); });
        var addButton = card.querySelector('.kshop-add-btn');
        if (addButton) {
            Workbench.EntityTile.labelAction(addButton, item && item.displayname, '加入购物车');
            addButton.addEventListener('click', function(event) {
                if (self._intent.addFromButton) self._intent.addFromButton(event);
            });
        }
    };

    CatalogPresenter.prototype._activateCard = function(event) {
        if (event.target.closest && event.target.closest('button')) return;
        if (this._intent.consumeDragClick && this._intent.consumeDragClick()) return;
        var item = this.find(Number(event.currentTarget.getAttribute('data-idx')));
        if (!item || this.isLocked(item) || item.type === '非卖品' || isAtLimit(item)) return;
        if (this._intent.select) this._intent.select(item, event.currentTarget);
        if (this._intent.playCue) this._intent.playCue('select');
    };

    CatalogPresenter.prototype._doubleClickCard = function(event) {
        if (!this._state.canEdit || !this._state.canEdit()) return;
        var item = this.find(Number(event.currentTarget.getAttribute('data-idx')));
        if (item && this._intent.dispatchAdd) this._intent.dispatchAdd(item, 'double_click');
    };

    return {
        CatalogPresenter:CatalogPresenter,
        isStackable:isStackable,
        isLocked:isLocked,
        findCatalogItem:findCatalogItem,
        matchesCategory:matchesCategory,
        buildCategoryTree:buildCategoryTree
    };
});
