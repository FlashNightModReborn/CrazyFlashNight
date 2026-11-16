/** Potion selection and emergency authorization controls; writes remain in the session. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CharacterBuildDrugControls = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';
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
    function validEmergencyInjection(value) {
        if (!ownKeys(value, ['v', 'enabled', 'physicalSlot', 'itemKey', 'status'])
                || value.v !== 1 || typeof value.enabled !== 'boolean'
                || integer(value.physicalSlot, -2) < -1 || integer(value.physicalSlot, -2) > 7
                || !boundedString(value.itemKey, 160)) return false;
        if (value.enabled) return value.physicalSlot >= 0 && value.itemKey.trim().length > 0
            && ['authorized', 'empty', 'item_changed'].indexOf(value.status) >= 0;
        return value.status === 'disabled' || value.status === 'unsupported_config'
            && value.physicalSlot === -1 && value.itemKey === '';
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
    function intent(snapshot, enabled, target) {
        if (!snapshot || !snapshot.emergencyInjection || typeof enabled !== 'boolean') return null;
        var slot = enabled && target && target.kind === 'drug' ? target.drugSlot : -1;
        var row = slot >= 0 && snapshot.drugs && snapshot.drugs[slot];
        if (enabled && (!row || !row.occupied || !row.item)) return null;
        return {cmd:'configureEmergencyInjection', enabled:enabled,
            drugSlot:slot, expectedItemName:enabled ? row.item.name : ''};
    }
    function validMutationProof(response, expected) {
        var cfg = response.payload.emergencyInjection;
        return response.affectedBackpackSlot === -1 && !!expected && !!cfg
            && cfg.enabled === expected.enabled && cfg.physicalSlot === expected.drugSlot
            && cfg.itemKey === expected.expectedItemName
            && cfg.status === (cfg.enabled ? 'authorized' : 'disabled');
    }
    function installView(prototype) {
        var mount = prototype.mount;
        prototype.mount = function(parent) {
            var result = mount.call(this, parent), self = this, root = this.root;
            if (!result || this._emergencyBoundRoot === root) return result;
            this._emergencyBoundRoot = root;
            this._emergencyRow = root.querySelector('[data-emergency-row]');
            this._emergencyStatus = root.querySelector('[data-emergency-status]');
            this._emergencyAuthorize = root.querySelector('[data-build-action="emergencyAuthorize"]');
            this._emergencyDisable = root.querySelector('[data-build-action="emergencyDisable"]');
            function click(event) {
                var node = event.target.closest('[data-build-action]');
                if (!node || !root.contains(node) || node.disabled) return;
                var action = node.getAttribute('data-build-action');
                if (action === 'emergencyAuthorize') self._onEmergencyInjection(true);
                else if (action === 'emergencyDisable') self._onEmergencyInjection(false);
            }
            root.addEventListener('click', click);
            this._listeners.push(function() { root.removeEventListener('click', click); });
            return result;
        };
        prototype.syncEmergencyInjection = function() {
            if (!this._emergencyRow) return false;
            var cfg = this._snapshot && this._snapshot.emergencyInjection;
            this._emergencyRow.hidden = !cfg;
            if (!cfg) return false;
            var selected = /(?:^|:)drug([1-8])$/.exec(String(this._selectedSlotKey || ''));
            var slot = selected ? Number(selected[1]) - 1 : -1;
            var item = slot >= 0 && this._snapshot.drugs && this._snapshot.drugs['drug' + (slot + 1)];
            var locked = this._interactionState !== 'idle' || this._itemUseState !== 'idle';
            this._emergencyStatus.textContent = cfg.status === 'unsupported_config' ? '应急注射：配置暂不可用'
                : cfg.enabled ? '应急药：第' + (Math.floor(cfg.physicalSlot / 4) + 1) + '组'
                    + (cfg.physicalSlot % 4 + 1) + '号 · ' + cfg.itemKey
                    + (cfg.status === 'empty' ? '（待补充）' : '') : '应急注射：关闭 · 先选择药剂槽';
            this._emergencyAuthorize.disabled = locked || !item || !item.presentation
                || cfg.status === 'unsupported_config'
                || cfg.enabled && cfg.physicalSlot === slot && cfg.itemKey === item.presentation.name;
            this._emergencyAuthorize.setAttribute('aria-label', item && item.presentation
                ? '将' + item.presentation.name + '设为两套61五甲共用的应急药，换药需重新授权'
                : '先选择一个已装入药品的槽位');
            this._emergencyDisable.setAttribute('aria-label', '关闭应急自动注射');
            this._emergencyDisable.hidden = !cfg.enabled;
            this._emergencyDisable.disabled = locked;
            return true;
        };
        ['_syncSlotSelection', 'setInteractionState', 'setItemUseState'].forEach(function(name) {
            var original = prototype[name];
            prototype[name] = function() {
                var result = original.apply(this, arguments);
                this.syncEmergencyInjection();
                return result;
            };
        });
    }
    return {validEmergencyInjection:validEmergencyInjection, validMutationProof:validMutationProof,
        drugDefinitions:drugDefinitions, switchSummary:switchSummary, intent:intent, installView:installView};
});
