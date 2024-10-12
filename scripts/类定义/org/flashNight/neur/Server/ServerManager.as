import org.flashNight.neur.Event.Delegate;

class org.flashNight.neur.Server.ServerManager {
    public static var instance:ServerManager;
    public var portList:Array;
    public var portIndex:Number;
    public var currentPort:Number;
    public var requestQueue:Array;
    public var messageQueue:Array; // 消息队列
    private var frameClip:MovieClip; // 用于管理 enterFrame 事件的影片剪辑

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
        requestQueue = [];
        messageQueue = [];
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
        frameClip.onEnterFrame = Delegate.create(this, processRequestQueue);
    }

    public function getAvailablePort():Void {
        if (portIndex < portList.length) {
            var port:Number = portList[portIndex];
            trace("Trying to connect to port: " + port);

            addToQueue({
                url: "http://localhost:" + port + "/testConnection",
                type: "testConnection",
                onSuccess: Delegate.createWithParams(this, onPortSuccess, [port]),
                onFailure: Delegate.createWithParams(this, onPortFailure, [port])
            });
        } else {
            trace("No available ports found.");
        }
    }

    private function onPortSuccess(port:Number):Void {
        trace("Connected to port: " + port);
        currentPort = port;

        if (messageQueue.length > 0) {
            var messagesToSend:Array = messageQueue.slice();
            messageQueue = [];
            sendMessageBatch(messagesToSend);
        }
    }

    private function onPortFailure(port:Number):Void {
        trace("Failed to connect to port: " + port);
        portIndex++;
        getAvailablePort();
    }

    // 发送服务器消息（始终批量发送）
    public function sendServerMessage(message:String):Void {
        messageQueue.push(message);
        trace("Message queued: " + message);

        if (currentPort != null && messageQueue.length > 0) {
            var messagesToSend:Array = messageQueue.slice();
            messageQueue = [];
            sendMessageBatch(messagesToSend);
        }
    }

    // 批量发送消息的方法
    private function sendMessageBatch(messages:Array):Void {
        var combinedMessages:String = messages.join("|"); // 使用 '|' 作为分隔符
        trace("Sending batch message: " + combinedMessages + " to port: " + currentPort);

        addToQueue({
            url: "http://localhost:" + currentPort + "/logBatch",
            type: "logMessages",
            data: { messages: combinedMessages },
            onSuccess: Delegate.createWithParams(this, onMessageSuccess, [currentPort]),
            onFailure: Delegate.createWithParams(this, onMessageFailure, [currentPort])
        });
    }

    /*
    // 移除 sendMessage 方法，确保所有消息通过批量发送
    private function sendMessage(message:String):Void {
        trace("Sending message: " + message + " to port " + currentPort);

        addToQueue({
            url: "http://localhost:" + currentPort + "/log",
            type: "logMessage",
            data: { message: message },
            onSuccess: Delegate.createWithParams(this, onMessageSuccess, [currentPort]),
            onFailure: Delegate.createWithParams(this, onMessageFailure, [currentPort])
        });
    }
    */

    private function onMessageSuccess(port:Number):Void {
        trace("Message sent to port " + port);
    }

    private function onMessageFailure(port:Number):Void {
        trace("Failed to send message to port " + port);
    }

    private function addToQueue(request:Object):Void {
        if (request.type == "testConnection") {
            var exists:Boolean = false;
            for (var i:Number = 0; i < requestQueue.length; i++) {
                if (requestQueue[i].type == request.type) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                requestQueue.push(request);
                trace("Request added to queue: " + request.type + " for URL: " + request.url);
            } else {
                trace("Duplicate testConnection request not added.");
            }
        } else {
            requestQueue.push(request);
            trace("Request added to queue: " + request.type + " for URL: " + request.url);
        }
    }

    public function processRequestQueue():Void {
        while (requestQueue.length > 0) {
            var request:Object = requestQueue.shift();
            var lv:LoadVars = new LoadVars();

            if (request.data != undefined) {
                for (var key:String in request.data) {
                    lv[key] = request.data[key];
                    trace("Setting LoadVars key: " + key + " to value: " + request.data[key]);
                }
            }

            lv.onSuccessCallback = request.onSuccess;
            lv.onFailureCallback = request.onFailure;

            lv.onLoad = function(success:Boolean):Void {
                if (success && this.onSuccessCallback != undefined) {
                    this.onSuccessCallback();
                } else if (!success && this.onFailureCallback != undefined) {
                    this.onFailureCallback();
                }
            };

            lv.sendAndLoad(request.url, lv, "POST");
            trace("Request sent: " + request.type + " to " + request.url);
        }
    }
}
