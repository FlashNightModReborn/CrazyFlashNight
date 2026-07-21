import org.flashNight.arki.scene.ChestSessionService;
import org.flashNight.arki.scene.ChestS0SocketBridge;

/** Chest S0 专用 socket actual-wire 的 TestLoader 契约测试。 */
class org.flashNight.arki.scene.ChestS0SocketBridgeTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var _cases:Number = 0;
    private static var _transport:Object;
    private static var _sent:Array;
    private static var _begins:Array;
    private static var _callbacks:Array;
    private static var _killCount:Number = 0;
    private static var _pauseAcquireCount:Number = 0;
    private static var _pauseReleaseCount:Number = 0;

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        _cases = 0;
        trace("=== ChestS0SocketBridgeTest S01-S10 start ===");
        try {
            testS01DoubleGateAndDedicatedFailClosed(); _cases++;
            testS02SuccessWireAndTerminal(); _cases++;
            testS03CapabilityIsOneShot(); _cases++;
            testS04KnownOpenFailureCanPrecedeBeginResponse(); _cases++;
            testS05CausalQueryResolvesKnownNoWrite(); _cases++;
            testS06SocketCloseExpiresWithoutFabricatedAck(); _cases++;
            testS07BeginInFlightDisconnectRecoversWithFreshNormalBootstrap(); _cases++;
            testS08ConsumedBootstrapCannotReactivateAfterSuspend(); _cases++;
            testS09BoundFlowIdentityCannotBeReadopted(); _cases++;
            testS10LateBeginResponseCannotReplaceAdoptedIdentity(); _cases++;
            trace("ChestS0SocketBridgeTest Tests Passed: " + _passed);
            trace("ChestS0SocketBridgeTest Tests Failed: " + _failed);
            if (_failed > 0) throw new Error(
                "ChestS0SocketBridgeTest failed: " + _failed + " checks");
            if (_cases != 10) throw new Error(
                "ChestS0SocketBridgeTest incomplete: " + _cases + "/10 cases");
            trace("ChestS0SocketBridgeTest Cases Passed: 10/10");
            trace("=== ChestS0SocketBridgeTest S01-S10 end ===");
        } finally {
            ChestS0SocketBridge.__testOnlyReset();
        }
    }

    private static function resetBridge():Void {
        ChestS0SocketBridge.__testOnlyReset();
        _sent = [];
        _begins = [];
        _callbacks = [];
        _killCount = 0;
        _pauseAcquireCount = 0;
        _pauseReleaseCount = 0;
        _transport = {
            isSocketConnected: true,
            sendTaskToNode: function(task:String, payload:Object, extra:Object):Boolean {
                _sent.push({task:task, payload:payload, extra:extra});
                return true;
            },
            sendTaskWithCallback: function(task:String, payload:Object, extra:Object,
                                             callback:Function, timeoutFrames:Number):Void {
                _begins.push({task:task, payload:payload, extra:extra,
                    timeoutFrames:timeoutFrames});
                _callbacks.push(callback);
            }
        };
        ChestS0SocketBridge.__testOnlySetTransport(_transport);
        ChestS0SocketBridge.__testOnlySetPauseAdapters(
            function():Boolean { _pauseAcquireCount++; return true; },
            function():Void { _pauseReleaseCount++; });
    }

    private static function fixture():Object {
        var target:Object = {
            presetName: "保险柜",
            row: 2,
            col: 3,
            chestS0FixtureId: ChestSessionService.FIXTURE_ID,
            chestS0As2GateId: ChestS0SocketBridge.LOCAL_GATE_ID,
            rewardCount: 0
        };
        target.dispatcher = {
            publish: function(eventName:String, eventTarget:Object):Void {
                if (eventName == "kill") {
                    _killCount++;
                    ChestS0SocketBridge.handleTargetInvalid(eventTarget);
                }
            }
        };
        return target;
    }

    private static function bootstrap(capability:String):Object {
        return {
            task: "cmd",
            action: "devLockboxS0Bootstrap",
            protocolVersion: 1,
            capability: capability,
            connectionGeneration: 7,
            gameProcessId: 4321,
            documentEpoch: 11,
            source: ChestSessionService.SOURCE_ID,
            fixture: ChestSessionService.FIXTURE_ID,
            resumeActive: false
        };
    }

    private static function arm(target:Object, capability:String):Void {
        ChestS0SocketBridge.observeLocalFixture(target);
        ChestS0SocketBridge.handleHostCommand(bootstrap(capability));
    }

    private static function begin(target:Object):Object {
        return ChestSessionService.beginFixture(target, ChestSessionService.SOURCE_ID);
    }

    private static function deliverBeginSuccess(sessionId:String):Void {
        deliverBeginSuccessIdentity(sessionId, "flow.test.1", "panel.test.1");
    }

    private static function deliverBeginSuccessIdentity(
            sessionId:String, flowHandle:String, panelInstanceId:String):Void {
        var callback:Function = Function(_callbacks.shift());
        callback({
            task: "dev_lockbox_s0_response",
            action: "begin",
            success: true,
            accepted: true,
            flowHandle: flowHandle,
            panelInstanceId: panelInstanceId,
            documentEpoch: 11,
            callId: 0
        });
    }

    private static function deliverBeginFailure(sessionId:String, error:String):Void {
        var callback:Function = Function(_callbacks.shift());
        callback({
            task: "dev_lockbox_s0_response",
            action: "begin",
            success: false,
            accepted: false,
            error: error,
            callId: 0
        });
    }

    private static function flowCommand(action:String, sessionId:String):Object {
        return {
            task: "cmd",
            action: action,
            protocolVersion: 1,
            sessionId: sessionId,
            flowHandle: "flow.test.1",
            panelInstanceId: "panel.test.1",
            documentEpoch: 11,
            source: ChestSessionService.SOURCE_ID,
            fixture: ChestSessionService.FIXTURE_ID
        };
    }

    private static function lastPayload():Object {
        return _sent.length == 0 ? null : _sent[_sent.length - 1].payload;
    }

    private static function countSentAction(action:String):Number {
        var count:Number = 0;
        for (var i:Number = 0; i < _sent.length; i++) {
            if (_sent[i].payload.action == action) count++;
        }
        return count;
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

    private static function testS01DoubleGateAndDedicatedFailClosed():Void {
        resetBridge();
        var authorizedTarget:Object = fixture();
        arm(authorizedTarget, "cap.s01");
        var target:Object = fixture();
        delete target.chestS0As2GateId;
        var observed:Boolean = ChestS0SocketBridge.observeLocalFixture(target);
        var started:Object = begin(target);
        var malformedConsumed:Boolean = ChestS0SocketBridge.handleHostCommand({
            task:"cmd", action:"devLockboxS0ApplyResult", result:"success"
        });
        var doubleGatePass:Boolean = !observed && _sent.length == 1 && _begins.length == 0
            && started.handled && !started.success && started.error == "development_disabled"
            && ChestSessionService.getActiveSessionId() == "" && malformedConsumed;

        resetBridge();
        var lateTarget:Object = fixture();
        var cachedBootstrap:Boolean = ChestS0SocketBridge.handleHostCommand(
            bootstrap("cap.s01.bootstrap-first"));
        var dormantBeforeMarker:Boolean = cachedBootstrap && _sent.length == 0
            && _begins.length == 0;
        var lateObserved:Boolean = ChestS0SocketBridge.observeLocalFixture(lateTarget);
        var lateStarted:Object = begin(lateTarget);
        var bootstrapFirstPass:Boolean = dormantBeforeMarker && lateObserved
            && _sent.length == 1 && _sent[0].payload.action == "bootstrap_ack"
            && lateStarted.success && _begins.length == 1;

        resetBridge();
        target = fixture();
        arm(target, "cap.s01.pause-fail");
        ChestS0SocketBridge.__testOnlySetPauseAdapters(
            function():Boolean { _pauseAcquireCount++; return false; },
            function():Void { _pauseReleaseCount++; });
        var pauseRejected:Object = begin(target);
        check(doubleGatePass && bootstrapFirstPass
                && pauseRejected.handled && !pauseRejected.success
                && pauseRejected.error == "panel_open_failed" && _begins.length == 0
                && _pauseAcquireCount == 1 && _pauseReleaseCount == 0,
            "S01 double gate, bootstrap-before-marker activation, dedicated schema, and synchronous AS2 pause acquisition fail closed");
    }

    private static function testS02SuccessWireAndTerminal():Void {
        resetBridge();
        var target:Object = fixture();
        arm(target, "cap.s02");
        var ack:Object = lastPayload();
        var started:Object = begin(target);
        var beginPayload:Object = _begins[0].payload;
        deliverBeginSuccess(started.sessionId);
        var apply:Object = flowCommand("devLockboxS0ApplyResult", started.sessionId);
        apply.flowCallId = 1;
        apply.result = "success";
        ChestS0SocketBridge.handleHostCommand(apply);
        var resultAck:Object = lastPayload();
        var frame:Object = ChestSessionService.handleOpenFrame(target, started.sessionId);
        ChestS0SocketBridge.handleAuthorityTransition(frame);
        var terminal:Object = lastPayload();
        check(ack.action == "bootstrap_ack" && ack.capability == "cap.s02"
                && beginPayload.action == "begin" && beginPayload.capability == "cap.s02"
                && beginPayload.pauseAcquired === true && _pauseAcquireCount == 1
                && beginPayload.sessionId == started.sessionId,
            "S02 exact bootstrap ack feeds one trusted socket begin payload");
        check(_killCount == 1 && resultAck.action == "result_ack"
                && resultAck.authorityState == ChestSessionService.OPENING_ANIMATION
                && resultAck.authorityTerminal === false && resultAck.applied === true,
            "S02 success emits one own-kill and a nonterminal authority result ack");
        check(frame.success && terminal.action == "authority_terminal"
                && terminal.terminal == ChestSessionService.COMPLETED_NO_REWARD
                && terminal.flowCallId == 1 && target.rewardCount == 0,
            "S02 open frame emits one COMPLETED_NO_REWARD terminal with zero reward");
    }

    private static function testS03CapabilityIsOneShot():Void {
        resetBridge();
        var first:Object = fixture();
        arm(first, "cap.s03");
        var started:Object = begin(first);
        deliverBeginSuccess(started.sessionId);
        var cancel:Object = flowCommand("devLockboxS0ApplyResult", started.sessionId);
        cancel.flowCallId = 1;
        cancel.result = "cancel";
        ChestS0SocketBridge.handleHostCommand(cancel);
        var second:Object = fixture();
        var retry:Object = begin(second);
        var rotated:Object = bootstrap("cap.s03.rotated");
        rotated.connectionGeneration = 8;
        ChestS0SocketBridge.handleHostCommand(rotated);
        var third:Object = fixture();
        var afterRotation:Object = begin(third);
        check(retry.handled && !retry.success && retry.error == "panel_open_failed"
                && _begins.length == 2 && afterRotation.success
                && _begins[1].payload.capability == "cap.s03.rotated" && _killCount == 0,
            "S03 capability is one-shot, while a fresh Host bootstrap authorizes the next attempt");
    }

    private static function testS04KnownOpenFailureCanPrecedeBeginResponse():Void {
        resetBridge();
        var target:Object = fixture();
        arm(target, "cap.s04");
        var started:Object = begin(target);
        var failed:Object = flowCommand("devLockboxS0OpenFailed", started.sessionId);
        failed.flowCallId = 1;
        failed.reason = "pre_execution_rejected";
        ChestS0SocketBridge.handleHostCommand(failed);
        deliverBeginFailure(started.sessionId, "panel_enqueue_failed");
        var ack:Object = lastPayload();
        var state:Object = ChestSessionService.querySession(started.sessionId);
        check(ack.action == "revocation_ack" && ack.authorityState == "REVOKED"
                && ack.observedCallWatermark == 1 && state.state == "REVOKED"
                && _killCount == 0 && _pauseAcquireCount == 1 && _pauseReleaseCount == 1,
            "S04 ordered open-failed push can adopt identity before begin failure response");
    }

    private static function testS05CausalQueryResolvesKnownNoWrite():Void {
        resetBridge();
        var target:Object = fixture();
        arm(target, "cap.s05");
        var started:Object = begin(target);
        deliverBeginSuccess(started.sessionId);
        var query:Object = flowCommand("devLockboxS0QueryResult", started.sessionId);
        query.unknownFlowCallId = 1;
        ChestS0SocketBridge.handleHostCommand(query);
        var reply:Object = lastPayload();
        var state:Object = ChestSessionService.querySession(started.sessionId);
        check(reply.action == "result_query_reply" && reply.disposition == "not_applied"
                && reply.observedCallWatermark == 1 && reply.authorityTerminal === true
                && reply.authorityState == "REVOKED" && state.state == "REVOKED",
            "S05 ordered causal query records watermark then resolves known-no-write");
    }

    private static function testS06SocketCloseExpiresWithoutFabricatedAck():Void {
        resetBridge();
        var target:Object = fixture();
        arm(target, "cap.s06");
        var started:Object = begin(target);
        deliverBeginSuccess(started.sessionId);
        var terminalBefore:Number = countSentAction("authority_terminal");
        var sentBefore:Number = _sent.length;
        _transport.isSocketConnected = false;
        ChestS0SocketBridge.handleSocketClosed();
        var suspended:Object = ChestSessionService.querySession(started.sessionId);
        _transport.isSocketConnected = true;
        var reconnect:Object = bootstrap("cap.s06.reconnect");
        reconnect.connectionGeneration = 8;
        reconnect.resumeActive = true;
        ChestS0SocketBridge.handleHostCommand(reconnect);
        var reconnectAck:Object = lastPayload();
        var query:Object = flowCommand("devLockboxS0QueryResult", started.sessionId);
        query.unknownFlowCallId = 1;
        ChestS0SocketBridge.handleHostCommand(query);
        var reply:Object = lastPayload();
        check(suspended.state == "LOCK_PENDING" && _sent.length >= sentBefore + 2
                && countSentAction("authority_terminal") == terminalBefore
                && reconnectAck.action == "bootstrap_ack"
                && reconnectAck.connectionGeneration == 8
                && reconnectAck.resumeActive === true
                && reply.action == "result_query_reply"
                && reply.disposition == "not_applied" && reply.authorityState == "REVOKED",
            "S06 disconnect preserves authority; fresh generation bootstrap and causal query recover it");

        resetBridge();
        target = fixture();
        arm(target, "cap.s06.expire");
        started = begin(target);
        deliverBeginSuccess(started.sessionId);
        ChestS0SocketBridge.handleTargetInvalid(target);
        var earlyTerminal:Object = lastPayload();
        check(earlyTerminal.action == "authority_terminal"
                && earlyTerminal.terminal == "EXPIRED"
                && earlyTerminal.flowCallId == 1
                && earlyTerminal.observedCallWatermark == 0,
            "S06 pre-result target expiry emits the legal zero-watermark EXPIRED terminal");
    }

    private static function testS07BeginInFlightDisconnectRecoversWithFreshNormalBootstrap():Void {
        resetBridge();
        var target:Object = fixture();
        arm(target, "cap.s07.initial");
        var orphan:Object = begin(target);
        var pending:Object = ChestSessionService.querySession(orphan.sessionId);

        // begin callback 故意不交付：模拟请求已写入 socket，但 Host 尚未接受/无 response。
        _transport.isSocketConnected = false;
        ChestS0SocketBridge.handleSocketClosed();
        _transport.isSocketConnected = true;
        var normal:Object = bootstrap("cap.s07.normal");
        normal.connectionGeneration = 8;
        ChestS0SocketBridge.handleHostCommand(normal);
        var normalAck:Object = lastPayload();
        var settled:Object = ChestSessionService.querySession(orphan.sessionId);
        // 旧 callback 即使在收敛后迟到，也不得复活 orphan 或污染下一 attempt。
        deliverBeginSuccess(orphan.sessionId);
        var afterLateResponse:Object = ChestSessionService.querySession(orphan.sessionId);

        check(pending.state == ChestSessionService.LOCK_PENDING
                && settled.state == ChestSessionService.REVOKED
                && settled.observedCallWatermark == 1
                && settled.terminalReason == "known_no_write"
                && afterLateResponse.state == ChestSessionService.REVOKED
                && ChestSessionService.getActiveSessionId().length == 0
                && normalAck.action == "bootstrap_ack"
                && normalAck.resumeActive === false && _pauseReleaseCount == 1,
            "S07 normal bootstrap proves known-no-write and settles begin-in-flight orphan");

        var fresh:Object = begin(target);
        check(fresh.success && fresh.sessionId != orphan.sessionId
                && _begins.length == 2
                && _begins[1].payload.capability == "cap.s07.normal"
                && ChestSessionService.querySession(fresh.sessionId).state
                    == ChestSessionService.LOCK_PENDING,
            "S07 settled orphan releases authority and permits one fresh tracked begin");
    }

    private static function testS08ConsumedBootstrapCannotReactivateAfterSuspend():Void {
        resetBridge();
        var target:Object = fixture();
        arm(target, "cap.s08.consumed");
        var orphan:Object = begin(target);
        var initialAckCount:Number = countSentAction("bootstrap_ack");

        _transport.isSocketConnected = false;
        ChestS0SocketBridge.handleSocketClosed();
        _transport.isSocketConnected = true;
        var sentBeforeMarker:Number = _sent.length;
        var observed:Boolean = ChestS0SocketBridge.observeLocalFixture(fixture());
        var stillPending:Object = ChestSessionService.querySession(orphan.sessionId);

        check(observed && initialAckCount == 1 && _sent.length == sentBeforeMarker
                && countSentAction("bootstrap_ack") == 1
                && stillPending.state == ChestSessionService.LOCK_PENDING
                && stillPending.observedCallWatermark == 0
                && _begins.length == 1 && _pauseReleaseCount == 0,
            "S08 a consumed suspended bootstrap cannot re-ack or settle authority when a marker is re-observed");

        var fresh:Object = bootstrap("cap.s08.fresh");
        fresh.connectionGeneration = 8;
        ChestS0SocketBridge.handleHostCommand(fresh);
        var freshAck:Object = lastPayload();
        var settled:Object = ChestSessionService.querySession(orphan.sessionId);
        check(freshAck.action == "bootstrap_ack"
                && freshAck.capability == "cap.s08.fresh"
                && freshAck.connectionGeneration == 8
                && settled.state == ChestSessionService.REVOKED
                && settled.observedCallWatermark == 1
                && _pauseReleaseCount == 1,
            "S08 only a fresh Host bootstrap may reactivate and settle the suspended orphan");
    }

    private static function testS09BoundFlowIdentityCannotBeReadopted():Void {
        resetBridge();
        var target:Object = fixture();
        arm(target, "cap.s09");
        var started:Object = begin(target);
        deliverBeginSuccess(started.sessionId);
        var sentBefore:Number = _sent.length;

        var foreignResult:Object = flowCommand(
            "devLockboxS0ApplyResult", started.sessionId);
        foreignResult.flowHandle = "flow.test.foreign";
        foreignResult.panelInstanceId = "panel.test.foreign";
        foreignResult.flowCallId = 1;
        foreignResult.result = "success";
        var foreignResultConsumed:Boolean = ChestS0SocketBridge.handleHostCommand(foreignResult);

        var foreignFailure:Object = flowCommand(
            "devLockboxS0OpenFailed", started.sessionId);
        foreignFailure.flowHandle = "flow.test.foreign";
        foreignFailure.panelInstanceId = "panel.test.foreign";
        foreignFailure.flowCallId = 1;
        foreignFailure.reason = "pre_execution_rejected";
        var foreignFailureConsumed:Boolean = ChestS0SocketBridge.handleHostCommand(foreignFailure);
        var stillPending:Object = ChestSessionService.querySession(started.sessionId);

        check(foreignResultConsumed && foreignFailureConsumed
                && _sent.length == sentBefore && _killCount == 0
                && _pauseReleaseCount == 0
                && stillPending.state == ChestSessionService.LOCK_PENDING
                && stillPending.observedCallWatermark == 0,
            "S09 a bound flow rejects same-session commands with a different exact identity");

        var exactResult:Object = flowCommand(
            "devLockboxS0ApplyResult", started.sessionId);
        exactResult.flowCallId = 1;
        exactResult.result = "success";
        ChestS0SocketBridge.handleHostCommand(exactResult);
        var exactAck:Object = lastPayload();
        var applied:Object = ChestSessionService.querySession(started.sessionId);
        check(_killCount == 1 && _sent.length == sentBefore + 1
                && exactAck.action == "result_ack"
                && exactAck.flowHandle == "flow.test.1"
                && exactAck.panelInstanceId == "panel.test.1"
                && applied.state == ChestSessionService.OPENING_ANIMATION
                && applied.observedCallWatermark == 1,
            "S09 the original exact identity remains authoritative after rejected rebind attempts");
    }

    private static function testS10LateBeginResponseCannotReplaceAdoptedIdentity():Void {
        resetBridge();
        var target:Object = fixture();
        arm(target, "cap.s10.mismatch");
        var started:Object = begin(target);

        // Host command 先于 callback 到达并收养 flow.test.1/panel.test.1。
        var adoptedResult:Object = flowCommand(
            "devLockboxS0ApplyResult", started.sessionId);
        adoptedResult.flowCallId = 1;
        adoptedResult.result = "success";
        ChestS0SocketBridge.handleHostCommand(adoptedResult);
        var sentBeforeMismatch:Number = _sent.length;
        var adoptedState:Object = ChestSessionService.querySession(started.sessionId);

        // 同 session 的迟到 callback 携带异 identity；callback 被消费，但不得 rebind。
        deliverBeginSuccessIdentity(
            started.sessionId, "flow.test.foreign", "panel.test.foreign");
        var afterMismatch:Object = ChestSessionService.querySession(started.sessionId);
        check(_callbacks.length == 0 && _sent.length == sentBeforeMismatch
                && _killCount == 1
                && adoptedState.state == ChestSessionService.OPENING_ANIMATION
                && afterMismatch.state == ChestSessionService.OPENING_ANIMATION
                && lastPayload().action == "result_ack"
                && lastPayload().flowHandle == "flow.test.1"
                && lastPayload().panelInstanceId == "panel.test.1",
            "S10 mismatched late begin response is consumed without replacing the adopted identity");

        var frame:Object = ChestSessionService.handleOpenFrame(target, started.sessionId);
        ChestS0SocketBridge.handleAuthorityTransition(frame);
        var terminal:Object = lastPayload();
        check(frame.success && terminal.action == "authority_terminal"
                && terminal.flowHandle == "flow.test.1"
                && terminal.panelInstanceId == "panel.test.1"
                && ChestSessionService.querySession(started.sessionId).state
                    == ChestSessionService.COMPLETED_NO_REWARD,
            "S10 the originally adopted exact identity remains able to complete after mismatch");

        // 同 identity 的极迟 callback 是幂等确认，不能重置 terminalSent 后重复终态。
        resetBridge();
        target = fixture();
        arm(target, "cap.s10.exact");
        started = begin(target);
        adoptedResult = flowCommand("devLockboxS0ApplyResult", started.sessionId);
        adoptedResult.flowCallId = 1;
        adoptedResult.result = "success";
        ChestS0SocketBridge.handleHostCommand(adoptedResult);
        frame = ChestSessionService.handleOpenFrame(target, started.sessionId);
        ChestS0SocketBridge.handleAuthorityTransition(frame);
        var terminalBeforeExact:Number = countSentAction("authority_terminal");
        var sentBeforeExact:Number = _sent.length;
        deliverBeginSuccessIdentity(started.sessionId, "flow.test.1", "panel.test.1");
        check(_callbacks.length == 0 && _sent.length == sentBeforeExact
                && countSentAction("authority_terminal") == terminalBeforeExact
                && lastPayload().flowHandle == "flow.test.1"
                && lastPayload().panelInstanceId == "panel.test.1",
            "S10 matching late begin response confirms the exact flow without duplicate terminal");
    }
}
