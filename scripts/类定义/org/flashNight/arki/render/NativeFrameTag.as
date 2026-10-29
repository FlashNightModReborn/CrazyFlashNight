class org.flashNight.arki.render.NativeFrameTag {
    private static var MAGIC:Number = 0x13579B;
    private static var CELL:Number = 16;
    private static var TAG_Y:Number = 560;
    private static var clip:MovieClip;
    private static var cells:Array;
    private static var currentEpoch:Number = -2;
    private static var currentFrame:Number = -2;

    private static function color(index:Number, epoch:Number, frame:Number):Number {
        if (index == 0) return MAGIC;
        var f0:Number = frame % 256;
        var f1:Number = Math.floor(frame / 256) % 256;
        var f2:Number = Math.floor(frame / 65536) % 256;
        if (index == 1) return f0 * 65536 + f1 * 256 + f2;
        if (index == 3) return (255 - f0) * 65536 + (255 - f1) * 256 + (255 - f2);
        var e0:Number = epoch % 256;
        var e1:Number = Math.floor(epoch / 256) % 256;
        var check:Number = (f0 + f1 + f2 + e0 + e1 + 0xA7) % 256;
        return e0 * 65536 + e1 * 256 + check;
    }

    private static function paint(index:Number):Void {
        var value:Number = color(index, currentEpoch, currentFrame);
        cells[index].clear();
        cells[index].beginFill(value);
        cells[index].moveTo(0, 0); cells[index].lineTo(CELL, 0); cells[index].lineTo(CELL, CELL);
        cells[index].lineTo(0, CELL); cells[index].endFill();
    }

    public static function update(root:MovieClip, epoch:Number, frame:Number):Void {
        if (root == null) return;
        if (!isFinite(epoch) || !isFinite(frame) || epoch < 0 || frame < 0) {
            hide(); return;
        }
        var nextEpoch:Number = Math.floor(epoch) % 65536;
        var nextFrame:Number = Math.floor(frame) % 16777216;
        if (clip != null && currentEpoch == nextEpoch && currentFrame == nextFrame) {
            clip._visible = true; return;
        }
        currentEpoch = nextEpoch; currentFrame = nextFrame;
        if (clip == null) {
            clip = root.createEmptyMovieClip("__nativeFrameTag", 2000000000);
            clip._x = 0; clip._y = TAG_Y;
            cells = [];
            for (var i:Number = 0; i < 4; i++) {
                var block:MovieClip = clip.createEmptyMovieClip("c" + i, i + 1);
                block._x = i * CELL;
                cells[i] = block;
            }
        }
        clip._visible = true;
        for (var j:Number = 0; j < 4; j++) paint(j);
    }

    public static function hide():Void {
        if (clip != null) clip._visible = false;
        currentEpoch = -2; currentFrame = -2;
    }

    public static function reset():Void {
        if (clip != null) clip.removeMovieClip();
        clip = null; cells = null; currentEpoch = -2; currentFrame = -2;
    }

    public static function stateForTests():Object {
        var colors:Array = [];
        if (cells != null) {
            for (var i:Number = 0; i < cells.length; i++) {
                colors[i] = color(i, currentEpoch, currentFrame);
            }
        }
        return {epoch:currentEpoch, frame:currentFrame, visible:clip != null && clip._visible, colors:colors};
    }

    public static function checksumForTests(epoch:Number, frame:Number):Number {
        return color(2, epoch, frame) % 256;
    }
}
