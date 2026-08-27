/** Right-hand equipment tuning view for the owned inventory workbench. */
var EquipmentTuningView = (function() {
    'use strict';

    var Model = typeof EquipmentTuningModel !== 'undefined' ? EquipmentTuningModel : null;
    var Renderer = typeof EquipmentTuningRender !== 'undefined' ? EquipmentTuningRender : null;
    var DecisionPresenter = typeof EquipmentTuningDecisionPresenter !== 'undefined'
        ? EquipmentTuningDecisionPresenter : null;
    var WriteLifecycle =
        typeof EquipmentTuningWriteLifecycle !== 'undefined'
            ? EquipmentTuningWriteLifecycle : null;
    var LoadoutLifecycle =
        typeof EquipmentTuningLoadoutLifecycle !== 'undefined'
            ? EquipmentTuningLoadoutLifecycle : null;
    if (!Model || typeof Model.diagnosticAuthoritySourceKey !== 'function'
            || !Renderer || !DecisionPresenter || !WriteLifecycle
            || !LoadoutLifecycle) throw new Error(
        'EquipmentTuningView load order: model, decision presenter, renderer, confirmation, interaction, write lifecycle, loadout lifecycle, then view.');
    var wireRef = Model.wireRef;
    var sameRef = Model.sameRef;
    var refKey = Model.refKey;
    var normalizeTuningSource = Model.normalizeTuningSource;
    var diagnosticAuthoritySourceKey = Model.diagnosticAuthoritySourceKey;
    var tuningSourceSupports = Model.tuningSourceSupports;
    var normalizeConversionCandidates = Model.normalizeConversionCandidates;
    var previewIntentKey = Model.previewIntentKey;
    var isOperation = Model.isOperation;
    var isOperationGroup = Model.isOperationGroup;
    var nextEnhancementLevel = Model.nextEnhancementLevel;
    var errorMessage = Model.errorMessage;
    var enhancementAvailableMax = Model.enhancementAvailableMax;
    var candidateInstalled = Model.candidateInstalled;
    var defaultModFilterPath = Model.defaultModFilterPath;
    var Confirmation = typeof EquipmentTuningConfirmation !== 'undefined'
        ? EquipmentTuningConfirmation : null;
    var Components = typeof WorkbenchComponents !== 'undefined'
        ? WorkbenchComponents : null;
    var Interaction = typeof EquipmentTuningInteraction !== 'undefined'
        ? EquipmentTuningInteraction : null;


    function create(options) {
        return new TuningView(options || {});
    }

    function TuningView(options) {
        var self = this;
        if (!Confirmation || !Confirmation.shared || !Components
                || !Components.ChoiceGroup || !Components.CommitBar
                || !Interaction || !Interaction.interactionLockProjection) {
            throw new Error('EquipmentTuningView requires confirmation, interaction, and workbench component ports.');
        }
        this.instanceKey = String(options.instanceKey || 'equipment-tuning');
        this.instancePolicy = 'singletonByBinding';
        this.viewKind = 'equipment-tuning';
        this.allowedSlots = ['R'];
        this._send = typeof options.send === 'function' ? options.send : function(message) { return Bridge.send(message); };
        this._beginWrite = options.beginWrite || function() { return false; };
        this._completeWrite = options.completeWrite || function(_, __, callback) { if (callback) callback({success:false}); return false; };
        this._refreshInventory = options.refreshInventory || function(callback) {
            if (callback) callback({success:false, error:'inventory_refresh_unavailable'});
            return false;
        };
        this._refreshLoadout = options.refreshLoadout || function(_, callback) {
            if (callback) callback({success:false, error:'loadout_refresh_unavailable'});
            return false;
        };
        this._resolveSlot = options.resolveSlot || function() { return null; };
        this._onStateChange = options.onStateChange || function() {};
        this._toast = options.toast || function() {};
        this._densityController = options.densityController || null;
        this._loadConversionCandidates = options.loadConversionCandidates || function(_, __, callback) {
            if (callback) callback({success:false, error:'inventory_projection_unavailable'});
            return false;
        };
        this._inspectorAvailable = typeof options.openInspector === 'function';
        this._openInspector = this._inspectorAvailable
            ? options.openInspector : function() { return false; };
        this._closeInspector = typeof options.closeInspector === 'function'
            ? options.closeInspector : function() { return false; };
        this._root = null;
        this._panelInstanceId = '';
        this._viewSessionId = '';
        this._source = null;
        this._sourceItem = null;
        this._target = null;
        this._targetItem = null;
        this._snapshot = null;
        this._preview = null;
        this._previewDiagnostic = null;
        this._tooltipEpoch = 0;
        this._tooltipCache = {};
        this._tooltipScope = null;
        this._operation = 'enhance';
        this._targetLevel = 0;
        this._enhancePreviewTimer = 0;
        this._queuedEnhanceLevel = null;
        this._previewPendingOperation = '';
        this._previewIntentKey = '';
        this._previewRequestGeneration = 0;
        this._previewPendingGeneration = 0;
        this._conversionCandidates = [];
        this._conversionLoading = false;
        this._conversionError = '';
        this._conversionProjectionEpoch = 0;
        this._modFilterPath = defaultModFilterPath();
        this._modNavigator = null;
        this._replaceCandidateKey = '';
        this._replaceCandidateName = '';
        this._infoPanelOpen = false;
        this._infoSubject = null;
        this._confirmationPort = options.confirmationPort || Confirmation.shared;
        this._modConfirmationMode = this._confirmationPort.read();
        this._confirmationControl = null;
        this._confirmationChoice = null;
        this._confirmationBoundary = null;
        this._confirmationReason = null;
        this._confirmationUnsubscribe = null;
        this._commitBar = null;
        this._previewFocusIntent = null;
        this._detailScrollAnchor = null;
        this._interactionAnnouncement = '';
        this._diagnosticEvents = [];
        this._diagnosticSequence = 0;
        this._commitDiagnostic = null;
        this._diagnosticSink = typeof options.onDiagnostic === 'function'
            ? options.onDiagnostic : null;
        this._quickCommitIntent = null;
        this._modIntent = null;
        this._busy = false;
        this._inventoryWriteHandle = null;
        this._readPending = false;
        this._detaching = false;
        this._needsReconcile = false;
        this._lastCommitCallId = '';
        this._refreshRetryRequired = false;
        this._refreshRetryPending = false;
        this._refreshReconcileCallId = '';
        this._refreshChanged = false;
        this._loadoutBarrier = null;
        this._status = '请选择左侧背包装备';
        this._mux = new EquipmentTuningRuntime.RequestMux({
            send:function(message) { return self._send(message); },
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce,
            diagnostic:function(event) { self._recordDiagnostic(event); }
        });
        this._confirmationUnsubscribe = this._confirmationPort.subscribe(function(mode) {
            self._applyModConfirmationMode(mode);
        });
    }

    TuningView.prototype.mount = function(root) {
        this._root = root;
        this.root = root;
        if (this._densityController && this._densityController.register) this._densityController.register(this);
        this.render();
    };

    TuningView.prototype.unmount = function() {
        this._invalidateTooltipAuthority(false);
        if (this._densityController && this._densityController.unregister) this._densityController.unregister(this);
        this._root = null;
        this.root = null;
    };

    TuningView.prototype.subscribe = function() { return null; };

    TuningView.prototype._recordDiagnostic = function(event, detail) {
        if (typeof event === 'string') {
            detail = detail || {};
            detail.event = event;
            event = detail;
        }
        event = event && typeof event === 'object' ? event : {};
        var eventName = String(event.event || '');
        if (!/^(candidate_hit|lock_denied|intrinsic_unavailable|preview_issued|response_tuple_mismatch|preview_adopted|commit_issued|commit_adopted|inventory_refresh_settled|reconcile_issued|reconcile_adopted)$/.test(eventName)) {
            return false;
        }
        var record = {sequence:++this._diagnosticSequence, event:eventName};
        ['cmd', 'operation', 'capability', 'phase'].forEach(function(key) {
            var value = String(event[key] || '');
            if (/^[a-z_]{1,40}$/.test(value)) record[key] = value;
        });
        if (!record.operation && isOperation(this._operation)) {
            record.operation = this._operation;
        }
        if (event.mismatchFields instanceof Array) {
            record.mismatchFields = event.mismatchFields.filter(function(value) {
                return /^(type|domain|callId|cmd|panelInstanceId|viewSessionId)$/.test(String(value));
            }).slice(0, 6);
        }
        var muxState = this._mux ? this._mux.debugState() : {pendingCount:0};
        var sourceKey = event.sourceKey != null
            ? String(event.sourceKey) : diagnosticAuthoritySourceKey(this._source);
        var candidateKey = event.candidateKey != null
            ? String(event.candidateKey)
            : this._modIntent ? String(this._modIntent.candidateKey || '')
                : this._commitDiagnostic ? String(this._commitDiagnostic.candidateKey || '')
                    : this._previewDiagnostic ? String(this._previewDiagnostic.candidateKey || '') : '';
        var intentKey = event.intentKey != null
            ? String(event.intentKey)
            : this._commitDiagnostic ? String(this._commitDiagnostic.intentKey || '')
                : this._previewDiagnostic ? String(this._previewDiagnostic.intentKey || '')
                    : String(this._previewIntentKey || '');
        function bounded(value, limit) {
            return String(value || '').replace(/[\u0000-\u001f\u007f]/g, '').slice(0, limit);
        }
        record.webCallId = EquipmentTuningRuntime.safeToken(event.webCallId
            || event.event === 'inventory_refresh_settled'
                && this._commitDiagnostic && this._commitDiagnostic.webCallId || '');
        record.panelInstanceId = EquipmentTuningRuntime.safeToken(this._panelInstanceId);
        record.viewSessionId = EquipmentTuningRuntime.safeToken(this._viewSessionId);
        record.sourceKey = bounded(sourceKey, 180);
        record.candidateKey = bounded(candidateKey, 180);
        record.intentKey = bounded(intentKey, 384);
        record.reconcileAfterCallId = EquipmentTuningRuntime.safeToken(
            event.reconcileAfterCallId || ''
        );
        record.pendingCount = Math.max(0, Number(event.pendingCount != null
            ? event.pendingCount : muxState.pendingCount) || 0);
        ['success', 'tokenPresent', 'transactionIdPresent', 'requiresReconcile',
            'currentLeasePresent', 'needsReconcile', 'reconciled', 'noOp'].forEach(function(key) {
            if (typeof event[key] === 'boolean') record[key] = event[key];
        });
        if (typeof record.tokenPresent !== 'boolean') {
            record.tokenPresent = !!(this._preview && this._preview.tuningToken);
        }
        if (typeof record.needsReconcile !== 'boolean') {
            record.needsReconcile = this._needsReconcile === true;
        }
        record.confirmationMode = this._modConfirmationMode === 'fast' ? 'fast' : 'safe';
        record.autoCommitPending = record.confirmationMode === 'fast'
            && !!this._quickCommitIntent;
        record.writeState = this._refreshRetryPending ? 'refresh_pending'
            : this._refreshRetryRequired ? 'refresh_required'
                : this._inventoryWriteHandle ? 'write_pending'
                    : this._needsReconcile || this._loadoutBarrier
                        ? 'reconcile_required'
                        : this._readPending ? 'read_pending' : 'idle';
        record.commitReady = this.getInteractionProjection().commit === true;
        this._diagnosticEvents.push(record);
        if (this._diagnosticEvents.length > 24) this._diagnosticEvents.shift();
        try {
            this._send({
                type:'debug',
                scope:'equipment_tuning',
                sequence:record.sequence,
                event:record.event,
                cmd:record.cmd || '',
                operation:record.operation || '',
                capability:record.capability || '',
                phase:record.phase || '',
                webCallId:record.webCallId,
                panelInstanceId:record.panelInstanceId,
                viewSessionId:record.viewSessionId,
                sourceKey:record.sourceKey,
                candidateKey:record.candidateKey,
                intentKey:record.intentKey,
                reconcileAfterCallId:record.reconcileAfterCallId,
                pendingCount:record.pendingCount,
                tokenPresent:record.tokenPresent,
                commitReady:record.commitReady,
                confirmationMode:record.confirmationMode,
                autoCommitPending:record.autoCommitPending,
                writeState:record.writeState,
                success:typeof record.success === 'boolean' ? record.success : null,
                transactionIdPresent:typeof record.transactionIdPresent === 'boolean'
                    ? record.transactionIdPresent : null,
                requiresReconcile:typeof record.requiresReconcile === 'boolean'
                    ? record.requiresReconcile : null,
                currentLeasePresent:typeof record.currentLeasePresent === 'boolean'
                    ? record.currentLeasePresent : null,
                needsReconcile:typeof record.needsReconcile === 'boolean'
                    ? record.needsReconcile : null,
                reconciled:typeof record.reconciled === 'boolean'
                    ? record.reconciled : null,
                noOp:typeof record.noOp === 'boolean' ? record.noOp : null,
                mismatchFields:record.mismatchFields || []
            });
        } catch (_) {}
        if (this._diagnosticSink) this._diagnosticSink(record);
        return true;
    };

    TuningView.prototype._bindCommitDiagnostic = function(operation, callId) {
        var preview = this._previewDiagnostic || {};
        this._commitDiagnostic = {
            webCallId:EquipmentTuningRuntime.safeToken(callId),
            operation:String(operation || ''),
            candidateKey:String(preview.candidateKey || ''),
            intentKey:String(preview.intentKey || this._previewIntentKey || '')
        };
        return this._commitDiagnostic;
    };

    TuningView.prototype.getInteractionProjection = function() {
        return Interaction.interactionLockProjection({
            operation:this._operation,
            sourceKind:this._source && this._source.sourceKind || '',
            busy:this._busy,
            readPending:this._readPending,
            previewPendingOperation:this._previewPendingOperation,
            previewScheduled:!!this._enhancePreviewTimer
                || this._queuedEnhanceLevel != null,
            detaching:this._detaching,
            needsReconcile:this._needsReconcile,
            refreshRetryRequired:this._refreshRetryRequired,
            refreshRetryPending:this._refreshRetryPending,
            inventoryWritePending:!!this._inventoryWriteHandle,
            conversionLoading:this._conversionLoading,
            loadoutBarrier:this._loadoutBarrier,
            allowSourceRecovery:this._needsReconcile && !this._source
                && !!EquipmentTuningRuntime.safeToken(this._lastCommitCallId),
            hasPreviewToken:!!(this._preview && this._preview.tuningToken),
            mux:this._mux.debugState()
        });
    };

    TuningView.prototype._allowInteraction = function(capability, announce) {
        var projection = this.getInteractionProjection();
        if (projection[capability] === true) return true;
        this._recordDiagnostic('lock_denied', {
            capability:String(capability || ''),
            phase:String(projection.phase || '')
        });
        if (announce !== false && projection.reason
                && projection.reason !== this._interactionAnnouncement) {
            this._interactionAnnouncement = projection.reason;
            this._toast(projection.reason);
        }
        return false;
    };

    TuningView.prototype._capturePreviewFocusIntent = function(forceControlOrigin) {
        var document = this._root && this._root.ownerDocument;
        var active = document && document.activeElement;
        var editing = !!(active && active.matches
            && active.matches('input,textarea,select,[contenteditable="true"]'));
        if (editing) {
            this._previewFocusIntent = null;
            return false;
        }
        var fromControl = !!(active && this._root.contains(active)
            && active !== document.body);
        this._previewFocusIntent = forceControlOrigin || fromControl
            ? {origin:active || null} : null;
        return !!this._previewFocusIntent;
    };

    TuningView.prototype.openSession = function(panelInstanceId) {
        this.closeSession();
        this._diagnosticEvents = [];
        this._diagnosticSequence = 0;
        panelInstanceId = EquipmentTuningRuntime.safeToken(panelInstanceId);
        if (!panelInstanceId) {
            this._status = 'Host 面板实例无效';
            this.render({preserveScroll:false});
            return false;
        }
        this._panelInstanceId = panelInstanceId;
        this._viewSessionId = ('tuning.' + Date.now().toString(36) + '.'
            + Math.floor(Math.random() * 0x7fffffff).toString(36)).replace(/[^A-Za-z0-9._-]/g, '');
        this._createTooltipScope();
        var opened = this._mux.openSession(this._panelInstanceId, this._viewSessionId);
        this._status = opened ? '请选择左侧背包装备' : '无法建立调制会话';
        this._emit();
        this.render({preserveScroll:false});
        return opened;
    };

    TuningView.prototype._disposeTooltipScope = function() {
        if (this._tooltipScope && this._tooltipScope.dispose) this._tooltipScope.dispose();
        this._tooltipScope = null;
    };

    TuningView.prototype._createTooltipScope = function() {
        this._disposeTooltipScope();
        this._tooltipScope = typeof PanelTooltip !== 'undefined' && PanelTooltip.createScope
            ? PanelTooltip.createScope('equipment-tuning-' + this._tooltipEpoch,
                {profile:'dense-inspect'}) : null;
        return this._tooltipScope;
    };

    TuningView.prototype._invalidateTooltipAuthority = function(recreateScope) {
        this._tooltipEpoch++;
        this._tooltipCache = {};
        this._disposeTooltipScope();
        if (recreateScope !== false && this._viewSessionId) this._createTooltipScope();
        return this._tooltipEpoch;
    };

    TuningView.prototype._adoptSnapshot = function(snapshot) {
        if (!snapshot || typeof snapshot !== 'object' || snapshot instanceof Array) return false;
        this._invalidateTooltipAuthority();
        this._snapshot = snapshot;
        return true;
    };

    TuningView.prototype.closeSession = function() {
        this._closeInspector();
        this._setConversionProjection(false);
        if (this._enhancePreviewTimer) clearTimeout(this._enhancePreviewTimer);
        this._enhancePreviewTimer = 0;
        this._queuedEnhanceLevel = null;
        this._previewPendingOperation = '';
        this._previewIntentKey = '';
        this._previewPendingGeneration = 0;
        this._quickCommitIntent = null;
        this._modIntent = null;
        this._mux.closeSession();
        this._panelInstanceId = '';
        this._viewSessionId = '';
        this._source = null;
        this._sourceItem = null;
        this._target = null;
        this._targetItem = null;
        this._snapshot = null;
        this._preview = null;
        this._previewDiagnostic = null;
        this._previewIntentKey = '';
        this._invalidateTooltipAuthority(false);
        this._busy = false;
        this._inventoryWriteHandle = null;
        this._readPending = false;
        this._detaching = false;
        this._needsReconcile = false;
        this._lastCommitCallId = '';
        this._refreshRetryRequired = false;
        this._refreshRetryPending = false;
        this._refreshReconcileCallId = '';
        this._refreshChanged = false;
        this._loadoutBarrier = null;
        this._conversionCandidates = [];
        this._conversionLoading = false;
        this._conversionError = '';
        this._modFilterPath = defaultModFilterPath();
        this._replaceCandidateKey = '';
        this._replaceCandidateName = '';
        this._resetInfoPanel();
        this._quickCommitIntent = null;
        this._modIntent = null;
        this._previewFocusIntent = null;
        this._detailScrollAnchor = null;
        this._interactionAnnouncement = '';
        this._status = '调制会话已关闭';
        this._emit();
        this.render({preserveScroll:false});
    };

    TuningView.prototype.destroy = function() {
        this.closeSession();
        this._mux.destroy();
        if (this._modNavigator) { this._modNavigator.destroy(); this._modNavigator = null; }
        if (this._confirmationUnsubscribe) this._confirmationUnsubscribe();
        this._confirmationUnsubscribe = null;
        if (this._confirmationChoice) this._confirmationChoice.destroy();
        this._confirmationChoice = null;
        this._confirmationControl = null;
        this._confirmationBoundary = null;
        this._confirmationReason = null;
        if (this._commitBar) this._commitBar.destroy();
        this._commitBar = null;
        this._previewFocusIntent = null;
        this._detailScrollAnchor = null;
        if (this._densityController && this._densityController.unregister) this._densityController.unregister(this);
        this._root = null;
    };

    TuningView.prototype.canClose = function() {
        return !this._busy && !this._readPending && !this._detaching && !this._needsReconcile
            && !this._refreshRetryRequired && !this._refreshRetryPending
            && !this._inventoryWriteHandle
            && !this._loadoutBarrier
            && !this._conversionLoading
            && this._mux.debugState().pendingCount === 0;
    };

    TuningView.prototype.detachSession = function(callback) {
        callback = typeof callback === 'function' ? callback : function() {};
        if (!this._mux.debugState().active) { callback(true, {success:true, detached:true}); return true; }
        if (!this.canClose()) return false;
        var self = this;
        this._detaching = true;
        this._readPending = true;
        this._status = '正在撤销调制令牌';
        this._emit();
        this.render();
        var callId = this._mux.request('detach', {}, function(response) {
            self._readPending = false;
            self._detaching = false;
            if (response && response.success === true) {
                self.closeSession();
                callback(true, response);
                return;
            }
            self._status = errorMessage(response && response.error);
            self._emit();
            self.render();
            callback(false, response || {success:false, error:'detach_failed'});
        });
        if (!callId && this._readPending) {
            this._readPending = false;
            this._detaching = false;
            this._status = errorMessage('not_sent');
            this._emit();
            this.render();
            callback(false, {success:false, error:'not_sent'});
        }
        return !!callId;
    };

    TuningView.prototype.handleInventorySelection = function(slot) {
        var recoveryCallId = this._needsReconcile && !this._source
            ? EquipmentTuningRuntime.safeToken(this._lastCommitCallId) : '';
        if (!slot || !slot.occupied || !slot.item || slot.item.itemKind !== 'equipment'
                || !this._allowInteraction('source', false)
                || (this._needsReconcile && !recoveryCallId)) return false;
        this._closeInspector();
        var ref = normalizeTuningSource({
            sourceKind:'inventory',
            containerId:'背包',
            slot:Number(slot.physicalSlot != null ? slot.physicalSlot : slot.slot),
            expectedLease:String(slot.slotLease != null ? slot.slotLease : slot.expectedLease)
        });
        if (!ref) return false;
        this._setConversionProjection(false);
        this._resetInfoPanel();
        this._source = ref;
        this._sourceItem = slot.item;
        this._target = null;
        this._targetItem = null;
        this._snapshot = null;
        this._preview = null;
        this._previewDiagnostic = null;
        this._replaceCandidateKey = '';
        this._replaceCandidateName = '';
        this._quickCommitIntent = null;
        this._modIntent = null;
        this._needsReconcile = !!recoveryCallId;
        this._status = recoveryCallId ? '正在用新位置完成未知提交对账' : '正在读取权威调制状态';
        this._emit();
        this.render({preserveScroll:false});
        this.requestSnapshot(recoveryCallId);
        return true;
    };

    TuningView.prototype.handleLoadoutSelection = function(source, item) {
        var normalized = normalizeTuningSource(source);
        if (!normalized || normalized.sourceKind !== 'loadout' || !item
                || item.itemKind !== 'equipment'
                || !this._allowInteraction('source', false)) return false;
        this._closeInspector();
        this._setConversionProjection(false);
        this._source = normalized;
        this._sourceItem = item;
        this._target = null;
        this._targetItem = null;
        this._snapshot = null;
        this._preview = null;
        this._replaceCandidateKey = '';
        this._replaceCandidateName = '';
        this._resetInfoPanel();
        this._quickCommitIntent = null;
        this._modIntent = null;
        if (!tuningSourceSupports(normalized, this._operation)) this._operation = 'enhance';
        this._status = '正在读取当前槽位的权威调制状态';
        this._emit();
        this.render({preserveScroll:false});
        this.requestSnapshot();
        return true;
    };

    TuningView.prototype.selectConversionTarget = function(slot) {
        if (this._operation !== 'convert' || !this._source || !this._snapshot
                || !tuningSourceSupports(this._source, 'convert')
                || !slot || !slot.occupied || !slot.item || slot.item.itemKind !== 'equipment'
                || !this._allowInteraction('conversionCandidate')) return false;
        var ref = wireRef(slot);
        if (sameRef(this._source, ref) || String(slot.item.use || '') !== String(this._sourceItem && this._sourceItem.use || '')) {
            return false;
        }
        var sourceLevel = Number(this._sourceItem && this._sourceItem.enhancementLevel);
        var targetLevel = Number(slot.item.enhancementLevel);
        if (isFinite(sourceLevel) && isFinite(targetLevel) && sourceLevel === targetLevel) return false;
        this._closeInspector();
        this._target = ref;
        this._targetItem = slot.item;
        this._preview = null;
        this._capturePreviewFocusIntent(true);
        this.render();
        return this.requestPreview('convert', {target:ref, focusNext:true});
    };

    TuningView.prototype._inspectAvailable = function(item) {
        var gender = this._snapshot && String(this._snapshot.gender || '');
        return this._inspectorAvailable && !!item && (gender === '男' || gender === '女');
    };

    TuningView.prototype._canInspect = function(item) {
        return this._inspectAvailable(item) && this._allowInteraction('inspect', false);
    };

    TuningView.prototype.inspectCurrentEquipment = function() {
        if (!this._canInspect(this._sourceItem)) return false;
        return this._openInspector(this._sourceItem, String(this._snapshot.gender), 'source') !== false;
    };

    TuningView.prototype.inspectConversionTarget = function() {
        if (this._operation !== 'convert' || !this._target || !this._canInspect(this._targetItem)) return false;
        return this._openInspector(this._targetItem, String(this._snapshot.gender), 'conversion-target') !== false;
    };

    TuningView.prototype.requestSnapshot = function(reconcileAfterCallId) {
        if (!this._source || this._busy || this._readPending || this._detaching
                || this._refreshRetryRequired || this._refreshRetryPending) return false;
        var self = this;
        var payload = {source:this._source};
        if (reconcileAfterCallId) payload.reconcileAfterCallId = reconcileAfterCallId;
        this._snapshot = null;
        this._preview = null;
        this._previewPendingOperation = '';
        this._previewIntentKey = '';
        this._previewPendingGeneration = 0;
        this._quickCommitIntent = null;
        this._modIntent = null;
        this._status = reconcileAfterCallId ? '正在对账未知提交' : '正在同步调制状态';
        this._readPending = true;
        this.render();
        var callId = this._mux.request('snapshot', payload, function(response, entry) {
            self._readPending = false;
            var resumeCallId = !reconcileAfterCallId && response && response.requiresReconcile
                ? EquipmentTuningRuntime.safeToken(response.reconcileAfterCallId) : '';
            if (resumeCallId) {
                self._lastCommitCallId = resumeCallId;
                self._needsReconcile = true;
                self._status = '正在恢复上次中断的提交对账';
                self._emit();
                self.render();
                self.requestSnapshot(resumeCallId);
                return;
            }
            var reconcileConfirmed = !reconcileAfterCallId || (response && response.reconciled === true
                && response.reconcileAfterCallId === reconcileAfterCallId);
            if (response && response.success === true && response.snapshot && reconcileConfirmed) {
                self._adoptSnapshot(response.snapshot);
                self._preview = null;
                if (self._replaceCandidateKey && !candidateInstalled(
                        response.snapshot.modCandidates, self._replaceCandidateKey)) {
                    self._replaceCandidateKey = '';
                    self._replaceCandidateName = '';
                    if (self._operation === 'replace_mod') self._operation = 'install_mod';
                }
                self._needsReconcile = false;
                if (reconcileAfterCallId) self._lastCommitCallId = '';
                self._targetLevel = nextEnhancementLevel(response.snapshot);
                self._status = '装备状态已同步';
            } else {
                self._needsReconcile = !!reconcileAfterCallId || !!(response && response.requiresReconcile);
                self._status = reconcileAfterCallId && response && response.success === true
                    ? '权威快照尚未越过未知提交' : errorMessage(response && response.error);
            }
            if (reconcileAfterCallId) {
                self._recordDiagnostic('reconcile_adopted', {
                    webCallId:entry && entry.callId,
                    reconcileAfterCallId:reconcileAfterCallId,
                    success:!!(response && response.success === true && reconcileConfirmed),
                    reconciled:!!(response && response.reconciled === true
                        && response.reconcileAfterCallId === reconcileAfterCallId),
                    requiresReconcile:!!(response && response.requiresReconcile),
                    needsReconcile:self._needsReconcile === true
                });
                if (!self._needsReconcile) self._commitDiagnostic = null;
            }
            if (self._snapshot && self._operation === 'enhance'
                    && Number(self._snapshot.enhance.currentLevel) < enhancementAvailableMax(self._snapshot)) {
                self.scheduleEnhancementPreview(self._targetLevel, 120);
            }
            self._emit();
            self.render();
            if (self._snapshot && reconcileAfterCallId && self._loadoutBarrier
                    && self._loadoutBarrier.kind === 'unknown'
                    && self._loadoutBarrier.callId === reconcileAfterCallId) {
                self._finishLoadoutBarrier();
                return;
            }
            if (self._snapshot && self._operation === 'convert') self._setConversionProjection(true);
        }, reconcileAfterCallId ? {
            onIssued:function(entry) {
                self._recordDiagnostic('reconcile_issued', {
                    webCallId:entry && entry.callId,
                    reconcileAfterCallId:reconcileAfterCallId,
                    needsReconcile:true
                });
            }
        } : null);
        if (!callId && this._readPending) { this._readPending = false; this.render(); }
        return !!callId;
    };

    TuningView.prototype.requestPreview = function(operation, extra) {
        operation = String(operation || this._operation);
        if (!isOperation(operation) || !tuningSourceSupports(this._source, operation)) return false;
        extra = extra || {};
        var capability = operation === 'enhance' ? 'stepper'
            : operation === 'convert' ? 'conversionCandidate'
            : operation === 'install_tier' ? 'tier'
            : operation === 'detach_mod' || operation === 'detach_all_mods'
                ? 'detach' : 'candidate';
        if (!this._source || !this._allowInteraction(capability)) return false;
        if (operation === 'enhance') this._previewFocusIntent = null;
        else this._capturePreviewFocusIntent(extra.focusNext === true);
        this._operation = operation;
        // A preview attempt immediately supersedes the prior token. Keep this
        // boundary ahead of local payload checks so a rejected attempt cannot
        // leave the old confirmation/commit path active.
        this._preview = null;
        this._previewDiagnostic = null;
        this._quickCommitIntent = null;
        var payload = {operation:operation, source:this._source};
        if (operation === 'enhance') payload.targetLevel = Math.floor(Number(extra.targetLevel || this._targetLevel));
        else if (operation === 'convert') payload.target = extra.target || this._target;
        else if (operation !== 'detach_all_mods') payload.candidateKey = String(extra.candidateKey || '');
        if (operation === 'replace_mod') {
            payload.replaceCandidateKey = String(extra.replaceCandidateKey || this._replaceCandidateKey || '');
        }
        var intentKey = previewIntentKey(operation, payload);
        this._previewIntentKey = intentKey;
        if ((operation === 'convert' && !payload.target)
                || (operation !== 'enhance' && operation !== 'convert' && operation !== 'detach_all_mods'
                    && !payload.candidateKey)
                || (operation === 'replace_mod' && !payload.replaceCandidateKey)) {
            this._previewPendingOperation = '';
            this._modIntent = null;
            this._readPending = false;
            this._status = errorMessage('invalid_payload');
            this._emit();
            this.render({previewOnly:true});
            return false;
        }
        var self = this;
        var quickCommit = extra.quickCommit === true && this._modConfirmationMode === 'fast'
            && (operation === 'install_mod' || operation === 'replace_mod' || operation === 'detach_mod');
        this._quickCommitIntent = quickCommit ? {
            intentKey:intentKey,
            operation:operation,
            candidateName:String(extra.candidateName || ''),
            replaceCandidateName:String(extra.replaceCandidateName || '')
        } : null;
        this._previewPendingOperation = operation;
        var requestGeneration = ++this._previewRequestGeneration;
        this._previewPendingGeneration = requestGeneration;
        this._modIntent = this._createModIntent(
            operation,
            payload,
            extra,
            intentKey
        );
        this._status = this._modIntent
            ? this._modIntentStatus('preview_pending')
            : '正在核算调制结果';
        this._readPending = true;
        this.render({previewOnly:true});
        var callId = this._mux.request('preview', payload, function(response, entry) {
            var isLatestIntent = self._previewIntentKey === intentKey;
            var ownsPending = self._previewPendingGeneration === requestGeneration;
            // A late response belongs only to its superseded intent. It must not
            // clear, restore, or otherwise mutate a newer in-flight generation. An
            // enhancement request whose queued target changed still owns the pending
            // lock, so settle only that lock and drain the queued latest target.
            if (!isLatestIntent || !ownsPending) {
                if (ownsPending) {
                    self._readPending = false;
                    self._previewPendingOperation = '';
                    self._previewPendingGeneration = 0;
                    self._emit();
                    self.render({previewOnly:true});
                    self._drainEnhancementPreview();
                }
                return;
            }
            self._readPending = false;
            self._previewPendingOperation = '';
            self._previewPendingGeneration = 0;
            if (response && response.success === true) {
                self._preview = response;
                self._previewDiagnostic = {
                    webCallId:entry && entry.callId,
                    operation:operation,
                    candidateKey:String(payload.candidateKey || ''),
                    intentKey:intentKey
                };
                self._recordDiagnostic('preview_adopted', {
                    operation:operation,
                    webCallId:entry && entry.callId,
                    candidateKey:payload.candidateKey,
                    intentKey:intentKey
                });
                self._status = response.noOp ? '该操作不会改变装备' : '';
                self._setModIntentPhase('preview_ready');
            } else {
                self._preview = null;
                self._previewDiagnostic = null;
                self._modIntent = null;
                self._status = errorMessage(response && response.error);
            }
            var quickIntentReady = !!self._preview
                && self._quickCommitIntent
                && self._quickCommitIntent.intentKey === intentKey;
            if (quickIntentReady && self._tryQuickCommit(intentKey)) {
                self._drainEnhancementPreview();
                return;
            }
            self._emit();
            self.render({
                previewOnly:true,
                focusNext:!!self._preview
            });
            self._drainEnhancementPreview();
        }, {
            onIssued:function(entry) {
                self._recordDiagnostic('preview_issued', {
                    operation:operation,
                    webCallId:entry && entry.callId,
                    candidateKey:payload.candidateKey,
                    intentKey:intentKey
                });
            }
        });
        if (!callId && this._readPending) {
            this._readPending = false;
            this._previewPendingOperation = '';
            if (this._previewPendingGeneration === requestGeneration) {
                this._previewPendingGeneration = 0;
            }
            this._previewFocusIntent = null;
            this._modIntent = null;
            this._quickCommitIntent = null;
            this._emit();
            this.render({previewOnly:true});
        }
        return !!callId;
    };

    TuningView.prototype.commit = function() {
        if (!this._preview || !this._preview.tuningToken
                || !this._allowInteraction('commit')) return false;
        if (this._source && this._source.sourceKind === 'loadout') {
            return this._commitLoadout();
        }
        this._quickCommitIntent = null;
        this._setModIntentPhase('write_pending');
        var inventoryWrite = this._beginWrite('equipment_tuning.commit');
        if (!inventoryWrite) {
            this._setModIntentPhase('preview_ready');
            this._toast('背包正在执行其他操作，请稍候。');
            return false;
        }
        this._inventoryWriteHandle = inventoryWrite;
        var self = this;
        var committedOperation = String(this._preview.operation || '');
        this._busy = true;
        this._status = this._modIntent
            ? this._modIntentStatus('write_pending')
            : '正在提交，期间不会重放';
        this.render({previewOnly:true});
        var commitResponseSettled = false;
        var callId = this._mux.request('commit', {expectedTuningToken:String(this._preview.tuningToken)}, function(response, entry) {
            commitResponseSettled = true;
            if (self._inventoryWriteHandle !== inventoryWrite) return;
            var ambiguous = EquipmentTuningRuntime.isAmbiguous(response);
            var noOp = !!(response && response.success === true && response.noOp);
            self._recordDiagnostic('commit_adopted', {
                operation:committedOperation,
                webCallId:entry && entry.callId,
                success:!!(response && response.success === true),
                tokenPresent:true,
                transactionIdPresent:!!(response && response.transactionId),
                requiresReconcile:ambiguous,
                noOp:!!(response && response.noOp === true)
            });
            if (response && response.success === true) {
                var committedSnapshot = response.snapshot || null;
                if (committedSnapshot) self._adoptSnapshot(committedSnapshot);
                self._preview = null;
                if (committedOperation === 'replace_mod' || committedOperation === 'detach_mod') {
                    self._replaceCandidateKey = '';
                    self._replaceCandidateName = '';
                    self._operation = 'install_mod';
                }
                self._lastCommitCallId = '';
                self._setModIntentPhase('committed_syncing');
                self._status = noOp ? '无变化，未写入存档'
                    : self._modIntent
                        ? self._modIntentStatus('committed_syncing')
                        : '提交成功，正在刷新背包';
                self._emit();
                self.render();
                if (!self._finishInventoryWrite(inventoryWrite, !noOp, function(refreshResult) {
                    self._afterInventoryRefresh(
                        '',
                        !noOp,
                        refreshResult,
                        committedSnapshot
                    );
                })) return;
                self._toast(noOp ? '两件装备强化度相同，无需写入。' : '装备调制已提交。');
                return;
            }
            self._preview = null;
            if (ambiguous) {
                var barrierId = EquipmentTuningRuntime.safeToken(response && response.reconcileAfterCallId)
                    || EquipmentTuningRuntime.safeToken(callId);
                self._needsReconcile = true;
                self._lastCommitCallId = barrierId;
                self._setModIntentPhase('uncertain');
                self._status = '提交结果不明确，正在刷新并对账';
                if (!self._finishInventoryWrite(inventoryWrite, true, function(refreshResult) {
                    self._afterInventoryRefresh(barrierId, true, refreshResult);
                })) return;
            } else {
                self._lastCommitCallId = '';
                self._modIntent = null;
                self._status = errorMessage(response && response.error);
                var staleLease = response && (response.error === 'stale_state' || response.error === 'stale_lease');
                if (!self._finishInventoryWrite(inventoryWrite, !!staleLease, function(refreshResult) {
                    if (staleLease) self._afterInventoryRefresh('', false, refreshResult);
                    else self.requestSnapshot();
                })) return;
            }
            self._emit();
            self.render();
        }, {
            onIssued:function(entry) {
                var diagnostic = self._bindCommitDiagnostic(
                    committedOperation,
                    entry && entry.callId
                );
                self._recordDiagnostic('commit_issued', {
                    operation:committedOperation,
                    webCallId:entry && entry.callId,
                    candidateKey:diagnostic.candidateKey,
                    intentKey:diagnostic.intentKey,
                    tokenPresent:true
                });
            }
        });
        if (!callId && this._inventoryWriteHandle === inventoryWrite) {
            this._needsReconcile = false;
            this._lastCommitCallId = '';
            this._modIntent = null;
            this._status = errorMessage('not_sent');
            this._finishInventoryWrite(inventoryWrite, false, function() { self.requestSnapshot(); });
            this._emit();
            this.render();
        } else if (!commitResponseSettled) {
            // RequestMux can settle a definitive local send failure synchronously. Keep
            // the generated watermark while the request is still pending. A synchronously
            // settled ambiguous response may already have replaced it with a Host hint.
            this._lastCommitCallId = callId;
        } else if (!this._needsReconcile) {
            this._lastCommitCallId = '';
        }
        return !!callId;
    };

    TuningView.prototype._applyModConfirmationMode = function(mode) {
        mode = mode === 'fast' ? 'fast' : 'safe';
        if (this._modConfirmationMode === mode) return true;
        this._modConfirmationMode = mode;
        this._quickCommitIntent = null;
        this._emit();
        this.render();
        return true;
    };

    TuningView.prototype.setModConfirmationMode = function(mode) {
        if (!this._allowInteraction('confirmation')) return false;
        return this._confirmationPort.set(mode) === (mode === 'fast' ? 'fast' : 'safe');
    };

    TuningView.prototype.getConfirmationState = function() {
        return Confirmation.project(this._modConfirmationMode, {
            interaction:this.getInteractionProjection()
        });
    };

    TuningView.prototype.openHelp = function(openModal) {
        if (!this._root) return false;
        if (typeof openModal === 'function') return !!openModal(Confirmation.helpSpec());
        this._infoSubject = {
            key:'confirmation-help',
            title:'逐次确认与单件快捷',
            detail:'逐次确认会停在预览等待提交；单件快捷只自动提交安全的单件配件操作。'
                + Confirmation.BOUNDARY_TEXT + '。打开或收起说明不会改变可执行能力。'
        };
        return this._openInfoPanel();
    };

    TuningView.prototype._resetInfoPanel = function() {
        this._infoPanelOpen = false;
        this._infoSubject = null;
    };

    TuningView.prototype.setOperation = function(operation) {
        if (!isOperationGroup(operation)
                || !tuningSourceSupports(this._source, operation)
                || !this._allowInteraction('tabs')) return false;
        this._closeInspector();
        if (operation !== 'enhance') {
            if (this._enhancePreviewTimer) clearTimeout(this._enhancePreviewTimer);
            this._enhancePreviewTimer = 0;
            this._queuedEnhanceLevel = null;
        }
        var wasConvert = this._operation === 'convert';
        var operationChanged = this._operation !== operation;
        this._operation = operation;
        if (operationChanged) this._infoSubject = null;
        this._preview = null;
        this._previewIntentKey = '';
        this._quickCommitIntent = null;
        this._modIntent = null;
        if (operation !== 'install_mod') {
            this._replaceCandidateKey = '';
            this._replaceCandidateName = '';
        }
        if (operation !== 'convert') { this._target = null; this._targetItem = null; }
        if (wasConvert !== (operation === 'convert')) this._setConversionProjection(operation === 'convert');
        if (operation === 'enhance' && this._snapshot) {
            this.scheduleEnhancementPreview(this._targetLevel, 80);
        }
        this.render({preserveScroll:false});
        return true;
    };

    TuningView.prototype._selectReplacementCandidate = function(candidate) {
        if (!candidate || !candidate.candidateKey
                || !this._allowInteraction('slot')) return false;
        this._operation = 'install_mod';
        this._replaceCandidateKey = String(candidate.candidateKey);
        this._replaceCandidateName = String(candidate.itemName || '');
        this._preview = null;
        this._previewIntentKey = '';
        this._quickCommitIntent = null;
        this._modIntent = null;
        this._status = '请选择要替换成的配件';
        this.render();
        return true;
    };

    TuningView.prototype._clearReplacementCandidate = function() {
        if (!this._allowInteraction('slot')) return false;
        this._replaceCandidateKey = '';
        this._replaceCandidateName = '';
        if (this._operation === 'replace_mod') this._operation = 'install_mod';
        this._preview = null;
        this._previewIntentKey = '';
        this._quickCommitIntent = null;
        this._modIntent = null;
        this._status = '已取消配件替换';
        this.render();
        return true;
    };

    TuningView.prototype.scheduleEnhancementPreview = function(level, delay) {
        if (!this._snapshot) return false;
        var enhance = this._snapshot.enhance || {};
        var current = Number(enhance.currentLevel || 0);
        var max = enhancementAvailableMax(this._snapshot);
        if (current >= max) return false;
        level = Math.max(current + 1, Math.min(max, Math.floor(Number(level))));
        if (!isFinite(level)) level = current + 1;
        this._targetLevel = level;
        this._queuedEnhanceLevel = level;
        this._previewIntentKey = 'enhance|' + level;
        if (this._enhancePreviewTimer) clearTimeout(this._enhancePreviewTimer);
        var self = this;
        this._enhancePreviewTimer = setTimeout(function() {
            self._enhancePreviewTimer = 0;
            self._drainEnhancementPreview();
        }, Math.max(0, Number(delay) || 0));
        return true;
    };

    TuningView.prototype._drainEnhancementPreview = function() {
        if (this._operation !== 'enhance' || this._queuedEnhanceLevel == null || this._enhancePreviewTimer
                || this._busy || this._readPending || this._detaching || this._needsReconcile
                || this._refreshRetryRequired || this._refreshRetryPending) return false;
        var level = this._queuedEnhanceLevel;
        this._queuedEnhanceLevel = null;
        if (!this.requestPreview('enhance', {targetLevel:level})) {
            this._queuedEnhanceLevel = level;
            return false;
        }
        return true;
    };

    TuningView.prototype._setConversionProjection = function(active) {
        active = !!active && this._operation === 'convert'
            && tuningSourceSupports(this._source, 'convert')
            && !!this._sourceItem && !!this._source && !!this._snapshot;
        var epoch = ++this._conversionProjectionEpoch;
        if (!active) {
            this._conversionCandidates = [];
            this._conversionLoading = false;
            this._conversionError = '';
            return false;
        }
        var self = this;
        var sourceKey = refKey(this._source);
        this._conversionCandidates = [];
        this._conversionLoading = true;
        this._conversionError = '';
        this.render();
        var callbackCalled = false;
        var started = this._loadConversionCandidates(this._sourceItem, this._source, function(state) {
            callbackCalled = true;
            if (epoch !== self._conversionProjectionEpoch || self._operation !== 'convert'
                    || sourceKey !== refKey(self._source)) return;
            self._conversionLoading = false;
            if (state && state.success === true && Array.isArray(state.candidates)) {
                self._conversionCandidates = normalizeConversionCandidates(state.candidates, self._source, self._sourceItem);
                self._conversionError = '';
            } else {
                self._conversionCandidates = [];
                self._conversionError = errorMessage(state && state.error || 'inventory_projection_failed');
            }
            self._emit();
            self.render();
        });
        if (!started && !callbackCalled && epoch === this._conversionProjectionEpoch) {
            this._conversionLoading = false;
            this._conversionError = '当前无法读取同类装备，请稍后重试。';
            this._emit();
            this.render();
        }
        return !!started;
    };


    TuningView.prototype.debugState = function() {
        return {operation:this._operation, source:this._source, target:this._target, busy:this._busy, readPending:this._readPending,
            inventoryWritePending:!!this._inventoryWriteHandle,
            detaching:this._detaching, refreshRetryRequired:this._refreshRetryRequired,
            refreshRetryPending:this._refreshRetryPending, refreshReconcileCallId:this._refreshReconcileCallId,
            needsReconcile:this._needsReconcile, hasSnapshot:!!this._snapshot, hasPreview:!!this._preview,
            gender:this._snapshot ? String(this._snapshot.gender || '') : '',
            targetLevel:this._targetLevel, queuedEnhanceLevel:this._queuedEnhanceLevel,
            previewPendingOperation:this._previewPendingOperation, previewIntentKey:this._previewIntentKey,
            conversionLoading:this._conversionLoading, conversionCandidateCount:this._conversionCandidates.length,
            conversionError:this._conversionError,
            modFilterPath:this._modFilterPath.slice(),
            replaceCandidateKey:this._replaceCandidateKey, replaceCandidateName:this._replaceCandidateName,
            infoPanelOpen:this._infoPanelOpen,
            infoSubjectKey:this._infoSubject ? String(this._infoSubject.key || '') : '',
            modConfirmationMode:this._modConfirmationMode, quickCommitPending:!!this._quickCommitIntent,
            modIntent:this._modIntent ? {
                intentKey:this._modIntent.intentKey,
                operation:this._modIntent.operation,
                candidateKey:this._modIntent.candidateKey,
                replaceCandidateKey:this._modIntent.replaceCandidateKey,
                phase:this._modIntent.phase
            } : null,
            confirmationChoice:this.getConfirmationState(),
            interaction:this.getInteractionProjection(),
            sourceKind:this._source && this._source.sourceKind || '',
            loadoutBarrier:this._loadoutBarrier ? {
                kind:this._loadoutBarrier.kind,
                callId:this._loadoutBarrier.callId,
                changed:this._loadoutBarrier.changed,
                sessionGeneration:this._loadoutBarrier.source
                    ? this._loadoutBarrier.source.sessionGeneration : 0,
                slotKey:this._loadoutBarrier.source
                    ? this._loadoutBarrier.source.slotKey : ''
            } : null,
            lastCommitCallId:this._lastCommitCallId,
            tooltipEpoch:this._tooltipEpoch,
            tooltipCacheCount:Object.keys(this._tooltipCache).length,
            diagnostics:this._diagnosticEvents.slice(), mux:this._mux.debugState()};
    };

    TuningView.prototype._emit = function() { this._onStateChange(this.debugState()); };

    WriteLifecycle.install(TuningView, Model);
    LoadoutLifecycle.install(TuningView, Model);
    DecisionPresenter.install(TuningView, Model);
    Renderer.install(TuningView, Model);

    return {create:create};
})();
