(function(root) {
    'use strict';
    if (typeof module === 'object' && module.exports) {
        require('./minigames/lockbox/lockbox-panel.js');
        module.exports = {};
        return;
    }
    if (!root.LockboxPanel && root.console && root.console.warn) {
        root.console.warn('[Deprecated] Use modules/minigames/lockbox/lockbox-panel.js instead of modules/lockbox-panel.js');
    }
})(typeof self !== 'undefined' ? self : this);
