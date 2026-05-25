var MapHotspotHitcapture = (function() {
    'use strict';

    // ================================================================
    // 地图面板 hotspot 像素级命中代理层
    //
    //   单个 DOM 节点 .map-hotspot-hitcapture (z=4, pointer-events:auto),
    //   覆盖整个 _contentFitEl, 是页面上唯一接收鼠标事件的 hotspot 命中层。
    //   .map-hotspot button 同时存在 (z=3) 但 pointer-events:none, 仅服务键盘 Tab / aria。
    //
    //   命中流程:
    //     pointermove(rAF 节流) → query 命中变化时切换 cursor + 调 onHover + 显式 playHover()
    //     pointerdown 命中+enabled+非busy → 临时设 data-audio-cue=transition + 记 pendingNavigateId
    //     pointerup → 重新 query release 坐标, 与 pointerdown 不匹配则 removeAttribute + 清 pendingNavigateId
    //     click → 若 pendingNavigateId 仍在则 onClick(id); 总是清理 attr / pending
    //     pointercancel / contextmenu / pointerleave → 全清理
    //
    //   音效路径 (v4 决策):
    //     - hover cue: 由本模块在 hit null→非null 时显式 BootstrapAudio.playHover() 调用,
    //       不依赖 overlay-audio-bindings.js 的 mouseover 代理 (那个代理要求 [data-audio-cue]
    //       属性常驻, 而本模块只在 pointerdown 命中期临时设属性)
    //     - click cue: 走 overlay-audio-bindings.js 的 click capture 代理 (透明转发 [data-audio-cue]),
    //       因 capture 比本模块 click bubble 早, 所以 pointerup 已经决定 attr 在不在
    //
    //   坐标契约:
    //     clientX/Y → page 坐标 = (clientX - rect.left) / rect.width * page.width
    //     避开依赖 _stageScale / _contentFitScale 直接读取 rect; 与 transform 解耦
    //     pageX/Y 传给 MapHittestEngine.query (内部 Math.round)
    // ================================================================

    var _el = null;
    var _callbacks = null;
    var _mounted = false;

    var _currentHover = null;          // 当前 hover hotspot id (或 null)
    var _pendingNavigateId = null;     // pointerdown 锁定的导航目标
    var _pendingFrame = 0;

    function getEngine() {
        return typeof MapHittestEngine !== 'undefined' ? MapHittestEngine : null;
    }

    function queryHotspot(clientX, clientY) {
        if (!_el || !_callbacks) return null;
        var rect = _el.getBoundingClientRect();
        if (!rect.width || !rect.height) return null;
        var pageId = _callbacks.getCurrentPageId ? _callbacks.getCurrentPageId() : '';
        if (!pageId) return null;
        var page = _callbacks.getCurrentPage ? _callbacks.getCurrentPage() : null;
        var pageW = (page && page.width) || 1031;
        var pageH = (page && page.height) || 608;
        var px = (clientX - rect.left) / rect.width * pageW;
        var py = (clientY - rect.top) / rect.height * pageH;

        var engine = getEngine();
        if (!engine) return null;
        var result = engine.query(pageId, px, py);
        if (!result) return null;

        var hotspotIds = result.hotspotIds || [];
        if (!hotspotIds.length) return null;

        var visible = _callbacks.getVisibleLookup ? _callbacks.getVisibleLookup() : null;
        var enabled = _callbacks.getEnabledLookup ? _callbacks.getEnabledLookup() : null;
        for (var i = 0; i < hotspotIds.length; i += 1) {
            var id = hotspotIds[i];
            if (visible && !visible[id]) continue;
            if (enabled && !enabled[id]) continue;
            return id;
        }
        return null;
    }

    function playHoverCue() {
        var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
        if (A && typeof A.playHover === 'function') A.playHover();
    }

    function setHover(hit) {
        if (hit === _currentHover) return;
        if (_currentHover && _callbacks && _callbacks.onHover) {
            _callbacks.onHover(_currentHover, false);
        }
        _currentHover = hit;
        if (hit) {
            if (_callbacks && _callbacks.onHover) _callbacks.onHover(hit, true);
            playHoverCue();
        }
    }

    function clearPending() {
        if (_el) _el.removeAttribute('data-audio-cue');
        _pendingNavigateId = null;
    }

    function onPointerMove(e) {
        if (_pendingFrame) return;
        var clientX = e.clientX;
        var clientY = e.clientY;
        _pendingFrame = requestAnimationFrame(function() {
            _pendingFrame = 0;
            if (!_mounted || !_el) return;
            var hit = queryHotspot(clientX, clientY);
            _el.style.cursor = hit ? 'pointer' : 'default';
            setHover(hit);
        });
    }

    function onPointerDown(e) {
        if (e.button !== 0) return;
        var hit = queryHotspot(e.clientX, e.clientY);
        var busy = _callbacks && _callbacks.getBusyLookup ? _callbacks.getBusyLookup() : null;
        if (hit && (!busy || !busy[hit])) {
            _el.setAttribute('data-audio-cue', 'transition');
            _pendingNavigateId = hit;
        } else {
            clearPending();
        }
    }

    function onPointerUp(e) {
        if (e.button !== 0) return;
        // pointerup 早于 click; 这里 query release 坐标, 不匹配则 remove attr
        // 让 overlay-audio-bindings.js click capture 代理看不到 → 不播 cue + onClick 也不 navigate
        var releaseHit = queryHotspot(e.clientX, e.clientY);
        if (releaseHit !== _pendingNavigateId) {
            clearPending();
        }
    }

    function onClick(e) {
        var navId = _pendingNavigateId;
        clearPending();
        if (navId && _callbacks && _callbacks.onClick) {
            _callbacks.onClick(navId, e);
        }
    }

    function onPointerCancel() {
        clearPending();
    }

    function onContextMenu() {
        clearPending();
    }

    function onPointerLeave() {
        if (_pendingFrame) {
            cancelAnimationFrame(_pendingFrame);
            _pendingFrame = 0;
        }
        setHover(null);
        clearPending();
        if (_el) _el.style.cursor = 'default';
    }

    function mount(containerEl, callbacks) {
        if (_mounted) destroy();
        if (!containerEl) return;
        _el = containerEl;
        _callbacks = callbacks || {};
        _mounted = true;
        _currentHover = null;
        _pendingNavigateId = null;
        _el.style.cursor = 'default';

        _el.addEventListener('pointermove', onPointerMove);
        _el.addEventListener('pointerdown', onPointerDown);
        _el.addEventListener('pointerup', onPointerUp);
        _el.addEventListener('click', onClick);
        _el.addEventListener('pointercancel', onPointerCancel);
        _el.addEventListener('contextmenu', onContextMenu);
        _el.addEventListener('pointerleave', onPointerLeave);
    }

    function destroy() {
        if (!_mounted) return;
        if (_pendingFrame) {
            cancelAnimationFrame(_pendingFrame);
            _pendingFrame = 0;
        }
        if (_el) {
            _el.removeEventListener('pointermove', onPointerMove);
            _el.removeEventListener('pointerdown', onPointerDown);
            _el.removeEventListener('pointerup', onPointerUp);
            _el.removeEventListener('click', onClick);
            _el.removeEventListener('pointercancel', onPointerCancel);
            _el.removeEventListener('contextmenu', onContextMenu);
            _el.removeEventListener('pointerleave', onPointerLeave);
            _el.removeAttribute('data-audio-cue');
            _el.style.cursor = '';
        }
        _el = null;
        _callbacks = null;
        _currentHover = null;
        _pendingNavigateId = null;
        _mounted = false;
    }

    function debugState() {
        return {
            mounted: _mounted,
            currentHover: _currentHover,
            pendingNavigateId: _pendingNavigateId,
            pendingFrame: _pendingFrame !== 0
        };
    }

    // QA hook: 模拟事件流程时直接探一次 hitmap (绕过 DOM 事件)
    function queryAt(clientX, clientY) {
        return queryHotspot(clientX, clientY);
    }

    return {
        mount: mount,
        destroy: destroy,
        debugState: debugState,
        queryAt: queryAt
    };
})();

if (typeof window !== 'undefined') {
    window.MapHotspotHitcapture = MapHotspotHitcapture;
}
