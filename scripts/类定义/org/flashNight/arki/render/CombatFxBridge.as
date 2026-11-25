import org.flashNight.arki.render.DecalStampQueue;
import org.flashNight.arki.render.VisualRandom;
import org.flashNight.arki.audio.AudioBridge;
import org.flashNight.arki.render.BloodVisualBridge;

// 只提交出生事件与游戏时钟；不创建活动弹壳 MC，也不逐粒子更新或回传。
import org.flashNight.arki.render.EquipmentLightBridge;
import org.flashNight.arki.render.SceneLightBridge;

class org.flashNight.arki.render.CombatFxBridge {
    private static var enabled:Boolean = false;
    private static var worldLights:Boolean = false;
    private static var generation:Number = -1;
    private static var digest:String = "";
    private static var byName:Object = {};
    private static var styles:Array = [];
    private static var sounds:Object = {};
    private static var birthSounds:Object = {};
    private static var epoch:Number = 0;
    private static var sequence:Number = 0;
    private static var gameTick:Number = 0;
    private static var lastEvent:Number = 0;
    private static var spawns:Array = [];
    private static var acks:Array = [];
    private static var impacts:Array = [];
    private static var impactDropped:Number = 0;
    private static var dropped:Number = 0;
    private static var shakeCapVersion:Number = 0;
    private static var shakeLastSeenGrant:Number = 0;
    private static var shakeGrant:Number = 0;
    private static var shakePaused:Boolean = false;
    private static var shakeAwaitingGrant:Boolean = false;
    private static var shakeGrants:Array = [0,0,0,0,0,0,0,0];
    private static var shakeProfiles:Array = [0,0,0,0,0,0,0,0];
    private static var shakeXs:Array = [0,0,0,0,0,0,0,0];
    private static var shakeYs:Array = [0,0,0,0,0,0,0,0];
    private static var shakeCount:Number = 0;
    private static var shakeDropped:Number = 0;
    private static var shakeTailRemaining:Number = 0;
    private static var shakeTailNeedsClear:Boolean = false;
    private static var shakeMaxProfile:Number = 7;
    private static var shakeTailLimit:Number = 31;
    private static var shakePriority:Array = [0,1,2,5,3,6,7,4];
    private static var shakeScreenWide:Object = null;
    private static var shakeBulletMap:Object = {};
    private static var shakeEffectMap:Object = {};

    public static function installedCatalogDigest(expectedGeneration:Number):String {
        return enabled && generation == expectedGeneration ? org.flashNight.arki.render.WorkerProjectionPolicy.adoptedCatalogDigest(digest) : "";
    }
    public static function isDecorationClean():Boolean {
        return spawns.length == 0 && impacts.length == 0 && acks.length == 0 && shakeCount == 0
            && DecalStampQueue.getStats().pending == 0 && BloodVisualBridge.getStats().queued == 0
            && BloodVisualBridge.getStats().pendingStamps == 0;
    }

    public static function configure(caps:Object):Void {
        if (caps == null || caps.version !== 1 || typeof caps.generation != "number"
            || !isFinite(caps.generation) || caps.generation < 1 || caps.generation > 1000000000
            || caps.generation != Math.floor(caps.generation)
            || !(caps.styles instanceof Array) || (caps.styles.length < 1 && caps["native"] === true) || caps.styles.length > 64
            || typeof caps.digest != "string" || (caps.digest.length != 64 && !(caps.styles.length == 0 && caps.digest === ""))) {
            disconnect();
            return;
        }
        if (caps.generation < generation) return;
        var names:Object = {};
        var next:Array = [];
        var nextSounds:Object = {};
        var nextBirthSounds:Object = {};
        for (var i:Number = 0; i < caps.styles.length; i++) {
            var item:Object = caps.styles[i];
            if (item.index !== i || typeof item.linkage != "string" || item.linkage.length < 1
                || item.linkage.length > 128 || (item.kind != "casing" && item.kind != "muzzle" && item.kind != "impact" && item.kind != "blood")
                || names[item.linkage] != undefined
                || (item.kind == "casing" && item.linkage.substr(item.linkage.length - 2) != "弹壳")) {
                disconnect();
                return;
            }
            next[i] = item;
            names[item.linkage] = item;
            if(item.variantSounds instanceof Array && item.variantSounds.length<=16)
                for(var soundIndex:Number=0;soundIndex<item.variantSounds.length;soundIndex++) {
                    var sound:String=item.variantSounds[soundIndex];
                    if(typeof sound=="string" && sound.length>0 && sound.length<=128
                        && sound.indexOf("..")<0 && sound.indexOf("/")<0 && sound.indexOf("\\")<0
                        && sound.indexOf(":")<0) {
                        if(item.soundAtBirth===true)nextBirthSounds[sound]=true;
                        else nextSounds[sound]=true;
                    }
                }
        }
        var active:Boolean = caps["native"] === true;
        if (generation != caps.generation) {
            resetScene();
            shakeLastSeenGrant = 0;
            shakeAwaitingGrant = false;
            shakePaused = _root.暂停 ? true : false;
        } else if (enabled != active || digest != caps.digest) {
            resetDecorations();
        }
        worldLights = caps.worldLights == undefined ? active : caps.worldLights === true;
        if (digest != caps.digest) DecalStampQueue.clearCache();
        generation = caps.generation;
        digest = caps.digest;
        byName = names;
        styles = next;
        sounds = nextSounds;
        birthSounds = nextBirthSounds;
        enabled = active;
        var blood:Object=names["子弹碎片-飞血"];
        BloodVisualBridge.configure(active && caps.bloodVersion === 1,
            blood != undefined && blood.kind == "blood" && caps.bloodVersion === 1 ? blood.index : -1);
        EquipmentLightBridge.configure(caps);
        SceneLightBridge.configureCaps(caps);
        configureShake(caps);
    }

    private static function resetShakeConfigDefaults():Void {
        shakeMaxProfile = 7;
        shakeTailLimit = 31;
        shakePriority = [0,1,2,5,3,6,7,4];
        var wide:Object = {};
        wide[7] = true;
        shakeScreenWide = wide;
        shakeBulletMap = {};
        shakeEffectMap = {};
    }

    private static function parseShakeBindings(raw:Object, maxProfile:Number, totalRef:Object):Object {
        if (raw == null || typeof raw != "object" || (raw instanceof Array)) return null;
        var out:Object = {};
        for (var key:String in raw) {
            if (!raw.hasOwnProperty(key)) continue;
            if (typeof key != "string" || key.length < 1 || key.length > 128) return null;
            var pid:Number = raw[key];
            if (typeof pid != "number" || !isFinite(pid) || pid != Math.floor(pid) || pid < 1 || pid > maxProfile) return null;
            totalRef.count++;
            if (totalRef.count > 256) return null;
            out[key] = pid;
        }
        return out;
    }

    private static function applyShakeConfig(cfg:Object):Boolean {
        if (cfg == undefined) {
            resetShakeConfigDefaults();
            return true;
        }
        if (cfg == null || typeof cfg != "object" || (cfg instanceof Array)) return false;
        var nextMax:Number = cfg.maxProfile;
        var nextTail:Number = cfg.tailTicks;
        if (typeof nextMax != "number" || !isFinite(nextMax) || nextMax != Math.floor(nextMax) || nextMax < 1 || nextMax > 16) return false;
        if (typeof nextTail != "number" || !isFinite(nextTail) || nextTail != Math.floor(nextTail) || nextTail < 2 || nextTail > 121) return false;
        var rawPrio:Array = cfg.priorities;
        if (!(rawPrio instanceof Array) || rawPrio.length != nextMax + 1 || rawPrio[0] !== 0) return false;
        var nextPrio:Array = [0];
        for (var i:Number = 1; i <= nextMax; i++) {
            var prio:Number = rawPrio[i];
            if (typeof prio != "number" || !isFinite(prio) || prio != Math.floor(prio) || prio < 1 || prio > 100) return false;
            nextPrio[i] = prio;
        }
        var rawWide:Array = cfg.screenWide;
        if (!(rawWide instanceof Array) || rawWide.length > nextMax) return false;
        var nextWide:Object = {};
        for (var w:Number = 0; w < rawWide.length; w++) {
            var wid:Number = rawWide[w];
            if (typeof wid != "number" || !isFinite(wid) || wid != Math.floor(wid) || wid < 1 || wid > nextMax) return false;
            nextWide[wid] = true;
        }
        var totalRef:Object = {count:0};
        var nextBullets:Object = parseShakeBindings(cfg.bullets, nextMax, totalRef);
        if (nextBullets == null) return false;
        var nextEffects:Object = parseShakeBindings(cfg.effects, nextMax, totalRef);
        if (nextEffects == null) return false;
        shakeMaxProfile = nextMax;
        shakeTailLimit = nextTail;
        shakePriority = nextPrio;
        shakeScreenWide = nextWide;
        shakeBulletMap = nextBullets;
        shakeEffectMap = nextEffects;
        return true;
    }

    private static function configureShake(caps:Object):Void {
        var nextGrant:Number = caps.shakeGrant;
        if (caps.shakeVersion !== 1 || typeof nextGrant != "number" || !isFinite(nextGrant)
            || nextGrant != Math.floor(nextGrant) || nextGrant < 1 || nextGrant > 1000000000) {
            shakeCapVersion = 0;
            shakeGrant = 0;
            clearShakeQueueAndTail();
            return;
        }
        if (!applyShakeConfig(caps.shakeConfig)) {
            shakeCapVersion = 0;
            shakeGrant = 0;
            clearShakeQueueAndTail();
            resetShakeConfigDefaults();
            return;
        }
        shakeCapVersion = 1;
        // Repeated and stale grants cannot reopen a locally revoked grant.
        if (nextGrant <= shakeLastSeenGrant) return;
        shakeLastSeenGrant = nextGrant;
        clearShakeQueueAndTail();
        var localPaused:Boolean = shakePaused || (_root.暂停 ? true : false);
        shakeAwaitingGrant = localPaused;
        shakeGrant = localPaused ? 0 : nextGrant;
    }

    private static function clearShakeQueueAndTail():Void {
        shakeCount = 0;
        shakeTailRemaining = 0;
        shakeTailNeedsClear = false;
    }

    public static function lightTick():Number { return gameTick; }
    // Births before flush first appear at age zero in its upcoming snapshot.
    public static function lightBirthTick():Number { return gameTick + (_root.暂停 ? 0 : 1); }
    public static function isEnabled():Boolean { return enabled; }
    public static function disconnect():Void {
        enabled = false;
        worldLights = false;
        generation = -1;
        EquipmentLightBridge.disconnect();
        SceneLightBridge.configureCaps({});
        resetScene();
        BloodVisualBridge.disconnect();
        shakeCapVersion = 0;
        shakeLastSeenGrant = 0;
        shakeAwaitingGrant = false;
        resetShakeConfigDefaults();
    }

    public static function resetScene():Void {
        clearShakeQueueAndTail();
        shakeGrant = 0;
        shakeAwaitingGrant = true;
        gameTick = 0;
        resetDecorations();
        EquipmentLightBridge.resetScene();
    }
    private static function resetDecorations():Void {
        epoch++;
        sequence = 0;
        lastEvent = 0;
        spawns.length = 0;
        impacts.length = 0;
        acks.length = 0;
        DecalStampQueue.resetScene();
        BloodVisualBridge.resetScene();
    }

    public static function onPauseChanged(newVal:Boolean, oldVal:Boolean):Void {
        var nextPaused:Boolean = newVal ? true : false;
        if (nextPaused == shakePaused) return;
        shakePaused = nextPaused;
        shakeGrant = 0;
        shakeAwaitingGrant = true;
        if (nextPaused) {
            shakeCount = 0;
            if (!enabled && !worldLights && shakeTailRemaining > 0) {
                shakeTailRemaining = 0;
                shakeTailNeedsClear = true;
            }
        }
    }

    public static function tryShake(profileId:Number, worldX:Number, worldY:Number):Boolean {
        if (org.flashNight.arki.render.WorkerProjectionPolicy.isNone("combatDecoration")) return false;
        if (shakeCapVersion !== 1 || shakeGrant <= 0 || shakePaused || shakeAwaitingGrant || _root.暂停) return false;
        if (!(profileId >= 1 && profileId <= shakeMaxProfile && profileId === Math.floor(profileId))) return false;
        if (shakeScreenWide != null ? shakeScreenWide[profileId] === true : profileId == 7) {
            // Screen-wide events do not use position, but their wire coordinates must still be valid.
            if (typeof worldX != "number" || !isFinite(worldX) || Math.abs(worldX) > 1000000) worldX = 0;
            if (typeof worldY != "number" || !isFinite(worldY) || Math.abs(worldY) > 1000000) worldY = 0;
        } else if (typeof worldX != "number" || typeof worldY != "number" || !isFinite(worldX + worldY)
            || Math.abs(worldX) > 1000000 || Math.abs(worldY) > 1000000) {
            return false;
        }

        var slot:Number;
        if (shakeCount < 8) {
            slot = shakeCount++;
        } else {
            shakeDropped++;
            var profiles:Array = shakeProfiles;
            var priorities:Array = shakePriority;
            slot = 0;
            var lowestPriority:Number = priorities[profiles[slot]];
            for (var i:Number = 1; i < 8; i++) {
                var priority:Number = priorities[profiles[i]];
                if (priority < lowestPriority) {
                    lowestPriority = priority;
                    slot = i;
                }
            }
            if (priorities[profileId] <= lowestPriority) slot = -1;
        }
        if (slot >= 0) {
            shakeGrants[slot] = shakeGrant;
            shakeProfiles[slot] = profileId;
            shakeXs[slot] = worldX;
            shakeYs[slot] = worldY;
        }
        if (!enabled && !worldLights) {
            shakeTailRemaining = shakeTailLimit;
            shakeTailNeedsClear = false;
        }
        return true;
    }

    public static function tryShakePhase(profileId:Number, worldX:Number, worldY:Number):Boolean {
        return tryShake(profileId, worldX, worldY);
    }

    public static function tryBulletShake(baseAsset:String, worldX:Number, worldY:Number):Boolean {
        if (shakeCapVersion !== 1 || shakeGrant <= 0 || baseAsset == undefined) return false;
        var profileId:Number = shakeBulletMap[baseAsset];
        if (profileId == undefined) return false;
        return tryShake(profileId, worldX, worldY);
    }

    public static function tryEffectShake(effectType:String, worldX:Number, worldY:Number):Boolean {
        if (shakeCapVersion !== 1 || shakeGrant <= 0 || effectType == undefined) return false;
        var profileId:Number = shakeEffectMap[effectType];
        if (profileId == undefined) return false;
        return tryShake(profileId, worldX, worldY);
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
        var style:Object = byName[linkage];
        if (style == undefined || style.kind != "casing") return false;
        if (org.flashNight.arki.render.WorkerProjectionPolicy.isNone("combatDecoration")) return true;
        // 已接管的纯装饰在暂停/断连时丢弃，不重新分配 AS2 MC。
        if (!enabled) return true;
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
        var style:Object = byName[linkage];
        if (style == undefined || style.kind != "muzzle") return false;
        if (org.flashNight.arki.render.WorkerProjectionPolicy.isNone("combatDecoration")) return true;
        // 已接管的纯装饰在暂停/断连时丢弃，不重新分配 AS2 MC。
        if (!enabled) return true;
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
        var style:Object = byName[linkage];
        if (style == undefined || style.kind != "impact") return false;
        if (org.flashNight.arki.render.WorkerProjectionPolicy.isNone("combatDecoration")) return true;
        // Nested random rotation is representable by the current quad for unit parent scale.
        if (style.randomRotation === true && Math.abs(scale) != 100) return false;
        // 已接管的纯装饰在暂停/断连时丢弃，不重新分配 AS2 MC。
        if (!enabled) return true;
        if (_root.暂停 || (!_root.是否视觉元素 && !forceTrigger) || !visible(x, y)) return true;
        if (!isFinite(x + y + scale) || Math.abs(scale) > 1000 || scale == 0) return true;
        if (style.skipOriginYZero === true && y == 0) return true;
        // Auditory hit feedback is admitted with the hit, before a sprite-only cap.
        if(style.soundAtBirth===true)playImpactBirthSound(style,seed);
        if (impacts.length >= 32) { impactDropped++; return true; }
        impacts[impacts.length] = "i," + style.index + "," + x + "," + y + "," + scale + ",100,0," + seed + ",0";
        return true;
    }

    private static function playImpactBirthSound(style:Object,seed:Number):Void {
        if(style.soundAtBirth!==true || !(style.variantSounds instanceof Array)
            || style.variantSounds.length<1 || style.variantSounds.length>16)return;
        var sound:String=style.variantSounds[seed%style.variantSounds.length];
        if(typeof sound!="string" || birthSounds[sound]!==true)return;
        // The root manager owns mute semantics. A bare focused fixture may omit it.
        if(typeof _root.播放音效=="function")_root.播放音效(sound);
        else AudioBridge.playSound(sound);
    }

    public static function receiveEvents(data:Object):Void {
        if (org.flashNight.arki.render.WorkerProjectionPolicy.isNone("combatDecoration")) return;
        if (!enabled || data == null || data.version !== 1 || data.generation !== generation || data.epoch !== epoch
            || typeof data.sequence != "number" || !isFinite(data.sequence) || data.sequence <= lastEvent
            || data.sequence != Math.floor(data.sequence) || data.sequence > 1000000000
            || !(data.settled instanceof Array) || data.settled.length > 8
            || (data.bloodLandings != undefined && (!(data.bloodLandings instanceof Array) || data.bloodLandings.length > 8))
            || (data.sounds != undefined && (!(data.sounds instanceof Array) || data.sounds.length > 8))) return;
        lastEvent = data.sequence;
        if(data.bloodLandings != undefined)BloodVisualBridge.receiveLandings(data.bloodLandings);
        if(data.sounds instanceof Array)
            for(var soundIndex:Number=0;soundIndex<data.sounds.length;soundIndex++) {
                var sound:String=data.sounds[soundIndex];
                if(typeof sound=="string" && sounds[sound]===true)AudioBridge.playSound(sound);
            }
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
        var baseActive:Boolean = enabled || worldLights;
        var shakeOnlyActive:Boolean = !baseActive && shakeCapVersion === 1
            && (shakeCount > 0 || shakeTailRemaining > 0 || shakeTailNeedsClear);
        if (!baseActive && !shakeOnlyActive) return;
        var paused:Boolean = _root.暂停 ? true : false;
        if (paused) {
            shakeCount = 0;
            shakeGrant = 0;
            shakeAwaitingGrant = true;
            shakePaused = true;
        } else {
            gameTick++;
            if (enabled && !org.flashNight.arki.render.WorkerProjectionPolicy.isNone("combatDecoration")) {
                var drawn:Array = DecalStampQueue.flush();
                for (var i:Number = 0; i < drawn.length && acks.length < 64; i++) acks[acks.length] = drawn[i];
            }
        }
        sequence++;
        var payload:String = epoch + "|" + sequence + "|" + gameTick + "|" + (paused ? 1 : 0);
        for (var spawnIndex:Number = 0; spawnIndex < spawns.length; spawnIndex++) payload += ";" + spawns[spawnIndex];
        for (var hitIndex:Number = 0; hitIndex < impacts.length; hitIndex++) payload += ";" + impacts[hitIndex];
        for (var ackIndex:Number = 0; ackIndex < acks.length; ackIndex++) payload += ";" + acks[ackIndex];
        if (enabled) payload += BloodVisualBridge.flush();
        spawns.length = 0;
        impacts.length = 0;
        acks.length = 0;
        payload += EquipmentLightBridge.payload();
        if (!paused && shakeCount > 0 && !org.flashNight.arki.render.WorkerProjectionPolicy.isNone("combatDecoration")) {
            for (var shakeIndex:Number = 0; shakeIndex < shakeCount; shakeIndex++) {
                var record:String = ";h," + shakeGrants[shakeIndex] + "," + shakeProfiles[shakeIndex]
                    + "," + shakeXs[shakeIndex] + "," + shakeYs[shakeIndex];
                if (length(payload) + length(record) <= 32768) payload += record;
                else shakeDropped++;
            }
        }
        shakeCount = 0;
        if (shakeOnlyActive) {
            if (paused || shakeTailNeedsClear) {
                shakeTailRemaining = 0;
                shakeTailNeedsClear = false;
            } else if (shakeTailRemaining > 0) {
                shakeTailRemaining--;
            }
        }
        org.flashNight.arki.render.FrameBroadcaster.setCombatFxPayload(payload);
    }

    public static function getStats():Object {
        return {enabled:enabled, epoch:epoch, queued:spawns.length, queuedImpacts:impacts.length,
            dropped:dropped, impactDropped:impactDropped, stamp:DecalStampQueue.getStats(),
            shakeVersion:shakeCapVersion, shakeGrant:shakeGrant, shakeQueued:shakeCount,
            shakeDropped:shakeDropped, shakeTail:shakeTailRemaining};
    }
    /** Source callers may avoid even coordinates for an audited casing. Unknown styles keep their old route. */
    public static function consumeShellWithoutProjection(linkage:String):Boolean {
        if (!org.flashNight.arki.render.WorkerProjectionPolicy.isNone("combatDecoration")) return false;
        var style:Object=byName[linkage];if(style==undefined || style.kind!="casing")return false;
        VisualRandom.eventSeed(2);return true;
    }
}
