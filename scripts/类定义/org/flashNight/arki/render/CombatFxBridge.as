import org.flashNight.arki.render.DecalStampQueue;
import org.flashNight.arki.render.VisualRandom;
import org.flashNight.arki.audio.AudioBridge;

// 只提交出生事件与游戏时钟；不创建活动弹壳 MC，也不逐粒子更新或回传。
class org.flashNight.arki.render.CombatFxBridge {
    private static var enabled:Boolean = false;
    private static var generation:Number = -1;
    private static var digest:String = "";
    private static var byName:Object = {};
    private static var styles:Array = [];
    private static var epoch:Number = 0;
    private static var sequence:Number = 0;
    private static var gameTick:Number = 0;
    private static var lastEvent:Number = 0;
    private static var spawns:Array = [];
    private static var acks:Array = [];
    private static var impacts:Array = [];
    private static var impactDropped:Number = 0;
    private static var dropped:Number = 0;

    public static function configure(caps:Object):Void {
        if (caps == null || caps.version !== 1 || typeof caps.generation != "number"
            || !isFinite(caps.generation) || caps.generation < 1 || caps.generation > 1000000000
            || caps.generation != Math.floor(caps.generation)
            || !(caps.styles instanceof Array) || caps.styles.length < 1 || caps.styles.length > 64
            || typeof caps.digest != "string" || caps.digest.length != 64) {
            disconnect();
            return;
        }
        if (caps.generation < generation) return;
        var names:Object = {};
        var next:Array = [];
        for (var i:Number = 0; i < caps.styles.length; i++) {
            var item:Object = caps.styles[i];
            if (item.index !== i || typeof item.linkage != "string" || item.linkage.length < 1
                || item.linkage.length > 128 || (item.kind != "casing" && item.kind != "muzzle" && item.kind != "impact")
                || names[item.linkage] != undefined
                || (item.kind == "casing" && item.linkage.substr(item.linkage.length - 2) != "弹壳")) {
                disconnect();
                return;
            }
            next[i] = item;
            names[item.linkage] = item;
        }
        var active:Boolean = caps["native"] === true;
        if (generation != caps.generation || enabled != active || digest != caps.digest) resetScene();
        if (digest != caps.digest) DecalStampQueue.clearCache();
        generation = caps.generation;
        digest = caps.digest;
        byName = names;
        styles = next;
        enabled = active;
    }

    public static function disconnect():Void { enabled = false; generation = -1; resetScene(); }

    public static function resetScene():Void {
        epoch++;
        sequence = 0;
        gameTick = 0;
        lastEvent = 0;
        spawns.length = 0;
        impacts.length = 0;
        acks.length = 0;
        DecalStampQueue.resetScene();
    }

    private static function visible(x:Number, y:Number):Boolean {
        var world:MovieClip = _root.gameworld;
        var sx:Number = world._xscale * 0.01;
        var px:Number = world._x + x * sx;
        var py:Number = world._y + y * sx;
        return world && px >= 0 && px <= Stage.width && py >= 0 && py <= Stage.height;
    }

    public static function tryShell(linkage:String, x:Number, y:Number, scale:Number, count:Number, ground:Number):Boolean {
        var seed:Number = VisualRandom.eventSeed(2);
        if (!enabled) return false;
        var style:Object = byName[linkage];
        if (style == undefined || style.kind != "casing") return false;
        if (_root.暂停 || !visible(x, y)) return true;
        if (!isFinite(x + y + scale + count + ground) || count < 1 || Math.abs(scale) > 1000 || scale == 0) return true;
        if (spawns.length >= 32) { dropped++; return true; }
        count = Math.floor(count > 64 ? 64 : count);
        spawns[spawns.length] = "s," + style.index + "," + x + "," + y + "," + scale + ","
            + Math.abs(scale) + "," + ground + "," + count + "," + seed + ",0";
        return true;
    }

    public static function tryMuzzle(linkage:String, x:Number, y:Number, scale:Number, rotation:Number):Boolean {
        var seed:Number = VisualRandom.eventSeed(1);
        if (!enabled) return false;
        var style:Object = byName[linkage];
        if (style == undefined || style.kind != "muzzle") return false;
        if (_root.暂停 || !_root.是否视觉元素 || !visible(x, y)) return true;
        if (!isFinite(rotation)) rotation = 0;
        if (!isFinite(x + y + scale) || Math.abs(scale) > 1000 || scale == 0) return true;
        if (style.skipOriginYZero === true && y == 0) return true;
        if (spawns.length >= 32) { dropped++; return true; }
        // EffectSystem 原接口只继承 X 缩放；Y 保持素材的 100%。
        spawns[spawns.length] = "m," + style.index + "," + x + "," + y + "," + scale + ",100,"
            + rotation + "," + seed + ",0";
        return true;
    }

    // Only audited fire-and-forget hit callers opt in; legacy callers may still need a MovieClip.
    public static function tryImpact(linkage:String, x:Number, y:Number, scale:Number, forceTrigger:Boolean):Boolean {
        var seed:Number = VisualRandom.eventSeed(3);
        if (!enabled) return false;
        var style:Object = byName[linkage];
        if (style == undefined || style.kind != "impact") return false;
        if (_root.暂停 || (!_root.是否视觉元素 && !forceTrigger) || !visible(x, y)) return true;
        if (!isFinite(x + y + scale) || Math.abs(scale) > 1000 || scale == 0) return true;
        if (style.skipOriginYZero === true && y == 0) return true;
        if (impacts.length >= 32) { impactDropped++; return true; }
        impacts[impacts.length] = "i," + style.index + "," + x + "," + y + "," + scale + ",100,0," + seed + ",0";
        return true;
    }

    public static function receiveEvents(data:Object):Void {
        if (!enabled || data.version !== 1 || data.generation !== generation || data.epoch !== epoch
            || typeof data.sequence != "number" || !isFinite(data.sequence) || data.sequence <= lastEvent
            || !(data.settled instanceof Array) || data.settled.length > 8) return;
        lastEvent = data.sequence;
        var hits:Number = Number(data.groundHits);
        if (isFinite(hits) && hits > 0 && hits <= 3) {
            for (var h:Number = 0; h < hits; h++) AudioBridge.playSound("shell-hit-ground.mp3");
        }
        for (var i:Number = 0; i < data.settled.length; i++) {
            var pose:Array = data.settled[i];
            if (!(pose instanceof Array) || pose.length != 7) continue;
            var valid:Boolean = true;
            for (var k:Number = 0; k < 7; k++) {
                if (typeof pose[k] != "number" || !isFinite(pose[k])) valid = false;
            }
            if (!valid || pose[0] < 1 || pose[0] > 2147483647 || pose[0] != Math.floor(pose[0])
                || pose[1] != Math.floor(pose[1]) || pose[1] < 0 || pose[1] >= styles.length
                || Math.abs(pose[2]) > 1000000 || Math.abs(pose[3]) > 1000000
                || Math.abs(pose[4]) > 1000000 || Math.abs(pose[5]) > 1000 || Math.abs(pose[6]) > 1000) continue;
            var style:Object = styles[pose[1]];
            if (style.kind != "casing") continue;
            if (!DecalStampQueue.enqueue(pose, style.linkage) && acks.length < 64)
                acks[acks.length] = "a," + pose[0] + ",0";
        }
    }

    public static function flush():Void {
        if (!enabled) return;
        var paused:Boolean = _root.暂停 ? true : false;
        if (!paused) {
            gameTick++;
            var drawn:Array = DecalStampQueue.flush();
            for (var i:Number = 0; i < drawn.length && acks.length < 64; i++) acks[acks.length] = drawn[i];
        }
        sequence++;
        var payload:String = epoch + "|" + sequence + "|" + gameTick + "|" + (paused ? 1 : 0);
        for (var spawnIndex:Number = 0; spawnIndex < spawns.length; spawnIndex++) payload += ";" + spawns[spawnIndex];
        for (var hitIndex:Number = 0; hitIndex < impacts.length; hitIndex++) payload += ";" + impacts[hitIndex];
        for (var ackIndex:Number = 0; ackIndex < acks.length; ackIndex++) payload += ";" + acks[ackIndex];
        spawns.length = 0;
        impacts.length = 0;
        acks.length = 0;
        org.flashNight.arki.render.FrameBroadcaster.setCombatFxPayload(payload);
    }

    public static function getStats():Object {
        return {enabled:enabled, epoch:epoch, queued:spawns.length, queuedImpacts:impacts.length, dropped:dropped, impactDropped:impactDropped, stamp:DecalStampQueue.getStats()};
    }
}
