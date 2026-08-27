import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.PlayerAssetTransaction;

import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.item.itemCollection.EquipmentInventory;
import org.flashNight.arki.item.itemCollection.DrugInventory;
import org.flashNight.neur.Event.LifecycleEventDispatcher;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.EquipmentTuningService;
import org.flashNight.arki.item.CharacterBuildService;
import org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;

/** EquipmentTuningService 行为与事务回归。 */
class org.flashNight.arki.item.EquipmentTuningServiceTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var SLOT_KEYS:Array = [
        "头部装备", "上装装备", "下装装备", "手部装备",
        "脚部装备", "颈部装备", "长枪", "手枪",
        "手枪2", "刀", "手雷"
    ];
    private static var SLOT_DATA_KEYS:Array = [
        "头部装备数据", "上装装备数据", "下装装备数据",
        "手部装备数据", "脚部装备数据", "颈部装备数据",
        "长枪数据", "手枪数据", "手枪2数据", "刀数据",
        "手雷数据"
    ];

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        trace("=== EquipmentTuningServiceTest start ===");
        testSnapshotGenderNormalization();
        testWireShapeAndReconcileBarrier();
        testInstallAndEnhanceCommit();
        testSnapshotAndDetachInvalidateTokens();
        testPreviewAttemptRevokesPreviousToken();
        testSameLevelConvertNoOp();
        testStaleMaterialAndFailureRollback();
        testCandidateAvailabilityRequiresOwnedMaterial();
        testWebCommitOperationMatrix();
        testOwnershipFlowProjection();
        testTierProgression();
        testWebInstallModAndTooltip();
        testDetachPolicySemantics();
        testFinalStateEventsAndBusyGuard();
        testFinalStateListenerFaultRecovery();
        testStrictSourceKindsAndWornStaleFences();
        testWornCommitAndLiveDirtyBoundary();
        testWornConversionAcrossBackpack();
        testWornAllowedOperationMatrix();
        testWornRollbackAndUnknownReconcile();
        testPreviewStatRows();
        trace("EquipmentTuningServiceTest Tests Passed: " + _passed);
        trace("EquipmentTuningServiceTest Tests Failed: " + _failed);
        trace("=== EquipmentTuningServiceTest end ===");
    }

    private static function resetFixture():Void {
        EquipmentUtil.loadEquipmentConfig({
            levelStatList:[1,1.02,1.04,1.06,1.08,1.1,1.12,1.14,1.16,1.18,1.2,1.22,1.24,1.26],
            decimalPropDict:{weight:1},
            tierNameToKeyDict:{二阶:"data_2",三阶:"data_3",四阶:"data_4"},
            tierToMaterialDict:{
                data_2:"二阶复合防御组件", data_3:"三阶复合防御组件", data_4:"四阶复合防御组件"
            },
            defaultTierDataDict:{
                二阶:{level:12,defence:80}, 三阶:{level:15,defence:120}, 四阶:{level:20,defence:180}
            }
        });
        EquipmentUtil.loadModData([
            {name:"基础导轨",use:"手枪",provideTags:"导轨",detachPolicy:"single"},
            {name:"依赖瞄具",use:"手枪",requireTags:"导轨",detachPolicy:"single"},
            {name:"普通握把",use:"手枪",detachPolicy:"single",
                modGrade:"medium",uiGradeLabel:"中等",uiGradeColor:"#996600",
                catalogScope:"firearm",uiScopeLabel:"枪械",
                uiRole:"precision",uiRoleLabel:"精准与操控",uiSymbol:"triangle-outline",
                tag:"握柄包覆"},
            {name:"光棱射线弹-强化",use:"手枪",detachPolicy:"single"},
            {name:"光谱射线弹",use:"手枪",detachPolicy:"single"},
            {name:"光谱射线弹-强化",use:"手枪",detachPolicy:"single"},
            {name:"遗留握柄",use:"长枪",detachPolicy:"single"},
            {name:"级联核心",use:"手枪",detachPolicy:"cascade"},
            {name:"测试增幅插件",use:"手枪",detachPolicy:"single",stats:{flat:{vampirism:3}}}
        ]);
        ItemUtil.loadItemData([
            {name:"测试手枪A",displayname:"测试手枪A",icon:"测试",type:"武器",use:"手枪",weapontype:"手枪",
                data:{level:1,modslot:4,damage:10,interval:100,impact:100,bullet:"普通子弹",split:1},
                data_2:{level:12,damage:30,interval:77,impact:25}},
            {name:"测试手枪B",displayname:"测试手枪B",icon:"测试",type:"武器",use:"手枪",weapontype:"手枪",data:{level:1,modslot:4,damage:10}},
            {name:"测试未知槽手枪",displayname:"测试未知槽手枪",icon:"测试",type:"武器",use:"手枪",weapontype:"手枪",data:{level:1,damage:10}},
            {name:"测试负数槽手枪",displayname:"测试负数槽手枪",icon:"测试",type:"武器",use:"手枪",weapontype:"手枪",data:{level:1,modslot:-1,damage:10}},
            {name:"测试小数槽手枪",displayname:"测试小数槽手枪",icon:"测试",type:"武器",use:"手枪",weapontype:"手枪",data:{level:1,modslot:1.5,damage:10}},
            {name:"测试非数值槽手枪",displayname:"测试非数值槽手枪",icon:"测试",type:"武器",use:"手枪",weapontype:"手枪",data:{level:1,modslot:"not-a-number",damage:10}},
            {name:"测试NaN槽手枪",displayname:"测试NaN槽手枪",icon:"测试",type:"武器",use:"手枪",weapontype:"手枪",data:{level:1,modslot:Number("not-a-number"),damage:10}},
            {name:"测试正无穷槽手枪",displayname:"测试正无穷槽手枪",icon:"测试",type:"武器",use:"手枪",weapontype:"手枪",data:{level:1,modslot:Number.POSITIVE_INFINITY,damage:10}},
            {name:"测试负无穷槽手枪",displayname:"测试负无穷槽手枪",icon:"测试",type:"武器",use:"手枪",weapontype:"手枪",data:{level:1,modslot:Number.NEGATIVE_INFINITY,damage:10}},
            {name:"测试头盔",displayname:"测试头盔",icon:"测试",type:"防具",use:"头部装备",data:{level:1,modslot:4,defence:10,hp:50,magicdefence:{热:10,基础:5}}},
            // 调制材料与生产 XML 一致归入“收集品 / 材料”；富注释分栏依赖这组权威类型。
            {name:"强化石",displayname:"强化石",icon:"测试",type:"收集品",use:"材料",data:{}},
            {name:"二阶复合防御组件",displayname:"二阶组件",icon:"测试",type:"收集品",use:"材料",data:{}},
            {name:"三阶复合防御组件",displayname:"三阶组件",icon:"测试",type:"收集品",use:"材料",data:{}},
            {name:"四阶复合防御组件",displayname:"四阶组件",icon:"测试",type:"收集品",use:"材料",data:{}},
            {name:"基础导轨",displayname:"基础导轨",icon:"测试",type:"收集品",use:"材料",data:{}},
            {name:"依赖瞄具",displayname:"依赖瞄具",icon:"测试",type:"收集品",use:"材料",data:{}},
            {name:"普通握把",displayname:"人体工学握把",icon:"握把专用图标",type:"收集品",use:"材料",data:{}},
            {name:"光棱射线弹-强化",displayname:"棱镜折射阵列",icon:"全光谱棱镜阵列",type:"收集品",use:"材料",data:{}},
            {name:"光谱射线弹",displayname:"色散射线弹",icon:"棱栅射线弹",type:"收集品",use:"材料",data:{}},
            {name:"光谱射线弹-强化",displayname:"全谱色散引擎",icon:"环式棱栅折射阵列",type:"收集品",use:"材料",data:{}},
            {name:"遗留握柄",displayname:"旧式握柄展示",icon:"旧式握柄图标",type:"收集品",use:"材料",data:{}},
            {name:"级联核心",displayname:"级联核心",icon:"测试",type:"收集品",use:"材料",data:{}},
            {name:"测试增幅插件",displayname:"测试增幅插件",icon:"测试",type:"收集品",use:"材料",data:{}}
        ]);
        _root.物品栏 = {
            背包:new ArrayInventory(null, 50),
            仓库:new ArrayInventory(null, 10),
            战备箱:new ArrayInventory(null, 10)
        };
        _root.收集品栏 = {材料:new DictCollection(null)};
        _root.性别 = "男";
        _root.主线任务进度 = 0;
        _root.主角被动技能 = {铁匠:{启用:false,等级:0}};
        _root.存档系统 = {dirtyMark:false};
        _root._saveExt = {成就:{v:1,cnt:{}}};
        _root.task_chains_progress = {挑战:0};
        _root.基建系统 = {infrastructure:{越野车:false}};
        InventoryPanelService.install();
        EquipmentTuningService.install();
        InventoryPanelService.testOnlyReset();
        EquipmentTuningService.testOnlyReset();
        CharacterBuildService.testOnlyReset();
        PlayerAssetTransaction.resetForTests();
    }

    private static function testSnapshotGenderNormalization():Void {
        resetFixture();
        // ItemUtil 会为缺省 modslot 补旧式默认值；这里删除该补值，模拟
        // 上游权威字段确实缺失的输入，避免把“缺失”误测成合法 3 槽。
        delete ItemUtil.getRawItemData("测试未知槽手枪").data.modslot;
        // 同样在 loader 之后重放畸形权威值，避免 AS2 宽松等值比较把
        // NaN / 非数值输入误判为空值并替换成旧式默认槽数。
        ItemUtil.getRawItemData("测试负数槽手枪").data.modslot = -1;
        ItemUtil.getRawItemData("测试小数槽手枪").data.modslot = 1.5;
        ItemUtil.getRawItemData("测试非数值槽手枪").data.modslot =
            "not-a-number";
        ItemUtil.getRawItemData("测试NaN槽手枪").data.modslot =
            Number("not-a-number");
        ItemUtil.getRawItemData("测试正无穷槽手枪").data.modslot =
            Number.POSITIVE_INFINITY;
        ItemUtil.getRawItemData("测试负无穷槽手枪").data.modslot =
            Number.NEGATIVE_INFINITY;
        _root.物品栏.背包.add(0, equipment("测试手枪A", 1, []));
        _root.物品栏.背包.add(1, equipment("测试未知槽手枪", 1, []));
        _root.物品栏.背包.add(2, equipment("测试负数槽手枪", 1, []));
        _root.物品栏.背包.add(3, equipment("测试小数槽手枪", 1, []));
        _root.物品栏.背包.add(4, equipment("测试非数值槽手枪", 1, []));
        _root.物品栏.背包.add(5, equipment("测试NaN槽手枪", 1, []));
        _root.物品栏.背包.add(6, equipment("测试正无穷槽手枪", 1, []));
        _root.物品栏.背包.add(7, equipment("测试负无穷槽手枪", 1, []));
        var inventory:Object = inventorySnapshot();
        var snapshotParams:Object = params("gender");
        snapshotParams.source = sourceRef(inventory, 0);

        _root.性别 = "女";
        var female:Object = EquipmentTuningService.execute("snapshot", snapshotParams);
        _root.性别 = "female";
        var normalized:Object = EquipmentTuningService.execute("snapshot", snapshotParams);
        var unknownParams:Object = params("gender");
        unknownParams.source = sourceRef(inventory, 1);
        var unknown:Object = EquipmentTuningService.execute("snapshot", unknownParams);
        var malformedSlots:Array = [2, 3, 4, 5, 6, 7];
        var malformedCapacityOmitted:Boolean = true;
        for (var malformedIndex:Number = 0;
                malformedIndex < malformedSlots.length;
                malformedIndex++) {
            var malformedParams:Object =
                params("modslot-malformed-" + malformedIndex);
            malformedParams.source =
                sourceRef(inventory, Number(malformedSlots[malformedIndex]));
            var malformed:Object =
                EquipmentTuningService.execute("snapshot", malformedParams);
            var malformedCurrentOmitted:Boolean = malformed.success
                && !malformed.snapshot.equipment.hasOwnProperty(
                    "modSlotCapacity");
            // 当前项放在左侧，确保前一项失败后仍逐项验证余下夹具。
            malformedCapacityOmitted =
                malformedCurrentOmitted && malformedCapacityOmitted;
        }

        assertTrue(female.success && female.snapshot.gender == "女"
                && female.snapshot.equipment.modSlotCapacity == 4
                && normalized.success && normalized.snapshot.gender == "男"
                && unknown.success
                && !unknown.snapshot.equipment.hasOwnProperty("modSlotCapacity")
                && malformedCapacityOmitted,
            "snapshot 规范化性别、保留 4 槽权威值，并对缺失、负数、小数、非数值、NaN 与正负无穷省略容量字段");
    }

    private static function equipment(name:String, level:Number, mods:Array):BaseItem {
        return new BaseItem(name, {level:level,mods:mods}, 10);
    }

    private static function inventorySnapshot():Object {
        return InventoryPanelService.execute("snapshot", {
            v:1, requests:[{containerId:"背包",offset:0,limit:50}]
        }).snapshots[0];
    }

    private static function sourceRef(snapshot:Object, slot:Number):Object {
        for (var i:Number = 0; i < snapshot.slots.length; i++) {
            if (Number(snapshot.slots[i].physicalSlot) == slot) {
                return {
                    sourceKind:"inventory",
                    containerId:"背包",
                    slot:slot,
                    expectedLease:String(
                        snapshot.slots[i].slotLease)
                };
            }
        }
        return null;
    }

    private static function snapshotMaterialCount(snapshot:Object, itemName:String):Number {
        var rows:Array = snapshot == null ? null : snapshot.materials;
        if (!(rows instanceof Array)) return -1;
        for (var i:Number = 0; i < rows.length; i++) {
            if (String(rows[i].itemName) == itemName) return Number(rows[i].count);
        }
        return -1;
    }

    private static function installWornPublishProbe(
        fixture:Object,
        suffix:String):Object {
        var probe:Object = {
            equipmentPublishes:0,
            materialPublishes:0
        };
        var equipmentHolder:MovieClip = _root.createEmptyMovieClip(
            "__tuningWornEquipment_" + suffix,
            _root.getNextHighestDepth());
        var materialHolder:MovieClip = _root.createEmptyMovieClip(
            "__tuningWornMaterial_" + suffix,
            _root.getNextHighestDepth());
        probe.equipmentHolder = equipmentHolder;
        probe.materialHolder = materialHolder;
        var equipmentDispatcher:LifecycleEventDispatcher =
            new LifecycleEventDispatcher(equipmentHolder);
        var materialDispatcher:LifecycleEventDispatcher =
            new LifecycleEventDispatcher(materialHolder);
        var countEquipment:Function = function():Void {
            probe.equipmentPublishes++;
        };
        var countMaterial:Function = function():Void {
            probe.materialPublishes++;
        };
        equipmentDispatcher.subscribe(
            "ItemAdded", countEquipment);
        equipmentDispatcher.subscribe(
            "ItemRemoved", countEquipment);
        equipmentDispatcher.subscribe(
            "ItemValueChanged", countEquipment);
        materialDispatcher.subscribe(
            "ItemAdded", countMaterial);
        materialDispatcher.subscribe(
            "ItemRemoved", countMaterial);
        materialDispatcher.subscribe(
            "ItemValueChanged", countMaterial);
        fixture.inventory.setDispatcher(
            equipmentDispatcher);
        _root.收集品栏.材料.setDispatcher(
            materialDispatcher);
        return probe;
    }

    private static function removeWornPublishProbe(
        fixture:Object,
        probe:Object):Void {
        fixture.inventory.setDispatcher(null);
        _root.收集品栏.材料.setDispatcher(null);
        probe.equipmentHolder.removeMovieClip();
        probe.materialHolder.removeMovieClip();
    }

    private static function params(view:String):Object {
        return {v:1,panelInstanceId:"test.panel",viewSessionId:view};
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

    private static function webCommit(view:String, operation:String,
                                      sourceSlot:Number, targetSlot:Number,
                                      candidateName:String, targetLevel,
                                      replaceCandidateName:String):Object {
        var inventory:Object = inventorySnapshot();
        var source:Object = sourceRef(inventory, sourceSlot);
        var snapshotParams:Object = params(view);
        snapshotParams.source = source;
        var snapshot:Object = EquipmentTuningService.execute("snapshot", snapshotParams);
        if (!snapshot.success) return {snapshot:snapshot};

        var previewParams:Object = params(view);
        previewParams.operation = operation;
        previewParams.source = source;
        if (targetSlot >= 0) previewParams.target = sourceRef(inventory, targetSlot);
        if (targetLevel != undefined) previewParams.targetLevel = targetLevel;
        if (candidateName != undefined && candidateName != "") {
            var candidates:Array = operation == "install_tier"
                ? snapshot.snapshot.tierCandidates : snapshot.snapshot.modCandidates;
            for (var i:Number = 0; i < candidates.length; i++) {
                if (String(candidates[i].itemName) == candidateName) {
                    previewParams.candidateKey = String(candidates[i].candidateKey);
                    break;
                }
            }
        }
        if (operation == "replace_mod" && replaceCandidateName != undefined
                && replaceCandidateName != "") {
            for (i = 0; i < snapshot.snapshot.modCandidates.length; i++) {
                if (String(snapshot.snapshot.modCandidates[i].itemName) == replaceCandidateName) {
                    previewParams.replaceCandidateKey = String(snapshot.snapshot.modCandidates[i].candidateKey);
                    break;
                }
            }
        }
        var preview:Object = EquipmentTuningService.execute("preview", previewParams);
        if (!preview.success) return {snapshot:snapshot, preview:preview};
        var commitParams:Object = params(view);
        commitParams.expectedTuningToken = preview.tuningToken;
        return {snapshot:snapshot, preview:preview,
            commit:EquipmentTuningService.execute("commit", commitParams)};
    }

    private static function testInstallAndEnhanceCommit():Void {
        resetFixture();
        assertTrue(typeof _root.gameCommands.equipmentTuningSnapshot == "function"
                && typeof _root.gameCommands.equipmentTuningPreview == "function"
                && typeof _root.gameCommands.equipmentTuningCommit == "function"
                && typeof _root.gameCommands.equipmentTuningTooltip == "function"
                && typeof _root.gameCommands.equipmentTuningDetach == "function",
            "安装五个 equipment tuning handler");
        var item:BaseItem = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("强化石", 100);
        var bagRevision:Number = _root.物品栏.背包.getMutationRevision();
        var materialRevision:Number = _root.收集品栏.材料.getMutationRevision();
        var lease:Object = sourceRef(inventorySnapshot(), 0);
        var snapshotParams:Object = params("enhance");
        snapshotParams.source = lease;
        var snap:Object = EquipmentTuningService.execute("snapshot", snapshotParams);
        assertTrue(snap.success && snap.snapshot.enhance.currentLevel == 1
                && snap.snapshot.enhance.maxLevel == 7
                && snap.snapshot.enhance.availableMaxLevel == 7
                && snap.snapshot.enhance.hardMaxLevel == 13
                && snapshotMaterialCount(snap.snapshot, "强化石") == 100,
            "snapshot 投影当前强化度、动态/永久上限与材料持有量");

        var previewParams:Object = params("enhance");
        previewParams.operation = "enhance";
        previewParams.source = lease;
        previewParams.targetLevel = 3;
        var preview:Object = EquipmentTuningService.execute("preview", previewParams);
        assertTrue(preview.success && preview.canCommit == true
                && preview.materials[0].before == 100
                && preview.materials[0].delta == -3
                && item.value.level == 1 && _root.收集品栏.材料.getValue("强化石") == 100,
            "enhance preview 冻结 token/精确 delta 且零写");

        var commitParams:Object = params("enhance");
        commitParams.expectedTuningToken = preview.tuningToken;
        commitParams.writeEpoch = 1;
        var committed:Object = EquipmentTuningService.execute("commit", commitParams);
        assertTrue(committed.success && committed.transactionId != undefined
                && committed.tuningToken == preview.tuningToken
                && committed.before.source.equipment.level == 1
                && committed.after.source.equipment.level == 3,
            "enhance commit 回包满足冻结结构");
        assertTrue(item.value.level == 3 && _root.收集品栏.材料.getValue("强化石") == 97
                && _root.物品栏.背包.getMutationRevision() == bagRevision + 1
                && _root.收集品栏.材料.getMutationRevision() == materialRevision + 1,
            "装备与材料批次各只推进一次 revision");
        assertTrue(item.lastUpdate > 10 && _root.存档系统.dirtyMark == true
                && _root._saveExt.成就.cnt["装备强化次数"] == 1,
            "成功提交更新时间戳、dirty 与正确成就键");

        var replay:Object = EquipmentTuningService.execute("commit", commitParams);
        assertTrue(!replay.success && replay.error == "token_invalid"
                && replay.transactionId == committed.transactionId
                && item.value.level == 3 && _root.收集品栏.材料.getValue("强化石") == 97,
            "token 重放确定拒绝并回同 transactionId");
    }

    private static function testWireShapeAndReconcileBarrier():Void {
        resetFixture();
        var item:BaseItem = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        var lease:Object = sourceRef(inventorySnapshot(), 0);
        var previousServer:Object = _root.server;
        var captured:String = "";
        _root.server = {sendSocketMessage:function(message:String):Boolean {
            captured = message;
            return true;
        }};
        _root.gameCommands.equipmentTuningSnapshot({
            v:1, callId:77, requestCallId:"read.barrier.1", writeEpoch:4,
            panelInstanceId:"test.panel", viewSessionId:"wire", source:lease,
            reconcileAfterCallId:"write.not.sent"
        });
        assertTrue(captured.indexOf('"task":"equipment_tuning_response"') >= 0
                && captured.indexOf('"command":"snapshot"') >= 0
                && captured.indexOf('"callId":77') >= 0
                && captured.indexOf('"panelInstanceId":"test.panel"') >= 0
                && captured.indexOf('"viewSessionId":"wire"') >= 0
                && captured.indexOf('"writeEpoch":4') >= 0,
            "handler 回包携冻结 task/command/call/session/writeEpoch 字段");
        assertTrue(captured.indexOf('"reconciled":true') >= 0
                && captured.indexOf('"reconcileAfterCallId":"write.not.sent"') >= 0,
            "显式 reconcile snapshot 作为有序 barrier 覆盖未送达写");
        assertTrue(captured.indexOf('"requestCallId"') < 0,
            "requestCallId 只进入内部水位账本而不回显");
        captured = "";
        _root.gameCommands.equipmentTuningDetach({
            v:1, callId:78, requestCallId:"detach.1", writeEpoch:5,
            panelInstanceId:"test.panel", viewSessionId:"wire"
        });
        assertTrue(captured.indexOf('"task":"equipment_tuning_response"') >= 0
                && captured.indexOf('"command":"detach"') >= 0
                && captured.indexOf('"callId":78') >= 0
                && captured.indexOf('"panelInstanceId":"test.panel"') >= 0
                && captured.indexOf('"viewSessionId":"wire"') >= 0
                && captured.indexOf('"writeEpoch":5') >= 0
                && captured.indexOf('"success":true') >= 0
                && captured.indexOf('"requestCallId"') < 0,
            "detach handler 只返回冻结 common shape 并确认生命周期屏障");
        _root.server = previousServer;
    }

    private static function testSnapshotAndDetachInvalidateTokens():Void {
        resetFixture();
        var item:BaseItem = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("强化石", 10);
        var lease:Object = sourceRef(inventorySnapshot(), 0);
        var snapshotParams:Object = params("snapshot-invalidate");
        snapshotParams.source = lease;
        EquipmentTuningService.execute("snapshot", snapshotParams);
        var previewParams:Object = params("snapshot-invalidate");
        previewParams.operation = "enhance";
        previewParams.source = lease;
        previewParams.targetLevel = 2;
        var preview:Object = EquipmentTuningService.execute("preview", previewParams);
        EquipmentTuningService.execute("snapshot", snapshotParams);
        var commitParams:Object = params("snapshot-invalidate");
        commitParams.expectedTuningToken = preview.tuningToken;
        var invalidated:Object = EquipmentTuningService.execute("commit", commitParams);
        assertTrue(preview.success && !invalidated.success && invalidated.error == "token_invalid"
                && item.value.level == 1 && _root.收集品栏.材料.getValue("强化石") == 10,
            "同 session fresh snapshot 撤销旧 preview token 且 commit 零写");

        preview = EquipmentTuningService.execute("preview", previewParams);
        var detachParams:Object = params("snapshot-invalidate");
        var detached:Object = EquipmentTuningService.execute("detach", detachParams);
        var repeated:Object = EquipmentTuningService.execute("detach", detachParams);
        commitParams.expectedTuningToken = preview.tuningToken;
        invalidated = EquipmentTuningService.execute("commit", commitParams);
        assertTrue(preview.success && detached.success && repeated.success
                && !invalidated.success && invalidated.error == "view_session_expired"
                && item.value.level == 1 && _root.收集品栏.材料.getValue("强化石") == 10,
            "detach 幂等撤销 session/plan，旧 token 后续 commit 必败且零写");
    }

    private static function testPreviewAttemptRevokesPreviousToken():Void {
        resetFixture();
        var item:BaseItem = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("强化石", 10);
        var lease:Object = sourceRef(inventorySnapshot(), 0);
        var snapshotParams:Object = params("preview-generation");
        snapshotParams.source = lease;
        EquipmentTuningService.execute("snapshot", snapshotParams);

        var previewAParams:Object = params("preview-generation");
        previewAParams.operation = "enhance";
        previewAParams.source = lease;
        previewAParams.targetLevel = 2;
        var previewA:Object = EquipmentTuningService.execute(
            "preview", previewAParams);
        var previewBParams:Object = params("preview-generation");
        previewBParams.operation = "enhance";
        previewBParams.source = lease;
        previewBParams.targetLevel = 3;
        var previewB:Object = EquipmentTuningService.execute(
            "preview", previewBParams);
        var commitAParams:Object = params("preview-generation");
        commitAParams.expectedTuningToken = previewA.tuningToken;
        var commitA:Object = EquipmentTuningService.execute(
            "commit", commitAParams);
        var commitBParams:Object = params("preview-generation");
        commitBParams.expectedTuningToken = previewB.tuningToken;
        var commitB:Object = EquipmentTuningService.execute(
            "commit", commitBParams);
        assertTrue(previewA.success && previewB.success
                && !commitA.success && commitA.error == "token_invalid"
                && commitB.success && item.value.level == 3
                && _root.收集品栏.材料.getValue("强化石") == 7,
            "成功 preview B 立即替代 A；A 零写拒绝且 B 仍可一次提交");

        resetFixture();
        item = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("强化石", 10);
        lease = sourceRef(inventorySnapshot(), 0);
        snapshotParams = params("preview-failure-generation");
        snapshotParams.source = lease;
        EquipmentTuningService.execute("snapshot", snapshotParams);
        previewAParams = params("preview-failure-generation");
        previewAParams.operation = "enhance";
        previewAParams.source = lease;
        previewAParams.targetLevel = 2;
        previewA = EquipmentTuningService.execute(
            "preview", previewAParams);
        var failedParams:Object = params("preview-failure-generation");
        failedParams.operation = "enhance";
        failedParams.source = lease;
        failedParams.targetLevel = 99;
        var failedPreview:Object = EquipmentTuningService.execute(
            "preview", failedParams);
        commitAParams = params("preview-failure-generation");
        commitAParams.expectedTuningToken = previewA.tuningToken;
        commitA = EquipmentTuningService.execute(
            "commit", commitAParams);
        assertTrue(previewA.success && !failedPreview.success
                && !commitA.success && commitA.error == "token_invalid"
                && item.value.level == 1
                && _root.收集品栏.材料.getValue("强化石") == 10,
            "同 session 新 preview 即使业务失败也撤销 A，旧 token 后续提交零写拒绝");
    }

    private static function testSameLevelConvertNoOp():Void {
        resetFixture();
        var first:BaseItem = equipment("测试手枪A", 2, []);
        var second:BaseItem = equipment("测试手枪B", 2, []);
        _root.物品栏.背包.add(0, first);
        _root.物品栏.背包.add(1, second);
        var bagRevision:Number = _root.物品栏.背包.getMutationRevision();
        var materialRevision:Number = _root.收集品栏.材料.getMutationRevision();
        var firstTime:Number = first.lastUpdate;
        var secondTime:Number = second.lastUpdate;
        var inventory:Object = inventorySnapshot();
        var source:Object = sourceRef(inventory, 0);
        var target:Object = sourceRef(inventory, 1);
        var previewParams:Object = params("convert");
        previewParams.operation = "convert";
        previewParams.source = source;
        previewParams.target = target;
        var preview:Object = EquipmentTuningService.execute("preview", previewParams);
        var commitParams:Object = params("convert");
        commitParams.expectedTuningToken = preview.tuningToken;
        var committed:Object = EquipmentTuningService.execute("commit", commitParams);
        assertTrue(preview.success && preview.noOp == true && committed.success && committed.noOp == true,
            "同级强化度转换返回确定 no-op");
        assertTrue(_root.物品栏.背包.getMutationRevision() == bagRevision
                && _root.收集品栏.材料.getMutationRevision() == materialRevision
                && first.lastUpdate == firstTime && second.lastUpdate == secondTime
                && _root.存档系统.dirtyMark == false,
            "同级 no-op 不写 revision、时间戳或 dirty");
    }

    private static function testStaleMaterialAndFailureRollback():Void {
        resetFixture();
        var item:BaseItem = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("强化石", 10);
        var lease:Object = sourceRef(inventorySnapshot(), 0);
        var previewParams:Object = params("stale");
        previewParams.operation = "enhance";
        previewParams.source = lease;
        previewParams.targetLevel = 2;
        var preview:Object = EquipmentTuningService.execute("preview", previewParams);
        var bagRevision:Number = _root.物品栏.背包.getMutationRevision();
        _root.收集品栏.材料.addValue("强化石", -1);
        var commitParams:Object = params("stale");
        commitParams.expectedTuningToken = preview.tuningToken;
        var stale:Object = EquipmentTuningService.execute("commit", commitParams);
        assertTrue(!stale.success && stale.error == "stale_state"
                && item.value.level == 1 && _root.物品栏.背包.getMutationRevision() == bagRevision
                && _root.存档系统.dirtyMark == false,
            "材料精确 before 变化使 commit 零装备写并消费 token");
        var replay:Object = EquipmentTuningService.execute("commit", commitParams);
        assertTrue(!replay.success && replay.error == "token_invalid", "stale token 不可重放");

        resetFixture();
        item = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("强化石", 10);
        lease = sourceRef(inventorySnapshot(), 0);
        previewParams = params("rollback");
        previewParams.operation = "enhance";
        previewParams.source = lease;
        previewParams.targetLevel = 2;
        preview = EquipmentTuningService.execute("preview", previewParams);
        bagRevision = _root.物品栏.背包.getMutationRevision();
        var materialRevision:Number = _root.收集品栏.材料.getMutationRevision();
        EquipmentTuningService.testOnlyFailNextCommit();
        commitParams = params("rollback");
        commitParams.expectedTuningToken = preview.tuningToken;
        var failed:Object = EquipmentTuningService.execute("commit", commitParams);
        assertTrue(!failed.success && failed.error == "commit_failed"
                && item.value.level == 1 && _root.收集品栏.材料.getValue("强化石") == 10
                && _root.物品栏.背包.getMutationRevision() == bagRevision
                && _root.收集品栏.材料.getMutationRevision() == materialRevision
                && _root.存档系统.dirtyMark == false,
            "确定性失败注入发生于任何装备/材料写之前");
    }

    private static function testTierProgression():Void {
        resetFixture();
        var item:BaseItem = equipment("测试头盔", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("二阶复合防御组件", 1);
        _root.收集品栏.材料.add("三阶复合防御组件", 1);
        _root.收集品栏.材料.add("四阶复合防御组件", 1);
        var denied:Object = webCommit(
            "tier-denied", "install_tier", 0, -1,
            "三阶复合防御组件", undefined);
        assertTrue(denied.preview != null
                && !denied.preview.success
                && denied.preview.error == "invalid_transition"
                && item.value.tier == undefined
                && _root.收集品栏.材料.getValue("三阶复合防御组件") == 1,
            "无 tier 装备不能跳过二阶");
        var tier2:Object = webCommit(
            "tier-2", "install_tier", 0, -1,
            "二阶复合防御组件", undefined);
        var tier3:Object = webCommit(
            "tier-3", "install_tier", 0, -1,
            "三阶复合防御组件", undefined);
        var tier4:Object = webCommit(
            "tier-4", "install_tier", 0, -1,
            "四阶复合防御组件", undefined);
        assertTrue(tier2.commit.success && tier3.commit.success
                && tier4.commit.success && item.value.tier == "四阶"
                && _root.收集品栏.材料.getValue("二阶复合防御组件") == 0
                && _root.收集品栏.材料.getValue("三阶复合防御组件") == 0
                && _root.收集品栏.材料.getValue("四阶复合防御组件") == 0,
            "tier 严格按二阶→三阶→四阶推进并逐次消费材料");
        assertTrue(_root._saveExt.成就.cnt["装备进阶次数"] == 3,
            "成功进阶只记录装备进阶次数");
    }

    private static function statRow(stats, key:String):Object {
        if (!(stats instanceof Array)) return null;
        for (var i:Number = 0; i < stats.length; i++) {
            if (String(stats[i].key) == key) return stats[i];
        }
        return null;
    }

    private static function testPreviewStatRows():Void {
        resetFixture();
        var item:BaseItem = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("强化石", 100);
        var enhance:Object = webCommit("stats-enhance", "enhance", 0, -1, "", 3, "");
        var beforeStats:Array = enhance.preview.success
            ? enhance.preview.before.source.equipment.stats : null;
        var afterStats:Array = enhance.preview.success
            ? enhance.preview.after.source.equipment.stats : null;
        var beforeDamage:Object = statRow(beforeStats, "damage");
        var afterDamage:Object = statRow(afterStats, "damage");
        assertTrue(enhance.preview.success && enhance.commit.success
                && beforeStats instanceof Array && afterStats instanceof Array
                && beforeStats.length == afterStats.length
                && beforeDamage != null && afterDamage != null
                && Math.abs(Number(beforeDamage.value) - 10) < 0.0001
                && Math.abs(Number(afterDamage.value) - 11) < 0.0001
                && String(beforeDamage.label) == "伤害加成",
            "强化 preview 投影结构化属性并按倍率试算（伤害加成 10 × 1.06 四舍五入为 11）");
        assertTrue(enhance.snapshot.success
                && !enhance.snapshot.snapshot.equipment.hasOwnProperty("stats"),
            "snapshot 装备投影不携带 stats 字段（载荷最小化）");

        resetFixture();
        var tierGun:BaseItem = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, tierGun);
        _root.收集品栏.材料.add("二阶复合防御组件", 1);
        var gunTier:Object = webCommit(
            "stats-gun-tier", "install_tier", 0, -1, "二阶复合防御组件", undefined);
        var gunBefore:Array = gunTier.preview.success
            ? gunTier.preview.before.source.equipment.stats : null;
        var gunAfter:Array = gunTier.preview.success
            ? gunTier.preview.after.source.equipment.stats : null;
        var rateBefore:Object = statRow(gunBefore, "fireRate");
        var rateAfter:Object = statRow(gunAfter, "fireRate");
        assertTrue(gunTier.preview.success && gunTier.commit.success
                && statRow(gunBefore, "interval") == null
                && statRow(gunAfter, "interval") == null
                && rateBefore != null && rateAfter != null
                && String(rateBefore.label) == "射速（发/秒）"
                && Math.abs(Number(rateBefore.value) - 10) < 0.0001
                && Math.abs(Number(rateAfter.value) - 12.9) < 0.0001
                && Math.abs(Number(statRow(gunBefore, "impact").value) - 5) < 0.0001
                && Math.abs(Number(statRow(gunAfter, "impact").value) - 20) < 0.0001,
            "枪械进阶 preview 按运行时口径显示射速与实际冲击力，不泄露 interval/impact 原始参数");

        resetFixture();
        var helm:BaseItem = equipment("测试头盔", 1, []);
        _root.物品栏.背包.add(0, helm);
        _root.收集品栏.材料.add("二阶复合防御组件", 1);
        var tier:Object = webCommit(
            "stats-tier", "install_tier", 0, -1, "二阶复合防御组件", undefined);
        var tierBefore:Array = tier.preview.success
            ? tier.preview.before.source.equipment.stats : null;
        var tierAfter:Array = tier.preview.success
            ? tier.preview.after.source.equipment.stats : null;
        var tierAfterClean:Boolean = true;
        if (tierAfter instanceof Array) {
            for (var li:Number = 0; li < tierAfter.length; li++) {
                if (String(tierAfter[li].label).indexOf("<") >= 0) {
                    tierAfterClean = false;
                }
            }
        }
        var mdHeat:Object = statRow(tierBefore, "magicdefence.热");
        var mdBase:Object = statRow(tierBefore, "magicdefence.基础");
        assertTrue(tier.preview.success && tier.commit.success
                && Math.abs(Number(statRow(tierBefore, "defence").value) - 10) < 0.0001
                && Math.abs(Number(statRow(tierAfter, "defence").value) - 80) < 0.0001
                && Math.abs(Number(statRow(tierAfter, "level").value) - 12) < 0.0001
                && String(statRow(tierAfter, "hp").label) == "HP"
                && tierAfterClean
                && mdHeat != null && String(mdHeat.label) == "魔法抗性·热"
                && Math.abs(Number(mdHeat.value) - 10) < 0.0001
                && mdBase != null && String(mdBase.label) == "魔法抗性·能量"
                && Math.abs(Number(mdBase.value) - 5) < 0.0001,
            "进阶 preview 覆盖 defence/等级限制、剥离 label 标签并拍平魔法抗性");

        resetFixture();
        var modded:BaseItem = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, modded);
        _root.收集品栏.材料.add("测试增幅插件", 1);
        var install:Object = webCommit(
            "stats-mod", "install_mod", 0, -1, "测试增幅插件", undefined);
        assertTrue(install.preview.success && install.commit.success
                && statRow(install.preview.before.source.equipment.stats, "vampirism") == null
                && Math.abs(Number(statRow(
                    install.preview.after.source.equipment.stats,
                    "vampirism").value) - 3) < 0.0001,
            "插件 preview 在安装后新增对应属性行");
        var detach:Object = webCommit(
            "stats-detach", "detach_mod", 0, -1, "测试增幅插件", undefined);
        assertTrue(detach.preview.success && detach.commit.success
                && statRow(detach.preview.before.source.equipment.stats, "vampirism") != null
                && statRow(detach.preview.after.source.equipment.stats, "vampirism") == null,
            "插件 preview 在卸下后移除对应属性行");

        // —— 候选 tooltip 试算 diff（注释图片栏数据源）——
        var tipLease:Object = sourceRef(inventorySnapshot(), 0);
        var tipSnapshotParams:Object = params("stats-tip");
        tipSnapshotParams.source = tipLease;
        var tipSnap:Object = EquipmentTuningService.execute("snapshot", tipSnapshotParams);
        var tipKey:String = "";
        for (var ti:Number = 0; ti < tipSnap.snapshot.modCandidates.length; ti++) {
            if (String(tipSnap.snapshot.modCandidates[ti].itemName) == "测试增幅插件") {
                tipKey = String(tipSnap.snapshot.modCandidates[ti].candidateKey);
                break;
            }
        }
        var tipParams:Object = params("stats-tip");
        tipParams.candidateKey = tipKey;
        tipParams.source = tipLease;
        var tip:Object = EquipmentTuningService.execute("tooltip", tipParams);
        assertTrue(tipSnap.success && tip.success
                && tip.statsBefore instanceof Array && tip.statsAfter instanceof Array
                && statRow(tip.statsBefore, "vampirism") == null
                && Math.abs(Number(statRow(tip.statsAfter, "vampirism").value) - 3) < 0.0001,
            "候选 tooltip 携带安装前后属性投影（材料缺失不阻挡试算）");
        var legacyTipParams:Object = params("stats-tip");
        legacyTipParams.candidateKey = tipKey;
        var legacyTip:Object = EquipmentTuningService.execute("tooltip", legacyTipParams);
        assertTrue(legacyTip.success && legacyTip.statsBefore == undefined
                && legacyTip.statsAfter == undefined,
            "无 source 的旧形态 tooltip 不携带属性投影");
    }

    private static function testCandidateAvailabilityRequiresOwnedMaterial():Void {
        resetFixture();
        var item:BaseItem = equipment("测试头盔", 1, []);
        _root.物品栏.背包.add(0, item);
        var lease:Object = sourceRef(inventorySnapshot(), 0);
        var snapshotParams:Object = params("availability");
        snapshotParams.source = lease;
        var snapshot:Object = EquipmentTuningService.execute("snapshot", snapshotParams).snapshot;
        var tierCandidate:Object = null;
        for (var i:Number = 0; i < snapshot.tierCandidates.length; i++) {
            if (snapshot.tierCandidates[i].itemName == "二阶复合防御组件") {
                tierCandidate = snapshot.tierCandidates[i];
            }
        }
        assertTrue(tierCandidate != null && tierCandidate.owned == 0
                && tierCandidate.available == false && tierCandidate.reason == "material_missing",
            "tier 规则允许但材料为零时不可点击");

        resetFixture();
        item = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        lease = sourceRef(inventorySnapshot(), 0);
        snapshotParams = params("availability");
        snapshotParams.source = lease;
        snapshot = EquipmentTuningService.execute("snapshot", snapshotParams).snapshot;
        var modCandidate:Object = null;
        for (i = 0; i < snapshot.modCandidates.length; i++) {
            if (snapshot.modCandidates[i].itemName == "普通握把") {
                modCandidate = snapshot.modCandidates[i];
            }
        }
        var identityProjectionOk:Boolean = modCandidate != null && modCandidate.owned == 0
                && modCandidate.available == false && modCandidate.reason == "material_missing"
                && modCandidate.grade == "medium" && modCandidate.scope == "firearm"
                && modCandidate.role == "precision" && modCandidate.symbol == "triangle-outline"
                && modCandidate.displayName == "人体工学握把"
                && modCandidate.icon == "握把专用图标";
        var identityFixtures:Array = [
            {itemName:"光棱射线弹-强化", displayName:"棱镜折射阵列", icon:"全光谱棱镜阵列"},
            {itemName:"光谱射线弹", displayName:"色散射线弹", icon:"棱栅射线弹"},
            {itemName:"光谱射线弹-强化", displayName:"全谱色散引擎", icon:"环式棱栅折射阵列"}
        ];
        for (var fixtureIndex:Number = 0; fixtureIndex < identityFixtures.length; fixtureIndex++) {
            var expectedIdentity:Object = identityFixtures[fixtureIndex];
            var projectedIdentity:Object = null;
            for (i = 0; i < snapshot.modCandidates.length; i++) {
                if (snapshot.modCandidates[i].itemName == expectedIdentity.itemName) {
                    projectedIdentity = snapshot.modCandidates[i];
                    break;
                }
            }
            identityProjectionOk = identityProjectionOk && projectedIdentity != null
                && String(projectedIdentity.candidateKey).indexOf("mod.") == 0
                && projectedIdentity.itemName == expectedIdentity.itemName
                && projectedIdentity.displayName == expectedIdentity.displayName
                && projectedIdentity.icon == expectedIdentity.icon;
        }
        var selectorDriftParams:Object = params("availability");
        selectorDriftParams.operation = "install_mod";
        selectorDriftParams.source = lease;
        selectorDriftParams.candidateKey = "棱镜折射阵列";
        var selectorDrift:Object = EquipmentTuningService.execute(
            "preview", selectorDriftParams);
        identityProjectionOk = identityProjectionOk && !selectorDrift.success
            && selectorDrift.error == "unknown_candidate";

        ItemUtil.getRawItemData("普通握把").displayname = " \t ";
        ItemUtil.getRawItemData("普通握把").icon = " undefined ";
        ItemUtil.getRawItemData("光棱射线弹-强化").displayname =
            " UnDeFiNeD ";
        ItemUtil.getRawItemData("光棱射线弹-强化").icon = "\r\n";
        snapshotParams = params("availability-sentinel");
        snapshotParams.source = lease;
        snapshot = EquipmentTuningService.execute(
            "snapshot", snapshotParams).snapshot;
        var fallbackGrip:Object = null;
        var fallbackRay:Object = null;
        for (i = 0; i < snapshot.modCandidates.length; i++) {
            if (snapshot.modCandidates[i].itemName == "普通握把") {
                fallbackGrip = snapshot.modCandidates[i];
            }
            if (snapshot.modCandidates[i].itemName ==
                    "光棱射线弹-强化") {
                fallbackRay = snapshot.modCandidates[i];
            }
        }
        var fallbackTooltipParams:Object = params(
            "availability-sentinel");
        fallbackTooltipParams.candidateKey =
            String(fallbackGrip.candidateKey);
        var fallbackTooltip:Object = EquipmentTuningService.execute(
            "tooltip", fallbackTooltipParams);
        identityProjectionOk = identityProjectionOk
            && fallbackGrip.displayName == "普通握把"
            && fallbackGrip.icon == "普通握把"
            && fallbackRay.displayName == "光棱射线弹-强化"
            && fallbackRay.icon == "光棱射线弹-强化"
            && fallbackTooltip.success
            && fallbackTooltip.text == "普通握把";
        assertTrue(identityProjectionOk,
            "mod 三名全异候选分工投影，哨兵展示叶回退内部名，且显示名不能代替 candidateKey");

        ItemUtil.getRawItemData("普通握把").displayname = 73;
        ItemUtil.getRawItemData("普通握把").icon = {bad:true};
        ItemUtil.getRawItemData("测试手枪A").displayname = {bad:true};
        ItemUtil.getRawItemData("测试手枪A").icon = 74;
        ItemUtil.getRawItemData("强化石").displayname = 75;
        ItemUtil.getRawItemData("强化石").icon = {bad:true};
        snapshotParams = params("availability-wrong-type");
        snapshotParams.source = lease;
        snapshot = EquipmentTuningService.execute(
            "snapshot", snapshotParams).snapshot;
        var wrongTypeGrip:Object = null;
        var wrongTypeStone:Object = null;
        for (i = 0; i < snapshot.modCandidates.length; i++) {
            if (snapshot.modCandidates[i].itemName == "普通握把") {
                wrongTypeGrip = snapshot.modCandidates[i];
                break;
            }
        }
        for (i = 0; i < snapshot.materials.length; i++) {
            if (snapshot.materials[i].itemName == "强化石") {
                wrongTypeStone = snapshot.materials[i];
                break;
            }
        }
        assertTrue(wrongTypeGrip != null && wrongTypeStone != null
                && wrongTypeGrip.displayName == "普通握把"
                && wrongTypeGrip.icon == "普通握把"
                && snapshot.equipment.displayName == "测试手枪A"
                && snapshot.equipment.icon == "测试手枪A"
                && wrongTypeStone.displayName == "强化石"
                && wrongTypeStone.icon == "强化石",
            "legacy 展示字段仅接收 string；number/object 在候选、装备与材料投影均回退内部名");
        var wrongTypeTooltipParams:Object = params(
            "availability-wrong-type");
        wrongTypeTooltipParams.candidateKey =
            String(wrongTypeGrip.candidateKey);
        var wrongTypeTooltip:Object = EquipmentTuningService.execute(
            "tooltip", wrongTypeTooltipParams);
        assertTrue(wrongTypeTooltip.success
                && wrongTypeTooltip.text == "普通握把",
            "tooltip 不把 number/object legacy 展示字段强转为伪身份");
        _root.收集品栏.材料.add("普通握把", 1);
        snapshotParams = params("availability");
        snapshotParams.source = sourceRef(inventorySnapshot(), 0);
        snapshot = EquipmentTuningService.execute("snapshot", snapshotParams).snapshot;
        for (i = 0; i < snapshot.modCandidates.length; i++) {
            if (snapshot.modCandidates[i].itemName == "普通握把") {
                modCandidate = snapshot.modCandidates[i];
            }
        }
        assertTrue(modCandidate.owned == 1 && modCandidate.available == true
                && modCandidate.reason == "",
            "规则允许且材料充足时 mod 候选可点击");
    }

    private static function testWebCommitOperationMatrix():Void {
        resetFixture();
        var item:BaseItem = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("强化石", 10);
        var result:Object = webCommit("matrix-enhance", "enhance", 0, -1, "", 2);
        assertTrue(result.commit.success && item.value.level == 2
                && _root.收集品栏.材料.getValue("强化石") == 9,
            "Web enhance snapshot→preview→commit 成功");

        resetFixture();
        var target:BaseItem = equipment("测试手枪B", 5, []);
        item = equipment("测试手枪A", 2, []);
        _root.物品栏.背包.add(0, item);
        _root.物品栏.背包.add(1, target);
        result = webCommit("matrix-convert", "convert", 0, 1, "", undefined);
        assertTrue(result.commit.success && result.commit.noOp == false
                && item.value.level == 5 && target.value.level == 2,
            "Web convert 真实交换两件装备强化度");

        resetFixture();
        item = equipment("测试头盔", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("二阶复合防御组件", 1);
        result = webCommit("matrix-tier", "install_tier", 0, -1, "二阶复合防御组件", undefined);
        assertTrue(result.commit.success && item.value.tier == "二阶"
                && _root.收集品栏.材料.getValue("二阶复合防御组件") == 0,
            "Web install_tier 消费候选材料并安装二阶");

        resetFixture();
        item = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("普通握把", 1);
        result = webCommit("matrix-install-mod", "install_mod", 0, -1, "普通握把", undefined);
        var installedSuccess:Boolean = result.commit.success && item.value.mods.length == 1
            && item.value.mods[0] == "普通握把"
            && _root.收集品栏.材料.getValue("普通握把") == 0;
        _root.收集品栏.材料.add("级联核心", 1);
        result = webCommit("matrix-replace-mod", "replace_mod", 0, -1,
            "级联核心", undefined, "普通握把");
        assertTrue(installedSuccess && result.preview.success && result.commit.success
                && result.preview.removedMods.length == 1
                && result.preview.removedMods[0] == "普通握把"
                && item.value.mods.length == 1 && item.value.mods[0] == "级联核心"
                && _root.收集品栏.材料.getValue("普通握把") == 1
                && _root.收集品栏.材料.getValue("级联核心") == 0
                && _root._saveExt.成就.cnt["配件安装次数"] == 2,
            "Web install_mod 与 replace_mod 均以单次事务消费新件、返还旧件并提交最终配置");

        resetFixture();
        item = equipment("测试手枪A", 1, ["基础导轨","依赖瞄具","普通握把"]);
        _root.物品栏.背包.add(0, item);
        result = webCommit("matrix-detach-mod", "detach_mod", 0, -1, "基础导轨", undefined);
        assertTrue(result.commit.success && item.value.mods.length == 1
                && item.value.mods[0] == "普通握把"
                && _root.收集品栏.材料.getValue("基础导轨") == 1
                && _root.收集品栏.材料.getValue("依赖瞄具") == 1,
            "Web detach_mod 返还目标及一跳依赖配件");

        resetFixture();
        item = equipment("测试手枪A", 1, ["基础导轨","普通握把"]);
        _root.物品栏.背包.add(0, item);
        result = webCommit("matrix-detach-all", "detach_all_mods", 0, -1, "", undefined);
        assertTrue(result.commit.success && item.value.mods.length == 0
                && _root.收集品栏.材料.getValue("基础导轨") == 1
                && _root.收集品栏.材料.getValue("普通握把") == 1,
            "Web detach_all_mods 原子返还全部配件");
    }

    private static function testOwnershipFlowProjection():Void {
        resetFixture();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        var item:BaseItem = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("普通握把", 1);
        var result:Object = webCommit(
            "ownership-install", "install_mod", 0, -1,
            "普通握把", undefined);
        assertTrue(result.commit.success && receipts.length == 0,
            "配件从材料栏嵌入装备属于纯迁移，不发布 loss");

        resetFixture();
        receipts = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        item = equipment("测试手枪A", 1, ["基础导轨","普通握把"]);
        _root.物品栏.背包.add(0, item);
        result = webCommit(
            "ownership-detach", "detach_all_mods", 0, -1,
            "", undefined);
        assertTrue(result.commit.success && receipts.length == 0,
            "配件从装备返还材料栏属于纯迁移，不发布 gain");

        resetFixture();
        receipts = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        item = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("强化石", 10);
        result = webCommit(
            "ownership-enhance", "enhance", 0, -1,
            "", 2);
        assertTrue(result.commit.success && receipts.length == 1
                && receipts[0].effects.length == 1
                && receipts[0].effects[0].direction == "loss"
                && receipts[0].effects[0].name == "强化石"
                && receipts[0].effects[0].count == 1,
            "不可回收强化材料仍发布真实 loss");
    }

    private static function testDetachPolicySemantics():Void {
        resetFixture();
        var item:BaseItem = equipment("测试手枪A", 1, ["基础导轨","依赖瞄具","普通握把"]);
        _root.物品栏.背包.add(0, item);
        var detached:Object = webCommit(
            "detach-policy-direct", "detach_mod", 0, -1,
            "基础导轨", undefined);
        assertTrue(detached.commit.success
                && item.value.mods.length == 1 && item.value.mods[0] == "普通握把"
                && _root.收集品栏.材料.getValue("基础导轨") == 1
                && _root.收集品栏.材料.getValue("依赖瞄具") == 1,
            "卸载有依赖插件时保持冻结策略：目标 + 一跳直接依赖");

        resetFixture();
        item = equipment("测试手枪A", 1, ["级联核心","普通握把"]);
        _root.物品栏.背包.add(0, item);
        detached = webCommit(
            "detach-policy-cascade", "detach_mod", 0, -1,
            "级联核心", undefined);
        assertTrue(detached.commit.success && item.value.mods.length == 0
                && _root.收集品栏.材料.getValue("级联核心") == 1
                && _root.收集品栏.材料.getValue("普通握把") == 1,
            "无依赖且 detachPolicy=cascade 时卸下全部插件");

        resetFixture();
        item = equipment("测试手枪A", 1, ["基础导轨","依赖瞄具","普通握把"]);
        _root.物品栏.背包.add(0, item);
        var all:Object = webCommit(
            "detach-policy-all", "detach_all_mods", 0, -1,
            "", undefined);
        assertTrue(all.commit.success && item.value.mods.length == 0
                && _root.收集品栏.材料.getValue("基础导轨") == 1
                && _root.收集品栏.材料.getValue("依赖瞄具") == 1
                && _root.收集品栏.材料.getValue("普通握把") == 1,
            "一键卸下在同一材料 batch 中返还全部插件");

        resetFixture();
        item = equipment("测试手枪A", 1, ["遗留握柄"]);
        _root.物品栏.背包.add(0, item);
        var historicalSnapshotParams:Object = params(
            "detach-policy-historical-snapshot");
        historicalSnapshotParams.source = sourceRef(
            inventorySnapshot(), 0);
        var historicalPreSnapshot:Object = EquipmentTuningService.execute(
            "snapshot", historicalSnapshotParams).snapshot;
        var historicalPreMaterial:Object = null;
        for (var historicalMaterialIndex:Number = 0;
                historicalMaterialIndex
                    < historicalPreSnapshot.materials.length;
                historicalMaterialIndex++) {
            if (historicalPreSnapshot.materials[
                    historicalMaterialIndex].itemName
                    == "遗留握柄") {
                historicalPreMaterial = historicalPreSnapshot.materials[
                    historicalMaterialIndex];
                break;
            }
        }
        var historical:Object = webCommit(
            "detach-policy-historical", "detach_all_mods", 0, -1,
            "", undefined);
        var historicalPostMaterial:Object = null;
        var historicalSnapshotMaterials:Array = historical.commit != null
                && historical.commit.snapshot != null
            ? historical.commit.snapshot.materials : [];
        for (var materialIndex:Number = 0;
                materialIndex < historicalSnapshotMaterials.length;
                materialIndex++) {
            if (historicalSnapshotMaterials[materialIndex].itemName
                    == "遗留握柄") {
                historicalPostMaterial =
                    historicalSnapshotMaterials[materialIndex];
                break;
            }
        }
        assertTrue(historical.commit != null && historical.commit.success
                && item.value.mods.length == 0
                && historicalPreMaterial != null
                && historicalPreMaterial.displayName
                    == "旧式握柄展示"
                && historicalPreMaterial.icon
                    == "旧式握柄图标"
                && historicalPreMaterial.count == 0
                && historical.commit.materials[0].displayName
                    == "旧式握柄展示"
                && historical.commit.materials[0].icon
                    == "旧式握柄图标"
                && historicalPostMaterial != null
                && historicalPostMaterial.displayName
                    == "旧式握柄展示"
                && historicalPostMaterial.icon
                    == "旧式握柄图标"
                && historicalPostMaterial.count == 1,
            "已退出可安装池的历史插件在 pre-preview 与 post snapshot 均覆盖返还材料三元身份及计数");
    }

    private static function testWebInstallModAndTooltip():Void {
        resetFixture();
        var item:BaseItem = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("普通握把", 1);
        var lease:Object = sourceRef(inventorySnapshot(), 0);
        var snapshotParams:Object = params("install_mod");
        snapshotParams.source = lease;
        var snapshot:Object = EquipmentTuningService.execute("snapshot", snapshotParams);
        var candidateKey:String = "";
        var snapshotMaterial:Object = null;
        for (var i:Number = 0; i < snapshot.snapshot.modCandidates.length; i++) {
            var candidate:Object = snapshot.snapshot.modCandidates[i];
            if (candidate.itemName == "普通握把") candidateKey = String(candidate.candidateKey);
        }
        for (i = 0; i < snapshot.snapshot.materials.length; i++) {
            if (snapshot.snapshot.materials[i].itemName == "普通握把") {
                snapshotMaterial = snapshot.snapshot.materials[i];
                break;
            }
        }
        var tooltipParams:Object = params("install_mod");
        tooltipParams.candidateKey = candidateKey;
        var tooltip:Object = EquipmentTuningService.execute("tooltip", tooltipParams);
        assertTrue(candidateKey.indexOf("mod.") == 0 && tooltip.success
                && tooltip.candidateKey == candidateKey
                && typeof tooltip.introHTML == "string" && tooltip.introHTML.length > 0
                && typeof tooltip.descHTML == "string" && tooltip.descHTML.length > 0
                && tooltip.itemType == "收集品" && tooltip.itemUse == "材料"
                && typeof tooltip.text == "string",
            "snapshot 只暴露 ASCII opaque candidateKey，tooltip 只保留 intro/desc 分段与 plain text");
        var previewParams:Object = params("install_mod");
        previewParams.operation = "install_mod";
        previewParams.source = lease;
        previewParams.candidateKey = candidateKey;
        var preview:Object = EquipmentTuningService.execute("preview", previewParams);
        var commitParams:Object = params("install_mod");
        commitParams.expectedTuningToken = preview.tuningToken;
        var committed:Object = EquipmentTuningService.execute("commit", commitParams);
        assertTrue(preview.success && committed.success
                && snapshotMaterial != null
                && snapshotMaterial.itemName == "普通握把"
                && snapshotMaterial.displayName == "人体工学握把"
                && snapshotMaterial.icon == "握把专用图标"
                && preview.materials[0].itemName == "普通握把"
                && preview.materials[0].displayName == "人体工学握把"
                && preview.materials[0].icon == "握把专用图标"
                && committed.materials[0].itemName == "普通握把"
                && committed.materials[0].displayName == "人体工学握把"
                && committed.materials[0].icon == "握把专用图标"
                && item.value.mods.length == 1 && item.value.mods[0] == "普通握把"
                && _root.收集品栏.材料.getValue("普通握把") == 0,
            "Web candidate 驱动 install_mod，且 snapshot/preview/commit 材料三元身份一致后原子消费");
        assertTrue(_root._saveExt.成就.cnt["配件安装次数"] == 1,
            "成功安装只记录配件安装次数");
    }

    private static function testFinalStateEventsAndBusyGuard():Void {
        resetFixture();
        var item:BaseItem = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("强化石", 10);
        var bagHolder:MovieClip = _root.createEmptyMovieClip("__tuningBagTest", _root.getNextHighestDepth());
        var materialHolder:MovieClip = _root.createEmptyMovieClip("__tuningMaterialTest", _root.getNextHighestDepth());
        var bagDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(bagHolder);
        var materialDispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(materialHolder);
        _root.物品栏.背包.setDispatcher(bagDispatcher);
        _root.收集品栏.材料.setDispatcher(materialDispatcher);
        var sawFinalBag:Boolean = false;
        var sawFinalMaterial:Boolean = false;
        var reentry:Object = null;
        bagDispatcher.subscribe("ItemValueChanged", function():Void {
            sawFinalBag = item.value.level == 2 && _root.收集品栏.材料.getValue("强化石") == 9;
            if (reentry == null) reentry = EquipmentTuningService.execute("snapshot", {
                v:1,panelInstanceId:"test.panel",viewSessionId:"events",source:null
            });
        });
        materialDispatcher.subscribe("ItemValueChanged", function():Void {
            sawFinalMaterial = item.value.level == 2 && _root.收集品栏.材料.getValue("强化石") == 9;
        });
        var lease:Object = sourceRef(inventorySnapshot(), 0);
        var previewParams:Object = params("events");
        previewParams.operation = "enhance";
        previewParams.source = lease;
        previewParams.targetLevel = 2;
        var preview:Object = EquipmentTuningService.execute("preview", previewParams);
        var commitParams:Object = params("events");
        commitParams.expectedTuningToken = preview.tuningToken;
        var committed:Object = EquipmentTuningService.execute("commit", commitParams);
        assertTrue(committed.success && sawFinalBag && sawFinalMaterial,
            "材料与装备事件都只观察到完整最终状态");
        assertTrue(reentry != null && reentry.error == "busy",
            "统一发布阶段仍受领域重入守卫保护");
        _root.物品栏.背包.setDispatcher(null);
        _root.收集品栏.材料.setDispatcher(null);
        bagHolder.removeMovieClip();
        materialHolder.removeMovieClip();
    }

    private static function testFinalStateListenerFaultRecovery():Void {
        resetFixture();
        EventBus.getInstance().forceResetDispatchDepth();
        var item:BaseItem = equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, item);
        _root.收集品栏.材料.add("强化石", 100);
        var bagHolder:MovieClip = _root.createEmptyMovieClip(
            "__tuningBagFaultTest", _root.getNextHighestDepth());
        var materialHolder:MovieClip = _root.createEmptyMovieClip(
            "__tuningMaterialFaultTest", _root.getNextHighestDepth());
        var bagDispatcher:LifecycleEventDispatcher =
            new LifecycleEventDispatcher(bagHolder);
        var materialDispatcher:LifecycleEventDispatcher =
            new LifecycleEventDispatcher(materialHolder);
        _root.物品栏.背包.setDispatcher(bagDispatcher);
        _root.收集品栏.材料.setDispatcher(materialDispatcher);
        var bagPublishes:Number = 0;
        var materialPublishes:Number = 0;
        bagDispatcher.subscribe("ItemValueChanged", function():Void {
            bagPublishes++;
        });
        materialDispatcher.subscribe("ItemValueChanged", function():Void {
            materialPublishes++;
            if (materialPublishes == 1) {
                throw "tuning_material_listener_failed";
            }
        });

        try {
            var first:Object = webCommit(
                "event-fault-first", "enhance", 0, -1, "", 2, "");
            assertTrue(first.commit.success
                    && item.value.level == 2
                    && _root.收集品栏.材料.getValue("强化石") == 99
                    && materialPublishes == 1 && bagPublishes == 1
                    && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
                "材料监听器抛错不逆转 authority，先恢复 EventBus depth 并继续背包事件/成功回包");

            var second:Object = webCommit(
                "event-fault-next", "enhance", 0, -1, "", 3, "");
            assertTrue(second.commit.success
                    && item.value.level == 3
                    && _root.收集品栏.材料.getValue("强化石") == 97
                    && materialPublishes == 2 && bagPublishes == 2
                    && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
                "listener-fault 后下一调制事务拥有独立事件快照并正常完成");
        } finally {
            _root.物品栏.背包.setDispatcher(null);
            _root.收集品栏.材料.setDispatcher(null);
            bagHolder.removeMovieClip();
            materialHolder.removeMovieClip();
            EventBus.getInstance().forceResetDispatchDepth();
        }
    }

    private static function installWornFixture(
        slotKey:String,
        item:BaseItem):Object {
        _root.getItemData = function(name):Object {
            return ItemUtil.getItemData(String(name));
        };
        var equipmentInventory:EquipmentInventory =
            new EquipmentInventory(null);
        var added:Boolean =
            equipmentInventory.add(slotKey, item);
        _root.物品栏.装备栏 = equipmentInventory;
        _root.物品栏.药剂栏 =
            new DrugInventory(null, 8);
        _root._webPanelPauseLease =
            "lease.fixture.worn-tuning";

        var gameworld:Object = {};
        var hero:Object = {
            _name:"wornTuningHero",
            _parent:gameworld,
            version:1,
            aabbCollider:{},
            新版人物文字信息:{},
            dispatcher:{
                publish:function():Void {},
                subscribe:function():String { return "fixture"; },
                destroy:function():Void {}
            },
            buffManager:{
                update:function():Void {},
                addBuff:function():String { return "fixture"; },
                removeBuff:function():Boolean { return true; },
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
            syncRefs:{},
            dressupRegistry:{},
            dressupRefreshing:false,
            重量:1,
            行走X速度:1,
            hp满血值:100,
            mp满血值:50,
            防御力:10,
            魔法抗性:{基础:10},
            主动战技:{},
            生命周期函数列表:[],
            格斗架势:false
        };
        _root.控制目标 = hero._name;
        _root.gameworld = gameworld;
        gameworld[hero._name] = hero;
        _root.装备引用配置 = {
            刷新所有装扮:function():Void {}
        };
        _root.根据等级计算值 =
            function():Number { return 1; };
        _root.主角函数 = {
            创建主动战技槽位表:
                function():Object { return {}; },
            获取装备主动战技种类:
                function():String { return ""; }
        };
        _root.敌人函数 = {魔法伤害种类:[]};
        _root.玩家信息界面 = {
            刷新攻击模式:function():Void {}
        };
        _root.UI系统 = {
            iconBar:{initialize:function():Void {}}
        };
        _root.refreshCalls = 0;
        _root.刷新人物装扮 =
            function(targetName:String):Void {
                _root.refreshCalls++;
            };
        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            var key:String = String(SLOT_KEYS[i]);
            var equipped:Object =
                equipmentInventory.getItem(key);
            hero[key] = equipped;
            hero[SLOT_DATA_KEYS[i]] = equipped == null
                ? null : equipped.getData();
        }
        RuntimeEquipmentProjection.beginCanonical(hero);
        RuntimeEquipmentProjection.completeCanonical(hero);

        CharacterBuildService.testOnlyUseRoot(_root);
        var opened:Object = CharacterBuildService.open();
        return {
            added:added,
            opened:opened,
            inventory:equipmentInventory,
            item:item,
            slotKey:slotKey,
            hero:hero
        };
    }

    private static function wornSource(fixture:Object,
                                       revision:Number):Object {
        return {
            sourceKind:"loadout",
            sessionGeneration:
                Number(fixture.opened.sessionGeneration),
            slotKey:String(fixture.slotKey),
            expectedLoadoutRevision:revision
        };
    }

    private static function currentWornSource(
        fixture:Object):Object {
        var current:Object = CharacterBuildService.snapshot(
            Number(fixture.opened.sessionGeneration));
        return wornSource(
            fixture, Number(current.loadoutRevision));
    }

    private static function findCandidateKey(
        snapshot:Object,
        operation:String,
        itemName:String):String {
        var rows:Array = operation == "install_tier"
            ? snapshot.tierCandidates : snapshot.modCandidates;
        for (var i:Number = 0; i < rows.length; i++) {
            if (String(rows[i].itemName) == itemName) {
                return String(rows[i].candidateKey);
            }
        }
        return "";
    }

    private static function prepareWornOperation(
        fixture:Object,
        view:String,
        operation:String,
        candidateName:String,
        replaceCandidateName:String,
        targetLevel):Object {
        var source:Object = currentWornSource(fixture);
        var snapshotParams:Object = params(view);
        snapshotParams.source = source;
        var snapshot:Object =
            EquipmentTuningService.execute(
                "snapshot", snapshotParams);
        if (!snapshot.success) {
            return {source:source, snapshot:snapshot};
        }
        var previewParams:Object = params(view);
        previewParams.operation = operation;
        previewParams.source = source;
        if (targetLevel != undefined) {
            previewParams.targetLevel = targetLevel;
        }
        if (candidateName != undefined
                && candidateName != "") {
            previewParams.candidateKey =
                findCandidateKey(snapshot.snapshot,
                    operation, candidateName);
        }
        if (replaceCandidateName != undefined
                && replaceCandidateName != "") {
            previewParams.replaceCandidateKey =
                findCandidateKey(snapshot.snapshot,
                    "replace_mod", replaceCandidateName);
        }
        var preview:Object =
            EquipmentTuningService.execute(
                "preview", previewParams);
        return {
            source:source,
            snapshot:snapshot,
            preview:preview
        };
    }

    private static function commitWornOperation(
        fixture:Object,
        view:String,
        operation:String,
        candidateName:String,
        replaceCandidateName:String,
        targetLevel):Object {
        var prepared:Object = prepareWornOperation(
            fixture, view, operation, candidateName,
            replaceCandidateName, targetLevel);
        if (prepared.preview == null
                || !prepared.preview.success) {
            return prepared;
        }
        var commitParams:Object = params(view);
        commitParams.expectedTuningToken =
            prepared.preview.tuningToken;
        prepared.commit = EquipmentTuningService.execute(
            "commit", commitParams);
        return prepared;
    }

    private static function testStrictSourceKindsAndWornStaleFences():Void {
        resetFixture();
        var bagItem:BaseItem =
            equipment("测试手枪A", 1, []);
        _root.物品栏.背包.add(0, bagItem);
        _root.收集品栏.材料.add("强化石", 10);
        var strictParams:Object = params("strict-source");
        var exactInventory:Object =
            sourceRef(inventorySnapshot(), 0);
        strictParams.source = {
            containerId:"背包",
            slot:exactInventory.slot,
            expectedLease:exactInventory.expectedLease
        };
        var missingKind:Object =
            EquipmentTuningService.execute(
                "snapshot", strictParams);
        assertTrue(!missingKind.success
                && missingKind.error == "invalid_payload"
                && bagItem.value.level == 1,
            "生产 wire 缺 sourceKind fail-closed，且不存在 legacy adapter 旁路");

        resetFixture();
        var item:BaseItem =
            equipment("测试手枪A", 1, []);
        var fixture:Object =
            installWornFixture("手枪", item);
        var source:Object = wornSource(
            fixture,
            Number(fixture.opened.loadoutRevision));
        var validParams:Object = params("worn-source");
        validParams.source = source;
        var valid:Object =
            EquipmentTuningService.execute(
                "snapshot", validParams);
        assertTrue(fixture.added && fixture.opened.success
                && valid.success
                && valid.snapshot.source.sourceKind
                    == "loadout"
                && valid.snapshot.source.sessionGeneration
                    == source.sessionGeneration
                && valid.snapshot.source.slotKey == "手枪"
                && valid.snapshot.source
                    .expectedLoadoutRevision
                    == source.expectedLoadoutRevision
                && !valid.snapshot.source.hasOwnProperty(
                    "containerId"),
            "loadout snapshot 只镜像 exact generation/slot/revision 四键来源");

        var staleGeneration:Object = {
            sourceKind:"loadout",
            sessionGeneration:
                Number(source.sessionGeneration) + 1,
            slotKey:"手枪",
            expectedLoadoutRevision:
                Number(source.expectedLoadoutRevision)
        };
        var staleRevision:Object = {
            sourceKind:"loadout",
            sessionGeneration:
                Number(source.sessionGeneration),
            slotKey:"手枪",
            expectedLoadoutRevision:
                Number(source.expectedLoadoutRevision) + 1
        };
        var invalidSlot:Object = {
            sourceKind:"loadout",
            sessionGeneration:
                Number(source.sessionGeneration),
            slotKey:"饰品",
            expectedLoadoutRevision:
                Number(source.expectedLoadoutRevision)
        };
        var staleParams:Object = params("worn-stale");
        staleParams.source = staleGeneration;
        var generationDenied:Object =
            EquipmentTuningService.execute(
                "snapshot", staleParams);
        staleParams.source = staleRevision;
        var revisionDenied:Object =
            EquipmentTuningService.execute(
                "snapshot", staleParams);
        staleParams.source = invalidSlot;
        var slotDenied:Object =
            EquipmentTuningService.execute(
                "snapshot", staleParams);
        var extraSource:Object = wornSource(
            fixture,
            Number(source.expectedLoadoutRevision));
        extraSource.containerId = "背包";
        staleParams.source = extraSource;
        var extraDenied:Object =
            EquipmentTuningService.execute(
                "snapshot", staleParams);
        assertTrue(!generationDenied.success
                && generationDenied.error == "stale_session"
                && !revisionDenied.success
                && revisionDenied.error == "stale_state"
                && !slotDenied.success
                && slotDenied.error == "invalid_slot"
                && !extraDenied.success
                && extraDenied.error == "invalid_payload",
            "loadout source 对 stale generation/revision、白名单外槽和多余键全部 fail-closed");

        var convertSnapshotParams:Object =
            params("worn-convert");
        convertSnapshotParams.source = source;
        EquipmentTuningService.execute(
            "snapshot", convertSnapshotParams);
        var convertParams:Object = params("worn-convert");
        convertParams.operation = "convert";
        convertParams.source = source;
        convertParams.target = source;
        var convertDenied:Object =
            EquipmentTuningService.execute(
                "preview", convertParams);
        assertTrue(!convertDenied.success
                && convertDenied.error
                    == "unsupported_operation"
                && item.value.level == 1,
            "loadout convert 仍拒绝非背包 target 且零装备写");
    }

    private static function testWornCommitAndLiveDirtyBoundary():Void {
        resetFixture();
        _root.收集品栏.材料.add("强化石", 10);
        var item:BaseItem =
            equipment("测试手枪A", 1, []);
        var fixture:Object =
            installWornFixture("手枪", item);
        var beforeEquipmentRevision:Number =
            fixture.inventory.getMutationRevision();
        var beforeMaterialRevision:Number =
            _root.收集品栏.材料
                .getMutationRevision();
        var beforeDerived:Object =
            fixture.hero.手枪数据;
        var result:Object = commitWornOperation(
            fixture, "worn-enhance", "enhance",
            "", "", 2);
        var current:Object = CharacterBuildService.snapshot(
            Number(fixture.opened.sessionGeneration));

        assertTrue(result.snapshot.success
                && result.preview.success
                && result.commit.success
                && item.value.level == 2
                && _root.收集品栏.材料
                    .getValue("强化石") == 9
                && fixture.inventory
                    .getMutationRevision()
                    == beforeEquipmentRevision + 1
                && _root.收集品栏.材料
                    .getMutationRevision()
                    == beforeMaterialRevision + 1,
            "worn item value 与材料以单批次原子提交且两边 raw revision 各推进一次");
        assertTrue(result.commit.inventorySnapshots
                    instanceof Array
                && result.commit.inventorySnapshots.length == 0
                && result.commit.before.source.source
                    .expectedLoadoutRevision
                    == fixture.opened.loadoutRevision
                && result.commit.after.source.source
                    .expectedLoadoutRevision
                    == fixture.opened.loadoutRevision + 1
                && result.commit.snapshot.source
                    .expectedLoadoutRevision
                    == fixture.opened.loadoutRevision + 1
                && snapshotMaterialCount(
                    result.commit.snapshot,
                    "强化石") == 9
                && result.commit.materials[0].after == 9,
            "worn commit 返回 pre-before/post-after/post-snapshot、写后材料且不伪造背包 snapshot");
        assertTrue(current.success
                && current.loadoutRevision
                    == fixture.opened.loadoutRevision + 1
                && current.loadoutChanged == false
                && current.liveRefreshDirty
                && fixture.hero.手枪 === item
                && fixture.hero.手枪数据 === beforeDerived
                && _root.refreshCalls == 0,
            "Character hook 精确同步一次；共享 worn item 引用不冒充派生属性已刷新");
    }

    private static function prepareWornConversion(
        fixture:Object,
        view:String,
        targetSlot:Number):Object {
        var source:Object = currentWornSource(fixture);
        var snapshotParams:Object = params(view);
        snapshotParams.source = source;
        var snapshot:Object = EquipmentTuningService.execute(
            "snapshot", snapshotParams);
        var target:Object = sourceRef(
            inventorySnapshot(), targetSlot);
        var previewParams:Object = params(view);
        previewParams.operation = "convert";
        previewParams.source = source;
        previewParams.target = target;
        var preview:Object = EquipmentTuningService.execute(
            "preview", previewParams);
        return {
            source:source,
            target:target,
            snapshot:snapshot,
            preview:preview
        };
    }

    private static function commitPreparedWornConversion(
        prepared:Object,
        view:String):Object {
        var commitParams:Object = params(view);
        commitParams.expectedTuningToken =
            prepared.preview.tuningToken;
        return EquipmentTuningService.execute(
            "commit", commitParams);
    }

    private static function testWornConversionAcrossBackpack():Void {
        resetFixture();
        var worn:BaseItem = equipment(
            "测试手枪A", 2, []);
        var target:BaseItem = equipment(
            "测试手枪B", 5, []);
        _root.物品栏.背包.add(0, target);
        var fixture:Object = installWornFixture(
            "手枪", worn);
        var beforeWornRevision:Number =
            fixture.inventory.getMutationRevision();
        var beforeBagRevision:Number =
            _root.物品栏.背包.getMutationRevision();
        var prepared:Object = prepareWornConversion(
            fixture, "worn-convert-success", 0);
        var committed:Object =
            commitPreparedWornConversion(
                prepared, "worn-convert-success");
        var current:Object = CharacterBuildService.snapshot(
            Number(fixture.opened.sessionGeneration));
        var postTarget:Object = sourceRef(
            committed.inventorySnapshots[0], 0);
        assertTrue(prepared.snapshot.success
                && prepared.preview.success
                && committed.success
                && !committed.noOp
                && worn.value.level == 5
                && target.value.level == 2
                && fixture.inventory.getMutationRevision()
                    == beforeWornRevision + 1
                && _root.物品栏.背包.getMutationRevision()
                    == beforeBagRevision + 1
                && current.loadoutRevision
                    == fixture.opened.loadoutRevision + 1
                && current.liveRefreshDirty,
            "loadout 与背包强化度以双 receipt 原子交换，两个 raw revision 和一个构筑 revision 各推进一次");
        assertTrue(committed.inventorySnapshots.length == 1
                && committed.after.source.source
                    .expectedLoadoutRevision
                    == fixture.opened.loadoutRevision + 1
                && committed.after.target.source.expectedLease
                    == postTarget.expectedLease
                && postTarget.expectedLease
                    != prepared.target.expectedLease
                && committed.after.source.equipment.level == 5
                && committed.after.target.equipment.level == 2,
            "loadout convert 回包同时证明 post-loadout 与轮换 lease 后的完整背包 target");

        resetFixture();
        worn = equipment("测试手枪A", 2, []);
        target = equipment("测试手枪B", 5, []);
        _root.物品栏.背包.add(0, target);
        fixture = installWornFixture("手枪", worn);
        prepared = prepareWornConversion(
            fixture, "worn-convert-rollback", 0);
        var wornValue:Object = worn.value;
        var targetValue:Object = target.value;
        var wornTime:Number = worn.lastUpdate;
        var targetTime:Number = target.lastUpdate;
        beforeWornRevision =
            fixture.inventory.getMutationRevision();
        beforeBagRevision =
            _root.物品栏.背包.getMutationRevision();
        EquipmentTuningService
            .testOnlyFailNextWornConversionBagCommit();
        var rolledBack:Object =
            commitPreparedWornConversion(
                prepared, "worn-convert-rollback");
        current = CharacterBuildService.snapshot(
            Number(fixture.opened.sessionGeneration));
        assertTrue(!rolledBack.success
                && rolledBack.error == "commit_failed"
                && worn.value === wornValue
                && target.value === targetValue
                && worn.lastUpdate == wornTime
                && target.lastUpdate == targetTime
                && fixture.inventory.getMutationRevision()
                    == beforeWornRevision
                && _root.物品栏.背包.getMutationRevision()
                    == beforeBagRevision
                && current.loadoutRevision
                    == fixture.opened.loadoutRevision
                && !current.liveRefreshDirty,
            "背包侧提交失败会恢复 worn value/time/revision，且 Character authority 完全不前进");

        resetFixture();
        worn = equipment("测试手枪A", 2, []);
        target = equipment("测试手枪B", 5, []);
        _root.物品栏.背包.add(0, target);
        fixture = installWornFixture("手枪", worn);
        prepared = prepareWornConversion(
            fixture, "worn-convert-stale", 0);
        target.lastUpdate = Number(target.lastUpdate) + 1;
        beforeWornRevision =
            fixture.inventory.getMutationRevision();
        beforeBagRevision =
            _root.物品栏.背包.getMutationRevision();
        var stale:Object = commitPreparedWornConversion(
            prepared, "worn-convert-stale");
        assertTrue(!stale.success
                && stale.error == "stale_state"
                && worn.value.level == 2
                && target.value.level == 5
                && fixture.inventory.getMutationRevision()
                    == beforeWornRevision
                && _root.物品栏.背包.getMutationRevision()
                    == beforeBagRevision,
            "loadout convert 在 commit 临界区重新验证背包 target，stale target 零交换");

        resetFixture();
        worn = equipment("测试手枪A", 2, []);
        target = equipment("测试手枪B", 5, []);
        _root.物品栏.背包.add(0, target);
        fixture = installWornFixture("手枪", worn);
        prepared = prepareWornConversion(
            fixture, "worn-convert-observed", 0);
        CharacterBuildService
            .testOnlyFailNextWornPostcondition();
        var observed:Object = commitPreparedWornConversion(
            prepared, "worn-convert-observed");
        current = CharacterBuildService.snapshot(
            Number(fixture.opened.sessionGeneration));
        assertTrue(!observed.success
                && observed.error == "needs_reconcile"
                && worn.value.level == 5
                && target.value.level == 2
                && current.loadoutRevision
                    == fixture.opened.loadoutRevision + 1
                && current.liveRefreshDirty
                && observed.writeEpoch == 1
                && _root.存档系统.dirtyMark,
            "Character authority 已观察跨容器 post-state 后保留双侧提交并要求双快照对账，绝不反向伪装失败");
    }

    private static function testWornAllowedOperationMatrix():Void {
        resetFixture();
        _root.收集品栏.材料.add(
            "二阶复合防御组件", 1);
        var armor:BaseItem =
            equipment("测试头盔", 1, []);
        var armorFixture:Object =
            installWornFixture("头部装备", armor);
        var tier:Object = commitWornOperation(
            armorFixture, "worn-tier", "install_tier",
            "二阶复合防御组件", "", undefined);
        assertTrue(tier.commit.success
                && armor.value.tier == "二阶"
                && _root.收集品栏.材料.getValue(
                    "二阶复合防御组件") == 0,
            "loadout 允许 install_tier 并消费材料");

        resetFixture();
        _root.收集品栏.材料.add("普通握把", 2);
        _root.收集品栏.材料.add("级联核心", 1);
        _root.收集品栏.材料.add("基础导轨", 1);
        var weapon:BaseItem =
            equipment("测试手枪A", 1, []);
        var weaponFixture:Object =
            installWornFixture("手枪", weapon);
        var installed:Object = commitWornOperation(
            weaponFixture, "worn-mod-install",
            "install_mod", "普通握把", "", undefined);
        var replaced:Object = commitWornOperation(
            weaponFixture, "worn-mod-replace",
            "replace_mod", "级联核心",
            "普通握把", undefined);
        var detached:Object = commitWornOperation(
            weaponFixture, "worn-mod-detach",
            "detach_mod", "级联核心", "", undefined);
        var installedAgain:Object = commitWornOperation(
            weaponFixture, "worn-mod-install-again",
            "install_mod", "普通握把", "", undefined);
        var installedRail:Object = commitWornOperation(
            weaponFixture, "worn-mod-install-rail",
            "install_mod", "基础导轨", "", undefined);
        var detachedAll:Object = commitWornOperation(
            weaponFixture, "worn-mod-detach-all",
            "detach_all_mods", "", "", undefined);
        assertTrue(installed.commit.success
                && replaced.commit.success
                && detached.commit.success
                && installedAgain.commit.success
                && installedRail.commit.success
                && detachedAll.commit.success
                && weapon.value.mods.length == 0
                && _root.收集品栏.材料
                    .getValue("普通握把") == 2
                && _root.收集品栏.材料
                    .getValue("级联核心") == 1
                && _root.收集品栏.材料
                    .getValue("基础导轨") == 1,
            "loadout 允许 install/replace/detach/detach_all mod，返还与扣料无复制");
    }

    private static function testWornRollbackAndUnknownReconcile():Void {
        resetFixture();
        _root.收集品栏.材料.add("强化石", 10);
        var item:BaseItem =
            equipment("测试手枪A", 1, []);
        var fixture:Object =
            installWornFixture("手枪", item);
        var materialPrepared:Object = prepareWornOperation(
            fixture, "worn-material-failure",
            "enhance", "", "", 2);
        var beforeValue:Object = item.value;
        var beforeItemTime:Number = item.lastUpdate;
        var beforeEquipmentRevision:Number =
            fixture.inventory.getMutationRevision();
        var beforeMaterialRevision:Number =
            _root.收集品栏.材料
                .getMutationRevision();
        EquipmentTuningService
            .testOnlyFailNextMaterialCommit();
        var commitParams:Object =
            params("worn-material-failure");
        commitParams.expectedTuningToken =
            materialPrepared.preview.tuningToken;
        var materialFailed:Object =
            EquipmentTuningService.execute(
                "commit", commitParams);
        var afterMaterialFailure:Object =
            CharacterBuildService.snapshot(
                Number(fixture.opened.sessionGeneration));
        assertTrue(!materialFailed.success
                && materialFailed.error == "commit_failed"
                && item.value === beforeValue
                && item.lastUpdate == beforeItemTime
                && _root.收集品栏.材料
                    .getValue("强化石") == 10
                && fixture.inventory
                    .getMutationRevision()
                    == beforeEquipmentRevision
                && _root.收集品栏.材料
                    .getMutationRevision()
                    == beforeMaterialRevision
                && afterMaterialFailure.loadoutRevision
                    == fixture.opened.loadoutRevision
                && !afterMaterialFailure
                    .liveRefreshDirty,
            "材料提交失败完整 rollback worn value/材料/revision，Character authority 不前进");
        var materialReplay:Object =
            EquipmentTuningService.execute(
                "commit", commitParams);
        assertTrue(!materialReplay.success
                && materialReplay.error == "token_invalid",
            "材料失败已消费 token，绝不重放");

        resetFixture();
        _root.收集品栏.材料.add("强化石", 10);
        item = equipment("测试手枪A", 1, []);
        fixture = installWornFixture("手枪", item);
        var serializationPrepared:Object =
            prepareWornOperation(
                fixture, "worn-serialization-failure",
                "enhance", "", "", 2);
        beforeValue = item.value;
        beforeItemTime = item.lastUpdate;
        beforeEquipmentRevision =
            fixture.inventory.getMutationRevision();
        beforeMaterialRevision =
            _root.收集品栏.材料
                .getMutationRevision();
        var rollbackProbe:Object =
            installWornPublishProbe(
                fixture, "pre_authority_rollback");
        EquipmentTuningService
            .testOnlyFailNextSerialization();
        commitParams =
            params("worn-serialization-failure");
        commitParams.expectedTuningToken =
            serializationPrepared.preview.tuningToken;
        var serializationFailed:Object =
            EquipmentTuningService.execute(
                "commit", commitParams);
        var afterSerializationFailure:Object =
            CharacterBuildService.snapshot(
                Number(fixture.opened.sessionGeneration));
        assertTrue(!serializationFailed.success
                && serializationFailed.error
                    == "commit_failed"
                && item.value === beforeValue
                && item.lastUpdate == beforeItemTime
                && _root.收集品栏.材料
                    .getValue("强化石") == 10
                && fixture.inventory
                    .getMutationRevision()
                    == beforeEquipmentRevision
                && _root.收集品栏.材料
                    .getMutationRevision()
                    == beforeMaterialRevision
                && afterSerializationFailure
                    .loadoutRevision
                    == fixture.opened.loadoutRevision,
            "写后投影序列化预检异常完整 rollback，不扣重、不复制、不推进 loadout");
        assertTrue(rollbackProbe.equipmentPublishes == 0
                && rollbackProbe.materialPublishes == 0
                && serializationFailed.writeEpoch == 0
                && !_root.存档系统.dirtyMark
                && _root._saveExt.成就.cnt[
                    "装备强化次数"] == undefined,
            "pre-authority rollback 零 publish、零 write epoch、零 dirty/成就副作用");
        removeWornPublishProbe(
            fixture, rollbackProbe);

        resetFixture();
        _root.收集品栏.材料.add("强化石", 10);
        item = equipment("测试手枪A", 1, []);
        fixture = installWornFixture("手枪", item);
        var observedPrepared:Object =
            prepareWornOperation(
                fixture, "worn-observed-postcondition",
                "enhance", "", "", 2);
        var observedProbe:Object =
            installWornPublishProbe(
                fixture, "observed_unknown");
        CharacterBuildService
            .testOnlyFailNextWornPostcondition();
        commitParams =
            params("worn-observed-postcondition");
        commitParams.expectedTuningToken =
            observedPrepared.preview.tuningToken;
        var observedFailure:Object =
            EquipmentTuningService.execute(
                "commit", commitParams);
        var observedState:Object =
            CharacterBuildService.snapshot(
                Number(fixture.opened.sessionGeneration));
        var observedReplay:Object =
            EquipmentTuningService.execute(
                "commit", commitParams);
        assertTrue(!observedFailure.success
                && observedFailure.error
                    == "needs_reconcile"
                && item.value.level == 2
                && _root.收集品栏.材料
                    .getValue("强化石") == 9
                && observedState.loadoutRevision
                    == fixture.opened.loadoutRevision + 1
                && observedState.liveRefreshDirty
                && observedFailure.writeEpoch == 1
                && _root.存档系统.dirtyMark,
            "hook 已观察 post authority 后置异常时保留 raw commit、推进 dirty/write epoch 并 needs_reconcile");
        assertTrue(observedProbe.equipmentPublishes == 1
                && observedProbe.materialPublishes == 1
                && _root._saveExt.成就.cnt[
                    "装备强化次数"] == 1
                && !observedReplay.success
                && observedReplay.error == "token_invalid"
                && observedReplay.writeEpoch == 1,
            "observed-unknown 的装备/材料 publish 与成就恰好一次，token replay 不重复副作用");
        removeWornPublishProbe(
            fixture, observedProbe);

        resetFixture();
        _root.收集品栏.材料.add("强化石", 10);
        item = equipment("测试手枪A", 1, []);
        fixture = installWornFixture("手枪", item);
        var unknown:Object = commitWornOperation(
            fixture, "worn-unknown",
            "enhance", "", "", 2);
        commitParams = params("worn-unknown");
        commitParams.expectedTuningToken =
            unknown.preview.tuningToken;
        var replay:Object =
            EquipmentTuningService.execute(
                "commit", commitParams);
        var staleReconcileParams:Object =
            params("worn-unknown");
        staleReconcileParams.source = unknown.source;
        staleReconcileParams.reconcileAfterCallId =
            "worn.unknown.commit";
        var staleReconcile:Object =
            EquipmentTuningService.execute(
                "snapshot", staleReconcileParams);
        var freshLoadout:Object =
            CharacterBuildService.snapshot(
                Number(fixture.opened.sessionGeneration));
        var freshReconcileParams:Object =
            params("worn-unknown");
        freshReconcileParams.source = wornSource(
            fixture,
            Number(freshLoadout.loadoutRevision));
        freshReconcileParams.reconcileAfterCallId =
            "worn.unknown.commit";
        var reconciled:Object =
            EquipmentTuningService.execute(
                "snapshot", freshReconcileParams);
        assertTrue(unknown.commit.success
                && !replay.success
                && replay.error == "token_invalid"
                && !staleReconcile.success
                && staleReconcile.error == "stale_state"
                && reconciled.success
                && reconciled.reconciled
                && reconciled.reconcileAfterCallId
                    == "worn.unknown.commit"
                && reconciled.snapshot.source
                    .expectedLoadoutRevision
                    == freshLoadout.loadoutRevision
                && reconciled.snapshot.equipment.level == 2
                && snapshotMaterialCount(
                    reconciled.snapshot,
                    "强化石") == 9,
            "unknown 不 replay：旧 source 拒绝，先取 fresh loadout revision 后 exact tuning reconcile 成功");
    }
}
