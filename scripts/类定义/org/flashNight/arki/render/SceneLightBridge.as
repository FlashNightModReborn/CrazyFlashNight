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
    private static var valid:Boolean = true;
    private static var capsSeen:Number = 0;
    private static var capsNative:String = "n/a";
    private static var capsSlv:String = "n/a";
    private static var capsKeys:String = "n/a";
    private static var failureReason:String = "";
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
        var next:Boolean = caps["native"] === true && caps.sceneLightsVersion === 1;
        catalogDigest = org.flashNight.arki.render.WorkerProjectionPolicy.adoptedCatalogDigest(caps.sceneLightsDigest);
        if (enabled != next) {
            enabled = next; dirty = true; revision++;
            for (var i:Number = 0; i < entries.length; i++) entries[i].last = "";
            org.flashNight.arki.weather.WorldLightingBridge.snapNext();
            if (enabled && !valid) fail(failureReason);
        }
    }
    public static function resetScene():Void {
        world = null; identity = null; sources = {}; entries = []; definitions = [];
        configured = false; dirty = true; revision++; sequence = 0; sceneKey = ""; valid = true;
        failureReason = ""; lastBaseLightingTier = -1;
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
        if (prior != undefined && prior.clip && prior.clip.__sceneLightInstanceIdentity === prior.token) { fail("duplicate_anchor"); return; }
        var token:Object = {};
        clip.__sceneLightInstanceIdentity = token;
        _global.ASSetPropFlags(clip, ["__sceneLightInstanceIdentity"], 1, false);
        sources[key] = {clip:clip, token:token};
    }
    // loadMovie replaces target variables. Register the identity only after
    // loadClip's onLoadInit and validate the captured registration/world token.
    public static function loadSource(clip:MovieClip, url:String, key:String):Void {
        if (!ensureWorld()) return;
        if (sources[key] != undefined) { fail("duplicate_anchor"); return; }
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
        if (receipt.world === identity && sources[receipt.key].receipt === receipt) fail("anchor_load_error");
        receipt.loader.removeListener(receipt.listener); receipt.loader = null; receipt.listener = null;
    }
    public static function diag():String {
        return (enabled ? 1 : 0) + "" + (configured ? 1 : 0) + "" + (valid ? 1 : 0)
            + "" + (dirty ? 1 : 0) + "|" + capsSeen + ":" + capsNative + ":" + capsSlv
            + "|" + definitions.length + "|" + sceneKey + "|" + capsKeys;
    }
    public static function configure(base:Array, extra:Array, key:String):Void {
        if (!ensureWorld()) return;
        var merged:Array = []; var indices:Object = {};
        indices.__proto__ = null;
        merge(base, merged, indices); merge(extra, merged, indices);
        if (merged.length > 128) { fail("source_capacity"); return; }
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
        definitions = merged; entries = []; sceneKey = key; configured = true; dirty = true; revision++;
        for (var i:Number = 0; i < merged.length; i++) {
            var raw:Object = merged[i];
            var curve:Array = parseCurve(raw.FrameCurve);
            entries[i] = {raw:raw, id:i+1, curve:curve, manual:1, last:"", pose:null, stateDirty:true};
        }
        org.flashNight.arki.weather.WorldLightingBridge.snapNext();
    }
    private static function merge(list:Array, result:Array, indices:Object):Void {
        for (var i:Number = 0; i < list.length; i++) {
            var raw:Object = ObjectUtil.clone(list[i]);
            var key:String = String(raw.Key);
            if (raw.Key == undefined || key.length == 0 || key.length > 128) { fail("invalid_key"); return; }
            var index = indices[key];
            if (index == undefined) { indices[key] = result.length; result.push(raw); }
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
        if (parts.length > 32) { fail("invalid_curve"); return result; }
        var previous:Number = 0;
        for (var i:Number = 0; i < parts.length; i++) {
            var pair:Array = parts[i].split(":");
            var frame:Number = Number(pair[0]), strength:Number = Number(pair[1]);
            if (pair.length != 2 || !isFinite(frame + strength) || frame <= previous || frame != Math.floor(frame)
                || frame > 10000 || strength < 0 || strength > 1) { fail("invalid_curve"); return []; }
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
            if (!root || root.__sceneLightInstanceIdentity !== source.token || !anchor || anchor._name == undefined) strength = 0;
            else {
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
            fail("invalid_pose"); strength = 0; x = 0; y = 0; dx = 1; dy = 0; size = 1; hand = 1;
        }
        strength = Math.max(0,Math.min(1,strength));
        return [entry.id,x,y,dx,dy,size,strength,hand];
    }
    public static function snapshot():Object {
        if (!enabled || !dirty || !valid) return null;
        var poses:Array = [];
        for (var i:Number = 0; i < entries.length; i++) { entries[i].pose = sample(entries[i]); poses.push(entries[i].pose); }
        return {version:1, revision:revision, key:sceneKey, definitions:definitions, poses:poses};
    }
    public static function sent():Void { if (enabled && valid) dirty = false; }
    public static function flush():String {
        if (!enabled || !configured || !valid || !ensureWorld()) return null;
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
        if (!changed || !valid) return null;
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
    public static function resolveBaseLightingTier(autoUnlock:Boolean):Number {
        var sys:Object = _root.基建系统;
        if (sys != undefined && sys.infrastructure != undefined) {
            if (autoUnlock === true && _root.当前为战斗地图 !== true
                    && sys.dict != undefined && sys.dict["基地供电与照明"] != null
                    && sys.infrastructure["基地供电与照明"] == null) {
                sys.infrastructure["基地供电与照明"] = 0;
                if (typeof _root.发布消息 == "function") {
                    _root.发布消息("发现新的基建项目：基地供电与照明");
                }
            }
            var rawLv:Number = Number(sys.infrastructure["基地供电与照明"]);
            if (!isNaN(rawLv) && isFinite(rawLv)) {
                return Math.max(0, Math.min(3, Math.floor(rawLv)));
            }
            if (sys.dict != undefined) return 0;
        }
        return 3;
    }
    public static function hasActiveBaseLighting():Boolean {
        for (var i:Number = 0; i < entries.length; i++) {
            var checkKey:String = String(entries[i].raw.Key);
            if (checkKey.indexOf("gate-") === 0 || checkKey.indexOf("garage-") === 0 || checkKey.indexOf("roof-") === 0) {
                return true;
            }
        }
        return false;
    }
    public static function baseLightTierFactor(key:String, infraTier:Number):Number {
        var tier:Number = (isNaN(infraTier) || !isFinite(infraTier)) ? 3 : Math.max(0, Math.min(3, Math.floor(infraTier)));
        if (key === "gate-emblem-accent" || key === "gate-perimeter-guide-e"
                || key === "garage-bpk-underglow" || key === "garage-showroom-accent-se"
                || key === "roof-helipad-approach-c" || key === "roof-perimeter-accent-e") {
            return tier < 3 ? 0 : 1;
        }
        if (key === "gate-cam-searchlight" || key === "gate-watchtower-east-beam"
                || key === "garage-truss-flood-c"
                || key === "roof-helipad-flood-l" || key === "roof-helipad-flood-r") {
            return tier < 2 ? 0 : (tier == 2 ? 0.90625 : 1);
        }
        if (key === "gate-bunker-wall-wash"
                || key === "garage-truss-flood-w" || key === "garage-truss-flood-e"
                || key === "roof-bounty-wall-wash") {
            return tier < 1 ? 0 : (tier == 1 ? 0.875 : (tier == 2 ? 0.953125 : 1));
        }
        return tier <= 0 ? 0.84375 : (tier == 1 ? 0.90625 : (tier == 2 ? 0.953125 : 1));
    }
    public static function effectiveAmbientLight(rawLight:Number):Number {
        if (isNaN(rawLight) || !isFinite(rawLight) || rawLight >= 7 || !hasActiveBaseLighting()) {
            return rawLight;
        }
        var infraTier:Number = resolveBaseLightingTier(false);
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
        var infraTier:Number = resolveBaseLightingTier(hasBaseLight);
        if (hasBaseLight && lastBaseLightingTier !== infraTier) {
            lastBaseLightingTier = infraTier;
            org.flashNight.arki.weather.WorldLightingBridge.snapNext();
        }
        for (var j:Number = 0; j < entries.length; j++) {
            var key:String = String(entries[j].raw.Key);
            if (key.indexOf("gate-") === 0 || key.indexOf("garage-") === 0 || key.indexOf("roof-") === 0) {
                var isBeacon:Boolean = (key === "roof-antenna-beacon" || key === "gate-outpost-beacon");
                var ambientFactor:Number = isBeacon ? beaconWeight : tierWeight;
                var tierFactor:Number = baseLightTierFactor(key, infraTier);
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
    private static function fail(reason:String):Void {
        valid = false; failureReason = reason;
        trace("[SceneLightBridge] " + reason);
        if (enabled && _root.server.isSocketConnected) _root.server.sendSocketMessage("Vscene|"+reason);
    }
}
