/**
 * 当前地点来自 C# 四源解析。pending 只用于跳转动画中的短时显示，绝不表示实际到达。
 */
import org.flashNight.arki.map.MapDomainBridge;

class org.flashNight.arki.map.MapHotspotResolver {
    private static var _pendingHotspotId:String = "";
    private static var _pendingSource:String = "";
    private static var _pendingUntil:Number = 0;
    public static function resolveCurrentFromSources():String {
        return String(MapDomainBridge.getProjection().snapshot.currentHotspotId || "");
    }
    public static function isCurrentFrameName(frameName:String):Boolean {
        if (frameName == undefined || frameName == "") return false;
        var location:String = String(MapDomainBridge.getBootstrap().locationByFrame[frameName] || "");
        return location != "" && location == String(MapDomainBridge.getProjection().currentLocationId || "");
    }
    public static function resolveCurrent():String {
        var current:String = resolveCurrentFromSources();
        if (_pendingHotspotId != "") {
            if (getTimer() > _pendingUntil || current == _pendingHotspotId || (current != "" && current != _pendingSource)) reset();
            else return _pendingHotspotId;
        }
        return current;
    }
    public static function beginPending(targetHotspotId:String):Void {
        _pendingSource = resolveCurrentFromSources();
        _pendingHotspotId = targetHotspotId; _pendingUntil = getTimer() + 2000;
    }
    public static function reset():Void { _pendingHotspotId = ""; _pendingSource = ""; _pendingUntil = 0; }
}
