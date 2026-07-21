/** Right-hand equipment tuning view for the owned inventory workbench. */
var EquipmentTuningView = (function() {
    'use strict';

    var Model = typeof EquipmentTuningModel !== 'undefined' ? EquipmentTuningModel : null;
    var Renderer = typeof EquipmentTuningRender !== 'undefined' ? EquipmentTuningRender : null;
    if (!Model || !Renderer) {
        throw new Error('EquipmentTuningView load order: item-filter.js, equipment-tuning-model.js, equipment-tuning-render.js, then equipment-tuning-view.js.');
    }
    var wireRef = Model.wireRef;
    var sameRef = Model.sameRef;
    var refKey = Model.refKey;
    var quickCommitEligible = Model.quickCommitEligible;
    var normalizeConversionCandidates = Model.normalizeConversionCandidates;
    var previewIntentKey = Model.previewIntentKey;
    var isOperation = Model.isOperation;
    var isOperationGroup = Model.isOperationGroup;
    var nextEnhancementLevel = Model.nextEnhancementLevel;
    var errorMessage = Model.errorMessage;
    var enhancementAvailableMax = Model.enhancementAvailableMax;
    var candidateInstalled = Model.candidateInstalled;


    function create(options) {
        return new TuningView(options || {});
    }

    function TuningView(options) {
        var self = this;
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
        this._resolveSlot = options.resolveSlot || function() { return null; };
        this._onStateChange = options.onStateChange || function() {};
        this._toast = options.toast || function() {};
        this._densityController = options.densityController || null;
        this._loadConversionCandidates = options.loadConversionCandidates || function(_, __, callback) {
            if (callback) callback({success:false, error:'inventory_projection_unavailable'});
            return false;
        };
        this._openInspector = typeof options.openInspector === 'function'
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
        this._tooltipCache = {};
        this._operation = 'enhance';
        this._targetLevel = 0;
        this._enhancePreviewTimer = 0;
        this._queuedEnhanceLevel = null;
        this._previewPendingOperation = '';
        this._previewIntentKey = '';
        this._conversionCandidates = [];
        this._conversionLoading = false;
        this._conversionError = '';
        this._conversionProjectionEpoch = 0;
        this._modFilterPath = [];
        this._modNavigator = null;
        this._replaceCandidateKey = '';
        this._replaceCandidateName = '';
        this._modConfirmationMode = options.modConfirmationMode === 'fast' ? 'fast' : 'safe';
        this._quickCommitIntent = null;
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
        this._status = '请选择左侧背包装备';
        this._mux = new EquipmentTuningRuntime.RequestMux({
            send:function(message) { return self._send(message); },
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce
        });
    }

    TuningView.prototype.mount = function(root) {
        this._root = root;
        this.root = root;
        if (this._densityController && this._densityController.register) this._densityController.register(this);
        this.render();
    };

    TuningView.prototype.unmount = function() {
        if (this._densityController && this._densityController.unregister) this._densityController.unregister(this);
        this._root = null;
        this.root = null;
    };

    TuningView.prototype.subscribe = function() { return null; };

    TuningView.prototype.openSession = function(panelInstanceId) {
        this.closeSession();
        panelInstanceId = EquipmentTuningRuntime.safeToken(panelInstanceId);
        if (!panelInstanceId) {
            this._status = 'Host 面板实例无效';
            this.render({preserveScroll:false});
            return false;
        }
        this._panelInstanceId = panelInstanceId;
        this._viewSessionId = ('tuning.' + Date.now().toString(36) + '.'
            + Math.floor(Math.random() * 0x7fffffff).toString(36)).replace(/[^A-Za-z0-9._-]/g, '');
        var opened = this._mux.openSession(this._panelInstanceId, this._viewSessionId);
        this._status = opened ? '请选择左侧背包装备' : '无法建立调制会话';
        this._emit();
        this.render({preserveScroll:false});
        return opened;
    };

    TuningView.prototype.closeSession = function() {
        this._closeInspector();
        this._setConversionProjection(false);
        if (this._enhancePreviewTimer) clearTimeout(this._enhancePreviewTimer);
        this._enhancePreviewTimer = 0;
        this._queuedEnhanceLevel = null;
        this._previewPendingOperation = '';
        this._previewIntentKey = '';
        this._quickCommitIntent = null;
        this._mux.closeSession();
        this._panelInstanceId = '';
        this._viewSessionId = '';
        this._source = null;
        this._sourceItem = null;
        this._target = null;
        this._targetItem = null;
        this._snapshot = null;
        this._preview = null;
        this._previewIntentKey = '';
        this._tooltipCache = {};
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
        this._conversionCandidates = [];
        this._conversionLoading = false;
        this._conversionError = '';
        this._modFilterPath = [];
        this._replaceCandidateKey = '';
        this._replaceCandidateName = '';
        this._quickCommitIntent = null;
        this._status = '调制会话已关闭';
        this._emit();
        this.render({preserveScroll:false});
    };

    TuningView.prototype.destroy = function() {
        this.closeSession();
        this._mux.destroy();
        if (this._modNavigator) { this._modNavigator.destroy(); this._modNavigator = null; }
        if (this._densityController && this._densityController.unregister) this._densityController.unregister(this);
        this._root = null;
    };

    TuningView.prototype.canClose = function() {
        return !this._busy && !this._readPending && !this._detaching && !this._needsReconcile
            && !this._refreshRetryRequired && !this._refreshRetryPending
            && !this._inventoryWriteHandle
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
                || this._busy || this._readPending || this._detaching
                || this._refreshRetryRequired || this._refreshRetryPending
                || (this._needsReconcile && !recoveryCallId)
                || this._mux.debugState().pendingCount > 0) return false;
        this._closeInspector();
        var ref = wireRef(slot);
        this._setConversionProjection(false);
        this._source = ref;
        this._sourceItem = slot.item;
        this._target = null;
        this._targetItem = null;
        this._snapshot = null;
        this._preview = null;
        this._replaceCandidateKey = '';
        this._replaceCandidateName = '';
        this._quickCommitIntent = null;
        this._needsReconcile = !!recoveryCallId;
        this._status = recoveryCallId ? '正在用新位置完成未知提交对账' : '正在读取权威调制状态';
        this.render({preserveScroll:false});
        this.requestSnapshot(recoveryCallId);
        return true;
    };

    TuningView.prototype.selectConversionTarget = function(slot) {
        if (this._operation !== 'convert' || !this._source || !this._snapshot
                || !slot || !slot.occupied || !slot.item || slot.item.itemKind !== 'equipment'
                || this._busy || this._readPending || this._detaching || this._conversionLoading
                || this._refreshRetryRequired || this._refreshRetryPending || this._needsReconcile) return false;
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
        this.render();
        return this.requestPreview('convert', {target:ref});
    };

    TuningView.prototype._canInspect = function(item) {
        var gender = this._snapshot && String(this._snapshot.gender || '');
        return !!item && (gender === '男' || gender === '女')
            && !this._busy && !this._readPending && !this._detaching && !this._needsReconcile
            && !this._refreshRetryRequired && !this._refreshRetryPending
            && !this._inventoryWriteHandle && !this._conversionLoading && !this._enhancePreviewTimer
            && this._queuedEnhanceLevel == null
            && this._mux.debugState().pendingCount === 0;
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
        this._quickCommitIntent = null;
        this._status = reconcileAfterCallId ? '正在对账未知提交' : '正在同步调制状态';
        this._readPending = true;
        this.render();
        var callId = this._mux.request('snapshot', payload, function(response) {
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
                self._snapshot = response.snapshot;
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
            if (self._snapshot && self._operation === 'enhance'
                    && Number(self._snapshot.enhance.currentLevel) < enhancementAvailableMax(self._snapshot)) {
                self.scheduleEnhancementPreview(self._targetLevel, 120);
            }
            self._emit();
            self.render();
            if (self._snapshot && self._operation === 'convert') self._setConversionProjection(true);
        });
        if (!callId && this._readPending) { this._readPending = false; this.render(); }
        return !!callId;
    };

    TuningView.prototype.requestPreview = function(operation, extra) {
        if (!this._source || this._busy || this._readPending || this._detaching
                || this._refreshRetryRequired || this._refreshRetryPending || this._needsReconcile) return false;
        operation = String(operation || this._operation);
        if (!isOperation(operation)) return false;
        this._operation = operation;
        var payload = {operation:operation, source:this._source};
        extra = extra || {};
        if (operation === 'enhance') payload.targetLevel = Math.floor(Number(extra.targetLevel || this._targetLevel));
        else if (operation === 'convert') payload.target = extra.target || this._target;
        else if (operation !== 'detach_all_mods') payload.candidateKey = String(extra.candidateKey || '');
        if (operation === 'replace_mod') {
            payload.replaceCandidateKey = String(extra.replaceCandidateKey || this._replaceCandidateKey || '');
        }
        if ((operation === 'convert' && !payload.target)
                || (operation !== 'enhance' && operation !== 'convert' && operation !== 'detach_all_mods'
                    && !payload.candidateKey)
                || (operation === 'replace_mod' && !payload.replaceCandidateKey)) return false;
        var self = this;
        this._preview = null;
        var intentKey = previewIntentKey(operation, payload);
        var quickCommit = extra.quickCommit === true && this._modConfirmationMode === 'fast'
            && (operation === 'install_mod' || operation === 'replace_mod' || operation === 'detach_mod');
        this._quickCommitIntent = quickCommit ? {
            intentKey:intentKey,
            operation:operation,
            candidateName:String(extra.candidateName || ''),
            replaceCandidateName:String(extra.replaceCandidateName || '')
        } : null;
        this._previewIntentKey = intentKey;
        this._previewPendingOperation = operation;
        this._status = '正在核算调制结果';
        this._readPending = true;
        this.render();
        var callId = this._mux.request('preview', payload, function(response) {
            self._readPending = false;
            self._previewPendingOperation = '';
            var isLatestIntent = self._previewIntentKey === intentKey;
            if (isLatestIntent && response && response.success === true) {
                self._preview = response;
                self._status = response.noOp ? '该操作不会改变装备' : '';
            } else if (isLatestIntent) {
                self._preview = null;
                self._status = errorMessage(response && response.error);
            } else {
                self._preview = null;
                self._status = '正在核算最新目标';
            }
            self._emit();
            self.render();
            if (isLatestIntent && self._preview && self._quickCommitIntent
                    && self._quickCommitIntent.intentKey === intentKey) {
                self._tryQuickCommit(intentKey);
            }
            self._drainEnhancementPreview();
        });
        if (!callId && this._readPending) {
            this._readPending = false; this._previewPendingOperation = ''; this.render();
        }
        return !!callId;
    };

    TuningView.prototype._finishInventoryWrite = function(operation, needsRefresh, callback) {
        if (!operation || this._inventoryWriteHandle !== operation) return false;
        var self = this;
        var completed = this._completeWrite(operation, !!needsRefresh, function(result) {
            if (self._inventoryWriteHandle !== operation) return;
            self._inventoryWriteHandle = null;
            self._busy = false;
            if (typeof callback === 'function') callback(result);
        });
        if (!completed && this._inventoryWriteHandle === operation) {
            this._inventoryWriteHandle = null;
            this._busy = false;
        }
        return !!completed;
    };

    TuningView.prototype.commit = function() {
        if (this._busy || this._readPending || this._detaching || this._needsReconcile
            || this._refreshRetryRequired || this._refreshRetryPending
            || !this._preview || !this._preview.tuningToken) return false;
        this._quickCommitIntent = null;
        var inventoryWrite = this._beginWrite('equipment_tuning.commit');
        if (!inventoryWrite) {
            this._toast('背包正在执行其他操作，请稍候。');
            return false;
        }
        this._inventoryWriteHandle = inventoryWrite;
        var self = this;
        var committedOperation = String(this._preview.operation || '');
        this._busy = true;
        this._status = '正在提交，期间不会重放';
        this.render();
        var commitResponseSettled = false;
        var callId = this._mux.request('commit', {expectedTuningToken:String(this._preview.tuningToken)}, function(response) {
            commitResponseSettled = true;
            if (self._inventoryWriteHandle !== inventoryWrite) return;
            var ambiguous = EquipmentTuningRuntime.isAmbiguous(response);
            var noOp = !!(response && response.success === true && response.noOp);
            if (response && response.success === true) {
                self._preview = null;
                if (committedOperation === 'replace_mod' || committedOperation === 'detach_mod') {
                    self._replaceCandidateKey = '';
                    self._replaceCandidateName = '';
                    self._operation = 'install_mod';
                }
                self._lastCommitCallId = '';
                self._status = noOp ? '无变化，未写入存档' : '提交成功，正在刷新背包';
                if (!self._finishInventoryWrite(inventoryWrite, !noOp, function(refreshResult) {
                    self._afterInventoryRefresh('', !noOp, refreshResult);
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
                self._status = '提交结果不明确，正在刷新并对账';
                if (!self._finishInventoryWrite(inventoryWrite, true, function(refreshResult) {
                    self._afterInventoryRefresh(barrierId, true, refreshResult);
                })) return;
            } else {
                self._lastCommitCallId = '';
                self._status = errorMessage(response && response.error);
                var staleLease = response && (response.error === 'stale_state' || response.error === 'stale_lease');
                if (!self._finishInventoryWrite(inventoryWrite, !!staleLease, function(refreshResult) {
                    if (staleLease) self._afterInventoryRefresh('', false, refreshResult);
                    else self.requestSnapshot();
                })) return;
            }
            self._emit();
            self.render();
        });
        if (!callId && this._inventoryWriteHandle === inventoryWrite) {
            this._needsReconcile = false;
            this._lastCommitCallId = '';
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

    TuningView.prototype.setModConfirmationMode = function(mode) {
        mode = mode === 'fast' ? 'fast' : 'safe';
        if (this._modConfirmationMode === mode) return true;
        this._modConfirmationMode = mode;
        this._quickCommitIntent = null;
        this._emit();
        this.render();
        return true;
    };

    TuningView.prototype._tryQuickCommit = function(intentKey) {
        var intent = this._quickCommitIntent;
        if (!intent || intent.intentKey !== intentKey || this._modConfirmationMode !== 'fast'
                || !this._preview || this._previewIntentKey !== intentKey || this._preview.noOp
                || !this._preview.tuningToken || this._busy || this._readPending || this._needsReconcile) return false;
        var eligible = quickCommitEligible(this._preview, intent);
        this._quickCommitIntent = null;
        if (!eligible) {
            this._status = '检测到连带变更，已停在预览';
            this._toast('快速模式检测到连带变更，已停在预览，请确认。');
            this._emit();
            this.render();
            return false;
        }
        return this.commit();
    };

    TuningView.prototype._afterInventoryRefresh = function(reconcileAfterCallId, changed, refreshResult) {
        reconcileAfterCallId = EquipmentTuningRuntime.safeToken(reconcileAfterCallId);
        if (!refreshResult || refreshResult.success !== true) {
            this._setConversionProjection(false);
            this._refreshRetryRequired = true;
            this._refreshRetryPending = false;
            this._refreshReconcileCallId = reconcileAfterCallId;
            this._refreshChanged = !!changed;
            this._needsReconcile = !!reconcileAfterCallId;
            this._snapshot = null;
            this._preview = null;
            this._status = '背包刷新失败；必须重试成功后才能使用新租约对账';
            this._emit();
            this.render();
            return false;
        }
        this._refreshRetryRequired = false;
        this._refreshRetryPending = false;
        this._refreshReconcileCallId = '';
        this._refreshChanged = false;
        this._setConversionProjection(false);
        var slot = this._source ? this._resolveSlot(this._source.containerId, this._source.slot) : null;
        if (!slot || !slot.occupied || !slot.item || slot.item.itemKind !== 'equipment') {
            this._source = null;
            this._sourceItem = null;
            this._snapshot = null;
            this._preview = null;
            this._needsReconcile = !!reconcileAfterCallId;
            this._status = changed ? '装备已移动，请重新选择' : '请选择左侧背包装备';
            this._emit();
            this.render();
            return false;
        }
        this._source = wireRef(slot);
        this._sourceItem = slot.item;
        this._target = null;
        this._targetItem = null;
        this._snapshot = null;
        this._preview = null;
        this._emit();
        this.requestSnapshot(reconcileAfterCallId);
        return true;
    };

    TuningView.prototype.retryInventoryRefresh = function() {
        if (!this._refreshRetryRequired || this._refreshRetryPending || this._busy
                || this._readPending || this._detaching) return false;
        var self = this;
        var reconcileAfterCallId = this._refreshReconcileCallId;
        var changed = this._refreshChanged;
        this._refreshRetryPending = true;
        this._status = '正在重试背包刷新';
        this._emit();
        this.render();
        var callbackCalled = false;
        var started = this._refreshInventory(function(result) {
            callbackCalled = true;
            self._refreshRetryPending = false;
            if (result && result.success === true) {
                self._afterInventoryRefresh(reconcileAfterCallId, changed, result);
                return;
            }
            self._refreshRetryRequired = true;
            self._status = '背包刷新仍未成功，请重试';
            self._emit();
            self.render();
        });
        if (!started && !callbackCalled) {
            this._refreshRetryPending = false;
            this._status = '当前无法重试背包刷新';
            this._emit();
            this.render();
        }
        return !!started;
    };

    TuningView.prototype.setOperation = function(operation) {
        if (!isOperationGroup(operation) || this._busy || this._readPending || this._detaching
                || this._refreshRetryRequired || this._refreshRetryPending) return false;
        this._closeInspector();
        if (operation !== 'enhance') {
            if (this._enhancePreviewTimer) clearTimeout(this._enhancePreviewTimer);
            this._enhancePreviewTimer = 0;
            this._queuedEnhanceLevel = null;
        }
        var wasConvert = this._operation === 'convert';
        this._operation = operation;
        this._preview = null;
        this._previewIntentKey = '';
        this._quickCommitIntent = null;
        if (operation !== 'install_mod') {
            this._replaceCandidateKey = '';
            this._replaceCandidateName = '';
        }
        if (operation !== 'convert') { this._target = null; this._targetItem = null; }
        if (wasConvert !== (operation === 'convert')) this._setConversionProjection(operation === 'convert');
        this.render({preserveScroll:false});
        if (operation === 'enhance' && this._snapshot) this.scheduleEnhancementPreview(this._targetLevel, 80);
        return true;
    };

    TuningView.prototype._selectReplacementCandidate = function(candidate) {
        if (!candidate || !candidate.candidateKey || this._busy || this._readPending
                || this._detaching || this._needsReconcile) return false;
        this._operation = 'install_mod';
        this._replaceCandidateKey = String(candidate.candidateKey);
        this._replaceCandidateName = String(candidate.itemName || '');
        this._preview = null;
        this._previewIntentKey = '';
        this._quickCommitIntent = null;
        this._status = '请选择要替换成的配件';
        this.render();
        return true;
    };

    TuningView.prototype._clearReplacementCandidate = function() {
        this._replaceCandidateKey = '';
        this._replaceCandidateName = '';
        if (this._operation === 'replace_mod') this._operation = 'install_mod';
        this._preview = null;
        this._previewIntentKey = '';
        this._quickCommitIntent = null;
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
        active = !!active && this._operation === 'convert' && !!this._sourceItem && !!this._source && !!this._snapshot;
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
            modConfirmationMode:this._modConfirmationMode, quickCommitPending:!!this._quickCommitIntent,
            lastCommitCallId:this._lastCommitCallId, mux:this._mux.debugState()};
    };

    TuningView.prototype._emit = function() { this._onStateChange(this.debugState()); };

    Renderer.install(TuningView, Model);

    return {create:create};
})();
