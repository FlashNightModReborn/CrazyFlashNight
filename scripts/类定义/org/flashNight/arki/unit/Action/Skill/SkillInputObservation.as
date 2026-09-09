// 独立技能观察流：不参与许可、扣费、锁存、冷却或动画控制。
class org.flashNight.arki.unit.Action.Skill.SkillInputObservation {
    public static var enabled:Boolean = false;
    private static var session:String = "";
    private static var rows:Array = [];
    private static var states:Array = [];
    private static var keys:Array = [];
    private static var sequence:Number = 0;
    private static var dropped:Number = 0;
    private static var frameCount:Number = 0;
    private static var controlCount:Number = 0;
    private static var bridgeCount:Number = 0;
    private static var sampleCount:Number = 0;
    private static var advanceCount:Number = 0;
    private static var lastFlush:Number = 0;
    private static var activeUnit:Object = null;
    private static var activeAttempt:Number = 0;
    private static var attempt:Number = 0;
    private static var watch:Object = null;
    private static var target:Object = null;
    private static var targetGeneration:Number = 0;
    private static var bridgeGeneration:Number = 0;

    public static function configure(value:String):Void {
        try {
            if (session == value) return;
            session = value;
            rows = []; states = []; keys = [];
            sequence = dropped = frameCount = controlCount = bridgeCount = sampleCount = advanceCount = 0;
            lastFlush = getTimer();
            activeUnit = null; activeAttempt = attempt = 0; watch = null; target = null; targetGeneration = 0;
            enabled = true;
            record("ready", 0, bridgeGeneration, 0, "bounded_128_v1");
        } catch (e) { enabled = false; }
    }
    public static function record(kind:String, slot:Number, a:Number, b:Number, detail:String):Void {
        if (!enabled) return;
        try {
            if (rows.length >= 128) { dropped++; return; }
            rows.push(" seq=" + (++sequence) + " timer=" + getTimer() + " event=" + kind
                + " target=" + targetGeneration + " bridge=" + bridgeGeneration + " slot=" + slot + " a=" + a + " b=" + b + " attempt=" + activeAttempt
                + " detail=" + escape(String(detail).substr(0, 160)));
        } catch (e) { dropped++; }
    }
    public static function frame():Void {
        if (typeof _root.__focusSkillObservationSession == "string" && _root.__focusSkillObservationSession != session)
            configure(String(_root.__focusSkillObservationSession));
        if (!enabled) return;
        frameCount++;
        try {
            if (watch != null) {
                if (typeof watch.man._currentframe != "number") {
                    record("animation_unavailable", watch.slot, watch.frame, -1, "attempt_" + watch.attempt);
                    watch = null;
                } else if (watch.man._currentframe != watch.frame) {
                    record("animation_advanced", watch.slot, watch.frame, Number(watch.man._currentframe), "attempt_" + watch.attempt);
                    watch = null;
                } else if (getTimer() - watch.at > 1000) {
                    record("animation_no_progress", watch.slot, watch.frame, Number(watch.man._currentframe), "attempt_" + watch.attempt);
                    watch = null;
                }
            }
            if (getTimer() - lastFlush < 1000) return;
            lastFlush = getTimer();
            record("progress", 0, frameCount, controlCount, "bridge_" + bridgeCount + "_sample_" + sampleCount + "_cd_" + advanceCount + "_dropped_" + dropped);
            record("keys", 0, 0, 0, keys.join(","));
            if (_root.server.isSocketConnected !== true || typeof _root.server.sendSkillObservation != "function") return;
            var batch:Number = Math.min(rows.length, 32);
            for (var i:Number = 0; i < batch; i++) {
                var row:String = String(rows[0]);
                try {
                    if (_root.server.sendSkillObservation("[SkillInputAS2] session=" + session + " v=1" + row) !== true) break;
                    rows.shift();
                } catch (sendError) { rows.shift(); dropped++; }
            }
        } catch (e) { dropped++; }
    }
    public static function control(unit:Object):Void {
        if (!enabled) return;
        controlCount++;
        if (target !== unit) {
            target = unit; targetGeneration++; states = [];
            record("target_changed", 0, targetGeneration, 0, unit == null ? "missing" : String(unit._name));
        }
        if (unit == null && controlCount % 30 == 1) record("target_missing", 0, controlCount, 0, "no_sample");
    }
    public static function installed():Void { bridgeGeneration++; record("bridge_installed", 0, bridgeGeneration, 0, "root_bridge"); }
    public static function bridge():Void { if (enabled) bridgeCount++; }
    public static function sample(slot:Number, key:Number, down:Boolean):Void {
        if (!enabled) return;
        sampleCount++;
        try {
            keys[slot - 1] = key;
            if (states[slot] !== down) {
                states[slot] = down;
                record("sample", slot, key, down ? 1 : 0, "edge");
            }
        } catch (e) { dropped++; }
    }
    public static function decision(slot:Number, code:Number, consumed:Boolean):Void {
        if (!enabled) return;
        // 每个槽只记录判定变化，不把持续按住变成逐帧日志。
        try {
            var index:Number = slot + 20;
            var value:Number = code * 2 + (consumed ? 1 : 0);
            if (states[index] === value) return;
            states[index] = value;
            record("decision", slot, code, consumed ? 1 : 0, "0_up_1_disabled_2_latched_3_unequipped_4_attempt_5_cd_not_ready");
        } catch (e) { dropped++; }
    }
    public static function begin(unit:Object, slot:Number, name:String):Void {
        if (!enabled) return;
        activeUnit = unit; activeAttempt = ++attempt;
        record("attempt", slot, activeAttempt, 0, name);
    }
    public static function end(slot:Number, released:Boolean, cooldown:Boolean):Void {
        if (!enabled) return;
        record("release_result", slot, released ? 1 : 0, cooldown ? 1 : 0, "result_not_animation");
        activeUnit = null; activeAttempt = 0;
    }
    public static function guard(unit:Object, code:Number):Void {
        if (enabled && unit === activeUnit) record("guard", 0, code, 0, "0_invalid_1_hp_mp_2_permission_false_3_permission_true");
    }
    public static function attached(unit:Object, man:Object, status:String):Void {
        if (!enabled || unit !== activeUnit) return;
        try {
            record("attach", 0, Number(man._currentframe), 0, status);
            if (watch != null) record("animation_watch_superseded", watch.slot, watch.attempt, activeAttempt, "progress_unknown");
            if (man != null) watch = {man:man, frame:Number(man._currentframe), at:getTimer(), attempt:activeAttempt, slot:0};
        } catch (e) { dropped++; }
    }
    public static function cooldown(key:String, generation:Number, step:Number, phase:String):Void {
        if (!enabled || key.indexOf("quick:") != 0) return;
        if (phase == "advance") { advanceCount++; if (step % 30 != 1) return; }
        record("cooldown", 0, generation, step, key + "_" + phase);
    }
}
