var MapAvatarSourceData = (function createMapAvatarSourceData(definition) {
    'use strict';

    var _entries = (definition || MapDefinitionData).avatarSources;

    var _entriesByAssetUrl = {};

    function clone(value) {
        return value ? JSON.parse(JSON.stringify(value)) : null;
    }

    function normalizeSymbolName(value) {
        return String(value || '')
            .replace(/^.*[\\/]/, '')
            .replace(/\.(?:png|webp)$/i, '')
            .trim();
    }

    Object.keys(_entries).forEach(function(key) {
        var entry = _entries[key];
        if (!entry || !entry.assetUrl) return;
        _entriesByAssetUrl[normalizeSymbolName(entry.assetUrl)] = entry;
    });

    function getBySymbolName(symbolName) {
        var key = normalizeSymbolName(symbolName);
        return _entries[key] ? clone(_entries[key]) : null;
    }

    function getByAssetUrl(assetUrl) {
        var key = normalizeSymbolName(assetUrl);
        if (_entriesByAssetUrl[key]) {
            return clone(_entriesByAssetUrl[key]);
        }
        var entryKeys = Object.keys(_entries);
        for (var i = 0; i < entryKeys.length; i += 1) {
            var entry = _entries[entryKeys[i]];
            if (entry && normalizeSymbolName(entry.assetUrl) === key) {
                return clone(entry);
            }
        }
        return getBySymbolName(assetUrl);
    }

    function getAll() {
        return clone(_entries);
    }

    return {
        create: createMapAvatarSourceData,
        getBySymbolName: getBySymbolName,
        getByAssetUrl: getByAssetUrl,
        getAll: getAll
    };
})();
