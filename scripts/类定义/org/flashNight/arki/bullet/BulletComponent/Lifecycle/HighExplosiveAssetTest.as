import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.component.Collider.ColliderFactoryRegistry;
import org.flashNight.arki.component.Damage.DamageManagerFactory;
import org.flashNight.arki.component.Damage.DamageResult;
import org.flashNight.arki.component.Shield.AdaptiveShield;
import org.flashNight.arki.component.StatHandler.DodgeHandler;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine;

/** Native published high-explosive timeline + production factory/queue/damage.
 * Controlled rectangular targets, stationary actors and forced dodge outcomes.
 * No saves, acquisition, player input, AI, hit movement or gameplay acceptance.
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.HighExplosiveAssetTest {
    private static var passed:Number, failed:Number, ticks:Number, age:Number, index:Number;
    private static var finished:Boolean, loaded:Boolean;
    private static var library:MovieClip, world:MovieClip, driver:MovieClip, shooter:MovieClip;
    private static var projectile:MovieClip, loader:MovieClipLoader, listener:Object;
    private static var cases:Array, targets:Array, cache:Object, saved:Object, current:Object;

    private static function check(ok:Boolean, message:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] HighExplosiveAssetTest: " + message); }
    }
    private static function shallow(source:Object):Object {
        var result:Object={};
        for (var key:String in source) result[key]=source[key];
        return result;
    }
    private static function noOp():Void {}
    private static function acquire(unit:Object, interval:Number):Object { return cache; }
    private static function forcedDodge():String { return current.mode=="miss" ? "躲闪" : "未躲闪"; }
    private static function dodgeResult():Object { return {}; }

    public static function runAllTests():Void {
        passed=failed=ticks=0; index=-1; finished=loaded=false; targets=[];
        cases=[
            {id:"free-flight",count:0,distance:0,mode:"flight"},
            {id:"near-one",count:1,distance:100,mode:"hit"},
            {id:"mid-one",count:1,distance:260,mode:"hit"},
            {id:"far-one",count:1,distance:420,mode:"hit"},
            {id:"near-four",count:4,distance:100,mode:"hit"},
            {id:"mid-four",count:4,distance:260,mode:"hit"},
            {id:"near-dense-four",count:4,distance:100,spacing:0,mode:"hit"},
            {id:"near-packed-four",count:4,distance:100,spacing:15,mode:"hit"},
            {id:"map-four",count:4,distance:140,mode:"map"},
            {id:"resolved-miss",count:1,distance:100,mode:"miss"},
            {id:"invulnerable",count:1,distance:100,mode:"null"},
            {id:"heat-resistant",count:1,distance:100,mode:"heat"},
            {id:"base-resistant",count:1,distance:100,mode:"base"}
        ];
        var queue:Object=org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
        var targetCache:Object=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
        var dodge:Object=org.flashNight.arki.component.StatHandler.DodgeHandler;
        saved={world:_root.gameworld,clock:_root.帧计时器,paused:_root.暂停,collision:_root.collisionLayer,
            xmin:_root.Xmin,xmax:_root.Xmax,ymin:_root.Ymin,ymax:_root.Ymax,
            copy:_root.对象浅拷贝,sound:_root.播放音效,fx:_root.效果,message:_root.发布消息,
            queues:queue.activeQueues,fake:queue.fakeUnits,uids:queue.queueUIDs,
            probe:queue._raySettleProbe,acquire:targetCache.acquireEnemyCache,
            dodge:dodge.calculateDodgeState,dodgeResult:dodge.calcDodgeResult};
        _root.暂停=false; _root.帧计时器={当前帧数:0,帧率:30,毫秒每帧:1000/30};
        _root.Xmin=-1000;_root.Xmax=10000;_root.Ymin=-1000;_root.Ymax=1000;
        _root.对象浅拷贝=shallow;
        _root.播放音效=_root.效果=_root.发布消息=noOp;
        _root.collisionLayer={hitTest:function(x:Number,y:Number):Boolean {
            return HighExplosiveAssetTest.current.mode=="map" && x>=80;
        }};
        targetCache.acquireEnemyCache=acquire;
        dodge.calculateDodgeState=forcedDodge;dodge.calcDodgeResult=dodgeResult;
        FactionManager.initialize();BulletQueueProcessor.initialize();ColliderFactoryRegistry.init();
        DamageManagerFactory.init();PinkNoiseEngine.getInstance();
        queue._raySettleProbe=null;
        DamageResult.getIMPACT().triggerDisplay=noOp;
        world=_root.createEmptyMovieClip("__heWorld",_root.getNextHighestDepth());
        world._visible=false;_root.gameworld=world;
        library=world.createEmptyMovieClip("heLibrary",world.getNextHighestDepth());
        world.子弹区域=library;
        shooter=world.createEmptyMovieClip("heShooter",world.getNextHighestDepth());
        shooter.是否为敌人=false;shooter.命中率=10000;shooter.伤害加成=0;
        shooter.等级=33;shooter._x=0;shooter._y=0;shooter.Z轴坐标=0;
        shooter.方向="右";shooter.dispatcher=new EventDispatcher();
        driver=_root.createEmptyMovieClip("__heDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {
            try { HighExplosiveAssetTest.tick(); }
            catch (error:Object) {
                HighExplosiveAssetTest.check(false,"tick exception "+error);
                HighExplosiveAssetTest.finish();
            }
        };
        loader=new MovieClipLoader();listener={};
        listener.onLoadInit=function(mc:MovieClip):Void {
            mc.stop();HighExplosiveAssetTest.loaded=true;
            trace("HighExplosiveLibrary url="+mc._url);
            HighExplosiveAssetTest.startCase();
        };
        listener.onLoadError=function(mc:MovieClip,code:String):Void {
            HighExplosiveAssetTest.check(false,"load "+code);HighExplosiveAssetTest.finish();
        };
        loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/3XD的素材.swf",library),"published owner SWF requested");
    }

    private static function startCase():Void {
        if (projectile._parent) projectile.removeMovieClip();
        for(var k:Number=0;k<targets.length;k++) {
            targets[k].dispatcher.destroy();targets[k].removeMovieClip();
        }
        targets=[];index++;
        if(index>=cases.length) { finish();return; }
        current=cases[index];age=0;current.hits=0;current.damage=0;current.removedAt=-1;
        current.exploded=false;current.hitTargets={};
        for(var i:Number=0;i<current.count;i++) {
            var target:MovieClip=world.createEmptyMovieClip("heTarget"+i,world.getNextHighestDepth());
            target._x=current.distance+i*(current.spacing===undefined?30:current.spacing);target._y=target.Z轴坐标=0;
            target.hp=target.hp满血值=1000000;target.等级=33;target.防御力=100;
            target.是否为敌人=true;target.躲闪率=1;target.damageTakenMultiplier=1;
            target.魔法抗性={基础:current.mode=="base"?80:0,热:current.mode=="heat"?80:0};
            target.无敌=current.mode=="null";
            target.shield=AdaptiveShield.createDormant("he-fixture");
            target.dispatcher=new EventDispatcher();
            target.dispatcher.subscribe("hit",function(unit:MovieClip,source:MovieClip,b:Object,cr:Object,result:Object):Void {
                HighExplosiveAssetTest.recordHit(unit,b,result);
            },target);
            var area:MovieClip=target.createEmptyMovieClip("area",1);
            area.beginFill(0xff0000);area.moveTo(-10,-105);area.lineTo(10,-105);
            area.lineTo(10,-45);area.lineTo(-10,-45);area.lineTo(-10,-105);area.endFill();
            target.aabbCollider=new AABBCollider(0,0,0,0);
            target.aabbCollider.updateFromUnitArea(target);
            targets.push(target);
        }
        rebuildCache();
        var props:Object={子弹种类:"高爆子弹",发射者:shooter._name,shootX:0,shootY:-75,shootZ:0,
            子弹速度:40,子弹威力:100,子弹散射度:0,武器扩散倍率:0,霰弹值:1,
            Z轴攻击范围:40,击倒率:0,水平击退速度:10,垂直击退速度:0,
            击中后子弹的效果:"",伤害类型:"物理",命中率:10000,角度偏移:0};
        BulletFactory.prepareBulletData(props,shooter);
        projectile=BulletFactory.createBullet(props,shooter,0);
        check(projectile._parent===library,"actual export attached "+current.id);
        check(projectile.flags===0,"current high-explosive type flags are zero "+current.id);
        projectile.__hePrecheck=projectile.onEnterFrame;delete projectile.onEnterFrame;
        current.lastHp=1000000*current.count;
        trace("HighExplosiveCaseStart id="+current.id+" flags="+projectile.flags+" frame="+projectile._currentframe+" scatter="+projectile.霰弹值);
        sample("birth");
    }

    private static function rebuildCache():Void {
        var lefts:Array=[],rights:Array=[],maxs:Array=[];var maximum:Number=-Infinity;
        for(var i:Number=0;i<targets.length;i++) {
            targets[i].aabbCollider.updateFromUnitArea(targets[i]);
            var box:Object=targets[i].aabbCollider;
            lefts.push(box.left);rights.push(box.right);
            maximum=Math.max(maximum,box.right);maxs.push(maximum);
        }
        cache={data:targets,leftValues:lefts,rightValues:rights,rightMaxValues:maxs};
    }
    private static function recordHit(target:MovieClip,b:Object,result:Object):Void {
        current.hits++;current.hitTargets[target._name]=true;
        trace("HighExplosiveHit id="+current.id+" age="+age+" target="+target._name+
            " frame="+b._currentframe+" scatter="+b.霰弹值+" type="+b.伤害类型+
            " element="+b.魔法伤害属性+" power="+b.破坏力+" damage="+target.损伤值+
            " hp="+target.hp+" count="+b.hitCount+" exploded="+b.已爆炸+
            " segments="+result.actualScatterUsed+" horizontal="+b.水平击退速度+" nullResult="+(result===DamageResult.NULL));
    }
    private static function sample(phase:String):Void {
        if(!projectile._parent) return;
        var bounds:Object=projectile.area ? projectile.area.getBounds(projectile) : null;
        trace("HighExplosiveFrame id="+current.id+" age="+age+" phase="+phase+
            " frame="+projectile._currentframe+" x="+projectile._x+" scatter="+projectile.霰弹值+
            " type="+projectile.伤害类型+" element="+projectile.魔法伤害属性+
            " exploded="+projectile.已爆炸+" area="+(bounds ? bounds.xMin+","+bounds.xMax+","+bounds.yMin+","+bounds.yMax : "none"));
    }
    private static function tick():Void {
        if(finished)return;
        ticks++;_root.帧计时器.当前帧数=ticks;
        if(!loaded) {
            if(ticks>240) { check(false,"owner SWF load timeout");finish(); }
            return;
        }
        age++;
        if(age===1)check(typeof(projectile.命中前伤害参数函数)=="function","pre-hit transform installed by actual first timeline frame "+current.id);
        if(projectile._parent) {
            sample("before");
            projectile.__hePrecheck.call(projectile);
            BulletQueueProcessor.processQueue();
            if(projectile.已爆炸)current.exploded=true;
            sample("after");
        } else if(current.removedAt<0)current.removedAt=age;
        var hp:Number=0;
        for(var i:Number=0;i<targets.length;i++)hp+=targets[i].hp;
        current.damage=current.count*1000000-hp;
        if(age>=32) {
            var unique:Number=0;for(var key:String in current.hitTargets)unique++;
            check(isFinite(current.damage)&&current.damage>=0,"finite settled HP "+current.id);
            if(current.mode=="hit" || current.mode=="heat" || current.mode=="base")check(current.damage>0,"production damage path exercised "+current.id);
            if(current.mode=="miss" || current.mode=="null")check(current.damage===0,"rejected contact is zero damage "+current.id);
            trace("HighExplosiveMeasure id="+current.id+" hits="+current.hits+" unique="+unique+
                " damage="+current.damage+" removedAt="+current.removedAt+" exploded="+current.exploded);
            startCase();
        }
    }
    private static function finish():Void {
        if(finished)return;finished=true;
        if(projectile._parent)projectile.removeMovieClip();
        delete driver.onEnterFrame;
        var queue:Object=org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
        var targetCache:Object=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
        var dodge:Object=org.flashNight.arki.component.StatHandler.DodgeHandler;
        queue.activeQueues=saved.queues;queue.fakeUnits=saved.fake;queue.queueUIDs=saved.uids;queue._raySettleProbe=saved.probe;
        targetCache.acquireEnemyCache=saved.acquire;dodge.calculateDodgeState=saved.dodge;dodge.calcDodgeResult=saved.dodgeResult;
        _root.gameworld=saved.world;_root.帧计时器=saved.clock;_root.暂停=saved.paused;_root.collisionLayer=saved.collision;
        _root.Xmin=saved.xmin;_root.Xmax=saved.xmax;_root.Ymin=saved.ymin;_root.Ymax=saved.ymax;
        _root.对象浅拷贝=saved.copy;_root.播放音效=saved.sound;_root.效果=saved.fx;_root.发布消息=saved.message;
        if(world._parent)world.removeMovieClip();
        trace("HighExplosiveAssetTest result: passed="+passed+" failed="+failed+" cases="+cases.length);
        _root.highExplosiveAssetComplete();
    }
}
