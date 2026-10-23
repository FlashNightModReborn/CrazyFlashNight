/** Prepared choreography rules. No actor writes, rewards, saves or scene jumps. */
class org.flashNight.arki.scene.Cf6TraversalRules {
    private static function finite(value):Boolean {
        return typeof value == "number" && !isNaN(value) && isFinite(value) && Math.abs(value) < 1000000;
    }
    public static function valid(spec:Object):Boolean {
        if (spec == null || spec.fps !== 30 || spec.mode != "arrive" && spec.mode != "depart"
                || !finite(spec.durationFrames) || !(spec.durationFrames > 0) || spec.durationFrames > 600
                || Math.floor(spec.durationFrames) != spec.durationFrames
                || !(spec.samples instanceof Array) || spec.samples.length != spec.durationFrames) return false;
        if (spec.actorReleaseFrame != null && (!finite(spec.actorReleaseFrame)
                || spec.mode != "arrive" || !(spec.actorReleaseFrame > 0)
                || spec.actorReleaseFrame > spec.durationFrames || Math.floor(spec.actorReleaseFrame) != spec.actorReleaseFrame)) return false;
        for (var i:Number=0; i<spec.samples.length; i++) {
            var row:Object=spec.samples[i];
            if (row == null || row.frame !== i+1 || !finite(row.x) || !finite(row.z)
                    || typeof row.visible != "boolean" || row.action != "walk" && row.action != "stand") return false;
        }
        return true;
    }
    public static function create(spec:Object, owner:Object):Object {
        if (owner == null || typeof owner != "object" || !valid(spec)) return null;
        var rows:Array=[];
        for (var i:Number=0; i<spec.samples.length; i++) {
            var row:Object=spec.samples[i];
            rows.push({frame:row.frame,x:row.x,z:row.z,visible:row.visible,action:row.action});
        }
        // Shoe-bound x offsets oscillate during a vertical walk and are not facing.
        // These prepared door/lift tracks have one dominant travel axis. Freeze
        // horizontal heading from their visible endpoints; vertical tracks retain
        // the actor's admitted heading instead of chasing per-frame shoe motion.
        var first:Object=null,last:Object=null;
        for(i=0;i<rows.length;i++) {
            if(spec.actorReleaseFrame!=null && rows[i].frame>=spec.actorReleaseFrame) break;
            if(rows[i].visible) {if(first==null) first=rows[i];last=rows[i];}
        }
        var heading:String=null;
        if(first!=null && last!=null) {
            var dx:Number=last.x-first.x,dz:Number=last.z-first.z;
            if(Math.abs(dx)>0.05 && Math.abs(dx)>Math.abs(dz)) heading=dx<0?"左":"右";
        }
        return {owner:owner,mode:spec.mode,duration:spec.durationFrames,releaseAt:spec.actorReleaseFrame,
            samples:rows,heading:heading,phase:"waiting",frame:0,actorReleased:false,delivered:false};
    }
    /** Gate is spatial and clear is authoritative. A timer alone never starts departure. */
    public static function advance(s:Object, owner:Object, paused:Boolean, cleared:Boolean, atGate:Boolean):String {
        if (s == null || s.phase == "cancelled" || s.phase == "complete") return "";
        if (owner !== s.owner) {s.phase="cancelled";return "cancel";}
        if (paused) return "";
        var cue:String="";
        if (s.phase == "waiting") {
            if (s.mode == "depart" && (!cleared || !atGate)) return "";
            s.phase="playing";cue="begin";
        }
        s.frame++;
        if (s.releaseAt != null && s.frame == s.releaseAt && !s.actorReleased) {
            s.actorReleased=true;cue="release-actor";
        }
        if (s.frame == s.duration) {s.phase="complete";return "complete";}
        return cue;
    }
    public static function sample(s:Object, owner:Object):Object {
        if (s == null || owner !== s.owner || s.actorReleased || s.phase == "cancelled"
                || !(s.frame > 0) || s.frame > s.samples.length) return null;
        var row:Object=s.samples[s.frame-1];
        // Caller cannot mutate the frozen source sample or the next frame.
        return {frame:row.frame,x:row.x,z:row.z,visible:row.visible,action:row.action};
    }
    public static function cancel(s:Object, owner:Object):Boolean {
        if (s == null || owner !== s.owner || s.phase == "cancelled" || s.delivered) return false;
        s.phase="cancelled";return true;
    }
    public static function takeCompletion(s:Object, owner:Object):Boolean {
        if (s == null || owner !== s.owner || s.phase != "complete" || s.delivered) return false;
        s.delivered=true;return true;
    }
}
