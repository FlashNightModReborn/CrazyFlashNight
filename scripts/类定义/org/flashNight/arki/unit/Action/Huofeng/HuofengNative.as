import org.flashNight.arki.unit.Action.Huofeng.*;
import org.flashNight.arki.unit.UnitComponent.Routing.*;

/** 原生冷兵器动作只换装配和进攻快照；学习、资源、时序仍由原消费者负责。 */
class org.flashNight.arki.unit.Action.Huofeng.HuofengNative {
    public static function isSkill(name:String):Boolean {
        return name==="迅斩" || name==="瞬步斩" || name==="凶斩" || name==="火舞旋风" || name==="拔刀术";
    }
    public static function linkage(unit:Object,kind:String,name:String,original:String):String {
        if (!HuofengRules.profileActive(unit)) return original;
        if ((kind==="skill" && isSkill(name)) || (kind==="weapon" && HuofengInput.allowedPassive(name))) {
            return "火凤套装_冷兵器_"+name;
        }
        return original;
    }
    public static function snapshot(unit:Object):Object {
        var attrs:Object={};
        HuofengCombat.primaryAttributes(unit,attrs);
        return {owner:unit.__huofeng,power:HuofengRules.liveBladePower(unit),force:HuofengRules.numberOrZero(unit.内力),
            mpPower:HuofengRules.numberOrZero(unit.mp攻击加成),damage:HuofengRules.numberOrZero(unit.伤害加成),
            attributes:attrs,token:{owner:unit.__huofeng,cancelled:false,requiresProfile:true}};
    }
    public static function force(unit:Object):Number {
        var s:Object=unit.man.__huofengColdSnapshot;
        return s!=null ? s.force : unit.内力;
    }
    public static function mpPower(unit:Object):Number {
        var s:Object=unit.man.__huofengColdSnapshot;
        return s!=null ? s.mpPower : unit.mp攻击加成;
    }
    public static function actionType(unit:Object):String { return HuofengRules.profileActive(unit) ? "刀剑" : unit.兵器动作类型; }

    public static function initializeBullet(emitter:MovieClip):Object {
        var b:Object=_root.子弹属性初始化(emitter);
        var unit:MovieClip=emitter;
        for(var i:Number=0;i<8 && unit!=undefined;i++) {
            if (unit.__huofeng!=undefined) break;
            unit=unit._parent;
        }
        if (unit!=undefined && HuofengRules.profileActive(unit)) prepareBullet(unit,b);
        return b;
    }
    public static function ownsColdAction(unit:Object):Boolean {
        var s:Object=unit.man.__huofengColdSnapshot;
        return HuofengRules.profileActive(unit) && s!=null && s.owner===unit.__huofeng && !s.token.cancelled;
    }
    public static function prepareBullet(unit:Object,b:Object):Void {
        var s:Object=unit.man.__huofengColdSnapshot;
        if (s==null || s.owner!==unit.__huofeng) return;
        for(var key:String in s.attributes) b[key]=s.attributes[key];
        // Native formulas add G in DamageCalculator; freeze that same one G.
        b.__huofengDamageSnapshot=s.damage;
        // Native blades and projectile timelines own their own contact windows.
        // Retain cancellation, without borrowing the custom hammer's spatial dedupe.
        b.__huofengPulse={action:s.token};
    }
    public static function cancel(unit:MovieClip,recover:Boolean):Void {
        var man:MovieClip=unit.man;
        var s:Object=man.__huofengColdSnapshot;
        if (s==null || s.owner!==unit.__huofeng) {
            man=unit.getInstanceAtDepth(0);s=man.__huofengColdSnapshot;
        }
        if (s==null || s.owner!==unit.__huofeng || man._parent!==unit) return;
        s.token.cancelled=true;
        if (!(unit.hp>0) || man!==unit.man) HuofengAction.retireMan(man);
        else if (recover) RoutingLifecycle.recoverMissingSkillContainer(unit);
    }
    public static function routeJump(unit:MovieClip,state:String):Boolean {
        if ((state!=="空手跳" && state!=="兵器跳") || !HuofengRules.profileActive(unit) || unit.__huofengJumpPending) return false;
        unit.__huofeng.cancelAction(false);
        unit.__huofengJumpPending=true;
        RoutingIntent.suppressOldManUnload(unit);
        RoutingIntent.triggerStateTransitionJob(unit,"空手跳","容器",HuofengNative.attachJump,"容器");
        return true;
    }
    public static function attachJump(unit:MovieClip):Void {
        delete unit.__huofengJumpPending;
        if (!HuofengRules.profileActive(unit)) { RoutingLifecycle.recoverMissingSkillContainer(unit);return; }
        var init:Object=ContainerInitScratch.getWeapon(unit.container);
        init.__huofengColdSnapshot=snapshot(unit);
        var man:MovieClip=RoutingRuntime.attachMovie(unit,"火凤套装_冷兵器_跳跃","man",0,init);
        delete init.__huofengColdSnapshot;
        if (man==undefined) RoutingLifecycle.recoverMissingSkillContainer(unit);
    }
    public static function install():Void {
        _root.火凤套装接口={锋利度:HuofengRules.bladePower,空手补项:HuofengRules.unarmedTerm,
            内力:HuofengNative.force,气伤:HuofengNative.mpPower,动作类型:HuofengNative.actionType,
            子弹初始化:HuofengNative.initializeBullet,冻结子弹:HuofengNative.prepareBullet};
    }
}
