/**
 * RoutingIntent — 路由意图 API 的 class 化落点
 *
 * 目的：把 `_root.路由基础` 中已经收束稳定的状态切换作业、同帧跳转保护、
 *       容器结束写状态和诊断 dump 搬到 class 静态方法中。
 *
 * 现阶段 `_root.路由基础` 仍作为旧帧脚本 / XML 资源的兼容门面；
 * 第二阶段后续可以逐步把业务调用点改为直接调用本 class，并在 TestLoader
 * 里针对这些静态方法构造夹具。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.RoutingIntent {

    public static var LABEL_CONTAINER:String = "容器";
    public static var STATE_WEAPON:String = "兵器攻击";
    public static var STATE_WEAPON_CONTAINER:String = "兵器攻击容器";
    public static var STATE_BAREHAND:String = "空手攻击";
    public static var BIG_END_PUNCH:String = "普攻结束";
    public static var SMALL_END_WEAPON:String = "兵器攻击结束";
    public static var SMALL_END_BAREHAND:String = "空手攻击结束";

    public static function suppressOldManUnload(unit:MovieClip):Void {
        if (unit.man != undefined) {
            unit.man.onUnload = function() {};
        }
    }

    public static function markWeaponSameFrameJump(unit:MovieClip):Void {
        unit.__skipWeaponChangeFrame = _root.帧计时器.当前帧数;
    }

    public static function isWeaponSameFrameJump(unit:MovieClip):Boolean {
        return unit.__skipWeaponChangeFrame === _root.帧计时器.当前帧数;
    }

    public static function markBarehandSameFrameJump(unit:MovieClip):Void {
        unit.__skipBarehandChangeFrame = _root.帧计时器.当前帧数;
    }

    public static function isBarehandSameFrameJump(unit:MovieClip):Boolean {
        return unit.__skipBarehandChangeFrame === _root.帧计时器.当前帧数;
    }

    public static function bindContainerEndState(man:MovieClip, unit:MovieClip, smallEndState:String):Void {
        if (man == undefined) {
            return;
        }
        var prevOnUnload:Function = man.onUnload;
        var targetUnit:MovieClip = unit;
        var bigEnd:String = BIG_END_PUNCH;
        var smallEnd:String = smallEndState;
        man.onUnload = function() {
            if (prevOnUnload != undefined) {
                prevOnUnload.apply(this);
            }
            targetUnit.UpdateBigSmallState(bigEnd, smallEnd);
        };
    }

    public static function createStateTransitionJob(unit:MovieClip, gotoLabel:String, callback:Function):Object {
        var job:Object = unit.__stateTransitionJob;
        if (job == undefined) {
            job = {};
            unit.__stateTransitionJob = job;
        }
        job.gotoLabel = gotoLabel;
        job.callback = callback;
        job.arg_containerName = undefined;
        job.arg_targetLabel = undefined;
        return job;
    }

    public static function submitStateTransitionJob(unit:MovieClip, logicalState:String, forceGotoLabel:String):Void {
        if (forceGotoLabel != null && unit.__stateGotoLabel === forceGotoLabel) {
            unit.__stateGotoLabel = logicalState;
        }
        unit.状态改变(logicalState);

        var job:Object = unit.__stateTransitionJob;
        if (job != undefined && job.callback != undefined) {
            clearStateTransitionJob(unit);
        }
    }

    public static function triggerStateTransitionJob(unit:MovieClip, logicalState:String, gotoLabel:String, callback:Function, forceGotoLabel:String):Object {
        var job:Object = createStateTransitionJob(unit, gotoLabel, callback);
        submitStateTransitionJob(unit, logicalState, forceGotoLabel);
        return job;
    }

    public static function executeStateTransitionJob(unit:MovieClip):Void {
        var job:Object = unit.__stateTransitionJob;
        if (job == undefined || job.callback == undefined) {
            return;
        }
        var cb:Function = job.callback;
        job.callback = undefined;
        job.gotoLabel = undefined;
        cb(unit);
    }

    public static function getJobGotoOverride(unit:MovieClip):String {
        var job:Object = unit.__stateTransitionJob;
        if (job == undefined || job.gotoLabel == undefined) {
            return null;
        }
        return job.gotoLabel;
    }

    public static function clearStateTransitionJob(unit:MovieClip):Void {
        var job:Object = unit.__stateTransitionJob;
        if (job != undefined) {
            job.callback = undefined;
            job.gotoLabel = undefined;
            job.arg_containerName = undefined;
            job.arg_targetLabel = undefined;
        }
    }

    public static function dumpState(unit:MovieClip):String {
        if (unit == undefined) {
            return "[路由dump] unit=undefined";
        }
        var s:String = "[路由dump]";
        s += " 帧=" + _root.帧计时器.当前帧数;
        s += " name=" + unit._name;
        s += " 状态=" + unit.状态;
        s += " 旧状态=" + unit.旧状态;
        s += " __stateGotoLabel=" + unit.__stateGotoLabel;
        s += " 兵器攻击名=" + unit.兵器攻击名;
        s += " 空手攻击名=" + unit.空手攻击名;
        s += " 技能名=" + unit.技能名;
        s += " __skipWeapon=" + unit.__skipWeaponChangeFrame;
        s += " __skipBare=" + unit.__skipBarehandChangeFrame;

        var job:Object = unit.__stateTransitionJob;
        if (job == undefined) {
            s += " job=undefined";
        } else {
            s += " job{goto=" + job.gotoLabel
              +  " cb=" + (job.callback != undefined)
              +  " arg_cn=" + job.arg_containerName
              +  " arg_tl=" + job.arg_targetLabel + "}";
        }

        s += " 浮空=" + unit.浮空;
        s += " temp_y=" + unit.temp_y;
        s += " _y=" + unit._y;
        s += " Z=" + unit.Z轴坐标;
        s += " 技能浮空=" + unit.技能浮空;
        s += " 战技浮空=" + unit.战技浮空;
        s += " __preserve=" + unit.__preserveFloatFlagOnUnload;

        var hasMan:Boolean = (unit.man != undefined);
        s += " man=" + hasMan;
        if (hasMan) {
            s += " man.__isDynamic=" + unit.man.__isDynamicMan;
        } else {
            s += " man.__isDynamic=undefined";
        }
        return s;
    }
}
