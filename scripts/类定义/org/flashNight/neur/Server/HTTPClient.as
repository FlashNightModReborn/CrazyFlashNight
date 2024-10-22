// 文件路径: org/flashNight/neur/Server/HTTPClient.as
import org.flashNight.neur.Server.ServerManager;
import org.flashNight.neur.Event.EventBus;

class org.flashNight.neur.Server.HTTPClient {
    private var portList:Array;
    private var portIndex:Number;
    private var currentPort:Number;
    private var isSending:Boolean = false;
    private var reconnectionAttempts:Number = 0;
    private var maxReconnectionAttempts:Number;
    private var reconnectionDelayFrames:Number;
    private var framesSinceLastReconnectionAttempt:Number = 0;
    private var isReconnecting:Boolean = false;

    private var eventBus:EventBus;

    public function HTTPClient(ports:Array, maxAttempts:Number, delayFrames:Number) {
        portList = ports;
        portIndex = 0;
        currentPort = null;
        maxReconnectionAttempts = maxAttempts;
        reconnectionDelayFrames = delayFrames;
        eventBus = EventBus.getInstance();

        // 订阅 frameUpdate 事件
        eventBus.subscribe("frameUpdate", onFrameUpdate, this);
    }

    /**
     * 开始端口检测
     */
    public function getAvailablePort():Void {
        getAvailablePortInternal();
    }

    private function getAvailablePortInternal():Void {
        if (portIndex < portList.length) {
            var port:Number = portList[portIndex];
            trace("HTTPClient: Trying to connect to HTTP server on port: " + port);
            testConnection(port);
        } else {
            trace("HTTPClient: No available ports found.");
            // 发布端口检测失败事件
            eventBus.publish("httpPortDetectionFailed");
        }
    }

    public function getCurrentPort():Number {
        return currentPort;
    }

    /**
     * 测试与指定端口的连接
     * @param port 要测试的端口号
     */
    private function testConnection(port:Number):Void {
        var lv:LoadVars = new LoadVars();
        var self:HTTPClient = this;

        lv.onLoad = function(success:Boolean):Void {
            if (success) {
                self.onPortSuccess(port);
            } else {
                self.onPortFailure(port);
            }
        };

        lv.sendAndLoad("http://localhost:" + port + "/testConnection", lv, "POST");
    }

    /**
     * 端口连接成功的处理
     * @param port 成功连接的端口号
     */
    private function onPortSuccess(port:Number):Void {
        trace("HTTPClient: Connected to HTTP server on port: " + port);
        currentPort = port;
        reconnectionAttempts = 0;
        isReconnecting = false;
        framesSinceLastReconnectionAttempt = 0;

        // 发布端口连接成功事件
        eventBus.publish("httpPortConnected", currentPort);
    }

    /**
     * 端口连接失败的处理
     * @param port 失败的端口号
     */
    private function onPortFailure(port:Number):Void {
        trace("HTTPClient: Failed to connect to HTTP server on port: " + port);
        reconnectionAttempts++;
        framesSinceLastReconnectionAttempt = 0;

        if (reconnectionAttempts < maxReconnectionAttempts) {
            isReconnecting = true;
            trace("HTTPClient: Reconnection attempt " + reconnectionAttempts + " scheduled in " + reconnectionDelayFrames + " frames.");
        } else {
            isReconnecting = false;
            trace("HTTPClient: Max reconnection attempts reached. Giving up.");
            // 发布端口检测失败事件
            eventBus.publish("httpPortDetectionFailed");
        }

        portIndex++;
        if (portIndex >= portList.length) {
            portIndex = 0; // 循环尝试端口列表
        }

        // 尝试下一个端口
        getAvailablePortInternal();
    }

    /**
     * 处理 frameUpdate 事件
     * @param currentFrame 当前帧数
     */
    private function onFrameUpdate(currentFrame:Number):Void {
        if (isReconnecting) {
            framesSinceLastReconnectionAttempt++;
            if (framesSinceLastReconnectionAttempt >= reconnectionDelayFrames) {
                isReconnecting = false;
                framesSinceLastReconnectionAttempt = 0;
                trace("HTTPClient: Attempting reconnection...");
                getAvailablePortInternal();
            }
        }

        // 如果没有在发送消息且有可发送的消息
        if (!isSending && currentPort != null) {
            var manager:ServerManager = ServerManager.getInstance();
            var message:String = manager.getMessagesToSend();
            if (message.length > 0) {
                sendMessage(message, currentFrame);
            }
        }
    }

    /**
     * 发送消息
     * @param messageBuffer 要发送的消息
     * @param currentFrame 当前帧数
     */
    public function sendMessage(messageBuffer:String, currentFrame:Number):Void {
        if (currentPort == null) {
            trace("HTTPClient: No current HTTP port available. Cannot send messages.");
            return;
        }

        if (isSending) {
            trace("HTTPClient: Already sending messages. Send aborted.");
            return;
        }

        var lv:LoadVars = new LoadVars();
        var self:HTTPClient = this;

        lv.frame = currentFrame;
        lv.messages = messageBuffer;

        trace("HTTPClient: Sending messages for frame " + currentFrame + ": " + messageBuffer + " to HTTP port: " + currentPort);

        isSending = true;

        lv.onLoad = function(success:Boolean):Void {
            isSending = false;
            if (success) {
                trace("HTTPClient: Messages sent successfully.");
                // 发布消息发送成功事件
                eventBus.publish("httpMessageSent");
            } else {
                trace("HTTPClient: Failed to send messages.");
                // 发布消息发送失败事件
                eventBus.publish("httpMessageFailed");
            }
        };

        lv.sendAndLoad("http://localhost:" + currentPort + "/logBatch", lv, "POST");
    }
}
