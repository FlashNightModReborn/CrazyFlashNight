/** GameStage 跨 SubStage 计时池的确定性回归。 */
import org.flashNight.arki.scene.StageTimePoolController;
import org.flashNight.arki.scene.StageInfo;

class org.flashNight.arki.scene.StageTimePoolControllerTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var cases:Number = 0;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        cases = 0;
        trace("=== StageTimePoolControllerTest start ===");

        testNoPoolCompatibility(); cases++;
        testContinuousAndReentry(); cases++;
        testGapPauseAndResume(); cases++;
        testOverlapExpiry(); cases++;
        testPauseAndUiCadence(); cases++;
        testCleanupAndRestart(); cases++;
        testValidationFailures(); cases++;
        testStageInfoRefNormalization(); cases++;

        trace("StageTimePoolControllerTest Tests Passed: " + passed);
        trace("StageTimePoolControllerTest Tests Failed: " + failed);
        if (failed > 0 || passed != 46 || cases != 8) {
            throw new Error("StageTimePoolControllerTest failed: " + failed
                + " failures, " + passed + "/46 assertions, " + cases + "/8 cases");
        }
        trace("StageTimePoolControllerTest Cases Passed: 8/8");
        trace("=== StageTimePoolControllerTest end ===");
    }

    private static function testNoPoolCompatibility():Void {
        var controller:StageTimePoolController = new StageTimePoolController();
        check(controller.initialize(null, [[], []]),
            "C01 legacy stage without pools initializes");
        check(!controller.isEnabled() && controller.getPoolCount() == 0,
            "C01 legacy stage keeps timer subsystem disabled");
        controller.enterStage(0);
        check(controller.getActiveCount() == 0 && controller.drainUiCommands().length == 0,
            "C01 legacy stage emits no HUD command");
        check(controller.tick(true) == null,
            "C01 legacy stage tick is a no-op");
    }

    private static function testContinuousAndReentry():Void {
        var controller:StageTimePoolController = new StageTimePoolController();
        check(controller.initialize([pool("rescue", 3, "抵达目标")],
                [["rescue"], ["rescue"]]),
            "C02 continuous pool initializes");
        controller.enterStage(0);
        check(controller.getActiveCount() == 1,
            "C02 first SubStage activates one pool");
        var commands:Array = controller.drainUiCommands();
        check(commands.length == 1 && commands[0].type == "set"
                && commands[0].remainingSeconds == 3,
            "C02 entering stage emits initial full-duration HUD value");
        check(tickFrames(controller, 30) == null
                && controller.getRemainingSeconds("rescue") == 2,
            "C02 thirty active frames consume one second");
        controller.leaveStage();
        commands = controller.drainUiCommands();
        check(commands.length == 2 && commands[0].type == "set"
                && commands[1].type == "clear",
            "C02 leave drains cadence update then clears active HUD row");
        controller.enterStage(1);
        commands = controller.drainUiCommands();
        check(commands.length == 1 && commands[0].remainingSeconds == 2,
            "C02 re-entry resumes instead of resetting duration");
        check(tickFrames(controller, 59) == null
                && controller.getRemainingFrames("rescue") == 1,
            "C02 pool remains alive until its exact final frame");
        check(controller.tick(true) == "rescue"
                && controller.getRemainingFrames("rescue") == 0,
            "C02 exact final frame raises one timeout result");
    }

    private static function testGapPauseAndResume():Void {
        var controller:StageTimePoolController = new StageTimePoolController();
        check(controller.initialize([pool("route_a", 4, "章节 A")],
                [["route_a"], [], ["route_a"]]),
            "C03 non-contiguous pool initializes");
        controller.enterStage(0);
        controller.drainUiCommands();
        tickFrames(controller, 30);
        check(controller.getRemainingSeconds("route_a") == 3,
            "C03 first tagged stage consumes time");
        controller.leaveStage();
        controller.drainUiCommands();
        controller.enterStage(1);
        check(controller.getActiveCount() == 0,
            "C03 untagged gap has no active pool");
        check(tickFrames(controller, 90) == null
                && controller.getRemainingSeconds("route_a") == 3,
            "C03 untagged gap does not consume retained time");
        controller.enterStage(2);
        check(controller.getActiveCount() == 1
                && controller.getRemainingSeconds("route_a") == 3,
            "C03 later tagged stage resumes retained pool");
    }

    private static function testOverlapExpiry():Void {
        var controller:StageTimePoolController = new StageTimePoolController();
        check(controller.initialize([
                pool("route_a", 2, "章节 A"),
                pool("route_b", 3, "章节 B")
            ], [["route_a", "route_b"]]),
            "C04 overlapping pools initialize");
        controller.enterStage(0);
        var commands:Array = controller.drainUiCommands();
        check(controller.getActiveCount() == 2 && commands.length == 2,
            "C04 overlapping stage exposes both independent HUD rows");
        check(tickFrames(controller, 59) == null
                && controller.getRemainingFrames("route_a") == 1
                && controller.getRemainingFrames("route_b") == 31,
            "C04 both pools decrement on every shared active frame");
        check(controller.tick(true) == "route_a"
                && controller.getRemainingFrames("route_a") == 0
                && controller.getRemainingFrames("route_b") == 30,
            "C04 first expiring pool wins deterministically without skipping peer tick");
        check(controller.tick(true) == null
                && controller.getRemainingFrames("route_b") == 29,
            "C04 expired pool is idempotent while a peer can still advance");
    }

    private static function testPauseAndUiCadence():Void {
        var controller:StageTimePoolController = new StageTimePoolController();
        check(controller.initialize([pool("pause_test", 2, "暂停测试")],
                [["pause_test"]]),
            "C05 pause fixture initializes");
        controller.enterStage(0);
        controller.drainUiCommands();
        for (var i:Number = 0; i < 60; i++) controller.tick(false);
        check(controller.getRemainingSeconds("pause_test") == 2
                && controller.drainUiCommands().length == 0,
            "C05 paused frames neither consume time nor emit UI churn");
        tickFrames(controller, 29);
        check(controller.getRemainingFrames("pause_test") == 31
                && controller.drainUiCommands().length == 0,
            "C05 HUD is rate-limited until displayed second changes");
        controller.tick(true);
        var commands:Array = controller.drainUiCommands();
        check(controller.getRemainingFrames("pause_test") == 30
                && commands.length == 1 && commands[0].remainingSeconds == 1,
            "C05 second boundary emits exactly one refreshed HUD value");
    }

    private static function testCleanupAndRestart():Void {
        var controller:StageTimePoolController = new StageTimePoolController();
        check(controller.initialize([pool("restart", 2, "重开测试")], [["restart"]]),
            "C06 cleanup fixture initializes");
        controller.enterStage(0);
        controller.drainUiCommands();
        tickFrames(controller, 30);
        check(controller.getRemainingSeconds("restart") == 1,
            "C06 pre-cleanup state is consumed");
        controller.clear();
        var commands:Array = controller.drainUiCommands();
        check(!controller.isEnabled() && controller.getActiveCount() == 0
                && commands.length == 2 && commands[1].type == "clearAll",
            "C06 full cleanup disables state and clears every HUD row");
        controller.clear();
        check(controller.drainUiCommands().length == 0,
            "C06 cleanup is idempotent");
        check(controller.initialize([pool("restart", 2, "重开测试")], [["restart"]])
                && controller.getRemainingSeconds("restart") == 2
                && controller.drainUiCommands().length == 0,
            "C06 new run starts from authored duration without stale commands");
    }

    private static function testValidationFailures():Void {
        var controller:StageTimePoolController = new StageTimePoolController();
        check(!controller.initialize([pool("dup", 2, "A"), pool("dup", 3, "B")],
                [["dup"]]) && controller.getValidationError().indexOf("重复") >= 0,
            "C07 duplicate IDs fail closed");
        check(!controller.initialize(null, [["missing"]])
                && controller.getValidationError().indexOf("未知") >= 0,
            "C07 unknown references fail closed");
        check(!controller.initialize([pool("7", 2, "数字")], [["7"]]),
            "C07 numeric IDs fail closed after XML auto-conversion");
        check(!controller.initialize([pool("bad_label", 2, "坏|标签")], [["bad_label"]]),
            "C07 wire delimiter in display name fails closed");
        check(!controller.initialize([pool("bad_time", 0, "零秒")], [["bad_time"]]),
            "C07 nonpositive duration fails closed");
        check(!controller.initialize([{
                DurationSeconds:2,
                DisplayName:"缺少标识",
                TimeoutResult:"FailStage"
            }], [["undefined"]]),
            "C07 missing ID fails closed before undefined string coercion");
        var missingResult:Object = pool("missing_result", 2, "缺少结果");
        delete missingResult.TimeoutResult;
        check(!controller.initialize([missingResult], [["missing_result"]]),
            "C07 missing timeout result fails closed");
        var unsupported:Object = pool("unsupported", 2, "结果");
        unsupported.TimeoutResult = "ClearStage";
        check(!controller.initialize([unsupported], [["unsupported"]]),
            "C07 unsupported timeout result fails closed");
        check(!controller.initialize([pool("unused", 2, "未引用")], [[]])
                && controller.getValidationError().indexOf("未被") >= 0,
            "C07 unreferenced definitions fail closed");
        check(!controller.initialize([pool("same", 2, "重复引用")],
                [["same", "same"]]),
            "C07 duplicate references in one SubStage fail closed");
        var many:Array = [];
        var refs:Array = [];
        for (var i:Number = 0; i < 5; i++) {
            many.push(pool("pool_" + i, 2, "池 " + i));
            refs.push("pool_" + i);
        }
        check(!controller.initialize(many, [refs]),
            "C07 more than four simultaneous pools fail closed");
    }

    private static function testStageInfoRefNormalization():Void {
        var refs:Array = StageInfo.parseTimePoolRefs({TimePoolRef:"single"});
        check(refs.length == 1 && refs[0] == "single",
            "C08 scalar TimePoolRef normalizes to one-element array");
        refs = StageInfo.parseTimePoolRefs({TimePoolRef:["first", "second"]});
        check(refs.length == 2 && refs[0] == "first" && refs[1] == "second",
            "C08 repeated TimePoolRef preserves XML order");
        refs = StageInfo.parseTimePoolRefs({});
        check(refs.length == 0,
            "C08 missing TimePoolRef normalizes to empty array");
        refs = StageInfo.parseTimePoolRefs({TimePoolRef:7});
        check(refs.length == 1 && refs[0] == "7",
            "C08 numeric XML leaf is explicitly converted before validation");
    }

    private static function pool(id, seconds:Number, label:String):Object {
        return {
            Id:id,
            DurationSeconds:seconds,
            DisplayName:label,
            TimeoutResult:"FailStage"
        };
    }

    private static function tickFrames(controller:StageTimePoolController,
            count:Number):String {
        var firstExpired:String = null;
        for (var i:Number = 0; i < count; i++) {
            var expired:String = controller.tick(true);
            if (firstExpired == null && expired != null) firstExpired = expired;
        }
        return firstExpired;
    }

    private static function check(condition:Boolean, message:String):Void {
        if (condition) {
            passed++;
            trace("PASS: " + message);
        } else {
            failed++;
            trace("[TEST_FAIL] " + message);
        }
    }
}
