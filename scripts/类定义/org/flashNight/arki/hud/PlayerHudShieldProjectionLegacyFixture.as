/** Frozen 0c36a08a projection oracle; test-only, never imported by production. */
/** Detached HUD facts only. Never updates, recharges, materializes or spends resources. */
class org.flashNight.arki.hud.PlayerHudShieldProjectionLegacyFixture {
    private static function finite(value:Number):Boolean { return (value - value) == 0; }
    public static function recovery(state:String, progress:Number, remainingMs:Number, totalMs:Number):Object {
        return {state:state, progress:progress, remainingMs:remainingMs, totalMs:totalMs};
    }
    public static function read(unit:Object):Object {
        var shield:Object = unit.shield;
        var detail:Object = {strengthKind:"unavailable", strength:0, resistsBypass:false,
            recovery:recovery("unavailable", 0, 0, 0)};
        if (shield == null || typeof shield.getMaxCapacity != "function") return detail;
        var maximum:Number = Number(shield.getMaxCapacity());
        if (!finite(maximum)) return detail;
        if (!(maximum > 0)) {
            detail.strengthKind = "finite";
            detail.recovery = recovery("none", 0, 0, 0);
            return detail;
        }
        var strength:Number = Number(shield.getStrength());
        if (strength == Number.POSITIVE_INFINITY) detail.strengthKind = "unlimited";
        else if (finite(strength) && !(strength < 0)) {
            detail.strengthKind = "finite";
            detail.strength = strength;
        }
        if (typeof shield.getResistantCount == "function") detail.resistsBypass = shield.getResistantCount() > 0;
        var aggregate:Object = {count:0, full:0, manual:0, unknown:false, charging:false,
            health:false, mp:false, waiting:null, visited:0};
        visit(shield, unit.__titaniumType61, aggregate, 0);
        if (aggregate.charging) detail.recovery = recovery("charging", 1, 0, 0);
        else if (aggregate.unknown || aggregate.count == 0) detail.recovery = recovery("unavailable", 0, 0, 0);
        // An unknown layer might recover sooner; only a complete summary may advertise the next wait.
        else if (aggregate.waiting != null) detail.recovery = aggregate.waiting;
        else if (aggregate.health && aggregate.mp) detail.recovery = recovery("conditions", 0, 0, 0);
        else if (aggregate.health) detail.recovery = recovery("health", 0, 0, 0);
        else if (aggregate.mp) detail.recovery = recovery("mp", 0, 0, 0);
        else if (aggregate.full == aggregate.count) detail.recovery = recovery("full", 0, 0, 0);
        else detail.recovery = recovery("manual", 0, 0, 0);
        return detail;
    }
    private static function visit(shield:Object, external:Object, aggregate:Object, depth:Number):Void {
        if (shield == null) { aggregate.unknown = true; return; }
        if (depth > 8 || aggregate.visited > 128) { aggregate.unknown = true; return; }
        aggregate.visited++;
        if (typeof shield.isActive == "function" && !shield.isActive()) return;
        if (typeof shield.getHudRecoveryDelegate == "function") {
            var delegate:Object = shield.getHudRecoveryDelegate();
            if (delegate != null) { visit(delegate, external, aggregate, depth + 1); return; }
        }
        if (typeof shield.getShields == "function") {
            var children:Array = shield.getShields();
            if (children.length > 0) {
                for (var i:Number = 0; i < children.length; i++) {
                    if (aggregate.visited > 128) { aggregate.unknown = true; break; }
                    visit(children[i], external, aggregate, depth + 1);
                }
                return;
            }
        }
        var maximum:Number = Number(shield.getMaxCapacity());
        if (!(maximum > 0) || !finite(maximum)) return;
        aggregate.count++;
        var state:Object;
        if (external != null && typeof external.getHudRecoveryState == "function" &&
            typeof external.ownsHudShield == "function" && external.ownsHudShield(shield)) {
            state = external.getHudRecoveryState();
        } else state = readLayer(shield, maximum);
        if (state.state == "charging") aggregate.charging = true;
        else if (state.state == "waiting") {
            if (aggregate.waiting == null || state.remainingMs < aggregate.waiting.remainingMs) aggregate.waiting = state;
        } else if (state.state == "full") aggregate.full++;
        else if (state.state == "health") aggregate.health = true;
        else if (state.state == "mp") aggregate.mp = true;
        else if (state.state == "manual") aggregate.manual++;
        else aggregate.unknown = true;
    }
    private static function readLayer(shield:Object, maximum:Number):Object {
        var capacity:Number = Number(shield.getCapacity());
        var target:Number = Number(shield.getTargetCapacity());
        var rate:Number = Number(shield.getRechargeRate());
        if (!finite(capacity) || !finite(target) || !finite(rate)) return recovery("unavailable", 0, 0, 0);
        target = Math.max(0, Math.min(maximum, target));
        if (!(capacity < target)) return recovery("full", 0, 0, 0);
        if (!(rate > 0)) return recovery("manual", 0, 0, 0);
        if (typeof shield.isDelayed != "function" || typeof shield.getDelayTimer != "function") return recovery("unavailable", 0, 0, 0);
        if (!shield.isDelayed()) return recovery("charging", 1, 0, 0);
        var remain:Number = Number(shield.getDelayTimer());
        var total:Number = Number(shield.getRechargeDelay());
        var fps:Number = Number(_root.帧计时器.帧率);
        if (!finite(remain) || !finite(total) || !finite(fps) || !(total > 0) || !(fps > 0)) return recovery("unavailable", 0, 0, 0);
        remain = Math.max(0, Math.min(total, remain));
        // Quantize presentation, not the game timer. The final delayed update still precedes recharge.
        var progress:Number = Math.floor((1 - remain / total) * 100) / 100;
        return recovery("waiting", progress, Math.ceil(remain * 10 / fps) * 100, Math.ceil(total * 10 / fps) * 100);
    }
}
