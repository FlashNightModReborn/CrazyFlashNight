import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.interaction.NativeInteractionContext;

/** One scene-owned, read-only target. Gameplay controllers own selection and life. */
class org.flashNight.arki.hud.FocusTargetHudService {
    private static var installed:Boolean = false;
    private static var serial:Number = 0;
    private static var binding:Object;
    private static var cached:Object;

    public static function install():Void {
        if (installed) return;
        installed = true;
        NativeInteractionContext.onSceneTeardown(clearScene);
    }
    private static function finite(value):Boolean {
        // Same numeric envelope as PlayerHudState.Number; never poison the whole HUD packet.
        return typeof value == "number" && (value - value) == 0
            && !(value > 1000000000000000) && !(value < -1000000000000000);
    }
    private static function validLabel(value:String):Boolean {
        var size:Number = length(value);
        if (size == 0 || size > 192) return false;
        for (var i:Number = 0; i < size; i++) {
            var code:Number = value.charCodeAt(i);
            if (code == 0) return false;
            if (code > 55295 && code < 56320) {
                if (!(++i < size)) return false;
                code = value.charCodeAt(i);
                if (!(code > 56319 && code < 57344)) return false;
            } else if (code > 56319 && code < 57344) return false;
        }
        return true;
    }
    /** Caller must capture the ordinary identity marker before any delayed work. */
    public static function bind(world:MovieClip, worldIdentity:Object, unit:MovieClip,
            identityKey:String, unitIdentity:Object, role:String, label:String):Object {
        if (typeof world != "movieclip" || world !== _root.gameworld
                || typeof worldIdentity != "object" || worldIdentity == null
                || worldIdentity !== StageReturnFlow.worldIdentity(world)
                || typeof unit != "movieclip" || unit._parent !== world
                || world[unit._name] !== unit || typeof identityKey != "string"
                || length(identityKey) == 0 || length(identityKey) > 96
                || typeof unitIdentity != "object" || unitIdentity == null
                || unit[identityKey] !== unitIdentity || (role != "boss" && role != "protect")
                || typeof label != "string" || !finite(unit.hp)
                || !finite(unit.hp满血值) || !(unit.hp满血值 > 0)) return null;
        if (length(label) == 0) label = unit.名字 == undefined ? "" : String(unit.名字);
        if (length(label) == 0) label = role == "boss" ? "Boss" : "保护目标";
        // Reject unbounded author labels instead of splitting a UTF-16 surrogate pair.
        if (!validLabel(label)) return null;
        install();
        var lease:Object = {};
        binding = {lease:lease, worldIdentity:worldIdentity, name:unit._name,
            identityKey:identityKey, unitIdentity:unitIdentity, role:role, label:label, id:++serial};
        cached = null;
        return lease;
    }
    public static function clear(lease:Object):Boolean {
        if (binding == null || lease == null || binding.lease !== lease) return false;
        clearScene();
        return true;
    }
    private static function clearScene():Void { binding = null; cached = null; }

    /** Resolve by captured name + two ordinary tokens, never a retained MovieClip reference. */
    public static function snapshot():Object {
        var state:Object = binding;
        if (state == null) return null;
        var world:MovieClip = _root.gameworld;
        var unit:MovieClip = world[state.name];
        if (typeof world != "movieclip" || world.__stageReturnWorldIdentity !== state.worldIdentity
                || typeof unit != "movieclip" || unit._parent !== world
                || unit[state.identityKey] !== state.unitIdentity) {
            clearScene();
            return null;
        }
        var hp = unit.hp;
        var maximum = unit.hp满血值;
        // Temporary unavailable facts hide the bar; they never become fake zero/full health.
        if (!finite(hp) || !finite(maximum) || !(maximum > 0)) { cached = null; return null; }
        if (cached != null && cached.hp[0] === hp && cached.hp[1] === maximum) return cached;
        cached = {id:state.id, role:state.role, name:state.label, hp:[hp, maximum]};
        return cached;
    }
}
