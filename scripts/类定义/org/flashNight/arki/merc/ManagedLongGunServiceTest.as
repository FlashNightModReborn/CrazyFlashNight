import org.flashNight.aven.test.*;
import org.flashNight.arki.merc.ManagedLongGunService;
import org.flashNight.arki.merc.PetPanelService;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.component.Effect.EffectSystem;
import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.BladeFireSpinController;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer;
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
            testPetSpawnAndAtomicRebuild();
            testPetPanelSharedCoreContracts();
            testPetUpgradeUsesFullRebuild();
            testUpgradeThresholdUsesCommittedPetLevel();
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
        check(target.hp == 6000,
            "普通属性投影只改变最大值，不在换装中途免费回复 current HP");
        DressupInitializer.settleSpawnResources(target);
        var upgradeResourceProbe:Object = {
            hp:1, hp满血值:100, mp:1, mp满血值:10
        };
        DressupInitializer.settleSpawnResources(
            upgradeResourceProbe, {mode:"upgrade", currentMp:4});
        check(target.hp == 18000 && target.mp == 0 && target.mp满血值 == 0
                && upgradeResourceProbe.hp == 100 && upgradeResourceProbe.mp == 4,
            "出生在 Dressup 后同步最终资源；升级计划只回满 HP 并保留已有 MP");
        check(target.空手攻击力 == 240
                && target.魔法抗性.基础 == 50 && target.魔法抗性.电 == -100
                && target.魔法抗性.波 == 0 && target.魔法抗性.装甲 == 25
                && target.魔法抗性.机械 == 20 && target.魔法抗性.凡俗 == 10
                && target.魔法抗性.人类 == undefined,
            "T800 装备投影保留敌人难度空攻及电/装甲/机械权威抗性，不注入人类模板标签");

        target.hp = 9000;
        DressupInitializer.updateProperties(target);
        check(target.hp满血值 == 18000 && target.mp满血值 == 0
                && target.空手攻击力 == 240 && target.魔法抗性.电 == -100
                && target.魔法抗性.装甲 == 25 && target.魔法抗性.机械 == 20,
            "T800 重复换装从稳定 HP/MP/空攻/抗性基底重建，不重复倍率或累计装备投影");
        check(target.hp == 9000,
            "重复换装保留受伤后的绝对 current HP，不借幂等投影免费回血");

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

    /** 战宠根调用链：同步只验落位，资源在第 0 帧投影后结算；明确坏候选仍失败关闭。 */
    private static function testPetSpawnAndAtomicRebuild():Void {
        var oldPetInfo:Array = _root.宠物信息;
        var oldPetCatalog:Array = _root.宠物库;
        var oldPetUnits:Array = _root.宠物mc库;
        var oldDeployedIds:Array = _root.出战宠物id库;
        var oldGameworld:Object = _root.gameworld;
        var oldLoad:Function = _root.加载游戏世界人物;
        var oldSafeRemove:Function = _root.战宠UI函数.安全移除装备单位;
        var oldSave:Object = _root.存档系统;
        var oldCombatMap:Object = _root.当前为战斗地图;
        var oldPetInfoPanel:Object = _root.宠物信息界面;
        var oldPublish:Function = _root.发布消息;
        var oldTranslate:Function = _root.获得翻译;
        var oldMoney:Object = _root.金钱;

        var world:Object = {
            nextDepth:10,
            getNextHighestDepth:function():Number { return this.nextDepth++; }
        };
        var oldUnit:Object = {
            _name:"宠物0敌人-终结者T800", _parent:world, _x:120, _y:240,
            hp:7000, hp满血值:18000, mp:4, mp满血值:10,
            hasDressup:true,
            宠物属性:{宠物信息数组号:0}
        };
        var removed:Array = [];
        var loadMode:String = "success";
        var loaderSawOldAlive:Boolean = true;

        _root.宠物信息 = [[66, 100, 200, 0, 1, {}]];
        _root.宠物库 = [];
        _root.宠物库[66] = {Identifier:"敌人-终结者T800", Name:"终结者", Height:185};
        _root.宠物mc库 = [oldUnit];
        _root.出战宠物id库 = [0];
        _root.gameworld = world;
        _root.存档系统 = {dirtyMark:false};
        _root.当前为战斗地图 = false;
        _root.宠物信息界面 = {排列宠物图标:function():Void {}};
        _root.获得翻译 = function(value:String):String { return value; };
        _root.加载游戏世界人物 = function(identifier:String, instanceName:String,
                                            depth:Number, initObject:Object):Object {
            loaderSawOldAlive = loaderSawOldAlive
                && _root.宠物mc库[0] === oldUnit && removed.length == 0;
            if (loadMode == "null") return null;
            if (loadMode == "partial" && instanceName.indexOf("宠物1") == 0) return null;
            if (loadMode == "nullAttached") {
                world[instanceName] = {
                    _name:instanceName, _parent:world,
                    _x:initObject._x, _y:initObject._y
                };
                return null;
            }
            if (loadMode == "throw") {
                var partial:Object = {
                    _name:instanceName, _parent:world,
                    _x:initObject._x, _y:initObject._y
                };
                world[instanceName] = partial;
                throw "mock spawn failure";
            }
            var parentRef:Object = loadMode == "foreign" ? {} : world;
            var candidate:Object = {
                _name:instanceName, _parent:parentRef,
                _x:initObject._x, _y:initObject._y,
                hp:6000, hp满血值:18000, mp:1, mp满血值:10,
                兵种:identifier, 宠物属性:initObject.宠物属性,
                名字:initObject.名字,
                延迟常驻淬毒结算:initObject.延迟常驻淬毒结算,
                __petResourceSettlement:initObject.__petResourceSettlement,
                hasDressup:true,
                dispatcher:{publish:function():Void {}},
                aabbCollider:{}, unitAI:{}, shield:{}, version:1,
                __unitInitializedVersion:1,
                装载生命周期函数:function():Void {},
                完成生命周期函数装载:function():Void {},
                生命周期函数列表:[]
            };
            if (loadMode == "halfReady") {
                delete candidate.dispatcher;
                delete candidate.aabbCollider;
                delete candidate.生命周期函数列表;
            }
            if (loadMode == "lateHalfReady") {
                candidate.__unitInitializedVersion = 0;
            }
            if (loadMode == "lateHalfReadyNonDressup") {
                candidate.hasDressup = false;
                candidate.__unitInitializedVersion = 0;
                delete candidate.装载生命周期函数;
                delete candidate.完成生命周期函数装载;
                delete candidate.生命周期函数列表;
            }
            if (loadMode == "deferredNoMp") {
                // FP20 真实 attachMovie 返回栈只有 placement/initObject；第 0 帧尚未
                // 建立组件、资源、Dressup 与 StaticInitializer 完成闩锁。
                delete candidate.hp;
                delete candidate.hp满血值;
                delete candidate.mp;
                delete candidate.mp满血值;
                delete candidate.hasDressup;
                delete candidate.dispatcher;
                delete candidate.aabbCollider;
                delete candidate.unitAI;
                delete candidate.shield;
                delete candidate.version;
                delete candidate.__unitInitializedVersion;
                delete candidate.装载生命周期函数;
                delete candidate.完成生命周期函数装载;
                delete candidate.生命周期函数列表;
            }
            if (candidate.宠物属性 && candidate.宠物属性.常驻淬毒) {
                _root.战宠进阶函数.常驻淬毒.单位进阶执行.call(candidate);
            }
            if (parentRef === world) world[instanceName] = candidate;
            return candidate;
        };

        var laterUnloadReached:Boolean = false;
        var teardownThrowName:String = "__managedPetTeardownThrow";
        var teardownThrowUnit:MovieClip = _root.createEmptyMovieClip(
            teardownThrowName, _root.getNextHighestDepth());
        // 逆序先抛错，再证明更早注册的卸载动作与 bare 原生删除仍继续。
        teardownThrowUnit.生命周期函数列表 = [
            {动作:function():Void { laterUnloadReached = true; }},
            {动作:function():Void { throw "mock lifecycle unload failure"; }}
        ];
        check(oldSafeRemove(teardownThrowUnit) && laterUnloadReached
                && _root[teardownThrowName] == undefined,
            "Dressup 卸载动作抛错时仍继续其余逆序卸载与 bare 原生删除，不遗留旧宠");

        var nativeFallbackName:String = "__managedPetNativeRemoveFallback";
        var nativeFallbackUnit:MovieClip = _root.createEmptyMovieClip(
            nativeFallbackName, _root.getNextHighestDepth());
        nativeFallbackUnit.生命周期函数列表 = [];
        nativeFallbackUnit.removeMovieClip = function():Void {
            throw "mock overridden remove failure";
        };
        check(oldSafeRemove(nativeFallbackUnit)
                && _root[nativeFallbackName] == undefined,
            "时间轴覆写实例 removeMovieClip 也不能拦截 bare 原生 action 删除动态宠物");

        var softAliasParent:Object = {};
        var softAliasUnit:Object = {
            _name:"softAliasPet", _parent:softAliasParent,
            生命周期函数列表:[],
            removeMovieClip:function():Void { this._parent = undefined; }
        };
        softAliasParent.softAliasPet = softAliasUnit;
        check(oldSafeRemove(softAliasUnit)
                && softAliasUnit._parent === softAliasParent
                && softAliasParent.softAliasPet === softAliasUnit,
            "原生删除请求发出后同步引用仍可见也按命令提交，不再用显示树读回误报失败");

        var toggleAliasParent:Object = {};
        var toggleAliasUnit:Object = {
            _name:"toggleAliasPet", _parent:toggleAliasParent,
            宠物属性:{宠物信息数组号:0},
            生命周期函数列表:[],
            removeMovieClip:function():Void { this._parent = undefined; }
        };
        var toggleSiblingUnit:Object = {
            _name:"toggleSiblingPet", _parent:toggleAliasParent,
            宠物属性:{宠物信息数组号:7},
            生命周期函数列表:[]
        };
        toggleAliasParent.toggleAliasPet = toggleAliasUnit;
        toggleAliasParent.toggleSiblingPet = toggleSiblingUnit;
        _root.宠物信息[0][4] = 1;
        _root.宠物mc库 = [toggleAliasUnit, toggleSiblingUnit];
        _root.出战宠物id库 = [0, 7];
        _root.存档系统.dirtyMark = false;
        check(_root.战宠UI函数.尝试切换宠物出战状态(0, false)
                && _root.宠物信息[0][4] == 0
                && _root.宠物mc库.length == 1
                && _root.宠物mc库[0] === toggleSiblingUnit
                && _root.出战宠物id库.length == 1
                && _root.出战宠物id库[0] == 7
                && toggleAliasParent.toggleAliasPet === toggleAliasUnit
                && toggleAliasParent.toggleSiblingPet === toggleSiblingUnit
                && _root.存档系统.dirtyMark === true,
            "父级软别名残留时休息仍只移除目标 slot、保留兄弟投影并可靠标脏");
        _root.宠物信息[0][4] = 1;
        _root.宠物mc库 = [oldUnit];
        _root.出战宠物id库 = [0];
        _root.存档系统.dirtyMark = false;

        var removalFailureTarget:Object = null;
        var removalAttempts:Array = [];
        _root.战宠UI函数.安全移除装备单位 = function(unit:Object):Boolean {
            removalAttempts.push(unit);
            if (unit === removalFailureTarget) return false;
            removed.push(unit);
            unit.removed = true;
            // 真实 removeMovieClip 后 detached 引用不可再作为部署效果权威；测试也
            // 清掉字段，确保生产重建在移除前已经快照 marker/value。
            delete unit.已常驻淬毒;
            delete unit.淬毒;
            if (unit._name != undefined && world[unit._name] === unit) {
                delete world[unit._name];
            }
            return true;
        };

        try {
            var spawned:Object = _root.战宠UI函数.创建宠物单位(0, 10, 20, "__spawnProbe");
            check(spawned != null && spawned.hp == 18000 && spawned.mp == 10,
                "新战宠创建返回前以 Dressup 后最终最大值同步 current HP/MP");

            loadMode = "deferredNoMp";
            var rebuilt:Boolean = _root.战宠UI函数.重建宠物单位(0, false, null);
            var replacement:Object = _root.宠物mc库[0];
            check(rebuilt && loaderSawOldAlive && replacement !== oldUnit
                    && oldUnit.removed === true
                    && replacement.__petResourceSettlement
                    && replacement.__petResourceSettlement.mode == "preserve",
                "真实 deferred 换枪重建只验同步落位，保留资源计划后替换并清理旧单位");
            if(replacement && replacement.__petResourceSettlement){
                replacement.hp = 6000;
                replacement.hp满血值 = 18000;
                StaticInitializer.settlePendingPetResources(replacement);
            }
            check(replacement.hp == 7000 && replacement.mp == undefined
                    && replacement.mp满血值 == undefined,
                "普通换枪在 Dressup 后保留旧绝对 HP，且无 MP 战宠不制造伪 MP 字段");

            loadMode = "success";
            removalFailureTarget = replacement;
            var attemptsBeforeRemovalFailure:Number = removalAttempts.length;
            var removedBeforeRemovalFailure:Number = removed.length;
            check(!_root.战宠UI函数.重建宠物单位(0, false, null)
                    && _root.宠物mc库[0] === replacement
                    && _root.出战宠物id库[0] == 0
                    && removalAttempts.length == attemptsBeforeRemovalFailure + 2
                    && removed.length == removedBeforeRemovalFailure + 1,
                "旧单位移除失败时清理新候选并保持活动数组指向旧单位，不产生双实例");

            _root.宠物信息[0][4] = 1;
            attemptsBeforeRemovalFailure = removalAttempts.length;
            check(!_root.战宠UI函数.尝试切换宠物出战状态(0, false)
                    && _root.宠物信息[0][4] == 1
                    && _root.宠物mc库[0] === replacement
                    && _root.出战宠物id库[0] == 0
                    && removalAttempts.length == attemptsBeforeRemovalFailure + 1,
                "退场移除失败时回滚出战 flag 且不先删除活动数组条目");

            var cleanupSuccess:Object = {
                _name:"cleanupSuccess", _parent:world,
                removeMovieClip:function():Void {}
            };
            world.cleanupSuccess = cleanupSuccess;
            _root.宠物mc库 = [replacement, cleanupSuccess];
            _root.出战宠物id库 = [0, 7];
            check(_root.删除场景宠物() !== true
                    && _root.宠物mc库.length == 1
                    && _root.宠物mc库[0] === replacement
                    && _root.出战宠物id库.length == 1
                    && _root.出战宠物id库[0] == 0
                    && cleanupSuccess.removed === true,
                "批量清场只提交已受理删除条目，调用前失败的单位与 id 继续成对受跟踪");
            _root.宠物mc库 = [replacement];
            _root.出战宠物id库 = [0];
            removalFailureTarget = null;

            var effectClass:Object = EffectSystem;
            var oldEffect:Function = effectClass.Effect;
            effectClass.Effect = function():Void { throw "mock rebuild effect failure"; };
            var beforeEffectRebuild:Object = _root.宠物mc库[0];
            var effectRebuilt:Boolean = false;
            try {
                effectRebuilt = _root.战宠UI函数.重建宠物单位(
                    0, false, "升级动画2");
            } finally {
                effectClass.Effect = oldEffect;
            }
            check(effectRebuilt && _root.宠物mc库[0] !== beforeEffectRebuild
                    && beforeEffectRebuild.removed === true,
                "提交后的升级动画异常被隔离，完整替换仍返回成功并保持数组权威");

            loadMode = "null";
            var beforeFailure:Object = _root.宠物mc库[0];
            var removedBeforeFailure:Number = removed.length;
            check(!_root.战宠UI函数.重建宠物单位(0, false, null)
                    && _root.宠物mc库[0] === beforeFailure
                    && _root.出战宠物id库[0] == 0
                    && removed.length == removedBeforeFailure,
                "attachMovie 返回空值时 rebuilt=false，旧单位与出战数组保持原样");

            loadMode = "nullAttached";
            removedBeforeFailure = removed.length;
            check(!_root.战宠UI函数.重建宠物单位(0, false, null)
                    && _root.宠物mc库[0] === beforeFailure
                    && _root.出战宠物id库[0] == 0
                    && removed.length == removedBeforeFailure + 1
                    && removed[removed.length - 1] !== beforeFailure,
                "加载器挂入临时候选后返回空值时清理孤儿，旧单位与数组保持原样");

            loadMode = "throw";
            removedBeforeFailure = removed.length;
            check(!_root.战宠UI函数.重建宠物单位(0, false, null)
                    && _root.宠物mc库[0] === beforeFailure
                    && _root.出战宠物id库[0] == 0
                    && removed.length == removedBeforeFailure + 1
                    && removed[removed.length - 1] !== beforeFailure,
                "attachMovie 抛错时 rebuilt=false，只清理唯一临时名的半建候选并保留旧单位");

            loadMode = "foreign";
            removedBeforeFailure = removed.length;
            check(!_root.战宠UI函数.重建宠物单位(0, false, null)
                    && _root.宠物mc库[0] === beforeFailure
                    && removed.length == removedBeforeFailure + 1
                    && removed[removed.length - 1] !== beforeFailure,
                "半初始化候选父级不符时只清理候选，绝不销毁或替换旧单位");

            loadMode = "halfReady";
            removedBeforeFailure = removed.length;
            check(!_root.战宠UI函数.重建宠物单位(0, false, null)
                    && _root.宠物mc库[0] === beforeFailure
                    && _root.出战宠物id库[0] == 0
                    && removed.length == removedBeforeFailure + 1
                    && removed[removed.length - 1] !== beforeFailure,
                "同父级同宠物 id 但组件/Dressup 未就绪的候选仍失败关闭并保留旧单位");

            loadMode = "lateHalfReady";
            removedBeforeFailure = removed.length;
            check(!_root.战宠UI函数.重建宠物单位(0, false, null)
                    && _root.宠物mc库[0] === beforeFailure
                    && _root.出战宠物id库[0] == 0
                    && removed.length == removedBeforeFailure + 1,
                "早期组件与 Dressup 字段齐全但初始化完成版本过期时仍拒绝原子替换");

            // 首次出战与 rebuild 共用同一 readiness/cleanup，按钮态写失败必须回滚。
            _root.宠物mc库 = [];
            _root.出战宠物id库 = [];
            _root.宠物信息[0][4] = 0;
            var initialName:String = "宠物0敌人-终结者T800";

			loadMode = "deferredNoMp";
			var deferredDeployed:Boolean = _root.战宠UI函数.尝试切换宠物出战状态(
				0, true, 10, 20);
			var deferredPet:Object = _root.宠物mc库[0];
			var deferredPlacementAccepted:Boolean = deferredDeployed
				&& _root.宠物信息[0][4] == 1
				&& _root.宠物mc库.length == 1 && _root.出战宠物id库[0] == 0
				&& deferredPet && deferredPet.__petResourceSettlement
				&& deferredPet.__petResourceSettlement.mode == "spawn";
			if(deferredPet && deferredPet.__petResourceSettlement){
				deferredPet.hp = 6000;
				deferredPet.hp满血值 = 18000;
				StaticInitializer.settlePendingPetResources(deferredPet);
			}
			check(deferredPlacementAccepted && deferredPet.hp == 18000
					&& deferredPet.mp == undefined && deferredPet.mp满血值 == undefined
					&& deferredPet.__petResourceSettlement == undefined,
				"真实 attach 返回相位只验落位；后置结算会补最终 HP 且不自行制造缺失 MP 字段");
			_root.战宠UI函数.尝试切换宠物出战状态(0, false);

            loadMode = "nullAttached";
            removedBeforeFailure = removed.length;
            check(!_root.战宠UI函数.尝试切换宠物出战状态(0, true, 10, 20)
                    && _root.宠物信息[0][4] == 0
                    && _root.宠物mc库.length == 0 && _root.出战宠物id库.length == 0
                    && removed.length == removedBeforeFailure + 1 && world[initialName] == undefined,
                "首次出战加载器挂入后返回空值会清孤儿、回滚 flag 且不污染两数组");

            loadMode = "throw";
            removedBeforeFailure = removed.length;
            check(!_root.战宠UI函数.尝试切换宠物出战状态(0, true, 10, 20)
                    && _root.宠物信息[0][4] == 0
                    && _root.宠物mc库.length == 0 && _root.出战宠物id库.length == 0
                    && removed.length == removedBeforeFailure + 1 && world[initialName] == undefined,
                "首次出战加载器抛错会清半建单位、回滚 flag 且不污染两数组");

            loadMode = "lateHalfReadyNonDressup";
            removedBeforeFailure = removed.length;
            check(!_root.战宠UI函数.尝试切换宠物出战状态(0, true, 10, 20)
                    && _root.宠物信息[0][4] == 0
                    && _root.宠物mc库.length == 0 && _root.出战宠物id库.length == 0
                    && removed.length == removedBeforeFailure + 1 && world[initialName] == undefined,
                "非 Dressup 候选后半初始化未完成时首次出战同样失败关闭并回滚 flag");

            // 旧档 [5] 可能是 number；创建入口必须先正规化为对象并标脏，再向 loader
            // 传递稳定的 pet identity，不能依赖玩家先打开 Web/旧 Flash 面板做迁移。
            loadMode = "success";
            _root.宠物信息 = [[66, 100, 200, 0, 1, 1]];
            _root.存档系统.dirtyMark = false;
            var legacyAttrsSpawn:Object = _root.战宠UI函数.创建宠物单位(
                0, 10, 20, "__legacyAttrsProbe");
            check(legacyAttrsSpawn != null
                    && typeof _root.宠物信息[0][5] == "object"
                    && _root.宠物信息[0][5].宠物信息数组号 == 0
                    && _root.宠物信息[0][5].宠物库数组号 == 66
                    && _root.存档系统.dirtyMark === true,
                "数字型旧档宠物属性在首次创建前正规化、标脏并保留权威身份");
            _root.战宠UI函数.安全移除装备单位(legacyAttrsSpawn);

            // 批量加载不能把失败槽留成“flag=1 但没有 MovieClip”的永久假出战态。
            loadMode = "null";
            _root.宠物信息 = [[66, 100, 200, 0, 1, {}]];
            _root.宠物mc库 = [];
            _root.出战宠物id库 = [];
            _root.存档系统.dirtyMark = false;
            check(_root.加载宠物(10, 20) === false
                    && _root.宠物信息[0][4] == 0
                    && _root.宠物mc库.length == 0 && _root.出战宠物id库.length == 0
                    && _root.存档系统.dirtyMark === true,
                "存档加载单只部署失败时回到可恢复休息态并报告 aggregate false");

            _root.宠物信息 = [[66, 100, 0, 0, 1, {}]];
            _root.存档系统.dirtyMark = false;
            _root.发布消息 = function():Void { throw "mock stamina notice failure"; };
            check(_root.加载宠物(10, 20) === false
                    && _root.宠物信息[0][4] == 0
                    && _root.存档系统.dirtyMark === true,
                "零体力旧档先持久化休息态，提示异常不覆盖权威闭环");
            _root.发布消息 = oldPublish;

            loadMode = "partial";
            _root.宠物信息 = [
                [66, 100, 200, 0, 1, {}],
                [66, 100, 200, 0, 1, {}]
            ];
            _root.宠物mc库 = [];
            _root.出战宠物id库 = [];
            _root.存档系统.dirtyMark = false;
            check(_root.加载宠物(10, 20) === false
                    && _root.宠物信息[0][4] == 1 && _root.宠物信息[1][4] == 0
                    && _root.宠物mc库.length == 1 && _root.出战宠物id库.length == 1
                    && _root.出战宠物id库[0] == 0
                    && _root.存档系统.dirtyMark === true,
                "批量加载保留成功宠物，只回滚失败槽并准确返回 partial failure");
            _root.删除场景宠物();

            loadMode = "success";
            _root.宠物信息 = [];
            _root.宠物信息[1] = [66, 100, 200, 0, 1, {}];
            _root.宠物mc库 = [];
            _root.出战宠物id库 = [];
            check(_root.加载宠物(10, 20) === true
                    && _root.宠物mc库.length == 1
                    && _root.出战宠物id库[0] == 1,
                "稀疏旧档空槽会被跳过，后续有效出战槽仍可完成加载");
            _root.删除场景宠物();

            _root.宠物信息 = [[66, 100, 200, 0, 1, {}]];
            _root.宠物mc库 = [{宠物属性:{宠物信息数组号:0}}];
            _root.出战宠物id库 = [0];
            _root.存档系统.dirtyMark = false;
            _root.宠物减体力();
            check(_root.宠物信息[0][2] == 198
                    && _root.存档系统.dirtyMark === true,
                "战斗地图首次实际扣除宠物体力前标脏，单独换场也能持久化消耗");

            // 常驻淬毒先缓冲金币回执，再写单位毒性/marker；marker setter 故障
            // 必须 exact 恢复并清 frame，下一只单位仍可独立完成一次收费。
            org.flashNight.arki.item.PlayerAssetTransaction.resetForTests();
            var poisonReceipts:Array = [];
            org.flashNight.arki.item.PlayerAssetTransaction.setTestSink(
                function(receipt:Object):Void { poisonReceipts.push(receipt); });
            _root.当前为战斗地图 = true;
            _root.金钱 = 1000;
            _root.存档系统 = {dirtyMark:false};
            var poisonMarkerSetterCalls:Number = 0;
            var poisonMarkerValue:Boolean = false;
            var poisonFaultUnit:Object = {
                延迟常驻淬毒结算:false,
                宠物属性:{常驻淬毒:{来源:"玩家", 启用:true}},
                名字:"事务故障宠"
            };
            poisonFaultUnit.addProperty("已常驻淬毒",
                function():Boolean { return poisonMarkerValue; },
                function(value:Boolean):Void {
                    poisonMarkerSetterCalls++;
                    if (value === true) throw "persistent_poison_marker_fault";
                    poisonMarkerValue = value;
                });
            var poisonFault = null;
            try {
                _root.战宠进阶函数.常驻淬毒.单位进阶执行.call(poisonFaultUnit);
            } catch (poisonError) {
                poisonFault = poisonError;
            }
            check(poisonFault == "persistent_poison_marker_fault"
                    && poisonMarkerSetterCalls == 2
                    && _root.金钱 == 1000
                    && poisonFaultUnit.淬毒 == undefined
                    && poisonFaultUnit.已常驻淬毒 === false
                    && _root.存档系统.dirtyMark === false
                    && poisonReceipts.length == 0
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null,
                "常驻淬毒 record 后 marker fault exact 恢复金币/毒性/marker/dirty 并清 frame");
            var poisonUnrestorableUnit:Object = {
                延迟常驻淬毒结算:false,
                宠物属性:{常驻淬毒:{来源:"玩家", 启用:true}},
                名字:"恢复失败宠"
            };
            var poisonUnrestorableMarker:Boolean = false;
            poisonUnrestorableUnit.addProperty("已常驻淬毒",
                function():Boolean { return poisonUnrestorableMarker; },
                function(value:Boolean):Void {
                    if (value === true) poisonUnrestorableMarker = true;
                    throw "persistent_poison_unrestorable_marker";
                });
            var poisonUnrestorableFault = null;
            try {
                _root.战宠进阶函数.常驻淬毒.单位进阶执行.call(
                    poisonUnrestorableUnit);
            } catch (poisonUnrestorableError) {
                poisonUnrestorableFault = poisonUnrestorableError;
            }
            check(poisonUnrestorableFault == "persistent_poison_unrestorable_marker"
                    && _root.金钱 == 500
                    && poisonUnrestorableUnit.已常驻淬毒 === true
                    && _root.存档系统.dirtyMark === true
                    && poisonReceipts.length == 1
                    && poisonReceipts[0].effects.length == 1
                    && poisonReceipts[0].effects[0].direction == "loss"
                    && poisonReceipts[0].effects[0].name == "金钱"
                    && poisonReceipts[0].effects[0].count == 500
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null,
                "常驻淬毒 unit restore 失败时保留真实扣款与匹配 loss receipt，不伪造回滚");
            var poisonRecoveredUnit:Object = {
                延迟常驻淬毒结算:false,
                宠物属性:{常驻淬毒:{来源:"玩家", 启用:true}},
                名字:"事务恢复宠"
            };
            _root.战宠进阶函数.常驻淬毒.单位进阶执行.call(poisonRecoveredUnit);
            check(_root.金钱 == 0 && poisonRecoveredUnit.淬毒 == 70
                    && poisonRecoveredUnit.已常驻淬毒 === true
                    && _root.存档系统.dirtyMark === true
                    && poisonReceipts.length == 2
                    && poisonReceipts[1].effects.length == 1
                    && poisonReceipts[1].effects[0].direction == "loss"
                    && poisonReceipts[1].effects[0].name == "金钱"
                    && poisonReceipts[1].effects[0].count == 500
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null,
                "常驻淬毒异常后的下一事务只收费一次并发布精确 loss receipt");
            org.flashNight.arki.item.PlayerAssetTransaction.resetForTests();

            // 常驻淬毒是每图一次的部署副作用：候选未采用前绝不能扣钱；同图重建
            // 继承已付费 marker 与剩余淬毒，避免免费开关/换枪反复收费。
            _root.当前为战斗地图 = true;
            _root.金钱 = 1000;
            _root.宠物信息 = [[66, 100, 200, 0, 0, {
                常驻淬毒:{来源:"玩家", 启用:true}
            }]];
            _root.宠物mc库 = [];
            _root.出战宠物id库 = [];
            loadMode = "halfReady";
            check(!_root.战宠UI函数.尝试切换宠物出战状态(0, true, 10, 20)
                    && _root.金钱 == 1000 && _root.宠物信息[0][4] == 0,
                "半初始化常驻淬毒候选在正式采用前零扣费并回滚出战态");

            loadMode = "success";
            var poisonDeployed:Boolean = _root.战宠UI函数.尝试切换宠物出战状态(
                0, true, 10, 20);
            var paidPoisonUnit:Object = _root.宠物mc库[0];
            if(paidPoisonUnit){
                // 真实 load flush 会在采用之后再次跑宠物属性钩子；marker 必须阻止二扣。
                _root.战宠进阶函数.常驻淬毒.单位进阶执行.call(paidPoisonUnit);
            }
            check(poisonDeployed && _root.金钱 == 500
                    && paidPoisonUnit.已常驻淬毒 === true && paidPoisonUnit.淬毒 == 70,
                "首次正式采用只结算一次常驻淬毒；第 0 帧重入读取 marker 不重复扣费");
            paidPoisonUnit.淬毒 = 43;
            check(_root.战宠UI函数.重建宠物单位(0, false, null)
                    && _root.金钱 == 500 && _root.宠物mc库[0] !== paidPoisonUnit
                    && _root.宠物mc库[0].已常驻淬毒 === true
                    && _root.宠物mc库[0].淬毒 == 43,
                "同图成功重建继承已付费 marker 与剩余淬毒，不重复扣费");

            var unpaidOldUnit:Object = _root.宠物mc库[0];
            unpaidOldUnit.已常驻淬毒 = false;
            unpaidOldUnit.淬毒 = 0;
            removalFailureTarget = unpaidOldUnit;
            check(!_root.战宠UI函数.重建宠物单位(0, false, null)
                    && _root.金钱 == 500 && _root.宠物mc库[0] === unpaidOldUnit,
                "旧单位移除失败时未采用候选零扣常驻淬毒费用并保持原单位");
            removalFailureTarget = null;
            _root.删除场景宠物();

        } finally {
            _root.宠物信息 = oldPetInfo;
            _root.宠物库 = oldPetCatalog;
            _root.宠物mc库 = oldPetUnits;
            _root.出战宠物id库 = oldDeployedIds;
            _root.gameworld = oldGameworld;
            _root.加载游戏世界人物 = oldLoad;
            _root.战宠UI函数.安全移除装备单位 = oldSafeRemove;
            _root.存档系统 = oldSave;
            _root.当前为战斗地图 = oldCombatMap;
            _root.宠物信息界面 = oldPetInfoPanel;
            _root.发布消息 = oldPublish;
            _root.获得翻译 = oldTranslate;
            _root.金钱 = oldMoney;
        }
    }

    /** 在线升级统一走完整两阶段重建，不能再按宠物类型维护两套刷新逻辑。 */
    private static function testPetUpgradeUsesFullRebuild():Void {
        var oldPetInfo:Array = _root.宠物信息;
        var oldPetUnits:Array = _root.宠物mc库;
        var oldDeployedIds:Array = _root.出战宠物id库;
        var oldRebuild:Function = _root.战宠UI函数.重建宠物单位;
        var called:Number = 0;
        var observedId:Number = -1;
        var observedUpgrade:Boolean = false;
        var observedEffect:String = "";

        _root.宠物信息 = [];
        _root.宠物信息[2] = [66, 100, 200, 0, 1, {}];
        _root.出战宠物id库 = [2];
        _root.宠物mc库 = [{
            _x:100, _y:200, hasDressup:true,
            宠物属性:{宠物信息数组号:2}
        }];
        _root.战宠UI函数.重建宠物单位 = function(id:Number, upgrade:Boolean,
                                                        effectName:String):Boolean {
            called++;
            observedId = id;
            observedUpgrade = upgrade;
            observedEffect = effectName;
            return true;
        };

        try {
            _root.宠物升级加载(0);
            check(called == 1 && observedId == 2 && observedUpgrade === true
                    && observedEffect == "升级动画2",
                "升级包装按 mc 库索引解析稀疏存档槽，并统一走满血两阶段重建");
        } finally {
            _root.宠物信息 = oldPetInfo;
            _root.宠物mc库 = oldPetUnits;
            _root.出战宠物id库 = oldDeployedIds;
            _root.战宠UI函数.重建宠物单位 = oldRebuild;
        }
    }

    /** 两阶段替换后旧 MovieClip 已卸载；下一档经验阈值必须读取存档权威等级。 */
    private static function testUpgradeThresholdUsesCommittedPetLevel():Void {
        var oldPetInfo:Array = _root.宠物信息;
        var oldPetUnits:Array = _root.宠物mc库;
        var oldDeployedIds:Array = _root.出战宠物id库;
        var oldPetCatalog:Array = _root.宠物库;
        var oldUpgradeLoad:Function = _root.宠物升级加载;
        var oldRequirement:Function = _root.战宠UI函数.计算战宠升级所需经验;
        var oldPublish:Function = _root.发布消息;
        var oldDifficulty:Number = _root.难度等级;
        var oldLevel:Number = _root.等级;
        var oldLevelLimit:Number = _root.等级限制;
        var oldSave:Object = _root.存档系统;
        var oldRefreshDeferred:Object = _root.战宠UI函数._宠物刷新待处理;
        var observedIdentifier:String = "";
        var observedLevel:Number = -1;

        _root.宠物信息 = [[66, 99, 200, 0, 1, {
            宠物升级经验:0,
            宠物升级所需经验:0.5
        }]];
        _root.出战宠物id库 = [0];
        _root.宠物mc库 = [{hp:1, 兵种:"敌人-终结者T800", 等级:99}];
        _root.宠物库 = [];
        _root.宠物库[66] = {Name:"终结者", Identifier:"敌人-终结者T800"};
        _root.难度等级 = 1;
        _root.等级 = 100;
        _root.等级限制 = 100;
        _root.存档系统 = {dirtyMark:false};
        _root.战宠UI函数._宠物刷新待处理 = {};
        _root.发布消息 = function():Void {};
        _root.宠物升级加载 = function(index:Number):Boolean {
            // 模拟两阶段重建：旧局部对象不会被原地更新。
            _root.宠物mc库[index] = {hp:1, 兵种:"敌人-终结者T800", 等级:100};
            return false;
        };
        _root.战宠UI函数.计算战宠升级所需经验 = function(identifier:String,
                                                                level:Number):Number {
            observedIdentifier = identifier;
            observedLevel = level;
            return 1000;
        };

        try {
            _root.经验值计算(1, 1, 1, 2);
            check(_root.宠物信息[0][1] == 100 && observedLevel == 100
                    && observedIdentifier == "敌人-终结者T800",
                "两阶段替换后下一档经验阈值只读已提交存档/宠物库，不读取卸载旧单位");
            check(_root.存档系统 != undefined && _root.存档系统.dirtyMark === true,
                "玩家已达等级上限时宠物经验/升级仍独立标脏并进入存档队列");
            check(_root.宠物信息[0][5].宠物升级所需经验 == 1000
                    && _root.战宠UI函数._宠物刷新待处理[0].reason == "auto_level_up"
                    && _root.战宠UI函数._宠物刷新待处理[0].level == 100,
                "自动升级先提交等级/下一阈值，重建失败不回滚事实并显式标记 refresh deferred");

            _root.宠物信息 = [[66, 1, 200, 0, 1, {宠物升级经验:0}]];
            _root.宠物mc库 = [{hp:1, 兵种:"敌人-终结者T800", 等级:1}];
            _root.战宠UI函数.计算战宠升级所需经验 = function(identifier:String,
                                                                    level:Number):Number {
                return level == 1 ? 0.5 : 1000;
            };
            _root.经验值计算(1, 1, 1, 2);
            check(_root.宠物信息[0][1] == 2
                    && _root.宠物信息[0][5].宠物升级所需经验 == 1000,
                "旧档缺失升级阈值时先建立有限阈值，本次战斗经验即可正常触发升级");

            _root.宠物信息 = [
                [66, 1, 200, 0, 1, {宠物升级经验:0, 宠物升级所需经验:0.5}],
                [66, 1, 200, 0, 1, {宠物升级经验:0, 宠物升级所需经验:0.5}]
            ];
            _root.出战宠物id库 = [0, 1];
            _root.宠物mc库 = [
                {hp:1, 兵种:"敌人-终结者T800", 等级:1},
                {hp:1, 兵种:"敌人-终结者T800", 等级:1}
            ];
            _root.战宠UI函数._宠物刷新待处理 = {};
            _root.宠物升级加载 = function(index:Number):Boolean {
                if (index == 0) throw "mock auto-level rebuild failure";
                return false;
            };
            _root.经验值计算(1, 1, 1, 2);
            check(_root.宠物信息[0][1] == 2 && _root.宠物信息[1][1] == 2
                    && _root.战宠UI函数._宠物刷新待处理[0].reason == "auto_level_up"
                    && _root.战宠UI函数._宠物刷新待处理[1].reason == "auto_level_up",
                "自动升级重建抛错只记 refresh deferred，不中断后续宠物经验结算");
        } finally {
            _root.宠物信息 = oldPetInfo;
            _root.宠物mc库 = oldPetUnits;
            _root.出战宠物id库 = oldDeployedIds;
            _root.宠物库 = oldPetCatalog;
            _root.宠物升级加载 = oldUpgradeLoad;
            _root.战宠UI函数.计算战宠升级所需经验 = oldRequirement;
            _root.发布消息 = oldPublish;
            _root.难度等级 = oldDifficulty;
            _root.等级 = oldLevel;
            _root.等级限制 = oldLevelLimit;
            _root.存档系统 = oldSave;
            _root.战宠UI函数._宠物刷新待处理 = oldRefreshDeferred;
        }
    }

    /** Web/旧 UI 共用的升级、重命名与解散核心必须保持同一写入/重建边界。 */
    private static function testPetPanelSharedCoreContracts():Void {
        var oldPetInfo:Array = _root.宠物信息;
        var oldPetCatalog:Array = _root.宠物库;
        var oldPetUnits:Array = _root.宠物mc库;
        var oldDeployedIds:Array = _root.出战宠物id库;
        var oldLevelLimit:Object = _root.等级限制;
        var oldLevel:Object = _root.等级;
        var oldMaxDeploy:Object = _root.最大宠物出战数;
        var oldMoney:Object = _root.金钱;
        var oldSave:Object = _root.存档系统;
        var oldCombatMap:Object = _root.当前为战斗地图;
        var oldChallengeMode:Function = _root.isChallengeMode;
        var oldEasyMode:Function = _root.isEasyMode;
        var oldSingleSubmit:Function = _root.singleSubmit;
        var oldSingleAcquire:Function = _root.singleAcquire;
        var oldRequirement:Function = _root.战宠UI函数.计算战宠升级所需经验;
        var oldRebuild:Function = _root.战宠UI函数.重建宠物单位;
        var oldRemoveSceneSlot:Function = _root.战宠UI函数.移除场景宠物槽;
        var oldSafeRemove:Function = _root.战宠UI函数.安全移除装备单位;
        var oldSetPetDeploy:Function = _root.战宠UI函数.设置宠物出战;
        var oldRefreshDeferred:Object = _root.战宠UI函数._宠物刷新待处理;
        var oldDeleteScene:Function = _root.删除场景宠物;
        var oldLoadPets:Function = _root.加载宠物;
        var oldPreflight:Function = ManagedLongGunService.preflightWithdrawal;
        var oldWithdraw:Function = ManagedLongGunService.withdraw;
        var oldSingleRequire:Function = ItemUtil.singleRequire;
        var oldInventory:Object = _root.物品栏;
        var oldCollections:Object = _root.收集品栏;
        var oldMaterialDict:Object = ItemUtil.materialDict;
        var oldServer:Object = _root.server;
        var oldPetInfoPanel:Object = _root.宠物信息界面;
        var oldGameworld:Object = _root.gameworld;
        var oldControlTarget:Object = _root.控制目标;
        var oldPendingHire:Object = _root._pendingHire;

        _root.宠物库 = [];
        _root.宠物库[66] = {
            Identifier:"敌人-终结者T800", Name:"终结者", Height:185
        };
        _root.等级限制 = 100;
        _root.当前为战斗地图 = false;
        _root.战宠UI函数._宠物刷新待处理 = {};
        _root.战宠UI函数.计算战宠升级所需经验 = function(identifier:String,
                                                                level:Number):Number {
            return level * 1000;
        };

        try {
            var advanceResponse:String = "";
            var hairRebuildSawCommit:Boolean = false;
            _root.server = {sendSocketMessage:function(payload:String):Boolean {
                advanceResponse = payload;
                return true;
            }};
            _root.宠物信息界面 = undefined;
            _root.宠物库[66].Promotion = {Item:"切换发型"};
            _root.宠物信息 = [[66, 5, 200, 0, 1, {发色:"橙"}]];
            _root.存档系统 = {dirtyMark:false};
            _root.战宠UI函数.重建宠物单位 = function(id:Number,
                                                            upgrade:Boolean):Boolean {
                hairRebuildSawCommit = id == 0 && upgrade === false
                    && _root.宠物信息[0][5].发色 == "白"
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null;
                return true;
            };
            PetPanelService.handleAdvance({callId:"hair_tx", slotIndex:0,
                scheme:"切换发型"});
            check(_root.宠物信息[0][5].发色 == "白"
                    && _root.存档系统.dirtyMark === true
                    && hairRebuildSawCommit
                    && advanceResponse.indexOf('"success":true') >= 0
                    && advanceResponse.indexOf('"rebuilt":true') >= 0
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null,
                "发色进阶只写 attrs，旧 Flash UI 缺失不抛且 commit 后统一 rebuild(false)");

            _root.宠物信息 = [[66, 5, 50, 0, 0, {}]];
            _root.金钱 = 999;
            _root.存档系统 = {dirtyMark:false};
            var staminaInsufficient:Object = PetPanelService.restoreStaminaSlot(0);
            check(staminaInsufficient.success !== true
                    && staminaInsufficient.error == "insufficient_gold"
                    && _root.金钱 == 999 && _root.宠物信息[0][2] == 50
                    && _root.存档系统.dirtyMark === false,
                "旧 UI 体力恢复金币不足时共享权威保持余额/体力/dirty 零写");

            _root.金钱 = 1500;
            var staminaRestored:Object = PetPanelService.restoreStaminaSlot(0);
            check(staminaRestored.success === true && staminaRestored.cost == 1000
                    && staminaRestored.gold == 500 && _root.金钱 == 500
                    && _root.宠物信息[0][2] == 200
                    && _root.存档系统.dirtyMark === true
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null,
                "Web/旧 UI 体力恢复共用 dirty-first 显式金币事务与满体力写");

            var insufficientAttrs:Object = {
                宠物升级经验:17, 宠物升级所需经验:10000, marker:"unchanged"
            };
            _root.宠物信息 = [[66, 5, 200, 0, 1, insufficientAttrs]];
            _root.存档系统 = {dirtyMark:false};
            var insufficientRebuilds:Number = 0;
            _root.singleSubmit = function():Boolean { return false; };
            _root.战宠UI函数.重建宠物单位 = function():Boolean {
                insufficientRebuilds++;
                return true;
            };
            var insufficient:Object = PetPanelService.levelUpSlot(0);
            check(insufficient.success !== true && insufficient.error == "insufficient_stones"
                    && _root.宠物信息[0][1] == 5
                    && _root.宠物信息[0][5] === insufficientAttrs
                    && insufficientAttrs.宠物升级所需经验 == 10000
                    && insufficientAttrs.marker == "unchanged"
                    && insufficientRebuilds == 0
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null,
                "升级灵石不足时不正规化/改写等级与阈值，也不触发部署态重建或遗留事务");

            var thresholdAttrs:Object = {
                宠物升级经验:23, 宠物升级所需经验:5000, marker:"threshold_fault"
            };
            _root.宠物信息 = [[66, 5, 200, 0, 0, thresholdAttrs]];
            _root.存档系统 = {dirtyMark:false};
            var thresholdSubmitCalls:Number = 0;
            _root.singleSubmit = function():Boolean {
                thresholdSubmitCalls++;
                return true;
            };
            _root.战宠UI函数.计算战宠升级所需经验 = function(identifier:String,
                                                                    level:Number):Number {
                throw "mock threshold failure";
                return 0; // AS2 编译器要求显式返回；运行时永远不可达。
            };
            var thresholdFault = null;
            try {
                PetPanelService.levelUpSlot(0);
            } catch (thresholdError) {
                thresholdFault = thresholdError;
            }
            var thresholdFaultWasZeroWrite:Boolean = thresholdFault == "mock threshold failure"
                && thresholdSubmitCalls == 0
                && _root.宠物信息[0][1] == 5
                && _root.宠物信息[0][5] === thresholdAttrs
                && thresholdAttrs.宠物升级所需经验 == 5000
                && thresholdAttrs.marker == "threshold_fault"
                && _root.存档系统.dirtyMark === false
                && org.flashNight.arki.item.PlayerAssetTransaction.current() == null;
            _root.战宠UI函数.计算战宠升级所需经验 = function(identifier:String,
                                                                    level:Number):Number {
                return level * 1000;
            };
            var thresholdRecovered:Object = PetPanelService.levelUpSlot(0);
            check(thresholdFaultWasZeroWrite && thresholdRecovered.success === true
                    && thresholdSubmitCalls == 1
                    && _root.宠物信息[0][1] == 6
                    && thresholdAttrs.宠物升级所需经验 == 6000
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null,
                "升级阈值回调异常在扣石/等级/dirty 前失败且不悬栈，下一事务可独立提交");

            var dirtySetterCalls:Number = 0;
            var submitAfterDirtyFailure:Number = 0;
            var throwingSave:Object = {};
            throwingSave.addProperty("dirtyMark",
                function():Boolean { return false; },
                function(value:Boolean):Void {
                    dirtySetterCalls++;
                    throw "mock pet save unavailable";
                });
            var dirtyAttrs:Object = {宠物升级所需经验:5000};
            _root.宠物信息 = [[66, 5, 200, 0, 0, dirtyAttrs]];
            _root.存档系统 = throwingSave;
            _root.singleSubmit = function():Boolean {
                submitAfterDirtyFailure++;
                return true;
            };
            var dirtyFailed:Boolean = false;
            try {
                PetPanelService.levelUpSlot(0);
            } catch (dirtyError) {
                dirtyFailed = true;
            }
            check(dirtyFailed && dirtySetterCalls == 1 && submitAfterDirtyFailure == 0
                    && _root.宠物信息[0][1] == 5
                    && _root.宠物信息[0][5] === dirtyAttrs
                    && dirtyAttrs.宠物升级所需经验 == 5000
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null,
                "升级 dirtyMark 不可用时在扣灵石/等级写前失败关闭并先结清显式事务 frame");

            var materialFixture:Object = {};
            materialFixture["战宠灵石"] = true;
            ItemUtil.materialDict = materialFixture;
            ItemUtil.itemDataDict["战宠灵石"] = {
                name:"战宠灵石", displayname:"战宠灵石", icon:"战宠灵石",
                type:"收集品", use:"材料", price:1, data:{level:1}
            };
            var stoneCollection:DictCollection = new DictCollection(null);
            stoneCollection.add("战宠灵石", 20);
            var listenerBag:ArrayInventory = new ArrayInventory(null, 2);
            var listenerDrugs:ArrayInventory = new ArrayInventory(null, 2);
            _root.物品栏 = {
                装备栏:{getItem:function():Object { return null; }},
                背包:listenerBag, 药剂栏:listenerDrugs
            };
            _root.收集品栏 = {
                材料:stoneCollection, 情报:new DictCollection(null)
            };
            _root.宠物信息 = [[66, 5, 200, 0, 0, {
                宠物升级所需经验:5000
            }]];
            _root.存档系统 = {dirtyMark:false};
            _root.singleSubmit = function(name:String, count:Number,
                                          context:Object):Boolean {
                return ItemUtil.singleSubmit(name, count, context);
            };
            var listenerHolder:MovieClip = _root.createEmptyMovieClip(
                "__petLevelStoneListenerFault", _root.getNextHighestDepth());
            var stoneDispatcher:LifecycleEventDispatcher =
                new LifecycleEventDispatcher(listenerHolder);
            stoneCollection.setDispatcher(stoneDispatcher);
            stoneDispatcher.subscribe("ItemValueChanged", function():Void {
                throw "pet_level_stone_listener_failed";
            });
            org.flashNight.arki.item.PlayerAssetTransaction.resetForTests();
            var levelReceipts:Array = [];
            org.flashNight.arki.item.PlayerAssetTransaction.setTestSink(
                function(receipt:Object):Void { levelReceipts.push(receipt); });
            var stoneFault = null;
            try {
                PetPanelService.levelUpSlot(0);
            } catch (stoneError) {
                stoneFault = stoneError;
            }
            check(stoneFault == "pet_level_stone_listener_failed"
                    && stoneCollection.getValue("战宠灵石") == 20
                    && _root.宠物信息[0][1] == 5
                    && _root.宠物信息[0][5].宠物升级所需经验 == 5000
                    && _root.存档系统.dirtyMark === false
                    && levelReceipts.length == 0
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null
                    && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
                "升级扣石 listener fault exact 恢复灵石/等级/dirty 并丢弃 partial receipt");
            stoneCollection.setDispatcher(null);
            var levelRecovered:Object = PetPanelService.levelUpSlot(0);
            check(levelRecovered.success === true
                    && stoneCollection.getValue("战宠灵石") == 10
                    && _root.宠物信息[0][1] == 6
                    && levelReceipts.length == 1
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null,
                "升级扣石 listener fault 后下一事务可独立提交且不重复扣除");
            listenerHolder.removeMovieClip();
            org.flashNight.arki.item.PlayerAssetTransaction.resetForTests();

            var deleteStoneCollection:DictCollection = new DictCollection(null);
            _root.收集品栏.材料 = deleteStoneCollection;
            _root.宠物信息 = [[66, 25, 200, 0, 0, {
                宠物升级所需经验:10000
            }]];
            _root.存档系统 = {dirtyMark:false};
            _root.singleAcquire = function(name:String, count:Number,
                                           context:Object):Boolean {
                return ItemUtil.singleAcquire(name, count, context);
            };
            ManagedLongGunService.preflightWithdrawal = function():Object {
                return {success:true, required:false};
            };
            _root.删除场景宠物 = function():Boolean { return true; };
            var deleteListenerHolder:MovieClip = _root.createEmptyMovieClip(
                "__petDeleteStoneListenerFault", _root.getNextHighestDepth());
            var deleteStoneDispatcher:LifecycleEventDispatcher =
                new LifecycleEventDispatcher(deleteListenerHolder);
            deleteStoneCollection.setDispatcher(deleteStoneDispatcher);
            deleteStoneDispatcher.subscribe("ItemAdded", function():Void {
                throw "pet_delete_refund_listener_failed";
            });
            var deleteReceipts:Array = [];
            org.flashNight.arki.item.PlayerAssetTransaction.setTestSink(
                function(receipt:Object):Void { deleteReceipts.push(receipt); });
            var deleteFault = null;
            try {
                PetPanelService.deletePetSlot(0);
            } catch (deleteError) {
                deleteFault = deleteError;
            }
            check(deleteFault == "pet_delete_refund_listener_failed"
                    && deleteStoneCollection.getValue("战宠灵石") == 0
                    && _root.宠物信息[0][0] == 66
                    && _root.宠物信息[0][1] == 25
                    && _root.宠物信息[0][5].宠物升级所需经验 == 10000
                    && _root.存档系统.dirtyMark === false
                    && deleteReceipts.length == 0
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null
                    && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
                "解散返还 listener fault exact 恢复灵石/宠物/dirty 并丢弃 partial receipt");
            deleteStoneCollection.setDispatcher(null);
            var deleteRecovered:Object = PetPanelService.deletePetSlot(0);
            check(deleteRecovered.success === true && deleteRecovered.stoneRefund == 4
                    && deleteStoneCollection.getValue("战宠灵石") == 4
                    && _root.宠物信息[0].length == 0
                    && deleteReceipts.length == 1
                    && deleteReceipts[0].effects.length == 1
                    && deleteReceipts[0].effects[0].direction == "gain"
                    && deleteReceipts[0].effects[0].name == "战宠灵石"
                    && deleteReceipts[0].effects[0].count == 4
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null,
                "解散返还 listener fault 后下一事务只返还一次并清空宠物槽");
            deleteListenerHolder.removeMovieClip();
            org.flashNight.arki.item.PlayerAssetTransaction.resetForTests();

            _root.宠物信息 = [[66, 5, 200, 0, 1, 1]];
            _root.存档系统 = {dirtyMark:false};
            var submitSawDirty:Boolean = false;
            var rebuildSawCommitted:Boolean = false;
            _root.singleSubmit = function(name:String, count:Number,
                                          context:Object):Boolean {
                submitSawDirty = _root.存档系统.dirtyMark === true
                    && name == "战宠灵石" && count == 10;
                return true;
            };
            _root.战宠UI函数.重建宠物单位 = function(id:Number,
                                                            upgrade:Boolean,
                                                            effectName:String):Boolean {
                rebuildSawCommitted = id == 0 && upgrade === true
                    && effectName == "升级动画2"
                    && _root.宠物信息[0][1] == 6
                    && _root.宠物信息[0][5].宠物升级所需经验 == 6000
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null;
                return false;
            };
            var committed:Object = PetPanelService.levelUpSlot(0);
            check(committed.success === true && committed.newLevel == 6
                    && committed.stoneCost == 10 && committed.newXpNeeded == 6000
                    && committed.rebuilt !== true && committed.refreshDeferred === true
                    && submitSawDirty && rebuildSawCommitted
                    && typeof _root.宠物信息[0][5] == "object"
                    && _root.战宠UI函数._宠物刷新待处理[0].reason == "level_up",
                "升级显式提交灵石+等级+下一阈值后才重建；重建失败仍返回成功并请求刷新");

            _root.宠物信息 = [[66, 6, 200, 0, 1, {customName:"铁卫"}]];
            _root.存档系统 = {dirtyMark:false};
            var renameSawAuthority:Boolean = false;
            _root.战宠UI函数.重建宠物单位 = function(id:Number,
                                                            upgrade:Boolean):Boolean {
                renameSawAuthority = _root.存档系统.dirtyMark === true
                    && _root.战宠UI函数.获取宠物显示名(id) == "先锋"
                    && upgrade !== true;
                return false;
            };
            var oldDisplayName:String = _root.战宠UI函数.获取宠物显示名(0);
            var renamed:Object = PetPanelService.renamePetSlot(0, "先锋");
            check(oldDisplayName == "铁卫" && renamed.success === true
                    && renamed.name == "先锋" && renamed.refreshDeferred === true
                    && _root.宠物信息[0][5].customName == "先锋"
                    && _root.战宠UI函数.获取宠物显示名(0) == "先锋"
                    && renameSawAuthority
                    && _root.战宠UI函数._宠物刷新待处理[0].reason == "rename",
                "customName 是显示名唯一覆盖权威，重命名 dirty-first 且部署态统一完整重建");

            var deleteCandidate:Array = [66, 25, 200, 0, 1, {
                宠物升级所需经验:10000, 托管长枪:{name:"L85A1"}
            }];
            _root.宠物信息 = [deleteCandidate];
            _root.存档系统 = {dirtyMark:false};
            var failedDeleteProjectionCalls:Number = 0;
            ManagedLongGunService.preflightWithdrawal = function():Object {
                return {success:false, error:"inventory_full"};
            };
            _root.战宠UI函数.移除场景宠物槽 = function():Boolean {
                failedDeleteProjectionCalls++;
                return true;
            };
            var deleteBlocked:Object = PetPanelService.deletePetSlot(0);
            check(deleteBlocked.success !== true && deleteBlocked.error == "inventory_full"
                    && _root.宠物信息[0] === deleteCandidate
                    && _root.存档系统.dirtyMark === false
                    && failedDeleteProjectionCalls == 0,
                "解散托管武器预检失败时宠物/存档/场景均零写");

            var remaining:Array = [66, 1, 200, 0, 1, {}];
            _root.宠物信息 = [deleteCandidate, remaining];
            _root.存档系统 = {dirtyMark:false};
            var deleteWorld:Object = {};
            var deletedRuntime:Object = {
                _name:"宠物0敌人-终结者T800", _parent:deleteWorld,
                宠物属性:{宠物信息数组号:0}
            };
            var remainingRuntime:Object = {
                _name:"宠物1敌人-终结者T800", _parent:deleteWorld,
                宠物属性:{宠物信息数组号:1}
            };
            deleteWorld[deletedRuntime._name] = deletedRuntime;
            deleteWorld[remainingRuntime._name] = remainingRuntime;
            _root.宠物mc库 = [deletedRuntime, remainingRuntime];
            _root.出战宠物id库 = [0, 1];
            var withdrawCalls:Number = 0;
            var acquireCalls:Number = 0;
            var teardownAfterCommit:Boolean = false;
            var removedRuntime:Array = [];
            var fullReloadCalls:Number = 0;
            ManagedLongGunService.preflightWithdrawal = function():Object {
                return {success:true, required:true};
            };
            ManagedLongGunService.withdraw = function():Object {
                withdrawCalls++;
                return {success:true};
            };
            ItemUtil.singleRequire = function():Object { return {}; };
            _root.singleAcquire = function(name:String, count:Number,
                                           context:Object):Boolean {
                acquireCalls++;
                return name == "战宠灵石" && count == 4
                    && _root.存档系统.dirtyMark === true;
            };
            _root.战宠UI函数.移除场景宠物槽 = oldRemoveSceneSlot;
            _root.战宠UI函数.安全移除装备单位 = function(unit:Object):Boolean {
                teardownAfterCommit = _root.宠物信息[0].length == 0
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null;
                removedRuntime.push(unit);
                return true;
            };
            _root.删除场景宠物 = function():Boolean {
                fullReloadCalls++;
                return true;
            };
            _root.加载宠物 = function():Boolean {
                fullReloadCalls++;
                return true;
            };
            var deleted:Object = PetPanelService.deletePetSlot(0);
            check(deleted.success === true && deleted.deleted === true
                    && deleted.stoneRefund == 4 && deleted.weaponReturned === true
                    && deleted.refreshDeferred === false
                    && _root.宠物信息[0].length == 0
                    && withdrawCalls == 1 && acquireCalls == 1
                    && teardownAfterCommit && removedRuntime.length == 1
                    && removedRuntime[0] === deletedRuntime && fullReloadCalls == 0
                    && _root.宠物mc库.length == 1
                    && _root.宠物mc库[0] === remainingRuntime
                    && _root.出战宠物id库.length == 1
                    && _root.出战宠物id库[0] == 1
                    && deleteWorld[deletedRuntime._name] === deletedRuntime
                    && deleteWorld[remainingRuntime._name] === remainingRuntime
                    && _root.战宠UI函数._宠物刷新待处理[0] == undefined,
                "共享解散核心提交资产后只撤目标 slot；软别名残留不触发全场清空或重载");

            var worldExisting:Array = [66, 5, 200, 0, 1, {}];
            var worldPetData:Array = [66, 8, 120, 0, 1, {}];
            var worldExistingRuntime:Object = {
                _name:"宠物0敌人-终结者T800",
                宠物属性:{宠物信息数组号:0}
            };
            _root.宠物信息 = [worldExisting, []];
            _root.宠物mc库 = [worldExistingRuntime];
            _root.出战宠物id库 = [0];
            _root.等级 = 25;
            _root.最大宠物出战数 = 5;
            _root.isChallengeMode = function():Boolean { return false; };
            _root.isEasyMode = function():Boolean { return false; };
            _root.金钱 = 1000;
            _root.存档系统 = {dirtyMark:false};
            var worldNpcRemoved:Boolean = false;
            var worldParent:Object = {
                hero:{_x:320, _y:240},
                hireNpc:{_x:100, removeMovieClip:function():Void {
                    worldNpcRemoved = true;
                }}
            };
            worldParent[worldExistingRuntime._name] = worldExistingRuntime;
            worldExistingRuntime._parent = worldParent;
            _root.gameworld = worldParent;
            _root.控制目标 = "hero";
            _root._pendingHire = {
                npcId:"hireNpc", pet:worldPetData, 雇佣价格:100
            };
            var worldDeployCalls:Number = 0;
            var worldDeploySawCommit:Boolean = false;
            _root.战宠UI函数.设置宠物出战 = function(id:Number,
                                                            deployed:Boolean,
                                                            x:Number, y:Number):Boolean {
                worldDeployCalls++;
                worldDeploySawCommit = id == 1 && deployed === true
                    && x == 320 && y == 240
                    && _root.宠物信息[1] === worldPetData
                    && _root.宠物mc库.length == 1
                    && _root.宠物mc库[0] === worldExistingRuntime
                    && org.flashNight.arki.item.PlayerAssetTransaction.current() == null;
                var adoptedRuntime:Object = {
                    宠物属性:{宠物信息数组号:id}, _parent:worldParent
                };
                _root.宠物mc库.push(adoptedRuntime);
                _root.出战宠物id库.push(id);
                return true;
            };
            var worldAdoptResponse:String = "";
            _root.server = {sendSocketMessage:function(payload:String):Boolean {
                worldAdoptResponse = payload;
                return true;
            }};
            fullReloadCalls = 0;
            PetPanelService.handleWorldAdopt({callId:"world_targeted"});
            check(worldDeployCalls == 1 && worldDeploySawCommit
                    && fullReloadCalls == 0 && worldNpcRemoved
                    && _root.宠物信息[0] === worldExisting
                    && _root.宠物信息[1] === worldPetData
                    && _root.宠物mc库.length == 2
                    && _root.宠物mc库[0] === worldExistingRuntime
                    && _root.出战宠物id库[0] == 0
                    && _root.出战宠物id库[1] == 1
                    && worldParent[worldExistingRuntime._name] === worldExistingRuntime
                    && _root._pendingHire == undefined
                    && _root.金钱 == 900 && _root.存档系统.dirtyMark === true
                    && worldAdoptResponse.indexOf('"success":true') >= 0
                    && worldAdoptResponse.indexOf('"refreshDeferred":false') >= 0
                    && _root.战宠UI函数._宠物刷新待处理[1] == undefined,
                "world_adopt 提交后只部署新 slot，既有 canonical 软别名与同图单位原样保留");
        } finally {
            _root.宠物信息 = oldPetInfo;
            _root.宠物库 = oldPetCatalog;
            _root.宠物mc库 = oldPetUnits;
            _root.出战宠物id库 = oldDeployedIds;
            _root.等级限制 = oldLevelLimit;
            _root.等级 = oldLevel;
            _root.最大宠物出战数 = oldMaxDeploy;
            _root.金钱 = oldMoney;
            _root.存档系统 = oldSave;
            _root.当前为战斗地图 = oldCombatMap;
            _root.isChallengeMode = oldChallengeMode;
            _root.isEasyMode = oldEasyMode;
            _root.singleSubmit = oldSingleSubmit;
            _root.singleAcquire = oldSingleAcquire;
            _root.战宠UI函数.计算战宠升级所需经验 = oldRequirement;
            _root.战宠UI函数.重建宠物单位 = oldRebuild;
            _root.战宠UI函数.移除场景宠物槽 = oldRemoveSceneSlot;
            _root.战宠UI函数.安全移除装备单位 = oldSafeRemove;
            _root.战宠UI函数.设置宠物出战 = oldSetPetDeploy;
            _root.战宠UI函数._宠物刷新待处理 = oldRefreshDeferred;
            _root.删除场景宠物 = oldDeleteScene;
            _root.加载宠物 = oldLoadPets;
            ManagedLongGunService.preflightWithdrawal = oldPreflight;
            ManagedLongGunService.withdraw = oldWithdraw;
            ItemUtil.singleRequire = oldSingleRequire;
            _root.物品栏 = oldInventory;
            _root.收集品栏 = oldCollections;
            ItemUtil.materialDict = oldMaterialDict;
            delete ItemUtil.itemDataDict["战宠灵石"];
            _root.server = oldServer;
            _root.宠物信息界面 = oldPetInfoPanel;
            _root.gameworld = oldGameworld;
            _root.控制目标 = oldControlTarget;
            _root._pendingHire = oldPendingHire;
        }
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
