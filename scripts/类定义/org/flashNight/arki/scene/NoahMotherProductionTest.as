/** Published things5 timeline load callbacks; no save slots. */
class org.flashNight.arki.scene.NoahMotherProductionTest {
    private static var library:MovieClip;
    private static var watch:MovieClip;
    private static var mother:MovieClip;
    private static var bug:MovieClip;
    private static var death:MovieClip;
    private static var loader:MovieClipLoader;
    private static var frame:Number=0;
    private static var passed:Number=0;
    private static var failed:Number=0;
    public static var births:Number=0;
    public static var transformations:Number=0;
    public static var allowed:Boolean=false;
    public static function runAllTests():Void {
        _root.暂停=false;_root.场景转换中=false;
        _root.gameworld=_root.createEmptyMovieClip("noahNativeWorld",_root.getNextHighestDepth());
        _root.gameworld.__stageReturnWorldIdentity={};
        _root.gameworld.__noahMotherEncounter={canProduce:function():Boolean {return org.flashNight.arki.scene.NoahMotherProductionTest.allowed;}};
        _root.初始化敌人模板=function():Void {this.hp=this.hp满血值=1000;this.是否为敌人=true;this.等级=41;this.stop();};
        _root.加载游戏世界人物=function():MovieClip {org.flashNight.arki.scene.NoahMotherProductionTest.births++;return null;};
        _root.敌人函数={基因虫生成僵尸:function():Boolean {
            if(!org.flashNight.arki.scene.NoahMotherProductionTest.allowed)return false;
            org.flashNight.arki.scene.NoahMotherProductionTest.transformations++;return true;
        }};
        library=_root.createEmptyMovieClip("noahThings5",_root.getNextHighestDepth());
        loader=new MovieClipLoader();var listener:Object={};
        listener.onLoadInit=function(mc:MovieClip):Void {org.flashNight.arki.scene.NoahMotherProductionTest.loaded(mc);};
        listener.onLoadError=function(mc:MovieClip,code:String):Void {trace("[FAIL] Noah production asset "+code);};
        loader.addListener(listener);loader.loadClip("../flashswf/arts/things5.swf",library);
    }
    private static function check(ok:Boolean,label:String):Void {if(ok)passed++;else {failed++;trace("[FAIL] NoahMotherProductionTest "+label);}}
    public static function loaded(mc:MovieClip):Void {
        mother=mc.attachMovie("敌人-普通尸母","mother",200,{近战招式:"a0"});
        bug=mc.attachMovie("敌人-普通基因虫","bug",201);
        watch=_root.createEmptyMovieClip("noahProductionWatch",_root.getNextHighestDepth());
        watch.onEnterFrame=function():Void {org.flashNight.arki.scene.NoahMotherProductionTest.tick();};
    }
    public static function tick():Void {
        frame++;
        if(frame==2){
            check(mother.基因虫数量==5,"native mother retains five offspring");
            check(mother._name!=undefined && bug.基因虫生成僵尸!=undefined,"both published native producers attach");
            mother.gotoAndStop(38);mother.man.gotoAndStop(23);
        }
        if(frame==4){check(births==0 && mother.基因虫数量==5,"blocked birth retains native quota");mother.man.gotoAndStop(24);allowed=true;}
        if(frame==5)mother.man.gotoAndStop(23);
        if(frame==7){check(births==1 && mother.基因虫数量==4,"released slot makes one native offspring");allowed=false;bug.gotoAndStop("血腥死");
            // 原生爆裂动作是未命名子元件，不能误测消失帧或已卸载的 man。
            for(var name:String in bug){var child:MovieClip=bug[name];if(typeof child=="movieclip" && child._totalframes==197)death=child;}}
        if(frame==24){check(transformations==0 && death._currentframe==9,"full population holds transformation at its native production frame");allowed=true;}
        if(frame==37){check(transformations==1 && death._currentframe>9,"freed capacity resumes transformation exactly once");}
        if(frame==38){allowed=false;delete _root.gameworld.__noahMotherEncounter;mother.man.gotoAndStop(24);}
        if(frame==39)mother.man.gotoAndStop(23);
        if(frame==42){
            check(births==2 && mother.基因虫数量==3,"other maps retain original mother production");
            delete watch.onEnterFrame;watch.removeMovieClip();mother.removeMovieClip();bug.removeMovieClip();library.removeMovieClip();
            _root.gameworld.removeMovieClip();
            trace("NoahMotherProductionTest Tests Passed: "+passed);trace("NoahMotherProductionTest Tests Failed: "+failed);
            trace("FocusedTestRunId noah-mother-production Complete: "+_root.__noahProductionRunId);
        }
    }
}
