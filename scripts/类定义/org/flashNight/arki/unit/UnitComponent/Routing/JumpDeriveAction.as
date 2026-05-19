import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * JumpDeriveAction — 派生跳跃执行层
 *
 * 接 JumpDerivePlan 的 plan，把 3 个调用点重复的副作用模板收成一份。
 * 入口：tryDerive(unit, man, passiveEntry, keyComboPressed, targetState):Boolean
 *       一行 if-return 即可替换原 4 行内联模板。
 *
 * 副作用清单（统一在 execute 里）：
 *   1) unit.跳横移速度       = unit.行走X速度
 *   2) unit.跳跃中移动速度   = unit.行走X速度
 *   3) unit.状态改变(plan.targetState)        — 走 _root.主角函数.状态改变 facade
 *   4) man.removeMovieClip()
 *
 * 调用方仍负责自己 `return undefined / return` 跳出本帧 — 不同路由文件签名不同，
 * 本类不假设调用栈的具体 return 类型。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.JumpDeriveAction {

    /**
     * 按 plan 执行派生跳跃副作用。
     * @return triggered — 与 plan.triggered 同；调用方按此决定是否提前 return
     */
    public static function execute(unit:MovieClip, man:MovieClip, plan:Object):Boolean {
        if (!plan.triggered) {
            return false;
        }
        unit.跳横移速度       = unit.行走X速度;
        unit.跳跃中移动速度   = unit.行走X速度;
        unit.状态改变(plan.targetState);
        man.removeMovieClip();
        return true;
    }

    /**
     * 调用方一行入口：构造 plan + 执行。
     * 兵器上挑 / 空手升龙拳 ×2 三处的 if 体收成单次调用。
     */
    public static function tryDerive(unit:MovieClip,
                                     man:MovieClip,
                                     passiveEntry:Object,
                                     keyComboPressed:Boolean,
                                     targetState:String):Boolean {
        var plan:Object = JumpDerivePlan.build(
            passiveEntry, unit.飞行浮空, keyComboPressed, targetState
        );
        return execute(unit, man, plan);
    }
}
