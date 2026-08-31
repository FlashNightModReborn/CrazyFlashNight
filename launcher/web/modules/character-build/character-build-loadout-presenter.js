/** Authoritative loadout tooltip presentation and character-build slot-grid hooks. */
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
        var drugSlot = /^drug([1-8])$/.test(String(id || ''))
            ? Number(String(id).substring(4)) - 1 : -1;
        return kind === 'drug' && drugSlot >= 0
            ? {kind:'drug', drugSlot:drugSlot} : null;
    }

    function install(prototype) {
        if (!prototype) throw new Error('CharacterBuildLoadoutPresenter.install requires a view method target');
        prototype._bindLoadoutTooltip = function(
                slot, key, slotLabel, projection, target, extraSuppression) {
            if (!target || !this._loadoutTooltipScope
                    || typeof this._loadoutTooltipScope.bindAsync !== 'function') return false;
            var self = this;
            slot.setAttribute('data-loadout-tooltip',
                this._fetchLoadoutTooltip ? 'authoritative' : 'projection-fallback');
            return this._loadoutTooltipScope.bindAsync(slot, {
                key:'loadout:' + this._loadoutTooltipEpoch + ':' + key,
                item:projection,
                cache:this._loadoutTooltipCache,
                // 区域定侧：装备槽注释恒放左侧——左侧纸娃娃是被动预览区，右侧是正在
                // 操作的候选/调制面板；左侧放不下时由共享定位器回退打分，且同一次
                // 悬停内侧向锁定，不再随鼠标位置翻面。
                placement:'left',
                // 锚点覆盖到整个槽位 grid：注释贴槽位列的左缘放置，同组各槽位置一致，
                // 且永不盖住相邻槽位（含空槽）——鼠标在槽位间移动不会落进浮层被截获。
                anchor:function(event, node) { return node.parentNode; },
                isSuppressed:function() {
                    return self._candidateDragActive || self._interactionState !== 'idle'
                        || (typeof extraSuppression === 'function'
                            && extraSuppression());
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
        };
        return prototype;
    }

    /* 槽位网格钩子：角标（facet 计数）、调制标记与已装备注释保持 cb 私有，
     * 由共享 loadout-picker slot-grid 在渲染时回调。 */
    function slotGridHooks() {
        return {
            releaseGrid:function(view, grid) {
                if (view._loadoutTooltipScope && view._loadoutTooltipScope.releaseTree) {
                    view._loadoutTooltipScope.releaseTree(grid);
                }
            },
            projectSlot:function(view, slot, item, definition) {
                slot.setAttribute('data-tunable', item && item.tunable === true ? 'true' : 'false');
                if (item && item.tuningReason) {
                    slot.setAttribute('data-tuning-reason', text(item.tuningReason));
                }
                var meta = definition && definition.drugMeta;
                if (meta) {
                    slot.setAttribute('data-drug-bank', String(meta.bank));
                    slot.setAttribute('data-drug-lane', String(meta.lane));
                    slot.setAttribute('data-drug-active', meta.active ? 'true' : 'false');
                    slot.setAttribute('data-drug-ready', meta.ready ? 'true' : 'false');
                    slot.setAttribute('data-drug-state', meta.ready ? 'ready'
                        : Number(meta.totalSteps) > 0 ? 'cooling' : 'unavailable');
                    slot.setAttribute('data-cooldown-progress',
                        String(meta.progressPercent));
                    slot.setAttribute('data-cooldown-remaining-ms',
                        String(meta.remainingMs));
                    if (slot.style && typeof slot.style.setProperty === 'function') {
                        slot.style.setProperty('--drug-cooldown-progress',
                            String(meta.progressPercent) + '%');
                    }
                }
            },
            bindSlotTooltip:function(view, slot, key, slotLabel, projection, kind, id) {
                view._bindLoadoutTooltip(
                    slot, key, slotLabel, projection, loadoutTarget(kind, id));
            },
            decorateSlot:function(view, slot, kind, id) {
                FacetCountsModule.decorateSlot(slot, view._facetCounts, kind, id);
            }
        };
    }

    return {
        install:install,
        slotGridHooks:slotGridHooks,
        loadoutBasicTooltipHtml:loadoutBasicTooltipHtml,
        loadoutRichTooltipHtml:loadoutRichTooltipHtml,
        loadoutFailureTooltipHtml:loadoutFailureTooltipHtml,
        loadoutTarget:loadoutTarget
    };
});
