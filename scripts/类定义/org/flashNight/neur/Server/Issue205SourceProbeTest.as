import org.flashNight.neur.Server.Issue205SourceProbe;
import org.flashNight.neur.Server.QualificationConsoleScope;
class org.flashNight.neur.Server.Issue205SourceProbeTest {
    private static var _passed:Number=0;
    private static var _failed:Number=0;
    private static function check(value:Boolean,label:String):Void {
        if(value)_passed++;else{_failed++;trace("FAIL Issue205SourceProbe "+label);}
    }
    public static function runAllTests():Void {
        _passed=0;_failed=0;
        var before:Object=Issue205SourceProbe.inspectForTest();
        Issue205SourceProbe.mark(0);
        check(Issue205SourceProbe.inspectForTest().counts[0]===before.counts[0],"disabled counter is inert");
        Issue205SourceProbe.enableForTest(true);
        Issue205SourceProbe.mark(0);Issue205SourceProbe.mark(1);Issue205SourceProbe.mark(2);Issue205SourceProbe.mark(3);
        var live:Object=Issue205SourceProbe.inspectForTest();
        check(live.counts[0]===before.counts[0]+1,"update entry");
        check(live.counts[1]===before.counts[1]+1,"update exit");
        check(live.order[0]<live.order[1] && live.order[1]<live.order[2] && live.order[2]<live.order[3],"callback order");
        var world:MovieClip=_root.createEmptyMovieClip("__issue205SamePathTest",_root.getNextHighestDepth());
        Issue205SourceProbe.attached(world);
        var old:Object=world.__issue205Owner;
        var retired:Function=old.unloadCallback;
        check(typeof old=="object" && old.id>0,"plain owner attached");
        var visible:Boolean=false;for(var key:String in world){if(key=="__issue205Owner")visible=true;}
        check(!visible,"plain owner hidden from enumeration; no diagnostic MovieClip added");
        world.removeMovieClip();
        world=_root.createEmptyMovieClip("__issue205SamePathTest",_root.getNextHighestDepth());
        Issue205SourceProbe.attached(world);
        var next:Object=world.__issue205Owner;
        retired();
        check(old!==next && next.id>old.id,"same path gets a new plain owner");
        check(old.unloaded===true && next.unloaded===false,"late old unload cannot mutate new owner");
        var once:Number=Issue205SourceProbe.inspectForTest().unload;retired();
        check(Issue205SourceProbe.inspectForTest().unload===once,"unload witness is idempotent");
        Issue205SourceProbe.disposing();
        check(Issue205SourceProbe.inspectForTest().dispose===before.dispose+1,"dispose request separate from unload");
        world.removeMovieClip();
        Issue205SourceProbe.enableForTest(false);
        check(QualificationConsoleScope.allows("cf7_agent_i2051110","#get:savePath","cf7_agent_i2051110",""),"original test role allowed");
        check(QualificationConsoleScope.allows("cf7_agent_i2051110","#eval:hero.hp","bookrun_own","cf7_agent_i2051110"),"owned book is read-only");
        check(!QualificationConsoleScope.allows("cf7_agent_i2051110","#give:机枪贫铀穿甲弹,1000","bookrun_own","cf7_agent_i2051110"),"book mutation denied");
        check(!QualificationConsoleScope.allows("cf7_agent_i2051110","#get:savePath","real_user_role",""),"other role denied");
        trace("Issue205SourceProbeTest Tests Passed: "+_passed);
        trace("Issue205SourceProbeTest Tests Failed: "+_failed);
    }
}
