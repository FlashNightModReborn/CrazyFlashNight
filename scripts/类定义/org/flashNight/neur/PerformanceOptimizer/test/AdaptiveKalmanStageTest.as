import org.flashNight.neur.Controller.SimpleKalmanFilter1D;
import org.flashNight.neur.PerformanceOptimizer.AdaptiveKalmanStage;

/**
 * AdaptiveKalmanStageTest - 自适应卡尔曼阶段单元测试
 */
class org.flashNight.neur.PerformanceOptimizer.test.AdaptiveKalmanStageTest {

    public static function runAllTests():String {
        var out:String = "=== AdaptiveKalmanStageTest ===\n";
        out += test_qScalingAndClamp();
        out += test_estimateMovesTowardMeasurement();
        return out + "\n";
    }

    private static function test_qScalingAndClamp():String {
        var out:String = "[Q scaling]\n";
        var kf:SimpleKalmanFilter1D = new SimpleKalmanFilter1D(30, 0.5, 1);
        var stage:AdaptiveKalmanStage = new AdaptiveKalmanStage(kf, 0.1, 0.01, 2.0);

        stage.reset(30, 1);
        stage.filter(20, 0.5); // Q=0.05
        out += line(almostEqual(kf.getProcessNoise(), 0.05, 0.0001), "dt=0.5 → Q=0.05");

        stage.filter(20, 0.001); // Q=0.0001 clamp→0.01
        out += line(almostEqual(kf.getProcessNoise(), 0.01, 0.0001), "dt=0.001 → Q clamp到0.01");

        stage.filter(20, 100); // Q=10 clamp→2
        out += line(almostEqual(kf.getProcessNoise(), 2.0, 0.0001), "dt=100 → Q clamp到2.0");

        return out;
    }

    private static function test_estimateMovesTowardMeasurement():String {
        var out:String = "[estimate]\n";
        var kf:SimpleKalmanFilter1D = new SimpleKalmanFilter1D(30, 0.5, 1);
        var stage:AdaptiveKalmanStage = new AdaptiveKalmanStage(kf, 0.1, 0.01, 2.0);

        stage.reset(30, 1);
        var est:Number = stage.filter(10, 1);
        out += line(est < 30 && est > 10, "估计值向测量值移动（10 < est < 30）");

        return out;
    }

    private static function line(ok:Boolean, msg:String):String {
        return "  " + (ok ? "✓ " : "✗ ") + msg + "\n";
    }

    private static function almostEqual(a:Number, b:Number, eps:Number):Boolean {
        return Math.abs(a - b) <= eps;
    }
}
