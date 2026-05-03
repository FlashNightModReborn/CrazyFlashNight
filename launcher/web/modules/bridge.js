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
    function send(msg) {
        if (window.chrome && window.chrome.webview) {
            window.chrome.webview.postMessage(msg);
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
        send({ type: 'task', task: taskName, callId: callId, payload: payload || {} });
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
