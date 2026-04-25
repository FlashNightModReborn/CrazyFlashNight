var CF7FrameLimiter = (function() {
    "use strict";

    if (window.CF7FrameLimiter && window.CF7FrameLimiter.setLimit) {
        return window.CF7FrameLimiter;
    }

    var nativeRequestAnimationFrame = window.requestAnimationFrame
        ? window.requestAnimationFrame.bind(window)
        : function(cb) { return window.setTimeout(function() { cb(performance.now()); }, 16); };
    var nativeCancelAnimationFrame = window.cancelAnimationFrame
        ? window.cancelAnimationFrame.bind(window)
        : function(id) { window.clearTimeout(id); };

    var nextId = 1;
    var callbacks = {};
    var queue = [];
    var pumpId = 0;
    var lastDispatchAt = 0;
    var limit = normalizeLimit(window.CF7_FRAME_RATE_LIMIT);
    var intervalMs = intervalFor(limit);

    function normalizeLimit(value) {
        var n = Number(value);
        if (!isFinite(n) || n < 0) return 60;
        if (n === 0) return 0;
        if (n < 15) return 15;
        if (n > 240) return 240;
        return Math.round(n);
    }

    function intervalFor(fps) {
        return fps > 0 ? (1000 / fps) : 0;
    }

    function applyRootState() {
        var root = document.documentElement;
        if (!root) return;
        root.classList.toggle("perf-frame-capped", limit > 0);
        root.style.setProperty("--overlay-frame-rate-limit", String(limit));
    }

    function schedulePump() {
        if (pumpId) return;
        pumpId = nativeRequestAnimationFrame(pump);
    }

    function pump(now) {
        pumpId = 0;

        if (limit > 0 && lastDispatchAt > 0 && now - lastDispatchAt < intervalMs - 0.5) {
            schedulePump();
            return;
        }

        lastDispatchAt = now;
        var batch = queue;
        queue = [];
        for (var i = 0; i < batch.length; i++) {
            var id = batch[i];
            var cb = callbacks[id];
            if (!cb) continue;
            delete callbacks[id];
            try {
                cb(now);
            } catch (err) {
                setTimeout(function(e) { throw e; }.bind(null, err), 0);
            }
        }

        if (queue.length > 0) schedulePump();
    }

    function requestFrame(cb) {
        if (typeof cb !== "function") {
            return nativeRequestAnimationFrame(cb);
        }
        var id = nextId++;
        callbacks[id] = cb;
        queue.push(id);
        schedulePump();
        return id;
    }

    function cancelFrame(id) {
        if (callbacks[id]) delete callbacks[id];
    }

    function setLimit(value) {
        limit = normalizeLimit(value);
        intervalMs = intervalFor(limit);
        window.CF7_FRAME_RATE_LIMIT = limit;
        applyRootState();
        if (queue.length > 0) schedulePump();
        return limit;
    }

    window.requestAnimationFrame = requestFrame;
    window.cancelAnimationFrame = cancelFrame;
    applyRootState();

    return {
        setLimit: setLimit,
        getLimit: function() { return limit; },
        getIntervalMs: function() { return intervalMs; },
        nativeRequestAnimationFrame: nativeRequestAnimationFrame,
        nativeCancelAnimationFrame: nativeCancelAnimationFrame
    };
})();
