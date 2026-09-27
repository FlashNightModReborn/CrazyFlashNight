import flash.display.BitmapData;
import flash.geom.Matrix;
import flash.geom.ColorTransform;

// 场景内有界落地队列；素材位图可跨场景，临时源 MC 烘焙后立即移除。
class org.flashNight.arki.render.DecalStampQueue {
    private static var queue:Array = [];
    private static var cache:Object = {};
    private static var density:Object = {};
    private static var total:Number = 0;
    private static var cacheCount:Number = 0;
    private static var bakeSerial:Number = 0;
    private static var matrix:Matrix = new Matrix();
    private static var darken:ColorTransform = new ColorTransform(0.7, 0.7, 0.7, 1, 0, 0, 0, 0);

    public static function resetScene():Void { queue.length = 0; density = {}; total = 0; }

    public static function clearCache():Void {
        for (var key:String in cache) cache[key].bitmap.dispose();
        cache = {};
        cacheCount = 0;
    }

    public static function enqueue(pose:Array, linkage:String):Boolean {
        if (queue.length >= 64 || linkage == undefined) return false;
        queue[queue.length] = {pose:pose, linkage:linkage};
        return true;
    }

    public static function flush():Array {
        var acks:Array = [];
        var count:Number = queue.length < 4 ? queue.length : 4;
        for (var i:Number = 0; i < count; i++) {
            var item:Object = queue.shift();
            var drawn:Boolean = drawPose(item.pose, item.linkage);
            acks[acks.length] = "a," + item.pose[0] + "," + (drawn ? 1 : 0);
        }
        return acks;
    }

    private static function bitmapFor(linkage:String):Object {
        var found:Object = cache[linkage];
        if (found != undefined) return found;
        if (cacheCount >= 32) return undefined;
        var parent:MovieClip = _root.gameworld.效果;
        if (!parent) return undefined;
        var source:MovieClip = parent.attachMovie(linkage, "__fxBake" + (++bakeSerial), parent.getNextHighestDepth());
        if (!source) return undefined;
        source.stop();
        source._x = -100000;
        source._y = -100000;
        var bounds:Object = source.getBounds(source);
        var left:Number = Math.floor(bounds.xMin) - 1;
        var top:Number = Math.floor(bounds.yMin) - 1;
        var width:Number = Math.ceil(bounds.xMax) - left + 1;
        var height:Number = Math.ceil(bounds.yMax) - top + 1;
        if (!isFinite(width + height) || width < 1 || height < 1 || width > 256 || height > 256) {
            source.removeMovieClip();
            return undefined;
        }
        var bitmap:BitmapData = new BitmapData(width, height, true, 0);
        if (!bitmap) { source.removeMovieClip(); return undefined; }
        bitmap.draw(source, new Matrix(1, 0, 0, 1, -left, -top), null, "normal", undefined, true);
        source.removeMovieClip();
        found = {bitmap:bitmap, left:left, top:top};
        cache[linkage] = found;
        cacheCount++;
        return found;
    }

    private static function drawPose(pose:Array, linkage:String):Boolean {
        var world:MovieClip = _root.gameworld;
        var body:MovieClip = world.deadbody;
        var target:BitmapData = body.layers[2];
        if (!world || !body || !target || total >= 4096) return false;
        var x:Number = pose[2], y:Number = pose[3];
        var screenX:Number = world._x + x * world._xscale * 0.01;
        var screenY:Number = world._y + y * world._yscale * 0.01;
        if (screenX < -60 || screenX > Stage.width + 60 || screenY < -60 || screenY > Stage.height + 60) return false;
        var cell:String = Math.floor(x / 64) + ":" + Math.floor(y / 64);
        var used:Number = density[cell] == undefined ? 0 : density[cell];
        if (used >= 32) return false;
        var asset:Object = bitmapFor(linkage);
        if (asset == undefined) return false;
        var angle:Number = pose[4] * Math.PI / 180;
        var sx:Number = pose[5] * 0.01, sy:Number = pose[6] * 0.01;
        var cosV:Number = Math.cos(angle), sinV:Number = Math.sin(angle);
        matrix.a = cosV * sx; matrix.b = sinV * sx;
        matrix.c = -sinV * sy; matrix.d = cosV * sy;
        matrix.tx = x + matrix.a * asset.left + matrix.c * asset.top;
        matrix.ty = y + matrix.b * asset.left + matrix.d * asset.top;
        var toLayer:Matrix = body.transform.matrix.clone();
        toLayer.invert();
        matrix.concat(toLayer);
        target.draw(asset.bitmap, matrix, darken, "normal", undefined, true);
        density[cell] = used + 1;
        total++;
        return true;
    }

    public static function getStats():Object {
        return {pending:queue.length, cached:cacheCount, stamps:total};
    }
}
