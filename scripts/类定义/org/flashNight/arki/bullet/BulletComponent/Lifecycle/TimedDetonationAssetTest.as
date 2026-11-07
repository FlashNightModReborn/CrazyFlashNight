import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Loader.InfoLoader;
import org.flashNight.arki.bullet.BulletComponent.Movement.MovementSystem;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.component.Collider.ColliderFactoryRegistry;
import org.flashNight.arki.component.Shield.AdaptiveShield;
import org.flashNight.arki.component.StatHandler.DodgeHandler;
import org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine;

/**
 * 真实 lady/原版弹库/JohnWick 爆炸库、XML InfoLoader、生产 shoot/factory/unit-init/queue 路径。
 * 三个独立素材域由夹具路由（游戏由共享库提供）；受控矩形目标和固定闪避。
 * 最后一个场景使用实际墙钟与原生 onEnterFrame，验证首次下落及转场取消。
 * 不读取或写入玩家存档，不代签完整关卡/手感验收。
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.TimedDetonationAssetTest {
    private static var passed:Number,failed:Number,ticks:Number,loaded:Number,phase:Number;
    private static var done:Boolean,xmlReady:Boolean,mapHit:Boolean;
    private static var world:MovieClip,stock:MovieClip,blasts:MovieClip,driver:MovieClip,shooter:MovieClip,target:MovieClip;
    private static var loader:MovieClipLoader,listener:Object,saved:Object,records:Array,spawned:Array,cache:Object;
    private static var coverageTargets:Array;
    private static var tag:String,live:Object,bornAt:Number,emittedAt:Number,observedFrames:Number,deathEvents:Number;

    private static function check(ok:Boolean,name:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] TimedDetonationAssetTest: "+name);}
    }
    private static function noop():Void {}
    private static function shallow(source:Object):Object {
        var result:Object={};for(var key:String in source)result[key]=source[key];return result;
    }
    private static function acquire(unit:Object,interval:Number):Object{return cache;}
    private static function hit():String{return "未躲闪";}
    private static function dodgeResult():Object{return {};}

    public static function runAllTests():Void {
        passed=failed=ticks=loaded=phase=0;done=xmlReady=mapHit=false;records=[];spawned=[];tag="load";
        var tc:Object=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
        var dodge:Object=org.flashNight.arki.component.StatHandler.DodgeHandler;
        saved={world:_root.gameworld,clock:_root.帧计时器,paused:_root.暂停,collision:_root.collisionLayer,
            gravity:_root.重力加速度,xmin:_root.Xmin,xmax:_root.Xmax,ymin:_root.Ymin,ymax:_root.Ymax,
            copy:_root.对象浅拷贝,sound:_root.播放音效,message:_root.发布消息,fx:_root.效果,
            depth:DepthManager.instance,shoot:_root.子弹区域shoot传递,acquire:tc.acquireEnemyCache,
            dodge:dodge.calculateDodgeState,dodgeResult:dodge.calcDodgeResult};
        _root.暂停=false;_root.重力加速度=0.5;
        _root.帧计时器={当前帧数:0,帧率:30,unitUpdateWheel:{add:function():Number{return 1;},remove:noop}};
        _root.Xmin=-10000;_root.Xmax=10000;_root.Ymin=-10000;_root.Ymax=10000;
        _root.对象浅拷贝=shallow;_root.播放音效=_root.发布消息=_root.效果=noop;
        _root.collisionLayer={hitTest:function(x:Number,y:Number):Boolean{return TimedDetonationAssetTest.mapHit;}};
        tc.acquireEnemyCache=acquire;dodge.calculateDodgeState=hit;dodge.calcDodgeResult=dodgeResult;
        ColliderFactoryRegistry.init();FactionManager.initialize();PinkNoiseEngine.getInstance();
        StaticInitializer.factory=new AABBColliderFactory(32);
        MovementSystem.initialize();
        InfoLoader.getInstance().onLoad(function(data:Object):Void {
            TimedDetonationAssetTest.xmlReady=data.attributeData["fm92刺弹炮弹"].timedDetonation.timeoutMs==1000;
        });
        cache={data:[],leftValues:[],rightValues:[],rightMaxValues:[]};
        world=_root.createEmptyMovieClip("__timedLady",_root.getNextHighestDepth());world._visible=false;
        stock=_root.createEmptyMovieClip("__timedStock",_root.getNextHighestDepth());stock._visible=false;
        blasts=_root.createEmptyMovieClip("__timedBlasts",_root.getNextHighestDepth());blasts._visible=false;
        driver=_root.createEmptyMovieClip("__timedDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {
            try{TimedDetonationAssetTest.tick();}
            catch(e){TimedDetonationAssetTest.check(false,"native tick exception "+e);TimedDetonationAssetTest.finish();}
        };
        listener={onLoadInit:function(mc:MovieClip):Void{mc.stop();TimedDetonationAssetTest.loaded++;},
            onLoadError:function(mc:MovieClip,code:String):Void{
                TimedDetonationAssetTest.check(false,"published library load "+code);TimedDetonationAssetTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/lady.swf",world),"request published lady library");
        check(loader.loadClip("../flashswf/arts/原版素材库-子弹.swf",stock),"request published ordinary grenade library");
        check(loader.loadClip("../flashswf/arts/new/PTXOA馆长_JohnWick系列.swf",blasts),"request actual ordinary-grenade explosion library");
    }
    private static function initializeWorld():Void {
        _root.gameworld=world;world.子弹区域=stock;world.dispatcher=new EventDispatcher();
        world.地图={僵尸型敌人总个数:0,僵尸型敌人场上实际人数:0};
        DepthManager.instance=new DepthManager(world,0,870655,128);
        DepthManager.instance.calibrate(-1000,1000);
        shooter=world.createEmptyMovieClip("timedShooter",900001);
        shooter.hp=1000;shooter.是否为敌人=false;shooter.命中率=10000;shooter.伤害加成=0;
        shooter.等级=35;shooter.方向="右";shooter.Z轴坐标=0;shooter.伤害类型="魔法";shooter.魔法伤害属性="热";
        shooter.毒=7;shooter.淬毒=19;shooter.dispatcher=new EventDispatcher();
        _root.子弹区域shoot传递=recordShot;
        BulletQueueProcessor.reset();BulletQueueProcessor.initialize();
    }
    private static function recordShot(props:Object):Object {
        var previous:Object=world.子弹区域;
        // 独立 TestLoader 没有游戏的共享库总锚点；仍通过原生产 shoot 与 factory 实例化。
        world.子弹区域=props.子弹种类=="高压爆炸"?world:
            (props.子弹种类=="火焰集束手雷爆炸"?blasts:stock);
        var result:Object=saved.shoot(props);
        world.子弹区域=previous;
        records.push({tag:tag,type:props.子弹种类,props:shallow(props),clip:result,time:getTimer()});
        if(result!=null)spawned.push(result);
        return result;
    }
    private static function fire(y:Number,speed:Number):MovieClip {
        return MovieClip(_root.子弹区域shoot传递({子弹种类:"fm92刺弹炮弹",发射者:shooter._name,
            shootX:0,shootY:y,shootZ:0,子弹威力:100,子弹速度:speed==undefined?17:speed,子弹散射度:0,霰弹值:1,
            Z轴攻击范围:40,击倒率:0,伤害类型:"魔法",魔法伤害属性:"热",命中率:10000,
            水平击退速度:0,垂直击退速度:0,角度偏移:0}));
    }
    private static function count(type:String):Number {
        var total:Number=0;for(var i:Number=0;i<records.length;i++)if(records[i].tag==tag && records[i].type==type)total++;
        return total;
    }
    private static function cleanup():Void {
        for(var i:Number=0;i<spawned.length;i++)if(spawned[i]._parent)spawned[i].removeMovieClip();
        spawned=[];if(target._parent){target.dispatcher.destroy();target.removeMovieClip();}target=null;
        cache={data:[],leftValues:[],rightValues:[],rightMaxValues:[]};mapHit=false;
        BulletQueueProcessor.reset();BulletQueueProcessor.initialize();
    }
    private static function step(projectile:MovieClip):Void {
        _root.帧计时器.当前帧数++;
        projectile.onEnterFrame();BulletQueueProcessor.processQueue();
    }
    private static function makeTarget():Void {
        target=world.createEmptyMovieClip("timedEnemy",900002);
        target.Z轴坐标=0;target.hp=target.hp满血值=100000;target.等级=35;target.防御力=0;
        target.是否为敌人=true;target.躲闪率=1;target.damageTakenMultiplier=1;target.魔法抗性={基础:0,热:0};
        target.shield=AdaptiveShield.createDormant("timed-fixture");target.dispatcher=new EventDispatcher();
        var area:MovieClip=target.createEmptyMovieClip("area",1);
        area.beginFill(0xff0000);area.moveTo(-25,-100);area.lineTo(25,-100);area.lineTo(25,-40);area.lineTo(-25,-40);area.endFill();
        target.aabbCollider=new AABBCollider(0,0,0,0);target.aabbCollider.updateFromUnitArea(target);
        var box:Object=target.aabbCollider;
        cache={data:[target],leftValues:[box.left],rightValues:[box.right],rightMaxValues:[box.right]};
    }
    private static function synchronousCases():Void {
        tag="timeout";var b:MovieClip=fire(-500);var state:Object=b.__timedDetonation;
        check(b._parent===world && b.unitBulletConfig.hitPoint==1,"real factory creates interceptable FM92 from XML");
        check(b.dispatcher!=null && b.__unitInitializedVersion!=null,"production StaticInitializer completed unit registration");
        check(state.profile.timeoutMs==1000 && state.profile.scatter.type=="普通手雷","InfoLoader to factory config chain is active");
        state.elapsedMs=999;state.lastMs=getTimer();
        check(!b.shouldDestroy(b) && count("普通手雷")==0,"real projectile remains armed before deadline");
        state.elapsedMs=1000;step(b);
        check(state.emitted && state.reason=="timeout","empty-target queue terminates timeout through disappearance");
        check(count("高压爆炸")==1 && count("普通手雷")==4,"timeout creates one parent blast and exactly four real grenades");
        trace("TimedDetonationNativeCase timeout explosions="+count("高压爆炸")+" children="+count("普通手雷"));
        var child:MovieClip=null;
        for(var i:Number=0;i<records.length;i++)if(records[i].tag==tag && records[i].type=="普通手雷"){
            child=records[i].clip;
            check(child._parent===stock && child.area!=null && child.__timedDetonation!=null,"actual ordinary grenade attaches and receives controller "+i);
            check(child.毒==state.snapshot.毒 && child.nanoToxic==state.snapshot.nanoToxic && child.lockShooterAttributes,"child preserves locked toxin snapshot "+i);
        }
        var before:Number=child._y-child.Z轴坐标;
        child.updateMovement(child);
        check(child._y-child.Z轴坐标>before,"actual ordinary grenade begins downwards");
        child.area.onEnterFrame=function():Void{this._parent._y-=99;};
        check(child.area.onEnterFrame==undefined,"native area rejects late upward-gravity handler");
        var childState:Object=child.__timedDetonation;child.gotoAndPlay("消失");
        check(childState.emitted && count("火焰集束手雷爆炸")==1,"native gotoAndPlay override prevents legacy second grenade explosion");
        check(records[records.length-1].clip._parent===blasts,"ordinary grenade blast is a real published effect instance");
        check(count("普通手雷")==4,"child explosion cannot recursively scatter");
        cleanup();

        tag="contact-early";makeTarget();b=fire(-75);state=b.__timedDetonation;state.elapsedMs=500;step(b);
        check(state.emitted && state.reason=="impact","enemy contact before 1s detonates immediately");
        check(count("高压爆炸")==1 && count("普通手雷")==0,"early enemy contact emits no grenades");cleanup();
        tag="contact";makeTarget();b=fire(-75);state=b.__timedDetonation;state.elapsedMs=1000;step(b);
        check(state.emitted && state.reason=="impact","real enemy contact wins at timeout boundary");
        check(target.hp<target.hp满血值 && isFinite(target.hp),"production damage settlement ran for enemy contact");
        check(count("高压爆炸")==1 && count("普通手雷")==0,"enemy contact never spawns grenades");
        trace("TimedDetonationNativeCase contact explosions="+count("高压爆炸")+" children="+count("普通手雷"));cleanup();

        tag="map";b=fire(-500);state=b.__timedDetonation;state.elapsedMs=1000;mapHit=true;step(b);
        check(state.emitted && state.reason=="impact" && count("普通手雷")==0,"map collision takes priority over timeout");
        check(count("高压爆炸")==1,"map collision creates exactly one blast");cleanup();
        tag="intercept";b=fire(-500);state=b.__timedDetonation;
        state.elapsedMs=1000;
        check(b.shouldDestroy(b) && state.timeoutRequested,"interception fixture reaches a pending timeout");
        deathEvents=0;
        b.dispatcher.subscribe("death",function(unit:MovieClip):Void{
            if(unit._killed) TimedDetonationAssetTest.deathEvents++;
        },b);
        UnitBulletLifecycle.onHit(b,shooter,null);
        check(state.emitted && state.reason=="impact" && count("高压爆炸")==1 && count("普通手雷")==0,"actual UnitBullet hit/kill path detonates once without scatter");cleanup();
        check(deathEvents==1,"interception publishes death exactly once before synchronous detonation removal");
        tag="left";shooter.方向="左";b=fire(-500);state=b.__timedDetonation;
        check(b.xmov<0,"left-facing FM92 preserves original flight direction");
        state.elapsedMs=1000;step(b);
        check(state.emitted && count("高压爆炸")==1 && count("普通手雷")==4,"left-facing timeout has the same four downward grenades");
        cleanup();shooter.方向="右";
        tag="long-flight";b=fire(-1200,60);state=b.__timedDetonation;b._x=1500;state.elapsedMs=500;
        check(!b.shouldDestroy(b),"armed timed projectile survives the legacy 900px range prune");
        state.elapsedMs=1000;step(b);
        check(state.emitted && state.reason=="timeout" && count("高压爆炸")==1 && count("普通手雷")==4,"distant high-speed projectile still expires into four grenades");
        trace("TimedDetonationNativeCase long-flight explosions="+count("高压爆炸")+" children="+count("普通手雷"));cleanup();
        tag="removed";b=fire(-500);state=b.__timedDetonation;b.removeMovieClip();
        check(state.cancelled && count("高压爆炸")==0 && count("普通手雷")==0,"safeRemove cancels without firing");cleanup();
        tag="unchanged";
        var plain:MovieClip=MovieClip(_root.子弹区域shoot传递({子弹种类:"普通手雷",发射者:shooter._name,shootX:0,shootY:-500,shootZ:0,
            子弹威力:100,子弹速度:0,子弹散射度:0,霰弹值:1,Z轴攻击范围:40,击倒率:0,角度偏移:0}));
        check(plain._parent===stock && plain.__timedDetonation==undefined,"unconfigured ordinary grenade retains original lifecycle");cleanup();
    }

    private static function makeCoverageTargets():Void {
        coverageTargets=[];
        var positions:Array=[];
        for(var x:Number=-320;x<=320;x+=80)positions.push({x:x,z:0});
        positions.push({x:-80,z:85},{x:80,z:-85},{x:600,z:0},{x:0,z:200});
        for(var i:Number=0;i<positions.length;i++) {
            var unit:MovieClip=world.createEmptyMovieClip("timedCoverage"+i,901000+i);
            unit._x=positions[i].x;unit._y=unit.Z轴坐标=positions[i].z;
            unit.hp=unit.hp满血值=100000;unit.等级=35;unit.防御力=0;unit.是否为敌人=true;
            unit.躲闪率=1;unit.damageTakenMultiplier=1;unit.魔法抗性={基础:0,热:0};
            unit.shield=AdaptiveShield.createDormant("timed-coverage-"+i);unit.dispatcher=new EventDispatcher();
            var area:MovieClip=unit.createEmptyMovieClip("area",1);
            area.beginFill(0xff0000);area.moveTo(-6,-100);area.lineTo(6,-100);
            area.lineTo(6,-40);area.lineTo(-6,-40);area.endFill();
            unit.aabbCollider=new AABBCollider(0,0,0,0);unit.aabbCollider.updateFromUnitArea(unit);
            coverageTargets.push(unit);
        }
        var ordered:Array=coverageTargets.concat();
        ordered.sort(function(a:Object,b:Object):Number{return a.aabbCollider.left-b.aabbCollider.left;});
        cache={data:ordered,leftValues:[],rightValues:[],rightMaxValues:[]};
        var rightMax:Number=-Infinity;
        for(i=0;i<ordered.length;i++) {
            var box:Object=ordered[i].aabbCollider;rightMax=Math.max(rightMax,box.right);
            cache.leftValues.push(box.left);cache.rightValues.push(box.right);cache.rightMaxValues.push(rightMax);
        }
    }
    private static function removeCoverageTargets():Void {
        for(var i:Number=0;i<coverageTargets.length;i++) {
            coverageTargets[i].dispatcher.destroy();coverageTargets[i].removeMovieClip();
        }
        coverageTargets=[];cleanup();
    }
    private static function coverageHits():Array {
        var result:Array=[];
        for(var i:Number=0;i<coverageTargets.length;i++)result.push(coverageTargets[i].hp<coverageTargets[i].hp满血值);
        return result;
    }
    private static function countHits(values:Array):Number {
        var result:Number=0;for(var i:Number=0;i<values.length;i++)if(values[i])result++;return result;
    }
    /** 采样真实时间轴 area，并经原生 precheck/queue 实际扣血，不以视觉尺寸代替命中。 */
    private static function exerciseBlastFrames():Object {
        var left:Number=Infinity,right:Number=-Infinity,zmin:Number=Infinity,zmax:Number=-Infinity,valid:Number=0;
        for(var i:Number=0;i<records.length;i++) {
            var record:Object=records[i];
            if(record.tag!=tag || (record.type!="高压爆炸" && record.type!="火焰集束手雷爆炸"))continue;
            var clip:MovieClip=record.clip;if(!clip._parent)continue;
            valid++;
            zmin=Math.min(zmin,clip.Z轴坐标-clip.Z轴攻击范围);zmax=Math.max(zmax,clip.Z轴坐标+clip.Z轴攻击范围);
            var callback:Function=clip.onEnterFrame;delete clip.onEnterFrame;
            var frameCount:Number=clip._totalframes;
            for(var f:Number=1;f<frameCount && clip._parent;f++) {
                clip.gotoAndStop(f);_root.帧计时器.当前帧数++;
                if(clip.area) {
                    var bounds:Object=clip.area.getRect(world);
                    left=Math.min(left,bounds.xMin);right=Math.max(right,bounds.xMax);
                }
                callback.call(clip);BulletQueueProcessor.processQueue();
            }
        }
        return {width:right-left,depth:zmax-zmin,valid:valid};
    }
    private static function coverageCases():Void {
        var oldGravity:Number=_root.重力加速度;_root.重力加速度=1;
        tag="coverage-direct";makeCoverageTargets();
        _root.子弹区域shoot传递({子弹种类:"高压爆炸",发射者:shooter._name,shootX:0,shootY:0,shootZ:0,
            子弹威力:70,子弹速度:0,子弹散射度:0,霰弹值:1,Z轴攻击范围:80,击倒率:0,角度偏移:0,
            伤害类型:"魔法",魔法伤害属性:"热",命中率:10000,水平击退速度:0,垂直击退速度:0});
        var direct:Object=exerciseBlastFrames();var directHits:Array=coverageHits();
        check(direct.valid==1 && direct.width>300 && direct.width<450,"real direct blast has measured area width");
        check(!directHits[0] && !directHits[8] && !directHits[9] && !directHits[10],"direct blast misses lateral and depth extension targets");
        check(directHits[4],"direct blast damages center control target");removeCoverageTargets();

        tag="coverage-scatter";
        var source:MovieClip=fire(-600);var state:Object=source.__timedDetonation;
        check(state.profile.scatter.landingSpread.radiusX==240 && state.profile.scatter.fallSpeed==20,"production XML enables spread footprint");
        state.elapsedMs=1000;source.shouldDestroy(source);source.gotoAndPlay("消失");
        var children:Array=[];
        for(var i:Number=0;i<records.length;i++)if(records[i].tag==tag && records[i].type=="普通手雷") {
            var child:MovieClip=records[i].clip;delete child.onEnterFrame;
            children.push({clip:child,state:child.__timedDetonation});
        }
        // 空中段无靶，隔离测量落地爆炸覆盖；敌人拦截与地图命中由前面的原队列回归覆盖。
        for(var f:Number=0;f<100;f++)for(i=0;i<children.length;i++) {
            if(!children[i].state.emitted)children[i].clip.updateMovement(children[i].clip);
        }
        var realChildren:Number=0;
        for(i=0;i<records.length;i++)if(records[i].tag==tag && records[i].type=="火焰集束手雷爆炸" && records[i].clip._parent===blasts)realChildren++;
        check(children.length==4 && realChildren==4,"four ordinary grenades land into four actual explosion clips");
        makeCoverageTargets();var scatter:Object=exerciseBlastFrames();var spreadHits:Array=coverageHits();
        var ratio:Number=scatter.width/direct.width;
        check(ratio>=1.5 && ratio<=2.1,"actual scatter explosion width is 1.5 to 2.1 times direct blast: "+ratio);
        check(scatter.depth>=direct.depth*1.2,"actual scatter depth coverage exceeds direct blast by at least 20 percent");
        check(spreadHits[0] && spreadHits[8],"actual queue damages both lateral targets outside direct blast");
        check(spreadHits[9] && spreadHits[10],"actual queue damages staggered depth targets outside direct blast");
        for(i=0;i<9;i++)check(spreadHits[i],"no missing damage across ground center line "+i);
        check(!spreadHits[11] && !spreadHits[12],"spread remains bounded beyond configured ground footprint");
        check(countHits(spreadHits)>countHits(directHits),"same target formation gains real additional hits");
        trace("TimedDetonationCoverage directWidth="+direct.width+" scatterWidth="+scatter.width+" ratio="+ratio
            +" directHits="+countHits(directHits)+" scatterHits="+countHits(spreadHits));
        removeCoverageTargets();_root.重力加速度=oldGravity;
    }
    private static function tick():Void {
        if(done)return;ticks++;_root.帧计时器.当前帧数++;
        if(phase==0){
            if(loaded==3 && xmlReady){
                check(xmlReady,"real bullets_cases.xml loaded via InfoLoader");initializeWorld();synchronousCases();coverageCases();
                tag="no-area";
                var b:MovieClip=fire(-500);
                live={clip:b,state:b.__timedDetonation,callback:b.onEnterFrame};
                delete b.onEnterFrame;
                // 时间轴静态子剪辑须先换到动态深度才能原生删除；下一帧才验证缺失。
                b.area.swapDepths(9000);b.area.removeMovieClip();phase=3;
            }else if(ticks>300){check(false,"asset/XML readiness watchdog");finish();}
            return;
        }
        if(phase==3){
            check(live.clip.area==undefined,"native timeline area was genuinely removed");
            live.state.elapsedMs=1000;live.callback.call(live.clip);
            check(live.state.emitted && count("高压爆炸")==1 && count("普通手雷")==4,"area-free precheck has finite timeout exit");cleanup();
            tag="live";bornAt=getTimer();emittedAt=-1;observedFrames=0;
            var automatic:MovieClip=fire(-1200);
            live={clip:automatic,name:automatic._name,state:automatic.__timedDetonation};phase=1;
            return;
        }
        if(phase==1){
            BulletQueueProcessor.processQueue();
            if(live.state.emitted && emittedAt<0){
                emittedAt=getTimer();
                var elapsed:Number=emittedAt-bornAt;
                check(elapsed>=990 && elapsed<1400,"real wall-clock timeout is 1s plus at most sampled-frame delay: "+elapsed);
                check(live.state.reason=="timeout" && count("高压爆炸")==1 && count("普通手雷")==4,"automatic native callbacks create exactly four children");
                trace("TimedDetonationNativeCase live elapsedMs="+elapsed+" explosions="+count("高压爆炸")+" children="+count("普通手雷"));
            }
            if(emittedAt>0 && ++observedFrames==4){
                check(world[live.name].__timedDetonation!==live.state,"original parent birth is absent after native unload boundary");
                for(var i:Number=0;i<records.length;i++)if(records[i].tag==tag && records[i].type=="普通手雷"){
                    var child:Object=records[i].clip;
                    check(child._parent!=null && child._y-child.Z轴坐标>records[i].props.shootY-records[i].props.shootZ,"native first frames move each grenade down "+i);
                    check(child.area.onEnterFrame==undefined,"late onClipEvent(load) cannot restore old gravity "+i);
                }
                var oldCount:Number=records.length;world.removeMovieClip();stock.removeMovieClip();blasts.removeMovieClip();
                live.recordCount=oldCount;phase=2;observedFrames=0;
            }
            if(getTimer()-bornAt>3000){check(false,"wall-clock detonation watchdog");finish();}
        }else if(phase==2 && ++observedFrames==3){
            check(records.length==live.recordCount,"scene unload cancels remaining children without late bursts");finish();
        }
    }
    private static function finish():Void {
        if(done)return;done=true;delete driver.onEnterFrame;
        cleanup();
        var tc:Object=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
        var dodge:Object=org.flashNight.arki.component.StatHandler.DodgeHandler;
        tc.acquireEnemyCache=saved.acquire;dodge.calculateDodgeState=saved.dodge;dodge.calcDodgeResult=saved.dodgeResult;
        _root.gameworld=saved.world;_root.帧计时器=saved.clock;_root.暂停=saved.paused;_root.collisionLayer=saved.collision;
        _root.重力加速度=saved.gravity;_root.Xmin=saved.xmin;_root.Xmax=saved.xmax;_root.Ymin=saved.ymin;_root.Ymax=saved.ymax;
        _root.对象浅拷贝=saved.copy;_root.播放音效=saved.sound;_root.发布消息=saved.message;_root.效果=saved.fx;
        _root.子弹区域shoot传递=saved.shoot;DepthManager.instance=saved.depth;
        if(world._parent)world.removeMovieClip();if(stock._parent)stock.removeMovieClip();if(blasts._parent)blasts.removeMovieClip();driver.removeMovieClip();
        trace("TimedDetonationAssetTest Tests Passed: "+passed);
        trace("TimedDetonationAssetTest Tests Failed: "+failed);
        _root.timedDetonationAssetComplete();
    }
}
