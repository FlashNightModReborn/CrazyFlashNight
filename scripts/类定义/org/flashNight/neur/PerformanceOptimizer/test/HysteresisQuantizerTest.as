import org.flashNight.neur.PerformanceOptimizer.HysteresisQuantizer;

/**
 * HysteresisQuantizerTest - 非对称迟滞量化器单元测试
 *
 * 覆盖：
 * - 降级（level↑）2次确认快速响应
 * - 升级（level↓）3次确认谨慎恢复
 * - 方向反转重置计数
 * - clamp 到 [minLevel, maxLevel]
 * - 严格等号比较
 * - clearConfirmation 重置
 */
class org.flashNight.neur.PerformanceOptimizer.test.HysteresisQuantizerTest {

    public static function runAllTests():String {
        var out:String = "=== HysteresisQuantizerTest ===\n";
        out += test_downgrade_twoStep();
        out += test_upgrade_threeStep();
        out += test_directionReversal();
        out += test_clampByMinLevel();
        out += test_strictEquality();
        out += test_clearConfirmation();
        out += test_customThresholds();
        return out + "\n";
    }

    /**
     * 降级（level↑，画质↓）：2次连续确认即执行
     */
    private static function test_downgrade_twoStep():String {
        var out:String = "[downgrade_2step]\n";
        var q:HysteresisQuantizer = new HysteresisQuantizer(0, 3);

        // 当前 level=0，PID 输出 1.2 → candidate=1 → 降级方向
        var r1:Number = q.process(1.2, 0);
        out += line(r1 < 0 && q.isAwaitingConfirmation(),
            "降级第1次：不切换，进入等待");
        out += line(q.getConfirmCount() == 1 && q.getPendingDirection() == 1,
            "确认计数=1，方向=降级(+1)");

        var r2:Number = q.process(1.2, 0);
        out += line(r2 == 1,
            "降级第2次：达到阈值，切换到1");
        out += line(q.getConfirmCount() == 0,
            "切换后确认计数归零");

        // 候选 === 当前 → 确认状态清空
        var r3:Number = q.process(1.2, 1);
        out += line(r3 < 0 && !q.isAwaitingConfirmation(),
            "候选等于当前：确认状态清空");

        return out;
    }

    /**
     * 升级（level↓，画质↑）：3次连续确认才执行
     */
    private static function test_upgrade_threeStep():String {
        var out:String = "[upgrade_3step]\n";
        var q:HysteresisQuantizer = new HysteresisQuantizer(0, 3);

        // 当前 level=2，PID 输出 0.8 → candidate=1 → 升级方向
        var r1:Number = q.process(0.8, 2);
        out += line(r1 < 0 && q.getConfirmCount() == 1,
            "升级第1次：不切换，计数=1");

        var r2:Number = q.process(0.8, 2);
        out += line(r2 < 0 && q.getConfirmCount() == 2,
            "升级第2次：不切换（需3次），计数=2");
        out += line(q.getPendingDirection() == -1,
            "方向=升级(-1)");

        var r3:Number = q.process(0.8, 2);
        out += line(r3 == 1,
            "升级第3次：达到阈值，切换到1");

        return out;
    }

    /**
     * 方向反转：计数从 1 重新开始（不是 0）
     */
    private static function test_directionReversal():String {
        var out:String = "[directionReversal]\n";
        var q:HysteresisQuantizer = new HysteresisQuantizer(0, 3);

        // 升级方向，积累到第2次
        q.process(0.8, 2); // 升级，count=1
        q.process(0.8, 2); // 升级，count=2
        out += line(q.getConfirmCount() == 2 && q.getPendingDirection() == -1,
            "升级方向积累2次");

        // 方向反转到降级
        var r:Number = q.process(2.6, 2);
        out += line(r < 0 && q.getConfirmCount() == 1 && q.getPendingDirection() == 1,
            "方向反转：计数重置为1，方向=降级(+1)");

        // 继续降级方向，达到阈值
        var r2:Number = q.process(2.6, 2);
        out += line(r2 == 3,
            "降级第2次（含反转的1次）：达到阈值，切换到3");

        return out;
    }

    /**
     * clamp 到 [minLevel, maxLevel]，升级方向需要3次确认
     */
    private static function test_clampByMinLevel():String {
        var out:String = "[clamp]\n";
        var q:HysteresisQuantizer = new HysteresisQuantizer(2, 3);

        // PID 输出 0 → round=0 → clamp 到 minLevel=2, 当前 level=3 → 升级方向
        var r1:Number = q.process(0, 3);
        out += line(r1 < 0 && q.isAwaitingConfirmation(),
            "候选被clamp到minLevel=2（第1次等待）");

        var r2:Number = q.process(0, 3);
        out += line(r2 < 0 && q.getConfirmCount() == 2,
            "升级第2次：需3次确认，继续等待");

        var r3:Number = q.process(0, 3);
        out += line(r3 == 2,
            "升级第3次：达到阈值，切换到2");

        return out;
    }

    /**
     * 严格等号比较 !== 防止类型强制转换
     */
    private static function test_strictEquality():String {
        var out:String = "[strictEquality]\n";
        var q:HysteresisQuantizer = new HysteresisQuantizer(0, 3);

        // 模拟类型异常：currentLevel 为字符串 "1"，candidate 为数字 1
        // 使用 !== 时，"1" !== 1 为 true → 检测到变化（正确行为）
        // 若使用 != 时，"1" != 1 为 false → 不检测变化（错误行为）
        var untypedLevel = "1";
        var r1:Number = q.process(1.2, untypedLevel);
        out += line(r1 < 0 && q.isAwaitingConfirmation(),
            "严格比较: Number(1) !== String('1') 检测为变化");

        q.clearConfirmation();

        // 正常数字比较: candidate == currentLevel → 不应触发
        var r2:Number = q.process(1.2, 1);
        out += line(r2 < 0 && !q.isAwaitingConfirmation(),
            "Number(1) === Number(1) 不触发变化");

        return out;
    }

    /**
     * clearConfirmation 和 setConfirmState 测试
     */
    private static function test_clearConfirmation():String {
        var out:String = "[clearConfirmation]\n";
        var q:HysteresisQuantizer = new HysteresisQuantizer(0, 3);

        q.process(1.2, 0); // 降级 count=1
        out += line(q.isAwaitingConfirmation(), "process后有待确认");

        q.clearConfirmation();
        out += line(!q.isAwaitingConfirmation() && q.getConfirmCount() == 0,
            "clearConfirmation 清空所有状态");

        // setConfirmState 精确控制
        q.setConfirmState(2, -1);
        out += line(q.getConfirmCount() == 2 && q.getPendingDirection() == -1,
            "setConfirmState(2, -1) 精确设置");

        // 向后兼容 setAwaitingConfirmation
        q.setAwaitingConfirmation(true);
        out += line(q.getConfirmCount() == 1 && q.getPendingDirection() == 1,
            "setAwaitingConfirmation(true) 兼容模式：count=1, direction=降级");

        q.setAwaitingConfirmation(false);
        out += line(q.getConfirmCount() == 0 && q.getPendingDirection() == 0,
            "setAwaitingConfirmation(false) 清空");

        return out;
    }

    /**
     * 自定义阈值测试
     */
    private static function test_customThresholds():String {
        var out:String = "[customThresholds]\n";

        // 降级1次确认，升级4次确认
        var q:HysteresisQuantizer = new HysteresisQuantizer(0, 3, 1, 4);
        out += line(q.getDowngradeThreshold() == 1 && q.getUpgradeThreshold() == 4,
            "自定义阈值：降级=1, 升级=4");

        // 降级：1次即切换
        var r1:Number = q.process(1.2, 0);
        out += line(r1 == 1,
            "降级阈值=1：首次即切换");

        // 升级：需要4次
        q.clearConfirmation();
        q.process(0.4, 2); // count=1
        q.process(0.4, 2); // count=2
        q.process(0.4, 2); // count=3
        var r2:Number = q.process(0.4, 2); // count=4
        out += line(r2 == 0,
            "升级阈值=4：第4次切换");

        // 默认阈值（不传参数）
        var q2:HysteresisQuantizer = new HysteresisQuantizer(0, 3);
        out += line(q2.getDowngradeThreshold() == 2 && q2.getUpgradeThreshold() == 3,
            "默认阈值：降级=2, 升级=3");

        return out;
    }

    private static function line(ok:Boolean, msg:String):String {
        return "  " + (ok ? "✓ " : "✗ ") + msg + "\n";
    }
}
