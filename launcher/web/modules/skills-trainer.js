/** Pure trainer target-level and preview-freshness policy. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.SkillsTrainer = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function affordableMaxLevel(entry, skillPoints) {
        var current = Number(entry && entry.currentLevel || 0);
        var max = Number(entry && entry.maxLevel || 1);
        var upgradeSP = Number(entry && entry.upgradeSP);
        var points = Number(skillPoints);
        if (!isFinite(current)) current = 0;
        if (!isFinite(max)) max = 1;
        current = Math.max(0, Math.floor(current));
        max = Math.max(1, Math.floor(max));
        if (current <= 0) return 1;
        if (current >= max) return max;
        if (upgradeSP === 0) return max;
        if (!isFinite(upgradeSP) || upgradeSP < 0) return current;
        if (!isFinite(points) || points < 0) points = 0;
        return Math.min(max, current + Math.floor(Math.floor(points) / upgradeSP));
    }

    function initialDesiredLevel(entry, skillPoints) {
        var current = Number(entry && entry.currentLevel || 0);
        var max = affordableMaxLevel(entry, skillPoints);
        if (current <= 0) return 1;
        return max > current ? current + 1 : current;
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

    function normalizedDesiredLevel(entry, level, skillPoints) {
        var current = Number(entry && entry.currentLevel || 0);
        var max = affordableMaxLevel(entry, skillPoints);
        var numeric = Number(level);
        if (current > 0 && max <= current) return current;
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
        affordableMaxLevel:affordableMaxLevel,
        initialDesiredLevel:initialDesiredLevel,
        targetMarkLevels:targetMarkLevels,
        normalizedDesiredLevel:normalizedDesiredLevel,
        previewMatches:previewMatches,
        previewDebounceMs:previewDebounceMs,
        previewTokenFreshMs:previewTokenFreshMs,
        hasFreshPreviewToken:hasFreshPreviewToken
    };
});
