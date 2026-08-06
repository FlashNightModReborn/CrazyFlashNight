/** Inventory-write, retry, and immediate intent lifecycle for Equipment Tuning. */
var EquipmentTuningWriteLifecycle = (function() {
    'use strict';

    function install(TuningView, Model) {
        if (!TuningView || !TuningView.prototype || !Model) {
            throw new Error(
                'EquipmentTuningWriteLifecycle requires a tuning view and model.'
            );
        }
        var refKey = Model.refKey;
        var normalizeTuningSource = Model.normalizeTuningSource;
        var quickCommitEligible = Model.quickCommitEligible;
        var nextEnhancementLevel = Model.nextEnhancementLevel;
        var enhancementAvailableMax = Model.enhancementAvailableMax;

        TuningView.prototype._createModIntent = function(
            operation,
            payload,
            extra,
            intentKey
        ) {
            if (operation !== 'install_mod' && operation !== 'replace_mod'
                    && operation !== 'detach_mod') return null;
            return {
                viewSessionId:this._viewSessionId,
                sourceFence:refKey(this._source),
                intentKey:intentKey,
                operation:operation,
                candidateKey:String(payload.candidateKey || ''),
                candidateName:String(extra.candidateName || ''),
                replaceCandidateKey:String(payload.replaceCandidateKey || ''),
                replaceCandidateName:String(extra.replaceCandidateName || ''),
                phase:'preview_pending'
            };
        };

        TuningView.prototype._setModIntentPhase = function(phase) {
            if (!this._modIntent) return false;
            this._modIntent.phase = String(phase || '');
            return true;
        };

        TuningView.prototype._modIntentStatus = function(phase) {
            var intent = this._modIntent;
            if (!intent) return '';
            var action = intent.operation === 'detach_mod'
                ? '卸下「' + (intent.candidateName || '当前配件') + '」'
                : intent.operation === 'replace_mod'
                    ? '用「' + (intent.candidateName || '新配件') + '」替换「'
                        + (intent.replaceCandidateName || '当前配件') + '」'
                    : '安装「' + (intent.candidateName || '所选配件') + '」';
            if (phase === 'preview_pending') return '正在校验：' + action;
            if (phase === 'write_pending') return '权威预览已确认，正在' + action;
            if (phase === 'committed_syncing') {
                return '已写入，正在同步：' + action;
            }
            if (phase === 'uncertain') return '提交结果待对账：' + action;
            return '';
        };

        TuningView.prototype._finishInventoryWrite = function(
            operation,
            needsRefresh,
            callback
        ) {
            if (!operation || this._inventoryWriteHandle !== operation) {
                return false;
            }
            var self = this;
            var completed = this._completeWrite(
                operation,
                !!needsRefresh,
                function(result) {
                    if (self._inventoryWriteHandle !== operation) return;
                    self._inventoryWriteHandle = null;
                    self._busy = false;
                    if (typeof callback === 'function') callback(result);
                }
            );
            if (!completed && this._inventoryWriteHandle === operation) {
                this._inventoryWriteHandle = null;
                this._busy = false;
            }
            return !!completed;
        };

        TuningView.prototype._tryQuickCommit = function(intentKey) {
            var intent = this._quickCommitIntent;
            if (!intent || intent.intentKey !== intentKey
                    || this._modConfirmationMode !== 'fast'
                    || !this._preview
                    || this._previewIntentKey !== intentKey) return false;
            if (this._preview.noOp || !this._preview.tuningToken || this._busy
                    || this._readPending || this._needsReconcile) {
                this._quickCommitIntent = null;
                this._setModIntentPhase('preview_ready');
                return false;
            }
            var eligible = quickCommitEligible(this._preview, intent);
            this._quickCommitIntent = null;
            if (!eligible) {
                this._setModIntentPhase('preview_ready');
                var removed = this._preview.removedMods instanceof Array
                    ? this._preview.removedMods.length : 0;
                var expectedRemoved =
                    intent.operation === 'install_mod' ? 0 : 1;
                var collateral = Math.max(0, removed - expectedRemoved);
                var impact = collateral > 0
                    ? '将额外卸下 ' + collateral + ' 个依赖插件'
                    : '检测到额外联动';
                this._status = impact + '，已停在预览';
                this._toast(impact + '；请确认后再提交。');
                this._emit();
                this.render({previewOnly:true, focusNext:true});
                return true;
            }
            this._setModIntentPhase('write_pending');
            this._status = this._modIntentStatus('write_pending');
            if (this.commit()) return true;
            this._setModIntentPhase('preview_ready');
            this._emit();
            this.render({previewOnly:true, focusNext:true});
            return true;
        };

        TuningView.prototype._afterInventoryRefresh = function(
            reconcileAfterCallId,
            changed,
            refreshResult,
            authoritativeSnapshot
        ) {
            var self = this;
            function recordRefresh(success) {
                var commitDiagnostic = self._commitDiagnostic || {};
                self._recordDiagnostic('inventory_refresh_settled', {
                    operation:commitDiagnostic.operation || self._operation,
                    webCallId:commitDiagnostic.webCallId,
                    candidateKey:commitDiagnostic.candidateKey,
                    intentKey:commitDiagnostic.intentKey,
                    success:success === true,
                    currentLeasePresent:!!(self._source
                        && self._source.sourceKind === 'inventory'
                        && self._source.expectedLease),
                    needsReconcile:self._needsReconcile === true
                });
                if (success === true && self._needsReconcile !== true) {
                    self._commitDiagnostic = null;
                }
            }
            reconcileAfterCallId =
                EquipmentTuningRuntime.safeToken(reconcileAfterCallId);
            if (!refreshResult || refreshResult.success !== true) {
                this._setConversionProjection(false);
                this._refreshRetryRequired = true;
                this._refreshRetryPending = false;
                this._refreshReconcileCallId = reconcileAfterCallId;
                this._refreshChanged = !!changed;
                this._needsReconcile = !!reconcileAfterCallId;
                this._snapshot = null;
                this._preview = null;
                this._modIntent = null;
                this._status =
                    '背包刷新失败；必须重试成功后才能使用新租约对账';
                recordRefresh(false);
                this._emit();
                this.render();
                return false;
            }
            this._refreshRetryRequired = false;
            this._refreshRetryPending = false;
            this._refreshReconcileCallId = '';
            this._refreshChanged = false;
            this._setConversionProjection(false);
            this._resetInfoPanel();
            var slot = this._source
                ? this._resolveSlot(
                    this._source.containerId,
                    this._source.slot
                )
                : null;
            if (!slot || !slot.occupied || !slot.item
                    || slot.item.itemKind !== 'equipment') {
                this._source = null;
                this._sourceItem = null;
                this._snapshot = null;
                this._preview = null;
                this._modIntent = null;
                this._needsReconcile = !!reconcileAfterCallId;
                this._status = changed
                    ? '装备已移动，请重新选择'
                    : '请选择左侧背包装备';
                recordRefresh(true);
                this._emit();
                this.render();
                return false;
            }
            this._source = normalizeTuningSource({
                sourceKind:'inventory',
                containerId:'背包',
                slot:Number(
                    slot.physicalSlot != null
                        ? slot.physicalSlot
                        : slot.slot
                ),
                expectedLease:String(
                    slot.slotLease != null
                        ? slot.slotLease
                        : slot.expectedLease
                )
            });
            if (!this._source) {
                this._sourceItem = null;
                this._snapshot = null;
                this._preview = null;
                this._status = '背包装备租约无效，请重新选择';
                recordRefresh(true);
                this._emit();
                this.render();
                return false;
            }
            this._sourceItem = slot.item;
            this._target = null;
            this._targetItem = null;
            var authoritativeSource = normalizeTuningSource(
                authoritativeSnapshot && authoritativeSnapshot.source
            );
            if (authoritativeSource
                    && authoritativeSource.sourceKind === 'inventory'
                    && refKey(authoritativeSource) === refKey(this._source)) {
                this._snapshot = authoritativeSnapshot;
                this._preview = null;
                this._needsReconcile = false;
                this._modIntent = null;
                this._targetLevel =
                    nextEnhancementLevel(authoritativeSnapshot);
                this._status = '装备状态已同步';
                recordRefresh(true);
                this._emit();
                this.render();
                if (this._operation === 'enhance'
                        && Number(
                            authoritativeSnapshot.enhance.currentLevel
                        ) < enhancementAvailableMax(
                            authoritativeSnapshot
                        )) {
                    this.scheduleEnhancementPreview(
                        this._targetLevel,
                        120
                    );
                }
                if (this._operation === 'convert') {
                    this._setConversionProjection(true);
                }
                return true;
            }
            this._snapshot = null;
            this._preview = null;
            recordRefresh(true);
            this._emit();
            this.requestSnapshot(reconcileAfterCallId);
            return true;
        };

        TuningView.prototype.retryInventoryRefresh = function() {
            if (!this._refreshRetryRequired
                    || !this._allowInteraction('retry')) return false;
            if (this._source && this._source.sourceKind === 'loadout') {
                return this._beginLoadoutRefresh();
            }
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
                    self._afterInventoryRefresh(
                        reconcileAfterCallId,
                        changed,
                        result
                    );
                    return;
                }
                self._refreshRetryRequired = true;
                self._status = '背包刷新仍未成功，请重试';
                self._recordDiagnostic('inventory_refresh_settled', {
                    operation:self._operation,
                    success:false,
                    currentLeasePresent:!!(self._source
                        && self._source.sourceKind === 'inventory'
                        && self._source.expectedLease),
                    needsReconcile:self._needsReconcile === true
                });
                self._emit();
                self.render();
            });
            if (!started && !callbackCalled) {
                this._refreshRetryPending = false;
                this._status = '当前无法重试背包刷新';
                this._recordDiagnostic('inventory_refresh_settled', {
                    operation:this._operation,
                    success:false,
                    currentLeasePresent:!!(this._source
                        && this._source.sourceKind === 'inventory'
                        && this._source.expectedLease),
                    needsReconcile:this._needsReconcile === true
                });
                this._emit();
                this.render();
            }
            return !!started;
        };

        return TuningView;
    }

    return {install:install};
})();
