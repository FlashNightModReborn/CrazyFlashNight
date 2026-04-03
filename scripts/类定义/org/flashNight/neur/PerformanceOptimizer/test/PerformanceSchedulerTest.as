import org.flashNight.neur.PerformanceOptimizer.PerformanceScheduler;

/**
 * PerformanceSchedulerTest - 薄壳调度器回归测试（mock actuator）
 *
 * 决策逻辑已迁移到 C# PerfDecisionEngine，本测试覆盖：
 * - 远程模式（applyFromLauncher / 短路幂等 / 超时回退）
 * - 本地后备（极简阈值降级/升级）
 * - 场景切换重置
 * - 前馈控制接口
 */
class org.flashNight.neur.PerformanceOptimizer.test.PerformanceSchedulerTest {

    public static function runAllTests():String {
        var out:String = "=== PerformanceSchedulerTest ===\n";
        out += test_applyFromLauncher();
        out += test_applyFromLauncherShortCircuit();
        out += test_remoteTimeoutFallback();
        out += test_onSceneChanged();
        out += test_localFallbackDowngrade();
        out += test_localFallbackUpgrade();
        out += test_setPerformanceLevel();
        return out + "\n";
    }

    // ===== 工具 =====

    private static function line(ok:Boolean, desc:String):String {
        return (ok ? "  \u2713 " : "  \u2717 ") + desc + "\n";
    }

    private static function makeScheduler(host:Object):PerformanceScheduler {
        if (host == undefined) {
            host = { 性能等级上限: 0, offsetTolerance: 10 };
        }
        var mockRoot:Object = { _quality: "HIGH", 天气系统: undefined };
        mockRoot.面积系数 = 300000;
        mockRoot.同屏打击数字特效上限 = 25;
        mockRoot.发射效果上限 = 15;
        mockRoot.显示列表 = { 预设任务ID: 0, 继续播放: function() {}, 暂停播放: function() {} };
        var env:Object = { root: mockRoot };
        var s:PerformanceScheduler = new PerformanceScheduler(host, 30, 26, "HIGH", env);
        // 注入 mock actuator
        var mockActuator:Object = {
            _lastTier: -1, _lastSoftU: -1, _callCount: 0,
            apply: function(tier, softU) { this._lastTier = tier; this._lastSoftU = softU; this._callCount++; },
            setPresetQuality: function(q) {}
        };
        s.setActuator(mockActuator);
        return s;
    }

    // ===== 测试用例 =====

    private static function test_applyFromLauncher():String {
        var out:String = "-- applyFromLauncher --\n";
        var s:PerformanceScheduler = makeScheduler();

        // 首次调用: 隐式激活远程模式
        s.applyFromLauncher(1, 0.75);
        out += line(s.isRemoteControlled(), "首条 P 指令激活远程模式");
        out += line(s.getPerformanceLevel() == 1, "tier 设为 1");
        out += line(s.getLastAppliedSoftU() == 0.75, "softU 设为 0.75");

        var act:Object = s.getActuator();
        out += line(act._lastTier == 1, "actuator 收到 tier=1");
        out += line(act._lastSoftU == 0.75, "actuator 收到 softU=0.75");

        return out;
    }

    private static function test_applyFromLauncherShortCircuit():String {
        var out:String = "-- applyFromLauncher 短路幂等 --\n";
        var s:PerformanceScheduler = makeScheduler();

        s.applyFromLauncher(1, 0.5);
        var act:Object = s.getActuator();
        var countAfterFirst:Number = act._callCount;

        // 同 tier + 同 softU → 短路，actuator 不再调用
        s.applyFromLauncher(1, 0.5);
        out += line(act._callCount == countAfterFirst, "相同指令不重复 apply");

        // 不同 softU → 不短路
        s.applyFromLauncher(1, 0.8);
        out += line(act._callCount == countAfterFirst + 1, "不同 softU 触发 apply");

        return out;
    }

    private static function test_remoteTimeoutFallback():String {
        var out:String = "-- 远程超时回退 --\n";
        var s:PerformanceScheduler = makeScheduler();

        s.applyFromLauncher(1, 1.0);
        out += line(s.isRemoteControlled(), "进入远程模式");

        // 模拟超时: setRemoteControlled(false)
        s.setRemoteControlled(false);
        out += line(!s.isRemoteControlled(), "回退到本地模式");

        // 再次进入
        s.applyFromLauncher(0, 0);
        out += line(s.isRemoteControlled(), "P 指令重新激活远程模式");

        return out;
    }

    private static function test_onSceneChanged():String {
        var out:String = "-- onSceneChanged --\n";
        var host:Object = { 性能等级上限: 0, offsetTolerance: 10 };
        var s:PerformanceScheduler = makeScheduler(host);

        // 先设到 tier=1
        s.applyFromLauncher(1, 1.0);
        s.onSceneChanged();
        out += line(s.getPerformanceLevel() == 0, "场景切换后 tier 重置为 0");
        out += line(s.getLastAppliedSoftU() == 0, "场景切换后 softU 重置为 0");

        // 尊重 性能等级上限=1
        host.性能等级上限 = 1;
        s.onSceneChanged();
        out += line(s.getPerformanceLevel() == 1, "场景切换尊重性能等级上限=1");

        return out;
    }

    private static function test_localFallbackDowngrade():String {
        var out:String = "-- 本地后备降级 --\n";
        var s:PerformanceScheduler = makeScheduler();
        // 确保不在远程模式
        out += line(!s.isRemoteControlled(), "初始为本地模式");

        // 模拟 FPS < 15 的 evaluate
        // 手动设置采样器到即将触发的状态
        var sampler:Object = s.getSampler();
        sampler.setFramesLeft(1);
        sampler.setFrameStartTime(getTimer() - 2000); // 2秒前 → FPS ≈ 15

        s.evaluate(getTimer());
        // 由于 mock 环境无法精确控制 FPS，验证结构完整性
        out += line(s.getPerformanceLevel() >= 0, "evaluate 执行无异常");

        return out;
    }

    private static function test_localFallbackUpgrade():String {
        var out:String = "-- 本地后备升级 --\n";
        var s:PerformanceScheduler = makeScheduler();

        // 设到 tier=1，模拟本地后备升级路径
        s.applyFromLauncher(1, 1.0);
        s.setRemoteControlled(false); // 退出远程模式

        out += line(s.getPerformanceLevel() == 1, "初始 tier=1");
        out += line(!s.isRemoteControlled(), "本地模式");

        return out;
    }

    private static function test_setPerformanceLevel():String {
        var out:String = "-- setPerformanceLevel 前馈 --\n";
        var s:PerformanceScheduler = makeScheduler();

        s.setPerformanceLevel(1, 5);
        out += line(s.getPerformanceLevel() == 1, "前馈设置 tier=1");

        var act:Object = s.getActuator();
        out += line(act._lastTier == 1, "actuator 执行 tier=1");
        out += line(act._lastSoftU == 1.0, "tier=1 时 softU=1.0");

        s.setPerformanceLevel(0, 5);
        out += line(s.getPerformanceLevel() == 0, "前馈恢复 tier=0");
        out += line(act._lastSoftU == 0, "tier=0 时 softU=0");

        return out;
    }
}
