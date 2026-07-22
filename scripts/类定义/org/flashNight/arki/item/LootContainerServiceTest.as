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

/** S1：瞬态 Web loot container 的 identity/lease/事务/挂起/终态回归。 */
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
        testMaterializedInventoryValidationFence();
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
        testTransportDetachUnpauseLastItemRetry();
        testTransportDetachConflictStaysPending();
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
        testInitialOpenSynchronousFailureSuspendsSameInventory();
        testSuspendAnchorFailureIsZeroAuthority();
        testSuspendedAnchorUnloadExpires();
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
            testFixtureId:id,
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
            target, inventory,
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
        var arbitrary:Object = {presetName:"装备箱", row:3, col:5};
        var arbitraryResult:Object = LootContainerService.beginFixture(arbitrary);
        LootContainerService.abortReservedOpen(arbitrary, "test_arbitrary_grid");
        var smallest:Object = {presetName:"资源箱", row:1, col:1};
        var smallestResult:Object = LootContainerService.beginFixture(smallest);
        LootContainerService.abortReservedOpen(smallest, "test_smallest_grid");
        var boundary:Object = {presetName:"保险柜", row:8, col:8};
        var boundaryResult:Object = LootContainerService.beginFixture(boundary);
        LootContainerService.abortReservedOpen(boundary, "test_boundary_grid");
        var tooWide:Object = LootContainerService.beginFixture(
            {presetName:"装备箱", row:1, col:9});
        var tooLarge:Object = LootContainerService.beginFixture(
            {presetName:"资源箱", row:9, col:8});
        var directResult:Object = LootContainerService.beginFixture(
            {presetName:"资源箱", row:0, col:0});
        check(arbitraryResult.handled && arbitraryResult.reserved
                && smallestResult.handled && smallestResult.reserved
                && boundaryResult.handled && boundaryResult.reserved
                && LootContainerService.classifyFixtureShape(arbitrary)
                    == "supported_web_grid"
                && LootContainerService.classifyFixtureShape(smallest)
                    == "supported_web_grid"
                && LootContainerService.classifyFixtureShape(boundary)
                    == "supported_web_grid"
                && tooWide.handled && !tooWide.reserved
                && tooWide.reason == "unsupported_grid_shape"
                && tooLarge.handled && !tooLarge.reserved
                && tooLarge.reason == "unsupported_grid_shape"
                && !directResult.handled && directResult.reason == "direct_delivery",
            "任意正网格按 8 列/64 格边界进入 Web，超界 fail closed，非正网格才 direct");

        var fractionTarget:Object = {presetName:"装备箱", row:2.5, col:4};
        var stringTarget:Object = {presetName:"装备箱", row:"2", col:4};
        var nanTarget:Object = {presetName:"装备箱", row:Number("not-a-number"), col:4};
        var infinityTarget:Object = {
            presetName:"装备箱", row:Number.POSITIVE_INFINITY, col:4};
        var knownMissingTarget:Object = {presetName:"装备箱"};
        var mixedMalformedTarget:Object = {presetName:"资源箱", row:2};
        var mixedSignTarget:Object = {presetName:"资源箱", row:-1, col:4};
        var unrelatedTarget:Object = {presetName:"投影召唤器", row:4, col:8};
        var fractionResult:Object = LootContainerService.beginFixture(fractionTarget);
        var stringResult:Object = LootContainerService.beginFixture(stringTarget);
        var nanResult:Object = LootContainerService.beginFixture(nanTarget);
        var infinityResult:Object = LootContainerService.beginFixture(infinityTarget);
        var knownMissingResult:Object = LootContainerService.beginFixture(knownMissingTarget);
        var mixedMalformedResult:Object = LootContainerService.beginFixture(mixedMalformedTarget);
        var mixedSignResult:Object = LootContainerService.beginFixture(mixedSignTarget);
        var unrelatedResult:Object = LootContainerService.beginFixture(unrelatedTarget);
        check(LootContainerService.classifyFixtureShape(fractionTarget)
                    == "unsupported_grid_shape"
                && LootContainerService.classifyFixtureShape(stringTarget)
                    == "unsupported_grid_shape"
                && LootContainerService.classifyFixtureShape(nanTarget)
                    == "unsupported_grid_shape"
                && LootContainerService.classifyFixtureShape(infinityTarget)
                    == "unsupported_grid_shape"
                && LootContainerService.classifyFixtureShape(knownMissingTarget)
                    == "unsupported_grid_shape"
                && LootContainerService.classifyFixtureShape(mixedMalformedTarget)
                    == "unsupported_grid_shape"
                && LootContainerService.classifyFixtureShape(mixedSignTarget)
                    == "direct_delivery"
                && LootContainerService.classifyFixtureShape(unrelatedTarget)
                    == "not_web_loot_grid"
                && fractionResult.handled && stringResult.handled
                && nanResult.handled && infinityResult.handled
                && knownMissingResult.handled && mixedMalformedResult.handled
                && !mixedSignResult.handled
                && !unrelatedResult.handled && !unrelatedResult.reserved
                && unrelatedResult.reason == "not_web_loot_grid",
            "六箱域内 malformed fail closed、完整非正整数 direct；正网格投影召唤器不被 loot 劫持");
        var markerIgnored:Object = {presetName:"装备箱", row:2, col:4,
            chestRolloutId:"s1.partial"};
        var markerIgnoredResult:Object = LootContainerService.beginFixture(markerIgnored);
        check(markerIgnoredResult.handled && markerIgnoredResult.reserved,
            "authored rollout marker 不再参与运行时路由");
        LootContainerService.abortReservedOpen(markerIgnored, "test_marker_ignored");

        var target:Object = makeTarget("s1.reserve");
        var inventory:ArrayInventory = makeInventory([stack(STACK, 2, 1)]);
        var begun:Object = LootContainerService.beginFixture(target);
        var reentrantBegin:Object = null;
        var committed:Object = LootContainerService.commitReservedOpen(target, inventory,
            function(box:Object):Boolean {
                reentrantBegin = LootContainerService.beginFixture(
                    makeTarget("s1.reentrant-busy"));
                return LootContainerService.observeDeath(box).ownKill === true;
            });
        var overwrite:Object = LootContainerService.commitReservedOpen(
            target, makeInventory([]), function(box:Object):Boolean { return false; });
        var secondTarget:Object = LootContainerService.beginFixture(makeTarget("s1.second"));
        var pendingOpen:Object = LootContainerService.guardOpenGridFixture(target);
        var pendingBreak:Object = LootContainerService.guardBreakGridFixture(target);
        var unrelatedBreak:Object = LootContainerService.guardBreakGridFixture(
            makeTarget("s1.break-other"));
        check(begun.handled && begun.state == "LOOT_COMMIT_PENDING"
                && reentrantBegin.handled && !reentrantBegin.reserved
                && reentrantBegin.reason == "loot_flow_busy"
                && !overwrite.success && overwrite.error == "materialization_conflict"
                && secondTarget.handled && secondTarget.reason == "loot_flow_busy"
                && !pendingOpen.handled
                && pendingOpen.reason == "loot_reservation_ready"
                && pendingBreak.handled && pendingBreak.reason == "loot_reservation_pending"
                && !unrelatedBreak.handled,
            "commit 先固化唯一 inventory；覆盖、并发 reservation 与同箱破碎均 fail closed");

        var duplicateDeath:Object = LootContainerService.observeDeath(target);
        var active:Object = LootContainerService.activateReservedOpen(target);
        var revision:Number = active.authorityRevision;
        var duplicateActivation:Object = LootContainerService.activateReservedOpen(target);
        var activeBreak:Object = LootContainerService.guardBreakGridFixture(target);
        check(committed.success
                && duplicateDeath.ownKill && duplicateDeath.reason == "duplicate_own_death"
                && active.success && active.closeLease != ""
                && duplicateActivation.success && duplicateActivation.duplicate
                && duplicateActivation.authorityRevision == revision
                && activeBreak.handled && activeBreak.reason == "loot_authority_active",
            "kill proof 后重复 death/open-frame 均幂等且不推进 revision");
        LootContainerService.expireScene("scene_cleanup");
    }

    private static function testMaterializedInventoryValidationFence():Void {
        resetWorld();
        var target:Object = makeTarget("s1.materialization-fence-inventory");
        var inventory:ArrayInventory = new ArrayInventory(null, 7);
        var item:BaseItem = stack(STACK, 1, 82);
        inventory.add(0, item);
        var begun:Object = LootContainerService.beginFixture(target);
        var killCalls:Number = 0;
        var inventoryRejected:Object = LootContainerService.commitReservedOpen(
            target, inventory,
            function(box:Object):Boolean { killCalls++; return true; });
        var replacement:ArrayInventory = makeInventory([stack(STACK, 1, 81)]);
        var overwriteRejected:Object = LootContainerService.commitReservedOpen(
            target, replacement,
            function(box:Object):Boolean { killCalls++; return true; });
        var abortRejected:Object = LootContainerService.abortReservedOpen(
            target, "materialization_failed");
        var expiryRejected:Object = LootContainerService.expireScene("scene_cleanup");
        var diagnostic:Object = LootContainerService.execute("query", {
            v:1,
            chestSessionId:begun.chestSessionId,
            lootContainerId:begun.lootContainerId,
            containerEpoch:begun.containerEpoch
        });
        var breakGuard:Object = LootContainerService.guardBreakGridFixture(target);

        check(!inventoryRejected.success
                && inventoryRejected.error == "invalid_loot_inventory"
                && inventoryRejected.state == "LOOT_COMMIT_PENDING"
                && inventoryRejected.remainingCount == 1 && killCalls == 0
                && !overwriteRejected.success
                && overwriteRejected.error == "materialization_conflict"
                && overwriteRejected.remainingCount == 1
                && !abortRejected.success && abortRejected.error == "commit_pending"
                && !expiryRejected.success && expiryRejected.error == "commit_pending"
                && !diagnostic.success && diagnostic.error == "commit_pending"
                && diagnostic.state == "LOOT_COMMIT_PENDING"
                && diagnostic.remainingCount == 1 && inventory.getItem("0") === item
                && breakGuard.handled && breakGuard.reason == "loot_reservation_pending",
            "planner inventory 先固化；capacity 拒绝后覆盖、abort 与 scene cleanup 均不可吞奖励");
    }

    private static function testReservationKillUnavailableRecovery():Void {
        resetWorld();
        var unavailableTarget:Object = makeTarget("s1.kill-unavailable");
        var unavailableInventory:ArrayInventory = makeInventory([stack(STACK, 1, 9)]);
        var unavailableBegin:Object = LootContainerService.beginFixture(unavailableTarget);
        var unavailable:Object = LootContainerService.commitReservedOpen(
            unavailableTarget, unavailableInventory, null);
        var unavailableRetry:Object = LootContainerService.beginFixture(unavailableTarget);
        var unavailableBreak:Object = LootContainerService.guardBreakGridFixture(unavailableTarget);
        var unavailableExpiry:Object = LootContainerService.expireScene("scene_cleanup");
        check(unavailableBegin.reserved
                && !unavailable.success && unavailable.error == "kill_adapter_unavailable"
                && unavailableRetry.handled && !unavailableRetry.reserved
                && unavailableRetry.reason == "loot_reservation_pending"
                && unavailableBreak.handled
                && unavailableBreak.reason == "loot_reservation_pending"
                && !unavailableExpiry.success
                && unavailableExpiry.error == "commit_pending"
                && unavailableExpiry.state == "LOOT_COMMIT_PENDING"
                && unavailableInventory.getItem("0") != null,
            "kill adapter 缺失保留 pending hard fence，scene cleanup 不得吞掉已物化奖励");
    }

    private static function testReservationActivationGateRecovery():Void {
        resetWorld();
        var gateTarget:Object = makeTarget("s1.activation-gate");
        var gateInventory:ArrayInventory = makeInventory([stack(STACK, 1, 10)]);
        LootContainerService.beginFixture(gateTarget);
        var gateCommitted:Object = LootContainerService.commitReservedOpen(
            gateTarget, gateInventory,
            function(box:Object):Boolean { return false; });
        var rejected:Object = LootContainerService.activateReservedOpen(gateTarget);
        var gateRetry:Object = LootContainerService.beginFixture(gateTarget);
        var gateBreak:Object = LootContainerService.guardBreakGridFixture(gateTarget);
        var gateExpiry:Object = LootContainerService.expireScene("scene_cleanup");

        resetWorld();
        var holdTarget:Object = makeTarget("s1.activation-hold");
        holdTarget.stop = function():Void { throw "forced_target_hold_failure"; };
        var holdInventory:ArrayInventory = makeInventory([stack(STACK, 1, 11)]);
        LootContainerService.beginFixture(holdTarget);
        var holdCommitted:Object = LootContainerService.commitReservedOpen(
            holdTarget, holdInventory, function(box:Object):Boolean {
                box._killed = true;
                return LootContainerService.observeDeath(box).ownKill === true;
            });
        var holdRejected:Object = LootContainerService.activateReservedOpen(holdTarget);
        var holdExpiry:Object = LootContainerService.expireScene("scene_cleanup");
        var holdBreak:Object = LootContainerService.guardBreakGridFixture(holdTarget);
        check(!gateCommitted.success && gateCommitted.error == "kill_adapter_failed"
                && !rejected.success && rejected.error == "activation_gate_failed"
                && gateRetry.handled && gateRetry.reason == "loot_reservation_pending"
                && gateBreak.handled && gateBreak.reason == "loot_reservation_pending"
                && !gateExpiry.success && gateExpiry.error == "commit_pending"
                && gateInventory.getItem("0") != null
                && holdCommitted.success
                && !holdRejected.success && holdRejected.error == "target_hold_failed"
                && !holdExpiry.success && holdExpiry.error == "commit_pending"
                && holdExpiry.state == "LOOT_COMMIT_PENDING"
                && holdBreak.handled && holdBreak.reason == "loot_reservation_pending"
                && holdInventory.getItem("0") != null,
            "activation/target hold 内部失败保留 materialized pending hard fence，scene cleanup 不吞奖励");
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
            target, inventory, function(box:Object):Boolean {
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
            LootContainerService.testOnlyFailNextPostCommit("dirty");
            var expiryBlocked:Object = LootContainerService.expireScene("scene_cleanup");
            var recovered:Object = LootContainerService.execute("query", queryParams(authority));

            check(!pending.success && pending.error == "commit_pending"
                    && pending.state == "LOOT_COMMIT_PENDING"
                    && pending.lastAppliedOperationId == operationId
                    && !snapshotBlocked.success && snapshotBlocked.error == "commit_pending"
                    && !otherClaim.success && otherClaim.error == "commit_pending"
                    && !closeBlocked.success && closeBlocked.error == "commit_pending"
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

    private static function testTransportDetachUnpauseLastItemRetry():Void {
        var sourceOwner:MovieClip = _root.createEmptyMovieClip(
            "__loot_detach_unpause_source", _root.getNextHighestDepth());
        var destinationOwner:MovieClip = _root.createEmptyMovieClip(
            "__loot_detach_unpause_destination", _root.getNextHighestDepth());
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
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
            _root._webPanelPauseLease = "test-detach-unpause-last-item";
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

            check(!pending.success && pending.error == "commit_pending"
                    && firstDetach.handled && !firstDetach.recovered
                    && firstDetach.reason == "recovery_pending"
                    && fenceHeld && fenceReleased
                    && queryRecovered.success && queryRecovered.state == "CONSUMED"
                    && queryRecovered.terminal != null
                    && queryRecovered.terminal.kind == "CONSUMED"
                    && sourceEvents == 1 && destinationEvents == 1
                    && flow.inventory.getItem("0") == null
                    && _root.物品栏.背包.getItem("0") === item,
                "detach unpause retry");
        } finally {
            _root.server = previousServer;
            _root._webPanelPauseLease = undefined;
            sourceOwner.removeMovieClip();
            destinationOwner.removeMovieClip();
        }
    }

    private static function testTransportDetachConflictStaysPending():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
            var item:BaseItem = equipment(3952);
            var flow:Object = activate([item], "s1.detach-conflict");
            LootContainerService.requestOpenPanel();
            callbacks[0]({success:true, accepted:true});
            var openAttemptSeq:Number = Number(sent[0].payload.initData.openAttemptSeq);
            var authority:Object = snapshot(flow);

            LootClaimCommitCoordinator.testOnlyFailNext(
                "ordinary_destination_write", "after_false");
            var pending:Object = LootContainerService.execute(
                "claim", claimParams(authority, 0, "claim.detach-conflict"));
            var conflicting:BaseItem = equipment(3953);
            _root.物品栏.背包.transactionWrite(0, conflicting);
            _root._webPanelPauseLease = "test-detach-conflict";

            var detached:Object = LootContainerService.reconcileSocketDetach(flow.target);
            var exactRetry:Object = LootContainerService.execute("query",
                proofQueryParams(authority, openAttemptSeq, "socket.detach.conflict"));
            var expiryBlocked:Object = LootContainerService.expireScene("scene_cleanup");

            check(!pending.success && pending.error == "commit_pending"
                    && !detached.success && detached.error == "claim_commit_pending"
                    && detached.state == "LOOT_COMMIT_PENDING"
                    && !exactRetry.success && exactRetry.error == "commit_pending"
                    && !expiryBlocked.success && expiryBlocked.error == "commit_pending"
                    && LootContainerService.hasPendingTransportDetach()
                    && flow.inventory.getItem("0") === item
                    && _root.物品栏.背包.getItem("0") === conflicting
                    && _root._webPanelPauseLease == "test-detach-conflict"
                    && _root.存档系统.dirtyMark === false,
                "detach 遇 destination 冲突保持 journal、inventory、pause 与 scene hard fence");
        } finally {
            _root.server = previousServer;
            _root._webPanelPauseLease = undefined;
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
            check(suspended.success && suspended.state == "LOOT_SUSPENDED"
                    && suspended.closeLease == "" && suspended.terminal == null
                    && suspended.snapshots.length == 0 && suspended.remainingCount == 1
                    && duplicateSuspend.success && duplicateSuspend.state == "LOOT_SUSPENDED"
                    && flow.target._killed === true && flow.target.stopCount == 1
                    && flow.target.stopped,
                "非空 close(false) 落 first-class suspend，保留 killed/同一 inventory");

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
        check(suspended.success && first.success && first.suspendedWithoutPanel
                && first.pauseReleaseRequired && first.pauseReleased
                && first.state == "LOOT_SUSPENDED"
                && second.success && second.suspendedWithoutPanel
                && second.pauseReleaseRequired !== true
                && _root._webPanelPauseLease == "later-panel-lease"
                && LootContainerService.canReopenSuspendedTarget(flow.target),
            "socket close 对 suspend 只完成 exact pause proof；稳定态不派生替代展示、不 pending、不释放后来 lease");
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
        try {
            resetWorld();
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
                    && flow.target.stopped,
                "transport 存在但 disconnected 的同步 callback failure 恢复 exact suspend，不误报 reopen");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
        }
    }

    private static function testSuspendAsyncRejectionRestoresAndStalesLateCallback():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
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
                    && flow.target.stopCount == 1,
                "async rejection 收回 exact suspend；新 reopen 后迟到旧 callback 不污染 authority");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
        }
    }

    private static function testSuspendAsyncTimeoutRestoresAnchor():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
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
                    && flow.target.stopped,
                "async timeout 收回原 suspend，但必须等 exact unpause/detach proof 后才重新开放 anchor");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
        }
    }

    private static function testSuspendSocketDetachOrderingAndLateCallback():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
            var flow:Object = activate([stack(STACK, 1, 618)], "s1.suspend-socket-order");
            var before:Object = snapshot(flow);
            LootContainerService.execute("close",
                closeParams(before, "close.suspend-socket-order", before.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();

            var first:Object = LootContainerService.resumeSuspended(flow.target);
            var firstAttempt:Number = Number(sent[0].payload.initData.openAttemptSeq);
            // 对齐 ServerManager.onSocketClose：先执行 transport detach，随后才失败
            // _pendingCallbacks。此时必须直接恢复 Web-only suspend。
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
                    && detached.success && detached.suspendedWithoutPanel
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
                    && callbacks.length == 3,
                "socket proof 恢复 suspend；pre-ACK recovery 只登记，ACK 后才应用且旧 proof 不证明新 ACTIVE");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
        }
    }

    private static function testSuspendReopenAnchorLossExpires():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
            var flow:Object = activate([stack(STACK, 1, 619)], "s1.suspend-reopen-anchor-loss");
            var before:Object = snapshot(flow);
            LootContainerService.execute("close",
                closeParams(before, "close.suspend-reopen-anchor-loss", before.closeLease, false));
            LootContainerService.releaseSuspendedPauseForClose();
            var dispatched:Object = LootContainerService.resumeSuspended(flow.target);

            // callback 前 target 已失去 scene anchor；恢复不得停留 ACTIVE，也不得
            // 把同一 inventory 交给第二套展示生命周期。
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
                    && flow.target.playCount == 1
                    && next.handled && next.reserved,
                "reopen rollback 丢失 exact anchor 时显式 EXPIRED、释放 busy");
            LootContainerService.abortReservedOpen(nextTarget, "test_cleanup");
        } finally {
            _root.server = previousServer;
        }
    }

    private static function testSuspendSocketDetachAnchorLossReleasesPause():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
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
                    && detached.success && detached.suspendedWithoutPanel
                    && detached.state == "EXPIRED" && detached.pauseReleaseRequired === false
                    && _root._webPanelPauseLease == undefined
                    && terminal.success && terminal.state == "EXPIRED"
                    && terminal.terminal != null
                    && terminal.terminal.reason == "suspended_anchor_lost"
                    && flow.target.playCount == 1
                    && next.handled && next.reserved,
                "pending reopen 断线+锚点丢失先释放 exact pause，再落 EXPIRED");
            LootContainerService.abortReservedOpen(nextTarget, "test_cleanup");
        } finally {
            _root._webPanelPauseLease = undefined;
            _root.server = previousServer;
        }
    }

    private static function testSuspendSocketDetachPauseReleaseRetry():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
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
            // 或先改变 authority。
            LootContainerService.testOnlyFailNextTransportHandoff("unpause");
            var proofStillPending:Object = LootContainerService.execute("query",
                proofQueryParams(before, attemptSeq, "socket.unpause.retry"));
            var recovered:Object = LootContainerService.execute("query",
                proofQueryParams(before, attemptSeq, "socket.unpause.retry"));
            var fenceReleased:Boolean = !LootContainerService.hasPendingTransportDetach();
            if (callbacks.length > 0) callbacks[0]({success:false, error:"socket closed"});
            var stable:Object = LootContainerService.execute("query", queryParams(before));

            check(dispatched.success && dispatched.reopened && sent.length == 1
                    && !firstDetach.success && firstDetach.suspendedWithoutPanel
                    && firstDetach.pauseReleaseRequired
                    && firstDetach.error == "suspend_pause_release_failed"
                    && firstDetach.state == "LOOT_COMMIT_PENDING"
                    && fenceHeld && leaseHeld
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
        }
    }

    private static function testSuspendDirectReopenPauseReleaseRetry():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
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
                    && flow.target.playCount == 0,
                "direct reopen rejection 的 non-empty pause release 可 exact 重试且不改 revision");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root._webPanelPauseLease = undefined;
            _root.server = previousServer;
        }
    }

    private static function testSuspendTerminalReopenPauseReleaseRetry():Void {
        var previousServer:Object = _root.server;
        try {
            // empty reopen failure：首次内部 release 失败后必须保留 PENDING fence；
            // 未授权 proof 只投影 commit_pending，不得顺带推进 release。
            resetWorld();
            var emptySent:Array = [];
            var emptyCallbacks:Array = [];
            installPanelTransport(emptySent, emptyCallbacks);
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
            installPanelTransport(anchorSent, anchorCallbacks);
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
                    && emptyFlow.target.playCount == 1
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
                    && anchorFlow.target.playCount == 1
                    && afterAnchor.handled && afterAnchor.reserved,
                "empty/anchor-lost reopen 的 pause release 失败保留可重试 fence；终态只提交一次且 proof shape 合法");
            LootContainerService.abortReservedOpen(afterAnchorTarget, "test_cleanup");
        } finally {
            _root._webPanelPauseLease = undefined;
            _root.server = previousServer;
        }
    }

    private static function testSuspendAcceptedRecoveryStaysSuspended():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
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
            var guard:Object = LootContainerService.guardOpenGridFixture(
                flow.target);
            check(dispatched.success && dispatched.reopened
                    && recovered.handled && recovered.recovered
                    && recovered.suspended
                    && authority.success && authority.state == "LOOT_SUSPENDED"
                    && authority.remainingCount == 1
                    && proof.success && proof.state == "LOOT_SUSPENDED"
                    && LootContainerService.canReopenSuspendedTarget(flow.target)
                    && guard.handled && guard.reopen,
                "reopen recovery 在 accepted callback 前后都回到 first-class SUSPENDED");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
        }
    }

    private static function testCloseAttemptProofSurvivesRejectedReopen():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
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
                    && proofAAfterCReject.success,
                "close 不提前推进 attempt；A proof 丢回包后跨 B/C rejection 与no-send 仍可证明 suspend");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
        }
    }

    private static function testRecoveryProofLedgerOrderingAndCapacity():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
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
                    && laterProofAfterDelayedOlder.state == "LOOT_SUSPENDED",
                "proof ledger 满时 fail closed 不 LRU；exact query 收敛旧项，迟到较旧 query 不删 later proof");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
        }
    }

    private static function testSuspendReopenFailureEmptyConsumes():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
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
            var nextTarget:Object = makeTarget("s1.after-reopen-empty");
            var next:Object = LootContainerService.beginFixture(nextTarget);
            check(dispatched.success && dispatched.reopened
                    && terminal.success && terminal.state == "CONSUMED"
                    && terminal.remainingCount == 0 && terminal.terminal != null
                    && terminal.terminal.kind == "CONSUMED"
                    && terminal.terminal.reason == "panel_open_failure_empty"
                    && flow.target.playCount == 1
                    && next.handled && next.reserved,
                "reopen failure 发现同一 inventory 已空时直接 CONSUMED，不生成空 suspend");
            LootContainerService.abortReservedOpen(nextTarget, "test_cleanup");
        } finally {
            _root.server = previousServer;
        }
    }

    private static function testInitialOpenSynchronousFailureSuspendsSameInventory():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            _root.server = {
                sendTaskWithCallback:function(task:String, payload:Object, extra:Object,
                                              callback:Function, timeoutFrames:Number):Void {
                    callback({success:false, error:"socket not connected"});
                }
            };
            var item:BaseItem = stack(STACK, 1, 620);
            var flow:Object = activate([item], "s1.initial-sync-failure");
            var requested:Boolean = LootContainerService.requestOpenPanel();
            var authority:Object = LootContainerService.execute(
                "query", queryParams(flow.active));
            var guard:Object = LootContainerService.beginFixture(flow.target);
            check(!requested && authority.success
                    && authority.state == "LOOT_SUSPENDED"
                    && authority.remainingCount == 1
                    && flow.inventory.getItem("0") === item
                    && guard.handled && guard.reopen
                    && LootContainerService.canReopenSuspendedTarget(flow.target),
                "初次 open 同步失败保留 same target/inventory 并进入 Web-only suspend");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
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

    private static function testReliablePanelOpenCallbacks():Void {
        var previousServer:Object = _root.server;
        try {
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
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
            var rejectedGuard:Object = LootContainerService.guardOpenGridFixture(
                makeTarget("s1.after-panel-rejected"));
            check(rejectedQuery.success && rejectedQuery.state == "LOOT_SUSPENDED"
                    && rejectedQuery.remainingCount == 1
                    && rejectedGuard.handled && rejectedGuard.reason == "loot_flow_busy"
                    && rejectedFlow.inventory.getItem("0") != null,
                "无 callId 的 Host rejection 收回 same inventory 到 Web-only suspend");

            sent = []; callbacks = [];
            installPanelTransport(sent, callbacks);
            resetWorld();
            var timeoutFlow:Object = activate([stack(STACK, 1, 712)], "s1.panel-timeout");
            LootContainerService.requestOpenPanel();
            callbacks[0]({success:false, error:"callback timeout"});
            var timeoutQuery:Object = LootContainerService.execute("query", queryParams(timeoutFlow.active));
            var timeoutGuard:Object = LootContainerService.guardOpenGridFixture(makeTarget("s1.after-timeout"));
            check(timeoutQuery.success && timeoutQuery.state == "LOOT_SUSPENDED"
                    && timeoutGuard.handled && timeoutGuard.reason == "loot_flow_busy"
                    && timeoutFlow.inventory.getItem("0") != null,
                "panel callback timeout 保留 same inventory 并进入 Web-only suspend");

            sent = []; callbacks = [];
            installPanelTransport(sent, callbacks);
            resetWorld();
            var disconnectFlow:Object = activate([stack(STACK, 1, 713)], "s1.panel-disconnect");
            LootContainerService.requestOpenPanel();
            callbacks[0]({success:false, error:"socket closed"});
            var disconnectQuery:Object = LootContainerService.execute(
                "query", queryParams(disconnectFlow.active));
            var disconnectGuard:Object = LootContainerService.guardOpenGridFixture(
                makeTarget("s1.after-disconnect"));
            check(disconnectQuery.success && disconnectQuery.state == "LOOT_SUSPENDED"
                    && disconnectGuard.handled && disconnectGuard.reason == "loot_flow_busy"
                    && disconnectFlow.inventory.getItem("0") != null,
                "panel callback 断线保留 same inventory 并进入 Web-only suspend");

            sent = []; callbacks = [];
            installPanelTransport(sent, callbacks);
            resetWorld();
            var oldFlow:Object = activate([stack(STACK, 1, 714)], "s1.panel-old-callback");
            LootContainerService.requestOpenPanel();
            var oldCallback:Function = callbacks[0];
            LootContainerService.expireScene("scene_cleanup");
            sent = []; callbacks = [];
            installPanelTransport(sent, callbacks);
            resetWorld();
            var freshFlow:Object = activate([stack(STACK, 1, 715)], "s1.panel-fresh-authority");
            oldCallback({success:false, accepted:false, error:"open_not_queued"});
            var freshQuery:Object = LootContainerService.execute("query", queryParams(freshFlow.active));
            var freshGuard:Object = LootContainerService.guardOpenGridFixture(
                makeTarget("s1.after-stale-callback"));
            check(freshQuery.success && freshQuery.state == "LOOT_ACTIVE"
                    && !freshGuard.handled,
                "迟到旧 open callback 复核 session/container/epoch，不污染 fresh authority");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
        }
    }

    private static function testRecoveryProofStrictShapeAndNonce():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
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
                    && validRecoveryResult.reason == "recovery_pending",
                "wire query 严格 7/9 键、recovery 严格 8 键；opaque 与 Host 统一 ._~- 及 128 边界");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
        }
    }

    private static function testInitialRecoveryBeforeAckProof():Void {
        var previousServer:Object = _root.server;
        try {
            resetWorld();
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
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
                    && proofAfterAck.success && proofAfterAck.state == "LOOT_SUSPENDED"
                    && duplicateSignal.handled && duplicateSignal.recovered
                    && duplicateSignal.duplicate
                    && duplicateProof.success
                    && !wrongNonce.success && wrongNonce.error == "recovery_nonce_mismatch"
                    && flow.inventory.getItem("0") != null,
                "initial recovery 早于 ACK 只登记；ACK 后挂起同一 inventory，错 nonce 零副作用");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
        }
    }

    private static function testConnectedPanelRecoverySignal():Void {
        var previousServer:Object = _root.server;
        try {
            var sent:Array = [];
            var callbacks:Array = [];
            installPanelTransport(sent, callbacks);
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
            var recoveryGuard:Object = LootContainerService.guardOpenGridFixture(
                makeTarget("s1.after-connected-recovery"));

            LootContainerService.expireScene("scene_cleanup");
            resetWorld();
            var freshFlow:Object = activate([stack(STACK, 1, 717)], "s1.connected-recovery-fresh");
            var late:Object = LootContainerService.handlePanelRecovery(envelope);
            var freshQuery:Object = LootContainerService.execute("query", queryParams(freshFlow.active));
            check(!malformedResult.handled && malformedResult.reason == "invalid_payload"
                    && !staleResult.handled && staleResult.reason == "stale_open_attempt"
                    && recovered.handled && recovered.recovered && recovered.suspended
                    && duplicate.handled && duplicate.recovered && duplicate.duplicate
                    && flow.inventory.getItem("0") != null
                    && recoveryQuery.success && recoveryQuery.state == "LOOT_SUSPENDED"
                    && recoveryGuard.handled && recoveryGuard.reason == "loot_flow_busy"
                    && !late.handled && late.reason == "stale_identity"
                    && freshQuery.success && freshQuery.state == "LOOT_ACTIVE",
                "accepted 后 exact8 recovery 匹配 identity+attempt+nonce并挂起；畸形/迟到拒绝、重复幂等");
            LootContainerService.expireScene("scene_cleanup");
        } finally {
            _root.server = previousServer;
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
