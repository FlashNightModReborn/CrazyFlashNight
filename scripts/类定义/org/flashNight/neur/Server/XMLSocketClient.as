import org.flashNight.neur.Event.Delegate;

class org.flashNight.neur.Server.XMLSocketClient {
    public var xmlSocket:XMLSocket;
    public var isSocketConnected:Boolean = false;
    public var jsonParser:JSON;
    public var storedHost:String; // 存储的主机信息
    public var storedPort:Number; // 存储的端口信息

    public function XMLSocketClient() {
        jsonParser = new JSON(true); // 宽容模式
    }

    public function connect(socketHost:String, socketPort:Number):Void {
        if (socketPort == null) {
            trace("Socket port not available. Cannot connect.");
            return;
        }

        // 保存连接信息
        storedHost = socketHost;
        storedPort = socketPort;

        xmlSocket = new XMLSocket();
        xmlSocket.onConnect = Delegate.create(this, onSocketConnect);
        xmlSocket.onData = Delegate.create(this, onSocketData);
        xmlSocket.onClose = Delegate.create(this, onSocketClose);

        xmlSocket.connect(socketHost, socketPort);
    }

    public function onSocketConnect(success:Boolean):Void {
        if (success) {
            trace("XMLSocket connected to server.");
            isSocketConnected = true;
        } else {
            trace("Failed to connect XMLSocket to server.");
            isSocketConnected = false;
        }
    }

    public function onSocketClose():Void {
        trace("XMLSocket connection closed");
        isSocketConnected = false;
        // 尝试重新连接
        setTimeout(Delegate.create(this, reconnect), 1000);
    }

    public function reconnect():Void {
        // 使用存储的连接信息重新连接
        if (storedHost != null && storedPort != null) {
            trace("Reconnecting to " + storedHost + ":" + storedPort);
            connect(storedHost, storedPort);
        } else {
            trace("No host or port stored. Cannot reconnect.");
        }
    }

    public function onSocketData(data:String):Void {
        trace("Received data from server: " + data);
        data = data.split('\0').join('');

        var response:Object = jsonParser.parse(data);
        if (jsonParser.errors.length > 0) {
            trace("JSON parsing errors: " + jsonParser.errors);
            return;
        }

        if (response.success) {
            if (response.result !== undefined) {
                trace("Task succeeded. Result: " + response.result);
            }
            if (response.match !== undefined) {
                trace("Regex Match Result: " + response.match);
            }
        } else {
            trace("Task failed. Error: " + response.error);
        }
    }

    public function sendMessage(message:String):Void {
        if (isSocketConnected) {
            xmlSocket.send(message + '\0');
            trace("Sent message to server: " + message);
        } else {
            trace("Socket not connected. Cannot send message.");
        }
    }

    // 任务方法
    public function executeEvalTask(code:String):Void {
        var message:Object = {
            task: "eval",
            payload: code,
            extra: null
        };
        sendTask(message);
    }

    public function executeRegexTask(text:String, pattern:String, flags:String):Void {
        var message:Object = {
            task: "regex",
            payload: text,
            extra: {
                pattern: pattern,
                flags: flags
            }
        };
        sendTask(message);
    }

    public function executeComputationTask(data:Array):Void {
        var message:Object = {
            task: "computation",
            payload: null,
            extra: {
                data: data
            }
        };
        sendTask(message);
    }

    public function sendTask(message:Object):Void {
        var messageString:String = jsonParser.stringify(message);
        if (messageString == null) {
            trace("Failed to stringify message.");
            return;
        }
        sendMessage(messageString);
    }
}
