import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.LootContainerService;
import org.flashNight.arki.item.LootClaimCommitCoordinator;
import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.item.itemCollection.InformationCollection;
import org.flashNight.neur.Event.LifecycleEventDispatcher;
import org.flashNight.arki.scene.SceneManager;
import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.BoxInteractionArbiter;

/** S1：瞬态 loot container 的 identity/lease/事务/终态/legacy recovery 回归。 */
class org.flashNight.arki.item.LootContainerServiceTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var _backup:Object;
    private static var STACK:String = "S1测试补给";
    private static var ANTIBIOTIC:String = "抗生素";
    private static var EQUIPMENT:String = "S1测试装备";
    private static var MATERIAL:String = "S1测试材料";
    private static var INFORMATION:String = "S1测试情报";
    private static var MOD:String = "S1测试插件";

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        trace("=== LootContainerServiceTest start ===");
        installMetadata();

        testReservationKillGateAndOverwrite();
        testReservationKillUnavailableRecovery();
        testReservationActivationGateRecovery();
        testUnexpectedDeathBeforeMaterialization();
        testProductionDeathUnloadOrdering();
        testAbortReservationAndClaimExceptionRecovery();
        testSnapshotOwnedClaimsStaleAndConsumed();
        testClaimPendingEmptyQuery();
        testClaimPendingMergeQuery();
        testClaimPendingCollectionQuery();
        testPendingClaimRejectsOperationDrift();
        testPostCommitDirtyRetryGate();
        testPostCommitDestinationCacheRetry();
        testSceneTeardownPendingBarrier();
        testTransportDetachSettlesPendingClaim();
        testTransportDetachUncertainFailClosed();
        testTransportDetachPostCommitRecovery();
        testTransportDetachRendererRetry();
        testTransportDetachUnpauseLastItemRetry();
        testPendingClaimSceneExpiryEmpty();
        testPendingClaimSceneExpiryMerge();
        testPendingClaimSceneExpiryEquipment();
        testPendingClaimSceneExpiryScalar();
        testPendingClaimSceneExpiryCollection();
        testFullBackpackZeroSideEffect();
        testFullBackpackExistingStackStillMerges();
        testMaterialAndInformationClaims();
        testCurrencyClaims();
        testAbandonExpireAndDuplicateClose();
        testSuspendAnchorReopenIdentityAndStaleClose();
        testSuspendPauseSocketBypass();
        testSuspendNoSendRollback();
        testSuspendSynchronousCallbackFailureRestoresAnchor();
        testSuspendAsyncRejectionRestoresAndStalesLateCallback();
        testSuspendAsyncTimeoutRestoresAnchor();
        testSuspendSocketDetachOrderingAndLateCallback();
        testSuspendReopenAnchorLossExpires();
        testSuspendSocketDetachAnchorLossReleasesPause();
        testSuspendSocketDetachPauseReleaseRetry();
        testSuspendDirectReopenPauseReleaseRetry();
        testSuspendTerminalReopenPauseReleaseRetry();
        testSuspendAcceptedRecoveryStaysSuspended();
        testCloseAttemptProofSurvivesRejectedReopen();
        testRecoveryProofLedgerOrderingAndCapacity();
        testSuspendReopenFailureEmptyConsumes();
        testInitialOpenSynchronousFailureRendersLegacyOnce();
        testSuspendAnchorFailureIsZeroAuthority();
        testSuspendedAnchorUnloadExpires();
        testLegacyClaimOnlyServiceAdapter();
        testLegacyRecoveryKeepsSameInventory();
        testLegacyRecoveryObserverLifecycle();
        testReliablePanelOpenCallbacks();
        testRecoveryProofStrictShapeAndNonce();
        testInitialRecoveryBeforeAckProof();
        testConnectedPanelRecoverySignal();
        testWireHandlersAndExactPayload();

        restoreMetadata();
        trace("LootContainerServiceTest Tests Passed: " + _passed);
        trace("LootContainerServiceTest Tests Failed: " + _failed);
        trace("=== LootContainerServiceTest end ===");
    }

    private static function installMetadata():Void {
        _backup = {
            itemDataDict:ItemUtil.itemDataDict,
            equipmentDict:ItemUtil.equipmentDict,
            materialDict:ItemUtil.materialDict,
            informationMaxValueDict:ItemUtil.informationMaxValueDict,
            modDict:EquipmentUtil.modDict,
            levelCallback:_root.主角是否升级
        };
        ItemUtil.itemDataDict = {};
        ItemUtil.equipmentDict = {};
        ItemUtil.materialDict = {};
        ItemUtil.informationMaxValueDict = {};
        EquipmentUtil.modDict = {};

        addMeta(STACK, "消耗品", "道具");
        addMeta(ANTIBIOTIC, "消耗品", "药剂");
        addMeta(EQUIPMENT, "武器", "手枪");
        addMeta(MATERIAL, "收集品", "材料");
        addMeta(INFORMATION, "收集品", "情报");
        addMeta("金币", "消耗品", "货币");
        addMeta("K点", "消耗品", "货币");
        addMeta("经验值", "消耗品", "货币");
        addMeta("技能点", "消耗品", "货币");
        ItemUtil.equipmentDict[EQUIPMENT] = true;
        ItemUtil.materialDict[MATERIAL] = true;
        ItemUtil.informationMaxValueDict[INFORMATION] = 5;
        EquipmentUtil.modDict[MOD] = {
            modGrade:"medium", uiGradeLabel:"中等", uiGradeColor:"#996600",
            catalogScope:"firearm", uiRole:"precision", uiRoleLabel:"精准",
            uiSymbol:"triangle-outline"
        };
    }

    private static function addMeta(name:String, typeName:String, useName:String):Void {
        ItemUtil.itemDataDict[name] = {
            name:name, displayname:name, icon:name, type:typeName, use:useName,
            price:1, description:"S1 测试", data:{level:1, modslot:3}
        };
    }

    private static function restoreMetadata():Void {
        ItemUtil.itemDataDict = _backup.itemDataDict;
        ItemUtil.equipmentDict = _backup.equipmentDict;
        ItemUtil.materialDict = _backup.materialDict;
        ItemUtil.informationMaxValueDict = _backup.informationMaxValueDict;
        EquipmentUtil.modDict = _backup.modDict;
        _root.主角是否升级 = _backup.levelCallback;
    }

    private static function resetWorld():Void {
        if (_root.gameworld != undefined && _root.gameworld != null) {
            BoxInteractionArbiter.cleanup(_root.gameworld);
        }
        _root.gameworld = makeTestGameworld();
        _root.物品栏 = {
            背包:new ArrayInventory(null, 50),
            仓库:new ArrayInventory(null, 1200),
            战备箱:new ArrayInventory(null, 400)
        };
        _root.收集品栏 = {
            材料:new DictCollection(null),
            情报:new InformationCollection(null)
        };
        _root.主线任务进度 = 20;
        _root.task_chains_progress = {挑战:0};
        _root.基建系统 = {infrastructure:{越野车:false}};
        _root.存档系统 = {dirtyMark:false};
        _root.金钱 = 100;
        _root.虚拟币 = 20;
        _root.经验值 = 30;
        _root.技能点数 = 40;
        _root.等级 = 1;
        _root._webPanelPauseLease = undefined;
        _root.__lootLevelChecks = 0;
        _root.主角是否升级 = function():Void { _root.__lootLevelChecks++; };
        InventoryPanelService.testOnlyReset();
        LootContainerService.testOnlyReset();
    }

    private static function makeTarget(id:String):Object {
        var dispatcher:Object = {pickUpCount:0, lastTarget:null};
        dispatcher.publish = function(eventName:String, target:Object):Void {
            if (eventName == "pickUpBox") {
                this.pickUpCount++;
                this.lastTarget = target;
            }
        };
        var target:Object = {
            presetName:"装备箱", row:2, col:4,
            chestRolloutId:id, lootFlowProfile:"web-loot-v1", unlockPolicy:"skip",
            _parent:_root.gameworld, _x:0, Z轴坐标:0, area:{},
            interactionEnabled:true, pickupEnabled:true, _killed:false,
            dispatcher:dispatcher, stopCount:0, playCount:0, stopped:false
        };
        target.stop = function():Void { this.stopCount++; this.stopped = true; };
        target.play = function():Void { this.playCount++; this.stopped = false; };
        return target;
    }

    private static function makeTestGameworld():Object {
        var dispatcher:Object = {handlers:[]};
        dispatcher.subscribeGlobal = function(eventName:String, callback:Function,
                                              scope:Object):Boolean {
            this.handlers.push({eventName:eventName, callback:callback, scope:scope});
            return true;
        };
        dispatcher.unsubscribeGlobal = function(eventName:String, callback:Function,
                                                scope:Object):Boolean {
            for (var i:Number = 0; i < this.handlers.length; i++) {
                var row:Object = this.handlers[i];
                if (row.eventName == eventName && row.callback === callback
                        && row.scope === scope) {
                    this.handlers.splice(i, 1);
                    return true;
                }
            }
            return false;
        };
        dispatcher.emit = function():Void {
            var snapshot:Array = this.handlers.slice(0);
            for (var i:Number = 0; i < snapshot.length; i++) {
                snapshot[i].callback.call(snapshot[i].scope);
            }
        };
        return {dispatcher:dispatcher};
    }

    private static function makeInventory(items:Array):ArrayInventory {
        var inventory:ArrayInventory = new ArrayInventory(null, 8);
        for (var i:Number = 0; i < items.length; i++) inventory.add(i, items[i]);
        return inventory;
    }

    private static function stack(name:String, value:Number, lastUpdate:Number):BaseItem {
        return new BaseItem(name, value, lastUpdate);
    }

    private static function equipment(lastUpdate:Number):BaseItem {
        var item:BaseItem = new BaseItem(EQUIPMENT,
            {level:4, tier:"二阶", mods:[MOD], shots:9}, lastUpdate);
        item.getData = function():Object {
            return {
                name:EQUIPMENT, displayname:EQUIPMENT, icon:EQUIPMENT,
                type:"武器", use:"手枪", data:{level:1, modslot:3}
            };
        };
        return item;
    }

    private static function activate(items:Array, id:String):Object {
        var target:Object = makeTarget(id);
        var inventory:ArrayInventory = makeInventory(items);
        var begun:Object = LootContainerService.beginFixture(target);
        var committed:Object = LootContainerService.commitReservedOpen(
            target, inventory, {
                presetName:"装备箱", row:2, col:4, chestRolloutId:id,
                lootFlowProfile:"web-loot-v1", unlockPolicy:"skip"
            },
            function(box:Object):Boolean {
                box._killed = true;
                return LootContainerService.observeDeath(box).ownKill === true;
            });
        var activated:Object = LootContainerService.activateReservedOpen(target);
        check(begun.handled && begun.reserved && committed.success
                && activated.success && activated.state == "LOOT_ACTIVE",
            "完整物化、同步 own-kill proof 后才进入 LOOT_ACTIVE");
        return {target:target, inventory:inventory, active:activated};
    }

    private static function snapshot(flow:Object):Object {
        return LootContainerService.execute("snapshot", {
            v:1,
            chestSessionId:flow.active.chestSessionId,
            lootContainerId:flow.active.lootContainerId,
            containerEpoch:flow.active.containerEpoch,
            loot:{offset:0, limit:8},
            backpack:{offset:0, limit:50}
        });
    }

    private static function claimParams(response:Object, slot:Number, operationId:String):Object {
        var loot:Object = response.snapshots[0];
        var row:Object = loot.slots[slot];
        return {
            v:1,
            chestSessionId:response.chestSessionId,
            lootContainerId:response.lootContainerId,
            containerEpoch:response.containerEpoch,
            expectedAuthorityRevision:response.authorityRevision,
            operationId:operationId,
            direction:"loot_to_player",
            targetContainerId:"背包",
            source:{
                containerId:loot.containerId,
                slot:row.physicalSlot,
                expectedLease:row.slotLease,
                expectedContainerVersion:loot.containerVersion
            }
        };
    }

    private static function queryParams(response:Object):Object {
        return {
            v:1,
            chestSessionId:response.chestSessionId,
            lootContainerId:response.lootContainerId,
            containerEpoch:response.containerEpoch
        };
    }

    private static function proofQueryParams(response:Object, attemptSeq:Number,
                                              nonce:String):Object {
        return {
            v:1,
            chestSessionId:response.chestSessionId,
            lootContainerId:response.lootContainerId,
            containerEpoch:response.containerEpoch,
            openAttemptSeq:attemptSeq,
            recoveryNonce:nonce
        };
    }

    private static function recoveryEnvelope(response:Object, attemptSeq:Number,
                                              nonce:String, reason:String):Object {
        return {
            task:"cmd", action:"lootPanelRecovery",
            chestSessionId:response.chestSessionId,
            lootContainerId:response.lootContainerId,
            containerEpoch:response.containerEpoch,
            openAttemptSeq:attemptSeq,
            recoveryNonce:nonce,
            reason:reason
        };
    }

    private static function closeParams(response:Object, operationId:String,
                                        closeLease:String, abandon:Boolean):Object {
        return {
            v:1,
            chestSessionId:response.chestSessionId,
            lootContainerId:response.lootContainerId,
            containerEpoch:response.containerEpoch,
            expectedAuthorityRevision:response.authorityRevision,
            operationId:operationId,
            closeLease:closeLease,
            abandon:abandon
        };
    }

    private static function testReservationKillGateAndOverwrite():Void {
        resetWorld();
        var ordinary:Object = {presetName:"装备箱", row:2, col:4};
        check(!LootContainerService.beginFixture(ordinary).handled,
            "无 exact marker 的旧箱继续委托 legacy");
        var malformed:Object = {presetName:"装备箱", row:2, col:4,
            chestRolloutId:"s1.partial"};
        var malformedResult:Object = LootContainerService.beginFixture(malformed);
        check(malformedResult.handled && !malformedResult.reserved
                && malformedResult.reason == "invalid_rollout_marker",
            "partial marker fail closed，不穿回 legacy kill");
        var missingThird:Object = {presetName:"装备箱", row:2, col:4,
            chestRolloutId:"s1.missing-third", lootFlowProfile:"web-loot-v1"};
        var missingThirdResult:Object = LootContainerService.beginFixture(missingThird);
        check(missingThirdResult.handled && !missingThirdResult.reserved
                && missingThirdResult.reason == "invalid_rollout_marker",
            "缺少 unlockPolicy 的两字段 marker fail closed");
        var wrongThird:Object = {presetName:"装备箱", row:2, col:4,
            chestRolloutId:"s1.wrong-third", lootFlowProfile:"web-loot-v1",
            unlockPolicy:"open"};
        var wrongThirdResult:Object = LootContainerService.beginFixture(wrongThird);
        check(wrongThirdResult.handled && !wrongThirdResult.reserved
                && wrongThirdResult.reason == "invalid_rollout_marker",
            "unlockPolicy 非 skip 时 fail closed");

        var target:Object = makeTarget("s1.reserve");
        var inventory:ArrayInventory = makeInventory([stack(STACK, 2, 1)]);
        var begun:Object = LootContainerService.beginFixture(target);
        var markerMismatch:Object = LootContainerService.register(
            target, inventory, {unlockPolicy:"open"});
        var firstRegister:Object = LootContainerService.register(target, inventory, {
            presetName:"装备箱", row:2, col:4, chestRolloutId:"s1.reserve",
            lootFlowProfile:"web-loot-v1", unlockPolicy:"skip"
        });
        var overwrite:Object = LootContainerService.register(target, makeInventory([]), null);
        var secondTarget:Object = LootContainerService.beginFixture(makeTarget("s1.second"));
        check(begun.handled && begun.state == "LOOT_COMMIT_PENDING"
                && !markerMismatch.success && markerMismatch.error == "metadata_mismatch"
                && firstRegister.success
                && !overwrite.success && overwrite.error == "materialization_conflict"
                && secondTarget.handled && secondTarget.reason == "loot_flow_busy",
            "一次只允许一个 reservation，已物化 inventory 不可覆盖");

        var committed:Object = LootContainerService.commitReservedOpen(target, inventory, null,
            function(box:Object):Boolean {
                return LootContainerService.observeDeath(box).ownKill === true;
            });
        var duplicateDeath:Object = LootContainerService.observeDeath(target);
        var active:Object = LootContainerService.activateReservedOpen(target);
        var revision:Number = active.authorityRevision;
        var duplicateActivation:Object = LootContainerService.activateReservedOpen(target);
        check(committed.success
                && duplicateDeath.ownKill && duplicateDeath.reason == "duplicate_own_death"
                && active.success && active.closeLease != ""
                && duplicateActivation.success && duplicateActivation.duplicate
                && duplicateActivation.authorityRevision == revision,
            "kill proof 后重复 death/open-frame 均幂等且不推进 revision");
        LootContainerService.expireScene("scene_cleanup");
    }

    private static function testReservationKillUnavailableRecovery():Void {
        resetWorld();
        var unavailableTarget:Object = makeTarget("s1.kill-unavailable");
        var unavailableInventory:ArrayInventory = makeInventory([stack(STACK, 1, 9)]);
        var unavailableBegin:Object = LootContainerService.beginFixture(unavailableTarget);
        var unavailable:Object = LootContainerService.commitReservedOpen(
            unavailableTarget, unavailableInventory, null, null);
        var unavailableFallback:Object = LootContainerService.consumeLegacyFallback(
            unavailableTarget);
        var unavailableGuard:Object = LootContainerService.guardAnyGridFixture(unavailableTarget);
        check(unavailableBegin.reserved
                && !unavailable.success && unavailable.error == "kill_adapter_unavailable"
                && unavailableFallback.success
                && unavailableFallback.inventory === unavailableInventory
                && unavailableGuard.handled
                && unavailableGuard.reason == "kill_adapter_unavailable",
            "materialized reservation 的 kill adapter 缺失进入 same-object ACTIVE recovery");
        LootContainerService.expireScene("scene_cleanup");
    }

    private static function testReservationActivationGateRecovery():Void {
        resetWorld();
        var gateTarget:Object = makeTarget("s1.activation-gate");
        var gateInventory:ArrayInventory = makeInventory([stack(STACK, 1, 10)]);
        LootContainerService.beginFixture(gateTarget);
        var registered:Object = LootContainerService.register(gateTarget, gateInventory, {
            presetName:"装备箱", row:2, col:4, chestRolloutId:"s1.activation-gate",
            lootFlowProfile:"web-loot-v1", unlockPolicy:"skip"
        });
        var rejected:Object = LootContainerService.activateReservedOpen(gateTarget);
        var gateFallback:Object = LootContainerService.consumeLegacyFallback(gateTarget);
        var gateGuard:Object = LootContainerService.guardAnyGridFixture(gateTarget);
        check(registered.success
                && !rejected.success && rejected.error == "activation_gate_failed"
                && gateFallback.success && gateFallback.inventory === gateInventory
                && gateGuard.handled && gateGuard.reason == "activation_gate_failed",
            "未取得 own-kill proof 的 activation gate 失败不遗留 busy reservation");
        LootContainerService.expireScene("scene_cleanup");
    }

    private static function testUnexpectedDeathBeforeMaterialization():Void {
        resetWorld();
        var earlyDeathTarget:Object = makeTarget("s1.early-unexpected-death");
        var earlyBegin:Object = LootContainerService.beginFixture(earlyDeathTarget);
        var earlyDeath:Object = LootContainerService.observeDeath(earlyDeathTarget);
        var earlyTerminal:Object = LootContainerService.execute("query", {
            v:1, chestSessionId:earlyBegin.chestSessionId,
            lootContainerId:earlyBegin.lootContainerId,
            containerEpoch:earlyBegin.containerEpoch
        });
        var afterEarlyDeathTarget:Object = makeTarget("s1.after-early-death");
        var afterEarlyDeath:Object = LootContainerService.beginFixture(afterEarlyDeathTarget);
        check(!earlyDeath.ownKill && earlyDeath.reason == "unexpected_death"
                && earlyTerminal.success && earlyTerminal.state == "EXPIRED"
                && earlyTerminal.terminal.reason == "unexpected_death"
                && afterEarlyDeath.reserved,
            "物化前 unexpected death 无可 recovery inventory 时终止 reservation 并释放全局槽");
        LootContainerService.abortReservedOpen(afterEarlyDeathTarget, "test_cleanup");
    }

    private static function testProductionDeathUnloadOrdering():Void {
        resetWorld();
        var target:Object = makeTarget("s1.death-unload-order");
        var inventory:ArrayInventory = makeInventory([stack(STACK, 1, 13)]);
        LootContainerService.beginFixture(target);
        var deathDuringDispatch:Object = null;
        var committed:Object = LootContainerService.commitReservedOpen(
            target, inventory, null, function(box:Object):Boolean {
                deathDuringDispatch = LootContainerService.observeDeath(box);
                return deathDuringDispatch.ownKill === true;
            });
        // InteractionHandler 的 onUnload 可能在同步 death 后、open frame 前再次观察同一 target。
        var unloadBeforeActivation:Object = LootContainerService.observeDeath(target);
        var active:Object = LootContainerService.activateReservedOpen(target);
        var lateDeathAfterActivation:Object = LootContainerService.observeDeath(target);
        check(committed.success
                && deathDuringDispatch.reason == "own_kill_observed"
                && unloadBeforeActivation.ownKill
                && unloadBeforeActivation.reason == "duplicate_own_death"
                && active.success && active.state == "LOOT_ACTIVE"
                && lateDeathAfterActivation.ownKill
                && lateDeathAfterActivation.reason == "duplicate_own_death",
            "生产 death→onUnload→open-frame 顺序保持 own-kill proof 幂等，不误入 recovery");
        LootContainerService.expireScene("scene_cleanup");
    }

    private static function testAbortReservationAndClaimExceptionRecovery():Void {
        resetWorld();
        var target:Object = makeTarget("s1.abort");
        var begun:Object = LootContainerService.beginFixture(target);
        var wrongTarget:Object = LootContainerService.abortReservedOpen(
            makeTarget("s1.not-current"), "materialization_failed");
        var stillReserved:Object = LootContainerService.beginFixture(makeTarget("s1.busy"));
        var aborted:Object = LootContainerService.abortReservedOpen(target, "materialization_failed");
        var tombstone:Object = LootContainerService.execute("query", {
            v:1, chestSessionId:begun.chestSessionId,
            lootContainerId:begun.lootContainerId, containerEpoch:begun.containerEpoch
        });
        var nextTarget:Object = makeTarget("s1.after-abort");
        var next:Object = LootContainerService.beginFixture(nextTarget);
        check(!wrongTarget.success && wrongTarget.error == "reservation_mismatch"
                && stillReserved.reason == "loot_flow_busy"
                && aborted.success && aborted.state == "EXPIRED"
                && tombstone.success && tombstone.terminal.reason == "materialization_failed"
                && next.reserved,
            "abort 只终止同 target 未 kill reservation，留下 tombstone 并立即释放全局槽");
        LootContainerService.abortReservedOpen(nextTarget, "test_cleanup");

        resetWorld();
        var flow:Object = activate([stack(STACK, 2, 11)], "s1.commit-throw");
        var before:Object = snapshot(flow);
        var ordinaryMaterialDict:Object = ItemUtil.materialDict;
        var throwingMaterialDict:Object = {};
        throwingMaterialDict.__resolve = function() { throw "forced_classification_error"; };
        var failed:Object;
        try {
            ItemUtil.materialDict = throwingMaterialDict;
            failed = LootContainerService.execute(
                "claim", claimParams(before, 0, "claim.throw"));
        } finally {
            ItemUtil.materialDict = ordinaryMaterialDict;
        }
        var sourceIntactAfterFailure:Boolean = flow.inventory.getItem("0") != null;
        var query:Object = LootContainerService.execute("query", queryParams(before));
        var retry:Object = LootContainerService.execute(
            "claim", claimParams(query, 0, "claim.retry"));
        check(!failed.success && failed.error == "commit_failed"
                && query.success && query.state == "LOOT_ACTIVE"
                && sourceIntactAfterFailure && flow.inventory.getItem("0") == null && retry.success,
            "commit 抛异常后恢复 LOOT_ACTIVE/_busy，原 source 可重新领取");
        LootContainerService.execute("close",
            closeParams(retry, "close.retry", retry.closeLease, false));

        resetWorld();
        var activeFlow:Object = activate([stack(STACK, 1, 12)], "s1.active-abort");
        var activeAbort:Object = LootContainerService.abortReservedOpen(
            activeFlow.target, "must_not_touch_active");
        var activeQuery:Object = LootContainerService.execute("query", queryParams(activeFlow.active));
        check(!activeAbort.success && activeAbort.error == "reservation_mismatch"
                && activeQuery.success && activeQuery.state == "LOOT_ACTIVE",
            "abortReservedOpen 不得终止或改写 active authority");
        LootContainerService.expireScene("scene_cleanup");
    }

    private static function testSnapshotOwnedClaimsStaleAndConsumed():Void {
        resetWorld();
        var stackItem:BaseItem = stack(STACK, 7, 101);
        var equipmentItem:BaseItem = equipment(202);
        var flow:Object = activate([stackItem, equipmentItem], "s1.owned");
        var first:Object = snapshot(flow);
        var equipmentProjection:Object = first.snapshots[0].slots[1].item;
        check(first.success && first.snapshots.length == 2
                && first.snapshots[0].containerId == first.lootContainerId
                && first.snapshots[1].containerId == "背包"
                && equipmentProjection.itemKind == "equipment"
                && equipmentProjection.enhancementLevel == 4
                && equipmentProjection.tierSlotUsed
                && equipmentProjection.modSlotUsed == 1,
            "snapshot 同时投影 loot/背包 lease，并保留装备 level/tier/mods 描述");

        var equipmentClaim:Object = LootContainerService.execute(
            "claim", claimParams(first, 1, "claim.equipment"));
        var bagEquipment:Object = _root.物品栏.背包.getItem("0");
        check(equipmentClaim.success && bagEquipment === equipmentItem
                && bagEquipment.value.level == 4 && bagEquipment.value.tier == "二阶"
                && bagEquipment.value.mods[0] == MOD && bagEquipment.value.shots == 9
                && bagEquipment.lastUpdate == 202 && _root.存档系统.dirtyMark,
            "装备 BaseItem 原对象移入背包，descriptor 与 lastUpdate 不重建");

        var staleParams:Object = claimParams(first, 1, "claim.stale");
        var stale:Object = LootContainerService.execute("claim", staleParams);
        check(!stale.success && stale.error == "stale_state",
            "成功写后旧 authorityRevision/slot lease 全部失效");

        var second:Object = equipmentClaim;
        var forgedParams:Object = claimParams(second, 0, "claim.reverse");
        forgedParams.direction = "player_to_loot";
        var forged:Object = LootContainerService.execute("claim", forgedParams);
        check(!forged.success && forged.error == "transfer_forbidden"
                && flow.inventory.getItem("0") === stackItem,
            "伪造方向被 AS2 白名单拒绝且 source 零变化");

        var stackClaim:Object = LootContainerService.execute(
            "claim", claimParams(second, 0, "__proto__"));
        check(stackClaim.success && _root.物品栏.背包.getItem("1") === stackItem
                && stackClaim.remainingCount == 0,
            "普通栈在空目的槽保留 BaseItem 对象并清空 loot");

        var closeLease:String = stackClaim.closeLease;
        var closeRequest:Object = closeParams(stackClaim, "constructor", closeLease, false);
        var closed:Object = LootContainerService.execute("close", closeRequest);
        var duplicate:Object = LootContainerService.execute("close", closeRequest);
        var queried:Object = LootContainerService.execute("query", queryParams(closed));
        check(closed.success && closed.state == "CONSUMED" && closed.terminal.kind == "CONSUMED"
                && duplicate.success && queried.success
                && queried.lastAppliedOperationId == "constructor"
                && queried.snapshots.length == 0,
            "原型同名 operationId 仍可幂等；空箱 close/tombstone query 完成对账");
    }

    private static function testClaimPendingEmptyQuery():Void {
        resetWorld();
        var equipmentItem:BaseItem = equipment(391);
        var equipmentFlow:Object = activate([equipmentItem], "s1.pending-equipment");
        var equipmentRequest:Object = claimParams(
            snapshot(equipmentFlow), 0, "claim.pending-equipment");
        LootClaimCommitCoordinator.testOnlyFailNext("ordinary_destination_write", "after_false");
        LootClaimCommitCoordinator.testOnlyFailNext("ordinary_source_write", "false");
        var equipmentPending:Object = LootContainerService.execute("claim", equipmentRequest);
        var equipmentDuplicatedInternally:Boolean = _root.物品栏.背包.getItem("0") === equipmentItem
            && equipmentFlow.inventory.getItem("0") === equipmentItem;
        var equipmentStillPending:Object = LootContainerService.execute(
            "query", queryParams(equipmentFlow.active));
        var equipmentCommitted:Object = LootContainerService.execute(
            "query", queryParams(equipmentFlow.active));
        check(!equipmentPending.success && equipmentPending.error == "commit_pending"
                && equipmentPending.state == "LOOT_COMMIT_PENDING"
                && equipmentDuplicatedInternally
                && !equipmentStillPending.success
                && equipmentStillPending.error == "commit_pending"
                && equipmentStillPending.state == "LOOT_COMMIT_PENDING"
                && equipmentCommitted.success
                && equipmentCommitted.lastAppliedOperationId == "claim.pending-equipment"
                && _root.物品栏.背包.getItem("0") === equipmentItem
                && equipmentFlow.inventory.getItem("0") == null,
            "ordinary empty-slot：destination 已落地却返回 false 时，两次 causal query 仅前滚 source 且不重复写入 destination");
    }

    private static function testClaimPendingMergeQuery():Void {
        resetWorld();
        var bagStack:BaseItem = stack(STACK, 4, 392);
        _root.物品栏.背包.add(0, bagStack);
        var mergeSource:BaseItem = stack(STACK, 2, 393);
        var mergeFlow:Object = activate([mergeSource], "s1.pending-merge");
        var mergeRequest:Object = claimParams(snapshot(mergeFlow), 0, "claim.pending-merge");
        LootClaimCommitCoordinator.testOnlyFailNext("ordinary_source_write", "false");
        LootClaimCommitCoordinator.testOnlyFailNext("ordinary_rollback", "throw");
        var mergePending:Object = LootContainerService.execute("claim", mergeRequest);
        var mergePendingState:Boolean = bagStack.value == 6
            && mergeFlow.inventory.getItem("0") === mergeSource;
        var mergeCommitted:Object = LootContainerService.execute(
            "query", queryParams(mergeFlow.active));
        check(!mergePending.success && mergePending.error == "commit_pending"
                && mergePendingState && mergeCommitted.success
                && bagStack.value == 6 && mergeFlow.inventory.getItem("0") == null,
            "ordinary merge：rollback throw 不清 pending；query 只删 source，不二次累加 destination");
    }

    private static function testClaimPendingCollectionQuery():Void {
        resetWorld();
        var materialItem:BaseItem = stack(MATERIAL, 3, 394);
        var materialFlow:Object = activate([materialItem], "s1.pending-material");
        var materialRequest:Object = claimParams(
            snapshot(materialFlow), 0, "claim.pending-material");
        LootClaimCommitCoordinator.testOnlyFailNext("special_source_write", "false");
        LootClaimCommitCoordinator.testOnlyFailNext("special_rollback", "false");
        var materialPending:Object = LootContainerService.execute("claim", materialRequest);
        var materialPendingState:Boolean = _root.收集品栏.材料.getValue(MATERIAL) == 3
            && materialFlow.inventory.getItem("0") === materialItem;
        var materialCommitted:Object = LootContainerService.execute(
            "query", queryParams(materialFlow.active));
        check(!materialPending.success && materialPending.error == "commit_pending"
                && materialPendingState && materialCommitted.success
                && _root.收集品栏.材料.getValue(MATERIAL) == 3
                && materialFlow.inventory.getItem("0") == null,
            "special material：rollback false 保留 before/after journal；query forward-complete 后材料不复制");
    }

    private static function testPendingClaimRejectsOperationDrift():Void {
        resetWorld();
        var pendingItem:BaseItem = equipment(3941);
        var flow:Object = activate([pendingItem], "s1.pending-operation-drift");
        var authority:Object = snapshot(flow);
        var original:Object = claimParams(authority, 0, "claim.pending-drift");
        LootClaimCommitCoordinator.testOnlyFailNext("ordinary_destination_write", "after_false");
        var pending:Object = LootContainerService.execute("claim", original);

        var otherOperation:Object = LootContainerService.execute("claim",
            claimParams(authority, 0, "claim.other-operation"));
        check(!pending.success && pending.error == "commit_pending"
                && !otherOperation.success && otherOperation.error == "operation_conflict"
                && otherOperation.state == "LOOT_COMMIT_PENDING"
                && _root.物品栏.背包.getItem("0") === pendingItem
                && flow.inventory.getItem("0") === pendingItem,
            "pending claim 拒绝不同 operationId，source/destination exact 状态不变");

        var changedFingerprint:Object = claimParams(authority, 0, "claim.pending-drift");
        changedFingerprint.source.expectedLease = "loot.slot.drift";
        var fingerprintConflict:Object = LootContainerService.execute("claim", changedFingerprint);
        var expired:Object = LootContainerService.expireScene("scene_cleanup");
        check(!fingerprintConflict.success && fingerprintConflict.error == "operation_conflict"
                && fingerprintConflict.state == "LOOT_COMMIT_PENDING"
                && expired.success && expired.lastAppliedOperationId == "claim.pending-drift"
                && _root.物品栏.背包.getItem("0") === pendingItem
                && flow.inventory.getItem("0") == null,
            "pending claim 拒绝同 operationId 不同 fingerprint，随后只按原 journal 收敛");
    }

    private static function testPostCommitDirtyRetryGate():Void {
        var sourceOwner:MovieClip = _root.createEmptyMovieClip(
            "__loot_post_commit_dirty_source", _root.getNextHighestDepth());
        var destinationOwner:MovieClip = _root.createEmptyMovieClip(
            "__loot_post_commit_dirty_destination", _root.getNextHighestDepth());
        try {
            resetWorld();
            var item:BaseItem = stack(STACK, 2, 3942);
            var flow:Object = activate([item], "s1.post-commit-dirty");
            var sourceEvents:Number = 0;
            var destinationEvents:Number = 0;
            var sourceDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(sourceOwner);
            var destinationDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(destinationOwner);
            flow.inventory.setDispatcher(sourceDispatcher);
            _root.物品栏.背包.setDispatcher(destinationDispatcher);
            sourceDispatcher.subscribe("ItemRemoved", function():Void { sourceEvents++; });
            destinationDispatcher.subscribe("ItemAdded", function():Void { destinationEvents++; });

            var authority:Object = snapshot(flow);
            var operationId:String = "claim.post-commit-dirty";
            LootContainerService.testOnlyFailNextPostCommit("dirty");
            var pending:Object = LootContainerService.execute(
                "claim", claimParams(authority, 0, operationId));
            var snapshotBlocked:Object = snapshot(flow);
            var otherClaim:Object = LootContainerService.execute(
                "claim", claimParams(authority, 0, "claim.post-commit-other"));
            var closeBlocked:Object = LootContainerService.execute(
                "close", closeParams(authority, "close.post-commit", authority.closeLease, true));
            var legacyBlocked:Object = LootContainerService.consumeLegacyFallback(flow.target);
            LootContainerService.testOnlyFailNextPostCommit("dirty");
            var expiryBlocked:Object = LootContainerService.expireScene("scene_cleanup");
            var recovered:Object = LootContainerService.execute("query", queryParams(authority));

            check(!pending.success && pending.error == "commit_pending"
                    && pending.state == "LOOT_COMMIT_PENDING"
                    && pending.lastAppliedOperationId == operationId
                    && !snapshotBlocked.success && snapshotBlocked.error == "commit_pending"
                    && !otherClaim.success && otherClaim.error == "commit_pending"
                    && !closeBlocked.success && closeBlocked.error == "commit_pending"
                    && !legacyBlocked.success && legacyBlocked.error == "claim_commit_pending"
                    && !expiryBlocked.success && expiryBlocked.error == "commit_pending"
                    && expiryBlocked.state == "LOOT_COMMIT_PENDING"
                    && recovered.success && recovered.state == "LOOT_ACTIVE"
                    && recovered.lastAppliedOperationId == operationId
                    && _root.存档系统.dirtyMark === true
                    && flow.inventory.getItem("0") == null
                    && _root.物品栏.背包.getItem("0") === item
                    && sourceEvents == 1 && destinationEvents == 1,
                "journal 后 dirty 失败保持 pending；所有旁路拒绝，仅 causal query 完成 exact 副作用且事件一次");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            sourceOwner.removeMovieClip();
            destinationOwner.removeMovieClip();
        }
    }

    private static function testPostCommitDestinationCacheRetry():Void {
        var sourceOwner:MovieClip = _root.createEmptyMovieClip(
            "__loot_post_commit_cache_source", _root.getNextHighestDepth());
        var destinationOwner:MovieClip = _root.createEmptyMovieClip(
            "__loot_post_commit_cache_destination", _root.getNextHighestDepth());
        try {
            resetWorld();
            var dirtyWrites:Number = 0;
            var dirtyValue:Boolean = false;
            var saveSystem:Object = {};
            saveSystem.addProperty("dirtyMark",
                function():Boolean { return dirtyValue; },
                function(value:Boolean):Void { dirtyWrites++; dirtyValue = value; });
            _root.存档系统 = saveSystem;

            var item:BaseItem = equipment(3943);
            var flow:Object = activate([item], "s1.post-commit-destination-cache");
            var sourceEvents:Number = 0;
            var destinationEvents:Number = 0;
            var sourceDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(sourceOwner);
            var destinationDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(destinationOwner);
            flow.inventory.setDispatcher(sourceDispatcher);
            _root.物品栏.背包.setDispatcher(destinationDispatcher);
            sourceDispatcher.subscribe("ItemRemoved", function():Void { sourceEvents++; });
            destinationDispatcher.subscribe("ItemAdded", function():Void { destinationEvents++; });

            var authority:Object = snapshot(flow);
            var request:Object = claimParams(
                authority, 0, "claim.post-commit-destination-cache");
            LootContainerService.testOnlyFailNextPostCommit("destination_cache");
            var pending:Object = LootContainerService.execute("claim", request);
            var eventsSuppressedBeforeRecovery:Boolean = sourceEvents == 0 && destinationEvents == 0;
            var recovered:Object = LootContainerService.execute("query", queryParams(authority));
            var duplicate:Object = LootContainerService.execute("claim", request);

            check(!pending.success && pending.error == "commit_pending"
                    && pending.state == "LOOT_COMMIT_PENDING"
                    && dirtyValue && dirtyWrites == 1
                    && eventsSuppressedBeforeRecovery
                    && flow.inventory.getItem("0") == null
                    && _root.物品栏.背包.getItem("0") === item
                    && recovered.success && recovered.state == "LOOT_ACTIVE"
                    && recovered.lastAppliedOperationId == "claim.post-commit-destination-cache"
                    && duplicate.success && dirtyWrites == 1
                    && sourceEvents == 1 && destinationEvents == 1,
                "destination cache 失败不重做 dirty/写入；query 恢复后 duplicate 也不重复事件");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            sourceOwner.removeMovieClip();
            destinationOwner.removeMovieClip();
        }
    }

    private static function testSceneTeardownPendingBarrier():Void {
        var manager:SceneManager = SceneManager.getInstance();
        var previousWorld:MovieClip = manager.gameworld;
        var testWorld:MovieClip = null;
        try {
            resetWorld();
            var item:BaseItem = equipment(3944);
            var flow:Object = activate([item], "s1.scene-teardown-barrier");
            LootContainerService.testOnlyFailNextPostCommit("dirty");
            var pending:Object = LootContainerService.execute(
                "claim", claimParams(snapshot(flow), 0, "claim.scene-teardown-barrier"));

            testWorld = _root.createEmptyMovieClip(
                "__loot_scene_teardown_barrier", _root.getNextHighestDepth());
            var dispatcher:Object = {
                destroyCount:0,
                destroy:function():Void { this.destroyCount++; }
            };
            testWorld.dispatcher = dispatcher;
            manager.gameworld = testWorld;

            // 再阻断 expireScene 内的 mandatory-effect retry，首轮必须完整保留 world。
            LootContainerService.testOnlyFailNextPostCommit("dirty");
            var blocked:Boolean = manager.removeGameWorld();
            var retained:Boolean = manager.gameworld === testWorld
                && dispatcher.destroyCount == 0 && testWorld._parent != null;
            var removed:Boolean = manager.removeGameWorld();
            var terminal:Object = LootContainerService.execute(
                "query", queryParams(flow.active));

            check(!pending.success && pending.error == "commit_pending"
                    && !blocked && retained && removed
                    && manager.gameworld == null && dispatcher.destroyCount == 1
                    && terminal.success && terminal.state == "EXPIRED"
                    && terminal.lastAppliedOperationId == "claim.scene-teardown-barrier"
                    && _root.物品栏.背包.getItem("0") === item
                    && flow.inventory.getItem("0") == null
                    && _root.存档系统.dirtyMark === true,
                "SceneManager 在 commit/effects pending 时零 teardown；下一次收敛后才销毁 world");
        } finally {
            if (testWorld != null && testWorld._parent != null) testWorld.removeMovieClip();
            manager.gameworld = previousWorld;
            LootContainerService.testOnlyReset();
        }
    }

    private static function testTransportDetachSettlesPendingClaim():Void {
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var presented:Array = [];
            installLegacyRenderer(presented);
            var item:BaseItem = equipment(3944);
            var flow:Object = activate([item], "s1.detach-pending");
            var authority:Object = snapshot(flow);
            LootClaimCommitCoordinator.testOnlyFailNext(
                "ordinary_destination_write", "after_false");
            LootClaimCommitCoordinator.testOnlyFailNext("ordinary_source_write", "false");
            var pending:Object = LootContainerService.execute(
                "claim", claimParams(authority, 0, "claim.detach-pending"));
            var genericBlocked:Object = LootContainerService.consumeLegacyFallback(flow.target);
            var reconciled:Object = LootContainerService.reconcileTransportDetach(flow.target);
            var afterTerminal:Object = LootContainerService.consumeLegacyFallback(flow.target);

            check(!pending.success && pending.error == "commit_pending"
                    && !genericBlocked.success && genericBlocked.error == "claim_commit_pending"
                    && reconciled.success && reconciled.readyForLegacy
                    && reconciled.state == "CONSUMED"
                    && !afterTerminal.success && afterTerminal.error == "no_legacy_fallback"
                    && presented.length == 1 && presented[0].inventory === flow.inventory
                    && flow.inventory.getItem("0") == null
                    && _root.物品栏.背包.getItem("0") === item
                    && _root.存档系统.dirtyMark === true,
                "transport detach 只按 exact journal 收敛半提交，呈现同一空 inventory 后落终态");
            LootContainerService.testOnlyReset();
        } finally {
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testTransportDetachUncertainFailClosed():Void {
        resetWorld();
        var item:BaseItem = equipment(3945);
        var flow:Object = activate([item], "s1.detach-uncertain");
        var authority:Object = snapshot(flow);
        LootClaimCommitCoordinator.testOnlyFailNext(
            "ordinary_destination_write", "after_false");
        var pending:Object = LootContainerService.execute(
            "claim", claimParams(authority, 0, "claim.detach-uncertain"));
        var conflicting:BaseItem = equipment(3946);
        _root.物品栏.背包.transactionWrite(0, conflicting);

        var reconciled:Object = LootContainerService.reconcileTransportDetach(flow.target);
        var genericBlocked:Object = LootContainerService.consumeLegacyFallback(flow.target);
        var queried:Object = LootContainerService.execute("query", queryParams(authority));
        check(!pending.success && pending.error == "commit_pending"
                && !reconciled.success && !reconciled.readyForLegacy
                && reconciled.error == "claim_commit_pending"
                && reconciled.state == "LOOT_COMMIT_PENDING"
                && !genericBlocked.success && genericBlocked.error == "claim_commit_pending"
                && !queried.success && queried.error == "commit_pending"
                && !LootContainerService.requestOpenPanel()
                && flow.inventory.getItem("0") === item
                && _root.物品栏.背包.getItem("0") === conflicting
                && _root.存档系统.dirtyMark === false,
            "transport detach 遇 destination conflict 保持 pending，禁止 legacy/open/dirty");
        LootContainerService.testOnlyReset();
    }

    private static function testTransportDetachPostCommitRecovery():Void {
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var presented:Array = [];
            installLegacyRenderer(presented);
            var oneShotItem:BaseItem = stack(STACK, 2, 3947);
            var oneShotFlow:Object = activate([oneShotItem], "s1.detach-post-once");
            var oneShotAuthority:Object = snapshot(oneShotFlow);
            LootContainerService.testOnlyFailNextPostCommit("dirty");
            var oneShotPending:Object = LootContainerService.execute("claim", claimParams(
                oneShotAuthority, 0, "claim.detach-post-once"));
            var oneShotGeneric:Object = LootContainerService.consumeLegacyFallback(oneShotFlow.target);
            var oneShotReady:Object = LootContainerService.reconcileTransportDetach(oneShotFlow.target);

            resetWorld();
            installLegacyRenderer(presented);
            var persistentItem:BaseItem = equipment(3948);
            var persistentFlow:Object = activate([persistentItem], "s1.detach-post-persistent");
            var persistentAuthority:Object = snapshot(persistentFlow);
            _root.存档系统 = null;
            var persistentPending:Object = LootContainerService.execute("claim", claimParams(
                persistentAuthority, 0, "claim.detach-post-persistent"));
            var firstBlocked:Object = LootContainerService.reconcileTransportDetach(persistentFlow.target);
            var secondBlocked:Object = LootContainerService.reconcileTransportDetach(persistentFlow.target);
            var persistentGeneric:Object = LootContainerService.consumeLegacyFallback(persistentFlow.target);
            _root.存档系统 = {dirtyMark:false};
            var persistentReady:Object = LootContainerService.reconcileTransportDetach(persistentFlow.target);

            check(!oneShotPending.success && oneShotPending.error == "commit_pending"
                    && !oneShotGeneric.success && oneShotGeneric.error == "claim_commit_pending"
                    && oneShotReady.success && oneShotReady.readyForLegacy
                    && oneShotReady.state == "CONSUMED"
                    && oneShotFlow.inventory.getItem("0") == null
                    && !persistentPending.success && persistentPending.error == "commit_pending"
                    && !firstBlocked.success && !secondBlocked.success
                    && firstBlocked.error == "claim_commit_pending"
                    && secondBlocked.error == "claim_commit_pending"
                    && !persistentGeneric.success
                    && persistentGeneric.error == "claim_commit_pending"
                    && persistentReady.success && persistentReady.readyForLegacy
                    && persistentReady.state == "CONSUMED"
                    && persistentFlow.inventory.getItem("0") == null
                    && _root.物品栏.背包.getItem("0") === persistentItem
                    && _root.存档系统.dirtyMark === true && presented.length == 2,
                "transport detach 可恢复一次性 post effect；持久失败保持前置门，条件恢复后各呈现一次并终止空箱");
            LootContainerService.testOnlyReset();
        } finally {
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testTransportDetachRendererRetry():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
            var attempts:Number = 0;
            var presented:Array = [];
            _root.地图元件 = {
                显示Web战利品旧界面:function(projection:Object):Boolean {
                    attempts++;
                    if (attempts == 1) return false;
                    presented.push(projection);
                    return true;
                }
            };
            var flow:Object = activate([
                stack(STACK, 2, 3949), stack(STACK, 3, 3950)
            ], "s1.detach-renderer-retry");
            LootContainerService.requestOpenPanel();
            var openAttemptSeq:Number = Number(sent[0].payload.initData.openAttemptSeq);
            callbacks[0]({success:true, accepted:true});
            var authority:Object = snapshot(flow);
            var first:Object = LootContainerService.reconcileSocketDetach(flow.target);
            var snapshotBlocked:Object = snapshot(flow);
            var expiryBlocked:Object = LootContainerService.expireScene("scene_cleanup");
            var ordinaryBlocked:Object = LootContainerService.execute(
                "query", queryParams(authority));
            var queryRecovered:Object = LootContainerService.execute(
                "query", proofQueryParams(authority, openAttemptSeq,
                    "socket.renderer.retry"));
            var projection:Object = LootContainerService.consumeLegacyFallback(flow.target);

            check(!first.success && first.error == "claim_commit_pending"
                    && first.state == "LOOT_COMMIT_PENDING"
                    && !snapshotBlocked.success && snapshotBlocked.error == "commit_pending"
                    && !expiryBlocked.success && expiryBlocked.error == "commit_pending"
                    && expiryBlocked.state == "LOOT_COMMIT_PENDING"
                    && !ordinaryBlocked.success && ordinaryBlocked.error == "commit_pending"
                    && attempts == 2 && presented.length == 1
                    && presented[0].inventory === flow.inventory
                    && queryRecovered.success && queryRecovered.state == "LOOT_ACTIVE"
                    && projection.success && projection.rendererConfirmed === true,
                "socket renderer 首次失败保持 fence；普通 query 不续跑，exact 9 键 proof 重试成功");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testTransportDetachUnpauseLastItemRetry():Void {
        var sourceOwner:MovieClip = _root.createEmptyMovieClip(
            "__loot_detach_unpause_source", _root.getNextHighestDepth());
        var destinationOwner:MovieClip = _root.createEmptyMovieClip(
            "__loot_detach_unpause_destination", _root.getNextHighestDepth());
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
            var presented:Array = [];
            installLegacyRenderer(presented);
            var item:BaseItem = equipment(3951);
            var flow:Object = activate([item], "s1.detach-unpause-last-item");
            LootContainerService.requestOpenPanel();
            callbacks[0]({success:true, accepted:true});
            var openAttemptSeq:Number = Number(sent[0].payload.initData.openAttemptSeq);
            var sourceEvents:Number = 0;
            var destinationEvents:Number = 0;
            var sourceDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(sourceOwner);
            var destinationDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(destinationOwner);
            flow.inventory.setDispatcher(sourceDispatcher);
            _root.物品栏.背包.setDispatcher(destinationDispatcher);
            sourceDispatcher.subscribe("ItemRemoved", function():Void { sourceEvents++; });
            destinationDispatcher.subscribe("ItemAdded", function():Void { destinationEvents++; });

            var authority:Object = snapshot(flow);
            LootContainerService.testOnlyFailNextPostCommit("dirty");
            var pending:Object = LootContainerService.execute("claim", claimParams(
                authority, 0, "claim.detach-unpause-last-item"));
            LootContainerService.testOnlyFailNextTransportHandoff("unpause");
            var firstDetach:Object = LootContainerService.handlePanelRecovery({
                task:"cmd", action:"lootPanelRecovery",
                chestSessionId:authority.chestSessionId,
                lootContainerId:authority.lootContainerId,
                containerEpoch:authority.containerEpoch,
                openAttemptSeq:openAttemptSeq,
                recoveryNonce:"recovery.unpause.last.item",
                reason:"web_mount_failed"
            });
            var fenceHeld:Boolean = LootContainerService.hasPendingTransportDetach();
            var queryRecovered:Object = LootContainerService.execute(
                "query", proofQueryParams(authority, openAttemptSeq,
                    "recovery.unpause.last.item"));
            var fenceReleased:Boolean = !LootContainerService.hasPendingTransportDetach();
            var afterTerminal:Object = LootContainerService.consumeLegacyFallback(flow.target);

            check(!pending.success && pending.error == "commit_pending"
                    && firstDetach.handled && !firstDetach.recovered
                    && firstDetach.rendered && firstDetach.reason == "recovery_pending"
                    && fenceHeld && fenceReleased
                    && presented.length == 1 && presented[0].inventory === flow.inventory
                    && queryRecovered.success && queryRecovered.state == "CONSUMED"
                    && queryRecovered.terminal != null
                    && queryRecovered.terminal.kind == "CONSUMED"
                    && !afterTerminal.success && afterTerminal.error == "no_legacy_fallback"
                    && sourceEvents == 1 && destinationEvents == 1
                    && flow.inventory.getItem("0") == null
                    && _root.物品栏.背包.getItem("0") === item,
                "detach unpause retry");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
            sourceOwner.removeMovieClip();
            destinationOwner.removeMovieClip();
        }
    }

    private static function testPendingClaimSceneExpiryEmpty():Void {
        resetWorld();
        var emptyItem:BaseItem = stack(STACK, 2, 395);
        var emptyFlow:Object = activate([emptyItem], "s1.expiry-empty");
        LootClaimCommitCoordinator.testOnlyFailNext("ordinary_source_write", "false");
        LootClaimCommitCoordinator.testOnlyFailNext("ordinary_rollback", "false");
        var emptyPending:Object = LootContainerService.execute("claim", claimParams(
            snapshot(emptyFlow), 0, "claim.expiry-empty"));
        var emptyExpired:Object = LootContainerService.expireScene("scene_cleanup");
        check(!emptyPending.success && emptyPending.error == "commit_pending"
                && emptyExpired.success && emptyExpired.state == "EXPIRED"
                && emptyExpired.lastAppliedOperationId == "claim.expiry-empty"
                && _root.物品栏.背包.getItem("0") === emptyItem
                && emptyFlow.inventory.getItem("0") == null
                && emptyExpired.remainingCount == 0 && _root.存档系统.dirtyMark,
            "scene cleanup 先完成 ordinary empty-slot pending，再写 journal/dirty 并终止");
    }

    private static function testPendingClaimSceneExpiryMerge():Void {
        resetWorld();
        var mergeBag:BaseItem = stack(STACK, 4, 396);
        _root.物品栏.背包.add(0, mergeBag);
        var mergeItem:BaseItem = stack(STACK, 3, 397);
        var mergeFlow:Object = activate([mergeItem], "s1.expiry-merge");
        LootClaimCommitCoordinator.testOnlyFailNext("ordinary_source_write", "false");
        LootClaimCommitCoordinator.testOnlyFailNext("ordinary_rollback", "throw");
        var mergePending:Object = LootContainerService.execute("claim", claimParams(
            snapshot(mergeFlow), 0, "claim.expiry-merge"));
        var mergeExpired:Object = LootContainerService.expireScene("scene_cleanup");
        check(!mergePending.success && mergePending.error == "commit_pending"
                && mergeExpired.success && mergeExpired.lastAppliedOperationId == "claim.expiry-merge"
                && mergeBag.value == 7 && mergeFlow.inventory.getItem("0") == null
                && mergeExpired.remainingCount == 0 && _root.存档系统.dirtyMark,
            "scene cleanup 先完成 ordinary merge pending，destination 不二次累加");
    }

    private static function testPendingClaimSceneExpiryEquipment():Void {
        resetWorld();
        var expiryEquipment:BaseItem = equipment(398);
        var equipmentFlow:Object = activate([expiryEquipment], "s1.expiry-equipment");
        LootClaimCommitCoordinator.testOnlyFailNext("ordinary_destination_write", "after_false");
        LootClaimCommitCoordinator.testOnlyFailNext("ordinary_source_write", "false");
        var equipmentPending:Object = LootContainerService.execute("claim", claimParams(
            snapshot(equipmentFlow), 0, "claim.expiry-equipment"));
        var equipmentExpired:Object = LootContainerService.expireScene("scene_cleanup");
        check(!equipmentPending.success && equipmentPending.error == "commit_pending"
                && equipmentExpired.success
                && equipmentExpired.lastAppliedOperationId == "claim.expiry-equipment"
                && _root.物品栏.背包.getItem("0") === expiryEquipment
                && equipmentFlow.inventory.getItem("0") == null
                && equipmentExpired.remainingCount == 0 && _root.存档系统.dirtyMark,
            "scene cleanup 对 destination-after-false 装备执行 exact source settle 后才终止");
    }

    private static function testPendingClaimSceneExpiryScalar():Void {
        resetWorld();
        var moneyFlow:Object = activate([stack("金币", 5, 399)], "s1.expiry-scalar");
        LootClaimCommitCoordinator.testOnlyFailNext("special_source_write", "false");
        LootClaimCommitCoordinator.testOnlyFailNext("special_rollback", "false");
        var moneyPending:Object = LootContainerService.execute("claim", claimParams(
            snapshot(moneyFlow), 0, "claim.expiry-scalar"));
        var moneyExpired:Object = LootContainerService.expireScene("scene_cleanup");
        check(!moneyPending.success && moneyPending.error == "commit_pending"
                && moneyExpired.success && moneyExpired.lastAppliedOperationId == "claim.expiry-scalar"
                && _root.金钱 == 105 && moneyFlow.inventory.getItem("0") == null
                && moneyExpired.remainingCount == 0 && _root.存档系统.dirtyMark,
            "scene cleanup 先完成 scalar pending，数值不重复累加且进入成功 journal");
    }

    private static function testPendingClaimSceneExpiryCollection():Void {
        resetWorld();
        var collectionFlow:Object = activate(
            [stack(MATERIAL, 3, 400)], "s1.expiry-collection");
        LootClaimCommitCoordinator.testOnlyFailNext("special_source_write", "false");
        LootClaimCommitCoordinator.testOnlyFailNext("special_rollback", "throw");
        var collectionPending:Object = LootContainerService.execute("claim", claimParams(
            snapshot(collectionFlow), 0, "claim.expiry-collection"));
        var collectionExpired:Object = LootContainerService.expireScene("scene_cleanup");
        check(!collectionPending.success && collectionPending.error == "commit_pending"
                && collectionExpired.success
                && collectionExpired.lastAppliedOperationId == "claim.expiry-collection"
                && _root.收集品栏.材料.getValue(MATERIAL) == 3
                && collectionFlow.inventory.getItem("0") == null
                && collectionExpired.remainingCount == 0 && _root.存档系统.dirtyMark,
            "scene cleanup 先完成 collection pending，收集品不复制且成功副作用可持久化");
    }

    private static function testFullBackpackZeroSideEffect():Void {
        resetWorld();
        for (var i:Number = 0; i < 50; i++) _root.物品栏.背包.add(i, stack(STACK, i + 1, i + 1));
        var equipmentItem:BaseItem = equipment(303);
        var flow:Object = activate([equipmentItem], "s1.full");
        var snap:Object = snapshot(flow);
        _root.存档系统.dirtyMark = false;
        var result:Object = LootContainerService.execute("claim", claimParams(snap, 0, "claim.full"));
        check(!result.success && result.error == "target_full"
                && flow.inventory.getItem("0") === equipmentItem
                && _root.物品栏.背包.size() == 50 && !_root.存档系统.dirtyMark,
            "满背包装备领取失败时 source/背包/dirtyMark 均零副作用");
        LootContainerService.expireScene("scene_cleanup");
    }

    private static function testFullBackpackExistingStackStillMerges():Void {
        resetWorld();
        var destination:BaseItem = stack(ANTIBIOTIC, 358, 304);
        _root.物品栏.背包.add(14, destination);
        for (var i:Number = 0; i < 50; i++) {
            if (i != 14) _root.物品栏.背包.add(i, stack(STACK, i + 1, 305 + i));
        }
        var source:BaseItem = stack(ANTIBIOTIC, 3, 355);
        var flow:Object = activate([source], "s1.full-existing-stack");
        var snap:Object = snapshot(flow);
        _root.存档系统.dirtyMark = false;
        var result:Object = LootContainerService.execute(
            "claim", claimParams(snap, 0, "claim.full-existing-stack"));
        check(result.success && result.authorityRevision == snap.authorityRevision + 1
                && result.remainingCount == 0
                && _root.物品栏.背包.size() == 50
                && _root.物品栏.背包.getItem("14") === destination
                && destination.value == 361 && flow.inventory.getItem("0") == null
                && _root.存档系统.dirtyMark,
            "50/50 满背包已有同名数值抗生素栈时仍原位合并，source 清空且 authority/dirty 推进");
        LootContainerService.expireScene("scene_cleanup");
    }

    private static function testMaterialAndInformationClaims():Void {
        resetWorld();
        var materialItem:BaseItem = stack(MATERIAL, 3, 401);
        var materialFlow:Object = activate([materialItem], "s1.material");
        var materialResult:Object = LootContainerService.execute(
            "claim", claimParams(snapshot(materialFlow), 0, "claim.material"));
        check(materialResult.success && _root.收集品栏.材料.getValue(MATERIAL) == 3
                && materialFlow.inventory.getItem("0") == null,
            "材料按独立 claim 原子进入材料域，不塞背包");
        LootContainerService.execute("close",
            closeParams(materialResult, "close.material", materialResult.closeLease, false));

        resetWorld();
        _root.收集品栏.情报.add(INFORMATION, 4);
        var infoItem:BaseItem = stack(INFORMATION, 2, 402);
        var infoFlow:Object = activate([infoItem], "s1.info");
        var infoSnapshot:Object = snapshot(infoFlow);
        _root.存档系统.dirtyMark = false;
        var capped:Object = LootContainerService.execute(
            "claim", claimParams(infoSnapshot, 0, "claim.info.cap"));
        check(!capped.success && capped.error == "cap_reached"
                && _root.收集品栏.情报.getValue(INFORMATION) == 4
                && infoFlow.inventory.getItem("0") === infoItem && !_root.存档系统.dirtyMark,
            "情报已满或差部分容量时整格保留，不静默 clamp");
        _root.收集品栏.情报.addValue(INFORMATION, -4);
        var infoClaim:Object = LootContainerService.execute(
            "claim", claimParams(infoSnapshot, 0, "claim.info.ok"));
        check(infoClaim.success && _root.收集品栏.情报.getValue(INFORMATION) == 2
                && infoFlow.inventory.getItem("0") == null,
            "目标可完整接收时情报整格提交并删除 source");
        LootContainerService.execute("close",
            closeParams(infoClaim, "close.info", infoClaim.closeLease, false));
    }

    private static function testCurrencyClaims():Void {
        resetWorld();
        var flow:Object = activate([
            stack("金币", 5, 501), stack("K点", 6, 502),
            stack("经验值", 7, 503), stack("技能点", 8, 504)
        ], "s1.currency");
        var current:Object = snapshot(flow);
        current = LootContainerService.execute("claim", claimParams(current, 0, "claim.money"));
        current = LootContainerService.execute("claim", claimParams(current, 1, "claim.kpoints"));
        current = LootContainerService.execute("claim", claimParams(current, 2, "claim.experience"));
        current = LootContainerService.execute("claim", claimParams(current, 3, "claim.skill"));
        check(current.success && _root.金钱 == 105 && _root.虚拟币 == 26
                && _root.经验值 == 37 && _root.技能点数 == 48
                && _root.__lootLevelChecks == 1 && current.remainingCount == 0,
            "金币/K点/经验值/技能点使用内部稳定键进入各自权威域");
        LootContainerService.execute("close",
            closeParams(current, "close.currency", current.closeLease, false));
    }

    private static function testAbandonExpireAndDuplicateClose():Void {
        resetWorld();
        var flow:Object = activate([stack(STACK, 1, 601)], "s1.abandon");
        var snap:Object = snapshot(flow);
        var lease:String = snap.closeLease;
        var abandonRequest:Object = closeParams(snap, "close.abandon", lease, true);
        _root._webPanelPauseLease = "test-terminal-visual-close-lease";
        var abandoned:Object = LootContainerService.execute("close", abandonRequest);
        var duplicate:Object = LootContainerService.execute("close", abandonRequest);
        check(abandoned.success && abandoned.state == "ABANDONED"
                && abandoned.terminal.remainingCount == 1 && duplicate.success
                && flow.target.playCount == 1 && !flow.target.stopped
                && _root._webPanelPauseLease == "test-terminal-visual-close-lease",
            "显式放弃产生 ABANDONED tombstone，duplicate close 不重复写；终态保留 pause 至 Host exact visual close");

        resetWorld();
        var expiring:Object = activate([stack(STACK, 2, 602)], "s1.expire");
        var activeSnapshot:Object = snapshot(expiring);
        _root._webPanelPauseLease = "test-scene-terminal-visual-close-lease";
        LootContainerService.expireScene("scene_cleanup");
        var expired:Object = LootContainerService.execute("query", queryParams(activeSnapshot));
        check(expired.success && expired.state == "EXPIRED"
                && expired.terminal.reason == "scene_cleanup" && expired.remainingCount == 1
                && _root._webPanelPauseLease == "test-scene-terminal-visual-close-lease",
            "scene cleanup 产生 EXPIRED 并保留 remainingCount；可见面板 lease 留给 Host teardown");
    }

    private static function testSuspendAnchorReopenIdentityAndStaleClose():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
            var flow:Object = activate([stack(STACK, 3, 610)], "s1.suspend-reopen");
            var before:Object = snapshot(flow);
            var oldLease:String = before.closeLease;
            var suspendRequest:Object = closeParams(
                before, "close.suspend", oldLease, false);
            var suspended:Object = LootContainerService.execute("close", suspendRequest);
            var duplicateSuspend:Object = LootContainerService.execute("close", suspendRequest);
            var fallback:Object = LootContainerService.consumeLegacyFallback(flow.target);
            check(suspended.success && suspended.state == "LOOT_SUSPENDED"
                    && suspended.closeLease == "" && suspended.terminal == null
                    && suspended.snapshots.length == 0 && suspended.remainingCount == 1
                    && duplicateSuspend.success && duplicateSuspend.state == "LOOT_SUSPENDED"
                    && !fallback.success && fallback.error == "loot_suspended"
                    && flow.target._killed === true && flow.target.stopCount == 1
                    && flow.target.stopped,
                "非空 close(false) 落 first-class suspend，保留 killed/同一 inventory 并旁路 legacy");

            var pauseReleased:Object = LootContainerService.releaseSuspendedPauseForClose();
            var same:Object = LootContainerService.beginFixture(flow.target);
            var neighbour:Object = LootContainerService.beginFixture(makeTarget("s1.suspend-neighbour"));
            var heroArea:Object = {};
            heroArea.hitTest = function(other:Object):Boolean { return true; };
            BoxInteractionArbiter.__setTestInteractionContext(
                {_x:0, Z轴坐标:0, area:heroArea}, null);
            try {
                _root.gameworld.dispatcher.emit();
            } finally {
                BoxInteractionArbiter.__clearTestInteractionContext();
            }
            check(pauseReleased.handled && pauseReleased.success
                    && same.handled && same.reopen && same.chestSessionId == before.chestSessionId
                    && neighbour.handled && !neighbour.reopen
                    && neighbour.reason == "loot_flow_busy"
                    && flow.target.dispatcher.pickUpCount == 1,
                "只有 exact suspended killed target 恢复互动资格；相邻网格箱保持 single-flow busy");

            var resumed:Object = LootContainerService.resumeSuspended(flow.target);
            var staleClose:Object = LootContainerService.execute("close", suspendRequest);
            var after:Object = LootContainerService.execute("query", queryParams(before));
            if (callbacks.length > 0) callbacks[0]({success:true, accepted:true});
            check(resumed.success && resumed.reopened && resumed.state == "LOOT_ACTIVE"
                    && resumed.chestSessionId == before.chestSessionId
                    && resumed.lootContainerId == before.lootContainerId
                    && resumed.containerEpoch == before.containerEpoch
                    && resumed.closeLease != "" && resumed.closeLease != oldLease
                    && sent.length == 1 && after.success && after.remainingCount == 1
                    && after.snapshots[0].slots[0].item.quantity == 3
                    && !staleClose.success && staleClose.error == "operation_conflict"
                    && flow.target.stopCount == 1 && flow.target._killed === true,
                "reopen 沿用 triple/物品且刷新 lease；旧 suspend op 与拾取副作用均不重放");
            LootContainerService.expireScene("scene_cleanup");
            check(flow.target.playCount == 1 && !flow.target.stopped,
                "terminal 先撤 anchor，再让 held target 自然继续 authored 时间轴");
        } finally {
            _root.server = previousServer;
        }
    }

    private static function testSuspendPauseSocketBypass():Void {
        resetWorld();
        var flow:Object = activate([stack(STACK, 1, 611)], "s1.suspend-socket");
        var before:Object = snapshot(flow);
        var suspended:Object = LootContainerService.execute("close",
            closeParams(before, "close.suspend-socket", before.closeLease, false));
        var first:Object = LootContainerService.reconcileSocketDetach(flow.target);
        _root._webPanelPauseLease = "later-panel-lease";
        var second:Object = LootContainerService.reconcileSocketDetach(flow.target);
        var fallback:Object = LootContainerService.consumeLegacyFallback(flow.target);
        check(suspended.success && first.success && first.suspendedNoRenderer
                && first.pauseReleaseRequired && first.pauseReleased
                && first.state == "LOOT_SUSPENDED"
                && second.success && second.suspendedNoRenderer
                && second.pauseReleaseRequired !== true
                && _root._webPanelPauseLease == "later-panel-lease"
                && !fallback.success && fallback.error == "loot_suspended"
                && LootContainerService.canReopenSuspendedTarget(flow.target),
            "socket close 对 suspend 只完成 exact pause proof；稳定态不 renderer、不 pending、不释放后来 lease");
        _root._webPanelPauseLease = undefined;
        LootContainerService.expireScene("scene_cleanup");
    }

    private static function testSuspendNoSendRollback():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var flow:Object = activate([stack(STACK, 2, 612)], "s1.suspend-nosend");
            var before:Object = snapshot(flow);
            LootContainerService.execute("close",
                closeParams(before, "close.suspend-nosend", before.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();
            _root.server = null;
            var rejected:Object = LootContainerService.resumeSuspended(flow.target);
            var guarded:Object = LootContainerService.beginFixture(flow.target);
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
            var resumed:Object = LootContainerService.resumeSuspended(flow.target);
            check(!rejected.success && rejected.error == "panel_open_unavailable"
                    && rejected.state == "LOOT_SUSPENDED"
                    && guarded.handled && guarded.reopen
                    && resumed.success && resumed.state == "LOOT_ACTIVE"
                    && resumed.chestSessionId == before.chestSessionId
                    && sent.length == 1 && flow.target.stopCount == 1,
                "同步 no-send 保持 SUSPENDED anchor；transport 恢复后仍以原对象重开");
            if (callbacks.length > 0) callbacks[0]({success:true, accepted:true});
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
        }
    }

    private static function testSuspendSynchronousCallbackFailureRestoresAnchor():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var presented:Array = [];
            installLegacyRenderer(presented);
            // 对齐真实 ServerManager：transport 对象 / 方法仍存在，但 socket
            // 未连接时 sendTaskWithCallback 会在当前调用栈同步回调失败。
            _root.server = {
                isSocketConnected:false,
                sendTaskWithCallback:function(task:String, payload:Object, extra:Object,
                                              callback:Function, timeoutFrames:Number):Void {
                    callback({success:false, error:"socket not connected"});
                }
            };
            var flow:Object = activate([stack(STACK, 2, 615)], "s1.suspend-sync-callback");
            var before:Object = snapshot(flow);
            LootContainerService.execute("close",
                closeParams(before, "close.suspend-sync-callback", before.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();

            var rejected:Object = LootContainerService.resumeSuspended(flow.target);
            var authority:Object = LootContainerService.execute("query", queryParams(before));
            var guard:Object = LootContainerService.beginFixture(flow.target);
            check(!rejected.success && rejected.error == "panel_open_unavailable"
                    && rejected.state == "LOOT_SUSPENDED" && rejected.reopened !== true
                    && authority.success && authority.state == "LOOT_SUSPENDED"
                    && authority.remainingCount == 1 && authority.closeLease == ""
                    && guard.handled && guard.reopen
                    && LootContainerService.canReopenSuspendedTarget(flow.target)
                    && presented.length == 0 && flow.target.stopped,
                "transport 存在但 disconnected 的同步 callback failure 恢复 exact suspend，不误报 reopen/不回弹旧 UI");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testSuspendAsyncRejectionRestoresAndStalesLateCallback():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            var presented:Array = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            var flow:Object = activate([stack(STACK, 1, 616)], "s1.suspend-async-reject");
            var before:Object = snapshot(flow);
            LootContainerService.execute("close",
                closeParams(before, "close.suspend-async-reject", before.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();

            var first:Object = LootContainerService.resumeSuspended(flow.target);
            callbacks[0]({success:false, accepted:false, error:"panel_busy"});
            var suspended:Object = LootContainerService.execute("query", queryParams(before));
            var guarded:Object = LootContainerService.beginFixture(flow.target);

            // 再次重开后重放旧 attempt callback，exact openAttemptSeq 必须使其惰性。
            var second:Object = LootContainerService.resumeSuspended(flow.target);
            callbacks[0]({success:false, error:"callback timeout"});
            var active:Object = LootContainerService.execute("query", queryParams(before));
            if (callbacks.length > 1) callbacks[1]({success:true, accepted:true});
            check(first.success && first.reopened && callbacks.length == 2
                    && suspended.success && suspended.state == "LOOT_SUSPENDED"
                    && guarded.handled && guarded.reopen
                    && second.success && second.reopened && active.success
                    && active.state == "LOOT_ACTIVE" && active.remainingCount == 1
                    && presented.length == 0 && flow.target.stopCount == 1,
                "async rejection 收回 exact suspend；新 reopen 后迟到旧 callback 不污染 authority/不回弹旧 UI");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testSuspendAsyncTimeoutRestoresAnchor():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            var presented:Array = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            var flow:Object = activate([stack(STACK, 1, 617)], "s1.suspend-async-timeout");
            var before:Object = snapshot(flow);
            LootContainerService.execute("close",
                closeParams(before, "close.suspend-async-timeout", before.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();

            var dispatched:Object = LootContainerService.resumeSuspended(flow.target);
            callbacks[0]({success:false, error:"callback timeout"});
            var authority:Object = LootContainerService.execute("query", queryParams(before));
            var guard:Object = LootContainerService.beginFixture(flow.target);
            var blockedBeforeProof:Boolean =
                !LootContainerService.canReopenSuspendedTarget(flow.target);
            var released:Object = LootContainerService.releaseSuspendedPauseForClose();
            check(dispatched.success && dispatched.reopened && sent.length == 1
                    && authority.success && authority.state == "LOOT_SUSPENDED"
                    && authority.remainingCount == 1 && authority.closeLease == ""
                    && guard.handled && guard.reopen
                    && blockedBeforeProof && released.handled && released.success
                    && LootContainerService.canReopenSuspendedTarget(flow.target)
                    && presented.length == 0 && flow.target.stopped,
                "async timeout 收回原 suspend，但必须等 exact unpause/detach proof 后才重新开放 anchor");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testSuspendSocketDetachOrderingAndLateCallback():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            var presented:Array = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            var flow:Object = activate([stack(STACK, 1, 618)], "s1.suspend-socket-order");
            var before:Object = snapshot(flow);
            LootContainerService.execute("close",
                closeParams(before, "close.suspend-socket-order", before.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();

            var first:Object = LootContainerService.resumeSuspended(flow.target);
            var firstAttempt:Number = Number(sent[0].payload.initData.openAttemptSeq);
            // 对齐 ServerManager.onSocketClose：先执行 transport detach，随后才失败
            // _pendingCallbacks。此时绝不能先创建 legacy renderer。
            var detached:Object = LootContainerService.reconcileSocketDetach(flow.target);
            var suspended:Object = LootContainerService.execute("query",
                proofQueryParams(before, firstAttempt, "socket.first.attempt"));
            var canRetry:Boolean = LootContainerService.canReopenSuspendedTarget(flow.target);

            var second:Object = LootContainerService.resumeSuspended(flow.target);
            var secondAttempt:Number = Number(sent[1].payload.initData.openAttemptSeq);
            var staleRecovery:Object = LootContainerService.handlePanelRecovery(
                recoveryEnvelope(before, firstAttempt,
                    "recovery.stale.first", "web_mount_failed"));
            callbacks[0]({success:false, error:"socket closed"});
            var afterLate:Object = LootContainerService.execute("query", queryParams(before));
            var currentRecovery:Object = LootContainerService.handlePanelRecovery(
                recoveryEnvelope(before, secondAttempt,
                    "recovery.current.second", "web_mount_failed"));
            var preAckProof:Object = LootContainerService.execute("query",
                proofQueryParams(before, secondAttempt, "recovery.current.second"));
            callbacks[1]({success:true, accepted:true});
            var recoveredSuspended:Object = LootContainerService.execute(
                "query", proofQueryParams(before, secondAttempt,
                    "recovery.current.second"));
            var duplicateRecovery:Object = LootContainerService.handlePanelRecovery(
                recoveryEnvelope(before, secondAttempt,
                    "recovery.current.second", "web_mount_failed"));
            var third:Object = LootContainerService.resumeSuspended(flow.target);
            var oldProofDuringThird:Object = LootContainerService.execute("query",
                proofQueryParams(before, secondAttempt, "recovery.current.second"));
            // second attempt 的重复 callback 迟到；第三次 attempt 必须保持 ACTIVE。
            callbacks[1]({success:true, accepted:true});
            var afterSecondLate:Object = LootContainerService.execute(
                "query", queryParams(before));
            if (callbacks.length > 2) callbacks[2]({success:true, accepted:true});

            check(first.success && first.reopened
                    && detached.success && detached.suspendedNoRenderer
                    && detached.state == "LOOT_SUSPENDED"
                    && suspended.success && suspended.state == "LOOT_SUSPENDED"
                    && canRetry && second.success && second.reopened
                    && secondAttempt > firstAttempt
                    && !staleRecovery.handled && staleRecovery.reason == "stale_open_attempt"
                    && afterLate.success && afterLate.state == "LOOT_ACTIVE"
                    && currentRecovery.handled && !currentRecovery.recovered
                    && currentRecovery.reason == "recovery_pending"
                    && !preAckProof.success && preAckProof.error == "recovery_pending"
                    && recoveredSuspended.success
                    && recoveredSuspended.state == "LOOT_SUSPENDED"
                    && duplicateRecovery.handled && duplicateRecovery.recovered
                    && duplicateRecovery.duplicate
                    && third.success && third.reopened
                    && !oldProofDuringThird.success
                    && afterSecondLate.success && afterSecondLate.state == "LOOT_ACTIVE"
                    && presented.length == 0 && callbacks.length == 3,
                "socket proof 恢复 suspend；pre-ACK recovery 只登记，ACK 后才应用且旧 proof 不证明新 ACTIVE");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testSuspendReopenAnchorLossExpires():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            var presented:Array = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            var flow:Object = activate([stack(STACK, 1, 619)], "s1.suspend-reopen-anchor-loss");
            var before:Object = snapshot(flow);
            LootContainerService.execute("close",
                closeParams(before, "close.suspend-reopen-anchor-loss", before.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();
            var dispatched:Object = LootContainerService.resumeSuspended(flow.target);

            // callback 前 target 已失去 scene anchor；恢复不得停留 ACTIVE，也不得
            // 把同一 inventory 交给旧 renderer。
            flow.target.area = null;
            callbacks[0]({success:false, accepted:false, error:"panel_busy"});
            var expired:Object = LootContainerService.execute("query", queryParams(before));
            var nextTarget:Object = makeTarget("s1.after-reopen-anchor-loss");
            var next:Object = LootContainerService.beginFixture(nextTarget);
            check(dispatched.success && dispatched.reopened
                    && expired.success && expired.state == "EXPIRED"
                    && expired.remainingCount == 1 && expired.terminal != null
                    && expired.terminal.reason == "suspended_anchor_lost"
                    && !LootContainerService.canReopenSuspendedTarget(flow.target)
                    && presented.length == 0 && flow.target.playCount == 1
                    && next.handled && next.reserved,
                "reopen rollback 丢失 exact anchor 时显式 EXPIRED、释放 busy，绝不回弹 legacy");
            LootContainerService.abortReservedOpen(nextTarget, "test_cleanup");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testSuspendSocketDetachAnchorLossReleasesPause():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            var presented:Array = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            var flow:Object = activate([stack(STACK, 1, 621)],
                "s1.suspend-socket-anchor-loss");
            var before:Object = snapshot(flow);
            LootContainerService.execute("close", closeParams(before,
                "close.suspend-socket-anchor-loss", before.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();
            var dispatched:Object = LootContainerService.resumeSuspended(flow.target);
            _root._webPanelPauseLease = "test-reopen-anchor-loss-lease";

            // 真实 socket close 先于 pending callback，且 target 已脱离 scene。
            // terminal EXPIRED 不能把本次 reopen 的全局 pause lease 留在空中。
            flow.target.area = null;
            var attemptSeq:Number = Number(sent[0].payload.initData.openAttemptSeq);
            var detached:Object = LootContainerService.reconcileSocketDetach(flow.target);
            var terminal:Object = LootContainerService.execute("query",
                proofQueryParams(before, attemptSeq, "socket.anchor.loss"));
            if (callbacks.length > 0) callbacks[0]({success:false, error:"socket closed"});
            var nextTarget:Object = makeTarget("s1.after-socket-anchor-loss");
            var next:Object = LootContainerService.beginFixture(nextTarget);
            check(dispatched.success && dispatched.reopened
                    && detached.success && detached.suspendedNoRenderer
                    && detached.state == "EXPIRED" && detached.pauseReleaseRequired === false
                    && _root._webPanelPauseLease == undefined
                    && terminal.success && terminal.state == "EXPIRED"
                    && terminal.terminal != null
                    && terminal.terminal.reason == "suspended_anchor_lost"
                    && presented.length == 0 && flow.target.playCount == 1
                    && next.handled && next.reserved,
                "pending reopen 断线+锚点丢失先释放 exact pause，再落 EXPIRED 且不渲染 legacy");
            LootContainerService.abortReservedOpen(nextTarget, "test_cleanup");
        } finally {
            _root._webPanelPauseLease = undefined;
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testSuspendSocketDetachPauseReleaseRetry():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            var presented:Array = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            var flow:Object = activate([stack(STACK, 1, 622)],
                "s1.suspend-socket-unpause-retry");
            var before:Object = snapshot(flow);
            LootContainerService.execute("close", closeParams(before,
                "close.suspend-socket-unpause-retry", before.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();
            var dispatched:Object = LootContainerService.resumeSuspended(flow.target);
            _root._webPanelPauseLease = "test-reopen-unpause-retry-lease";
            LootContainerService.testOnlyFailNextTransportHandoff("unpause");

            var attemptSeq:Number = Number(sent[0].payload.initData.openAttemptSeq);
            var firstDetach:Object = LootContainerService.reconcileSocketDetach(flow.target);
            var fenceHeld:Boolean = LootContainerService.hasPendingTransportDetach();
            var leaseHeld:Boolean = _root._webPanelPauseLease != undefined;
            var ordinaryBlocked:Object = LootContainerService.execute(
                "query", queryParams(before));
            // exact socket proof 只重试被冻结的 pause-release 阶段；不得重滚、重发 open
            // 或先创建 legacy renderer。
            LootContainerService.testOnlyFailNextTransportHandoff("unpause");
            var proofStillPending:Object = LootContainerService.execute("query",
                proofQueryParams(before, attemptSeq, "socket.unpause.retry"));
            var recovered:Object = LootContainerService.execute("query",
                proofQueryParams(before, attemptSeq, "socket.unpause.retry"));
            var fenceReleased:Boolean = !LootContainerService.hasPendingTransportDetach();
            if (callbacks.length > 0) callbacks[0]({success:false, error:"socket closed"});
            var stable:Object = LootContainerService.execute("query", queryParams(before));

            check(dispatched.success && dispatched.reopened && sent.length == 1
                    && !firstDetach.success && firstDetach.suspendedNoRenderer
                    && firstDetach.pauseReleaseRequired
                    && firstDetach.error == "suspend_pause_release_failed"
                    && firstDetach.state == "LOOT_COMMIT_PENDING"
                    && fenceHeld && leaseHeld && presented.length == 0
                    && !ordinaryBlocked.success && ordinaryBlocked.error == "commit_pending"
                    && !proofStillPending.success
                    && proofStillPending.state == "LOOT_COMMIT_PENDING"
                    && proofStillPending.error == "commit_pending"
                    && recovered.success && recovered.state == "LOOT_SUSPENDED"
                    && recovered.remainingCount == 1 && recovered.closeLease == ""
                    && fenceReleased && _root._webPanelPauseLease == undefined
                    && LootContainerService.canReopenSuspendedTarget(flow.target)
                    && stable.success && stable.state == "LOOT_SUSPENDED",
                "pending reopen pause release 首次失败保留完整 PENDING fence；causal query 仅重试 release 后恢复 suspend");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root._webPanelPauseLease = undefined;
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testSuspendDirectReopenPauseReleaseRetry():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            var presented:Array = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            var flow:Object = activate([stack(STACK, 1, 623)],
                "s1.suspend-direct-unpause-retry");
            var before:Object = snapshot(flow);
            LootContainerService.execute("close", closeParams(before,
                "close.suspend-direct-unpause-retry", before.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();
            var dispatched:Object = LootContainerService.resumeSuspended(flow.target);

            // 明确 callback rejection 已经恢复 non-empty SUSPENDED；真实 lease 仍在时
            // 必须冻结 reopen 资格，exact webPanelUnpause 失败后可原地重试。
            _root._webPanelPauseLease = "test-direct-reopen-unpause-lease";
            callbacks[0]({success:false, accepted:false, error:"panel_busy"});
            var suspendedBefore:Object = LootContainerService.execute(
                "query", queryParams(before));
            var blockedBefore:Boolean = !LootContainerService.canReopenSuspendedTarget(
                flow.target);
            LootContainerService.testOnlyFailNextTransportHandoff("unpause");
            var firstRelease:Object = LootContainerService.releaseSuspendedPauseForClose();
            var suspendedAfterFailure:Object = LootContainerService.execute(
                "query", queryParams(before));
            var secondRelease:Object = LootContainerService.releaseSuspendedPauseForClose();
            var stable:Object = LootContainerService.execute("query", queryParams(before));
            var duplicateRelease:Object = LootContainerService.releaseSuspendedPauseForClose();

            check(dispatched.success && dispatched.reopened && sent.length == 1
                    && suspendedBefore.success
                    && suspendedBefore.state == "LOOT_SUSPENDED"
                    && blockedBefore && firstRelease.handled && !firstRelease.success
                    && suspendedAfterFailure.success
                    && suspendedAfterFailure.authorityRevision
                        == suspendedBefore.authorityRevision
                    && !LootContainerService.hasPendingTransportDetach()
                    && secondRelease.handled && secondRelease.success
                    && stable.success && stable.state == "LOOT_SUSPENDED"
                    && stable.authorityRevision == suspendedBefore.authorityRevision
                    && !duplicateRelease.handled
                    && _root._webPanelPauseLease == undefined
                    && LootContainerService.canReopenSuspendedTarget(flow.target)
                    && presented.length == 0 && flow.target.playCount == 0,
                "direct reopen rejection 的 non-empty pause release 可 exact 重试；不改 revision、不渲染 legacy");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root._webPanelPauseLease = undefined;
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testSuspendTerminalReopenPauseReleaseRetry():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            // empty reopen failure：首次内部 release 失败后必须保留 PENDING fence；
            // 未授权 proof 只投影 commit_pending，不得顺带推进 release。
            resetWorld();
            var emptySent:Array = [];
            var emptyCallbacks:Array = [];
            var emptyPresented:Array = [];
            installPanelTransport(emptySent, emptyCallbacks);
            installLegacyRenderer(emptyPresented);
            var emptyFlow:Object = activate([stack(STACK, 1, 625)],
                "s1.suspend-terminal-empty-unpause-retry");
            var emptyBefore:Object = snapshot(emptyFlow);
            LootContainerService.execute("close", closeParams(emptyBefore,
                "close.suspend-terminal-empty-unpause-retry",
                emptyBefore.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();
            var emptyDispatched:Object = LootContainerService.resumeSuspended(
                emptyFlow.target);
            var emptyAttemptSeq:Number = Number(
                emptySent[0].payload.initData.openAttemptSeq);
            emptyFlow.inventory.remove(0);
            _root._webPanelPauseLease = "test-terminal-empty-unpause-lease";
            LootContainerService.testOnlyFailNextTransportHandoff("unpause");
            emptyCallbacks[0]({success:false, accepted:false, error:"panel_busy"});
            var emptyFenceHeld:Boolean = LootContainerService.hasPendingTransportDetach();
            var emptyPending:Object = LootContainerService.execute("query",
                proofQueryParams(emptyBefore, emptyAttemptSeq, "unapplied.empty.retry"));
            var emptyPendingRevision:Number = Number(emptyPending.authorityRevision);
            LootContainerService.testOnlyFailNextTransportHandoff("unpause");
            var emptyReleaseFailed:Object =
                LootContainerService.releaseSuspendedPauseForClose();
            var emptyPendingAgain:Object = LootContainerService.execute("query",
                proofQueryParams(emptyBefore, emptyAttemptSeq, "unapplied.empty.retry"));
            var emptyReleaseDone:Object =
                LootContainerService.releaseSuspendedPauseForClose();
            var emptyTerminal:Object = LootContainerService.execute(
                "query", queryParams(emptyBefore));
            var emptyStable:Object = LootContainerService.execute(
                "query", queryParams(emptyBefore));
            var emptyDuplicateRelease:Object =
                LootContainerService.releaseSuspendedPauseForClose();
            var afterEmptyTarget:Object = makeTarget("s1.after-terminal-empty-retry");
            var afterEmpty:Object = LootContainerService.beginFixture(afterEmptyTarget);
            LootContainerService.abortReservedOpen(afterEmptyTarget, "test_cleanup");

            // anchor-lost reopen failure 走同一 fence；成功释放后必须只落一次 EXPIRED。
            resetWorld();
            var anchorSent:Array = [];
            var anchorCallbacks:Array = [];
            var anchorPresented:Array = [];
            installPanelTransport(anchorSent, anchorCallbacks);
            installLegacyRenderer(anchorPresented);
            var anchorFlow:Object = activate([stack(STACK, 1, 626)],
                "s1.suspend-terminal-anchor-unpause-retry");
            var anchorBefore:Object = snapshot(anchorFlow);
            LootContainerService.execute("close", closeParams(anchorBefore,
                "close.suspend-terminal-anchor-unpause-retry",
                anchorBefore.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();
            var anchorDispatched:Object = LootContainerService.resumeSuspended(
                anchorFlow.target);
            var anchorAttemptSeq:Number = Number(
                anchorSent[0].payload.initData.openAttemptSeq);
            anchorFlow.target.area = null;
            _root._webPanelPauseLease = "test-terminal-anchor-unpause-lease";
            LootContainerService.testOnlyFailNextTransportHandoff("unpause");
            anchorCallbacks[0]({success:false, accepted:false, error:"panel_busy"});
            var anchorFenceHeld:Boolean = LootContainerService.hasPendingTransportDetach();
            var anchorPending:Object = LootContainerService.execute("query",
                proofQueryParams(anchorBefore, anchorAttemptSeq, "unapplied.anchor.retry"));
            var anchorReleaseDone:Object =
                LootContainerService.releaseSuspendedPauseForClose();
            var anchorTerminal:Object = LootContainerService.execute(
                "query", queryParams(anchorBefore));
            var anchorStable:Object = LootContainerService.execute(
                "query", queryParams(anchorBefore));
            var afterAnchorTarget:Object = makeTarget("s1.after-terminal-anchor-retry");
            var afterAnchor:Object = LootContainerService.beginFixture(afterAnchorTarget);

            check(emptyDispatched.success && emptyDispatched.reopened
                    && emptyFenceHeld && !emptyPending.success
                    && emptyPending.state == "LOOT_COMMIT_PENDING"
                    && emptyPending.error == "commit_pending"
                    && emptyReleaseFailed.handled && !emptyReleaseFailed.success
                    && emptyPendingAgain.authorityRevision == emptyPendingRevision
                    && emptyReleaseDone.handled && emptyReleaseDone.success
                    && emptyTerminal.success && emptyTerminal.state == "CONSUMED"
                    && emptyTerminal.terminal != null
                    && emptyTerminal.terminal.reason == "reopen_failure_empty"
                    && emptyStable.authorityRevision == emptyTerminal.authorityRevision
                    && !emptyDuplicateRelease.handled
                    && emptyPresented.length == 0 && emptyFlow.target.playCount == 1
                    && afterEmpty.handled && afterEmpty.reserved
                    && anchorDispatched.success && anchorDispatched.reopened
                    && anchorFenceHeld && !anchorPending.success
                    && anchorPending.state == "LOOT_COMMIT_PENDING"
                    && anchorPending.error == "commit_pending"
                    && anchorReleaseDone.handled && anchorReleaseDone.success
                    && anchorTerminal.success && anchorTerminal.state == "EXPIRED"
                    && anchorTerminal.terminal != null
                    && anchorTerminal.terminal.reason == "suspended_anchor_lost"
                    && anchorStable.authorityRevision == anchorTerminal.authorityRevision
                    && anchorPresented.length == 0 && anchorFlow.target.playCount == 1
                    && afterAnchor.handled && afterAnchor.reserved,
                "empty/anchor-lost reopen 的 pause release 失败保留可重试 fence；终态只提交一次且 proof shape 合法");
            LootContainerService.abortReservedOpen(afterAnchorTarget, "test_cleanup");
        } finally {
            _root._webPanelPauseLease = undefined;
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testSuspendAcceptedRecoveryStaysSuspended():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            var presented:Array = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            var flow:Object = activate([stack(STACK, 2, 623)],
                "s1.suspend-accepted-recovery");
            var before:Object = snapshot(flow);
            LootContainerService.execute("close", closeParams(before,
                "close.suspend-accepted-recovery", before.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();
            var dispatched:Object = LootContainerService.resumeSuspended(flow.target);
            var attemptSeq:Number = Number(sent[0].payload.initData.openAttemptSeq);
            callbacks[0]({success:true, accepted:true});

            var recovered:Object = LootContainerService.handlePanelRecovery({
                task:"cmd", action:"lootPanelRecovery",
                chestSessionId:before.chestSessionId,
                lootContainerId:before.lootContainerId,
                containerEpoch:before.containerEpoch,
                openAttemptSeq:attemptSeq,
                recoveryNonce:"recovery.accepted.reopen",
                reason:"web_mount_failed"
            });
            var authority:Object = LootContainerService.execute("query", queryParams(before));
            var proof:Object = LootContainerService.execute("query",
                proofQueryParams(before, attemptSeq, "recovery.accepted.reopen"));
            var guard:Object = LootContainerService.guardAnyGridFixture(
                flow.target);
            check(dispatched.success && dispatched.reopened
                    && recovered.handled && recovered.recovered && !recovered.rendered
                    && recovered.suspended
                    && authority.success && authority.state == "LOOT_SUSPENDED"
                    && authority.remainingCount == 1
                    && proof.success && proof.state == "LOOT_SUSPENDED"
                    && LootContainerService.canReopenSuspendedTarget(flow.target)
                    && guard.handled && guard.reopen && !guard.recovery
                    && presented.length == 0,
                "reopen recovery 在 accepted callback 前后都回到 first-class SUSPENDED，不创建 legacy UI");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testCloseAttemptProofSurvivesRejectedReopen():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            var presented:Array = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            var flow:Object = activate([stack(STACK, 2, 625)],
                "s1.close-attempt-proof");
            LootContainerService.requestOpenPanel();
            var attemptA:Number = Number(sent[0].payload.initData.openAttemptSeq);
            callbacks[0]({success:true, accepted:true});
            var before:Object = snapshot(flow);
            var closed:Object = LootContainerService.execute("close", closeParams(before,
                "close.attempt-proof", before.closeLease, false));
            var proofAfterLostClose:Object = LootContainerService.execute("query",
                proofQueryParams(before, attemptA, "unknown.close.a"));
            var lateRecovery:Object = LootContainerService.handlePanelRecovery(
                recoveryEnvelope(before, attemptA, "late.close.a", "web_mount_failed"));
            callbacks[0]({success:true, accepted:true});
            LootContainerService.releaseSuspendedPauseForClose();

            var reopenedB:Object = LootContainerService.resumeSuspended(flow.target);
            var attemptB:Number = Number(sent[1].payload.initData.openAttemptSeq);
            var proofAWhileBActive:Object = LootContainerService.execute("query",
                proofQueryParams(before, attemptA, "unknown.close.a"));
            var staleRecoveryA:Object = LootContainerService.handlePanelRecovery(
                recoveryEnvelope(before, attemptA, "late.close.a", "web_mount_failed"));
            callbacks[1]({success:false, accepted:false, error:"panel_busy"});
            var proofAAfterBReject:Object = LootContainerService.execute("query",
                proofQueryParams(before, attemptA, "unknown.close.a"));

            // no-send 与明确 rejection 都不是新 Host binding ACK，不得淘汰 A。
            var workingServer:Object = _root.server;
            _root.server = null;
            var noSend:Object = LootContainerService.resumeSuspended(flow.target);
            _root.server = workingServer;
            var proofAAfterNoSend:Object = LootContainerService.execute("query",
                proofQueryParams(before, attemptA, "unknown.close.a"));
            var reopenedC:Object = LootContainerService.resumeSuspended(flow.target);
            callbacks[2]({success:false, accepted:false, error:"panel_busy"});
            var proofAAfterCReject:Object = LootContainerService.execute("query",
                proofQueryParams(before, attemptA, "unknown.close.a"));

            check(closed.success && closed.state == "LOOT_SUSPENDED"
                    && proofAfterLostClose.success
                    && proofAfterLostClose.state == "LOOT_SUSPENDED"
                    && !lateRecovery.handled && lateRecovery.reason == "no_active_authority"
                    && reopenedB.success && reopenedB.reopened
                    && attemptB == attemptA + 1
                    && !proofAWhileBActive.success
                    && !staleRecoveryA.handled
                    && staleRecoveryA.reason == "stale_open_attempt"
                    && proofAAfterBReject.success
                    && proofAAfterBReject.state == "LOOT_SUSPENDED"
                    && !noSend.success && noSend.error == "panel_open_unavailable"
                    && proofAAfterNoSend.success
                    && reopenedC.success && reopenedC.reopened
                    && proofAAfterCReject.success
                    && presented.length == 0,
                "close 不提前推进 attempt；A proof 丢回包后跨 B/C rejection 与no-send 仍可证明 suspend");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testRecoveryProofLedgerOrderingAndCapacity():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            var presented:Array = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            var flow:Object = activate([stack(STACK, 1, 626)],
                "s1.proof-ledger-capacity");
            LootContainerService.requestOpenPanel();
            var attemptA:Number = Number(sent[0].payload.initData.openAttemptSeq);
            callbacks[0]({success:true, accepted:true});
            var before:Object = snapshot(flow);
            LootContainerService.execute("close", closeParams(before,
                "close.proof-ledger-capacity", before.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();

            var socketAttempts:Array = [];
            for (var i:Number = 0; i < 7; i++) {
                var reopened:Object = LootContainerService.resumeSuspended(flow.target);
                var attempt:Number = Number(sent[sent.length - 1].payload.initData.openAttemptSeq);
                socketAttempts.push(attempt);
                var detached:Object = LootContainerService.reconcileSocketDetach(flow.target);
                callbacks[callbacks.length - 1]({success:false, error:"socket closed"});
                if (!reopened.success || !detached.success
                        || detached.state != "LOOT_SUSPENDED") break;
            }
            var blocked:Object = LootContainerService.resumeSuspended(flow.target);
            var latestBeforePrune:Number = Number(
                socketAttempts[socketAttempts.length - 1]);
            var firstLatestProof:Object = LootContainerService.execute("query",
                proofQueryParams(before, latestBeforePrune, "socket.latest.first"));

            var reopenedAfterPrune:Object = LootContainerService.resumeSuspended(flow.target);
            var laterAttempt:Number = Number(sent[sent.length - 1].payload.initData.openAttemptSeq);
            var laterDetached:Object = LootContainerService.reconcileSocketDetach(flow.target);
            callbacks[callbacks.length - 1]({success:false, error:"socket closed"});
            // B proof 的超时重试只可 prune <B，绝不能删掉已完成的 later proof。
            var delayedOlderProof:Object = LootContainerService.execute("query",
                proofQueryParams(before, latestBeforePrune, "socket.latest.retry"));

            var reopenedNewest:Object = LootContainerService.resumeSuspended(flow.target);
            var newestAttempt:Number = Number(sent[sent.length - 1].payload.initData.openAttemptSeq);
            var newestDetached:Object = LootContainerService.reconcileSocketDetach(flow.target);
            callbacks[callbacks.length - 1]({success:false, error:"socket closed"});
            var laterProofAfterDelayedOlder:Object = LootContainerService.execute("query",
                proofQueryParams(before, laterAttempt, "socket.later.proof"));

            check(socketAttempts.length == 7
                    && latestBeforePrune == attemptA + 7
                    && !blocked.success && blocked.error == "recovery_history_full"
                    && LootContainerService.canReopenSuspendedTarget(flow.target)
                    && firstLatestProof.success
                    && reopenedAfterPrune.success && reopenedAfterPrune.reopened
                    && laterDetached.success && laterDetached.state == "LOOT_SUSPENDED"
                    && delayedOlderProof.success
                    && reopenedNewest.success && reopenedNewest.reopened
                    && newestAttempt == laterAttempt + 1
                    && newestDetached.success && newestDetached.state == "LOOT_SUSPENDED"
                    && laterProofAfterDelayedOlder.success
                    && laterProofAfterDelayedOlder.state == "LOOT_SUSPENDED"
                    && presented.length == 0,
                "proof ledger 满时 fail closed 不 LRU；exact query 收敛旧项，迟到较旧 query 不删 later proof");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testSuspendReopenFailureEmptyConsumes():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            var presented:Array = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            var flow:Object = activate([stack(STACK, 1, 624)],
                "s1.suspend-reopen-empty");
            var before:Object = snapshot(flow);
            LootContainerService.execute("close", closeParams(before,
                "close.suspend-reopen-empty", before.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();
            var dispatched:Object = LootContainerService.resumeSuspended(flow.target);

            // 白盒模拟已投递 reopen 的未知窗口内 inventory 恰好被取空；failure
            // recovery 必须落 CONSUMED，而不是制造 remaining=0 的 SUSPENDED。
            flow.inventory.remove(0);
            callbacks[0]({success:false, accepted:false, error:"panel_busy"});
            var terminal:Object = LootContainerService.execute("query", queryParams(before));
            var fallback:Object = LootContainerService.consumeLegacyFallback(flow.target);
            var nextTarget:Object = makeTarget("s1.after-reopen-empty");
            var next:Object = LootContainerService.beginFixture(nextTarget);
            check(dispatched.success && dispatched.reopened
                    && terminal.success && terminal.state == "CONSUMED"
                    && terminal.remainingCount == 0 && terminal.terminal != null
                    && terminal.terminal.kind == "CONSUMED"
                    && terminal.terminal.reason == "reopen_failure_empty"
                    && !fallback.success && fallback.error == "no_legacy_fallback"
                    && presented.length == 0 && flow.target.playCount == 1
                    && next.handled && next.reserved,
                "reopen failure 发现同一 inventory 已空时直接 CONSUMED，不生成空 suspend/legacy");
            LootContainerService.abortReservedOpen(nextTarget, "test_cleanup");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testInitialOpenSynchronousFailureRendersLegacyOnce():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var presented:Array = [];
            installLegacyRenderer(presented);
            _root.server = {
                sendTaskWithCallback:function(task:String, payload:Object, extra:Object,
                                              callback:Function, timeoutFrames:Number):Void {
                    callback({success:false, error:"socket not connected"});
                }
            };
            var flow:Object = activate([stack(STACK, 1, 620)], "s1.initial-sync-failure");
            var requested:Boolean = LootContainerService.requestOpenPanel();
            // authored caller 会因 false 再进入 fallback helper；rendererConfirmed 必须
            // 让第二次调用只复取 projection，不再渲染第二个 AS2 窗口。
            var duplicate:Object = LootContainerService.consumeLegacyFallback(flow.target);
            var authority:Object = LootContainerService.execute(
                "query", queryParams(flow.active));
            check(!requested && duplicate.success && duplicate.rendererConfirmed
                    && authority.success && authority.state == "LOOT_ACTIVE"
                    && presented.length == 1 && presented[0].inventory === flow.inventory,
                "初次 open 同步 callback failure 保持既有 legacy fallback，authored 二次调用不重复渲染");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testSuspendAnchorFailureIsZeroAuthority():Void {
        resetWorld();
        var flow:Object = activate([stack(STACK, 1, 613)], "s1.suspend-anchor-fail");
        var before:Object = snapshot(flow);
        var area:Object = flow.target.area;
        flow.target.area = null;
        var rejected:Object = LootContainerService.execute("close",
            closeParams(before, "close.suspend-anchor-fail", before.closeLease, false));
        var after:Object = LootContainerService.execute("query", queryParams(before));
        check(!rejected.success && rejected.error == "suspend_unavailable"
                && rejected.state == "LOOT_ACTIVE"
                && rejected.authorityRevision == before.authorityRevision
                && rejected.lastAppliedOperationId == before.lastAppliedOperationId
                && after.success && after.state == "LOOT_ACTIVE"
                && after.closeLease == before.closeLease && after.remainingCount == 1,
            "anchor preflight 失败时 operation/revision/lease/inventory 全部零变化");
        flow.target.area = area;
        LootContainerService.execute("close",
            closeParams(after, "close.anchor-cleanup", after.closeLease, true));
    }

    private static function testSuspendedAnchorUnloadExpires():Void {
        resetWorld();
        var flow:Object = activate([stack(STACK, 1, 614)], "s1.suspend-unload");
        var before:Object = snapshot(flow);
        LootContainerService.execute("close",
            closeParams(before, "close.suspend-unload", before.closeLease, false));
        _root._webPanelPauseLease = "test-unload-terminal-visual-close-lease";
        LootContainerService.testOnlyFailNextTransportHandoff("unpause");
        var unloaded:Object = LootContainerService.handleTargetUnload(flow.target);
        var terminal:Object = LootContainerService.execute("query", queryParams(before));
        var freshTarget:Object = makeTarget("s1.after-suspend-unload");
        var fresh:Object = LootContainerService.beginFixture(freshTarget);
        check(unloaded.success && unloaded.handled && unloaded.state == "EXPIRED"
                && terminal.success && terminal.state == "EXPIRED"
                && terminal.terminal.reason == "suspended_anchor_unloaded"
                && !LootContainerService.canReopenSuspendedTarget(flow.target)
                && flow.target.playCount == 1 && fresh.reserved
                && _root._webPanelPauseLease == "test-unload-terminal-visual-close-lease",
            "exact suspended target onUnload 在 unpause 暂败时仍清 anchor/active；lease 留给迟到 Host unpause");
        _root._webPanelPauseLease = undefined;
        LootContainerService.abortReservedOpen(freshTarget, "test_cleanup");
    }

    private static function testLegacyClaimOnlyServiceAdapter():Void {
        // foreign inventory 不能借本地 adapter 写当前 authority；普通最后一格仍走
        // CommitCoordinator、dirty 与显式 CONSUMED，不依赖同步 remove observer。
        resetWorld();
        var ordinaryItem:BaseItem = equipment(690);
        var ordinaryFlow:Object = activate([ordinaryItem], "s1.legacy-claim-ordinary");
        var ordinaryProjection:Object = LootContainerService.consumeLegacyFallback(
            ordinaryFlow.target);
        var unconfirmed:Object = LootContainerService.claimLegacyRecoverySlot(
            ordinaryFlow.inventory, 0);
        LootContainerService.confirmLegacyRenderer(ordinaryFlow.target);
        var foreign:Object = LootContainerService.claimLegacyRecoverySlot(
            new ArrayInventory(null, 8), 0);
        _root.存档系统.dirtyMark = false;
        var ordinary:Object = LootContainerService.claimLegacyRecoverySlot(
            ordinaryFlow.inventory, 0);
        check(ordinaryProjection.success
                && !unconfirmed.success && unconfirmed.error == "legacy_renderer_unconfirmed"
                && !foreign.success && foreign.error == "recovery_inventory_mismatch"
                && ordinary.success && ordinary.released === true
                && ordinary.state == "CONSUMED"
                && _root.物品栏.背包.getItem("0") === ordinaryItem
                && ordinaryFlow.inventory.getItem("0") == null
                && _root.存档系统.dirtyMark === true,
            "claim-only adapter 拒绝未呈现/foreign inventory；普通最后一格经事务落 dirty+CONSUMED");

        // 满背包装备必须严格零写。
        resetWorld();
        for (var i:Number = 0; i < 50; i++) {
            _root.物品栏.背包.add(i, stack(STACK, i + 1, 700 + i));
        }
        var fullItem:BaseItem = equipment(760);
        var fullFlow:Object = activate([fullItem], "s1.legacy-claim-full");
        LootContainerService.consumeLegacyFallback(fullFlow.target);
        LootContainerService.confirmLegacyRenderer(fullFlow.target);
        var fullRevision:Number = fullFlow.inventory.getMutationRevision();
        _root.存档系统.dirtyMark = false;
        var full:Object = LootContainerService.claimLegacyRecoverySlot(
            fullFlow.inventory, 0);
        check(!full.success && full.error == "target_full"
                && fullFlow.inventory.getItem("0") === fullItem
                && fullFlow.inventory.getMutationRevision() == fullRevision
                && _root.物品栏.背包.size() == 50
                && _root.存档系统.dirtyMark === false,
            "claim-only 满背包装备返回 target_full，source/revision/背包/dirty 零变化");
        LootContainerService.expireScene("scene_cleanup");

        // 背包虽满但已有数值栈时仍由 coordinator 原位合并。
        resetWorld();
        var destination:BaseItem = stack(ANTIBIOTIC, 358, 761);
        _root.物品栏.背包.add(14, destination);
        for (i = 0; i < 50; i++) {
            if (i != 14) _root.物品栏.背包.add(i, stack(STACK, i + 1, 762 + i));
        }
        var antibiotic:BaseItem = stack(ANTIBIOTIC, 3, 812);
        var stackFlow:Object = activate([antibiotic], "s1.legacy-claim-stack");
        LootContainerService.consumeLegacyFallback(stackFlow.target);
        LootContainerService.confirmLegacyRenderer(stackFlow.target);
        _root.存档系统.dirtyMark = false;
        var merged:Object = LootContainerService.claimLegacyRecoverySlot(
            stackFlow.inventory, 0);
        check(merged.success && merged.released === true && merged.state == "CONSUMED"
                && destination.value == 361 && _root.物品栏.背包.size() == 50
                && stackFlow.inventory.getItem("0") == null
                && _root.存档系统.dirtyMark === true,
            "claim-only 满背包已有抗生素栈仍原位合并并终止空箱");

        // 特殊资产也只走事务域：材料成功必 dirty；情报超 cap 必整格保留且零 dirty。
        resetWorld();
        var material:BaseItem = stack(MATERIAL, 3, 813);
        var materialFlow:Object = activate([material], "s1.legacy-claim-material");
        LootContainerService.consumeLegacyFallback(materialFlow.target);
        LootContainerService.confirmLegacyRenderer(materialFlow.target);
        _root.存档系统.dirtyMark = false;
        var materialClaim:Object = LootContainerService.claimLegacyRecoverySlot(
            materialFlow.inventory, 0);
        check(materialClaim.success && materialClaim.released === true
                && _root.收集品栏.材料.getValue(MATERIAL) == 3
                && materialFlow.inventory.getItem("0") == null
                && _root.存档系统.dirtyMark === true,
            "claim-only 材料经 collection transaction 提交并标 dirty");

        resetWorld();
        _root.收集品栏.情报.add(INFORMATION, 4);
        var information:BaseItem = stack(INFORMATION, 2, 814);
        var infoFlow:Object = activate([information], "s1.legacy-claim-info-cap");
        LootContainerService.consumeLegacyFallback(infoFlow.target);
        LootContainerService.confirmLegacyRenderer(infoFlow.target);
        var infoRevision:Number = infoFlow.inventory.getMutationRevision();
        _root.存档系统.dirtyMark = false;
        var capped:Object = LootContainerService.claimLegacyRecoverySlot(
            infoFlow.inventory, 0);
        check(!capped.success && capped.error == "cap_reached"
                && _root.收集品栏.情报.getValue(INFORMATION) == 4
                && infoFlow.inventory.getItem("0") === information
                && infoFlow.inventory.getMutationRevision() == infoRevision
                && _root.存档系统.dirtyMark === false,
            "claim-only 情报超 cap 整格保留，source/revision/dirty 零变化");
        LootContainerService.expireScene("scene_cleanup");

        // 已写 journal 后的连续 mandatory-effect 故障由 adapter/completion/guard 的 causal
        // retry 分阶段收敛；事件和实际写入都只能发生一次。
        var sourceOwner:MovieClip = _root.createEmptyMovieClip(
            "__loot_legacy_claim_source", _root.getNextHighestDepth());
        var destinationOwner:MovieClip = _root.createEmptyMovieClip(
            "__loot_legacy_claim_destination", _root.getNextHighestDepth());
        try {
            resetWorld();
            var pendingItem:BaseItem = equipment(815);
            var pendingFlow:Object = activate([pendingItem], "s1.legacy-claim-reconcile");
            var sourceEvents:Number = 0;
            var destinationEvents:Number = 0;
            var sourceDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(sourceOwner);
            var destinationDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(
                destinationOwner);
            pendingFlow.inventory.setDispatcher(sourceDispatcher);
            _root.物品栏.背包.setDispatcher(destinationDispatcher);
            sourceDispatcher.subscribe("ItemRemoved", function():Void { sourceEvents++; });
            destinationDispatcher.subscribe("ItemAdded", function():Void { destinationEvents++; });
            LootContainerService.consumeLegacyFallback(pendingFlow.target);
            LootContainerService.confirmLegacyRenderer(pendingFlow.target);
            var sourceRevisionBefore:Number = pendingFlow.inventory.getMutationRevision();
            var destinationRevisionBefore:Number = _root.物品栏.背包.getMutationRevision();
            // claim、adapter causal query、adapter completion 与首次 fixture guard 连续失败；
            // 第二次 guard 必须只重试 effects 后终止，绝不能重放 source/destination 写。
            LootContainerService.testOnlyFailNextPostCommit("dirty", 4);
            _root.存档系统.dirtyMark = false;
            var pendingAdapter:Object = LootContainerService.claimLegacyRecoverySlot(
                pendingFlow.inventory, 0);
            var pendingExposure:Object = LootContainerService.consumeLegacyFallback(null);
            var writeAppliedOnce:Boolean = pendingFlow.inventory.getItem("0") == null
                && _root.物品栏.背包.getItem("0") === pendingItem
                && pendingFlow.inventory.getMutationRevision() == sourceRevisionBefore + 1
                && _root.物品栏.背包.getMutationRevision() == destinationRevisionBefore + 1
                && sourceEvents == 0 && destinationEvents == 0
                && _root.存档系统.dirtyMark === false;
            var blockedGuard:Object = LootContainerService.guardAnyGridFixture(
                makeTarget("s1.legacy-claim-pending-blocked"));
            var stillSingleWrite:Boolean = pendingFlow.inventory.getMutationRevision()
                    == sourceRevisionBefore + 1
                && _root.物品栏.背包.getMutationRevision() == destinationRevisionBefore + 1
                && sourceEvents == 0 && destinationEvents == 0
                && _root.存档系统.dirtyMark === false;
            var releasedGuard:Object = LootContainerService.guardAnyGridFixture(
                makeTarget("s1.legacy-claim-after-effects"));
            var terminal:Object = LootContainerService.execute(
                "query", queryParams(pendingFlow.active));
            var postEffectsPassed:Boolean = !pendingAdapter.success
                    && pendingAdapter.error == "commit_pending"
                    && !pendingExposure.success
                    && pendingExposure.error == "claim_commit_pending"
                    && writeAppliedOnce
                    && blockedGuard.handled && blockedGuard.recovery === false
                    && blockedGuard.reason == "claim_commit_pending"
                    && stillSingleWrite
                    && !releasedGuard.handled && releasedGuard.reason == "recovery_consumed"
                    && terminal.success && terminal.state == "CONSUMED"
                    && pendingFlow.inventory.getItem("0") == null
                    && _root.物品栏.背包.getItem("0") === pendingItem
                    && _root.物品栏.背包.size() == 1
                    && pendingFlow.inventory.getMutationRevision() == sourceRevisionBefore + 1
                    && _root.物品栏.背包.getMutationRevision() == destinationRevisionBefore + 1
                    && sourceEvents == 1 && destinationEvents == 1
                    && _root.存档系统.dirtyMark === true;

            // source 已空但 pendingCommit 的连续 causal query 仍可能失败。adapter 内置 query、
            // completion 与首次 guard 都必须保持 fence；下一次 guard 只能续跑同一 journal。
            resetWorld();
            var journalItem:BaseItem = equipment(816);
            var journalFlow:Object = activate([journalItem], "s1.legacy-claim-pending-journal");
            sourceEvents = 0;
            destinationEvents = 0;
            var journalSourceDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(
                sourceOwner);
            var journalDestinationDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(
                destinationOwner);
            journalFlow.inventory.setDispatcher(journalSourceDispatcher);
            _root.物品栏.背包.setDispatcher(journalDestinationDispatcher);
            journalSourceDispatcher.subscribe("ItemRemoved", function():Void { sourceEvents++; });
            journalDestinationDispatcher.subscribe("ItemAdded", function():Void { destinationEvents++; });
            LootContainerService.consumeLegacyFallback(journalFlow.target);
            LootContainerService.confirmLegacyRenderer(journalFlow.target);
            var journalSourceRevision:Number = journalFlow.inventory.getMutationRevision();
            var journalDestinationRevision:Number = _root.物品栏.背包.getMutationRevision();
            LootClaimCommitCoordinator.testOnlyFailNext(
                "ordinary_source_write", "after_false");
            LootClaimCommitCoordinator.testOnlyFailNext("ordinary_rollback", "false");
            LootClaimCommitCoordinator.testOnlyFailNext("resume", "false", 3);
            _root.存档系统.dirtyMark = false;
            var journalPending:Object = LootContainerService.claimLegacyRecoverySlot(
                journalFlow.inventory, 0);
            var journalExposure:Object = LootContainerService.consumeLegacyFallback(null);
            var journalAppliedOnce:Boolean = journalFlow.inventory.getItem("0") == null
                && _root.物品栏.背包.getItem("0") === journalItem
                && journalFlow.inventory.getMutationRevision() == journalSourceRevision + 1
                && _root.物品栏.背包.getMutationRevision() == journalDestinationRevision + 1
                && sourceEvents == 0 && destinationEvents == 0
                && _root.存档系统.dirtyMark === false;
            var journalBlocked:Object = LootContainerService.guardAnyGridFixture(
                makeTarget("s1.legacy-journal-pending-blocked"));
            var journalStillSingleWrite:Boolean = journalFlow.inventory.getMutationRevision()
                    == journalSourceRevision + 1
                && _root.物品栏.背包.getMutationRevision() == journalDestinationRevision + 1
                && sourceEvents == 0 && destinationEvents == 0
                && _root.存档系统.dirtyMark === false;
            var journalReleased:Object = LootContainerService.guardAnyGridFixture(
                makeTarget("s1.legacy-journal-after-reconcile"));
            var journalTerminal:Object = LootContainerService.execute(
                "query", queryParams(journalFlow.active));
            var pendingJournalPassed:Boolean = !journalPending.success
                && journalPending.error == "commit_pending"
                && !journalExposure.success
                && journalExposure.error == "claim_commit_pending"
                && journalAppliedOnce
                && journalBlocked.handled && journalBlocked.recovery === false
                && journalBlocked.reason == "claim_commit_pending"
                && journalStillSingleWrite
                && !journalReleased.handled && journalReleased.reason == "recovery_consumed"
                && journalTerminal.success && journalTerminal.state == "CONSUMED"
                && journalFlow.inventory.getItem("0") == null
                && _root.物品栏.背包.getItem("0") === journalItem
                && journalFlow.inventory.getMutationRevision() == journalSourceRevision + 1
                && _root.物品栏.背包.getMutationRevision() == journalDestinationRevision + 1
                && sourceEvents == 1 && destinationEvents == 1
                && _root.存档系统.dirtyMark === true;

            // 可证明 rollback 必须恢复 source 并保持 recovery；foreign fixture 只可重呈现
            // 原箱，不能被误判空箱 CONSUMED，也不能获得新的网格 authority。
            resetWorld();
            var rollbackItem:BaseItem = equipment(817);
            var rollbackFlow:Object = activate([rollbackItem], "s1.legacy-claim-rolled-back");
            LootContainerService.consumeLegacyFallback(rollbackFlow.target);
            LootContainerService.confirmLegacyRenderer(rollbackFlow.target);
            LootClaimCommitCoordinator.testOnlyFailNext("ordinary_source_write", "false");
            _root.存档系统.dirtyMark = false;
            var rolledBack:Object = LootContainerService.claimLegacyRecoverySlot(
                rollbackFlow.inventory, 0);
            var rollbackCompletion:Object = LootContainerService.completeLegacyRecoveryIfEmpty();
            var rollbackGuard:Object = LootContainerService.guardAnyGridFixture(
                makeTarget("s1.legacy-rollback-foreign"));
            var rollbackAuthority:Object = LootContainerService.execute(
                "query", queryParams(rollbackFlow.active));
            var rollbackPassed:Boolean = !rolledBack.success && rolledBack.error == "commit_failed"
                && rollbackCompletion.success && rollbackCompletion.released === false
                && rollbackCompletion.reason == "recovery_nonempty"
                && rollbackFlow.inventory.getItem("0") === rollbackItem
                && _root.物品栏.背包.size() == 0
                && rollbackGuard.handled && rollbackGuard.recovery === true
                && rollbackGuard.requestedTargetMatches === false
                && rollbackAuthority.success && rollbackAuthority.state == "LOOT_ACTIVE"
                && rollbackAuthority.remainingCount == 1
                && _root.存档系统.dirtyMark === false;
            LootContainerService.expireScene("scene_cleanup");

            check(postEffectsPassed && pendingJournalPassed && rollbackPassed,
                "claim-only 空箱持续 journal/effects 故障保持 guard；重试零写重放，rollback 不误终止");
        } finally {
            sourceOwner.removeMovieClip();
            destinationOwner.removeMovieClip();
        }
    }

    private static function testLegacyRecoveryKeepsSameInventory():Void {
        resetWorld();
        var sourceItem:BaseItem = stack(STACK, 2, 701);
        var flow:Object = activate([sourceItem], "s1.recovery");
        var first:Object = LootContainerService.consumeLegacyFallback(flow.target);
        var second:Object = LootContainerService.consumeLegacyFallback(flow.target);
        var guard:Object = LootContainerService.guardAnyGridFixture(makeTarget("s1.blocked"));
        var direct:Object = LootContainerService.beginFixture({presetName:"直接爆落", row:0, col:0});
        var nonempty:Object = LootContainerService.completeLegacyRecoveryIfEmpty();
        var recoveryQuery:Object = LootContainerService.execute("query", queryParams(flow.active));
        var refusedClose:Object = LootContainerService.execute("close",
            closeParams(recoveryQuery, "close.recovery-nonempty", recoveryQuery.closeLease, false));
        check(first.success && first.inventory === flow.inventory
                && second.success && second.duplicate && second.inventory === first.inventory
                && guard.handled && guard.recovery && guard.inventory === first.inventory
                && !direct.handled
                && !nonempty.released
                && recoveryQuery.success && recoveryQuery.state == "LOOT_ACTIVE"
                && !refusedClose.success && refusedClose.error == "suspend_unavailable"
                && refusedClose.state == "LOOT_ACTIVE",
            "legacy recovery 保持同一 ACTIVE inventory，禁止伪装 suspend 且只阻止新网格箱");
        flow.inventory.transactionWrite(0, null);
        var released:Object = LootContainerService.completeLegacyRecoveryIfEmpty();
        var consumedQuery:Object = LootContainerService.execute("query", queryParams(flow.active));
        check(released.released && released.state == "CONSUMED"
                && consumedQuery.success && consumedQuery.state == "CONSUMED"
                && consumedQuery.terminal.remainingCount == 0
                && !LootContainerService.guardAnyGridFixture(flow.target).handled,
            "legacy inventory 取空后才提交 CONSUMED tombstone/remaining=0 并释放");

        resetWorld();
        var failedTarget:Object = makeTarget("s1.killfail");
        var failedInventory:ArrayInventory = makeInventory([stack(STACK, 1, 702)]);
        var begun:Object = LootContainerService.beginFixture(failedTarget);
        var failed:Object = LootContainerService.commitReservedOpen(
            failedTarget, failedInventory, null, function():Boolean { return false; });
        var fallback:Object = LootContainerService.consumeLegacyFallback(failedTarget);
        var recoveryState:Object = LootContainerService.execute("query", {
            v:1, chestSessionId:begun.chestSessionId,
            lootContainerId:begun.lootContainerId, containerEpoch:begun.containerEpoch
        });
        LootContainerService.expireScene("scene_cleanup");
        var expiredRecovery:Object = LootContainerService.execute("query", {
            v:1, chestSessionId:begun.chestSessionId,
            lootContainerId:begun.lootContainerId, containerEpoch:begun.containerEpoch
        });
        check(!failed.success && failed.error == "kill_adapter_failed"
                && fallback.inventory === failedInventory
                && recoveryState.success && recoveryState.state == "LOOT_ACTIVE"
                && expiredRecovery.success && expiredRecovery.state == "EXPIRED"
                && expiredRecovery.terminal.reason == "scene_cleanup",
            "kill adapter 失败保持 same-object ACTIVE recovery，只有 scene cleanup 才 EXPIRED");
    }

    private static function testLegacyRecoveryObserverLifecycle():Void {
        var owner:MovieClip = _root.createEmptyMovieClip(
            "__loot_recovery_observer_test", _root.getNextHighestDepth());
        try {
            resetWorld();
            var flow:Object = activate([stack(STACK, 1, 703)], "s1.recovery-observer");
            LootContainerService.consumeLegacyFallback(flow.target);
            var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(owner);
            flow.inventory.setDispatcher(dispatcher);
            var attached:Object = LootContainerService.attachLegacyRecoveryObserver();
            flow.inventory.remove(0);
            var consumed:Object = LootContainerService.execute("query", queryParams(flow.active));
            check(attached.success && consumed.success && consumed.state == "CONSUMED"
                    && consumed.terminal.remainingCount == 0,
                "legacy UI 最后一格移除事件自动提交 CONSUMED，不等待 scene cleanup");

            resetWorld();
            var oldFlow:Object = activate([stack(STACK, 1, 704)], "s1.recovery-observer-old");
            LootContainerService.consumeLegacyFallback(oldFlow.target);
            var secondDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(owner);
            oldFlow.inventory.setDispatcher(secondDispatcher);
            LootContainerService.attachLegacyRecoveryObserver();
            LootContainerService.expireScene("scene_cleanup");
            resetWorld();
            var freshFlow:Object = activate([stack(STACK, 1, 705)], "s1.recovery-observer-fresh");
            oldFlow.inventory.remove(0);
            var fresh:Object = LootContainerService.execute("query", queryParams(freshFlow.active));
            check(fresh.success && fresh.state == "LOOT_ACTIVE",
                "terminal/reset 会解绑旧 recovery observer，旧 inventory 事件不污染 fresh authority");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            owner.removeMovieClip();
        }
    }

    private static function testReliablePanelOpenCallbacks():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            var sent:Array = [];
            var callbacks:Array = [];
            var presented:Array = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            resetWorld();
            var rejectedFlow:Object = activate([stack(STACK, 1, 711)], "s1.panel-rejected");
            var requested:Boolean = LootContainerService.requestOpenPanel();
            var body:Object = sent[0].payload;
            var bodyKeyCount:Number = ownKeyCount(body);
            var initKeyCount:Number = ownKeyCount(body.initData);
            check(requested && sent.length == 1 && callbacks.length == 1
                    && sent[0].task == "panel_request" && sent[0].extra == null
                    && sent[0].timeoutFrames == 600 && bodyKeyCount == 3
                    && body.panel == "loot" && body.source == "map_chest"
                    && initKeyCount == 8
                    && body.initData.chestSessionId == rejectedFlow.active.chestSessionId
                    && body.initData.lootContainerId == rejectedFlow.active.lootContainerId
                    && Number(body.initData.openAttemptSeq) > 0,
                "panel open 使用 callback envelope，authored payload/initData 保持 exact 3/8 键并携 attempt token");
            callbacks[0]({success:false, accepted:false, error:"panel_busy"});
            var rejectedQuery:Object = LootContainerService.execute(
                "query", queryParams(rejectedFlow.active));
            var rejectedGuard:Object = LootContainerService.guardAnyGridFixture(
                makeTarget("s1.after-panel-rejected"));
            check(rejectedQuery.success && rejectedQuery.state == "LOOT_ACTIVE"
                    && rejectedGuard.handled && rejectedGuard.reason == "panel_open_rejected"
                    && presented.length == 1 && presented[0].inventory === rejectedFlow.inventory,
                "无 callId 的 Host rejection callback 进入 same-object ACTIVE recovery 并显示旧 UI");

            sent = []; callbacks = []; presented = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            resetWorld();
            var timeoutFlow:Object = activate([stack(STACK, 1, 712)], "s1.panel-timeout");
            LootContainerService.requestOpenPanel();
            callbacks[0]({success:false, error:"callback timeout"});
            var timeoutQuery:Object = LootContainerService.execute("query", queryParams(timeoutFlow.active));
            var timeoutGuard:Object = LootContainerService.guardAnyGridFixture(makeTarget("s1.after-timeout"));
            check(timeoutQuery.success && timeoutQuery.state == "LOOT_ACTIVE"
                    && timeoutGuard.handled && timeoutGuard.reason == "panel_open_timeout"
                    && presented[0].inventory === timeoutFlow.inventory,
                "panel callback timeout 保留 same-object ACTIVE authority 并提供 legacy recovery");

            sent = []; callbacks = []; presented = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            resetWorld();
            var disconnectFlow:Object = activate([stack(STACK, 1, 713)], "s1.panel-disconnect");
            LootContainerService.requestOpenPanel();
            callbacks[0]({success:false, error:"socket closed"});
            var disconnectQuery:Object = LootContainerService.execute(
                "query", queryParams(disconnectFlow.active));
            var disconnectGuard:Object = LootContainerService.guardAnyGridFixture(
                makeTarget("s1.after-disconnect"));
            check(disconnectQuery.success && disconnectQuery.state == "LOOT_ACTIVE"
                    && disconnectGuard.handled && disconnectGuard.reason == "panel_open_unavailable"
                    && presented[0].inventory === disconnectFlow.inventory,
                "panel callback 断线保留 same-object ACTIVE authority 并提供 legacy recovery");

            sent = []; callbacks = []; presented = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            resetWorld();
            var oldFlow:Object = activate([stack(STACK, 1, 714)], "s1.panel-old-callback");
            LootContainerService.requestOpenPanel();
            var oldCallback:Function = callbacks[0];
            LootContainerService.expireScene("scene_cleanup");
            sent = []; callbacks = []; presented = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            resetWorld();
            var freshFlow:Object = activate([stack(STACK, 1, 715)], "s1.panel-fresh-authority");
            oldCallback({success:false, accepted:false, error:"open_not_queued"});
            var freshQuery:Object = LootContainerService.execute("query", queryParams(freshFlow.active));
            var freshGuard:Object = LootContainerService.guardAnyGridFixture(
                makeTarget("s1.after-stale-callback"));
            check(freshQuery.success && freshQuery.state == "LOOT_ACTIVE"
                    && !freshGuard.handled && presented.length == 0,
                "迟到旧 open callback 复核 session/container/epoch，不污染 fresh authority");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testRecoveryProofStrictShapeAndNonce():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            var presented:Array = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            var flow:Object = activate([stack(STACK, 1, 718)],
                "s1.recovery-shape");
            LootContainerService.requestOpenPanel();
            var attemptSeq:Number = Number(sent[0].payload.initData.openAttemptSeq);
            var ordinaryWire:Object = {
                task:"cmd", action:"lootQuery", callId:901, v:1,
                chestSessionId:flow.active.chestSessionId,
                lootContainerId:flow.active.lootContainerId,
                containerEpoch:flow.active.containerEpoch
            };
            var proofWire:Object = {
                task:"cmd", action:"lootQuery", callId:902, v:1,
                chestSessionId:flow.active.chestSessionId,
                lootContainerId:flow.active.lootContainerId,
                containerEpoch:flow.active.containerEpoch,
                openAttemptSeq:attemptSeq,
                recoveryNonce:"proof.with.dot~tilde"
            };
            var halfAttempt:Object = {};
            var halfNonce:Object = {};
            var key:String;
            for (key in ordinaryWire) {
                halfAttempt[key] = ordinaryWire[key];
                halfNonce[key] = ordinaryWire[key];
            }
            halfAttempt.openAttemptSeq = attemptSeq;
            halfNonce.recoveryNonce = "proof.only.nonce";
            var colonProof:Object = {};
            var spaceProof:Object = {};
            for (key in proofWire) {
                colonProof[key] = proofWire[key];
                spaceProof[key] = proofWire[key];
            }
            colonProof.recoveryNonce = "bad:nonce";
            spaceProof.recoveryNonce = "bad nonce";
            var nonce128:String = "";
            for (var i:Number = 0; i < 128; i++) nonce128 += "x";
            var maxProof:Object = {};
            var tooLongProof:Object = {};
            for (key in proofWire) {
                maxProof[key] = proofWire[key];
                tooLongProof[key] = proofWire[key];
            }
            maxProof.recoveryNonce = nonce128;
            tooLongProof.recoveryNonce = nonce128 + "x";

            var ordinaryResult:Object = LootContainerService.execute("query", ordinaryWire);
            var unappliedProof:Object = LootContainerService.execute("query", proofWire);
            var halfAttemptResult:Object = LootContainerService.execute("query", halfAttempt);
            var halfNonceResult:Object = LootContainerService.execute("query", halfNonce);
            var colonResult:Object = LootContainerService.execute("query", colonProof);
            var spaceResult:Object = LootContainerService.execute("query", spaceProof);
            var maxResult:Object = LootContainerService.execute("query", maxProof);
            var tooLongResult:Object = LootContainerService.execute("query", tooLongProof);

            var validRecovery:Object = recoveryEnvelope(flow.active, attemptSeq,
                "recovery.with.dot~tilde", "web_mount_failed");
            var missingNonce:Object = {};
            var extraRecovery:Object = {};
            var badRecovery:Object = {};
            for (key in validRecovery) {
                missingNonce[key] = validRecovery[key];
                extraRecovery[key] = validRecovery[key];
                badRecovery[key] = validRecovery[key];
            }
            delete missingNonce.recoveryNonce;
            extraRecovery.extra = true;
            badRecovery.recoveryNonce = "bad:nonce";
            var missingNonceResult:Object = LootContainerService.handlePanelRecovery(missingNonce);
            var extraRecoveryResult:Object = LootContainerService.handlePanelRecovery(extraRecovery);
            var badRecoveryResult:Object = LootContainerService.handlePanelRecovery(badRecovery);
            var validRecoveryResult:Object = LootContainerService.handlePanelRecovery(validRecovery);

            check(ownKeyCount(ordinaryWire) == 7 && ownKeyCount(proofWire) == 9
                    && ownKeyCount(validRecovery) == 8
                    && ordinaryResult.success && ordinaryResult.state == "LOOT_ACTIVE"
                    && !unappliedProof.success
                    && unappliedProof.error == "recovery_not_applied"
                    && !halfAttemptResult.success && halfAttemptResult.error == "invalid_payload"
                    && !halfNonceResult.success && halfNonceResult.error == "invalid_payload"
                    && !colonResult.success && colonResult.error == "invalid_payload"
                    && !spaceResult.success && spaceResult.error == "invalid_payload"
                    && !maxResult.success && maxResult.error == "recovery_not_applied"
                    && !tooLongResult.success && tooLongResult.error == "invalid_payload"
                    && !missingNonceResult.handled
                    && missingNonceResult.reason == "invalid_payload"
                    && !extraRecoveryResult.handled
                    && extraRecoveryResult.reason == "invalid_payload"
                    && !badRecoveryResult.handled
                    && badRecoveryResult.reason == "invalid_payload"
                    && validRecoveryResult.handled && !validRecoveryResult.recovered
                    && validRecoveryResult.reason == "recovery_pending"
                    && presented.length == 0,
                "wire query 严格 7/9 键、recovery 严格 8 键；opaque 与 Host 统一 ._~- 及 128 边界");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testInitialRecoveryBeforeAckProof():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            var presented:Array = [];
            installPanelTransport(sent, callbacks);
            installLegacyRenderer(presented);
            var flow:Object = activate([stack(STACK, 1, 719)],
                "s1.initial-recovery-pre-ack");
            LootContainerService.requestOpenPanel();
            var attemptSeq:Number = Number(sent[0].payload.initData.openAttemptSeq);
            var envelope:Object = recoveryEnvelope(flow.active, attemptSeq,
                "recovery.initial.pre.ack", "web_open_failed");
            var registered:Object = LootContainerService.handlePanelRecovery(envelope);
            var proofBeforeAck:Object = LootContainerService.execute("query",
                proofQueryParams(flow.active, attemptSeq, "recovery.initial.pre.ack"));
            var ordinaryBeforeAck:Object = LootContainerService.execute(
                "query", queryParams(flow.active));
            callbacks[0]({success:true, accepted:true});
            var proofAfterAck:Object = LootContainerService.execute("query",
                proofQueryParams(flow.active, attemptSeq, "recovery.initial.pre.ack"));
            var duplicateSignal:Object = LootContainerService.handlePanelRecovery(envelope);
            var duplicateProof:Object = LootContainerService.execute("query",
                proofQueryParams(flow.active, attemptSeq, "recovery.initial.pre.ack"));
            var wrongNonce:Object = LootContainerService.execute("query",
                proofQueryParams(flow.active, attemptSeq, "recovery.initial.wrong"));

            check(registered.handled && !registered.recovered
                    && registered.reason == "recovery_pending"
                    && !proofBeforeAck.success && proofBeforeAck.error == "recovery_pending"
                    && ordinaryBeforeAck.success && ordinaryBeforeAck.state == "LOOT_ACTIVE"
                    && presented.length == 1
                    && proofAfterAck.success && proofAfterAck.state == "LOOT_ACTIVE"
                    && duplicateSignal.handled && duplicateSignal.recovered
                    && duplicateSignal.duplicate
                    && duplicateProof.success
                    && !wrongNonce.success && wrongNonce.error == "recovery_nonce_mismatch"
                    && presented[0].inventory === flow.inventory,
                "initial recovery 早于 ACK 只登记；ACK 后才完成 legacy proof，重复幂等且错 nonce 零副作用");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function testConnectedPanelRecoverySignal():Void {
        var previousServer:Object = _root.server;
        var previousMapElements:Object = _root.地图元件;
        try {
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
            var presented:Array = [];
            installLegacyRenderer(presented);
            resetWorld();
            var flow:Object = activate([stack(STACK, 1, 716)], "s1.connected-recovery");
            LootContainerService.requestOpenPanel();
            callbacks[0]({success:true, accepted:true});
            var openAttemptSeq:Number = Number(sent[0].payload.initData.openAttemptSeq);
            var envelope:Object = {
                task:"cmd", action:"lootPanelRecovery",
                chestSessionId:flow.active.chestSessionId,
                lootContainerId:flow.active.lootContainerId,
                containerEpoch:flow.active.containerEpoch,
                openAttemptSeq:openAttemptSeq,
                recoveryNonce:"recovery.connected.initial",
                reason:"web_mount_failed"
            };
            var malformed:Object = {};
            for (var key:String in envelope) malformed[key] = envelope[key];
            malformed.extra = true;
            var malformedResult:Object = LootContainerService.handlePanelRecovery(malformed);
            var stale:Object = {};
            for (key in envelope) stale[key] = envelope[key];
            stale.openAttemptSeq = Number(stale.openAttemptSeq) + 1;
            var staleResult:Object = LootContainerService.handlePanelRecovery(stale);
            var recovered:Object = LootContainerService.handlePanelRecovery(envelope);
            var duplicate:Object = LootContainerService.handlePanelRecovery(envelope);
            var recoveryQuery:Object = LootContainerService.execute("query",
                proofQueryParams(flow.active, openAttemptSeq,
                    "recovery.connected.initial"));
            var recoveryGuard:Object = LootContainerService.guardAnyGridFixture(
                makeTarget("s1.after-connected-recovery"));

            LootContainerService.expireScene("scene_cleanup");
            resetWorld();
            var freshFlow:Object = activate([stack(STACK, 1, 717)], "s1.connected-recovery-fresh");
            var late:Object = LootContainerService.handlePanelRecovery(envelope);
            var freshQuery:Object = LootContainerService.execute("query", queryParams(freshFlow.active));
            check(!malformedResult.handled && malformedResult.reason == "invalid_payload"
                    && !staleResult.handled && staleResult.reason == "stale_open_attempt"
                    && recovered.handled && recovered.recovered && recovered.rendered
                    && duplicate.handled && duplicate.recovered && duplicate.duplicate
                    && presented.length == 1
                    && presented[0].inventory === flow.inventory
                    && recoveryQuery.success && recoveryQuery.state == "LOOT_ACTIVE"
                    && recoveryGuard.handled && recoveryGuard.reason == "web_mount_failed"
                    && !late.handled && late.reason == "stale_identity"
                    && freshQuery.success && freshQuery.state == "LOOT_ACTIVE",
                "accepted 后 exact8 recovery 匹配 identity+attempt+nonce；畸形/迟到拒绝、重复幂等");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
            _root.地图元件 = previousMapElements;
        }
    }

    private static function installPanelTransport(sent:Array, callbacks:Array):Void {
        _root.server = {
            sendTaskWithCallback:function(task:String, payload:Object, extra:Object,
                                          callback:Function, timeoutFrames:Number):Void {
                sent.push({task:task, payload:payload, extra:extra,
                    timeoutFrames:timeoutFrames});
                callbacks.push(callback);
            }
        };
    }

    private static function installLegacyRenderer(presented:Array):Void {
        _root.地图元件 = {
            显示Web战利品旧界面:function(projection:Object):Boolean {
                presented.push(projection);
                return true;
            }
        };
    }

    private static function ownKeyCount(value:Object):Number {
        var count:Number = 0;
        for (var key:String in value) {
            if (typeof value.hasOwnProperty != "function" || value.hasOwnProperty(key)) count++;
        }
        return count;
    }

    private static function testWireHandlersAndExactPayload():Void {
        resetWorld();
        LootContainerService.install();
        var flow:Object = activate([stack(STACK, 1, 801)], "s1.wire");
        var captured:String = "";
        var previousServer:Object = _root.server;
        _root.server = {sendSocketMessage:function(message:String):Boolean { captured = message; return true; }};
        _root.gameCommands["lootQuery"]({
            task:"cmd", action:"lootQuery", callId:77, v:1,
            chestSessionId:flow.active.chestSessionId,
            lootContainerId:flow.active.lootContainerId,
            containerEpoch:flow.active.containerEpoch
        });
        check(captured.indexOf('"task":"loot_response"') >= 0
                && captured.indexOf('"callId":77') >= 0
                && captured.indexOf('"closeLease":"close.') >= 0
                && typeof _root.gameCommands["lootPanelRecovery"] == "function",
            "gameCommands 返回 exact loot_response/callId 与 active closeLease");
        var invalid:Object = LootContainerService.execute("query", {
            v:1, chestSessionId:flow.active.chestSessionId,
            lootContainerId:flow.active.lootContainerId,
            containerEpoch:flow.active.containerEpoch,
            unexpected:true
        });
        check(!invalid.success && invalid.error == "invalid_payload",
            "未知顶层字段被 strict command shape 拒绝");
        var partialEnvelope:Object = LootContainerService.execute("query", {
            task:"cmd", v:1,
            chestSessionId:flow.active.chestSessionId,
            lootContainerId:flow.active.lootContainerId,
            containerEpoch:flow.active.containerEpoch
        });
        check(!partialEnvelope.success && partialEnvelope.error == "invalid_payload",
            "ServerManager envelope 必须 task/action/callId 三字段原子出现");
        _root.server = previousServer;
        LootContainerService.expireScene("scene_cleanup");
    }

    private static function check(condition:Boolean, message:String):Void {
        if (condition) {
            _passed++;
            trace("PASS: " + message);
        } else {
            _failed++;
            trace("FAIL: " + message);
        }
    }
}
