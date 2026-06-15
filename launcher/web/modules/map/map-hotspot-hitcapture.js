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
    //   切层构建窗口 (目标 hitmap 未就绪, query 恒 null):
    //     pointerdown 未命中且 !currentMapReady() → 暂存按下坐标 (deferred), pointerup 暂存释放坐标;
    //     面板在该 hitmap 构建就绪后调 flushDeferred → 用就绪图重放该点击 (down/up 同判定且非 busy 即
    //     onClick 导航) → 切层首点不丢失。面板每次切层先 clearDeferred 作废上一窗口的暂存。
    //     窗口内 hover 光标显 progress (显式"加载中", 非静默死区)。
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

    // 切层构建窗口内的"暂存点击": 目标 hitmap 尚未就绪 (engine.query 返回 null) 时, 记下
    // 按下/释放坐标; 面板在该 hitmap 构建就绪后调 flushDeferred → 用就绪图重放该点击, 命中即
    // 导航 → 切层首点不丢失 (P2-1)。面板每次切层/切图先 clearDeferred 作废上一窗口的暂存。
    var _deferredDown = null;          // { x, y } 窗口内 pointerdown 客户端坐标
    var _deferredUp = null;            // { x, y } 窗口内 pointerup 客户端坐标 (与 down 比对防拖拽)

    function getEngine() {
        return typeof MapHittestEngine !== 'undefined' ? MapHittestEngine : null;
    }

    // 当前查询键对应的 hitmap 是否就绪 (可被 query 命中)。未就绪 = 切层/开页构建窗口期。
    function currentMapReady() {
        var engine = getEngine();
        var pageId = _callbacks && _callbacks.getCurrentPageId ? _callbacks.getCurrentPageId() : '';
        return !!(engine && pageId && engine.isReady && engine.isReady(pageId));
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

    // 作废暂存点击 (面板切层/切图/关闭时调用)。
    function clearDeferred() {
        _deferredDown = null;
        _deferredUp = null;
    }

    // 构建就绪后重放窗口内的暂存点击: 用就绪图重新判定按下坐标; 命中且释放坐标判定一致
    // (防拖拽离开) 且非 busy → 走与即时点击相同的 onClick 导航路径。
    function flushDeferred() {
        if (!_deferredDown) return;
        var down = _deferredDown;
        var up = _deferredUp || down;
        clearDeferred();
        var downHit = queryHotspot(down.x, down.y);
        if (!downHit) return;
        if (queryHotspot(up.x, up.y) !== downHit) return;   // 拖拽到别处释放 → 不导航 (同即时路径语义)
        var busy = _callbacks && _callbacks.getBusyLookup ? _callbacks.getBusyLookup() : null;
        if (busy && busy[downHit]) return;
        if (_callbacks && _callbacks.onClick) _callbacks.onClick(downHit, null);
    }

    function onPointerMove(e) {
        if (_pendingFrame) return;
        var clientX = e.clientX;
        var clientY = e.clientY;
        _pendingFrame = requestAnimationFrame(function() {
            _pendingFrame = 0;
            if (!_mounted || !_el) return;
            var hit = queryHotspot(clientX, clientY);
            // 命中 → pointer; 未命中但 hitmap 仍在构建 → progress (显式"加载中", 非静默死区); 否则 default
            _el.style.cursor = hit ? 'pointer' : (currentMapReady() ? 'default' : 'progress');
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
            clearDeferred();
        } else if (!hit && !currentMapReady()) {
            // 切层/开页构建窗口: query 因 hitmap 未就绪而返回 null (非真·空白处)。暂存按下坐标,
            // 待 flushDeferred 用就绪图重放 → 首点不丢。busy 留到重放时再判 (届时才有 id)。
            _deferredDown = { x: e.clientX, y: e.clientY };
            _deferredUp = null;
            clearPending();
        } else {
            clearDeferred();
            clearPending();
        }
    }

    function onPointerUp(e) {
        if (e.button !== 0) return;
        if (_deferredDown) {
            // 窗口内释放: 暂存释放坐标, 留待 flushDeferred 与按下坐标比对 (防拖拽误触)。
            _deferredUp = { x: e.clientX, y: e.clientY };
            return;
        }
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
        clearDeferred();
    }

    function onContextMenu() {
        clearPending();
        clearDeferred();
    }

    function onPointerLeave() {
        if (_pendingFrame) {
            cancelAnimationFrame(_pendingFrame);
            _pendingFrame = 0;
        }
        setHover(null);
        clearPending();
        clearDeferred();   // 鼠标移出舞台 = 放弃本次点击, 不再于就绪后重放
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
        clearDeferred();
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
        clearDeferred();
        _mounted = false;
    }

    function debugState() {
        return {
            mounted: _mounted,
            currentHover: _currentHover,
            pendingNavigateId: _pendingNavigateId,
            pendingFrame: _pendingFrame !== 0,
            deferredPending: !!_deferredDown
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
        queryAt: queryAt,
        clearDeferred: clearDeferred,
        flushDeferred: flushDeferred
    };
})();

if (typeof window !== 'undefined') {
    window.MapHotspotHitcapture = MapHotspotHitcapture;
}
