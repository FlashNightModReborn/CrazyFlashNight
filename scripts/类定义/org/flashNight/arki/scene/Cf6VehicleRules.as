/** A07 finite encounter/clock rules. The live collision and damage adapters own authority. */
class org.flashNight.arki.scene.Cf6VehicleRules {
    private static function finite(value):Boolean {
        return typeof value == "number" && !isNaN(value) && isFinite(value) && Math.abs(value) < 1000000;
    }
    private static function whole(value, maximum:Number):Boolean {
        return finite(value) && value > 0 && !(value > maximum) && Math.floor(value) == value;
    }
    public static function create(spec:Object, owner:Object, health:Number, speedX:Number, speedZ:Number):Object {
        if (spec == null || owner == null || typeof owner != "object" || spec.fps !== 30
                || !whole(spec.roadKillThreshold,1000) || !whole(spec.roadToBossFrames,600)
                || !whole(spec.fireIntervalMs,2000) || spec.fireIntervalMs < 34 || spec.barrels !== 2
                || !whole(spec.bossLoopFrames,600) || !whole(spec.bossThrowFrame,spec.bossLoopFrames)
                || !whole(spec.bossDeathFirstFrame,1000) || !whole(spec.bossExitFrame,2000)
                || spec.bossDeathFirstFrame !== spec.bossLoopFrames+1
                || !(spec.bossExitFrame > spec.bossDeathFirstFrame)
                || !finite(spec.originalBossHp) || !(spec.originalBossHp > 0)
                || !finite(health) || !(health > 0)
                || !finite(speedX) || !(speedX > 0) || speedX > 100
                || !finite(speedZ) || !(speedZ > 0) || speedZ > 100) return null;
        return {owner:owner,phase:"road",frame:0,roadKills:0,killTarget:spec.roadKillThreshold,
            introFrames:spec.roadToBossFrames,bossLoop:spec.bossLoopFrames,throwFrame:spec.bossThrowFrame,
            deathFirst:spec.bossDeathFirstFrame,deathLast:spec.bossExitFrame,bossFrame:0,
            bossHp:spec.originalBossHp,health:health,speedX:speedX,speedZ:speedZ,
            firePeriod:spec.fireIntervalMs*30,fireCredit:0,firing:false,
            roadEvents:{},bossHits:{},playerHits:{},delivered:false};
    }
    private static function current(s:Object, owner:Object):Boolean {
        return s != null && owner === s.owner && s.phase != "cancelled" && s.phase != "defeat" && s.phase != "complete";
    }
    private static function eventKey(id):String {
        if (typeof id != "string" || id.length == 0 || id.length > 120) return "";
        return "event."+id;
    }
    /** Feed only a verified final death of this room's road actor; escaping is not a kill. */
    public static function roadDeath(s:Object, owner:Object, actorId:String):Boolean {
        if (!current(s,owner) || s.phase != "road") return false;
        var key:String=eventKey(actorId);
        if (key == "" || s.roadEvents[key] === true) return false;
        s.roadEvents[key]=true;s.roadKills++;
        if (s.roadKills == s.killTarget) {s.phase="boss-intro";s.frame=0;s.firing=false;s.fireCredit=0;}
        return true;
    }
    public static function hitBoss(s:Object, owner:Object, hitId:String, power:Number):Boolean {
        if (!current(s,owner) || s.phase != "boss" || !finite(power) || !(power > 0)) return false;
        var key:String=eventKey(hitId);
        if (key == "" || s.bossHits[key] === true) return false;
        s.bossHits[key]=true;s.bossHp=Math.max(0,s.bossHp-power);
        if (!(s.bossHp > 0)) {s.phase="boss-death";s.bossFrame=s.deathFirst-1;s.frame=0;}
        return true;
    }
    public static function hitPlayer(s:Object, owner:Object, hitId:String, power:Number):Boolean {
        if (!current(s,owner) || s.phase == "boss-intro" || !finite(power) || !(power > 0)) return false;
        var key:String=eventKey(hitId);
        if (key == "" || s.playerHits[key] === true) return false;
        s.playerHits[key]=true;s.health=Math.max(0,s.health-power);
        if (!(s.health > 0)) s.phase="defeat";
        return true;
    }
    public static function reachTail(s:Object, owner:Object, triggerReached:Boolean):Boolean {
        if (!current(s,owner) || s.phase != "tail" || !triggerReached) return false;
        s.phase="complete";return true;
    }
    /** Fixed 30 Hz simulation, not render delta catch-up. Output describes intent only. */
    public static function tick(s:Object, owner:Object, paused:Boolean, input:Object):Object {
        var result:Object={shots:0,dx:0,dz:0,bossThrow:false,cue:""};
        if (s == null) return result;
        if (owner !== s.owner) {s.phase="cancelled";result.cue="cancel";return result;}
        if (!current(s,owner) || paused) return result;
        s.frame++;
        if (s.phase == "boss-intro") {
            if (s.frame == s.introFrames) {s.phase="boss";s.frame=0;s.bossFrame=0;result.cue="spawn-boss";}
            return result;
        }
        if (s.phase == "boss") {
            s.bossFrame=s.bossFrame%s.bossLoop+1;
            result.bossThrow=s.bossFrame==s.throwFrame;
        } else if (s.phase == "boss-death") {
            s.bossFrame++;
            if (s.bossFrame == s.deathLast) {s.phase="tail";s.frame=0;result.cue="spawn-tail";}
        }
        // Invalid axes do not create movement; no Key.isDown or global key rebinding here.
        if (input != null && finite(input.x) && finite(input.z)) {
            result.dx=Math.max(-1,Math.min(1,input.x))*s.speedX;
            result.dz=Math.max(-1,Math.min(1,input.z))*s.speedZ;
        }
        if (input != null && input.fire === true) {
            if (!s.firing) {s.firing=true;s.fireCredit=0;result.shots=2;}
            else {
                // Integer numerator preserves the original 150 ms dual-gun cadence at 30 Hz.
                s.fireCredit+=1000;
                if (!(s.fireCredit < s.firePeriod)) {s.fireCredit-=s.firePeriod;result.shots=2;}
            }
        } else {s.firing=false;s.fireCredit=0;}
        return result;
    }
    public static function takeCompletion(s:Object, owner:Object):Boolean {
        if (s == null || owner !== s.owner || s.phase != "complete" || s.delivered) return false;
        s.delivered=true;return true;
    }
    public static function cancel(s:Object, owner:Object):Boolean {
        if (s == null || owner !== s.owner || s.delivered || s.phase == "cancelled") return false;
        s.phase="cancelled";return true;
    }
}
