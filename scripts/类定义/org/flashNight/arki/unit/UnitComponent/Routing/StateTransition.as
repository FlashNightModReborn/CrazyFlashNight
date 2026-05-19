import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * StateTransition — `_root.主角函数.状态改变` 的 class 化编排
 *
 * 三层结构：
 *   StateTransitionCore   — 6 真值表纯函数
 *   StateTransitionPlan   — snapshot(self) + build(snapshot, newStateName) 纯函数决策
 *   StateTransition.apply — 拿 plan 执行副作用，是唯一持有 self 写权限的层
 *
 * 生产路径： `_root.主角函数.状态改变 = function(n) { StateTransition.apply(this, n); }`
 *
 * 测试路径：plain object spy + StateTransition.apply(u, "X")，跳过 _root.主角函数 facade。
 * 端到端契约（producer-set → 状态改变 → gotoAndStop → executeStateTransitionJob → callback）
 * 保持原行为不变，由 StateTransitionTest 覆盖。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.StateTransition {

    public static function apply(self:MovieClip, newStateName:String):Void {
        // 1. 一次性 snapshot
        var snap:Object = StateTransitionPlan.snapshot(self);

        // 2. 纯函数 buildPlan
        var plan:Object = StateTransitionPlan.build(snap, newStateName);

        // 3. executor — 唯一持有 self 写权限和外部副作用调用权限的代码段
        if (plan.storeFlyState) {
            self.存储当前飞行状态("状态改变");
        }
        if (plan.earlyReturn) {
            return;
        }

        self.攻击模式 = plan.attackMode;
        self.旧状态   = plan.oldState;

        if (plan.removeDynamicMan) {
            self.man.removeMovieClip();
        }

        self.__stateGotoLabel = plan.gotoLabel;

        if (plan.transition) {
            self.状态 = plan.newLogicalState;
            self.gotoAndStop(plan.gotoLabel);
            self.读取当前飞行状态();
            RoutingIntent.executeStateTransitionJob(self);
        } else {
            RoutingIntent.clearStateTransitionJob(self);
        }
    }
}
