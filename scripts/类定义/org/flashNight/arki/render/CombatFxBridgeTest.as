import flash.display.BitmapData;
import org.flashNight.arki.render.CombatFxBridge;
import org.flashNight.arki.render.DecalStampQueue;
import org.flashNight.arki.render.FrameBroadcaster;
import org.flashNight.arki.render.VisualRandom;
import org.flashNight.arki.component.Effect.EffectSystem;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

class org.flashNight.arki.render.CombatFxBridgeTest {
    private static var passed:Number;
    private static var failed:Number;
    public static var made:Number;
    public static var packet:String;

    private static function check(ok:Boolean, name:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] CombatFxBridgeTest: " + name); }
    }

    public static function runAllTests():Void {
        passed = 0; failed = 0; made = 0; packet = "";
        var oldWorld:MovieClip = _root.gameworld;
        var oldServer:Object = _root.server;
        var oldPause = _root.暂停;
        var oldVisual = _root.是否视觉元素;
        var oldMax:Number = EffectSystem.maxEffectCount;
        var world:MovieClip = _root.createEmptyMovieClip("combatFxTestWorld", 76546);
        var effects:MovieClip = world.createEmptyMovieClip("效果", 1);
        var body:MovieClip = world.createEmptyMovieClip("deadbody", 2);
        body._x = 10; body._y = 20;
        var pixels:BitmapData = new BitmapData(256, 256, true, 0);
        body.layers = [null, null, pixels];
        world.effectPools = {};
        effects.attachMovie = function(linkage:String, name:String, depth:Number):MovieClip {
            CombatFxBridgeTest.made++;
            var clip:MovieClip = this.createEmptyMovieClip(name, depth);
            clip.beginFill(0xFFFFFF, 100);
            clip.moveTo(0, 0); clip.lineTo(8, 0); clip.lineTo(8, 4); clip.lineTo(0, 4); clip.lineTo(0, 0);
            clip.endFill();
            return clip;
        };
        _root.gameworld = world;
        _root.暂停 = false;
        _root.是否视觉元素 = true;
        _root.server = {isSocketConnected:true, sendSocketMessage:function(value:String):Void {
            CombatFxBridgeTest.packet = value;
        }};
        FrameBroadcaster.reset();
        DecalStampQueue.clearCache();
        var caps:Object = {version:1, generation:2,
            digest:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            styles:[{index:0, linkage:"测试弹壳", kind:"casing"},
                    {index:1, linkage:"测试枪火", kind:"muzzle"},
                    {index:2, linkage:"测试命中", kind:"impact"}]};
        caps["native"] = true;
        CombatFxBridge.configure(caps);
        check(CombatFxBridge.getStats().enabled === true, "capability admits known styles");
        var stale:Object = {version:1, generation:1, digest:caps.digest, styles:caps.styles};
        stale["native"] = false;
        CombatFxBridge.configure(stale);
        check(CombatFxBridge.getStats().enabled === true, "old connection capability cannot revoke current ownership");
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
        DecalStampQueue.clearCache();
        pixels.dispose();
        _root.gameworld = oldWorld;_root.server = oldServer;
        _root.暂停 = oldPause;_root.是否视觉元素 = oldVisual;
        world.removeMovieClip();
        trace("CombatFxBridgeTest Tests Passed: " + passed);
        trace("CombatFxBridgeTest Tests Failed: " + failed);
    }
}
