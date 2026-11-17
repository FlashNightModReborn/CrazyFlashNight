/** Potion selection and emergency authorization controls; writes remain in the session. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CharacterBuildDrugControls = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';
    var SUPPORTED_CHEST_NAMES = {
        '统合61式胸甲':true,
        '钛合金61式胸甲':true
    };
    var CONTROL_CHARACTERS = /[\u0000-\u001f\u007f-\u009f]/;
    function ownKeys(value, expected) {
        return !!value && typeof value === 'object' && Object.keys(value).length === expected.length
            && expected.every(function(key) { return Object.prototype.hasOwnProperty.call(value, key); });
    }
    function integer(value, fallback) {
        return typeof value === 'number' && isFinite(value) && Math.floor(value) === value ? value : fallback;
    }
    function boundedString(value, maximum) {
        return typeof value === 'string' && value.length <= maximum && !CONTROL_CHARACTERS.test(value);
    }
    function supportsChestItem(item) {
        return !!item && typeof item === 'object'
            && SUPPORTED_CHEST_NAMES[String(item.name || '')] === true;
    }
    function validEmergencyInjection(value) {
        if (!ownKeys(value, ['v', 'enabled', 'physicalSlot', 'itemKey', 'status'])
                || value.v !== 1 || typeof value.enabled !== 'boolean'
                || integer(value.physicalSlot, -2) < -1 || integer(value.physicalSlot, -2) > 7
                || !boundedString(value.itemKey, 160)) return false;
        if (value.enabled) return value.physicalSlot >= 0 && value.itemKey.trim().length > 0
            && ['authorized', 'empty', 'item_changed'].indexOf(value.status) >= 0;
        return value.physicalSlot === -1 && value.itemKey === ''
            && (value.status === 'disabled' || value.status === 'unsupported_config');
    }
    function validChestTarget(target) {
        if (!target || typeof target !== 'object' || Array.isArray(target)) return false;
        if (target.kind === 'loadout') {
            if (target.slotKey !== '上装装备') return false;
            if (!Object.prototype.hasOwnProperty.call(target, 'expectedLoadoutRevision')) {
                return ownKeys(target, ['kind', 'slotKey']);
            }
            var rev = integer(target.expectedLoadoutRevision, -1);
            return ownKeys(target, ['kind', 'slotKey', 'expectedLoadoutRevision'])
                && rev >= 0 && rev <= 2147483647;
        }
        if (target.kind === 'backpack') {
            var slot = integer(target.slot, -1);
            var lease = String(target.expectedLease || '');
            return ownKeys(target, ['kind', 'containerId', 'slot', 'expectedLease'])
                && target.containerId === '背包'
                && slot >= 0 && slot <= 49
                && /^[A-Za-z0-9._~-]{1,128}$/.test(lease);
        }
        return false;
    }
    function chestTargetFromSource(source, loadoutRevision) {
        if (!source || typeof source !== 'object') return null;
        var kind = String(source.sourceKind || source.kind || '');
        var slotKey = String(source.slotKey || source.slot || '');
        if ((kind === 'wearer' || kind === 'loadout' || kind === 'equipment')
                && slotKey === '上装装备') {
            var rev = integer(loadoutRevision, -1);
            var loadoutTarget = {kind:'loadout', slotKey:'上装装备'};
            if (rev >= 0 && rev <= 2147483647) loadoutTarget.expectedLoadoutRevision = rev;
            return loadoutTarget;
        }
        if ((kind === 'inventory' || kind === 'backpack')
                && String(source.containerId || '') === '背包') {
            var slot = integer(source.slot, -1);
            var lease = String(source.expectedLease || '');
            return slot >= 0 && slot <= 49 && /^[A-Za-z0-9._~-]{1,128}$/.test(lease)
                ? {kind:'backpack', containerId:'背包', slot:slot, expectedLease:lease} : null;
        }
        return null;
    }
    function slotPresentation(snapshot, slot) {
        var rows = snapshot && Array.isArray(snapshot.drugs) ? snapshot.drugs : [];
        var row = rows[slot] || null;
        var bank = Math.floor(slot / 4);
        var bankLabel = bank === 0 ? 'I' : 'II';
        var fallbackKey = ['7', '8', '9', '0'][slot % 4];
        var keyLabel = row && row.keyLabel ? String(row.keyLabel) : fallbackKey;
        return {
            slot:slot,
            bank:bank,
            bankLabel:bankLabel,
            keyLabel:keyLabel,
            shortcutLabel:bankLabel + '-[' + keyLabel + ']',
            row:row
        };
    }
    function drugDefinitions(snapshot, definitions) {
        var meta = snapshot && snapshot.drugMeta || {};
        return definitions.map(function(definition) {
            var row = meta[definition.id] || null;
            return {
                id:definition.id,
                label:row && row.keyLabel
                    ? row.keyLabel : definition.label,
                physicalSlot:definition.physicalSlot,
                bank:definition.bank,
                lane:definition.lane,
                drugMeta:row
            };
        });
    }
    function switchSummary(layout) {
        if (!layout) return '';
        var key = String(layout.switchKeyLabel || '未绑定');
        var cooldown = layout.switchCooldown || {};
        if (cooldown.ready === true) return key + ' 切换';
        var seconds = Math.max(0, Number(cooldown.remainingMs) || 0) / 1000;
        return key + ' 切换 · 冷却 ' + seconds.toFixed(1) + 's';
    }
    function copyChestTarget(target) {
        if (target.kind === 'backpack') {
            return {
                kind:'backpack',
                containerId:'背包',
                slot:target.slot,
                expectedLease:target.expectedLease
            };
        }
        var copy = {kind:'loadout', slotKey:'上装装备'};
        if (Object.prototype.hasOwnProperty.call(target, 'expectedLoadoutRevision')) {
            copy.expectedLoadoutRevision = target.expectedLoadoutRevision;
        }
        return copy;
    }
    function intent(snapshot, chestTarget, enabled, target) {
        if (!snapshot || typeof enabled !== 'boolean' || !validChestTarget(chestTarget)) return null;
        var slot = enabled && target && target.kind === 'drug' ? target.drugSlot : -1;
        var row = slot >= 0 && snapshot.drugs && snapshot.drugs[slot];
        if (enabled && (!row || !row.occupied || !row.item)) return null;
        return {cmd:'configureEmergencyInjection', chestTarget:copyChestTarget(chestTarget),
            enabled:enabled, drugSlot:slot, expectedItemName:enabled ? row.item.name : ''};
    }
    function sameEmergencyState(left, right) {
        return !!left && !!right
            && left.v === right.v
            && left.enabled === right.enabled
            && left.physicalSlot === right.physicalSlot
            && left.itemKey === right.itemKey
            && left.status === right.status;
    }
    function validMutationProof(response, expected) {
        if (!response || !response.payload || !expected || !validChestTarget(expected.chestTarget)) {
            return false;
        }
        var targetCfg = response.payload.targetEmergencyInjection;
        var expectedAffected = expected.chestTarget.kind === 'backpack'
            ? expected.chestTarget.slot : -1;
        if (response.affectedBackpackSlot !== expectedAffected || !validEmergencyInjection(targetCfg)) {
            return false;
        }
        if (targetCfg.enabled !== expected.enabled || targetCfg.physicalSlot !== expected.drugSlot
                || targetCfg.itemKey !== expected.expectedItemName
                || targetCfg.status !== (targetCfg.enabled ? 'authorized' : 'disabled')) {
            return false;
        }
        if (expected.chestTarget.kind === 'loadout') {
            var wornCfg = response.payload.emergencyInjection;
            if (!validEmergencyInjection(wornCfg) || !sameEmergencyState(wornCfg, targetCfg)) {
                return false;
            }
        }
        return true;
    }
    function buildChestTargetPayload(target, stateLoadoutRevision, integerFn, tokenFn) {
        if (!validChestTarget(target)) return null;
        if (target.kind === 'loadout') {
            var hasRev = Object.prototype.hasOwnProperty.call(target, 'expectedLoadoutRevision');
            var loadoutRev = integerFn(hasRev ? target.expectedLoadoutRevision : stateLoadoutRevision, 0, 2147483647);
            return loadoutRev === null ? null : {kind:'loadout', slotKey:'上装装备', expectedLoadoutRevision:loadoutRev};
        }
        var slot = integerFn(target.slot, 0, 49);
        var lease = tokenFn(target.expectedLease);
        return slot === null || !lease ? null : {kind:'backpack', containerId:'背包', slot:slot, expectedLease:lease};
    }
    function validEmergencyAgainstDrugs(cfg, drugs) {
        if (!cfg || !cfg.enabled) return true;
        var row = drugs[cfg.physicalSlot];
        var same = row.occupied && row.item.name === cfg.itemKey;
        return cfg.status === 'authorized' ? same
            : cfg.status === 'empty' ? !row.occupied : row.occupied && !same;
    }
    function validProjectionEmergency(payload) {
        var cfg = payload.emergencyInjection;
        if (cfg && !validEmergencyAgainstDrugs(cfg, payload.drugs)) return false;
        if (payload.targetEmergencyInjection
                && !validEmergencyAgainstDrugs(payload.targetEmergencyInjection, payload.drugs)) return false;
        var wornChestRow = null;
        for (var i = 0; i < payload.equipment.length; i++) {
            var eqRow = payload.equipment[i];
            if (eqRow.slotKey === '上装装备') wornChestRow = eqRow;
            if (eqRow.occupied === true && eqRow.item && eqRow.item.emergencyInjection) {
                if (!validEmergencyAgainstDrugs(eqRow.item.emergencyInjection, payload.drugs)) return false;
            }
        }
        if (cfg) {
            var chestItem = wornChestRow && wornChestRow.occupied === true ? wornChestRow.item : null;
            if (chestItem && supportsChestItem(chestItem)) {
                if (chestItem.emergencyInjection
                        && !sameEmergencyState(cfg, chestItem.emergencyInjection)) return false;
            } else if (cfg.enabled || cfg.status !== 'disabled') {
                return false;
            }
        }
        return true;
    }
    return {supportsChestItem:supportsChestItem, validEmergencyInjection:validEmergencyInjection,
        validChestTarget:validChestTarget, chestTargetFromSource:chestTargetFromSource,
        buildChestTargetPayload:buildChestTargetPayload,
        validProjectionEmergency:validProjectionEmergency,
        slotPresentation:slotPresentation, validMutationProof:validMutationProof,
        sameEmergencyState:sameEmergencyState,
        drugDefinitions:drugDefinitions, switchSummary:switchSummary, intent:intent};
});
