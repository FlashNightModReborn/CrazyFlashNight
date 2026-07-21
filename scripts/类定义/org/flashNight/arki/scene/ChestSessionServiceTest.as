
import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;
import org.flashNight.arki.scene.ChestSessionService;

/** S0 ADR A13-A25：无奖励 ChestSessionService TestLoader 测试。 */
class org.flashNight.arki.scene.ChestSessionServiceTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var _caseCount:Number = 0;

    private static var _requestCount:Number = 0;
    private static var _openCount:Number = 0;
    private static var _spyCount:Number = 0;
    private static var _rewardCount:Number = 0;
    private static var _requestShouldQueue:Boolean = true;
    private static var _syncTargetInvalid:Boolean = false;
    private static var _syncOpenFrame:Boolean = false;
    private static var _lastRequest:Object;
    private static var _stateSeenByOpen:String = "";
    private static var _expectedSeenByOpen:Boolean = false;
    private static var _reentrantSpyBegin:Object;

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        _caseCount = 0;
        trace("=== ChestSessionServiceTest start ===");
        try {
            testA13LateMarkerRead();
            _caseCount++;
            testA14ExactFixtureValidation();
            _caseCount++;
            testA15DevelopmentGateFailClosed();
            _caseCount++;
            testA16LockPendingHasNoRewardSideEffects();
            _caseCount++;
            testA17KnownFailuresRevoke();
            _caseCount++;
            testA18RetryGetsNewIdentityAndOldResultsStayStale();
            _caseCount++;
            testA19ResultValidationAndUniqueKill();
            _caseCount++;
            testA20OpenFrameExactlyOnce();
            _caseCount++;
            testA21InvalidCallbacksHaveNoEffect();
            _caseCount++;
            testA22ServicePathIsNoReward();
            _caseCount++;
            testA23SingleActiveSession();
            _caseCount++;
            testA24ExpiryAndSynchronousOwnKill();
            _caseCount++;
            testA25CausalQueryNeverReplays();
            _caseCount++;

            trace("ChestSessionServiceTest Tests Passed: " + _passed);
            trace("ChestSessionServiceTest Tests Failed: " + _failed);
            if (_failed > 0) throw new Error(
                "ChestSessionServiceTest failed: " + _failed + " checks");
            if (_caseCount != 13) throw new Error(
                "ChestSessionServiceTest incomplete: " + _caseCount + "/13 cases");
            trace("ChestSessionServiceTest Cases Passed: 13/13");
            trace("=== ChestSessionServiceTest end ===");
        } finally {
            ChestSessionService.testOnlyReset();
        }
    }

    private static function resetService():Void {
        ChestSessionService.testOnlyReset();
        _requestCount = 0;
        _openCount = 0;
        _spyCount = 0;
        _rewardCount = 0;
        _requestShouldQueue = true;
        _syncTargetInvalid = true;
        _syncOpenFrame = false;
        _lastRequest = null;
        _stateSeenByOpen = "";
        _expectedSeenByOpen = false;
        _reentrantSpyBegin = null;
        ChestSessionService.configureAdapters(
            ChestSessionServiceTest.requestOpenAdapter,
            ChestSessionServiceTest.openAdapter,
            ChestSessionServiceTest.openFrameSpyAdapter
        );
    }

    private static function enableDevelopment():Void {
        ChestSessionService.setDevelopmentEnabled(true);
    }

    private static function fixture():Object {
        return {
            presetName: "保险柜",
            row: 2,
            col: 3,
            chestS0FixtureId: ChestSessionService.FIXTURE_ID,
            chestS0As2GateId: ChestSessionService.AS2_GATE_ID,
            rollCount: 0,
            createCount: 0,
            containerCount: 0,
            legacyUiCount: 0
        };
    }

    private static function begin(target:Object):Object {
        return ChestSessionService.beginFixture(target, ChestSessionService.SOURCE_ID);
    }

    private static function requestOpenAdapter(request:Object):Boolean {
        _requestCount++;
        _lastRequest = request;
        return _requestShouldQueue;
    }

    private static function openAdapter(target:Object, sessionId:String):Void {
        _openCount++;
        _stateSeenByOpen = String(target.chestSessionState);
        var snapshot:Object = ChestSessionService.querySession(sessionId);
        _expectedSeenByOpen = snapshot.success && snapshot.killIssued
            && snapshot.expectedOwnKill;
        // 生产 openAction 会同步发布 kill，InteractionHandler 的 death hook 回报 own-kill。
        if (_syncTargetInvalid) ChestSessionService.handleTargetInvalid(target);
        if (_syncOpenFrame) ChestSessionService.handleOpenFrame(target, sessionId);
    }

    private static function openFrameSpyAdapter(target:Object, sessionId:String):Void {
        _spyCount++;
    }

    private static function throwingRequestAdapter(request:Object):Boolean {
        _requestCount++;
        throw new Error("request adapter test failure");
        return false;
    }

    private static function throwingOpenAdapter(target:Object, sessionId:String):Void {
        _openCount++;
        throw new Error("open adapter test failure");
    }

    private static function throwingSpyAdapter(target:Object, sessionId:String):Void {
        _spyCount++;
        throw new Error("spy adapter test failure");
    }

    private static function reentrantBeginThenThrowSpyAdapter(
            target:Object, sessionId:String):Void {
        _spyCount++;
        _reentrantSpyBegin = ChestSessionService.beginFixture(
            target, ChestSessionService.SOURCE_ID);
        throw new Error("spy adapter reentrant begin failure");
    }

    private static function rewardProbe():Void {
        _rewardCount++;
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

    private static function testA13LateMarkerRead():Void {
        resetService();
        enableDevelopment();
        var oldWorld:Object = _root.gameworld;
        var handlers:Array = [];
        var world:Object = {dispatcher:{}};
        world.dispatcher.subscribeGlobal = function(
                eventName:String, callback:Function, scope:Object):Boolean {
            handlers.push({callback:callback, scope:scope});
            return true;
        };
        world.dispatcher.unsubscribeGlobal = function():Boolean { return true; };
        var localHandlers:Object = {};
        var localSubscribeCount:Number = 0;
        var localTargetSubscribeCount:Number = 0;
        var localUnsubscribeCount:Number = 0;
        var localDispatcher:Object = {};
        localDispatcher.subscribe = function(
                eventName:String, callback:Function, scope:Object):Boolean {
            localHandlers[eventName] = {callback:callback, scope:scope};
            localSubscribeCount++;
            return true;
        };
        localDispatcher.unsubscribe = function(
                eventName:String, callback:Function, scope:Object):Boolean {
            var item:Object = localHandlers[eventName];
            if (!item || item.callback !== callback || item.scope !== scope) return false;
            delete localHandlers[eventName];
            localUnsubscribeCount++;
            return true;
        };
        localDispatcher.unsubscribeGlobal = function():Boolean { return true; };
        localDispatcher.subscribeTargetEvent = function(
                eventName:String, callback:Function, scope:Object):String {
            localTargetSubscribeCount++;
            var handlerId:String = "unload-" + localTargetSubscribeCount;
            localHandlers[eventName] = {
                callback:callback, scope:scope, handlerId:handlerId
            };
            return handlerId;
        };
        localDispatcher.unsubscribeTargetEvent = function(
                eventName:String, handlerId:String):Boolean {
            var item:Object = localHandlers[eventName];
            if (!item || item.handlerId != handlerId) return false;
            delete localHandlers[eventName];
            localUnsubscribeCount++;
            return true;
        };
        localDispatcher.publish = function(eventName:String, value:Object):Void {
            var item:Object = localHandlers[eventName];
            if (item) item.callback.call(item.scope, value);
        };
        localDispatcher.unsubscribeAll = function():Void { localHandlers = {}; };
        var target:MovieClip = _root.createEmptyMovieClip(
            "__chestS0A13Target", _root.getNextHighestDepth());
        target._x = 0;
        target.Z轴坐标 = 0;
        target.area = {};
        target._killed = false;
        target.presetName = "保险柜";
        target.row = 2;
        target.col = 3;
        target.dispatcher = localDispatcher;
        var hero:Object = {_x:0, Z轴坐标:0, area:{}};
        hero.area.hitTest = function():Boolean { return true; };
        var partialTarget:MovieClip = null;

        // 真实生产接线顺序：先 initialize/register，再模拟 cloneParameters 注入 marker。
        try {
            _root.gameworld = world;
            InteractionHandler.initialize(target);
            InteractionHandler.initialize(target);
            var replacementHandlers:Object = {};
            var replacementDispatcher:Object = {};
            replacementDispatcher.subscribe = function(
                    eventName:String, callback:Function, scope:Object):Boolean {
                replacementHandlers[eventName] = {callback:callback, scope:scope};
                localSubscribeCount++;
                return true;
            };
            replacementDispatcher.unsubscribe = function(
                    eventName:String, callback:Function, scope:Object):Boolean {
                var item:Object = replacementHandlers[eventName];
                if (!item || item.callback !== callback || item.scope !== scope) return false;
                delete replacementHandlers[eventName];
                return true;
            };
            replacementDispatcher.unsubscribeGlobal = function():Boolean { return true; };
            replacementDispatcher.subscribeTargetEvent = function(
                    eventName:String, callback:Function, scope:Object):String {
                localTargetSubscribeCount++;
                var handlerId:String = "unload-" + localTargetSubscribeCount;
                replacementHandlers[eventName] = {
                    callback:callback, scope:scope, handlerId:handlerId
                };
                return handlerId;
            };
            replacementDispatcher.unsubscribeTargetEvent = function(
                    eventName:String, handlerId:String):Boolean {
                var item:Object = replacementHandlers[eventName];
                if (!item || item.handlerId != handlerId) return false;
                delete replacementHandlers[eventName];
                return true;
            };
            replacementDispatcher.publish = function(eventName:String, value:Object):Void {
                var item:Object = replacementHandlers[eventName];
                if (item) item.callback.call(item.scope, value);
            };
            replacementDispatcher.unsubscribeAll = function():Void {
                replacementHandlers = {};
            };
            target.dispatcher = replacementDispatcher;
            InteractionHandler.initialize(target);
            target.chestS0FixtureId = ChestSessionService.FIXTURE_ID;
            target.chestS0As2GateId = ChestSessionService.AS2_GATE_ID;
            BoxInteractionArbiter.__setTestInteractionContext(hero, null);
            handlers[0].callback.call(handlers[0].scope);
            BoxInteractionArbiter.__clearTestInteractionContext();
            var activeId:String = ChestSessionService.getActiveSessionId();
            var started:Object = ChestSessionService.querySession(activeId);
            check(started.success && started.state == ChestSessionService.LOCK_PENDING
                    && _requestCount == 1 && _lastRequest.sessionId == activeId
                    && handlers.length == 1 && localSubscribeCount == 4
                    && localTargetSubscribeCount == 2 && localUnsubscribeCount == 3
                    && localHandlers.pickUpBox === undefined
                    && localHandlers.death === undefined
                    && localHandlers.onUnload === undefined,
                "A13 old dispatcher is exactly detached; replacement dispatcher is wired once");
            replacementHandlers.onUnload.callback.call(replacementHandlers.onUnload.scope);
            check(ChestSessionService.querySession(activeId).state
                        == ChestSessionService.EXPIRED,
                "A13 individual target unload unregisters and expires the active fixture");

            // 第二个本地订阅失败时必须事务回滚，且后续同 dispatcher 重试仍能完整初始化。
            var partialHandlers:Object = {};
            var partialSubscribeCount:Number = 0;
            var partialUnsubscribeCount:Number = 0;
            var failDeath:Boolean = true;
            var partialDispatcher:Object = {};
            partialDispatcher.subscribe = function(
                    eventName:String, callback:Function, scope:Object):Boolean {
                partialSubscribeCount++;
                if (eventName == "death" && failDeath) return false;
                partialHandlers[eventName] = {callback:callback, scope:scope};
                return true;
            };
            partialDispatcher.unsubscribe = function(
                    eventName:String, callback:Function, scope:Object):Boolean {
                var item:Object = partialHandlers[eventName];
                if (!item || item.callback !== callback || item.scope !== scope) return false;
                delete partialHandlers[eventName];
                partialUnsubscribeCount++;
                return true;
            };
            partialDispatcher.subscribeTargetEvent = function(
                    eventName:String, callback:Function, scope:Object):String {
                partialHandlers[eventName] = {
                    callback:callback, scope:scope, handlerId:"partial-unload"
                };
                return "partial-unload";
            };
            partialDispatcher.unsubscribeTargetEvent = function(
                    eventName:String, handlerId:String):Boolean {
                var item:Object = partialHandlers[eventName];
                if (!item || item.handlerId != handlerId) return false;
                delete partialHandlers[eventName];
                partialUnsubscribeCount++;
                return true;
            };
            partialDispatcher.unsubscribeAll = function():Void { partialHandlers = {}; };
            partialTarget = _root.createEmptyMovieClip(
                "__chestS0A13PartialTarget", _root.getNextHighestDepth());
            partialTarget.presetName = "保险柜";
            partialTarget.dispatcher = partialDispatcher;

            InteractionHandler.initialize(partialTarget);
            check(partialTarget.__cf7InteractionHandlerInitialized !== true
                    && partialHandlers.pickUpBox === undefined
                    && partialSubscribeCount == 2 && partialUnsubscribeCount == 1
                    && BoxInteractionArbiter.__getKnownRecordCount(world) == 0,
                "A13 partial subscription failure rolls back handlers, init flag, and arbiter target");

            failDeath = false;
            InteractionHandler.initialize(partialTarget);
            check(partialTarget.__cf7InteractionHandlerInitialized === true
                    && partialHandlers.pickUpBox != null
                    && partialHandlers.death != null && partialHandlers.onUnload != null
                    && partialSubscribeCount == 4
                    && BoxInteractionArbiter.__getKnownRecordCount(world) == 1,
                "A13 rolled-back target can retry and initialize exactly once");
        } finally {
            BoxInteractionArbiter.__clearTestInteractionContext();
            InteractionHandler.cleanup(target);
            if (partialTarget != null) {
                InteractionHandler.cleanup(partialTarget);
                partialTarget.removeMovieClip();
            }
            BoxInteractionArbiter.cleanup(world);
            target.removeMovieClip();
            _root.gameworld = oldWorld;
        }
    }

    private static function testA14ExactFixtureValidation():Void {
        resetService();
        enableDevelopment();
        var missing:Object = {presetName:"保险柜", row:2, col:3};
        var truthy:Object = {presetName:"保险柜", row:2, col:3, chestS0FixtureId:true};
        var wrongPreset:Object = fixture();
        wrongPreset.presetName = "资源箱";
        var directDrop:Object = fixture();
        directDrop.row = 0;
        var missingGate:Object = fixture();
        delete missingGate.chestS0As2GateId;
        var wrongGate:Object = fixture();
        wrongGate.chestS0As2GateId = "other-local-gate";
        var truthyGate:Object = fixture();
        truthyGate.chestS0As2GateId = true;
        var inheritedMarker:Object = {
            presetName:"保险柜", row:2, col:3,
            chestS0As2GateId:ChestSessionService.AS2_GATE_ID
        };
        inheritedMarker.__proto__ = {chestS0FixtureId:ChestSessionService.FIXTURE_ID};
        var inheritedGate:Object = {
            presetName:"保险柜", row:2, col:3,
            chestS0FixtureId:ChestSessionService.FIXTURE_ID
        };
        inheritedGate.__proto__ = {chestS0As2GateId:ChestSessionService.AS2_GATE_ID};
        var outOfRange:Object = fixture();
        outOfRange.row = 2147483648;
        var wrongSource:Object = ChestSessionService.beginFixture(fixture(), "other-source");
        var a:Object = begin(missing);
        var b:Object = begin(truthy);
        var c:Object = begin(wrongPreset);
        var d:Object = begin(directDrop);
        var e:Object = begin(missingGate);
        var f:Object = begin(wrongGate);
        var g:Object = begin(truthyGate);
        var inheritedMarkerResult:Object = begin(inheritedMarker);
        var inheritedGateResult:Object = begin(inheritedGate);
        var outOfRangeResult:Object = begin(outOfRange);
        check(!a.handled && !b.handled && !a.success && !b.success,
            "A14 missing or truthy non-exact marker stays outside the experiment");
        check(!c.handled && !c.success
                && !d.handled && !d.success
                && wrongSource.handled && !wrongSource.success
                && _requestCount == 0,
            "A14 wrong preset/direct-drop delegate legacy; wrong source fails closed without session");
        check(e.handled && !e.success && e.error == "development_disabled"
                && f.handled && !f.success && f.error == "development_disabled"
                && g.handled && !g.success && g.error == "development_disabled"
                && ChestSessionService.getActiveSessionId() == "" && _requestCount == 0,
            "A14 each exact fixture requires its own exact string AS2 gate even after development is enabled");
        check(!inheritedMarkerResult.handled && !inheritedMarkerResult.success
                && inheritedGateResult.handled && !inheritedGateResult.success
                && inheritedGateResult.error == "development_disabled"
                && !outOfRangeResult.handled && !outOfRangeResult.success,
            "A14 authored markers are own fields and service shape matches the positive Int32 domain");
    }

    private static function testA15DevelopmentGateFailClosed():Void {
        resetService();
        ChestSessionService.setDevelopmentEnabled("true");
        var exact:Object = begin(fixture());
        var ordinary:Object = begin({presetName:"保险柜", row:2, col:3});
        var exactFrame:Object = ChestSessionService.handleOpenFrame(fixture());
        check(exact.handled && !exact.success && exact.error == "development_disabled"
                && exact.state == ChestSessionService.AVAILABLE
                && ChestSessionService.getActiveSessionId() == "" && _requestCount == 0,
            "A15 exact fixture is handled/fail-closed when the AS2 dev gate is off or non-boolean");
        check(!ordinary.handled && !ordinary.success
                && exactFrame.handled && !exactFrame.success && _spyCount == 0,
            "A15 ordinary targets may use legacy, while exact fixture frames stay short-circuited");

        resetService();
        enableDevelopment();
        ChestSessionService.configureAdapters({}, ChestSessionServiceTest.openAdapter,
            ChestSessionServiceTest.openFrameSpyAdapter);
        var wrongAdapter:Object = begin(fixture());
        check(wrongAdapter.handled && !wrongAdapter.success
                && wrongAdapter.error == "adapter_unavailable"
                && ChestSessionService.getActiveSessionId() == "",
            "A15 truthy non-function adapters fail closed before a session is signed");
    }

    private static function testA16LockPendingHasNoRewardSideEffects():Void {
        resetService();
        enableDevelopment();
        var target:Object = fixture();
        target.掉落物判定 = ChestSessionServiceTest.rewardProbe;
        target.createContainer = ChestSessionServiceTest.rewardProbe;
        target.openLegacyUi = ChestSessionServiceTest.rewardProbe;
        var started:Object = begin(target);
        check(started.success && target.chestSessionState == ChestSessionService.LOCK_PENDING
                && _requestCount == 1 && _openCount == 0 && _spyCount == 0
                && _rewardCount == 0,
            "A16 signing reaches LOCK_PENDING with zero kill/reward/container/UI side effects");
        check(_lastRequest.fixtureId == ChestSessionService.FIXTURE_ID
                && _lastRequest.source == ChestSessionService.SOURCE_ID
                && _lastRequest.sessionId == started.sessionId,
            "A16 request-open adapter receives only the exact no-reward fixture identity");
    }

    private static function testA17KnownFailuresRevoke():Void {
        resetService();
        enableDevelopment();
        var target:Object = fixture();
        var cancelStart:Object = begin(target);
        var cancel:Object = ChestSessionService.commitResult(
            cancelStart.sessionId, 1, {result:"cancel"});
        var cancelState:Object = ChestSessionService.querySession(cancelStart.sessionId);
        check(cancel.success && cancelState.state == ChestSessionService.REVOKED
                && target.chestSessionState == ChestSessionService.AVAILABLE
                && _openCount == 0,
            "A17 cancel revokes the old session and restores AVAILABLE without kill");

        resetService();
        enableDevelopment();
        target = fixture();
        var failureStart:Object = begin(target);
        var failure:Object = ChestSessionService.commitResult(
            failureStart.sessionId, 1, {result:"failure"});
        check(failure.success
                && ChestSessionService.querySession(failureStart.sessionId).state
                    == ChestSessionService.REVOKED
                && target.chestSessionState == ChestSessionService.AVAILABLE
                && _openCount == 0,
            "A17 gameplay failure revokes without kill");

        resetService();
        enableDevelopment();
        _requestShouldQueue = false;
        target = fixture();
        var openFailure:Object = begin(target);
        check(openFailure.handled && !openFailure.success
                && openFailure.error == "panel_open_failed"
                && openFailure.state == ChestSessionService.REVOKED
                && target.chestSessionState == ChestSessionService.AVAILABLE
                && _openCount == 0,
            "A17 known panel-open failure revokes synchronously and remains no-kill");

        resetService();
        enableDevelopment();
        target = fixture();
        var adapterStart:Object = begin(target);
        ChestSessionService.configureAdapters(
            ChestSessionServiceTest.requestOpenAdapter, {},
            ChestSessionServiceTest.openFrameSpyAdapter);
        var adapterFailure:Object = ChestSessionService.commitResult(
            adapterStart.sessionId, 1, {result:"success"});
        check(!adapterFailure.success && adapterFailure.error == "adapter_unavailable"
                && ChestSessionService.querySession(adapterStart.sessionId).state
                    == ChestSessionService.REVOKED
                && _openCount == 0,
            "A17 a mid-flow missing kill adapter revokes before resultApplied or kill");

        resetService();
        enableDevelopment();
        ChestSessionService.configureAdapters(
            ChestSessionServiceTest.throwingRequestAdapter,
            ChestSessionServiceTest.openAdapter,
            ChestSessionServiceTest.openFrameSpyAdapter);
        var requestException:Object = begin(fixture());
        check(!requestException.success && requestException.error == "panel_open_exception"
                && requestException.state == ChestSessionService.REVOKED
                && ChestSessionService.getActiveSessionId() == "" && _requestCount == 1,
            "A17 request adapter exceptions revoke synchronously without stranding active state");

        resetService();
        enableDevelopment();
        target = fixture();
        var openExceptionStart:Object = begin(target);
        ChestSessionService.configureAdapters(
            ChestSessionServiceTest.requestOpenAdapter,
            ChestSessionServiceTest.throwingOpenAdapter,
            ChestSessionServiceTest.openFrameSpyAdapter);
        var openException:Object = ChestSessionService.commitResult(
            openExceptionStart.sessionId, 1, {result:"success"});
        check(!openException.success && openException.error == "kill_dispatch_exception"
                && ChestSessionService.querySession(openExceptionStart.sessionId).state
                    == ChestSessionService.EXPIRED
                && ChestSessionService.getActiveSessionId() == "" && _openCount == 1,
            "A17 kill adapter exceptions clear transient ownership and expire once");
    }

    private static function testA18RetryGetsNewIdentityAndOldResultsStayStale():Void {
        resetService();
        enableDevelopment();
        var target:Object = fixture();
        var first:Object = begin(target);
        ChestSessionService.commitResult(first.sessionId, 1, {result:"cancel"});
        var second:Object = begin(target);
        var oldSuccess:Object = ChestSessionService.commitResult(first.sessionId, 1, {result:"success"});
        var oldCancel:Object = ChestSessionService.commitResult(first.sessionId, 1, {result:"cancel"});
        var oldFailure:Object = ChestSessionService.commitResult(first.sessionId, 1, {result:"failure"});
        check(second.success && second.sessionId != first.sessionId
                && second.state == ChestSessionService.LOCK_PENDING,
            "A18 retry requires a new input and receives a new session identity");
        check(oldSuccess.error == "stale_session" && oldCancel.error == "stale_session"
                && oldFailure.error == "stale_session" && _openCount == 0
                && ChestSessionService.getActiveSessionId() == second.sessionId,
            "A18 every late result for the revoked identity is stale and side-effect free");

        resetService();
        enableDevelopment();
        var rollbackTarget:Object = fixture();
        var rollbackSession:Object = begin(rollbackTarget);
        var retainedWhileActive:Boolean = ChestSessionService.__getRetainedTargetCount() == 1;
        ChestSessionService.commitResult(rollbackSession.sessionId, 1, {result:"cancel"});
        var tombstone:Object = ChestSessionService.querySession(rollbackSession.sessionId);
        var exactTerminalFrame:Object = ChestSessionService.handleOpenFrame(
            rollbackTarget, rollbackSession.sessionId);
        delete rollbackTarget.chestS0FixtureId;
        var delegatedBegin:Object = begin(rollbackTarget);
        var delegatedOpen:Object = ChestSessionService.handleOpenFrame(
            rollbackTarget, rollbackSession.sessionId);
        var delegatedBreak:Object = ChestSessionService.handleBreakFrame(rollbackTarget);
        check(retainedWhileActive && ChestSessionService.__getRetainedTargetCount() == 0
                && tombstone.success && tombstone.state == ChestSessionService.REVOKED
                && exactTerminalFrame.handled && !exactTerminalFrame.success
                && !delegatedBegin.handled && !delegatedOpen.handled
                && !delegatedBreak.handled,
            "A18 terminal tombstone keeps causal state without target retention or rollback suppression");
    }

    private static function testA19ResultValidationAndUniqueKill():Void {
        resetService();
        enableDevelopment();
        var target:Object = fixture();
        var started:Object = begin(target);
        check(ChestSessionService.MAX_FLOW_CALL_ID == 1,
            "A19 public callId contract is the singleton domain {1}");
        var malformed:Object = ChestSessionService.commitResult(started.sessionId, 1, null);
        var rewardBearing:Object = ChestSessionService.commitResult(
            started.sessionId, 1, {result:"success", coins:999});
        var unsupported:Object = ChestSessionService.commitResult(
            started.sessionId, 1, {result:"win"});
        var nonInitialCallId:Object = ChestSessionService.commitResult(
            started.sessionId, 2, {result:"success"});
        var unsafeCallId:Object = ChestSessionService.commitResult(
            started.sessionId, 2147483648, {result:"success"});
        var beforeValid:Object = ChestSessionService.querySession(started.sessionId);
        var success:Object = ChestSessionService.commitResult(
            started.sessionId, 1, {result:"success"});
        var duplicate:Object = ChestSessionService.commitResult(
            started.sessionId, 1, {result:"success"});
        check(malformed.error == "invalid_payload" && rewardBearing.error == "invalid_payload"
                && unsupported.error == "invalid_payload"
                && nonInitialCallId.error == "invalid_payload"
                && unsafeCallId.error == "invalid_payload"
                && beforeValid.observedCallWatermark == 0 && _openCount == 1,
            "A19 invalid results neither advance causal watermark nor precede one valid kill");
        check(success.success && duplicate.error == "duplicate_result"
                && _stateSeenByOpen == ChestSessionService.OPENING_ANIMATION
                && _expectedSeenByOpen
                && target.chestSessionState == ChestSessionService.OPENING_ANIMATION,
            "A19 state and expectedOwnKill are committed before openAction; duplicate cannot kill");
    }

    private static function testA20OpenFrameExactlyOnce():Void {
        resetService();
        enableDevelopment();
        var target:Object = fixture();
        var started:Object = begin(target);
        ChestSessionService.commitResult(started.sessionId, 1, {result:"success"});
        // 真实 XFL 只传 target；service 只能绑定当前 active 的同一目标。
        var first:Object = ChestSessionService.handleOpenFrame(target);
        var duplicate:Object = ChestSessionService.handleOpenFrame(target);
        var state:Object = ChestSessionService.querySession(started.sessionId);
        check(first.success && !duplicate.success && _spyCount == 1
                && state.state == ChestSessionService.COMPLETED_NO_REWARD
                && state.openFrameHandled && ChestSessionService.getActiveSessionId() == ""
                && ChestSessionService.__getRetainedTargetCount() == 0,
            "A20 first legal open-frame completes no-reward; duplicate spy stays exactly one");

        resetService();
        enableDevelopment();
        _syncOpenFrame = true;
        target = fixture();
        started = begin(target);
        ChestSessionService.commitResult(started.sessionId, 1, {result:"success"});
        duplicate = ChestSessionService.handleOpenFrame(target);
        check(ChestSessionService.querySession(started.sessionId).state
                    == ChestSessionService.COMPLETED_NO_REWARD
                && !duplicate.success && _openCount == 1 && _spyCount == 1,
            "A20 synchronous open-frame reentry still completes and spies exactly once");

        resetService();
        enableDevelopment();
        target = fixture();
        started = begin(target);
        ChestSessionService.commitResult(started.sessionId, 1, {result:"success"});
        ChestSessionService.configureAdapters(
            ChestSessionServiceTest.requestOpenAdapter,
            ChestSessionServiceTest.openAdapter, {});
        var missingSpy:Object = ChestSessionService.handleOpenFrame(target, started.sessionId);
        check(!missingSpy.success && missingSpy.error == "adapter_unavailable"
                && ChestSessionService.querySession(started.sessionId).state
                    == ChestSessionService.EXPIRED
                && ChestSessionService.getActiveSessionId() == "" && _spyCount == 0,
            "A20 a mid-flow missing frame spy expires instead of throwing or completing");

        resetService();
        enableDevelopment();
        target = fixture();
        started = begin(target);
        ChestSessionService.commitResult(started.sessionId, 1, {result:"success"});
        ChestSessionService.configureAdapters(
            ChestSessionServiceTest.requestOpenAdapter,
            ChestSessionServiceTest.openAdapter,
            ChestSessionServiceTest.throwingSpyAdapter);
        var spyException:Object = ChestSessionService.handleOpenFrame(target, started.sessionId);
        check(!spyException.success && spyException.error == "open_frame_spy_failed"
                && ChestSessionService.querySession(started.sessionId).state
                    == ChestSessionService.EXPIRED
                && ChestSessionService.getActiveSessionId() == "" && _spyCount == 1,
            "A20 frame spy exceptions are contained and converge to EXPIRED");

        resetService();
        enableDevelopment();
        target = fixture();
        started = begin(target);
        ChestSessionService.commitResult(started.sessionId, 1, {result:"success"});
        ChestSessionService.configureAdapters(
            ChestSessionServiceTest.requestOpenAdapter,
            ChestSessionServiceTest.openAdapter,
            ChestSessionServiceTest.reentrantBeginThenThrowSpyAdapter);
        var reentrantException:Object = ChestSessionService.handleOpenFrame(
            target, started.sessionId);
        var oldAfterReentry:Object = ChestSessionService.querySession(started.sessionId);
        var newAfterReentry:Object = ChestSessionService.querySession(
            _reentrantSpyBegin.sessionId);
        check(!reentrantException.success
                && reentrantException.error == "open_frame_spy_failed"
                && _reentrantSpyBegin.success
                && _reentrantSpyBegin.sessionId != started.sessionId
                && oldAfterReentry.state == ChestSessionService.COMPLETED_NO_REWARD
                && newAfterReentry.state == ChestSessionService.LOCK_PENDING
                && ChestSessionService.getActiveSessionId() == _reentrantSpyBegin.sessionId
                && target.chestSessionState == ChestSessionService.LOCK_PENDING
                && ChestSessionService.__getRetainedTargetCount() == 1,
            "A20 reentrant spy failure preserves the newer exact session and target generation");
    }

    private static function testA21InvalidCallbacksHaveNoEffect():Void {
        resetService();
        enableDevelopment();
        var target:Object = fixture();
        var started:Object = begin(target);
        var early:Object = ChestSessionService.handleOpenFrame(target, started.sessionId);
        var wrongTarget:Object = ChestSessionService.handleOpenFrame(fixture(), started.sessionId);
        ChestSessionService.commitResult(started.sessionId, 1, {result:"cancel"});
        var retry:Object = begin(target);
        var stale:Object = ChestSessionService.handleOpenFrame(target, started.sessionId);
        check(early.handled && early.error == "invalid_state"
                && wrongTarget.handled && wrongTarget.error == "stale_session"
                && stale.handled && stale.error == "stale_session"
                && _spyCount == 0
                && ChestSessionService.getActiveSessionId() == retry.sessionId,
            "A21 early/wrong-target/old-session callbacks are short-circuited with zero spy");
    }

    private static function testA22ServicePathIsNoReward():Void {
        resetService();
        enableDevelopment();
        var target:Object = fixture();
        target.掉落物判定 = ChestSessionServiceTest.rewardProbe;
        target.掉落物转换为物品栏 = ChestSessionServiceTest.rewardProbe;
        target.openLegacyUi = ChestSessionServiceTest.rewardProbe;
        var started:Object = begin(target);
        ChestSessionService.commitResult(started.sessionId, 1, {result:"success"});
        ChestSessionService.handleOpenFrame(target, started.sessionId);
        check(_openCount == 1 && _spyCount == 1 && _rewardCount == 0
                && target.rollCount == 0 && target.createCount == 0
                && target.containerCount == 0 && target.legacyUiCount == 0,
            "A22 service-level success has one own-kill/spy and zero service reward side effects");
    }

    private static function testA23SingleActiveSession():Void {
        resetService();
        enableDevelopment();
        var firstTarget:Object = fixture();
        var secondTarget:Object = fixture();
        var first:Object = begin(firstTarget);
        var sameTarget:Object = begin(firstTarget);
        delete firstTarget.chestS0FixtureId;
        var markerLostSameTarget:Object = begin(firstTarget);
        var second:Object = begin(secondTarget);
        check(first.success && sameTarget.error == "busy"
                && sameTarget.state == ChestSessionService.LOCK_PENDING
                && markerLostSameTarget.handled && markerLostSameTarget.error == "busy"
                && firstTarget.chestSessionState == ChestSessionService.LOCK_PENDING
                && second.handled && !second.success && second.error == "busy"
                && secondTarget.chestSessionState == ChestSessionService.AVAILABLE
                && ChestSessionService.getActiveSessionId() == first.sessionId
                && _requestCount == 1 && _openCount == 0,
            "A23 an active flow rejects a second fixture without pre-signing or kill");
    }

    private static function testA24ExpiryAndSynchronousOwnKill():Void {
        resetService();
        enableDevelopment();
        var target:Object = fixture();
        var external:Object = begin(target);
        var breakFrame:Object = ChestSessionService.handleBreakFrame(target);
        var late:Object = ChestSessionService.commitResult(external.sessionId, 1, {result:"success"});
        var lateFrame:Object = ChestSessionService.handleOpenFrame(target, external.sessionId);
        check(breakFrame.handled && breakFrame.success
                && ChestSessionService.querySession(external.sessionId).state
                    == ChestSessionService.EXPIRED
                && late.error == "stale_session" && !lateFrame.success && _openCount == 0
                && ChestSessionService.__getRetainedTargetCount() == 0,
            "A24 external break frame expires without legacy reward and makes late work inert");

        resetService();
        enableDevelopment();
        var sceneTarget:Object = fixture();
        var scene:Object = begin(sceneTarget);
        ChestSessionService.handleSceneUnload();
        var sceneLate:Object = ChestSessionService.commitResult(
            scene.sessionId, 1, {result:"success"});
        var sceneLateFrame:Object = ChestSessionService.handleOpenFrame(
            sceneTarget, scene.sessionId);
        check(ChestSessionService.querySession(scene.sessionId).state
                    == ChestSessionService.EXPIRED
                && sceneLate.error == "stale_session" && !sceneLateFrame.success
                && _openCount == 0 && _spyCount == 0,
            "A24 scene unload expires and makes all late work inert");

        resetService();
        enableDevelopment();
        var authorityTarget:Object = fixture();
        var authority:Object = begin(authorityTarget);
        ChestSessionService.handleAuthorityTeardown();
        var authorityLate:Object = ChestSessionService.commitResult(
            authority.sessionId, 1, {result:"success"});
        var authorityLateFrame:Object = ChestSessionService.handleOpenFrame(
            authorityTarget, authority.sessionId);
        check(ChestSessionService.querySession(authority.sessionId).state
                    == ChestSessionService.EXPIRED
                && authorityLate.error == "stale_session" && !authorityLateFrame.success
                && _openCount == 0 && _spyCount == 0,
            "A24 authority teardown expires and makes all late work inert");

        resetService();
        enableDevelopment();
        target = fixture();
        var wrongTimeline:Object = begin(target);
        ChestSessionService.commitResult(wrongTimeline.sessionId, 1, {result:"success"});
        var unexpectedBreak:Object = ChestSessionService.handleBreakFrame(target);
        var rejectedOpen:Object = ChestSessionService.handleOpenFrame(target, wrongTimeline.sessionId);
        check(unexpectedBreak.success
                && ChestSessionService.querySession(wrongTimeline.sessionId).state
                    == ChestSessionService.EXPIRED
                && !rejectedOpen.success && _spyCount == 0,
            "A24 a break frame is never mistaken for expected own-kill, even after success");

        resetService();
        enableDevelopment();
        _syncTargetInvalid = true;
        target = fixture();
        var ownKill:Object = begin(target);
        ChestSessionService.commitResult(ownKill.sessionId, 1, {result:"success"});
        var ownKillState:Object = ChestSessionService.querySession(ownKill.sessionId);
        ChestSessionService.handleOpenFrame(target, ownKill.sessionId);
        check(ownKillState.state == ChestSessionService.OPENING_ANIMATION
                && ownKillState.ownKillObserved && ownKillState.expectedOwnKill
                && _openCount == 1 && _spyCount == 1,
            "A24 synchronous death from the expected own-kill is not misclassified EXPIRED");

        resetService();
        enableDevelopment();
        _syncTargetInvalid = false;
        target = fixture();
        var missingDeath:Object = begin(target);
        var dispatchFailure:Object = ChestSessionService.commitResult(
            missingDeath.sessionId, 1, {result:"success"});
        check(!dispatchFailure.success && dispatchFailure.error == "kill_dispatch_failed"
                && ChestSessionService.querySession(missingDeath.sessionId).state
                    == ChestSessionService.EXPIRED
                && ChestSessionService.getActiveSessionId() == "" && _openCount == 1,
            "A24 openAction without synchronous own-kill proof expires the session");
    }

    private static function testA25CausalQueryNeverReplays():Void {
        resetService();
        enableDevelopment();
        var started:Object = begin(fixture());
        ChestSessionService.commitResult(started.sessionId, 1, {result:"success"});
        var applied:Object = ChestSessionService.queryResult(started.sessionId, 1);
        var appliedAgain:Object = ChestSessionService.queryResult(started.sessionId, 1);
        check(applied.resolution == "applied" && applied.appliedResult == "success"
                && applied.observedCallWatermark >= 1 && applied.writeEpoch > 0
                && appliedAgain.resolution == "applied" && _openCount == 1,
            "A25 fresh causal query recovers ack-lost success without replaying openAction");

        resetService();
        enableDevelopment();
        var retryTarget:Object = fixture();
        started = begin(retryTarget);
        var oldRead:Object = ChestSessionService.queryResult(started.sessionId, 1);
        var invalidOldObservation:Object = ChestSessionService.recordCausalObservation(
            started.sessionId, 0);
        var stillOld:Object = ChestSessionService.queryResult(started.sessionId, 1);
        ChestSessionService.recordCausalObservation(started.sessionId, 1);
        var noWrite:Object = ChestSessionService.queryResult(started.sessionId, 1);
        var resolved:Object = ChestSessionService.resolveKnownNoWrite(started.sessionId, 1);
        var resolvedState:Object = ChestSessionService.querySession(started.sessionId);
        var availableAfterResolve:Boolean = retryTarget.chestSessionState
            == ChestSessionService.AVAILABLE;
        var retry:Object = begin(retryTarget);
        var late:Object = ChestSessionService.commitResult(
            started.sessionId, 1, {result:"success"});
        check(oldRead.resolution == "unknown" && stillOld.resolution == "unknown"
                && invalidOldObservation.error == "invalid_payload"
                && noWrite.resolution == "known_no_write"
                && noWrite.observedCallWatermark >= 1 && resolved.success
                && resolvedState.state == ChestSessionService.REVOKED
                && availableAfterResolve
                && retryTarget.chestSessionState == ChestSessionService.LOCK_PENDING
                && retry.success && retry.sessionId != started.sessionId
                && late.error == "stale_session" && _openCount == 0,
            "A25 fresh no-write proof revokes the old attempt and retry gets a new identity");
    }
}
