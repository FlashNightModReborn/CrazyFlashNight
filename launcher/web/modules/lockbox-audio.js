(function(root) {
    'use strict';
    if (typeof module === 'object' && module.exports) {
        require('./minigames/lockbox/lockbox-audio.js');
        module.exports = {};
        return;
    }
    if (!root.LockboxAudio && root.console && root.console.warn) {
        root.console.warn('[Deprecated] Use modules/minigames/lockbox/lockbox-audio.js instead of modules/lockbox-audio.js');
    }
})(typeof self !== 'undefined' ? self : this);
