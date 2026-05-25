var MapSceneVisualLayer = (function() {
    'use strict';

    // ================================================================
    // 地图面板 sceneVisual DOM 层 (Phase 1B)
    //
    //   把每个 sceneVisual 渲染为一个 <div.map-scene-visual> wrapper, 含:
    //     <div.map-scene-visual-plate>   z=0  (仅 base 页 + is-visible 时显示)
    //     <img.map-scene-visual-img>     z=1  (PNG 资源)
    //     <div.map-scene-visual-glow>    z=2  (focus/current 时的发光层)
    //
    //   常态: visibility:hidden + opacity:0 (双控, 因为 display 不可过渡).
    //   syncState 根据 hover/current/filter/hierarchy 切换 .is-visible / .is-current / .is-focus.
    //
    //   状态规则 (与 canvas drawScene line 1116-1122 对齐):
    //     isCurrent = visual.hotspotIds ∩ currentHotspotId
    //     isHover   = visual.hotspotIds ∩ hoverHotspotId  OR  visual.hotspotIds 中有 busyLookup hit
    //     isFocus   = isCurrent || isHover
    //     inFilter  = !activeFilterId || visual.filterIds.includes(activeFilterId)
    //
    //     hierarchy 模式: 仅 isFocus + inFilter → visible (.is-current 或 .is-focus);
    //                     非 focus 由 canvas 画 muted 底图 (调用方靠 canvasSkipVisualIds
    //                     跳过 DOM 已显示的, 避免双绘 plate/glow).
    //     非 hierarchy:   同 hierarchy 的 visible 规则; 但 canvas 整层 drawScenes 跳过.
    //
    //   dimmer 规则 (Plan C 已退役):
    //     原方案: 非 hierarchy + hover → has-focus-dim → dimmer opacity 0.35 压暗 bg canvas.
    //     Plan C 改为 canvas 端 per-scene muted (alpha 0.42), 焦点对比由 canvas 本身提供;
    //     dimmer DOM 元素保留但永不激活 (CSS rule 与开关 toggle 都删除/不调用), 避免 anomaly 被一起压暗.
    //
    //   坐标契约:
    //     visual.rect (在 page 坐标系, 单位像素) → CSS left/top/width/height 用百分比
    //     转换公式 (与 hotspot toPercent 一致): pct = (v / pageDim * 100).toFixed(4) + '%'
    // ================================================================

    var _containerEl = null;
    var _dimmerEl = null;
    var _stageFrameEl = null;
    var _currentPageId = '';
    var _wrappers = [];        // [{ visualId, rect, hotspotIds, filterIds, el, plate, img, glow }]
    var _wrappersById = {};
    var _lastSyncResult = { domVisibleVisualIds: [] };
    var _resolveAssetUrl = null;

    function toPercent(value, total) {
        if (!total || !isFinite(total)) return '0%';
        return ((value / total) * 100).toFixed(4) + '%';
    }

    function ensureContainerCleared() {
        if (!_containerEl) return;
        // 清掉旧 wrappers 以及监听器 (img onload 已 fire-and-forget, 直接 remove)
        while (_containerEl.firstChild) {
            _containerEl.removeChild(_containerEl.firstChild);
        }
        _wrappers = [];
        _wrappersById = {};
    }

    function setResolveAssetUrl(fn) {
        _resolveAssetUrl = typeof fn === 'function' ? fn : null;
    }

    function buildWrapper(visual, page) {
        var rect = visual.rect || { x: 0, y: 0, w: 0, h: 0 };
        var hotspotIds = (visual.hotspotIds || []).slice();
        var filterIds = (visual.filterIds || []).slice();

        var el = document.createElement('div');
        el.className = 'map-scene-visual';
        el.setAttribute('data-visual-id', visual.id || '');
        el.setAttribute('data-hotspot-ids', hotspotIds.join(','));
        el.setAttribute('data-filter-ids', filterIds.join(','));
        el.style.left = toPercent(rect.x, page.width);
        el.style.top = toPercent(rect.y, page.height);
        el.style.width = toPercent(rect.w, page.width);
        el.style.height = toPercent(rect.h, page.height);

        var plate = document.createElement('div');
        plate.className = 'map-scene-visual-plate';
        plate.setAttribute('aria-hidden', 'true');

        var img = document.createElement('img');
        img.className = 'map-scene-visual-img';
        img.alt = '';
        img.draggable = false;
        img.decoding = 'async';
        // 预加载: 设置 src 让浏览器 fetch + decode, 不阻塞 syncPage
        // resolveAssetUrl 把 'assets/map/...' 解析到 /launcher/web/ 下绝对路径
        var resolved = (_resolveAssetUrl && visual.assetUrl)
            ? _resolveAssetUrl(visual.assetUrl)
            : (visual.assetUrl || '');
        if (resolved) img.src = resolved;

        var glow = document.createElement('div');
        glow.className = 'map-scene-visual-glow';
        glow.setAttribute('aria-hidden', 'true');

        el.appendChild(plate);
        el.appendChild(img);
        el.appendChild(glow);

        return {
            visualId: visual.id || '',
            rect: rect,
            hotspotIds: hotspotIds,
            filterIds: filterIds,
            el: el,
            plate: plate,
            img: img,
            glow: glow
        };
    }

    // 整页全部 sceneVisuals 一次性建 DOM (与 filter 无关).
    // filter 切换只改 syncState 里的 visible 计算, 不重建 DOM.
    function syncPage(page) {
        if (!_containerEl || !page) return;
        ensureContainerCleared();
        _currentPageId = page.id || '';

        var visuals = page.sceneVisuals || [];
        var frag = document.createDocumentFragment();
        for (var i = 0; i < visuals.length; i += 1) {
            var v = visuals[i];
            if (!v) continue;
            var wrapper = buildWrapper(v, page);
            _wrappers.push(wrapper);
            _wrappersById[wrapper.visualId] = wrapper;
            frag.appendChild(wrapper.el);
        }
        _containerEl.appendChild(frag);
        _lastSyncResult = { domVisibleVisualIds: [] };
    }

    function arrayHasAny(arr, set) {
        if (!arr || !set) return false;
        for (var i = 0; i < arr.length; i += 1) {
            if (set[arr[i]]) return true;
        }
        return false;
    }

    function arrayIncludes(arr, value) {
        if (!arr || !value) return false;
        for (var i = 0; i < arr.length; i += 1) {
            if (arr[i] === value) return true;
        }
        return false;
    }

    // args: {
    //   viewMode: 'hierarchy' | 'default',
    //   activeFilterId: string,
    //   currentHotspotId: string,
    //   hoverHotspotId: string,
    //   busyLookup: { hotspotId: true }
    // }
    function syncState(args) {
        args = args || {};
        var hierarchy = args.viewMode === 'hierarchy';
        var activeFilterId = args.activeFilterId || '';
        var currentHotspotId = args.currentHotspotId || '';
        var hoverHotspotId = args.hoverHotspotId || '';
        var busyLookup = args.busyLookup || {};

        var visibleVisualIds = [];
        var i;
        var w;
        var inFilter;
        var isCurrent;
        var isHover;
        var isFocus;
        var visible;

        for (i = 0; i < _wrappers.length; i += 1) {
            w = _wrappers[i];
            inFilter = !activeFilterId || arrayIncludes(w.filterIds, activeFilterId);
            isCurrent = !!currentHotspotId && arrayIncludes(w.hotspotIds, currentHotspotId);
            isHover = (!!hoverHotspotId && arrayIncludes(w.hotspotIds, hoverHotspotId))
                || arrayHasAny(w.hotspotIds, busyLookup);
            isFocus = isCurrent || isHover;

            visible = inFilter && isFocus;

            // 用 className 整体重写 (一次回流) 避免逐 toggle 多次属性写
            var cls = 'map-scene-visual';
            if (visible) {
                cls += ' is-visible';
                visibleVisualIds.push(w.visualId);
            }
            if (visible && isCurrent) cls += ' is-current';
            else if (visible && isHover) cls += ' is-focus';
            if (w.el.className !== cls) w.el.className = cls;
        }

        // Plan C: dimmer 已退役, 焦点压暗改由 canvas drawScene 的 per-scene muted (0.42/0.58/0.7) 完成.
        // 保留 hierarchy 变量声明给未来策略调整, 此处不再 toggle .has-focus-dim.
        void hierarchy;
        void hoverHotspotId;

        _lastSyncResult = { domVisibleVisualIds: visibleVisualIds };
        return _lastSyncResult;
    }

    function lastSyncResult() {
        return _lastSyncResult;
    }

    function mount(containerEl, dimmerEl, stageFrameEl, resolveAssetUrl) {
        if (containerEl) _containerEl = containerEl;
        if (dimmerEl) _dimmerEl = dimmerEl;
        if (stageFrameEl) _stageFrameEl = stageFrameEl;
        setResolveAssetUrl(resolveAssetUrl);
    }

    function destroy() {
        ensureContainerCleared();
        if (_stageFrameEl) _stageFrameEl.classList.remove('has-focus-dim');
        if (_dimmerEl) _dimmerEl.style.opacity = '';
        _currentPageId = '';
        _lastSyncResult = { domVisibleVisualIds: [] };
    }

    function debugState() {
        return {
            pageId: _currentPageId,
            visualCount: _wrappers.length,
            domVisibleCount: _lastSyncResult.domVisibleVisualIds.length,
            domVisibleVisualIds: _lastSyncResult.domVisibleVisualIds.slice(),
            hasDimmer: !!_dimmerEl,
            // Plan C: dimActive 永远 false (dimmer 已退役), 字段保留供向后兼容 ui32c
            dimActive: false
        };
    }

    return {
        mount: mount,
        destroy: destroy,
        syncPage: syncPage,
        syncState: syncState,
        lastSyncResult: lastSyncResult,
        debugState: debugState
    };
})();

if (typeof window !== 'undefined') {
    window.MapSceneVisualLayer = MapSceneVisualLayer;
}
