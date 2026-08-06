/** Equipped-slot rendering and authoritative loadout tooltip presentation. */
(function(root, factory) {
    'use strict';
    var facets = typeof module !== 'undefined' && module.exports
        ? require('./character-build-facet-counts.js')
        : root && root.CharacterBuildFacetCounts;
    var api = factory(facets);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildLoadoutPresenter = api;
        root.CharacterBuildLoadoutPresenter = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(FacetCountsModule) {
    'use strict';
    if (!FacetCountsModule || typeof FacetCountsModule.decorateSlot !== 'function') {
        throw new Error('CharacterBuildLoadoutPresenter requires CharacterBuildFacetCounts');
    }

    function text(value, fallback) {
        return String(value == null || value === '' ? fallback || '' : value);
    }
    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
    function finiteNumber(value) {
        value = Number(value);
        return isFinite(value) ? value : null;
    }
    function loadoutBasicTooltipHtml(item, slotLabel) {
        item = item || {};
        var rows = [];
        var type = item.majorType || item.use || item.itemKind || '物品';
        rows.push(['槽位', slotLabel || item.use || '已装备']);
        rows.push(['类型', type]);
        var level = finiteNumber(item.balanceSummary && item.balanceSummary.level);
        if (level !== null) rows.push(['需求等级', level]);
        var enhancement = finiteNumber(item.enhancementLevel);
        var maxEnhancement = finiteNumber(item.maxEnhancementLevel);
        if (enhancement !== null && enhancement > 0) {
            rows.push(['强化', '+' + enhancement
                + (maxEnhancement !== null && maxEnhancement > 0
                    ? ' / +' + maxEnhancement : '')]);
        }
        if (item.rarity) rows.push(['稀有度', item.rarity]);
        if (item.setName) rows.push(['套装', item.setName
            + (finiteNumber(item.setOrder) > 0 ? ' · 第 ' + Number(item.setOrder) + ' 件' : '')]);
        var quantity = finiteNumber(item.quantity);
        if (quantity !== null && quantity > 1) rows.push(['数量', quantity]);
        if (item.tierSlotAvailable === true) {
            rows.push(['进阶', item.tierSlotUsed === true ? '已安装' : '可安装']);
        }
        var modCapacity = finiteNumber(item.modSlotCapacity);
        var modUsed = finiteNumber(item.modSlotUsed);
        if (modCapacity !== null && modCapacity > 0) {
            rows.push(['插件', Math.max(0, modUsed || 0) + ' / ' + modCapacity]);
        }
        var weight = finiteNumber(item.balanceSummary && item.balanceSummary.weightLayers);
        if (weight !== null) rows.push(['重量层', weight]);
        var html = '<div class="kshop-tt-header"><b>'
            + escapeHtml(item.displayName || '未知物品') + '</b></div>'
            + '<div class="kshop-tt-divider"></div>';
        for (var i = 0; i < rows.length; i++) {
            html += '<span class="kshop-tt-dim">' + escapeHtml(rows[i][0])
                + '</span> ' + escapeHtml(rows[i][1]) + '<br>';
        }
        var mods = Array.isArray(item.modSlots) ? item.modSlots : [];
        for (i = 0; i < mods.length; i++) {
            var mod = mods[i] || {};
            html += '<span class="kshop-tt-dim">插件 ' + (i + 1) + '</span> '
                + escapeHtml(mod.displayName || '未命名插件')
                + (mod.gradeLabel ? ' · ' + escapeHtml(mod.gradeLabel) : '')
                + (mod.roleLabel ? ' · ' + escapeHtml(mod.roleLabel) : '') + '<br>';
        }
        return '<div class="character-build-loadout-tt-context">' + html
            + '<div class="kshop-tt-loading">正在读取完整说明…</div></div>';
    }
    function loadoutRichTooltipHtml(item, slotLabel, tooltip, response) {
        var data = response && response.payload;
        if (!data || !tooltip || typeof tooltip.buildItemRichHtml !== 'function') {
            return loadoutBasicTooltipHtml(item, slotLabel);
        }
        var iconKey = data.iconName || item && item.icon || '';
        var meta = '<div class="character-build-loadout-tt-slot"><span class="kshop-tt-dim">当前槽位</span> '
            + escapeHtml(slotLabel || '已装备') + '</div>';
        return tooltip.buildItemRichHtml({
            iconHtml:tooltip.dynamicIconHtml ? tooltip.dynamicIconHtml(iconKey) : '',
            iconUrl:tooltip.staticIconUrl ? tooltip.staticIconUrl(iconKey) : '',
            introHTML:data.introHTML || '',
            descHTML:data.descHTML || '',
            metaHTML:meta,
            rootClass:'kshop-tt-rich-context character-build-loadout-tt-context',
            layoutType:tooltip.inferLayoutType
                ? tooltip.inferLayoutType(data.itemType || item && (
                    item.majorType || item.use)) : undefined
        });
    }
    function loadoutFailureTooltipHtml(item, slotLabel) {
        return loadoutBasicTooltipHtml(item, slotLabel).replace(
            '正在读取完整说明…',
            '完整说明暂时读取失败；移开后重新悬停即可重试。');
    }
    function loadoutTarget(kind, id) {
        if (kind === 'armor' || kind === 'weapon') {
            return {kind:'equipment', slotKey:String(id || '')};
        }
        var drugSlot = /^drug([1-4])$/.test(String(id || ''))
            ? Number(String(id).substring(4)) - 1 : -1;
        return kind === 'drug' && drugSlot >= 0
            ? {kind:'drug', drugSlot:drugSlot} : null;
    }
    function itemAt(collection, id) {
        return collection && Object.prototype.hasOwnProperty.call(collection, id)
            ? collection[id] : null;
    }

    function install(prototype) {
        if (!prototype) throw new Error('CharacterBuildLoadoutPresenter.install requires a view method target');
        prototype._renderSlotGroup = function(grid, definitions, collection, kind, roving) {
            var activeElement = this._document.activeElement;
            var restoreFocus = !!(activeElement && grid.contains(activeElement));
            if (this._loadoutTooltipScope && this._loadoutTooltipScope.releaseTree) {
                this._loadoutTooltipScope.releaseTree(grid);
            }
            var fragment = this._document.createDocumentFragment();
            for (var i = 0; i < definitions.length; i++) {
                var definition = definitions[i];
                var item = itemAt(collection, definition.id);
                var key = kind + ':' + definition.id;
                var slot = this._document.createElement('button');
                slot.type = 'button';
                slot.className = 'character-build-slot';
                slot.setAttribute('role', 'gridcell');
                slot.setAttribute('data-roving-key', key);
                slot.setAttribute('data-slot-id', definition.id);
                slot.setAttribute('data-slot-protocol-key', definition.id);
                slot.setAttribute('data-slot-kind', kind);
                slot.setAttribute('data-empty', item ? 'false' : 'true');
                slot.setAttribute('data-tunable', item && item.tunable === true ? 'true' : 'false');
                if (item && item.tuningReason) {
                    slot.setAttribute('data-tuning-reason', text(item.tuningReason));
                }
                slot.setAttribute('data-focus-label', definition.label);
                slot.setAttribute('data-focus-name', item ? item.name : '空槽');
                slot.setAttribute('aria-selected', key === this._selectedSlotKey ? 'true' : 'false');
                if (item && item.blocked) slot.setAttribute('data-blocked', 'true');
                var meta = item ? item.meta || item.type || '已装备' : '点击查看可用候选';
                slot.setAttribute('data-focus-meta', meta);
                var card = this._renderOwnedSlot(definition.label, {
                    occupied:!!item,
                    physicalSlot:i,
                    item:item && item.presentation || {}
                }, {iconHtml:this._iconHtml, allowDiscard:false, tagName:'span'});
                card.classList.add('character-build-slot-card');
                slot.setAttribute('aria-label', card.getAttribute('aria-label'));
                card.setAttribute('aria-hidden', 'true');
                slot.appendChild(card);
                if (item) this._bindLoadoutTooltip(
                    slot, key, definition.label, item.presentation || {},
                    loadoutTarget(kind, definition.id));
                var label = this._document.createElement('span');
                label.className = 'character-build-slot-label';
                label.textContent = definition.label;
                slot.appendChild(label);
                FacetCountsModule.decorateSlot(
                    slot, this._facetCounts, kind, definition.id);
                fragment.appendChild(slot);
            }
            grid.innerHTML = '';
            grid.appendChild(fragment);
            roving.refresh({
                preferredKey:this._activeSlotKey.indexOf(kind + ':') === 0 ? this._activeSlotKey : '',
                focus:restoreFocus
            });
            return true;
        };

        prototype._bindLoadoutTooltip = function(
                slot, key, slotLabel, projection, target) {
            if (!target || !this._loadoutTooltipScope
                    || typeof this._loadoutTooltipScope.bindAsync !== 'function') return false;
            var self = this;
            slot.setAttribute('data-loadout-tooltip',
                this._fetchLoadoutTooltip ? 'authoritative' : 'projection-fallback');
            this._loadoutTooltipScope.bindAsync(slot, {
                key:'loadout:' + this._loadoutTooltipEpoch + ':' + key,
                item:projection,
                cache:this._loadoutTooltipCache,
                isSuppressed:function() {
                    return self._candidateDragActive || self._interactionState !== 'idle';
                },
                renderBasic:function(value) {
                    return loadoutBasicTooltipHtml(value, slotLabel);
                },
                renderRich:function(value, response) {
                    return loadoutRichTooltipHtml(value, slotLabel, self._tooltip, response);
                },
                renderFailure:function(value) {
                    return loadoutFailureTooltipHtml(value, slotLabel);
                },
                fetch:this._fetchLoadoutTooltip ? function(_, callback) {
                    return self._fetchLoadoutTooltip(target, callback);
                } : null
            });
            return true;
        };
        return prototype;
    }

    return {
        install:install,
        loadoutBasicTooltipHtml:loadoutBasicTooltipHtml,
        loadoutRichTooltipHtml:loadoutRichTooltipHtml,
        loadoutFailureTooltipHtml:loadoutFailureTooltipHtml,
        loadoutTarget:loadoutTarget
    };
});
