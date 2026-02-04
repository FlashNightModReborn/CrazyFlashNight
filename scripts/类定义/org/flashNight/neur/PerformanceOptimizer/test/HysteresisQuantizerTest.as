import org.flashNight.neur.PerformanceOptimizer.HysteresisQuantizer;

/**
 * HysteresisQuantizerTest - 迟滞量化器单元测试
 */
class org.flashNight.neur.PerformanceOptimizer.test.HysteresisQuantizerTest {

    public static function runAllTests():String {
        var out:String = "=== HysteresisQuantizerTest ===\n";
        out += test_twoStepConfirmation();
        out += test_clampByMinLevel();
        out += test_strictEquality();
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

    private static function test_strictEquality():String {
        var out:String = "[strictEquality]\n";
        var q:HysteresisQuantizer = new HysteresisQuantizer(0, 3);

        // 模拟类型异常：currentLevel 为字符串 "1"，candidate 为数字 1
        // 使用 !== 时，"1" !== 1 为 true → 检测到变化（正确行为）
        // 若使用 != 时，"1" != 1 为 false → 不检测变化（错误行为）
        // 注意：使用无类型注解的中间变量绕过 AS2 编译期类型检查，
        //       运行时仍为 String 类型，以验证 !== 的严格比较行为
        var untypedLevel = "1";
        var r1:Object = q.process(1.2, untypedLevel);
        // candidate = round(1.2) = 1, currentLevel = "1"
        // 严格比较: 1 !== "1" → true → 应该进入等待
        out += line(r1.levelChanged == false && q.isAwaitingConfirmation(),
            "严格比较: Number(1) !== String('1') 检测为变化");

        q.clearConfirmation();

        // 正常数字比较: candidate == currentLevel → 不应触发
        var r2:Object = q.process(1.2, 1);
        out += line(r2.levelChanged == false && !q.isAwaitingConfirmation(),
            "Number(1) === Number(1) 不触发变化");

        return out;
    }

    private static function line(ok:Boolean, msg:String):String {
        return "  " + (ok ? "✓ " : "✗ ") + msg + "\n";
    }
}
