/**
 * Pure character-build mutation descriptors and response proofs.
 *
 * Session owns transport/state; controller owns UI and the inventory write gate.
 * This leaf only reconstructs the four frozen commands and validates their two
 * authoritative write-after projections.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildMutation = api;
        root.CharacterBuildMutation = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var MUTATIONS = {
        equipEquipment:true,
        unequipEquipment:true,
        equipDrug:true,
        unequipDrug:true
    };

    function integer(value, min, max) {
        value = Number(value);
        return isFinite(value) && Math.floor(value) === value
            && value >= min && value <= max ? value : null;
    }
    function token(value) {
        value = String(value || '');
        return /^[A-Za-z0-9._~-]{1,128}$/.test(value) ? value : '';
    }
    function own(value, key) {
        return Object.prototype.hasOwnProperty.call(value || {}, key);
    }
    function validIdentityTriple(value) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
        var keys = ['name', 'displayName', 'icon'];
        for (var i = 0; i < keys.length; i++) {
            var text = value[keys[i]];
            if (typeof text !== 'string' || text.length > 256
                    || text.trim().length === 0
                    || text.trim().toLowerCase() === 'undefined') return false;
        }
        return true;
    }
    function validItemIdentity(item) {
        if (!validIdentityTriple(item)) return false;
        if (own(item, 'modSlots')) {
            if (!Array.isArray(item.modSlots) || item.modSlots.length > 3) return false;
            for (var i = 0; i < item.modSlots.length; i++) {
                if (!validIdentityTriple(item.modSlots[i])) return false;
            }
        }
        return !own(item, 'modMeta') || item.modMeta === null
            || validIdentityTriple(item.modMeta);
    }
    function sourceForCandidate(candidate) {
        var raw = candidate && candidate.raw || {};
        var source = raw.source || {};
        var slot = integer(raw.physicalSlot, 0, 49);
        var lease = token(source.expectedLease);
        return slot === null || !lease ? null : {
            containerId:'背包',
            slot:slot,
            expectedLease:lease
        };
    }
    function equipIntent(target, candidate) {
        var source = sourceForCandidate(candidate);
        if (!target || !source || candidate.blocked === true) return null;
        if (target.kind === 'equipment' && String(target.slotKey || '')) {
            return {cmd:'equipEquipment', slotKey:String(target.slotKey), source:source};
        }
        var drugSlot = integer(target.drugSlot, 0, 3);
        return target.kind === 'drug' && drugSlot !== null
            ? {cmd:'equipDrug', drugSlot:drugSlot, source:source} : null;
    }
    function unequipIntent(target) {
        if (!target) return null;
        if (target.kind === 'equipment' && String(target.slotKey || '')) {
            return {cmd:'unequipEquipment', slotKey:String(target.slotKey)};
        }
        var drugSlot = integer(target.drugSlot, 0, 3);
        return target.kind === 'drug' && drugSlot !== null
            ? {cmd:'unequipDrug', drugSlot:drugSlot} : null;
    }
    function buildPayload(intent, state) {
        if (!intent || !state || !MUTATIONS[intent.cmd]) return null;
        var payload = {v:1, sessionGeneration:integer(state.sessionGeneration, 1, 2147483647)};
        var equipment = intent.cmd === 'equipEquipment' || intent.cmd === 'unequipEquipment';
        var equip = intent.cmd === 'equipEquipment' || intent.cmd === 'equipDrug';
        if (payload.sessionGeneration === null) return null;
        if (equipment) {
            if (!String(intent.slotKey || '')) return null;
            payload.expectedLoadoutRevision = integer(state.loadoutRevision, 0, 2147483647);
            payload.slotKey = String(intent.slotKey);
        } else {
            payload.expectedDrugRevision = integer(state.drugRevision, 0, 2147483647);
            payload.drugSlot = integer(intent.drugSlot, 0, 3);
        }
        if ((equipment ? payload.expectedLoadoutRevision : payload.expectedDrugRevision) === null
                || (!equipment && payload.drugSlot === null)) return null;
        if (equip) {
            var source = intent.source || {};
            var sourceSlot = integer(source.slot, 0, 49);
            var lease = token(source.expectedLease);
            if (source.containerId !== '背包' || sourceSlot === null || !lease) return null;
            payload.source = {containerId:'背包', slot:sourceSlot, expectedLease:lease};
        }
        return payload;
    }
    function validFullBackpackSnapshots(snapshots) {
        var snapshot = Array.isArray(snapshots) && snapshots.length === 1
            ? snapshots[0] : null;
        if (!snapshot || snapshot.containerId !== '背包'
                || Number(snapshot.capacity) !== 50
                || Number(snapshot.accessibleCapacity) !== 50
                || Number(snapshot.offset) !== 0
                || Number(snapshot.limit) !== 50
                || !Array.isArray(snapshot.slots)
                || snapshot.slots.length !== 50) return false;
        for (var i = 0; i < snapshot.slots.length; i++) {
            var slot = snapshot.slots[i];
            if (!slot || typeof slot !== 'object') return false;
            if (slot.occupied === true && !validItemIdentity(slot.item)) return false;
            if (slot.item != null && !validItemIdentity(slot.item)) return false;
        }
        return true;
    }
    function validMutationResult(response, command, validProjection, expectedSourceSlot) {
        if (!response || MUTATIONS[command] !== true
                || response.operation !== command
                || typeof response.changed !== 'boolean'
                || integer(response.affectedBackpackSlot, 0, 49) === null
                || !validProjection(response.payload)
                || !validFullBackpackSnapshots(response.inventorySnapshots)) return false;
        return command.indexOf('equip') !== 0
            || response.affectedBackpackSlot === expectedSourceSlot;
    }

    function MutationCoordinator(options) {
        options = options || {};
        if (!options.session) throw new Error('MutationCoordinator requires a session');
        this._session = options.session;
        this._ports = options.ports || {};
        this._onApplied = typeof options.onApplied === 'function' ? options.onApplied : function() {};
        this._inventoryWrite = null;
        this._pending = null;
    }
    MutationCoordinator.prototype._completeInventory = function(snapshots) {
        var operation = this._inventoryWrite;
        this._inventoryWrite = null;
        return operation && this._ports.completeExternalWrite
            ? this._ports.completeExternalWrite(operation, snapshots || null) : true;
    };
    MutationCoordinator.prototype._result = function(response, accepted, unknown) {
        if (!this._pending) return;
        if (accepted) {
            this._completeInventory(response.inventorySnapshots);
            this._pending = null;
            this._onApplied(response);
            if (this._ports.toast) this._ports.toast(response.cmd === 'snapshot'
                ? '角色构筑写入结果已确认。'
                : response.changed ? '角色构筑已更新。' : '当前构筑已是目标状态。');
            return;
        }
        if (unknown) {
            if (!this._pending.reconcileAttempted) {
                this._pending.reconcileAttempted = true;
                this._session.reconcileMutation(this._result.bind(this));
            } else if (this._ports.toast) {
                this._ports.toast('写入结果仍未确认，请使用“重新确认结果”。');
            }
            return;
        }
        this._completeInventory(null);
        this._pending = null;
    };
    MutationCoordinator.prototype.start = function(intent) {
        if (!intent || this._pending || this._session.getState() !== 'idle') return false;
        var operation = this._ports.beginExternalWrite
            ? this._ports.beginExternalWrite('character-build.' + intent.cmd) : {local:true};
        if (!operation) {
            if (this._ports.toast) this._ports.toast('背包正在处理另一项操作。');
            return false;
        }
        this._inventoryWrite = operation;
        this._pending = {reconcileAttempted:false};
        var done = this._result.bind(this), callId = null;
        if (intent.cmd === 'equipEquipment') {
            callId = this._session.equipEquipment(intent.slotKey, intent.source, done);
        } else if (intent.cmd === 'unequipEquipment') {
            callId = this._session.unequipEquipment(intent.slotKey, done);
        } else if (intent.cmd === 'equipDrug') {
            callId = this._session.equipDrug(intent.drugSlot, intent.source, done);
        } else if (intent.cmd === 'unequipDrug') {
            callId = this._session.unequipDrug(intent.drugSlot, done);
        }
        if (!callId) {
            this._completeInventory(null);
            this._pending = null;
        }
        return !!callId;
    };
    MutationCoordinator.prototype.equip = function(target, candidate) {
        var intent = equipIntent(target, candidate);
        if (!intent && this._ports.toast) this._ports.toast('该候选当前不可装备。');
        return intent ? this.start(intent) : false;
    };
    MutationCoordinator.prototype.unequip = function(target) {
        return this.start(unequipIntent(target));
    };
    MutationCoordinator.prototype.reconcile = function() {
        if (!this._pending || this._session.getState() !== 'needs_reconcile') return false;
        this._pending.reconcileAttempted = true;
        return !!this._session.reconcileMutation(this._result.bind(this));
    };
    MutationCoordinator.prototype.destroy = function() {
        this._inventoryWrite = null;
        this._pending = null;
    };
    MutationCoordinator.prototype.isPending = function() { return !!this._pending; };

    return {
        commands:Object.keys(MUTATIONS),
        buildPayload:buildPayload,
        validItemIdentity:validItemIdentity,
        validFullBackpackSnapshots:validFullBackpackSnapshots,
        validMutationResult:validMutationResult,
        MutationCoordinator:MutationCoordinator
    };
});
