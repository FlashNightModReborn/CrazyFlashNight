import org.flashNight.arki.scene.StageIntroService;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.scene.BookComicService;
import org.flashNight.arki.scene.BookDefinition;
import org.flashNight.arki.ui.SceneTransitionService;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.neur.Event.EventDispatcher;

/** Real AVM1 identity and permission tests; never opens a player SharedObject. */
class org.flashNight.arki.scene.StageIntroServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var starts:Number;
    private static var continues:Number;
    private static function check(value:Boolean, label:String):Void {
        if(value) passed++; else { failed++; trace("[StageIntro FAIL] " + label); }
    }
    private static function descriptor():Object {
        return {kind:"book_chapter",bookId:"repair-campus",chapter:0,pageId:"prologue",bgmLease:false};
    }
    private static function fixture(capable:Boolean, bookId:String, index:Number, routeId:String):Object {
        if(bookId==undefined)bookId="repair-campus";if(index==undefined)index=0;
        StageIntroService.retire(); BookComicService.onTransportDisconnected(); SceneTransitionService.clear();
        if(_root.gameworld != undefined) _root.gameworld.removeMovieClip();
        _root.gameworld=undefined;
        _root.savePath="cf7_agent_stage_intro_fixture";
        _root._saveExt={bookRun:{bookId:bookId,slot:_root.savePath,outcome:"active",seed:17,startedAt:100,debug:true}};
        if(bookId=="cf6-sting") {
            _root._saveExt.bookRun.routeId=routeId;
            var maps:Array=[];for(var m:Number=0;m<21;m++)maps.push({dialogue:[]});
            var def:Object=BookDefinition;
            def[routeId=="type61"?"_type61":"_cf6"]={id:bookId,stageName:"书中历险-毒刺行动",maps:maps,chapterIntros:[{chapter:1,pageId:"cf6-s1",bgmLease:true},{chapter:2,pageId:"cf6-s2",bgmLease:true},{chapter:3,pageId:"cf6-s3",bgmLease:true},{chapter:7,pageId:"cf6-s4",bgmLease:true},{chapter:8,pageId:"cf6-s5",bgmLease:true},{chapter:18,pageId:"cf6-s6",bgmLease:true}]};
        }
        _root.当前关卡名=BookDefinition.get().stageName;
        _root.加载背景列表={本次背景:"Andy"}; _root.初期关卡列表=[];
        _root.淡出动画={_currentframe:5,play:function():Void {},stop:function():Void {}};
        SceneTransitionService.sendOverride=function(p:Object):Boolean {return true;};
        SceneTransitionService.begin(_root.淡出动画);
        var transition:Object=SceneTransitionService;
        var s:Object=transition._session;
        SceneTransitionService.presented({requestId:s.requestId,revision:s.revision,kind:"covered",introVersion:capable?1:0});
        var world:MovieClip=_root.createEmptyMovieClip("__stageIntroWorld",9288);
        _root.gameworld=world; world.__stageReturnWorldIdentity={}; world.dispatcher=new EventDispatcher();
        _root.server={isSocketConnected:true,
            sendTaskWithCallback:function(task:String,p:Object,extra:Object,callback:Function):Void {_root.__introOpen=p.initData;},
            sendTaskToNode:function(task:String,p:Object):Boolean {_root.__introReply=p;return true;},
            sendServerMessage:function(message:String):Void {}};
        PauseManager.set(false,"manual");
        StageIntroService.declare(world,org.flashNight.arki.scene.BookRunRules.chapterIntro(BookDefinition.get(),index));
        return StageIntroService.active();
    }
    private static function gate(scope:Object):Object {
        return {manager:{onPlayerReady:function(p:Object):Void {starts++;}},world:scope.owner};
    }
    private static function receipt(scope:Object,kind:String):Object {
        return {kind:kind,introId:scope.id,requestId:scope.requestId,revision:scope.wireRevision};
    }
    private static function testPermission():Void {
        check(fixture(false)==null,"old Host keeps the complete legacy contract");
        var s:Object=fixture(true);
        check(s!=null && _root.gameworld.__stageIntroExecutionHeld===true,"supported declared intro holds execution");
        check(_root.暂停===false,"intro does not acquire an ordinary pause lease");
        var foundFlag:Boolean=false;var member:String;
        for(member in _root.gameworld)if(member=="__stageIntroExecutionHeld")foundFlag=true;
        check(!foundFlag,"permission flag cannot enter legacy world-unit enumeration");
        check(s.owner!==s.world,"world identity is an independent ordinary object");
        starts=0;var p:Object=gate(s);
        check(StageIntroService.deferStart(p) && starts==0,"player readiness stores pending Start");
        check(org.flashNight.arki.unit.UnitAI.core.AIEnvironment.isPaused(),"AI consumes execution permission without changing root pause");
        var empty:Object=org.flashNight.arki.component.Damage.DamageCalculator.calculateDamage({},null,{},1,"未躲闪");
        check(empty===org.flashNight.arki.component.Damage.DamageResult.NULL,"damage rejected before any manager or target mutation");
        s.state="narrative";
        StageIntroService.completeNarrative(s);
        check(starts==0 && _root.gameworld.__stageIntroExecutionHeld===true,"narrative completion alone cannot start combat");
        var wrong:Object=receipt(s,"intro_surface");wrong.introId="intro:foreign";
        StageIntroService.handleReceipt(wrong);
        check(starts==0,"foreign surface receipt cannot grant execution");
        wrong=receipt(s,"intro_surface");wrong.revision--;
        StageIntroService.handleReceipt(wrong);
        check(starts==0,"old revision cannot grant execution");
        StageIntroService.handleReceipt(receipt(s,"intro_surface"));
        check(starts==1 && _root.gameworld.__stageIntroExecutionHeld===false,"both responsibilities grant pending Start once");
        StageIntroService.handleReceipt(receipt(s,"intro_surface"));StageIntroService.completeNarrative(s);
        check(starts==1 && !StageIntroService.deferStart(p),"duplicate terminal and surface receipts do not restart");
    }
    private static function testFailure():Void {
        var s:Object=fixture(true);s.state="opening";continues=0;
        check(BookComicService.begin("prologue",function():Void {continues++;},StageIntroService.interruption(s)),"pilot comic uses existing business opener");
        var data:Object=_root.__introOpen;
        check(data.v===2 && data.introId===s.id,"open carries the exact protected handoff identity");
        var p:Object={v:1,callId:12,presentationId:data.presentationId,slot:data.slot,sceneId:data.sceneId,
            pageId:data.pageId,panelInstanceId:"intro.fixture.1",reason:"failed"};
        BookComicService.handle("finish",p);
        check(continues==0 && s.state=="failed","decode failure interrupts instead of completing the story");
        check(_root.gameworld.__stageIntroExecutionHeld===true,"failed comic keeps the outer execution responsibility");
        StageIntroService.handleReceipt(receipt(s,"intro_surface"));
        check(s.surfaceReady!==true,"late surface readiness cannot override failed narrative");
        StageIntroService.handleReceipt(receipt(s,"intro_retry"));
        check(s.state=="opening" && _root.gameworld.__stageIntroExecutionHeld===true,"retry retains execution protection");
    }
    private static function testWorldRetirement():Void {
        var s:Object=fixture(true);s.state="narrative";starts=0;StageIntroService.deferStart(gate(s));
        StageIntroService.completeNarrative(s);
        var oldIdentity:Object=s.owner;
        _root.gameworld.removeMovieClip();
        var replacement:MovieClip=_root.createEmptyMovieClip("__stageIntroWorld",9288);
        _root.gameworld=replacement;replacement.__stageReturnWorldIdentity={};replacement.__stageIntroExecutionHeld=true;
        check(oldIdentity!==StageReturnFlow.worldIdentity(replacement),"same path MovieClip replacement has a fresh ordinary identity");
        StageIntroService.handleReceipt(receipt(s,"intro_surface"));
        check(starts==0 && StageIntroService.active()==null,"old completion cannot start the replacement world");
        StageIntroService.retire();
        check(replacement.__stageIntroExecutionHeld===true,"retiring old reference cannot clear a replacement hold");
    }
    private static function testAllOpenings():Void {
        var books:Array=["repair-campus","cf6-sting","cf6-sting"], routes:Array=[undefined,"historical","type61"];
        for(var b:Number=0;b<books.length;b++) {
            var indices:Array=b==0?[0,6]:[1,2,3,7,8,18];
            for(var j:Number=0;j<indices.length;j++) {
                var s:Object=fixture(true,books[b],indices[j],routes[b]);
                var plan:Object=org.flashNight.arki.scene.BookRunRules.chapterIntro(BookDefinition.get(),indices[j]);
                check(s!=null && s.chapter===indices[j] && s.pageId===plan.pageId,"all opening declarations enter one held scope "+b+":"+indices[j]);
                _root._saveExt.bookRun=org.flashNight.gesh.object.PersistedSnapshot.clone(_root._saveExt.bookRun);
                check(StageIntroService.active()===s,"legitimate detached run snapshot retains exact scope "+b+":"+indices[j]);
                starts=0;StageIntroService.deferStart(gate(s));s.state="opening";
                check(!StageIntroService.canPresentChapter(indices[j]+1),"foreign chapter cannot take this opening's scope "+b+":"+indices[j]);
                StageIntroService.prepared(s);
                StageIntroService.completeNarrative(s);
                check(starts==0 && s.world.__stageIntroExecutionHeld===true,"narrative alone never starts any opening "+b+":"+indices[j]);
                StageIntroService.handleReceipt(receipt(s,"intro_surface"));StageIntroService.completeNarrative(s);
                check(starts==1 && s.world.__stageIntroExecutionHeld===false,"every opening resumes exactly once "+b+":"+indices[j]);
                org.flashNight.neur.Event.EventBus.getInstance().publish("SceneTransitionReleased",s.world,"",s.owner);
                check(s.state=="complete" && starts==1,"duplicate timeline release cannot reopen a completed opening "+b+":"+indices[j]);
            }
        }
    }
    private static function testExecutionClock():Void {
        var s:Object=fixture(true),api:Object=org.flashNight.arki.scene.StageRunSession;
        var savedRun:Object=api._run,savedReturn:Boolean=api._returnRequested;
        try {
            api._run={activeFrames:12,outcome:"active"};api._returnRequested=false;
            for(var i:Number=0;i<300;i++)org.flashNight.arki.scene.StageRunSession.tick();
            check(api._run.activeFrames==12,"authoritative report clock rejects every held frame");
            org.flashNight.arki.scene.StageRunSession.finish("victory");
            check(api._run.outcome=="active","held opening cannot turn a direct victory callback into a report or reward");
            _root.gameworld.__combatAdmitted=false;
            s.state="narrative";StageIntroService.completeNarrative(s);StageIntroService.handleReceipt(receipt(s,"intro_surface"));
            for(i=0;i<60;i++)org.flashNight.arki.scene.StageRunSession.tick();
            check(api._run.activeFrames==12,"report clock remains held while CF6 __combatAdmitted is false");
            org.flashNight.arki.scene.StageRunSession.finish("victory");
            check(api._run.outcome=="active","CF6 entry hold rejects victory before __combatAdmitted");
            _root.gameworld.__combatAdmitted=true;
            org.flashNight.arki.scene.StageRunSession.tick();
            check(api._run.activeFrames==13,"report clock resumes on the first granted gameplay frame");
            _root.gameworld.__combatAdmitted=false;
            org.flashNight.arki.scene.StageRunSession.finish("failure");
            check(api._run.outcome=="failure","failure remains reachable while __combatAdmitted is false");
        } finally {api._run=savedRun;api._returnRequested=savedReturn;}
    }
    private static function testRunAndDeclarationBoundaries():Void {
        var s:Object=fixture(true);starts=0;StageIntroService.deferStart(gate(s));s.state="narrative";
        var nextRun:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(_root._saveExt.bookRun);
        nextRun.startedAt++;_root._saveExt.bookRun=nextRun;
        StageIntroService.completeNarrative(s);StageIntroService.handleReceipt(receipt(s,"intro_surface"));
        check(starts==0 && s.narrativeDone===false,"another run cannot consume the old narrative or surface receipt");
        check(StageIntroService.active()==null,"run tuple change retires current-scope admission");
        s=fixture(true);StageIntroService.retire();
        var wrong:Object=descriptor();wrong.pageId="boss";StageIntroService.declare(_root.gameworld,wrong);
        check(StageIntroService.active()==null && _root.gameworld.__stageIntroExecutionHeld!==true,"page must match the configured chapter declaration");
        wrong=descriptor();wrong.bgmLease=true;StageIntroService.declare(_root.gameworld,wrong);
        check(StageIntroService.active()==null,"BGM policy cannot be forged by the stage descriptor");
    }
    private static function testCf6CombatAdmissionMatrix():Void {
        var manager:org.flashNight.arki.scene.StageManager=org.flashNight.arki.scene.StageManager.getInstance();
        var stageMock:Object=manager;
        var bridge:Object=org.flashNight.arki.scene.PlayerSceneLifecycle;
        var savedIsReady:Function=bridge.isReady;
        var savedGameworld:MovieClip=manager.gameworld,savedStage:Number=manager.currentStage;
        var savedActive=manager.isActive,savedFinished=manager.isFinished,savedFailed=manager.isFailed;
        var savedSpawner=stageMock.spawner,savedInfo=stageMock.currentStageInfo,savedAdmission=stageMock.combatAdmission;
        var s:Object=fixture(true,"cf6-sting",1,"historical");
        var world:MovieClip=s.world;
        var startCount:Number=0,waveCount:Number=0;
        world.dispatcher.subscribe("Start",function():Void {startCount++;},null);
        try {
            manager.gameworld=world;manager.currentStage=0;
            manager.isActive=true;manager.isFinished=false;manager.isFailed=false;
            stageMock.currentStageInfo={waveInfo:[{}],basicInfo:{Cf6MapId:"A01",Cf6ChapterIndex:1}};
            stageMock.spawner={init:function():Void {waveCount++;}};
            var admission:Object=manager.beginCombatAdmission(world,1,"A01");
            var enumerated:Boolean=false;
            for(var k:String in world) if(k=="__combatAdmitted") enumerated=true;
            check(admission!=null && world.__combatAdmitted===false && !enumerated,
                "CF6 combatAdmission initializes non-enumerable __combatAdmitted=false");
            var g:Object={manager:manager,world:s.owner,stage:0,published:true};
            bridge.isReady=function(candidate:Object):Boolean {return candidate===g && _root.gameworld===world;};
            manager.onPlayerReady(g);
            check(startCount==0 && waveCount==0 && world.__combatAdmitted===false && s.playerGate===g,
                "onPlayerReady records pending gate on both combatAdmission and StageIntroService");
            manager.noteCurtainReleased(world,s.owner);
            s.state="narrative";
            StageIntroService.completeNarrative(s);
            StageIntroService.handleReceipt(receipt(s,"intro_surface"));
            check(world.__stageIntroExecutionHeld===false && world.__combatAdmitted===false
                && startCount==0 && waveCount==0,
                "tryGrant releases only NarrativeHold while roomReady is still false");
            manager.noteRoomReady(world,s.owner,"A01");
            check(world.__combatAdmitted===true && startCount==1 && waveCount==1,
                "roomReady completes CF6 admission and dispatches Start + waves once");
            manager.noteRoomReady(world,s.owner,"A01");
            manager.noteNarrativeDone(world,s.owner,1);
            manager.noteCurtainReleased(world,s.owner);
            manager.onPlayerReady(g);
            check(startCount==1 && waveCount==1,"duplicate completion notifications remain idempotent");

            // Start callback replacing world prevents spawner.init
            StageIntroService.retire();
            var world2:MovieClip=_root.createEmptyMovieClip("__stageIntroWorld2",9289);
            _root.gameworld=world2;world2.__stageReturnWorldIdentity={};
            world2.dispatcher=new EventDispatcher();
            var startCount2:Number=0,waveCount2:Number=0;
            world2.dispatcher.subscribe("Start",function():Void {
                startCount2++;
                var world3:MovieClip=_root.createEmptyMovieClip("__stageIntroWorld3",9291);
                _root.gameworld=world3;world3.__stageReturnWorldIdentity={};
            },null);
            manager.gameworld=world2;manager.currentStage=1;
            var admission2:Object=manager.beginCombatAdmission(world2,2,"A02");
            var g2:Object={manager:manager,world:world2.__stageReturnWorldIdentity,stage:1,published:true};
            bridge.isReady=function(candidate:Object):Boolean {
                return candidate===g2 && _root.gameworld===world2 && manager.gameworld===world2;
            };
            stageMock.spawner={init:function():Void {waveCount2++;}};
            manager.noteCurtainReleased(world2,world2.__stageReturnWorldIdentity);
            manager.noteNarrativeDone(world2,world2.__stageReturnWorldIdentity,2);
            manager.noteRoomReady(world2,world2.__stageReturnWorldIdentity,"A02");
            manager.onPlayerReady(g2);
            check(startCount2==1 && waveCount2==0 && world2.__combatAdmitted===false && admission2.failed===true,
                "Start callback world replacement permanently marks admission failed and revokes combat admission");
            if(_root.gameworld!=undefined && _root.gameworld!==world && _root.gameworld!==world2) _root.gameworld.removeMovieClip();
            _root.gameworld=world2;
            manager.noteRoomReady(world2,world2.__stageReturnWorldIdentity,"A02");
            manager.onPlayerReady(g2);
            check(waveCount2==0 && world2.__combatAdmitted===false,
                "restoring old world after Start replacement cannot re-admit or call spawner.init");
            world2.__stageReturnWorldIdentity={};
            var replacement:Object=manager.beginCombatAdmission(world2,2,"A02");
            world2.__combatAdmitted=true;
            stageMock.revokeCombatAdmission(admission2);
            check(world2.__combatAdmitted===true && replacement.failed===false,
                "retired record cannot revoke a new owner on the same native MovieClip handle");
            stageMock.revokeCombatAdmission(replacement);
            check(world2.__combatAdmitted===false && replacement.failed===true,
                "current exact record still revokes its own native world");
            world2.removeMovieClip();
        } finally {
            bridge.isReady=savedIsReady;
            manager.gameworld=savedGameworld;manager.currentStage=savedStage;
            manager.isActive=savedActive;manager.isFinished=savedFinished;manager.isFailed=savedFailed;
            stageMock.spawner=savedSpawner;stageMock.currentStageInfo=savedInfo;
            stageMock.combatAdmission=savedAdmission;
        }
    }
    public static function runAllTests():Void {
        passed=0;failed=0;
        var keys:Array=["gameworld","server","savePath","_saveExt","暂停","当前关卡名","淡出动画","加载背景列表","初期关卡列表","__introOpen","__introReply"];
        var definition:Object=BookDefinition,savedCf6:Object=definition._cf6,savedType61:Object=definition._type61;
        var saved:Object={};for(var i:Number=0;i<keys.length;i++)saved[keys[i]]=_root[keys[i]];
        _root.gameworld=undefined;
        try {testPermission();testFailure();testWorldRetirement();testAllOpenings();testExecutionClock();testRunAndDeclarationBoundaries();testCf6CombatAdmissionMatrix();}
        finally {
            definition._cf6=savedCf6;definition._type61=savedType61;
            StageIntroService.retire();BookComicService.onTransportDisconnected();SceneTransitionService.clear();
            _root.gameworld.removeMovieClip();SceneTransitionService.sendOverride=null;
            for(i=0;i<keys.length;i++)_root[keys[i]]=saved[keys[i]];
        }
        trace("StageIntroServiceTest Tests Passed: "+passed);
        trace("StageIntroServiceTest Tests Failed: "+failed);
    }
}
