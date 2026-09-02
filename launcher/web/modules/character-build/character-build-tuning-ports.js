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

    function bindSourceTooltip(owner, node, item, source, isSuppressed) {
        if (!node || !item || !source) return null;
        if (source.sourceKind === 'loadout') {
            var slotKey = String(source.slotKey || '');
            if (!slotKey || !owner._buildView
                    || typeof owner._buildView._bindLoadoutTooltip !== 'function') return null;
            return owner._buildView._bindLoadoutTooltip(
                node,
                'tuning:' + String(source.sessionGeneration || '') + ':' + slotKey
                    + ':' + String(source.expectedLoadoutRevision || '')
                    + ':' + String(item.name || ''),
                slotKey.replace(/装备$/, ''), item,
                {kind:'equipment', slotKey:slotKey}, isSuppressed);
        }
        var physicalSlot = Number(source.slot);
        var lease = String(source.expectedLease || '');
        if (source.sourceKind !== 'inventory' || source.containerId !== '背包'
                || !isFinite(physicalSlot) || Math.floor(physicalSlot) !== physicalSlot
                || physicalSlot < 0 || physicalSlot > 49
                || !/^[A-Za-z0-9._-]{1,128}$/.test(lease)
                || !owner._bindCandidateTooltip) return null;
        return owner._bindCandidateTooltip(node, {
            key:'tuning-source:' + physicalSlot + ':' + lease
                + ':' + String(item.name || ''),
            name:String(item.displayName || item.name || ''),
            type:String(item.majorType || item.use || '装备'),
            presentation:item,
            raw:{source:{containerId:'背包', slot:physicalSlot, expectedLease:lease}}
        }, isSuppressed);
    }

    return {
        loadConversionCandidates:loadConversionCandidates,
        bindSourceTooltip:bindSourceTooltip,
        openInspector:openInspector,
        closeInspector:closeInspector
    };
});
