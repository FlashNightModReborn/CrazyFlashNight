import JSON;
import org.flashNight.neur.Server.*;
class org.flashNight.neur.Server.TaskHandler {
    private var jsonParser:JSON; // JSON parser instance

    /**
     * 构造函数
     * @param jsonParser JSON解析器实例
     */
    public function TaskHandler(jsonParser:JSON) {
        this.jsonParser = jsonParser; // 初始化 JSON 解析器
    }

    /**
     * 使用 JSON 类进行序列化，并发送任务到服务器。
     * @param taskType 任务类型
     * @param payload 任务载荷
     * @param extra 额外参数
     */
    public function sendTaskToNode(taskType:String, payload:String, extra:Object):Void {
        var message:Object = new Object();
        message.task = taskType;
        message.payload = payload;
        message.extra = extra;

        var messageString:String = jsonParser.stringify(message); // 序列化消息
        if (messageString == null) {
            trace("TaskHandler: Failed to stringify message.");
            return;
        }

        sendSocketMessage(messageString); // 发送消息
    }

    /**
     * 发送消息到 XMLSocket 服务器。
     * @param message 要发送的消息
     */
    private function sendSocketMessage(message:String):Void {
        var serverManager:ServerManager = ServerManager.getInstance();
        if (serverManager.isSocketConnected) {
            serverManager.xmlSocket.send(message + '\0'); // 发送带有 null 终止符的消息
            trace("TaskHandler: Sent message to server: " + message);
        } else {
            trace("TaskHandler: Socket not connected. Cannot send message.");
        }
    }

    /**
     * 执行 eval 任务。
     * @param code 要评估的代码
     */
    public function executeEvalTask(code:String):Void {
        sendTaskToNode("eval", code, null);
    }

    /**
     * 执行正则表达式匹配任务。
     * @param text 要匹配的文本
     * @param pattern 正则表达式模式
     * @param flags 正则表达式标志
     */
    public function executeRegexTask(text:String, pattern:String, flags:String):Void {
        var extra:Object = new Object();
        extra.pattern = pattern;
        extra.flags = flags;

        sendTaskToNode("regex", text, extra);
    }

    /**
     * 执行计算任务。
     * @param data 要计算的数据数组
     */
    public function executeComputationTask(data:Array):Void {
        var extra:Object = new Object();
        extra.data = data;

        sendTaskToNode("computation", null, extra);
    }
}
