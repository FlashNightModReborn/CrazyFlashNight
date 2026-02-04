import org.flashNight.neur.Controller.PIDController;
import org.flashNight.neur.Controller.SimpleKalmanFilter1D;
import org.flashNight.neur.PerformanceOptimizer.PerformanceScheduler;

/**
 * PerformanceSchedulerTest - 门面协调器基础回归测试（mock actuator/viz）
 */
class org.flashNight.neur.PerformanceOptimizer.test.PerformanceSchedulerTest {

    public static function runAllTests():String {
        var out:String = "=== PerformanceSchedulerTest ===\n";
        out += test_twoStepConfirmationLeadsToActuation();
        return out + "\n";
    }

    private static function test_twoStepConfirmationLeadsToActuation():String {
        var out:String = "[evaluate]\n";

        // mock root ui
        var canvas:Object = { clear:function(){}, beginFill:function(){}, endFill:function(){}, moveTo:function(){}, lineTo:function(){}, curveTo:function(){}, lineStyle:function(){}, _x:0, _y:0 };
        var root:Object = {
            _quality: "HIGH",
            lastMsg: null,
            发布消息: function(msg:String):Void { this.lastMsg = msg; },
            天气系统: { 当前时间: 0, 昼夜光照: buildLight() },
            玩家信息界面: { 性能帧率显示器: { 帧率数字: { text: null }, 画布: canvas } },
            显示列表: { 预设任务ID: "TASK", 继续播放:function(){}, 暂停播放:function(){} },
            UI系统: { 经济面板动效: true }
        };

        // host stub
        var host:Object = {
            帧率: 30,
            targetFPS: 26,
            预设画质: "HIGH",
            性能等级: 0,
            性能等级上限: 0,
            实际帧率: 0,
            frameStartTime: 0,
            measurementIntervalFrames: 30,
            awaitConfirmation: false,
            kalmanFilter: new SimpleKalmanFilter1D(30, 0.5, 1),
            PID: new PIDController(1, 0, 0, 1000, 0.1),
            offsetTolerance: 0
        };

        var scheduler:PerformanceScheduler = new PerformanceScheduler(host, 30, 26, "HIGH", {root: root});

        // 注入 mock actuator（记录apply调用）
        var applied:Array = [];
        var mockActuator:Object = { apply: function(level:Number):Void { applied.push(level); } };
        scheduler.setActuator(mockActuator);

        // 注入 mock viz（避免依赖绘图/天气）
        var mockViz:Object = {
            updateData: function(fps:Number):Void {},
            drawCurve: function(c:MovieClip, level:Number):Void {}
        };
        scheduler.setVisualization(mockViz);

        // 模拟60帧，帧间隔50ms（≈20FPS），触发两次评估
        var t:Number = 0;
        for (var i:Number = 0; i < 60; i++) {
            t += 50;
            scheduler.evaluate(t);
        }

        out += line(applied.length == 1, "两次确认后只执行一次切档");
        out += line(applied.length == 1 && applied[0] == 3, "低FPS下切到level3（clamp后）");
        out += line(host.性能等级 == 3, "host.性能等级更新为3");
        out += line(host.measurementIntervalFrames == 120, "切到level3后采样周期=120帧");

        return out;
    }

    private static function buildLight():Array {
        var arr:Array = [];
        for (var i:Number = 0; i < 24; i++) {
            arr.push(i % 9);
        }
        return arr;
    }

    private static function line(ok:Boolean, msg:String):String {
        return "  " + (ok ? "✓ " : "✗ ") + msg + "\n";
    }
}
