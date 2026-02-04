import org.flashNight.neur.PerformanceOptimizer.FPSVisualization;

/**
 * FPSVisualizationTest - 可视化模块单元测试（使用mock canvas / weather）
 */
class org.flashNight.neur.PerformanceOptimizer.test.FPSVisualizationTest {

    public static function runAllTests():String {
        var out:String = "=== FPSVisualizationTest ===\n";
        out += test_updateDataAndDrawCurve();
        return out + "\n";
    }

    private static function test_updateDataAndDrawCurve():String {
        var out:String = "[viz]\n";

        var light:Array = [];
        for (var i:Number = 0; i < 24; i++) {
            light.push(i % 9);
        }
        var weather:Object = { 当前时间: 10.5, 昼夜光照: light };

        var viz:FPSVisualization = new FPSVisualization(4, 30, weather);
        viz.updateData(25);

        out += line(viz.getBuffer().min <= viz.getBuffer().max, "buffer min/max 合法");
        out += line(viz.getFPSDiff() >= 5, "fpsDiff >= 最小差异5");

        // mock canvas
        var canvas = makeCanvasMock();
        viz.drawCurve(canvas, 0);

        // 检查lineStyle颜色（level0→绿色）
        var lineStyleCall:Object = findLastCall(canvas.calls, "lineStyle");
        out += line(lineStyleCall != null && lineStyleCall.color == 0x00FF00, "level0 线条颜色=0x00FF00");

        // 再画一次 level2 → 黄色
        canvas.calls = [];
        viz.drawCurve(canvas, 2);
        lineStyleCall = findLastCall(canvas.calls, "lineStyle");
        out += line(lineStyleCall != null && lineStyleCall.color == 0xFFFF00, "level2 线条颜色=0xFFFF00");

        return out;
    }

    private static function makeCanvasMock():Object {
        return {
            _x: 0,
            _y: 0,
            calls: [],
            clear: function():Void { this.calls.push({fn:"clear"}); },
            beginFill: function(color:Number, alpha:Number):Void { this.calls.push({fn:"beginFill", color:color, alpha:alpha}); },
            endFill: function():Void { this.calls.push({fn:"endFill"}); },
            moveTo: function(x:Number, y:Number):Void { this.calls.push({fn:"moveTo", x:x, y:y}); },
            lineTo: function(x:Number, y:Number):Void { this.calls.push({fn:"lineTo", x:x, y:y}); },
            curveTo: function(cx:Number, cy:Number, ax:Number, ay:Number):Void { this.calls.push({fn:"curveTo"}); },
            lineStyle: function(thickness:Number, color:Number, alpha:Number):Void { this.calls.push({fn:"lineStyle", thickness:thickness, color:color, alpha:alpha}); }
        };
    }

    private static function findLastCall(calls:Array, fnName:String):Object {
        for (var i:Number = calls.length - 1; i >= 0; i--) {
            if (calls[i].fn == fnName) {
                return calls[i];
            }
        }
        return null;
    }

    private static function line(ok:Boolean, msg:String):String {
        return "  " + (ok ? "✓ " : "✗ ") + msg + "\n";
    }
}
