import org.flashNight.neur.Server.BootstrapWait;

/**
 * BootstrapWaitTest - 10b 绿阶段
 * 场景: startWait 进 Waiting / 完成推进 / 超时 fail-closed
 */
class org.flashNight.neur.Server.test.BootstrapWaitTest {

    private static var testCount:Number = 0;
    private static var passedCount:Number = 0;
    private static var failedCount:Number = 0;

    public static function runAllTests():Void {
        trace("========== BootstrapWaitTest START ==========");
        testCount = 0; passedCount = 0; failedCount = 0;

        test_startWait_sets_state_Waiting();
        test_recovery_done_advances();
        test_timeout_fails_closed();

        trace("========== BootstrapWaitTest END: " + passedCount + "/" + testCount + " passed, " + failedCount + " failed ==========");
    }

    private static function assert(cond:Boolean, msg:String):Void {
        testCount++;
        if (cond) { passedCount++; trace("[PASS] " + msg); }
        else { failedCount++; trace("[FAIL] " + msg); }
    }

    // startWait() 后状态 Waiting
    private static function test_startWait_sets_state_Waiting():Void {
        BootstrapWait.startWait(5000, null, "bootstrap_ready_send");
        assert(BootstrapWait.getState() == "Waiting", "startWait_state: " + BootstrapWait.getState());
    }

    // 存档恢复完成时 tick 应推进到 Success
    private static function test_recovery_done_advances():Void {
        // 设置 _root.存档恢复等待中 返回 false (不 pending)
        _root["存档恢复等待中"] = function():Boolean { return false; };
        BootstrapWait.startWait(5000, null, null);
        BootstrapWait._tickForTest();
        assert(BootstrapWait.isDone() == true, "recovery_done: done");
        assert(BootstrapWait.getState() == "Success", "recovery_done: state=" + BootstrapWait.getState());
        delete _root["存档恢复等待中"];
    }

    // 超时 fail-closed: state=Failed, done=true, 不 gotoAndPlay
    private static function test_timeout_fails_closed():Void {
        _root["存档恢复等待中"] = function():Boolean { return true; };  // 一直 pending
        BootstrapWait.startWait(5000, null, "should_not_fire");
        BootstrapWait._forceTimeoutForTest();
        assert(BootstrapWait.isDone() == true, "timeout: done");
        assert(BootstrapWait.getState() == "Failed", "timeout: state=" + BootstrapWait.getState());
        delete _root["存档恢复等待中"];
    }
}
