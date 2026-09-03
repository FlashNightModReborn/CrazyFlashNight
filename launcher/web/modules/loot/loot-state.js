/** Pure loot-session coordinator. Flash remains the only inventory/reward authority. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.LootState = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var ACTIVE_STATES = {LOOT_ACTIVE:true};
    var TERMINAL_STATES = {CONSUMED:true, ABANDONED:true, EXPIRED:true};
    var AMBIGUOUS_ERRORS = {
        client_timeout:true, disconnected:true, malformed_response:true,
        reconcile_required:true, ack_unknown:true, not_sent:true, transport_closed:true
    };
    var CAPACITY_NO_WRITE_ERRORS = {
        target_full:true, inventory_full:true, capacity_reached:true, cap_reached:true
    };
    var STALE_ERRORS = {stale_lease:true, stale_state:true};
    var REFRESH_ONLY_ERRORS = {
        target_full:true, inventory_full:true, capacity_reached:true, cap_reached:true,
        stale_lease:true, stale_state:true, invalid_direction:true, invalid_target:true,
        unsupported_destination:true, slot_empty:true, terminal:true, expired:true,
        busy:true, operation_conflict:true
    };

    function own(value, key) { return Object.prototype.hasOwnProperty.call(value || {}, key); }
    function hasExactKeys(value, expected) {
        if (!value || typeof value !== 'object') return false;
        var keys = Object.keys(value);
        if (keys.length !== expected.length) return false;
        for (var i = 0; i < keys.length; i++) if (expected.indexOf(keys[i]) < 0) return false;
        return true;
    }
    function integer(value) {
        return typeof value === 'number' && isFinite(value) && Math.floor(value) === value
            ? value : null;
    }
    function text(value, limit) {
        return typeof value === 'string' && value.length > 0 && value.length <= (limit || 200)
            ? value : '';
    }
    function identityText(value, limit) {
        return typeof value === 'string' && value.length <= (limit || 256)
            && value.trim().length > 0 && value.trim().toLowerCase() !== 'undefined';
    }
    function boundedText(value, limit, allowEmpty) {
        return typeof value === 'string' && value.length <= limit
            && (allowEmpty || value.length > 0)
            && !/[\u0000-\u001f\u007f]/.test(value);
    }
    function validModIdentity(mod) {
        return !!mod && typeof mod === 'object' && !Array.isArray(mod)
            && identityText(mod.name) && identityText(mod.displayName)
            && identityText(mod.icon);
    }
    function validItemIdentity(item) {
        if (!item || typeof item !== 'object' || Array.isArray(item)) return false;
        if (!identityText(item.name) || !identityText(item.displayName)
                || !identityText(item.icon)) return false;
        if (own(item, 'modSlots')) {
            if (!Array.isArray(item.modSlots) || item.modSlots.length > 3) return false;
            for (var i = 0; i < item.modSlots.length; i++) {
                if (!validModIdentity(item.modSlots[i])) return false;
            }
        }
        return !own(item, 'modMeta') || item.modMeta === null
            || validModIdentity(item.modMeta);
    }
    function validConfirm(item, confirm) {
        var keys = ['itemKind','name','displayName','quantity','enhancementLevel',
            'rarity','tier','modSignature','lastUpdate'];
        if (!hasExactKeys(confirm, keys)
                || !identityText(confirm.name) || !identityText(confirm.displayName)) return false;
        var quantity = integer(confirm.quantity);
        var enhancement = integer(confirm.enhancementLevel);
        var lastUpdate = integer(confirm.lastUpdate);
        return boundedText(confirm.itemKind, 256, true)
            && boundedText(confirm.rarity, 256, true)
            && boundedText(confirm.tier, 256, true)
            && boundedText(confirm.modSignature, 1024, true)
            && quantity !== null && quantity >= 0
            && enhancement !== null && enhancement >= 0
            && lastUpdate !== null && lastUpdate >= 0
            && confirm.itemKind === item.itemKind
            && confirm.name === item.name
            && confirm.displayName === item.displayName
            && confirm.rarity === item.rarity
            && quantity === item.quantity
            && enhancement === item.enhancementLevel;
    }
    function opaque(value) {
        return typeof value === 'string' && value.length > 0 && value.length <= 128
            && /^[A-Za-z0-9._~-]+$/.test(value) ? value : '';
    }
    function safeWord(value) {
        return typeof value === 'string' && value.length > 0 && value.length <= 64
            && /^[a-z][a-z0-9_]*$/.test(value) ? value : '';
    }
    function clone(value) {
        if (value == null || typeof value !== 'object') return value;
        if (Array.isArray(value)) return value.map(clone);
        var result = {};
        for (var key in value) if (own(value, key)) result[key] = clone(value[key]);
        return result;
    }

    function normalizeRootIds(value) {
        if (!Array.isArray(value)||value.length>50) return null;
        var result=[],seen={};
        for (var i=0;i<value.length;i++) {
            var id=opaque(value[i]);
            if (!id||own(seen,id)) return null;
            seen[id]=true;result.push(id);
        }
        return result;
    }

    function normalizeRewardRoot(response,expectedRootId) {
        if (!response||typeof response!=='object'||Array.isArray(response)) return null;
        var rootId=opaque(response.rootOperationId);
        var status=String(response.rootStatus||'');
        var kind=String(response.resultKind||'');
        var stopReason=String(response.stopReason||'');
        var error=String(response.error||'');
        var appliedCount=integer(response.appliedCount);
        var result=response.result;
        if (!rootId||rootId.length>72||rootId!==String(expectedRootId||'')
                ||['not_started','pending','committed','terminal_failure','quarantined']
                    .indexOf(status)<0
                ||['none','in_progress','all_applied','partial_applied','no_effect_capacity',
                    'partial_failed','failed','quarantined'].indexOf(kind)<0
                ||stopReason!==''&&!safeWord(stopReason)
                ||error!==''&&!safeWord(error)
                ||appliedCount==null||appliedCount<0||appliedCount>50
                ||!hasExactKeys(result,
                    ['appliedEntryIds','blockedEntries','remainingEntryIds'])) return null;
        var applied=normalizeRootIds(result.appliedEntryIds);
        var remaining=normalizeRootIds(result.remainingEntryIds);
        if (!applied||!remaining||applied.length!==appliedCount
                ||!Array.isArray(result.blockedEntries)||result.blockedEntries.length>50)
            return null;
        var appliedSet={},remainingSet={},blockedSet={},blocked=[];
        for (var i=0;i<applied.length;i++) appliedSet[applied[i]]=true;
        for (i=0;i<remaining.length;i++) {
            if (own(appliedSet,remaining[i])) return null;
            remainingSet[remaining[i]]=true;
        }
        for (i=0;i<result.blockedEntries.length;i++) {
            var candidate=result.blockedEntries[i];
            var entryId=candidate&&opaque(candidate.entryId);
            var blockedError=candidate&&safeWord(candidate.error);
            if (!hasExactKeys(candidate,['entryId','error'])||!entryId||!blockedError
                    ||own(appliedSet,entryId)||own(blockedSet,entryId)) return null;
            blockedSet[entryId]=true;blocked.push({entryId:entryId,error:blockedError});
        }
        var exactCapacityRemainder=blocked.length===remaining.length;
        for (i=0;i<blocked.length;i++) {
            if (!own(remainingSet,blocked[i].entryId)
                    ||!own(CAPACITY_NO_WRITE_ERRORS,blocked[i].error)) {
                exactCapacityRemainder=false;
                break;
            }
        }
        var exact=false;
        if (status==='not_started') exact=kind==='none'&&!applied.length&&!blocked.length
            &&!remaining.length&&appliedCount===0&&!stopReason;
        else if (status==='pending') exact=kind==='in_progress';
        else if (status==='committed'&&kind==='all_applied') exact=applied.length>0
            &&!blocked.length&&!remaining.length&&!error;
        else if (status==='committed'&&kind==='partial_applied') exact=applied.length>0
            &&blocked.length>0&&remaining.length>0&&exactCapacityRemainder
            &&!error&&stopReason==='capacity_limited';
        else if (status==='terminal_failure'&&kind==='no_effect_capacity') exact=!applied.length
            &&blocked.length>0&&remaining.length>0&&exactCapacityRemainder
            &&own(CAPACITY_NO_WRITE_ERRORS,error)&&error===blocked[0].error
            &&stopReason==='capacity_limited';
        else if (status==='terminal_failure'&&kind==='partial_failed') exact=applied.length>0
            &&!!error&&stopReason==='child_failed';
        else if (status==='terminal_failure'&&kind==='failed') exact=!applied.length
            &&!!error&&stopReason==='child_failed';
        else if (status==='quarantined'&&kind==='quarantined') exact=!!error;
        if (!exact) return null;
        return {rootOperationId:rootId,rootStatus:status,resultKind:kind,
            result:{appliedEntryIds:applied,blockedEntries:blocked,remainingEntryIds:remaining},
            appliedCount:appliedCount,error:error,stopReason:stopReason};
    }

    function rewardRootCapacityReason(root) {
        if (!root||root.stopReason!=='capacity_limited'
                ||root.resultKind!=='partial_applied'
                    &&root.resultKind!=='no_effect_capacity'
                ||!root.result||!Array.isArray(root.result.blockedEntries)
                ||!root.result.blockedEntries.length) return '';
        var first='';
        for (var i=0;i<root.result.blockedEntries.length;i++) {
            var error=String(root.result.blockedEntries[i].error||'');
            if (!own(CAPACITY_NO_WRITE_ERRORS,error)) return '';
            if (!first||error==='target_full'||error==='inventory_full') first=error;
        }
        return first;
    }

    function normalizeSlot(value, fallbackIndex, requireLease, requireConfirm) {
        if (!value || typeof value !== 'object' || Array.isArray(value)
                || typeof value.occupied !== 'boolean') return null;
        var physicalSlot = integer(value.physicalSlot);
        if (physicalSlot == null || physicalSlot < 0) return null;
        var occupied = value.occupied === true;
        var lease = opaque(value.slotLease);
        if (!lease || (occupied && (!value.item || typeof value.item !== 'object'
                || Array.isArray(value.item)))) return null;
        if (occupied && !validItemIdentity(value.item)) return null;
        if (occupied && requireConfirm
                && (!own(value, 'confirmProjection')
                    || !validConfirm(value.item, value.confirmProjection))) return null;
        if (occupied && !requireConfirm && own(value, 'confirmProjection')
                && !validConfirm(value.item, value.confirmProjection)) return null;
        return {
            physicalSlot:physicalSlot,
            occupied:occupied,
            slotLease:lease,
            item:occupied ? clone(value.item) : null,
            confirmProjection:occupied && own(value, 'confirmProjection')
                ? clone(value.confirmProjection) : null,
            targetDomain:value.targetDomain == null ? '' : String(value.targetDomain),
            blockReason:value.blockReason == null ? '' : String(value.blockReason)
        };
    }

    function normalizeWindow(value, expectedId, complete, requireLease) {
        if (!value || typeof value !== 'object' || !Array.isArray(value.slots)) return null;
        var offset = integer(value.offset), limit = integer(value.limit), capacity = integer(value.capacity);
        var accessibleCapacity = integer(value.accessibleCapacity);
        var snapshotSeq = integer(value.snapshotSeq), containerVersion = integer(value.containerVersion);
        if (offset == null || limit == null || capacity == null || accessibleCapacity == null
                || snapshotSeq == null || containerVersion == null || offset < 0 || limit < 0
                || capacity < 1 || accessibleCapacity < 0 || accessibleCapacity > capacity
                || snapshotSeq < 0 || containerVersion < 0) return null;
        if (offset >= capacity || limit > capacity - offset) return null;
        if (complete && (offset !== 0 || limit !== capacity || value.slots.length !== capacity)) return null;
        if (!complete && value.slots.length !== limit) return null;
        var containerId = typeof value.containerId === 'string' ? value.containerId : '';
        if (containerId !== expectedId) return null;
        var slots = [], seen = {};
        for (var i = 0; i < value.slots.length; i++) {
            var slot = normalizeSlot(value.slots[i], offset + i, requireLease,
                expectedId === '背包');
            if (!slot || slot.physicalSlot < offset || slot.physicalSlot >= offset + limit
                    || seen[slot.physicalSlot]) return null;
            seen[slot.physicalSlot] = true;
            slots.push(slot);
        }
        return {
            containerId:containerId, offset:offset, limit:limit, capacity:capacity,
            accessibleCapacity:accessibleCapacity,
            snapshotSeq:snapshotSeq,
            containerVersion:containerVersion,
            closeLease:value.closeLease == null ? '' : String(value.closeLease),
            slots:slots
        };
    }

    function normalizedState(value) {
        if (value === 'LOOT_ACTIVE') return 'ACTIVE';
        if (value === 'LOOT_SUSPENDED') return 'SUSPENDED';
        return own(TERMINAL_STATES,value) ? value : '';
    }

    function projectionObject(response) {
        return response && typeof response === 'object' && !Array.isArray(response) ? response : null;
    }

    function normalizeProjection(response, identity, allowZeroSuspended) {
        var raw = projectionObject(response);
        if (!raw) return null;
        var state = normalizedState(raw.state);
        var authorityRevision = integer(raw.authorityRevision);
        if (!state || authorityRevision == null || authorityRevision < 0) return null;
        var lastAppliedOperationId = raw.lastAppliedOperationId === '' ? ''
            : opaque(raw.lastAppliedOperationId);
        var remainingCount = integer(raw.remainingCount);
        if (remainingCount == null || remainingCount < 0 || lastAppliedOperationId == null
                || raw.lastAppliedOperationId !== '' && !lastAppliedOperationId) return null;
        var result = {
            state:state,
            authorityRevision:authorityRevision,
            lastAppliedOperationId:lastAppliedOperationId,
            remainingCount:remainingCount,
            blockReason:raw.blockReason == null ? '' : String(raw.blockReason),
            closeLease:raw.closeLease === '' ? '' : opaque(raw.closeLease),
            backpack:null,
            drugLoadout:null,
            loot:null,
            terminal:null
        };
        if (state === 'ACTIVE') {
            if (!Array.isArray(raw.snapshots) || raw.snapshots.length !== 3) return null;
            for (var snapshotIndex = 0; snapshotIndex < raw.snapshots.length; snapshotIndex++) {
                var candidate = raw.snapshots[snapshotIndex];
                if (candidate && candidate.containerId === identity.lootContainerId) {
                    result.loot = normalizeWindow(candidate, identity.lootContainerId, true, true);
                } else if (candidate && candidate.containerId === '背包') {
                    result.backpack = normalizeWindow(candidate, '背包', false, false);
                } else if (candidate && candidate.containerId === '药剂栏') {
                    result.drugLoadout = normalizeWindow(candidate, '药剂栏', true, false);
                } else return null;
            }
            if (!result.backpack || !result.drugLoadout || !result.loot || !result.closeLease
                    || result.drugLoadout.capacity !== 8
                    || result.drugLoadout.accessibleCapacity !== 8) return null;
            var occupied = 0;
            for (var i = 0; i < result.loot.slots.length; i++) if (result.loot.slots[i].occupied) occupied++;
            if (occupied !== remainingCount) return null;
        } else if (state === 'SUSPENDED') {
            var zeroSuspendedAllowed=allowZeroSuspended===true&&identity
                &&identity.source==='stage_settlement';
            if (remainingCount < 0 || remainingCount === 0&&!zeroSuspendedAllowed
                    || raw.closeLease !== ''
                    || !Array.isArray(raw.snapshots) || raw.snapshots.length !== 0
                    || raw.tooltip !== null || raw.terminal !== null) return null;
        } else {
            if (!Array.isArray(raw.snapshots) || raw.snapshots.length !== 0) return null;
            if (raw.closeLease !== '' || !hasExactKeys(raw.terminal,
                    ['kind','reason','remainingCount'])) return null;
            var terminal = raw.terminal;
            var kind = normalizedState(terminal.kind);
            var terminalRemaining = integer(terminal.remainingCount);
            if (!own(TERMINAL_STATES,kind) || kind !== state || terminalRemaining == null
                    || terminalRemaining < 0 || terminalRemaining !== remainingCount
                    || kind === 'CONSUMED' && terminalRemaining !== 0
                    || kind === 'ABANDONED' && terminalRemaining <= 0
                    || !safeWord(terminal.reason)) return null;
            result.terminal = {
                kind:kind,
                reason:terminal.reason,
                remainingCount:terminalRemaining
            };
        }
        return result;
    }

    function defaultNotice() {}
    function operationNonce(value) {
        value = String(value || '').replace(/[^A-Za-z0-9._~-]/g,'').slice(0,48);
        return value || ('view.' + Date.now().toString(36) + '.'
            + Math.floor(Math.random() * 0x7fffffff).toString(36));
    }
    function operationId(prefix, nonce, revision) {
        return 'loot-op.' + String(prefix || 'write') + '.' + nonce + '.' + revision.toString(36);
    }

    function Coordinator(options) {
        options = options || {};
        if (typeof options.request !== 'function') throw new Error('loot request function is required');
        this.identity = clone(options.identity || {});
        this._request = options.request;
        this._onChange = typeof options.onChange === 'function' ? options.onChange : defaultNotice;
        this._generation = 1;
        this._intentRevision = 0;
        this._operationNonce = operationNonce(options.operationNonce);
        this._phase = 'idle';
        this._projection = null;
        this._pending = null;
        this._unknown = null;
        this._lastError = '';
        this._detached = false;
        this._rewardRoot = this.identity.source === 'reward_inbox' ? {
            rootOperationId:String(options.recoverableRootOperationId||''),
            rootStatus:String(options.recoverableRootStatus||'not_started'),
            recoveryRequired:options.recoveryRequired===true,
            recoveryOnly:options.recoveryOnly===true,
            previousTerminalRootOperationId:
                options.recoverableRootStatus==='committed'
                    ||options.recoverableRootStatus==='terminal_failure'
                ? String(options.recoverableRootOperationId||'') : ''
        } : null;
        this._rewardRootAdmissionEnabled = !this._rewardRoot
            || options.rewardRootAdmissionEnabled !== false;
        this._allowZeroSuspended = this.identity.source === 'stage_settlement'
            && options.settlementReport && typeof options.settlementReport === 'object'
            && !Array.isArray(options.settlementReport);
        this._lootLimit = Math.max(0, Math.min(64, integer(options.capacity) || 0));
        this._backpackLimit = Math.max(1, Math.min(100, integer(options.backpackLimit) || 50));
    }

    Coordinator.prototype._emit = function() { this._onChange(this.debugState()); };
    Coordinator.prototype._normalizeProjection = function(response) {
        var projection = normalizeProjection(
            response, this.identity, this._allowZeroSuspended);
        if (!projection || projection.state !== 'ACTIVE') return projection;
        if (projection.loot.capacity !== this._lootLimit
                || projection.backpack.offset !== 0
                || projection.backpack.limit !== Math.min(
                    this._backpackLimit, projection.backpack.capacity)) return null;
        return projection;
    };
    Coordinator.prototype._apply = function(projection) {
        if (!projection || (this._projection
                && projection.authorityRevision < this._projection.authorityRevision)) return false;
        this._projection = projection;
        this._phase = projection.state === 'ACTIVE' ? 'active'
            : projection.state === 'SUSPENDED' ? 'suspended' : 'terminal';
        this._lastError = projection.blockReason || '';
        this._pending = null;
        this._unknown = null;
        this._emit();
        return true;
    };
    Coordinator.prototype._markReconcile = function(entry, operationIdValue, error, refreshOnly,
            failureAuthorityRevision) {
        var pending = this._pending || {};
        var localAuthorityRevision = this._projection ? this._projection.authorityRevision : 0;
        var failureRevision = integer(failureAuthorityRevision);
        var freshnessWatermark = failureRevision != null && failureRevision >= 0
            ? Math.max(localAuthorityRevision,failureRevision) : localAuthorityRevision;
        this._phase = 'reconcile_required';
        this._pending = null;
        this._unknown = {
            callId:String(entry && entry.callId || ''),
            operationId:String(operationIdValue || ''),
            kind:String(pending.kind || ''),
            expectedState:String(pending.expectedState || ''),
            beforeRemaining:integer(pending.beforeRemaining),
            beforeLastAppliedOperationId:String(pending.beforeLastAppliedOperationId || ''),
            beforeCloseLease:String(pending.beforeCloseLease || ''),
            physicalSlot:integer(pending.physicalSlot),
            slotLease:String(pending.slotLease || ''),
            physicalSlots:Array.isArray(pending.physicalSlots)
                ? pending.physicalSlots.map(Number) : [],
            slotLeases:Array.isArray(pending.slotLeases)
                ? pending.slotLeases.map(String) : [],
            expectedContainerVersion:integer(pending.expectedContainerVersion),
            authorityRevision:localAuthorityRevision,
            freshnessWatermark:freshnessWatermark,
            requiresCausalCompletion:error === 'commit_pending',
            refreshOnly:refreshOnly === true,
            error:String(error || 'unknown_result')
        };
        this._lastError = 'reconcile_required';
        this._emit();
    };

    Coordinator.prototype._enterRewardRecovery = function(rootId,error) {
        if (!this._rewardRoot||!opaque(rootId)) return false;
        this._phase='reconcile_required';
        this._pending=null;
        this._unknown={kind:'rewardRoot',operationId:String(rootId),
            error:String(error||'recovery_required')};
        this._lastError=String(error||'recovery_required');
        this._emit();
        return true;
    };

    Coordinator.prototype._consumeRewardRoot = function(response,rootId) {
        if (!this._rewardRoot) return null;
        var root=normalizeRewardRoot(response,rootId);
        if (!root) return null;
        var projection=this._normalizeProjection(response);
        if (projection&&!this._apply(projection)) return null;
        this._pending=null;
        this._rewardRoot.rootOperationId=root.rootOperationId;
        this._rewardRoot.rootStatus=root.rootStatus;
        this._rewardRoot.exact=clone(root);
        this._lastError=root.error||rewardRootCapacityReason(root)||'';
        if (root.rootStatus==='pending'||root.rootStatus==='quarantined') {
            this._rewardRoot.recoveryRequired=true;
            this._enterRewardRecovery(root.rootOperationId,
                root.rootStatus==='quarantined'?'reward_root_quarantined':'recovery_required');
            return {root:root,settled:false,success:false};
        }
        this._unknown=null;
        if (root.rootStatus==='committed'||root.rootStatus==='terminal_failure') {
            this._rewardRoot.previousTerminalRootOperationId=root.rootOperationId;
            this._rewardRoot.recoveryRequired=true;
        } else {
            this._rewardRoot.recoveryRequired=false;
        }
        this._phase=this._projection
            ? this._projection.state==='ACTIVE'?'active'
                :this._projection.state==='SUSPENDED'?'suspended':'terminal'
            :'reconcile_required';
        this._emit();
        if (root.rootStatus==='committed'||root.rootStatus==='terminal_failure')
            this._ackRewardTerminal(root.rootOperationId);
        return {root:root,settled:true,success:root.rootStatus==='committed'};
    };

    Coordinator.prototype._ackRewardTerminal = function(rootId) {
        if (!this._rewardRoot||!opaque(rootId)||this._detached) return false;
        var self=this,generation=this._generation;
        return !!this._request('query',{
            rootOperationId:rootId,
            acknowledgeTerminalRootOperationId:rootId
        },{kind:'rootAck',latestWins:true,operationId:rootId},function(response){
            if(generation!==self._generation||self._detached)return;
            var exact=normalizeRewardRoot(response,rootId);
            if(exact&&(exact.rootStatus==='committed'
                    ||exact.rootStatus==='terminal_failure')) {
                self._rewardRoot.recoveryRequired=false;
                self._rewardRoot.exact=clone(exact);
                self._emit();
            }
        });
    };

    Coordinator.prototype.open = function(callback) {
        if (this._phase !== 'idle') return false;
        this._phase = 'opening'; this._emit();
        var self = this, generation = this._generation;
        var callId = this._request('snapshot', {
            loot:{offset:0, limit:this._lootLimit},
            backpack:{offset:0, limit:this._backpackLimit}
        }, {kind:'snapshot', singleFlight:true}, function(response) {
            if (generation !== self._generation || self._detached) return;
            var strictTerminalError = response && response.success === false
                && response.terminal && own(TERMINAL_STATES,response.state);
            var projection = response && (response.success === true || strictTerminalError)
                ? self._normalizeProjection(response) : null;
            if (!projection || !self._apply(projection)) {
                self._phase = 'reconcile_required';
                self._lastError = response && response.error || 'malformed_response';
                self._emit();
            } else if (self._rewardRoot&&self._rewardRoot.recoveryRequired)
                self._enterRewardRecovery(self._rewardRoot.rootOperationId,
                    'recovery_required');
            if (typeof callback === 'function') callback(!!projection, response);
        });
        if (!callId) {
            this._phase = 'reconcile_required'; this._lastError = 'disconnected'; this._emit();
            return false;
        }
        return true;
    };

    /**
     * Read-only ACTIVE refresh used after the embedded inventory organizer settles.
     * It never replays a claim/close operation and keeps the previous projection on failure.
     */
    Coordinator.prototype.refresh = function(callback) {
        if (this._phase !== 'active' || this._pending || !this._projection) return false;
        var beforeRevision = this._projection.authorityRevision;
        var self = this, generation = this._generation;
        this._pending = {kind:'refresh', operationId:'', callId:''};
        this._emit();
        var callId = this._request('snapshot', {
            loot:{offset:0, limit:this._lootLimit},
            backpack:{offset:0, limit:this._backpackLimit}
        }, {kind:'refresh', singleFlight:true, latestWins:true,
            onIssued:function(entry) { if (self._pending) self._pending.callId = entry.callId; }},
        function(response) {
            if (generation !== self._generation || self._detached) return;
            self._pending = null;
            var strictTerminalError = response && response.success === false
                && response.terminal && own(TERMINAL_STATES,response.state);
            var projection = response && (response.success === true || strictTerminalError)
                ? self._normalizeProjection(response) : null;
            var applied = !!projection && projection.authorityRevision >= beforeRevision
                && self._apply(projection);
            if (!applied) {
                self._lastError = response && response.error || 'loot_refresh_failed';
                self._emit();
            }
            if (typeof callback === 'function') callback(
                applied && projection.state === 'ACTIVE', response);
        });
        if (!callId) {
            this._pending = null;
            this._lastError = 'disconnected';
            this._emit();
            return false;
        }
        return true;
    };

    Coordinator.prototype._sourceRef = function(slot) {
        var loot = this._projection && this._projection.loot;
        return {
            containerId:this.identity.lootContainerId,
            slot:Number(slot.physicalSlot),
            expectedLease:String(slot.slotLease),
            expectedContainerVersion:loot ? Number(loot.containerVersion) : 0
        };
    };

    Coordinator.prototype._sourceRefs = function(slots) {
        var refs=[];
        for (var i=0;i<slots.length;i++) refs.push(this._sourceRef(slots[i]));
        return refs;
    };

    Coordinator.prototype._capacityFailureProvesNoWrite = function(response, error, pending) {
        var projection = this._projection;
        if (!response || response.success !== false
                || !own(CAPACITY_NO_WRITE_ERRORS,error)
                || response.state !== 'LOOT_ACTIVE'
                || response.closeLease !== ''
                || !Array.isArray(response.snapshots) || response.snapshots.length !== 0
                || response.tooltip !== null || response.terminal !== null
                || integer(response.authorityRevision) !== integer(pending.beforeAuthorityRevision)
                || integer(response.remainingCount) !== integer(pending.beforeRemaining)
                || typeof response.lastAppliedOperationId !== 'string'
                || response.lastAppliedOperationId !== pending.beforeLastAppliedOperationId
                || !projection || projection.state !== 'ACTIVE'
                || projection.authorityRevision !== pending.beforeAuthorityRevision
                || projection.remainingCount !== pending.beforeRemaining
                || projection.lastAppliedOperationId !== pending.beforeLastAppliedOperationId
                || !projection.loot
                || projection.loot.containerVersion !== pending.expectedContainerVersion)
            return false;
        var slots = projection.loot.slots || [];
        for (var i = 0; i < slots.length; i++) {
            if (slots[i].physicalSlot !== pending.physicalSlot) continue;
            return slots[i].occupied === true && slots[i].slotLease === pending.slotLease;
        }
        return false;
    };

    Coordinator.prototype._claimSuccessProvesAdvance = function(projection, pending, operationIdValue) {
        if (!projection || projection.state !== 'ACTIVE' || !projection.loot
                || integer(pending.beforeAuthorityRevision) == null
                || integer(pending.beforeRemaining) == null
                || integer(pending.physicalSlot) == null
                || projection.authorityRevision !== pending.beforeAuthorityRevision + 1
                || projection.remainingCount !== pending.beforeRemaining - 1
                || projection.lastAppliedOperationId !== operationIdValue)
            return false;
        var slots = projection.loot.slots || [];
        for (var i = 0; i < slots.length; i++) {
            if (slots[i].physicalSlot !== pending.physicalSlot) continue;
            return slots[i].occupied === false;
        }
        return false;
    };

    Coordinator.prototype._claimBatchProjection = function(projection,pending) {
        if (!projection||projection.state!=='ACTIVE'||!projection.loot
                ||!Array.isArray(pending.physicalSlots)||!Array.isArray(pending.slotLeases)
                ||pending.physicalSlots.length<1
                ||pending.physicalSlots.length!==pending.slotLeases.length) return null;
        var bySlot={},slots=projection.loot.slots||[];
        for (var i=0;i<slots.length;i++) bySlot[String(slots[i].physicalSlot)]=slots[i];
        var empty=0;
        for (i=0;i<pending.physicalSlots.length;i++) {
            var slot=bySlot[String(pending.physicalSlots[i])];
            if (!slot) return null;
            if (!slot.occupied) empty++;
            else if (slot.slotLease!==String(pending.slotLeases[i])) return null;
        }
        return {empty:empty,containerVersion:projection.loot.containerVersion};
    };

    Coordinator.prototype._claimBatchSuccessProvesAdvance = function(
            projection,pending,operationIdValue) {
        var requested=Array.isArray(pending.physicalSlots)?pending.physicalSlots.length:0;
        var applied=projection&&integer(pending.beforeAuthorityRevision)!=null
            ? projection.authorityRevision-pending.beforeAuthorityRevision:0;
        var requestedProjection=this._claimBatchProjection(projection,pending);
        return requested>0&&applied>=1&&applied<=requested&&requestedProjection
            &&projection.remainingCount===pending.beforeRemaining-applied
            &&projection.lastAppliedOperationId===operationIdValue
            &&requestedProjection.empty===applied;
    };

    Coordinator.prototype._claimBatchCapacityFailureProvesNoWrite = function(
            response,error,pending) {
        var projection=this._projection;
        if (!response||response.success!==false||!own(CAPACITY_NO_WRITE_ERRORS,error)
                ||response.state!=='LOOT_ACTIVE'||response.closeLease!==''
                ||!Array.isArray(response.snapshots)||response.snapshots.length!==0
                ||response.tooltip!==null||response.materials!==null||response.terminal!==null
                ||integer(response.authorityRevision)!==integer(pending.beforeAuthorityRevision)
                ||integer(response.remainingCount)!==integer(pending.beforeRemaining)
                ||typeof response.lastAppliedOperationId!=='string'
                ||response.lastAppliedOperationId!==pending.beforeLastAppliedOperationId
                ||!projection||projection.state!=='ACTIVE'
                ||projection.authorityRevision!==pending.beforeAuthorityRevision
                ||projection.remainingCount!==pending.beforeRemaining
                ||projection.lastAppliedOperationId!==pending.beforeLastAppliedOperationId
                ||!projection.loot
                ||projection.loot.containerVersion!==pending.expectedContainerVersion) return false;
        var requestedProjection=this._claimBatchProjection(projection,pending);
        return !!requestedProjection&&requestedProjection.empty===0;
    };

    Coordinator.prototype._unknownClaimProjectionProves = function(projection, unknown) {
        if (integer(unknown.authorityRevision) == null
                || integer(unknown.beforeRemaining) == null
                || integer(unknown.physicalSlot) == null
                || integer(unknown.expectedContainerVersion) == null
                || integer(unknown.freshnessWatermark) == null
                || !opaque(unknown.slotLease) || !projection
                || projection.authorityRevision < unknown.freshnessWatermark) return false;
        var appliedContext = {
            beforeAuthorityRevision:unknown.authorityRevision,
            beforeRemaining:unknown.beforeRemaining,
            physicalSlot:unknown.physicalSlot
        };
        if (this._claimSuccessProvesAdvance(projection,appliedContext,unknown.operationId))
            return true;
        if (unknown.requiresCausalCompletion === true || !projection
                || projection.state !== 'ACTIVE' || !projection.loot
                || projection.authorityRevision !== Number(unknown.authorityRevision)
                || projection.remainingCount !== Number(unknown.beforeRemaining)
                || projection.lastAppliedOperationId
                    !== String(unknown.beforeLastAppliedOperationId || '')
                || projection.closeLease !== String(unknown.beforeCloseLease || '')
                || projection.loot.containerVersion
                    !== Number(unknown.expectedContainerVersion)) return false;
        var slots = projection.loot.slots || [];
        for (var i = 0; i < slots.length; i++) {
            if (slots[i].physicalSlot !== Number(unknown.physicalSlot)) continue;
            return slots[i].occupied === true
                && slots[i].slotLease === String(unknown.slotLease || '');
        }
        return false;
    };

    Coordinator.prototype._unknownClaimBatchProjectionProves = function(projection,unknown) {
        if (!projection||integer(unknown.authorityRevision)==null
                ||integer(unknown.beforeRemaining)==null
                ||integer(unknown.expectedContainerVersion)==null
                ||integer(unknown.freshnessWatermark)==null
                ||projection.authorityRevision<unknown.freshnessWatermark) return false;
        var requested=Array.isArray(unknown.physicalSlots)?unknown.physicalSlots.length:0;
        if (!requested||!Array.isArray(unknown.slotLeases)
                ||unknown.slotLeases.length!==requested) return false;
        var requestedProjection=this._claimBatchProjection(projection,unknown);
        if (!requestedProjection) return false;
        var applied=projection.authorityRevision-unknown.authorityRevision;
        if (applied>=1&&applied<=requested
                &&projection.lastAppliedOperationId===unknown.operationId
                &&projection.remainingCount===unknown.beforeRemaining-applied
                &&requestedProjection.empty===applied) return true;
        return unknown.requiresCausalCompletion!==true
            &&projection.state==='ACTIVE'
            &&projection.authorityRevision===unknown.authorityRevision
            &&projection.remainingCount===unknown.beforeRemaining
            &&projection.lastAppliedOperationId
                ===String(unknown.beforeLastAppliedOperationId||'')
            &&projection.closeLease===String(unknown.beforeCloseLease||'')
            &&projection.loot.containerVersion===unknown.expectedContainerVersion
            &&requestedProjection.empty===0;
    };

    Coordinator.prototype._unknownCloseActiveProjectionProvesNoWrite = function(projection, unknown) {
        return unknown.requiresCausalCompletion !== true && projection
            && projection.state === 'ACTIVE' && projection.loot
            && integer(unknown.authorityRevision) != null
            && integer(unknown.beforeRemaining) != null
            && integer(unknown.expectedContainerVersion) != null
            && integer(unknown.freshnessWatermark) != null
            && opaque(unknown.beforeCloseLease)
            && projection.authorityRevision === unknown.authorityRevision
            && projection.authorityRevision >= unknown.freshnessWatermark
            && projection.remainingCount === unknown.beforeRemaining
            && projection.lastAppliedOperationId
                === String(unknown.beforeLastAppliedOperationId || '')
            && projection.closeLease === unknown.beforeCloseLease
            && projection.loot.containerVersion === unknown.expectedContainerVersion;
    };

    Coordinator.prototype.claim = function(slot, callback) {
        if (!this._rewardRootAdmissionEnabled
                || this._phase !== 'active' || this._pending || !slot || !slot.occupied
                || !text(String(slot.slotLease || ''), 240)) return false;
        var revision = ++this._intentRevision;
        var opId = operationId('claim', this._operationNonce, revision);
        var self = this, generation = this._generation;
        this._phase = 'write_pending';
        this._pending = {
            kind:'claim', operationId:opId, intentRevision:revision, callId:'',
            beforeAuthorityRevision:this._projection.authorityRevision,
            beforeRemaining:this._projection.remainingCount,
            beforeLastAppliedOperationId:this._projection.lastAppliedOperationId,
            beforeCloseLease:this._projection.closeLease,
            physicalSlot:Number(slot.physicalSlot),
            slotLease:String(slot.slotLease),
            expectedContainerVersion:Number(this._projection.loot.containerVersion)
        };
        this._lastError = ''; this._emit();
        var claimPayload={
            operationId:opId,
            direction:'loot_to_player',
            source:this._sourceRef(slot),
            targetContainerId:'自动',
            expectedAuthorityRevision:this._projection.authorityRevision
        };
        if(this._rewardRoot)claimPayload.previousTerminalRootOperationId=
            String(this._rewardRoot.previousTerminalRootOperationId||'');
        var callId = this._request('claim', claimPayload, {
            kind:'write', singleFlight:true, write:true, operationId:opId,
            onIssued:function(entry) { if (self._pending) self._pending.callId = entry.callId; }
        }, function(response, entry) {
            if (generation !== self._generation || self._detached) return;
            if (self._rewardRoot) {
                var rootOutcome=response&&!response.clientSynthetic
                    ?self._consumeRewardRoot(response,opId):null;
                if(rootOutcome){
                    if(typeof callback==='function')callback(rootOutcome.success,response);
                    return;
                }
                self._markReconcile(entry,opId,response&&response.error||'malformed_response');
                if(typeof callback==='function')callback(false,response);
                return;
            }
            var projection = self._normalizeProjection(response);
            var pending = self._pending || {};
            if (response && response.success === true && projection
                    && self._claimSuccessProvesAdvance(projection,pending,opId)
                    && self._apply(projection)) {
                if (typeof callback === 'function') callback(true, response);
                return;
            }
            var error = response && response.error || 'malformed_response';
            if (response && (response.clientSynthetic || response.requiresReconcile
                    || own(AMBIGUOUS_ERRORS,error))
                    || response && response.success === true) {
                self._markReconcile(entry, opId, error, false,
                    response && response.authorityRevision);
            } else if (own(STALE_ERRORS,error)) {
                self._markReconcile(entry, opId, error, true,
                    response && response.authorityRevision);
            } else if (self._capacityFailureProvesNoWrite(response,error,pending)) {
                self._phase = 'active'; self._pending = null; self._lastError = error; self._emit();
            } else if (projection && own(TERMINAL_STATES,projection.state)) {
                self._apply(projection);
            } else if (own(REFRESH_ONLY_ERRORS,error)) {
                self._markReconcile(entry, opId, error, true,
                    response && response.authorityRevision);
            } else self._markReconcile(entry, opId, error, false,
                response && response.authorityRevision);
            if (typeof callback === 'function') callback(false, response);
        });
        if (!callId && this._phase === 'write_pending') {
            this._markReconcile({callId:''}, opId, 'disconnected');
            return false;
        }
        return true;
    };

    Coordinator.prototype.claimBatch = function(slots, callback) {
        if (!this._rewardRootAdmissionEnabled
                ||this._phase!=='active'||this._pending||!this._projection
                ||!Array.isArray(slots)||slots.length<1||slots.length>50) return false;
        var physicalSlots=[],slotLeases=[],seen={};
        for (var i=0;i<slots.length;i++) {
            var slot=slots[i],physicalSlot=integer(slot&&slot.physicalSlot);
            var slotLease=slot&&text(String(slot.slotLease||''),240);
            if (!slot||!slot.occupied||physicalSlot==null||!slotLease
                    ||own(seen,String(physicalSlot))) return false;
            seen[String(physicalSlot)]=true;
            physicalSlots.push(physicalSlot);slotLeases.push(slotLease);
        }
        var revision=++this._intentRevision;
        var opId=operationId('batch',this._operationNonce,revision);
        var self=this,generation=this._generation;
        this._phase='write_pending';
        this._pending={
            kind:'claimBatch',operationId:opId,intentRevision:revision,callId:'',
            beforeAuthorityRevision:this._projection.authorityRevision,
            beforeRemaining:this._projection.remainingCount,
            beforeLastAppliedOperationId:this._projection.lastAppliedOperationId,
            beforeCloseLease:this._projection.closeLease,
            physicalSlots:physicalSlots,slotLeases:slotLeases,
            expectedContainerVersion:Number(this._projection.loot.containerVersion)
        };
        this._lastError='';this._emit();
        var batchPayload={
            operationId:opId,
            direction:'loot_to_player',sources:this._sourceRefs(slots),
            targetContainerId:'自动',
            expectedAuthorityRevision:this._projection.authorityRevision
        };
        if(this._rewardRoot)batchPayload.previousTerminalRootOperationId=
            String(this._rewardRoot.previousTerminalRootOperationId||'');
        var callId=this._request('claimBatch',batchPayload,{
            kind:'write',singleFlight:true,write:true,operationId:opId,
            onIssued:function(entry){if(self._pending)self._pending.callId=entry.callId;}
        },function(response,entry){
            if(generation!==self._generation||self._detached)return;
            if(self._rewardRoot){
                var rootOutcome=response&&!response.clientSynthetic
                    ?self._consumeRewardRoot(response,opId):null;
                if(rootOutcome){
                    if(typeof callback==='function')callback(rootOutcome.success,response);
                    return;
                }
                self._markReconcile(entry,opId,response&&response.error||'malformed_response');
                if(typeof callback==='function')callback(false,response);
                return;
            }
            var projection=self._normalizeProjection(response),pending=self._pending||{};
            if(response&&response.success===true&&projection
                    &&self._claimBatchSuccessProvesAdvance(projection,pending,opId)
                    &&self._apply(projection)){
                if(typeof callback==='function')callback(true,response);
                return;
            }
            var error=response&&response.error||'malformed_response';
            if(response&&(response.clientSynthetic||response.requiresReconcile
                    ||own(AMBIGUOUS_ERRORS,error))||response&&response.success===true){
                self._markReconcile(entry,opId,error,false,
                    response&&response.authorityRevision);
            }else if(own(STALE_ERRORS,error)){
                self._markReconcile(entry,opId,error,true,
                    response&&response.authorityRevision);
            }else if(self._claimBatchCapacityFailureProvesNoWrite(response,error,pending)){
                self._phase='active';self._pending=null;self._lastError=error;self._emit();
            }else if(projection&&own(TERMINAL_STATES,projection.state)){
                self._apply(projection);
            }else if(own(REFRESH_ONLY_ERRORS,error)){
                self._markReconcile(entry,opId,error,true,
                    response&&response.authorityRevision);
            }else self._markReconcile(entry,opId,error,false,
                response&&response.authorityRevision);
            if(typeof callback==='function')callback(false,response);
        });
        if(!callId&&this._phase==='write_pending'){
            this._markReconcile({callId:''},opId,'disconnected');
            return false;
        }
        return true;
    };

    Coordinator.prototype.close = function(abandon, callback) {
        if (this._phase !== 'active' || this._pending || !this._projection) return false;
        if (abandon === true && this.identity.source === 'reward_inbox') return false;
        abandon = abandon === true;
        if (this._projection.remainingCount === 0) abandon = false;
        var beforeRevision = this._projection.authorityRevision;
        var beforeRemaining = this._projection.remainingCount;
        var expectedState = abandon ? 'ABANDONED'
            : beforeRemaining > 0 ? 'SUSPENDED' : 'CONSUMED';
        var revision = ++this._intentRevision;
        var opId = operationId(abandon ? 'abandon'
            : beforeRemaining > 0 ? 'suspend' : 'consume', this._operationNonce, revision);
        var self = this, generation = this._generation;
        this._phase = 'write_pending';
        this._pending = {
            kind:'close',
            operationId:opId,
            intentRevision:revision,
            callId:'',
            expectedState:expectedState,
            beforeRemaining:beforeRemaining,
            beforeLastAppliedOperationId:this._projection.lastAppliedOperationId,
            beforeCloseLease:this._projection.closeLease,
            expectedContainerVersion:this._projection.loot
                ? this._projection.loot.containerVersion : null
        };
        this._lastError = ''; this._emit();
        var callId = this._request('close', {
            operationId:opId,
            closeLease:this._projection.closeLease,
            abandon:abandon,
            expectedAuthorityRevision:this._projection.authorityRevision
        }, {
            kind:'write', singleFlight:true, write:true, operationId:opId,
            onIssued:function(entry) { if (self._pending) self._pending.callId = entry.callId; }
        }, function(response, entry) {
            if (generation !== self._generation || self._detached) return;
            var projection = self._normalizeProjection(response);
            if (response && response.success === true && projection
                    && projection.state === expectedState
                    && projection.authorityRevision === beforeRevision + 1
                    && (expectedState === 'CONSUMED' ? projection.remainingCount === 0
                        : projection.remainingCount === beforeRemaining)
                    && projection.lastAppliedOperationId === opId && self._apply(projection)) {
                if (typeof callback === 'function') callback(true, response);
                return;
            }
            var error = response && response.error || 'malformed_response';
            if (response && (response.clientSynthetic || response.requiresReconcile
                    || own(AMBIGUOUS_ERRORS,error))
                    || response && response.success === true) {
                self._markReconcile(entry, opId, error, false,
                    response && response.authorityRevision);
            } else if (own(STALE_ERRORS,error)) {
                self._markReconcile(entry, opId, error, true,
                    response && response.authorityRevision);
            } else if (projection && own(TERMINAL_STATES,projection.state)) {
                self._apply(projection);
            } else if (own(REFRESH_ONLY_ERRORS,error)) {
                self._markReconcile(entry, opId, error, true,
                    response && response.authorityRevision);
            } else self._markReconcile(entry, opId, error, false,
                response && response.authorityRevision);
            if (typeof callback === 'function') callback(false, response);
        });
        if (!callId && this._phase === 'write_pending') {
            this._markReconcile({callId:''}, opId, 'disconnected');
            return false;
        }
        return true;
    };

    Coordinator.prototype._queryRewardRoot = function(callback) {
        if(this._phase!=='reconcile_required'||this._pending||!this._rewardRoot)return false;
        var unknown=clone(this._unknown||{});
        var rootId=opaque(unknown.operationId)||opaque(this._rewardRoot.rootOperationId);
        if(!rootId)return false;
        var self=this,generation=this._generation;
        this._pending={kind:'query',operationId:rootId,callId:''};
        this._emit();
        var callId=this._request('query',{rootOperationId:rootId},{kind:'query',
            singleFlight:true,latestWins:true,operationId:rootId,
            onIssued:function(entry){if(self._pending)self._pending.callId=entry.callId;}},
        function(response){
            if(generation!==self._generation||self._detached)return;
            self._pending=null;
            var outcome=response&&!response.clientSynthetic
                ?self._consumeRewardRoot(response,rootId):null;
            if(!outcome){
                self._phase='reconcile_required';self._unknown=unknown;
                self._lastError=response&&response.error||'reconcile_failed';self._emit();
            }
            if(typeof callback==='function')callback(!!outcome&&outcome.settled,response);
        });
        if(!callId){
            this._pending=null;this._phase='reconcile_required';this._unknown=unknown;
            this._lastError='disconnected';this._emit();return false;
        }
        return true;
    };

    Coordinator.prototype.query = function(callback) {
        if(this._rewardRoot)return this._queryRewardRoot(callback);
        if (this._phase !== 'reconcile_required' || this._pending) return false;
        var unknown = clone(this._unknown || {});
        var self = this, generation = this._generation;
        this._pending = {kind:'query', operationId:unknown.operationId || '', callId:''};
        this._emit();
        var callId = this._request('query', {}, {kind:'query', singleFlight:true, latestWins:true,
            onIssued:function(entry) { if (self._pending) self._pending.callId = entry.callId; }},
        function(response) {
            if (generation !== self._generation || self._detached) return;
            self._pending = null;
            var strictTerminalError = response && response.success === false
                && response.terminal && own(TERMINAL_STATES,response.state);
            var projection = response && (response.success === true || strictTerminalError)
                ? self._normalizeProjection(response) : null;
            // A projection can be well-formed yet fail the causal proof below.  Its observed
            // authority revision still raises the reconciliation freshness floor; otherwise a
            // later, older projection could launder an unknown write as an exact no-write result.
            var observedRevision = integer(response && response.authorityRevision);
            if (observedRevision != null && observedRevision >= 0)
                unknown.freshnessWatermark = Math.max(
                    Number(unknown.freshnessWatermark) || 0, observedRevision);
            if (response && response.error === 'commit_pending') {
                unknown.requiresCausalCompletion = true;
            }
            var provesUnknown = false;
            if (projection && unknown.refreshOnly === true) {
                provesUnknown = projection.state !== 'SUSPENDED'
                    && projection.authorityRevision
                    >= Number(unknown.freshnessWatermark);
            } else if (projection && projection.state === 'SUSPENDED') {
                provesUnknown = unknown.kind === 'close'
                    && unknown.expectedState === 'SUSPENDED'
                    && projection.lastAppliedOperationId === unknown.operationId
                    && projection.authorityRevision > Number(unknown.authorityRevision)
                    && projection.authorityRevision
                        >= Number(unknown.freshnessWatermark)
                    && projection.remainingCount === Number(unknown.beforeRemaining);
            } else if (projection && own(TERMINAL_STATES,projection.state)) {
                if (unknown.kind === 'claim' || unknown.kind === 'claimBatch') {
                    provesUnknown = projection.authorityRevision
                        > Number(unknown.authorityRevision)
                        && projection.authorityRevision
                            >= Number(unknown.freshnessWatermark);
                } else if (unknown.kind !== 'close') provesUnknown = true;
                else if (projection.authorityRevision > Number(unknown.authorityRevision)) {
                    provesUnknown = projection.authorityRevision
                        >= Number(unknown.freshnessWatermark)
                        && (projection.state === 'EXPIRED'
                        || projection.state === unknown.expectedState
                            && projection.lastAppliedOperationId === unknown.operationId
                            && projection.remainingCount === Number(unknown.beforeRemaining));
                }
            } else if (projection && unknown.kind === 'claim') {
                provesUnknown = self._unknownClaimProjectionProves(projection,unknown);
            } else if (projection && unknown.kind === 'claimBatch') {
                provesUnknown = self._unknownClaimBatchProjectionProves(projection,unknown);
            } else if (projection && unknown.kind === 'close') {
                provesUnknown = self._unknownCloseActiveProjectionProvesNoWrite(
                    projection,unknown);
            } else if (projection) {
                provesUnknown = !unknown.operationId
                    || projection.lastAppliedOperationId === unknown.operationId
                    || unknown.requiresCausalCompletion !== true
                        && projection.authorityRevision === Number(unknown.authorityRevision);
            }
            if (!projection || !provesUnknown
                    || !self._apply(projection)) {
                self._phase = 'reconcile_required';
                self._unknown = unknown;
                self._lastError = projection ? 'stale_reconcile' : response && response.error || 'reconcile_failed';
                self._emit();
                if (typeof callback === 'function') callback(false, response);
                return;
            }
            if (typeof callback === 'function') callback(true, response);
        });
        if (!callId) {
            this._pending = null; this._lastError = 'disconnected'; this._emit(); return false;
        }
        return true;
    };

    Coordinator.prototype.tooltip = function(slot, callback) {
        if ((this._phase !== 'active' && this._phase !== 'reconcile_required')
                || !slot || !slot.occupied) return false;
        return !!this._request('tooltip', {
            expectedAuthorityRevision:this._projection ? this._projection.authorityRevision : 0,
            source:this._sourceRef(slot)
        },
            {kind:'tooltip', latestWins:true}, callback);
    };

    Coordinator.prototype.forceDetach = function() {
        if (this._detached) return false;
        this._detached = true; this._generation++;
        this._pending = null;
        this._phase = 'detached';
        this._emit();
        return true;
    };
    Coordinator.prototype.destroy = function() { return this.forceDetach(); };
    Coordinator.prototype.projection = function() { return this._projection; };
    Coordinator.prototype.debugState = function() {
        return {
            phase:this._phase,
            intentRevision:this._intentRevision,
            authorityRevision:this._projection ? this._projection.authorityRevision : -1,
            remainingCount:this._projection ? this._projection.remainingCount : null,
            blockReason:this._lastError || this._projection && this._projection.blockReason || '',
            terminal:this._projection && this._projection.terminal ? clone(this._projection.terminal) : null,
            pending:this._pending ? clone(this._pending) : null,
            unknown:this._unknown ? clone(this._unknown) : null,
            rewardRoot:this._rewardRoot ? clone(this._rewardRoot) : null,
            rewardRootAdmissionEnabled:this._rewardRootAdmissionEnabled,
            detached:this._detached
        };
    };

    return {
        Coordinator:Coordinator,
        normalizeProjection:normalizeProjection,
        normalizeRewardRoot:normalizeRewardRoot,
        normalizeWindow:normalizeWindow,
        normalizeSlot:normalizeSlot,
        ACTIVE_STATES:ACTIVE_STATES,
        TERMINAL_STATES:TERMINAL_STATES
    };
});
