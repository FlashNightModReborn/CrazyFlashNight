import org.flashNight.aven.test.*;

import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.component.Effect.EffectSystem;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.LootContainerService;
import org.flashNight.arki.item.obtain.ItemObtainIndex;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.item.itemCollection.InformationCollection;
import org.flashNight.arki.map.MapHotspotResolver;
import org.flashNight.arki.map.MapPanelCatalog;
import org.flashNight.arki.map.MapPanelService;
import org.flashNight.arki.merc.ArenaController;
import org.flashNight.arki.merc.ArenaCalibrationService;
import org.flashNight.arki.merc.ArenaPanelService;
import org.flashNight.arki.scene.StageManager;
import org.flashNight.arki.stageSelect.StageSelectPanelService;
import org.flashNight.arki.task.TaskPanelService;
import org.flashNight.arki.task.TaskUtil;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.KillEventComponent;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.RespawnEventComponent;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.Server.SaveManager;

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
        testRespawnRestoresSkillAndSecondDeathGuards();
        testFailedRespawnRefundsAndRestrictionDoesNotSpend();
        testProjectionFailureCannotBreakRevive();
        testReturnFreezesAndOfflinePanelPreservesRewards();
        testZeroRewardOfflineSettlementSurvivesSceneExpiry();
        testSettlementRewardInformationCapFilter();
        testPreparedSettlementPersistsWithoutReroll();
        testReturnRequiresDurableSettlementFlush();
        testPersistedSettlementProgressAndRestartRestore();
        testPersistedSettlementVersionsFailClosed();
        testStageSettlementEmptyArrayShapeRepair();
        testTaskAndPetEmptyArrayShapeRepair();
        testPersistedSettlementTerminalCleanup();
        testReturnAvailabilityAndRetreat();
        testDeliverableReturnWaitsForSettlementVisualClose();
        testHostIntentRevisionAndIdempotency();
        testLifecycleAdmissionAndReservation();
        testStageManagerReservationAuthority();
        testStageLoaderRootExactlyOnce();
        testStageManagerProjectionFailures();
        testProductionSceneTransitionAuthority();
        testMapNavigationAuthority();
        testStageSelectLifecycleAuthority();
        testTaskDeferredEntryAuthority();
        testArenaDeferredLoadAuthority();
        testSoftlockObservationOwnerIsReadOnly();

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

    /**
     * 复现“死亡后只有小跳可用”：普通技能门读取 倒地，小跳则显式无条件。
     * 同一个 MovieClip 复活后还必须重新武装 _killed，保证第二次致死仍发布
     * kill/death，而不是只能等到换小地图重建单位。
     */
    private static function testRespawnRestoresSkillAndSecondDeathGuards():Void {
        resetWorld(0);
        var hero:MovieClip = installHero("no_effect");
        // TestLoader 不装载主角技能的时间轴帧脚本。这里执行与生产门相同的
        // 最小状态判定；runner 另行静态校验生产脚本仍把“默认/小跳”绑定到
        // 这两种语义，避免测试因缺失时间轴上下文而假红或自说自话。
        var ordinarySkillGate:Function = function():Boolean {
            return !this.倒地 ? true : false;
        };
        var smallJumpGate:Function = function():Boolean {
            return true;
        };
        hero.mp = 0;
        hero.mp满血值 = 80;
        hero.倒地 = true;
        hero._killed = true;
        hero._deathDiagLogged = true;
        hero._visible = false;
        hero.__animationCompleteCount = 0;
        hero.动画完毕 = function():Void {
            this.__animationCompleteCount++;
            this.状态 = "兵器站立";
        };
        hero.watchDogData = {
            initialized:true,
            zeroHPDetector:{zeroHPCounter:50, waitingForRespawn:true}
        };

        assertTrue(ordinarySkillGate.call(hero) === false,
            "downed death fixture blocks an ordinary skill before respawn");
        assertTrue(smallJumpGate.call(hero) === true,
            "downed death fixture reproduces the unconditional small-jump exception");

        RespawnEventComponent.onRespawn(hero);

        assertTrue(hero.hp == 100 && hero.mp == 80,
            "respawn restores the same unit's hp and mp");
        assertTrue(hero.倒地 === false
                && ordinarySkillGate.call(hero) === true,
            "respawn clears the downed gate before ordinary skills resume");
        assertTrue(hero._killed === false && hero._deathDiagLogged == undefined,
            "respawn rearms kill delivery and clears the prior death diagnostic guard");
        assertTrue(hero.watchDogData.zeroHPDetector.zeroHPCounter == 0
                && hero.watchDogData.zeroHPDetector.waitingForRespawn === false,
            "respawn resets zero-hp watchdog state instead of publishing a duplicate respawn");
        assertTrue(hero.__animationCompleteCount == 1 && hero._visible === true,
            "respawn performs one animation recovery and restores visibility");

        hero.__secondDeathCount = 0;
        hero.垂直速度 = 0;
        hero.状态改变 = function(nextState:String):Void {
            this.状态 = nextState;
        };
        hero.dispatcher = new EventDispatcher();
        hero.dispatcher.subscribeSingle("kill", KillEventComponent.onKill, hero);
        hero.dispatcher.subscribeSingle("death", function(target:MovieClip):Void {
            if (target === hero) hero.__secondDeathCount++;
        }, hero);
        hero.hp = 0;
        if (hero.hp <= 0 && !hero._killed) {
            hero.dispatcher.publish("kill", hero);
        }
        assertTrue(hero.__secondDeathCount == 1 && hero.状态 == "血腥死",
            "a second lethal hit reaches the production kill/death event chain");
        assertTrue(hero._killed === true,
            "the second death re-establishes the duplicate-death guard exactly once");
        TargetCacheManager.removeUnit(hero);
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

    private static function testLifecycleAdmissionAndReservation():Void {
        resetWorld(0);
        _root.当前为战斗地图 = true;
        assertEquals("", StageRunSession.reserveStageStart(
            "battle_map", "战斗图旁路", "简单"),
            "no-run battle map still rejects a forged stage reservation");
        _root.当前为战斗地图 = false;
        _root.斗兽标定模式 = true;
        assertEquals("", StageRunSession.reserveStageStart(
            "calibration", "标定旁路", "简单"),
            "no-run calibration state rejects an ordinary stage reservation");
        _root.斗兽标定模式 = false;
        var token:String = StageRunSession.reserveStageStart(
            "focused_test", "准入关卡", "困难");
        assertTrue(token != "", "first asynchronous stage start obtains a reservation");
        assertFalse(StageRunSession.onReturnBaseStarted(),
            "canonical return fails closed while a stage start is pending");
        StageManager.getInstance().clear();
        assertTrue(StageRunSession.isStageStartReservationValid(token),
            "ordinary StageManager.clear cannot cancel a pending reservation");
        assertEquals("", StageRunSession.reserveStageStart(
            "focused_test_2", "第二关卡", "简单"),
            "a second asynchronous start cannot reserve the same vacant run slot");
        assertFalse(StageRunSession.canStartStage(),
            "pending reservation closes the public stage admission gate");
        assertFalse(StageRunSession.cancelStageStart("wrong-token"),
            "only the exact owner token can cancel a reservation");
        assertTrue(StageRunSession.cancelStageStart(token),
            "the exact owner token releases a failed transition");
        assertFalse(StageRunSession.begin("准入关卡", "困难", token),
            "a cancelled asynchronous token cannot start a stale loaded scene");
        assertTrue(StageRunSession.testOnlySnapshot() == null,
            "cancelled token rejection creates no replacement run");
        assertTrue(StageRunSession.canStartStage(),
            "failed transition cancellation reopens stage admission");

        var beforeRestartToken:String = StageRunSession.reserveStageStart(
            "restart_aba", "重启前关卡", "简单");
        StageRunSession.resetForRestart();
        var afterRestartToken:String = StageRunSession.reserveStageStart(
            "restart_aba", "重启后关卡", "简单");
        assertTrue(beforeRestartToken != "" && afterRestartToken != ""
                && beforeRestartToken != afterRestartToken,
            "restart never reuses a prior stage-start token");
        assertFalse(StageRunSession.isStageStartReservationValid(beforeRestartToken)
                || StageRunSession.cancelStageStart(beforeRestartToken),
            "pre-restart token cannot inspect or cancel the post-restart reservation");
        assertTrue(StageRunSession.isStageStartReservationValid(afterRestartToken),
            "post-restart reservation remains owned by its new exact token");
        StageRunSession.cancelStageStart(afterRestartToken);

        token = StageRunSession.reserveStageStart(
            "focused_test", "准入关卡", "困难");
        assertTrue(token != "", "a later valid transition can reserve again");
        assertFalse(StageRunSession.begin("准入关卡", "困难"),
            "a matching target without the exact token cannot steal a reservation");
        assertTrue(StageRunSession.begin("准入关卡", "困难", token),
            "first gameplay frame consumes the matching reservation");
        var runId:String = String(StageRunSession.testOnlySnapshot().runId);
        assertFalse(StageRunSession.canStartStage(),
            "an active run blocks every new stage start");
        assertFalse(StageRunSession.begin("覆盖关卡", "简单"),
            "an active run cannot be overwritten by a second begin");
        assertEquals(runId, String(StageRunSession.testOnlySnapshot().runId),
            "rejected second begin preserves the original run identity");
        assertFalse(StageRunSession.canNavigateAwayFromStage(),
            "an active run blocks map and stage-select scene exits");

        StageRunSession.finish("victory");
        assertFalse(StageRunSession.canStartStage(),
            "victory remains nonterminal until canonical return and settlement");
        assertFalse(StageRunSession.canNavigateAwayFromStage(),
            "victory cannot bypass the canonical return lifecycle");
        assertTrue(StageRunSession.onReturnBaseStarted(),
            "canonical return freezes the victory settlement");
        assertFalse(StageRunSession.canStartStage(),
            "prepared settlement still blocks a new run");
        StageRunSession.onSettlementState("ABANDONED", 0);
        _root.当前为战斗地图 = false;
        assertTrue(StageRunSession.canStartStage(),
            "terminal settlement after return allows the next stage");
        assertTrue(StageRunSession.canNavigateAwayFromStage(),
            "terminal settlement after return allows ordinary navigation");
        token = StageRunSession.reserveStageStart(
            "focused_test", "下一关", "简单");
        assertTrue(token != "", "terminal returned run can reserve the next stage");
        assertTrue(StageRunSession.cancelStageStart(token),
            "terminal-run reservation remains exactly cancellable");

        resetWorld(0);
        assertTrue(StageRunSession.begin("失败关卡", "困难"),
            "failure coverage creates an independent active run");
        StageRunSession.finish("failure");
        assertFalse(StageRunSession.canStartStage(),
            "failure remains nonterminal until canonical return and settlement");
        assertFalse(StageRunSession.canNavigateAwayFromStage(),
            "failure cannot bypass the canonical return lifecycle");
    }

    private static function testStageManagerReservationAuthority():Void {
        var manager:StageManager = StageManager.getInstance();
        var stageData:Array = [minimalManagerStage("")];
        var obtainIndex:ItemObtainIndex = ItemObtainIndex.getInstance();
        var oldFade:Object = _root.淡出动画;
        var oldReturnBase:Object = _root.返回基地;
        obtainIndex.clearDynamicDiscoveries();

        resetWorld(0);
        _root.当前为战斗地图 = false;
        manager.dispose();
        var tokenA:String = StageRunSession.reserveStageStart(
            "manager_a", "管理器 A", "简单");
        assertTrue(manager.initialize(stageData, null, tokenA, false),
            "StageManager accepts a valid exact reservation before mutation");
        assertFalse(manager.abortPreparedStage("wrong-token"),
            "prepared manager rejects a forged abort token");
        assertTrue(StageRunSession.isStageStartReservationValid(tokenA),
            "forged abort preserves the exact reservation");
        assertTrue(manager.abortPreparedStage(tokenA),
            "exact abort clears an unentered prepared manager");
        assertFalse(manager.isActive,
            "exact abort clears prepared manager activity");

        var preservedRewards:Array = [["旧场景奖励", 1, 1]];
        var preparedRewards:Array = [["候选关奖励", 1, 1]];
        var preparedRewardConfig:Array = [{
            Name:"候选关掉落索引物", AcquisitionProbability:1, QuantityMax:1
        }];
        _root.关卡可获得奖励品 = preservedRewards;
        tokenA = StageRunSession.reserveStageStart(
            "manager_reward_abort", "奖励预载取消", "简单");
        assertTrue(manager.initialize(stageData, null, tokenA, false,
                preparedRewards, "奖励预载取消", preparedRewardConfig)
                && _root.关卡可获得奖励品 === preservedRewards
                && !obtainIndex.isStageDiscovered("奖励预载取消")
                && manager["hasPreparedStageRewardCache"] === true,
            "StageManager stages candidate rewards and drops without old-scene mutation");
        assertTrue(manager.abortPreparedStage(tokenA)
                && _root.关卡可获得奖励品 === preservedRewards
                && !obtainIndex.isStageDiscovered("奖励预载取消")
                && manager["hasPreparedStageRewardCache"] === false,
            "exact preload abort discards staged rewards and drops without pollution");

        tokenA = StageRunSession.reserveStageStart(
            "manager_a", "管理器 A", "简单");
        assertTrue(manager.initialize(stageData, null, tokenA, false),
            "late A/B coverage prepares request A");
        assertTrue(manager.abortPreparedStage(tokenA),
            "request A can release only its own preload");
        var tokenB:String = StageRunSession.reserveStageStart(
            "manager_b", "管理器 B", "简单");
        assertTrue(manager.initialize(stageData, null, tokenB, false),
            "request B can prepare after A releases");
        assertFalse(manager.abortPreparedStage(tokenA),
            "late request A error cannot abort prepared request B");
        assertTrue(manager.isActive
                && StageRunSession.isStageStartReservationValid(tokenB),
            "late A error preserves B manager state and reservation");
        assertTrue(manager.abortPreparedStage(tokenB),
            "request B remains exactly abortable by its own token");

        var invalidStageData:Array = [minimalManagerStage("missing_pool")];
        var invalidToken:String = StageRunSession.reserveStageStart(
            "invalid_timepool", "无效计时池", "简单");
        assertFalse(manager.initialize(invalidStageData, null, invalidToken, false),
            "invalid TimePool references fail StageManager initialization");
        assertTrue(StageRunSession.canStartStage() && !manager.isActive,
            "invalid TimePool exact-cancels reservation and leaves no active preload");

        var forgedToken:String = StageRunSession.reserveStageStart(
            "ordinary", "普通关", "简单");
        assertFalse(manager.initialize(stageData, null, forgedToken, true),
            "calibration host admission rejects a forged ordinary reservation source");
        assertTrue(StageRunSession.cancelStageStart(forgedToken),
            "owner can release reservation rejected by forged calibration admission");

        var calibrationToken:String = StageRunSession.reserveStageStart(
            "arena_calibration", "DEATH MATCH角斗场", "");
        assertTrue(manager.initialize(stageData, null, calibrationToken, true),
            "narrow calibration host accepts its exact source and target token");
        assertTrue(manager.abortPreparedStage(calibrationToken),
            "calibration preload has the same exact abort semantics");

        var cancelledCalibrationToken:String = StageRunSession.reserveStageStart(
            "arena_calibration", "DEATH MATCH角斗场", "");
        assertTrue(manager.initialize(stageData, null, cancelledCalibrationToken, true),
            "cancelled calibration coverage first prepares an exact host admission");
        StageRunSession.cancelStageStart(cancelledCalibrationToken);
        _root.斗兽标定模式 = true;
        _root.角斗场对手类型 = "calibration";
        manager.initStage();
        assertTrue(!manager.isActive && _root.当前为战斗地图 == false
                && StageRunSession.testOnlySnapshot() == null
                && _root.斗兽标定模式 !== true
                && _root.角斗场对手类型 != "calibration",
            "cancelled calibration token cannot enter or leave active calibration globals");
        _root.斗兽标定模式 = false;
        _root.角斗场对手类型 = undefined;

        var mismatchToken:String = StageRunSession.reserveStageStart(
            "normal_stage", "正规目标", "简单");
        assertTrue(manager.initialize(stageData, null, mismatchToken, false),
            "normal preload initializes before target mismatch coverage");
        _root.斗兽标定模式 = true;
        _root.角斗场对手类型 = "calibration";
        _root.当前关卡名 = "伪造目标";
        _root.当前关卡难度 = "简单";
        manager.initStage();
        assertTrue(!manager.isActive && StageRunSession.testOnlySnapshot() == null
                && !StageRunSession.isStageStartReservationValid(mismatchToken),
            "stale calibration globals cannot bypass normal token target matching");
        _root.斗兽标定模式 = false;
        _root.角斗场对手类型 = undefined;

        resetWorld(0);
        _root.当前为战斗地图 = false;
        manager.dispose();
        _root.当前关卡名 = "初始化异常关";
        _root.当前关卡难度 = "简单";
        var setupReturnCalls:Number = 0;
        var setupFadeCalls:Number = 0;
        _root.淡出动画 = {淡出跳转帧:function(frame:String):Void {
            setupFadeCalls++;
        }};
        _root.返回基地 = function():Boolean {
            setupReturnCalls++;
            if (!StageRunSession.onReturnBaseStarted()) return false;
            _root.淡出动画.淡出跳转帧("基地门口");
            manager.clear();
            _root.当前为战斗地图 = false;
            return true;
        };
        var setupFailureToken:String = StageRunSession.reserveStageStart(
            "setup_failure", "初始化异常关", "简单");
        assertTrue(manager.initialize(stageData, null, setupFailureToken, false,
                preparedRewards, "初始化异常关", preparedRewardConfig)
                && !obtainIndex.isStageDiscovered("初始化异常关"),
            "normal initStage coverage keeps staged drops undiscovered before exact init");
        manager["stageEventHandler"] = {
            init:function():Void {
                throw new Error("synthetic normal stage setup failure");
            },
            clear:function():Void {}
        };
        manager.initStage();
        var setupFailureState:Object = StageRunSession.testOnlySnapshot();
        assertTrue(_root.关卡可获得奖励品 !== preservedRewards
                && _root.关卡可获得奖励品[0][0] == "候选关奖励"
                && obtainIndex.isStageDiscovered("初始化异常关")
                && manager["hasPreparedStageRewardCache"] === false,
            "first exact gameplay init commits staged rewards and drops exactly once");
        assertTrue(!manager.isActive && _root.当前为战斗地图 === false
                && !StageRunSession.isStageStartReservationValid(setupFailureToken)
                && setupReturnCalls == 1 && setupFadeCalls == 1,
            "normal setup throw invokes one canonical return/fade and leaves no active manager");
        assertTrue(setupFailureState != null
                && setupFailureState.outcome == "failure"
                && setupFailureState.returnRequested === true,
            "normal setup throw becomes a canonical returnable failure terminal");
        manager.dispose();

        resetWorld(0);
        _root.当前为战斗地图 = false;
        manager.dispose();
        _root.当前关卡名 = "空奖励关";
        _root.当前关卡难度 = "简单";
        _root.关卡可获得奖励品 = preservedRewards;
        var emptyFadeCalls:Number = 0;
        var emptyReturnCalls:Number = 0;
        _root.淡出动画 = {淡出跳转帧:function(frame:String):Void {
            emptyFadeCalls++;
        }};
        _root.返回基地 = function():Boolean {
            emptyReturnCalls++;
            if (!StageRunSession.onReturnBaseStarted()) return false;
            _root.淡出动画.淡出跳转帧("基地门口");
            manager.clear();
            _root.当前为战斗地图 = false;
            return true;
        };
        var emptyRewardToken:String = StageRunSession.reserveStageStart(
            "empty_reward", "空奖励关", "简单");
        assertTrue(manager.initialize(stageData, null, emptyRewardToken, false,
                [], "空奖励关", [])
                && _root.关卡可获得奖励品 === preservedRewards
                && manager["hasPreparedStageRewardCache"] === true,
            "empty reward preload remains staged and preserves old-scene rewards");
        manager["stageEventHandler"] = {
            init:function():Void {
                throw new Error("synthetic empty reward setup stop");
            },
            clear:function():Void {}
        };
        manager.initStage();
        assertTrue(_root.关卡可获得奖励品 instanceof Array
                && _root.关卡可获得奖励品.length == 0
                && manager["hasPreparedStageRewardCache"] === false
                && emptyReturnCalls == 1 && emptyFadeCalls == 1,
            "first exact gameplay init commits an authored empty reward list");
        manager.dispose();

        resetWorld(0);
        _root.当前为战斗地图 = false;
        manager.dispose();
        _root.当前关卡名 = "掉落提交异常关";
        _root.当前关卡难度 = "简单";
        _root.关卡可获得奖励品 = preservedRewards;
        var commitThrowFadeCalls:Number = 0;
        var commitThrowReturnCalls:Number = 0;
        _root.淡出动画 = {淡出跳转帧:function(frame:String):Void {
            commitThrowFadeCalls++;
        }};
        _root.返回基地 = function():Boolean {
            commitThrowReturnCalls++;
            if (!StageRunSession.onReturnBaseStarted()) return false;
            _root.淡出动画.淡出跳转帧("基地门口");
            manager.clear();
            _root.当前为战斗地图 = false;
            return true;
        };
        var commitThrowToken:String = StageRunSession.reserveStageStart(
            "reward_commit_throw", "掉落提交异常关", "简单");
        assertTrue(manager.initialize(stageData, null, commitThrowToken, false,
                preparedRewards, "掉落提交异常关", preparedRewardConfig)
                && _root.关卡可获得奖励品 === preservedRewards,
            "drop commit exception coverage first prepares without visible mutation");
        var originalUpdateStageDrops:Function = obtainIndex.updateStageDrops;
        var updateStageDropsThrowCount:Number = 0;
        obtainIndex["updateStageDrops"] = function(stageName:String,
                rewards:Array):Boolean {
            updateStageDropsThrowCount++;
            throw new Error("synthetic updateStageDrops failure");
            return false;
        };
        manager.initStage();
        obtainIndex["updateStageDrops"] = originalUpdateStageDrops;
        assertTrue(updateStageDropsThrowCount == 1
                && _root.关卡可获得奖励品 === preservedRewards
                && manager["hasPreparedStageRewardCache"] === false
                && !manager.isActive && _root.当前为战斗地图 === false
                && commitThrowReturnCalls == 1 && commitThrowFadeCalls == 1,
            "drop commit throw preserves old rewards and enters recoverable failure return");
        manager.dispose();

        resetWorld(0);
        _root.当前为战斗地图 = false;
        manager.dispose();
        _root.当前关卡名 = "初始化异常重试关";
        _root.当前关卡难度 = "简单";
        var retryFade:Object = {
            calls:0,
            failNext:true,
            淡出跳转帧:function(frame:String):Void {
                this.calls++;
                if (this.failNext) throw new Error("synthetic fade failure");
            }
        };
        var retryReturnCalls:Number = 0;
        _root.淡出动画 = retryFade;
        _root.返回基地 = function():Boolean {
            retryReturnCalls++;
            if (!StageRunSession.onReturnBaseStarted()) return false;
            try {
                _root.淡出动画.淡出跳转帧("基地门口");
            } catch (fadeError) {
                return false;
            }
            manager.clear();
            _root.当前为战斗地图 = false;
            return true;
        };
        var retryFailureToken:String = StageRunSession.reserveStageStart(
            "setup_failure_retry", "初始化异常重试关", "简单");
        assertTrue(manager.initialize(stageData, null, retryFailureToken, false),
            "retryable initStage failure coverage prepares an exact first stage");
        manager["stageEventHandler"] = {
            init:function():Void {
                throw new Error("synthetic retryable stage setup failure");
            },
            clear:function():Void {}
        };
        manager.initStage();
        var retryFailureState:Object = StageRunSession.testOnlySnapshot();
        assertTrue(manager.isActive && manager.isFailed
                && _root.当前为战斗地图 === true
                && retryReturnCalls == 1 && retryFade.calls == 1
                && retryFailureState != null
                && retryFailureState.outcome == "failure"
                && retryFailureState.returnRequested === true,
            "rejected first fade preserves a fail-stopped battle manager for retry");
        retryFade.failNext = false;
        var retryAccepted:Boolean = _root.返回基地();
        assertTrue(retryAccepted && retryReturnCalls == 2 && retryFade.calls == 2
                && !manager.isActive && _root.当前为战斗地图 === false,
            "second canonical return retries the frozen run and clears after fade");
        manager.dispose();

        resetWorld(0);
        _root.当前为战斗地图 = false;
        _root.斗兽标定模式 = false;
        _root.角斗场对手类型 = undefined;
        var calibrationSetupToken:String = StageRunSession.reserveStageStart(
            "arena_calibration", "DEATH MATCH角斗场", "");
        assertTrue(manager.initialize(stageData, null, calibrationSetupToken, true),
            "calibration initStage failure coverage prepares its exact host token");
        _root.斗兽标定模式 = true;
        _root.角斗场对手类型 = "calibration";
        manager["stageEventHandler"] = {
            init:function():Void {
                throw new Error("synthetic calibration stage setup failure");
            },
            clear:function():Void {}
        };
        manager.initStage();
        assertTrue(!manager.isActive && _root.当前为战斗地图 === false
                && StageRunSession.testOnlySnapshot() == null
                && StageRunSession.canStartStage()
                && _root.斗兽标定模式 !== true,
            "calibration setup throw clears host state without creating a run or leak");
        manager.dispose();

        resetWorld(0);
        _root.当前为战斗地图 = false;
        assertTrue(StageRunSession.begin("活动清理门", "简单"),
            "ordinary clear coverage creates an active run");
        manager.isActive = true;
        manager.clear();
        assertTrue(manager.isActive && StageRunSession.testOnlySnapshot() != null,
            "ordinary StageManager.clear rejects an active run without half cleanup");
        manager.dispose();
        assertTrue(!manager.isActive && StageRunSession.testOnlySnapshot() == null
                && _root.当前为战斗地图 === false,
            "restart dispose force-resets manager and StageRunSession together");
        var restartToken:String = StageRunSession.reserveStageStart(
            "after_restart", "重启后关卡", "简单");
        assertTrue(restartToken != "",
            "forced restart reset reopens exact stage reservation admission");
        StageRunSession.cancelStageStart(restartToken);
        _root.淡出动画 = oldFade;
        _root.返回基地 = oldReturnBase;
    }

    private static function minimalManagerStage(timePoolRef:String):Object {
        var stage:Object = {
            BasicInformation:{Environment:{}},
            Wave:{SubWave:[]}
        };
        if (timePoolRef != "") stage.TimePoolRef = timePoolRef;
        return stage;
    }

    private static function testStageLoaderRootExactlyOnce():Void {
        resetWorld(0);
        _root.当前为战斗地图 = false;
        var productionLoader:Function = _root.载入关卡数据;
        assertTrue(typeof productionLoader == "function",
            "focused runner includes the production stage XML root coordinator");
        if (typeof productionLoader != "function") return;

        var loaderPrototype:Object =
            org.flashNight.gesh.xml.LoadXml.BaseStageXMLLoader.prototype;
        var oldLoad:Function = loaderPrototype.load;
        var oldManager:Object = StageManager.instance;
        var oldDebug:Object = _root.发布调试消息;
        var oldRewardsParser:Object = _root.解析并设置奖励品配置;
        var successCount:Number = 0;
        var errorCount:Number = 0;
        var stageData:Object = {
            Rewards:{Reward:[["loader-cache-probe", 1, 1]]},
            SubStage:[minimalManagerStage("")],
            TimePools:null
        };
        var managerStub:Object = {
            initializeCalls:0,
            abortCalls:0,
            prepared:false,
            stagedRewards:null,
            stagedDropName:"",
            stagedRewardConfig:null,
            throwInitialize:true,
            initialize:function(data, timePools, reservationToken,
                    allowCalibrationHost, stageRewards, stageDropName,
                    stageRewardConfig):Boolean {
                this.initializeCalls++;
                this.prepared = true;
                this.stagedRewards = stageRewards;
                this.stagedDropName = stageDropName;
                this.stagedRewardConfig = stageRewardConfig;
                if (this.throwInitialize) {
                    throw new Error("synthetic initialize failure");
                    return false;
                }
                return true;
            },
            abortPreparedStage:function(token:String):Boolean {
                this.abortCalls++;
                this.prepared = false;
                return true;
            }
        };
        var token:String = StageRunSession.reserveStageStart(
            "root_loader_throw", "生产根加载异常", "简单");

        StageManager["instance"] = managerStub;
        _root.发布调试消息 = function():Void {
            throw new Error("synthetic debug projection failure");
        };
        var oldStageRewards:Object = _root.关卡可获得奖励品;
        var loaderPreservedRewards:Array = [["loader-old-scene", 1, 1]];
        _root.关卡可获得奖励品 = loaderPreservedRewards;
        _root.解析并设置奖励品配置 = function():Array {
            return [["loader-staged-reward", 1, 1]];
        };
        loaderPrototype.load = function(onLoaded:Function, onLoadError:Function):Void {
            onLoaded(stageData);
            // 模拟底层错误/成功重复回调；root 必须保持 one-shot terminal。
            onLoadError();
            onLoaded(stageData);
        };

        productionLoader("无限过图", "data/stages/test.xml",
            function():Void { successCount++; },
            function():Void { errorCount++; }, token, false);

        assertEquals(1, managerStub.initializeCalls,
            "production stage XML root invokes throwing initialize once");
        assertTrue(errorCount == 1 && successCount == 0,
            "initialize throw produces exactly one error and zero success callbacks");
        assertTrue(managerStub.abortCalls == 1 && managerStub.prepared === false,
            "initialize throw exact-aborts its prepared manager state once");
        assertTrue(!StageRunSession.isStageStartReservationValid(token)
                && StageRunSession.canStartStage(),
            "initialize throw releases only its stage-start reservation");

        var successToken:String = StageRunSession.reserveStageStart(
            "root_loader_success", "生产根加载成功", "简单");
        managerStub.throwInitialize = false;
        managerStub.prepared = false;
        successCount = 0;
        errorCount = 0;
        productionLoader("无限过图", "data/stages/test.xml",
            function():Void { successCount++; },
            function():Void { errorCount++; }, successToken, false);
        assertTrue(successCount == 1 && errorCount == 0,
            "success debug throw still hands off exactly one success callback");
        assertTrue(managerStub.initializeCalls == 2 && managerStub.abortCalls == 1,
            "success and duplicate terminal callbacks do not repeat initialize or abort");
        assertTrue(managerStub.prepared === true
                && StageRunSession.isStageStartReservationValid(successToken),
            "success debug throw leaves prepared manager and exact token to its caller");
        assertTrue(_root.关卡可获得奖励品 === loaderPreservedRewards
                && managerStub.stagedRewards[0][0] == "loader-staged-reward"
                && managerStub.stagedDropName == "test"
                && managerStub.stagedRewardConfig[0][0] == "loader-cache-probe",
            "production root stages rewards on the exact manager without old-scene mutation");
        StageRunSession.cancelStageStart(successToken);
        managerStub.prepared = false;

        loaderPrototype.load = oldLoad;
        StageManager["instance"] = oldManager;
        _root.发布调试消息 = oldDebug;
        _root.解析并设置奖励品配置 = oldRewardsParser;
        _root.关卡可获得奖励品 = oldStageRewards;
        StageRunSession.testOnlyReset();
    }

    private static function testStageManagerProjectionFailures():Void {
        var manager:StageManager = StageManager.getInstance();
        var oldServer:Object = _root.server;
        var oldGameworld:Object = _root.gameworld;
        var oldStageAnimation:Object = _root.最上层加载外部动画;
        var oldStageFinished:Object = _root.关卡结束;
        var oldStageFrame:Object = _root.关卡地图帧值;
        var timedStage:Array = [minimalManagerStage("hud_pool")];
        var timePools:Array = [{
            Id:"hud_pool", DurationSeconds:5,
            DisplayName:"回归计时", TimeoutResult:"FailStage"
        }];
        var throwingServer:Object = {
            isSocketConnected:true,
            sendCount:0,
            sendSocketMessage:function():Boolean {
                this.sendCount++;
                throw new Error("synthetic socket failure");
                return false;
            }
        };
        _root.server = throwingServer;

        resetWorld(0);
        _root.当前为战斗地图 = false;
        manager.dispose();
        var abortToken:String = StageRunSession.reserveStageStart(
            "projection_abort", "投影清理", "简单");
        assertTrue(manager.initialize(timedStage, timePools, abortToken, false),
            "projection failure coverage prepares a timed stage");
        manager["timePoolController"].enterStage(0);
        assertTrue(manager.abortPreparedStage(abortToken) && !manager.isActive
                && StageRunSession.canStartStage(),
            "socket throw during TimePool flush still fully aborts manager and reservation");

        var clearToken:String = StageRunSession.reserveStageStart(
            "projection_clear", "清图投影", "简单");
        assertTrue(manager.initialize(timedStage, timePools, clearToken, false)
                && StageRunSession.begin("清图投影", "简单", clearToken),
            "clearStage projection coverage prepares a timed stage");
        var clearEvents:Array = [];
        manager.currentStage = 0;
        manager["currentStageInfo"] = {
            basicInfo:{Animation:{Load:0, Path:"synthetic"}, EndFrame:""}
        };
        _root.最上层加载外部动画 = function():Void {
            throw new Error("synthetic clear animation failure");
        };
        var clearWorld:MovieClip = _root.createEmptyMovieClip(
            "__stageManagerClearWorld", _root.getNextHighestDepth());
        clearWorld.关卡结束 = false;
        clearWorld.允许通行 = false;
        clearWorld.通关箭头 = {_visible:true};
        clearWorld.dispatcher = {
            publish:function(name:String):Void {
                clearEvents.push(name);
                if (name == "Clear" || name == "StageFinished") {
                    throw new Error("synthetic " + name + " listener failure");
                }
            }
        };
        _root.gameworld = clearWorld;
        manager.gameworld = clearWorld;
        manager["timePoolController"].enterStage(0);
        var clearEscaped:Boolean = false;
        try {
            manager.clearStage();
        } catch (clearError) {
            clearEscaped = true;
        }
        assertFalse(clearEscaped,
            "clearStage contains TimePool and native HUD socket projection failures");
        assertTrue(manager.isCleared && manager.isFinished
                && StageRunSession.testOnlySnapshot().outcome == "victory"
                && clearEvents.length == 2
                && clearEvents[0] == "Clear"
                && clearEvents[1] == "StageFinished",
            "throwing StageFinished listener still commits authoritative victory exactly once");
        manager.dispose();
        clearWorld.removeMovieClip();

        resetWorld(0);
        _root.当前为战斗地图 = false;
        var failToken:String = StageRunSession.reserveStageStart(
            "projection_fail", "失败投影", "简单");
        assertTrue(manager.initialize(timedStage, timePools, failToken, false)
                && StageRunSession.begin("失败投影", "简单", failToken),
            "failStage projection coverage creates the exact active run");
        var failEvents:Array = [];
        manager.currentStage = 0;
        var failWorld:MovieClip = _root.createEmptyMovieClip(
            "__stageManagerFailWorld", _root.getNextHighestDepth());
        failWorld.关卡结束 = false;
        failWorld.允许通行 = true;
        failWorld.通关箭头 = {_visible:true};
        failWorld.dispatcher = {
            publish:function(name:String):Void {
                failEvents.push(name);
                throw new Error("synthetic StageFailed listener failure");
            }
        };
        manager.gameworld = failWorld;
        manager["timePoolController"].enterStage(0);
        var failEscaped:Boolean = false;
        try {
            manager.failStage();
        } catch (failError) {
            failEscaped = true;
        }
        assertFalse(failEscaped,
            "failStage contains TimePool and native HUD socket projection failures");
        assertTrue(manager.isFailed && failEvents[0] == "StageFailed"
                && StageRunSession.testOnlySnapshot().outcome == "failure",
            "failStage socket throw still commits failure and publishes StageFailed");

        manager.dispose();
        failWorld.removeMovieClip();

        resetWorld(0);
        _root.当前为战斗地图 = false;
        var finishToken:String = StageRunSession.reserveStageStart(
            "projection_finish", "完成回调投影", "简单");
        assertTrue(manager.initialize(timedStage, timePools, finishToken, false)
                && StageRunSession.begin("完成回调投影", "简单", finishToken),
            "finish callback failure coverage creates the exact active run");
        manager.currentStage = 0;
        manager["currentStageInfo"] = {
            basicInfo:{Animation:{Load:1}, EndFrame:"投影完成帧"}
        };
        _root.关卡结束 = function():Void {
            throw new Error("synthetic finish callback failure");
        };
        var finishEscaped:Boolean = false;
        try {
            manager.finishStage();
        } catch (finishError) {
            finishEscaped = true;
        }
        assertTrue(!finishEscaped && manager.isFinished
                && StageRunSession.testOnlySnapshot().outcome == "victory"
                && _root.关卡地图帧值 == "投影完成帧",
            "throwing finish callback cannot interrupt victory terminal or EndFrame");

        var closeWorld:MovieClip = _root.createEmptyMovieClip(
            "__stageManagerCloseWorld", _root.getNextHighestDepth());
        manager.gameworld = closeWorld;
        manager.environment = {synthetic:true};
        manager.spawnPoints = [closeWorld];
        manager.isCleared = true;
        manager["spawner"] = {close:function():Void {
            throw new Error("synthetic spawner close failure");
        }};
        manager["stageEventHandler"] = {clear:function():Void {
            throw new Error("synthetic handler clear failure");
        }};
        var closeEscaped:Boolean = false;
        try {
            manager.closeStage();
        } catch (closeError) {
            closeEscaped = true;
        }
        assertTrue(!closeEscaped && manager.gameworld == null
                && manager.environment == null && manager.spawnPoints == null
                && manager.isCleared === false,
            "throwing close callbacks cannot retain manager refs or cleared flag");
        closeWorld.removeMovieClip();
        manager.dispose();
        _root.server = oldServer;
        _root.gameworld = oldGameworld;
        _root.最上层加载外部动画 = oldStageAnimation;
        _root.关卡结束 = oldStageFinished;
        _root.关卡地图帧值 = oldStageFrame;
    }

    /**
     * TestLoader 直接 include 生产场景转换脚本；这里调用捕获到的真实函数，
     * 防止测试替身把投影异常与权威 clear/FinishStage 顺序测成假绿。
     */
    private static function testProductionSceneTransitionAuthority():Void {
        var productionReturnBase:Function = _backup.returnBase;
        var productionStageFinished:Function = _backup.stageFinished;
        var oldPlayerInfo:Object = _root.玩家信息界面;
        var oldOutcomeUi:Object = _root.关卡结束界面;
        var oldRestrictions:Object = _root.限制系统;
        var oldSound:Object = _root.soundEffectManager;
        var oldFade:Object = _root.淡出动画;
        var oldNewSpawn:Object = _root.新出生;
        var oldEntry:Object = _root.场景进入位置名;
        var oldStageType:Object = _root.关卡类型;
        var oldStageFrame:Object = _root.关卡地图帧值;
        var oldFinishStage:Object = _root.FinishStage;
        var oldStageName:Object = _root.当前关卡名;
        var oldDifficulty:Object = _root.当前关卡难度;
        var oldReturnBase:Object = _root.返回基地;
        var oldStageFinished:Object = _root.关卡结束;
        var effectClass:Object = EffectSystem;
        var oldScreenEffect:Function = effectClass.ScreenEffect;
        var manager:StageManager = StageManager.getInstance();

        assertTrue(typeof productionReturnBase == "function"
                && typeof productionStageFinished == "function",
            "focused runner captures production return-base and stage-finished functions");
        if (typeof productionReturnBase != "function"
                || typeof productionStageFinished != "function") return;

        resetWorld(0);
        manager.dispose();
        var projectionHero:MovieClip = installHero("success");
        projectionHero.hp = 50;
        assertTrue(StageRunSession.begin("生产返回投影异常", "简单"),
            "production return projection coverage creates an active run");
        StageRunSession.finish("failure");
        manager.isActive = true;
        manager.isFailed = true;
        manager.currentStage = 0;
        _root.当前为战斗地图 = true;
        var projectionCounts:Object = {hp:0, restriction:0, bgm:0, fade:0, frame:undefined};
        _root.玩家信息界面 = {
            刷新hp显示:function():Void {
                projectionCounts.hp++;
                throw new Error("synthetic HP projection failure");
            },
            刷新mp显示:function():Void {}
        };
        _root.限制系统 = {clearEntries:function():Void {
            projectionCounts.restriction++;
            throw new Error("synthetic restriction projection failure");
        }};
        _root.soundEffectManager = {stopBGMForTransition:function():Void {
            projectionCounts.bgm++;
            throw new Error("synthetic BGM projection failure");
        }};
        _root.关卡结束界面 = {_visible:true, 关卡是否结束:true};
        _root.关卡地图帧值 = 37;
        _root.淡出动画 = {淡出跳转帧:function(frame):Void {
            projectionCounts.fade++;
            projectionCounts.frame = frame;
        }};
        _root.返回基地 = productionReturnBase;
        var projectionAccepted:Boolean = _root.返回基地();
        assertTrue(projectionAccepted && projectionCounts.hp == 1
                && projectionCounts.restriction == 1 && projectionCounts.bgm == 1
                && projectionCounts.fade == 1 && projectionCounts.frame === 37
                && !manager.isActive && _root.当前为战斗地图 === false,
            "production return ignores HP/restriction/BGM throws and clears after one fade");

        resetWorld(0);
        manager.dispose();
        var retryHero:MovieClip = installHero("success");
        retryHero.hp = 50;
        StageRunSession.begin("生产返回淡出重试", "简单");
        StageRunSession.finish("failure");
        manager.isActive = true;
        manager.isFailed = true;
        manager.currentStage = 0;
        _root.当前为战斗地图 = true;
        _root.玩家信息界面 = undefined;
        _root.soundEffectManager = undefined;
        _root.关卡结束界面 = undefined;
        _root.新出生 = false;
        _root.场景进入位置名 = "原入口";
        _root.关卡类型 = "原类型";
        _root.关卡地图帧值 = "原返回帧";
        var productionFade:Object = {
            calls:0,
            throwNext:true,
            淡出跳转帧:function(frame):Void {
                this.calls++;
                if (this.throwNext) throw new Error("synthetic production fade failure");
            }
        };
        _root.淡出动画 = productionFade;
        _root.返回基地 = productionReturnBase;
        var firstAccepted:Boolean = _root.返回基地();
        assertTrue(!firstAccepted && productionFade.calls == 1
                && manager.isActive && manager.isFailed
                && _root.当前为战斗地图 === true
                && _root.新出生 === false
                && _root.场景进入位置名 == "原入口"
                && _root.关卡类型 == "原类型",
            "production fade throw preserves manager and rolls back all three transition globals");
        productionFade.throwNext = false;
        var secondAccepted:Boolean = _root.返回基地();
        assertTrue(secondAccepted && productionFade.calls == 2
                && !manager.isActive && _root.当前为战斗地图 === false
                && _root.新出生 === true
                && _root.场景进入位置名 == "出生地"
                && _root.关卡类型 == "",
            "second production return retries the frozen run and clears after one accepted fade");

        resetWorld(0);
        manager.dispose();
        StageRunSession.begin("生产通关提交", "困难");
        _root.当前关卡名 = "生产通关提交";
        _root.当前关卡难度 = "困难";
        var effectCalls:Number = 0;
        var finishStageCalls:Number = 0;
        var finishStageName:String = "";
        var finishStageDifficulty:String = "";
        effectClass.ScreenEffect = function():Void {
            effectCalls++;
            throw new Error("synthetic victory effect failure");
        };
        _root.FinishStage = function(stageName:String, difficulty:String):Void {
            finishStageCalls++;
            finishStageName = stageName;
            finishStageDifficulty = difficulty;
        };
        _root.关卡结束 = productionStageFinished;
        var finishEscaped:Boolean = false;
        try {
            _root.关卡结束();
        } catch (finishError) {
            finishEscaped = true;
        }
        assertTrue(!finishEscaped && effectCalls == 1 && finishStageCalls == 1
                && finishStageName == "生产通关提交"
                && finishStageDifficulty == "困难"
                && StageRunSession.testOnlySnapshot().outcome == "victory",
            "production victory effect throw still commits FinishStage exactly once");

        effectClass.ScreenEffect = oldScreenEffect;
        manager.dispose();
        _root.玩家信息界面 = oldPlayerInfo;
        _root.关卡结束界面 = oldOutcomeUi;
        _root.限制系统 = oldRestrictions;
        _root.soundEffectManager = oldSound;
        _root.淡出动画 = oldFade;
        _root.新出生 = oldNewSpawn;
        _root.场景进入位置名 = oldEntry;
        _root.关卡类型 = oldStageType;
        _root.关卡地图帧值 = oldStageFrame;
        _root.FinishStage = oldFinishStage;
        _root.当前关卡名 = oldStageName;
        _root.当前关卡难度 = oldDifficulty;
        _root.返回基地 = oldReturnBase;
        _root.关卡结束 = oldStageFinished;
    }

    private static function testMapNavigationAuthority():Void {
        var oldBase:Array = MapPanelCatalog.BASE_HOTSPOT_IDS;
        var oldGrouped:Object = MapPanelCatalog.GROUPED_HOTSPOT_IDS;
        var oldTargets:Object = MapPanelCatalog.NAVIGATE_TARGETS;
        var oldPages:Object = MapPanelCatalog.HOTSPOT_PAGES;
        var oldProgress:Object = _root.task_chains_progress;
        var oldInfrastructure:Object = _root.基建系统;
        var oldFade:Object = _root.淡出动画;
        var oldOutcome:Object = _root.关卡结束界面;
        var oldEntry:Object = _root.场景进入位置名;

        MapPanelCatalog.BASE_HOTSPOT_IDS = ["test_base"];
        MapPanelCatalog.GROUPED_HOTSPOT_IDS = {
            warlord:["test_locked"], rock:[], blackiron:[], fallen:[],
            defense:[], restricted:[], schoolOutside:[], schoolInside:[]
        };
        MapPanelCatalog.NAVIGATE_TARGETS = {
            test_base:"测试基地帧", test_locked:"伪造锁区帧"
        };
        MapPanelCatalog.HOTSPOT_PAGES = {test_base:"base", test_locked:"faction"};
        _root.task_chains_progress = {主线:0, 大学:0};
        _root.基建系统 = {infrastructure:{}};
        _root.关卡结束界面 = {_visible:1};
        _root.淡出动画 = {
            fadeCount:0,
            淡出跳转帧:function(frameName:String):Void { this.fadeCount++; }
        };
        MapHotspotResolver.reset();

        resetWorld(0);
        assertTrue(StageRunSession.begin("地图门控关卡", "困难"),
            "map authority coverage creates an active run");
        assertFalse(MapPanelService.navigateToHotspot("test_base"),
            "active run rejects even an unlocked forged navigate command");
        assertEquals(0, _root.淡出动画.fadeCount,
            "active navigate rejection occurs before fade side effects");
        StageRunSession.finish("victory");
        assertFalse(MapPanelService.navigateToHotspot("test_base"),
            "victory still rejects map navigation before canonical return");
        assertEquals(0, _root.淡出动画.fadeCount,
            "victory navigate rejection performs no fade");
        StageRunSession.onReturnBaseStarted();
        StageRunSession.onSettlementState("ABANDONED", 0);
        _root.当前为战斗地图 = false;
        assertTrue(MapPanelService.navigateToHotspot("test_base"),
            "terminal returned run permits an unlocked map target");
        assertEquals(1, _root.淡出动画.fadeCount,
            "allowed terminal navigation performs exactly one fade");
        assertFalse(MapPanelService.navigateToHotspot("test_locked"),
            "forged locked hotspot is rejected by the AS2 unlock hard gate");
        assertEquals(1, _root.淡出动画.fadeCount,
            "forged locked hotspot cannot trigger another fade");

        resetWorld(0);
        assertTrue(StageRunSession.begin("地图失败关卡", "困难"),
            "map authority coverage creates a failure run");
        StageRunSession.finish("failure");
        assertFalse(MapPanelService.navigateToHotspot("test_base"),
            "failure still rejects map navigation before canonical return");
        assertEquals(1, _root.淡出动画.fadeCount,
            "failure navigate rejection performs no fade");

        MapHotspotResolver.reset();
        MapPanelCatalog.BASE_HOTSPOT_IDS = oldBase;
        MapPanelCatalog.GROUPED_HOTSPOT_IDS = oldGrouped;
        MapPanelCatalog.NAVIGATE_TARGETS = oldTargets;
        MapPanelCatalog.HOTSPOT_PAGES = oldPages;
        _root.task_chains_progress = oldProgress;
        _root.基建系统 = oldInfrastructure;
        _root.淡出动画 = oldFade;
        _root.关卡结束界面 = oldOutcome;
        _root.场景进入位置名 = oldEntry;
    }

    private static function testStageSelectLifecycleAuthority():Void {
        var oldServer:Object = _root.server;
        var oldStageInfo:Object = _root.StageInfoDict;
        var oldUnlock:Function = _root.isStageUnlocked;
        var oldConfigure:Function = _root.配置关卡属性;
        var oldDifficulty:Function = _root.计算难度等级;
        var oldChallenge:Function = _root.isChallengeMode;
        var oldLoader:Function = _root.载入关卡数据;
        var oldFade:Object = _root.淡出动画;
        var oldStageName:Object = _root.当前关卡名;
        var oldMapFrame:Object = _root.关卡地图帧值;
        var oldRestriction:Object = _root.限制系统;
        var loadCount:Number = 0;
        var responseSink:Object = {
            isSocketConnected:true,
            messages:[],
            sendSocketMessage:function(message:String):Boolean {
                this.messages.push(message);
                return true;
            }
        };

        StageSelectPanelService.install();
        _root.StageInfoDict = {
            测试难度关:{Name:"测试难度关", Type:"无限过图", UnlockCondition:0,
                url:"data/stages/test.xml", FadeTransitionFrame:"wuxianguotu_1"},
            测试外交图:{Name:"测试外交图", Type:"外交地图", UnlockCondition:0,
                RootFadeTransitionFrame:"测试外交帧", Address:"出生地"}
        };
        _root.isStageUnlocked = function(stageName:String):Boolean { return true; };
        _root.isChallengeMode = function():Boolean { return false; };
        _root.计算难度等级 = function(difficulty:String):Number { return 1; };
        _root.配置关卡属性 = function(stageName:String):Void {
            this.关卡路径 = "data/stages/test.xml";
            this.关卡类型 = "无限过图";
            this.当前关卡名 = stageName;
            this.淡出跳转帧 = "wuxianguotu_1";
            this.限制词条 = [];
        };
        _root.载入关卡数据 = function():Void { loadCount++; };
        _root.淡出动画 = {
            fadeCount:0,
            淡出跳转帧:function(frameName:String):Void { this.fadeCount++; }
        };
        _root.当前关卡名 = "原关卡";
        _root.关卡地图帧值 = "原返回帧";

        resetWorld(0);
        _root.server = responseSink;
        assertTrue(StageRunSession.begin("选关活动关", "困难"),
            "stage-select coverage creates an active run");
        StageSelectPanelService.handleReturnFrame({callId:"active-return", returnFrameLabel:"基地门口"});
        assertEquals(0, _root.淡出动画.fadeCount,
            "active run rejects stage-select return before fade");
        StageSelectPanelService.handleEnter({callId:"active-enter", stageName:"测试难度关",
            difficulty:"简单", entryKind:"difficulty"});
        assertEquals(0, loadCount, "active run rejects difficulty entry before stage load");
        assertEquals("原关卡", _root.当前关卡名,
            "active difficulty rejection preserves current stage globals");
        StageSelectPanelService.handleEnter({callId:"active-map", stageName:"测试外交图",
            difficulty:"", entryKind:"map"});
        assertEquals(0, _root.淡出动画.fadeCount,
            "active run rejects stage-select map entry before fade");

        StageRunSession.finish("victory");
        StageSelectPanelService.handleReturnFrame({callId:"victory-return", returnFrameLabel:"基地门口"});
        assertEquals(0, _root.淡出动画.fadeCount,
            "victory rejects stage-select return before canonical return");
        StageSelectPanelService.handleEnter({callId:"victory-enter", stageName:"测试难度关",
            difficulty:"简单", entryKind:"difficulty"});
        assertEquals(0, loadCount, "victory rejects difficulty entry before stage load");
        StageSelectPanelService.handleEnter({callId:"victory-map", stageName:"测试外交图",
            difficulty:"", entryKind:"map"});
        assertEquals(0, _root.淡出动画.fadeCount,
            "victory rejects stage-select map entry before fade");

        resetWorld(0);
        _root.server = responseSink;
        assertTrue(StageRunSession.begin("选关失败关", "困难"),
            "stage-select coverage creates a failure run");
        StageRunSession.finish("failure");
        StageSelectPanelService.handleReturnFrame({callId:"failure-return", returnFrameLabel:"基地门口"});
        assertEquals(0, _root.淡出动画.fadeCount,
            "failure rejects stage-select return before canonical return");
        StageSelectPanelService.handleEnter({callId:"failure-enter", stageName:"测试难度关",
            difficulty:"简单", entryKind:"difficulty"});
        assertEquals(0, loadCount, "failure rejects difficulty entry before stage load");
        StageSelectPanelService.handleEnter({callId:"failure-map", stageName:"测试外交图",
            difficulty:"", entryKind:"map"});
        assertEquals(0, _root.淡出动画.fadeCount,
            "failure rejects stage-select map entry before fade");

        resetWorld(0);
        _root.server = responseSink;
        _root.当前为战斗地图 = false;
        _root.当前关卡名 = "原关卡";
        _root.淡出动画 = {
            fadeCount:0,
            淡出跳转帧:function(frameName:String):Void { this.fadeCount++; }
        };
        loadCount = 0;
        var capturedStartToken:String = "";
        var capturedLoaded:Function;
        var capturedLoadError:Function;
        _root.载入关卡数据 = function(stageType, url, onLoaded, onLoadError,
                stageStartToken):Void {
            loadCount++;
            capturedStartToken = String(stageStartToken || "");
            capturedLoaded = onLoaded;
            capturedLoadError = onLoadError;
        };
        var responseCountBefore:Number = responseSink.messages.length;
        StageSelectPanelService.handleEnter({callId:"vacant-enter", stageName:"测试难度关",
            difficulty:"简单", entryKind:"difficulty"});
        assertEquals(1, loadCount,
            "vacant stage-select entry starts exactly one asynchronous load");
        assertEquals(0, _root.淡出动画.fadeCount,
            "deferred stage-select entry performs no fade before XML success");
        assertTrue(capturedStartToken != "",
            "stage-select passes its exact reservation token into the loader");
        assertEquals("原关卡", _root.当前关卡名,
            "deferred stage-select entry preserves globals before XML success");
        assertEquals(responseCountBefore, responseSink.messages.length,
            "deferred stage-select entry sends no premature success response");
        capturedLoaded({});
        assertEquals(1, _root.淡出动画.fadeCount,
            "XML success performs exactly one stage-select fade");
        assertEquals("测试难度关", _root.当前关卡名,
            "XML success commits the selected stage globals");
        assertEquals(responseCountBefore + 1, responseSink.messages.length,
            "XML success sends exactly one stage-select response");
        var stageSelectSuccessWire:String =
            String(responseSink.messages[responseSink.messages.length - 1]);
        assertTrue(stageSelectSuccessWire.indexOf("\"callId\":\"vacant-enter\"") >= 0,
            "deferred stage-select success preserves the exact wire callId");
        assertTrue(stageSelectSuccessWire.indexOf("\"stageName\":\"测试难度关\"") >= 0
                && stageSelectSuccessWire.indexOf("\"difficulty\":\"简单\"") >= 0
                && stageSelectSuccessWire.indexOf("\"entryKind\":\"difficulty\"") >= 0,
            "deferred stage-select success preserves its complete correlation envelope");
        capturedLoaded({});
        capturedLoadError();
        assertEquals(1, _root.淡出动画.fadeCount,
            "duplicate stage loader callbacks cannot repeat the fade");
        assertEquals(responseCountBefore + 1, responseSink.messages.length,
            "duplicate stage loader callbacks cannot repeat the response");
        assertFalse(StageRunSession.canStartStage(),
            "stage-select reservation stays held until first gameplay init");
        assertTrue(StageRunSession.begin("测试难度关", "简单", capturedStartToken),
            "first gameplay init consumes the exact stage-select reservation");

        resetWorld(0);
        _root.当前为战斗地图 = false;
        _root.当前关卡名 = "回包异常前原关卡";
        _root.淡出动画 = {
            fadeCount:0,
            淡出跳转帧:function(frameName:String):Void { this.fadeCount++; }
        };
        var responseThrowCount:Number = 0;
        _root.server = {
            sendSocketMessage:function(message:String):Boolean {
                responseThrowCount++;
                throw new Error("injected stage-select response failure");
                return false;
            }
        };
        capturedStartToken = "";
        capturedLoaded = undefined;
        capturedLoadError = undefined;
        _root.载入关卡数据 = function(stageType, url, onLoaded, onLoadError,
                stageStartToken):Void {
            capturedStartToken = String(stageStartToken || "");
            capturedLoaded = onLoaded;
            capturedLoadError = onLoadError;
        };
        StageSelectPanelService.handleEnter({callId:"response-throw", stageName:"测试难度关",
            difficulty:"简单", entryKind:"difficulty"});
        var responseEscaped:Boolean = false;
        try {
            capturedLoaded({});
        } catch (responseFailure) {
            responseEscaped = true;
        }
        assertFalse(responseEscaped,
            "committed stage-select response failure cannot escape the loader callback");
        assertTrue(responseThrowCount == 1 && _root.淡出动画.fadeCount == 1,
            "response failure happens after exactly one committed fade");
        assertTrue(capturedStartToken != ""
                && StageRunSession.isStageStartReservationValid(capturedStartToken),
            "post-commit response failure preserves the exact reservation");
        assertTrue(StageRunSession.begin("测试难度关", "简单", capturedStartToken),
            "gameplay init still consumes the reservation after response transport failure");

        resetWorld(0);
        _root.server = responseSink;
        _root.当前为战斗地图 = false;
        _root.当前关卡名 = "错误前原关卡";
        _root.淡出动画 = {
            fadeCount:0,
            淡出跳转帧:function(frameName:String):Void { this.fadeCount++; }
        };
        capturedLoaded = undefined;
        capturedLoadError = undefined;
        _root.载入关卡数据 = function(stageType, url, onLoaded, onLoadError,
                stageStartToken):Void {
            capturedLoaded = onLoaded;
            capturedLoadError = onLoadError;
        };
        responseCountBefore = responseSink.messages.length;
        StageSelectPanelService.handleEnter({callId:"deferred-error", stageName:"测试难度关",
            difficulty:"简单", entryKind:"difficulty"});
        capturedLoadError();
        capturedLoadError();
        capturedLoaded({});
        assertEquals(0, _root.淡出动画.fadeCount,
            "deferred stage-select error and late success perform no fade");
        assertEquals("错误前原关卡", _root.当前关卡名,
            "deferred stage-select error preserves stage globals");
        assertEquals(responseCountBefore + 1, responseSink.messages.length,
            "deferred stage-select error responds exactly once");
        var stageSelectErrorWire:String =
            String(responseSink.messages[responseSink.messages.length - 1]);
        assertTrue(stageSelectErrorWire.indexOf("\"callId\":\"deferred-error\"") >= 0
                && stageSelectErrorWire.indexOf("\"error\":\"stage_load_failed\"") >= 0,
            "deferred stage-select error preserves exact callId and error on the wire");
        assertTrue(StageRunSession.canStartStage(),
            "deferred stage-select error exact-cancels its reservation");

        _root.StageInfoDict.测试难度关.Name = "";
        loadCount = 0;
        _root.载入关卡数据 = function():Void { loadCount++; };
        StageSelectPanelService.handleEnter({callId:"empty-name", stageName:"测试难度关",
            difficulty:"简单", entryKind:"difficulty"});
        assertEquals(0, loadCount,
            "empty authoritative StageInfo.Name fails before loader start");
        assertTrue(StageRunSession.canStartStage(),
            "empty authoritative StageInfo.Name creates no reservation leak");
        _root.StageInfoDict.测试难度关.Name = "测试难度关";

        resetWorld(0);
        _root.server = responseSink;
        _root.当前为战斗地图 = false;
        _root.当前关卡名 = "原关卡";
        _root.淡出动画 = {fadeCount:0};
        loadCount = 0;
        assertTrue(StageRunSession.canStartStage(),
            "transition failure coverage begins with vacant admission");
        StageSelectPanelService.handleEnter({callId:"missing-fade", stageName:"测试难度关",
            difficulty:"简单", entryKind:"difficulty"});
        assertEquals(0, loadCount,
            "missing fade fails preflight before stage loading");
        assertEquals("原关卡", _root.当前关卡名,
            "missing fade fails before current-stage mutation");
        assertTrue(StageRunSession.canStartStage(),
            "failed stage-select preflight exact-cancels its reservation");

        resetWorld(0);
        _root.server = responseSink;
        _root.当前为战斗地图 = false;
        _root.当前通关的关卡 = "原通关值";
        _root.当前关卡难度 = "原难度";
        _root.难度等级 = 77;
        _root.当前关卡名 = "淡出异常前关卡";
        _root.场景进入位置名 = "原入口";
        _root.关卡类型 = "原类型";
        _root.关卡地图帧值 = "原地图帧";
        var originalRestrictionEntries:Object = {ExistingLimit:true};
        _root.限制系统 = {
            entries:originalRestrictionEntries,
            limitLevel:7,
            openEntries:function(entries:Array):Void {
                for (var entryIndex:Number = 0; entryIndex < entries.length; entryIndex++) {
                    this.entries[entries[entryIndex]] = true;
                }
            },
            addLimitLevel:function(value):Void { this.limitLevel = value; }
        };
        _root.配置关卡属性 = function(stageName:String):Void {
            this.关卡路径 = "data/stages/test.xml";
            this.关卡类型 = "无限过图";
            this.当前关卡名 = stageName;
            this.淡出跳转帧 = "wuxianguotu_1";
            this.起点帧 = "新地图帧";
            this.限制词条 = ["InjectedLimit"];
            this.限制难度等级 = 9;
        };
        _root.淡出动画 = {淡出跳转帧:function(frameName:String):Void {
            throw new Error("synthetic stage-select fade failure");
        }};
        capturedLoaded = undefined;
        _root.载入关卡数据 = function(stageType, url, onLoaded):Void {
            capturedLoaded = onLoaded;
        };
        responseCountBefore = responseSink.messages.length;
        StageSelectPanelService.handleEnter({callId:"fade-throw", stageName:"测试难度关",
            difficulty:"简单", entryKind:"difficulty"});
        var stageSelectManagerBefore:Object = StageManager.instance;
        var throwingStageSelectManager:Object = {
            abortCalls:0,
            abortPreparedStage:function(token:String):Boolean {
                this.abortCalls++;
                throw new Error("synthetic stage-select abort failure");
                return false;
            }
        };
        StageManager["instance"] = throwingStageSelectManager;
        capturedLoaded({});
        StageManager["instance"] = stageSelectManagerBefore;
        var fadeFailureWire:String =
            String(responseSink.messages[responseSink.messages.length - 1]);
        assertTrue(responseSink.messages.length == responseCountBefore + 1
                && throwingStageSelectManager.abortCalls == 1
                && fadeFailureWire.indexOf("\"callId\":\"fade-throw\"") >= 0
                && fadeFailureWire.indexOf("\"error\":\"stage_transition_failed\"") >= 0,
            "stage-select fade failure preserves exact correlation and failure wire");
        assertTrue(_root.当前通关的关卡 == "原通关值"
                && _root.当前关卡难度 == "原难度" && _root.难度等级 == 77
                && _root.当前关卡名 == "淡出异常前关卡"
                && _root.场景进入位置名 == "原入口"
                && _root.关卡类型 == "原类型" && _root.关卡地图帧值 == "原地图帧",
            "stage-select fade failure restores every transition global");
        assertTrue(_root.限制系统.entries === originalRestrictionEntries
                && _root.限制系统.entries.ExistingLimit === true
                && _root.限制系统.entries.InjectedLimit !== true
                && _root.限制系统.limitLevel == 7
                && StageRunSession.canStartStage(),
            "stage-select fade failure restores restrictions and exact-cancels admission");

        _root.server = oldServer;
        _root.StageInfoDict = oldStageInfo;
        _root.isStageUnlocked = oldUnlock;
        _root.配置关卡属性 = oldConfigure;
        _root.计算难度等级 = oldDifficulty;
        _root.isChallengeMode = oldChallenge;
        _root.载入关卡数据 = oldLoader;
        _root.淡出动画 = oldFade;
        _root.当前关卡名 = oldStageName;
        _root.关卡地图帧值 = oldMapFrame;
        _root.限制系统 = oldRestriction;
    }

    private static function testTaskDeferredEntryAuthority():Void {
        // 真实入口由 install 初始化 LiteJSON。旧测试未安装服务，sendResponse(undefined)
        // 仍会让 message count 增长，因而掩盖了整条 wire 实际为 undefined 的问题。
        TaskPanelService.install();
        var oldTasks:Object = TaskUtil.tasks;
        var oldStageInfo:Object = _root.StageInfoDict;
        var oldTodo:Object = _root.tasks_to_do;
        var oldFinished:Object = _root.tasks_finished;
        var oldLoader:Object = _root.载入关卡数据;
        var oldDifficulty:Object = _root.计算难度等级;
        var oldArrayConfig:Object = _root.配置数据为数组;
        var oldFade:Object = _root.淡出动画;
        var oldSound:Object = _root.soundEffectManager;
        var oldAddTask:Object = _root.AddTask;
        var oldCurrencyUi:Object = _root.获取虚拟币值;
        var oldDialogue:Object = _root.对话框界面;
        var oldServer:Object = _root.server;
        var oldRestriction:Object = _root.限制系统;
        var responseSink:Object = {
            isSocketConnected:true,
            messages:[],
            sendSocketMessage:function(message:String):Boolean {
                this.messages.push(message);
                return true;
            }
        };
        var dispatchTask:Object = {
            id:8101,
            dispatch_board:"focused_board",
            finish_requirements:["延迟任务关#简单"]
        };
        var dungeonTask:Object = {
            id:8102,
            chain:"委托",
            finish_requirements:["延迟任务关#简单"],
            deposit:25,
            Kdeposit:5,
            restricted_level:1
        };
        TaskUtil.tasks = {};
        TaskUtil.tasks[8101] = dispatchTask;
        TaskUtil.tasks[8102] = dungeonTask;
        _root.StageInfoDict = {
            延迟任务关:{
                Name:"延迟任务关", Type:"无限过图",
                url:"data/stages/task-deferred.xml",
                FadeTransitionFrame:"wuxianguotu_1"
            }
        };
        _root.计算难度等级 = function(value:String):Number { return 1; };
        _root.配置数据为数组 = function(value):Array {
            if (value instanceof Array) return value;
            return value == undefined || value == null ? [] : [value];
        };
        _root.soundEffectManager = {stopBGMForTransition:function():Void {}};
        _root.对话框界面 = {_visible:true};
        _root.获取虚拟币值 = function():Void {};

        resetWorld(0);
        _root.当前为战斗地图 = false;
        _root.server = responseSink;
        _root.tasks_to_do = [{id:8101}];
        _root.tasks_finished = {};
        _root.计算难度等级 = function(value:String):Number { return 1; };
        _root.配置数据为数组 = function(value):Array {
            if (value instanceof Array) return value;
            return value == undefined || value == null ? [] : [value];
        };
        _root.soundEffectManager = {stopBGMForTransition:function():Void {}};
        _root.对话框界面 = {_visible:true};
        _root.淡出动画 = {
            fadeCount:0,
            淡出跳转帧:function(frameName:String):Void { this.fadeCount++; }
        };
        var capturedLoaded:Function;
        var capturedError:Function;
        var capturedToken:String = "";
        _root.载入关卡数据 = function(stageType, url, onLoaded, onLoadError,
                stageStartToken):Void {
            capturedLoaded = onLoaded;
            capturedError = onLoadError;
            capturedToken = String(stageStartToken || "");
        };
        var responseBefore:Number = responseSink.messages.length;
        TaskPanelService.handleDispatchBoardEnter({
            callId:"dispatch-success", boardId:"focused_board", taskId:8101
        });
        assertEquals(0, _root.淡出动画.fadeCount,
            "dispatch load performs no fade before deferred XML success");
        assertEquals(responseBefore, responseSink.messages.length,
            "dispatch load sends no premature success response");
        capturedLoaded({});
        assertEquals(1, _root.淡出动画.fadeCount,
            "dispatch XML success performs exactly one fade");
        var dispatchSuccessWire:String =
            String(responseSink.messages[responseSink.messages.length - 1]);
        assertTrue(responseSink.messages.length == responseBefore + 1
                && dispatchSuccessWire.indexOf('"callId":"dispatch-success"') >= 0
                && dispatchSuccessWire.indexOf('"taskId":8101') >= 0
                && dispatchSuccessWire.indexOf('"stageName":"延迟任务关"') >= 0
                && dispatchSuccessWire.indexOf('"difficulty":"简单"') >= 0,
            "dispatch XML success preserves exact callId and authoritative fields in its raw response");
        capturedLoaded({});
        capturedError();
        assertEquals(1, _root.淡出动画.fadeCount,
            "dispatch duplicate callbacks cannot repeat transition");
        assertEquals(responseBefore + 1, responseSink.messages.length,
            "dispatch duplicate callbacks cannot repeat response");
        assertTrue(StageRunSession.cancelStageStart(capturedToken),
            "dispatch success preserves token until gameplay init");

        StageRunSession.testOnlyReset();
        _root.当前为战斗地图 = false;
        _root.当前关卡名 = "响应异常前";
        _root.淡出动画 = {
            fadeCount:0,
            淡出跳转帧:function(frameName:String):Void { this.fadeCount++; }
        };
        var throwingServer:Object = {
            isSocketConnected:true,
            sendSocketMessage:function(message:String):Boolean {
                throw new Error("response transport failure");
                return false;
            }
        };
        _root.server = throwingServer;
        capturedLoaded = undefined;
        capturedToken = "";
        TaskPanelService.handleDispatchBoardEnter({
            callId:"dispatch-response-throw", boardId:"focused_board", taskId:8101
        });
        var responseEscaped:Boolean = false;
        try { capturedLoaded({}); }
        catch (responseThrow) { responseEscaped = true; }
        assertFalse(responseEscaped,
            "post-fade dispatch response exception does not escape or cancel commit");
        assertEquals(1, _root.淡出动画.fadeCount,
            "dispatch response exception happens after the successful fade");
        assertTrue(StageRunSession.isStageStartReservationValid(capturedToken),
            "dispatch response exception preserves gameplay reservation");
        StageRunSession.cancelStageStart(capturedToken);

        StageRunSession.testOnlyReset();
        _root.当前为战斗地图 = false;
        _root.server = responseSink;
        _root.tasks_to_do = [];
        _root.金钱 = 100;
        _root.虚拟币 = 50;
        _root.等级 = 10;
        _root.存档系统.dirtyMark = false;
        _root.AddTask = function(taskId):Void {
            _root.tasks_to_do.push({id:taskId});
        };
        _root.淡出动画 = {
            fadeCount:0,
            淡出跳转帧:function(frameName:String):Void { this.fadeCount++; }
        };
        capturedLoaded = undefined;
        capturedError = undefined;
        responseBefore = responseSink.messages.length;
        TaskPanelService.handleDungeonEnter({
            callId:"dungeon-error", taskId:8102, mode:"normal"
        });
        assertTrue(_root.金钱 == 100 && _root.虚拟币 == 50
                && _root.tasks_to_do.length == 0
                && _root.淡出动画.fadeCount == 0,
            "dungeon deferred load has zero asset/task/transition writes before callback");
        capturedError();
        capturedError();
        capturedLoaded({});
        assertTrue(_root.金钱 == 100 && _root.虚拟币 == 50
                && _root.tasks_to_do.length == 0
                && _root.淡出动画.fadeCount == 0,
            "dungeon load error and late success keep zero asset/task/transition writes");
        var dungeonFailureWire:String =
            String(responseSink.messages[responseSink.messages.length - 1]);
        assertTrue(responseSink.messages.length == responseBefore + 1
                && dungeonFailureWire.indexOf('"callId":"dungeon-error"') >= 0
                && dungeonFailureWire.indexOf('"success":false') >= 0
                && dungeonFailureWire.indexOf('"error":"stage_load_failed"') >= 0,
            "dungeon load error preserves exact callId and error in its raw response");
        assertTrue(StageRunSession.canStartStage(),
            "dungeon load error exact-cancels reservation");

        StageRunSession.testOnlyReset();
        _root.当前为战斗地图 = false;
        responseBefore = responseSink.messages.length;
        capturedLoaded = undefined;
        TaskPanelService.handleDungeonEnter({
            callId:"dungeon-success", taskId:8102, mode:"normal"
        });
        capturedLoaded({});
        assertTrue(_root.金钱 == 75 && _root.虚拟币 == 45
                && _root.tasks_to_do.length == 1
                && _root.tasks_to_do[0].id == 8102,
            "dungeon success commits task and both currencies before completing transition");
        assertEquals(1, _root.淡出动画.fadeCount,
            "dungeon success performs one fade after commit");
        var dungeonSuccessWire:String =
            String(responseSink.messages[responseSink.messages.length - 1]);
        assertTrue(responseSink.messages.length == responseBefore + 1
                && dungeonSuccessWire.indexOf('"callId":"dungeon-success"') >= 0
                && dungeonSuccessWire.indexOf('"entered":true') >= 0
                && dungeonSuccessWire.indexOf('"mode":"normal"') >= 0,
            "dungeon success preserves exact callId and mode in its raw post-fade response");
        capturedLoaded({});
        assertTrue(_root.金钱 == 75 && _root.虚拟币 == 45
                && _root.tasks_to_do.length == 1,
            "dungeon duplicate success cannot double-charge or duplicate AddTask");
        StageRunSession.testOnlyReset();

        _root.当前为战斗地图 = false;
        _root.tasks_to_do = [];
        _root.金钱 = 100;
        _root.虚拟币 = 50;
        _root.存档系统.dirtyMark = false;
        _root.淡出动画.fadeCount = 0;
        _root.AddTask = function(taskId):Void {
            throw new Error("AddTask commit failure");
        };
        responseBefore = responseSink.messages.length;
        TaskPanelService.handleDungeonEnter({
            callId:"dungeon-commit-throw", taskId:8102, mode:"normal"
        });
        capturedLoaded({});
        assertTrue(_root.金钱 == 100 && _root.虚拟币 == 50
                && _root.tasks_to_do.length == 0
                && _root.淡出动画.fadeCount == 0,
            "dungeon commit exception rolls back before fade and charges nothing");
        assertEquals(responseBefore + 1, responseSink.messages.length,
            "dungeon commit exception emits one failure response");
        assertTrue(StageRunSession.canStartStage(),
            "dungeon commit exception exact-cancels its reservation");

        StageRunSession.testOnlyReset();
        _root.当前为战斗地图 = false;
        _root.AddTask = function(taskId):Void {
            _root.tasks_to_do.push({id:taskId});
        };
        _root.淡出动画 = {
            fadeCount:0,
            淡出跳转帧:function(frameName:String):Void {
                throw new Error("fade failure");
            }
        };
        _root.当前通关的关卡 = "任务前通关";
        _root.当前关卡难度 = "任务前难度";
        _root.难度等级 = 42;
        _root.当前关卡名 = "任务前关卡";
        _root.场景进入位置名 = "任务前入口";
        _root.关卡类型 = "任务前类型";
        _root.关卡地图帧值 = "任务前地图帧";
        var taskRestrictionEntries:Object = {ExistingTaskLimit:true};
        _root.限制系统 = {
            entries:taskRestrictionEntries,
            limitLevel:6,
            openEntries:function(entries:Array):Void {
                for (var entryIndex:Number = 0; entryIndex < entries.length; entryIndex++) {
                    this.entries[entries[entryIndex]] = true;
                }
            },
            addLimitLevel:function(value):Void { this.limitLevel = value; }
        };
        _root.StageInfoDict.延迟任务关.Limitation = ["InjectedTaskLimit"];
        _root.StageInfoDict.延迟任务关.LimitLevel = 8;
        _root.StageInfoDict.延迟任务关.StartFrame = "任务新地图帧";
        _root.对话框界面._visible = true;
        responseBefore = responseSink.messages.length;
        TaskPanelService.handleDungeonEnter({
            callId:"dungeon-fade-throw", taskId:8102, mode:"normal"
        });
        var taskManagerBefore:Object = StageManager.instance;
        var throwingTaskManager:Object = {
            abortCalls:0,
            abortPreparedStage:function(token:String):Boolean {
                this.abortCalls++;
                throw new Error("synthetic task abort failure");
                return false;
            }
        };
        StageManager["instance"] = throwingTaskManager;
        capturedLoaded({});
        StageManager["instance"] = taskManagerBefore;
        assertTrue(_root.金钱 == 100 && _root.虚拟币 == 50
                && _root.tasks_to_do.length == 0,
            "dungeon transition exception rolls back committed task and currencies");
        assertTrue(_root.当前通关的关卡 == "任务前通关"
                && _root.当前关卡难度 == "任务前难度" && _root.难度等级 == 42
                && _root.当前关卡名 == "任务前关卡"
                && _root.场景进入位置名 == "任务前入口"
                && _root.关卡类型 == "任务前类型"
                && _root.关卡地图帧值 == "任务前地图帧"
                && _root.限制系统.entries === taskRestrictionEntries
                && _root.限制系统.entries.ExistingTaskLimit === true
                && _root.限制系统.entries.InjectedTaskLimit !== true
                && _root.限制系统.limitLevel == 6
                && _root.对话框界面._visible === true,
            "dungeon fade failure restores transition globals, restrictions, and dialogue");
        assertTrue(responseSink.messages.length == responseBefore + 1
                && throwingTaskManager.abortCalls == 1,
            "dungeon transition exception emits one failure response");
        assertTrue(StageRunSession.canStartStage(),
            "dungeon transition exception aborts prepared preload and reservation");

        TaskUtil.tasks = oldTasks;
        _root.StageInfoDict = oldStageInfo;
        _root.tasks_to_do = oldTodo;
        _root.tasks_finished = oldFinished;
        _root.载入关卡数据 = oldLoader;
        _root.计算难度等级 = oldDifficulty;
        _root.配置数据为数组 = oldArrayConfig;
        _root.淡出动画 = oldFade;
        _root.soundEffectManager = oldSound;
        _root.AddTask = oldAddTask;
        _root.获取虚拟币值 = oldCurrencyUi;
        _root.对话框界面 = oldDialogue;
        _root.server = oldServer;
        _root.限制系统 = oldRestriction;
    }

    private static function testArenaDeferredLoadAuthority():Void {
        var oldStageInfo:Object = _root.StageInfoDict;
        var oldLoader:Object = _root.载入关卡数据;
        var oldDifficulty:Object = _root.计算难度等级;
        var oldType:Object = _root.关卡类型;
        var oldPath:Object = _root.关卡路径;
        var oldDeposit:Object = _root.押金;
        var oldReward:Object = _root.角斗场奖金;
        var oldFade:Object = _root.淡出动画;
        var oldUnitLoader:Object = _root.加载游戏世界人物;
        var oldSharedLoader:Object = _root.加载共享场景;
        var oldTroops:Object = _root.兵种库;
        var oldServer:Object = _root.server;
        var oldCalibrationMode:Object = _root.斗兽标定模式;
        var oldCalibrationNoSave:Object = _root.斗兽标定禁存档;
        var oldAgentCalibrationNoSave:Object = _root._agentCalibrationNoSave;
        var oldClearedStage:Object = _root.当前通关的关卡;
        var oldCurrentStageName:Object = _root.当前关卡名;
        var oldInfiniteMode:Object = _root.无限过图模式;
        var oldSceneEntry:Object = _root.场景进入位置名;
        var oldOpponentType:Object = _root.角斗场对手类型;
        var oldRoster:Object = _root.角斗场roster阵容;
        var oldEnemyCompanions:Object = _root.敌人同伴数;
        var oldEnemyTotal:Object = _root.敌人总数;
        var oldSceneTransition:Object = _root.场景转换函数;
        var oldFrameTimer:Object = _root.帧计时器;
        var oldLineup:Object = _root.出阵人员;
        var oldLineupCache:Object = _root._arenaLineupCache;
        var oldReuseCount:Object = _root.当前佣兵重用数;
        var oldReuseLimit:Object = _root.竞技场佣兵重用基数;
        var oldArenaEntering:Object = _root.角斗场入场中;
        var oldPublishing:Object = _root.发布请求;
        var oldSound:Object = _root.soundEffectManager;

        resetWorld(0);
        _root.当前为战斗地图 = false;
        _root.StageInfoDict = {};
        _root.StageInfoDict["DEATH MATCH角斗场"] = {
            Name:"DEATH MATCH角斗场", Type:"无限过图",
            url:"data/stages/arena-deferred.xml"
        };
        _root.计算难度等级 = function(value:String):Number { return 2; };
        _root.关卡类型 = "旧类型";
        _root.关卡路径 = "旧路径";
        _root.押金 = 7;
        _root.角斗场奖金 = 9;
        var capturedLoaded:Function;
        var capturedError:Function;
        var capturedToken:String = "";
        _root.载入关卡数据 = function(stageType, url, onLoaded, onLoadError,
                stageStartToken):Void {
            capturedLoaded = onLoaded;
            capturedError = onLoadError;
            capturedToken = String(stageStartToken || "");
        };
        var readyCount:Number = 0;
        var errorCount:Number = 0;
        assertTrue(ArenaController.prepareArenaStage(100, 200, "困难",
            function():Void { readyCount++; },
            function():Void { errorCount++; }),
            "arena starts one deferred stage load with an exact reservation");
        assertTrue(capturedToken != ""
                && _root.关卡类型 == "旧类型" && _root.押金 == 7,
            "arena deferred load writes no context before XML success");
        capturedError();
        capturedError();
        capturedLoaded({});
        assertTrue(errorCount == 1 && readyCount == 0,
            "arena error and late success terminate exactly once");
        assertTrue(_root.关卡类型 == "旧类型" && _root.关卡路径 == "旧路径"
                && _root.押金 == 7 && _root.角斗场奖金 == 9,
            "arena late load error preserves all arena transition context");
        assertTrue(StageRunSession.canStartStage(),
            "arena late error exact-cancels its reservation");

        capturedLoaded = undefined;
        capturedError = undefined;
        readyCount = 0;
        errorCount = 0;
        assertTrue(ArenaController.prepareArenaStage(100, 200, "困难",
            function():Void { readyCount++; },
            function():Void { errorCount++; }),
            "arena can reserve again after a failed deferred load");
        capturedLoaded({});
        capturedLoaded({});
        capturedError();
        assertTrue(readyCount == 1 && errorCount == 0,
            "arena deferred success ignores duplicate and late error callbacks");
        assertTrue(_root.关卡类型 == "旧类型" && _root.押金 == 7,
            "arena loader success alone still does not commit context");
        assertTrue(ArenaController.applyPreparedArenaContext(100, 200, "困难"),
            "arena final commit explicitly applies prepared context");
        assertTrue(_root.关卡类型 == "无限过图"
                && _root.关卡路径 == "data/stages/arena-deferred.xml"
                && _root.押金 == 100 && _root.角斗场奖金 == 200,
            "arena prepared context uses frozen authoritative values");
        assertTrue(ArenaController.cancelPendingStageStart(),
            "arena prepared success remains exact-cancellable before gameplay init");

        var lateErrorCount:Number = 0;
        assertTrue(ArenaController.prepareArenaStage(10, 20, "简单",
            function():Void {},
            function(expectedToken:String):Void {
                lateErrorCount++;
                ArenaController.cancelPendingStageStart(expectedToken);
            }),
            "arena race coverage reserves request A");
        var lateErrorA:Function = capturedError;
        var tokenA:String = capturedToken;
        assertTrue(ArenaController.cancelPendingStageStart(tokenA),
            "external close exact-cancels arena request A");
        assertTrue(ArenaController.prepareArenaStage(30, 40, "困难",
            function():Void {}, function():Void {}),
            "arena race coverage reserves request B after A closes");
        var tokenB:String = capturedToken;
        lateErrorA();
        assertTrue(lateErrorCount == 1
                && StageRunSession.isStageStartReservationValid(tokenB),
            "late A loader error and service cleanup cannot cancel request B");
        assertTrue(ArenaController.cancelPendingStageStart(tokenB),
            "request B remains exactly cancellable by its own token");

        StageRunSession.testOnlyReset();
        _root.当前为战斗地图 = false;
        _root.斗兽标定模式 = false;
        _root.金钱 = 1000;
        _root.当前佣兵重用数 = 0;
        _root.竞技场佣兵重用基数 = 10;
        _root.角斗场入场中 = false;
        _root.发布请求 = false;
        _root._arenaLineupCache = [];
        _root.soundEffectManager = undefined;
        _root.淡出动画 = {
            fadeCount:0,
            淡出跳转帧:function(frameName:String):Void { this.fadeCount++; }
        };
        var arenaResponses:Object = {
            messages:[],
            sendSocketMessage:function(message:String):Boolean {
                this.messages.push(message);
                return true;
            }
        };
        _root.server = arenaResponses;
        ArenaPanelService.install();
        var arenaEnterParams:Function = function(callId:String):Object {
            return {
                callId:callId,
                authorityId:"focused-standard",
                authorityMode:"standard",
                authoritySourceDigest:"0123456789ABCDEF",
                levelMin:1,
                levelMax:1,
                opponentCount:1,
                economyMultiplier:1,
                benchLevel:1,
                expr:"#0@1-1%1",
                reward:1000,
                deposit:500,
                difficulty:"简单"
            };
        };
        _root.出阵人员 = [["frozen-lineup", 1]];
        capturedLoaded = undefined;
        capturedError = undefined;
        capturedToken = "";
        _root.载入关卡数据 = function(stageType, url, onLoaded, onLoadError,
                stageStartToken):Void {
            capturedLoaded = onLoaded;
            capturedError = onLoadError;
            capturedToken = String(stageStartToken || "");
        };
        var responseBefore:Number = arenaResponses.messages.length;
        ArenaPanelService.handleEnter(arenaEnterParams("arena-success-wire"));
        capturedLoaded({});
        var arenaSuccessWire:String = String(arenaResponses.messages[responseBefore]);
        assertTrue(arenaResponses.messages.length == responseBefore + 1
                && arenaSuccessWire.indexOf("\"callId\":\"arena-success-wire\"") >= 0
                && arenaSuccessWire.indexOf("\"success\":true") >= 0
                && arenaSuccessWire.indexOf("\"closePanel\":true") >= 0
                && arenaSuccessWire.indexOf("\"deposit\":500") >= 0
                && arenaSuccessWire.indexOf("\"reward\":1000") >= 0
                && arenaSuccessWire.indexOf("\"expr\":\"#0@1-1%1\"") >= 0,
            "arena deferred success preserves exact callId and authority in its raw post-fade response");
        ArenaController.cancelPendingStageStart(capturedToken);
        _root.角斗场入场中 = false;
        _root.金钱 = 1000;
        _root.当前佣兵重用数 = 0;
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = false;
        _root.淡出动画.fadeCount = 0;

        responseBefore = arenaResponses.messages.length;
        ArenaPanelService.handleEnter(arenaEnterParams("arena-lineup-cleared"));
        _root.出阵人员 = [];
        capturedLoaded({});
        assertTrue(_root.金钱 == 1000 && _root.淡出动画.fadeCount == 0
                && _root.当前佣兵重用数 == 0 && _root.角斗场入场中 == false,
            "arena pending lineup clear fails before charge, reuse mutation, or fade");
        assertTrue(StageRunSession.canStartStage()
                && arenaResponses.messages.length == responseBefore + 1
                && String(arenaResponses.messages[responseBefore]).indexOf("\"success\":false") >= 0,
            "arena lineup-clear failure exact-cancels and never reports success");
        var arenaFailureWire:String = String(arenaResponses.messages[responseBefore]);
        assertTrue(arenaFailureWire.indexOf("\"callId\":\"arena-lineup-cleared\"") >= 0
                && arenaFailureWire.indexOf("\"success\":false") >= 0
                && arenaFailureWire.indexOf("\"error\":\"stage_state_changed\"") >= 0,
            "arena deferred failure preserves exact callId and error in its raw response");

        _root.出阵人员 = [["frozen-lineup", 2]];
        responseBefore = arenaResponses.messages.length;
        ArenaPanelService.handleEnter(arenaEnterParams("arena-lineup-replaced"));
        _root.出阵人员 = [["replacement-lineup", 2]];
        capturedLoaded({});
        assertTrue(_root.金钱 == 1000 && _root.淡出动画.fadeCount == 0
                && _root.当前佣兵重用数 == 0 && _root.角斗场入场中 == false,
            "arena pending lineup replacement fails before authoritative writes");
        assertTrue(StageRunSession.canStartStage()
                && arenaResponses.messages.length == responseBefore + 1
                && String(arenaResponses.messages[responseBefore]).indexOf("\"success\":false") >= 0,
            "arena lineup-replacement failure releases reservation without false success");
        _root.出阵人员 = [];
        assertFalse(ArenaController.commitArena(),
            "empty merc commit returns false instead of a silent no-op");
        assertFalse(ArenaController.commitRoster([]),
            "empty roster commit returns false instead of a silent no-op");
        assertFalse(ArenaController.commitEscalation("", [], 1, 1, 1, 0, 0, 1),
            "empty escalation commit returns false instead of a silent no-op");

        _root.server = {
            isSocketConnected:true,
            sendSocketMessage:function(message:String):Boolean { return true; }
        };
        ArenaCalibrationService.install();
        assertTrue(ArenaController.prepareArenaStage(0, 0, "",
            function():Void {}, function():Void {}, true),
            "calibration abort coverage owns a pending reservation");
        ArenaCalibrationService.testOnlySetPendingRun({
            callId:"calibration-abort-old", batchId:"batch-abort"
        });
        ArenaCalibrationService.handleAbort({
            callId:"calibration-abort", batchId:"batch-abort"
        });
        var afterAbortToken:String = StageRunSession.reserveStageStart(
            "after_calibration_abort", "abort 后关卡", "简单");
        assertTrue(afterAbortToken != "",
            "calibration pending abort releases admission for a new reservation");
        StageRunSession.cancelStageStart(afterAbortToken);

        assertTrue(ArenaController.prepareArenaStage(0, 0, "",
            function():Void {}, function():Void {}, true),
            "calibration supersede coverage owns the old pending reservation");
        ArenaCalibrationService.testOnlySetPendingRun({
            callId:"calibration-superseded", batchId:"batch-old"
        });
        ArenaCalibrationService.handleRun({
            callId:"calibration-new", batchId:"batch-new",
            blueRoster:[], redRoster:[]
        });
        var afterSupersedeToken:String = StageRunSession.reserveStageStart(
            "after_calibration_supersede", "supersede 后关卡", "简单");
        assertTrue(afterSupersedeToken != "",
            "calibration pending supersede releases admission for the replacement run");
        StageRunSession.cancelStageStart(afterSupersedeToken);

        ArenaCalibrationService.testOnlySetPendingRun(undefined);
        _root.当前为战斗地图 = false;
        _root.斗兽标定模式 = false;
        _root.加载游戏世界人物 = function():Void {};
        _root.加载共享场景 = function():Void {};
        _root.兵种库 = {标定测试兵:{兵种名:"标定测试兵"}};
        var calibrationRoster:Array = [{兵种:"标定测试兵", 等级:1}];
        _root.淡出动画 = {
            fadeCount:0,
            淡出跳转帧:function(frameName:String):Void { this.fadeCount++; }
        };
        var calibrationLoads:Array = [];
        _root.载入关卡数据 = function(stageType, url, onLoaded, onLoadError,
                stageStartToken):Void {
            calibrationLoads.push({
                loaded:onLoaded,
                error:onLoadError,
                token:String(stageStartToken || "")
            });
        };
        ArenaCalibrationService.handleRun({
            callId:"calibration-race-error-a", batchId:"race-error-a",
            blueRoster:calibrationRoster, redRoster:calibrationRoster
        });
        var calibrationTokenA:String = String(calibrationLoads[0].token || "");
        ArenaCalibrationService.handleRun({
            callId:"calibration-race-error-b", batchId:"race-error-b",
            blueRoster:calibrationRoster, redRoster:calibrationRoster
        });
        assertEquals(2, calibrationLoads.length,
            "calibration supersede starts one exact replacement load");
        var calibrationTokenB:String = String(calibrationLoads[1].token || "");
        ArenaCalibrationService.onCalibrationStageInitializationFailed(
            calibrationTokenA);
        assertTrue(calibrationTokenA != "" && calibrationTokenB != ""
                && StageRunSession.isStageStartReservationValid(calibrationTokenB)
                && _root.淡出动画.fadeCount == 0,
            "late calibration A initialization failure preserves pending owner B");
        calibrationLoads[0].error();
        assertTrue(calibrationTokenB != ""
                && StageRunSession.isStageStartReservationValid(calibrationTokenB)
                && _root.淡出动画.fadeCount == 0,
            "late calibration A error preserves pending B and performs no stale fade");
        calibrationLoads[1].loaded({});
        assertTrue(_root.淡出动画.fadeCount == 1
                && StageRunSession.isStageStartReservationValid(calibrationTokenB),
            "calibration B success alone commits exactly its own pending fade");
        ArenaCalibrationService.handleAbort({
            callId:"calibration-race-abort-b", batchId:"race-error-b"
        });
        assertTrue(StageRunSession.isStageStartReservationValid(calibrationTokenB)
                && _root.淡出动画.fadeCount == 1,
            "abort after calibration fade commit is rejected without dismantling B");
        ArenaCalibrationService.handleRun({
            callId:"calibration-race-supersede-c", batchId:"race-error-c",
            blueRoster:calibrationRoster, redRoster:calibrationRoster
        });
        assertTrue(calibrationLoads.length == 2
                && StageRunSession.isStageStartReservationValid(calibrationTokenB)
                && _root.淡出动画.fadeCount == 1,
            "supersede after calibration fade commit is rejected without preparing C");
        ArenaController.cancelPendingStageStart(calibrationTokenB);
        ArenaCalibrationService.testOnlySetPendingRun(undefined);
        _root.斗兽标定模式 = false;
        _root.斗兽标定禁存档 = false;
        _root._agentCalibrationNoSave = false;
        assertTrue(StageRunSession.canStartStage(),
            "focused calibration committed-transition cleanup leaves no reservation leak");

        calibrationLoads = [];
        _root.淡出动画.fadeCount = 0;
        ArenaCalibrationService.handleRun({
            callId:"calibration-race-success-a", batchId:"race-success-a",
            blueRoster:calibrationRoster, redRoster:calibrationRoster
        });
        ArenaCalibrationService.handleRun({
            callId:"calibration-race-success-b", batchId:"race-success-b",
            blueRoster:calibrationRoster, redRoster:calibrationRoster
        });
        var calibrationSuccessTokenB:String = String(calibrationLoads[1].token || "");
        calibrationLoads[0].loaded({});
        assertTrue(calibrationSuccessTokenB != ""
                && StageRunSession.isStageStartReservationValid(calibrationSuccessTokenB)
                && _root.淡出动画.fadeCount == 0,
            "late calibration A success cannot complete or clear pending B");
        calibrationLoads[1].loaded({});
        assertTrue(_root.淡出动画.fadeCount == 1
                && StageRunSession.isStageStartReservationValid(calibrationSuccessTokenB),
            "B still completes after stale A success is ignored");
        ArenaController.cancelPendingStageStart(calibrationSuccessTokenB);
        ArenaCalibrationService.testOnlySetPendingRun(undefined);
        _root.斗兽标定模式 = false;
        _root.斗兽标定禁存档 = false;
        _root._agentCalibrationNoSave = false;
        assertTrue(StageRunSession.canStartStage(),
            "late-success calibration sequence leaves no reservation leak after exact cleanup");

        calibrationLoads = [];
        var fadeRollbackRoster:Array = [{sentinel:"原阵容"}];
        _root.斗兽标定模式 = false;
        _root.斗兽标定禁存档 = false;
        _root._agentCalibrationNoSave = false;
        _root.当前通关的关卡 = "原通关关卡";
        _root.当前关卡名 = "原当前关卡";
        _root.关卡类型 = "原关卡类型";
        _root.无限过图模式 = true;
        _root.场景进入位置名 = "原场景入口";
        _root.角斗场对手类型 = "roster";
        _root.角斗场roster阵容 = fadeRollbackRoster;
        _root.押金 = 321;
        _root.角斗场奖金 = 654;
        _root.敌人同伴数 = 7;
        _root.敌人总数 = 8;
        _root.场景转换函数 = {上次切换帧数:77};
        _root.帧计时器 = {当前帧数:999};
        _root.soundEffectManager = undefined;
        var calibrationFade:Object = {
            calls:0,
            fadeCount:0,
            throwNext:true,
            淡出跳转帧:function(frameName:String):Void {
                this.calls++;
                this.fadeCount++;
                if (this.throwNext) throw new Error("synthetic calibration fade failure");
            }
        };
        _root.淡出动画 = calibrationFade;
        ArenaCalibrationService.handleRun({
            callId:"calibration-fade-fail-a", batchId:"fade-fail-a",
            blueRoster:calibrationRoster, redRoster:calibrationRoster
        });
        var failedCalibrationLoad:Object = calibrationLoads[0];
        var failedCalibrationToken:String = String(failedCalibrationLoad.token || "");
        failedCalibrationLoad.loaded({});
        assertTrue(calibrationFade.calls == 1 && StageRunSession.canStartStage()
                && !StageRunSession.isStageStartReservationValid(failedCalibrationToken)
                && _root.斗兽标定模式 === false
                && _root.斗兽标定禁存档 === false
                && _root._agentCalibrationNoSave === false
                && _root.当前通关的关卡 == "原通关关卡"
                && _root.当前关卡名 == "原当前关卡"
                && _root.关卡类型 == "原关卡类型"
                && _root.无限过图模式 === true
                && _root.场景进入位置名 == "原场景入口"
                && _root.角斗场对手类型 == "roster"
                && _root.角斗场roster阵容 === fadeRollbackRoster
                && _root.押金 == 321 && _root.角斗场奖金 == 654
                && _root.敌人同伴数 == 7 && _root.敌人总数 == 8
                && _root.场景转换函数.上次切换帧数 == 77,
            "calibration fade throw exact-releases A and restores every transition global");

        calibrationFade.throwNext = false;
        ArenaCalibrationService.handleRun({
            callId:"calibration-fade-retry-b", batchId:"fade-retry-b",
            blueRoster:calibrationRoster, redRoster:calibrationRoster
        });
        var fadeRetryTokenB:String = calibrationLoads.length > 1
            ? String(calibrationLoads[1].token || "") : "";
        assertTrue(calibrationLoads.length == 2 && fadeRetryTokenB != ""
                && StageRunSession.isStageStartReservationValid(fadeRetryTokenB),
            "calibration fade failure allows a new exact pending reservation");
        failedCalibrationLoad.loaded({});
        failedCalibrationLoad.error();
        assertTrue(StageRunSession.isStageStartReservationValid(fadeRetryTokenB)
                && calibrationFade.calls == 1
                && _root.当前关卡名 == "原当前关卡"
                && _root.关卡类型 == "原关卡类型"
                && _root.押金 == 321 && _root.角斗场奖金 == 654,
            "late callbacks from fade-failed A cannot mutate or cancel pending B");
        ArenaCalibrationService.handleAbort({
            callId:"calibration-fade-retry-abort", batchId:"fade-retry-b"
        });
        assertTrue(StageRunSession.canStartStage(),
            "replacement B remains exactly abortable after A fade failure");

        calibrationLoads = [];
        _root.淡出动画.fadeCount = 0;
        var throwingCalibrationResponses:Object = {
            throwsRemaining:1,
            sent:0,
            sendSocketMessage:function(message:String):Boolean {
                this.sent++;
                if (this.throwsRemaining > 0) {
                    this.throwsRemaining--;
                    throw new Error("synthetic calibration response failure");
                }
                return true;
            }
        };
        _root.server = throwingCalibrationResponses;
        ArenaCalibrationService.handleRun({
            callId:"calibration-response-throw-a", batchId:"response-throw-a",
            blueRoster:calibrationRoster, redRoster:calibrationRoster
        });
        ArenaCalibrationService.handleRun({
            callId:"calibration-response-throw-b", batchId:"response-throw-b",
            blueRoster:calibrationRoster, redRoster:calibrationRoster
        });
        var responseThrowTokenB:String = calibrationLoads.length > 1
            ? String(calibrationLoads[1].token || "") : "";
        assertTrue(calibrationLoads.length == 2 && responseThrowTokenB != ""
                && StageRunSession.isStageStartReservationValid(responseThrowTokenB),
            "throwing A supersede response still clears A and prepares exact B");
        calibrationLoads[0].error();
        calibrationLoads[0].loaded({});
        assertTrue(StageRunSession.isStageStartReservationValid(responseThrowTokenB)
                && _root.淡出动画.fadeCount == 0,
            "late A callbacks after response throw cannot consume or transition B");
        calibrationLoads[1].error();
        assertTrue(StageRunSession.canStartStage(),
            "B failure after throwing A response exact-releases the replacement reservation");

        _root.StageInfoDict = oldStageInfo;
        _root.载入关卡数据 = oldLoader;
        _root.计算难度等级 = oldDifficulty;
        _root.关卡类型 = oldType;
        _root.关卡路径 = oldPath;
        _root.押金 = oldDeposit;
        _root.角斗场奖金 = oldReward;
        _root.淡出动画 = oldFade;
        _root.加载游戏世界人物 = oldUnitLoader;
        _root.加载共享场景 = oldSharedLoader;
        _root.兵种库 = oldTroops;
        _root.server = oldServer;
        _root.斗兽标定模式 = oldCalibrationMode;
        _root.斗兽标定禁存档 = oldCalibrationNoSave;
        _root._agentCalibrationNoSave = oldAgentCalibrationNoSave;
        _root.当前通关的关卡 = oldClearedStage;
        _root.当前关卡名 = oldCurrentStageName;
        _root.无限过图模式 = oldInfiniteMode;
        _root.场景进入位置名 = oldSceneEntry;
        _root.角斗场对手类型 = oldOpponentType;
        _root.角斗场roster阵容 = oldRoster;
        _root.敌人同伴数 = oldEnemyCompanions;
        _root.敌人总数 = oldEnemyTotal;
        _root.场景转换函数 = oldSceneTransition;
        _root.帧计时器 = oldFrameTimer;
        _root.出阵人员 = oldLineup;
        _root._arenaLineupCache = oldLineupCache;
        _root.当前佣兵重用数 = oldReuseCount;
        _root.竞技场佣兵重用基数 = oldReuseLimit;
        _root.角斗场入场中 = oldArenaEntering;
        _root.发布请求 = oldPublishing;
        _root.soundEffectManager = oldSound;
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

    private static function testSettlementRewardInformationCapFilter():Void {
        var intel:String = "StageRunSession测试情报";
        addMeta(intel, "收集品", "情报");
        ItemUtil.informationMaxValueDict[intel] = 1;

        resetWorld(0);
        _root.收集品栏.情报.add(intel, 1);
        _root.关卡可获得奖励品 = [[intel, 1, 1], [REWARD, 1, 1]];
        assertTrue(StageRunSession.begin("结算情报上限", "简单"),
            "settlement intel-cap stage run begins");
        StageRunSession.finish("victory");
        assertTrue(StageRunSession.onReturnBaseStarted(),
            "victory return prepares the settlement");
        var state:Object = StageRunSession.testOnlySnapshot();
        assertEquals(1, state.inventory.size(),
            "capped story intel is not materialized into the settlement box");
        assertEquals(1, state.remainingRewards,
            "remaining rewards only count actually generated items");
        assertEquals(1, state.report.rewardRollOmissions,
            "the capped intel roll is counted as an omission");

        resetWorld(0);
        _root.关卡可获得奖励品 = [[intel, 1, 1], [REWARD, 1, 1]];
        assertTrue(StageRunSession.begin("结算情报放行", "简单"),
            "settlement intel-accept stage run begins");
        StageRunSession.finish("victory");
        assertTrue(StageRunSession.onReturnBaseStarted(),
            "victory return prepares the second settlement");
        state = StageRunSession.testOnlySnapshot();
        assertEquals(2, state.inventory.size(),
            "uncapped intel is materialized alongside the other reward");
        assertEquals(2, state.remainingRewards,
            "both rewards remain claimable");
    }

    private static function testZeroRewardOfflineSettlementSurvivesSceneExpiry():Void {
        resetWorld(0);
        _root.关卡可获得奖励品 = [];
        assertTrue(StageRunSession.begin("零奖励失败结算", "简单"),
            "zero-reward production splice begins a real stage run");
        StageRunSession.finish("failure");
        assertTrue(StageRunSession.onReturnBaseStarted(),
            "zero-reward failure enters the canonical return lifecycle");
        _root.当前为战斗地图 = false;
        StageRunSession.onSceneReady();

        var state:Object = StageRunSession.testOnlySnapshot();
        var report:Object = state.report;
        assertEquals("rewards_pending", state.settlement,
            "offline zero-reward open remains explicitly resumable");
        assertEquals(0, state.remainingRewards,
            "offline zero-reward settlement reports exact zero remaining");
        assertTrue(report != null && report.outcome == "failure"
                && report.stageName == "零奖励失败结算",
            "offline zero-reward settlement retains the exact failure report");
        assertTrue(LootContainerService.hasStageSettlementPending(),
            "zero-reward stage settlement still owns pending Loot authority");

        var expiry:Object = LootContainerService.expireScene("scene_cleanup");
        assertEquals("LOOT_SUSPENDED", expiry.state,
            "scene expiry preserves zero-reward stage settlement as SUSPENDED");
        state = StageRunSession.testOnlySnapshot();
        assertTrue(state.report === report,
            "scene expiry preserves the same zero-reward report object");
        assertEquals("rewards_pending", state.settlement,
            "scene expiry does not terminalize the zero-reward report");
        assertTrue(LootContainerService.hasStageSettlementPending(),
            "scene expiry leaves zero-reward Loot authority recoverable");
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

    private static function testPreparedSettlementPersistsWithoutReroll():Void {
        resetWorld(0);
        _root.关卡可获得奖励品 = [[REWARD, 1, 1]];
        assertTrue(StageRunSession.begin("持久化冻结", "困难"),
            "persistent settlement begins from an ordinary stage run");
        StageRunSession.finish("victory");
        assertTrue(StageRunSession.prepareSettlement(),
            "prepare writes the frozen settlement into save ext");
        var state:Object = StageRunSession.testOnlySnapshot();
        var inventory:Object = state.inventory;
        var store:Object = _root._saveExt.stageSettlement;
        var settlementId:String = String(store.pending.settlementId);
        assertTrue(store.v == 1 && store.nextSeq == 2
                && settlementId == "stage.settlement.1",
            "first persisted settlement receives a stable monotonic identity");
        assertTrue(store.pending.manifest.length == 1
                && store.pending.remainingManifest.length == 1
                && store.pending.report.outcome == "victory",
            "pending record freezes manifest, remaining inventory, and report");
        assertTrue(_root.存档系统.dirtyMark === true,
            "ext persistence marks the save dirty without pretending it was flushed");

        _root.关卡可获得奖励品 = [];
        assertTrue(StageRunSession.prepareSettlement(),
            "repeated prepare reuses the already materialized settlement");
        state = StageRunSession.testOnlySnapshot();
        store = _root._saveExt.stageSettlement;
        assertTrue(state.inventory === inventory && state.inventory.size() == 1,
            "prepare retry never rerolls or replaces the reward inventory");
        assertTrue(String(store.pending.settlementId) == settlementId
                && store.nextSeq == 2 && store.pending.manifest.length == 1,
            "prepare retry reuses the same id and immutable manifest");
    }

    private static function testReturnRequiresDurableSettlementFlush():Void {
        resetWorld(0);
        _root.关卡可获得奖励品 = [[REWARD, 1, 1]];
        _root.__stageRunSessionTestFlushCalls = 0;
        _root.强制存盘 = function():Boolean {
            _root.__stageRunSessionTestFlushCalls++;
            return _root.__stageRunSessionTestFlushCalls >= 2;
        };
        assertTrue(StageRunSession.begin("持久化退场门", "困难"),
            "durable return fixture begins from an ordinary stage run");
        StageRunSession.finish("victory");
        assertFalse(StageRunSession.onReturnBaseStarted(),
            "return is denied when the first durable save reports false");
        var first:Object = StageRunSession.testOnlySnapshot();
        var inventory:Object = first.inventory;
        var settlementId:String = String(first.settlementId);
        assertTrue(first.returnRequested === false && inventory != null
                && inventory.size() == 1
                && _root._saveExt.stageSettlement.pending.settlementId == settlementId,
            "failed flush preserves the exact prepared and pending settlement before transition");

        _root.关卡可获得奖励品 = [];
        assertTrue(StageRunSession.onReturnBaseStarted(),
            "same return request succeeds after the durable save retry reports true");
        var second:Object = StageRunSession.testOnlySnapshot();
        assertTrue(_root.__stageRunSessionTestFlushCalls == 2
                && second.returnRequested === true
                && second.inventory === inventory
                && String(second.settlementId) == settlementId
                && second.inventory.size() == 1,
            "durable retry reuses one settlement id and reward object without rerolling");
        delete _root.__stageRunSessionTestFlushCalls;
    }

    private static function testPersistedSettlementProgressAndRestartRestore():Void {
        resetWorld(0);
        _root.关卡可获得奖励品 = [[REWARD, 1, 1], [REWARD, 1, 1]];
        StageRunSession.begin("重启恢复", "挑战");
        StageRunSession.finish("victory");
        assertTrue(StageRunSession.prepareSettlement(),
            "restart fixture persists two exact reward slots");
        var state:Object = StageRunSession.testOnlySnapshot();
        var settlementId:String = String(state.settlementId);
        var remaining:ArrayInventory = state.inventory;
        remaining.remove(0);
        var receipt:Object = {
            kind:"claim", fingerprint:"loot_to_player|bag|slot.0",
            authorityRevision:3
        };
        var progress:Object = StageRunSession.recordSettlementProgress(
            settlementId, "claim.restart.1", remaining, receipt);
        assertTrue(progress.success === true && progress.duplicate === false
                && progress.remainingCount == 1,
            "claim progress stores exact remaining inventory and first receipt");
        var duplicate:Object = StageRunSession.recordSettlementProgress(
            settlementId, "claim.restart.1", remaining, receipt);
        assertTrue(duplicate.success === true && duplicate.duplicate === true,
            "same operation id and result is an idempotent persistence success");
        var stagnant:Object = StageRunSession.recordSettlementProgress(
            settlementId, "claim.restart.stagnant", remaining, {
                kind:"claim", fingerprint:"loot_to_player|bag|slot.1",
                authorityRevision:4
            });
        assertEquals("invalid_remaining_inventory", stagnant.error,
            "a new claim receipt cannot persist without removing exactly one current reward");
        var persistedReceipt:Object = StageRunSession.getPersistedSettlementReceipt(
            settlementId, "claim.restart.1");
        var allReceipts:Object = StageRunSession.getPersistedSettlementReceipts(settlementId);
        assertTrue(persistedReceipt.success === true && persistedReceipt.found === true
                && persistedReceipt.receipt.authorityRevision == 3
                && persistedReceipt.receipt.remainingCount == 1
                && allReceipts.success === true && allReceipts.receipts.length == 1
                && allReceipts.originalCount == 2 && allReceipts.remainingCount == 1
                && allReceipts.receipts[0].operationId == "claim.restart.1",
            "persisted receipt can seed claim idempotency after process restart");

        remaining.remove(1);
        var conflict:Object = StageRunSession.recordSettlementProgress(
            settlementId, "claim.restart.1", remaining, receipt);
        assertEquals("operation_conflict", conflict.error,
            "same operation id cannot be rebound to a different remaining manifest");

        StageRunSession.resetForRestart();
        var restored:Object = StageRunSession.restorePendingSettlement();
        state = StageRunSession.testOnlySnapshot();
        assertTrue(restored.success === true && restored.restored === true
                && restored.remainingCount == 1 && restored.receiptCount == 1,
            "restart restores one exact pending reward and its receipt journal");
        assertTrue(state.inventory.size() == 1 && state.inventory.getItem(0) == null
                && state.inventory.getItem(1).name == REWARD,
            "remaining manifest rebuilds BaseItem objects at their original physical slots");
        assertTrue(state.report.outcome == "victory" && state.outcome == "victory"
                && state.settlement == "rewards_pending"
                && state.returnRequested === true,
            "restart restores report/run authority as a resumable base settlement");
        assertFalse(StageRunSession.canStartStage(),
            "restored pending settlement blocks a new stage overwrite");
        var secondRestore:Object = StageRunSession.restorePendingSettlement();
        assertTrue(secondRestore.success === true && secondRestore.duplicate === true,
            "duplicate restore preserves the existing in-memory authority");
    }

    private static function testPersistedSettlementVersionsFailClosed():Void {
        resetWorld(0);
        var future:Object = {v:2, nextSeq:1, pending:{future:true}};
        _root._saveExt.stageSettlement = future;
        var restored:Object = StageRunSession.restorePendingSettlement();
        assertEquals("future_settlement_store_version", restored.error,
            "future settlement schema fails closed under an older runtime");
        assertTrue(StageRunSession.hasPersistedSettlementPending(),
            "unknown future settlement authority remains an admission blocker");
        assertFalse(StageRunSession.begin("禁止覆盖未来档", "简单"),
            "future pending schema cannot be overwritten by a new run");
        assertTrue(_root._saveExt.stageSettlement === future,
            "future store is preserved byte-structure-wise instead of downgraded");

        StageRunSession.testOnlyReset();
        var malformed:Object = {v:1, nextSeq:1, pending:{v:1}};
        _root._saveExt.stageSettlement = malformed;
        restored = StageRunSession.restorePendingSettlement();
        assertEquals("malformed_persisted_settlement", restored.error,
            "malformed current-version pending record fails closed");
        assertTrue(StageRunSession.hasPersistedSettlementPending(),
            "malformed pending record still blocks destructive overwrite");
        assertFalse(StageRunSession.begin("禁止覆盖畸形档", "简单"),
            "malformed pending record closes stage admission");
        assertTrue(_root._saveExt.stageSettlement === malformed,
            "malformed store remains untouched for diagnosis and recovery");
    }

    private static function testStageSettlementEmptyArrayShapeRepair():Void {
        resetWorld(0);
        // 复刻 AMF0 现场：0 击杀/0 物品流向的撤退 + 空奖励池，五个数组字段全被
        // 磨成空对象 {} 落盘（manifest/remainingManifest/receipts + kills/itemFlows）。
        var mydata:Object = makeShapeRepairMydata();
        mydata.ext.stageSettlement = {v:1, nextSeq:2, pending:{
            v:1, settlementId:"stage.settlement.1", runId:"run.amf0.empty.arrays",
            runRevision:1, state:"prepared", outcome:"retreat", life:"alive",
            capacity:8,
            report:{v:1, runId:"run.amf0.empty.arrays", stageName:"空奖励撤退关",
                difficulty:"简单", outcome:"retreat", activeFrames:0, totalKills:0,
                omittedKillTypes:0, totalItemGains:0, totalItemLosses:0,
                omittedItemFlowTypes:0, rewardRollOmissions:0,
                kills:{}, itemFlows:{}},
            manifest:{}, remainingManifest:{}, remainingCount:0,
            receipts:{}, deliverAfterSettlement:false}};
        var changed:Boolean = SaveManager.getInstance().migrate(mydata, {});
        var repaired:Object = mydata.ext.stageSettlement.pending;
        assertTrue(changed === true
                && repaired.manifest instanceof Array
                && repaired.remainingManifest instanceof Array
                && repaired.receipts instanceof Array
                && repaired.report.kills instanceof Array
                && repaired.report.itemFlows instanceof Array,
            "migrate 把结算持久态五个被磨成空对象的数组字段修复回 []");
        assertTrue(repaired.manifest.length == 0 && repaired.receipts.length == 0
                && repaired.report.kills.length == 0
                && repaired.report.itemFlows.length == 0,
            "形状修复只换容器，不捏造任何结算内容");

        // 修复后的持久态在生产读档路径上可解码、可恢复、可正常收敛。
        _root._saveExt.stageSettlement = mydata.ext.stageSettlement;
        var restored:Object = StageRunSession.restorePendingSettlement();
        assertTrue(restored.success === true && restored.restored === true
                && restored.remainingCount == 0 && restored.receiptCount == 0,
            "修复后的零奖励结算在重启恢复路径上成功 decode 并恢复");
        StageRunSession.onSettlementState("CONSUMED", 0);
        var store:Object = _root._saveExt.stageSettlement;
        assertTrue(store.pending == null
                && store.lastTerminal.settlementId == "stage.settlement.1"
                && store.lastTerminal.terminalState == "claimed",
            "恢复后的零奖励结算可写入终态 marker 并释放 pending");
        assertTrue(StageRunSession.begin("修复后开新关", "简单"),
            "终态收敛后新关卡准入恢复，软锁解除");

        // 带键非数组是真损坏：migrate 不得吞掉，decode 侧继续 fail closed。
        StageRunSession.testOnlyReset();
        var corrupt:Object = makeShapeRepairMydata();
        corrupt.ext.stageSettlement = {v:1, nextSeq:2, pending:{
            v:1, settlementId:"stage.settlement.1", runId:"run.amf0.corrupt",
            runRevision:1, state:"prepared", outcome:"retreat", life:"alive",
            capacity:8,
            report:{v:1, runId:"run.amf0.corrupt", stageName:"真损坏关",
                difficulty:"简单", outcome:"retreat", activeFrames:0, totalKills:0,
                omittedKillTypes:0, totalItemGains:0, totalItemLosses:0,
                omittedItemFlowTypes:0, rewardRollOmissions:0,
                kills:{ghost:1}, itemFlows:{}},
            manifest:{slot:0}, remainingManifest:{}, remainingCount:0,
            receipts:{}, deliverAfterSettlement:false}};
        SaveManager.getInstance().migrate(corrupt, {});
        var corruptPending:Object = corrupt.ext.stageSettlement.pending;
        assertTrue(!(corruptPending.manifest instanceof Array)
                && corruptPending.manifest.slot == 0
                && !(corruptPending.report.kills instanceof Array)
                && corruptPending.report.kills.ghost == 1,
            "带键非数组不被形状修复吞掉，原文保留供诊断");
        _root._saveExt.stageSettlement = corrupt.ext.stageSettlement;
        var corruptRestore:Object = StageRunSession.restorePendingSettlement();
        assertEquals("malformed_persisted_settlement", corruptRestore.error,
            "真损坏结算仍 fail closed 并报畸形");
        assertTrue(StageRunSession.hasPersistedSettlementPending()
                && !StageRunSession.canStartStage(),
            "真损坏结算继续阻止新关卡覆盖，保留诊断现场");
        SaveManager.getInstance().clearPendingDrugLoadoutMigration();
        SaveManager.getInstance().clearPendingRewardInboxMigration();
    }

    private static function testTaskAndPetEmptyArrayShapeRepair():Void {
        resetWorld(0);
        // AMF0 现场：无进行中任务、五个宠物槽全空 → tasks_to_do 与内层槽
        // 全部被磨成空对象 {} 落盘。
        var mydata:Object = makeShapeRepairMydata();
        mydata.tasks.tasks_to_do = {};
        mydata.pets.宠物信息 = [{}, {}, {}, {}, {}];
        var soData:Object = {};
        var changed:Boolean = SaveManager.getInstance().migrate(mydata, soData);
        assertTrue(changed === true
                && mydata.tasks.tasks_to_do instanceof Array
                && mydata.tasks.tasks_to_do.length == 0,
            "migrate 把被磨成空对象的 tasks_to_do 修复回空数组");
        var info:Object = mydata.pets.宠物信息;
        var slotsOk:Boolean = info instanceof Array && info.length == 5;
        for (var i:Number = 0; i < 5; i++) {
            if (!(info[i] instanceof Array) || info[i].length != 0) slotsOk = false;
        }
        assertTrue(slotsOk,
            "migrate 把宠物信息五个被磨成空对象的内层空槽修复回 []");
        // 修复后的形状经受得住消费方操作：push/splice 与空槽判定不再静默失败。
        mydata.tasks.tasks_to_do.push({id:"shape.repair.task"});
        mydata.tasks.tasks_to_do.splice(0, 1);
        assertTrue(mydata.tasks.tasks_to_do.length == 0,
            "修复后的 tasks_to_do 上 push/splice 正常生效");
        var emptyCount:Number = 0;
        for (var s:Number = 0; s < info.length; s++) {
            if (info[s] == undefined || info[s].length == 0) emptyCount++;
        }
        assertEquals(5, emptyCount,
            "修复后的宠物内层槽按 length==0 全部判为空槽");
        // SOL 通道生产流程：migrate 变更经 syncTopLevelFromMydata 同步到顶层 key。
        SaveManager.getInstance().syncTopLevelFromMydata(mydata, soData);
        assertTrue(soData.tasks_to_do instanceof Array
                && soData.战宠 instanceof Array && soData.战宠[0] instanceof Array,
            "修复结果经 syncTopLevelFromMydata 同步到顶层 tasks_to_do / 战宠");
        // 既有任务与带键占用槽不被修复触碰。
        var occupied:Object = makeShapeRepairMydata();
        occupied.tasks.tasks_to_do = [{id:"keep.me"}];
        occupied.pets.宠物信息 = [["战宠甲"], {}, ["战宠乙"], {}, {}];
        SaveManager.getInstance().migrate(occupied, {});
        assertTrue(occupied.tasks.tasks_to_do.length == 1
                && occupied.tasks.tasks_to_do[0].id == "keep.me"
                && occupied.pets.宠物信息[0][0] == "战宠甲"
                && occupied.pets.宠物信息[2][0] == "战宠乙"
                && occupied.pets.宠物信息[1] instanceof Array
                && occupied.pets.宠物信息[1].length == 0,
            "占用槽与既有任务原样保留，仅空槽 {} 被修复");
        SaveManager.getInstance().clearPendingDrugLoadoutMigration();
        SaveManager.getInstance().clearPendingRewardInboxMigration();
    }

    private static function testPersistedSettlementTerminalCleanup():Void {
        resetWorld(0);
        _root.关卡可获得奖励品 = [[REWARD, 1, 1]];
        StageRunSession.begin("终态清理一", "简单");
        StageRunSession.finish("victory");
        StageRunSession.onReturnBaseStarted();
        var settlementId:String = String(StageRunSession.testOnlySnapshot().settlementId);
        var cleared:Object = StageRunSession.clearPersistedSettlement(
            settlementId, "claimed", {
                operationId:"close.terminal.1", kind:"close",
                fingerprint:"close|consume", authorityRevision:5
            });
        var store:Object = _root._saveExt.stageSettlement;
        assertTrue(cleared.success === true && cleared.duplicate === false,
            "terminal persistence clears pending with an explicit success result");
        assertTrue(store.pending == null && store.lastTerminal.settlementId == settlementId
                && store.lastTerminal.terminalState == "claimed"
                && store.lastTerminal.receipt.operationId == "close.terminal.1",
            "terminal marker preserves the last exact receipt without retaining rewards");
        var duplicate:Object = StageRunSession.clearPersistedSettlement(
            settlementId, "claimed", null);
        assertTrue(duplicate.success === true && duplicate.duplicate === true,
            "repeated terminal cleanup is idempotent after pending removal");
        var conflict:Object = StageRunSession.clearPersistedSettlement(
            settlementId, "abandoned", null);
        assertFalse(conflict.success,
            "a cleared settlement cannot be relabeled with a conflicting terminal state");

        StageRunSession.onSettlementState("CONSUMED", 0);
        assertTrue(StageRunSession.begin("终态清理二", "简单"),
            "terminal in-memory and persisted cleanup reopen stage admission");
        StageRunSession.finish("victory");
        assertTrue(StageRunSession.prepareSettlement(),
            "next stage can persist a new settlement after terminal cleanup");
        assertEquals("stage.settlement.2",
            StageRunSession.testOnlySnapshot().settlementId,
            "terminal cleanup retains the monotonic sequence for the next settlement");
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

    private static function testSoftlockObservationOwnerIsReadOnly():Void {
        resetWorld(0);
        var oldTransition = _root.场景转换中;
        var oldCalibration = _root.斗兽标定模式;
        _root.场景转换中 = false;
        _root.斗兽标定模式 = false;
        _root.当前为战斗地图 = false;
        assertEquals("base_scene", StageRunSession.getObservationOwner(),
            "O1 scene owner names the idle base without mutation");
        _root.场景转换中 = true;
        assertEquals("scene_transition", StageRunSession.getObservationOwner(),
            "O1 scene owner names the existing transition wait");
        _root.场景转换中 = false;
        _root.当前为战斗地图 = true;
        assertEquals("legacy_battle_map", StageRunSession.getObservationOwner(),
            "O1 scene owner names the legacy battle owner");
        _root.当前为战斗地图 = false;
        _root.斗兽标定模式 = true;
        assertEquals("arena_calibration", StageRunSession.getObservationOwner(),
            "O1 scene owner names the calibration owner");
        _root.斗兽标定模式 = false;
        assertTrue(StageRunSession.begin("O1只读场景", "简单"),
            "O1 observation fixture can establish a normal stage owner");
        var before:Object = StageRunSession.testOnlySnapshot();
        assertEquals("stage_run", StageRunSession.getObservationOwner(),
            "O1 scene owner names an active StageRunSession");
        var after:Object = StageRunSession.testOnlySnapshot();
        assertTrue(before.revision === after.revision
                && before.runId === after.runId
                && before.outcome === after.outcome,
            "reading the O1 scene owner leaves the exact run unchanged");
        var oldPause = _root.暂停;
        org.flashNight.arki.pause.PauseManager.install();
        org.flashNight.arki.pause.PauseManager.set(false, "o1-test");
        assertEquals("none",
            org.flashNight.arki.pause.PauseManager.getObservationOwner(),
            "O1 pause owner names an unpaused runtime");
        var observationLease:String =
            org.flashNight.arki.pause.PauseManager.lease(true, "webpanel");
        assertEquals("webpanel",
            org.flashNight.arki.pause.PauseManager.getObservationOwner(),
            "O1 pause owner names the existing Web panel lease without its id");
        var pauseBeforeRead:Boolean = _root.暂停 === true;
        org.flashNight.arki.pause.PauseManager.getObservationOwner();
        assertTrue(pauseBeforeRead === (_root.暂停 === true),
            "reading the O1 pause owner leaves pause state unchanged");
        org.flashNight.arki.pause.PauseManager.releaseLease(observationLease);
        _root.暂停 = oldPause;
        StageRunSession.testOnlyReset();
        _root.场景转换中 = oldTransition;
        _root.斗兽标定模式 = oldCalibration;
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

    /** AMF0 形状修复夹具：最小但完整的 3.0 mydata（drug/reward 归一化所需字段齐备）。 */
    private static function makeShapeRepairMydata():Object {
        var md:Object = {};
        md.version = "3.0";
        md.lastSaved = "2026-09-03 00:00:00";
        md[0] = ["形状修复角色", "男", 1000, 10, 500, 170, 5, "无", 10000, 0, [], 0, [], ""];
        md[3] = 0;
        md.inventory = {背包:[], 装备栏:{}, 药剂栏:{}, 仓库:[], 战备箱:[]};
        md.collection = {材料:{}, 情报:{}};
        md.infrastructure = {};
        md.tasks = {tasks_to_do:[], tasks_finished:{}, task_chains_progress:{}};
        md.pets = {宠物信息:[[], [], [], [], []], 宠物领养限制:5};
        md.shop = {商城已购买物品:[], 商城购物车:[]};
        md.ext = {};
        return md;
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
        _root._saveExt = {};
        _root.强制存盘 = function():Boolean { return true; };
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
        _root.当前为战斗地图 = false;
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
            saveExt:_root._saveExt,
            forceSave:_root.强制存盘,
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
            stageFinished:_root.关卡结束,
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
        _root._saveExt = _backup.saveExt;
        _root.强制存盘 = _backup.forceSave;
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
        _root.关卡结束 = _backup.stageFinished;
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
