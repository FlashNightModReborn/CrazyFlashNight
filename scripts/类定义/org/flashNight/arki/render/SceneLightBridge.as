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
    private static var failureReason:String = "";

    public static function configureCaps(caps:Object):Void {
        var next:Boolean = caps["native"] === true && caps.sceneLightsVersion === 1;
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
        failureReason = "";
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
    public static function configure(base:Array, extra:Array, key:String):Void {
        if (!ensureWorld()) return;
        var merged:Array = []; var indices:Object = {};
        indices.__proto__ = null;
        merge(base, merged, indices); merge(extra, merged, indices);
        if (merged.length > 128) { fail("source_capacity"); return; }
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
            var pose:Array = sample(entry); var row:String = pose.join(",");
            if (row != entry.last) changed = true;
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
    private static function fail(reason:String):Void {
        valid = false; failureReason = reason;
        trace("[SceneLightBridge] " + reason);
        if (enabled && _root.server.isSocketConnected) _root.server.sendSocketMessage("Vscene|"+reason);
    }
}
