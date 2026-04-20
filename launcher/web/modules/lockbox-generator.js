(function(root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory(require('./minigames/lockbox/core/generator.js'));
    } else if (!root.LockboxGenerator && root.console && root.console.warn) {
        root.console.warn('[Deprecated] Use modules/minigames/lockbox/core/generator.js instead of modules/lockbox-generator.js');
    }
})(typeof self !== 'undefined' ? self : this, function(generator) {
    'use strict';
    return generator;
});
