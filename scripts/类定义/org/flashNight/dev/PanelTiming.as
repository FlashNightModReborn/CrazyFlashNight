/** Opt-in, bounded elapsed-time observations; no gameplay or save authority. */
class org.flashNight.dev.PanelTiming {
    public static var enabled:Boolean = false;
    private static var profileId:String = "";
    private static var records:Number = 0;

    public static function install():Void {
        _root.gameCommands["panelTimingProfile"] = function(p:Object):Void {
            org.flashNight.dev.PanelTiming.configure(p);
        };
    }
    public static function configure(p:Object):Void {
        if (p.v !== 1 || typeof p.enabled != "boolean" || typeof p.profileId != "string"
            || p.profileId.substr(0,3) != "pt:" || length(p.profileId) > 48) return;
        enabled = p.enabled;
        profileId = p.profileId;
        records = 0;
    }
    public static function start():Number {
        return enabled ? getTimer() : -1;
    }
    public static function finish(metric:String, started:Number, callId:Number):Void {
        if (!enabled || started < 0) return;
        record(metric,getTimer()-started,callId);
    }
    public static function record(metric:String, elapsed:Number, callId:Number):Void {
        if (!enabled) return;
        if (elapsed < 0 || ++records > 4096) { enabled = false; return; }
        if ((callId-callId) != 0 || callId < 0 || callId != Math.floor(callId)) callId = 0;
        _root.server.sendServerMessage("[PanelTiming] id=" + profileId + " metric=" + metric
            + " ms=" + elapsed + " call=" + callId);
    }
}
