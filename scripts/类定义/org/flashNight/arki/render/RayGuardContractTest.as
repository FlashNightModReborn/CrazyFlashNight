import org.flashNight.arki.render.RayVfxManager;
import org.flashNight.arki.render.RayStyleRegistry;
import org.flashNight.arki.render.VisualRandom;
import org.flashNight.arki.spatial.transform.SceneCoordinateManager;
import org.flashNight.naki.RandomNumberEngine.SeededLinearCongruentialEngine;

/** Fixed visual RNG; records and forwards real MovieClip drawing calls for before/after comparison. */
class org.flashNight.arki.render.RayGuardContractTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static function check(ok:Boolean,label:String):Void {
        if (ok) passed++; else {failed++; trace("[FAIL] RayGuardContractTest: " + label);}
    }
    private static function encode(value):String {
        if (value instanceof Array) {
            var parts:Array = [];
            for (var i:Number = 0; i < value.length; i++) parts.push(encode(value[i]));
            return "[" + parts.join(",") + "]";
        }
        if (typeof value == "object" && value != null) {
            var keys:Array = [];
            for (var key:String in value) if (typeof value[key] != "function") keys.push(key);
            keys.sort();
            var text:String = "{";
            for (i = 0; i < keys.length; i++) text += keys[i] + ":" + encode(value[keys[i]]) + ",";
            return text + "}";
        }
        return typeof value + ":" + String(value);
    }
    private static function drawRecorder(original:Function,method:String,stats:Object):Function {
        return function() {
            var line:String = method;
            for (var i:Number = 0; i < arguments.length; i++) line += "|" + RayGuardContractTest.encode(arguments[i]);
            stats.calls++;
            for (i = 0; i < line.length; i++) {
                var code:Number = line.charCodeAt(i);
                stats.h1 = (stats.h1 * 31 + code) % 2147483647;
                stats.h2 = (stats.h2 * 131 + code) % 2147483629;
            }
            return original.apply(this,arguments);
        };
    }
    private static function childRecorder(original:Function,stats:Object):Function {
        return function() {
            var child:MovieClip = original.apply(this,arguments);
            RayGuardContractTest.observeDrawing(child,stats);
            return child;
        };
    }
    private static function observeDrawing(mc:MovieClip,stats:Object):Void {
        var names:Array = ["clear","lineStyle","moveTo","lineTo","curveTo","beginFill","beginGradientFill","endFill"];
        for (var i:Number = 0; i < names.length; i++) mc[names[i]] = drawRecorder(mc[names[i]],names[i],stats);
        mc.createEmptyMovieClip = childRecorder(mc.createEmptyMovieClip,stats);
    }
    private static function metaFor(index:Number):Object {
        if (index == 0) return null;
        if (index == 1) return {};
        if (index == 2) return {segmentKind:"fork",intensity:0.75,isHit:true};
        if (index == 3) return {segmentKind:"pierce",intensity:1,hitPoints:[{x:80,y:40},{x:120,y:45}],isHit:true};
        return {segmentKind:"flame",isBlocked:true,intensity:0.8,pulseIndex:2,pulseCount:4,
            shotSeed:19,isDamagePulse:true,damageHitPoints:[{x:120,y:45}]};
    }
    private static function testRenderMatrix(parent:MovieClip):Void {
        var styles:Array = RayStyleRegistry.getStyleNames();
        check(styles.length > 10,"registered real renderer matrix");
        var randomFacade:Object = VisualRandom;
        for (var s:Number = 0; s < styles.length; s++) {
            for (var variant:Number = 0; variant < 5; variant++) {
                for (var lod:Number = 0; lod < 3; lod++) {
                    randomFacade.engine = new SeededLinearCongruentialEngine(2468);
                    RayVfxManager.resetPools();
                    var mc:MovieClip = parent.createEmptyMovieClip("drawing",parent.getNextHighestDepth());
                    var stats:Object = {calls:0,h1:1,h2:1};
                    observeDrawing(mc,stats);
                    var config:Object = variant == 0 ? null : {counterRotate:variant == 2};
                    var arc:Object = {startX:20,startY:30,endX:180,endY:50,age:2,phaseAge:2,
                        config:config,meta:metaFor(variant),visualDuration:5,fadeDuration:3,totalDuration:8};
                    RayStyleRegistry.renderArc(styles[s],arc,lod,mc);
                    var bounds:Object = mc.getBounds(mc);
                    check(stats.calls > 0 && bounds.xMax > bounds.xMin,
                        "actual draw " + styles[s] + "/" + variant + "/" + lod);
                    trace("AS2_GUARD_DRAW " + styles[s] + "/" + variant + "/" + lod + " "
                        + stats.calls + "/" + stats.h1 + "/" + stats.h2 + "/" + encode(bounds));
                    mc.removeMovieClip();
                }
            }
        }
    }
    private static function testManagerInputs(parent:MovieClip):Void {
        var manager:Object = RayVfxManager;
        var coords:Object = SceneCoordinateManager;
        var offsets:Array = [undefined,null,{}, {x:5,y:-3}, {x:"7",y:2}, {x:1.0/0,y:Number(undefined)}];
        for (var i:Number = 0; i < offsets.length; i++) {
            coords.effectOffset = offsets[i];
            RayVfxManager.initWithContainer(parent);
            RayVfxManager.spawn(10,20,110,40,null,null);
            var arc:Object = manager._activeArcs[0];
            var ox:Number = i == 3 ? 5 : (i == 4 ? 7 : 0);
            var oy:Number = i == 3 ? -3 : (i == 4 ? 2 : 0);
            check(RayVfxManager.getActiveCount() == 1 && arc.vfxStyle == "tesla" && !arc.flickerEnabled,
                "null config/meta default arc " + i);
            check(arc.startX == 10 + ox && arc.startY == 20 + oy && arc.endX == 110 + ox,
                "missing/finite/malformed offset semantics " + i);
            RayVfxManager.reset();
        }
    }
    public static function runAllTests():Void {
        passed = failed = 0;
        var coords:Object = SceneCoordinateManager;
        var oldOffset:Object = coords.effectOffset;
        var randomFacade:Object = VisualRandom;
        var oldEngine:Object = randomFacade.engine;
        var oldReference:Boolean = RayVfxManager.referenceRenderingForTests;
        RayVfxManager.referenceRenderingForTests = true;
        var parent:MovieClip = _root.createEmptyMovieClip("__rayGuardFixture",_root.getNextHighestDepth());
        testRenderMatrix(parent);
        testManagerInputs(parent);
        RayVfxManager.reset();
        parent.removeMovieClip();
        coords.effectOffset = oldOffset;
        randomFacade.engine = oldEngine;
        RayVfxManager.referenceRenderingForTests = oldReference;
        trace("RayGuardContractTest Tests Passed: " + passed);
        trace("RayGuardContractTest Tests Failed: " + failed);
    }
}
