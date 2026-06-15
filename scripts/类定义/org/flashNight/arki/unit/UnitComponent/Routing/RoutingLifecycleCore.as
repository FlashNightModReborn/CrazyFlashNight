import org.flashNight.arki.unit.*;
/**
 * RoutingLifecycleCore — 路由生命周期的纯决策层
 *
 * 只接收值、返回值，不读取 `_root`、不调用 MovieClip API、不创建调度任务。
 * 生产路径由 RoutingLifecycle 写回副作用；TestLoader 可直接覆盖这里的稳定契约。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycleCore {

    public static var BONUS_MODE_BAREHAND:String = "空手";
    public static var BONUS_MODE_SKILL:String = "技能";

    public static function resolveBonusMode(isFistSkill:Boolean):String {
        return isFistSkill ? BONUS_MODE_BAREHAND : BONUS_MODE_SKILL;
    }

    public static function resolveTempY(currentTempY:Number, isFloating:Boolean, y:Number, z:Number):Number {
        if (currentTempY > 0) {
            return currentTempY;
        }
        if (isFloating === true) {
            return y;
        }
        // 与 isInAir 的 0.5 容差对齐：[z-0.5, z) 带内视为贴地（返回 0），
        // 防止定时器时序下亚像素残留把单位误判为“在空中”而触发幽灵浮空。
        if (!isNaN(z) && y < z - 0.5) {
            return y;
        }
        return 0;
    }

    public static function shouldApplyFloat(tempY:Number):Boolean {
        return (tempY > 0) == true;
    }

    public static function isInAir(y:Number, z:Number):Boolean {
        return (y < z - 0.5) == true;
    }

    public static function shouldResetOnEndCleanup(state:String, excludeState:String):Boolean {
        return state != excludeState;
    }

    public static function shouldPreserveDoubleJump(enableDoubleJump:Boolean, inAir:Boolean):Boolean {
        return enableDoubleJump == true && inAir == true;
    }

    public static function shouldStartNaturalLanding(enableDoubleJump:Boolean, inAir:Boolean):Boolean {
        return enableDoubleJump != true && inAir == true;
    }
}
