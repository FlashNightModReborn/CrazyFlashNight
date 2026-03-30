import org.flashNight.neur.Server.ServerManager;

// ServerManager 集成测试用例
// 在 TestLoader.as 中 import 本文件内容运行，需要 C# Guardian Launcher 在后台运行。

var manager:ServerManager = ServerManager.getInstance();

// === Step 1: FSM 状态转换验证 ===
// 构造函数自动启动状态机，trace 输出：
//   [FSM] DISCONNECTED -> HTTP_PROBING (retry=0, frame=0)
//   [FSM] HTTP_PROBING -> FETCHING_PORT (retry=0, frame=N)
//   [FSM] FETCHING_PORT -> SOCKET_CONNECTING (retry=0, frame=N)
//   [FSM] SOCKET_CONNECTING -> CONNECTED (retry=0, frame=N)
trace("Step 1: FSM should auto-transition to CONNECTED (check trace above)");

// === Step 2: 模拟帧更新 ===
trace("Step 2: Simulating frame updates...");
for (var i:Number = 0; i < 5; i++) {
    manager.onEnterFrameHandler();
}

// === Step 3: 消息缓冲测试 ===
trace("Step 3: Testing message buffering...");
manager.sendServerMessage("Test message 1");
manager.sendServerMessage("Test message 2");
manager.sendServerMessage("Test message 3");
manager.onEnterFrameHandler(); // 触发缓冲区发送

// === Step 4: Socket 消息发送 ===
trace("Step 4: Testing sendSocketMessage...");
trace("isSocketConnected = " + manager.isSocketConnected);
if (manager.isSocketConnected) {
    // 发送 toast task（活跃 task，fire-and-forget）
    trace("Sending toast task...");
    manager.sendTaskToNode("toast", "ServerManager test OK", null);

    // 发送带回调的 task
    trace("Sending gomoku_eval with callback (will timeout if no rapfi)...");
    manager.sendTaskWithCallback("gomoku_eval",
        {board: "test", timeLimit: 1000}, null,
        function(response:Object):Void {
            trace("Callback received: success=" + response.success);
        }
    );
}

// === Step 5: 断线重连测试 ===
trace("Step 5: Simulating disconnection...");
if (manager.xmlSocket != null) {
    manager.xmlSocket.close();
    // FSM 应输出：[FSM] CONNECTED -> FETCHING_PORT
    // 然后自动重新发现端口并恢复连接
}

trace("Testing complete. Async results will appear in subsequent traces.");
