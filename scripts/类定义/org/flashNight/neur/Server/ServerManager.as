import org.flashNight.neur.Event.Delegate;
import org.flashNight.neur.Event.EventBus;
import FastJSON; 

class org.flashNight.neur.Server.ServerManager {
    public static var instance:ServerManager;
    public var portList:Array;
    public var portIndex:Number;
    public var currentPort:Number;
    private var frameClip:MovieClip; // 用于管理 enterFrame 事件的影片剪辑
    public var currentFrame:Number; // 独立的帧计数器

    // 重连相关变量
    public var reconnectionAttempts:Number = 0;
    public var maxReconnectionAttempts:Number = 5;
    public var reconnectionDelayFrames:Number = 300; // 固定重连间隔10秒
    public var framesSinceLastReconnectionAttempt:Number = 0;
    public var isReconnecting:Boolean = false;

    // 消息发送相关变量
    private var isSending:Boolean = false; // 当前是否在发送消息
    private var hasSentThisFrame:Boolean = false; // 本帧是否已发送过消息
    private var messageBuffer:String = ""; // 待发送的消息缓冲区

    // Cached EventBus instance
    private var eventBus:EventBus;

    // 新增变量
    public var xmlSocket:XMLSocket;
    public var socketHost:String = "localhost";
    public var socketPort:Number = null; // 初始为空，在获取到端口号后设置
    public var isSocketConnected:Boolean = false; // 用于跟踪连接状态

    // JSON parser instance
    private var jsonParser:FastJSON;

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
        eventBus = EventBus.getInstance(); // Cache EventBus instance
        extractPorts();
        initFrameClip();
        getAvailablePort(); // 启动端口检测

        // Subscribe internal functions to frameUpdate event
        eventBus.subscribe("frameUpdate", onFrameUpdate, this);

        // Initialize JSON parser
        jsonParser = new FastJSON(); // 传入 true 以启用宽容模式
    }

    // 获取单例实例
    public static function getInstance():ServerManager {
        if (instance == null) {
            instance = new ServerManager();
        }
        return instance;
    }

    // 提取端口号
    public function extractPorts():Void {
        var eyeOf119:String = (_root.闪客之夜 != undefined) ? _root.闪客之夜.toString() : "1192433993";
        trace("Extracting ports from eyeOf119: " + eyeOf119);

        // 提取4位数的端口
        for (var i:Number = 0; i <= eyeOf119.length - 4; i++) {
            var port4:String = eyeOf119.substring(i, i + 4);
            var port4Num:Number = Number(port4);

            if (isValidPort(port4Num) && !containsPort(port4Num)) {
                portList.push(port4Num);
                trace("Added valid 4-digit port: " + port4Num);
            }
        }

        // 提取5位数的端口
        for (var j:Number = 0; j <= eyeOf119.length - 5; j++) {
            var port5:String = eyeOf119.substring(j, j + 5);
            var port5Num:Number = Number(port5);

            if (isValidPort(port5Num) && !containsPort(port5Num)) {
                portList.push(port5Num);
                trace("Added valid 5-digit port: " + port5Num);
            }
        }

        // 确保端口3000被加入（如果还未加入）
        if (!containsPort(3000) && isValidPort(3000)) {
            portList.push(3000);
            trace("Added default port: 3000");
        }

        // 移除重复的端口
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

    private function initFrameClip():Void {
        frameClip = _root.createEmptyMovieClip("ServerManagerFrameClip", _root.getNextHighestDepth());
        frameClip.onEnterFrame = function() {
            ServerManager.instance.onEnterFrameHandler();
        };
    }

    public function getAvailablePort():Void {
        if (portIndex < portList.length) {
            var port:Number = portList[portIndex];
            trace("Trying to connect to HTTP server on port: " + port);

            testConnection(port);
        } else {
            trace("No available ports found.");
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
        trace("Connected to HTTP server on port: " + port);
        currentPort = port;

        // 重置重连相关变量
        reconnectionAttempts = 0;
        framesSinceLastReconnectionAttempt = 0;
        isReconnecting = false;

        // 获取 XMLSocket 端口
        getSocketPort();
    }

    private function onPortFailure(port:Number):Void {
        trace("Failed to connect to HTTP server on port: " + port);
        reconnectionAttempts++;
        framesSinceLastReconnectionAttempt = 0;

        if (reconnectionAttempts < maxReconnectionAttempts) {
            isReconnecting = true;
            trace("Reconnection attempt " + reconnectionAttempts + " scheduled in " + reconnectionDelayFrames + " frames.");
        } else {
            isReconnecting = false;
            trace("Max reconnection attempts reached. Giving up.");
        }

        portIndex++;
        if (portIndex >= portList.length) {
            portIndex = 0; // 循环尝试端口列表
        }
    }

    // 获取 XMLSocket 端口号
    private function getSocketPort():Void {
        var lv:LoadVars = new LoadVars();

        lv.onLoad = function(success:Boolean):Void {
            if (success) {
                var response:Object = this;
                if (response.socketPort != undefined) {
                    ServerManager.instance.socketPort = Number(response.socketPort);
                    trace("Retrieved XMLSocket port: " + ServerManager.instance.socketPort);
                    // 初始化 XMLSocket 连接
                    ServerManager.instance.initXMLSocket();
                } else {
                    trace("Failed to retrieve socket port.");
                }
            } else {
                trace("Failed to load socket port.");
            }
        };

        lv.load("http://localhost:" + currentPort + "/getSocketPort");
    }

    // 发送服务器消息（将消息追加到 messageBuffer）
    public function sendServerMessage(message:String):Void {
        // 验证消息内容，确保只接受字符串且不包含非法字符
        /*
        if (typeof(message) != "string" || message.indexOf("{") != -1 || message.indexOf("}") != -1) {
            trace("Invalid message format. Only plain strings without '{}' are allowed.");
            return;
        }
        */

        // 将消息追加到消息缓冲区
        if (messageBuffer.length > 0) {
            messageBuffer += "|" + message;
        } else {
            messageBuffer = message;
        }

        trace("Message appended to buffer: " + message);
    }

    public function onEnterFrameHandler():Void {
        // 增加帧计数
        currentFrame++;

        // Publish frameUpdate event
        eventBus.publish("frameUpdate", currentFrame);

        // 重置 hasSentThisFrame 标志
        hasSentThisFrame = false;
    }

    public function onFrameUpdate(currentFrame:Number):Void {
        // 处理重连逻辑
        if (isReconnecting) {
            framesSinceLastReconnectionAttempt++;
            if (framesSinceLastReconnectionAttempt >= reconnectionDelayFrames) {
                isReconnecting = false;
                trace("Attempting reconnection...");
                getAvailablePort(); // 尝试重连
            }
        }

        // 如果当前没有在发送消息，且消息缓冲区不为空，且已连接到端口，且本帧还未发送过消息
        if (!isSending && messageBuffer.length > 0 && currentPort != null && !hasSentThisFrame) {
            sendMessageBuffer();
        }
    }

    // 发送积累的消息
    private function sendMessageBuffer():Void {
        if (currentPort == null) {
            trace("No current HTTP port available. Cannot send messages.");
            return;
        }

        if (isSending) {
            trace("Already sending messages. Send aborted.");
            return;
        }

        // 发送消息
        var lv:LoadVars = new LoadVars();
        var messageToSend:String = messageBuffer; // 仅发送消息内容，不包含帧数

        lv.frame = currentFrame; // 将帧数作为独立参数
        lv.messages = messageToSend;

        trace("Sending messages for frame " + currentFrame + ": " + messageToSend + " to HTTP port: " + currentPort);

        isSending = true;
        hasSentThisFrame = true; // 标记本帧已经发送过消息

        lv.onLoad = function(success:Boolean):Void {
            if (success) {
                ServerManager.instance.onMessageSuccess();
            } else {
                ServerManager.instance.onMessageFailure();
            }
        };

        lv.sendAndLoad("http://localhost:" + currentPort + "/logBatch", lv, "POST");

        // 清空消息缓冲区
        messageBuffer = "";
    }

    private function onMessageSuccess():Void {
        trace("Messages sent successfully.");
        isSending = false;
    }

    private function onMessageFailure():Void {
        trace("Failed to send messages.");
        isSending = false;
        // 可选：将失败的消息重新加入缓冲区或记录错误
    }

    // 初始化 XMLSocket
    public function initXMLSocket():Void {
        var self = this; // 保存对 this 的引用
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

        connectToSocket();
    }

    public function connectToSocket():Void {
        if (socketPort == null) {
            trace("Socket port not available. Cannot connect.");
            return;
        }

        xmlSocket.connect(socketHost, socketPort);
    }

    // 修改后的 XMLSocket onConnect 事件处理器
    private function onSocketConnect(success:Boolean):Void {
        if (success) {
            trace("XMLSocket connected to server on port: " + socketPort);
            isSocketConnected = true; // 标记为已连接
        } else {
            trace("Failed to connect XMLSocket to server on port: " + socketPort);
            isSocketConnected = false; // 标记为未连接
        }
    }

    // 使用 JSON 类解析服务器返回的数据
    private function onSocketData(data:String):Void {
        trace("Received data from server: " + data);
        // 移除 null 终止符
        data = data.split('\0').join('');

        var response:Object = jsonParser.parse(data);

        if (response.success) {
            if (response.task == "audio") {
                // 处理音频任务的成功响应
                trace("Audio task succeeded: " + response.message);
            } else {
                // 处理其他任务的成功响应
                trace("Task succeeded. Result: " + response.result);
            }
        } else {
            // 处理错误信息
            trace("Task failed. Error: " + response.error);
        }
    }


    public function onSocketClose():Void {
        trace("XMLSocket connection closed");
        isSocketConnected = false; // 标记为未连接
        // 尝试重新连接
        setTimeout(Delegate.create(this, connectToSocket), 1000); // 1秒后重试连接
    }

    // 发送消息的函数，检查是否已连接
    public function sendSocketMessage(message:String):Void {
        if (isSocketConnected) {
            xmlSocket.send(message + '\0');
            trace("Sent message to server: " + message);
        } else {
            trace("Socket not connected. Cannot send message.");
        }
    }

    // 删除自定义的 JSON 序列化和解析函数

    // 使用 JSON 类进行序列化
    public function sendTaskToNode(taskType:String, payload:Object, extra:Object):Void {
        var message:Object = new Object();
        message.task = taskType;
        message.payload = payload;
        if (extra != null) {
            message.extra = extra;
        }

        var messageString:String = jsonParser.stringify(message);
        if (messageString == null) {
            trace("Failed to stringify message.");
            return;
        }

        sendSocketMessage(messageString);
    }


    // 具体任务执行函数

    // 执行 eval 任务
    public function executeEvalTask(code:String):Void {
        sendTaskToNode("eval", code, null);
    }

    // 执行正则表达式匹配任务
    public function executeRegexTask(text:String, pattern:String, flags:String):Void {
        var extra:Object = new Object();
        extra.pattern = pattern;
        extra.flags = flags;

        sendTaskToNode("regex", text, extra);
    }

    // 执行计算任务
    public function executeComputationTask(data:Array):Void {
        var extra:Object = new Object();
        extra.data = data;

        sendTaskToNode("computation", null, extra);
    }

    // 示例：使用 socket 进行计算密集型任务
    public function heavyComputation(data:String):Void {
        sendSocketMessage(data);
    }

    // 执行音频任务
    public function executeAudioTask(action:String, src:String, options:Object):Void {
        var payload:Object = new Object();
        payload.action = action;
        if (src != null) {
            payload.src = src;
        }
        if (options != null) {
            payload.options = options;
        }

        sendTaskToNode("audio", payload, null);
    }

}
