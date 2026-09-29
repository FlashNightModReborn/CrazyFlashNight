import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/** Original Ray/Band.checkCollision is the geometry oracle; this suite does not duplicate Slab. */
class org.flashNight.arki.bullet.BulletComponent.Queue.RayScanGeometryTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var pairs:Number;
    private static var rejected:Number;
    private static var hits:Number;
    private static var fallbackCalls:Number;
    private static function check(value:Boolean, name:String):Void {
        if (value) passed++;
        else { failed++; trace("[TEST_FAIL] RayScanGeometryTest: " + name); }
    }
    private static function pair(ray:Object, target:Object, z:Number, width:Number, name:String):Void {
        // Each collider returns a reused static result. Capture primitive values before another call.
        var original:Object = ray.checkCollision(target, z);
        var originalHit:Boolean = original.isColliding;
        var originalT:Number = original.tEntry;
        var originalX:Number = original.overlapCenter.x;
        var originalY:Number = original.overlapCenter.y;
        var decline:Boolean = BulletQueueProcessor.rejectRayCandidateY(BulletQueueProcessor.prepareRayYWindow(ray), target, z);
        var optimizedHit:Boolean = false;
        var optimizedT:Number, optimizedX:Number, optimizedY:Number;
        if (!decline) {
            var current:Object = ray.checkCollision(target, z);
            optimizedHit = current.isColliding;
            optimizedT = current.tEntry; optimizedX = current.overlapCenter.x; optimizedY = current.overlapCenter.y;
        } else {
            rejected++;
            check(!originalHit, "no false-negative: " + name);
        }
        if (originalHit) hits++;
        pairs++;
        check(originalHit === optimizedHit && (!originalHit || (originalT === optimizedT
            && originalX === optimizedX && originalY === optimizedY)), "exact original result: " + name);
    }
    private static function zeroReject(window:Object, target:Object, z:Number):Boolean { return false; }
    private static function reject(ray:Object, target:Object, z:Number):Boolean {
        return BulletQueueProcessor.rejectRayCandidateY(BulletQueueProcessor.prepareRayYWindow(ray),target,z);
    }
    private static function signature(items:Array, count:Number):String {
        var output:String = "";
        for (var i:Number = 0; i < count; i++) {
            var item:Object = items[i];
            output += item.target._name + ":" + item.tEntry + ":" + item.hitX + ":" + item.hitY + ";";
        }
        return output;
    }
    private static function scanOracle():Void {
        var world:MovieClip = _root.createEmptyMovieClip("rayScanOracleWorld", 78211);
        var xs:Array = [-80,-50,-50,-20,20,20,50,80];
        var units:Array = [], left:Array = [], right:Array = [];
        var maximum:Number = -100000;
        for (var i:Number = 0; i < xs.length; i++) {
            var target:MovieClip = world.createEmptyMovieClip("unit" + i, i);
            target.hp = i == 1 ? 0 : 100; target.防止无限飞 = i == 6;
            target.Z轴坐标 = (i % 3 - 1) * 15;
            target.aabbCollider = new AABBCollider(xs[i] - 8, xs[i] + 8, -12, 12);
            units.push(target); left.push(xs[i] - 8);
            maximum = Math.max(maximum, xs[i] + 8); right.push(maximum);
        }
        var BQP:Object = BulletQueueProcessor;
        var normal:Function = BQP.rejectRayCandidateY;
        var directions:Array = [[1,0],[-1,0],[3,4],[-3,-4],[0,0]];
        for (var d:Number = 0; d < directions.length; d++) for (var wide:Number = 0; wide < 2; wide++) {
            var ray:Object;
            if (wide) {
                var band:BandRayCollider = new BandRayCollider(new Vector(0,0),new Vector(directions[d][0],directions[d][1]),100);
                band.setHalfWidth(20); ray = band;
            } else ray = new RayCollider(new Vector(0,0),new Vector(directions[d][0],directions[d][1]),100);
            var ctx:Object = {areaAABB:ray,unitMap:units,unitLen:units.length,unitLeftKeys:left,unitRightMax:right,
                bulletZOffset:0,bulletZRange:50,bullet:{_flameHits:[]}};
            var visited:Object = {unit2:true};
            for (var minIndex:Number = 0; minIndex < 3; minIndex++) {
                var minT:Number = [-1,0,30][minIndex];
                BQP.rejectRayCandidateY = zeroReject;
                var before:Object = BQP.findAlongRay(ctx, visited, minT);
                BQP.rejectRayCandidateY = normal;
                var after:Object = BQP.findAlongRay(ctx, visited, minT);
                check((before == null && after == null) || (before != null && after != null
                    && before.target === after.target && before.tEntry === after.tEntry
                    && before.hitX === after.hitX && before.hitY === after.hitY),
                    "real findAlongRay preserves selection/ties/cursor " + d + ":" + wide + ":" + minT);
            }
            BQP.rejectRayCandidateY = zeroReject;
            var baseHits:Array = BQP["collectFlameHits"](ctx,3);
            var baseCount:Number = ctx.flameHitCount;
            var baseline:String = signature(baseHits,baseCount);
            BQP.rejectRayCandidateY = normal;
            var newHits:Array = BQP["collectFlameHits"](ctx,3);
            check(baseCount == ctx.flameHitCount && baseline == signature(newHits,ctx.flameHitCount),
                "real flame scan preserves top-N order and exact entry geometry " + d + ":" + wide);
        }
        BQP.rejectRayCandidateY = normal;
        world.removeMovieClip();
    }
    private static function fallbackOracle():Void {
        var ray:Object = new RayCollider(new Vector(0,0),new Vector(1,0),100);
        var target:Object = new AABBCollider(20,40,100,120);
        check(reject(ray,target,0), "known concrete C2/C3 miss takes the fast path");
        var fields:Array = ["left","right","top","bottom"];
        var bad:Array = [Number(undefined),1/0,-1/0,undefined,"100"];
        for (var side:Number = 0; side < 2; side++) for (var f:Number = 0; f < fields.length; f++) {
            var object:Object = side == 0 ? ray : target;
            var oldValue = object[fields[f]];
            for (var v:Number = 0; v < bad.length; v++) {
                object[fields[f]] = bad[v];
                if (side == 1 && f < 2) {
                    // X remains exclusively the original collider's responsibility; Y-only rejection stays equivalent.
                    pair(ray,target,0,0,"non-finite target X oracle " + fields[f] + ":" + v);
                } else check(!reject(ray,target,0),
                    "non-numeric/non-finite window or target Y falls back " + side + ":" + fields[f] + ":" + v);
            }
            object[fields[f]] = oldValue;
        }
        for (var n:Number = 0; n < bad.length; n++) {
            check(!reject(ray,target,bad[n]), "invalid Z uses original method " + n);
        }
        var clamped:BandRayCollider = new BandRayCollider(new Vector(0,0),new Vector(1,0),100);
        clamped.setHalfWidth(-1);
        check(BulletQueueProcessor.prepareRayYWindow(clamped).halfWidth === 0, "negative Band width uses its actual zero clamp");
        clamped.setHalfWidth(Number(undefined));
        check(BulletQueueProcessor.prepareRayYWindow(clamped).halfWidth === 0, "NaN Band width uses its actual zero clamp");
        clamped.setHalfWidth(0);
        var initialWindow:Object = BulletQueueProcessor.prepareRayYWindow(clamped);
        clamped.setHalfWidth(25);
        var changedWindow:Object = BulletQueueProcessor.prepareRayYWindow(clamped);
        check(initialWindow.halfWidth === 0 && changedWindow.halfWidth === 25,
            "each new scan reads actual changed Band width without global cached state");
        var changedWidth:Object = clamped;
        changedWidth.getHalfWidth = function():Number { RayScanGeometryTest.fallbackCalls++; return 25; };
        fallbackCalls = 0;
        check(BulletQueueProcessor.prepareRayYWindow(changedWidth) == null && fallbackCalls == 0,
            "unknown half-width getter falls back without invoking it");
        delete changedWidth.getHalfWidth;
        target.top = Number.MAX_VALUE; target.bottom = Number.MAX_VALUE;
        check(!reject(ray,target,Number.MAX_VALUE), "finite-input Z overflow falls back");
        target.top = -Number.MAX_VALUE; target.bottom = -Number.MAX_VALUE;
        clamped.setHalfWidth(Number.MAX_VALUE);
        check(!reject(clamped,target,0), "finite-input expansion overflow falls back");
        target.top = 100; target.bottom = 120;
        check(!reject({},target,0), "unknown source type is untouched");
        check(!reject(ray,{left:20,right:40,top:100,bottom:120},0),
            "plain object bounds do not prove target C2/C3");
        var point:PointCollider = new PointCollider(30,110);
        check(!reject(ray,point,0),
            "private-position Point target retains its original getAABB path");
        pair(ray,point,0,0,"Point conservative fallback");
        var proto:Object = {}; proto.__proto__ = AABBCollider.prototype;
        var oldProto:Object = target.__proto__; target.__proto__ = proto;
        check(!reject(ray,target,0), "unknown derived target prototype is not admitted");
        target.__proto__ = oldProto;
        var originalGet:Function = target.getAABB;
        target.getAABB = function(z:Number):AABB {
            RayScanGeometryTest.fallbackCalls++;
            return new AABB(20,40,-10+z,10+z);
        };
        fallbackCalls = 0;
        check(!reject(ray,target,0) && fallbackCalls == 0,
            "overridden getAABB falls back without calling or mutating it");
        pair(ray,target,0,0,"custom projection remains a hit despite misleading public bounds");
        check(fallbackCalls == 2, "custom fallback executes the real projection on both oracle sides");
        target.getAABB = originalGet;
        var sourceProto:Object = {}; sourceProto.__proto__ = RayCollider.prototype;
        oldProto = ray.__proto__; ray.__proto__ = sourceProto;
        check(!reject(ray,target,0), "unknown derived source prototype falls back");
        ray.__proto__ = oldProto;
        var band:BandRayCollider = new BandRayCollider(new Vector(0,0),new Vector(1,0),100);
        band.setHalfWidth(1/0);
        check(!reject(band,target,0), "actual infinite Band width falls back");
        pair(band,target,0,band.getHalfWidth(),"infinite Band uses the unchanged old collider");
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0; pairs = 0; rejected = 0; hits = 0;
        var started:Number = getTimer();
        var directions:Array = [[1,0],[-1,0],[0,1],[0,-1],[3,4],[-3,4],[3,-4],[-3,-4],
            [1,0.000000000001],[-1,0.000000000001],[0.000000000001,1],[0,0]];
        var bounds:Array = [[-10,10,-10,10],[20,40,-10,10],[-40,-20,-10,10],
            [20,40,0,10],[20,40,-10,0],[100,120,-10,10],[20,20,-10,10],
            [20,40,100,120],[20,40,-120,-100],[40,20,-10,10],[20,40,10,-10],
            [20,40,-0.000000000001,0.000000000001]];
        var zs:Array = [-70,-25,0,25,70];
        var widths:Array = [0,0,25,63]; // first is thin; second is real zero-width Band.
        for (var d:Number = 0; d < directions.length; d++) for (var w:Number = 0; w < widths.length; w++) {
            var ray:Object;
            if (w == 0) ray = new RayCollider(new Vector(0,0),new Vector(directions[d][0],directions[d][1]),100);
            else {
                var band:BandRayCollider = new BandRayCollider(new Vector(0,0),new Vector(directions[d][0],directions[d][1]),100);
                band.setHalfWidth(widths[w]); ray = band;
            }
            for (var b:Number = 0; b < bounds.length; b++) for (var z:Number = 0; z < zs.length; z++) {
                var box:Array = bounds[b];
                pair(ray,new AABBCollider(box[0],box[1],box[2],box[3]),zs[z],widths[w],"AABB "+d+":"+w+":"+b+":"+z);
                pair(ray,new CoverageAABBCollider(box[0],box[1],box[2],box[3]),zs[z],widths[w],"Coverage "+d+":"+w+":"+b+":"+z);
            }
        }
        var zero:RayCollider = new RayCollider(new Vector(20,10),new Vector(1,0),0);
        pair(zero,new AABBCollider(10,30,0,20),0,0,"zero length inside");
        pair(zero,new AABBCollider(30,40,30,40),0,0,"zero length outside");
        var moved:RayCollider = new RayCollider(new Vector(0,0),new Vector(1,0),100);
        moved.updateFromTransparentBullet({_x:40,_y:70});
        pair(moved,new AABBCollider(60,80,60,80),0,0,"updated origin");
        moved.setRayFast(0,0,Number(undefined),1,100);
        pair(moved,new AABBCollider(20,40,100,120),0,0,"invalid direction original safe miss");
        moved.setRayFast(0,0,1,0,100);
        pair(moved,new RayCollider(new Vector(20,-10),new Vector(1,1),30),0,0,"Ray target original projection");
        pair(moved,new BandRayCollider(new Vector(20,90),new Vector(1,1),30),0,0,"Band target original projection");
        fallbackOracle();
        scanOracle();
        check(rejected > 100 && hits > 100, "oracle exercised both rejection and real positive collisions");
        check(getTimer() - started < 25000, "focused geometry oracle stays bounded");
        trace("[RAY_SCAN_ORACLE] pairs=" + pairs + "|rejected=" + rejected + "|hits=" + hits
            + "|elapsedMs=" + (getTimer() - started) + "|oracle=unchanged-Ray-and-Band|comparison=exact");
        trace("RayScanGeometryTest Tests Passed: " + passed);
        trace("RayScanGeometryTest Tests Failed: " + failed);
    }
}