import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.CharacterBuildService;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

/** Gate A2/A3：inventory-domain lease、原子事务、窗口化与整容器整理回归。 */
class org.flashNight.arki.item.InventoryPanelServiceTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        trace("=== InventoryPanelServiceTest start ===");

        testWorkbenchPanelRequest();
        testRangeSnapshot();
        testStableReadLeaseAndMutationVersion();
        testFilteredSnapshot();
        testEquipmentProjectionScope();
        testArrayInventoryMutationRevision();
        testFacetCacheInvalidation();
        testItemUtilBalanceExtraction();
        testPresentationProjection();
        testBalanceSummaryProjection();
        testTooltipLeaseAndInstance();
        testSourceAndTargetStale();
        testMergeCountStale();
        testDomainReject();
        testBattleboxAccessPolicy();
        testBattleboxTransfers();
        testAutoTransferAuthorityQueueAndFailure();
        testAutoTransferBatchSuccessAndSingleScan();
        testAutoTransferBatchPartialAndValidation();
        testAutoTransferBatchRollback();
        testAutoTransferBatchComparison();
        testMoveMergeSwapAndReverse();
        testSameContainerTransfersAndRollback();
        testEventReentrancy();
        testCommitFailureRollback();
        testDiscardProjectionAndSuccess();
        testSortValidationMergeEpochAndLease();
        testBackpackAuthoritySort();
        testBattleboxAccessiblePrefixSort();
        testSortRejectsLossyPlan();
        testSortCommitFailureRollback();
        testSortEventReentrancy();
        testWindowPerformanceMatrix();
        testFullWarehouseSortPerformance();

        trace("InventoryPanelServiceTest Tests Passed: " + _passed);
        trace("InventoryPanelServiceTest Tests Failed: " + _failed);
        trace("=== InventoryPanelServiceTest end ===");
    }

    private static function resetInventories():Void {
        _root.物品栏 = {
            背包: new ArrayInventory(null, 50),
            仓库: new ArrayInventory(null, 1200),
            战备箱: new ArrayInventory(null, 400)
        };
        _root.主线任务进度 = 0;
        _root.task_chains_progress = {挑战: 0};
        _root.基建系统 = {infrastructure: {越野车: false}};
        _root.存档系统 = {dirtyMark: false};
        InventoryPanelService.testOnlyReset();
    }

    private static function characterBuildReadinessRoot():Object {
        var equipment:Object = {
            getItem:function(key:String):Object {
                return null;
            }
        };
        var drugs:Object = {
            getMutationRevision:function():Number {
                return 1;
            },
            getItem:function(key:String):Object {
                return null;
            }
        };
        var backpack:Object = {
            capacity:50,
            getMutationRevision:function():Number {
                return 1;
            },
            getItem:function(key:String):Object {
                return null;
            }
        };
        var root:Object = {
            物品栏:{
                装备栏:equipment,
                药剂栏:drugs,
                背包:backpack
            },
            控制目标:"readinessHero"
        };
        var gameworld:Object = {};
        var hero:Object = {
            _name:"readinessHero",
            _parent:gameworld,
            aabbCollider:{},
            新版人物文字信息:{},
            dispatcher:{
                publish:function():Void {},
                subscribe:function():String {
                    return "readiness";
                },
                destroy:function():Void {}
            },
            buffManager:{
                update:function():Void {},
                addBuff:function():String {
                    return "readiness";
                },
                removeBuff:function():Boolean {
                    return true;
                },
                destroy:function():Void {}
            },
            buff:{
                初始:function():Void {},
                更新:function():Void {}
            },
            读取基础被动效果:function():Void {},
            gotoAndStop:function():Void {},
            根据模式重新读取武器加成:function():Void {},
            装载主动战技:function():Void {},
            装载生命周期函数:function():Void {},
            完成生命周期函数装载:function():Void {},
            dressupRefreshing:false
        };
        gameworld.readinessHero = hero;
        root.gameworld = gameworld;
        root.刷新人物装扮 = function(target:String):Void {};
        root.装备引用配置 = {
            刷新所有装扮:function():Void {}
        };
        root.根据等级计算值 = function():Number {
            return 1;
        };
        root.主角函数 = {
            创建主动战技槽位表:function():Object {
                return {};
            },
            获取装备主动战技种类:function():String {
                return "";
            }
        };
        root.敌人函数 = {魔法伤害种类:[]};
        root.玩家信息界面 = {
            刷新攻击模式:function():Void {}
        };
        root.UI系统 = {
            iconBar:{initialize:function():Void {}}
        };
        return root;
    }

    private static function item(name:String, value):Object {
        return {name: name, value: value, lastUpdate: 1};
    }

    private static function testWorkbenchPanelRequest():Void {
        var fixture:Array = [{name:"中心表注入测试装备", setId:"test_center_set"}];
        fixture.itemSets = [{id:"test_center_set", name:"中心表注入测试套装", order:77}];
        ItemUtil.hydrateItemSetMetadata(fixture);
        assertTrue(fixture[0].setName == "中心表注入测试套装"
                && Number(fixture[0].setOrder) == 77,
            "ItemUtil hydrates setName/setOrder from item_sets metadata");

        var previousServer:Object = _root.server;
        var captured:String = "";
        var sendCount:Number = 0;
        _root.server = {
            sendSocketMessage: function(message:String):Boolean {
                captured = message;
                sendCount++;
                return true;
            }
        };
        var readinessRoot:Object =
            characterBuildReadinessRoot();
        CharacterBuildService.testOnlyUseRoot(
            readinessRoot);
        var opened:Boolean = InventoryPanelService.requestOpenWorkbench({
            profile: "warehouse",
            source: "dormitory"
        });
        assertTrue(opened && sendCount == 1, "宿舍仓库入口发送一次 panel_request");
        assertTrue(captured.indexOf('"task":"panel_request"') >= 0
            && captured.indexOf('"panel":"workbench"') >= 0
            && captured.indexOf('"profile":"warehouse"') >= 0
            && captured.indexOf('"view":"storage"') >= 0
            && captured.indexOf('"source":"dormitory"') >= 0,
            "宿舍入口发送 storage/profile/source");
        var tuningOpened:Boolean = InventoryPanelService.requestOpenWorkbench({
            profile: "warehouse", view: "tuning", source: "equipment_tuning"
        });
        assertTrue(tuningOpened && sendCount == 2
                && captured.indexOf('"view":"tuning"') >= 0,
            "调制入口发送 tuning view");
        var buildOpened:Boolean = InventoryPanelService.requestOpenWorkbench({
            profile:"battlebox", view:"build", source:"agent_control"
        });
        assertTrue(buildOpened && sendCount == 3
                && captured.indexOf('"profile":"battlebox"') >= 0
                && captured.indexOf('"view":"build"') >= 0
                && captured.indexOf('"source":"agent_control"') >= 0
                && captured.indexOf('"openRequestId"') < 0,
            "agent_control 受控直达无需 nonce 且不合成字段");
        var nativeHudLegacyBuildOpened:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"build",
                source:"nativehud_equipment"
            });
        assertTrue(!nativeHudLegacyBuildOpened && sendCount == 3,
            "nativehud_equipment 角色构筑缺 nonce 时 fail-closed");
        var nativeHudLegacyStorageOpened:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"storage",
                source:"nativehud_equipment"
            });
        assertTrue(!nativeHudLegacyStorageOpened && sendCount == 3,
            "nativehud_equipment 非 build tuple 直接拒绝");
        var validOpenRequestId:String =
            "workbench.open.Valid_1-2~3";
        for (var validNonceIndex:Number =
                validOpenRequestId.length;
                validNonceIndex < 160;
                validNonceIndex++) {
            validOpenRequestId += "x";
        }
        var nativeHudBuildOpened:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"build",
                source:"nativehud_equipment",
                openRequestId:validOpenRequestId
            });
        assertTrue(nativeHudBuildOpened && sendCount == 4
                && captured.indexOf('"profile":"battlebox"') >= 0
                && captured.indexOf('"view":"build"') >= 0
                && captured.indexOf(
                    '"source":"nativehud_equipment"') >= 0
                && captured.indexOf(
                    '"openRequestId":"' + validOpenRequestId + '"') >= 0,
            "nativehud_equipment 角色构筑顶层原样回显 160 字符合法 openRequestId");
        var nativeHudTuningOpened:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"tuning",
                source:"nativehud_equipment_tuning",
                openRequestId:validOpenRequestId
            });
        assertTrue(nativeHudTuningOpened && sendCount == 5
                && captured.indexOf('"profile":"battlebox"') >= 0
                && captured.indexOf('"view":"tuning"') >= 0
                && captured.indexOf(
                    '"source":"nativehud_equipment_tuning"') >= 0
                && captured.indexOf(
                    '"openRequestId":"' + validOpenRequestId + '"') >= 0,
            "nativehud_equipment_tuning 只按 battlebox/tuning 精确 tuple 原样回显 nonce");
        var rejectedMissingTuningOpenRequestId:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"tuning",
                source:"nativehud_equipment_tuning"
            });
        var rejectedNearTuningView:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"storage",
                source:"nativehud_equipment_tuning",
                openRequestId:validOpenRequestId
            });
        var rejectedNearTuningProfile:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"warehouse",
                view:"tuning",
                source:"nativehud_equipment_tuning",
                openRequestId:validOpenRequestId
            });
        var rejectedNearTuningSource:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"tuning",
                source:"nativehud_equipment_tuning_extra",
                openRequestId:validOpenRequestId
            });
        assertTrue(!rejectedMissingTuningOpenRequestId
                && !rejectedNearTuningView
                && !rejectedNearTuningProfile
                && !rejectedNearTuningSource
                && sendCount == 5,
            "生产调制 opener 缺 nonce 或 source/profile/view 近似 tuple 都零发送");
        var rejectedStorageOpenRequestId:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"storage",
                source:"nativehud_equipment",
                openRequestId:"wrong.storage"
            });
        var rejectedTuningOpenRequestId:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"tuning",
                source:"nativehud_equipment",
                openRequestId:"wrong.tuning"
            });
        var rejectedAgentOpenRequestId:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"build",
                source:"agent_control",
                openRequestId:"wrong.agent"
            });
        assertTrue(!rejectedStorageOpenRequestId
                && !rejectedTuningOpenRequestId
                && !rejectedAgentOpenRequestId
                && sendCount == 5,
            "openRequestId 只允许两个 nativehud 精确 tuple，其他组合零发送");
        var tooLongOpenRequestId:String =
            validOpenRequestId + "x";
        var rejectedNumericOpenRequestId:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"build",
                source:"nativehud_equipment",
                openRequestId:7
            });
        var rejectedNullOpenRequestId:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"build",
                source:"nativehud_equipment",
                openRequestId:null
            });
        var rejectedEmptyOpenRequestId:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"build",
                source:"nativehud_equipment",
                openRequestId:""
            });
        var rejectedWhitespaceOpenRequestId:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"build",
                source:"nativehud_equipment",
                openRequestId:"bad token"
            });
        var rejectedSlashOpenRequestId:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"build",
                source:"nativehud_equipment",
                openRequestId:"bad/token"
            });
        var rejectedLongOpenRequestId:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"build",
                source:"nativehud_equipment",
                openRequestId:tooLongOpenRequestId
            });
        assertTrue(!rejectedNumericOpenRequestId
                && !rejectedNullOpenRequestId
                && !rejectedEmptyOpenRequestId
                && !rejectedWhitespaceOpenRequestId
                && !rejectedSlashOpenRequestId
                && !rejectedLongOpenRequestId
                && sendCount == 5,
            "显式 openRequestId 拒绝非字符串、空值、非法字符与 161 字符超长值且零发送");
        readinessRoot.gameworld = null;
        var rejectedNotReadyBuild:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"build",
                source:"agent_control"
            });
        var storageWhileBuildNotReady:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"warehouse",
                view:"storage",
                source:"dormitory"
            });
        var tuningWhileBuildNotReady:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"warehouse",
                view:"tuning",
                source:"equipment_tuning"
            });
        assertTrue(!rejectedNotReadyBuild
                && storageWhileBuildNotReady
                && tuningWhileBuildNotReady
                && sendCount == 7,
            "build readiness 失败零发送，且 storage/tuning 准入不受影响");
        var rejected:Boolean = InventoryPanelService.requestOpenWorkbench({profile: "仓库"});
        var rejectedView:Boolean = InventoryPanelService.requestOpenWorkbench({profile:"warehouse", view:"editor"});
        var rejectedWarehouseBuild:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"warehouse", view:"build", source:"agent_control"
            });
        var rejectedBuildSource:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox", view:"build", source:"inventory_workbench"
            });
        var rejectedMissingBuildSource:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox", view:"build"
            });
        var rejectedNearBuildSource:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"build",
                source:"nativehud_equipment_extra"
            });
        var rejectedPaddedBuildSource:Boolean =
            InventoryPanelService.requestOpenWorkbench({
                profile:"battlebox",
                view:"build",
                source:"nativehud_equipment "
            });
        assertTrue(!rejected && !rejectedView
                && !rejectedWarehouseBuild && !rejectedBuildSource
                && !rejectedMissingBuildSource
                && !rejectedNearBuildSource
                && !rejectedPaddedBuildSource
                && sendCount == 7,
            "build 仍拒绝非法 profile/view、缺 source、前缀/尾空格及白名单外 source");

        CharacterBuildService.testOnlyReset();
        _root.server = previousServer;
    }

    private static function snapshot(backpackLimit:Number, warehouseLimit:Number):Object {
        return InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [
                {containerId: "背包", offset: 0, limit: backpackLimit},
                {containerId: "仓库", offset: 0, limit: warehouseLimit}
            ]
        });
    }

    private static function warehouseSnapshot(offset:Number, limit:Number):Object {
        return InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [{containerId: "仓库", offset: offset, limit: limit}]
        });
    }

    private static function battleboxSnapshot(offset:Number, limit:Number):Object {
        return InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [{containerId: "战备箱", offset: offset, limit: limit}]
        });
    }

    private static function unlockFullBattlebox():Void {
        _root.主线任务进度 = 78;
        _root.task_chains_progress.挑战 = 3;
        _root.基建系统.infrastructure.越野车 = true;
    }

    private static function storagePairSnapshot(targetContainerId:String):Object {
        return InventoryPanelService.execute("snapshot", {
            v:1,
            requests:[
                {containerId:"背包", offset:0, limit:50},
                {containerId:targetContainerId, offset:0,
                    limit:targetContainerId == "战备箱" ? 40 : 50}
            ]
        });
    }

    private static function autoTransferBatchWindows(targetContainerId:String):Array {
        return [
            {containerId:"背包", offset:0, limit:50, filterKey:"all"},
            {containerId:targetContainerId, offset:0,
                limit:targetContainerId == "战备箱" ? 40 : 50,
                filterKey:"all"}
        ];
    }

    private static function refsFrom(response:Object, snapshotIndex:Number, count:Number):Array {
        var refs:Array = [];
        for (var i:Number = 0; i < count; i++) {
            refs.push(refFrom(response, snapshotIndex, i));
        }
        return refs;
    }

    private static function filteredSnapshot(containerId:String, offset:Number, limit:Number, filterKey:String):Object {
        return InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [{containerId: containerId, offset: offset, limit: limit, filterKey: filterKey}]
        });
    }

    private static function structuredSnapshot(containerId:String, offset:Number, limit:Number, filterKey:String, filterSpec:Object):Object {
        return InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [{containerId: containerId, offset: offset, limit: limit, filterKey: filterKey, filterSpec: filterSpec}]
        });
    }

    private static function scopedSnapshot(containerId:String, filterKey:String,
                                            filterSpec:Object):Object {
        var request:Object = {
            containerId:containerId,
            offset:0,
            limit:50,
            filterKey:filterKey,
            scope:"equipment"
        };
        if (filterSpec != null) request.filterSpec = filterSpec;
        return InventoryPanelService.execute("snapshot", {
            v:1,
            requests:[request]
        });
    }

    private static function facetAt(nodes:Array, id:String):Object {
        for (var i:Number = 0; i < nodes.length; i++) if (String(nodes[i].id) == id) return nodes[i];
        return null;
    }

    private static function refFrom(response:Object, snapshotIndex:Number, slotIndex:Number):Object {
        var container:Object = response.snapshots[snapshotIndex];
        var slot:Object = container.slots[slotIndex];
        return {
            containerId: container.containerId,
            slot: slot.physicalSlot,
            expectedLease: slot.slotLease
        };
    }

    private static function assertTrue(condition:Boolean, message:String):Void {
        if (condition) {
            _passed++;
            trace("PASS: " + message);
        } else {
            _failed++;
            trace("FAIL: " + message);
        }
    }

    private static function installSortTestMetadata(names:Array):Object {
        var state:Object = {
            names: names,
            itemDictWasUndefined: org.flashNight.arki.item.ItemUtil.itemDataDict == undefined,
            equipmentDictWasUndefined: org.flashNight.arki.item.ItemUtil.equipmentDict == undefined,
            previous: {}
        };
        if (state.itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = {};
        if (state.equipmentDictWasUndefined) org.flashNight.arki.item.ItemUtil.equipmentDict = {};
        for (var i:Number = 0; i < names.length; i++) {
            var name:String = String(names[i]);
            state.previous[name] = org.flashNight.arki.item.ItemUtil.itemDataDict[name];
            org.flashNight.arki.item.ItemUtil.itemDataDict[name] = {
                type: "测试装备", use: "测试", price: i + 1, level: 1, id: 900000 + i
            };
        }
        return state;
    }

    private static function restoreSortTestMetadata(state:Object):Void {
        for (var i:Number = 0; i < state.names.length; i++) {
            var name:String = String(state.names[i]);
            if (state.previous[name] == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict[name];
            else org.flashNight.arki.item.ItemUtil.itemDataDict[name] = state.previous[name];
        }
        if (state.itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = undefined;
        if (state.equipmentDictWasUndefined) org.flashNight.arki.item.ItemUtil.equipmentDict = undefined;
    }

    private static function testRangeSnapshot():Void {
        resetInventories();
        _root.物品栏.背包.add(0, item("药剂", 3));
        var response:Object = snapshot(50, 10);
        assertTrue(response.success && response.snapshots.length == 2, "range snapshot 返回两个容器窗口");
        assertTrue(response.snapshots[0].slots.length == 50 && response.snapshots[1].slots.length == 10,
            "range snapshot 严格按 limit 返回");
        assertTrue(response.snapshots[0].slots[0].occupied && response.snapshots[0].slots[1].occupied == false,
            "占用槽与空槽都获得可校验投影");
        assertTrue(String(response.snapshots[0].slots[1].slotLease).length > 0,
            "空目标槽也由 AS2 铸造 lease");
    }

    private static function testStableReadLeaseAndMutationVersion():Void {
        resetInventories();
        _root.物品栏.背包.add(0, item("稳定租约物品", 3));
        var first:Object = snapshot(10, 10);
        var firstRef:Object = refFrom(first, 0, 0);
        var second:Object = snapshot(10, 10);
        var secondRef:Object = refFrom(second, 0, 0);
        assertTrue(firstRef.expectedLease == secondRef.expectedLease
                && first.snapshots[0].containerVersion == second.snapshots[0].containerVersion,
            "相同容器版本的重复纯读复用槽位 lease");
        assertTrue(InventoryPanelService.validateExternalSlotRef(firstRef, true).success,
            "后续纯读不会使先前响应中的 lease 失效");

        _root.物品栏.背包.add(1, item("容器版本推进", 1));
        var stale:Object = InventoryPanelService.validateExternalSlotRef(firstRef, true);
        assertTrue(!stale.success && stale.error == "stale_state",
            "任一真实容器写入推进版本并拒绝旧 lease");

        resetInventories();
        var equipment:Object = item("原位变化装备", {level:1, mods:[]});
        _root.物品栏.背包.add(0, equipment);
        first = snapshot(10, 10);
        firstRef = refFrom(first, 0, 0);
        equipment.value.mods.push("新插件");
        stale = InventoryPanelService.validateExternalSlotRef(firstRef, false);
        assertTrue(!stale.success && stale.error == "stale_state",
            "同一对象引用的装备原位变化也由指纹拒绝旧 lease");
    }

    private static function testFilteredSnapshot():Void {
        resetInventories();
        var itemDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.itemDataDict == undefined;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = {};
        var previousMaterial:Object = org.flashNight.arki.item.ItemUtil.itemDataDict["筛选材料"];
        var previousWeapon:Object = org.flashNight.arki.item.ItemUtil.itemDataDict["筛选武器"];
        org.flashNight.arki.item.ItemUtil.itemDataDict["筛选材料"] = {type: "收集品", use: "材料", price: 1};
        org.flashNight.arki.item.ItemUtil.itemDataDict["筛选武器"] = {type: "武器", use: "长枪", weapontype: "突击步枪",
            setId:"test_rifle", setName:"测试长枪套装", price: 2};
        for (var slot:Number = 0; slot < 51; slot++) {
            _root.物品栏.仓库.add(slot, new BaseItem("筛选材料", 1, slot + 1));
        }
        _root.物品栏.仓库.add(100, new BaseItem("筛选武器", {level: 1}, 1));

        var secondPage:Object = filteredSnapshot("仓库", 50, 50, "material");
        assertTrue(secondPage.success && secondPage.snapshots[0].filterKey == "material"
                && secondPage.snapshots[0].viewCapacity == 51
                && secondPage.snapshots[0].slots.length == 1
                && secondPage.snapshots[0].slots[0].physicalSlot == 50,
            "全容器分类筛选按匹配数量分页并保留真实 physicalSlot");
        var weapon:Object = filteredSnapshot("仓库", 0, 50, "weapon");
        assertTrue(weapon.success && weapon.snapshots[0].viewCapacity == 1
                && weapon.snapshots[0].slots[0].physicalSlot == 100,
            "分类筛选跨越未加载物理页查找匹配物品");
        var structured:Object = structuredSnapshot("仓库", 0, 50, "weapon", {
            major:"weapon", use:"长枪", subtype:"突击步枪"
        });
        var weaponFacet:Object = facetAt(structured.snapshots[0].filterFacets, "weapon");
        var longGunFacet:Object = weaponFacet == null ? null : facetAt(weaponFacet.children, "长枪");
        var rifleFacet:Object = longGunFacet == null ? null : facetAt(longGunFacet.children, "突击步枪");
        assertTrue(structured.success && structured.snapshots[0].viewCapacity == 1
                && structured.snapshots[0].filterSpec.subtype == "突击步枪"
                && structured.snapshots[0].filterItemCount == 52
                && rifleFacet != null && rifleFacet.count == 1,
            "结构化筛选由权威层匹配用途/子类并返回全容器 facet 数量");
        var setFiltered:Object = structuredSnapshot("仓库", 0, 50, "all", {branch:"set", setId:"test_rifle"});
        var setFacet:Object = facetAt(setFiltered.snapshots[0].setFacets, "test_rifle");
        assertTrue(setFiltered.success && setFiltered.snapshots[0].viewCapacity == 1
                && setFiltered.snapshots[0].slots[0].physicalSlot == 100
                && setFiltered.snapshots[0].filterSpec.setId == "test_rifle"
                && setFiltered.snapshots[0].setFilterItemCount == 1
                && setFacet != null && setFacet.label == "测试长枪套装" && setFacet.count == 1,
            "套装筛选跨物理页由权威层匹配并返回套装 facet");
        var allSets:Object = structuredSnapshot("仓库", 0, 50, "all", {branch:"set"});
        assertTrue(allSets.success && allSets.snapshots[0].viewCapacity == 1,
            "套装分支根节只显示已显式标注的物品");
        var invalidSpec:Object = structuredSnapshot("仓库", 0, 50, "weapon", {
            major:"weapon", subtype:"突击步枪"
        });
        assertTrue(!invalidSpec.success && invalidSpec.error == "unsupported_filter",
            "结构化筛选拒绝缺少用途的武器子类路径");
        var mismatchedSpec:Object = structuredSnapshot("仓库", 0, 50, "all", {major:"weapon"});
        assertTrue(!mismatchedSpec.success && mismatchedSpec.error == "unsupported_filter",
            "结构化筛选拒绝与 legacy filterKey 矛盾的路径");
        var clamped:Object = filteredSnapshot("仓库", 50, 50, "weapon");
        assertTrue(clamped.success && clamped.snapshots[0].offset == 0
                && clamped.snapshots[0].slots[0].physicalSlot == 100,
            "筛选结果缩减后把过期页码收敛到合法末页");
        var invalid:Object = filteredSnapshot("仓库", 0, 50, "unknown");
        assertTrue(!invalid.success && invalid.error == "unsupported_filter",
            "未知分类筛选在 AS2 权威层严格拒绝");

        if (previousMaterial == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict["筛选材料"];
        else org.flashNight.arki.item.ItemUtil.itemDataDict["筛选材料"] = previousMaterial;
        if (previousWeapon == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict["筛选武器"];
        else org.flashNight.arki.item.ItemUtil.itemDataDict["筛选武器"] = previousWeapon;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = undefined;
    }

    private static function testEquipmentProjectionScope():Void {
        resetInventories();
        var dictWasUndefined:Boolean =
            org.flashNight.arki.item.ItemUtil.itemDataDict == undefined;
        if (dictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = {};
        var names:Array = [
            "scope长枪", "scope护具", "scope手雷", "scope药剂",
            "scope数字伪装备", "scope材料"
        ];
        var previous:Object = {};
        for (var i:Number = 0; i < names.length; i++) {
            previous[String(names[i])] =
                org.flashNight.arki.item.ItemUtil.itemDataDict[String(names[i])];
        }
        org.flashNight.arki.item.ItemUtil.itemDataDict["scope长枪"] = {
            type:"武器", use:"长枪", weapontype:"突击步枪", price:1
        };
        org.flashNight.arki.item.ItemUtil.itemDataDict["scope护具"] = {
            type:"防具", use:"上装装备", price:1
        };
        org.flashNight.arki.item.ItemUtil.itemDataDict["scope手雷"] = {
            type:"武器", use:"手雷", price:1
        };
        org.flashNight.arki.item.ItemUtil.itemDataDict["scope药剂"] = {
            type:"消耗品", use:"药剂", price:1
        };
        org.flashNight.arki.item.ItemUtil.itemDataDict["scope数字伪装备"] = {
            type:"武器", use:"长枪", price:1
        };
        org.flashNight.arki.item.ItemUtil.itemDataDict["scope材料"] = {
            type:"材料", use:"材料", price:1
        };

        _root.物品栏.背包.add(1,
            new BaseItem("scope长枪", {level:1, mods:[]}, 1));
        _root.物品栏.背包.add(2, new BaseItem("scope手雷", 4, 1));
        _root.物品栏.背包.add(3, new BaseItem("scope药剂", 2, 1));
        _root.物品栏.背包.add(4,
            new BaseItem("scope护具", {level:1, mods:[]}, 1));
        _root.物品栏.背包.add(5,
            new BaseItem("scope数字伪装备", 3, 1));
        _root.物品栏.背包.add(6,
            new BaseItem("scope材料", {level:1}, 1));
        _root.物品栏.背包.add(7,
            new BaseItem("scope未知目录", {level:1}, 1));

        var scoped:Object = scopedSnapshot("背包", "all", null);
        var projection:Object = scoped.snapshots[0];
        var weaponFacet:Object = facetAt(projection.filterFacets, "weapon");
        var armorFacet:Object = facetAt(projection.filterFacets, "armor");
        assertTrue(scoped.success && projection.scope == "equipment"
                && projection.viewCapacity == 2
                && projection.slots.length == 2
                && projection.slots[0].physicalSlot == 1
                && projection.slots[1].physicalSlot == 4,
            "equipment scope 只按 catalog 武器/防具 + object value 投影并保持物理顺序");
        assertTrue(projection.filterItemCount == 2
                && weaponFacet != null && weaponFacet.count == 1
                && armorFacet != null && armorFacet.count == 1
                && facetAt(projection.filterFacets, "consumable") == null
                && facetAt(projection.filterFacets, "material") == null,
            "equipment scope 的 facets 与计数不泄漏非装备 taxonomy");

        var weaponOnly:Object = scopedSnapshot("背包", "weapon", {
            branch:"category", major:"weapon"
        });
        assertTrue(weaponOnly.success
                && weaponOnly.snapshots[0].scope == "equipment"
                && weaponOnly.snapshots[0].viewCapacity == 1
                && weaponOnly.snapshots[0].slots[0].physicalSlot == 1,
            "equipment scope 先收紧 authority，再与既有 taxonomy filter 合取");

        var invalidContainer:Object =
            scopedSnapshot("仓库", "all", null);
        var unknownScope:Object = InventoryPanelService.execute("snapshot", {
            v:1,
            requests:[{
                containerId:"背包", offset:0, limit:50,
                filterKey:"all", scope:"developer"
            }]
        });
        assertTrue(!invalidContainer.success
                && invalidContainer.error == "unsupported_scope"
                && !unknownScope.success
                && unknownScope.error == "unsupported_scope",
            "equipment scope 仅允许背包且拒绝未知 scope");

        for (i = 0; i < names.length; i++) {
            var name:String = String(names[i]);
            if (previous[name] == undefined) {
                delete org.flashNight.arki.item.ItemUtil.itemDataDict[name];
            } else {
                org.flashNight.arki.item.ItemUtil.itemDataDict[name] =
                    previous[name];
            }
        }
        if (dictWasUndefined) {
            org.flashNight.arki.item.ItemUtil.itemDataDict = undefined;
        }
    }

    private static function testArrayInventoryMutationRevision():Void {
        var inventory:ArrayInventory = new ArrayInventory(null, 8);
        var holder:MovieClip = _root.createEmptyMovieClip("__inventoryRevisionTest", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        var addEventVersion:Number = -1;
        var valueEventVersion:Number = -1;
        var removeEventVersion:Number = -1;
        inventory.setDispatcher(dispatcher);
        dispatcher.subscribe("ItemAdded", function():Void {
            addEventVersion = inventory.getMutationRevision();
        });
        dispatcher.subscribe("ItemValueChanged", function():Void {
            valueEventVersion = inventory.getMutationRevision();
        });
        dispatcher.subscribe("ItemRemoved", function():Void {
            removeEventVersion = inventory.getMutationRevision();
        });
        var v0:Number = inventory.getMutationRevision();
        var added:Boolean = inventory.add(0, item("版本堆叠", 2));
        var v1:Number = inventory.getMutationRevision();
        inventory.addValue("0", 1);
        var v2:Number = inventory.getMutationRevision();
        inventory.addValue("0", -3);
        var v3:Number = inventory.getMutationRevision();
        var zeroRemoveEventVersion:Number = removeEventVersion;
        var readded:Boolean = inventory.add(0, item("版本重建", 1));
        var v4:Number = inventory.getMutationRevision();
        var wrote:Boolean = inventory.transactionWrite(1, item("事务单槽", 1));
        var v5:Number = inventory.getMutationRevision();
        var replacedAll:Boolean = inventory.transactionReplaceAll([
            item("整表一", 1), item("整表二", 2)
        ]);
        var v6:Number = inventory.getMutationRevision();
        var replacedPrefix:Boolean = inventory.transactionReplacePrefix([
            item("前缀一", 1)
        ], 4);
        var v7:Number = inventory.getMutationRevision();
        inventory.remove(0);
        var v8:Number = inventory.getMutationRevision();
        inventory.setItems({});
        var v9:Number = inventory.getMutationRevision();
        var failed:Boolean = inventory.add(99, item("越界写入", 1));
        var v10:Number = inventory.getMutationRevision();

        assertTrue(added && readded && wrote && replacedAll && replacedPrefix && !failed
                && v1 > v0 && v2 > v1 && v3 > v2 && v4 > v3 && v5 > v4
                && v6 > v5 && v7 > v6 && v8 > v7 && v9 > v8 && v10 == v9
                && addEventVersion == v4 && valueEventVersion == v2
                && zeroRemoveEventVersion == v3,
            "ArrayInventory 全部成功写入口在同步事件前推进单调版本，失败写入保持版本不变");
        inventory.setDispatcher(null);
        holder.removeMovieClip();
    }

    private static function testFacetCacheInvalidation():Void {
        resetInventories();
        var itemDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.itemDataDict == undefined;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = {};
        var name:String = "Facet缓存移动武器";
        var previous:Object = org.flashNight.arki.item.ItemUtil.itemDataDict[name];
        org.flashNight.arki.item.ItemUtil.itemDataDict[name] = {
            type:"武器", use:"长枪", weapontype:"突击步枪", price:1
        };
        _root.物品栏.背包.add(0, new BaseItem(name, {level:1}, 1));

        // 首次 snapshot 同时建立背包与仓库 facet 缓存，再走正常跨容器写路径。
        var before:Object = snapshot(50, 50);
        var moved:Object = InventoryPanelService.execute("move", {
            v:1,
            source:refFrom(before, 0, 0),
            target:refFrom(before, 1, 0)
        });
        var backpackSnapshot:Object = moved.success ? moved.snapshots[0] : null;
        var warehouseAfterMove:Object = moved.success ? moved.snapshots[1] : null;
        var warehouseWeapon:Object = warehouseAfterMove == null
            ? null : facetAt(warehouseAfterMove.filterFacets, "weapon");
        assertTrue(moved.success
                && backpackSnapshot.filterItemCount == 0
                && facetAt(backpackSnapshot.filterFacets, "weapon") == null
                && warehouseAfterMove.filterItemCount == 1
                && warehouseWeapon != null && warehouseWeapon.count == 1,
            "跨容器写入后 facet 缓存立即反映来源移除与目标新增");

        // 普通游戏逻辑可直接走 ArrayInventory.add/remove，不会调用 inventory-domain 失效入口。
        var versionBeforeRemove:Number = _root.物品栏.仓库.getMutationRevision();
        _root.物品栏.仓库.remove(0);
        var afterExternalRemove:Object = warehouseSnapshot(0, 50);
        assertTrue(afterExternalRemove.success
                && _root.物品栏.仓库.getMutationRevision() > versionBeforeRemove
                && afterExternalRemove.snapshots[0].filterItemCount == 0
                && facetAt(afterExternalRemove.snapshots[0].filterFacets, "weapon") == null,
            "外部容器写入通过单调版本自动击穿 facet 缓存");

        if (previous == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict[name];
        else org.flashNight.arki.item.ItemUtil.itemDataDict[name] = previous;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = undefined;
    }

    private static function testTooltipLeaseAndInstance():Void {
        resetInventories();
        var name:String = "GateA3库存注释";
        var itemDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.itemDataDict == undefined;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = {};
        var previousMeta:Object = org.flashNight.arki.item.ItemUtil.itemDataDict[name];
        org.flashNight.arki.item.ItemUtil.itemDataDict[name] = {
            name: name, displayname: name, type: "收集品", use: "材料", price: 1,
            description: "<FONT COLOR=\"#FF00FF\">库存实例注释测试</FONT>"
        };
        var owned:BaseItem = new BaseItem(name, 3, 1);
        _root.物品栏.背包.add(0, owned);
        var response:Object = snapshot(10, 10);
        var source:Object = refFrom(response, 0, 0);
        var tooltip:Object = InventoryPanelService.execute("tooltip", {v: 1, source: source});
        assertTrue(tooltip.success && tooltip.itemName == name
            && tooltip.introHTML != undefined && tooltip.descHTML != undefined
            && tooltip.descHTML.indexOf("&quot;") < 0
            && tooltip.descHTML.indexOf("COLOR=\"#FF00FF\"") >= 0,
            "tooltip 按 lease 读取真实库存实例并返回 Web 可解析的富文本");

        _root.物品栏.背包.remove(0);
        _root.物品栏.背包.add(0, new BaseItem(name, 1, 2));
        var stale:Object = InventoryPanelService.execute("tooltip", {v: 1, source: source});
        assertTrue(!stale.success && stale.error == "stale_state",
            "tooltip 不接受已替换 occupant 的旧 lease");

        if (previousMeta == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict[name];
        else org.flashNight.arki.item.ItemUtil.itemDataDict[name] = previousMeta;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = undefined;
    }

    private static function testItemUtilBalanceExtraction():Void {
        var previous:Object = {
            itemDataDict:ItemUtil.itemDataDict,
            balanceDataDict:ItemUtil.balanceDataDict,
            itemDataArray:ItemUtil.itemDataArray,
            itemNamesByID:ItemUtil.itemNamesByID,
            maxID:ItemUtil.maxID,
            equipmentDict:ItemUtil.equipmentDict,
            materialDict:ItemUtil.materialDict,
            informationMaxValueDict:ItemUtil.informationMaxValueDict,
            multiTierDict:ItemUtil.multiTierDict,
            itemSetDict:ItemUtil.itemSetDict,
            itemSetByItem:ItemUtil.itemSetByItem,
            itemSetConfigDict:ItemUtil.itemSetConfigDict
        };
        var previousRoot:Object = {
            itemData:_root.物品属性列表,
            itemArray:_root.物品属性数组,
            itemSets:_root.物品套装索引,
            itemSetConfigs:_root.物品套装配置索引,
            names:_root.id物品名对应表,
            maxId:_root.物品最大id,
            count:_root.物品总数
        };
        var embeddedBalance:Object = {
            formulaFamily:"weapon", schemaVersion:1, workbookVersion:1,
            profiles:{data:{status:"unresolved"}}
        };
        var combinedData:Object = {
            only:{
                name:"balance提取测试物品", type:"消耗品", use:"药剂",
                data:{level:1}, balance:embeddedBalance
            }
        };

        ItemUtil.loadItemData(combinedData);
        var raw:Object = ItemUtil.getRawItemData("balance提取测试物品");
        var clone:Object = ItemUtil.getItemData("balance提取测试物品");
        assertTrue(raw.balance == undefined && clone.balance == undefined
                && ItemUtil.getRawBalanceData("balance提取测试物品") === embeddedBalance
                && ItemUtil.getRawBalanceData(1) === embeddedBalance,
            "ItemUtil 装入时独立提取 balance，常规 raw/clone 不再携带审计树");

        ItemUtil.itemDataDict = previous.itemDataDict;
        ItemUtil.balanceDataDict = previous.balanceDataDict;
        ItemUtil.itemDataArray = previous.itemDataArray;
        ItemUtil.itemNamesByID = previous.itemNamesByID;
        ItemUtil.maxID = previous.maxID;
        ItemUtil.equipmentDict = previous.equipmentDict;
        ItemUtil.materialDict = previous.materialDict;
        ItemUtil.informationMaxValueDict = previous.informationMaxValueDict;
        ItemUtil.multiTierDict = previous.multiTierDict;
        ItemUtil.itemSetDict = previous.itemSetDict;
        ItemUtil.itemSetByItem = previous.itemSetByItem;
        ItemUtil.itemSetConfigDict = previous.itemSetConfigDict;
        _root.物品属性列表 = previousRoot.itemData;
        _root.物品属性数组 = previousRoot.itemArray;
        _root.物品套装索引 = previousRoot.itemSets;
        _root.物品套装配置索引 = previousRoot.itemSetConfigs;
        _root.id物品名对应表 = previousRoot.names;
        _root.物品最大id = previousRoot.maxId;
        _root.物品总数 = previousRoot.count;
    }

    private static function testPresentationProjection():Void {
        resetInventories();
        var name:String = "GateA3槽位展示装备";
        var itemDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.itemDataDict == undefined;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = {};
        var balanceDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.balanceDataDict == undefined;
        if (balanceDictWasUndefined) org.flashNight.arki.item.ItemUtil.balanceDataDict = {};
        var previousMeta:Object = org.flashNight.arki.item.ItemUtil.itemDataDict[name];
        var previousModAMeta:Object = org.flashNight.arki.item.ItemUtil.itemDataDict["插件A"];
        var previousModBMeta:Object = org.flashNight.arki.item.ItemUtil.itemDataDict["插件B"];
        var previousModCMeta:Object = org.flashNight.arki.item.ItemUtil.itemDataDict["插件C"];
        var previousBalance:Object = org.flashNight.arki.item.ItemUtil.balanceDataDict[name];
        var previousModDict:Object = org.flashNight.arki.item.EquipmentUtil.modDict;
        org.flashNight.arki.item.ItemUtil.itemDataDict[name] = {
            name: name, displayname: "GateA3展示名称", type: "武器", use: "手枪", price: 1,
            data: {
                level:1, power:100, interval:400, capacity:8, weight:1, impact:2, modslot:3,
                bullet:"普通子弹", clipname:"手枪通用弹药", split:1, singleshoot:true
            },
            data_2: {level:2}
        };
        org.flashNight.arki.item.ItemUtil.itemDataDict["插件A"] = {
            name:"插件A", displayname:"插件A展示名", icon:"插件A专用图标",
            type:"收集品", use:"装备插件", price:1
        };
        org.flashNight.arki.item.ItemUtil.itemDataDict["插件B"] = {
            name:"插件B", displayname:" \t ", icon:" Undefined ",
            type:"收集品", use:"装备插件", price:1
        };
        org.flashNight.arki.item.ItemUtil.itemDataDict["插件C"] = {
            name:"插件C", displayname:17, icon:{legacy:"bad"},
            type:"收集品", use:"装备插件", price:1
        };
        org.flashNight.arki.item.ItemUtil.balanceDataDict[name] = {
            formulaFamily:"weapon", schemaVersion:1, workbookVersion:1,
            profiles:{
                data:{
                    dualWield:2, pierce:1, damageType:1, shotgun:1, magPrice:200,
                    weightLayers:0, category:1, formula:1, status:"confirmed", displayEligible:true,
                    inputDigest:"fnv1a32:ed41885c", auditRef:"weapon:GateA3槽位展示装备:data"
                },
                data_2:{
                    dualWield:2, pierce:1, damageType:1, shotgun:1, magPrice:200,
                    weightLayers:1, category:1, formula:1, status:"confirmed", displayEligible:true,
                    inputDigest:"fnv1a32:8dc680d9", auditRef:"weapon:GateA3槽位展示装备:data_2"
                }
            }
        };
        org.flashNight.arki.item.EquipmentUtil.modDict = {
            插件A: {
                modGrade: "medium", uiGradeLabel: "中等", uiGradeColor: "#996600",
                catalogScope: "firearm", uiScopeLabel: "枪械", tag: "瞄具",
                uiRole: "precision", uiRoleLabel: "精准与操控", uiSymbol: "triangle-outline"
            },
            插件B: {
                modGrade: "special", uiGradeLabel: "特殊", uiGradeColor: "#FFFF00",
                uiRole: "mechanism", uiRoleLabel: "特殊机制", uiSymbol: "star-solid"
            },
            插件C: {
                modGrade: "unknown", uiGradeLabel: "未知档级", uiGradeColor: "#58636E",
                uiRole: "utility", uiRoleLabel: "结构与功能", uiSymbol: "diamond-outline"
            }
        };
        var equipment:Object = {
            name: name,
            value: {level: org.flashNight.arki.item.EquipmentUtil.getMaxLevel(), tier: "二阶", mods: ["插件A", "插件B", "插件C"]},
            lastUpdate: 1,
            getData: function():Object {
                return {name: name, displayname: "GateA3展示名称", type: "武器", use: "手枪", icon: name, data: {modslot: 3}};
            }
        };
        _root.物品栏.背包.add(0, equipment);
        _root.物品栏.背包.add(1, item("插件A", 12345));
        _root.物品栏.背包.add(2, {
            name:name, value:{level:1, tier:"狱火", mods:[]}, lastUpdate:1,
            getData:function():Object { return {name:name, type:"武器", use:"手枪", data:{modslot:3}}; }
        });
        _root.物品栏.背包.add(3, {
            name:name, value:{level:1, tier:"不存在进阶", mods:[]}, lastUpdate:1,
            getData:function():Object { return {name:name, type:"武器", use:"手枪", data:{modslot:3}}; }
        });
        _root.物品栏.背包.add(4, {
            name:name, value:{level:1, mods:[]}, lastUpdate:1,
            getData:function():Object { return {name:name, type:"武器", use:"手枪", data:{modslot:3}}; }
        });
        var legacyIdentityName:String = "GateA3旧标识物品";
        _root.物品栏.背包.add(5, {
            name:legacyIdentityName, value:2, lastUpdate:1,
            getData:function():Object {
                return {
                    name:legacyIdentityName,
                    displayname:" \t ",
                    icon:" Undefined ",
                    type:"收集品",
                    use:"材料"
                };
            }
        });
        var wrongTypeIdentityName:String = "GateA3错型标识物品";
        _root.物品栏.背包.add(6, {
            name:wrongTypeIdentityName, value:1, lastUpdate:1,
            getData:function():Object {
                return {
                    name:wrongTypeIdentityName,
                    displayname:17,
                    icon:{legacy:"bad"},
                    type:"收集品",
                    use:"材料"
                };
            }
        });
        var response:Object = snapshot(10, 10);
        var equipmentProjection:Object = response.snapshots[0].slots[0].item;
        var stackProjection:Object = response.snapshots[0].slots[1].item;
        assertTrue(equipmentProjection.isMaxEnhancement
            && equipmentProjection.maxEnhancementLevel == org.flashNight.arki.item.EquipmentUtil.getMaxLevel()
            && equipmentProjection.tierSlotAvailable && equipmentProjection.tierSlotUsed
            && equipmentProjection.modSlotCapacity == 3 && equipmentProjection.modSlotUsed == 3
            && equipmentProjection.modSlots.length == 3
            && equipmentProjection.name == name && equipmentProjection.displayName == "GateA3展示名称"
            && equipmentProjection.modSlots[0].grade == "medium"
            && equipmentProjection.modSlots[0].symbol == "triangle-outline"
            && equipmentProjection.modSlots[1].gradeColor == "#FFFF00"
            && equipmentProjection.modSlots[1].symbol == "star-solid"
            && equipmentProjection.balanceSummary != undefined
            && equipmentProjection.balanceSummary.state == "confirmed"
            && equipmentProjection.balanceSummary.weightLayers == 1
            && equipmentProjection.balanceSummary.formula == 1
            && equipmentProjection.balanceSummary.level == 2,
            "库存进阶实例严格选择对应 balance profile，并保留展示与插件投影");
        assertTrue(equipmentProjection.modSlots[0].name == "插件A"
                && equipmentProjection.modSlots[0].displayName == "插件A展示名"
                && equipmentProjection.modSlots[0].icon == "插件A专用图标"
                && equipmentProjection.modSlots[0].name != equipmentProjection.modSlots[0].displayName
                && equipmentProjection.modSlots[0].name != equipmentProjection.modSlots[0].icon
                && equipmentProjection.modSlots[0].displayName != equipmentProjection.modSlots[0].icon,
            "插件槽投影保持内部名、显示名、图标名三者独立");
        assertTrue(equipmentProjection.modSlots[1].name == "插件B"
                && equipmentProjection.modSlots[1].displayName == "插件B"
                && equipmentProjection.modSlots[1].icon == "插件B"
                && equipmentProjection.modSlots[2].displayName == "插件C"
                && equipmentProjection.modSlots[2].icon == "插件C",
            "插件槽旧数据适配在空白、wrapped-case undefined 与错型字段时仅在 AS2 回退内部名");
        assertTrue(stackProjection.itemKind == "stack" && stackProjection.quantity == 12345
            && !stackProjection.isMaxEnhancement && stackProjection.modSlotCapacity == 0
            && stackProjection.modMeta.grade == "medium"
            && stackProjection.modMeta.name == "插件A"
            && stackProjection.modMeta.displayName == "插件A展示名"
            && stackProjection.modMeta.icon == "插件A专用图标"
            && stackProjection.modMeta.scope == "firearm"
            && stackProjection.modMeta.role == "precision",
            "插件材料投影读取数量与 mod 元数据");
        assertTrue(response.snapshots[0].slots[2].item.balanceSummary == undefined,
            "映射到未配置变体时隐藏，不回退 data");
        assertTrue(response.snapshots[0].slots[3].item.balanceSummary == undefined,
            "非空且无法映射的进阶严格 fail-closed");
        assertTrue(response.snapshots[0].slots[4].item.balanceSummary != undefined
                && response.snapshots[0].slots[4].item.balanceSummary.level == 1
                && response.snapshots[0].slots[4].item.balanceSummary.weightLayers == 0,
            "无进阶库存实例选择 data profile");
        assertTrue(response.snapshots[0].slots[5].item.name == legacyIdentityName
                && response.snapshots[0].slots[5].item.displayName == legacyIdentityName
                && response.snapshots[0].slots[5].item.icon == legacyIdentityName
                && response.snapshots[0].slots[6].item.name == wrongTypeIdentityName
                && response.snapshots[0].slots[6].item.displayName == wrongTypeIdentityName
                && response.snapshots[0].slots[6].item.icon == wrongTypeIdentityName,
            "顶层物品展示与图标在空白、wrapped-case undefined 及错型时只由 AS2 适配为内部名");

        if (previousMeta == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict[name];
        else org.flashNight.arki.item.ItemUtil.itemDataDict[name] = previousMeta;
        if (previousModAMeta == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict["插件A"];
        else org.flashNight.arki.item.ItemUtil.itemDataDict["插件A"] = previousModAMeta;
        if (previousModBMeta == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict["插件B"];
        else org.flashNight.arki.item.ItemUtil.itemDataDict["插件B"] = previousModBMeta;
        if (previousModCMeta == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict["插件C"];
        else org.flashNight.arki.item.ItemUtil.itemDataDict["插件C"] = previousModCMeta;
        if (previousBalance == undefined) delete org.flashNight.arki.item.ItemUtil.balanceDataDict[name];
        else org.flashNight.arki.item.ItemUtil.balanceDataDict[name] = previousBalance;
        org.flashNight.arki.item.EquipmentUtil.modDict = previousModDict;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = undefined;
        if (balanceDictWasUndefined) org.flashNight.arki.item.ItemUtil.balanceDataDict = undefined;
    }

    private static function testBalanceSummaryProjection():Void {
        var profile:Object = {
            dualWield:2, pierce:1, damageType:1, shotgun:1, magPrice:200,
            weightLayers:0, category:1, formula:1, status:"confirmed", displayEligible:true,
            inputDigest:"fnv1a32:96ca5e46", auditRef:"weapon:测试手枪:data"
        };
        var balance:Object = {
            schemaVersion:1, formulaFamily:"weapon", workbookVersion:1,
            profiles:{data:profile}
        };
        var raw:Object = {
            name:"测试手枪", type:"武器", use:"手枪",
            data:{
                level:1, power:100, interval:400, capacity:8, weight:1, impact:2,
                bullet:"普通子弹", clipname:"手枪通用弹药", split:1, singleshoot:true
            }
        };

        var summary:Object = InventoryPanelService.buildBalanceSummary(raw, balance, "data");
        var wire:String = new LiteJSON().stringify(summary);
        assertTrue(summary != null && summary.state == "confirmed"
            && summary.weightLayers == 0 && summary.formula == 1 && summary.level == 1,
            "digest 匹配的 weapon-v1 data profile 生成最小摘要");
        assertTrue(summary.auditRef == undefined && summary.profileKey == undefined
            && summary.inputDigest == undefined && summary.workbookVersion == undefined
            && summary.workbookSha256 == undefined
            && wire.indexOf("workbookVersion") < 0 && wire.indexOf("workbookSha256") < 0
            && wire.indexOf("WBR-") < 0
            && wire.indexOf("SHA256") < 0 && wire.indexOf("auditRef") < 0,
            "balance 摘要不泄漏 profile、auditRef、digest 或工作簿信息");
        var frozenVectorRaw:Object = {
            name:"测试手枪", type:"武器", use:"手枪",
            data:{
                level:10, power:135, interval:110, capacity:30, weight:4, impact:20,
                bullet:"普通子弹", clipname:"手枪弹药", split:1, singleshoot:true
            }
        };
        var frozenVectorBalance:Object = {
            schemaVersion:1, formulaFamily:"weapon", workbookVersion:1,
            profiles:{data:{
                dualWield:2, pierce:1, damageType:1, shotgun:1, magPrice:200,
                weightLayers:0, category:1, formula:1, status:"confirmed", displayEligible:true,
                inputDigest:"fnv1a32:4bbce563", auditRef:"weapon:测试手枪:data"
            }}
        };
        var frozenVectorSummary:Object = InventoryPanelService.buildBalanceSummary(
            frozenVectorRaw, frozenVectorBalance, "data");
        assertTrue(frozenVectorSummary != null && frozenVectorSummary.level == 10,
            "AS2 通过工具侧冻结的 weapon-v1 跨栈 digest vector fnv1a32:4bbce563");
        raw.balance = balance;
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, null, "data") == null,
            "运行时不读取 rawItemData 内嵌 balance fallback");
        delete raw.balance;

        delete balance.workbookVersion;
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "容器缺少 workbookVersion 时直接省略投影");
        balance.workbookVersion = 2;
        var rejectsFutureWorkbook:Boolean = InventoryPanelService.buildBalanceSummary(
            raw, balance, "data") == null;
        balance.workbookVersion = "1";
        var rejectsStringWorkbook:Boolean = InventoryPanelService.buildBalanceSummary(
            raw, balance, "data") == null;
        balance.workbookVersion = true;
        var rejectsBooleanWorkbook:Boolean = InventoryPanelService.buildBalanceSummary(
            raw, balance, "data") == null;
        assertTrue(rejectsFutureWorkbook && rejectsStringWorkbook && rejectsBooleanWorkbook,
            "未实现版本、字符串1与布尔 true 都不得冒充数字 workbookVersion=1");
        balance.workbookVersion = 1;
        balance.workbookSha256 = "BAC3D341DB2B2BF966C3D473ED4793725BAF0B68BE01BA0D2804A76D6DCB840A";
        var rejectsLegacyWorkbookSha:Boolean = InventoryPanelService.buildBalanceSummary(
            raw, balance, "data") == null;
        delete balance.workbookSha256;
        var acceptsCurrentWorkbook:Boolean = InventoryPanelService.buildBalanceSummary(
            raw, balance, "data") != null;
        assertTrue(rejectsLegacyWorkbookSha && acceptsCurrentWorkbook,
            "旧 workbookSha256 按未知字段拒绝，只有数字 workbookVersion=1 可投影");
        var itemName:String = raw.name;
        delete raw.name;
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "digest 身份缺少 itemName 时 fail-closed");
        raw.name = itemName;

        delete raw.data.impact;
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "十四项数字输入不完整时 fail-closed");
        raw.data.impact = 2;
        raw.data.level = "1";
        summary = InventoryPanelService.buildBalanceSummary(raw, balance, "data");
        assertTrue(summary != null && summary.level == 1,
            "数字字符串按 String(Number(v)) 与工具产生相同 canonical 值");
        raw.data.level = 1;

        raw.data.power = 101;
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "data 公式输入变化后旧 inputDigest 立即失效");
        raw.data.power = 100;
        raw.data.bullet = "异常子弹";
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "bullet 等机制输入漂移后旧 inputDigest 立即失效");
        raw.data.bullet = "普通子弹";
        profile.weightLayers = 1;
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "profile 公式输入变化后旧 inputDigest 立即失效");
        profile.weightLayers = 0;

        profile.formula = 2;
        profile.inputDigest = "fnv1a32:95ca5cb3";
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "即使 digest 与输入一致，未实现的 formula=2 仍被严格 v1 门拒绝");
        profile.formula = true;
        profile.inputDigest = "fnv1a32:96ca5e46";
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "布尔 true 不得借 Number(true)=1 冒充 formula=1");
        profile.formula = 1;

        raw.data_fire = {level:2};
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "任一实际 data_* 缺少 profile 时，基础 data 也不得显示绿色");
        delete raw.data_fire;
        balance.profiles.data_fire = profile;
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "balance 多出无实际 data_* 来源的 profile 时整容器 fail-closed");
        delete balance.profiles.data_fire;

        balance.dualWield = 2;
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "旧平铺公式字段混入 v1 容器时不得被忽略");
        delete balance.dualWield;
        balance.audit = {ruleRefs:[]};
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "审计结构混入 compact 容器时不得被忽略");
        delete balance.audit;
        profile.rationale = "旧自由文本";
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "旧 rationale 混入 compact profile 时不得被忽略");
        delete profile.rationale;
        profile.sourceDigest = "sha256:ledger-only";
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "仅属外部台账的 sourceDigest 混入 runtime profile 时不得被忽略");
        delete profile.sourceDigest;

        delete profile.displayEligible;
        balance.displayEligible = true;
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "只接受 profile 内的 displayEligible，不信任容器同名标志");
        profile.displayEligible = true;
        delete balance.displayEligible;

        var baseData:Object = raw.data;
        raw.data = [baseData];
        balance.profiles.data = [profile];
        summary = InventoryPanelService.buildBalanceSummary(raw, [balance], "data");
        assertTrue(summary != null && summary.state == "confirmed",
            "XML 单元素 data/balance/profile 数组形状仍保持唯一语义");
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, [balance, balance], "data") == null,
            "多个 balance 容器因歧义 fail-closed");
        balance.profiles.data = [profile, profile];
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "同键多个 profile 因歧义 fail-closed");
        balance.profiles.data = profile;
        raw.data = [baseData, baseData];
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "多个基础 data 节点因公式输入歧义 fail-closed");

        raw.data = baseData;
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data_fire") == null,
            "选中 profile 缺失时不回退 data");
        profile.status = "unresolved";
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "非 confirmed profile 不生成绿色摘要");
        profile.status = "confirmed";
        var auditRef:String = profile.auditRef;
        profile.auditRef = "";
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "auditRef 缺失时不生成摘要");
        profile.auditRef = auditRef;
        delete balance.formulaFamily;
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "缺少 weapon formulaFamily 时直接省略投影");
        balance.formulaFamily = "armor";
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "非 weapon formulaFamily 不生成武器摘要");
        balance.formulaFamily = "weapon";
        delete balance.schemaVersion;
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "缺少严格 v1 schema 标记时直接省略投影");
        balance.schemaVersion = 2;
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "未上线旧 v2 平铺记录不兼容、不生成摘要");
        balance.schemaVersion = true;
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "布尔 true 不得借 Number(true)=1 冒充 schemaVersion=1");
        balance.schemaVersion = 1;
        raw.type = "防具";
        assertTrue(InventoryPanelService.buildBalanceSummary(raw, balance, "data") == null,
            "非武器原始记录不生成 balance 摘要");
    }

    private static function testSourceAndTargetStale():Void {
        resetInventories();
        _root.物品栏.背包.add(0, item("药剂", 3));
        var response:Object = snapshot(10, 10);
        var source:Object = refFrom(response, 0, 0);
        var target:Object = refFrom(response, 1, 0);
        _root.物品栏.背包.remove(0);
        _root.物品栏.背包.add(0, item("另一物品", 1));
        var staleSource:Object = InventoryPanelService.execute("move", {v: 1, source: source, target: target});
        assertTrue(!staleSource.success && staleSource.error == "stale_state", "source occupant 被替换后拒绝旧 lease");

        resetInventories();
        _root.物品栏.背包.add(0, item("药剂", 3));
        response = snapshot(10, 10);
        source = refFrom(response, 0, 0);
        target = refFrom(response, 1, 0);
        _root.物品栏.仓库.add(0, item("抢占目标", 1));
        var staleTarget:Object = InventoryPanelService.execute("move", {v: 1, source: source, target: target});
        assertTrue(!staleTarget.success && staleTarget.error == "stale_state", "空 target 变 occupied 后拒绝旧 lease");
    }

    private static function testMergeCountStale():Void {
        resetInventories();
        _root.物品栏.背包.add(0, item("药剂", 3));
        _root.物品栏.仓库.add(0, item("药剂", 4));
        var response:Object = snapshot(10, 10);
        var source:Object = refFrom(response, 0, 0);
        var target:Object = refFrom(response, 1, 0);
        _root.物品栏.仓库.addValue("0", 1);
        var result:Object = InventoryPanelService.execute("merge", {v: 1, source: source, target: target});
        assertTrue(!result.success && result.error == "stale_state", "merge 目标数量变化后双端 count lease 拒绝");
    }

    private static function testDomainReject():Void {
        resetInventories();
        var result:Object = InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [{containerId: "未开放容器", offset: 0, limit: 10}]
        });
        assertTrue(!result.success && result.error == "unsupported_container", "AS2 容器白名单最终拒绝未知领域");
    }

    private static function testBattleboxAccessPolicy():Void {
        resetInventories();
        var result:Object = battleboxSnapshot(0, 40);
        assertTrue(result.success && result.snapshots[0].capacity == 400
                && result.snapshots[0].accessibleCapacity == 0
                && result.snapshots[0].pageSizeHint == 40
                && result.snapshots[0].locked && result.snapshots[0].slots.length == 0,
            "未解锁战备箱保留物理容量但返回零可访问容量与锁定快照");

        _root.主线任务进度 = 14;
        assertTrue(InventoryPanelService.getAccessibleCapacity("战备箱") == 40,
            "主线越过初始门槛后开放战备箱第一页");
        _root.task_chains_progress.挑战 = 3;
        assertTrue(InventoryPanelService.getAccessibleCapacity("战备箱") == 120,
            "挑战进度最多追加两页战备箱容量");
        _root.主线任务进度 = 78;
        assertTrue(InventoryPanelService.getAccessibleCapacity("战备箱") == 200,
            "后期主线追加两页战备箱容量");
        _root.基建系统.infrastructure.越野车 = true;
        assertTrue(InventoryPanelService.getAccessibleCapacity("战备箱") == 240,
            "越野车基建追加最终一页且不暴露存档保留槽位");

        result = battleboxSnapshot(240, 40);
        assertTrue(!result.success && result.error == "slot_locked",
            "range snapshot 拒绝越过剧情可访问容量的窗口");

        _root.主线任务进度 = 14;
        _root.task_chains_progress.挑战 = 0;
        _root.基建系统.infrastructure.越野车 = false;
        result = InventoryPanelService.execute("move", {
            v: 1,
            source: {containerId: "战备箱", slot: 40, expectedLease: "fake"},
            target: {containerId: "背包", slot: 0, expectedLease: "fake"}
        });
        assertTrue(!result.success && result.error == "slot_locked",
            "写操作在 lease 校验前拒绝战备箱未解锁槽位");
    }

    private static function testBattleboxTransfers():Void {
        resetInventories();
        _root.主线任务进度 = 78;
        _root.task_chains_progress.挑战 = 3;
        _root.基建系统.infrastructure.越野车 = true;
        var moving:Object = item("战备物资", 2);
        _root.物品栏.背包.add(0, moving);
        var response:Object = InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [
                {containerId: "背包", offset: 0, limit: 50},
                {containerId: "战备箱", offset: 0, limit: 40}
            ]
        });
        var result:Object = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 1, 0)
        });
        assertTrue(result.success && _root.物品栏.战备箱.getItem("0") === moving
                && result.snapshots[0].pageSizeHint == 50
                && result.snapshots[1].pageSizeHint == 40
                && result.snapshots[1].slots.length == 40,
            "背包→战备箱 whole-slot move 返回两端各自的权威页大小");

        result = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(result, 1, 0), target: refFrom(result, 0, 1)
        });
        assertTrue(result.success && _root.物品栏.背包.getItem("1") === moving
                && _root.物品栏.战备箱.getItem("0") == null,
            "战备箱→背包反向移动复用同一事务协议");
    }

    private static function testAutoTransferAuthorityQueueAndFailure():Void {
        resetInventories();
        var firstSource:Object = item("快速材料", 3);
        var secondSource:Object = item("快速装备", {level: 2});
        _root.物品栏.背包.add(0, firstSource);
        _root.物品栏.背包.add(1, secondSource);
        _root.物品栏.仓库.add(100, item("快速材料", 4));
        var response:Object = snapshot(10, 10);
        var windows:Array = [
            {containerId: "背包", offset: 0, limit: 10, filterKey: "all"},
            {containerId: "仓库", offset: 0, limit: 10, filterKey: "all"}
        ];
        var result:Object = InventoryPanelService.execute("autoTransfer", {
            v: 1,
            source: refFrom(response, 0, 0),
            targetContainerId: "仓库",
            policy: "mergeThenEmpty",
            windows: windows
        });
        assertTrue(result.success && result.operation == "merge"
                && result.destination.containerId == "仓库" && result.destination.slot == 100
                && _root.物品栏.仓库.getItem("100").value == 7,
            "autoTransfer 跨未加载页优先合并同名堆叠");
        assertTrue(result.snapshots[1].offset == 0 && result.snapshots[1].slots[0].physicalSlot == 0,
            "autoTransfer 按 Web 原窗口重铸 lease 且不跳到真实落位页");

        result = InventoryPanelService.execute("autoTransfer", {
            v: 1,
            source: refFrom(result, 0, 1),
            targetContainerId: "仓库",
            policy: "mergeThenEmpty",
            windows: windows
        });
        assertTrue(result.success && result.operation == "move" && result.destination.slot == 0
                && _root.物品栏.仓库.getItem("0") === secondSource
                && _root.物品栏.仓库.getItem("100").value == 7,
            "连续快速转移使用上一回包新 lease，并只占首个空槽不交换其他物品");

        response = snapshot(10, 10);
        var badPolicy:Object = InventoryPanelService.execute("autoTransfer", {
            v: 1,
            source: refFrom(response, 1, 0),
            targetContainerId: "背包",
            policy: "swapThenEmpty",
            windows: windows
        });
        assertTrue(!badPolicy.success && badPolicy.error == "unsupported_policy",
            "autoTransfer 拒绝可诱发自动交换的未知策略");
        var badPair:Object = InventoryPanelService.execute("autoTransfer", {
            v: 1,
            source: refFrom(response, 1, 0),
            targetContainerId: "仓库",
            policy: "mergeThenEmpty",
            windows: windows
        });
        assertTrue(!badPair.success && badPair.error == "transfer_forbidden",
            "autoTransfer 只允许背包与仓库或战备箱成对传输");

        resetInventories();
        _root.主线任务进度 = 14;
        var blockedSource:Object = item("无法转移", {level: 1});
        _root.物品栏.背包.add(0, blockedSource);
        for (var slot:Number = 0; slot < 40; slot++) {
            _root.物品栏.战备箱.add(slot, item("占位装备" + slot, {level: 1}));
        }
        response = InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [
                {containerId: "背包", offset: 0, limit: 50},
                {containerId: "战备箱", offset: 0, limit: 40}
            ]
        });
        result = InventoryPanelService.execute("autoTransfer", {
            v: 1,
            source: refFrom(response, 0, 0),
            targetContainerId: "战备箱",
            policy: "mergeThenEmpty",
            windows: [
                {containerId: "背包", offset: 0, limit: 50, filterKey: "all"},
                {containerId: "战备箱", offset: 0, limit: 40, filterKey: "all"}
            ]
        });
        assertTrue(!result.success && result.error == "target_full"
                && _root.物品栏.背包.getItem("0") === blockedSource
                && !_root.存档系统.dirtyMark,
            "autoTransfer 目标已满时来源与 dirty 状态保持不变");

        resetInventories();
        var rollbackSource:Object = item("回滚装备", {level: 3});
        _root.物品栏.背包.add(0, rollbackSource);
        response = snapshot(10, 10);
        InventoryPanelService.testOnlyFailNextCommit("仓库", 0);
        result = InventoryPanelService.execute("autoTransfer", {
            v: 1,
            source: refFrom(response, 0, 0),
            targetContainerId: "仓库",
            policy: "mergeThenEmpty",
            windows: windows
        });
        assertTrue(!result.success && result.error == "commit_failed"
                && _root.物品栏.背包.getItem("0") === rollbackSource
                && _root.物品栏.仓库.getItem("0") == null
                && !_root.存档系统.dirtyMark,
            "autoTransfer 目标提交失败时原子回滚且不发布 dirty");
    }

    private static function testAutoTransferBatchSuccessAndSingleScan():Void {
        resetInventories();
        unlockFullBattlebox();
        var mergeSource:Object = new BaseItem("批量已有材料", 2, 1);
        var movedStack:Object = new BaseItem("批量新材料", 4, 1);
        var foldedStack:Object = new BaseItem("批量新材料", 3, 1);
        var existingTarget:Object = new BaseItem("批量已有材料", 5, 1);
        _root.物品栏.背包.add(0, mergeSource);
        _root.物品栏.背包.add(1, movedStack);
        _root.物品栏.背包.add(2, foldedStack);
        _root.物品栏.战备箱.add(239, existingTarget);

        var sourceHolder:MovieClip = _root.createEmptyMovieClip(
            "__inventoryBatchSourceEvents", _root.getNextHighestDepth()
        );
        var targetHolder:MovieClip = _root.createEmptyMovieClip(
            "__inventoryBatchTargetEvents", _root.getNextHighestDepth()
        );
        var sourceDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(sourceHolder);
        var targetDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(targetHolder);
        var removedCount:Number = 0;
        var addedCount:Number = 0;
        var valueCount:Number = 0;
        sourceDispatcher.subscribe("ItemRemoved", function():Void { removedCount++; });
        targetDispatcher.subscribe("ItemAdded", function():Void { addedCount++; });
        targetDispatcher.subscribe("ItemValueChanged", function():Void { valueCount++; });
        _root.物品栏.背包.setDispatcher(sourceDispatcher);
        _root.物品栏.战备箱.setDispatcher(targetDispatcher);

        var before:Object = storagePairSnapshot("战备箱");
        var sourceRevision:Number = _root.物品栏.背包.getMutationRevision();
        var targetRevision:Number = _root.物品栏.战备箱.getMutationRevision();
        var sourceRebuilds:Number = _root.物品栏.背包._getIndexRebuildCountForTests();
        var targetRebuilds:Number = _root.物品栏.战备箱._getIndexRebuildCountForTests();
        var result:Object = InventoryPanelService.execute("autoTransferBatch", {
            v:1,
            sources:refsFrom(before, 0, 3),
            targetContainerId:"战备箱",
            policy:"mergeThenEmpty",
            windows:autoTransferBatchWindows("战备箱")
        });
        var perf:Object = InventoryPanelService.testOnlyGetLastBatchPerf();

        assertTrue(result.success && result.operation == "autoTransferBatch"
                && result.policy == "mergeThenEmpty"
                && result.requestedCount == 3 && result.completedCount == 3
                && result.results.length == 3 && result.failure == undefined,
            "autoTransferBatch 全成功返回稳定 v1 批量响应且省略 failure");
        assertTrue(result.results[0].operation == "merge"
                && result.results[0].destination.slot == 239
                && result.results[1].operation == "move"
                && result.results[1].destination.slot == 0
                && result.results[2].operation == "merge"
                && result.results[2].destination.slot == 0,
            "autoTransferBatch 按选择顺序模拟已有堆合并、首空移动、再合并新堆");
        assertTrue(_root.物品栏.战备箱.getItem("239") === existingTarget
                && existingTarget.value == 7
                && _root.物品栏.战备箱.getItem("0") === movedStack
                && movedStack.value == 7
                && _root.物品栏.背包.getItem("0") == null
                && _root.物品栏.背包.getItem("1") == null
                && _root.物品栏.背包.getItem("2") == null,
            "批量 merge 保留既有对象、批量 move 保留首个 BaseItem 引用并守恒数量");
        assertTrue(_root.物品栏.背包.getMutationRevision() == sourceRevision + 1
                && _root.物品栏.战备箱.getMutationRevision() == targetRevision + 1
                && _root.物品栏.背包._getIndexRebuildCountForTests() == sourceRebuilds + 1
                && _root.物品栏.战备箱._getIndexRebuildCountForTests() == targetRebuilds + 1,
            "全成功批量事务每个容器只推进一次 revision 且只重建一次索引");
        assertTrue(removedCount == 3 && addedCount == 1 && valueCount == 1
                && _root.存档系统.dirtyMark
                && result.snapshots.length == 2,
            "批量成功只标脏一次语义、逐源 removed、逐目标触达槽聚合事件并单次返回窗口组");
        assertTrue(perf != null && perf.requested == 3 && perf.completed == 3
                && perf.targetScanned == 240 && perf.plan >= 0
                && perf.commit >= 0 && perf.snapshot >= 0 && perf.total >= 0,
            "240 槽战备箱由 batch 规划恰好扫描一次并记录完整分阶段 trace 字段");

        _root.物品栏.背包.setDispatcher(null);
        _root.物品栏.战备箱.setDispatcher(null);
        sourceHolder.removeMovieClip();
        targetHolder.removeMovieClip();
    }

    private static function testAutoTransferBatchPartialAndValidation():Void {
        resetInventories();
        _root.主线任务进度 = 14;
        var first:Object = new BaseItem("批量前缀一", {level:1}, 1);
        var blocked:Object = new BaseItem("批量前缀二", {level:1}, 1);
        var untouched:Object = new BaseItem("批量前缀三", {level:1}, 1);
        _root.物品栏.背包.add(0, first);
        _root.物品栏.背包.add(1, blocked);
        _root.物品栏.背包.add(2, untouched);
        for (var slot:Number = 0; slot < 39; slot++) {
            _root.物品栏.战备箱.add(slot, item("批量占位" + slot, {level:1}));
        }
        var before:Object = storagePairSnapshot("战备箱");
        var sourceRevision:Number = _root.物品栏.背包.getMutationRevision();
        var targetRevision:Number = _root.物品栏.战备箱.getMutationRevision();
        var sourceRebuilds:Number = _root.物品栏.背包._getIndexRebuildCountForTests();
        var targetRebuilds:Number = _root.物品栏.战备箱._getIndexRebuildCountForTests();
        var result:Object = InventoryPanelService.execute("autoTransferBatch", {
            v:1, sources:refsFrom(before, 0, 3), targetContainerId:"战备箱",
            policy:"mergeThenEmpty", windows:autoTransferBatchWindows("战备箱")
        });
        assertTrue(result.success && result.requestedCount == 3 && result.completedCount == 1
                && result.results.length == 1 && result.results[0].operation == "move"
                && result.results[0].destination.slot == 39
                && result.failure.index == 1 && result.failure.error == "target_full",
            "目标在第 j 项满时只提交有效前缀并返回零基 failure index 与 target_full");
        assertTrue(_root.物品栏.战备箱.getItem("39") === first
                && _root.物品栏.背包.getItem("0") == null
                && _root.物品栏.背包.getItem("1") === blocked
                && _root.物品栏.背包.getItem("2") === untouched,
            "部分成功不会跳过失败项或改写失败项之后的来源槽");
        assertTrue(_root.物品栏.背包.getMutationRevision() == sourceRevision + 1
                && _root.物品栏.战备箱.getMutationRevision() == targetRevision + 1
                && _root.物品栏.背包._getIndexRebuildCountForTests() == sourceRebuilds + 1
                && _root.物品栏.战备箱._getIndexRebuildCountForTests() == targetRebuilds + 1
                && result.snapshots.length == 2,
            "部分前缀仍只执行每容器一次 revision/rebuild 与一次窗口组重投影");

        resetInventories();
        _root.主线任务进度 = 14;
        var fullSource:Object = new BaseItem("首项满保护", {level:1}, 1);
        _root.物品栏.背包.add(0, fullSource);
        for (slot = 0; slot < 40; slot++) {
            _root.物品栏.战备箱.add(slot, item("全满占位" + slot, {level:1}));
        }
        before = storagePairSnapshot("战备箱");
        sourceRevision = _root.物品栏.背包.getMutationRevision();
        targetRevision = _root.物品栏.战备箱.getMutationRevision();
        sourceRebuilds = _root.物品栏.背包._getIndexRebuildCountForTests();
        targetRebuilds = _root.物品栏.战备箱._getIndexRebuildCountForTests();
        result = InventoryPanelService.execute("autoTransferBatch", {
            v:1, sources:[refFrom(before, 0, 0)], targetContainerId:"战备箱",
            policy:"mergeThenEmpty", windows:autoTransferBatchWindows("战备箱")
        });
        var fullPerf:Object = InventoryPanelService.testOnlyGetLastBatchPerf();
        assertTrue(!result.success && result.error == "target_full"
                && result.snapshots == undefined
                && _root.物品栏.背包.getItem("0") === fullSource
                && !_root.存档系统.dirtyMark
                && _root.物品栏.背包.getMutationRevision() == sourceRevision
                && _root.物品栏.战备箱.getMutationRevision() == targetRevision
                && _root.物品栏.背包._getIndexRebuildCountForTests() == sourceRebuilds
                && _root.物品栏.战备箱._getIndexRebuildCountForTests() == targetRebuilds
                && fullPerf.completed == 0 && fullPerf.targetScanned == 40,
            "首项即满返回失败且零写、零 dirty、零 snapshot、零 revision/rebuild");

        resetInventories();
        _root.物品栏.背包.add(0, item("陈旧批量来源", 1));
        before = storagePairSnapshot("仓库");
        var staleRef:Object = refFrom(before, 0, 0);
        _root.物品栏.背包.add(49, item("推进版本", 1));
        var stale:Object = InventoryPanelService.execute("autoTransferBatch", {
            v:1, sources:[staleRef], targetContainerId:"仓库",
            policy:"mergeThenEmpty", windows:autoTransferBatchWindows("仓库")
        });

        resetInventories();
        _root.物品栏.背包.add(0, item("重复来源", 1));
        before = storagePairSnapshot("仓库");
        var duplicateRef:Object = refFrom(before, 0, 0);
        var duplicate:Object = InventoryPanelService.execute("autoTransferBatch", {
            v:1, sources:[duplicateRef, duplicateRef], targetContainerId:"仓库",
            policy:"mergeThenEmpty", windows:autoTransferBatchWindows("仓库")
        });

        resetInventories();
        _root.物品栏.背包.add(0, item("混容器背包", 1));
        _root.物品栏.仓库.add(0, item("混容器仓库", 1));
        before = storagePairSnapshot("仓库");
        var mixed:Object = InventoryPanelService.execute("autoTransferBatch", {
            v:1, sources:[refFrom(before, 0, 0), refFrom(before, 1, 0)],
            targetContainerId:"仓库", policy:"mergeThenEmpty",
            windows:autoTransferBatchWindows("仓库")
        });
        var overLimitRefs:Array = [];
        for (slot = 0; slot < 51; slot++) {
            overLimitRefs.push({containerId:"背包", slot:slot, expectedLease:"fake"});
        }
        var overLimit:Object = InventoryPanelService.execute("autoTransferBatch", {
            v:1, sources:overLimitRefs, targetContainerId:"仓库",
            policy:"mergeThenEmpty", windows:autoTransferBatchWindows("仓库")
        });
        assertTrue(!stale.success && stale.error == "stale_state"
                && !duplicate.success && duplicate.error == "invalid_payload"
                && !mixed.success && mixed.error == "invalid_payload"
                && !overLimit.success && overLimit.error == "invalid_payload",
            "batch 严格拒绝 stale、重复槽、混来源容器与超过 50 项请求");
    }

    private static function testAutoTransferBatchRollback():Void {
        resetInventories();
        _root.主线任务进度 = 14;
        var first:Object = new BaseItem("批量回滚堆", 4, 1);
        var second:Object = new BaseItem("批量回滚堆", 3, 1);
        _root.物品栏.背包.add(0, first);
        _root.物品栏.背包.add(1, second);

        var sourceHolder:MovieClip = _root.createEmptyMovieClip(
            "__inventoryBatchRollbackSource", _root.getNextHighestDepth()
        );
        var targetHolder:MovieClip = _root.createEmptyMovieClip(
            "__inventoryBatchRollbackTarget", _root.getNextHighestDepth()
        );
        var sourceDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(sourceHolder);
        var targetDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(targetHolder);
        var sourceEvents:Number = 0;
        var targetEvents:Number = 0;
        sourceDispatcher.subscribe("ItemRemoved", function():Void { sourceEvents++; });
        targetDispatcher.subscribe("ItemAdded", function():Void { targetEvents++; });
        targetDispatcher.subscribe("ItemValueChanged", function():Void { targetEvents++; });
        _root.物品栏.背包.setDispatcher(sourceDispatcher);
        _root.物品栏.战备箱.setDispatcher(targetDispatcher);

        var before:Object = storagePairSnapshot("战备箱");
        var sourceRevision:Number = _root.物品栏.背包.getMutationRevision();
        var targetRevision:Number = _root.物品栏.战备箱.getMutationRevision();
        var sourceRebuilds:Number = _root.物品栏.背包._getIndexRebuildCountForTests();
        var targetRebuilds:Number = _root.物品栏.战备箱._getIndexRebuildCountForTests();
        InventoryPanelService.testOnlyFailNextCommit("战备箱", 0);
        var result:Object = InventoryPanelService.execute("autoTransferBatch", {
            v:1, sources:refsFrom(before, 0, 2), targetContainerId:"战备箱",
            policy:"mergeThenEmpty", windows:autoTransferBatchWindows("战备箱")
        });
        var indexes:Array = _root.物品栏.背包.getIndexes();
        assertTrue(!result.success && result.error == "commit_failed"
                && _root.物品栏.背包.getItem("0") === first
                && _root.物品栏.背包.getItem("1") === second
                && first.value == 4 && second.value == 3
                && _root.物品栏.战备箱.getItem("0") == null,
            "目标批量提交故障后 receipt 精确恢复来源槽、数量与对象引用");
        assertTrue(_root.物品栏.背包.getMutationRevision() == sourceRevision
                && _root.物品栏.战备箱.getMutationRevision() == targetRevision
                && _root.物品栏.背包._getIndexRebuildCountForTests() == sourceRebuilds + 1
                && _root.物品栏.战备箱._getIndexRebuildCountForTests() == targetRebuilds
                && indexes.length == 2 && indexes[0] == 0 && indexes[1] == 1,
            "rollback 恢复 raw revision 与旧索引树且故障路径每端不超过一次重建");
        assertTrue(!_root.存档系统.dirtyMark && sourceEvents == 0 && targetEvents == 0
                && result.snapshots == undefined,
            "批量 commit failure 不标脏、不发事件且不生成成功 snapshot");

        _root.物品栏.背包.setDispatcher(null);
        _root.物品栏.战备箱.setDispatcher(null);
        sourceHolder.removeMovieClip();
        targetHolder.removeMovieClip();
    }

    private static function runAutoTransferComparisonFixture(count:Number, useBatch:Boolean):Object {
        resetInventories();
        unlockFullBattlebox();
        for (var i:Number = 0; i < count; i++) {
            _root.物品栏.背包.add(i, item("批量性能对照" + i, {level:1}));
        }
        var response:Object = storagePairSnapshot("战备箱");
        var sourceRevision:Number = _root.物品栏.背包.getMutationRevision();
        var targetRevision:Number = _root.物品栏.战备箱.getMutationRevision();
        var sourceRebuilds:Number = _root.物品栏.背包._getIndexRebuildCountForTests();
        var targetRebuilds:Number = _root.物品栏.战备箱._getIndexRebuildCountForTests();
        var requests:Number = 0;
        var snapshots:Number = 0;
        var success:Boolean = true;
        var started:Number = getTimer();
        if (useBatch) {
            var batchResult:Object = InventoryPanelService.execute("autoTransferBatch", {
                v:1, sources:refsFrom(response, 0, count), targetContainerId:"战备箱",
                policy:"mergeThenEmpty", windows:autoTransferBatchWindows("战备箱")
            });
            requests = 1;
            success = batchResult.success && batchResult.completedCount == count;
            snapshots = batchResult.snapshots == undefined ? 0 : batchResult.snapshots.length;
        } else {
            for (i = 0; i < count; i++) {
                response = InventoryPanelService.execute("autoTransfer", {
                    v:1, source:refFrom(response, 0, i), targetContainerId:"战备箱",
                    policy:"mergeThenEmpty", windows:autoTransferBatchWindows("战备箱")
                });
                requests++;
                if (!response.success) {
                    success = false;
                    break;
                }
                snapshots += response.snapshots.length;
            }
        }
        var elapsed:Number = getTimer() - started;
        var moved:Number = 0;
        for (i = 0; i < count; i++) {
            if (_root.物品栏.战备箱.getItem(String(i)) != null) moved++;
        }
        return {
            success:success,
            elapsed:elapsed,
            requests:requests,
            snapshots:snapshots,
            moved:moved,
            sourceRevisionDelta:_root.物品栏.背包.getMutationRevision() - sourceRevision,
            targetRevisionDelta:_root.物品栏.战备箱.getMutationRevision() - targetRevision,
            sourceRebuildDelta:_root.物品栏.背包._getIndexRebuildCountForTests() - sourceRebuilds,
            targetRebuildDelta:_root.物品栏.战备箱._getIndexRebuildCountForTests() - targetRebuilds
        };
    }

    private static function testAutoTransferBatchComparison():Void {
        var sizes:Array = [1, 10, 50];
        for (var i:Number = 0; i < sizes.length; i++) {
            var count:Number = Number(sizes[i]);
            var oldMetrics:Object = runAutoTransferComparisonFixture(count, false);
            var batchMetrics:Object = runAutoTransferComparisonFixture(count, true);
            trace("[InventoryPanelService PERF] autoTransferComparison"
                + " count=" + count
                + " oldTotal=" + oldMetrics.elapsed
                + " batchTotal=" + batchMetrics.elapsed
                + " oldRequests=" + oldMetrics.requests
                + " batchRequests=" + batchMetrics.requests);
            assertTrue(oldMetrics.success && batchMetrics.success
                    && oldMetrics.moved == count && batchMetrics.moved == count,
                count + " 件旧逐项与新 batch 在同进程 fixture 中完成等价移动");
            assertTrue(oldMetrics.requests == count && batchMetrics.requests == 1
                    && oldMetrics.snapshots == count * 2 && batchMetrics.snapshots == 2,
                count + " 件 batch 将逐项 round-trip 等价请求与窗口组压缩为一次");
            assertTrue(oldMetrics.sourceRevisionDelta == count
                    && oldMetrics.targetRevisionDelta == count
                    && oldMetrics.sourceRebuildDelta == count
                    && oldMetrics.targetRebuildDelta == count
                    && batchMetrics.sourceRevisionDelta == 1
                    && batchMetrics.targetRevisionDelta == 1
                    && batchMetrics.sourceRebuildDelta == 1
                    && batchMetrics.targetRebuildDelta == 1,
                count + " 件确定性计数证明 batch 每容器仅一次 revision/index rebuild");
        }
    }

    private static function testMoveMergeSwapAndReverse():Void {
        resetInventories();
        var moving:Object = item("武器", {level: 2});
        _root.物品栏.背包.add(0, moving);
        var response:Object = snapshot(10, 10);
        var result:Object = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 1, 0)
        });
        assertTrue(result.success && _root.物品栏.仓库.getItem("0") === moving && _root.物品栏.背包.getItem("0") == null,
            "whole-slot move 保持 BaseItem 外壳引用并提交两端");
        assertTrue(_root.存档系统.dirtyMark == true, "成功 move 设置 dirtyMark");

        resetInventories();
        _root.物品栏.背包.add(0, item("药剂", 3));
        var mergeTarget:Object = item("药剂", 4);
        _root.物品栏.仓库.add(0, mergeTarget);
        response = snapshot(10, 10);
        result = InventoryPanelService.execute("merge", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 1, 0)
        });
        assertTrue(result.success && mergeTarget.value == 7 && _root.物品栏.背包.getItem("0") == null,
            "whole-stack merge 原地更新目标并清源");

        resetInventories();
        var left:Object = item("左物品", {level: 1});
        var right:Object = item("右物品", {level: 1});
        _root.物品栏.背包.add(0, left);
        _root.物品栏.仓库.add(0, right);
        response = snapshot(10, 10);
        result = InventoryPanelService.execute("swap", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 1, 0)
        });
        assertTrue(result.success && _root.物品栏.背包.getItem("0") === right && _root.物品栏.仓库.getItem("0") === left,
            "whole-slot swap 原子交换两端引用");

        resetInventories();
        var reverseItem:Object = item("反向物品", 2);
        _root.物品栏.仓库.add(0, reverseItem);
        response = snapshot(10, 10);
        result = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(response, 1, 0), target: refFrom(response, 0, 0)
        });
        assertTrue(result.success && result.operation == "move" && _root.物品栏.背包.getItem("0") === reverseItem,
            "仓库→背包反向仍调用同一 move operation");
    }

    private static function testSameContainerTransfersAndRollback():Void {
        resetInventories();
        var moving:Object = item("背包内移动", {level: 2});
        _root.物品栏.背包.add(0, moving);
        var response:Object = snapshot(10, 10);
        var result:Object = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 0, 2)
        });
        assertTrue(result.success && _root.物品栏.背包.getItem("2") === moving
                && _root.物品栏.背包.getItem("0") == null,
            "背包内 whole-slot move 保持引用并移动 physicalSlot");
        assertTrue(result.snapshots.length == 1 && result.snapshots[0].containerId == "背包",
            "同容器同窗口 transfer 只返回一个去重 snapshot");

        resetInventories();
        _root.物品栏.背包.add(0, item("背包药剂", 3));
        var mergeTarget:Object = item("背包药剂", 4);
        _root.物品栏.背包.add(1, mergeTarget);
        response = snapshot(10, 10);
        result = InventoryPanelService.execute("merge", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 0, 1)
        });
        assertTrue(result.success && mergeTarget.value == 7 && _root.物品栏.背包.getItem("0") == null,
            "背包内同名 stack whole-stack merge 成立");

        resetInventories();
        var warehouseLeft:Object = item("仓库左物品", {level: 1});
        var warehouseRight:Object = item("仓库右物品", {level: 1});
        _root.物品栏.仓库.add(0, warehouseLeft);
        _root.物品栏.仓库.add(1, warehouseRight);
        response = snapshot(10, 10);
        result = InventoryPanelService.execute("swap", {
            v: 1, source: refFrom(response, 1, 0), target: refFrom(response, 1, 1)
        });
        assertTrue(result.success && _root.物品栏.仓库.getItem("0") === warehouseRight
                && _root.物品栏.仓库.getItem("1") === warehouseLeft,
            "仓库内异类 whole-slot swap 原子换位");

        resetInventories();
        var selfStack:Object = item("同槽保护", 5);
        _root.物品栏.背包.add(0, selfStack);
        response = snapshot(10, 10);
        var selfRef:Object = refFrom(response, 0, 0);
        result = InventoryPanelService.execute("merge", {v: 1, source: selfRef, target: selfRef});
        assertTrue(!result.success && result.error == "same_slot" && selfStack.value == 5
                && _root.物品栏.背包.getItem("0") === selfStack,
            "同 physicalSlot 在提交前拒绝，避免自 merge 数据损坏");

        resetInventories();
        var rollbackItem:Object = item("同容器回滚", 2);
        _root.物品栏.背包.add(0, rollbackItem);
        response = snapshot(10, 10);
        InventoryPanelService.testOnlyFailNextCommit("背包", 1);
        result = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 0, 1)
        });
        assertTrue(!result.success && result.error == "commit_failed",
            "同容器第二槽提交失败返回 commit_failed");
        assertTrue(_root.物品栏.背包.getItem("0") === rollbackItem
                && _root.物品栏.背包.getItem("1") == null && _root.存档系统.dirtyMark == false,
            "同容器第二槽失败完整回滚且不标脏");
    }

    private static function testEventReentrancy():Void {
        resetInventories();
        _root.物品栏.背包.add(0, item("药剂", 2));
        var holder:MovieClip = _root.createEmptyMovieClip("__inventoryPanelServiceTest", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        _root.物品栏.背包.setDispatcher(dispatcher);
        var reentryResult:Object = null;
        dispatcher.subscribe("ItemRemoved", function():Void {
            reentryResult = InventoryPanelService.execute("snapshot", {
                v: 1, requests: [{containerId: "背包", offset: 0, limit: 10}]
            });
        });

        var response:Object = snapshot(10, 10);
        var result:Object = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 1, 0)
        });
        assertTrue(result.success && reentryResult != null && reentryResult.error == "busy",
            "生命周期事件同步重入被事务守卫拒绝");
        _root.物品栏.背包.setDispatcher(null);
        holder.removeMovieClip();
    }

    private static function testCommitFailureRollback():Void {
        resetInventories();
        var sourceItem:Object = item("药剂", 2);
        _root.物品栏.背包.add(0, sourceItem);
        var response:Object = snapshot(10, 10);
        InventoryPanelService.testOnlyFailNextCommit("仓库", 0);
        var result:Object = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 1, 0)
        });
        assertTrue(!result.success && result.error == "commit_failed", "提交段失败返回 commit_failed");
        assertTrue(_root.物品栏.背包.getItem("0") === sourceItem && _root.物品栏.仓库.getItem("0") == null,
            "第二端提交失败后第一端完整回滚，无部分写");
        assertTrue(_root.存档系统.dirtyMark == false, "回滚路径不设置 dirtyMark");
    }

    private static function testDiscardProjectionAndSuccess():Void {
        resetInventories();
        var stack:Object = item("药剂", 2);
        _root.物品栏.背包.add(0, stack);
        var response:Object = snapshot(10, 10);
        var source:Object = refFrom(response, 0, 0);
        stack.value = 3;
        var stale:Object = InventoryPanelService.execute("discard", {v: 1, source: source});
        assertTrue(!stale.success && stale.error == "stale_state", "确认框展示数量变化后 discard 要求重新确认");

        response = snapshot(10, 10);
        source = refFrom(response, 0, 0);
        var result:Object = InventoryPanelService.execute("discard", {v: 1, source: source});
        assertTrue(result.success && _root.物品栏.背包.getItem("0") == null && result.snapshots[0].slots[0].occupied == false,
            "discard 删除整槽、标脏并在同一回包刷新背包");
    }

    private static function testSortValidationMergeEpochAndLease():Void {
        resetInventories();
        var itemDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.itemDataDict == undefined;
        var equipmentDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.equipmentDict == undefined;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = {};
        if (equipmentDictWasUndefined) org.flashNight.arki.item.ItemUtil.equipmentDict = {};
        var previousMeta:Object = org.flashNight.arki.item.ItemUtil.itemDataDict["强化石"];
        var previousAlphaMeta:Object = org.flashNight.arki.item.ItemUtil.itemDataDict["Alpha"];
        var previousZuluMeta:Object = org.flashNight.arki.item.ItemUtil.itemDataDict["Zulu"];
        // 对齐 data/items 正式 schema：材料是 type=收集品 + use=材料。
        // 禁止用不存在的 type=材料 夹具把 ItemSortUtil 的分类错误遮住。
        org.flashNight.arki.item.ItemUtil.itemDataDict["强化石"] = {type: "收集品", use: "材料", price: 1, level: 0, id: 1};
        org.flashNight.arki.item.ItemUtil.itemDataDict["Alpha"] = {type: "测试装备", use: "测试", price: 2, level: 1, id: 2};
        org.flashNight.arki.item.ItemUtil.itemDataDict["Zulu"] = {type: "测试装备", use: "测试", price: 3, level: 1, id: 3};
        _root.物品栏.仓库.add(50, item("强化石", 2));
        _root.物品栏.仓库.add(51, item("强化石", 3));
        _root.物品栏.仓库.add(52, item("Zulu", {level: 1}));
        _root.物品栏.仓库.add(53, item("Alpha", {level: 1}));
        var before:Object = warehouseSnapshot(50, 50);
        var oldLease:Object = refFrom(before, 0, 0);
        var invalid:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1, container: {containerId: "仓库", offset: 50, limit: 50}, methodName: "unknown"
        });
        assertTrue(!invalid.success && invalid.error == "unsupported_sort_method" && _root.存档系统.dirtyMark == false,
            "未知整理策略严格拒绝且不写入");

        var result:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1, container: {containerId: "仓库", offset: 50, limit: 50}, methodName: "byName"
        });
        assertTrue(result.success && result.snapshots[0].offset == 50 && result.snapshots[0].containerEpoch == 2,
            "sortAndMerge 保持当前窗口并递增整容器 epoch");
        var mergedFound:Boolean = false;
        var alphaSlot:Number = -1;
        var zuluSlot:Number = -1;
        for (var sortedSlot:Number = 0; sortedSlot < _root.物品栏.仓库.capacity; sortedSlot++) {
            var sortedItem:Object = _root.物品栏.仓库.getItem(String(sortedSlot));
            if (sortedItem == null) continue;
            if (sortedSlot < 8) trace("[InventoryPanelService SORT] slot=" + sortedSlot + " name=" + sortedItem.name + " value=" + sortedItem.value);
            if (sortedItem.name == "强化石" && Number(sortedItem.value) == 5) mergedFound = true;
            if (sortedItem.name == "Alpha") alphaSlot = sortedSlot;
            if (sortedItem.name == "Zulu") zuluSlot = sortedSlot;
        }
        trace("[InventoryPanelService SORT] size=" + _root.物品栏.仓库.size() + " merged=" + mergedFound
            + " alphaSlot=" + alphaSlot + " zuluSlot=" + zuluSlot);
        assertTrue(_root.物品栏.仓库.size() == 3 && mergedFound && alphaSlot >= 0 && zuluSlot > alphaSlot,
            "权威整理按名称重排并合并可堆叠物品");
        assertTrue(_root.存档系统.dirtyMark == true, "成功整理显式 dirtyMark");
        var stale:Object = InventoryPanelService.execute("move", {
            v: 1,
            source: oldLease,
            target: {containerId: "背包", slot: 0, expectedLease: "old"}
        });
        assertTrue(!stale.success && stale.error == "stale_state", "整容器整理后旧仓库 page lease 全部失效");
        if (previousMeta == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict["强化石"];
        else org.flashNight.arki.item.ItemUtil.itemDataDict["强化石"] = previousMeta;
        if (previousAlphaMeta == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict["Alpha"];
        else org.flashNight.arki.item.ItemUtil.itemDataDict["Alpha"] = previousAlphaMeta;
        if (previousZuluMeta == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict["Zulu"];
        else org.flashNight.arki.item.ItemUtil.itemDataDict["Zulu"] = previousZuluMeta;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = undefined;
        if (equipmentDictWasUndefined) org.flashNight.arki.item.ItemUtil.equipmentDict = undefined;
    }

    private static function testBackpackAuthoritySort():Void {
        resetInventories();
        var metadata:Object = installSortTestMetadata(["Alpha", "Zulu"]);
        _root.物品栏.背包.add(2, item("Zulu", {level: 1}));
        _root.物品栏.背包.add(40, item("Alpha", {level: 1}));
        var result:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1,
            container: {containerId: "背包", offset: 0, limit: 50, filterKey: "all"},
            methodName: "byName"
        });
        assertTrue(result.success && result.sortedCapacity == 50
                && _root.物品栏.背包.getItem("0").name == "Alpha"
                && _root.物品栏.背包.getItem("1").name == "Zulu"
                && result.snapshots[0].containerEpoch == 2,
            "背包复用事务化权威整理并重铸整容器 epoch");
        assertTrue(_root.存档系统.dirtyMark == true,
            "背包权威整理成功后显式标脏");
        restoreSortTestMetadata(metadata);
    }

    private static function testBattleboxAccessiblePrefixSort():Void {
        resetInventories();
        _root.主线任务进度 = 14;
        var metadata:Object = installSortTestMetadata(["Alpha", "Zulu"]);
        _root.物品栏.战备箱.add(3, item("Zulu", {level: 1}));
        _root.物品栏.战备箱.add(35, item("Alpha", {level: 1}));
        var reservedA:Object = item("保留区A", {level: 1});
        var reservedB:Object = item("保留区B", {level: 1});
        _root.物品栏.战备箱.add(80, reservedA);
        _root.物品栏.战备箱.add(399, reservedB);

        var result:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1,
            container: {containerId: "战备箱", offset: 0, limit: 40, filterKey: "all"},
            methodName: "byName"
        });
        assertTrue(result.success && result.sortedCapacity == 40
                && _root.物品栏.战备箱.getItem("0").name == "Alpha"
                && _root.物品栏.战备箱.getItem("1").name == "Zulu",
            "战备箱权威整理只压缩当前剧情已解锁前缀");
        assertTrue(_root.物品栏.战备箱.getItem("80") === reservedA
                && _root.物品栏.战备箱.getItem("399") === reservedB,
            "战备箱400槽锁定保留区逐槽保持原 key 与对象引用");
        assertTrue(_root.存档系统.dirtyMark == true && result.snapshots[0].containerEpoch == 2,
            "战备箱前缀整理标脏并使可见 lease 失效");
        restoreSortTestMetadata(metadata);
    }

    private static function testSortCommitFailureRollback():Void {
        resetInventories();
        var metadata:Object = installSortTestMetadata(["Alpha", "Zulu"]);
        var first:Object = item("Zulu", {level: 1});
        var second:Object = item("Alpha", {level: 1});
        _root.物品栏.仓库.add(70, first);
        _root.物品栏.仓库.add(71, second);
        InventoryPanelService.testOnlyFailNextCommit("仓库", -1);
        var result:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1, container: {containerId: "仓库", offset: 50, limit: 50}, methodName: "byName"
        });
        assertTrue(!result.success && result.error == "commit_failed", "整容器提交失败返回 commit_failed");
        assertTrue(_root.物品栏.仓库.getItem("70") === first && _root.物品栏.仓库.getItem("71") === second,
            "整理计划隔离执行，提交失败保持所有 physicalSlot 原状");
        assertTrue(_root.存档系统.dirtyMark == false, "整理回滚路径不标脏");
        restoreSortTestMetadata(metadata);
    }

    private static function testSortRejectsLossyPlan():Void {
        resetInventories();
        var legacy:Object = item("未注册历史物品", 7);
        _root.物品栏.仓库.add(33, legacy);
        var result:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1, container: {containerId: "仓库", offset: 0, limit: 50}, methodName: "byName"
        });
        assertTrue(!result.success && result.error == "sort_failed"
                && _root.物品栏.仓库.getItem("33") === legacy && _root.存档系统.dirtyMark == false,
            "整理计划若过滤未知历史物品则拒绝提交，不静默丢物");
    }

    private static function testSortEventReentrancy():Void {
        resetInventories();
        var metadata:Object = installSortTestMetadata(["Alpha", "Zulu"]);
        _root.物品栏.仓库.add(0, item("Zulu", {level: 1}));
        _root.物品栏.仓库.add(1, item("Alpha", {level: 1}));
        var holder:MovieClip = _root.createEmptyMovieClip("__inventorySortServiceTest", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        _root.物品栏.仓库.setDispatcher(dispatcher);
        var reentry:Object = null;
        dispatcher.subscribe("ItemRemoved", function():Void {
            if (reentry == null) reentry = warehouseSnapshot(0, 50);
        });
        var result:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1, container: {containerId: "仓库", offset: 0, limit: 50}, methodName: "byName"
        });
        assertTrue(result.success && reentry != null && reentry.error == "busy",
            "整理提交后的生命周期事件仍处于事务重入守卫内");
        _root.物品栏.仓库.setDispatcher(null);
        holder.removeMovieClip();
        restoreSortTestMetadata(metadata);
    }

    private static function testWindowPerformanceMatrix():Void {
        var capacities:Array = [50, 400, 1200];
        var ratios:Array = [0, 0.5, 1];
        for (var c:Number = 0; c < capacities.length; c++) {
            for (var r:Number = 0; r < ratios.length; r++) {
                var capacity:Number = capacities[c];
                _root.物品栏 = {
                    背包: new ArrayInventory(null, 50),
                    仓库: new ArrayInventory(null, capacity)
                };
                _root.存档系统 = {dirtyMark: false};
                InventoryPanelService.testOnlyReset();
                var occupied:Number = Math.floor(capacity * Number(ratios[r]));
                for (var slot:Number = 0; slot < occupied; slot++) {
                    _root.物品栏.仓库.add(slot, item("Perf" + slot, 1));
                }
                var started:Number = getTimer();
                var response:Object = null;
                for (var iteration:Number = 0; iteration < 100; iteration++) {
                    response = warehouseSnapshot(0, Math.min(50, capacity));
                }
                var elapsed:Number = getTimer() - started;
                var payloadChars:Number = new LiteJSON().stringify(response).length;
                trace("[InventoryPanelService PERF] capacity=" + capacity + " occupancy=" + occupied
                    + " window=50 iterations=100 elapsedMs=" + elapsed + " payloadChars=" + payloadChars);
                assertTrue(response.success && response.snapshots[0].slots.length == Math.min(50, capacity)
                        && elapsed < 5000 && payloadChars < 100000,
                    "窗口快照性能门 " + capacity + " 槽 / " + Math.round(Number(ratios[r]) * 100) + "% 占用");
            }
        }
    }

    private static function testFullWarehouseSortPerformance():Void {
        resetInventories();
        var itemDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.itemDataDict == undefined;
        var equipmentDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.equipmentDict == undefined;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = {};
        if (equipmentDictWasUndefined) org.flashNight.arki.item.ItemUtil.equipmentDict = {};
        var previousMeta:Object = org.flashNight.arki.item.ItemUtil.itemDataDict["GateA3性能堆叠"];
        org.flashNight.arki.item.ItemUtil.itemDataDict["GateA3性能堆叠"] = {
            type: "收集品", use: "材料", price: 1, level: 0, id: 999999
        };
        for (var slot:Number = 0; slot < 1200; slot++) {
            _root.物品栏.仓库.add(slot, item("GateA3性能堆叠", 1));
        }
        var started:Number = getTimer();
        var result:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1, container: {containerId: "仓库", offset: 0, limit: 50}, methodName: "byType"
        });
        var elapsed:Number = getTimer() - started;
        trace("[InventoryPanelService PERF] fullWarehouseSort capacity=1200 occupancy=1200 elapsedMs=" + elapsed);
        assertTrue(result.success && _root.物品栏.仓库.size() == 1
                && Number(_root.物品栏.仓库.getItem("0").value) == 1200 && elapsed < 5000,
            "1200/1200 满仓权威整理与合并性能门");
        if (previousMeta == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict["GateA3性能堆叠"];
        else org.flashNight.arki.item.ItemUtil.itemDataDict["GateA3性能堆叠"] = previousMeta;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = undefined;
        if (equipmentDictWasUndefined) org.flashNight.arki.item.ItemUtil.equipmentDict = undefined;
    }
}
