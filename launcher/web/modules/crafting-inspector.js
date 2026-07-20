/** 合成工作台对通用 EquipmentInspector 的薄适配层。 */
var CraftingInspector = (function() {
    'use strict';

    function copyOptions(options) {
        var source = options || {};
        var result = {};
        for (var key in source) {
            if (Object.prototype.hasOwnProperty.call(source, key)) result[key] = source[key];
        }
        result.item = source.output || source.item || {};
        result.kind = 'crafting-inspector';
        result.kicker = '产物检视';
        result.closeLabel = '返回合成';
        result.context = 'crafting';
        return result;
    }

    function open(options) {
        if (typeof EquipmentInspector === 'undefined' || !EquipmentInspector.open) return null;
        return EquipmentInspector.open(copyOptions(options));
    }

    return {
        loadManifest: function(url) { return EquipmentInspector.loadManifest(url); },
        resolveProductSource: function(output, gender, manifest) {
            return EquipmentInspector.resolveItemSource(output, gender, manifest);
        },
        buildStateForSource: function(source, manifest) {
            return EquipmentInspector.buildStateForSource(source, manifest);
        },
        open: open,
        constants: EquipmentInspector.constants
    };
})();
