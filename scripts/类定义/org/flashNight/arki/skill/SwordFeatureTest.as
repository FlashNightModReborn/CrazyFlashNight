import org.flashNight.arki.skill.*;

/** Native AVM1 invokes the production frame functions; isolated actors and route outlet. */
class org.flashNight.arki.skill.SwordFeatureTest {
    private static var passed:Number,failed:Number;
    private static function check(ok:Boolean,label:String):Void {if(ok)passed++;else{failed++;trace("[TEST_FAIL] SwordFeatureTest: "+label);}}
    public static function runAllTests():Void {
        passed=failed=0;
        var functions:Object=_root.技能函数;
        var oldRoute:Object=_root.兵器攻击路由;
        var oldMonitor:Object=functions.搓招监控;
        var calls:Object={count:0,label:""};
        _root.兵器攻击路由={兵器攻击标签跳转:function(actor:Object,label:String):Void{calls.count++;calls.label=label;}};
        functions.搓招监控=function(label:String,result:Number):Number{return result;};
        var context:MovieClip=_root.__swordFeatureContext;
        var actor:MovieClip=context._parent;
        var r:Object={_saveExt:{},主角被动技能:{剑气释放:{启用:true,等级:1}}};
        actor.被动技能=r.主角被动技能;actor.方向="右";actor.下行=true;actor.右行=true;actor.动作A=true;
        var methods:Array=["使用剑气释放","使用双剑气","使用飞沙走石","使用疾影剑气"];
        var labels:Array=["剑气释放","双剑气","飞沙走石","疾影剑气"];
        var ids:Array=["sword.wave","sword.double_wave","sword.sand","sword.shadow"];
        SkillFeaturePolicy.project(r);
        for(var i:Number=0;i<methods.length;i++) {
            var fn:Function=functions[methods[i]];actor.当前搓招名=labels[i];calls.count=0;
            check(fn.call(context)==1&&calls.count==1&&calls.label==labels[i],"legacy DFA "+ids[i]);
            actor.当前搓招名=undefined;calls.count=0;
            check(fn.call(context)==2&&calls.count==1,"frame fallback "+ids[i]);
            r._saveExt.skillFeatures=SkillFeaturePolicy.withChoice(r,ids[i],false);SkillFeaturePolicy.project(r);
            actor.当前搓招名=labels[i];calls.count=0;
            check(fn.call(context)==0&&calls.count==0&&actor.动作A===true,"disabled DFA leaves normal attack available "+ids[i]);
            actor.当前搓招名=undefined;
            check(fn.call(context)==0&&calls.count==0,"disabled frame fallback "+ids[i]);
            var restored:Object=SkillFeaturePolicy.withChoice(r,ids[i],true);if(restored==null)delete r._saveExt.skillFeatures;else r._saveExt.skillFeatures=restored;SkillFeaturePolicy.project(r);
        }
        var types:Array=["单刀","双刀","长柄","疾影"];
        var remapped:Array=["剑气释放","双剑气","飞沙走石","疾影剑气"];
        for(var j:Number=0;j<types.length;j++) {
            actor.兵器动作类型=types[j];actor.当前搓招名=remapped[j];calls.count=0;
            check(functions.判定剑气或飞沙.call(context)==1&&calls.label==remapped[j],"weapon routing "+types[j]);
            r._saveExt.skillFeatures=SkillFeaturePolicy.withChoice(r,ids[j],false);SkillFeaturePolicy.project(r);calls.count=0;
            check(functions.判定剑气或飞沙.call(context)==0&&calls.count==0,"routed opt-out "+types[j]);
            var next:Object=SkillFeaturePolicy.withChoice(r,ids[j],true);if(next==null)delete r._saveExt.skillFeatures;else r._saveExt.skillFeatures=next;SkillFeaturePolicy.project(r);
        }
        actor.被动技能.剑气释放.启用=false;
        for(var k:Number=0;k<methods.length;k++) {actor.当前搓招名=labels[k];check(functions[methods[k]].call(context)==0,"parent master switch "+ids[k]);}
        actor.被动技能.剑气释放.启用=true;actor.被动技能.剑气释放.等级=0;actor.当前搓招名="剑气释放";
        check(functions.使用剑气释放.call(context)==0,"parent level prerequisite");
        actor.removeMovieClip();_root.兵器攻击路由=oldRoute;functions.搓招监控=oldMonitor;
        trace("SwordFeatureTest Tests Passed: "+passed);trace("SwordFeatureTest Tests Failed: "+failed);
    }
}
