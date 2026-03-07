import org.flashNight.gesh.paint.renderMachine.*;
import org.flashNight.neur.Event.Delegate; // 引入 Delegate 类
import flash.geom.ColorTransform;
import flash.display.BitmapData;
import flash.geom.Matrix;

class org.flashNight.gesh.paint.renderMachine.RendererVM {
    public var utils:org.flashNight.gesh.paint.renderMachine.Utils;
    private var commandStream:String;
    private var len:Number;
    private var i:Number;
    private var commandMap:Object;
    private var mc:MovieClip; // Drawing target

    // Current drawing state
    private var penX:Number = 0;
    private var penY:Number = 0;
    private var currentColor:Number = 0x000000;
    private var currentAlpha:Number = 100;

    public function RendererVM(target:MovieClip) {
        this.mc = target;
        this.utils = new org.flashNight.gesh.paint.renderMachine.Utils();
        initializeCommandMap();  // 动态初始化命令映射
    }

    // 动态初始化命令映射，使用 Delegate 包装函数
    private function initializeCommandMap():Void {
        commandMap = {};
        commandMap["M"] = Delegate.create(this, handleMoveTo);
        commandMap["L"] = Delegate.create(this, handleLineTo);
        commandMap["C"] = Delegate.create(this, handleCurveTo);
        commandMap["R"] = Delegate.create(this, handleDrawRect);
        commandMap["O"] = Delegate.create(this, handleDrawCircle);
        commandMap["A"] = Delegate.create(this, handleDrawRoundRect);
        commandMap["P"] = Delegate.create(this, handleDrawPolygon);
        commandMap["S"] = Delegate.create(this, handleSetLineStyle);
        commandMap["F"] = Delegate.create(this, handleBeginFill);
        commandMap["G"] = Delegate.create(this, handleBeginGradientFill);
        commandMap["B"] = Delegate.create(this, handleBeginBitmapFill);
        commandMap["T"] = Delegate.create(this, handleSetColorTransform);
        commandMap["Q"] = Delegate.create(this, handleSetAlpha);
        commandMap["N"] = Delegate.create(this, handleSetBlendModeNormal);
        commandMap["X"] = Delegate.create(this, handleSetBlendModeMultiply);
        commandMap["D"] = Delegate.create(this, handleSetBlendModeAdd);
        commandMap["U"] = Delegate.create(this, handleSetBlendModeSubtract);
        commandMap["K"] = Delegate.create(this, handleClear);
        commandMap["E"] = Delegate.create(this, handleEndFill);
        commandMap[";"] = Delegate.create(this, handleEndCommand);
    }

    public function executeCommandStream(commandStream:String):Void {
        this.commandStream = commandStream;
        this.len = commandStream.length;
        this.i = 0;

        while (i < len) {
            var cmd:String = commandStream.charAt(i++);
            var handler:Function = commandMap[cmd];
            if (handler != undefined) {
                handler(); // 直接调用缓存的函数对象
            } else if (cmd == ';') {
                continue;  // 命令终止符
            } else {
                // 未知命令，可以考虑添加日志
                // trace("Unknown command: " + cmd);
            }
        }
    }

    // 命令处理函数
    private function handleMoveTo():Void {
        var x:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var y:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();

        penX = x;
        penY = y;
        mc.moveTo(penX, penY);
    }

    private function handleLineTo():Void {
        var x:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var y:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();

        penX = x;
        penY = y;
        mc.lineTo(penX, penY);
    }

    private function handleCurveTo():Void {
        var cx:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var cy:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var ax:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var ay:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();

        mc.curveTo(cx, cy, ax, ay);
    }

    private function handleDrawRect():Void {
        var x:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var y:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var w:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var h:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();

        mc.moveTo(x, y);
        mc.lineTo(x + w, y);
        mc.lineTo(x + w, y + h);
        mc.lineTo(x, y + h);
        mc.lineTo(x, y);
    }

    private function handleDrawCircle():Void {
        var x:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var y:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var r:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();

        drawCircle(mc, x, y, r);
    }

    private function handleDrawRoundRect():Void {
        var x:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var y:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var w:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var h:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var rx:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var ry:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();

        mc.drawRoundRect(x, y, w, h, rx, ry);
    }

    private function handleDrawPolygon():Void {
        var x:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var y:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var radius:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var sides:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();

        drawPolygon(mc, x, y, radius, sides);
    }

    private function handleSetLineStyle():Void {
        var thickness:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var colorCode:String = utils.readColorCode(commandStream, len, i);
        i = utils.getCurrentIndex();
        var alpha:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var color:Number = utils.decodeColor(colorCode);
        currentColor = color;
        currentAlpha = alpha;

        mc.lineStyle(thickness, currentColor, currentAlpha);
    }

    private function handleBeginFill():Void {
        var colorCode:String = utils.readColorCode(commandStream, len, i);
        i = utils.getCurrentIndex();
        var alpha:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var color:Number = utils.decodeColor(colorCode);

        mc.beginFill(color, alpha);
    }

    private function handleBeginGradientFill():Void {
        var type:String = utils.readString(commandStream, len, i);
        i = utils.getCurrentIndex();
        var colors:String = utils.readString(commandStream, len, i);
        i = utils.getCurrentIndex();
        var alphas:String = utils.readString(commandStream, len, i);
        i = utils.getCurrentIndex();
        var ratios:String = utils.readString(commandStream, len, i);
        i = utils.getCurrentIndex();
        var colorArray:Array = utils.decodeColors(colors);
        var alphaArray:Array = utils.decodeAlphas(alphas);
        var ratioArray:Array = utils.decodeRatios(ratios);

        mc.beginGradientFill(type, colorArray, alphaArray, ratioArray);
    }

    private function handleBeginBitmapFill():Void {
        var bitmapId:String = utils.readString(commandStream, len, i);
        i = utils.getCurrentIndex();

        var bitmapData:BitmapData = getBitmapDataById(bitmapId);

        if (bitmapData != null) {
            var matrix:Matrix = new Matrix();
            mc.beginBitmapFill(bitmapData, matrix, true, true);
        } else {
            // BitmapData 未找到，可以添加日志或默认处理
            // trace("BitmapData not found for ID: " + bitmapId);
        }
    }

    private function handleSetColorTransform():Void {
        var rM:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var gM:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var bM:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var rO:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var gO:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var bO:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var aM:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();
        var aO:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();

        var ct:ColorTransform = new ColorTransform();
        ct.redMultiplier = rM;
        ct.greenMultiplier = gM;
        ct.blueMultiplier = bM;
        ct.redOffset = rO;
        ct.greenOffset = gO;
        ct.blueOffset = bO;
        ct.alphaMultiplier = aM;
        ct.alphaOffset = aO;

        mc.transform.colorTransform = ct;
    }

    private function handleSetAlpha():Void {
        var alpha:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex();

        currentAlpha = alpha;
        mc._alpha = alpha;
    }

    private function handleSetBlendModeNormal():Void {
        mc.blendMode = "normal";
    }

    private function handleSetBlendModeMultiply():Void {
        mc.blendMode = "multiply";
    }

    private function handleSetBlendModeAdd():Void {
        mc.blendMode = "add";
    }

    private function handleSetBlendModeSubtract():Void {
        mc.blendMode = "subtract";
    }

    private function handleClear():Void {
        mc.clear();
    }

    private function handleEndFill():Void {
        mc.endFill();
    }

    private function handleEndCommand():Void {
        // 处理命令终止符，如果需要的话
    }

    // 辅助函数：绘制圆形
    private function drawCircle(mc:MovieClip, x:Number, y:Number, r:Number):Void {
        mc.moveTo(x + r, y);
        for (var angle:Number = 0; angle <= 360; angle += 10) {
            var radian:Number = angle * (Math.PI / 180);
            var px:Number = x + r * Math.cos(radian);
            var py:Number = y + r * Math.sin(radian);
            mc.lineTo(px, py);
        }
    }

    // 辅助函数：绘制多边形
    private function drawPolygon(mc:MovieClip, x:Number, y:Number, radius:Number, sides:Number):Void {
        mc.moveTo(x + radius, y);
        for (var j:Number = 1; j <= sides; j++) {
            var angle:Number = (j / sides) * 2 * Math.PI;
            mc.lineTo(x + radius * Math.cos(angle), y + radius * Math.sin(angle));
        }
        mc.lineTo(x + radius, y);
    }

    // 获取 BitmapData（此处保留之前的逻辑）
    private function getBitmapDataById(bitmapId:String):BitmapData {
        // 实现逻辑以根据 bitmapId 加载 BitmapData
        // 这是一个占位符，需根据实际情况实现
        return null;
    }
}
