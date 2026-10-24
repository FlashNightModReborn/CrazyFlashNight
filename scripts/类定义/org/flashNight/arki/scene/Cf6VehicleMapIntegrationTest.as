import org.flashNight.arki.scene.*;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.neur.Event.EventDispatcher;

/** Map/Stage/Wave integration only. Vehicle, resources, camera, save queries and fade are explicit memory ports. */
class org.flashNight.arki.scene.Cf6VehicleMapIntegrationTest {
    private static var passed:Number,failed:Number;
    private static var ports:Array;
    private static var currentFixture:Object;
    private static function check(value:Boolean,label:String):Void {
        if(value)passed++;else {failed++;trace("[FAIL] Cf6VehicleMapIntegration: "+label);}
    }
    private static function port(api:Object,key:String,value):Void {
        ports.push({api:api,key:key,value:api[key]});api[key]=value;
    }
    private static function noop():Void {}
    private static function clearEvent():Void {
        _root.__cf6MapClearCount++;
        if(_root.__cf6MapMode=="pause-on-clear")_root.__cf6MapPeer=PauseManager.lease(true,"peer-clear");
    }
    private static function waveEvent():Void {_root.__cf6MapWaveCount++;}
    private static function vehicleBegin(room:Object,spec:Object):Object {
        var token:Object={};var actor:MovieClip=room.world.hero;
        var s:Object={room:room,world:room.world,owner:room.owner,actor:actor,token:token,status:"playing",closed:false,
            rules:{phase:"road",roadKills:11,budget:17},resumeStatus:"playing"};
        actor.__cf6VehicleFixtureOwner=token;room.world.__cf6VehicleSession=s;return s;
    }
    private static function vehicleTick(s:Object):String {
        if(s==null || s.closed)return "cancelled";
        if(s.world!==_root.gameworld || s.world.__stageReturnWorldIdentity!==s.owner
                || s.world.__cf6VehicleSession!==s || s.world.hero.__cf6VehicleFixtureOwner!==s.token)return "cancelled";
        if(!(s.actor.hp>0)) {
            if(s.status!="dead")s.resumeStatus=s.status;
            s.status="dead";return "dead";
        }
        if(s.status=="dead")s.status=s.resumeStatus;
        return s.status;
    }
    private static function vehicleDispose(s:Object):Void {
        if(s==null || s.closed)return;
        _root.__cf6MapDisposeCount++;
        if(s.world.__stageReturnWorldIdentity===s.owner && s.world.__cf6VehicleSession===s)delete s.world.__cf6VehicleSession;
        if(s.actor.__cf6VehicleFixtureOwner===s.token)delete s.actor.__cf6VehicleFixtureOwner;
        s.closed=true;
    }
    private static function cleanup():Void {
        Cf6MapMechanism.teardown();
        if(_root.__cf6MapPeer!=undefined)PauseManager.releaseLease(_root.__cf6MapPeer);
        _root.__cf6MapPeer=undefined;
        if(currentFixture.spawner!=null)currentFixture.spawner.close();
        if(_root.gameworld._name=="__cf6VehicleMapFixture")_root.gameworld.removeMovieClip();
        currentFixture=null;
    }
    private static function fixture(mode:String,waveBeforeBind:Boolean):Object {
        cleanup();_root.暂停=false;_root.__cf6MapMode=mode;
        _root.__cf6MapClearCount=0;_root.__cf6MapWaveCount=0;_root.__cf6MapTypedCount=0;
        _root.__cf6MapFadeCount=0;_root.__cf6MapRecordCount=0;_root.__cf6MapBridgeCount=0;_root.__cf6MapDisposeCount=0;
        _root.savePath="cf6.vehicle.map.memory";_root.当前关卡名="书中历险-毒刺行动";_root.控制目标="hero";_root.当前为战斗地图=true;
        _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"historical",outcome:"active",slot:String(_root.savePath),seed:23,startedAt:1792550000000}};
        var w:MovieClip=_root.createEmptyMovieClip("__cf6VehicleMapFixture",_root.getNextHighestDepth());_root.gameworld=w;w.__stageReturnWorldIdentity={};
        w.createEmptyMovieClip("地图",1);w.地图.僵尸型敌人总个数=0;
        w.createEmptyMovieClip("效果",2);w.dispatcher=new EventDispatcher();
        w.dispatcher.subscribe("Clear",clearEvent,null);w.dispatcher.subscribe("WaveFinished",waveEvent,null);
        var h:MovieClip=w.createEmptyMovieClip("hero",w.getNextHighestDepth());h.hp=h.hp满血值=100;h.mp=h.mp满血值=40;h._x=10;h._y=h.Z轴坐标=20;
        var managerApi:Object=StageManager;managerApi.instance=null;var manager:Object=StageManager.getInstance();
        manager.gameworld=w;manager.currentStage=0;manager.isActive=true;manager.isCleared=false;manager.isFailed=false;manager.isFinished=false;
        manager.stageMode="infinite";manager.stageInfoList=[{},{}];manager.environment={};manager.spawnPoints=[];manager.timePoolController=null;
        manager.requestCf6VehicleAdvance=function(world:MovieClip,owner:Object,stage:Number):String {
            _root.__cf6MapTypedCount++;
            var api:Object=org.flashNight.arki.scene.StageManager;return api.prototype.requestCf6VehicleAdvance.call(this,world,owner,stage);
        };
        var life:Object={life:"alive",outcome:"active",revision:1};var runApi:Object=StageRunSession;runApi._run=life;runApi._returnRequested=false;
        var sceneApi:Object=SceneManager;sceneApi.instance=null;SceneManager.getInstance().gameworld=w;
        var waveApi:Object=WaveSpawner;waveApi.instance=null;
        var wheelApi:Object=WaveSpawnWheel;wheelApi.instance=null;WaveSpawnWheel.getInstance();
        var info:StageInfo=new StageInfo({BasicInformation:{Environment:{},Animation:{Load:1}},
            Wave:{SubWave:[{WaveInformation:{Duration:0,FinishRequirement:0},EnemyGroup:{Enemy:[]}}]}});
        manager.currentStageInfo=info;
        var spawner:WaveSpawner=WaveSpawner.getInstance();spawner.init(info);manager.spawner=spawner;
        currentFixture={world:w,hero:h,manager:manager,spawner:spawner,life:life,owner:w.__stageReturnWorldIdentity};
        if(waveBeforeBind) {
            spawner.clockTick();
            check(spawner.isFinished && !manager.isCleared && _root.__cf6MapClearCount==0,"real empty wave before room binding cannot clear");
        }
        check(Cf6MapMechanism.beginRoom(w,w.__stageReturnWorldIdentity,"A07",{assetScale:1024/600,layers:[],vehicle:Cf6VehicleTestData.spec()}),"A07 room admitted with explicit vehicle port");
        var mechanismApi:Object=Cf6MapMechanism;delete mechanismApi.watch.onEnterFrame;
        currentFixture.room=w.__cf6Mechanism;
        _root.转场景记录数据=function():Void {_root.__cf6MapRecordCount++;};
        _root.淡出动画={__transitionProjectionIdentity:{},__returnFadeActive:false};
        _root.淡出动画.淡出跳转帧=function(frame:String) {
            _root.__cf6MapFadeCount++;
            if(_root.__cf6MapMode=="throw")throw new Error("fixture navigation outcome unknown");
            if(_root.__cf6MapMode=="undefined")return undefined;
            this.__returnFadeActive=true;this.跳转帧=frame;this.__stageReturnToken=undefined;this.__transitionProjectionIdentity={};return true;
        };
        return currentFixture;
    }
    private static function ticks(count:Number):Void {for(var n:Number=0;n<count;n++)Cf6MapMechanism.tick();}
    private static function tail(f:Object):Void {f.room.vehicle.status="complete";Cf6MapMechanism.tick();}
    private static function emptyWave():Void {
        var f:Object=fixture("accepted",false);f.spawner.clockTick();ticks(120);
        check(f.spawner.isFinished && _root.__cf6MapWaveCount==1,"real WaveSpawner completes the zero-enemy ordinary wave once");
        check(!f.manager.isCleared && _root.__cf6MapClearCount==0 && !f.room.delivered,"empty wave/time cannot deliver vehicle clear");
        check(_root.__cf6MapTypedCount==0 && _root.__cf6MapFadeCount==0 && f.world.允许通行===false,"playing car cannot navigate through ordinary exit");
        f=fixture("accepted",true);ticks(5);
        check(!f.manager.isCleared && !f.room.delivered,"latched early clear is not vehicle completion");tail(f);
        check(_root.__cf6MapClearCount==1 && f.room.advanceReceipt.status=="accepted","only actual vehicle port tail releases early wave clear");
    }
    private static function singleTail():Void {
        var f:Object=fixture("accepted",false);f.spawner.clockTick();tail(f);ticks(20);
        check(_root.__cf6MapClearCount==1 && f.manager.isCleared && f.manager.currentStage==0,"tail clears actual StageManager exactly once without incrementing stage");
        check(_root.__cf6MapTypedCount==1 && _root.__cf6MapFadeCount==1 && _root.__cf6MapRecordCount==1,"tail uses typed advance and shared navigation writer once");
        check(_root.__cf6MapBridgeCount==1 && f.room.advanceReceipt.status=="accepted" && f.world.允许通行===false,"accepted transfer intent retains closed legacy gate");
        check(f.manager.requestCf6VehicleAdvance(f.world,f.owner,0)=="rejected" && _root.__cf6MapFadeCount==1,"duplicate typed request cannot replay fade");
    }
    private static function lifeCase(loading:Boolean):Void {
        var f:Object=fixture("accepted",false);f.spawner.clockTick();Cf6MapMechanism.tick();
        var rules:Object=f.room.vehicle.rules;if(loading)f.room.pending=1;
        f.hero.hp=0;StageRunSession.onHeroDeath();Cf6MapMechanism.tick();
        check(f.life.life=="dead" && f.life.outcome=="active" && !f.manager.isFailed,"vehicle HP0 is life death, not StageFailed");
        check(f.room.vehicle.status=="dead" && !f.room.failed && _root.__cf6MapClearCount==0,"death waits without clear or room teardown even during resource wait");
        f.hero.hp=100;StageRunSession.onHeroRespawn(f.hero);f.room.pending=0;Cf6MapMechanism.tick();
        check(f.life.life=="alive" && f.room.vehicle.status=="playing" && f.room.vehicle.rules===rules && rules.roadKills==11 && rules.budget==17,"same-world revival resumes simulated vehicle state without resetting progress");
        tail(f);check(_root.__cf6MapClearCount==1 && _root.__cf6MapFadeCount==1,"revived vehicle can complete through the standard seam");
    }
    private static function foreignPause(mode:String):Void {
        var f:Object=fixture(mode,false);f.spawner.clockTick();Cf6MapMechanism.tick();
        if(mode=="pause-before-tail")_root.__cf6MapPeer=PauseManager.lease(true,"peer-before-tail");
        tail(f);ticks(5);
        check(_root.__cf6MapClearCount==1 && f.manager.isCleared,"tail can record its real clear while foreign UI owns pause");
        check(_root.__cf6MapTypedCount==0 && _root.__cf6MapFadeCount==0 && f.room.advanceReceipt==undefined && f.room.vehicleAdvanceStatus==undefined,"foreign pause defers first navigation without consuming the one-shot receipt");
        check(PauseManager.isPaused(),"foreign pause is not released by vehicle completion");
        check(f.world.允许通行===false,"legacy gate stays closed while first typed navigation waits for foreign pause");
        PauseManager.releaseLease(_root.__cf6MapPeer);_root.__cf6MapPeer=undefined;Cf6MapMechanism.tick();ticks(3);
        check(_root.__cf6MapClearCount==1 && _root.__cf6MapTypedCount==1 && _root.__cf6MapFadeCount==1 && f.room.advanceReceipt.status=="accepted","unpause issues the first navigation exactly once");
    }
    private static function unknownAndReplacement():Void {
        var modes:Array=["undefined","throw","bridge-refuse"];
        for(var i:Number=0;i<modes.length;i++) {
            var f:Object=fixture(modes[i],false);f.spawner.clockTick();tail(f);ticks(10);
            check(f.room.advanceReceipt.status=="unknown" && _root.__cf6MapFadeCount==1,"unknown "+modes[i]+" records outcome without replay");
            check(f.world.允许通行===false && f.room.failed && _root.__cf6MapDisposeCount==1,"unknown "+modes[i]+" releases only room simulation and closes exit");
            check(f.manager.requestCf6VehicleAdvance(f.world,f.owner,0)=="rejected" && _root.__cf6MapFadeCount==1,"unknown "+modes[i]+" remains one-shot after direct retry");
        }
        f=fixture("accepted",false);f.spawner.clockTick();tail(f);
        var newCamera:Object={};_root.__cf6MapCameraOwner=newCamera;
        f.world.removeMovieClip();var replacement:MovieClip=_root.createEmptyMovieClip("__cf6VehicleMapFixture",_root.getNextHighestDepth());
        _root.gameworld=replacement;replacement.__stageReturnWorldIdentity={};replacement.允许通行=true;
        var newVehicle:Object={};replacement.__cf6VehicleSession=newVehicle;
        _root.__cf6MapPeer=PauseManager.lease(true,"replacement-world");Cf6MapMechanism.tick();
        check(replacement.允许通行===true && replacement.__cf6VehicleSession===newVehicle,"old accepted room teardown never mutates same-path replacement world");
        check(_root.__cf6MapCameraOwner===newCamera && PauseManager.isPaused(),"old teardown leaves new camera and foreign pause owners intact");
        check(_root.__cf6MapFadeCount==1,"world replacement cannot replay accepted navigation");
    }
    public static function runAllTests():Void {
        passed=failed=0;ports=[];PauseManager.install();
        var keys:Array=["gameworld","控制目标","存档系统","savePath","_saveExt","当前关卡名","当前为战斗地图","暂停","场景转换中","server","淡出动画","转场景记录数据","场景进入位置名","发布消息",
            "__cf6MapMode","__cf6MapPeer","__cf6MapClearCount","__cf6MapWaveCount","__cf6MapTypedCount","__cf6MapFadeCount","__cf6MapRecordCount","__cf6MapBridgeCount","__cf6MapDisposeCount","__cf6MapCameraOwner"];
        var saved:Object={};for(var i:Number=0;i<keys.length;i++)saved[keys[i]]=_root[keys[i]];
        var managerApi:Object=StageManager;port(managerApi,"instance",null);
        var sceneApi:Object=SceneManager;port(sceneApi,"instance",null);
        var waveApi:Object=WaveSpawner;port(waveApi,"instance",null);var wheelApi:Object=WaveSpawnWheel;port(wheelApi,"instance",null);
        var vehicleApi:Object=Cf6VehicleService;port(vehicleApi,"begin",vehicleBegin);port(vehicleApi,"tick",vehicleTick);port(vehicleApi,"dispose",vehicleDispose);
        var mechanismApi:Object=Cf6MapMechanism;port(mechanismApi,"loadLayers",function(s:Object,layers:Array):Void {s.layers=[];s.pending=0;});
        var cameraApi:Object=org.flashNight.arki.camera.HorizontalScroller;
        port(cameraApi,"pushFocus",function():Object {var h:Object={};_root.__cf6MapCameraOwner=h;return h;});
        port(cameraApi,"setFocusViewport",function():Boolean {return true;});
        port(cameraApi,"releaseFocus",function(h:Object):Boolean {if(h==undefined || _root.__cf6MapCameraOwner!==h)return false;_root.__cf6MapCameraOwner=null;return true;});
        var saveApi:Object=org.flashNight.neur.Server.SaveManager;
        port(saveApi,"getInstance",function():Object {return {hasRewardCommitPending:function():Boolean {return false;},isRecoveryPending:function():Boolean {return false;},isRepairPending:function():Boolean {return false;}};});
        var runApi:Object=StageRunSession;port(runApi,"_run",null);port(runApi,"_returnRequested",false);port(runApi,"pushState",noop);
        port(runApi,"hasPersistedSettlementPending",function():Boolean {return false;});
        var lootApi:Object=org.flashNight.arki.item.LootContainerService;port(lootApi,"hasStageSettlementPending",function():Boolean {return false;});
        var returnApi:Object=StageReturnFlow;port(returnApi,"canBeginSceneLoad",function():Boolean {return true;});
        var bridgeApi:Object=PlayerResourceTransferBridge;port(bridgeApi,"recordAdmittedDoor",function():Boolean {_root.__cf6MapBridgeCount++;return _root.__cf6MapMode!="bridge-refuse";});
        _root.发布消息=noop;_root.存档系统={};_root.场景转换中=false;_root.server={isSocketConnected:false};
        trace("CF6VehicleMapEvidence: actual MapMechanism/StageManager/WaveSpawner; mocked vehicle/loader/camera/persistence-query/fade ports; no live game claim");
        try {emptyWave();singleTail();lifeCase(false);lifeCase(true);foreignPause("pause-before-tail");foreignPause("pause-on-clear");unknownAndReplacement();}
        catch(error){check(false,"exception "+error);}
        finally {
            cleanup();
            for(i=ports.length-1;i>=0;i--)ports[i].api[ports[i].key]=ports[i].value;
            for(i=0;i<keys.length;i++)_root[keys[i]]=saved[keys[i]];
        }
        trace("Cf6VehicleMapIntegrationTest Tests Passed: "+passed);trace("Cf6VehicleMapIntegrationTest Tests Failed: "+failed);
    }
}