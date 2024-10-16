import org.flashNight.neur.Event.Delegate;

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
        extractPorts();
        initFrameClip();
        getAvailablePort(); // 启动端口检测
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
            trace("Trying to connect to port: " + port);

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
        trace("Connected to port: " + port);
        currentPort = port;

        // 重置重连相关变量
        reconnectionAttempts = 0;
        framesSinceLastReconnectionAttempt = 0;
        isReconnecting = false;

        trace("Messages are queued and will be sent in the next frame.");
    }

    private function onPortFailure(port:Number):Void {
        trace("Failed to connect to port: " + port);
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

    // 发送服务器消息（将消息追加到messageBuffer）
    public function sendServerMessage(message:String):Void {
        // 验证消息内容，确保只接受字符串且不包含非法字符
        if (typeof(message) != "string" || message.indexOf("{") != -1 || message.indexOf("}") != -1) {
            trace("Invalid message format. Only plain strings without '{}' are allowed.");
            return;
        }

        // 将消息追加到消息缓冲区
        if (messageBuffer.length > 0) {
            messageBuffer += "|" + message;
        } else {
            messageBuffer = message;
        }

        trace("Message appended to buffer: " + message);
    }

    // 每帧处理请求队列和消息发送
    private function onEnterFrameHandler():Void {
        // 增加帧计数
        currentFrame++;

        // 重置hasSentThisFrame标志
        hasSentThisFrame = false;

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
            trace("No current port available. Cannot send messages.");
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

        trace("Sending messages for frame " + currentFrame + ": " + messageToSend + " to port: " + currentPort);

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
}
