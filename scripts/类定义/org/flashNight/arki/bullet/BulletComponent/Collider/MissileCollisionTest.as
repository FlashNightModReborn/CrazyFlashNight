import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.Util.*;
import org.flashNight.arki.bullet.BulletComponent.Chain.*;

/** 真实 MovieClip 的转向/镜像边界与导弹寻的回归；不加载游戏或玩家存档。 */
class org.flashNight.arki.bullet.BulletComponent.Collider.MissileCollisionTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++; else { failed++; trace("[FAIL] " + label); }
    }
    private static function box(parent:MovieClip, name:String, x:Number, y:Number, w:Number, h:Number):MovieClip {
        var mc:MovieClip=parent.createEmptyMovieClip(name,parent.getNextHighestDepth());
        mc.beginFill(0xffffff);mc.moveTo(x,y);mc.lineTo(x+w,y);mc.lineTo(x+w,y+h);
        mc.lineTo(x,y+h);mc.lineTo(x,y);mc.endFill();return mc;
    }
    private static function matches(c:AABBCollider, area:MovieClip, world:MovieClip):Boolean {
        var r:Object=area.getRect(world);
        return Math.abs(c.left-r.xMin)<0.11 && Math.abs(c.right-r.xMax)<0.11
            && Math.abs(c.top-r.yMin)<0.11 && Math.abs(c.bottom-r.yMax)<0.11;
    }
    private static function track(world:MovieClip, angle:Number, depth:Number):Boolean {
        var shooter:MovieClip=world.createEmptyMovieClip("shooter",world.getNextHighestDepth());
        var enemy:MovieClip=world.createEmptyMovieClip("enemy",world.getNextHighestDepth());
        shooter.hp=100;shooter.攻击目标="enemy";
        enemy.hp=100;enemy._x=450;enemy._y=depth;enemy.Z轴坐标=depth;enemy.中心高度=75;
        enemy.area=box(enemy,"area",-20,-135,40,130);
        var b:MovieClip=world.createEmptyMovieClip("missile",world.getNextHighestDepth());
        b._x=angle==0?100:800;b._y=165;b.Z轴坐标=240;b._rotation=angle;
        b.area=box(b,"area",-5,-5,10,10);
        var params:Object=DefaultMissileCallbacks.build(shooter,25,angle);
        params.usePreLaunch=false;
        var m:MissileMovement=MissileMovement.create(params);
        var a:AABBCollider=new AABBCollider(0,0,0,0);
        var other:AABBCollider=new AABBCollider(0,0,0,0);other.updateFromUnitArea(enemy);
        var hit:Boolean=false;
        for(var f:Number=0;f<145;f++) {
            m.updateMovement(b);a.updateFromBullet(b,b.area);
            var z:Number=b.Z轴坐标-enemy.Z轴坐标;
            if(z<50 && z>-50 && a.checkCollision(other,z).isColliding) {hit=true;break;}
        }
        b.removeMovieClip();enemy.removeMovieClip();shooter.removeMovieClip();return hit;
    }
    private static var fixtureUnits:Number = 0;
    private static function acquireTrailUnit(type:String):MovieClip {
        var zone:MovieClip = _root.gameworld.子弹区域;
        return zone.createEmptyMovieClip("trailUnit" + (++fixtureUnits), zone.getNextHighestDepth());
    }
    private static function releaseTrailUnit(unit:MovieClip):Void { unit.removeMovieClip(); }
    private static function trailSpread(span:Number):Number {
        return (fixtureUnits % 2 == 0 ? -0.5 : 0.5) * span;
    }
    /** Production trail initializer/tick, real MC transforms, broad+narrow collision and Z gate. */
    private static function trackTrail(world:MovieClip, angle:Number, depth:Number):Void {
        var label:String = "trail angle=" + angle + " depth=" + depth;
        var shooter:MovieClip=world.createEmptyMovieClip("shooter",world.getNextHighestDepth());
        var enemy:MovieClip=world.createEmptyMovieClip("enemy",world.getNextHighestDepth());
        shooter.hp=100;shooter.攻击目标="enemy";
        enemy.hp=100;enemy._x=450;enemy._y=depth;enemy.Z轴坐标=depth;enemy.中心高度=75;
        enemy.area=box(enemy,"area",-20,-135,40,130);
        var zone:MovieClip=world.子弹区域;
        var b:MovieClip=zone.createEmptyMovieClip("trailMissile",zone.getNextHighestDepth());
        b._x=angle==0?100:800;b._y=165;b.Z轴坐标=240;b._rotation=angle;
        b.xmov=angle==0?25:-25;b.ymov=0;b.霰弹值=4;b.子弹散射度=15;
        b.子弹种类="横向拖尾追踪联弹-普通无壳子弹";
        // Exact exported 联弹area shape and instance transform: 25x25 * 0.4, translated -5,-5.
        b.area=box(b,"area",0,0,25,25);
        b.area._x=-5;b.area._y=-5;b.area._xscale=40;b.area._yscale=40;
        _root.联弹系统.横向拖尾联弹初始化(b.area);
        var group:ChainGroup=ChainUnitManager.findGroupByBullet(b);
        check(group != null && group.单元体列表.length==4,label+" initializes four real-MC trail units");
        var params:Object=DefaultMissileCallbacks.build(shooter,25,angle);
        params.usePreLaunch=false;
        var m:MissileMovement=MissileMovement.create(params);
        check(m.vx*m.vx+m.vy*m.vy>0 && (angle==0?m.vx>0:m.vx<0),label+" create preserves launch velocity");
        var a:AABBCollider=new AABBCollider(0,0,0,0);
        var poly:PolygonCollider=new PolygonCollider();
        var other:AABBCollider=new AABBCollider(0,0,0,0);other.updateFromUnitArea(enemy);
        var hit:Boolean=false;
        var closest:Number=Infinity;
        for(var f:Number=0;f<145;f++) {
            _root.帧计时器.当前帧数++;
            ChainUnitManager.tick();
            m.updateMovement(b);
            a.updateFromBullet(b,b.area);
            var z:Number=b.Z轴坐标-enemy.Z轴坐标;
            var dx:Number=b._x-enemy._x;
            var dy:Number=b._y-(enemy._y-75);
            var distance:Number=Math.sqrt(dx*dx+dy*dy);
            if(distance<closest) closest=distance;
            if(z<50 && z>-50 && a.checkCollision(other,z).isColliding) {
                var rot:Number=b._rotation;
                if(rot==0 || rot==180) {hit=true;break;}
                poly.updateFromBullet(b,b.area);
                if(poly.checkCollision(other,z).isColliding) {hit=true;break;}
            }
        }
        if(!hit) trace("[TRAIL_MISS] "+label+" closest="+closest+" x="+b._x+" y="+b._y+" z="+b.Z轴坐标+" rotation="+b._rotation);
        check(hit,label+" hits through real AABB/Polygon and depth gate");
        ChainUnitManager.removeGroupByBullet(b);
        b.removeMovieClip();enemy.removeMovieClip();shooter.removeMovieClip();
    }
    private static var searchFixture:Array;
    private static var searchCalls:Number;
    private static function cachedEnemies(shooter:MovieClip, interval:Number):Array {
        searchCalls++;
        return searchFixture;
    }
    private static function searchMovement(shooter:MovieClip, angle:Number):MissileMovement {
        var params:Object=DefaultMissileCallbacks.build(shooter,25,angle);
        params.usePreLaunch=false;
        return MissileMovement.create(params);
    }
    /** Real production callbacks and FSM actions, without the designated-target fast path. */
    private static function defaultSearch(world:MovieClip):Void {
        var shooter:MovieClip=world.createEmptyMovieClip("searchShooter",world.getNextHighestDepth());
        shooter.hp=100;shooter.攻击目标="无";
        var b:MovieClip=world.createEmptyMovieClip("searchMissile",world.getNextHighestDepth());
        b._x=100;b._y=165;b.Z轴坐标=240;b._rotation=0;
        searchFixture=[];searchCalls=0;
        for(var i:Number=0;i<9;i++) {
            var enemy:MovieClip=world.createEmptyMovieClip("searchEnemy"+i,world.getNextHighestDepth());
            enemy.hp=100;enemy.flags=0;enemy._x=i==8?150:450+i;
            enemy._y=240;enemy.Z轴坐标=240;enemy.中心高度=75;
            searchFixture.push(enemy);
        }
        _root.帧计时器.获取敌人缓存=cachedEnemies;
        var m:MissileMovement=searchMovement(shooter,0);
        m.updateMovement(b);
        check(!m.hasTarget,"default search leaves unfinished first eight-candidate batch pending");
        m.updateMovement(b);
        check(m.hasTarget && m.target==searchFixture[8],"default search completes nine candidates and picks nearest from second batch");
        check(searchCalls==2,"default search consumes exactly two bounded cache reads for nine candidates");
        var saved:Array=searchFixture;
        searchFixture=[];searchCalls=0;
        b._x=100;b._y=165;b.Z轴坐标=240;b._rotation=0;
        m=searchMovement(shooter,0);
        for(i=0;i<24;i++) m.updateMovement(b);
        check(!m.hasTarget && searchCalls>=2 && searchCalls<=4,"empty cache retries at bounded frequency without locking a target");
        check(b._x>100 && b._rotation==0,"no-target right-facing missile continues normal flight");
        searchFixture=[saved[0]];
        for(i=0;i<12 && !m.hasTarget;i++) m.updateMovement(b);
        check(m.hasTarget && m.target==saved[0],"empty cache later populated can acquire a target");
        shooter.攻击目标="searchEnemy8";searchCalls=0;
        b._x=100;b._y=165;b.Z轴坐标=240;b._rotation=0;
        m=searchMovement(shooter,0);m.updateMovement(b);
        check(m.hasTarget && m.target==saved[8] && searchCalls==0,"designated target retains priority without scanning cache");
        saved[8].hp=0;
        for(i=0;i<12 && m.target!=saved[0];i++) m.updateMovement(b);
        check(m.hasTarget && m.target==saved[0],"invalid designated target returns to default search");
        shooter.攻击目标="无";searchFixture=[];searchCalls=0;
        b._x=800;b._y=165;b.Z轴坐标=240;b._rotation=180;
        m=searchMovement(shooter,180);
        for(i=0;i<150;i++) m.updateMovement(b);
        check(b._x<800 && Math.abs(Math.abs(b._rotation)-180)<0.001,"no-target left-facing missile keeps launch direction");
        check(m.frame==150 && b.shouldDestroy(b)===true,"default search retries preserve finite 150-frame lifetime");
        b.removeMovieClip();shooter.removeMovieClip();
        for(i=0;i<saved.length;i++) saved[i].removeMovieClip();
        searchFixture=null;
    }
    public static function runAllTests():Void {
        passed=0;failed=0;
        var oldWorld:MovieClip=_root.gameworld;
        var world:MovieClip=_root.createEmptyMovieClip("missileCollisionFixture",_root.getNextHighestDepth());
        var oldTimer:Object=_root.帧计时器;
        var oldRandom:Function=_root.随机偏移;
        var oldPaused:Object=_root.暂停;
        var manager:Object=ChainUnitManager;
        var oldAcquire:Function=manager.acquireUnit;
        var oldRelease:Function=manager.releaseUnit;
        world.createEmptyMovieClip("子弹区域",1);
        _root.gameworld=world;
        _root.帧计时器={当前帧数:1};_root.暂停=false;
        _root.随机偏移=trailSpread;
        manager.acquireUnit=acquireTrailUnit;manager.releaseUnit=releaseTrailUnit;
        try {
            var b:MovieClip=world.createEmptyMovieClip("turning",world.getNextHighestDepth());
            b._x=100;b._y=100;b.area=box(b,"area",0,-4,45,8);
            var a:AABBCollider=new AABBCollider(0,0,0,0);
            a.updateFromBullet(b,b.area);
            check(matches(a,b.area,world),"birth bounds");
            b._rotation=90;a.updateFromBullet(b,b.area);
            check(matches(a,b.area,world),"turn with unchanged local area rebuilds world bounds");
            var enemy:AABBCollider=new AABBCollider(98,102,128,132);
            check(a.checkCollision(enemy,0).isColliding,"turn reaches target outside the original horizontal box");
            b._rotation=35;b._x+=90;b._y-=25;a.updateFromBullet(b,b.area);
            check(matches(a,b.area,world),"turn and translation together");
            b._xscale=-150;b._yscale=80;a.updateFromBullet(b,b.area);
            check(matches(a,b.area,world),"mirror and scale update bounds");
            b._x+=37;b._y+=14;a.updateFromBullet(b,b.area);
            check(matches(a,b.area,world),"stable transform keeps translation correct");
            b.removeMovieClip();
            check(track(world,0,240),"right-facing missile hits target");
            check(track(world,180,240),"left-facing missile hits target");
            check(track(world,0,320),"missile follows target at another depth");
            check(track(world,180,160),"left missile follows target at another depth");
            trackTrail(world,0,240);
            trackTrail(world,180,240);
            trackTrail(world,0,320);
            trackTrail(world,180,160);
            defaultSearch(world);
        } finally {
            ChainUnitManager.resetAll();
            manager.acquireUnit=oldAcquire;manager.releaseUnit=oldRelease;
            _root.随机偏移=oldRandom;_root.帧计时器=oldTimer;_root.暂停=oldPaused;
            world.removeMovieClip();_root.gameworld=oldWorld;
        }
        trace("MissileCollisionTest Tests Passed: "+passed);
        trace("MissileCollisionTest Tests Failed: "+failed);
    }
}
