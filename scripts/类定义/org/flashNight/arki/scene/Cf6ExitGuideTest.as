import org.flashNight.arki.scene.*;
/** Disposable real MovieClip identity tests; guidance must never grant navigation. */
class org.flashNight.arki.scene.Cf6ExitGuideTest {
    private static var passed:Number,failed:Number;
    private static function check(ok:Boolean,label:String):Void {if(ok) passed++;else {failed++;trace("[FAIL] Cf6ExitGuide: "+label);}}
    private static function fixture():Object {
        var world:MovieClip=_root.createEmptyMovieClip("__cf6GuideFixture",_root.getNextHighestDepth());
        world.__stageReturnWorldIdentity={};world.允许通行=false;world.关卡结束=false;_root.gameworld=world;
        var manager:Object={currentStage:0,isFailed:false,isFinished:false};var cls:Object=StageManager;cls.instance=manager;
        var room:Object={world:world,owner:world.__stageReturnWorldIdentity,stageManager:manager,stageIndex:0,clearRequested:false,
            departure:{spec:{gate:{x:120,z:230,radius:42}},rules:{phase:"waiting"}}};world.__cf6Mechanism=room;
        return room;
    }
    private static function testClearCue():Void {
        var effectClass:Object=org.flashNight.arki.component.Effect.EffectSystem;
        var previousEffect:Function=effectClass.Effect,previousCalls=_root.__cf6CueCalls;
        _root.__cf6CueCalls=0;
        effectClass.Effect=function(name:String,x:Number,y:Number,scale:Number):Void {_root.__cf6CueCalls++;};
        var s:Object=fixture(),hero:MovieClip=s.world.createEmptyMovieClip("hero",7);
        hero.hp=100;hero._x=150;hero._y=240;
        check(!Cf6ExitGuideService.showClearCue(s,hero) && _root.__cf6CueCalls==0,"uncleared combat cannot issue cue");
        s.clearRequested=true;hero._visible=false;
        check(!Cf6ExitGuideService.showClearCue(s,hero),"hidden arrival waits for actual visible actor");
        hero._visible=true;hero.hp=0;
        check(!Cf6ExitGuideService.showClearCue(s,hero),"dead actor gets no victory cue");
        hero.hp=100;
        check(Cf6ExitGuideService.showClearCue(s,hero) && _root.__cf6CueCalls==1,"real clear request issues existing cue before final clear");
        check(Cf6ExitGuideService.hasClearCue(s.stageManager,s.world),"final clear can observe exact presentation receipt");
        check(!Cf6ExitGuideService.showClearCue(s,hero) && _root.__cf6CueCalls==1,"repeated ticks cannot duplicate cue");
        check(!s.world.允许通行 && !s.world.关卡结束,"early cue cannot grant clear or navigation");
        check(!Cf6ExitGuideService.hasClearCue({},s.world),"foreign manager cannot suppress its own cue");
        s.stageManager.currentStage++;
        check(!Cf6ExitGuideService.hasClearCue(s.stageManager,s.world),"later stage cannot consume old cue");
        s.world.removeMovieClip();s=fixture();hero=s.world.createEmptyMovieClip("hero",7);hero.hp=100;s.clearRequested=true;
        effectClass.Effect=function():Void {_root.__cf6CueCalls++;throw "partial projection fixture";};
        check(Cf6ExitGuideService.showClearCue(s,hero) && _root.__cf6CueCalls==2,"partially failed projection is still single-attempt");
        check(!Cf6ExitGuideService.showClearCue(s,hero) && Cf6ExitGuideService.hasClearCue(s.stageManager,s.world),"partial projection cannot replay at final clear");
        var original:Object=s.owner;s.world.__stageReturnWorldIdentity={};
        check(!Cf6ExitGuideService.hasClearCue(s.stageManager,s.world),"world identity replacement invalidates cue receipt");
        s.world.removeMovieClip();effectClass.Effect=previousEffect;_root.__cf6CueCalls=previousCalls;
    }
    private static function testAcquisitionGeometry():Void {
        for(var i:Number=0;i<2;i++) {
            var s:Object=fixture(),radius:Number=i==0 ? 42 : 35;
            s.departure.spec.gate.radius=radius;
            s.departure.rules.heading=i==0 ? null : "右";
            var h:Object=Cf6ExitGuideService.begin(s,null);
            var bounds:Object=h.clip.getBounds(h.clip);
            var x:Number=Math.max(Math.abs(bounds.xMin),Math.abs(bounds.xMax));
            var z:Number=Math.max(Math.abs(bounds.yMin),Math.abs(bounds.yMax));
            check(Math.sqrt(x*x+z*z)<radius,"complete rendered guide fits acquisition circle radius="+radius);
            var point:Object={hp:100,_x:120+x,Z轴坐标:230+z};
            check(Cf6TraversalService.atGate(s.departure.spec,point),"outer guide bounds enter actual atGate radius="+radius);
            check(h.clip._rotation==(i==0 ? 0 : 90),"door/up and elevator/right follow trajectory heading");
            Cf6ExitGuideService.end(h);s.world.removeMovieClip();
        }
        var s:Object=fixture();s.departure.rules.heading="右";s.departure.spec.gate.direction="左";
        var h:Object=Cf6ExitGuideService.begin(s,null);
        check(h.clip._rotation==-90,"explicit authored gate direction wins over inferred heading");
        Cf6ExitGuideService.end(h);s.world.removeMovieClip();
    }
    public static function runAllTests():Void {
        passed=failed=0;var previousWorld=_root.gameworld,cls:Object=StageManager,previousManager=cls.instance;
        var s:Object=fixture(),h:Object=Cf6ExitGuideService.begin(s,{x:900,z:900,direction:"右"});
        check(h!=null,"valid current-room guide");
        check(h.clip._x==120 && h.clip._y==230,"actual acquisition gate wins over optional point");
        trace("Cf6ExitGuide AlphaReadback: requested=45 actual="+h.clip._alpha+" visible="+h.clip._visible);
        check(h.clip._visible && Math.abs(h.clip._alpha-45)<100/256,"locked exit is dim but findable before clear");
        s.clearRequested=true;Cf6ExitGuideService.tick(h);
        check(h.clip._visible && h.clip._alpha==100,"actual clear request brightens guide before entering");
        check(!s.world.允许通行 && !s.world.关卡结束 && s.departure.rules.phase=="waiting","guide never publishes clear or advances authority");
        s.departure.rules.phase="playing";Cf6ExitGuideService.tick(h);check(!h.clip._visible,"owned departure hides guide");
        s.departure.rules.phase="complete";Cf6ExitGuideService.tick(h);check(!h.clip._visible,"completed departure remains hidden");
        Cf6ExitGuideService.end(h);check(h.closed && h.clip._parent==undefined,"cleanup removes only owned clip");
        Cf6ExitGuideService.end(h);check(h.closed,"cleanup is idempotent");
        s.departure=null;h=Cf6ExitGuideService.begin(s,{x:340,z:360,direction:"右"});
        check(h!=null && h.clip._x==340 && h.clip._y==360 && h.clip._rotation==90,"ordinary exit uses explicit world point and direction");
        h.clip.__cf6ExitGuideOwner={};Cf6ExitGuideService.end(h);check(h.clip._parent===s.world,"foreign marker survives cleanup");
        check(Cf6ExitGuideService.begin(s,{x:NaN,z:10})==null,"nonfinite point rejected");
        check(Cf6ExitGuideService.begin(s,null)==null,"missing guide does not invent edge coordinates");
        s.world.removeMovieClip();s=fixture();h=Cf6ExitGuideService.begin(s,null);
        s.stageManager.currentStage++;Cf6ExitGuideService.tick(h);check(h.closed,"stage identity change closes guide");
        s.world.removeMovieClip();s=fixture();h=Cf6ExitGuideService.begin(s,null);
        var oldName:String=h.clip._name;s.world.removeMovieClip();var replacement:MovieClip=_root.createEmptyMovieClip("__cf6GuideFixture",_root.getNextHighestDepth());
        _root.gameworld=replacement;replacement.__stageReturnWorldIdentity={};
        var sameName:MovieClip=replacement.createEmptyMovieClip(oldName,1);sameName.__cf6ExitGuideOwner={};
        Cf6ExitGuideService.tick(h);check(h.closed && sameName._parent===replacement,"same-path world replacement stays untouched");
        replacement.removeMovieClip();testClearCue();testAcquisitionGeometry();_root.gameworld=previousWorld;cls.instance=previousManager;
        trace("Cf6ExitGuideTest Tests Passed: "+passed);trace("Cf6ExitGuideTest Tests Failed: "+failed);
    }
}
