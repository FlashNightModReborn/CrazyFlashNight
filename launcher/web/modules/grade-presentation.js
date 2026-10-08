/**
 * Canonical grade presentation for the Web layer — the single JS source.
 *
 * The authoritative dictionary is data/items/equipment_mods/ui_presentation.xml;
 * this module is its one runtime copy for every Web consumer (inventory mod
 * projection, choice rewards, item-use reveal). tools/audit-grade-colors.js
 * pins this module equal to the XML and forbids any second copy, so the
 * topology can never silently diverge again.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.GradePresentation = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var GRADES = {
        low:{label:'低级', color:'#006600'},
        medium:{label:'中等', color:'#996600'},
        high:{label:'高等', color:'#0099FF'},
        special:{label:'特殊', color:'#FFFF00'}
    };
    var UNKNOWN_COLOR = '#58636E';
    // Aggregation/grouping order for result summaries: special stays a
    // standalone orthogonal class, never a "highest rarity" claim.
    var GROUP_ORDER = ['special', 'high', 'medium', 'low', 'unknown'];

    function normalize(value) {
        value = String(value || 'unknown');
        return GRADES[value] ? value : 'unknown';
    }
    function color(value) {
        var grade = normalize(value);
        return grade === 'unknown' ? UNKNOWN_COLOR : GRADES[grade].color;
    }
    function label(value) {
        var grade = normalize(value);
        return grade === 'unknown' ? '' : GRADES[grade].label;
    }
    function isReducedPresentation(win) {
        win = win || (typeof window !== 'undefined' ? window : null);
        return !!win && win.CF7_REDUCED_PRESENTATION === true;
    }

    return {
        GRADES:GRADES,
        UNKNOWN_COLOR:UNKNOWN_COLOR,
        GROUP_ORDER:GROUP_ORDER,
        normalize:normalize,
        color:color,
        label:label,
        isReducedPresentation:isReducedPresentation
    };
});
