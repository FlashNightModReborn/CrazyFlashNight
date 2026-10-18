import org.flashNight.arki.scene.BaseSiegeController;
import org.flashNight.arki.scene.StageManager;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.scene.StageEvent;
import org.flashNight.arki.scene.SceneInteractionManager;
import org.flashNight.arki.scene.WaveSpawner;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater;

/** Actual MovieClip identities, stage-event spawning and production AI target selection. */
class org.flashNight.arki.scene.BaseSiegeFlowTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var world:MovieClip;
    private static var actor:MovieClip;
    private static var manager:Object;
    private static var events:Object;
    private static var clears:Number;
    private static var legacyRoom:Object;
    public static function runAllTests():Void {
        passed=0;failed=0;clears=0;events={};
        var saved:Object={world:_root.gameworld,hero:_root.控制目标,pause:_root.暂停,
            transition:_root.场景转换中,sound:_root.播放音效,spawn:_root.加载游戏世界人物,
            types:_root.兵种库,clock:_root.帧计时器};
        _root.暂停=false;_root.场景转换中=false;_root.帧计时器={当前帧数:1};
        _root.播放音效=function(text:String):Void {};
        _root.兵种库={};
        _root.加载游戏世界人物=function(id:String,name:String,depth:Number,init:Object):MovieClip {
            return org.flashNight.arki.scene.BaseSiegeFlowTest.spawnUnit(name,depth,init);
        };
        manager=StageManager.getInstance();var oldClear:Function=manager.clearStage;
        manager.isActive=true;manager.isFailed=false;manager.isFinished=false;
        manager.clearStage=function():Void {org.flashNight.arki.scene.BaseSiegeFlowTest.recordClear();};
        setupWorld();
        // Reproduce the real transition state: close() leaves gameworld null before Start.
        var spawnContext:Object=WaveSpawner.getInstance();
        spawnContext.close();
        var sceneContext:Object=org.flashNight.arki.scene.SceneManager.getInstance();
        var savedSceneWorld:MovieClip=sceneContext.gameworld;
        var savedPoints:Array=manager.spawnPoints;var savedEnvironment:Object=manager.environment;
        sceneContext.gameworld=world;manager.spawnPoints=[];manager.environment={};
        spawnContext.prepareScene({basicInfo:{PlayerX:1610,PlayerY:455}});
        check(spawnContext.gameworld===world && !spawnContext.isActive,"pre-Start scene binding does not start waves");
        var startData:Object={EventName:"Start",Enemy:[
            {spritename:"主角-男",Name:"A",InstanceName:"arrivalA",x:1510,y:435},
            {spritename:"主角-男",Name:"B",InstanceName:"arrivalB",x:1460,y:490}]};
        var arrival:StageEvent=new StageEvent(startData);arrival.execute();
        check(world.arrivalA._name=="arrivalA" && world.arrivalB._name=="arrivalB","both Start-event companions survive a closed spawner");
        check(world.arrivalA.getDepth()!=world.arrivalB.getDepth(),"Start-event companions receive distinct current-world depths");
        check(world.arrivalA._x==1510 && world.arrivalB._y==490,"Start-event companion coordinates are preserved");
        world.arrivalA.removeMovieClip();world.arrivalB.removeMovieClip();
        sceneContext.gameworld=savedSceneWorld;manager.spawnPoints=savedPoints;manager.environment=savedEnvironment;
        BaseSiegeController.start("crash");
        check(BaseSiegeController.snapshot()==null,"crash has no persistent controller");
        check(_root.__baseSiegeLoadWatch._name==undefined && _root.__baseSiegeWatch._name==undefined,"no objective HUD or idle frame observer");
        legacyRoom={owner:StageReturnFlow.worldIdentity(world),manager:manager,done:true};
        var begin:Number=getTimer();for(var p:Number=0;p<20000;p++)legacyIdleTick(legacyRoom);
        trace("BaseSiegePerf ScriptOnly: legacyIdleCalls=20000 legacyMs="+(getTimer()-begin)+" revisedIdleObservers=0; excludes rendering and game AI");
        BaseSiegeController.start("rhino");
        check(BaseSiegeController.snapshot().observerActive===true,"temporary observer waits for external art");
        BaseSiegeController.pollLoaded();
        check(BaseSiegeController.snapshot().assetsReady===true,"actual ready markers admit loaded art");
        check(BaseSiegeController.snapshot().observerActive===false,"observer is removed once art is ready");
        check(world.stageInstance0.shieldMC.cacheAsBitmap===true && world.stageInstance1.cacheAsBitmap===true,"static coil body and relay are cached independently of animated power");
        check(world.__siegeOperation._name==undefined,"relay cannot be operated before first-wave dialogue");
        BaseSiegeController.signal("enable");var action:Function=world.__siegeOperation.onInteract;
        check(BaseSiegeController.snapshot().phase=="ready","dialogue continuation enables operation");
        action.call(world.__siegeOperation);
        check(BaseSiegeController.snapshot().deployed===false,"far callback is rejected");
        setHero(1560,420);actor.hp=0;action.call(world.__siegeOperation);
        check(BaseSiegeController.snapshot().deployed===false,"dead player callback is rejected");
        actor.hp=100;_root.暂停=true;action.call(world.__siegeOperation);
        check(BaseSiegeController.snapshot().deployed===false,"paused player callback is rejected");
        _root.暂停=false;SceneInteractionManager.instance.update(1560,420);SceneInteractionManager.instance.interact();
        check(BaseSiegeController.snapshot().deployed===true && events.SiegeRelayActivated==1,"one operation activates the real stage event");
        check(BaseSiegeController.snapshot().coilAnimation=="shieldReturn" && world.stageInstance0.shieldMC.lastRequested==73,"R5 transition starts from the shield endpoint");
        check(world.siege_relay_guard.threat==30 && world.siege_relay_guard.是否为敌人===false,"production StageEvent passes threat and friendly faction");
        check(world.siege_relay_guard.publishStageEvent===true && world.siege_relay_guard.产生源=="无","guard destruction participates in named death events without wave count");
        check(!events.SiegeCounterattack,"counterattack waits for a live initialized guard target");
        action.call(world.__siegeOperation);
        check(events.SiegeRelayActivated==1,"duplicate operation cannot spawn duplicate guard units");
        BaseSiegeController.pollLoaded();
        check(BaseSiegeController.snapshot().guardReady===true && events.SiegeCounterattack==1,"initialized guard releases the triggered second wave once");
        check(world.siege_relay_guard.man._visible===false && world.siege_relay_guard.area._width==50,"guard uses the map relay art with a sized live hitbox");
        check(BaseSiegeController.snapshot().observerActive===true,"R5 transition keeps only a short-lived observer");
        for(var backTick:Number=0;backTick<36;backTick++)BaseSiegeController.pollLoaded();
        check(world.stageInstance0.shieldMC.lastRequested==1 && world.stageInstance0.interferenceMC._visible===true && BaseSiegeController.snapshot().coilAnimation=="interferenceForward","shield returns to the shared tower before interference starts");
        for(var forwardTick:Number=0;forwardTick<25;forwardTick++)BaseSiegeController.pollLoaded();
        check(world.stageInstance0.interferenceMC.lastRequested==49 && world.stageInstance0.effectPowered._visible===true && BaseSiegeController.snapshot().observerActive===false && BaseSiegeController.snapshot().coilAnimation=="none","interference completes and the temporary observer retires");
        check(BaseSiegeController.interceptClear(manager,world),"unfinished waves still block exit");
        WaveSpawner.instance.isFinished=true;world.siege_relay_guard.hp=0;
        check(BaseSiegeController.interceptClear(manager,world),"destroyed relay cannot pass clear");
        world.siege_relay_guard.hp=5000;
        check(!BaseSiegeController.interceptClear(manager,world) && BaseSiegeController.snapshot().done===true,"wave completion releases the existing clear path");
        check(world.siege_relay_guard.threat==0,"completed guard objective releases threat");

        // Real target-cache selection: a farther threatened facility beats the nearer hero.
        var attacker:MovieClip=spawnUnit("focusedAttacker",world.getNextHighestDepth(),{_x:500,_y:600,是否为敌人:true});
        setHero(520,600);actor.是否为敌人=false;actor.threat=10;actor.aabbCollider={left:510,right:530};
        var guard:MovieClip=world.siege_relay_guard;guard._x=700;guard.threat=30;guard.aabbCollider={left:675,right:725};
        TargetCacheManager.initialize();TargetCacheUpdater.addUnit(actor);TargetCacheUpdater.addUnit(guard);TargetCacheUpdater.addUnit(attacker);
        check(TargetCacheManager.findValidEnemyForAI(attacker,0,15)===guard,"production AI selects the live relay above the closer player");
        guard.hp=0;TargetCacheUpdater.removeUnit(guard);_root.帧计时器.当前帧数++;
        check(TargetCacheManager.findValidEnemyForAI(attacker,0,15)!==guard,"retired relay is excluded after the production death-removal notification");
        BaseSiegeController.start("tigr");BaseSiegeController.pollLoaded();BaseSiegeController.signal("enable");
        check(SceneInteractionManager.instance.currentMC===world.__siegeOperation,"player already at the relay can interact immediately after dialogue");
        action.call(world.__siegeOperation);
        check(BaseSiegeController.snapshot().deployed===false,"stale callback in the same world is rejected");
        var oldWorld:MovieClip=world;oldWorld.removeMovieClip();setupWorld();
        check(oldWorld===world,"test covers actual AVM1 MovieClip reference rebinding");
        BaseSiegeController.start("roof");BaseSiegeController.pollLoaded();action.call(world.__siegeOperation);
        check(BaseSiegeController.snapshot().kind=="roof" && BaseSiegeController.snapshot().deployed===false,"previous scene callback cannot affect roof");
        check(BaseSiegeController.snapshot().observerActive===false,"roof has no persistent escort or repair polling");
        BaseSiegeController.signal("finished");
        check(clears==0,"premature ending callback cannot finish combat");
        BaseSiegeController.signal("outage");
        check(world.stageInstance1.lastRequested==2,"outage is driven by dialogue event");
        check(BaseSiegeController.interceptClear(manager,world) && events.SiegeRoofSecured==1,"original combat clear starts the narrative ending");
        BaseSiegeController.interceptClear(manager,world);
        check(events.SiegeRoofSecured==1,"ending dialogue is dispatched exactly once");
        check(world.siege_engineer._name==undefined && world.__siegeOperation._name==undefined,"no escort actor or repair interaction gate is created");
        setHero(0,0);BaseSiegeController.signal("restore");
        check(world.stageInstance1.lastRequested==3,"repair is shown by dialogue without standing or escort distance");
        BaseSiegeController.signal("finished");
        check(clears==1 && BaseSiegeController.snapshot().done===true,"ending continuation releases original completion");
        BaseSiegeController.signal("finished");check(clears==1,"duplicate ending callback is inert");
        BaseSiegeController.start("lobby");
        check(BaseSiegeController.snapshot()==null && !BaseSiegeController.interceptClear(manager,world),"original base rooms have no added gameplay gate");
        world.removeMovieClip();_root.gameworld=saved.world;manager.clearStage=oldClear;manager.isActive=false;
        _root.控制目标=saved.hero;_root.暂停=saved.pause;_root.场景转换中=saved.transition;
        _root.播放音效=saved.sound;_root.加载游戏世界人物=saved.spawn;_root.兵种库=saved.types;_root.帧计时器=saved.clock;
        trace("BaseSiegeFlowTest Tests Passed: "+passed);trace("BaseSiegeFlowTest Tests Failed: "+failed);
    }
    private static function legacyIdleTick(r:Object):Void {
        if(!(r!=null && r===legacyRoom && r.owner!=null
            && r.owner===StageReturnFlow.worldIdentity(_root.gameworld)
            && r.manager.isActive && !r.manager.isFailed && !r.manager.isFinished))return;
        if(r.done)return;
    }
    public static function recordClear():Void {clears++;}
    private static function setupWorld():Void {
        world=_root.createEmptyMovieClip("__siegeWorld",_root.getNextHighestDepth());_root.gameworld=world;
        actor=spawnUnit("focusedHero",1,{_x:900,_y:455,是否为敌人:false});_root.控制目标="focusedHero";
        world.createEmptyMovieClip("地图",2).僵尸型敌人总个数=0;
        for(var i:Number=0;i<2;i++){
            var prop:MovieClip=world.createEmptyMovieClip("stageInstance"+i,3+i);prop.__siegeReady=true;
            prop.beginFill(0x888888);prop.moveTo(0,0);prop.lineTo(20,0);prop.lineTo(20,20);prop.lineTo(0,20);prop.endFill();
            prop.gotoAndStop=function(state:Number):Void {this.lastRequested=state;};
            var shield:MovieClip=prop.createEmptyMovieClip("shieldMC",prop.getNextHighestDepth());
            var interference:MovieClip=prop.createEmptyMovieClip("interferenceMC",prop.getNextHighestDepth());
            var standby:MovieClip=prop.createEmptyMovieClip("effectStandby",prop.getNextHighestDepth());
            var powered:MovieClip=prop.createEmptyMovieClip("effectPowered",prop.getNextHighestDepth());
            var parts:Array=[shield,interference,standby,powered];
            for(var j:Number=0;j<parts.length;j++)parts[j].gotoAndStop=function(state:Number):Void {this.lastRequested=state;};
            shield._visible=true;interference._visible=false;standby._visible=true;powered._visible=false;
        }
        var interactions:Object=SceneInteractionManager.getInstance();interactions.interactionInfoList=[];interactions.currentMC=null;
        world.addInteraction=function(mc:MovieClip,dx:Number,dy:Number,x:Number,y:Number):Void {
            org.flashNight.arki.scene.SceneInteractionManager.instance.addInteraction(mc,dx,dy,x,y);
        };
        world.dispatcher={publish:function(name:String):Void {org.flashNight.arki.scene.BaseSiegeFlowTest.recordEvent(name);}};
        var spawner:Object=WaveSpawner.getInstance();spawner.gameworld=world;spawner.spawnPoints=[];spawner.isFinished=false;
    }
    public static function recordEvent(name:String):Void {
        events[name]=events[name]>0?events[name]+1:1;
        if(name=="SiegeRelayActivated"){
            var data:Object={EventName:name,Enemy:[{spritename:"特殊友军-保护仪器",Name:"有源中继",InstanceName:"siege_relay_guard",IsHostile:false,Level:1,x:580,y:621.6,Parameters:{threat:30,publishStageEvent:true}}]};
            var stageEvent:StageEvent=new StageEvent(data);stageEvent.execute();
        }
    }
    public static function spawnUnit(name:String,depth:Number,init:Object):MovieClip {
        var u:MovieClip=_root.gameworld.createEmptyMovieClip(name,depth);
        for(var key:String in init)u[key]=init[key];
        u.hp=5000;u.threat=init.threat==undefined?10:init.threat;
        u.Z轴坐标=u._y;u.状态改变=function(label:String):Void {};
        u.createEmptyMovieClip("man",1);var area:MovieClip=u.createEmptyMovieClip("area",2);
        area.beginFill(0xFFFFFF);area.moveTo(0,0);area.lineTo(10,0);area.lineTo(10,10);area.lineTo(0,10);area.lineTo(0,0);area.endFill();
        u.aabbCollider={left:u._x-10,right:u._x+10,updateFromUnitArea:function(unit:MovieClip):Void {this.left=unit._x-25;this.right=unit._x+25;}};
        return u;
    }
    private static function setHero(x:Number,y:Number):Void {actor._x=x;actor._y=y;actor.Z轴坐标=y;}
    private static function check(value:Boolean,label:String):Void {
        if(value)passed++;else{failed++;trace("BaseSiegeFlowTest FAIL: "+label);}
    }
}
