import org.flashNight.arki.unit.Action.Huofeng.*;

/** 火凤只开放刀剑通用派生，主动技能继续走现役学习/MP/冷却消费者。 */
class org.flashNight.arki.unit.Action.Huofeng.HuofengInput {
    public static function weaponSkillHeld():Boolean { return Key.isDown(_root.武器技能键); }
    public static function locked(unit:Object):Boolean {
        return unit.__huofengNirvana!=null && !unit.__huofengNirvana.cancelled;
    }

    public static function tryCancel(unit:MovieClip,action:Object):Boolean {
        if (!HuofengRules.profileActive(unit) || locked(unit)) return false;
        var released:Number=_root.技能函数.冷兵器主动技能搓招(unit,6,30,false);
        if (released<0) return true;
        if (released>0) {
            HuofengAction.cancel(action.owner,action,false);
            return true;
        }
        // AS2 现役派生以其派生被动“启用”为权威，不用 XML 上游等级代替学习状态。
        var names:Array=["使用蓄力重劈","使用剑气释放","使用贯穿突刺","使用月光斩"];
        for(var i:Number=0;i<names.length;i++) {
            var handler:Function=_root.技能函数[names[i]];
            if (handler!=undefined && handler.apply(unit.man)>0) {
                HuofengAction.cancel(action.owner,action,false);
                return true;
            }
        }
        return false;
    }

    public static function allowedPassive(name:String):Boolean {
        return name==="剑气释放" || name==="贯穿突刺" || name==="月光斩" || name==="蓄力重劈";
    }

    public static function skillPermission(unit:MovieClip,skill:Object):Boolean {
        return !locked(unit) && unit.__huofeng!=null && unit.__huofeng.canEnterSpin();
    }
    public static function releaseSpin(unit:MovieClip,skill:Object):Boolean {
        return unit.__huofeng!=null && unit.__huofeng.startSpin();
    }
    public static function install():Void {
        HuofengNative.install();
        if (_root.主动战技函数.空手==undefined) _root.主动战技函数.空手={};
        _root.主动战技函数.空手.焰链回旋={原子释放:true,固定资源消耗:true,释放许可判定:HuofengInput.skillPermission,释放:HuofengInput.releaseSpin};
    }
}
