(function(root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory(require('./minigames/lockbox/core/index.js'));
    } else if (!root.LockboxCore && root.console && root.console.warn) {
        root.console.warn('[Deprecated] Use modules/minigames/lockbox/core/index.js instead of modules/lockbox-core.js');
    }
})(typeof self !== 'undefined' ? self : this, function(core) {
    'use strict';
    return core;
});
