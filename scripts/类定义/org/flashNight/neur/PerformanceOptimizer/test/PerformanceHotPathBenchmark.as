import org.flashNight.neur.Controller.PIDController;
import org.flashNight.neur.Controller.SimpleKalmanFilter1D;
import org.flashNight.neur.PerformanceOptimizer.IntervalSampler;
import org.flashNight.neur.PerformanceOptimizer.AdaptiveKalmanStage;
import org.flashNight.neur.PerformanceOptimizer.HysteresisQuantizer;
import org.flashNight.neur.PerformanceOptimizer.PerformanceActuator;
import org.flashNight.neur.PerformanceOptimizer.FPSVisualization;
import org.flashNight.neur.PerformanceOptimizer.PerformanceScheduler;

/**
 * PerformanceHotPathBenchmark - 热路径微基准测试
 *
 * 用途：
 * - 同机器回归对比，量化优化前后的性能变化
 * - 不要将数据跨机器横向比较（AVM1 执行速度受硬件/播放器版本影响）
 * - 每个基准报告 checksum 防止编译器/AVM 消除空循环
 *
 * 覆盖的热路径：
 *   L0 极热（每帧）: tick、evaluate(fast-path)
 *   L1 温热（每采样窗口）: measure+resetInterval、filter、process、evaluate(sample-path)
 *   L2 冷（低频）: apply、updateData+drawCurve
 */
class org.flashNight.neur.PerformanceOptimizer.test.PerformanceHotPathBenchmark {

    /** 轻量级操作迭代次数（tick 等每帧调用的操作） */
    private static var ITER_LIGHT:Number = 100000;
    /** 中等操作迭代次数（每采样窗口调用的操作） */
    private static var ITER_MEDIUM:Number = 20000;
    /** 重量级操作迭代次数（低频调用 + 绘图操作） */
    private static var ITER_HEAVY:Number = 5000;

    public static function runAllTests():String {
        var out:String = "=== PerformanceHotPathBenchmark ===\n";
        out += "  note: same-machine comparison only\n";
        out += bench_intervalSampler_tick();
        out += bench_intervalSampler_measureReset();
        out += bench_kalman_filter();
        out += bench_quantizer_process();
        out += bench_actuator_apply();
        out += bench_visualization_updateDraw();
        out += bench_scheduler_evaluateFastPath();
        out += bench_scheduler_evaluateSamplePath();
        return out + "\n";
    }

    // ------------------------------------------------------------------
    // IntervalSampler
    // ------------------------------------------------------------------

    /**
     * 基准：IntervalSampler.tick()
     * 最热路径，每帧调用。测试纯倒计时递减 + 比较的开销。
     */
    private static function bench_intervalSampler_tick():String {
        var sampler:IntervalSampler = new IntervalSampler(30);
        sampler.setFramesLeft(ITER_LIGHT + 1);

        var t0:Number = getTimer();
        var checksum:Number = 0;
        for (var i:Number = 0; i < ITER_LIGHT; i++) {
            if (sampler.tick()) checksum++;
        }
        var elapsed:Number = getTimer() - t0;
        return line("IntervalSampler.tick", elapsed, ITER_LIGHT, checksum);
    }

    /**
     * 基准：IntervalSampler.measure() + resetInterval()
     * 每采样窗口调用一次。测试区间平均FPS计算 + 窗口重置。
     */
    private static function bench_intervalSampler_measureReset():String {
        var sampler:IntervalSampler = new IntervalSampler(30);
        sampler.setFrameStartTime(0);

        var now:Number = 0;
        var checksum:Number = 0;
        var t0:Number = getTimer();

        for (var i:Number = 0; i < ITER_MEDIUM; i++) {
            var level:Number = i & 3;
            now += 16 + level;
            checksum += sampler.measure(now, level);
            sampler.resetInterval(now, level);
        }

        var elapsed:Number = getTimer() - t0;
        return line("IntervalSampler.measure+resetInterval", elapsed, ITER_MEDIUM, checksum);
    }

    // ------------------------------------------------------------------
    // AdaptiveKalmanStage
    // ------------------------------------------------------------------

    /**
     * 基准：AdaptiveKalmanStage.filter()
     * 每采样窗口调用一次。包含自适应Q缩放 + Kalman predict + update 全链路。
     */
    private static function bench_kalman_filter():String {
        var kf:SimpleKalmanFilter1D = new SimpleKalmanFilter1D(30, 0.5, 1);
        var stage:AdaptiveKalmanStage = new AdaptiveKalmanStage(kf, 0.1, 0.01, 2.0);
        stage.reset(30, 1);

        var checksum:Number = 0;
        var t0:Number = getTimer();

        for (var i:Number = 0; i < ITER_MEDIUM; i++) {
            var measured:Number = 18 + (i % 11);   // 18..28 模拟帧率波动
            var dt:Number = 0.2 + ((i % 4) * 0.4); // 0.2,0.6,1.0,1.4 模拟变采样间隔
            checksum += stage.filter(measured, dt);
        }

        var elapsed:Number = getTimer() - t0;
        return line("AdaptiveKalmanStage.filter", elapsed, ITER_MEDIUM, checksum);
    }

    // ------------------------------------------------------------------
    // HysteresisQuantizer
    // ------------------------------------------------------------------

    /**
     * 基准：HysteresisQuantizer.process()
     * 每采样窗口调用一次。交替方向输入，覆盖累积和反转两条路径。
     */
    private static function bench_quantizer_process():String {
        var q:HysteresisQuantizer = new HysteresisQuantizer(0, 3, 2, 3);
        var currentLevel:Number = 2;
        var checksum:Number = 0;
        var t0:Number = getTimer();

        // 交替方向输入，覆盖累积路径和方向反转路径
        for (var i:Number = 0; i < ITER_LIGHT; i++) {
            var pidOutput:Number = ((i & 1) == 0) ? 2.8 : 0.2;
            var r:Object = q.process(pidOutput, currentLevel);
            if (r.levelChanged) {
                currentLevel = r.newLevel;
            }
            checksum += currentLevel;
        }

        var elapsed:Number = getTimer() - t0;
        return line("HysteresisQuantizer.process", elapsed, ITER_LIGHT, checksum);
    }

    // ------------------------------------------------------------------
    // PerformanceActuator
    // ------------------------------------------------------------------

    /**
     * 基准：PerformanceActuator.apply()
     * 低频调用（迟滞确认后才执行）。测试多维降载参数写入开销。
     */
    private static function bench_actuator_apply():String {
        var deps:Object = makeActuatorDeps();
        var actuator:PerformanceActuator = deps.actuator;
        var host:Object = deps.host;

        var checksum:Number = 0;
        var t0:Number = getTimer();

        for (var i:Number = 0; i < ITER_MEDIUM; i++) {
            actuator.apply(i & 3);
            checksum += host.offsetTolerance;
        }

        var elapsed:Number = getTimer() - t0;
        return line("PerformanceActuator.apply", elapsed, ITER_MEDIUM, checksum);
    }

    // ------------------------------------------------------------------
    // FPSVisualization
    // ------------------------------------------------------------------

    /**
     * 基准：FPSVisualization.updateData() + drawCurve()
     * 每采样窗口调用一次。主要开销在 Flash 绘图 API（curveTo 等）。
     */
    private static function bench_visualization_updateDraw():String {
        var light:Array = buildLight();
        var weather:Object = { 当前时间: 8.5, 昼夜光照: light };

        var viz:FPSVisualization = new FPSVisualization(24, 30, weather);
        var canvas = makeCanvasNoOp();

        var checksum:Number = 0;
        var t0:Number = getTimer();

        for (var i:Number = 0; i < ITER_HEAVY; i++) {
            viz.updateData(20 + (i % 10));
            viz.drawCurve(canvas, i & 3);
            checksum += viz.getFPSDiff();
        }

        var elapsed:Number = getTimer() - t0;
        return line("FPSVisualization.updateData+drawCurve", elapsed, ITER_HEAVY, checksum);
    }

    // ------------------------------------------------------------------
    // PerformanceScheduler
    // ------------------------------------------------------------------

    /**
     * 基准：PerformanceScheduler.evaluate() 快速退出路径
     * 模拟 97% 的实际调用场景：tick 倒计时未到，立即返回。
     * 用于量化 evaluate→tick 方法调用链的纯开销。
     */
    private static function bench_scheduler_evaluateFastPath():String {
        var scheduler:PerformanceScheduler = makeSchedulerForBench(30);
        var sampler:IntervalSampler = scheduler.getSampler();
        sampler.setFramesLeft(ITER_LIGHT + 1); // 保证几乎全部走快速退出

        var checksum:Number = 0;
        var t0:Number = getTimer();

        for (var i:Number = 0; i < ITER_LIGHT; i++) {
            scheduler.evaluate(i);
            checksum += sampler.getFramesLeft();
        }

        var elapsed:Number = getTimer() - t0;
        return line("PerformanceScheduler.evaluate(fast-path)", elapsed, ITER_LIGHT, checksum);
    }

    /**
     * 基准：PerformanceScheduler.evaluate() 采样点处理路径
     * 每次迭代强制触发采样，走完 measure→kalman→PID→quantizer→reset 全链路。
     */
    private static function bench_scheduler_evaluateSamplePath():String {
        var scheduler:PerformanceScheduler = makeSchedulerForBench(30);
        var sampler:IntervalSampler = scheduler.getSampler();
        sampler.setFrameStartTime(0);

        var now:Number = 0;
        var checksum:Number = 0;
        var t0:Number = getTimer();

        for (var i:Number = 0; i < ITER_HEAVY; i++) {
            sampler.setFramesLeft(1);    // 强制下一次 tick 触发采样
            now += 50;                   // 模拟 ~20 FPS 时间线
            scheduler.evaluate(now);
            checksum += scheduler.getPerformanceLevel();
        }

        var elapsed:Number = getTimer() - t0;
        return line("PerformanceScheduler.evaluate(sample-path)", elapsed, ITER_HEAVY, checksum);
    }

    // ------------------------------------------------------------------
    // 辅助构造方法
    // ------------------------------------------------------------------

    /**
     * 构造用于 scheduler 基准测试的完整环境
     * - mock actuator（隔离执行器开销）
     * - viz/logger 置空（隔离可视化/日志开销）
     */
    private static function makeSchedulerForBench(frameRate:Number):PerformanceScheduler {
        var canvas:Object = makeCanvasNoOp();

        var root:Object = {
            _quality: "HIGH",
            发布消息: function(msg:String):Void {},
            天气系统: { 当前时间: 0, 昼夜光照: buildLight() },
            玩家信息界面: { 性能帧率显示器: { 帧率数字: { text: null }, 画布: canvas } },
            显示列表: { 预设任务ID: "TASK", 继续播放: function() {}, 暂停播放: function() {} },
            UI系统: { 经济面板动效: true }
        };

        var host:Object = {
            帧率: frameRate,
            性能等级上限: 0,
            offsetTolerance: 0
        };

        var pid:PIDController = new PIDController(0.2, 0.5, -30, 3, 0.2);
        var scheduler:PerformanceScheduler = new PerformanceScheduler(host, frameRate, 26, "HIGH", {root: root}, pid);
        scheduler.setActuator(makeActuatorMock());
        scheduler.setVisualization(null); // 隔离 scheduler 核心，排除可视化开销
        scheduler.setLogger(null);
        return scheduler;
    }

    /**
     * 构造用于 PerformanceActuator.apply() 基准测试的完整依赖环境
     * - 所有子系统为 mock 对象
     * - 保留与生产代码一致的属性结构
     */
    private static function makeActuatorDeps():Object {
        var root:Object = {
            _quality: "HIGH",
            面积系数: 0,
            同屏打击数字特效上限: 0,
            发射效果上限: 0,
            天气系统: { 光照等级更新阈值: 0 },
            显示列表: { 预设任务ID: "TASK", 继续播放: function() {}, 暂停播放: function() {} },
            UI系统: { 经济面板动效: true }
        };

        var effectSystem:Object = {};
        var deathRenderer:Object = { isEnabled: false, enableCulling: false };
        var shellSystem:Object = { setMaxShellCountLimit: function(v):Void {} };
        var trailRenderer:Object = { getInstance: function():Object { return { setQuality: function(v):Void {} }; } };
        var clipFrameRenderer:Object = { setPerformanceLevel: function(v):Void {} };
        var bladeRenderer:Object = { setPerformanceLevel: function(v):Void {} };

        var env:Object = {
            root: root,
            EffectSystem: effectSystem,
            DeathEffectRenderer: deathRenderer,
            ShellSystem: shellSystem,
            TrailRenderer: trailRenderer,
            ClipFrameRenderer: clipFrameRenderer,
            BladeMotionTrailsRenderer: bladeRenderer
        };

        var host:Object = { offsetTolerance: 0 };
        var actuator:PerformanceActuator = new PerformanceActuator(host, "HIGH", env);
        return { actuator: actuator, host: host };
    }

    /** mock 执行器（用于隔离 scheduler 基准中的 actuator 开销） */
    private static function makeActuatorMock():Object {
        return {
            lastLevel: -1,
            presetQuality: "HIGH",
            apply: function(level:Number):Void { this.lastLevel = level; },
            setPresetQuality: function(q:String):Void { this.presetQuality = q; },
            getPresetQuality: function():String { return this.presetQuality; }
        };
    }

    /** 空操作画布（消除 Flash 绘图 API 的实际渲染开销） */
    private static function makeCanvasNoOp():Object {
        return {
            _x: 0,
            _y: 0,
            clear: function():Void {},
            beginFill: function(color:Number, alpha:Number):Void {},
            endFill: function():Void {},
            moveTo: function(x:Number, y:Number):Void {},
            lineTo: function(x:Number, y:Number):Void {},
            curveTo: function(cx:Number, cy:Number, ax:Number, ay:Number):Void {},
            lineStyle: function(thickness:Number, color:Number, alpha:Number):Void {}
        };
    }

    /** 构造 24 小时光照数组（与其他测试一致） */
    private static function buildLight():Array {
        var arr:Array = [];
        for (var i:Number = 0; i < 24; i++) {
            arr.push(i % 9);
        }
        return arr;
    }

    /**
     * 格式化单条基准结果
     * @param name 基准名称
     * @param elapsedMs 总耗时（ms）
     * @param iterations 迭代次数
     * @param checksum 校验和（防止空循环消除）
     */
    private static function line(name:String, elapsedMs:Number, iterations:Number, checksum:Number):String {
        var perOpUs:Number = (iterations > 0) ? (elapsedMs * 1000 / iterations) : 0;
        return "  " + name + ": " + elapsedMs + " ms / " + iterations +
               " (" + round3(perOpUs) + " us/op, checksum=" + round3(checksum) + ")\n";
    }

    /** 保留3位小数 */
    private static function round3(v:Number):Number {
        return Math.round(v * 1000) / 1000;
    }
}
