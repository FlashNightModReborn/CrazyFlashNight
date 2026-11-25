import flash.display.BitmapData;
import org.flashNight.arki.render.CombatFxBridge;
import org.flashNight.arki.render.DecalStampQueue;
import org.flashNight.arki.render.FrameBroadcaster;
import org.flashNight.arki.render.VisualRandom;
import org.flashNight.arki.component.Effect.EffectSystem;
import org.flashNight.arki.component.Effect.BulletEffectHandler;
import org.flashNight.arki.component.Effect.BitmapEffectRenderer;
import org.flashNight.arki.render.BloodVisualBridge;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

class org.flashNight.arki.render.CombatFxBridgeTest {
    private static var passed:Number;
    private static var failed:Number;
    public static var made:Number;
    public static var packet:String;
    public static var lastLinkage:String;
    public static var lastEffect:MovieClip;
    public static var heard:Array;
    public static var birthHeard:Array;

    private static function check(ok:Boolean, name:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] CombatFxBridgeTest: " + name); }
    }

    private static function flushShakeFrame():String {
        packet = "";
        CombatFxBridge.flush();
        FrameBroadcaster.send();
        var start:Number = packet.indexOf("\x06");
        if (start < 0) return "";
        return packet.substr(start + 1).split("\x07")[0].split("\x08")[0].split("\x09")[0];
    }

    private static function testShakeTail():Void {
        check(flushShakeFrame() == "", "a newly granted shake-only bridge does not emit idle F6");
        var tick:Number = CombatFxBridge.lightTick();
        var epoch:Number = CombatFxBridge.getStats().epoch;
        check(CombatFxBridge.tryShake(2, 25, -40) && CombatFxBridge.getStats().shakeTail == 31,
            "a shake birth starts the bounded shake-only window");
        var frame:Array = flushShakeFrame().split(";");
        var firstHeader:Array = frame[0].split("|");
        var sequence:Number = Number(firstHeader[1]);
        check(frame.length == 2 && frame[1] == "h,5,2,25,-40"
            && Number(firstHeader[0]) == epoch && Number(firstHeader[2]) == tick + 1 && firstHeader[3] == "0",
            "the shake-only birth travels with its enqueue grant and active F6 header");
        var contiguous:Boolean = true;
        for (var i:Number = 1; i < 31; i++) {
            var expected:String = epoch + "|" + (sequence + i) + "|" + (tick + 1 + i) + "|0";
            if (flushShakeFrame() != expected) contiguous = false;
        }
        check(contiguous && CombatFxBridge.getStats().shakeTail == 0,
            "exactly 30 header-only frames follow the birth with no h replay");
        check(flushShakeFrame() == "" && flushShakeFrame() == "", "shake-only F6 stops at the end of the window");
    }

    private static function testShakeQueue():Void {
        var projectionApi:Object = org.flashNight.arki.render.WorkerProjectionPolicy;
        var oldIsNone:Function = projectionApi.isNone;
        projectionApi.isNone = function(name:String):Boolean { return name == "combatDecoration"; };
        check(!CombatFxBridge.tryShake(2, 1, 2) && CombatFxBridge.isDecorationClean() && flushShakeFrame() == "",
            "worker none cannot produce shake or start an F6 window");
        projectionApi.isNone = oldIsNone;
        check(CombatFxBridge.tryShake(2, 1, 2) && !CombatFxBridge.isDecorationClean(),
            "a pending shake is part of decoration cleanliness");
        projectionApi.isNone = function(name:String):Boolean { return name == "combatDecoration"; };
        check(flushShakeFrame().indexOf(";h,") < 0 && CombatFxBridge.isDecorationClean(),
            "worker none drops a shake queued before the projection policy changed");
        projectionApi.isNone = oldIsNone;

        var droppedBefore:Number = CombatFxBridge.getStats().shakeDropped;
        var ids:Array = [7,4,3,2,4,5,6,7];
        for (var i:Number = 0; i < ids.length; i++) CombatFxBridge.tryShake(ids[i], i, 0);
        check(CombatFxBridge.getStats().shakeQueued == 8 && CombatFxBridge.getStats().shakeTail == 31,
            "eight births fill one queue and reset the tail to 31 without accumulating");
        CombatFxBridge.tryShake(5, 90, 0);
        CombatFxBridge.tryShake(4, 91, 0);
        CombatFxBridge.tryShake(2, 92, 0);
        var wire:String = flushShakeFrame();
        check(wire.split(";h,").length == 9 && wire.indexOf(";h,5,5,90,0") >= 0
            && wire.indexOf(";h,5,2,3,0") < 0 && wire.indexOf(";h,5,4,91,0") < 0
            && wire.indexOf(";h,5,2,92,0") < 0 && wire.indexOf(";h,5,4,1,0") >= 0,
            "the ninth birth replaces the lowest priority and ties or lower priorities cannot replace a survivor");
        check(CombatFxBridge.getStats().shakeDropped == droppedBefore + 3 && CombatFxBridge.getStats().shakeQueued == 0,
            "each capacity eviction or discard is counted and the frame consumes the queue");

        check(!CombatFxBridge.tryShake(0, 1, 2) && !CombatFxBridge.tryShake(8, 1, 2)
            && !CombatFxBridge.tryShake(1.5, 1, 2) && !CombatFxBridge.tryShake(NaN, 1, 2)
            && !CombatFxBridge.tryShake(2, NaN, 2) && !CombatFxBridge.tryShake(6, 1, Infinity)
            && !CombatFxBridge.tryShake(1, -1000001, 2) && CombatFxBridge.getStats().shakeQueued == 0,
            "invalid profiles and positional coordinates are rejected before enqueue");
        check(CombatFxBridge.tryShake(1, -1000000, 1000000)
            && CombatFxBridge.tryShake(7, NaN, Infinity) && CombatFxBridge.tryShake(7, 1000001, -12),
            "world bounds are inclusive and screen-wide coordinates are normalized independently");
        wire = flushShakeFrame();
        check(wire.indexOf(";h,5,1,-1000000,1000000") >= 0 && wire.indexOf(";h,5,7,0,0") >= 0
            && wire.indexOf(";h,5,7,0,-12") >= 0, "normalization keeps every shake coordinate valid on F6");
    }

    private static function sampleShakeConfig():Object {
        var bullets:Object = {};
        bullets["普通爆炸"] = 2;
        bullets["集束连环爆炸"] = 2;
        bullets["高压爆炸"] = 2;
        bullets["火焰集束手雷爆炸"] = 2;
        bullets["火焰集束爆炸声"] = 2;
        bullets["火焰集束爆炸"] = 2;
        bullets["高爆爆炸"] = 2;
        bullets["地面爆炸"] = 2;
        bullets["爆炸"] = 2;
        bullets["支援飞弹爆炸"] = 3;
        bullets["小火焰爆炸"] = 1;
        bullets["普通霹雷"] = 1;
        bullets["联弹爆炸"] = 1;
        bullets["巨大物理爆炸"] = 5;
        bullets["核弹爆炸"] = 5;
        bullets["阿修罗闪空"] = 4;
        var effects:Object = {};
        effects["小地震"] = 7;
        return {
            maxProfile: 7,
            tailTicks: 31,
            priorities: [0,1,2,5,3,6,7,4],
            screenWide: [7],
            bullets: bullets,
            effects: effects
        };
    }

    private static function testShakeProducers(caps:Object):Void {
        var linkages:Array = ["普通爆炸","集束连环爆炸","高压爆炸","火焰集束手雷爆炸","火焰集束爆炸声",
            "火焰集束爆炸","高爆爆炸","地面爆炸","爆炸","支援飞弹爆炸","小火焰爆炸","普通霹雷","联弹爆炸",
            "巨大物理爆炸","核弹爆炸","阿修罗闪空"];
        var profiles:Array = [2,2,2,2,2,2,2,2,2,3,1,1,1,5,5,4];
        for (var i:Number = 0; i < linkages.length; i++) {
            var accepted:Boolean = CombatFxBridge.tryBulletShake(linkages[i], i, -10);
            var rows:Array = flushShakeFrame().split(";");
            check(accepted && rows.length == 2 && rows[1] == "h,5," + profiles[i] + "," + i + ",-10",
                "bullet linkage has its configured wire profile: " + linkages[i]);
        }
        check(!CombatFxBridge.tryBulletShake("量子爆弹", 1, 2) && !CombatFxBridge.tryBulletShake("小地震", 1, 2)
            && !CombatFxBridge.tryBulletShake("核弹爆炸特效", 1, 2) && !CombatFxBridge.tryBulletShake("普通爆炸2", 1, 2)
            && flushShakeFrame().indexOf(";h,") < 0, "non-whitelisted parents, visual children and near matches never emit");
        check(CombatFxBridge.tryShakePhase(6, 61, 18) && flushShakeFrame().indexOf(";h,5,6,61,18") >= 0,
            "the quantum phase helper emits profile six");

        var beforeMade:Number = made;
        var battle:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();
        var beforeRng:Number = battle.captureState();
        var previousVisual = _root.是否视觉元素;
        _root.是否视觉元素 = false;
        var quake:MovieClip = EffectSystem.Effect("小地震", 0, 0, 100, false);
        _root.是否视觉元素 = previousVisual;
        var offscreen:MovieClip = EffectSystem.Effect("小地震", 1000000, -1000000, 100, false);
        check(quake == null && offscreen == null && made == beforeMade && battle.captureState() == beforeRng,
            "screen-wide requests preserve culling, visual admission, MovieClip count and gameplay RNG");
        check(flushShakeFrame().split(";h,5,7,").length == 3,
            "both the visually disabled and offscreen quake requests emit configured effect profile seven");

        // Dynamic table reconfigure: new profile 8 + custom bullet/effect + custom tail & screenWide.
        var customBullets:Object = {};
        customBullets["自定义爆破"] = 8;
        var customEffects:Object = {};
        customEffects["自定义震地"] = 8;
        var customCaps:Object = {
            version:1, generation:caps.generation, worldLights:false, styles:[], digest:"",
            shakeVersion:1, shakeGrant:caps.shakeGrant,
            shakeConfig:{
                maxProfile:8, tailTicks:40, priorities:[0,1,2,3,4,5,6,7,9], screenWide:[8],
                bullets:customBullets, effects:customEffects
            }
        };
        customCaps["native"] = false;
        CombatFxBridge.configure(customCaps);
        check(!CombatFxBridge.tryBulletShake("普通爆炸", 1, 2) && CombatFxBridge.tryBulletShake("自定义爆破", NaN, Infinity)
            && CombatFxBridge.getStats().shakeTail == 40
            && flushShakeFrame().indexOf(";h,5,8,0,0") >= 0,
            "data-driven shakeConfig replaces bullet map, extends maxProfile/tailTicks, and applies custom screenWide");
        check(CombatFxBridge.tryEffectShake("自定义震地", 12, 34) && flushShakeFrame().indexOf(";h,5,8,12,34") >= 0,
            "data-driven shakeConfig drives effect shake bindings");

        // Malformed shakeConfig must fail closed.
        customCaps.shakeConfig = {maxProfile:8, tailTicks:40, priorities:[0,1], screenWide:[], bullets:{}, effects:{}};
        CombatFxBridge.configure(customCaps);
        check(CombatFxBridge.getStats().shakeVersion == 0 && !CombatFxBridge.tryShake(1, 0, 0),
            "malformed shakeConfig fails closed");
        // Restore valid config with strictly newer grant? Wait: keep grant sequence intact by re-testing on fresh generation.
        CombatFxBridge.configure(caps);
        check(!CombatFxBridge.tryShake(2, 1, 2), "malformed shakeConfig revocation keeps grant high-water mark");
        caps.generation++;
        caps.shakeGrant = 5;
        CombatFxBridge.configure(caps);
        check(CombatFxBridge.tryBulletShake("普通爆炸", 1, 2) && flushShakeFrame().indexOf(";h,5,2,1,2") >= 0,
            "fresh generation restores valid shakeConfig cleanly");
    }

    private static function testShakeGrants(caps:Object):Void {
        CombatFxBridge.tryShake(2, 1, 2);
        caps.shakeGrant = 6;
        CombatFxBridge.configure(caps);
        check(CombatFxBridge.getStats().shakeGrant == 6 && CombatFxBridge.getStats().shakeQueued == 0
            && CombatFxBridge.getStats().shakeTail == 0 && flushShakeFrame() == "",
            "grant rotation clears the unsent prior-grant birth and its tail");
        CombatFxBridge.tryShake(2, 3, 4);
        caps.shakeGrant = 5;
        CombatFxBridge.configure(caps);
        check(CombatFxBridge.getStats().shakeGrant == 6 && CombatFxBridge.getStats().shakeQueued == 1,
            "a stale grant cannot change the active grant or its queue");
        caps.shakeGrant = 6;
        CombatFxBridge.configure(caps);
        check(CombatFxBridge.getStats().shakeQueued == 1 && flushShakeFrame().indexOf(";h,6,2,3,4") >= 0,
            "same-grant caps are idempotent and the birth retains its enqueue-time stamp");

        var invalid:Array = [0,-1,1.5,NaN,Infinity,1000000001,"6",undefined];
        for (var i:Number = 0; i < invalid.length; i++) {
            caps.shakeGrant = invalid[i];
            CombatFxBridge.configure(caps);
            check(CombatFxBridge.getStats().shakeVersion == 0 && !CombatFxBridge.tryShake(2, 1, 2),
                "invalid grant disables shake: " + invalid[i]);
        }
        caps.shakeVersion = "1";
        caps.shakeGrant = 7;
        CombatFxBridge.configure(caps);
        check(CombatFxBridge.getStats().shakeVersion == 0 && flushShakeFrame() == "",
            "the shake version must be numeric one and revocation clears the tail");
        caps.shakeVersion = 1;
        caps.shakeGrant = 6;
        CombatFxBridge.configure(caps);
        check(!CombatFxBridge.tryShake(2, 1, 2), "capability revocation keeps the session grant high-water mark");
        caps.shakeGrant = 7;
        CombatFxBridge.configure(caps);
        check(CombatFxBridge.tryShake(2, 5, 6), "a strictly newer grant reopens after capability revocation");

        CombatFxBridge.resetScene();
        CombatFxBridge.configure(caps);
        check(CombatFxBridge.getStats().shakeQueued == 0 && !CombatFxBridge.tryShake(2, 1, 2) && flushShakeFrame() == "",
            "scene reset discards the old queue and requires a newer grant within the same connection");
        caps.shakeGrant = 8;
        CombatFxBridge.configure(caps);
        check(CombatFxBridge.tryShake(2, 7, 8), "a newer grant reopens after a scene reset");
    }

    private static function testShakePause(caps:Object):Void {
        var tick:Number = CombatFxBridge.lightTick();
        _root.暂停 = true;
        CombatFxBridge.onPauseChanged(true, false);
        check(CombatFxBridge.getStats().shakeGrant == 0 && CombatFxBridge.getStats().shakeQueued == 0
            && CombatFxBridge.getStats().shakeTail == 0 && !CombatFxBridge.tryShake(2, 1, 2),
            "pause immediately revokes the grant and drains unsent shake");
        var pausedHeader:Array = flushShakeFrame().split("|");
        check(pausedHeader.length == 4 && Number(pausedHeader[2]) == tick && pausedHeader[3] == "1"
            && flushShakeFrame() == "", "an active shake-only window emits one paused header and then stops");
        caps.shakeGrant = 9;
        CombatFxBridge.configure(caps);
        check(CombatFxBridge.getStats().shakeGrant == 0 && !CombatFxBridge.tryShake(2, 1, 2),
            "a newer grant received during pause stays unusable");

        _root.暂停 = false;
        CombatFxBridge.onPauseChanged(false, true);
        check(!CombatFxBridge.tryShake(2, 1, 2), "unpause waits for a grant");
        caps.shakeGrant = 8;
        CombatFxBridge.configure(caps);
        caps.shakeGrant = 9;
        CombatFxBridge.configure(caps);
        check(!CombatFxBridge.tryShake(2, 1, 2) && flushShakeFrame() == "",
            "grants already seen before and during pause cannot reopen on resume");
        caps.shakeGrant = 10;
        CombatFxBridge.configure(caps);
        CombatFxBridge.onPauseChanged(false, true);
        check(CombatFxBridge.tryShake(2, 3, 4) && flushShakeFrame().indexOf(";h,10,2,3,4") >= 0,
            "the first strictly newer grant after resume tags future births and a duplicate pause callback is inert");

        CombatFxBridge.tryShake(2, 5, 6);
        _root.暂停 = 1;
        pausedHeader = flushShakeFrame().split("|");
        check(pausedHeader[3] == "1" && CombatFxBridge.getStats().shakeGrant == 0
            && CombatFxBridge.getStats().shakeQueued == 0 && flushShakeFrame() == "",
            "the truthy root pause revokes pending shake in flush even without a pause callback");
        _root.暂停 = false;
        CombatFxBridge.onPauseChanged(false, true);
    }

    private static function fixedLightPayload(wire:String):Function {
        return function():String { return wire; };
    }

    private static function testShakePayloadCeiling(caps:Object):Void {
        caps.generation++;
        caps.shakeGrant = 1;
        caps.worldLights = true;
        CombatFxBridge.configure(caps);
        var header:String = CombatFxBridge.getStats().epoch + "|1|1|0";
        var smallRecord:String = ";h,1,1,0,0";
        // Pad a synthetic equipment-light record so only the shorter shake fits.
        var lightPrefix:String = ";l,1,0,1.";
        var lightSuffix:String = ",1,0,0,1,0,1,1,1,1,0,0,0,0";
        var padLength:Number = 32768 - header.length - smallRecord.length - lightPrefix.length - lightSuffix.length;
        var zeros:String = "0";
        while (zeros.length < padLength) zeros += zeros;
        var lights:String = lightPrefix + zeros.substr(0, padLength) + lightSuffix;
        var lightApi:Object = org.flashNight.arki.render.EquipmentLightBridge;
        var oldPayload:Function = lightApi.payload;
        lightApi.payload = fixedLightPayload(lights);
        var droppedBefore:Number = CombatFxBridge.getStats().shakeDropped;
        CombatFxBridge.tryShake(5, 1000000, -1000000);
        CombatFxBridge.tryShake(1, 0, 0);
        var wire:String = flushShakeFrame();
        lightApi.payload = oldPayload;
        check(wire.length == 32768 && wire == header + lights + smallRecord,
            "the F6 ceiling preserves all light data and still appends a later shake that fits exactly");
        check(CombatFxBridge.getStats().shakeDropped == droppedBefore + 1 && CombatFxBridge.getStats().shakeQueued == 0,
            "only the oversize shake is discarded and counted");
    }

    private static function runShakeTests():Void {
        var caps:Object = {version:1, generation:3, worldLights:true, styles:[], digest:""};
        caps["native"] = false;
        CombatFxBridge.configure(caps);
        check(!CombatFxBridge.tryShake(2, 1, 2) && !CombatFxBridge.tryBulletShake("普通爆炸", 1, 2),
            "old Host caps do not admit shake");
        var wire:String = flushShakeFrame();
        check(wire != "" && wire.indexOf(";h,") < 0, "old Host keeps its regular F6 without an h record");

        caps.worldLights = false;
        caps.shakeVersion = 1;
        caps.shakeGrant = 5;
        caps.shakeConfig = sampleShakeConfig();
        CombatFxBridge.configure(caps);
        testShakeTail();
        testShakeQueue();
        testShakeProducers(caps);
        testShakeGrants(caps);
        testShakePause(caps);

        CombatFxBridge.disconnect();
        caps.shakeGrant = 1;
        CombatFxBridge.configure(caps);
        check(CombatFxBridge.tryShake(2, 9, 10) && flushShakeFrame().indexOf(";h,1,2,9,10") >= 0,
            "Host restart after disconnect can regrant one");
        caps.shakeGrant = 1000000000;
        CombatFxBridge.configure(caps);
        check(CombatFxBridge.tryShake(2, 11, 12), "the upper grant bound is valid");
        testShakePayloadCeiling(caps);
        CombatFxBridge.disconnect();
    }

    public static function runAllTests():Void {
        passed = 0; failed = 0; made = 0; packet = "";heard=[];birthHeard=[];lastLinkage="";
        var oldWorld:MovieClip = _root.gameworld;
        var oldServer:Object = _root.server;
        var oldPause = _root.暂停;
        var oldVisual = _root.是否视觉元素;
        var oldMax:Number = EffectSystem.maxEffectCount;
        var oldGravity=_root.重力加速度;
        var oldRootPlay:Function=_root.播放音效;
        var oldBloodDict:Object=BitmapEffectRenderer.bitmapDict;
        var oldBloodInfos:Array=BitmapEffectRenderer.bloodstainInfos;
        var audioApi:Object=org.flashNight.arki.audio.AudioBridge;
        var oldAudioPlay:Function=audioApi.playSound;
        audioApi.playSound=function(name:String):Void {CombatFxBridgeTest.heard.push(name);};
        var projectionApi:Object=org.flashNight.arki.render.WorkerProjectionPolicy;
        var oldIsNone:Function=projectionApi.isNone;
        var world:MovieClip = _root.createEmptyMovieClip("combatFxTestWorld", 76546);
        var effects:MovieClip = world.createEmptyMovieClip("效果", 1);
        var body:MovieClip = world.createEmptyMovieClip("deadbody", 2);
        body._x = 10; body._y = 20;
        var pixels:BitmapData = new BitmapData(256, 256, true, 0);
        var bloodPixels:BitmapData=new BitmapData(256,256,true,0);
        var bloodArt:BitmapData=new BitmapData(2,2,true,0xFFAA1100);
        body.layers = [bloodPixels, null, pixels];
        body.layerOriginX=10;body.layerOriginY=20;
        BitmapEffectRenderer.bitmapDict={combatFxBlood:bloodArt};
        BitmapEffectRenderer.bloodstainInfos=[];
        for(var bloodIndex:Number=0;bloodIndex<8;bloodIndex++)BitmapEffectRenderer.bloodstainInfos[bloodIndex]={id:"combatFxBlood",offsetX:1,offsetY:1};
        world.effectPools = {};
        effects.attachMovie = function(linkage:String, name:String, depth:Number):MovieClip {
            CombatFxBridgeTest.made++;CombatFxBridgeTest.lastLinkage=linkage;
            var clip:MovieClip = this.createEmptyMovieClip(name, depth);
            clip.beginFill(0xFFFFFF, 100);
            clip.moveTo(0, 0); clip.lineTo(8, 0); clip.lineTo(8, 4); clip.lineTo(0, 4); clip.lineTo(0, 0);
            clip.endFill();CombatFxBridgeTest.lastEffect=clip;
            return clip;
        };
        _root.gameworld = world;
        _root.暂停 = false;
        _root.是否视觉元素 = true;_root.重力加速度=1;
        _root.server = {isSocketConnected:true, sendSocketMessage:function(value:String):Void {
            CombatFxBridgeTest.packet = value;
        }};
        FrameBroadcaster.reset();
        DecalStampQueue.clearCache();
        var caps:Object = {version:1, generation:2, bloodVersion:1,
            digest:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            styles:[{index:0, linkage:"测试弹壳", kind:"casing"},
                    {index:1, linkage:"测试枪火", kind:"muzzle"},
                    {index:2, linkage:"测试命中", kind:"impact",variantSounds:["fixture-hit.wav","../blocked.wav"]},
                    {index:3, linkage:"子弹碎片-飞血", kind:"blood"},
                    {index:4, linkage:"空手攻击火花", kind:"impact",randomRotation:true},
                    {index:5, linkage:"出生声音测试", kind:"impact",soundAtBirth:true,variantSounds:["birth-a.wav","birth-b.wav","birth-c.wav"]},
                    {index:6, linkage:"出生声音零位跳过", kind:"impact",soundAtBirth:true,skipOriginYZero:true,variantSounds:["birth-zero.wav"]}]};
        caps["native"] = true;
        CombatFxBridge.configure(caps);
        check(CombatFxBridge.getStats().enabled === true, "capability admits known styles");
        var stale:Object = {version:1, generation:1, digest:caps.digest, styles:caps.styles};
        stale["native"] = false;
        CombatFxBridge.configure(stale);
        check(CombatFxBridge.getStats().enabled === true, "old connection capability cannot revoke current ownership");
        var wrongStyles:Array=caps.styles.slice();
        wrongStyles[3]={index:3,linkage:"子弹碎片-飞血",kind:"impact"};
        var wrongBlood:Object={version:1,generation:2,bloodVersion:1,digest:caps.digest,styles:wrongStyles};
        wrongBlood["native"]=true;CombatFxBridge.configure(wrongBlood);
        check(BloodVisualBridge.getStats().style<0,"a blood name with the wrong kind cannot enable the particle channel");
        CombatFxBridge.configure(caps);
        var battle:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();
        var before:Number = battle.captureState();
        var shell:Boolean = CombatFxBridge.tryShell("测试弹壳", 50, 50, 100, 5, 150);
        var muzzle:Boolean = CombatFxBridge.tryMuzzle("测试枪火", 60, 50, -100, 10);
        check(shell && muzzle && made == 0, "native spawn does not allocate a source MovieClip");
        var hit:MovieClip = EffectSystem.Effect("测试命中", 70, 50, 100, false, true);
        check(hit == null && made == 0 && CombatFxBridge.getStats().queuedImpacts == 1,
            "explicit fire-and-forget hit bypasses MovieClip allocation");
        EffectSystem.maxEffectCount = -1;
        EffectSystem.Effect("not-created", 50, 50, 100, false);
        EffectSystem.maxEffectCount = oldMax;
        check(battle.captureState() == before, "visual consumers preserve gameplay RNG state");
        CombatFxBridge.flush();FrameBroadcaster.send();
        check(packet.indexOf("\x06") > 0 && packet.indexOf(";s,0,") > 0 && packet.indexOf(";m,1,") > 0,
            "both event domains share the bounded frame section");
        check(packet.indexOf(";i,2,") > 0, "hit event travels in the same bounded frame section");
        var header:Array = packet.split("\x06")[1].split(";")[0].split("|");
        var tick:Number = Number(header[2]);
        _root.暂停 = 1;
        CombatFxBridge.flush();FrameBroadcaster.send();
        header = packet.split("\x06")[1].split(";")[0].split("|");
        check(Number(header[2]) == tick && header[3] == "1", "truthy pause freezes game clock");
        _root.暂停 = false;
        var currentEpoch:Number = CombatFxBridge.getStats().epoch;
        var event:Object = {version:1, generation:2, epoch:currentEpoch, sequence:1, groundHits:0,
            settled:[[101,0,30,40,0,100,100],[102,0,60,80,90,100,100],[103,0,80,40,0,-100,100]]};
        CombatFxBridge.receiveEvents(event);
        check(DecalStampQueue.getStats().pending == 3, "settled poses queue without active MCs");
        CombatFxBridge.flush();FrameBroadcaster.send();
        check(made == 1 && DecalStampQueue.getStats().cached == 1, "one bitmap bake serves repeated stamps");
        check((pixels.getPixel32(24,22) >>> 24) == 255, "world-to-layer translation writes the expected pixel");
        check((pixels.getPixel32(48,64) >>> 24) == 255, "rotated stamp keeps its registration");
        check((pixels.getPixel32(65,22) >>> 24) == 255, "mirrored stamp keeps its registration");
        CombatFxBridge.receiveEvents(event);
        CombatFxBridge.flush();FrameBroadcaster.send();
        check(DecalStampQueue.getStats().stamps == 3 && packet.indexOf(";a,") < 0, "duplicate settlement batch is not replayed");
        for (var batch:Number = 2; batch < 12; batch++) {
            var poses:Array = [];
            for (var i:Number = 0; i < 8; i++) poses[i] = [batch * 8 + i + 200,0,100,100,0,100,100];
            CombatFxBridge.receiveEvents({version:1, generation:2, epoch:currentEpoch, sequence:batch, groundHits:0, settled:poses});
        }
        check(DecalStampQueue.getStats().pending == 64, "stamp backlog is bounded");
        CombatFxBridge.resetScene();
        check(DecalStampQueue.getStats().pending == 0 && DecalStampQueue.getStats().cached == 1,
            "scene reset retires poses but keeps immutable cached art");
        event.sequence = 999;
        CombatFxBridge.receiveEvents(event);
        check(DecalStampQueue.getStats().pending == 0, "old scene settlements cannot reach the new bitmap");
        check(CombatFxBridge.tryMuzzle("未知效果", 40, 40, 100, 0) === false, "unsupported effect retains its AS2 route");
        for (var n:Number = 0; n < 33; n++) CombatFxBridge.tryMuzzle("测试枪火", 40, 40, 100, 0);
        check(CombatFxBridge.getStats().queued == 32, "spawn burst is bounded before serialization");
        for (var h:Number = 0; h < 33; h++) CombatFxBridge.tryImpact("测试命中", 40, 40, 100, false);
        check(CombatFxBridge.getStats().queuedImpacts == 32 && CombatFxBridge.getStats().queued == 32,
            "impact bursts do not consume shooting event capacity");
        check(CombatFxBridge.tryImpact("测试枪火", 40, 40, 100, false) === false,
            "impact admission cannot steal a muzzle style");
        CombatFxBridge.flush();FrameBroadcaster.send();
        _root.是否视觉元素 = false;
        CombatFxBridge.tryImpact("测试命中", 40, 40, 100, false);
        CombatFxBridge.tryImpact("测试命中", 40, 40, 100, true);
        check(CombatFxBridge.getStats().queuedImpacts == 1, "force trigger retains its visual admission meaning");
        _root.是否视觉元素 = true;
        var beforeLegacy:Number = made;
        var legacy:MovieClip = EffectSystem.Effect("测试命中", 40, 40, 100, true);
        check(legacy != null && made == beforeLegacy + 1,
            "callers needing a MovieClip keep the legacy return contract");
        // New ordinary blood remains fire-and-forget; acid still owns its AS2 gameplay MC.
        CombatFxBridge.flush();FrameBroadcaster.send();
        var beforeBlood:Number=made;
        BulletEffectHandler.createBulletEffect({击中效果:"飙血",_name:"bloodSource",Z轴坐标:120},40,40,100);
        check(made==beforeBlood && BloodVisualBridge.getStats().queued==1,"ordinary hit routes to seeded blood without a MovieClip");
        CombatFxBridge.flush();FrameBroadcaster.send();
        check(packet.indexOf(";p,")>0,"ordinary blood births share the ordered combat frame channel");
        BulletEffectHandler.createBulletEffect({击中效果:"异形飙血",_name:"acidSource",Z轴坐标:120},40,40,100);
        check(made==beforeBlood+1 && lastLinkage=="子弹碎片-异形飞血" && lastEffect.出血来源=="acidSource",
            "acid blood keeps its original gameplay source and MovieClip route");
        var beforeUnarmed:Number=made;
        var unarmedLegacy:MovieClip=EffectSystem.Effect("空手攻击火花",40,40,150,false,true);
        check(unarmedLegacy!=null && made==beforeUnarmed+1,"full presentation keeps non-unit unarmed transforms on the original route");
        check(CombatFxBridge.tryImpact("空手攻击火花",40,40,-100,false),"unit mirrored unarmed transforms use native presentation");
        CombatFxBridge.flush();FrameBroadcaster.send();
        var eventEpoch:Number=CombatFxBridge.getStats().epoch;
        var beforeNone:Number=made;
        var heardBefore:Number=heard.length;
        projectionApi.isNone=function(name:String):Boolean{return name=="combatDecoration";};
        EffectSystem.Effect("空手攻击火花",40,40,150,false,true);
        EffectSystem.Effect("测试命中",40,40,100,false,true);
        BulletEffectHandler.createBulletEffect({击中效果:"飙血",_name:"noneBlood",Z轴坐标:120},40,40,100);
        CombatFxBridge.tryShell("测试弹壳",40,40,100,1,140);CombatFxBridge.tryMuzzle("测试枪火",40,40,100,0);
        check(made==beforeNone && BloodVisualBridge.getStats().queued==0 && CombatFxBridge.getStats().queued==0
            && CombatFxBridge.getStats().queuedImpacts==0,"none consumes ordinary decoration before transform fallback without allocating MCs");
        var feedback:Object={version:1,generation:2,epoch:eventEpoch,sequence:1,groundHits:0,settled:[],
            bloodLandings:[[701,2,40,50]],sounds:["fixture-hit.wav","../blocked.wav","unknown.wav"]};
        CombatFxBridge.receiveEvents(feedback);
        check(BloodVisualBridge.getStats().pendingStamps==0 && heard.length==heardBefore,"none rejects blood landings and audio feedback");
        BulletEffectHandler.createBulletEffect({击中效果:"异形飙血",_name:"noneAcid",Z轴坐标:120},40,40,100);
        check(made==beforeNone+1 && lastLinkage=="子弹碎片-异形飞血" && lastEffect.出血来源=="noneAcid",
            "none does not remove acid gameplay authority with decorative consumers");
        projectionApi.isNone=oldIsNone;
        CombatFxBridge.receiveEvents(feedback);
        check(BloodVisualBridge.getStats().pendingStamps==1 && heard.length==heardBefore+1 && heard[heardBefore]=="fixture-hit.wav",
            "full feedback forwards one blood landing and only catalog-approved sound names");
        CombatFxBridge.receiveEvents(feedback);
        check(BloodVisualBridge.getStats().pendingStamps==1 && heard.length==heardBefore+1,"a repeated event sequence never repeats landing or sound");
        CombatFxBridge.flush();FrameBroadcaster.send();
        check((bloodPixels.getPixel32(29,29)>>>24)==255,"public feedback drains the explicit blood variant into layer zero");
        feedback.sequence=2;CombatFxBridge.receiveEvents(feedback);
        check(BloodVisualBridge.getStats().pendingStamps==0 && heard.length==heardBefore+2,"repeated landing id stays deduplicated while a new legitimate same-name sound can play");
        feedback.sequence=3;feedback.bloodLandings=[[702,2,40,50]];feedback.epoch=eventEpoch-1;CombatFxBridge.receiveEvents(feedback);
        check(BloodVisualBridge.getStats().pendingStamps==0 && heard.length==heardBefore+2,"old scene feedback cannot stamp or play sounds");
        feedback.epoch=eventEpoch;feedback.generation=1;CombatFxBridge.receiveEvents(feedback);
        check(BloodVisualBridge.getStats().pendingStamps==0 && heard.length==heardBefore+2,"old connection feedback cannot stamp or play sounds");
        feedback.generation=2;feedback.sequence=2.5;CombatFxBridge.receiveEvents(feedback);
        check(heard.length==heardBefore+2,"fractional event sequence cannot advance audio delivery");
        feedback.sequence=3;feedback.bloodLandings=[];
        for(var overflow:Number=0;overflow<9;overflow++)feedback.bloodLandings.push([702+overflow,2,40,50]);
        CombatFxBridge.receiveEvents(feedback);
        check(BloodVisualBridge.getStats().pendingStamps==0 && heard.length==heardBefore+2,"oversized blood feedback is rejected before any side effect");
        feedback.bloodLandings=[];feedback.sounds=[];
        for(overflow=0;overflow<9;overflow++)feedback.sounds.push("fixture-hit.wav");
        CombatFxBridge.receiveEvents(feedback);
        check(heard.length==heardBefore+2,"oversized audio feedback is rejected before delivery");
        feedback.sounds=["fixture-hit.wav"];CombatFxBridge.receiveEvents(feedback);
        check(heard.length==heardBefore+3,"invalid batches do not consume the next valid feedback sequence");

        // Birth sounds use the admitted hit immediately, independently of sprite capacity.
        CombatFxBridge.flush();FrameBroadcaster.send();
        _root.播放音效=function(name:String):Void {CombatFxBridgeTest.birthHeard.push(name);};
        var activeRootPlay:Function=_root.播放音效;
        var beforeBirthMc:Number=made;
        var beforeFallback:Number=heard.length;
        CombatFxBridge.tryImpact("出生声音测试",40,40,100,false);
        check(birthHeard.length==1 && heard.length==beforeFallback && made==beforeBirthMc
            && CombatFxBridge.getStats().queuedImpacts==1,"birth sound uses the explicit root entry in the same call without a MovieClip or audio fallback");
        CombatFxBridge.flush();FrameBroadcaster.send();
        var birthWire:Array=packet.split(";i,5,")[1].split(";")[0].split(",");
        var birthNames:Array=caps.styles[5].variantSounds;
        check(birthHeard[0]===birthNames[Number(birthWire[5])%birthNames.length],"same seed modulo chooses matching image and sound branches");
        CombatFxBridge.flush();FrameBroadcaster.send();
        check(birthHeard.length==1,"flushing a birth never replays its already delivered sound");
        var muteRootCalls:Number=0;
        _root.播放音效=function(name:String):Void {muteRootCalls++;};
        CombatFxBridge.tryImpact("出生声音测试",40,40,100,false);
        check(muteRootCalls==1 && heard.length==beforeFallback,"an existing mute-owning root entry is never bypassed by audio fallback");
        _root.播放音效=undefined;
        CombatFxBridge.tryImpact("出生声音测试",40,40,100,false);
        check(heard.length==beforeFallback+1,"only a focused fixture without the root entry uses AudioBridge fallback");
        _root.播放音效=activeRootPlay;
        CombatFxBridge.flush();FrameBroadcaster.send();
        var quietBirths:Number=birthHeard.length;
        var quietFallback:Number=heard.length;
        projectionApi.isNone=function(name:String):Boolean{return name=="combatDecoration";};
        CombatFxBridge.tryImpact("出生声音测试",40,40,100,false);
        check(birthHeard.length==quietBirths && heard.length==quietFallback,"none suppresses birth sounds before projection admission");
        projectionApi.isNone=oldIsNone;
        _root.暂停=true;CombatFxBridge.tryImpact("出生声音测试",40,40,100,false);_root.暂停=false;
        check(birthHeard.length==quietBirths && heard.length==quietFallback,"pause never starts a birth sound");
        _root.是否视觉元素=false;CombatFxBridge.tryImpact("出生声音测试",40,40,100,false);
        check(birthHeard.length==quietBirths,"disabled ordinary visual admission also suppresses its birth sound");
        CombatFxBridge.tryImpact("出生声音测试",40,40,100,true);_root.是否视觉元素=true;
        check(birthHeard.length==quietBirths+1,"force-trigger retains the original admitted hit-sound meaning");
        quietBirths=birthHeard.length;
        CombatFxBridge.tryImpact("出生声音测试",-10000,40,100,false);
        CombatFxBridge.tryImpact("出生声音测试",40,40,NaN,false);
        CombatFxBridge.tryImpact("出生声音测试",40,40,0,false);
        check(birthHeard.length==quietBirths,"offscreen and invalid input gates run before birth audio");
        CombatFxBridge.tryImpact("出生声音零位跳过",40,0,100,false);
        check(birthHeard.length==quietBirths,"authored origin-zero removal runs before birth audio");
        CombatFxBridge.flush();FrameBroadcaster.send();
        var burstSoundStart:Number=birthHeard.length;
        for(var soundBurst:Number=0;soundBurst<33;soundBurst++)CombatFxBridge.tryImpact("出生声音测试",40,40,100,false);
        check(birthHeard.length==burstSoundStart+33 && CombatFxBridge.getStats().queuedImpacts==32,
            "the sprite-only 32-event ceiling cannot swallow an already admitted hit sound");
        CombatFxBridge.flush();FrameBroadcaster.send();
        var impactRows:Array=packet.split(";i,5,");var matchingBranches:Boolean=impactRows.length==33;
        for(soundBurst=1;soundBurst<impactRows.length;soundBurst++) {
            var soundFields:Array=impactRows[soundBurst].split(";")[0].split(",");
            if(birthHeard[burstSoundStart+soundBurst-1]!==birthNames[Number(soundFields[5])%birthNames.length])matchingBranches=false;
        }
        check(matchingBranches,"every retained burst sprite uses the sound branch chosen from its own seed");
        var stoppedBirths:Number=birthHeard.length;
        CombatFxBridge.flush();FrameBroadcaster.send();CombatFxBridge.flush();FrameBroadcaster.send();
        check(birthHeard.length==stoppedBirths && CombatFxBridge.getStats().queuedImpacts==0,"stopped firing never creates deferred birth audio on later flushes");
        var feedbackFallback:Number=heard.length;
        CombatFxBridge.receiveEvents({version:1,generation:2,epoch:eventEpoch,sequence:4,groundHits:0,settled:[],
            sounds:["birth-a.wav","fixture-hit.wav"]});
        check(birthHeard.length==stoppedBirths && heard.length==feedbackFallback+1 && heard[feedbackFallback]=="fixture-hit.wav",
            "feedback cannot replay local birth sounds while non-birth audio remains compatible");

        caps["native"] = false;
        CombatFxBridge.configure(caps);
        check(CombatFxBridge.tryShell("测试弹壳", 50, 50, 100, 1, 150)
            && CombatFxBridge.tryMuzzle("测试枪火", 50, 50, 100, 0)
            && CombatFxBridge.tryImpact("测试命中", 50, 50, 100, false)
            && CombatFxBridge.getStats().queued == 0 && CombatFxBridge.getStats().queuedImpacts == 0,
            "capability loss consumes owned decoration without MC fallback or queued replay");

        CombatFxBridge.disconnect();
        beforeLegacy = made;
        EffectSystem.Effect("测试命中", 40, 40, 100, false, true);
        check(made == beforeLegacy
            && CombatFxBridge.tryShell("测试弹壳", 50, 50, 100, 1, 150)
            && CombatFxBridge.tryMuzzle("测试枪火", 50, 50, 100, 0)
            && !CombatFxBridge.tryShell("未接管弹壳", 50, 50, 100, 1, 150),
            "disconnect keeps known decoration native-only and leaves unknown linkages alone");
        // The focused runner pins the original pass count and rejects any failure sentinel.
        var legacyPassed:Number = passed;
        var legacyFailed:Number = failed;
        runShakeTests();
        trace("CombatFxBridgeShakeTest Tests Passed: " + (passed - legacyPassed));
        trace("CombatFxBridgeShakeTest Tests Failed: " + (failed - legacyFailed));
        DecalStampQueue.clearCache();
        pixels.dispose();bloodPixels.dispose();bloodArt.dispose();
        BitmapEffectRenderer.bitmapDict=oldBloodDict;BitmapEffectRenderer.bloodstainInfos=oldBloodInfos;
        audioApi.playSound=oldAudioPlay;projectionApi.isNone=oldIsNone;_root.重力加速度=oldGravity;_root.播放音效=oldRootPlay;
        _root.gameworld = oldWorld;_root.server = oldServer;
        _root.暂停 = oldPause;_root.是否视觉元素 = oldVisual;
        world.removeMovieClip();
        trace("CombatFxBridgeTest Tests Passed: " + legacyPassed);
        trace("CombatFxBridgeTest Tests Failed: " + legacyFailed);
    }
}
