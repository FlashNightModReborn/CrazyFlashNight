import org.flashNight.gesh.path.PathManager;
import org.flashNight.arki.render.EquipmentLightBridge;
import org.flashNight.arki.render.LightRegistry;

class org.flashNight.gesh.xml.LoadXml.LightProfilesLoader {
    private static var state:Number = 0;
    private static var started:Number;
    private static var request:XML;

    public static function start():Void {
        if (state != 0) return;
        state = 1; started = getTimer();
        var path:String = PathManager.resolvePath("data/combat_visuals/light_profiles.xml");
        if (path == null) { finish(null,"resource path unavailable"); return; }
        request = new XML(); request.ignoreWhite = true;
        request.onLoad = function(ok:Boolean):Void {
            if (state != 1) return;
            var registry:Object = ok ? LightRegistry.parse(request) : null;
            finish(registry, ok ? LightRegistry.error : "load failed");
        };
        request.load(path);
    }
    private static function finish(registry:Object, reason:String):Void {
        if (state != 1) return;
        state = 2;
        if (registry == null) {
            registry = LightRegistry.empty();
            trace("[LightProfiles] " + reason);
            if (_root.服务器.发布服务器消息 != undefined) _root.服务器.发布服务器消息("[LightProfiles] " + reason);
        }
        EquipmentLightBridge.installLightProfiles(registry);
        request.onLoad = null;
        request = null;
    }
    public static function settled():Boolean {
        if (state == 1 && getTimer() - started >= 5000) finish(null,"load timed out");
        return state == 2;
    }
}
