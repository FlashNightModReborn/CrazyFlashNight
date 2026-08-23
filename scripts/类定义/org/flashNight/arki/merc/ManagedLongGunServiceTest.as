import org.flashNight.aven.test.*;
import org.flashNight.arki.merc.ManagedLongGunService;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.BladeFireSpinController;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

/** T800 托管长枪 policy 与冻结边界的纯 AS2 回归。 */
class org.flashNight.arki.merc.ManagedLongGunServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        trace("=== ManagedLongGunServiceTest start ===");
        var catalogReceipt:Object = installCatalogFixture();
        try {
            testRankAndLevelCaps();
            testInitialSubtypeGate();
            testMiddleAndFinalLongGunGate();
            testFrozenSnapshotIsolation();
            testCorruptCustodyFailsClosed();
            testUnsupportedCustodyFailsClosed();
            testLeaseBoundHandoffAndFrozenWithdrawal();
            testTransactionCommitFailureAtomicity();
            testPostCommitNotificationIsolationAndBusyRecovery();
            testNestedEventBusNotificationIsolation();
            testUnitPreparationAndNonHeroAmmoSentinel();
            testUnitPreparationInstallsDressupLifecycleBridge();
            testT800DressupProjectionPreservesEnemyAuthority();
            testM134SuccessfulShotIntent();
        } finally {
            restoreCatalogFixture(catalogReceipt);
        }
        trace("ManagedLongGunServiceTest Tests Passed: " + passed);
        trace("ManagedLongGunServiceTest Tests Failed: " + failed);
        trace("=== ManagedLongGunServiceTest end ===");
    }

    private static function pet(level:Number, attrs:Object):Array {
        return [66, level, 200, 0, 0, attrs == null ? {} : attrs];
    }

    private static function gun(useName:String, subtype:String, level:Number):Object {
        return {use:useName, weapontype:subtype, data:{level:level}};
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
        ItemUtil.itemDataDict["L85A1"] = {
            name:"L85A1", displayname:"L85A2", icon:"L85A1",
            type:"武器", use:"长枪", weapontype:"突击步枪",
            data:{level:5, modslot:1}
        };
        ItemUtil.itemDataDict["战术版AK200"] = {
            name:"战术版AK200", displayname:"战术版AK200", icon:"战术版AK200",
            type:"武器", use:"长枪", weapontype:"突击步枪",
            data:{level:27, modslot:1}
        };
        ItemUtil.itemDataDict["KRISS"] = {
            name:"KRISS", displayname:"KRISS", icon:"KRISS",
            type:"武器", use:"手枪", weapontype:"冲锋手枪",
            data:{level:1, modslot:1}
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

    private static function testRankAndLevelCaps():Void {
        var initial:Array = pet(40, {});
        var middle:Array = pet(40, {终结者武器扩展:true});
        var finalRank:Array = pet(40, {终结者全武装:true});
        check(ManagedLongGunService.getRank(initial) == 0
            && ManagedLongGunService.getWeaponLevelLimit(initial) == 15,
            "初阶武器等级上限固定为 min(15, 战宠等级)");
        check(ManagedLongGunService.getRank(middle) == 1
            && ManagedLongGunService.getWeaponLevelLimit(middle) == 30,
            "中阶武器等级上限固定为 min(30, 战宠等级)");
        check(ManagedLongGunService.getRank(finalRank) == 2
            && ManagedLongGunService.getWeaponLevelLimit(finalRank) == 40,
            "终阶只保留不得高于战宠自身等级");
    }

    private static function testInitialSubtypeGate():Void {
        var t800:Array = pet(20, {});
        check(ManagedLongGunService.evaluateDataForPet(t800, gun("长枪", "冲锋枪", 15)).success,
            "初阶允许冲锋枪");
        check(ManagedLongGunService.evaluateDataForPet(t800, gun("长枪", "突击步枪", 15)).success,
            "初阶允许突击步枪");
        var battle:Object = ManagedLongGunService.evaluateDataForPet(t800, gun("长枪", "战斗步枪", 15));
        check(!battle.success && battle.error == "weapon_type_locked",
            "初阶拒绝战斗步枪等较强门类");
        var tooHigh:Object = ManagedLongGunService.evaluateDataForPet(t800, gun("长枪", "突击步枪", 16));
        check(!tooHigh.success && tooHigh.error == "weapon_level_locked",
            "初阶拒绝需求等级高于 15 的允许门类");
    }

    private static function testMiddleAndFinalLongGunGate():Void {
        var middle:Array = pet(40, {终结者武器扩展:true});
        check(ManagedLongGunService.evaluateDataForPet(middle, gun("长枪", "发射器", 30)).success,
            "中阶起枪种不限，允许 30 级发射器");
        var middleHigh:Object = ManagedLongGunService.evaluateDataForPet(middle, gun("长枪", "特殊", 31));
        check(!middleHigh.success && middleHigh.error == "weapon_level_locked",
            "中阶仍保留 30 级需求上限");

        var finalRank:Array = pet(55, {终结者全武装:true});
        check(ManagedLongGunService.evaluateDataForPet(finalRank, gun("长枪", "特殊", 55)).success,
            "终阶允许任意长枪门类至自身等级");
        var beyondPet:Object = ManagedLongGunService.evaluateDataForPet(finalRank, gun("长枪", "特殊", 56));
        check(!beyondPet.success && beyondPet.error == "weapon_level_locked",
            "终阶仍拒绝高于战宠自身等级的武器");
        var notLongGun:Object = ManagedLongGunService.evaluateDataForPet(finalRank, gun("手枪", "冲锋枪", 1));
        check(!notLongGun.success && notLongGun.error == "not_long_gun",
            "任何阶位都只接受 use=长枪");
    }

    private static function testFrozenSnapshotIsolation():Void {
        var original:Object = {
            name:"测试托管长枪",
            value:{level:7, shot:4, mods:["测试插件"]},
            lastUpdate:123
        };
        var fakeItem:Object = {
            toObject:function():Object { return original; }
        };
        var frozen:Object = ManagedLongGunService.freezeItem(fakeItem);
        original.value.shot = 99;
        original.value.mods[0] = "已污染";
        check(frozen != null && frozen.value.shot == 4
            && frozen.value.mods[0] == "测试插件",
            "冻结交付快照与来源对象深度隔离");
        var second:Object = ObjectUtil.clone(frozen);
        second.value.shot = -1;
        check(frozen.value.shot == 4,
            "运行态副本变化不回写冻结权威");
    }

    private static function testCorruptCustodyFailsClosed():Void {
        var corrupt:Array = pet(40, {
            托管长枪:{version:2, item:null}
        });
        check(ManagedLongGunService.hasCustody(corrupt),
            "未知版本仍占用托管位，禁止新交付覆盖");
        var state:Object = ManagedLongGunService.buildPanelState(corrupt, null);
        check(state != null && state.custodyCorrupt === true
                && state.weapon == null && state.candidates.length == 0,
            "损坏托管快照失败关闭且不投影候选武器");
        check(state.defaultWeaponView != null
                && state.defaultWeaponView.name == "L85A1"
                && String(state.defaultWeaponView.icon).length > 0,
            "预设长枪也通过物品权威投影提供图标，不由 Web 维护名称映射");
        var preflight:Object = ManagedLongGunService.preflightWithdrawal(corrupt);
        check(preflight.success !== true && preflight.error == "custody_corrupt",
            "损坏托管快照禁止取回与删除宠物");

        var wrongUse:Array = pet(40, {
            托管长枪:{version:1, item:new BaseItem("KRISS", {level:1, shot:0, mods:[]}, 1).toObject()}
        });
        var wrongUsePreflight:Object = ManagedLongGunService.preflightWithdrawal(wrongUse);
        check(wrongUsePreflight.success !== true && wrongUsePreflight.error == "custody_corrupt",
            "有效但非长枪的伪托管快照同样失败关闭");
    }

    private static function testUnsupportedCustodyFailsClosed():Void {
        var unsupported:Array = [999, 40, 200, 0, 0, {
            托管长枪:{version:1, item:{name:"未知托管武器"}}
        }];
        var preflight:Object = ManagedLongGunService.preflightWithdrawal(unsupported);
        check(preflight.success !== true && preflight.error == "unsupported_pet",
            "未登记 policy 的托管字段禁止通过删除路径丢失物品");
    }

    private static function testLeaseBoundHandoffAndFrozenWithdrawal():Void {
        var oldInventory:Object = _root.物品栏;
        var oldCombat:Object = _root.当前为战斗地图;
        var oldSave:Object = _root.存档系统;
        try {
            var bag:ArrayInventory = new ArrayInventory(null, 2);
            _root.物品栏 = {背包:bag};
            _root.当前为战斗地图 = false;
            _root.存档系统 = {dirtyMark:false};

            var original:BaseItem = new BaseItem("L85A1", {
                level:6,
                shot:7,
                mods:["战术背带"]
            }, 123456);
            bag.add(0, original);
            var t800:Array = pet(10, {});
            var snapshot:Object = InventoryPanelService.buildExternalSnapshot("背包", 0, 2);
            var firstRef:Object = {
                containerId:"背包",
                slot:0,
                expectedLease:String(snapshot.slots[0].slotLease)
            };

            // 只推进一次无关槽位 revision，即可证明旧 lease 不能转移所有权。
            bag.transactionWrite(1, new BaseItem("测试占位", 1, 1));
            bag.transactionWrite(1, null);
            var stale:Object = ManagedLongGunService.handoff(t800, firstRef);
            check(stale.success !== true && stale.error == "stale_state"
                    && bag.getItem("0") === original && !ManagedLongGunService.hasCustody(t800),
                "交付必须复证当前背包 lease，过期引用不改变所有权");

            snapshot = InventoryPanelService.buildExternalSnapshot("背包", 0, 2);
            firstRef.expectedLease = String(snapshot.slots[0].slotLease);
            var candidateTooltip:Object = ManagedLongGunService.buildWeaponTooltip(t800, firstRef);
            check(candidateTooltip.success === true && candidateTooltip.itemName == "L85A1"
                    && candidateTooltip.introHTML != undefined
                    && candidateTooltip.descHTML != undefined,
                "背包候选注释按当前 lease 读取真实强化实例并复用 canonical composer");
            _root.当前为战斗地图 = true;
            var combatLocked:Object = ManagedLongGunService.handoff(t800, firstRef);
            check(combatLocked.success !== true && combatLocked.error == "combat_locked"
                    && bag.getItem("0") === original && !ManagedLongGunService.hasCustody(t800),
                "战斗地图禁止交付且不改变背包或托管权威");
            _root.当前为战斗地图 = false;

            var handoff:Object = ManagedLongGunService.handoff(t800, firstRef);
            var frozen:Object = t800[5].托管长枪.item;
            check(handoff.success === true && bag.getItem("0") == null
                    && ManagedLongGunService.hasCustody(t800)
                    && frozen.value.level == 6 && frozen.value.shot == 7
                    && frozen.value.mods[0] == "战术背带" && frozen.lastUpdate == 123456,
                "交付原子移出背包并冻结强化、弹量、插件与时间戳");
            var managedTooltip:Object = ManagedLongGunService.buildWeaponTooltip(t800, null);
            check(managedTooltip.success === true && managedTooltip.itemName == "L85A1"
                    && managedTooltip.introHTML != undefined
                    && managedTooltip.descHTML != undefined,
                "当前托管武器注释从冻结权威的运行时克隆生成完整实例属性");

            var managedTarget:Object = {
                是否为敌人:false,
                宠物属性:{宠物库数组号:66, 托管长枪:t800[5].托管长枪}
            };
            ManagedLongGunService.prepareUnit(managedTarget);
            managedTarget.长枪.value.shot = 99;
            managedTarget.长枪.value.mods[0] = "运行态污染";
            check(managedTarget.长枪 !== original && managedTarget.使用托管长枪 === true
                    && frozen.value.shot == 7 && frozen.value.mods[0] == "战术背带",
                "出战单位只持有运行态克隆，射击与生命周期写入不回写冻结权威");

            var ordinaryEnemy:Object = {
                是否为敌人:true,
                长枪:"战术版AK200",
                宠物属性:{托管长枪:t800[5].托管长枪}
            };
            ManagedLongGunService.prepareUnit(ordinaryEnemy);
            check(ordinaryEnemy.长枪 == "战术版AK200"
                    && ordinaryEnemy.使用托管长枪 === false,
                "普通敌人忽略意外同名托管字段并保留关卡显式武器");

            bag.transactionWrite(0, new BaseItem("测试占位A", 1, 1));
            bag.transactionWrite(1, new BaseItem("测试占位B", 1, 1));
            var full:Object = ManagedLongGunService.preflightWithdrawal(t800);
            check(full.success !== true && full.error == "inventory_full"
                    && ManagedLongGunService.hasCustody(t800),
                "满背包时取回与删除预检失败关闭且保留托管权威");
            bag.transactionWrite(0, null);
            bag.transactionWrite(1, null);

            var withdrawn:Object = ManagedLongGunService.withdraw(t800);
            var restored:BaseItem = BaseItem(bag.getItem("0"));
            check(withdrawn.success === true && restored != null && restored !== original
                    && restored.value.level == 6 && restored.value.shot == 7
                    && restored.value.mods[0] == "战术背带" && restored.lastUpdate == 123456,
                "取回只重建交付快照，不带回 AI 免费换弹或运行态收益");
            check(!ManagedLongGunService.hasCustody(t800)
                    && _root.存档系统.dirtyMark === true,
                "背包真实持有恢复对象后才清除托管权威并标记存档");
        } finally {
            _root.物品栏 = oldInventory;
            _root.当前为战斗地图 = oldCombat;
            _root.存档系统 = oldSave;
        }
    }

    /**
     * transactionWrite 的三个可见提交阶段均注入同步异常。
     * 每个阶段都要同时证明交付/取回失败时所有权唯一，
     * 且清除故障后原请求可直接重试，不需要额外对账。
     */
    private static function testTransactionCommitFailureAtomicity():Void {
        var oldInventory:Object = _root.物品栏;
        var oldCombat:Object = _root.当前为战斗地图;
        var oldSave:Object = _root.存档系统;
        try {
            _root.当前为战斗地图 = false;
            var phases:Array = ["mutation", "rebuildIndexes", "bumpRevision"];
            for (var i:Number = 0; i < phases.length; i++) {
                testHandoffCommitFailurePhase(String(phases[i]));
                testWithdrawCommitFailurePhase(String(phases[i]));
            }
        } finally {
            _root.物品栏 = oldInventory;
            _root.当前为战斗地图 = oldCombat;
            _root.存档系统 = oldSave;
        }
    }

    private static function testHandoffCommitFailurePhase(phase:String):Void {
        var bag:ArrayInventory = new ArrayInventory(null, 2);
        _root.物品栏 = {背包:bag};
        _root.存档系统 = {dirtyMark:false};
        var original:BaseItem = new BaseItem("L85A1", {
            level:6, shot:7, mods:["交付提交故障"]
        }, 410000);
        bag.add(0, original);

        var t800:Array = pet(10, {});
        var snapshot:Object = InventoryPanelService.buildExternalSnapshot("背包", 0, 2);
        var source:Object = {
            containerId:"背包",
            slot:0,
            expectedLease:String(snapshot.slots[0].slotLease)
        };
        var beforeItems:Object = bag.getItems();
        var beforeTree:Object = bag.getTreeSet();
        var beforeIndexes:String = String(bag.getIndexes());
        var beforeRevision:Number = bag.getMutationRevision();

        bag._setTransactionWriteFaultHookForTests(makeTransactionWriteFault(phase));
        var failed:Object;
        try {
            failed = ManagedLongGunService.handoff(t800, source);
        } finally {
            bag._setTransactionWriteFaultHookForTests(null);
        }
        check(failed != null && failed.success !== true && failed.error == "commit_failed"
                && bag.getItem("0") === original && bag.getItems() === beforeItems
                && bag.getTreeSet() === beforeTree
                && String(bag.getIndexes()) == beforeIndexes
                && bag.size() == 1 && bag.getFirstVacancy() == 1
                && bag.getMutationRevision() == beforeRevision
                && !ManagedLongGunService.hasCustody(t800)
                && _root.存档系统.dirtyMark === false,
            "交付在 " + phase + " 异常时恢复物品/索引/revision 且撤销 custody");

        var retried:Object = ManagedLongGunService.handoff(t800, source);
        check(retried != null && retried.success === true
                && bag.getItem("0") == null && bag.size() == 0
                && ManagedLongGunService.hasCustody(t800),
            "交付在 " + phase + " 故障清除后原 lease 可重试且所有权唯一");
    }

    private static function testWithdrawCommitFailurePhase(phase:String):Void {
        var bag:ArrayInventory = new ArrayInventory(null, 2);
        _root.物品栏 = {背包:bag};
        _root.存档系统 = {dirtyMark:false};
        var original:BaseItem = new BaseItem("L85A1", {
            level:6, shot:5, mods:["取回提交故障"]
        }, 420000);
        bag.add(0, original);

        var t800:Array = pet(10, {});
        var snapshot:Object = InventoryPanelService.buildExternalSnapshot("背包", 0, 2);
        var source:Object = {
            containerId:"背包",
            slot:0,
            expectedLease:String(snapshot.slots[0].slotLease)
        };
        var seeded:Object = ManagedLongGunService.handoff(t800, source);
        var beforeCustody:Object = t800[5].托管长枪;
        var beforeItems:Object = bag.getItems();
        var beforeTree:Object = bag.getTreeSet();
        var beforeIndexes:String = String(bag.getIndexes());
        var beforeRevision:Number = bag.getMutationRevision();
        _root.存档系统.dirtyMark = false;

        bag._setTransactionWriteFaultHookForTests(makeTransactionWriteFault(phase));
        var failed:Object;
        try {
            failed = ManagedLongGunService.withdraw(t800);
        } finally {
            bag._setTransactionWriteFaultHookForTests(null);
        }
        check(seeded != null && seeded.success === true
                && failed != null && failed.success !== true && failed.error == "commit_failed"
                && bag.getItem("0") == null && bag.getItems() === beforeItems
                && !bag.getItems().hasOwnProperty("0")
                && bag.getTreeSet() === beforeTree
                && String(bag.getIndexes()) == beforeIndexes
                && bag.size() == 0 && bag.getFirstVacancy() == 0
                && bag.getMutationRevision() == beforeRevision
                && t800[5].托管长枪 === beforeCustody
                && ManagedLongGunService.hasCustody(t800)
                && _root.存档系统.dirtyMark === false,
            "取回在 " + phase + " 异常时恢复空背包/索引/revision 且保留 custody");

        var retried:Object = ManagedLongGunService.withdraw(t800);
        var restored:Object = bag.getItem("0");
        check(retried != null && retried.success === true
                && restored != null && restored.name == "L85A1"
                && bag.size() == 1 && String(bag.getIndexes()) == "0"
                && !ManagedLongGunService.hasCustody(t800),
            "取回在 " + phase + " 故障清除后可重试且只恢复一份武器");
    }

    private static function makeTransactionWriteFault(expectedPhase:String):Function {
        return function(actualPhase:String):Void {
            if (actualPhase == expectedPhase) {
                throw new Error("transactionWrite injected failure: " + expectedPhase);
            }
        };
    }

    private static function testPostCommitNotificationIsolationAndBusyRecovery():Void {
        var oldInventory:Object = _root.物品栏;
        var oldCombat:Object = _root.当前为战斗地图;
        var oldSave:Object = _root.存档系统;
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__managedLongGunThrowingEvents", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        try {
            var bag:ArrayInventory = new ArrayInventory(null, 2);
            _root.物品栏 = {背包:bag};
            _root.当前为战斗地图 = false;
            _root.存档系统 = {dirtyMark:false};
            var original:BaseItem = new BaseItem("L85A1", {
                level:6, shot:7, mods:["异常边界测试"]
            }, 123456);
            bag.add(0, original);
            bag.setDispatcher(dispatcher);

            var throwRemoved:Function = function():Void {
                throw new Error("managed-longgun ItemRemoved listener");
            };
            var throwAdded:Function = function():Void {
                throw new Error("managed-longgun ItemAdded listener");
            };
            dispatcher.subscribe("ItemRemoved", throwRemoved);
            dispatcher.subscribe("ItemAdded", throwAdded);

            var t800:Array = pet(10, {});
            var snapshot:Object = InventoryPanelService.buildExternalSnapshot("背包", 0, 2);
            var source:Object = {
                containerId:"背包",
                slot:0,
                expectedLease:String(snapshot.slots[0].slotLease)
            };
            var handoff:Object = ManagedLongGunService.handoff(t800, source);
            check(handoff.success === true && bag.getItem("0") == null
                    && ManagedLongGunService.hasCustody(t800)
                    && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
                "交付提交后的 ItemRemoved 监听器异常不改写成功结果且恢复事件总线");

            var withdrawn:Object = ManagedLongGunService.withdraw(t800);
            check(withdrawn.success === true && bag.getItem("0") != null
                    && !ManagedLongGunService.hasCustody(t800)
                    && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
                "取回提交后的 ItemAdded 监听器异常不改写成功结果并恢复事件总线/busy");

            // 再验证通知层之外的意外异常也会经过 finally 释放服务锁。
            bag.setDispatcher(null);
            var second:BaseItem = new BaseItem("L85A1", {
                level:6, shot:3, mods:[]
            }, 234567);
            bag.transactionWrite(0, second);
            var secondPet:Array = pet(10, {});
            snapshot = InventoryPanelService.buildExternalSnapshot("背包", 0, 2);
            source = {
                containerId:"背包",
                slot:0,
                expectedLease:String(snapshot.slots[0].slotLease)
            };
            var dirtyTrap:Object = {};
            dirtyTrap.addProperty("dirtyMark",
                function():Boolean { return false; },
                function(value:Boolean):Void {
                    throw new Error("managed-longgun dirty setter");
                });
            _root.存档系统 = dirtyTrap;
            var escaped:Boolean = false;
            try {
                ManagedLongGunService.handoff(secondPet, source);
            } catch (unexpectedError) {
                escaped = true;
            }
            _root.存档系统 = {dirtyMark:false};
            var recovered:Object = ManagedLongGunService.withdraw(secondPet);
            check(escaped && recovered.success === true
                    && !ManagedLongGunService.hasCustody(secondPet),
                "非通知型意外异常向外传播后 finally 仍释放 busy，允许按权威状态取回");
        } finally {
            dispatcher.destroy();
            holder.removeMovieClip();
            _root.物品栏 = oldInventory;
            _root.当前为战斗地图 = oldCombat;
            _root.存档系统 = oldSave;
        }
    }

    /**
     * 托管写可能从其他全局事件回调进入。库存通知监听器抛错时，
     * 服务的冷边界令牌只能恢复内层通知槽；绝不能清空外层快照并吞掉后续监听器。
     */
    private static function testNestedEventBusNotificationIsolation():Void {
        var oldInventory:Object = _root.物品栏;
        var oldCombat:Object = _root.当前为战斗地图;
        var oldSave:Object = _root.存档系统;
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__managedLongGunNestedEvents", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        var bus:EventBus = EventBus.getInstance();
        var outerEvent:String = "ManagedLongGunNestedOuter";
        var outerScope:Object = {};
        var handoffResult:Object = null;
        var outerTailRan:Boolean = false;
        var petInfo:Array = pet(10, {});

        var outerTail:Function = function():Void {
            outerTailRan = true;
        };
        var invokeHandoff:Function = function():Void {
            var snapshot:Object = InventoryPanelService.buildExternalSnapshot("背包", 0, 2);
            handoffResult = ManagedLongGunService.handoff(petInfo, {
                containerId:"背包",
                slot:0,
                expectedLease:String(snapshot.slots[0].slotLease)
            });
        };
        var throwRemoved:Function = function():Void {
            throw new Error("managed-longgun nested ItemRemoved listener");
        };

        try {
            var bag:ArrayInventory = new ArrayInventory(null, 2);
            bag.add(0, new BaseItem("L85A1", {
                level:6, shot:7, mods:["嵌套异常测试"]
            }, 345678));
            bag.setDispatcher(dispatcher);
            dispatcher.subscribe("ItemRemoved", throwRemoved);
            _root.物品栏 = {背包:bag};
            _root.当前为战斗地图 = false;
            _root.存档系统 = {dirtyMark:false};

            // EventBus 倒序派发：先订阅 tail，再订阅托管入口，确保托管先执行。
            bus.subscribe(outerEvent, outerTail, outerScope);
            bus.subscribe(outerEvent, invokeHandoff, outerScope);
            bus.publish0(outerEvent);

            check(handoffResult != null && handoffResult.success === true
                    && bag.getItem("0") == null && ManagedLongGunService.hasCustody(petInfo)
                    && outerTailRan,
                "嵌套库存监听器抛错后外层后续监听器仍继续执行");
            check(Number(bus["_dispatchDepth"]) == 0,
                "嵌套托管事务结束后 EventBus dispatch depth 精确恢复为 0");
        } finally {
            bus.unsubscribe(outerEvent, invokeHandoff, outerScope);
            bus.unsubscribe(outerEvent, outerTail, outerScope);
            dispatcher.destroy();
            holder.removeMovieClip();
            _root.物品栏 = oldInventory;
            _root.当前为战斗地图 = oldCombat;
            _root.存档系统 = oldSave;
        }
    }

    private static function testUnitPreparationAndNonHeroAmmoSentinel():Void {
        var target:Object = {
            是否为敌人:false,
            宠物属性:{宠物库数组号:66}
        };
        ManagedLongGunService.prepareUnit(target);
        check(target.长枪 == "L85A1" && target.使用托管长枪 === false
                && target.攻击模式 == "长枪" && target.enableShoot === true,
            "无托管武器的 T800 使用预设 L85A1");
        check(target.装备能力.复合枪械 === false && target.装备能力.自动抡枪 === false,
            "T800 显式关闭不受支持的复合枪械与自动抡枪能力");

        var unarmedEnemy:Object = {是否为敌人:true};
        ManagedLongGunService.prepareUnit(unarmedEnemy);
        check(unarmedEnemy.长枪 == null && unarmedEnemy.攻击模式 == "空手"
                && unarmedEnemy.enableShoot === false,
            "普通 T800 未配置长枪时只启用近战路径");
        var armedEnemy:Object = {是否为敌人:true, 长枪:"战术版AK200"};
        ManagedLongGunService.prepareUnit(armedEnemy);
        check(armedEnemy.长枪 == "战术版AK200" && armedEnemy.攻击模式 == "长枪"
                && armedEnemy.enableShoot === true,
            "普通 T800 保留关卡显式配置的长枪");
        var legacyRandomEnemy:Object = {是否为敌人:true, 长枪:"随机长枪"};
        ManagedLongGunService.prepareUnit(legacyRandomEnemy);
        check(legacyRandomEnemy.长枪 == null && legacyRandomEnemy.攻击模式 == "空手"
                && legacyRandomEnemy.enableShoot === false,
            "无解析器的旧随机长枪占位不会误启 Shoot，按未配置武器回落近战");

        var oldGameworld:Object = _root.gameworld;
        var oldControlTarget:String = _root.控制目标;
        var hero:Object = {_name:"managedTestHero"};
        var ally:Object = {_name:"managedTestAlly"};
        _root.gameworld = {managedTestHero:hero};
        _root.控制目标 = "managedTestHero";
        check(ShootInitCore.resolveMagazineStock(ally, "不存在也不得查询的弹匣") == 1,
            "非主角射击核心使用正哨兵且不依赖玩家弹匣库存");
        _root.gameworld = oldGameworld;
        _root.控制目标 = oldControlTarget;
    }

    private static function testT800DressupProjectionPreservesEnemyAuthority():Void {
        var oldControlTarget:String = _root.控制目标;
        var target:MovieClip = _root.createEmptyMovieClip(
            "__managedT800DressupProjection", _root.getNextHighestDepth());
        target.等级 = 60;
        target.是否为敌人 = false;
        target.hp满血值 = 6000; // 敌人模板已完成等级插值 × 难度2
        target.hp = 6000;
        target.空手攻击力_min = 10;
        target.空手攻击力_max = 120;
        target.基本空手攻击力 = 240; // 敌人模板已完成难度2
        target.基本防御力 = 800;
        target.基础命中率 = 10;
        target.基础韧性系数 = 1;
        target.基础躲闪率 = 100;
        target.体重 = 130;
        target.攻击模式 = "空手";
        target.area = {_height:1};
        target._yscale = 100;
        target.label = {非生物:true, 机械:true};
        target.魔法抗性 = {
            基础:50, 电:-100, 热:50, 冷:50, 波:0, 蚀:50, 毒:50, 冲:50,
            装甲:25, 机械:20, 凡俗:10
        };
        target.根据模式重新读取武器加成 = function(mode:String):Void {};

        var dataKeys:Array = [
            "头部装备数据", "上装装备数据", "手部装备数据", "下装装备数据",
            "脚部装备数据", "颈部装备数据", "长枪数据", "手枪数据",
            "手枪2数据", "刀数据", "手雷数据"
        ];
        for (var i:Number = 0; i < dataKeys.length; i++) {
            target[dataKeys[i]] = {data:{}};
        }

        _root.控制目标 = "__managedDifferentHero";
        DressupInitializer.updateProperties(target);
        check(target.hp基本满血值 == 6000 && target.hp满血值 == 18000
                && isFinite(Number(target.hp满血值))
                && target.mp基本满血值 == 0 && target.mp满血值 == 0
                && isFinite(Number(target.mp满血值)),
            "T800 缺失 hp/mp 基本满值时从敌人模板 live HP 安全建基，友军倍率不产生 NaN");
        check(target.空手攻击力 == 240
                && target.魔法抗性.基础 == 50 && target.魔法抗性.电 == -100
                && target.魔法抗性.波 == 0 && target.魔法抗性.装甲 == 25
                && target.魔法抗性.机械 == 20 && target.魔法抗性.凡俗 == 10
                && target.魔法抗性.人类 == undefined,
            "T800 装备投影保留敌人难度空攻及电/装甲/机械权威抗性，不注入人类模板标签");

        DressupInitializer.updateProperties(target);
        check(target.hp满血值 == 18000 && target.mp满血值 == 0
                && target.空手攻击力 == 240 && target.魔法抗性.电 == -100
                && target.魔法抗性.装甲 == 25 && target.魔法抗性.机械 == 20,
            "T800 重复换装从稳定 HP/MP/空攻/抗性基底重建，不重复倍率或累计装备投影");

        var human:MovieClip = _root.createEmptyMovieClip(
            "__managedHumanDressupProjection", _root.getNextHighestDepth());
        human.等级 = 60;
        human.是否为敌人 = true;
        human.hp基本满血值 = 1000;
        human.mp基本满血值 = 100;
        human.基本空手攻击力 = 20;
        human.体重 = 60;
        human.area = {_height:1};
        human._yscale = 100;
        human.label = {};
        human.魔法抗性 = {基础:999, 电:999}; // 首次已有表也不是非生物模板权威
        human.根据模式重新读取武器加成 = function(mode:String):Void {};
        for (i = 0; i < dataKeys.length; i++) human[dataKeys[i]] = {data:{}};
        DressupInitializer.updateProperties(human);
        human.等级 = 70;
        DressupInitializer.updateProperties(human);
        check(human.魔法抗性.基础 == 17 && human.魔法抗性.电 == 17
                && human.魔法抗性.人类 == 70
                && human.装备投影含模板魔法抗性 === false,
            "人形首次已有抗性表也不冻结为模板权威，升级与重复换装继续按当前等级投影");

        _root.控制目标 = oldControlTarget;
        human.removeMovieClip();
        target.removeMovieClip();
    }

    private static function testM134SuccessfulShotIntent():Void {
        var unit:Object = {
            攻击模式:"长枪",
            syncRefs:{},
            dispatcher:new EventDispatcher()
        };
        var gunAnim:Object = {_totalFrames:8, _currentFrame:1};
        gunAnim.gotoAndStop = function(frame:Number):Void { this._currentFrame = frame; };
        unit.长枪_引用 = {动画:gunAnim};
        var ref:Object = {自机:unit, 生命周期函数列表:[]};
        var init:Function = _root.装备生命周期函数.M134初始化;
        check(init != undefined,
            "聚焦测试已装载 M134 生命周期脚本");
        if (init == undefined) return;

        init(ref, {
            maxSpinCount:29,
            spinUpAmount:5,
            spinSpeedFactor:1,
            spinDownRate:0.33
        });

        unit.dispatcher.publish("processShot", unit, "长枪", null, {});
        check(ref.isFiring === true,
            "成功提交的主长枪 processShot 驱动 M134 枪管转动意图");
        BladeFireSpinController.tick(ref, unit.长枪_引用.动画);
        _root.装备生命周期函数.M134视觉更新(ref);
        check(gunAnim._currentFrame > 1,
            "M134 成功射击意图会推进当前规范长枪引用的可见动画帧");

        unit.dispatcher.publish("processShot", unit, "长枪副武器", null, {});
        check(ref.isFiring === false,
            "长枪副武器 processShot 不污染 M134 主枪转动意图");

        unit.dispatcher.publish("长枪射击");
        check(ref.isFiring === true,
            "M134 继续兼容旧时间轴长枪射击事件");

        check(ref.生命周期函数列表.length == 1
                && Number(unit.dispatcher["_subCount"]) == 3,
            "M134 初始化把两个射击订阅和 placement 订阅登记为同一卸载资源");
        init(ref, {
            maxSpinCount:29,
            spinUpAmount:5,
            spinSpeedFactor:1,
            spinDownRate:0.33
        });
        check(ref.生命周期函数列表.length == 1
                && Number(unit.dispatcher["_subCount"]) == 3,
            "M134 同一 lifecycle ref 防御性重入仍只保留三条当前订阅和一个卸载资源");
        var unload:Object = ref.生命周期函数列表[0];
        unload.动作(unload.额外参数);
        ref.isFiring = false;
        unit.dispatcher.publish("processShot", unit, "长枪", null, {});
        unit.dispatcher.publish("长枪射击");
        check(ref.isFiring === false && Number(unit.dispatcher["_subCount"]) == 0,
            "M134 生命周期卸载后旧 processShot/长枪射击/placement 回调全部移除");

        var replacement:Object = {自机:unit, 生命周期函数列表:[]};
        init(replacement, {
            maxSpinCount:29,
            spinUpAmount:5,
            spinSpeedFactor:1,
            spinDownRate:0.33
        });
        unit.dispatcher.publish("processShot", unit, "长枪", null, {});
        check(replacement.isFiring === true && ref.isFiring === false
                && Number(unit.dispatcher["_subCount"]) == 3,
            "M134 换装后只有当前 lifecycle ref 接收成功射击，不累积旧匿名订阅");
        replacement.生命周期函数列表[0].动作(
            replacement.生命周期函数列表[0].额外参数);
        unit.dispatcher.destroy();
    }

    private static function testUnitPreparationInstallsDressupLifecycleBridge():Void {
        var target:Object = {
            是否为敌人:false,
            宠物属性:{宠物库数组号:66}
        };
        ManagedLongGunService.prepareUnit(target);
        check(target.装载主动战技 === _root.主角函数.装载主动战技
                && target.装载副武器控制槽 === _root.主角函数.装载副武器控制槽
                && target.装载生命周期函数 === _root.主角函数.装载生命周期函数
                && target.完成生命周期函数装载 === _root.主角函数.完成生命周期函数装载,
            "T800 在普通敌人模板初始化前补齐成熟换装战技与生命周期入口");

        var customSkill:Function = function():Void {};
        var customSubweapon:Function = function():Void {};
        var customLifecycle:Function = function():Void {};
        var customFinalize:Function = function():Void {};
        var customized:Object = {
            是否为敌人:true,
            长枪:"战术版AK200",
            装载主动战技:customSkill,
            装载副武器控制槽:customSubweapon,
            装载生命周期函数:customLifecycle,
            完成生命周期函数装载:customFinalize
        };
        ManagedLongGunService.prepareUnit(customized);
        check(customized.装载主动战技 === customSkill
                && customized.装载副武器控制槽 === customSubweapon
                && customized.装载生命周期函数 === customLifecycle
                && customized.完成生命周期函数装载 === customFinalize,
            "T800 素材自带换装入口优先，桥接不会覆盖定制实现");
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
