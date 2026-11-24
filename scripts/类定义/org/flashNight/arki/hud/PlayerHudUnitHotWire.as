/** Compact numeric delta inside the existing F-frame's pi: segment.
 * Cold layouts, membership and unnegotiated sessions use the same complete JSON groups.
 */
class org.flashNight.arki.hud.PlayerHudUnitHotWire {
    public static function encode(epoch:Number, seq:Number, groups:Object, oldFocus, oldAllies):String {
        for (var key:String in groups) {
            if (!groups.hasOwnProperty(key)) continue;
            if (key != "focusTarget" && key != "allies") return null;
        }
        return encodeUnitsOnly(epoch, seq, groups.focusTarget, groups.hasOwnProperty("focusTarget"),
            groups.allies, groups.hasOwnProperty("allies"), oldFocus, oldAllies);
    }

    public static function encodeUnitsOnly(epoch:Number, seq:Number, focusGroup, hasFocus:Boolean,
            alliesGroup, hasAllies:Boolean, oldFocus, oldAllies):String {
        var parts:Array = ["~1," + epoch + "," + seq];
        if (hasFocus && (!(focusGroup instanceof Array) || !(oldFocus instanceof Array)
                || !appendRows("f", oldFocus, focusGroup, parts))) return null;
        if (hasAllies && (alliesGroup == null || oldAllies == null
                || !appendRows("a", oldAllies.rows, alliesGroup.rows, parts)
                || !appendRows("o", oldAllies.overflow, alliesGroup.overflow, parts))) return null;
        if (parts.length < 2 || parts.length > 65) return null;
        return parts.join(";");
    }

    // Profile only. Keep ordinary capture and the wire-format decision independent of diagnostics.
    public static function fallbackReason(groups:Object, oldFocus, oldAllies):String {
        var f:Boolean = groups.hasOwnProperty("focusTarget"), a:Boolean = groups.hasOwnProperty("allies");
        if (!f && !a) return "noUnit";
        var prefix:String = "unit";
        for (var key:String in groups) if (groups.hasOwnProperty(key) && key != "focusTarget" && key != "allies") prefix = "mixed";
        var stat:Object = {identity:false,cold:false,rows:0};
        if (f) inspectRows("f",oldFocus,groups.focusTarget,stat);
        if (a) {
            if (oldAllies == null || groups.allies == null) stat.identity = true;
            else {
                inspectRows("a",oldAllies.rows,groups.allies.rows,stat);
                inspectRows("o",oldAllies.overflow,groups.allies.overflow,stat);
            }
        }
        if (stat.identity) return prefix + "Identity";
        if (stat.cold) return prefix + "Cold";
        if (stat.rows > 64) return prefix + "Limit";
        if (stat.rows == 0) return prefix + "Unchanged";
        return prefix + "Numeric";
    }

    private static function inspectRows(kind:String, before, after, stat:Object):Void {
        if (!(before instanceof Array) || !(after instanceof Array)) {stat.identity = true; return;}
        if (before === after) return;
        if (before.length != after.length) {stat.identity = true; return;}
        for (var j:Number = 0; j < after.length; j++) {
            var old:Object = before[j], row:Object = after[j];
            if (row === old) continue;
            if (old == null || row == null || row.id !== old.id || row.generation !== old.generation || row.slot !== old.slot) {
                stat.identity = true; return;
            }
            if (row.name !== old.name || row.role !== old.role || row.icon !== old.icon || row.doll !== old.doll
                || row.compact !== old.compact || row["protected"] !== old["protected"]) stat.cold = true;
            if (kind == "f") {
                var hasExt:Boolean = row.flags != undefined;
                var oldExt:Boolean = old.flags != undefined;
                if (hasExt != oldExt || (hasExt && (row.shield == null || old.shield == null))) stat.cold = true;
                else if (row.hp[0] !== old.hp[0] || row.hp[1] !== old.hp[1] || row.hits !== old.hits
                        || (hasExt && (row.shield[0] !== old.shield[0] || row.shield[1] !== old.shield[1]
                            || row.poise !== old.poise || row.flags !== old.flags
                            || (row.hitSeq == undefined ? 0 : row.hitSeq) !== (old.hitSeq == undefined ? 0 : old.hitSeq))))
                    stat.rows++;
            } else if (row.hp[0] !== old.hp[0] || row.hp[1] !== old.hp[1]
                    || row.shield[0] !== old.shield[0] || row.shield[1] !== old.shield[1] || row.down !== old.down) {
                stat.rows++;
            }
        }
    }

    private static function appendRows(kind:String, before:Array, after:Array, parts:Array):Boolean {
        if (before === after) return true;
        if (!(before instanceof Array) || !(after instanceof Array) || before.length != after.length) return false;
        for (var i:Number = 0; i < after.length; i++) {
            var old:Object = before[i], row:Object = after[i];
            if (old === row) continue;
            if (row.id !== old.id || row.name !== old.name || row.role !== old.role || row.icon !== old.icon
                || row.doll !== old.doll || row.compact !== old.compact) return false;
            var hp:Array = row.hp, oldHp:Array = old.hp;
            if (kind == "f") {
                var hasExt:Boolean = row.flags != undefined;
                var oldExt:Boolean = old.flags != undefined;
                if (hasExt != oldExt) return false;
                var hits:Number = row.hits == undefined ? 0 : row.hits;
                if (!hasExt) {
                    if (hp[0] !== oldHp[0] || hp[1] !== oldHp[1] || row.hits !== old.hits)
                        parts.push("f," + i + "," + row.id + "," + hp[0] + "," + hp[1] + "," + hits);
                } else {
                    var fsh:Array = row.shield, oldFsh:Array = old.shield;
                    if (fsh == null || oldFsh == null) return false;
                    var hitSeq:Number = row.hitSeq == undefined ? 0 : row.hitSeq;
                    var oldHitSeq:Number = old.hitSeq == undefined ? 0 : old.hitSeq;
                    if (hp[0] !== oldHp[0] || hp[1] !== oldHp[1] || row.hits !== old.hits
                            || fsh[0] !== oldFsh[0] || fsh[1] !== oldFsh[1]
                            || row.poise !== old.poise || row.flags !== old.flags || hitSeq !== oldHitSeq)
                        parts.push("f," + i + "," + row.id + "," + hp[0] + "," + hp[1] + "," + hits
                            + "," + fsh[0] + "," + fsh[1] + "," + row.poise + "," + row.flags + "," + hitSeq);
                }
            } else {
                if (row.generation !== old.generation || row.slot !== old.slot || row["protected"] !== old["protected"]) return false;
                var ash:Array = row.shield, oldAsh:Array = old.shield;
                if (hp[0] !== oldHp[0] || hp[1] !== oldHp[1] || ash[0] !== oldAsh[0]
                    || ash[1] !== oldAsh[1] || row.down !== old.down)
                    parts.push(kind + "," + i + "," + row.id + "," + row.generation + "," + hp[0] + "," +
                        hp[1] + "," + ash[0] + "," + ash[1] + "," + (row.down ? "1" : "0"));
            }
            if (parts.length > 65) return false;
        }
        return true;
    }
}
