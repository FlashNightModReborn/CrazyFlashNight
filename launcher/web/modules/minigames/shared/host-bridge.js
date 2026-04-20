(function(root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory();
    } else {
        root.MinigameHostBridge = factory();
    }
})(typeof self !== 'undefined' ? self : this, function() {
    'use strict';

    function getRoot() {
        if (typeof window === 'undefined' || !window.__minigameOverlayRoot) return '';
        return String(window.__minigameOverlayRoot);
    }

    function resolveUrl(path) {
        var cleanPath = String(path || '');
        var root = getRoot();
        if (!root) return cleanPath;
        if (!cleanPath) return root;
        if (root.charAt(root.length - 1) === '/' && cleanPath.charAt(0) === '/') {
            return root + cleanPath.slice(1);
        }
        if (root.charAt(root.length - 1) !== '/' && cleanPath.charAt(0) !== '/') {
            return root + '/' + cleanPath;
        }
        return root + cleanPath;
    }

    function sendSession(game, kind, data) {
        if (typeof Bridge === 'undefined' || !Bridge.send) return false;
        Bridge.send({
            type: 'panel',
            cmd: 'minigame_session',
            payload: {
                game: game,
                kind: kind,
                data: data || {}
            }
        });
        return true;
    }

    return {
        resolveUrl: resolveUrl,
        sendSession: sendSession
    };
});
