/** Loadout commit, refresh, and reconciliation lifecycle for Equipment Tuning. */
var EquipmentTuningLoadoutLifecycle = (function() {
    'use strict';

    function install(TuningView, Model) {
        if (!TuningView || !TuningView.prototype || !Model
                || typeof Model.tuningSourceSupports !== 'function'
                || typeof Model.normalizeTuningSource !== 'function'
                || typeof Model.sameLoadoutIdentity !== 'function'
                || typeof Model.validLoadoutCommit !== 'function'
                || typeof Model.errorMessage !== 'function') {
            throw new Error(
                'EquipmentTuningLoadoutLifecycle requires a tuning view and model.'
            );
        }
        var tuningSourceSupports = Model.tuningSourceSupports;
        var normalizeTuningSource = Model.normalizeTuningSource;
        var errorMessage = Model.errorMessage;
        var nextEnhancementLevel = Model.nextEnhancementLevel;

        TuningView.prototype._commitLoadout = function() {
            if (!this._source || this._source.sourceKind !== 'loadout'
                    || !tuningSourceSupports(this._source, this._preview.operation)) return false;
            this._quickCommitIntent = null;
            this._setModIntentPhase('write_pending');
            var write = this._beginWrite('equipment_tuning.commit.loadout');
            if (!write) {
                this._setModIntentPhase('preview_ready');
                this._toast('角色构筑正在执行其他操作，请稍候。');
                return false;
            }
            this._inventoryWriteHandle = write;
            var self = this;
            var operation = String(this._preview.operation || '');
            this._busy = true;
            this._status = this._modIntent
                ? this._modIntentStatus('write_pending')
                : '正在提交当前装备调制，期间不会重放';
            this._emit();
            this.render({previewOnly:true});
            var settled = false;
            var callId = this._mux.request(
                'commit',
                {expectedTuningToken:String(this._preview.tuningToken)},
                function(response, entry) {
                    settled = true;
                    if (self._inventoryWriteHandle !== write) return;
                    var exactSuccess = Model.validLoadoutCommit(response, operation);
                    var ambiguous = response && response.success === true
                        || EquipmentTuningRuntime.isAmbiguous(response);
                    self._recordDiagnostic('commit_adopted', {
                        operation:operation,
                        webCallId:entry && entry.callId,
                        success:exactSuccess,
                        tokenPresent:true,
                        transactionIdPresent:!!(response && response.transactionId),
                        requiresReconcile:ambiguous && !exactSuccess,
                        noOp:!!(response && response.noOp === true)
                    });
                    self._preview = null;
                    self._busy = false;
                    if (exactSuccess) {
                        self._adoptSnapshot(response.snapshot);
                        if (operation === 'replace_mod' || operation === 'detach_mod') {
                            self._replaceCandidateKey = '';
                            self._replaceCandidateName = '';
                            self._operation = 'install_mod';
                        }
                        self._targetLevel = nextEnhancementLevel(
                            response.snapshot);
                        self._needsReconcile = false;
                        self._lastCommitCallId = '';
                        self._setModIntentPhase('committed_syncing');
                        self._loadoutBarrier = {
                            kind:'known',
                            callId:String(response.callId || ''),
                            changed:response.noOp !== true,
                            operation:operation,
                            inventorySnapshots:response.inventorySnapshots.length > 0
                                ? response.inventorySnapshots : null,
                            needsInventoryRefresh:false,
                            source:normalizeTuningSource(self._source)
                        };
                        self._status = response.noOp ? '调制无变化，正在同步完整构筑'
                            : self._modIntent
                                ? self._modIntentStatus('committed_syncing')
                                : '调制已确认，正在同步完整构筑';
                        self._emit();
                        self.render();
                        self._beginLoadoutRefresh();
                        return;
                    }
                    if (ambiguous) {
                        var barrierId = EquipmentTuningRuntime.safeToken(
                            response && response.reconcileAfterCallId)
                            || EquipmentTuningRuntime.safeToken(response && response.callId)
                            || EquipmentTuningRuntime.safeToken(callId);
                        self._needsReconcile = !!barrierId;
                        self._lastCommitCallId = barrierId;
                        self._setModIntentPhase('uncertain');
                        self._loadoutBarrier = barrierId ? {
                            kind:'unknown',
                            callId:barrierId,
                            changed:true,
                            operation:operation,
                            inventorySnapshots:null,
                            needsInventoryRefresh:operation === 'convert',
                            source:normalizeTuningSource(self._source)
                        } : null;
                        self._status = barrierId
                            ? '提交结果不明确，先同步完整构筑再完成调制水位对账'
                            : '提交结果不明确，但未取得可用对账水位';
                        self._emit();
                        self.render();
                        if (barrierId) self._beginLoadoutRefresh();
                        else self._finishInventoryWrite(
                            write, operation === 'convert', function(result) {
                            if (operation === 'convert'
                                    && (!result || result.success !== true)) {
                                self._refreshRetryRequired = true;
                                self._status = '提交结果不明确，且背包同步失败；请重试';
                                self._emit();
                                self.render();
                                return;
                            }
                            if (operation === 'convert') {
                                self._target = null;
                                self._targetItem = null;
                            }
                            self.requestSnapshot();
                        });
                        return;
                    }
                    self._loadoutBarrier = null;
                    self._lastCommitCallId = '';
                    self._modIntent = null;
                    self._status = errorMessage(response && response.error);
                    var staleTarget = operation === 'convert' && response
                        && (response.error === 'stale_state'
                            || response.error === 'stale_lease');
                    self._finishInventoryWrite(write, !!staleTarget, function(result) {
                        if (staleTarget && (!result || result.success !== true)) {
                            self._refreshRetryRequired = true;
                            self._status = '目标已变化，且背包同步失败；请重试';
                            self._emit();
                            self.render();
                            return;
                        }
                        if (staleTarget) {
                            self._target = null;
                            self._targetItem = null;
                        }
                        self.requestSnapshot();
                    });
                    self._emit();
                    self.render();
                },
                {
                    onIssued:function(entry) {
                        var diagnostic = self._bindCommitDiagnostic(
                            operation,
                            entry && entry.callId
                        );
                        self._recordDiagnostic('commit_issued', {
                            operation:operation,
                            webCallId:entry && entry.callId,
                            candidateKey:diagnostic.candidateKey,
                            intentKey:diagnostic.intentKey,
                            tokenPresent:true
                        });
                    }
                }
            );
            if (!callId && this._inventoryWriteHandle === write) {
                this._loadoutBarrier = null;
                this._needsReconcile = false;
                this._lastCommitCallId = '';
                this._modIntent = null;
                this._status = errorMessage('not_sent');
                this._finishInventoryWrite(write, false, function() { self.requestSnapshot(); });
                this._emit();
                this.render();
            } else if (!settled) {
                this._lastCommitCallId = callId;
            }
            return !!callId;
        };

        TuningView.prototype._beginLoadoutRefresh = function() {
            if (!this._loadoutBarrier || !this._inventoryWriteHandle
                    || !this._source || this._source.sourceKind !== 'loadout'
                    || this._busy || this._readPending || this._refreshRetryPending) return false;
            var self = this;
            var write = this._inventoryWriteHandle;
            var barrier = this._loadoutBarrier;
            var expectedSource = barrier.source;
            if (!Model.sameLoadoutIdentity(this._source, expectedSource)) {
                this._refreshRetryRequired = true;
                this._status = '角色构筑会话已切换；拒绝跨会话采用快照';
                this._emit();
                this.render();
                return false;
            }
            this._refreshRetryRequired = false;
            this._refreshRetryPending = true;
            this._busy = true;
            this._status = '正在采用完整 11+4 角色构筑快照';
            this._emit();
            this.render();
            var callbackCalled = false;
            var started = this._refreshLoadout(this._source, function(result) {
                callbackCalled = true;
                if (self._inventoryWriteHandle !== write
                        || self._loadoutBarrier !== barrier) return;
                self._refreshRetryPending = false;
                var source = normalizeTuningSource(result && result.source);
                var accepted = result && result.success === true
                    && source && source.sourceKind === 'loadout'
                    && Model.sameLoadoutIdentity(source, expectedSource)
                    && result.item && result.item.itemKind === 'equipment';
                if (!accepted) {
                    self._busy = false;
                    self._refreshRetryRequired = true;
                    self._modIntent = null;
                    self._status = '完整构筑同步失败；必须重试成功后才能继续';
                    self._emit();
                    self.render();
                    return;
                }
                self._resetInfoPanel();
                self._source = source;
                self._sourceItem = result.item;
                self._refreshRetryRequired = false;
                self._busy = false;
                if (barrier.kind === 'unknown') {
                    self._status = '完整构筑已采用，正在按新 revision 对账调制水位';
                    self._emit();
                    self.render();
                    self.requestSnapshot(barrier.callId);
                    return;
                }
                self._finishLoadoutBarrier();
            });
            if (!started && !callbackCalled) {
                this._busy = false;
                this._refreshRetryPending = false;
                this._refreshRetryRequired = true;
                this._status = '当前无法同步完整构筑，请重试';
                this._emit();
                this.render();
            }
            return !!started;
        };

        TuningView.prototype._finishLoadoutBarrier = function() {
            if (!this._loadoutBarrier || !this._inventoryWriteHandle) return false;
            var barrier = this._loadoutBarrier;
            var write = this._inventoryWriteHandle;
            var self = this;
            this._loadoutBarrier = null;
            this._needsReconcile = false;
            this._lastCommitCallId = '';
            this._refreshRetryRequired = false;
            this._refreshRetryPending = false;
            this._busy = false;
            this._modIntent = null;
            this._status = barrier.changed
                ? '当前装备调制已提交并同步'
                : '当前装备状态已确认';
            if (!this._finishInventoryWrite(
                    write,
                    barrier.needsInventoryRefresh === true,
                    function(result) {
                if (!result || result.success !== true) {
                    self._refreshRetryRequired = true;
                    self._status = '构筑已同步，但背包同步失败；请重试';
                    self._emit();
                    self.render();
                    return;
                }
                if (barrier.operation === 'convert') {
                    self._target = null;
                    self._targetItem = null;
                    self._setConversionProjection(true);
                }
                self._toast(barrier.changed ? '当前装备调制已提交。' : '当前装备无需变化。');
                self._emit();
                self.render();
            }, barrier.inventorySnapshots)) {
                this._status = '构筑写锁释放失败，请重新打开面板';
                this._emit();
                this.render();
                return false;
            }
            return true;
        };
    }

    return {install:install};
})();
