/** Right-hand equipment tuning view for the owned inventory workbench. */
var EquipmentTuningView = (function() {
    'use strict';

    var _instances = [];
    var _bridgeInstalled = false;

    function installBridge() {
        if (_bridgeInstalled || typeof Bridge === 'undefined' || !Bridge.on) return;
        _bridgeInstalled = true;
        Bridge.on('panel_resp', function(data) {
            for (var i = 0; i < _instances.length; i++) {
                if (_instances[i] && _instances[i]._mux.handleResponse(data)) return;
            }
        });
    }

    function create(options) {
        installBridge();
        var view = new TuningView(options || {});
        _instances.push(view);
        return view;
    }

    function TuningView(options) {
        var self = this;
        this.instanceKey = String(options.instanceKey || 'equipment-tuning');
        this.instancePolicy = 'singletonByBinding';
        this.viewKind = 'equipment-tuning';
        this.allowedSlots = ['R'];
        this._send = typeof options.send === 'function' ? options.send : function(message) { return Bridge.send(message); };
        this._beginWrite = options.beginWrite || function() { return false; };
        this._completeWrite = options.completeWrite || function(_, callback) { if (callback) callback({success:false}); return false; };
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
            this.render();
            return false;
        }
        this._panelInstanceId = panelInstanceId;
        this._viewSessionId = ('tuning.' + Date.now().toString(36) + '.'
            + Math.floor(Math.random() * 0x7fffffff).toString(36)).replace(/[^A-Za-z0-9._-]/g, '');
        var opened = this._mux.openSession(this._panelInstanceId, this._viewSessionId);
        this._status = opened ? '请选择左侧背包装备' : '无法建立调制会话';
        this._emit();
        this.render();
        return opened;
    };

    TuningView.prototype.closeSession = function() {
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
        this.render();
    };

    TuningView.prototype.destroy = function() {
        this.closeSession();
        if (this._modNavigator) { this._modNavigator.destroy(); this._modNavigator = null; }
        if (this._densityController && this._densityController.unregister) this._densityController.unregister(this);
        var index = _instances.indexOf(this);
        if (index >= 0) _instances.splice(index, 1);
        this._root = null;
    };

    TuningView.prototype.canClose = function() {
        return !this._busy && !this._readPending && !this._detaching && !this._needsReconcile
            && !this._refreshRetryRequired && !this._refreshRetryPending
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
        this.render();
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
        this._target = ref;
        this._targetItem = slot.item;
        this._preview = null;
        this.render();
        return this.requestPreview('convert', {target:ref});
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
            self._emit();
            self.render();
            if (self._snapshot && self._operation === 'enhance'
                    && Number(self._snapshot.enhance.currentLevel) < enhancementAvailableMax(self._snapshot)) {
                self.scheduleEnhancementPreview(self._targetLevel, 120);
            } else if (self._snapshot && self._operation === 'convert') {
                self._setConversionProjection(true);
            }
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

    TuningView.prototype.commit = function() {
        if (this._busy || this._readPending || this._detaching || this._needsReconcile
                || this._refreshRetryRequired || this._refreshRetryPending
                || !this._preview || !this._preview.tuningToken) return false;
        this._quickCommitIntent = null;
        if (!this._beginWrite('equipment_tuning.commit')) {
            this._toast('背包正在执行其他操作，请稍候。');
            return false;
        }
        var self = this;
        var committedOperation = String(this._preview.operation || '');
        this._busy = true;
        this._status = '正在提交，期间不会重放';
        this.render();
        var callId = this._mux.request('commit', {expectedTuningToken:String(this._preview.tuningToken)}, function(response) {
            self._busy = false;
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
                self._completeWrite(!noOp, function(refreshResult) {
                    self._afterInventoryRefresh('', !noOp, refreshResult);
                });
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
                self._completeWrite(true, function(refreshResult) {
                    self._afterInventoryRefresh(barrierId, true, refreshResult);
                });
            } else {
                self._lastCommitCallId = '';
                self._status = errorMessage(response && response.error);
                var staleLease = response && (response.error === 'stale_state' || response.error === 'stale_lease');
                self._completeWrite(!!staleLease, function(refreshResult) {
                    if (staleLease) self._afterInventoryRefresh('', false, refreshResult);
                    else self.requestSnapshot();
                });
            }
            self._emit();
            self.render();
        });
        if (!callId) {
            this._busy = false;
            this._needsReconcile = false;
            this._lastCommitCallId = '';
            this._status = errorMessage('not_sent');
            this._completeWrite(false, function() { self.requestSnapshot(); });
            this._emit();
            this.render();
        } else if (this._busy) {
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
        this.render();
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

    TuningView.prototype.render = function() {
        if (!this._root) return;
        if (this._modNavigator) { this._modNavigator.destroy(); this._modNavigator = null; }
        clear(this._root);
        var root = element('div', 'equipment-tuning-view');
        root.setAttribute('data-operation', this._operation === 'replace_mod' ? 'install_mod' : this._operation);
        root.setAttribute('data-reconcile', this._needsReconcile ? 'required' : 'clear');
        root.appendChild(this._renderHeader());
        root.appendChild(this._renderTabs());
        root.appendChild(this._renderBody());
        root.appendChild(this._renderPreview());
        this._root.appendChild(root);
    };

    TuningView.prototype._renderHeader = function() {
        var header = element('section', 'equipment-tuning-summary');
        if (!this._sourceItem) {
            var emptyMark = element('div', 'equipment-tuning-empty-mark'); emptyMark.textContent = '＋';
            var emptyCopy = element('div', 'equipment-tuning-summary-copy');
            emptyCopy.innerHTML = '<b>选择背包装备</b><small>仅背包内武器与防具可调制</small>';
            header.appendChild(emptyMark); header.appendChild(emptyCopy);
            return header;
        }
        var item = this._sourceItem;
        var icon = element('span', 'equipment-tuning-main-icon');
        icon.innerHTML = iconHtml(item.icon || item.name, 'kshop-icon');
        var copy = element('div', 'equipment-tuning-main-copy equipment-tuning-summary-copy');
        var equipment = this._snapshot && this._snapshot.equipment;
        var level = equipment ? Number(equipment.level || 0) : Number(item.enhancementLevel || 0);
        copy.innerHTML = '<b>' + escapeHtml(item.displayName || item.name) + '</b>'
            + '<span>强化 +' + level + (equipment && equipment.tier ? ' · ' + escapeHtml(equipment.tier) : '') + '</span>'
            + '<small>' + escapeHtml(this._status) + '</small>';
        header.appendChild(icon);
        header.appendChild(copy);
        var installedState = this._renderInstalledState(equipment);
        if (installedState.childNodes.length) header.appendChild(installedState);
        return header;
    };

    TuningView.prototype._renderInstalledState = function(equipment) {
        var state = element('div', 'equipment-tuning-installed-state');
        if (!equipment) return state;
        var self = this;
        var tierName = String(equipment.tier || '');
        var tierCandidate = candidateForTier(this._snapshot && this._snapshot.tierCandidates, tierName);
        if (tierName) {
            var tier = element('button', 'equipment-tuning-status-icon tier');
            tier.type = 'button';
            tier.setAttribute('aria-label', '当前进阶：' + tierName + '，点击查看进阶');
            tier.innerHTML = iconHtml(tierCandidate && tierCandidate.itemName || tierName, 'kshop-icon')
                + '<span class="equipment-tuning-status-mark" aria-hidden="true">阶</span>';
            tier.addEventListener('click', function() { self.setOperation('install_tier'); });
            if (tierCandidate) this._bindCandidateTooltip(tier, tierCandidate);
            state.appendChild(tier);
        }
        var candidates = this._snapshot && this._snapshot.modCandidates || [];
        var installed = equipment.mods instanceof Array ? equipment.mods : [];
        installed.forEach(function(name) {
            var candidate = candidateForItem(candidates, name);
            var button = element('button', 'equipment-tuning-status-icon mod grade-'
                + String(candidate && candidate.grade || 'unknown'));
            button.type = 'button';
            button.setAttribute('aria-label', '已安装配件：' + String(name) + '，点击选择替换');
            if (candidate && candidate.gradeColor) {
                button.style.setProperty('--equipment-mod-grade-color', String(candidate.gradeColor));
            }
            button.innerHTML = iconHtml(name, 'kshop-icon')
                + '<i class="equipment-tuning-status-role inventory-mod-glyph symbol-'
                + normalizeModSymbol(candidate && candidate.symbol) + '" aria-hidden="true"></i>';
            button.disabled = self._busy || self._readPending || self._needsReconcile
                || !candidate || !candidate.candidateKey;
            button.addEventListener('click', function() {
                if (candidate && candidate.candidateKey) {
                    self._selectReplacementCandidate(candidate);
                }
            });
            if (candidate) self._bindCandidateTooltip(button, candidate);
            state.appendChild(button);
        });
        return state;
    };

    TuningView.prototype._renderTabs = function() {
        var tabs = element('nav', 'equipment-tuning-tabs');
        var self = this;
        [['enhance','强化度'],['convert','交换'],['install_tier','进阶'],['install_mod','配件']].forEach(function(pair) {
            var button = element('button', 'equipment-tuning-tab' + (self._operation === pair[0]
                || (pair[0] === 'install_mod' && (self._operation === 'replace_mod'
                    || self._operation === 'detach_mod' || self._operation === 'detach_all_mods')) ? ' active' : ''));
            button.type = 'button'; button.textContent = pair[1]; button.disabled = self._busy || self._readPending;
            button.addEventListener('click', function() { self.setOperation(pair[0]); });
            tabs.appendChild(button);
        });
        return tabs;
    };

    TuningView.prototype._renderBody = function() {
        var body = element('section', 'equipment-tuning-body');
        if (this._refreshRetryRequired) {
            var refreshRetry = element('button', 'equipment-tuning-retry');
            refreshRetry.type = 'button';
            refreshRetry.textContent = this._refreshRetryPending ? '正在重试刷新…' : '重试背包刷新';
            refreshRetry.disabled = this._refreshRetryPending;
            var refreshSelf = this;
            refreshRetry.addEventListener('click', function() { refreshSelf.retryInventoryRefresh(); });
            body.appendChild(empty(this._status));
            body.appendChild(refreshRetry);
            return body;
        }
        if (!this._source) { body.appendChild(empty('从左侧选择一件装备后，Flash 会返回权威候选。')); return body; }
        if (!this._snapshot) {
            var retry = element('button', 'equipment-tuning-retry'); retry.type = 'button';
            retry.textContent = this._needsReconcile ? '重新对账' : '重试同步';
            var self = this; retry.addEventListener('click', function() { self.requestSnapshot(self._lastCommitCallId); });
            body.appendChild(empty(this._status)); body.appendChild(retry); return body;
        }
        if (this._operation === 'enhance' || this._operation === 'convert') {
            if (this._operation === 'enhance') this._renderEnhance(body);
            else this._renderConvert(body);
        }
        else if (this._operation === 'install_tier') this._renderCandidates(body, this._snapshot.tierCandidates || [], 'install_tier');
        else this._renderMods(body);
        return body;
    };

    TuningView.prototype._renderEnhance = function(body) {
        var enhance = this._snapshot.enhance || {};
        var current = Number(enhance.currentLevel || (this._snapshot.equipment && this._snapshot.equipment.level) || 0);
        var availableMax = enhancementAvailableMax(this._snapshot);
        var hardMax = enhancementHardMax(this._snapshot);
        var max = Math.min(availableMax, hardMax);
        var canEnhance = current < max;
        var target = canEnhance ? Math.max(current + 1, Math.min(max, Number(this._targetLevel || current + 1))) : current;
        var ownedStones = materialCount(this._snapshot.materials, '强化石');
        var reactor = element('section', 'equipment-tuning-enhance-reactor');
        var core = element('div', 'equipment-tuning-stone-core');
        var staticMotion = prefersReducedMotion()
            || !!(this._root && this._root.closest && this._root.closest('.item-grid-compact'));
        core.setAttribute('data-motion', staticMotion ? 'static' : 'animated');
        core.innerHTML = materialIconHtml('强化石', 'equipment-tuning-stone-icon', staticMotion);
        var reactorCopy = element('div', 'equipment-tuning-reactor-copy');
        reactorCopy.innerHTML = '<span>D.L.S. / CRYSTAL RESONANCE</span><b>强化石共振注能</b>';
        var reactorBalance = element('div', 'equipment-tuning-reactor-balance');
        var stoneDelta = this._preview && this._preview.operation === 'enhance'
            ? materialDeltaFor(this._preview.materials, '强化石') : null;
        reactorBalance.innerHTML = '<span>持有 <strong>' + exactQuantity(ownedStones) + '</strong></span>';
        if (stoneDelta) {
            reactorBalance.innerHTML += '<em class="equipment-tuning-reactor-spend">消耗 <b>'
                + exactQuantity(Math.max(0, -Number(stoneDelta.delta || 0))) + '</b> · 强化后剩余 <b>'
                + exactQuantity(stoneDelta.after) + '</b></em>';
        } else if (this._readPending && this._previewPendingOperation === 'enhance') {
            reactorBalance.innerHTML += '<em class="equipment-tuning-reactor-pending">正在计算消耗…</em>';
        }
        reactorCopy.appendChild(reactorBalance);
        var reactorReadout = element('div', 'equipment-tuning-reactor-readout');
        reactorReadout.innerHTML = canEnhance
            ? '<span>目标输出</span><b>+' + current + '<i>→</i>+' + target + '</b>'
            : '<span>' + (current >= hardMax ? '强化上限' : '当前状态') + '</span><b>+'
                + current + (current >= hardMax ? '<i>·</i>已封顶' : '') + '</b>';
        reactor.appendChild(core); reactor.appendChild(reactorCopy); reactor.appendChild(reactorReadout);
        body.appendChild(reactor);
        var panel = element('div', 'equipment-tuning-level-panel');
        if (!canEnhance) {
            panel.classList.add('capped');
            var cappedHeading = element('div', 'equipment-tuning-level-heading');
            cappedHeading.innerHTML = current >= hardMax
                ? '<span>永久强化上限</span><b>+' + hardMax + ' · 已封顶</b>'
                : '<span>当前阶段暂不能继续强化</span><b>当前 +' + current + '</b>';
            panel.appendChild(cappedHeading);
            var cappedCopy = element('p', 'equipment-tuning-cap-copy');
            cappedCopy.textContent = current >= hardMax
                ? '这件装备已经达到最高强化度。'
                : '继续推进剧情或提升铁匠能力后再来查看。';
            panel.appendChild(cappedCopy);
            body.appendChild(panel);
            return;
        }
        var heading = element('div', 'equipment-tuning-level-heading');
        heading.innerHTML = '<span>选择目标强化度</span><b>+' + target + '</b>';
        panel.appendChild(heading);
        var stepper = element('div', 'equipment-tuning-level-stepper');
        var self = this;
        var minus = actionButton('−', function() { self._chooseEnhancementLevel(target - 1); });
        minus.classList.add('equipment-tuning-level-step');
        var input = element('input', 'equipment-tuning-level-input');
        input.type = 'number'; input.min = String(Math.min(max, current + 1)); input.max = String(max); input.value = String(target);
        input.setAttribute('data-browser-native', '1');
        input.addEventListener('change', function() { self._chooseEnhancementLevel(input.value); });
        var plus = actionButton('+', function() { self._chooseEnhancementLevel(target + 1); });
        plus.classList.add('equipment-tuning-level-step');
        input.disabled = this._busy || (this._readPending && this._previewPendingOperation !== 'enhance') || current >= max;
        minus.disabled = input.disabled || target <= current + 1;
        plus.disabled = input.disabled || target >= max;
        stepper.appendChild(minus); stepper.appendChild(input); stepper.appendChild(plus);
        var slider = element('input', 'equipment-tuning-level-slider');
        slider.type = 'range'; slider.min = String(Math.min(max, current + 1)); slider.max = String(max); slider.step = '1'; slider.value = String(target);
        slider.setAttribute('data-browser-native', '1');
        slider.disabled = input.disabled;
        slider.addEventListener('change', function() { self._chooseEnhancementLevel(slider.value); });
        var controls = element('div', 'equipment-tuning-level-controls');
        controls.appendChild(stepper); controls.appendChild(slider);
        panel.appendChild(controls);
        var marks = element('div', 'equipment-tuning-level-marks');
        for (var level = current + 1; level <= max; level++) {
            (function(markLevel) {
                var mark = element('button', 'equipment-tuning-level-mark' + (markLevel === target ? ' active' : ''));
                mark.type = 'button'; mark.textContent = String(markLevel); mark.disabled = input.disabled;
                mark.addEventListener('click', function() { self._chooseEnhancementLevel(markLevel); });
                marks.appendChild(mark);
            })(level);
        }
        panel.appendChild(marks);
        var cap = actionButton('升至当前上限 +' + max, function() { self._chooseEnhancementLevel(max); });
        cap.classList.add('equipment-tuning-level-cap'); cap.disabled = input.disabled || target >= max; panel.appendChild(cap);
        body.appendChild(panel);
    };

    TuningView.prototype._chooseEnhancementLevel = function(level) {
        if (!this._snapshot || this._busy
                || (this._readPending && this._previewPendingOperation !== 'enhance') || this._needsReconcile) return false;
        var enhance = this._snapshot.enhance || {};
        var current = Number(enhance.currentLevel || 0), max = Math.min(
            enhancementAvailableMax(this._snapshot), enhancementHardMax(this._snapshot));
        level = Math.max(current + 1, Math.min(max, Math.floor(Number(level))));
        if (!isFinite(level) || current >= max) return false;
        this._targetLevel = level;
        this._preview = null;
        this.render();
        return this.scheduleEnhancementPreview(level, 160);
    };

    TuningView.prototype._renderConvert = function(body) {
        var pair = element('div', 'equipment-tuning-convert-pair');
        pair.appendChild(conversionEquipmentCard(this._sourceItem, '当前装备'));
        var arrow = element('div', 'equipment-tuning-convert-arrow');
        arrow.textContent = '↔'; arrow.setAttribute('aria-hidden', 'true'); pair.appendChild(arrow);
        pair.appendChild(conversionEquipmentCard(this._targetItem, this._targetItem ? '交换目标' : '等待选择', true));
        body.appendChild(pair);

        var heading = element('div', 'equipment-tuning-conversion-heading');
        heading.innerHTML = '<b>可交换装备</b><span>' + (this._conversionLoading ? '同步中'
            : this._conversionCandidates.length + ' 件') + '</span>';
        body.appendChild(heading);

        if (this._conversionLoading) {
            body.appendChild(empty('正在读取同类装备，不会改变左侧背包筛选。'));
        } else if (this._conversionError) {
            body.appendChild(empty(this._conversionError));
            var retry = actionButton('重新读取候选', this._setConversionProjection.bind(this, true));
            retry.classList.add('equipment-tuning-conversion-retry'); body.appendChild(retry);
        } else if (!this._conversionCandidates.length) {
            body.appendChild(empty('背包中没有强化度不同的其他同类装备。'));
        } else {
            var self = this;
            var grid = element('div', 'equipment-tuning-conversion-candidates');
            this._conversionCandidates.forEach(function(slot) {
                var item = slot.item || {};
                var selected = self._target && sameRef(self._target, wireRef(slot));
                var button = element('button', 'equipment-tuning-conversion-card' + (selected ? ' selected' : ''));
                button.type = 'button';
                button.setAttribute('data-physical-slot', String(slot.physicalSlot));
                button.setAttribute('aria-pressed', selected ? 'true' : 'false');
                button.setAttribute('aria-label', String(item.displayName || item.name || '装备')
                    + '，强化 +' + Number(item.enhancementLevel || 0));
                button.innerHTML = iconHtml(item.icon || item.name, 'kshop-icon')
                    + '<span class="equipment-tuning-conversion-copy"><b>'
                    + escapeHtml(item.displayName || item.name || '未知装备') + '</b><small>'
                    + escapeHtml(item.use || '同类装备') + ' · 强化 +' + Number(item.enhancementLevel || 0)
                    + '</small></span><i class="equipment-tuning-conversion-level">+'
                    + Number(item.enhancementLevel || 0) + '</i>';
                button.addEventListener('click', function() { self.selectConversionTarget(slot); });
                grid.appendChild(button);
            });
            body.appendChild(grid);
        }
        var hint = element('p', 'equipment-tuning-hint');
        hint.textContent = '这里仅列出背包中的同类装备，不会改变左侧的筛选与排序。'; body.appendChild(hint);
    };

    TuningView.prototype._renderCandidates = function(body, candidates, operation) {
        var list = element('div', 'equipment-tuning-candidates');
        var self = this;
        if (!candidates.length) { body.appendChild(empty('当前装备没有可用候选。')); return; }
        candidates.forEach(function(candidate) {
            var button = element('button', 'equipment-tuning-candidate' + (candidate.available ? ' available' : ' blocked'));
            button.type = 'button'; button.disabled = self._busy || self._readPending || self._needsReconcile;
            button.setAttribute('aria-disabled', candidate.available ? 'false' : 'true');
            button.setAttribute('data-grade', String(candidate.grade || 'unknown'));
            button.setAttribute('data-scope', String(candidate.scope || 'unknown'));
            button.setAttribute('data-role', String(candidate.role || 'utility'));
            button.setAttribute('aria-label', String(candidate.itemName || candidate.candidateKey) + '，持有 '
                + Number(candidate.owned || 0) + '，' + String(candidate.gradeLabel || candidate.tierName || '未分类')
                + (candidate.scopeLabel ? '，' + String(candidate.scopeLabel) : '')
                + (candidate.roleLabel ? '，' + String(candidate.roleLabel) : '')
                + (candidate.reason ? '，' + String(candidate.reason) : ''));
            if (candidate.gradeColor) button.style.setProperty('--equipment-mod-grade-color', String(candidate.gradeColor));
            var owned = Math.max(0, Math.floor(Number(candidate.owned) || 0));
            button.innerHTML = iconHtml(candidate.itemName || candidate.candidateKey, 'kshop-icon')
                + '<i class="equipment-tuning-role-glyph inventory-mod-glyph symbol-'
                + normalizeModSymbol(candidate.symbol) + '" aria-hidden="true"></i>'
                + (owned > 1 ? '<span class="inventory-slot-value quantity equipment-tuning-owned-count" aria-label="持有数量 '
                    + exactQuantity(owned) + '">'
                    + compactQuantity(owned) + '</span>' : '')
                + '<span><b>' + escapeHtml(candidate.itemName || candidate.candidateKey) + '</b><small>持有 '
                + owned + ' · ' + escapeHtml(candidate.gradeLabel || candidate.tierName || '未分类')
                + (candidate.scopeLabel ? ' · ' + escapeHtml(candidate.scopeLabel) : '')
                + (candidate.roleLabel ? ' · ' + escapeHtml(candidate.roleLabel) : '')
                + (candidate.reason ? ' · ' + escapeHtml(candidate.reason) : '') + '</small></span>';
            button.addEventListener('click', function() {
                if (candidate.available) self.requestPreview(operation, {
                    candidateKey:candidate.candidateKey,
                    candidateName:candidate.itemName,
                    replaceCandidateKey:self._replaceCandidateKey,
                    replaceCandidateName:self._replaceCandidateName,
                    quickCommit:self._modConfirmationMode === 'fast'
                });
            });
            self._bindCandidateTooltip(button, candidate);
            list.appendChild(button);
        });
        body.appendChild(list);
    };

    TuningView.prototype._bindCandidateTooltip = function(node, candidate) {
        if (!node || !candidate || !candidate.candidateKey || typeof PanelTooltip === 'undefined'
                || !PanelTooltip || typeof PanelTooltip.bindAsyncHover !== 'function') return;
        var self = this;
        PanelTooltip.bindAsyncHover(node, {
            cache:this._tooltipCache,
            key:'equipment-tuning:' + this._viewSessionId + ':'
                + String(this._source && this._source.expectedLease || '') + ':' + String(candidate.candidateKey),
            item:candidate,
            isSuppressed:function() { return self._busy || !self._mux.debugState().active; },
            renderBasic:function(value) {
                return '<div class="kshop-tt-header"><b>' + escapeHtml(value.itemName || value.candidateKey)
                    + '</b></div><div class="kshop-tt-loading">加载中…</div>';
            },
            renderRich:function(value, rich) {
                var rawHtml = rich && rich.html ? String(rich.html) : '';
                var textHtml = rawHtml ? '' : escapeHtml(rich && rich.text || '');
                if (!PanelTooltip.buildItemRichHtml) {
                    return rawHtml && PanelTooltip.convertAS2Html
                        ? PanelTooltip.convertAS2Html(rawHtml) : (rawHtml || textHtml);
                }
                var options = {
                    iconHtml:PanelTooltip.dynamicIconHtml ? PanelTooltip.dynamicIconHtml(value.itemName) : '',
                    iconUrl:PanelTooltip.staticIconUrl ? PanelTooltip.staticIconUrl(value.itemName) : '',
                    descHTML:rich && rich.descHTML ? String(rich.descHTML) : '',
                    rootClass:'equipment-tuning-tooltip',
                    layoutType:PanelTooltip.inferLayoutType
                        ? PanelTooltip.inferLayoutType(rich && (rich.itemType || rich.itemUse) || 'material') : ''
                };
                if (rich && rich.introHTML) options.introHTML = String(rich.introHTML);
                else if (rawHtml) options.introHTML = rawHtml;
                else options.introWebHTML = textHtml;
                return PanelTooltip.buildItemRichHtml(options);
            },
            fetch:function(value, callback) {
                self._mux.request('tooltip', {candidateKey:String(value.candidateKey)}, callback);
            }
        });
    };

    TuningView.prototype._renderMods = function(body) {
        var equipment = this._snapshot.equipment || {};
        var installed = equipment.mods || [];
        var candidates = this._snapshot.modCandidates || [];
        var replacementKey = this._replaceCandidateKey;
        var replacementMode = !!replacementKey;
        if (installed.length) {
            var heading = element('h3', 'equipment-tuning-section-title');
            heading.textContent = replacementMode ? '已安装 · 已选择待替换配件' : '已安装 · 点击选择替换';
            body.appendChild(heading);
            var installedList = element('div', 'equipment-tuning-installed');
            var self = this;
            installed.forEach(function(name) {
                var candidate = candidateForItem(candidates, name);
                var candidateKey = candidate && candidate.candidateKey;
                var selected = candidateKey && candidateKey === replacementKey;
                var entry = element('div', 'equipment-tuning-installed-entry');
                var button = element('button', 'equipment-tuning-installed-card equipment-tuning-detach grade-'
                    + String(candidate && candidate.grade || 'unknown') + (selected ? ' selected' : ''));
                button.type = 'button';
                button.setAttribute('aria-label', '已安装配件：' + String(name) + '，点击选择替换');
                button.setAttribute('aria-pressed', selected ? 'true' : 'false');
                if (candidate && candidate.gradeColor) {
                    button.style.setProperty('--equipment-mod-grade-color', String(candidate.gradeColor));
                }
                button.innerHTML = iconHtml(name, 'kshop-icon')
                    + '<span><b>' + escapeHtml(name) + '</b><small>'
                    + escapeHtml(candidate && candidate.gradeLabel || '已安装')
                    + (candidate && candidate.roleLabel ? ' · ' + escapeHtml(candidate.roleLabel) : '') + '</small></span>'
                    + '<i class="equipment-tuning-role-glyph inventory-mod-glyph symbol-'
                    + normalizeModSymbol(candidate && candidate.symbol) + '" aria-hidden="true"></i>';
                button.addEventListener('click', function() {
                    if (candidateKey) self._selectReplacementCandidate(candidate);
                });
                button.disabled = self._busy || self._readPending || self._needsReconcile || !candidateKey;
                if (candidate) self._bindCandidateTooltip(button, candidate);
                entry.appendChild(button);
                var detach = element('button', 'equipment-tuning-installed-quick-detach');
                detach.type = 'button';
                detach.textContent = '×';
                detach.setAttribute('aria-label', '卸下配件：' + String(name));
                detach.setAttribute('data-title', '卸下：' + String(name));
                detach.disabled = self._busy || self._readPending || self._needsReconcile || !candidateKey;
                detach.addEventListener('click', function(event) {
                    event.stopPropagation();
                    self.requestPreview('detach_mod', {
                        candidateKey:candidateKey,
                        candidateName:String(name),
                        quickCommit:self._modConfirmationMode === 'fast'
                    });
                });
                entry.appendChild(detach);
                installedList.appendChild(entry);
            });
            if (replacementMode) {
                var detachSelected = actionButton('仅卸下所选', function() {
                    self.requestPreview('detach_mod', {
                        candidateKey:replacementKey,
                        candidateName:self._replaceCandidateName,
                        quickCommit:self._modConfirmationMode === 'fast'
                    });
                });
                detachSelected.classList.add('equipment-tuning-detach-selected');
                detachSelected.setAttribute('aria-label','仅卸下所选配件');
                detachSelected.setAttribute('data-title','仅卸下所选配件');
                detachSelected.disabled = self._busy || self._readPending || self._needsReconcile;
                installedList.appendChild(detachSelected);
                var cancelReplacement = actionButton('取消替换', function() { self._clearReplacementCandidate(); });
                cancelReplacement.classList.add('equipment-tuning-replace-cancel');
                cancelReplacement.setAttribute('aria-label','取消替换');
                cancelReplacement.setAttribute('data-title','取消替换');
                cancelReplacement.disabled = self._busy || self._readPending || self._needsReconcile;
                installedList.appendChild(cancelReplacement);
            }
            var all = actionButton('卸下全部', function() { self.requestPreview('detach_all_mods'); });
            all.classList.add('danger', 'equipment-tuning-detach-all');
            all.setAttribute('aria-label','卸下全部配件');
            all.setAttribute('data-title','卸下全部配件');
            all.disabled = self._busy || self._readPending || self._needsReconcile; installedList.appendChild(all);
            body.appendChild(installedList);
        }
        var title = element('h3', 'equipment-tuning-section-title');
        title.textContent = replacementMode ? '选择替换配件' : '可安装配件';
        body.appendChild(title);
        var availableCandidates = candidates.filter(function(candidate) { return candidate.installed !== true; }).map(function(candidate) {
            if (!replacementMode) return candidate;
            var projected = {};
            for (var key in candidate) projected[key] = candidate[key];
            var replaceableFrom = candidate.replaceableFrom instanceof Array ? candidate.replaceableFrom : [];
            projected.available = Number(candidate.owned || 0) > 0 && replaceableFrom.indexOf(replacementKey) >= 0;
            projected.reason = projected.available ? ''
                : (Number(candidate.owned || 0) <= 0 ? 'material_missing' : '不能替换所选配件');
            return projected;
        });
        if (typeof ItemFilter !== 'undefined' && ItemFilter.FilterNavigator) {
            var filter = element('section', 'equipment-tuning-mod-filter');
            var breadcrumb = element('div', 'equipment-tuning-mod-breadcrumb');
            filter.appendChild(breadcrumb);
            var self = this;
            this._modNavigator = new ItemFilter.FilterNavigator({
                tree:buildModFilterTree(availableCandidates), path:this._modFilterPath,
                presentation:'drilldown', allLabel:'全部配件', ariaLabel:'配件分类筛选',
                visualStyle:'catalog', autoDescendSingle:false, breadcrumbHost:breadcrumb,
                onChange:function(path) { self._modFilterPath = path.slice(); self.render(); }
            });
            this._modNavigator.root.classList.add('equipment-tuning-mod-navigator');
            filter.appendChild(this._modNavigator.root); body.appendChild(filter);
            availableCandidates = availableCandidates.filter(function(candidate) {
                return modMatchesFilter(candidate, self._modFilterPath);
            });
        }
        var count = element('p', 'equipment-tuning-filter-count');
        count.textContent = '显示 ' + availableCandidates.length + ' / ' + candidates.filter(function(candidate) { return candidate.installed !== true; }).length;
        body.appendChild(count);
        this._renderCandidates(body, availableCandidates, replacementMode ? 'replace_mod' : 'install_mod');
    };

    TuningView.prototype._renderPreview = function() {
        var section = element('section', 'equipment-tuning-preview');
        if (!this._preview) {
            section.classList.add('is-empty');
            if (this._operation === 'enhance') section.classList.add('enhance-compact');
            section.appendChild(empty(this._needsReconcile ? '上次提交结果未知，必须完成权威对账。'
                : (this._operation === 'enhance'
                    ? (this._readPending ? '正在计算强化消耗…' : '选择目标强化度后确认。')
                    : '选择操作后在此确认材料与结果。')));
            return section;
        }
        var compactEnhance = this._preview.operation === 'enhance';
        if (compactEnhance) {
            section.classList.add('enhance-compact');
        } else {
            var heading = element('div', 'equipment-tuning-preview-heading');
            heading.innerHTML = '<b>' + operationLabel(this._preview.operation) + '</b><span>'
                + (this._preview.noOp ? '无需变更' : (this._preview.tuningToken ? '材料与结果已确认' : '条件不满足')) + '</span>';
            section.appendChild(heading);
            var equipmentDelta = renderEquipmentDelta(this._preview.before, this._preview.after);
            if (equipmentDelta) section.appendChild(equipmentDelta);
            var materials = this._preview.materials || [];
            if (materials.length) {
                var list = element('div', 'equipment-tuning-material-deltas');
                materials.forEach(function(material) {
                    var row = element('div', 'equipment-tuning-material-delta');
                    var materialName = String(material.itemName || '');
                    row.innerHTML = '<span class="equipment-tuning-material-label">'
                        + materialIconHtml(materialName, 'equipment-tuning-material-icon', true)
                        + '<em>' + escapeHtml(materialName) + '</em></span><b>'
                        + Number(material.before || 0) + (Number(material.delta || 0) >= 0 ? ' +' : ' ')
                        + Number(material.delta || 0) + ' → ' + Number(material.after || 0) + '</b>';
                    list.appendChild(row);
                });
                section.appendChild(list);
            }
            if (this._preview.removedMods && this._preview.removedMods.length) {
                var removed = element('p', 'equipment-tuning-removed');
                removed.textContent = '将返还：' + this._preview.removedMods.join('、'); section.appendChild(removed);
            }
        }
        var commit = actionButton(this._busy ? '提交中…' : commitLabel(this._preview), this.commit.bind(this));
        commit.classList.add('equipment-tuning-commit');
        commit.disabled = this._busy || this._readPending || this._needsReconcile || !this._preview.tuningToken;
        section.appendChild(commit);
        return section;
    };

    TuningView.prototype.debugState = function() {
        return {operation:this._operation, source:this._source, target:this._target, busy:this._busy, readPending:this._readPending,
            detaching:this._detaching, refreshRetryRequired:this._refreshRetryRequired,
            refreshRetryPending:this._refreshRetryPending, refreshReconcileCallId:this._refreshReconcileCallId,
            needsReconcile:this._needsReconcile, hasSnapshot:!!this._snapshot, hasPreview:!!this._preview,
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

    function wireRef(slot) {
        return {containerId:'背包', slot:Number(slot.physicalSlot != null ? slot.physicalSlot : slot.slot),
            expectedLease:String(slot.slotLease != null ? slot.slotLease : slot.expectedLease)};
    }
    function sameRef(a, b) { return a && b && a.containerId === b.containerId && Number(a.slot) === Number(b.slot); }
    function refKey(ref) {
        return ref ? String(ref.containerId || '') + ':' + Number(ref.slot) + ':' + String(ref.expectedLease || '') : '';
    }

    function quickCommitEligible(preview, intent) {
        var materials = preview && preview.materials instanceof Array ? preview.materials : [];
        var removed = preview && preview.removedMods instanceof Array ? preview.removedMods : [];
        if (intent.operation === 'install_mod') {
            return removed.length === 0 && materials.length === 1
                && materialDeltaEquals(materials[0], intent.candidateName, -1);
        }
        if (intent.operation === 'replace_mod') {
            return removed.length === 1 && removed[0] === intent.replaceCandidateName
                && materials.length === 2
                && hasMaterialDelta(materials, intent.candidateName, -1)
                && hasMaterialDelta(materials, intent.replaceCandidateName, 1);
        }
        if (intent.operation === 'detach_mod') {
            return removed.length === 1 && removed[0] === intent.candidateName
                && materials.length === 1 && materialDeltaEquals(materials[0], intent.candidateName, 1);
        }
        return false;
    }

    function hasMaterialDelta(materials, itemName, delta) {
        for (var i = 0; i < materials.length; i++) {
            if (materialDeltaEquals(materials[i], itemName, delta)) return true;
        }
        return false;
    }

    function materialDeltaEquals(row, itemName, delta) {
        return !!row && String(row.itemName || '') === String(itemName || '')
            && Number(row.delta) === Number(delta);
    }
    function normalizeConversionCandidates(candidates, source, sourceItem) {
        var out = [], seen = {}, sourceUse = String(sourceItem && sourceItem.use || '');
        var sourceLevel = Number(sourceItem && sourceItem.enhancementLevel);
        for (var i = 0; i < candidates.length; i++) {
            var slot = candidates[i], item = slot && slot.item, ref = slot && wireRef(slot);
            if (!slot || !slot.occupied || !item || item.itemKind !== 'equipment' || !ref
                    || sameRef(source, ref) || String(item.use || '') !== sourceUse) continue;
            var targetLevel = Number(item.enhancementLevel);
            if (isFinite(sourceLevel) && isFinite(targetLevel) && sourceLevel === targetLevel) continue;
            var key = refKey(ref);
            if (seen[key]) continue;
            seen[key] = true; out.push(slot);
        }
        return out;
    }
    function conversionEquipmentCard(item, label, emptyTarget) {
        var card = element('div', 'equipment-tuning-convert-item' + (!item ? ' empty' : ''));
        if (!item) {
            card.innerHTML = '<div class="equipment-tuning-empty-mark">?</div><span><small>'
                + escapeHtml(label || '等待选择') + '</small><b>'
                + (emptyTarget ? '从下方选择目标' : '未选择装备') + '</b></span>';
            return card;
        }
        card.innerHTML = iconHtml(item.icon || item.name, 'kshop-icon')
            + '<span><small>' + escapeHtml(label || '装备') + '</small><b>'
            + escapeHtml(item.displayName || item.name || '未知装备') + '</b><em>强化 +'
            + Number(item.enhancementLevel || 0) + '</em></span>';
        return card;
    }
    function previewIntentKey(operation, payload) {
        payload = payload || {};
        if (operation === 'enhance') return 'enhance|' + Math.floor(Number(payload.targetLevel || 0));
        if (operation === 'convert') {
            var target = payload.target || {};
            return 'convert|' + String(target.containerId || '') + '|' + Number(target.slot) + '|'
                + String(target.expectedLease || '');
        }
        return String(operation || '') + '|' + String(payload.candidateKey || '')
            + '|' + String(payload.replaceCandidateKey || '');
    }
    function isOperation(value) { return /^(enhance|convert|install_tier|install_mod|replace_mod|detach_mod|detach_all_mods)$/.test(value); }
    function isOperationGroup(value) { return /^(enhance|convert|install_tier|install_mod)$/.test(value); }
    function nextEnhancementLevel(snapshot) {
        var enhance = snapshot && snapshot.enhance || {};
        var current = Number(enhance.currentLevel || snapshot.equipment && snapshot.equipment.level || 0);
        var max = Math.min(enhancementAvailableMax(snapshot), enhancementHardMax(snapshot));
        return Math.min(max, current + 1);
    }
    function operationLabel(value) {
        var labels = {enhance:'强化预览',convert:'强化度转换',install_tier:'装备进阶',install_mod:'安装配件',
            replace_mod:'替换配件',detach_mod:'卸下配件',detach_all_mods:'卸下全部配件'};
        return labels[value] || '调制预览';
    }
    function errorMessage(error) {
        var labels = {invalid_payload:'请求字段无效。',stale_state:'装备或材料状态已变化，请重新选择。',
            material_missing:'材料不足。',insufficient_material:'材料不足。',target_invalid:'转换目标无效。',
            invalid_target:'转换目标无效。',same_slot:'不能选择同一件装备。',
            type_mismatch:'只能在相同类型装备之间转换。',different_use:'只能在相同类型装备之间转换。',
            level_cap:'已达到当前强化上限。',tier_locked:'进阶顺序尚未满足。',invalid_transition:'进阶顺序尚未满足。',
            mod_unavailable:'该配件当前不可安装。',mod_not_installed:'目标配件已不在装备上。',busy:'Flash 正在处理另一项调制。',
            invalid_equipment:'该物品不能调制。',invalid_mods:'装备的配件数据无效。',unknown_candidate:'候选项已失效，请刷新。',
            token_invalid:'调制预览已失效，请重新预览。',token_expired:'调制预览已过期，请重新预览。',
            view_session_expired:'调制会话已失效，请重新进入。',commit_failed:'调制提交失败，未写入存档。',
            timeout:'调制响应超时。',client_timeout:'调制响应超时。',disconnected:'连接已断开。',not_sent:'请求未送达 Flash。',
            malformed_response:'Flash 回包不完整。',reconcile_required:'上次提交结果需要重新对账。',
            inventory_projection_failed:'同类装备读取失败，请重试。',
            inventory_projection_unavailable:'当前无法读取同类装备。'};
        return labels[error] || '调制操作失败，请重试。';
    }
    function element(tag, className) { var node = document.createElement(tag); if (className) node.className = className; return node; }
    function clear(node) { while (node && node.firstChild) node.removeChild(node.firstChild); }
    function empty(text) { var node = element('div', 'equipment-tuning-empty'); node.textContent = text || ''; return node; }
    function actionButton(text, handler) { var button = element('button', 'equipment-tuning-action'); button.type = 'button'; button.textContent = text; if (handler) button.addEventListener('click', handler); return button; }
    function iconHtml(name, cls) {
        var html = typeof Icons !== 'undefined' && Icons.html ? Icons.html(name, cls || 'kshop-icon', ' onerror="this.style.display=\'none\'"') : '';
        return html || '<span class="kshop-icon-placeholder"></span>';
    }
    function materialIconHtml(name, cls, staticOnly) {
        if (staticOnly && typeof Icons !== 'undefined' && Icons.resolveStatic) {
            var url = Icons.resolveStatic(name);
            if (url) return '<img class="' + escapeHtml(cls || 'kshop-icon') + '" src="'
                + escapeHtml(url) + '" data-icon-name="' + escapeHtml(name)
                + '" data-icon-static="1" alt="">';
        }
        return iconHtml(name, cls);
    }
    function prefersReducedMotion() {
        return typeof window !== 'undefined' && window.matchMedia
            && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    }
    function escapeHtml(value) { return String(value == null ? '' : value).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
    function candidateForItem(candidates, itemName) {
        candidates = candidates || [];
        for (var i = 0; i < candidates.length; i++) {
            if (String(candidates[i] && candidates[i].itemName || '') === String(itemName || '')) {
                return candidates[i];
            }
        }
        return null;
    }
    function candidateForTier(candidates, tierName) {
        candidates = candidates || [];
        for (var i = 0; i < candidates.length; i++) {
            if (String(candidates[i] && candidates[i].tierName || '') === String(tierName || '')) {
                return candidates[i];
            }
        }
        return null;
    }
    function exactQuantity(value) {
        if (typeof InventoryUI !== 'undefined' && InventoryUI.exactQuantity) return InventoryUI.exactQuantity(value);
        return String(Math.max(0, Math.floor(Number(value) || 0))).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }
    function materialCount(materials, itemName) {
        if (materials instanceof Array) {
            for (var i = 0; i < materials.length; i++) {
                if (String(materials[i] && materials[i].itemName || '') === String(itemName || '')) {
                    return Math.max(0, Math.floor(Number(materials[i].count) || 0));
                }
            }
            return 0;
        }
        return Math.max(0, Math.floor(Number(materials && materials[itemName]) || 0));
    }
    function materialDeltaFor(materials, itemName) {
        materials = materials || [];
        for (var i = 0; i < materials.length; i++) {
            if (String(materials[i] && materials[i].itemName || '') === String(itemName || '')) {
                return materials[i];
            }
        }
        return null;
    }
    function enhancementAvailableMax(snapshot) {
        var enhance = snapshot && snapshot.enhance || {};
        var current = Number(enhance.currentLevel || snapshot && snapshot.equipment && snapshot.equipment.level || 0);
        return Number(enhance.availableMaxLevel != null ? enhance.availableMaxLevel
            : (enhance.maxLevel != null ? enhance.maxLevel : current));
    }
    function enhancementHardMax(snapshot) {
        var enhance = snapshot && snapshot.enhance || {};
        var equipment = snapshot && snapshot.equipment || {};
        var available = enhancementAvailableMax(snapshot);
        return Number(enhance.hardMaxLevel != null ? enhance.hardMaxLevel
            : (equipment.hardMaxLevel != null ? equipment.hardMaxLevel : available));
    }
    function candidateInstalled(candidates, candidateKey) {
        candidates = candidates || [];
        for (var i = 0; i < candidates.length; i++) {
            if (String(candidates[i] && candidates[i].candidateKey || '') === String(candidateKey || '')) {
                return candidates[i].installed === true;
            }
        }
        return false;
    }
    function compactQuantity(value) {
        if (typeof InventoryUI !== 'undefined' && InventoryUI.compactQuantity) return InventoryUI.compactQuantity(value);
        var quantity = Math.max(0, Math.floor(Number(value) || 0));
        if (quantity < 10000) return String(quantity);
        var unitValue = quantity >= 100000000 ? 100000000 : 10000;
        var scaled = quantity / unitValue;
        var compact = scaled < 10 ? Math.floor(scaled * 10) / 10 : Math.floor(scaled);
        return String(compact).replace(/\.0$/, '') + (unitValue === 100000000 ? '亿' : '万');
    }
    function modStatus(candidate) {
        if (candidate && candidate.available === true) return {id:'available', label:'可安装', order:0};
        var reason = String(candidate && candidate.reason || '');
        if (reason === 'material_missing' || reason === '材料不足') return {id:'material_missing', label:'材料不足', order:1};
        return {id:'blocked', label:'条件不符', order:2};
    }
    function normalizeModSymbol(value) {
        value = String(value || 'diamond-outline');
        return /^(triangle|square|circle|diamond|star)-(solid|outline)$/.test(value)
            ? value : 'diamond-outline';
    }
    function modSegment(candidate, field, labelField, fallbackId, fallbackLabel, order) {
        var id = String(candidate && candidate[field] || fallbackId);
        return {id:id, label:String(candidate && candidate[labelField] || fallbackLabel), order:Number(order) || 0};
    }
    function buildModFilterTree(candidates) {
        candidates = candidates || [];
        var gradeOrder = {low:0, medium:1, high:2, special:3, unknown:9};
        return ItemFilter.branchTree([
            {id:'grade', label:'档级', tree:ItemFilter.build(candidates, function(candidate) {
                var value = modSegment(candidate, 'grade', 'gradeLabel', 'unknown', '未知档级', gradeOrder[String(candidate.grade || 'unknown')]);
                return [value];
            })},
            {id:'scope', label:'用途', tree:ItemFilter.build(candidates, function(candidate) {
                return [modSegment(candidate, 'scope', 'scopeLabel', 'unknown', '未分类', 0)];
            })},
            {id:'role', label:'定位', tree:ItemFilter.build(candidates, function(candidate) {
                return [modSegment(candidate, 'role', 'roleLabel', 'utility', '结构与功能', 0)];
            })},
            {id:'status', label:'状态', tree:ItemFilter.build(candidates, function(candidate) { return [modStatus(candidate)]; })}
        ], candidates.length);
    }
    function modMatchesFilter(candidate, path) {
        path = path || [];
        if (path.length < 2) return true;
        var value = String(path[1]);
        if (path[0] === 'grade') return String(candidate.grade || 'unknown') === value;
        if (path[0] === 'scope') return String(candidate.scope || 'unknown') === value;
        if (path[0] === 'role') return String(candidate.role || 'utility') === value;
        if (path[0] === 'status') return modStatus(candidate).id === value;
        return true;
    }
    function commitLabel(preview) {
        preview = preview || {};
        if (preview.operation !== 'enhance') {
            var labels = {convert:'互换强化度', install_tier:'确认进阶', install_mod:'安装配件',
                replace_mod:'替换配件', detach_mod:'卸下配件', detach_all_mods:'卸下全部配件'};
            return labels[preview.operation] || '确认调制';
        }
        var after = preview.after && preview.after.source && preview.after.source.equipment;
        var target = after ? Number(after.level || 0) : 0;
        var cost = 0, materials = preview.materials || [];
        for (var i = 0; i < materials.length; i++) {
            if (String(materials[i].itemName || '') === '强化石') cost += Math.max(0, -Number(materials[i].delta || 0));
        }
        return '强化至 +' + target + (cost > 0 ? ' · ' + cost + ' 强化石' : '');
    }
    function renderEquipmentDelta(before, after) {
        before = before || {}; after = after || {};
        var keys = ['source','target'];
        var list = element('div', 'equipment-tuning-equipment-deltas');
        var count = 0;
        for (var i = 0; i < keys.length; i++) {
            var left = before[keys[i]] && before[keys[i]].equipment;
            var right = after[keys[i]] && after[keys[i]].equipment;
            if (!left || !right) continue;
            var diff = equipmentDiff(left, right);
            if (!diff) continue;
            var row = element('div', 'equipment-tuning-equipment-delta');
            var name = right.displayName || right.name || left.displayName || left.name || (keys[i] === 'source' ? '主装备' : '目标装备');
            row.innerHTML = '<b>' + escapeHtml(name) + '</b><span>' + escapeHtml(diff) + '</span>';
            list.appendChild(row); count++;
        }
        return count ? list : null;
    }
    function equipmentDiff(left, right) {
        var parts = [];
        var levelBefore = Number(left.level || 0), levelAfter = Number(right.level || 0);
        if (levelBefore !== levelAfter) parts.push('+' + levelBefore + ' → +' + levelAfter);
        if (left.tier !== right.tier) parts.push((left.tier || '—') + ' → ' + (right.tier || '—'));
        var beforeMods = left.mods || [];
        var afterMods = right.mods || [];
        var removed = beforeMods.filter(function(m) { return afterMods.indexOf(m) < 0; });
        var added = afterMods.filter(function(m) { return beforeMods.indexOf(m) < 0; });
        if (removed.length) parts.push('卸下 ' + removed.join('、'));
        if (added.length) parts.push('安装 ' + added.join('、'));
        return parts.join(' · ');
    }

    return {create:create};
})();
