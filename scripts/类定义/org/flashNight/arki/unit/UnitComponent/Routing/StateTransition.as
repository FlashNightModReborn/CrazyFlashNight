import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * StateTransition — `_root.主角函数.状态改变` 的 class 化编排
 *
 * 决策层：StateTransitionCore（真值表/标签计算，纯函数）
 * 副作用层：通过 self 上的 instance method 派发（self.gotoAndStop /
 *           self.读取当前飞行状态 / self.存储当前飞行状态 / self.man.removeMovieClip）
 *           — 测试夹具用 plain object spy 同名方法即可拦截
 * 路由集成：RoutingIntent.getJobGotoOverride / executeStateTransitionJob /
 *           clearStateTransitionJob，与 producer-set 同步嵌套契约保持原行为
 *
 * 生产路径： `_root.主角函数.状态改变 = function(n) { StateTransition.apply(this, n); }`
 *
 * 测试路径： fake unit (plain object) 挂 spy gotoAndStop / 读取当前飞行状态 / ...
 *           调用 `StateTransition.apply(u, "X")` 直接走 class，跳过 `_root.主角函数` 上的 facade。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.StateTransition {

    public static function apply(self:MovieClip, newStateName:String):Void {
        // 1. snapshot 飞行状态（仅控制目标 + <攻击模式>攻击/<攻击模式>站立 切换）
        if (StateTransitionCore.shouldStoreFlyState(self._name, _root.控制目标, newStateName, self.攻击模式)) {
            self.存储当前飞行状态("状态改变");
        }

        // 2. 飞行浮空中尝试"<X>跑"：忽略本次切换
        if (StateTransitionCore.shouldEarlyReturnOnFlyingRun(self.飞行浮空, newStateName)) {
            return;
        }

        // 3. 攻击模式兜底
        self.攻击模式 = StateTransitionCore.resolveAttackMode(self.攻击模式);

        // 4. 记录旧状态
        self.旧状态 = self.状态;

        // 5. 计算 prev/new gotoLabel — 仅主角-男读 job override，避免非容器化单位多余调用
        var prevGotoLabel:String   = StateTransitionCore.resolvePrevGotoLabel(self.__stateGotoLabel, self.旧状态);
        var isHeroMale:Boolean     = (self.兵种 === StateTransitionCore.HERO_KIND_MALE);
        var jobGotoOverride:String = isHeroMale ? RoutingIntent.getJobGotoOverride(self) : null;
        var gotoLabel:String       = StateTransitionCore.resolveGotoLabel(newStateName, isHeroMale, jobGotoOverride);

        // 6. 动态 man 清理：attachMovie 动态创建的 man 不会随 gotoAndStop 自动销毁
        if (self.man && self.man.__isDynamicMan) {
            self.man.removeMovieClip();
        }

        // 7. 记录本次实际跳转的显示帧（供下次状态改变判断"从哪个显示帧离开"）
        self.__stateGotoLabel = gotoLabel;

        // 8. 真发生 gotoAndStop 才执行 job 回调；否则走兜底 clearJob
        if (StateTransitionCore.shouldTransition(self.旧状态, newStateName, prevGotoLabel, gotoLabel)) {
            self.状态 = newStateName;
            self.gotoAndStop(gotoLabel);
            self.读取当前飞行状态();
            RoutingIntent.executeStateTransitionJob(self);
        } else {
            RoutingIntent.clearStateTransitionJob(self);
        }
    }
}
