import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.arki.hud.FocusTargetHudService;

/** Only deployed companions, deployed pets and stage-authored battle allies enter here. */
class org.flashNight.arki.hud.PlayerHudAllyRoster {
    private static var owner:Object;
    private static var generation:Number = 0;
    private static var serial:Number = 0;
    private static var pass:Number = 0;
    private static var entries:Array = [];
    private static var cached:Object = {rows:[], overflow:[]};
    private static var installed:Boolean = false;


    private static var sampling:String = "deadline";
    private static var dirty:Boolean = true;
    private static var lastSampleMs:Number = -1;
    private static var lastPause:Boolean;
    public static var sampled:Boolean;
    public static function configure(mode:String):Void {
        if (mode != "every" && mode != "two" && mode != "four") mode = "deadline";
        if (mode != sampling) { sampling = mode; dirty = true; }
    }
    public static function currentMode():String { return sampling; }
    public static function sampleDue(mode:String, frame:Number, now:Number, previous:Number, critical:Boolean):Boolean {
        return critical || previous < 0 || now < previous || mode == "every"
            || frame % (mode == "two" ? 2 : 4) == 0 || (mode == "deadline" && now - previous >= 50);
    }
    private static function hpBand(hp, maximum):Number {
        if (!finite(hp) || !finite(maximum) || maximum <= 0) return -1;
        return hp <= 0 ? 0 : (hp < maximum * 0.30 ? 1 : 2);
    }
    /** Debug only. Read live members directly, independently of all cached HP rows. */
    public static function observeHp():Array {
        var result:Array = [], world:MovieClip = _root.gameworld;
        for (var i:Number=0; i<entries.length;i++) {
            var e:Object=entries[i], unit:MovieClip=world[e.key];
            if (typeof unit=="movieclip" && unit.__hudAllyEntry===e && !e.masked)
                result.push([e.slot,e.id,generation,unit.hp,unit.hp满血值]);
        }
        return result;
    }

    public static function clear():Void {
        dirty = true; lastSampleMs = -1;
        entries = [];
        cached = {rows:[], overflow:[]};
        owner = null;
    }
    private static function enter(world:MovieClip):Void {
        if (!installed) {
            NativeInteractionContext.onSceneTeardown(clear);
            installed = true;
        }
        var token:Object = StageReturnFlow.worldIdentity(world);
        if (owner !== token) {
            clear();
            owner = token;
            generation++;
        }
    }
    public static function onUnitInitialized(unit:MovieClip):Void {
        var role:String = unit.__hudAllyRole;
        if (role != "merc" && role != "pet" && role != "map") return;
        if (unit.是否为敌人 !== false) return;
        admit(unit, role);
    }
    private static function admit(unit:MovieClip, role:String):Object {
        var world:MovieClip = _root.gameworld;
        if (typeof world != "movieclip" || typeof unit != "movieclip" || unit._parent !== world ||
                world[unit._name] !== unit || unit._name == _root.控制目标 || unit.__unitInitializedVersion == undefined ||
                unit.__unitInitializedVersion !== unit.version) return null;
        enter(world);
        var prior:Object = unit.__hudAllyEntry;
        if (prior != null && prior.owner === owner && prior.version === unit.version) return prior;
        var entry:Object = {owner:owner, key:unit._name, version:unit.version, id:++serial, role:role,
            rank:role == "merc" ? 3 : (role == "pet" ? 2 : 1), slot:-1, portraitTick:-30};
        unit.__hudAllyEntry = entry;
        _global.ASSetPropFlags(unit, ["__hudAllyEntry"], 1, 0);
        entries.push(entry);
        dirty = true;
        return entry;
    }
    private static function noteFocus(unit:MovieClip, role:String, focusId:Number):Void {
        var entry:Object = unit.__hudAllyEntry;
        if (role == "protect" && (entry == null || entry.owner !== owner || entry.version !== unit.version)) {
            entry = admit(unit, "map");
            if (entry != null) entry.leaseOnly = true;
        }
        if (entry == null || entry.owner !== owner || entry.version !== unit.version) return;
        entry.focusPass = pass;
        entry.focusId = focusId;
        entry.protection = role == "protect";
    }
    private static function finite(x):Boolean {
        return typeof x == "number" && isFinite(x) && Math.abs(x) <= 1000000000000000;
    }
    private static function samePortrait(a:Object, b:Object):Boolean {
        if (a == null || a.icon != b.icon) return false;
        if (a.doll == null || b.doll == null) return a.doll == b.doll;
        for (var k:String in b.doll) if (a.doll[k] !== b.doll[k]) return false;
        return true;
    }
    private static function read(entry:Object, unit:MovieClip, protectedUnit:Boolean):Object {
        var hp:Number = unit.hp, maximum:Number = unit.hp满血值;
        if (!finite(hp) || !finite(maximum) || maximum <= 0) return null;
        var shield:Object = unit.shield;
        var sc:Number = 0, sm:Number = 0;
        if (typeof shield.getCapacity == "function" && typeof shield.getMaxCapacity == "function") {
            sm = Number(shield.getMaxCapacity());
            sc = Number(shield.getCapacity());
            if (!finite(sc) || !finite(sm) || sm <= 0) sc = sm = 0;
        }
        if (pass - entry.portraitTick >= 30) {
            var portrait:Object = FocusTargetHudService.extractPortrait(unit);
            if (!samePortrait(entry.portrait, portrait)) entry.portrait = portrait;
            entry.portraitTick = pass;
        }
        if (entry.label == undefined || entry.rawName !== unit.名字 || entry.rawKind !== unit.兵种) {
            entry.rawName = unit.名字; entry.rawKind = unit.兵种;
            entry.label = FocusTargetHudService.unitLabel(unit, "ally");
        }
        var name:String = entry.label;
        var old:Object = entry.row;
        if (old != null && old.slot === entry.slot && old.name === name && old.icon === entry.portrait.icon
                && old.doll === entry.portrait.doll && old.hp[0] === hp && old.hp[1] === maximum
                && old.shield[0] === sc && old.shield[1] === sm && old["protected"] === protectedUnit) return old;
        var result:Object = {slot:entry.slot, id:entry.id, generation:generation, role:entry.role, name:name,
            icon:entry.portrait.icon, doll:entry.portrait.doll, hp:[hp,maximum], shield:[sc,sm], down:hp<=0};
        result["protected"] = protectedUnit;
        entry.row = result;
        return result;
    }
    private static function sameRows(a:Array, b:Array):Boolean {
        if (a.length != b.length) return false;
        for (var i:Number = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
        return true;
    }
    /** Keep incumbents stationary. Choose the last seat of the lowest eligible tier. */
    private static function place(entry:Object, seats:Array):Void {
        var victim:Number = -1;
        for (var j:Number = 0; j < 20; j++) {
            var incumbent:Object = seats[j];
            if (incumbent == null) { seats[j] = entry; entry.slot = j; return; }
            if (incumbent.rank < entry.rank && (victim < 0 || incumbent.rank <= seats[victim].rank)) victim = j;
        }
        if (victim < 0) return;
        seats[victim].slot = -1;
        seats[victim] = entry;
        entry.slot = victim;
    }
    public static function snapshot(hero:Object, focusList):Object {
        var frame:Number = Number(_root.帧计时器.当前帧数);
        return snapshotAt(hero,focusList,isFinite(frame)?frame:pass+1,getTimer(),_root.暂停 === true,false);
    }
    public static function snapshotAt(hero:Object, focusList, frame:Number, now:Number, paused:Boolean, force:Boolean):Object {
        var world:MovieClip = _root.gameworld;
        if (typeof world != "movieclip") { if (owner != null) clear(); return cached; }
        enter(world);
        pass++;
        FocusTargetHudService.visitRosterBindings(world, noteFocus);
        var shown:Object = {};
        if (focusList instanceof Array) {
            for (var k:Number = 0; k < focusList.length; k++) shown["i"+focusList[k].id] = true;
        } else if (focusList != null) shown["i"+focusList.id] = true;

        // Legacy scripts can write HP or detach clips without sending an event.
        // Check just identity and critical edges on skipped beats. Shield accessors,
        // portrait extraction, seat assignment and immutable row reads stay on full samples.
        var critical:Boolean = dirty || force === true || paused !== lastPause;
        lastPause = paused;
        var i:Number, entry:Object, unit:MovieClip;
        for (i=0; i<entries.length; i++) {
            entry = entries[i]; unit = world[entry.key];
            var protect:Boolean = entry.focusPass === pass && entry.protection === true;
            var masked:Boolean = entry.focusPass === pass && shown["i"+entry.focusId] === true;
            if (typeof unit != "movieclip" || unit._parent !== world || unit.__hudAllyEntry !== entry
                    || unit.version !== entry.version || unit === hero || (!protect && (entry.leaseOnly || unit.是否为敌人 !== false))) {
                critical = true; continue;
            }
            var liveRole:String = unit.__hudAllyRole;
            if ((liveRole == "merc" || liveRole == "pet" || liveRole == "map") && (liveRole != entry.role || entry.leaseOnly)) {
                entry.role = liveRole; entry.rank = liveRole == "merc" ? 3 : (liveRole == "pet" ? 2 : 1);
                entry.leaseOnly = false; entry.row = null; critical = true;
            }
            var band:Number = hpBand(unit.hp, unit.hp满血值);
            if (protect !== entry.wasProtected || masked !== entry.masked || entry.band === undefined
                    || band != entry.band
                    || (paused && entry.row != null && (unit.hp !== entry.row.hp[0] || unit.hp满血值 !== entry.row.hp[1]))) critical = true;
            entry.wasProtected = protect; entry.masked = masked; entry.band = band;
        }
        if (!isFinite(frame)) frame = pass;
        sampled = sampleDue(sampling, frame, now, lastSampleMs, critical);
        if (!sampled) return cached;
        lastSampleMs = now; dirty = false;
        var seats:Array = new Array(20), pending:Array = [], held:Array = [];
        for (i = 0; i < entries.length; i++) {
            entry = entries[i];
            unit = world[entry.key];
            var isProtected:Boolean = entry.focusPass === pass && entry.protection === true;
            if (typeof unit != "movieclip" || unit._parent !== world || unit.__hudAllyEntry !== entry ||
                    unit.version !== entry.version || unit === hero || (!isProtected && (entry.leaseOnly || unit.是否为敌人 !== false))) {
                entries.splice(i--, 1);
                if (unit.__hudAllyEntry === entry) delete unit.__hudAllyEntry;
                continue;
            }
            if (entry.focusPass === pass && shown["i"+entry.focusId] === true) { entry.slot = -1; continue; }
            if (isProtected) {
                if (entry.slot >= 20) held[entry.slot-20] = entry;
                else pending.push(entry);
            } else if (entry.slot >= 0 && entry.slot < 20) seats[entry.slot] = entry;
            else { entry.slot = -1; pending.push(entry); }
        }
        for (i = 0; i < pending.length; i++) {
            entry = pending[i];
            if (entry.focusPass === pass && entry.protection) {
                var h:Number = 0;
                while (held[h] != null) h++;
                held[h] = entry; entry.slot = h+20;
            } else place(entry, seats);
        }
        var rows:Array = [], overflow:Array = [], row:Object;
        for (i = 0; i < seats.length + held.length; i++) {
            entry = i < 20 ? seats[i] : held[i-20];
            if (entry != null) {
                row = read(entry, world[entry.key], i>=20);
                if (row != null) rows.push(row);
            }
        }
        for (i = 0; i < entries.length; i++) {
            entry = entries[i];
            if (entry.slot != -1 || (entry.focusPass === pass && shown["i"+entry.focusId] === true)) continue;
            row = read(entry, world[entry.key], false);
            if (row != null) overflow.push(row);
        }
        if (!sameRows(cached.rows,rows) || !sameRows(cached.overflow,overflow)) cached = {rows:rows,overflow:overflow};
        return cached;
    }
}
