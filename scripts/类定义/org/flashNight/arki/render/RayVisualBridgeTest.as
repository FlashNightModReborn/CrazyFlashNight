import org.flashNight.arki.bullet.BulletComponent.Queue.BulletCancelQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;
import org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine;
import org.flashNight.arki.render.RayVisualBridge;
import org.flashNight.arki.render.RayVfxManager;
import org.flashNight.arki.render.RayStyleRegistry;
import org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig;
import org.flashNight.arki.spatial.transform.SceneCoordinateManager;

class org.flashNight.arki.render.RayVisualBridgeTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var randomCalls:Number;
    private static var pinkCalls:Number;
    private static function check(value:Boolean, name:String):Void {
        if (value) passed++;
        else { failed++; trace("[TEST_FAIL] RayVisualBridgeTest: " + name); }
    }
    private static function capabilities():Object {
        var names:Array = RayStyleRegistry.getStyleNames();
        var styles:Array = [];
        for (var i:Number = 0; i < names.length; i++) styles[i] = {index:i, id:names[i]};
        // 配对必需模式：全部容量与 channel/lighting 版本字段缺一不可。
        return {version:1, generation:1, native:true, styles:styles,
            maxArcs:1024, drawLimit:4096, configLimit:1024,
            channelVersion:1, lightingVersion:1};
    }
    private static function fresh(world:MovieClip):Void {
        RayVfxManager.referenceRenderingForTests = false;
        RayVfxManager.reset(); RayVisualBridge.disconnect();
        RayVfxManager.initWithContainer(world); RayVisualBridge.configure(capabilities());
        SceneCoordinateManager.effectOffset.setTo(0, 0);
        _root.暂停 = false;
    }
    private static function event(payload:String, operation:String):Array {
        var rows:Array = payload.split(";");
        for (var i:Number = 1; i < rows.length; i++)
            if (rows[i].substr(0, 2) == operation + ",") return rows[i].split(",");
        return null;
    }
    private static function flame(serial:Number, target:Number):Object {
        return {segmentKind:"flame", flameVfxKey:"tester:flame", flameVfxSerial:serial,
            targetLength:target, isDamagePulse:true, isHotPulse:false, shotSeed:123,
            intensity:1, pulseIndex:0, pulseCount:5, hitPoints:null};
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var oldPause = _root.暂停;
        var oldX:Number = SceneCoordinateManager.effectOffset.x;
        var oldY:Number = SceneCoordinateManager.effectOffset.y;
        var world:MovieClip = _root.createEmptyMovieClip("rayVisualBridgeTest", 76543);
        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.flickerEnabled = false;
        fresh(world);
        var styles:Array = RayStyleRegistry.getStyleNames();
        randomCalls = 0;
        var oldRandom:Function = Math.random;
        var visualProbe:Function = function():Number { RayVisualBridgeTest.randomCalls++; return 0.5; };
        Math.random = visualProbe;
        var visualReadOnly:Boolean = Math.random !== visualProbe;
        if (visualReadOnly) {
            _global.ASSetPropFlags(Math, "random", 0, 4);
            Math.random = visualProbe;
        }
        check(Math.random === visualProbe, "native RNG probe replacement is actually installed");
        for (var i:Number = 0; i < styles.length; i++) {
            cfg.vfxStyle = styles[i];
            RayVfxManager.spawn(10, 20, 100, 20, cfg, {segmentKind:"main", intensity:1});
        }
        Math.random = oldRandom;
        if (visualReadOnly) _global.ASSetPropFlags(Math, "random", 4, 0);
        var payload:String = RayVisualBridge.flush();
        check(RayVisualBridge.getStats().active == 12, "all twelve styles are native-owned");
        check(RayVfxManager.getActiveCount() == 0, "native takeover allocates no Flash arc");
        check(randomCalls == 0, "native path consumes no Math.random samples");
        check(RayVisualBridge.getStats().configs == 12, "style mutation creates immutable config definitions");
        check(event(payload, "s") != null && event(payload, "c") != null, "definitions and births share an ordered packet");
        var epoch:Number = RayVisualBridge.getStats().epoch;
        RayVisualBridge.configure(capabilities());
        check(RayVisualBridge.getStats().epoch == epoch && RayVisualBridge.getStats().active == 12,
            "duplicate capabilities do not clear live rays");

        fresh(world); cfg.vfxStyle = "prism";
        SceneCoordinateManager.effectOffset.setTo(20, 30);
        var hits:Array = [{x:80, y:90}];
        var meta:Object = {segmentKind:"pierce", hitPoints:hits, damageHitPoints:hits, intensity:1};
        RayVfxManager.spawn(10, 20, 100, 20, cfg, meta);
        var row:Array = event(RayVisualBridge.flush(), "s");
        check(Number(row[5]) == 30 && Number(row[6]) == 50, "birth geometry includes scene offset once");
        check(row[20] == "100:120" && row[21] == "100:120", "hit and damage points are independent snapshots");
        check(hits[0].x == 80 && hits[0].y == 90, "caller hit points remain unmodified");
        _root.暂停 = true;
        var tick:Number = RayVisualBridge.getStats().tick;
        RayVisualBridge.flush(); RayVisualBridge.flush();
        check(RayVisualBridge.getStats().tick == tick, "pause does not age native visuals");
        _root.暂停 = false;
        RayVisualBridge.disconnect();
        check(RayVfxManager.getActiveCount() == 0 && RayVisualBridge.getStats().active == 1,
            "disconnect keeps native ownership of the live ray for resync");
        check(hits[0].x == 80 && hits[0].y == 90, "handoff does not mutate gameplay metadata");
        check(RayVisualBridge.flush() == null, "disconnected bridge emits no stale section");
        RayVisualBridge.configure(capabilities());
        var resync:String = RayVisualBridge.flush();
        check(resync != null && event(resync, "s") != null && event(resync, "c") != null,
            "re-grant after disconnect re-emits the retained live ray");

        fresh(world); cfg.vfxStyle = "flame_stream";
        RayVfxManager.spawn(0, 0, 300, 0, cfg, flame(3, 400)); RayVisualBridge.flush();
        RayVfxManager.spawn(80, 0, 160, 0, cfg, flame(4, 400));
        row = event(RayVisualBridge.flush(), "u");
        check(row != null && Number(row[7]) == 380, "newer shot keeps expanded length and can move its origin");
        check(RayVisualBridge.getStats().active == 1, "continuous flame reuses one native arc");
        RayVfxManager.spawn(0, 0, 600, 0, cfg, flame(3, 700));
        check(event(RayVisualBridge.flush(), "u") == null && RayVisualBridge.getStats().active == 1,
            "stale flame serial is consumed without a fallback duplicate");
        RayVfxManager.spawn(80, 0, 170, 0, cfg, flame(4, 90));
        row = event(RayVisualBridge.flush(), "u");
        check(Number(row[7]) == 170, "real blocking length contraction remains visible");
        RayVfxManager.spawn(80, 0, 80, 200, cfg, flame(5, 200));
        check(event(RayVisualBridge.flush(), "s") != null && RayVisualBridge.getStats().active == 2,
            "direction discontinuity starts a new arc while the old arc fades");
        var disabled:Object = capabilities(); disabled["native"] = false;
        RayVisualBridge.configure(disabled);
        check(RayVfxManager.getActiveCount() == 0 && RayVisualBridge.getStats().active == 2,
            "capability suspend retains both live flame records without Flash restore");
        check(RayVisualBridge.flush() == null, "suspended presentation emits no packets");
        RayVisualBridge.configure(capabilities());
        payload = RayVisualBridge.flush();
        check(eventCount(payload, "s") == 2 && event(payload, "l") != null,
            "presentation resume re-emits live arcs and lights under a fresh epoch");

        fresh(world); cfg.vfxStyle = "wave"; cfg.chainDelay = 2;
        SceneCoordinateManager.effectOffset.setTo(10, 10);
        RayVfxManager.spawn(0, 0, 100, 0, cfg, {segmentKind:"chain",hitIndex:2,intensity:1});
        row = event(RayVisualBridge.flush(), "s");
        check(Number(row[4]) == 4, "chain delay keeps authored hitIndex times chainDelay");
        SceneCoordinateManager.effectOffset.setTo(30, 40);
        RayVisualBridge.disconnect();
        check(RayVfxManager.getDelayedCount() == 0 && RayVfxManager.getActiveCount() == 0
            && RayVisualBridge.getStats().active == 1,
            "disconnect keeps the delayed segment as a native record");
        RayVfxManager.update(); RayVfxManager.update(); RayVfxManager.update();
        check(RayVfxManager.getActiveCount() == 0 && RayVisualBridge.getStats().active == 1,
            "no Flash arc materializes while the bridge retains the pending segment");

        fresh(world); cfg.vfxStyle = "prism"; cfg.chainDelay = 0;
        cfg.visualDuration = 3; cfg.fadeOutDuration = 2;
        RayVfxManager.spawn(0, 0, 100, 0, cfg, null); RayVisualBridge.flush();
        cfg.thickness = 9;
        RayVfxManager.spawn(0, 5, 100, 5, cfg, null);
        payload = RayVisualBridge.flush();
        check(event(payload, "c") != null && RayVisualBridge.getStats().configs == 2,
            "mutated effective config is versioned instead of silently reusing old values");
        for (i = 0; i < 7; i++) RayVisualBridge.flush();
        check(RayVisualBridge.getStats().active == 0, "unrefreshed rays expire by game ticks");
        RayVfxManager.reset();
        check(RayVisualBridge.getStats().active == 0 && RayVisualBridge.getStats().configs == 0,
            "scene reset drops descriptors and config definitions together");
        RayVisualBridge.disconnect();
        RayVfxManager.spawn(0, 0, 100, 0, cfg, null);
        check(RayVfxManager.getActiveCount() == 0, "unavailable native host cannot create a Flash fallback");
        RayVfxManager.referenceRenderingForTests = true;
        RayVfxManager.spawn(0, 0, 100, 0, cfg, null);
        check(RayVfxManager.getActiveCount() == 1, "offline reference renderer requires explicit test opt-in");
        RayVfxManager.referenceRenderingForTests = false;
        testGameplayRandomIsolation(world);
        testPaletteAdmission(world);
        testLightOverrides(world);
        testVisualChannels(world);
        benchmarkAs2Costs(world);
        emitGpuWire(world);
        RayVfxManager.reset(); RayVisualBridge.disconnect();world.removeMovieClip();
        SceneCoordinateManager.effectOffset.setTo(oldX, oldY);_root.暂停 = oldPause;
        trace("RayVisualBridgeTest Tests Passed: " + passed);
        trace("RayVisualBridgeTest Tests Failed: " + failed);
    }
    private static function fixedGameplayRandom():Number {
        var sample:Number = (RayVisualBridgeTest.randomCalls * 37 + 13) % 100;
        RayVisualBridgeTest.randomCalls++;
        return sample * 0.01;
    }
    private static function testGameplayRandomIsolation(world:MovieClip):Void {
        var cfg:TeslaRayConfig = TeslaRayConfig.fromXML({vfxStyle:"tesla",vfxPreset:"ra2_tesla"});
        cfg.flickerEnabled = true;
        var prism:TeslaRayConfig = TeslaRayConfig.fromXML({vfxStyle:"prism",vfxPreset:"ra2_prism"});
        prism.flickerEnabled = true;
        var b:MovieClip = world.createEmptyMovieClip("rngBounce", world.getNextHighestDepth());
        var oldRandom:Function = Math.random;
        var damageRng:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();
        var damageSeed:Number = damageRng.captureState();
        var pink:PinkNoiseEngine = PinkNoiseEngine.getInstance();
        var pinkFloat:Function = pink.nextFloat, pinkFluctuation:Function = pink.randomFluctuation;
        pinkCalls = 0;
        pink.nextFloat = function():Number { RayVisualBridgeTest.pinkCalls++; return 0.5; };
        pink.randomFluctuation = function(range:Number):Number { RayVisualBridgeTest.pinkCalls++; return 1; };
        check(pink.nextFloat !== pinkFloat && pink.randomFluctuation !== pinkFluctuation,
            "damage PinkNoise probes are installed before measuring calls");
        fresh(world); randomCalls = 0; Math.random = fixedGameplayRandom;
        var mathReadOnly:Boolean = Math.random !== fixedGameplayRandom;
        if (mathReadOnly) {
            _global.ASSetPropFlags(Math, "random", 0, 4);
            Math.random = fixedGameplayRandom;
        }
        check(Math.random === fixedGameplayRandom, "real bounce uses the installed fixed gameplay sequence");
        RayVfxManager.spawn(0, 0, 100, 0, cfg, null);
        RayVfxManager.spawn(0, 20, 100, 20, prism, null);
        RayVfxManager.update();RayVisualBridge.flush();
        b.xmov = 20; b.ymov = 0;
        BulletCancelQueueProcessor.handleBounce(b, "missingRngTestShooter");
        var nativeX:Number = b.xmov, nativeY:Number = b.ymov;
        var nativeSamples:Number = randomCalls;
        fresh(world);RayVisualBridge.disconnect();randomCalls = 0;
        RayVfxManager.referenceRenderingForTests = true;
        RayVfxManager.spawn(0, 0, 100, 0, cfg, null);
        RayVfxManager.spawn(0, 20, 100, 20, prism, null);
        RayVfxManager.update();RayVfxManager.update();
        b.xmov = 20; b.ymov = 0;
        BulletCancelQueueProcessor.handleBounce(b, "missingRngTestShooter");
        Math.random = oldRandom;
        if (mathReadOnly) _global.ASSetPropFlags(Math, "random", 4, 0);
        pink.nextFloat = pinkFloat; pink.randomFluctuation = pinkFluctuation;
        trace("[RayRandom] nativeSamples=" + nativeSamples + " fallbackSamples=" + randomCalls
            + " native=" + nativeX + "," + nativeY + " fallback=" + b.xmov + "," + b.ymov + " pinkCalls=" + pinkCalls);
        check(nativeSamples == 1 && randomCalls == 1, "both display owners consume exactly one gameplay sample for the real bounce");
        check(Math.abs(b.xmov - nativeX) < 0.000001 && Math.abs(b.ymov - nativeY) < 0.000001,
            "real bounce direction is identical with native or Flash Tesla/Prism/flicker");
        check(damageRng.captureState() == damageSeed, "ray display ownership never advances the actual scatter LCG state");
        check(pinkCalls == 0, "ray display ownership never samples the actual damage PinkNoise engine");
        b.removeMovieClip();
    }

    private static function testPaletteAdmission(world:MovieClip):Void {
        fresh(world);
        var config:TeslaRayConfig = TeslaRayConfig.fromXML({vfxStyle:"spectrum",vfxPreset:"ra3_spectrum"});
        config.palette = [0xFF0000,0xFF8800,0xFFFF00,0x88FF00,0x00FFFF,0x0088FF,0x0000FF,0xFF00FF];
        check(RayVisualBridge.trySpawn(10, 20, 410, 20, config, {segmentKind:"main",intensity:1}) === true,
            "eight-colour custom palette is a source fault, consumed without Flash restore");
        RayVfxManager.spawn(10, 20, 410, 20, config, {segmentKind:"main",intensity:1});
        check(RayVfxManager.getActiveCount() == 0 && RayVisualBridge.getStats().active == 0,
            "inexpressible native config never falls back to the original Flash renderer");
    }

    private static function freshChannels(world:MovieClip):Void {
        // channelVersion=1 已并入必需能力载荷；helper 保留以维持调用点。
        fresh(world);
    }
    private static function channelShot(owner:MovieClip, slot:String, muzzle:MovieClip):Object {
        var props:Object = {子弹种类:"channelFixture", 发射者:owner._name, 霰弹值:1};
        RayVisualBridge.captureShot(owner, slot, muzzle, props, owner[slot]);
        // The real Factory shallow-copies props; identity snapshot itself must stay independent of later captures.
        var bullet:Object = {};
        for (var key:String in props) bullet[key] = props[key];
        bullet.发射者名 = props.发射者;
        RayVisualBridge.bindBulletIdentity(bullet);
        return bullet;
    }
    private static function channelSpawn(bullet:Object, cfg:TeslaRayConfig, sx:Number, ex:Number):Void {
        RayVfxManager.spawnForBullet(bullet, sx, 20, ex, 20, cfg,
            {segmentKind:"main", hitIndex:0, intensity:1, isHit:false});
    }
    private static function eventCount(payload:String, operation:String):Number {
        var rows:Array = payload.split(";"); var count:Number = 0;
        for (var i:Number = 1; i < rows.length; i++) if (rows[i].substr(0, 2) == operation + ",") count++;
        return count;
    }
    private static function testVisualChannels(world:MovieClip):Void {
        var payload:String;
        var oldWorld = _root.gameworld, oldClock = _root.帧计时器;
        _root.gameworld = world; _root.帧计时器 = {当前帧数:100};
        var owner:MovieClip = world.createEmptyMovieClip("channelOwner", 76551);
        owner.version = 801;
        var muzzle:MovieClip = owner.createEmptyMovieClip("muzzle", 1);
        var otherMuzzle:MovieClip = owner.createEmptyMovieClip("muzzle2", 2);
        var weapon:Object = {name:"same-name", value:{shot:0}};
        owner.长枪 = weapon; owner.手枪2 = {name:"same-name", value:{shot:0}};
        var cfg:TeslaRayConfig = TeslaRayConfig.fromXML({vfxStyle:"prism",visualDuration:5,fadeOutDuration:3});
        var initializer:Object = BulletInitializer;
        var savedAttributes:Object = initializer["attributeMap"];
        initializer["attributeMap"] = {channelFixture:{rayConfig:cfg}};
        var oldRandom:Function = Math.random;
        Math.random = fixedGameplayRandom;
        var readOnly:Boolean = Math.random !== fixedGameplayRandom;
        if (readOnly) { _global.ASSetPropFlags(Math, "random", 0, 4); Math.random = fixedGameplayRandom; }
        check(Math.random === fixedGameplayRandom, "channel RNG probe is actually installed");
        randomCalls = 0;
        var damageRng:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();
        var damageState:Number = damageRng.captureState();

        fresh(world);
        var legacyCaps:Object = capabilities(); delete legacyCaps.channelVersion;
        RayVisualBridge.configure(legacyCaps);
        var b:Object = channelShot(owner, "长枪", muzzle);
        check(b._rayVisualIdentity == null && !RayVisualBridge.getStats().enabled,
            "missing channelVersion is an explicit pairing failure, not a downgrade");
        check(RayVisualBridge.flush() == null, "unnegotiated channel emits no wire");

        freshChannels(world);
        b = channelShot(owner, "长枪", muzzle);
        check(b._rayVisualIdentity != null, "real owner slot muzzle and registered ray produce a source identity");
        var scatterProps:Object = {子弹种类:"channelFixture", 发射者:owner._name, 霰弹值:3};
        RayVisualBridge.captureShot(owner, "长枪", muzzle, scatterProps, owner.长枪);
        check(scatterProps._rayVisualShot == null,
            "actual multi-projectile split cannot collapse several near-parallel misses into one channel");
        scatterProps.霰弹值 = 1; initializer["attributeMap"].channelFixture.霰弹值 = 2;
        RayVisualBridge.captureShot(owner, "长枪", muzzle, scatterProps, owner.长枪);
        check(scatterProps._rayVisualShot == null, "prepared XML split override also refuses a shared serial");
        delete initializer["attributeMap"].channelFixture.霰弹值;
        var originalSource:Number = b._rayVisualIdentity.source;
        var oldSerial:Number = b._rayVisualIdentity.serial;
        channelSpawn(b, cfg, 10, 110); channelSpawn(b, cfg, 12, 112);
        payload = RayVisualBridge.flush(); var first:Array = event(payload, "s");
        check(eventCount(payload, "s") == 1 && eventCount(payload, "u") == 0
            && Number(first[5]) == 12 && Number(first[14]) > 0,
            "same-frame birth plus update keeps one s with the latest geometry");
        check(RayVisualBridge.getStats().channelCoalesced == 1, "coalescing is observable on the actual event queue");
        channelSpawn(b, cfg, 13, 113); payload = RayVisualBridge.flush();
        var update:Array = event(payload, "u");
        check(update != null && Number(update[3]) == 0 && Number(update[1]) == Number(first[1]),
            "same shot geometry update keeps original birth and id");
        var newer:Object = channelShot(owner, "长枪", muzzle);
        channelSpawn(newer, cfg, 14, 114); payload = RayVisualBridge.flush(); update = event(payload, "u");
        check(update != null && Number(update[15]) > oldSerial && Number(update[3]) == 2
            && Number(update[13]) == Number(first[13]) && RayVisualBridge.getStats().active == 1,
            "new real shot refreshes pulse age while retaining channel id and visual seed");
        channelSpawn(b, cfg, 15, 115); payload = RayVisualBridge.flush();
        check(event(payload, "s") == null && event(payload, "u") == null,
            "an older serial cannot move an already newer channel backwards");
        var epoch:Number = RayVisualBridge.getStats().epoch;
        RayVisualBridge.configure(capabilities());
        check(RayVisualBridge.getStats().epoch == epoch && RayVisualBridge.getStats().active == 1,
            "identical channel capability retransmission does not erase a live ray");

        var offhand:Object = channelShot(owner, "手枪2", otherMuzzle);
        check(offhand._rayVisualIdentity.source != originalSource, "dual wield slots and muzzles never share source identity");
        owner.长枪 = {name:"same-name", value:{shot:0}};
        var replacement:Object = channelShot(owner, "长枪", muzzle);
        check(replacement._rayVisualIdentity.source != originalSource, "same-name replacement weapon gets a fresh source");
        owner.长枪 = weapon;
        var returned:Object = channelShot(owner, "长枪", muzzle);
        check(returned._rayVisualIdentity.source != originalSource,
            "switching back to the old weapon reference cannot revive its prior source");
        var muzzleSource:Number = returned._rayVisualIdentity.source;
        muzzle.removeMovieClip(); muzzle = owner.createEmptyMovieClip("muzzle", 1);
        returned = channelShot(owner, "长枪", muzzle);
        check(returned._rayVisualIdentity.source != muzzleSource,
            "same-path replacement MovieClip muzzle has a new captured instance token");
        var beforeVersion:Number = returned._rayVisualIdentity.source;
        owner.version++;
        returned = channelShot(owner, "长枪", muzzle);
        check(returned._rayVisualIdentity.source != beforeVersion, "owner instance generation isolates the source registry");
        var stray:MovieClip = world.createEmptyMovieClip("strayMuzzle", 76552);
        check(channelShot(owner, "长枪", stray)._rayVisualIdentity == null, "muzzle outside the real owner subtree is rejected");
        var props:Object = {子弹种类:"channelFixture", 发射者:owner._name, 霰弹值:1};
        RayVisualBridge.captureShot(owner, "长枪", muzzle, props, {name:"same-name"});
        check(props._rayVisualShot == null, "wrong weapon object is not inferred from its name");
        RayVisualBridge.captureShot(owner, "长枪", muzzle, props, owner.长枪);
        _root.帧计时器.当前帧数++;
        props.发射者名 = owner._name;
        RayVisualBridge.bindBulletIdentity(props);
        check(props._rayVisualIdentity == null, "stale firing props cannot supply a later frame with old identity");

        freshChannels(world);
        b = channelShot(owner, "长枪", muzzle); channelSpawn(b, cfg, 10, 110); first = event(RayVisualBridge.flush(), "s");
        newer = channelShot(owner, "长枪", muzzle);
        RayVfxManager.spawnForBullet(newer, 10, 20, 10, 120, cfg, {segmentKind:"main",isHit:false,intensity:1});
        payload = RayVisualBridge.flush();
        check(event(payload, "s") != null && Number(event(payload, "s")[1]) != Number(first[1])
            && Number(event(payload, "s")[14]) == Number(first[14]), "turn discontinuity uses a new exact segment on the same source channel");
        newer = channelShot(owner, "长枪", muzzle); channelSpawn(newer, cfg, 300, 400);
        check(event(RayVisualBridge.flush(), "s") != null, "teleporting muzzle never deforms the previous ray into a long false path");

        freshChannels(world);
        var targetA:MovieClip = world.createEmptyMovieClip("channelTargetA", 76553); targetA.version = 911;
        var targetB:MovieClip = world.createEmptyMovieClip("channelTargetB", 76554); targetB.version = 912;
        b = channelShot(owner, "长枪", muzzle); RayVisualBridge.noteTarget(b, targetA);
        RayVfxManager.spawnForBullet(b, 10, 20, 110, 20, cfg, {segmentKind:"main",hitIndex:0,isHit:true,intensity:1});
        first = event(RayVisualBridge.flush(), "s");
        newer = channelShot(owner, "长枪", muzzle); RayVisualBridge.noteTarget(newer, targetB);
        RayVfxManager.spawnForBullet(newer, 10, 20, 110, 20, cfg, {segmentKind:"main",hitIndex:0,isHit:true,intensity:1});
        update = event(RayVisualBridge.flush(), "s");
        check(update != null && Number(update[14]) != Number(first[14]), "different actual target topology cannot merge even at equal coordinates");
        newer = channelShot(owner, "长枪", muzzle); RayVisualBridge.noteTarget(newer, {version:911,_name:"channelTargetA"});
        RayVfxManager.spawnForBullet(newer, 10, 20, 110, 20, cfg, {segmentKind:"main",isHit:true,intensity:1});
        check(Number(event(RayVisualBridge.flush(), "s")[14]) == 0, "unproven target identity stays independent");

        freshChannels(world); cfg.chainDelay = 2;
        b = channelShot(owner, "长枪", muzzle); RayVisualBridge.noteTarget(b, targetA);
        RayVfxManager.spawnForBullet(b, 10, 20, 110, 20, cfg, {segmentKind:"chain",hitIndex:1,isHit:true,intensity:1});
        newer = channelShot(owner, "长枪", muzzle); RayVisualBridge.noteTarget(newer, targetA);
        RayVfxManager.spawnForBullet(newer, 10, 20, 110, 20, cfg, {segmentKind:"chain",hitIndex:1,isHit:true,intensity:1});
        payload = RayVisualBridge.flush();
        check(eventCount(payload, "s") == 2 && Number(event(payload, "s")[4]) == 2 && Number(event(payload, "s")[14]) == 0,
            "delayed chain segments keep separate births and their authored delay");
        cfg.chainDelay = 0;

        var styles:Array = RayStyleRegistry.getStyleNames();
        for (var styleIndex:Number = 0; styleIndex < 10; styleIndex++) {
            freshChannels(world); cfg.vfxStyle = styles[styleIndex];
            b = channelShot(owner, "长枪", muzzle); channelSpawn(b, cfg, 10, 110); RayVisualBridge.flush();
            newer = channelShot(owner, "长枪", muzzle); channelSpawn(newer, cfg, 10, 110);
            check(event(RayVisualBridge.flush(), "u") != null && RayVisualBridge.getStats().active == 1,
                "ordinary style uses the negotiated channel: " + styles[styleIndex]);
        }
        freshChannels(world); cfg.vfxStyle = "bagua_rod";
        b = channelShot(owner, "长枪", muzzle); channelSpawn(b, cfg, 10, 310);
        newer = channelShot(owner, "长枪", muzzle); channelSpawn(newer, cfg, 10, 310);
        payload = RayVisualBridge.flush();
        check(eventCount(payload, "s") == 2 && Number(event(payload, "s")[14]) == 0, "Bagua retains independent structural pulses");

        freshChannels(world); cfg.vfxStyle = "prism";
        b = channelShot(owner, "长枪", muzzle); channelSpawn(b, cfg, 10, 110); first = event(RayVisualBridge.flush(), "s");
        cfg.thickness += 1;
        newer = channelShot(owner, "长枪", muzzle); channelSpawn(newer, cfg, 10, 110);
        payload = RayVisualBridge.flush(); update = event(payload, "s");
        check(event(payload, "c") != null && update != null && Number(update[2]) != Number(first[2])
            && Number(update[14]) != Number(first[14]), "mutable configuration produces a fresh definition and independent channel");

        freshChannels(world); cfg.visualDuration = 1; cfg.fadeOutDuration = 1;
        b = channelShot(owner, "长枪", muzzle); channelSpawn(b, cfg, 10, 110);
        RayVisualBridge.flush(); RayVisualBridge.flush(); RayVisualBridge.flush();
        check(RayVisualBridge.getStats().active == 0, "ordinary channel expires under the real game clock");
        channelSpawn(b, cfg, 11, 111); payload = RayVisualBridge.flush();
        check(event(payload, "s") == null && event(payload, "u") == null && RayVisualBridge.getStats().active == 0,
            "expired same-serial snapshots cannot resurrect a finished pulse");
        newer = channelShot(owner, "长枪", muzzle); channelSpawn(newer, cfg, 11, 111);
        check(event(RayVisualBridge.flush(), "s") != null, "a genuinely new shot can restart an expired source channel");

        freshChannels(world); cfg.visualDuration = 5; cfg.fadeOutDuration = 3;
        b = channelShot(owner, "长枪", muzzle); channelSpawn(b, cfg, 10, 110);
        for (var age:Number = 0; age < 6; age++) RayVisualBridge.flush();
        newer = channelShot(owner, "长枪", muzzle); channelSpawn(newer, cfg, 10, 110); RayVisualBridge.flush();
        var caps:Object = capabilities(); caps.channelVersion = 0;
        RayVisualBridge.configure(caps);
        check(RayVfxManager.getActiveCount() == 0 && !RayVisualBridge.getStats().enabled
            && RayVisualBridge.getStats().active >= 1,
            "unsupported channelVersion is a pairing fault; live rays stay owned for resync");
        check(!RayVisualBridge.getStats().channelsEnabled, "capability downgrade disables further ordinary channel updates");

        freshChannels(world); cfg.vfxStyle = "flame_stream";
        RayVfxManager.spawn(10, 20, 110, 20, cfg, flame(1, 100));
        RayVfxManager.spawn(10, 20, 120, 20, cfg, flame(1, 100));
        RayVisualBridge.stopFlame("tester:flame", 1);
        RayVfxManager.spawn(10, 20, 130, 20, cfg, flame(2, 100));
        payload = RayVisualBridge.flush();
        var parts:Array = payload.split(";"); var operations:String = "";
        for (var p:Number = 1; p < parts.length; p++) {
            var op:String = parts[p].substr(0, 1);
            if (op == "s" || op == "u" || op == "x") operations += op;
        }
        check(operations == "sxs", "same-frame coalescing retains birth-stop-new-birth ordering for flame");
        _root.暂停 = true;
        var pausedTick:Number = RayVisualBridge.getStats().tick;
        RayVisualBridge.flush();
        check(RayVisualBridge.getStats().tick == pausedTick, "pause never advances the negotiated channel clock");
        _root.暂停 = false;

        freshChannels(world); cfg.vfxStyle = "flame_stream";
        b = channelShot(owner, "长枪", muzzle); offhand = channelShot(owner, "手枪2", otherMuzzle);
        b._flameVfxKey = RayVisualBridge.flameKey(b); b._flameVfxSerial = 1;
        offhand._flameVfxKey = RayVisualBridge.flameKey(offhand); offhand._flameVfxSerial = 2;
        var fireA:Object = flame(1, 100); fireA.flameVfxKey = b._flameVfxKey;
        var fireB:Object = flame(2, 100); fireB.flameVfxKey = offhand._flameVfxKey;
        RayVfxManager.spawnForBullet(b, 10, 20, 110, 20, cfg, fireA);
        RayVfxManager.spawnForBullet(offhand, 10, 20, 110, 20, cfg, fireB);
        payload = RayVisualBridge.flush();
        check(b._flameVfxKey != offhand._flameVfxKey && eventCount(payload, "s") == 2
            && RayVisualBridge.getStats().active == 2, "new capability isolates two real flame muzzles on one actor");
        RayVisualBridge.stopFlame(b._flameVfxKey, b._flameVfxSerial);
        RayVfxManager.spawnForBullet(offhand, 10, 20, 120, 20, cfg, fireB);
        payload = RayVisualBridge.flush();
        check(event(payload, "x") != null && event(payload, "u") != null
            && Number(event(payload, "x")[1]) != Number(event(payload, "u")[1]),
            "bullet stop uses the captured flame key and cannot stop the other hand");
        fresh(world);
        check(RayVisualBridge.flameKey(b) == "source:" + b._rayVisualIdentity.source + ":channelFixture",
            "paired capability keeps the captured source identity as the flame key");
        check(randomCalls == 0 && damageRng.captureState() == damageState,
            "source capture topology and channel reuse consume neither global nor dedicated gameplay RNG");
        Math.random = oldRandom; if (readOnly) _global.ASSetPropFlags(Math, "random", 4, 0);
        initializer["attributeMap"] = savedAttributes;
        RayVfxManager.reset(); RayVisualBridge.disconnect();
        owner.removeMovieClip(); stray.removeMovieClip(); targetA.removeMovieClip(); targetB.removeMovieClip();
        _root.gameworld = oldWorld; _root.帧计时器 = oldClock;
    }
    private static function freshLighting(world:MovieClip):Void {
        // lightingVersion=1 已并入必需能力载荷；helper 保留以维持调用点。
        fresh(world);
    }
    private static function testLightOverrides(world:MovieClip):Void {
        var oldRandom:Function = Math.random;
        Math.random = fixedGameplayRandom;
        var mathReadOnly:Boolean = Math.random !== fixedGameplayRandom;
        if (mathReadOnly) { _global.ASSetPropFlags(Math, "random", 0, 4);Math.random = fixedGameplayRandom; }
        check(Math.random === fixedGameplayRandom, "lighting RNG probe is actually installed");
        randomCalls = 0;
        var rng:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();
        var rngState:Number = rng.captureState();
        var config:TeslaRayConfig = new TeslaRayConfig();
        check(config.lightProfile == "auto" && config.lightEnergyScale === 1 && config.lightWidthScale === 1
            && config.lightColor === -1 && config.lightFadeTicks === -1, "constructor lighting defaults are explicit and valid");
        config = TeslaRayConfig.fromXML({vfxStyle:"prism"});
        fresh(world);
        RayVfxManager.spawn(10, 20, 410, 20, config, null);
        var payload:String = RayVisualBridge.flush();
        check(event(payload, "c") != null && event(payload, "l") != null,
            "paired capability always carries the light record for its config");
        var oldEpoch:Number = RayVisualBridge.getStats().epoch;
        var caps:Object = capabilities(); delete caps.lightingVersion;
        RayVisualBridge.configure(caps);
        check(!RayVisualBridge.getStats().enabled && RayVfxManager.getActiveCount() == 0,
            "missing lightingVersion is an explicit pairing failure, never a downgrade");
        caps = capabilities();
        RayVisualBridge.configure(caps);
        check(RayVisualBridge.getStats().epoch > oldEpoch && RayVisualBridge.getStats().active == 1,
            "re-grant after a rejected capability resyncs the retained live ray");
        RayVfxManager.reset();
        RayVfxManager.spawn(10, 20, 410, 20, config, null);
        payload = RayVisualBridge.flush();
        var light:Array = event(payload, "l");
        check(light != null && light[2] == "auto" && Number(light[3]) == 1 && Number(light[4]) == 1
            && Number(light[5]) == -1 && Number(light[6]) == -1, "new host gets default auto light metadata");
        var lines:Array = payload.split(";");
        check(lines[2].substr(0, 4) == "c,1," && lines[3] == "l,1,auto,1,1,-1,-1",
            "light definition immediately follows its immutable config definition");
        oldEpoch = RayVisualBridge.getStats().epoch;
        RayVisualBridge.configure(caps);
        check(RayVisualBridge.getStats().epoch == oldEpoch, "identical lighting capabilities do not reset active rays");

        freshLighting(world);
        config = TeslaRayConfig.fromXML({vfxStyle:"prism",rayMode:"pierce",damageFalloff:0.75,chainDelay:2,
            lightProfile:"beam",lightEnergyScale:"1.5",lightWidthScale:"0.75",lightColor:"#FF8800",lightFadeTicks:"12"});
        check(config.lightProfile == "beam" && config.lightEnergyScale === 1.5 && config.lightWidthScale === 0.75
            && config.lightColor === 0xFF8800 && config.lightFadeTicks === 12, "per-weapon XML light override is parsed without losing colour or sentinels");
        check(config.rayMode == "pierce" && config.damageFalloff === 0.75 && config.chainDelay === 2,
            "light parsing leaves ray gameplay fields unchanged");
        RayVfxManager.spawn(10, 20, 410, 20, config, null);
        payload = RayVisualBridge.flush();light = event(payload, "l");
        check(light[2] == "beam" && Number(light[3]) == 1.5 && Number(light[4]) == 0.75
            && Number(light[5]) == 0xFF8800 && Number(light[6]) == 12, "resolved lighting override crosses the production wire");
        trace("[RAY_LIGHT_WIRE] " + payload);
        RayVfxManager.spawn(10, 25, 410, 25, config, null);payload = RayVisualBridge.flush();
        check(event(payload, "c") == null && event(payload, "l") == null,
            "unchanged light config is emitted once instead of repeated per shot");
        config.lightWidthScale = 2;
        RayVfxManager.spawn(10, 30, 410, 30, config, null);payload = RayVisualBridge.flush();light = event(payload, "l");
        check(light != null && Number(light[1]) == 2 && Number(light[4]) == 2,
            "changing only a light knob creates a new immutable config id");
        config.lightProfile = "none";
        RayVfxManager.spawn(10, 35, 410, 35, config, null);payload = RayVisualBridge.flush();light = event(payload, "l");
        check(light[2] == "none" && event(payload, "s") != null && RayVisualBridge.getStats().active == 4,
            "none disables lighting while native ray geometry stays owned and visible");
        trace("[RAY_LIGHT_NONE_WIRE] " + payload);

        config = TeslaRayConfig.fromXML({lightEnergyScale:1.5,lightProfile:"beam",
            vfxParams:{lightProfile:"arc",lightEnergyScale:0.5,lightWidthScale:2,lightColor:"0x123456",lightFadeTicks:0}});
        check(config.lightProfile == "arc" && config.lightEnergyScale === 0.5 && config.lightWidthScale === 2
            && config.lightColor === 0x123456 && config.lightFadeTicks === 0, "vfxParams override only the declared lighting fields");
        var bad:Array = [
            {lightProfile:"beam;injected"}, {lightEnergyScale:3}, {lightEnergyScale:Number(undefined)},
            {lightWidthScale:0.2}, {lightWidthScale:1 / 0}, {lightColor:-2}, {lightColor:16777216},
            {lightColor:1.5}, {lightFadeTicks:31}, {lightFadeTicks:0.5}, {lightFadeTicks:Number(undefined)}
        ];
        for (var i:Number = 0; i < bad.length; i++) {
            freshLighting(world);config = new TeslaRayConfig();
            for (var key:String in bad[i]) config[key] = bad[i][key];
            config.vfxStyle = "prism";
            check(RayVisualBridge.trySpawn(10, 20, 410, 20, config, null) === true
                && RayVfxManager.getActiveCount() == 0,
                "invalid light override is consumed with a fault, never Flash-restored #" + i);
        }
        RayVfxManager.spawn(10, 20, 410, 20, config, null);
        check(RayVfxManager.getActiveCount() == 0 && RayVisualBridge.getStats().active == 0,
            "invalid light metadata is consumed without a Flash owner");
        freshLighting(world);
        config = TeslaRayConfig.fromXML({vfxParams:{lightEnergyScale:"invalid"}});
        check(RayVisualBridge.trySpawn(10, 20, 410, 20, config, null) === true,
            "invalid numeric vfxParams light input is a consumed source fault");
        config = TeslaRayConfig.fromXML({lightColor:"0xFFoops"});
        check(RayVisualBridge.trySpawn(10, 20, 410, 20, config, null) === true,
            "partial hexadecimal light colour is a consumed source fault");
        config = TeslaRayConfig.fromXML({vfxParams:{lightColor:"#12345z"}});
        check(RayVisualBridge.trySpawn(10, 20, 410, 20, config, null) === true,
            "malformed vfxParams colour is a consumed source fault");
        fresh(world);caps = capabilities();caps.lightingVersion = "1";RayVisualBridge.configure(caps);
        check(!RayVisualBridge.getStats().enabled,
            "lighting version negotiation requires numeric one");
        config = new TeslaRayConfig();RayVfxManager.spawn(10, 20, 410, 20, config, null);
        check(RayVfxManager.getActiveCount() == 0,
            "unnegotiated channel cannot create a Flash fallback");
        Math.random = oldRandom;
        if (mathReadOnly) _global.ASSetPropFlags(Math, "random", 4, 0);
        check(randomCalls == 0 && rng.captureState() == rngState, "lighting admission, rejection and serialization never sample gameplay RNG");
    }

    /** Count actual new child clips after each spawn/update, outside all timed regions.
     * Only FlameStreamRenderer creates nested clips; its body/glow are retained, never transient.
     * Arc ids are monotonic, so target paths cannot alias within this benchmark. */
    private static function observeClips(parent:MovieClip, seen:Object, result:Object):Number {
        var alive:Number = 0;
        for (var member:String in parent) {
            var child = parent[member];
            if (typeof child != "movieclip" || child._parent !== parent) continue;
            var key:String = "$" + child._target;
            if (seen[key] !== true) { seen[key] = true; result.movieClipCreated++; }
            alive++;
            alive += observeClips(child, seen, result);
        }
        return alive;
    }
    private static function oneCostRun(world:MovieClip, configs:Array, count:Number,
        ticks:Number, nativeOwner:Boolean):Object {
        fresh(world);
        RayVfxManager.referenceRenderingForTests = !nativeOwner;
        if (!nativeOwner) RayVisualBridge.disconnect();
        var result:Object = {spawnMs:0, updateMs:0, flushMs:0, wireBytes:0, maxWireBytes:0,
            movieClipCreated:0, maxLiveClips:0, arcCreated:0, randomCalls:0,
            maintained:true, lod:0, measuredTicks:ticks};
        var seen:Object = {};
        var randomBefore:Number = RayVisualBridgeTest.randomCalls;
        var begin:Number;
        for (var i:Number = 0; i < count; i++) {
            var x:Number = i % 2 == 0 ? 44 : 552;
            var y:Number = 58 + Math.floor((i % 12) / 2) * 80 + (i > 11 ? 8 : 0);
            var config:TeslaRayConfig = configs[i % 12];
            var meta:Object = {segmentKind:"main",hitIndex:0,intensity:1,isHit:true,hitPoints:null};
            begin = getTimer();
            RayVfxManager.spawn(x, y, x + 410, y, config, meta);
            result.spawnMs += getTimer() - begin;
            var alive:Number = observeClips(world.rayVfxContainer, seen, result);
            if (alive > result.maxLiveClips) result.maxLiveClips = alive;
        }
        result.arcCreated = RayVfxManager.getActiveCount();
        for (var tick:Number = 0; tick < ticks; tick++) {
            begin = getTimer();
            RayVfxManager.update();
            result.updateMs += getTimer() - begin;
            begin = getTimer();
            var wire:String = RayVisualBridge.flush();
            result.flushMs += getTimer() - begin;
            // Wire is numeric ASCII only: character length equals UTF-8 byte length.
            var bytes:Number = wire == null ? 0 : wire.length;
            result.wireBytes += bytes;
            if (bytes > result.maxWireBytes) result.maxWireBytes = bytes;
            var active:Number = nativeOwner ? RayVisualBridge.getStats().active : RayVfxManager.getActiveCount();
            if (active != count) result.maintained = false;
            alive = observeClips(world.rayVfxContainer, seen, result);
            if (alive > result.maxLiveClips) result.maxLiveClips = alive;
            result.lod = RayVfxManager.getCurrentLOD();
        }
        result.randomCalls = RayVisualBridgeTest.randomCalls - randomBefore;
        return result;
    }
    private static function combineCost(total:Object, run:Object):Void {
        total.spawnMs += run.spawnMs; total.updateMs += run.updateMs; total.flushMs += run.flushMs;
        total.wireBytes += run.wireBytes;total.measuredTicks += run.measuredTicks;
        total.movieClipCreated += run.movieClipCreated;total.arcCreated += run.arcCreated;
        total.randomCalls += run.randomCalls;
        if (run.maxLiveClips > total.maxLiveClips) total.maxLiveClips = run.maxLiveClips;
        if (run.maxWireBytes > total.maxWireBytes) total.maxWireBytes = run.maxWireBytes;
        if (!run.maintained) total.maintained = false;
        total.lod = run.lod;
    }
    private static function printCost(total:Object, owner:String, count:Number, repetitions:Number):Void {
        trace("[RAY_AS2_COST] owner=" + owner + " activeArcs=" + count + " repetitions=" + repetitions
            + " ticks=" + total.measuredTicks + " spawnMs=" + total.spawnMs + " updateMs=" + total.updateMs
            + " flushMs=" + total.flushMs + " arcMcCreated=" + total.arcCreated
            + " movieClipCreated=" + total.movieClipCreated + " maxLiveClips=" + total.maxLiveClips
            + " wireBytes=" + total.wireBytes + " avgWireBytesPerTick=" + Math.round(total.wireBytes / total.measuredTicks * 10) / 10
            + " maxWireBytesPerTick=" + total.maxWireBytes + " gameplayRandomSamples=" + total.randomCalls
            + " legacyLOD=" + total.lod + " maintained=" + total.maintained);
    }
    private static function emptyCost():Object {
        return {spawnMs:0,updateMs:0,flushMs:0,wireBytes:0,maxWireBytes:0,movieClipCreated:0,
            arcCreated:0,maxLiveClips:0,randomCalls:0,measuredTicks:0,lod:0,maintained:true};
    }
    private static function benchmarkAs2Costs(world:MovieClip):Void {
        var started:Number = getTimer();
        var names:Array = RayStyleRegistry.getStyleNames();
        var configs:Array = [];
        var ticks:Number = 24, repetitions:Number = 3;
        for (var i:Number = 0; i < names.length; i++) {
            var config:TeslaRayConfig = TeslaRayConfig.fromXML({vfxStyle:names[i],
                vfxPreset:RayStyleRegistry.getDefaultPreset(names[i])});
            // Keep all arcs alive for the matched load. No style geometry, width, colours,
            // random branch probability or existing Flash LOD rules are simplified.
            config.visualDuration = ticks + 2;
            configs[i] = config;
        }
        var oldRandom:Function = Math.random;
        Math.random = fixedGameplayRandom;
        var mathReadOnly:Boolean = Math.random !== fixedGameplayRandom;
        if (mathReadOnly) { _global.ASSetPropFlags(Math, "random", 0, 4);Math.random = fixedGameplayRandom; }
        check(Math.random === fixedGameplayRandom, "cost benchmark gameplay RNG probe is installed");
        trace("[RAY_AS2_COST_SCOPE] getTimer-resolution-ms=1; AS2-function-cost-only; no-frame-paint/GPU/FPS; setup-and-clip-observation-excluded; same-resolved-config-and-geometry; lifetime-extended-only; stock-LOD; warmup=1-per-mode/load");
        for (var load:Number = 0; load < 2; load++) {
            var count:Number = load == 0 ? 12 : 24;
            oneCostRun(world, configs, count, ticks, false);
            oneCostRun(world, configs, count, ticks, true);
            var legacy:Object = emptyCost(), nativeCost:Object = emptyCost();
            for (var repetition:Number = 0; repetition < repetitions; repetition++) {
                // Reverse owner order each repetition to reduce ordering/cache bias.
                if (repetition % 2 == 0) {
                    combineCost(legacy, oneCostRun(world, configs, count, ticks, false));
                    combineCost(nativeCost, oneCostRun(world, configs, count, ticks, true));
                } else {
                    combineCost(nativeCost, oneCostRun(world, configs, count, ticks, true));
                    combineCost(legacy, oneCostRun(world, configs, count, ticks, false));
                }
            }
            printCost(legacy, "flash", count, repetitions);
            printCost(nativeCost, "native-bridge", count, repetitions);
            check(legacy.maintained && nativeCost.maintained, count + " active arcs survive every measured tick on both owners");
            check(legacy.movieClipCreated > 0 && nativeCost.movieClipCreated == 0,
                count + " native arc load creates no Flash child clips");
            check(legacy.randomCalls == 0 && nativeCost.randomCalls == 0,
                count + " display-only load leaves gameplay Math.random untouched on both owners");
            check(legacy.wireBytes == 0 && nativeCost.wireBytes > 0,
                count + " cost sample accounts for native wire instead of hiding serialization");
        }
        Math.random = oldRandom;
        if (mathReadOnly) _global.ASSetPropFlags(Math, "random", 4, 0);
        var elapsed:Number = getTimer() - started;
        trace("[RAY_AS2_COST_DONE] wallMs=" + elapsed);
        check(elapsed < 30000, "bounded AS2 cost comparison finishes within 30 seconds");
    }

    /** 真实预设 -> 生产桥 -> wire；Host/GPU 夹具直接重放此输出。 */
    private static function emitGpuWire(world:MovieClip):Void {
        freshLighting(world);
        trace("[RAY_GPU_SCENE] gallery");
        var names:Array = RayStyleRegistry.getStyleNames();
        for (var i:Number = 0; i < names.length; i++) {
            var cfg:TeslaRayConfig = TeslaRayConfig.fromXML({vfxStyle:names[i],
                vfxPreset:RayStyleRegistry.getDefaultPreset(names[i])});
            var x:Number = (i % 2 == 0) ? 44 : 552;
            var y:Number = 58 + Math.floor(i / 2) * 88;
            RayVfxManager.spawn(x, y, x + 410, y, cfg,
                {segmentKind:"main",hitIndex:0,intensity:1,isHit:true,hitPoints:null});
        }
        trace("[RAY_GPU_WIRE] " + RayVisualBridge.flush());
        freshLighting(world);
        trace("[RAY_GPU_SCENE] flame");
        var fire:TeslaRayConfig = TeslaRayConfig.fromXML({vfxStyle:"flame_stream",vfxPreset:"flame_stream"});
        for (var tick:Number = 0; tick < 40; tick++) {
            for (var sample:Number = 0; sample < 3; sample++) {
                var blocked:Boolean = tick > 11 && tick < 25;
                var m:Object = flame(1 + Math.floor(tick / 12), blocked ? 220 : 800);
                m.flameVfxKey = "gpu:" + sample;
                m.pulseIndex = tick % 5; m.pulseCount = 5;
                m.isHotPulse = m.pulseIndex == 1 || m.pulseIndex == 2;
                m.isDamagePulse = tick % 2 == 0; m.isBlocked = blocked;
                if (sample == 0) RayVfxManager.spawn(80, 110, blocked ? 300 : 930, 110, fire, m);
                else if (sample == 1) RayVfxManager.spawn(100, 250, blocked ? 300 : 650, blocked ? 327 : 460, fire, m);
                else RayVfxManager.spawn(720, 340, 850, 340, fire, m);
            }
            trace("[RAY_GPU_WIRE] " + RayVisualBridge.flush());
        }
        for (var fade:Number = 0; fade < 5; fade++) trace("[RAY_GPU_WIRE] " + RayVisualBridge.flush());
    }

}
