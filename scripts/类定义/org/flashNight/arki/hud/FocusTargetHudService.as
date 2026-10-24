import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.arki.unit.UnitUtil;

/**
 * Scene-owned read-only focus targets (protect / boss / combat) with portrait metadata and player combo counter.
 * Gameplay controllers own explicit protect/boss leases; combat target tracks the hero's
 * active hostile target with AOE anti-jitter and 150-frame (5s) out-of-combat expiry.
 */
class org.flashNight.arki.hud.FocusTargetHudService {
    public static var MAX_TARGETS:Number = 4;
    public static var COMBAT_TTL_FRAMES:Number = 150;
    public static var COMBAT_STICKY_FRAMES:Number = 15;
    public static var COMBO_TTL_FRAMES:Number = 75;

    private static var installed:Boolean = false;
    private static var serial:Number = 0;
    private static var binding:Object;
    private static var bindings:Array = [];
    private static var combatState:Object;
    private static var aggroState:Object;
    private static var comboState:Object;
    private static var cached:Object;
    private static var cachedList:Array;

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
    private static function cleanField(value, maxLen:Number):String {
        if (value == null || value == undefined) return "";
        var raw:String = String(value);
        var out:String = "";
        for (var i:Number = 0; i < length(raw) && length(out) < maxLen; i++) {
            var c:Number = raw.charCodeAt(i);
            if (c >= 32 && c != 127) out += raw.charAt(i);
        }
        return validLabel(out) ? out : "";
    }
    private static function extractPortrait(unit:MovieClip):Object {
        var key:String = cleanField(UnitUtil.getUnitTypeKey(unit), 128);
        var info:Object = _root.敌人属性表 != undefined ? _root.敌人属性表[key] : null;
        var fixedAppearance:Boolean = info != undefined && info.battleRecordAppearance == "fixed";
        var individual:Boolean = !fixedAppearance && (unit.hasDressup === true || key.indexOf("主角-") == 0);
        if (individual) {
            return {
                icon: "",
                doll: {
                    face: cleanField(unit.脸型, 64),
                    hair: cleanField(unit.发型, 64),
                    mask: cleanField(unit.面具, 64),
                    head: cleanField(unit.头部装备, 64),
                    body: cleanField(unit.上装装备, 64),
                    leg: cleanField(unit.下装装备, 64),
                    hand: cleanField(unit.手部装备, 64),
                    foot: cleanField(unit.脚部装备, 64),
                    neck: cleanField(unit.颈部装备, 64),
                    gender: cleanField(unit.性别, 64)
                }
            };
        }
        var icon:String = cleanField(unit.头像 != undefined ? unit.头像 : unit.icon, 128);
        if (length(icon) == 0) {
            if (info != undefined && info.displayname != undefined) icon = key;
            else if (key.indexOf("敌人-") == 0) icon = key;
            else if (length(key) > 0 && key != "未知单位" && key != String(unit._name)) icon = "敌人-" + key;
        }
        return {icon: icon, doll: null};
    }
    private static function syncBindingsWithPrimary():Void {
        if (binding == null) {
            if (bindings.length > 0) bindings.length = 0;
            cached = null;
        } else if (bindings.length == 0) {
            bindings.push(binding);
        }
    }
    private static function currentFrame():Number {
        var f:Number = _root.帧计时器 != undefined ? Number(_root.帧计时器.当前帧数) : NaN;
        if ((f - f) == 0 && f >= 0) return Math.floor(f);
        return Math.floor(getTimer() * 30 / 1000);
    }
    private static function ensureCombatToken(unit:MovieClip):Object {
        var token:Object = unit.__focusHudCombatIdentity;
        if (typeof token != "object" || token == null) {
            token = {};
            unit.__focusHudCombatIdentity = token;
            _global.ASSetPropFlags(unit, ["__focusHudCombatIdentity"], 1, 0);
        }
        return token;
    }
    private static function isHostileToHero(hero:MovieClip, target:MovieClip):Boolean {
        if (target == null || target === hero || target.element) return false;
        if (hero != null && hero.是否为敌人 === true) return target.是否为敌人 !== true;
        return target.是否为敌人 !== false;
    }
    private static function unitLabel(unit:MovieClip, role:String):String {
        var label:String = unit.名字 == undefined ? "" : String(unit.名字);
        if (!validLabel(label)) label = unit.兵种 == undefined ? "" : String(unit.兵种);
        if (!validLabel(label)) label = role == "boss" ? "Boss" : (role == "protect" ? "保护目标" : "交战目标");
        return label;
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
        syncBindingsWithPrimary();
        if (bindings.length > 0 && bindings[0].worldIdentity !== worldIdentity) {
            bindings.length = 0;
            combatState = null;
            aggroState = null;
            comboState = null;
        }
        var lease:Object = {};
        var entry:Object = {
            lease: lease,
            worldIdentity: worldIdentity,
            name: unit._name,
            identityKey: identityKey,
            unitIdentity: unitIdentity,
            role: role,
            label: label,
            id: ++serial,
            portrait: extractPortrait(unit),
            cached: null,
            cachedRich: null
        };
        var replaced:Boolean = false;
        for (var i:Number = 0; i < bindings.length; i++) {
            if (bindings[i].name === unit._name) {
                bindings[i] = entry;
                replaced = true;
                break;
            }
        }
        if (!replaced) bindings.push(entry);
        binding = bindings[0];
        cached = null;
        cachedList = null;
        return lease;
    }

    public static function clear(lease:Object):Boolean {
        syncBindingsWithPrimary();
        if (lease == null || bindings.length == 0) return false;
        for (var i:Number = 0; i < bindings.length; i++) {
            if (bindings[i].lease === lease) {
                bindings.splice(i, 1);
                binding = bindings.length > 0 ? bindings[0] : null;
                cached = binding != null ? binding.cached : null;
                cachedList = null;
                return true;
            }
        }
        return false;
    }

    /** Record a direct hit dealt by the controlled hero onto a hostile unit. */
    public static function recordPlayerHit(shooter:MovieClip, target:MovieClip, damageResult:Object):Void {
        if (shooter == null || target == null || shooter._name !== _root.控制目标 || target === shooter) return;
        var world:MovieClip = _root.gameworld;
        if (typeof world != "movieclip" || shooter._parent !== world || target._parent !== world
                || world[target._name] !== target || !isHostileToHero(shooter, target)) return;
        var worldIdentity:Object = StageReturnFlow.worldIdentity(world);
        if (typeof worldIdentity != "object" || worldIdentity == null) return;
        var token:Object = ensureCombatToken(target);
        if (!finite(target.hp) || !finite(target.hp满血值) || !(target.hp满血值 > 0)) return;
        install();
        var frame:Number = currentFrame();
        var hitSegments:Number = 1;
        if (damageResult != null) {
            var scatterUsed:Number = Number(damageResult.actualScatterUsed);
            if ((scatterUsed - scatterUsed) == 0 && scatterUsed > 1) {
                var missRaw:Number = Number(damageResult.scatterMissCount);
                var missCount:Number = (damageResult.scatterModelEnabled === true && (missRaw - missRaw) == 0 && missRaw > 0)
                    ? missRaw : 0;
                hitSegments = Math.floor(scatterUsed - missCount);
                if (hitSegments < 1) hitSegments = 1;
            }
        }
        if (comboState == null || comboState.worldIdentity !== worldIdentity
                || (frame - comboState.lastFrame) < 0 || (frame - comboState.lastFrame) > COMBO_TTL_FRAMES) {
            comboState = {
                worldIdentity: worldIdentity,
                count: hitSegments,
                lastFrame: frame,
                targetName: target._name
            };
        } else {
            comboState.count += hitSegments;
            if (comboState.count > 999999) comboState.count = 999999;
            comboState.lastFrame = frame;
            comboState.targetName = target._name;
        }
        cachedList = null;

        if (!(target.hp > 0)) {
            if (combatState != null && combatState.worldIdentity === worldIdentity
                    && combatState.name === target._name && combatState.unitIdentity === token) {
                combatState = null;
            }
            return;
        }
        if (combatState != null && combatState.worldIdentity === worldIdentity) {
            if (combatState.name === target._name && combatState.unitIdentity === token) {
                combatState.lastFrame = frame;
                return;
            }
            var curUnit:MovieClip = world[combatState.name];
            var age:Number = frame - combatState.lastFrame;
            if (typeof curUnit == "movieclip" && curUnit._parent === world
                    && curUnit.__focusHudCombatIdentity === combatState.unitIdentity
                    && finite(curUnit.hp) && curUnit.hp > 0 && finite(curUnit.hp满血值) && curUnit.hp满血值 > 0
                    && age >= 0 && age <= COMBAT_STICKY_FRAMES
                    && Number(target.hp满血值) < Number(curUnit.hp满血值)) {
                return;
            }
        }
        combatState = {
            worldIdentity: worldIdentity,
            name: target._name,
            unitIdentity: token,
            role: "combat",
            label: unitLabel(target, "combat"),
            id: ++serial,
            lastFrame: frame,
            portrait: extractPortrait(target),
            cachedRich: null
        };
    }

    /** Record an aggro/lock-on change on the controlled hero (`hero.攻击目标`). */
    public static function recordPlayerAggro(sender:MovieClip, target:MovieClip):Void {
        if (sender == null || target == null || sender._name !== _root.控制目标 || target === sender) return;
        var world:MovieClip = _root.gameworld;
        if (typeof world != "movieclip" || sender._parent !== world || target._parent !== world
                || world[target._name] !== target || !isHostileToHero(sender, target)
                || !finite(target.hp) || !(target.hp > 0)
                || !finite(target.hp满血值) || !(target.hp满血值 > 0)) return;
        var worldIdentity:Object = StageReturnFlow.worldIdentity(world);
        if (typeof worldIdentity != "object" || worldIdentity == null) return;
        install();
        var token:Object = ensureCombatToken(target);
        var frame:Number = currentFrame();
        if (aggroState != null && aggroState.worldIdentity === worldIdentity
                && aggroState.name === target._name && aggroState.unitIdentity === token) {
            aggroState.lastFrame = frame;
            return;
        }
        aggroState = {
            worldIdentity: worldIdentity,
            name: target._name,
            unitIdentity: token,
            role: "combat",
            label: unitLabel(target, "combat"),
            id: ++serial,
            lastFrame: frame,
            portrait: extractPortrait(target),
            cachedRich: null
        };
        cachedList = null;
    }

    public static function clearPlayerAggro(sender:MovieClip):Void {
        if (sender == null || sender._name !== _root.控制目标) return;
        aggroState = null;
        cachedList = null;
    }

    private static function clearScene():Void {
        binding = null;
        bindings.length = 0;
        combatState = null;
        aggroState = null;
        comboState = null;
        cached = null;
        cachedList = null;
    }

    /** Resolve by captured name + two ordinary tokens, never a retained MovieClip reference. */
    public static function snapshot():Object {
        syncBindingsWithPrimary();
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
        if (!finite(hp) || !finite(maximum) || !(maximum > 0)) { cached = null; state.cached = null; return null; }
        if (cached != null && cached.id === state.id && cached.hp[0] === hp && cached.hp[1] === maximum) return cached;
        cached = {id:state.id, role:state.role, name:state.label, hp:[hp, maximum]};
        state.cached = cached;
        return cached;
    }

    private static function buildRichSnapshot(state:Object, hp:Number, maximum:Number, hits:Number):Object {
        var effectiveHits:Number = (hits > 0) ? hits : 0;
        var rich:Object = state.cachedRich;
        var prevHits:Number = (rich != null && rich.hits != undefined) ? rich.hits : 0;
        if (rich != null && rich.hp[0] === hp && rich.hp[1] === maximum && prevHits === effectiveHits) return rich;
        rich = {id:state.id, role:state.role, name:state.label, hp:[hp, maximum]};
        var p:Object = state.portrait;
        if (p != null) {
            if (length(p.icon) > 0) rich.icon = p.icon;
            if (p.doll != null) rich.doll = p.doll;
        }
        if (effectiveHits > 0) rich.hits = effectiveHits;
        state.cachedRich = rich;
        return rich;
    }

    private static function resolveCombatState(state:Object, world:MovieClip, worldIdentity:Object, frame:Number):Object {
        if (state == null) return null;
        if (state.worldIdentity !== worldIdentity) return null;
        var age:Number = frame - state.lastFrame;
        if (age < 0 || age > COMBAT_TTL_FRAMES) return null;
        var unit:MovieClip = world[state.name];
        if (typeof unit != "movieclip" || unit._parent !== world
                || unit.__focusHudCombatIdentity !== state.unitIdentity) return null;
        var hp = unit.hp;
        var maximum = unit.hp满血值;
        if (!finite(hp) || !(hp > 0) || !finite(maximum) || !(maximum > 0)) return null;
        if (state.portrait == null) state.portrait = extractPortrait(unit);
        return {state: state, hp: hp, maximum: maximum};
    }

    private static function syncHeroAggroProperty(world:MovieClip, worldIdentity:Object, hero:Object, frame:Number):Void {
        if (hero == null || typeof hero != "movieclip" || hero._parent !== world) return;
        var aggroName:String = typeof hero.攻击目标 == "string" ? hero.攻击目标 : "";
        if (length(aggroName) == 0 || aggroName == "无") {
            aggroState = null;
            return;
        }
        var target:MovieClip = world[aggroName];
        if (typeof target != "movieclip" || target._parent !== world || world[target._name] !== target
                || !isHostileToHero(MovieClip(hero), target)
                || !finite(target.hp) || !(target.hp > 0)
                || !finite(target.hp满血值) || !(target.hp满血值 > 0)) {
            if (aggroState != null && aggroState.name === aggroName) aggroState = null;
            return;
        }
        var token:Object = ensureCombatToken(target);
        if (aggroState == null || aggroState.worldIdentity !== worldIdentity
                || aggroState.name !== target._name || aggroState.unitIdentity !== token) {
            aggroState = {
                worldIdentity: worldIdentity,
                name: target._name,
                unitIdentity: token,
                role: "combat",
                label: unitLabel(target, "combat"),
                id: ++serial,
                lastFrame: frame,
                portrait: extractPortrait(target),
                cachedRich: null
            };
        }
    }

    /**
     * Multi-target projection ordered by protect > boss > combat (capped at MAX_TARGETS = 4).
     * Reuses the returned Array reference when all items are unchanged.
     */
    public static function snapshotList(hero:Object):Array {
        syncBindingsWithPrimary();
        var world:MovieClip = _root.gameworld;
        if (typeof world != "movieclip") {
            clearScene();
            return null;
        }
        var worldIdentity:Object = world.__stageReturnWorldIdentity;
        if (worldIdentity == null && (bindings.length > 0 || combatState != null || aggroState != null || hero != null)) {
            worldIdentity = StageReturnFlow.worldIdentity(world);
        }
        if (typeof worldIdentity != "object" || worldIdentity == null) {
            clearScene();
            return null;
        }
        var frame:Number = currentFrame();
        var activeCombo:Number = 0;
        var comboTargetName:String = "";
        if (comboState != null) {
            var comboAge:Number = frame - comboState.lastFrame;
            if (comboState.worldIdentity === worldIdentity && comboAge >= 0 && comboAge <= COMBO_TTL_FRAMES && comboState.count > 0) {
                activeCombo = comboState.count;
                comboTargetName = comboState.targetName;
            } else {
                comboState = null;
            }
        }

        var protectCand:Array = [];
        var bossCand:Array = [];
        var boundNames:Object = {};
        for (var i:Number = 0; i < bindings.length; i++) {
            var state:Object = bindings[i];
            var unit:MovieClip = world[state.name];
            if (state.worldIdentity !== worldIdentity || typeof unit != "movieclip"
                    || unit._parent !== world || unit[state.identityKey] !== state.unitIdentity) {
                bindings.splice(i, 1);
                i--;
                continue;
            }
            boundNames[state.name] = true;
            var hp = unit.hp;
            var maximum = unit.hp满血值;
            if (!finite(hp) || !finite(maximum) || !(maximum > 0)) {
                state.cached = null;
                state.cachedRich = null;
                continue;
            }
            if (state.portrait == null) state.portrait = extractPortrait(unit);
            var item:Object = {state: state, hp: hp, maximum: maximum};
            if (state.role == "protect") protectCand.push(item);
            else bossCand.push(item);
        }
        binding = bindings.length > 0 ? bindings[0] : null;
        if (binding == null) cached = null;

        var candidates:Array = [];
        var j:Number;
        for (j = 0; j < protectCand.length && candidates.length < MAX_TARGETS; j++) candidates.push(protectCand[j]);
        for (j = 0; j < bossCand.length && candidates.length < MAX_TARGETS; j++) candidates.push(bossCand[j]);

        if (candidates.length < MAX_TARGETS) {
            var combatResolved:Object = resolveCombatState(combatState, world, worldIdentity, frame);
            var combatName:String = combatResolved != null ? combatState.name : "";
            if (combatResolved == null) {
                combatState = null;
                syncHeroAggroProperty(world, worldIdentity, hero, frame);
                combatResolved = resolveCombatState(aggroState, world, worldIdentity, frame);
                combatName = combatResolved != null ? aggroState.name : "";
            }
            if (combatResolved != null && boundNames[combatName] !== true) {
                candidates.push(combatResolved);
            }
        }

        if (candidates.length == 0) {
            cachedList = null;
            return null;
        }

        var comboRecipientIndex:Number = -1;
        if (activeCombo > 0) {
            for (j = 0; j < candidates.length; j++) {
                if (candidates[j].state.role != "protect" && candidates[j].state.name === comboTargetName) {
                    comboRecipientIndex = j;
                    break;
                }
            }
            if (comboRecipientIndex < 0) {
                for (j = candidates.length - 1; j >= 0; j--) {
                    if (candidates[j].state.role == "combat") {
                        comboRecipientIndex = j;
                        break;
                    }
                }
            }
            if (comboRecipientIndex < 0) {
                for (j = 0; j < candidates.length; j++) {
                    if (candidates[j].state.role == "boss") {
                        comboRecipientIndex = j;
                        break;
                    }
                }
            }
        }

        var list:Array = [];
        for (j = 0; j < candidates.length; j++) {
            var c:Object = candidates[j];
            var rowHits:Number = (j === comboRecipientIndex) ? activeCombo : 0;
            list.push(buildRichSnapshot(c.state, c.hp, c.maximum, rowHits));
        }

        if (cachedList != null && cachedList.length == list.length) {
            var same:Boolean = true;
            for (var k:Number = 0; k < list.length; k++) {
                if (cachedList[k] !== list[k]) { same = false; break; }
            }
            if (same) return cachedList;
        }
        cachedList = list;
        return cachedList;
    }
}
