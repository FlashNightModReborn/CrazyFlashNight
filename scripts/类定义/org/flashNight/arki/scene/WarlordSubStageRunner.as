/**
 * 单个 Warlord SubStage 的 AS2 外层 binding 与结果栅栏。
 * 本类不拥有战棋内部规则，也不把 Suspended/Unknown 映射成 GameStage 胜负。
 */
class org.flashNight.arki.scene.WarlordSubStageRunner {
    public static var START_TASK:String = "warlord_stage_start";
    public static var RESULT_ACTION:String = "warlord_stage_result";
    public static var OUTER_CANCELLATION_TASK:String =
        "warlord_stage_outer_cancelled";
    public static var BINDING_SCHEMA:String = "warlord.stage-outer-binding.v1";
    public static var TERMINAL_SCHEMA:String = "warlord.stage-outer-terminal.v1";
    public static var ATTEMPT_SCHEMA:String = "warlord.stage-outer-attempt.v1";
    public static var OUTER_CANCELLATION_SCHEMA:String =
        "warlord.stage-outer-cancellation.v1";
    public static var PLAYER_AVATAR_PORTRAIT_SCHEMA:String = "warlord.player-avatar-portrait.v1";

    private static var MAX_SAFE_INTEGER:Number = 9007199254740991;
    private static var OPAQUE_ID_PATTERN:RegExp = new RegExp(
        "^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$", "");
    private static var TERMINAL_KEYS:Array = [
        "schema", "runId", "subStageId", "scenarioRef", "callId", "revision",
        "terminal", "reasonCode"
    ];
    private static var ATTEMPT_KEYS:Array = [
        "schema", "runId", "subStageId", "scenarioRef", "callId", "revision",
        "result", "reasonCode"
    ];
    private static var callSequence:Number = 0;

    private var binding:Object;
    private var playerAvatarPortrait:Object;
    private var acceptedTerminal:Object = null;
    private var phase:String = "idle";
    private var sender:Object;
    private var observer:Object;
    private var resultHandler:Function;
    private var disposed:Boolean = false;

    public function WarlordSubStageRunner(runId:String, subStageId:String,
            scenarioRef:String, resultObserver:Object, transport:Object) {
        if (!isOpaqueId(runId) || !isOpaqueId(subStageId)
                || !isOpaqueId(scenarioRef)) {
            throw new Error("invalid Warlord outer binding identity");
        }
        observer = resultObserver;
        sender = transport;
        binding = createBinding(runId, subStageId, scenarioRef, 0);
        playerAvatarPortrait = buildPlayerAvatarPortrait();
    }

    /** 首次启动；明确未送达即判定父 GameStage 启动失败。 */
    public function start():Boolean {
        if (disposed || phase != "idle") return false;
        if (!installResultHandler()) {
            failNotStarted("stage.result-handler-unavailable", null);
            return false;
        }
        // 先认领 awaiting，再发送。测试 transport 与同进程 bridge 可以在
        // sendBinding 返回前同步回送 attempt/terminal；该回送必须胜过随后
        // 的 false/throw，不能被覆写回 awaiting。
        phase = "awaiting_terminal";
        var delivered:Boolean = sendBinding(binding);
        if (delivered || phase != "awaiting_terminal") return true;
        failNotStarted("stage.transport-not-started", null);
        return false;
    }

    /** 只接收 exact terminal v1 或 exact attempt v1。 */
    public function handleResult(payload:Object):Object {
        if (disposed) return rejected("late_event");
        var event:Object = parseEvent(payload);
        if (event == null) return rejected("invalid_contract");

        var envelope:Object = event.envelope;
        if (Number(envelope.revision) < Number(binding.revision)) {
            return rejected("late_event");
        }
        if (Number(envelope.revision) > Number(binding.revision)
                || envelope.runId !== binding.runId
                || envelope.subStageId !== binding.subStageId
                || envelope.scenarioRef !== binding.scenarioRef
                || envelope.callId !== binding.callId) {
            return rejected("identity_drift");
        }

        if (acceptedTerminal != null) {
            if (event.kind == "attempt") return rejected("late_event");
            if (sameTerminal(acceptedTerminal, envelope)) {
                return accepted("duplicate", envelope);
            }
            return rejected("terminal_conflict");
        }
        if (phase == "terminal") return rejected("late_event");

        if (event.kind == "attempt") {
            failNotStarted(String(envelope.reasonCode), envelope);
            return accepted("not_started_failed", null);
        }

        acceptedTerminal = cloneTerminal(envelope);
        if (envelope.terminal == "CompleteSubStage"
                || envelope.terminal == "FailStage") {
            phase = "terminal";
            notifyObserver("onWarlordSubStageTerminal", acceptedTerminal);
        } else {
            phase = "frozen";
            notifyObserver("onWarlordSubStageFrozen", acceptedTerminal);
        }
        return accepted("accepted", acceptedTerminal);
    }

    public function getPhase():String { return phase; }

    /** 测试与 coordinator 的只读快照，禁止调用方改写内部 binding。 */
    public function getBindingSnapshot():Object { return cloneBinding(binding); }

    /**
     * 父 GameStage 销毁前的唯一 outer 退役信号。它只携 exact 六字段 binding，
     * 不生成 SubStage 业务 terminal，也不承担场景或战略裁决。
     */
    public function publishOuterCancellation(reasonCode:String):Boolean {
        if (disposed || !isOpaqueId(reasonCode)) return false;
        var target:Object = sender != null ? sender : _root.server;
        if (target == null || typeof target.sendTaskToNode != "function") {
            return false;
        }
        try {
            return target.sendTaskToNode(OUTER_CANCELLATION_TASK, {
                schema:OUTER_CANCELLATION_SCHEMA,
                binding:cloneBinding(binding),
                reasonCode:reasonCode
            }, null) === true;
        } catch (sendError) {
            trace("[WarlordSubStageRunner] outer cancellation failed: "
                + sendError);
            return false;
        }
    }

    public function dispose():Void {
        if (disposed) return;
        disposed = true;
        phase = "disposed";
        acceptedTerminal = null;
        removeResultHandler();
        observer = null;
        sender = null;
    }

    /** ServerManager 已按 action 分流；runner 自己拥有唯一结果 handler。 */
    public function handleHostCommand(command:Object):Object {
        if (disposed) return rejected("late_event");
        if (command == null || typeof command != "object"
                || command instanceof Array || command.task !== "cmd"
                || command.action !== RESULT_ACTION
                || !owns(command, "payload")) {
            return rejected("invalid_contract");
        }
        var result:Object = handleResult(command.payload);
        if (!result.accepted) {
            trace("[WarlordSubStageRunner] rejected Warlord result: "
                + result.reasonCode);
        }
        return result;
    }

    private function installResultHandler():Boolean {
        if (resultHandler != null) return true;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        if (typeof _root.gameCommands[RESULT_ACTION] == "function") {
            return false;
        }
        var self:WarlordSubStageRunner = this;
        resultHandler = function(command:Object):Void {
            self.handleHostCommand(command);
        };
        _root.gameCommands[RESULT_ACTION] = resultHandler;
        return true;
    }

    private function removeResultHandler():Void {
        if (resultHandler == null || _root.gameCommands == undefined) return;
        if (_root.gameCommands[RESULT_ACTION] === resultHandler) {
            delete _root.gameCommands[RESULT_ACTION];
        }
        resultHandler = null;
    }

    private function sendBinding(value:Object, portrait:Object):Boolean {
        var target:Object = sender != null ? sender : _root.server;
        if (target == null || typeof target.sendTaskToNode != "function") return false;
        try {
            return target.sendTaskToNode(START_TASK, {
                binding:cloneBinding(value),
                playerAvatarPortrait:clonePlayerAvatarPortrait(
                    portrait != undefined ? portrait : playerAvatarPortrait)
            }, null) === true;
        } catch (sendError) {
            trace("[WarlordSubStageRunner] start handoff failed: " + sendError);
            return false;
        }
    }

    private function notifyObserver(methodName:String, value:Object):Void {
        if (observer == null || typeof observer[methodName] != "function") return;
        try {
            observer[methodName](value);
        } catch (observerError) {
            trace("[WarlordSubStageRunner] observer " + methodName
                + " failed: " + observerError);
        }
    }

    private function failNotStarted(reasonCode:String, attempt:Object):Void {
        if (disposed || phase == "terminal") return;
        phase = "terminal";
        var failure:Object = attempt != null ? cloneAttempt(attempt) : {
            schema:ATTEMPT_SCHEMA,
            runId:binding.runId,
            subStageId:binding.subStageId,
            scenarioRef:binding.scenarioRef,
            callId:binding.callId,
            revision:binding.revision,
            result:"not_started",
            reasonCode:reasonCode
        };
        notifyObserver("onWarlordSubStageStartFailed", failure);
        removeResultHandler();
    }

    private static function createBinding(runId:String, subStageId:String,
            scenarioRef:String, revision:Number):Object {
        return {
            schema:BINDING_SCHEMA,
            runId:runId,
            subStageId:subStageId,
            scenarioRef:scenarioRef,
            callId:nextCallId(),
            revision:revision
        };
    }

    private static function nextCallId():String {
        callSequence++;
        if (callSequence > 2147483647) callSequence = 1;
        return "warlord.stage." + getTimer() + "." + callSequence;
    }

    private static function parseEvent(payload:Object):Object {
        if (payload == null || typeof payload != "object"
                || payload instanceof Array || !isValidIdentity(payload)
                || !isOpaqueId(payload.reasonCode)) return null;
        if (payload.schema === TERMINAL_SCHEMA) {
            if (!hasExactOwnKeys(payload, TERMINAL_KEYS)
                    || !isTerminalKind(payload.terminal)) return null;
            return {kind:"terminal", envelope:cloneTerminal(payload)};
        }
        if (payload.schema === ATTEMPT_SCHEMA) {
            if (!hasExactOwnKeys(payload, ATTEMPT_KEYS)
                    || payload.result !== "not_started") return null;
            return {kind:"attempt", envelope:cloneAttempt(payload)};
        }
        return null;
    }

    private static function isValidIdentity(value:Object):Boolean {
        return isOpaqueId(value.runId) && isOpaqueId(value.subStageId)
            && isOpaqueId(value.scenarioRef) && isOpaqueId(value.callId)
            && isRevision(value.revision);
    }

    private static function isOpaqueId(value):Boolean {
        return typeof value == "string" && OPAQUE_ID_PATTERN.test(value);
    }

    private static function isRevision(value):Boolean {
        return typeof value == "number" && isFinite(value)
            && Math.floor(Number(value)) == Number(value)
            && Number(value) >= 0 && Number(value) <= MAX_SAFE_INTEGER;
    }

    private static function isTerminalKind(value):Boolean {
        return value === "CompleteSubStage" || value === "FailStage"
            || value === "Suspended" || value === "Unknown";
    }

    private static function hasExactOwnKeys(value:Object, expected:Array):Boolean {
        var count:Number = 0;
        for (var key:String in value) {
            if (!owns(value, key)) continue;
            if (!arrayContainsExact(expected, key)) return false;
            count++;
        }
        if (count != expected.length) return false;
        for (var i:Number = 0; i < expected.length; i++) {
            if (!owns(value, expected[i])) return false;
        }
        return true;
    }

    private static function owns(value:Object, key:String):Boolean {
        return value != null && Object.prototype.hasOwnProperty.call(value, key);
    }

    private static function arrayContainsExact(values:Array, value):Boolean {
        for (var i:Number = 0; i < values.length; i++) {
            if (values[i] === value) return true;
        }
        return false;
    }

    private static function sameTerminal(left:Object, right:Object):Boolean {
        return left.schema === right.schema && left.runId === right.runId
            && left.subStageId === right.subStageId
            && left.scenarioRef === right.scenarioRef
            && left.callId === right.callId && left.revision === right.revision
            && left.terminal === right.terminal
            && left.reasonCode === right.reasonCode;
    }

    private static function cloneBinding(value:Object):Object {
        if (value == null) return null;
        return {schema:value.schema, runId:value.runId,
            subStageId:value.subStageId, scenarioRef:value.scenarioRef,
            callId:value.callId, revision:value.revision};
    }

    /**
     * 只读主角纸娃娃投影：没有角色名、武器、数值、存档或资源 URL。
     * Web 必须继续经 manifest 白名单解析，不得把此 tuple 当成资源定位器。
     */
    private static function buildPlayerAvatarPortrait():Object {
        // 战棋打开、战斗交接与回归时，控制目标可能是临时战斗投影或镜头；
        // 它们都不是角色纸娃娃的持久权威。主角外观始终由 SaveManager
        // 维护在 _root 的当前存档投影中，不能因控制目标切换而漂移。
        var gender:String = portraitText(_root.性别);
        if (gender != "女") gender = "男";
        return {
            schema:PLAYER_AVATAR_PORTRAIT_SCHEMA,
            gender:gender,
            face:portraitText(_root.脸型),
            hair:portraitText(_root.发型),
            equipment:{
                head:portraitEquipment("头部装备"),
                body:portraitEquipment("上装装备"),
                hand:portraitEquipment("手部装备"),
                leg:portraitEquipment("下装装备"),
                foot:portraitEquipment("脚部装备"),
                neck:portraitEquipment("颈部装备")
            }
        };
    }

    /**
     * 装备栏是当前穿戴装备的存档权威；_root 同名字段仅为旧调用点兼容。
     * 已有装备栏 API 时，即使槽位为空也不借用可能过期的 root 值。
     */
    private static function portraitEquipment(slot:String):String {
        var equipment:Object = undefined;
        try {
            equipment = _root.物品栏 != undefined ? _root.物品栏.装备栏 : undefined;
            if (equipment != undefined
                    && typeof equipment.getNameString == "function") {
                return portraitText(equipment.getNameString(slot));
            }
        } catch (ignore) {
            // 旧存档/测试壳没有装备栏 API 时才走兼容 root 字段。
        }
        return portraitText(_root[slot]);
    }

    private static function clonePlayerAvatarPortrait(value:Object):Object {
        if (value == null) return null;
        var equipment:Object = value.equipment != undefined ? value.equipment : {};
        return {
            schema:PLAYER_AVATAR_PORTRAIT_SCHEMA,
            gender:value.gender == "女" ? "女" : "男",
            face:portraitText(value.face), hair:portraitText(value.hair),
            equipment:{
                head:portraitText(equipment.head), body:portraitText(equipment.body),
                hand:portraitText(equipment.hand), leg:portraitText(equipment.leg),
                foot:portraitText(equipment.foot), neck:portraitText(equipment.neck)
            }
        };
    }

    /** FastJSON 的此 wire 不承载自由文本；丢弃控制符、反斜杠与引号。 */
    private static function portraitText(value):String {
        if (value == undefined || value == null) return "";
        var text:String = String(value);
        if (text.length > 128) return "";
        for (var i:Number = 0; i < text.length; i++) {
            var code:Number = text.charCodeAt(i);
            if (code < 32 || text.charAt(i) == "\\" || text.charAt(i) == "\"") {
                return "";
            }
        }
        return text;
    }

    private static function cloneTerminal(value:Object):Object {
        return {schema:value.schema, runId:value.runId,
            subStageId:value.subStageId, scenarioRef:value.scenarioRef,
            callId:value.callId, revision:value.revision,
            terminal:value.terminal, reasonCode:value.reasonCode};
    }

    private static function cloneAttempt(value:Object):Object {
        return {schema:value.schema, runId:value.runId,
            subStageId:value.subStageId, scenarioRef:value.scenarioRef,
            callId:value.callId, revision:value.revision,
            result:value.result, reasonCode:value.reasonCode};
    }

    private static function accepted(disposition:String, terminal:Object):Object {
        return {accepted:true, disposition:disposition, terminal:terminal};
    }

    private static function rejected(reasonCode:String):Object {
        return {accepted:false, disposition:"rejected", reasonCode:reasonCode};
    }
}
