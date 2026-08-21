var Bridge = (function() {
    var handlers = {};
    var taskCallbacks = {};
    var taskSeq = 0;
    function on(type, handler) {
        if (!handlers[type]) handlers[type] = [];
        handlers[type].push(handler);
    }
    /** 移除已注册的 handler（按引用匹配，仅移除第一个匹配项） */
    function off(type, handler) {
        if (!handlers[type]) return;
        for (var i = handlers[type].length - 1; i >= 0; i--) {
            if (handlers[type][i] === handler) {
                handlers[type].splice(i, 1);
                break;
            }
        }
    }
    /**
     * 尝试把消息交给本地 WebView2 transport。
     * true 只表示 postMessage 已在当前页面同步投递，不代表 Host 已接受业务请求。
     */
    function send(msg) {
        if (!window.chrome || !window.chrome.webview
                || typeof window.chrome.webview.postMessage !== 'function') return false;
        try {
            window.chrome.webview.postMessage(msg);
            return true;
        } catch (e) {
            return false;
        }
    }
    /**
     * Web→C# 通用 task 调用：
     *   Bridge.task('font_pack', { op:'status' }, function(resp){ ... });
     * C# 端响应回到 type='taskResult'，按 callId 匹配触发回调（一次性，触发后销毁）。
     * cb(null) 在 webview 缺失时同步触发，便于浏览器 harness 防御。
     */
    function task(taskName, payload, cb) {
        if (!window.chrome || !window.chrome.webview) {
            if (typeof cb === 'function') cb(null);
            return null;
        }
        taskSeq += 1;
        var callId = 'wt_' + Date.now().toString(36) + '_' + taskSeq;
        if (typeof cb === 'function') taskCallbacks[callId] = cb;
        if (send({ type: 'task', task: taskName, callId: callId, payload: payload || {} }) === false) {
            delete taskCallbacks[callId];
            if (typeof cb === 'function') cb(null);
            return null;
        }
        return callId;
    }
    if (window.chrome && window.chrome.webview) {
        window.chrome.webview.addEventListener('message', function(event) {
            var data = event.data;
            if (!data || !data.type) return;
            if (data.type === 'taskResult' && data.callId && taskCallbacks[data.callId]) {
                var cb = taskCallbacks[data.callId];
                delete taskCallbacks[data.callId];
                try { cb(data); } catch(e) { console.error(e); }
                return;
            }
            if (handlers[data.type]) {
                var list = handlers[data.type];
                for (var i = 0; i < list.length; i++) {
                    try { list[i](data); } catch(e) { console.error(e); }
                }
            }
        });
    }
    return { on: on, off: off, send: send, task: task };
})();

var OverlayViewportMetrics = (function() {
    var scheduled = false;

    function readRootSize() {
        var root = document.documentElement || document.body;
        return {
            w: root ? root.clientWidth : 0,
            h: root ? root.clientHeight : 0
        };
    }

    function report(reason) {
        if (typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') return;
        var root = readRootSize();
        var vv = window.visualViewport || null;
        Bridge.send({
            type: 'viewportMetrics',
            reason: reason || 'unspecified',
            innerWidth: window.innerWidth || 0,
            innerHeight: window.innerHeight || 0,
            clientWidth: root.w || 0,
            clientHeight: root.h || 0,
            devicePixelRatio: window.devicePixelRatio || 1,
            visualViewportWidth: vv ? vv.width : 0,
            visualViewportHeight: vv ? vv.height : 0
        });
    }

    function schedule(reason) {
        if (scheduled) return;
        scheduled = true;
        var raf = window.requestAnimationFrame || function(cb) { return setTimeout(cb, 16); };
        raf(function() {
            scheduled = false;
            report(reason || 'scheduled');
        });
    }

    window.addEventListener('resize', function() { schedule('window_resize'); });
    if (window.visualViewport && window.visualViewport.addEventListener) {
        window.visualViewport.addEventListener('resize', function() { schedule('visual_viewport_resize'); });
        window.visualViewport.addEventListener('scroll', function() { schedule('visual_viewport_scroll'); });
    }
    window.addEventListener('load', function() { schedule('load'); });

    return {
        report: report,
        schedule: schedule
    };
})();

// === Overlay scale: 只给 tooltip 用的窗口跟随缩放 ===
//
// panel layer 在 launcher Panel 模式下保持 _webViewZoomFactor=1.0 的 CSS px 布局
// （inset 百分比 + viewport 单位天然跟随窗口）。仅 tooltip 跟 AS2 端 Flash stage
// 缩放语义不一致，在大窗口下视觉过大，所以单独按 vpH/FLASH_DESIGN_HEIGHT 缩放。
//
// 这里把 scale 写入 --cf7-overlay-scale 给 panels.css 的 `#panel-tooltip` 用
// （`transform: scale(...)`，layout 不受影响，只是视觉缩放）。
//
// FLASH_DESIGN_HEIGHT 调优史：
//   - 576（更早）：@1080p scale=1.875，实测视觉比 AS2 大约 150%，用户反馈偏大
//   - 864（现）：@1080p=1.25x、@4K=2.5x；用户实测视觉对比定标
//
// 历史教训（回滚记录）：曾把 transform 改成 `body { zoom }` 想同步缩放整个 panel，
// 但破坏了 panel layer 一贯 CSS px 行为，已回滚为只缩 tooltip。
var OverlayScale = (function() {
    var FLASH_DESIGN_HEIGHT = 864;
    var current = 1;

    function compute() {
        var h = window.innerHeight || 0;
        if (h <= 0) return 1;
        return Math.max(0.25, h / FLASH_DESIGN_HEIGHT);
    }

    function update() {
        current = compute();
        if (document.documentElement) {
            document.documentElement.style.setProperty('--cf7-overlay-scale', current);
        }
    }

    function get() { return current; }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', update);
    } else {
        update();
    }
    window.addEventListener('resize', update);
    if (window.visualViewport && window.visualViewport.addEventListener) {
        window.visualViewport.addEventListener('resize', update);
    }

    return { get: get, update: update };
})();

// 启动期字体预热：避免 tooltip 首次悬浮时拿 fallback 字体度量算高度、
// 字体 swap 后再 reflow 导致"第一次错位、第二次才对"。
// document.fonts.load(spec) 触发字体下载并把对应 FontFace 入 ready Promise；
// 之后任意时刻调 document.fonts.ready 都立即 resolved。
// 这里只热常见尺寸，挑战字体（intel-font-*）按需加载，不在这里预热。
(function preloadCommonFonts() {
    if (!window.CF7FontCatalog || typeof window.CF7FontCatalog.prewarm !== 'function') return;
    function warm() {
        // 常见正文/批注/等宽角色；缺失 asset 或独立 harness 404 时安静落回 catalog fallback。
        window.CF7FontCatalog.prewarm([
            'web.intelligence.body',
            'web.intelligence.note',
            'web.overlay.mono'
        ], { size: 13, text: '闪客快打7 ABC 0123，。' });
    }
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', warm);
    } else {
        warm();
    }
})();

// 启动期一次性探针：把 WebGL renderer 回报给 launcher，验证 gpuPreference 是否真的把 WebView2 调度到独显。
// 写 reg 不等于 Windows 一定遵从（Optimus / MUX / 驱动策略可能覆盖），事后验证比静态推理可靠。
(function reportGpuInfoOnce() {
    if (typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') return;
    function probe() {
        var vendor = null, renderer = null;
        try {
            var canvas = document.createElement('canvas');
            var gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
            if (gl) {
                var ext = gl.getExtension('WEBGL_debug_renderer_info');
                if (ext) {
                    vendor = gl.getParameter(ext.UNMASKED_VENDOR_WEBGL) || null;
                    renderer = gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) || null;
                } else {
                    vendor = gl.getParameter(gl.VENDOR) || null;
                    renderer = gl.getParameter(gl.RENDERER) || null;
                }
            }
        } catch (e) {}
        Bridge.send({ type: 'gpuInfo', vendor: vendor, renderer: renderer });
    }
    if (document.readyState === 'complete' || document.readyState === 'interactive') probe();
    else window.addEventListener('DOMContentLoaded', probe);
})();
