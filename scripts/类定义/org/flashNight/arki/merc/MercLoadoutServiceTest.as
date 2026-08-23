import org.flashNight.arki.merc.MercLoadoutService;
import org.flashNight.arki.merc.MercPanelService;
import org.flashNight.arki.merc.MercSpawner;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

/** 佣兵装备托管（一期）policy、事务与冻结边界的纯 AS2 回归。设计：docs/佣兵装备托管-设计-2026-08-23.md §9。 */
class org.flashNight.arki.merc.MercLoadoutServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        trace("=== MercLoadoutServiceTest start ===");
        var catalogReceipt:Object = installCatalogFixture();
        try {
            testSlotWritability();
            testPolicyGates();
            testFreezeAndRuntimeIsolation();
            testLegacyCompatibility();
            testDeliverSuccessAndProjection();
            testDeliverGateMatrix();
            testDeliverCommitFailureAtomicity();
            testReplaceFlow();
            testReplaceFailuresAndRollback();
            testWithdrawFlow();
            testWithdrawFailures();
            testCorruptSlotFailsClosed();
            testSpawnLoadout();
            testCandidates();
            testSlotTooltip();
            testBusyReentryAndNotificationIsolation();
            testDismissGuardAndPanelCommands();
        } finally {
            restoreCatalogFixture(catalogReceipt);
        }
        trace("MercLoadoutServiceTest Tests Passed: " + passed);
        trace("MercLoadoutServiceTest Tests Failed: " + failed);
        trace("=== MercLoadoutServiceTest end ===");
    }

    // merc tuple: [0]等级 [1]名字 [2]id [3]身高 [4]脸型 [5]发型 [6..16]装备 [17]性别 [18]价格 [19]元数据
    private static function merc(level:Number, id:String):Array {
        return [level, "测试佣兵", id, 175, "脸型A", "发型A",
            "测试头盔", "", "", "", "", "", "测试长枪A", "", "", "", "", "男", 1000, {}];
    }

    /**
     * Focused TestLoader 不加载生产物品 XML。这里仅安装本套件实际使用的最小目录，
     * 让 BaseItem.createFromObject/createFromString 走与游戏内相同的名称和 use 复证，
     * 而不是把“目录尚未初始化”误报成托管快照损坏。
     */
    private static function installCatalogFixture():Object {
        var receipt:Object = {
            itemDataDict:ItemUtil.itemDataDict,
            equipmentDict:ItemUtil.equipmentDict
        };
        ItemUtil.itemDataDict = {};
        ItemUtil.itemDataDict["测试头盔"] = {
            name:"测试头盔", displayname:"测试头盔", icon:"测试头盔",
            type:"防具", use:"头部装备", data:{level:3}
        };
        ItemUtil.itemDataDict["测试名盔"] = {
            name:"测试名盔", displayname:"测试名盔", icon:"测试名盔",
            type:"防具", use:"头部装备", data:{level:30}
        };
        ItemUtil.itemDataDict["测试异型头"] = {
            name:"测试异型头", displayname:"测试异型头", icon:"测试异型头",
            type:"材料", use:"头部装备", data:{level:1}
        };
        ItemUtil.itemDataDict["测试长枪A"] = {
            name:"测试长枪A", displayname:"测试长枪A", icon:"测试长枪A",
            type:"武器", use:"长枪", weapontype:"突击步枪", data:{level:5, modslot:1}
        };
        ItemUtil.itemDataDict["测试长枪B"] = {
            name:"测试长枪B", displayname:"测试长枪B", icon:"测试长枪B",
            type:"武器", use:"长枪", weapontype:"狙击枪", data:{level:8, modslot:1}
        };
        ItemUtil.itemDataDict["测试重炮"] = {
            name:"测试重炮", displayname:"测试重炮", icon:"测试重炮",
            type:"武器", use:"长枪", weapontype:"发射器", data:{level:30, modslot:1}
        };
        ItemUtil.itemDataDict["测试手枪"] = {
            name:"测试手枪", displayname:"测试手枪", icon:"测试手枪",
            type:"武器", use:"手枪", weapontype:"冲锋手枪", data:{level:2, modslot:1}
        };
        ItemUtil.itemDataDict["测试刀"] = {
            name:"测试刀", displayname:"测试刀", icon:"测试刀",
            type:"武器", use:"刀", weapontype:"短刀", data:{level:1}
        };
        ItemUtil.itemDataDict["测试材料"] = {
            name:"测试材料", displayname:"测试材料", icon:"测试材料",
            type:"材料", use:"材料"
        };
        ItemUtil.itemDataDict["测试占位"] = {
            name:"测试占位", displayname:"测试占位", icon:"测试占位",
            type:"材料", use:"材料"
        };
        // 本测试验证托管/库存原子性，不重复测试 EquipmentCalculator；保持空字典
        // 可令 getData 返回上述目录克隆，同时避免 focused fixture 伪装完整强化配置。
        ItemUtil.equipmentDict = {};
        return receipt;
    }

    private static function restoreCatalogFixture(receipt:Object):Void {
        ItemUtil.itemDataDict = receipt.itemDataDict;
        ItemUtil.equipmentDict = receipt.equipmentDict;
    }

    private static function saveRoot():Object {
        return {
            物品栏:_root.物品栏,
            当前为战斗地图:_root.当前为战斗地图,
            存档系统:_root.存档系统,
            同伴数据:_root.同伴数据,
            佣兵是否出战信息:_root.佣兵是否出战信息,
            佣兵个数限制:_root.佣兵个数限制,
            同伴数:_root.同伴数,
            可雇佣兵:_root.可雇佣兵,
            隐藏的可雇佣兵:_root.隐藏的可雇佣兵,
            gameworld:_root.gameworld,
            菜单MC对应名:_root.菜单MC对应名,
            server:_root.server,
            gameCommands:_root.gameCommands
        };
    }

    private static function restoreRoot(s:Object):Void {
        _root.物品栏 = s.物品栏;
        _root.当前为战斗地图 = s.当前为战斗地图;
        _root.存档系统 = s.存档系统;
        _root.同伴数据 = s.同伴数据;
        _root.佣兵是否出战信息 = s.佣兵是否出战信息;
        _root.佣兵个数限制 = s.佣兵个数限制;
        _root.同伴数 = s.同伴数;
        _root.可雇佣兵 = s.可雇佣兵;
        _root.隐藏的可雇佣兵 = s.隐藏的可雇佣兵;
        _root.gameworld = s.gameworld;
        _root.菜单MC对应名 = s.菜单MC对应名;
        _root.server = s.server;
        _root.gameCommands = s.gameCommands;
    }

    /** 常用 _root 战场：单佣兵（休息）+ 空背包 cap。返回 {merc, bag}。 */
    private static function setupMercScene(bagCapacity:Number):Object {
        var m:Array = merc(10, "m1");
        var bag:ArrayInventory = new ArrayInventory(null, bagCapacity);
        _root.物品栏 = {背包:bag};
        _root.当前为战斗地图 = false;
        _root.存档系统 = {dirtyMark:false};
        _root.同伴数据 = [m];
        _root.佣兵是否出战信息 = [0];
        _root.佣兵个数限制 = 1;
        return {merc:m, bag:bag};
    }

    private static function snapshotRef(bag:ArrayInventory, slot:Number, limit:Number):Object {
        var snapshot:Object = InventoryPanelService.buildExternalSnapshot("背包", 0, limit);
        return {
            containerId:"背包",
            slot:slot,
            expectedLease:String(snapshot.slots[slot].slotLease)
        };
    }

    private static function testSlotWritability():Void {
        var allOpen:Boolean = true;
        for (var slot:Number = 6; slot <= 15; slot++) {
            if (!MercLoadoutService.isWritableSlot(slot)) allOpen = false;
        }
        check(allOpen, "merc[6..15] 全部可写");
        check(!MercLoadoutService.isWritableSlot(16) && !MercLoadoutService.isWritableSlot(5)
                && !MercLoadoutService.isWritableSlot(17),
            "手雷槽 16 与界外槽位不可写");
        check(MercLoadoutService.isWritableSlot("6") && MercLoadoutService.isWritableSlot("15")
                && MercLoadoutService.slotUseKey(8) == "手部装备"
                && MercLoadoutService.slotUseKey(9) == "下装装备"
                && MercLoadoutService.slotUseKey(14) == "手枪2",
            "字符串槽键可写且槽名映射正确");
        check(!MercLoadoutService.isWritableSlot("abc")
                && !MercLoadoutService.isWritableSlot(NaN)
                && !MercLoadoutService.isWritableSlot(-1)
                && !MercLoadoutService.isWritableSlot(6.5)
                && MercLoadoutService.slotUseKey(16) == null,
            "非整数/NaN/负槽全部拒绝");
    }

    private static function testPolicyGates():Void {
        var m:Array = merc(10, "m1");
        check(MercLoadoutService.evaluateItemForSlot(m, 6,
                new BaseItem("测试头盔", {level:1}, 1)).success === true,
            "use 匹配槽名的防具通过 policy");
        var mismatch:Object = MercLoadoutService.evaluateItemForSlot(m, 7,
            new BaseItem("测试头盔", {level:1}, 1));
        check(!mismatch.success && mismatch.error == "slot_mismatch",
            "use 与槽名不匹配被拒绝");
        check(MercLoadoutService.evaluateItemForSlot(m, 14,
                new BaseItem("测试手枪", {level:1}, 1)).success === true,
            "手枪2 槽接受 use=手枪 候选");
        check(MercLoadoutService.evaluateItemForSlot(m, 13,
                new BaseItem("测试手枪", {level:1}, 1)).success === true,
            "手枪槽接受 use=手枪 候选");
        var locked:Object = MercLoadoutService.evaluateItemForSlot(m, 6,
            new BaseItem("测试名盔", {level:1}, 1));
        check(!locked.success && locked.error == "level_locked"
                && Number(locked.requirementLevel) == 30,
            "等级门基准为佣兵自身等级（10 级佣兵拒绝需求 30 装备）");
        var wrongType:Object = MercLoadoutService.evaluateItemForSlot(m, 6,
            new BaseItem("测试异型头", {level:1}, 1));
        check(!wrongType.success && wrongType.error == "not_equipment",
            "type 非武器/防具的 use 匹配物仍被拒绝");
        var notEquip:Object = MercLoadoutService.evaluateItemForSlot(m, 6,
            new BaseItem("测试材料", 5, 1));
        check(!notEquip.success && notEquip.error == "invalid_item",
            "value 非 Object 的非装备实例被拒绝");
        check(MercLoadoutService.evaluateItemForSlot(m, 16,
                new BaseItem("测试头盔", {level:1}, 1)).error == "slot_locked",
            "手雷槽 16 在 policy 层即 slot_locked");
    }

    private static function testFreezeAndRuntimeIsolation():Void {
        var original:Object = {
            name:"测试长枪B",
            value:{level:7, shot:4, mods:["测试插件"]},
            lastUpdate:123
        };
        var fakeItem:Object = {
            toObject:function():Object { return original; }
        };
        var frozen:Object = MercLoadoutService.freezeItem(fakeItem);
        original.value.shot = 99;
        original.value.mods[0] = "已污染";
        check(frozen != null && frozen.value.shot == 4
                && frozen.value.mods[0] == "测试插件",
            "冻结交付快照与来源对象深度隔离");
        var runtime:BaseItem = MercLoadoutService.createRuntimeItem(12, frozen);
        check(runtime != null && runtime.name == "测试长枪B"
                && runtime.value.level == 7 && runtime.value.shot == 4,
            "冻结快照经克隆重建为运行时 BaseItem");
        runtime.value.shot = -1;
        check(frozen.value.shot == 4,
            "运行态副本变化不回写冻结权威");
        check(MercLoadoutService.createRuntimeItem(13, frozen) == null
                && MercLoadoutService.createRuntimeItem(14,
                    MercLoadoutService.freezeItem(new BaseItem("测试手枪", {level:2}, 9))) != null,
            "运行时克隆按目标槽复证 use（长枪冻结拒绝进手枪槽，手枪冻结可进手枪2槽）");
    }

    private static function testLegacyCompatibility():Void {
        var legacy:Array = merc(10, "legacy");
        legacy.length = 19;
        check(MercLoadoutService.getLoadoutRevision(legacy) == 0
                && !MercLoadoutService.hasAnyCustody(legacy),
            "无 merc[19] 的旧档按无托管、revision 0 判空");
        var emptyMeta:Array = merc(10, "legacy2");
        check(MercLoadoutService.getLoadoutRevision(emptyMeta) == 0
                && !MercLoadoutService.hasAnyCustody(emptyMeta),
            "merc[19] 无托管字段同样判空兼容");
        var s:Object = saveRoot();
        try {
            setupMercScene(2);
            var proj:Object = MercLoadoutService.buildLoadoutProjection(emptyMeta, 0);
            check(proj.loadoutRevision == 0 && proj.canOperate === true
                    && proj.deployState == 0 && proj.slots["6"].state == "preset",
                "旧档投影 revision 0 且休息态可操作");
            var poolProj:Object = MercLoadoutService.buildLoadoutProjection(emptyMeta, -1);
            check(poolProj.canOperate === false && poolProj.deployState == null
                    && poolProj.slots["6"].preset != null,
                "池佣兵（slotIndex<0）投影仅 preset 且不可操作");
        } finally {
            restoreRoot(s);
        }
    }

    private static function testDeliverSuccessAndProjection():Void {
        var s:Object = saveRoot();
        try {
            var scene:Object = setupMercScene(3);
            var m:Array = scene.merc;
            var bag:ArrayInventory = scene.bag;
            m[19].是否杂交 = false;
            var original:BaseItem = new BaseItem("测试长枪B", {
                level:6, shot:7, mods:["战术背带"]
            }, 123456);
            bag.add(0, original);

            var result:Object = MercLoadoutService.deliver(
                0, "m1", "12", 0, snapshotRef(bag, 0, 3));
            var frozen:Object = m[19].装备托管.slots["12"].item;
            check(result.success === true && bag.getItem("0") == null
                    && MercLoadoutService.getLoadoutRevision(m) == 1
                    && result.operation == "deliver" && Number(result.loadoutRevision) == 1,
                "交付原子移出背包并递增 loadoutRevision");
            check(frozen.value.level == 6 && frozen.value.shot == 7
                    && frozen.value.mods[0] == "战术背带" && frozen.lastUpdate == 123456,
                "交付冻结强化、弹量、插件与时间戳");
            check(_root.存档系统.dirtyMark === true,
                "交付成功标脏存档");
            check(m[19].是否杂交 == false && m[19].装备托管.version == 1,
                "首次写入创建托管域且保留 merc[19] 既有元数据键");
            var proj:Object = MercLoadoutService.buildLoadoutProjection(m, 0);
            check(proj.canOperate === true && proj.slots["12"].state == "custody"
                    && proj.slots["12"].custody.name == "测试长枪B"
                    && proj.slots["12"].custody.level == 6,
                "投影托管槽三态为 custody 且携带冻结概览");
            check(proj.slots["6"].state == "preset"
                    && proj.slots["6"].preset.name == "测试头盔"
                    && proj.slots["6"].preset.level == 1
                    && proj.slots["6"].preset.raw == "测试头盔",
                "预设槽按默认强化口径投影（10 级佣兵默认强化回落 1）");
        } finally {
            restoreRoot(s);
        }
    }

    private static function testDeliverGateMatrix():Void {
        var s:Object = saveRoot();
        try {
            var scene:Object = setupMercScene(3);
            var m:Array = scene.merc;
            var bag:ArrayInventory = scene.bag;
            var original:BaseItem = new BaseItem("测试长枪B", {level:6, shot:7}, 222);
            bag.add(0, original);

            _root.当前为战斗地图 = true;
            var combat:Object = MercLoadoutService.deliver(0, "m1", "12", 0, snapshotRef(bag, 0, 3));
            check(combat.error == "combat_locked" && bag.getItem("0") === original
                    && !MercLoadoutService.hasAnyCustody(m),
                "战斗地图交付 combat_locked 且零写入");
            _root.当前为战斗地图 = false;

            _root.佣兵是否出战信息[0] = 1;
            var deployed:Object = MercLoadoutService.deliver(0, "m1", "12", 0, snapshotRef(bag, 0, 3));
            check(deployed.error == "merc_deployed" && !MercLoadoutService.hasAnyCustody(m),
                "出战佣兵交付 merc_deployed");
            _root.佣兵是否出战信息[0] = -1;
            var dead:Object = MercLoadoutService.deliver(0, "m1", "12", 0, snapshotRef(bag, 0, 3));
            check(dead.error == "merc_dead" && !MercLoadoutService.hasAnyCustody(m),
                "阵亡佣兵交付 merc_dead");
            _root.佣兵是否出战信息[0] = 0;

            var staleRev:Object = MercLoadoutService.deliver(0, "m1", "12", 99, snapshotRef(bag, 0, 3));
            check(staleRev.error == "stale_state" && !MercLoadoutService.hasAnyCustody(m),
                "expectedLoadoutRevision 漂移即 stale_state");
            var badId:Object = MercLoadoutService.deliver(0, "别的佣兵", "12", 0, snapshotRef(bag, 0, 3));
            check(badId.error == "merc_id_mismatch",
                "mercId 不匹配即 merc_id_mismatch");
            check(MercLoadoutService.deliver(5, "m1", "12", 0, null).error == "merc_not_found"
                    && MercLoadoutService.deliver(-1, "m1", "12", 0, null).error == "invalid_index",
                "越界/非法 mercIndex 分别报 merc_not_found 与 invalid_index");
            check(MercLoadoutService.deliver(0, "m1", "16", 0, null).error == "slot_locked",
                "手雷槽 16 写操作 slot_locked");

            var leaseRef:Object = snapshotRef(bag, 0, 3);
            bag.transactionWrite(1, new BaseItem("测试占位", 1, 1));
            bag.transactionWrite(1, null);
            var staleLease:Object = MercLoadoutService.deliver(0, "m1", "12", 0, leaseRef);
            check(staleLease.error == "stale_state" && bag.getItem("0") === original,
                "背包 revision 推进后旧 lease 交付 stale_state 且不移除原物");

            var wrongContainer:Object = MercLoadoutService.deliver(0, "m1", "12", 0, {
                containerId:"战备箱", slot:0, expectedLease:"x"
            });
            check(wrongContainer.error == "unsupported_container",
                "非背包容器 unsupported_container");

            var first:Object = MercLoadoutService.deliver(0, "m1", "12", 0, snapshotRef(bag, 0, 3));
            bag.add(1, new BaseItem("测试长枪A", {level:2}, 333));
            var again:Object = MercLoadoutService.deliver(0, "m1", "12", 1, snapshotRef(bag, 1, 3));
            check(first.success === true && again.error == "custody_exists"
                    && bag.getItem("1") != null,
                "已有有效托管的槽位重复交付 custody_exists 提示改用 replace");
            var nullSource:Object = MercLoadoutService.deliver(0, "m1", "13", 1, null);
            check(nullSource.error == "invalid_payload",
                "空 source 在 lease 复证处 invalid_payload（断言序：公共门先于 lease）");
        } finally {
            restoreRoot(s);
        }
    }

    /**
     * transactionWrite 的三个可见提交阶段均注入同步异常。
     * 每个阶段都要证明交付失败时所有权唯一，且故障清除后原请求可直接重试。
     */
    private static function testDeliverCommitFailureAtomicity():Void {
        var s:Object = saveRoot();
        try {
            var phases:Array = ["mutation", "rebuildIndexes", "bumpRevision"];
            for (var i:Number = 0; i < phases.length; i++) {
                testDeliverCommitFailurePhase(String(phases[i]));
            }
        } finally {
            restoreRoot(s);
        }
    }

    private static function testDeliverCommitFailurePhase(phase:String):Void {
        var scene:Object = setupMercScene(2);
        var m:Array = scene.merc;
        var bag:ArrayInventory = scene.bag;
        var original:BaseItem = new BaseItem("测试长枪B", {level:6, shot:7}, 410000);
        bag.add(0, original);
        var source:Object = snapshotRef(bag, 0, 2);
        var beforeRevision:Number = bag.getMutationRevision();

        bag._setTransactionWriteFaultHookForTests(makeTransactionWriteFault(phase));
        var failed:Object;
        try {
            failed = MercLoadoutService.deliver(0, "m1", "12", 0, source);
        } finally {
            bag._setTransactionWriteFaultHookForTests(null);
        }
        check(failed != null && failed.success !== true && failed.error == "commit_failed"
                && bag.getItem("0") === original
                && bag.getMutationRevision() == beforeRevision
                && !MercLoadoutService.hasAnyCustody(m)
                && MercLoadoutService.getLoadoutRevision(m) == 0
                && _root.存档系统.dirtyMark === false,
            "交付在 " + phase + " 异常时恢复背包/revision 且撤销托管、不标脏");

        var retried:Object = MercLoadoutService.deliver(0, "m1", "12", 0, snapshotRef(bag, 0, 2));
        check(retried != null && retried.success === true
                && bag.getItem("0") == null
                && MercLoadoutService.hasAnyCustody(m),
            "交付在 " + phase + " 故障清除后重试成功且所有权唯一");
    }

    private static function makeTransactionWriteFault(expectedPhase:String):Function {
        return function(actualPhase:String):Void {
            if (actualPhase == expectedPhase) {
                throw new Error("transactionWrite injected failure: " + expectedPhase);
            }
        };
    }

    private static function testReplaceFlow():Void {
        var s:Object = saveRoot();
        try {
            var scene:Object = setupMercScene(3);
            var m:Array = scene.merc;
            var bag:ArrayInventory = scene.bag;
            bag.add(0, new BaseItem("测试长枪B", {level:6, shot:7, mods:["旧插件"]}, 111));

            var empty:Object = MercLoadoutService.replace(0, "m1", "12", 0, snapshotRef(bag, 0, 3));
            check(empty.error == "no_custody",
                "无托管槽位 replace 报 no_custody");

            var delivered:Object = MercLoadoutService.deliver(0, "m1", "12", 0, snapshotRef(bag, 0, 3));
            var newGun:BaseItem = new BaseItem("测试长枪A", {level:9, shot:2}, 222);
            bag.add(1, newGun);
            var replaced:Object = MercLoadoutService.replace(0, "m1", "12", 1, snapshotRef(bag, 1, 3));
            var landed:BaseItem = BaseItem(bag.getItem("1"));
            check(delivered.success === true && replaced.success === true
                    && Number(replaced.loadoutRevision) == 2,
                "replace 成功并递增 loadoutRevision");
            check(landed != null && landed.name == "测试长枪B"
                    && landed.value.shot == 7 && landed.value.mods[0] == "旧插件"
                    && landed.lastUpdate == 111,
                "旧冻结物重建后落回新物品原来的背包格（无需空位）");
            check(m[19].装备托管.slots["12"].item.name == "测试长枪A"
                    && m[19].装备托管.slots["12"].item.value.level == 9,
                "新物品冻结快照接管托管槽");
            check(_root.存档系统.dirtyMark === true
                    && MercLoadoutService.buildLoadoutProjection(m, 0).slots["12"].custody.name == "测试长枪A",
                "replace 标脏且投影跟进新托管");
        } finally {
            restoreRoot(s);
        }
    }

    private static function testReplaceFailuresAndRollback():Void {
        var s:Object = saveRoot();
        try {
            var scene:Object = setupMercScene(3);
            var m:Array = scene.merc;
            var bag:ArrayInventory = scene.bag;
            bag.add(0, new BaseItem("测试长枪B", {level:6}, 111));
            MercLoadoutService.deliver(0, "m1", "12", 0, snapshotRef(bag, 0, 3));

            m[19].装备托管.slots["12"] = {version:2, item:null};
            bag.add(1, new BaseItem("测试长枪A", {level:1}, 222));
            var corruptVersion:Object = MercLoadoutService.replace(0, "m1", "12", 1, snapshotRef(bag, 1, 3));
            check(corruptVersion.error == "custody_corrupt"
                    && bag.getItem("1") != null,
                "未知版本旧托管 fail-closed 且新物品不动");

            m[19].装备托管.slots["12"] = {
                version:1,
                item:new BaseItem("测试手枪", {level:1}, 5).toObject()
            };
            var corruptUse:Object = MercLoadoutService.replace(0, "m1", "12", 1, snapshotRef(bag, 1, 3));
            check(corruptUse.error == "custody_corrupt",
                "use 不匹配槽位的旧托管快照同样 fail-closed");

            var phases:Array = ["mutation", "rebuildIndexes", "bumpRevision"];
            for (var i:Number = 0; i < phases.length; i++) {
                testReplaceRollbackPhase(String(phases[i]));
            }
        } finally {
            restoreRoot(s);
        }
    }

    private static function testReplaceRollbackPhase(phase:String):Void {
        var scene:Object = setupMercScene(3);
        var m:Array = scene.merc;
        var bag:ArrayInventory = scene.bag;
        bag.add(0, new BaseItem("测试长枪B", {level:6, shot:7}, 111));
        MercLoadoutService.deliver(0, "m1", "12", 0, snapshotRef(bag, 0, 3));
        var oldRecord:Object = m[19].装备托管.slots["12"];
        var newGun:BaseItem = new BaseItem("测试长枪A", {level:9}, 222);
        bag.add(1, newGun);
        _root.存档系统.dirtyMark = false;

        bag._setTransactionWriteFaultHookForTests(makeTransactionWriteFault(phase));
        var failed:Object;
        try {
            failed = MercLoadoutService.replace(0, "m1", "12", 1, snapshotRef(bag, 1, 3));
        } finally {
            bag._setTransactionWriteFaultHookForTests(null);
        }
        check(failed != null && failed.success !== true && failed.error == "commit_failed"
                && bag.getItem("1") === newGun
                && m[19].装备托管.slots["12"] === oldRecord
                && MercLoadoutService.getLoadoutRevision(m) == 1
                && _root.存档系统.dirtyMark === false,
            "replace 在 " + phase + " 异常时背包保留新物品且托管还原旧记录");

        var retried:Object = MercLoadoutService.replace(0, "m1", "12", 1, snapshotRef(bag, 1, 3));
        check(retried != null && retried.success === true
                && bag.getItem("1") != null && bag.getItem("1").name == "测试长枪B"
                && m[19].装备托管.slots["12"].item.name == "测试长枪A",
            "replace 在 " + phase + " 故障清除后可重试且新旧各归其位");
    }

    private static function testWithdrawFlow():Void {
        var s:Object = saveRoot();
        try {
            var scene:Object = setupMercScene(3);
            var m:Array = scene.merc;
            var bag:ArrayInventory = scene.bag;
            var original:BaseItem = new BaseItem("测试长枪B", {
                level:6, shot:7, mods:["战术背带"]
            }, 123456);
            bag.add(0, original);
            MercLoadoutService.deliver(0, "m1", "12", 0, snapshotRef(bag, 0, 3));
            _root.存档系统.dirtyMark = false;

            var withdrawn:Object = MercLoadoutService.withdraw(0, "m1", "12", 1);
            var restored:BaseItem = BaseItem(bag.getItem("0"));
            check(withdrawn.success === true && Number(withdrawn.targetSlot) == 0
                    && restored != null && restored !== original,
                "取回重建克隆写入首个空位（非原实例复用）");
            check(restored.value.level == 6 && restored.value.shot == 7
                    && restored.value.mods[0] == "战术背带" && restored.lastUpdate == 123456,
                "取回只恢复交付瞬间的冻结物品");
            check(m[19].装备托管.slots["12"] == undefined
                    && !MercLoadoutService.hasAnyCustody(m)
                    && MercLoadoutService.getLoadoutRevision(m) == 2,
                "背包真实持有恢复对象后才清除托管记录并递增 revision");
            check(_root.存档系统.dirtyMark === true,
                "取回成功标脏存档");
            var proj:Object = MercLoadoutService.buildLoadoutProjection(m, 0);
            check(proj.slots["12"].state == "preset"
                    && proj.slots["12"].preset.name == "测试长枪A",
                "取回后槽位投影自动回落预设");
        } finally {
            restoreRoot(s);
        }
    }

    private static function testWithdrawFailures():Void {
        var s:Object = saveRoot();
        try {
            var scene:Object = setupMercScene(2);
            var m:Array = scene.merc;
            var bag:ArrayInventory = scene.bag;
            check(MercLoadoutService.withdraw(0, "m1", "12", 0).error == "no_custody",
                "无托管取回 no_custody");

            bag.add(0, new BaseItem("测试长枪B", {level:6, shot:7}, 111));
            MercLoadoutService.deliver(0, "m1", "12", 0, snapshotRef(bag, 0, 2));
            bag.add(0, new BaseItem("测试占位", 1, 1));
            bag.add(1, new BaseItem("测试占位", 1, 1));
            var full:Object = MercLoadoutService.withdraw(0, "m1", "12", 1);
            check(full.error == "inventory_full" && MercLoadoutService.hasAnyCustody(m),
                "满背包取回预检失败关闭且保留托管权威");
            bag.transactionWrite(0, null);
            bag.transactionWrite(1, null);

            m[19].装备托管.slots["12"] = {version:2, item:null};
            check(MercLoadoutService.withdraw(0, "m1", "12", 1).error == "custody_corrupt",
                "损坏托管记录取回 custody_corrupt");
            m[19].装备托管.slots["12"] = {
                version:1, item:new BaseItem("测试长枪A", {level:2, shot:1}, 5).toObject()
            };

            bag._setTransactionWriteFaultHookForTests(makeTransactionWriteFault("mutation"));
            var failed:Object;
            try {
                failed = MercLoadoutService.withdraw(0, "m1", "12", 1);
            } finally {
                bag._setTransactionWriteFaultHookForTests(null);
            }
            check(failed.error == "commit_failed" && MercLoadoutService.hasAnyCustody(m)
                    && bag.getItem("0") == null
                    && MercLoadoutService.getLoadoutRevision(m) == 1,
                "取回提交异常时保留托管且背包/revision 不变");
            var retried:Object = MercLoadoutService.withdraw(0, "m1", "12", 1);
            check(retried.success === true && bag.getItem("0") != null
                    && bag.getItem("0").name == "测试长枪A"
                    && !MercLoadoutService.hasAnyCustody(m),
                "取回故障清除后重试成功且只恢复一份物品");
        } finally {
            restoreRoot(s);
        }
    }

    private static function testCorruptSlotFailsClosed():Void {
        var s:Object = saveRoot();
        try {
            var scene:Object = setupMercScene(2);
            var m:Array = scene.merc;
            var bag:ArrayInventory = scene.bag;
            // AS2 对象字面量不接受引号数字键，括号赋值建立槽位记录
            var corruptSlots:Object = {};
            corruptSlots["12"] = {version:2, item:null};
            m[19].装备托管 = {version:1, loadoutRevision:3, slots:corruptSlots};
            bag.add(0, new BaseItem("测试长枪B", {level:6}, 111));

            check(MercLoadoutService.hasAnyCustody(m),
                "损坏记录仍占据槽位（解雇守卫判有托管）");
            check(MercLoadoutService.deliver(0, "m1", "12", 3, snapshotRef(bag, 0, 2)).error == "custody_corrupt",
                "损坏占位槽交付 fail-closed");
            check(MercLoadoutService.replace(0, "m1", "12", 3, snapshotRef(bag, 0, 2)).error == "custody_corrupt",
                "损坏占位槽替换 fail-closed");
            check(MercLoadoutService.withdraw(0, "m1", "12", 3).error == "custody_corrupt",
                "损坏占位槽取回 fail-closed");
            check(MercLoadoutService.buildLoadoutProjection(m, 0).slots["12"].state == "custody_corrupt",
                "损坏占位槽投影三态为 custody_corrupt");
            check(MercLoadoutService.buildSpawnLoadout(m).长枪 == "测试长枪A",
                "损坏占位槽出战生成安全回退预设字符串");

            _root.可雇佣兵 = [];
            _root.隐藏的可雇佣兵 = [];
            _root.同伴数 = 1;
            _root.菜单MC对应名 = "菜单";
            _root.gameworld = {菜单:{removeMovieClip:function():Void {}}};
            var removed = MercSpawner.removeMerc("m1");
            check(removed != undefined && removed.success !== true
                    && removed.error == "custody_not_empty"
                    && _root.同伴数据[0] === m && _root.同伴数 == 1,
                "解雇守卫：损坏占位阻塞 removeMerc 且零写入");
        } finally {
            restoreRoot(s);
        }
    }

    private static function testSpawnLoadout():Void {
        var s:Object = saveRoot();
        try {
            var scene:Object = setupMercScene(2);
            var m:Array = scene.merc;
            var bag:ArrayInventory = scene.bag;

            var presetOnly:Object = MercLoadoutService.buildSpawnLoadout(m);
            check(presetOnly.头部装备 == "测试头盔" && presetOnly.长枪 == "测试长枪A"
                    && presetOnly.刀 == "" && presetOnly.颈部装备 == "",
                "无托管时十键恒为预设字符串原样（含空串）");
            var grenadeAbsent:Boolean = presetOnly.手雷 === undefined;
            for (var key:String in presetOnly) {
                if (key == "手雷") grenadeAbsent = false;
            }
            check(grenadeAbsent,
                "出战解析不返回手雷键");

            bag.add(0, new BaseItem("测试长枪B", {level:6, shot:7}, 111));
            MercLoadoutService.deliver(0, "m1", "12", 0, snapshotRef(bag, 0, 2));
            var first:Object = MercLoadoutService.buildSpawnLoadout(m);
            check(first.长枪 instanceof BaseItem && first.长枪.name == "测试长枪B",
                "托管槽产出 BaseItem 克隆而非字符串");
            var second:Object = MercLoadoutService.buildSpawnLoadout(m);
            check(second.长枪 instanceof BaseItem && second.长枪 !== first.长枪,
                "每次调用产出全新克隆");
            first.长枪.value.shot = 99;
            check(m[19].装备托管.slots["12"].item.value.shot == 7,
                "出战克隆的战斗变化不回写托管权威");
        } finally {
            restoreRoot(s);
        }
    }

    private static function testCandidates():Void {
        var s:Object = saveRoot();
        try {
            var scene:Object = setupMercScene(4);
            var m:Array = scene.merc;
            var bag:ArrayInventory = scene.bag;
            bag.add(0, new BaseItem("测试长枪B", {level:6}, 111));
            bag.add(1, new BaseItem("测试手枪", {level:2}, 222));
            bag.add(2, new BaseItem("测试重炮", {level:1}, 333));

            var result:Object = MercLoadoutService.buildCandidates(m, 12);
            check(result.success === true && result.candidates.length == 2
                    && Number(result.loadoutRevision) == 0,
                "候选只列 use 匹配该槽的背包物品（手枪不产生跨槽噪声）");
            var first:Object = result.candidates[0];
            check(first.eligible === true && first.lockReason == ""
                    && first.source.containerId == "背包"
                    && Number(first.source.slot) == 0
                    && String(first.source.expectedLease).length > 0
                    && first.item != null && first.item.name == "测试长枪B",
                "合格候选携带背包 lease 引用与物品投影");
            var second:Object = result.candidates[1];
            check(second.eligible === false && second.lockReason == "level_locked"
                    && Number(second.requirementLevel) == 30,
                "高需求等级候选盖章 level_locked 与需求等级");
            MercLoadoutService.deliver(0, "m1", "12", 0, snapshotRef(bag, 0, 4));
            var after:Object = MercLoadoutService.buildCandidates(m, 12);
            check(Number(after.loadoutRevision) == 1 && after.candidates.length == 1
                    && after.candidates[0].item.name == "测试重炮",
                "交付后候选 revision 跟进且已交付物品退出列表");
            check(MercLoadoutService.buildCandidates(m, 16).error == "slot_locked",
                "手雷槽候选 slot_locked");
        } finally {
            restoreRoot(s);
        }
    }

    private static function testSlotTooltip():Void {
        var s:Object = saveRoot();
        try {
            var scene:Object = setupMercScene(2);
            var m:Array = scene.merc;
            var bag:ArrayInventory = scene.bag;

            var preset:Object = MercLoadoutService.buildSlotTooltip(m, 6, null);
            check(preset.success === true && preset.itemName == "测试头盔"
                    && preset.introHTML != undefined && preset.descHTML != undefined,
                "预设槽 tooltip 按默认强化口径生成实例级富注释");
            check(MercLoadoutService.buildSlotTooltip(m, 7, null).error == "item_data_missing",
                "空预设槽 tooltip item_data_missing");

            bag.add(0, new BaseItem("测试长枪B", {level:6, shot:7}, 111));
            var ref:Object = snapshotRef(bag, 0, 2);
            var candidate:Object = MercLoadoutService.buildSlotTooltip(m, 12, ref);
            check(candidate.success === true && candidate.itemName == "测试长枪B",
                "背包候选 tooltip 按当前 lease 读取真实实例");
            bag.transactionWrite(1, new BaseItem("测试占位", 1, 1));
            bag.transactionWrite(1, null);
            check(MercLoadoutService.buildSlotTooltip(m, 12, ref).error == "stale_state",
                "过期 lease 的候选 tooltip stale_state");

            MercLoadoutService.deliver(0, "m1", "12", 0, snapshotRef(bag, 0, 2));
            var managed:Object = MercLoadoutService.buildSlotTooltip(m, 12, null);
            check(managed.success === true && managed.itemName == "测试长枪B",
                "托管槽 tooltip 从冻结权威的运行时克隆生成");
            m[19].装备托管.slots["12"] = {version:1, item:{name:"不存在的枪", value:{level:1}}};
            check(MercLoadoutService.buildSlotTooltip(m, 12, null).error == "custody_corrupt",
                "无法重建的托管快照 tooltip custody_corrupt");
        } finally {
            restoreRoot(s);
        }
    }

    /**
     * 托管写可能从其他全局事件回调进入。库存通知监听器抛错或在通知内重入时，
     * 服务必须隔离通知异常、拒绝重入并精确恢复 EventBus dispatch 槽。
     */
    private static function testBusyReentryAndNotificationIsolation():Void {
        var s:Object = saveRoot();
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__mercLoadoutThrowingEvents", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        try {
            var scene:Object = setupMercScene(2);
            var m:Array = scene.merc;
            var bag:ArrayInventory = scene.bag;
            bag.setDispatcher(dispatcher);
            bag.add(0, new BaseItem("测试长枪B", {level:6, shot:7}, 111));

            var reentry:Object = null;
            var throwAndReenter:Function = function():Void {
                reentry = MercLoadoutService.deliver(0, "m1", "13", 1, null);
                throw new Error("merc-loadout ItemRemoved listener");
            };
            dispatcher.subscribe("ItemRemoved", throwAndReenter);
            var handoff:Object = MercLoadoutService.deliver(0, "m1", "12", 0, snapshotRef(bag, 0, 2));
            check(handoff.success === true && bag.getItem("0") == null
                    && MercLoadoutService.hasAnyCustody(m)
                    && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
                "交付提交后的 ItemRemoved 监听器异常不改写成功结果且恢复事件总线");
            check(reentry != null && reentry.success !== true && reentry.error == "busy",
                "通知回调内重入写操作被 _busy 拒绝");

            var throwAdded:Function = function():Void {
                throw new Error("merc-loadout ItemAdded listener");
            };
            dispatcher.subscribe("ItemAdded", throwAdded);
            var withdrawn:Object = MercLoadoutService.withdraw(0, "m1", "12", 1);
            check(withdrawn.success === true && bag.getItem("0") != null
                    && !MercLoadoutService.hasAnyCustody(m)
                    && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
                "取回提交后的 ItemAdded 监听器异常不改写成功结果并恢复事件总线/busy");
        } finally {
            dispatcher.destroy();
            holder.removeMovieClip();
            restoreRoot(s);
        }
    }

    /** MercPanelService 集成：install 注册、解雇守卫早反馈与读命令全链路。 */
    private static function testDismissGuardAndPanelCommands():Void {
        var s:Object = saveRoot();
        try {
            var scene:Object = setupMercScene(2);
            var m:Array = scene.merc;
            var bag:ArrayInventory = scene.bag;
            _root.可雇佣兵 = [];
            _root.隐藏的可雇佣兵 = [];
            _root.同伴数 = 1;
            _root.菜单MC对应名 = "菜单";
            _root.gameworld = {菜单:{removeMovieClip:function():Void {}}};
            var sent:Array = [];
            _root.server = {sendSocketMessage:function(msg:String):Void { sent.push(String(msg)); }};
            _root.gameCommands = undefined;

            MercPanelService.install();
            check(typeof _root.gameCommands["mercLoadoutDeliver"] == "function"
                    && typeof _root.gameCommands["mercLoadoutReplace"] == "function"
                    && typeof _root.gameCommands["mercLoadoutWithdraw"] == "function"
                    && typeof _root.gameCommands["mercLoadoutCandidates"] == "function"
                    && typeof _root.gameCommands["mercLoadoutTooltip"] == "function",
                "install 注册 5 个托管 gameCommands");

            bag.add(0, new BaseItem("测试长枪B", {level:6}, 111));
            MercLoadoutService.deliver(0, "m1", "12", 0, snapshotRef(bag, 0, 2));
            var sentBefore:Number = sent.length;
            MercPanelService.handleDismiss({callId:"d1", mercIndex:0});
            check(sent.length == sentBefore + 1
                    && sent[sent.length - 1].indexOf("custody_not_empty") > -1
                    && _root.同伴数据[0] === m && _root.同伴数 == 1,
                "handleDismiss 托管早期反馈 custody_not_empty 且零写入");

            MercLoadoutService.withdraw(0, "m1", "12", 1);
            var removeResult = MercSpawner.removeMerc("m1");
            check(removeResult != undefined && removeResult.success === true
                    && _root.同伴数据.length == 0 && _root.佣兵是否出战信息.length == 0,
                "逐槽取回后 removeMerc 放行并返回 success");

            _root.同伴数据 = [merc(10, "m2")];
            _root.佣兵是否出战信息 = [0];
            _root.同伴数 = 1;
            _root.gameCommands["mercLoadoutCandidates"]({callId:"c1", mercIndex:0, mercId:"m2", slotKey:"12"});
            check(sent[sent.length - 1].indexOf("candidates") > -1
                    && sent[sent.length - 1].indexOf("测试长枪B") > -1,
                "mercLoadoutCandidates 经 gameCommands 全链路返回候选快照");
            _root.gameCommands["mercLoadoutTooltip"]({callId:"t1", mercIndex:0, mercId:"m2", slotKey:"6"});
            check(sent[sent.length - 1].indexOf("测试头盔") > -1,
                "mercLoadoutTooltip 经 gameCommands 全链路返回预设 tooltip");
        } finally {
            restoreRoot(s);
        }
    }

    private static function check(condition:Boolean, message:String):Void {
        if (condition) {
            passed++;
            trace("[PASS] " + message);
        } else {
            failed++;
            trace("[FAIL] " + message);
        }
    }
}
