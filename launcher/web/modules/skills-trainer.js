/** Pure trainer target-level and preview-freshness policy. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.SkillsTrainer = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function initialDesiredLevel(entry) {
        var current = Number(entry && entry.currentLevel || 0);
        var max = Number(entry && entry.maxLevel || 1);
        return current <= 0 ? 1 : Math.min(max, current + 1);
    }

    function targetMarkLevels(min, max) {
        min = Math.ceil(Number(min));
        max = Math.floor(Number(max));
        var levels = [], count = max - min + 1, level;
        if (!isFinite(min) || !isFinite(max) || count <= 0) return levels;
        if (count <= 12) {
            for (level = min; level <= max; level++) levels.push(level);
            return levels;
        }
        levels.push(min);
        for (level = Math.ceil(min / 5) * 5; level < max; level += 5) {
            if (level !== min) levels.push(level);
        }
        if (max !== min) levels.push(max);
        return levels;
    }

    function normalizedDesiredLevel(entry, level) {
        var current = Number(entry && entry.currentLevel || 0);
        var max = Number(entry && entry.maxLevel || 1);
        var numeric = Number(level);
        if (!isFinite(numeric)) numeric = current + 1;
        numeric = Math.round(numeric);
        return current <= 0 ? 1 : Math.max(current + 1, Math.min(max, numeric));
    }

    function previewMatches(preview, entry, desiredLevel) {
        return !!(preview && entry && preview.skillKey === entry.skillKey
            && Number(preview.desiredLevel) === Number(desiredLevel));
    }

    function previewDebounceMs(config) {
        var configured = Number(config && config.previewDebounceMs);
        return isFinite(configured) && configured >= 0 ? configured : 140;
    }

    function previewTokenFreshMs(config) {
        var configured = Number(config && config.previewTokenFreshMs);
        return isFinite(configured) && configured >= 50 && configured <= 29000 ? configured : 25000;
    }

    function hasFreshPreviewToken(state, entry, now) {
        state = state || {};
        now = Number(now);
        if (!isFinite(now)) now = Date.now();
        return previewMatches(state.preview, entry, state.desiredLevel)
            && !!state.preview.canCommit
            && !!state.preview.learnToken
            && Number(state.receivedAt) > 0
            && now - Number(state.receivedAt) < previewTokenFreshMs(state.config);
    }

    return {
        initialDesiredLevel:initialDesiredLevel,
        targetMarkLevels:targetMarkLevels,
        normalizedDesiredLevel:normalizedDesiredLevel,
        previewMatches:previewMatches,
        previewDebounceMs:previewDebounceMs,
        previewTokenFreshMs:previewTokenFreshMs,
        hasFreshPreviewToken:hasFreshPreviewToken
    };
});
