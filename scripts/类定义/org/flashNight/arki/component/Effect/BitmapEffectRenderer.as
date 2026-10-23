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
        renderBloodstainVariant(x, y, random(8));
    }

    // Native decoration already selected the variant; keep the existing layer/pixels.
    public static function renderBloodstainVariant(x:Number, y:Number, index:Number):Boolean{
        if(!isFinite(x + y + index) || index < 0 || index > 7 || index != Math.floor(index)) return false;
        if(!bloodstainInfos || !bitmapDict || !_root.gameworld) return false;
        var bitmapInfo = bloodstainInfos[index];
        if(bitmapInfo == undefined) return false;
        var bitmap = bitmapDict[bitmapInfo.id];
        var deadbody:MovieClip = _root.gameworld.deadbody;
        if(!bitmap || !deadbody || !deadbody.layers || !deadbody.layers[0]) return false;
        var originX:Number = isNaN(deadbody.layerOriginX) ? 0 : deadbody.layerOriginX;
        var originY:Number = isNaN(deadbody.layerOriginY) ? 0 : deadbody.layerOriginY;
        // 渲染到尸体层第0层
        deadbody.layers[0].copyPixels(
            bitmap,
            bitmap.rectangle,
            new Point(x - originX - bitmapInfo.offsetX, y - originY - bitmapInfo.offsetY),
            null,
            null,
            true
        );
        return true;
    }

}
