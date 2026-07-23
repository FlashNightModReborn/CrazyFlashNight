/** KShop tooltip presenter. No transport or item authority is owned here. */
(function(root, factory) {
    var workbenchApi = root && (root.Workbench || root.WorkbenchPrimitives);
    if (!workbenchApi && typeof module !== 'undefined' && module.exports) {
        workbenchApi = require('./workbench-primitives.js');
    }
    var api = factory(workbenchApi);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.KShopTooltipPresenter = api;
})(typeof window !== 'undefined' ? window : globalThis, function(WorkbenchApi) {
    'use strict';

    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }

    function ownedTooltipKey(containerId, slot) {
        return String(containerId) + ':' + Number(slot.physicalSlot) + ':' + String(slot.slotLease || '');
    }

    function catalogBasicFacts(item, locked) {
        return {
            name:String(item && item.displayname || ''),
            type:String(item && item.majorType || ''),
            subtype:String(item && item.subType || ''),
            level:String(item && item.level || 0),
            price:String(item && item.price || 0),
            locked:!!locked
        };
    }

    function ownedBasicFacts(item) {
        item = item || {};
        return {
            name:String(item.displayName || item.name || '未知物品'),
            type:String(item.majorType || item.use || item.itemKind || '物品'),
            quantity:Math.max(0, Number(item.quantity) || 0),
            enhancementLevel:Math.max(0, Number(item.enhancementLevel) || 0)
        };
    }

    function balanceMetaHtml(item) {
        var itemCard = WorkbenchApi && WorkbenchApi.ItemCard;
        return itemCard && itemCard.balanceTooltipMetaHtml
            ? itemCard.balanceTooltipMetaHtml(item) : '';
    }

    function TooltipPresenter(options) {
        options = options || {};
        this._state = options.state || {};
        this._intent = options.intent || {};
        this._catalogCache = {};
        this._ownedCache = {};
    }

    TooltipPresenter.prototype.reset = function() {
        this._catalogCache = {};
        this._ownedCache = {};
    };

    TooltipPresenter.prototype.hide = function() {
        if (typeof PanelTooltip !== 'undefined' && PanelTooltip.hide) PanelTooltip.hide();
    };

    TooltipPresenter.prototype._bindAsyncHover = function(node, options) {
        if (this._intent.bindAsyncHover) return this._intent.bindAsyncHover(node, options);
        return PanelTooltip.bindAsyncHover(node, options);
    };

    TooltipPresenter.prototype._iconHtml = function(iconKey) {
        var html = PanelTooltip.dynamicIconHtml(iconKey);
        return html || '<div class="kshop-tt-icon-placeholder"></div>';
    };

    TooltipPresenter.prototype._catalogBasicHtml = function(item) {
        var facts = catalogBasicFacts(item, this._state.isLocked && this._state.isLocked(item));
        var intro = '<div class="kshop-tt-header"><b>' + escapeHtml(facts.name) + '</b></div>'
            + '<span class="kshop-tt-dim">类型</span> ' + escapeHtml(facts.type) + ' / ' + escapeHtml(facts.subtype) + '<br>'
            + '<span class="kshop-tt-dim">等级</span> ' + escapeHtml(facts.level)
            + (facts.locked ? ' <span class="kshop-tt-locked">⚿ 锁定</span>' : '') + '<br>'
            + '<span class="kshop-tt-price">K ' + escapeHtml(facts.price) + '</span>';
        return PanelTooltip.buildItemRichHtml({
            iconHtml:this._iconHtml(item.icon), introWebHTML:intro, descHTML:'',
            metaHTML:balanceMetaHtml(item),
            rootClass:'kshop-tt-rich-context',
            layoutType:PanelTooltip.inferLayoutType(item.majorType)
        });
    };

    TooltipPresenter.prototype._catalogRichHtml = function(item, data) {
        var locked = this._state.isLocked && this._state.isLocked(item);
        return PanelTooltip.buildItemRichHtml({
            iconHtml:this._iconHtml(item.icon),
            iconUrl:PanelTooltip.staticIconUrl(item.icon),
            introHTML:data.introHTML,
            descHTML:data.descHTML,
            metaHTML:balanceMetaHtml(item),
            rootClass:'kshop-tt-rich-context',
            suffix:locked ? '<div class="flash-tt-lock-banner kshop-tt-lock-banner">⚿ 锁定 — 需要 Lv.' + item.level + '</div>' : '',
            layoutType:PanelTooltip.inferLayoutType(item.majorType)
        });
    };

    TooltipPresenter.prototype._ownedBasicHtml = function(item) {
        var facts = ownedBasicFacts(item);
        var iconKey = item.icon || item.name;
        var intro = '<div class="kshop-tt-header"><b>' + escapeHtml(facts.name) + '</b></div>'
            + '<span class="kshop-tt-dim">类型</span> ' + escapeHtml(facts.type) + '<br>'
            + (facts.quantity > 1 ? '<span class="kshop-tt-dim">数量</span> ' + facts.quantity + '<br>' : '')
            + (facts.enhancementLevel > 0 ? '<span class="kshop-tt-dim">强化</span> +' + facts.enhancementLevel + '<br>' : '');
        return PanelTooltip.buildItemRichHtml({
            iconHtml:this._iconHtml(iconKey), introWebHTML:intro, descHTML:'',
            metaHTML:balanceMetaHtml(item),
            rootClass:'kshop-tt-rich-context inventory-owned-tt-context',
            layoutType:PanelTooltip.inferLayoutType(item.majorType || item.use)
        });
    };

    TooltipPresenter.prototype._ownedRichHtml = function(item, data) {
        var iconKey = data.iconName || item.icon || item.name;
        return PanelTooltip.buildItemRichHtml({
            iconHtml:this._iconHtml(iconKey), iconUrl:PanelTooltip.staticIconUrl(iconKey),
            introHTML:data.introHTML || '', descHTML:data.descHTML || '',
            metaHTML:balanceMetaHtml(item),
            rootClass:'kshop-tt-rich-context inventory-owned-tt-context',
            layoutType:PanelTooltip.inferLayoutType(data.itemType || item.majorType || item.use)
        });
    };

    TooltipPresenter.prototype.bindCatalog = function(card, item) {
        var self = this;
        this._bindAsyncHover(card, {
            cache:this._catalogCache,
            key:item.idx,
            item:item,
            isSuppressed:function() { return !!(self._state.isDragSuppressed && self._state.isDragSuppressed()); },
            renderBasic:function(entry) { return self._catalogBasicHtml(entry); },
            renderRich:function(entry, data) { return self._catalogRichHtml(entry, data); },
            fetch:function(entry, callback) {
                self._intent.requestShop('tooltip', {idx:entry.idx}, function(resp) {
                    if (self._state.isOpen && !self._state.isOpen()) return;
                    if (typeof document !== 'undefined' && !document.documentElement.contains(card)) return;
                    callback(resp);
                });
            }
        });
    };

    TooltipPresenter.prototype.bindOwned = function(node, containerId, slot) {
        var self = this;
        var item = slot.item || {};
        this._bindAsyncHover(node, {
            cache:this._ownedCache,
            key:ownedTooltipKey(containerId, slot),
            item:item,
            isSuppressed:function() {
                return !!((self._state.isDragSuppressed && self._state.isDragSuppressed())
                    || (self._state.isOwnedSelectionSuppressed && self._state.isOwnedSelectionSuppressed()));
            },
            renderBasic:function(entry) { return self._ownedBasicHtml(entry); },
            renderRich:function(entry, data) { return self._ownedRichHtml(entry, data); },
            fetch:function(_, callback) {
                self._intent.requestInventory('tooltip', {
                    v:1,
                    source:self._intent.ownedSlotRef(containerId, slot)
                }, function(resp) {
                    if (self._state.isOpen && !self._state.isOpen()) return;
                    if (typeof document !== 'undefined' && !document.documentElement.contains(node)) return;
                    callback(resp);
                });
            }
        });
    };

    TooltipPresenter.prototype.showItemDetail = function(idx, anchorElement) {
        var self = this;
        var item = this._state.findCatalogItem && this._state.findCatalogItem(idx);
        if (!item) return;
        var cached = this._catalogCache[idx];
        PanelTooltip.showAnchored(cached ? this._catalogRichHtml(item, cached) : this._catalogBasicHtml(item), anchorElement);
        if (!cached) {
            this._intent.requestShop('tooltip', {idx:idx}, function(resp) {
                if (self._state.isOpen && !self._state.isOpen()) return;
                if (resp && resp.success) {
                    self._catalogCache[idx] = {descHTML:resp.descHTML || '', introHTML:resp.introHTML || ''};
                }
            });
        }
    };

    return {
        TooltipPresenter:TooltipPresenter,
        ownedTooltipKey:ownedTooltipKey,
        catalogBasicFacts:catalogBasicFacts,
        ownedBasicFacts:ownedBasicFacts,
        balanceMetaHtml:balanceMetaHtml,
        escapeHtml:escapeHtml
    };
});
