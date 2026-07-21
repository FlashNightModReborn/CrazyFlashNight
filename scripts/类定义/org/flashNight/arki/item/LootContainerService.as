import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.LootContainerValidation;
import org.flashNight.arki.item.LootClaimCommitCoordinator;
import org.flashNight.gesh.tooltip.TooltipComposer;

/**
 * 地图网格箱的瞬态战利品权威。
 *
 * 奖励只在 AS2 内存中存在。Web 只收到投影与不可猜写 lease；所有领取均由本类按
 * loot -> player 单向策略提交。beginFixture/register/commitReservedOpen/observeDeath/
 * activateReservedOpen 把“完整物化后才 kill”收成同步门，避免 source 已死而容器未注册。
 */
class org.flashNight.arki.item.LootContainerService {
    private static var STATE_PENDING:String = "LOOT_COMMIT_PENDING";
    private static var STATE_ACTIVE:String = "LOOT_ACTIVE";
    private static var STATE_SUSPENDED:String = "LOOT_SUSPENDED";
    private static var STATE_CONSUMED:String = "CONSUMED";
    private static var STATE_ABANDONED:String = "ABANDONED";
    private static var STATE_EXPIRED:String = "EXPIRED";
    private static var PANEL_SOURCE:String = "map_chest";
    private static var FLOW_PROFILE:String = "web-loot-v1";
    private static var MAX_SAFE_INTEGER:Number = 9007199254740991;
    private static var MAX_TOMBSTONES:Number = 16;
    private static var MAX_RECOVERY_PROOFS:Number = 8;

    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;
    private static var _busy:Boolean = false;
    private static var _authorityEpoch:Number = 1;
    private static var _sessionSeq:Number = 0;
    private static var _containerEpochSeq:Number = 0;
    private static var _leaseSeq:Number = 0;
    private static var _closeLeaseSeq:Number = 0;
    private static var _snapshotSeq:Number = 0;
    private static var _legacyClaimSeq:Number = 0;
    private static var _reservation:Object = null;
    private static var _active:Object = null;
    private static var _legacyRecovery:Object = null;
    private static var _legacyObserverRecord:Object = null;
    private static var _legacyObserverDispatcher:Object = null;
    private static var _legacyObserverCallback:Function = null;
    private static var _terminalBySession:Object = {};
    private static var _terminalOrder:Array = [];
    private static var _lootLeaseIds:Array = [];
    private static var _lootLeaseRefs:Array = [];
    private static var _lootLeaseVersions:Array = [];
    private static var _lootLeaseSignatures:Array = [];
    private static var _testPostCommitFailureStage:String = "";
    private static var _testPostCommitFailureRemaining:Number = 0;
    private static var _testTransportHandoffFailureStage:String = "";

    public static function install():Void {
        if (_inited) return;
        _json = new LiteJSON();
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["lootSnapshot"] = function(params) {
            org.flashNight.arki.item.LootContainerService.handle("snapshot", params);
        };
        _root.gameCommands["lootTooltip"] = function(params) {
            org.flashNight.arki.item.LootContainerService.handle("tooltip", params);
        };
        _root.gameCommands["lootClaim"] = function(params) {
            org.flashNight.arki.item.LootContainerService.handle("claim", params);
        };
        _root.gameCommands["lootClose"] = function(params) {
            org.flashNight.arki.item.LootContainerService.handle("close", params);
        };
        _root.gameCommands["lootQuery"] = function(params) {
            org.flashNight.arki.item.LootContainerService.handle("query", params);
        };
        _root.gameCommands["lootPanelRecovery"] = function(params) {
            org.flashNight.arki.item.LootContainerService.handlePanelRecovery(params);
        };
        _inited = true;
    }

    private static function handle(commandName:String, params:Object):Void {
        var response:Object = execute(commandName, params);
        response.task = "loot_response";
        response.callId = params == undefined ? undefined : params.callId;
        sendResponse(response);
    }

    /** 同步测试入口；wire handler 只额外补 task/callId。 */
    public static function execute(commandName:String, params:Object):Object {
        if (_busy) return emptyFailure(params, "busy");
        if (params == undefined || params.v !== 1) {
            return emptyFailure(params, "unsupported_version");
        }
        if (!validateCommandShape(commandName, params)) return emptyFailure(params, "invalid_payload");
        if (commandName == "snapshot") return executeSnapshot(params);
        if (commandName == "tooltip") return executeTooltip(params);
        if (commandName == "claim") return executeClaim(params);
        if (commandName == "close") return executeClose(params);
        if (commandName == "query") return executeQuery(params);
        return emptyFailure(params, "unsupported_cmd");
    }

    /**
     * InteractionHandler 的最早裁决。无 marker 委托 legacy；精确 marker 一旦命中即由本服务
     * handled=true 占住，禁止旧 handler 在奖励完整物化前直接 kill。
     */
    public static function beginFixture(target:Object):Object {
        var guard:Object = guardAnyGridFixture(target);
        if (guard.handled) return guard;

        var hasRollout:Boolean = hasOwnField(target, "chestRolloutId");
        var hasProfile:Boolean = hasOwnField(target, "lootFlowProfile");
        var hasUnlockPolicy:Boolean = hasOwnField(target, "unlockPolicy");
        if (!hasRollout && !hasProfile && !hasUnlockPolicy) {
            return {handled:false, reserved:false, reason:"not_web_loot_fixture"};
        }
        if (!hasRollout || !hasProfile || !hasUnlockPolicy
                || typeof target.chestRolloutId != "string"
                || !isSafeToken(String(target.chestRolloutId), 64)
                || typeof target.lootFlowProfile != "string"
                || target.lootFlowProfile !== FLOW_PROFILE
                || typeof target.unlockPolicy != "string"
                || target.unlockPolicy !== "skip") {
            return {handled:true, reserved:false, reason:"invalid_rollout_marker"};
        }
        if (!hasExactGridShape(target)) {
            return {handled:true, reserved:false, reason:"invalid_grid_shape"};
        }
        if (_reservation != null || _active != null) {
            return {handled:true, reserved:false, reason:"loot_flow_busy"};
        }

        _sessionSeq++;
        _containerEpochSeq++;
        var stem:String = _authorityEpoch + "." + _sessionSeq;
        _reservation = {
            target:target,
            rolloutId:String(target.chestRolloutId),
            rolloutProfile:String(target.lootFlowProfile),
            unlockPolicy:String(target.unlockPolicy),
            presetName:String(target.presetName),
            row:Number(target.row),
            col:Number(target.col),
            chestSessionId:"chest." + stem,
            lootContainerId:"loot." + stem,
            closeLease:"close." + stem + "." + getTimer(),
            containerEpoch:_containerEpochSeq,
            authorityRevision:1,
            lastAppliedOperationId:"",
            state:STATE_PENDING,
            reason:"",
            inventory:null,
            materialized:false,
            killIssued:false,
            killDispatchInProgress:false,
            ownKillObserved:false,
            operations:{},
            pendingCommit:null,
            postCommitEffects:null,
            transportDetachNeeded:false,
            transportDetachReason:"",
            transportRendererDone:false,
            transportUnpauseDone:false,
            legacyRendererConfirmed:false,
            legacyRecovery:false,
            targetHeld:false,
            suspendedAnchorRegistered:false,
            suspendPauseReleasePending:false,
            openAttemptSeq:0,
            openAttemptWasReopen:false,
            reopenBaseSuspendedAttemptSeq:0,
            suspendedFromOpenAttemptSeq:0,
            terminalFromOpenAttemptSeq:0,
            reopenAttemptSeq:0,
            acceptedOpenAttemptSeq:0,
            recoveryPendingOpenAttemptSeq:0,
            recoveryPendingNonce:"",
            recoveryPendingReason:"",
            recoveryAppliedOpenAttemptSeq:0,
            recoveryAppliedNonce:"",
            socketDetachObservedOpenAttemptSeq:0,
            socketDetachAppliedOpenAttemptSeq:0,
            completedRecoveryProofs:{},
            completedRecoveryProofOrder:[],
            transportDetachResumeSuspended:false,
            transportDetachReleasePause:false
        };
        return {
            handled:true,
            reserved:true,
            reason:"reserved",
            state:STATE_PENDING,
            chestSessionId:_reservation.chestSessionId,
            lootContainerId:_reservation.lootContainerId,
            containerEpoch:_reservation.containerEpoch
        };
    }

    /** 把一次且仅一次的已滚取 ArrayInventory 绑定到 reservation。这里只登记，不 kill、不开放 Web。 */
    public static function register(target:Object, inventory:ArrayInventory, metadata:Object):Object {
        if (_busy) return localFailure("busy");
        var reservation:Object = _reservation;
        if (reservation == null || reservation.target !== target) return localFailure("reservation_mismatch");
        if (reservation.state != STATE_PENDING) return localFailure("terminal_state");
        if (reservation.materialized) {
            if (reservation.inventory === inventory && metadataMatches(reservation, metadata)) {
                var duplicate:Object = recordResponse(reservation, true, "");
                duplicate.duplicate = true;
                return duplicate;
            }
            return localFailure("materialization_conflict");
        }
        if (!metadataMatches(reservation, metadata)) return localFailure("metadata_mismatch");
        if (!validateInventory(inventory, reservation.row * reservation.col)) {
            return localFailure("invalid_loot_inventory");
        }
        reservation.inventory = inventory;
        reservation.materialized = true;
        reservation.authorityRevision++;
        return recordResponse(reservation, true, "");
    }

    /**
     * 奖励创建/验证失败时撤销尚未 kill 的 reservation。只终止精确同一 target，
     * 不接触 active authority，也不把业务失败遗留成全局 busy。
     */
    public static function abortReservedOpen(target:Object, reason:String):Object {
        if (_busy) return localFailure("busy");
        var reservation:Object = _reservation;
        if (reservation == null || reservation.target !== target) {
            return localFailure("reservation_mismatch");
        }
        if (reservation.killIssued) return localFailure("kill_already_issued");
        var terminalReason:String = isSafeReason(reason) ? reason : "reservation_aborted";
        return finishTerminal(reservation, STATE_EXPIRED, terminalReason, "");
    }

    /**
     * 安全 kill 提交：先保存唯一 inventory/killIssued，再在同步调用栈执行 killAction。
     * killAction 必须返回 true，并在返回前经 observeDeath(target) 证明观察到 own kill。
     */
    public static function commitReservedOpen(target:Object, inventory:ArrayInventory,
                                              metadata:Object, killAction:Function):Object {
        if (_busy) return localFailure("busy");
        var registered:Object = register(target, inventory, metadata);
        if (!registered.success) return registered;
        var reservation:Object = _reservation;
        if (typeof killAction != "function") {
            moveToLegacyRecovery(reservation, "kill_adapter_unavailable");
            return localFailure("kill_adapter_unavailable");
        }
        if (reservation.killIssued) return localFailure("kill_already_issued");

        reservation.killIssued = true;
        reservation.killDispatchInProgress = true;
        reservation.authorityRevision++;
        _busy = true;
        var adapterAccepted:Boolean = false;
        try {
            adapterAccepted = killAction(target) === true;
        } catch (killError) {
            adapterAccepted = false;
        }
        reservation.killDispatchInProgress = false;
        _busy = false;

        if (!adapterAccepted) {
            moveToLegacyRecovery(reservation, "kill_adapter_failed");
            return localFailure("kill_adapter_failed");
        }
        if (!reservation.ownKillObserved) {
            moveToLegacyRecovery(reservation, "own_kill_unobserved");
            return localFailure("own_kill_unobserved");
        }
        return recordResponse(reservation, true, "");
    }

    /** KillEventComponent 在同步 kill 派发中调用；只有当前 reservation 的 own kill 可解门。 */
    public static function observeDeath(target:Object):Object {
        if (_reservation != null && _reservation.target === target) {
            if (_reservation.killIssued && _reservation.ownKillObserved) {
                return {handled:true, ownKill:true, reason:"duplicate_own_death"};
            }
            if (_reservation.killIssued && _reservation.killDispatchInProgress) {
                _reservation.ownKillObserved = true;
                _reservation.authorityRevision++;
                return {handled:true, ownKill:true, reason:"own_kill_observed"};
            }
            if (_reservation.inventory == null) {
                finishTerminal(_reservation, STATE_EXPIRED, "unexpected_death", "");
                return {handled:true, ownKill:false, reason:"unexpected_death"};
            }
            moveToLegacyRecovery(_reservation, "unexpected_death");
            return {handled:true, ownKill:false, reason:"unexpected_death"};
        }
        if (_active != null && _active.target === target && _active.ownKillObserved) {
            return {handled:true, ownKill:true, reason:"duplicate_own_death"};
        }
        if (_legacyRecovery != null && _legacyRecovery.target === target) {
            return {handled:true, ownKill:false, reason:"legacy_recovery"};
        }
        return {handled:false, ownKill:false, reason:"not_active_target"};
    }

    /**
     * 真实 MovieClip onUnload 的生命周期边界。SUSPENDED anchor 一旦离开场景就不再
     * 可恢复，必须原子撤销 arbiter 强引用并落 EXPIRED，禁止遗留假 anchor/global busy。
     */
    public static function handleTargetUnload(target:Object):Object {
        var record:Object = _active;
        if (record != null && record.target === target && record.state == STATE_SUSPENDED) {
            if (record.pendingCommit != null || record.postCommitEffects != null
                    || record.transportDetachNeeded === true) {
                return failureFor(record, "commit_pending");
            }
            if (record.suspendPauseReleasePending === true) {
                var released:Object = releaseSuspendedPauseForClose();
                // target 已不可恢复；即使 PauseManager 暂时失败也必须先消除假 anchor。
                // 迟到 generic unpause 仍会按普通面板路径释放共享 lease。
                if (released == null || released.success !== true) {
                    record.suspendPauseReleasePending = false;
                }
            }
            var expired:Object = finishTerminal(
                record, STATE_EXPIRED, "suspended_anchor_unloaded", "");
            expired.handled = true;
            expired.ownKill = false;
            return expired;
        }
        return observeDeath(target);
    }

    /** 箱子结束帧调用；只有 materialized + own-kill proof 齐全才开放 Web authority。 */
    public static function activateReservedOpen(target:Object):Object {
        if (_busy) return localFailure("busy");
        if (_active != null && _active.target === target && _active.state == STATE_ACTIVE) {
            if (!holdTargetTimeline(_active)) return localFailure("target_hold_failed");
            var duplicate:Object = recordResponse(_active, true, "");
            duplicate.duplicate = true;
            return duplicate;
        }
        var reservation:Object = _reservation;
        if (reservation == null || reservation.target !== target) return localFailure("reservation_mismatch");
        if (!reservation.materialized || !reservation.killIssued || !reservation.ownKillObserved) {
            moveToLegacyRecovery(reservation, "activation_gate_failed");
            return localFailure("activation_gate_failed");
        }
        // 本函数只在箱体 authored open/break callback 的同步调用栈执行。先冻结根时间轴，
        // 后开放 authority，保证 Web 生命周期内不会自然跑到“无效”帧 removeMovieClip。
        if (!holdTargetTimeline(reservation)) {
            moveToLegacyRecovery(reservation, "target_hold_failed");
            return localFailure("target_hold_failed");
        }
        reservation.state = STATE_ACTIVE;
        reservation.authorityRevision++;
        _active = reservation;
        _reservation = null;
        invalidateLootLeases();
        return recordResponse(_active, true, "");
    }

    /**
     * 通过 ServerManager callback envelope 请求打开 panel。同步投递失败由调用方回退；
     * 已投递后的拒绝、断线或 timeout 则由 exact callback 自动进入 same-object recovery。
     */
    public static function requestOpenPanel():Boolean {
        var dispatched:Object = dispatchPanelOpen(false);
        return dispatched != null && dispatched.queued === true;
    }

    /**
     * panel_request 的严格投递边界。ServerManager 在 socket 未连接 / stringify
     * 失败时会在 sendTaskWithCallback 调用栈内同步回调失败；“方法正常返回”
     * 因此不等于“已投递”。本方法显式观察同步 callback，且把 reopen 意图
     * 绑到 exact openAttemptSeq，供异步拒绝 / timeout 恢复原 suspend anchor。
     */
    private static function dispatchPanelOpen(reopenAttempt:Boolean):Object {
        var record:Object = _active;
        if (record == null || record.state != STATE_ACTIVE) {
            return {queued:false, attemptStarted:false, callbackObserved:false,
                callbackAccepted:false, error:"panel_open_unavailable"};
        }
        var transport:Object = _root.server;
        if (transport == undefined || typeof transport.sendTaskWithCallback != "function") {
            return {queued:false, attemptStarted:false, callbackObserved:false,
                callbackAccepted:false, error:"panel_open_unavailable"};
        }
        if (!hasRecoveryProofCapacity(record)) {
            return {queued:false, attemptStarted:false, callbackObserved:false,
                callbackAccepted:false, error:"recovery_history_full"};
        }
        clearCurrentRecoveryProof(record);
        record.openAttemptSeq = Number(record.openAttemptSeq) + 1;
        record.openAttemptWasReopen = reopenAttempt === true;
        record.reopenBaseSuspendedAttemptSeq = reopenAttempt === true
            ? Number(record.suspendedFromOpenAttemptSeq) : 0;
        // callback 之外也必须持久保存当前 open 的来源。socket close 会先执行
        // transport detach、随后才清 pending callback；只放在 closure 内无法在
        // legacy handoff 前识别这是一次 reopen。
        record.reopenAttemptSeq = reopenAttempt === true ? record.openAttemptSeq : 0;
        record.acceptedOpenAttemptSeq = 0;
        var identity:Object = {
            chestSessionId:record.chestSessionId,
            lootContainerId:record.lootContainerId,
            containerEpoch:record.containerEpoch,
            openAttemptSeq:record.openAttemptSeq,
            reopenAttempt:reopenAttempt === true
        };
        var callbackObserved:Boolean = false;
        var callbackAccepted:Boolean = false;
        var callbackError:String = "";
        try {
            transport.sendTaskWithCallback(
                "panel_request",
                LootContainerValidation.buildPanelRequest(record, PANEL_SOURCE),
                null,
                function(response:Object):Void {
                    callbackObserved = true;
                    callbackAccepted = response != null
                        && response.success === true && response.accepted === true;
                    if (!callbackAccepted) {
                        callbackError = LootContainerValidation.panelOpenFailureReason(response);
                    }
                    org.flashNight.arki.item.LootContainerService.handlePanelOpenResponse(
                        identity, response);
                },
                600
            );
        } catch (sendError) {
            return {queued:false, attemptStarted:true,
                callbackObserved:callbackObserved, callbackAccepted:callbackAccepted,
                error:callbackError == "" ? "panel_open_unavailable" : callbackError};
        }
        if (callbackObserved && !callbackAccepted) {
            return {queued:false, attemptStarted:true, callbackObserved:true,
                callbackAccepted:false,
                error:callbackError == "" ? "panel_open_rejected" : callbackError};
        }
        return {queued:true, attemptStarted:true,
            callbackObserved:callbackObserved, callbackAccepted:callbackAccepted, error:""};
    }

    /** Arbiter 唯一允许绕过 _killed 的能力判断；不写 target，也不放宽其他交互条件。 */
    public static function canReopenSuspendedTarget(target:Object):Boolean {
        var record:Object = _active;
        return record != null && record.state == STATE_SUSPENDED
            && record.target === target && record.targetHeld === true
            && record.suspendedAnchorRegistered === true
            && record.suspendPauseReleasePending !== true
            && record.pendingCommit == null && record.postCommitEffects == null
            && record.transportDetachNeeded !== true;
    }

    /**
     * exact suspended target 的原对象重开。沿用 triple/inventory，只刷新 close lease；
     * 同步 transport 未投递时恢复 SUSPENDED anchor，不重滚、不 kill、不重播拾取音效。
     */
    public static function resumeSuspended(target:Object):Object {
        if (_busy) return localFailure("busy");
        var record:Object = _active;
        if (record == null || record.target !== target || record.state != STATE_SUSPENDED) {
            return localFailure("not_suspended_target");
        }
        if (record.pendingCommit != null || record.postCommitEffects != null
                || record.transportDetachNeeded === true) {
            return failureFor(record, "commit_pending");
        }
        if (!hasRecoveryProofCapacity(record)) {
            return failureFor(record, "recovery_history_full");
        }
        // 上一页 suspend 的暂停解除尚未得到本地证明时，游戏本不应接受下一次互动。
        if (record.suspendPauseReleasePending === true) {
            return failureFor(record, "pause_release_pending");
        }
        // 全局 webpanel lease 不是 loot-scoped。正常 suspend close 的 exact
        // unpause 已证明后这里必须为空；否则拒绝开始新 attempt，避免把别的 panel
        // lease 误认成 reopen 所有并在失败恢复时释放。
        if (_root._webPanelPauseLease != undefined) {
            return failureFor(record, "pause_release_pending");
        }
        if (record.targetHeld !== true || record.suspendedAnchorRegistered !== true) {
            return failureFor(record, "suspend_unavailable");
        }
        var transport:Object = _root.server;
        if (transport == undefined || typeof transport.sendTaskWithCallback != "function") {
            return failureFor(record, "panel_open_unavailable");
        }
        if (!org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.BoxInteractionArbiter.unregister(
                target)) {
            return failureFor(record, "suspend_unavailable");
        }
        record.suspendedAnchorRegistered = false;
        record.state = STATE_ACTIVE;
        record.reason = "";
        record.closeLease = mintCloseLease(record);
        record.suspendPauseReleasePending = false;
        record.authorityRevision++;
        invalidateLootLeases();

        var dispatched:Object = dispatchPanelOpen(true);
        if (dispatched != null && dispatched.queued === true
                && record.state == STATE_ACTIVE) {
            var resumed:Object = recordResponse(record, true, "");
            resumed.reopened = true;
            return resumed;
        }

        var dispatchError:String = dispatched == null || typeof dispatched.error != "string"
            ? "panel_open_unavailable" : String(dispatched.error);
        // 同步 callback failure 已在 exact attempt 回调中收回 SUSPENDED；
        // 方法缺失 / send 抛错则由调用方执行同一恢复 helper。两条路都
        // 不报 reopened，也不触发 same-object legacy renderer。
        if (record.state != STATE_SUSPENDED && !isTerminalState(record.state)) {
            var restored:Object = restoreSuspendedAfterReopenFailure(
                record, dispatchError, Number(record.openAttemptSeq));
            if (restored == null || restored.success !== true) {
                return restored == null ? failureFor(record, "suspend_unavailable") : restored;
            }
        }
        return failureFor(record, dispatchError);
    }

    private static function handlePanelOpenResponse(identity:Object, response:Object):Void {
        var record:Object = _active;
        if (record == null || record.state != STATE_ACTIVE
                || record.chestSessionId !== identity.chestSessionId
                || record.lootContainerId !== identity.lootContainerId
                || Number(record.containerEpoch) != Number(identity.containerEpoch)
                || Number(record.openAttemptSeq) != Number(identity.openAttemptSeq)) return;
        if (response != null && response.success === true && response.accepted === true) {
            // 只有 exact callback accepted 才把 pending attempt 升格为 Host 已接纳。
            // open 来源是 attempt 的持久属性，不能因 callback 先后顺序被清掉。
            record.acceptedOpenAttemptSeq = Number(identity.openAttemptSeq);
            pruneCompletedRecoveryProofsBefore(record, Number(identity.openAttemptSeq));
            record.reopenBaseSuspendedAttemptSeq = 0;
            advancePendingPanelRecovery(record);
            return;
        }
        var failureReason:String = LootContainerValidation.panelOpenFailureReason(response);
        if (identity.reopenAttempt === true) {
            restoreSuspendedAfterReopenFailure(
                record, failureReason, Number(identity.openAttemptSeq));
            return;
        }
        // transport-detach reconcile 可能已先完成 same-object recovery；随后清理
        // pending callback 时不得为同一 record 再创建一次 legacy renderer。
        if (_legacyRecovery === record) return;
        record.transportDetachReason = failureReason;
        reconcileTransportDetach(record.target);
    }

    /**
     * reopen 在任何权威写开始前失败时，不具备跳回旧 AS2 renderer 的理由：
     * 先重新建立 exact target anchor，再把 authority 收回 LOOT_SUSPENDED。这个
     * helper 同时服务“方法不存在 / send 抛错”的 no-send 与 callback 失败。
     */
    private static function restoreSuspendedAfterReopenFailure(record:Object,
                                                                reason:String,
                                                                attemptSeq:Number):Object {
        if (record == null || _active !== record
                || Number(record.openAttemptSeq) != Number(attemptSeq)
                || record.openAttemptWasReopen !== true) {
            return localFailure("stale_open_attempt");
        }
        if (record.state == STATE_SUSPENDED) {
            return recordResponse(record, true, "");
        }
        if (record.state != STATE_ACTIVE) return failureFor(record, "terminal_state");
        if (record.pendingCommit != null || record.postCommitEffects != null
                || (record.transportDetachNeeded === true
                    && record.transportDetachResumeSuspended !== true)) {
            return failureFor(record, "commit_pending");
        }
        var attemptOwnsRecovery:Boolean = Number(record.acceptedOpenAttemptSeq) == attemptSeq
            || Number(record.recoveryPendingOpenAttemptSeq) == attemptSeq
            || Number(record.socketDetachObservedOpenAttemptSeq) == attemptSeq;
        var suspendedOriginAttempt:Number = attemptOwnsRecovery
            ? attemptSeq : Number(record.reopenBaseSuspendedAttemptSeq);
        if (suspendedOriginAttempt <= 0) suspendedOriginAttempt = attemptSeq;

        // 可恢复性证明必须先于 authority/revision 改变。若 target 已经离开
        // world 或 arbiter 不可用，原地继续 ACTIVE 会只留不可达强引用；按锚点
        // 丢失的生命周期边界显式 EXPIRED，也绝不创建 legacy renderer。
        // reopen 失败时 inventory 已可能在上一页被取空；空 authority 不得制造
        // LOOT_SUSPENDED(remaining=0)。先安全释放可能存在的本次 panel lease，
        // 再按同一 inventory 落 CONSUMED。
        if (remainingCount(record) <= 0) {
            if (_root._webPanelPauseLease != undefined && !releaseTransportPauseLease()) {
                return holdReopenTerminalPauseRetry(record, reason);
            }
            markCompletedRecoveryProofs(record, attemptSeq);
            record.terminalFromOpenAttemptSeq = suspendedOriginAttempt;
            recordAuthorityClosedProof(record, suspendedOriginAttempt);
            record.reopenAttemptSeq = 0;
            record.acceptedOpenAttemptSeq = 0;
            record.transportDetachNeeded = false;
            record.transportDetachResumeSuspended = false;
            record.transportDetachReleasePause = false;
            return finishTerminal(record, STATE_CONSUMED, "reopen_failure_empty", "");
        }
        if (!registerSuspendedAnchor(record)) {
            if (_root._webPanelPauseLease != undefined && !releaseTransportPauseLease()) {
                return holdReopenTerminalPauseRetry(record, reason);
            }
            markCompletedRecoveryProofs(record, attemptSeq);
            record.terminalFromOpenAttemptSeq = suspendedOriginAttempt;
            recordAuthorityClosedProof(record, suspendedOriginAttempt);
            record.transportDetachNeeded = false;
            record.transportDetachResumeSuspended = false;
            record.transportDetachReleasePause = false;
            return finishTerminal(record, STATE_EXPIRED, "suspended_anchor_lost", "");
        }
        record.state = STATE_SUSPENDED;
        record.suspendedFromOpenAttemptSeq = suspendedOriginAttempt;
        record.reason = isSafeReason(reason) ? reason : "panel_open_unavailable";
        record.closeLease = "";
        // 只有本次 reopen 已实际取得全局 webpanel lease 时才等 Host 的
        // visual close/unpause 证明；同步 disconnected/no-send 根本没有新 lease，
        // 应立即恢复互动资格。
        // timeout 表示已投递但结果未知；即使当前尚未观察到 lease，也必须等
        // exact Host close/unpause 或 socket detach 证明后才能再次互动。明确 rejection
        // 与同步 no-send 则只在真实观察到本次全局 lease 时等待释放。
        record.suspendPauseReleasePending = reason == "panel_open_timeout"
            || _root._webPanelPauseLease != undefined;
        record.reopenAttemptSeq = 0;
        record.acceptedOpenAttemptSeq = 0;
        record.transportDetachNeeded = false;
        record.transportDetachResumeSuspended = false;
        record.transportDetachReleasePause = false;
        record.authorityRevision++;
        invalidateLootLeases();
        markCompletedRecoveryProofs(record, attemptSeq);
        recordAuthorityClosedProof(record, suspendedOriginAttempt);
        return recordResponse(record, true, "");
    }

    /**
     * 空箱 / 锚点丢失的 reopen failure 必须先释放本次 Web pause 才能落终态。
     * release 暂时失败时冻结与 socket recovery 相同的 resume-suspended fence；
     * exact webPanelUnpause、socket close 或 causal query 后续只重试 release，不会
     * 重发 open、重滚物品或创建 legacy renderer。
     */
    private static function holdReopenTerminalPauseRetry(record:Object,
                                                          reason:String):Object {
        var isNewFence:Boolean = record.transportDetachNeeded !== true;
        record.transportDetachNeeded = true;
        record.transportDetachResumeSuspended = true;
        record.transportDetachReleasePause = true;
        record.transportDetachReason = isSafeReason(reason)
            ? reason : "panel_open_unavailable";
        record.state = STATE_PENDING;
        if (isNewFence) {
            record.authorityRevision++;
            invalidateLootLeases();
        }
        return failureFor(record, "commit_pending");
    }

    /** Host bind/watchdog 失败的 connected-path handoff；先持久 proof 再等 exact ACK。 */
    public static function handlePanelRecovery(params:Object):Object {
        if (!LootContainerValidation.validatePanelRecoveryEnvelope(params)) {
            return {handled:false, recovered:false, reason:"invalid_payload"};
        }
        var checked:Object = validateAnyIdentity(params);
        if (!checked.success) {
            return {handled:false, recovered:false, reason:"stale_identity"};
        }
        var record:Object = checked.record;
        var recoveryAttemptSeq:Number = Number(params.openAttemptSeq);
        if (recoveryAttemptSeq != Number(record.openAttemptSeq)) {
            return {handled:false, recovered:false, reason:"stale_open_attempt"};
        }
        // exact recovery 命令本身只能由已接纳该 binding 的 Host 生成，
        // 因此即使 panel_request callback 还未被 AS2 观察，也可安全删去更旧 proof。
        pruneCompletedRecoveryProofsBefore(record, recoveryAttemptSeq);
        var recoveryNonce:String = String(params.recoveryNonce);
        var recoveryReason:String = String(params.reason);
        if (hasExactConnectedAppliedProof(record, recoveryAttemptSeq, recoveryNonce)) {
            return {handled:true, recovered:true, duplicate:true,
                rendered:record.legacyRendererConfirmed === true,
                suspended:record.state == STATE_SUSPENDED, reason:record.reason};
        }
        if (isTerminalState(record.state) || record.state == STATE_SUSPENDED) {
            return {handled:false, recovered:false, reason:"no_active_authority"};
        }
        if (Number(record.recoveryPendingOpenAttemptSeq) == recoveryAttemptSeq) {
            if (record.recoveryPendingNonce !== recoveryNonce
                    || record.recoveryPendingReason !== recoveryReason) {
                return {handled:false, recovered:false, reason:"recovery_nonce_mismatch"};
            }
        } else {
            if (Number(record.recoveryPendingOpenAttemptSeq) > 0
                    || Number(record.recoveryAppliedOpenAttemptSeq) == recoveryAttemptSeq
                    || hasConnectedProofForAttempt(record, recoveryAttemptSeq)) {
                return {handled:false, recovered:false, reason:"recovery_nonce_mismatch"};
            }
            record.recoveryPendingOpenAttemptSeq = recoveryAttemptSeq;
            record.recoveryPendingNonce = recoveryNonce;
            record.recoveryPendingReason = recoveryReason;
        }
        // recovery 可以比 panel_request accepted callback 更早进入 AS2。此时只登记
        // pending，不先行宣称成功；ACK 到达后由 callback 继续同一 proof。
        if (Number(record.acceptedOpenAttemptSeq) != recoveryAttemptSeq) {
            return {handled:true, recovered:false, rendered:false,
                suspended:false, reason:"recovery_pending"};
        }
        var detachResult:Object = advancePendingPanelRecovery(record);
        var recovered:Boolean = hasExactConnectedAppliedProof(
            record, recoveryAttemptSeq, recoveryNonce);
        return {handled:true, recovered:recovered,
            rendered:record.legacyRendererConfirmed === true,
            suspended:record.state == STATE_SUSPENDED,
            reason:recovered ? record.reason : "recovery_pending"};
    }

    private static function advancePendingPanelRecovery(record:Object):Object {
        if (record == null || Number(record.recoveryPendingOpenAttemptSeq) <= 0
                || Number(record.recoveryPendingOpenAttemptSeq) != Number(record.openAttemptSeq)
                || Number(record.acceptedOpenAttemptSeq) != Number(record.openAttemptSeq)) {
            return {success:false, error:"recovery_pending"};
        }
        var reason:String = isSafeReason(String(record.recoveryPendingReason))
            ? String(record.recoveryPendingReason) : "web_open_failed";
        if (hasCurrentReopenAttempt(record)) {
            return startReopenTransportRecovery(record, reason, false);
        }
        record.transportDetachReason = reason;
        return reconcileTransportDetach(record.target);
    }

    private static function clearCurrentRecoveryProof(record:Object):Void {
        if (record == null) return;
        record.recoveryPendingOpenAttemptSeq = 0;
        record.recoveryPendingNonce = "";
        record.recoveryPendingReason = "";
        record.recoveryAppliedOpenAttemptSeq = 0;
        record.recoveryAppliedNonce = "";
        record.socketDetachObservedOpenAttemptSeq = 0;
        record.socketDetachAppliedOpenAttemptSeq = 0;
    }

    private static function recoveryProofKey(attemptSeq:Number):String {
        return "$" + String(attemptSeq);
    }

    private static function ensureRecoveryProofLedger(record:Object):Void {
        if (record.completedRecoveryProofs == undefined) record.completedRecoveryProofs = {};
        if (!(record.completedRecoveryProofOrder instanceof Array)) {
            record.completedRecoveryProofOrder = [];
        }
    }

    private static function completedRecoveryProof(record:Object, attemptSeq:Number):Object {
        if (record == null || attemptSeq <= 0) return null;
        ensureRecoveryProofLedger(record);
        return record.completedRecoveryProofs[recoveryProofKey(attemptSeq)];
    }

    private static function ensureCompletedRecoveryProof(record:Object,
                                                          attemptSeq:Number):Object {
        var existing:Object = completedRecoveryProof(record, attemptSeq);
        if (existing != null) return existing;
        ensureRecoveryProofLedger(record);
        // 未经 Host 确认的 proof 不可盲目淘汰。dispatch 在容量尽头前
        // 会 fail closed，直到 Host 的 exact proof query 将候选集收敛。
        if (record.completedRecoveryProofOrder.length >= MAX_RECOVERY_PROOFS) return null;
        var entry:Object = {
            attemptSeq:attemptSeq,
            connectedNonce:"",
            connectedApplied:false,
            socketApplied:false,
            authorityClosed:false
        };
        record.completedRecoveryProofs[recoveryProofKey(attemptSeq)] = entry;
        record.completedRecoveryProofOrder.push(attemptSeq);
        return entry;
    }

    private static function recordAuthorityClosedProof(record:Object,
                                                        attemptSeq:Number):Void {
        var entry:Object = ensureCompletedRecoveryProof(record, attemptSeq);
        if (entry != null) entry.authorityClosed = true;
    }

    private static function recordConnectedAppliedProof(record:Object, attemptSeq:Number,
                                                         nonce:String):Void {
        var entry:Object = ensureCompletedRecoveryProof(record, attemptSeq);
        if (entry == null) return;
        if (entry.connectedNonce == "" || entry.connectedNonce === nonce) {
            entry.connectedNonce = nonce;
            entry.connectedApplied = true;
        }
    }

    private static function recordSocketAppliedProof(record:Object,
                                                      attemptSeq:Number):Void {
        var entry:Object = ensureCompletedRecoveryProof(record, attemptSeq);
        if (entry != null) entry.socketApplied = true;
    }

    private static function markCompletedRecoveryProofs(record:Object,
                                                         attemptSeq:Number):Void {
        if (record == null || attemptSeq <= 0
                || Number(record.openAttemptSeq) != attemptSeq) return;
        if (Number(record.recoveryPendingOpenAttemptSeq) == attemptSeq) {
            record.recoveryAppliedOpenAttemptSeq = attemptSeq;
            record.recoveryAppliedNonce = String(record.recoveryPendingNonce);
            recordConnectedAppliedProof(
                record, attemptSeq, String(record.recoveryPendingNonce));
            record.recoveryPendingOpenAttemptSeq = 0;
            record.recoveryPendingNonce = "";
            record.recoveryPendingReason = "";
        }
        if (Number(record.socketDetachObservedOpenAttemptSeq) == attemptSeq) {
            record.socketDetachAppliedOpenAttemptSeq = attemptSeq;
            recordSocketAppliedProof(record, attemptSeq);
        }
    }

    private static function hasConnectedProofForAttempt(record:Object,
                                                         attemptSeq:Number):Boolean {
        var entry:Object = completedRecoveryProof(record, attemptSeq);
        return entry != null && entry.connectedApplied === true;
    }

    private static function hasExactConnectedAppliedProof(record:Object,
                                                           attemptSeq:Number,
                                                           nonce:String):Boolean {
        if (record == null) return false;
        if (Number(record.recoveryAppliedOpenAttemptSeq) == attemptSeq
                && record.recoveryAppliedNonce === nonce) return true;
        var entry:Object = completedRecoveryProof(record, attemptSeq);
        return entry != null && entry.connectedApplied === true
            && entry.connectedNonce === nonce;
    }

    private static function hasSocketAppliedProof(record:Object,
                                                   attemptSeq:Number):Boolean {
        if (record == null) return false;
        if (Number(record.socketDetachAppliedOpenAttemptSeq) == attemptSeq) return true;
        var entry:Object = completedRecoveryProof(record, attemptSeq);
        return entry != null && entry.socketApplied === true;
    }

    private static function pruneCompletedRecoveryProofsBefore(record:Object,
                                                                attemptSeq:Number):Void {
        if (record == null) return;
        ensureRecoveryProofLedger(record);
        var kept:Array = [];
        for (var i:Number = 0; i < record.completedRecoveryProofOrder.length; i++) {
            var candidate:Number = Number(record.completedRecoveryProofOrder[i]);
            if (candidate < attemptSeq) {
                delete record.completedRecoveryProofs[recoveryProofKey(candidate)];
            } else {
                kept.push(candidate);
            }
        }
        record.completedRecoveryProofOrder = kept;
    }

    private static function hasRecoveryProofCapacity(record:Object):Boolean {
        if (record == null) return false;
        ensureRecoveryProofLedger(record);
        return record.completedRecoveryProofOrder.length < MAX_RECOVERY_PROOFS;
    }

    private static function canRecordRecoveryProof(record:Object,
                                                    attemptSeq:Number):Boolean {
        return attemptSeq <= 0 || completedRecoveryProof(record, attemptSeq) != null
            || hasRecoveryProofCapacity(record);
    }

    /**
     * socket detach 的持久恢复入口。首次调用先冻结 transportDetachNeeded；之后只有 exact
     * journal 收敛、mandatory effects、same-object renderer 与本地 pause lease 四项均得到证明，
     * 才重新暴露 ACTIVE/terminal。失败阶段由后续 causal query 原地重试，绝不重滚奖励。
     */
    public static function reconcileSocketDetach(target:Object):Object {
        var record:Object = _legacyRecovery != null
            ? _legacyRecovery : (_active != null ? _active : _reservation);
        if (record != null && record.inventory != null
                && (target == null || record.target === target)
                && !isTerminalState(record.state)
                && Number(record.openAttemptSeq) > 0) {
            // 只有 ServerManager.onSocketClose 的专用入口能写 observed。
            // callback/recovery 共用的 reconcileTransportDetach 不具备这个能力。
            record.socketDetachObservedOpenAttemptSeq = Number(record.openAttemptSeq);
        }
        return reconcileTransportDetach(target);
    }

    public static function reconcileTransportDetach(target:Object):Object {
        if (_busy) return {success:false, readyForLegacy:false, error:"busy"};
        var record:Object = _legacyRecovery != null
            ? _legacyRecovery : (_active != null ? _active : _reservation);
        if (record == null || record.inventory == null) {
            return {success:false, readyForLegacy:false, error:"no_legacy_fallback"};
        }
        if (target != null && record.target !== target) {
            return {success:false, readyForLegacy:false, error:"recovery_target_mismatch"};
        }

        // ServerManager.onSocketClose 的生产顺序是先调用本入口，再逐个失败 pending
        // callback。当前 reopen 意图因此必须由 record 持久识别，先恢复 suspend，
        // 绝不能进入下面的 same-object legacy renderer。
        if (hasCurrentReopenAttempt(record)) {
            return startReopenTransportRecovery(
                record, "panel_open_unavailable", true);
        }

        // 已落权威 suspend 的 socket close 不是 renderer failure。只在 exact close 尚待
        // generic unpause 时释放这一次 loot pause；稳定 suspend 不碰后来面板的共享 lease。
        if (record.state == STATE_SUSPENDED) {
            return reconcileSuspendedTransportDetach(record);
        }
        if (isTerminalState(record.state)) {
            return {success:false, readyForLegacy:false,
                error:"terminal_state", state:record.state};
        }
        if (record.transportDetachNeeded !== true) {
            record.transportDetachNeeded = true;
            record.transportRendererDone = record.legacyRendererConfirmed === true;
            record.transportUnpauseDone = false;
            record.state = STATE_PENDING;
            record.authorityRevision++;
            invalidateLootLeases();
        }
        return continueTransportDetach(record);
    }

    private static function continueTransportDetach(record:Object):Object {
        if (record == null || record.transportDetachNeeded !== true) {
            return {success:false, readyForLegacy:false, error:"transport_detach_not_pending"};
        }

        // 不重放客户端写，只按冻结 journal 观察 exact before/after，前滚 source 或接受
        // 可证明 rollback。transport flag 在整个过程保持 record 为 LOOT_COMMIT_PENDING。
        if (record.pendingCommit != null) {
            var pending:Object = record.pendingCommit;
            var settled:Object = null;
            _busy = true;
            try {
                settled = LootClaimCommitCoordinator.settleForSceneExpiry(pending);
            } finally {
                _busy = false;
            }
            if (settled != null && settled.success) {
                finalizeClaim(record, pending, settled);
            } else if (settled != null && settled.rolledBack === true) {
                record.pendingCommit = null;
                record.state = STATE_PENDING;
            } else {
                record.state = STATE_PENDING;
                return {success:false, readyForLegacy:false,
                    error:"claim_commit_pending", state:STATE_PENDING};
            }
        }
        if (record.postCommitEffects != null && !retryPostCommitEffects(record)) {
            return {success:false, readyForLegacy:false,
                error:"claim_commit_pending", state:STATE_PENDING};
        }
        if (record.pendingCommit != null || record.postCommitEffects != null) {
            return {success:false, readyForLegacy:false,
                error:"claim_commit_pending", state:STATE_PENDING};
        }

        // reopen transport recovery 可复用上面的 exact journal/effect 收敛，但最终
        // handoff 是 first-class SUSPENDED/terminal，不是旧 AS2 renderer。connected
        // watchdog 等 Host exact close 后 generic unpause；socket close 则在本栈立即
        // 释放当前 pause lease，避免断线后永久暂停。
        if (record.transportDetachResumeSuspended === true) {
            var reopenAttemptSeq:Number = Number(record.reopenAttemptSeq);
            var releasePauseNow:Boolean = record.transportDetachReleasePause === true;
            var reopenReason:String = isSafeReason(String(record.transportDetachReason))
                ? String(record.transportDetachReason) : "panel_open_unavailable";
            // socket detach 已是本次 reopen pause lease 的最终因果证明。必须在
            // suspend anchor 恢复之前先释放：若 anchor 同时丢失，后续会落
            // EXPIRED 并清掉 _active，届时已没有可重试的 record 能补放租约。
            // 释放失败则保留整个 transport fence，供后续 causal query/socket
            // retry 只继续这一阶段。
            if (releasePauseNow && !releaseTransportPauseLease()) {
                return {success:false, readyForLegacy:false, suspendedNoRenderer:true,
                    pauseReleaseRequired:true, error:"suspend_pause_release_failed",
                    state:STATE_PENDING};
            }
            record.state = STATE_ACTIVE;
            var restored:Object = restoreSuspendedAfterReopenFailure(
                record, reopenReason, reopenAttemptSeq);
            if (restored == null || restored.success !== true) {
                return {success:false, readyForLegacy:false,
                    suspendedNoRenderer:true,
                    error:restored == null ? "suspend_unavailable" : restored.error,
                    state:record.state};
            }
            if (isTerminalState(record.state)) {
                return {success:true, readyForLegacy:false, suspendedNoRenderer:true,
                    pauseReleaseRequired:false, state:record.state};
            }
            return {success:true, readyForLegacy:false, suspendedNoRenderer:true,
                pauseReleaseRequired:record.suspendPauseReleasePending === true,
                pauseReleased:releasePauseNow, state:STATE_SUSPENDED};
        }

        if (!prepareTransportLegacyRecovery(record)) {
            return {success:false, readyForLegacy:false,
                error:"legacy_fallback_failed", state:STATE_PENDING};
        }

        if (record.transportRendererDone !== true) {
            var rendered:Boolean = false;
            if (record.legacyRendererConfirmed === true) {
                rendered = true;
            } else if (_root.地图元件 != undefined
                    && typeof _root.地图元件.显示Web战利品旧界面 == "function") {
                try {
                    injectTransportHandoffFailure("renderer");
                    rendered = _root.地图元件.显示Web战利品旧界面(
                        legacyRendererProjection(record, false)) === true;
                } catch (rendererError) {
                    rendered = false;
                }
            }
            if (!rendered) {
                record.state = STATE_PENDING;
                return {success:false, readyForLegacy:false,
                    error:"claim_commit_pending", state:STATE_PENDING};
            }
            record.legacyRendererConfirmed = true;
            record.transportRendererDone = true;
        }

        if (record.transportUnpauseDone !== true) {
            if (!releaseTransportPauseLease()) {
                record.state = STATE_PENDING;
                return {success:false, readyForLegacy:false,
                    error:"claim_commit_pending", state:STATE_PENDING};
            }
            record.transportUnpauseDone = true;
        }

        record.transportDetachNeeded = false;
        record.state = STATE_ACTIVE;
        record.authorityRevision++;
        invalidateLootLeases();
        var completedAttemptSeq:Number = Number(record.openAttemptSeq);
        markCompletedRecoveryProofs(record, completedAttemptSeq);

        // renderer 内可能同步观察到最后一件已被领取；transport/pause 证明完成后再落 CONSUMED。
        if (remainingCount(record) <= 0) {
            record.terminalFromOpenAttemptSeq = completedAttemptSeq;
            recordAuthorityClosedProof(record, completedAttemptSeq);
            var terminal:Object = finishTerminal(record, STATE_CONSUMED, "legacy_consumed", "");
            return {success:terminal.success, readyForLegacy:terminal.success,
                state:record.state, terminal:terminal};
        }
        return {success:true, readyForLegacy:true, state:record.state};
    }

    /**
     * reopen 的 transport/mount 恢复与初次 open 的 legacy handoff 分流。先冻结 mode，
     * 再复用 continueTransportDetach 的 pending journal 收敛；重复 socket close 可把
     * connected recovery 升级成 releasePauseNow，但绝不反向降级。
     */
    private static function startReopenTransportRecovery(record:Object, reason:String,
                                                          releasePauseNow:Boolean):Object {
        if (!hasCurrentReopenAttempt(record)) {
            return {success:false, readyForLegacy:false, error:"stale_open_attempt"};
        }
        if (record.transportDetachNeeded !== true) {
            record.transportDetachNeeded = true;
            record.transportDetachResumeSuspended = true;
            record.transportDetachReleasePause = releasePauseNow === true;
            record.transportDetachReason = isSafeReason(reason)
                ? reason : "panel_open_unavailable";
            record.state = STATE_PENDING;
            record.authorityRevision++;
            invalidateLootLeases();
        } else if (record.transportDetachResumeSuspended !== true) {
            return {success:false, readyForLegacy:false,
                error:"claim_commit_pending", state:STATE_PENDING};
        } else if (releasePauseNow === true) {
            record.transportDetachReleasePause = true;
        }
        return continueTransportDetach(record);
    }

    private static function hasCurrentReopenAttempt(record:Object):Boolean {
        var attemptSeq:Number = record == null ? 0 : Number(record.openAttemptSeq);
        return record != null && !isTerminalState(record.state)
            && (record.state == STATE_ACTIVE || record.state == STATE_PENDING)
            && record.legacyRecovery !== true && record.openAttemptWasReopen === true
            && attemptSeq > 0 && Number(record.reopenAttemptSeq) == attemptSeq;
    }

    private static function prepareTransportLegacyRecovery(record:Object):Boolean {
        if (record == null || record.inventory == null
                || record.transportDetachNeeded !== true
                || record.pendingCommit != null || record.postCommitEffects != null
                || isTerminalState(record.state)) return false;
        if ((_active != null && _active !== record)
                || (_legacyRecovery != null && _legacyRecovery !== record)) return false;
        record.state = STATE_PENDING;
        record.reason = typeof record.transportDetachReason == "string"
                && isSafeReason(String(record.transportDetachReason))
            ? String(record.transportDetachReason) : "transport_detach";
        record.legacyRecovery = true;
        _active = record;
        if (_reservation === record) _reservation = null;
        _legacyRecovery = record;
        invalidateLootLeases();
        return true;
    }

    private static function releaseTransportPauseLease():Boolean {
        try {
            injectTransportHandoffFailure("unpause");
            if (_root._webPanelPauseLease != undefined) {
                org.flashNight.arki.pause.PauseManager.releaseLease(_root._webPanelPauseLease);
                _root._webPanelPauseLease = undefined;
            }
        } catch (unpauseError) {
            return false;
        }
        return _root._webPanelPauseLease == undefined;
    }

    /** 正常 webPanelUnpause 的 exact suspend-close 交接；handled=true 时调用方必须直接返回。 */
    public static function releaseSuspendedPauseForClose():Object {
        var record:Object = _active;
        // reopen failure 若要落 CONSUMED/EXPIRED，pause release 是终态提交前的
        // mandatory stage。它不是普通 SUSPENDED，但同一个 exact Host unpause
        // 仍是最直接的因果重试入口。
        if (record != null && record.state == STATE_PENDING
                && record.transportDetachNeeded === true
                && record.transportDetachResumeSuspended === true
                && record.transportDetachReleasePause === true) {
            var continued:Object = continueTransportDetach(record);
            return {
                handled:true,
                success:continued != null && continued.success === true,
                reason:continued != null && continued.success === true
                    ? "suspend_pause_released" : "suspend_pause_release_failed"
            };
        }
        if (record == null || record.state != STATE_SUSPENDED
                || record.suspendPauseReleasePending !== true) {
            return {handled:false, success:false, reason:"no_suspend_pause_release"};
        }
        if (!releaseTransportPauseLease()) {
            return {handled:true, success:false, reason:"suspend_pause_release_failed"};
        }
        record.suspendPauseReleasePending = false;
        return {handled:true, success:true, reason:"suspend_pause_released"};
    }

    private static function reconcileSuspendedTransportDetach(record:Object):Object {
        var releaseRequired:Boolean = record.suspendPauseReleasePending === true;
        if (releaseRequired) {
            var released:Object = releaseSuspendedPauseForClose();
            if (released == null || released.success !== true) {
                return {success:false, readyForLegacy:false, suspendedNoRenderer:true,
                    pauseReleaseRequired:true, error:"suspend_pause_release_failed",
                    state:STATE_SUSPENDED};
            }
        }
        markCompletedRecoveryProofs(record, Number(record.openAttemptSeq));
        return {success:true, readyForLegacy:false, suspendedNoRenderer:true,
            pauseReleaseRequired:releaseRequired,
            pauseReleased:releaseRequired && _root._webPanelPauseLease == undefined,
            state:STATE_SUSPENDED};
    }

    public static function consumeLegacyFallback(target:Object):Object {
        // Suspend 是用户完成的一次权威 close，不是 transport failure；generic unpause、
        // navigation close 与 socket callback 都不得借此弹回旧 AS2 资源箱 UI。
        if (_active != null && _active.state == STATE_SUSPENDED) {
            return localFailure("loot_suspended");
        }
        if (_legacyRecovery != null) {
            if (target != null && _legacyRecovery.target !== target) return localFailure("recovery_target_mismatch");
            // 最后一格 source 写可能已完成，但 claim journal / mandatory effects 仍待
            // causal retry；此时绝不能把空 inventory 再暴露给 renderer。
            if (_legacyRecovery.pendingCommit != null
                    || _legacyRecovery.postCommitEffects != null
                    || _legacyRecovery.transportDetachNeeded === true) {
                return localFailure("claim_commit_pending");
            }
            return legacyRendererProjection(_legacyRecovery, true);
        }
        var record:Object = _active != null ? _active : _reservation;
        // legacy renderer 不是事务 reconcile 入口；只有同 op 或 causal query 可以推进 journal。
        if (record != null && (record.pendingCommit != null
                || record.postCommitEffects != null
                || record.transportDetachNeeded === true)) return localFailure("claim_commit_pending");
        if (record == null || record.inventory == null) return localFailure("no_legacy_fallback");
        if (target != null && record.target !== target) return localFailure("recovery_target_mismatch");
        moveToLegacyRecovery(record, "legacy_fallback");
        if (_legacyRecovery == null) return localFailure("legacy_fallback_failed");
        return legacyRendererProjection(_legacyRecovery, false);
    }

    /** 地图 renderer 成功返回后登记可见性证明；重复确认只接受同一 recovery target。 */
    public static function confirmLegacyRenderer(target:Object):Boolean {
        var record:Object = _legacyRecovery;
        if (record == null || (target != null && record.target !== target)) return false;
        record.legacyRendererConfirmed = true;
        if (record.transportDetachNeeded === true) record.transportRendererDone = true;
        return true;
    }

    /**
     * 旧资源箱外观的唯一领取适配器。UI 不得直接写 transient inventory；本入口先用
     * causal query 收敛可能残留的 claim journal/effects，再从新鲜权威快照铸造现有
     * loot -> 背包 claim。最后一格只在 claim 完整提交后显式落 CONSUMED。
     */
    public static function claimLegacyRecoverySlot(inventory:Object, slot:Number):Object {
        var record:Object = _legacyRecovery;
        if (record == null) return localFailure("no_legacy_recovery");
        if (record.inventory !== inventory) return localFailure("recovery_inventory_mismatch");
        if (record.legacyRendererConfirmed !== true) {
            return localFailure("legacy_renderer_unconfirmed");
        }
        if (!isWhole(slot) || slot < 0 || slot >= record.inventory.capacity) {
            return failureFor(record, "invalid_slot");
        }

        var queryParams:Object = {
            v:1,
            chestSessionId:record.chestSessionId,
            lootContainerId:record.lootContainerId,
            containerEpoch:record.containerEpoch
        };
        var current:Object = execute("query", queryParams);
        if (current == null || current.success !== true) return current;
        if (current.state != STATE_ACTIVE) return failureFor(record, "terminal_state");
        if (!(current.snapshots instanceof Array)) {
            return failureFor(record, "authority_unavailable");
        }

        var lootSnapshot:Object = null;
        for (var i:Number = 0; i < current.snapshots.length; i++) {
            if (current.snapshots[i].containerId === record.lootContainerId) {
                lootSnapshot = current.snapshots[i];
                break;
            }
        }
        if (lootSnapshot == null || !(lootSnapshot.slots instanceof Array)) {
            return failureFor(record, "authority_unavailable");
        }
        var sourceRow:Object = null;
        for (i = 0; i < lootSnapshot.slots.length; i++) {
            if (Number(lootSnapshot.slots[i].physicalSlot) == slot) {
                sourceRow = lootSnapshot.slots[i];
                break;
            }
        }
        if (sourceRow == null || sourceRow.occupied !== true) {
            var emptyCompletion:Object = completeLegacyRecoveryIfEmpty();
            if (emptyCompletion != null && emptyCompletion.released === true) {
                return emptyCompletion;
            }
            return failureFor(record, "stale_state");
        }

        _legacyClaimSeq++;
        var operationId:String = "legacy." + String(record.containerEpoch)
            + "." + String(_legacyClaimSeq);
        var claim:Object = execute("claim", {
            v:1,
            chestSessionId:record.chestSessionId,
            lootContainerId:record.lootContainerId,
            containerEpoch:record.containerEpoch,
            expectedAuthorityRevision:current.authorityRevision,
            operationId:operationId,
            direction:"loot_to_player",
            targetContainerId:"背包",
            source:{
                containerId:lootSnapshot.containerId,
                slot:sourceRow.physicalSlot,
                expectedLease:sourceRow.slotLease,
                expectedContainerVersion:lootSnapshot.containerVersion
            }
        });
        // 同步故障可能已留下可判定 journal；立即用 query 做一次 causal reconcile，
        // 仍不确定则保持 pending，绝不另造 operation 或退回旧直写路径。
        if (claim != null && claim.success !== true && claim.error == "commit_pending") {
            claim = execute("query", queryParams);
        }

        var completion:Object = completeLegacyRecoveryIfEmpty();
        if (completion != null && completion.released === true) return completion;
        return claim;
    }

    /** generic webPanelUnpause 的本地栅栏；loot handoff 未证明时不得提前释放游戏暂停。 */
    public static function hasPendingTransportDetach():Boolean {
        var record:Object = _legacyRecovery != null
            ? _legacyRecovery : (_active != null ? _active : _reservation);
        return record != null && record.transportDetachNeeded === true;
    }

    /** recovery 存在时任何新网格箱都必须停止；原 renderer 可复取同一 inventory 参数。 */
    public static function guardAnyGridFixture(target:Object):Object {
        if (_active != null && _active.state == STATE_SUSPENDED) {
            if (_active.target === target) {
                return {handled:true, recovery:false, reopen:true,
                    reason:"loot_suspended", state:STATE_SUSPENDED,
                    chestSessionId:_active.chestSessionId,
                    lootContainerId:_active.lootContainerId,
                    containerEpoch:_active.containerEpoch};
            }
            if (hasExactGridShape(target)) {
                return {handled:true, recovery:false, reopen:false,
                    reason:"loot_flow_busy", state:STATE_SUSPENDED};
            }
            return {handled:false, recovery:false, reason:"not_grid_fixture"};
        }
        if (_legacyRecovery == null) return {handled:false, recovery:false, reason:"no_recovery"};
        if (_legacyRecovery.transportDetachNeeded === true) {
            return {handled:true, recovery:true, reason:"claim_commit_pending"};
        }
        if (remainingCount(_legacyRecovery) <= 0) {
            var completion:Object = completeLegacyRecoveryIfEmpty();
            if (completion == null || completion.released !== true) {
                // 最后一格写入已经落地但 mandatory effects 尚未收敛时，仍由原
                // recovery 占住所有网格箱；否则普通旧箱可从 handled:false 绕过权威门。
                return {handled:true, recovery:false, reason:"claim_commit_pending",
                    state:_legacyRecovery == null ? STATE_PENDING : _legacyRecovery.state};
            }
            return {handled:false, recovery:false, reason:"recovery_consumed"};
        }
        var sameRecoveryTarget:Boolean = _legacyRecovery.target === target;
        if (!sameRecoveryTarget && !hasExactGridShape(target)) {
            return {handled:false, recovery:false, reason:"not_grid_fixture"};
        }
        var projection:Object = legacyRendererProjection(_legacyRecovery, true);
        projection.handled = true;
        projection.recovery = true;
        projection.reason = _legacyRecovery.reason;
        projection.requestedTargetMatches = sameRecoveryTarget;
        return projection;
    }

    /** 旧 UI 关闭/刷新时调用；非空只隐藏 UI，不释放唯一容器强引用。 */
    public static function completeLegacyRecoveryIfEmpty():Object {
        if (_legacyRecovery == null) return {success:true, released:false, reason:"no_recovery"};
        var record:Object = _legacyRecovery;
        // destination/source 事务可能已进入 exact journal，但 source 槽已经为空。旧 UI 此时
        // 没有图标可再次触发 query；completion 必须只续跑同一 pending operation，绝不另造
        // operationId 或重放 begin/write。query 后必须重新读 remaining，兼容安全回滚恢复 source。
        if (record.pendingCommit != null) {
            var reconciled:Object = execute("query", {
                v:1,
                chestSessionId:record.chestSessionId,
                lootContainerId:record.lootContainerId,
                containerEpoch:record.containerEpoch
            });
            if (_legacyRecovery !== record && isTerminalState(String(record.state))) {
                return legacyTerminalCompletion(record);
            }
            if (record.pendingCommit != null) {
                if (reconciled == null || reconciled.success === true) {
                    reconciled = failureFor(record, "commit_pending");
                }
                reconciled.released = false;
                reconciled.reason = "recovery_pending";
                return reconciled;
            }
        }
        if (remainingCount(record) > 0) {
            return {success:true, released:false, reason:"recovery_nonempty"};
        }
        // claim 的 source/destination 写可能已完成，而 dirty/cache/event mandatory effects
        // 仍处于可重试 journal。空 UI 已没有可再次点击的物品，因此 completion 本身必须
        // 推进一步；只重放 effects，绝不重放 claim 写事务。
        if (record.postCommitEffects != null && !retryPostCommitEffects(record)) {
            var pendingEffects:Object = failureFor(record, "commit_pending");
            pendingEffects.released = false;
            pendingEffects.reason = "recovery_pending";
            return pendingEffects;
        }
        // 测试兼容 observer 可能在 post-effect 事件栈内已完成 terminal；避免外层二次提交。
        if (_legacyRecovery !== record && isTerminalState(String(record.state))) {
            return legacyTerminalCompletion(record);
        }
        var result:Object = finishTerminal(record, STATE_CONSUMED, "legacy_consumed", "");
        if (result == null || result.success !== true) {
            if (result == null) result = failureFor(record, "commit_pending");
            result.released = false;
            result.reason = "recovery_pending";
            return result;
        }
        result.released = true;
        result.reason = "recovery_consumed";
        return result;
    }

    private static function legacyTerminalCompletion(record:Object):Object {
        var terminalResult:Object = recordResponse(record, true, "");
        terminalResult.released = record != null && record.state == STATE_CONSUMED;
        terminalResult.reason = terminalResult.released
            ? "recovery_consumed" : "recovery_pending";
        return terminalResult;
    }

    /**
     * 旧 UI 创建布局后会给同一 inventory 安装生命周期 dispatcher；此时订阅移除/数量变化，
     * 让最后一个物品被拿走的同步事件直接提交 CONSUMED，而不是等场景清理误记 EXPIRED。
     */
    public static function attachLegacyRecoveryObserver():Object {
        var record:Object = _legacyRecovery;
        if (record == null || !(record.inventory instanceof ArrayInventory)) {
            return localFailure("no_legacy_recovery");
        }
        var dispatcher:Object = record.inventory.getDispatcher();
        if (dispatcher == null || typeof dispatcher.subscribe != "function") {
            return localFailure("legacy_dispatcher_unavailable");
        }
        if (_legacyObserverRecord === record && _legacyObserverDispatcher === dispatcher
                && _legacyObserverCallback != null) {
            return {success:true, duplicate:true};
        }

        detachLegacyRecoveryObserver(null);
        var inventory:ArrayInventory = record.inventory;
        var callback:Function = function(changedInventory:Object, key:String):Void {
            org.flashNight.arki.item.LootContainerService.handleLegacyRecoveryMutation(
                record, changedInventory);
        };
        var removedSubscribed:Boolean = false;
        var valueSubscribed:Boolean = false;
        try {
            removedSubscribed = dispatcher.subscribe("ItemRemoved", callback, null);
            valueSubscribed = dispatcher.subscribe("ItemValueChanged", callback, null);
        } catch (subscribeError) {
            removedSubscribed = false;
            valueSubscribed = false;
        }
        if (!removedSubscribed || !valueSubscribed) {
            try {
                if (removedSubscribed) dispatcher.unsubscribe("ItemRemoved", callback, null);
                if (valueSubscribed) dispatcher.unsubscribe("ItemValueChanged", callback, null);
            } catch (unsubscribeError) {
            }
            return localFailure("legacy_observer_subscribe_failed");
        }
        _legacyObserverRecord = record;
        _legacyObserverDispatcher = dispatcher;
        _legacyObserverCallback = callback;
        return {success:true, duplicate:false};
    }

    /** 场景卸载是唯一允许非空 recovery 无 UI 接管而过期的生命周期边界。 */
    public static function expireScene(reason:String):Object {
        var safeReason:String = isSafeReason(reason) ? reason : "scene_cleanup";
        var record:Object = _active != null ? _active : _reservation;
        var result:Object;
        if (record != null && record.transportDetachNeeded === true) {
            // scene cleanup 不是 renderer/pause handoff 的 causal continuation；transport detach
            // 必须只由原 lifecycle 调用或重连 lootQuery 续跑，禁止同栈显示后立刻 EXPIRED。
            return failureFor(record, "commit_pending");
        }
        if (record != null && record.pendingCommit != null) {
            var pending:Object = record.pendingCommit;
            _busy = true;
            var settled:Object = null;
            try {
                settled = LootClaimCommitCoordinator.settleForSceneExpiry(pending);
            } finally {
                _busy = false;
            }
            if (settled != null && settled.success) {
                finalizeClaim(record, pending, settled);
                record = _active != null ? _active : _reservation;
            } else if (settled != null && settled.rolledBack === true) {
                record.pendingCommit = null;
                record.state = STATE_ACTIVE;
            } else {
                record.state = STATE_PENDING;
                return failureFor(record, "commit_pending");
            }
        }
        if (record != null && record.postCommitEffects != null
                && !retryPostCommitEffects(record)) {
            return failureFor(record, "commit_pending");
        }
        if (record != null) result = finishTerminal(record, STATE_EXPIRED, safeReason, "");
        else result = {success:true, state:STATE_EXPIRED, reason:safeReason};
        detachLegacyRecoveryObserver(null);
        _legacyRecovery = null;
        return result;
    }

    private static function executeSnapshot(params:Object):Object {
        var checked:Object = validateActiveIdentity(params);
        if (!checked.success) return checked.response;
        var windows:Object = validateWindows(params, checked.record);
        if (!windows.success) return failureFor(checked.record, windows.error);
        var response:Object = recordResponse(checked.record, true, "");
        try {
            response.snapshots = buildFreshSnapshots(
                checked.record, windows.loot, windows.backpack);
        } catch (snapshotError) {
            trace("[LootContainerService] snapshot failed: " + snapshotError);
            response.snapshots = null;
        }
        if (response.snapshots == null) return failureFor(checked.record, "authority_unavailable");
        return response;
    }

    private static function executeTooltip(params:Object):Object {
        var checked:Object = validateActiveIdentity(params);
        if (!checked.success) return checked.response;
        var record:Object = checked.record;
        if (!validExpectedAuthority(params, record)) return failureFor(record, "stale_state");
        var source:Object = validateTooltipSource(record, params.source);
        if (!source.success) return failureFor(record, source.error);
        var tooltip:Object = null;
        try {
            tooltip = buildTooltip(source.item);
        } catch (tooltipError) {
            trace("[LootContainerService] tooltip failed: " + tooltipError);
            tooltip = null;
        }
        if (tooltip == null) return failureFor(record, "tooltip_failed");
        var response:Object = recordResponse(record, true, "");
        response.tooltip = tooltip;
        return response;
    }

    private static function executeClaim(params:Object):Object {
        var checked:Object = validateAnyIdentity(params);
        if (!checked.success) return checked.response;
        var record:Object = checked.record;
        if (record.transportDetachNeeded === true) return failureFor(record, "commit_pending");
        var operationId:String = validOperationId(params.operationId) ? String(params.operationId) : "";
        if (operationId == "") return failureFor(record, "invalid_operation_id");
        var fingerprint:String = claimFingerprint(params);
        var prior:Object = record.operations[operationKey(operationId)];
        if (prior != undefined) return duplicateClaim(record, prior, fingerprint);
        if (record.postCommitEffects != null) return failureFor(record, "commit_pending");
        if (record.pendingCommit != null) {
            var pending:Object = record.pendingCommit;
            if (pending.operationId !== operationId || pending.fingerprint !== fingerprint) {
                return failureFor(record, "operation_conflict");
            }
            if (!validExpectedAuthority(params, record)) return failureFor(record, "stale_state");
            _busy = true;
            var resumed:Object = null;
            try {
                resumed = LootClaimCommitCoordinator.resume(pending);
            } finally {
                _busy = false;
            }
            if (resumed == null || !resumed.success) {
                record.state = STATE_PENDING;
                return failureFor(record, resumed == null ? "commit_pending" : resumed.error);
            }
            return finalizeClaim(record, pending, resumed);
        }
        if (record.state != STATE_ACTIVE) return failureFor(record, "terminal_state");
        if (!validExpectedAuthority(params, record)) return failureFor(record, "stale_state");
        if (params.direction !== "loot_to_player" || params.targetContainerId !== "背包") {
            return failureFor(record, "transfer_forbidden");
        }
        var source:Object = validateLootSource(record, params.source, true);
        if (!source.success) return failureFor(record, source.error);

        _busy = true;
        record.state = STATE_PENDING;
        record.pendingCommit = {
            operationId:operationId,
            fingerprint:fingerprint,
            sourceSlot:source.slot,
            sourceItem:source.item,
            sourceVersion:source.inventory.getMutationRevision(),
            kind:""
        };
        var committed:Object = null;
        try {
            var kind:String = classifyItem(source.item);
            record.pendingCommit.kind = kind;
            committed = LootClaimCommitCoordinator.begin(record.pendingCommit, source, kind);
        } catch (caughtCommitError) {
            trace("[LootContainerService] claim commit exception: " + caughtCommitError);
            committed = LootClaimCommitCoordinator.reconcileUnexpectedFailure(
                record.pendingCommit);
        } finally {
            _busy = false;
        }
        if (committed == null || !committed.success) {
            if (committed != null && committed.pending === true) {
                record.state = STATE_PENDING;
                return failureFor(record, "commit_pending");
            }
            record.pendingCommit = null;
            record.state = STATE_ACTIVE;
            return failureFor(record, committed == null ? "commit_failed" : committed.error);
        }
        return finalizeClaim(record, record.pendingCommit, committed);
    }

    private static function finalizeClaim(record:Object, pending:Object, committed:Object):Object {
        var operationId:String = String(pending.operationId);
        var fingerprint:String = String(pending.fingerprint);
        var source:Object = {
            inventory:pending.sourceInventory,
            slot:Number(pending.sourceSlot),
            item:pending.sourceItem
        };
        // 先把成功操作写入幂等 journal，再释放 busy；后续缓存/事件/投影均为可恢复副作用。
        record.pendingCommit = null;
        record.state = STATE_PENDING;
        record.authorityRevision++;
        record.lastAppliedOperationId = operationId;
        record.operations[operationKey(operationId)] = {
            kind:"claim",
            fingerprint:fingerprint,
            authorityRevision:record.authorityRevision
        };
        record.postCommitEffects = {
            operationId:operationId,
            fingerprint:fingerprint,
            committed:committed,
            source:source,
            dirtyDone:false,
            lootCacheDone:false,
            destinationCacheDone:committed.destinationSlot == undefined,
            sourceEventPublished:false,
            destinationEventPublished:committed.destinationInventory == undefined,
            collectionEventPublished:committed.collection == undefined,
            levelEventPublished:committed.postCommitKind != "experience"
        };
        var effectsCompleted:Boolean = retryPostCommitEffects(record);
        if (!effectsCompleted) return failureFor(record, "commit_pending");

        var response:Object = recordResponse(record, true, "");
        try {
            response.snapshots = buildFreshSnapshots(record, null, null);
        } catch (snapshotError) {
            trace("[LootContainerService] post-commit snapshot failed: " + snapshotError);
            response.snapshots = null;
        }
        // 写已落地但投影不可得时必须回 error，让 Web 走 query reconcile；
        // success:true + [] 会违反 active response 必含 loot/backpack 双快照的冻结 union。
        if (response.snapshots == null) return failureFor(record, "authority_unavailable");
        return response;
    }

    /**
     * operation journal 已写后的 mandatory effects 恢复门。dirty 最先执行；两层 cache
     * invalidation 分步幂等。全部成功前 record 保持 LOOT_COMMIT_PENDING，只有同 op 或
     * causal query 可调用本函数重试。事件按子事件先标记后派发，监听器抛错也不重放。
     */
    private static function completePostCommitEffects(record:Object):Boolean {
        var effects:Object = record == null ? null : record.postCommitEffects;
        if (effects == null) return true;
        var prior:Object = record.operations[operationKey(String(effects.operationId))];
        if (prior == undefined || prior.kind != "claim"
                || prior.fingerprint !== effects.fingerprint
                || record.lastAppliedOperationId !== effects.operationId) return false;

        if (!effects.dirtyDone) {
            try {
                injectPostCommitFailure("dirty");
                if (!markDirtyVerified()) return false;
                effects.dirtyDone = true;
            } catch (dirtyError) {
                trace("[LootContainerService] post-commit dirty pending");
                return false;
            }
        }
        if (!effects.lootCacheDone) {
            try {
                injectPostCommitFailure("loot_cache");
                invalidateLootLeases();
                effects.lootCacheDone = true;
            } catch (lootCacheError) {
                trace("[LootContainerService] post-commit loot cache pending");
                return false;
            }
        }
        if (!effects.destinationCacheDone) {
            try {
                injectPostCommitFailure("destination_cache");
                InventoryPanelService.invalidateExternalSlot(
                    "背包", Number(effects.committed.destinationSlot));
                effects.destinationCacheDone = true;
            } catch (destinationCacheError) {
                trace("[LootContainerService] post-commit destination cache pending");
                return false;
            }
        }

        record.postCommitEffects = null;
        record.state = record.transportDetachNeeded === true ? STATE_PENDING : STATE_ACTIVE;
        publishPostCommitEvents(effects);
        return true;
    }

    private static function retryPostCommitEffects(record:Object):Boolean {
        _busy = true;
        var completed:Boolean = false;
        try {
            completed = completePostCommitEffects(record);
        } finally {
            _busy = false;
        }
        return completed;
    }

    private static function executeClose(params:Object):Object {
        var checked:Object = validateAnyIdentity(params);
        if (!checked.success) return checked.response;
        var record:Object = checked.record;
        if (record.pendingCommit != null || record.postCommitEffects != null
                || record.transportDetachNeeded === true) {
            return failureFor(record, "commit_pending");
        }
        var operationId:String = validOperationId(params.operationId) ? String(params.operationId) : "";
        if (operationId == "") return failureFor(record, "invalid_operation_id");
        if (typeof params.abandon != "boolean") return failureFor(record, "invalid_payload");
        var fingerprint:String = closeFingerprint(params);

        var prior:Object = record.operations == undefined
            ? undefined : record.operations[operationKey(operationId)];
        if (prior != undefined) return duplicateClose(record, prior, fingerprint, operationId);
        if (record.state != STATE_ACTIVE) return failureFor(record, "terminal_state");
        if (!validExpectedAuthority(params, record)) return failureFor(record, "stale_state");
        if (typeof params.closeLease != "string" || params.closeLease !== record.closeLease) {
            return failureFor(record, "stale_close_lease");
        }
        var remaining:Number = remainingCount(record);
        var closingAttemptSeq:Number = Number(record.openAttemptSeq);
        if (!canRecordRecoveryProof(record, closingAttemptSeq)) {
            return failureFor(record, "recovery_history_full");
        }

        if (remaining > 0 && params.abandon !== true) {
            // anchor 是 suspend 的可恢复性前置条件；注册失败时 authority/op journal 零变化。
            if (!registerSuspendedAnchor(record)) {
                return failureFor(record, "suspend_unavailable");
            }
            record.operations[operationKey(operationId)] = {
                kind:"close", fingerprint:fingerprint, resultState:STATE_SUSPENDED
            };
            record.lastAppliedOperationId = operationId;
            record.state = STATE_SUSPENDED;
            record.reason = "user_suspended";
            record.closeLease = "";
            record.suspendPauseReleasePending = true;
            record.suspendedFromOpenAttemptSeq = closingAttemptSeq;
            recordAuthorityClosedProof(record, closingAttemptSeq);
            clearCurrentRecoveryProof(record);
            record.openAttemptWasReopen = false;
            record.reopenBaseSuspendedAttemptSeq = 0;
            record.reopenAttemptSeq = 0;
            record.acceptedOpenAttemptSeq = 0;
            record.transportDetachResumeSuspended = false;
            record.transportDetachReleasePause = false;
            record.authorityRevision++;
            record.operations[operationKey(operationId)].authorityRevision =
                record.authorityRevision;
            invalidateLootLeases();
            var suspended:Object = recordResponse(record, true, "");
            suspended.success = true;
            suspended.error = "";
            return suspended;
        }

        var terminalState:String = remaining <= 0 ? STATE_CONSUMED : STATE_ABANDONED;
        record.operations[operationKey(operationId)] = {
            kind:"close", fingerprint:fingerprint, resultState:terminalState
        };
        record.lastAppliedOperationId = operationId;
        var terminalReason:String = remaining <= 0 ? "empty_close" : "explicit_abandon";
        record.terminalFromOpenAttemptSeq = closingAttemptSeq;
        recordAuthorityClosedProof(record, closingAttemptSeq);
        clearCurrentRecoveryProof(record);
        record.openAttemptWasReopen = false;
        record.reopenBaseSuspendedAttemptSeq = 0;
        record.reopenAttemptSeq = 0;
        record.acceptedOpenAttemptSeq = 0;
        var response:Object = finishTerminal(record, terminalState, terminalReason, operationId);
        if (response == null || response.success !== true) {
            return response == null ? failureFor(record, "commit_pending") : response;
        }
        response.success = true;
        response.error = "";
        return response;
    }

    private static function executeQuery(params:Object):Object {
        var checked:Object = validateAnyIdentity(params);
        if (!checked.success) return checked.response;
        var record:Object = checked.record;
        if (hasOwnField(params, "openAttemptSeq")) {
            return executeRecoveryProofQuery(record, params);
        }
        if (record.transportDetachNeeded === true) {
            // connected/socket recovery 只能由 exact 9 键 proof 续跑。保留旧的
            // attempt=0 内部 transport 测试路径，但普通 triple query 不再是 handoff proof。
            if (Number(record.recoveryPendingOpenAttemptSeq) > 0
                    || Number(record.socketDetachObservedOpenAttemptSeq) > 0) {
                return failureFor(record, "commit_pending");
            }
            var detachResult:Object = continueTransportDetach(record);
            if (detachResult == null || detachResult.success !== true) {
                return failureFor(record, "commit_pending");
            }
            if (isTerminalState(record.state)) return recordResponse(record, true, "");
        }
        // 写回包落在 destination-after/source-present 时，Web 只允许 causal query，禁止重放写。
        // query 以 pending journal 的 exact before/after 观察继续 forward-complete，再投影最终状态。
        if (record.pendingCommit != null) {
            _busy = true;
            var resumed:Object = null;
            try {
                resumed = LootClaimCommitCoordinator.resume(record.pendingCommit);
            } finally {
                _busy = false;
            }
            if (resumed == null || !resumed.success) {
                record.state = STATE_PENDING;
                return failureFor(record, "commit_pending");
            }
            var finalized:Object = finalizeClaim(record, record.pendingCommit, resumed);
            if (finalized == null) return failureFor(record, "commit_pending");
            if (!finalized.success) {
                if (record.postCommitEffects != null) return failureFor(record, "commit_pending");
                return finalized;
            }
            record = _active;
        }
        if (record.postCommitEffects != null) {
            if (!retryPostCommitEffects(record)) return failureFor(record, "commit_pending");
        }
        return buildQueryProjection(record);
    }

    private static function executeRecoveryProofQuery(record:Object, params:Object):Object {
        var attemptSeq:Number = Number(params.openAttemptSeq);
        var nonce:String = String(params.recoveryNonce);

        if (recoveryProofCanProject(record, attemptSeq, nonce)) {
            pruneCompletedRecoveryProofsBefore(record, attemptSeq);
            return buildQueryProjection(record);
        }

        var exactConnectedPending:Boolean = Number(record.recoveryPendingOpenAttemptSeq)
                == attemptSeq && record.recoveryPendingNonce === nonce;
        var exactSocketObserved:Boolean = Number(record.socketDetachObservedOpenAttemptSeq)
            == attemptSeq;
        // 授权检查必须先于任何 journal/renderer/pause 变更。错 attempt/nonce
        // 即使当前有 transport fence，也不得误 settle。
        if (!exactConnectedPending && !exactSocketObserved) {
            var exactConnectedApplied:Boolean = hasExactConnectedAppliedProof(
                record, attemptSeq, nonce);
            if (Number(record.recoveryPendingOpenAttemptSeq) == attemptSeq
                    || ((Number(record.recoveryAppliedOpenAttemptSeq) == attemptSeq
                            || hasConnectedProofForAttempt(record, attemptSeq))
                        && !exactConnectedApplied)) {
                return recoveryProofFailureFor(record, "recovery_nonce_mismatch");
            }
            var proofError:String = attemptSeq == Number(record.openAttemptSeq)
                ? "recovery_not_applied" : "stale_recovery_proof";
            return recoveryProofFailureFor(record, proofError);
        }

        var advanced:Object = null;
        if (exactConnectedPending) {
            if (Number(record.acceptedOpenAttemptSeq) != attemptSeq) {
                return recoveryProofFailureFor(record, "recovery_pending");
            }
            advanced = advancePendingPanelRecovery(record);
        } else if (record.transportDetachNeeded === true) {
            advanced = continueTransportDetach(record);
        } else if (!hasSocketAppliedProof(record, attemptSeq)) {
            // onSocketClose 已写 exact observed 但首次 reconcile 可能在 busy 门前返回；
            // 重连 proof 只允许继续这个已观察的 socket attempt。
            advanced = reconcileTransportDetach(record.target);
        }

        if (recoveryProofCanProject(record, attemptSeq, nonce)) {
            pruneCompletedRecoveryProofsBefore(record, attemptSeq);
            return buildQueryProjection(record);
        }
        return recoveryProofFailureFor(record, "recovery_pending");
    }

    /** Host wire sanitizer 要求 LOOT_COMMIT_PENDING 与 commit_pending 成对出现。 */
    private static function recoveryProofFailureFor(record:Object,
                                                     activeError:String):Object {
        return failureFor(record, record != null && record.state == STATE_PENDING
            ? "commit_pending" : activeError);
    }

    private static function recoveryProofCanProject(record:Object, attemptSeq:Number,
                                                     nonce:String):Boolean {
        if (record == null || attemptSeq <= 0) return false;
        var entry:Object = completedRecoveryProof(record, attemptSeq);
        var exactConnected:Boolean = hasExactConnectedAppliedProof(
            record, attemptSeq, nonce);
        var exactSocket:Boolean = hasSocketAppliedProof(record, attemptSeq);
        var authorityClosed:Boolean = entry != null && entry.authorityClosed === true;
        if (record.state == STATE_SUSPENDED) {
            if (Number(record.socketDetachObservedOpenAttemptSeq) == attemptSeq
                    && !exactSocket) return false;
            return Number(record.suspendedFromOpenAttemptSeq) == attemptSeq
                || exactConnected || exactSocket || authorityClosed;
        }
        if (isTerminalState(record.state)) {
            return Number(record.terminalFromOpenAttemptSeq) == attemptSeq
                || exactConnected || exactSocket || authorityClosed;
        }
        // ACTIVE 成功投影只能是同 attempt 已完成的 legacy handoff。
        // 旧 proof 绝不能拿新 attempt 的 Web ACTIVE 当成恢复证明。
        return record.state == STATE_ACTIVE
            && Number(record.openAttemptSeq) == attemptSeq
            && record.legacyRecovery === true
            && record.legacyRendererConfirmed === true
            && _root._webPanelPauseLease == undefined
            && (exactConnected || exactSocket);
    }

    private static function buildQueryProjection(record:Object):Object {
        var response:Object = recordResponse(record, true, "");
        if (record.state == STATE_ACTIVE) {
            try {
                response.snapshots = buildFreshSnapshots(record, null, null);
            } catch (snapshotError) {
                trace("[LootContainerService] query snapshot failed: " + snapshotError);
                response.snapshots = null;
            }
            if (response.snapshots == null) return failureFor(record, "authority_unavailable");
        }
        return response;
    }

    private static function validateActiveIdentity(params:Object):Object {
        var checked:Object = validateAnyIdentity(params);
        if (!checked.success) return checked;
        if (checked.record.state != STATE_ACTIVE) {
            var errorCode:String = checked.record.pendingCommit != null
                    || checked.record.postCommitEffects != null
                    || checked.record.transportDetachNeeded === true
                ? "commit_pending" : "terminal_state";
            return {success:false, response:failureFor(checked.record, errorCode)};
        }
        return checked;
    }

    private static function validateAnyIdentity(params:Object):Object {
        if (params == undefined
                || typeof params.chestSessionId != "string"
                || typeof params.lootContainerId != "string"
                || !isSafeToken(String(params.chestSessionId), 96)
                || !isSafeToken(String(params.lootContainerId), 96)
                || !isPositiveWhole(params.containerEpoch)) {
            return {success:false, response:emptyFailure(params, "invalid_identity")};
        }
        var sessionId:String = String(params.chestSessionId);
        var record:Object = null;
        if (_active != null && _active.chestSessionId === sessionId) record = _active;
        else if (_reservation != null && _reservation.chestSessionId === sessionId) record = _reservation;
        else record = _terminalBySession[sessionId];
        if (record == null
                || record.lootContainerId !== String(params.lootContainerId)
                || Number(record.containerEpoch) != Number(params.containerEpoch)) {
            return {success:false, response:emptyFailure(params, "invalid_identity")};
        }
        return {success:true, record:record};
    }

    private static function validExpectedAuthority(params:Object, record:Object):Boolean {
        return isPositiveWhole(params.expectedAuthorityRevision)
            && Number(params.expectedAuthorityRevision) == Number(record.authorityRevision);
    }

    private static function validateWindows(params:Object, record:Object):Object {
        if (params.loot == undefined || params.backpack == undefined) return {success:false, error:"invalid_payload"};
        var loot:Object = normalizeWindow(params.loot, record.inventory.capacity, 100);
        if (loot == null) return {success:false, error:"invalid_payload"};
        // 战利品网格不分页；Host 对成功投影也冻结为完整 capacity，partial 直接 fail closed。
        if (Number(loot.offset) != 0 || Number(loot.limit) != record.inventory.capacity) {
            return {success:false, error:"invalid_payload"};
        }
        var backpack:ArrayInventory = resolveBackpack();
        if (backpack == null) return {success:false, error:"authority_unavailable"};
        var bag:Object = normalizeWindow(params.backpack, backpack.capacity, 100);
        if (bag == null) return {success:false, error:"invalid_payload"};
        return {success:true, loot:loot, backpack:bag};
    }

    private static function normalizeWindow(input:Object, capacity:Number, maxLimit:Number):Object {
        if (input == undefined || !hasOnlyKeys(input, ["offset", "limit"])
                || !isWhole(input.offset) || !isPositiveWhole(input.limit)) return null;
        var offset:Number = Number(input.offset);
        var limit:Number = Number(input.limit);
        if (offset < 0 || offset >= capacity || limit > maxLimit) return null;
        return {offset:offset, limit:limit};
    }

    private static function validateTooltipSource(record:Object, sourceRef:Object):Object {
        if (sourceRef == undefined || !hasOnlyKeys(sourceRef,
                ["containerId", "slot", "expectedLease", "expectedContainerVersion"])
                || typeof sourceRef.containerId != "string") {
            return {success:false, error:"invalid_payload"};
        }
        if (sourceRef.containerId === record.lootContainerId) return validateLootSource(record, sourceRef, true);
        if (sourceRef.containerId !== "背包") return {success:false, error:"transfer_forbidden"};
        var bag:ArrayInventory = resolveBackpack();
        if (bag == null || !isPositiveWhole(sourceRef.expectedContainerVersion)
                || Number(sourceRef.expectedContainerVersion) != bag.getMutationRevision()) {
            return {success:false, error:"stale_state"};
        }
        var checked:Object = InventoryPanelService.validateExternalSlotRef(sourceRef, false);
        if (!checked.success) return {success:false, error:String(checked.error)};
        return checked;
    }

    private static function validateLootSource(record:Object, sourceRef:Object, mustOccupy:Boolean):Object {
        if (sourceRef == undefined
                || !hasOnlyKeys(sourceRef,
                    ["containerId", "slot", "expectedLease", "expectedContainerVersion"])
                || typeof sourceRef.containerId != "string"
                || sourceRef.containerId !== record.lootContainerId
                || !isWhole(sourceRef.slot)
                || typeof sourceRef.expectedLease != "string"
                || !isPositiveWhole(sourceRef.expectedContainerVersion)) {
            return {success:false, error:"invalid_payload"};
        }
        var slot:Number = Number(sourceRef.slot);
        var inventory:ArrayInventory = record.inventory;
        if (slot < 0 || slot >= inventory.capacity) return {success:false, error:"invalid_slot"};
        var version:Number = inventory.getMutationRevision();
        if (Number(sourceRef.expectedContainerVersion) != version
                || _lootLeaseIds[slot] !== sourceRef.expectedLease
                || Number(_lootLeaseVersions[slot]) != version) {
            return {success:false, error:"stale_state"};
        }
        var item:Object = inventory.getItem(String(slot));
        if (item !== _lootLeaseRefs[slot]
                || itemSignature(item) != String(_lootLeaseSignatures[slot])) {
            return {success:false, error:"stale_state"};
        }
        if (mustOccupy && item == null) return {success:false, error:"stale_state"};
        return {success:true, containerId:record.lootContainerId, inventory:inventory, slot:slot, item:item};
    }

    private static function buildFreshSnapshots(record:Object, lootWindow:Object, bagWindow:Object):Array {
        if (record == null || record.state != STATE_ACTIVE || record.inventory == null) return null;
        if (lootWindow == null) lootWindow = {offset:0, limit:Math.min(100, record.inventory.capacity)};
        var backpack:ArrayInventory = resolveBackpack();
        if (backpack == null) return null;
        if (bagWindow == null) bagWindow = {offset:0, limit:Math.min(50, backpack.capacity)};
        var bagSnapshot:Object = InventoryPanelService.buildExternalSnapshot(
            "背包", Number(bagWindow.offset), Number(bagWindow.limit));
        if (bagSnapshot == null) return null;
        return [buildLootSnapshot(record, Number(lootWindow.offset), Number(lootWindow.limit)), bagSnapshot];
    }

    private static function buildLootSnapshot(record:Object, offset:Number, limit:Number):Object {
        var inventory:ArrayInventory = record.inventory;
        var version:Number = inventory.getMutationRevision();
        var end:Number = Math.min(inventory.capacity, offset + limit);
        var slots:Array = [];
        for (var slot:Number = offset; slot < end; slot++) {
            var item:Object = inventory.getItem(String(slot));
            var row:Object = {
                physicalSlot:slot,
                occupied:item != null,
                slotLease:issueLootLease(record, slot, item, version)
            };
            if (item != null) row.item = InventoryPanelService.buildItemProjection(item);
            slots.push(row);
        }
        _snapshotSeq++;
        return {
            containerId:record.lootContainerId,
            capacity:inventory.capacity,
            accessibleCapacity:inventory.capacity,
            viewCapacity:inventory.capacity,
            filterKey:"all",
            pageSizeHint:inventory.capacity,
            locked:false,
            snapshotSeq:_snapshotSeq,
            containerEpoch:record.containerEpoch,
            containerVersion:version,
            offset:offset,
            limit:slots.length,
            slots:slots,
            filterFacets:[],
            filterItemCount:remainingCount(record),
            setFacets:[],
            setFilterItemCount:0
        };
    }

    private static function issueLootLease(record:Object, slot:Number, item:Object, version:Number):String {
        var signature:String = itemSignature(item);
        var current:String = _lootLeaseIds[slot] == undefined ? "" : String(_lootLeaseIds[slot]);
        if (current != "" && _lootLeaseRefs[slot] === item
                && Number(_lootLeaseVersions[slot]) == version
                && String(_lootLeaseSignatures[slot]) == signature) return current;
        _leaseSeq++;
        var lease:String = record.lootContainerId + ".slot." + slot + "." + _leaseSeq;
        _lootLeaseIds[slot] = lease;
        _lootLeaseRefs[slot] = item;
        _lootLeaseVersions[slot] = version;
        _lootLeaseSignatures[slot] = signature;
        return lease;
    }

    private static function invalidateLootLeases():Void {
        _lootLeaseIds = [];
        _lootLeaseRefs = [];
        _lootLeaseVersions = [];
        _lootLeaseSignatures = [];
    }

    private static function buildTooltip(item:Object):Object {
        if (item == null) return null;
        var itemData:Object = ItemUtil.getItemData(item.name);
        if (itemData == null) return null;
        var projection:Object = InventoryPanelService.buildItemProjection(item);
        var instanceValue:Object = typeof item.value == "object" ? item.value : {level:1};
        var baseItem = item instanceof BaseItem && typeof item.value == "object" ? item : null;
        var descHTML:String;
        var introHTML:String;
        try {
            descHTML = TooltipComposer.generateItemDescriptionText(itemData, baseItem);
            introHTML = TooltipComposer.generateIntroPanelContent(baseItem, itemData, instanceValue);
        } catch (tooltipError) {
            return null;
        }
        if (typeof descHTML != "string" || typeof introHTML != "string") return null;
        var itemType:String = String(projection.majorType);
        if (itemType == "消耗品" && projection.use != undefined) itemType = String(projection.use);
        return {
            itemName:String(item.name),
            displayname:String(projection.displayName),
            iconName:String(projection.icon),
            itemType:itemType,
            descHTML:descHTML.split('"').join("'"),
            introHTML:introHTML.split('"').join("'")
        };
    }

    /** mandatory effects 已完成后的 best-effort 事件；每个 flag 都先置位，保证至多一次。 */
    private static function publishPostCommitEvents(effects:Object):Void {
        var committed:Object = effects.committed;
        var source:Object = effects.source;
        if (!effects.sourceEventPublished) {
            effects.sourceEventPublished = true;
            try {
                source.inventory.publishTransactionChange(source.slot, "removed");
            } catch (sourceEventError) {
                trace("[LootContainerService] source event failed");
            }
        }
        if (!effects.destinationEventPublished) {
            effects.destinationEventPublished = true;
            try {
                committed.destinationInventory.publishTransactionChange(
                    Number(committed.destinationSlot), String(committed.destinationEvent));
            } catch (destinationEventError) {
                trace("[LootContainerService] destination event failed");
            }
        }
        if (!effects.collectionEventPublished) {
            effects.collectionEventPublished = true;
            try {
                if (typeof committed.collection.publishTransactionChanges == "function") {
                    committed.collection.publishTransactionChanges(committed.collectionChanges);
                }
            } catch (collectionEventError) {
                trace("[LootContainerService] collection event failed");
            }
        }
        if (!effects.levelEventPublished) {
            effects.levelEventPublished = true;
            try {
                if (typeof _root.主角是否升级 == "function") {
                    _root.主角是否升级(_root.等级, _root.经验值);
                }
            } catch (levelError) {
                trace("[LootContainerService] level check failed");
            }
        }
    }

    private static function classifyItem(item:Object):String {
        var name:String = String(item.name);
        if (name == "金币") return "money";
        if (name == "K点") return "kpoints";
        if (name == "经验值") return "experience";
        if (name == "技能点") return "skill_points";
        if (ItemUtil.isMaterial(name)) return "material";
        if (ItemUtil.isInformation(name)) return "information";
        return "ordinary";
    }

    private static function duplicateClaim(record:Object, prior:Object, fingerprint:String):Object {
        if (prior.kind != "claim" || prior.fingerprint != fingerprint) {
            return failureFor(record, "operation_conflict");
        }
        if (record.postCommitEffects != null) {
            if (record.postCommitEffects.operationId !== record.lastAppliedOperationId
                    || !retryPostCommitEffects(record)) {
                return failureFor(record, "commit_pending");
            }
        }
        var response:Object = recordResponse(record, true, "");
        try {
            response.snapshots = buildFreshSnapshots(record, null, null);
        } catch (snapshotError) {
            trace("[LootContainerService] duplicate claim snapshot failed: " + snapshotError);
            response.snapshots = null;
        }
        if (response.snapshots == null) return failureFor(record, "authority_unavailable");
        return response;
    }

    private static function duplicateClose(record:Object, prior:Object, fingerprint:String,
                                           operationId:String):Object {
        if (prior.kind != "close" || prior.fingerprint != fingerprint) {
            return failureFor(record, "operation_conflict");
        }
        // suspend op 只在仍为当前 suspend 时幂等；reopen/再次 suspend 后的旧回包不能
        // 被误认成新页面的 close 成功。
        if (prior.resultState == STATE_SUSPENDED
                && (record.state != STATE_SUSPENDED
                    || record.lastAppliedOperationId !== operationId)) {
            return failureFor(record, "operation_conflict");
        }
        return recordResponse(record, true, "");
    }

    private static function claimFingerprint(params:Object):String {
        var source:Object = params == undefined ? null : params.source;
        return String(params.direction) + "|" + String(params.targetContainerId) + "|"
            + String(source == null ? "" : source.containerId) + "|"
            + String(source == null ? "" : source.slot) + "|"
            + String(source == null ? "" : source.expectedLease) + "|"
            + String(source == null ? "" : source.expectedContainerVersion);
    }

    private static function closeFingerprint(params:Object):String {
        return String(params.closeLease) + "|" + String(params.abandon);
    }

    /** 防止 __proto__/constructor 等合法 safe token 与 Object 原型成员碰撞。 */
    private static function operationKey(operationId:String):String {
        return "$" + operationId;
    }

    private static function finishTerminal(record:Object, terminalState:String,
                                           reason:String, operationId:String):Object {
        if (record != null && (record.pendingCommit != null
                || record.postCommitEffects != null
                || record.transportDetachNeeded === true)) {
            return failureFor(record, "commit_pending");
        }
        // 正常 terminal 只证明 AS2 权威已落盘，不能冒充 Web DOM 与 native
        // PanelHost 的 exact visual close。全局 pause lease 必须继续由 Host 持有，
        // 待 LootPanelCoordinator 收齐关闭证明后经 webPanelUnpause 释放；否则游戏会
        // 在旧面板仍可见或仍可回调时提前恢复。reopen failure 等无可见面板路径已在
        // 各自调用 finishTerminal 前完成其 mandatory pause-release stage。
        detachLegacyRecoveryObserver(record);
        releaseSuspendedAnchor(record);
        releaseHeldTargetTimeline(record);
        record.state = terminalState;
        record.reason = reason;
        record.pendingCommit = null;
        if (Number(record.terminalFromOpenAttemptSeq) <= 0) {
            record.terminalFromOpenAttemptSeq = Number(record.openAttemptSeq);
        }
        recordAuthorityClosedProof(record, Number(record.terminalFromOpenAttemptSeq));
        record.recoveryPendingOpenAttemptSeq = 0;
        record.recoveryPendingNonce = "";
        record.recoveryPendingReason = "";
        record.authorityRevision++;
        if (operationId != "") {
            record.lastAppliedOperationId = operationId;
            var journalKey:String = operationKey(operationId);
            if (record.operations[journalKey] != undefined) {
                record.operations[journalKey].authorityRevision = record.authorityRevision;
                record.operations[journalKey].resultState = terminalState;
            }
        }
        invalidateLootLeases();
        var tombstone:Object = {
            chestSessionId:record.chestSessionId,
            lootContainerId:record.lootContainerId,
            containerEpoch:record.containerEpoch,
            authorityRevision:record.authorityRevision,
            lastAppliedOperationId:record.lastAppliedOperationId,
            closeLease:record.closeLease,
            state:terminalState,
            reason:reason,
            remainingCount:remainingCount(record),
            operations:record.operations,
            openAttemptSeq:record.openAttemptSeq,
            openAttemptWasReopen:record.openAttemptWasReopen,
            suspendedFromOpenAttemptSeq:record.suspendedFromOpenAttemptSeq,
            terminalFromOpenAttemptSeq:record.terminalFromOpenAttemptSeq,
            recoveryAppliedOpenAttemptSeq:record.recoveryAppliedOpenAttemptSeq,
            recoveryAppliedNonce:record.recoveryAppliedNonce,
            socketDetachObservedOpenAttemptSeq:record.socketDetachObservedOpenAttemptSeq,
            socketDetachAppliedOpenAttemptSeq:record.socketDetachAppliedOpenAttemptSeq,
            completedRecoveryProofs:record.completedRecoveryProofs,
            completedRecoveryProofOrder:record.completedRecoveryProofOrder
        };
        storeTombstone(tombstone);
        if (_active === record) _active = null;
        if (_reservation === record) _reservation = null;
        if (_legacyRecovery === record) _legacyRecovery = null;
        return recordResponse(tombstone, true, "");
    }

    private static function handleLegacyRecoveryMutation(record:Object,
                                                         changedInventory:Object):Void {
        if (_legacyRecovery !== record || record == null
                || record.inventory !== changedInventory) return;
        // ArrayInventory.remove 先发布事件、后维护 occupiedCount；强制索引校验会按已删除的
        // items 重建计数，使 completeLegacyRecoveryIfEmpty 在同一事件栈读取到真实空状态。
        try {
            record.inventory.getIndexes();
        } catch (indexError) {
            return;
        }
        completeLegacyRecoveryIfEmpty();
    }

    private static function detachLegacyRecoveryObserver(record:Object):Void {
        if (record != null && _legacyObserverRecord !== record) return;
        var dispatcher:Object = _legacyObserverDispatcher;
        var callback:Function = _legacyObserverCallback;
        _legacyObserverRecord = null;
        _legacyObserverDispatcher = null;
        _legacyObserverCallback = null;
        if (dispatcher == null || callback == null) return;
        try {
            if (typeof dispatcher.isDestroyed != "function" || !dispatcher.isDestroyed()) {
                dispatcher.unsubscribe("ItemRemoved", callback, null);
                dispatcher.unsubscribe("ItemValueChanged", callback, null);
            }
        } catch (unsubscribeError) {
        }
    }

    private static function moveToLegacyRecovery(record:Object, reason:String):Void {
        if (record == null || record.inventory == null || isTerminalState(record.state)) return;
        // reservation 在 kill/open 门期间也使用 LOOT_COMMIT_PENDING，但它没有 claim journal，
        // 且完整物化失败后必须能交回 same-object legacy UI。只阻止真实领取半提交。
        if (record.pendingCommit != null || record.postCommitEffects != null
                || record.transportDetachNeeded === true) return;
        if ((_active != null && _active !== record)
                || (_legacyRecovery != null && _legacyRecovery !== record)) return;
        if (_legacyRecovery === record) return;
        record.state = STATE_ACTIVE;
        record.reason = isSafeReason(reason) ? reason : "legacy_fallback";
        record.legacyRecovery = true;
        record.reopenAttemptSeq = 0;
        record.acceptedOpenAttemptSeq = 0;
        record.transportDetachResumeSuspended = false;
        record.transportDetachReleasePause = false;
        record.authorityRevision++;
        _active = record;
        if (_reservation === record) _reservation = null;
        _legacyRecovery = record;
        invalidateLootLeases();
    }

    private static function holdTargetTimeline(record:Object):Boolean {
        if (record == null || record.target == null) return false;
        if (record.targetHeld === true) return true;
        var target:Object = record.target;
        if (typeof target.stop != "function") return false;
        try {
            target.stop();
        } catch (holdError) {
            return false;
        }
        record.targetHeld = true;
        return true;
    }

    /** suspend authority 落地前的 exact scene-object anchor 证明。 */
    private static function registerSuspendedAnchor(record:Object):Boolean {
        if (record == null || record.target == null || record.targetHeld !== true
                || record.legacyRecovery === true) return false;
        if (record.suspendedAnchorRegistered === true) return true;
        var target:Object = record.target;
        var gameworld:Object = _root.gameworld;
        if (gameworld == null || target._parent !== gameworld
                || target.dispatcher == null
                || typeof target.dispatcher.publish != "function"
                || target.area == null
                || target.interactionEnabled === false
                || target.pickupEnabled === false) return false;
        var registered:Boolean = false;
        try {
            registered = org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.BoxInteractionArbiter.register(
                target, gameworld) === true;
        } catch (anchorError) {
            registered = false;
        }
        if (!registered) return false;
        record.suspendedAnchorRegistered = true;
        return true;
    }

    private static function releaseSuspendedAnchor(record:Object):Void {
        if (record == null || record.suspendedAnchorRegistered !== true) return;
        record.suspendedAnchorRegistered = false;
        try {
            org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.BoxInteractionArbiter.unregister(
                record.target);
        } catch (anchorError) {
        }
    }

    private static function releaseHeldTargetTimeline(record:Object):Void {
        if (record == null || record.targetHeld !== true) return;
        var target:Object = record.target;
        record.targetHeld = false;
        if (target == null || typeof target.play != "function") return;
        try {
            target.play();
        } catch (playError) {
        }
    }

    private static function mintCloseLease(record:Object):String {
        _closeLeaseSeq++;
        return "close." + String(record.chestSessionId) + "."
            + String(record.containerEpoch) + "." + _closeLeaseSeq + "." + getTimer();
    }

    private static function legacyRendererProjection(record:Object, duplicate:Boolean):Object {
        return {
            success:true,
            duplicate:duplicate,
            inventory:record.inventory,
            target:record.target,
            presetName:record.presetName,
            row:record.row,
            col:record.col,
            chestSessionId:record.chestSessionId,
            lootContainerId:record.lootContainerId,
            rendererConfirmed:record.legacyRendererConfirmed === true
        };
    }

    private static function storeTombstone(record:Object):Void {
        var sessionId:String = String(record.chestSessionId);
        if (_terminalBySession[sessionId] == undefined) _terminalOrder.push(sessionId);
        _terminalBySession[sessionId] = record;
        while (_terminalOrder.length > MAX_TOMBSTONES) {
            var expiredId:String = String(_terminalOrder.shift());
            delete _terminalBySession[expiredId];
        }
    }

    private static function recordResponse(record:Object, success:Boolean, errorCode:String):Object {
        var terminal:Object = null;
        var closeLease:String = "";
        if (success && record != null && record.state == STATE_ACTIVE) closeLease = String(record.closeLease);
        if (record != null && isTerminalState(record.state)) {
            terminal = {
                kind:String(record.state),
                reason:String(record.reason),
                remainingCount:Number(record.remainingCount == undefined ? remainingCount(record) : record.remainingCount)
            };
        }
        return {
            success:success,
            error:errorCode,
            chestSessionId:record == null ? "" : String(record.chestSessionId),
            lootContainerId:record == null ? "" : String(record.lootContainerId),
            containerEpoch:record == null ? 0 : Number(record.containerEpoch),
            authorityRevision:record == null ? 0 : Number(record.authorityRevision),
            lastAppliedOperationId:record == null ? "" : String(record.lastAppliedOperationId),
            closeLease:closeLease,
            state:record == null ? "" : String(record.state),
            remainingCount:record == null ? 0 : remainingCount(record),
            snapshots:[],
            tooltip:null,
            terminal:terminal
        };
    }

    private static function failureFor(record:Object, errorCode:String):Object {
        return recordResponse(record, false, errorCode);
    }

    private static function emptyFailure(params:Object, errorCode:String):Object {
        return {
            success:false,
            error:errorCode,
            chestSessionId:safeEcho(params == undefined ? null : params.chestSessionId),
            lootContainerId:safeEcho(params == undefined ? null : params.lootContainerId),
            containerEpoch:params != undefined && isPositiveWhole(params.containerEpoch)
                ? Number(params.containerEpoch) : 0,
            authorityRevision:0,
            lastAppliedOperationId:"",
            closeLease:"",
            state:"",
            remainingCount:0,
            snapshots:[],
            tooltip:null,
            terminal:null
        };
    }

    private static function localFailure(errorCode:String):Object {
        return {success:false, error:errorCode};
    }

    private static function remainingCount(record:Object):Number {
        if (record == null || record.inventory == null) {
            return record == null || isNaN(Number(record.remainingCount)) ? 0 : Number(record.remainingCount);
        }
        return record.inventory.size();
    }

    private static function resolveBackpack():ArrayInventory {
        if (_root.物品栏 == undefined) return null;
        var backpack:ArrayInventory = _root.物品栏.背包;
        return backpack instanceof ArrayInventory ? backpack : null;
    }

    private static function validateInventory(inventory:ArrayInventory, expectedCapacity:Number):Boolean {
        if (!(inventory instanceof ArrayInventory)
                || inventory.capacity != expectedCapacity
                || !isPositiveWhole(inventory.capacity)
                || inventory.capacity > 100) return false;
        var indexes:Array = inventory.getIndexes();
        if (!(indexes instanceof Array) || indexes.length > inventory.capacity) return false;
        for (var i:Number = 0; i < indexes.length; i++) {
            var slot:Number = Number(indexes[i]);
            if (!isWhole(slot) || slot < 0 || slot >= inventory.capacity) return false;
            if (!validateItem(inventory.getItem(String(slot)))) return false;
        }
        return true;
    }

    private static function validateItem(item:Object):Boolean {
        if (!(item instanceof BaseItem)
                || !isSafeText(String(item.name), 128)
                || !ItemUtil.isItem(String(item.name))
                || !isWhole(item.lastUpdate)
                || Number(item.lastUpdate) < 0) return false;
        if (ItemUtil.isEquipment(String(item.name))) {
            if (item.value == null || typeof item.value != "object") return false;
            if (!isPositiveWhole(item.value.level)) return false;
            return serializableValue(item.value, 0, []);
        }
        return isPositiveWhole(item.value) && Number(item.value) <= MAX_SAFE_INTEGER;
    }

    private static function serializableValue(value, depth:Number, seen:Array):Boolean {
        if (depth > 6 || value === undefined || typeof value == "function" || typeof value == "movieclip") return false;
        if (value === null) return true;
        var kind:String = typeof value;
        if (kind == "number") return (Number(value) - Number(value)) == 0;
        if (kind == "string") return isSafeText(String(value), 256);
        if (kind == "boolean") return true;
        if (kind != "object") return false;
        for (var seenIndex:Number = 0; seenIndex < seen.length; seenIndex++) {
            if (seen[seenIndex] === value) return false;
        }
        seen.push(value);
        var count:Number = 0;
        for (var key:String in value) {
            if (typeof value.hasOwnProperty == "function" && !value.hasOwnProperty(key)) continue;
            count++;
            if (count > 64 || !isSafeText(key, 64) || !serializableValue(value[key], depth + 1, seen)) {
                seen.pop();
                return false;
            }
        }
        if (value instanceof Array && value.length > 64) {
            seen.pop();
            return false;
        }
        seen.pop();
        return true;
    }

    private static function metadataMatches(record:Object, metadata:Object):Boolean {
        if (metadata == undefined || metadata == null) return true;
        if (typeof metadata != "object" || metadata instanceof Array) return false;
        for (var key:String in metadata) {
            if (typeof metadata.hasOwnProperty == "function" && !metadata.hasOwnProperty(key)) continue;
            if (key != "presetName" && key != "displayName" && key != "row"
                    && key != "col" && key != "chestRolloutId"
                    && key != "lootFlowProfile" && key != "unlockPolicy") return false;
        }
        if (metadata.presetName != undefined && metadata.presetName !== record.presetName) return false;
        if (metadata.displayName != undefined && metadata.displayName !== record.presetName) return false;
        if (metadata.row != undefined && Number(metadata.row) != record.row) return false;
        if (metadata.col != undefined && Number(metadata.col) != record.col) return false;
        if (metadata.chestRolloutId != undefined && metadata.chestRolloutId !== record.rolloutId) return false;
        if (metadata.lootFlowProfile != undefined
                && metadata.lootFlowProfile !== record.rolloutProfile) return false;
        if (metadata.unlockPolicy != undefined
                && metadata.unlockPolicy !== record.unlockPolicy) return false;
        return true;
    }

    private static function hasExactGridShape(target:Object):Boolean {
        if (target == null || typeof target.presetName != "string"
                || !isPositiveWhole(target.row) || !isPositiveWhole(target.col)) return false;
        if (target.presetName === "保险柜") return target.row === 4 && target.col === 8;
        if (target.presetName === "生存箱") return target.row === 4 && target.col === 4;
        if (target.presetName === "装备箱") return target.row === 2 && target.col === 4;
        return false;
    }

    private static function hasOwnField(target:Object, key:String):Boolean {
        return target != null && typeof target.hasOwnProperty == "function" && target.hasOwnProperty(key);
    }

    private static function itemSignature(item:Object):String {
        if (item == null) return "empty";
        var signature:String = String(item.name) + "|" + String(item.lastUpdate) + "|";
        if (typeof item.value == "number") return signature + "n:" + item.value;
        var value:Object = item.value;
        signature += "o:" + String(value.level) + ":" + String(value.tier) + ":";
        var mods:Object = value.mods;
        if (mods instanceof Array) {
            for (var i:Number = 0; i < mods.length; i++) signature += String(mods[i]).length + ":" + mods[i] + ";";
        } else if (mods != null) {
            var names:Array = [];
            for (var key:String in mods) names.push(key + "=" + String(mods[key]));
            names.sort();
            for (i = 0; i < names.length; i++) signature += names[i].length + ":" + names[i] + ";";
        }
        return signature;
    }

    private static function validOperationId(value):Boolean {
        return typeof value == "string" && isSafeToken(String(value), 96);
    }

    private static function validateCommandShape(commandName:String, params:Object):Boolean {
        return LootContainerValidation.validateCommandShape(commandName, params);
    }

    private static function hasOnlyKeys(value:Object, allowed:Array):Boolean {
        return LootContainerValidation.hasOnlyKeys(value, allowed);
    }

    private static function safeEcho(value):String {
        return typeof value == "string" && isSafeToken(String(value), 96) ? String(value) : "";
    }

    private static function isSafeToken(value:String, maxLength:Number):Boolean {
        if (value == undefined || value.length < 1 || value.length > maxLength) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            var valid:Boolean = (code >= 48 && code <= 57)
                || (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
                || code == 45 || code == 46 || code == 58 || code == 95;
            if (!valid) return false;
        }
        return true;
    }

    private static function isSafeText(value:String, maxLength:Number):Boolean {
        if (value == undefined || value.length < 1 || value.length > maxLength) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (code < 32 || code == 127) return false;
        }
        return true;
    }

    private static function isSafeReason(value:String):Boolean {
        if (value == undefined || value.length < 1 || value.length > 64) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (!((code >= 97 && code <= 122) || (code >= 48 && code <= 57) || code == 95)) return false;
        }
        return true;
    }

    private static function isTerminalState(state:String):Boolean {
        return state == STATE_CONSUMED || state == STATE_ABANDONED || state == STATE_EXPIRED;
    }

    private static function isWhole(value):Boolean {
        return typeof value == "number" && (value - value) == 0 && Math.floor(value) == value;
    }

    private static function isPositiveWhole(value):Boolean {
        return isWhole(value) && Number(value) > 0 && Number(value) <= MAX_SAFE_INTEGER;
    }

    private static function markDirtyVerified():Boolean {
        if (_root.存档系统 == undefined || _root.存档系统 == null) return false;
        _root.存档系统.dirtyMark = true;
        return _root.存档系统.dirtyMark === true;
    }

    private static function injectPostCommitFailure(stage:String):Void {
        if (_testPostCommitFailureStage !== stage
                || _testPostCommitFailureRemaining <= 0) return;
        _testPostCommitFailureRemaining--;
        if (_testPostCommitFailureRemaining <= 0) {
            _testPostCommitFailureStage = "";
            _testPostCommitFailureRemaining = 0;
        }
        throw "injected_post_commit_" + stage;
    }

    private static function injectTransportHandoffFailure(stage:String):Void {
        if (_testTransportHandoffFailureStage !== stage) return;
        _testTransportHandoffFailureStage = "";
        throw "injected_transport_handoff_" + stage;
    }

    /** TestLoader 专用：后续 repeatCount 次 journal mandatory effect 抛错；省略时仍只失败一次。 */
    public static function testOnlyFailNextPostCommit(stage:String, repeatCount:Number):Void {
        if (stage != "dirty" && stage != "loot_cache"
                && stage != "destination_cache") return;
        _testPostCommitFailureStage = stage;
        _testPostCommitFailureRemaining = isWhole(repeatCount)
                && repeatCount > 0 && repeatCount <= 100 ? repeatCount : 1;
    }

    /** TestLoader 专用：下一次 transport renderer/unpause 证明失败。 */
    public static function testOnlyFailNextTransportHandoff(stage:String):Void {
        if (stage != "renderer" && stage != "unpause") return;
        _testTransportHandoffFailureStage = stage;
    }

    private static function sendResponse(response:Object):Void {
        if (_root.server == undefined || _root.server.sendSocketMessage == undefined) return;
        if (_json == undefined) _json = new LiteJSON();
        _root.server.sendSocketMessage(_json.stringify(response));
    }

    /** TestLoader 专用：隔离静态 authority、lease、tombstone 与 recovery。 */
    public static function testOnlyReset():Void {
        detachLegacyRecoveryObserver(null);
        releaseSuspendedAnchor(_active);
        releaseHeldTargetTimeline(_active);
        if (_reservation !== _active) releaseHeldTargetTimeline(_reservation);
        LootClaimCommitCoordinator.testOnlyReset();
        _busy = false;
        _authorityEpoch++;
        _sessionSeq = 0;
        _containerEpochSeq = 0;
        _leaseSeq = 0;
        _closeLeaseSeq = 0;
        _snapshotSeq = 0;
        _legacyClaimSeq = 0;
        _reservation = null;
        _active = null;
        _legacyRecovery = null;
        _testPostCommitFailureStage = "";
        _testPostCommitFailureRemaining = 0;
        _testTransportHandoffFailureStage = "";
        _terminalBySession = {};
        _terminalOrder = [];
        invalidateLootLeases();
    }
}
