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
        replacement.removeMovieClip();_root.gameworld=previousWorld;cls.instance=previousManager;
        trace("Cf6ExitGuideTest Tests Passed: "+passed);trace("Cf6ExitGuideTest Tests Failed: "+failed);
    }
}
