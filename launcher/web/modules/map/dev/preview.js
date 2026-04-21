var MapPreview = (function() {
    'use strict';

    var DRAFT_STORAGE_KEY = 'cf7.map.preview.builderDrafts.v1';
    var _els = {};
    var _state = {
        pageId: 'base',
        filterId: '',
        viewport: '1600x900',
        mode: 'preview',
        roommateGender: 'male',
        lockedGroups: [],
        fit: true,
        showHotspots: true,
        showSource: true,
        showLabels: true,
        showButtons: true,
        showAvatars: true,
        showHints: true,
        selectedTargetKind: '',
        selectedTargetId: '',
        step: 1,
        draftRects: {},
        draftFilterRects: {},
        drag: null
    };

    function init() {
        bindElements();
        hydrateFromQuery();
        loadDraftState();
        buildPageSelect();
        bindControls();
        bindKeyboard();
        applyViewport();
        render();
    }

    function bindElements() {
        _els.pageSelect = document.getElementById('preview-page-select');
        _els.filterSelect = document.getElementById('preview-filter-select');
        _els.viewportSelect = document.getElementById('preview-viewport-select');
        _els.roommateSelect = document.getElementById('preview-roommate-select');
        _els.lockedGroupsInput = document.getElementById('preview-locked-groups-input');
        _els.fitCheckbox = document.getElementById('preview-fit-checkbox');
        _els.hotspotsCheckbox = document.getElementById('preview-hotspots-checkbox');
        _els.sourceCheckbox = document.getElementById('preview-source-checkbox');
        _els.labelsCheckbox = document.getElementById('preview-labels-checkbox');
        _els.buttonsCheckbox = document.getElementById('preview-buttons-checkbox');
        _els.avatarsCheckbox = document.getElementById('preview-avatars-checkbox');
        _els.hintsCheckbox = document.getElementById('preview-hints-checkbox');
        _els.stepInput = document.getElementById('preview-step-input');
        _els.builderCheckbox = document.getElementById('preview-builder-checkbox');
        _els.resetBtn = document.getElementById('preview-reset-btn');
        _els.copyPageBtn = document.getElementById('preview-copy-page-btn');
        _els.copyManifestBtn = document.getElementById('preview-copy-manifest-btn');
        _els.copyAuditBtn = document.getElementById('preview-copy-audit-btn');
        _els.copyOverridesBtn = document.getElementById('preview-copy-overrides-btn');
        _els.pasteOverridesBtn = document.getElementById('preview-paste-overrides-btn');
        _els.clearPageDraftsBtn = document.getElementById('preview-clear-page-drafts-btn');
        _els.clearAllDraftsBtn = document.getElementById('preview-clear-all-drafts-btn');
        _els.downloadPageBtn = document.getElementById('preview-download-page-btn');
        _els.downloadAuditBtn = document.getElementById('preview-download-audit-btn');
        _els.resetSelectedBtn = document.getElementById('preview-reset-selected-btn');
        _els.snapSelectedBtn = document.getElementById('preview-snap-selected-btn');
        _els.copySelectedBtn = document.getElementById('preview-copy-selected-btn');
        _els.calibration = document.getElementById('preview-calibration');
        _els.status = document.getElementById('preview-status');
        _els.shell = document.getElementById('preview-shell');
        _els.stageWrap = document.getElementById('preview-stage-wrap');
        _els.stage = document.getElementById('preview-stage');
        _els.backdrop = document.getElementById('preview-stage-backdrop');
        _els.image = document.getElementById('preview-stage-image');
        _els.sceneLayer = document.getElementById('preview-scene-layer');
        _els.sourceLayer = document.getElementById('preview-source-layer');
        _els.hotspotLayer = document.getElementById('preview-hotspot-layer');
        _els.avatarLayer = document.getElementById('preview-avatar-layer');
        _els.hintLayer = document.getElementById('preview-hint-layer');
        _els.filterLayer = document.getElementById('preview-filter-layer');
        _els.summary = document.getElementById('preview-summary');
        _els.selection = document.getElementById('preview-selection');
        _els.audit = document.getElementById('preview-audit');
        _els.dump = document.getElementById('preview-dump');
    }

    function hydrateFromQuery() {
        var query = new URLSearchParams(window.location.search);
        _state.pageId = MapPanelData.resolvePageId(query.get('page') || _state.pageId);
        _state.filterId = query.get('filter') || _state.filterId;
        _state.viewport = query.get('viewport') || _state.viewport;
        _state.mode = resolveMode(query.get('mode') || '');
        _state.roommateGender = query.get('gender') || _state.roommateGender;
        _state.lockedGroups = parseList(query.get('lockedGroups'));
        _state.fit = query.get('fit') !== '0';
        _state.showHotspots = query.get('hotspots') !== '0';
        _state.showSource = query.get('source') !== '0';
        _state.showLabels = query.get('labels') !== '0';
        _state.showButtons = query.get('buttons') !== '0';
        _state.showAvatars = query.get('avatars') !== '0';
        _state.showHints = query.get('hints') !== '0';
        _state.step = normalizeStep(query.get('step') || '1');
    }

    function buildPageSelect() {
        var ids = MapPanelData.getPageOrder();
        _els.pageSelect.innerHTML = '';
        for (var i = 0; i < ids.length; i += 1) {
            var page = MapPanelData.getPage(ids[i]);
            var opt = document.createElement('option');
            opt.value = page.id;
            opt.textContent = page.tabLabel + ' [' + page.id + ']';
            _els.pageSelect.appendChild(opt);
        }
        syncControls();
    }

    function bindControls() {
        _els.pageSelect.addEventListener('change', function() {
            _state.pageId = MapPanelData.resolvePageId(_els.pageSelect.value);
            _state.filterId = '';
            clearSelection();
            render();
        });

        _els.filterSelect.addEventListener('change', function() {
            _state.filterId = _els.filterSelect.value;
            clearSelection();
            render();
        });

        _els.viewportSelect.addEventListener('change', function() {
            _state.viewport = _els.viewportSelect.value;
            applyViewport();
            render();
        });

        _els.roommateSelect.addEventListener('change', function() {
            _state.roommateGender = _els.roommateSelect.value;
            render();
        });

        _els.lockedGroupsInput.addEventListener('change', function() {
            _state.lockedGroups = parseList(_els.lockedGroupsInput.value);
            render();
        });

        _els.fitCheckbox.addEventListener('change', function() {
            _state.fit = _els.fitCheckbox.checked;
            render();
        });

        _els.hotspotsCheckbox.addEventListener('change', function() {
            _state.showHotspots = _els.hotspotsCheckbox.checked;
            render();
        });

        _els.sourceCheckbox.addEventListener('change', function() {
            _state.showSource = _els.sourceCheckbox.checked;
            render();
        });

        _els.labelsCheckbox.addEventListener('change', function() {
            _state.showLabels = _els.labelsCheckbox.checked;
            render();
        });

        _els.buttonsCheckbox.addEventListener('change', function() {
            _state.showButtons = _els.buttonsCheckbox.checked;
            render();
        });

        _els.avatarsCheckbox.addEventListener('change', function() {
            _state.showAvatars = _els.avatarsCheckbox.checked;
            render();
        });

        _els.hintsCheckbox.addEventListener('change', function() {
            _state.showHints = _els.hintsCheckbox.checked;
            render();
        });

        _els.stepInput.addEventListener('change', function() {
            _state.step = normalizeStep(_els.stepInput.value);
            _els.stepInput.value = String(_state.step);
        });

        _els.builderCheckbox.addEventListener('change', function() {
            _state.mode = _els.builderCheckbox.checked ? 'builder' : 'preview';
            render();
        });

        _els.resetBtn.addEventListener('click', function() {
            clearSelection();
            _els.shell.scrollTop = 0;
            _els.shell.scrollLeft = 0;
            render();
        });

        _els.copyPageBtn.addEventListener('click', function() {
            copyJson(buildCalibratedPageExport(_state.pageId), 'copied page json');
        });

        _els.copyManifestBtn.addEventListener('click', function() {
            copyJson(buildCalibratedManifestExport(), 'copied full manifest');
        });

        _els.copyAuditBtn.addEventListener('click', function() {
            copyJson(buildAuditExport(), 'copied audit json');
        });

        _els.copyOverridesBtn.addEventListener('click', function() {
            copyJson(buildPageOverridesBundle(_state.pageId), 'copied page overrides');
        });

        _els.pasteOverridesBtn.addEventListener('click', function() {
            pasteOverrideBundle();
        });

        _els.clearPageDraftsBtn.addEventListener('click', function() {
            clearPageDrafts(_state.pageId);
        });

        _els.clearAllDraftsBtn.addEventListener('click', function() {
            clearAllDrafts();
        });

        _els.downloadPageBtn.addEventListener('click', function() {
            downloadJson(buildCalibratedPageExport(_state.pageId), 'map-page-' + _state.pageId + '.json');
        });

        _els.downloadAuditBtn.addEventListener('click', function() {
            downloadJson(buildAuditExport(), 'map-audit-' + _state.pageId + '.json');
        });

        _els.resetSelectedBtn.addEventListener('click', function() {
            resetSelectedRect();
        });

        _els.snapSelectedBtn.addEventListener('click', function() {
            snapSelectedToSource();
        });

        _els.copySelectedBtn.addEventListener('click', function() {
            copySelectedOverride();
        });

        if (_els.calibration) {
            _els.calibration.addEventListener('click', function(event) {
                var op = event.target && event.target.getAttribute ? event.target.getAttribute('data-calib') : '';
                if (!op) return;
                event.preventDefault();
                applyCalibration(op);
            });
        }
    }

    function bindKeyboard() {
        document.addEventListener('keydown', function(event) {
            if (!_state.selectedTargetId || shouldIgnoreKeyEvent(event)) return;

            if (event.key === 'ArrowLeft') {
                event.preventDefault();
                applyCalibration(event.shiftKey ? 'w-' : 'x-');
            } else if (event.key === 'ArrowRight') {
                event.preventDefault();
                applyCalibration(event.shiftKey ? 'w+' : 'x+');
            } else if (event.key === 'ArrowUp') {
                event.preventDefault();
                applyCalibration(event.shiftKey ? 'h-' : 'y-');
            } else if (event.key === 'ArrowDown') {
                event.preventDefault();
                applyCalibration(event.shiftKey ? 'h+' : 'y+');
            }
        });
    }

    function syncControls() {
        _els.pageSelect.value = _state.pageId;
        _els.viewportSelect.value = _state.viewport;
        _els.builderCheckbox.checked = _state.mode === 'builder';
        _els.roommateSelect.value = _state.roommateGender;
        _els.lockedGroupsInput.value = _state.lockedGroups.join(',');
        _els.fitCheckbox.checked = _state.fit;
        _els.hotspotsCheckbox.checked = _state.showHotspots;
        _els.sourceCheckbox.checked = _state.showSource;
        _els.labelsCheckbox.checked = _state.showLabels;
        _els.buttonsCheckbox.checked = _state.showButtons;
        _els.avatarsCheckbox.checked = _state.showAvatars;
        _els.hintsCheckbox.checked = _state.showHints;
        _els.stepInput.value = String(_state.step);
    }

    function parseList(value) {
        return String(value || '')
            .split(',')
            .map(function(item) { return item.trim(); })
            .filter(Boolean);
    }

    function resolveMode(value) {
        var mode = String(value || window.__MAP_PREVIEW_MODE || '').toLowerCase();
        return mode === 'builder' ? 'builder' : 'preview';
    }

    function normalizeStep(value) {
        return Math.max(0.1, parseFloat(value || '1') || 1);
    }

    function round(value) {
        return Math.round(Number(value || 0) * 100) / 100;
    }

    function snapToStep(value, step) {
        return round(Math.round(Number(value || 0) / step) * step);
    }

    function shouldIgnoreKeyEvent(event) {
        var target = event.target;
        var tag = target && target.tagName ? target.tagName.toLowerCase() : '';
        return tag === 'input' || tag === 'textarea' || tag === 'select' || (target && target.isContentEditable);
    }

    function parseViewport(value) {
        var parts = String(value || '1600x900').split('x');
        return {
            width: Math.max(800, parseInt(parts[0] || '1600', 10) || 1600),
            height: Math.max(600, parseInt(parts[1] || '900', 10) || 900)
        };
    }

    function applyViewport() {
        var viewport = parseViewport(_state.viewport);
        _els.shell.style.width = viewport.width + 'px';
        _els.shell.style.height = viewport.height + 'px';
    }

    function resolvePage() {
        return MapPanelData.getPage(_state.pageId);
    }

    function selectTarget(kind, id) {
        _state.selectedTargetKind = kind || '';
        _state.selectedTargetId = id || '';
    }

    function clearSelection() {
        selectTarget('', '');
    }

    function isSelected(kind, id) {
        return _state.selectedTargetKind === kind && _state.selectedTargetId === id;
    }

    function loadDraftState() {
        if (!window.localStorage) return;
        try {
            var raw = window.localStorage.getItem(DRAFT_STORAGE_KEY);
            if (!raw) return;
            var parsed = JSON.parse(raw);
            _state.draftRects = parsed && parsed.hotspots ? parsed.hotspots : {};
            _state.draftFilterRects = parsed && parsed.filters ? parsed.filters : {};
        } catch (err) {
            _state.draftRects = {};
            _state.draftFilterRects = {};
        }
    }

    function persistDraftState() {
        if (!window.localStorage) return;
        try {
            window.localStorage.setItem(DRAFT_STORAGE_KEY, JSON.stringify({
                hotspots: _state.draftRects,
                filters: _state.draftFilterRects
            }));
        } catch (err) {
            // Ignore persistence failures; preview/builder should remain usable without localStorage.
        }
    }

    function resolveFilter(page) {
        var filter = MapPanelData.findFilter(page.id, _state.filterId);
        if (filter) return filter;

        var fallbackId = page.defaultFilterId || ((page.filters && page.filters[0]) ? page.filters[0].id : '');
        _state.filterId = fallbackId;
        return MapPanelData.findFilter(page.id, fallbackId);
    }

    function resolveAuditFilter(page) {
        if (_state.pageId === page.id) {
            return resolveFilter(page);
        }
        var fallbackId = page.defaultFilterId || ((page.filters && page.filters[0]) ? page.filters[0].id : '');
        return MapPanelData.findFilter(page.id, fallbackId);
    }

    function getVisibleHotspots(page, filter) {
        return MapPanelData.getVisibleHotspots(page.id, filter ? filter.id : '');
    }

    function getActiveViewMode(page, filter) {
        return MapPanelData.isLayerRelationFilter(page.id, filter ? filter.id : '') ? 'hierarchy' : 'default';
    }

    function getCurrentHotspotId(visibleHotspots, hotspotStates) {
        for (var i = 0; i < visibleHotspots.length; i += 1) {
            var state = hotspotStates[visibleHotspots[i].id];
            if (!state || state.enabled) {
                return visibleHotspots[i].id;
            }
        }
        return visibleHotspots[0] ? visibleHotspots[0].id : '';
    }

    function getFocusHotspotId(visibleHotspots, currentHotspotId) {
        var selectedHotspotId = _state.selectedTargetKind === 'hotspot' ? _state.selectedTargetId : '';
        for (var i = 0; i < visibleHotspots.length; i += 1) {
            if (visibleHotspots[i].id === selectedHotspotId) {
                return selectedHotspotId;
            }
        }
        return currentHotspotId;
    }

    function render() {
        syncControls();

        var page = resolvePage();
        var filter = resolveFilter(page);
        var visibleHotspots = getVisibleHotspots(page, filter);
        var unlocks = buildUnlockFlags();
        var hotspotStates = MapPanelData.buildHotspotStates(unlocks);
        var activeViewMode = getActiveViewMode(page, filter);
        var currentHotspotId = getCurrentHotspotId(visibleHotspots, hotspotStates);
        var focusHotspotId = getFocusHotspotId(visibleHotspots, currentHotspotId);

        renderFilterSelect(page, filter);
        renderStage(page, filter, visibleHotspots, hotspotStates, unlocks, activeViewMode, currentHotspotId, focusHotspotId);
        renderSummary(page, filter, visibleHotspots, hotspotStates, activeViewMode, currentHotspotId, focusHotspotId);
        renderSelection(page, filter, hotspotStates, activeViewMode, currentHotspotId, focusHotspotId);
        renderAudit(page, visibleHotspots);
        renderDump(page, filter, visibleHotspots, hotspotStates, unlocks, activeViewMode, currentHotspotId, focusHotspotId);
        renderStatus(page, filter, visibleHotspots, activeViewMode, currentHotspotId, focusHotspotId);
    }

    function buildUnlockFlags() {
        var unlocks = MapPanelData.normalizeUnlockFlags({});
        for (var i = 0; i < _state.lockedGroups.length; i += 1) {
            if (_state.lockedGroups[i]) {
                unlocks[_state.lockedGroups[i]] = false;
            }
        }
        return unlocks;
    }

    function renderFilterSelect(page, filter) {
        var filters = page.filters || [];
        _els.filterSelect.innerHTML = '';
        for (var i = 0; i < filters.length; i += 1) {
            var opt = document.createElement('option');
            opt.value = filters[i].id;
            opt.textContent = filters[i].label + ' [' + filters[i].id + ']';
            _els.filterSelect.appendChild(opt);
        }
        _els.filterSelect.value = filter ? filter.id : '';
    }

    function getDraftRect(hotspotId) {
        return hotspotId ? (_state.draftRects[hotspotId] || null) : null;
    }

    function getDraftFilterRect(pageId, filterId) {
        var pageRects = _state.draftFilterRects[pageId] || {};
        return filterId ? (pageRects[filterId] || null) : null;
    }

    function setDraftRect(kind, pageId, id, rect) {
        if (!id || !rect) return;
        if (kind === 'filter') {
            if (!_state.draftFilterRects[pageId]) {
                _state.draftFilterRects[pageId] = {};
            }
            _state.draftFilterRects[pageId][id] = roundRect(rect);
        } else {
            _state.draftRects[id] = roundRect(rect);
        }
        persistDraftState();
    }

    function removeDraftRect(kind, pageId, id) {
        if (!id) return;
        if (kind === 'filter') {
            if (_state.draftFilterRects[pageId]) {
                delete _state.draftFilterRects[pageId][id];
                if (!Object.keys(_state.draftFilterRects[pageId]).length) {
                    delete _state.draftFilterRects[pageId];
                }
            }
        } else {
            delete _state.draftRects[id];
        }
        persistDraftState();
    }

    function cloneRect(rect) {
        return rect ? {
            x: rect.x,
            y: rect.y,
            w: rect.w,
            h: rect.h
        } : null;
    }

    function roundRect(rect) {
        return {
            x: round(rect.x),
            y: round(rect.y),
            w: round(rect.w),
            h: round(rect.h)
        };
    }

    function sameRect(a, b) {
        return !!a && !!b &&
            round(a.x) === round(b.x) &&
            round(a.y) === round(b.y) &&
            round(a.w) === round(b.w) &&
            round(a.h) === round(b.h);
    }

    function getRenderRect(pageId, hotspot) {
        if (!hotspot) return null;
        return cloneRect(getDraftRect(hotspot.id) || hotspot.rect);
    }

    function getRenderFilterRect(pageId, filter) {
        if (!filter || !filter.buttonRect) return null;
        return cloneRect(getDraftFilterRect(pageId, filter.id) || filter.buttonRect);
    }

    function computeAudit(pageId, hotspotId, rect) {
        var sourceRect = MapPanelData.getSourceRect(pageId, hotspotId);
        if (!sourceRect || !rect) {
            return {
                status: 'missing',
                note: 'missing_xfl_ref',
                dx: null,
                dy: null,
                sourceRect: null
            };
        }

        var dx = round(rect.x - sourceRect.x);
        var dy = round(rect.y - sourceRect.y);
        if (MapPanelData.isHandTunedLayout(hotspotId)) {
            return { status: 'hand_tuned', note: 'hand_tuned_composite_rect', dx: dx, dy: dy, sourceRect: sourceRect };
        }
        if (Math.abs(dx) <= 0.5 && Math.abs(dy) <= 0.5) {
            return { status: 'exact', note: 'xfl_aligned', dx: dx, dy: dy, sourceRect: sourceRect };
        }
        if (Math.abs(dx) <= 8 && Math.abs(dy) <= 8) {
            return { status: 'near', note: 'minor_delta', dx: dx, dy: dy, sourceRect: sourceRect };
        }
        return { status: 'review', note: 'large_delta', dx: dx, dy: dy, sourceRect: sourceRect };
    }

    function cloneSourceRect(rect) {
        return rect ? {
            x: round(rect.x),
            y: round(rect.y),
            w: round(rect.w),
            h: round(rect.h)
        } : null;
    }

    function rectCenter(rect) {
        if (!rect) return null;
        return {
            x: round(rect.x + (rect.w / 2)),
            y: round(rect.y + (rect.h / 2))
        };
    }

    function rectDelta(currentRect, sourceRect) {
        if (!currentRect || !sourceRect) return null;
        var currentCenter = rectCenter(currentRect);
        var sourceCenter = rectCenter(sourceRect);
        return {
            dx: round(currentRect.x - sourceRect.x),
            dy: round(currentRect.y - sourceRect.y),
            dw: round(currentRect.w - sourceRect.w),
            dh: round(currentRect.h - sourceRect.h),
            centerDx: round(currentCenter.x - sourceCenter.x),
            centerDy: round(currentCenter.y - sourceCenter.y)
        };
    }

    function maxAbsDelta(delta) {
        if (!delta) return 0;
        return Math.max(
            Math.abs(delta.dx),
            Math.abs(delta.dy),
            Math.abs(delta.dw),
            Math.abs(delta.dh),
            Math.abs(delta.centerDx),
            Math.abs(delta.centerDy)
        );
    }

    function unionRects(rects) {
        var filtered = (rects || []).filter(Boolean);
        if (!filtered.length) return null;

        var minX = filtered[0].x;
        var minY = filtered[0].y;
        var maxX = filtered[0].x + filtered[0].w;
        var maxY = filtered[0].y + filtered[0].h;
        var i;

        for (i = 1; i < filtered.length; i += 1) {
            minX = Math.min(minX, filtered[i].x);
            minY = Math.min(minY, filtered[i].y);
            maxX = Math.max(maxX, filtered[i].x + filtered[i].w);
            maxY = Math.max(maxY, filtered[i].y + filtered[i].h);
        }

        return {
            x: round(minX),
            y: round(minY),
            w: round(maxX - minX),
            h: round(maxY - minY)
        };
    }

    function rectIou(a, b) {
        if (!a || !b) return null;
        var left = Math.max(a.x, b.x);
        var top = Math.max(a.y, b.y);
        var right = Math.min(a.x + a.w, b.x + b.w);
        var bottom = Math.min(a.y + a.h, b.y + b.h);
        var width = Math.max(0, right - left);
        var height = Math.max(0, bottom - top);
        var intersection = width * height;
        var union = (a.w * a.h) + (b.w * b.h) - intersection;
        return union ? round(intersection / union) : 0;
    }

    function getAvatarSourceSlot(assetUrl) {
        if (typeof MapAvatarSourceData === 'undefined' || !MapAvatarSourceData || !MapAvatarSourceData.getByAssetUrl) {
            return null;
        }
        return MapAvatarSourceData.getByAssetUrl(assetUrl || '');
    }

    function getAvatarDisplayRect(slot) {
        var sourceSlot = getAvatarSourceSlot(slot && slot.assetUrl);
        if (sourceSlot && sourceSlot.rect) {
            return cloneSourceRect(sourceSlot.rect);
        }
        return slot ? cloneSourceRect({ x: slot.x, y: slot.y, w: slot.w, h: slot.h }) : null;
    }

    function getComponentRect(page, hotspotId) {
        if (!page || !hotspotId) return null;
        var visuals = page.sceneVisuals || [];
        var rects = [];
        var i;

        for (i = 0; i < visuals.length; i += 1) {
            if (containsHotspotId(visuals[i].hotspotIds || [], hotspotId)) {
                rects.push(cloneSourceRect(visuals[i].rect));
            }
        }

        return unionRects(rects);
    }

    function computeComponentAudit(page, hotspotId, renderRect) {
        var componentRect = getComponentRect(page, hotspotId);
        var sourceRect = MapPanelData.getSourceRect(page.id, hotspotId);
        return {
            componentRect: componentRect,
            componentDelta: rectDelta(componentRect, sourceRect),
            boxVsComponent: rectDelta(renderRect, componentRect),
            boxVsComponentIou: rectIou(renderRect, componentRect)
        };
    }

    function computeAvatarAudit(slot) {
        var sourceSlot = getAvatarSourceSlot(slot.assetUrl);
        var currentRect = getAvatarDisplayRect(slot);
        var sourceRect = sourceSlot ? cloneSourceRect(sourceSlot.rect) : null;
        var delta = rectDelta(currentRect, sourceRect);
        var maxDelta = maxAbsDelta(delta);

        if (!sourceRect) {
            return {
                status: 'missing',
                note: 'missing_avatar_source',
                sourceRect: null,
                delta: null,
                sourceSlot: null
            };
        }

        if (maxDelta <= 0.5) {
            return { status: 'exact', note: 'xfl_aligned', sourceRect: sourceRect, delta: delta, sourceSlot: sourceSlot };
        }
        if (maxDelta <= 4) {
            return { status: 'near', note: 'minor_delta', sourceRect: sourceRect, delta: delta, sourceSlot: sourceSlot };
        }
        return { status: 'review', note: 'large_delta', sourceRect: sourceRect, delta: delta, sourceSlot: sourceSlot };
    }

    function renderStage(page, filter, visibleHotspots, hotspotStates, unlocks, activeViewMode, currentHotspotId, focusHotspotId) {
        _els.stage.style.width = page.width + 'px';
        _els.stage.style.height = page.height + 'px';
        renderStageBackdrop(page, activeViewMode);
        renderStageImage(page);

        var shellRect = _els.shell.getBoundingClientRect();
        var scale = _state.fit
            ? Math.min((shellRect.width - 24) / page.width, (shellRect.height - 24) / page.height, 1)
            : 1;

        _els.stageWrap.style.width = Math.round(page.width * scale) + 'px';
        _els.stageWrap.style.height = Math.round(page.height * scale) + 'px';
        _els.stageWrap.style.transform = 'scale(' + scale.toFixed(4) + ')';

        renderSceneVisuals(page, filter, hotspotStates, activeViewMode, currentHotspotId, focusHotspotId);
        renderSourceRects(page, visibleHotspots);
        renderHotspots(visibleHotspots, hotspotStates, activeViewMode, currentHotspotId, focusHotspotId);
        renderFilterButtons(page, filter, unlocks);
        renderAvatars(page, currentHotspotId, focusHotspotId);
        renderHints(page, unlocks);
    }

    function useAssembledVisuals(page) {
        return !!(page && page.renderMode === 'assembled' && page.sceneVisuals && page.sceneVisuals.length);
    }

    function renderStageBackdrop(page, activeViewMode) {
        var theme = page && page.backdropTheme ? page.backdropTheme : 'default';
        _els.stage.classList.toggle('is-assembled', useAssembledVisuals(page));
        _els.stage.classList.toggle('is-layer-relation', activeViewMode === 'hierarchy');
        _els.stage.setAttribute('data-page-id', page ? page.id : '');
        _els.backdrop.className = 'preview-stage-backdrop preview-stage-backdrop--' + theme;
    }

    function renderStageImage(page) {
        var hasBackground = !!(page && page.backgroundUrl);
        var hideImage = useAssembledVisuals(page);

        _els.image.classList.toggle('is-hidden', !hasBackground || hideImage);
        _els.image.width = page.width;
        _els.image.height = page.height;

        if (hasBackground) {
            _els.image.src = resolveAssetPath(page.backgroundUrl);
            return;
        }

        _els.image.removeAttribute('src');
    }

    function getVisibleSceneVisuals(page, filter) {
        return MapPanelData.getVisibleSceneVisuals(page.id, filter ? filter.id : '');
    }

    function renderSceneVisuals(page, filter, hotspotStates, activeViewMode, currentHotspotId, focusHotspotId) {
        _els.sceneLayer.innerHTML = '';
        if (!useAssembledVisuals(page)) return;

        var visuals = getVisibleSceneVisuals(page, filter);
        for (var i = 0; i < visuals.length; i += 1) {
            var visual = visuals[i];
            if (!visual || !visual.rect || !visual.assetUrl) continue;

            var rect = visual.rect;
            var el = document.createElement('div');
            var enabledCount = countEnabledHotspots(visual.hotspotIds || [], hotspotStates);
            var isLocked = !!((visual.hotspotIds || []).length && enabledCount === 0);
            var isSelectedVisual = containsHotspotId(visual.hotspotIds || [], _state.selectedTargetKind === 'hotspot' ? _state.selectedTargetId : '');
            var isCurrent = containsHotspotId(visual.hotspotIds || [], currentHotspotId);
            var isFocused = containsHotspotId(visual.hotspotIds || [], focusHotspotId);
            var isMuted = !!focusHotspotId && !isFocused;

            el.className = 'preview-scene-node'
                + (isLocked ? ' is-disabled' : '')
                + (isSelectedVisual ? ' is-selected' : '')
                + (isCurrent ? ' is-current' : '')
                + (isFocused ? ' is-emphasis' : '')
                + (isMuted ? ' is-muted' : '')
                + (activeViewMode === 'hierarchy' ? ' is-relationship' : '');
            el.style.left = rect.x + 'px';
            el.style.top = rect.y + 'px';
            el.style.width = rect.w + 'px';
            el.style.height = rect.h + 'px';
            el.title = visual.label || visual.id;

            var img = document.createElement('img');
            img.className = 'preview-scene-node-image';
            img.alt = '';
            img.src = resolveAssetPath(visual.assetUrl);
            el.appendChild(img);

            var glow = document.createElement('span');
            glow.className = 'preview-scene-node-glow';
            el.appendChild(glow);

            if (_state.showLabels) {
                var tag = document.createElement('span');
                tag.className = 'preview-tag';
                tag.textContent = visual.label + ' [' + visual.id + ']';
                el.appendChild(tag);
            }

            _els.sceneLayer.appendChild(el);
        }
    }

    function countEnabledHotspots(hotspotIds, hotspotStates) {
        var count = 0;
        for (var i = 0; i < hotspotIds.length; i += 1) {
            var state = hotspotStates[hotspotIds[i]];
            if (!state || state.enabled) count += 1;
        }
        return count;
    }

    function containsHotspotId(hotspotIds, hotspotId) {
        return !!(hotspotId && hotspotIds && hotspotIds.indexOf(hotspotId) >= 0);
    }

    function resolveAssetPath(assetUrl) {
        if (!assetUrl) return '';
        if (/^(?:[a-z]+:|\/)/i.test(assetUrl)) return assetUrl;
        return '../../../' + assetUrl.replace(/^\.?\//, '');
    }

    function renderSourceRects(page, hotspots) {
        _els.sourceLayer.innerHTML = '';
        if (!_state.showSource) return;

        for (var i = 0; i < hotspots.length; i += 1) {
            var sourceRect = MapPanelData.getSourceRect(page.id, hotspots[i].id);
            if (!sourceRect) continue;

            var audit = computeAudit(page.id, hotspots[i].id, getRenderRect(page.id, hotspots[i]));
            var el = document.createElement('div');
            el.className = 'preview-source-rect is-' + audit.status;
            el.style.left = sourceRect.x + 'px';
            el.style.top = sourceRect.y + 'px';
            el.style.width = sourceRect.w + 'px';
            el.style.height = sourceRect.h + 'px';
            el.title = hotspots[i].id + ' sourceRect';

            if (_state.showLabels) {
                var tag = document.createElement('span');
                tag.className = 'preview-tag preview-source-tag';
                tag.textContent = hotspots[i].id + ' source [' + audit.status + ']';
                el.appendChild(tag);
            }

            _els.sourceLayer.appendChild(el);
        }

        renderAvatarSourceSlots(page);
    }

    function renderAvatarSourceSlots(page) {
        if (!_state.showAvatars) return;

        var slots = page.staticAvatars || [];
        for (var i = 0; i < slots.length; i += 1) {
            var audit = computeAvatarAudit(slots[i]);
            if (!audit.sourceRect) continue;

            var el = document.createElement('div');
            el.className = 'preview-source-rect preview-avatar-source is-' + audit.status + (isSelected('avatar', slots[i].id) ? ' is-selected' : '');
            el.style.left = audit.sourceRect.x + 'px';
            el.style.top = audit.sourceRect.y + 'px';
            el.style.width = audit.sourceRect.w + 'px';
            el.style.height = audit.sourceRect.h + 'px';
            el.title = slots[i].id + ' avatar source [' + audit.status + ']';

            if (_state.showLabels) {
                var tag = document.createElement('span');
                tag.className = 'preview-tag preview-source-tag';
                tag.textContent = slots[i].label + ' avatar [' + audit.status + ']';
                el.appendChild(tag);
            }

            _els.sourceLayer.appendChild(el);
        }
    }

    function renderHotspots(hotspots, hotspotStates, activeViewMode, currentHotspotId, focusHotspotId) {
        _els.hotspotLayer.innerHTML = '';
        if (!_state.showHotspots) return;

        for (var i = 0; i < hotspots.length; i += 1) {
            var hotspot = hotspots[i];
            var rect = getRenderRect(_state.pageId, hotspot);
            var hotspotState = hotspotStates[hotspot.id] || { enabled: true, lockedReason: '' };
            var audit = computeAudit(_state.pageId, hotspot.id, rect);
            var isCurrent = currentHotspotId === hotspot.id;
            var isFocused = focusHotspotId === hotspot.id;
            var isMuted = !!focusHotspotId && !isFocused;
            var el = document.createElement('button');
            el.className = 'preview-hotspot is-' + audit.status
                + (isSelected('hotspot', hotspot.id) ? ' is-selected' : '')
                + (hotspotState.enabled ? '' : ' is-locked')
                + (isCurrent ? ' is-current' : '')
                + (isMuted ? ' is-muted' : '')
                + (activeViewMode === 'hierarchy' ? ' is-relation' : '')
                + (_state.mode === 'builder' ? ' is-builder' : '');
            el.type = 'button';
            el.style.left = rect.x + 'px';
            el.style.top = rect.y + 'px';
            el.style.width = rect.w + 'px';
            el.style.height = rect.h + 'px';
            el.title = hotspot.id + ' -> ' + hotspot.sceneName + ' [' + audit.status + ' dx=' + audit.dx + ', dy=' + audit.dy + ']' + (hotspotState.enabled ? '' : (' / ' + hotspotState.lockedReason));
            el.addEventListener('click', makeHotspotHandler(hotspot.id));
            addBuilderHandle(el, 'hotspot', hotspot.id, hotspot.label);

            if (_state.showLabels) {
                var tag = document.createElement('span');
                tag.className = 'preview-tag';
                tag.textContent = hotspot.label + ' [' + hotspot.id + ']';
                el.appendChild(tag);
            }

            _els.hotspotLayer.appendChild(el);
        }
    }

    function makeHotspotHandler(hotspotId) {
        return function() {
            selectTarget('hotspot', hotspotId);
            render();
        };
    }

    function renderFilterButtons(page, activeFilter, unlocks) {
        _els.filterLayer.innerHTML = '';
        if (!_state.showButtons) return;

        var filters = page.filters || [];
        for (var i = 0; i < filters.length; i += 1) {
            if (!filters[i].buttonRect) continue;

            var rect = getRenderFilterRect(page.id, filters[i]);
            var unlockGroup = MapPanelData.getFilterUnlockGroup(page.id, filters[i].id);
            var meta = MapPanelData.getUnlockGroupMeta(unlockGroup);
            var isLocked = !!(meta && !unlocks[unlockGroup]);
            var btn = document.createElement('button');
            btn.className = 'preview-filter-button' + (activeFilter && activeFilter.id === filters[i].id ? ' is-active' : '') + (isSelected('filter', filters[i].id) ? ' is-selected' : '') + (isLocked ? ' is-locked' : '') + (_state.mode === 'builder' ? ' is-builder' : '');
            btn.type = 'button';
            btn.style.left = rect.x + 'px';
            btn.style.top = rect.y + 'px';
            btn.style.width = rect.w + 'px';
            btn.style.height = rect.h + 'px';
            btn.title = filters[i].id + (isLocked && meta ? (' / ' + meta.lockedReason) : '');
            btn.addEventListener('click', makeFilterHandler(filters[i].id));
            addBuilderHandle(btn, 'filter', filters[i].id, filters[i].label);

            if (_state.showLabels) {
                var tag = document.createElement('span');
                tag.className = 'preview-tag';
                tag.textContent = filters[i].label + ' [' + filters[i].id + ']';
                btn.appendChild(tag);
            }

            _els.filterLayer.appendChild(btn);
        }
    }

    function renderHints(page, unlocks) {
        _els.hintLayer.innerHTML = '';
        if (!_state.showHints) return;

        var hints = MapPanelData.getPageFlashHints(page.id);
        for (var i = 0; i < hints.length; i += 1) {
            if (MapPanelData.evaluateCondition(unlocks, hints[i].conditionId) !== !!hints[i].whenValue) continue;

            var filter = MapPanelData.findFilter(page.id, hints[i].filterId);
            if (!filter || !filter.buttonRect) continue;

            var el = document.createElement('div');
            el.className = 'preview-hint';
            el.style.left = (filter.buttonRect.x + (filter.buttonRect.w / 2)) + 'px';
            el.style.top = (filter.buttonRect.y + 8) + 'px';
            el.textContent = hints[i].label || hints[i].id;
            _els.hintLayer.appendChild(el);
        }
    }

    function makeFilterHandler(filterId) {
        return function() {
            _state.filterId = filterId;
            selectTarget('filter', filterId);
            render();
        };
    }

    function addBuilderHandle(el, kind, id, label) {
        if (_state.mode !== 'builder' || !el) return;

        el.addEventListener('mousedown', function(event) {
            if (event.button !== 0) return;
            startDrag(kind, id, 'move', event);
        });

        var handle = document.createElement('span');
        handle.className = 'preview-resize-handle';
        handle.title = 'resize ' + label + ' [' + id + ']';
        handle.addEventListener('mousedown', function(event) {
            if (event.button !== 0) return;
            event.stopPropagation();
            startDrag(kind, id, 'resize', event);
        });
        el.appendChild(handle);
    }

    function startDrag(kind, id, mode, event) {
        stopDrag();
        var rect = getSelectedRect(kind, _state.pageId, id);
        if (!rect) return;
        event.preventDefault();
        selectTarget(kind, id);
        _state.drag = {
            kind: kind,
            id: id,
            mode: mode,
            origin: toStagePoint(event),
            rect: cloneRect(rect)
        };
        document.addEventListener('mousemove', onDragMove);
        document.addEventListener('mouseup', stopDrag);
        render();
    }

    function onDragMove(event) {
        if (!_state.drag) return;

        var point = toStagePoint(event);
        var step = normalizeStep(_state.step);
        var dx = snapToStep(point.x - _state.drag.origin.x, step);
        var dy = snapToStep(point.y - _state.drag.origin.y, step);
        var rect = cloneRect(_state.drag.rect);

        if (_state.drag.mode === 'resize') {
            rect.w = Math.max(1, snapToStep(_state.drag.rect.w + dx, step));
            rect.h = Math.max(1, snapToStep(_state.drag.rect.h + dy, step));
        } else {
            rect.x = snapToStep(_state.drag.rect.x + dx, step);
            rect.y = snapToStep(_state.drag.rect.y + dy, step);
        }

        setDraftRect(_state.drag.kind, _state.pageId, _state.drag.id, rect);
        render();
    }

    function stopDrag() {
        if (!_state.drag) return;
        _state.drag = null;
        document.removeEventListener('mousemove', onDragMove);
        document.removeEventListener('mouseup', stopDrag);
    }

    function toStagePoint(event) {
        var stageRect = _els.stage.getBoundingClientRect();
        var scaleX = stageRect.width / Math.max(1, _els.stage.offsetWidth);
        var scaleY = stageRect.height / Math.max(1, _els.stage.offsetHeight);
        return {
            x: round((event.clientX - stageRect.left) / scaleX),
            y: round((event.clientY - stageRect.top) / scaleY)
        };
    }

    function getSelectedRect(kind, pageId, id) {
        if (kind === 'filter') {
            var filter = MapPanelData.findFilter(pageId, id);
            return getRenderFilterRect(pageId, filter);
        }
        if (kind === 'avatar') {
            return getAvatarRenderRect(pageId, id);
        }
        return getRenderRect(pageId, MapPanelData.findHotspot(pageId, id));
    }

    function renderAvatars(page, currentHotspotId, focusHotspotId) {
        _els.avatarLayer.innerHTML = '';
        if (!_state.showAvatars) return;

        renderStaticAvatars(page, currentHotspotId, focusHotspotId);
        renderDynamicAvatars(page, currentHotspotId, focusHotspotId);
    }

    function getAvatarRenderRect(pageId, avatarId) {
        var page = MapPanelData.getPage(pageId);
        var slots = (page.staticAvatars || []).concat(page.dynamicAvatars || []);
        var i;
        for (i = 0; i < slots.length; i += 1) {
            if (slots[i].id === avatarId) {
                if (page.staticAvatars && i < page.staticAvatars.length) {
                    return getAvatarDisplayRect(slots[i]);
                }
                return { x: slots[i].x, y: slots[i].y, w: slots[i].w, h: slots[i].h };
            }
        }
        return null;
    }

    function appendAvatarImage(el, assetUrl, fallbackAlt) {
        var img = document.createElement('img');
        img.alt = fallbackAlt || '';
        img.src = resolveAssetPath(assetUrl);
        el.appendChild(img);
    }

    function renderStaticAvatars(page, currentHotspotId, focusHotspotId) {
        var slots = page.staticAvatars || [];
        for (var i = 0; i < slots.length; i += 1) {
            var slot = slots[i];
            var audit = computeAvatarAudit(slot);
            var isCurrent = !!slot.hotspotId && slot.hotspotId === currentHotspotId;
            var isFocus = !!slot.hotspotId && slot.hotspotId === focusHotspotId;
            var isMuted = !!focusHotspotId && !!slot.hotspotId && slot.hotspotId !== focusHotspotId;
            var rect = getAvatarDisplayRect(slot);
            var el = document.createElement('button');
            el.className = 'preview-avatar-slot preview-avatar-slot--static'
                + (isSelected('avatar', slot.id) ? ' is-selected' : '')
                + (isCurrent ? ' is-current' : '')
                + (isFocus ? ' is-focus' : '')
                + (isMuted ? ' is-muted' : '')
                + ' is-' + audit.status;
            el.type = 'button';
            el.style.left = rect.x + 'px';
            el.style.top = rect.y + 'px';
            el.style.width = rect.w + 'px';
            el.style.height = rect.h + 'px';
            el.title = slot.id + ' -> ' + slot.hotspotId + ' [' + audit.status + ']';
            el.addEventListener('click', makeAvatarHandler(slot.id));
            appendAvatarImage(el, slot.assetUrl, slot.label || slot.id);

            if (_state.showLabels) {
                var tag = document.createElement('span');
                tag.className = 'preview-tag';
                tag.textContent = slot.label + ' [' + slot.id + ']';
                el.appendChild(tag);
            }

            _els.avatarLayer.appendChild(el);
        }
    }

    function renderDynamicAvatars(page, currentHotspotId, focusHotspotId) {
        var slots = page.dynamicAvatars || [];
        for (var i = 0; i < slots.length; i += 1) {
            var slot = slots[i];
            var el = document.createElement('button');
            var isCurrent = !!slot.hotspotId && slot.hotspotId === currentHotspotId;
            var isFocus = !!slot.hotspotId && slot.hotspotId === focusHotspotId;
            var isMuted = !!focusHotspotId && !!slot.hotspotId && slot.hotspotId !== focusHotspotId;
            el.className = 'preview-avatar-slot preview-avatar-slot--dynamic'
                + (isSelected('avatar', slot.id) ? ' is-selected' : '')
                + (isCurrent ? ' is-current' : '')
                + (isFocus ? ' is-focus' : '')
                + (isMuted ? ' is-muted' : '');
            el.type = 'button';
            el.style.left = slot.x + 'px';
            el.style.top = slot.y + 'px';
            el.style.width = slot.w + 'px';
            el.style.height = slot.h + 'px';
            el.title = slot.id + ' -> ' + slot.hotspotId;
            el.addEventListener('click', makeAvatarHandler(slot.id));

            if (slot.kind === 'roommateGender') {
                appendAvatarImage(
                    el,
                    _state.roommateGender === 'female'
                        ? 'assets/map/roommate-female.png'
                        : 'assets/map/roommate-male.png',
                    slot.kind
                );
            }

            if (_state.showLabels) {
                var tag = document.createElement('span');
                tag.className = 'preview-tag';
                tag.textContent = slot.id + ' [' + slot.kind + ']';
                el.appendChild(tag);
            }

            _els.avatarLayer.appendChild(el);
        }
    }

    function makeAvatarHandler(avatarId) {
        return function() {
            selectTarget('avatar', avatarId);
            render();
        };
    }

    function buildPageAudit(pageId) {
        var page = MapPanelData.getPage(pageId);
        var filter = resolveAuditFilter(page);
        var visibleHotspots = getVisibleHotspots(page, filter);
        var hotspotRows = [];
        var avatarRows = [];
        var i;

        for (i = 0; i < visibleHotspots.length; i += 1) {
            var hotspot = visibleHotspots[i];
            var renderRect = getRenderRect(page.id, hotspot);
            var audit = computeAudit(page.id, hotspot.id, renderRect);
            var componentAudit = computeComponentAudit(page, hotspot.id, renderRect);
            hotspotRows.push({
                id: hotspot.id,
                label: hotspot.label,
                status: audit.status,
                note: audit.note,
                delta: {
                    dx: audit.dx,
                    dy: audit.dy
                },
                sourceRect: cloneSourceRect(audit.sourceRect),
                currentRect: cloneSourceRect(renderRect),
                componentRect: cloneSourceRect(componentAudit.componentRect),
                boxVsComponent: componentAudit.boxVsComponent,
                boxVsComponentIou: componentAudit.boxVsComponentIou
            });
        }

        var staticAvatars = page.staticAvatars || [];
        for (i = 0; i < staticAvatars.length; i += 1) {
            var avatarAudit = computeAvatarAudit(staticAvatars[i]);
            avatarRows.push({
                id: staticAvatars[i].id,
                label: staticAvatars[i].label,
                hotspotId: staticAvatars[i].hotspotId || '',
                status: avatarAudit.status,
                note: avatarAudit.note,
                sourceRect: cloneSourceRect(avatarAudit.sourceRect),
                currentRect: cloneSourceRect(getAvatarDisplayRect(staticAvatars[i])),
                delta: avatarAudit.delta,
                symbolName: avatarAudit.sourceSlot ? avatarAudit.sourceSlot.symbolName : '',
                crop: avatarAudit.sourceSlot ? avatarAudit.sourceSlot.crop || null : null
            });
        }

        return {
            pageId: page.id,
            filterId: filter ? filter.id : null,
            hotspotRows: hotspotRows,
            avatarRows: avatarRows
        };
    }

    function buildAuditExport() {
        var pageIds = MapPanelData.getPageOrder();
        var pages = {};
        var i;

        for (i = 0; i < pageIds.length; i += 1) {
            pages[pageIds[i]] = buildPageAudit(pageIds[i]);
        }

        return {
            version: 1,
            pageOrder: pageIds.slice(),
            pages: pages
        };
    }

    function renderAudit(page, visibleHotspots) {
        if (!_els.audit) return;

        var audit = buildPageAudit(page.id);
        var hotspotCounts = { exact: 0, near: 0, hand_tuned: 0, review: 0, missing: 0 };
        var avatarCounts = { exact: 0, near: 0, review: 0, missing: 0 };
        var lines = [];
        var i;

        for (i = 0; i < audit.hotspotRows.length; i += 1) {
            hotspotCounts[audit.hotspotRows[i].status] += 1;
        }
        for (i = 0; i < audit.avatarRows.length; i += 1) {
            if (!(audit.avatarRows[i].status in avatarCounts)) {
                avatarCounts[audit.avatarRows[i].status] = 0;
            }
            avatarCounts[audit.avatarRows[i].status] += 1;
        }

        lines.push('hotspots');
        lines.push(JSON.stringify(hotspotCounts));
        lines.push('avatars');
        lines.push(JSON.stringify(avatarCounts));
        lines.push('');
        lines.push('review hotspots');
        for (i = 0; i < audit.hotspotRows.length; i += 1) {
            if (audit.hotspotRows[i].status === 'review' || audit.hotspotRows[i].status === 'missing') {
                lines.push(
                    audit.hotspotRows[i].id
                    + ' dx=' + (audit.hotspotRows[i].delta ? audit.hotspotRows[i].delta.dx : 'n/a')
                    + ' dy=' + (audit.hotspotRows[i].delta ? audit.hotspotRows[i].delta.dy : 'n/a')
                    + ' iou=' + (audit.hotspotRows[i].boxVsComponentIou == null ? 'n/a' : audit.hotspotRows[i].boxVsComponentIou)
                );
            }
        }
        lines.push('');
        lines.push('review avatars');
        for (i = 0; i < audit.avatarRows.length; i += 1) {
            if (audit.avatarRows[i].status === 'review' || audit.avatarRows[i].status === 'missing') {
                lines.push(
                    audit.avatarRows[i].id
                    + ' dx=' + (audit.avatarRows[i].delta ? audit.avatarRows[i].delta.dx : 'n/a')
                    + ' dy=' + (audit.avatarRows[i].delta ? audit.avatarRows[i].delta.dy : 'n/a')
                );
            }
        }

        _els.audit.textContent = lines.join('\n');
    }

    function renderSummary(page, filter, visibleHotspots, hotspotStates, activeViewMode, currentHotspotId, focusHotspotId) {
        var lockedCount = 0;
        var auditCounts = { exact: 0, near: 0, hand_tuned: 0, review: 0, missing: 0 };
        var avatarAuditCounts = { exact: 0, near: 0, review: 0, missing: 0 };
        for (var i = 0; i < visibleHotspots.length; i += 1) {
            if (hotspotStates[visibleHotspots[i].id] && !hotspotStates[visibleHotspots[i].id].enabled) {
                lockedCount += 1;
            }
            var audit = computeAudit(page.id, visibleHotspots[i].id, getRenderRect(page.id, visibleHotspots[i]));
            auditCounts[audit.status] += 1;
        }
        var staticAvatars = page.staticAvatars || [];
        for (i = 0; i < staticAvatars.length; i += 1) {
            var avatarAudit = computeAvatarAudit(staticAvatars[i]);
            if (!(avatarAudit.status in avatarAuditCounts)) {
                avatarAuditCounts[avatarAudit.status] = 0;
            }
            avatarAuditCounts[avatarAudit.status] += 1;
        }

        var summary = [
            'manifest: ' + MapManifest.id + ' v' + MapManifest.version,
            'page: ' + page.id + ' (' + page.width + 'x' + page.height + ')',
            'renderMode: ' + (page.renderMode || 'background') + ' / sceneVisuals=' + ((page.sceneVisuals || []).length),
            'filter: ' + (filter ? filter.id : 'none'),
            'viewMode: ' + activeViewMode + ' / current=' + (currentHotspotId || 'none') + ' / focus=' + (focusHotspotId || 'none'),
            'visible hotspots: ' + visibleHotspots.length + ' / ' + (page.hotspots || []).length,
            'locked visible hotspots: ' + lockedCount,
            'audit visible: exact=' + auditCounts.exact + ', near=' + auditCounts.near + ', hand=' + auditCounts.hand_tuned + ', review=' + auditCounts.review + ', missing=' + auditCounts.missing,
            'static avatars: ' + staticAvatars.length + ' / audit exact=' + avatarAuditCounts.exact + ', near=' + avatarAuditCounts.near + ', review=' + avatarAuditCounts.review + ', missing=' + avatarAuditCounts.missing,
            'locked groups: ' + (_state.lockedGroups.length ? _state.lockedGroups.join(',') : 'none'),
            'dynamic avatars: ' + ((page.dynamicAvatars || []).length),
            'draft hotspot overrides: ' + Object.keys(getPageDraftOverrides(page.id)).length,
            'draft filter overrides: ' + Object.keys(getPageDraftFilterOverrides(page.id)).length,
            'mode: ' + _state.mode,
            'viewport: ' + _state.viewport + (_state.fit ? ' (fit)' : ' (native)')
        ];
        _els.summary.textContent = summary.join('\n');
    }

    function renderSelection(page, filter, hotspotStates, activeViewMode, currentHotspotId, focusHotspotId) {
        var lines = [
            'pageAlias: ' + MapPanelData.resolvePageId(page.id),
            'active filter: ' + (filter ? filter.id : 'none'),
            'viewMode: ' + activeViewMode,
            'current hotspot: ' + (currentHotspotId || 'none'),
            'focus hotspot: ' + (focusHotspotId || 'none'),
            'mode: ' + _state.mode
        ];

        if (_state.selectedTargetKind === 'hotspot' && _state.selectedTargetId) {
            var hotspot = MapPanelData.findHotspot(page.id, _state.selectedTargetId);
            var exportedHotspot = hotspot ? findExportedHotspot(buildCalibratedPageExport(page.id), hotspot.id) : null;
            if (hotspot) {
                var sourceRect = MapPanelData.getSourceRect(page.id, hotspot.id);
                var renderRect = getRenderRect(page.id, hotspot);
                var audit = computeAudit(page.id, hotspot.id, renderRect);
                lines.push('selected hotspot: ' + hotspot.id);
                lines.push('scene: ' + hotspot.sceneName);
                lines.push('base rect: x=' + hotspot.rect.x + ', y=' + hotspot.rect.y + ', w=' + hotspot.rect.w + ', h=' + hotspot.rect.h);
                lines.push('current rect: x=' + renderRect.x + ', y=' + renderRect.y + ', w=' + renderRect.w + ', h=' + renderRect.h);
                if (sourceRect) {
                    lines.push('source rect: x=' + sourceRect.x + ', y=' + sourceRect.y + ', w=' + sourceRect.w + ', h=' + sourceRect.h);
                } else {
                    lines.push('source rect: missing');
                }
                var componentAudit = computeComponentAudit(page, hotspot.id, renderRect);
                if (componentAudit.componentRect) {
                    lines.push('component rect: x=' + componentAudit.componentRect.x + ', y=' + componentAudit.componentRect.y + ', w=' + componentAudit.componentRect.w + ', h=' + componentAudit.componentRect.h);
                    lines.push('box vs component: dx=' + componentAudit.boxVsComponent.centerDx + ', dy=' + componentAudit.boxVsComponent.centerDy + ', iou=' + componentAudit.boxVsComponentIou);
                }
                lines.push('audit: ' + audit.status + ' / ' + audit.note);
                lines.push('delta: dx=' + audit.dx + ', dy=' + audit.dy);
                if (hotspotStates[hotspot.id]) {
                    lines.push('enabled: ' + hotspotStates[hotspot.id].enabled);
                    lines.push('lockedReason: ' + (hotspotStates[hotspot.id].lockedReason || ''));
                }
                if (exportedHotspot) {
                    lines.push('target: ' + exportedHotspot.target.type + ' -> ' + exportedHotspot.target.sceneName);
                    lines.push('display.filterIds: ' + exportedHotspot.display.filterIds.join(','));
                    lines.push('display.when: ' + (exportedHotspot.display.when || []).join(','));
                }
            }
        } else if (_state.selectedTargetKind === 'filter' && _state.selectedTargetId) {
            var selectedFilter = MapPanelData.findFilter(page.id, _state.selectedTargetId);
            var currentRect = getRenderFilterRect(page.id, selectedFilter);
            if (selectedFilter && currentRect) {
                var unlockGroup = MapPanelData.getFilterUnlockGroup(page.id, selectedFilter.id);
                var meta = MapPanelData.getUnlockGroupMeta(unlockGroup);
                lines.push('selected filter: ' + selectedFilter.id);
                lines.push('label: ' + selectedFilter.label);
                lines.push('current rect: x=' + currentRect.x + ', y=' + currentRect.y + ', w=' + currentRect.w + ', h=' + currentRect.h);
                lines.push('buttonRect base: x=' + selectedFilter.buttonRect.x + ', y=' + selectedFilter.buttonRect.y + ', w=' + selectedFilter.buttonRect.w + ', h=' + selectedFilter.buttonRect.h);
                lines.push('unlockGroup: ' + (unlockGroup || 'none'));
                lines.push('lockedReason: ' + (meta ? meta.lockedReason : ''));
            }
        } else if (_state.selectedTargetKind === 'avatar' && _state.selectedTargetId) {
            var staticSlots = page.staticAvatars || [];
            for (var i = 0; i < staticSlots.length; i += 1) {
                if (staticSlots[i].id !== _state.selectedTargetId) continue;
                var avatarAudit = computeAvatarAudit(staticSlots[i]);
                lines.push('selected avatar: ' + staticSlots[i].id);
                lines.push('label: ' + staticSlots[i].label);
                lines.push('hotspot: ' + (staticSlots[i].hotspotId || ''));
                lines.push('data rect: x=' + staticSlots[i].x + ', y=' + staticSlots[i].y + ', w=' + staticSlots[i].w + ', h=' + staticSlots[i].h);
                var avatarRect = getAvatarDisplayRect(staticSlots[i]);
                lines.push('render rect: x=' + avatarRect.x + ', y=' + avatarRect.y + ', w=' + avatarRect.w + ', h=' + avatarRect.h);
                if (avatarAudit.sourceRect) {
                    lines.push('source rect: x=' + avatarAudit.sourceRect.x + ', y=' + avatarAudit.sourceRect.y + ', w=' + avatarAudit.sourceRect.w + ', h=' + avatarAudit.sourceRect.h);
                } else {
                    lines.push('source rect: missing');
                }
                if (avatarAudit.delta) {
                    lines.push('delta: dx=' + avatarAudit.delta.dx + ', dy=' + avatarAudit.delta.dy + ', dw=' + avatarAudit.delta.dw + ', dh=' + avatarAudit.delta.dh);
                }
                if (avatarAudit.sourceSlot && avatarAudit.sourceSlot.crop) {
                    lines.push('crop: scaleX=' + avatarAudit.sourceSlot.crop.scaleX + ', scaleY=' + avatarAudit.sourceSlot.crop.scaleY + ', tx=' + avatarAudit.sourceSlot.crop.tx + ', ty=' + avatarAudit.sourceSlot.crop.ty);
                }
                lines.push('audit: ' + avatarAudit.status + ' / ' + avatarAudit.note);
                break;
            }
        } else {
            lines.push('selected target: none');
        }

        _els.selection.textContent = lines.join('\n');
    }

    function renderDump(page, filter, visibleHotspots, hotspotStates, unlocks, activeViewMode, currentHotspotId, focusHotspotId) {
        var dump = buildCalibratedPageExport(page.id);
        dump.previewState = {
            filterId: filter ? filter.id : null,
            activeViewMode: activeViewMode,
            currentHotspotId: currentHotspotId || null,
            focusHotspotId: focusHotspotId || null,
            selectedTargetKind: _state.selectedTargetKind || null,
            selectedTargetId: _state.selectedTargetId || null,
            visibleHotspotIds: visibleHotspots.map(function(item) { return item.id; }),
            viewport: _state.viewport,
            roommateGender: _state.roommateGender,
            lockedGroups: _state.lockedGroups.slice(),
            showSource: _state.showSource,
            mode: _state.mode,
            step: _state.step,
            draftOverrides: getPageDraftOverrides(page.id),
            draftFilterOverrides: getPageDraftFilterOverrides(page.id),
            unlocks: unlocks,
            hotspotStates: hotspotStates
        };
        _els.dump.textContent = JSON.stringify(dump, null, 2);
    }

    function renderStatus(page, filter, visibleHotspots, activeViewMode, currentHotspotId, focusHotspotId) {
        var selectedHotspot = _state.selectedTargetKind === 'hotspot' && _state.selectedTargetId ? MapPanelData.findHotspot(page.id, _state.selectedTargetId) : null;
        var selectedAudit = _state.selectedTargetKind === 'hotspot' && _state.selectedTargetId
            ? computeAudit(page.id, _state.selectedTargetId, getRenderRect(page.id, selectedHotspot))
            : null;
        var selectedAvatarAudit = null;
        if (_state.selectedTargetKind === 'avatar' && _state.selectedTargetId) {
            var avatarSlots = page.staticAvatars || [];
            for (var i = 0; i < avatarSlots.length; i += 1) {
                if (avatarSlots[i].id === _state.selectedTargetId) {
                    selectedAvatarAudit = computeAvatarAudit(avatarSlots[i]);
                    break;
                }
            }
        }
        _els.status.textContent =
            'preview page=' + page.id +
            ', filter=' + (filter ? filter.id : 'none') +
            ', view=' + activeViewMode +
            ', current=' + (currentHotspotId || 'none') +
            ', focus=' + (focusHotspotId || 'none') +
            ', visible=' + visibleHotspots.length +
            ', hotspotTotal=' + (page.hotspots || []).length +
            ', avatarTotal=' + ((page.staticAvatars || []).length) +
            ', draftHotspots=' + Object.keys(getPageDraftOverrides(page.id)).length +
            ', draftFilters=' + Object.keys(getPageDraftFilterOverrides(page.id)).length +
            ', lockedGroups=' + (_state.lockedGroups.join('|') || 'none') +
            (_state.selectedTargetId ? (', selected=' + _state.selectedTargetKind + ':' + _state.selectedTargetId + (selectedAudit ? (':' + selectedAudit.status) : (selectedAvatarAudit ? (':' + selectedAvatarAudit.status) : ''))) : '');
    }

    function getPageDraftOverrides(pageId) {
        var page = MapPanelData.getPage(pageId);
        var hotspots = page.hotspots || [];
        var overrides = {};
        var i;

        for (i = 0; i < hotspots.length; i += 1) {
            var draft = getDraftRect(hotspots[i].id);
            if (draft && !sameRect(draft, hotspots[i].rect)) {
                overrides[hotspots[i].id] = roundRect(draft);
            }
        }

        return overrides;
    }

    function getPageDraftFilterOverrides(pageId) {
        var page = MapPanelData.getPage(pageId);
        var filters = page.filters || [];
        var overrides = {};
        var i;

        for (i = 0; i < filters.length; i += 1) {
            var draft = getDraftFilterRect(pageId, filters[i].id);
            if (draft && !sameRect(draft, filters[i].buttonRect)) {
                overrides[filters[i].id] = roundRect(draft);
            }
        }

        return overrides;
    }

    function buildPageOverridesBundle(pageId) {
        var overrides = getPageDraftOverrides(pageId);
        var filterOverrides = getPageDraftFilterOverrides(pageId);
        var bundle = {};
        bundle[pageId] = {
            hotspots: overrides,
            filters: filterOverrides
        };
        return bundle;
    }

    function buildCalibratedPageExport(pageId) {
        var page = MapPanelData.exportPage(pageId);
        var i;

        for (i = 0; i < page.hotspots.length; i += 1) {
            var draft = getDraftRect(page.hotspots[i].id);
            if (!draft) continue;
            page.hotspots[i].rect = roundRect(draft);
            page.hotspots[i].layoutAudit = computeAudit(page.id, page.hotspots[i].id, page.hotspots[i].rect);
        }

        for (i = 0; i < page.filters.length; i += 1) {
            var filterDraft = getDraftFilterRect(page.id, page.filters[i].id);
            if (!filterDraft) continue;
            page.filters[i].buttonRect = roundRect(filterDraft);
        }

        return page;
    }

    function buildCalibratedManifestExport() {
        var manifest = MapPanelData.exportManifest();
        var pageIds = manifest.pageOrder || [];
        var i;

        for (i = 0; i < pageIds.length; i += 1) {
            manifest.pages[pageIds[i]] = buildCalibratedPageExport(pageIds[i]);
        }

        return manifest;
    }

    function findExportedHotspot(pageExport, hotspotId) {
        var hotspots = pageExport && pageExport.hotspots ? pageExport.hotspots : [];
        var i;

        for (i = 0; i < hotspots.length; i += 1) {
            if (hotspots[i].id === hotspotId) {
                return hotspots[i];
            }
        }

        return null;
    }

    function resetSelectedRect() {
        if (!_state.selectedTargetId) return;
        if (_state.selectedTargetKind !== 'hotspot' && _state.selectedTargetKind !== 'filter') {
            _els.status.textContent = 'selected avatar is read-only';
            return;
        }
        removeDraftRect(_state.selectedTargetKind, _state.pageId, _state.selectedTargetId);
        render();
    }

    function snapSelectedToSource() {
        if (_state.selectedTargetKind !== 'hotspot' || !_state.selectedTargetId) return;
        var sourceRect = MapPanelData.getSourceRect(_state.pageId, _state.selectedTargetId);
        if (!sourceRect) {
            _els.status.textContent = 'selected hotspot has no source rect';
            return;
        }
        setDraftRect('hotspot', _state.pageId, _state.selectedTargetId, cloneRect(sourceRect));
        render();
    }

    function copySelectedOverride() {
        if (!_state.selectedTargetId) {
            _els.status.textContent = 'select a hotspot or filter first';
            return;
        }
        if (_state.selectedTargetKind !== 'hotspot' && _state.selectedTargetKind !== 'filter') {
            _els.status.textContent = 'selected avatar is read-only';
            return;
        }
        var rect = getSelectedRect(_state.selectedTargetKind, _state.pageId, _state.selectedTargetId);
        var bundle = {};
        bundle[_state.pageId] = { hotspots: {}, filters: {} };
        bundle[_state.pageId][_state.selectedTargetKind === 'filter' ? 'filters' : 'hotspots'][_state.selectedTargetId] = roundRect(rect);
        copyJson(bundle, 'copied selected override');
    }

    function applyCalibration(op) {
        if (!_state.selectedTargetId) {
            _els.status.textContent = 'select a hotspot or filter first';
            return;
        }
        if (_state.selectedTargetKind !== 'hotspot' && _state.selectedTargetKind !== 'filter') {
            _els.status.textContent = 'selected avatar is read-only';
            return;
        }

        var rect = getSelectedRect(_state.selectedTargetKind, _state.pageId, _state.selectedTargetId);
        if (!rect) return;
        var step = normalizeStep(_state.step);

        if (op === 'x-') rect.x -= step;
        if (op === 'x+') rect.x += step;
        if (op === 'y-') rect.y -= step;
        if (op === 'y+') rect.y += step;
        if (op === 'w-') rect.w = Math.max(1, rect.w - step);
        if (op === 'w+') rect.w += step;
        if (op === 'h-') rect.h = Math.max(1, rect.h - step);
        if (op === 'h+') rect.h += step;

        setDraftRect(_state.selectedTargetKind, _state.pageId, _state.selectedTargetId, rect);
        render();
    }

    function pasteOverrideBundle() {
        var input = window.prompt('Paste override JSON');
        if (!input) return;

        try {
            applyOverrideBundle(JSON.parse(input));
            render();
            _els.status.textContent = 'applied override bundle';
        } catch (err) {
            _els.status.textContent = 'invalid override bundle';
        }
    }

    function applyOverrideBundle(bundle) {
        var pageId;
        for (pageId in (bundle || {})) {
            if (!bundle.hasOwnProperty(pageId)) continue;
            var normalizedPageId = MapPanelData.resolvePageId(pageId);
            var pageBundle = bundle[pageId] || {};
            var hotspotBundle = isRectMap(pageBundle) ? pageBundle : (pageBundle.hotspots || {});
            var filterBundle = pageBundle.filters || {};
            var hotspotId;
            var filterId;

            for (hotspotId in hotspotBundle) {
                if (hotspotBundle.hasOwnProperty(hotspotId)) {
                    setDraftRect('hotspot', normalizedPageId, hotspotId, hotspotBundle[hotspotId]);
                }
            }

            for (filterId in filterBundle) {
                if (filterBundle.hasOwnProperty(filterId)) {
                    setDraftRect('filter', normalizedPageId, filterId, filterBundle[filterId]);
                }
            }
        }
    }

    function isRectMap(value) {
        var keys = Object.keys(value || {});
        if (!keys.length) return false;
        var first = value[keys[0]];
        return !!(first && typeof first.x === 'number' && typeof first.y === 'number' && typeof first.w === 'number' && typeof first.h === 'number');
    }

    function clearPageDrafts(pageId) {
        var page = MapPanelData.getPage(pageId);
        var hotspots = page.hotspots || [];
        var filters = page.filters || [];
        var i;

        for (i = 0; i < hotspots.length; i += 1) {
            delete _state.draftRects[hotspots[i].id];
        }
        delete _state.draftFilterRects[pageId];
        persistDraftState();
        clearSelection();
        render();
        _els.status.textContent = 'cleared drafts for ' + pageId;
    }

    function clearAllDrafts() {
        _state.draftRects = {};
        _state.draftFilterRects = {};
        persistDraftState();
        clearSelection();
        render();
        _els.status.textContent = 'cleared all drafts';
    }

    function copyJson(value, successText) {
        var text = JSON.stringify(value, null, 2);
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(function() {
                _els.status.textContent = successText;
            }, function() {
                _els.status.textContent = 'copy failed';
            });
            return;
        }

        var ta = document.createElement('textarea');
        ta.value = text;
        ta.setAttribute('readonly', 'readonly');
        ta.style.position = 'absolute';
        ta.style.left = '-9999px';
        document.body.appendChild(ta);
        ta.select();
        try {
            document.execCommand('copy');
            _els.status.textContent = successText;
        } catch (err) {
            _els.status.textContent = 'copy failed';
        }
        document.body.removeChild(ta);
    }

    function downloadJson(value, filename) {
        var blob = new Blob([JSON.stringify(value, null, 2)], { type: 'application/json' });
        var url = URL.createObjectURL(blob);
        var link = document.createElement('a');
        link.href = url;
        link.download = filename;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);
        _els.status.textContent = 'downloaded ' + filename;
    }

    window.addEventListener('load', init);

    return {
        init: init
    };
})();
