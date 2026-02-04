import org.flashNight.neur.PerformanceOptimizer.IntervalSampler;

/**
 * IntervalSamplerTest - 变周期采样器单元测试
 */
class org.flashNight.neur.PerformanceOptimizer.test.IntervalSamplerTest {

    public static function runAllTests():String {
        var out:String = "=== IntervalSamplerTest ===\n";
        out += test_tickTriggersAtZero();
        out += test_measureAndReset();
        return out + "\n";
    }

    private static function test_tickTriggersAtZero():String {
        var out:String = "[tick]\n";
        var s:IntervalSampler = new IntervalSampler(30);

        var ok:Boolean = true;
        for (var i:Number = 0; i < 29; i++) {
            ok = ok && (s.tick() == false);
        }
        ok = ok && (s.getFramesLeft() == 1);
        ok = ok && (s.tick() == true);
        ok = ok && (s.getFramesLeft() == 0);

        out += line(ok, "倒计时29次不触发，第30次触发");
        return out;
    }

    private static function test_measureAndReset():String {
        var out:String = "[measure/reset]\n";
        var s:IntervalSampler = new IntervalSampler(30);
        s.setFrameStartTime(0);

        var fps0:Number = s.measure(1000, 0);
        out += line(almostEqual(fps0, 30.0, 0.0001), "level0: dt=1s → FPS=30.0");

        var dt:Number = s.getDeltaTimeSec(1000);
        out += line(almostEqual(dt, 1.0, 0.0001), "dtSec=1.0");

        out += line(s.getPIDDeltaTimeFrames(3) == 120, "PID deltaFrames: level3→120");

        s.resetInterval(1000, 2);
        out += line(s.getFrameStartTime() == 1000, "resetInterval: frameStartTime更新");
        out += line(s.getFramesLeft() == 90, "resetInterval: level2→90帧");

        s.setProtectionWindow(2000, 1, 2);
        out += line(s.getFramesLeft() == 90, "protection: max(30*1, 30*(1+2))=90");

        s.setProtectionWindow(2000, 10, 2);
        out += line(s.getFramesLeft() == 300, "protection: max(30*10, 90)=300");

        return out;
    }

    private static function line(ok:Boolean, msg:String):String {
        return "  " + (ok ? "✓ " : "✗ ") + msg + "\n";
    }

    private static function almostEqual(a:Number, b:Number, eps:Number):Boolean {
        return Math.abs(a - b) <= eps;
    }
}
