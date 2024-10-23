import org.flashNight.neur.Server.ServerManager;

// 创建 ServerManager 实例并测试主要功能
var manager:ServerManager = ServerManager.getInstance();

// Step 1: 测试 HTTP 端口连接和重连机制
trace("Testing HTTP port connection...");
// HTTPClient 已经在构造函数中开始端口检测，无需再次调用

// Step 2: 模拟帧更新，测试 EnterFrame 事件的处理能力
trace("Simulating frame updates...");
for (var i:Number = 0; i < 5; i++) {
    manager.onEnterFrameHandler(); // 模拟 5 帧更新
}

// Step 3: 测试消息缓冲和批量消息发送
trace("Testing message buffering and sending...");
manager.sendServerMessage("Test message 1");
manager.sendServerMessage("Test message 2");
manager.sendServerMessage("Test message 3");
manager.onEnterFrameHandler(); // 触发消息发送

// Step 4: 测试 XMLSocket 连接
trace("Testing XMLSocket connection...");
// XMLSocket 连接将在成功获取 socketPort 后自动初始化

// 等待连接成功后发送任务
trace("Waiting for XMLSocket connection to be established...");
var connectionInterval = setInterval(function() {
    if (manager.isSocketConnected) {
        clearInterval(connectionInterval);
        trace("Sending message to XMLSocket server...");
        manager.sendSocketMessage("Hello XMLSocket Server");
        
        // 发送 eval 任务
        trace("Sending eval task...");
        manager.executeEvalTask("Math.pow(2, 3)"); // 应返回 8

        // 发送正则表达式匹配任务
        trace("Sending regex task...");
        manager.executeRegexTask("hello world", "hello", ""); // 应返回 match array

        // 发送计算任务
        trace("Sending computation task...");
        manager.executeComputationTask([1, 2, 3, 4]); // 应返回 10
    } else {
        trace("Waiting for socket connection...");
    }
}, 500); // 每500毫秒检查一次

// Step 5: 测试重连逻辑 (模拟掉线)
trace("Simulating disconnection and reconnection...");
if (manager.xmlSocket != null) {
    manager.xmlSocket.close(); // 模拟 Socket 关闭并触发重连机制
} else {
    trace("ServerManager: XMLSocketClient is not initialized.");
}

// Step 6: 模拟帧更新，观察重连过程
trace("Simulating frame updates for reconnection...");
for (var j:Number = 0; j < 300; j++) { // 模拟 300 帧，重连间隔为 300 帧
    manager.onEnterFrameHandler();
}

// Step 7: 发送任务后等待结果
// 由于是异步操作，结果将在 onSocketData 中处理
trace("Testing complete. Awaiting asynchronous task results.");
