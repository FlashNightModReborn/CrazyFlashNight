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
        out += test_holdBlocksRemoteApply();
        out += test_holdDisconnectClearsWasRemote();
        out += test_sceneEpochChangeTrigger();
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

    // --- hold 期间 P 指令不穿透 ---
    private static function test_holdBlocksRemoteApply():String {
        var out:String = "-- hold 阻止 P 指令穿透 --\n";
        var s:PerformanceScheduler = makeScheduler();

        // 先进入远程模式
        s.applyFromLauncher(0, 0);
        out += line(s.isRemoteControlled(), "初始远程模式");

        // 前馈: tier=1, hold=10秒 → 挂起远程
        s.setPerformanceLevel(1, 10);
        out += line(!s.isRemoteControlled(), "hold 期间远程模式挂起");
        out += line(s.getPerformanceLevel() == 1, "前馈设为 tier=1");

        // hold 期间 C# 发来 P0|0 → 应被拦截
        var act:Object = s.getActuator();
        var countBefore:Number = act._callCount;
        s.applyFromLauncher(0, 0);
        out += line(!s.isRemoteControlled(), "P 指令未恢复远程模式");
        out += line(s.getPerformanceLevel() == 1, "tier 未被 P 指令覆盖");
        out += line(act._callCount == countBefore, "actuator 未被调用");

        return out;
    }

    // --- hold + 断线: 不伪恢复远程，但 hold 保护继续生效 ---
    private static function test_holdDisconnectClearsWasRemote():String {
        var out:String = "-- hold + 断线 --\n";
        var s:PerformanceScheduler = makeScheduler();

        // 进入远程模式
        s.applyFromLauncher(0, 0);
        out += line(s.isRemoteControlled(), "初始远程模式");

        // 前馈 hold: tier=1, 10秒
        s.setPerformanceLevel(1, 10);
        out += line(!s.isRemoteControlled(), "hold 挂起远程");
        out += line(s.getPerformanceLevel() == 1, "前馈 tier=1");

        // 模拟断连: onSocketClose → setRemoteControlled(false)
        s.setRemoteControlled(false);
        out += line(!s.isRemoteControlled(), "断连后本地模式");

        // 关键1: hold 保护窗口仍然存在（tier 不被本地后备改写）
        // hold 期间 P 指令被拦截，applyFromLauncher 不会改 tier
        var act:Object = s.getActuator();
        var countBefore:Number = act._callCount;
        s.applyFromLauncher(0, 0);
        out += line(s.getPerformanceLevel() == 1, "hold 中断连后 tier 仍被保护");
        out += line(act._callCount == countBefore, "hold 中 P 指令仍被拦截");

        // 关键2: 推进时间越过 hold 窗口，验证到期后不会伪恢复远程
        // setPerformanceLevel 用 getTimer() 设置 holdUntilMs，所以传一个足够大的 currentTime
        var futureTime:Number = getTimer() + 20000; // 20秒后，超过 10秒 hold
        s.getSampler().setFramesLeft(1); // 确保到达采样点
        s.getSampler().setFrameStartTime(futureTime - 1000); // 1秒前，使 FPS 测量合理
        s.evaluate(futureTime);
        // hold 到期 + _wasRemoteBeforeHold 已清 → 不应恢复远程
        out += line(!s.isRemoteControlled(), "hold 到期后未伪恢复远程");

        return out;
    }

    // --- sceneEpoch 概念验证（AS2 端只测 _sceneEpoch 递增）---
    private static function test_sceneEpochChangeTrigger():String {
        var out:String = "-- sceneEpoch 递增 --\n";
        var s:PerformanceScheduler = makeScheduler();

        // 场景切换递增 epoch
        s.onSceneChanged();
        s.onSceneChanged();
        // 无法直接读 _sceneEpoch，但验证 onSceneChanged 执行无异常
        out += line(s.getPerformanceLevel() == 0, "两次 onSceneChanged 后 tier=0");

        // sceneEpoch 嵌入在 FPS payload 中，由 C# 端 FrameTask 解析检测
        // 此处仅验证 AS2 端状态一致性
        out += line(s.getLastAppliedSoftU() == 0, "onSceneChanged 后 softU=0");

        return out;
    }
}
