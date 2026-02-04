import org.flashNight.neur.PerformanceOptimizer.PerformanceActuator;

/**
 * PerformanceActuatorTest - 执行器单元测试（使用依赖注入mock）
 */
class org.flashNight.neur.PerformanceOptimizer.test.PerformanceActuatorTest {

    public static function runAllTests():String {
        var out:String = "=== PerformanceActuatorTest ===\n";
        out += test_allLevelsApplyExpectedValues();
        return out + "\n";
    }

    private static function test_allLevelsApplyExpectedValues():String {
        var out:String = "[apply]\n";

        // --- mock root and dependencies ---
        var displayList:Object = {
            预设任务ID: "TASK",
            continueCalled: false,
            continueArg: null,
            pauseCalled: false,
            pauseArg: null,
            继续播放: function(id):Void { this.continueCalled = true; this.continueArg = id; },
            暂停播放: function(id):Void { this.pauseCalled = true; this.pauseArg = id; }
        };

        var root:Object = {
            _quality: "HIGH",
            面积系数: null,
            同屏打击数字特效上限: null,
            发射效果上限: null,
            天气系统: { 光照等级更新阈值: null },
            显示列表: displayList,
            UI系统: { 经济面板动效: null }
        };

        var effectSystem:Object = {};
        var deathRenderer:Object = { isEnabled: null, enableCulling: null };
        var shellSystem:Object = { limit: null, setMaxShellCountLimit: function(v):Void { this.limit = v; } };
        var trailInstance:Object = { q: null, setQuality: function(v):Void { this.q = v; } };
        var trailRenderer:Object = { getInstance: function():Object { return trailInstance; } };
        var clipFrameRenderer:Object = { level: null, setPerformanceLevel: function(v):Void { this.level = v; } };
        var bladeRenderer:Object = { level: null, setPerformanceLevel: function(v):Void { this.level = v; } };

        var env:Object = {
            root: root,
            EffectSystem: effectSystem,
            DeathEffectRenderer: deathRenderer,
            ShellSystem: shellSystem,
            TrailRenderer: trailRenderer,
            ClipFrameRenderer: clipFrameRenderer,
            BladeMotionTrailsRenderer: bladeRenderer
        };

        var host:Object = { offsetTolerance: null };
        var a:PerformanceActuator = new PerformanceActuator(host, "HIGH", env);

        // Level 0
        resetCalls(displayList);
        a.apply(0);
        out += line(effectSystem.maxEffectCount == 20, "L0 maxEffectCount=20");
        out += line(effectSystem.maxScreenEffectCount == 20, "L0 maxScreenEffectCount=20");
        out += line(effectSystem.isDeathEffect == true, "L0 isDeathEffect=true");
        out += line(root.面积系数 == 300000, "L0 面积系数=300000");
        out += line(root.同屏打击数字特效上限 == 25, "L0 同屏打击数字特效上限=25");
        out += line(deathRenderer.isEnabled == true && deathRenderer.enableCulling == false, "L0 DeathEffectRenderer启用且不剔除");
        out += line(root._quality == "HIGH", "L0 quality恢复预设(HIGH)");
        out += line(root.天气系统.光照等级更新阈值 == 0.1, "L0 光照阈值=0.1");
        out += line(shellSystem.limit == 25, "L0 shellLimit=25");
        out += line(root.发射效果上限 == 15, "L0 发射效果上限=15");
        out += line(displayList.continueCalled && displayList.continueArg == "TASK", "L0 显示列表继续播放");
        out += line(root.UI系统.经济面板动效 == true, "L0 UI动效=true");
        out += line(host.offsetTolerance == 10, "L0 offsetTolerance=10");
        out += line(trailInstance.q == 0 && clipFrameRenderer.level == 0 && bladeRenderer.level == 0, "L0 渲染器档位=0");

        // Level 1
        resetCalls(displayList);
        a.apply(1);
        out += line(effectSystem.maxEffectCount == 15, "L1 maxEffectCount=15");
        out += line(root.面积系数 == 450000, "L1 面积系数=450000");
        out += line(root._quality == "MEDIUM", "L1 quality=MEDIUM(预设非LOW)");
        out += line(root.天气系统.光照等级更新阈值 == 0.2, "L1 光照阈值=0.2");
        out += line(shellSystem.limit == 18, "L1 shellLimit=18");
        out += line(displayList.continueCalled && !displayList.pauseCalled, "L1 显示列表继续播放");
        out += line(host.offsetTolerance == 30, "L1 offsetTolerance=30");
        out += line(trailInstance.q == 1 && clipFrameRenderer.level == 1 && bladeRenderer.level == 1, "L1 渲染器档位=1");

        // Level 2
        resetCalls(displayList);
        a.apply(2);
        out += line(effectSystem.maxEffectCount == 10, "L2 maxEffectCount=10");
        out += line(effectSystem.isDeathEffect == false, "L2 isDeathEffect=false");
        out += line(root.面积系数 == 600000, "L2 面积系数=600000");
        out += line(root._quality == "LOW", "L2 quality=LOW");
        out += line(root.天气系统.光照等级更新阈值 == 0.5, "L2 光照阈值=0.5");
        out += line(shellSystem.limit == 12, "L2 shellLimit=12");
        out += line(displayList.pauseCalled && displayList.pauseArg == "TASK", "L2 显示列表暂停播放");
        out += line(root.UI系统.经济面板动效 == false, "L2 UI动效=false");
        out += line(host.offsetTolerance == 50, "L2 offsetTolerance=50");
        out += line(trailInstance.q == 2 && clipFrameRenderer.level == 2 && bladeRenderer.level == 2, "L2 渲染器档位=2");

        // Level 3 (default)
        resetCalls(displayList);
        a.apply(3);
        out += line(effectSystem.maxEffectCount == 0, "L3 maxEffectCount=0");
        out += line(effectSystem.maxScreenEffectCount == 5, "L3 maxScreenEffectCount=5");
        out += line(root.面积系数 == 3000000, "L3 面积系数=3000000");
        out += line(root.天气系统.光照等级更新阈值 == 1, "L3 光照阈值=1");
        out += line(shellSystem.limit == 10, "L3 shellLimit=10");
        out += line(root.发射效果上限 == 0, "L3 发射效果上限=0");
        out += line(displayList.pauseCalled, "L3 显示列表暂停播放");
        out += line(host.offsetTolerance == 80, "L3 offsetTolerance=80");
        out += line(trailInstance.q == 3 && clipFrameRenderer.level == 3 && bladeRenderer.level == 3, "L3 渲染器档位=3");

        return out;
    }

    private static function resetCalls(displayList:Object):Void {
        displayList.continueCalled = false;
        displayList.continueArg = null;
        displayList.pauseCalled = false;
        displayList.pauseArg = null;
    }

    private static function line(ok:Boolean, msg:String):String {
        return "  " + (ok ? "✓ " : "✗ ") + msg + "\n";
    }
}
