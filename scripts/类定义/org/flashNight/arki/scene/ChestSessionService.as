
/**
 * 地图资源箱 S0 无奖励会话服务。
 * 只证明保险柜开锁编排和唯一 kill 所有权；不滚奖、不创建容器、不打开旧 UI。
 */
class org.flashNight.arki.scene.ChestSessionService {
    public static var FIXTURE_ID:String = "insurance-safe-s0-v1";
    public static var AS2_GATE_ID:String = "local-as2-dev-s0-v1";
    public static var SOURCE_ID:String = "as2-chest-s0";

    public static var AVAILABLE:String = "AVAILABLE";
    public static var LOCK_PENDING:String = "LOCK_PENDING";
    public static var OPENING_ANIMATION:String = "OPENING_ANIMATION";
    public static var COMPLETED_NO_REWARD:String = "COMPLETED_NO_REWARD";
    public static var REVOKED:String = "REVOKED";
    public static var EXPIRED:String = "EXPIRED";
    /** S0 每个 flow 仅有一个业务写意图，callId 的完整合法域就是 {1}。 */
    public static var MAX_FLOW_CALL_ID:Number = 1;

    // AS2 开发门必须显式开启；类注册和 test reset 后默认关闭。
    private static var _developmentEnabled:Boolean = false;
    private static var _requestOpenAction:Object;
    private static var _openAction:Object;
    private static var _openFrameSpy:Object;

    private static var _active:Object;
    private static var _sessions:Object = {};
    private static var _authorityEpoch:Number = 0;
    private static var _sessionSequence:Number = 0;
    private static var _writeEpoch:Number = 0;

    public static function setDevelopmentEnabled(enabled):Void {
        _developmentEnabled = typeof enabled == "boolean" && enabled === true;
    }

    /**
     * requestOpenAction(request) 只表示请求已排队，返回值必须严格为 true。
     * openAction(target, sessionId) 是 success 后唯一允许发布正常 kill 的入口。
     * openFrameSpy(target, sessionId) 只观察开盖帧，不承载奖励逻辑。
     */
    public static function configureAdapters(requestOpenAction:Object,
                                             openAction:Object,
                                             openFrameSpy:Object):Void {
        _requestOpenAction = requestOpenAction;
        _openAction = openAction;
        _openFrameSpy = openFrameSpy;
    }

    /**
     * 真正提交互动时才重读 XML 后注入的 marker/preset/row/col。
     * 精确 marker 会占住实验路径；配置错误或开发门关闭也不会回落旧 UI。
     * 普通非 fixture 返回 handled=false，调用方可继续既有处理器。
     */
    public static function beginFixture(target:Object, source:String):Object {
        // 已签发目标即使 marker 被意外移除，也必须保持 busy，不能穿回旧奖励路径。
        if (_active !== undefined && _active !== null && _active.target === target) {
            var activeBusy:Object = response(true, false, "busy", null);
            activeBusy.state = _active.state;
            return activeBusy;
        }
        if (!hasExactFixtureMarker(target)) {
            return response(false, false, "not_s0_fixture", null);
        }
        // row/col==0 直投箱与其他 preset 永远委托原处理器，不因误贴 marker 吞掉奖励。
        if (!hasExactFixtureShape(target)) {
            return response(false, false, "fixture_shape_not_applicable", null);
        }

        setBoxState(target, AVAILABLE);
        // fixture marker 会保留旧路径短路语义，但每个 target 仍必须独立持有精确
        // authored gate；场景内另一只箱子的授权绝不能泄漏到当前目标。
        if (!hasExactLocalGate(target)) {
            return response(true, false, "development_disabled", null);
        }
        // 另一个精确 fixture 保持 AVAILABLE；不预签第二个 session。
        if (_active !== undefined && _active !== null) {
            var busyResponse:Object = response(true, false, "busy", null);
            busyResponse.state = AVAILABLE;
            return busyResponse;
        }
        if (!_developmentEnabled) {
            return response(true, false, "development_disabled", null);
        }
        if (source !== SOURCE_ID) {
            return response(true, false, "fixture_mismatch", null);
        }
        if (typeof _requestOpenAction != "function"
                || typeof _openAction != "function"
                || typeof _openFrameSpy != "function") {
            return response(true, false, "adapter_unavailable", null);
        }
        _sessionSequence++;
        var sessionId:String = "chest-s0." + _authorityEpoch + "." + _sessionSequence;
        var session:Object = {
            sessionId: sessionId,
            target: target,
            source: source,
            fixtureId: FIXTURE_ID,
            state: LOCK_PENDING,
            resultApplied: false,
            appliedCallId: 0,
            appliedResult: "",
            observedCallWatermark: 0,
            writeEpoch: 0,
            killIssued: false,
            killDispatchInProgress: false,
            expectedOwnKill: false,
            ownKillObserved: false,
            openFrameHandled: false,
            terminalReason: ""
        };
        _sessions[sessionId] = session;
        _active = session;
        setBoxState(target, LOCK_PENDING);
        markWrite(session);

        var queued:Boolean = false;
        try {
            var requestOpenAction:Function = Function(_requestOpenAction);
            queued = requestOpenAction({
                sessionId: sessionId,
                fixtureId: FIXTURE_ID,
                source: SOURCE_ID,
                presetName: "保险柜"
            }) === true;
        } catch (requestError) {
            if (session.state == LOCK_PENDING) {
                revokeSession(session, "panel_open_exception");
            }
            return response(true, false, "panel_open_exception", session);
        }

        // adapter 可以同步回报已知失败；只在本 session 仍 pending 时补撤销。
        if (!queued && session.state == LOCK_PENDING) {
            revokeSession(session, "panel_open_failed");
            return response(true, false, "panel_open_failed", session);
        }
        if (session.state != LOCK_PENDING) {
            return response(true, false, session.terminalReason, session);
        }
        return response(true, true, "", session);
    }

    /** 有限 result 提交；payload 只允许一个字段 result。 */
    public static function commitResult(sessionId:String, callId:Number, payload:Object):Object {
        var session:Object = getSession(sessionId);
        if (session === undefined || session === null) return failure("stale_session", null);
        if (!isValidCallId(callId)) return failure("invalid_payload", session);
        if (!isValidResultPayload(payload)) return failure("invalid_payload", session);
        if (_active !== session) return failure("stale_session", session);
        if (session.resultApplied) return failure("duplicate_result", session);
        if (session.state != LOCK_PENDING) return failure("invalid_state", session);
        // success 需要的执行 adapter 也属于提交前置条件；中途失效时撤销而不标记 resultApplied。
        var resultName:String = payload.result;
        if (resultName == "success" && typeof _openAction != "function") {
            observeWatermark(session, callId);
            revokeSession(session, "adapter_unavailable");
            return failure("adapter_unavailable", session);
        }

        // 只有已通过 payload/session/state/adapter 校验的权威提交才推进 result 观测水位。
        observeWatermark(session, callId);
        session.resultApplied = true;
        session.appliedCallId = callId;
        session.appliedResult = resultName;

        if (resultName == "cancel" || resultName == "failure") {
            revokeSession(session, resultName);
            return successResult(session, resultName);
        }

        // 必须在同步发布 kill 之前先提交状态和 own-kill 期望。
        session.state = OPENING_ANIMATION;
        session.killIssued = true;
        session.killDispatchInProgress = true;
        session.expectedOwnKill = true;
        setBoxState(session.target, OPENING_ANIMATION);
        markWrite(session);

        // resultApplied + killIssued 已先置位，重入或同步 death 都不能二次 kill/误 EXPIRE。
        var openError:Object = null;
        try {
        var openAction:Function = Function(_openAction);
        openAction(session.target, session.sessionId);
        } catch (caughtOpenError) {
            openError = caughtOpenError;
        } finally {
            session.killDispatchInProgress = false;
        }

        // 同步 callback 可以已经完成或终止 session；绝不覆盖它的终态/原因。
        if (session.state == COMPLETED_NO_REWARD) {
            return successResult(session, resultName);
        }
        if (session.state != OPENING_ANIMATION) {
            return failure(session.terminalReason.length > 0
                ? session.terminalReason : "terminal_reentry", session);
        }
        if (openError !== null) {
            expireSession(session, "kill_dispatch_exception");
            return failure("kill_dispatch_exception", session);
        }
        if (!session.ownKillObserved) {
            expireSession(session, "kill_dispatch_failed");
            return failure("kill_dispatch_failed", session);
        }
        return successResult(session, resultName);
    }

    public static function handleKnownPanelOpenFailure(sessionId:String, callId:Number):Object {
        return commitResult(sessionId, callId, {result: "failure"});
    }

    /**
     * XFL 开盖帧入口。精确 marker 或已签发过的目标始终 handled，短路旧滚奖/UI；
     * 只有当前 session 的首个合法 callback 会触发 spy。
     */
    public static function handleOpenFrame(target:Object, sessionId:String):Object {
        if (!isReservedFixtureTarget(target)) {
            return response(false, false, "not_s0_fixture", null);
        }
        // 真实 XFL callback 只有 target；仅允许它绑定到“当前 active 且同一 target”。
        if ((sessionId === undefined || sessionId === null || sessionId.length == 0)
                && _active !== undefined && _active !== null && _active.target === target) {
            sessionId = String(_active.sessionId);
        }
        var session:Object = getSession(sessionId);
        if (session === undefined || session === null || _active !== session
                || session.target !== target) {
            return response(true, false, "stale_session", session);
        }
        if (session.state != OPENING_ANIMATION || !session.resultApplied
                || session.appliedResult != "success" || !session.killIssued
                || !session.ownKillObserved) {
            return response(true, false, "invalid_state", session);
        }
        if (session.openFrameHandled) {
            return response(true, false, "duplicate_callback", session);
        }
        if (typeof _openFrameSpy != "function") {
            expireSession(session, "open_frame_spy_unavailable");
            return failure("adapter_unavailable", session);
        }

        // 先完成并释放 active，再调用 spy，避免 spy 重入造成重复观察。
        session.openFrameHandled = true;
        session.expectedOwnKill = false;
        session.state = COMPLETED_NO_REWARD;
        setBoxState(target, COMPLETED_NO_REWARD);
        markWrite(session);
        _active = null;
        // 外部 spy 可同步重入并建立下一代 session。异常回收前必须复核旧
        // session/target 与全局 authority/write generation 仍完全未变。
        var spySessionId:String = String(session.sessionId);
        var spyTarget:Object = target;
        var spyAuthorityEpoch:Number = _authorityEpoch;
        var spyWriteGeneration:Number = _writeEpoch;
        try {
        var openFrameSpy:Function = Function(_openFrameSpy);
        openFrameSpy(target, sessionId);
        } catch (spyError) {
            var exactOldCompletion:Boolean = getSession(spySessionId) === session
                && session.sessionId === spySessionId
                && session.target === spyTarget
                && session.state === COMPLETED_NO_REWARD
                && _active == null
                && _authorityEpoch === spyAuthorityEpoch
                && _writeEpoch === spyWriteGeneration
                && spyTarget.chestSessionState === COMPLETED_NO_REWARD;
            if (exactOldCompletion) {
                expireSession(session, "open_frame_spy_failed");
            } else {
                // 新 authority 已接管 target 时，只释放旧 tombstone 的强引用；
                // 不得把新 target/session 的 LOCK_PENDING 改写成 EXPIRED。
                releaseSessionTarget(session);
            }
            return failure("open_frame_spy_failed", session);
        }
        releaseSessionTarget(session);
        return response(true, true, "", session);
    }

    /** success 前的外部击碎会 EXPIRED；已签发 own-kill 的 death 只是观测。 */
    public static function handleTargetInvalid(target:Object):Object {
        var session:Object = _active;
        if (session === undefined || session === null || session.target !== target) {
            return failure("stale_target", session);
        }
        if (session.state == OPENING_ANIMATION && session.expectedOwnKill
                && session.killIssued && session.killDispatchInProgress) {
            if (!session.ownKillObserved) {
                session.ownKillObserved = true;
                markWrite(session);
            }
            return successResult(session, "expected_own_kill");
        }
        expireSession(session, "target_invalid");
        return successResult(session, "expired");
    }

    /** 保险柜破碎帧入口：精确 S0 目标只失效会话，绝不落入旧爆落。 */
    public static function handleBreakFrame(target:Object):Object {
        if (!isReservedFixtureTarget(target)) {
            return response(false, false, "not_s0_fixture", null);
        }
        var session:Object = _active !== undefined && _active !== null
            && _active.target === target ? _active : null;
        if (session !== null) {
            // 破碎帧绝不属于正常 own-kill；即使状态已 OPENING 也必须失效。
            expireSession(session, "target_broken");
            return response(true, true, "", session);
        }
        return response(true, false, "stale_target", null);
    }

    public static function handleSceneUnload():Object {
        return expireActive("scene_unload");
    }

    public static function handleAuthorityTeardown():Object {
        return expireActive("authority_teardown");
    }

    /** 受信有序分发器记录因果水位；只写观测元数据，不重放 result。 */
    public static function recordCausalObservation(sessionId:String,
                                                   observedCallWatermark:Number):Object {
        var session:Object = getSession(sessionId);
        if (session === undefined || session === null) return failure("stale_session", null);
        if (!isValidCallId(observedCallWatermark)) return failure("invalid_payload", session);
        var previousWatermark:Number = Number(session.observedCallWatermark);
        observeWatermark(session, observedCallWatermark);
        if (session.observedCallWatermark != previousWatermark) markWrite(session);
        return querySession(sessionId);
    }

    /**
     * 仅供受信有序 task 在已记录 fresh watermark 后调用。
     * queryResult 保持纯读；known-no-write 的权威收敛在这里原子撤销旧 attempt。
     */
    public static function resolveKnownNoWrite(sessionId:String,
                                               unknownCallId:Number):Object {
        var session:Object = getSession(sessionId);
        if (session === undefined || session === null) return failure("stale_session", null);
        if (!isValidCallId(unknownCallId)) return failure("invalid_payload", session);
        if (_active !== session || session.state != LOCK_PENDING || session.resultApplied) {
            return failure("invalid_state", session);
        }
        if (session.observedCallWatermark < unknownCallId) {
            return failure("causal_proof_incomplete", session);
        }
        revokeSession(session, "known_no_write");
        return successResult(session, "known_no_write");
    }

    /** 查询绝不调用 commitResult/openAction；调用方必须检查 resolution 与水位。 */
    public static function queryResult(sessionId:String, unknownCallId:Number):Object {
        var session:Object = getSession(sessionId);
        if (session === undefined || session === null) return failure("stale_session", null);
        if (!isValidCallId(unknownCallId)) return failure("invalid_payload", session);

        var resolution:String = "unknown";
        if (session.resultApplied && session.appliedCallId == unknownCallId) {
            resolution = "applied";
        } else if (session.observedCallWatermark >= unknownCallId) {
            resolution = "known_no_write";
        }
        return {
            success: true,
            sessionId: session.sessionId,
            state: session.state,
            resolution: resolution,
            appliedResult: resolution == "applied" ? session.appliedResult : "",
            appliedCallId: session.appliedCallId,
            observedCallWatermark: session.observedCallWatermark,
            writeEpoch: session.writeEpoch,
            authorityWriteEpoch: _writeEpoch
        };
    }

    /** TestLoader/受信接线使用的只读状态投影。 */
    public static function querySession(sessionId:String):Object {
        var session:Object = getSession(sessionId);
        if (session === undefined || session === null) return failure("stale_session", null);
        return {
            success: true,
            sessionId: session.sessionId,
            state: session.state,
            observedCallWatermark: session.observedCallWatermark,
            writeEpoch: session.writeEpoch,
            authorityWriteEpoch: _writeEpoch,
            killIssued: session.killIssued,
            expectedOwnKill: session.expectedOwnKill,
            ownKillObserved: session.ownKillObserved,
            openFrameHandled: session.openFrameHandled,
            appliedCallId: session.appliedCallId,
            appliedResult: session.appliedResult,
            terminalReason: session.terminalReason
        };
    }

    public static function getActiveSessionId():String {
        return _active === undefined || _active === null ? "" : String(_active.sessionId);
    }

    /** TestLoader 专用：终态因果 tombstone 不得继续强引用已结束的 MovieClip。 */
    public static function __getRetainedTargetCount():Number {
        var count:Number = 0;
        for (var sessionId:String in _sessions) {
            var session:Object = _sessions[sessionId];
            if (session !== undefined && session !== null
                    && session.target !== undefined && session.target !== null) {
                count++;
            }
        }
        return count;
    }

    /** TestLoader 专用：隔离静态状态，同时让 authority epoch 单调推进。 */
    public static function testOnlyReset():Void {
        _developmentEnabled = false;
        _requestOpenAction = undefined;
        _openAction = undefined;
        _openFrameSpy = undefined;
        _active = null;
        _sessions = {};
        _authorityEpoch++;
        _sessionSequence = 0;
        _writeEpoch = 0;
    }

    private static function hasExactFixtureMarker(target:Object):Boolean {
        return target !== undefined && target !== null
            && hasOwnAuthoredField(target, "chestS0FixtureId")
            && typeof target.chestS0FixtureId == "string"
            && target.chestS0FixtureId === FIXTURE_ID;
    }

    private static function hasExactLocalGate(target:Object):Boolean {
        return target !== undefined && target !== null
            && hasOwnAuthoredField(target, "chestS0As2GateId")
            && typeof target.chestS0As2GateId == "string"
            && target.chestS0As2GateId === AS2_GATE_ID;
    }

    private static function hasOwnAuthoredField(target:Object, key:String):Boolean {
        return target !== undefined && target !== null
            && typeof target.hasOwnProperty == "function" && target.hasOwnProperty(key);
    }

    private static function hasExactFixtureShape(target:Object):Boolean {
        return hasExactFixtureMarker(target)
            && typeof target.presetName == "string"
            && target.presetName === "保险柜"
            && isPositiveWholeNumber(target.row)
            && isPositiveWholeNumber(target.col);
    }

    private static function isPositiveWholeNumber(value):Boolean {
        return typeof value == "number" && (value - value) == 0
            && value >= 1 && value <= 2147483647 && Math.floor(value) == value;
    }

    private static function isValidCallId(value:Number):Boolean {
        // S0 每个 flow 只有一个业务写意图，因此唯一合法 callId 恰好为 1。
        return typeof value == "number" && value === 1;
    }

    private static function isValidResultPayload(payload:Object):Boolean {
        if (payload === undefined || payload === null || typeof payload != "object"
                || payload instanceof Array) return false;
        var resultFieldCount:Number = 0;
        for (var key:String in payload) {
            if (key != "result") return false;
            resultFieldCount++;
        }
        if (resultFieldCount != 1 || typeof payload.result != "string") return false;
        return payload.result == "success" || payload.result == "cancel"
            || payload.result == "failure";
    }

    private static function isReservedFixtureTarget(target:Object):Boolean {
        if (hasExactFixtureShape(target)) return true;
        // marker 在 active 期间即使被误删也必须继续 fail-closed；终态 session 只保留
        // 无 target 的因果 tombstone，不能在 rollback 移除 marker 后永久吞 legacy。
        return _active !== undefined && _active !== null && _active.target === target;
    }

    private static function getSession(sessionId:String):Object {
        if (typeof sessionId != "string" || sessionId.length == 0) return null;
        var session:Object = _sessions[sessionId];
        return session === undefined ? null : session;
    }

    private static function observeWatermark(session:Object, callId:Number):Void {
        if (callId > Number(session.observedCallWatermark)) {
            session.observedCallWatermark = callId;
        }
    }

    private static function markWrite(session:Object):Void {
        _writeEpoch++;
        session.writeEpoch = _writeEpoch;
    }

    private static function setBoxState(target:Object, state:String):Void {
        if (target !== undefined && target !== null) target.chestSessionState = state;
    }

    private static function revokeSession(session:Object, reason:String):Void {
        var target:Object = session.target;
        session.state = REVOKED;
        session.killDispatchInProgress = false;
        session.expectedOwnKill = false;
        session.terminalReason = reason;
        setBoxState(target, AVAILABLE);
        markWrite(session);
        if (_active === session) _active = null;
        releaseSessionTarget(session);
    }

    private static function expireSession(session:Object, reason:String):Void {
        var target:Object = session.target;
        session.state = EXPIRED;
        session.killDispatchInProgress = false;
        session.expectedOwnKill = false;
        session.terminalReason = reason;
        setBoxState(target, EXPIRED);
        markWrite(session);
        if (_active === session) _active = null;
        releaseSessionTarget(session);
    }

    private static function releaseSessionTarget(session:Object):Void {
        if (session !== undefined && session !== null) session.target = null;
    }

    private static function expireActive(reason:String):Object {
        var session:Object = _active;
        if (session === undefined || session === null) return failure("no_active_session", null);
        expireSession(session, reason);
        return successResult(session, "expired");
    }

    private static function response(handled:Boolean, successful:Boolean,
                                     errorCode:String, session:Object):Object {
        return {
            handled: handled,
            success: successful,
            error: errorCode,
            sessionId: session === undefined || session === null ? "" : session.sessionId,
            state: session === undefined || session === null ? AVAILABLE : session.state,
            observedCallWatermark: session === undefined || session === null
                ? 0 : session.observedCallWatermark,
            writeEpoch: session === undefined || session === null ? _writeEpoch : session.writeEpoch
        };
    }

    private static function failure(errorCode:String, session:Object):Object {
        return response(true, false, errorCode, session);
    }

    private static function successResult(session:Object, resultName:String):Object {
        var value:Object = response(true, true, "", session);
        value.result = resultName;
        return value;
    }
}
