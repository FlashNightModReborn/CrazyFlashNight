/*
 * EquipmentTuningService —— 装备调制权威服务。
 * snapshot/preview 零写；commit 重新验证会话、lease、规则与材料精确数量，
 * 再以无事件批处理完成装备和材料写入，最后统一 dirty、成就、事件与投影。
 */
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.EquipmentInventory;
import org.flashNight.arki.achievement.AchievementMetrics;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.tooltip.TooltipComposer;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.equipment.EquipmentStatProjector;
import org.flashNight.neur.Event.EventBus;

/** 装备调制唯一权威写服务；Web 只提交不可信意图。 */
class org.flashNight.arki.item.EquipmentTuningService {
    private static var _json:LiteJSON;
    private static var _installed:Boolean = false;
    private static var _busy:Boolean = false;
    private static var _sessionPanel:String = "";
    private static var _sessionView:String = "";
    private static var _sessionGeneration:Number = 0;
    private static var _candidateNames:Object = {};
    private static var _plan:Object = null;
    private static var _tokenSeq:Number = 0;
    private static var _transactionSeq:Number = 0;
    private static var _tokenTransactions:Object = {};
    private static var _tokenTransactionOrder:Array = [];
    private static var _writeEpoch:Number = 0;
    private static var _processedCalls:Object = {};
    private static var _processedCallOrder:Array = [];
    private static var _testFailNext:Boolean = false;
    private static var _testFailNextMaterialCommit:Boolean = false;
    private static var _testFailNextSerialization:Boolean = false;
    private static var _testFailNextWornConversionBagCommit:Boolean = false;
    private static var _allowedOperations:Object = {
        enhance:true, convert:true, install_tier:true,
        install_mod:true, replace_mod:true, detach_mod:true, detach_all_mods:true
    };
    private static var _loadoutAllowedOperations:Object = {
        enhance:true, convert:true, install_tier:true, install_mod:true,
        replace_mod:true, detach_mod:true, detach_all_mods:true
    };
    private static var _inventorySourceKeys:Object = {
        sourceKind:true, containerId:true, slot:true, expectedLease:true
    };
    private static var _loadoutSourceKeys:Object = {
        sourceKind:true, sessionGeneration:true,
        slotKey:true, expectedLoadoutRevision:true
    };

    public static function install():Void {
        if (_installed) return;
        _json = new LiteJSON();
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["equipmentTuningSnapshot"] = function(params) {
            org.flashNight.arki.item.EquipmentTuningService.handle("snapshot", params);
        };
        _root.gameCommands["equipmentTuningPreview"] = function(params) {
            org.flashNight.arki.item.EquipmentTuningService.handle("preview", params);
        };
        _root.gameCommands["equipmentTuningCommit"] = function(params) {
            org.flashNight.arki.item.EquipmentTuningService.handle("commit", params);
        };
        _root.gameCommands["equipmentTuningTooltip"] = function(params) {
            org.flashNight.arki.item.EquipmentTuningService.handle("tooltip", params);
        };
        _root.gameCommands["equipmentTuningDetach"] = function(params) {
            org.flashNight.arki.item.EquipmentTuningService.handle("detach", params);
        };
        _installed = true;
    }

    private static function handle(commandName:String, params:Object):Void {
        var response:Object = execute(commandName, params);
        response.task = "equipment_tuning_response";
        response.callId = params == undefined ? undefined : params.callId;
        if (params != undefined && params.requestCallId != undefined) {
            recordProcessedCall(String(params.requestCallId));
        }
        sendResponse(response);
    }

    /** 同步协议入口，同时供 TestLoader 行为测试使用。 */
    public static function execute(commandName:String, params:Object):Object {
        var result:Object;
        if (_busy) result = fail("busy");
        else if (params == undefined || Number(params.v) != 1) result = fail("unsupported_version");
        else if (commandName == "snapshot") result = executeSnapshot(params);
        else if (commandName == "preview") result = executePreview(params);
        else if (commandName == "commit") result = executeCommit(params);
        else if (commandName == "tooltip") result = executeTooltip(params);
        else if (commandName == "detach") result = executeDetach(params);
        else result = fail("unsupported_cmd");
        return decorateResponse(result, commandName, params);
    }

    private static function executeSnapshot(params:Object):Object {
        var session:Object = activateWebSession(params);
        if (!session.success) return session;
        // fresh snapshot / 显式 reconcile 都建立新的读基线；旧 preview 不能跨基线提交。
        revokeActivePlan();
        var source:Object = resolveWebSlot(params.source);
        if (!source.success) return source;
        var snapshot:Object = buildTuningSnapshot(source, safeSourceRef(source));
        if (snapshot == null) return fail("snapshot_failed");
        var response:Object = {success:true, snapshot:snapshot};
        if (params.reconcileAfterCallId != undefined) {
            var targetCallId:String = String(params.reconcileAfterCallId);
            response.reconcileAfterCallId = targetCallId;
            // 同一有序 socket 上的显式 snapshot 是 barrier：读到的状态必然位于该写意图之后。
            response.reconciled = true;
        }
        return response;
    }

    private static function executePreview(params:Object):Object {
        var session:Object = activateWebSession(params);
        if (!session.success) return session;
        // 同一权威 session 中，每次新 preview 尝试都是单一当前计划的代际边界。
        // 即使后续参数、候选或业务规则校验失败，也不得让旧 token 继续可提交。
        revokeActivePlan();
        var operation:String = params.operation == undefined ? "" : String(params.operation);
        if (_allowedOperations[operation] !== true) return fail("unsupported_operation");
        var source:Object = resolveWebSlot(params.source);
        if (!source.success) return source;
        if (source.sourceKind == "loadout"
                && _loadoutAllowedOperations[operation] !== true) {
            return fail("unsupported_operation");
        }
        var target:Object = null;
        if (operation == "convert") {
            target = resolveWebSlot(params.target);
            if (!target.success) return target;
            if (target.sourceKind != "inventory") {
                return fail("unsupported_operation");
            }
        }

        var candidateName:String = "";
        var replaceCandidateName:String = "";
        if (operation == "install_tier" || operation == "install_mod"
                || operation == "replace_mod" || operation == "detach_mod") {
            if (params.candidateKey == undefined) return fail("invalid_payload");
            var candidate:Object = _candidateNames[String(params.candidateKey)];
            var expectedKind:String = operation == "install_tier" ? "tier" : "mod";
            if (candidate == null || candidate.kind != expectedKind) return fail("unknown_candidate");
            candidateName = String(candidate.itemName);
        }
        if (operation == "replace_mod") {
            if (params.replaceCandidateKey == undefined) return fail("invalid_payload");
            var replaceCandidate:Object = _candidateNames[String(params.replaceCandidateKey)];
            if (replaceCandidate == null || replaceCandidate.kind != "mod") return fail("unknown_candidate");
            replaceCandidateName = String(replaceCandidate.itemName);
        }
        var plan:Object = buildPlan(operation, source, target, candidateName,
                                    replaceCandidateName, params.targetLevel);
        if (!plan.success) return plan;
        installPlan(plan);
        return buildPreviewResponse(plan);
    }

    private static function executeCommit(params:Object):Object {
        if (!sessionMatches(params)) return commitFail("view_session_expired", tokenTransaction(params));
        var token:String = params.expectedTuningToken == undefined ? "" : String(params.expectedTuningToken);
        var knownTransaction:String = token == "" ? "" : String(_tokenTransactions[token]);
        if (_plan == null || token == "" || token != _plan.tuningToken) {
            return commitFail("token_invalid", knownTransaction);
        }

        var plan:Object = _plan;
        _plan = null;
        var transactionId:String = String(plan.transactionId);
        if (getTimer() - Number(plan.createdAt) > 30000) {
            return commitFail("token_expired", transactionId);
        }

        _busy = true;
        var source:Object = revalidateSlot(plan.source);
        if (!source.success) {
            _busy = false;
            return commitFail("stale_state", transactionId);
        }
        var target:Object = null;
        if (plan.target != null) {
            target = revalidateSlot(plan.target);
            if (!target.success) {
                _busy = false;
                return commitFail("stale_state", transactionId);
            }
        }

        var fresh:Object = buildPlan(plan.operation, source, target, plan.candidateName,
                                     plan.replaceCandidateName, plan.targetLevel);
        if (!fresh.success || !plansEqual(plan, fresh)) {
            _busy = false;
            return commitFail("stale_state", transactionId);
        }
        fresh.tuningToken = token;
        fresh.transactionId = transactionId;

        if (fresh.noOp == true) {
            var noOpSnapshot:Object = buildTuningSnapshot(source, safeSourceRef(source));
            var noOpInventory:Object = source.sourceKind == "inventory"
                ? InventoryPanelService.buildExternalSnapshot("背包", 0, 50)
                : null;
            _busy = false;
            return {
                success:true, transactionId:transactionId, tuningToken:token,
                canCommit:false, operation:fresh.operation, noOp:true,
                before:fresh.before, after:fresh.after, materials:fresh.materials,
                removedMods:fresh.removedMods,
                snapshot:noOpSnapshot,
                inventorySnapshots:noOpInventory == null
                    ? [] : [noOpInventory]
            };
        }

        var materials:Object = getMaterialCollection();
        if (materials == null || !materials.canApplyTransactionDeltas(fresh.materialDeltas)) {
            _busy = false;
            return commitFail("stale_state", transactionId);
        }

        var timestamp:Number = nextTimestamp(fresh.changes);
        var valueChanges:Array = [];
        for (var i:Number = 0; i < fresh.changes.length; i++) {
            var plannedChange:Object = fresh.changes[i];
            valueChanges.push({
                slot:plannedChange.slot.slot,
                expectedItem:plannedChange.slot.item,
                expectedValue:plannedChange.slot.item.value,
                expectedLastUpdate:plannedChange.slot.item.lastUpdate,
                value:ObjectUtil.clone(plannedChange.afterValue),
                lastUpdate:timestamp
            });
        }

        if (source.sourceKind == "loadout") {
            var wornResult:Object = commitWornPlan(
                fresh, source, valueChanges, materials,
                timestamp, token, transactionId);
            _busy = false;
            return wornResult;
        }

        var bag:ArrayInventory = ArrayInventory(source.inventory);
        if (!bag.canApplyValueTransaction(valueChanges)) {
            _busy = false;
            return commitFail("stale_state", transactionId);
        }
        if (_testFailNext) {
            _testFailNext = false;
            _busy = false;
            return commitFail("commit_failed", transactionId);
        }

        // 两个容器入口均已完整预检；以下无回调提交阶段不会暴露半状态。
        if (!bag.transactionApplyValueChanges(valueChanges)) {
            _busy = false;
            return commitFail("commit_failed", transactionId);
        }
        var materialCommit:Object = materials.transactionApplyDeltas(fresh.materialDeltas);
        if (!materialCommit.success) {
            _busy = false;
            return commitFail("commit_failed", transactionId);
        }

        _writeEpoch++;
        markDirty();
        publishCommittedMaterialEffects(
            fresh, materialCommit, transactionId);
        try {
            if (fresh.achievementMetric != "") {
                AchievementMetrics.record(fresh.achievementMetric, 1);
            }
        } catch (achievementMetricError) {
            // 装备/材料权威与 receipt 已提交；可选统计失败不得阻断失效广播和回包。
            trace("[EquipmentTuningService] post-commit achievement metric failed: "
                + achievementMetricError);
        }
        for (i = 0; i < fresh.affectedSlots.length; i++) {
            try {
                InventoryPanelService.invalidateExternalSlot(
                    "背包", Number(fresh.affectedSlots[i]));
            } catch (bagInvalidationError) {
                // 领域提交和 receipt 均已闭合；可选失效通知失败不阻断其余观察者与回包。
                trace("[EquipmentTuningService] post-commit invalidation failed: "
                    + bagInvalidationError);
            }
        }
        var recoverMaterialDispatch:Function = null;
        try {
            recoverMaterialDispatch =
                EventBus.getInstance().createDispatchRecoveryToken();
            materials.publishTransactionChanges(materialCommit.changes);
        } catch (materialPublishError) {
            recoverCommittedDispatch(recoverMaterialDispatch);
            trace("[EquipmentTuningService] post-commit material publish failed: "
                + materialPublishError);
        }
        for (i = 0; i < fresh.affectedSlots.length; i++) {
            var recoverBagDispatch:Function = null;
            try {
                recoverBagDispatch =
                    EventBus.getInstance().createDispatchRecoveryToken();
                bag.publishTransactionChange(Number(fresh.affectedSlots[i]), "value");
            } catch (bagPublishError) {
                recoverCommittedDispatch(recoverBagDispatch);
                trace("[EquipmentTuningService] post-commit bag publish failed: "
                    + bagPublishError);
            }
        }

        var inventorySnapshot:Object = InventoryPanelService.buildExternalSnapshot("背包", 0, 50);
        var newSourceRef:Object = refFromInventorySnapshot(inventorySnapshot, source.slot);
        var committedSnapshot:Object = buildTuningSnapshot(
            source, newSourceRef, fresh.materials);
        var committedAfter:Object = buildCommittedAfter(fresh, timestamp, inventorySnapshot);
        _busy = false;
        return {
            success:true, transactionId:transactionId, tuningToken:token,
            canCommit:false, operation:fresh.operation, noOp:false,
            before:fresh.before, after:committedAfter,
            materials:buildCommittedMaterials(fresh.materials),
            removedMods:fresh.removedMods,
            snapshot:committedSnapshot,
            inventorySnapshots:inventorySnapshot == null ? [] : [inventorySnapshot]
        };
    }

    /**
     * 已穿戴单件调制的跨资源提交。装备栏与材料均先完整预检，再无事件写入；
     * 材料、投影或序列化预检失败时恢复两边 value/revision。只有完整回包形状已经
     * 可序列化后，才由 CharacterBuildService 的窄 hook 消费一次 loadout revision。
     */
    private static function commitWornPlan(
        plan:Object,
        source:Object,
        valueChanges:Array,
        materials:Object,
        timestamp:Number,
        token:String,
        transactionId:String):Object {
        if (plan.operation == "convert") {
            return commitWornConversionPlan(
                plan, source, valueChanges, timestamp,
                token, transactionId);
        }
        var equipment:EquipmentInventory =
            EquipmentInventory(source.inventory);
        if (equipment == null
                || typeof equipment.canApplyWornValueTransaction
                    != "function"
                || typeof equipment.transactionApplyWornValueChanges
                    != "function"
                || typeof equipment.rollbackWornValueTransaction
                    != "function"
                || typeof equipment.publishWornValueTransaction
                    != "function"
                || typeof materials.rollbackTransactionDeltas
                    != "function") {
            return commitFail("service_not_ready", transactionId);
        }
        if (!equipment.canApplyWornValueTransaction(valueChanges)
                || !materials.canApplyTransactionDeltas(
                    plan.materialDeltas)) {
            return commitFail("stale_state", transactionId);
        }

        var equipmentCommit:Object = null;
        try {
            equipmentCommit =
                equipment.transactionApplyWornValueChanges(valueChanges);
        } catch (equipmentError) {
            equipmentCommit = {success:false, rollbackComplete:false};
        }
        if (equipmentCommit == null
                || equipmentCommit.success !== true) {
            return commitFail(
                equipmentCommit != null
                    && equipmentCommit.rollbackComplete === true
                    ? "commit_failed" : "needs_reconcile",
                transactionId);
        }

        var materialCommit:Object = null;
        try {
            if (_testFailNextMaterialCommit) {
                _testFailNextMaterialCommit = false;
                materialCommit = {success:false, rollbackComplete:true};
            } else {
                materialCommit =
                    materials.transactionApplyDeltas(
                        plan.materialDeltas);
            }
        } catch (materialError) {
            materialCommit = {success:false, rollbackComplete:false};
        }
        if (materialCommit == null
                || materialCommit.success !== true) {
            var equipmentRestored:Boolean =
                equipment.rollbackWornValueTransaction(
                    equipmentCommit);
            var materialKnownClean:Boolean = materialCommit != null
                && materialCommit.rollbackComplete === true;
            return commitFail(
                equipmentRestored && materialKnownClean
                    ? "commit_failed" : "needs_reconcile",
                transactionId);
        }

        var nextLoadoutRevision:Number =
            Number(source.expectedLoadoutRevision) + 1;
        var postSource:Object = {
            sourceKind:"loadout",
            sessionGeneration:Number(source.sessionGeneration),
            slotKey:String(source.slot),
            expectedLoadoutRevision:nextLoadoutRevision
        };
        var committedSnapshot:Object = null;
        var committedAfter:Object = null;
        var response:Object = null;
        try {
            committedSnapshot =
                buildTuningSnapshot(source, postSource, plan.materials);
            var changed:Object = plan.changes[0];
            committedAfter = {
                source:{
                    source:postSource,
                    equipment:buildEquipmentProjection(
                        changed.slot.item,
                        changed.afterValue,
                        timestamp)
                }
            };
            response = {
                success:true,
                transactionId:transactionId,
                tuningToken:token,
                canCommit:false,
                operation:plan.operation,
                noOp:false,
                before:plan.before,
                after:committedAfter,
                materials:buildCommittedMaterials(plan.materials),
                removedMods:plan.removedMods,
                snapshot:committedSnapshot,
                inventorySnapshots:[]
            };
        } catch (projectionError) {
            response = null;
        }
        if (response == null || committedSnapshot == null
                || !commitProjectionSerializable(response)) {
            var projectionRollback:Boolean = rollbackWornRawCommit(
                equipment, equipmentCommit,
                materials, materialCommit);
            return commitFail(
                projectionRollback
                    ? "commit_failed" : "needs_reconcile",
                transactionId);
        }

        var synced:Object =
            org.flashNight.arki.item.CharacterBuildService
                .commitWornTuningSynchronization(
                    Number(source.sessionGeneration),
                    String(source.slot),
                    Number(source.expectedLoadoutRevision),
                    source.item);
        if (synced == null || synced.success !== true) {
            if (synced != null
                    && synced.authorityObserved === true) {
                // Character baseline 已观察 post-state；反向回滚会制造
                // baseline=post / raw=pre 的二次漂移，只能保留 authority 对账。
                publishCommittedWornSideEffects(
                    plan, materials, materialCommit,
                    equipment, equipmentCommit, transactionId);
                return commitFail(
                    "needs_reconcile", transactionId);
            }
            var hookRollback:Boolean = rollbackWornRawCommit(
                equipment, equipmentCommit,
                materials, materialCommit);
            var hookError:String = synced == null
                || synced.error == undefined
                ? "needs_reconcile" : String(synced.error);
            return commitFail(
                hookRollback && hookError != "needs_reconcile"
                    ? "commit_failed" : "needs_reconcile",
                transactionId);
        }
        if (Number(synced.loadoutRevision)
                    != nextLoadoutRevision
                || synced.liveRefreshDirty !== true) {
            // Character authority 已观察到 raw commit；此后只能通过 fresh snapshot 对账，
            // 绝不能反向伪装成确定未写。
            publishCommittedWornSideEffects(
                plan, materials, materialCommit,
                equipment, equipmentCommit, transactionId);
            return commitFail("needs_reconcile", transactionId);
        }

        publishCommittedWornSideEffects(
            plan, materials, materialCommit,
            equipment, equipmentCommit, transactionId);
        return response;
    }

    /**
     * 已穿戴装备与背包装备的强化度原子交换。
     * 两个容器都签发可回滚 receipt 后才消费一次 Character Build revision；
     * 成功回包同时携带 post-loadout source 与完整背包 snapshot。
     */
    private static function commitWornConversionPlan(
        plan:Object,
        source:Object,
        valueChanges:Array,
        timestamp:Number,
        token:String,
        transactionId:String):Object {
        var equipment:EquipmentInventory =
            EquipmentInventory(source.inventory);
        var bag:ArrayInventory = plan.target == null
            ? null : ArrayInventory(plan.target.inventory);
        if (equipment == null || bag == null
                || plan.target.sourceKind != "inventory"
                || !(valueChanges instanceof Array)
                || valueChanges.length != 2
                || typeof bag.transactionApplyValueChangesWithReceipt
                    != "function"
                || typeof bag.rollbackValueTransaction != "function"
                || typeof bag.publishValueTransaction != "function") {
            return commitFail("service_not_ready", transactionId);
        }

        var wornChanges:Array = [valueChanges[0]];
        var bagChanges:Array = [valueChanges[1]];
        if (String(wornChanges[0].slot) != String(source.slot)
                || Number(bagChanges[0].slot)
                    != Number(plan.target.slot)
                || !equipment.canApplyWornValueTransaction(wornChanges)
                || !bag.canApplyValueTransaction(bagChanges)) {
            return commitFail("stale_state", transactionId);
        }

        var equipmentCommit:Object = null;
        try {
            equipmentCommit =
                equipment.transactionApplyWornValueChanges(
                    wornChanges);
        } catch (equipmentError) {
            equipmentCommit = {success:false, rollbackComplete:false};
        }
        if (equipmentCommit == null
                || equipmentCommit.success !== true) {
            return commitFail(
                equipmentCommit != null
                    && equipmentCommit.rollbackComplete === true
                    ? "commit_failed" : "needs_reconcile",
                transactionId);
        }

        var bagCommit:Object = null;
        try {
            if (_testFailNextWornConversionBagCommit) {
                _testFailNextWornConversionBagCommit = false;
                bagCommit = {success:false, rollbackComplete:true};
            } else {
                bagCommit =
                    bag.transactionApplyValueChangesWithReceipt(
                        bagChanges);
            }
        } catch (bagError) {
            bagCommit = {success:false, rollbackComplete:false};
        }
        if (bagCommit == null || bagCommit.success !== true) {
            var equipmentRestored:Boolean = false;
            try {
                equipmentRestored =
                    equipment.rollbackWornValueTransaction(
                        equipmentCommit) === true;
            } catch (equipmentRollbackError) {
                equipmentRestored = false;
            }
            var bagKnownClean:Boolean = bagCommit != null
                && bagCommit.rollbackComplete === true;
            return commitFail(
                equipmentRestored && bagKnownClean
                    ? "commit_failed" : "needs_reconcile",
                transactionId);
        }

        var nextLoadoutRevision:Number =
            Number(source.expectedLoadoutRevision) + 1;
        var postSource:Object = {
            sourceKind:"loadout",
            sessionGeneration:Number(source.sessionGeneration),
            slotKey:String(source.slot),
            expectedLoadoutRevision:nextLoadoutRevision
        };
        var inventorySnapshot:Object = null;
        var postTarget:Object = null;
        var committedSnapshot:Object = null;
        var response:Object = null;
        try {
            inventorySnapshot =
                InventoryPanelService.buildExternalSnapshot(
                    "背包", 0, 50);
            postTarget = refFromInventorySnapshot(
                inventorySnapshot, Number(plan.target.slot));
            committedSnapshot = buildTuningSnapshot(
                source, postSource, plan.materials);
            response = {
                success:true,
                transactionId:transactionId,
                tuningToken:token,
                canCommit:false,
                operation:plan.operation,
                noOp:false,
                before:plan.before,
                after:{
                    source:{
                        source:postSource,
                        equipment:buildEquipmentProjection(
                            source.item,
                            plan.changes[0].afterValue,
                            timestamp)
                    },
                    target:{
                        source:postTarget,
                        equipment:buildEquipmentProjection(
                            plan.target.item,
                            plan.changes[1].afterValue,
                            timestamp)
                    }
                },
                materials:[],
                removedMods:[],
                snapshot:committedSnapshot,
                inventorySnapshots:inventorySnapshot == null
                    ? [] : [inventorySnapshot]
            };
        } catch (projectionError) {
            response = null;
        }
        if (response == null || inventorySnapshot == null
                || postTarget == null || committedSnapshot == null
                || !commitProjectionSerializable(response)) {
            rollbackWornConversionRawCommit(
                equipment, equipmentCommit, bag, bagCommit);
            // buildExternalSnapshot 可能已轮换目标 lease；即使 raw state 恢复，
            // Web 仍必须刷新背包，不能把它降格成确定未写。
            return commitFail("needs_reconcile", transactionId);
        }

        var synced:Object =
            org.flashNight.arki.item.CharacterBuildService
                .commitWornTuningSynchronization(
                    Number(source.sessionGeneration),
                    String(source.slot),
                    Number(source.expectedLoadoutRevision),
                    source.item);
        if (synced == null || synced.success !== true) {
            if (synced != null
                    && synced.authorityObserved === true) {
                publishCommittedWornConversionSideEffects(
                    bag, bagCommit, equipment, equipmentCommit);
                return commitFail(
                    "needs_reconcile", transactionId);
            }
            rollbackWornConversionRawCommit(
                equipment, equipmentCommit, bag, bagCommit);
            return commitFail("needs_reconcile", transactionId);
        }
        if (Number(synced.loadoutRevision)
                    != nextLoadoutRevision
                || synced.liveRefreshDirty !== true) {
            publishCommittedWornConversionSideEffects(
                bag, bagCommit, equipment, equipmentCommit);
            return commitFail("needs_reconcile", transactionId);
        }

        publishCommittedWornConversionSideEffects(
            bag, bagCommit, equipment, equipmentCommit);
        return response;
    }

    private static function rollbackWornConversionRawCommit(
        equipment:EquipmentInventory,
        equipmentCommit:Object,
        bag:ArrayInventory,
        bagCommit:Object):Boolean {
        var bagRestored:Boolean = false;
        var equipmentRestored:Boolean = false;
        try {
            bagRestored = bag.rollbackValueTransaction(
                bagCommit) === true;
        } catch (bagRollbackError) {
            bagRestored = false;
        }
        try {
            equipmentRestored =
                equipment.rollbackWornValueTransaction(
                    equipmentCommit) === true;
        } catch (equipmentRollbackError) {
            equipmentRestored = false;
        }
        return bagRestored && equipmentRestored;
    }

    private static function publishCommittedWornConversionSideEffects(
        bag:ArrayInventory,
        bagCommit:Object,
        equipment:EquipmentInventory,
        equipmentCommit:Object):Void {
        _writeEpoch++;
        try {
            markDirty();
        } catch (dirtyError) {
            // authority 已提交；保存异常由后续 reconcile/保存策略收敛。
        }
        var recoverBagValueDispatch:Function = null;
        try {
            recoverBagValueDispatch =
                EventBus.getInstance().createDispatchRecoveryToken();
            bag.publishValueTransaction(bagCommit);
        } catch (bagPublishError) {
            // 监听器异常不能反向改变已提交 authority。
            recoverCommittedDispatch(recoverBagValueDispatch);
        }
        var recoverWornConversionDispatch:Function = null;
        try {
            recoverWornConversionDispatch =
                EventBus.getInstance().createDispatchRecoveryToken();
            equipment.publishWornValueTransaction(
                equipmentCommit);
        } catch (equipmentPublishError) {
            // 同上。
            recoverCommittedDispatch(recoverWornConversionDispatch);
        }
    }

    /**
     * Character authority 已观察 raw commit 后的唯一副作用出口。
     *
     * success 与 observed-unknown 都必须恰好调用一次；在此之前的失败必须先回滚，
     * 且绝不能调用本函数。监听器/统计异常只隔离当前副作用，不能反向改变 authority。
     */
    private static function publishCommittedWornSideEffects(
        plan:Object,
        materials:Object,
        materialCommit:Object,
        equipment:EquipmentInventory,
        equipmentCommit:Object,
        transactionId:String):Void {
        _writeEpoch++;
        try {
            markDirty();
        } catch (dirtyError) {
            // authority 已提交；dirty 写异常只允许由后续 reconcile/保存策略收敛。
        }
        publishCommittedMaterialEffects(
            plan, materialCommit, transactionId);
        try {
            if (plan.achievementMetric != "") {
                AchievementMetrics.record(
                    plan.achievementMetric, 1);
            }
        } catch (achievementError) {
            // 权威已提交；统计失败不能回滚玩法状态。
        }
        var recoverWornMaterialDispatch:Function = null;
        try {
            recoverWornMaterialDispatch =
                EventBus.getInstance().createDispatchRecoveryToken();
            materials.publishTransactionChanges(
                materialCommit.changes);
        } catch (materialPublishError) {
            // 监听器只能观察完整最终状态，派发异常不改变 authority。
            recoverCommittedDispatch(recoverWornMaterialDispatch);
        }
        var recoverWornEquipmentDispatch:Function = null;
        try {
            recoverWornEquipmentDispatch =
                EventBus.getInstance().createDispatchRecoveryToken();
            equipment.publishWornValueTransaction(
                equipmentCommit);
        } catch (equipmentPublishError) {
            // 同上；未知响应通过 snapshot reconcile 收敛。
            recoverCommittedDispatch(recoverWornEquipmentDispatch);
        }
    }

    /** 已提交 authority 的可选事件失败只恢复本次同步派发深度。 */
    private static function recoverCommittedDispatch(recoverDispatch:Function):Void {
        if (recoverDispatch == null) return;
        try {
            recoverDispatch();
        } catch (recoveryError) {
            // 清理令牌本身不得取代原可选通知边界，也不得阻断权威回包。
        }
    }

    /**
     * 只投影材料事务的真实所有权变化。配件安装/拆卸/替换只是“材料栏 ↔ 装备槽”
     * 迁移，玩家始终拥有同一配件，不得伪装成获得或失去；强化石、进阶材料等
     * 不可回收消耗仍按最终 delta 发布。
     */
    private static function publishCommittedMaterialEffects(
        plan:Object, materialCommit:Object, transactionId:String):Void {
        if (materialCommit == null || !(materialCommit.changes instanceof Array)) return;
        if (plan.operation == "install_mod" || plan.operation == "replace_mod"
                || plan.operation == "detach_mod"
                || plan.operation == "detach_all_mods") return;
        var context:Object = {
            source:"equipment_tuning", reason:String(plan.operation),
            operationId:String(transactionId), mergeScope:"operation"
        };
        var assetTransaction:Object = PlayerAssetTransaction.begin(context);
        try {
            for (var i:Number = 0; i < materialCommit.changes.length; i++) {
                var change:Object = materialCommit.changes[i];
                var delta:Number = Number(change.delta);
                if (delta == 0 || isNaN(delta)) continue;
                PlayerAssetTransaction.recordEffect(
                    delta > 0 ? "gain" : "loss", "material", String(change.key),
                    Math.abs(delta), context);
            }
            PlayerAssetTransaction.commit(assetTransaction);
        } catch (effectProjectionError) {
            // 到达这里前领域权威已经提交；异常只允许丢弃尚未发布的投影 frame，
            // 不得伪造材料/装备回滚，也不得污染后续隐式物资事务。
            PlayerAssetTransaction.settleAfterException(assetTransaction, false);
            throw effectProjectionError;
        }
    }

    private static function rollbackWornRawCommit(
        equipment:EquipmentInventory,
        equipmentCommit:Object,
        materials:Object,
        materialCommit:Object):Boolean {
        var materialRestored:Boolean = false;
        var equipmentRestored:Boolean = false;
        try {
            materialRestored =
                materials.rollbackTransactionDeltas(
                    materialCommit) === true;
        } catch (materialRollbackError) {
            materialRestored = false;
        }
        try {
            equipmentRestored =
                equipment.rollbackWornValueTransaction(
                    equipmentCommit) === true;
        } catch (equipmentRollbackError) {
            equipmentRestored = false;
        }
        return materialRestored && equipmentRestored;
    }

    private static function commitProjectionSerializable(
        response:Object):Boolean {
        try {
            if (_testFailNextSerialization) {
                _testFailNextSerialization = false;
                throw "fixture_tuning_serialization";
            }
            var serializer:LiteJSON =
                _json == null ? new LiteJSON() : _json;
            serializer.stringifySafe(response);
            return true;
        } catch (serializationError) {
            return false;
        }
    }

    private static function executeTooltip(params:Object):Object {
        if (!sessionMatches(params)) return fail("view_session_expired");
        if (params.candidateKey == undefined) return fail("invalid_payload");
        var candidateKey:String = String(params.candidateKey);
        var candidate:Object = _candidateNames[candidateKey];
        if (candidate == null) return fail("unknown_candidate");
        var itemData:Object = ItemUtil.getItemData(candidate.itemName);
        if (itemData == undefined || itemData == null) return fail("item_data_missing");
        var descHTML:String = TooltipComposer.generateItemDescriptionText(itemData, null);
        var introHTML:String = TooltipComposer.generateIntroPanelContent(null, itemData, {level:1});
        var displayName:String = String(
            itemPresentation(String(candidate.itemName)).displayName);
        // wire 由 sendResponse 的 stringifySafe 统一转义；保留原始 htmlText 双引号属性。
        var response:Object = {success:true, candidateKey:candidateKey,
            // 分段字段是 Web 富注释自动分栏的唯一权威输入。
            introHTML:introHTML, descHTML:descHTML,
            itemType:String(itemData.type), itemUse:String(itemData.use),
            text:displayName};
        // 候选试算：规则允许装上当前装备时附 before/after 属性投影，
        // 供 Web 在注释图片栏渲染属性 diff；材料缺失不阻挡试算（便于规划），
        // 零写且任何输入异常都回落为无 stats 的旧形态
        var statPreview:Object = buildCandidateStatPreview(candidate, params);
        if (statPreview != null) {
            response.statsBefore = statPreview.before;
            response.statsAfter = statPreview.after;
        }
        return response;
    }

    private static function buildCandidateStatPreview(candidate:Object, params:Object):Object {
        if (params == null || params.source == undefined) return null;
        var resolved:Object = resolveWebSlot(params.source);
        if (!resolved.success) return null;
        var item:BaseItem = BaseItem(resolved.item);
        var itemData:Object = item.getData();
        var value:Object = item.value;
        var afterValue:Object = ObjectUtil.clone(value);
        if (candidate.kind == "mod") {
            var modName:String = String(candidate.itemName);
            if (indexOfString(value.mods, modName) >= 0) return null;
            if (Number(EquipmentUtil.isModMaterialAvailable(item, itemData, modName)) != 1) return null;
            afterValue.mods = cloneArray(value.mods);
            afterValue.mods.push(modName);
        } else if (candidate.kind == "tier") {
            var tierMaterial:String = String(candidate.itemName);
            if (!isTierTransitionAllowed(item, tierMaterial)) return null;
            var tierName:String = String(EquipmentUtil.tierMaterialToNameDict[tierMaterial]);
            if (tierName == "" || tierName == "undefined") return null;
            afterValue.tier = tierName;
        } else return null;
        return {
            before:EquipmentStatProjector.project(String(item.name), value),
            after:EquipmentStatProjector.project(String(item.name), afterValue)
        };
    }

    /**
     * Host 在 tuning view 卸载前发送的生命周期屏障。只撤销匹配当前 session 的
     * 临时候选与 token，不写装备/材料；重复 detach 同一已失效 session 仍成功。
     */
    private static function executeDetach(params:Object):Object {
        if (params.panelInstanceId == undefined || params.viewSessionId == undefined) {
            return fail("invalid_session");
        }
        var panel:String = String(params.panelInstanceId);
        var view:String = String(params.viewSessionId);
        if (panel == "" || view == "") return fail("invalid_session");
        if (_sessionPanel == "" && _sessionView == "") return {success:true};
        if (panel != _sessionPanel || view != _sessionView) return fail("view_session_expired");
        revokeActivePlan();
        _candidateNames = {};
        _sessionPanel = "";
        _sessionView = "";
        _sessionGeneration++;
        return {success:true};
    }

    private static function buildPlan(operation:String,
                                      source:Object,
                                      target:Object,
                                      candidateName:String,
                                      replaceCandidateName:String,
                                      targetLevel):Object {
        if (!source.success) return source;
        var sourceItem:BaseItem = BaseItem(source.item);
        var sourceValue:Object = sourceItem.value;
        var afterSource:Object = ObjectUtil.clone(sourceValue);
        var afterTarget:Object = null;
        var materialDeltas:Object = {};
        var achievementMetric:String = "";
        var removedMods:Array = [];
        var noOp:Boolean = false;
        var fingerprint:String = baseRuleFingerprint();

        if (operation == "enhance") {
            if (!isWholeNumber(targetLevel)) return fail("invalid_target");
            var requestedLevel:Number = Number(targetLevel);
            var currentLevel:Number = Number(sourceValue.level);
            var cap:Number = getEnhancementCap();
            if (requestedLevel <= currentLevel || requestedLevel > cap) return fail("invalid_target");
            var cost:Number = calculateEnhancementCost(currentLevel, requestedLevel);
            materialDeltas["强化石"] = -cost;
            afterSource.level = requestedLevel;
            achievementMetric = "装备强化次数";
            fingerprint += "|cap=" + cap + "|cost=" + cost;
        } else if (operation == "convert") {
            if (target == null || !target.success) return fail("invalid_target");
            if (source.sourceKind == "inventory") {
                if (target.sourceKind != "inventory"
                        || source.inventory !== target.inventory) {
                    return fail("invalid_target");
                }
                if (source.slot == target.slot) return fail("same_slot");
            } else if (source.sourceKind == "loadout") {
                if (target.sourceKind != "inventory"
                        || source.inventory === target.inventory) {
                    return fail("invalid_target");
                }
            } else return fail("invalid_target");
            var sourceRaw:Object = ItemUtil.getRawItemData(sourceItem.name);
            var targetRaw:Object = ItemUtil.getRawItemData(target.item.name);
            if (sourceRaw == null || targetRaw == null || String(sourceRaw.use) != String(targetRaw.use)) {
                return fail("different_use");
            }
            afterTarget = ObjectUtil.clone(target.item.value);
            var sourceLevel:Number = Number(sourceValue.level);
            var otherLevel:Number = Number(target.item.value.level);
            if (sourceLevel == otherLevel) noOp = true;
            else {
                afterSource.level = otherLevel;
                afterTarget.level = sourceLevel;
            }
        } else if (operation == "install_tier") {
            if (candidateName == "" || !isTierTransitionAllowed(sourceItem, candidateName)) {
                return fail("invalid_transition");
            }
            materialDeltas[candidateName] = -1;
            var tierName:String = String(EquipmentUtil.tierMaterialToNameDict[candidateName]);
            if (tierName == "" || tierName == "undefined") return fail("unknown_candidate");
            afterSource.tier = tierName;
            achievementMetric = "装备进阶次数";
            fingerprint += "|tier=" + candidateName + ">" + tierName;
        } else if (operation == "install_mod") {
            if (candidateName == "") return fail("unknown_candidate");
            var itemData:Object = sourceItem.getData();
            var availability:Number = Number(EquipmentUtil.isModMaterialAvailable(sourceItem, itemData, candidateName));
            if (availability != 1) return fail("mod_unavailable");
            materialDeltas[candidateName] = -1;
            afterSource.mods = cloneArray(sourceValue.mods);
            afterSource.mods.push(candidateName);
            achievementMetric = "配件安装次数";
            fingerprint += "|mod=" + candidateName + "|availability=" + availability;
        } else if (operation == "replace_mod") {
            if (candidateName == "" || replaceCandidateName == ""
                    || candidateName == replaceCandidateName) return fail("invalid_payload");
            var replacementDetach:Object = buildDetachPlan(sourceItem, replaceCandidateName);
            if (!replacementDetach.success) return replacementDetach;
            var replacementValue:Object = ObjectUtil.clone(sourceValue);
            replacementValue.mods = cloneArray(replacementDetach.remainingMods);
            var replacementProbe:BaseItem = new BaseItem(sourceItem.name, replacementValue, sourceItem.lastUpdate);
            var replacementData:Object = replacementProbe.getData();
            var replacementAvailability:Number = Number(
                EquipmentUtil.isModMaterialAvailable(replacementProbe, replacementData, candidateName));
            if (replacementAvailability != 1) return fail("mod_unavailable");
            afterSource.mods = cloneArray(replacementDetach.remainingMods);
            afterSource.mods.push(candidateName);
            removedMods = replacementDetach.removedMods;
            addReturnedMaterials(materialDeltas, removedMods);
            addMaterialDelta(materialDeltas, candidateName, -1);
            achievementMetric = "配件安装次数";
            fingerprint += "|replace=" + replaceCandidateName + ">" + candidateName
                + "|" + removedMods.join(",") + "|" + replacementDetach.policy
                + "|availability=" + replacementAvailability;
        } else if (operation == "detach_mod") {
            var detach:Object = buildDetachPlan(sourceItem, candidateName);
            if (!detach.success) return detach;
            afterSource.mods = detach.remainingMods;
            removedMods = detach.removedMods;
            addReturnedMaterials(materialDeltas, removedMods);
            fingerprint += "|detach=" + candidateName + "|" + removedMods.join(",") + "|" + detach.policy;
        } else if (operation == "detach_all_mods") {
            if (!(sourceValue.mods instanceof Array) || sourceValue.mods.length == 0) return fail("mod_not_installed");
            removedMods = cloneArray(sourceValue.mods);
            afterSource.mods = [];
            addReturnedMaterials(materialDeltas, removedMods);
            fingerprint += "|detach_all=" + removedMods.join(",");
        } else return fail("unsupported_operation");

        if (!noOp) {
            var sourceValidation:Object = validatePlannedEquipment(
                source, sourceItem, afterSource);
            if (!sourceValidation.success) return sourceValidation;
            if (afterTarget != null) {
                var targetValidation:Object = validatePlannedEquipment(
                    target, BaseItem(target.item), afterTarget);
                if (!targetValidation.success) return targetValidation;
            }
        }

        var materials:Object = getMaterialCollection();
        if (materials == null) return fail("condition_failed");
        var materialProjection:Object = buildMaterialPlan(materials, materialDeltas);
        if (!materialProjection.success) return materialProjection;

        var changes:Array = [];
        if (!noOp) {
            changes.push({slot:source, afterValue:afterSource});
            if (afterTarget != null) changes.push({slot:target, afterValue:afterTarget});
        }
        var before:Object = {source:{source:safeSourceRef(source), equipment:buildEquipmentProjection(source.item, sourceValue, source.item.lastUpdate, true)}};
        var after:Object = {source:{source:safeSourceRef(source), equipment:buildEquipmentProjection(source.item, afterSource, source.item.lastUpdate, true)}};
        var affectedSlots:Array = noOp ? [] : [source.slot];
        if (target != null) {
            before.target = {source:safeSourceRef(target), equipment:buildEquipmentProjection(target.item, target.item.value, target.item.lastUpdate, true)};
            after.target = {source:safeSourceRef(target), equipment:buildEquipmentProjection(target.item, afterTarget, target.item.lastUpdate, true)};
            if (!noOp) affectedSlots.push(target.slot);
        }
        return {
            success:true, operation:operation, source:source, target:target,
            candidateName:candidateName, replaceCandidateName:replaceCandidateName,
            targetLevel:targetLevel, noOp:noOp,
            before:before, after:after, materialDeltas:materialDeltas,
            materials:materialProjection.materials, changes:changes,
            removedMods:removedMods, affectedSlots:affectedSlots,
            achievementMetric:achievementMetric, ruleFingerprint:fingerprint
        };
    }

    private static function buildDetachPlan(item:BaseItem, candidateName:String):Object {
        var mods:Array = item.value.mods;
        if (!(mods instanceof Array) || candidateName == "") return fail("invalid_mods");
        var index:Number = indexOfString(mods, candidateName);
        if (index < 0) return fail("mod_not_installed");
        var dependentMods:Array = EquipmentUtil.getDependentMods(item, candidateName);
        var removed:Array = [];
        var remaining:Array = [];
        var policy:String = "single";
        var i:Number;
        if (dependentMods != null && dependentMods.length > 0) {
            // 冻结玩法语义：目标 + 一跳直接依赖；不递归扩闭包。
            policy = "direct_dependents";
            var removeSet:Object = {};
            removeSet[candidateName] = true;
            for (i = 0; i < dependentMods.length; i++) removeSet[String(dependentMods[i])] = true;
            for (i = 0; i < mods.length; i++) {
                if (removeSet[String(mods[i])] == true) removed.push(String(mods[i]));
                else remaining.push(String(mods[i]));
            }
        } else {
            var modData:Object = EquipmentUtil.modDict == null ? null : EquipmentUtil.modDict[candidateName];
            if (modData != null && String(modData.detachPolicy) == "cascade") {
                policy = "cascade_all";
                removed = cloneArray(mods);
                remaining = [];
            } else {
                removed.push(candidateName);
                remaining = cloneArray(mods);
                remaining.splice(index, 1);
            }
        }
        return {success:true, removedMods:removed, remainingMods:remaining, policy:policy};
    }

    private static function installPlan(plan:Object):Void {
        _tokenSeq++;
        _transactionSeq++;
        plan.tuningToken = "tune." + _sessionGeneration + "." + _tokenSeq + "." + getTimer();
        plan.transactionId = "tune.tx." + _transactionSeq;
        plan.createdAt = getTimer();
        plan.sessionPanel = _sessionPanel;
        plan.sessionView = _sessionView;
        plan.sessionGeneration = _sessionGeneration;
        _plan = plan;
        rememberTokenTransaction(plan.tuningToken, plan.transactionId);
    }

    private static function revokeActivePlan():Void {
        if (_plan != null && _plan.tuningToken != undefined) {
            delete _tokenTransactions[String(_plan.tuningToken)];
        }
        _plan = null;
    }

    private static function buildPreviewResponse(plan:Object):Object {
        return {
            success:true, canCommit:true,
            tuningToken:plan.tuningToken,
            operation:plan.operation, noOp:plan.noOp,
            before:plan.before, after:plan.after, materials:plan.materials,
            removedMods:plan.removedMods
        };
    }

    private static function plansEqual(expected:Object, current:Object):Boolean {
        return expected.operation == current.operation
            && expected.candidateName == current.candidateName
            && expected.replaceCandidateName == current.replaceCandidateName
            && String(expected.targetLevel) == String(current.targetLevel)
            && expected.noOp == current.noOp
            && expected.achievementMetric == current.achievementMetric
            && expected.ruleFingerprint == current.ruleFingerprint
            && deepEqual(expected.before, current.before, 0)
            && deepEqual(expected.after, current.after, 0)
            && deepEqual(expected.materials, current.materials, 0)
            && deepEqual(expected.materialDeltas, current.materialDeltas, 0)
            && deepEqual(expected.removedMods, current.removedMods, 0)
            && deepEqual(expected.affectedSlots, current.affectedSlots, 0);
    }

    private static function buildTuningSnapshot(
            source:Object, sourceRef:Object,
            requiredMaterials:Array):Object {
        if (source == null || source.item == null) return null;
        var materials:Object = getMaterialCollection();
        if (materials == null) return null;
        var item:BaseItem = BaseItem(source.item);
        var tierCandidates:Array = [];
        var modCandidates:Array = [];
        var materialNames:Object = {};
        materialNames["强化石"] = true;
        var nextCandidates:Object = {};

        var tierList:Array = EquipmentUtil.getAvailableTierMaterials(item);
        var tierSeen:Object = {};
        for (var i:Number = 0; i < tierList.length; i++) {
            var tierMaterial:String = String(tierList[i]);
            if (tierSeen[tierMaterial] == true) continue;
            tierSeen[tierMaterial] = true;
            var tierKey:String = "tier." + tierCandidates.length;
            var tierAllowed:Boolean = isTierTransitionAllowed(item, tierMaterial);
            var tierOwned:Number = materials.getValue(tierMaterial);
            var tierPresentation:Object = itemPresentation(tierMaterial);
            nextCandidates[tierKey] = {kind:"tier", itemName:tierMaterial};
            materialNames[tierMaterial] = true;
            tierCandidates.push({
                candidateKey:tierKey, itemName:tierMaterial,
                displayName:tierPresentation.displayName, icon:tierPresentation.icon,
                tierName:String(EquipmentUtil.tierMaterialToNameDict[tierMaterial]),
                owned:tierOwned, available:tierAllowed && tierOwned > 0,
                reason:tierAllowed ? (tierOwned > 0 ? "" : "material_missing") : "tier_transition_rejected"
            });
        }

        var availableMods:Array = EquipmentUtil.getAvailableModMaterials(item);
        var modSeen:Object = {};
        var modKeys:Object = {};
        var itemData:Object = item.getData();
        for (i = 0; i < availableMods.length; i++) {
            var modName:String = String(availableMods[i]);
            if (modSeen[modName] == true) continue;
            modSeen[modName] = true;
            var modKey:String = "mod." + modCandidates.length;
            modKeys[modName] = modKey;
            var availability:Number = Number(EquipmentUtil.isModMaterialAvailable(item, itemData, modName));
            var modOwned:Number = materials.getValue(modName);
            nextCandidates[modKey] = {kind:"mod", itemName:modName};
            materialNames[modName] = true;
            modCandidates.push(buildModCandidateProjection(
                modKey, modName, modOwned, indexOfString(item.value.mods, modName) >= 0,
                availability == 1 && modOwned > 0, availability,
                availability == 1 ? (modOwned > 0 ? "" : "material_missing") : modAvailabilityReason(availability)
            ));
        }

        // 历史已安装插件即使退出当前候选池，仍必须可被 detach_mod 精确引用。
        for (i = 0; i < item.value.mods.length; i++) {
            modName = String(item.value.mods[i]);
            modKey = modKeys[modName];
            if (modKey == undefined) {
                modKey = "mod." + modCandidates.length;
                modKeys[modName] = modKey;
            }
            nextCandidates[modKey] = {kind:"mod", itemName:modName};
            materialNames[modName] = true;
            if (modSeen[modName] != true) {
                modSeen[modName] = true;
                modCandidates.push(buildModCandidateProjection(
                    modKey, modName, materials.getValue(modName), true,
                    false, -2, modAvailabilityReason(-2)
                ));
            }
        }

        // 提交后已卸下的历史插件可能不再属于当前候选池；
        // post snapshot 仍必须证明本次所有材料终值与展示身份。
        if (requiredMaterials != undefined && requiredMaterials != null) {
            for (i = 0; i < requiredMaterials.length; i++) {
                var requiredName:String = String(
                    requiredMaterials[i].itemName);
                materialNames[requiredName] = true;
            }
        }

        // 逐个模拟“先拆旧件、再装新件”的最终状态，只投影可原子替换的旧件键。
        for (i = 0; i < modCandidates.length; i++) {
            var replacementProjection:Object = modCandidates[i];
            if (replacementProjection.installed == true) continue;
            for (var installedIndex:Number = 0; installedIndex < item.value.mods.length; installedIndex++) {
                var installedName:String = String(item.value.mods[installedIndex]);
                if (canReplaceMod(item, installedName, String(replacementProjection.itemName))) {
                    replacementProjection.replaceableFrom.push(String(modKeys[installedName]));
                }
            }
        }
        _candidateNames = nextCandidates;

        var names:Array = [];
        for (var materialName:String in materialNames) names.push(materialName);
        names.sort();
        var materialSnapshot:Array = [];
        for (i = 0; i < names.length; i++) {
            var materialPresentation:Object = itemPresentation(String(names[i]));
            materialSnapshot.push({
                itemName:names[i],
                displayName:materialPresentation.displayName,
                icon:materialPresentation.icon,
                count:materials.getValue(names[i])
            });
        }
        var level:Number = Number(item.value.level);
        var cap:Number = getEnhancementCap();
        var hardCap:Number = EquipmentUtil.getMaxLevel();
        return {
            gender:buildGender(),
            source:sourceRef,
            equipment:buildEquipmentProjection(item, item.value, item.lastUpdate),
            enhance:{currentLevel:level, maxLevel:cap, availableMaxLevel:cap, hardMaxLevel:hardCap},
            tierCandidates:tierCandidates, modCandidates:modCandidates,
            materials:materialSnapshot,
            materialRevision:materials.getMutationRevision(),
            inventoryRevision:source.inventory.getMutationRevision()
        };
    }

    private static function buildGender():String {
        return String(_root.性别) == "女" ? "女" : "男";
    }

    private static function buildEquipmentProjection(item:Object, value:Object, lastUpdate:Number, includeStats:Boolean):Object {
        var raw:Object = ItemUtil.getRawItemData(item.name);
        // preview 的 after 必须从传入 value 重算；直接读取 item.getData() 会把
        // 替换前的等级需求与配件槽容量泄漏进 after 投影。
        var projectionProbe:BaseItem = new BaseItem(
            String(item.name), ObjectUtil.clone(value), lastUpdate);
        var data:Object = projectionProbe.getData();
        // 唯一 legacy metadata 适配点：Host/Web 只消费完整三元身份，绝不再猜内部名。
        var presentation:Object = itemPresentation(String(item.name));
        var modSlotCapacity:Number = 0;
        var modSlotCapacityKnown:Boolean = data != null
            && data.data != undefined && data.data != null
            && data.data.hasOwnProperty("modslot")
            && data.data.modslot != undefined;
        if (modSlotCapacityKnown) {
            var rawModSlotCapacity:Number = Number(data.data.modslot);
            if (isNaN(rawModSlotCapacity)
                    || rawModSlotCapacity == Number.POSITIVE_INFINITY
                    || rawModSlotCapacity == Number.NEGATIVE_INFINITY
                    || rawModSlotCapacity < 0
                    || Math.floor(rawModSlotCapacity) != rawModSlotCapacity) {
                modSlotCapacityKnown = false;
            } else {
                modSlotCapacity = rawModSlotCapacity;
            }
        }
        var projection:Object = {
            name:String(item.name),
            displayName:String(presentation.displayName),
            icon:String(presentation.icon),
            type:raw == null || raw.type == undefined ? "" : String(raw.type),
            use:raw == null || raw.use == undefined ? "" : String(raw.use),
            level:Number(value.level),
            tier:value.tier == undefined || value.tier == null ? "" : String(value.tier),
            mods:cloneArray(value.mods), lastUpdate:Number(lastUpdate),
            maxLevel:getEnhancementCap(), hardMaxLevel:EquipmentUtil.getMaxLevel()
        };
        if (modSlotCapacityKnown) {
            projection.modSlotCapacity = modSlotCapacity;
        }
        // preview 的 before/after 附带结构化属性投影，供 Web 端做前后对比；
        // snapshot 不传 includeStats，保持载荷最小
        if (includeStats) {
            projection.stats = EquipmentStatProjector.project(String(item.name), value);
        }
        return projection;
    }

    private static function buildMaterialPlan(materials:Object, deltas:Object):Object {
        if (!materials.canApplyTransactionDeltas(deltas)) return fail("insufficient_material");
        var names:Array = [];
        for (var key:String in deltas) names.push(key);
        names.sort();
        var result:Array = [];
        for (var i:Number = 0; i < names.length; i++) {
            var before:Number = materials.getValue(names[i]);
            var delta:Number = Number(deltas[names[i]]);
            var presentation:Object = itemPresentation(String(names[i]));
            result.push({
                itemName:names[i],
                displayName:presentation.displayName,
                icon:presentation.icon,
                before:before,
                delta:delta,
                after:before + delta
            });
        }
        return {success:true, materials:result};
    }

    private static function buildCommittedMaterials(materials:Array):Array {
        var result:Array = [];
        for (var i:Number = 0; i < materials.length; i++) {
            var row:Object = materials[i];
            result.push({
                itemName:row.itemName,
                displayName:row.displayName,
                icon:row.icon,
                before:row.before,
                delta:row.delta,
                after:row.after
            });
        }
        return result;
    }

    private static function buildCommittedAfter(plan:Object, timestamp:Number, inventorySnapshot:Object):Object {
        var result:Object = {};
        for (var i:Number = 0; i < plan.changes.length; i++) {
            var change:Object = plan.changes[i];
            var key:String = change.slot.slot == plan.source.slot ? "source" : "target";
            result[key] = {
                source:refFromInventorySnapshot(inventorySnapshot, change.slot.slot),
                equipment:buildEquipmentProjection(change.slot.item, change.afterValue, timestamp)
            };
        }
        return result;
    }

    private static function resolveWebSlot(ref:Object):Object {
        if (ref == null || typeof ref != "object"
                || typeof ref.sourceKind != "string") {
            return fail("invalid_payload");
        }
        var sourceKind:String = String(ref.sourceKind);
        if (sourceKind == "inventory") {
            return resolveWebInventorySlot(ref);
        }
        if (sourceKind == "loadout") {
            return resolveWebLoadoutSlot(ref);
        }
        return fail("invalid_payload");
    }

    private static function resolveWebInventorySlot(ref:Object):Object {
        if (!hasExactKeys(ref, _inventorySourceKeys)
                || typeof ref.containerId != "string"
                || typeof ref.slot != "number"
                || typeof ref.expectedLease != "string"
                || String(ref.expectedLease) == "") {
            return fail("invalid_payload");
        }
        var checked:Object =
            InventoryPanelService.validateExternalSlotRef({
                containerId:String(ref.containerId),
                slot:Number(ref.slot),
                expectedLease:String(ref.expectedLease)
            }, false);
        if (!checked.success) return checked;
        if (checked.containerId != "背包") return fail("container_forbidden");
        var valid:Object = validateEquipment(checked.item);
        if (!valid.success) return valid;
        checked.sourceKind = "inventory";
        checked.ref = {
            sourceKind:"inventory",
            containerId:"背包",
            slot:checked.slot,
            expectedLease:String(ref.expectedLease)
        };
        checked.expectedValue = ObjectUtil.clone(checked.item.value);
        checked.expectedLastUpdate = Number(checked.item.lastUpdate);
        return checked;
    }

    private static function resolveWebLoadoutSlot(ref:Object):Object {
        if (!hasExactKeys(ref, _loadoutSourceKeys)
                || typeof ref.sessionGeneration != "number"
                || typeof ref.slotKey != "string"
                || String(ref.slotKey) == ""
                || typeof ref.expectedLoadoutRevision != "number"
                || !isWholeNumber(ref.sessionGeneration)
                || !isWholeNumber(ref.expectedLoadoutRevision)) {
            return fail("invalid_payload");
        }
        var resolved:Object =
            org.flashNight.arki.item.CharacterBuildService
                .resolveWornTuningSource(
                    Number(ref.sessionGeneration),
                    String(ref.slotKey),
                    Number(ref.expectedLoadoutRevision));
        if (resolved == null || resolved.success !== true) {
            // CharacterBuildService 的失败对象携带会话状态等内部键，直接上线会越出
            // 调制域响应白名单（Host 判 malformed_response）；只投影 error 出站。
            if (resolved == null) return fail("service_not_ready");
            var sourceError:String = String(resolved.error);
            return fail(sourceError == "" || sourceError == "undefined" ? "stale_state" : sourceError);
        }
        var valid:Object = validateEquipment(resolved.item);
        if (!valid.success) return valid;
        return {
            success:true,
            sourceKind:"loadout",
            inventory:resolved.inventory,
            slot:String(resolved.slotKey),
            item:resolved.item,
            sessionGeneration:Number(resolved.sessionGeneration),
            expectedLoadoutRevision:Number(resolved.loadoutRevision),
            ref:{
                sourceKind:"loadout",
                sessionGeneration:Number(resolved.sessionGeneration),
                slotKey:String(resolved.slotKey),
                expectedLoadoutRevision:
                    Number(resolved.loadoutRevision)
            },
            expectedValue:ObjectUtil.clone(resolved.item.value),
            expectedLastUpdate:Number(resolved.item.lastUpdate)
        };
    }

    private static function revalidateSlot(previous:Object):Object {
        var current:Object = resolveWebSlot(previous.ref);
        if (!current.success) return current;
        if (current.item !== previous.item
                || Number(current.item.lastUpdate) != Number(previous.expectedLastUpdate)
                || !deepEqual(previous.expectedValue, current.item.value, 0)) return fail("stale_state");
        return current;
    }

    private static function validateEquipment(item:Object):Object {
        if (item == null || item.value == null || typeof item.value != "object") return fail("invalid_equipment");
        var raw:Object = ItemUtil.getRawItemData(item.name);
        if (raw == null || (raw.type != "武器" && raw.type != "防具")) return fail("invalid_equipment");
        var level:Number = Number(item.value.level);
        if (isNaN(level) || Math.floor(level) != level || level < 1) return fail("invalid_equipment");
        if (!(item.value.mods instanceof Array)) return fail("invalid_mods");
        return {success:true};
    }

    /**
     * 只在调制写计划上验证最终态；存档加载与既有非法装备保持原样。
     * 背包装备可高于玩家等级，已穿戴装备则必须继续满足 Character Build
     * 使用的有效等级门。所有写入都必须落在最终有效配件槽容量内。
     */
    private static function validatePlannedEquipment(slot:Object,
                                                      item:BaseItem,
                                                      value:Object):Object {
        var probe:BaseItem = new BaseItem(
            item.name, ObjectUtil.clone(value), item.lastUpdate);
        var shape:Object = validateEquipment(probe);
        if (!shape.success) return shape;

        var itemData:Object = probe.getData();
        if (itemData == null || itemData.data == null
                || typeof itemData.data != "object"
                || !finiteNumber(itemData.data.level)) {
            return fail("invalid_equipment");
        }

        var rawCapacity = itemData.data.modslot;
        var capacity:Number = Number(rawCapacity);
        if (rawCapacity == undefined || isNaN(capacity)
                || capacity == Number.POSITIVE_INFINITY
                || capacity == Number.NEGATIVE_INFINITY
                || capacity < 0 || Math.floor(capacity) != capacity) {
            return fail("invalid_equipment");
        }
        if (probe.value.mods.length > capacity) {
            return fail("mod_unavailable");
        }

        if (slot != null && slot.sourceKind == "loadout") {
            if (!finiteNumber(_root.等级)) return fail("invalid_equipment");
            if (Number(itemData.data.level) > Number(_root.等级)) {
                return fail("level_locked");
            }
        }
        return {success:true};
    }

    private static function finiteNumber(value):Boolean {
        return typeof value == "number" && !isNaN(value)
            && value != Number.POSITIVE_INFINITY
            && value != Number.NEGATIVE_INFINITY;
    }

    private static function safeSourceRef(slot:Object):Object {
        if (slot == null) return null;
        if (slot.sourceKind == "loadout") {
            return {
                sourceKind:"loadout",
                sessionGeneration:Number(slot.sessionGeneration),
                slotKey:String(slot.slot),
                expectedLoadoutRevision:
                    Number(slot.expectedLoadoutRevision)
            };
        }
        var ref:Object = {
            sourceKind:"inventory",
            containerId:"背包",
            slot:Number(slot.slot)
        };
        if (slot.ref != null
                && slot.ref.expectedLease != undefined) {
            ref.expectedLease =
                String(slot.ref.expectedLease);
        }
        return ref;
    }

    private static function refFromInventorySnapshot(snapshot:Object, slot:Number):Object {
        if (snapshot == null || !(snapshot.slots instanceof Array)) {
            return {
                sourceKind:"inventory",
                containerId:"背包",
                slot:slot
            };
        }
        for (var i:Number = 0; i < snapshot.slots.length; i++) {
            var row:Object = snapshot.slots[i];
            if (Number(row.physicalSlot) == Number(slot)) {
                return {
                    sourceKind:"inventory",
                    containerId:"背包",
                    slot:Number(slot),
                    expectedLease:String(row.slotLease)
                };
            }
        }
        return {
            sourceKind:"inventory",
            containerId:"背包",
            slot:Number(slot)
        };
    }

    private static function isTierTransitionAllowed(item:BaseItem, materialName:String):Boolean {
        if (!EquipmentUtil.isTierMaterialAvailable(item, materialName)) return false;
        var nextTier:String = String(EquipmentUtil.tierMaterialToNameDict[materialName]);
        if (nextTier == "" || nextTier == "undefined") return false;
        var currentTier:String = item.value.tier == undefined || item.value.tier == null ? "" : String(item.value.tier);
        if (currentTier == "") return nextTier != "三阶" && nextTier != "四阶";
        if (currentTier == "二阶") return nextTier == "三阶";
        if (currentTier == "三阶") return nextTier == "四阶";
        return false;
    }

    private static function getEnhancementCap():Number {
        var progress:Number = Number(_root.主线任务进度);
        if (isNaN(progress)) progress = 0;
        if (progress > 129) return 13;
        var cap:Number = progress > 74 ? 9 : 7;
        var smith:Object = _root.主角被动技能 == undefined ? null : _root.主角被动技能.铁匠;
        if (smith != null && smith.启用 == true && Number(smith.等级) >= 10) cap++;
        return cap;
    }

    private static function calculateEnhancementCost(currentLevel:Number, targetLevel:Number):Number {
        var multiplier:Number = 1;
        var smith:Object = _root.主角被动技能 == undefined ? null : _root.主角被动技能.铁匠;
        if (smith != null && smith.启用 == true) multiplier = Math.max(1 - Number(smith.等级) * 0.05, 0);
        var cost:Number = 0;
        for (var i:Number = currentLevel; i < targetLevel; i++) {
            cost += Math.floor(multiplier * (i - 1) * (i - 1) * (i - 1) + 1);
        }
        return cost;
    }

    private static function baseRuleFingerprint():String {
        var progress:Number = Number(_root.主线任务进度);
        if (isNaN(progress)) progress = 0;
        var smith:Object = _root.主角被动技能 == undefined ? null : _root.主角被动技能.铁匠;
        var enabled:Boolean = smith != null && smith.启用 == true;
        var level:Number = smith == null ? 0 : Number(smith.等级);
        if (isNaN(level)) level = 0;
        return "progress=" + progress + "|smith=" + enabled + ":" + level;
    }

    private static function addReturnedMaterials(deltas:Object, names:Array):Void {
        for (var i:Number = 0; i < names.length; i++) {
            var name:String = String(names[i]);
            addMaterialDelta(deltas, name, 1);
        }
    }

    private static function addMaterialDelta(deltas:Object, itemName:String, delta:Number):Void {
        var current:Number = Number(deltas[itemName]);
        if (isNaN(current)) current = 0;
        deltas[itemName] = current + delta;
    }

    private static function canReplaceMod(item:BaseItem,
            installedName:String, candidateName:String):Boolean {
        if (installedName == "" || candidateName == "" || installedName == candidateName) return false;
        var detach:Object = buildDetachPlan(item, installedName);
        if (!detach.success) return false;
        var probeValue:Object = ObjectUtil.clone(item.value);
        probeValue.mods = cloneArray(detach.remainingMods);
        var probe:BaseItem = new BaseItem(item.name, probeValue, item.lastUpdate);
        return Number(EquipmentUtil.isModMaterialAvailable(
            probe, probe.getData(), candidateName)) == 1;
    }

    private static function getMaterialCollection():Object {
        if (_root.收集品栏 == undefined || _root.收集品栏.材料 == null) return null;
        var collection:Object = _root.收集品栏.材料;
        if (collection.isDict != true
                || typeof collection.getValue != "function"
                || typeof collection.canApplyTransactionDeltas != "function"
                || typeof collection.transactionApplyDeltas != "function") return null;
        return collection;
    }

    private static function nextTimestamp(changes:Array):Number {
        var timestamp:Number = new Date().getTime();
        for (var i:Number = 0; i < changes.length; i++) {
            var oldTimestamp:Number = Number(changes[i].slot.item.lastUpdate);
            if (!isNaN(oldTimestamp) && timestamp <= oldTimestamp) timestamp = oldTimestamp + 1;
        }
        return timestamp;
    }

    private static function activateWebSession(params:Object):Object {
        if (params.panelInstanceId == undefined || params.viewSessionId == undefined) return fail("invalid_session");
        var panel:String = String(params.panelInstanceId);
        var view:String = String(params.viewSessionId);
        if (panel == "" || view == "") return fail("invalid_session");
        if (panel != _sessionPanel || view != _sessionView) {
            revokeActivePlan();
            _sessionPanel = panel;
            _sessionView = view;
            _sessionGeneration++;
            _candidateNames = {};
        }
        return {success:true};
    }

    private static function sessionMatches(params:Object):Boolean {
        return params != null && params.panelInstanceId != undefined && params.viewSessionId != undefined
            && String(params.panelInstanceId) == _sessionPanel && String(params.viewSessionId) == _sessionView;
    }

    private static function decorateResponse(response:Object, commandName:String, params:Object):Object {
        if (response == null) response = fail("internal_error");
        response.v = 1;
        response.command = commandName;
        response.writeEpoch = params != null && isWholeNumber(params.writeEpoch)
            ? Number(params.writeEpoch) : _writeEpoch;
        if (params != null) {
            if (params.panelInstanceId != undefined) response.panelInstanceId = String(params.panelInstanceId);
            if (params.viewSessionId != undefined) response.viewSessionId = String(params.viewSessionId);
            if (params.reconcileAfterCallId != undefined && response.reconcileAfterCallId == undefined) {
                response.reconcileAfterCallId = String(params.reconcileAfterCallId);
            }
        }
        return response;
    }

    private static function commitFail(errorCode:String, transactionId:String):Object {
        var response:Object = fail(errorCode);
        if (transactionId != "" && transactionId != "undefined") response.transactionId = transactionId;
        return response;
    }

    private static function tokenTransaction(params:Object):String {
        if (params == null || params.expectedTuningToken == undefined) return "";
        var value:Object = _tokenTransactions[String(params.expectedTuningToken)];
        return value == undefined ? "" : String(value);
    }

    private static function rememberTokenTransaction(token:String, transactionId:String):Void {
        _tokenTransactions[token] = transactionId;
        _tokenTransactionOrder.push(token);
        while (_tokenTransactionOrder.length > 64) {
            var expired:String = String(_tokenTransactionOrder.shift());
            delete _tokenTransactions[expired];
        }
    }

    private static function recordProcessedCall(callId:String):Void {
        if (callId == "" || _processedCalls[callId] == true) return;
        _processedCalls[callId] = true;
        _processedCallOrder.push(callId);
        while (_processedCallOrder.length > 128) {
            var expired:String = String(_processedCallOrder.shift());
            delete _processedCalls[expired];
        }
    }

    private static function modAvailabilityReason(code:Number):String {
        if (EquipmentUtil.modAvailabilityResults != null
                && EquipmentUtil.modAvailabilityResults[code] != undefined) {
            return String(EquipmentUtil.modAvailabilityResults[code]);
        }
        return "mod_install_rejected";
    }

    /**
     * 内部物品名是交易与插件规则的稳定键；displayname / icon 是独立的展示键。
     * 快照必须同时投影三者，否则 Web 会在射线类插件等“三名分离”数据上用内部名查图而显示空白。
     */
    private static function itemPresentation(itemName:String):Object {
        var itemData:Object = ItemUtil.getItemData(itemName);
        var displayName:String = itemName;
        var icon:String = itemName;
        if (itemData != null) {
            displayName = presentationTextOrFallback(
                itemData.displayname, itemName);
            icon = presentationTextOrFallback(
                itemData.icon, itemName);
        }
        return {displayName:displayName, icon:icon};
    }

    private static function presentationTextOrFallback(
            value, fallback:String):String {
        // legacy XML metadata is accepted only when it is already a string.
        // Number/Object coercion would turn corrupt metadata into plausible Web identity.
        if (value == undefined || value == null
                || typeof value != "string") return fallback;
        var text:String = String(value);
        var start:Number = 0;
        var end:Number = text.length - 1;
        while (start <= end && isPresentationWhitespace(
                text.charCodeAt(start))) start++;
        while (end >= start && isPresentationWhitespace(
                text.charCodeAt(end))) end--;
        if (start > end) return fallback;
        var trimmed:String = text.substring(start, end + 1);
        if (trimmed.toLowerCase() == "undefined") return fallback;
        return text;
    }

    private static function isPresentationWhitespace(code:Number):Boolean {
        return code <= 32 || code == 160;
    }

    /** 将插件定义的单源元数据投影给 Web 候选目录；安装权威仍是 availabilityCode。 */
    private static function buildModCandidateProjection(candidateKey:String, modName:String, owned:Number,
            installed:Boolean, available:Boolean, availabilityCode:Number, reason:String):Object {
        var modData:Object = EquipmentUtil.modDict == undefined ? null : EquipmentUtil.modDict[modName];
        var presentation:Object = itemPresentation(modName);
        var result:Object = {
            candidateKey:candidateKey,
            itemName:modName,
            displayName:presentation.displayName,
            icon:presentation.icon,
            owned:owned,
            installed:installed,
            available:available,
            availabilityCode:availabilityCode,
            reason:reason,
            replaceableFrom:[],
            grade:"unknown",
            scope:"unknown",
            role:"utility"
        };
        if (modData == null) return result;
        result.grade = String(modData.modGrade || "unknown");
        result.gradeLabel = String(modData.uiGradeLabel || "未知档级");
        result.gradeColor = String(modData.uiGradeColor || "#58636E");
        result.scope = String(modData.catalogScope || "unknown");
        result.scopeLabel = String(modData.uiScopeLabel || "未分类");
        result.role = String(modData.uiRole || "utility");
        result.roleLabel = String(modData.uiRoleLabel || "结构与功能");
        result.symbol = String(modData.uiSymbol || "diamond-outline");
        return result;
    }

    private static function indexOfString(values:Array, expected:String):Number {
        if (!(values instanceof Array)) return -1;
        for (var i:Number = 0; i < values.length; i++) if (String(values[i]) == expected) return i;
        return -1;
    }

    private static function cloneArray(values:Object):Array {
        var result:Array = [];
        if (!(values instanceof Array)) return result;
        for (var i:Number = 0; i < values.length; i++) result.push(values[i]);
        return result;
    }

    private static function deepEqual(left:Object, right:Object, depth:Number):Boolean {
        if (left === right) return true;
        if (depth > 16 || left == null || right == null || typeof left != typeof right) return false;
        if (typeof left != "object") return String(left) == String(right);
        var leftArray:Boolean = left instanceof Array;
        if (leftArray != (right instanceof Array)) return false;
        if (leftArray && left.length != right.length) return false;
        var leftCount:Number = 0;
        var rightCount:Number = 0;
        for (var leftKey:String in left) {
            leftCount++;
            if (!deepEqual(left[leftKey], right[leftKey], depth + 1)) return false;
        }
        for (var rightKey:String in right) rightCount++;
        return leftCount == rightCount;
    }

    private static function hasExactKeys(value:Object,
                                         allowed:Object):Boolean {
        if (value == null || typeof value != "object"
                || allowed == null) return false;
        var seen:Object = {};
        for (var key:String in value) {
            if (typeof value.hasOwnProperty == "function"
                    && !value.hasOwnProperty(key)) {
                continue;
            }
            if (allowed[key] !== true) return false;
            seen[key] = true;
        }
        for (key in allowed) {
            if (allowed[key] === true && seen[key] !== true) {
                return false;
            }
        }
        return true;
    }

    private static function isWholeNumber(value):Boolean {
        return typeof value == "number" && !isNaN(value) && Math.floor(value) == value;
    }

    private static function markDirty():Void {
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
    }

    private static function fail(errorCode:String, detail):Object {
        return {success:false, error:errorCode};
    }

    private static function sendResponse(response:Object):Void {
        if (_root.server == undefined || _root.server.sendSocketMessage == undefined) return;
        // 响应可含用户可编辑自由文本：统一走 stringifySafe 标准转义出口。
        _root.server.sendSocketMessage(_json.stringifySafe(response));
    }

    public static function testOnlyFailNextCommit():Void {
        _testFailNext = true;
    }

    public static function testOnlyFailNextMaterialCommit():Void {
        _testFailNextMaterialCommit = true;
    }

    public static function testOnlyFailNextSerialization():Void {
        _testFailNextSerialization = true;
    }

    public static function testOnlyFailNextWornConversionBagCommit():Void {
        _testFailNextWornConversionBagCommit = true;
    }

    public static function testOnlyReset():Void {
        _busy = false;
        _sessionPanel = "";
        _sessionView = "";
        _sessionGeneration++;
        _candidateNames = {};
        _plan = null;
        _writeEpoch = 0;
        _processedCalls = {};
        _processedCallOrder = [];
        _tokenTransactions = {};
        _tokenTransactionOrder = [];
        _testFailNext = false;
        _testFailNextMaterialCommit = false;
        _testFailNextSerialization = false;
        _testFailNextWornConversionBagCommit = false;
    }
}
