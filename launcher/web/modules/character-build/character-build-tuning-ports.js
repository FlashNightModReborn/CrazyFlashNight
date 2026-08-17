/** Character Build ports used by the embedded Equipment Tuning view. */
(function(root, factory) {
    'use strict';
    var model = typeof module !== 'undefined' && module.exports
        ? require('../equipment-tuning-model.js') : root && root.EquipmentTuningModel;
    var adapter = typeof module !== 'undefined' && module.exports
        ? require('./character-build-tuning-adapter.js') : root && root.CharacterBuildTuningAdapter;
    var api = factory(model, adapter, root);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildTuningPorts = api;
        root.CharacterBuildTuningPorts = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(EquipmentTuningModel, TuningAdapter, global) {
    'use strict';
    if (!EquipmentTuningModel || !EquipmentTuningModel.normalizeTuningSource
            || !TuningAdapter || !TuningAdapter.slotFor) {
        throw new Error('CharacterBuildTuningPorts requires tuning model and adapter');
    }

    function loadConversionCandidates(owner, sourceItem, source, callback) {
        source = EquipmentTuningModel.normalizeTuningSource(source);
        var state = owner._session.debugState();
        if (!owner._active || !source || source.sourceKind !== 'loadout'
                || !EquipmentTuningModel.sameLoadoutIdentity(source, owner._entrySource)
                || state.state !== 'idle'
                || state.sessionGeneration !== source.sessionGeneration) return false;
        var slotKey = owner._slotKey;
        var callId = owner._session.requestCandidates(
            {kind:'equipment', slotKey:slotKey},
            'compatible',
            function(response, accepted, targetKey, scope) {
                if (!owner._active || owner._slotKey !== slotKey
                        || !EquipmentTuningModel.sameLoadoutIdentity(
                            source, owner._entrySource)) return;
                if (!accepted || targetKey !== 'equipment:' + slotKey
                        || scope !== 'compatible' || !response
                        || !response.payload) {
                    callback({success:false, error:response && response.error
                        || 'inventory_projection_failed'});
                    return;
                }
                var projected;
                try {
                    projected = owner._projectCandidates(response.payload);
                } catch (_) {
                    callback({success:false, error:'inventory_projection_failed'});
                    return;
                }
                var slots = [];
                for (var i = 0; i < projected.length; i++) {
                    var slot = TuningAdapter.slotFor(projected[i]);
                    if (slot) slots.push(slot);
                }
                callback({success:true, candidates:slots});
            });
        return !!callId;
    }

    function openInspector(owner, item, gender, role) {
        var shell = owner._ports.shell;
        if (!shell || !global.EquipmentInspector || !global.EquipmentInspector.open) return false;
        closeInspector(owner);
        if (global.PanelTooltip && global.PanelTooltip.hide) global.PanelTooltip.hide();
        var projection = global.InventoryWorkbenchOwnedView
            && global.InventoryWorkbenchOwnedView.primitiveProjection
            ? global.InventoryWorkbenchOwnedView.primitiveProjection(item) : item;
        var controller = null;
        controller = global.EquipmentInspector.open({
            shell:shell,
            item:projection,
            gender:gender,
            kind:'equipment-inspector',
            kicker:role === 'conversion-target' ? '交换目标检视' : '当前装备检视',
            closeLabel:'返回调制',
            context:'character-build-tuning',
            onClose:function() {
                if (owner._inspector === controller) owner._inspector = null;
            }
        });
        owner._inspector = controller;
        return !!controller;
    }

    function closeInspector(owner) {
        if (!owner._inspector) return false;
        var controller = owner._inspector;
        owner._inspector = null;
        if (controller.close) controller.close();
        else if (controller.destroy) controller.destroy();
        return true;
    }

    return {
        loadConversionCandidates:loadConversionCandidates,
        openInspector:openInspector,
        closeInspector:closeInspector
    };
});
