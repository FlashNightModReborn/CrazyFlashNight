import JSON;
import org.flashNight.arki.skill.*;
import org.flashNight.arki.unit.Action.Shoot.*;

/** 真实 AVM1：目录、前置、偏好隔离及实际枪械消费者；仅内存 fixture，不接触玩家槽位。 */
class org.flashNight.arki.skill.SkillFeaturePolicyTest {
    private static var passed:Number,failed:Number;
    private static function check(ok:Boolean,label:String):Void {if(ok)passed++;else{failed++;trace("[TEST_FAIL] SkillFeaturePolicyTest: "+label);}}
    private static function near(a:Number,b:Number):Boolean {return isFinite(a)&&Math.abs(a-b)<0.000001;}
    private static function choice(r:Object,id:String,enabled:Boolean):Void {
        var next:Object=SkillFeaturePolicy.withChoice(r,id,enabled);
        if(next==null)delete r._saveExt.skillFeatures;else r._saveExt.skillFeatures=next;
        SkillFeaturePolicy.project(r);
    }
    public static function runAllTests():Void {
        passed=failed=0;
        var r:Object={_saveExt:{},主角被动技能:{冲击连携:{启用:true,等级:10}}};
        var unit:Object={被动技能:r.主角被动技能,攻击模式:"双枪",装备枪械威力加成:20};
        var list:Array=SkillFeatureRegistry.all();var seen:Object={};
        for(var i:Number=0;i<list.length;i++) {
            check(SkillFeaturePolicy.validId(list[i].id)&&!seen[list[i].id],"stable unique feature "+list[i].id);
            seen[list[i].id]=true;
        }
        check(!SkillFeaturePolicy.validId("impact_chain.bad\n")&&!SkillFeaturePolicy.validId("__proto__")
            &&!SkillFeaturePolicy.validId("a..b"),"control characters and malformed IDs are rejected");
        check(!SkillFeaturePolicy.meetsLevel(2,3)&&SkillFeaturePolicy.meetsLevel(3,3)
            &&!SkillFeaturePolicy.meetsLevel(NaN,1)&&!SkillFeaturePolicy.meetsLevel(1.5,1),"generic level boundary is explicit");
        SkillFeaturePolicy.project(r);
        check(SkillFeaturePolicy.isEnabled(unit,"impact_chain.half_reload")&&r._saveExt.skillFeatures==undefined,"old saves default on without materializing preferences");
        choice(r,"impact_chain.half_reload",false);
        check(!SkillFeaturePolicy.isEnabled(unit,"impact_chain.half_reload")&&SkillFeaturePolicy.isEnabled(unit,"impact_chain.pistol_power"),"half reload is independently disabled");
        check(near(ShootInitCore.calculateWeaponPower(unit,"手枪",100,false),120),"disabled half reload preserves full main-hand damage");
        choice(r,"impact_chain.pistol_power",false);
        check(near(ShootInitCore.calculateWeaponPower(unit,"手枪",100,false),100),"main-hand power consumer follows only its own switch");
        check(near(ShootInitCore.calculateWeaponImpact(unit,"手枪2",1,"霰弹枪"),0.5),"two shotgun impact sources retain the original additive formula");
        choice(r,"impact_chain.offhand_impact",false);
        check(near(ShootInitCore.calculateWeaponImpact(unit,"手枪2",1,"霰弹枪"),1/1.5),"mixed impact can be disabled while shotgun impact remains");
        choice(r,"impact_chain.shotgun_impact",false);
        check(near(ShootInitCore.calculateWeaponImpact(unit,"手枪2",1,"霰弹枪"),1),"both impact switches off recover the base impact");
        var config:Object={hitBehavior:{type:"plain"},basePower:100,powerMultiplier:1,hostPowerMultiplier:1,hostWeaponType:"霰弹枪",impact:1};
        check(near(LongGunSubWeaponCore.calculatePower(unit,config),210)&&near(LongGunSubWeaponCore.calculateImpact(unit,config),0.5),"subweapon retains full legacy formulas");
        choice(r,"impact_chain.shotgun_subweapon_power",false);
        check(near(LongGunSubWeaponCore.calculatePower(unit,config),110),"shotgun subweapon multiplier is independent");
        choice(r,"impact_chain.subweapon_power",false);choice(r,"impact_chain.subweapon_impact",false);
        check(near(LongGunSubWeaponCore.calculatePower(unit,config),100)&&near(LongGunSubWeaponCore.calculateImpact(unit,config),1),"conversion and impact have separate consumers");
        var npc:Object={被动技能:{冲击连携:{启用:true,等级:10}}};
        check(SkillFeaturePolicy.isEnabled(npc,"impact_chain.pistol_power"),"player preferences do not leak into NPC passives");
        unit.被动技能.冲击连携.启用=false;
        check(!SkillFeaturePolicy.isEnabled(unit,"impact_chain.ghost_loading"),"parent remains a compatibility master switch");
        unit.被动技能.冲击连携.启用=true;
        r._saveExt.skillFeatures.disabledIds["future.skill"]=true;
        choice(r,"impact_chain.half_reload",true);
        check(r._saveExt.skillFeatures.disabledIds["future.skill"]===true,"unknown saved IDs survive a known choice");
        var json:JSON=new JSON(false);var copy:Object=json.parse(json.stringify(r._saveExt));
        var restored:Object={_saveExt:copy,主角被动技能:{冲击连携:{启用:true,等级:10}}};SkillFeaturePolicy.project(restored);
        check(!SkillFeaturePolicy.isEnabled({被动技能:restored.主角被动技能},"impact_chain.pistol_power"),"JSON roundtrip and post-load projection preserve opt-out");
        var signature:String=SkillFeaturePolicy.signature(r);
        r._saveExt.skillFeatures={v:2,disabledIds:{}};
        check(!SkillFeaturePolicy.readState(r).valid&&SkillFeaturePolicy.signature(r)!=signature,"future schema is preserved and rejected for writes");
        r._saveExt.skillFeatures={v:1,disabledIds:{bad:false}};
        check(!SkillFeaturePolicy.readState(r).valid,"malformed sparse state is rejected without repair");
        var capped:Object={_saveExt:{skillFeatures:{v:1,disabledIds:{}}}};
        for(var n:Number=0;n<128;n++)capped._saveExt.skillFeatures.disabledIds["future.f"+n]=true;
        check(SkillFeaturePolicy.withChoice(capped,"impact_chain.half_reload",false)===undefined,"129th opt-out is rejected before persistence");
        var reduced:Object=SkillFeaturePolicy.withChoice(capped,"future.f0",true);
        check(reduced!=undefined&&SkillFeaturePolicy.readState({_saveExt:{skillFeatures:reduced}}).valid,"full sparse namespace still permits an opt-out to be removed");
        r._saveExt={};SkillFeaturePolicy.project(r);
        unit.长枪={value:{shot:0}};unit.长枪弹匣容量=8;
        unit.长枪属性={reloadType:"tube",clipname:"feature-mag",overload:{chamber:1,ghost:2,reward:1}};
        var ammo:Object=WeaponAmmoRuntime.ensure(unit,"长枪");
        ammo.chamber=1;ammo.paidChamber=1;ammo.ghost=2;ammo.reward=3;ammo.paidNormal=8;ammo.reserve=7;
        unit.长枪.value.shot=-6;
        choice(r,"impact_chain.ghost_loading",false);WeaponAmmoRuntime.reconcileSkillFeatures(unit);
        check(ammo.ghost==0&&ammo.reserve==9&&ammo.chamber==1&&ammo.reward==3&&WeaponAmmoRuntime.normal(unit.长枪.value,8)==8,
            "committed ghost opt-out refunds only the two funded ghost rounds");
        WeaponAmmoRuntime.reconcileSkillFeatures(unit);
        check(ammo.reserve==9,"projection retry cannot duplicate the refund");
        choice(r,"impact_chain.ghost_loading",true);WeaponAmmoRuntime.reconcileSkillFeatures(unit);
        check(ammo.ghost==0&&ammo.reserve==9&&WeaponAmmoRuntime.ghostLimit(unit,"长枪")==2,"reenabling restores eligibility without granting ammunition");
        trace("SkillFeaturePolicyTest Tests Passed: "+passed);trace("SkillFeaturePolicyTest Tests Failed: "+failed);
    }
}
