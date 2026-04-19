import org.flashNight.neur.Server.BootstrapHandshake;

/**
 * BootstrapHandshakeTest - 10b 绿阶段
 * 四场景: success / timeout / invalid_response / done 锁存
 * 用 _onResponseForTest / _triggerTimeoutForTest 绕过 socket
 */
class org.flashNight.neur.Server.test.BootstrapHandshakeTest {

    private static var testCount:Number = 0;
    private static var passedCount:Number = 0;
    private static var failedCount:Number = 0;

    public static function runAllTests():Void {
        trace("========== BootstrapHandshakeTest START ==========");
        testCount = 0; passedCount = 0; failedCount = 0;

        test_start_transitions_to_WaitResp();
        test_success_response_sets_done();
        test_done_latch_blocks_late_callback();
        test_invalid_response_fails();
        test_timeout_fails_closed();
        test_custom_timeout_still_fails_closed();

        trace("========== BootstrapHandshakeTest END: " + passedCount + "/" + testCount + " passed, " + failedCount + " failed ==========");
    }

    private static function assert(cond:Boolean, msg:String):Void {
        testCount++;
        if (cond) { passedCount++; trace("[PASS] " + msg); }
        else { failedCount++; trace("[FAIL] " + msg); }
    }

    // start() 后状态应为 Sending 或 WaitResp
    private static function test_start_transitions_to_WaitResp():Void {
        BootstrapHandshake.start("attempt_001", null, null);
        var s:String = BootstrapHandshake.getState();
        assert(s == "Sending" || s == "WaitResp", "start_transitions: state=" + s);
    }

    // 成功响应 → _done=true + onSuccess 调用
    private static function test_success_response_sets_done():Void {
        var successCalled:Boolean = false;
        var receivedResp:Object = null;
        BootstrapHandshake.start("attempt_002",
            function(r:Object):Void { successCalled = true; receivedResp = r; },
            null);
        BootstrapHandshake._onResponseForTest({ success: true, savePath: "test_slot", attemptId: "attempt_002" });
        assert(BootstrapHandshake.isDone() == true, "success: done latched");
        assert(successCalled == true, "success: onSuccess called");
        assert(BootstrapHandshake.getState() == "Success", "success: state=" + BootstrapHandshake.getState());
    }

    // _done 锁存后, 再次调用 handleResponse 不应重复触发
    private static function test_done_latch_blocks_late_callback():Void {
        var count:Number = 0;
        BootstrapHandshake.start("attempt_003",
            function(r:Object):Void { count++; },
            null);
        BootstrapHandshake._onResponseForTest({ success: true, savePath: "x" });
        BootstrapHandshake._onResponseForTest({ success: true, savePath: "y" });  // 晚到, 应忽略
        assert(count == 1, "done_latch: onSuccess called exactly once, got " + count);
    }

    // invalid_response: success:true 但 savePath 缺失
    private static function test_invalid_response_fails():Void {
        var failReason:String = null;
        BootstrapHandshake.start("attempt_004", null,
            function(r:String):Void { failReason = r; });
        BootstrapHandshake._onResponseForTest({ success: true /* no savePath */ });
        assert(failReason == "invalid_response", "invalid_response: reason=" + failReason);
        assert(BootstrapHandshake.getState() == "Failed", "invalid_response: state=Failed");
    }

    // timeout fail-closed
    private static function test_timeout_fails_closed():Void {
        var failReason:String = null;
        BootstrapHandshake.start("attempt_005", null,
            function(r:String):Void { failReason = r; });
        BootstrapHandshake._triggerTimeoutForTest();
        assert(failReason == "timeout", "timeout: reason=" + failReason);
        assert(BootstrapHandshake.getState() == "Failed", "timeout: state=Failed");
    }

    // Phase D Step D1: 自定义 timeoutMs (60s) 路径仍 fail-closed;
    // _triggerTimeoutForTest 直接触发 handleTimeout, 无需真等 60s.
    private static function test_custom_timeout_still_fails_closed():Void {
        var failReason:String = null;
        BootstrapHandshake.start("attempt_006", null,
            function(r:String):Void { failReason = r; },
            60000);
        BootstrapHandshake._triggerTimeoutForTest();
        assert(failReason == "timeout", "custom_timeout: reason=" + failReason);
        assert(BootstrapHandshake.getState() == "Failed", "custom_timeout: state=Failed");
    }
}
