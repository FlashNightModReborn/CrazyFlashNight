import org.flashNight.arki.unit.*;

/**
 * StateTransitionCore — unit.状态改变 的纯决策层
 *
 * 把 `_root.主角函数.状态改变` 中的真值表与标签计算抽成纯函数。
 * 完全不读 `_root`、不调 MovieClip API、不写 unit 字段；Phase β 的
 * StateTransition.apply 编排会用这层做决策，再把结果回写到 self。
 *
 * 接受方向：所有输入必须是值（已经从 unit 属性读出），输出为值或简单 Boolean。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.StateTransitionCore {

    public static var CONTAINER_LABEL:String        = "容器";
    public static var DEFAULT_ATTACK_MODE:String    = "空手";
    public static var ALIAS_SKILL:String            = "技能";
    public static var ALIAS_BATTLE_SKILL:String     = "战技";
    public static var ALIAS_WEAPON_CONTAINER:String = "兵器攻击容器";
    public static var HERO_KIND_MALE:String         = "主角-男";

    /**
     * 是否需要在 gotoAndStop 前 snapshot 飞行状态。
     * 仅控制目标在切换到"<攻击模式>攻击 / <攻击模式>站立"时调用 存储当前飞行状态。
     */
    public static function shouldStoreFlyState(name:String, controlTarget:String, newStateName:String, attackMode:String):Boolean {
        if (name !== controlTarget) {
            return false;
        }
        return newStateName === attackMode + "攻击"
            || newStateName === attackMode + "站立";
    }

    /**
     * 飞行浮空中尝试切到"<X>跑"系列状态：忽略本次状态改变。
     * 避免飞行中地面跑动状态意外触发。
     */
    public static function shouldEarlyReturnOnFlyingRun(isFlying:Boolean, newStateName:String):Boolean {
        return isFlying === true && newStateName.indexOf("跑") > -1;
    }

    /**
     * 攻击模式兜底。 `!self.攻击模式` 视 undefined/null/空字符串/0 为缺省。
     */
    public static function resolveAttackMode(currentAttackMode:String):String {
        if (!currentAttackMode) {
            return DEFAULT_ATTACK_MODE;
        }
        return currentAttackMode;
    }

    /**
     * 上次实际跳转的显示帧。 __stateGotoLabel 未设过时退回 oldState（兼容旧轨迹）。
     */
    public static function resolvePrevGotoLabel(stateGotoLabel:String, oldState:String):String {
        if (stateGotoLabel != undefined) {
            return stateGotoLabel;
        }
        return oldState;
    }

    /**
     * 计算本次 gotoAndStop 实际使用的帧标签。
     * 仅主角-男容器化场景启用别名 + job 覆盖；其他单位/兵种直传 newStateName。
     *
     * 优先级： jobGotoOverride > 容器化别名 > newStateName。
     */
    public static function resolveGotoLabel(newStateName:String, isHeroMale:Boolean, jobGotoOverride:String):String {
        var label:String = newStateName;
        if (isHeroMale === true) {
            if (newStateName === ALIAS_SKILL
             || newStateName === ALIAS_BATTLE_SKILL
             || newStateName === ALIAS_WEAPON_CONTAINER) {
                label = CONTAINER_LABEL;
            }
            if (jobGotoOverride != null) {
                label = jobGotoOverride;
            }
        }
        return label;
    }

    /**
     * 是否真正需要 gotoAndStop（逻辑状态变 or 显示帧变）。
     * 否则走兜底 clearStateTransitionJob 路径，避免 callback 残留到下次状态改变。
     */
    public static function shouldTransition(oldState:String, newLogicalState:String, prevGotoLabel:String, newGotoLabel:String):Boolean {
        return oldState != newLogicalState || prevGotoLabel != newGotoLabel;
    }
}
