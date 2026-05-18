import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.UnitComponent.Routing.*;
import org.flashNight.neur.ScheduleTimer.*;

/**
 * RoutingLifecycle — 路由生命周期 API 的 class 化落点
 *
 * 负责技能/战技/普攻容器共用的动画完毕、浮空、结束清理与通用 initObject。
 * `_root.路由基础` 暂时保留为兼容门面，生产路由逐步直连本 class。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycle {

    public static function preparePoseAndBonus(unit:MovieClip):Void {
        unit.格斗架势 = true;
        if (HeroUtil.isFistSkill(unit.技能名)) {
            unit.根据模式重新读取武器加成("空手");
        } else {
            unit.根据模式重新读取武器加成("技能");
        }
    }

    public static function ensureTempY(unit:MovieClip):Void {
        if (unit.temp_y > 0) {
            return;
        }
        if (unit.浮空 === true) {
            unit.temp_y = unit._y;
            return;
        }
        if (!isNaN(unit.Z轴坐标) && unit._y < unit.Z轴坐标) {
            unit.temp_y = unit._y;
            return;
        }
        unit.temp_y = 0;
    }

    public static function bindMovement(man:MovieClip):Void {
        man.攻击时移动 = _root.技能函数.攻击时移动;
        man.攻击时后退移动 = _root.技能函数.攻击时移动;
        man.攻击时按键四向移动 = _root.技能函数.攻击时按键四向移动;
        man.攻击时可改变移动方向 = _root.技能函数.攻击时可改变移动方向;
        man.攻击时可斜向改变移动方向 = _root.技能函数.攻击时可斜向改变移动方向;
        man.攻击时斜向移动 = _root.技能函数.攻击时斜向移动;
        man.攻击时可斜向改变移动方向2 = _root.技能函数.攻击时可斜向改变移动方向2;
        man.获取移动方向 = _root.技能函数.获取移动方向;
    }

    public static function buildPublicContainerInit(container:MovieClip):Object {
        return ContainerInitScratch.getPublic(container);
    }

    public static function bindEndCleanup(clip:MovieClip, unit:MovieClip, excludeState:String, endBigState:String, floatFlag:String):Void {
        var prevOnUnload:Function = clip.onUnload;
        var targetUnit:MovieClip = unit;
        var excluded:String = excludeState;
        var endState:String = endBigState;
        var flag:String = floatFlag;
        clip.onUnload = function() {
            if (prevOnUnload != undefined) {
                prevOnUnload.apply(this);
            }
            targetUnit.无敌 = false;
            var needReset:Boolean = (targetUnit.状态 != excluded);
            if (needReset) {
                targetUnit.temp_y = 0;
            }
            targetUnit.UpdateBigSmallState(endState, endState);
            targetUnit.根据模式重新读取武器加成(targetUnit.攻击模式);
            if (needReset) {
                if (targetUnit.__preserveFloatFlagOnUnload == flag) {
                    delete targetUnit.__preserveFloatFlagOnUnload;
                } else {
                    targetUnit[flag] = false;
                }
            }
            if (targetUnit.dispatcher != undefined && targetUnit.dispatcher != null) {
                targetUnit.dispatcher.publish("skillEnd", targetUnit);
            }
        };
    }

    public static function handleFloat(man:MovieClip, unit:MovieClip, floatFlag:String):Void {
        man.落地 = true;
        if (unit.temp_y <= 0) {
            return;
        }

        unit[floatFlag] = true;
        unit._y = unit.temp_y;
        unit.起始Y = unit.Z轴坐标;
        man.落地 = false;
        unit.浮空 = true;

        clearSkillFloatTask(unit);

        if (_root.空中控制器 != undefined) {
            _root.空中控制器.关闭自然落地(unit);
            _root.空中控制器.关闭跳跃浮空(unit);
            _root.空中控制器.启用技能浮空(unit, floatFlag, man);
        }
    }

    public static function clearSkillFloatTask(unit:MovieClip):Void {
        if (_root.空中控制器 != undefined) {
            _root.空中控制器.关闭技能浮空(unit);
        }
        if (unit.__技能浮空任务ID != null) {
            EnhancedCooldownWheel.I().removeTask(unit.__技能浮空任务ID);
            unit.__技能浮空任务ID = null;
        }
    }

    public static function clearNaturalLandingTask(unit:MovieClip):Void {
        if (_root.空中控制器 != undefined) {
            _root.空中控制器.关闭自然落地(unit);
        }
        if (unit.__自然落地任务ID != null) {
            EnhancedCooldownWheel.I().removeTask(unit.__自然落地任务ID);
            unit.__自然落地任务ID = null;
        }
    }

    public static function startNaturalLandingTask(unit:MovieClip):Void {
        clearNaturalLandingTask(unit);
        if (_root.空中控制器 != undefined) {
            _root.空中控制器.启用自然落地(unit);
        }
    }

    public static function completeAnimation(man:MovieClip, unit:MovieClip, enableDoubleJump:Boolean):Void {
        clearSkillFloatTask(unit);

        var inAir:Boolean = unit._y < unit.Z轴坐标 - 0.5;
        if (enableDoubleJump && inAir) {
            unit.技能浮空 = true;
            unit.__preserveFloatFlagOnUnload = "技能浮空";
        }

        unit.动画完毕();
        man.removeMovieClip();

        if (!enableDoubleJump && inAir) {
            startNaturalLandingTask(unit);
        }
    }
}
