import flash.display.BitmapData;
import flash.geom.Rectangle;
import flash.geom.Point;
import org.flashNight.naki.RandomNumberEngine.*;


/**
 * BitmapEffectRenderer
 * 
 * 位图特效渲染器。目前仅有渲染位图血迹功能
 */

class org.flashNight.arki.component.Effect.BitmapEffectRenderer
{
    public static var initialized:Boolean = false;

    public static var bitmapDict:Object;
    public static var bloodstainInfos:Array;

    /**
     * 初始化，在全局初始器执行
     */
    public static function initialize():Void{
        if(initialized) return;
        bitmapDict = {};
        initialized = true;
    }

    /**
     * 载入血迹位图
     */
    public static function loadBloodstains():Void{
        var bolldstainID:String = "位图血迹";
        bloodstainInfos = new Array(8);
        for(var i=0; i<8; i++){
            var id = bolldstainID + i;
            var bitmap = BitmapData.loadBitmap(id);
            bloodstainInfos[i] = {
                id: id,
                offsetX: (bitmap.width * 0.5) >> 0,
                offsetY: (bitmap.height * 0.5) >> 0
            };
            bitmapDict[id] = bitmap;
        }
    }


    public static function renderBloodstain(x:Number, y:Number):Void{
        var bitmapInfo = bloodstainInfos[random(8)];
        var bitmap = bitmapDict[bitmapInfo.id];
        // 渲染到尸体层第0层
        _root.gameworld.deadbody.layers[0].copyPixels(
            bitmap,
            bitmap.rectangle,
            new Point(x - bitmapInfo.offsetX, y - bitmapInfo.offsetY),
            null,
            null,
            true
        );
    }

}
