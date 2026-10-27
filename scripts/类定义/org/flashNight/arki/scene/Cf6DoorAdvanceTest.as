import org.flashNight.arki.scene.*;
import org.flashNight.arki.pause.PauseManager;

/** Real StageManager method with controlled in-memory fade/save-query seams; never jumps or writes a save. */
class org.flashNight.arki.scene.Cf6DoorAdvanceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean,label:String):Void {
        if(value) passed++;else {failed++;trace("[FAIL] Cf6DoorAdvance: "+label);}
    }
    private static function fixture(mode:String,preserve:Boolean):Object {
        Cf6MapMechanism.teardown();
        if(_root.gameworld._name=="__cf6AdvanceFixture") _root.gameworld.removeMovieClip();
        if(_root.__cf6AdvancePeer!=undefined) PauseManager.releaseLease(_root.__cf6AdvancePeer);
        _root.__cf6AdvancePeer=undefined;_root.暂停=false;_root.__cf6AdvanceMode=mode;
        _root.__cf6AdvanceRecords=0;_root.__cf6AdvanceCalls=0;_root.__cf6AdvanceBridgeRecords=0;
        _root.savePath="cf6.advance.fixture";_root.当前关卡名="书中历险-毒刺行动";_root.控制目标="hero";
        _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"historical",outcome:"active",slot:"cf6.advance.fixture",seed:123,startedAt:1792550000000}};
        var w:MovieClip=_root.createEmptyMovieClip("__cf6AdvanceFixture",_root.getNextHighestDepth());_root.gameworld=w;
        w.createEmptyMovieClip("效果",20);
        var h:MovieClip=w.createEmptyMovieClip("hero",10);h.hp=100;h._x=11;h._y=h.Z轴坐标=20;h.方向="右";h.攻击模式="长枪";
        // Production traversal freezes the native gun upper-body clip by label.
        h.createEmptyMovieClip("man",1);
        h.状态改变=function(value:String):Void {this.状态=value;};h.方向改变=function(value:String):Void {this.方向=value;};
        var manager:Object={isActive:true,isCleared:false,isFailed:false,isFinished:false,currentStage:0,stageMode:"infinite",stageInfoList:[{},{}],gameworld:w};
        var managerClass:Object=org.flashNight.arki.scene.StageManager;managerClass.instance=manager;
        manager.requestCf6DoorAdvance=managerClass.prototype.requestCf6DoorAdvance;
        manager.clearStage=function():Void {
            if(org.flashNight.arki.scene.Cf6MapMechanism.interceptClear(this,this.gameworld)) return;
            this.isCleared=true;this.gameworld.允许通行=true;
            if(_root.__cf6AdvanceMode=="peer") _root.__cf6AdvancePeer=org.flashNight.arki.pause.PauseManager.lease(true,"dialogue");
        };
        _root.转场景记录数据=function():Void {
            _root.__cf6AdvanceRecords++;
            if(_root.__cf6AdvanceMode=="record-replaces") {
                var api:Object=org.flashNight.arki.scene.StageManager;api.instance={};
            }
            if(_root.__cf6AdvanceMode=="record-opens-pause")
                _root.__cf6AdvancePeer=org.flashNight.arki.pause.PauseManager.lease(true,"dialogue");
            if(_root.__cf6AdvanceMode=="record-fails-stage") {
                var managerApi:Object=org.flashNight.arki.scene.StageManager;managerApi.instance.isFailed=true;
            }
        };
        _root.淡出动画={__transitionProjectionIdentity:{},__returnFadeActive:mode=="busy-fade",跳转中标签:mode=="busy-tag"};
        _root.淡出动画.淡出跳转帧=function(frame:String) {
            _root.__cf6AdvanceCalls++;
            if(_root.__cf6AdvanceMode=="throw") throw new Error("fixture fade throw");
            if(_root.__cf6AdvanceMode=="false") return false;
            if(_root.__cf6AdvanceMode=="undefined") return undefined;
            this.__returnFadeActive=true;this.跳转帧=frame;this.__stageReturnToken=undefined;
            if(_root.__cf6AdvanceMode!="true-no-new") this.__transitionProjectionIdentity={};
            if(_root.__cf6AdvanceMode=="true-wrong-target") this.跳转帧="基地地图";
            if(_root.__cf6AdvanceMode=="true-wrong-token") this.__stageReturnToken="foreign";
            if(_root.__cf6AdvanceMode=="true-array") this.__transitionProjectionIdentity=[];
            if(_root.__cf6AdvanceMode=="true-replaces") {
                var api:Object=org.flashNight.arki.scene.StageManager;api.instance={};
            }
            return true;
        };
        var path:Object={mode:"depart",fps:30,durationFrames:2,preserveActorPosition:preserve,
            gate:{x:10,z:20,radius:12},exit:{x:80,z:30},samples:[
            {frame:1,x:10,z:20,visible:true,action:"stand"},
            {frame:2,x:20,z:5,visible:false,action:"stand"}]};
        var identity:Object=StageReturnFlow.worldIdentity(w);
        Cf6MapMechanism.beginRoom(w,identity,"A03",{kind:"door",layers:[],traversal:{depart:path}});Cf6MapMechanism.tick();
        return {world:w,hero:h,manager:manager,owner:identity,room:w.__cf6Mechanism};
    }
    private static function complete(f:Object):Void {
        f.manager.clearStage();Cf6MapMechanism.tick();Cf6MapMechanism.tick();
    }
    private static function testAccepted():Void {
        var f:Object=fixture("true",false);
        check(f.manager.requestCf6DoorAdvance(f.world,f.owner,0)=="rejected" && _root.__cf6AdvanceCalls==0,"no fabricated clear or premature departure");
        complete(f);
        check(f.room.advanceReceipt.status=="accepted" && _root.__cf6AdvanceRecords==1 && _root.__cf6AdvanceCalls==1,"exact cleared choreography invokes standard fade once");
        check(_root.__cf6AdvanceBridgeRecords==1,"only explicitly admitted fresh fade registers HP/MP transfer intent once");
        check(f.hero._x==20 && f.hero.Z轴坐标==5 && !f.hero._visible && f.room.departure.acquired && f.world.允许通行===false,"accepted handoff keeps final doorway pose and blocks duplicate legacy gate");
        check(f.manager.requestCf6DoorAdvance(f.world,f.owner,0)=="rejected" && _root.__cf6AdvanceCalls==1 && _root.__cf6AdvanceBridgeRecords==1,"duplicate exact request is rejected without replay");
        check(f.manager.currentStage==0 && f.manager.isCleared,"handoff does not increment stage or replace real clear");
        _root.淡出动画.__returnFadeActive=false;Cf6MapMechanism.tick();
        check(f.hero._visible && f.hero._x==80 && f.world.允许通行===false && !_root.暂停,"failed presentation returns only owned display/control and keeps navigation locked");
    }
    private static function testResults():Void {
        var modes:Array=["false","undefined","true-no-new","throw","query-bad","record-replaces","true-wrong-target","true-wrong-token","true-array","true-replaces","record-opens-pause","record-fails-stage"];
        for(var i:Number=0;i<modes.length;i++) {
            var f:Object=fixture(modes[i],false);complete(f);
            var status:String=modes[i]=="false" ? "rejected" : "unknown";
            check(f.room.advanceReceipt.status==status,modes[i]+" retains exact request outcome");
            check(_root.__cf6AdvanceBridgeRecords==0,modes[i]+" rejected or unknown fade cannot register a transfer intent");
            check(f.hero._visible && !f.room.departure.acquired && (modes[i]=="record-replaces" || modes[i]=="true-replaces" || f.world.允许通行===(modes[i]=="false")),modes[i]+" restores own actor; only definite admitted rejection permits standard manual gate");
            var count:Number=_root.__cf6AdvanceCalls;Cf6MapMechanism.tick();f.manager.requestCf6DoorAdvance(f.world,f.owner,0);
            check(_root.__cf6AdvanceCalls==count,modes[i]+" is never automatically replayed");
        }
    }
    private static function testGuards():Void {
        var modes:Array=["peer","reward","persisted","can-begin","busy-fade","busy-tag"];
        for(var i:Number=0;i<modes.length;i++) {
            var f:Object=fixture(modes[i],false);complete(f);
            check(f.room.advanceReceipt.status=="rejected" && _root.__cf6AdvanceRecords==0 && _root.__cf6AdvanceCalls==0,modes[i]+" blocks before memory transfer and fade");
            check(_root.__cf6AdvanceBridgeRecords==0,modes[i]+" admission guard cannot register a transfer intent");
            check(f.world.允许通行===false && (modes[i]!="peer" || _root.暂停===true),modes[i]+" does not bypass external owner or unknown-write fence");
        }
        var preserve:Object=fixture("true",true);complete(preserve);
        check(preserve.hero._x==11 && preserve.hero.Z轴坐标==20,"1430 stationary adaptation preserves actual approach foot point");
        var old:Object=preserve.room;var world:MovieClip=preserve.world;
        world.removeMovieClip();var replacement:MovieClip=_root.createEmptyMovieClip("__cf6AdvanceFixture",_root.getNextHighestDepth());
        _root.gameworld=replacement;replacement.__stageReturnWorldIdentity={};replacement.允许通行=true;
        Cf6MapMechanism.tick();check(replacement.允许通行===true && !_root.暂停,"accepted old scene cancellation never writes replacement gate");
    }
    private static function testBridgeRefusal():Void {
        var f:Object=fixture("bridge-refuse",false);complete(f);
        check(_root.__cf6AdvanceCalls==1 && _root.__cf6AdvanceBridgeRecords==1 && f.room.advanceReceipt.status=="unknown",
            "post-fade transfer registration refusal is unknown, never definite non-execution");
        check(f.world.允许通行===false && f.hero._visible && !f.room.departure.acquired,
            "registration refusal restores owned actor while retaining the unknown navigation fence");
        Cf6MapMechanism.tick();f.manager.requestCf6DoorAdvance(f.world,f.owner,0);
        check(_root.__cf6AdvanceCalls==1 && _root.__cf6AdvanceBridgeRecords==1,
            "registration refusal cannot automatically replay fade or transfer registration");
    }
    public static function runAllTests():Void {
        passed=0;failed=0;PauseManager.install();
        var keys:Array=["gameworld","控制目标","savePath","当前关卡名","_saveExt","暂停","淡出动画","转场景记录数据","场景进入位置名","发布消息","__cf6AdvanceMode","__cf6AdvanceRecords","__cf6AdvanceCalls","__cf6AdvancePeer","__cf6AdvanceBridgeRecords"];
        var saved:Object={};for(var i:Number=0;i<keys.length;i++) saved[keys[i]]=_root[keys[i]];
        var managerClass:Object=org.flashNight.arki.scene.StageManager,oldManager=managerClass.instance;
        var saveClass:Object=org.flashNight.neur.Server.SaveManager,oldSave=saveClass.getInstance;
        var runClass:Object=org.flashNight.arki.scene.StageRunSession,oldPending=runClass.hasPersistedSettlementPending;
        var lootClass:Object=org.flashNight.arki.item.LootContainerService,oldLoot=lootClass.hasStageSettlementPending;
        var returnClass:Object=org.flashNight.arki.scene.StageReturnFlow,oldCan=returnClass.canBeginSceneLoad;
        var targets:Object=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager,oldHero=targets.findHero;
        var bridge:Object=PlayerSceneLifecycle;var oldRecord:Function=bridge.recordAdmittedDoor;
        bridge.recordAdmittedDoor=function(frame:String):Boolean {
            _root.__cf6AdvanceBridgeRecords++;
            if(_root.__cf6AdvanceMode=="bridge-refuse") return false;
            return oldRecord.call(this,frame);
        };
        saveClass.getInstance=function():Object {return {
            hasRewardCommitPending:function(){return _root.__cf6AdvanceMode=="query-bad" ? undefined : _root.__cf6AdvanceMode=="reward";},
            isRecoveryPending:function():Boolean {return false;},isRepairPending:function():Boolean {return false;}};};
        runClass.hasPersistedSettlementPending=function():Boolean {return _root.__cf6AdvanceMode=="persisted";};
        lootClass.hasStageSettlementPending=function():Boolean {return false;};
        returnClass.canBeginSceneLoad=function():Boolean {return _root.__cf6AdvanceMode!="can-begin";};
        targets.findHero=function():MovieClip {return _root.gameworld.hero;};
        _root.发布消息=function(message:String):Void {};
        try {testAccepted();testResults();testGuards();testBridgeRefusal();}
        finally {
            Cf6MapMechanism.teardown();if(_root.__cf6AdvancePeer!=undefined) PauseManager.releaseLease(_root.__cf6AdvancePeer);
            if(_root.gameworld._name=="__cf6AdvanceFixture") _root.gameworld.removeMovieClip();
            managerClass.instance=oldManager;saveClass.getInstance=oldSave;runClass.hasPersistedSettlementPending=oldPending;
            lootClass.hasStageSettlementPending=oldLoot;returnClass.canBeginSceneLoad=oldCan;targets.findHero=oldHero;bridge.recordAdmittedDoor=oldRecord;
            for(i=0;i<keys.length;i++) _root[keys[i]]=saved[keys[i]];
        }
        trace("Cf6DoorAdvanceTest Tests Passed: "+passed);
        trace("Cf6DoorAdvanceTest Tests Failed: "+failed);
    }
}
