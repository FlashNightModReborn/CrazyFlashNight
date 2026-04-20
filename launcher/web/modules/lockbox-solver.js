(function(root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory(require('./minigames/lockbox/core/solver.js'));
    } else if (!root.LockboxSolver && root.console && root.console.warn) {
        root.console.warn('[Deprecated] Use modules/minigames/lockbox/core/solver.js instead of modules/lockbox-solver.js');
    }
})(typeof self !== 'undefined' ? self : this, function(solver) {
    'use strict';
    return solver;
});
