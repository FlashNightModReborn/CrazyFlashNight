import org.flashNight.arki.render.*;
import org.flashNight.arki.bullet.BulletComponent.Chain.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
/** Actual drawing and collider bounds. A consumer gate must preserve every row, not merely hit one target. */
class org.flashNight.arki.render.WorkerTrailGeometryTest {
    private static var saved:Object;
    private static var world:MovieClip;
    private static var baseline:Array;
    private static var passed:Number;
    private static var failed:Number;
    private static var counter:Number;
    private static var complete:String;
    private static function check(ok:Boolean,label:String):Void {if(ok)passed++;else{failed++;trace("[TEST_FAIL] WorkerTrailGeometryTest: "+label);}}
    private static function clip(type:String):MovieClip {
        var zone:MovieClip=world.子弹区域;return zone.createEmptyMovieClip("probeUnit"+(++counter),zone.getNextHighestDepth());
    }
    private static function release(unit:MovieClip):Void {unit.removeMovieClip();}
    private static function spread(span:Number):Number {return (counter%2==0?-0.5:0.5)*span;}
    private static function random():Number {return 0.5;}
    private static function box(parent:MovieClip):MovieClip {
        var area:MovieClip=parent.createEmptyMovieClip("area",1);
        // Timeline-authored graphics survive MovieClip.clear(). Keep the exported base rectangle
        // in a child so clear() only removes the production trail drawing, as it does in the XFL.
        var shape:MovieClip=area.createEmptyMovieClip("authoredRectangle",1);shape.beginFill(0xffffff);shape.moveTo(0,0);
        shape.lineTo(25,0);shape.lineTo(25,25);shape.lineTo(0,25);shape.lineTo(0,0);shape.endFill();
        area._x=-5;area._y=-5;area._xscale=area._yscale=40;return area;
    }
    public static function runAllTests():Void {
        passed=failed=counter=0;complete="FocusedTestRunId worker-trail-geometry Complete: "+_root.__workerTrailRunId;
        var manager:Object=ChainUnitManager;
        saved={world:_root.gameworld,timer:_root.帧计时器,pause:_root.暂停,random:_root.随机偏移,math:Math.random,
            acquire:manager.acquireUnit,release:manager.releaseUnit};
        world=_root.createEmptyMovieClip("__workerTrailGeometryWorld",_root.getNextHighestDepth());world.createEmptyMovieClip("子弹区域",1);
        _root.gameworld=world;_root.帧计时器={当前帧数:1};_root.暂停=false;_root.随机偏移=spread;
        manager.acquireUnit=clip;manager.releaseUnit=release;
        Math.random=random;saved.mathReadOnly=Math.random!==random;
        if(saved.mathReadOnly){_global.ASSetPropFlags(Math,"random",0,4);Math.random=random;}
        check(Math.random===random,"controlled true gameplay random hook installed");
        WorkerProjectionTestHost.install(false,function():Void {WorkerTrailGeometryTest.full();});
    }
    private static function transcript():Array {
        counter=0;var out:Array=[];
        for(var direction:Number=0;direction<2;direction++) {
            var zone:MovieClip=world.子弹区域;
            var b:MovieClip=zone.createEmptyMovieClip("trail",zone.getNextHighestDepth());
            b._x=direction==0?100:800;b._y=165;b.Z轴坐标=240;b._rotation=direction==0?0:180;
            b.xmov=direction==0?25:-25;b.ymov=0;b.霰弹值=4;b.子弹散射度=15;
            b.子弹种类="横向拖尾追踪联弹-普通无壳子弹";b.area=box(b);
            _root.联弹系统.横向拖尾联弹初始化(b.area);
            var g:ChainGroup=ChainUnitManager.findGroupByBullet(b);
            var a:AABBCollider=new AABBCollider(0,0,0,0);
            for(var tick:Number=0;tick<48;tick++) {
                _root.帧计时器.当前帧数++;
                var update:Function=g.update;update(g);b._x+=b.xmov;
                a.updateFromBullet(b,b.area);
                var r:Object=b.area.getRect(world);
                var row:Array=[a.left,a.right,a.top,a.bottom,r.xMin,r.xMax,r.yMin,r.yMax,b.area._width,b.area._height];
                for(var u:Number=0;u<g.单元体列表.length;u++)row.push(g.单元体列表[u].x,g.单元体列表[u].y,g.单元体列表[u].rot);
                out.push(row);
            }
            ChainUnitManager.removeGroupByBullet(b);b.removeMovieClip();
        }
        return out;
    }
    private static function full():Void {
        try {baseline=transcript();WorkerProjectionTestHost.restore();WorkerProjectionTestHost.install(true,function():Void {WorkerTrailGeometryTest.none();});}
        catch(error){check(false,"full fixture "+error);finish();}
    }
    private static function none():Void {
        try {
            var next:Array=transcript(),different:Number=0,first:Number=-1;
            for(var i:Number=0;i<baseline.length;i++) {
                var same:Boolean=baseline[i].length==next[i].length;
                for(var k:Number=0;same&&k<baseline[i].length;k++)if(baseline[i][k]!==next[i][k])same=false;
                if(!same){different++;if(first<0)first=i;}
            }
            trace("[WORKER_TRAIL_GEOMETRY] rows="+baseline.length+" differingRows="+different+" firstMismatch="+first);
            if(first>=0){trace("[WORKER_TRAIL_FULL] "+baseline[first].join(","));trace("[WORKER_TRAIL_NONE] "+next[first].join(","));}
            check(different==0,"full/none exact actual AABB, drawing bounds, transforms and unit coordinates");
        }catch(error){check(false,"none fixture "+error);}
        finish();
    }
    private static function finish():Void {
        WorkerProjectionTestHost.restore();ChainUnitManager.resetAll();var manager:Object=ChainUnitManager;
        manager.acquireUnit=saved.acquire;manager.releaseUnit=saved.release;Math.random=saved.math;
        if(saved.mathReadOnly)_global.ASSetPropFlags(Math,"random",4,0);
        _root.gameworld=saved.world;_root.帧计时器=saved.timer;_root.暂停=saved.pause;_root.随机偏移=saved.random;
        world.removeMovieClip();trace("WorkerTrailGeometryTest Tests Passed: "+passed);trace("WorkerTrailGeometryTest Tests Failed: "+failed);trace(complete);
    }
}
