import org.flashNight.arki.unit.*;
import org.flashNight.neur.ScheduleTimer.*;

/**
 * RoutingRuntime — 路由生命周期的外部副作用适配层
 *
 * 生产环境默认委派到 `_root.空中控制器` 与 EnhancedCooldownWheel。
 * TestLoader 可注入 mock air/scheduler，避免依赖真实帧时间推进。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.RoutingRuntime {

    private static var __airController:Object;
    private static var __scheduler:Object;

    public static function setAirControllerForTest(air:Object):Void {
        __airController = air;
    }

    public static function clearAirControllerForTest():Void {
        __airController = undefined;
    }

    public static function setSchedulerForTest(scheduler:Object):Void {
        __scheduler = scheduler;
    }

    public static function clearSchedulerForTest():Void {
        __scheduler = undefined;
    }

    private static function getAirController():Object {
        if (__airController !== undefined) {
            return __airController;
        }
        return _root.空中控制器;
    }

    public static function removeTask(taskID:Number):Void {
        var scheduler:Object = __scheduler;
        if (scheduler != undefined && scheduler.removeTask != undefined) {
            scheduler.removeTask(taskID);
            return;
        }
        EnhancedCooldownWheel.I().removeTask(taskID);
    }

    public static function closeSkillFloat(unit:MovieClip):Void {
        var air:Object = getAirController();
        if (air != undefined && air.关闭技能浮空 != undefined) {
            air.关闭技能浮空(unit);
        }
    }

    public static function closeNaturalLanding(unit:MovieClip):Void {
        var air:Object = getAirController();
        if (air != undefined && air.关闭自然落地 != undefined) {
            air.关闭自然落地(unit);
        }
    }

    public static function closeJumpFloat(unit:MovieClip):Void {
        var air:Object = getAirController();
        if (air != undefined && air.关闭跳跃浮空 != undefined) {
            air.关闭跳跃浮空(unit);
        }
    }

    public static function enableSkillFloat(unit:MovieClip, floatFlag:String, man:MovieClip):Void {
        var air:Object = getAirController();
        if (air != undefined && air.启用技能浮空 != undefined) {
            air.启用技能浮空(unit, floatFlag, man);
        }
    }

    public static function enableNaturalLanding(unit:MovieClip):Void {
        var air:Object = getAirController();
        if (air != undefined && air.启用自然落地 != undefined) {
            air.启用自然落地(unit);
        }
    }
}
