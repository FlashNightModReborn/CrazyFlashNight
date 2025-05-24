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

// 等待连接成功后发送任务
trace("Waiting for XMLSocket connection to be established...");
var connectionInterval = setInterval(function() {
    if (manager.isSocketConnected) {
        clearInterval(connectionInterval);
        trace("Sending message to XMLSocket server...");
        manager.sendSocketMessage('{"message":"Hello XMLSocket Server"}');
        
        // 发送基础任务
        executeBasicTasks();
        
        // 开始音频控制任务测试
        testAudioControlTasks();
    } else {
        trace("Waiting for socket connection...");
    }
}, 500); // 每500毫秒检查一次

// 执行基础测试任务的函数
function executeBasicTasks():Void {
    // 发送 eval 任务
    trace("Sending eval task...");
    manager.executeEvalTask("Math.pow(2, 3)"); // 应返回 8

    // 发送正则表达式匹配任务
    trace("Sending regex task...");
    manager.executeRegexTask("hello world", "hello", ""); // 应返回 match array

    // 发送计算任务
    trace("Sending computation task...");
    manager.executeComputationTask([1, 2, 3, 4]); // 应返回 10
}

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
trace("Testing complete. Awaiting asynchronous task results.");

// 音频控制任务
function testAudioControlTasks():Void {
    // 获取当前 SWF 文件的 URL
    var swfURL:String = _root._url;

    // 提取到 "resources" 的基础路径
    var basePathIndex:Number = swfURL.indexOf("resources");
    var basePath:String = swfURL.substring(0, basePathIndex) + "resources/flashswf/sounds/soundManager/LIBRARY/";
    trace("Base Path for LIBRARY: " + basePath);

    // 动态生成音频文件的完整路径
    var audioFilePath:String = basePath + "VOXScrm_Wilhelm scream (ID 0477)_BSB.mp3";
    trace("Audio File Path: " + audioFilePath);

    // 测试音频控制任务
    trace("Testing audio control tasks...");

    // 音频播放和初始化函数
    function initializeAudio():Void {
        trace("Initializing and playing audio...");
        var playOptions:Object = new Object();
        playOptions.volume = 0.5; // 设置初始音量
        playOptions.loop = true;  // 设置循环播放
        manager.executeAudioTask("play", audioFilePath, playOptions);
    }

    // 音量调整函数
    function setVolume(level:Number):Void {
        trace("Sending audio setVolume task...");
        var volumeOptions:Object = new Object();
        volumeOptions.volume = level; // 设置音量
        manager.executeAudioTask("setVolume", audioFilePath, volumeOptions);
    }

    // 暂停音频函数
    function pauseAudio():Void {
        trace("Sending audio pause task...");
        manager.executeAudioTask("pause", audioFilePath, null);
    }

    // 继续播放音频函数
    function resumeAudio():Void {
        trace("Sending audio resume task...");
        manager.executeAudioTask("play", audioFilePath, null); // 使用当前实例恢复播放
    }

    // 停止音频函数
    function stopAudio():Void {
        trace("Sending audio stop task...");
        manager.executeAudioTask("stop", audioFilePath, null);
    }

    // 先初始化并播放音频
    initializeAudio();

    // 延迟操作：音量调整
    setTimeout(function() {
        setVolume(0.8); // 2 秒后调整音量至 80%
    }, 2000);

    // 延迟操作：暂停音频
    setTimeout(function() {
        pauseAudio(); // 5 秒后暂停音频
    }, 5000);

    // 延迟操作：继续播放音频
    setTimeout(function() {
        resumeAudio(); // 7 秒后继续播放
    }, 7000);

    // 延迟操作：停止音频
    setTimeout(function() {
        stopAudio(); // 10 秒后停止音频
    }, 10000);

    // 测试完成，等待异步任务结果
    trace("Audio testing complete. Awaiting asynchronous task results.");
}
