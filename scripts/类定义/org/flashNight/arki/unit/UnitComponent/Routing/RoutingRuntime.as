import org.flashNight.arki.unit.*;
import org.flashNight.neur.ScheduleTimer.*;

/**
 * RoutingRuntime — 路由生命周期的外部副作用适配层
 *
 * 生产环境默认委派到 `_root.空中控制器` 与 EnhancedCooldownWheel。
 * TestLoader 可注入 mock air/scheduler，避免依赖真实帧时间推进。
 *
 * ════════════════════════════════════════════════════════════════════
 * FROZEN ADAPTER SURFACE — 添加方法需 review，业务代码禁止绕过
 * ════════════════════════════════════════════════════════════════════
 * 本类是 Routing/* 触达 `_root.空中控制器` 的 ONLY 通道。规则：
 *
 * 1) RoutingLifecycle / StateTransition / 任何 Routing/ 下的 class 都
 *    **不得直接读写 `_root.空中控制器.xxx`**。一律走 RoutingRuntime.*。
 *
 * 2) 业务侧（玩家模板迁移.as / 路由 .as / asLoader 帧脚本）需要新的空中控制器
 *    交互时，**只能从下面这张表扩**，不能在调用点绕回 _root。新加 adapter
 *    需要：(a) 此处文档加一行；(b) RoutingRuntime 加 setXxxForTest /
 *    clearXxxForTest 注入接口（如已通过 getAirController 复用则不必）。
 *
 * 3) `_root.空中控制器` 本体何时重构、是否拆类，与本表无关 — 本类已抹平
 *    测试需求，本体改造不再是路由系统稳固的硬阻塞（user 2026-05-18 决策）。
 *
 * 当前 frozen surface（v2，2026-05-19）：
 *   removeTask(taskID)                                  → EnhancedCooldownWheel
 *   closeSkillFloat(unit)                               → 关闭技能浮空
 *   closeNaturalLanding(unit)                           → 关闭自然落地
 *   closeJumpFloat(unit)                                → 关闭跳跃浮空
 *   enableSkillFloat(unit, floatFlag, man)              → 启用技能浮空
 *   enableNaturalLanding(unit)                          → 启用自然落地
 *   attachMovie(parent, linkage, name, depth, initObj)  → MovieClip.attachMovie
 *
 * 测试侧 mock 接口：
 *   setAirControllerForTest    / clearAirControllerForTest
 *   setSchedulerForTest        / clearSchedulerForTest
 *   setAttachMovieAdapterForTest / clearAttachMovieAdapterForTest
 */
class org.flashNight.arki.unit.UnitComponent.Routing.RoutingRuntime {

    private static var __airController:Object;
    private static var __scheduler:Object;
    private static var __attachMovieAdapter:Object;

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

    public static function setAttachMovieAdapterForTest(adapter:Object):Void {
        __attachMovieAdapter = adapter;
    }

    public static function clearAttachMovieAdapterForTest():Void {
        __attachMovieAdapter = undefined;
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

    /**
     * 低层 attachMovie adapter — Routing/* 调用 parent.attachMovie 的统一入口。
     *
     * 生产路径：parent.attachMovie(linkage, name, depth, initObj)（原生 AS2 同步
     * enumerate + copy initObject own properties 到新 MovieClip）。
     * 测试路径：若 __attachMovieAdapter 已注入，转发到 adapter.attachMovie(...)
     * 由 mock 决定返回 MockMovieClip 还是 undefined（模拟 missing symbol）。
     *
     * 返回 undefined 表示 linkage 不存在；调用方需自决 fallback
     * （见 ContainerSpec.getMissingFallback 与高层 ContainerAttachAction）。
     *
     * 注：parent / adapter 走 untyped 路径，方便测试侧传 MockMovieClip / spy
     * object 而无需强制做 MovieClip 子类化。
     */
    public static function attachMovie(parent, linkage:String, name:String, depth:Number, initObj:Object):MovieClip {
        var adapter = __attachMovieAdapter;
        if (adapter != undefined && adapter.attachMovie != undefined) {
            return adapter.attachMovie(parent, linkage, name, depth, initObj);
        }
        return parent.attachMovie(linkage, name, depth, initObj);
    }
}
