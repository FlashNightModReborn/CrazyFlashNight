var MapHud = (function() {
    'use strict';

    var SVG_NS = 'http://www.w3.org/2000/svg';
    var XLINK_NS = 'http://www.w3.org/1999/xlink';

    var _contextEl = null;
    var _rootEl = null;
    var _buttonEl = null;
    var _modeEl = null;
    var _outlineEl = null;
    var _labelEl = null;
    var _renderSeq = 0;
    var _state = {
        mode: '0',
        hotspotId: '',
        visible: false,
        renderable: false,
        collapsed: false
    };
    var _warned = {};

    function warnOnce(key, message) {
        if (_warned[key]) return;
        _warned[key] = true;
        console.warn(message);
    }

    function sanitizeMode(value) {
        value = String(value || '0');
        return /^(0|1|2|3)$/.test(value) ? value : '0';
    }

    function round(value) {
        return (Math.round((Number(value) || 0) * 100) / 100).toFixed(2);
    }

    function emitStateChange() {
        if (typeof document === 'undefined' || !document || typeof CustomEvent === 'undefined') return;
        document.dispatchEvent(new CustomEvent('maphudstatechange', {
            detail: {
                collapsed: !!_state.collapsed,
                available: !!_state.renderable,
                visible: !!_state.visible,
                mode: sanitizeMode(_state.mode)
            }
        }));
    }

    function reportRectSoon() {
        setTimeout(function() {
            if (typeof Notch !== 'undefined' && Notch && typeof Notch.reportRect === 'function') {
                Notch.reportRect();
            }
        }, 50);
    }

    function syncVisibleState() {
        var nextVisible = !!(_state.renderable && !_state.collapsed);
        if (!_rootEl) return;
        if (_state.visible === nextVisible) return;

        _state.visible = nextVisible;
        if (nextVisible) {
            _rootEl.style.display = '';
            _rootEl.classList.add('is-visible');
            if (_contextEl) _contextEl.classList.add('has-map');
        } else {
            _rootEl.classList.remove('is-visible');
            _rootEl.style.display = 'none';
            if (_contextEl) _contextEl.classList.remove('has-map');
        }
        reportRectSoon();
    }

    function setRenderable(nextRenderable) {
        _state.renderable = !!nextRenderable;
        syncVisibleState();
        emitStateChange();
    }

    function setCollapsed(nextCollapsed) {
        nextCollapsed = !!nextCollapsed;
        if (_state.collapsed === nextCollapsed) return;
        _state.collapsed = nextCollapsed;
        if (_rootEl) _rootEl.setAttribute('data-collapsed', nextCollapsed ? '1' : '0');
        syncVisibleState();
        emitStateChange();
    }

    function toggleCollapsed() {
        if (!_state.renderable) return false;
        setCollapsed(!_state.collapsed);
        return true;
    }

    function clearVisual() {
        if (_outlineEl) _outlineEl.innerHTML = '';
        if (_modeEl) _modeEl.innerHTML = '';
        if (_labelEl) _labelEl.textContent = '';
        if (_rootEl) {
            _rootEl.setAttribute('data-page-id', '');
            _rootEl.setAttribute('data-focus-filter-id', '');
            _rootEl.setAttribute('data-group', '');
            _rootEl.setAttribute('data-mode', '0');
        }
        if (_buttonEl) {
            _buttonEl.title = '打开地图';
            _buttonEl.setAttribute('aria-label', '打开地图');
        }
    }

    function openMapPanel() {
        if (typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') return;
        Bridge.send({ type: 'click', key: 'TASK_MAP' });
    }

    function createSvgNode(tagName, attrs) {
        var el = document.createElementNS(SVG_NS, tagName);
        var key;
        attrs = attrs || {};
        for (key in attrs) {
            if (attrs[key] == null) continue;
            if (key === 'href') {
                el.setAttributeNS(XLINK_NS, 'href', attrs[key]);
                el.setAttribute('href', attrs[key]);
                continue;
            }
            el.setAttribute(key, attrs[key]);
        }
        return el;
    }

    function buildModeIcon(mode) {
        var svg = createSvgNode('svg', {
            'class': 'map-hud-mode-icon',
            'viewBox': '0 0 16 16',
            'focusable': 'false',
            'aria-hidden': 'true'
        });

        if (mode === '1') {
            svg.appendChild(createSvgNode('path', {
                'd': 'M3 7.1L8 3l5 4.1v5H9.7v-3H6.3v3H3z',
                'fill': 'none',
                'stroke': 'currentColor',
                'stroke-width': '1.5',
                'stroke-linejoin': 'round'
            }));
            return svg;
        }

        svg.appendChild(createSvgNode('circle', {
            'cx': '4',
            'cy': '4',
            'r': '1.5',
            'fill': 'currentColor'
        }));
        svg.appendChild(createSvgNode('circle', {
            'cx': '12',
            'cy': '5',
            'r': '1.5',
            'fill': 'currentColor'
        }));
        svg.appendChild(createSvgNode('circle', {
            'cx': '6',
            'cy': '12',
            'r': '1.5',
            'fill': 'currentColor'
        }));
        svg.appendChild(createSvgNode('polyline', {
            'points': '4,4 12,5 6,12',
            'fill': 'none',
            'stroke': 'currentColor',
            'stroke-width': '1.4',
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round'
        }));
        return svg;
    }

    function buildFallbackRectLayer(blocks, currentHotspotId) {
        var group = createSvgNode('g', { 'class': 'map-hud-svg-fallbacks' });
        var i;
        var block;
        var rect;
        var radius;

        blocks = blocks || [];

        for (i = 0; i < blocks.length; i++) {
            block = blocks[i];
            rect = block && block.sourceRect ? block.sourceRect : null;
            if (!rect) continue;

            radius = Math.max(6, Math.min(12, Math.min(rect.w, rect.h) * 0.12));
            group.appendChild(createSvgNode('rect', {
                'class': 'map-hud-svg-fallback-block' + (block.hotspotId === currentHotspotId ? ' is-current' : ''),
                'x': round(rect.x),
                'y': round(rect.y),
                'width': round(rect.w),
                'height': round(rect.h),
                'rx': round(radius),
                'ry': round(radius)
            }));
        }

        return group;
    }

    function buildVisualMask(defsEl, visual, maskId) {
        var mask = createSvgNode('mask', {
            'id': maskId,
            'maskUnits': 'userSpaceOnUse',
            'maskContentUnits': 'userSpaceOnUse',
            'mask-type': 'alpha',
            'style': 'mask-type:alpha',
            'x': round(visual.sourceRect.x),
            'y': round(visual.sourceRect.y),
            'width': round(visual.sourceRect.w),
            'height': round(visual.sourceRect.h)
        });

        mask.appendChild(createSvgNode('image', {
            'href': visual.assetUrl,
            'x': round(visual.sourceRect.x),
            'y': round(visual.sourceRect.y),
            'width': round(visual.sourceRect.w),
            'height': round(visual.sourceRect.h),
            'preserveAspectRatio': 'none'
        }));

        defsEl.appendChild(mask);
    }

    function buildSvg(outline, currentHotspotId) {
        var viewport = outline && outline.viewportRect ? outline.viewportRect : null;
        var blocks = outline && outline.blocks ? outline.blocks : [];
        var visuals = outline && outline.visuals ? outline.visuals : [];
        var currentRect = outline && outline.currentRect ? outline.currentRect : null;
        var svg;
        var defs;
        var silhouetteGroup;
        var currentGroup;
        var beaconGroup;
        var i;
        var visual;
        var maskId;
        var centerX;
        var centerY;

        if (!viewport || (!blocks.length && !visuals.length)) return null;

        svg = createSvgNode('svg', {
            'class': 'map-hud-svg',
            'viewBox': [
                round(viewport.x),
                round(viewport.y),
                round(viewport.w),
                round(viewport.h)
            ].join(' '),
            'preserveAspectRatio': 'xMidYMid meet',
            'focusable': 'false',
            'aria-hidden': 'true'
        });

        if (visuals.length) {
            defs = createSvgNode('defs');
            silhouetteGroup = createSvgNode('g', { 'class': 'map-hud-svg-silhouettes' });
            currentGroup = createSvgNode('g', { 'class': 'map-hud-svg-current-layer' });

            _renderSeq += 1;
            for (i = 0; i < visuals.length; i++) {
                visual = visuals[i];
                if (!visual || !visual.sourceRect || !visual.assetUrl) continue;

                maskId = 'map-hud-mask-' + _renderSeq + '-' + i;
                buildVisualMask(defs, visual, maskId);

                silhouetteGroup.appendChild(createSvgNode('rect', {
                    'class': 'map-hud-svg-silhouette',
                    'x': round(visual.sourceRect.x),
                    'y': round(visual.sourceRect.y),
                    'width': round(visual.sourceRect.w),
                    'height': round(visual.sourceRect.h),
                    'mask': 'url(#' + maskId + ')'
                }));

                if (visual.isCurrent) {
                    currentGroup.appendChild(createSvgNode('rect', {
                        'class': 'map-hud-svg-current-glow',
                        'x': round(visual.sourceRect.x),
                        'y': round(visual.sourceRect.y),
                        'width': round(visual.sourceRect.w),
                        'height': round(visual.sourceRect.h),
                        'mask': 'url(#' + maskId + ')'
                    }));
                    currentGroup.appendChild(createSvgNode('rect', {
                        'class': 'map-hud-svg-current',
                        'x': round(visual.sourceRect.x),
                        'y': round(visual.sourceRect.y),
                        'width': round(visual.sourceRect.w),
                        'height': round(visual.sourceRect.h),
                        'mask': 'url(#' + maskId + ')'
                    }));
                }
            }

            svg.appendChild(defs);
            svg.appendChild(silhouetteGroup);
            svg.appendChild(currentGroup);
        } else {
            svg.appendChild(buildFallbackRectLayer(blocks, currentHotspotId));
        }

        if (currentRect) {
            centerX = currentRect.x + (currentRect.w / 2);
            centerY = currentRect.y + (currentRect.h / 2);
            beaconGroup = createSvgNode('g', { 'class': 'map-hud-svg-beacon' });
            beaconGroup.appendChild(createSvgNode('circle', {
                'class': 'map-hud-svg-beacon-ring',
                'cx': round(centerX),
                'cy': round(centerY),
                'r': '7.2'
            }));
            beaconGroup.appendChild(createSvgNode('circle', {
                'class': 'map-hud-svg-beacon-core',
                'cx': round(centerX),
                'cy': round(centerY),
                'r': '3.3'
            }));
            svg.appendChild(beaconGroup);
        }

        return svg;
    }

    function render(meta, outline) {
        var renderMode = meta.pageId === 'base' ? '1' : '2';
        var pageText = renderMode === '1' ? '\u57fa\u5730' : '\u5916\u90e8';
        var titleText = meta.label || meta.pageLabel || '\u5f53\u524d\u4f4d\u7f6e';
        var svg = buildSvg(outline, meta.hotspotId);
        var groupId = (typeof MapPanelData !== 'undefined' && MapPanelData && typeof MapPanelData.getHotspotUnlockGroup === 'function')
            ? (MapPanelData.getHotspotUnlockGroup(meta.pageId, meta.hotspotId) || '')
            : '';
        // base \u7ec4\u5728 catalog \u4e2d\u65e0 unlockGroup\uff08\u8fd4\u56de\u7a7a\u4e32\uff09\uff0c\u89c6\u4f5c base \u7ec4\u4ee5\u4fbf\u67d3\u8272
        if (!groupId && meta.pageId === 'base') groupId = 'base';

        _rootEl.setAttribute('data-mode', renderMode);
        _rootEl.setAttribute('data-page-id', meta.pageId || '');
        _rootEl.setAttribute('data-focus-filter-id', outline.focusFilterId || '');
        _rootEl.setAttribute('data-group', groupId);
        _buttonEl.title = pageText + ' / ' + titleText + ' \u00b7 \u6253\u5f00\u5730\u56fe';
        _buttonEl.setAttribute('aria-label', pageText + ' / ' + titleText);

        _modeEl.innerHTML = '';
        _modeEl.appendChild(buildModeIcon(renderMode));
        _labelEl.textContent = titleText;
        _outlineEl.innerHTML = '';
        if (svg) _outlineEl.appendChild(svg);
    }

    function applyState() {
        var mode = sanitizeMode(_state.mode);
        var hotspotId = String(_state.hotspotId || '');
        var meta;
        var outline;

        if (!_rootEl || !_buttonEl || !_modeEl || !_outlineEl || !_labelEl || typeof MapPanelData === 'undefined') {
            warnOnce('map-hud-bootstrap', '[MapHud] MapPanelData unavailable; HUD stays hidden');
            return;
        }

        if (mode !== '1' && mode !== '2') {
            clearVisual();
            setRenderable(false);
            return;
        }

        if (!hotspotId) {
            warnOnce('map-hud-empty-hotspot', '[MapHud] missing mh for visible HUD mode');
            clearVisual();
            setRenderable(false);
            return;
        }

        meta = MapPanelData.resolveHotspotMeta(hotspotId);
        if (!meta) {
            warnOnce('map-hud-hotspot-' + hotspotId, '[MapHud] unresolved hotspotId=' + hotspotId);
            clearVisual();
            setRenderable(false);
            return;
        }

        outline = MapPanelData.getHudOutline(meta.pageId, meta.hotspotId);
        if (!outline || ((!outline.blocks || !outline.blocks.length) && (!outline.visuals || !outline.visuals.length))) {
            warnOnce('map-hud-page-' + meta.pageId, '[MapHud] no outline content for pageId=' + meta.pageId);
            clearVisual();
            setRenderable(false);
            return;
        }

        render(meta, outline);
        setRenderable(true);
    }

    function init() {
        if (_rootEl) return;
        _contextEl = document.getElementById('context-panel');
        _rootEl = document.getElementById('map-hud');
        _buttonEl = document.getElementById('map-hud-button');
        _modeEl = document.getElementById('map-hud-mode');
        _outlineEl = document.getElementById('map-hud-outline');
        _labelEl = document.getElementById('map-hud-label-text');
        if (!_rootEl || !_buttonEl || !_modeEl || !_outlineEl || !_labelEl) return;

        _buttonEl.addEventListener('click', openMapPanel);

        if (typeof UiData !== 'undefined' && UiData) {
            UiData.on('mm', function(value) {
                _state.mode = sanitizeMode(value);
                applyState();
            });
            UiData.on('mh', function(value) {
                _state.hotspotId = String(value || '');
                applyState();
            });
        }

        applyState();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    return {
        init: init,
        refresh: applyState,
        toggleCollapsed: toggleCollapsed,
        setCollapsed: setCollapsed,
        isCollapsed: function() { return !!_state.collapsed; },
        isAvailable: function() { return !!_state.renderable; }
    };
})();
