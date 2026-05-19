import org.flashNight.arki.unit.*;

/**
 * JumpDerivePredicate — 派生跳跃（上挑 / 升龙拳）触发判定的纯函数
 *
 * 收口三处重复模板：
 *   - 兵器攻击路由.载入后跳转兵器攻击容器（上挑：B 键）
 *   - 空手攻击路由.__job_跨容器跳转 （升龙拳：A + B）
 *   - 空手攻击路由.载入后跳转空手攻击容器（升龙拳：A + B）
 *
 * 决策真值表：飞行浮空 / 被动技能存在 / 被动技能启用 / 按键组合命中
 * 任一条件不满足则不触发，副作用（状态改变、man.removeMovieClip、跳横移速度写回）
 * 由调用方拼装，保留生产代码本地可读性。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.JumpDerivePredicate {

    /**
     * 派生跳跃触发判定。
     *
     * @param passiveEntry    `unit.被动技能.X` 索引；undefined / null 表示未学会
     * @param isFlying        `unit.飞行浮空`；true 时禁止派生
     * @param keyComboPressed 调用方预计算的按键组合
     *                        - 上挑：  `Key.isDown(unit.B键)`
     *                        - 升龙拳：`Key.isDown(unit.A键) && Key.isDown(unit.B键)`
     */
    public static function shouldTrigger(passiveEntry:Object, isFlying:Boolean, keyComboPressed:Boolean):Boolean {
        if (isFlying === true) {
            return false;
        }
        if (passiveEntry == undefined) {
            return false;
        }
        if (!passiveEntry.启用) {
            return false;
        }
        return keyComboPressed === true;
    }
}
