import org.flashNight.gesh.paint.renderMachine.*;
import flash.geom.ColorTransform;

class org.flashNight.gesh.paint.renderMachine.RendererVM {
    public var utils:org.flashNight.gesh.paint.renderMachine.Utils; // 修改为 public
    private var commandStream:String;
    private var len:Number;
    private var i:Number;
    private var commandMap:Object;
    private var mc:MovieClip; // 绘图目标

    // 当前绘图状态
    private var penX:Number = 0;
    private var penY:Number = 0;
    private var currentColor:Number = 0x000000;
    private var currentAlpha:Number = 100;

    public function RendererVM(target:MovieClip) {
        this.mc = target;
        this.utils = new org.flashNight.gesh.paint.renderMachine.Utils();
        initializeCommandMap();  // 使用动态初始化来构建指令映射表
    }

    // 动态初始化指令映射表
    private function initializeCommandMap():Void {
        commandMap = {};
        commandMap["M"] = handleMoveTo;
        commandMap["L"] = handleLineTo;
        commandMap["C"] = handleCurveTo;
        commandMap["R"] = handleDrawRect;
        commandMap["O"] = handleDrawCircle;
        commandMap["A"] = handleDrawRoundRect;  // 'A' 指令的不同用途可以通过进一步区分
        commandMap["P"] = handleDrawPolygon;
        commandMap["S"] = handleSetLineStyle;
        commandMap["F"] = handleBeginFill;
        commandMap["G"] = handleBeginGradientFill;
        commandMap["B"] = handleBeginBitmapFill;
        commandMap["T"] = handleSetColorTransform;
        commandMap["N"] = handleSetBlendModeNormal;
        commandMap["X"] = handleSetBlendModeMultiply;
        commandMap["D"] = handleSetBlendModeAdd;
        commandMap["U"] = handleSetBlendModeSubtract;
        commandMap["K"] = handleClear;
        commandMap["E"] = handleEndFill;
        commandMap[";"] = handleEndCommand;
    }

    public function executeCommandStream(commandStream:String):Void {
        this.commandStream = commandStream;
        this.len = commandStream.length;
        this.i = 0;

        trace("Executing command stream: " + commandStream);

        while (i < len) {
            var cmd:String = commandStream.charAt(i++);
            trace("Processing command: " + cmd); // 输出当前处理的指令
            
            var handler:Function = commandMap[cmd];
            if (handler != undefined) {
                handler.call(this);
            } else if (cmd == ';') {
                continue;  // 指令结束符
            } else {
                trace("未知指令: " + cmd);  // 输出未知指令
            }
        }
    }

    // 指令处理函数
    private function handleMoveTo():Void {
        var x:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var y:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引

        trace("Executing MoveTo with parameters: x=" + x + ", y=" + y); // 输出参数

        penX = x;
        penY = y;
        mc.moveTo(penX, penY);
    }

    private function handleLineTo():Void {
        var x:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var y:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引

        trace("Executing LineTo with parameters: x=" + x + ", y=" + y); // 输出参数

        penX = x;
        penY = y;
        mc.lineTo(penX, penY);
    }

    private function handleCurveTo():Void {
        var cx:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var cy:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var ax:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var ay:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引

        trace("Executing CurveTo with control: cx=" + cx + ", cy=" + cy + ", anchor: ax=" + ax + ", ay=" + ay); // 输出参数

        mc.curveTo(cx, cy, ax, ay);
    }

    private function handleDrawRect():Void {
        var x:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var y:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var w:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var h:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引

        trace("Executing DrawRect with parameters: x=" + x + ", y=" + y + ", w=" + w + ", h=" + h); // 输出参数

        mc.moveTo(x, y);
        mc.lineTo(x + w, y);
        mc.lineTo(x + w, y + h);
        mc.lineTo(x, y + h);
        mc.lineTo(x, y);
    }

    private function handleDrawCircle():Void {
        var x:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var y:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var r:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引

        trace("Executing DrawCircle with parameters: x=" + x + ", y=" + y + ", r=" + r); // 输出参数

        drawCircle(mc, x, y, r);
    }

    private function handleDrawRoundRect():Void {
        var x:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var y:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var w:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var h:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var rx:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var ry:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引

        trace("Executing DrawRoundRect with parameters: x=" + x + ", y=" + y + ", w=" + w + ", h=" + h + ", rx=" + rx + ", ry=" + ry); // 输出参数

        mc.drawRoundRect(x, y, w, h, rx, ry);
    }

    private function handleDrawPolygon():Void {
        var x:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var y:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var radius:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var sides:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引

        trace("Executing DrawPolygon with parameters: x=" + x + ", y=" + y + ", radius=" + radius + ", sides=" + sides); // 输出参数

        drawPolygon(mc, x, y, radius, sides);
    }

    private function handleSetLineStyle():Void {
        var thickness:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var colorCode:String = utils.readColorCode(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var alpha:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var color:Number = utils.decodeColor(colorCode);
        currentColor = color;
        currentAlpha = alpha;

        trace("Executing SetLineStyle with parameters: thickness=" + thickness + ", color=" + color.toString(16) + ", alpha=" + alpha); // 输出参数

        mc.lineStyle(thickness, currentColor, currentAlpha);
    }

    private function handleBeginFill():Void {
        var colorCode:String = utils.readColorCode(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var alpha:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var color:Number = utils.decodeColor(colorCode);

        trace("Executing BeginFill with parameters: color=" + color.toString(16) + ", alpha=" + alpha); // 输出参数

        mc.beginFill(color, alpha);
    }

    private function handleBeginGradientFill():Void {
        var type:String = utils.readString(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var colors:String = utils.readString(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var alphas:String = utils.readString(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var ratios:String = utils.readString(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var colorArray:Array = utils.decodeColors(colors);
        var alphaArray:Array = utils.decodeAlphas(alphas);
        var ratioArray:Array = utils.decodeRatios(ratios);

        trace("Executing BeginGradientFill with type=" + type + ", colors=" + colors + ", alphas=" + alphas + ", ratios=" + ratios); // 输出参数

        mc.beginGradientFill(type, colorArray, alphaArray, ratioArray);
    }

    private function handleBeginBitmapFill():Void {
        // todo: 插入日志后续实现位图填充逻辑
        trace("Executing BeginBitmapFill - Not yet implemented"); // 输出todo日志
    }

    private function handleSetColorTransform():Void {
        var rM:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var gM:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var bM:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var rO:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var gO:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var bO:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var aM:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        var aO:Number = utils.readNumber(commandStream, len, i);
        i = utils.getCurrentIndex(); // 更新索引
        
        trace("Executing SetColorTransform with parameters: rM=" + rM + ", gM=" + gM + ", bM=" + bM + ", rO=" + rO + ", gO=" + gO + ", bO=" + bO + ", aM=" + aM + ", aO=" + aO); // 输出参数

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

    private function handleSetBlendModeNormal():Void {
        trace("Executing SetBlendMode: normal"); // 输出混合模式
        mc.blendMode = "normal";
    }

    private function handleSetBlendModeMultiply():Void {
        trace("Executing SetBlendMode: multiply"); // 输出混合模式
        mc.blendMode = "multiply";
    }

    private function handleSetBlendModeAdd():Void {
        trace("Executing SetBlendMode: add"); // 输出混合模式
        mc.blendMode = "add";
    }

    private function handleSetBlendModeSubtract():Void {
        trace("Executing SetBlendMode: subtract"); // 输出混合模式
        mc.blendMode = "subtract";
    }

    private function handleClear():Void {
        trace("Executing Clear"); // 输出清除操作
        mc.clear();
    }

    private function handleEndFill():Void {
        trace("Executing EndFill"); // 输出结束填充操作
        mc.endFill();
    }

    private function handleEndCommand():Void {
        // 可以在此处处理指令结束的逻辑
        trace("Executing EndCommand"); // 输出结束指令
    }

    // 绘制圆形的辅助函数
    private function drawCircle(mc:MovieClip, x:Number, y:Number, r:Number):Void {
        trace("Drawing Circle with parameters: x=" + x + ", y=" + y + ", radius=" + r); // 输出绘制圆形的参数
        mc.moveTo(x + r, y);
        for (var angle:Number = 0; angle <= 360; angle += 10) {
            var radian:Number = angle * (Math.PI / 180);
            var px:Number = x + r * Math.cos(radian);
            var py:Number = y + r * Math.sin(radian);
            mc.lineTo(px, py);
        }
    }

    // 绘制多边形的辅助函数
    private function drawPolygon(mc:MovieClip, x:Number, y:Number, radius:Number, sides:Number):Void {
        trace("Drawing Polygon with parameters: x=" + x + ", y=" + y + ", radius=" + radius + ", sides=" + sides); // 输出绘制多边形的参数
        mc.moveTo(x + radius, y);
        for (var j:Number = 1; j <= sides; j++) {
            var angle:Number = (j / sides) * 2 * Math.PI;
            mc.lineTo(x + radius * Math.cos(angle), y + radius * Math.sin(angle));
        }
        mc.lineTo(x + radius, y);
    }
}
