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
        selected.length = 0; previous.length = 0; scene++;
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

    public static function sample(ref:Object, outlet:MovieClip, strength:Number):Boolean {
        var entry:Object = ref.equipmentLight;
        if (!valid(entry) || entry.kind == 0 || !drawn(entry) || !outlet._parent || !ensureEntry(entry)
            || !visible(entry.actor[entry.slot + "_引用"])) { hide(ref); return false; }
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
        entry.tier = (entry.actor._name === _root.控制目标 ? 3 : 0) + (entry.kind == 0 ? 0 : 1);
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
    public static function getStats():Object {
        return {enabled:nativeEnabled,radialEnabled:radialEnabled,registered:entries.length,scene:scene,
            activeSources:sourceCount,coalescedOrCulled:mergedCount,candidates:candidates.length,admitted:selected.length,dropped:droppedCount};
    }
}
