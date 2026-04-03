import org.flashNight.neur.PerformanceOptimizer.IntervalSampler;
import org.flashNight.neur.PerformanceOptimizer.PerformanceScheduler;

/**
 * PerformanceHotPathBenchmark - 热路径微基准测试（简化版）
 *
 * Kalman/PID/HysteresisQuantizer 已迁移到 C# PerfDecisionEngine。
 * 仅保留 AS2 端仍存在的热路径基准：tick、measure、evaluate。
 */
class org.flashNight.neur.PerformanceOptimizer.test.PerformanceHotPathBenchmark {

    private static var ITER_LIGHT:Number = 100000;
    private static var ITER_MEDIUM:Number = 20000;

    public static function runAllTests():String {
        var out:String = "=== PerformanceHotPathBenchmark ===\n";
        out += "  note: same-machine comparison only\n";
        out += bench_intervalSampler_tick();
        out += bench_intervalSampler_measureReset();
        out += bench_scheduler_evaluateFastPath();
        return out + "\n";
    }

    private static function line(name:String, ms:Number, iters:Number, check:Number):String {
        var usPerCall:Number = Math.round(ms / iters * 1000000) / 1000;
        return "  " + name + ": " + ms + "ms / " + iters + " = " + usPerCall + " us/call  [chk=" + check + "]\n";
    }

    // --- IntervalSampler.tick (每帧) ---
    private static function bench_intervalSampler_tick():String {
        var s:IntervalSampler = new IntervalSampler(30);
        var checksum:Number = 0;
        var t0:Number = getTimer();
        for (var i:Number = 0; i < ITER_LIGHT; i++) {
            s._framesLeft = 30;
            if (s.tick()) checksum++;
        }
        var elapsed:Number = getTimer() - t0;
        return line("IntervalSampler.tick", elapsed, ITER_LIGHT, checksum);
    }

    // --- IntervalSampler.measure + resetInterval (每采样窗口) ---
    private static function bench_intervalSampler_measureReset():String {
        var s:IntervalSampler = new IntervalSampler(30);
        var checksum:Number = 0;
        var now:Number = getTimer();
        s.resetInterval(now, 0);
        var t0:Number = getTimer();
        for (var i:Number = 0; i < ITER_MEDIUM; i++) {
            var fps:Number = s.measure(now + 1000, 0);
            s.resetInterval(now + 1000, 0);
            checksum += fps;
            now += 1000;
        }
        var elapsed:Number = getTimer() - t0;
        return line("IntervalSampler.measure+reset", elapsed, ITER_MEDIUM, Math.round(checksum));
    }

    // --- PerformanceScheduler.evaluate 快速路径 (帧内 --framesLeft != 0) ---
    private static function bench_scheduler_evaluateFastPath():String {
        var host:Object = { 性能等级上限: 0, offsetTolerance: 10 };
        var mockRoot:Object = { _quality: "HIGH", 天气系统: undefined };
        mockRoot.面积系数 = 300000;
        mockRoot.同屏打击数字特效上限 = 25;
        mockRoot.发射效果上限 = 15;
        mockRoot.显示列表 = { 预设任务ID: 0, 继续播放: function() {}, 暂停播放: function() {} };
        var env:Object = { root: mockRoot };
        var scheduler:PerformanceScheduler = new PerformanceScheduler(host, 30, 26, "HIGH", env);
        // 设置 framesLeft 确保不到达采样点
        scheduler.getSampler()._framesLeft = ITER_LIGHT + 10;
        var checksum:Number = 0;
        var t0:Number = getTimer();
        for (var i:Number = 0; i < ITER_LIGHT; i++) {
            scheduler.evaluate();
            checksum++;
        }
        var elapsed:Number = getTimer() - t0;
        return line("Scheduler.evaluate(fast-path)", elapsed, ITER_LIGHT, checksum);
    }
}
