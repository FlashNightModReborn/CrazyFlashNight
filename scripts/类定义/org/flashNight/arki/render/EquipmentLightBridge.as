// AS2 owns sources, actor aggregation and admission; native owns only illumination.
import org.flashNight.arki.unit.UnitUtil;

class org.flashNight.arki.render.EquipmentLightBridge {
    private static var entries:Array = [];
    private static var candidates:Array = [];
    private static var actors:Array = [];
    private static var selected:Array = [];
    private static var previous:Array = [];
    private static var viewport:Object = {};
    private static var nextId:Number = 0;
    private static var scene:Number = 0;
    private static var serial:Number = 0;
    private static var checking:Boolean = false;
    private static var nativeEnabled:Boolean = false;
    private static var radialEnabled:Boolean = false;
    private static var budgetTick:Number = 0;
    private static var sourceCount:Number = 0;
    private static var mergedCount:Number = 0;
    private static var droppedCount:Number = 0;
    private static var profile:Object = null;
    // Ordinary muzzle preset (local_lights.v1.json / 枪火), not a new lamp.
    private static var radialPeak:Number = 1.5;
    private static var projectiles:Array = [];
    private static var bulletProfiles:Object = null;
    private static var bulletPoint:Object = {x:0, y:0};

    // Focused TestLoader instrumentation only; normal snapshots read a null gate.
    public static function profilePayloadForTests(enabled:Boolean):Object {
        var previousProfile:Object = profile;
        profile = enabled ? {calls:0,validation:0,collection:0,aggregation:0,admission:0,serialization:0} : null;
        return previousProfile;
    }

    public static function configure(caps:Object):Void {
        nativeEnabled = caps["native"] === true && caps.equipmentLights === 2;
        radialEnabled = nativeEnabled && caps.equipmentRadialLights === 1;
    }
    public static function resetScene():Void {
        // Worn body contributions have no per-frame lifecycle task. Preserve
        // still-valid owners across a transport reset; a new world/actor token
        // invalidates them normally. Only the native projections are reset.
        var retained:Array = entries; entries = [];
        candidates.length = 0; actors.length = 0;
        selected.length = 0; previous.length = 0; projectiles.length = 0; scene++;
        var now:Number = Number(_root.帧计时器.当前帧数);
        budgetTick = isFinite(now) ? now : 0;
        sourceCount = mergedCount = droppedCount = 0;
        for (var i:Number = 0; i < retained.length; i++) {
            var entry:Object = retained[i];
            if (entry.kind == 0 && entry.role == "body" && valid(entry)) {
                entry.scene = -1; entry.sampled = true; ensureEntry(entry);
            }
        }
    }
    public static function disconnect():Void { nativeEnabled = radialEnabled = false; resetScene(); }
    private static function numberOr(value, fallback:Number):Number { return value == undefined ? fallback : Number(value); }

    public static function bind(ref:Object, kind:Number, param:Object):Boolean {
        release(ref);
        var actor:MovieClip = ref.自机;
        var world:MovieClip = _root.gameworld;
        if (!actor._parent || !world._parent || !actor[ref.装备类型]) return false;
        if (!actor.__equipmentLightIdentity) actor.__equipmentLightIdentity = {};
        if (!world.__equipmentLightIdentity) world.__equipmentLightIdentity = {};
        var radial:Boolean = kind == 0;
        var role:String = radial ? String(param.group) : "directional";
        var extent:Number = radial ? numberOr(param.radius, 90) : numberOr(param.length, kind == 1 ? 1000 : 750);
        var width:Number = radial ? 0 : numberOr(param.halfWidth, kind == 1 ? 260 : 28);
        var energy:Number = numberOr(param.energy, radial ? 0.45 : (kind == 1 ? 1.45 : 0.85));
        var color:Number = numberOr(param.color, kind == 2 ? 16719648 : 16773584);
        var lightColor:Number = numberOr(param.lightColor, kind == 2 ? 16737872 : color);
        var nearRadius:Number = numberOr(param.nearRadius, kind == 1 ? 140 : 0);
        var nearEnergy:Number = numberOr(param.nearEnergy, kind == 1 ? 1.15 : 0);
        if ((kind != 0 && kind != 1 && kind != 2) || !isFinite(extent + width + energy + color + lightColor + nearRadius + nearEnergy)
            || extent < 1 || extent > (radial ? 320 : 1024) || (!radial && (width < 0.5 || width > 512))
            || energy < 0 || energy > 2 || color < 0 || color > 16777215
            || lightColor < 0 || lightColor > 16777215 || nearRadius < 0 || nearRadius > 320
            || nearEnergy < 0 || nearEnergy > 2 || ((nearRadius == 0) != (nearEnergy == 0))
            || (kind != 1 && nearRadius != 0) || (radial && role != "body" && role != "blade")) return false;
        ref.equipmentLight = {owner:ref, actor:actor, equipment:actor[ref.装备类型],
            actorIdentity:actor.__equipmentLightIdentity, worldIdentity:world.__equipmentLightIdentity,
            version:actor.version, slot:ref.装备类型, mods:modSignature(actor[ref.装备类型]), modNames:copyMods(actor[ref.装备类型]),
            kind:kind, role:role, channel:param.channel != undefined ? String(param.channel) : "primary",
            priority:ref.来源插件 != undefined ? 1 : 2, length:extent, width:width, energy:energy,
            beamColor:color, baseColor:lightColor, color:lightColor,
            r:((lightColor >> 16) & 255) / 255, g:((lightColor >> 8) & 255) / 255, b:(lightColor & 255) / 255,
            nearRadius:nearRadius, nearEnergy:nearEnergy, near:{x:0,y:0},
            origin:{x:0,y:0}, forward:{x:0,y:0}, active:true, sampled:false, scene:-1,
            trailTick:-10000, dx:0, dy:0, strength:0, checked:-1};
        if (radial) {
            // A neutral component reveals material detail while retaining hue.
            var light:Object = ref.equipmentLight;
            light.r = 0.2 + light.r * 0.8; light.g = 0.2 + light.g * 0.8; light.b = 0.2 + light.b * 0.8;
        }
        if (radial && role == "body") {
            ref.equipmentLight.strength = 1; ref.equipmentLight.sampled = true;
            return ensureEntry(ref.equipmentLight);
        }
        return true;
    }

    public static function modSignature(equipment:Object):String {
        var mods:Array = equipment.value.mods;
        if (!(mods instanceof Array)) return "";
        var signature:String = "";
        for (var i:Number = 0; i < mods.length; i++) {
            var name:String = String(mods[i]); signature += length(name) + ":" + name;
        }
        return signature;
    }
    public static function copyMods(equipment:Object):Array {
        var mods:Array = equipment.value.mods, names:Array = [];
        if (mods instanceof Array) for (var i:Number = 0; i < mods.length; i++) names.push(String(mods[i]));
        return names;
    }
    public static function matchesMods(equipment:Object,names:Array):Boolean {
        var mods:Array = equipment.value.mods;
        if (!(mods instanceof Array)) return names.length == 0;
        if (mods.length != names.length) return false;
        for (var i:Number = 0; i < names.length; i++) {
            if (mods[i] !== names[i] && String(mods[i]) !== names[i]) return false;
        }
        return true;
    }
    private static function valid(entry:Object):Boolean {
        if (!entry) return false;
        var snapshot:Boolean = checking;
        var currentSerial:Number = serial;
        if (snapshot && entry.checked == currentSerial) return entry.validated;
        var actor:MovieClip = entry.actor;
        var context:Object = entry.context;
        var identity:Boolean, version:Number;
        if (snapshot && context) {
            // AVM1 resolves MovieClip properties through the display path. Read
            // the common actor/world gates once for all five worn components.
            if (context.checked != currentSerial) {
                var world:MovieClip = _root.gameworld;
                context.checked = currentSerial;
                context.validated = actor._parent && world._parent
                    && actor.__equipmentLightIdentity === context.actorIdentity
                    && world.__equipmentLightIdentity === context.worldIdentity;
                context.version = actor.version; context.alive = actor.hp > 0;
                context.visible = visible(actor); context.mode = actor.攻击模式;
                context.bladeHeld = !!actor.man.兵器使用标签 || actor.状态 == "兵器攻击";
                context.bladeChecked = -1;
            }
            identity = context.validated; version = context.version;
        } else {
            identity = actor._parent && _root.gameworld._parent
                && actor.__equipmentLightIdentity === entry.actorIdentity
                && _root.gameworld.__equipmentLightIdentity === entry.worldIdentity;
            version = actor.version;
        }
        var result:Boolean = entry.active && identity && version === entry.version && actor[entry.slot] === entry.equipment;
        if (result) {
            // Empty mod lists dominate armor. Still compare every nonempty name:
            // an in-place, same-length edit must invalidate even in the same tick.
            var names:Array = entry.modNames, mods:Array = entry.equipment.value.mods;
            var count:Number = names.length;
            result = (mods instanceof Array) ? mods.length == count : count == 0;
            if (result) for (var i:Number = 0; i < count; i++) {
                if (mods[i] !== names[i] && String(mods[i]) !== names[i]) { result = false; break; }
            }
        }
        if (snapshot) { entry.checked = currentSerial; entry.validated = result; }
        return result;
    }
    public static function isValid(ref:Object):Boolean { return valid(ref.equipmentLight); }
    private static function drawn(entry:Object):Boolean {
        var actor:MovieClip = entry.actor;
        var context:Object = checking ? entry.context : null;
        if (context ? (!context.alive || !context.visible) : (!(actor.hp > 0) || !actor._visible)) return false;
        if (entry.kind == 0) {
            if (entry.role == "body") return true;
            if (context && context.bladeChecked == serial) return context.bladeVisible;
            var node:MovieClip = actor[entry.slot + "_引用"];
            var shown:Boolean = !!node._parent;
            while (node && node !== actor) {
                if (!node._visible) { shown = false; break; }
                node = node._parent;
            }
            shown = shown && node === actor && (context ? context.bladeHeld : (!!actor.man.兵器使用标签 || actor.状态 == "兵器攻击"));
            if (context) { context.bladeChecked = serial; context.bladeVisible = shown; }
            return shown;
        }
        var mode:String = context ? context.mode : actor.攻击模式;
        if (entry.slot == "长枪") return mode == "长枪";
        return (entry.slot == "手枪" || entry.slot == "手枪2")
            && (mode == "手枪" || mode == "手枪2" || mode == "双枪");
    }
    public static function isDrawn(ref:Object):Boolean { return valid(ref.equipmentLight) && drawn(ref.equipmentLight); }
    private static function visible(node:MovieClip):Boolean {
        while (node && node !== _root.gameworld) {
            if (!node._visible) return false;
            node = node._parent;
        }
        return node === _root.gameworld && node._visible;
    }
    private static function detach(entry:Object):Void {
        var peers:Array = entry.peers;
        if (peers) for (var i:Number = peers.length - 1; i > -1; i--) {
            if (peers[i] === entry) { peers[i] = peers[peers.length - 1]; peers.pop(); }
        }
        entry.peers = null;
        var group:Object = entry.lightGroup;
        if (group) {
            var members:Array = group.members;
            for (i = members.length - 1; i > -1; i--) {
                if (members[i] === entry) { members[i] = members[members.length-1]; members.pop(); }
            }
            group.dirty = true; entry.lightGroup = null;
        }
    }
    private static function ensureEntry(entry:Object):Boolean {
        if (entry.scene === scene) return true;
        for (var i:Number = entries.length - 1; i > -1; i--) {
            if (!valid(entries[i])) { entries[i].active = false; detach(entries[i]); entries[i] = entries[entries.length - 1]; entries.pop(); }
        }
        if (nextId > 999999990) return false;
        // Raw contributors have a separate safety ceiling from the 16 GPU lamps.
        // Even at that ceiling a later player must not be starved by NPC sources.
        if (entries.length >= 256) {
            if (entry.actor._name !== _root.控制目标) return false;
            var victim:Number = -1;
            for (i = 0; i < entries.length; i++) {
                if (entries[i].actor._name === _root.控制目标) continue;
                victim = i;
                if (entries[i].kind == 0) break;
            }
            if (victim < 0) return false;
            var retired:Object = entries[victim];
            retired.sampled = false; retired.scene = -1; detach(retired);
            entries[victim] = entries[entries.length-1]; entries.pop();
        }
        var actor:MovieClip = entry.actor;
        var context:Object = actor.__equipmentLightContext;
        if (!context || context.actorIdentity !== entry.actorIdentity || context.worldIdentity !== entry.worldIdentity || context.scene != scene) {
            context = {actor:actor, actorIdentity:entry.actorIdentity, worldIdentity:entry.worldIdentity,
                scene:scene, peers:{}, groups:{}, build:-1};
            actor.__equipmentLightContext = context;
        }
        detach(entry);
        var key:String = "$" + entry.slot + ":" + entry.kind + ":" + entry.role + ":" + entry.channel;
        var peers:Array = context.peers[key];
        if (!peers) { peers = []; context.peers[key] = peers; }
        peers.push(entry); entry.peers = peers; entry.context = context;
        entry.id = ++nextId; entry.scene = scene;
        if (entry.kind == 0) {
            var group:Object = context.groups[entry.role];
            if (!group) {
                group = {id:++nextId, actor:actor, context:context, kind:0, role:entry.role,
                    width:0, dx:0, dy:0, strength:1, nearRadius:0, nearEnergy:0, near:{x:0,y:0},
                    origin:{x:0,y:0}, members:[], dirty:true, build:-1, selected:false};
                context.groups[entry.role] = group;
            }
            entry.lightGroup = group; group.members.push(entry); group.dirty = true;
        }
        entries.push(entry); return true;
    }

    public static function sample(ref:Object, outlet:MovieClip, strength:Number, visual:MovieClip):Boolean {
        var entry:Object = ref.equipmentLight;
        if (visual == undefined) visual = entry.actor[entry.slot + "_引用"];
        if (!valid(entry) || entry.kind == 0 || !drawn(entry) || !outlet._parent || !ensureEntry(entry)
            || !visible(visual)) { hide(ref); return false; }
        // An action prop must still be a visible descendant of the equipped
        // actor. A light cannot sample a detached or another actor's marker.
        var ancestor:MovieClip = outlet;
        while (ancestor && ancestor !== visual) ancestor = ancestor._parent;
        if (ancestor !== visual) { hide(ref); return false; }
        while (ancestor && ancestor !== entry.actor) ancestor = ancestor._parent;
        if (ancestor !== entry.actor) { hide(ref); return false; }
        var origin:Object = entry.origin, forward:Object = entry.forward;
        origin.x = 0; origin.y = 0; forward.x = 100; forward.y = 0;
        outlet.localToGlobal(origin); outlet.localToGlobal(forward);
        _root.gameworld.globalToLocal(origin); _root.gameworld.globalToLocal(forward);
        var dx:Number = forward.x - origin.x, dy:Number = forward.y - origin.y;
        var magnitude:Number = Math.sqrt(dx * dx + dy * dy);
        if (!isFinite(origin.x + origin.y + magnitude + strength) || !(magnitude > 0.001)
            || Math.abs(origin.x) > 1000000 || Math.abs(origin.y) > 1000000) { hide(ref); return false; }
        entry.x = origin.x; entry.y = origin.y; entry.dx = dx / magnitude; entry.dy = dy / magnitude;
        var near:Object = entry.near;
        near.x = 0; near.y = 0; entry.actor.localToGlobal(near); _root.gameworld.globalToLocal(near);
        near.y -= UnitUtil.calculateCenterOffset(entry.actor);
        if (!isFinite(near.x + near.y) || Math.abs(near.x) > 1000000 || Math.abs(near.y) > 1000000) { hide(ref); return false; }
        entry.strength = Math.max(0, Math.min(1, strength));
        entry.tick = _root.帧计时器.当前帧数; entry.sampled = true;
        return owns(ref);
    }

    // Body coordinates are resolved once per actor in payload(). Blade anchors
    // cache their local centre on the actual marker, surviving no stale MC alias.
    public static function sampleRadial(ref:Object, anchor:MovieClip, strength:Number, color:Number):Boolean {
        var entry:Object = ref.equipmentLight;
        if (!valid(entry) || entry.kind != 0 || !drawn(entry) || !(strength > 0) || !isFinite(strength)
            || !visible(entry.actor) || !ensureEntry(entry)) { hide(ref); return false; }
        if (entry.role == "blade") {
            var weapon:MovieClip = entry.actor[entry.slot + "_引用"];
            if (!weapon._parent || !visible(weapon) || !anchor._parent) { hide(ref); return false; }
            var center:Object = anchor.__equipmentLightCenter;
            if (!center || center.frame != anchor._currentframe) {
                var rect:Object = anchor.getRect(anchor);
                center = {x:(rect.xMin + rect.xMax) * 0.5,y:(rect.yMin + rect.yMax) * 0.5};
                if (!isFinite(center.x + center.y)) center = {x:0,y:0};
                center.frame = anchor._currentframe; anchor.__equipmentLightCenter = center;
            }
            var point:Object = entry.origin;
            point.x = center.x; point.y = center.y;
            anchor.localToGlobal(point); _root.gameworld.globalToLocal(point);
            if (!isFinite(point.x + point.y) || Math.abs(point.x) > 1000000 || Math.abs(point.y) > 1000000) { hide(ref); return false; }
            entry.x = point.x; entry.y = point.y;
        }
        if (!isFinite(color) || color < 0 || color > 16777215) { hide(ref); return false; }
        if (entry.lightGroup && (entry.color != color || entry.strength != Math.min(1,strength))) entry.lightGroup.dirty = true;
        if (entry.color != color) {
            entry.color = color; entry.r = 0.2 + (((color >> 16) & 255) / 255) * 0.8;
            entry.g = 0.2 + (((color >> 8) & 255) / 255) * 0.8; entry.b = 0.2 + ((color & 255) / 255) * 0.8;
        }
        entry.strength = Math.min(1, strength); entry.tick = _root.帧计时器.当前帧数; entry.sampled = true;
        return owns(ref);
    }
    public static function owns(ref:Object):Boolean {
        var entry:Object = ref.equipmentLight;
        if (!valid(entry) || !drawn(entry) || !entry.sampled || entry.scene !== scene) return false;
        var peers:Array = entry.peers;
        var now:Number = _root.帧计时器.当前帧数;
        for (var i:Number = 0; i < peers.length; i++) {
            var other:Object = peers[i];
            if (other === entry || !other.sampled || !valid(other) || !drawn(other)
                || (!(other.kind == 0 && other.role == "body") && !_root.暂停 && now - other.tick > 2)) continue;
            if (other.priority > entry.priority || (other.priority == entry.priority && other.id < entry.id)) return false;
        }
        return true;
    }
    public static function hide(ref:Object):Void {
        if (ref.equipmentLight) {
            ref.equipmentLight.sampled = false; ref.equipmentLight.trailTick = -10000;
            if (ref.equipmentLight.lightGroup) ref.equipmentLight.lightGroup.dirty = true;
        }
    }
    public static function release(ref:Object):Void {
        var entry:Object = ref.equipmentLight;
        if (entry) { entry.active = false; entry.sampled = false; detach(entry); }
        for (var i:Number = entries.length - 1; i > -1; i--) {
            if (entries[i] === entry) { entries[i] = entries[entries.length - 1]; entries.pop(); }
        }
        ref.equipmentLight = null;
    }
    private static function onScreen(entry:Object):Boolean {
        var view:Object = viewport;
        var scale:Number = view.scale;
        var x0:Number = view.x + entry.x * scale, y0:Number = view.y + entry.y * scale;
        var extent:Number = (entry.kind == 0 ? entry.length : entry.width) * view.absScale;
        if (entry.kind == 0) return x0 + extent >= 0 && x0 - extent <= view.width && y0 + extent >= 0 && y0 - extent <= view.height;
        var x1:Number = entry.kind == 0 ? x0 : x0 + entry.dx * entry.length * scale;
        var y1:Number = entry.kind == 0 ? y0 : y0 + entry.dy * entry.length * scale;
        if (Math.max(x0,x1) + extent >= 0 && Math.min(x0,x1) - extent <= view.width
            && Math.max(y0,y1) + extent >= 0 && Math.min(y0,y1) - extent <= view.height) return true;
        var nx:Number = view.x + entry.near.x * scale, ny:Number = view.y + entry.near.y * scale;
        var radius:Number = entry.nearRadius * view.absScale;
        return radius > 0 && nx + radius >= 0 && nx - radius <= view.width && ny + radius >= 0 && ny - radius <= view.height;
    }
    private static function contribute(entry:Object, now:Number):Void {
        var group:Object = entry.lightGroup;
        entry.eligible = serial;
        if (entry.role == "body") {
            if (group.build != serial) {
                group.build = serial; group.suppressed = false;
                var bodyPoint:Object = group.origin; bodyPoint.x = 0; bodyPoint.y = 0;
                entry.actor.localToGlobal(bodyPoint); _root.gameworld.globalToLocal(bodyPoint);
                group.x = bodyPoint.x; group.y = bodyPoint.y - UnitUtil.calculateCenterOffset(entry.actor);
            }
            return;
        }
        var energy:Number = entry.energy * entry.strength;
        var age:Number = now - entry.trailTick;
        if (entry.role == "blade" && age > -1 && age < 4) energy *= 1 + 0.18 * (1 - age * 0.25);
        if (group.build != serial) {
            group.build = serial; group.sum = 0; group.peak = 0; group.length = 0; group.suppressed = false;
            if (entry.role == "body") {
                var point:Object = group.origin; point.x = 0; point.y = 0;
                entry.actor.localToGlobal(point); _root.gameworld.globalToLocal(point);
                group.x = point.x; group.y = point.y - UnitUtil.calculateCenterOffset(entry.actor);
            }
        }
        group.sum += energy;
        if (energy > group.peak || (energy == group.peak && entry.id < group.dominant)) {
            group.peak = energy; group.dominant = entry.id;
            group.r = entry.r; group.g = entry.g; group.b = entry.b;
            if (entry.role == "blade") {
                group.x = age == 0 ? entry.trailX : entry.x;
                group.y = age == 0 ? entry.trailY : entry.y;
            }
        }
        if (entry.length > group.length) group.length = entry.length;
        group.energy = Math.min(2, group.peak + Math.min(group.peak * 0.25, (group.sum - group.peak) * 0.12));
    }
    private static function bodyParameters(group:Object):Void {
        if (group.dirty) {
            var sum:Number = 0, peak:Number = 0, extent:Number = 0, dominant:Object;
            var members:Array = group.members;
            for (var i:Number = 0; i < members.length; i++) {
                var entry:Object = members[i];
                if (entry.eligible != serial) continue;
                var energy:Number = entry.energy * entry.strength;
                sum += energy; if (entry.length > extent) extent = entry.length;
                if (!dominant || energy > peak || (energy == peak && entry.id < dominant.id)) { peak = energy; dominant = entry; }
            }
            group.bodyRadius = extent; group.bodyEnergy = Math.min(2,peak + Math.min(peak*0.25,(sum-peak)*0.12));
            group.bodyR = dominant.r; group.bodyG = dominant.g; group.bodyB = dominant.b; group.dirty = false;
        }
        // Restore cached base values before temporary sword union/suppression.
        group.length = group.bodyRadius; group.energy = group.bodyEnergy;
        group.r = group.bodyR; group.g = group.bodyG; group.b = group.bodyB;
    }
    private static function compatible(a:Object, b:Object):Boolean {
        var r:Number = a.r - b.r, g:Number = a.g - b.g, v:Number = a.b - b.b;
        return r*r + g*g + v*v < 0.16;
    }
    private static function finishActor(context:Object):Void {
        var body:Object = context.groups.body, blade:Object = context.groups.blade;
        var hasBody:Boolean = body && body.build == serial;
        var hasBlade:Boolean = blade && blade.build == serial;
        if (hasBody) {
            var actor:MovieClip = context.actor, world:MovieClip = _root.gameworld;
            if (actor._parent === world) {
                body.x = actor._x; body.y = actor._y;
            } else {
                var point:Object = body.origin; point.x = 0; point.y = 0;
                actor.localToGlobal(point); world.globalToLocal(point);
                body.x = point.x; body.y = point.y;
            }
            body.y -= UnitUtil.calculateCenterOffset(actor);
            bodyParameters(body);
        }
        if (hasBody && hasBlade && compatible(body,blade)) {
            var dx:Number = blade.x - body.x, dy:Number = blade.y - body.y;
            var cover:Number = Math.sqrt(dx*dx + dy*dy) + blade.length;
            if (cover < body.length * 1.15 && cover < 200) {
                body.length = Math.max(body.length,cover);
                body.energy = Math.min(radialPeak, body.energy + blade.energy);
                blade.suppressed = true;
            }
        }
        var torch:Object = context.coveringTorch;
        if (hasBody && torch) {
            dx = body.x - torch.near.x; dy = body.y - torch.near.y;
            if (Math.sqrt(dx*dx + dy*dy) + body.length <= torch.nearRadius
                && torch.nearEnergy > body.energy * 1.3) body.suppressed = true;
        }
        if (hasBody) body.energy = Math.min(radialPeak,body.energy);
        if (hasBlade) blade.energy = Math.min(radialPeak,blade.energy);
        if (hasBody && !body.suppressed && hasBlade && !blade.suppressed) {
            dx = blade.x-body.x; dy = blade.y-body.y;
            var distance2:Number = dx*dx+dy*dy, reach:Number = body.length+blade.length;
            if (distance2 < reach*reach) {
                // At every pixel at least one centre is >= half the separation
                // away. The radial shader uses (1-r*r)^2, giving this safe upper
                // bound without a per-pixel loop or extra native light.
                var halfDistance2:Number = distance2*0.25;
                var bodyFalloff:Number = Math.max(0,1-halfDistance2/(body.length*body.length));
                var bladeFalloff:Number = Math.max(0,1-halfDistance2/(blade.length*blade.length));
                var overlapPeak:Number = Math.max(body.energy+blade.energy*bladeFalloff*bladeFalloff,
                    blade.energy+body.energy*bodyFalloff*bodyFalloff);
                if (overlapPeak > radialPeak) {
                    var gain:Number = radialPeak/overlapPeak;
                    body.energy *= gain; blade.energy *= gain;
                }
            }
        }
        if (hasBody && !body.suppressed && isFinite(body.x+body.y) && Math.abs(body.x)<=1000000 && Math.abs(body.y)<=1000000 && onScreen(body)) candidates.push(body);
        if (hasBlade && !blade.suppressed && onScreen(blade)) candidates.push(blade);
    }
    private static function rank(entry:Object):Void {
        entry.selected = !!entry.selected;
        entry.tier = entry.tierOverride != undefined ? entry.tierOverride
            : ((entry.actor._name === _root.控制目标 ? 3 : 0) + (entry.kind == 0 ? 0 : 1));
        var view:Object = viewport;
        var scale:Number = view.scale;
        var dx:Number = view.x + entry.x * scale - view.width * 0.5;
        var dy:Number = view.y + entry.y * scale - view.height * 0.5;
        if (entry.kind != 0) {
            var extent:Number = entry.length * scale;
            var t:Number = extent == 0 ? 0 : Math.max(0,Math.min(1,-(dx*entry.dx + dy*entry.dy)/extent));
            dx += entry.dx * extent * t; dy += entry.dy * extent * t;
        }
        entry.score = (dx*dx + dy*dy) * (entry.selected ? 0.75 : 1);
        entry.held = entry.selected && budgetTick < entry.holdUntil;
    }
    private static function rounded(value:Number):Number { return Math.round(value*10000)/10000; }

    private static function radialWire(entry:Object):String {
        var energy:Number = entry.energy * entry.strength;
        var round:Function = Math.round;
        if (entry.wireRadius !== entry.length || entry.wireEnergy !== energy
            || entry.wireR !== entry.r || entry.wireG !== entry.g || entry.wireB !== entry.b) {
            entry.wireRadius = entry.length; entry.wireEnergy = energy;
            entry.wireR = entry.r; entry.wireG = entry.g; entry.wireB = entry.b;
            entry.wireTail = ",0,0," + round(entry.length*10000)/10000 + ",0," + round(energy*10000)/10000
                + "," + round(entry.r*10000)/10000 + "," + round(entry.g*10000)/10000
                + "," + round(entry.b*10000)/10000 + ",0,0,0,0";
            entry.wire = null;
        }
        if (entry.wire == null || entry.wireX !== entry.x || entry.wireY !== entry.y) {
            entry.wireX = entry.x; entry.wireY = entry.y;
            entry.wire = ";l," + entry.id + ",0," + round(entry.x*10000)/10000 + "," + round(entry.y*10000)/10000 + entry.wireTail;
        }
        return entry.wire;
    }

    public static function payload():String {
        if (!nativeEnabled) return "";
        var timing:Object = profile;
        var stamp:Number = timing ? getTimer() : 0, nextStamp:Number;
        var now:Number = _root.帧计时器.当前帧数;
        var paused:Boolean = !!_root.暂停;
        var sources:Array = entries, pending:Array = candidates, contexts:Array = actors;
        var admitted:Array = selected, residents:Array = previous;
        var view:Object = viewport, world:MovieClip = _root.gameworld;
        view.x = world._x; view.y = world._y; view.scale = world._xscale * 0.01;
        view.absScale = Math.abs(view.scale); view.width = Stage.width; view.height = Stage.height;
        if (now < budgetTick) {
            for (var old:Number = 0; old < residents.length; old++) residents[old].selected = false;
            residents.length = 0; budgetTick = now;
        }
        if (!paused) budgetTick = now;
        var currentSerial:Number = ++serial, currentScene:Number = scene, frameTick:Number = budgetTick;
        checking = true; pending.length = 0; contexts.length = 0; admitted.length = 0;
        var count:Number = 0, radial:Boolean = radialEnabled;
        var validate:Function = valid, detachSource:Function = detach, ownsLight:Function = owns;
        var collect:Function = contribute, inView:Function = onScreen, finish:Function = finishActor, rankLight:Function = rank;
        var i:Number, j:Number, entry:Object, context:Object, group:Object;
        // Static body sources are validated and collected in one traversal.
        // Single-owner slots need no second valid/drawn/peer/contribute chain.
        for (i = sources.length - 1; i > -1; i--) {
            entry = sources[i];
            if (!validate(entry)) { entry.active = false; detachSource(entry); sources[i] = sources[sources.length-1]; sources.pop(); continue; }
            if (entry.kind == 0 && entry.role == "body") {
                context = entry.context; group = entry.lightGroup;
                var eligible:Boolean = radial && context.alive && context.visible && entry.sampled
                    && entry.scene === currentScene && entry.energy*entry.strength > 0;
                if (eligible && entry.peers.length > 1) eligible = ownsLight(entry.owner);
                if (eligible != entry.bodyEligible) { group.dirty = true; entry.bodyEligible = eligible; }
                if (!eligible) continue;
                count++; entry.eligible = currentSerial;
                group.build = currentSerial; group.suppressed = false;
                if (context.build != currentSerial) {
                    context.build = currentSerial; context.coveringTorch = null; context.nearWinner = null;
                    contexts[contexts.length] = context;
                }
            } else {
                if (!paused && now-entry.tick > 2) entry.sampled = false;
            }
        }
        if (timing) { nextStamp = getTimer(); timing.validation += nextStamp-stamp; stamp = nextStamp; }
        // Keep the original registry order for equal-strength directional fills.
        for (i = 0; i < sources.length; i++) {
            entry = sources[i];
            if (entry.kind == 0 && entry.role == "body") continue;
            if ((entry.kind == 0 && (!radial || !(entry.energy*entry.strength > 0))) || !ownsLight(entry.owner)) continue;
            count++; context = entry.context;
            if (context.build != currentSerial) {
                context.build = currentSerial; context.coveringTorch = null; context.nearWinner = null; contexts[contexts.length] = context;
            }
            if (entry.kind == 0) collect(entry,frameTick);
            else if (inView(entry)) {
                pending[pending.length] = entry;
                if (entry.nearRadius > 0 && (!context.coveringTorch || entry.nearEnergy > context.coveringTorch.nearEnergy)) context.coveringTorch = entry;
            }
        }
        sourceCount = count;
        if (timing) { nextStamp = getTimer(); timing.collection += nextStamp-stamp; stamp = nextStamp; }
        for (i = 0; i < contexts.length; i++) finish(contexts[i]);
        if (radial && projectiles.length > 0) {
            count += collectBullets(frameTick, paused);
            sourceCount = count;
        }
        if (timing) { nextStamp = getTimer(); timing.aggregation += nextStamp-stamp; stamp = nextStamp; }
        checking = false;
        mergedCount = count - pending.length;
        for (i = 0; i < pending.length; i++) {
            entry = pending[i]; rankLight(entry);
            j = admitted.length;
            var tier:Number = entry.tier, held:Boolean = entry.held, score:Number = entry.score, id:Number = entry.id;
            while (j > 0) {
                var other:Object = admitted[j-1];
                if (!(tier != other.tier ? tier > other.tier : (held != other.held ? held :
                    (score != other.score ? score < other.score : id < other.id)))) break;
                j--;
            }
            if (j < 16) {
                var end:Number = admitted.length < 16 ? admitted.length : 15;
                for (var k:Number = end; k > j; k--) admitted[k] = admitted[k-1];
                admitted[j] = entry;
            }
        }
        droppedCount = pending.length - admitted.length;
        for (i = 0; i < admitted.length; i++) {
            entry = admitted[i];
            if (!entry.selected) entry.holdUntil = frameTick + 8;
            if (entry.kind == 1 && entry.nearRadius > 0) {
                context = entry.context;
                if (!context.nearWinner || entry.id < context.nearWinner.id) context.nearWinner = entry;
            }
        }
        for (i = 0; i < residents.length; i++) residents[i].selected = false;
        residents.length = 0;
        if (timing) { nextStamp = getTimer(); timing.admission += nextStamp-stamp; stamp = nextStamp; }
        var result:String = "";
        var radialRecord:Function = radialWire, round:Function = rounded;
        for (i = 0; i < admitted.length; i++) {
            entry = admitted[i]; entry.selected = true; residents[residents.length] = entry;
            if (entry.kind == 0) { result += radialRecord(entry); continue; }
            var hasNear:Boolean = entry.kind == 1 && entry.context.nearWinner === entry;
            result += ";l," + entry.id + "," + entry.kind + "," + round(entry.x) + "," + round(entry.y)
                + "," + round(entry.dx) + "," + round(entry.dy) + "," + round(entry.length) + "," + entry.width
                + "," + round(entry.energy * entry.strength) + "," + round(entry.r) + "," + round(entry.g) + "," + round(entry.b)
                + "," + (hasNear ? round(entry.near.x) : 0) + "," + (hasNear ? round(entry.near.y) : 0)
                + "," + (hasNear ? entry.nearRadius : 0) + "," + (hasNear ? round(entry.nearEnergy) : 0);
        }
        if (timing) { timing.serialization += getTimer()-stamp; timing.calls++; }
        return result;
    }
    private static function initBulletProfiles():Object {
        var m:Object = {};
        var raw:String =
            "爆炸,260,1.75,16753226,0,-45,17,1;火球爆炸,250,1.7,16747576,0,-40,17,1;等离子爆炸,260,1.8,7399679,0,-45,17,1;" +
            "集束连环爆炸,270,1.8,16752712,0,-45,18,1;联弹爆炸,230,1.55,16753226,0,-35,17,1;定向爆破,250,1.7,16752196,0,-40,17,1;" +
            "铁血弹爆炸,220,1.5,16746550,0,-30,15,1;空中爆炸1,230,1.55,16753226,0,-20,15,1;火焰爆发,240,1.65,16747574,150,0,17,1;" +
            "小火焰爆发,195,1.4,16747574,115,0,17,1;冰流爆发,230,1.5,7396607,145,0,17,1;" +
            "加强电球,145,1.15,7919871,0,0,53,0,7,245,1.65,-35;量子爆弹,130,0.95,9234687,0,-60,52,0,33,305,1.85,-120;" +
            "火球,175,1.35,16747059,0,0,42,0;火焰,155,1.15,16745518,25,0,34,0;普通火箭弹,155,1.2,16753740,-20,0,38,0;" +
            "高爆火箭弹,165,1.25,16750656,-20,0,38,0;激光火箭弹,165,1.3,16742984,-15,0,35,0;榴弹,135,1,16754772,-10,0,34,0;" +
            "高爆榴弹,145,1.1,16751684,-10,0,34,0;穿甲榴弹,145,1.1,16756824,-10,0,34,0;集束榴弹,145,1.1,16753740,0,0,34,0;" +
            "战术集束榴弹,150,1.15,16753740,0,0,34,0;高爆子弹,135,1.05,16756824,0,0,25,0;天基炮弹,175,1.35,16758880,0,0,40,0;" +
            "战斧导弹,165,1.25,16753740,-20,0,45,0;追踪导弹,150,1.15,16753740,-15,0,45,0;长钉导弹,150,1.15,16753740,-15,0,45,0;" +
            "红外制导导弹,150,1.15,16753740,-15,0,45,0;微型导弹,135,1,16753740,-10,0,40,0;连环导弹,145,1.1,16753740,-15,0,40,0;" +
            "外星导弹,155,1.2,6875391,-15,0,45,0;蓝旋反坦克炮弹,175,1.35,6086911,0,0,40,0;能量弹,170,1.35,7006463,0,0,40,0;" +
            "能量球,165,1.3,7006463,0,0,40,0;电球,145,1.15,7919871,0,0,35,0;等离子榴弹,155,1.25,6875391,0,0,34,0;" +
            "等离子导弹,160,1.25,6875391,-15,0,45,0;压缩能量榴弹,155,1.25,7923967,0,0,34,0;重型电浆弹,175,1.4,6876927,0,0,40,0;" +
            "战术电浆团,165,1.3,6876927,0,0,40,0;外星文明的馈赠,185,1.45,7401727,0,0,40,0;电磁弹,150,1.2,7395583,0,0,30,0;" +
            "脉冲弹,150,1.2,7397631,0,0,30,0;蓝紫穿刺子弹,155,1.2,10385663,0,0,30,0;紫光球,150,1.15,12871935,0,0,35,0;" +
            "铁枪磁暴弹,175,1.35,7136511,0,0,35,0;铁枪能量弹,150,1.15,7136511,0,0,30,0;高斯穿刺弹,145,1.1,8447231,0,0,25,0;" +
            "重型高斯弹,160,1.25,8447231,0,0,25,0;极寒弹,140,1.05,7922943,0,0,25,0;急冻弹,140,1.05,7922943,0,0,25,0;" +
            "寒冰冲击波,190,1.35,7922943,40,0,20,0;烈焰弹,140,1.05,16749112,0,0,25,0;日珥弹,155,1.2,16753720,0,0,25,0;" +
            "黄金子弹,135,1,16765524,0,0,25,0;次元弹,155,1.2,12087551,0,0,30,0;破魔弹,145,1.1,13662463,0,0,25,0;" +
            "生体护盾破坏弹,145,1.1,6881180,0,0,25,0;腐蚀弹,140,1.05,7929696,0,0,25,0;剧毒弹,140,1.05,7929696,0,0,25,0;" +
            "异形酸液,145,1.1,8716114,0,0,30,0;火凤火攻,190,1.45,16743982,0,-25,10,1;火凤回旋,235,1.65,16747574,0,-45,20,1;" +
            "中火燃,195,1.45,16745520,0,-35,15,1;熔炎裂渊,245,1.7,16743982,0,-45,24,1;金炎裂渊,250,1.75,16758852,0,-45,24,1;" +
            "浴火重生,280,1.85,16749624,0,-65,30,1;浴火重生-火凤,280,1.85,16749624,0,-65,30,1;凤凰浴火重生,300,1.95,16750652,0,-75,30,1;" +
            "凤凰浴火重生小型,240,1.65,16749624,0,-50,25,1;火凤套装_回血提示,180,1.3,16753216,0,-40,16,1;" +
            "火凤套装_热附击,165,1.3,16746548,0,-25,10,1;火凤套装_完整热附击,195,1.5,16750140,0,-30,12,1;" +
            "火凤套装_原版火攻,180,1.35,16745010,0,-15,8,1;火凤套装_原版回旋,230,1.6,16749624,0,-35,19,1;" +
            "__phoenix_revive,260,1.8,16748086,0,-45,4,1;__phoenix_ember,135,0.85,16742952,0,-35,4,0;" +
            "__huofeng_nirvana,270,1.85,16749624,0,0,4,1;__huofeng_ember,130,0.8,16744492,0,-35,4,0;" +
            "__pulse_heat,215,1.5,16747574,0,0,6,1;__pulse_cold,200,1.35,7396607,0,0,6,1";
        var rows:Array = raw.split(";");
        for (var i:Number = 0; i < rows.length; i++) {
            var p:Array = rows[i].split(",");
            var col:Number = Number(p[3]);
            m[p[0]] = {
                radius:Number(p[1]), energy:Number(p[2]),
                r:0.2 + (((col >> 16) & 255) / 255) * 0.8,
                g:0.2 + (((col >> 8) & 255) / 255) * 0.8,
                b:0.2 + ((col & 255) / 255) * 0.8,
                forwardOffset:Number(p[4]), offsetY:Number(p[5]),
                totalFrames:Number(p[6]), isExplosion:p[7] == "1",
                stageFrame:p.length > 8 ? Number(p[8]) : 0,
                stageRadius:p.length > 8 ? Number(p[9]) : 0,
                stageEnergy:p.length > 8 ? Number(p[10]) : 0,
                stageOffsetY:p.length > 8 ? Number(p[11]) : 0
            };
        }
        bulletProfiles = m;
        return m;
    }

    public static function emitPulseAt(asset:String, px:Number, py:Number, shooter:MovieClip,
        radiusOverride:Number, energyOverride:Number, durationOverride:Number):Void {
        if (!radialEnabled || !asset || nextId > 999999990) return;
        var map:Object = bulletProfiles || initBulletProfiles();
        var spec:Object = map[asset];
        if (!spec) return;
        var targetX:Number = Number(px) + spec.forwardOffset;
        var targetY:Number = Number(py) + spec.offsetY;
        if (!isFinite(targetX + targetY) || Math.abs(targetX) > 1000000 || Math.abs(targetY) > 1000000) return;
        var effRadius:Number = radiusOverride > 0 ? Math.min(320, Math.max(30, radiusOverride)) : spec.radius;
        var effEnergy:Number = energyOverride > 0 ? Math.min(2, Math.max(0.05, energyOverride)) : spec.energy;
        var effDuration:Number = durationOverride > 0 ? durationOverride : spec.totalFrames;
        var now:Number = Number(_root.帧计时器.当前帧数);
        if (!isFinite(now)) now = budgetTick;
        var isActorContinuous:Boolean = shooter != null && (durationOverride > 0 || radiusOverride > 0);
        for (var i:Number = projectiles.length - 1; i > -1; i--) {
            var existing:Object = projectiles[i];
            if (existing.isPulse && existing.asset === asset && existing.scene === scene) {
                var dx:Number = existing.x - targetX, dy:Number = existing.y - targetY;
                if ((isActorContinuous && existing.actor === shooter) || dx * dx + dy * dy < 3600) {
                    existing.x = targetX;
                    existing.y = targetY;
                    existing.baseRadius = effRadius;
                    existing.baseEnergy = effEnergy;
                    existing.pulseDuration = effDuration;
                    existing.birthTick = now;
                    existing.expireTick = now + effDuration;
                    return;
                }
            }
        }
        addProjectileEntry(null, asset, spec, shooter, true, targetX, targetY);
        var added:Object = projectiles[projectiles.length - 1];
        if (added && added.asset === asset) {
            added.baseRadius = effRadius;
            added.baseEnergy = effEnergy;
            added.pulseDuration = effDuration;
            added.expireTick = now + effDuration;
        }
    }

    public static function registerBullet(bullet:Object, obj:Object, shooter:MovieClip):Void {
        if (!radialEnabled || !bullet || !obj || nextId > 999999990) return;
        var map:Object = bulletProfiles || initBulletProfiles();
        var asset:String = obj.baseAsset ? String(obj.baseAsset) : String(obj.子弹种类);
        if (bullet._parent != undefined) {
            var spec:Object = map[asset];
            if (!spec) return;
            addProjectileEntry(MovieClip(bullet), asset, spec, shooter, false, 0, 0);
            return;
        }
        var sound:String = obj.声音;
        var magic:String = obj.魔法伤害属性;
        if (sound == "火流.wav" || sound == "冰流.wav"
            || (asset == "近战子弹" && (magic == "热" || magic == "冷"))) {
            var pulseKey:String = (sound == "冰流.wav" || magic == "冷") ? "__pulse_cold" : "__pulse_heat";
            var pulseSpec:Object = map[pulseKey];
            var col:Object = bullet.aabbCollider;
            var px:Number = Number(obj.shootX);
            var py:Number = Number(obj.shootY);
            if (col && isFinite(col.left + col.right + col.top + col.bottom)) {
                px = (col.left + col.right) * 0.5;
                py = (col.top + col.bottom) * 0.5;
            }
            if (!isFinite(px + py) || Math.abs(px) > 1000000 || Math.abs(py) > 1000000) return;
            var now:Number = Number(_root.帧计时器.当前帧数);
            if (!isFinite(now)) now = budgetTick;
            for (var i:Number = projectiles.length - 1; i > -1; i--) {
                var existing:Object = projectiles[i];
                if (existing.isPulse && existing.asset === pulseKey && existing.scene === scene) {
                    var dx:Number = existing.x - px, dy:Number = existing.y - py;
                    if (dx * dx + dy * dy < 8100) {
                        existing.x = px; existing.y = py;
                        existing.birthTick = now;
                        existing.expireTick = now + pulseSpec.totalFrames;
                        return;
                    }
                }
            }
            addProjectileEntry(null, pulseKey, pulseSpec, shooter, true, px, py);
        }
    }

    public static function registerEffect(mc:MovieClip, effectType:String):Void {
        if (!radialEnabled || !mc || !mc._parent || !effectType || nextId > 999999990) return;
        var map:Object = bulletProfiles || initBulletProfiles();
        var spec:Object = map[effectType];
        if (!spec) return;
        var now:Number = Number(_root.帧计时器.当前帧数);
        if (!isFinite(now)) now = budgetTick;
        for (var i:Number = projectiles.length - 1; i > -1; i--) {
            var existing:Object = projectiles[i];
            if (existing.mc === mc) {
                existing.asset = effectType;
                existing.spec = spec;
                existing.scene = scene;
                existing.birthTick = now;
                existing.expireTick = now + spec.totalFrames + 4;
                return;
            }
        }
        addProjectileEntry(mc, effectType, spec, null, false, 0, 0);
    }

    private static function addProjectileEntry(mc:MovieClip, asset:String, spec:Object, shooter:MovieClip,
        isPulse:Boolean, px:Number, py:Number):Void {
        var now:Number = Number(_root.帧计时器.当前帧数);
        if (!isFinite(now)) now = budgetTick;
        for (var i:Number = projectiles.length - 1; i > -1; i--) {
            var old:Object = projectiles[i];
            if (old.scene !== scene || now > old.expireTick || (!old.isPulse && (!old.mc._parent || !old.mc._visible))) {
                projectiles.splice(i, 1);
            }
        }
        if (projectiles.length >= 48) {
            var evict:Number = 0;
            for (i = 0; i < projectiles.length; i++) {
                if (!projectiles[i].spec.isExplosion) { evict = i; break; }
            }
            projectiles.splice(evict, 1);
        }
        var maxTicks:Number = isPulse ? spec.totalFrames : (spec.isExplosion ? spec.totalFrames + 4 : 180);
        var isHero:Boolean = shooter != null && shooter._name === _root.控制目标;
        var tierVal:Number = isHero ? 3 : (spec.isExplosion ? 2 : 1);
        projectiles.push({
            id: ++nextId,
            kind: 0,
            mc: mc,
            asset: asset,
            spec: spec,
            actor: shooter,
            tierOverride: tierVal,
            isBullet: true,
            isPulse: isPulse,
            x: px,
            y: py,
            baseRadius: spec.radius,
            baseEnergy: spec.energy,
            pulseDuration: maxTicks,
            length: spec.radius,
            width: 0,
            dx: 0,
            dy: 0,
            energy: spec.energy,
            strength: 1,
            r: spec.r,
            g: spec.g,
            b: spec.b,
            nearRadius: 0,
            nearEnergy: 0,
            scene: scene,
            birthTick: now,
            expireTick: now + maxTicks,
            selected: false,
            holdUntil: 0
        });
    }

    private static function collectBullets(now:Number, paused:Boolean):Number {
        var world:MovieClip = _root.gameworld;
        if (!world._parent) return 0;
        var bulletLayer:MovieClip = world.子弹区域;
        var effectLayer:MovieClip = world.效果;
        var pending:Array = candidates;
        var basePendingCount:Number = pending.length;
        var activeBulletSources:Number = 0;
        for (var i:Number = 0; i < projectiles.length; i++) {
            var item:Object = projectiles[i];
            var spec:Object = item.spec;
            if (item.scene !== scene || (!paused && now > item.expireTick)) {
                projectiles.splice(i, 1); i--; continue;
            }
            if (item.isPulse) {
                var pDur:Number = item.pulseDuration > 0 ? item.pulseDuration : spec.totalFrames;
                var age:Number = now - item.birthTick;
                if (age < 0) age = 0;
                if (!paused && age >= pDur) {
                    projectiles.splice(i, 1); i--; continue;
                }
                var pulseFade:Number = 1 - age / (pDur + 1);
                item.length = item.baseRadius > 0 ? item.baseRadius : spec.radius;
                item.energy = (item.baseEnergy > 0 ? item.baseEnergy : spec.energy) * pulseFade;
            } else {
                var mc:MovieClip = item.mc;
                if (!mc._parent || !mc._visible) {
                    projectiles.splice(i, 1); i--; continue;
                }
                var cf:Number = mc._currentframe;
                if (spec.isExplosion && cf > spec.totalFrames) {
                    projectiles.splice(i, 1); i--; continue;
                }
                var bx:Number, by:Number;
                var parentClip:MovieClip = mc._parent;
                if (parentClip === world || parentClip === bulletLayer || parentClip === effectLayer) {
                    bx = mc._x; by = mc._y;
                } else {
                    var pt:Object = bulletPoint;
                    pt.x = 0; pt.y = 0;
                    mc.localToGlobal(pt); world.globalToLocal(pt);
                    bx = pt.x; by = pt.y;
                }
                var sx:Number = mc._xscale;
                var absScaleX:Number = isFinite(sx) ? Math.abs(sx) * 0.01 : 1;
                if (absScaleX < 0.5) absScaleX = 0.5;
                else if (absScaleX > 1.5) absScaleX = 1.5;
                var inStage2:Boolean = spec.stageFrame > 0 && cf >= spec.stageFrame;
                if (!inStage2 && spec.forwardOffset != 0) {
                    var rot:Number = isFinite(mc._rotation) ? mc._rotation * (Math.PI / 180) : 0;
                    var dir:Number = sx < 0 ? -1 : 1;
                    var fDist:Number = spec.forwardOffset * absScaleX;
                    bx += Math.cos(rot) * fDist * dir;
                    by += Math.sin(rot) * fDist * dir;
                }
                if (inStage2) {
                    by += spec.stageOffsetY;
                    var stageProg:Number = (cf - spec.stageFrame) / Math.max(1, spec.totalFrames - spec.stageFrame);
                    var stageFade:Number = stageProg < 0.3 ? 1 : Math.max(0.2, 1 - (stageProg - 0.3) / 0.7 * 0.8);
                    item.length = Math.min(320, Math.max(40, spec.stageRadius));
                    item.energy = Math.min(2, spec.stageEnergy * stageFade);
                    if (item.tierOverride < 2) item.tierOverride = 2;
                } else if (spec.isExplosion) {
                    by += spec.offsetY;
                    var expProg:Number = (cf - 1) / Math.max(1, spec.totalFrames);
                    var expFade:Number = expProg < 0.35 ? 1 : Math.max(0.2, 1 - (expProg - 0.35) / 0.65 * 0.8);
                    item.length = Math.min(320, Math.max(40, spec.radius * Math.min(1.3, absScaleX)));
                    item.energy = Math.min(2, spec.energy * expFade);
                } else {
                    by += spec.offsetY;
                    item.length = Math.min(320, Math.max(30, spec.radius * Math.min(1.25, absScaleX)));
                    item.energy = spec.energy;
                }
                if (!isFinite(bx + by + item.length + item.energy) || Math.abs(bx) > 1000000 || Math.abs(by) > 1000000 || !(item.energy > 0.01)) {
                    continue;
                }
                item.x = bx; item.y = by;
            }
            if (!onScreen(item)) continue;
            activeBulletSources++;
            var merged:Boolean = false;
            for (var j:Number = basePendingCount; j < pending.length; j++) {
                var peer:Object = pending[j];
                if (peer.asset === item.asset) {
                    var pdx:Number = peer.x - item.x, pdy:Number = peer.y - item.y;
                    if (pdx * pdx + pdy * pdy < 5625) {
                        peer.energy = Math.min(2, peer.energy + item.energy * 0.22);
                        peer.length = Math.min(320, Math.max(peer.length, item.length * 1.08));
                        merged = true;
                        break;
                    }
                }
            }
            if (!merged) pending[pending.length] = item;
        }
        return activeBulletSources;
    }

    public static function getStats():Object {
        return {enabled:nativeEnabled,radialEnabled:radialEnabled,registered:entries.length,scene:scene,
            activeSources:sourceCount,coalescedOrCulled:mergedCount,candidates:candidates.length,admitted:selected.length,dropped:droppedCount};
    }
}
