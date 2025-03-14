import org.flashNight.sara.util.*;

class org.flashNight.arki.spatial.transform.SceneCoordinateManager {
    // 静态属性：存储当前的偏移量
    public static var offset:Object = new Vector(0, 0);
    
    // 计算偏移量，直接操作静态属性
    public static function calculateOffset():Void {
        offset.setTo(0, 0);

        var gw:MovieClip = _root.gameworld;
        var map:MovieClip = gw.地图;

        map.localToGlobal(offset);
        gw.globalToLocal(offset);

        return offset;
    }
    
    // 获取当前偏移量
    public static function getOffset():Object {
        return offset;
    }
}
