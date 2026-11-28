import org.flashNight.neur.Event.Delegate;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.gesh.path.PathManager;
import org.flashNight.arki.item.LootContainerService;
import org.flashNight.arki.audio.AudioBridge;
import FastJSON;
import org.flashNight.arki.key.KeyManager;
import org.flashNight.arki.render.FrameBroadcaster;

/**
 * ServerManager — AS2 ↔ C# Guardian Launcher 通信管理器（单例）
 *
 * 职责：
 *   1. HTTP 端口发现（POST /testConnection）
 *   2. XMLSocket 端口获取（GET /getSocketPort）
 *   3. XMLSocket 双向通信（JSON + \0 终止符）
 *   4. HTTP 日志批量上报（POST /logBatch）
 *   5. callId 回调路由（异步 task 结果分发）
 *
 * 连接状态机（帧驱动，无 setTimeout/setInterval）：
 *
 *   S_DISCONNECTED(0)
 *     │ delay elapsed && retryCount < MAX
 *     v
 *   S_HTTP_PROBING(1)       ← testConnection(portList[portIndex])
 *     │ success → currentPort = port
 *     v
 *   S_FETCHING_PORT(2)      ← GET /getSocketPort
 *     │ success → socketPort = port
 *     v
 *   S_SOCKET_CONNECTING(3)  ← XMLSocket.connect()
 *     │ success
 *     v
 *   S_CONNECTED(4)
 *     │ onSocketClose
 *     v
 *   S_FETCHING_PORT(2)      ← 重新发现端口（不死守旧端口）
 *
 *   失败路径：任意层失败 → retryCount++ → S_DISCONNECTED → 等待 delay → 重试
 *   超过 MAX_RETRIES 后静止在 S_DISCONNECTED
 */
class org.flashNight.neur.Server.ServerManager {
    public static var instance:ServerManager;
    public var portList:Array;
    public var portIndex:Number;
    public var currentPort:Number;
    private var frameClip:MovieClip;
    public var currentFrame:Number;
    public var gameFrame:Number;
    public var gameFrameAdvanced:Boolean;

    // ==================== 连接状态机 ====================
    private var _state:Number;
    private var _stateEnteredFrame:Number;
    private var _retryCount:Number;
    private var _workerMode:Boolean;
    private var _workerOrigin:String;
    private var _workerRetired:Boolean;

    private static var S_DISCONNECTED:Number      = 0;
    private static var S_HTTP_PROBING:Number       = 1;
    private static var S_FETCHING_PORT:Number      = 2;
    private static var S_SOCKET_CONNECTING:Number  = 3;
    private static var S_CONNECTED:Number          = 4;

    private static var MAX_RETRIES:Number    = 5;
    private static var RETRY_DELAY:Number    = 150; // 5s @30fps

    // ==================== 消息发送 ====================
    private var isSending:Boolean = false;
    private var hasSentThisFrame:Boolean = false;
    private var messageBuffer:String = "";

    // ==================== EventBus ====================
    private var eventBus:EventBus;

    // ==================== XMLSocket ====================
    public var xmlSocket:XMLSocket;
    public var socketHost:String = "localhost";
    public var socketPort:Number = null;
    public var isSocketConnected:Boolean = false;

    private var _inputCell:Object;
    private var _inputWire:Object;
    private var _authoredWorldDrag:Object;
    private var _authoredWorldDragMouse:Object;
    private var _inputResetPending:Boolean = false;

    // ==================== JSON ====================
    private var jsonParser:FastJSON;

    // ==================== Callback 路由 ====================
    private var _callIdCounter:Number;
    private var _pendingCallbacks:Object;
    private static var CALLBACK_TIMEOUT_MS:Number = 20000;

    // Audio Platform v2 exact envelopes. BGM result intentionally has no task field.
    private static var AUDIO_BGM_RESULT_KEYS:Array = [
        "wireRevision", "requestId", "audioSessionId",
        "audioReadyGeneration", "deviceGeneration", "operation",
        "completionState", "category", "stage", "nativeCode", "hresult",
        "decoderBackend", "messageKey"
    ];
    private static var AUDIO_READY_KEYS:Array = [
        "task", "wireRevision", "audioSessionId", "audioReadyGeneration",
        "deviceGeneration", "loaded", "failed", "overrides",
        "capabilityDigest"
    ];
    private static var AUDIO_UNAVAILABLE_KEYS:Array = [
        "task", "wireRevision", "audioSessionId", "audioReadyGeneration",
        "deviceGeneration", "category", "messageKey"
    ];
    private static var JUKEBOX_PLAY_COMMAND_KEYS:Array = [
        "task", "action", "title"
    ];

    // ==================== 状态名称（调试用）====================
    private static var STATE_NAMES:Array = [
        "DISCONNECTED", "HTTP_PROBING", "FETCHING_PORT", "SOCKET_CONNECTING", "CONNECTED"
    ];

    // 构造函数
    public function ServerManager() {
        if (instance != null) {
            trace("ServerManager 已经实例化。");
            return;
        }
        instance = this;

        portList = [];
        portIndex = 0;
        currentPort = null;
        currentFrame = 0;
        gameFrame = 0;
        gameFrameAdvanced = false;
        _inputCell = _root.GameInput;
        _state = S_DISCONNECTED;
        _stateEnteredFrame = 0;
        _retryCount = 0;

        _workerMode = String(_root.cf7ArenaWorker || "") == "1"
            || readWorkerLaunchField("cf7ArenaWorker") == "1";
        if (_workerMode) {
            _root.cf7ArenaWorker = "1";
            if (_root.cf7ArenaWorkerId == undefined)
                _root.cf7ArenaWorkerId = readWorkerLaunchField("cf7ArenaWorkerId");
            if (_root.cf7ArenaSessionEpoch == undefined)
                _root.cf7ArenaSessionEpoch = readWorkerLaunchField("cf7ArenaSessionEpoch");
            if (_root.cf7WorkerProjectionVersion == undefined)
                _root.cf7WorkerProjectionVersion = readWorkerLaunchField("cf7WorkerProjectionVersion");
        }
        _workerRetired = false;
        _workerOrigin = String(_root._url || "").split("?")[0];
        _workerOrigin = _workerOrigin.split("\\").join("/");
        eventBus = EventBus.getInstance();
        if (!_workerMode) extractPorts();
        initFrameClip();

        // Subscribe internal functions to frameUpdate event
        eventBus.subscribe("frameUpdate", onFrameUpdate, this);

        // Initialize JSON parser
        jsonParser = new FastJSON();

        // Callback 路由初始化
        _callIdCounter = 0;
        _pendingCallbacks = {};

        // 启动连接：先尝试读端口文件快速连接，失败则 fallback 盲扫
        if (!_workerMode) {
            org.flashNight.neur.Server.Issue205SourceProbe.install();
            org.flashNight.neur.Server.AgentHarnessService.install();
        }
        tryLoadPortsFile();
    }

    /**
     * 尝试从 launcher_ports.json 读取端口，实现快速连接。
     * 成功：直接用文件中的 httpPort 跳过盲扫，进入 FETCHING_PORT。
     * 失败：fallback 到 S_HTTP_PROBING 盲扫。
     */
    private function tryLoadPortsFile():Void {
        // PathManager 提供项目根路径（兼容 testMovie / 游戏 / Steam 环境）
        if (!PathManager.isEnvironmentValid()) {
            PathManager.initialize(null);
        }
        var base:String = _workerMode
            ? _workerOrigin.substring(0, _workerOrigin.lastIndexOf("/") + 1)
            : PathManager.getBasePath();
        if (base == null || base.length == 0) {
            trace("[ServerManager] No basePath, fallback to blind scan");
            transitionTo(S_HTTP_PROBING);
            return;
        }

        var portsUrl:String = base + "launcher_ports.json";
        trace("[ServerManager] Trying ports file: " + portsUrl);

        var lv:LoadVars = new LoadVars();
        lv.onData = function(rawData:String):Void {
            if (rawData == null || rawData == undefined) {
                trace("[ServerManager] Ports file not found, fallback to blind scan");
                ServerManager.instance.transitionTo(ServerManager.S_HTTP_PROBING);
                return;
            }

            if (ServerManager.instance._workerMode || rawData.indexOf("\"arenaWorker\"") >= 0) {
                // A Worker descriptor can never silently become legacy discovery,
                // even if a projector failed to expose the launch query variables.
                ServerManager.instance._workerMode = true;
                ServerManager.instance.acceptWorkerPorts(rawData);
                return;
            }

            // 手动解析简单 JSON: {"httpPort":1192,"socketPort":1924,"pid":12345}
            var hp:Number = ServerManager.instance.extractJsonNumber(rawData, "httpPort");
            var sp:Number = ServerManager.instance.extractJsonNumber(rawData, "socketPort");

            if (isNaN(hp) || hp <= 0) {
                trace("[ServerManager] Invalid httpPort in ports file, fallback");
                ServerManager.instance.transitionTo(ServerManager.S_HTTP_PROBING);
                return;
            }

            trace("[ServerManager] Ports file: httpPort=" + hp + " socketPort=" + sp);
            ServerManager.instance.currentPort = hp;
            if (!isNaN(sp) && sp > 0) {
                ServerManager.instance.socketPort = sp;
                // 直接跳到 socket 连接（httpPort 和 socketPort 都已知）
                ServerManager.instance.transitionTo(ServerManager.S_SOCKET_CONNECTING);
            } else {
                // 只有 httpPort，走正常 FETCHING_PORT 获取 socketPort
                ServerManager.instance.transitionTo(ServerManager.S_FETCHING_PORT);
            }
        };
        lv.load(portsUrl);
    }

    /**
     * 从简单 JSON 字符串中提取数字字段值。
     * 不依赖 FastJSON，避免在连接建立前引入复杂解析。
     * 容忍 "key" : 123 和 "key":123 两种格式（跳过冒号后的空白）。
     */
    private function extractJsonNumber(json:String, key:String):Number {
        var search:String = "\"" + key + "\"";
        var idx:Number = json.indexOf(search);
        if (idx < 0) return NaN;
        idx += search.length;
        // 跳过空白
        while (idx < json.length && json.charAt(idx) <= " ") idx++;
        // 期望冒号
        if (idx >= json.length || json.charAt(idx) != ":") return NaN;
        idx++;
        // 跳过空白
        while (idx < json.length && json.charAt(idx) <= " ") idx++;
        // 读取数字
        var end:Number = idx;
        while (end < json.length) {
            var c:String = json.charAt(end);
            if (c == "," || c == "}" || c <= " ") break;
            end++;
        }
        return Number(json.substring(idx, end));
    }

    private function readWorkerLaunchField(key:String):String {
        var url:String = String(_root._url || "");
        var queryAt:Number = url.indexOf("?");
        if (queryAt < 0) return "";
        var fields:Array = url.substr(queryAt + 1).split("&");
        var prefix:String = key + "=";
        for (var i:Number = 0; i < fields.length; i++) {
            if (String(fields[i]).indexOf(prefix) == 0)
                return unescape(String(fields[i]).substr(prefix.length));
        }
        return "";
    }

    private function acceptWorkerPorts(rawData:String):Void {
        var descriptor:Object = jsonParser.parse(rawData);
        var hp:Number = Number(descriptor.httpPort);
        var sp:Number = Number(descriptor.socketPort);
        var actualOrigin:String = unescape(_workerOrigin).split("|").join(":").toLowerCase();
        var expectedOrigin:String = unescape(String(descriptor.swfOrigin || "")).split("|").join(":").toLowerCase();
        if (descriptor.arenaWorker !== true
                || String(descriptor.workerId || "") == ""
                || String(descriptor.sessionEpoch || "") == ""
                || descriptor.workerId !== _root.cf7ArenaWorkerId
                || descriptor.sessionEpoch !== _root.cf7ArenaSessionEpoch
                || actualOrigin != expectedOrigin
                || !(hp > 0 && hp < 65536) || hp != Math.floor(hp)
                || !(sp > 0 && sp < 65536) || sp != Math.floor(sp) || hp == sp) {
            _workerRetired = true;
            transitionTo(S_DISCONNECTED);
            trace("[ServerManager] Worker descriptor identity rejected");
            return;
        }
        currentPort = hp;
        socketPort = sp;
        socketHost = "127.0.0.1";
        transitionTo(S_SOCKET_CONNECTING);
    }

    // 获取单例实例
    public static function getInstance():ServerManager {
        if (instance == null) {
            instance = new ServerManager();
        }
        return instance;
    }

    // ==================== 状态机核心 ====================

    /**
     * 状态转换 + 入口动作。所有状态变更必须通过此方法。
     */
    private function transitionTo(newState:Number):Void {
        if (_workerMode && (newState == S_HTTP_PROBING || newState == S_FETCHING_PORT)) {
            _workerRetired = true;
            newState = S_DISCONNECTED;
        }
        var oldState:Number = _state;
        _state = newState;
        _stateEnteredFrame = currentFrame;

        // 更新 isSocketConnected（FrameBroadcaster 等外部代码读取此字段）
        isSocketConnected = (newState == S_CONNECTED);

        trace("[FSM] " + STATE_NAMES[oldState] + " -> " + STATE_NAMES[newState]
              + " (retry=" + _retryCount + ", frame=" + currentFrame + ")");

        // 入口动作
        switch (newState) {
            case S_HTTP_PROBING:
                if (portIndex < portList.length) {
                    testConnection(portList[portIndex]);
                } else {
                    // 无可用端口，回到 DISCONNECTED
                    portIndex = 0;
                    _retryCount++;
                    transitionTo(S_DISCONNECTED);
                }
                break;

            case S_FETCHING_PORT:
                getSocketPort();
                break;

            case S_SOCKET_CONNECTING:
                initXMLSocket();
                break;

            // S_DISCONNECTED, S_CONNECTED: 无入口动作，由 onFrameUpdate 驱动
        }
    }

    // ==================== 端口提取 ====================

    public function extractPorts():Void {
        var eyeOf119:String = (_root.闪客之夜 != undefined) ? _root.闪客之夜.toString() : "1192433993";
        trace("Extracting ports from eyeOf119: " + eyeOf119);

        // 提取4位数的端口
        for (var i:Number = 0; i <= eyeOf119.length - 4; i++) {
            var port4:String = eyeOf119.substring(i, i + 4);
            var port4Num:Number = Number(port4);
            if (isValidPort(port4Num) && !containsPort(port4Num)) {
                portList.push(port4Num);
            }
        }

        // 提取5位数的端口
        for (var j:Number = 0; j <= eyeOf119.length - 5; j++) {
            var port5:String = eyeOf119.substring(j, j + 5);
            var port5Num:Number = Number(port5);
            if (isValidPort(port5Num) && !containsPort(port5Num)) {
                portList.push(port5Num);
            }
        }

        // 确保端口3000被加入
        if (!containsPort(3000) && isValidPort(3000)) {
            portList.push(3000);
        }

        // 去重
        var uniquePorts:Object = {};
        var finalPortList:Array = [];
        for (var k:Number = 0; k < portList.length; k++) {
            var port:Number = portList[k];
            if (uniquePorts[port] == undefined) {
                uniquePorts[port] = true;
                finalPortList.push(port);
            }
        }
        portList = finalPortList;

        trace("Final extracted ports: " + portList.join(", "));
    }

    private function isValidPort(port:Number):Boolean {
        return (port >= 1024 && port <= 65535);
    }

    private function containsPort(port:Number):Boolean {
        for (var i:Number = 0; i < portList.length; i++) {
            if (portList[i] == port) {
                return true;
            }
        }
        return false;
    }

    // ==================== 帧驱动 ====================

    private function initFrameClip():Void {
        var MAX_DEPTH:Number = 1048575;
        frameClip = _root.createEmptyMovieClip("ServerManagerFrameClip", MAX_DEPTH);
        frameClip.onEnterFrame = Delegate.create(this, onEnterFrameHandler);
    }

    public function onEnterFrameHandler():Void {
        currentFrame++;
        if (this._inputCell != null && this._inputCell.passiveActive === true) commitPassiveInput();
        // 本拍只采样一次。分发中取得或释放的暂停租约从下一拍生效。
        gameFrameAdvanced = (_root.暂停 !== true);
        if (gameFrameAdvanced) gameFrame++;
        eventBus.publish("frameUpdate", currentFrame);
        hasSentThisFrame = false;
    }

    public function onFrameUpdate(currentFrame:Number):Void {
        // ---- 状态机 tick ----
        if (_state == S_DISCONNECTED) {
            // 等待重连延迟
            if (!_workerRetired && _retryCount < MAX_RETRIES
                && (currentFrame - _stateEnteredFrame) >= RETRY_DELAY) {
                transitionTo(_workerMode && socketPort > 0 ? S_SOCKET_CONNECTING : S_HTTP_PROBING);
            }
        }

        // ---- S_CONNECTED 业务逻辑 ----
        if (_state == S_CONNECTED) {
            // 发送 HTTP 日志缓冲区
            if (!isSending && messageBuffer.length > 0 && currentPort != null && !hasSentThisFrame) {
                sendMessageBuffer();
            }
        }

        // ---- Callback 超时扫描（所有状态都执行，确保断线后也能清理）----
        // 期限按 getTimer 墙钟毫秒判定：帧率漂移不再改变真实超时；
        // 60 帧扫描节拍只影响探测粒度（最坏延迟 ~2s@30fps），不改变期限本身。
        if (currentFrame % 60 === 0) {
            var now:Number = getTimer();
            for (var k:String in _pendingCallbacks) {
                var e:Object = _pendingCallbacks[k];
                var timeoutMs:Number = (e.timeoutMs != undefined && !isNaN(e.timeoutMs) && e.timeoutMs > 0)
                    ? e.timeoutMs
                    : CALLBACK_TIMEOUT_MS;
                if (now - e.sentAt > timeoutMs) {
                    delete _pendingCallbacks[k];
                    e.cb({success: false, error: "callback timeout"});
                }
            }
        }

        // native_dialogue §4.6 等待业务提交冲刷：rewardPending 解除后重验
        // 会话身份与 epoch 再提交终态。早期返回廉价（无会话/无义务即退）；
        // 逐帧驱动使 pending 解除后下一帧即提交，不依赖 Host 重试节拍。
        // 必须在帧泵而非暂停 watch 分发内执行——claim 释放嵌套在 watch
        // 分发中会被外层折叠回 true。
        org.flashNight.arki.dialogue.NativeDialogueService.tryAwaitingCommit();
    }

    // ==================== HTTP 端口探测 ====================

    // 保留公共接口兼容性（通信_fs_本地服务器.as 的兼容代理可能调用）
    public function getAvailablePort():Void {
        if (_state == S_DISCONNECTED || _state == S_CONNECTED) {
            _retryCount = 0;
            transitionTo(S_HTTP_PROBING);
        }
    }

    private function testConnection(port:Number):Void {
        var lv:LoadVars = new LoadVars();
        lv.onLoad = function(success:Boolean):Void {
            if (success) {
                ServerManager.instance.onPortSuccess(port);
            } else {
                ServerManager.instance.onPortFailure(port);
            }
        };
        lv.sendAndLoad("http://localhost:" + port + "/testConnection", lv, "POST");
    }

    private function onPortSuccess(port:Number):Void {
        // 防止过期回调：只在 HTTP_PROBING 状态处理
        if (_state != S_HTTP_PROBING) return;

        trace("Connected to HTTP server on port: " + port);
        currentPort = port;
        _retryCount = 0;
        transitionTo(S_FETCHING_PORT);
    }

    private function onPortFailure(port:Number):Void {
        if (_state != S_HTTP_PROBING) return;

        trace("Failed to connect to HTTP server on port: " + port);
        portIndex++;
        if (portIndex >= portList.length) {
            portIndex = 0;
            // 整轮循环完毕才计为一次重试（而非每个端口失败都计数）
            _retryCount++;
        }
        transitionTo(S_DISCONNECTED);
    }

    // ==================== Socket 端口获取 ====================

    private function getSocketPort():Void {
        var lv:LoadVars = new LoadVars();
        lv.onLoad = function(success:Boolean):Void {
            if (success) {
                var response:Object = this;
                if (response.socketPort != undefined) {
                    ServerManager.instance.onSocketPortReceived(Number(response.socketPort));
                } else {
                    ServerManager.instance.onSocketPortFailed("no socketPort in response");
                }
            } else {
                ServerManager.instance.onSocketPortFailed("HTTP load failed");
            }
        };
        lv.load("http://localhost:" + currentPort + "/getSocketPort");
    }

    private function onSocketPortReceived(port:Number):Void {
        if (_state != S_FETCHING_PORT) return;

        socketPort = port;
        trace("Retrieved XMLSocket port: " + socketPort);
        transitionTo(S_SOCKET_CONNECTING);
    }

    private function onSocketPortFailed(reason:String):Void {
        if (_state != S_FETCHING_PORT) return;

        trace("Failed to get socket port: " + reason);
        _retryCount++;
        transitionTo(S_DISCONNECTED);
    }

    // ==================== XMLSocket ====================

    public function initXMLSocket():Void {
        retirePassiveInput();
        var self = this;
        var socket:XMLSocket = new XMLSocket();
        xmlSocket = socket;
        socket.onConnect = function(success:Boolean):Void {
            if (self.xmlSocket !== socket) return;
            self.onSocketConnect(success);
        };
        socket.onData = function(data:String):Void {
            if (self.xmlSocket !== socket || !self.isSocketConnected) return;
            self.onSocketData(data);
        };
        socket.onClose = function():Void {
            if (self.xmlSocket !== socket) return;
            self.onSocketClose();
        };

        if (socketPort == null) {
            trace("Socket port not available. Cannot connect.");
            _retryCount++;
            transitionTo(S_DISCONNECTED);
            return;
        }
        socket.connect(socketHost, socketPort);
    }

    private function onSocketConnect(success:Boolean):Void {
        if (_state != S_SOCKET_CONNECTING) return;

        if (success) {
            trace("XMLSocket connected to server on port: " + socketPort);
            _retryCount = 0;
            transitionTo(S_CONNECTED);
            // Transport ready is not audio ready. Clear any prior tuple and wait for
            // an exact audio_ready from this live socket.
            AudioBridge.onTransportConnected();
            _root.帧计时器.scheduler.onTransportConnected();
        } else {
            trace("Failed to connect XMLSocket to server on port: " + socketPort);
            _retryCount++;
            transitionTo(S_DISCONNECTED);
        }
    }

    // I1's serial commit point is the system frame, including while gameplay is paused.
    // The socket callbacks own only the inbox, except for closing an unavailable gate.
    private static function inputUInt(value:String, minimum:Number):Number {
        if (typeof value != "string") return -1;
        var count:Number = length(value);
        if (count == 0 || count > 10 || (count > 1 && value.charAt(0) === "0")) return -1;
        var n:Number = 0;
        for (var i:Number = 0; i < count; ++i) {
            var digit:Number = value.charCodeAt(i) - 48;
            if (digit < 0 || digit > 9) return -1;
            n = n * 10 + digit;
        }
        return n < minimum || n > 2147483647 ? -1 : n;
    }

    private static function inputToken(value:String):Boolean {
        if (typeof value != "string") return false;
        var count:Number = length(value);
        if (count == 0 || count > 96) return false;
        for (var i:Number = 0; i < count; ++i) {
            var ch:Number = value.charCodeAt(i);
            if ((ch >= 48 && ch <= 57) || (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122)
                    || ch == 45 || ch == 46 || ch == 95) continue;
            return false;
        }
        return true;
    }

    private function onInputWire(data:String):Void {
        var count:Number = length(data);
        if (count > 4096 || data.substr(0, 3) !== "I1|") {
            faultInput("input_wire_version_or_size", 0);
            return;
        }
        for (var i:Number = 0; i < count; ++i) {
            var ch:Number = data.charCodeAt(i);
            if (ch < 32 || ch > 126) {
                faultInput("input_wire_characters", 0);
                return;
            }
        }

        var parts:Array = data.split("|");
        var state:Object = _inputWire;
        var connection:Number = inputUInt(parts[3], 1);
        if (length(parts[2]) != 32 || connection < 1) {
            faultInput("input_wire_identity", 0);
            return;
        }
        for (i = 0; i < 32; ++i) {
            ch = parts[2].charCodeAt(i);
            if ((ch < 48 || ch > 57) && (ch < 97 || ch > 102)) {
                faultInput("input_wire_identity", 0);
                return;
            }
        }
        if (state != null && (parts[2] !== state.session || connection !== state.connection)) return;
        if (parts[1] === "Bind") {
            bindPassiveInput(parts, connection);
            return;
        }
        if (state == null) return;
        switch (parts[1]) {
            case "InputBatch": stageInputBatch(state, parts); break;
            case "WorldPointerCancel": stageWorldPointerCancel(state, parts); break;
            case "Cancel": stageInputCancel(state, parts); break;
            case "Cancelled":
                if (parts.length == 11 && parts[9] === "1" && parts[10] === "1"
                        && parts.slice(2, 9).join("|") === state.localCancel) {
                    _inputCell.lastHostCancelled = state.localCancel;
                    state.localCancel = null;
                }
                break;
            case "K": stageComboResult(state, parts, data); break;
            default: faultInput("input_wire_kind", 0); break;
        }
    }

    private function bindPassiveInput(parts:Array, connection:Number):Void {
        var cell:Object = _inputCell;
        if (cell == null) return;
        if (cell.facadeInstalled !== true || parts.length != 7 || parts[4] !== "15"
                || parts[5] !== "1" || parts[6] !== "64") {
            faultInput("input_wire_capability", 0);
            return;
        }

        var session:String = parts[2];
        if (_inputWire == null) {
            _inputWire = {session:session, connection:connection, receivedEpoch:0, receivedBatch:0,
                observationGeneration:0, observedThrough:0, revokedEpoch:0, inputFrameSeq:0,
                highestTicket:0, receipts:{}, worldPointerCancelTicket:0};
            cell.sessionId = session;
            cell.connectionIncarnation = connection;
            cell.bound = true;
            cell.passiveActive = true;
            installAuthoredWorldDragMouse();
            closeInputSnapshot(cell, 0);
            var timer:Object = _root.帧计时器;
            if (timer != null) timer.dfaSentToLauncher = false;
            _inputResetPending = true;
            trace("[I1] Bound C=" + connection);
        }
        sendSocketMessage("I1|Capability|" + session + "|" + connection + "|15|1|64");
    }

    private function faultInput(reason:String, epoch:Number):Void {
        var state:Object = _inputWire;
        if (state == null) {
            if (_inputCell != null && _inputCell.passiveActive === true) _inputCell.lastFault = reason;
            return;
        }
        if (state.fault != null) return;
        var knownEpoch:Number = Math.max(state.receivedEpoch, _inputCell.snapshot.keyboardEpoch);
        state.fault = reason;
        // Prefer the grant we have actually seen over a future epoch in a broken packet.
        state.faultEpoch = knownEpoch > state.revokedEpoch ? knownEpoch : (epoch > state.revokedEpoch ? epoch : 0);
    }

    private function stageInputBatch(state:Object, parts:Array):Void {
        if (state.fault != null || state.localCancel != null) return;
        var epoch:Number = inputUInt(parts[4], 1);
        if (epoch > 0 && (epoch <= state.revokedEpoch || epoch < state.receivedEpoch
                || (state.cancel != null && epoch <= state.cancel.epoch))) return;
        if (parts.length != 11 || epoch < 1) {
            faultInput("input_batch_fields", epoch);
            return;
        }
        if (state.needsCancel === true) {
            faultInput("input_epoch_unqualified", epoch);
            return;
        }

        var batchSeq:Number = inputUInt(parts[5], 1);
        var obsGen:Number = inputUInt(parts[6], 1);
        var obsThrough:Number = inputUInt(parts[7], 0);
        var edgeCount:Number = inputUInt(parts[9], 0);
        if (batchSeq < 1 || obsGen < 1 || obsThrough < 0 || edgeCount < 0 || edgeCount > 64) {
            faultInput("input_batch_fields", epoch);
            return;
        }

        var newEpoch:Boolean = epoch !== state.receivedEpoch;
        var previousBatch:Number = newEpoch ? 0 : state.receivedBatch;
        if (batchSeq <= previousBatch) return;
        if (batchSeq !== previousBatch + 1 || (!newEpoch && (obsGen !== state.observationGeneration
                || obsThrough < state.observedThrough))) {
            faultInput("input_sequence", epoch);
            return;
        }

        var words:Array = inputBitmap(parts[8]);
        if (words == null || (edgeCount == 0 ? parts[10] !== "-" : parts[10] === "-")) {
            faultInput("input_batch_bitmap_or_edges", epoch);
            return;
        }
        var rows:Array = edgeCount == 0 ? _inputCell.noEdges : String(parts[10]).split(";");
        if (rows.length !== edgeCount) {
            faultInput("input_batch_edge_count", epoch);
            return;
        }
        var earlier:Object = newEpoch ? null : state.staged;
        var stagedCount:Number = (earlier == null ? 0 : earlier.edgeCount) + edgeCount;
        if (stagedCount > 64) {
            faultInput("input_edges_overflow", epoch);
            return;
        }
        var priorWords:Array = newEpoch ? _inputCell.neutralWords
            : (earlier != null ? earlier.words : _inputCell.snapshot.words);
        var edges:Array = inputEdges(rows, newEpoch ? 0 : state.observedThrough, obsThrough, priorWords, words);
        if (edges == null) {
            faultInput("input_projection", epoch);
            return;
        }
        var stagedEdges:Array = earlier == null ? [] : earlier.edges;
        for (var i:Number = 0; i < edges.length; ++i) stagedEdges.push(edges[i]);
        state.staged = {epoch:epoch, seq:batchSeq, words:words, edges:stagedEdges, edgeCount:stagedCount};
        state.receivedEpoch = epoch;
        state.receivedBatch = batchSeq;
        state.observationGeneration = obsGen;
        state.observedThrough = obsThrough;
    }

    private function inputBitmap(hex:String):Array {
        if (length(hex) != 64) return null;
        var words:Array = [];
        var at:Number = 0;
        for (var word:Number = 0; word < 8; ++word) {
            var value:Number = 0;
            for (var n:Number = 0; n < 8; ++n) {
                var digit:Number = hex.charCodeAt(at++);
                if (digit >= 48 && digit <= 57) digit -= 48;
                else if (digit >= 65 && digit <= 70) digit -= 55;
                else return null;
                value = value * 16 + digit;
            }
            words[word] = value;
        }
        return words;
    }

    private function inputEdges(rows:Array, previousSeq:Number, observedThrough:Number,
                                priorWords:Array, words:Array):Array {
        var projected:Array = priorWords.slice();
        var edges:Array = [];
        for (var i:Number = 0; i < rows.length; ++i) {
            var fields:Array = String(rows[i]).split(",");
            if (fields.length != 3) return null;
            var seq:Number = inputUInt(fields[0], 1);
            var vk:Number = inputUInt(fields[1], 0);
            var direction:String = fields[2];
            if (seq <= previousSeq || seq > observedThrough || vk < 0 || vk > 255
                    || (direction !== "D" && direction !== "U")) return null;
            previousSeq = seq;
            var index:Number = vk >>> 5;
            var bit:Number = 1 << (vk & 31);
            var down:Boolean = direction === "D";
            var wasDown:Boolean = (projected[index] & bit) != 0;
            // An observed Up for an already suppressed key is a physical fact only.
            if (down && wasDown) return null;
            if (!down && !wasDown) continue;
            projected[index] = (down ? projected[index] | bit : projected[index] & ~bit) >>> 0;
            edges.push({seq:seq, vk:vk, down:down});
        }
        for (var word:Number = 0; word < 8; ++word) {
            if (projected[word] !== words[word]) return null;
        }
        return edges;
    }

    private function stageInputCancel(state:Object, parts:Array):Void {
        var epoch:Number = inputUInt(parts[5], 1);
        var ticket:Number = inputUInt(parts[6], 1);
        var currentEpoch:Number = Math.max(state.receivedEpoch, _inputCell.snapshot.keyboardEpoch);
        if (parts.length != 10 || ticket < 1 || epoch < 1 || !inputToken(parts[9])) {
            if (epoch < 1 || epoch >= currentEpoch) faultInput("input_cancel_fields", epoch);
            return;
        }
        if (parts[4] !== "Game" || parts[7] !== "AS2" || inputUInt(parts[8], 1) !== state.connection) return;

        var identity:String = parts.slice(2, 9).join("|");
        var receipt:Object = state.receipts[ticket];
        if (receipt != null) {
            if (receipt.identity === identity) sendSocketMessage(receipt.wire);
            return;
        }
        if (state.cancel != null || ticket <= state.highestTicket || epoch < currentEpoch
                || (epoch <= state.revokedEpoch && !(epoch === state.revokedEpoch && state.localCancel != null))
                || (epoch > currentEpoch && _inputCell.gateOpen === true && state.fault == null)) return;
        // A grant may be revoked before its first batch reaches Flash.
        state.cancel = {epoch:epoch, ticket:ticket, identity:identity};
    }

    private function stageComboResult(state:Object, parts:Array, wire:String):Void {
        if (_inputCell.gateOpen !== true || state.fault != null || state.cancel != null) return;
        var epoch:Number = inputUInt(parts[4], 1);
        if (epoch > 0 && epoch !== _inputCell.snapshot.keyboardEpoch) return;
        if (parts.length != 15 || epoch < 1) {
            faultInput("input_combo_fields", epoch);
            return;
        }
        var inputFrame:Number = inputUInt(parts[5], 1);
        var actor:Number = inputUInt(parts[6], 1);
        var module:Number = inputUInt(parts[7], 0);
        var moduleInc:Number = inputUInt(parts[8], 1);
        var config:Number = inputUInt(parts[9], 1);
        var commandSeq:Number = inputUInt(parts[10], 0);
        var cmdId:Number = inputUInt(parts[11], 0);
        if (inputFrame < 1 || actor < 1 || module < 0 || module > 2 || moduleInc < 1
                || config < 1 || commandSeq < 0 || cmdId < 0 || ((cmdId == 0) != (commandSeq == 0))) {
            faultInput("input_combo_fields", epoch);
            return;
        }

        var fault:String = FrameBroadcaster.stageVersionedResult({
            epoch:epoch, inputFrameSeq:inputFrame, actorInc:actor, moduleId:module,
            moduleInc:moduleInc, configInc:config, commandSeq:commandSeq, cmdId:cmdId,
            cmdName:unescape(parts[12]), hintsJson:parts[14], wire:wire
        });
        if (fault != null) faultInput(fault, epoch);
    }

    public function faultPassiveCombo(reason:String):Void {
        if (_inputCell.gateOpen === true) faultInput(reason, _inputCell.snapshot.keyboardEpoch);
    }

    private function closeInputSnapshot(cell:Object, epoch:Number):Void {
        cell.gateOpen = false;
        cell.snapshot = {systemFrame:currentFrame, inputFrameSeq:cell.bound ? _inputWire.inputFrameSeq : 0,
            keyboardEpoch:epoch, words:cell.neutralWords, edges:cell.noEdges};
    }

    public function beginAuthoredWorldDrag(instance:Object):Boolean {
        if (instance == null || _authoredWorldDrag != null) return false;
        if (_root.cf7R1PassiveInput == "1" || _inputCell.passiveActive === true) {
            if (_inputWire == null || _inputWire.worldPointerCancel != null ||
                    _inputCell.gateOpen !== true) return false;
        }
        _authoredWorldDrag = instance;
        return true;
    }

    public function endAuthoredWorldDrag(instance:Object):Boolean {
        if (_authoredWorldDrag == null || _authoredWorldDrag !== instance) return false;
        _authoredWorldDrag = null;
        if (_inputWire != null) _inputWire.mouseWorldDrag = null;
        return true;
    }

    private function cancelAuthoredWorldDrag():Boolean {
        if (_authoredWorldDrag == null) return false;
        _authoredWorldDrag = null;
        if (_inputWire != null) _inputWire.mouseWorldDrag = null;
        _root.stopDrag();
        _root.鼠标.gotoAndStop("手型普通");
        return true;
    }

    private function installAuthoredWorldDragMouse():Void {
        if (_authoredWorldDragMouse != null) return;
        var server:ServerManager = this;
        _authoredWorldDragMouse = {
            onMouseDown:function():Void { server.onAuthoredWorldMouseDown(); },
            onMouseUp:function():Void { server.onAuthoredWorldMouseUp(); }
        };
        Mouse.addListener(_authoredWorldDragMouse);
    }

    private function canRecoverAuthoredWorldPointer(state:Object, receipt:Object):Boolean {
        return _inputCell.bound === true && _inputCell.passiveActive === true && _inputCell.gateOpen === true
                && _inputCell.connectionIncarnation === state.connection && state.cancel == null
                && state.fault == null && state.needsCancel !== true && state.localCancel == null
                && state.worldPointerCancel == null && state.lastWorldPointerReceipt === receipt
                && _authoredWorldDrag == null;
    }

    private function onAuthoredWorldMouseDown():Void {
        var state:Object = _inputWire;
        if (state == null) return;
        state.mouseWorldClose = null;
        var resume:Object = state.worldDragResume;
        if (resume == null) return;
        // The first real AVM1 primary Down consumes the recovery ticket.
        state.worldDragResume = null;
        if (!canRecoverAuthoredWorldPointer(state, resume.receipt)) return;
        var instance:Object = resume.instance;
        if (instance.resumeAuthoredWorldDrag() === true && _authoredWorldDrag === instance) {
            state.mouseWorldDrag = instance;
        } else if (typeof instance.isAuthoredWorldCloseHit == "function"
                && typeof instance.releaseAuthoredWorldClose == "function"
                && instance.isAuthoredWorldCloseHit() === true) {
            state.mouseWorldClose = {instance:instance, receipt:resume.receipt,
                keyboardEpoch:_inputCell.snapshot.keyboardEpoch};
        }
    }

    private function onAuthoredWorldMouseUp():Void {
        var state:Object = _inputWire;
        if (state == null) return;
        var close:Object = state.mouseWorldClose;
        state.mouseWorldClose = null;
        if (close != null && close.keyboardEpoch === _inputCell.snapshot.keyboardEpoch
                && canRecoverAuthoredWorldPointer(state, close.receipt)) {
            close.instance.releaseAuthoredWorldClose();
        }
        var instance:Object = state.mouseWorldDrag;
        if (instance == null || _authoredWorldDrag !== instance) return;
        state.mouseWorldDrag = null;
        instance.releaseAuthoredWorldDrag();
    }

    public function retireAuthoredWorldDragInstance(instance:Object):Void {
        var state:Object = _inputWire;
        if (state != null) {
            if (state.worldDragResume != null && state.worldDragResume.instance === instance) state.worldDragResume = null;
            if (state.mouseWorldClose != null && state.mouseWorldClose.instance === instance) state.mouseWorldClose = null;
        }
        if (_authoredWorldDrag === instance && instance != null) cancelAuthoredWorldDrag();
    }

    private function stageWorldPointerCancel(state:Object, parts:Array):Void {
        var ticket:Number = inputUInt(parts[4], 1);
        var nativeEpoch:Number = inputUInt(parts[5], 1);
        if (parts.length != 6 || ticket < 1 || nativeEpoch < 1) return;
        var identity:String = parts.slice(2).join("|");
        var prior:Object = state.lastWorldPointerReceipt;
        if (prior != null && prior.identity === identity) {
            sendSocketMessage(prior.wire);
            return;
        }
        if (ticket <= state.worldPointerCancelTicket || state.worldPointerCancel != null) return;
        state.mouseWorldClose = null;
        state.worldPointerCancel = {ticket:ticket, identity:identity};
    }

    private function settleWorldPointerCancel(state:Object):Void {
        var pending:Object = state.worldPointerCancel;
        if (pending == null) return;
        var instance:Object = _authoredWorldDrag;
        var oldDrag:Boolean = cancelAuthoredWorldDrag();
        state.worldPointerCancel = null;
        state.worldPointerCancelTicket = pending.ticket;
        var wire:String = "I1|WorldPointerCancelled|" + pending.identity + "|1";
        var receipt:Object = {identity:pending.identity, wire:wire};
        state.lastWorldPointerReceipt = receipt;
        state.worldDragResume = oldDrag && typeof instance.resumeAuthoredWorldDrag == "function"
                && typeof instance.releaseAuthoredWorldDrag == "function" ? {instance:instance, receipt:receipt} : null;
        sendSocketMessage(wire);
        trace("[I1] WorldPointerCancelled " + pending.identity + " authoredDrag=" + oldDrag);
    }

    private function settleInputObligations():Void {
        if (_inputWire != null) _inputWire.mouseWorldClose = null;
        ++_inputCell.cancelSerial;
        _inputCell.clearKeyPresses();
        if (!cancelAuthoredWorldDrag() && typeof _root.stopDrag == "function") _root.stopDrag();
        KeyManager.cancelPassiveInput();
        FrameBroadcaster.cancelVersionedInput();
        // Logic loads after Shared. Keep the explicit gameplay hooks on its root bridge.
        var timer:Object = _root.帧计时器;
        if (typeof timer.cancelPassiveInput == "function") timer.cancelPassiveInput();
    }

    private function retirePassiveInput():Void {
        var state:Object = _inputWire;
        if (state == null) return;
        _inputCell.bound = false;
        // PassiveActive remains armed in a VM that had switched to Host input.
        // An unavailable Host cannot turn raw Flash keys into a new grant.
        closeInputSnapshot(_inputCell, _inputCell.snapshot.keyboardEpoch);
        _inputWire = null;
        _inputResetPending = true;
    }

    private function commitPassiveInput():Void {
        var cell:Object = _inputCell;
        var state:Object = _inputWire;
        if (_inputResetPending) {
            _inputResetPending = false;
            settleInputObligations();
        }

        if (state != null) {
            settleWorldPointerCancel(state);
            var control:Object = state.cancel;
            if (control != null) {
                state.cancel = null;
                state.highestTicket = control.ticket;
                var alreadySettled:Boolean = control.epoch === state.revokedEpoch;
                state.revokedEpoch = control.epoch;
                state.needsCancel = false;
                closeInputSnapshot(cell, control.epoch);
                if (state.staged != null && state.staged.epoch <= control.epoch) state.staged = null;
                if (state.localCancel != null && state.localCancel !== control.identity) state.localCancel = null;
                if (!alreadySettled) settleInputObligations();
                var receipt:String = "I1|Cancelled|" + control.identity + "|1|1";
                state.receipts[control.ticket] = {identity:control.identity, wire:receipt};
                cell.lastCancelled = receipt;
                sendSocketMessage(receipt);
                trace("[I1] Cancelled " + control.identity);
            }

            if ((state.staged != null || cell.gateOpen === true)
                    && (state.inputFrameSeq >= 2147483647 || currentFrame > 2147483647)) {
                faultInput("input_frame_exhausted", 0);
            }
            if (state.fault != null) {
                var fault:String = state.fault;
                var faultEpoch:Number = state.faultEpoch;
                state.fault = null;
                cell.lastFault = fault;
                trace("[I1] fault=" + fault + " epoch=" + faultEpoch);
                if (faultEpoch > state.revokedEpoch) {
                    closeInputSnapshot(cell, faultEpoch);
                    state.staged = null;
                    state.revokedEpoch = faultEpoch;
                    settleInputObligations();
                    if (state.highestTicket < 2147483647) {
                        var localTicket:Number = Math.max(faultEpoch, state.highestTicket + 1);
                        state.localCancel = state.session + "|" + state.connection + "|Game|" + faultEpoch
                            + "|" + localTicket + "|AS2|" + state.connection;
                        sendSocketMessage("I1|Cancel|" + state.localCancel + "|" + fault);
                    }
                } else if (faultEpoch == 0 && control == null && state.localCancel == null) {
                    // A malformed first batch can omit any usable epoch. Stay closed,
                    // then request cancellation as soon as the peer identifies its grant.
                    state.staged = null;
                    closeInputSnapshot(cell, cell.snapshot.keyboardEpoch);
                    if (state.needsCancel !== true) settleInputObligations();
                    state.needsCancel = true;
                }
            }

            var batch:Object = state.staged;
            if (batch != null) {
                state.staged = null;
                if (cell.snapshot.keyboardEpoch !== batch.epoch || cell.gateOpen !== true) {
                    if (cell.gateOpen === true) {
                        state.revokedEpoch = cell.snapshot.keyboardEpoch;
                        closeInputSnapshot(cell, state.revokedEpoch);
                        settleInputObligations();
                    }
                    FrameBroadcaster.beginVersionedInputEpoch();
                }
                cell.gateOpen = true;
                cell.snapshot = {systemFrame:currentFrame, inputFrameSeq:++state.inputFrameSeq,
                    keyboardEpoch:batch.epoch, words:batch.words, edges:batch.edges};
                sendSocketMessage("I1|Latch|" + state.session + "|" + state.connection + "|" + batch.epoch
                    + "|" + batch.seq + "|" + currentFrame + "|" + state.inputFrameSeq);
            } else if (cell.gateOpen === true) {
                var previous:Object = cell.snapshot;
                cell.snapshot = {systemFrame:currentFrame, inputFrameSeq:++state.inputFrameSeq,
                    keyboardEpoch:previous.keyboardEpoch, words:previous.words, edges:cell.noEdges};
            }
        }
        if (cell.gateOpen !== true) closeInputSnapshot(cell, cell.snapshot.keyboardEpoch);
        var timer:Object = _root.帧计时器;
        if (typeof timer.preparePassiveActor == "function") timer.preparePassiveActor();
        cell.recordKeyEdges(cell.snapshot.edges);
        cell.recordPhase("server", currentFrame);
        KeyManager.tickPassiveInput(cell.snapshot, cell.gateOpen);
    }

    // 使用 try/catch 包住 FastJSON.parse 处理服务器返回的数据
    // 契约：热路径(frame)走快车道不经过此方法；冷路径(task 响应)用 try/catch 兜底
    private function onSocketData(data:String):Void {
        // XMLSocket.onData 已剥除帧终止符。CS6 的 '\0' 是空串，split 会拆坏代理对。
        if (data.length == 0) return;
        var prefix:String = data.charAt(0);
        if (prefix == "I") {
            onInputWire(data);
            return;
        }

        // C# 打击数字源头开关：H0=关闭入队/序列化，H1=开启。
        // 行为模式与世界行上限由 Host 独占，Flash 只需要知道是否应产出事件。
        if (prefix == "H") {
            if (data == "H0" || data == "H1") {
                org.flashNight.arki.component.Effect.HitNumberBatchProcessor.setHostEnabled(
                    data == "H1"
                );
            } else if (data == "Hh0" || data == "Hh1") {
                org.flashNight.arki.component.Effect.HitNumberBatchProcessor.setHealHostEnabled(data == "Hh1");
            }
            return;
        }

        // Raw K no longer feeds combo input. Only the standalone protocol
        // latency fixture hooks this diagnostic echo.
        if (prefix == "K") {
            if (_root.__protocolBench != null && _root.GameInput.passiveActive !== true)
                FrameBroadcaster.receiveK(data.substring(1));
            return;
        }

        // 性能目标快车道：P{tier}|{softU100}|{quality}|{command}|{scene}。
        if (prefix == "P") {
            var payload:String = data.substring(1);
            var perfParts:Array = payload.split("|");
            if (perfParts.length == 5) {
                var tier:Number = Number(perfParts[0]);
                var softU100:Number = Number(perfParts[1]);
                if (!isNaN(tier) && !isNaN(softU100)) {
                    var sched:Object = _root.帧计时器.scheduler;
                    if (sched != null) {
                        sched.applyFromLauncher(tier, softU100 / 100, String(perfParts[2]), Number(perfParts[3]), Number(perfParts[4]));
                    }
                }
            }
            return;
        }

        var response:Object;
        try {
            response = jsonParser.parse(data);
        } catch (e) {
            trace("[ServerManager] Bad packet: " + e.message + " | data=" + data.substring(0, 80));
            return;
        }

        // Audio v2 lifecycle push has an explicit task and an exact key set.
        // Near-matches are consumed as malformed audio packets and never fall through
        // to generic task/callback routing.
        if (response.task === "audio_ready") {
            if (!isExactAudioReadyEnvelope(response)
                    || !AudioBridge.handleAudioReady(response)) {
                trace("[ServerManager] Rejected malformed audio_ready");
            }
            return;
        }
        if (response.task === "audio_unavailable") {
            if (!isExactAudioUnavailableEnvelope(response)
                    || !AudioBridge.handleAudioUnavailable(response)) {
                trace("[ServerManager] Rejected malformed audio_unavailable");
            }
            return;
        }

        // Correlated BGM results deliberately have no task/callId. Identify them only
        // by the strict 13-key v2 schema; connectionGeneration is therefore rejected.
        var audioResultLike:Boolean = response.wireRevision === 2
            && (response.completionState !== undefined
                || (response.requestId !== undefined
                    && response.audioSessionId !== undefined));
        if (audioResultLike) {
            if (!isExactAudioBgmResultEnvelope(response)
                    || !AudioBridge.handleBgmResult(response)) {
                trace("[ServerManager] Rejected malformed or uncorrelated audio result");
            }
            return;
        }

        // 处理服务器推送的控制台命令
        if (response.task == "console") {
            handleConsoleCommand(response.command,response.qualificationSlot);
            return;
        }

        // 处理 C#→AS2 游戏命令
        if (response.task == "cmd") {
            handleGameCommand(response.action, response);
            return;
        }

        // 音乐目录同步（Launcher → Flash）
        if (response.task == "catalog") {
            if (_root.soundEffectManager != undefined) {
                _root.soundEffectManager.mergeCatalog(response);
            }
            return;
        }
        if (response.task == "catalogUpdate") {
            if (_root.soundEffectManager != undefined) {
                _root.soundEffectManager.updateCatalog(response);
            }
            return;
        }
        if (response.task == "save_push") {
            org.flashNight.neur.Server.SaveManager.getInstance().receiveSavePush(response);
            return;
        }

        // C2-β: BootstrapPanel 修复卡片走完后 launcher push task=repair_resolved.
        // 载荷: {success, forced?, slot, cleanedSnapshot?}. SaveManager 落地清洁 snapshot
        // (或 forced 路径用原坏档) + 清 _repairPending → asLoader 帧循环放行 sendReady.
        if (response.task == "repair_resolved") {
            org.flashNight.neur.Server.SaveManager.getInstance().applyRepairResolved(response);
            return;
        }

        // native_dialogue wire v2 能力推送（每连接代重发）：
        // {task:"dialogue_caps", modes:["snapshot","book"]}；
        // 闩的 socket generation 作用域与清闩收口由服务侧管理。
        if (response.task == "dialogue_caps") {
            org.flashNight.arki.dialogue.NativeDialogueService.applyCaps(response.modes);
            return;
        }
        // 插话「我接了」发布成功后的 Host 推送：{task:"agent_task_publish", taskId, npc, slot, token}。
        // 校验 → 版本读取 → 热更收敛 → 关旧对白 → GetTask 接管在 通信_aka_Agent联动.as。
        if (response.task == "agent_task_publish") {
            if (_root.agent != undefined && typeof _root.agent.接收任务发布推送 == "function") {
                _root.agent.接收任务发布推送(response);
            }
            return;
        }
        // 每连接代由配套 Host 确认原生天气绘制；未确认时仅保留天气选择状态。
        if (response.task == "weather_caps") {
            org.flashNight.arki.render.WeatherParticleRenderer.setNativeEnabled(response.native === true);
            org.flashNight.arki.weather.WorldLightingBridge.publish(
                org.flashNight.arki.weather.WeatherSystem.getInstance(), true);
            return;
        }
        if (response.task == "visual_wire_offer" || response.task == "visual_wire_commit") {
            org.flashNight.arki.render.VisualWireService.handle(response);
            return;
        }
        if (response.task == "bullet_visual_caps") {
            org.flashNight.arki.render.BulletVisualProbe.configure(response);
            return;
        }
        if (response.task == "worker_projection_offer" || response.task == "worker_projection_commit") {
            org.flashNight.arki.render.WorkerProjectionPolicy.handle(response);
            return;
        }
        if (response.task == "ray_visual_caps") {
            org.flashNight.arki.render.RayVisualBridge.configure(response);
            return;
        }
        if (response.task == "chain_visual_caps") {
            org.flashNight.arki.render.ChainVisualBridge.configure(response);
            return;
        }
        if (response.task == "combat_fx_caps") {
            org.flashNight.arki.render.CombatFxBridge.configure(response);
            return;
        }
        if (response.task == "combat_fx_events") {
            org.flashNight.arki.render.CombatFxBridge.receiveEvents(response);
            return;
        }

        // Callback 路由：有 callId 的响应分发到注册的回调
        if (response.callId !== undefined) {
            var cbKey:String = String(response.callId);
            var cbEntry:Object = _pendingCallbacks[cbKey];
            if (cbEntry != undefined) {
                delete _pendingCallbacks[cbKey];
                cbEntry.cb(response);
                return;
            }
        }

        // 未被 callback 路由匹配的通用响应
        if (response.success) {
            trace("[ServerManager] Task result: " + response.result);
        } else {
            trace("[ServerManager] Task error: " + response.error);
        }
    }

    // 处理从服务器推送来的控制台命令
    private function handleConsoleCommand(command:String,qualificationSlot:String):Void {
        if (_root.__characterExitSeal != null) return;
        command = unescape(command);
        if (qualificationSlot!=undefined && qualificationSlot!=""
            && !org.flashNight.neur.Server.QualificationConsoleScope.allows(qualificationSlot,command,
                String(_root.savePath),String(_root._saveExt.bookRun.originSlot))) {
            sendSocketMessage(jsonParser.stringify({task:"console_result",success:false,
                command:command,result:"qualification_role_scope_mismatch"}));return;
        }
        trace("[Console] Executing: " + command);

        var result:String = "";

        if (_root.cheatCode != undefined) {
            var output:Array = [];
            var origTip:Function = _root.最上层发布文字提示;
            var origMsg:Function = _root.发布消息;

            _root.最上层发布文字提示 = function(msg:String):Void {
                output.push(msg);
                if (origTip != undefined) {
                    origTip.call(_root, msg);
                }
            };
            _root.发布消息 = function(msg:String):Void {
                output.push(msg);
                if (origMsg != undefined) {
                    origMsg.call(_root, msg);
                }
            };

            _root.cheatCode(command);

            _root.最上层发布文字提示 = origTip;
            _root.发布消息 = origMsg;

            result = (output.length > 0) ? output.join("\n") : "OK";
        } else {
            result = "cheatCode not available";
        }

        trace("[Console] Result: " + result);

        var responseObj:Object = new Object();
        responseObj.task = "console_result";
        responseObj.success = true;
        responseObj.command = command;
        responseObj.result = result;

        var responseString:String = jsonParser.stringify(responseObj);
        sendSocketMessage(responseString);
    }

    // C#→AS2 游戏命令分发器
    private function handleGameCommand(action:String, params:Object):Void {
        if (_root.__characterExitSeal != null && action != "characterBuildPersistedExit") return;
        if (action == undefined || action == "") {
            trace("[GameCmd] Missing action");
            return;
        }
        if (action == "jukeboxPlay" && !isExactJukeboxPlayCommand(params)) {
            trace("[GameCmd] Rejected malformed jukeboxPlay command");
            return;
        }
        // 真正未决的奖励候选禁止竞争写入。暂停只挡游戏帧，还需挡 Host 命令入口。
        // 恢复命令始终重交原候选；摘要/页/冷却读取不会参与资产事务。
        if (org.flashNight.neur.Server.SaveManager.getInstance().hasRewardCommitPending()
                && action != "lootQuery" && action.indexOf("itemUseStash") != 0
                && action != "openInventoryWorkbench" && action != "inventorySnapshot" && action != "inventoryTooltip"
                && action != "characterBuildSnapshot" && action != "webPanelUnpause"
                && action != "bookComicPrepared" && action != "bookComicFinish"
                && action != "ragChatUnavailable"
                // 只读可用性通知，不参与奖励事务，奖励未决时也不能丢。
                && action != "ragTerminalAvailable"
                // 任务前插话临时新增奖励：覆盖层已由 Host 落盘，这里只按变化源重读任务定义，
                // 不写库存/奖励账本；奖励候选未决时也不能丢，否则结算会读不到已生效的增量。
                && action != "taskRewardOverrideChanged"
                && action != "itemUseInboxSnapshot" && action != "itemUseCooldownSnapshot"
                && !(action == "agentHarnessCmd" && params != undefined && params.sub == "world_snapshot")) {
            trace("[GameCmd] reward candidate pending: " + action);
            return;
        }
        var handler:Function = _root.gameCommands[action];
        if (typeof handler == "function") {
            handler(params);
        } else {
            trace("[GameCmd] Unknown action: " + action);
        }
    }

    public function onSocketClose():Void {
        // 主动 uncertainty recovery 会本地执行一次 onSocketClose；若服务器关闭事件
        // 已经排队，后到的重复通知必须保持幂等，不能再次推进 loot proof/FSM。
        if (xmlSocket == null && !isSocketConnected && _state != S_CONNECTED) return;
        retirePassiveInput();
        trace("XMLSocket connection closed");
        isSocketConnected = false;
        org.flashNight.arki.component.Effect.HitNumberBatchProcessor.setHostEnabled(false);
        org.flashNight.arki.component.Effect.HitNumberBatchProcessor.setHealHostEnabled(false);
        org.flashNight.arki.render.WeatherParticleRenderer.setNativeEnabled(false);
        org.flashNight.arki.render.VisualWireService.retire();
        org.flashNight.arki.render.WorkerProjectionPolicy.retired();
        org.flashNight.arki.render.BulletVisualProbe.disconnect();
        org.flashNight.arki.render.RayVisualBridge.disconnect();
        org.flashNight.arki.render.ChainVisualBridge.disconnect();
        org.flashNight.arki.render.CombatFxBridge.disconnect();
        // 先 retire 当前 source；旧 XMLSocket 排队的 onData/onClose 即使在新连接建立后
        // 才抵达，也会被 initXMLSocket closure 的对象身份门拒绝。
        xmlSocket = null;
        AudioBridge.onTransportDisconnected();
        org.flashNight.arki.dialogue.NativeDialogueService.onTransportDisconnected();
        org.flashNight.arki.scene.BookComicService.onTransportDisconnected();
        org.flashNight.arki.ui.NativeGuidanceService.clear();
        org.flashNight.neur.Server.AgentHarnessService.onTransportDisconnected();

        // loot 奖励只存在本地内存；Host 断线时直接让服务续跑 exact journal/effects，
        // 并把同一 authority 收敛到 Web-only SUSPENDED 或终态。不存在 Flash UI 回退。
        var lootReconciled:Boolean = false;
        try {
            var lootDetach:Object = LootContainerService.reconcileSocketDetach(null);
            lootReconciled = lootDetach != null && lootDetach.success === true;
            if (!lootReconciled && lootDetach != null
                    && lootDetach.error != "no_web_loot_authority"
                    && lootDetach.error != "terminal_state") {
                trace("[LootContainerService] socket detach not settled: "
                    + (lootDetach.error == undefined ? "unknown" : lootDetach.error));
            }
        } catch (lootReconcileError) {
            lootReconciled = false;
            trace("[LootContainerService] socket detach exception: " + lootReconcileError);
        }
        if (lootReconciled && _root._webPanelPauseLease != undefined) {
            trace("[LootContainerService] detach proof returned with pause lease; fail closed");
        }

        // CharacterBuild 没有远端 UI 回退。断线时在清 pending callback 前只同步完成
        // exact finalize/persist，并保留 session 开始时捕获的 pause lease。AS2 此刻无法
        // 证明 Host visual 已退场；真正释放必须等待重连后的 Host-only recoverDetach。
        try {
            var characterBuildDetach:Object =
                org.flashNight.arki.item.CharacterBuildService
                    .reconcileSocketDetach();
            if (characterBuildDetach != null
                    && characterBuildDetach.handled === true
                    && characterBuildDetach.success !== true) {
                trace("[CharacterBuildService] socket detach not settled: "
                    + (characterBuildDetach.error == undefined
                        ? "unknown" : characterBuildDetach.error));
            }
        } catch (characterBuildReconcileError) {
            trace("[CharacterBuildService] socket detach exception: "
                + characterBuildReconcileError);
        }

        // 清理所有 pending callback（断线后不会再收到响应）
        for (var k:String in _pendingCallbacks) {
            _pendingCallbacks[k].cb({success: false, error: "socket closed"});
        }
        _pendingCallbacks = {};

        // 断连只关闭性能命令入口；保持最后有效表现目标。
        var sched:Object = _root.帧计时器.scheduler;
        if (sched != null) {
            sched.onTransportDisconnected();
        }

        // 关键：回到 FETCHING_PORT 重新发现端口（launcher 可能重启在不同端口）
        // 不是死守旧端口，也不用 setTimeout
        _retryCount = 0;
        transitionTo(S_FETCHING_PORT);
    }

    /**
     * panel_request 回包结果不确定时，主动切断本 socket generation。XMLSocket.onClose
     * 只保证服务器侧关闭通知，因此本地 close 后显式执行统一 onSocketClose 收敛路径；
     * Host 会从对端断开观察同一 generation，并在重连后发 exact causal proof query。
     */
    public function forceSocketRecovery(reason:String):Boolean {
        if (_state != S_CONNECTED || !isSocketConnected || xmlSocket == null) return false;
        trace("[ServerManager] force socket recovery: " + reason);
        var retiringSocket:XMLSocket = xmlSocket;
        try {
            retiringSocket.close();
        } catch (closeError) {
            trace("[ServerManager] force socket recovery failed: " + closeError);
            return false;
        }
        if (xmlSocket === retiringSocket) xmlSocket = null;
        onSocketClose();
        return true;
    }

    // ==================== 消息发送 ====================

    public function sendSocketMessage(message:String):Boolean {
        if (isSocketConnected) {
            xmlSocket.send(message + '\0');
            return true;
        } else {
            trace("Socket not connected. Cannot send message.");
            return false;
        }
    }

    public function sendServerMessage(message:String):Void {
        if (messageBuffer.length > 0) {
            messageBuffer += "|" + message;
        } else {
            messageBuffer = message;
        }
    }

    public function sendImmediate(message:String):Void {
        if (currentPort == null) return;
        var lv:LoadVars = new LoadVars();
        lv.messages = message;
        lv.frame = currentFrame;
        lv.sendAndLoad("http://localhost:" + currentPort + "/logBatch", new LoadVars(), "POST");
    }

    private function sendMessageBuffer():Void {
        if (currentPort == null || isSending) return;

        var lv:LoadVars = new LoadVars();
        var messageToSend:String = messageBuffer;

        lv.frame = currentFrame;
        lv.messages = messageToSend;

        isSending = true;
        hasSentThisFrame = true;

        lv.onLoad = function(success:Boolean):Void {
            ServerManager.instance.isSending = false;
        };

        lv.sendAndLoad("http://localhost:" + currentPort + "/logBatch", lv, "POST");

        messageBuffer = "";
    }

    // ==================== Task 发送 ====================

    public function sendTaskToNode(taskType:String, payload:Object, extra:Object):Boolean {
        var message:Object = buildTaskEnvelope(taskType, payload, extra);
        if (message == null) return false;

        var messageString:String = jsonParser.stringify(message);
        if (messageString == null) {
            trace("Failed to stringify message.");
            return false;
        }

        return sendSocketMessage(messageString);
    }

    /**
     * All existing tasks retain {task,payload,extra}. Audio v2 alone is a frozen flat
     * exact-key wire, so its payload own fields are copied beside task before the same
     * FastJSON serializer runs. Audio extra/task injection fails closed.
     */
    private static function buildTaskEnvelope(
            taskType:String,
            payload:Object,
            extra:Object):Object {
        if (typeof taskType != "string" || taskType.length == 0) return null;
        var message:Object = new Object();
        message.task = taskType;

        if (taskType == "audio") {
            if (payload == null || typeof payload != "object" || extra != null) return null;
            for (var key:String in payload) {
                if (!owns(payload, key)) continue;
                if (key == "task") return null;
                message[key] = payload[key];
            }
            return message;
        }

        message.payload = payload;
        if (extra != null) message.extra = extra;
        return message;
    }

    private static function isExactAudioBgmResultEnvelope(value:Object):Boolean {
        return hasExactOwnKeys(value, AUDIO_BGM_RESULT_KEYS)
            && value.wireRevision === 2
            && typeof value.requestId == "string"
            && typeof value.audioSessionId == "string"
            && typeof value.audioReadyGeneration == "string"
            && typeof value.deviceGeneration == "string"
            && typeof value.operation == "string"
            && typeof value.completionState == "string"
            && typeof value.category == "string"
            && typeof value.stage == "string"
            && typeof value.nativeCode == "number"
            && typeof value.hresult == "number"
            && typeof value.decoderBackend == "string"
            && typeof value.messageKey == "string";
    }

    private static function isExactAudioReadyEnvelope(value:Object):Boolean {
        return hasExactOwnKeys(value, AUDIO_READY_KEYS)
            && value.task === "audio_ready"
            && value.wireRevision === 2
            && typeof value.audioSessionId == "string"
            && typeof value.audioReadyGeneration == "string"
            && typeof value.deviceGeneration == "string"
            && typeof value.loaded == "number"
            && typeof value.failed == "number"
            && typeof value.overrides == "number"
            && typeof value.capabilityDigest == "string";
    }

    private static function isExactAudioUnavailableEnvelope(value:Object):Boolean {
        return hasExactOwnKeys(value, AUDIO_UNAVAILABLE_KEYS)
            && value.task === "audio_unavailable"
            && value.wireRevision === 2
            && typeof value.audioSessionId == "string"
            && typeof value.audioReadyGeneration == "string"
            && typeof value.deviceGeneration == "string"
            && typeof value.category == "string"
            && typeof value.messageKey == "string";
    }

    private static function isExactJukeboxPlayCommand(value:Object):Boolean {
        return hasExactOwnKeys(value, JUKEBOX_PLAY_COMMAND_KEYS)
            && value.task === "cmd"
            && value.action === "jukeboxPlay"
            && typeof value.title == "string"
            && value.title.length > 0;
    }

    private static function hasExactOwnKeys(value:Object, expected:Array):Boolean {
        if (value == null || typeof value != "object") return false;
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
        return value != null
            && Object.prototype.hasOwnProperty.call(value, key);
    }

    private static function arrayContainsExact(values:Array, value):Boolean {
        for (var i:Number = 0; i < values.length; i++) {
            if (values[i] === value) return true;
        }
        return false;
    }

    // Focused TestLoader hooks exercise the exact production helpers without opening
    // ports or constructing the ServerManager singleton.
    public static function _buildTaskEnvelopeForTest(
            taskType:String,
            payload:Object,
            extra:Object):Object {
        return buildTaskEnvelope(taskType, payload, extra);
    }

    public static function _isExactAudioBgmResultEnvelopeForTest(value:Object):Boolean {
        return isExactAudioBgmResultEnvelope(value);
    }

    public static function _isExactAudioReadyEnvelopeForTest(value:Object):Boolean {
        return isExactAudioReadyEnvelope(value);
    }

    public static function _isExactAudioUnavailableEnvelopeForTest(value:Object):Boolean {
        return isExactAudioUnavailableEnvelope(value);
    }

    public static function _isExactJukeboxPlayCommandForTest(value:Object):Boolean {
        return isExactJukeboxPlayCommand(value);
    }

    /**
     * 带 callId 应答路由的 task 发送。
     * @param callbackTimeoutMs 回调墙钟期限，单位毫秒：超时扫描比较
     *        getTimer() 实际时间差（非帧计数，帧率漂移不改变真实期限）；
     *        缺省/非法回退 CALLBACK_TIMEOUT_MS。
     * 底层 send 失败时立即移除 pending 并同步回调
     * {success:false,error:"send failed"}，不留幽灵回调。
     */
    public function sendTaskWithCallback(taskType:String, payload:Object, extra:Object,
                                          callback:Function, callbackTimeoutMs:Number,
                                          trustedArchiveShadow:Boolean):Void {
        var callId:Number = _callIdCounter++;
        var message:Object = new Object();
        message.task = taskType;
        message.payload = payload;
        message.callId = callId;
        if (extra != null) {
            message.extra = extra;
        }

        var messageString:String = trustedArchiveShadow === true
            ? org.flashNight.neur.Server.ArchiveShadowWire.stringify(jsonParser, message)
            : jsonParser.stringify(message);
        if (messageString == null) {
            callback({success: false, error: "stringify failed"});
            return;
        }
        if (!isSocketConnected) {
            callback({success: false, error: "socket not connected"});
            return;
        }

        var timeoutMs:Number = (callbackTimeoutMs != undefined && !isNaN(callbackTimeoutMs) && callbackTimeoutMs > 0)
            ? callbackTimeoutMs
            : CALLBACK_TIMEOUT_MS;
        var cbKey:String = String(callId);
        _pendingCallbacks[cbKey] = {cb: callback, sentAt: getTimer(), timeoutMs: timeoutMs};
        if (!sendSocketMessage(messageString)) {
            delete _pendingCallbacks[cbKey];
            callback({success: false, error: "send failed"});
        }
    }

}
