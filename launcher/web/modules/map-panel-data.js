var MapPanelData = (function createMapPanelData(definition) {
    'use strict';

    if (typeof MapDefinitionData === 'undefined') throw new Error('地图定义未加载');
    var _definition = JSON.parse(JSON.stringify(definition || MapDefinitionData));
    var _pageOrder = _definition.pageOrder;
    var _pageAliases = _definition.pageAliases;
    var _sourceRefs = _definition.sourceRefs;
    var _unlockGroups = _definition.unlockGroups;
    var _pageUnlockGroups = _definition.pageUnlockGroups;
    var _handTunedLayoutIds = _definition.handTunedLayoutIds;
    var _xflSourceRects = _definition.xflSourceRects;
    var _pages = _definition.pages;
    // 矩形在 C# 编辑事务中随图块更新，运行时只消费规范化定义。


    function buildSceneVisualUnionRect(sceneVisuals, hotspotId) {
        var rect = null;
        var i;

        for (i = 0; i < sceneVisuals.length; i++) {
            var visual = sceneVisuals[i];
            if (!visual || !visual.rect || !visual.hotspotIds || visual.hotspotIds.indexOf(hotspotId) < 0) continue;

            if (!rect) {
                rect = {
                    x: visual.rect.x,
                    y: visual.rect.y,
                    w: visual.rect.w,
                    h: visual.rect.h
                };
                continue;
            }

            var minX = Math.min(rect.x, visual.rect.x);
            var minY = Math.min(rect.y, visual.rect.y);
            var maxX = Math.max(rect.x + rect.w, visual.rect.x + visual.rect.w);
            var maxY = Math.max(rect.y + rect.h, visual.rect.y + visual.rect.h);

            rect.x = +minX.toFixed(2);
            rect.y = +minY.toFixed(2);
            rect.w = +(maxX - minX).toFixed(2);
            rect.h = +(maxY - minY).toFixed(2);
        }

        return rect;
    }

    function getUnlockGroupMeta(groupId) {
        return groupId ? (_unlockGroups[groupId] || null) : null;
    }

    function getPageUnlockMapping(pageId) {
        return _pageUnlockGroups[resolvePageId(pageId)] || {};
    }

    function getSourceRect(pageId, hotspotId) {
        var pageRects = _xflSourceRects[resolvePageId(pageId)] || {};
        return hotspotId ? (pageRects[hotspotId] || null) : null;
    }

    function isHandTunedLayout(hotspotId) {
        return !!_handTunedLayoutIds[hotspotId];
    }

    function getLayoutAuditMeta(pageId, hotspotId) {
        var sourceRect = getSourceRect(pageId, hotspotId);
        var hotspot = findHotspot(pageId, hotspotId);
        var dx = null;
        var dy = null;
        var status = 'missing';
        var note = 'missing_xfl_ref';

        if (sourceRect && hotspot) {
            dx = +(hotspot.rect.x - sourceRect.x).toFixed(2);
            dy = +(hotspot.rect.y - sourceRect.y).toFixed(2);

            if (isHandTunedLayout(hotspotId)) {
                status = 'hand_tuned';
                note = 'hand_tuned_composite_rect';
            } else if (Math.abs(dx) <= 0.5 && Math.abs(dy) <= 0.5) {
                status = 'exact';
                note = 'xfl_aligned';
            } else if (Math.abs(dx) <= 8 && Math.abs(dy) <= 8) {
                status = 'near';
                note = 'minor_delta';
            } else {
                status = 'review';
                note = 'large_delta';
            }
        }

        return {
            status: status,
            note: note,
            dx: dx,
            dy: dy,
            sourceRect: sourceRect
        };
    }

    function getHotspotUnlockGroup(pageId, hotspotId) {
        var mapping = getPageUnlockMapping(pageId);
        return hotspotId ? ((mapping.hotspots || {})[hotspotId] || '') : '';
    }

    function getFilterUnlockGroup(pageId, filterId) {
        var mapping = getPageUnlockMapping(pageId);
        return filterId ? ((mapping.filters || {})[filterId] || '') : '';
    }

    function normalizeUnlockFlags(unlocks) {
        var normalized = {};
        var groupId;
        unlocks = unlocks || {};

        for (groupId in _unlockGroups) {
            normalized[groupId] = unlocks[groupId] === true;
        }

        return normalized;
    }

    function evaluateCondition(unlocks, conditionId) {
        var groupId;
        var normalized = normalizeUnlockFlags(unlocks);

        if (!conditionId) return true;

        for (groupId in _unlockGroups) {
            if (_unlockGroups[groupId].conditionId === conditionId) {
                return !!normalized[groupId];
            }
        }

        return false;
    }

    function buildPageDisplayConditions(pageId) {
        var mapping = getPageUnlockMapping(pageId);
        var used = {};
        var groupId;
        var items = [];

        function collect(source) {
            var key;
            for (key in (source || {})) {
                groupId = source[key];
                if (groupId && !used[groupId] && _unlockGroups[groupId]) {
                    used[groupId] = true;
                    items.push({
                        id: _unlockGroups[groupId].conditionId,
                        kind: 'snapshotFlag',
                        path: 'unlocks.' + groupId,
                        label: _unlockGroups[groupId].label
                    });
                }
            }
        }

        collect(mapping.filters);
        collect(mapping.hotspots);
        return items;
    }

    function buildPageFlashHints(page) {
        var filters = page.filters || [];
        var hints = [];
        var i;

        for (i = 0; i < filters.length; i++) {
            var unlockGroup = getFilterUnlockGroup(page.id, filters[i].id);
            var meta = getUnlockGroupMeta(unlockGroup);
            if (!meta || !filters[i].buttonRect) continue;

            hints.push({
                id: 'hint.' + page.id + '.' + filters[i].id,
                kind: 'lockedFilter',
                filterId: filters[i].id,
                pageId: page.id,
                conditionId: meta.conditionId,
                whenValue: false,
                label: meta.lockedReason
            });
        }

        return hints;
    }

    function getPageFlashHints(pageId) {
        return buildPageFlashHints(getPage(pageId));
    }

    function getPageDisplayConditions(pageId) {
        return buildPageDisplayConditions(resolvePageId(pageId));
    }

    function buildHotspotStates(unlocks) {
        var normalized = normalizeUnlockFlags(unlocks);
        var states = {};
        var ids = getAllHotspotIds();
        var i;

        for (i = 0; i < ids.length; i++) {
            var hotspotId = ids[i];
            var pageId = findHotspotPageId(hotspotId);
            var unlockGroup = getHotspotUnlockGroup(pageId, hotspotId);
            var meta = getUnlockGroupMeta(unlockGroup);
            var enabled = meta ? !!normalized[unlockGroup] : true;

            states[hotspotId] = {
                enabled: enabled,
                unlockGroup: unlockGroup || '',
                lockedReason: enabled || !meta ? '' : meta.lockedReason
            };
        }

        return states;
    }

    function buildEnabledHotspotIds(unlocks) {
        var states = buildHotspotStates(unlocks);
        var ids = [];
        var hotspotId;

        for (hotspotId in states) {
            if (states[hotspotId].enabled) {
                ids.push(hotspotId);
            }
        }

        return ids;
    }

    function getPage(id) {
        return _pages[_pageAliases[id] || id] || _pages.base;
    }

    function getPageOrder() {
        return _pageOrder.slice();
    }

    // 与 map-panel.js 内部 resolveAssetUrl 行为一致: 兼容 overlay 嵌入 Flash
    // 上下文时 document.location 不在 launcher/web/ 根的情况, 把相对 url 锚到 /launcher/web/。
    function resolveAssetUrlForPrewarm(assetUrl) {
        var value = String(assetUrl || '');
        if (!value || /^(?:[a-z]+:|\/|#)/i.test(value)) return value;
        if (typeof document === 'undefined' || !document.location) return value;
        var marker = '/launcher/web/';
        var href = String(document.location.href || '');
        var idx = href.indexOf(marker);
        if (idx < 0) return value;
        try {
            return new URL(value, href.slice(0, idx + marker.length)).href;
        } catch (err) {
            return value;
        }
    }

    // 在 boot 阶段 idle window 调用, 把指定页的 sceneVisuals 资产解码进 image cache。
    // 等用户首次开图, <img src=...> 命中已解码 bitmap, 跳过磁盘 IO + decode 阻塞。
    function prewarmAssets(pageId) {
        var page = getPage(pageId);
        if (!page) return;

        var urls = [];
        if (page.backgroundUrl) urls.push(page.backgroundUrl);
        var visuals = page.sceneVisuals || [];
        for (var i = 0; i < visuals.length; i++) {
            if (visuals[i] && visuals[i].assetUrl) urls.push(visuals[i].assetUrl);
        }

        for (var j = 0; j < urls.length; j++) {
            var img = new Image();
            img.decoding = 'async';
            img.src = resolveAssetUrlForPrewarm(urls[j]);
            // decode() 把 WebP 进一步解到 GPU-ready bitmap；失败静默（网络抖动 / 资产缺失不影响主流程）
            if (typeof img.decode === 'function') {
                img.decode().catch(function() {});
            }
        }
    }

    function isLayerRelationFilter(pageId, filterId) {
        var filter = findFilter(pageId, filterId);
        return !!(filter && filter.viewMode === 'hierarchy');
    }

    function getManifest() {
        return {
            version: 2,
            id: 'cf7.map',
            schema: 'cf7.map/manifest-v2',
            sourceRefs: _sourceRefs,
            unlockGroups: _unlockGroups,
            pageOrder: _pageOrder.slice(),
            pageAliases: _pageAliases,
            pages: _pages
        };
    }

    function resolvePageId(id) {
        return _pageAliases[id] || id || _pageOrder[0];
    }

    function getAllHotspotIds() {
        var ids = [];
        var seen = {};
        for (var i = 0; i < _pageOrder.length; i++) {
            var page = getPage(_pageOrder[i]);
            var hotspots = page.hotspots || [];
            for (var j = 0; j < hotspots.length; j++) {
                if (!seen[hotspots[j].id]) {
                    seen[hotspots[j].id] = true;
                    ids.push(hotspots[j].id);
                }
            }
        }
        return ids;
    }

    function cloneRect(rect) {
        if (!rect) return null;
        return {
            x: +Number(rect.x || 0).toFixed(2),
            y: +Number(rect.y || 0).toFixed(2),
            w: +Number(rect.w || 0).toFixed(2),
            h: +Number(rect.h || 0).toFixed(2)
        };
    }

    function unionRect(a, b) {
        var left, top, right, bottom;
        if (!a) return cloneRect(b);
        if (!b) return cloneRect(a);

        left = Math.min(a.x, b.x);
        top = Math.min(a.y, b.y);
        right = Math.max(a.x + a.w, b.x + b.w);
        bottom = Math.max(a.y + a.h, b.y + b.h);
        return {
            x: +left.toFixed(2),
            y: +top.toFixed(2),
            w: +(right - left).toFixed(2),
            h: +(bottom - top).toFixed(2)
        };
    }

    function padRectToPage(bounds, page, padX, padY) {
        var left = Math.max(0, bounds.x - padX);
        var top = Math.max(0, bounds.y - padY);
        var right = Math.min(page.width, bounds.x + bounds.w + padX);
        var bottom = Math.min(page.height, bounds.y + bounds.h + padY);
        return {
            x: +left.toFixed(2),
            y: +top.toFixed(2),
            w: +Math.max(1, right - left).toFixed(2),
            h: +Math.max(1, bottom - top).toFixed(2)
        };
    }

    function normalizeHudRect(rect, bounds) {
        return {
            x: +((rect.x - bounds.x) / bounds.w).toFixed(4),
            y: +((rect.y - bounds.y) / bounds.h).toFixed(4),
            w: +(rect.w / bounds.w).toFixed(4),
            h: +(rect.h / bounds.h).toFixed(4)
        };
    }

    function buildHudHotspotRect(page, hotspot) {
        var sceneRect = buildSceneVisualUnionRect(page && page.sceneVisuals ? page.sceneVisuals : [], hotspot.id);
        return cloneRect(sceneRect || hotspot.rect);
    }

    function findHotspot(pageId, hotspotId) {
        var page = getPage(pageId);
        var hotspots = page.hotspots || [];
        for (var i = 0; i < hotspots.length; i++) {
            if (hotspots[i].id === hotspotId) {
                return hotspots[i];
            }
        }
        return null;
    }

    function findHudFocusFilter(page, hotspotId) {
        var filters = page && page.filters ? page.filters : [];
        var hotspotCount = page && page.hotspots ? page.hotspots.length : 0;
        var best = null;
        var ids;
        var i;

        if (!page || !hotspotId || hotspotCount <= 1) return null;

        for (i = 0; i < filters.length; i++) {
            ids = filters[i] && filters[i].hotspotIds ? filters[i].hotspotIds : [];
            if (!ids.length || ids.indexOf(hotspotId) < 0) continue;
            if (filters[i].id === 'all' || filters[i].id === 'hierarchy' || filters[i].viewMode === 'hierarchy') continue;
            if (ids.length >= hotspotCount) continue;

            if (!best || ids.length < best.hotspotIds.length) {
                best = filters[i];
            }
        }

        return best;
    }

    function clampNumber(value, min, max) {
        value = isFinite(value) ? Number(value) : min;
        return Math.max(min, Math.min(max, value));
    }

    function intersectsHotspotIds(leftIds, rightIds) {
        var i;
        if (!leftIds || !rightIds || !leftIds.length || !rightIds.length) return false;
        for (i = 0; i < leftIds.length; i++) {
            if (rightIds.indexOf(leftIds[i]) >= 0) {
                return true;
            }
        }
        return false;
    }

    function buildHudVisualEntries(page, focusIds, focusHotspotId) {
        var visuals = page && page.sceneVisuals ? page.sceneVisuals : [];
        var entries = [];
        var i;
        var rect;
        var hotspotIds;

        for (i = 0; i < visuals.length; i++) {
            hotspotIds = (visuals[i].hotspotIds || []).slice();
            if (focusIds && hotspotIds.length && !intersectsHotspotIds(hotspotIds, focusIds)) continue;

            rect = cloneRect(visuals[i].rect);
            if (!rect || rect.w <= 0 || rect.h <= 0) continue;

            entries.push({
                id: visuals[i].id,
                label: visuals[i].label || visuals[i].id,
                assetUrl: visuals[i].assetUrl,
                hotspotIds: hotspotIds,
                sourceRect: rect,
                isCurrent: hotspotIds.indexOf(focusHotspotId) >= 0
            });
        }

        return entries;
    }

    function resolveHudFitPreset(pageId, focusFilterId) {
        var source = (typeof MapFitPresets !== 'undefined' && MapFitPresets && typeof MapFitPresets.resolve === 'function')
            ? MapFitPresets.resolve(pageId || '', focusFilterId || '')
            : null;

        return {
            padXRate: clampNumber((source && source.padXRate != null ? source.padXRate : 0.055) * 0.42, 0.012, 0.07),
            padXMin: clampNumber((source && source.padXMin != null ? source.padXMin : 22) * 0.22, 2, 20),
            padXMax: clampNumber((source && source.padXMax != null ? source.padXMax : 54) * 0.24, 6, 28),
            padYRate: clampNumber((source && source.padYRate != null ? source.padYRate : 0.07) * 0.38, 0.012, 0.075),
            padYMin: clampNumber((source && source.padYMin != null ? source.padYMin : 20) * 0.18, 2, 18),
            padYMax: clampNumber((source && source.padYMax != null ? source.padYMax : 48) * 0.2, 6, 22)
        };
    }

    function findHotspotPageId(hotspotId) {
        for (var i = 0; i < _pageOrder.length; i++) {
            var page = getPage(_pageOrder[i]);
            var hotspots = page.hotspots || [];
            for (var j = 0; j < hotspots.length; j++) {
                if (hotspots[j].id === hotspotId) {
                    return page.id;
                }
            }
        }
        return '';
    }

    function resolveHotspotMeta(hotspotId) {
        var pageId = findHotspotPageId(hotspotId);
        var page = pageId ? getPage(pageId) : null;
        var hotspot = page ? findHotspot(pageId, hotspotId) : null;
        if (!page || !hotspot) return null;

        return {
            pageId: page.id,
            pageLabel: page.title || page.tabLabel || page.id,
            hotspotId: hotspot.id,
            label: hotspot.label || hotspot.id,
            sceneName: hotspot.sceneName || '',
            rect: buildHudHotspotRect(page, hotspot)
        };
    }

    function getHudOutline(pageId, focusHotspotId) {
        var page = getPage(pageId);
        var hotspots = page && page.hotspots ? page.hotspots : [];
        var focusFilter = findHudFocusFilter(page, focusHotspotId);
        var focusIds = focusFilter && focusFilter.hotspotIds ? focusFilter.hotspotIds : null;
        var focusHotspot = focusHotspotId ? findHotspot(pageId, focusHotspotId) : null;
        var visuals = buildHudVisualEntries(page, focusIds, focusHotspotId);
        var fitPreset = resolveHudFitPreset(pageId, focusFilter ? focusFilter.id : '');
        var blocks = [];
        var bounds = null;
        var i;
        var rect;
        var viewportRect;
        var padX;
        var padY;

        if (!page || !hotspots.length) return null;

        for (i = 0; i < visuals.length; i++) {
            bounds = unionRect(bounds, visuals[i].sourceRect);
        }

        for (i = 0; i < hotspots.length; i++) {
            if (focusIds && focusIds.indexOf(hotspots[i].id) < 0) continue;
            rect = buildHudHotspotRect(page, hotspots[i]);
            if (!rect || rect.w <= 0 || rect.h <= 0) continue;
            bounds = unionRect(bounds, rect);
            blocks.push({
                hotspotId: hotspots[i].id,
                label: hotspots[i].label || hotspots[i].id,
                sourceRect: rect
            });
        }

        if (!bounds || !blocks.length) return null;

        padX = clampNumber(bounds.w * fitPreset.padXRate, fitPreset.padXMin, fitPreset.padXMax);
        padY = clampNumber(bounds.h * fitPreset.padYRate, fitPreset.padYMin, fitPreset.padYMax);
        viewportRect = padRectToPage(bounds, page, padX, padY);

        for (i = 0; i < blocks.length; i++) {
            blocks[i].rect = normalizeHudRect(blocks[i].sourceRect, viewportRect);
        }

        return {
            pageId: page.id,
            pageLabel: page.title || page.tabLabel || page.id,
            focusFilterId: focusFilter ? focusFilter.id : '',
            focusFilterLabel: focusFilter ? (focusFilter.label || focusFilter.id) : '',
            currentRect: focusHotspot ? buildHudHotspotRect(page, focusHotspot) : null,
            viewportRect: viewportRect,
            visuals: visuals,
            blocks: blocks
        };
    }

    function findFilter(pageId, filterId) {
        var page = getPage(pageId);
        var filters = page.filters || [];
        for (var i = 0; i < filters.length; i++) {
            if (filters[i].id === filterId) {
                return filters[i];
            }
        }
        return null;
    }

    function getVisibleHotspots(pageId, filterId) {
        var page = getPage(pageId);
        var hotspots = (page.hotspots || []).slice();
        var filter = findFilter(page.id, filterId);
        var lookup = {};
        var visible = [];
        var i;

        if (!filter || !(filter.hotspotIds || []).length) {
            return hotspots;
        }

        for (i = 0; i < filter.hotspotIds.length; i++) {
            lookup[filter.hotspotIds[i]] = true;
        }

        for (i = 0; i < hotspots.length; i++) {
            if (lookup[hotspots[i].id]) {
                visible.push(hotspots[i]);
            }
        }

        return visible;
    }

    function getVisibleSceneVisuals(pageId, filterId) {
        var page = getPage(pageId);
        var visuals = (page.sceneVisuals || []).slice();
        var visible = [];
        var i;

        if (!filterId || filterId === 'all') {
            return visuals;
        }

        for (i = 0; i < visuals.length; i++) {
            var filterIds = visuals[i].filterIds || [];
            if (!filterIds.length || filterIds.indexOf(filterId) >= 0) {
                visible.push(visuals[i]);
            }
        }

        return visible;
    }

    function buildFilterIdsForHotspot(page, hotspotId) {
        var filterIds = [];
        var filters = page.filters || [];
        for (var i = 0; i < filters.length; i++) {
            if ((filters[i].hotspotIds || []).indexOf(hotspotId) >= 0) {
                filterIds.push(filters[i].id);
            }
        }
        return filterIds;
    }

    // C 阶段后 staticAvatars 不再带 x/y/w/h, dynamicAvatars 也改为 relX/relY;
    // exportPage 派生 marker rect 走 source-data + hotspot.rect 两步计算。
    // MapAvatarSourceData 可能未加载 (overlay.html boot 期 / 旧 Node 工具仅加载 panel-data),
    // 此时返回 null rect 而不是空对象, 让消费方明确处理 missing-source 状况。
    function resolveStaticAvatarExportRect(pageId, slot) {
        if (!slot || !slot.assetUrl) return null;
        if (typeof MapAvatarSourceData === 'undefined' || !MapAvatarSourceData || !MapAvatarSourceData.getByAssetUrl) return null;
        var sourceSlot = MapAvatarSourceData.getByAssetUrl(slot.assetUrl);
        if (!sourceSlot || !sourceSlot.size) return null;
        var hotspotId = slot.hotspotId || sourceSlot.hotspotId;
        if (!hotspotId) return null;
        var hotspot = findHotspot(pageId, hotspotId);
        if (!hotspot || !hotspot.rect) return null;
        var relX = slot.relX !== undefined ? Number(slot.relX) : sourceSlot.relX;
        var relY = slot.relY !== undefined ? Number(slot.relY) : sourceSlot.relY;
        var w = slot.w !== undefined ? Number(slot.w) : sourceSlot.size.w;
        var h = slot.h !== undefined ? Number(slot.h) : sourceSlot.size.h;
        return {
            x: hotspot.rect.x + relX,
            y: hotspot.rect.y + relY,
            w: w,
            h: h
        };
    }

    function resolveDynamicAvatarExportRect(pageId, slot) {
        if (!slot || !slot.hotspotId) return null;
        var hotspot = findHotspot(pageId, slot.hotspotId);
        if (!hotspot || !hotspot.rect) return null;
        return {
            x: hotspot.rect.x + slot.relX,
            y: hotspot.rect.y + slot.relY,
            w: slot.w,
            h: slot.h
        };
    }

    function exportPage(pageId) {
        var page = getPage(pageId);
        var filters = page.filters || [];
        var hotspots = page.hotspots || [];
        var staticAvatars = page.staticAvatars || [];
        var slots = page.dynamicAvatars || [];
        var sceneNodes = [];
        var exportedHotspots = [];
        var markers = [];

        for (var i = 0; i < filters.length; i++) {
            var filterUnlockGroup = getFilterUnlockGroup(page.id, filters[i].id);
            var filterMeta = getUnlockGroupMeta(filterUnlockGroup);
            sceneNodes.push({
                id: filters[i].id,
                label: filters[i].label,
                kind: 'filter',
                hotspotIds: (filters[i].hotspotIds || []).slice(),
                buttonRect: filters[i].buttonRect || null,
                displayConditions: filterMeta ? [filterMeta.conditionId] : [],
                interactionState: {
                    enabledBy: filterMeta ? ('unlock.' + filterUnlockGroup) : 'always',
                    lockedReason: filterMeta ? filterMeta.lockedReason : ''
                }
            });
        }

        for (var v = 0; v < (page.sceneVisuals || []).length; v++) {
            sceneNodes.push({
                id: page.sceneVisuals[v].id,
                label: page.sceneVisuals[v].label,
                kind: 'sceneVisual',
                asset: page.sceneVisuals[v].assetUrl,
                rect: page.sceneVisuals[v].rect,
                filterIds: (page.sceneVisuals[v].filterIds || []).slice(),
                hotspotIds: (page.sceneVisuals[v].hotspotIds || []).slice()
            });
        }

        for (var j = 0; j < hotspots.length; j++) {
            var hotspotUnlockGroup = getHotspotUnlockGroup(page.id, hotspots[j].id);
            var hotspotMeta = getUnlockGroupMeta(hotspotUnlockGroup);
            exportedHotspots.push({
                id: hotspots[j].id,
                label: hotspots[j].label,
                rect: hotspots[j].rect,
                sourceRect: getSourceRect(page.id, hotspots[j].id),
                target: {
                    type: 'scene',
                    sceneName: hotspots[j].sceneName
                },
                display: {
                    filterIds: buildFilterIdsForHotspot(page, hotspots[j].id),
                    when: hotspotMeta ? [hotspotMeta.conditionId] : []
                },
                interactionState: {
                    enabledBy: hotspotMeta ? ('unlock.' + hotspotUnlockGroup) : 'always',
                    lockedReason: hotspotMeta ? hotspotMeta.lockedReason : ''
                },
                layoutAudit: getLayoutAuditMeta(page.id, hotspots[j].id)
            });
        }

        for (var k = 0; k < staticAvatars.length; k++) {
            markers.push({
                id: staticAvatars[k].id,
                kind: 'staticAvatar',
                label: staticAvatars[k].label || '',
                hotspotId: staticAvatars[k].hotspotId || null,
                asset: staticAvatars[k].assetUrl,
                rect: resolveStaticAvatarExportRect(page.id, staticAvatars[k])
            });
        }

        for (k = 0; k < slots.length; k++) {
            markers.push({
                id: slots[k].id,
                kind: 'dynamicAvatar',
                stateKey: slots[k].kind,
                hotspotId: slots[k].hotspotId || null,
                rect: resolveDynamicAvatarExportRect(page.id, slots[k])
            });
        }

        return {
            id: page.id,
            title: page.title,
            tabLabel: page.tabLabel,
            size: {
                width: page.width,
                height: page.height
            },
            layers: [
                {
                    id: 'background',
                    kind: 'background',
                    asset: page.backgroundUrl,
                    width: page.width,
                    height: page.height
                }
            ],
            sceneNodes: sceneNodes,
            hotspots: exportedHotspots,
            markers: markers,
            flashHints: buildPageFlashHints(page),
            displayConditions: buildPageDisplayConditions(page.id),
            interactionState: {
                defaultFilterId: page.defaultFilterId || '',
                snapshotVersion: 2,
                renderMode: page.renderMode || 'background',
                backdropTheme: page.backdropTheme || 'default'
            }
        };
    }

    function exportManifest() {
        var pages = {};
        for (var i = 0; i < _pageOrder.length; i++) {
            pages[_pageOrder[i]] = exportPage(_pageOrder[i]);
        }
        return {
            version: 2,
            id: 'cf7.map',
            schema: 'cf7.map/manifest-v2',
            sourceRefs: _sourceRefs,
            unlockGroups: _unlockGroups,
            pageOrder: _pageOrder.slice(),
            pageAliases: _pageAliases,
            pages: pages
        };
    }

    function getAssetCapability(pageId, filterId) {
        if (_definition.version < 2) return null; // 只供冻结的一阶段测试夹具使用旧几何。
        var page = (_definition.assetCapabilities || {})[pageId] || {};
        return JSON.parse(JSON.stringify(page[filterId || '*'] || page['*'] || {sourceRatio:1,verified:false,worstAsset:''}));
    }

    return {
        create: createMapPanelData,
        getAssetCapability: getAssetCapability,
        getManifest: getManifest,
        getPage: getPage,
        getPageOrder: getPageOrder,
        getUnlockGroupMeta: getUnlockGroupMeta,
        getHotspotUnlockGroup: getHotspotUnlockGroup,
        getFilterUnlockGroup: getFilterUnlockGroup,
        getPageFlashHints: getPageFlashHints,
        getPageDisplayConditions: getPageDisplayConditions,
        getSourceRect: getSourceRect,
        isHandTunedLayout: isHandTunedLayout,
        getLayoutAuditMeta: getLayoutAuditMeta,
        normalizeUnlockFlags: normalizeUnlockFlags,
        evaluateCondition: evaluateCondition,
        buildHotspotStates: buildHotspotStates,
        buildEnabledHotspotIds: buildEnabledHotspotIds,
        resolvePageId: resolvePageId,
        isLayerRelationFilter: isLayerRelationFilter,
        getAllHotspotIds: getAllHotspotIds,
        findHotspot: findHotspot,
        findHotspotPageId: findHotspotPageId,
        resolveHotspotMeta: resolveHotspotMeta,
        getHudOutline: getHudOutline,
        findFilter: findFilter,
        getVisibleHotspots: getVisibleHotspots,
        getVisibleSceneVisuals: getVisibleSceneVisuals,
        prewarmAssets: prewarmAssets,
        exportPage: exportPage,
        exportManifest: exportManifest
    };
})();

var MapManifest = MapPanelData.exportManifest();
