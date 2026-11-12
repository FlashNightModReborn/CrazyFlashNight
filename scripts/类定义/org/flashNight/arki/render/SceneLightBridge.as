import org.flashNight.gesh.object.ObjectUtil;

import flash.geom.Transform;
/** Scene definitions are copied once; only changed bound poses use F9. No gameplay RNG. */
class org.flashNight.arki.render.SceneLightBridge {
    private static var enabled:Boolean = false;
    private static var world:MovieClip;
    private static var identity:Object;
    private static var sources:Object = {};
    private static var entries:Array = [];
    private static var definitions:Array = [];
    private static var configured:Boolean = false;
    private static var dirty:Boolean = true;
    private static var revision:Number = 1;
    private static var sequence:Number = 0;
    private static var sceneKey:String = "";
    private static var basePowerScene:Boolean = false;
    private static var warnings:Object = {};
    private static var capsSeen:Number = 0;
    private static var capsNative:String = "n/a";
    private static var capsSlv:String = "n/a";
    private static var capsKeys:String = "n/a";
    private static var catalogDigest:String = "";
    private static var lastBaseLightingTier:Number = -1;
    public static function installedCatalogDigest():String { return enabled ? catalogDigest : ""; }

    public static function configureCaps(caps:Object):Void {
        capsSeen++;
        capsNative = String(caps["native"]);
        capsSlv = String(caps.sceneLightsVersion);
        var ks:Array = [];
        for (var k:String in caps) ks.push(k);
        capsKeys = ks.join(",");
        var next:Boolean = (caps.worldLights == undefined ? caps["native"] === true : caps.worldLights === true) && caps.sceneLightsVersion === 1;
        catalogDigest = org.flashNight.arki.render.WorkerProjectionPolicy.adoptedCatalogDigest(caps.sceneLightsDigest);
        if (enabled != next) {
            enabled = next; dirty = true; revision++;
            for (var i:Number = 0; i < entries.length; i++) entries[i].last = "";
            org.flashNight.arki.weather.WorldLightingBridge.snapNext();
        }
    }
    public static function resetScene():Void {
        world = null; identity = null; sources = {}; entries = []; definitions = [];
        configured = false; dirty = true; revision++; sequence = 0; sceneKey = ""; basePowerScene = false;
        warnings = {}; warnings.__proto__ = null; lastBaseLightingTier = -1;
        sources.__proto__ = null;
    }
    private static function ensureWorld():Boolean {
        var current:MovieClip = _root.gameworld;
        if (!current) return false;
        if (identity == null || current.__sceneLightWorldIdentity !== identity) {
            resetScene(); world = current; identity = {};
            current.__sceneLightWorldIdentity = identity;
            _global.ASSetPropFlags(current, ["__sceneLightWorldIdentity"], 1, false);
        }
        return true;
    }
    public static function isConfigured():Boolean { return ensureWorld() && configured; }
    public static function track(clip:MovieClip, key):Void {
        if (key == undefined || key == "" || !ensureWorld()) return;
        key = String(key);
        var prior:Object = sources[key];
        if (prior != undefined && (prior.blocked || prior.receipt || (prior.clip && prior.clip.__sceneLightInstanceIdentity === prior.token))) {
            sources[key] = {blocked:true};
            warn(key, "duplicate_anchor");
            return;
        }
        var token:Object = {};
        clip.__sceneLightInstanceIdentity = token;
        _global.ASSetPropFlags(clip, ["__sceneLightInstanceIdentity"], 1, false);
        sources[key] = {clip:clip, token:token};
    }
    // loadMovie replaces target variables. Register the identity only after
    // loadClip's onLoadInit and validate the captured registration/world token.
    public static function loadSource(clip:MovieClip, url:String, key:String):Void {
        if (!ensureWorld()) return;
        if (sources[key] != undefined) {
            sources[key] = {blocked:true};
            warn(key, "duplicate_anchor");
            clip.loadMovie(url);
            return;
        }
        var receipt:Object = {key:key,world:identity,loader:new MovieClipLoader()};
        var listener:Object = {receipt:receipt};
        listener.onLoadInit = function(target:MovieClip):Void {
            org.flashNight.arki.render.SceneLightBridge.loadedSource(this.receipt,target);
        };
        listener.onLoadError = function(target:MovieClip, reason:String):Void {
            org.flashNight.arki.render.SceneLightBridge.loadFailed(this.receipt);
        };
        receipt.listener = listener; sources[key] = {receipt:receipt};
        receipt.loader.addListener(listener); receipt.loader.loadClip(url,clip);
    }
    private static function loadedSource(receipt:Object, target:MovieClip):Void {
        if (receipt.world === identity && _root.gameworld.__sceneLightWorldIdentity === receipt.world
            && sources[receipt.key].receipt === receipt) {
            var token:Object = {}; target.__sceneLightInstanceIdentity = token;
            _global.ASSetPropFlags(target,["__sceneLightInstanceIdentity"],1,false);
            sources[receipt.key] = {clip:target,token:token};
        }
        receipt.loader.removeListener(receipt.listener); receipt.loader = null; receipt.listener = null;
    }
    private static function loadFailed(receipt:Object):Void {
        if (receipt.world === identity && sources[receipt.key].receipt === receipt) {
            sources[receipt.key] = {blocked:true};
            warn(receipt.key, "anchor_load_error");
        }
        receipt.loader.removeListener(receipt.listener); receipt.loader = null; receipt.listener = null;
    }
    public static function diag():String {
        return (enabled ? 1 : 0) + "" + (configured ? 1 : 0) + "1"
            + "" + (dirty ? 1 : 0) + "|" + capsSeen + ":" + capsNative + ":" + capsSlv
            + "|" + definitions.length + "|" + sceneKey + "|" + capsKeys;
    }
    public static function configure(base:Array, extra:Array, key:String, basePower:Boolean):Void {
        if (!ensureWorld()) return;
        var merged:Array = []; var indices:Object = {};
        indices.__proto__ = null;
        sceneKey = key; basePowerScene = basePower === true;
        merge(base, merged, indices); merge(extra, merged, indices);
        // XML 源里所有字段都是字符串；快照直接进宿主强类型校验，
        // 数值/布尔字段必须在发送前归一为 JSON number/boolean。
        var numericFields:Array = ["X","Y","OffsetX","OffsetY","Angle","Radius","Length",
            "HalfWidth","Energy","BaseEnergy","Amplitude","Rate","Phase","SweepAngle","Priority"];
        for (var i:Number = 0; i < merged.length; i++) {
            var def:Object = merged[i];
            for (var f:String in numericFields) {
                var name:String = numericFields[f];
                if (def[name] != undefined) def[name] = Number(def[name]);
            }
            if (def.Enabled != undefined) def.Enabled = flag(def.Enabled, true);
        }
        definitions = []; entries = []; configured = true; dirty = true; revision++;
        for (var i:Number = 0; i < merged.length; i++) {
            var raw:Object = merged[i];
            if (raw == null || raw.__ambiguous) continue;
            var curve:Array = parseCurve(raw.FrameCurve);
            if (curve == null) { warn(raw.Key, "invalid_curve"); continue; }
            var tier:Number = raw.BasePowerTier == undefined ? -1 : Number(raw.BasePowerTier);
            if ((raw.BasePowerTier != undefined && (!basePowerScene || raw.BasePowerTier === "" || !(tier >= 0 && tier <= 3 && tier == Math.floor(tier))))
                    || (raw.BaseBeacon != undefined && (tier < 0 || !(raw.BaseBeacon === true || raw.BaseBeacon === false || raw.BaseBeacon === "true" || raw.BaseBeacon === "false")))) {
                warn(raw.Key, "invalid_base_power"); continue;
            }
            var beacon:Boolean = flag(raw.BaseBeacon,false);
            delete raw.BasePowerTier; delete raw.BaseBeacon;
            var id:Number = definitions.length + 1;
            entries.push({raw:raw, id:id, curve:curve, tier:tier, beacon:beacon, manual:1, last:"", pose:null, stateDirty:true});
            definitions.push(raw);
        }
        org.flashNight.arki.weather.WorldLightingBridge.snapNext();
    }
    private static function merge(list:Array, result:Array, indices:Object):Void {
        var seen:Object = {}; seen.__proto__ = null;
        for (var i:Number = 0; i < list.length; i++) {
            var raw:Object = ObjectUtil.clone(list[i]);
            var key:String = String(raw.Key);
            if (raw.Key == undefined || key.length == 0 || key.length > 128) { warn("#"+i,"invalid_key"); continue; }
            var index = indices[key];
            if (seen[key] === true) {
                if (index != undefined) result[index].__ambiguous = true;
                warn(key, "duplicate_light"); continue;
            }
            seen[key] = true;
            if (index == undefined) {
                if (result.length >= 128) { warn(key, "source_capacity"); continue; }
                indices[key] = result.length; result.push(raw);
            }
            else { for (var field:String in raw) result[index][field] = raw[field]; }
        }
    }
    private static function flag(value, fallback:Boolean):Boolean {
        return value == undefined ? fallback : (value === true || value === "true");
    }
    private static function num(value, fallback:Number):Number { return value == undefined ? fallback : Number(value); }
    private static function lookup(clip:MovieClip, path:String):MovieClip {
        if (path == undefined || path == "") return clip;
        var parts:Array = path.split(".");
        for (var i:Number = 0; i < parts.length; i++) clip = clip[parts[i]];
        return clip;
    }
    private static function parseCurve(text):Array {
        var result:Array = [];
        if (text == undefined || text == "") return result;
        var parts:Array = String(text).split(",");
        if (parts.length > 32) return null;
        var previous:Number = 0;
        for (var i:Number = 0; i < parts.length; i++) {
            var pair:Array = parts[i].split(":");
            var frame:Number = Number(pair[0]), strength:Number = Number(pair[1]);
            if (pair.length != 2 || !isFinite(frame + strength) || frame <= previous || frame != Math.floor(frame)
                || frame > 10000 || strength < 0 || strength > 1) return null;
            result.push({frame:frame, strength:strength}); previous = frame;
        }
        return result;
    }
    private static function curveStrength(curve:Array, frame:Number):Number {
        if (curve.length == 0) return 1;
        if (frame <= curve[0].frame) return curve[0].strength;
        for (var i:Number = 1; i < curve.length; i++) {
            if (frame <= curve[i].frame) {
                var a:Object = curve[i-1], b:Object = curve[i];
                return a.strength + (b.strength-a.strength)*(frame-a.frame)/(b.frame-a.frame);
            }
        }
        return curve[curve.length-1].strength;
    }
    private static function sample(entry:Object):Array {
        var raw:Object = entry.raw;
        var x:Number = num(raw.X,0), y:Number = num(raw.Y,0), dx:Number = 1, dy:Number = 0, size:Number = 1, hand:Number = 1;
        var strength:Number = entry.manual;
        if (raw.AttachTo != undefined && raw.AttachTo != "") {
            var source:Object = sources[String(raw.AttachTo)];
            var root:MovieClip = source.clip;
            var anchor:MovieClip = lookup(root,raw.Anchor);
            if (!root || root.__sceneLightInstanceIdentity !== source.token || !anchor || anchor._name == undefined) {
                strength = 0;
                if (!source.receipt && !source.blocked) {
                    entry.missingSamples = (entry.missingSamples || 0) + 1;
                    if (entry.missingSamples == 4) warn(raw.Key, "missing_anchor:" + raw.AttachTo + "/" + (raw.Anchor || ""));
                }
            }
            else {
                entry.missingSamples = 0;
                var ox:Number = num(raw.OffsetX,0), oy:Number = num(raw.OffsetY,0);
                var origin:Object = {x:ox,y:oy}, axis:Object = {x:ox+1,y:oy}, up:Object = {x:ox,y:oy+1};
                // Compose only below gameworld. Camera changes must not dirty
                // a fixed world source or introduce stage-coordinate rounding.
                var chain:MovieClip = anchor;
                while (chain && chain != world) {
                    var matrix:Object = new Transform(chain).matrix;
                    var points:Array = [origin,axis,up];
                    for (var k:Number = 0; k < 3; k++) {
                        var px:Number = points[k].x, py:Number = points[k].y;
                        points[k].x = matrix.a*px + matrix.c*py + matrix.tx;
                        points[k].y = matrix.b*px + matrix.d*py + matrix.ty;
                    }
                    chain = chain._parent;
                }
                if (chain != world) strength = 0;
                x = Math.round(origin.x*64)/64; y = Math.round(origin.y*64)/64;
                var vx:Number = axis.x-origin.x, vy:Number = axis.y-origin.y;
                var length:Number = Math.sqrt(vx*vx+vy*vy);
                if (length < 0.001 || !isFinite(length)) strength = 0;
                else {
                    if (flag(raw.FollowRotation,false)) { dx = vx/length; dy = vy/length; hand = vx*(up.y-origin.y)-vy*(up.x-origin.x) < 0 ? -1 : 1; }
                    if (flag(raw.FollowScale,false)) size = length;
                }
                if (flag(raw.FollowVisibility,true)) {
                    var cursor:MovieClip = anchor;
                    while (cursor && cursor != world) {
                        if (!cursor._visible || cursor._alpha <= 0) { strength = 0; break; }
                        cursor = cursor._parent;
                    }
                }
                strength *= curveStrength(entry.curve,root._currentframe);
                if (raw.StatePath != undefined && raw.StatePath != "") {
                    var state:Object = root; var names:Array = String(raw.StatePath).split(".");
                    for (var j:Number = 0; j < names.length; j++) state = state[names[j]];
                    strength *= typeof state == "boolean" ? (state ? 1 : 0) : num(state,0);
                }
            }
        } else { x += num(raw.OffsetX,0); y += num(raw.OffsetY,0); }
        if (!isFinite(x+y+dx+dy+size+strength) || Math.abs(x)>1000000 || Math.abs(y)>1000000 || size<0.001 || size>20) {
            warn(raw.Key, "invalid_pose"); strength = 0; x = 0; y = 0; dx = 1; dy = 0; size = 1; hand = 1;
        }
        strength = Math.max(0,Math.min(1,strength));
        return [entry.id,x,y,dx,dy,size,strength,hand];
    }
    public static function snapshot():Object {
        if (!enabled || !dirty) return null;
        var poses:Array = [];
        for (var i:Number = 0; i < entries.length; i++) { entries[i].pose = sample(entries[i]); poses.push(entries[i].pose); }
        return {version:1, revision:revision, key:sceneKey, definitions:definitions, poses:poses};
    }
    public static function sent():Void { if (enabled) dirty = false; }
    public static function flush():String {
        if (!enabled || !configured || !ensureWorld()) return null;
        var changed:Boolean = false; var rows:Array = [];
        for (var i:Number = 0; i < entries.length; i++) {
            var entry:Object = entries[i];
            if (entry.raw.AttachTo == undefined && !entry.stateDirty) continue;
            var pose:Array = sample(entry);
            var previous:Array = entry.lastEncodedPose;
            var row:String = entry.lastRow;
            var equal:Boolean = previous != null;
            if (equal) {
                for (var p:Number = 0; p < 8; p++) {
                    if (pose[p] !== previous[p]) { equal = false; break; }
                }
            }
            if (!equal) {
                row = pose.join(",");
                if (row != entry.last) changed = true;
                entry.lastEncodedPose = pose;
                entry.lastRow = row;
            }
            entry.last = row; entry.pose = pose; entry.stateDirty = false; rows.push(row);
        }
        if (!changed) return null;
        return org.flashNight.arki.weather.WorldLightingBridge.getScene() + "|" + revision + "|" + (++sequence) + ";" + rows.join(";");
    }
    public static function setEnabled(key:String, active:Boolean):Boolean {
        for (var i:Number = 0; i < entries.length; i++) if (entries[i].raw.Key == key) {
            entries[i].manual = active ? 1 : 0; entries[i].stateDirty = true; return true;
        }
        return false;
    }
    public static function setWeight(key:String, weight:Number):Boolean {
        if (isNaN(weight) || !isFinite(weight)) return false;
        var clamped:Number = Math.max(0, Math.min(1, Math.round(weight * 64) / 64));
        for (var i:Number = 0; i < entries.length; i++) if (entries[i].raw.Key == key) {
            if (entries[i].manual !== clamped) {
                entries[i].manual = clamped;
                entries[i].stateDirty = true;
            }
            return true;
        }
        return false;
    }
    public static function resolveBaseLightingTier():Number {
        var sys:Object = _root.基建系统;
        if (sys != undefined && sys.infrastructure != undefined) {
            var rawLv:Number = Number(sys.infrastructure["基地供电与照明"]);
            if (!isNaN(rawLv) && isFinite(rawLv)) {
                return Math.max(0, Math.min(3, Math.floor(rawLv)));
            }
            if (sys.dict != undefined) return 0;
        }
        return 3;
    }
    public static function hasActiveBaseLighting():Boolean {
        return basePowerScene;
    }
    private static function baseLightTierFactor(minimum:Number, infraTier:Number):Number {
        var tier:Number = (isNaN(infraTier) || !isFinite(infraTier)) ? 3 : Math.max(0, Math.min(3, Math.floor(infraTier)));
        if (tier < minimum) return 0;
        if (minimum == 3) return 1;
        if (minimum == 2) return tier == 2 ? 0.90625 : 1;
        if (minimum == 1) return tier == 1 ? 0.875 : (tier == 2 ? 0.953125 : 1);
        return tier <= 0 ? 0.84375 : (tier == 1 ? 0.90625 : (tier == 2 ? 0.953125 : 1));
    }
    public static function effectiveAmbientLight(rawLight:Number):Number {
        if (isNaN(rawLight) || !isFinite(rawLight) || rawLight >= 7 || !hasActiveBaseLighting()) {
            return rawLight;
        }
        var infraTier:Number = resolveBaseLightingTier();
        var floor:Number = infraTier <= 0 ? 1.00 : (infraTier == 1 ? 1.15 : (infraTier == 2 ? 1.30 : 1.45));
        var t:Number = Math.max(0, Math.min(1, (rawLight - 1.0) / 6.0));
        var lifted:Number = floor + t * (7.0 - floor);
        return Math.max(rawLight, Math.round(lifted * 100) / 100);
    }
    public static function baseCharacterInfoMinOpacity():Number {
        if (!hasActiveBaseLighting()) return 0;
        return 100;
    }
    public static function syncAmbientLight(lightLevel:Number, gw:MovieClip):Void {
        var level:Number = (isNaN(lightLevel) || !isFinite(lightLevel)) ? 7 : lightLevel;
        var tierWeight:Number = level > 5.5 ? 0 : (level > 3.0 ? 0.55 : 1);
        var beaconWeight:Number = level > 5.5 ? 0.35 : 1;
        var hasBaseLight:Boolean = hasActiveBaseLighting();
        var infraTier:Number = resolveBaseLightingTier();
        if (hasBaseLight && lastBaseLightingTier !== infraTier) {
            lastBaseLightingTier = infraTier;
            org.flashNight.arki.weather.WorldLightingBridge.snapNext();
        }
        for (var j:Number = 0; j < entries.length; j++) {
            if (hasBaseLight && entries[j].tier >= 0) {
                var ambientFactor:Number = entries[j].beacon ? beaconWeight : tierWeight;
                var tierFactor:Number = baseLightTierFactor(entries[j].tier, infraTier);
                var targetWeight:Number = ambientFactor * tierFactor;
                var clamped:Number = Math.max(0, Math.min(1, Math.round(targetWeight * 64) / 64));
                if (entries[j].manual !== clamped) {
                    entries[j].manual = clamped;
                    entries[j].stateDirty = true;
                }
            }
        }
        var targetWorld:MovieClip = gw != null ? gw : _root.gameworld;
        if (targetWorld != null && targetWorld.基地灯光 != undefined) {
            var rig:MovieClip = targetWorld.基地灯光;
            if (rig.灯具层 != undefined) {
                rig.灯具层._visible = true;
                rig.灯具层._alpha = 88;
            }
            if (rig.发光层 != undefined) {
                rig.发光层._visible = tierWeight > 0;
                rig.发光层._alpha = Math.round(tierWeight * 100);
            }
            if (rig.信标层 != undefined) {
                rig.信标层._visible = true;
                rig.信标层._alpha = level > 5.5 ? 45 : 100;
            }
        }
    }
    private static function warn(key:String, reason:String):Void {
        var message:String = sceneKey + "|" + key + "|" + reason;
        if (warnings[message]) return;
        warnings[message] = true;
        trace("[SceneLightBridge] " + message);
        if (_root.server.isSocketConnected) _root.server.sendServerMessage("[SceneLightBridge] " + message);
    }
}
