/**
 * Character-build candidate facet counts.
 *
 * AS2/Host own the complete inventory facet projection. This leaf only maps a
 * fixed Character Build target to its existing catalog `use` node; it neither
 * guesses taxonomy from names nor performs transport requests.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildFacetCounts = api;
        root.CharacterBuildFacetCounts = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var MAX_ITEMS = 50;
    var EXACT_KEYS = ['filterFacets', 'filterItemCount', 'scope'];

    function whole(value, minimum, maximum) {
        return typeof value === 'number' && isFinite(value)
            && Math.floor(value) === value
            && value >= minimum && value <= maximum;
    }

    function safeText(value) {
        return typeof value === 'string' && value.length > 0
            && value.length <= 128 && !/[\x00-\x1f\x7f-\x9f]/.test(value);
    }

    function exactKeys(value, expected) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
        var keys = Object.keys(value).sort();
        expected = expected.slice().sort();
        if (keys.length !== expected.length) return false;
        for (var i = 0; i < keys.length; i++) {
            if (keys[i] !== expected[i]) return false;
        }
        return true;
    }

    function readFacetArray(facets, depth, useCounts) {
        if (!Array.isArray(facets) || facets.length > MAX_ITEMS || depth > 2) return -1;
        var ids = Object.create(null);
        var total = 0;
        for (var i = 0; i < facets.length; i++) {
            var facet = facets[i];
            if (!exactKeys(facet, ['children', 'count', 'id', 'label', 'order'])
                    || !safeText(facet.id) || !safeText(facet.label)
                    || ids[facet.id] || !whole(facet.count, 0, MAX_ITEMS)
                    || typeof facet.order !== 'number' || !isFinite(facet.order)
                    || facet.order < -1000000 || facet.order > 1000000) return -1;
            ids[facet.id] = true;
            if (!Array.isArray(facet.children)) return -1;
            var childTotal = facet.children.length === 0 ? 0
                : depth >= 2 ? -1
                : readFacetArray(facet.children, depth + 1, useCounts);
            if (childTotal < 0 || childTotal > facet.count) return -1;
            if (depth === 1) {
                useCounts[facet.id] = (useCounts[facet.id] || 0) + facet.count;
                if (useCounts[facet.id] > MAX_ITEMS) return -1;
            }
            total += facet.count;
            if (total > MAX_ITEMS) return -1;
        }
        return total;
    }

    function normalize(projection) {
        if (!exactKeys(projection, EXACT_KEYS)
                || projection.scope !== 'all'
                || !whole(projection.filterItemCount, 0, MAX_ITEMS)) {
            return {known:false, total:null, useCounts:null};
        }
        var useCounts = Object.create(null);
        var total = readFacetArray(projection.filterFacets, 0, useCounts);
        if (total !== projection.filterItemCount) {
            return {known:false, total:null, useCounts:null};
        }
        return {
            known:true,
            total:projection.filterItemCount,
            useCounts:useCounts
        };
    }

    function countForTarget(model, kind, id) {
        if (!model || model.known !== true || !model.useCounts) return null;
        if (kind === 'drug') return model.useCounts['药剂'] || 0;
        id = String(id || '');
        if (!id) return null;
        var count = model.useCounts[id] || 0;
        if (id === '手枪2') count += model.useCounts['手枪'] || 0;
        return count;
    }

    function badgeText(count) {
        return count == null ? '—' : String(count);
    }

    function accessibleText(count) {
        return count == null
            ? '背包候选数量暂不可用'
            : '背包候选 ' + count + ' 个';
    }

    /**
     * Decorate an existing slot data node. This is intentionally a leaf
     * helper, not a component lifecycle: CharacterBuildView still owns the
     * button, stable key, focus and selection.
     */
    function decorateSlot(slot, model, kind, id) {
        var count = countForTarget(model, kind, id);
        var state = count == null ? 'unknown' : 'known';
        var badge = slot.ownerDocument.createElement('small');
        badge.className = 'character-build-slot-count';
        badge.setAttribute('data-slot-candidate-count', '');
        badge.setAttribute('data-count-state', state);
        badge.setAttribute('aria-hidden', 'true');
        badge.textContent = badgeText(count);
        badge.title = accessibleText(count);
        slot.setAttribute('data-candidate-count-state', state);
        if (count != null) {
            slot.setAttribute('data-candidate-count', String(count));
        }
        slot.setAttribute(
            'aria-label',
            slot.getAttribute('aria-label') + '，' + accessibleText(count));
        slot.appendChild(badge);
        return count;
    }

    function focusSummary(model, node) {
        if (!node) {
            return {
                text:model && model.known
                    ? '浏览：尚未选择槽位 · 数字为背包候选数'
                    : '浏览：尚未选择槽位 · 背包候选数暂不可用',
                title:''
            };
        }
        var countCopy =
            node.getAttribute('data-candidate-count-state') === 'known'
                ? '背包候选 '
                    + node.getAttribute('data-candidate-count') + ' 个'
                : '背包候选数暂不可用';
        return {
            text:'浏览：' + node.getAttribute('data-focus-label') + ' · '
                + node.getAttribute('data-focus-name') + ' · '
                + countCopy + ' · Enter 选择',
            title:node.getAttribute('data-focus-label') + ' · '
                + node.getAttribute('data-focus-name') + ' · '
                + node.getAttribute('data-focus-meta')
        };
    }

    function syncFocusSummary(root, summaryNode, model, key) {
        var activeKey = String(key || '');
        var node = activeKey
            ? root.querySelector(
                '[data-roving-key="'
                    + activeKey.replace(/"/g, '\\"') + '"]')
            : null;
        var summary = focusSummary(model, node);
        summaryNode.textContent = summary.text;
        summaryNode.title = summary.title;
        return activeKey;
    }

    return {
        normalize:normalize,
        countForTarget:countForTarget,
        badgeText:badgeText,
        accessibleText:accessibleText,
        decorateSlot:decorateSlot,
        focusSummary:focusSummary,
        syncFocusSummary:syncFocusSummary
    };
});
