/**
 * 已显式接入的真实 NPC 实例适配。这里只执行 C# presence，不解释剧情条件。
 */
class org.flashNight.arki.map.MapWorldNpcController {
    private static var _entries:Array = [];
    private static var _permit:Object;
    private static var _permitPresence:Boolean = false;

    private static function taskName(npc:Object):String {
        return npc.任务名 != undefined && String(npc.任务名) != "" ? String(npc.任务名) : String(npc.名字);
    }
    private static function matches(binding:Object, npc:Object, originalName:String):Boolean {
        return String(binding.runtimeName) == String(npc.名字) && String(binding.taskName) == taskName(npc)
            && (String(binding.instanceName || "") == "" || String(binding.instanceName) == originalName);
    }
    /** 返回 true 表示先由桥接器接管；未绑定人物完全保留原世界逻辑。 */
    public static function intercept(npc:Object):Boolean {
        if (_permit === npc) return false;
        for (var i:Number = 0; i < _entries.length; i++) if (_entries[i].npc === npc) return true;
        var bindings:Array = org.flashNight.arki.map.MapDomainBridge.getBootstrap().worldBindings;
        var candidate:Boolean = false;
        for (i = 0; i < bindings.length; i++) if (matches(bindings[i], npc, String(npc._name))) candidate = true;
        if (!candidate) return false;
        _entries.push({npc:npc, originalName:String(npc._name), world:_root.gameworld, binding:null});
        npc._visible = false; npc.enabled = false;
        return true;
    }
    public static function hasPresencePermit(npc:Object):Boolean { return _permit === npc && _permitPresence; }
    private static function initializeNpc(entry:Object, managed:Boolean):Void {
        _permit = entry.npc; _permitPresence = managed;
        try { _root.初始化NPC(entry.npc); }
        finally { _permit = undefined; _permitPresence = false; }
    }
    public static function refresh():Void {
        if (_entries.length == 0) return;
        var projection:Object = org.flashNight.arki.map.MapDomainBridge.getProjection();
        var bindings:Array = org.flashNight.arki.map.MapDomainBridge.getBootstrap().worldBindings;
        var keep:Array = [];
        for (var i:Number = 0; i < _entries.length; i++) {
            var entry:Object = _entries[i];
            var npc:Object = entry.npc;
            if (npc._parent == undefined || entry.world !== _root.gameworld) continue;
            if (projection == undefined || String(projection.currentLocationId || "") == "") {
                npc._visible = false; npc.enabled = false; keep.push(entry); continue;
            }
            var binding:Object = entry.binding;
            if (binding == null) {
                for (var j:Number = 0; j < bindings.length; j++) {
                    if (bindings[j].locationId == projection.currentLocationId && matches(bindings[j], npc, entry.originalName)) {
                        binding = bindings[j]; break;
                    }
                }
                if (binding == null) {
                    npc._visible = true; npc.enabled = true; initializeNpc(entry, false);
                    continue;
                }
                entry.binding = binding; npc.__mapPlacementId = String(binding.placementId);
            }
            var state:Object = projection.placements[String(binding.placementId)];
            var present:Boolean = binding.locationId == projection.currentLocationId && binding.ready === true && state.present === true && state.worldReady === true;
            npc._visible = present; npc.enabled = present;
            if (present && npc.NPC初始化完毕 !== true) initializeNpc(entry, true);
            keep.push(entry);
        }
        _entries = keep;
    }
    public static function canInteract(npc:Object):Boolean {
        var placementId:String = String(npc.__mapPlacementId || "");
        if (placementId == "") return true;
        var state:Object = org.flashNight.arki.map.MapDomainBridge.getProjection().placements[placementId];
        return state.present === true && state.worldReady === true && npc._visible !== false && npc.enabled !== false;
    }
}
