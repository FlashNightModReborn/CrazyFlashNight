var Bridge = (function() {
    var handlers = {};
    function on(type, handler) {
        if (!handlers[type]) handlers[type] = [];
        handlers[type].push(handler);
    }
    function send(msg) {
        if (window.chrome && window.chrome.webview) {
            window.chrome.webview.postMessage(msg);
        }
    }
    if (window.chrome && window.chrome.webview) {
        window.chrome.webview.addEventListener('message', function(event) {
            var data = event.data;
            if (data && data.type && handlers[data.type]) {
                var list = handlers[data.type];
                for (var i = 0; i < list.length; i++) {
                    try { list[i](data); } catch(e) { console.error(e); }
                }
            }
        });
    }
    return { on: on, send: send };
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
