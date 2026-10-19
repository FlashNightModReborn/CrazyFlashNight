import org.flashNight.arki.ui.SceneTransitionService;
import org.flashNight.arki.camera.HorizontalScroller;
import org.flashNight.neur.Event.EventBus;
class org.flashNight.arki.ui.SceneTransitionServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var sent:Array;
    private static var counters:Object;
    private static var released:Array;
    private static var calibrationReleases:Array;
    private static var ordinaryReadyCount:Number;
    private static function onReleased(world:Object,token:String,identity:Object):Void {
        released.push({world:world,identity:identity});
    }
    private static function check(ok:Boolean,label:String):Void {
        if (ok) passed++; else {failed++; trace("[SceneTransition FAIL] "+label);}
    }
    private static var cameraHolder:MovieClip;
    private static var cameraSequence:Number;
    private static function cameraWorld(token:String, commit:Boolean):MovieClip {
        var w:MovieClip=cameraHolder.createEmptyMovieClip("world"+(++cameraSequence),cameraSequence);
        _root.gameworld=w;
        w.__stageReturnWorldIdentity={};w.__stageReturnToken=token == undefined ? "" : token;
        w.背景长=2400;w.背景高=800;
        var hero:MovieClip=w.createEmptyMovieClip("hero",1);hero._x=1200;hero._y=400;
        _root.控制目标="hero";
        HorizontalScroller.onSceneChanged(w,w.__stageReturnToken,w.__stageReturnWorldIdentity);
        if(commit !== false) HorizontalScroller.update();
        return w;
    }
    private static function fixture(frame:Number):Object {
        counters = {plays:0,stops:0,retries:0,returns:0,jumps:0};
        return {_currentframe:frame,
            play:function():Void {counters.plays++;},stop:function():Void {counters.stops++;},
            gotoAndPlay:function(frame:Number):Void {counters.jumps++;counters.target=frame;this._currentframe=frame;},
            gotoAndStop:function(frame:Number):Void {this._currentframe=frame;if(frame==37)SceneTransitionService.failed(this);},
            淡出跳转帧:function(frame:String,token:String):Void {counters.retries++;}};
    }
    private static function testExternalSceneFrames():Void {
        var host:Object = {_currentframe:37,_saveExt:{bookRun:{}},savePath:"fixture"};
        check(org.flashNight.arki.scene.SceneTransitionGuard.observedSharedSceneFrame(host,"外部地图")==0,
            "unobserved external placement cannot grant direct mounting");
        org.flashNight.arki.scene.SceneTransitionGuard.rememberSharedSceneFrame(host,"地图-测试空间");
        check(host.__externalSceneFrame===37,"external initialization records its actual root frame");
        check(org.flashNight.arki.scene.SceneTransitionGuard.observedSharedSceneFrame(host,"外部地图")==37,
            "cleared external world can reuse its observed placement");
        host.gameworld={};
        check(org.flashNight.arki.scene.SceneTransitionGuard.observedSharedSceneFrame(host,"外部地图")==0,
            "live external world cannot grant duplicate mounting");
        host.gameworld=undefined; host._currentframe=51;
        org.flashNight.arki.scene.SceneTransitionGuard.rememberSharedSceneFrame(host,"基地场景-基地门口");
        check(host.__baseSceneFrame===51,"base initialization retains its own placement");
        check(host.__externalSceneFrame===37,"base initialization cannot replace the external placement");
        host._currentframe=61;
        org.flashNight.arki.scene.SceneTransitionGuard.rememberSharedSceneFrame(host,"wuxianguotu_1");
        check(host.__externalSceneFrame===37,"battle initialization cannot replace the external placement");
        check(org.flashNight.arki.scene.SceneTransitionGuard.observedSharedSceneFrame(host,"wuxianguotu_1")==0,
            "ordinary battle entry does not gain the Lee shortcut");
        host._saveExt.bookRun={bookId:"lee-trial",outcome:"active",slot:"fixture"};
        check(org.flashNight.arki.scene.SceneTransitionGuard.observedSharedSceneFrame(host,"wuxianguotu_1")==61,
            "active exact Lee slot retains its observed battle placement");
        host._saveExt.bookRun.slot="foreign";
        check(org.flashNight.arki.scene.SceneTransitionGuard.observedSharedSceneFrame(host,"wuxianguotu_1")==0,
            "foreign Lee slot cannot gain battle reentry");
        host.__externalSceneFrame=0;
        check(org.flashNight.arki.scene.SceneTransitionGuard.observedSharedSceneFrame(host,"外部地图")==0,
            "zero external placement is rejected");
        host.__externalSceneFrame="37";
        check(org.flashNight.arki.scene.SceneTransitionGuard.observedSharedSceneFrame(host,"外部地图")==0,
            "text external placement is rejected");
    }
    public static function runAllTests():Void {
        passed=0; failed=0; sent=[]; released=[];
        testExternalSceneFrames();
        EventBus.getInstance().subscribe("SceneTransitionReleased",onReleased,SceneTransitionServiceTest);
        var old:Object = {fade:_root.淡出动画,world:_root.gameworld,data:_root.加载背景列表,
            stages:_root.初期关卡列表,flag:_root.关卡标志,progress:_root.主线任务进度,
            returned:_root.从加载失败返回,entry:_root.场景进入位置名,
            saveExt:_root._saveExt,battle:_root.当前为战斗地图,
            transitioning:_root.场景转换中,calibration:_root.斗兽标定模式,
            cameraTimer:_root.帧计时器,cameraSky:_root.天空盒,cameraControl:_root.控制目标,
            cameraScale:_root.basicZoomScale,cameraToggle:_root.cameraZoomToggle,cameraParallax:_root.启用后景};
        cameraSequence=0;cameraHolder=_root.createEmptyMovieClip("__transitionCameraFixture",_root.getNextHighestDepth());
        _root.天空盒=cameraHolder.createEmptyMovieClip("sky",10000);_root.天空盒.地平线高度=240;
        _root.帧计时器={当前帧数:0,offsetTolerance:0};_root.basicZoomScale=1;_root.cameraZoomToggle=false;_root.启用后景=false;
        SceneTransitionService.sendOverride = function(p:Object):Boolean {sent.push(p); return true;};
        _root._saveExt=null; _root.当前为战斗地图=false;
        _root.场景转换中=false; _root.斗兽标定模式=false;
        _root.初期关卡列表=["stage"]; _root.关卡标志="base"; _root.主线任务进度=25;
        _root.加载背景列表={基地背景:["Andy","BLue"],关卡背景:["Blue",{Name:"黑铁众",Unlock:26}],本次背景:null};
        check(SceneTransitionService.backgroundList().length==2,"base backgrounds preserved");
        _root.关卡标志="stage";
        check(SceneTransitionService.backgroundList().length==1,"unlock equality remains locked");
        _root.主线任务进度=26;
        check(SceneTransitionService.backgroundList().length==2,"strict unlock admits later progress");
        _root.关卡标志="wuxianguotu_1";
        check(SceneTransitionService.backgroundList()[0]=="Blue","infinite battle list preserved");
        _root.加载背景列表.本次背景="黑铁众";
        check(SceneTransitionService.backgroundList()[0]=="黑铁众","explicit stage background wins");
        check(_root.加载背景列表.本次背景==null,"explicit override consumed once");
        check(SceneTransitionService.imageId("BLue")=="Blue","legacy case alias");
        check(SceneTransitionService.imageId("../save")=="Andy","unknown image uses bounded fallback");
        _root.加载背景列表=null;
        check(SceneTransitionService.backgroundList().length==10,"legacy default image count");
        var fade:Object=fixture(5); _root.淡出动画=fade;
        _root.gameworld=cameraWorld(undefined,true);
        SceneTransitionService.begin(fade); var cover:Object=sent[sent.length-1];
        check(cover.phase=="cover" && cover.revision==1,"common entry publishes cover");
        var beforeBegin:Number=sent.length;
        _root.加载背景列表={本次背景:"Blue"};
        SceneTransitionService.begin(fade);
        check(sent.length==beforeBegin,"common frame reuses the admitted pre-cover identity");
        check(_root.加载背景列表.本次背景=="Blue","common reentry does not consume another one-shot image");
        _root.加载背景列表=null;
        SceneTransitionService.awaitCovered(fade);
        check(counters.stops==1 && counters.plays==0,"no presentation receipt keeps cleanup blocked");
        SceneTransitionService.presented({requestId:"tr:foreign",revision:1,kind:"covered"});
        check(counters.plays==0,"foreign identity cannot release cleanup");
        SceneTransitionService.presented({requestId:cover.requestId,revision:100,kind:"covered"});
        check(counters.plays==0,"future revision cannot release cleanup");
        SceneTransitionService.presented({requestId:cover.requestId,revision:1.5,kind:"covered"});
        check(counters.plays==0,"fractional revision rejected");
        SceneTransitionService.presented({requestId:cover.requestId,revision:1,kind:"covered"});
        check(counters.plays==1,"valid curtain releases original timeline");
        fade._currentframe=6; SceneTransitionService.tick();
        SceneTransitionService.setTip(fade,"tip"); var loading:Object=sent[sent.length-1];
        check(loading.phase=="loading" && loading.imageId==cover.imageId,"image selection immutable during cleanup");
        check(org.flashNight.arki.scene.StageRunSession.getStageStartBlockReason()=="scene_transition",
            "legacy entry flag blocks first substage initialization");
        fade._currentframe=17; fade.__returnFadeActive=false;
        check(org.flashNight.arki.scene.StageRunSession.canStartStage(),
            "original frame-17 flag release permits the production stage admission gate");
        var projectionIdentity:Object=fade.__transitionProjectionIdentity;
        SceneTransitionService.tick();
        check(sent[sent.length-1].phase=="loading" && sent[sent.length-1].requestId==cover.requestId
            && fade.__transitionProjectionIdentity===projectionIdentity,
            "legacy admission release preserves the independent Web curtain identity");
        check(SceneTransitionService.isPresentationPending(),"report presentation stays blocked after frame-17 admission release");
        fade._currentframe=30; SceneTransitionService.awaitReveal(fade);
        check(sent[sent.length-1].phase=="loading","frame 30 does not manufacture SceneReady");
        EventBus.getInstance().publish("SceneReady",_root.gameworld,"",_root.gameworld.__stageReturnWorldIdentity);
        check(sent[sent.length-1].phase=="loading","old-world ready event rejected");
        _root.gameworld=cameraWorld(undefined,false);
        EventBus.getInstance().publish("SceneReady",_root.gameworld,"",{});
        check(sent[sent.length-1].phase=="loading","rebound world path with foreign ordinary identity rejected");
        EventBus.getInstance().publish("SceneReady",_root.gameworld,"",_root.gameworld.__stageReturnWorldIdentity);
        check(sent[sent.length-1].phase=="loading","Ready without initial camera pose stays covered");
        HorizontalScroller.update();SceneTransitionService.awaitReveal(fade);
        check(HorizontalScroller.hasInitialPose(_root.gameworld,_root.gameworld.__stageReturnWorldIdentity,
            HorizontalScroller.sceneScope(_root.gameworld,_root.gameworld.__stageReturnWorldIdentity)),"exact initial pose satisfies reveal fence");
        var reveal:Object=sent[sent.length-1];
        check(reveal.phase=="reveal","new-world ready requests Host capture fence");
        var before:Number=counters.plays;
        SceneTransitionService.presented({requestId:reveal.requestId,revision:reveal.revision-1,kind:"revealed"});
        check(counters.plays==before,"old reveal receipt cannot advance");
        var validReadyIdentity:Object=_root.gameworld.__stageReturnWorldIdentity;
        _root.gameworld.__stageReturnWorldIdentity={};
        SceneTransitionService.presented({requestId:reveal.requestId,revision:reveal.revision,kind:"revealed"});
        check(counters.plays==before,"late reveal cannot advance a rebound world with another ordinary identity");
        _root.gameworld.__stageReturnWorldIdentity=validReadyIdentity;
        SceneTransitionService.presented({requestId:reveal.requestId,revision:reveal.revision,kind:"revealed"});
        check(counters.plays==before+1,"exact reveal releases tail once");
        fade.__transitionProjectionIdentity={}; before=counters.plays;
        SceneTransitionService.presented({requestId:reveal.requestId,revision:reveal.revision,kind:"revealed"});
        check(counters.plays==before,"same-path replacement identity fences old callback");
        SceneTransitionService.clear();
        check(released.length==0,"foreign projection identity cannot publish a successful report handoff");
        fade=fixture(5); _root.淡出动画=fade;
        SceneTransitionService.begin(fade); cover=sent[sent.length-1];
        SceneTransitionService.presented({requestId:cover.requestId,revision:cover.revision,kind:"covered"});
        _root.gameworld=cameraWorld("return.token",true);
        fade._currentframe=30;
        EventBus.getInstance().publish("SceneReady",_root.gameworld,"return.token",_root.gameworld.__stageReturnWorldIdentity);
        reveal=sent[sent.length-1];
        SceneTransitionService.presented({requestId:reveal.requestId,revision:reveal.revision,kind:"revealed"});
        check(SceneTransitionService.isPresentationPending() && released.length==0,"successful reveal still keeps report behind the original tail");
        fade._currentframe=36; SceneTransitionService.tick();
        check(sent[sent.length-1].phase=="hide" && released.length==1
            && released[0].world===_root.gameworld && released[0].identity===_root.gameworld.__stageReturnWorldIdentity,
            "terminal hide publishes one exact ready-world handoff");
        check(!SceneTransitionService.isPresentationPending(),"successful terminal hide releases report presentation");
        SceneTransitionService.clear();
        check(released.length==1,"duplicate clear never republishes the report handoff");
        fade=fixture(5); _root.淡出动画=fade; SceneTransitionService.begin(fade);
        fade._currentframe=1; fade.__returnFadeActive=false; SceneTransitionService.tick();
        check(sent[sent.length-1].phase=="hide" && !SceneTransitionService.isPresentationPending(),"explicit cleanup cancellation at the empty frame retires its curtain");
        check(released.length==1,"cleanup cancellation does not manufacture a successful arrival");
        fade=revealedFixture();
        fade._currentframe=1; SceneTransitionService.tick();
        check(sent[sent.length-1].phase=="hide" && !SceneTransitionService.isPresentationPending() && released.length==1,
            "cancellation after a reveal receipt still cannot publish a successful arrival");
        fade=revealedFixture();
        fade._currentframe=37; SceneTransitionService.failed(fade); SceneTransitionService.clear();
        check(sent[sent.length-1].phase=="hide" && released.length==1,
            "error retirement after a reveal receipt cannot publish a successful arrival");
        fade=revealedFixture(); SceneTransitionService.clear();
        check(sent[sent.length-1].phase=="hide" && released.length==1,
            "explicit early retirement cannot bypass the successful terminal frame");
        fade=fixture(37); _root.淡出动画=fade; SceneTransitionService.failed(fade);
        var error:Object=sent[sent.length-1];
        check(error.phase=="error","failure projection stays visible");
        SceneTransitionService.action({requestId:error.requestId,revision:error.revision-1,verb:"retry"});
        check(counters.retries==0,"stale error click rejected");
        SceneTransitionService.action({requestId:error.requestId,revision:error.revision,verb:"retry"});
        check(counters.retries==1,"retry uses original fade entry");
        SceneTransitionService.action({requestId:error.requestId,revision:error.revision,verb:"retry"});
        check(counters.retries==1,"double click never replays navigation");
        check(sent[sent.length-1].actionPending===true,"authoritative unknown-action lock projected");
        SceneTransitionService.clear();
        check(released.length==1,"loading-error retirement does not publish a successful report handoff");
        fade=fixture(37); _root.淡出动画=fade;
        _root.从加载失败返回=function():Void {counters.returns++;};
        SceneTransitionService.failed(fade); error=sent[sent.length-1];
        SceneTransitionService.action({requestId:error.requestId,revision:error.revision,verb:"return"});
        check(counters.returns==1 && _root.场景进入位置名=="出生地","return uses existing authority and spawn");
        SceneTransitionService.clear();
        check(sent[sent.length-1].phase=="hide","terminal identity tombstone emitted");
        fade=fixture(6); _root.淡出动画=fade; SceneTransitionService.begin(fade);
        var managedCleanup:Boolean=SceneTransitionService.cleanupCompleted(fade);
        SceneTransitionService.tick(); SceneTransitionService.tick();
        check(!managedCleanup && counters.jumps==0,"cleanup advancement cannot substitute for curtain coverage");
        cover=sent[sent.length-1];
        SceneTransitionService.presented({requestId:cover.requestId,revision:cover.revision,kind:"covered"});
        managedCleanup=SceneTransitionService.cleanupCompleted({_currentframe:6});
        check(!managedCleanup && counters.stops==0,"foreign fade cannot schedule timeline advancement");
        SceneTransitionService.cleanupCompleted(fade);
        check(counters.stops==1 && counters.jumps==0,"successful cleanup pins only the waiting frame");
        managedCleanup=SceneTransitionService.cleanupCompleted(fade);
        check(managedCleanup && counters.stops==1,"duplicate cleanup completion retains frame ownership without resetting its fence");
        SceneTransitionService.tick();
        check(counters.jumps==0,"cleanup preserves an EnterFrame boundary");
        SceneTransitionService.tick();
        check(counters.jumps==1 && counters.target==13,"cleanup crosses only blank frames and still enters original load frame");
        fade._currentframe=15; SceneTransitionService.initializationCompleted(fade);
        SceneTransitionService.tick(); SceneTransitionService.tick();
        check(counters.jumps==1,"task checks and frame-17 save guard cannot be skipped");
        fade._currentframe=17; SceneTransitionService.initializationCompleted(fade);
        SceneTransitionService.tick();
        check(counters.jumps==1,"initialization preserves its own frame boundary");
        SceneTransitionService.tick();
        check(counters.jumps==2 && counters.target==30,"initialization advances to original reveal gate");
        SceneTransitionService.awaitReveal(fade);
        check(sent[sent.length-1].phase!="reveal","shortened wait still requires new-world SceneReady");
        SceneTransitionService.clear();
        fade=fixture(6); _root.淡出动画=fade; SceneTransitionService.begin(fade); cover=sent[sent.length-1];
        SceneTransitionService.presented({requestId:cover.requestId,revision:cover.revision,kind:"covered"});
        SceneTransitionService.cleanupCompleted(fade); SceneTransitionService.clear();
        SceneTransitionService.tick(); SceneTransitionService.tick();
        check(counters.jumps==0,"retired session cannot perform a scheduled jump");
        SceneTransitionService.begin(fade); cover=sent[sent.length-1];
        SceneTransitionService.presented({requestId:cover.requestId,revision:cover.revision,kind:"covered"});
        SceneTransitionService.cleanupCompleted(fade); fade._currentframe=37; SceneTransitionService.failed(fade);
        SceneTransitionService.tick(); SceneTransitionService.tick();
        check(counters.jumps==0,"load failure cancels a pending blank-frame skip");
        SceneTransitionService.clear();
        check(!SceneTransitionService.cleanupCompleted(fade),
            "unmanaged legacy cleanup can resume its original fade timeline");
        testCalibrationPresentation();
        testBackgroundPresentation();
        testLoadingDeadline();
        HorizontalScroller.releaseScene(_root.gameworld,_root.gameworld.__stageReturnWorldIdentity,
            HorizontalScroller.sceneScope(_root.gameworld,_root.gameworld.__stageReturnWorldIdentity));
        cameraHolder.removeMovieClip();
        _root.帧计时器=old.cameraTimer;_root.天空盒=old.cameraSky;_root.控制目标=old.cameraControl;
        _root.basicZoomScale=old.cameraScale;_root.cameraZoomToggle=old.cameraToggle;_root.启用后景=old.cameraParallax;
        _root.淡出动画=old.fade; _root.gameworld=old.world; _root.加载背景列表=old.data;
        _root.初期关卡列表=old.stages; _root.关卡标志=old.flag; _root.主线任务进度=old.progress;
        _root.从加载失败返回=old.returned; _root.场景进入位置名=old.entry;
        _root._saveExt=old.saveExt; _root.当前为战斗地图=old.battle;
        _root.场景转换中=old.transitioning; _root.斗兽标定模式=old.calibration;
        SceneTransitionService.sendOverride=null;
        EventBus.getInstance().unsubscribe("SceneTransitionReleased",onReleased,SceneTransitionServiceTest);
        trace("SceneTransitionServiceTest Tests Passed: "+passed);
        trace("SceneTransitionServiceTest Tests Failed: "+failed);
    }
    private static var backgroundLoads:Array;
    private static var rejectBackground:Boolean;
    private static function pendingBackground():Object {
        SceneTransitionService.clear();
        var fade:Object=fixture(5);_root.淡出动画=fade;
        _root.gameworld=cameraWorld(undefined,true);
        SceneTransitionService.begin(fade);var cover:Object=sent[sent.length-1];
        SceneTransitionService.presented({requestId:cover.requestId,revision:cover.revision,kind:"covered"});
        _root.gameworld=cameraWorld(undefined,true);
        var target:Object={};
        _root.gameworld.背景={外部动画加载壳mc:target};
        SceneTransitionService.loadBackground(_root.gameworld,"fixture.swf",target);
        fade._currentframe=30;
        EventBus.getInstance().publish("SceneReady",_root.gameworld,"",_root.gameworld.__stageReturnWorldIdentity);
        return {fade:fade,target:target,load:backgroundLoads[backgroundLoads.length-1]};
    }
    private static function testLoadingDeadline():Void {
        SceneTransitionService.clear();
        var fade:Object=fixture(5);_root.淡出动画=fade;
        SceneTransitionService.begin(fade);var cover:Object=sent[sent.length-1];
        SceneTransitionService.presented({requestId:cover.requestId,revision:cover.revision,kind:"covered"});
        fade._currentframe=6;SceneTransitionService.tick();
        var api:Object=SceneTransitionService;api._session.waitAt=getTimer()-30001;
        SceneTransitionService.tick();
        check(fade._currentframe==6 && counters.retries==0,"cleanup and unknown writes are never bypassed by loading timeout");
        fade._currentframe=30;SceneTransitionService.tick();
        check(fade._currentframe==30,"new loading milestone gets a fresh deadline");
        api._session.waitAt=getTimer()-30001;SceneTransitionService.tick();
        check(fade._currentframe==37 && sent[sent.length-1].phase=="error" && counters.retries==0,
            "missing SceneReady ends at the existing failure page without automatic replay");
        var rev:Number=sent[sent.length-1].revision;SceneTransitionService.tick();
        check(sent[sent.length-1].revision==rev,"stalled failure is reported once");
        SceneTransitionService.clear();
    }
    private static function testBackgroundPresentation():Void {
        backgroundLoads=[];rejectBackground=false;
        var proto:Object=MovieClipLoader.prototype;
        var original:Object={load:proto.loadClip,add:proto.addListener,remove:proto.removeListener};
        proto.addListener=function(listener:Object):Boolean {this.fixtureListener=listener;return true;};
        proto.removeListener=function(listener:Object):Boolean {this.fixtureListener=null;return true;};
        proto.loadClip=function(url:String,target:Object):Boolean {
            backgroundLoads.push({listener:this.fixtureListener,target:target});return !rejectBackground;
        };
        var value:Object=pendingBackground();
        check(sent[sent.length-1].phase!="reveal","business SceneReady cannot reveal an unfinished background");
        SceneTransitionService.tick();SceneTransitionService.tick();
        check(sent[sent.length-1].phase!="reveal","ordinary ticks cannot complete the external loader");
        value.load.listener.onLoadInit({});SceneTransitionService.tick();SceneTransitionService.tick();
        check(sent[sent.length-1].phase!="reveal","foreign loader target cannot complete visual readiness");
        value.load.listener.onLoadInit(value.target);
        check(sent[sent.length-1].phase!="reveal","load-init callback does not reveal in its own frame");
        SceneTransitionService.tick();
        check(sent[sent.length-1].phase!="reveal","first tick may share the load-init frame");
        SceneTransitionService.tick();
        check(sent[sent.length-1].phase=="reveal","initialized background crosses a frame before Host reveal request");
        var revision:Number=sent[sent.length-1].revision;
        value.load.listener.onLoadError(value.target,"late",0);SceneTransitionService.tick();
        check(sent[sent.length-1].phase=="reveal" && sent[sent.length-1].revision==revision,"late loader error cannot reverse successful initialization");
        value=pendingBackground();
        SceneTransitionService.backgroundBaked(_root.gameworld,_root.gameworld.背景);
        SceneTransitionService.tick();SceneTransitionService.tick();
        check(sent[sent.length-1].phase!="reveal","baking a pre-load placeholder cannot grant background readiness");
        value.load.listener.onLoadComplete(value.target);SceneTransitionService.tick();SceneTransitionService.tick();
        check(sent[sent.length-1].phase!="reveal","download completion alone is not initialized pixels");
        SceneTransitionService.backgroundBaked(_root.gameworld,{});SceneTransitionService.tick();SceneTransitionService.tick();
        check(sent[sent.length-1].phase!="reveal","foreign background bake cannot acknowledge this loader");
        SceneTransitionService.backgroundBaked(_root.gameworld,_root.gameworld.背景);
        delete _root.gameworld.背景.外部动画加载壳mc;
        SceneTransitionService.tick();SceneTransitionService.tick();
        check(sent[sent.length-1].phase=="reveal","completed bitmap bake survives unloading the original loader child");
        value=pendingBackground();
        var old:Object=value.load;
        SceneTransitionService.loadBackground(_root.gameworld,"replacement.swf",value.target);
        var fresh:Object=backgroundLoads[backgroundLoads.length-1];
        old.listener.onLoadInit(value.target);old.listener.onLoadError(value.target,"late",0);
        SceneTransitionService.tick();SceneTransitionService.tick();
        check(sent[sent.length-1].phase!="reveal" && value.fade._currentframe==30,"superseded load cannot complete or fail the replacement at the same path");
        fresh.listener.onLoadInit(value.target);SceneTransitionService.tick();SceneTransitionService.tick();
        check(sent[sent.length-1].phase=="reveal","current replacement owns readiness");
        value=pendingBackground();_root.gameworld.__stageReturnWorldIdentity={};
        value.load.listener.onLoadInit(value.target);SceneTransitionService.tick();SceneTransitionService.tick();
        check(sent[sent.length-1].phase!="reveal","world identity replacement rejects late load-init");
        value=pendingBackground();value.load.listener.onLoadError(value.target,"missing",404);SceneTransitionService.tick();
        check(value.fade._currentframe==37 && sent[sent.length-1].phase=="error","load error enters the existing covered failure timeline");
        revision=sent[sent.length-1].revision;
        value.load.listener.onLoadInit(value.target);SceneTransitionService.tick();
        check(sent[sent.length-1].phase=="error" && sent[sent.length-1].revision==revision,"load-init after failure cannot release the curtain");
        rejectBackground=true;value=pendingBackground();SceneTransitionService.tick();rejectBackground=false;
        check(value.fade._currentframe==37 && sent[sent.length-1].phase=="error","synchronous load rejection remains covered");
        value=pendingBackground();value.load.listener.ticket.started=getTimer()-30001;SceneTransitionService.tick();
        check(value.fade._currentframe==37 && sent[sent.length-1].phase=="error" && counters.retries==0,"load deadline fails closed without navigation replay");
        SceneTransitionService.clear();
        proto.loadClip=original.load;proto.addListener=original.add;proto.removeListener=original.remove;
    }
    private static function revealedFixture():Object {
        var fade:Object=fixture(5); _root.淡出动画=fade;
        SceneTransitionService.begin(fade); var cover:Object=sent[sent.length-1];
        SceneTransitionService.presented({requestId:cover.requestId,revision:cover.revision,kind:"covered"});
        _root.gameworld=cameraWorld(undefined,true); fade._currentframe=30;
        EventBus.getInstance().publish("SceneReady",_root.gameworld,"return.token",_root.gameworld.__stageReturnWorldIdentity);
        var reveal:Object=sent[sent.length-1];
        SceneTransitionService.presented({requestId:reveal.requestId,revision:reveal.revision,kind:"revealed"});
        return fade;
    }

    private static function onCalibrationReleased(owner:Object,context:Object,world:Object,
            identity:Object,fade:Object,projection:Object):Void {
        calibrationReleases.push({owner:owner,context:context,world:world,identity:identity,
            fade:fade,projection:projection});
    }
    private static function onOrdinaryReady(world:Object,token:String,identity:Object):Void {
        ordinaryReadyCount++;
    }
    private static function calibrationFixture(holder:MovieClip):Object {
        SceneTransitionService.clear();
        if (holder.world != undefined) holder.world.removeMovieClip();
        var previous:MovieClip=holder.createEmptyMovieClip("world",1);
        _root.gameworld=previous;
        var previousIdentity:Object=org.flashNight.arki.scene.StageReturnFlow.worldIdentity(previous);
        var fade:Object=fixture(5); _root.淡出动画=fade;
        SceneTransitionService.begin(fade); var cover:Object=sent[sent.length-1];
        SceneTransitionService.presented({requestId:cover.requestId,revision:cover.revision,kind:"covered"});
        previous.removeMovieClip();
        var world:MovieClip=holder.createEmptyMovieClip("world",1);
        _root.gameworld=world; world._arenaCalibrationStage=true;
        var identity:Object=org.flashNight.arki.scene.StageReturnFlow.worldIdentity(world);
        fade._currentframe=17; SceneTransitionService.tick(); SceneTransitionService.setTip(fade,"calibration");
        return {world:world,identity:identity,previous:previous,previousIdentity:previousIdentity,
            fade:fade,projection:fade.__transitionProjectionIdentity,owner:{token:"calibration.owner"},
            context:{workerId:"w01",sessionEpoch:"session01",assignmentId:"assignment01",attemptId:"attempt01",
                batchId:"batch01",manifestHash:"manifest01",caseId:"case01",caseHash:"casehash01",runId:"run01",repeatIndex:1}};
    }
    private static function readyCalibration(value:Object):Boolean {
        value.world.背景长=2400;value.world.背景高=800;
        var camera:MovieClip=value.world.camera;
        if(camera==undefined) camera=value.world.createEmptyMovieClip("camera",5);
        camera._x=1200;camera._y=400;
        HorizontalScroller.bindExplicitScene(value.world,value.identity,camera,value.owner,true);
        HorizontalScroller.update();
        return SceneTransitionService.calibrationWorldReady(value.world,value.identity,value.fade,
            value.projection,value.owner,value.context,onCalibrationReleased);
    }
    private static function testCalibrationPresentation():Void {
        var oldWorld:Object=_root.gameworld, oldFade:Object=_root.淡出动画;
        var ordinaryBefore:Number=released.length;
        ordinaryReadyCount=0; calibrationReleases=[];
        EventBus.getInstance().subscribe("SceneReady",onOrdinaryReady,SceneTransitionServiceTest);
        var holder:MovieClip=_root.createEmptyMovieClip("__calibrationCurtainFixture",_root.getNextHighestDepth());
        var value:Object=calibrationFixture(holder);
        check(value.previous===value.world && value.previousIdentity!==value.identity,
            "real same-path MovieClip rebind keeps a distinct captured ordinary identity");
        check(!SceneTransitionService.calibrationWorldReady(value.world,value.previousIdentity,value.fade,
            value.projection,value.owner,value.context,onCalibrationReleased),"old same-path world identity cannot admit calibration readiness");
        check(!SceneTransitionService.calibrationWorldReady(value.world,value.identity,value.fade,
            {},value.owner,value.context,onCalibrationReleased),"foreign fade projection identity is rejected");
        check(!SceneTransitionService.calibrationWorldReady(value.world,value.identity,value.fade,
            value.projection,value.owner,value.context,null),"missing release callback cannot borrow ordinary arrival");
        value.world._arenaCalibrationStage=false;
        check(!readyCalibration(value),"ordinary world cannot use calibration presentation admission");
        value.world._arenaCalibrationStage=true;
        check(readyCalibration(value),"exact no-player world admits dedicated visual readiness");
        check(sent[sent.length-1].phase=="loading" && calibrationReleases.length==0 && ordinaryReadyCount==0,
            "visual readiness before frame 30 neither reveals nor publishes ordinary SceneReady");
        check(readyCalibration(value),"duplicate exact dedicated readiness is idempotent");
        check(!SceneTransitionService.calibrationWorldReady(value.world,value.identity,value.fade,
            value.projection,{},value.context,onCalibrationReleased),"another owner cannot replace the dedicated waiter");
        check(!SceneTransitionService.calibrationWorldReady(value.world,value.identity,value.fade,
            value.projection,value.owner,{},onCalibrationReleased),"another context cannot replace the frozen dedicated waiter");
        value.fade._currentframe=30; SceneTransitionService.awaitReveal(value.fade);
        var reveal:Object=sent[sent.length-1];
        check(reveal.phase=="reveal" && calibrationReleases.length==0,
            "frame 30 asks the existing native/Web fence without releasing the run");
        var plays:Number=counters.plays;
        SceneTransitionService.presented({requestId:reveal.requestId,revision:reveal.revision-1,kind:"revealed"});
        check(counters.plays==plays && calibrationReleases.length==0,"stale reveal cannot release the calibration tail");
        SceneTransitionService.presented({requestId:reveal.requestId,revision:reveal.revision,kind:"revealed"});
        check(counters.plays==plays+1 && calibrationReleases.length==0,"exact reveal still waits for original frame 36");
        value.fade._currentframe=36; SceneTransitionService.tick();
        check(calibrationReleases.length==1 && calibrationReleases[0].owner===value.owner
            && calibrationReleases[0].context===value.context && calibrationReleases[0].identity===value.identity
            && calibrationReleases[0].projection===value.projection && sent[sent.length-1].phase=="hide",
            "successful tail hides first and returns the exact dedicated world/context once");
        check(released.length==ordinaryBefore && ordinaryReadyCount==0,
            "dedicated release emits neither ordinary SceneReady nor SceneTransitionReleased");
        SceneTransitionService.clear();
        check(calibrationReleases.length==1,"duplicate clear cannot replay the dedicated release");

        var modes:Array=["early","frame1","error","world","epoch","fade"];
        for(var i:Number=0;i<modes.length;i++) {
            value=calibrationFixture(holder); readyCalibration(value);
            value.fade._currentframe=30; SceneTransitionService.awaitReveal(value.fade);
            reveal=sent[sent.length-1];
            SceneTransitionService.presented({requestId:reveal.requestId,revision:reveal.revision,kind:"revealed"});
            if(modes[i]=="early") SceneTransitionService.clear();
            else if(modes[i]=="frame1") {value.fade._currentframe=1;SceneTransitionService.tick();}
            else if(modes[i]=="error") {value.fade._currentframe=37;SceneTransitionService.failed(value.fade);SceneTransitionService.clear();}
            else {
                if(modes[i]=="world") {
                    value.world.removeMovieClip(); _root.gameworld=holder.createEmptyMovieClip("world",1);
                    _root.gameworld._arenaCalibrationStage=true;
                    org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld);
                } else if(modes[i]=="epoch") org.flashNight.arki.weather.WorldLightingBridge.sceneChanged();
                else value.fade.__transitionProjectionIdentity={};
                value.fade._currentframe=36; SceneTransitionService.tick();
            }
            check(calibrationReleases.length==1 && released.length==ordinaryBefore && ordinaryReadyCount==0,
                "cancelled or replaced dedicated presentation cannot release a run: "+modes[i]);
        }
        SceneTransitionService.clear(); holder.removeMovieClip();
        _root.gameworld=oldWorld; _root.淡出动画=oldFade;
        EventBus.getInstance().unsubscribe("SceneReady",onOrdinaryReady,SceneTransitionServiceTest);
    }
}
