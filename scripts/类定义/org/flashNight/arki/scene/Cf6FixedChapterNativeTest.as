import org.flashNight.arki.scene.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.DeathEventComponent;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory;
import org.flashNight.arki.component.Collider.ColliderFactoryRegistry;
import org.flashNight.arki.collision.CollisionLayerRenderer;
import org.flashNight.arki.spatial.move.Mover;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.xml.LoadXml.EnemyPropertiesLoader;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.Server.SaveManager;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/** Actual chapter JSON, actor initializer, collision renderer and spawn consumers.
 * Wave times and boss HP are controlled; this is not a complete player journey. */
class org.flashNight.arki.scene.Cf6FixedChapterNativeTest {
    private static var passed:Number,failed:Number,frame:Number,age:Number,phase:Number,index:Number;
    private static var maps:Array,book:Object,map:Object,config:Object,seen:Object,pending:Array,expected:Object;
    private static var world:MovieClip,driver:MovieClip,hero:MovieClip,boss:MovieClip,lootActor:MovieClip;
    private static var wave:WaveSpawner,info:StageInfo,propsReady:Boolean,finished:Boolean,phaseDeath:Boolean;
    private static var total:Number,bossTotal:Number,lastSupport:Number,bossExpected:Number;
    private static var samples:Array,lastFrameTime:Number,warningPeak:Number,slot:String;
    private static var nativeInitializer:Function,nativeAttach:Function,lifeTasks:Array,deathDone:Boolean;
    private static var geometry:Object,perfActors:Number,chapterCollision:MovieClip;
    // Test-only instrumentation on the real ten active actors, removed with the room.
    private static var perfActorMs:Number,perfTicks:Number,perfRays:Number,perfPoints:Number;
    private static var perfTotalMs:Number,perfWindows:Array,oldRay:Function,oldPoint:Function;
    private static function check(ok:Boolean,label:String):Void {if(ok)passed++;else{failed++;trace("[FAIL] Cf6FixedChapterNativeTest "+label);}}
    public static function runAllTests():Void {
        passed=failed=frame=age=phase=index=total=bossTotal=warningPeak=0;finished=propsReady=deathDone=false;
        seen={};maps=Cf6FixedChapterFixture.mapIds();samples=[];lifeTasks=[];
        trace("[CF6_CHAPTER_BEGIN] actual chapter and native spawn consumers");
        Cf6FixedSoldierNativeTest.prepareWorld(prepared);
    }
    private static function prepared(library:MovieClip):Void {
        world=library;check(Cf6FixedSoldierNativeTest.preparationFailures()==0,"real catalogs and equipment lifecycle prepared");
        _root.cf6InstallChapterRuntime();_root.cf6InstallChapterHelpers();
        nativeAttach=_root.加载游戏世界人物;
        _root.加载游戏世界人物=function(id:String,name:String,depth:Number,init:Object):MovieClip {
            var u:MovieClip=Cf6FixedChapterNativeTest.nativeAttach(id,name,depth,init);
            if(u!=null && typeof u.cf6UnitIdentity=="string")u.__chapterBirthCoordinates={x:u._x,z:u._y};
            return u;
        };
        _root.最大等级=60;_root.等级=7;_root.难度等级=1;_root.duplicateOf=ObjectUtil.clone;_root.配置数据为数组=ObjectUtil.toArray;
        _root.常用工具函数={线性插值:function(x:Number,a:Number,b:Number,c:Number,d:Number):Number {return c+(x-a)*(d-c)/(b-a);}};
        _root.身高百分比转换=org.flashNight.arki.unit.UnitUtil.getHeightPercentage;
        _root.经验值计算=function():Void {};_root.主角是否升级=function():Void {};_root.add2map=function():Void {};
        _root.pickupItemManager={createCollectible:function():Void {}};
        _root.帧计时器.taskManager={addLifecycleTask:function(u:Object,label:String,fn:Function,delay:Number,args:Array):Number {
            lifeTasks.push({unit:u,version:u.version,fn:fn,args:args});return lifeTasks.length;
        }};
        ColliderFactoryRegistry.init();StaticInitializer.factory=new AABBColliderFactory(64);FactionManager.initialize();
        nativeInitializer=_root.初始化敌人模板;
        _root.初始化敌人模板=function():Void {
            this.装载生命周期函数=_root.主角函数.装载生命周期函数;
            this.完成生命周期函数装载=_root.主角函数.完成生命周期函数装载;
            Cf6FixedChapterNativeTest.nativeInitializer.call(this);
        };
        _root.兵种库=Cf6FixedChapterFixture.unitAttributes();
        setupSave();BookDefinition.load("cf6-sting","type61");
        EnemyPropertiesLoader.getInstance().loadEnemyProperties(function(data:Object):Void {
            _root.敌人属性表=data;propsReady=true;
        },function():Void {check(false,"real EnemyPropertiesLoader");finish();});
        driver=_root.createEmptyMovieClip("__cf6ChapterDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {try{Cf6FixedChapterNativeTest.tick();}catch(error){check(false,"phase="+phase+" exception="+error);finish();}};
    }
    private static function setupSave():Void {
        slot="cf7_env_cf6_chapter_"+_root.cf6ChapterRunId;_root.savePath=slot;
        _root.当前关卡名="书中历险-毒刺行动";_root.允许存档=true;_root.角色名="FixedChapterFixture";
        _root.性别="男";_root.身高=175;_root.基础身价值=_root.身价=1000;
        _root.金钱=_root.虚拟币=_root.经验值=_root.技能点数=0;_root.玩家称号="";_root.difficultyMode=0;_root.easterEgg=false;
        _root.脸型="";_root.发型="";_root.键值设定=[];_root.佣兵是否出战信息=[];
        _root.同伴数据=[];_root.同伴数=0;_root.主角技能表=[[]];_root.主角被动技能={};_root.主线任务进度=0;
        _root.商城已购买物品=[];_root.商城购物车=[];_root.存档系统={dirtyMark:false};
        _root.全局健身HP加成=_root.全局健身MP加成=_root.全局健身空攻加成=_root.全局健身防御加成=_root.全局健身内力加成=0;
        _root.基建系统={infrastructure:{}};_root.宠物信息=[[],[],[],[],[]];_root.宠物领养限制=5;
        _root.UpdateTaskProgress=function():Void {};_root.更新主角被动技能=function():Void {};
        _root.根据等级得升级所需经验=function(level:Number):Number {return 0;};
        _root.UI系统={};_root.tasks_to_do=[];_root.tasks_finished={};_root.task_chains_progress={};_root.等级限制=100;
        _root.物品栏={};var names:Array=["背包","装备栏","药剂栏","仓库","战备箱"];
        for(var n:Number=0;n<names.length;n++)_root.物品栏[names[n]]=new ArrayInventory(null,50);
        _root.收集品栏={材料:new DictCollection(null),情报:new InformationCollection(null)};
        _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"type61",slot:slot,seed:761,startedAt:93,planSeed:93,outcome:"active"}};
        // Native actor/death/transaction integration; physical restart persistence
        // is independently verified by the twelve-process cold probe.
        SaveManager.getInstance()._configureSaveFlowForTest({flushResult:true,saveInFlight:false});
        RewardInboxService.resetForTests();
    }
    private static function beginMap():Void {
        if(index>=maps.length){finish();return;}
        Cf6BossEncounter.cancel();if(world!=null)world.removeMovieClip();lifeTasks=[];pending=[];expected={};
        for(var i:Number=0;i<book.maps.length;i++)if(book.maps[i].id==maps[index])map=book.maps[i];
        world=_root.createEmptyMovieClip("cf6ChapterWorld"+index,_root.getNextHighestDepth());_root.gameworld=world;
        world.__stageReturnWorldIdentity={};world.dispatcher=new EventDispatcher();
        world.createEmptyMovieClip("地图",world.getNextHighestDepth());world.地图.僵尸型敌人总个数=0;world.地图.僵尸型敌人场上实际人数=0;
        world.子弹区域=world;world.createEmptyMovieClip("效果",world.getNextHighestDepth());
        world.createEmptyMovieClip("deadbody",world.getNextHighestDepth()).layers=[null,null,{}];
        var env:Object=Cf6FixedChapterFixture.environment(map.id);
        _root.Xmin=env.Xmin;_root.Xmax=env.Xmax;_root.Ymin=env.Ymin;_root.Ymax=env.Ymax;
        DepthManager.instance=new DepthManager(world);DepthManager.instance.calibrate(env.Ymin,env.Ymax);
        if(chapterCollision!=null)chapterCollision.removeMovieClip();
        chapterCollision=_root.createEmptyMovieClip("chapterCollision",_root.getNextHighestDepth());
        _root.collisionLayer=chapterCollision;
        CollisionLayerRenderer.drawBoundary(_root.collisionLayer,env.Xmin,env.Xmax,env.Ymin,env.Ymax,300,false);
        CollisionLayerRenderer.drawPolygons(_root.collisionLayer,env.Collision);Mover.init();
        hero=world.createEmptyMovieClip("chapterHero",world.getNextHighestDepth());hero.hp=10000000;hero.version=1;
        hero._x=600;hero._y=hero.Z轴坐标=(env.Ymin+env.Ymax)/2;hero.是否为敌人=false;
        hero.createEmptyMovieClip("area",1);hero.area.beginFill(1);hero.area.moveTo(-8,-100);hero.area.lineTo(8,-100);hero.area.lineTo(8,0);hero.area.lineTo(-8,0);hero.area.endFill();
        _root.控制目标="chapterHero";_root.暂停=false;_root.场景转换中=false;
        var api:Object=StageManager;api.instance={currentStage:index,isActive:true,isFailed:false,isFinished:false,isCleared:false,
            environment:env,spawnPoints:[],currentBookMapId:function():String{return map.id;},clearStage:function():Void {}};
        api=SceneManager;api.instance={gameworld:world};
        info=new StageInfo(ObjectUtil.clone(map.stage));
        for(i=0;i<info.spawnPointInfo.length;i++){
            var sp:MovieClip=world.createEmptyMovieClip("chapterSpawn"+i,world.getNextHighestDepth());
            sp.僵尸型敌人场上实际人数=0;sp.僵尸型敌人总个数=0;sp.QuantityMax=0;
            StageManager.instance.spawnPoints.push(sp);
        }
        wave=WaveSpawner.getInstance();wave.prepareScene(info);var dynamicWave:Object=wave;dynamicWave.waveInfo=info.waveInfo;
        // Lazy fixed-world binding is exercised by actual actor birth, before chapter presentation.
        for(var w:Number=0;w<info.waveInfo.length;w++)for(var e:Number=1;e<info.waveInfo[w].length;e++){
            var entry:Object=info.waveInfo[w][e],slots:Array=entry.Parameters.cf6FixedSlots;
            if(slots==null)continue;
            for(var q:Number=0;q<entry.Quantity;q++){
                var name:String=entry.Attribute.名字+"_"+w+"_"+e+"_"+(entry.Quantity-q);
                expected[name]={slot:slots[q],entry:entry,wave:w+1,entryIndex:e-1,ordinal:q};
                check(wave.spawn(entry.Attribute,e,w,entry.Quantity-q,q),"actual wave accepts "+slots[q].parameters.cf6UnitIdentity);
                pending.push({name:name,birth:frame});
            }
        }
        trace("[CF6_CHAPTER_MAP] "+map.id+" waveActors="+pending.length);age=0;phase=1;
    }
    private static function validate(name:String,row:Object):Void {
        var u:MovieClip=world[name],p:Object=row.slot.parameters;
        check(u!=null && u.__unitInitializedVersion===u.version && isFinite(u.version),"native birth complete "+p.cf6UnitIdentity);
        check(u.cf6ActionState!=null && u.cf6FixedError==undefined && u.cf6UnitIdentity===p.cf6UnitIdentity,"actual fixed adapter "+p.cf6UnitIdentity);
        check(seen[p.cf6UnitIdentity]!==true,"unique chapter identity "+p.cf6UnitIdentity);seen[p.cf6UnitIdentity]=true;total++;
        check(Math.abs(u.__chapterBirthCoordinates.x-row.slot.x)<.06 && Math.abs(u.__chapterBirthCoordinates.z-row.slot.y)<.06
            && u.cf6BirthX===row.slot.x && u.cf6BirthZ===row.slot.y,"exact authored placement "+p.cf6UnitIdentity);
        var pt:Object={x:u._x,y:u.Z轴坐标};world.localToGlobal(pt);
        check(Mover.isPointValid(pt.x,pt.y),"native collision clear at birth "+p.cf6UnitIdentity);
        var numeric:Object=_root.敌人属性表[u.兵种];
        var hp:Number=Math.floor(numeric.hp_min+(numeric.hp_max-numeric.hp_min)/59*u.等级)*u.__cf6DifficultyScale;
        check(isFinite(hp) && hp>100 && u.hp满血值===hp,"actual level and difficulty "+p.cf6UnitIdentity+" hp="+u.hp满血值+" expected="+hp);
        check(u.等级===row.entry.Level && u.cf6SourceSeat===p.cf6SourceSeat,"level and original seat "+p.cf6UnitIdentity);
        if(row.wave!=undefined)check(u.cf6SpawnWave===row.wave && u.cf6SpawnEntry===row.entryIndex && u.cf6SpawnOrdinal===row.ordinal,"wave provenance "+p.cf6UnitIdentity);
        if(p.cf6UnitIdentity=="CF6-M-XX")lootActor=u;
        if(p.cf6UnitIdentity=="CF6-M-IX")check(phaseDeath && world[map.bossEncounter.nextPhase.instanceName].__unitInitializedVersion!=null,"migrated IX waits for real robot successor");
    }
    private static function geometryProbe():Void {
        var a:MovieClip=world.createEmptyMovieClip("laneA",world.getNextHighestDepth()),b:MovieClip=world.createEmptyMovieClip("laneB",world.getNextHighestDepth());
        a._x=500;a.Z轴坐标=600;b._x=700;b.Z轴坐标=600;
        var original:MovieClip=_root.collisionLayer;var wall:MovieClip=_root.createEmptyMovieClip("laneWall",_root.getNextHighestDepth());
        _root.collisionLayer=wall;CollisionLayerRenderer.drawRect(wall,{xMin:590,xMax:610,yMin:570,yMax:630});
        check(!Cf6SoldierActions.clearLane(a,b),"blocking ground lane at zero camera offset");
        world._x=-380;world._y=-220;
        geometry={a:a,b:b,wall:wall,original:original};phase=5;age=0;
    }
    private static function verifyTranslatedGeometry():Void {
        var a:MovieClip=geometry.a,b:MovieClip=geometry.b,point:Object={x:600,y:600};world.localToGlobal(point);
        var direct:Boolean=geometry.wall.hitTest(600,600,true),lane:Boolean=Cf6SoldierActions.clearLane(a,b);
        trace("[CF6_CHAPTER_GEOMETRY] global="+point.x+","+point.y+" wall="+direct+" lane="+lane
            +" actor="+a._x+","+a.Z轴坐标+" target="+b._x+","+b.Z轴坐标+" world="+world._x+","+world._y);
        check(direct && !lane,"blocking ground lane after camera translation");
        a.Z轴坐标=b.Z轴坐标=660;
        check(Cf6SoldierActions.clearLane(a,b),"clear parallel lane after camera translation");
        // Production creates /collisionLayer at the root, not inside the camera.
        world._x=0;world._y=-63;geometry.wall.clear();
        CollisionLayerRenderer.drawBoundary(geometry.wall,170.6667,853.3333,426.6667,529.0667,300,false);
        a._x=681.85;a.Z轴坐标=481.35;b._x=371.2;b.Z轴坐标=475.392;
        check(Cf6SoldierActions.clearLane(a,b),"A10 observed M249 clear lane matches 39 real ground samples at camera y=-63");
        CollisionLayerRenderer.drawRect(geometry.wall,{xMin:520,xMax:536,yMin:461,yMax:500});
        check(!Cf6SoldierActions.clearLane(a,b),"real obstacle on the same A10 firing lane still blocks");
        world._xscale=world._yscale=125;
        check(!Cf6SoldierActions.clearLane(a,b),"camera zoom cannot move a real ground obstacle");
        world._xscale=world._yscale=100;
        world._x=world._y=0;_root.collisionLayer=geometry.original;geometry.wall.removeMovieClip();a.removeMovieClip();b.removeMovieClip();
        geometry=null;beginBoss();
    }
    private static function beginPerformance():Void {
        // Actual A14 waves contain10/10/9 fixed actors. Keep one ten-person
        // wave after validating all29 identities; do not present29 simultaneous
        // actors as the ordinary authored workload.
        perfActors=perfActorMs=perfTicks=perfRays=perfPoints=perfTotalMs=0;perfWindows=[];
        var actions:Object=Cf6SoldierActions,mover:Object=Mover;
        oldRay=actions.clearLane;oldPoint=mover.isPointValid;
        actions.clearLane=function(a:MovieClip,b:MovieClip):Boolean {
            Cf6FixedChapterNativeTest.perfRays++;return Cf6FixedChapterNativeTest.oldRay(a,b);
        };
        mover.isPointValid=function(x:Number,y:Number):Boolean {
            Cf6FixedChapterNativeTest.perfPoints++;return Cf6FixedChapterNativeTest.oldPoint(x,y);
        };
        for(var name:String in world){var u:MovieClip=world[name];
            if(typeof u!="movieclip" || u._parent!==world || typeof u.cf6UnitIdentity!="string")continue;
            if(u.cf6SpawnWave!==1){u.removeMovieClip();continue;}perfActors++;
            u.__chapterOriginalTick=u.soldierTick;
            u.soldierTick=function():Void {
                var started:Number=getTimer();
                this.__chapterOriginalTick();
                Cf6FixedChapterNativeTest.perfTicks++;
                Cf6FixedChapterNativeTest.perfActorMs+=getTimer()-started;
            };
        }
        world._x=180;world._y=-220;hero._x=430;hero._y=hero.Z轴坐标=629;
        phase=3;age=0;lastFrameTime=0;warningPeak=0;samples=[];
    }
    private static function filteredPlan(source:Object):Object {
        var p:Object=ObjectUtil.clone(source);p.groups=[];
        for(var g:Number=0;g<source.groups.length;g++){
            var group:Object={hpRatio:source.groups[g].hpRatio,enemies:[]};
            for(var e:Number=0;e<source.groups[g].enemies.length;e++){
                var entry:Object=source.groups[g].enemies[e];
                if(entry.Parameters.cf6FixedSlots==null)continue;
                group.enemies.push(ObjectUtil.clone(entry));bossExpected+=entry.Quantity;
                for(var q:Number=0;q<entry.Quantity;q++)expected[entry.Parameters.cf6FixedSlots[q].parameters.cf6UnitIdentity]={slot:entry.Parameters.cf6FixedSlots[q],entry:entry};
            }
            p.groups.push(group);
        }
        if(source.nextPhase!=null)p.nextPhase=filteredPlan(source.nextPhase);return p;
    }
    private static function beginBoss():Void {
        if(map.bossEncounter==null){nextMap();return;}
        bossExpected=0;lastSupport=-1;bossTotal=0;phaseDeath=false;pending=[];
        var plan:Object=filteredPlan(map.bossEncounter);
        if(map.id=="A20"){
            var entry:Object;
            for(var w:Number=0;w<info.waveInfo.length;w++)for(var e:Number=1;e<info.waveInfo[w].length;e++)
                if(info.waveInfo[w][e].InstanceName==plan.instanceName)entry=info.waveInfo[w][e];
            check(entry!=null,"actual final human source entry");
            var birthEvent:StageEvent=new StageEvent({EventName:"Cf6ChapterBoss",Enemy:[ObjectUtil.clone(entry)]});birthEvent.execute();
        }else{
            boss=world.createEmptyMovieClip(plan.instanceName,world.getNextHighestDepth());
            boss.hp=100;boss.hp满血值=100;boss.version=1;boss.__unitInitializedVersion=1;
        }
        Cf6BossEncounter.start(world,world.__stageReturnWorldIdentity,plan);phase=2;age=0;
    }
    private static function bossTick():Void {
        for(var name:String in world){
            var u:MovieClip=world[name];
            if(typeof u!="movieclip" || u._parent!==world || u.cf6BossOwnerToken==undefined || typeof u.cf6UnitIdentity!="string" || u.__chapterObserved)continue;
            u.__chapterObserved=true;pending.push({name:name,birth:frame});
            if(lastSupport>=0 && !phaseDeath)check(frame-lastSupport>=map.bossEncounter.intervalFrames,"native finite support spacing");
            lastSupport=frame;
        }
        for(var i:Number=pending.length-1;i>=0;i--){
            var row:Object=pending[i];if(frame-row.birth<12)continue;
            var unit:MovieClip=world[row.name];validate(row.name,expected[unit.cf6UnitIdentity]);bossTotal++;pending.splice(i,1);
        }
        if(map.id=="A20" && !phaseDeath && bossTotal==1 && age>45){
            boss=world[map.bossEncounter.instanceName];phaseDeath=true;
            boss.hp=0;boss.状态改变("血腥死");boss._killed=true;DeathEventComponent.onDeath(boss);
            check(Cf6BossEncounter.blocksClear(world,StageManager.instance),"human death preserves phase ownership");
        }
        if(bossTotal==bossExpected && pending.length==0){
            trace("[CF6_CHAPTER_BOSS] "+map.id+" fixedSupport="+bossTotal+" nativePhase="+phaseDeath);nextMap();return;
        }
        if(age>900){check(false,"boss support bounded timeout "+map.id+" received="+bossTotal+" expected="+bossExpected);nextMap();}
    }
    private static function beginDeath():Void {
        check(lootActor!=null && lootActor.soldierPhase==1,"actual G1111 shield actor selected");
        lootActor.__breakOriginX=lootActor._x;
        lootActor.hp=0;
        org.flashNight.arki.spatial.move.Mover.beginEnemyHitMove(lootActor,"右",20,1);
        check(lootActor.soldierPhase==0,"actual shield break starts transition");
        check(_root._saveExt.bookRun.cf6SoldierLoot.records["u.CF6-M-XX"]==null,"shield break never yields a package");
        phase=4;age=0;deathDone=false;
    }
    private static function deathTick():Void {
        if(age==15)check(lootActor.soldierPhase==0,"shield transition waits beyond the break art for the lethal impulse");
        if(!deathDone && lootActor.soldierPhase==2){
            check(!org.flashNight.arki.spatial.move.Mover.pendingPhaseMotion(lootActor)
                && lootActor._x>lootActor.__breakOriginX+1 && Math.abs(lootActor._y-lootActor.Z轴坐标)<.1,
                "same second-phase actor retains the settled horizontal and ground position");
            check(lootActor.长枪.name=="G1111" && lootActor.长枪.value.isRocketMode===false,"native item survived shield break");
            lootActor.长枪.value.shot=4;lootActor.长枪.value.chapterExtension={kept:9};
            LinearCongruentialEngine.instance.nextFloat=function():Number{return 0;};
            lootActor.hp=0;lootActor.dispatcher.publish("kill",lootActor);deathDone=true;
            for(var n:Number=0;n<4;n++)Cf6SoldierLoot.prepareForTransition();
            var p:Object=_root._saveExt.bookRun.cf6SoldierLoot.records["u.CF6-M-XX"];
            check(p.kind=="longgun" && p.state=="OWNED","native combat death admits one package "+p.state+" error="+Cf6SoldierLoot.lastError);
            check(p.items[0].value.shot===4 && p.items[0].value.isRocketMode===false && p.items[0].value.chapterExtension.kept===9,"native death snapshot keeps full actual item");
            check(_root._saveExt.bookRun.cf6SoldierLoot.packages===1 && RewardStashService.peek().entries.length>=2,"one package with ordinary reload ammo");
            var count:Number=RewardStashService.peek().entries.length;
            lootActor.dispatcher.publish("kill",lootActor);Cf6SoldierLoot.prepareForTransition();
            check(RewardStashService.peek().entries.length===count,"duplicate kill cannot duplicate ownership");
            trace("[CF6_CHAPTER_DEATH] actual shield break then native kill, exact G1111 packet owned");
            beginBoss();return;
        }
        if(age>180){check(false,"native shield transition timeout");beginBoss();}
    }
    private static function performanceTick():Void {
        var now:Number=getTimer();if(lastFrameTime>0)samples.push(now-lastFrameTime);lastFrameTime=now;
        var warnings:Number=0;
        for(var name:String in world){var u:MovieClip=world[name];if(typeof u!="movieclip" || u.cf6ActionState==null)continue;
            u.攻击目标=hero._name;if(u.cf6Warning._visible)warnings++;
            if(!isFinite(u._x) || !isFinite(u.Z轴坐标)){check(false,"finite A14 actor position");finish();return;}
        }
        perfTotalMs+=perfActorMs;perfWindows.push(perfActorMs);perfActorMs=0;
        warningPeak=Math.max(warningPeak,warnings);
        if(age>=180){
            samples.sort(Array.NUMERIC);var sum:Number=0;for(var s:Number=0;s<samples.length;s++)sum+=samples[s];
            trace("[CF6_CHAPTER_PERF] A14 authored first wave actors="+perfActors+"; samples="+samples.length+" frameMeanMs="+Math.round(sum/samples.length*100)/100
                +" p95Ms="+samples[Math.floor(samples.length*.95)]+" maxMs="+samples[samples.length-1]+" warningPeak="+warningPeak+" emission=controlled");
            var actions:Object=Cf6SoldierActions,mover:Object=Mover;
            actions.clearLane=oldRay;mover.isPointValid=oldPoint;
            perfWindows.sort(Array.NUMERIC);
            trace("[CF6_AI_COST] actors="+perfActors+" frames="+perfWindows.length+" ticks="+perfTicks
                +" tickTotalMs="+perfTotalMs+" tickMeanPerFrameMs="+Math.round(100*perfTotalMs/perfWindows.length)/100
                +" tickP95PerFrameMs="+perfWindows[Math.floor(perfWindows.length*.95)]
                +" rayCalls="+perfRays+" pointProbes="+perfPoints+" emission=controlled");
            check(perfTicks>=1700 && perfWindows.length>=175,"actual A14 ten-actor AI cost sample");
            check(samples.length>=175 && warningPeak==0,"bounded native workload has no synthetic fire lines");beginBoss();
        }
    }
    private static function nextMap():Void {Cf6BossEncounter.cancel();index++;beginMap();}
    private static function tick():Void {
        if(finished)return;frame++;age++;_root.帧计时器.当前帧数=frame;
        if(frame>5000){check(false,"chapter bounded timeout");finish();return;}
        for(var t:Number=lifeTasks.length-1;t>=0;t--){var job:Object=lifeTasks[t];
            if(job.unit._parent!==world || job.unit.version!==job.version){lifeTasks.splice(t,1);continue;}job.fn.apply(null,job.args);
        }
        if(phase==0){if(!propsReady || !BookDefinition.ready("cf6-sting","type61"))return;
            book=BookDefinition.get("cf6-sting","type61");config=book.type61.soldiers;
            check(config.counts.personnel==158 && BookDefinition.valid(book),"actual full runtime book accepted");beginMap();return;}
        Cf6SoldierActions.now();
        if(phase==1 && age>=16){
            for(var i:Number=0;i<pending.length;i++)validate(pending[i].name,expected[pending[i].name]);pending=[];
            if(index==0){geometryProbe();return;}
            if(map.id=="A14"){beginPerformance();return;}
            if(map.id=="A19"){beginDeath();return;}beginBoss();return;
        }
        if(phase==2)bossTick();else if(phase==3)performanceTick();else if(phase==4)deathTick();else if(phase==5 && age>=2)verifyTranslatedGeometry();
    }
    private static function finish():Void {
        if(finished)return;finished=true;
        if(chapterCollision!=null)chapterCollision.removeMovieClip();Cf6BossEncounter.cancel();
        check(total==158,"all158 actual chapter identities observed; got "+total);
        if(driver!=null)driver.removeMovieClip();if(world!=null)world.removeMovieClip();
        var service:Object=Cf6SoldierLoot;if(service.watcher!=null)delete service.watcher.onEnterFrame;
        if(slot!=null)SharedObject.getLocal(slot).clear();
        trace("Cf6FixedChapterNativeTest: "+passed+" passed, "+failed+" failed; "+total+" chapter actors, 12 authored maps");
        if(failed>0)trace("[TEST_FAIL] Cf6FixedChapterNativeTest suite failed");
        trace("FocusedTestRunId cf6-fixed-chapter Complete: "+_root.cf6ChapterRunId);
    }
}
