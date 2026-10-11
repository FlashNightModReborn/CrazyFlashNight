import org.flashNight.arki.ui.SceneTransitionService;
import org.flashNight.neur.Event.EventBus;
class org.flashNight.arki.ui.SceneTransitionServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var sent:Array;
    private static var counters:Object;
    private static var released:Array;
    private static function onReleased(world:Object,token:String,identity:Object):Void {
        released.push({world:world,identity:identity});
    }
    private static function check(ok:Boolean,label:String):Void {
        if (ok) passed++; else {failed++; trace("[SceneTransition FAIL] "+label);}
    }
    private static function fixture(frame:Number):Object {
        counters = {plays:0,stops:0,retries:0,returns:0,jumps:0};
        return {_currentframe:frame,
            play:function():Void {counters.plays++;},stop:function():Void {counters.stops++;},
            gotoAndPlay:function(frame:Number):Void {counters.jumps++;counters.target=frame;this._currentframe=frame;},
            淡出跳转帧:function(frame:String,token:String):Void {counters.retries++;}};
    }
    public static function runAllTests():Void {
        passed=0; failed=0; sent=[]; released=[];
        EventBus.getInstance().subscribe("SceneTransitionReleased",onReleased,SceneTransitionServiceTest);
        var old:Object = {fade:_root.淡出动画,world:_root.gameworld,data:_root.加载背景列表,
            stages:_root.初期关卡列表,flag:_root.关卡标志,progress:_root.主线任务进度,
            returned:_root.从加载失败返回,entry:_root.场景进入位置名,
            saveExt:_root._saveExt,battle:_root.当前为战斗地图,
            transitioning:_root.场景转换中,calibration:_root.斗兽标定模式};
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
        _root.gameworld={__stageReturnWorldIdentity:{}};
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
        _root.gameworld={__stageReturnWorldIdentity:{}};
        EventBus.getInstance().publish("SceneReady",_root.gameworld,"",{});
        check(sent[sent.length-1].phase=="loading","rebound world path with foreign ordinary identity rejected");
        EventBus.getInstance().publish("SceneReady",_root.gameworld,"",_root.gameworld.__stageReturnWorldIdentity);
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
        _root.gameworld={__stageReturnWorldIdentity:{}};
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
    private static function revealedFixture():Object {
        var fade:Object=fixture(5); _root.淡出动画=fade;
        SceneTransitionService.begin(fade); var cover:Object=sent[sent.length-1];
        SceneTransitionService.presented({requestId:cover.requestId,revision:cover.revision,kind:"covered"});
        _root.gameworld={__stageReturnWorldIdentity:{}}; fade._currentframe=30;
        EventBus.getInstance().publish("SceneReady",_root.gameworld,"return.token",_root.gameworld.__stageReturnWorldIdentity);
        var reveal:Object=sent[sent.length-1];
        SceneTransitionService.presented({requestId:reveal.requestId,revision:reveal.revision,kind:"revealed"});
        return fade;
    }
}
