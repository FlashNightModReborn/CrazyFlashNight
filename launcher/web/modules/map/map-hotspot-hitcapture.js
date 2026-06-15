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
    //     pointerdown 未命中且 !currentMapReady() → 暂存按下的 page 坐标 (deferred); pointerup 暂存
    //     释放的 page 坐标。重放只在"按下+释放"都齐 (一次完整点击) 时进行, 不在按住期间误触:
    //       · hitmap 在 pointerup 之前就绪 → 面板 flushDeferred 此刻 _deferredUp 尚空 → 不动, 待 up;
    //       · pointerup 时若已就绪 → 由 up 触发重放; 否则留待面板就绪回调 flushDeferred。
    //     重放用就绪图按 page 坐标重判 (布局无关, 切层重布局/舞台位移不致误解释 client 坐标),
    //     down/up 同判定且非 busy → onClick 导航 → 切层首点不丢失。面板每次切层先 clearDeferred
    //     作废上一窗口的暂存; 移出舞台/取消手势亦清。窗口内 hover 光标显 progress (显式"加载中")。
    //
    //   音效路径 (v4 决策):
    //     - hover cue: 由本模块在 hit null→非null 时显式 BootstrapAudio.playHover() 调用,
    //       不依赖 overlay-audio-bindings.js 的 mouseover 代理 (那个代理要求 [data-audio-cue]
    //       属性常驻, 而本模块只在 pointerdown 命中期临时设属性)
    //     - click cue: 走 overlay-audio-bindings.js 的 click capture 代理 (透明转发 [data-audio-cue]),
    //       因 capture 比本模块 click bubble 早, 所以 pointerup 已经决定 attr 在不在
    //     - 重放 cue: 重放无真实 click 事件, click 代理捕获不到 → flushDeferred 显式 playTransition()
    //       补一次 (与即时点击各播一次, 不重不漏)
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

    // 切层构建窗口内的"暂存点击": 目标 hitmap 尚未就绪 (engine.query 返回 null) 时, 记下按下/释放的
    // page 坐标 (布局无关); 待"按下+释放"都齐, 面板就绪回调 (或 up 时已就绪) 触发 flushDeferred →
    // 用就绪图重放该点击, 命中即导航 → 切层首点不丢失 (P2-1)。每次切层/切图先 clearDeferred 作废。
    var _deferredDown = null;          // { px, py } 窗口内 pointerdown 的 page 坐标 (布局无关)
    var _deferredUp = null;            // { px, py } 窗口内 pointerup 的 page 坐标 (与 down 比对防拖拽)

    function getEngine() {
        return typeof MapHittestEngine !== 'undefined' ? MapHittestEngine : null;
    }

    // 当前查询键对应的 hitmap 是否就绪 (可被 query 命中)。未就绪 = 切层/开页构建窗口期。
    function currentMapReady() {
        var engine = getEngine();
        var pageId = _callbacks && _callbacks.getCurrentPageId ? _callbacks.getCurrentPageId() : '';
        return !!(engine && pageId && engine.isReady && engine.isReady(pageId));
    }

    // 客户端坐标 → page 坐标 (与 transform 解耦, 直接读 rect)。返回 null = 布局未就绪。
    function clientToPage(clientX, clientY) {
        if (!_el) return null;
        var rect = _el.getBoundingClientRect();
        if (!rect.width || !rect.height) return null;
        var page = _callbacks && _callbacks.getCurrentPage ? _callbacks.getCurrentPage() : null;
        var pageW = (page && page.width) || 1031;
        var pageH = (page && page.height) || 608;
        return {
            px: (clientX - rect.left) / rect.width * pageW,
            py: (clientY - rect.top) / rect.height * pageH
        };
    }

    // page 坐标 → hotspot id (engine 命中 + visible/enabled 兜底)。page 坐标与布局无关,
    // 故暂存重放时用它 (而非 client 坐标) 不受切层重布局影响。
    function resolveHotspotAtPage(px, py) {
        if (!_callbacks) return null;
        var pageId = _callbacks.getCurrentPageId ? _callbacks.getCurrentPageId() : '';
        if (!pageId) return null;
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

    function queryHotspot(clientX, clientY) {
        var pagePt = clientToPage(clientX, clientY);
        if (!pagePt) return null;
        return resolveHotspotAtPage(pagePt.px, pagePt.py);
    }

    function playHoverCue() {
        var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
        if (A && typeof A.playHover === 'function') A.playHover();
    }

    // 重放导航的 transition 音效: 重放无真实 click 事件, overlay-audio-bindings 的 click 代理
    // 捕获不到 → 这里显式补一次 (与即时点击经 data-audio-cue='transition' 播放的语义一致, 各一次)。
    function playTransitionCue() {
        var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
        if (A && typeof A.playTransition === 'function') A.playTransition();
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

    // 构建就绪后重放窗口内的暂存点击。仅当"按下+释放"都齐 (一次完整点击) 才重放 —— 若 hitmap
    // 在 pointerup 之前就绪, 此处 _deferredUp 尚空 → 直接返回 (不在按住期间误触), 待 pointerup 触发。
    // 用就绪图按 page 坐标重判 (布局无关): 命中、释放判定与按下一致 (防拖拽)、非 busy → 走与即时
    // 点击相同的 onClick 导航路径, 并显式补一次 transition 音效。
    function flushDeferred() {
        if (!_deferredDown || !_deferredUp) return;
        var down = _deferredDown;
        var up = _deferredUp;
        clearDeferred();                                             // 完整点击 → 无论结果都消费掉
        var downHit = resolveHotspotAtPage(down.px, down.py);
        if (!downHit) return;
        if (resolveHotspotAtPage(up.px, up.py) !== downHit) return;  // 拖拽到别处释放 → 不导航
        var busy = _callbacks && _callbacks.getBusyLookup ? _callbacks.getBusyLookup() : null;
        if (busy && busy[downHit]) return;
        playTransitionCue();
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
            // 切层/开页构建窗口: query 因 hitmap 未就绪而返回 null (非真·空白处)。暂存按下的 page 坐标
            // (布局无关, 切层重布局不致误解释), 待 pointerup + flushDeferred 重放 → 首点不丢。
            // 仅在拿到 pointerup 后才重放 (见 flushDeferred), 不在按住期间误触。
            _deferredDown = clientToPage(e.clientX, e.clientY);
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
            // 窗口内释放: 暂存释放的 page 坐标 (与 down 比对防拖拽)。
            _deferredUp = clientToPage(e.clientX, e.clientY);
            // 若 hitmap 此刻已就绪 (窗口在按住期间结束) → 释放即重放; 否则留待面板就绪回调 flushDeferred。
            if (currentMapReady()) flushDeferred();
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
