import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * JumpDerivePlan — 派生跳跃决策计划层
 *
 * 把 JumpDerivePredicate.shouldTrigger 的 Boolean 输出 + 目标态字符串
 * 包成一个 plan，让 executor 完全按 plan 字段执行副作用，避免兵器 / 空手
 * 两条派生路径各自重写"跳横移速度 / 跳跃中移动速度 / 状态改变 / removeMovieClip"
 * 模板时漂移。
 *
 * 政策 vs 数据：
 *   - 政策（本类拿）：是否触发、目标态字符串
 *   - 数据（executor 拿）：unit.行走X速度（速度源固定，无政策选择）
 */
class org.flashNight.arki.unit.UnitComponent.Routing.JumpDerivePlan {

    /**
     * 纯函数：从派生输入构造计划。
     *
     * @param passiveEntry    `unit.被动技能.<上挑|升龙拳>` 索引
     * @param isFlying        `unit.飞行浮空`
     * @param keyComboPressed 调用方预计算的按键组合
     * @param targetState     触发后传给 状态改变 的字符串（"兵器跳" / "空手跳"）
     * @return plan: { triggered:Boolean, targetState:String }
     *         triggered=false 时 targetState 仍保留（便于诊断）
     */
    public static function build(passiveEntry:Object,
                                 isFlying:Boolean,
                                 keyComboPressed:Boolean,
                                 targetState:String):Object {
        return {
            triggered:   JumpDerivePredicate.shouldTrigger(passiveEntry, isFlying, keyComboPressed),
            targetState: targetState
        };
    }
}
