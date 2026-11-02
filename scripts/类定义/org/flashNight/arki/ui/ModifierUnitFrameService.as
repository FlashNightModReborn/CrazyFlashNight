import flash.display.BitmapData;
import flash.geom.Matrix;

class org.flashNight.arki.ui.ModifierUnitFrameService {
    private static var _sequence:Number = 0;

    public static function capture(spriteName:String):Object {
        var parent:MovieClip = _root.修改工具界面 != undefined && _root.修改工具界面.缩略图 != undefined ? _root.修改工具界面.缩略图 : _root;
        var holder:MovieClip = parent.createEmptyMovieClip("__modifierUnitFrame" + (++_sequence), parent.getNextHighestDepth());
        var inst:MovieClip = null;
        try {
            inst = holder.attachMovie(spriteName, "unit", 1);
        } catch (attachError) {
            inst = null;
        }
        if (inst == null && parent != _root) {
            holder.removeMovieClip();
            parent = _root;
            holder = parent.createEmptyMovieClip("__modifierUnitFrame" + (++_sequence), parent.getNextHighestDepth());
            try {
                inst = holder.attachMovie(spriteName, "unit", 1);
            } catch (fallbackAttachError) {
                inst = null;
            }
        }
        if (inst == null) {
            holder.removeMovieClip();
            return null;
        }
        var bitmap:BitmapData = null;
        try {
            inst.gotoAndStop(1);
            inst._x = 0;
            inst._y = 0;
            var bounds:Object = inst.getBounds(holder);
            var x0:Number = Math.floor(bounds.xMin);
            var y0:Number = Math.floor(bounds.yMin);
            var sourceW:Number = Math.ceil(bounds.xMax - bounds.xMin);
            var sourceH:Number = Math.ceil(bounds.yMax - bounds.yMin);
            if (sourceW < 1 || sourceH < 1) return null;
            var factor:Number = Math.min(1, 192 / Math.max(sourceW, sourceH));
            var width:Number = Math.max(1, Math.ceil(sourceW * factor));
            var height:Number = Math.max(1, Math.ceil(sourceH * factor));
            bitmap = new BitmapData(width, height, true, 0);
            bitmap.draw(inst, new Matrix(factor, 0, 0, factor, -x0 * factor, -y0 * factor));
            var bytes:Array = [];
            for (var py:Number = 0; py < height; py++) {
                for (var px:Number = 0; px < width; px++) {
                    var color:Number = bitmap.getPixel32(px, py);
                    bytes.push((color >> 24) & 255, (color >> 16) & 255, (color >> 8) & 255, color & 255);
                }
            }
            return {width:width, height:height, pixels:Base64.encodeBytes(bytes)};
        } catch (frameError) {
            return null;
        } finally {
            if (bitmap != null) bitmap.dispose();
            holder.removeMovieClip();
        }
    }
}