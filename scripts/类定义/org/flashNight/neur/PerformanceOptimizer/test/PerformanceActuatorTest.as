import org.flashNight.neur.PerformanceOptimizer.PerformanceActuator;

/**
 * PerformanceActuatorTest - 执行器单元测试（使用依赖注入mock）
 */
class org.flashNight.neur.PerformanceOptimizer.test.PerformanceActuatorTest {

    public static function runAllTests():String {
        var out:String = "=== PerformanceActuatorTest ===\n";
        out += test_tier0_softU0();
        out += test_tier0_softU03();
        out += test_tier1_softU05();
        out += test_tier1_softU1();
        out += test_rendererLevelMapping();
        out += test_booleanThresholds();
        return out + "\n";
    }

    // --- shared mock factory ---

    private static function makeMocks():Object {
        var displayList:Object = {
            预设任务ID: "TASK",
            continueCalled: false,
            pauseCalled: false,
            继续播放: function(id):Void { this.continueCalled = true; },
            暂停播放: function(id):Void { this.pauseCalled = true; }
        };

        var root:Object = {
            _quality: "HIGH",
            面积系数: null,
            同屏打击数字特效上限: null,
            发射效果上限: null,
            天气系统: { lightUpdateThreshold: null },
            显示列表: displayList
        };

        var effectSystem:Object = {};
        var deathRenderer:Object = { isEnabled: null, enableCulling: null };
        var shellSystem:Object = { limit: null, setMaxShellCountLimit: function(v):Void { this.limit = v; } };
        var trailInstance:Object = { q: null, setQuality: function(v):Void { this.q = v; } };
        var trailRenderer:Object = { getInstance: function():Object { return trailInstance; } };
        var clipFrameRenderer:Object = { level: null, setPerformanceLevel: function(v):Void { this.level = v; } };
        var bladeRenderer:Object = { level: null, setPerformanceLevel: function(v):Void { this.level = v; } };
        var weatherParticleRenderer:Object = { level: null, setPerformanceLevel: function(v):Void { this.level = v; } };
        var skyboxRenderer:Object = { level: null, setPerformanceLevel: function(v):Void { this.level = v; } };
        var gwOverlayRenderer:Object = { level: null, setPerformanceLevel: function(v):Void { this.level = v; } };

        var env:Object = {
            root: root,
            EffectSystem: effectSystem,
            DeathEffectRenderer: deathRenderer,
            ShellSystem: shellSystem,
            TrailRenderer: trailRenderer,
            ClipFrameRenderer: clipFrameRenderer,
            BladeMotionTrailsRenderer: bladeRenderer,
            WeatherParticleRenderer: weatherParticleRenderer,
            SkyboxRenderer: skyboxRenderer,
            GameWorldOverlayRenderer: gwOverlayRenderer
        };

        var host:Object = { offsetTolerance: null };
        var a:PerformanceActuator = new PerformanceActuator(host, "HIGH", env);
        return { a: a, root: root, es: effectSystem, dr: deathRenderer, ss: shellSystem,
                 host: host, dl: displayList, trail: trailInstance,
                 clip: clipFrameRenderer, blade: bladeRenderer,
                 wp: weatherParticleRenderer, sky: skyboxRenderer, gw: gwOverlayRenderer };
    }

    // --- tier 0, softU=0: 全质量 ---
    private static function test_tier0_softU0():String {
        var out:String = "[tier0_softU0]\n";
        var m:Object = makeMocks();
        m.a.apply(0, 0.0);
        out += line(m.root._quality == "HIGH", "quality=HIGH（预设）");
        out += line(m.dl.continueCalled, "显示列表继续播放");
        out += line(m.es.maxEffectCount == 20, "maxEffectCount=20");
        out += line(m.es.maxScreenEffectCount == 20, "maxScreenEffectCount=20");
        out += line(m.es.isDeathEffect == true, "isDeathEffect=true");
        out += line(m.root.面积系数 == 300000, "面积系数=300000");
        out += line(m.root.同屏打击数字特效上限 == 25, "同屏打击数字特效上限=25");
        out += line(m.dr.isEnabled == true, "DeathEffectRenderer启用");
        out += line(m.dr.enableCulling == false, "enableCulling=false");
        out += line(m.ss.limit == 25, "shellLimit=25");
        out += line(m.root.发射效果上限 == 15, "发射效果上限=15");
        out += line(m.host.offsetTolerance == 10, "offsetTolerance=10");
        out += line(m.trail.q == 0, "渲染器档位=0");
        return out;
    }

    // --- tier 0, softU=0.3: 微降 ---
    private static function test_tier0_softU03():String {
        var out:String = "[tier0_softU03]\n";
        var m:Object = makeMocks();
        m.a.apply(0, 0.3);
        out += line(m.root._quality == "HIGH", "quality=HIGH（tier0始终预设）");
        out += line(m.dl.continueCalled, "显示列表继续播放");
        out += line(m.es.maxEffectCount == 14, "maxEffectCount≈14");
        out += line(m.es.isDeathEffect == true, "isDeathEffect=true（softU<0.5）");
        out += line(m.dr.isEnabled == true, "DeathEffectRenderer启用（softU<0.5）");
        out += line(m.dr.enableCulling == true, "enableCulling=true（softU>=0.25）");
        out += line(m.trail.q == 1, "渲染器档位=1（softU=0.3→rl=1）");
        return out;
    }

    // --- tier 1, softU=0.5: LOW + 中等降载 ---
    private static function test_tier1_softU05():String {
        var out:String = "[tier1_softU05]\n";
        var m:Object = makeMocks();
        m.a.apply(1, 0.5);
        out += line(m.root._quality == "LOW", "quality=LOW");
        out += line(m.dl.pauseCalled, "显示列表暂停播放");
        out += line(m.es.maxEffectCount == 10, "maxEffectCount=10");
        out += line(m.es.isDeathEffect == false, "isDeathEffect=false（softU>=0.5）");
        out += line(m.dr.isEnabled == false, "DeathEffectRenderer禁用（softU>=0.5）");
        out += line(m.trail.q == 2, "渲染器档位=2（softU=0.5→rl=2）");
        return out;
    }

    // --- tier 1, softU=1.0: 满降载 ---
    private static function test_tier1_softU1():String {
        var out:String = "[tier1_softU1]\n";
        var m:Object = makeMocks();
        m.a.apply(1, 1.0);
        out += line(m.root._quality == "LOW", "quality=LOW");
        out += line(m.es.maxEffectCount == 0, "maxEffectCount=0");
        out += line(m.es.maxScreenEffectCount == 5, "maxScreenEffectCount=5");
        out += line(m.root.面积系数 == 3000000, "面积系数=3000000");
        out += line(m.root.同屏打击数字特效上限 == 10, "同屏打击数字特效上限=10");
        out += line(m.ss.limit == 10, "shellLimit=10");
        out += line(m.root.发射效果上限 == 0, "发射效果上限=0");
        out += line(m.host.offsetTolerance == 80, "offsetTolerance=80");
        out += line(m.trail.q == 3, "渲染器档位=3");
        return out;
    }

    // --- 渲染器档位映射: softU → rendererLevel ---
    private static function test_rendererLevelMapping():String {
        var out:String = "[rendererLevel]\n";
        var m:Object = makeMocks();
        // softU=0 → rl=0
        m.a.apply(0, 0.0);
        out += line(m.trail.q == 0, "softU=0.0→rl=0");
        // softU=0.25 → rl=1
        m.a.apply(0, 0.25);
        out += line(m.trail.q == 1, "softU=0.25→rl=1");
        // softU=0.5 → rl=2
        m.a.apply(1, 0.5);
        out += line(m.trail.q == 2, "softU=0.5→rl=2");
        // softU=0.75 → rl=3
        m.a.apply(1, 0.75);
        out += line(m.trail.q == 3, "softU=0.75→rl=3");
        // softU=1.0 → rl=3 (clamped)
        m.a.apply(1, 1.0);
        out += line(m.trail.q == 3, "softU=1.0→rl=3（clamp）");
        return out;
    }

    // --- 布尔阈值边界 ---
    private static function test_booleanThresholds():String {
        var out:String = "[boolThreshold]\n";
        var m:Object = makeMocks();
        m.a.apply(0, 0.49);
        out += line(m.es.isDeathEffect == true, "softU=0.49: isDeathEffect=true");
        out += line(m.dr.isEnabled == true, "softU=0.49: deathRenderer启用");
        m.a.apply(1, 0.51);
        out += line(m.es.isDeathEffect == false, "softU=0.51: isDeathEffect=false");
        out += line(m.dr.isEnabled == false, "softU=0.51: deathRenderer禁用");
        // enableCulling threshold at 0.25
        m.a.apply(0, 0.24);
        out += line(m.dr.enableCulling == false, "softU=0.24: enableCulling=false");
        m.a.apply(0, 0.26);
        out += line(m.dr.enableCulling == true, "softU=0.26: enableCulling=true");
        return out;
    }

    private static function line(ok:Boolean, msg:String):String {
        return "  " + (ok ? "✓ " : "✗ ") + msg + "\n";
    }
}
