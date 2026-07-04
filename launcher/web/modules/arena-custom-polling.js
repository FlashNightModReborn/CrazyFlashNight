(function(root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory();
    } else {
        root.ArenaCustomPolling = factory();
    }
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
    'use strict';

    function clear(timerId) {
        if (timerId) clearTimeout(timerId);
        return 0;
    }

    function schedule(timerId, options) {
        options = options || {};
        timerId = clear(timerId);
        if (!options.active || typeof options.callback !== 'function') return 0;
        return setTimeout(function() {
            options.callback();
        }, options.delayMs || 1000);
    }

    return {
        clear: clear,
        schedule: schedule
    };
});
