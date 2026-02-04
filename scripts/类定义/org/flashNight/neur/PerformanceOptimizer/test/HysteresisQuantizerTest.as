import org.flashNight.neur.PerformanceOptimizer.HysteresisQuantizer;

/**
 * HysteresisQuantizerTest - 迟滞量化器单元测试
 */
class org.flashNight.neur.PerformanceOptimizer.test.HysteresisQuantizerTest {

    public static function runAllTests():String {
        var out:String = "=== HysteresisQuantizerTest ===\n";
        out += test_twoStepConfirmation();
        out += test_clampByMinLevel();
        return out + "\n";
    }

    private static function test_twoStepConfirmation():String {
        var out:String = "[confirm]\n";
        var q:HysteresisQuantizer = new HysteresisQuantizer(0, 3);

        var r1:Object = q.process(1.2, 0);
        out += line(r1.levelChanged == false && r1.newLevel == 0 && q.isAwaitingConfirmation(), "第一次检测到变化：不切换，进入等待");

        var r2:Object = q.process(1.2, 0);
        out += line(r2.levelChanged == true && r2.newLevel == 1 && !q.isAwaitingConfirmation(), "第二次检测到变化：执行切换到1");

        var r3:Object = q.process(1.2, 1);
        out += line(r3.levelChanged == false && !q.isAwaitingConfirmation(), "候选等于当前：确认状态清空");

        return out;
    }

    private static function test_clampByMinLevel():String {
        var out:String = "[clamp]\n";
        var q:HysteresisQuantizer = new HysteresisQuantizer(2, 3);

        var r1:Object = q.process(0, 3); // round(0)=0 clamp→2
        out += line(r1.levelChanged == false && q.isAwaitingConfirmation(), "候选被clamp到minLevel=2（第一次等待）");

        var r2:Object = q.process(0, 3);
        out += line(r2.levelChanged == true && r2.newLevel == 2, "第二次确认：切换到2");

        q.clearConfirmation();
        out += line(!q.isAwaitingConfirmation(), "clearConfirmation清空状态");

        return out;
    }

    private static function line(ok:Boolean, msg:String):String {
        return "  " + (ok ? "✓ " : "✗ ") + msg + "\n";
    }
}
