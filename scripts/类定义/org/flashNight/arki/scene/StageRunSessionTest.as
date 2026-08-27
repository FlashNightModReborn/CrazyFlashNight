import org.flashNight.aven.test.*;

import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.LootContainerService;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.item.itemCollection.InformationCollection;
import org.flashNight.neur.Event.EventDispatcher;

/** StageRunSession 的 outcome/life 正交状态、复活与结算冻结 focused 回归。 */
class org.flashNight.arki.scene.StageRunSessionTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var _backup:Object;
    private static var _testHero:MovieClip;
    private static var REWARD:String = "StageRunSession测试补给";
    private static var REVIVE:String = "复活币";

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        trace("=== StageRunSessionTest start ===");
        backupWorld();
        installMetadata();

        testOutcomeLifeAndFrameClock();
        testKillReportAndRewardFreeze();
        testAssetFlowReportAndBoundedTypes();
        testVictoryThenDeathCanReviveExactlyOnce();
        testRealDispatcherReceivesHeroArgument();
        testFailedRespawnRefundsAndRestrictionDoesNotSpend();
        testProjectionFailureCannotBreakRevive();
        testReturnFreezesAndOfflinePanelPreservesRewards();
        testReturnAvailabilityAndRetreat();
        testDeliverableReturnWaitsForSettlementVisualClose();
        testHostIntentRevisionAndIdempotency();

        restoreWorld();
        trace("StageRunSessionTest Tests Passed: " + _passed);
        trace("StageRunSessionTest Tests Failed: " + _failed);
        trace("=== StageRunSessionTest end ===");
    }

    private static function testOutcomeLifeAndFrameClock():Void {
        resetWorld(0);
        var hero:MovieClip = installHero("success");
        assertTrue(StageRunSession.begin("测试关卡", "困难"),
            "begin creates one stage run");
        for (var i:Number = 0; i < 45; i++) StageRunSession.tick();
        StageRunSession.finish("victory");
        StageRunSession.onHeroDeath();
        var state:Object = StageRunSession.testOnlySnapshot();
        assertEquals(45, state.activeFrames, "unpaused StageManager frames are the report clock");
        assertEquals("victory", state.outcome, "victory survives a later death");
        assertEquals("dead", state.life, "post-victory death remains independently visible");
        var companion:MovieClip = _root.createEmptyMovieClip(
            "__stageRunSessionTestCompanion", _root.getNextHighestDepth());
        companion.hp = 100;
        StageRunSession.onHeroRespawn(companion);
        assertEquals("dead", StageRunSession.testOnlySnapshot().life,
            "a non-player respawn cannot clear the hero death state");
        companion.removeMovieClip();
        hero.dispatcher.publish("respawn", hero);
        assertEquals("alive", StageRunSession.testOnlySnapshot().life,
            "respawn changes only the life axis");
    }

    /**
     * 生产 EventBus v3 只用 scope 绑定 this，不会把 scope 隐式塞进第一个形参。
     * 这条回归必须经过真实 EventDispatcher，防止无参数测试替身再次掩盖
     * “监听已发布但 target 为 undefined，玩家仍伏地并重新弹窗”的故障。
     */
    private static function testRealDispatcherReceivesHeroArgument():Void {
        resetWorld(1);
        var hero:MovieClip = installHero("real_dispatcher");
        StageRunSession.begin("真实分发复活", "困难");
        StageRunSession.onHeroDeath();
        var revived:Object = StageRunSession.requestReviveLocal("focused_test");
        assertTrue(revived.success === true,
            "shared revive publishes the hero through the real EventDispatcher");
        assertEquals(100, hero.hp,
            "real dispatcher callback receives the hero and restores hp");
        assertEquals(1, hero.__respawnPublishCount,
            "real dispatcher executes exactly one respawn callback");
        assertEquals("alive", StageRunSession.testOnlySnapshot().life,
            "real dispatcher revive commits the life axis");
        assertEquals(0, ItemUtil.getTotal(REVIVE),
            "real dispatcher revive spends exactly one coin without rollback");
    }

    private static function testKillReportAndRewardFreeze():Void {
        resetWorld(0);
        _root.关卡可获得奖励品 = [
            [REWARD, 1, 1], ["金钱", 1, 1], ["经验", 1, 1],
            [REWARD, 2147483648, 1], [REWARD, 1, 2147483648]
        ];
        StageRunSession.begin("统计关卡", "挑战");
        for (var frame:Number = 0; frame < 61; frame++) StageRunSession.tick();
        for (var i:Number = 0; i < 100; i++) {
            StageRunSession.recordKillProjection({
                key:"enemy." + i,
                displayName:"敌人 " + i,
                iconName:"敌人图标 " + i,
                doll:null,
                eliteLevel:i == 0 ? 2 : 0
            });
        }
        StageRunSession.finish("victory");
        assertTrue(StageRunSession.prepareSettlement(),
            "settlement freezes a valid reward inventory");
        var state:Object = StageRunSession.testOnlySnapshot();
        var report:Object = state.report;
        assertEquals("victory", report.outcome, "frozen report keeps outcome");
        assertEquals(61, report.activeFrames, "frozen report keeps exact active frames");
        assertEquals(100, report.totalKills, "all kill facts remain counted");
        assertEquals(96, report.kills.length, "kill presentation has a bounded type list");
        assertEquals(4, report.omittedKillTypes, "omitted unique kill types are explicit");
        assertEquals(3, state.inventory.size(), "all deterministic rewards materialize once");
        assertEquals(REWARD, state.inventory.getItem(0).name,
            "ordinary reward keeps its item identity");
        assertEquals("金币", state.inventory.getItem(1).name,
            "legacy money reward normalizes to scalar authority identity");
        assertEquals("经验值", state.inventory.getItem(2).name,
            "legacy experience reward normalizes to scalar authority identity");
        assertEquals(2, report.rewardRollOmissions,
            "reward random spans above AVM1 int range fail closed");
        assertFalse(StageRunSession.begin("覆盖关卡", "简单"),
            "a frozen unclaimed reward blocks run overwrite");
    }

    private static function testAssetFlowReportAndBoundedTypes():Void {
        resetWorld(0);
        assertTrue(StageRunSession.begin("物资统计", "挑战"),
            "asset report starts with the same authoritative stage run");
        StageRunSession.recordAssetProjection({
            direction:"gain", kind:"material", itemKey:REWARD,
            name:"测试补给显示名", icon:"测试补给图标", tier:"普通",
            source:"pickup", reason:"ground_loot", count:2
        });
        StageRunSession.recordAssetProjection({
            direction:"gain", kind:"material", itemKey:REWARD,
            name:"测试补给显示名", icon:"测试补给图标", tier:"普通",
            source:"pickup", reason:"ground_loot", count:3
        });
        StageRunSession.recordAssetProjection({
            direction:"loss", kind:"item", itemKey:REWARD,
            name:"测试补给显示名", icon:"测试补给图标", tier:"",
            source:"item_use", reason:"consume", count:1
        });
        StageRunSession.recordAssetProjection({
            direction:"neutral", kind:"item", itemKey:"ignored",
            name:"ignored", icon:"", tier:"", source:"unknown", reason:"", count:99
        });
        StageRunSession.finish("victory");
        assertTrue(StageRunSession.prepareSettlement(),
            "settlement freezes pickup and consumption facts with the run");
        var report:Object = StageRunSession.testOnlySnapshot().report;
        assertEquals(5, report.totalItemGains,
            "same pickup fact aggregates its exact positive quantity");
        assertEquals(1, report.totalItemLosses,
            "item consumption stays on an independent loss total");
        assertEquals(2, report.itemFlows.length,
            "gain and loss remain two explicit presentation facts");
        assertTrue(report.itemFlows[0].direction == "gain"
                && report.itemFlows[0].displayName == "测试补给显示名"
                && report.itemFlows[0].source == "pickup"
                && report.itemFlows[0].reason == "ground_loot"
                && report.itemFlows[0].count == 5,
            "pickup report preserves catalog display, source, reason, and aggregate count");
        assertTrue(report.itemFlows[1].direction == "loss"
                && report.itemFlows[1].source == "item_use"
                && report.itemFlows[1].reason == "consume"
                && report.itemFlows[1].count == 1,
            "consumption report preserves the authoritative asset broadcast context");
        assertEquals(0, report.omittedItemFlowTypes,
            "invalid neutral broadcasts do not consume the presentation budget");
        StageRunSession.recordAssetProjection({
            direction:"gain", kind:"item", itemKey:"late.fact", name:"late.fact",
            icon:"", tier:"", source:"pickup", reason:"late", count:7
        });
        assertEquals(5, report.totalItemGains,
            "a frozen settlement report cannot be mutated by a later broadcast");

        resetWorld(0);
        assertTrue(StageRunSession.begin("物资类型上限", "挑战"),
            "a fresh run owns a fresh bounded asset ledger");
        for (var i:Number = 0; i < 98; i++) {
            StageRunSession.recordAssetProjection({
                direction:"gain", kind:"item", itemKey:"asset." + i,
                name:"物资 " + i, icon:"物资图标", tier:"", source:"pickup",
                reason:"ground_loot", count:1
            });
        }
        StageRunSession.finish("victory");
        assertTrue(StageRunSession.prepareSettlement(),
            "bounded asset ledger remains a valid settlement report");
        report = StageRunSession.testOnlySnapshot().report;
        assertEquals(98, report.totalItemGains,
            "bounded presentation never drops the exact aggregate gain total");
        assertEquals(96, report.itemFlows.length,
            "asset presentation list is capped at the frozen protocol maximum");
        assertEquals(2, report.omittedItemFlowTypes,
            "each extra unique asset type is disclosed exactly once");
    }

    private static function testVictoryThenDeathCanReviveExactlyOnce():Void {
        resetWorld(2);
        var hero:Object = installHero("success");
        StageRunSession.begin("通关后死亡", "困难");
        StageRunSession.finish("victory");
        StageRunSession.onHeroDeath();
        var revived:Object = StageRunSession.requestReviveLocal("focused_test");
        assertTrue(revived.success === true,
            "victory followed by death still accepts the shared revive path");
        assertEquals(100, hero.hp, "respawn event restores hero hp");
        var state:Object = StageRunSession.testOnlySnapshot();
        assertEquals("victory", state.outcome, "revive cannot erase victory");
        assertEquals("alive", state.life, "successful respawn returns life to alive");
        assertEquals(1, ItemUtil.getTotal(REVIVE), "successful revive spends exactly one coin");
        var duplicate:Object = StageRunSession.requestReviveLocal("focused_test");
        assertEquals("actor_alive", duplicate.error, "alive actor cannot spend a second revive coin");
        assertEquals(1, ItemUtil.getTotal(REVIVE), "rejected duplicate revive is zero-write");

        resetWorld(2);
        hero = installHero("no_effect");
        StageRunSession.begin("外部恢复校正", "困难");
        StageRunSession.onHeroDeath();
        hero.hp = 50;
        var reconciled:Object = StageRunSession.requestReviveLocal("focused_test");
        assertEquals("actor_alive", reconciled.error,
            "an already restored hero reconciles without another revive");
        assertEquals("alive", StageRunSession.testOnlySnapshot().life,
            "external hp recovery repairs the life projection");
        assertEquals(2, ItemUtil.getTotal(REVIVE),
            "external hp recovery spends no revive coin");

        resetWorld(1);
        installHero("success_throw");
        StageRunSession.begin("复活后回调抛错", "困难");
        StageRunSession.onHeroDeath();
        var postWriteThrow:Object = StageRunSession.requestReviveLocal("focused_test");
        assertTrue(postWriteThrow.success === true,
            "a dispatcher throw after real hp recovery still commits the revive");
        assertEquals("alive", StageRunSession.testOnlySnapshot().life,
            "post-write dispatcher failure cannot mark a restored hero dead again");
        assertEquals(0, ItemUtil.getTotal(REVIVE),
            "post-write dispatcher failure never refunds an already successful revive");
    }

    private static function testFailedRespawnRefundsAndRestrictionDoesNotSpend():Void {
        resetWorld(1);
        var hero:Object = installHero("no_effect");
        StageRunSession.begin("复活回滚", "困难");
        StageRunSession.onHeroDeath();
        var failed:Object = StageRunSession.requestReviveLocal("focused_test");
        assertEquals("respawn_dispatch_failed", failed.error,
            "a dispatched event without hp recovery is not accepted");
        assertEquals(1, ItemUtil.getTotal(REVIVE), "failed respawn refunds the deducted coin");
        assertEquals("dead", StageRunSession.testOnlySnapshot().life,
            "failed respawn returns to dead for retry");
        assertEquals(1, hero.dispatcher.publishCount, "failed path dispatches only once");

        resetWorld(1);
        hero = installHero("success");
        _root.限制系统.DisableResurrection = true;
        StageRunSession.begin("禁复活", "挑战");
        StageRunSession.onHeroDeath();
        var restricted:Object = StageRunSession.requestReviveLocal("focused_test");
        assertEquals("resurrection_restricted", restricted.error,
            "stage restriction rejects revive before dispatch");
        assertEquals(1, ItemUtil.getTotal(REVIVE), "restricted revive spends no coin");
        assertEquals(0, hero.dispatcher.publishCount, "restricted revive publishes no respawn event");
    }

    private static function testProjectionFailureCannotBreakRevive():Void {
        resetWorld(1);
        var hero:MovieClip = installHero("success");
        _root.server = {
            isSocketConnected:true,
            sendTaskToNode:function():Void { throw new Error("forced_projection_failure"); }
        };
        StageRunSession.begin("投影断线", "困难");
        StageRunSession.onHeroDeath();
        var revived:Object = StageRunSession.requestReviveLocal("focused_test");
        assertTrue(revived.success === true,
            "a throwing C# projection cannot interrupt the authoritative revive");
        assertEquals(100, hero.hp,
            "projection failure still leaves the hero restored");
        assertEquals(0, ItemUtil.getTotal(REVIVE),
            "projection failure still commits exactly one revive coin");
    }

    private static function testReturnFreezesAndOfflinePanelPreservesRewards():Void {
        resetWorld(0);
        _root.关卡可获得奖励品 = [[REWARD, 1, 1]];
        installHero("no_effect");
        StageRunSession.begin("离线结算", "简单");
        StageRunSession.finish("victory");
        StageRunSession.onHeroDeath();
        _root.返回基地 = function():Boolean {
            return StageRunSession.onReturnBaseStarted();
        };
        var returned:Object = StageRunSession.requestReturnBaseLocal("focused_test");
        assertTrue(returned.success === true, "dead post-victory actor can return to base");
        var state:Object = StageRunSession.testOnlySnapshot();
        assertTrue(state.returnRequested === true, "return freezes the run before transition");
        assertEquals("prepared", state.settlement, "return prepares one settlement object");
        assertEquals(1, state.inventory.size(), "prepared settlement keeps its reward");
        assertFalse(StageRunSession.canRequestRevive(),
            "return transition removes the revive capability before base load");
        assertEquals("return_in_progress",
            StageRunSession.requestReviveLocal("focused_test").error,
            "late settings recovery cannot spend a coin during return");

        _root.当前为战斗地图 = false;
        StageRunSession.onSceneReady();
        state = StageRunSession.testOnlySnapshot();
        assertEquals("rewards_pending", state.settlement,
            "offline Web open becomes a resumable reward state");
        assertEquals(1, state.remainingRewards, "offline open cannot lose the reward");
        assertTrue(LootContainerService.hasStageSettlementPending(),
            "anchorless settlement authority remains pending");
        var expiry:Object = LootContainerService.expireScene("scene_cleanup");
        assertEquals("LOOT_SUSPENDED", expiry.state,
            "base settlement survives unrelated scene cleanup");
        StageRunSession.onSettlementState("CONSUMED", 0);
        assertTrue(StageRunSession.onReturnBaseStarted(),
            "repeated return after a terminal settlement remains idempotent");
        state = StageRunSession.testOnlySnapshot();
        assertTrue(state.settlement == "claimed" && state.inventory == null,
            "terminal return cannot materialize the same stage rewards a second time");
    }

    private static function testReturnAvailabilityAndRetreat():Void {
        resetWorld(0);
        StageRunSession.begin("主动撤离", "困难");
        var blocked:Object = StageRunSession.requestReturnBaseLocal("focused_test");
        assertEquals("return_base_unavailable", blocked.error,
            "alive active run cannot use the outcome return action");
        StageRunSession.onHeroDeath();
        _root.返回基地 = function():Boolean {
            return StageRunSession.onReturnBaseStarted();
        };
        var returned:Object = StageRunSession.requestReturnBaseLocal("focused_test");
        assertTrue(returned.success === true, "dead active run may retreat to base");
        var state:Object = StageRunSession.testOnlySnapshot();
        assertEquals("retreat", state.outcome, "dead active return freezes a retreat outcome");
        assertEquals("prepared", state.settlement, "retreat still produces an empty settlement");
    }

    private static function testDeliverableReturnWaitsForSettlementVisualClose():Void {
        resetWorld(0);
        installHero("no_effect");
        var resolverCalls:Number = 0;
        var navigateCalls:Number = 0;
        var navigatedHotspot:String = "";
        StageRunSession.testOnlySetDeliverableHooks(
            function():Object {
                resolverCalls++;
                return {
                    hotspotId:"base_test_delivery",
                    returnNavigable:true,
                    navigable:_root.当前为战斗地图 !== true
                };
            },
            function(hotspotId:String):Boolean {
                navigateCalls++;
                navigatedHotspot = hotspotId;
                return true;
            }
        );
        StageRunSession.begin("交付透传", "困难");
        StageRunSession.finish("victory");
        _root.返回基地 = function():Boolean {
            return StageRunSession.onReturnBaseStarted();
        };

        var before:Object = StageRunSession.testOnlySnapshot();
        _root.gameCommands.stageOutcomeAction({
            task:"cmd", action:"stageOutcomeAction", v:1,
            runId:String(before.runId), expectedRevision:Number(before.revision),
            intent:"return_deliverable", intentId:"host.deliver.focused.1"
        });
        var returning:Object = StageRunSession.testOnlySnapshot();
        assertTrue(returning.returnRequested === true
                && returning.deliverAfterSettlement === true,
            "deliver intent first enters the normal frozen return flow");
        assertEquals(0, navigateCalls,
            "battle map never navigates before base settlement");

        _root.当前为战斗地图 = false;
        _root._webPanelPauseLease = "focused-stage-settlement-lease";
        StageRunSession.onSettlementState("CONSUMED", 0);
        assertEquals(0, navigateCalls,
            "authority terminal alone cannot overlap the visible Web panel");
        assertTrue(StageRunSession.testOnlySnapshot().deliverAfterSettlement === true,
            "pending delivery survives until exact visual close");

        StageRunSession.onWebPanelClosed();
        assertEquals(0, navigateCalls,
            "a still-held Web pause lease blocks premature navigation");
        _root._webPanelPauseLease = undefined;
        StageRunSession.onWebPanelClosed();
        assertTrue(navigateCalls == 1
                && navigatedHotspot == "base_test_delivery"
                && resolverCalls >= 2,
            "exact close re-resolves AS2 authority and navigates once");
        assertFalse(StageRunSession.testOnlySnapshot().deliverAfterSettlement,
            "successful handoff consumes the pending delivery intent");
        StageRunSession.onWebPanelClosed();
        assertEquals(1, navigateCalls,
            "duplicate close proof cannot replay task navigation");
    }

    private static function testHostIntentRevisionAndIdempotency():Void {
        resetWorld(2);
        installHero("success");
        StageRunSession.install();
        StageRunSession.begin("意图栅栏", "困难");
        StageRunSession.onHeroDeath();
        var before:Object = StageRunSession.testOnlySnapshot();
        var intent:Object = {
            task:"cmd", action:"stageOutcomeAction", v:1,
            runId:String(before.runId), expectedRevision:Number(before.revision),
            intent:"revive", intentId:"host.focused.1"
        };
        _root.gameCommands.stageOutcomeAction(intent);
        assertEquals("alive", StageRunSession.testOnlySnapshot().life,
            "exact host intent reaches the shared revive path");
        assertEquals(1, ItemUtil.getTotal(REVIVE), "exact host intent spends one coin");
        _root.gameCommands.stageOutcomeAction(intent);
        assertEquals(1, ItemUtil.getTotal(REVIVE), "duplicate intent id cannot replay a spend");
        var stale:Object = {
            task:"cmd", action:"stageOutcomeAction", v:1,
            runId:String(before.runId), expectedRevision:Number(before.revision),
            intent:"revive", intentId:"host.focused.2"
        };
        _root.gameCommands.stageOutcomeAction(stale);
        assertEquals(1, ItemUtil.getTotal(REVIVE), "new id with stale revision is also zero-write");
    }

    private static function installHero(mode:String):MovieClip {
        if (_testHero != undefined) _testHero.removeMovieClip();
        var hero:MovieClip = _root.createEmptyMovieClip(
            "__stageRunSessionTestHero", _root.getNextHighestDepth());
        _testHero = hero;
        hero.hp = 0;
        hero.hp满血值 = 100;
        if (mode == "real_dispatcher") {
            hero.__respawnPublishCount = 0;
            hero.dispatcher = new EventDispatcher();
            hero.dispatcher.subscribeSingle("respawn", function(target:MovieClip):Void {
                if (target !== hero) return;
                hero.__respawnPublishCount++;
                hero.hp = hero.hp满血值;
                StageRunSession.onHeroRespawn(hero);
            }, hero);
            _root.gameworld[_root.控制目标] = hero;
            return hero;
        }
        hero.dispatcher = {publishCount:0};
        hero.dispatcher.publish = function(eventName:String, target:MovieClip):Void {
            if (eventName != "respawn") return;
            this.publishCount++;
            if (target !== hero) return;
            if (mode == "success") {
                hero.hp = hero.hp满血值;
                StageRunSession.onHeroRespawn(hero);
            } else if (mode == "success_throw") {
                hero.hp = hero.hp满血值;
                StageRunSession.onHeroRespawn(hero);
                throw new Error("post-respawn listener failure");
            }
        };
        _root.gameworld[_root.控制目标] = hero;
        return hero;
    }

    private static function resetWorld(reviveCoins:Number):Void {
        if (_testHero != undefined) {
            _testHero.removeMovieClip();
            _testHero = undefined;
        }
        LootContainerService.testOnlyReset();
        StageRunSession.testOnlyReset();
        _root.gameworld = {};
        _root.控制目标 = "hero";
        _root.物品栏 = {
            背包:new ArrayInventory(null, 50),
            仓库:new ArrayInventory(null, 1200),
            战备箱:new ArrayInventory(null, 400)
        };
        _root.收集品栏 = {
            材料:new DictCollection(null),
            情报:new InformationCollection(null)
        };
        if (reviveCoins > 0) _root.收集品栏.材料.add(REVIVE, reviveCoins);
        _root.存档系统 = {dirtyMark:false};
        _root.金钱 = 0;
        _root.虚拟币 = 0;
        _root.经验值 = 0;
        _root.技能点数 = 0;
        _root.等级 = 1;
        _root.限制系统 = {
            DisableResurrection:false,
            clearEntries:function():Void { this.DisableResurrection = false; }
        };
        _root.关卡可获得奖励品 = [];
        _root.当前为战斗地图 = true;
        _root._webPanelPauseLease = undefined;
        _root.是否是某网站 = function():Boolean { return false; };
        _root.server = {isSocketConnected:false};
        _root.返回基地 = function():Boolean { return true; };
        _root.主角是否升级 = function():Void {};
    }

    private static function installMetadata():Void {
        ItemUtil.itemDataDict = {};
        ItemUtil.equipmentDict = {};
        ItemUtil.materialDict = {};
        ItemUtil.informationMaxValueDict = {};
        EquipmentUtil.modDict = {};
        addMeta(REWARD, "消耗品", "道具");
        addMeta(REVIVE, "收集品", "材料");
        addMeta("金币", "消耗品", "货币");
        addMeta("经验值", "消耗品", "货币");
        ItemUtil.materialDict[REVIVE] = true;
    }

    private static function addMeta(name:String, typeName:String, useName:String):Void {
        ItemUtil.itemDataDict[name] = {
            name:name, displayname:name, icon:name, type:typeName, use:useName,
            price:1, description:"StageRunSession focused test", data:{level:1}
        };
    }

    private static function backupWorld():Void {
        _backup = {
            itemDataDict:ItemUtil.itemDataDict,
            equipmentDict:ItemUtil.equipmentDict,
            materialDict:ItemUtil.materialDict,
            informationMaxValueDict:ItemUtil.informationMaxValueDict,
            modDict:EquipmentUtil.modDict,
            gameworld:_root.gameworld,
            controlTarget:_root.控制目标,
            inventory:_root.物品栏,
            collection:_root.收集品栏,
            saveSystem:_root.存档系统,
            money:_root.金钱,
            virtualCurrency:_root.虚拟币,
            experience:_root.经验值,
            skillPoints:_root.技能点数,
            level:_root.等级,
            restrictions:_root.限制系统,
            rewards:_root.关卡可获得奖励品,
            battleMap:_root.当前为战斗地图,
            pauseLease:_root._webPanelPauseLease,
            siteCheck:_root.是否是某网站,
            server:_root.server,
            returnBase:_root.返回基地,
            levelCheck:_root.主角是否升级
        };
    }

    private static function restoreWorld():Void {
        if (_testHero != undefined) {
            _testHero.removeMovieClip();
            _testHero = undefined;
        }
        LootContainerService.testOnlyReset();
        StageRunSession.testOnlyReset();
        ItemUtil.itemDataDict = _backup.itemDataDict;
        ItemUtil.equipmentDict = _backup.equipmentDict;
        ItemUtil.materialDict = _backup.materialDict;
        ItemUtil.informationMaxValueDict = _backup.informationMaxValueDict;
        EquipmentUtil.modDict = _backup.modDict;
        _root.gameworld = _backup.gameworld;
        _root.控制目标 = _backup.controlTarget;
        _root.物品栏 = _backup.inventory;
        _root.收集品栏 = _backup.collection;
        _root.存档系统 = _backup.saveSystem;
        _root.金钱 = _backup.money;
        _root.虚拟币 = _backup.virtualCurrency;
        _root.经验值 = _backup.experience;
        _root.技能点数 = _backup.skillPoints;
        _root.等级 = _backup.level;
        _root.限制系统 = _backup.restrictions;
        _root.关卡可获得奖励品 = _backup.rewards;
        _root.当前为战斗地图 = _backup.battleMap;
        _root._webPanelPauseLease = _backup.pauseLease;
        _root.是否是某网站 = _backup.siteCheck;
        _root.server = _backup.server;
        _root.返回基地 = _backup.returnBase;
        _root.主角是否升级 = _backup.levelCheck;
    }

    private static function assertTrue(value:Boolean, message:String):Void {
        if (value) {
            _passed++;
            trace("PASS: " + message);
        } else {
            _failed++;
            trace("[TEST_FAIL] " + message + " expected=true actual=false");
        }
    }

    private static function assertFalse(value:Boolean, message:String):Void {
        assertTrue(!value, message);
    }

    private static function assertEquals(expected, actual, message:String):Void {
        if (expected === actual) {
            _passed++;
            trace("PASS: " + message);
        } else {
            _failed++;
            trace("[TEST_FAIL] " + message + " expected=" + expected + " actual=" + actual);
        }
    }
}
