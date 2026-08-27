/** Quick-transfer intent queue. Explicit batch commits and immediate single writes use separate authority ports. */
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
                || typeof options.autoTransferBatch !== 'function' || typeof options.slotRef !== 'function') {
            throw new Error('QuickTransferController requires getSlot, slotRef, autoTransfer, and autoTransferBatch ports');
        }
        this._getSlot = options.getSlot;
        this._autoTransfer = options.autoTransfer;
        this._autoTransferBatch = options.autoTransferBatch;
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
        this._batchInFlight = [];
        this._committing = false;
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
            && (!state.busyOwner || state.busyOwner === 'inventory.autoTransfer'
                || state.busyOwner === 'inventory.autoTransferBatch');
    };
    QuickTransferController.prototype.setMode = function(mode) {
        if (mode !== 'deposit' && mode !== 'withdraw') return false;
        if (this._mode === mode) return this.exit();
        if (!this._authorityReady()) { this._onNotice('not_ready'); return false; }
        if (this._inFlight || this._batchInFlight.length || this._committing) { this._onNotice('in_flight'); return false; }
        this._clearPending();
        this._mode = mode;
        this._completed = 0;
        this._accepted = 0;
        this._emit();
        return true;
    };
    QuickTransferController.prototype.exit = function() {
        if (this._inFlight || this._batchInFlight.length || this._committing) return false;
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
        this._batchInFlight = [];
        this._committing = false;
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
        if (context.viewMode === 'tuning'
                || (context.profile !== 'warehouse' && context.profile !== 'battlebox')) return false;
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
        if (context.slot && context.slot.occupied) {
            this.enqueue(context.containerId, context.slot, !!this._mode);
        }
        return true;
    };
    QuickTransferController.prototype.enqueue = function(containerId, slot, deferStart) {
        deferStart = deferStart == null ? !!this._mode : !!deferStart;
        if (!this._authorityReady()) { this._onNotice('busy'); return false; }
        if (this._committing && this._mode) { this._onNotice('in_flight'); return false; }
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
        if (this._pending.length + (this._inFlight ? 1 : 0) + this._batchInFlight.length >= this._limit) {
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
        if (!deferStart) {
            this._committing = true;
            this._drain();
        }
        return true;
    };
    QuickTransferController.prototype.commit = function() {
        if (!this._mode) { this._onNotice('no_mode'); return false; }
        if (!this._authorityReady()) { this._onNotice('busy'); return false; }
        if (this._inFlight || this._batchInFlight.length || this._committing) { this._onNotice('in_flight'); return false; }
        if (!this._pending.length) { this._onNotice('nothing_selected'); return false; }
        this._committing = true;
        this._emit();
        return this._commitBatch();
    };
    QuickTransferController.prototype._commitBatch = function() {
        var self = this;
        if (!this._committing || !this._mode || this._inFlight
                || this._batchInFlight.length || !this._pending.length) return false;
        var entries = this._pending.slice();
        var sources = [];
        var targetContainerId = entries[0].targetContainerId;
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            var currentSlot = this._getSlot(entry.containerId, entry.slot);
            if (!currentSlot || !currentSlot.occupied
                    || slotSignature(currentSlot) !== entry.signature
                    || entry.targetContainerId !== targetContainerId) {
                this._halt({success:false, error:'stale_state'});
                return false;
            }
            sources.push(this._slotRef(entry.containerId, currentSlot));
        }
        this._pending = [];
        this._batchInFlight = entries;
        this._emit();
        var generation = this._getGeneration();
        var settled = false;
        function done(result) {
            if (settled) return;
            settled = true;
            if (!self._isGenerationCurrent(generation) || self._batchInFlight !== entries) return;
            var completedCount = result == null ? NaN : result.completedCount;
            var exactCount = typeof completedCount === 'number' && isFinite(completedCount)
                && Math.floor(completedCount) === completedCount
                && completedCount >= 1 && completedCount <= entries.length;
            if (result && result.success === true && exactCount
                    && !result.failure && completedCount === entries.length) {
                self._finishBatch(completedCount, null);
                return;
            }
            var failureIndex = result && result.failure == null
                ? NaN : result.failure.index;
            if (result && result.success === true && exactCount
                    && result.failure && !Array.isArray(result.failure)
                    && result.failure.error === 'target_full'
                    && typeof failureIndex === 'number' && isFinite(failureIndex)
                    && Math.floor(failureIndex) === failureIndex
                    && failureIndex === completedCount && completedCount < entries.length) {
                self._finishBatch(completedCount, {
                    success:true,
                    error:'target_full',
                    failure:{index:failureIndex, error:'target_full'},
                    completedCount:completedCount
                });
                return;
            }
            self._halt(result && result.success === true
                ? {success:false, error:'invalid_response'}
                : result || {success:false, error:'invalid_response'});
        }
        var started = false;
        try {
            started = this._autoTransferBatch(sources, targetContainerId, done);
        } catch (error) {
            done({success:false, error:error});
            return false;
        }
        if (!started && !settled) {
            settled = true;
            this._halt({success:false, error:'busy'});
        }
        return !!started;
    };
    QuickTransferController.prototype._finishBatch = function(completedCount, failure) {
        for (var i = 0; i < this._batchInFlight.length; i++) {
            delete this._entries[this._batchInFlight[i].key];
        }
        this._batchInFlight = [];
        this._completed += Number(completedCount);
        this._committing = false;
        this._mode = null;
        this._emit();
        if (failure) this._onError(failure);
    };
    QuickTransferController.prototype._drain = function() {
        var self = this;
        if (!this._committing || this._inFlight || this._batchInFlight.length || !this._pending.length) return false;
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
                if (!self._isGenerationCurrent(generation) || self._inFlight !== entry) return;
                delete self._entries[entry.key];
                self._inFlight = null;
                if (result && result.success === true) {
                    self._completed++;
                    if (self._pending.length) {
                        self._emit();
                        self._drain();
                    } else {
                        self._committing = false;
                        self._mode = null;
                        self._emit();
                    }
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
        if (this._inFlight) delete this._entries[this._inFlight.key];
        this._inFlight = null;
        for (var i = 0; i < this._batchInFlight.length; i++) {
            delete this._entries[this._batchInFlight[i].key];
        }
        this._batchInFlight = [];
        this._clearPending();
        this._committing = false;
        this._mode = null;
        this._emit();
        this._onError(result || {success:false, error:'invalid_response'});
    };
    QuickTransferController.prototype.isBusy = function() {
        return !!this._inFlight || !!this._batchInFlight.length || this._committing;
    };
    QuickTransferController.prototype.getMode = function() { return this._mode; };
    QuickTransferController.prototype.debugState = function() {
        var batchKeys = {};
        var inFlightKeys = [];
        for (var batchIndex = 0; batchIndex < this._batchInFlight.length; batchIndex++) {
            batchKeys[this._batchInFlight[batchIndex].key] = true;
            inFlightKeys.push(this._batchInFlight[batchIndex].key);
        }
        if (this._inFlight) inFlightKeys.push(this._inFlight.key);
        var entries = {};
        for (var key in this._entries) entries[key] = {
            key:this._entries[key].key,
            containerId:this._entries[key].containerId,
            slot:this._entries[key].slot,
            targetContainerId:this._entries[key].targetContainerId,
            inflight:!!(batchKeys[key] || (this._inFlight && this._inFlight.key === key))
        };
        return {
            mode:this._mode,
            pending:this._pending.length,
            pendingCount:this._pending.length,
            inFlight:this._inFlight ? this._inFlight.key : null,
            inflight:this._inFlight ? entries[this._inFlight.key] : null,
            inFlightKeys:inFlightKeys,
            inflightCount:inFlightKeys.length,
            queued:this._pending.length + inFlightKeys.length,
            staged:this._mode && !this._committing ? this._pending.length : 0,
            committing:this._committing,
            completed:this._completed,
            accepted:this._accepted,
            limit:this._limit,
            entries:entries
        };
    };

    function createCommandBar(options) {
        options = options || {};
        var document = options.document;
        if (!document) throw new Error('Quick-transfer command bar requires a document');
        var root = document.createElement('section');
        root.className = 'inventory-quick-transfer-bar';
        root.setAttribute('data-workbench-body-footer', '');
        root.setAttribute('aria-label', '批量转移');
        var statusNode = document.createElement('div');
        statusNode.className = 'inventory-quick-transfer-status';
        statusNode.setAttribute('role', 'status');
        statusNode.setAttribute('aria-live', 'polite');
        root.appendChild(statusNode);
        var modeGroup = document.createElement('div');
        modeGroup.className = 'inventory-quick-transfer-modes';
        modeGroup.setAttribute('role', 'group');
        modeGroup.setAttribute('aria-label', '批量转移方向');
        root.appendChild(modeGroup);

        function button(className, label, ariaLabel, onClick) {
            var node = document.createElement('button');
            node.type = 'button';
            node.className = 'workbench-mode-btn ' + className;
            node.textContent = label;
            node.setAttribute('aria-label', ariaLabel);
            node.addEventListener('click', onClick);
            return node;
        }
        function modeButton(mode, label, direction) {
            var node = button('inventory-quick-transfer-btn', label,
                label + '（' + direction + '）；选中多件后点击执行转移',
                function() { options.onMode(mode); });
            node.setAttribute('data-quick-mode', mode);
            node.setAttribute('data-audio-cue', 'toggle');
            node.setAttribute('aria-pressed', 'false');
            modeGroup.appendChild(node);
            return node;
        }
        var rightContainerId = String(options.rightContainerId || '仓库');
        var depositButton = modeButton('deposit', '批量存入', '背包 → ' + rightContainerId);
        var withdrawButton = modeButton('withdraw', '批量取出', rightContainerId + ' → 背包');
        var actions = document.createElement('div');
        actions.className = 'inventory-quick-transfer-actions';
        var cancelButton = button('inventory-quick-transfer-cancel', '退出批量',
            '取消当前批量选择并退出批量模式', options.onCancel);
        cancelButton.setAttribute('data-audio-cue', 'back');
        var commitButton = button('inventory-quick-transfer-commit', '执行转移',
            '一次执行当前选中的批量转移', options.onCommit);
        commitButton.setAttribute('data-audio-cue', 'activate');
        actions.appendChild(cancelButton);
        actions.appendChild(commitButton);
        root.appendChild(actions);

        function update(state, context) {
            state = state || {};
            context = context || {};
            var mode = state.mode || '';
            depositButton.classList.toggle('active', mode === 'deposit');
            depositButton.setAttribute('aria-pressed', mode === 'deposit' ? 'true' : 'false');
            withdrawButton.classList.toggle('active', mode === 'withdraw');
            withdrawButton.setAttribute('aria-pressed', mode === 'withdraw' ? 'true' : 'false');
            root.hidden = context.visible === false;
            root.setAttribute('data-mode', mode);
            root.setAttribute('data-staged', String(state.staged || 0));
            root.classList.toggle('active', !!mode);
            root.classList.toggle('busy', !!state.committing);
            commitButton.hidden = !mode && !state.committing;
            commitButton.textContent = state.committing ? '转移中…'
                : '执行转移（' + Number(state.pending || 0) + '）';
            cancelButton.hidden = !mode || !!state.committing;
            cancelButton.disabled = !!state.committing;
            statusNode.textContent = mode === 'deposit'
                ? '批量存入：选择背包物品后执行'
                : mode === 'withdraw'
                    ? '批量取出：选择' + rightContainerId + '物品后执行'
                    : 'Ctrl+单击：单件快速转移';
            if (state.committing) {
                statusNode.textContent += ' · 待处理 ' + state.queued + ' · 已完成 ' + state.completed;
            } else if (state.staged) {
                statusNode.textContent += ' · 已选 ' + state.staged;
            } else if (state.completed) {
                statusNode.textContent += ' · 已完成 ' + state.completed;
            }
        }
        return {
            root:root,
            statusNode:statusNode,
            depositButton:depositButton,
            withdrawButton:withdrawButton,
            cancelButton:cancelButton,
            commitButton:commitButton,
            update:update
        };
    }

    return {
        QuickTransferController:QuickTransferController,
        createCommandBar:createCommandBar,
        keyOf:keyOf,
        slotSignature:slotSignature
    };
});
