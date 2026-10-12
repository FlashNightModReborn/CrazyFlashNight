import org.flashNight.arki.unit.Action.Skill.*;

/** 实际 SWF 加载顺序门。TestLoader 提供与 asLoader 同源的两类；资源不得成为第一定义者。 */
class org.flashNight.dev.SWFAuthorityDebtTest {
    private static var passed:Number,failed:Number,phase:Number,ticks:Number;
    private static var pkg:Object,attributeClass:Object,damageClass:Object;
    private static var loader:MovieClipLoader,listener:Object;
    private static var resource:MovieClip,actor:MovieClip,driver:MovieClip;
    private static var finished:Boolean;
    private static function check(ok:Boolean,name:String):Void {
        if(ok)passed++;else{failed++;trace("[FAIL] SWFAuthorityDebt "+name);}
    }
    public static function runAllTests():Void {
        passed=failed=phase=ticks=0;finished=false;
        attributeClass=SkillAttributeCore;damageClass=SkillDamageCore;
        pkg=_global.org.flashNight.arki.unit.Action.Skill;
        check(typeof(attributeClass.transferWeaponAttributes)=="function"&&typeof(damageClass.speedToDamage)=="function","canonical classes available before resources");
        actor=_root.createEmptyMovieClip("authorityDebtActor",_root.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("authorityDebtDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {
            if(++SWFAuthorityDebtTest.ticks>200){SWFAuthorityDebtTest.check(false,"actual resource load timeout");SWFAuthorityDebtTest.complete();}
        };
        loader=new MovieClipLoader();listener={};
        listener.onLoadInit=function(mc:MovieClip):Void{SWFAuthorityDebtTest.loaded(mc);};
        listener.onLoadError=function(mc:MovieClip,error:String):Void{SWFAuthorityDebtTest.check(false,"load "+error);SWFAuthorityDebtTest.complete();};
        loader.addListener(listener);loadNext();
    }
    private static function loadNext():Void {
        ticks=0;
        if(phase==1){delete pkg.SkillAttributeCore;delete pkg.SkillDamageCore;}
        resource=_root.createEmptyMovieClip("authorityDebtResource"+phase,_root.getNextHighestDepth());
        trace("SWFAuthorityDebt load order="+(phase==0?"loader-first":"resource-first"));
        loader.loadClip("../flashswf/arts/new/Codex黑仔素材.swf",resource);
    }
    private static function loaded(mc:MovieClip):Void {
        mc.stop();
        if(phase==0)check(pkg.SkillAttributeCore===attributeClass&&pkg.SkillDamageCore===damageClass,"resource preserves existing class identity");
        else {
            check(pkg.SkillAttributeCore==undefined&&pkg.SkillDamageCore==undefined,"resource-first defines no project classes");
            pkg.SkillAttributeCore=attributeClass;pkg.SkillDamageCore=damageClass;
        }
        actor.兵器伤害类型="魔法";actor.兵器魔法伤害属性="火";actor.兵器斩杀=10;actor.基础斩杀=3;
        var bullet:Object={};SkillAttributeCore.transferWeaponAttributes(actor,bullet);
        check(bullet.伤害类型=="魔法"&&bullet.魔法伤害属性=="火"&&bullet.斩杀==13,"real weapon attribute projection order "+phase);
        check(SkillDamageCore.speedToDamage(5)==12,"real speed damage order "+phase);
        actor.刀属性={skillmultipliers:{凶斩:2.5}};
        check(SkillDamageCore.getSkillMultiplier(actor,"凶斩")==2.5,"real multiplier order "+phase);
        actor.刀属性.skillmultipliers.凶斩="invalid";
        check(SkillDamageCore.getSkillMultiplier(actor,"凶斩")==1,"invalid multiplier fallback order "+phase);
        loader.unloadClip(resource);resource.removeMovieClip();
        if(++phase<2)loadNext();else complete();
    }
    private static function complete():Void {
        if(finished)return;finished=true;
        pkg.SkillAttributeCore=attributeClass;pkg.SkillDamageCore=damageClass;
        if(resource!=undefined){loader.unloadClip(resource);resource.removeMovieClip();}
        actor.removeMovieClip();driver.removeMovieClip();
        trace("SWFAuthorityDebtTest passed="+passed+" failed="+failed);
        _root.swfAuthorityDebtComplete();
    }
}
