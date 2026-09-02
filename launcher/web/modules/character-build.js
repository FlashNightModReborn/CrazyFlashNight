/** Character Build transport/session/view composition; the parent owns routing and close. */
(function(root, factory) {
    'use strict';
    var session = typeof module !== 'undefined' && module.exports
        ? require('./character-build-session.js') : root && root.CharacterBuildSession;
    var view = typeof module !== 'undefined' && module.exports
        ? require('./character-build-view.js') : root && root.CharacterBuildView;
    var tuning = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-tuning.js') : root && root.CharacterBuildTuning;
    var mutation = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-mutation.js') : root && root.CharacterBuildMutation;
    var pose = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-pose.js') : root && root.CharacterBuildPose;
    var projection = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-projection.js')
        : root && root.CharacterBuildProjection;
    var candidateTooltip = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-candidate-tooltip.js')
        : root && root.CharacterBuildCandidateTooltip;
    var transport = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-transport.js')
        : root && root.CharacterBuildTransport;
    var candidateChannel = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-candidate-channel.js')
        : root && root.CharacterBuildCandidateChannel;
    var itemUse = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-item-use.js')
        : root && root.CharacterBuildItemUse;
    var itemUseChannel = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-item-use-channel.js')
        : root && root.CharacterBuildItemUseChannel;
    var api = factory(
        session, view, tuning, mutation, pose, projection, candidateTooltip,
        transport, candidateChannel, itemUse, itemUseChannel, root);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuild = api;
        root.CharacterBuild = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(SessionModule, ViewModule, TuningModule, Mutation, Pose, Projection,
        CandidateTooltipModule, Transport, CandidateChannel, ItemUseModule,
        ItemUseChannel, global) {
    'use strict';
    if (!SessionModule || !SessionModule.CharacterBuildSession) throw new Error('CharacterBuildSession is required');
    if (!ViewModule || !ViewModule.CharacterBuildView) throw new Error('CharacterBuildView is required');
    if (!TuningModule || !TuningModule.CharacterBuildTuning) throw new Error('CharacterBuildTuning is required');
    if (!Mutation) throw new Error('CharacterBuildMutation is required');
    if (!Pose || !Pose.select) throw new Error('CharacterBuildPose is required');
    if (!Projection || typeof Projection.viewSnapshot !== 'function') {
        throw new Error('CharacterBuildProjection is required');
    }
    if (!CandidateTooltipModule || !CandidateTooltipModule.CandidateTooltip) {
        throw new Error('CharacterBuildCandidateTooltip is required');
    }
    if (!Transport || typeof Transport.createRequestMux !== 'function') {
        throw new Error('CharacterBuildTransport is required');
    }
    if (!CandidateChannel || typeof CandidateChannel.install !== 'function') {
        throw new Error('CharacterBuildCandidateChannel is required');
    }
    if (!ItemUseModule || typeof ItemUseModule.Controller !== 'function') {
        throw new Error('CharacterBuildItemUse is required');
    }
    if (!ItemUseChannel || typeof ItemUseChannel.install !== 'function') {
        throw new Error('CharacterBuildItemUseChannel is required');
    }
    var MANIFEST_URL = 'assets/dressup/manifest.json';
    // Structural body fields define stable framing; pose extremities stay draw-only for inspection.
    var CHARACTER_CAMERA_FIT_FIELDS = Pose.cameraFitFields();
    var DRAW_FIELDS = Pose.drawFields();
    var manifestPromise = null;
    var copy = Transport.copy;
    var createRequestMux = Transport.createRequestMux;

    function CharacterBuildController(options) {
        options = options || {};
        var self = this;
        this._document = options.document || global.document;
        this._ports = options.ports || {};
        this._mux = options.mux || createRequestMux(options);
        this._tooltip = options.tooltip || global.PanelTooltip;
        this._session = new SessionModule.CharacterBuildSession({
            mux:this._mux,
            onState:this._stateChanged.bind(this),
            onError:this._error.bind(this),
            onCandidateAuthorityReset:function() {
                // Host revokes the previous candidate source set as soon as a
                // candidates/snapshot read is admitted, even if it later fails.
                self._candidateCache = null;
                if (self._candidateTooltip) self._candidateTooltip.invalidate();
            }
        });
        this._candidateTooltip = new CandidateTooltipModule.CandidateTooltip({
            send:options.send,
            setTimer:options.setTimer,
            clearTimer:options.clearTimer,
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce,
            router:options.router,
            mux:options.tooltipMux,
            tooltip:this._tooltip
        });
        this._mutations = new Mutation.MutationCoordinator({
            session:this._session,
            ports:this._ports,
            onApplied:function(response) { self._applySnapshot(response.payload, true); }
        });
        this._itemUse = new ItemUseModule.Controller({
            send:options.send,
            setTimer:options.setTimer,
            clearTimer:options.clearTimer,
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce,
            router:options.router,
            onState:function(state, reason) {
                self._itemUseStateChanged(state, reason);
            },
            onSettled:function(response, committed, pending) {
                self._itemUseSettled(response, committed, pending);
            },
            onInbox:function(inbox) { self._itemUseInboxChanged(inbox); },
            onCooldown:function(lanes) { self._itemUseCooldownChanged(lanes); }
        });
        this._view = null;
        this._tuning = null;
        this._renderer = null;
        this._rendererState = null;
        this._snapshotPayload = null;
        this._selectedTarget = null;
        this._selectedSlotKey = '';
        this._selectedCandidate = null;
        this._candidateScope = 'backpack';
        // Deliberately one recent entry: Host authorizes candidate tooltips only
        // for its latest candidate source set. A multi-key cache would let the UI
        // redisplay rows whose rich-tooltip capability has already been replaced.
        this._candidateCache = null;
        this._mountGeneration = 0;
        this._resizeObserver = null;
        this._panelInstanceId = '';
        this._candidateRecoverySequence = 0;
        this._itemUseBindKey = '';
        this._itemUseResumeSelection = null;
        this._rewardAuthority = null;
        this._tuningTransport = {
            send:options.send,
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce
        };
    }

    CharacterBuildController.prototype._stateChanged = function(state, reason, debug) {
        if (this._candidateTooltip
                && (reason === 'mutation_start' || reason === 'flush_start'
                    || reason === 'finalize_start' || reason === 'finalize_retry')) {
            this._candidateTooltip.invalidate();
        }
        if (reason === 'mutation_start' || reason === 'flush_start'
                || reason === 'finalize_start' || reason === 'finalize_retry') {
            this._candidateCache = null;
        }
        var tuningLocked = !!(this._tuning && this._tuning.isLocked());
        var itemUseState = this._itemUse
            ? this._itemUse.debugState().state : 'closed';
        var itemUsePending = itemUseState === 'write_pending'
            || itemUseState === 'query_pending';
        var itemUseUnknown = itemUseState === 'needs_reconcile';
        if (this._ports.setStatus) {
            var label = itemUseState === 'write_pending' ? '正在使用物品'
                : itemUseState === 'query_pending' ? '正在确认物品使用结果'
                : itemUseUnknown ? '物品使用结果待确认'
                : tuningLocked ? '正在同步装备调制'
                : reason === 'mutation_reconciled' ? '写入结果已确认'
                : state === 'opening' || state === 'opening_reconcile' ? '正在确认构筑会话'
                : state === 'write_pending' ? '正在写入构筑'
                : state === 'flush_pending' ? '正在应用并保存'
                : state === 'needs_reconcile' ? '等待结果确认'
                : state === 'flush_failed' ? '应用或保存失败'
                : debug && debug.liveRefreshDirty ? '构筑待应用' : '已同步';
            this._ports.setStatus(label, itemUseUnknown
                || state === 'flush_failed' || state === 'needs_reconcile'
                ? 'warning' : state === 'opening' || state === 'opening_reconcile'
                    || state === 'flush_pending' || itemUsePending ? 'busy' : 'ready');
        }
        if (this._view) {
            this._view.setInteractionState(itemUsePending ? 'write_pending'
                : itemUseUnknown ? 'mutation_reconcile'
                : tuningLocked ? 'write_pending'
                : state === 'needs_reconcile' && debug && debug.unknown
                    && debug.unknown.kind === 'mutation' ? 'mutation_reconcile' : state);
            this._view.setItemUseState(itemUseState);
        }
        if (this._ports.setInteractionLocked) {
            var locked = tuningLocked || itemUsePending || itemUseUnknown
                || state === 'write_pending'
                || state === 'needs_reconcile' || state === 'flush_pending';
            this._ports.setInteractionLocked(locked, itemUseUnknown
                ? '物品使用结果尚待确认；只会查询结果，不会自动重放使用。'
                : itemUsePending ? '物品使用正在处理，完成后才能切换整备目标。'
                : tuningLocked
                ? this._tuning.lockReason() : state === 'needs_reconcile'
                ? '写入结果尚待确认，完成对账后才能进入收纳。'
                : state === 'write_pending' ? '构筑正在写入，完成后才能进入收纳。'
                    : locked ? '构筑正在结算，完成后才能进入收纳。' : '');
        }
        if (this._ports.onSessionState) this._ports.onSessionState(state, reason, debug);
    };
    CharacterBuildController.prototype._error = function(response, command) {
        var error = response && response.error;
        // Candidate failures already render in the Web candidate pane, including
        // stale-state recovery. Repeating them in the Flash HUD is both delayed
        // and can outlive a successful tuning commit during close/finalize.
        if (command === 'candidates') return;
        // Tooltip 是悬浮/焦点触发的展示增强；失败时保留本地紧凑摘要，
        // 不用 toast 打断玩家当前的构筑操作。
        if (command === 'tooltip') return;
        if (this._ports.toast) this._ports.toast(command === 'finalize'
            ? '当前构筑尚未完成应用与保存，请重试关闭。'
            : error === 'not_sent' ? '角色构筑连接不可用。' : '角色构筑同步失败，请重试。', command, response);
    };
    CharacterBuildController.prototype._loadManifest = function() {
        if (this._ports.loadManifest) return this._ports.loadManifest();
        if (!manifestPromise) {
            var pending = global.DressupDollRenderer.loadManifest(
                this._ports.manifestUrl || MANIFEST_URL);
            manifestPromise = pending;
            pending.catch(function() {
                if (manifestPromise === pending) manifestPromise = null;
            });
        }
        return manifestPromise;
    };
    CharacterBuildController.prototype._createView = function(host) {
        if (this._view) return this._view;
        var self = this, renderRequest = null;
        this._view = new ViewModule.CharacterBuildView({
            document:this._document,
            density:this._ports.getDensity ? this._ports.getDensity() : 'full',
            candidateScope:this._candidateScope,
            onSlotSelect:function(selection) { return self._selectSlot(selection); },
            onCandidateScopeChange:function(scope, selection) {
                return self._changeCandidateScope(scope, selection);
            },
            onCandidateSelect:function(candidate) {
                self._selectedCandidate = candidate;
                if (self._view) self._view.setItemUseCandidate(candidate);
                self._renderPortrait(candidate);
            },
            bindCandidateTooltip:function(node, candidate, isSuppressed) {
                return self._candidateTooltip
                    ? self._candidateTooltip.bind(node, candidate, isSuppressed) : null;
            },
            fetchLoadoutTooltip:function(target, callback) {
                var callId = self._session.requestLoadoutTooltip(
                    target, function(response, accepted) {
                        callback(accepted
                            ? {success:true, payload:response.payload}
                            : response || {success:false, error:'tooltip_failed'});
                    });
                if (!callId) callback({success:false, error:'not_issued'});
                return callId;
            },
            tooltip:this._tooltip,
            onCommitCandidate:function(candidate) {
                return self._mutations.equip(self._selectedTarget, candidate);
            },
            onUseCandidate:function(candidate) {
                return self._useCandidate(candidate);
            },
            onOpenInbox:function() { return self._openRewardInbox(); },
            onSlotDropEquip:function(slotKey, candidate) {
                return self._equipDroppedCandidate(slotKey, candidate);
            },
            onTune:function() { return self._enterTuning(); },
            onUnequip:function() { return self._mutations.unequip(self._selectedTarget); },
            onReconcile:function() { return self._mutations.reconcile(); },
            renderOwnedSlot:global.InventoryUI && global.InventoryUI.renderOwnedSlot,
            iconHtml:function(name, className) {
                var fallback = '<span class="' + (className || 'inventory-owned-icon')
                    + ' inventory-icon-fallback" aria-hidden="true">◇</span>';
                var html = global.Icons && global.Icons.html
                    ? global.Icons.html(name, className, ' onerror="this.outerHTML=\''
                        + fallback.replace(/"/g, '&quot;') + '\'"') : '';
                return html || fallback;
            },
            onStatsModeChange:function(active, statsRoot, opener) {
                return self._ports.statsMode
                    ? self._ports.statsMode(active, statsRoot, opener) : null;
            },
            onDollViewportChange:function(mode, stage, preview, reason) {
                if (reason === 'pan' || !self._renderer) return;
                if (renderRequest !== null) global.cancelAnimationFrame(renderRequest);
                renderRequest = global.requestAnimationFrame(function() {
                    renderRequest = null;
                    var canvas = self._view && self._view.getCanvas();
                    if (!canvas || !stage.contains(canvas) || !self._renderer
                            || preview.isOpen() !== (mode !== 'embedded')) return;
                    var rect = canvas.getBoundingClientRect();
                    self._renderer.setPixelRatio(Math.min(4, Math.max(1,
                        (Number(global.devicePixelRatio) || 1)
                            * Math.max(rect.width / Math.max(1, canvas.clientWidth || rect.width),
                                rect.height / Math.max(1, canvas.clientHeight || rect.height)))));
                });
            },
            onRequestClose:function(intent) {
                return self._ports.requestClose ? self._ports.requestClose(intent.reason) : false;
            }
        });
        this._view.mount(host);
        this._tuning = new TuningModule.CharacterBuildTuning({
            session:this._session,
            view:this._view,
            ports:this._ports,
            send:this._tuningTransport.send,
            timeoutMs:this._tuningTransport.timeoutMs,
            sessionNonce:this._tuningTransport.sessionNonce,
            density:this._ports.getDensity ? this._ports.getDensity() : 'full',
            projectCandidates:Projection.viewCandidates,
            bindCandidateTooltip:this._candidateTooltip
                ? this._candidateTooltip.bind.bind(this._candidateTooltip) : null,
            invalidateCandidateTooltip:function() {
                if (self._candidateTooltip) self._candidateTooltip.invalidate();
            },
            adoptSnapshot:function(payload, restore) { self._applySnapshot(payload, restore); },
            onLockChange:function() {
                self._stateChanged(self._session.getState(), 'tuning_state', self._session.debugState());
            }
        });
        this._view.setInteractionState(this._session.getState());
        return this._view;
    };
    CharacterBuildController.prototype._ensureRenderer = function() {
        if (!this._view || this._renderer) return;
        var self = this, generation = this._mountGeneration;
        this._loadManifest().then(function(manifest) {
            if (!self._view || self._renderer || generation !== self._mountGeneration) return;
            self._renderer = global.DressupDollRenderer.create(self._view.getCanvas(), {
                manifest:manifest,
                animate:!(global.matchMedia && global.matchMedia('(prefers-reduced-motion: reduce)').matches),
                fps:24,
                maxScale:12,
                ignoreCssTransforms:true
            });
            self._manifest = manifest;
            self._renderPortrait(null);
            self._resizeObserver = new global.ResizeObserver(function() {
                if (self._renderer && self._rendererState) self._renderer.render(self._rendererState);
            });
            self._resizeObserver.observe(self._view.getCanvas());
            self._view.syncDollViewport('renderer');
        }).catch(function() {
            if (generation === self._mountGeneration && self._ports.toast) {
                self._ports.toast('纸娃娃素材不可用；装备管理仍可继续，预览已降级。');
            }
        });
    };
    CharacterBuildController.prototype._portraitState = function(candidate) {
        if (!this._manifest || !this._snapshotPayload) return null;
        var portrait = this._snapshotPayload.portrait || {};
        var equipment = copy(portrait.equipment);
        if (candidate && candidate.raw && candidate.raw.item && this._selectedTarget
                && this._selectedTarget.kind === 'equipment') {
            equipment[this._selectedTarget.slotKey] = String(candidate.raw.item.name || '');
        }
        var pose = Pose.select(equipment, this._selectedTarget);
        var state = global.DressupDollRenderer.buildStateFromEquipment(this._manifest, {
            gender:portrait.gender === '女' ? '女' : '男',
            equipment:equipment,
            appearance:portrait.appearance || {},
            fitFields:CHARACTER_CAMERA_FIT_FIELDS,
            drawFields:DRAW_FIELDS,
            rig:'battle',
            stateLabel:pose.stateLabel,
            attackMode:pose.attackMode,
            zoom:1.05,
            margin:18
        });
        return global.DressupDollRenderer.withFitEnvelope(
            this._renderer,
            state,
            Pose.cameraEnvelopePoses(),
            0.06);
    };
    CharacterBuildController.prototype._renderPortrait = function(candidate) {
        if (!this._renderer) return false;
        this._rendererState = this._portraitState(candidate);
        var rendered = this._rendererState ? !!this._renderer.render(this._rendererState) : false;
        if (rendered && !candidate) this._flashDollSwap();
        return rendered;
    };
    // 换装扫描光（与建角页同一签名）：只在装备真实变更（非候选试穿）重绘时触发。
    CharacterBuildController.prototype._flashDollSwap = function() {
        if (global.matchMedia && global.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
        var canvas = this._view && typeof this._view.getCanvas === 'function'
            ? this._view.getCanvas() : null;
        var stage = canvas && canvas.parentElement;
        if (!stage || !stage.classList || !stage.classList.contains('character-build-doll-stage')) return;
        stage.classList.remove('cb-doll-swapping');
        void stage.offsetWidth;
        stage.classList.add('cb-doll-swapping');
        stage.addEventListener('animationend', function handler() {
            stage.removeEventListener('animationend', handler);
            stage.classList.remove('cb-doll-swapping');
        });
    };
    CharacterBuildController.prototype._applySnapshot = function(
            payload, restoreSelection, deferCandidates) {
        this._snapshotPayload = payload;
        this._selectedCandidate = null;
        this._candidateCache = null;
        if (this._candidateTooltip) {
            this._candidateTooltip.reset(
                this._panelInstanceId,
                this._session.getSessionGeneration());
        }
        var projected = Projection.viewSnapshot(payload);
        this._createView().setSnapshot(projected);
        this._itemUseCooldownFromSnapshot(projected);
        this._view.setItemUseCandidate(null);
        this._bindItemUse();
        this._ensureRenderer();
        this._renderPortrait(null);
        var restored = restoreSelection !== false && this._selectedSlotKey
            && this._view.restoreSlot(this._selectedSlotKey);
        if (!restored) {
            this._selectedSlotKey = '';
            this._selectedTarget = null;
            this._candidateScope = 'backpack';
            this._session.setCandidateScope(this._candidateScope);
            // Reactivation first paints the cached snapshot, then immediately asks
            // for a fresh snapshot. Only the fresh adoption may issue the neutral
            // overview read, otherwise one view mount creates duplicate traffic.
            if (deferCandidates !== true) this._view.showBackpackOverview();
        }
    };
    CharacterBuildController.prototype._enterTuning = function() {
        if (!this._tuning || !this._selectedTarget
                || this._selectedTarget.kind !== 'equipment' || !this._snapshotPayload) return false;
        var entered = false;
        if (this._selectedCandidate) {
            if (this._candidateTooltip) this._candidateTooltip.invalidate();
            entered = this._tuning.enterCandidate(
                this._selectedCandidate, this._selectedTarget, this._panelInstanceId);
        } else {
            var item = TuningModule.findEquipment(
                this._snapshotPayload, this._selectedTarget.slotKey);
            if (!item) return false;
            if (this._candidateTooltip) this._candidateTooltip.invalidate();
            entered = this._tuning.enter(
                this._selectedTarget.slotKey, item, this._panelInstanceId);
        }
        // Tuning owns a separate read/write lifecycle and may replace the exact
        // inventory source lease. Only revoke the optimistic read after entry
        // really succeeds; a refused attempt keeps the still-valid authority.
        if (entered) this._candidateCache = null;
        return entered;
    };

    CharacterBuildController.prototype.activate = function(host, panelInstanceId) {
        if (!host || !panelInstanceId) return false;
        if (!this._view) {
            this._candidateScope = 'backpack';
            this._session.setCandidateScope(this._candidateScope);
        }
        this._panelInstanceId = String(panelInstanceId);
        this._mountGeneration++;
        var generation = this._mountGeneration, exactPanelInstanceId = this._panelInstanceId;
        this._createView(host);
        this._ensureRenderer();
        var self = this;
        if (this._session.getState() === 'closed') {
            return !!this._session.open(this._panelInstanceId, function(response, accepted) {
                if (generation !== self._mountGeneration
                        || exactPanelInstanceId !== self._panelInstanceId) return;
                if (accepted && self._view) {
                    self._applySnapshot(response.payload);
                } else if (self._session.getState() === 'closed'
                        && self._ports.onMountFailed) {
                    self._ports.onMountFailed(exactPanelInstanceId, response);
                }
            });
        }
        if (this._snapshotPayload) this._applySnapshot(
            this._snapshotPayload, false, true);
        if (this._candidateTooltip) this._candidateTooltip.invalidate();
        return !!this._session.refreshSnapshot(function(response, accepted) {
            if (generation === self._mountGeneration
                    && exactPanelInstanceId === self._panelInstanceId
                    && accepted && self._view) {
                self._applySnapshot(response.payload);
            }
        });
    };
    CharacterBuildController.prototype.suspend = function() {
        this._candidateRecoverySequence++;
        this._mountGeneration++;
        if (this._candidateTooltip) this._candidateTooltip.suspend();
        this._candidateCache = null;
        this._stopItemUseCooldownPolling();
        if (this._itemUse) this._itemUse.close();
        this._itemUseBindKey = '';
        this._itemUseResumeSelection = null;
        this._rewardAuthority = null;
        this._session.suspendView();
        if (this._tuning) this._tuning.destroy();
        this._tuning = null;
        if (this._resizeObserver) this._resizeObserver.disconnect();
        this._resizeObserver = null;
        if (this._renderer) this._renderer.destroy();
        this._renderer = null;
        this._rendererState = null;
        if (this._view) this._view.destroy();
        this._view = null;
        return true;
    };
    CharacterBuildController.prototype.openStats = function(opener) {
        if (!this._view || this._tuning && this._tuning.isActive()) return false;
        var self = this;
        return !!this._session.prepareStats(function(response, accepted) {
            if (!accepted || !self._view) return;
            self._view.setStats(response.payload);
            self._view.openStats(opener);
        });
    };
    CharacterBuildController.prototype.closeStats = function(reason) {
        return !!(this._view && this._view.closeStats(reason));
    };
    CharacterBuildController.prototype.consumeEscape = function() {
        if (this._tuning && this._tuning.isActive()) return this._tuning.consumeEscape();
        return !!(this._view && this._view.consumeEscape());
    };
    CharacterBuildController.prototype.setDensity = function(mode) {
        if (this._tuning) this._tuning.setDensity(mode);
        return !!(this._view && this._view.setDensity(mode));
    };
    CharacterBuildController.prototype.syncViewport = function() { if (this._view) this._view.syncDollViewport('mount'); };
    CharacterBuildController.prototype.openHelp = function() {
        if (this._tuning && this._tuning.isActive()) return this._tuning.openHelp();
        return this._ports.openModal ? !!this._ports.openModal({
            kind:'character-build-help',
            title:'角色构筑帮助',
            message:'未选择栏位时默认显示背包总览，可把装备拖到高亮栏位；礼包与药剂则在选中后用明确按钮打开或服用。',
            detail:'选择装备/药剂栏会切换到该栏位的兼容候选，主按钮仍用于装备或装入。背包总览中的可用物品只响应按钮或再次按 Enter，不响应双击；礼包内容进入待领取页，药剂由系统选择符合规则的冷却通道。结果未知时只查询原操作，不会自动重放。',
            actions:[{id:'close', label:'知道了', primary:true, audioCue:'confirm'}]
        }) : false;
    };
    CharacterBuildController.prototype.finalize = function(callback) {
        var itemUseState = this._itemUse.debugState().state;
        if (itemUseState !== 'idle' && itemUseState !== 'closed') {
            if (callback) callback(false, {
                success:false, error:'item_use_pending'
            }, itemUseState === 'needs_reconcile');
            return null;
        }
        if (this._tuning && this._tuning.isActive()) {
            var self = this;
            return this._tuning.exit(function(detached) {
                if (detached) self.finalize(callback);
                else if (callback) callback(false, {success:false, error:'tuning_detach_failed'}, false);
            });
        }
        return this._session.finalize(function(response, accepted, unknown) {
            if (callback) callback(accepted, response, unknown);
        });
    };
    CharacterBuildController.prototype.canLeave = function() {
        var state = this._session.getState();
        var itemUseState = this._itemUse.debugState().state;
        return (itemUseState === 'idle' || itemUseState === 'closed')
            && (state === 'idle' || state === 'flush_failed');
    };
    CharacterBuildController.prototype.prepareLeave = function(callback) {
        if (this._tuning && this._tuning.isActive()) {
            var self = this;
            return this._tuning.exit(function(detached) {
                if (detached) self.prepareLeave(callback);
                else if (callback) callback(false);
            });
        }
        return this._session.prepareLeave(function(_, accepted) {
            if (callback) callback(accepted);
        });
    };
    CharacterBuildController.prototype.canClose = function() {
        var itemUseState = this._itemUse.debugState().state;
        return (itemUseState === 'idle' || itemUseState === 'closed')
            && !(this._tuning && this._tuning.isActive()) && this._session.canClose();
    };
    CharacterBuildController.prototype.destroy = function() {
        this._candidateRecoverySequence++;
        this.suspend();
        if (this._candidateTooltip) this._candidateTooltip.destroy();
        this._itemUse.destroy();
        this._session.destroy();
        this._mutations.destroy();
        return true;
    };
    CharacterBuildController.prototype.debugState = function() {
        return {
            mounted:!!this._view,
            rendererCount:this._renderer ? 1 : 0,
            selectedTarget:this._selectedTarget,
            selectedSlotKey:this._selectedSlotKey,
            mutationPending:this._mutations.isPending(),
            tuning:this._tuning ? this._tuning.debugState() : null,
            candidateTooltip:this._candidateTooltip
                ? this._candidateTooltip.debugState() : null,
            candidateCacheCount:this._candidateCache ? 1 : 0,
            itemUseResumeSelection:this._itemUseResumeSelection ? {
                physicalSlot:this._itemUseResumeSelection.physicalSlot,
                itemName:this._itemUseResumeSelection.itemName,
                requestKey:this._itemUseResumeSelection.requestKey || ''
            } : null,
            itemUse:this._itemUse.debugState(),
            session:this._session.debugState(),
            view:this._view ? this._view.debugState() : null
        };
    };

    ItemUseChannel.install(CharacterBuildController.prototype);
    CandidateChannel.install(CharacterBuildController.prototype);
    return {
        CharacterBuildController:CharacterBuildController,
        createRequestMux:createRequestMux,
        candidateCacheTarget:CandidateChannel.candidateCacheTarget
    };
});
