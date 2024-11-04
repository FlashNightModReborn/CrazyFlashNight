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
        manager.sendSocketMessage('{"message":"Hello XMLSocket Server"}');
        
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

// 其他测试步骤保持不变...

// Step 8: 测试音频控制任务
trace("Testing audio control tasks...");

// 播放音频
trace("Sending audio play task...");
var playOptions:Object = new Object();
playOptions.volume = 0.5; // 设置初始音量
playOptions.loop = true; // 设置循环播放
manager.executeAudioTask("play", "path/to/your/audio.mp3", playOptions);

// 调整音量
setTimeout(function() {
    trace("Sending audio setVolume task...");
    var volumeOptions:Object = new Object();
    volumeOptions.volume = 0.8; // 调整音量至 80%
    manager.executeAudioTask("setVolume", null, volumeOptions);
}, 2000); // 等待 2 秒后调整音量

// 暂停音频
setTimeout(function() {
    trace("Sending audio pause task...");
    manager.executeAudioTask("pause", null, null);
}, 5000); // 等待 5 秒后暂停音频

// 继续播放音频
setTimeout(function() {
    trace("Sending audio play task to resume...");
    manager.executeAudioTask("play", null, null);
}, 7000); // 等待 2 秒后继续播放

// 停止音频
setTimeout(function() {
    trace("Sending audio stop task...");
    manager.executeAudioTask("stop", null, null);
}, 10000); // 等待 3 秒后停止音频

// Step 9: 测试完成，等待异步任务结果
trace("Audio testing complete. Awaiting asynchronous task results.");

