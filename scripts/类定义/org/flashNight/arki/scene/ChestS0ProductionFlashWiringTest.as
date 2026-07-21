import org.flashNight.arki.unit.UnitComponent.Initializer.test.*;
import org.flashNight.arki.scene.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.*;
import org.flashNight.neur.Event.*;

/**
 * S0 F01-F04 生产 Flash 接线 smoke。
 *
 * 与 P01-P04 模型不同，本套件必须经过 LifecycleEventDispatcher 的真实
 * interactionKeyDown、BoxInteractionArbiter、InteractionHandler、
 * KillEventComponent、SceneManager.removeGameWorld 与根资源箱回调 include。
 * 它仍不代替真实 XFL 时间轴的人工视觉验收。
 */
class org.flashNight.arki.scene.ChestS0ProductionFlashWiringTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var _caseCount:Number = 0;

    private static var _oldWorld:Object;
    private static var _oldServer:Object;
    private static var _oldSceneWorld:MovieClip;
    private static var _oldInventoryDrop:Function;
    private static var _oldEnemyDropCheck:Function;
    private static var _oldEnemyDropItem:Object;

    private static var _world:MovieClip;
    private static var _targets:Array = [];
    private static var _hero:Object;
    private static var _queueOpen:Boolean = true;
    private static var _requestCount:Number = 0;
    private static var _killDispatchCount:Number = 0;
    private static var _deathCount:Number = 0;
    private static var _spyCount:Number = 0;
    private static var _legacyRewardOrUiCount:Number = 0;

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        _caseCount = 0;
        snapshotRootState();
        installRootSpies();
        trace("=== ChestS0ProductionFlashWiring F01-F04 start ===");
        try {
            testF01ProductionSuccessPath();
            _caseCount++;
            testF02KnownFailureAndRetry();
            _caseCount++;
            testF03GlobalArbitrationAndConsumers();
            _caseCount++;
            testF04SceneAndRootCallbackTeardown();
            _caseCount++;

            trace("ChestS0ProductionFlashWiring Tests Passed: " + _passed);
            trace("ChestS0ProductionFlashWiring Tests Failed: " + _failed);
            if (_failed > 0 || _caseCount != 4) {
                throw new Error("ChestS0ProductionFlashWiring failed: "
                    + _failed + " checks, " + _caseCount + "/4 cases");
            }
            trace("ChestS0ProductionFlashWiring Cases Passed: 4/4");
        } finally {
            try {
                cleanupWiring();
                ChestS0SocketBridge.__testOnlyReset();
            } finally {
                restoreRootState();
            }
        }
        trace("=== ChestS0ProductionFlashWiring F01-F04 complete ===");
    }

    private static function testF01ProductionSuccessPath():Void {
        resetWiring(true);
        var target:MovieClip = createBox("F01", "保险柜", 4, 2, 3, true);

        emitInteraction(null);
        var sessionId:String = ChestSessionService.getActiveSessionId();
        var pending:Object = ChestSessionService.querySession(sessionId);
        var committed:Object = ChestSessionService.commitResult(
            sessionId, 1, {result:"success"});
        var opening:Object = ChestSessionService.querySession(sessionId);
        _root.地图元件.资源箱开启脚本(target);
        var completed:Object = ChestSessionService.querySession(sessionId);
        _root.地图元件.资源箱开启脚本(target);

        check(sessionId.length > 0 && pending.state == ChestSessionService.LOCK_PENDING,
            "F01 PASS: real interactionKeyDown signs exactly one pending session");
        check(committed.success && opening.state == ChestSessionService.OPENING_ANIMATION
                && target._killed && opening.ownKillObserved
                && _killDispatchCount == 1 && _deathCount == 1,
            "F01 PASS: production KillEventComponent observes one own-kill chain");
        check(completed.state == ChestSessionService.COMPLETED_NO_REWARD
                && _requestCount == 1 && _spyCount == 1
                && _legacyRewardOrUiCount == 0
                && ChestSessionService.__getRetainedTargetCount() == 0,
            "F01 PASS: real root open callback completes once with zero reward/UI");
    }

    private static function testF02KnownFailureAndRetry():Void {
        resetWiring(true);
        var target:MovieClip = createBox("F02", "保险柜", 4, 2, 3, true);
        emitInteraction(null);
        var firstId:String = ChestSessionService.getActiveSessionId();
        var cancel:Object = ChestSessionService.commitResult(
            firstId, 1, {result:"cancel"});
        var late:Object = ChestSessionService.commitResult(
            firstId, 1, {result:"success"});
        emitInteraction(null);
        var retryId:String = ChestSessionService.getActiveSessionId();
        var failure:Object = ChestSessionService.commitResult(
            retryId, 1, {result:"failure"});

        check(cancel.success && !late.success && late.error == "stale_session"
                && retryId.length > 0 && retryId != firstId && failure.success,
            "F02 PASS: cancel/failure revoke, retry uses a new identity, old result is stale");
        check(_killDispatchCount == 0 && _deathCount == 0 && _spyCount == 0
                && _legacyRewardOrUiCount == 0,
            "F02 PASS: known non-success paths have zero kill/reward/UI side effects");

        resetWiring(true);
        _queueOpen = false;
        var openFailureTarget:MovieClip = createBox(
            "F02OpenFailure", "保险柜", 4, 2, 3, true);
        emitInteraction(null);
        check(ChestSessionService.getActiveSessionId() == ""
                && openFailureTarget.chestSessionState == ChestSessionService.AVAILABLE
                && _requestCount == 1 && _killDispatchCount == 0 && _deathCount == 0,
            "F02 PASS: known panel-open failure restores AVAILABLE without kill");
    }

    private static function testF03GlobalArbitrationAndConsumers():Void {
        resetWiring(true);
        var first:MovieClip = createBox("F03Near", "保险柜", 4, 2, 3, true);
        var second:MovieClip = createBox("F03Far", "保险柜", 12, 2, 3, true);
        emitInteraction(null);
        var firstSession:String = ChestSessionService.getActiveSessionId();
        check(firstSession.length > 0
                && first.chestSessionState == ChestSessionService.LOCK_PENDING
                && second.chestSessionState == ChestSessionService.AVAILABLE
                && _requestCount == 1,
            "F03 PASS: one global input selects only the nearest of two grid fixtures");
        ChestSessionService.commitResult(firstSession, 1, {result:"cancel"});

        resetWiring(true);
        var grid:MovieClip = createBox("F03Grid", "保险柜", 12, 2, 3, true);
        var direct:MovieClip = createBox("F03Direct", "资源箱", 3, 0, 0, false);
        emitInteraction(null);
        check(direct._killed && !grid._killed
                && ChestSessionService.getActiveSessionId() == ""
                && _requestCount == 0 && _deathCount == 1,
            "F03 PASS: grid/direct-drop mix dispatches only the nearest legacy box");

        resetWiring(true);
        var consumerBoxA:MovieClip = createBox("F03ConsumerA", "保险柜", 4, 2, 3, true);
        var consumerBoxB:MovieClip = createBox("F03ConsumerB", "保险柜", 8, 2, 3, true);
        var projector:Object = {count:0};
        var groundPickup:Object = {count:0};
        _world.dispatcher.subscribeGlobal("interactionKeyDown", function():Void {
            this.count++;
        }, projector);
        _world.dispatcher.subscribeGlobal("interactionKeyDown", function():Void {
            this.count++;
        }, groundPickup);
        emitInteraction({name:"scene-current"});
        var suppressed:Boolean = ChestSessionService.getActiveSessionId() == "";
        emitInteraction(null);
        check(suppressed && projector.count == 2 && groundPickup.count == 2
                && _requestCount == 1
                && ((consumerBoxA.chestSessionState == ChestSessionService.LOCK_PENDING
                        && consumerBoxB.chestSessionState == ChestSessionService.AVAILABLE)
                    || (consumerBoxB.chestSessionState == ChestSessionService.LOCK_PENDING
                        && consumerBoxA.chestSessionState == ChestSessionService.AVAILABLE)),
            "F03 PASS: scene priority plus projector/ground consumers preserve one box winner");
    }

    private static function testF04SceneAndRootCallbackTeardown():Void {
        resetWiring(true);
        var duplicateTarget:MovieClip = createBox(
            "F04Duplicate", "保险柜", 4, 2, 3, true);
        emitInteraction(null);
        var duplicateId:String = ChestSessionService.getActiveSessionId();
        ChestSessionService.commitResult(duplicateId, 1, {result:"success"});
        _root.地图元件.资源箱开启脚本(duplicateTarget);
        var duplicateResult:Object = ChestSessionService.commitResult(
            duplicateId, 1, {result:"success"});
        _root.地图元件.资源箱开启脚本(duplicateTarget);
        check(!duplicateResult.success && _killDispatchCount == 1
                && _deathCount == 1 && _spyCount == 1
                && _legacyRewardOrUiCount == 0,
            "F04 PASS: duplicate result/root callback has no late side effects");

        resetWiring(true);
        var breakTarget:MovieClip = createBox("F04Break", "保险柜", 4, 2, 3, true);
        emitInteraction(null);
        var breakId:String = ChestSessionService.getActiveSessionId();
        _root.地图元件.资源箱破碎脚本(breakTarget);
        _root.地图元件.资源箱破碎脚本(breakTarget);
        check(ChestSessionService.querySession(breakId).state == ChestSessionService.EXPIRED
                && _killDispatchCount == 0 && _deathCount == 0
                && _legacyRewardOrUiCount == 0,
            "F04 PASS: real root break callback expires once and never falls into legacy reward");

        resetWiring(true);
        var sceneTarget:MovieClip = createBox("F04Scene", "保险柜", 4, 2, 3, true);
        emitInteraction(null);
        var sceneId:String = ChestSessionService.getActiveSessionId();
        var manager:SceneManager = SceneManager.getInstance();
        manager.gameworld = _world;
        manager.removeGameWorld();
        _world = null;
        _targets = [];
        var lateAfterScene:Object = ChestSessionService.commitResult(
            sceneId, 1, {result:"success"});
        check(ChestSessionService.querySession(sceneId).state == ChestSessionService.EXPIRED
                && !lateAfterScene.success && _killDispatchCount == 0
                && _deathCount == 0 && _legacyRewardOrUiCount == 0
                && ChestSessionService.__getRetainedTargetCount() == 0,
            "F04 PASS: SceneManager.removeGameWorld expires first; late work stays inert");
    }

    private static function snapshotRootState():Void {
        _oldWorld = _root.gameworld;
        _oldServer = _root.server;
        _oldSceneWorld = SceneManager.getInstance().gameworld;
        _oldInventoryDrop = _root.地图元件.掉落物转换为物品栏;
        _oldEnemyDropCheck = _root.敌人函数.掉落物判定;
        _oldEnemyDropItem = _root.敌人函数.掉落物品;
    }

    private static function installRootSpies():Void {
        _root.server = null;
        _root.地图元件.掉落物转换为物品栏 = function(target:Object):Void {
            ChestS0ProductionFlashWiringTest.observeLegacyRewardOrUi();
        };
        _root.敌人函数.掉落物判定 = function():Void {
            ChestS0ProductionFlashWiringTest.observeLegacyRewardOrUi();
        };
        _root.敌人函数.掉落物品 = function():Void {};
    }

    private static function restoreRootState():Void {
        BoxInteractionArbiter.__clearTestInteractionContext();
        SceneManager.getInstance().gameworld = _oldSceneWorld;
        _root.gameworld = _oldWorld;
        _root.server = _oldServer;
        _root.地图元件.掉落物转换为物品栏 = _oldInventoryDrop;
        _root.敌人函数.掉落物判定 = _oldEnemyDropCheck;
        _root.敌人函数.掉落物品 = _oldEnemyDropItem;
    }

    private static function resetWiring(developmentEnabled:Boolean):Void {
        cleanupWiring();
        ChestSessionService.testOnlyReset();
        _queueOpen = true;
        _requestCount = 0;
        _killDispatchCount = 0;
        _deathCount = 0;
        _spyCount = 0;
        _legacyRewardOrUiCount = 0;
        _targets = [];
        _world = _root.createEmptyMovieClip(
            "__chestS0ProductionWorld" + getTimer(), _root.getNextHighestDepth());
        _world.dispatcher = new LifecycleEventDispatcher(_world);
        _root.gameworld = _world;
        _hero = {
            _x: 0,
            Z轴坐标: 0,
            area: {hitTest:function(targetArea:Object):Boolean { return true; }}
        };
        BoxInteractionArbiter.__setTestInteractionContext(_hero, null);
        ChestSessionService.configureAdapters(
            ChestS0ProductionFlashWiringTest.requestOpenAdapter,
            ChestS0ProductionFlashWiringTest.openAdapter,
            ChestS0ProductionFlashWiringTest.openFrameSpyAdapter);
        ChestSessionService.setDevelopmentEnabled(developmentEnabled);
    }

    private static function cleanupWiring():Void {
        BoxInteractionArbiter.__clearTestInteractionContext();
        if (_world) {
            for (var i:Number = 0; i < _targets.length; i++) {
                var target:MovieClip = _targets[i];
                if (!target) continue;
                InteractionHandler.cleanup(target);
                if (target.dispatcher && typeof target.dispatcher.destroy == "function") {
                    target.dispatcher.destroy();
                }
                target.removeMovieClip();
            }
            BoxInteractionArbiter.cleanup(_world);
            if (_world.dispatcher && typeof _world.dispatcher.destroy == "function") {
                _world.dispatcher.destroy();
            }
            _world.removeMovieClip();
        }
        _world = null;
        _targets = [];
    }

    private static function createBox(label:String, presetName:String,
                                      x:Number, row:Number, col:Number,
                                      exactFixture:Boolean):MovieClip {
        var target:MovieClip = _world.createEmptyMovieClip(
            "__chestS0Production" + label + getTimer(), _world.getNextHighestDepth());
        target.presetName = presetName;
        target.row = row;
        target.col = col;
        if (exactFixture) {
            target.chestS0FixtureId = ChestSessionService.FIXTURE_ID;
            target.chestS0As2GateId = ChestSessionService.AS2_GATE_ID;
            target.chestSessionState = ChestSessionService.AVAILABLE;
        }
        target._x = x;
        target.Z轴坐标 = 0;
        target._killed = false;
        target.hitPoint = 1;
        target.area = target.createEmptyMovieClip("area", target.getNextHighestDepth());
        target.element = target.createEmptyMovieClip("element", target.getNextHighestDepth());
        target.dispatcher = new LifecycleEventDispatcher(target);
        KillEventComponent.initialize(target);
        InteractionHandler.initialize(target);
        target.dispatcher.subscribe("death", function(value:Object):Void {
            ChestS0ProductionFlashWiringTest.observeDeath(value);
        }, target);
        _targets.push(target);
        return target;
    }

    private static function emitInteraction(sceneCurrent:Object):Void {
        BoxInteractionArbiter.__setTestInteractionContext(_hero, sceneCurrent);
        _world.dispatcher.publishGlobal("interactionKeyDown");
    }

    private static function requestOpenAdapter(request:Object):Boolean {
        _requestCount++;
        return _queueOpen;
    }

    private static function openAdapter(target:Object, sessionId:String):Void {
        _killDispatchCount++;
        target.dispatcher.publish("kill", target);
    }

    private static function openFrameSpyAdapter(target:Object, sessionId:String):Void {
        _spyCount++;
    }

    public static function observeDeath(target:Object):Void {
        _deathCount++;
    }

    public static function observeLegacyRewardOrUi():Void {
        _legacyRewardOrUiCount++;
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
