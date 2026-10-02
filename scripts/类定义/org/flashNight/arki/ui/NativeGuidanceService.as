import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.neur.Server.ServerManager;

/** AS2 owns U8 triggers and lifetime; Host owns display only. No pause/save/task writes. */
class org.flashNight.arki.ui.NativeGuidanceService {
    private static var _installed:Boolean = false;
    private static var _sequence:Number = 0;
    private static var _session:Object = null;
    private static var _pump:MovieClip;
    public static var sendOverride:Function = null;
    public static var helpAdmissionOverride:Function = null;

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        NativeInteractionContext.install();
        NativeInteractionContext.onSceneTeardown(clear);
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["nativeGuidanceAction"] = function(params:Object):Void {
            org.flashNight.arki.ui.NativeGuidanceService.handleAction(params);
        };
        _pump = _root.createEmptyMovieClip("NativeGuidanceFrameClip", _root.getNextHighestDepth());
        _pump.onEnterFrame = function():Void { org.flashNight.arki.ui.NativeGuidanceService.tick(); };
    }
    public static function guideId(filename:String):String {
        switch (filename) {
            case "引导-开始游戏": return "start";
            case "引导-地图传送": return "map";
            case "引导-战斗": return "combat";
            case "引导-奔跑": return "run";
            case "引导-拾取": return "pickup";
            case "引导-打开箱子": return "crate";
            case "引导-打开箱子2": return "crate-safe";
        }
        return null;
    }
    public static function show(filename:String):Boolean {
        install();
        var id:String = guideId(filename);
        if (id == null) return false;
        clear();
        _sequence++;
        _session = {requestId:"ng:" + _sequence, sceneId:NativeInteractionContext.getSceneId(),
            revision:0, guideId:id, frames:0, signature:null};
        tick();
        return true;
    }
    private static function key(value, fallback:String):String {
        if (typeof _root.keyshow != "function" || typeof value != "number") return fallback;
        var label:String = String(_root.keyshow(value));
        return label.length > 0 && label.length <= 24 ? label : fallback;
    }
    private static function bindings():Object {
        var attack = _root.键值设定[4][2];
        var jump = _root.键值设定[5][2];
        return {left:key(_root.左键,"A"),right:key(_root.右键,"D"),up:key(_root.上键,"W"),
            down:key(_root.下键,"S"),attack:key(attack,"J"),jump:key(jump,"K"),interact:key(_root.互动键,"E")};
    }
    public static function opacity(id:String, frames:Number, playerX:Number):Number {
        if (id == "pickup" || id == "crate" || id == "crate-safe") {
            if (isNaN(playerX)) return 0;
            var center:Number = id == "crate-safe" ? 700 : 900;
            var distance:Number = Math.abs(playerX - center);
            return distance <= 100 ? 0.75 : Math.max(0, 1 - distance * 0.0025);
        }
        if (id == "combat" || id == "run" || id == "start") return Math.min(0.7, Math.max(0, frames - 50) / 100);
        return 1;
    }
    public static function tick():Void {
        var s:Object = _session;
        if (s == null) return;
        s.frames++;
        var alpha:Number = opacity(s.guideId, s.frames, Number(_root.gameworld.玩家0._x));
        // SceneReady may trigger the map tutorial before settlement requests reach Host.
        // Keep the same request dormant until the existing AS2 authorities are idle.
        if ((s.guideId == "start" || s.guideId == "map") && !canPresentHelp(s.guideId)) alpha = 0;
        var keys:Object = bindings();
        var signature:String = alpha + "|" + keys.left + "|" + keys.right + "|" + keys.up + "|" + keys.down + "|" + keys.attack + "|" + keys.jump + "|" + keys.interact;
        if (signature === s.signature) return;
        // Each attempted snapshot receives a new revision; failed best-effort sends are retried,
        // while a matching user close always retires before the next frame.
        s.revision++;
        var payload:Object = {version:1,op:"show",requestId:s.requestId,sceneId:s.sceneId,
            revision:s.revision,guideId:s.guideId,opacity:alpha,keys:keys};
        if (send(payload)) s.signature = signature;
    }
    public static function allowsAutomaticHelp(id:String, owner:String, lane:String, reportPending:Boolean):Boolean {
        if (id != "start" && id != "map") return true;
        return owner != "stage_settlement" && owner != "scene_transition"
            && owner != "stage_start_reservation" && lane == "idle" && reportPending !== true;
    }
    private static function canPresentHelp(id:String):Boolean {
        if (helpAdmissionOverride != null) return helpAdmissionOverride() === true;
        return allowsAutomaticHelp(id,
            org.flashNight.arki.scene.StageRunSession.getObservationOwner(),
            org.flashNight.arki.item.LootContainerService.getObservationLane(),
            org.flashNight.arki.scene.StageRunSession.hasUnpresentedSettlementReport());
    }
    private static function send(payload:Object):Boolean {
        if (sendOverride != null) return sendOverride(payload) === true;
        var sm:ServerManager = ServerManager.getInstance();
        return sm != null && sm.sendTaskToNode("native_guidance", payload, null) === true;
    }
    public static function clear():Void {
        var s:Object = _session;
        _session = null;
        if (s != null) send({version:1,op:"hide",requestId:s.requestId,sceneId:s.sceneId});
    }
    public static function handleAction(params:Object):Void {
        var s:Object = _session;
        if (s == null || params == null || params.verb !== "close"
            || params.requestId !== s.requestId || params.sceneId !== s.sceneId
            || typeof params.revision != "number" || params.revision <= 0
            || Math.floor(params.revision) !== params.revision || params.revision > s.revision
            || !NativeInteractionContext.isCurrentWorld(_root.gameworld)) return;
        // A close refers to a displayed revision of this immutable request. Fading/key updates
        // may have advanced the snapshot while the same-request close was in transit.
        clear();
    }
}
