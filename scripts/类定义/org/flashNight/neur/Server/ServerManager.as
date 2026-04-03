import org.flashNight.neur.Event.Delegate;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.gesh.path.PathManager;
import FastJSON;

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

    // ==================== 连接状态机 ====================
    private var _state:Number;
    private var _stateEnteredFrame:Number;
    private var _retryCount:Number;

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

    // ==================== JSON ====================
    private var jsonParser:FastJSON;

    // ==================== Callback 路由 ====================
    private var _callIdCounter:Number;
    private var _pendingCallbacks:Object;
    private static var CALLBACK_TIMEOUT_FRAMES:Number = 600; // 20s @30fps

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
        _state = S_DISCONNECTED;
        _stateEnteredFrame = 0;
        _retryCount = 0;

        eventBus = EventBus.getInstance();
        extractPorts();
        initFrameClip();

        // Subscribe internal functions to frameUpdate event
        eventBus.subscribe("frameUpdate", onFrameUpdate, this);

        // Initialize JSON parser
        jsonParser = new FastJSON();

        // Callback 路由初始化
        _callIdCounter = 0;
        _pendingCallbacks = {};

        // 启动连接：先尝试读端口文件快速连接，失败则 fallback 盲扫
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
        var base:String = PathManager.getBasePath();
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
        eventBus.publish("frameUpdate", currentFrame);
        hasSentThisFrame = false;
    }

    public function onFrameUpdate(currentFrame:Number):Void {
        // ---- 状态机 tick ----
        if (_state == S_DISCONNECTED) {
            // 等待重连延迟
            if (_retryCount < MAX_RETRIES
                && (currentFrame - _stateEnteredFrame) >= RETRY_DELAY) {
                transitionTo(S_HTTP_PROBING);
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
        if (currentFrame % 60 === 0) {
            for (var k:String in _pendingCallbacks) {
                var e:Object = _pendingCallbacks[k];
                if (currentFrame - e.frame > CALLBACK_TIMEOUT_FRAMES) {
                    delete _pendingCallbacks[k];
                    e.cb({success: false, error: "callback timeout"});
                }
            }
        }
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
        var self = this;
        xmlSocket = new XMLSocket();
        xmlSocket.onConnect = function(success:Boolean):Void {
            self.onSocketConnect(success);
        };
        xmlSocket.onData = function(data:String):Void {
            self.onSocketData(data);
        };
        xmlSocket.onClose = function():Void {
            self.onSocketClose();
        };

        if (socketPort == null) {
            trace("Socket port not available. Cannot connect.");
            _retryCount++;
            transitionTo(S_DISCONNECTED);
            return;
        }
        xmlSocket.connect(socketHost, socketPort);
    }

    private function onSocketConnect(success:Boolean):Void {
        if (_state != S_SOCKET_CONNECTING) return;

        if (success) {
            trace("XMLSocket connected to server on port: " + socketPort);
            _retryCount = 0;
            transitionTo(S_CONNECTED);
        } else {
            trace("Failed to connect XMLSocket to server on port: " + socketPort);
            _retryCount++;
            transitionTo(S_DISCONNECTED);
        }
    }

    // 使用 try/catch 包住 FastJSON.parse 处理服务器返回的数据
    // 契约：热路径(frame)走快车道不经过此方法；冷路径(task 响应)用 try/catch 兜底
    private function onSocketData(data:String):Void {
        // 移除 null 终止符
        data = data.split('\0').join('');

        // 性能调度快车道：P{tier}|{softU_x100}（绕过 JSON 解析）
        if (data.length > 0 && data.charAt(0) == "P") {
            var payload:String = data.substring(1);
            var sep:Number = payload.indexOf("|");
            if (sep >= 0) {
                var tier:Number = Number(payload.substring(0, sep));
                var softU100:Number = Number(payload.substring(sep + 1));
                if (!isNaN(tier) && !isNaN(softU100)) {
                    var sched:Object = _root.帧计时器.scheduler;
                    if (sched != null) {
                        sched.applyFromLauncher(tier, softU100 / 100);
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

        // 处理服务器推送的控制台命令
        if (response.task == "console") {
            handleConsoleCommand(response.command);
            return;
        }

        // 处理 C#→AS2 游戏命令
        if (response.task == "cmd") {
            handleGameCommand(response.action, response);
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
    private function handleConsoleCommand(command:String):Void {
        command = unescape(command);
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
        if (action == undefined || action == "") {
            trace("[GameCmd] Missing action");
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
        trace("XMLSocket connection closed");
        isSocketConnected = false;

        // 清理所有 pending callback（断线后不会再收到响应）
        for (var k:String in _pendingCallbacks) {
            _pendingCallbacks[k].cb({success: false, error: "socket closed"});
        }
        _pendingCallbacks = {};

        // 性能调度: 断连回退到本地模式（幂等，已是 local 时空操作）
        var sched:Object = _root.帧计时器.scheduler;
        if (sched != null) {
            sched.setRemoteControlled(false);
        }

        // 关键：回到 FETCHING_PORT 重新发现端口（launcher 可能重启在不同端口）
        // 不是死守旧端口，也不用 setTimeout
        _retryCount = 0;
        transitionTo(S_FETCHING_PORT);
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
        var message:Object = new Object();
        message.task = taskType;
        message.payload = payload;
        if (extra != null) {
            message.extra = extra;
        }

        var messageString:String = jsonParser.stringify(message);
        if (messageString == null) {
            trace("Failed to stringify message.");
            return false;
        }

        return sendSocketMessage(messageString);
    }

    public function sendTaskWithCallback(taskType:String, payload:Object, extra:Object,
                                          callback:Function):Void {
        var callId:Number = _callIdCounter++;
        var message:Object = new Object();
        message.task = taskType;
        message.payload = payload;
        message.callId = callId;
        if (extra != null) {
            message.extra = extra;
        }

        var messageString:String = jsonParser.stringify(message);
        if (messageString == null) {
            callback({success: false, error: "stringify failed"});
            return;
        }
        if (!isSocketConnected) {
            callback({success: false, error: "socket not connected"});
            return;
        }

        _pendingCallbacks[String(callId)] = {cb: callback, frame: currentFrame};
        sendSocketMessage(messageString);
    }

}
