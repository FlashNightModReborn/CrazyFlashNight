/** Serialized quick-transfer intent queue. Authority is supplied through explicit ports. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryWorkbenchQuickTransfer = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function noop() {}
    function keyOf(containerId, physicalSlot) { return String(containerId) + ':' + Number(physicalSlot); }
    function slotSignature(slot) {
        var item = slot && slot.item ? slot.item : {};
        var confirm = slot && slot.confirmProjection ? slot.confirmProjection : item;
        return [
            String(item.name || ''),
            String(confirm.itemKind || item.itemKind || ''),
            String(confirm.displayName || item.displayName || ''),
            Number(confirm.quantity == null ? item.quantity : confirm.quantity),
            Number(confirm.enhancementLevel == null ? item.enhancementLevel || 0 : confirm.enhancementLevel),
            String(confirm.rarity || item.rarity || '')
        ].join('|');
    }

    function QuickTransferController(options) {
        options = options || {};
        if (typeof options.getSlot !== 'function' || typeof options.autoTransfer !== 'function'
                || typeof options.slotRef !== 'function') {
            throw new Error('QuickTransferController requires getSlot, slotRef, and autoTransfer ports');
        }
        this._getSlot = options.getSlot;
        this._autoTransfer = options.autoTransfer;
        this._slotRef = options.slotRef;
        this._getAuthorityState = typeof options.getAuthorityState === 'function'
            ? options.getAuthorityState : function() { return {ready:false}; };
        this._getGeneration = typeof options.getGeneration === 'function' ? options.getGeneration : function() { return 0; };
        this._isGenerationCurrent = typeof options.isGenerationCurrent === 'function'
            ? options.isGenerationCurrent : function() { return true; };
        this._onChange = typeof options.onChange === 'function' ? options.onChange : noop;
        this._onError = typeof options.onError === 'function' ? options.onError : noop;
        this._onNotice = typeof options.onNotice === 'function' ? options.onNotice : noop;
        this._rightContainerId = String(options.rightContainerId || '仓库');
        this._limit = Math.max(1, Number(options.limit || 24));
        this._mode = null;
        this._pending = [];
        this._inFlight = null;
        this._entries = {};
        this._completed = 0;
        this._accepted = 0;
    }

    QuickTransferController.prototype.configure = function(options) {
        options = options || {};
        if (options.rightContainerId) this._rightContainerId = String(options.rightContainerId);
        return true;
    };
    QuickTransferController.prototype._emit = function() { this._onChange(this.debugState()); };
    QuickTransferController.prototype._authorityReady = function() {
        var state = this._getAuthorityState() || {};
        return !!state.ready && !state.refreshRequired
            && (!state.busyOwner || state.busyOwner === 'inventory.autoTransfer');
    };
    QuickTransferController.prototype.setMode = function(mode) {
        if (mode !== 'deposit' && mode !== 'withdraw') return false;
        if (this._mode === mode) return this.exit();
        if (!this._authorityReady()) { this._onNotice('not_ready'); return false; }
        if (this._inFlight) { this._onNotice('in_flight'); return false; }
        this._clearPending();
        this._mode = mode;
        this._completed = 0;
        this._accepted = 0;
        this._emit();
        return true;
    };
    QuickTransferController.prototype.exit = function() {
        if (!this._mode && !this._pending.length) return false;
        this._mode = null;
        this._clearPending();
        this._emit();
        return true;
    };
    QuickTransferController.prototype.reset = function() {
        this._mode = null;
        this._pending = [];
        this._inFlight = null;
        this._entries = {};
        this._completed = 0;
        this._accepted = 0;
        this._emit();
        return true;
    };
    QuickTransferController.prototype._clearPending = function() {
        for (var i = 0; i < this._pending.length; i++) delete this._entries[this._pending[i].key];
        this._pending = [];
    };
    QuickTransferController.prototype.acceptClick = function(event, context) {
        context = context || {};
        if (context.viewMode === 'tuning' || context.profile !== 'warehouse') return false;
        var modifierRequested = !!(event && event.ctrlKey);
        if (!this._mode && !modifierRequested) return false;
        if (event) {
            if (event.preventDefault) event.preventDefault();
            if (event.stopPropagation) event.stopPropagation();
        }
        if (this._mode === 'deposit' && context.containerId !== '背包') {
            this._onNotice('deposit_source'); return true;
        }
        if (this._mode === 'withdraw' && context.containerId !== this._rightContainerId) {
            this._onNotice('withdraw_source'); return true;
        }
        if (context.slot && context.slot.occupied) this.enqueue(context.containerId, context.slot);
        return true;
    };
    QuickTransferController.prototype.enqueue = function(containerId, slot) {
        if (!this._authorityReady()) { this._onNotice('busy'); return false; }
        var key = keyOf(containerId, slot && slot.physicalSlot);
        if (this._inFlight && this._inFlight.key === key) { this._onNotice('already_in_flight'); return false; }
        if (this._entries[key]) {
            for (var i = 0; i < this._pending.length; i++) {
                if (this._pending[i].key !== key) continue;
                this._pending.splice(i, 1);
                delete this._entries[key];
                this._accepted = Math.max(this._completed, this._accepted - 1);
                this._emit();
                return true;
            }
        }
        if (this._pending.length + (this._inFlight ? 1 : 0) >= this._limit) {
            this._onNotice('queue_full'); return false;
        }
        if (!this._mode && !this._inFlight && !this._pending.length) {
            this._completed = 0;
            this._accepted = 0;
        }
        var entry = {
            key:key,
            containerId:String(containerId),
            slot:Number(slot.physicalSlot),
            signature:slotSignature(slot),
            targetContainerId:containerId === '背包' ? this._rightContainerId : '背包'
        };
        this._entries[key] = entry;
        this._pending.push(entry);
        this._accepted++;
        this._emit();
        this._drain();
        return true;
    };
    QuickTransferController.prototype._drain = function() {
        var self = this;
        if (this._inFlight || !this._pending.length) return false;
        var entry = this._pending.shift();
        var currentSlot = this._getSlot(entry.containerId, entry.slot);
        if (!currentSlot || !currentSlot.occupied || slotSignature(currentSlot) !== entry.signature) {
            delete this._entries[entry.key];
            this._halt({success:false, error:'stale_state'});
            return false;
        }
        this._inFlight = entry;
        this._emit();
        var generation = this._getGeneration();
        var settled = false;
        function done(result) {
                if (settled) return;
                settled = true;
                if (!self._isGenerationCurrent(generation)) return;
                delete self._entries[entry.key];
                self._inFlight = null;
                if (result && result.success === true) {
                    self._completed++;
                    self._emit();
                    self._drain();
                } else self._halt(result || {success:false, error:'invalid_response'});
            }
        var started = false;
        try {
            started = this._autoTransfer(this._slotRef(entry.containerId, currentSlot), entry.targetContainerId, done);
        } catch (error) {
            done({success:false, error:error});
            return false;
        }
        if (!started && !settled) {
            settled = true;
            delete this._entries[entry.key];
            this._inFlight = null;
            this._halt({success:false, error:'busy'});
        }
        return !!started;
    };
    QuickTransferController.prototype._halt = function(result) {
        this._clearPending();
        this._mode = null;
        this._emit();
        this._onError(result || {success:false, error:'invalid_response'});
    };
    QuickTransferController.prototype.isBusy = function() { return !!this._inFlight || this._pending.length > 0; };
    QuickTransferController.prototype.getMode = function() { return this._mode; };
    QuickTransferController.prototype.debugState = function() {
        var entries = {};
        for (var key in this._entries) entries[key] = {
            key:this._entries[key].key,
            containerId:this._entries[key].containerId,
            slot:this._entries[key].slot,
            targetContainerId:this._entries[key].targetContainerId,
            inflight:!!(this._inFlight && this._inFlight.key === key)
        };
        return {
            mode:this._mode,
            pending:this._pending.length,
            pendingCount:this._pending.length,
            inFlight:this._inFlight ? this._inFlight.key : null,
            inflight:this._inFlight ? entries[this._inFlight.key] : null,
            queued:this._pending.length + (this._inFlight ? 1 : 0),
            completed:this._completed,
            accepted:this._accepted,
            limit:this._limit,
            entries:entries
        };
    };

    return {QuickTransferController:QuickTransferController, keyOf:keyOf, slotSignature:slotSignature};
});
