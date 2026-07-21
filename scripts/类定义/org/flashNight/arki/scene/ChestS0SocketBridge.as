import org.flashNight.neur.Server.ServerManager;

import org.flashNight.arki.scene.ChestSessionService;

/**
 * 地图资源箱 S0 的唯一 AS2 <-> Launcher socket 适配层。
 *
 * 该类默认休眠。只有同时观察到精确的本地开发 fixture 标记，并收到 Host
 * 绑定当前 socket generation / Flash PID / document epoch 的 bootstrap 后，才会
 * 打开 ChestSessionService 的开发门。业务消息只走 dev_lockbox_s0 专用 task，
 * 不注册到 gameCommands、HTTP、普通 Web 消息或旧奖励/UI 路径。
 */
class org.flashNight.arki.scene.ChestS0SocketBridge {
    public static var PROTOCOL_VERSION:Number = 1;
    public static var LOCAL_GATE_ID:String = ChestSessionService.AS2_GATE_ID;
    public static var SOCKET_TASK:String = "dev_lockbox_s0";

    private static var _localFixtureAuthorized:Boolean = false;
    private static var _bootstrap:Object = null;
    private static var _flow:Object = null;
    private static var _localSessionId:String = "";
    private static var _localDocumentEpoch:Number = 0;
    private static var _transport:Object;
    private static var _terminalSent:Boolean = false;
    private static var _pauseAssertedByS0:Boolean = false;
    private static var _testPauseAcquire:Function;
    private static var _testPauseRelease:Function;

    /**
     * 只观察 authored target 的值，不保留 MovieClip 引用。授权仅在当前场景有效，
     * SceneManager teardown 或 socket teardown 都会清零。
     */
    public static function observeLocalFixture(target:Object):Boolean {
        if (!hasExactLocalFixtureShape(target)) return false;
        _localFixtureAuthorized = true;
        activateBootstrapIfReady();
        return true;
    }

    /** ServerManager 在普通 gameCommands 之前用它截获专用 Host action。 */
    public static function isDedicatedHostAction(action:String):Boolean {
        return action == "devLockboxS0Bootstrap"
            || action == "devLockboxS0ApplyResult"
            || action == "devLockboxS0QueryResult"
            || action == "devLockboxS0OpenFailed";
    }

    /**
     * Host -> AS2 的严格入口。识别出的专用 action 即使 schema 非法也会被吞掉，
     * 永不回落到 _root.gameCommands。
     */
    public static function handleHostCommand(command:Object):Boolean {
        if (command === undefined || command === null
                || !isDedicatedHostAction(String(command.action))) return false;
        if (command.action == "devLockboxS0Bootstrap") {
            handleBootstrap(command);
            return true;
        }
        if (command.action == "devLockboxS0ApplyResult") {
            handleApplyResult(command);
            return true;
        }
        if (command.action == "devLockboxS0QueryResult") {
            handleResultQuery(command);
            return true;
        }
        handleOpenFailed(command);
        return true;
    }

    /** InteractionHandler 的 death/onUnload/cleanup 统一走这里以发送权威终态。 */
    public static function handleTargetInvalid(target:Object):Object {
        var result:Object = ChestSessionService.handleTargetInvalid(target);
        handleAuthorityTransition(result);
        return result;
    }

    /** XFL 根回调与其它会话转移在提交后调用；重复调用是幂等的。 */
    public static function handleAuthorityTransition(result:Object):Void {
        if (_flow === undefined || _flow === null || _terminalSent) return;
        if (result !== undefined && result !== null
                && typeof result.sessionId == "string" && result.sessionId.length > 0
                && result.sessionId !== _flow.sessionId) return;
        emitTerminalFromSession();
    }

    /** SceneManager 必须在 dispatcher/gameworld 销毁前调用。 */
    public static function handleSceneUnload():Object {
        var result:Object = ChestSessionService.handleSceneUnload();
        handleAuthorityTransition(result);
        // 场景已结束，不再允许新 begin；若 terminal 尚未被 Host 证明接收，保留
        // 纯字符串 tombstone，供同一进程的 socket reconnect 重放。绝不保留 target。
        ChestSessionService.setDevelopmentEnabled(false);
        ChestSessionService.configureAdapters(undefined, undefined, undefined);
        _localFixtureAuthorized = false;
        suspendBootstrap();
        return result;
    }

    /**
     * XMLSocket 断开是 transport unknown，不等于权威 teardown。Host 会保留 active
     * flow，并用新 generation/bootstrap 恢复因果查询；因此这里冻结新 begin，但
     * 保留 session/flow/tombstone 和本场景已观察过的 authored gate。
     */
    public static function handleSocketClosed():Object {
        ChestSessionService.setDevelopmentEnabled(false);
        suspendBootstrap();
        // send=true 不是 Host 已提交的证明；重连后允许幂等重放 terminal。
        _terminalSent = false;
        var activeId:String = ChestSessionService.getActiveSessionId();
        return activeId.length > 0
            ? ChestSessionService.querySession(activeId)
            : {handled:true, success:true, state:"transport_unknown"};
    }

    private static function handleBootstrap(command:Object):Void {
        var keys:Array = [
            "task", "action", "protocolVersion", "capability",
            "connectionGeneration", "gameProcessId", "documentEpoch",
            "source", "fixture", "resumeActive"
        ];
        if (!hasExactKeys(command, keys)
                || command.task !== "cmd"
                || command.action !== "devLockboxS0Bootstrap"
                || command.protocolVersion !== PROTOCOL_VERSION
                || !isOpaque(command.capability)
                || !isPositiveInt32(command.connectionGeneration)
                || !isPositiveInt32(command.gameProcessId)
                || !isPositiveInt32(command.documentEpoch)
                || typeof command.resumeActive != "boolean"
                || command.source !== ChestSessionService.SOURCE_ID
                || command.fixture !== ChestSessionService.FIXTURE_ID) return;

        var hasRecoveryTombstone:Boolean = (_flow !== undefined && _flow !== null)
            || _localSessionId.length > 0;
        // active reconnect 必须由 Host 明示；没有本地 tombstone 时不接受伪恢复。
        if (command.resumeActive === true && !hasRecoveryTombstone) return;
        // AS2 已持有 flow identity 时，Host 的 normal bootstrap 只能发生在旧 flow
        // 已终结后；活跃 flow 的冲突信号必须 fail-closed，不能撤销或覆盖。
        if (command.resumeActive === false && _flow !== undefined && _flow !== null) {
            var existingState:Object = ChestSessionService.querySession(_flow.sessionId);
            if (existingState.success !== true
                    || !isTerminalState(String(existingState.state))) return;
        }

        // 相同 bootstrap 可幂等重发 ack；新 generation/capability 用于 reconnect
        // 或前一 attempt 完整收束后的下一次 arm，二者都必须能轮换。
        if (_bootstrap !== undefined && _bootstrap !== null
                && _bootstrap.acknowledged === true) {
            if (sameBootstrap(command, _bootstrap)) sendBootstrapAck(_bootstrap);
            if (sameBootstrap(command, _bootstrap)) return;
        }

        // 活跃本地 session 只允许同一 Flash 进程恢复；document epoch 可因 Web
        // navigation 单调推进，flow identity 仍保留签发时 epoch。
        if (ChestSessionService.getActiveSessionId().length > 0
                && _bootstrap !== undefined && _bootstrap !== null
                && typeof _bootstrap.gameProcessId == "number"
                && command.gameProcessId !== _bootstrap.gameProcessId) return;

        _bootstrap = {
            protocolVersion: command.protocolVersion,
            capability: command.capability,
            connectionGeneration: command.connectionGeneration,
            gameProcessId: command.gameProcessId,
            documentEpoch: command.documentEpoch,
            source: command.source,
            fixture: command.fixture,
            resumeActive: command.resumeActive,
            acknowledged: false,
            consumed: false
        };
        if (_flow !== undefined && _flow !== null) _terminalSent = false;
        activateBootstrapIfReady();
    }

    private static function activateBootstrapIfReady():Void {
        var hasRecoveryTombstone:Boolean = (_flow !== undefined && _flow !== null)
            || _localSessionId.length > 0;
        if ((!_localFixtureAuthorized && !hasRecoveryTombstone)
                || _bootstrap === undefined || _bootstrap === null
                || _bootstrap.acknowledged === true
                || _bootstrap.consumed === true) return;

        ChestSessionService.configureAdapters(
            function(request:Object):Boolean {
                return ChestS0SocketBridge.requestTrackedOpen(request);
            },
            function(target:Object, sessionId:String):Void {
                if (target === undefined || target === null || target.dispatcher === undefined
                        || typeof target.dispatcher.publish != "function") {
                    throw new Error("S0 kill dispatcher unavailable");
                }
                target.dispatcher.publish("kill", target);
            },
            function(target:Object, sessionId:String):Void {
                trace("[ChestS0SocketBridge] open frame observed; session=" + sessionId);
            }
        );

        // begin 已排入 socket、但 Host 仍 Idle 且 response 丢失时，本地可能只剩
        // LOCK_PENDING + sessionId（没有 flow identity）。normal bootstrap 是专用
        // Host 有序分发器给出的 known-no-write 证明；先撤销 orphan，才可启用新 begin。
        // active resume 绝不走此分支，仍由后续 exact flow command validate/adopt。
        if (!settlePendingOrphanForNormalBootstrap(_bootstrap)) {
            ChestSessionService.setDevelopmentEnabled(false);
            ChestSessionService.configureAdapters(undefined, undefined, undefined);
            return;
        }

        if (!sendBootstrapAck(_bootstrap)) {
            ChestSessionService.setDevelopmentEnabled(false);
            ChestSessionService.configureAdapters(undefined, undefined, undefined);
            return;
        }
        _bootstrap.acknowledged = true;
        ChestSessionService.setDevelopmentEnabled(true);
        emitTerminalFromSession();
    }

    private static function sendBootstrapAck(binding:Object):Boolean {
        return sendPayload({
            action: "bootstrap_ack",
            protocolVersion: PROTOCOL_VERSION,
            capability: binding.capability,
            connectionGeneration: binding.connectionGeneration,
            gameProcessId: binding.gameProcessId,
            documentEpoch: binding.documentEpoch,
            source: ChestSessionService.SOURCE_ID,
            fixture: ChestSessionService.FIXTURE_ID,
            resumeActive: binding.resumeActive
        });
    }

    private static function settlePendingOrphanForNormalBootstrap(binding:Object):Boolean {
        if (binding.resumeActive !== false
                || (_flow !== undefined && _flow !== null)
                || _localSessionId.length == 0) return true;

        var orphanSessionId:String = _localSessionId;
        var state:Object = ChestSessionService.querySession(orphanSessionId);
        if (state.success !== true) return false;
        if (state.state == ChestSessionService.LOCK_PENDING) {
            if (ChestSessionService.getActiveSessionId() !== orphanSessionId) return false;
            var observation:Object = ChestSessionService.recordCausalObservation(
                orphanSessionId, 1);
            if (observation.success !== true) return false;
            var resolved:Object = ChestSessionService.resolveKnownNoWrite(orphanSessionId, 1);
            if (resolved.success !== true || resolved.state !== ChestSessionService.REVOKED) {
                return false;
            }
        } else if (!isTerminalState(String(state.state))) {
            return false;
        }

        _localSessionId = "";
        _localDocumentEpoch = 0;
        _terminalSent = false;
        releaseS0WebPanelPause();
        return true;
    }

    /** ChestSessionService requestOpenAction：返回 true 只代表消息已排入 socket。 */
    private static function requestTrackedOpen(request:Object):Boolean {
        var requestKeys:Array = ["sessionId", "fixtureId", "source", "presetName"];
        if (!_localFixtureAuthorized || _bootstrap === undefined || _bootstrap === null
                || _bootstrap.acknowledged !== true || _bootstrap.consumed === true
                || !hasExactKeys(request, requestKeys)
                || !isOpaque(request.sessionId)
                || request.fixtureId !== ChestSessionService.FIXTURE_ID
                || request.source !== ChestSessionService.SOURCE_ID
                || request.presetName !== "保险柜") return false;

        var transport:Object = getTransport();
        if (transport === undefined || transport === null
                || transport.isSocketConnected !== true
                || typeof transport.sendTaskWithCallback != "function") return false;

        // 新 attempt 不得继承前一终态的 flow identity；否则它在 begin response 丢失
        // 后会被旧 _flow 遮住，normal reconnect 无法识别并收敛 orphan。
        if (_flow !== undefined && _flow !== null
                && _flow.sessionId !== request.sessionId) {
            var priorState:Object = ChestSessionService.querySession(_flow.sessionId);
            if (priorState.success !== true
                    || !isTerminalState(String(priorState.state))) return false;
            _flow = null;
            _terminalSent = false;
        }

        // begin 由 AS2 发出；必须先在同一 AS2 调用栈内实际取得 webpanel lease，
        // 再把 pauseAcquired=true 的因果证明写入专用 socket。Host 的 generation-bound
        // pause 写与 UI 执行前复核只是冗余，不能替代这里的同步 lease。
        if (!acquireS0WebPanelPause()) return false;

        var capability:String = String(_bootstrap.capability);
        _bootstrap.consumed = true;
        _bootstrap.capability = "";
        _localSessionId = String(request.sessionId);
        _localDocumentEpoch = Number(_bootstrap.documentEpoch);
        var payload:Object = {
            action: "begin",
            protocolVersion: PROTOCOL_VERSION,
            capability: capability,
            sessionId: request.sessionId,
            pauseAcquired: true,
            source: ChestSessionService.SOURCE_ID,
            fixture: ChestSessionService.FIXTURE_ID
        };
        try {
            transport.sendTaskWithCallback(
                SOCKET_TASK,
                payload,
                null,
                function(response:Object):Void {
                    ChestS0SocketBridge.handleBeginResponse(request.sessionId, response);
                },
                600
            );
        } catch (sendError) {
            if (_localSessionId === request.sessionId) {
                _localSessionId = "";
                _localDocumentEpoch = 0;
            }
            releaseS0WebPanelPause();
            return false;
        }
        return true;
    }

    private static function handleBeginResponse(sessionId:String, response:Object):Void {
        if (ChestSessionService.getActiveSessionId() !== sessionId
                && _localSessionId !== sessionId
                && (_flow === undefined || _flow === null || _flow.sessionId !== sessionId)) return;

        var successKeys:Array = [
            "task", "action", "success", "accepted", "flowHandle",
            "panelInstanceId", "documentEpoch", "callId"
        ];
        if (hasExactKeys(response, successKeys)
                && response.task === "dev_lockbox_s0_response"
                && response.action === "begin"
                && response.success === true && response.accepted === true
                && isOpaque(response.flowHandle) && isOpaque(response.panelInstanceId)
                && isNonNegativeInt32(response.callId)
                && response.documentEpoch === _localDocumentEpoch) {
            // open-failed/result/query command 可能先于 begin callback 到达并收养 flow。
            // callback 只能确认同一完整 identity；任何同 session 异 flow/panel 的迟到
            // response 都必须被消费后丢弃，绝不能覆盖已经生效的 Host authority。
            if (_flow !== undefined && _flow !== null) {
                if (!matchesExactBeginResponseFlow(sessionId, response)) return;
                emitTerminalFromSession();
                return;
            }
            _flow = {
                sessionId: sessionId,
                flowHandle: response.flowHandle,
                panelInstanceId: response.panelInstanceId,
                documentEpoch: response.documentEpoch,
                flowCallId: 1
            };
            _terminalSent = false;
            emitTerminalFromSession();
            return;
        }

        var failureKeys:Array = [
            "task", "action", "success", "accepted", "error", "callId"
        ];
        if (hasExactKeys(response, failureKeys)
                && response.task === "dev_lockbox_s0_response"
                && response.action === "begin"
                && response.success === false && response.accepted === false
                && isNonNegativeInt32(response.callId)
                && isKnownBeginFailure(String(response.error))) {
            ChestSessionService.handleKnownPanelOpenFailure(sessionId, 1);
            releaseS0WebPanelPause();
        }
        // callback timeout / socket closed / malformed response 都是 transport unknown。
        // 不把未知写事实伪装成 known-no-write；重连后的有序 query 才能收敛。
    }

    private static function handleApplyResult(command:Object):Void {
        var keys:Array = baseFlowCommandKeys();
        keys.push("flowCallId");
        keys.push("result");
        if (!hasExactKeys(command, keys)
                || command.action !== "devLockboxS0ApplyResult"
                || !validateOrAdoptFlowCommand(command)
                || command.flowCallId !== 1 || !isLimitedResult(command.result)) return;

        var commit:Object = ChestSessionService.commitResult(
            _flow.sessionId, 1, {result: command.result});
        var state:Object = ChestSessionService.querySession(_flow.sessionId);
        if (state.success !== true || state.appliedCallId !== 1
                || state.appliedResult !== command.result) return;

        var terminal:Boolean = isTerminalState(String(state.state));
        sendPayload(withFlowIdentity({
            action: "result_ack",
            flowCallId: 1,
            result: command.result,
            applied: true,
            observedCallWatermark: state.observedCallWatermark,
            authorityTerminal: terminal,
            authorityState: state.state
        }));
        if (terminal) _terminalSent = true;
        handleAuthorityTransition(commit);
    }

    private static function handleResultQuery(command:Object):Void {
        var keys:Array = baseFlowCommandKeys();
        keys.push("unknownFlowCallId");
        if (!hasExactKeys(command, keys)
                || command.action !== "devLockboxS0QueryResult"
                || !validateOrAdoptFlowCommand(command)
                || command.unknownFlowCallId !== 1) return;

        var observation:Object = ChestSessionService.recordCausalObservation(_flow.sessionId, 1);
        if (observation.success !== true) {
            sendQueryReply("unknown", observation);
            return;
        }
        var query:Object = ChestSessionService.queryResult(_flow.sessionId, 1);
        if (query.success !== true) {
            sendQueryReply("unknown", query);
            return;
        }

        var disposition:String = "unknown";
        if (query.resolution == "applied") {
            disposition = String(query.appliedResult);
        } else if (query.resolution == "known_no_write") {
            ChestSessionService.resolveKnownNoWrite(_flow.sessionId, 1);
            query = ChestSessionService.queryResult(_flow.sessionId, 1);
            disposition = "not_applied";
        }
        sendQueryReply(disposition, query);
    }

    private static function sendQueryReply(disposition:String, query:Object):Void {
        var stateName:String = query !== undefined && query !== null
            && typeof query.state == "string" ? String(query.state) : ChestSessionService.LOCK_PENDING;
        var watermark:Number = query !== undefined && query !== null
            && typeof query.observedCallWatermark == "number"
            ? Number(query.observedCallWatermark) : 0;
        sendPayload(withFlowIdentity({
            action: "result_query_reply",
            flowCallId: 1,
            observedCallWatermark: watermark,
            disposition: disposition,
            authorityTerminal: isTerminalState(stateName),
            authorityState: stateName
        }));
        if (disposition != "unknown" && isTerminalState(stateName)) _terminalSent = true;
    }

    private static function handleOpenFailed(command:Object):Void {
        var keys:Array = baseFlowCommandKeys();
        keys.push("flowCallId");
        keys.push("reason");
        if (!hasExactKeys(command, keys)
                || command.action !== "devLockboxS0OpenFailed"
                || command.flowCallId !== 1
                || !isKnownOpenFailureReason(String(command.reason))
                || !validateOrAdoptFlowCommand(command)) return;

        ChestSessionService.handleKnownPanelOpenFailure(_flow.sessionId, 1);
        var state:Object = ChestSessionService.querySession(_flow.sessionId);
        if (state.success !== true || state.state !== ChestSessionService.REVOKED
                || state.observedCallWatermark !== 1) return;
        sendPayload(withFlowIdentity({
            action: "revocation_ack",
            observedCallWatermark: 1,
            authorityState: ChestSessionService.REVOKED
        }));
        _terminalSent = true;
    }

    /**
     * enqueue 失败可能先 push open-failed；断线也可能丢 begin response。专用 Host
     * command 可在 exact 本地 session + 签发 epoch 上补回 flow identity。
     */
    private static function validateOrAdoptFlowCommand(command:Object):Boolean {
        // Adoption only repairs the narrow ordering gap before the begin response establishes
        // an identity.  Once a flow exists, every Host command must match it exactly; a stale or
        // malformed command must never rebind the live AS2 authority to another panel identity.
        if (_flow !== undefined && _flow !== null) return validateFlowCommand(command);
        if (_bootstrap === undefined || _bootstrap === null
                || _bootstrap.acknowledged !== true
                || command.task !== "cmd" || command.protocolVersion !== PROTOCOL_VERSION
                || command.source !== ChestSessionService.SOURCE_ID
                || command.fixture !== ChestSessionService.FIXTURE_ID
                || command.documentEpoch !== _localDocumentEpoch
                || command.sessionId !== _localSessionId
                || !isOpaque(command.sessionId) || !isOpaque(command.flowHandle)
                || !isOpaque(command.panelInstanceId)) return false;
        _flow = {
            sessionId: command.sessionId,
            flowHandle: command.flowHandle,
            panelInstanceId: command.panelInstanceId,
            documentEpoch: command.documentEpoch,
            flowCallId: 1
        };
        _terminalSent = false;
        return true;
    }

    private static function emitTerminalFromSession():Void {
        if (_flow === undefined || _flow === null || _terminalSent) return;
        var state:Object = ChestSessionService.querySession(_flow.sessionId);
        if (state.success !== true
                || (state.state !== ChestSessionService.COMPLETED_NO_REWARD
                    && state.state !== ChestSessionService.EXPIRED)) return;
        if (sendPayload(withFlowIdentity({
            action: "authority_terminal",
            flowCallId: 1,
            observedCallWatermark: state.observedCallWatermark,
            terminal: state.state
        }))) _terminalSent = true;
    }

    private static function withFlowIdentity(extra:Object):Object {
        var payload:Object = {
            protocolVersion: PROTOCOL_VERSION,
            sessionId: _flow.sessionId,
            flowHandle: _flow.flowHandle,
            panelInstanceId: _flow.panelInstanceId,
            documentEpoch: _flow.documentEpoch,
            source: ChestSessionService.SOURCE_ID,
            fixture: ChestSessionService.FIXTURE_ID
        };
        for (var key:String in extra) {
            if (extra.hasOwnProperty(key)) payload[key] = extra[key];
        }
        return payload;
    }

    private static function baseFlowCommandKeys():Array {
        return [
            "task", "action", "protocolVersion", "sessionId", "flowHandle",
            "panelInstanceId", "documentEpoch", "source", "fixture"
        ];
    }

    private static function validateFlowCommand(command:Object):Boolean {
        return _flow !== undefined && _flow !== null
            && command.task === "cmd"
            && command.protocolVersion === PROTOCOL_VERSION
            && command.sessionId === _flow.sessionId
            && command.flowHandle === _flow.flowHandle
            && command.panelInstanceId === _flow.panelInstanceId
            && command.documentEpoch === _flow.documentEpoch
            && command.source === ChestSessionService.SOURCE_ID
            && command.fixture === ChestSessionService.FIXTURE_ID;
    }

    /** 已被更早 Host command 收养后，迟到 begin success 只能确认同一完整 flow identity。 */
    private static function matchesExactBeginResponseFlow(
            sessionId:String, response:Object):Boolean {
        return _flow !== undefined && _flow !== null
            && _flow.sessionId === sessionId
            && _flow.flowHandle === response.flowHandle
            && _flow.panelInstanceId === response.panelInstanceId
            && _flow.documentEpoch === response.documentEpoch
            && _flow.flowCallId === 1;
    }

    private static function sendPayload(payload:Object):Boolean {
        var transport:Object = getTransport();
        if (transport === undefined || transport === null
                || transport.isSocketConnected !== true
                || typeof transport.sendTaskToNode != "function") return false;
        return transport.sendTaskToNode(SOCKET_TASK, payload, null) === true;
    }

    private static function getTransport():Object {
        if (_transport !== undefined && _transport !== null) return _transport;
        return ServerManager.getInstance();
    }

    private static function acquireS0WebPanelPause():Boolean {
        var acquired:Boolean = false;
        if (_testPauseAcquire !== undefined && _testPauseAcquire !== null) {
            try { acquired = _testPauseAcquire() === true; }
            catch (testAcquireError) { acquired = false; }
        } else {
            // S0 只在 Host panel-idle arm 后可 begin；已有 lease 表示所有权不清，必须拒绝，
            // 不能在失败回包时误释放其它 panel 的全局 lease。
            if (_root === undefined || _root === null
                    || _root.gameCommands === undefined || _root.gameCommands === null
                    || typeof _root.gameCommands["webPanelPause"] != "function"
                    || _root._webPanelPauseLease !== undefined) return false;
            try {
                _root.gameCommands["webPanelPause"]();
                acquired = _root._webPanelPauseLease !== undefined;
            } catch (pauseError) {
                acquired = false;
            }
        }
        _pauseAssertedByS0 = acquired;
        return acquired;
    }

    private static function releaseS0WebPanelPause():Void {
        if (!_pauseAssertedByS0) return;
        _pauseAssertedByS0 = false;
        if (_testPauseRelease !== undefined && _testPauseRelease !== null) {
            try { _testPauseRelease(); } catch (testReleaseError) { }
            return;
        }
        if (_root === undefined || _root === null
                || _root.gameCommands === undefined || _root.gameCommands === null
                || typeof _root.gameCommands["webPanelUnpause"] != "function") return;
        try { _root.gameCommands["webPanelUnpause"](); } catch (unpauseError) { }
    }

    private static function clearRuntimeState(disableService:Boolean):Void {
        if (disableService) {
            ChestSessionService.setDevelopmentEnabled(false);
            ChestSessionService.configureAdapters(undefined, undefined, undefined);
        }
        _localFixtureAuthorized = false;
        _bootstrap = null;
        _flow = null;
        _localSessionId = "";
        _localDocumentEpoch = 0;
        _terminalSent = false;
        _pauseAssertedByS0 = false;
    }

    private static function suspendBootstrap():Void {
        if (_bootstrap === undefined || _bootstrap === null) return;
        _bootstrap.capability = "";
        _bootstrap.acknowledged = false;
        _bootstrap.consumed = true;
    }

    private static function hasExactLocalFixtureShape(target:Object):Boolean {
        return target !== undefined && target !== null
            && typeof target.hasOwnProperty == "function"
            && target.hasOwnProperty("chestS0FixtureId")
            && target.hasOwnProperty("chestS0As2GateId")
            && target.chestS0FixtureId === ChestSessionService.FIXTURE_ID
            && target.chestS0As2GateId === LOCAL_GATE_ID
            && target.presetName === "保险柜"
            && isPositiveInt32(target.row) && isPositiveInt32(target.col);
    }

    private static function sameBootstrap(command:Object, binding:Object):Boolean {
        return command.protocolVersion === binding.protocolVersion
            && command.capability === binding.capability
            && command.connectionGeneration === binding.connectionGeneration
            && command.gameProcessId === binding.gameProcessId
            && command.documentEpoch === binding.documentEpoch
            && command.source === binding.source && command.fixture === binding.fixture
            && command.resumeActive === binding.resumeActive;
    }

    private static function hasExactKeys(value:Object, keys:Array):Boolean {
        if (value === undefined || value === null || typeof value != "object"
                || value instanceof Array) return false;
        var count:Number = 0;
        for (var key:String in value) {
            if (!value.hasOwnProperty(key)) continue;
            if (!arrayContains(keys, key)) return false;
            count++;
        }
        if (count != keys.length) return false;
        for (var i:Number = 0; i < keys.length; i++) {
            if (!value.hasOwnProperty(keys[i])) return false;
        }
        return true;
    }

    private static function arrayContains(values:Array, needle:String):Boolean {
        for (var i:Number = 0; i < values.length; i++) {
            if (values[i] === needle) return true;
        }
        return false;
    }

    private static function isOpaque(value):Boolean {
        if (typeof value != "string" || value.length == 0 || value.length > 256) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (code < 32 || code == 127) return false;
        }
        return value.charCodeAt(0) > 32 && value.charCodeAt(value.length - 1) > 32;
    }

    private static function isPositiveInt32(value):Boolean {
        return typeof value == "number" && (value - value) == 0
            && value >= 1 && value <= 2147483647 && Math.floor(value) == value;
    }

    private static function isNonNegativeInt32(value):Boolean {
        return typeof value == "number" && (value - value) == 0
            && value >= 0 && value <= 2147483647 && Math.floor(value) == value;
    }

    private static function isLimitedResult(value):Boolean {
        return value === "success" || value === "cancel" || value === "failure";
    }

    private static function isTerminalState(value:String):Boolean {
        return value == ChestSessionService.COMPLETED_NO_REWARD
            || value == ChestSessionService.REVOKED
            || value == ChestSessionService.EXPIRED;
    }

    private static function isKnownOpenFailureReason(value:String):Boolean {
        return value == "pre_execution_rejected"
            || value == "post_not_delivered"
            || value == "web_bind_rejected";
    }

    private static function isKnownBeginFailure(value:String):Boolean {
        return value == "schema_mismatch" || value == "capability_rejected"
            || value == "panel_enqueue_failed" || value == "action_not_allowed"
            || value == "busy" || value == "not_dev_repository"
            || value == "environment_gate_closed" || value == "untrusted_origin"
            || value == "source_mismatch" || value == "fixture_mismatch"
            || value == "panel_orchestration_busy" || value == "invalid_document_epoch"
            || value == "document_epoch_mismatch" || value == "invalid_identity"
            || value == "invalid_request" || value == "web_navigation_pending";
    }

    /** TestLoader 专用；生产代码不得注入 transport。 */
    public static function __testOnlySetTransport(transport:Object):Void {
        _transport = transport;
    }

    public static function __testOnlySetPauseAdapters(acquire:Function, release:Function):Void {
        _testPauseAcquire = acquire;
        _testPauseRelease = release;
    }

    public static function __testOnlyReset():Void {
        ChestSessionService.testOnlyReset();
        _transport = undefined;
        _testPauseAcquire = undefined;
        _testPauseRelease = undefined;
        clearRuntimeState(false);
    }
}
