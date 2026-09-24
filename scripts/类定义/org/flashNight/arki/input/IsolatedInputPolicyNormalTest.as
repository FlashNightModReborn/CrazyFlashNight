/** Normal-entry regression: an absent candidate capability must retain real drivers. */
class org.flashNight.arki.input.IsolatedInputPolicyNormalTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var callbacks:Number;
    private static function check(value:Boolean, label:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] IsolationNormal: " + label); }
    }
    public static function runAllTests():Void {
        passed = failed = callbacks = 0;
        check(!org.flashNight.arki.input.IsolatedInputPolicy.forbidsLegacyDrivers(), "normal capability absent");
        check(org.flashNight.arki.key.KeyManager.getKeyName(69) == "E", "real key labels retained");
        check(typeof _root.keyPollMC.onEnterFrame == "function", "normal key polling installed");
        var timer:Object = org.flashNight.neur.Timer.FrameTimer.getInstance();
        // Exercise a fresh normal constructor after the TestLoader timeline's
        // own placed clips exist; do not assume early dynamic depths survive it.
        timer.destroy(); timer = org.flashNight.neur.Timer.FrameTimer.getInstance();
        check(typeof _root.__FRAME_TIMER_INSTANCE__.onEnterFrame == "function", "fresh normal frame driver installed");
        var callback:Function = function():Void { org.flashNight.arki.input.IsolatedInputPolicyNormalTest.callbacks++; };
        timer.addTask(callback); timer.update(); timer.removeTask(callback); timer.update();
        check(callbacks == 1, "frame task add and remove work");
        var wheel:Object = org.flashNight.neur.ScheduleTimer.CooldownWheel.I();
        check(typeof _root._cdWheel.onEnterFrame == "function", "normal wheel driver installed");
        wheel.reset(); wheel.add(1, callback); wheel.tick();
        check(callbacks == 2, "normal wheel callback executes");
        var enhanced:Object = org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel.I();
        enhanced.reset();
        var id:Number = enhanced.addDelayedTask(1, callback); wheel.tick();
        check(id > 0 && callbacks == 3, "normal delayed task executes");
        var cancelled:Number = enhanced.addDelayedTask(1, callback); enhanced.removeTask(cancelled); wheel.tick();
        check(callbacks == 3, "normal delayed cancellation works");
        _global.__cf7InputIsolationBootstrapV1 = {v:1, mode:"closed-legacy-drivers", module:"C1Island.swf"};
        check(!org.flashNight.arki.input.IsolatedInputPolicy.isValid(), "late flag cannot certify an already running VM");
        check(!org.flashNight.arki.input.IsolatedInputPolicy.forbidsLegacyDrivers(), "late flag does not rewrite normal entry semantics");
        delete _global.__cf7InputIsolationBootstrapV1;
        trace("IsolatedInputPolicyNormalTest Tests Passed: " + passed);
        trace("IsolatedInputPolicyNormalTest Tests Failed: " + failed);
    }
}
