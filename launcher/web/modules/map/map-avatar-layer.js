var MapAvatarLayer = (function() {
    'use strict';

    // ================================================================
    // 地图面板头像 DOM 层 (Phase 2)
    //
    //   把静态 + 动态头像从 canvas drawAvatar 抽到 DOM:
    //     <div.map-avatar data-avatar-id data-kind data-hotspot-id data-fallback>
    //       <img.map-avatar-img>
    //
    //   常态: opacity:1; 套头像 box-shadow 还原 canvas 投影 + 环境辉光.
    //   focus/current: scale(1.04) + lift -1px + 加亮 box-shadow.
    //   muted: opacity:0.34 + filter saturate(0.65) brightness(0.72).
    //
    //   fallback: <img> 未加载时显示 `attr(data-fallback)` 的字符,
    //   加载成功 (onload) → img 加 .is-loaded → ::after fallback 隐藏.
    //
    //   状态规则 (与 canvas drawAvatar line 1313-1316 对齐):
    //     isCurrent = avatar.hotspotId === currentHotspotId
    //     isFocus   = avatar.hotspotId === currentHotspotId
    //               || avatar.hotspotId === focusHotspotId
    //     muted     = !isFocus && !!focusId && avatar.hotspotId && avatar.hotspotId !== focusHotspotId
    //   focusHotspotId 用 hoverHotspotId || currentHotspotId 派生 (调用方 getFocusHotspotId).
    //
    //   syncPage 触发: applyPage (切页 / dynamic state 变 / _avatarVisibility 变)
    //   syncState 触发: filter switch / hover / busy 切换
    //
    //   缓存策略: syncPage 内部用 fingerprint 防重建闪烁 — 同样 slots 不重建 DOM.
    // ================================================================

    var _containerEl = null;
    var _wrappers = [];           // [{ id, kind, hotspotId, rect, assetUrl, fallbackChar, el, img }]
    var _wrappersById = {};
    var _lastFingerprint = '';
    var _lastSyncResult = { staticVisibleCount: 0, dynamicVisibleCount: 0, dynamicAvatarUrls: [] };

    function toPercent(value, total) {
        if (!total || !isFinite(total)) return '0%';
        return ((value / total) * 100).toFixed(4) + '%';
    }

    function ensureContainerCleared() {
        if (!_containerEl) return;
        while (_containerEl.firstChild) _containerEl.removeChild(_containerEl.firstChild);
        _wrappers = [];
        _wrappersById = {};
    }

    function computeFingerprint(slots, pageId) {
        // 任一 slot 的 id/kind/assetUrl/hotspotId/rect 变化都触发 DOM 重建;
        // 同一 (pageId, slot set) 重复调用直接跳过, 避免 filter 切换 flicker.
        var parts = [pageId || ''];
        for (var i = 0; i < slots.length; i += 1) {
            var s = slots[i] || {};
            var r = s.rect || {};
            parts.push([
                s.id || '', s.kind || '', s.hotspotId || '', s.assetUrl || '',
                r.x || 0, r.y || 0, r.w || 0, r.h || 0
            ].join(':'));
        }
        return parts.join('|');
    }

    function buildWrapper(slot, page) {
        var rect = slot.rect;
        var el = document.createElement('div');
        el.className = 'map-avatar';
        el.setAttribute('data-avatar-id', slot.id || '');
        el.setAttribute('data-kind', slot.kind || 'static');
        el.setAttribute('data-hotspot-id', slot.hotspotId || '');
        el.setAttribute('data-fallback', slot.fallbackChar || '?');
        el.style.left = toPercent(rect.x, page.width);
        el.style.top = toPercent(rect.y, page.height);
        el.style.width = toPercent(rect.w, page.width);
        el.style.height = toPercent(rect.h, page.height);

        var img = document.createElement('img');
        img.className = 'map-avatar-img';
        img.alt = '';
        img.draggable = false;
        img.decoding = 'async';
        // load 成功才挂 .is-loaded → ::after fallback 隐藏 (CSS :has selector); 失败保持 fallback.
        img.addEventListener('load', function() { img.classList.add('is-loaded'); });
        img.addEventListener('error', function() { img.classList.remove('is-loaded'); });
        if (slot.assetUrl) img.src = slot.assetUrl;

        el.appendChild(img);
        return {
            id: slot.id || '',
            kind: slot.kind || 'static',
            hotspotId: slot.hotspotId || '',
            rect: rect,
            assetUrl: slot.assetUrl || '',
            el: el,
            img: img
        };
    }

    function syncPage(page, slots) {
        if (!_containerEl || !page) return;
        slots = slots || [];
        var fp = computeFingerprint(slots, page.id);
        if (fp === _lastFingerprint && _wrappers.length === slots.length) return;
        ensureContainerCleared();
        var frag = document.createDocumentFragment();
        for (var i = 0; i < slots.length; i += 1) {
            var wrapper = buildWrapper(slots[i], page);
            _wrappers.push(wrapper);
            _wrappersById[wrapper.id] = wrapper;
            frag.appendChild(wrapper.el);
        }
        _containerEl.appendChild(frag);
        _lastFingerprint = fp;
        _lastSyncResult = { staticVisibleCount: 0, dynamicVisibleCount: 0, dynamicAvatarUrls: [] };
    }

    // args: {
    //   visibleLookup: { hotspotId: true } (filter-derived),
    //   enabledLookup: { hotspotId: true },
    //   avatarVisibility: { avatarId: false } overrides,
    //   focusHotspotId, currentHotspotId, hoverHotspotId, busyLookup
    // }
    function syncState(args) {
        args = args || {};
        var visibleLookup = args.visibleLookup || null;
        var enabledLookup = args.enabledLookup || null;
        var avatarVisibility = args.avatarVisibility || {};
        var focusHotspotId = args.focusHotspotId || '';
        var currentHotspotId = args.currentHotspotId || '';

        var staticVisibleCount = 0;
        var dynamicVisibleCount = 0;
        var dynamicAvatarUrls = [];
        var i;
        var w;
        var visible;
        var isCurrent;
        var isFocus;
        var muted;

        for (i = 0; i < _wrappers.length; i += 1) {
            w = _wrappers[i];

            // 可见性: 与 buildCanvas[Static|Dynamic]Avatars 口径对齐
            visible = true;
            if (w.hotspotId) {
                if (visibleLookup && !visibleLookup[w.hotspotId]) visible = false;
                if (enabledLookup && !enabledLookup[w.hotspotId]) visible = false;
            }
            if (w.id && Object.prototype.hasOwnProperty.call(avatarVisibility, w.id)
                && avatarVisibility[w.id] === false) visible = false;
            if (!w.assetUrl) visible = false;

            // focus / muted: 与 canvas drawAvatar 一致
            isCurrent = !!w.hotspotId && w.hotspotId === currentHotspotId;
            isFocus = isCurrent
                || (!!w.hotspotId && !!focusHotspotId && w.hotspotId === focusHotspotId);
            muted = !isFocus && !!focusHotspotId && !!w.hotspotId && w.hotspotId !== focusHotspotId;

            var cls = 'map-avatar';
            if (visible) {
                cls += ' is-visible';
                if (w.kind === 'dynamic') {
                    dynamicVisibleCount += 1;
                    dynamicAvatarUrls.push(w.assetUrl);
                } else {
                    staticVisibleCount += 1;
                }
            } else {
                cls += ' is-hidden';
            }
            if (isCurrent) cls += ' is-current';
            else if (isFocus) cls += ' is-focus';
            if (muted) cls += ' is-muted';
            if (w.el.className !== cls) w.el.className = cls;
        }

        _lastSyncResult = {
            staticVisibleCount: staticVisibleCount,
            dynamicVisibleCount: dynamicVisibleCount,
            dynamicAvatarUrls: dynamicAvatarUrls
        };
        return _lastSyncResult;
    }

    function mount(containerEl) {
        if (containerEl) _containerEl = containerEl;
    }

    function destroy() {
        ensureContainerCleared();
        _lastFingerprint = '';
        _lastSyncResult = { staticVisibleCount: 0, dynamicVisibleCount: 0, dynamicAvatarUrls: [] };
    }

    function debugState() {
        return {
            slotCount: _wrappers.length,
            staticVisibleCount: _lastSyncResult.staticVisibleCount,
            dynamicVisibleCount: _lastSyncResult.dynamicVisibleCount,
            totalVisibleCount: _lastSyncResult.staticVisibleCount + _lastSyncResult.dynamicVisibleCount,
            dynamicAvatarUrls: _lastSyncResult.dynamicAvatarUrls.slice(),
            currentDynamicAvatarUrl: _lastSyncResult.dynamicAvatarUrls[0] || ''
        };
    }

    return {
        mount: mount,
        destroy: destroy,
        syncPage: syncPage,
        syncState: syncState,
        debugState: debugState
    };
})();

if (typeof window !== 'undefined') {
    window.MapAvatarLayer = MapAvatarLayer;
}
