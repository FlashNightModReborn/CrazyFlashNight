import org.flashNight.arki.scene.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;
import org.flashNight.neur.Event.*;

/**
 * S0 P01-P04 TestLoader supplemental preflight。
 *
 * 与 A13-A25 的纯 service mock 不同，本套件使用临时 MovieClip、本地 dispatcher、
 * InteractionHandler 和测试 adapter，尽早发现基础组合错误。它不经过生产
 * interactionKeyDown / KillEventComponent / SceneManager / 根时间轴，不能充当冻结的
 * Flash 验收门；真实 XFL 与 GUI 路径必须另行验证。
 */
class org.flashNight.arki.scene.ChestS0FlashWiringTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var _caseCount:Number = 0;

    private static var _oldWorld:Object;
    private static var _world:MovieClip;
    private static var _targets:Array = [];
    private static var _queueOpen:Boolean = true;
    private static var _requestCount:Number = 0;
    private static var _killCount:Number = 0;
    private static var _spyCount:Number = 0;
    private static var _legacyRewardCount:Number = 0;

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        _caseCount = 0;
        _oldWorld = _root.gameworld;
        trace("=== ChestS0SupplementalPreflight P01-P04 start ===");
        try {
            testP01LocalDispatcherSuccessPath();
            _caseCount++;
            testP02KnownNonSuccessRevokesWithoutKill();
            _caseCount++;
            testP03SyntheticDeathAndDirectSceneHookExpire();
            _caseCount++;
            testP04GuardModelAndMarkerRollback();
            _caseCount++;

            trace("ChestS0SupplementalPreflight Tests Passed: " + _passed);
            trace("ChestS0SupplementalPreflight Tests Failed: " + _failed);
            if (_failed > 0 || _caseCount != 4) {
                throw new Error("ChestS0SupplementalPreflight failed: "
                    + _failed + " checks, " + _caseCount + "/4 cases");
            }
            trace("ChestS0SupplementalPreflight Cases Passed: 4/4");
        } finally {
            try {
                cleanupWiring();
            } finally {
                try {
                    ChestS0SocketBridge.__testOnlyReset();
                } finally {
                    _root.gameworld = _oldWorld;
                }
            }
        }
        trace("=== ChestS0SupplementalPreflight P01-P04 complete ===");
    }

    private static function testP01LocalDispatcherSuccessPath():Void {
        resetWiring(true);
        var target:MovieClip = createFixture("P01");
        var sessionId:String = beginThroughHandler(target);
        var before:Object = ChestSessionService.querySession(sessionId);
        var committed:Object = ChestSessionService.commitResult(
            sessionId, 1, {result:"success"});
        var opening:Object = ChestSessionService.querySession(sessionId);
        var frame:Object = invokeOpenGuardModel(target);
        var completed:Object = ChestSessionService.querySession(sessionId);
        var duplicate:Object = invokeOpenGuardModel(target);

        check(before.success && before.state == ChestSessionService.LOCK_PENDING,
            "P01 local dispatcher pickUpBox signs one LOCK_PENDING session");
        check(committed.success && opening.state == ChestSessionService.OPENING_ANIMATION
                && opening.killIssued && opening.ownKillObserved,
            "P01 test adapter observes one synchronous kill/death chain");
        check(frame.handled && frame.success
                && completed.state == ChestSessionService.COMPLETED_NO_REWARD
                && _requestCount == 1 && _killCount == 1 && _spyCount == 1
                && _legacyRewardCount == 0
                && ChestSessionService.__getRetainedTargetCount() == 0,
            "P01 guard model completes once with zero modeled legacy reward and no retained target");
        check(duplicate.handled && !duplicate.success && _spyCount == 1
                && _killCount == 1 && _legacyRewardCount == 0,
            "P01 duplicate guard-model callback stays fail-closed without repeated side effects");
    }

    private static function testP02KnownNonSuccessRevokesWithoutKill():Void {
        resetWiring(true);
        var cancelTarget:MovieClip = createFixture("P02Cancel");
        var cancelId:String = beginThroughHandler(cancelTarget);
        var cancel:Object = ChestSessionService.commitResult(
            cancelId, 1, {result:"cancel"});
        var cancelFrame:Object = invokeOpenGuardModel(cancelTarget);
        check(cancel.success
                && ChestSessionService.querySession(cancelId).state == ChestSessionService.REVOKED
                && cancelFrame.handled && !cancelFrame.success
                && _killCount == 0 && _spyCount == 0 && _legacyRewardCount == 0,
            "P02 cancel revokes and the guard model stays no-reward without kill");

        resetWiring(true);
        var failureTarget:MovieClip = createFixture("P02Failure");
        var failureId:String = beginThroughHandler(failureTarget);
        var failure:Object = ChestSessionService.commitResult(
            failureId, 1, {result:"failure"});
        check(failure.success
                && ChestSessionService.querySession(failureId).state == ChestSessionService.REVOKED
                && _killCount == 0 && _spyCount == 0 && _legacyRewardCount == 0,
            "P02 gameplay failure revokes without modeled kill/reward/UI side effects");

        resetWiring(true);
        _queueOpen = false;
        var openFailureTarget:MovieClip = createFixture("P02OpenFailure");
        openFailureTarget.dispatcher.publish("pickUpBox", openFailureTarget);
        check(ChestSessionService.getActiveSessionId() == ""
                && openFailureTarget.chestSessionState == ChestSessionService.AVAILABLE
                && _requestCount == 1 && _killCount == 0 && _legacyRewardCount == 0,
            "P02 known panel-open failure atomically restores AVAILABLE");
    }

    private static function testP03SyntheticDeathAndDirectSceneHookExpire():Void {
        resetWiring(true);
        var deathTarget:MovieClip = createFixture("P03Death");
        var deathId:String = beginThroughHandler(deathTarget);
        deathTarget.dispatcher.publish("death", deathTarget);
        var deathState:Object = ChestSessionService.querySession(deathId);
        var breakFrame:Object = invokeBreakGuardModel(deathTarget);
        check(deathState.success && deathState.state == ChestSessionService.EXPIRED
                && breakFrame.handled && !breakFrame.success
                && _killCount == 0 && _legacyRewardCount == 0
                && ChestSessionService.__getRetainedTargetCount() == 0,
            "P03 synthetic external death expires and the break guard model stays closed");

        resetWiring(true);
        var sceneTarget:MovieClip = createFixture("P03Scene");
        var sceneId:String = beginThroughHandler(sceneTarget);
        var sceneExpired:Object = ChestSessionService.handleSceneUnload();
        check(sceneExpired.success
                && ChestSessionService.querySession(sceneId).state == ChestSessionService.EXPIRED
                && _killCount == 0 && _legacyRewardCount == 0
                && ChestSessionService.__getRetainedTargetCount() == 0,
            "P03 direct scene-unload service hook expires the attempt and releases its target");
    }

    private static function testP04GuardModelAndMarkerRollback():Void {
        resetWiring(false);
        var target:MovieClip = createFixture("P04");
        target.dispatcher.publish("pickUpBox", target);
        var disabledFrame:Object = invokeOpenGuardModel(target);
        check(disabledFrame.handled && !disabledFrame.success
                && ChestSessionService.getActiveSessionId() == ""
                && _requestCount == 0 && _killCount == 0 && _legacyRewardCount == 0,
            "P04 exact fixture remains fail-closed while the AS2 dev gate is disabled");

        delete target.chestS0FixtureId;
        var ordinaryFrame:Object = invokeOpenGuardModel(target);
        check(!ordinaryFrame.handled && _legacyRewardCount == 1,
            "P04 marker removal with no signed attempt delegates the modeled legacy branch");

        target.chestS0FixtureId = ChestSessionService.FIXTURE_ID;
        ChestSessionService.setDevelopmentEnabled(true);
        var sessionId:String = beginThroughHandler(target);
        ChestSessionService.commitResult(sessionId, 1, {result:"cancel"});
        delete target.chestS0FixtureId;
        var rollbackOpen:Object = invokeOpenGuardModel(target);
        var rollbackBreak:Object = invokeBreakGuardModel(target);
        check(!rollbackOpen.handled && !rollbackBreak.handled
                && _legacyRewardCount == 3 && _killCount == 0
                && ChestSessionService.__getRetainedTargetCount() == 0,
            "P04 terminal tombstone releases marker rollback to both modeled callbacks");
    }

    private static function resetWiring(developmentEnabled:Boolean):Void {
        cleanupWiring();
        ChestSessionService.testOnlyReset();
        _queueOpen = true;
        _requestCount = 0;
        _killCount = 0;
        _spyCount = 0;
        _legacyRewardCount = 0;
        _targets = [];
        _world = _root.createEmptyMovieClip(
            "__chestS0FlashWorld" + getTimer(), _root.getNextHighestDepth());
        _world.dispatcher = new LifecycleEventDispatcher(_world);
        _root.gameworld = _world;
        ChestSessionService.configureAdapters(
            ChestS0FlashWiringTest.requestOpenAdapter,
            ChestS0FlashWiringTest.openAdapter,
            ChestS0FlashWiringTest.openFrameSpyAdapter);
        ChestSessionService.setDevelopmentEnabled(developmentEnabled);
    }

    private static function cleanupWiring():Void {
        for (var i:Number = 0; i < _targets.length; i++) {
            var target:MovieClip = _targets[i];
            if (!target) continue;
            InteractionHandler.cleanup(target);
            if (target.dispatcher && typeof target.dispatcher.destroy == "function") {
                target.dispatcher.destroy();
            }
            target.removeMovieClip();
        }
        _targets = [];
        if (_world) {
            BoxInteractionArbiter.cleanup(_world);
            if (_world.dispatcher && typeof _world.dispatcher.destroy == "function") {
                _world.dispatcher.destroy();
            }
            _world.removeMovieClip();
            _world = null;
        }
    }

    private static function createFixture(label:String):MovieClip {
        var target:MovieClip = _world.createEmptyMovieClip(
            "__chestS0Flash" + label + getTimer(), _world.getNextHighestDepth());
        target.presetName = "保险柜";
        target.row = 2;
        target.col = 3;
        target.chestS0FixtureId = ChestSessionService.FIXTURE_ID;
        target.chestS0As2GateId = ChestSessionService.AS2_GATE_ID;
        target._killed = false;
        target.dispatcher = new LifecycleEventDispatcher(target);
        InteractionHandler.initialize(target);
        var killBridge:Function = function(value:Object):Void {
            ChestS0FlashWiringTest.observeKill(value);
        };
        target.dispatcher.subscribe("kill", killBridge, target);
        _targets.push(target);
        return target;
    }

    private static function beginThroughHandler(target:MovieClip):String {
        target.dispatcher.publish("pickUpBox", target);
        var sessionId:String = ChestSessionService.getActiveSessionId();
        check(sessionId.length > 0, "preflight helper signed an active session");
        return sessionId;
    }

    private static function requestOpenAdapter(request:Object):Boolean {
        _requestCount++;
        return _queueOpen;
    }

    private static function openAdapter(target:Object, sessionId:String):Void {
        target.dispatcher.publish("kill", target);
    }

    private static function openFrameSpyAdapter(target:Object, sessionId:String):Void {
        _spyCount++;
    }

    public static function observeKill(target:Object):Void {
        _killCount++;
        target._killed = true;
        target.dispatcher.publish("death", target);
    }

    /** 仅模拟 handled 分支计数；不代表真实根帧脚本或 XFL callback。 */
    private static function invokeOpenGuardModel(target:Object):Object {
        var value:Object = ChestSessionService.handleOpenFrame(target);
        if (!value.handled) _legacyRewardCount++;
        return value;
    }

    /** 仅模拟 handled 分支计数；不代表真实根帧脚本或 XFL callback。 */
    private static function invokeBreakGuardModel(target:Object):Object {
        var value:Object = ChestSessionService.handleBreakFrame(target);
        if (!value.handled) _legacyRewardCount++;
        return value;
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
