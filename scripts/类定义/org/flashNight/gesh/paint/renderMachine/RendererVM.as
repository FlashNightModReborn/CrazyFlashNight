import org.flashNight.gesh.paint.renderMachine.*;
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
        initializeCommandMap();  // Dynamically initialize the command mapping
    }

    // Dynamically initialize the command mapping
    private function initializeCommandMap():Void {
        commandMap = {};
        commandMap["M"] = handleMoveTo;
        commandMap["L"] = handleLineTo;
        commandMap["C"] = handleCurveTo;
        commandMap["R"] = handleDrawRect;
        commandMap["O"] = handleDrawCircle;
        commandMap["A"] = handleDrawRoundRect;
        commandMap["P"] = handleDrawPolygon;
        commandMap["S"] = handleSetLineStyle;
        commandMap["F"] = handleBeginFill;
        commandMap["G"] = handleBeginGradientFill;
        commandMap["B"] = handleBeginBitmapFill;
        commandMap["T"] = handleSetColorTransform;
        commandMap["Q"] = handleSetAlpha;
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

        while (i < len) {
            var cmd:String = commandStream.charAt(i++);
            var handler:Function = commandMap[cmd];
            if (handler != undefined) {
                handler.call(this);
            } else if (cmd == ';') {
                continue;  // Command terminator
            } else {
                // Unknown command
            }
        }
    }

    // Command handling functions
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
            // BitmapData not found
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
        // Handle command termination if necessary
    }

    // Helper function to draw a circle
    private function drawCircle(mc:MovieClip, x:Number, y:Number, r:Number):Void {
        mc.moveTo(x + r, y);
        for (var angle:Number = 0; angle <= 360; angle += 10) {
            var radian:Number = angle * (Math.PI / 180);
            var px:Number = x + r * Math.cos(radian);
            var py:Number = y + r * Math.sin(radian);
            mc.lineTo(px, py);
        }
    }

    // Helper function to draw a polygon
    private function drawPolygon(mc:MovieClip, x:Number, y:Number, radius:Number, sides:Number):Void {
        mc.moveTo(x + radius, y);
        for (var j:Number = 1; j <= sides; j++) {
            var angle:Number = (j / sides) * 2 * Math.PI;
            mc.lineTo(x + radius * Math.cos(angle), y + radius * Math.sin(angle));
        }
        mc.lineTo(x + radius, y);
    }

    // Function to retrieve BitmapData by ID
    private function getBitmapDataById(bitmapId:String):BitmapData {
        // Implement logic to retrieve BitmapData based on bitmapId
        // For example, you might have a dictionary of BitmapData objects
        // Return the corresponding BitmapData object
        return null; // Placeholder
    }
}
