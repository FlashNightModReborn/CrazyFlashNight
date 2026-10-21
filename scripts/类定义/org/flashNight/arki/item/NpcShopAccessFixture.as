/** Focused suites only: synthetic Host projection, never installed by production boot. */
class org.flashNight.arki.item.NpcShopAccessFixture {
    private static var _getter:Function;
    private static var _current:Function;
    private static var _ready:Boolean;
    private static var _denied:Object;
    public static function install():Void {
        var bridge:Object = org.flashNight.arki.map.MapDomainBridge;
        _getter = bridge.getProjection; _current = bridge.isCurrent;
        _ready = true; _denied = {};
        bridge.getProjection = function():Object { return org.flashNight.arki.item.NpcShopAccessFixture.projection(); };
        bridge.isCurrent = function():Boolean { return org.flashNight.arki.item.NpcShopAccessFixture.ready(); };
    }
    public static function restore():Void {
        var bridge:Object = org.flashNight.arki.map.MapDomainBridge;
        bridge.getProjection = _getter; bridge.isCurrent = _current;
    }
    public static function ready():Boolean { return _ready; }
    public static function setReady(value:Boolean):Void { _ready = value; }
    public static function deny(shopId:String, value:Boolean):Void { _denied[shopId] = value; }
    public static function projection():Object {
        var access:Object = {};
        for (var shopId:String in _root.shops) access[shopId] = _denied[shopId] !== true;
        return {shopAccess:access};
    }
}
